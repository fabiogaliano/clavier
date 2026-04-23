//
//  ClickabilityPolicyTests.swift
//  clavierTests
//
//  Role-table coverage for ClickabilityPolicy.  The `isClickable(role:
//  element:enabled:)` variant needs a live AXUIElement for the
//  AXStaticText branch (it calls AXUIElementCopyActionNames), so we test
//  the pure `interactiveByRole` companion + `canPruneSubtree` here and
//  leave the action-probe branch to integration coverage.
//

import XCTest
@testable import clavier
import ApplicationServices

@MainActor
final class ClickabilityPolicyTests: XCTestCase {

    private let policy = ClickabilityPolicy.default

    // MARK: - interactiveByRole: truth table

    func test_button_isInteractive() {
        XCTAssertTrue(policy.interactiveByRole(role: kAXButtonRole as String, enabled: true))
    }

    func test_button_whenDisabled_isNotInteractive() {
        XCTAssertFalse(policy.interactiveByRole(role: kAXButtonRole as String, enabled: false))
    }

    func test_button_enabledNil_isInteractive() {
        // nil = "attribute absent"; we treat that as "not disabled".
        XCTAssertTrue(policy.interactiveByRole(role: kAXButtonRole as String, enabled: nil))
    }

    func test_staticTextRole_notInteractiveWithoutActionProbe() {
        // AXStaticText is only clickable when it exposes AXPress/AXShowMenu.
        // `interactiveByRole` is the role-table half — it must say "no".
        XCTAssertFalse(policy.interactiveByRole(role: kAXStaticTextRole as String, enabled: true))
    }

    func test_unknownRole_isNotInteractive() {
        XCTAssertFalse(policy.interactiveByRole(role: "AXSomethingCustom", enabled: true))
    }

    func test_menuItemAndLink_areInteractive() {
        XCTAssertTrue(policy.interactiveByRole(role: kAXMenuItemRole as String, enabled: true))
        XCTAssertTrue(policy.interactiveByRole(role: "AXLink", enabled: true))
    }

    func test_checkboxRadioPopup_areInteractive() {
        XCTAssertTrue(policy.interactiveByRole(role: kAXCheckBoxRole as String, enabled: true))
        XCTAssertTrue(policy.interactiveByRole(role: kAXRadioButtonRole as String, enabled: true))
        XCTAssertTrue(policy.interactiveByRole(role: kAXPopUpButtonRole as String, enabled: true))
    }

    func test_cell_isNotInteractiveByRoleAlone() {
        // AXCell by role alone used to accept ornamental row shells (e.g.
        // GitHub file-listing rows) whose only actions are AXShowMenu /
        // AXScrollToVisible.  The role-table half must say "no" — real
        // clickable cells go through the AXPress gate in `classify`.
        XCTAssertFalse(policy.interactiveByRole(role: "AXCell", enabled: true))
    }

    // MARK: - classify: AXCell AXPress gate

    func test_classify_cell_withoutClickAction_isNotInteractive() {
        // Ornamental row shell: only AXShowMenu / AXScrollToVisible, no
        // AXPress → rejected so the real clickable descendant (e.g. an
        // inner AXLink) is the only hint target.
        XCTAssertEqual(
            policy.classify(role: "AXCell", enabled: true, hasClickAction: false),
            .roleNotInteractive
        )
    }

    func test_classify_cell_withClickAction_isInteractive() {
        // Native NSTableView cells that expose AXPress remain clickable.
        XCTAssertEqual(
            policy.classify(role: "AXCell", enabled: true, hasClickAction: true),
            .interactiveRole
        )
    }

    func test_classify_cell_disabled_shortCircuits() {
        XCTAssertEqual(
            policy.classify(role: "AXCell", enabled: false, hasClickAction: true),
            .disabled
        )
    }

    // MARK: - canPruneSubtree

    func test_staticTextAndImage_subtreesArePruned() {
        XCTAssertTrue(policy.canPruneSubtree(role: kAXStaticTextRole as String))
        XCTAssertTrue(policy.canPruneSubtree(role: kAXImageRole as String))
    }

    func test_scrollBarAndProgressIndicator_subtreesArePruned() {
        XCTAssertTrue(policy.canPruneSubtree(role: "AXScrollBar"))
        XCTAssertTrue(policy.canPruneSubtree(role: "AXProgressIndicator"))
        XCTAssertTrue(policy.canPruneSubtree(role: "AXBusyIndicator"))
        XCTAssertTrue(policy.canPruneSubtree(role: kAXValueIndicatorRole as String))
    }

    func test_buttonSubtree_isNotPruned() {
        // Buttons can legitimately contain clickable children (e.g. text fields inside composite controls).
        XCTAssertFalse(policy.canPruneSubtree(role: kAXButtonRole as String))
    }

    func test_unknownRole_subtreeNotPruned() {
        XCTAssertFalse(policy.canPruneSubtree(role: "AXSomethingCustom"))
    }

    // MARK: - classify: native-app behaviour (webContext = nil)

