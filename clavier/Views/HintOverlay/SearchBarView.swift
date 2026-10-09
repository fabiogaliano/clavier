import AppKit

/// The glass capsule that carries hint mode's chrome: a leading icon, the
/// typed query or a status message, and trailing segments (match count,
/// continuous countdown, help).
///
/// Lays out a `HintScene.Bar` and nothing more; what to show is decided by
/// the scene.
@MainActor
final class SearchBarView: NSView {
    static let height: CGFloat = 40
    private static let leadingInset: CGFloat = 14
    /// Segments are capsules inside a capsule; a tighter end inset keeps
    /// their curve concentric with the bar's.
    private static let segmentTrailingInset: CGFloat = 6
    private static let textTrailingInset: CGFloat = 16
    private static let gap: CGFloat = 10
    /// Keeps the bar from twitching narrower and wider on every keystroke of
    /// a short query.
    private static let minimumWidth: CGFloat = 180
    private static let iconSize: CGFloat = 18

    var onHelp: (() -> Void)?

    private var glass: NSView?
    private let iconView = NSImageView()
    private let spinner = NSProgressIndicator()
    private let primaryText = NSTextField(labelWithString: "")
    private let detailText = NSTextField(labelWithString: "")
    private let caret = NSView()
    private let countSegment = SegmentView()
    private let continuousSegment = SegmentView()
    private let ring = CountdownRingView()
    private let helpSegment = SegmentView()

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.minimumWidth, height: Self.height))
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 12
        layer?.shadowOffset = CGSize(width: 0, height: -8)

        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = NSColor.labelColor.withAlphaComponent(0.8)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        for field in [primaryText, detailText] {
            field.backgroundColor = .clear
            field.isBordered = false
            field.drawsBackground = false
            field.lineBreakMode = .byTruncatingTail
        }

        caret.wantsLayer = true
        caret.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.7).cgColor

        continuousSegment.accessory = ring
        helpSegment.onClick = { [weak self] in self?.onHelp?() }

        for view in [iconView, spinner, primaryText, detailText, caret, countSegment, continuousSegment, helpSegment] {
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Lay out `bar`; the view resizes itself and returns its new size so the
    /// host can recentre it.
    @discardableResult
    func apply(_ bar: HintScene.Bar) -> CGSize {
        let midY = Self.height / 2
        var x = Self.leadingInset

        applyIcon(bar.icon)
        let iconFrame = CGRect(x: x, y: midY - Self.iconSize / 2, width: Self.iconSize, height: Self.iconSize)
        iconView.frame = iconFrame
        spinner.frame = iconFrame.insetBy(dx: 1, dy: 1)
        x = iconFrame.maxX + Self.gap

        x = applyBody(bar.body, startingAt: x, midY: midY)

        countSegment.isHidden = true
        continuousSegment.isHidden = true
        helpSegment.isHidden = true
        var placed: [SegmentView] = []
        for segment in bar.segments {
            let view: SegmentView
            switch segment {
            case .count(let style):
                view = countSegment
                view.configure(
                    text: style.labelText,
                    font: .monospacedSystemFont(ofSize: 12, weight: .medium),
                    color: style.labelColor,
                    background: NSColor.labelColor.withAlphaComponent(0.08)
                )
            case .continuous(let countdown):
                view = continuousSegment
                ring.update(countdown)
                view.configure(
                    text: countdown.map { "\($0.secondsLeft) s" } ?? "",
                    font: .monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                    color: .systemGreen,
                    background: NSColor.systemGreen.withAlphaComponent(0.18)
                )
            case .help(let title):
                view = helpSegment
                view.configure(
                    text: title,
                    font: .systemFont(ofSize: 12, weight: .medium),
                    color: .systemOrange,
                    background: NSColor.systemOrange.withAlphaComponent(0.18)
                )
            }
            view.isHidden = false
            view.frame.origin = CGPoint(x: x, y: midY - view.frame.height / 2)
            x = view.frame.maxX + Self.gap
            placed.append(view)
        }
        x -= Self.gap
        x += bar.segments.isEmpty ? Self.textTrailingInset : Self.segmentTrailingInset

        let width = max(ceil(x), Self.minimumWidth)
        // Segments sit at the trailing end even when the minimum width adds
        // slack, so their capsules stay concentric with the bar's.
        let slack = width - ceil(x)
        for view in placed {
            view.frame.origin.x += slack
        }
        if frame.width != width || glass == nil {
            setFrameSize(CGSize(width: width, height: Self.height))
            rebuildGlass()
        }
        return frame.size
    }

    private func applyIcon(_ icon: HintScene.Bar.Icon) {
        let symbol: String?
        switch icon {
        case .keyboard: symbol = "keyboard"
        case .search: symbol = "magnifyingglass"
        case .nothingToClick: symbol = "circle.slash"
        case .progress: symbol = nil
        }
        if let symbol {
            spinner.stopAnimation(nil)
            iconView.isHidden = false
            iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
        } else {
            iconView.isHidden = true
            spinner.startAnimation(nil)
        }
    }

    private func applyBody(_ body: HintScene.Bar.Body, startingAt start: CGFloat, midY: CGFloat) -> CGFloat {
        var x = start
        caret.isHidden = true
        detailText.isHidden = true

        switch body {
        case .query(let text):
            primaryText.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
            primaryText.textColor = .labelColor
            primaryText.stringValue = text
        case .placeholder(let text):
            primaryText.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
            primaryText.textColor = NSColor.labelColor.withAlphaComponent(0.5)
            primaryText.stringValue = text
        case .message(let text, _):
            primaryText.font = .systemFont(ofSize: 14)
            primaryText.textColor = .labelColor
            primaryText.stringValue = text
        }
        primaryText.sizeToFit()
        primaryText.frame.origin = CGPoint(x: x, y: (midY - primaryText.frame.height / 2).rounded())
        x = primaryText.frame.maxX

        if case .query = body {
            caret.isHidden = false
            caret.frame = CGRect(x: x + 1, y: midY - 8, width: 1.5, height: 16)
            startCaretBlink()
            x = caret.frame.maxX
        }

        if case .message(_, let detail?) = body {
            detailText.isHidden = false
            detailText.font = .systemFont(ofSize: 12)
            detailText.textColor = NSColor.labelColor.withAlphaComponent(0.55)
            detailText.stringValue = detail
            detailText.sizeToFit()
            detailText.frame.origin = CGPoint(x: x + 8, y: (midY - detailText.frame.height / 2).rounded())
            x = detailText.frame.maxX
        }

        return x + Self.gap
    }

    private func startCaretBlink() {
        guard let layer = caret.layer, layer.animation(forKey: "blink") == nil,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let blink = CAKeyframeAnimation(keyPath: "opacity")
        blink.values = [1, 0]
        blink.keyTimes = [0, 0.5]
        blink.calculationMode = .discrete
        blink.duration = 1.1
        blink.repeatCount = .infinity
        layer.add(blink, forKey: "blink")
    }

    private func rebuildGlass() {
        glass?.removeFromSuperview()
        let backdrop = GlassBackdrop.make(
            size: bounds.size,
            cornerRadius: Self.height / 2,
            tintColor: .windowBackgroundColor,
            tintAlpha: 0.38,
            borderAlpha: 0,
            material: .popover,
            rim: .specular(top: 0.45, bottom: 0.06),
            shadow: false
        )
        addSubview(backdrop, positioned: .below, relativeTo: nil)
        glass = backdrop
        layer?.shadowPath = CGPath(
            roundedRect: bounds,
            cornerWidth: Self.height / 2,
            cornerHeight: Self.height / 2,
            transform: nil
        )
    }
}

