//
//  ClickService.swift
//  clavier
//
//  Performs click actions via CGEvent
//

import Foundation
import AppKit

@MainActor
class ClickService {

    static let shared = ClickService()

    /// `flags` is set explicitly on every event: the user is usually still
    /// holding the modifier that chose the verb (⌃, ⇧), and letting it leak
    /// into the click would turn a double click into a shift-double-click.
    func click(at point: CGPoint, flags: CGEventFlags = []) {
        postClick(at: point, button: .left, flags: flags, clickState: 1)
    }

    func rightClick(at point: CGPoint) {
        postClick(at: point, button: .right, flags: [], clickState: 1)
    }

    /// The second press carries click state 2; without it apps see two
    /// unrelated single clicks rather than a double click.
    func doubleClick(at point: CGPoint) {
        postClick(at: point, button: .left, flags: [], clickState: 1)
        postClick(at: point, button: .left, flags: [], clickState: 2)
    }

    func moveCursor(to point: CGPoint) {
        let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
        move?.flags = []
        SyntheticClickTag.tag(move)
        move?.post(tap: .cghidEventTap)
    }

    private func postClick(at point: CGPoint, button: CGMouseButton, flags: CGEventFlags, clickState: Int64) {
        let (downType, upType): (CGEventType, CGEventType) = button == .right
            ? (.rightMouseDown, .rightMouseUp)
            : (.leftMouseDown, .leftMouseUp)
        let events = [
            CGEvent(mouseEventSource: nil, mouseType: downType, mouseCursorPosition: point, mouseButton: button),
            CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: point, mouseButton: button)
        ]
        for event in events {
            event?.flags = flags
            event?.setIntegerValueField(.mouseEventClickState, value: clickState)
            SyntheticClickTag.tag(event)
            event?.post(tap: .cghidEventTap)
        }
    }

    func scroll(at point: CGPoint, direction: ScrollDirection, speed: Double) {
        // Convert speed (1-10) to scroll delta
        let baseDelta = Int32(speed * 10)

        var deltaX: Int32 = 0
        var deltaY: Int32 = 0

        switch direction {
        case .up:
            deltaY = baseDelta
        case .down:
            deltaY = -baseDelta
        case .left:
            deltaX = baseDelta
        case .right:
            deltaX = -baseDelta
        }

        // Create scroll wheel event
        let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        )

        // Move cursor to scroll area center before scrolling
        let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
        moveEvent?.post(tap: .cghidEventTap)

        scrollEvent?.post(tap: .cghidEventTap)
    }
}

