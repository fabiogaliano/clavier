//
//  HintPlacementEngineTests.swift
//  clavierTests
//
//  Focused tests for HintPlacementEngine: placement ordering, collision
//  resolution, and viewport clamping.
//
//  Tests exercise the engine's pure geometry logic.  AXUIElement is constructed
//  from the current process pid — not to interact with its accessibility tree,
//  but purely to satisfy the UIElement initialiser which requires an AXUIElement
//  reference.
//
//  Coordinate note: HintPlacementEngine.place() returns coordinates in the
//  overlay window's local space (via ScreenGeometry.toWindowLocal).  Tests
//  therefore assert on window-local invariants (bounds, collision, offset delta)
//  rather than absolute screen-space positions that vary by display layout.
//

import XCTest
@testable import clavier

final class HintPlacementEngineTests: XCTestCase {

    // MARK: - Helpers

    /// Synthetic AX element scoped to this test process (never queried, just
    /// satisfies the UIElement initialiser contract).
    private let dummyAX: AXUIElement = AXUIElementCreateApplication(getpid())

    private func makeElement(frame: CGRect) -> UIElement {
        UIElement(
            stableID: ElementIdentity(pid: getpid(), role: "AXButton", frame: frame),
            axElement: dummyAX,
            frame: frame,
            visibleFrame: frame,
            role: "AXButton"
        )
    }

