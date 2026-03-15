//
//  ScreenGeometry.swift
//  clavier
//
//  Shared coordinate-system conversions for multi-display correctness.
//

import AppKit

/// Centralises all coordinate-system conversions used by the app.
///
/// Two coordinate systems are relevant:
///
/// **AX / Quartz** — used by the Accessibility API (`AXUIElement` positions and sizes)
///   and by `CGEvent` synthetic clicks/scrolls.
///   - Origin: top-left of the main display (the screen with the menu bar).
///   - Y increases **downward**.
///
/// **AppKit** — used by `NSWindow`, `NSView`, `NSScreen`, and `NSEvent.mouseLocation`.
///   - Origin: bottom-left of the main display.
///   - Y increases **upward**.
///
/// The Y-flip between the two systems always uses `mainScreenHeight` as the reference
/// because the AX origin is defined relative to the top-left of *that* screen.
/// This means the same formula works for elements on any display.
struct ScreenGeometry {

    // MARK: - Desktop bounds

    /// Union of all display frames in AppKit coordinates.
    ///
    /// Use this as the overlay window's `contentRect` so that hint and scroll
    /// overlays can render on every connected display, not just the main one.
    static var desktopBoundsInAppKit: CGRect {
        NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
    }

    /// Union of all display frames converted to AX / Quartz coordinates.
    ///
    /// Use this as the root clip rect when traversing AX element trees so that
    /// elements on non-main displays are not incorrectly culled.
    static var desktopBoundsInAX: CGRect {
        NSScreen.screens.reduce(CGRect.null) { acc, screen in
            acc.union(screenFrameToAX(screen.frame))
        }
    }

    // MARK: - Frame conversion

    /// Convert an AX element position and size to an AppKit `CGRect`.
    ///
    /// The AX API reports the top-left corner of an element; AppKit expects the
    /// bottom-left corner.  `mainScreenHeight` provides the flip axis that is
    /// correct for all displays in the current layout.
    static func axToAppKit(position: CGPoint, size: CGSize) -> CGRect {
        let flippedY = mainScreenHeight - position.y - size.height
        return CGRect(x: position.x, y: flippedY, width: size.width, height: size.height)
    }

    /// Convert an AppKit center point (from `element.centerPoint` or `area.centerPoint`)
    /// to Quartz / `CGEvent` screen coordinates for posting synthetic events.
    ///
    /// `CGEvent` mouse and scroll events use the same coordinate system as the
    /// AX API (top-left origin, y downward), so this is the inverse of the
    /// Y-flip in `axToAppKit`.
    static func appKitCenterToQuartz(_ center: CGPoint) -> CGPoint {
        CGPoint(x: center.x, y: mainScreenHeight - center.y)
    }

    // MARK: - Overlay coordinate helper

    /// Offset a rect that is in AppKit screen coordinates into the local coordinate
    /// system of an overlay window whose frame equals `desktopBoundsInAppKit`.
    ///
    /// NSWindow content views have their origin at (0, 0) in the *window's* local
    /// space, not in screen space.  When the window's origin is at a non-zero
    /// screen position (e.g. a leftmost display with negative x, or a display
    /// below the main screen with negative y), hint/highlight views must be
    /// translated by this offset so they appear at the correct screen location.
    static func toWindowLocal(_ screenRect: CGRect) -> CGRect {
        let origin = desktopBoundsInAppKit.origin
        return screenRect.offsetBy(dx: -origin.x, dy: -origin.y)
    }

    // MARK: - Helpers

    /// Height of the display that carries the menu bar.
    ///
    /// All Y-flip conversions use this as the reference because the AX coordinate
    /// origin is defined relative to the top-left of this particular display.
    static var mainScreenHeight: CGFloat {
        NSScreen.main?.frame.height ?? 0
    }

    // MARK: - Private

    /// Convert an NSScreen frame (AppKit coords) to its equivalent AX / Quartz rect.
    private static func screenFrameToAX(_ screenFrame: CGRect) -> CGRect {
        let h = mainScreenHeight
        return CGRect(
            x: screenFrame.origin.x,
            y: h - screenFrame.origin.y - screenFrame.height,
            width: screenFrame.width,
            height: screenFrame.height
        )
    }
}
