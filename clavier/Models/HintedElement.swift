//
//  HintedElement.swift
//  clavier
//
//  Presentation wrapper pairing a discovered domain entity with its assigned
//  hint token for a single hint-mode session.
//
//  `UIElement` is the immutable discovery record (no hint field); hint assignment
//  is expressed here so the domain type stays free of presentation concerns.
//
//  `HintSession` makes the controller's session lifecycle state explicit,
//  replacing the ad-hoc bool+array coupling that existed before P3-S1.
//

import Foundation

// MARK: - HintedElement

/// A discovered UI element paired with its session-scoped hint token.
///
/// Created by `HintModeController.assignHints()` and consumed by
/// `HintOverlayWindow` for rendering and diff-keying.
struct HintedElement: Equatable {
    var element: UIElement
    let hint: String

    /// Delegates to `element.stableID` — the overlay cache key for this entry.
    var identity: ElementIdentity { element.stableID }
}

// MARK: - HintSession

/// Explicit state for the active hint-mode session.
///
/// Replaces the previous ad-hoc combination of `isActive: Bool`,
/// `hintedElements: [HintedElement]`, `currentInput: String`,
/// `isTextSearchMode: Bool`, and `numberedElements: [HintedElement]`.
enum HintSessionMode {
    case oneShot
    case continuous
}

enum HintSession {
    case inactive

    /// Normal hint-prefix-matching state.
    case active(hintedElements: [HintedElement], filter: String, mode: HintSessionMode)

    /// Text-search sub-mode: a numbered subset of elements matched by text.
    case textSearch(hintedElements: [HintedElement], matches: [HintedElement], filter: String, mode: HintSessionMode)

    // MARK: Convenience accessors

    var isActive: Bool {
        switch self {
        case .inactive: return false
        case .active, .textSearch: return true
        }
    }

    var hintedElements: [HintedElement] {
        switch self {
        case .inactive: return []
        case .active(let elements, _, _): return elements
        case .textSearch(let elements, _, _, _): return elements
        }
    }

    var filter: String {
        switch self {
        case .inactive: return ""
        case .active(_, let filter, _): return filter
        case .textSearch(_, _, let filter, _): return filter
        }
    }

    var numberedElements: [HintedElement] {
        switch self {
        case .inactive, .active: return []
        case .textSearch(_, let matches, _, _): return matches
        }
    }

    var mode: HintSessionMode {
        switch self {
        case .inactive: return .oneShot
        case .active(_, _, let mode), .textSearch(_, _, _, let mode): return mode
        }
    }

    var isContinuous: Bool {
        mode == .continuous
    }

}
