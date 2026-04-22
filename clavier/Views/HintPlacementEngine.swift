//
//  HintPlacementEngine.swift
//  clavier
//
//  Stateful hint placement engine: cluster-aware cost-ranked label layout.
//
//  The algorithm is a UI-adapted blend of two families from the academic
//  Point-Feature Label Placement (PFLP) literature:
//
//  - **Greedy cost-ranked placement** (from Christensen, Marks & Shieber
//    1995's empirical study of PFLP): every candidate position is scored
//    against a cost function; the lowest-cost candidate wins.  The cost
//    is area-normalised so covering a small interactive icon is
//    penalised much more heavily than covering a large container.
//
//  - **Cluster-first preprocessing** (UI-specific; not in the PFLP
//    literature because maps don't have this structure): rows of
//    sibling widgets — navigator buttons, toolbar icons, tab strips —
//    share a geometric signature (same y, same height).  We detect
//    those clusters up front, pick ONE placement direction for the
//    whole row (above or below) based on the aggregate cost of each
//    option, and force every cluster member into that direction.  The
//    result is an aligned label strip instead of individually-optimal
//    but visually scattered placements.
//
//  Non-clustered elements fall through to the per-element cost-ranked
//  greedy, preserving the fast path for the common case.
//

import AppKit
import os

struct HintPlacementEngine {

    private var placedFrames: [CGRect] = []
    private let elementObstacles: [CGRect]
    private let windowSize: CGSize
    private let clusterDirection: [CGRect: PlacementDirection]

    enum PlacementDirection { case above, below, rightOf, leftOf }

    init(windowSize: CGSize, elementFrames: [CGRect] = []) {
        self.windowSize = windowSize
        self.elementObstacles = elementFrames
        self.clusterDirection = Self.detectClusters(
            elementFrames,
            windowSize: windowSize
        )
    }

    // MARK: - Public

    /// Cluster direction decided for this element up-front (nil if the
    /// element isn't part of a row or stack cluster).  The renderer calls
    /// this before `place` so it can size the outer container with the
    /// correct tail axis — a side-tail label needs extra width, a
    /// top/bottom-tail label needs extra height.
    func expectedDirection(for element: UIElement) -> PlacementDirection? {
        clusterDirection[element.visibleFrame]
    }

    mutating func place(element: UIElement, labelSize: CGSize, horizontalOffset: CGFloat) -> CGRect {
        let candidates = candidateFrames(element: element, labelSize: labelSize, horizontalOffset: horizontalOffset)
        let ownFrame = element.visibleFrame
        let obstacleCount = elementObstacles.count

        // Cluster members commit to the pre-decided direction.  We skip
        // label-on-label cost for these (cluster mates tile tightly and
        // that's expected — the row-alignment is the win).
        if let forced = clusterDirection[ownFrame] {
            let idx: Int
            switch forced {
            case .above:   idx = 0
            case .below:   idx = 1
            case .rightOf: idx = 2
            case .leftOf:  idx = 3
            }
            let rect = clamp(candidates[idx])
            placedFrames.append(rect)
            let elDesc = String(describing: ownFrame)
            let rDesc = String(describing: rect)
            Logger.hintMode.debug("place el=\(elDesc, privacy: .public) obstacles=\(obstacleCount) chose=CLUSTER(\(String(describing: forced), privacy: .public)) rect=\(rDesc, privacy: .public)")
            return rect
        }

        // Greedy with early-return on zero-cost — fast path for sparse
        // layouts where clean space exists.
        var ranked: [(rect: CGRect, cost: Double, label: String)] = []

        for (i, candidate) in candidates.enumerated() {
            let clamped = clamp(candidate)
            let cost = collisionCost(clamped, ownFrame: ownFrame)
            if cost == 0 {
                placedFrames.append(clamped)
                let elDesc = String(describing: ownFrame)
                let rDesc = String(describing: clamped)
                Logger.hintMode.debug("place el=\(elDesc, privacy: .public) obstacles=\(obstacleCount) chose=structured#\(i, privacy: .public) rect=\(rDesc, privacy: .public)")
                return clamped
            }
            ranked.append((clamped, cost, "structured#\(i)"))
        }

        let base = clamp(candidates[0])
        let step = labelSize.width + 4
        for multiplier: CGFloat in [1, -1, 2, -2, 3, -3] {
            let shifted = clamp(CGRect(x: base.minX + step * multiplier, y: base.minY,
                                      width: base.width, height: base.height))
            let cost = collisionCost(shifted, ownFrame: ownFrame)
            if cost == 0 {
                placedFrames.append(shifted)
                let elDesc = String(describing: ownFrame)
                let rDesc = String(describing: shifted)
                Logger.hintMode.debug("place el=\(elDesc, privacy: .public) obstacles=\(obstacleCount) chose=step×\(multiplier, privacy: .public) rect=\(rDesc, privacy: .public)")
                return shifted
            }
            ranked.append((shifted, cost, "step×\(multiplier)"))
        }

        let ownLocal = ScreenGeometry.toWindowLocal(ownFrame)
        let ownRect = clamp(CGRect(
            x: ownLocal.midX - labelSize.width / 2,
            y: ownLocal.midY - labelSize.height / 2,
            width: labelSize.width,
            height: labelSize.height
        ))
        let ownBaseline = 0.25
        ranked.append((ownRect, collisionCost(ownRect, ownFrame: ownFrame) + ownBaseline, "own"))

        let winner = ranked.min(by: { $0.cost < $1.cost })!
        placedFrames.append(winner.rect)
        let elDesc = String(describing: ownFrame)
        let rDesc = String(describing: winner.rect)
        Logger.hintMode.debug("place el=\(elDesc, privacy: .public) obstacles=\(obstacleCount) chose=BEST(\(winner.label, privacy: .public) cost=\(winner.cost, privacy: .public)) rect=\(rDesc, privacy: .public)")
        return winner.rect
    }

