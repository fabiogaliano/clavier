import SwiftUI

struct AppearanceTabView: View {
    @AppStorage(AppSettings.Keys.hintBackgroundHex) private var hintBackgroundHex: String = AppSettings.Defaults.hintBackgroundHex
    @AppStorage(AppSettings.Keys.hintBorderHex) private var hintBorderHex: String = AppSettings.Defaults.hintBorderHex
    @AppStorage(AppSettings.Keys.hintTextHex) private var hintTextHex: String = AppSettings.Defaults.hintTextHex
    @AppStorage(AppSettings.Keys.highlightTextHex) private var highlightTextHex: String = AppSettings.Defaults.highlightTextHex
    @AppStorage(AppSettings.Keys.hintBackgroundOpacity) private var hintBackgroundOpacity: Double = AppSettings.Defaults.hintBackgroundOpacity
    @AppStorage(AppSettings.Keys.hintBorderOpacity) private var hintBorderOpacity: Double = AppSettings.Defaults.hintBorderOpacity
    @AppStorage(AppSettings.Keys.hintSize) private var hintSize: Double = AppSettings.Defaults.hintSize
    @AppStorage(AppSettings.Keys.hintHorizontalOffset) private var hintHorizontalOffset: Double = AppSettings.Defaults.hintHorizontalOffset
    @AppStorage(AppSettings.Keys.showHintTail) private var showHintTail: Bool = AppSettings.Defaults.showHintTail
    @AppStorage(AppSettings.Keys.useSystemAccentColor) private var useSystemAccent: Bool = AppSettings.Defaults.useSystemAccentColor
    @AppStorage(AppSettings.Keys.hintPaddingX) private var hintPaddingX: Double = AppSettings.Defaults.hintPaddingX
    @AppStorage(AppSettings.Keys.hintPaddingY) private var hintPaddingY: Double = AppSettings.Defaults.hintPaddingY

