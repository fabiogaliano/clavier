//
//  HintLayoutTests.swift
//  clavierTests
//
//  Verifies the shared hint-label builder that both the production overlay
//  (`HintOverlayWindow`) and the debug overlay (`HintDebugOverlayWindow`)
//  use to produce hint views.  These tests lock the contract both sites
//  depend on: one view per element, views carry non-empty window-local
//  frames, and the frames match a direct `HintPlacementEngine` call for
//  an equivalent isolated layout.
//
//  Keeping one test over the shared helper is enough — its correctness
//  is then inherited by both overlays, which is the whole point of the
//  extraction.
//

import XCTest
@testable import clavier

final class HintLayoutTests: XCTestCase {

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

    @MainActor
    func test_buildLabels_returnsOneViewPerHintedElement() {
        let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let hintedA = HintedElement(
            element: makeElement(frame: CGRect(x: screen.midX - 60, y: screen.midY - 20, width: 120, height: 40)),
            hint: "ab"
        )
        let hintedB = HintedElement(
            element: makeElement(frame: CGRect(x: screen.midX - 60, y: screen.midY + 40, width: 120, height: 40)),
            hint: "cd"
        )

        let labels = HintLayout.buildLabels(
            for: [hintedA, hintedB],
            windowSize: ScreenGeometry.desktopBoundsInAppKit.size
        )

        XCTAssertEqual(labels.count, 2, "one label per input hinted element")
        XCTAssertEqual(labels[0].hinted.identity, hintedA.identity)
        XCTAssertEqual(labels[1].hinted.identity, hintedB.identity)

        for labeled in labels {
            XCTAssertGreaterThan(labeled.view.frame.width, 0, "view must carry a placed frame")
            XCTAssertGreaterThan(labeled.view.frame.height, 0)
        }
    }

    /// Production and debug overlays must agree on placement because they
    /// go through the same code path.  Exercise that guarantee by
    /// asserting the `buildLabels` frame lines up with a direct
    /// `HintPlacementEngine` call for the same input — if this ever
    /// drifts the two overlays will drift too.
    @MainActor
    func test_buildLabels_framesMatchDirectEngineCall() {
        let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let elementFrame = CGRect(x: screen.midX - 80, y: screen.midY - 20, width: 160, height: 40)
        let element = makeElement(frame: elementFrame)
        let hinted = HintedElement(element: element, hint: "jk")

        let windowSize = ScreenGeometry.desktopBoundsInAppKit.size
        let labels = HintLayout.buildLabels(for: [hinted], windowSize: windowSize)
        guard let built = labels.first else {
            XCTFail("expected one labeled view")
            return
        }

        // Re-run the engine with the same inputs the helper uses.  The
        // label size is the frame size produced by the helper because
        // the engine is what stamped it there.
        var engine = HintPlacementEngine(
            windowSize: windowSize,
            elementFrames: [element.visibleFrame]
        )
        let style = HintStyle()
        let expected = engine.place(
            element: element,
            labelSize: built.view.frame.size,
            horizontalOffset: style.horizontalOffset
        )

        XCTAssertEqual(built.view.frame.minX, expected.minX, accuracy: 0.5,
            "buildLabels must defer placement to HintPlacementEngine")
        XCTAssertEqual(built.view.frame.minY, expected.minY, accuracy: 0.5)
        XCTAssertEqual(built.view.frame.size, expected.size)
    }
}
