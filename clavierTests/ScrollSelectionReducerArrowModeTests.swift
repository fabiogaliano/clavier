//
//  ScrollSelectionReducerArrowModeTests.swift
//  clavierTests
//
//  Verifies that the reducer's arrow-key branch routes on the typed
//  `ScrollArrowMode` value rather than a raw string comparison.
//

import XCTest
@testable import clavier

final class ScrollSelectionReducerArrowModeTests: XCTestCase {

    private let dummyAX: AXUIElement = AXUIElementCreateApplication(getpid())

    private func makeArea(_ rect: CGRect = CGRect(x: 0, y: 0, width: 100, height: 100)) -> NumberedArea {
        NumberedArea(area: ScrollableArea(axElement: dummyAX, frame: rect), number: "1")
    }

    private func makeContext(arrow: ScrollArrowMode) -> ScrollInputContext {
        ScrollInputContext(
            scrollKeys: .default,
            arrowMode: arrow,
            scrollSpeed: 5,
            dashSpeed: 9,
            autoDeactivation: false,
            deactivationDelay: 5
        )
    }

    @MainActor
    func test_arrowKey_inSelectMode_selectsNextArea() {
        let areas = [makeArea(), makeArea(.init(x: 0, y: 200, width: 100, height: 100))]
        let session = ScrollSession.active(areas: areas, selected: 0, pendingInput: "")
        let (next, effects) = ScrollSelectionReducer.reduce(
            session: session,
            command: .arrowKey(.down, isShift: false),
            context: makeContext(arrow: .select)
        )
        XCTAssertEqual(next.selectedIndex, 1)
        let selected = effects.contains { if case .selectArea(let i) = $0 { return i == 1 } else { return false } }
        XCTAssertTrue(selected, "expected .selectArea(1) when arrowMode == .select")
    }

    @MainActor
    func test_arrowKey_inScrollMode_performsScroll() {
        let areas = [makeArea()]
        let session = ScrollSession.active(areas: areas, selected: 0, pendingInput: "")
        let (_, effects) = ScrollSelectionReducer.reduce(
            session: session,
            command: .arrowKey(.down, isShift: false),
            context: makeContext(arrow: .scroll)
        )
        let scrolled = effects.contains { if case .performScroll = $0 { return true } else { return false } }
        XCTAssertTrue(scrolled, "expected .performScroll when arrowMode == .scroll")
    }
}