    /// The main screen frame in AppKit coordinates.  All test elements must be
    /// placed within this frame so the screen-clamping step in the engine stays
    /// neutral and doesn't mask the behavior under test.
    private var mainScreen: CGRect {
        NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private var windowSize: CGSize {
        ScreenGeometry.desktopBoundsInAppKit.size
    }

    // MARK: - First-candidate placement (isolated element)

    /// The current engine (see `HintPlacementEngine`, cluster-first cost-ranked
    /// greedy) picks the first zero-cost candidate for an isolated element.
    /// Candidate #0 is horizontally centred on the element (offset by the
    /// configured `horizontalOffset`), so `placed.midX` should align with
    /// `elLocal.midX` within a sub-pixel tolerance.
    func testIsolatedElementPlacementIsHorizontallyCentred() {
        let screen = mainScreen
        let el = CGRect(x: screen.midX - 60, y: screen.midY - 20, width: 120, height: 40)
        let element = makeElement(frame: el)

        var engine = HintPlacementEngine(windowSize: windowSize)
        let labelSize = CGSize(width: 24, height: 16)
        let placed = engine.place(element: element, labelSize: labelSize, horizontalOffset: 0)

        let elLocal = ScreenGeometry.toWindowLocal(el)
        XCTAssertEqual(placed.midX, elLocal.midX, accuracy: 1.0,
            "isolated placement must keep the label centred on the element")
    }

    /// An isolated small element must still receive a placement whose size
    /// equals the requested label size and whose origin is on-screen.  This
    /// is the minimum contract the renderer relies on when a tiny target
    /// (e.g. a 30×20 icon) carries a wider hint label.
    func testIsolatedSmallElementGetsValidPlacement() {
        let screen = mainScreen
        let el = CGRect(x: screen.midX - 15, y: screen.midY - 10, width: 30, height: 20)
        let element = makeElement(frame: el)

        var engine = HintPlacementEngine(windowSize: windowSize)
        let labelSize = CGSize(width: 24, height: 16)
        let placed = engine.place(element: element, labelSize: labelSize, horizontalOffset: 0)

        XCTAssertEqual(placed.size, labelSize, "engine must preserve label size")
        XCTAssertGreaterThanOrEqual(placed.minX, 0, "placement must stay in window bounds")
        XCTAssertGreaterThanOrEqual(placed.minY, 0, "placement must stay in window bounds")
        XCTAssertLessThanOrEqual(placed.maxX, windowSize.width)
        XCTAssertLessThanOrEqual(placed.maxY, windowSize.height)
    }

    // MARK: - Collision resolution

    /// When the first candidate position collides with an already-placed hint,
    /// the engine should return a non-colliding position for the second hint.
    func testCollisionForcesAlternativePosition() {
        let screen = mainScreen
        let ws = windowSize

        // Both elements share the same frame — same first candidate → collision
        let sharedFrame = CGRect(x: screen.midX - 100, y: screen.midY - 20, width: 200, height: 40)
        let el1 = makeElement(frame: sharedFrame)
        let el2 = makeElement(frame: sharedFrame)

        var engine = HintPlacementEngine(windowSize: ws)
        let labelSize = CGSize(width: 24, height: 16)

        let first = engine.place(element: el1, labelSize: labelSize, horizontalOffset: 0)
        let second = engine.place(element: el2, labelSize: labelSize, horizontalOffset: 0)

        // Engine uses a 3 pt inset when collision-checking.
        let expandedFirst = first.insetBy(dx: -3, dy: -3)
        XCTAssertFalse(expandedFirst.intersects(second),
            "second placement \(second) must not collide with first \(first)")
    }

    // MARK: - Viewport clamping

    /// Any placed hint must remain within [0, windowSize.width] × [0, windowSize.height].
    func testPlacedHintStaysWithinWindowBounds() {
        let ws = windowSize
        let screen = mainScreen

        // Element at the far right of the screen to stress right/top clamping
        let el = CGRect(x: screen.maxX - 20, y: screen.maxY - 10, width: 40, height: 20)
        let element = makeElement(frame: el)

        var engine = HintPlacementEngine(windowSize: ws)
        let labelSize = CGSize(width: 30, height: 16)
        let placed = engine.place(element: element, labelSize: labelSize, horizontalOffset: 0)

        XCTAssertGreaterThanOrEqual(placed.minX, 0, "hint must not have negative x")
        XCTAssertGreaterThanOrEqual(placed.minY, 0, "hint must not have negative y")
        XCTAssertLessThanOrEqual(placed.maxX, ws.width + 1,
            "hint maxX \(placed.maxX) must not exceed window width \(ws.width)")
        XCTAssertLessThanOrEqual(placed.maxY, ws.height + 1,
            "hint maxY \(placed.maxY) must not exceed window height \(ws.height)")
    }

    /// A hint element at the left edge of the screen must produce a clamped hint
    /// with x ≥ 0.
    func testClampingAtLeftEdge() {
        let ws = windowSize
        let screen = mainScreen

        let el = CGRect(x: screen.minX + 2, y: screen.midY, width: 40, height: 20)
        let element = makeElement(frame: el)

        var engine = HintPlacementEngine(windowSize: ws)
        let placed = engine.place(element: element, labelSize: CGSize(width: 24, height: 16), horizontalOffset: 0)

        XCTAssertGreaterThanOrEqual(placed.minX, 0, "hint x must not be negative")
    }

    // MARK: - Horizontal offset delta

    /// The `horizontalOffset` parameter should shift the final x position by
    /// exactly that amount when no clamping or collision is in play.  Test this
    /// as a delta between offset=0 and offset=8.
    func testHorizontalOffsetShiftsAnchorX() {
        let ws = windowSize
        let screen = mainScreen

        // Spacious element away from edges so neither clamping nor screen-clamp fires.
        let el = CGRect(x: screen.midX - 100, y: screen.midY - 20, width: 200, height: 40)
        let element = makeElement(frame: el)
        let labelSize = CGSize(width: 24, height: 16)

        var engine0 = HintPlacementEngine(windowSize: ws)
        var engine8 = HintPlacementEngine(windowSize: ws)

        let placed0 = engine0.place(element: element, labelSize: labelSize, horizontalOffset: 0)
        let placed8 = engine8.place(element: element, labelSize: labelSize, horizontalOffset: 8)

        // The two results should differ by exactly 8 pt on x (no clamping involved).
        XCTAssertEqual(placed8.minX - placed0.minX, 8, accuracy: 1,
            "horizontalOffset 8 should shift x by 8 pt; got delta \(placed8.minX - placed0.minX)")
    }

    // MARK: - Placement size preservation

    /// The engine must not change the label size — only the origin should move.
    func testPlacedRectPreservesLabelSize() {
        let ws = windowSize
        let screen = mainScreen
        let el = CGRect(x: screen.midX - 50, y: screen.midY - 20, width: 100, height: 40)
        let element = makeElement(frame: el)
        let labelSize = CGSize(width: 32, height: 18)

        var engine = HintPlacementEngine(windowSize: ws)
        let placed = engine.place(element: element, labelSize: labelSize, horizontalOffset: 0)

        XCTAssertEqual(placed.width, labelSize.width, accuracy: 0.1,
            "placed rect width must match label width")
        XCTAssertEqual(placed.height, labelSize.height, accuracy: 0.1,
            "placed rect height must match label height")
    }
}
