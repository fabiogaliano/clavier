//
//  UIElement.swift
//  clavier
//
//  Wrapper for accessibility UI elements
//

import Foundation
import AppKit

struct UIElement: Identifiable {
    /// Transient id retained for `Identifiable` conformance required by
    /// SwiftUI/ForEach.  Overlay diff and deduplication must use `stableID`
    /// rather than this value — see `ElementIdentity` in `StableIdentity.swift`.
    let id = UUID()
    /// Stable content-addressed identity for overlay diffing (P3-S1) and
    /// cross-pass deduplication.  Derived from pid, role, and rounded frame.
    let stableID: ElementIdentity
    let axElement: AXUIElement
    let frame: CGRect
    // Frame intersected with the propagated ancestor/screen clip bounds during
    // AX traversal. Used as the anchor for hint placement and click targeting
    // so partially-clipped elements stay reachable.
    let visibleFrame: CGRect
    let role: String
    // Hash of nearest clickable ancestor (for deduplication)
    var clickableAncestorHash: Int? = nil
    // All text attributes loaded asynchronously after initial display
    var title: String?
    var label: String?
    var value: String?
    var elementDescription: String?
    var textAttributesLoaded: Bool = false

    var centerPoint: CGPoint {
        CGPoint(x: visibleFrame.midX, y: visibleFrame.midY)
    }

    /// Combined searchable text from all text properties
    var searchableText: String {
        [title, label, value, elementDescription]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
