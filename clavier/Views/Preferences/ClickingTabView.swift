import SwiftUI

struct ClickingTabView: View {
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

    var body: some View {
        Form {
            Section("Hotkey") {
                HStack {
                    Text("Activate Hint Mode")
                    Spacer()
                    ShortcutRecorderView(
                        keyCode: $hintShortcutKeyCode,
                        modifiers: $hintShortcutModifiers
                    )
                }
                Text("ESC - Cancel | Option - Clear search | Ctrl+Enter - Right-click")
                    .foregroundStyle(.secondary)
            }

            Section("Hint Characters") {
                HStack {
                    HStack(spacing: 4) {
                        Text("Characters")
                        HelpButton(helpText: "Characters used to generate hints. Default is home row keys (asdfhjkl). With 8 characters, you get 64 two-letter combinations.")
                    }
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
                Text("Current: \(hintCharacters.count) chars = \(hintCharacters.count * hintCharacters.count) two-letter combos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Text Search") {
                HStack {
                    HStack(spacing: 4) {
                        Text("Enable text search")
                        HelpButton(helpText: "Search UI elements by their text content. Type element names to find and click them.")
                    }
                    Spacer()
                    Toggle("", isOn: $textSearchEnabled)
                }

                if textSearchEnabled {
                    HStack {
                        HStack(spacing: 4) {
                            Text("Minimum characters")
                            HelpButton(helpText: "Number of characters required before text search activates. Auto-clicks when exactly one match remains.")
                        }
                        Spacer()
                        Stepper("\(minSearchCharacters)", value: $minSearchCharacters, in: 1...5)
                            .frame(width: 80)
                    }
                }

                HStack {
                    HStack(spacing: 4) {
                        Text("Manual refresh trigger")
                        HelpButton(helpText: "Type this text to manually refresh hints. Useful if UI changed but hints didn't update. Works in both normal and continuous mode.")
                    }
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
                .padding(.top, 4)

                HStack {
                    HStack(spacing: 4) {
                        Text("Hide-labels prefix")
                        HelpButton(helpText: "Single punctuation character. Typing it as the first filter character hides hint labels while the rest of the query searches normally. Leave blank to disable.")
                    }
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
            }

            Section("Behavior") {
                Toggle("Continuous Click Mode", isOn: $continuousClickMode)
                Text("When enabled, hint mode stays active after clicking. Continue clicking elements until you press ESC.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if continuousClickMode {
                    HStack {
                        HStack(spacing: 4) {
                            Text("Auto-deactivation")
                            HelpButton(helpText: "Automatically exit continuous mode after a period of inactivity.")
                        }
                        Spacer()
                        Toggle("", isOn: $autoHintDeactivation)
                    }

                    if autoHintDeactivation {
                        HStack {
                            HStack(spacing: 4) {
                                Text("Deactivation delay")
                                HelpButton(helpText: "How long to wait before automatically exiting continuous mode.")
                            }
                            Spacer()
                            Text("\(String(format: "%.1f", hintDeactivationDelay))s")
                                .monospacedDigit()
                                .frame(width: 50)
                        }
                        Slider(value: $hintDeactivationDelay, in: 5...30, step: 0.5)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
