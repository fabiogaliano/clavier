//
//  HintInputDecoderTests.swift
//  clavierTests
//
//  Raw key event → `HintInputCommand`, with a focus on modifier handling:
//  what hint mode consumes, what it passes through, and what ends it.
//

import XCTest
import CoreGraphics
import Carbon.HIToolbox
@testable import clavier

final class HintInputDecoderTests: XCTestCase {

    private enum Key {
        static let a: CGKeyCode = 0
        static let w: CGKeyCode = 13
        static let one: CGKeyCode = 18
        static let four: CGKeyCode = 21
        static let minus: CGKeyCode = 27
        static let returnKey: CGKeyCode = 36
        static let slash: CGKeyCode = 44
        static let tab: CGKeyCode = 48
        static let space: CGKeyCode = 49
        static let delete: CGKeyCode = 51
        static let escape: CGKeyCode = 53
        static let command: CGKeyCode = 55
        static let option: CGKeyCode = 58
    }

    private let plain = HintInputDecoder.Context(isTextSearchActive: false, numberedElementsCount: 0)

    private func decode(
        _ keyCode: CGKeyCode,
        flags: CGEventFlags = [],
        type: CGEventType = .keyDown,
        context: HintInputDecoder.Context? = nil
    ) -> HintInputCommand {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)!
        event.flags = flags
        return HintInputDecoder.decode(type: type, event: event, context: context ?? plain)
    }

    // MARK: - Characters

    func test_plainLetter_decodesAsLowercaseCharacter() {
        XCTAssertEqual(decode(Key.a), .character("a"))
    }

    func test_shiftedLetter_decodesAsLowercaseCharacter() {
        XCTAssertEqual(decode(Key.a, flags: .maskShift), .character("a"))
    }

    func test_shiftMinus_decodesAsUnderscore() {
        XCTAssertEqual(decode(Key.minus, flags: .maskShift), .character("_"))
    }

    func test_shiftedPunctuation_passesThroughUnlessItIsTheHidePrefix() {
        XCTAssertEqual(decode(Key.slash, flags: .maskShift), .passThrough)

        let withPrefix = HintInputDecoder.Context(isTextSearchActive: false, numberedElementsCount: 0, hidePrefix: "?")
        XCTAssertEqual(decode(Key.slash, flags: .maskShift, context: withPrefix), .character("?"))
    }

    // MARK: - Modifiers

    func test_optionPress_clearsSearch() {
        XCTAssertEqual(decode(Key.option, flags: .maskAlternate, type: .flagsChanged), .clearSearch)
    }

    func test_optionRelease_passesThrough() {
        XCTAssertEqual(decode(Key.option, flags: [], type: .flagsChanged), .passThrough)
    }

    func test_cmdLetter_dismissesInsteadOfTypingTheLetter() {
        XCTAssertEqual(decode(Key.w, flags: .maskCommand), .dismiss)
    }

    func test_cmdTab_dismisses() {
        XCTAssertEqual(decode(Key.tab, flags: .maskCommand), .dismiss)
    }

    func test_cmdWithOtherModifiers_dismisses() {
        XCTAssertEqual(decode(Key.a, flags: [.maskCommand, .maskShift]), .dismiss)
    }

    func test_cmdHeldAlone_doesNotDismiss() {
        XCTAssertEqual(decode(Key.command, flags: .maskCommand, type: .flagsChanged), .passThrough)
    }

    // MARK: - Special keys

    func test_tab_passesThrough() {
        XCTAssertEqual(decode(Key.tab), .passThrough)
    }

    func test_escape() {
        XCTAssertEqual(decode(Key.escape), .escape)
    }

    func test_return_withAndWithoutControl() {
        XCTAssertEqual(decode(Key.returnKey), .enter(withControl: false))
        XCTAssertEqual(decode(Key.returnKey, flags: .maskControl), .enter(withControl: true))
    }

    func test_delete() {
        XCTAssertEqual(decode(Key.delete), .backspace)
    }

    func test_space() {
        XCTAssertEqual(decode(Key.space), .spaceKey)
    }

    // MARK: - Digits

    func test_digit_withoutTextSearch_isACharacter() {
        XCTAssertEqual(decode(Key.one), .character("1"))
    }

    func test_digit_duringTextSearch_selectsNumberedMatch() {
        let searching = HintInputDecoder.Context(isTextSearchActive: true, numberedElementsCount: 3)
        XCTAssertEqual(decode(Key.one, context: searching), .selectNumbered(1))
    }

    func test_digit_beyondMatchCount_staysACharacter() {
        let searching = HintInputDecoder.Context(isTextSearchActive: true, numberedElementsCount: 3)
        XCTAssertEqual(decode(Key.four, context: searching), .character("4"))
    }

    // MARK: - Context snapshot

    func test_contextSnapshot_isNilForInactiveSession() {
        XCTAssertNil(HintInputDecoder.Context(session: .inactive, hidePrefix: ""))
    }

    // MARK: - Hotkey exemption

    func test_cmdHotkey_passesThroughInsteadOfDismissing() {
        let chord = HotkeyChord(keyCode: Int64(Key.space), carbonModifiers: cmdKey | shiftKey)
        let context = HintInputDecoder.Context(isTextSearchActive: false, numberedElementsCount: 0, hotkey: chord)
        XCTAssertEqual(decode(Key.space, flags: [.maskCommand, .maskShift], context: context), .passThrough)
        XCTAssertEqual(decode(Key.space, flags: [.maskCommand], context: context), .dismiss)
        XCTAssertEqual(decode(Key.space, flags: [.maskCommand, .maskShift, .maskAlphaShift], context: context), .passThrough)
    }

    func test_hotkeyWithoutCmd_isDecodedNormally() {
        // F17 isn't in the ASCII table, so it passes through regardless of the chord.
        let chord = HotkeyChord(keyCode: 64, carbonModifiers: 0)
        let context = HintInputDecoder.Context(isTextSearchActive: false, numberedElementsCount: 0, hotkey: chord)
        XCTAssertEqual(decode(64, context: context), .passThrough)
    }
}
