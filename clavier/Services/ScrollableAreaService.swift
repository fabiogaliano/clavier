//
//  ScrollableAreaService.swift
//  clavier
//
//  Façade for scrollable-area discovery: resolves the frontmost app, runs the
//  app-specific detector chain, and falls back to generic AX traversal.
//
//  The heavy lifting now lives in dedicated types under `ScrollDetection/`:
//    - `ScrollableAXProbe`              — shared AX hierarchy / role helpers
//    - `FocusedScrollableAreaFinder`    — Phase 1 focused-area lookup
//    - `ScrollableAreaTraverser`        — Phase 2 generic traversal + merge
//    - `ScrollableAreaMerger`           — merge / dedupe policy
//    - `DetectorRegistry` + `AppSpecificDetector` — per-app detection strategy
//

import Foundation
import AppKit

@MainActor
class ScrollableAreaService {

    static let shared = ScrollableAreaService()

    private let merger = ScrollableAreaMerger()
    private let focusedFinder = FocusedScrollableAreaFinder()
    private let traverser: ScrollableAreaTraverser

    init() {
        self.traverser = ScrollableAreaTraverser(merger: merger)
    }

    /// Discover scrollable areas in the frontmost application.
    ///
    /// Runs the per-app detector chain first; if no detector signals
    /// `.stopTraversal`, falls back to generic AX traversal so common
    /// containers (sidebars, viewport, etc.) are still picked up.
    func getScrollableAreas(
        onAreaFound: ((ScrollableArea) -> Void)? = nil,
        maxAreas: Int? = nil
    ) -> [ScrollableArea] {
        guard let context = frontmostAppContext() else { return [] }

        var areas: [ScrollableArea] = []
        var continuation: DetectionContinuation = .continueTraversal

        for detector in DetectorRegistry.shared.detectorsForBundleId(context.bundleId) {
            let result = detector.detect(
                windows: context.windows,
                appElement: context.appElement,
                bundleIdentifier: context.bundleId,
                onAreaFound: onAreaFound,
                maxAreas: maxAreas
            )

            areas.append(contentsOf: result.areas)

            if let max = maxAreas, areas.count >= max {
                return areas
            }

            if result.continuation == .stopTraversal {
                continuation = .stopTraversal
                break
            }
        }

        if continuation == .continueTraversal {
            let remaining = maxAreas.map { max(0, $0 - areas.count) }
            let traversed = traverser.traverse(
                windows: context.windows,
                onAreaFound: onAreaFound,
                maxAreas: remaining
            )
            areas.append(contentsOf: traversed)
        }

        return areas
    }

    /// Fast Phase 1 lookup: walk up from the AX-focused element to the nearest
    /// scrollable container. Returns `nil` if no usable container is found.
    func findFocusedScrollableArea() -> ScrollableArea? {
        focusedFinder.find()
    }

    // MARK: - Helpers

    private struct AppContext {
        let bundleId: String
        let appElement: AXUIElement
        let windows: [AXUIElement]
    }

    private func frontmostAppContext() -> AppContext? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let pid = app.processIdentifier as pid_t?,
              let bundleId = app.bundleIdentifier else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(pid)

        guard case .success(let windows) = AXReader.elements(kAXWindowsAttribute as CFString, of: appElement) else {
            return nil
        }

        return AppContext(bundleId: bundleId, appElement: appElement, windows: windows)
    }
}
