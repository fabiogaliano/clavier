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
enum HintInputCommand {
    case escape
    case backspace
    case enter(withControl: Bool)
    case clearSearch
    case selectNumbered(Int)
    case character(String)
    case passThrough
}

// MARK: - Decoder

/// Stateless decoder that maps raw CGEvents to `HintInputCommand` values.
enum HintInputDecoder {

    /// Caller-supplied context read on the CF run loop thread.
    ///
    /// Both fields must come from `nonisolated(unsafe)` statics so the
    /// callback can access them without crossing actor boundaries.
    struct Context {
        let isTextSearchActive: Bool
        let numberedElementsCount: Int
    }

    /// Decode a key event captured by the CGEvent tap.
    ///
    /// Returns `.passThrough` for events the hint mode should not consume
    /// (unrecognized key codes, modifier-only events that aren't clear-search).
    static func decode(type: CGEventType, event: CGEvent, context: Context) -> HintInputCommand {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Option key press → clear search
        if type == .flagsChanged && (keyCode == 58 || keyCode == 61) {
            if flags.contains(.maskAlternate) {
                return .clearSearch
            }
            return .passThrough
        }

        guard type == .keyDown else { return .passThrough }

        switch keyCode {
        case 53: return .escape
        case 36: return .enter(withControl: flags.contains(.maskControl))
        case 51: return .backspace
        case 49: return .character(" ")
        default: break
        }

        // Number keys during text search
        if context.isTextSearchActive {
            let numberKeyMap: [Int64: Int] = [
                18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9
            ]
            if let number = numberKeyMap[keyCode], number <= context.numberedElementsCount {
                return .selectNumbered(number)
            }
        }

        // Character keys
        guard var character = KeymapUtilities.asciiCharacter(forKeyCode: keyCode) else {
            return .passThrough
        }

        if keyCode == 27 && flags.contains(.maskShift) {
            character = "_"
        }

        let lower = character.lowercased()
        guard lower.count == 1,
              let ch = lower.first,
              ch.isLetter || ch.isNumber || "-._".contains(ch) else {
            return .passThrough
        }

        return .character(lower)
    }

}
