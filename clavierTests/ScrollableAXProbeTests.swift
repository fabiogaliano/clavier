//
//  ScrollableAXProbeTests.swift
//  clavierTests
//
//  Invariants for the shared scroll-detection probe. Predicates that depend
//  on a live AXUIElement (`hasScrollBars`, `hasWebAncestor`, `makeArea`) are
//  exercised end-to-end via integration paths; here we cover the static
//  configuration that drives them — the scrollable role allow-list and the
//  ancestor-walk depth cap — to lock in the surface that the traverser and
//  focused finder both depend on.
//

import XCTest
@testable import clavier
import ApplicationServices

@MainActor
final class ScrollableAXProbeTests: XCTestCase {

    // MARK: - Role allow-list

    func test_scrollableRoles_includeAXScrollArea() {
        XCTAssertTrue(ScrollableAXProbe.scrollableRoles.contains("AXScrollArea"))
    }

    func test_scrollableRoles_includeAXScrollView() {
        XCTAssertTrue(ScrollableAXProbe.scrollableRoles.contains("AXScrollView"))
    }

    func test_scrollableRoles_includeListGridContainers() {
        XCTAssertTrue(ScrollableAXProbe.scrollableRoles.contains(kAXTableRole as String))
        XCTAssertTrue(ScrollableAXProbe.scrollableRoles.contains(kAXOutlineRole as String))
        XCTAssertTrue(ScrollableAXProbe.scrollableRoles.contains(kAXListRole as String))
    }

    func test_scrollableRoles_excludeAXWebArea() {
        // AXWebArea is intentionally absent — including it would cause massive
        // over-detection in browsers. Web scrollables are reached via
        // hasWebAncestor on a child with a scrollable role.
        XCTAssertFalse(ScrollableAXProbe.scrollableRoles.contains("AXWebArea"))
    }

    func test_scrollableRoles_excludeAXTextArea() {
        // AXTextArea is too generic — a plain <textarea> would otherwise
        // register as a scroll target.
        XCTAssertFalse(ScrollableAXProbe.scrollableRoles.contains("AXTextArea"))
    }

    func test_scrollableRoles_excludeBareGroup() {
        // AXGroup is the most common AX role on the planet; treating it as
        // scrollable would make the traverser useless.
        XCTAssertFalse(ScrollableAXProbe.scrollableRoles.contains(kAXGroupRole as String))
    }

    // MARK: - Ancestor walk depth

    func test_maxAncestorWalk_isPositive() {
        XCTAssertGreaterThan(ScrollableAXProbe.maxAncestorWalk, 0,
                             "Ancestor walk must take at least one step.")
    }

    func test_maxAncestorWalk_isBoundedReasonably() {
        // Deep enough to clear realistic web-content nesting (Chrome devtools
        // sits ~6 levels below AXWebArea), but not so deep that a malicious
        // or buggy chain stalls the main thread.
        XCTAssertLessThanOrEqual(ScrollableAXProbe.maxAncestorWalk, 32)
    }
}
