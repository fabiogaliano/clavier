//
//  AccessibilityService.swift
//  clavier
//
//  Queries UI elements via Accessibility APIs
//

import Foundation
import AppKit

@MainActor
class AccessibilityService {

    static let shared = AccessibilityService()

    private let clickability = ClickabilityPolicy.default
    private let ancestorDedupe = AncestorDedupePolicy.default

    /// Traversal-local wrapper carrying a discovered element plus the
    /// bookkeeping needed for ancestor-based deduplication.  The ancestor
    /// hash is intentionally NOT stored on `UIElement` — it is a traversal
    /// concern only, collapsed into a clean `[UIElement]` before return.
    private struct PendingElement {
        var element: UIElement
        var clickableAncestorHash: Int?
    }

    func getClickableElements() -> [UIElement] {
        guard let focusedApp = NSWorkspace.shared.frontmostApplication,
              let pid = focusedApp.processIdentifier as pid_t? else {
            return []
        }

        let appElement = AXUIElementCreateApplication(pid)
        var pending: [PendingElement] = []

        // Get all windows
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return []
        }

        // Use the full desktop bounds in AX coordinates so windows on non-main
        // displays are not silently dropped by the intersection clip.
        let desktopBoundsAX = ScreenGeometry.desktopBoundsInAX

        // Process each window with visibility clipping
        let traverseStartTime = CFAbsoluteTimeGetCurrent()
        for window in windows {
            // Get window frame for visibility clipping
            let windowBounds = getWindowBounds(window) ?? desktopBoundsAX
            let visibleBounds = windowBounds.intersection(desktopBoundsAX)

            traverseElementOptimized(window, pid: pid, clickableAncestor: nil, into: &pending, clipBounds: visibleBounds)
        }
        let traverseEndTime = CFAbsoluteTimeGetCurrent()
        print("  ⏱️ traverseElements: \(String(format: "%.3f", traverseEndTime - traverseStartTime))s (\(pending.count) raw elements)")

        // Deduplicate elements whose clickable ancestor is already in the list.
        let dedupeStartTime = CFAbsoluteTimeGetCurrent()
        let deduplicated = pending.compactMap { $0.clickableAncestorHash == nil ? $0.element : nil }
        let dedupeEndTime = CFAbsoluteTimeGetCurrent()
        print("  ⏱️ deduplicateElements: \(String(format: "%.3f", dedupeEndTime - dedupeStartTime))s (\(deduplicated.count) unique)")

        return deduplicated
    }

    private func getWindowBounds(_ window: AXUIElement) -> CGRect? {
        switch AXReader.axFrameBatched(of: window) {
        case .success(let frame): return frame
        case .failure: return nil
        }
    }

    private func traverseElementOptimized(_ element: AXUIElement, pid: pid_t, clickableAncestor: (element: AXUIElement, frame: CGRect)?, into pending: inout [PendingElement], clipBounds: CGRect) {
        // BATCH FETCH: Get role, position, size, children, enabled in ONE IPC call
        let attributes = [
            kAXRoleAttribute as CFString,
            kAXPositionAttribute as CFString,
            kAXSizeAttribute as CFString,
            kAXChildrenAttribute as CFString,
            kAXEnabledAttribute as CFString
        ] as CFArray

        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, attributes, [], &values) == .success,
              let valuesArray = values as? [Any],
              valuesArray.count == 5 else {
            return
        }

        // Extract role
        guard let role = valuesArray[0] as? String else {
            return
        }

        // Extract position and size for visibility check
        guard let position = AXReader.decodeCGPoint(from: valuesArray[1]) else { return }
        guard let size = AXReader.decodeCGSize(from: valuesArray[2]) else { return }

        let elementFrame = CGRect(origin: position, size: size)

        // VISIBILITY CLIPPING: Skip entire subtree if element is off-screen
        if !elementFrame.intersects(clipBounds) {
            return // Early exit - don't traverse children
        }

        // Convert AX coordinates (top-left origin, y down) to AppKit (bottom-left origin, y up).
        let frame = ScreenGeometry.axToAppKit(position: position, size: size)

        // Extract enabled state (may be absent for non-interactive elements)
        let enabled = valuesArray[4] as? Bool

        let isClickable = clickability.isClickable(role: role, element: element, enabled: enabled)

        // If this element is clickable, it becomes the new ancestor for its children
        let newClickableAncestor: (element: AXUIElement, frame: CGRect)? = isClickable ? (element, frame) : clickableAncestor

        if isClickable {
            // Filter out elements too small to be meaningful click targets.
            // The origin check is intentionally omitted: secondary displays can
            // have negative AppKit coordinates (screens left of or below main).
            if frame.width > 5 && frame.height > 5 {
                // Compute the portion of the element that is actually visible
                // after ancestor/scroll/viewport clipping. Vimium-style: anchor
                // the hint to the visible rect so partially-clipped elements
                // don't get hints placed off-screen or behind containers.
                let visibleAX = elementFrame.intersection(clipBounds)
                let visibleFrame = ScreenGeometry.axToAppKit(
                    position: visibleAX.origin,
                    size: visibleAX.size
                )
                let uiElement = UIElement(
                    stableID: ElementIdentity(pid: pid, role: role, frame: frame),
                    axElement: element,
                    frame: frame,
                    visibleFrame: visibleFrame,
                    role: role
                )
                // Frame-aware dedup: only mark as duplicate if frames nearly match ancestor.
                // The ancestor hash lives on the traversal-local wrapper, not on UIElement.
                var ancestorHash: Int? = nil
                if let ancestor = clickableAncestor,
                   ancestorDedupe.framesMatch(frame, ancestor.frame) {
                    ancestorHash = Int(CFHash(ancestor.element))
                }
                pending.append(PendingElement(element: uiElement, clickableAncestorHash: ancestorHash))
            }
        }

        // SMART PRUNING: Skip subtrees for roles that never contain clickable children
        if clickability.canPruneSubtree(role: role) {
            return // Don't traverse children of these roles
        }

        // Traverse children (already fetched in batch call)
        guard let children = valuesArray[3] as? [AXUIElement] else {
            return
        }

        // Use tighter clip bounds for children (intersection with current element)
        let childClipBounds = elementFrame.intersection(clipBounds)

        for child in children {
            traverseElementOptimized(child, pid: pid, clickableAncestor: newClickableAncestor, into: &pending, clipBounds: childClipBounds)
        }
    }

}
