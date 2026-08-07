import XCTest
@testable import clavier

final class BrowserWebAreaReadinessPolicyTests: XCTestCase {

    private let policy = BrowserWebAreaReadinessPolicy()

    func test_largeBrowserWindowWithoutWebArea_waitsRegardlessOfNativeControlCount() {
        XCTAssertTrue(
            policy.shouldWait(
                windowFrame: CGRect(x: 0, y: 0, width: 1_200, height: 800),
                containsWebArea: false
            )
        )
    }

    func test_existingWebArea_isStructurallyReady() {
        XCTAssertFalse(
            policy.shouldWait(
                windowFrame: CGRect(x: 0, y: 0, width: 1_200, height: 800),
                containsWebArea: true
            )
        )
    }

    func test_smallBrowserSurface_doesNotWaitForPageContent() {
        XCTAssertFalse(
            policy.shouldWait(
                windowFrame: CGRect(x: 0, y: 0, width: 320, height: 240),
                containsWebArea: false
            )
        )
    }

    func test_missingFocusedWindow_doesNotIntroduceColdStartDelay() {
        XCTAssertFalse(policy.shouldWait(windowFrame: nil, containsWebArea: false))
    }
}
