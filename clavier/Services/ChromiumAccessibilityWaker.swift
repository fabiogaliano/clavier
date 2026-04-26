//
//  ChromiumAccessibilityWaker.swift
//  clavier
//
//  Wakes the dormant accessibility tree of Electron-based apps by setting
//  the private `AXManualAccessibility` attribute on the application AX
//  element.
//
//  ## Why this exists
//
//  Chromium-based apps (Electron) ship with their internal accessibility
//  tree disabled by default — exposing it costs CPU/memory on every DOM
//  mutation, so they wait for an a11y client to declare interest. macOS
//  provides a private hint attribute, `AXManualAccessibility`, that
//  external accessibility tools write to the *application* AX element to
//  flip Blink's `BrowserAccessibilityManagerMac` from "ignore" into "full
//  tree" mode. Once set, Chromium populates the tree within a few hundred
//  milliseconds and clavier's normal walker can find the actual UI.
//
//  Reference: introduced in Electron PR #10305 to replace the older
//  `AXEnhancedUserInterface` attribute (which has window-positioning
//  side effects when set externally — see Vimac issue #78).
//
//  ## What this does NOT solve
//
//  `AXManualAccessibility` is an **Electron** addition. CEF (Chromium
//  Embedded Framework) apps — notably Spotify — do not implement it.
//  For those, the only working mechanism is launching the app with
//  `--force-renderer-accessibility` at process start, which is a separate
//  user-side action documented in `SpotifyAccessibilityHelper`.
//
//  ## Design constraints
//
//  - Idempotent per pid: once a pid is woken we don't re-wake on every
//    discovery pass. The `Set<pid_t>` cache is invalidated when the
//    target app terminates so a re-launched process is woken again.
//  - Allow-list driven: only known Chromium/Electron bundle ids are
//    woken. Adding the attribute to a non-Chromium app is a no-op
//    (macOS routes the value into the void), but reading the bundle id
//    once is faster than always issuing the AX write.
//  - Honors a runtime toggle. When disabled, this becomes a no-op so
//    perf-conscious users can opt out without rebuilding.
//

import AppKit
import os

@MainActor
final class ChromiumAccessibilityWaker {

    static let shared = ChromiumAccessibilityWaker()

    /// Private CFString attribute Chromium/Electron observe on the
    /// application element. Not exported in the public AX headers, but
    /// stable since Electron PR #10305 (2017) and used by every macOS
    /// keyboard navigation tool that supports Electron apps.
    private static let manualAccessibilityAttribute = "AXManualAccessibility" as CFString

    /// Bundle identifiers known to ship as Electron and respond to
    /// `AXManualAccessibility`. Matches are case-sensitive — these are
    /// the values returned by `NSRunningApplication.bundleIdentifier`.
    private static let knownChromiumBundleIds: Set<String> = [
        "com.tinyspeck.slackmacgap",          // Slack
        "com.legcord.legcord",                // Legcord
        "com.hnc.Discord",                    // Discord
        "com.hnc.Discord.canary",
        "com.hnc.Discord.ptb",
        "notion.id",                          // Notion
        "com.figma.Desktop",                  // Figma desktop
        "com.linear.LinearDesktop",           // Linear
        "md.obsidian",                        // Obsidian
        "com.1password.1password",            // 1Password 8
        "com.microsoft.teams2",               // Microsoft Teams (new)
        "com.microsoft.teams",                // Microsoft Teams (legacy)
        "net.whatsapp.WhatsApp",              // WhatsApp Desktop
        "com.github.GitHubClient",            // GitHub Desktop
        "com.todesktop.230313mzl4w4u92",      // Cursor
        "com.exafunction.windsurf",           // Windsurf
        "com.electron.chatgpt",               // ChatGPT desktop
        "com.openai.chat",                    // ChatGPT (alt id)
        "com.anthropic.claudefordesktop",     // Claude desktop
        // NOTE: Spotify (com.spotify.client) is intentionally excluded —
        // it's CEF, not Electron, and `AXManualAccessibility` returns
        // `.attributeUnsupported` there. CEF activation is tracked
        // separately; see `docs/chromium-apps.md` Track B.
    ]

