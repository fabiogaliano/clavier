//
//  HintOverlayRenderer.swift
//  clavier
//
//  Adapter between the orchestrator and `HintOverlayWindow`.
//
//  The reducer speaks in separate effects (session update, search text,
//  match count, label hiding); this adapter folds them into one
//  `HintScene` and hands the window a single `render(_:style:)` call, so
//  the window never has to reconcile partial updates itself.
//

import Foundation
import AppKit

// MARK: - Renderer

/// Translates `HintSession` state into `HintScene`s for `HintOverlayWindow`.
///
/// The controller creates one instance per mode activation and calls
/// `present(session:)` whenever the session changes.  On deactivation,
/// it calls `close()`.
@MainActor
final class HintOverlayRenderer {

    private var window: HintOverlayWindow?
    /// Loaded once per activation; Preferences edits apply from the next one.
    private var style: OverlayStyle = AppSettings.hintStyle
    private var session: HintSession = .inactive
    private var chrome = HintScene.Chrome()

    /// Invoked when the user clicks the bar's help segment.
    var onHelpRequested: (() -> Void)?

    // MARK: - Lifecycle

    /// Open the overlay for the initial session.
    func open(session: HintSession) {
        style = AppSettings.hintStyle
        self.session = session
        chrome = HintScene.Chrome()
        let newWindow = HintOverlayWindow()
        newWindow.onBarHelp = { [weak self] in self?.onHelpRequested?() }
        self.window = newWindow
        render()
        newWindow.show()
    }

    /// Close and release the overlay.
    func close() {
        window?.orderOut(nil)
        window?.close()
        window = nil
        session = .inactive
        chrome = HintScene.Chrome()
    }

    // MARK: - Session rendering

    /// Render a session transition (filter change, text search, cleared filter).
    func present(session: HintSession) {
        self.session = session
        render()
    }

    func updateSearchBar(text: String) {
        chrome.searchText = text
        render()
    }

    func updateMatchCount(_ count: Int, isHydrating: Bool = false) {
        chrome.matchCount = count
        chrome.isHydrating = isHydrating
        render()
    }

    /// Replace all hints with a fresh element list (used by refresh).
    func updateHints(with hintedElements: [HintedElement]) {
        session = .active(hintedElements: hintedElements, filter: "", mode: session.mode)
        // A refresh implies the user started a new selection gesture; drop
        // search state and hide-mode so the redrawn labels are visible.
        // The countdown belongs to the session, not the gesture.
        chrome = HintScene.Chrome(countdown: chrome.countdown)
        render()
    }

    /// Advance the overlap rotation: labels hidden behind others in a
    /// connected overlap group move one step toward the front.
    func rotateOverlap() {
        window?.rotateOverlap()
    }

    /// Toggle hint-label visibility without discarding underlying state.
    /// Used by the hide-prefix flow so a user can type a query without
    /// letters on top of their own UI.
    func setLabelsHidden(_ hidden: Bool) {
        chrome.labelsHidden = hidden
        render()
    }

    func setContinuousMode(_ isContinuous: Bool) {
        let mode: HintSessionMode = isContinuous ? .continuous : .oneShot
        switch session {
        case .inactive:
            break
        case .active(let elements, let filter, _):
            session = .active(hintedElements: elements, filter: filter, mode: mode)
        case .textSearch(let elements, let matches, let filter, _):
            session = .textSearch(hintedElements: elements, matches: matches, filter: filter, mode: mode)
        }
        render()
    }

    /// Continuous-mode time left; `nil` when auto-deactivation is off.
    func setCountdown(_ countdown: HintScene.Countdown?) {
        guard chrome.countdown != countdown else { return }
        chrome.countdown = countdown
        render()
    }

    private func render() {
        window?.render(HintScene.derive(from: session, chrome: chrome), style: style)
    }
}
