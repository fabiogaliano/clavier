//
//  HintRefreshSettler.swift
//  clavier
//
//  Pure "has the UI finished changing?" policy behind the post-click refresh.
//
//  A click rarely changes the AX tree in one step: a popover animates in, a
//  listbox fills from the network, a menu slides open.  Reading the tree once
//  catches it half-drawn, so `HintRefreshCoordinator` samples it on a
//  backing-off schedule and asks this type after every sample whether to keep
//  going.
//
//  Each sample is reduced to a signature: the set of element identities
//  (pid + role + rounded frame).  An element that moves or resizes therefore
//  counts as "still changing", just like one that appears or disappears.
//
//      click ─► sample ─► sample ─► sample
//               differs   differs   same as previous  →  settled (.changed)
//
//      click ─► sample ─► sample ─► … ─► window over
//               baseline  baseline        →  .unchanged
//

import Foundation

/// Identity set of one discovery pass, used to compare AX-tree snapshots.
typealias HintTreeSignature = Set<ElementIdentity>

enum HintRefreshOutcome: Equatable {
    /// The UI diverged from the pre-click baseline.
    case changed
    /// The whole settle window passed without any sample differing from baseline.
    case unchanged
}

struct HintRefreshSettler {

    enum Verdict: Equatable {
        case sampleAgain(after: TimeInterval)
        case finished(HintRefreshOutcome)
    }

    private static let backoffFactor = 1.5

    let baseline: HintTreeSignature
    let delays: HintRefreshDelays

    private var previous: HintTreeSignature?
    private var nextInterval: TimeInterval
    private var hasDiverged = false

    init(baseline: HintTreeSignature, delays: HintRefreshDelays) {
        self.baseline = baseline
        self.delays = delays
        self.nextInterval = delays.pollInterval
    }

    var firstDelay: TimeInterval { delays.optimistic }

    /// Feed one sample; `elapsed` is the time since the click.
    mutating func observe(_ signature: HintTreeSignature, elapsed: TimeInterval) -> Verdict {
        defer { previous = signature }
        if signature != baseline { hasDiverged = true }

        // Two identical samples in a row after a divergence: the UI stopped moving.
        if hasDiverged, signature == previous {
            return .finished(.changed)
        }
        // A still-unchanged tree keeps being sampled until the window closes,
        // because popover content often arrives late (animation, network).
        guard elapsed < delays.settleWindow else {
            return .finished(hasDiverged ? .changed : .unchanged)
        }

        let wait = nextInterval
        nextInterval *= Self.backoffFactor
        return .sampleAgain(after: wait)
    }
}
