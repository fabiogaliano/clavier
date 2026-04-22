import AppKit
import Carbon

enum KeymapUtilities {
    static func formatShortcut(keyCode: Int, modifiers: Int) -> String {
        var result = ""
        if modifiers & controlKey != 0 { result += "⌃" }
        if modifiers & optionKey != 0 { result += "⌥" }
        if modifiers & shiftKey != 0 { result += "⇧" }
        if modifiers & cmdKey != 0 { result += "⌘" }
        result += keyCodeToString(keyCode)
        return result
    }

    static func keyCodeToString(_ keyCode: Int) -> String {
        let keyMap: [Int: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
            38: "J", 40: "K", 41: ";", 43: ",", 45: "N", 46: "M",
            49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 53: "⎋",
            123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        return keyMap[keyCode] ?? "?"
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var modifiers = 0
        if flags.contains(.control) { modifiers |= controlKey }
        if flags.contains(.option) { modifiers |= optionKey }
        if flags.contains(.shift) { modifiers |= shiftKey }
        if flags.contains(.command) { modifiers |= cmdKey }
        return modifiers
    }

    /// Lower-case ASCII character for a hardware key code on a US-QWERTY layout.
    ///
    /// Input-recognition counterpart to `keyCodeToString` (which is upper-case,
    /// `Int`-typed, and includes display-only glyphs like `Space` and `⎋`).
    /// `HintInputDecoder` and `ScrollInputDecoder` share this table.
    static func asciiCharacter(forKeyCode keyCode: Int64) -> String? {
        keyCodeToASCII[keyCode]
    }

    private static let keyCodeToASCII: [Int64: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
        8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
        16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 37: "l",
        38: "j", 40: "k", 41: ";", 43: ",", 45: "n", 46: "m", 47: ".",
        50: "`"
    ]
}
