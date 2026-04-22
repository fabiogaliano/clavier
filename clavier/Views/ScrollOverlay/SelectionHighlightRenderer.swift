import AppKit

/// Manages the selection border overlay for the active scroll area.
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
        applyActiveStyle(highlightView)

        for (identity, view) in hintViews {
            view.alphaValue = identity == numbered.identity ? 1.0 : 0.35
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

    /// Applies the visual style to the shared highlight view. Called at setup
    /// and on each selection so the style tracks accent/color preference
    /// changes without rebuilding the view.
    @MainActor
    static func applyActiveStyle(_ view: NSView?) {
        guard let view = view else { return }
        let borderHex = UserDefaults.standard.string(forKey: AppSettings.Keys.scrollBorderHex) ?? AppSettings.Defaults.scrollBorderHex
        let tint = AppearanceColor.effectiveTint(customHex: borderHex)
        view.wantsLayer = true
        view.layer?.borderColor = tint.withAlphaComponent(0.9).cgColor
        view.layer?.backgroundColor = tint.withAlphaComponent(0.08).cgColor
        view.layer?.borderWidth = 2
        view.layer?.cornerRadius = 6
    }
}
