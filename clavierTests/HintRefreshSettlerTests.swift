//
//  HintRefreshSettlerTests.swift
//  clavierTests
//
//  Verifies the post-click settle policy: sample until the AX tree stops
//  changing, keep sampling an unchanged tree until the window closes, and
//  back off between samples.
//

import XCTest
@testable import clavier

final class HintRefreshSettlerTests: XCTestCase {

    // Binary-exact values so backoff products compare equal without tolerance.
    private let delays = HintRefreshDelays(optimistic: 0.0625, pollInterval: 0.125, settleWindow: 1.0)

    private func signature(_ ys: Int...) -> HintTreeSignature {
        HintTreeSignature(ys.map {
            ElementIdentity(pid: 1, role: "AXButton", frame: CGRect(x: 0, y: CGFloat($0), width: 40, height: 20))
        })
    }

    func test_firstDelay_isOptimisticDelay() {
        let settler = HintRefreshSettler(baseline: signature(0), delays: delays)
        XCTAssertEqual(settler.firstDelay, 0.0625)
    }

    func test_divergedThenStable_finishesChanged() {
        var settler = HintRefreshSettler(baseline: signature(0), delays: delays)
        XCTAssertEqual(settler.observe(signature(0, 100), elapsed: 0.05), .sampleAgain(after: 0.125))
        XCTAssertEqual(settler.observe(signature(0, 100), elapsed: 0.15), .finished(.changed))
    }

    func test_popupStillAnimating_keepsSamplingUntilFramesHold() {
        // A popover sliding in reports a different frame on every sample.
        var settler = HintRefreshSettler(baseline: signature(0), delays: delays)
        XCTAssertEqual(settler.observe(signature(0, 90), elapsed: 0.05), .sampleAgain(after: 0.125))
        XCTAssertEqual(settler.observe(signature(0, 95), elapsed: 0.15), .sampleAgain(after: 0.1875))
        XCTAssertEqual(settler.observe(signature(0, 100), elapsed: 0.30), .sampleAgain(after: 0.28125))
        XCTAssertEqual(settler.observe(signature(0, 100), elapsed: 0.53), .finished(.changed))
    }

    func test_lateContent_isCaughtAfterUnchangedSamples() {
        // The popup's list arrives after the first two samples saw nothing new.
        var settler = HintRefreshSettler(baseline: signature(0), delays: delays)
        XCTAssertEqual(settler.observe(signature(0), elapsed: 0.05), .sampleAgain(after: 0.125))
        XCTAssertEqual(settler.observe(signature(0), elapsed: 0.15), .sampleAgain(after: 0.1875))
        XCTAssertEqual(settler.observe(signature(0, 100), elapsed: 0.30), .sampleAgain(after: 0.28125))
        XCTAssertEqual(settler.observe(signature(0, 100), elapsed: 0.53), .finished(.changed))
    }

    func test_neverDiverges_finishesUnchangedAtWindow() {
        var settler = HintRefreshSettler(baseline: signature(0), delays: delays)
        XCTAssertEqual(settler.observe(signature(0), elapsed: 0.5), .sampleAgain(after: 0.125))
        XCTAssertEqual(settler.observe(signature(0), elapsed: 1.0), .finished(.unchanged))
    }

    func test_neverHoldsStill_finishesChangedAtWindow() {
        // Streaming content: every sample differs, so give up at the window.
        var settler = HintRefreshSettler(baseline: signature(0), delays: delays)
        XCTAssertEqual(settler.observe(signature(1), elapsed: 0.5), .sampleAgain(after: 0.125))
        XCTAssertEqual(settler.observe(signature(2), elapsed: 1.0), .finished(.changed))
    }
}
