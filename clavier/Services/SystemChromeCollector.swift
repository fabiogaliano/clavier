//
//  SystemChromeCollector.swift
//  clavier
//
//  Discovers the system chrome a hint session can click besides the
//  frontmost app's windows: the frontmost app's menu bar titles, status
//  items on the right of the menu bar (owned by many processes), and the
//  Dock.  These are the targets people otherwise still reach for the mouse
//  for.
//
//  Chrome items are read one level deep with a single batched AX call each
//  instead of being walked: menu bar items carry their (closed) menus as
//  children, and walking those would hint every hidden menu item.  Only a
//  menu that is actually open (its bar item is `AXSelected`) is handed to
//  the regular walker.
//

import AppKit
import ApplicationServices
import os

/// Pure decisions behind `SystemChromeCollector`, split out for tests.
enum SystemChromePolicy {

    static let controlCenterBundleID = "com.apple.controlcenter"
    static let systemUIServerBundleID = "com.apple.systemuiserver"
    static let dockBundleID = "com.apple.dock"

    /// Wall-clock budget for enumerating status items across every running
    /// app.  Each app costs at least one cross-process round trip, so the
    /// pass is cut off rather than allowed to scale with the process count.
    static let statusPassBudget: CFTimeInterval = 0.030

    struct Candidate: Equatable {
        let pid: pid_t
        let bundleID: String?
        let activationPolicy: NSApplication.ActivationPolicy
    }

