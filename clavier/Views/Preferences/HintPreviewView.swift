import SwiftUI

struct HintPreviewView: View {
    let hintText: String
    @Binding var backgroundColor: Color
    @Binding var borderColor: Color
    @Binding var textColor: Color
    @Binding var highlightColor: Color
    @Binding var fontSize: Double
    @Binding var backgroundOpacity: Double
    @Binding var borderOpacity: Double

    var body: some View {
        HStack {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))

                RoundedRectangle(cornerRadius: 4)
                    .fill(backgroundColor.opacity(backgroundOpacity))

                RoundedRectangle(cornerRadius: 4)
                    .stroke(borderColor.opacity(borderOpacity), lineWidth: 1)

                HStack(spacing: 0) {
                    Text(String(hintText.prefix(1)))
                        .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                        .foregroundColor(highlightColor)

                    if hintText.count > 1 {
                        Text(String(hintText.dropFirst()))
                            .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                            .foregroundColor(textColor)
                    }
                }
                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: -1)
            }
            .frame(width: CGFloat(hintText.count) * fontSize * 0.8 + 16, height: fontSize + 8)
            Spacer()
        }
        .frame(height: 80)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}
