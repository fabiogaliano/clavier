//
//  ElementTextAttributesTests.swift
//  clavierTests
//
//  Pure-model tests for the new `ElementTextAttributes` struct and its
//  integration with `UIElement.searchableText`.  These cover hydration shape
//  without touching the AX API — the hydrator itself requires a real AX
//  target so it is tested via the existing hint-mode integration paths.
//

import XCTest
@testable import clavier

final class ElementTextAttributesTests: XCTestCase {

    // MARK: - searchableText composition

    func test_searchableText_joinsNonEmptyFields() {
        let attrs = ElementTextAttributes(
            title: "Save",
            label: nil,
            value: "default.txt",
            description: nil
        )
        XCTAssertEqual(attrs.searchableText, "Save default.txt")
    }

    func test_searchableText_dropsEmptyStrings() {
        let attrs = ElementTextAttributes(
            title: "",
            label: "Close",
            value: "",
            description: "dialog close button"
        )
        XCTAssertEqual(attrs.searchableText, "Close dialog close button")
    }

    func test_searchableText_emptyWhenAllFieldsMissing() {
        let attrs = ElementTextAttributes(title: nil, label: nil, value: nil, description: nil)
        XCTAssertEqual(attrs.searchableText, "")
    }

    // MARK: - UIElement integration

    private let dummyAX: AXUIElement = AXUIElementCreateApplication(getpid())

    private func makeElement(attributes: ElementTextAttributes?) -> UIElement {
        var element = UIElement(
            stableID: ElementIdentity(pid: getpid(), role: "AXButton", frame: .zero),
            axElement: dummyAX,
            frame: .zero,
            visibleFrame: .zero,
            role: "AXButton"
        )
        element.textAttributes = attributes
        return element
    }

    func test_uielement_searchableText_isEmpty_beforeHydration() {
        let element = makeElement(attributes: nil)
        XCTAssertEqual(element.searchableText, "",
            "searchableText must be empty until textAttributes is hydrated")
    }

    func test_uielement_searchableText_reflectsHydratedAttributes() {
        let element = makeElement(attributes: ElementTextAttributes(
            title: "Open",
            label: nil,
            value: nil,
            description: "primary action"
        ))
        XCTAssertEqual(element.searchableText, "Open primary action")
    }

    func test_uielement_searchableText_isEmpty_whenHydrationFoundNothing() {
        // A hydration pass that finds no text still produces a non-nil
        // ElementTextAttributes (fields all nil) so repeat hydration skips
        // the element.  searchableText should still be empty.
        let element = makeElement(attributes: ElementTextAttributes(
            title: nil, label: nil, value: nil, description: nil
        ))
        XCTAssertEqual(element.searchableText, "")
    }
}
