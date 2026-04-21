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

    private var detectors: [AppSpecificDetector] = []
    private var bundleIdToDetectors: [String: [AppSpecificDetector]] = [:]

    private init() {
        registerDefaultDetectors()
    }

    func register(_ detector: AppSpecificDetector) {
        detectors.append(detector)

        for bundleId in detector.supportedBundleIdentifiers {
            bundleIdToDetectors[bundleId, default: []].append(detector)
        }

        detectors.sort { $0.priority > $1.priority }
        for (bundleId, _) in bundleIdToDetectors {
            bundleIdToDetectors[bundleId]?.sort { $0.priority > $1.priority }
        }
    }

    func detectorsForBundleId(_ bundleId: String) -> [AppSpecificDetector] {
        bundleIdToDetectors[bundleId] ?? []
    }

    func hasDetectorFor(_ bundleId: String) -> Bool {
        bundleIdToDetectors[bundleId] != nil
    }

    private func registerDefaultDetectors() {
        register(ChromiumDetector())
    }
}
