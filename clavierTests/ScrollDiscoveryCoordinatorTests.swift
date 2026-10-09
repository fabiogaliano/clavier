//
//  ScrollDiscoveryCoordinatorTests.swift
//  clavierTests
//
//  Feeds scripted Phase 1 / Phase 2 results through the coordinator via a
//  fake service and checks the emitted `DiscoveryEvent` stream.
//

import XCTest
@testable import clavier

@MainActor
final class ScrollDiscoveryCoordinatorTests: XCTestCase {

    private final class FakeScrollableAreaService: ScrollableAreaService {
        var focused: ScrollableArea?
        var traversal: [ScrollableArea] = []
        private(set) var requestedMaxAreas: Int?

        override func findFocusedScrollableArea() -> ScrollableArea? { focused }

        override func getScrollableAreas(
            onAreaFound: ((ScrollableArea) -> Void)? = nil,
            maxAreas: Int? = nil
        ) -> [ScrollableArea] {
            requestedMaxAreas = maxAreas
            traversal.forEach { onAreaFound?($0) }
            return traversal
        }
    }

    private let dummyAX: AXUIElement = AXUIElementCreateApplication(getpid())

    // Far off any display so `isCursorInside` is deterministically false.
    private func area(x: CGFloat, y: CGFloat = 0, width: CGFloat = 100, height: CGFloat = 100) -> ScrollableArea {
        ScrollableArea(axElement: dummyAX, frame: CGRect(x: -100_000 + x, y: y, width: width, height: height))
    }

    /// Contains every point on every display, so the cursor is always inside.
    private func areaUnderCursor() -> ScrollableArea {
        ScrollableArea(axElement: dummyAX, frame: CGRect(x: -1_000_000, y: -1_000_000, width: 2_000_000, height: 2_000_000))
    }

    private func describe(_ event: DiscoveryEvent) -> String {
        switch event {
        case .areaAddedPhase1: return "phase1"
        case .areaAddedPhase2(_, let inside): return "phase2(cursor:\(inside))"
        case .areaReplaced(_, let indices, let inside): return "replaced(\(indices),cursor:\(inside))"
        }
    }

    private func run(_ service: FakeScrollableAreaService) -> [DiscoveryEvent] {
        let coordinator = ScrollDiscoveryCoordinator(service: service, merger: ScrollableAreaMerger())
        var events: [DiscoveryEvent] = []
        coordinator.discover { events.append($0) }
        return events
    }

    func test_focusedArea_emittedFirstAsPhase1_andDedupesPhase2Duplicate() {
        let service = FakeScrollableAreaService()
        let focused = area(x: 0)
        service.focused = focused
        service.traversal = [area(x: 2), area(x: 500)]

        let events = run(service)

        XCTAssertEqual(events.map(describe), ["phase1", "phase2(cursor:false)"])
    }

    func test_noFocusedArea_phase2OnlyEvents() {
        let service = FakeScrollableAreaService()
        service.traversal = [area(x: 0), area(x: 500)]

        XCTAssertEqual(run(service).map(describe), ["phase2(cursor:false)", "phase2(cursor:false)"])
    }

    func test_nestedCandidate_isDropped() {
        let service = FakeScrollableAreaService()
        service.traversal = [area(x: 0, width: 400, height: 400), area(x: 0, y: 10, width: 200, height: 100)]

        XCTAssertEqual(run(service).map(describe), ["phase2(cursor:false)"])
    }

    func test_enclosingCandidate_replacesEarlierAreas() {
        let service = FakeScrollableAreaService()
        service.traversal = [
            area(x: 0, y: 10, width: 100, height: 100),
            area(x: 500),
            area(x: 0, y: 0, width: 300, height: 300),
        ]

        let events = run(service)

        XCTAssertEqual(events.map(describe), ["phase2(cursor:false)", "phase2(cursor:false)", "replaced([0],cursor:false)"])
    }

    func test_cursorInsideArea_isReported() {
        let service = FakeScrollableAreaService()
        service.traversal = [areaUnderCursor()]

        XCTAssertEqual(run(service).map(describe), ["phase2(cursor:true)"])
    }

    func test_capsAtFifteenAreas() {
        let service = FakeScrollableAreaService()
        service.traversal = (0..<20).map { area(x: CGFloat($0) * 200) }

        let events = run(service)

        XCTAssertEqual(events.count, 15)
        XCTAssertEqual(service.requestedMaxAreas, 15)
    }

    /// The coordinator's replacement indices must line up with the session the
    /// reducer builds from the same event stream.
    func test_eventStream_foldsIntoContiguousSession() {
        let service = FakeScrollableAreaService()
        let focused = area(x: 1000)
        let enclosing = area(x: 0, y: 0, width: 300, height: 300)
        service.focused = focused
        service.traversal = [area(x: 0, y: 10, width: 100, height: 100), area(x: 500), enclosing]

        var session = ScrollSession.inactive
        for event in run(service) {
            session = ScrollSelectionReducer.reduce(session: session, discovery: event).0
        }

        XCTAssertEqual(session.areas.map(\.number), ["1", "2", "3"])
        XCTAssertEqual(session.areas.first?.identity, focused.stableID)
        XCTAssertEqual(session.areas.last?.identity, enclosing.stableID)
        XCTAssertEqual(session.selectedIndex, 0, "the focused area stays selected")
    }
}
