//
//  MatchCountPresenter.swift
//  clavier
//
//  Pure mapping from match-count state to the bar's count segment.
//
//   - `-1` — no active search: no segment.
//   -  `0` — search produced no matches: red "0".
//   -  `n ≥ 1` — blue "n", the same tint whether one or many match, so the
//            segment reads as information rather than a warning.
//

import AppKit

enum MatchCountPresenter {

    struct Style: Equatable {
        /// Empty means "draw no count segment".
        let labelText: String
        let labelColor: NSColor
    }

    /// `isHydrating`: element text is still being read, so a zero count only
    /// means "not known yet" and must not flash the red no-match state.
    static func style(forCount count: Int, isHydrating: Bool = false) -> Style {
        if count == 0 && isHydrating {
            return Style(labelText: "…", labelColor: .secondaryLabelColor)
        }
        switch count {
        case ..<0:
            return Style(labelText: "", labelColor: .secondaryLabelColor)
        case 0:
            return Style(labelText: "0", labelColor: .systemRed)
        default:
            return Style(labelText: "\(count)", labelColor: .systemBlue)
        }
    }
}
