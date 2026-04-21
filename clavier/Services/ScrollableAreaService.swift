//
//  ScrollableAreaService.swift
//  clavier
//
//  Queries UI elements via Accessibility APIs for scrollable areas
//

import Foundation
import AppKit

@MainActor
class ScrollableAreaService {

    static let shared = ScrollableAreaService()

    private let scrollableRoles: Set<String> = [
        "AXScrollArea",
        "AXScrollView",
        kAXTableRole as String,
        kAXOutlineRole as String,
        kAXListRole as String
        // Removed: "AXWebArea" - causes massive over-detection in browsers (every iframe, frame, document)
        // Removed: "AXTextArea" - too generic, causes false positives
        // Web content is still scrollable via scroll bar detection in hasScrollBars()
    ]

    // Configuration constants
    private enum Config {
        static let minimumAreaSize: CGFloat = 100
        static let duplicateTolerance: CGFloat = 10
        static let nestedTolerance: CGFloat = 5
        static let nestedSizeThreshold: CGFloat = 0.7  // Only filter nested areas >70% parent size
        static let sameOriginTolerance: CGFloat = 2.0  // Strict tolerance for X-origin matching
    }

    // Area relationship detection
    private enum AreaRelationship {
        case duplicate
        case newNestedInExisting
        case existingNestedInNew
        case independent

        static func detect(_ newArea: CGRect, _ existingArea: CGRect) -> AreaRelationship {
            // Check for duplicate (within tolerance)
            if abs(newArea.origin.x - existingArea.origin.x) < Config.duplicateTolerance &&
               abs(newArea.origin.y - existingArea.origin.y) < Config.duplicateTolerance &&
               abs(newArea.width - existingArea.width) < Config.duplicateTolerance &&
               abs(newArea.height - existingArea.height) < Config.duplicateTolerance {
                return .duplicate
            }

            // Check if new area is nested inside existing
            if newArea.minX >= existingArea.minX - Config.nestedTolerance &&
               newArea.maxX <= existingArea.maxX + Config.nestedTolerance &&
               newArea.minY >= existingArea.minY - Config.nestedTolerance &&
               newArea.maxY <= existingArea.maxY + Config.nestedTolerance {

                // If they share the same X origin, they're the same scrollable (filter regardless of size)
                let sameXOrigin = abs(newArea.origin.x - existingArea.origin.x) < Config.sameOriginTolerance

                if sameXOrigin {
                    return .newNestedInExisting
                }

                // Otherwise, only filter if >70% the size (near-duplicate)
                let newAreaSize = newArea.width * newArea.height
                let existingAreaSize = existingArea.width * existingArea.height
                let sizeRatio = newAreaSize / existingAreaSize

                if sizeRatio > Config.nestedSizeThreshold {
                    return .newNestedInExisting
                }
            }

            // Check if existing area is nested inside new
            if existingArea.minX >= newArea.minX - Config.nestedTolerance &&
               existingArea.maxX <= newArea.maxX + Config.nestedTolerance &&
               existingArea.minY >= newArea.minY - Config.nestedTolerance &&
               existingArea.maxY <= newArea.maxY + Config.nestedTolerance {

                // If they share the same X origin, they're the same scrollable (filter regardless of size)
                let sameXOrigin = abs(newArea.origin.x - existingArea.origin.x) < Config.sameOriginTolerance

                if sameXOrigin {
                    return .existingNestedInNew
                }

                // Otherwise, only filter if >70% the size (near-duplicate)
                let newAreaSize = newArea.width * newArea.height
                let existingAreaSize = existingArea.width * existingArea.height
                let sizeRatio = existingAreaSize / newAreaSize

                if sizeRatio > Config.nestedSizeThreshold {
                    return .existingNestedInNew
                }
            }

            return .independent
        }
    }

    /// Centralized logic to determine if a new area should be added
    /// Returns true if should add, modifies areas array to remove nested ones
    private func shouldAddArea(_ newArea: ScrollableArea, to areas: inout [ScrollableArea]) -> Bool {
        var indicesToRemove: [Int] = []

        for (index, existing) in areas.enumerated() {
            let relationship = AreaRelationship.detect(newArea.frame, existing.frame)

            switch relationship {
            case .duplicate:
                return false // Skip duplicate

            case .newNestedInExisting:
                return false // Skip nested area

            case .existingNestedInNew:
                // Mark existing area for removal (keep larger new area)
                indicesToRemove.append(index)

            case .independent:
                // Check if they're vertically stacked sections (same X/width, different Y/height)
                if abs(newArea.frame.origin.x - existing.frame.origin.x) < Config.duplicateTolerance &&
                   abs(newArea.frame.width - existing.frame.width) < Config.duplicateTolerance &&
                   abs(newArea.frame.origin.y - existing.frame.origin.y) >= Config.duplicateTolerance {

                    // They're sections in the same vertical column - keep the larger one
                    let newSize = newArea.frame.width * newArea.frame.height
                    let existingSize = existing.frame.width * existing.frame.height

                    if newSize > existingSize {
                        // New area is larger, remove existing
                        indicesToRemove.append(index)
                    } else {
                        // Existing is larger, skip new
                        return false
                    }
                }
                continue
            }
        }

        // Remove marked areas (in reverse order to maintain indices)
        for index in indicesToRemove.reversed() {
            areas.remove(at: index)
        }

        return true
    }

