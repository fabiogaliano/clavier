//
//  DetectorRegistry.swift
//  clavier
//
//  Registry for app-specific scrollable area detectors.
//
//  Hint refresh timing policy (previously `refreshDelays(for:)`) has been
//  split out to `HintRefreshTimingPolicy` / `AppTimingRegistry` (F08/F24).
//

import Foundation

@MainActor
class DetectorRegistry {
    static let shared = DetectorRegistry()

    private var bundleIdToDetectors: [String: [AppSpecificDetector]] = [:]

    private init() {
        registerDefaultDetectors()
    }

    func register(_ detector: AppSpecificDetector) {
        for bundleId in detector.supportedBundleIdentifiers {
            bundleIdToDetectors[bundleId, default: []].append(detector)
        }

        for (bundleId, _) in bundleIdToDetectors {
            bundleIdToDetectors[bundleId]?.sort { $0.priority > $1.priority }
        }
    }

    func detectorsForBundleId(_ bundleId: String) -> [AppSpecificDetector] {
        bundleIdToDetectors[bundleId] ?? []
    }

    private func registerDefaultDetectors() {
        register(ChromiumDetector())
    }
}
