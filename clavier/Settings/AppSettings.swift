import Foundation
import Carbon

enum AppSettings {
    enum Keys {
        // Hint Mode
        static let hintShortcutKeyCode = "hintShortcutKeyCode"
        static let hintShortcutModifiers = "hintShortcutModifiers"
        static let hintSize = "hintSize"
        static let hintColor = "hintColor" // legacy; removed in P5-S1
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
        static let hintSize = 12.0
        static let hintColor = "blue"
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
        static let scrollArrowMode = "select"
        static let showScrollAreaNumbers = true
        static let scrollKeys = "hjkl"
        static let scrollSpeed = 5.0
        static let dashSpeed = 9.0
        static let autoScrollDeactivation = true
        static let scrollDeactivationDelay = 5.0
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Keys.hintShortcutKeyCode: Defaults.hintShortcutKeyCode,
            Keys.hintShortcutModifiers: Defaults.hintShortcutModifiers,
            Keys.hintSize: Defaults.hintSize,
            Keys.hintColor: Defaults.hintColor,
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
            Keys.scrollArrowMode: Defaults.scrollArrowMode,
            Keys.showScrollAreaNumbers: Defaults.showScrollAreaNumbers,
            Keys.scrollKeys: Defaults.scrollKeys,
            Keys.scrollSpeed: Defaults.scrollSpeed,
            Keys.dashSpeed: Defaults.dashSpeed,
            Keys.autoScrollDeactivation: Defaults.autoScrollDeactivation,
            Keys.scrollDeactivationDelay: Defaults.scrollDeactivationDelay,
        ])
    }
}

// Typed reads with inline validation to guard against invalid stored values.
extension AppSettings {
    static var hintCharacters: String {
        let v = UserDefaults.standard.string(forKey: Keys.hintCharacters) ?? Defaults.hintCharacters
        return v.isEmpty ? Defaults.hintCharacters : v
    }

    static var minSearchCharacters: Int {
        let v = UserDefaults.standard.integer(forKey: Keys.minSearchCharacters)
        return (1...5).contains(v) ? v : Defaults.minSearchCharacters
    }

    static var manualRefreshTrigger: String {
        let v = UserDefaults.standard.string(forKey: Keys.manualRefreshTrigger) ?? Defaults.manualRefreshTrigger
        return v.isEmpty ? Defaults.manualRefreshTrigger : v
    }

    static var scrollKeys: String {
        let v = UserDefaults.standard.string(forKey: Keys.scrollKeys) ?? Defaults.scrollKeys
        return v.count == 4 ? v : Defaults.scrollKeys
    }

    static var scrollArrowMode: String {
        UserDefaults.standard.string(forKey: Keys.scrollArrowMode) ?? Defaults.scrollArrowMode
    }
}
