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
        static let s: CGKeyCode = 1
        static let semicolon: CGKeyCode = 41
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

    func test_shiftedLetter_decodesAsLowercaseCharacterWithShiftModifier() {
        XCTAssertEqual(decode(Key.a, flags: .maskShift), .character("a", modifier: .shift))
    }

    func test_shiftMinus_decodesAsUnderscore() {
        XCTAssertEqual(decode(Key.minus, flags: .maskShift), .character("_"))
    }

    func test_shiftedPunctuation_passesThroughUnlessItIsTheHidePrefix() {
        XCTAssertEqual(decode(Key.slash, flags: .maskShift), .passThrough)

        let withPrefix = HintInputDecoder.Context(isTextSearchActive: false, numberedElementsCount: 0, hidePrefix: "?")
        XCTAssertEqual(decode(Key.slash, flags: .maskShift, context: withPrefix), .character("?"))
    }

    func test_shiftedPunctuationHidePrefix_carriesNoModifier() {
        let withPrefix = HintInputDecoder.Context(isTextSearchActive: false, numberedElementsCount: 0, hidePrefix: ":")
        XCTAssertEqual(decode(Key.semicolon, flags: .maskShift, context: withPrefix), .character(":"))
    }

    // MARK: - Click modifiers on letters

    private var alphabet: HintInputDecoder.Context {
        HintInputDecoder.Context(isTextSearchActive: false, numberedElementsCount: 0, hintAlphabet: "asdfhjkl")
    }

    func test_controlLetter_decodesWithControlModifier() {
        XCTAssertEqual(decode(Key.s, flags: .maskControl, context: alphabet), .character("s", modifier: .control))
    }

    func test_optionLetter_decodesWithOptionModifier() {
        XCTAssertEqual(decode(Key.s, flags: .maskAlternate, context: alphabet), .character("s", modifier: .option))
    }

    func test_commandHintLetter_decodesWithCommandModifier() {
        XCTAssertEqual(decode(Key.s, flags: .maskCommand, context: alphabet), .character("s", modifier: .command))
    }

    func test_commandNonHintKey_stillDismisses() {
        XCTAssertEqual(decode(Key.w, flags: .maskCommand, context: alphabet), .dismiss)
        XCTAssertEqual(decode(Key.tab, flags: .maskCommand, context: alphabet), .dismiss)
        XCTAssertEqual(decode(Key.one, flags: .maskCommand, context: alphabet), .dismiss)
        XCTAssertEqual(decode(Key.escape, flags: .maskCommand, context: alphabet), .dismiss)
        XCTAssertEqual(decode(Key.space, flags: .maskCommand, context: alphabet), .dismiss)
        XCTAssertEqual(decode(Key.delete, flags: .maskCommand, context: alphabet), .dismiss)
    }

    func test_commandWinsOverOtherModifiers() {
        XCTAssertEqual(
            decode(Key.s, flags: [.maskCommand, .maskShift, .maskControl], context: alphabet),
            .character("s", modifier: .command)
        )
    }

    func test_controlWinsOverOptionAndShift() {
        XCTAssertEqual(
            decode(Key.s, flags: [.maskControl, .maskAlternate, .maskShift], context: alphabet),
            .character("s", modifier: .control)
        )
    }

    func test_capsLock_isNotAModifier() {
        XCTAssertEqual(decode(Key.s, flags: .maskAlphaShift, context: alphabet), .character("s"))
    }

    // MARK: - Modifiers

    func test_optionPress_passesThroughSoItCanStartAHover() {
        XCTAssertEqual(decode(Key.option, flags: .maskAlternate, type: .flagsChanged), .passThrough)
    }

    func test_optionRelease_clearsSearch() {
        XCTAssertEqual(decode(Key.option, flags: [], type: .flagsChanged), .clearSearch)
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

    func test_return_carriesTheHeldModifier() {
        XCTAssertEqual(decode(Key.returnKey), .enter(.none))
        XCTAssertEqual(decode(Key.returnKey, flags: .maskControl), .enter(.control))
        XCTAssertEqual(decode(Key.returnKey, flags: .maskShift), .enter(.shift))
        XCTAssertEqual(decode(Key.returnKey, flags: .maskCommand), .enter(.command))
        XCTAssertEqual(decode(Key.returnKey, flags: .maskAlternate), .enter(.option))
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

    func test_digitWithModifier_duringTextSearch_carriesTheModifier() {
        let searching = HintInputDecoder.Context(isTextSearchActive: true, numberedElementsCount: 3)
        XCTAssertEqual(decode(Key.one, flags: .maskControl, context: searching), .selectNumbered(1, modifier: .control))
        XCTAssertEqual(decode(Key.one, flags: .maskShift, context: searching), .selectNumbered(1, modifier: .shift))
        XCTAssertEqual(decode(Key.one, flags: .maskCommand, context: searching), .selectNumbered(1, modifier: .command))
        XCTAssertEqual(decode(Key.one, flags: .maskAlternate, context: searching), .selectNumbered(1, modifier: .option))
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
