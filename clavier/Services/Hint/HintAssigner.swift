//
//  HintAssigner.swift
//  clavier
//
//  Pure hint-token assignment for a hint-mode session.
//
//  Given the discovered clickable elements and a `HintCharacters` alphabet,
//  produces a `[HintedElement]` list where each element is paired with a
//  two- or three-character token.  Token length is driven by element count
//  only; which token an element gets is driven by a stable hash of the
//  element, so the same button shows the same token from one session to the
//  next and muscle memory can form.
//

import Foundation
import AppKit

enum HintAssigner {

    /// Assign hint tokens to `elements` using `alphabet` as the token
    /// character set.  The result keeps the input order; elements beyond the
    /// token space (`alphabet.count^3`) are dropped so the overlay has a 1:1
    /// mapping between visible elements and usable hints.
    ///
    /// `bundleIDs` maps pids to bundle identifiers so preferences survive an
    /// app relaunch (a pid does not); missing pids fall back to the pid.
    static func assign(
        to elements: [UIElement],
        alphabet: HintCharacters,
        minimumTokenLength: Int = 2,
        bundleIDs: [pid_t: String] = [:]
    ) -> [HintedElement] {
        assignPreservingHints(
            to: elements,
            previous: [],
            alphabet: alphabet,
            minimumTokenLength: minimumTokenLength,
            bundleIDs: bundleIDs
        )
    }

    /// Like `assign`, but every element still present in `previous` keeps its
    /// token (when it is still valid for the new token length).  Within a
    /// session this beats the hash preference: labels must not reshuffle
    /// while the user may already be typing, e.g. while a cold browser
    /// renderer adds page controls to an already-visible overlay.
    static func assignPreservingHints(
        to elements: [UIElement],
        previous: [HintedElement],
        alphabet: HintCharacters,
        minimumTokenLength: Int = 2,
        bundleIDs: [pid_t: String] = [:]
    ) -> [HintedElement] {
        let chars = alphabet.characters
        guard !chars.isEmpty, !elements.isEmpty else { return [] }

        // Sizing from the larger of the two sets keeps the token length from
        // shrinking mid-session, which would invalidate every visible token.
        let space = TokenSpace(
            alphabet: chars,
            firstLetters: chars,
            elementCount: max(elements.count, previous.count),
            minimumTokenLength: minimumTokenLength
        )

        let preserved = Dictionary(
            previous.map { ($0.identity, $0.hint) },
            uniquingKeysWith: { first, _ in first }
        )
        let hasher = PreferenceHasher(bundleIDs: bundleIDs)
        var tokens = [String?](repeating: nil, count: elements.count)
        assignRegion(
            Array(elements.indices),
            of: elements,
            space: space,
            preserved: preserved,
            hasher: hasher,
            into: &tokens
        )

        var result: [HintedElement] = []
        result.reserveCapacity(elements.count)
        for (element, token) in zip(elements, tokens) {
            if let token { result.append(HintedElement(element: element, hint: token)) }
        }
        return result
    }

    // MARK: - Region assignment

    /// Assign tokens from `space` to the elements at `indices`, in three
    /// passes so the outcome depends only on the element set and walk order:
    /// 1. within-session preserved tokens,
    /// 2. each element's hash-preferred token (first claimant in walk order
    ///    wins a contested slot),
    /// 3. losers probe forward from their preferred slot to the next free
    ///    one, so a collision only ever displaces the later element.
    private static func assignRegion(
        _ indices: [Int],
        of elements: [UIElement],
        space: TokenSpace,
        preserved: [ElementIdentity: String],
        hasher: PreferenceHasher,
        into tokens: inout [String?]
    ) {
        guard space.count > 0 else { return }
        let candidates = indices.prefix(space.count)

        var used = [Bool](repeating: false, count: space.count)
        // Per candidate (aligned with `candidates`): assigned slot or -1.
        var slots = [Int](repeating: -1, count: candidates.count)
        var preferred = [Int](repeating: 0, count: candidates.count)

        if !preserved.isEmpty {
            for (position, index) in candidates.enumerated() {
                guard let hint = preserved[elements[index].stableID],
                      let slot = space.index(of: hint),
                      !used[slot] else { continue }
                used[slot] = true
                slots[position] = slot
            }
        }

        let spaceCount = UInt64(space.count)
        for (position, index) in candidates.enumerated() where slots[position] < 0 {
            let wanted = Int(hasher.hash(elements[index]) % spaceCount)
            preferred[position] = wanted
            if !used[wanted] {
                used[wanted] = true
                slots[position] = wanted
            }
        }

        for position in slots.indices where slots[position] < 0 {
            var probe = (preferred[position] + 1) % space.count
            while used[probe] { probe = (probe + 1) % space.count }
            used[probe] = true
            slots[position] = probe
        }

        for (position, index) in candidates.enumerated() {
            tokens[index] = space.token(at: slots[position])
        }
    }

