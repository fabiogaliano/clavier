//
//  HintPlacementEngine.swift
//  clavier
//
//  Stateful hint placement engine: collision reduction and viewport clamping.
//

import AppKit

/// Tracks already-placed hint rects so each new hint can be nudged to a
/// non-colliding candidate position, and clamps every frame to the overlay
/// window's visible bounds.
struct HintPlacementEngine {

    private var placedFrames: [CGRect] = []
    private let windowSize: CGSize

    init(windowSize: CGSize) {
        self.windowSize = windowSize
    }

    // MARK: - Public

    mutating func place(element: UIElement, labelSize: CGSize, horizontalOffset: CGFloat) -> CGRect {
        let candidates = candidateFrames(element: element, labelSize: labelSize, horizontalOffset: horizontalOffset)

        for candidate in candidates {
            let clamped = clamp(candidate)
            if !collides(clamped) {
                placedFrames.append(clamped)
                return clamped
            }
        }

        // All structured candidates collide — scan in label-width steps so
        // stacked hints shift apart rather than drawing on top of each other.
        let base = clamp(candidates[0])
        let step = labelSize.width + 4
        for multiplier: CGFloat in [1, -1, 2, -2, 3, -3] {
            let shifted = clamp(CGRect(x: base.minX + step * multiplier, y: base.minY,
                                      width: base.width, height: base.height))
            if !collides(shifted) {
                placedFrames.append(shifted)
                return shifted
            }
        }

        placedFrames.append(base)
        return base
    }

    // MARK: - Private

    private func candidateFrames(element: UIElement, labelSize: CGSize, horizontalOffset: CGFloat) -> [CGRect] {
        let w = labelSize.width
        let h = labelSize.height
        let el = element.visibleFrame
        let gap: CGFloat = 4

        // Pre-clamp anchor in screen space so hints never escape the physical
        // display the element lives on, regardless of window-local zero point.
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(el) }) ?? NSScreen.main
        let sf = screen?.frame ?? CGRect(origin: .zero, size: windowSize)

        func sx(_ x: CGFloat) -> CGFloat { max(sf.minX, min(x, sf.maxX - w)) }
        func sy(_ y: CGFloat) -> CGFloat { max(sf.minY, min(y, sf.maxY - h)) }
        func local(x: CGFloat, y: CGFloat) -> CGRect {
            ScreenGeometry.toWindowLocal(CGRect(x: sx(x), y: sy(y), width: w, height: h))
        }

        let ax   = el.minX + horizontalOffset
        let midY = el.minY + (el.height - h) / 2

        // Size-adaptive placement (key insight from label-placement research):
        // When the hint is large relative to the element it labels, place it
        // OUTSIDE the element boundary so the icon/content stays readable.
        // 2024 user study (arxiv 2407.11996): preferred order is
        //   above > below > right > top-right > bottom-right > left > inside
        let fillsElement = w >= el.width * 0.7 || h >= el.height * 0.7

        if fillsElement {
            return [
                local(x: ax,                y: el.maxY + gap),           // above ← most preferred
                local(x: ax,                y: el.minY - h - gap),       // below
                local(x: el.maxX + gap,     y: midY),                    // right, vertically centred
                local(x: el.maxX + gap,     y: el.maxY - h),             // top-right
                local(x: el.maxX + gap,     y: el.minY),                 // bottom-right
                local(x: el.minX - w - gap, y: midY),                    // left, vertically centred
                local(x: ax,                y: el.maxY - h),             // inside top-left (last resort)
            ]
        }

        // Hint fits inside the element — inside-first, outside as escape hatches.
        return [
            local(x: ax,            y: el.maxY - h),                     // inside top-left
            local(x: ax + w + gap,  y: el.maxY - h),                    // nudge right inside
            local(x: ax,            y: midY),                            // vertically centred inside
            local(x: el.maxX - w,   y: el.maxY - h),                    // inside top-right
            local(x: ax,            y: el.maxY + gap),                   // above element
            local(x: ax,            y: el.minY - h - gap),              // below element
            local(x: el.maxX + gap, y: midY),                           // right of element
        ]
    }

    private func clamp(_ rect: CGRect) -> CGRect {
        let x = max(0, min(rect.minX, windowSize.width - rect.width))
        let y = max(0, min(rect.minY, windowSize.height - rect.height))
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }

    // 3 pt gap prevents visually-touching labels from passing as non-colliding.
    private func collides(_ rect: CGRect) -> Bool {
        placedFrames.contains { $0.insetBy(dx: -3, dy: -3).intersects(rect) }
    }
}
