//
//  AncestorDedupePolicy.swift
//  clavier
//
//  Frame-match predicate used during clickable-element traversal to decide
//  whether a child clickable should be suppressed because its nearest
//  clickable ancestor already covers the same region.
//
//  Why a dedicated type: the heuristic is pure geometry — no AX calls, no
//  traversal state — so pulling it out lets us unit-test tolerance behavior
//  without building an AX tree.  The walker stays responsible for actually
//  carrying the ancestor and deciding, per node, whether to consult the
//  policy; this type only answers "are these two frames close enough".
//
//  Not @MainActor: no AX APIs are touched.
//

import Foundation

struct AncestorDedupePolicy {

    /// Frames whose edges all lie within this many points are treated as
    /// "the same rectangle" for dedup purposes.  The value mirrors the
    /// legacy inline heuristic and is kept intact to preserve behavior.
    let frameTolerance: CGFloat

    static let `default` = AncestorDedupePolicy(frameTolerance: 10)

    /// True iff every edge of `frame` lies within `frameTolerance` of the
    /// corresponding edge of `ancestorFrame`.
    ///
    /// Equivalent to the inline predicate formerly in AccessibilityService;
    /// factored here so the tolerance contract is a single explicit value
    /// instead of a scattered literal.
    func framesMatch(_ frame: CGRect, _ ancestorFrame: CGRect) -> Bool {
        abs(frame.minX - ancestorFrame.minX) < frameTolerance
            && abs(frame.minY - ancestorFrame.minY) < frameTolerance
            && abs(frame.maxX - ancestorFrame.maxX) < frameTolerance
            && abs(frame.maxY - ancestorFrame.maxY) < frameTolerance
    }
}
