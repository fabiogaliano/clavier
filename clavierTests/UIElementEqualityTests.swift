import XCTest
@testable import clavier

final class UIElementEqualityTests: XCTestCase {

    private let dummyAX: AXUIElement = AXUIElementCreateApplication(getpid())

    private func make(frame: CGRect, text: ElementTextAttributes? = nil) -> UIElement {
        UIElement(
            stableID: ElementIdentity(pid: getpid(), role: "AXButton", frame: frame),
            axElement: dummyAX,
            frame: frame,
            visibleFrame: frame,
            role: "AXButton",
            textAttributes: text
        )
    }

    func test_identicalSnapshots_areEqual() {
        let frame = CGRect(x: 10, y: 20, width: 30, height: 40)
        XCTAssertEqual(make(frame: frame), make(frame: frame))
        XCTAssertEqual(
            HintedElement(element: make(frame: frame), hint: "as"),
            HintedElement(element: make(frame: frame), hint: "as")
        )
    }

    func test_differentGeometryOrText_areNotEqual() {
        let frame = CGRect(x: 10, y: 20, width: 30, height: 40)
        XCTAssertNotEqual(make(frame: frame), make(frame: frame.offsetBy(dx: 5, dy: 0)))
        let hydrated = ElementTextAttributes(title: "OK", label: nil, value: nil, description: nil)
        XCTAssertNotEqual(make(frame: frame), make(frame: frame, text: hydrated))
    }
}
