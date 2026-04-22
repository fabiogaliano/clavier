//
//  UIElement.swift
//  clavier
//
//  Wrapper for accessibility UI elements
//

import Foundation
import AppKit

/// Immutable snapshot of a clickable UI element discovered via AX traversal.
///
/// The core discovery record carries geometry and identity only.  Text
/// attributes (title/label/value/description) are hydrated separately into
/// `textAttributes` via `AXTextHydrator` on the main actor; they are nil
/// until hydration runs.
///
/// Traversal-only bookkeeping (e.g. "nearest clickable ancestor hash" used
/// for dedup) is NOT stored here — it lives in a traversal-local wrapper
/// inside `AccessibilityService` and is collapsed before this value is
/// produced.
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
    /// Frame intersected with the propagated ancestor/screen clip bounds
    /// during AX traversal.  Used as the anchor for hint placement and click
    /// targeting so partially-clipped elements stay reachable.
    let visibleFrame: CGRect
    let role: String
    /// Hydrated lazily after initial display.  `nil` means "not yet loaded";
    /// a non-nil value means hydration has run (fields within may still be
    /// individually nil if the element exposes no AX title/label/value).
    var textAttributes: ElementTextAttributes?

    var centerPoint: CGPoint {
        CGPoint(x: visibleFrame.midX, y: visibleFrame.midY)
    }

    /// Combined searchable text from hydrated text attributes.  Empty string
    /// if hydration has not run or the element exposes no text.
    var searchableText: String {
        textAttributes?.searchableText ?? ""
    }
}
