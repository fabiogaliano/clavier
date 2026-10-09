//
//  HintActionPerformer.swift
//  clavier
//
//  Executes the click verbs (primary, secondary, double, ⌘-click, hover)
//  on a hinted element.
//
//  Each action first attempts an AX action (`kAXPressAction` for primary,
//  `"AXShowMenu"` for secondary) and falls back to a synthesized CGEvent
//  click through `ClickService` when AX reports anything other than
//  `.success`. Some Electron/Chromium controls acknowledge `AXPress`
//  without actually activating, so web-content elements are routed
//  straight to the CGEvent path.
//
//  The type is `@MainActor` because every AXUIElement API is documented
//  by Apple DTS as main-thread only.
//

import Foundation
import ApplicationServices

@MainActor
enum HintActionPerformer {

    private static let primaryActionPolicy = HintActionPolicy()

    static func perform(_ kind: HintClickKind, on element: UIElement) {
        switch kind {
        case .primary:
            performPrimary(on: element)
        case .secondary:
            performSecondary(on: element)
        case .double:
            // AX has no double-press action, so this is always synthesized.
            ClickService.shared.doubleClick(at: quartzCenter(of: element))
        case .commandClick:
            // AXPress can't carry modifier flags; only a synthesized click
            // reaches the app as a ⌘-click.
            ClickService.shared.click(at: quartzCenter(of: element), flags: .maskCommand)
        case .hover:
            ClickService.shared.moveCursor(to: quartzCenter(of: element))
        }
    }

    /// Perform the element's primary action (single click equivalent).
    ///
    /// Tries `kAXPressAction` first; on any non-success AX status falls back
    /// to a CGEvent click at the element's visible centre.
    ///
    /// Some controls go *straight* to the CGEvent path instead of trusting
    /// `AXPress`. Chromium / Electron web content frequently returns
    /// `.success` for `AXPress` without actually activating the control.
    /// Routing all web-content elements through the mouse-click fallback
    /// fixes Windsurf, VS Code, and the same class of browser-hosted UI.
    static func performPrimary(on element: UIElement) {
        let context = HintPrimaryActionContext(
            role: element.role,
            isWebContent: element.isWebContent
        )
        let strategy = primaryActionPolicy.strategy(for: context)

        if strategy == .axPressThenCGEventFallback {
            let axStatus = AXUIElementPerformAction(element.axElement, kAXPressAction as CFString)
            if axStatus == .success { return }
        }

        ClickService.shared.click(at: quartzCenter(of: element))
    }

    /// Perform the element's secondary action (right click / context menu).
    ///
    /// Tries `"AXShowMenu"` first; on any non-success AX status falls back
    /// to a CGEvent right-click at the element's visible centre.
    static func performSecondary(on element: UIElement) {
        let axStatus = AXUIElementPerformAction(element.axElement, "AXShowMenu" as CFString)
        guard axStatus != .success else { return }

        ClickService.shared.rightClick(at: quartzCenter(of: element))
    }

    private static func quartzCenter(of element: UIElement) -> CGPoint {
        ScreenGeometry.appKitCenterToQuartz(element.centerPoint)
    }
}
