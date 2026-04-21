//
//  ScrollInputDecoder.swift
//  clavier
//
//  Command-decode adapter for scroll mode input.
//
//  Translates raw CGEvent key presses into typed `ScrollInputCommand` values.
//  This is the scroll-mode counterpart to `HintInputDecoder` — the same
//  "command decode entry for mode-specific adapters" seam defined in P2-S1.
//
//  The decoder is stateless: the caller (ScrollModeController) supplies the
//  CF-thread-readable context it needs via a `Context` value captured at
//  decode time.  Numeric-input accumulation and arrow-mode routing remain in
//  the controller for now — full reducer extraction is P4-S3.
//
//  Key mapping for scroll directions uses the same lower-case character table
//  as `HintInputDecoder.keyCodeToCharacter`; the table is replicated here
//  rather than shared because the two decoders have distinct inputs and the
//  table is stable enough that a shared copy adds coupling without benefit.
//

import AppKit

// MARK: - Command

/// Typed representation of a decoded scroll-mode keyboard command.
///
/// The event tap callback decodes a raw `CGEvent` into one of these cases
/// and dispatches it to the main thread, where `ScrollModeController` acts on it.
enum ScrollInputCommand {
    case escape
    case backspace
    case digit(Int)
    case arrowKey(ScrollDirection, isShift: Bool)
    case scrollKey(ScrollDirection, isShift: Bool)
    case consume
}

// MARK: - Decoder

/// Stateless decoder that maps raw CGEvents to `ScrollInputCommand` values.
enum ScrollInputDecoder {

    /// Caller-supplied context read on the CF run loop thread.
    ///
    /// Both fields must come from `nonisolated(unsafe)` statics so the
    /// callback can access them without crossing actor boundaries.
    struct Context {
        /// The four-character scroll-key string (e.g. "hjkl").
        let scrollKeys: String
    }

    /// Decode a key-down event captured by the CGEvent tap.
    ///
    /// Returns `.consume` for keys that scroll mode should swallow but not act
    /// on (unrecognized keys, modifier-only events).  The tap callback returns
    /// `nil` for all `.consume` and action commands — scroll mode does not pass
    /// any key through to the application while active.
    static func decode(type: CGEventType, event: CGEvent, context: Context) -> ScrollInputCommand {
        guard type == .keyDown else { return .consume }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let isShift = flags.contains(.maskShift)

        switch keyCode {
        case 53: return .escape
        case 51: return .backspace
        default: break
        }

        if let digit = numberKeyMap[keyCode] {
            return .digit(digit)
        }

        if let direction = arrowKeyMap[keyCode] {
            return .arrowKey(direction, isShift: isShift)
        }

        if let direction = scrollDirection(for: keyCode, scrollKeys: context.scrollKeys) {
            return .scrollKey(direction, isShift: isShift)
        }

        return .consume
    }

    // MARK: - Key maps

    private static let numberKeyMap: [Int64: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5,
        22: 6, 26: 7, 28: 8, 25: 9, 29: 0,
    ]

    private static let arrowKeyMap: [Int64: ScrollDirection] = [
        126: .up,
        125: .down,
        123: .left,
        124: .right,
    ]

    private static func scrollDirection(
        for keyCode: Int64,
        scrollKeys: String
    ) -> ScrollDirection? {
        guard scrollKeys.count == 4,
              let character = keyCodeToCharacter(keyCode) else { return nil }

        let chars = Array(scrollKeys.lowercased())
        let leftKey  = String(chars[0])
        let downKey  = String(chars[1])
        let upKey    = String(chars[2])
        let rightKey = String(chars[3])

        switch character {
        case leftKey:  return .left
        case downKey:  return .down
        case upKey:    return .up
        case rightKey: return .right
        default:       return nil
        }
    }

    /// Maps hardware key codes to their lower-case primary character.
    ///
    /// Covers the letter keys used by default hjkl bindings and any custom
    /// four-character `scrollKeys` string.  Number-row and punctuation keys
    /// are intentionally omitted — they are handled by `numberKeyMap` above
    /// and are not valid scroll-key characters.
    private static func keyCodeToCharacter(_ keyCode: Int64) -> String? {
        let keyMap: [Int64: String] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
            8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
            16: "y", 17: "t", 31: "o", 32: "u", 34: "i", 35: "p", 37: "l",
            38: "j", 40: "k", 45: "n", 46: "m",
        ]
        return keyMap[keyCode]
    }
}
