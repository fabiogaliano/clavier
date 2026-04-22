//
//  HintDiscoveryTracer.swift
//  clavier
//
//  Observation hook for the AX-tree walk performed during hint-mode
//  discovery.  Production code walks with tracer == nil, which is the
//  zero-overhead path.  Debug mode installs a recorder that captures one
//  event per visited node: role, frame, enabled, clickability decision,
//  final outcome, parent/ancestor linkage, and whether the walker
//  descended into its children.
//
//  This module is read both to power the visual debug overlay and to
//  produce the JSON snapshot Claude reads back from the user.
//

import Foundation
import AppKit
import ApplicationServices

/// One record per AX element the walker actually visited.
///
/// Nodes clipped off-screen appear here with `outcome == .clippedOffscreen`
/// so the snapshot captures "we reached this rect but stopped".  Nodes
/// under a pruned subtree do NOT appear — the walker never visits them.
struct HintDiscoveryEvent {
    let id: Int
    let parentId: Int?
    let depth: Int
    let role: String
    let roleDescription: String?
    let title: String?
    let label: String?
    let value: String?
    let description: String?
    let frameAX: CGRect
    let frameAppKit: CGRect
    let enabled: Bool?
    /// Verdict from `ClickabilityPolicy.evaluate` (role/enabled/static-text
    /// rules).  Independent of outcome: an element can be clickable but
    /// still end up rejected by dedup / min-size filters.
    let decision: ClickabilityPolicy.Decision
    let outcome: Outcome
    /// When `outcome == .acceptedDeduped`, the `id` of the clickable
    /// ancestor whose frame matched within `AncestorDedupePolicy`.
    let ancestorId: Int?
    /// False when the subtree was intentionally skipped via
    /// `skipSubtreeRoles`, or when the node was clipped off-screen (no
    /// recursion happens in either case).
    let childrenVisited: Bool

    enum Outcome: String, Encodable {
        case clippedOffscreen
        case accepted
        case acceptedDeduped
        case rejectedTooSmall
        case rejectedNotClickable
    }
}

/// Class-based tracer so recursive walker calls share one assignment
/// source for sequential ids.  `@MainActor` because the walker is — we
/// never touch this off the main thread.
@MainActor
final class HintDiscoveryRecorder {
    private(set) var events: [HintDiscoveryEvent] = []

    @discardableResult
    func record(
        parentId: Int?,
        depth: Int,
        role: String,
        roleDescription: String? = nil,
        title: String? = nil,
        label: String? = nil,
        value: String? = nil,
        description: String? = nil,
        frameAX: CGRect,
        frameAppKit: CGRect,
        enabled: Bool?,
        decision: ClickabilityPolicy.Decision,
        outcome: HintDiscoveryEvent.Outcome,
        ancestorId: Int? = nil,
        childrenVisited: Bool
    ) -> Int {
        let id = events.count
        events.append(
            HintDiscoveryEvent(
                id: id,
                parentId: parentId,
                depth: depth,
                role: role,
                roleDescription: roleDescription,
                title: title,
                label: label,
                value: value,
                description: description,
                frameAX: frameAX,
                frameAppKit: frameAppKit,
                enabled: enabled,
                decision: decision,
                outcome: outcome,
                ancestorId: ancestorId,
                childrenVisited: childrenVisited
            )
        )
        return id
    }

    /// Summary counts for the JSON snapshot header.  Computed lazily so
    /// callers don't pay the aggregation cost if they only want `events`.
    func summary() -> Summary {
        var s = Summary()
        for e in events {
            s.visited += 1
            switch e.outcome {
            case .clippedOffscreen: s.clipped += 1
            case .accepted: s.accepted += 1
            case .acceptedDeduped: s.deduped += 1
            case .rejectedTooSmall: s.rejectedTooSmall += 1
            case .rejectedNotClickable: s.rejectedNotClickable += 1
            }
            if !e.childrenVisited && e.outcome != .clippedOffscreen {
                s.prunedSubtrees += 1
            }
        }
        return s
    }

    struct Summary {
        var visited = 0
        var accepted = 0
        var deduped = 0
        var rejectedTooSmall = 0
        var rejectedNotClickable = 0
        var clipped = 0
        var prunedSubtrees = 0
    }
}
