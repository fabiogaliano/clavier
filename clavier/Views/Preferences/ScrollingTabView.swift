import SwiftUI

struct ScrollingTabView: View {
    @AppStorage(AppSettings.Keys.scrollShortcutKeyCode) private var scrollShortcutKeyCode: Int = AppSettings.Defaults.scrollShortcutKeyCode
    @AppStorage(AppSettings.Keys.scrollShortcutModifiers) private var scrollShortcutModifiers: Int = AppSettings.Defaults.scrollShortcutModifiers
    @AppStorage(AppSettings.Keys.scrollArrowMode) private var scrollArrowMode: ScrollArrowMode = AppSettings.Defaults.scrollArrowMode
    @AppStorage(AppSettings.Keys.showScrollAreaNumbers) private var showScrollAreaNumbers: Bool = AppSettings.Defaults.showScrollAreaNumbers
    @AppStorage(AppSettings.Keys.scrollKeys) private var scrollKeys: String = AppSettings.Defaults.scrollKeys
    @AppStorage(AppSettings.Keys.scrollSpeed) private var scrollSpeed: Double = AppSettings.Defaults.scrollSpeed
    @AppStorage(AppSettings.Keys.dashSpeed) private var dashSpeed: Double = AppSettings.Defaults.dashSpeed
    @AppStorage(AppSettings.Keys.autoScrollDeactivation) private var autoScrollDeactivation: Bool = AppSettings.Defaults.autoScrollDeactivation
    @AppStorage(AppSettings.Keys.scrollDeactivationDelay) private var scrollDeactivationDelay: Double = AppSettings.Defaults.scrollDeactivationDelay

    var body: some View {
        Form {
            Section("Controls") {
                HStack {
                    Text("Shortcut")
                    Spacer()
                    ShortcutRecorderView(
                        keyCode: $scrollShortcutKeyCode,
                        modifiers: $scrollShortcutModifiers
                    )
                }

                HStack {
                    HStack(spacing: 4) {
                        Text("Arrow keys")
                        HelpButton(helpText: "Controls what arrow keys do in scroll mode. 'Select' switches between scroll areas, 'Scroll' scrolls the active area directly.")
                    }
                    Spacer()
                    Picker("", selection: $scrollArrowMode) {
                        Text("Select").tag(ScrollArrowMode.select)
                        Text("Scroll").tag(ScrollArrowMode.scroll)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }

                HStack {
                    HStack(spacing: 4) {
                        Text("Show scroll area numbers")
                        HelpButton(helpText: "Display numbered hints over scrollable areas for quick selection.")
                    }
                    Spacer()
                    Toggle("", isOn: $showScrollAreaNumbers)
                }

                HStack {
                    HStack(spacing: 4) {
                        Text("Scroll keys")
                        HelpButton(helpText: "Four keys for left/down/up/right scrolling. Default is hjkl (vim-style).")
                    }
                    Spacer()
                    TextField("", text: $scrollKeys)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .onChange(of: scrollKeys) { _, newValue in
                            let cleaned = AppSettings.sanitizeScrollKeys(newValue)
                            if cleaned != newValue { scrollKeys = cleaned }
                        }
                }
            }

            Section("Speed") {
                VStack(alignment: .leading) {
                    Text("Scroll speed")
                    HStack {
                        Image(systemName: "tortoise")
                            .foregroundStyle(.secondary)
                        Slider(value: $scrollSpeed, in: 1...10, step: 1)
                        Image(systemName: "hare")
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading) {
                    HStack(spacing: 4) {
                        Text("Dash speed")
                        HelpButton(helpText: "Speed when holding Shift while scrolling for faster movement.")
                    }
                    HStack {
                        Image(systemName: "tortoise")
                            .foregroundStyle(.secondary)
                        Slider(value: $dashSpeed, in: 1...10, step: 1)
                        Image(systemName: "hare")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Deactivation") {
                HStack {
                    HStack(spacing: 4) {
                        Text("Automatic deactivation")
                        HelpButton(helpText: "Automatically exit scroll mode after a period of inactivity.")
                    }
                    Spacer()
                    Toggle("", isOn: $autoScrollDeactivation)
                }

                if autoScrollDeactivation {
                    HStack {
                        HStack(spacing: 4) {
                            Text("Deactivation delay")
                            HelpButton(helpText: "How long to wait before automatically exiting scroll mode.")
                        }
                        Spacer()
                        Text("\(String(format: "%.1f", scrollDeactivationDelay))s")
                            .monospacedDigit()
                            .frame(width: 50)
                    }
                    Slider(value: $scrollDeactivationDelay, in: 1...30, step: 0.5)
                }
            }
        }
        .formStyle(.grouped)
    }
}
