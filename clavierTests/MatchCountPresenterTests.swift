//
//  MatchCountPresenterTests.swift
//  clavierTests
//
//  Pure tests for the match-count → badge/border style mapping.
//

import XCTest
import AppKit
@testable import clavier

final class MatchCountPresenterTests: XCTestCase {

    func test_resetSentinel_producesBlueBorderWithEmptyLabel() {
        let style = MatchCountPresenter.style(forCount: -1)
        XCTAssertEqual(style.labelText, "")
        XCTAssertEqual(style.borderColor, .systemBlue)
    }

    func test_zeroMatches_producesRedStyle() {
        let style = MatchCountPresenter.style(forCount: 0)
        XCTAssertEqual(style.labelText, "0")
        XCTAssertEqual(style.labelColor, .systemRed)
        XCTAssertEqual(style.borderColor, .systemRed)
    }

    func test_singleMatch_producesGreenStyle() {
        let style = MatchCountPresenter.style(forCount: 1)
        XCTAssertEqual(style.labelText, "1")
        XCTAssertEqual(style.labelColor, .systemGreen)
        XCTAssertEqual(style.borderColor, .systemGreen)
    }

    func test_multiMatch_producesYellowStyleWithCount() {
        let style = MatchCountPresenter.style(forCount: 7)
        XCTAssertEqual(style.labelText, "7")
        XCTAssertEqual(style.labelColor, .systemYellow)
        XCTAssertEqual(style.borderColor, .systemYellow)
    }

    func test_largeMatchCount_stringsThroughAsIs() {
        let style = MatchCountPresenter.style(forCount: 123)
        XCTAssertEqual(style.labelText, "123")
    }

    func test_zeroMatchesWhileHydrating_showsPendingInsteadOfRed() {
        let style = MatchCountPresenter.style(forCount: 0, isHydrating: true)
        XCTAssertEqual(style.labelText, "…")
        XCTAssertNotEqual(style.borderColor, .systemRed)
    }

    func test_nonZeroMatchesWhileHydrating_showsRealCount() {
        let style = MatchCountPresenter.style(forCount: 3, isHydrating: true)
        XCTAssertEqual(style.labelText, "3")
    }
}
