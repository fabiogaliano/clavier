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

struct BrowserWebAreaReadinessPolicy {
    let minimumContentWindowSize = CGSize(width: 400, height: 400)

    func shouldWait(windowFrame: CGRect?, containsWebArea: Bool) -> Bool {
        guard let windowFrame else { return false }
        return windowFrame.width > minimumContentWindowSize.width
            && windowFrame.height > minimumContentWindowSize.height
            && !containsWebArea
    }
}

@MainActor
class AccessibilityService {

    static let shared = AccessibilityService()

    private let walker = ClickableElementWalker()
    private let chromeCollector = SystemChromeCollector(walker: ClickableElementWalker())
    private let browserReadinessPolicy = BrowserWebAreaReadinessPolicy()

    private struct BrowserPrewarm {
        let id: UUID
        let task: Task<Void, Never>
    }
    private var browserPrewarms: [pid_t: BrowserPrewarm] = [:]

    private static let browserReadinessTimeout: TimeInterval = 3.0
    private static let browserReadinessPollInterval: TimeInterval = 0.1
    private static let webAreaProbeNodeLimit = 1_024
    private static let webAreaProbeDepthLimit = 30

    /// Begin renderer readiness as soon as a known browser becomes frontmost.
    /// A hint activation can await this same task instead of restarting the
    /// browser's cold-renderer delay from the hotkey press.
    func prewarmBrowserWebArea(
        for app: NSRunningApplication,
        wakeOutcome: ChromiumAccessibilityWaker.WakeOutcome
    ) {
        let pid = app.processIdentifier
        guard wakeOutcome != .skipped,
              ChromiumAccessibilityWaker.isKnownBrowser(bundleId: app.bundleIdentifier),
              browserPrewarms[pid] == nil else { return }

        let id = UUID()
        let bundleId = app.bundleIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.waitForBrowserWebArea(
                appElement: appElement,
                pid: pid,
                bundleId: bundleId
            )
            self.finishBrowserPrewarm(pid: pid, id: id)
        }
        browserPrewarms[pid] = BrowserPrewarm(id: id, task: task)
    }

    func forgetBrowserPid(_ pid: pid_t) {
        browserPrewarms.removeValue(forKey: pid)?.task.cancel()
    }

    /// Synchronous discovery for refreshes after the initial session has
    /// already established renderer accessibility.
    func getClickableElements(
        includeSystemChrome: Bool,
        recorder: HintDiscoveryRecorder? = nil
    ) -> [UIElement] {
        guard let focusedApp = NSWorkspace.shared.frontmostApplication else { return [] }

        ChromiumAccessibilityWaker.shared.wakeIfNeeded(focusedApp)
        let appElement = AXUIElementCreateApplication(focusedApp.processIdentifier)
        return traverseAndCollect(
            appElement: appElement,
            app: focusedApp,
            includeSystemChrome: includeSystemChrome,
            recorder: recorder
        )
    }

    /// Initial discovery waits for a known browser's structural web root before
    /// doing the expensive full walk. Chromium builds that root asynchronously;
    /// counting native toolbar controls cannot distinguish a cold renderer from
    /// a page with few links.
    func getClickableElementsWhenReady(
        includeSystemChrome: Bool,
        recorder: HintDiscoveryRecorder? = nil,
        onBrowserRendererPending: (([UIElement]) -> Void)? = nil
    ) async -> [UIElement] {
        guard let focusedApp = NSWorkspace.shared.frontmostApplication else { return [] }

        let pid = focusedApp.processIdentifier
        let bundleId = focusedApp.bundleIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        let wakeOutcome = ChromiumAccessibilityWaker.shared.wakeIfNeeded(focusedApp)

        if ChromiumAccessibilityWaker.isKnownBrowser(bundleId: bundleId),
           wakeOutcome != .skipped {
            let immediateElements = traverseAndCollect(
                appElement: appElement,
                app: focusedApp,
                includeSystemChrome: includeSystemChrome,
                recorder: recorder
            )
            if immediateElements.contains(where: \.isWebContent) {
                return immediateElements
            }
            if !immediateElements.isEmpty {
                onBrowserRendererPending?(immediateElements)
            }
            await awaitBrowserWebArea(appElement: appElement, pid: pid, bundleId: bundleId)
        } else if wakeOutcome == .freshlyWoken {
            // Electron's manual-accessibility path settles much faster than the
            // standalone-browser path and has no structural browser chrome to
            // distinguish from the renderer root.
            try? await Task.sleep(for: .milliseconds(150))
        }

        guard !Task.isCancelled,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            return []
        }
        return traverseAndCollect(
            appElement: appElement,
            app: focusedApp,
            includeSystemChrome: includeSystemChrome,
            recorder: recorder
        )
    }

    /// Walk every window of `appElement`, dedupe, and return the resulting
    /// `UIElement`s after any initial renderer-readiness wait has completed.
    private func traverseAndCollect(
        appElement: AXUIElement,
        app: NSRunningApplication,
        includeSystemChrome: Bool,
        recorder: HintDiscoveryRecorder?
    ) -> [UIElement] {
        let pid = app.processIdentifier
        var windowsRef: CFTypeRef?
        let windows: [AXUIElement]
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let found = windowsRef as? [AXUIElement] {
            windows = found
        } else {
            windows = []
        }
        let menus = openMenus(of: appElement)
        guard !windows.isEmpty || !menus.isEmpty || includeSystemChrome else { return [] }

        // Full desktop bounds in AX coordinates so windows on non-main
        // displays are not silently dropped by the intersection clip.
        let desktopBoundsAX = ScreenGeometry.desktopBoundsInAX

        var pending: [PendingElement] = []

        let traverseStartTime = CFAbsoluteTimeGetCurrent()
        for menu in menus {
            walker.walk(menu, pid: pid, clipBounds: desktopBoundsAX, into: &pending, recorder: recorder)
        }
        for window in windows {
            let windowBounds = windowFrameAX(window) ?? desktopBoundsAX
            let visibleBounds = windowBounds.intersection(desktopBoundsAX)

            walker.walk(window, pid: pid, clipBounds: visibleBounds, into: &pending, recorder: recorder)
        }
        let traverseEndTime = CFAbsoluteTimeGetCurrent()
        Logger.accessibility.debug("traverseElements: \(Int((traverseEndTime - traverseStartTime) * 1000), privacy: .public)ms (\(pending.count, privacy: .public) raw)")

        var chrome: [UIElement] = []
        if includeSystemChrome {
            let chromeStartTime = CFAbsoluteTimeGetCurrent()
            chrome = chromeCollector.collect(
                frontmost: app,
                appElement: appElement,
                desktopAX: desktopBoundsAX,
                openMenuItems: &pending,
                recorder: recorder
            )
            let chromeElapsed = Int((CFAbsoluteTimeGetCurrent() - chromeStartTime) * 1000)
            Logger.accessibility.debug("systemChrome: \(chromeElapsed, privacy: .public)ms (\(chrome.count, privacy: .public) items)")
        }

        let dedupeStartTime = CFAbsoluteTimeGetCurrent()
        let deduplicated = ClickableElementWalker.collect(pending: pending)
        let dedupeEndTime = CFAbsoluteTimeGetCurrent()
        Logger.accessibility.debug("deduplicateElements: \(Int((dedupeEndTime - dedupeStartTime) * 1000), privacy: .public)ms (\(deduplicated.count, privacy: .public) unique)")

        return deduplicated + chrome
    }

    /// Open native menus (context menus, pop-up buttons, a browser's
    /// `<select>` popup) are children of the application element, not
    /// entries in `AXWindows`, so the window walk never reaches them.
    private func openMenus(of appElement: AXUIElement) -> [AXUIElement] {
        guard case .success(let children) = AXReader.elements(
            kAXChildrenAttribute as CFString,
            of: appElement
        ) else { return [] }
        return children.filter { child in
            guard case .success(let role) = AXReader.string(kAXRoleAttribute as CFString, of: child) else {
                return false
            }
            return role == kAXMenuRole as String
        }
    }

    private func awaitBrowserWebArea(
        appElement: AXUIElement,
        pid: pid_t,
        bundleId: String?
    ) async {
        if let prewarm = browserPrewarms[pid] {
            await prewarm.task.value
            return
        }
        await waitForBrowserWebArea(appElement: appElement, pid: pid, bundleId: bundleId)
    }

    private func finishBrowserPrewarm(pid: pid_t, id: UUID) {
        guard browserPrewarms[pid]?.id == id else { return }
        browserPrewarms.removeValue(forKey: pid)
    }

    private func waitForBrowserWebArea(
        appElement: AXUIElement,
        pid: pid_t,
        bundleId: String?
    ) async {
        let start = CFAbsoluteTimeGetCurrent()
        var contentWindow = browserContentWindow(of: appElement)
        while contentWindow == nil,
              CFAbsoluteTimeGetCurrent() - start < Self.browserReadinessTimeout {
            try? await Task.sleep(for: .seconds(Self.browserReadinessPollInterval))
            guard !Task.isCancelled,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                return
            }
            contentWindow = browserContentWindow(of: appElement)
        }

        guard let contentWindow else { return }
        let frame = windowFrameAX(contentWindow)
        guard browserReadinessPolicy.shouldWait(
            windowFrame: frame,
            containsWebArea: containsWebArea(in: contentWindow)
        ) else { return }

        while CFAbsoluteTimeGetCurrent() - start < Self.browserReadinessTimeout {
            try? await Task.sleep(for: .seconds(Self.browserReadinessPollInterval))
            guard !Task.isCancelled,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                return
            }
            if containsWebArea(in: contentWindow) {
                let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1_000)
                Logger.accessibility.debug(
                    "Browser AXWebArea ready for \(bundleId ?? "unknown", privacy: .public) after \(elapsed, privacy: .public)ms"
                )
                return
            }
        }

        Logger.accessibility.warning(
            "Browser AXWebArea did not appear within \(Int(Self.browserReadinessTimeout * 1_000), privacy: .public)ms for \(bundleId ?? "unknown", privacy: .public)"
        )
    }

    private func browserContentWindow(of appElement: AXUIElement) -> AXUIElement? {
        if case .success(let window) = AXReader.element(
            kAXFocusedWindowAttribute as CFString,
            of: appElement
        ) {
            return window
        }

        guard case .success(let windows) = AXReader.elements(
            kAXWindowsAttribute as CFString,
            of: appElement
        ) else { return nil }
        return windows.max { lhs, rhs in
            let lhsArea = windowFrameAX(lhs).map { $0.width * $0.height } ?? 0
            let rhsArea = windowFrameAX(rhs).map { $0.width * $0.height } ?? 0
            return lhsArea < rhsArea
        }
    }

    /// Geometry is intentionally not required here. AXGroup containers can be
    /// structural-only; requiring a frame before descending could hide the web
    /// root that this readiness probe exists to detect.
    private func containsWebArea(in root: AXUIElement) -> Bool {
        var stack: [(element: AXUIElement, depth: Int)] = [(root, 0)]
        var visited = 0

        while let current = stack.popLast(),
              visited < Self.webAreaProbeNodeLimit {
            visited += 1
            guard current.depth <= Self.webAreaProbeDepthLimit else { continue }

            if case .success(let role) = AXReader.string(kAXRoleAttribute as CFString, of: current.element),
               role == "AXWebArea" {
                return true
            }
            if case .success(let children) = AXReader.elements(kAXChildrenAttribute as CFString, of: current.element) {
                stack.append(contentsOf: children.reversed().map { ($0, current.depth + 1) })
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
