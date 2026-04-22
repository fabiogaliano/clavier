import AppKit

/// Appearance snapshot read once per overlay activation or refresh.
struct HintStyle {
    let fontSize: CGFloat
    let backgroundColor: NSColor
    let borderColor: NSColor
    let textColor: NSColor
    let bgOpacity: CGFloat
    let bdrOpacity: CGFloat
    let horizontalOffset: CGFloat

    init() {
        let size = UserDefaults.standard.double(forKey: AppSettings.Keys.hintSize)
        fontSize = size > 0 ? CGFloat(size) : CGFloat(AppSettings.Defaults.hintSize)
        let bgHex = UserDefaults.standard.string(forKey: AppSettings.Keys.hintBackgroundHex) ?? AppSettings.Defaults.hintBackgroundHex
        let brHex = UserDefaults.standard.string(forKey: AppSettings.Keys.hintBorderHex) ?? AppSettings.Defaults.hintBorderHex
        let txHex = UserDefaults.standard.string(forKey: AppSettings.Keys.hintTextHex) ?? AppSettings.Defaults.hintTextHex
        backgroundColor = NSColor(hex: bgHex)
        borderColor = NSColor(hex: brHex)
        textColor = NSColor(hex: txHex)
        let bgOp = UserDefaults.standard.double(forKey: AppSettings.Keys.hintBackgroundOpacity)
        bgOpacity = bgOp > 0 ? CGFloat(bgOp) : CGFloat(AppSettings.Defaults.hintBackgroundOpacity)
        let bdOp = UserDefaults.standard.double(forKey: AppSettings.Keys.hintBorderOpacity)
        bdrOpacity = bdOp > 0 ? CGFloat(bdOp) : CGFloat(AppSettings.Defaults.hintBorderOpacity)
        horizontalOffset = CGFloat(UserDefaults.standard.double(forKey: AppSettings.Keys.hintHorizontalOffset))
    }
}

/// Creates individual hint label views (glass bubble + directional tail).
///
/// Tail orientation is decided by the engine's cluster direction when the
/// label belongs to a row/column cluster, and inferred from the final
/// placement rect otherwise.  The tail always points *toward* the target
/// element, on whichever of the four sides of the bubble faces it.
enum HintLabelRenderer {

    /// Length of the tail along its pointing axis (5 pt = tip-to-base
    /// distance).  The perpendicular axis — the width of the tail base —
    /// uses `tailBase`.
    static let tailLength: CGFloat = 5
    static let tailBase: CGFloat = 10

    private enum TailSide { case bottom, top, right, left, hidden }

    @MainActor
    static func createHintLabel(
        for hintedElement: HintedElement,
        style: HintStyle,
        engine: inout HintPlacementEngine
    ) -> NSView {
        let label = NSTextField(labelWithString: hintedElement.hint)
        label.font = NSFont.monospacedSystemFont(ofSize: style.fontSize, weight: .bold)
        label.textColor = style.textColor
        label.backgroundColor = .clear
        label.isBordered = false
        label.isBezeled = false
        label.drawsBackground = false
        label.alignment = .center
        label.wantsLayer = true
        label.shadow = {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.shadowBlurRadius = 2
            return shadow
        }()

        label.sizeToFit()

        let padding: CGFloat = 2
        let bubbleWidth = label.frame.width + padding * 2
        let bubbleHeight = label.frame.height + padding

        // Axis decision up-front: cluster direction dictates whether the
        // tail will extend horizontally (side-placement) or vertically
        // (above/below).  Non-cluster elements default to the vertical
        // axis — matches the common above-centered case.
        let expected = engine.expectedDirection(for: hintedElement.element)
        let horizontalAxis = (expected == .rightOf || expected == .leftOf)

        let outerWidth  = horizontalAxis ? (bubbleWidth + tailLength) : bubbleWidth
        let outerHeight = horizontalAxis ? bubbleHeight : (bubbleHeight + tailLength)

        let outer = NSView(frame: CGRect(x: 0, y: 0, width: outerWidth, height: outerHeight))
        outer.wantsLayer = true

        let hintFrame = engine.place(
            element: hintedElement.element,
            labelSize: CGSize(width: outerWidth, height: outerHeight),
            horizontalOffset: style.horizontalOffset
        )

        // Decide tail side from the real placement result.  On the chosen
        // axis, whichever side is opposite the element's midpoint gets
        // the tail (so it points back at the element).
        let el = ScreenGeometry.toWindowLocal(hintedElement.element.visibleFrame)
        let tailSide: TailSide = {
            if horizontalAxis {
                if hintFrame.midX >= el.maxX { return .left }
                if hintFrame.midX <= el.minX { return .right }
                return .hidden
            } else {
                if hintFrame.midY >= el.maxY { return .bottom }
                if hintFrame.midY <= el.minY { return .top }
                return .hidden
            }
        }()

        // Position bubble within outer container, leaving tail space on
        // whichever side the tail sits.
        let bubbleOrigin: CGPoint = {
            switch tailSide {
            case .bottom: return CGPoint(x: 0,          y: tailLength)
            case .top:    return CGPoint(x: 0,          y: 0)
            case .right:  return CGPoint(x: 0,          y: 0)
            case .left:   return CGPoint(x: tailLength, y: 0)
            case .hidden: return CGPoint(x: 0,          y: 0)
            }
        }()

        let glassContainer = NSVisualEffectView(
            frame: CGRect(origin: bubbleOrigin, size: CGSize(width: bubbleWidth, height: bubbleHeight))
        )
        glassContainer.material = .hudWindow
        glassContainer.blendingMode = .behindWindow
        glassContainer.state = .active
        glassContainer.wantsLayer = true
        glassContainer.layer?.cornerRadius = 3
        glassContainer.layer?.masksToBounds = true
        glassContainer.layer?.borderWidth = 1
        glassContainer.layer?.borderColor = style.borderColor.withAlphaComponent(style.bdrOpacity).cgColor

        let tintOverlay = NSView(frame: CGRect(x: 0, y: 0, width: bubbleWidth, height: bubbleHeight))
        tintOverlay.wantsLayer = true
        tintOverlay.layer?.backgroundColor = style.backgroundColor.withAlphaComponent(style.bgOpacity).cgColor

        label.frame = CGRect(x: 0, y: 0, width: bubbleWidth, height: bubbleHeight)

        glassContainer.addSubview(tintOverlay)
        glassContainer.addSubview(label)
        outer.addSubview(glassContainer)

        if tailSide != .hidden {
            let tail = makeTail(
                side: tailSide,
                fill: style.backgroundColor.withAlphaComponent(min(1, style.bgOpacity + 0.3)),
                stroke: style.borderColor.withAlphaComponent(style.bdrOpacity)
            )
            tail.frame = tailFrame(side: tailSide, outerSize: CGSize(width: outerWidth, height: outerHeight), bubbleSize: CGSize(width: bubbleWidth, height: bubbleHeight))
            outer.addSubview(tail)
        }

        outer.frame = hintFrame

        return outer
    }

