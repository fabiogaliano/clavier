import AppKit

/// Stateless helpers for text-search highlight boxes and for finding a hint
/// label's text field inside its glass composition.
///
/// These are factored out of `HintOverlayWindow` to separate rendering concerns
/// from window lifecycle. The window owns the view caches; this module only
/// produces or mutates views.
enum MatchHighlightRenderer {

    /// Creates a soft-filled highlight over a matched text-search element
    /// (`frame` in screen coordinates). Thinner border + low-alpha fill reads as "this is the match" without
    /// overpowering the underlying UI element.
    @MainActor
    static func createHighlightView(frame: CGRect) -> NSView {
        let localFrame = ScreenGeometry.toWindowLocal(frame)
        let highlightView = NSView(frame: localFrame)
        highlightView.wantsLayer = true
        highlightView.layer?.borderWidth = 2
        highlightView.layer?.borderColor = NSColor.systemGreen.withAlphaComponent(0.85).cgColor
        highlightView.layer?.cornerRadius = 6
        highlightView.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.08).cgColor
        return highlightView
    }

    /// Recursively walks the view hierarchy to find the hint's NSTextField.
    /// The glass composition nests the label two levels deep (outer → glass →
    /// label), so a one-level walk would miss it.
    static func findTextField(in view: NSView) -> NSTextField? {
        if let textField = view as? NSTextField { return textField }
        for subview in view.subviews {
            if let found = findTextField(in: subview) { return found }
        }
        return nil
    }
}
