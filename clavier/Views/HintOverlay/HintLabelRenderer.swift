import AppKit
import CoreText

/// Creates individual hint label views (glass bubble + optional directional tail).
///
/// Tail orientation is decided by the engine's cluster direction when the
/// label belongs to a row/column cluster, and inferred from the final
/// placement rect otherwise. The tail always points *toward* the target
/// element, on whichever of the four sides of the bubble faces it.
enum HintLabelRenderer {

    /// Length of the tail along its pointing axis (5 pt = tip-to-base
    /// distance). The perpendicular axis — the width of the tail base —
    /// uses `tailBase`.
    static let tailLength: CGFloat = 5
    static let tailBase: CGFloat = 10

    /// Corner radius of the glass bubble. Chosen to read as a soft pill on
    /// typical 12–16pt hints without clashing with the tail's base width.
    static let bubbleCornerRadius: CGFloat = 6

    enum TailSide { case bottom, top, right, left, hidden }

    private struct Metrics {
        let labelSize: CGSize
        let bubbleSize: CGSize
        let outerSize: CGSize
    }

    @MainActor
    static func createHintLabel(
        for hintedElement: HintedElement,
        style: OverlayStyle,
        engine: inout HintPlacementEngine
    ) -> NSView {
        let label = makeTextLabel(text: hintedElement.hint, style: style)

        let expected = engine.expectedDirection(for: hintedElement.element)
        let horizontalAxis = (expected == .rightOf || expected == .leftOf)
        let metrics = measure(label: label, text: hintedElement.hint, style: style, horizontalAxis: horizontalAxis)

        let hintFrame = engine.place(
            element: hintedElement.element,
            labelSize: metrics.outerSize,
            horizontalOffset: style.horizontalOffset
        )

        let el = ScreenGeometry.toWindowLocal(hintedElement.element.visibleFrame)
        let tailSide: TailSide = {
            guard style.showTail else { return .hidden }
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

        let outer = assemble(label: label, metrics: metrics, style: style, tailSide: tailSide)
        outer.frame = hintFrame
        return outer
    }

    /// The same bubble `createHintLabel` produces, unplaced and with a fixed
    /// tail side.  Preferences renders its preview through this so the
    /// preview cannot drift from the live overlay.
    @MainActor
    static func createStandaloneLabel(
        text: String,
        typedPrefix: String,
        style: OverlayStyle,
        tailSide: TailSide
    ) -> NSView {
        let label = makeTextLabel(text: text, style: style)
        let horizontalAxis = (tailSide == .left || tailSide == .right)
        let metrics = measure(label: label, text: text, style: style, horizontalAxis: horizontalAxis)
        if !typedPrefix.isEmpty {
            MatchHighlightRenderer.highlightPrefix(in: label, prefix: typedPrefix, hint: text, style: style)
        }
        return assemble(
            label: label,
            metrics: metrics,
            style: style,
            tailSide: style.showTail ? tailSide : .hidden
        )
    }

    @MainActor
    private static func makeTextLabel(text: String, style: OverlayStyle) -> NSTextField {
        let label = NSTextField(labelWithString: text)
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
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.shadowBlurRadius = 2
            return shadow
        }()
        label.sizeToFit()
        return label
    }

    @MainActor
    private static func measure(
        label: NSTextField,
        text: String,
        style: OverlayStyle,
        horizontalAxis: Bool
    ) -> Metrics {
        // `labelW` includes the font's side-bearing (the whitespace the font
        // reserves around each glyph). `inkW` is the visible glyph rect from
        // Core Text — measurably narrower on monospaced bold. Sizing the
        // bubble from `inkW` + padding makes the bubble hug the letters; the
        // surrounding side-bearing whitespace is clipped by the glass
        // container's corner-radius mask.
        let labelW = label.frame.width
        let labelH = label.frame.height
        let inkW = glyphInkWidth(text: text, font: label.font ?? NSFont.monospacedSystemFont(ofSize: style.fontSize, weight: .bold))
        let bubbleWidth = ceil(inkW) + style.paddingX * 2
        let bubbleHeight = labelH + style.paddingY * 2

        let tailSpace = style.showTail ? tailLength : 0
        let outerWidth  = horizontalAxis ? (bubbleWidth + tailSpace) : bubbleWidth
        let outerHeight = horizontalAxis ? bubbleHeight : (bubbleHeight + tailSpace)

        return Metrics(
            labelSize: CGSize(width: labelW, height: labelH),
            bubbleSize: CGSize(width: bubbleWidth, height: bubbleHeight),
            outerSize: CGSize(width: outerWidth, height: outerHeight)
        )
    }

