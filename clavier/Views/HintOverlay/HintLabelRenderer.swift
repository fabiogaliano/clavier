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

    /// Uppercase monospaced glyphs crowd each other; a little tracking keeps
    /// pairs like "MW" from fusing.
    static let trackingPerPoint: CGFloat = 0.07

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
        let label = makeTextLabel(token: hintedElement.hint, typedPrefix: "", style: style)

        let expected = engine.expectedDirection(for: hintedElement.element)
        let horizontalAxis = (expected == .rightOf || expected == .leftOf)
        let metrics = measure(label: label, style: style, horizontalAxis: horizontalAxis)

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
        let label = makeTextLabel(token: text, typedPrefix: typedPrefix, style: style)
        let horizontalAxis = (tailSide == .left || tailSide == .right)
        let metrics = measure(label: label, style: style, horizontalAxis: horizontalAxis)
        return assemble(
            label: label,
            metrics: metrics,
            style: style,
            tailSide: style.showTail ? tailSide : .hidden
        )
    }

    /// Tokens are matched lowercase but drawn uppercase. The typed prefix
    /// is drawn at full strength and the rest dimmed, so the label reads as
    /// "you have typed this, press one of these next".
    static func attributedToken(_ token: String, typedPrefix: String, style: OverlayStyle) -> NSAttributedString {
        let display = token.uppercased()
        let font = labelFont(style)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let result = NSMutableAttributedString(string: display, attributes: [
            .font: font,
            .foregroundColor: style.remainderTextColor,
            .paragraphStyle: paragraph,
        ])
        let length = (display as NSString).length
        let prefixLength = min((typedPrefix.uppercased() as NSString).length, length)
        if prefixLength > 0 {
            result.addAttribute(.foregroundColor, value: style.highlightTextColor,
                                range: NSRange(location: 0, length: prefixLength))
        }
        // Tracking after the last glyph would push the text off-centre.
        if length > 1 {
            result.addAttribute(.kern, value: style.fontSize * trackingPerPoint,
                                range: NSRange(location: 0, length: length - 1))
        }
        return result
    }

    /// Redraws an existing label's text; used when a reused view gets a new
    /// token or the typed prefix changes.
    @MainActor
    static func applyToken(_ token: String, typedPrefix: String, to label: NSTextField, style: OverlayStyle) {
        label.attributedStringValue = attributedToken(token, typedPrefix: typedPrefix, style: style)
    }

    private static func labelFont(_ style: OverlayStyle) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: style.fontSize, weight: .semibold)
    }

    @MainActor
    private static func makeTextLabel(token: String, typedPrefix: String, style: OverlayStyle) -> NSTextField {
        let label = NSTextField(labelWithAttributedString: attributedToken(token, typedPrefix: typedPrefix, style: style))
        label.backgroundColor = .clear
        label.isBordered = false
        label.isBezeled = false
        label.drawsBackground = false
        label.alignment = .center
        label.wantsLayer = true
        label.sizeToFit()
        return label
    }

    @MainActor
    private static func measure(
        label: NSTextField,
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
        let inkW = glyphInkWidth(label.attributedStringValue)
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
            cornerRadius: style.labelCornerRadius,
            tintColor: style.backgroundColor,
            tintAlpha: style.backgroundOpacity,
            borderAlpha: style.borderOpacity,
            rim: .specular(top: style.borderOpacity, bottom: 0.12),
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
        outer.layer?.shadowRadius = 3
        outer.layer?.shadowOffset = CGSize(width: 0, height: -2)

        return outer
    }

    /// Measures the tight visual width of the rendered glyphs, ignoring the
    /// font's side-bearing. Using `.useGlyphPathBounds` gives the actual ink
    /// rect; monospaced semibold returns a value several points narrower than the
    /// advance-width frame `sizeToFit()` reports.
    private static func glyphInkWidth(_ attributed: NSAttributedString) -> CGFloat {
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
