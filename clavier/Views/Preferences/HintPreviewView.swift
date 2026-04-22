import SwiftUI
import AppKit

/// A faithful preview of the hint bubble — bridges the same `GlassBackdrop`
/// used by the live overlay so colour/opacity/tail changes here read exactly
/// the same way the user will see them on screen.
struct HintPreviewView: View {
    let hintText: String
    @Binding var backgroundColor: Color
    @Binding var borderColor: Color
    @Binding var textColor: Color
    @Binding var highlightColor: Color
    @Binding var fontSize: Double
    @Binding var backgroundOpacity: Double
    @Binding var borderOpacity: Double
    @Binding var showTail: Bool
    @Binding var useSystemAccent: Bool
    @Binding var paddingX: Double
    @Binding var paddingY: Double

    var body: some View {
        ZStack {
            // Textured backdrop so the glass has something to blur over —
            // otherwise the fallback reads as a flat tint against the Form.
            PreviewBackdrop()

            HintBubblePreview(
                hintText: hintText,
                backgroundColor: useSystemAccent ? Color.accentColor : backgroundColor,
                borderColor: useSystemAccent ? Color.accentColor : borderColor,
                textColor: textColor,
                highlightColor: highlightColor,
                fontSize: CGFloat(fontSize),
                backgroundOpacity: CGFloat(backgroundOpacity),
                borderOpacity: CGFloat(borderOpacity),
                showTail: showTail,
                paddingX: CGFloat(paddingX),
                paddingY: CGFloat(paddingY)
            )
        }
        .frame(height: 90)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct PreviewBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .systemBlue).opacity(0.22),
                Color(nsColor: .systemPurple).opacity(0.18),
                Color(nsColor: .systemPink).opacity(0.14)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct HintBubblePreview: View {
    let hintText: String
    let backgroundColor: Color
    let borderColor: Color
    let textColor: Color
    let highlightColor: Color
    let fontSize: CGFloat
    let backgroundOpacity: CGFloat
    let borderOpacity: CGFloat
    let showTail: Bool
    let paddingX: CGFloat
    let paddingY: CGFloat

    var body: some View {
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
        .padding(.horizontal, paddingX)
        .padding(.vertical, paddingY)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor.opacity(backgroundOpacity))
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(borderOpacity),
                                Color.white.opacity(borderOpacity * 0.25)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
            }
        )
        .overlay(alignment: .bottom) {
            if showTail {
                TailShape()
                    .fill(backgroundColor.opacity(backgroundOpacity))
                    .frame(width: 10, height: 5)
                    .offset(y: 5)
            }
        }
        .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: -1)
    }
}

private struct TailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.height))
        p.addLine(to: CGPoint(x: rect.width, y: 0))
        p.closeSubpath()
        return p
    }
}