/// A capsule inside the bar: optional leading accessory plus a short label.
@MainActor
private final class SegmentView: NSView {
    static let height: CGFloat = 28
    private static let padding: CGFloat = 10
    private static let accessoryGap: CGFloat = 6

    var accessory: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let accessory { addSubview(accessory) }
        }
    }
    var onClick: (() -> Void)?

    private let label = NSTextField(labelWithString: "")
    private var rim: CALayer?

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.height, height: Self.height))
        wantsLayer = true
        layer?.cornerRadius = Self.height / 2
        label.backgroundColor = .clear
        label.isBordered = false
        label.drawsBackground = false
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(text: String, font: NSFont, color: NSColor, background: NSColor) {
        label.font = font
        label.textColor = color
        label.stringValue = text
        label.isHidden = text.isEmpty
        label.sizeToFit()
        layer?.backgroundColor = background.cgColor
        (accessory as? CountdownRingView)?.tint = color

        var x = Self.padding
        if let accessory {
            accessory.frame.origin = CGPoint(x: x, y: (Self.height - accessory.frame.height) / 2)
            x = accessory.frame.maxX + (text.isEmpty ? 0 : Self.accessoryGap)
        }
        if !text.isEmpty {
            label.frame.origin = CGPoint(x: x, y: ((Self.height - label.frame.height) / 2).rounded())
            x = label.frame.maxX
        }
        let width = ceil(x + Self.padding)
        if frame.width != width || rim == nil {
            setFrameSize(CGSize(width: width, height: Self.height))
            rim?.removeFromSuperlayer()
            GlassBackdrop.addSpecularRim(to: self, cornerRadius: Self.height / 2, top: 0.25, bottom: 0)
            rim = layer?.sublayers?.last
        }
    }

    // The bar never becomes key, so the first click has to act.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { onClick != nil }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard onClick != nil, !isHidden, frame.contains(point) else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

