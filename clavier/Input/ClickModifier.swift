//
//  ClickModifier.swift
//  clavier
//
//  The modifier held on the keystroke that selects an element.  It only
//  matters on the keystroke that completes a selection (last hint letter,
//  Enter in text search, a numbered match); earlier keystrokes ignore it.
//

import CoreGraphics

enum ClickModifier: Equatable, Sendable {
    case none
    case control
    case shift
    case option

    /// ⌃ wins over ⌥, ⌥ over ⇧, so a chord with several modifiers resolves
    /// to exactly one verb instead of being rejected.  ⌘ is deliberately not
    /// a verb: ⌘+key is always an app shortcut and leaves the session.
    init(flags: CGEventFlags) {
        if flags.contains(.maskControl) {
            self = .control
        } else if flags.contains(.maskAlternate) {
            self = .option
        } else if flags.contains(.maskShift) {
            self = .shift
        } else {
            self = .none
        }
    }

    var clickKind: HintClickKind {
        switch self {
        case .none: return .primary
        case .control: return .secondary
        case .shift: return .double
        case .option: return .hover
        }
    }
}
