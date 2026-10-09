import AppKit

/// Creates numbered area label views for the scroll overlay.
///
/// The window owns the identity cache; this is a pure view factory.
enum AreaLabelRenderer {

    static let cornerRadius: CGFloat = 8

    @MainActor
    static func createHintLabel(for numbered: NumberedArea, style: OverlayStyle) -> NSView {
        let label = NSTextField(labelWithString: numbered.number)
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

        let width = label.frame.width + style.paddingX * 2
        let height = label.frame.height + style.paddingY * 2

        let container = GlassBackdrop.make(
            size: CGSize(width: width, height: height),
            cornerRadius: cornerRadius,
            tintColor: style.backgroundColor,
            tintAlpha: style.backgroundOpacity,
            borderAlpha: style.borderOpacity
        )

        label.frame = CGRect(x: 0, y: style.paddingY, width: width, height: label.frame.height)
        container.addSubview(label)

        let localOrigin = ScreenGeometry.toWindowLocal(
            CGRect(x: numbered.area.frame.maxX - width - 8,
                   y: numbered.area.frame.minY + 8,
                   width: width, height: height)
        )
        container.frame = CGRect(x: localOrigin.minX, y: localOrigin.minY, width: width, height: height)
        return container
    }

    /// Updates the displayed number on an existing label view. The label is
    /// nested inside the glass container, so callers can't simply cast the
    /// stored view to `NSTextField` anymore.
    static func updateNumber(on view: NSView, to newNumber: String) {
        if let textField = findLabel(in: view) {
            textField.stringValue = newNumber
        }
    }

    private static func findLabel(in view: NSView) -> NSTextField? {
        if let textField = view as? NSTextField { return textField }
        for subview in view.subviews {
            if let found = findLabel(in: subview) { return found }
        }
        return nil
    }
}
