import AppKit

/// Manages the yellow selection border overlay for the active scroll area.
///
/// The window creates the highlight view once at setup time and passes it here
/// to update. This keeps the frame/visibility mutation out of the window's
/// orchestration methods.
enum SelectionHighlightRenderer {

    /// Show the highlight border around the selected area and dim all others.
    @MainActor
    static func select(
        area numbered: NumberedArea,
        highlightView: NSView?,
        hintViews: [AreaIdentity: NSView]
    ) {
        highlightView?.frame = ScreenGeometry.toWindowLocal(numbered.area.frame)
        highlightView?.isHidden = false

        for (identity, view) in hintViews {
            view.alphaValue = identity == numbered.identity ? 1.0 : 0.3
        }
    }

    /// Hide the highlight and restore all hint view opacity.
    static func clearSelection(
        highlightView: NSView?,
        hintViews: [AreaIdentity: NSView]
    ) {
        highlightView?.isHidden = true
        for (_, view) in hintViews {
            view.alphaValue = 1.0
        }
    }
}
