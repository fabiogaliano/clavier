import AppKit
import SwiftUI

// Centralises the "liquid-glass-on-macOS-15" recipe (NSVisualEffectView blur +
// tint overlay + gradient rim + soft outer shadow) and the SwiftUI equivalent.
// macOS 26 ships `NSGlassEffectView` / SwiftUI `.glassEffect(...)`; when the
// project adopts Xcode 26 the real APIs slot in behind a single #available
// branch here and every renderer callsite stays unchanged.

@MainActor
enum GlassBackdrop {
    /// How the glass edge catches light.
    enum Rim {
        /// Full-perimeter gradient stroke, bright at the top.
        case gradient
        /// Liquid-glass look: a 1 px light line inside the top edge and a
        /// faint dark line inside the bottom edge, no perimeter stroke.
        case specular(top: CGFloat, bottom: CGFloat)
    }

    static func make(
        size: CGSize,
        cornerRadius: CGFloat,
        tintColor: NSColor,
        tintAlpha: CGFloat,
        borderAlpha: CGFloat,
        material: NSVisualEffectView.Material = .popover,
        rim: Rim = .gradient,
        shadow: Bool = true
    ) -> NSView {
        let container = NSView(frame: CGRect(origin: .zero, size: size))
        container.wantsLayer = true

        let blur = NSVisualEffectView(frame: container.bounds)
        blur.material = material
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = cornerRadius
        blur.layer?.masksToBounds = true
        blur.autoresizingMask = [.width, .height]

        let tint = NSView(frame: blur.bounds)
        tint.wantsLayer = true
        tint.layer?.backgroundColor = tintColor.withAlphaComponent(tintAlpha).cgColor
        tint.autoresizingMask = [.width, .height]
        blur.addSubview(tint)

        container.addSubview(blur)

        switch rim {
        case .gradient:
            addGradientRim(to: container, cornerRadius: cornerRadius, borderAlpha: borderAlpha)
        case .specular(let top, let bottom):
            addSpecularRim(to: container, cornerRadius: cornerRadius, top: top, bottom: bottom)
        }

        if shadow {
            container.layer?.masksToBounds = false
            container.layer?.shadowColor = NSColor.black.cgColor
            container.layer?.shadowOpacity = 0.18
            container.layer?.shadowRadius = 6
            container.layer?.shadowOffset = CGSize(width: 0, height: -2)
        }

        return container
    }

    private static func addGradientRim(to container: NSView, cornerRadius: CGFloat, borderAlpha: CGFloat) {
        // Gradient rim evokes a curved glass edge catching light — bright at
        // the top, fading toward the bottom. Community consensus (WWDC25 310,
        // Klarity) is that the rim carries the "glassiness" more than the fill.
        let rim = CAGradientLayer()
        rim.frame = container.bounds
        rim.colors = [
            NSColor.white.withAlphaComponent(borderAlpha).cgColor,
            NSColor.white.withAlphaComponent(borderAlpha * 0.2).cgColor
        ]
        rim.startPoint = CGPoint(x: 0.5, y: 1)
        rim.endPoint = CGPoint(x: 0.5, y: 0)

        let mask = CAShapeLayer()
        mask.frame = container.bounds
        let outer = CGPath(roundedRect: container.bounds,
                           cornerWidth: cornerRadius,
                           cornerHeight: cornerRadius,
                           transform: nil)
        let innerRect = container.bounds.insetBy(dx: 1, dy: 1)
        let inner = CGPath(roundedRect: innerRect,
                           cornerWidth: max(0, cornerRadius - 1),
                           cornerHeight: max(0, cornerRadius - 1),
                           transform: nil)
        let combined = CGMutablePath()
        combined.addPath(outer)
        combined.addPath(inner)
        mask.path = combined
        mask.fillRule = .evenOdd
        rim.mask = mask
        container.layer?.addSublayer(rim)
    }

    /// Each line is the shape minus itself shifted by 1 px, so it follows the
    /// corner curve and thins out toward the sides the way a lit glass edge
    /// does, instead of reading as a flat 1 px border.
    static func addSpecularRim(to container: NSView, cornerRadius: CGFloat, top: CGFloat, bottom: CGFloat) {
        let bounds = container.bounds
        let radius = min(cornerRadius, bounds.height / 2, bounds.width / 2)

        let clip = CALayer()
        clip.frame = bounds
        clip.cornerRadius = radius
        clip.masksToBounds = true

        func band(shiftY: CGFloat, color: NSColor) -> CAShapeLayer {
            let base = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
            var shift = CGAffineTransform(translationX: 0, y: shiftY)
            let shifted = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: &shift)
            let path = CGMutablePath()
            path.addPath(base)
            path.addPath(shifted)
            let layer = CAShapeLayer()
            layer.frame = bounds
            layer.path = path
            layer.fillRule = .evenOdd
            layer.fillColor = color.cgColor
            return layer
        }

        // Layer space is y-up here, so shifting down exposes the top edge.
        clip.addSublayer(band(shiftY: -1, color: NSColor.white.withAlphaComponent(top)))
        clip.addSublayer(band(shiftY: 1, color: NSColor.black.withAlphaComponent(bottom)))
        container.layer?.addSublayer(clip)
    }
}

// MARK: - SwiftUI glass fallback

extension View {
    /// Frosted-glass background usable inside SwiftUI views (Preferences,
    /// previews, chips). Layered to match the AppKit `GlassBackdrop` so the
    /// preview and the live overlay stay visually consistent.
    ///
    /// Requires an `InsettableShape` (RoundedRectangle, Capsule, Circle) so
    /// we can use `strokeBorder` for the rim without overshooting the fill.
    @ViewBuilder
    func glassedEffect<S: InsettableShape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            // Real liquid-glass (Metal shader) on macOS 26+. The fallback
            // below is still a reasonable approximation; this branch trades
            // it for the authentic system look once users upgrade.
            self.glassEffect(.regular, in: shape)
        } else {
            self.background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(
                        shape
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .primary.opacity(0.08),
                                        .primary.opacity(0.04),
                                        .clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .overlay(
                        shape
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.35),
                                        .white.opacity(0.08)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.8
                            )
                    )
                    .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: -2)
            }
        }
    }
}
