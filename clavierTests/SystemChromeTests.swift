//
//  SystemChromeTests.swift
//  clavierTests
//
//  Menu bar, status items and Dock: their own token region in the assigner,
//  plus the pure discovery decisions in `SystemChromePolicy`.
//

import XCTest
import AppKit
@testable import clavier

final class SystemChromeAssignmentTests: XCTestCase {

    private let dummyAX: AXUIElement = AXUIElementCreateApplication(getpid())
    private let homeRow = HintCharacters(characters: Array("asdfhjkl"))

    private func element(x: Int, y: Int = 0, pid: pid_t = 4242, chrome: Bool = false) -> UIElement {
        let frame = CGRect(x: CGFloat(x), y: CGFloat(y), width: 40, height: 20)
        let role = chrome ? kAXMenuBarItemRole as String : "AXButton"
        return UIElement(
            stableID: ElementIdentity(pid: pid, role: role, frame: frame),
            axElement: dummyAX,
            frame: frame,
            visibleFrame: frame,
            isSystemChrome: chrome,
            role: role
        )
    }

    private func windowElements(_ count: Int) -> [UIElement] {
        (0..<count).map { element(x: ($0 % 10) * 50, y: ($0 / 10) * 30) }
    }

    private func chromeElements(_ count: Int) -> [UIElement] {
        (0..<count).map { element(x: $0 * 60, y: 2000, pid: 777, chrome: true) }
    }

    func test_chromeTokensStartWithLastLetter_windowTokensNever() {
        let elements = windowElements(30) + chromeElements(6)
        let result = HintAssigner.assign(to: elements, alphabet: homeRow, reservesSystemChromePrefix: true)

        XCTAssertEqual(result.count, 36)
        XCTAssertEqual(Set(result.map(\.hint)).count, 36)
        for hinted in result {
            XCTAssertEqual(hinted.hint.first == "l", hinted.element.isSystemChrome, hinted.hint)
        }
    }

    func test_windowTokensUnaffectedByWhetherChromeWasFound() {
        let windows = windowElements(30)
        let alone = HintAssigner.assign(to: windows, alphabet: homeRow, reservesSystemChromePrefix: true)
        let withChrome = HintAssigner.assign(
            to: windows + chromeElements(12),
            alphabet: homeRow,
            reservesSystemChromePrefix: true
        )
        XCTAssertEqual(Array(withChrome.prefix(30).map(\.hint)), alone.map(\.hint))
    }

    func test_chromeRegionLength_isCountDriven() {
        let few = HintAssigner.assign(to: chromeElements(8), alphabet: homeRow, reservesSystemChromePrefix: true)
        XCTAssertTrue(few.allSatisfy { $0.hint.count == 2 })

        let many = HintAssigner.assign(to: chromeElements(9), alphabet: homeRow, reservesSystemChromePrefix: true)
        XCTAssertTrue(many.allSatisfy { $0.hint.count == 3 && $0.hint.first == "l" })
        XCTAssertEqual(Set(many.map(\.hint)).count, 9)
    }

    func test_windowRegionLength_isCountDriven_withinItsLetters() {
        // Seven first letters × eight = 56 two-letter window tokens.
        let fits = HintAssigner.assign(to: windowElements(56), alphabet: homeRow, reservesSystemChromePrefix: true)
        XCTAssertTrue(fits.allSatisfy { $0.hint.count == 2 })
        let overflows = HintAssigner.assign(to: windowElements(57), alphabet: homeRow, reservesSystemChromePrefix: true)
        XCTAssertTrue(overflows.allSatisfy { $0.hint.count == 3 })
    }

    func test_withoutReservation_fullAlphabetIsUsed() {
        let result = HintAssigner.assign(to: windowElements(64), alphabet: homeRow)
        XCTAssertEqual(Set(result.map(\.hint)).count, 64)
        XCTAssertTrue(result.allSatisfy { $0.hint.count == 2 })
    }

