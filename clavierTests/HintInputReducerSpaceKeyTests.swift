//
//  HintInputReducerSpaceKeyTests.swift
//  clavierTests
//
//  Verifies the Space-key reducer semantics:
//    - empty filter     → .rotateOverlap side effect, session unchanged
//    - non-empty filter → Space appends as " " character (preserves
//                         multi-word text search behaviour)
//

import XCTest
@testable import clavier

@MainActor
final class HintInputReducerSpaceKeyTests: XCTestCase {

    private let dummyAX: AXUIElement = AXUIElementCreateApplication(getpid())

    private func makeHinted(hint: String, text: String = "") -> HintedElement {
        let frame = CGRect(x: 0, y: 0, width: 40, height: 20)
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

    private func makeContext(minSearchChars: Int = 2, trigger: String = "rr") -> HintInputContext {
        HintInputContext(
            textSearchEnabled: true,
            minSearchChars: minSearchChars,
            refreshTrigger: trigger
        )
    }

    func test_spaceKey_withEmptyFilter_producesRotateOverlapAndKeepsSession() {
        let elements = [makeHinted(hint: "aa"), makeHinted(hint: "ab")]
        let session = HintSession.active(hintedElements: elements, filter: "")

        let (next, effects) = HintInputReducer.reduce(
            session: session,
            command: .spaceKey,
            context: makeContext()
        )

        XCTAssertEqual(next.filter, "", "session state must be unchanged by overlap rotation")
        XCTAssertTrue(next.isActive)
        XCTAssertEqual(effects.count, 1)
        if case .rotateOverlap = effects.first {
            // Expected.
        } else {
            XCTFail("expected .rotateOverlap, got \(String(describing: effects.first))")
        }
    }

    func test_spaceKey_withNonEmptyFilter_appendsSpaceCharacter() {
        let elements = [
            makeHinted(hint: "aa", text: "Search Box"),
            makeHinted(hint: "ab", text: "Search Button"),
        ]
        let session = HintSession.active(hintedElements: elements, filter: "search")

        let (next, _) = HintInputReducer.reduce(
            session: session,
            command: .spaceKey,
            context: makeContext()
        )

        XCTAssertEqual(next.filter, "search ", "space must extend the filter when non-empty")
        XCTAssertFalse(effectsContainRotate(HintInputReducer.reduce(
            session: session, command: .spaceKey, context: makeContext()
        ).1))
    }

    func test_spaceKey_whenInactive_isNoOp() {
        let (next, effects) = HintInputReducer.reduce(
            session: .inactive,
            command: .spaceKey,
            context: makeContext()
        )
        XCTAssertFalse(next.isActive)
        XCTAssertTrue(effects.isEmpty)
    }

    // MARK: - Helpers

    private func effectsContainRotate(_ effects: [HintSideEffect]) -> Bool {
        effects.contains { if case .rotateOverlap = $0 { return true } else { return false } }
    }
}
