//
//  HintLayout.swift
//  clavier
//
//  Shared builder for hint label views.
//
//  Both the production overlay (`HintOverlayWindow`) and the debug overlay
//  (`HintDebugOverlayWindow`) need the exact same placement result: token
//  assignment runs through `HintAssigner` and final frames come out of
//  `HintLabelRenderer.createHintLabel` + `HintPlacementEngine`.  Calling
//  that pipeline from two call sites invites drift; this enum is the one
//  place both paths go through.
//
//  Production attaches the returned views.  Debug mode reads `view.frame`
//  as the ground-truth token frame and renders the same view on its
//  overlay, so "where is the debug rectangle" and "where would the token
//  bubble render" come from the same computation.
//

import AppKit

@MainActor
enum HintLayout {

    /// One laid-out hint: the session-scoped (element, token) pair plus the
    /// view that would be rendered on the overlay.  The view's `frame` is
    /// already set to the final placement rect in window-local coordinates.
    struct LabeledView {
        let hinted: HintedElement
        let view: NSView
    }

    /// Build a hint label view per element using the production style,
    /// obstacle set, and placement engine.  Returns them in input order.
    ///
    /// `previousPlacements` lets the engine bias toward prior frames to
    /// reduce jitter across refreshes — production passes its recorded
    /// placements, debug mode passes `[:]` because debug is a one-shot
    /// observation.
    static func buildLabels(
        for hintedElements: [HintedElement],
        windowSize: CGSize,
        previousPlacements: [ElementIdentity: CGRect] = [:]
    ) -> [LabeledView] {
        let style = HintStyle()
        let obstacles = hintedElements.map { $0.element.visibleFrame }
        var engine = HintPlacementEngine(
            windowSize: windowSize,
            elementFrames: obstacles,
            previousPlacements: previousPlacements
        )
        return hintedElements.map { hinted in
            let view = HintLabelRenderer.createHintLabel(
                for: hinted,
                style: style,
                engine: &engine
            )
            return LabeledView(hinted: hinted, view: view)
        }
    }
}
