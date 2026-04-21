//
//  ScrollableArea.swift
//  clavier
//
//  Wrapper for scrollable UI elements
//

import Foundation
import AppKit

struct ScrollableArea: Identifiable {
    /// Transient id retained for `Identifiable` conformance required by
    /// SwiftUI/ForEach.  Merge deduplication and overlay diffing must use
    /// `stableID` — see `AreaIdentity` in `StableIdentity.swift`.
    let id = UUID()
    /// Stable content-addressed identity for merge deduplication (P2-S2) and
    /// overlay diffing (P3-S2).  Pid is derived from the AXUIElement directly.
    let stableID: AreaIdentity
    let axElement: AXUIElement
    let frame: CGRect
    var hint: String = ""

    init(axElement: AXUIElement, frame: CGRect) {
        self.stableID = AreaIdentity(axElement: axElement, frame: frame)
        self.axElement = axElement
        self.frame = frame
    }

    var centerPoint: CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }
}
