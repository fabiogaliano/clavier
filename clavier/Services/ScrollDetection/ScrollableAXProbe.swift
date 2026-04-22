//
//  ScrollableAXProbe.swift
//  clavier
//
//  Shared AX hierarchy / scroll-attribute helpers used by the scroll detection
//  pipeline.
//
//  Previously the same predicates and constructors were duplicated across
//  `ScrollableAreaService` and `ChromiumDetector`:
//    - `hasWebAncestor(_:)` ↔ `isWebContent(_:)` (10-level parent walk for AXWebArea)
//    - `createScrollableArea(from:)` (AppKit-frame conversion + wrapper init)
//
//  Centralising them here removes the duplication and lets future detectors
//  (or the focused-area finder) consume the same probe rather than carrying
//  their own copies.
//
//  This is a stateless probe — same shape as `AXReader`.
//

import AppKit

/// Stateless AX probes used by scroll-area detection.
///
/// All entry points are `@MainActor` because Apple DTS guidance is that
/// every Accessibility API call must come from the main thread (see
/// `claudedocs/api-research.md` → "Accessibility API threading").
@MainActor
enum ScrollableAXProbe {

    // MARK: - Roles

    /// Roles we treat as inherently scrollable when discovered via AX traversal.
    ///
    /// `AXWebArea` is intentionally absent — it triggers massive over-detection
    /// in browsers (every iframe / frame / document). Web scrollables are still
    /// reachable via `hasScrollBars` on their containers, or via a scrollable
    /// role under an `AXWebArea` ancestor (see `hasWebAncestor`).
    static let scrollableRoles: Set<String> = [
        "AXScrollArea",
        "AXScrollView",
        kAXTableRole as String,
        kAXOutlineRole as String,
        kAXListRole as String,
    ]

    /// Maximum levels of parent walking when probing the AX hierarchy.
    /// Web content can sit fairly deep; 10 has historically been sufficient.
    static let maxAncestorWalk = 10

    // MARK: - Predicates

    /// Whether `element` exposes scroll-bar attributes.
    ///
    /// - Parameter validateEnabled: When `true`, also requires that at least
    ///   one of the scroll bars reports `AXEnabled == true`. AppKit sets this
    ///   to true only when the content actually exceeds the visible area, so
    ///   it filters out inert scrollable containers whose content fits.
    static func hasScrollBars(_ element: AXUIElement, validateEnabled: Bool = false) -> Bool {
        let vResult = AXReader.element("AXVerticalScrollBar" as CFString, of: element)
        let hResult = AXReader.element("AXHorizontalScrollBar" as CFString, of: element)

        if !validateEnabled {
            if case .success = vResult { return true }
            if case .success = hResult { return true }
            return false
        }

        if case .success(let vScrollBar) = vResult,
           case .success(true) = AXReader.bool(kAXEnabledAttribute as CFString, of: vScrollBar) {
            return true
        }

        if case .success(let hScrollBar) = hResult,
           case .success(true) = AXReader.bool(kAXEnabledAttribute as CFString, of: hScrollBar) {
            return true
        }

        return false
    }

    /// Whether `element` lives under an `AXWebArea` (i.e. is web content).
    ///
    /// Used to grant scrollable roles inside web content an exemption from the
    /// native scroll-bar enabled check, since WebKit doesn't expose the
    /// `AXVerticalScrollBar` / `AXHorizontalScrollBar` attributes for in-page
    /// scrollers.
    static func hasWebAncestor(_ element: AXUIElement) -> Bool {
        var current = element
        for _ in 0..<maxAncestorWalk {
            guard case .success(let role) = AXReader.string(kAXRoleAttribute as CFString, of: current) else {
                return false
            }
            if role == "AXWebArea" {
                return true
            }
            guard case .success(let parent) = AXReader.element(kAXParentAttribute as CFString, of: current) else {
                return false
            }
            current = parent
        }
        return false
    }

    // MARK: - Construction

    /// Build a `ScrollableArea` for `element`, returning `nil` if its frame
    /// can't be read.
    ///
    /// Uses `AXReader.appKitFrame` so the AX → AppKit coordinate flip is
    /// applied consistently with the rest of the codebase.
    static func makeArea(from element: AXUIElement) -> ScrollableArea? {
        guard case .success(let frame) = AXReader.appKitFrame(of: element) else { return nil }
        return ScrollableArea(axElement: element, frame: frame)
    }
}