    /// The hash-preferred token an element would take in a fresh assignment
    /// of `elementCount` elements; exposed so tests can tell a preference
    /// winner from a collision loser.
    static func preferredToken(
        for element: UIElement,
        alphabet: HintCharacters,
        elementCount: Int,
        minimumTokenLength: Int = 2,
        bundleIDs: [pid_t: String] = [:]
    ) -> String? {
        let space = TokenSpace(
            alphabet: alphabet.characters,
            firstLetters: alphabet.characters,
            elementCount: elementCount,
            minimumTokenLength: minimumTokenLength
        )
        guard space.count > 0 else { return nil }
        let hasher = PreferenceHasher(bundleIDs: bundleIDs)
        return space.token(at: Int(hasher.hash(element) % UInt64(space.count)))
    }
}

// MARK: - Token space

/// All tokens of one length whose first letter is drawn from `firstLetters`
/// and whose remaining letters are drawn from the full alphabet, addressed by
/// a dense index so assignment can track occupancy in a flat array.
struct TokenSpace {
    let alphabet: [Character]
    let firstLetters: [Character]
    let length: Int
    let count: Int
    private let tailCount: Int
    private let alphabetIndex: [Character: Int]
    private let firstLetterIndex: [Character: Int]

    init(alphabet: [Character], firstLetters: [Character], length: Int) {
        self.alphabet = alphabet
        self.firstLetters = firstLetters
        self.length = max(length, 1)
        var tail = 1
        for _ in 1..<self.length { tail *= alphabet.count }
        self.tailCount = tail
        self.count = alphabet.isEmpty ? 0 : firstLetters.count * tail
        self.alphabetIndex = Dictionary(alphabet.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        self.firstLetterIndex = Dictionary(firstLetters.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Two characters while they suffice, otherwise three (the cap: anything
    /// beyond `firstLetters.count * n^2` elements goes unhinted).
    init(alphabet: [Character], firstLetters: [Character], elementCount: Int, minimumTokenLength: Int) {
        let twoCharCapacity = firstLetters.count * alphabet.count
        let length = minimumTokenLength >= 3 || elementCount > twoCharCapacity ? 3 : 2
        self.init(alphabet: alphabet, firstLetters: firstLetters, length: length)
    }

    func token(at index: Int) -> String {
        var token = String(firstLetters[index / tailCount])
        var divisor = tailCount
        var rest = index % tailCount
        while divisor > 1 {
            divisor /= alphabet.count
            token.append(alphabet[rest / divisor])
            rest %= divisor
        }
        return token
    }

    func index(of token: String) -> Int? {
        var iterator = token.makeIterator()
        guard let firstChar = iterator.next(),
              let first = firstLetterIndex[firstChar] else { return nil }
        var index = first
        var length = 1
        while let char = iterator.next() {
            guard let value = alphabetIndex[char] else { return nil }
            index = index * alphabet.count + value
            length += 1
        }
        return length == self.length ? index : nil
    }
}

// MARK: - Preference hash

/// FNV-style hash of (bundle id or pid, role, rounded frame).  Swift's `Hasher` is
/// seeded per process, so it cannot be used for a preference that must be the
/// same in the next session.  Text attributes are deliberately excluded: they
/// are hydrated after assignment, so including them would make the initial
/// pass and later refreshes disagree.
struct PreferenceHasher {
    private let appSeeds: [pid_t: UInt64]

    private static let offsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325
    private static let prime: UInt64 = 0x0000_0100_0000_01b3

    init(bundleIDs: [pid_t: String]) {
        appSeeds = bundleIDs.mapValues { Self.fnv(Self.offsetBasis, $0.utf8) }
    }

    func hash(_ element: UIElement) -> UInt64 {
        let identity = element.stableID
        var value = appSeeds[identity.pid]
            ?? Self.mix(Self.offsetBasis, UInt64(bitPattern: Int64(identity.pid)))
        value = Self.fnv(value, identity.role.utf8)
        let frame = identity.roundedFrame
        value = Self.mix(value, UInt64(bitPattern: Int64(frame.origin.x)))
        value = Self.mix(value, UInt64(bitPattern: Int64(frame.origin.y)))
        value = Self.mix(value, UInt64(bitPattern: Int64(frame.size.width)))
        value = Self.mix(value, UInt64(bitPattern: Int64(frame.size.height)))
        return value
    }

    private static func fnv(_ start: UInt64, _ bytes: String.UTF8View) -> UInt64 {
        var value = start
        for byte in bytes {
            value ^= UInt64(byte)
            value = value &* prime
        }
        return value
    }

    /// One multiply-xorshift round per word: a whole-word step keeps the hot
    /// path cheap while still spreading every input bit into the low bits the
    /// modulo keeps.
    private static func mix(_ value: UInt64, _ word: UInt64) -> UInt64 {
        var result = (value ^ word) &* prime
        result ^= result >> 29
        return result
    }
}

// MARK: - Bundle id lookup

extension HintAssigner {
    /// Bundle identifiers for every pid among `elements`, for `bundleIDs:`.
    @MainActor
    static func runningBundleIDs(for elements: [UIElement]) -> [pid_t: String] {
        var result: [pid_t: String] = [:]
        for pid in Set(elements.map(\.stableID.pid)) {
            if let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier {
                result[pid] = bundleID
            }
        }
        return result
    }
}
