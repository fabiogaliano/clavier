//
//  ScrollSelectionReducerDismissTests.swift
//  clavierTests
//
//  Leaving scroll mode (Cmd shortcut, app switch, mouse click) ends the
//  session regardless of selection or half-typed area numbers.
//

import XCTest
@testable import clavier

final class ScrollSelectionReducerDismissTests: XCTestCase {

    private let dummyAX: AXUIElement = AXUIElementCreateApplication(getpid())

    private let context = ScrollInputContext(
        scrollKeys: .default,
        arrowMode: .select,
        scrollSpeed: 5,
        dashSpeed: 9,
        autoDeactivation: false,
        deactivationDelay: 5
    )

    private func makeArea() -> NumberedArea {
        NumberedArea(area: ScrollableArea(axElement: dummyAX, frame: CGRect(x: 0, y: 0, width: 100, height: 100)), number: "1")
    }

    func test_dismiss_withSelectionAndPendingInput_deactivates() {
        let session = ScrollSession.active(areas: [makeArea()], selected: 0, pendingInput: "1")

        let (next, effects) = ScrollSelectionReducer.reduce(session: session, command: .dismiss, context: context)

        XCTAssertFalse(next.isActive)
        XCTAssertEqual(effects.count, 1)
        guard case .deactivate = effects.first else {
            return XCTFail("expected .deactivate, got \(String(describing: effects.first))")
        }
    }

    func test_dismiss_whenInactive_isNoOp() {
        let (next, effects) = ScrollSelectionReducer.reduce(session: .inactive, command: .dismiss, context: context)

        XCTAssertFalse(next.isActive)
        XCTAssertTrue(effects.isEmpty)
    }
}
