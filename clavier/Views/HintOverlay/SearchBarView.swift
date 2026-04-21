import AppKit

/// Builds the search bar subview anchored to the main display.
///
/// Returns the three NSView components the window needs to retain so it can
/// drive subsequent `updateSearchBar` and `updateMatchCount` calls.
enum SearchBarView {
    struct Components {
        let container: NSVisualEffectView
        let textField: NSTextField
        let countLabel: NSTextField
    }

    /// The search bar is intentionally anchored to the main display (the screen
    /// with the menu bar) because it is a global UI element the user types into,
    /// regardless of which display the hinted elements are on.
    @MainActor
    static func make(windowOrigin: CGPoint) -> Components {
        let mainFrame = NSScreen.main?.frame ?? .zero

        let containerWidth: CGFloat = 300
        let containerHeight: CGFloat = 40
        let containerX = mainFrame.minX + (mainFrame.width - containerWidth) / 2 - windowOrigin.x
        let containerY: CGFloat = 80 - windowOrigin.y

        let visualEffectView = NSVisualEffectView(
            frame: CGRect(x: containerX, y: containerY, width: containerWidth, height: containerHeight)
        )
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 10
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.layer?.borderWidth = 1.5
        visualEffectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor

        let textField = NSTextField(labelWithString: "")
        textField.font = NSFont.monospacedSystemFont(ofSize: 16, weight: .medium)
        textField.textColor = .white
        textField.backgroundColor = .clear
        textField.isBordered = false
        textField.alignment = .center
        textField.frame = CGRect(x: 10, y: 8, width: containerWidth - 80, height: 24)
        textField.placeholderString = "Type to search..."
        textField.placeholderAttributedString = NSAttributedString(
            string: "Type to search...",
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.5),
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            ]
        )

        let countLabel = NSTextField(labelWithString: "")
        countLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        countLabel.textColor = .systemYellow
        countLabel.backgroundColor = .clear
        countLabel.isBordered = false
        countLabel.alignment = .right
        countLabel.frame = CGRect(x: containerWidth - 70, y: 10, width: 60, height: 20)

        visualEffectView.addSubview(textField)
        visualEffectView.addSubview(countLabel)

        return Components(container: visualEffectView, textField: textField, countLabel: countLabel)
    }
}
