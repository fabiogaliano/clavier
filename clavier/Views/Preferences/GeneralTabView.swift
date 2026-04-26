import SwiftUI
import Carbon

struct GeneralTabView: View {
    @AppStorage(AppSettings.Keys.chromiumAccessibilityWakeEnabled)
    private var chromiumWakeEnabled: Bool = AppSettings.Defaults.chromiumAccessibilityWakeEnabled

    var body: some View {
        Form {
            Section("Permissions") {
                Button("Check Accessibility Permissions") {
                    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                    _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
                }
            }

            Section {
                Toggle("Wake accessibility in Chromium-based apps", isOn: $chromiumWakeEnabled)
                Text("""
                    Apps like Slack, Discord, Notion, Linear, Obsidian, 1Password, and Cursor are built on Electron, which keeps its accessibility tree dormant by default. clavier wakes it on activation so hints can target their UI.

                    While this is enabled, those apps maintain a live accessibility tree, which slightly increases their CPU and memory usage. Disable if you don't use clavier in Chromium-based apps and want to minimise impact.

                    Has no effect on Chrome, Arc, Edge, Brave, or VS Code — those manage their own accessibility tree.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Chromium app support")
            }

            Section("About") {
                Text("clavier - Keyboard Navigation for macOS")
                    .font(.headline)
                Text("Version 1.0")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
