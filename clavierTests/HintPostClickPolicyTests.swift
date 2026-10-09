//
//  HintPostClickPolicyTests.swift
//  clavierTests
//
//  Verifies what a session does after a click: continuous always refreshes,
//  one-shot closes unless the click opened a popup.
//

import XCTest
@testable import clavier
import ApplicationServices

final class HintPostClickPolicyTests: XCTestCase {

    func test_continuous_alwaysRefreshesAndStaysOpen() {
        XCTAssertEqual(HintPostClickPolicy.plan(mode: .continuous, clickOpensPopup: false), .refresh(closeIfUnchanged: false))
        XCTAssertEqual(HintPostClickPolicy.plan(mode: .continuous, clickOpensPopup: true), .refresh(closeIfUnchanged: false))
    }

    func test_oneShot_plainClick_closes() {
        XCTAssertEqual(HintPostClickPolicy.plan(mode: .oneShot, clickOpensPopup: false), .close)
    }

    func test_oneShot_popupClick_followsPopupButClosesIfNothingAppears() {
        XCTAssertEqual(HintPostClickPolicy.plan(mode: .oneShot, clickOpensPopup: true), .refresh(closeIfUnchanged: true))
    }

    // MARK: - Click kinds

    func test_rightClick_alwaysCountsAsOpeningAPopup() {
        XCTAssertTrue(HintPostClickPolicy.clickOpensPopup(kind: .secondary) { false })
    }

    func test_hover_neverCountsAsOpeningAPopup_soOneShotCloses() {
        let opens = HintPostClickPolicy.clickOpensPopup(kind: .hover) { true }
        XCTAssertFalse(opens)
        XCTAssertEqual(HintPostClickPolicy.plan(mode: .oneShot, clickOpensPopup: opens), .close)
        XCTAssertEqual(HintPostClickPolicy.plan(mode: .continuous, clickOpensPopup: opens), .refresh(closeIfUnchanged: false))
    }

    func test_pressingKinds_followTheTargetLikeALeftClick() {
        for kind in [HintClickKind.primary, .double] {
            XCTAssertTrue(HintPostClickPolicy.clickOpensPopup(kind: kind) { true }, "\(kind)")
            XCTAssertFalse(HintPostClickPolicy.clickOpensPopup(kind: kind) { false }, "\(kind)")
        }
    }

    func test_nonPressingKinds_doNotProbeTheTarget() {
        for kind in [HintClickKind.secondary, .hover] {
            _ = HintPostClickPolicy.clickOpensPopup(kind: kind) {
                XCTFail("\(kind) must not probe the element")
                return false
            }
        }
    }

    func test_opensPopup_byRole() {
        XCTAssertTrue(HintPostClickPolicy.opensPopup(role: kAXPopUpButtonRole as String, hasPopup: nil))
        XCTAssertTrue(HintPostClickPolicy.opensPopup(role: kAXMenuButtonRole as String, hasPopup: nil))
        XCTAssertTrue(HintPostClickPolicy.opensPopup(role: kAXComboBoxRole as String, hasPopup: nil))
        XCTAssertTrue(HintPostClickPolicy.opensPopup(role: kAXMenuBarItemRole as String, hasPopup: nil))
        XCTAssertFalse(HintPostClickPolicy.opensPopup(role: "AXDockItem", hasPopup: nil))
    }

    func test_opensPopup_byHasPopupAttribute() {
        // A web <button aria-haspopup="listbox"> can surface as plain AXButton.
        XCTAssertTrue(HintPostClickPolicy.opensPopup(role: kAXButtonRole as String, hasPopup: true))
        XCTAssertFalse(HintPostClickPolicy.opensPopup(role: kAXButtonRole as String, hasPopup: false))
        XCTAssertFalse(HintPostClickPolicy.opensPopup(role: "AXLink", hasPopup: nil))
    }
}
