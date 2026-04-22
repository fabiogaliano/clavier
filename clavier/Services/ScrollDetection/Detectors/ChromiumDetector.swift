//
//  ChromiumDetector.swift
//  clavier
//
//  Specialized detector for Chromium-based browsers (Chrome, Arc, Edge, Brave)
//  Optimizes detection of developer tools and web content
//

import Foundation
import AppKit
import os

@MainActor
class ChromiumDetector: AppSpecificDetector {

    var supportedBundleIdentifiers: Set<String> {
        [
            "com.google.Chrome",
            "com.google.Chrome.beta",
            "com.google.Chrome.dev",
            "com.google.Chrome.canary",
            "company.thebrowser.Browser",  // Arc
            "com.microsoft.edgemac",       // Edge
            "com.microsoft.edgemac.Beta",
            "com.microsoft.edgemac.Dev",
            "com.microsoft.edgemac.Canary",
            "com.brave.Browser",           // Brave
            "com.brave.Browser.beta",
            "com.brave.Browser.dev",
            "com.brave.Browser.nightly"
        ]
    }

    var priority: Int { 100 } // High priority for early execution

    func detect(
        windows: [AXUIElement],
        appElement: AXUIElement,
        bundleIdentifier: String,
        onAreaFound: ((ScrollableArea) -> Void)?,
        maxAreas: Int?
    ) -> DetectionResult {

        var areas: [ScrollableArea] = []
        var foundDevTools = false

        // Fast DevTools Detection - Look for AXSplitGroup (indicates docked dev tools)
        for window in windows {
            if let devToolsAreas = detectDevTools(in: window) {
                areas.append(contentsOf: devToolsAreas)
                foundDevTools = true

                // Call progressive callback
                devToolsAreas.forEach { onAreaFound?($0) }

                // Stop if we hit maxAreas
                if let max = maxAreas, areas.count >= max {
                    return .customAreas(areas)
                }
            }
        }

        // If we found dev tools, return them but continue normal traversal
        // (to also get main viewport, sidebars, etc.)
        if foundDevTools {
            Logger.scrollDetect.debug("ChromiumDetector: found \(areas.count, privacy: .public) DevTools panels")
            return .customAreasWithContinuation(areas)
        }

        // No dev tools detected, continue with normal detection
        return .continueNormal
    }

    /// Fast detection of Chromium DevTools panels
    /// Returns areas if DevTools detected, nil otherwise
    private func detectDevTools(in window: AXUIElement) -> [ScrollableArea]? {
        var areas: [ScrollableArea] = []

        guard case .success(let children) = AXReader.elements(kAXChildrenAttribute as CFString, of: window) else {
            return nil
        }

        // Look for AXSplitGroup (indicates docked dev tools)
        for child in children {
            guard case .success(let role) = AXReader.string(kAXRoleAttribute as CFString, of: child),
                  role == "AXSplitGroup" else {
                continue
            }

            // Found split group - this is the dev tools container
            // Now find large AXGroup elements inside (dev tools panels)
            findDevToolsPanels(in: child, depth: 0, maxDepth: 6, into: &areas)
        }

        return areas.isEmpty ? nil : areas
    }

    /// Find scrollable panels within DevTools split group
    private func findDevToolsPanels(in element: AXUIElement, depth: Int, maxDepth: Int, into areas: inout [ScrollableArea]) {
        guard depth < maxDepth else { return }

        guard case .success(let children) = AXReader.elements(kAXChildrenAttribute as CFString, of: element) else {
            return
        }

        for child in children {
            guard case .success(let role) = AXReader.string(kAXRoleAttribute as CFString, of: child) else {
                continue
            }

            // Look for large AXGroup elements (console, elements panel, network, sources)
            // that are rendered inside the embedded WebKit DevTools (AXWebArea ancestor).
            if role == "AXGroup",
               let area = ScrollableAXProbe.makeArea(from: child),
               area.frame.width > 400 && area.frame.height > 400,
               ScrollableAXProbe.hasWebAncestor(child) {
                areas.append(area)
            }

            // Recursively check children (dev tools has nested structure)
            findDevToolsPanels(in: child, depth: depth + 1, maxDepth: maxDepth, into: &areas)
        }
    }
}
