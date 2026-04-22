//
//  ScrollOverlayRenderer.swift
//  clavier
//
//  Adapter between the orchestrator and `ScrollOverlayWindow`.
//
//  Mirrors `HintOverlayRenderer` in the hint mode: the controller previously
//  held a `ScrollOverlayWindow?` directly and called its full method surface
//  from lifecycle, discovery callback, and effect handler code paths.  This
//  adapter hides the window behind a small domain-shaped API so the
//  controller only needs to express rendering *intent*.
//
//  Keeping the adapter thin is intentional — the window continues to own
//  label placement, highlight rendering, and identity-keyed view reuse.
//  This file is purely a translation layer.
//

import Foundation
import AppKit

@MainActor
final class ScrollOverlayRenderer {

    private var window: ScrollOverlayWindow?

    // MARK: - Lifecycle

    /// Open the overlay with an initial list of numbered areas (usually one).
    func open(initialAreas: [NumberedArea]) {
        let newWindow = ScrollOverlayWindow(numberedAreas: initialAreas)
        newWindow.show()
        self.window = newWindow
    }

    /// Close and release the overlay.
    func close() {
        window?.orderOut(nil)
        window?.close()
        window = nil
    }

    // MARK: - Area list mutation

    func addArea(_ numbered: NumberedArea) {
        window?.addArea(numbered)
    }

    func removeArea(withIdentity identity: AreaIdentity) {
        window?.removeArea(withIdentity: identity)
    }

    func updateNumber(forIdentity identity: AreaIdentity, newNumber: String) {
        window?.updateNumber(forIdentity: identity, newNumber: newNumber)
    }

    // MARK: - Selection

    func selectArea(at index: Int) {
        window?.selectArea(at: index)
    }

    func clearSelection() {
        window?.clearSelection()
    }
}
