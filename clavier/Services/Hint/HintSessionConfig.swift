//
//  HintSessionConfig.swift
//  clavier
//
//  Settings snapshot taken once when a hint session activates.
//
//  Preferences can change mid-session; reading them once keeps a session's
//  behaviour (timer, starting mode, search rules) consistent from open to
//  close, and gives the timer and reducer explicit inputs.
//

import Foundation

struct HintSessionConfig {
    let autoDeactivation: Bool
    let deactivationDelay: TimeInterval
    let initialMode: HintSessionMode
    let inputContext: HintInputContext
    var hintsSystemChrome: Bool = AppSettings.Defaults.hintSystemChrome

    static let `default` = HintSessionConfig(
        autoDeactivation: AppSettings.Defaults.autoHintDeactivation,
        deactivationDelay: AppSettings.Defaults.hintDeactivationDelay,
        initialMode: AppSettings.Defaults.continuousClickMode ? .continuous : .oneShot,
        inputContext: HintInputContext(
            textSearchEnabled: AppSettings.Defaults.textSearchEnabled,
            minSearchChars: AppSettings.Defaults.minSearchCharacters,
            refreshTrigger: AppSettings.Defaults.manualRefreshTrigger
        )
    )

    static func load() -> HintSessionConfig {
        let defaults = UserDefaults.standard
        let delay = defaults.double(forKey: AppSettings.Keys.hintDeactivationDelay)
        return HintSessionConfig(
            autoDeactivation: defaults.bool(forKey: AppSettings.Keys.autoHintDeactivation),
            deactivationDelay: delay == 0 ? AppSettings.Defaults.hintDeactivationDelay : delay,
            initialMode: defaults.bool(forKey: AppSettings.Keys.continuousClickMode) ? .continuous : .oneShot,
            inputContext: HintInputContext(
                textSearchEnabled: defaults.bool(forKey: AppSettings.Keys.textSearchEnabled),
                minSearchChars: AppSettings.minSearchCharacters,
                refreshTrigger: AppSettings.manualRefreshTrigger,
                hidePrefix: AppSettings.hideHintsPrefix
            ),
            hintsSystemChrome: AppSettings.hintSystemChrome
        )
    }

    /// Inactivity timeout for a session in `mode`, or `nil` when none applies.
    /// One-shot sessions end on their click, so only continuous ones time out.
    func autoDeactivationDelay(for mode: HintSessionMode) -> TimeInterval? {
        guard mode == .continuous, autoDeactivation else { return nil }
        return deactivationDelay
    }
}
