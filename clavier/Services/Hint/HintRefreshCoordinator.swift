//
//  HintRefreshCoordinator.swift
//  clavier
//
//  Async lifecycle for continuous-mode hint refresh after a click.
//
//  Owns the double-refresh pattern:
//  1. Optimistic refresh after T ms (fast path — UI may already have changed).
//  2. Fallback refresh after T+Δ ms if the element count didn't change.
//  3. Both refreshes are cancelled automatically when a new session starts
//     (via `cancelPending()`).
//
//  Depends on `HintRefreshTimingPolicy` (from P4-S1) rather than
//  `AppTimingRegistry.shared` directly, so timing can be injected in tests.
//
//  Conforms to `ModeCoordinator` marker protocol (P4-S1).
//

import Foundation
import AppKit
import os

// MARK: - Coordinator

/// Coordinates the optimistic + fallback refresh cycle after a click in
/// continuous hint mode.
///
/// The controller calls `scheduleRefresh(previousCount:onRefresh:)` after a
/// click.  The coordinator fires `onRefresh` twice on the main actor — once
/// after the optimistic delay and once after the fallback delay if needed.
/// Calling `cancelPending()` before either fires suppresses both.
@MainActor
final class HintRefreshCoordinator: ModeCoordinator {

    private let timingPolicy: HintRefreshTimingPolicy

    private static let defaultOptimisticDelay: TimeInterval = 0.050
    private static let defaultFallbackDelay: TimeInterval = 0.100

    /// Retained so `cancelPending()` can cancel an in-flight cycle.
    private var refreshTask: Task<Void, Never>?

    private var refreshStartTime: CFAbsoluteTime = 0

    init(timingPolicy: HintRefreshTimingPolicy) {
        self.timingPolicy = timingPolicy
    }

    // MARK: - Public API

    /// Cancel any in-flight refresh cycle.  Call when the mode deactivates or
    /// when a new session replaces the previous one.
    func cancelPending() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Schedule the optimistic + fallback refresh cycle.
    ///
    /// - Parameters:
    ///   - previousCount:  Element count before the click.  Used to decide
    ///                     whether the optimistic result shows a UI change.
    ///   - onRefresh:      Called on the main actor to run a hint refresh query.
    ///                     Returns the new element count so the coordinator can
    ///                     determine whether a UI change occurred.
    func scheduleRefresh(
        previousCount: Int,
        onRefresh: @escaping @MainActor () -> Int
    ) {
        cancelPending()

        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let delays = timingPolicy.refreshDelays(for: bundleId)

        let optimisticDelay = delays?.optimistic ?? HintRefreshCoordinator.defaultOptimisticDelay
        let fallbackDelay = delays?.fallback ?? HintRefreshCoordinator.defaultFallbackDelay

        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
        Logger.hintMode.debug("continuous: app=\(appName, privacy: .public) optimistic=\(Int(optimisticDelay * 1000), privacy: .public)ms fallback=\(Int(fallbackDelay * 1000), privacy: .public)ms")

        refreshStartTime = CFAbsoluteTimeGetCurrent()

        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .seconds(optimisticDelay))
                guard !Task.isCancelled else { return }

                let optimisticTime = CFAbsoluteTimeGetCurrent()
                Logger.hintMode.debug("continuous: optimistic refresh at +\(Int((optimisticTime - self.refreshStartTime) * 1000), privacy: .public)ms")

                let newCount = onRefresh()
                let uiChanged = newCount != previousCount

                if uiChanged {
                    Logger.hintMode.debug("continuous: UI changed (\(newCount, privacy: .public) elements)")
                    return
                }

                Logger.hintMode.debug("continuous: UI unchanged (still \(newCount, privacy: .public) elements)")
                try await Task.sleep(for: .seconds(fallbackDelay))
                guard !Task.isCancelled else { return }

                let fallbackTime = CFAbsoluteTimeGetCurrent()
                Logger.hintMode.debug("continuous: fallback refresh at +\(Int((fallbackTime - self.refreshStartTime) * 1000), privacy: .public)ms")

                _ = onRefresh()
            } catch {
                // Task cancelled — mode deactivated during refresh window
            }
        }
    }
}
