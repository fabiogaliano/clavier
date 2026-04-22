//
//  KeymapUtilitiesTests.swift
//  clavierTests
//
//  Guards the single-source-of-truth keycode → ASCII table used by
//  `HintInputDecoder` and `ScrollInputDecoder`.  A regression here would
//  silently mis-route keystrokes in either mode.
//

import XCTest
@testable import clavier

final class KeymapUtilitiesTests: XCTestCase {

    func test_asciiCharacter_letterKeyCodes_returnLowerCaseLetters() {
        XCTAssertEqual(KeymapUtilities.asciiCharacter(forKeyCode: 0), "a")
        XCTAssertEqual(KeymapUtilities.asciiCharacter(forKeyCode: 4), "h")
        XCTAssertEqual(KeymapUtilities.asciiCharacter(forKeyCode: 38), "j")
        XCTAssertEqual(KeymapUtilities.asciiCharacter(forKeyCode: 40), "k")
        XCTAssertEqual(KeymapUtilities.asciiCharacter(forKeyCode: 37), "l")
    }

    func test_asciiCharacter_numberRowKeyCodes_returnDigits() {
        XCTAssertEqual(KeymapUtilities.asciiCharacter(forKeyCode: 18), "1")
        XCTAssertEqual(KeymapUtilities.asciiCharacter(forKeyCode: 29), "0")
    }

    func test_asciiCharacter_punctuationKeyCodes_returnSymbols() {
        XCTAssertEqual(KeymapUtilities.asciiCharacter(forKeyCode: 27), "-")
        XCTAssertEqual(KeymapUtilities.asciiCharacter(forKeyCode: 47), ".")
        XCTAssertEqual(KeymapUtilities.asciiCharacter(forKeyCode: 41), ";")
    }

    func test_asciiCharacter_unknownKeyCodes_returnNil() {
        XCTAssertNil(KeymapUtilities.asciiCharacter(forKeyCode: 49)) // Space is display-only
        XCTAssertNil(KeymapUtilities.asciiCharacter(forKeyCode: 36)) // Return
        XCTAssertNil(KeymapUtilities.asciiCharacter(forKeyCode: 53)) // Escape
        XCTAssertNil(KeymapUtilities.asciiCharacter(forKeyCode: 999))
    }
}
