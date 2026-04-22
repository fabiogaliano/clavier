//
//  HintInputReducerHidePrefixTests.swift
//  clavierTests
//
//  Reducer tests for the hide-labels-while-searching prefix feature.
//

import XCTest
@testable import clavier

@MainActor
final class HintInputReducerHidePrefixTests: XCTestCase {

    private let dummyAX: AXUIElement = AXUIElementCreateApplication(getpid())

    private func makeHinted(hint: String, text: String) -> HintedElement {
        let frame = CGRect(x: 0, y: 0, width: 40, height: 20)
        let element = UIElement(
            stableID: ElementIdentity(pid: getpid(), role: "AXButton", frame: frame),
            axElement: dummyAX,
            frame: frame,
            visibleFrame: frame,
            role: "AXButton",
            textAttributes: ElementTextAttributes(title: text, label: nil, value: nil, description: nil)
        )
        return HintedElement(element: element, hint: hint)
    }

    private func makeContext(
        minSearchChars: Int = 2,
        trigger: String = "rr",
        prefix: String = ">"
    ) -> HintInputContext {
        HintInputContext(
            textSearchEnabled: true,
            minSearchChars: minSearchChars,
            refreshTrigger: trigger,
            hidePrefix: prefix
        )
    }

    // MARK: - Pure helpers

    func test_isHidePrefixActive_requiresNonEmptyPrefixAndLeadingMatch() {
        let active = makeContext(prefix: ">")
        let disabled = makeContext(prefix: "")

        XCTAssertTrue(HintInputReducer.isHidePrefixActive(">google", context: active))
        XCTAssertFalse(HintInputReducer.isHidePrefixActive("google", context: active))
        XCTAssertFalse(HintInputReducer.isHidePrefixActive("g>oogle", context: active))
        XCTAssertFalse(HintInputReducer.isHidePrefixActive(">google", context: disabled))
    }

    func test_effectiveFilter_stripsPrefixWhenActive() {
        let ctx = makeContext(prefix: ">")
        XCTAssertEqual(HintInputReducer.effectiveFilter(">google", context: ctx), "google")
        XCTAssertEqual(HintInputReducer.effectiveFilter(">", context: ctx), "")
        XCTAssertEqual(HintInputReducer.effectiveFilter("google", context: ctx), "google")
    }

    // MARK: - Integration through reduce

    func test_typingPrefixFirstCharacter_hidesLabelsButDoesNotMatchYet() {
        let elements = [
            makeHinted(hint: "aa", text: "Google"),
            makeHinted(hint: "ab", text: "Search"),
        ]
        let session = HintSession.active(hintedElements: elements, filter: "")

        let (next, effects) = HintInputReducer.reduce(
            session: session,
            command: .character(">"),
            context: makeContext()
        )

        XCTAssertEqual(next.filter, ">")
        XCTAssertTrue(effects.contains { if case .setLabelsHidden(true) = $0 { return true } else { return false } })
    }

    func test_hidePrefixQuery_matchesSameAsPlainQuery() {
        let elements = [
            makeHinted(hint: "aa", text: "Google Search"),
            makeHinted(hint: "ab", text: "Bing Search"),
        ]

        let plain = HintSession.active(hintedElements: elements, filter: "googl")
        let (plainNext, _) = HintInputReducer.reduce(
            session: plain, command: .character("e"),
            context: makeContext()
        )

        let hidden = HintSession.active(hintedElements: elements, filter: ">googl")
        let (hiddenNext, hiddenEffects) = HintInputReducer.reduce(
            session: hidden, command: .character("e"),
            context: makeContext()
        )

        // Both queries should end at the same click/selection outcome (single match)
        // and therefore collapse to .active with empty filter after the click.
        XCTAssertEqual(plainNext.filter, hiddenNext.filter, "hidden-prefix query must converge on same session as plain query")
        XCTAssertTrue(hiddenEffects.contains { if case .performClick = $0 { return true } else { return false } })
    }

    func test_backspacePastPrefix_emitsLabelsVisibleAgain() {
        let elements = [makeHinted(hint: "aa", text: "Item")]
        let session = HintSession.active(hintedElements: elements, filter: ">")

        let (next, effects) = HintInputReducer.reduce(
            session: session, command: .backspace,
            context: makeContext()
        )

        XCTAssertEqual(next.filter, "")
        XCTAssertTrue(effects.contains { if case .setLabelsHidden(false) = $0 { return true } else { return false } })
    }

    func test_escapeFromHiddenMode_restoresLabels() {
        let elements = [makeHinted(hint: "aa", text: "Alpha")]
        let session = HintSession.active(hintedElements: elements, filter: ">alp")

        let (next, effects) = HintInputReducer.reduce(
            session: session, command: .escape,
            context: makeContext()
        )

        XCTAssertEqual(next.filter, "")
        XCTAssertTrue(next.isActive)
        XCTAssertTrue(effects.contains { if case .setLabelsHidden(false) = $0 { return true } else { return false } })
    }

    func test_disabledPrefix_behavesAsStandardCharacter() {
        let elements = [makeHinted(hint: "aa", text: "Item")]
        let session = HintSession.active(hintedElements: elements, filter: "")

        // With prefix empty, the configured character is not a prefix marker,
        // so the character goes through standard filter insertion.  `-` is
        // already allowed by the decoder whitelist; we verify via the reducer.
        let (next, effects) = HintInputReducer.reduce(
            session: session, command: .character("-"),
            context: makeContext(prefix: "")
        )

        XCTAssertEqual(next.filter, "-")
        // Disabled → labels must NOT be reported hidden.
        XCTAssertTrue(effects.contains { if case .setLabelsHidden(false) = $0 { return true } else { return false } })
    }

    func test_hidePrefixDoesNotTriggerHintTokenMatchWithSameCharacters() {
        // Hint alphabet could theoretically include the prefix but the
        // sanitizer forbids letters/digits.  Still, verify hide-mode
        // disables exact-hint matching so `>ad` doesn't misfire on hint "ad".
        let elements = [makeHinted(hint: "ad", text: "Address Bar")]
        let session = HintSession.active(hintedElements: elements, filter: ">a")
        let (_, effects) = HintInputReducer.reduce(
            session: session, command: .character("d"),
            context: makeContext()
        )

        // "ad" in hide-mode should behave as a text search, not a hint click.
        // Given the element contains "Address" in its title, text search fires
        // and clicks it (single match).  The important invariant is: the
        // click comes from text search, not from the hint-token branch
        // (which would have fired even without `textAttributes`).  We check
        // by ensuring `setLabelsHidden(false)` precedes the click (text-search
        // single-match path) rather than the exact-hint branch.
        var sawRestore = false
        for effect in effects {
            if case .setLabelsHidden(false) = effect { sawRestore = true }
            if case .performClick = effect {
                XCTAssertTrue(sawRestore, "hide-mode must restore labels on match before clicking")
                return
            }
        }
        XCTFail("expected a click effect for single-match text search")
    }
}
