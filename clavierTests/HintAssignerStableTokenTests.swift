//
//  HintAssignerStableTokenTests.swift
//  clavierTests
//
//  The same element should get the same token every session: tokens come
//  from a stable per-element hash, collisions resolve deterministically, and
//  within-session preservation still wins over the hash.
//

import XCTest
@testable import clavier

final class HintAssignerStableTokenTests: XCTestCase {

    private let dummyAX: AXUIElement = AXUIElementCreateApplication(getpid())
    private let homeRow = HintCharacters(characters: Array("asdfhjkl"))

    private func element(x: Int, y: Int = 0, pid: pid_t = 4242, role: String = "AXButton") -> UIElement {
        let frame = CGRect(x: CGFloat(x), y: CGFloat(y), width: 40, height: 20)
        return UIElement(
            stableID: ElementIdentity(pid: pid, role: role, frame: frame),
            axElement: dummyAX,
            frame: frame,
            visibleFrame: frame,
            role: role
        )
    }

    private func grid(_ count: Int, pid: pid_t = 4242) -> [UIElement] {
        (0..<count).map { element(x: ($0 % 10) * 50, y: ($0 / 10) * 30, pid: pid) }
    }

    private func tokens(_ hinted: [HintedElement]) -> [ElementIdentity: String] {
        Dictionary(uniqueKeysWithValues: hinted.map { ($0.identity, $0.hint) })
    }

    // MARK: - Determinism

    func test_sameInputs_sameTokens() {
        let elements = grid(40)
        let first = HintAssigner.assign(to: elements, alphabet: homeRow)
        let second = HintAssigner.assign(to: elements, alphabet: homeRow)
        XCTAssertEqual(first.map(\.hint), second.map(\.hint))
        XCTAssertEqual(Set(first.map(\.hint)).count, 40)
    }

    func test_sameBundleAcrossRelaunch_sameTokens() {
        // A relaunched app has a new pid but the same bundle id.
        let before = grid(20, pid: 100)
        let after = grid(20, pid: 200)
        let first = HintAssigner.assign(to: before, alphabet: homeRow, bundleIDs: [100: "com.example.app"])
        let second = HintAssigner.assign(to: after, alphabet: homeRow, bundleIDs: [200: "com.example.app"])
        XCTAssertEqual(first.map(\.hint), second.map(\.hint))
    }

    func test_tokensDoNotFollowWalkOrder() {
        // Walk order only decides who wins a collision; uncontested elements
        // keep their token when the walk visits them in a different order.
        let elements = grid(12)
        let forward = tokens(HintAssigner.assign(to: elements, alphabet: homeRow))
        let reversed = tokens(HintAssigner.assign(to: elements.reversed(), alphabet: homeRow))

        let uncontested = elements.filter { candidate in
            let preferred = HintAssigner.preferredToken(for: candidate, alphabet: homeRow, elementCount: 12)
            return elements.filter {
                HintAssigner.preferredToken(for: $0, alphabet: homeRow, elementCount: 12) == preferred
            }.count == 1
        }
        XCTAssertFalse(uncontested.isEmpty)
        for candidate in uncontested {
            XCTAssertEqual(forward[candidate.stableID], reversed[candidate.stableID])
        }
    }

    // MARK: - Removal stability

    func test_elementRemoved_preferenceWinnersKeepTheirTokens() {
        let elements = grid(20)
        let before = tokens(HintAssigner.assign(to: elements, alphabet: homeRow))

        var remaining = elements
        remaining.remove(at: 7)
        let after = tokens(HintAssigner.assign(to: remaining, alphabet: homeRow))

        var winners = 0
        for candidate in remaining {
            let preferred = HintAssigner.preferredToken(for: candidate, alphabet: homeRow, elementCount: 20)
            guard before[candidate.stableID] == preferred else { continue }
            winners += 1
            XCTAssertEqual(after[candidate.stableID], preferred, "\(candidate.stableID) lost its token")
        }
        XCTAssertGreaterThan(winners, 10)
    }

    // MARK: - Collisions

    func test_collision_firstInWalkOrderWins_laterProbesToNextFreeToken() throws {
        let ab = HintCharacters(characters: Array("ab"))
        // A 2x2 token space makes a colliding pair easy to find.
        let pool = (0..<64).map { element(x: $0 * 50) }
        let preferred = pool.map { HintAssigner.preferredToken(for: $0, alphabet: ab, elementCount: 2)! }
        let firstIndex = try XCTUnwrap(pool.indices.first { i in
            pool.indices.contains { j in j > i && preferred[j] == preferred[i] }
        })
        let secondIndex = try XCTUnwrap(pool.indices.first { $0 > firstIndex && preferred[$0] == preferred[firstIndex] })
        let a = pool[firstIndex]
        let b = pool[secondIndex]
        let contested = preferred[firstIndex]

        let space = TokenSpace(alphabet: Array("ab"), firstLetters: Array("ab"), length: 2)
        let next = space.token(at: (space.index(of: contested)! + 1) % space.count)

        let ab1 = HintAssigner.assign(to: [a, b], alphabet: ab)
        XCTAssertEqual(ab1.map(\.hint), [contested, next])
        XCTAssertEqual(HintAssigner.assign(to: [a, b], alphabet: ab).map(\.hint), ab1.map(\.hint))

        let ba = HintAssigner.assign(to: [b, a], alphabet: ab)
        XCTAssertEqual(ba.map(\.hint), [contested, next])
    }

    // MARK: - Within-session preservation beats the hash

    func test_preservedToken_winsOverPreference() throws {
        let elements = grid(10)
        let target = elements[3]
        let preferred = try XCTUnwrap(
            HintAssigner.preferredToken(for: target, alphabet: homeRow, elementCount: 10)
        )
        let other = preferred == "ss" ? "dd" : "ss"
        let previous = [HintedElement(element: target, hint: other)]

        let result = tokens(HintAssigner.assignPreservingHints(
            to: elements,
            previous: previous,
            alphabet: homeRow
        ))
        XCTAssertEqual(result[target.stableID], other)
        XCTAssertEqual(Set(result.values).count, 10)
    }

    // MARK: - Performance

    func test_assign500Elements_performance() {
        let elements = (0..<500).map { element(x: ($0 % 25) * 50, y: ($0 / 25) * 30) }
        measure {
            _ = HintAssigner.assign(to: elements, alphabet: homeRow, bundleIDs: [4242: "com.example.app"])
        }
    }
}
