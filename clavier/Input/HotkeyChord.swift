//
//  HotkeyChord.swift
//  clavier
//
//  The registered global hotkey as the event tap sees it.
//
//  The decoders treat any ⌘ chord as "the user is leaving the session", so
//  a hotkey that itself contains ⌘ (e.g. ⌘⇧Space) would end the session it
//  is meant to toggle.  Carrying the chord in the tap context lets the
//  decoders exempt it and leave the Carbon handler to do the toggling.
//

import Carbon.HIToolbox
import CoreGraphics

struct HotkeyChord: Equatable, Sendable {
    let keyCode: Int64
    let carbonModifiers: Int

    /// Reads the chord stored under the given `UserDefaults` keys.
    init(keyCodeKey: String, modifiersKey: String) {
        self.init(
            keyCode: Int64(UserDefaults.standard.integer(forKey: keyCodeKey)),
            carbonModifiers: UserDefaults.standard.integer(forKey: modifiersKey)
        )
    }

    init(keyCode: Int64, carbonModifiers: Int) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    /// True when a key-down with these flags is this hotkey.  Only the four
    /// modifiers Carbon registers are compared; caps lock, fn and the
    /// device-dependent bits are ignored, as Carbon itself ignores them.
    func matches(keyCode: Int64, flags: CGEventFlags) -> Bool {
        guard keyCode == self.keyCode else { return false }
        return HotkeyChord.carbonModifiers(from: flags) == carbonModifiers
    }

    private static func carbonModifiers(from flags: CGEventFlags) -> Int {
        var modifiers = 0
        if flags.contains(.maskCommand) { modifiers |= cmdKey }
        if flags.contains(.maskShift) { modifiers |= shiftKey }
        if flags.contains(.maskAlternate) { modifiers |= optionKey }
        if flags.contains(.maskControl) { modifiers |= controlKey }
        return modifiers
    }
}
