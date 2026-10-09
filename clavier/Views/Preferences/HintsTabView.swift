import SwiftUI

struct HintsTabView: View {
    @AppStorage(AppSettings.Keys.hintShortcutKeyCode) private var hintShortcutKeyCode: Int = AppSettings.Defaults.hintShortcutKeyCode
    @AppStorage(AppSettings.Keys.hintShortcutModifiers) private var hintShortcutModifiers: Int = AppSettings.Defaults.hintShortcutModifiers
    @AppStorage(AppSettings.Keys.hintCharacters) private var hintCharacters: String = AppSettings.Defaults.hintCharacters
    @AppStorage(AppSettings.Keys.textSearchEnabled) private var textSearchEnabled: Bool = AppSettings.Defaults.textSearchEnabled
    @AppStorage(AppSettings.Keys.minSearchCharacters) private var minSearchCharacters: Int = AppSettings.Defaults.minSearchCharacters
    @AppStorage(AppSettings.Keys.manualRefreshTrigger) private var manualRefreshTrigger: String = AppSettings.Defaults.manualRefreshTrigger
    @AppStorage(AppSettings.Keys.hideHintsPrefix) private var hideHintsPrefix: String = AppSettings.Defaults.hideHintsPrefix
    @AppStorage(AppSettings.Keys.continuousClickMode) private var continuousClickMode: Bool = AppSettings.Defaults.continuousClickMode
    @AppStorage(AppSettings.Keys.autoHintDeactivation) private var autoHintDeactivation: Bool = AppSettings.Defaults.autoHintDeactivation
    @AppStorage(AppSettings.Keys.hintDeactivationDelay) private var hintDeactivationDelay: Double = AppSettings.Defaults.hintDeactivationDelay
    @AppStorage(AppSettings.Keys.hintSystemChrome) private var hintSystemChrome: Bool = AppSettings.Defaults.hintSystemChrome

    var body: some View {
        Form {
            Section("Shortcut") {
                HStack {
                    Text("Activation shortcut")
                    Spacer()
                    ShortcutRecorderView(
                        keyCode: $hintShortcutKeyCode,
                        modifiers: $hintShortcutModifiers
                    )
                }
                Text("ESC: clear search then exit · Option: clear search")
                    .foregroundStyle(.secondary)
                Toggle("Also hint the menu bar, status items and Dock", isOn: $hintSystemChrome)
            }

            Section("Hint Characters") {
                HStack {
                    Text("Alphabet")
                    Spacer()
                    TextField("", text: $hintCharacters)
                        .frame(width: 120)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .onChange(of: hintCharacters) { _, newValue in
                            let cleaned = AppSettings.sanitizeHintCharacters(newValue)
                            if cleaned != newValue { hintCharacters = cleaned }
                        }
                }
                caption("Keys used to build hints. \(hintCharacters.count) chars = \(hintCharacters.count * hintCharacters.count) two-letter combos.")
            }

            Section("Continuous mode") {
                Text("Press \(Text(hintShortcutDisplay).font(.system(.body, design: .monospaced)).bold()) twice — the second press keeps hints open after each click")

                Toggle("Start every session continuous", isOn: $continuousClickMode)

                Toggle("Exit after inactivity", isOn: $autoHintDeactivation)
                HStack {
                    Slider(value: $hintDeactivationDelay, in: 5...30, step: 0.5)
                    Text("\(String(format: "%.1f", hintDeactivationDelay))s")
                        .monospacedDigit()
                        .frame(width: 50, alignment: .trailing)
                }
                .disabled(!autoHintDeactivation)
            }

            Section("Search") {
                Toggle("Enable text search", isOn: $textSearchEnabled)
                caption("Type an element's text to click it without its hint code.")

                if textSearchEnabled {
                    HStack {
                        Text("Minimum characters")
                        Spacer()
                        Stepper("\(minSearchCharacters)", value: $minSearchCharacters, in: 1...5)
                            .frame(width: 80)
                    }
                    caption("Search starts after this many characters and clicks when one match remains.")
                }
            }

            Section {
                DisclosureGroup("Advanced") {
                    HStack {
                        Text("Manual refresh trigger")
                        Spacer()
                        TextField("rr", text: $manualRefreshTrigger)
                            .frame(width: 60)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.center)
                            .font(.system(.body, design: .monospaced))
                            .onChange(of: manualRefreshTrigger) { _, newValue in
                                let cleaned = AppSettings.sanitizeManualRefreshTrigger(newValue)
                                if cleaned != newValue { manualRefreshTrigger = cleaned }
                            }
                    }
                    caption("Type this to re-scan the window when hints are stale.")

                    HStack {
                        Text("Hide labels prefix")
                        Spacer()
                        TextField(">", text: $hideHintsPrefix)
                            .frame(width: 60)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.center)
                            .font(.system(.body, design: .monospaced))
                            .onChange(of: hideHintsPrefix) { _, newValue in
                                let cleaned = AppSettings.sanitizeHideHintsPrefix(newValue)
                                if cleaned != newValue { hideHintsPrefix = cleaned }
                            }
                    }
                    caption("Type this first to hide labels and search only. Leave blank to disable.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var hintShortcutDisplay: String {
        KeymapUtilities.formatShortcut(keyCode: hintShortcutKeyCode, modifiers: hintShortcutModifiers)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
