//
//  ClickabilityPolicy.swift
//  clavier
//
//  Role-based heuristics for deciding whether an AX element is a clickable
//  target, plus the list of subtrees that can be pruned from traversal
//  because their descendants never contribute clickable elements.
//
//  Extracted from `AccessibilityService` so the walker can stay focused on
//  recursion, batching, and clipping, and so the heuristics can be tested
//  without standing up a full AX tree.
//
//  Threading: `isClickable(role:element:enabled:)` calls
//  `AXUIElementCopyActionNames` for the `AXStaticText` branch, which is a
//  main-thread-only AX API per Apple DTS guidance recorded in
//  `claudedocs/api-research.md`.  The type is therefore `@MainActor`.
//

import Foundation
import ApplicationServices

@MainActor
struct ClickabilityPolicy {

    /// Roles assumed interactive by default.  When present, the capability
    /// check only gates on the element's `enabled` flag.
    let interactiveRoles: Set<String>

    /// Roles whose subtrees never contain clickable descendants — the
    /// walker can skip recursion into their children.
    let skipSubtreeRoles: Set<String>

    static let `default` = ClickabilityPolicy(
        interactiveRoles: [
            kAXButtonRole as String,
            "AXLink",
            kAXTextFieldRole as String,
            kAXCheckBoxRole as String,
            kAXRadioButtonRole as String,
            kAXPopUpButtonRole as String,
            kAXMenuButtonRole as String,
            "AXTab",
            kAXMenuItemRole as String,
            kAXIncrementorRole as String,
            kAXComboBoxRole as String,
            kAXSliderRole as String,
            kAXColorWellRole as String,
            "AXCell"
        ],
        skipSubtreeRoles: [
            kAXStaticTextRole as String,
            kAXImageRole as String,
            "AXScrollBar",
            kAXValueIndicatorRole as String,
            "AXBusyIndicator",
            "AXProgressIndicator"
        ]
    )

    /// Classified verdict used by the debug tracer in addition to the
    /// pass/fail answer consumed by the walker.  Cases carry the reason
    /// label shown in debug snapshots so Claude can see why a specific
    /// element was or was not hinted.
    enum Decision: String, Encodable {
        case interactiveRole
        case staticTextPressable
        case disabled
        case staticTextNoAction
        case roleNotInteractive

        var isClickable: Bool {
            switch self {
            case .interactiveRole, .staticTextPressable: return true
            case .disabled, .staticTextNoAction, .roleNotInteractive: return false
            }
        }
    }

    /// Classifying variant of `isClickable` — same decision points, plus
    /// a machine-readable reason tag used by the debug recorder.
    func evaluate(role: String, element: AXUIElement, enabled: Bool?) -> Decision {
        if let enabled, !enabled { return .disabled }
        if interactiveRoles.contains(role) { return .interactiveRole }
        if role == kAXStaticTextRole as String {
            return hasClickAction(element) ? .staticTextPressable : .staticTextNoAction
        }
        return .roleNotInteractive
    }

    /// Decide whether the element should receive a hint.
    ///
    /// - `enabled == false` short-circuits to `false` regardless of role.
    ///   `nil` means the attribute was absent in the batch read (common for
    ///   non-interactive elements) and is treated as "not disabled".
    /// - Interactive roles pass immediately.
    /// - `AXStaticText` is a special case: only clickable when it exposes
    ///   `AXPress` or `AXShowMenu`.
    func isClickable(role: String, element: AXUIElement, enabled: Bool?) -> Bool {
        evaluate(role: role, element: element, enabled: enabled).isClickable
    }

    /// Pure predicate companion to `isClickable` — same decision based only
    /// on role/enabled without the AX action lookup.  Useful for tests that
    /// want to cover the static role table without an `AXUIElement`.
    func interactiveByRole(role: String, enabled: Bool?) -> Bool {
        if let enabled, !enabled { return false }
        return interactiveRoles.contains(role)
    }

    func canPruneSubtree(role: String) -> Bool {
        skipSubtreeRoles.contains(role)
    }

    private func hasClickAction(_ element: AXUIElement) -> Bool {
        var actions: CFArray?
        guard AXUIElementCopyActionNames(element, &actions) == .success,
              let actionNames = actions as? [String] else {
            return false
        }
        return actionNames.contains(kAXPressAction as String)
            || actionNames.contains("AXShowMenu")
    }
}
