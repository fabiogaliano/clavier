//
//  ScrollableAreaMerger.swift
//  clavier
//
//  Canonical scroll-area merge/dedupe policy (F03, Phase 1-C gate).
//
//  Both the initial discovery pass in `ScrollableAreaService` and the
//  progressive update pass in `ScrollModeController` contained inline
//  duplicate versions of the same nesting/duplicate/stacking heuristics.
//  This module is the single authoritative implementation.
//
//  P2-S2 will migrate `ScrollModeController.continueProgressiveDiscovery`
//  to call this policy directly, at which point the controller's inline
//  geometry checks can be removed.
//
//  Tolerance constants match those previously scattered across both call
//  sites (service used named Config enum; controller used inline literals).
//

import AppKit

// MARK: - Merge decision

/// The outcome of evaluating a candidate area against the current set.
enum AreaMergeDecision {
    /// The candidate duplicates an existing area — discard it.
    case discard

    /// The candidate is spatially nested inside an existing area in a way
    /// that makes it redundant — discard it.
    case nestedInExisting

    /// The candidate is larger than (and encompasses) one or more existing
    /// areas that should be replaced — remove those and add the candidate.
    case replaceExisting(indicesToRemove: [Int])

    /// The candidate is genuinely independent — add it as-is.
    case add
}

// MARK: - ScrollableAreaMerger

/// Stateless merge-policy evaluator.
///
/// Call `decision(for:against:)` to get a merge decision, then act on it.
/// The caller is responsible for mutating the areas array; this type only
/// computes decisions so it stays testable without side effects.
struct ScrollableAreaMerger {

    // MARK: - Tolerances

    /// Two areas whose corners are all within this distance are considered
    /// duplicates and the incoming one is discarded.
    static let duplicateTolerance: CGFloat = 10

    /// Containment test tolerance — an area is considered "inside" another
    /// if all four edges are within this many points.
    static let nestedTolerance: CGFloat = 5

    /// Threshold for the contained/containing size ratio above which a nested
    /// area is treated as a near-duplicate rather than a distinct sub-area.
    static let nestedSizeThreshold: CGFloat = 0.7

    /// Two areas with origins within this horizontal distance are treated as
    /// sharing the same X-origin, making nesting unconditional regardless of
    /// size ratio.
    static let sameOriginTolerance: CGFloat = 2.0

    // MARK: - Policy

    /// Evaluate whether `candidate` should be added to `existing`.
    ///
    /// The returned decision describes what to do; it never modifies `existing`.
    func decision(for candidate: CGRect, against existing: [CGRect]) -> AreaMergeDecision {
        var indicesToRemove: [Int] = []

        for (index, existingFrame) in existing.enumerated() {
            let rel = relationship(candidate, existingFrame)

            switch rel {
            case .duplicate:
                return .discard

            case .candidateNestedInExisting:
                return .nestedInExisting

            case .existingNestedInCandidate:
                indicesToRemove.append(index)

            case .verticalSections:
                // Same X-origin, same width, different Y — keep the larger one.
                let candidateArea = candidate.width * candidate.height
                let existingArea = existingFrame.width * existingFrame.height
                if candidateArea > existingArea {
                    indicesToRemove.append(index)
                } else {
                    return .discard
                }

            case .independent:
                break
            }
        }

        if indicesToRemove.isEmpty {
            return .add
        }
        return .replaceExisting(indicesToRemove: indicesToRemove)
    }

    // MARK: - Internal geometry classification

    private enum Relationship {
        case duplicate
        case candidateNestedInExisting
        case existingNestedInCandidate
        case verticalSections
        case independent
    }

    private func relationship(_ candidate: CGRect, _ existing: CGRect) -> Relationship {
        // Duplicate: all four corners match within tolerance.
        if abs(candidate.origin.x - existing.origin.x) < Self.duplicateTolerance &&
           abs(candidate.origin.y - existing.origin.y) < Self.duplicateTolerance &&
           abs(candidate.width - existing.width) < Self.duplicateTolerance &&
           abs(candidate.height - existing.height) < Self.duplicateTolerance {
            return .duplicate
        }

        // Candidate nested inside existing.
        if candidate.minX >= existing.minX - Self.nestedTolerance &&
           candidate.maxX <= existing.maxX + Self.nestedTolerance &&
           candidate.minY >= existing.minY - Self.nestedTolerance &&
           candidate.maxY <= existing.maxY + Self.nestedTolerance {

            let sameXOrigin = abs(candidate.origin.x - existing.origin.x) < Self.sameOriginTolerance
            if sameXOrigin {
                return .candidateNestedInExisting
            }

            let candidateArea = candidate.width * candidate.height
            let existingArea = existing.width * existing.height
            if existingArea > 0 && (candidateArea / existingArea) > Self.nestedSizeThreshold {
                return .candidateNestedInExisting
            }
        }

        // Existing nested inside candidate.
        if existing.minX >= candidate.minX - Self.nestedTolerance &&
           existing.maxX <= candidate.maxX + Self.nestedTolerance &&
           existing.minY >= candidate.minY - Self.nestedTolerance &&
           existing.maxY <= candidate.maxY + Self.nestedTolerance {

            let sameXOrigin = abs(candidate.origin.x - existing.origin.x) < Self.sameOriginTolerance
            if sameXOrigin {
                return .existingNestedInCandidate
            }

            let candidateArea = candidate.width * candidate.height
            let existingArea = existing.width * existing.height
            if candidateArea > 0 && (existingArea / candidateArea) > Self.nestedSizeThreshold {
                return .existingNestedInCandidate
            }
        }

        // Vertically stacked sections: same X-origin and width but different Y — keep the larger.
        if abs(candidate.origin.x - existing.origin.x) < Self.duplicateTolerance &&
           abs(candidate.width - existing.width) < Self.duplicateTolerance &&
           abs(candidate.origin.y - existing.origin.y) >= Self.duplicateTolerance {
            return .verticalSections
        }

        return .independent
    }
}
