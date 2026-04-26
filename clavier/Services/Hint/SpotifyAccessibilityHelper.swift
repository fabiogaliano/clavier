//
//  SpotifyAccessibilityHelper.swift
//  clavier
//
//  Spotify is CEF (Chromium Embedded Framework), not Electron, so
//  `AXManualAccessibility` returns `.attributeUnsupported` and the
//  Electron-style runtime wake doesn't apply. The only mechanism that
//  populates Spotify's tree is launching it with
//  `--force-renderer-accessibility`. This helper offers two interaction
//  modes for that:
//
//  - **Manual** (default): on empty-tree detection, present a help
//    sheet whose primary action is a one-click terminate + relaunch
//    with the flag.
//  - **Auto** (opt-in via `spotifyAutoRelaunchEnabled`): observe
//    `NSWorkspace.didLaunchApplicationNotification` and silently
//    perform the same relaunch whenever Spotify launches without the
//    flag, paying ~2s extra startup latency for zero-click hint
//    coverage.
//
//  Background, dead ends, and full architecture: `docs/chromium-apps.md`.
//

import AppKit
import os

@MainActor
final class SpotifyAccessibilityHelper {

    static let shared = SpotifyAccessibilityHelper()

    static let spotifyBundleId = "com.spotify.client"

    /// One-shot per app-session dismissal. The user can permanently
    /// silence the prompt via `AppSettings.Keys.spotifyAccessibilityHelpEnabled`;
    /// this in-memory flag covers the milder "not now, but ask me again
    /// next time clavier launches" choice.
    private var dismissedThisSession = false

    /// Holds onto the help-sheet window so it isn't released the
    /// moment `presentIfApplicable` returns. NSWindow lifetime is
    /// managed by the caller — without this reference the window
    /// would deallocate immediately and never appear.
    private var activeSheet: SpotifyHelpSheetWindow?

    /// Workspace-launch observer for auto-relaunch mode. Attached
    /// once via `startMonitoring()` and lives for the app lifetime;
    /// the handler itself short-circuits when the auto-relaunch
    /// setting is off, so leaving the observer attached unconditionally
    /// costs almost nothing while letting users toggle the setting at
    /// runtime without the helper having to re-bind.
    private var workspaceLaunchObserver: NSObjectProtocol?

    /// Loop guard: timestamp of our last successful auto-relaunch.
    /// New `didLaunchApplicationNotification` events for Spotify are
    /// ignored within `autoRelaunchCooldown` of this time so we
    /// don't auto-relaunch the very Spotify process we just spawned.
    private var lastAutoRelaunchAt: Date?

    /// 10 seconds is comfortably longer than Spotify's launch + settle
    /// window (typically <3s), so the cooldown reliably covers the
    /// new pid's `didLaunch` notification without blocking legitimate
    /// user-initiated relaunches that happen minutes apart.
    private static let autoRelaunchCooldown: TimeInterval = 10

    private init() {}

