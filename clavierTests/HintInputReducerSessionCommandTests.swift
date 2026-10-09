//
//  HintInputReducerSessionCommandTests.swift
//  clavierTests
//
//  Commands that don't map to a plain hint keystroke: dismissal (Cmd
//  shortcut, app switch, mouse click) and re-running the filter once
//  element text arrives.
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

    private func isOnlyDeactivate(_ effects: [HintSideEffect]) -> Bool {
        guard effects.count == 1, case .deactivate = effects[0] else { return false }
        return true
    }

    // MARK: - dismiss

    func test_dismiss_fromActiveSession_deactivates() {
        let session = HintSession.active(hintedElements: [makeHinted(hint: "aa")], filter: "", mode: .continuous)

        let (next, effects) = HintInputReducer.reduce(session: session, command: .dismiss, context: context)

        XCTAssertFalse(next.isActive)
        XCTAssertTrue(isOnlyDeactivate(effects))
    }

    func test_dismiss_withTypedFilter_deactivatesInOneStep() {
        // Unlike Escape, leaving the session must not stop at clearing the filter.
        let session = HintSession.active(hintedElements: [makeHinted(hint: "aa")], filter: "a", mode: .oneShot)

        let (next, effects) = HintInputReducer.reduce(session: session, command: .dismiss, context: context)

        XCTAssertFalse(next.isActive)
        XCTAssertTrue(isOnlyDeactivate(effects))
    }

    func test_dismiss_fromTextSearch_deactivates() {
        let elements = [makeHinted(hint: "aa", text: "Save"), makeHinted(hint: "as", text: "Save As", x: 50)]
        let session = HintSession.textSearch(hintedElements: elements, matches: elements, filter: "sav", mode: .oneShot)

        let (next, effects) = HintInputReducer.reduce(session: session, command: .dismiss, context: context)

        XCTAssertFalse(next.isActive)
        XCTAssertTrue(isOnlyDeactivate(effects))
    }

    func test_dismiss_whenInactive_isNoOp() {
        let (next, effects) = HintInputReducer.reduce(session: .inactive, command: .dismiss, context: context)

        XCTAssertFalse(next.isActive)
        XCTAssertTrue(effects.isEmpty)
    }

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
