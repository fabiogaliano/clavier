import Foundation
import Carbon

enum AppSettings {
    enum Keys {
        // Hint Mode
        static let hintShortcutKeyCode = "hintShortcutKeyCode"
        static let hintShortcutModifiers = "hintShortcutModifiers"
        static let hintDebugShortcutKeyCode = "hintDebugShortcutKeyCode"
        static let hintDebugShortcutModifiers = "hintDebugShortcutModifiers"
        static let hintSize = "hintSize"
        static let continuousClickMode = "continuousClickMode"
        static let autoHintDeactivation = "autoHintDeactivation"
        static let hintDeactivationDelay = "hintDeactivationDelay"
        static let hintCharacters = "hintCharacters"
        static let textSearchEnabled = "textSearchEnabled"
        static let minSearchCharacters = "minSearchCharacters"
        static let manualRefreshTrigger = "manualRefreshTrigger"

        // Appearance
        static let hintBackgroundHex = "hintBackgroundHex"
        static let hintBorderHex = "hintBorderHex"
        static let hintTextHex = "hintTextHex"
        static let highlightTextHex = "highlightTextHex"
        static let hintBackgroundOpacity = "hintBackgroundOpacity"
        static let hintBorderOpacity = "hintBorderOpacity"
        static let hintHorizontalOffset = "hintHorizontalOffset"

        // Scroll Mode
        static let scrollShortcutKeyCode = "scrollShortcutKeyCode"
        static let scrollShortcutModifiers = "scrollShortcutModifiers"
        static let scrollArrowMode = "scrollArrowMode"
        static let showScrollAreaNumbers = "showScrollAreaNumbers"
        static let scrollKeys = "scrollKeys"
        static let scrollSpeed = "scrollSpeed"
        static let dashSpeed = "dashSpeed"
        static let autoScrollDeactivation = "autoScrollDeactivation"
        static let scrollDeactivationDelay = "scrollDeactivationDelay"
    }

    enum Defaults {
        static let hintShortcutKeyCode = 49
        static let hintShortcutModifiers = cmdKey | shiftKey
        static let hintDebugShortcutKeyCode = 49
        static let hintDebugShortcutModifiers = cmdKey | shiftKey | optionKey
        static let hintSize = 12.0
        static let continuousClickMode = false
        static let autoHintDeactivation = true
        static let hintDeactivationDelay = 5.0
        static let hintCharacters = "asdfhjkl"
        static let textSearchEnabled = true
        static let minSearchCharacters = 2
        static let manualRefreshTrigger = "rr"
        static let hintBackgroundHex = "#3B82F6"
        static let hintBorderHex = "#3B82F6"
        static let hintTextHex = "#FFFFFF"
        static let highlightTextHex = "#FFFF00"
        static let hintBackgroundOpacity = 0.3
        static let hintBorderOpacity = 0.6
        static let hintHorizontalOffset = -25.0
        static let scrollShortcutKeyCode = 14
        static let scrollShortcutModifiers = optionKey
        static let scrollArrowMode = ScrollArrowMode.select
        static let showScrollAreaNumbers = true
        static let scrollKeys = "hjkl"
        static let scrollSpeed = 5.0
        static let dashSpeed = 9.0
        static let autoScrollDeactivation = true
        static let scrollDeactivationDelay = 5.0

        // Validation ranges — owned here so reducers & views agree on limits.
        static let minSearchCharactersRange: ClosedRange<Int> = 1...5
        static let minHintCharactersCount = 2
        static let scrollKeysRequiredCount = 4
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Keys.hintShortcutKeyCode: Defaults.hintShortcutKeyCode,
            Keys.hintShortcutModifiers: Defaults.hintShortcutModifiers,
            Keys.hintDebugShortcutKeyCode: Defaults.hintDebugShortcutKeyCode,
            Keys.hintDebugShortcutModifiers: Defaults.hintDebugShortcutModifiers,
            Keys.hintSize: Defaults.hintSize,
            Keys.continuousClickMode: Defaults.continuousClickMode,
            Keys.autoHintDeactivation: Defaults.autoHintDeactivation,
            Keys.hintDeactivationDelay: Defaults.hintDeactivationDelay,
            Keys.hintCharacters: Defaults.hintCharacters,
            Keys.textSearchEnabled: Defaults.textSearchEnabled,
            Keys.minSearchCharacters: Defaults.minSearchCharacters,
            Keys.manualRefreshTrigger: Defaults.manualRefreshTrigger,
            Keys.hintBackgroundHex: Defaults.hintBackgroundHex,
            Keys.hintBorderHex: Defaults.hintBorderHex,
            Keys.hintTextHex: Defaults.hintTextHex,
            Keys.highlightTextHex: Defaults.highlightTextHex,
            Keys.hintBackgroundOpacity: Defaults.hintBackgroundOpacity,
            Keys.hintBorderOpacity: Defaults.hintBorderOpacity,
            Keys.hintHorizontalOffset: Defaults.hintHorizontalOffset,
            Keys.scrollShortcutKeyCode: Defaults.scrollShortcutKeyCode,
            Keys.scrollShortcutModifiers: Defaults.scrollShortcutModifiers,
            Keys.scrollArrowMode: Defaults.scrollArrowMode.rawValue,
            Keys.showScrollAreaNumbers: Defaults.showScrollAreaNumbers,
            Keys.scrollKeys: Defaults.scrollKeys,
            Keys.scrollSpeed: Defaults.scrollSpeed,
            Keys.dashSpeed: Defaults.dashSpeed,
            Keys.autoScrollDeactivation: Defaults.autoScrollDeactivation,
            Keys.scrollDeactivationDelay: Defaults.scrollDeactivationDelay,
        ])
    }
}

