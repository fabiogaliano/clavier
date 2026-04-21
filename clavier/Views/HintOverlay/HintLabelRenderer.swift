import AppKit

/// Appearance snapshot read once per overlay activation or refresh.
struct HintStyle {
    let fontSize: CGFloat
    let backgroundColor: NSColor
    let borderColor: NSColor
    let textColor: NSColor
    let bgOpacity: CGFloat
    let bdrOpacity: CGFloat
    let horizontalOffset: CGFloat

    init() {
        let size = UserDefaults.standard.double(forKey: AppSettings.Keys.hintSize)
        fontSize = size > 0 ? CGFloat(size) : CGFloat(AppSettings.Defaults.hintSize)
        let bgHex = UserDefaults.standard.string(forKey: AppSettings.Keys.hintBackgroundHex) ?? AppSettings.Defaults.hintBackgroundHex
        let brHex = UserDefaults.standard.string(forKey: AppSettings.Keys.hintBorderHex) ?? AppSettings.Defaults.hintBorderHex
        let txHex = UserDefaults.standard.string(forKey: AppSettings.Keys.hintTextHex) ?? AppSettings.Defaults.hintTextHex
        backgroundColor = NSColor(hex: bgHex)
        borderColor = NSColor(hex: brHex)
        textColor = NSColor(hex: txHex)
        let bgOp = UserDefaults.standard.double(forKey: AppSettings.Keys.hintBackgroundOpacity)
        bgOpacity = bgOp > 0 ? CGFloat(bgOp) : CGFloat(AppSettings.Defaults.hintBackgroundOpacity)
        let bdOp = UserDefaults.standard.double(forKey: AppSettings.Keys.hintBorderOpacity)
        bdrOpacity = bdOp > 0 ? CGFloat(bdOp) : CGFloat(AppSettings.Defaults.hintBorderOpacity)
        horizontalOffset = CGFloat(UserDefaults.standard.double(forKey: AppSettings.Keys.hintHorizontalOffset))
    }
}

/// Creates individual hint label views (glass container + tint + label).
///
/// The window owns the identity cache; this is a pure view factory that
/// consumes a `HintPlacementEngine` for layout and a `HintStyle` for appearance.
enum HintLabelRenderer {
    @MainActor
    static func createHintLabel(
        for hintedElement: HintedElement,
        style: HintStyle,
        engine: inout HintPlacementEngine
    ) -> NSView {
        let label = NSTextField(labelWithString: hintedElement.hint)
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
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.shadowBlurRadius = 2
            return shadow
        }()

        label.sizeToFit()

        let padding: CGFloat = 2
        let width = label.frame.width + padding * 2
        let height = label.frame.height + padding

        let glassContainer = NSVisualEffectView(frame: .zero)
        glassContainer.material = .hudWindow
        glassContainer.blendingMode = .behindWindow
        glassContainer.state = .active
        glassContainer.wantsLayer = true
        glassContainer.layer?.cornerRadius = 3
        glassContainer.layer?.masksToBounds = true
        glassContainer.layer?.borderWidth = 1
        glassContainer.layer?.borderColor = style.borderColor.withAlphaComponent(style.bdrOpacity).cgColor

        let tintOverlay = NSView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        tintOverlay.wantsLayer = true
        tintOverlay.layer?.backgroundColor = style.backgroundColor.withAlphaComponent(style.bgOpacity).cgColor

        label.frame = CGRect(x: 0, y: 0, width: width, height: height)

        glassContainer.addSubview(tintOverlay)
        glassContainer.addSubview(label)

        let hintFrame = engine.place(
            element: hintedElement.element,
            labelSize: CGSize(width: width, height: height),
            horizontalOffset: style.horizontalOffset
        )

        glassContainer.frame = hintFrame

        return glassContainer
    }
}