    /// Inspect the just-completed discovery result and decide whether
    /// to handle it. Returns `true` when the helper took over the
    /// activation (caller should bail out of hint mode); `false` to
    /// let normal hint mode proceed.
    ///
    /// Auto-mode and the help sheet are independent settings: a user
    /// who silenced the help sheet but enabled auto-relaunch still
    /// gets the silent relaunch on hint hotkey.
    func presentIfApplicable(elements: [UIElement]) -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return false }
        guard frontmost.bundleIdentifier == Self.spotifyBundleId else { return false }
        // A populated tree means Spotify already has the flag.
        guard elements.count < 5 else { return false }

        if isAutoRelaunchEnabled {
            Logger.app.debug("SpotifyAccessibilityHelper: auto-mode triggering silent relaunch on hint hotkey")
            Task { @MainActor in
                do {
                    try await self.relaunchSpotifyWithFlag()
                    self.lastAutoRelaunchAt = Date()
                } catch {
                    Logger.app.warning("SpotifyAccessibilityHelper: silent relaunch failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            return true
        }

        guard isHelperEnabled else { return false }
        guard !dismissedThisSession else { return false }

        Logger.app.debug("SpotifyAccessibilityHelper: empty tree detected, presenting help sheet")
        showSheet()
        return true
    }

    /// Attach the `didLaunchApplicationNotification` observer that
    /// powers auto-relaunch. Called once from `AppDelegate` at app
    /// launch. The handler itself checks the user setting before
    /// doing anything, so the observer is cheap to leave attached.
    func startMonitoring() {
        guard workspaceLaunchObserver == nil else { return }
        workspaceLaunchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleAppLaunchNotification(note)
        }
    }

    /// Surface the help sheet from the menu bar / Preferences manually.
    /// Bypasses the empty-tree heuristic for users who want to consult
    /// the instructions before reproducing the empty state.
    func presentManually() {
        showSheet()
    }

    // MARK: - One-click relaunch

    /// Errors surfaced to the help-sheet UI.
    enum RelaunchError: Error, LocalizedError {
        case notInstalled
        case launchFailed(Error)
        case timedOut

        var errorDescription: String? {
            switch self {
            case .notInstalled:
                return "Spotify isn't installed at /Applications/Spotify.app."
            case .launchFailed(let underlying):
                return "Couldn't relaunch Spotify: \(underlying.localizedDescription)"
            case .timedOut:
                return "Spotify didn't quit in time. Try again, or quit it manually first."
            }
        }
    }

    static let forceAccessibilityArgument = "--force-renderer-accessibility"

    /// Quit any running Spotify instances, wait for them to exit, then
    /// launch a fresh process with `--force-renderer-accessibility`.
    ///
    /// `NSWorkspace.openApplication` only honours `OpenConfiguration.arguments`
    /// on a fresh launch — if Spotify is already running we'd just be
    /// activating the existing instance and the flag would be silently
    /// dropped. The terminate-and-wait dance is mandatory.
    func relaunchSpotifyWithFlag() async throws {
        guard let spotifyURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.spotifyBundleId) else {
            throw RelaunchError.notInstalled
        }

        // Politely terminate every running Spotify instance. Multiple
        // instances are vanishingly rare but cheap to handle.
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: Self.spotifyBundleId) {
            app.terminate()
        }

        // Poll for exit. Spotify normally exits within 200–500 ms; a
        // 3-second budget covers slow disks and pending IO without
        // making the user wait visibly long.
        let pollInterval: UInt64 = 100_000_000 // 100 ms
        let maxAttempts = 30
        for _ in 0..<maxAttempts {
            let stillAlive = NSRunningApplication
                .runningApplications(withBundleIdentifier: Self.spotifyBundleId)
                .contains { !$0.isTerminated }
            if !stillAlive { break }
            try await Task.sleep(nanoseconds: pollInterval)
        }

        // Force-quit any holdout. Spotify ignoring SIGTERM is rare but
        // possible (e.g. mid-network-write). Fall back rather than
        // returning a confusing "didn't quit" error.
        let holdouts = NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.spotifyBundleId)
            .filter { !$0.isTerminated }
        if !holdouts.isEmpty {
            holdouts.forEach { $0.forceTerminate() }
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        // Final guard: if anything is still alive, give up loudly
        // rather than racing LaunchServices into handing back the
        // dying instance.
        let finalAlive = NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.spotifyBundleId)
            .contains { !$0.isTerminated }
        if finalAlive {
            throw RelaunchError.timedOut
        }

        // Launch fresh with the flag.
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = [Self.forceAccessibilityArgument]
        config.activates = true
        // `addsToRecentItems = false` would be tempting but the
        // default Dock-launch behaviour also adds, so leaving the
        // default keeps user expectations consistent.

        do {
            _ = try await NSWorkspace.shared.openApplication(at: spotifyURL, configuration: config)
            Logger.app.debug("SpotifyAccessibilityHelper: relaunched with \(Self.forceAccessibilityArgument, privacy: .public)")
        } catch {
            throw RelaunchError.launchFailed(error)
        }
    }

    // MARK: - Internals

    private var isHelperEnabled: Bool {
        UserDefaults.standard.object(forKey: AppSettings.Keys.spotifyAccessibilityHelpEnabled) as? Bool
            ?? AppSettings.Defaults.spotifyAccessibilityHelpEnabled
    }

    private var isAutoRelaunchEnabled: Bool {
        UserDefaults.standard.object(forKey: AppSettings.Keys.spotifyAutoRelaunchEnabled) as? Bool
            ?? AppSettings.Defaults.spotifyAutoRelaunchEnabled
    }

    // MARK: - Auto-relaunch handling

    private func handleAppLaunchNotification(_ note: Notification) {
        guard isAutoRelaunchEnabled else { return }
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == Self.spotifyBundleId else { return }

        // Cooldown: skip the new Spotify process we just spawned and
        // any rapid bounce that would loop.
        if let last = lastAutoRelaunchAt,
           Date().timeIntervalSince(last) < Self.autoRelaunchCooldown {
            Logger.app.debug("SpotifyAccessibilityHelper: skipping auto-relaunch within cooldown window")
            return
        }

        Task { @MainActor in
            // Spotify takes ~1–2 seconds to populate its accessibility
            // tree after launch (when the flag is on). Wait long
            // enough that an empty tree at this point means "no flag,"
            // not "still loading."
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !app.isTerminated else { return }
            guard self.isAutoRelaunchEnabled else { return }

            guard self.isAXTreeLikelyDormant(pid: app.processIdentifier) else {
                Logger.app.debug("SpotifyAccessibilityHelper: Spotify launched with populated tree, no relaunch needed")
                return
            }

            do {
                Logger.app.debug("SpotifyAccessibilityHelper: auto-relaunching naked Spotify launch")
                try await self.relaunchSpotifyWithFlag()
                self.lastAutoRelaunchAt = Date()
            } catch {
                Logger.app.warning("SpotifyAccessibilityHelper: auto-relaunch failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Heuristic: count descendants of the first window up to depth 3
    /// and call the tree dormant when the count is below a threshold.
    /// The dormant Spotify shell has fewer than 15 nodes in that
    /// range (a deep chain of single-child `AXGroup`s plus the 3
    /// traffic-light buttons); a flagged tree easily clears the
    /// hundreds because the web content's AX nodes appear at shallow
    /// depth.
    ///
    /// We deliberately bias toward false negatives — when uncertain,
    /// don't relaunch. A mistaken kill of a populated Spotify costs
    /// the user audio; a missed dormancy detection only means the
    /// help sheet might still be useful, and they can always trigger
    /// hints manually.
    private func isAXTreeLikelyDormant(pid: pid_t) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement],
              let firstWindow = windows.first else {
            // No windows yet — could be mid-launch. Don't be aggressive.
            return false
        }

        let count = countDescendants(of: firstWindow, depth: 0, maxDepth: 3)
        Logger.app.debug("SpotifyAccessibilityHelper: dormancy probe found \(count, privacy: .public) descendants (threshold 30)")
        return count < 30
    }

    private func countDescendants(of element: AXUIElement, depth: Int, maxDepth: Int) -> Int {
        guard depth < maxDepth else { return 0 }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return 0
        }
        var count = children.count
        for child in children {
            count += countDescendants(of: child, depth: depth + 1, maxDepth: maxDepth)
        }
        return count
    }

    private func showSheet() {
        // If a sheet is already up, just bring it forward instead of
        // stacking duplicates.
        if let existing = activeSheet {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let sheet = SpotifyHelpSheetWindow(
            onDismissThisSession: { [weak self] in
                self?.dismissedThisSession = true
                self?.closeSheet()
            },
            onDismissPermanently: { [weak self] in
                UserDefaults.standard.set(false, forKey: AppSettings.Keys.spotifyAccessibilityHelpEnabled)
                self?.dismissedThisSession = true
                self?.closeSheet()
            },
            onClose: { [weak self] in
                self?.closeSheet()
            }
        )

        activeSheet = sheet
        sheet.center()
        sheet.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeSheet() {
        activeSheet?.close()
        activeSheet = nil
    }
}
