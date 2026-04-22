//
//  ScrollableAreaTraverser.swift
//  clavier
//
//  Phase 2 of two-phase scroll-area discovery: depth-bounded traversal of an
//  AX window tree, accepting elements that pass the scroll-area predicate
//  and reach the minimum size, with merge deduplication via
//  `ScrollableAreaMerger`.
//
//  Previously embedded as `ScrollableAreaService.traverseElement(...)` with
//  five `inout` parameters threading state through the recursion. Lifting
//  the recursion into a dedicated type lets the recursion close over a small
//  state record instead of passing it explicitly.
//

import AppKit

/// Generic scrollable-area traversal driven by `ScrollableAXProbe`.
///
/// Owns the merge policy for the duration of a single `traverse` call; the
/// caller (`ScrollableAreaService`) provides the merger so progressive
/// discovery can converge on the same instance as the controller.
@MainActor
final class ScrollableAreaTraverser {

    /// Minimum side length in points for a discovered area to be accepted.
    /// Origin checks are intentionally omitted because secondary displays
    /// can have negative AppKit coordinates (screens to the left of or
    /// below the main display).
    static let minimumAreaSize: CGFloat = 100

    /// Default depth cap. Mirrors the previous inline literal.
    static let defaultMaxDepth = 10

    private let merger: ScrollableAreaMerger
    private let maxDepth: Int

    init(merger: ScrollableAreaMerger, maxDepth: Int = ScrollableAreaTraverser.defaultMaxDepth) {
        self.merger = merger
        self.maxDepth = maxDepth
    }

    /// Walk `windows` and return all scrollable areas found.
    ///
    /// - Parameters:
    ///   - windows: AX windows to descend into.
    ///   - onAreaFound: Progressive callback fired on each accepted area.
    ///   - maxAreas: Optional cap; traversal stops once reached.
    func traverse(
        windows: [AXUIElement],
        onAreaFound: ((ScrollableArea) -> Void)? = nil,
        maxAreas: Int? = nil
    ) -> [ScrollableArea] {
        var state = TraversalState(maxAreas: maxAreas)
        for window in windows {
            if state.shouldStop { break }
            descend(into: window, depth: 0, state: &state, onAreaFound: onAreaFound)
        }
        return state.areas
    }

    // MARK: - Internals

    private struct TraversalState {
        var areas: [ScrollableArea] = []
        var shouldStop = false
        let maxAreas: Int?

        var atCap: Bool {
            guard let max = maxAreas else { return false }
            return areas.count >= max
        }
    }

    private func descend(
        into element: AXUIElement,
        depth: Int,
        state: inout TraversalState,
        onAreaFound: ((ScrollableArea) -> Void)?
    ) {
        if state.shouldStop { return }
        if state.atCap {
            state.shouldStop = true
            return
        }
        guard depth < maxDepth else { return }

        guard case .success(let role) = AXReader.string(kAXRoleAttribute as CFString, of: element) else {
            return
        }

        let hasScrollableRole = ScrollableAXProbe.scrollableRoles.contains(role)
        let hasEnabledScrollBars = ScrollableAXProbe.hasScrollBars(element, validateEnabled: true)

        if hasScrollableRole || hasEnabledScrollBars {
            // Scrollable roles without native scroll-bar validation are accepted only
            // when the element is web content — WebKit doesn't expose AXVerticalScrollBar
            // / AXHorizontalScrollBar for in-page scrollers.
            let webExempted = hasScrollableRole && !hasEnabledScrollBars && ScrollableAXProbe.hasWebAncestor(element)
            let acceptable = hasEnabledScrollBars || webExempted

            if acceptable, let area = ScrollableAXProbe.makeArea(from: element),
               area.frame.width > Self.minimumAreaSize,
               area.frame.height > Self.minimumAreaSize {
                tryAccept(area, state: &state, onAreaFound: onAreaFound)
                if state.shouldStop { return }
            }
        }

        guard case .success(let children) = AXReader.elements(kAXChildrenAttribute as CFString, of: element) else {
            return
        }

        for child in children {
            if state.shouldStop { return }
            descend(into: child, depth: depth + 1, state: &state, onAreaFound: onAreaFound)
        }
    }

    /// Apply the merge policy against `state.areas` and append on `.add` /
    /// `.replaceExisting`. Mirrors the old `shouldAddArea` gate.
    private func tryAccept(
        _ area: ScrollableArea,
        state: inout TraversalState,
        onAreaFound: ((ScrollableArea) -> Void)?
    ) {
        let decision = merger.decision(for: area.frame, against: state.areas.map(\.frame))

        switch decision {
        case .discard, .nestedInExisting:
            return

        case .replaceExisting(let indices):
            for index in indices.sorted().reversed() {
                state.areas.remove(at: index)
            }
            state.areas.append(area)
            onAreaFound?(area)

        case .add:
            state.areas.append(area)
            onAreaFound?(area)
        }

        if state.atCap {
            state.shouldStop = true
        }
    }
}
