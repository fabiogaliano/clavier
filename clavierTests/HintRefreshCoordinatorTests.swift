//
//  HintRefreshCoordinatorTests.swift
//  clavierTests
//
//  Drives the post-click sampling loop on a virtual clock: the injected
//  sleeper advances time instantly, so the tests check the schedule and the
//  stop conditions without waiting out real delays.
//

import XCTest
@testable import clavier

@MainActor
final class HintRefreshCoordinatorTests: XCTestCase {

    private struct FixedTiming: HintRefreshTimingPolicy {
        let delays: HintRefreshDelays
        func refreshDelays(for bundleIdentifier: String?) -> HintRefreshDelays? { delays }
    }

    /// Virtual clock whose sleeps return immediately after advancing time.
    private final class VirtualClock {
        var now: CFAbsoluteTime = 1_000
        var sleeps: [TimeInterval] = []

        func sleep(_ interval: TimeInterval) throws {
            try Task.checkCancellation()
            sleeps.append(interval)
            now += interval
        }
    }

    // Binary-exact values so backoff products compare equal without tolerance.
    private let delays = HintRefreshDelays(optimistic: 0.0625, pollInterval: 0.125, settleWindow: 1.0)

    private func signature(_ ys: Int...) -> HintTreeSignature {
        HintTreeSignature(ys.map {
            ElementIdentity(pid: 1, role: "AXButton", frame: CGRect(x: 0, y: CGFloat($0), width: 40, height: 20))
        })
    }

    private func makeCoordinator(clock: VirtualClock) -> HintRefreshCoordinator {
        HintRefreshCoordinator(
            timingPolicy: FixedTiming(delays: delays),
            sleep: { try clock.sleep($0) },
            now: { clock.now }
        )
    }

    func test_popupSettles_reportsChangedAfterTwoMatchingSamples() async {
        let clock = VirtualClock()
        let coordinator = makeCoordinator(clock: clock)
        var samples = [signature(0, 90), signature(0, 100), signature(0, 100)]
        let done = expectation(description: "completion")
        var outcome: HintRefreshOutcome?

        coordinator.scheduleRefresh(
            baseline: signature(0),
            sample: { samples.removeFirst() },
            completion: { outcome = $0; done.fulfill() }
        )

        await fulfillment(of: [done], timeout: 2)
        XCTAssertEqual(outcome, .changed)
        XCTAssertEqual(clock.sleeps, [0.0625, 0.125, 0.1875], "first wait is optimistic, then backs off")
        XCTAssertTrue(samples.isEmpty)
    }

    func test_nothingChanges_reportsUnchangedOnceWindowElapses() async {
        let clock = VirtualClock()
        let coordinator = makeCoordinator(clock: clock)
        let done = expectation(description: "completion")
        var outcome: HintRefreshOutcome?
        var sampleCount = 0

        coordinator.scheduleRefresh(
            baseline: signature(0),
            sample: { sampleCount += 1; return self.signature(0) },
            completion: { outcome = $0; done.fulfill() }
        )

        await fulfillment(of: [done], timeout: 2)
        XCTAssertEqual(outcome, .unchanged)
        // Waits 0.0625, 0.125, 0.1875, 0.28125, 0.421875 → elapsed 1.078 ≥ 1.0 window.
        XCTAssertEqual(sampleCount, 5)
    }

    func test_sampleReturningNil_stopsWithoutCompletion() async {
        let clock = VirtualClock()
        let coordinator = makeCoordinator(clock: clock)
        let sampled = expectation(description: "sampled")
        let completed = expectation(description: "completion")
        completed.isInverted = true

        coordinator.scheduleRefresh(
            baseline: signature(0),
            sample: { sampled.fulfill(); return nil },
            completion: { _ in completed.fulfill() }
        )

        await fulfillment(of: [sampled, completed], timeout: 0.2)
        XCTAssertEqual(clock.sleeps.count, 1)
    }

    func test_cancelPending_beforeFirstSample_neverSamples() async {
        let clock = VirtualClock()
        let coordinator = makeCoordinator(clock: clock)
        let sampled = expectation(description: "sampled")
        sampled.isInverted = true

        coordinator.scheduleRefresh(
            baseline: signature(0),
            sample: { sampled.fulfill(); return self.signature(0) },
            completion: { _ in }
        )
        coordinator.cancelPending()

        await fulfillment(of: [sampled], timeout: 0.2)
        XCTAssertTrue(clock.sleeps.isEmpty)
    }

    func test_newSchedule_supersedesInFlightCycle() async {
        let clock = VirtualClock()
        let coordinator = makeCoordinator(clock: clock)
        let staleCompleted = expectation(description: "stale completion")
        staleCompleted.isInverted = true
        let done = expectation(description: "completion")

        coordinator.scheduleRefresh(
            baseline: signature(0),
            sample: { self.signature(0, 100) },
            completion: { _ in staleCompleted.fulfill() }
        )
        coordinator.scheduleRefresh(
            baseline: signature(0),
            sample: { self.signature(0, 100) },
            completion: { _ in done.fulfill() }
        )

        await fulfillment(of: [done, staleCompleted], timeout: 0.2)
    }
}
