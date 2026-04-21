//
//  AppSettingsTypesTests.swift
//  clavierTests
//
//  Covers the typed-settings boundary added in P5-S4:
//    * ScrollArrowMode raw-value round-trip + default fallback
//    * ScrollKeymap.parse validation rules
//    * HintCharacters.parse + sanitiser behaviour
//    * manual-refresh-trigger sanitiser
//    * min-search-characters range
//
//  Tests run against UserDefaults via an isolated suite so they never
//  touch the real app preferences.
//

import XCTest
@testable import clavier

final class AppSettingsTypesTests: XCTestCase {

    // MARK: - ScrollArrowMode

    func test_scrollArrowMode_roundTripsRawValue() {
        XCTAssertEqual(ScrollArrowMode(rawValue: "select"), .select)
        XCTAssertEqual(ScrollArrowMode(rawValue: "scroll"), .scroll)
        XCTAssertEqual(ScrollArrowMode.select.rawValue, "select")
        XCTAssertEqual(ScrollArrowMode.scroll.rawValue, "scroll")
    }

    func test_scrollArrowMode_rejectsUnknownRawValue() {
        XCTAssertNil(ScrollArrowMode(rawValue: "nonsense"))
    }

    // MARK: - ScrollKeymap

    func test_scrollKeymap_parsesValidFourLetters() {
        let km = ScrollKeymap.parse("hjkl")
        XCTAssertNotNil(km)
        XCTAssertEqual(km?.left, "h")
        XCTAssertEqual(km?.down, "j")
        XCTAssertEqual(km?.up, "k")
        XCTAssertEqual(km?.right, "l")
        XCTAssertEqual(km?.rawString, "hjkl")
    }

    func test_scrollKeymap_rejectsWrongLength() {
        XCTAssertNil(ScrollKeymap.parse("hjk"))
        XCTAssertNil(ScrollKeymap.parse("hjkla"))
        XCTAssertNil(ScrollKeymap.parse(""))
    }

    func test_scrollKeymap_rejectsDuplicateLetters() {
        XCTAssertNil(ScrollKeymap.parse("hjkk"))
    }

    func test_scrollKeymap_rejectsNonLetters() {
        XCTAssertNil(ScrollKeymap.parse("hj1l"))
        XCTAssertNil(ScrollKeymap.parse("hj k"))
    }

    func test_scrollKeymap_defaultIsValid() {
        XCTAssertEqual(ScrollKeymap.default.rawString, "hjkl")
    }

    // MARK: - HintCharacters

    func test_hintCharacters_parsesAndSanitisesInput() {
        let hc = HintCharacters.parse("ASDF")
        XCTAssertEqual(hc?.rawString, "asdf")
    }

    func test_hintCharacters_filtersDuplicatesAndNonLetters() {
        let hc = HintCharacters.parse("aabbcc12!")
        XCTAssertEqual(hc?.rawString, "abc")
    }

    func test_hintCharacters_rejectsBelowMinimum() {
        XCTAssertNil(HintCharacters.parse("a"))
        XCTAssertNil(HintCharacters.parse(""))
        XCTAssertNil(HintCharacters.parse("1234"))
    }

    func test_hintCharacters_defaultMatchesDeclaredDefault() {
        XCTAssertEqual(HintCharacters.default.rawString, AppSettings.Defaults.hintCharacters)
    }

    // MARK: - Sanitisers

    func test_sanitizeHintCharacters_dropsDuplicatesAndNonLetters() {
        XCTAssertEqual(AppSettings.sanitizeHintCharacters("AABbc1!d"), "abcd")
    }

    func test_sanitizeScrollKeys_keepsAtMostFourUniqueLetters() {
        XCTAssertEqual(AppSettings.sanitizeScrollKeys("hjklmn"), "hjkl")
        XCTAssertEqual(AppSettings.sanitizeScrollKeys("hhjkL"), "hjkl")
    }

    func test_sanitizeManualRefreshTrigger_replacesEmptyWithDefault() {
        XCTAssertEqual(AppSettings.sanitizeManualRefreshTrigger(""), AppSettings.Defaults.manualRefreshTrigger)
        XCTAssertEqual(AppSettings.sanitizeManualRefreshTrigger("xx"), "xx")
    }

    // MARK: - Validation ranges

    func test_minSearchCharactersRange_spansOneToFive() {
        XCTAssertTrue(AppSettings.Defaults.minSearchCharactersRange.contains(AppSettings.Defaults.minSearchCharacters))
        XCTAssertFalse(AppSettings.Defaults.minSearchCharactersRange.contains(0))
        XCTAssertFalse(AppSettings.Defaults.minSearchCharactersRange.contains(6))
    }
}
