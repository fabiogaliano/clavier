//
//  ChromiumAccessibilityWaker.swift
//  clavier
//
//  Enables dormant renderer accessibility in known Chromium-family apps.
//
//  Electron exposes the side-effect-free `AXManualAccessibility` attribute.
//  Standalone Chromium browsers instead expose `AXEnhancedUserInterface` on
//  the application root. The latter must never be written to an AXWindow:
//  window-scoped writes are what caused the window-manager regressions tracked
//  by Vimac issue #78.
//
//  CEF apps such as Spotify support neither runtime path. Spotify remains on
//  the launch-with-flag flow documented in `docs/chromium-apps.md`.
//

import AppKit
import os

@MainActor
final class ChromiumAccessibilityWaker {

    static let shared = ChromiumAccessibilityWaker()

    private static let manualAccessibilityAttribute = "AXManualAccessibility" as CFString
    private static let enhancedUserInterfaceAttribute = "AXEnhancedUserInterface" as CFString

    /// Standalone browsers that use Chromium's application-root enhanced-UI
    /// signal to enable renderer accessibility.
    static let knownBrowserBundleIds: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.dev",
        "com.google.Chrome.canary",
        "company.thebrowser.Browser",       // Arc
        "com.microsoft.edgemac",            // Edge
        "com.microsoft.edgemac.Beta",
        "com.microsoft.edgemac.Dev",
        "com.microsoft.edgemac.Canary",
        "com.brave.Browser",                // Brave
        "com.brave.Browser.beta",
        "com.brave.Browser.dev",
        "com.brave.Browser.nightly",
        "net.imput.helium"                  // Helium
    ]

    /// Electron apps that implement the narrower manual-accessibility signal.
    private static let knownElectronBundleIds: Set<String> = [
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
        "com.github.GitHubClient",             // GitHub Desktop
        "com.todesktop.230313mzl4w4u92",      // Cursor
        "com.exafunction.windsurf",            // Windsurf
        "com.electron.chatgpt",               // ChatGPT desktop
        "com.openai.chat",                    // ChatGPT (alternate id)
        "com.anthropic.claudefordesktop"      // Claude desktop
    ]

    private var wokenPids: Set<pid_t> = []

    private init() {}

    enum WakeOutcome: Equatable {
        case skipped
        case alreadyWoken
        case freshlyWoken
    }

    @discardableResult
    func wakeIfNeeded(_ app: NSRunningApplication) -> WakeOutcome {
        wakeIfNeeded(pid: app.processIdentifier, bundleId: app.bundleIdentifier)
    }

    @discardableResult
    func wakeIfNeeded(pid: pid_t, bundleId: String?) -> WakeOutcome {
        guard isWakeEnabled,
              let bundleId,
              Self.isKnownChromiumApp(bundleId: bundleId) else {
            return .skipped
        }
        if wokenPids.contains(pid) {
            return .alreadyWoken
        }

        let result = performWake(pid: pid, bundleId: bundleId)
        switch result {
        case .activated:
            wokenPids.insert(pid)
            return .freshlyWoken
        case .alreadyEnabled:
            wokenPids.insert(pid)
            return .alreadyWoken
        case .failed:
            return .skipped
        }
    }

    func forgetPid(_ pid: pid_t) {
        wokenPids.remove(pid)
    }

    static func isKnownChromiumApp(bundleId: String) -> Bool {
        knownBrowserBundleIds.contains(bundleId) || knownElectronBundleIds.contains(bundleId)
    }

    static func isKnownBrowser(bundleId: String?) -> Bool {
        bundleId.map(knownBrowserBundleIds.contains) ?? false
    }

    /// Chromium 151 on Helium changes the enhanced-UI value to true while
    /// returning `kAXErrorNotImplemented`. Read-back is therefore authoritative
    /// when the write result alone is inconclusive.
    static func enhancedWriteWasAccepted(writeResult: AXError, readBack: Bool?) -> Bool {
        writeResult == .success || readBack == true
    }

    private enum ActivationResult {
        case activated
        case alreadyEnabled
        case failed
    }

    private var isWakeEnabled: Bool {
        UserDefaults.standard.object(forKey: AppSettings.Keys.chromiumAccessibilityWakeEnabled) as? Bool
            ?? AppSettings.Defaults.chromiumAccessibilityWakeEnabled
    }

    private func performWake(pid: pid_t, bundleId: String) -> ActivationResult {
        let appElement = AXUIElementCreateApplication(pid)
        if Self.knownBrowserBundleIds.contains(bundleId) {
            return enableBrowser(appElement, pid: pid, bundleId: bundleId)
        }
        return enableElectron(appElement, pid: pid, bundleId: bundleId)
    }

    private func enableElectron(
        _ appElement: AXUIElement,
        pid: pid_t,
        bundleId: String
    ) -> ActivationResult {
        let result = AXUIElementSetAttributeValue(
            appElement,
            Self.manualAccessibilityAttribute,
            kCFBooleanTrue
        )
        guard result == .success else {
            Logger.accessibility.warning(
                "ChromiumAccessibilityWaker: AXManualAccessibility failed (\(result.rawValue, privacy: .public)) for \(bundleId, privacy: .public)"
            )
            return .failed
        }

        Logger.accessibility.debug(
            "ChromiumAccessibilityWaker: enabled Electron accessibility for \(bundleId, privacy: .public) (pid \(pid, privacy: .public))"
        )
        return .activated
    }

    private func enableBrowser(
        _ appElement: AXUIElement,
        pid: pid_t,
        bundleId: String
    ) -> ActivationResult {
        if readEnhancedUserInterface(from: appElement) == true {
            Logger.accessibility.debug(
                "ChromiumAccessibilityWaker: browser accessibility already enabled for \(bundleId, privacy: .public) (pid \(pid, privacy: .public))"
            )
            return .alreadyEnabled
        }

        let writeResult = AXUIElementSetAttributeValue(
            appElement,
            Self.enhancedUserInterfaceAttribute,
            kCFBooleanTrue
        )
        let readBack = readEnhancedUserInterface(from: appElement)
        guard Self.enhancedWriteWasAccepted(writeResult: writeResult, readBack: readBack) else {
            Logger.accessibility.warning(
                "ChromiumAccessibilityWaker: application-root AXEnhancedUserInterface failed (\(writeResult.rawValue, privacy: .public)) for \(bundleId, privacy: .public)"
            )
            return .failed
        }

        Logger.accessibility.debug(
            "ChromiumAccessibilityWaker: requested browser accessibility for \(bundleId, privacy: .public) (pid \(pid, privacy: .public), write \(writeResult.rawValue, privacy: .public))"
        )
        return .activated
    }

    private func readEnhancedUserInterface(from appElement: AXUIElement) -> Bool? {
        switch AXReader.bool(Self.enhancedUserInterfaceAttribute, of: appElement) {
        case .success(let enabled): return enabled
        case .failure: return nil
        }
    }
}