    // MARK: - Cluster detection

    /// Group elements that share a row signature — same `minY` and `height`
    /// within a 3 pt tolerance — into clusters of 3 or more.  For each
    /// cluster pick a single placement direction (above vs below) by
    /// comparing the aggregate cost of each option across every member.
    ///
    /// The tolerance has to be small (3 pt) because macOS AX sometimes
    /// reports heights off by a subpixel for antialiased borders; a
    /// looser threshold would spuriously merge unrelated rows.  The
    /// `count >= 3` minimum filters out incidental pairs that happen to
    /// line up but aren't visually a row.
    private static func detectClusters(
        _ frames: [CGRect],
        windowSize: CGSize
    ) -> [CGRect: PlacementDirection] {
        var directions: [CGRect: PlacementDirection] = [:]

        // Phase 1 — horizontal rows (same minY + height).  Direction is
        // above vs below.
        var rowBuckets: [String: [CGRect]] = [:]
        for frame in frames {
            let key = "\(Int(round(frame.minY / 3) * 3))_\(Int(round(frame.height / 3) * 3))"
            rowBuckets[key, default: []].append(frame)
        }
        for (_, members) in rowBuckets where members.count >= 3 {
            let direction = chooseVerticalStripDirection(for: members, allFrames: frames)
            for frame in members { directions[frame] = direction }
        }

        // Phase 2 — vertical stacks (same minX + width), skipping anything
        // already classified as a row.  Direction is right vs left.
        // Matches stacked panels like Activity Monitor's stat rows where
        // right-side placement should apply uniformly across the column.
        var colBuckets: [String: [CGRect]] = [:]
        for frame in frames where directions[frame] == nil {
            let key = "\(Int(round(frame.minX / 3) * 3))_\(Int(round(frame.width / 3) * 3))"
            colBuckets[key, default: []].append(frame)
        }
        for (_, members) in colBuckets where members.count >= 3 {
            let direction = chooseHorizontalStripDirection(for: members, allFrames: frames)
            for frame in members { directions[frame] = direction }
        }

        return directions
    }

    /// Pick above vs below for a cluster by computing each direction's
    /// aggregate area-normalised overlap cost against every non-cluster
    /// obstacle.  Cluster mates are excluded from the obstacle set here
    /// because they're the row we're labeling — we will be placing our
    /// strip in parallel to them, not colliding with them.
    ///
    /// If neither direction has room on the screen (clamped away) or
    /// both cost the same, default to below — matches the user's
    /// expectation for toolbar rows where the "content below" region
    /// is typically where a label is least obstructive.
    /// Summed area-normalised cost of placing a sample-size label at the
    /// given origin for every cluster member.  Shared by horizontal- and
    /// vertical-strip direction choosers.
    private static func stripCost(
        cluster: [CGRect],
        obstacles: [CGRect],
        labelSize: CGSize,
        origin: (CGRect) -> CGPoint
    ) -> Double {
        var total = 0.0
        for member in cluster {
            let labelRect = CGRect(origin: origin(member), size: labelSize)
            for other in obstacles {
                let overlap = other.intersection(labelRect)
                if !overlap.isNull && !overlap.isEmpty {
                    let otherArea = max(1, Double(other.width * other.height))
                    total += Double(overlap.width * overlap.height) / otherArea
                }
            }
        }
        return total
    }

