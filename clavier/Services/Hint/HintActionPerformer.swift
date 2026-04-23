//
//  HintActionPerformer.swift
//  clavier
//
//  Executes primary and secondary clicks on a hinted element.
//
//  Each action first attempts an AX action (`kAXPressAction` for primary,
//  `"AXShowMenu"` for secondary) and falls back to a synthesized CGEvent
//  click through `ClickService` when AX reports anything other than
//  `.success`. Some Electron/Chromium controls acknowledge `AXPress`
//  without actually activating, so web-content elements are routed
//  straight to the CGEvent path — see `claudedocs/api-research.md`.
//
//  The type is `@MainActor` because every AXUIElement API is documented
//  by Apple DTS as main-thread only (`claudedocs/api-research.md:54-93`).
//

import Foundation
import ApplicationServices

@MainActor
enum HintActionPerformer {

    private static let primaryActionPolicy = HintActionPolicy()

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

        let point = ScreenGeometry.appKitCenterToQuartz(element.centerPoint)
        ClickService.shared.click(at: point)
    }

    /// Perform the element's secondary action (right click / context menu).
    ///
    /// Tries `"AXShowMenu"` first; on any non-success AX status falls back
    /// to a CGEvent right-click at the element's visible centre.
    static func performSecondary(on element: UIElement) {
        let axStatus = AXUIElementPerformAction(element.axElement, "AXShowMenu" as CFString)
        guard axStatus != .success else { return }

        let point = ScreenGeometry.appKitCenterToQuartz(element.centerPoint)
        ClickService.shared.rightClick(at: point)
    }
}
