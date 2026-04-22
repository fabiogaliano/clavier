//
//  AncestorDedupePolicyTests.swift
//  clavierTests
//
//  Pure-geometry tests for the frame-match predicate that decides whether
//  a child clickable should be collapsed into its clickable ancestor.  No
//  AX dependencies — we exercise the tolerance contract on each edge.
//

import XCTest
@testable import clavier

final class AncestorDedupePolicyTests: XCTestCase {

    private let policy = AncestorDedupePolicy.default

    // MARK: - Exact match

    func test_identicalFrames_matchRegardlessOfTolerance() {
        let frame = CGRect(x: 10, y: 20, width: 100, height: 40)
        XCTAssertTrue(policy.framesMatch(frame, frame))
    }

    // MARK: - Within tolerance on each edge

    func test_framesWithinToleranceOnAllEdges_match() {
        let ancestor = CGRect(x: 10, y: 20, width: 100, height: 40)
        let child = CGRect(x: 14, y: 24, width: 100, height: 40) // shifted 4pt — under 10pt
        XCTAssertTrue(policy.framesMatch(child, ancestor))
    }

    // MARK: - Out of tolerance on a single edge

    func test_minXBeyondTolerance_doesNotMatch() {
        let ancestor = CGRect(x: 0, y: 0, width: 100, height: 40)
        let child = CGRect(x: 11, y: 0, width: 100, height: 40) // 11pt > 10pt
        XCTAssertFalse(policy.framesMatch(child, ancestor))
    }

    func test_minYBeyondTolerance_doesNotMatch() {
        let ancestor = CGRect(x: 0, y: 0, width: 100, height: 40)
        let child = CGRect(x: 0, y: 11, width: 100, height: 40)
        XCTAssertFalse(policy.framesMatch(child, ancestor))
    }

    func test_maxXBeyondTolerance_doesNotMatch() {
        let ancestor = CGRect(x: 0, y: 0, width: 100, height: 40)
        let child = CGRect(x: 0, y: 0, width: 111, height: 40)
        XCTAssertFalse(policy.framesMatch(child, ancestor))
    }

    func test_maxYBeyondTolerance_doesNotMatch() {
        let ancestor = CGRect(x: 0, y: 0, width: 100, height: 40)
        let child = CGRect(x: 0, y: 0, width: 100, height: 51)
        XCTAssertFalse(policy.framesMatch(child, ancestor))
    }

    // MARK: - Boundary: strictly less than, not less-or-equal

    func test_exactlyAtToleranceOnMinX_doesNotMatch() {
        let ancestor = CGRect(x: 0, y: 0, width: 100, height: 40)
        let child = CGRect(x: 10, y: 0, width: 100, height: 40) // == tolerance
        // Predicate is `< tolerance` (strict), so exactly-on-tolerance must not match.
        XCTAssertFalse(policy.framesMatch(child, ancestor))
    }

    // MARK: - Custom tolerance

    func test_customTolerance_enlargesMatchWindow() {
        let tightPolicy = AncestorDedupePolicy(frameTolerance: 2)
        let loosePolicy = AncestorDedupePolicy(frameTolerance: 20)
        let ancestor = CGRect(x: 0, y: 0, width: 100, height: 40)
        let child = CGRect(x: 5, y: 0, width: 100, height: 40)

        XCTAssertFalse(tightPolicy.framesMatch(child, ancestor))
        XCTAssertTrue(loosePolicy.framesMatch(child, ancestor))
    }
}
