//
//  HintOverlapCyclerTests.swift
//  clavierTests
//
//  Pure geometry tests for the Space-overlap cycling logic:
//  connected-component grouping and modular top-member rotation.
//

import XCTest
@testable import clavier

final class HintOverlapCyclerTests: XCTestCase {

    // MARK: - Grouping

    func test_nonOverlappingFramesProduceNoGroups() {
        let frames = [
            CGRect(x: 0,   y: 0, width: 20, height: 20),
            CGRect(x: 100, y: 0, width: 20, height: 20),
            CGRect(x: 200, y: 0, width: 20, height: 20),
        ]
        XCTAssertTrue(HintOverlapCycler.groups(for: frames).isEmpty)
    }

    func test_twoIntersectingFramesYieldOneGroup() {
        let frames = [
            CGRect(x: 0,  y: 0, width: 20, height: 20),
            CGRect(x: 10, y: 0, width: 20, height: 20),
        ]
        let groups = HintOverlapCycler.groups(for: frames)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].memberIndices, [0, 1])
    }

    func test_chainOfIntersectionsProducesSingleTransitiveGroup() {
        // 0 intersects 1, 1 intersects 2, but 0 does NOT intersect 2.
        // Union-find must still collapse them into one connected component.
        let frames = [
            CGRect(x: 0,  y: 0, width: 15, height: 20),
            CGRect(x: 10, y: 0, width: 15, height: 20),
            CGRect(x: 20, y: 0, width: 15, height: 20),
        ]
        let groups = HintOverlapCycler.groups(for: frames)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].memberIndices, [0, 1, 2])
    }

    func test_twoDisjointClustersYieldTwoGroups() {
        let frames = [
            CGRect(x: 0,   y: 0, width: 15, height: 20),
            CGRect(x: 10,  y: 0, width: 15, height: 20),
            CGRect(x: 200, y: 0, width: 15, height: 20),
            CGRect(x: 210, y: 0, width: 15, height: 20),
        ]
        let groups = HintOverlapCycler.groups(for: frames)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].memberIndices, [0, 1])
        XCTAssertEqual(groups[1].memberIndices, [2, 3])
    }

    func test_emptyOrSingleFrameInputProducesNoGroups() {
        XCTAssertTrue(HintOverlapCycler.groups(for: []).isEmpty)
        XCTAssertTrue(HintOverlapCycler.groups(for: [CGRect(x: 0, y: 0, width: 10, height: 10)]).isEmpty)
    }

    // MARK: - Rotation

    func test_stepZeroAlwaysSelectsOriginalFront() {
        XCTAssertEqual(HintOverlapCycler.topMember(size: 3, step: 0), 0)
        XCTAssertEqual(HintOverlapCycler.topMember(size: 5, step: 0), 0)
    }

    func test_rotationWrapsModuloGroupSize() {
        XCTAssertEqual(HintOverlapCycler.topMember(size: 3, step: 1), 1)
        XCTAssertEqual(HintOverlapCycler.topMember(size: 3, step: 2), 2)
        XCTAssertEqual(HintOverlapCycler.topMember(size: 3, step: 3), 0)
        XCTAssertEqual(HintOverlapCycler.topMember(size: 3, step: 6), 0)
        XCTAssertEqual(HintOverlapCycler.topMember(size: 3, step: 7), 1)
    }

    func test_rotationIsReversibleAfterGroupSizePresses() {
        // After `size` presses, the group must return to its original order.
        // Verify by checking the cyclic sequence visits every member exactly once.
        let size = 4
        var visited: [Int] = []
        for step in 0..<size {
            visited.append(HintOverlapCycler.topMember(size: size, step: step))
        }
        XCTAssertEqual(Set(visited), Set(0..<size))
        XCTAssertEqual(HintOverlapCycler.topMember(size: size, step: size), 0)
    }

    func test_negativeStepWrapsCorrectly() {
        XCTAssertEqual(HintOverlapCycler.topMember(size: 4, step: -1), 3)
        XCTAssertEqual(HintOverlapCycler.topMember(size: 4, step: -4), 0)
    }

    func test_sizeZeroDoesNotCrash() {
        XCTAssertEqual(HintOverlapCycler.topMember(size: 0, step: 5), 0)
    }
}