    func test_classify_button_isInteractive() {
        XCTAssertEqual(
            policy.classify(role: kAXButtonRole as String, enabled: true),
            .interactiveRole
        )
    }

    func test_classify_disabledShortCircuits_regardlessOfRole() {
        // Disabled wins over every other predicate, even for static text.
        XCTAssertEqual(
            policy.classify(
                role: kAXStaticTextRole as String,
                enabled: false,
                hasClickAction: true,
                hasURL: true,
                webContext: .init(inWebArea: true, hasClickableAncestor: false)
            ),
            .disabled
        )
    }

    func test_classify_staticText_noClickAction_isNoAction() {
        XCTAssertEqual(
            policy.classify(
                role: kAXStaticTextRole as String,
                enabled: true,
                hasClickAction: false
            ),
            .staticTextNoAction
        )
    }

    func test_classify_staticText_pressable_outsideWebArea_isPressable() {
        // Native app: pressable static text is accepted as today.
        // No URL, no ancestor, no web context — pre-WebArea behaviour.
        XCTAssertEqual(
            policy.classify(
                role: kAXStaticTextRole as String,
                enabled: true,
                hasClickAction: true
            ),
            .staticTextPressable
        )
    }

    func test_classify_staticText_pressable_nilWebContext_matchesLegacyBehaviour() {
        // When the walker passes webContext: nil we must match the pre-
        // narrowing classifier exactly — no ancestor / URL checks fire.
        XCTAssertEqual(
            policy.classify(
                role: kAXStaticTextRole as String,
                enabled: true,
                hasClickAction: true,
                hasURL: false,
                webContext: nil
            ),
            .staticTextPressable
        )
    }

    // MARK: - classify: web-area narrowing (A + B)

    func test_classify_inWebArea_withClickableAncestor_isDroppedByAncestor() {
        // Rule A: link text that duplicates its <a>/<button> wrapper.
        XCTAssertEqual(
            policy.classify(
                role: kAXStaticTextRole as String,
                enabled: true,
                hasClickAction: true,
                hasURL: false,
                webContext: .init(inWebArea: true, hasClickableAncestor: true)
            ),
            .staticTextDroppedByAncestor
        )
    }

    func test_classify_inWebArea_ancestorOverridesURL() {
        // Even if the text itself reports AXURL, an already-hinted
        // ancestor suppresses it so we don't emit two hints at the same
        // spot.
        XCTAssertEqual(
            policy.classify(
                role: kAXStaticTextRole as String,
                enabled: true,
                hasClickAction: true,
                hasURL: true,
                webContext: .init(inWebArea: true, hasClickableAncestor: true)
            ),
            .staticTextDroppedByAncestor
        )
    }

    func test_classify_inWebArea_noAncestor_noURL_isDroppedNoURL() {
        // Rule B: pressable paragraph/label text that isn't a real link.
        XCTAssertEqual(
            policy.classify(
                role: kAXStaticTextRole as String,
                enabled: true,
                hasClickAction: true,
                hasURL: false,
                webContext: .init(inWebArea: false, hasClickableAncestor: false)
            ),
            // inWebArea == false → narrowing off, accepted as today.
            .staticTextPressable
        )

        XCTAssertEqual(
            policy.classify(
                role: kAXStaticTextRole as String,
                enabled: true,
                hasClickAction: true,
                hasURL: false,
                webContext: .init(inWebArea: true, hasClickableAncestor: false)
            ),
            .staticTextDroppedNoURL
        )
    }

    func test_classify_inWebArea_noAncestor_withURL_isPressable() {
        // The genuine-link case: standalone <a href> not covered by an
        // outer clickable ancestor survives narrowing.
        XCTAssertEqual(
            policy.classify(
                role: kAXStaticTextRole as String,
                enabled: true,
                hasClickAction: true,
                hasURL: true,
                webContext: .init(inWebArea: true, hasClickableAncestor: false)
            ),
            .staticTextPressable
        )
    }

    func test_classify_inWebArea_interactiveRole_ignoresNarrowing() {
        // Narrowing only targets AXStaticText; AXButton inside a web
        // area must still pass normally even if its parent is clickable.
        XCTAssertEqual(
            policy.classify(
                role: kAXButtonRole as String,
                enabled: true,
                webContext: .init(inWebArea: true, hasClickableAncestor: true)
            ),
            .interactiveRole
        )
    }

    // MARK: - classify: Chromium AXDOMRole gate (commit 2)

    func test_classify_inWebArea_domRoleInteractive_overridesMissingURL() {
        // Chromium exposes AXDOMRole: when the HTML tag is "a" or
        // "button" we keep the element even without AXURL (rule B would
        // otherwise drop it).
        XCTAssertEqual(
            policy.classify(
                role: kAXStaticTextRole as String,
                enabled: true,
                hasClickAction: true,
                hasURL: false,
                domRole: "a",
                webContext: .init(inWebArea: true, hasClickableAncestor: false)
            ),
            .staticTextPressable
        )

        XCTAssertEqual(
            policy.classify(
                role: kAXStaticTextRole as String,
                enabled: true,
                hasClickAction: true,
                hasURL: false,
                domRole: "BUTTON",
                webContext: .init(inWebArea: true, hasClickableAncestor: false)
            ),
            .staticTextPressable,
            "DOM role comparison must be case-insensitive"
        )
    }

