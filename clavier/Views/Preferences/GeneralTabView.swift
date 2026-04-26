import SwiftUI
import Carbon

struct GeneralTabView: View {
    @AppStorage(AppSettings.Keys.chromiumAccessibilityWakeEnabled)
    private var chromiumWakeEnabled: Bool = AppSettings.Defaults.chromiumAccessibilityWakeEnabled

    @AppStorage(AppSettings.Keys.spotifyAccessibilityHelpEnabled)
    private var spotifyHelpEnabled: Bool = AppSettings.Defaults.spotifyAccessibilityHelpEnabled

    @AppStorage(AppSettings.Keys.spotifyAutoRelaunchEnabled)
    private var spotifyAutoRelaunch: Bool = AppSettings.Defaults.spotifyAutoRelaunchEnabled

    @State private var accessibilityGranted: Bool = AXIsProcessTrusted()

    private let permissionTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Permissions") {
                Label(
                    accessibilityGranted ? "Accessibility access granted" : "Accessibility access not granted",
                    systemImage: accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(accessibilityGranted ? .green : .orange)
                if !accessibilityGranted {
                    Button("Open Accessibility Settings…") {
                        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
                    }
                }
            }
            .onReceive(permissionTimer) { _ in
                accessibilityGranted = AXIsProcessTrusted()
            }

            Section {
                Toggle("Wake accessibility in Chromium-based apps", isOn: $chromiumWakeEnabled)
                Text("Allows hints to work in Slack, Discord, Notion, and other Electron apps. Slightly increases their memory usage while enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Chromium app support")
            }

            Section {
                Toggle("Show help when hints don't work in Spotify", isOn: $spotifyHelpEnabled)

                if spotifyHelpEnabled {
                    Button("Show Spotify help now…") {
                        SpotifyAccessibilityHelper.shared.presentManually()
                    }
                }

                Toggle("Auto-relaunch Spotify on every launch", isOn: $spotifyAutoRelaunch)

                Text("Silently relaunches Spotify with accessibility enabled. Adds ~2 seconds to startup; Spotify uses slightly more memory with accessibility on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Spotify")
            }

            Section("About") {
                Text("clavier")
                    .font(.headline)
                Text("Navigate any macOS app without touching the mouse.")
                    .foregroundStyle(.secondary)
                Text("Version 1.0")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
