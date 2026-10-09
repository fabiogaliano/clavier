//
//  HintInputReducerSessionCommandTests.swift
//  clavierTests
//
//  Commands the controller sends on its own rather than from a key press:
//  re-running the filter once element text arrives.
//

import XCTest
@testable import clavier

final class HintInputReducerSessionCommandTests: XCTestCase {

    private let dummyAX: AXUIElement = AXUIElementCreateApplication(getpid())

    private func makeHinted(hint: String, text: String = "", x: CGFloat = 0) -> HintedElement {
        let frame = CGRect(x: x, y: 0, width: 40, height: 20)
        let element = UIElement(
            stableID: ElementIdentity(pid: getpid(), role: "AXButton", frame: frame),
            axElement: dummyAX,
            frame: frame,
            visibleFrame: frame,
            role: "AXButton",
            textAttributes: text.isEmpty ? nil : ElementTextAttributes(title: text, label: nil, value: nil, description: nil)
        )
        return HintedElement(element: element, hint: hint)
    }

    private let context = HintInputContext(textSearchEnabled: true, minSearchChars: 2, refreshTrigger: "rr")

    // MARK: - reapplyFilter

    func test_reapplyFilter_afterHydration_findsMatchesTheEarlierPassMissed() {
        let hydrated = [
            makeHinted(hint: "aa", text: "Save", x: 0),
            makeHinted(hint: "as", text: "Save As", x: 50),
            makeHinted(hint: "ad", text: "Cancel", x: 100),
        ]
        let session = HintSession.active(hintedElements: hydrated, filter: "sav", mode: .oneShot)

        let (next, effects) = HintInputReducer.reduce(session: session, command: .reapplyFilter, context: context)

        XCTAssertEqual(next.numberedElements.count, 2)
        XCTAssertEqual(next.filter, "sav")
        XCTAssertTrue(effects.contains { if case .updateMatchCount(2) = $0 { return true } else { return false } })
    }

    func test_reapplyFilter_withEmptyFilter_isNoOp() {
        let session = HintSession.active(hintedElements: [makeHinted(hint: "aa", text: "Save")], filter: "", mode: .oneShot)

        let (next, effects) = HintInputReducer.reduce(session: session, command: .reapplyFilter, context: context)

        XCTAssertEqual(next.filter, "")
        XCTAssertTrue(effects.isEmpty)
    }
}
