//
//  ElementTextAttributes.swift
//  clavier
//
//  Hydrated text attributes for a discovered `UIElement`.
//
//  These values come from AX attribute reads (title / accessibility label /
//  value / accessibility description) and are loaded lazily after the hint
//  overlay has painted so traversal latency stays low.  A non-nil
//  `ElementTextAttributes` on a `UIElement` means hydration has run — even
//  if every individual field is nil because the element exposes no text.
//

import Foundation

struct ElementTextAttributes: Equatable {
    let title: String?
    let label: String?
    let value: String?
    let description: String?

    /// Whitespace-joined concatenation of the non-empty text fields.  Used by
    /// hint-mode text search (`HintInputReducer`) to locate elements by
    /// visible or accessibility-exposed text.
    var searchableText: String {
        [title, label, value, description]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
