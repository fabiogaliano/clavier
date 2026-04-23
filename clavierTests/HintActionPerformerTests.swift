//
//  HintActionPerformerTests.swift
//  clavierTests
//
//  Focused tests for the action-routing policy used by `HintActionPerformer`.
//

import XCTest
@testable import clavier

@MainActor
final class HintActionPolicyTests: XCTestCase {

    private let policy = HintActionPolicy()

    func test_primaryActionPolicy_prefersCGEventForWebContentControls() {
        XCTAssertEqual(
            policy.strategy(for: HintPrimaryActionContext(role: "AXRadioButton", isWebContent: true)),
            .cgEventOnly
        )
        XCTAssertEqual(
            policy.strategy(for: HintPrimaryActionContext(role: "AXButton", isWebContent: true)),
            .cgEventOnly
        )
    }

    func test_primaryActionPolicy_prefersCGEventForAXLinkOutsideWebContent() {
        XCTAssertEqual(
            policy.strategy(for: HintPrimaryActionContext(role: "AXLink", isWebContent: false)),
            .cgEventOnly
        )
    }

    func test_primaryActionPolicy_keepsAXPressForNativeControls() {
        XCTAssertEqual(
            policy.strategy(for: HintPrimaryActionContext(role: "AXButton", isWebContent: false)),
            .axPressThenCGEventFallback
        )
        XCTAssertEqual(
            policy.strategy(for: HintPrimaryActionContext(role: "AXRadioButton", isWebContent: false)),
            .axPressThenCGEventFallback
        )
    }
}