    @AppStorage(AppSettings.Keys.scrollBackgroundHex) private var scrollBackgroundHex: String = AppSettings.Defaults.scrollBackgroundHex
    @AppStorage(AppSettings.Keys.scrollBorderHex) private var scrollBorderHex: String = AppSettings.Defaults.scrollBorderHex
    @AppStorage(AppSettings.Keys.scrollTextHex) private var scrollTextHex: String = AppSettings.Defaults.scrollTextHex
    @AppStorage(AppSettings.Keys.scrollBackgroundOpacity) private var scrollBackgroundOpacity: Double = AppSettings.Defaults.scrollBackgroundOpacity
    @AppStorage(AppSettings.Keys.scrollBorderOpacity) private var scrollBorderOpacity: Double = AppSettings.Defaults.scrollBorderOpacity
    @AppStorage(AppSettings.Keys.scrollHintSize) private var scrollHintSize: Double = AppSettings.Defaults.scrollHintSize

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $useSystemAccent) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Use system accent color")
                            Text("Overrides custom colours for hints and scroll areas.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "paintpalette")
                            .foregroundStyle(.tint)
                    }
                }
            }

            Section("Hint Preview") {
                HintPreviewView(
                    hintText: "AJ",
                    backgroundColor: Binding(
                        get: { Color(hex: hintBackgroundHex) },
                        set: { hintBackgroundHex = $0.toHex() }
                    ),
                    borderColor: Binding(
                        get: { Color(hex: hintBorderHex) },
                        set: { hintBorderHex = $0.toHex() }
                    ),
                    textColor: Binding(
                        get: { Color(hex: hintTextHex) },
                        set: { hintTextHex = $0.toHex() }
                    ),
                    highlightColor: Binding(
                        get: { Color(hex: highlightTextHex) },
                        set: { highlightTextHex = $0.toHex() }
                    ),
                    fontSize: $hintSize,
                    backgroundOpacity: $hintBackgroundOpacity,
                    borderOpacity: $hintBorderOpacity,
                    showTail: $showHintTail,
                    useSystemAccent: $useSystemAccent,
                    paddingX: $hintPaddingX,
                    paddingY: $hintPaddingY
                )
                .listRowInsets(EdgeInsets())
            }

            Section("Hint Appearance") {
                Toggle(isOn: $showHintTail) {
                    Label("Show tail pointing to element", systemImage: "arrow.up.right")
                }

                ColorPicker("Background tint", selection: Binding(
                    get: { Color(hex: hintBackgroundHex) },
                    set: { hintBackgroundHex = $0.toHex() }
                ))
                .disabled(useSystemAccent)

                ColorPicker("Border", selection: Binding(
                    get: { Color(hex: hintBorderHex) },
                    set: { hintBorderHex = $0.toHex() }
                ))
                .disabled(useSystemAccent)

                ColorPicker("Text", selection: Binding(
                    get: { Color(hex: hintTextHex) },
                    set: { hintTextHex = $0.toHex() }
                ))

                ColorPicker("Matched prefix", selection: Binding(
                    get: { Color(hex: highlightTextHex) },
                    set: { highlightTextHex = $0.toHex() }
                ))

                VStack(alignment: .leading, spacing: 4) {
                    LabeledSliderValue(title: "Background opacity", value: hintBackgroundOpacity, format: .percent)
                    Slider(value: $hintBackgroundOpacity, in: 0...1, step: 0.05)
                }

                VStack(alignment: .leading, spacing: 4) {
                    LabeledSliderValue(title: "Border opacity", value: hintBorderOpacity, format: .percent)
                    Slider(value: $hintBorderOpacity, in: 0...1, step: 0.05)
                }

                VStack(alignment: .leading, spacing: 4) {
                    LabeledSliderValue(title: "Font size", value: hintSize, format: .points)
                    Slider(value: $hintSize, in: 10...20, step: 1)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Horizontal padding")
                        HelpButton(helpText: "Space between the hint text and the left/right edges of the bubble. Lower values make the bubble more compact — useful when hints overlap.")
                        Spacer()
                        Text("\(Int(hintPaddingX))px")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $hintPaddingX, in: 0...10, step: 1)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Vertical padding")
                        HelpButton(helpText: "Space between the hint text and the top/bottom edges of the bubble. 0 is the tightest the font metrics allow.")
                        Spacer()
                        Text("\(Int(hintPaddingY))px")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $hintPaddingY, in: 0...8, step: 1)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Horizontal offset")
                        HelpButton(helpText: "Shift hints horizontally to avoid covering text. Negative values move left (over icons), positive values move right. Default: -25px positions hints over icons in list views.")
                        Spacer()
                        Text("\(Int(hintHorizontalOffset))px")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $hintHorizontalOffset, in: -200...200, step: 5)
                }
            }

            Section("Scroll Area Appearance") {
                ColorPicker("Background tint", selection: Binding(
                    get: { Color(hex: scrollBackgroundHex) },
                    set: { scrollBackgroundHex = $0.toHex() }
                ))
                .disabled(useSystemAccent)

                ColorPicker("Border", selection: Binding(
                    get: { Color(hex: scrollBorderHex) },
                    set: { scrollBorderHex = $0.toHex() }
                ))
                .disabled(useSystemAccent)

                ColorPicker("Text", selection: Binding(
                    get: { Color(hex: scrollTextHex) },
                    set: { scrollTextHex = $0.toHex() }
                ))

                VStack(alignment: .leading, spacing: 4) {
                    LabeledSliderValue(title: "Background opacity", value: scrollBackgroundOpacity, format: .percent)
                    Slider(value: $scrollBackgroundOpacity, in: 0...1, step: 0.05)
                }

                VStack(alignment: .leading, spacing: 4) {
                    LabeledSliderValue(title: "Border opacity", value: scrollBorderOpacity, format: .percent)
                    Slider(value: $scrollBorderOpacity, in: 0...1, step: 0.05)
                }

                VStack(alignment: .leading, spacing: 4) {
                    LabeledSliderValue(title: "Font size", value: scrollHintSize, format: .points)
                    Slider(value: $scrollHintSize, in: 10...22, step: 1)
                }
            }

            Section {
                Button(role: .destructive) {
                    resetToDefaults()
                } label: {
                    Label("Reset all appearance settings", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func resetToDefaults() {
        hintBackgroundHex = AppSettings.Defaults.hintBackgroundHex
        hintBorderHex = AppSettings.Defaults.hintBorderHex
        hintTextHex = AppSettings.Defaults.hintTextHex
        highlightTextHex = AppSettings.Defaults.highlightTextHex
        hintBackgroundOpacity = AppSettings.Defaults.hintBackgroundOpacity
        hintBorderOpacity = AppSettings.Defaults.hintBorderOpacity
        hintSize = AppSettings.Defaults.hintSize
        hintHorizontalOffset = AppSettings.Defaults.hintHorizontalOffset
        showHintTail = AppSettings.Defaults.showHintTail
        useSystemAccent = AppSettings.Defaults.useSystemAccentColor
        hintPaddingX = AppSettings.Defaults.hintPaddingX
        hintPaddingY = AppSettings.Defaults.hintPaddingY
        scrollBackgroundHex = AppSettings.Defaults.scrollBackgroundHex
        scrollBorderHex = AppSettings.Defaults.scrollBorderHex
        scrollTextHex = AppSettings.Defaults.scrollTextHex
        scrollBackgroundOpacity = AppSettings.Defaults.scrollBackgroundOpacity
        scrollBorderOpacity = AppSettings.Defaults.scrollBorderOpacity
        scrollHintSize = AppSettings.Defaults.scrollHintSize
    }
}

/// Small title row that shows a live numeric value alongside its label.
/// Extracted so the Appearance tab doesn't repeat eight identical HStacks.
private struct LabeledSliderValue: View {
    enum Format { case percent, points }

    let title: String
    let value: Double
    let format: Format

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(formatted)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private var formatted: String {
        switch format {
        case .percent: return "\(Int(value * 100))%"
        case .points: return "\(Int(value))pt"
        }
    }
}
