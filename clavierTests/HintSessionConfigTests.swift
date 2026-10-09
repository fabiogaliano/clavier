//
//  HintSessionConfigTests.swift
//  clavierTests
//

import XCTest
@testable import clavier

final class HintSessionConfigTests: XCTestCase {

    private func makeConfig(autoDeactivation: Bool, delay: TimeInterval = 3) -> HintSessionConfig {
        HintSessionConfig(
            autoDeactivation: autoDeactivation,
            deactivationDelay: delay,
            initialMode: .oneShot,
            inputContext: HintInputContext(textSearchEnabled: true, minSearchChars: 2, refreshTrigger: "rr")
        )
    }

    func test_continuousSession_withAutoDeactivation_usesConfiguredDelay() {
        XCTAssertEqual(makeConfig(autoDeactivation: true, delay: 3).autoDeactivationDelay(for: .continuous), 3)
    }

    func test_continuousSession_withoutAutoDeactivation_hasNoTimer() {
        XCTAssertNil(makeConfig(autoDeactivation: false).autoDeactivationDelay(for: .continuous))
    }

    func test_oneShotSession_neverTimesOut() {
        XCTAssertNil(makeConfig(autoDeactivation: true).autoDeactivationDelay(for: .oneShot))
    }
}
