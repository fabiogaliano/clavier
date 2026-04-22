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
        alphabet: HintCharacters
    ) -> [HintedElement] {
        let chars = alphabet.characters
        let n = chars.count
        guard n > 0, !elements.isEmpty else { return [] }

        let twoCharCombos = n * n
        let threeCharCombos = n * n * n
        let hintCount = min(elements.count, threeCharCombos)

        var hints: [String] = []
        hints.reserveCapacity(hintCount)

        if elements.count <= twoCharCombos {
            for i in 0..<hintCount {
                let first = chars[i / n]
                let second = chars[i % n]
                hints.append("\(first)\(second)")
            }
        } else {
            for i in 0..<hintCount {
                let first = chars[i / (n * n)]
                let second = chars[(i / n) % n]
                let third = chars[i % n]
                hints.append("\(first)\(second)\(third)")
            }
        }

        return zip(elements.prefix(hintCount), hints).map { element, hint in
            HintedElement(element: element, hint: hint)
        }
    }
}