    /// Order in which processes are probed for status items: the frontmost
    /// app's own extras first, then the system hosts that own the clock,
    /// battery, Wi-Fi and the like, then everyone else.  When the time box
    /// runs out the items people use most are already in.
    ///
    /// Background-only processes cannot own a status item; clavier itself is
    /// skipped because an AX request to our own process from the main thread
    /// would wait on the very thread that has to answer it.
    static func statusProbeOrder(
        _ candidates: [Candidate],
        frontmostPID: pid_t,
        ownPID: pid_t
    ) -> [Candidate] {
        func rank(_ candidate: Candidate) -> Int {
            if candidate.pid == frontmostPID { return 0 }
            switch candidate.bundleID {
            case controlCenterBundleID: return 1
            case systemUIServerBundleID: return 2
            default: return 3
            }
        }
        let eligible = candidates.filter { candidate in
            candidate.pid != ownPID
                && candidate.bundleID != dockBundleID
                && (candidate.activationPolicy != .prohibited || rank(candidate) < 3)
        }
        return eligible.enumerated()
            .sorted { lhs, rhs in
                let (l, r) = (rank(lhs.element), rank(rhs.element))
                return l != r ? l < r : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// Whether a chrome item should get a hint.  Dock separators are not
    /// clickable; zero-sized or off-desktop items are status items the
    /// system has hidden (crowded menu bar, auto-hidden Dock).
    static func isHintable(role: String, subrole: String?, frameAX: CGRect, desktopAX: CGRect) -> Bool {
        guard role == kAXMenuBarItemRole as String || role == "AXDockItem" else { return false }
        guard subrole != "AXSeparatorDockItem" else { return false }
        guard frameAX.width > 1, frameAX.height > 1 else { return false }
        return frameAX.intersects(desktopAX)
    }
}

@MainActor
struct SystemChromeCollector {

    private let walker: ClickableElementWalker

    /// Per-request cap for status-item probes.  A hung or busy app would
    /// otherwise hold the main thread for the system default (about six
    /// seconds) while the user waits for hints.
    private static let probeMessagingTimeout: Float = 0.025

    init(walker: ClickableElementWalker) {
        self.walker = walker
    }

    /// Chrome items as `UIElement`s tagged `isSystemChrome`, in menu bar,
    /// status, Dock order.  Items of any chrome menu that is currently open
    /// are appended to `openMenuItems` as ordinary (non-chrome) elements so
    /// they share the window region with the rest of the session's targets.
    func collect(
        frontmost: NSRunningApplication,
        appElement: AXUIElement,
        desktopAX: CGRect,
        openMenuItems: inout [PendingElement],
        recorder: HintDiscoveryRecorder?
    ) -> [UIElement] {
        var chrome: [UIElement] = []
        let frontmostPID = frontmost.processIdentifier

        if case .success(let menuBar) = AXReader.element(kAXMenuBarAttribute as CFString, of: appElement) {
            appendItems(of: menuBar, pid: frontmostPID, desktopAX: desktopAX,
                        into: &chrome, openMenuItems: &openMenuItems, recorder: recorder)
        }

        collectStatusItems(frontmostPID: frontmostPID, desktopAX: desktopAX,
                           into: &chrome, openMenuItems: &openMenuItems, recorder: recorder)

        if let dock = NSRunningApplication.runningApplications(
            withBundleIdentifier: SystemChromePolicy.dockBundleID
        ).first {
            collectDockItems(pid: dock.processIdentifier, desktopAX: desktopAX, into: &chrome)
        }

        return chrome
    }

    // MARK: - Status items

    private func collectStatusItems(
        frontmostPID: pid_t,
        desktopAX: CGRect,
        into chrome: inout [UIElement],
        openMenuItems: inout [PendingElement],
        recorder: HintDiscoveryRecorder?
    ) {
        let start = CFAbsoluteTimeGetCurrent()
        let candidates = NSWorkspace.shared.runningApplications.map {
            SystemChromePolicy.Candidate(
                pid: $0.processIdentifier,
                bundleID: $0.bundleIdentifier,
                activationPolicy: $0.activationPolicy
            )
        }
        let order = SystemChromePolicy.statusProbeOrder(
            candidates,
            frontmostPID: frontmostPID,
            ownPID: ProcessInfo.processInfo.processIdentifier
        )

        var probed = 0
        for candidate in order {
            if CFAbsoluteTimeGetCurrent() - start > SystemChromePolicy.statusPassBudget {
                Logger.accessibility.debug(
                    "status items: time box hit after \(probed, privacy: .public)/\(order.count, privacy: .public) apps"
                )
                break
            }
            probed += 1

            let app = AXUIElementCreateApplication(candidate.pid)
            AXUIElementSetMessagingTimeout(app, Self.probeMessagingTimeout)
            for bar in statusBars(of: app, bundleID: candidate.bundleID) {
                AXUIElementSetMessagingTimeout(bar, Self.probeMessagingTimeout)
                appendItems(of: bar, pid: candidate.pid, desktopAX: desktopAX,
                            messagingTimeout: Self.probeMessagingTimeout,
                            into: &chrome, openMenuItems: &openMenuItems, recorder: recorder)
            }
        }

        let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1_000)
        Logger.accessibility.debug(
            "status items: probed \(probed, privacy: .public) apps in \(elapsed, privacy: .public)ms"
        )
    }

    /// Third-party status items hang off `AXExtrasMenuBar`.  The system hosts
    /// (Control Center, SystemUIServer) have historically exposed theirs as
    /// an `AXMenuBar` child instead, so those are read both ways.
    private func statusBars(of app: AXUIElement, bundleID: String?) -> [AXUIElement] {
        var bars: [AXUIElement] = []
        if case .success(let extras) = AXReader.element("AXExtrasMenuBar" as CFString, of: app) {
            bars.append(extras)
        }
        guard bundleID == SystemChromePolicy.controlCenterBundleID
                || bundleID == SystemChromePolicy.systemUIServerBundleID,
              case .success(let children) = AXReader.elements(kAXChildrenAttribute as CFString, of: app)
        else { return bars }

        for child in children where !bars.contains(where: { CFEqual($0, child) }) {
            if case .success(let role) = AXReader.string(kAXRoleAttribute as CFString, of: child),
               role == kAXMenuBarRole as String {
                bars.append(child)
            }
        }
        return bars
    }

    // MARK: - Dock

    private func collectDockItems(pid: pid_t, desktopAX: CGRect, into chrome: inout [UIElement]) {
        let dock = AXUIElementCreateApplication(pid)
        guard case .success(let children) = AXReader.elements(kAXChildrenAttribute as CFString, of: dock) else {
            return
        }
        for child in children {
            guard case .success(let role) = AXReader.string(kAXRoleAttribute as CFString, of: child),
                  role == kAXListRole as String,
                  case .success(let items) = AXReader.elements(kAXChildrenAttribute as CFString, of: child)
            else { continue }
            for item in items {
                if let node = ChromeNode.read(item),
                   let element = node.uiElement(item, pid: pid, desktopAX: desktopAX) {
                    chrome.append(element)
                }
            }
        }
    }

    // MARK: - Menu bars

    private func appendItems(
        of bar: AXUIElement,
        pid: pid_t,
        desktopAX: CGRect,
        messagingTimeout: Float? = nil,
        into chrome: inout [UIElement],
        openMenuItems: inout [PendingElement],
        recorder: HintDiscoveryRecorder?
    ) {
        guard case .success(let items) = AXReader.elements(kAXChildrenAttribute as CFString, of: bar) else {
            return
        }
        for item in items {
            if let messagingTimeout { AXUIElementSetMessagingTimeout(item, messagingTimeout) }
            guard let node = ChromeNode.read(item) else { continue }
            if let element = node.uiElement(item, pid: pid, desktopAX: desktopAX) {
                chrome.append(element)
            }
            // A menu bar title the user just pressed: its menu is the next
            // thing to hint, and it is not reachable from the window walk.
            guard node.selected else { continue }
            for menu in node.children {
                walker.walk(menu, pid: pid, clipBounds: desktopAX, into: &openMenuItems, recorder: recorder)
            }
        }
    }
}

/// One batched read of the attributes chrome discovery needs.
@MainActor
private struct ChromeNode {
    let role: String
    let subrole: String?
    let frameAX: CGRect
    let enabled: Bool?
    let selected: Bool
    let children: [AXUIElement]

