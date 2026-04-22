//
//  FocusedScrollableAreaFinder.swift
//  clavier
//
//  Phase 1 of two-phase scroll-area discovery: starts from the AX-focused
//  element and walks up the parent chain to the nearest scrollable container.
//
//  Previously embedded in `ScrollableAreaService.findFocusedScrollableArea()`.
//  Splitting it out keeps the service file focused on detector orchestration
//  and lets `ScrollDiscoveryCoordinator` depend on a narrower seam.
//

import AppKit

/// Finds the scrollable container that owns the AX-focused element.
///
/// Used by `ScrollDiscoveryCoordinator` for the fast Phase 1 result; the
/// returned area is auto-selected regardless of cursor position.
@MainActor
struct FocusedScrollableAreaFinder {

    /// Minimum side length in points for a focused area to be considered
    /// usable. Matches the previous inline literal in
    /// `ScrollableAreaService.findFocusedScrollableArea`.
    static let minimumSize: CGFloat = 100

    /// Locate the nearest scrollable ancestor of the AX-focused element of the
    /// frontmost application, or `nil` if no suitable container is found.
    func find() -> ScrollableArea? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let pid = app.processIdentifier as pid_t? else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(pid)

        guard case .success(let focusedElement) = AXReader.element(
            kAXFocusedUIElementAttribute as CFString,
            of: appElement
        ) else {
            return nil
        }

        return walkAncestors(from: focusedElement)
    }

    /// Walk parents from `start` up to the application root, returning the
    /// first ancestor that qualifies as a usable scrollable area.
    private func walkAncestors(from start: AXUIElement) -> ScrollableArea? {
        var current: AXUIElement? = start
        while let element = current {
            if isScrollable(element),
               let area = ScrollableAXProbe.makeArea(from: element),
               area.frame.width > Self.minimumSize,
               area.frame.height > Self.minimumSize {
                return area
            }

            switch AXReader.element(kAXParentAttribute as CFString, of: element) {
            case .success(let parent):
                current = parent
            case .failure:
                return nil
            }
        }
        return nil
    }

    private func isScrollable(_ element: AXUIElement) -> Bool {
        guard case .success(let role) = AXReader.string(kAXRoleAttribute as CFString, of: element) else {
            return false
        }
        return ScrollableAXProbe.scrollableRoles.contains(role)
            || ScrollableAXProbe.hasScrollBars(element)
    }
}
