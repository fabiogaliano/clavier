import ApplicationServices
import XCTest
@testable import clavier

@MainActor
final class ChromiumAccessibilityWakerTests: XCTestCase {

    func test_knownBrowserRegistry_includesHeliumAndExistingDetectors() {
        let expected = [
            "net.imput.helium",
            "com.google.Chrome",
            "company.thebrowser.Browser",
            "com.microsoft.edgemac",
            "com.brave.Browser"
        ]

        for bundleId in expected {
            XCTAssertTrue(ChromiumAccessibilityWaker.isKnownBrowser(bundleId: bundleId), bundleId)
        }
        XCTAssertFalse(ChromiumAccessibilityWaker.isKnownBrowser(bundleId: "com.tinyspeck.slackmacgap"))
    }

    func test_knownChromiumApp_includesBrowsersAndElectron() {
        XCTAssertTrue(ChromiumAccessibilityWaker.isKnownChromiumApp(bundleId: "net.imput.helium"))
        XCTAssertTrue(ChromiumAccessibilityWaker.isKnownChromiumApp(bundleId: "com.tinyspeck.slackmacgap"))
        XCTAssertFalse(ChromiumAccessibilityWaker.isKnownChromiumApp(bundleId: "com.apple.TextEdit"))
    }

    func test_enhancedWriteAcceptance_usesReadBackWhenHeliumReturnsNotImplemented() {
        XCTAssertTrue(
            ChromiumAccessibilityWaker.enhancedWriteWasAccepted(
                writeResult: .notImplemented,
                readBack: true
            )
        )
    }

    func test_enhancedWriteAcceptance_rejectsFailedWriteWithoutPositiveReadBack() {
        XCTAssertFalse(
            ChromiumAccessibilityWaker.enhancedWriteWasAccepted(
                writeResult: .notImplemented,
                readBack: false
            )
        )
        XCTAssertFalse(
            ChromiumAccessibilityWaker.enhancedWriteWasAccepted(
                writeResult: .attributeUnsupported,
                readBack: nil
            )
        )
    }
}