/// The ∞ glyph inside a ring that drains with continuous mode's
/// auto-deactivation timer.
@MainActor
private final class CountdownRingView: NSView {
    private static let size: CGFloat = 16
    private static let lineWidth: CGFloat = 1.6

    var tint: NSColor = .systemGreen {
        didSet {
            track.strokeColor = tint.withAlphaComponent(0.25).cgColor
            progress.strokeColor = tint.cgColor
            glyph.textColor = tint
        }
    }

    private let track = CAShapeLayer()
    private let progress = CAShapeLayer()
    private let glyph = NSTextField(labelWithString: "∞")
    private var shown: HintScene.Countdown?

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.size, height: Self.size))
        wantsLayer = true

        // Start at 12 o'clock and run clockwise (y-up layer space), so the
        // ring empties the way a clock hand sweeps.
        let center = CGPoint(x: Self.size / 2, y: Self.size / 2)
        let path = CGMutablePath()
        path.addArc(center: center, radius: 6.5, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        for shape in [track, progress] {
            shape.frame = bounds
            shape.path = path
            shape.fillColor = nil
            shape.lineWidth = Self.lineWidth
            shape.lineCap = .round
            layer?.addSublayer(shape)
        }

        glyph.font = .systemFont(ofSize: 10, weight: .semibold)
        glyph.alignment = .center
        glyph.backgroundColor = .clear
        glyph.isBordered = false
        glyph.drawsBackground = false
        glyph.sizeToFit()
        glyph.frame = CGRect(
            x: (Self.size - glyph.frame.width) / 2,
            y: ((Self.size - glyph.frame.height) / 2).rounded(),
            width: glyph.frame.width,
            height: glyph.frame.height
        )
        addSubview(glyph)
        tint = .systemGreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ countdown: HintScene.Countdown?) {
        defer { shown = countdown }
        guard let countdown else {
            track.isHidden = true
            progress.isHidden = true
            return
        }
        track.isHidden = false
        progress.isHidden = false
        guard countdown != shown else { return }

        // Ticks arrive once a second with the whole seconds left; draining
        // toward the next tick's value over that second keeps the ring
        // moving continuously and lets it reach empty exactly at
        // deactivation instead of a second late.
        let from = countdown.fraction
        let to = HintScene.Countdown(
            secondsLeft: countdown.secondsLeft - 1,
            totalSeconds: countdown.totalSeconds
        ).fraction

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progress.strokeEnd = to
        CATransaction.commit()

        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            progress.strokeEnd = from
            return
        }
        let drain = CABasicAnimation(keyPath: "strokeEnd")
        drain.fromValue = from
        drain.toValue = to
        drain.duration = 1
        drain.timingFunction = CAMediaTimingFunction(name: .linear)
        progress.add(drain, forKey: "drain")
    }
}

