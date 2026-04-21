//
//  HintOverlayRenderer.swift
//  clavier
//
//  Adapter between the orchestrator and `HintOverlayWindow`.
//
//  The controller previously called `HintOverlayWindow` methods directly and
//  knew its full API surface.  This adapter translates high-level renderer
//  intentions (show a session, close, update) into concrete `HintOverlayWindow`
//  method calls so the controller only speaks in terms of `HintSession`.
//
//  Keeping this adapter thin is intentional: the window's rendering logic
//  (placement, glass labels, search bar) stays untouched.  This is purely a
//  translation layer.
//

import Foundation
import AppKit

// MARK: - Renderer

/// Translates `HintSession` state into `HintOverlayWindow` calls.
///
/// The controller creates one instance per mode activation and calls
/// `present(session:)` whenever the session changes.  On deactivation,
/// it calls `close()`.
@MainActor
final class HintOverlayRenderer {

    private var window: HintOverlayWindow?

    // MARK: - Lifecycle

    /// Open the overlay for the initial session.
    func open(session: HintSession) {
        let hintedElements = session.hintedElements
        let newWindow = HintOverlayWindow(hintedElements: hintedElements)
        newWindow.show()
        self.window = newWindow
    }

    /// Close and release the overlay.
    func close() {
        window?.orderOut(nil)
        window?.close()
        window = nil
    }

    // MARK: - Session rendering

    /// Render a complete session update — diff hints, apply filter, show search bar.
    ///
    /// Called whenever the session transitions (new elements, filter change, text search).
    func present(session: HintSession) {
        guard let window else { return }
        renderSessionDiff(session: session, in: window)
    }

    /// Update just the search bar text without re-diffing hints.
    func updateSearchBar(text: String) {
        window?.updateSearchBar(text: text)
    }

    /// Update just the match count badge.
    func updateMatchCount(_ count: Int) {
        window?.updateMatchCount(count)
    }

    /// Replace all hints with a fresh element list (used by refresh).
    func updateHints(with hintedElements: [HintedElement]) {
        window?.updateHints(with: hintedElements)
    }

    // MARK: - Private rendering

    private func renderSessionDiff(session: HintSession, in window: HintOverlayWindow) {
        switch session {
        case .inactive:
            break

        case .active(_, let filter):
            window.filterHints(matching: filter, textMatches: [], numberedMode: false)

        case .textSearch(_, let matches, _):
            if matches.isEmpty {
                window.filterHints(matching: "", textMatches: [], numberedMode: false)
            } else if matches.count <= 9 {
                window.filterHints(matching: "", textMatches: matches, numberedMode: true)
            } else {
                window.filterHints(matching: "", textMatches: matches, numberedMode: false)
            }
        }
    }
}
