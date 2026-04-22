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

    /// HTML tag names / ARIA roles that Chromium reports via its
    /// undocumented `AXDOMRole` attribute for *interactive* web elements.
    /// Compared case-insensitively (values stored lowercased).  Only
    /// consulted inside `AXWebArea` when `AXDOMRole` is present on the
    /// candidate — Safari/Firefox don't expose the attribute and fall
    /// back to the URL rule.
    let interactiveDOMRoles: Set<String>

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
        ],
        interactiveDOMRoles: [
            "a",
            "button",
            "input",
            "select",
            "textarea",
            "summary",
            "details",
            "link",
            "menuitem",
            "tab",
            "checkbox",
            "radio",
            "switch"
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
        /// Pressable static text suppressed inside a web area because a
        /// clickable ancestor already covers the same content — typical of
        /// `<a>`/`<button>` wrapping inner text runs.
        case staticTextDroppedByAncestor
        /// Pressable static text suppressed inside a web area because it
        /// exposes no `AXURL` and isn't wrapped by a clickable ancestor.
        /// Filters out paragraph/label text that falsely advertises
        /// `AXPress` without being a real link.
        case staticTextDroppedNoURL
        /// Chromium-only: pressable static text suppressed because its
        /// `AXDOMRole` (HTML tag / ARIA role) is not an interactive
        /// element — e.g., a `<p>` or `<span>` that inherited `AXPress`
        /// from a nearby focusable ancestor.
        case staticTextDroppedByDOMRole

        var isClickable: Bool {
            switch self {
            case .interactiveRole, .staticTextPressable: return true
            case .disabled,
                 .staticTextNoAction,
                 .roleNotInteractive,
                 .staticTextDroppedByAncestor,
                 .staticTextDroppedNoURL,
                 .staticTextDroppedByDOMRole:
                return false
            }
        }
    }

    /// Structural context supplied by the walker when the node being
    /// classified lives inside a web page subtree.  Drives the narrowed
    /// AXStaticText rules — everywhere else (native apps) the classifier
    /// behaves as if this is absent.
    struct WebContext {
        /// `true` when any ancestor up the walk is an `AXWebArea`.
        let inWebArea: Bool
        /// `true` when the walker has already accepted some clickable
        /// element strictly above this node.  Used to drop text nodes
        /// that duplicate their wrapping link/button.
        let hasClickableAncestor: Bool
    }

    /// Classifying variant of `isClickable` — same decision points, plus
    /// a machine-readable reason tag used by the debug recorder.
    ///
    /// `webContext` is `nil` for native-app traversal and for the pre-web
    /// entry point; in both cases the classifier matches pre-WebArea
    /// behaviour exactly.  Inside an `AXWebArea` the walker passes a
    /// populated context, which activates the two narrowing rules.
    func evaluate(
        role: String,
        element: AXUIElement,
        enabled: Bool?,
        webContext: WebContext? = nil
    ) -> Decision {
        if let enabled, !enabled { return .disabled }
        if interactiveRoles.contains(role) { return .interactiveRole }
        if role == kAXStaticTextRole as String {
            guard hasClickAction(element) else { return .staticTextNoAction }
            if let ctx = webContext, ctx.inWebArea {
                if ctx.hasClickableAncestor { return .staticTextDroppedByAncestor }
                // Chromium exposes `AXDOMRole` (HTML tag or ARIA role) as
                // an undocumented extra attribute.  When present it's
                // ground truth — overrides the URL heuristic.
                if let dr = readDOMRole(element) {
                    return interactiveDOMRoles.contains(dr)
                        ? .staticTextPressable
                        : .staticTextDroppedByDOMRole
                }
                // Safari / Firefox fallback: no `AXDOMRole`, use URL.
                if !hasURL(element) { return .staticTextDroppedNoURL }
            }
            return .staticTextPressable
        }
        return .roleNotInteractive
    }

    /// Pure sibling of `evaluate` — same decision tree with AX probes
    /// hoisted out so tests can cover every branch without standing up a
    /// live AX tree.  `hasClickAction`, `hasURL` and `domRole` are
    /// nil/false by default so callers only need to set what the test
    /// case exercises.  `domRole` is compared case-insensitively.
    func classify(
        role: String,
        enabled: Bool?,
        hasClickAction: Bool = false,
        hasURL: Bool = false,
        domRole: String? = nil,
        webContext: WebContext? = nil
    ) -> Decision {
        if let enabled, !enabled { return .disabled }
        if interactiveRoles.contains(role) { return .interactiveRole }
        if role == kAXStaticTextRole as String {
            guard hasClickAction else { return .staticTextNoAction }
            if let ctx = webContext, ctx.inWebArea {
                if ctx.hasClickableAncestor { return .staticTextDroppedByAncestor }
                if let dr = domRole?.lowercased() {
                    return interactiveDOMRoles.contains(dr)
                        ? .staticTextPressable
                        : .staticTextDroppedByDOMRole
                }
                if !hasURL { return .staticTextDroppedNoURL }
            }
            return .staticTextPressable
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
    ///   `AXPress` or `AXShowMenu`.  Inside a web area the walker also
    ///   suppresses duplicates (see `Decision.staticTextDroppedByAncestor`)
    ///   and URL-less candidates (`staticTextDroppedNoURL`).
    func isClickable(
        role: String,
        element: AXUIElement,
        enabled: Bool?,
        webContext: WebContext? = nil
    ) -> Bool {
        evaluate(
            role: role,
            element: element,
            enabled: enabled,
            webContext: webContext
        ).isClickable
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

    /// Probe for the presence of `AXURL` — real web links carry one, plain
    /// text runs that happen to inherit `AXPress` from a nearby focusable
    /// ancestor do not.  Only called when the walker already knows we're
    /// inside an `AXWebArea` without a clickable ancestor, so it costs at
    /// most one extra IPC call per surviving static-text candidate.
    private func hasURL(_ element: AXUIElement) -> Bool {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXURL" as CFString, &ref) == .success else {
            return false
        }
        return ref != nil
    }

    /// Read Chromium's `AXDOMRole` attribute (the HTML tag name or ARIA
    /// role of the underlying DOM node) and return it lowercased.  Returns
    /// nil when the attribute is absent — e.g., Safari and Firefox don't
    /// expose it, so the classifier falls back to the URL rule for those.
    private func readDOMRole(_ element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXDOMRole" as CFString, &ref) == .success,
              let value = ref as? String,
              !value.isEmpty else {
            return nil
        }
        return value.lowercased()
    }
}
