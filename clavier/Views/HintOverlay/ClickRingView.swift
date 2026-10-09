import AppKit

/// Brief ring around the element a hint just clicked, confirming where the
/// click landed (most useful in continuous mode, where nothing else on
/// screen changes).
///
/// Each ring lives in its own tiny window so it outlives the hint overlay
/// when the click ends the session; the click itself never waits for it.
@MainActor
enum ClickRing {
    static let duration: CFTimeInterval = 0.18
    static let spread: CGFloat = 6

    /// Windows stay retained until their animation finishes.
    private static var live: [ObjectIdentifier: NSWindow] = [:]

    /// `frame` is in AppKit screen coordinates.
    static func show(around frame: CGRect, color: NSColor) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              frame.width > 0, frame.height > 0 else { return }

        let margin = spread + ClickRingView.lineWidth
        let window = NSWindow(
            contentRect: frame.insetBy(dx: -margin, dy: -margin),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let view = ClickRingView(frame: CGRect(origin: .zero, size: window.frame.size), margin: margin, color: color)
        window.contentView = view

        let key = ObjectIdentifier(window)
        live[key] = window
        window.orderFrontRegardless()
        view.play {
            window.orderOut(nil)
            live[key] = nil
        }
    }
}

@MainActor
final class ClickRingView: NSView {
    static let lineWidth: CGFloat = 2
    private static let cornerRadius: CGFloat = 6

    private let ring = CAShapeLayer()
    private let margin: CGFloat

    init(frame: CGRect, margin: CGFloat, color: NSColor) {
        self.margin = margin
        super.init(frame: frame)
        wantsLayer = true
        ring.frame = bounds
        ring.fillColor = nil
        ring.strokeColor = color.cgColor
        ring.lineWidth = Self.lineWidth
        ring.opacity = 0
        layer?.addSublayer(ring)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func play(completion: @escaping @MainActor () -> Void) {
        let target = bounds.insetBy(dx: margin, dy: margin)
        let start = path(around: target, outset: 0)
        let end = path(around: target, outset: ClickRing.spread)

        let grow = CABasicAnimation(keyPath: "path")
        grow.fromValue = start
        grow.toValue = end

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0

        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = ClickRing.duration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock {
            MainActor.assumeIsolated { completion() }
        }
        ring.path = end
        ring.add(group, forKey: "ring")
        CATransaction.commit()
    }

    private func path(around rect: CGRect, outset: CGFloat) -> CGPath {
        let r = rect.insetBy(dx: -outset, dy: -outset)
        let radius = min(Self.cornerRadius + outset, r.width / 2, r.height / 2)
        return CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
}
