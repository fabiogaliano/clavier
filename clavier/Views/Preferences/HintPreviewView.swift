import SwiftUI
import AppKit

/// Preview of a hint bubble mid-selection (first character typed), drawn by
/// the overlay's own `HintLabelRenderer` from the same `OverlayStyle` the
/// overlay loads, so the preview cannot drift from what appears on screen.
struct HintPreviewView: View {
    let token: String
    let style: OverlayStyle

    var body: some View {
        ZStack {
            // Textured backdrop so the tint has something to sit on rather
            // than a flat Form background.
            PreviewBackdrop()

            RenderedHintLabel(token: token, style: style)
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

private struct RenderedHintLabel: NSViewRepresentable {
    let token: String
    let style: OverlayStyle

    func makeNSView(context: Context) -> CenteringView {
        CenteringView()
    }

    func updateNSView(_ view: CenteringView, context: Context) {
        let label = HintLabelRenderer.createStandaloneLabel(
            text: token,
            typedPrefix: String(token.prefix(1)),
            style: style,
            tailSide: .bottom
        )
        view.setContent(label)
    }

    final class CenteringView: NSView {
        private var content: NSView?

        override var isFlipped: Bool { true }

        func setContent(_ view: NSView) {
            content?.removeFromSuperview()
            content = view
            addSubview(view)
            needsLayout = true
        }

        override func layout() {
            super.layout()
            guard let content else { return }
            content.setFrameOrigin(CGPoint(
                x: ((bounds.width - content.frame.width) / 2).rounded(),
                y: ((bounds.height - content.frame.height) / 2).rounded()
            ))
        }
    }
}
