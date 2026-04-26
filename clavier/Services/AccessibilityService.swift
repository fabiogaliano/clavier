//
//  AccessibilityService.swift
//  clavier
//
//  Facade for clickable-element discovery.  Resolves the frontmost app,
//  enumerates its windows, computes per-window visibility clipping, and
//  delegates recursion to `ClickableElementWalker`.  Dedup policy and
//  role-based heuristics live in their own policy types.
//

import Foundation
import AppKit
import os

@MainActor
class AccessibilityService {

    static let shared = AccessibilityService()

    private let walker = ClickableElementWalker()

    /// Entry point for hint discovery.  Produces the collapsed, deduped
    /// list of clickable elements in the frontmost application.
    ///
    /// `recorder` is nil on the production path.  Debug mode
    /// (`HintModeController.toggleDebugHintMode`) passes a non-nil
    /// recorder to capture per-node trace events that are later emitted
    /// as the debug overlay + JSON snapshot.
    func getClickableElements(recorder: HintDiscoveryRecorder? = nil) -> [UIElement] {
        guard let focusedApp = NSWorkspace.shared.frontmostApplication,
              let pid = focusedApp.processIdentifier as pid_t? else {
            return []
        }

        // Belt-and-suspenders wake: the eager activation hook in
        // `AppDelegate` covers the common case, but if the user
        // launched clavier *after* the Chromium app was already
        // frontmost — or the activation race somehow lost — this
        // catches it before the walk.
        let wakeOutcome = ChromiumAccessibilityWaker.shared.wakeIfNeeded(focusedApp)
        if wakeOutcome == .freshlyWoken {
            // Chromium needs ~100–500 ms to populate the tree after
            // `AXManualAccessibility` is set. 150 ms is a pragmatic
            // floor that catches most cases without making the hint
            // overlay feel laggy. The walker's empty-tree retry below
            // covers anything still in flight.
            usleep(150_000)
        }

        let appElement = AXUIElementCreateApplication(pid)
        let bundleId = focusedApp.bundleIdentifier

        let deduplicated = traverseAndCollect(appElement: appElement, pid: pid, recorder: recorder)

        // Empty-tree retry for known Chromium apps. If the eager wake
        // hasn't finished or the bundle id is on the list but the
        // attribute didn't take (CEF apps, etc.), one retry after a
        // short settle gives the tree a chance to appear before we
        // give up. Non-Chromium apps with empty trees usually just
        // have nothing clickable — no point retrying them.
        if shouldRetryForEmptyTree(deduplicated: deduplicated,
                                   appElement: appElement,
                                   bundleId: bundleId,
                                   wakeOutcome: wakeOutcome) {
            usleep(150_000)
            return traverseAndCollect(appElement: appElement, pid: pid, recorder: recorder)
        }

        return deduplicated
    }

    /// Walk every window of `appElement`, dedupe, and return the
    /// resulting `UIElement`s. Pulled out of `getClickableElements` so
    /// the empty-tree retry path can call it twice without duplicating
    /// the traversal logic.
    private func traverseAndCollect(
        appElement: AXUIElement,
        pid: pid_t,
        recorder: HintDiscoveryRecorder?
    ) -> [UIElement] {
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return []
        }

        // Full desktop bounds in AX coordinates so windows on non-main
        // displays are not silently dropped by the intersection clip.
        let desktopBoundsAX = ScreenGeometry.desktopBoundsInAX

        var pending: [PendingElement] = []

        let traverseStartTime = CFAbsoluteTimeGetCurrent()
        for window in windows {
            let windowBounds = windowFrameAX(window) ?? desktopBoundsAX
            let visibleBounds = windowBounds.intersection(desktopBoundsAX)

            walker.walk(window, pid: pid, clipBounds: visibleBounds, into: &pending, recorder: recorder)
        }
        let traverseEndTime = CFAbsoluteTimeGetCurrent()
        Logger.accessibility.debug("traverseElements: \(Int((traverseEndTime - traverseStartTime) * 1000), privacy: .public)ms (\(pending.count, privacy: .public) raw)")

        let dedupeStartTime = CFAbsoluteTimeGetCurrent()
        let deduplicated = ClickableElementWalker.collect(pending: pending)
        let dedupeEndTime = CFAbsoluteTimeGetCurrent()
        Logger.accessibility.debug("deduplicateElements: \(Int((dedupeEndTime - dedupeStartTime) * 1000), privacy: .public)ms (\(deduplicated.count, privacy: .public) unique)")

        return deduplicated
    }

    /// Heuristic for "the AX tree looks suspiciously empty for a
    /// Chromium app whose tree we just woke." Triggers exactly one
    /// retry and only when:
    ///   - the app is on the Chromium allow-list,
    ///   - this discovery pass produced very few clickables,
    ///   - the frontmost window is large enough that the emptiness
    ///     can't be explained by a tiny popover/notification.
    /// Skipped when the wake was already satisfied earlier in the
    /// session — a populated Chromium tree that legitimately has few
    /// clickables (e.g. a splash screen) shouldn't get retried.
    private func shouldRetryForEmptyTree(
        deduplicated: [UIElement],
        appElement: AXUIElement,
        bundleId: String?,
        wakeOutcome: ChromiumAccessibilityWaker.WakeOutcome
    ) -> Bool {
        guard wakeOutcome == .freshlyWoken else { return false }
        guard let bundleId, ChromiumAccessibilityWaker.isKnownChromiumApp(bundleId: bundleId) else {
            return false
        }
        guard deduplicated.count < 5 else { return false }

        // Look for at least one window large enough to plausibly host
        // hidden content. The 400×400 threshold matches the same
        // cutoff used in `ChromiumDetector` for DevTools panels.
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return false
        }
        for window in windows {
            if let frame = windowFrameAX(window), frame.width > 400, frame.height > 400 {
                Logger.accessibility.debug("Empty-tree retry triggered for \(bundleId, privacy: .public)")
                return true
            }
        }
        return false
    }

    private func windowFrameAX(_ window: AXUIElement) -> CGRect? {
        switch AXReader.axFrameBatched(of: window) {
        case .success(let frame): return frame
        case .failure: return nil
        }
    }
}