/// Small borderless panel that hosts the bar above the overlay.
///
/// A window of its own, rather than a subview of the desktop-sized overlay,
/// so the bar alone can take a click (the "Why?" segment) while the overlay
/// keeps ignoring the mouse everywhere else.
@MainActor
final class HintBarPanel: NSPanel {
    /// Room for the bar's outer shadow, which a tight window would clip.
    private static let shadowMargin: CGFloat = 32
    /// Distance from the bottom of the main display.
    private static let bottomOffset: CGFloat = 80

    let barView = SearchBarView()

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let root = NSView()
        root.wantsLayer = true
        contentView = root
        barView.isHidden = true
        root.addSubview(barView)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The bar is anchored to the main display because it is global chrome
    /// the user types into, regardless of which display the hints are on.
    func apply(_ bar: HintScene.Bar) {
        let size = barView.apply(bar)
        let screen = NSScreen.main?.frame ?? .zero
        let margin = Self.shadowMargin
        let frame = CGRect(
            x: (screen.midX - size.width / 2 - margin).rounded(),
            y: screen.minY + Self.bottomOffset - margin,
            width: size.width + margin * 2,
            height: size.height + margin * 2
        )
        if self.frame != frame {
            setFrame(frame, display: false)
        }
        barView.setFrameOrigin(CGPoint(x: margin, y: margin))
        ignoresMouseEvents = !bar.segments.contains {
            if case .help = $0 { return true }
            return false
        }
    }

    func setBarVisible(_ visible: Bool) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard let layer = barView.layer else {
            barView.isHidden = !visible
            return
        }
        let fadingOut = layer.animation(forKey: "barDisappear") != nil
        if visible {
            guard barView.isHidden || fadingOut else { return }
        } else {
            guard !barView.isHidden, !fadingOut else { return }
        }
        layer.removeAnimation(forKey: "barDisappear")

        if visible {
            barView.isHidden = false
            barView.alphaValue = 1
            guard !reduceMotion else { return }

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1

            // AppKit pins a backing layer's anchor to its origin, so scale
            // about the centre explicitly or the bar grows out of its corner.
            let center = CGPoint(x: barView.bounds.midX, y: barView.bounds.midY)
            var from = CATransform3DMakeTranslation(center.x, center.y, 0)
            from = CATransform3DScale(from, 0.96, 0.96, 1)
            from = CATransform3DTranslate(from, -center.x, -center.y, 0)
            let scale = CABasicAnimation(keyPath: "transform")
            scale.fromValue = NSValue(caTransform3D: from)
            scale.toValue = NSValue(caTransform3D: CATransform3DIdentity)

            let group = CAAnimationGroup()
            group.animations = [fade, scale]
            group.duration = 0.12
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(group, forKey: "barAppear")
        } else {
            ignoresMouseEvents = true
            guard !reduceMotion else {
                barView.isHidden = true
                return
            }
            fadeOut(layer)
        }
    }

    /// Fade the bar out; the overlay calls this when the session ends.
    func dismissBar() {
        ignoresMouseEvents = true
        guard !barView.isHidden, let layer = barView.layer,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        fadeOut(layer)
    }

    private func fadeOut(_ layer: CALayer) {
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                guard let self, layer.animation(forKey: "barDisappear") == nil, self.barView.alphaValue == 0 else { return }
                self.barView.isHidden = true
                self.barView.alphaValue = 1
            }
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = layer.presentation()?.opacity ?? 1
        fade.toValue = 0
        fade.duration = 0.1
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        barView.alphaValue = 0
        layer.add(fade, forKey: "barDisappear")
        CATransaction.commit()
    }
}