    @MainActor
    private static func assemble(
        label: NSTextField,
        metrics: Metrics,
        style: OverlayStyle,
        tailSide: TailSide
    ) -> NSView {
        let bubbleWidth = metrics.bubbleSize.width
        let bubbleHeight = metrics.bubbleSize.height
        let labelW = metrics.labelSize.width
        let labelH = metrics.labelSize.height

        let outer = NSView(frame: CGRect(origin: .zero, size: metrics.outerSize))
        outer.wantsLayer = true

        let bubbleOrigin: CGPoint = {
            switch tailSide {
            case .bottom: return CGPoint(x: 0,           y: tailLength)
            case .top:    return CGPoint(x: 0,           y: 0)
            case .right:  return CGPoint(x: 0,           y: 0)
            case .left:   return CGPoint(x: tailLength,  y: 0)
            case .hidden: return CGPoint(x: 0,           y: 0)
            }
        }()

        let glass = GlassBackdrop.make(
            size: metrics.bubbleSize,
            cornerRadius: bubbleCornerRadius,
            tintColor: style.backgroundColor,
            tintAlpha: style.backgroundOpacity,
            borderAlpha: style.borderOpacity,
            shadow: false
        )
        glass.frame.origin = bubbleOrigin

        // Label keeps its side-bearing-inclusive width so text rendering is
        // correct; its x is negative when side-bearing exceeds paddingX so
        // the invisible margins hang outside the bubble and get clipped.
        label.frame = CGRect(
            x: (bubbleWidth - labelW) / 2,
            y: (bubbleHeight - labelH) / 2,
            width: labelW,
            height: labelH
        )
        glass.addSubview(label)
        outer.addSubview(glass)

        if tailSide != .hidden {
            // Tail uses the bubble's exact tint + alpha so it reads as "the
            // same material" rather than a darker companion piece.
            let tail = makeTail(
                side: tailSide,
                fill: style.backgroundColor.withAlphaComponent(style.backgroundOpacity),
                stroke: NSColor.white.withAlphaComponent(style.borderOpacity * 0.35)
            )
            tail.frame = tailFrame(
                side: tailSide,
                outerSize: metrics.outerSize,
                bubbleSize: metrics.bubbleSize
            )
            outer.addSubview(tail)
        }

        // Soft outer shadow on the outer view so the tail participates in the
        // drop-shadow (if we put it on `glass` the tail would be shadowless).
        outer.layer?.masksToBounds = false
        outer.layer?.shadowColor = NSColor.black.cgColor
        outer.layer?.shadowOpacity = 0.2
        outer.layer?.shadowRadius = 5
        outer.layer?.shadowOffset = CGSize(width: 0, height: -1)

        return outer
    }

    /// Measures the tight visual width of the rendered glyphs, ignoring the
    /// font's side-bearing. Using `.useGlyphPathBounds` gives the actual ink
    /// rect; monospaced bold returns a value 5–6pt narrower than the
    /// advance-width frame `sizeToFit()` reports.
    private static func glyphInkWidth(text: String, font: NSFont) -> CGFloat {
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        return bounds.width
    }

    /// Position of the tail view within the outer container.
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
            layer.lineWidth = 0.75
            view.layer?.addSublayer(layer)
        }

        return view
    }
}
