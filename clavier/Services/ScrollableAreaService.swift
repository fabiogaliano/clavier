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

    // Configuration constants
    private enum Config {
        static let minimumAreaSize: CGFloat = 100
    }

    private let merger = ScrollableAreaMerger()

    /// Canonical merge-policy gate: delegates to `ScrollableAreaMerger`.
    ///
    /// Returns true if the candidate should be appended; removes any existing
    /// areas that the candidate supersedes.  The controller's progressive
    /// discovery path (P2-S2) will converge on the same merger instance.
    private func shouldAddArea(_ newArea: ScrollableArea, to areas: inout [ScrollableArea]) -> Bool {
        let existingFrames = areas.map(\.frame)
        let decision = merger.decision(for: newArea.frame, against: existingFrames)

        switch decision {
        case .discard, .nestedInExisting:
            return false

        case .replaceExisting(let indices):
            for index in indices.sorted().reversed() {
                areas.remove(at: index)
            }
            return true

        case .add:
            return true
        }
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
        var traversalContinuation: DetectionContinuation = .continueTraversal

        for detector in detectors {
            let result = detector.detect(
                windows: windows,
                appElement: appElement,
                bundleIdentifier: bundleId,
                onAreaFound: onAreaFound,
                maxAreas: maxAreas
            )

            areas.append(contentsOf: result.areas)

            if let max = maxAreas, areas.count >= max {
                return areas
            }

            if result.continuation == .stopTraversal {
                traversalContinuation = .stopTraversal
                break
            }
        }

        if traversalContinuation == .continueTraversal {
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
               (ScrollableAXProbe.scrollableRoles.contains(role) || ScrollableAXProbe.hasScrollBars(element)) {

                // Create scrollable area from this element
                if let area = ScrollableAXProbe.makeArea(from: element),
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

    /// Helper to find if an AXUIElement matches one of our scrollable areas
    private func findMatchingAreaIndex(element: AXUIElement, in areas: [ScrollableArea]) -> Int? {
        guard let elementArea = ScrollableAXProbe.makeArea(from: element) else {
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
        let hasScrollableRole = ScrollableAXProbe.scrollableRoles.contains(role)
        let hasEnabledScrollBars = ScrollableAXProbe.hasScrollBars(element, validateEnabled: true)

        // For progressive discovery, require either a scrollable role with enabled scrollbars, or just enabled scrollbars
        if hasScrollableRole || hasEnabledScrollBars {
            // If it has a scrollable role but no enabled scrollbars, check if it's web content
            if hasScrollableRole && !hasEnabledScrollBars {
                // Check if this is web content - web scrollables don't expose native scrollbar attributes
                let isWebContent = ScrollableAXProbe.hasWebAncestor(element)

                if isWebContent {
                    // Web scrollables are accepted without native scrollbar validation
                    if let area = ScrollableAXProbe.makeArea(from: element) {
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
            } else if let area = ScrollableAXProbe.makeArea(from: element) {
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

}
