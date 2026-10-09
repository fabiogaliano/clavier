//
//  HintInputDecoder.swift
//  clavier
//
//  Command-decode adapter for hint mode input.
//
//  Translates raw CGEvent key presses into typed `HintInputCommand` values.
//  This is the "command decode entry for mode-specific adapters" seam defined
//  in P2-S1.  The decoder is stateless: the caller (HintModeController)
//  supplies the CF-thread-readable state it needs (isTextSearchActive,
//  numberedElementsCount) via a `Context` value captured at decode time.
//
//  The split from HintModeController's inline callback keeps the event-tap
//  lambda thin: it calls `decode(type:event:context:)` and dispatches the
//  result to main.  All input logic (processInput, handleEscapeKey, etc.)
//  stays in the controller for now — full reducer extraction is P4-S2.
//
//  Key-code → character mapping is shared with `ScrollInputDecoder` via
//  `KeymapUtilities.asciiCharacter(forKeyCode:)`.  That table is the canonical
//  input-recognition map; `KeymapUtilities.keyCodeToString` remains separate
//  because it is upper-case and includes display-only glyphs (Space, ⎋, etc.).
//

import AppKit

// MARK: - Command

/// Typed representation of a decoded hint-mode keyboard command.
///
/// The event tap callback decodes a raw `CGEvent` into one of these cases and
/// dispatches it to the main thread, where `HintModeController` acts on it.
enum HintInputCommand: Equatable {
    case escape
    case backspace
    case enter(ClickModifier)
    case clearSearch
    case selectNumbered(Int, modifier: ClickModifier = .none)
    case character(String, modifier: ClickModifier = .none)
    /// Space pressed in hint mode — semantics resolved by the reducer
    /// (rotate overlap when filter is empty, otherwise treat as a space
    /// character for text search).
    case spaceKey
    case passThrough
    /// The user is leaving the session (a Cmd shortcut, an app switch, a
    /// mouse click).  The tap still passes the triggering key through.
    case dismiss
    /// Not produced by the decoder: the controller sends it when element text
    /// arrives after the user already typed, so the filter is matched again.
    case reapplyFilter
}

// MARK: - Decoder

/// Stateless decoder that maps raw CGEvents to `HintInputCommand` values.
enum HintInputDecoder {

    /// Caller-supplied context read on the CF run loop thread.
    ///
    /// The controller publishes one of these behind a lock whenever its
    /// session changes; the tap callback copies it once per event.
    struct Context: Equatable, Sendable {
        let isTextSearchActive: Bool
        let numberedElementsCount: Int
        /// Single non-alphanumeric marker the user has configured to hide
        /// labels during search. Empty when the feature is disabled.
        /// Passed through so the decoder can accept the character (shift +
        /// punctuation keys fall outside the default letter/digit whitelist).
        let hidePrefix: String
        /// The session's own toggle hotkey, exempt from the ⌘-dismiss rule.
        let hotkey: HotkeyChord?

        init(
            isTextSearchActive: Bool,
            numberedElementsCount: Int,
            hidePrefix: String = "",
            hotkey: HotkeyChord? = nil
        ) {
            self.isTextSearchActive = isTextSearchActive
            self.numberedElementsCount = numberedElementsCount
            self.hidePrefix = hidePrefix
            self.hotkey = hotkey
        }

        /// Tap-side view of `session`; `nil` when there is no live session.
        ///
        /// Numbered selection is only exposed for 1–9 matches: more than nine
        /// render as highlight boxes without numbers, so digits must keep
        /// typing into the filter.
        init?(session: HintSession, hidePrefix: String, hotkey: HotkeyChord? = nil) {
            guard session.isActive else { return nil }
            let numberedCount = session.numberedElements.count
            let inNumberedMode = numberedCount > 0 && numberedCount <= 9
            self.init(
                isTextSearchActive: inNumberedMode,
                numberedElementsCount: inNumberedMode ? numberedCount : 0,
                hidePrefix: hidePrefix,
                hotkey: hotkey
            )
        }
    }

    /// Decode a key event captured by the CGEvent tap.
    ///
    /// Returns `.passThrough` for events the hint mode should not consume
    /// (unrecognized key codes, modifier-only events that aren't clear-search).
    static func decode(type: CGEventType, event: CGEvent, context: Context) -> HintInputCommand {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Clear search fires on Option *release*: pressing ⌥ is also the
        // start of a ⌥+letter hover, and clearing on press would wipe the
        // first hint letter before the completing one arrives.
        if type == .flagsChanged && (keyCode == 58 || keyCode == 61) {
            if flags.contains(.maskAlternate) {
                return .passThrough
            }
            return .clearSearch
        }

        guard type == .keyDown else { return .passThrough }

        // The toggle hotkey belongs to the Carbon handler, which upgrades the
        // session to continuous; it must not be mistaken for a ⌘ shortcut.
        if context.hotkey?.matches(keyCode: keyCode, flags: flags) == true {
            return .passThrough
        }

        // ⌘+anything is a system or app shortcut (⌘Tab, ⌘W, ⌘S, …), never
        // hint input; decoding it would eat the shortcut.
        if flags.contains(.maskCommand) { return .dismiss }

        let modifier = ClickModifier(flags: flags)

        switch keyCode {
        case 53: return .escape
        case 36: return .enter(modifier)
        case 51: return .backspace
        case 49: return .spaceKey
        default: break
        }

        // Number keys during text search
        if context.isTextSearchActive {
            let numberKeyMap: [Int64: Int] = [
                18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9
            ]
            if let number = numberKeyMap[keyCode], number <= context.numberedElementsCount {
                return .selectNumbered(number, modifier: modifier)
            }
        }

        // Character keys. Base table holds plain unmodified keys; the
        // shifted-punctuation table supplies shift-produced symbols (including
        // keys absent from the base table like `/` and `\`).  A shifted
        // symbol is a different character, not a ⇧-modified one, so it
        // carries no modifier.
        let character: String
        var characterModifier = modifier
        if modifier == .shift, let shifted = shiftedPunctuation[keyCode] {
            character = shifted
            characterModifier = .none
        } else if keyCode == 27 && modifier == .shift {
            character = "_"
            characterModifier = .none
        } else if let base = KeymapUtilities.asciiCharacter(forKeyCode: keyCode) {
            character = base
        } else {
            return .passThrough
        }

        let lower = character.lowercased()
        guard lower.count == 1, let ch = lower.first else {
            return .passThrough
        }

        let isBaseAllowed = ch.isLetter || ch.isNumber || "-._".contains(ch)
        let isConfiguredPrefix = !context.hidePrefix.isEmpty && lower == context.hidePrefix
        guard isBaseAllowed || isConfiguredPrefix else {
            return .passThrough
        }

        return .character(lower, modifier: characterModifier)
    }

    /// Shift-modified punctuation characters produced by common US-QWERTY
    /// keys.  Only entries that could plausibly serve as a hide-prefix
    /// marker are listed; extend as needed when the default shortlist grows.
    private static let shiftedPunctuation: [Int64: String] = [
        24: "+",   // shift + =
        41: ":",   // shift + ;
        43: "<",   // shift + ,
        47: ">",   // shift + .
        44: "?",   // shift + /
        42: "|",   // shift + \
    ]

}
