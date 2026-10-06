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

    func test_opensPopup_byRole() {
        XCTAssertTrue(HintPostClickPolicy.opensPopup(role: kAXPopUpButtonRole as String, hasPopup: nil))
        XCTAssertTrue(HintPostClickPolicy.opensPopup(role: kAXMenuButtonRole as String, hasPopup: nil))
        XCTAssertTrue(HintPostClickPolicy.opensPopup(role: kAXComboBoxRole as String, hasPopup: nil))
    }

    func test_opensPopup_byHasPopupAttribute() {
        // A web <button aria-haspopup="listbox"> can surface as plain AXButton.
        XCTAssertTrue(HintPostClickPolicy.opensPopup(role: kAXButtonRole as String, hasPopup: true))
        XCTAssertFalse(HintPostClickPolicy.opensPopup(role: kAXButtonRole as String, hasPopup: false))
        XCTAssertFalse(HintPostClickPolicy.opensPopup(role: "AXLink", hasPopup: nil))
    }
}
