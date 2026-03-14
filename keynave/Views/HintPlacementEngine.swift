//
//  HintPlacementEngine.swift
//  keynave
//
//  Stateful hint placement engine: collision reduction and viewport clamping.
//

import AppKit

/// Tracks already-placed hint rects so each new hint can be nudged to a
/// non-colliding candidate position, and clamps every frame to the overlay
/// window's visible bounds.
struct HintPlacementEngine {

    private var placedFrames: [CGRect] = []

    /// Window-local size of the overlay (used for edge clamping).
    private let windowSize: CGSize

    init(windowSize: CGSize) {
        self.windowSize = windowSize
    }

    // MARK: - Public

    /// Returns a window-local frame for a hint label.
    ///
    /// Tries candidate positions in priority order and picks the first one
    /// that does not overlap an already-placed hint.  Falls back to the
    /// primary candidate when all alternatives collide.
    mutating func place(element: UIElement, labelSize: CGSize, horizontalOffset: CGFloat) -> CGRect {
        let candidates = candidateFrames(element: element, labelSize: labelSize, horizontalOffset: horizontalOffset)

        for candidate in candidates {
            let clamped = clamp(candidate)
            if !collides(clamped) {
                placedFrames.append(clamped)
                return clamped
            }
        }

        // All candidates collide — use the primary position, clamped.
        let fallback = clamp(candidates[0])
        placedFrames.append(fallback)
        return fallback
    }

    // MARK: - Private

    private func candidateFrames(element: UIElement, labelSize: CGSize, horizontalOffset: CGFloat) -> [CGRect] {
        let w = labelSize.width
        let h = labelSize.height
        let el = element.frame

        func local(x: CGFloat, y: CGFloat) -> CGRect {
            ScreenGeometry.toWindowLocal(CGRect(x: x, y: y, width: w, height: h))
        }

        return [
            // Primary: top-left corner of element with the user's horizontal offset.
            local(x: el.minX + horizontalOffset, y: el.maxY - h),
            // Nudge right past the hint label itself.
            local(x: el.minX + horizontalOffset + w + 4, y: el.maxY - h),
            // Vertically centred inside the element.
            local(x: el.minX + horizontalOffset, y: el.minY + (el.height - h) / 2),
            // Top-right corner as a last resort.
            local(x: el.maxX - w, y: el.maxY - h),
        ]
    }

    private func clamp(_ rect: CGRect) -> CGRect {
        let x = max(0, min(rect.minX, windowSize.width - rect.width))
        let y = max(0, min(rect.minY, windowSize.height - rect.height))
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }

    // Use a 1pt inset so labels that merely touch are still considered clear.
    private func collides(_ rect: CGRect) -> Bool {
        placedFrames.contains { $0.insetBy(dx: -1, dy: -1).intersects(rect) }
    }
}
