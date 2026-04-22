import AppKit

/// Builds the search bar subview anchored to the main display.
///
/// Returns the three NSView components the window needs to retain so it can
/// drive subsequent `updateSearchBar` and `updateMatchCount` calls.
enum SearchBarView {
    struct Components {
        let container: NSView
        let textField: NSTextField
        let countBadge: NSView
        let countLabel: NSTextField
    }

    /// The search bar is intentionally anchored to the main display (the screen
    /// with the menu bar) because it is a global UI element the user types into,
    /// regardless of which display the hinted elements are on.
    @MainActor
    static func make(windowOrigin: CGPoint) -> Components {
        let mainFrame = NSScreen.main?.frame ?? .zero

        let containerWidth: CGFloat = 320
        let containerHeight: CGFloat = 44
        let containerX = mainFrame.minX + (mainFrame.width - containerWidth) / 2 - windowOrigin.x
        let containerY: CGFloat = 80 - windowOrigin.y

        // Pill shape — corner radius ≈ half height reads as a capsule, which is
        // the modern macOS search-field aesthetic (Spotlight, Raycast, etc.).
        let pillRadius = containerHeight / 2

        let container = GlassBackdrop.make(
            size: CGSize(width: containerWidth, height: containerHeight),
            cornerRadius: pillRadius,
            tintColor: NSColor.black,
            tintAlpha: 0.08,
            borderAlpha: 0.35,
            material: .popover
        )
        container.frame.origin = CGPoint(x: containerX, y: containerY)

        let textField = NSTextField(labelWithString: "")
        textField.font = NSFont.monospacedSystemFont(ofSize: 16, weight: .medium)
        textField.textColor = NSColor.labelColor
        textField.backgroundColor = .clear
        textField.isBordered = false
        textField.alignment = .center
        textField.frame = CGRect(x: 16, y: (containerHeight - 22) / 2,
                                 width: containerWidth - 96, height: 22)
        textField.placeholderAttributedString = NSAttributedString(
            string: "Type to search…",
            attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            ]
        )

        // Inline rounded tag instead of a loose digit — reads as a chip.
        let badgeWidth: CGFloat = 58
        let badgeHeight: CGFloat = 22
        let badge = NSView(frame: CGRect(
            x: containerWidth - badgeWidth - 10,
            y: (containerHeight - badgeHeight) / 2,
            width: badgeWidth,
            height: badgeHeight
        ))
        badge.wantsLayer = true
        badge.layer?.cornerRadius = badgeHeight / 2
        badge.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.18).cgColor
        badge.layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.4).cgColor
        badge.layer?.borderWidth = 0.5
        badge.isHidden = true

        let countLabel = NSTextField(labelWithString: "")
        countLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        countLabel.textColor = .systemBlue
        countLabel.backgroundColor = .clear
        countLabel.isBordered = false
        countLabel.alignment = .center
        countLabel.frame = CGRect(x: 0, y: (badgeHeight - 14) / 2,
                                  width: badgeWidth, height: 14)
        badge.addSubview(countLabel)

        container.addSubview(textField)
        container.addSubview(badge)

        return Components(container: container, textField: textField, countBadge: badge, countLabel: countLabel)
    }
}
