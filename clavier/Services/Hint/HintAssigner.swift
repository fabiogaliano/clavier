//
//  HintAssigner.swift
//  clavier
//
//  Pure hint-token assignment for a hint-mode session.
//
//  Given the discovered clickable elements and a `HintCharacters` alphabet,
//  produces a `[HintedElement]` list where each element is paired with a
//  deterministic two- or three-character token.
//
//  Extracted from `HintModeController.assignHints` (P4 thinning pass) so the
//  mapping is a testable pure function with no dependency on UserDefaults or
//  the AX API.
//

import Foundation

enum HintAssigner {

    /// Assign hint tokens to `elements` using `alphabet` as the token
    /// character set.  The resulting array is aligned with the input prefix
    /// (it will contain at most `alphabet.count^3` entries — any extra
    /// discovered elements are dropped so the overlay has a 1:1 mapping
    /// between visible elements and usable hints).
    static func assign(
        to elements: [UIElement],
        alphabet: HintCharacters,
        minimumTokenLength: Int = 2
    ) -> [HintedElement] {
        let hints = tokens(
            alphabet: alphabet,
            elementCount: elements.count,
            minimumTokenLength: minimumTokenLength
        )
        return zip(elements.prefix(hints.count), hints).map { element, hint in
            HintedElement(element: element, hint: hint)
        }
    }

    /// Preserve every still-visible token while a cold browser renderer adds
    /// page controls to an already-visible native-chrome overlay. Without this,
    /// crossing the two-to-three-character capacity boundary would remap every
    /// hint while the user may already be typing.
    static func assignPreservingHints(
        to elements: [UIElement],
        previous: [HintedElement],
        alphabet: HintCharacters,
        minimumTokenLength: Int = 2
    ) -> [HintedElement] {
        let available = tokens(
            alphabet: alphabet,
            elementCount: max(elements.count, previous.count),
            minimumTokenLength: minimumTokenLength
        )
        let availableSet = Set(available)
        let currentIdentities = Set(elements.map(\.stableID))
        let preserved: [ElementIdentity: String] = Dictionary(
            uniqueKeysWithValues: previous.compactMap { hinted in
                guard currentIdentities.contains(hinted.identity),
                      availableSet.contains(hinted.hint) else { return nil }
                return (hinted.identity, hinted.hint)
            }
        )
        let used = Set(preserved.values)
        var unused = available.lazy.filter { !used.contains($0) }.makeIterator()

        return elements.prefix(available.count).compactMap { element in
            if let hint = preserved[element.stableID] {
                return HintedElement(element: element, hint: hint)
            }
            guard let hint = unused.next() else { return nil }
            return HintedElement(element: element, hint: hint)
        }
    }

    private static func tokens(
        alphabet: HintCharacters,
        elementCount: Int,
        minimumTokenLength: Int
    ) -> [String] {
        let chars = alphabet.characters
        let n = chars.count
        guard n > 0, elementCount > 0 else { return [] }

        let twoCharCombos = n * n
        let threeCharCombos = n * n * n
        let useThreeCharacters = minimumTokenLength >= 3 || elementCount > twoCharCombos
        let hintCount = min(elementCount, useThreeCharacters ? threeCharCombos : twoCharCombos)

        return (0..<hintCount).map { index in
            if useThreeCharacters {
                let first = chars[index / (n * n)]
                let second = chars[(index / n) % n]
                let third = chars[index % n]
                return "\(first)\(second)\(third)"
            }
            let first = chars[index / n]
            let second = chars[index % n]
            return "\(first)\(second)"
        }
    }
}
