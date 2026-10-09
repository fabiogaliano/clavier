//
//  ScrollSelectionReducerDiscoveryTests.swift
//  clavierTests
//

import XCTest
@testable import clavier

final class ScrollSelectionReducerDiscoveryTests: XCTestCase {

    private let dummyAX: AXUIElement = AXUIElementCreateApplication(getpid())

    private func area(y: CGFloat) -> ScrollableArea {
        ScrollableArea(axElement: dummyAX, frame: CGRect(x: 0, y: y, width: 100, height: 100))
    }

    private func numbered(_ areas: [ScrollableArea]) -> [NumberedArea] {
        areas.enumerated().map { NumberedArea(area: $0.element, number: "\($0.offset + 1)") }
    }

    private func describe(_ effects: [ScrollSideEffect]) -> [String] {
        effects.map { effect in
            switch effect {
            case .openOverlay: return "open"
            case .addArea(let n): return "add:\(n.number)"
            case .removeArea: return "remove"
            case .updateNumber(_, let number): return "renumber:\(number)"
            case .selectArea(let i): return "select:\(i)"
            case .clearSelection: return "clear"
            case .resetDeactivationTimer: return "timer"
            case .performScroll: return "scroll"
            case .deactivate: return "deactivate"
            }
        }
    }

    // MARK: - Phase 1

    func test_phase1_onInactiveSession_opensAndSelectsFocusedArea() {
        let (next, effects) = ScrollSelectionReducer.reduce(
            session: .inactive,
            discovery: .areaAddedPhase1(area(y: 0))
        )
        XCTAssertEqual(next.areas.map(\.number), ["1"])
        XCTAssertEqual(next.selectedIndex, 0)
        XCTAssertEqual(describe(effects), ["open", "select:0"])
    }

    // MARK: - Phase 2 add

    func test_phase2_firstArea_cursorInside_opensAndSelects() {
        let (next, effects) = ScrollSelectionReducer.reduce(
            session: .inactive,
            discovery: .areaAddedPhase2(area(y: 0), isCursorInside: true)
        )
        XCTAssertEqual(next.selectedIndex, 0)
        XCTAssertEqual(describe(effects), ["open", "select:0"])
    }

    func test_phase2_firstArea_cursorOutside_opensWithoutSelection() {
        let (next, effects) = ScrollSelectionReducer.reduce(
            session: .inactive,
            discovery: .areaAddedPhase2(area(y: 0), isCursorInside: false)
        )
        XCTAssertTrue(next.isActive)
        XCTAssertNil(next.selectedIndex)
        XCTAssertEqual(describe(effects), ["open"])
    }

    func test_phase2_laterArea_appendsWithoutStealingSelection_evenWithCursorInside() {
        let session = ScrollSession.active(areas: numbered([area(y: 0)]), selected: nil, pendingInput: "4")
        let (next, effects) = ScrollSelectionReducer.reduce(
            session: session,
            discovery: .areaAddedPhase2(area(y: 200), isCursorInside: true)
        )
        XCTAssertEqual(next.areas.map(\.number), ["1", "2"])
        XCTAssertNil(next.selectedIndex)
        XCTAssertEqual(describe(effects), ["add:2"])
        guard case .active(_, _, let pending) = next else { return XCTFail("expected active") }
        XCTAssertEqual(pending, "4", "discovery must not discard digits the user is typing")
    }

    // MARK: - Replacement

    func test_replaced_onInactiveSession_isIgnored() {
        let (next, effects) = ScrollSelectionReducer.reduce(
            session: .inactive,
            discovery: .areaReplaced(area(y: 0), replacedIndices: [0], isCursorInside: true)
        )
        XCTAssertFalse(next.isActive)
        XCTAssertTrue(effects.isEmpty)
    }

    func test_replaced_removesAndRenumbersContiguously() {
        let a = area(y: 0), b = area(y: 200), c = area(y: 400)
        let session = ScrollSession.active(areas: numbered([a, b, c]), selected: 2, pendingInput: "")
        let replacement = area(y: 600)

        let (next, effects) = ScrollSelectionReducer.reduce(
            session: session,
            discovery: .areaReplaced(replacement, replacedIndices: [0], isCursorInside: false)
        )

        XCTAssertEqual(next.areas.map(\.number), ["1", "2", "3"])
        XCTAssertEqual(next.areas.map(\.identity), [b.stableID, c.stableID, replacement.stableID])
        XCTAssertEqual(next.selectedIndex, 1, "selection follows its area when an earlier one is removed")
        XCTAssertEqual(describe(effects), ["remove", "renumber:1", "renumber:2", "add:3"])
    }

    func test_replaced_selectedArea_clearsSelection_andSelectsReplacementUnderCursor() {
        let a = area(y: 0), b = area(y: 200)
        let session = ScrollSession.active(areas: numbered([a, b]), selected: 1, pendingInput: "")

        let (next, effects) = ScrollSelectionReducer.reduce(
            session: session,
            discovery: .areaReplaced(area(y: 400), replacedIndices: [1], isCursorInside: true)
        )

        XCTAssertEqual(next.areas.count, 2)
        XCTAssertEqual(next.selectedIndex, 1)
        XCTAssertEqual(describe(effects), ["remove", "add:2", "select:1"])
    }

    func test_replaced_keepsExistingSelection_whenCursorInsideReplacement() {
        let a = area(y: 0), b = area(y: 200)
        let session = ScrollSession.active(areas: numbered([a, b]), selected: 0, pendingInput: "")

        let (next, effects) = ScrollSelectionReducer.reduce(
            session: session,
            discovery: .areaReplaced(area(y: 400), replacedIndices: [1], isCursorInside: true)
        )

        XCTAssertEqual(next.selectedIndex, 0)
        XCTAssertEqual(describe(effects), ["remove", "add:2"])
    }

    func test_replaced_multipleIndices_removesHighestFirst() {
        let a = area(y: 0), b = area(y: 200), c = area(y: 400)
        let session = ScrollSession.active(areas: numbered([a, b, c]), selected: nil, pendingInput: "")
        let replacement = area(y: 600)

        let (next, effects) = ScrollSelectionReducer.reduce(
            session: session,
            discovery: .areaReplaced(replacement, replacedIndices: [0, 2], isCursorInside: false)
        )

        XCTAssertEqual(next.areas.map(\.identity), [b.stableID, replacement.stableID])
        XCTAssertEqual(next.areas.map(\.number), ["1", "2"])
        let removed = effects.compactMap { if case .removeArea(let id) = $0 { return id } else { return nil } }
        XCTAssertEqual(removed, [c.stableID, a.stableID])
    }
}
