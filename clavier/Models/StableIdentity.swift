//
//  StableIdentity.swift
//  clavier
//
//  Stable identity primitives for discovered UI entities.
//
//  UUIDs assigned at discovery time are transient — they change on every
//  AX traversal pass, which breaks overlay diffing (P3-S1, F06) and
//  progressive-discovery merging (P2-S2, F03).
//
//  `ElementIdentity` and `AreaIdentity` are content-addressed: they hash a
//  combination of pid, role, and rounded screen frame.  Two snapshots of the
//  same real element will produce the same identity as long as the element
//  hasn't moved or resized beyond the rounding tolerance.
//
//  Design constraints honoured:
//  - No AX attribute reads here — callers supply already-decoded values.
//  - Frame rounding uses 1-pt buckets to absorb sub-pixel AX drift without
//    masking real movement.
//  - The types are `Hashable`+`Equatable` so they can be used as dictionary
//    keys in overlay caches (the primary consumer in P3-S1).
//

import Foundation
import AppKit

// MARK: - ElementIdentity

/// Stable identity for a hintable UI element discovered via AX traversal.
///
/// Used in P3-S1 to key hint-overlay view reuse by stable entity rather than
/// by the hint token string (`hintViews: [String: NSView]` → keyed by this).
struct ElementIdentity: Hashable, Equatable, CustomStringConvertible {
    let pid: pid_t
    let role: String
    /// Frame rounded to the nearest point so sub-pixel AX drift doesn't
    /// produce spurious mismatches across progressive discovery passes.
    let roundedFrame: CGRect

    init(pid: pid_t, role: String, frame: CGRect) {
        self.pid = pid
        self.role = role
        self.roundedFrame = frame.rounded()
    }

    /// Convenience: derive pid directly from the AX element.
    init(axElement: AXUIElement, role: String, frame: CGRect) {
        var derivedPid: pid_t = 0
        AXUIElementGetPid(axElement, &derivedPid)
        self.pid = derivedPid
        self.role = role
        self.roundedFrame = frame.rounded()
    }

    var description: String {
        "ElementIdentity(pid:\(pid) role:\(role) frame:\(roundedFrame))"
    }
}

// MARK: - AreaIdentity

/// Stable identity for a scrollable area discovered via AX traversal.
///
/// Parallel to `ElementIdentity` but omits role because scroll areas are
/// identified by geometry alone (multiple AX roles map to the same visible
/// scrollable container, and the frame is the discriminating attribute for
/// merger policy decisions anyway).
///
/// The pid is extracted directly from the AXUIElement via `AXUIElementGetPid`
/// so callers that don't already have pid on hand (e.g. `ChromiumDetector`)
/// don't need it threaded through.
struct AreaIdentity: Hashable, Equatable, CustomStringConvertible {
    let pid: pid_t
    /// Frame rounded to the nearest point.
    let roundedFrame: CGRect

    init(pid: pid_t, frame: CGRect) {
        self.pid = pid
        self.roundedFrame = frame.rounded()
    }

    /// Convenience: derive pid directly from the AX element.
    init(axElement: AXUIElement, frame: CGRect) {
        var derivedPid: pid_t = 0
        AXUIElementGetPid(axElement, &derivedPid)
        self.pid = derivedPid
        self.roundedFrame = frame.rounded()
    }

    var description: String {
        "AreaIdentity(pid:\(pid) frame:\(roundedFrame))"
    }
}

// MARK: - CGRect rounding helper

private extension CGRect {
    /// Round each component to the nearest integer point value.
    ///
    /// This absorbs the sub-pixel AX drift that occurs between traversal passes
    /// without masking genuine movement (an element that moves by 1+ pt will
    /// round to a different bucket).
    func rounded() -> CGRect {
        CGRect(
            x: Foundation.round(origin.x),
            y: Foundation.round(origin.y),
            width: Foundation.round(size.width),
            height: Foundation.round(size.height)
        )
    }
}