    /// Position of the tail view within the outer container.  On the
    /// pointing axis it hugs the edge opposite the bubble; on the
    /// perpendicular axis it centres on the bubble's midpoint so the
    /// tip aligns with the element's centre.
    private static func tailFrame(side: TailSide, outerSize: CGSize, bubbleSize: CGSize) -> CGRect {
        switch side {
        case .bottom:
            return CGRect(x: (outerSize.width - tailBase) / 2, y: 0,
                          width: tailBase, height: tailLength)
        case .top:
            return CGRect(x: (outerSize.width - tailBase) / 2, y: bubbleSize.height,
                          width: tailBase, height: tailLength)
        case .right:
            return CGRect(x: bubbleSize.width, y: (outerSize.height - tailBase) / 2,
                          width: tailLength, height: tailBase)
        case .left:
            return CGRect(x: 0, y: (outerSize.height - tailBase) / 2,
                          width: tailLength, height: tailBase)
        case .hidden:
            return .zero
        }
    }

    /// Triangular tail with its tip on `side` of the view's own bounds.
    /// Fill + two angled strokes; the edge adjoining the bubble is left
    /// unstroked so it blends into the bubble's border without doubling.
    @MainActor
    private static func makeTail(side: TailSide, fill: NSColor, stroke: NSColor) -> NSView {
        let size: CGSize
        switch side {
        case .bottom, .top:
            size = CGSize(width: tailBase, height: tailLength)
        case .right, .left:
            size = CGSize(width: tailLength, height: tailBase)
        case .hidden:
            size = .zero
        }

        let view = NSView(frame: CGRect(origin: .zero, size: size))
        view.wantsLayer = true

        // Tip and the two base points depend on which side the tail
        // points toward.  In AppKit coordinates (y-up), .bottom means
        // "tip at y=0" and .top means "tip at y=height".
        let tip: CGPoint
        let baseA: CGPoint
        let baseB: CGPoint
        switch side {
        case .bottom:
            tip   = CGPoint(x: size.width / 2, y: 0)
            baseA = CGPoint(x: 0,              y: size.height)
            baseB = CGPoint(x: size.width,     y: size.height)
        case .top:
            tip   = CGPoint(x: size.width / 2, y: size.height)
            baseA = CGPoint(x: 0,              y: 0)
            baseB = CGPoint(x: size.width,     y: 0)
        case .right:
            tip   = CGPoint(x: size.width, y: size.height / 2)
            baseA = CGPoint(x: 0,          y: 0)
            baseB = CGPoint(x: 0,          y: size.height)
        case .left:
            tip   = CGPoint(x: 0,          y: size.height / 2)
            baseA = CGPoint(x: size.width, y: 0)
            baseB = CGPoint(x: size.width, y: size.height)
        case .hidden:
            return view
        }

        let fillPath = CGMutablePath()
        fillPath.move(to: baseA)
        fillPath.addLine(to: tip)
        fillPath.addLine(to: baseB)
        fillPath.closeSubpath()

        let fillLayer = CAShapeLayer()
        fillLayer.path = fillPath
        fillLayer.fillColor = fill.cgColor
        fillLayer.strokeColor = NSColor.clear.cgColor
        view.layer?.addSublayer(fillLayer)

        let strokeA = CGMutablePath()
        strokeA.move(to: baseA)
        strokeA.addLine(to: tip)
        let strokeB = CGMutablePath()
        strokeB.move(to: tip)
        strokeB.addLine(to: baseB)
        for path in [strokeA, strokeB] {
            let layer = CAShapeLayer()
            layer.path = path
            layer.strokeColor = stroke.cgColor
            layer.fillColor = NSColor.clear.cgColor
            layer.lineWidth = 1
            view.layer?.addSublayer(layer)
        }

        return view
    }
}
