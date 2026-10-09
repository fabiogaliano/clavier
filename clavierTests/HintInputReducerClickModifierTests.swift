//
//  HintInputReducerClickModifierTests.swift
//  clavierTests
//
//  The modifier held on the keystroke that completes a selection picks the
//  click verb; on any other keystroke it is ignored.
//

import XCTest
@testable import clavier

final class HintInputReducerClickModifierTests: XCTestCase {

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

    private let verbs: [(ClickModifier, HintClickKind)] = [
        (.none, .primary),
        (.control, .secondary),
        (.shift, .double),
        (.option, .hover)
    ]

    private func performed(_ effects: [HintSideEffect]) -> [(HintClickKind, UIElement)] {
        effects.compactMap { effect in
            if case .perform(let kind, let element) = effect { return (kind, element) }
            return nil
        }
    }

    private func performedKinds(_ effects: [HintSideEffect]) -> [HintClickKind] {
        performed(effects).map(\.0)
    }

    private func reduce(_ session: HintSession, _ command: HintInputCommand) -> (HintSession, [HintSideEffect]) {
        HintInputReducer.reduce(session: session, command: command, context: context)
    }

    private func hintElements() -> [HintedElement] {
        [makeHinted(hint: "as"), makeHinted(hint: "ad", x: 50)]
    }

    private func searchElements() -> [HintedElement] {
        [makeHinted(hint: "as", text: "Save"), makeHinted(hint: "ad", text: "Save As", x: 50)]
    }

    // MARK: - Completing letter

    func test_completingLetter_mapsEachModifierToItsVerb() {
        for (modifier, expected) in verbs {
            let session = HintSession.active(hintedElements: hintElements(), filter: "a", mode: .oneShot)
            let (next, effects) = reduce(session, .character("s", modifier: modifier))
            XCTAssertEqual(performedKinds(effects), [expected], "\(modifier)")
            XCTAssertEqual(next.filter, "", "\(modifier)")
        }
    }

    func test_completingLetter_performsOnTheMatchedElement() {
        let elements = hintElements()
        let session = HintSession.active(hintedElements: elements, filter: "a", mode: .oneShot)
        let (_, effects) = reduce(session, .character("d", modifier: .control))
        XCTAssertEqual(performed(effects).map(\.1), [elements[1].element])
    }

    // MARK: - Non-final letter

    func test_modifierOnNonFinalLetter_isIgnored() {
        for modifier in [ClickModifier.control, .shift, .option] {
            let session = HintSession.active(hintedElements: hintElements(), filter: "", mode: .oneShot)
            let (next, effects) = reduce(session, .character("a", modifier: modifier))
            XCTAssertEqual(next.filter, "a", "\(modifier)")
            XCTAssertTrue(performedKinds(effects).isEmpty, "\(modifier)")
        }
    }

    func test_modifierOnNonFinalLetter_thenPlainCompletion_isAPlainClick() {
        let start = HintSession.active(hintedElements: hintElements(), filter: "", mode: .oneShot)
        let (afterFirst, _) = reduce(start, .character("a", modifier: .shift))
        let (_, effects) = reduce(afterFirst, .character("s"))
        XCTAssertEqual(performedKinds(effects), [.primary])
    }

    func test_modifierOnSearchKeystroke_singleTextMatch_isAPlainClick() {
        let searchable = [makeHinted(hint: "as", text: "Save"), makeHinted(hint: "ad", text: "Open", x: 50)]
        let session = HintSession.active(hintedElements: searchable, filter: "sa", mode: .oneShot)
        let (_, effects) = reduce(session, .character("v", modifier: .shift))
        XCTAssertEqual(performedKinds(effects), [.primary])
    }

    // MARK: - Enter in text search

    func test_enter_mapsModifierToVerbOnFirstMatch() {
        let searchable = searchElements()
        let session = HintSession.textSearch(hintedElements: searchable, matches: searchable, filter: "save", mode: .oneShot)

        for (modifier, expected) in verbs {
            let (_, effects) = reduce(session, .enter(modifier))
            XCTAssertEqual(performedKinds(effects), [expected], "\(modifier)")
            XCTAssertEqual(performed(effects).map(\.1), [searchable[0].element], "\(modifier)")
        }
    }

    // MARK: - Numbered selection

    func test_selectNumbered_mapsModifierToVerb() {
        let searchable = searchElements()
        let numbered = searchable.enumerated().map { HintedElement(element: $1.element, hint: "\($0 + 1)") }
        let session = HintSession.textSearch(hintedElements: searchable, matches: numbered, filter: "save", mode: .continuous)

        for (modifier, expected) in verbs {
            let (_, effects) = reduce(session, .selectNumbered(2, modifier: modifier))
            XCTAssertEqual(performedKinds(effects), [expected], "\(modifier)")
            XCTAssertEqual(performed(effects).map(\.1), [searchable[1].element], "\(modifier)")
        }
    }

    // MARK: - Option release

    func test_clearSearch_withEmptyFilter_isANoOp() {
        // ⌥ release after a ⌥-hover arrives once the filter is already cleared.
        let session = HintSession.active(hintedElements: hintElements(), filter: "", mode: .continuous)
        let (next, effects) = reduce(session, .clearSearch)
        XCTAssertEqual(next.filter, "")
        XCTAssertTrue(effects.isEmpty)
    }

    func test_clearSearch_withFilter_clearsIt() {
        let session = HintSession.active(hintedElements: hintElements(), filter: "a", mode: .continuous)
        let (next, effects) = reduce(session, .clearSearch)
        XCTAssertEqual(next.filter, "")
        XCTAssertFalse(effects.isEmpty)
    }
}
