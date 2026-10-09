//
//  HintPostClickPolicy.swift
//  clavier
//
//  Decides what a hint session does after it clicks something.
//
//  Continuous sessions always refresh.  One-shot sessions normally close, but
//  a click that opens a popup (select, combobox, menu button, context menu)
//  is only half a gesture — the user still has to pick an item.  Those clicks
//  keep the session alive, refresh once the popup settles, and close anyway
//  if nothing new appeared.
//

import Foundation
import ApplicationServices

enum HintPostClickPlan: Equatable {
    /// End the session (classic one-shot behaviour).
    case close
    /// Keep the session and refresh hints once the UI settles.
    /// `closeIfUnchanged` ends the session when the refresh finds nothing new.
    case refresh(closeIfUnchanged: Bool)
}

enum HintPostClickPolicy {

    /// Roles whose primary action opens a popup of choices.  Web buttons with
    /// `aria-haspopup` are caught by the `AXHasPopup` probe instead.
    static let popupTriggerRoles: Set<String> = [
        kAXPopUpButtonRole as String,
        kAXMenuButtonRole as String,
        kAXComboBoxRole as String
    ]

    static func plan(mode: HintSessionMode, clickOpensPopup: Bool) -> HintPostClickPlan {
        switch (mode, clickOpensPopup) {
        case (.continuous, _): return .refresh(closeIfUnchanged: false)
        case (.oneShot, true): return .refresh(closeIfUnchanged: true)
        case (.oneShot, false): return .close
        }
    }

    /// Whether a click of `kind` should be treated as opening a popup.
    /// `targetOpensPopup` probes the live element and is only evaluated for
    /// kinds that press it the way a left click would.
    static func clickOpensPopup(kind: HintClickKind, targetOpensPopup: () -> Bool) -> Bool {
        switch kind {
        case .secondary:
            return true // a right-click opens a context menu
        case .hover:
            // Nothing was pressed, so there is no popup to follow; a one-shot
            // session has done its job once the cursor is in place.
            return false
        case .primary, .double, .commandClick:
            return targetOpensPopup()
        }
    }

    static func opensPopup(role: String, hasPopup: Bool?) -> Bool {
        popupTriggerRoles.contains(role) || hasPopup == true
    }
}

/// Live AX side of `HintPostClickPolicy`.  Must run before the click, while
/// the element is still guaranteed to exist.
@MainActor
enum HintPopupTriggerProbe {
    static func opensPopup(_ element: UIElement) -> Bool {
        if HintPostClickPolicy.popupTriggerRoles.contains(element.role) { return true }
        let hasPopup = try? AXReader.bool("AXHasPopup" as CFString, of: element.axElement).get()
        return HintPostClickPolicy.opensPopup(role: element.role, hasPopup: hasPopup)
    }
}
