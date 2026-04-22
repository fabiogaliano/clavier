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

        let appElement = AXUIElementCreateApplication(pid)

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

    private func windowFrameAX(_ window: AXUIElement) -> CGRect? {
        switch AXReader.axFrameBatched(of: window) {
        case .success(let frame): return frame
        case .failure: return nil
        }
    }
}
