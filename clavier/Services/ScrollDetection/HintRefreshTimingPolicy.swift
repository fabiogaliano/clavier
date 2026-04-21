//
//  HintRefreshTimingPolicy.swift
//  clavier
//
//  Per-app hint refresh timing policy for continuous click mode.
//
//  This concern was previously carried by `AppSpecificDetector` via
//  `optimisticRefreshDelay` / `fallbackRefreshDelay` fields and surfaced
//  through `DetectorRegistry.refreshDelays(for:)` (F08 / F24).
//
//  Separating it here means:
//  - `AppSpecificDetector` is purely about scroll area detection.
//  - `HintModeController` (and its future `HintRefreshCoordinator` in P4-S2)
//    can depend on this contract without touching the scroll detection graph.
//

import Foundation

/// Per-app optimistic and fallback delays used by continuous hint mode refresh.
struct HintRefreshDelays {
    /// Delay before the first (optimistic) hint refresh after a click.
    let optimistic: TimeInterval
    /// Additional delay before the fallback refresh if the UI had not yet changed.
    let fallback: TimeInterval
}

/// Provides per-bundle-id hint refresh timing overrides.
///
/// When no override is registered for a bundle ID the caller falls back to its
/// own defaults (`HintModeController.defaultOptimisticDelay` /
/// `HintModeController.defaultFallbackDelay`).
protocol HintRefreshTimingPolicy {
    /// Returns app-specific delays for the given bundle identifier, or `nil` to
    /// use the caller's global defaults.
    func refreshDelays(for bundleIdentifier: String?) -> HintRefreshDelays?
}

// MARK: - Registry-backed implementation

/// Looks up hint refresh delays from registered per-app timing entries.
///
/// P4-S2 (`HintRefreshCoordinator`) will depend on this protocol rather than
/// on `DetectorRegistry`, keeping detector logic out of the hint refresh path.
@MainActor
final class AppTimingRegistry: HintRefreshTimingPolicy {

    static let shared = AppTimingRegistry()

    private var entries: [(bundleIds: Set<String>, delays: HintRefreshDelays)] = []

    private init() {
        registerDefaults()
    }

    func register(bundleIds: Set<String>, delays: HintRefreshDelays) {
        entries.append((bundleIds: bundleIds, delays: delays))
    }

    func refreshDelays(for bundleIdentifier: String?) -> HintRefreshDelays? {
        guard let id = bundleIdentifier else { return nil }
        return entries.first(where: { $0.bundleIds.contains(id) })?.delays
    }

    private func registerDefaults() {
        // Chromium browsers need longer delays due to their heavy rendering pipeline.
        register(
            bundleIds: [
                "com.google.Chrome",
                "com.google.Chrome.beta",
                "com.google.Chrome.dev",
                "com.google.Chrome.canary",
                "company.thebrowser.Browser",
                "com.microsoft.edgemac",
                "com.microsoft.edgemac.Beta",
                "com.microsoft.edgemac.Dev",
                "com.microsoft.edgemac.Canary",
                "com.brave.Browser",
                "com.brave.Browser.beta",
                "com.brave.Browser.dev",
                "com.brave.Browser.nightly",
            ],
            delays: HintRefreshDelays(optimistic: 0.200, fallback: 0.300)
        )
    }
}