    func getScrollableAreas(onAreaFound: ((ScrollableArea) -> Void)? = nil, maxAreas: Int? = nil) -> [ScrollableArea] {
        let startTime = Date()
        var elementCount = 0

        guard let focusedApp = NSWorkspace.shared.frontmostApplication,
              let pid = focusedApp.processIdentifier as pid_t?,
              let bundleId = focusedApp.bundleIdentifier else {
            return []
        }

        let appElement = AXUIElementCreateApplication(pid)
        var areas: [ScrollableArea] = []
        var shouldStop = false

        // Get all windows
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return []
        }

        // Try app-specific detection first
        let detectors = DetectorRegistry.shared.detectorsForBundleId(bundleId)
        var shouldContinueNormalTraversal = true

        for detector in detectors {
            let result = detector.detect(
                windows: windows,
                appElement: appElement,
                bundleIdentifier: bundleId,
                onAreaFound: onAreaFound,
                maxAreas: maxAreas
            )

            // Add any areas found by the detector
            areas.append(contentsOf: result.areas)

            // Check if we should stop
            if let max = maxAreas, areas.count >= max {
                return areas
            }

            // If detector says skip normal traversal, note it
            if !result.shouldContinueNormalTraversal {
                shouldContinueNormalTraversal = false
                break
            }
        }

        // Continue with normal traversal if detectors allow it
        if shouldContinueNormalTraversal {
            for (_, window) in windows.enumerated() {
                guard !shouldStop else { break }
                traverseElement(window, into: &areas, depth: 0, maxDepth: 10, elementCount: &elementCount, onAreaFound: onAreaFound, shouldStop: &shouldStop, maxAreas: maxAreas)
            }
        }

