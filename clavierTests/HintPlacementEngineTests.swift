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

    // MARK: - Placement ordering: inside-first for small hints

    /// When the hint label fits comfortably inside the element (< 70 % of
    /// element width), the engine must return a rect whose top-left corner lies
    /// INSIDE the element bounds (window-local y ∈ [element.minY, element.maxY)).
    func testInsideFirstPlacementWhenHintFitsElement() {
        let screen = mainScreen
        // Place a spacious element well inside the screen so no clamping fires.
        let el = CGRect(x: screen.midX - 60, y: screen.midY - 20, width: 120, height: 40)
        let element = makeElement(frame: el)
        let ws = windowSize

        var engine = HintPlacementEngine(windowSize: ws)
        // Label 24 × 16 pt — well under 70 % of element width (120 pt)
        let labelSize = CGSize(width: 24, height: 16)
        let placed = engine.place(element: element, labelSize: labelSize, horizontalOffset: 0)

        // Convert element frame to window-local for comparison
        let elLocal = ScreenGeometry.toWindowLocal(el)

        // Inside-first strategy: top of label should be at or below element.minY (in window-local),
        // and bottom of label should be at or below element.maxY.
        XCTAssertGreaterThanOrEqual(placed.minY, elLocal.minY - 1,
            "inside placement: label top should not be below element bottom")
        XCTAssertLessThanOrEqual(placed.maxY, elLocal.maxY + 1,
            "inside placement: label should fit within element height")
    }

    // MARK: - Placement ordering: outside-first for large hints

    /// When the hint label fills ≥ 70 % of the element width, the engine should
    /// prefer placing the label OUTSIDE the element (above or below) rather than
    /// inside.  The placed rect should not overlap the element's vertical range
    /// (allowing a 1-pt tolerance for the gap).
    func testOutsideFirstPlacementWhenHintFillsElement() {
        let screen = mainScreen
        // Small element with wide label to trigger fillsElement path.
        // Place it far from edges so no edge clamping hides the placement choice.
        let el = CGRect(x: screen.midX - 15, y: screen.midY - 10, width: 30, height: 20)
        let element = makeElement(frame: el)
        let ws = windowSize

        var engine = HintPlacementEngine(windowSize: ws)
        // Label 24 pt wide: 24/30 = 80 % → fillsElement = true
        let labelSize = CGSize(width: 24, height: 16)
        let placed = engine.place(element: element, labelSize: labelSize, horizontalOffset: 0)

        let elLocal = ScreenGeometry.toWindowLocal(el)

        // Outside-first: label should not overlap the element's interior.
        let labelIntersectsElement = placed.intersects(elLocal.insetBy(dx: 1, dy: 1))
        XCTAssertFalse(labelIntersectsElement,
            "outside-first placement \(placed) should not overlap element interior \(elLocal)")
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
