//
//  ScrollDiscoveryCoordinator.swift
//  clavier
//
//  Two-phase scroll area discovery lifecycle.
//
//  Phase 1: fast focused-area check via `ScrollableAreaService.findFocusedScrollableArea()`.
//  Phase 2: progressive full traversal via `ScrollableAreaService.getScrollableAreas(onAreaFound:)`.
//
//  The coordinator owns the cross-wave merger decisions so the controller doesn't
//  need to re-implement merge logic for progressive discovery.  Each decision fires
//  the appropriate callback on the controller.
//
//  Conforms to `ModeCoordinator` (P4-S1) as the async/discovery lifecycle owner
//  for scroll mode — mirrors `HintRefreshCoordinator`'s role in hint mode.
//

import Foundation
import AppKit

// MARK: - Discovery events

/// Structured event from the discovery coordinator to the controller.
///
/// The controller switches over each event and mutates its session accordingly.
enum DiscoveryEvent {
    /// The focused area was found in Phase 1.  The controller always auto-selects it,
    /// regardless of cursor position — mirroring the original Phase 1 behavior.
    case areaAddedPhase1(ScrollableArea)
    /// A brand-new area was found during Phase 2 progressive traversal.
    /// The controller auto-selects only when the cursor is inside it.
    case areaAddedPhase2(ScrollableArea, isCursorInside: Bool)
    /// This area supersedes one or more existing areas.  The controller must
    /// remove the areas at `replacedIndices` from its session, then add the new area.
    case areaReplaced(ScrollableArea, replacedIndices: [Int], isCursorInside: Bool)
}

// MARK: - Coordinator

/// Owns two-phase activation and cross-wave merger deduplication for scroll mode.
///
/// The controller creates one instance and calls `discover(onEvent:)` at each
/// activation.  All merger decisions are made here against a local frame list that
/// mirrors the controller's session state — the controller updates its session in
/// response to each event.
@MainActor
final class ScrollDiscoveryCoordinator: ModeCoordinator {

    private let service: ScrollableAreaService
    private let merger: ScrollableAreaMerger

    private static let maxAreas = 15

    init(service: ScrollableAreaService, merger: ScrollableAreaMerger) {
        self.service = service
        self.merger = merger
    }

    // MARK: - Public API

    /// Run two-phase discovery, firing `onEvent` for each decision on the main actor.
    ///
    /// - Parameter onEvent: Called once per merge decision in discovery order.
    ///   The controller must apply the session mutations implied by each event before
    ///   the next event fires (this is safe because `getScrollableAreas` is synchronous
    ///   on the main actor and yields between areas via the run loop, not via Task).
    func discover(onEvent: @escaping @MainActor (DiscoveryEvent) -> Void) {
        // Cross-wave frame list: seeds with Phase 1 result so Phase 2 can deduplicate against it.
        var crossWaveFrames: [CGRect] = []
        var areasFound = 0

        // Phase 1: fast focus check — always auto-selects on the controller side.
        if let focused = service.findFocusedScrollableArea() {
            crossWaveFrames.append(focused.frame)
            areasFound += 1
            onEvent(.areaAddedPhase1(focused))
        }

        // Phase 2: full progressive traversal with cross-wave deduplication.
        _ = service.getScrollableAreas(
            onAreaFound: { [weak self] area in
                guard let self else { return }
                guard areasFound < Self.maxAreas else { return }

                let decision = self.merger.decision(for: area.frame, against: crossWaveFrames)

                switch decision {
                case .discard, .nestedInExisting:
                    return

                case .replaceExisting(let indices):
                    for index in indices.sorted().reversed() {
                        crossWaveFrames.remove(at: index)
                        areasFound -= 1
                    }
                    crossWaveFrames.append(area.frame)
                    areasFound += 1
                    let isCursor = NSEvent.mouseLocation.inside(area.frame)
                    onEvent(.areaReplaced(area, replacedIndices: indices, isCursorInside: isCursor))

                case .add:
                    guard areasFound < Self.maxAreas else { return }
                    crossWaveFrames.append(area.frame)
                    areasFound += 1
                    let isCursor = NSEvent.mouseLocation.inside(area.frame)
                    onEvent(.areaAddedPhase2(area, isCursorInside: isCursor))
                }
            },
            maxAreas: Self.maxAreas
        )
    }
}

// MARK: - CGPoint helper

private extension CGPoint {
    func inside(_ rect: CGRect) -> Bool {
        rect.contains(self)
    }
}
