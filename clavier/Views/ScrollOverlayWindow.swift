//
//  ScrollOverlayWindow.swift
//  clavier
//
//  Transparent overlay window for displaying scroll area hints
//

import AppKit
import SwiftUI

@MainActor
class ScrollOverlayWindow: NSWindow {

    private var numberedAreas: [NumberedArea]
    /// Keyed by stable area identity so view reuse survives number reassignment
    /// across progressive-discovery merges (F06 equivalent for scroll, P3-S2).
    private var hintViews: [AreaIdentity: NSView] = [:]
    private var highlightView: NSView?
    private var selectedAreaIndex: Int?

    init(numberedAreas: [NumberedArea]) {
        self.numberedAreas = numberedAreas

        let desktopBounds = ScreenGeometry.desktopBoundsInAppKit

        super.init(
            contentRect: desktopBounds,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        self.level = .screenSaver
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isReleasedWhenClosed = false

        setupViews()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private func setupViews() {
        let containerView = NSView(frame: CGRect(origin: .zero, size: self.frame.size))
        containerView.wantsLayer = true

        let highlight = NSView(frame: .zero)
        highlight.wantsLayer = true
        highlight.layer?.borderColor = NSColor.systemYellow.cgColor
        highlight.layer?.borderWidth = 3
        highlight.layer?.cornerRadius = 4
        highlight.isHidden = true
        containerView.addSubview(highlight)
        highlightView = highlight

        let showNumbers = UserDefaults.standard.bool(forKey: AppSettings.Keys.showScrollAreaNumbers)

        if showNumbers {
            for numbered in numberedAreas {
                let hintView = createHintLabel(for: numbered)
                containerView.addSubview(hintView)
                hintViews[numbered.identity] = hintView
            }
        }

        self.contentView = containerView
    }

    private func createHintLabel(for numbered: NumberedArea) -> NSView {
        let label = NSTextField(labelWithString: numbered.number)
        label.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)
        label.textColor = .white
        label.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.9)
        label.isBordered = false
        label.isBezeled = false
        label.drawsBackground = true
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.cornerRadius = 4

        label.sizeToFit()

        let padding: CGFloat = 6
        let width = label.frame.width + padding * 2
        let height = label.frame.height + padding

        let localOrigin = ScreenGeometry.toWindowLocal(
            CGRect(x: numbered.area.frame.maxX - width - 8, y: numbered.area.frame.minY + 8, width: width, height: height)
        )

        label.frame = CGRect(x: localOrigin.minX, y: localOrigin.minY, width: width, height: height)

        return label
    }

    func show() {
        self.orderFrontRegardless()
    }

    /// Dynamically add a new numbered area to the overlay during progressive discovery.
    func addArea(_ numbered: NumberedArea) {
        numberedAreas.append(numbered)

        let showNumbers = UserDefaults.standard.bool(forKey: AppSettings.Keys.showScrollAreaNumbers)
        guard showNumbers else { return }

        let hintView = createHintLabel(for: numbered)
        contentView?.addSubview(hintView)
        hintViews[numbered.identity] = hintView

        // Dim the new hint if an area is already selected
        if selectedAreaIndex != nil {
            hintView.alphaValue = 0.3
        }
    }

    /// Remove an area from the overlay by its stable identity.
    func removeArea(withIdentity identity: AreaIdentity) {
        numberedAreas.removeAll { $0.identity == identity }

        if let hintView = hintViews[identity] {
            hintView.removeFromSuperview()
            hintViews.removeValue(forKey: identity)
        }
    }

    /// Update the displayed number for an area after resequencing.
    func updateNumber(forIdentity identity: AreaIdentity, newNumber: String) {
        if let idx = numberedAreas.firstIndex(where: { $0.identity == identity }) {
            numberedAreas[idx] = NumberedArea(area: numberedAreas[idx].area, number: newNumber)
        }

        if let hintView = hintViews[identity] as? NSTextField {
            hintView.stringValue = newNumber
        }
    }

    override func close() {
        hintViews.removeAll()
        self.contentView?.subviews.forEach { $0.removeFromSuperview() }
        self.orderOut(nil)
        super.close()
    }

    func selectArea(at index: Int) {
        guard index >= 0 && index < numberedAreas.count else { return }

        selectedAreaIndex = index
        let numbered = numberedAreas[index]

        highlightView?.frame = ScreenGeometry.toWindowLocal(numbered.area.frame)
        highlightView?.isHidden = false

        for (identity, view) in hintViews {
            view.alphaValue = identity == numbered.identity ? 1.0 : 0.3
        }
    }

    func clearSelection() {
        selectedAreaIndex = nil
        highlightView?.isHidden = true

        for (_, view) in hintViews {
            view.alphaValue = 1.0
        }
    }
}
