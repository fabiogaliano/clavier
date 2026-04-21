import AppKit

/// Creates numbered area label views for the scroll overlay.
///
/// The window owns the identity cache; this is a pure view factory.
enum AreaLabelRenderer {
    @MainActor
    static func createHintLabel(for numbered: NumberedArea) -> NSView {
        let label = NSTextField(labelWithString: numbered.number)
        label.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)
        label.textColor = .white
        label.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.9)
        label.isBordered = false
        label.isBezeled = false
        label.drawsBackground = true
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.cornerRadius = 4

        label.sizeToFit()

        let padding: CGFloat = 6
        let width = label.frame.width + padding * 2
        let height = label.frame.height + padding

        let localOrigin = ScreenGeometry.toWindowLocal(
            CGRect(x: numbered.area.frame.maxX - width - 8, y: numbered.area.frame.minY + 8, width: width, height: height)
        )

        label.frame = CGRect(x: localOrigin.minX, y: localOrigin.minY, width: width, height: height)

        return label
    }
}
