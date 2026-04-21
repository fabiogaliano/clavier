//
//  AppSpecificDetector.swift
//  clavier
//
//  Protocol for app-specific scrollable area detection
//

import Foundation
import AppKit

/// Whether normal AX traversal should run after an app-specific detector fires.
///
/// Replaces the `shouldContinueNormalTraversal: Bool` field that was embedded in
/// `DetectionResult` (F23).  An explicit enum makes the two cases self-documenting
/// at call sites and prevents accidental misuse of the boolean polarity.
enum DetectionContinuation {
    /// The detector fully handled this app; skip normal AX traversal.
    case stopTraversal
    /// The detector may have contributed areas; normal AX traversal should also run.
    case continueTraversal
}

/// Result from app-specific detection
struct DetectionResult {
    let areas: [ScrollableArea]
    let continuation: DetectionContinuation

    /// No custom areas found, continue with normal detection
    static var continueNormal: DetectionResult {
        DetectionResult(areas: [], continuation: .continueTraversal)
    }

    /// Custom areas found, skip normal traversal
    static func customAreas(_ areas: [ScrollableArea]) -> DetectionResult {
        DetectionResult(areas: areas, continuation: .stopTraversal)
    }

    /// Custom areas found, but also continue normal traversal
    static func customAreasWithContinuation(_ areas: [ScrollableArea]) -> DetectionResult {
        DetectionResult(areas: areas, continuation: .continueTraversal)
    }
}

/// Protocol for app-specific scrollable area detectors.
///
/// Scroll detection and hint refresh timing are now separate concerns (F08/F24).
/// Refresh delay configuration lives in `HintRefreshTimingPolicy` / `AppTimingRegistry`.
@MainActor
protocol AppSpecificDetector {
    /// Bundle identifiers this detector handles (e.g., "com.google.Chrome")
    var supportedBundleIdentifiers: Set<String> { get }

    /// Priority for detector execution (higher = runs first, default = 0)
    var priority: Int { get }

    /// Detect scrollable areas for supported apps.
    /// - Parameters:
    ///   - windows: AX windows from the app
    ///   - appElement: Root AX application element
    ///   - bundleIdentifier: Bundle ID of frontmost app
    ///   - onAreaFound: Progressive callback for each area found
    ///   - maxAreas: Optional limit on number of areas to find
    /// - Returns: Detection result with found areas and traversal continuation decision.
    func detect(
        windows: [AXUIElement],
        appElement: AXUIElement,
        bundleIdentifier: String,
        onAreaFound: ((ScrollableArea) -> Void)?,
        maxAreas: Int?
    ) -> DetectionResult
}

extension AppSpecificDetector {
    var priority: Int { 0 }
}
