//
//  ScrollInputDecoderTests.swift
//  clavierTests
//

import XCTest
import CoreGraphics
import Carbon.HIToolbox
@testable import clavier

final class ScrollInputDecoderTests: XCTestCase {

    private let context = ScrollInputDecoder.Context(scrollKeys: "hjkl")

    private func decode(_ keyCode: CGKeyCode, flags: CGEventFlags = []) -> ScrollInputCommand {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)!
        event.flags = flags
        return ScrollInputDecoder.decode(type: .keyDown, event: event, context: context)
    }

    func test_scrollKey_scrolls() {
        XCTAssertEqual(decode(38), .scrollKey(.down, isShift: false)) // j
    }

    func test_cmdKey_dismissesInsteadOfScrolling() {
        XCTAssertEqual(decode(38, flags: .maskCommand), .dismiss) // Cmd+J
        XCTAssertEqual(decode(48, flags: .maskCommand), .dismiss) // Cmd+Tab
    }

    func test_cmdHotkey_isNotDismissed() {
        let chord = HotkeyChord(keyCode: 49, carbonModifiers: cmdKey | shiftKey) // ⌘⇧Space
        let context = ScrollInputDecoder.Context(scrollKeys: "hjkl", hotkey: chord)
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true)!
        event.flags = [.maskCommand, .maskShift]
        XCTAssertEqual(ScrollInputDecoder.decode(type: .keyDown, event: event, context: context), .consume)
        // Same key with a different modifier set is still a foreign ⌘ chord.
        event.flags = [.maskCommand]
        XCTAssertEqual(ScrollInputDecoder.decode(type: .keyDown, event: event, context: context), .dismiss)
    }
}
