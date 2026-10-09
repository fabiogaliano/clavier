//
//  ScrollInputDecoderTests.swift
//  clavierTests
//

import XCTest
import CoreGraphics
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
}
