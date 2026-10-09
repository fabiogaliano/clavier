import AppKit

/// Appearance snapshot shared by the hint and scroll overlays.
///
/// Built once per session (or per Preferences render) through
/// `AppSettings.hintStyle` / `AppSettings.scrollStyle` and passed down to
/// the renderers, so no view factory reads `UserDefaults` itself.
struct OverlayStyle: Equatable {
    let fontSize: CGFloat
    let backgroundColor: NSColor
    let borderColor: NSColor
    /// Base colour of the letters still to type; drawn dimmed, see
    /// `remainderTextColor`.
    let textColor: NSColor
    /// Colour of the already-typed prefix of a hint token.
    let highlightTextColor: NSColor
    let backgroundOpacity: CGFloat
    /// Hint labels: strength of the specular highlight along the top edge.
    let borderOpacity: CGFloat
    let horizontalOffset: CGFloat
    let showTail: Bool
    let paddingX: CGFloat
    let paddingY: CGFloat

    /// Letters not yet typed recede so the typed prefix carries the eye.
    var remainderTextColor: NSColor {
        textColor.withAlphaComponent(textColor.alphaComponent * 0.55)
    }

    /// 7 pt at the default 12 pt size, scaled with the font so larger
    /// labels keep the same proportions instead of turning boxy.
    var labelCornerRadius: CGFloat {
        7 * fontSize / CGFloat(AppSettings.Defaults.hintSize)
    }

    /// Reads a raw stored value for a settings key; `nil` means "not stored".
    typealias Lookup = (String) -> Any?

    static func parseHint(_ value: @escaping Lookup, accentColor: NSColor = .controlAccentColor) -> OverlayStyle {
        typealias K = AppSettings.Keys
        typealias D = AppSettings.Defaults
        let reader = Reader(value: value)
        let useAccent = reader.bool(K.useSystemAccentColor, D.useSystemAccentColor)
        return OverlayStyle(
            fontSize: reader.positive(K.hintSize, D.hintSize),
            backgroundColor: useAccent ? accentColor : reader.color(K.hintBackgroundHex, D.hintBackgroundHex),
            borderColor: useAccent ? accentColor : reader.color(K.hintBorderHex, D.hintBorderHex),
            textColor: reader.color(K.hintTextHex, D.hintTextHex),
            highlightTextColor: reader.color(K.highlightTextHex, D.highlightTextHex),
            backgroundOpacity: reader.opacity(K.hintBackgroundOpacity, D.hintBackgroundOpacity),
            borderOpacity: reader.opacity(K.hintBorderOpacity, D.hintBorderOpacity),
            horizontalOffset: reader.double(K.hintHorizontalOffset, D.hintHorizontalOffset),
            showTail: reader.bool(K.showHintTail, D.showHintTail),
            paddingX: reader.nonNegative(K.hintPaddingX, D.hintPaddingX),
            paddingY: reader.nonNegative(K.hintPaddingY, D.hintPaddingY)
        )
    }

    static func parseScroll(_ value: @escaping Lookup, accentColor: NSColor = .controlAccentColor) -> OverlayStyle {
        typealias K = AppSettings.Keys
        typealias D = AppSettings.Defaults
        let reader = Reader(value: value)
        let useAccent = reader.bool(K.useSystemAccentColor, D.useSystemAccentColor)
        let textColor = reader.color(K.scrollTextHex, D.scrollTextHex)
        // Scroll labels have no typed prefix, tail, offset or user padding;
        // the fixed values are what the area labels have always used.
        return OverlayStyle(
            fontSize: reader.positive(K.scrollHintSize, D.scrollHintSize),
            backgroundColor: useAccent ? accentColor : reader.color(K.scrollBackgroundHex, D.scrollBackgroundHex),
            borderColor: useAccent ? accentColor : reader.color(K.scrollBorderHex, D.scrollBorderHex),
            textColor: textColor,
            highlightTextColor: textColor,
            backgroundOpacity: reader.opacity(K.scrollBackgroundOpacity, D.scrollBackgroundOpacity),
            borderOpacity: reader.opacity(K.scrollBorderOpacity, D.scrollBorderOpacity),
            horizontalOffset: 0,
            showTail: false,
            paddingX: 10,
            paddingY: 6
        )
    }

    /// Distinguishes "not stored" from a stored zero — a user-chosen 0 %
    /// opacity must stay 0 % rather than being mistaken for "unset".
    private struct Reader {
        let value: Lookup

        func double(_ key: String, _ fallback: Double) -> CGFloat {
            guard let number = value(key) as? NSNumber, number.doubleValue.isFinite else {
                return CGFloat(fallback)
            }
            return CGFloat(number.doubleValue)
        }

        func opacity(_ key: String, _ fallback: Double) -> CGFloat {
            min(max(double(key, fallback), 0), 1)
        }

        func positive(_ key: String, _ fallback: Double) -> CGFloat {
            let d = double(key, fallback)
            return d > 0 ? d : CGFloat(fallback)
        }

        func nonNegative(_ key: String, _ fallback: Double) -> CGFloat {
            max(double(key, fallback), 0)
        }

        func bool(_ key: String, _ fallback: Bool) -> Bool {
            (value(key) as? NSNumber)?.boolValue ?? fallback
        }

        func color(_ key: String, _ fallbackHex: String) -> NSColor {
            if let raw = value(key) as? String, let color = NSColor(validatingHex: raw) {
                return color
            }
            return NSColor(hex: fallbackHex)
        }
    }
}

extension AppSettings {
    static var hintStyle: OverlayStyle {
        OverlayStyle.parseHint { UserDefaults.standard.object(forKey: $0) }
    }

    static var scrollStyle: OverlayStyle {
        OverlayStyle.parseScroll { UserDefaults.standard.object(forKey: $0) }
    }
}
