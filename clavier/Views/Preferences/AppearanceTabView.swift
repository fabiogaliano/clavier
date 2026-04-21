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

    var body: some View {
        Form {
            Section("Live Preview") {
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
                    borderOpacity: $hintBorderOpacity
                )
            }

            Section("Colors") {
                ColorPicker("Background Tint", selection: Binding(
                    get: { Color(hex: hintBackgroundHex) },
                    set: { hintBackgroundHex = $0.toHex() }
                ))

                ColorPicker("Border", selection: Binding(
                    get: { Color(hex: hintBorderHex) },
                    set: { hintBorderHex = $0.toHex() }
                ))

                ColorPicker("Text", selection: Binding(
                    get: { Color(hex: hintTextHex) },
                    set: { hintTextHex = $0.toHex() }
                ))

                ColorPicker("Highlight (Matched Letters)", selection: Binding(
                    get: { Color(hex: highlightTextHex) },
                    set: { highlightTextHex = $0.toHex() }
                ))
            }

            Section("Transparency") {
                VStack(alignment: .leading) {
                    Text("Background: \(Int(hintBackgroundOpacity * 100))%")
                    Slider(value: $hintBackgroundOpacity, in: 0...1, step: 0.05)
                }

                VStack(alignment: .leading) {
                    Text("Border: \(Int(hintBorderOpacity * 100))%")
                    Slider(value: $hintBorderOpacity, in: 0...1, step: 0.05)
                }
            }

            Section("Size") {
                Slider(value: $hintSize, in: 10...20, step: 1) {
                    Text("Hint Size: \(Int(hintSize))pt")
                }
            }

            Section("Positioning") {
                VStack(alignment: .leading) {
                    HStack {
                        HStack(spacing: 4) {
                            Text("Horizontal offset")
                            HelpButton(helpText: "Shift hints horizontally to avoid covering text. Negative values move left (over icons), positive values move right. Default: -25px positions hints over icons in list views.")
                        }
                        Spacer()
                    }
                    HStack {
                        Text("\(Int(hintHorizontalOffset))px")
                            .monospacedDigit()
                            .frame(width: 60, alignment: .trailing)
                        Slider(value: $hintHorizontalOffset, in: -200...200, step: 5)
                    }
                }
            }

            Section {
                Button("Reset to Defaults") {
                    hintBackgroundHex = AppSettings.Defaults.hintBackgroundHex
                    hintBorderHex = AppSettings.Defaults.hintBorderHex
                    hintTextHex = AppSettings.Defaults.hintTextHex
                    highlightTextHex = AppSettings.Defaults.highlightTextHex
                    hintBackgroundOpacity = AppSettings.Defaults.hintBackgroundOpacity
                    hintBorderOpacity = AppSettings.Defaults.hintBorderOpacity
                    hintSize = AppSettings.Defaults.hintSize
                    hintHorizontalOffset = AppSettings.Defaults.hintHorizontalOffset
                }
            }
        }
        .formStyle(.grouped)
    }
}
