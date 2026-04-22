//
//  NumberedArea.swift
//  clavier
//
//  Presentation wrapper pairing a discovered scrollable area with its
//  session-scoped numeric hint token.
//
//  `ScrollableArea` is the immutable discovery record (no hint field); the
//  presentation number lives here so the domain type stays free of
//  session-scoped display concerns.
//
//  `ScrollSession` makes the controller's session lifecycle explicit,
//  replacing the ad-hoc sentinel-index + bool flag coupling that existed
//  before P3-S2.  Mirrors the HintedElement/HintSession shape from P3-S1.
//

import Foundation

// MARK: - NumberedArea

/// A discovered scrollable area paired with its session-scoped numeric hint.
///
/// Created by `ScrollModeController` during progressive discovery and consumed
/// by `ScrollOverlayWindow` for rendering and identity-keyed overlay diffing.
struct NumberedArea {
    let area: ScrollableArea
    let number: String

    /// Delegates to `area.stableID` — the overlay cache key for this entry.
    var identity: AreaIdentity { area.stableID }
}

// MARK: - ScrollSession

/// Explicit state for the active scroll-mode session.
///
/// Replaces the previous combination of `isActive: Bool`,
/// `areas: [ScrollableArea]`, `selectedAreaIndex: Int` (with sentinel -1),
/// and `currentInput: String`.
///
/// `selected` is an index into `areas`, or `nil` when no area is selected.
/// `pendingInput` accumulates digit characters before commit.
enum ScrollSession {
    case inactive

    /// Normal scroll session: areas discovered, optional selection, pending digit input.
    case active(areas: [NumberedArea], selected: Int?, pendingInput: String)

    // MARK: Convenience accessors

    var isActive: Bool {
        switch self {
        case .inactive: return false
        case .active: return true
        }
    }

    var areas: [NumberedArea] {
        switch self {
        case .inactive: return []
        case .active(let areas, _, _): return areas
        }
    }

    var selectedIndex: Int? {
        switch self {
        case .inactive: return nil
        case .active(_, let selected, _): return selected
        }
    }
}