    /// Above vs below for a row cluster.  Ties default to below — matches
    /// user expectation for toolbars where the "content below the chrome"
    /// region is usually the least-obstructive area for a label strip.
    private static func chooseVerticalStripDirection(
        for cluster: [CGRect],
        allFrames: [CGRect]
    ) -> PlacementDirection {
        let clusterSet = Set(cluster)
        let obstacles = allFrames.filter { !clusterSet.contains($0) }
        let sample = CGSize(width: 32, height: 22)
        let gap: CGFloat = 2

        let above = stripCost(cluster: cluster, obstacles: obstacles, labelSize: sample) {
            CGPoint(x: $0.midX - sample.width / 2, y: $0.maxY + gap)
        }
        let below = stripCost(cluster: cluster, obstacles: obstacles, labelSize: sample) {
            CGPoint(x: $0.midX - sample.width / 2, y: $0.minY - sample.height - gap)
        }
        return below <= above ? .below : .above
    }

    /// Right vs left for a vertical-stack cluster.  Ties default to right
    /// — matches Western reading order and the usual location of status-
    /// column whitespace in macOS panels.
    private static func chooseHorizontalStripDirection(
        for cluster: [CGRect],
        allFrames: [CGRect]
    ) -> PlacementDirection {
        let clusterSet = Set(cluster)
        let obstacles = allFrames.filter { !clusterSet.contains($0) }
        let sample = CGSize(width: 32, height: 22)
        let gap: CGFloat = 2

        let right = stripCost(cluster: cluster, obstacles: obstacles, labelSize: sample) {
            CGPoint(x: $0.maxX + gap, y: $0.midY - sample.height / 2)
        }
        let left = stripCost(cluster: cluster, obstacles: obstacles, labelSize: sample) {
            CGPoint(x: $0.minX - sample.width - gap, y: $0.midY - sample.height / 2)
        }
        return right <= left ? .rightOf : .leftOf
    }

    // MARK: - Candidate generation

    private func candidateFrames(element: UIElement, labelSize: CGSize, horizontalOffset: CGFloat) -> [CGRect] {
        let w = labelSize.width
        let h = labelSize.height
        let el = element.visibleFrame
        let gap: CGFloat = -4

        let screen = NSScreen.screens.first(where: { $0.frame.intersects(el) }) ?? NSScreen.main
        let sf = screen?.frame ?? CGRect(origin: .zero, size: windowSize)

        func sx(_ x: CGFloat) -> CGFloat { max(sf.minX, min(x, sf.maxX - w)) }
        func sy(_ y: CGFloat) -> CGFloat { max(sf.minY, min(y, sf.maxY - h)) }
        func local(x: CGFloat, y: CGFloat) -> CGRect {
            ScreenGeometry.toWindowLocal(CGRect(x: sx(x), y: sy(y), width: w, height: h))
        }

        let centerX = el.midX - w / 2 + horizontalOffset
        let midY    = el.minY + (el.height - h) / 2

        return [
            local(x: centerX,           y: el.maxY + gap),           // above-centred (index 0)
            local(x: centerX,           y: el.minY - h - gap),       // below-centred (index 1)
            local(x: el.maxX + gap,     y: midY),
            local(x: el.minX - w - gap, y: midY),
            local(x: el.maxX + gap,     y: el.maxY - h),
            local(x: el.minX - w - gap, y: el.maxY - h),
            local(x: centerX,           y: el.maxY - h),
        ]
    }

    private func clamp(_ rect: CGRect) -> CGRect {
        let x = max(0, min(rect.minX, windowSize.width - rect.width))
        let y = max(0, min(rect.minY, windowSize.height - rect.height))
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }

    /// Area-normalised collision cost.  See Christensen, Marks & Shieber
    /// 1995 for the empirical case that a weighted sum beats hard
    /// accept/reject filtering for dense layouts.
    private func collisionCost(_ rect: CGRect, ownFrame: CGRect) -> Double {
        var cost = 0.0
        for placed in placedFrames {
            let inflated = placed.insetBy(dx: -3, dy: -3)
            let overlap = inflated.intersection(rect)
            if !overlap.isNull && !overlap.isEmpty {
                cost += Double(overlap.width * overlap.height) * 0.5
            }
        }
        for other in elementObstacles where other != ownFrame {
            let otherLocal = ScreenGeometry.toWindowLocal(other)
            let overlap = otherLocal.intersection(rect)
            if !overlap.isNull && !overlap.isEmpty {
                let otherArea = max(1, Double(otherLocal.width * otherLocal.height))
                cost += Double(overlap.width * overlap.height) / otherArea
            }
        }
        return cost
    }
}
