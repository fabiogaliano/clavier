//
//  MatchCountPresenterTests.swift
//  clavierTests
//
//  Pure tests for the match-count → bar count segment mapping.
//

import XCTest
import AppKit
@testable import clavier

final class MatchCountPresenterTests: XCTestCase {

    func test_resetSentinel_drawsNoSegment() {
        XCTAssertEqual(MatchCountPresenter.style(forCount: -1).labelText, "")
    }

    func test_zeroMatches_isRed() {
        let style = MatchCountPresenter.style(forCount: 0)
        XCTAssertEqual(style.labelText, "0")
        XCTAssertEqual(style.labelColor, .systemRed)
    }

    func test_singleMatch_isBlue() {
        let style = MatchCountPresenter.style(forCount: 1)
        XCTAssertEqual(style.labelText, "1")
        XCTAssertEqual(style.labelColor, .systemBlue)
    }

    func test_multiMatch_isBlueWithCount() {
        let style = MatchCountPresenter.style(forCount: 7)
        XCTAssertEqual(style.labelText, "7")
        XCTAssertEqual(style.labelColor, .systemBlue)
    }

    func test_largeMatchCount_stringsThroughAsIs() {
        XCTAssertEqual(MatchCountPresenter.style(forCount: 123).labelText, "123")
    }

    func test_zeroMatchesWhileHydrating_showsPendingInsteadOfRed() {
        let style = MatchCountPresenter.style(forCount: 0, isHydrating: true)
        XCTAssertEqual(style.labelText, "…")
        XCTAssertNotEqual(style.labelColor, .systemRed)
    }

    func test_nonZeroMatchesWhileHydrating_showsRealCount() {
        XCTAssertEqual(MatchCountPresenter.style(forCount: 3, isHydrating: true).labelText, "3")
    }
}
