//
//  ClickableElementWalkerCollectTests.swift
//  clavierTests
//
//  Pure tests for `ClickableElementWalker.collect`. The walker can reach the
//  same real AX element through multiple structural paths (for example a web
//  table exposing both row and column children). The overlay keys views by
//  `stableID`, so collect must collapse duplicate stable identities before
//  hint assignment.
//

import XCTest
@testable import clavier

@MainActor
final class ClickableElementWalkerCollectTests: XCTestCase {

    private let dummyAX: AXUIElement = AXUIElementCreateApplication(getpid())

    private func makeElement(
        frame: CGRect,
        role: String = "AXLink",
        text: String? = nil,
        visibleFrame: CGRect? = nil
    ) -> UIElement {
        UIElement(
            stableID: ElementIdentity(pid: getpid(), role: role, frame: frame),
            axElement: dummyAX,
            frame: frame,
            visibleFrame: visibleFrame ?? frame,
            role: role,
            textAttributes: text.map {
                ElementTextAttributes(title: nil, label: nil, value: nil, description: $0)
            }
        )
    }

    func test_collect_dropsStableIdentityDuplicates_preservingFirstOccurrence() {
        let frame = CGRect(x: 100, y: 200, width: 80, height: 24)
        let first = makeElement(
            frame: frame,
            text: "row-path",
            visibleFrame: CGRect(x: 100, y: 200, width: 60, height: 24)
        )
        let duplicate = makeElement(
            frame: frame,
            text: "column-path",
            visibleFrame: CGRect(x: 100, y: 200, width: 80, height: 24)
        )

        let collected = ClickableElementWalker.collect(pending: [
            PendingElement(element: first, clickableAncestorHash: nil),
            PendingElement(element: duplicate, clickableAncestorHash: nil)
        ])

        XCTAssertEqual(collected.count, 1)
        XCTAssertEqual(collected[0].textAttributes?.description, "row-path")
        XCTAssertEqual(collected[0].visibleFrame, first.visibleFrame)
    }

    func test_collect_stillDropsAncestorDedupedEntries() {
        let survivor = makeElement(frame: CGRect(x: 0, y: 0, width: 40, height: 20), text: "survivor")
        let deduped = makeElement(frame: CGRect(x: 50, y: 0, width: 40, height: 20), text: "deduped")

        let collected = ClickableElementWalker.collect(pending: [
            PendingElement(element: survivor, clickableAncestorHash: nil),
            PendingElement(element: deduped, clickableAncestorHash: 123)
        ])

        XCTAssertEqual(collected.count, 1)
        XCTAssertEqual(collected[0].textAttributes?.description, "survivor")
    }
}
