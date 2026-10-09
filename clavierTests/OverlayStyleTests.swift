import XCTest
import AppKit
@testable import clavier

final class OverlayStyleTests: XCTestCase {

    private typealias K = AppSettings.Keys
    private typealias D = AppSettings.Defaults

    private func hint(_ stored: [String: Any]) -> OverlayStyle {
        OverlayStyle.parseHint({ stored[$0] }, accentColor: .systemPink)
    }

    private func scroll(_ stored: [String: Any]) -> OverlayStyle {
        OverlayStyle.parseScroll({ stored[$0] }, accentColor: .systemPink)
    }

    // MARK: - Letter case

    func test_hint_uppercase_defaultsOff_andReadsStoredValue() {
        XCTAssertFalse(hint([:]).uppercase)
        XCTAssertTrue(hint([K.hintUppercase: true]).uppercase)
    }

    @MainActor
    func test_attributedToken_followsCaseSetting() {
        let lower = HintLabelRenderer.attributedToken("as", typedPrefix: "a", style: hint([:]))
        let upper = HintLabelRenderer.attributedToken("as", typedPrefix: "a", style: hint([K.hintUppercase: true]))
        XCTAssertEqual(lower.string, "as")
        XCTAssertEqual(upper.string, "AS")
    }

    // MARK: - Opacity

    func test_hint_zeroOpacity_staysZero() {
        let style = hint([K.hintBackgroundOpacity: 0.0, K.hintBorderOpacity: 0.0])
        XCTAssertEqual(style.backgroundOpacity, 0)
        XCTAssertEqual(style.borderOpacity, 0)
    }

    func test_scroll_zeroOpacity_staysZero() {
        let style = scroll([K.scrollBackgroundOpacity: 0.0, K.scrollBorderOpacity: 0.0])
        XCTAssertEqual(style.backgroundOpacity, 0)
        XCTAssertEqual(style.borderOpacity, 0)
    }

    func test_hint_unsetOpacity_usesDefaults() {
        let style = hint([:])
        XCTAssertEqual(style.backgroundOpacity, CGFloat(D.hintBackgroundOpacity))
        XCTAssertEqual(style.borderOpacity, CGFloat(D.hintBorderOpacity))
    }

    func test_opacity_isClampedToUnitRange() {
        let style = hint([K.hintBackgroundOpacity: 1.7, K.hintBorderOpacity: -0.2])
        XCTAssertEqual(style.backgroundOpacity, 1)
        XCTAssertEqual(style.borderOpacity, 0)
    }

    func test_opacity_storedAsNSNumber_isRead() {
        let style = hint([K.hintBackgroundOpacity: NSNumber(value: 0.45)])
        XCTAssertEqual(style.backgroundOpacity, 0.45, accuracy: 0.0001)
    }

    // MARK: - Sizes and padding

    func test_nonPositiveFontSize_fallsBackToDefault() {
        XCTAssertEqual(hint([K.hintSize: 0.0]).fontSize, CGFloat(D.hintSize))
        XCTAssertEqual(scroll([K.scrollHintSize: -3.0]).fontSize, CGFloat(D.scrollHintSize))
        XCTAssertEqual(hint([K.hintSize: 16.0]).fontSize, 16)
    }

    func test_zeroPadding_isKept() {
        let style = hint([K.hintPaddingX: 0.0, K.hintPaddingY: 0.0])
        XCTAssertEqual(style.paddingX, 0)
        XCTAssertEqual(style.paddingY, 0)
    }

    func test_horizontalOffset_keepsNegativeValues() {
        XCTAssertEqual(hint([K.hintHorizontalOffset: -25.0]).horizontalOffset, -25)
    }

    // MARK: - Colours

    func test_validHex_isParsed() {
        let style = hint([K.hintTextHex: "#FF0000", K.highlightTextHex: "00FF00"])
        XCTAssertEqual(style.textColor, NSColor(hex: "#FF0000"))
        XCTAssertEqual(style.highlightTextColor, NSColor(hex: "#00FF00"))
    }

    func test_invalidHex_fallsBackToDefaultColour() {
        let style = hint([K.hintTextHex: "not a colour", K.hintBackgroundHex: "#12"])
        XCTAssertEqual(style.textColor, NSColor(hex: D.hintTextHex))
        XCTAssertEqual(style.backgroundColor, NSColor(hex: D.hintBackgroundHex))
    }

    func test_systemAccent_overridesTintAndBorder_butNotText() {
        let stored: [String: Any] = [
            K.useSystemAccentColor: true,
            K.hintBackgroundHex: "#FF0000",
            K.hintTextHex: "#00FF00",
        ]
        let style = hint(stored)
        XCTAssertEqual(style.backgroundColor, .systemPink)
        XCTAssertEqual(style.borderColor, .systemPink)
        XCTAssertEqual(style.textColor, NSColor(hex: "#00FF00"))

        let scrollStyle = scroll([K.useSystemAccentColor: true])
        XCTAssertEqual(scrollStyle.backgroundColor, .systemPink)
        XCTAssertEqual(scrollStyle.borderColor, .systemPink)
    }

    func test_defaultTypedPrefix_isWhite() {
        XCTAssertEqual(hint([:]).highlightTextColor, NSColor(hex: "#FFFFFF"))
    }

    func test_remainder_isTextColourAt55PercentAlpha() {
        let style = hint([K.hintTextHex: "#FF0000"])
        let remainder = style.remainderTextColor.usingColorSpace(.sRGB)!
        XCTAssertEqual(remainder.redComponent, 1, accuracy: 0.001)
        XCTAssertEqual(remainder.alphaComponent, 0.55, accuracy: 0.001)
    }

    func test_legacyYellowHighlight_stillParses() {
        XCTAssertEqual(hint([K.highlightTextHex: "#FFFF00"]).highlightTextColor, NSColor(hex: "#FFFF00"))
    }

    // MARK: - Label geometry

    func test_cornerRadius_isSevenAtDefaultSize_andScalesWithFont() {
        XCTAssertEqual(hint([:]).labelCornerRadius, 7, accuracy: 0.001)
        XCTAssertEqual(hint([K.hintSize: 18.0]).labelCornerRadius, 10.5, accuracy: 0.001)
    }

    // MARK: - Scroll specifics

    func test_scroll_usesFixedLabelGeometry() {
        let style = scroll([K.showHintTail: true, K.hintPaddingX: 1.0, K.hintHorizontalOffset: 40.0])
        XCTAssertFalse(style.showTail)
        XCTAssertEqual(style.paddingX, 10)
        XCTAssertEqual(style.paddingY, 6)
        XCTAssertEqual(style.horizontalOffset, 0)
    }

    // MARK: - Equatable

    func test_equalInputs_produceEqualStyles() {
        XCTAssertEqual(hint([K.hintSize: 14.0]), hint([K.hintSize: 14.0]))
        XCTAssertNotEqual(hint([K.hintSize: 14.0]), hint([K.hintSize: 15.0]))
    }
}