    func test_classify_inWebArea_domRoleNonInteractive_dropsEvenWithURL() {
        // Ground truth from the DOM wins over the URL heuristic: a <p>
        // that somehow reports both AXPress and AXURL is still paragraph
        // text and should be suppressed.
        XCTAssertEqual(
            policy.classify(
                role: kAXStaticTextRole as String,
                enabled: true,
                hasClickAction: true,
                hasURL: true,
                domRole: "p",
                webContext: .init(inWebArea: true, hasClickableAncestor: false)
            ),
            .staticTextDroppedByDOMRole
        )
    }

    func test_classify_inWebArea_domRoleAbsent_fallsBackToURLRule() {
        // Safari / Firefox path: AXDOMRole unavailable, classifier
        // continues using the existing URL rule from commit 1.
        XCTAssertEqual(
            policy.classify(
                role: kAXStaticTextRole as String,
                enabled: true,
                hasClickAction: true,
                hasURL: false,
                domRole: nil,
                webContext: .init(inWebArea: true, hasClickableAncestor: false)
            ),
            .staticTextDroppedNoURL
        )

        XCTAssertEqual(
            policy.classify(
                role: kAXStaticTextRole as String,
                enabled: true,
                hasClickAction: true,
                hasURL: true,
                domRole: nil,
                webContext: .init(inWebArea: true, hasClickableAncestor: false)
            ),
            .staticTextPressable
        )
    }

    // MARK: - classify: Safari / Firefox focusable fallback (commit 3)

    func test_classify_inWebArea_safariFocusableNoURL_isPressable() {
        // Safari exposes no AXDOMRole. A focusable element (has AXFocused
        // attribute) is accepted even without AXURL — e.g., <button>
        // renders as a focusable AXStaticText in some cases.
        XCTAssertEqual(
            policy.classify(
                role: kAXStaticTextRole as String,
                enabled: true,
                hasClickAction: true,
                hasURL: false,
                isFocusable: true,
                domRole: nil,
                webContext: .init(inWebArea: true, hasClickableAncestor: false)
            ),
            .staticTextPressable
        )
    }

    func test_classify_inWebArea_safariNotFocusableNoURL_isDropped() {
        // No DOM role, not focusable, no URL — paragraph / label text.
        XCTAssertEqual(
            policy.classify(
                role: kAXStaticTextRole as String,
                enabled: true,
                hasClickAction: true,
                hasURL: false,
                isFocusable: false,
                domRole: nil,
                webContext: .init(inWebArea: true, hasClickableAncestor: false)
            ),
            .staticTextDroppedNoURL
        )
    }

    func test_classify_inWebArea_safariNotFocusableWithURL_isPressable() {
        // URL alone (genuine link) is sufficient in the Safari fallback.
        XCTAssertEqual(
            policy.classify(
                role: kAXStaticTextRole as String,
                enabled: true,
                hasClickAction: true,
                hasURL: true,
                isFocusable: false,
                domRole: nil,
                webContext: .init(inWebArea: true, hasClickableAncestor: false)
            ),
            .staticTextPressable
        )
    }

    func test_classify_inWebArea_chromiumFocusable_deferredToDOMRole() {
        // When AXDOMRole is present (Chromium), focusability is NOT
        // consulted — DOM role is authoritative.  A focusable element
        // whose DOM role is "p" must still be dropped.
        XCTAssertEqual(
            policy.classify(
                role: kAXStaticTextRole as String,
                enabled: true,
                hasClickAction: true,
                hasURL: false,
                isFocusable: true,
                domRole: "p",
                webContext: .init(inWebArea: true, hasClickableAncestor: false)
            ),
            .staticTextDroppedByDOMRole
        )
    }

    func test_classify_inWebArea_ancestorOverridesDOMRole() {
        // Rule A short-circuits before the DOM-role check — an already-
        // clickable ancestor means we drop the inner text regardless of
        // what AXDOMRole says.
        XCTAssertEqual(
            policy.classify(
                role: kAXStaticTextRole as String,
                enabled: true,
                hasClickAction: true,
                hasURL: true,
                domRole: "a",
                webContext: .init(inWebArea: true, hasClickableAncestor: true)
            ),
            .staticTextDroppedByAncestor
        )
    }

    // MARK: - Decision.isClickable truth table for new cases

    func test_newDecisions_areNotClickable() {
        XCTAssertFalse(ClickabilityPolicy.Decision.staticTextDroppedByAncestor.isClickable)
        XCTAssertFalse(ClickabilityPolicy.Decision.staticTextDroppedNoURL.isClickable)
        XCTAssertFalse(ClickabilityPolicy.Decision.staticTextDroppedByDOMRole.isClickable)
    }
}