    func test_refresh_preservesChromeAndWindowTokens() {
        let initial = HintAssigner.assign(
            to: windowElements(10) + chromeElements(4),
            alphabet: homeRow,
            reservesSystemChromePrefix: true
        )
        let refreshed = HintAssigner.assignPreservingHints(
            to: windowElements(12) + chromeElements(4),
            previous: initial,
            alphabet: homeRow,
            reservesSystemChromePrefix: true
        )
        let after = Dictionary(uniqueKeysWithValues: refreshed.map { ($0.identity, $0.hint) })
        for hinted in initial {
            XCTAssertEqual(after[hinted.identity], hinted.hint)
        }
    }
}

final class SystemChromePolicyTests: XCTestCase {

    private typealias Candidate = SystemChromePolicy.Candidate

    func test_statusProbeOrder_frontmostThenSystemHostsThenOthers() {
        let candidates = [
            Candidate(pid: 10, bundleID: "com.example.other", activationPolicy: .accessory),
            Candidate(pid: 11, bundleID: SystemChromePolicy.systemUIServerBundleID, activationPolicy: .prohibited),
            Candidate(pid: 12, bundleID: "com.example.front", activationPolicy: .regular),
            Candidate(pid: 13, bundleID: SystemChromePolicy.controlCenterBundleID, activationPolicy: .accessory),
            Candidate(pid: 14, bundleID: "com.example.later", activationPolicy: .regular),
        ]
        let order = SystemChromePolicy.statusProbeOrder(candidates, frontmostPID: 12, ownPID: 99)
        XCTAssertEqual(order.map(\.pid), [12, 13, 11, 10, 14])
    }

    func test_statusProbeOrder_skipsSelfDockAndBackgroundOnly() {
        let candidates = [
            Candidate(pid: 1, bundleID: "fabiogaliano.clavier", activationPolicy: .accessory),
            Candidate(pid: 2, bundleID: SystemChromePolicy.dockBundleID, activationPolicy: .regular),
            Candidate(pid: 3, bundleID: "com.example.daemon", activationPolicy: .prohibited),
            Candidate(pid: 4, bundleID: nil, activationPolicy: .accessory),
        ]
        let order = SystemChromePolicy.statusProbeOrder(candidates, frontmostPID: 50, ownPID: 1)
        XCTAssertEqual(order.map(\.pid), [4])
    }

    private let desktop = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func test_isHintable_menuBarAndDockItems() {
        let frame = CGRect(x: 100, y: 0, width: 40, height: 24)
        XCTAssertTrue(SystemChromePolicy.isHintable(role: kAXMenuBarItemRole as String, subrole: nil, frameAX: frame, desktopAX: desktop))
        XCTAssertTrue(SystemChromePolicy.isHintable(role: "AXDockItem", subrole: "AXApplicationDockItem", frameAX: frame, desktopAX: desktop))
        XCTAssertFalse(SystemChromePolicy.isHintable(role: kAXMenuRole as String, subrole: nil, frameAX: frame, desktopAX: desktop))
    }

    func test_isHintable_rejectsSeparatorsHiddenAndOffscreenItems() {
        let frame = CGRect(x: 100, y: 860, width: 10, height: 40)
        XCTAssertFalse(SystemChromePolicy.isHintable(role: "AXDockItem", subrole: "AXSeparatorDockItem", frameAX: frame, desktopAX: desktop))
        XCTAssertFalse(SystemChromePolicy.isHintable(role: kAXMenuBarItemRole as String, subrole: nil, frameAX: CGRect(x: 0, y: 0, width: 0, height: 24), desktopAX: desktop))
        XCTAssertFalse(SystemChromePolicy.isHintable(role: "AXDockItem", subrole: nil, frameAX: CGRect(x: 100, y: 950, width: 60, height: 60), desktopAX: desktop))
    }
}