    static func read(_ element: AXUIElement) -> ChromeNode? {
        let attributes = [
            kAXRoleAttribute as CFString,
            kAXSubroleAttribute as CFString,
            kAXPositionAttribute as CFString,
            kAXSizeAttribute as CFString,
            kAXEnabledAttribute as CFString,
            kAXSelectedAttribute as CFString,
            kAXChildrenAttribute as CFString
        ] as CFArray

        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, attributes, [], &values) == .success,
              let array = values as? [Any], array.count == 7,
              let role = array[0] as? String,
              let position = AXReader.decodeCGPoint(from: array[2]),
              let size = AXReader.decodeCGSize(from: array[3]) else { return nil }

        return ChromeNode(
            role: role,
            subrole: array[1] as? String,
            frameAX: CGRect(origin: position, size: size),
            enabled: array[4] as? Bool,
            selected: array[5] as? Bool ?? false,
            children: array[6] as? [AXUIElement] ?? []
        )
    }

    func uiElement(_ element: AXUIElement, pid: pid_t, desktopAX: CGRect) -> UIElement? {
        guard enabled != false,
              SystemChromePolicy.isHintable(role: role, subrole: subrole, frameAX: frameAX, desktopAX: desktopAX)
        else { return nil }

        let frame = ScreenGeometry.axToAppKit(position: frameAX.origin, size: frameAX.size)
        let visibleAX = frameAX.intersection(desktopAX)
        let visibleFrame = ScreenGeometry.axToAppKit(position: visibleAX.origin, size: visibleAX.size)
        return UIElement(
            stableID: ElementIdentity(pid: pid, role: role, frame: frame),
            axElement: element,
            frame: frame,
            visibleFrame: visibleFrame,
            isSystemChrome: true,
            role: role
        )
    }
}
