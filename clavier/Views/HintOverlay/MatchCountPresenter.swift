//
//  MatchCountPresenter.swift
//  clavier
//
//  Pure mapping from match-count state to the visual style used by the
//  overlay's search bar.
//
//  The count values carry two kinds of signal, matching the existing
//  controller contract:
//   - `-1` — no active search / reset (blue border, empty badge).
//   -  `0` — search produced no matches (red border, "0" badge).
//   -  `1` — single match (green border, green "1" badge — typically the
//            last state the user sees before auto-click fires).
//   -  `n ≥ 2` — multi-match (yellow border, yellow "n" badge).
//
//  Extracted from `HintOverlayWindow.updateMatchCount` so the window can
//  apply a pre-computed `Style` without doing its own color branching,
//  and so the mapping is unit-testable.
//

import AppKit

enum MatchCountPresenter {

    /// Describes the visual state of the match-count badge and its
    /// surrounding search-bar border.
    struct Style: Equatable {
        let labelText: String
        let labelColor: NSColor
        let borderColor: NSColor
    }

    /// Map a raw match count to the badge + border style.
    ///
    /// `-1` is the sentinel for "reset / no search active" — callers pass it
    /// when filters clear or the overlay transitions back to hint-prefix mode.
    static func style(forCount count: Int) -> Style {
        switch count {
        case -1:
            return Style(
                labelText: "",
                labelColor: .systemYellow,
                borderColor: .systemBlue
            )
        case 0:
            return Style(
                labelText: "0",
                labelColor: .systemRed,
                borderColor: .systemRed
            )
        case 1:
            return Style(
                labelText: "1",
                labelColor: .systemGreen,
                borderColor: .systemGreen
            )
        default:
            return Style(
                labelText: "\(count)",
                labelColor: .systemYellow,
                borderColor: .systemYellow
            )
        }
    }
}
