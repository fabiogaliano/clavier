//
//  HintAssignerTests.swift
//  clavierTests
//
//  Pure-function tests for `HintAssigner.assign`.  No AX / UserDefaults
//  interaction; we construct synthetic UIElements bound to this test process
//  solely to satisfy the initialiser.
//

import XCTest
@testable import clavier

final class HintAssignerTests: XCTestCase {

    // MARK: - Helpers

    private let dummyAX: AXUIElement = AXUIElementCreateApplication(getpid())

    private func makeElements(_ n: Int) -> [UIElement] {
        (0..<n).map { i in
            let frame = CGRect(x: CGFloat(i * 10), y: 0, width: 40, height: 20)
            return UIElement(
                stableID: ElementIdentity(pid: getpid(), role: "AXButton", frame: frame),
                axElement: dummyAX,
                frame: frame,
                visibleFrame: frame,
                role: "AXButton"
            )
        }
    }

    private func alphabet(_ s: String) -> HintCharacters {
        HintCharacters(characters: Array(s))
    }

    // MARK: - Empty + degenerate inputs

    func test_emptyElements_returnsEmpty() {
        XCTAssertEqual(HintAssigner.assign(to: [], alphabet: alphabet("ab")).count, 0)
    }

    func test_emptyAlphabet_returnsEmpty() {
        let elements = makeElements(5)
        XCTAssertEqual(HintAssigner.assign(to: elements, alphabet: alphabet("")).count, 0)
    }

    // MARK: - Two-character tokens

    func test_twoCharTokens_fullGrid() {
        // 2-letter alphabet, 4 elements → fills the 2×2 grid.
        let elements = makeElements(4)
        let result = HintAssigner.assign(to: elements, alphabet: alphabet("ab"))
        XCTAssertEqual(result.map { $0.hint }, ["aa", "ab", "ba", "bb"])
    }

    func test_twoCharTokens_partialGrid() {
        let elements = makeElements(3)
        let result = HintAssigner.assign(to: elements, alphabet: alphabet("ab"))
        XCTAssertEqual(result.map { $0.hint }, ["aa", "ab", "ba"])
    }

    // MARK: - Three-character tokens

    func test_threeCharTokens_whenCountExceedsTwoCharCombos() {
        // 2-letter alphabet produces 4 two-char combos; 5 elements forces 3-char.
        let elements = makeElements(5)
        let result = HintAssigner.assign(to: elements, alphabet: alphabet("ab"))
        XCTAssertEqual(result.count, 5)
        XCTAssertTrue(result.allSatisfy { $0.hint.count == 3 })
        XCTAssertEqual(result.map { $0.hint }, ["aaa", "aab", "aba", "abb", "baa"])
    }

    func test_threeCharTokens_cappedAtCubeOfAlphabet() {
        // 2-letter alphabet → max 8 three-char combos.  Request 20; only 8 are produced.
        let elements = makeElements(20)
        let result = HintAssigner.assign(to: elements, alphabet: alphabet("ab"))
        XCTAssertEqual(result.count, 8)
        XCTAssertEqual(Set(result.map { $0.hint }).count, 8)
    }

    // MARK: - Identity preservation

    func test_eachHintedElementCarriesOriginalElement() {
        let elements = makeElements(3)
        let result = HintAssigner.assign(to: elements, alphabet: alphabet("xyz"))
        for (input, hinted) in zip(elements, result) {
            XCTAssertEqual(input.stableID, hinted.element.stableID)
        }
    }
}
