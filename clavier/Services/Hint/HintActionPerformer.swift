//
//  HintActionPerformer.swift
//  clavier
//
//  Executes primary and secondary clicks on a hinted element.
//
//  Each action first attempts an AX action (`kAXPressAction` for primary,
//  `"AXShowMenu"` for secondary) and falls back to a synthesized CGEvent
//  click through `ClickService` when AX reports anything other than
//  `.success`.  The fallback covers Electron/Chromium apps and elements
//  that do not publish the action — see `claudedocs/api-research.md`.
//
//  The type is `@MainActor` because every AXUIElement API is documented
//  by Apple DTS as main-thread only (`claudedocs/api-research.md:54-93`).
//

import Foundation
import ApplicationServices

@MainActor
enum HintActionPerformer {

    /// Perform the element's primary action (single click equivalent).
    ///
    /// Tries `kAXPressAction` first; on any non-success AX status falls back
    /// to a CGEvent click at the element's visible centre.
    ///
    /// `AXLink` is special-cased to go *straight* to the CGEvent path.
    /// Chromium web content frequently returns `.success` for `AXPress` on
    /// `AXLink` without actually following the link — the AX call is
    /// acknowledged but no navigation happens.  `AXLink` is essentially
    /// web-only on macOS (native apps render links as `AXButton` with a
    /// link-styled appearance), so skipping the AX path here doesn't affect
    /// any native-app behavior.
    static func performPrimary(on element: UIElement) {
        if element.role != "AXLink" {
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
