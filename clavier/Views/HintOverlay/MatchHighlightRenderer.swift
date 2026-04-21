import AppKit

/// Stateless helpers for prefix filtering, green-box highlight creation, and
/// match-count badge coloring in hint mode.
///
/// These are factored out of `HintOverlayWindow` to separate rendering concerns
/// from window lifecycle. The window owns the view caches; this module only
/// produces or mutates views.
enum MatchHighlightRenderer {

    /// Creates a green border highlight box over a matched text-search element.
    @MainActor
    static func createHighlightView(for element: UIElement) -> NSView {
        let localFrame = ScreenGeometry.toWindowLocal(element.visibleFrame.insetBy(dx: -2, dy: -2))
        let highlightView = NSView(frame: localFrame)
        highlightView.wantsLayer = true
        highlightView.layer?.borderWidth = 3
        highlightView.layer?.borderColor = NSColor.systemGreen.cgColor
        highlightView.layer?.cornerRadius = 4
        highlightView.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.1).cgColor
        return highlightView
    }

    /// Applies two-color attributed text to a hint label's text field so the
    /// already-typed prefix appears in the highlight color.
    static func highlightPrefix(in textField: NSTextField?, prefix: String, hint: String) {
        guard let textField = textField else { return }

        let highlightHex = UserDefaults.standard.string(forKey: AppSettings.Keys.highlightTextHex) ?? AppSettings.Defaults.highlightTextHex
        let textHex = UserDefaults.standard.string(forKey: AppSettings.Keys.hintTextHex) ?? AppSettings.Defaults.hintTextHex
        let highlightColor = NSColor(hex: highlightHex)
        let textColor = NSColor(hex: textHex)

        let attributedString = NSMutableAttributedString(string: hint)
        attributedString.addAttribute(.foregroundColor, value: highlightColor, range: NSRange(location: 0, length: prefix.count))
        if prefix.count < hint.count {
            attributedString.addAttribute(.foregroundColor, value: textColor, range: NSRange(location: prefix.count, length: hint.count - prefix.count))
        }
        textField.attributedStringValue = attributedString
    }

    /// Walks the glass container view hierarchy to find the `NSTextField` label.
    static func findTextField(in view: NSView) -> NSTextField? {
        if let textField = view as? NSTextField { return textField }
        for subview in view.subviews {
            if let textField = subview as? NSTextField { return textField }
        }
        return nil
    }
}