// MARK: - Typed domain representations

/// Arrow-key behaviour while scroll mode is active.
///
/// Persisted as a `String` (same raw value as before: `"select"` / `"scroll"`)
/// so `@AppStorage` reads/writes stay shape-compatible with the v1 defaults.
enum ScrollArrowMode: String, CaseIterable {
    case select
    case scroll
}

/// Four-letter scroll keymap (left, down, up, right).
///
/// Always constructed through `ScrollKeymap.parse(_:)` so every consumer sees
/// a value that has already passed validation.  The legacy `String` wire
/// format ("hjkl") is preserved round-trip via `rawString`.
struct ScrollKeymap: Equatable {
    let left: Character
    let down: Character
    let up: Character
    let right: Character

    var rawString: String { String([left, down, up, right]) }

    static let `default` = ScrollKeymap.parse(AppSettings.Defaults.scrollKeys)!

    /// Parse a user-entered string into a valid keymap.
    ///
    /// Requires exactly four distinct letters; returns nil otherwise.  The
    /// caller (usually `AppSettings`) falls back to `.default` on nil.
    static func parse(_ raw: String) -> ScrollKeymap? {
        let lowered = raw.lowercased()
        guard lowered.count == AppSettings.Defaults.scrollKeysRequiredCount,
              lowered.allSatisfy({ $0.isLetter }) else { return nil }
        let chars = Array(lowered)
        guard Set(chars).count == chars.count else { return nil }
        return ScrollKeymap(left: chars[0], down: chars[1], up: chars[2], right: chars[3])
    }
}

/// Hint alphabet used for two- and three-character hint assignment.
///
/// Persisted as a lowercase string of unique letters; must contain at least
/// `Defaults.minHintCharactersCount` characters to produce meaningful hints.
struct HintCharacters: Equatable {
    let characters: [Character]

    var rawString: String { String(characters) }
    var count: Int { characters.count }

    static let `default` = HintCharacters(characters: Array(AppSettings.Defaults.hintCharacters))

    /// Parse + sanitise a stored or user-entered string.
    ///
    /// Filters to unique lowercase letters; returns nil if fewer than
    /// `Defaults.minHintCharactersCount` survive.
    static func parse(_ raw: String) -> HintCharacters? {
        let sanitised = AppSettings.sanitizeHintCharacters(raw)
        guard sanitised.count >= AppSettings.Defaults.minHintCharactersCount else { return nil }
        return HintCharacters(characters: Array(sanitised))
    }
}

// MARK: - Parse-on-read accessors

/// Typed reads that centralise validation.  Reducers and controllers should
/// read through these properties rather than touching `UserDefaults` directly,
/// so every domain caller receives an already-validated value.
extension AppSettings {
    static var hintCharacters: HintCharacters {
        let raw = UserDefaults.standard.string(forKey: Keys.hintCharacters) ?? Defaults.hintCharacters
        return HintCharacters.parse(raw) ?? .default
    }

    static var minSearchCharacters: Int {
        let v = UserDefaults.standard.integer(forKey: Keys.minSearchCharacters)
        return Defaults.minSearchCharactersRange.contains(v) ? v : Defaults.minSearchCharacters
    }

    static var manualRefreshTrigger: String {
        let v = UserDefaults.standard.string(forKey: Keys.manualRefreshTrigger) ?? Defaults.manualRefreshTrigger
        return v.isEmpty ? Defaults.manualRefreshTrigger : v
    }

    static var scrollKeys: ScrollKeymap {
        let raw = UserDefaults.standard.string(forKey: Keys.scrollKeys) ?? Defaults.scrollKeys
        return ScrollKeymap.parse(raw) ?? .default
    }

    static var scrollArrowMode: ScrollArrowMode {
        let raw = UserDefaults.standard.string(forKey: Keys.scrollArrowMode) ?? Defaults.scrollArrowMode.rawValue
        return ScrollArrowMode(rawValue: raw) ?? Defaults.scrollArrowMode
    }
}

// MARK: - View-layer sanitisers
//
// `@AppStorage` has no `didSet`, so `TextField` edits must be sanitised as
// the user types.  The *rules* live here so views don't own domain logic;
// views just call the helper from their `onChange` closure.

extension AppSettings {
    /// Lower-case, keep unique letters only.  Used by the hint-alphabet field.
    static func sanitizeHintCharacters(_ raw: String) -> String {
        var seen = Set<Character>()
        return String(raw.lowercased().filter { $0.isLetter && seen.insert($0).inserted })
    }

    /// Lower-case, keep up to four unique letters.  Used by the scroll-keys field.
    static func sanitizeScrollKeys(_ raw: String) -> String {
        var seen = Set<Character>()
        return String(
            raw.lowercased()
                .filter { $0.isLetter && seen.insert($0).inserted }
                .prefix(Defaults.scrollKeysRequiredCount)
        )
    }

    /// Guarantee a non-empty refresh trigger; fall back to the default string.
    static func sanitizeManualRefreshTrigger(_ raw: String) -> String {
        raw.isEmpty ? Defaults.manualRefreshTrigger : raw
    }
}