        return areas
    }

    /// Fast focus detection - finds the focused scrollable area directly without needing full area list
    func findFocusedScrollableArea() -> ScrollableArea? {
        let startTime = Date()

        guard let focusedApp = NSWorkspace.shared.frontmostApplication,
              let pid = focusedApp.processIdentifier as pid_t? else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(pid)

        // Get the focused element
        guard case .success(let focusedElement) = AXReader.element(kAXFocusedUIElementAttribute as CFString, of: appElement) else {
            print("[PERF] No focused element found")
            return nil
        }

        // Walk up the parent chain to find a scrollable container
        var currentElement: AXUIElement? = focusedElement
        var stepCount = 0

        while let element = currentElement {
            stepCount += 1

            // Check if this element is scrollable
            if case .success(let role) = AXReader.string(kAXRoleAttribute as CFString, of: element),
               (scrollableRoles.contains(role) || hasScrollBars(element)) {

                // Create scrollable area from this element
                if let area = createScrollableArea(from: element),
                   area.frame.width > 100 && area.frame.height > 100 {
                    return area
                }
            }

            // Move to parent
            if case .success(let parent) = AXReader.element(kAXParentAttribute as CFString, of: element) {
                currentElement = parent
            } else {
                break
            }
        }

        return nil
    }

    /// Find the index of a scrollable area that contains the currently focused element
    func findFocusedScrollableAreaIndex(in areas: [ScrollableArea]) -> Int? {
        guard let focusedApp = NSWorkspace.shared.frontmostApplication,
              let pid = focusedApp.processIdentifier as pid_t? else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(pid)

        // Get the focused element
        guard case .success(let focusedElement) = AXReader.element(kAXFocusedUIElementAttribute as CFString, of: appElement) else {
            return nil
        }

        // Walk up the parent chain to find a scrollable container
        var currentElement: AXUIElement? = focusedElement

        while let element = currentElement {
            // Check if this element is one of our scrollable areas
            if let index = findMatchingAreaIndex(element: element, in: areas) {
                return index
            }

            // Move to parent
            if case .success(let parent) = AXReader.element(kAXParentAttribute as CFString, of: element) {
                currentElement = parent
            } else {
                break
            }
        }

        return nil
    }

    /// Find the index of a scrollable area under the mouse cursor
    func findScrollableAreaUnderCursorIndex(in areas: [ScrollableArea]) -> Int? {
        // Get current mouse cursor position
        let cursorLocation = NSEvent.mouseLocation

        // Find which area contains the cursor
        for (index, area) in areas.enumerated() {
            if area.frame.contains(cursorLocation) {
                return index
            }
        }

        return nil
    }

    /// Helper to find if an AXUIElement matches one of our scrollable areas
    private func findMatchingAreaIndex(element: AXUIElement, in areas: [ScrollableArea]) -> Int? {
        guard let elementArea = createScrollableArea(from: element) else {
            return nil
        }

        // Find matching area by comparing frames
        for (index, area) in areas.enumerated() {
            if abs(area.frame.origin.x - elementArea.frame.origin.x) < 5 &&
               abs(area.frame.origin.y - elementArea.frame.origin.y) < 5 &&
               abs(area.frame.width - elementArea.frame.width) < 5 &&
               abs(area.frame.height - elementArea.frame.height) < 5 {
                return index
            }
        }

        return nil
    }

    private func traverseElement(
        _ element: AXUIElement,
        into areas: inout [ScrollableArea],
        depth: Int,
        maxDepth: Int,
        elementCount: inout Int,
        onAreaFound: ((ScrollableArea) -> Void)?,
        shouldStop: inout Bool,
        maxAreas: Int?
    ) {
        // Check if we should stop early
        if shouldStop {
            return
        }

        if let max = maxAreas, areas.count >= max {
            shouldStop = true
            return
        }

        elementCount += 1

        // Stop if we've reached max depth
        guard depth < maxDepth else {
            return
        }

        // Get role
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String else {
            return
        }

        // Check if element is scrollable (with validation for progressive discovery)
        let hasScrollableRole = scrollableRoles.contains(role)
        let hasEnabledScrollBars = hasScrollBars(element, validateEnabled: true)

        // For progressive discovery, require either a scrollable role with enabled scrollbars, or just enabled scrollbars
        if hasScrollableRole || hasEnabledScrollBars {
            // If it has a scrollable role but no enabled scrollbars, check if it's web content
            if hasScrollableRole && !hasEnabledScrollBars {
                // Check if this is web content - web scrollables don't expose native scrollbar attributes
                let isWebContent = hasWebAncestor(element)

                if isWebContent {
                    // Web scrollables are accepted without native scrollbar validation
                    if let area = createScrollableArea(from: element) {
                        // Size filter only — origin check omitted because secondary displays
                        // can have negative AppKit coordinates (screens left of or below main).
                        if area.frame.width > Config.minimumAreaSize &&
                           area.frame.height > Config.minimumAreaSize {

                            // Use centralized area filtering logic
                            if shouldAddArea(area, to: &areas) {
                                areas.append(area)
                                onAreaFound?(area)

                                if let max = maxAreas, areas.count >= max {
                                    shouldStop = true
                                    return
                                }
                            }
                        }
                    }
                }
            } else if let area = createScrollableArea(from: element) {
                // Size filter only — see comment above for why origin check is omitted.
                if area.frame.width > Config.minimumAreaSize &&
                   area.frame.height > Config.minimumAreaSize {

                    // Use centralized area filtering logic
                    if shouldAddArea(area, to: &areas) {
                        areas.append(area)
                        onAreaFound?(area)

                        if let max = maxAreas, areas.count >= max {
                            shouldStop = true
                            return
                        }
                    }
                }
            }
        }

        // Traverse children
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return
        }

        for child in children {
            guard !shouldStop else { return }
            traverseElement(child, into: &areas, depth: depth + 1, maxDepth: maxDepth, elementCount: &elementCount, onAreaFound: onAreaFound, shouldStop: &shouldStop, maxAreas: maxAreas)
        }
    }

    private func hasScrollBars(_ element: AXUIElement, validateEnabled: Bool = false) -> Bool {
        let vResult = AXReader.element("AXVerticalScrollBar" as CFString, of: element)
        let hResult = AXReader.element("AXHorizontalScrollBar" as CFString, of: element)

        if !validateEnabled {
            if case .success = vResult { return true }
            if case .success = hResult { return true }
            return false
        }

        // Validate that at least one scroll bar is actually enabled (has scrollable content)
        if case .success(let vScrollBar) = vResult,
           case .success(true) = AXReader.bool(kAXEnabledAttribute as CFString, of: vScrollBar) {
            return true
        }

        if case .success(let hScrollBar) = hResult,
           case .success(true) = AXReader.bool(kAXEnabledAttribute as CFString, of: hScrollBar) {
            return true
        }

        return false
    }

    private func hasWebAncestor(_ element: AXUIElement) -> Bool {
        var currentElement = element
        let maxLevels = 10

        for _ in 0..<maxLevels {
            guard case .success(let role) = AXReader.string(kAXRoleAttribute as CFString, of: currentElement) else {
                break
            }

            if role == "AXWebArea" {
                return true
            }

            guard case .success(let parent) = AXReader.element(kAXParentAttribute as CFString, of: currentElement) else {
                break
            }

            currentElement = parent
        }

        return false
    }


    private func createScrollableArea(from axElement: AXUIElement) -> ScrollableArea? {
        guard case .success(let frame) = AXReader.appKitFrame(of: axElement) else { return nil }
        return ScrollableArea(axElement: axElement, frame: frame)
    }
}