    /// pids we've already poked. Cleared on app-termination notifications
    /// from `AppDelegate` so a relaunched process is re-woken on the
    /// fresh pid.
    private var wokenPids: Set<pid_t> = []

    private init() {}

    // MARK: - Public API

    /// Outcome of a wake attempt. Callers care about this because a
    /// fresh wake means Chromium is still populating its tree —
    /// `AccessibilityService` uses that signal to decide whether a
    /// brief settle delay is warranted before walking.
    enum WakeOutcome {
        /// Not a known Chromium app, or the feature is disabled.
        case skipped
        /// pid was already woken earlier in this session — tree should
        /// already be populated, no wait needed.
        case alreadyWoken
        /// Just now wrote `AXManualAccessibility` for this pid. Tree
        /// population is in flight; brief settle wait recommended.
        case freshlyWoken
    }

    /// Wake the AX tree of `app` if it is a known Chromium/Electron app
    /// and the user-facing toggle is enabled. Idempotent per pid.
    @discardableResult
    func wakeIfNeeded(_ app: NSRunningApplication) -> WakeOutcome {
        guard isWakeEnabled else { return .skipped }
        guard let bundleId = app.bundleIdentifier else { return .skipped }
        guard isKnownChromiumApp(bundleId: bundleId) else { return .skipped }

        let pid = app.processIdentifier
        if wokenPids.contains(pid) {
            return .alreadyWoken
        }

        performWake(pid: pid, bundleId: bundleId)
        wokenPids.insert(pid)
        return .freshlyWoken
    }

    /// Convenience for `AccessibilityService` which already has a pid in
    /// hand and would otherwise have to re-resolve the running-app
    /// instance from `NSWorkspace`.
    @discardableResult
    func wakeIfNeeded(pid: pid_t, bundleId: String?) -> WakeOutcome {
        guard isWakeEnabled else { return .skipped }
        guard let bundleId, isKnownChromiumApp(bundleId: bundleId) else { return .skipped }
        if wokenPids.contains(pid) {
            return .alreadyWoken
        }
        performWake(pid: pid, bundleId: bundleId)
        wokenPids.insert(pid)
        return .freshlyWoken
    }

    /// Drop a pid from the woken set. Called from `AppDelegate` when an
    /// app terminates so its replacement (next launch, new pid) is woken
    /// fresh.
    func forgetPid(_ pid: pid_t) {
        wokenPids.remove(pid)
    }

    /// Whether a given bundle id is on the wake allow-list. Used by
    /// `SpotifyAccessibilityHelper` and the empty-tree retry heuristic
    /// to gate behaviour without re-stating the list.
    static func isKnownChromiumApp(bundleId: String) -> Bool {
        knownChromiumBundleIds.contains(bundleId)
    }

    // MARK: - Internals

    private func isKnownChromiumApp(bundleId: String) -> Bool {
        Self.isKnownChromiumApp(bundleId: bundleId)
    }

    private var isWakeEnabled: Bool {
        // Default is true; only honour an explicit `false`.
        UserDefaults.standard.object(forKey: AppSettings.Keys.chromiumAccessibilityWakeEnabled) as? Bool
            ?? AppSettings.Defaults.chromiumAccessibilityWakeEnabled
    }

    private func performWake(pid: pid_t, bundleId: String) {
        let appElement = AXUIElementCreateApplication(pid)
        let result = AXUIElementSetAttributeValue(
            appElement,
            Self.manualAccessibilityAttribute,
            kCFBooleanTrue
        )

        switch result {
        case .success:
            Logger.accessibility.debug(
                "ChromiumAccessibilityWaker: woke \(bundleId, privacy: .public) (pid \(pid, privacy: .public))"
            )
        case .attributeUnsupported:
            // Expected for CEF-based apps (Spotify) — the attribute
            // isn't in their settable set. Silent at debug to avoid
            // noise on every Spotify activation.
            Logger.accessibility.debug(
                "ChromiumAccessibilityWaker: attribute unsupported for \(bundleId, privacy: .public) (likely CEF, not Electron)"
            )
        default:
            Logger.accessibility.warning(
                "ChromiumAccessibilityWaker: AXUIElementSetAttributeValue failed (\(result.rawValue, privacy: .public)) for \(bundleId, privacy: .public)"
            )
        }
    }
}
