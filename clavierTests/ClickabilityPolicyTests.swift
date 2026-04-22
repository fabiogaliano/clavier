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
}
