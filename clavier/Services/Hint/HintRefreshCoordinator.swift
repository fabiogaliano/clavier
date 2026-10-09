//
//  HintRefreshCoordinator.swift
//  clavier
//
//  Async lifecycle for the hint refresh that follows a click.
//
//  Samples the UI on the schedule chosen by `HintRefreshSettler` until it
//  settles (or the settle window runs out), then reports whether anything
//  changed.  The decision logic lives in the settler; this type only owns the
//  sleeping, cancellation, and logging.
//
//  Depends on `HintRefreshTimingPolicy` rather than `AppTimingRegistry.shared`
//  directly, so timing can be injected in tests.
//
//  Conforms to `ModeCoordinator` marker protocol (P4-S1).
//

import Foundation
import AppKit
import os

// MARK: - Coordinator

@MainActor
final class HintRefreshCoordinator: ModeCoordinator {

    private let timingPolicy: HintRefreshTimingPolicy
    private let sleep: @MainActor (TimeInterval) async throws -> Void
    private let now: @MainActor () -> CFAbsoluteTime

    /// Retained so `cancelPending()` can cancel an in-flight cycle.
    private var refreshTask: Task<Void, Never>?

    /// `sleep` and `now` are injectable so tests can drive the sampling
    /// schedule on a virtual clock instead of waiting out real delays.
    init(
        timingPolicy: HintRefreshTimingPolicy,
        sleep: @escaping @MainActor (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
        now: @escaping @MainActor () -> CFAbsoluteTime = CFAbsoluteTimeGetCurrent
    ) {
        self.timingPolicy = timingPolicy
        self.sleep = sleep
        self.now = now
    }

    // MARK: - Public API

    /// Cancel any in-flight refresh cycle.  Call when the mode deactivates or
    /// when a new click / manual refresh supersedes the current one.
    func cancelPending() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Sample the UI after a click until it settles.
    ///
    /// - Parameters:
    ///   - baseline:   Signature of the hints on screen when the click happened.
    ///   - sample:     Re-discovers (and re-renders if needed) on the main actor,
    ///                 returning the new signature, or nil to stop sampling
    ///                 (session ended, or the user started typing).
    ///   - completion: Called once with the outcome, unless sampling was
    ///                 stopped or cancelled first.
    func scheduleRefresh(
        baseline: HintTreeSignature,
        sample: @escaping @MainActor () -> HintTreeSignature?,
        completion: @escaping @MainActor (HintRefreshOutcome) -> Void
    ) {
        cancelPending()

        let app = NSWorkspace.shared.frontmostApplication
        let delays = timingPolicy.refreshDelays(for: app?.bundleIdentifier) ?? .standard
        let appName = app?.localizedName ?? "unknown"
        Logger.hintMode.debug("refresh: app=\(appName, privacy: .public) first=\(Int(delays.optimistic * 1000), privacy: .public)ms window=\(Int(delays.settleWindow * 1000), privacy: .public)ms")

        let sleep = self.sleep
        let now = self.now
        refreshTask = Task { @MainActor in
            var settler = HintRefreshSettler(baseline: baseline, delays: delays)
            let start = now()
            var wait = settler.firstDelay
            var samples = 0

            while true {
                do {
                    try await sleep(wait)
                } catch {
                    return // Cancelled — a newer click, manual refresh, or deactivation.
                }
                guard !Task.isCancelled, let signature = sample() else { return }
                samples += 1

                let elapsed = now() - start
                switch settler.observe(signature, elapsed: elapsed) {
                case .sampleAgain(let next):
                    wait = next
                case .finished(let outcome):
                    Logger.hintMode.debug("refresh: \(String(describing: outcome), privacy: .public) after \(samples, privacy: .public) samples, \(Int(elapsed * 1000), privacy: .public)ms")
                    completion(outcome)
                    return
                }
            }
        }
    }
}
