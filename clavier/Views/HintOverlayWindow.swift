import AppKit
import SwiftUI

@MainActor
class HintOverlayWindow: NSWindow {

    private var hintedElements: [HintedElement]
    /// Keyed by stable element identity so view reuse survives hint-token
    /// reassignment across session refreshes (F06).
    private var hintViews: [ElementIdentity: NSView] = [:]
    private var elementHighlights: [UUID: NSView] = [:]
    private var searchBarView: NSVisualEffectView?
    private var searchTextField: NSTextField?
    private var matchCountLabel: NSTextField?

    init(hintedElements: [HintedElement]) {
        self.hintedElements = hintedElements

        // Cover the entire desktop so hints render correctly on every display.
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

        setupHintViews()
        setupSearchBar()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private func setupHintViews() {
        let containerView = NSView(frame: CGRect(origin: .zero, size: self.frame.size))
        containerView.wantsLayer = true

        let style = HintStyle()
        var engine = HintPlacementEngine(windowSize: self.frame.size)
        for hintedElement in hintedElements {
            let hintView = HintLabelRenderer.createHintLabel(for: hintedElement, style: style, engine: &engine)
            containerView.addSubview(hintView)
            hintViews[hintedElement.identity] = hintView
        }

        self.contentView = containerView
    }

    private func setupSearchBar() {
        let windowOrigin = ScreenGeometry.desktopBoundsInAppKit.origin
        let components = SearchBarView.make(windowOrigin: windowOrigin)
        self.searchBarView = components.container
        self.searchTextField = components.textField
        self.matchCountLabel = components.countLabel
        self.contentView?.addSubview(components.container)
    }

    func show() {
        self.orderFrontRegardless()
    }

    func updateSearchBar(text: String) {
        searchTextField?.stringValue = text
        if text.isEmpty {
            searchBarView?.layer?.borderColor = NSColor.systemBlue.cgColor
        }
    }

    func updateMatchCount(_ count: Int) {
        if count == -1 {
            matchCountLabel?.stringValue = ""
            searchBarView?.layer?.borderColor = NSColor.systemBlue.cgColor
        } else if count == 0 {
            matchCountLabel?.stringValue = "0"
            matchCountLabel?.textColor = .systemRed
            searchBarView?.layer?.borderColor = NSColor.systemRed.cgColor
        } else if count == 1 {
            matchCountLabel?.stringValue = "1"
            matchCountLabel?.textColor = .systemGreen
            searchBarView?.layer?.borderColor = NSColor.systemGreen.cgColor
        } else {
            matchCountLabel?.stringValue = "\(count)"
            matchCountLabel?.textColor = .systemYellow
            searchBarView?.layer?.borderColor = NSColor.systemYellow.cgColor
        }
    }

    override func close() {
        hintViews.removeAll()
        self.contentView?.subviews.forEach { $0.removeFromSuperview() }
        self.orderOut(nil)
        super.close()
    }

    /// Diff the overlay against a new hint assignment list.
    ///
    /// Views are keyed by `ElementIdentity` so reuse is stable across refreshes
    /// where only the hint token changed — the F06 fix. The diff:
    /// - removes views whose identity is no longer present
    /// - updates the hint text of views whose token changed
    /// - repositions views whose frame changed
    /// - adds views for newly discovered elements
    func updateHints(with newHintedElements: [HintedElement]) {
        for (_, view) in elementHighlights { view.removeFromSuperview() }
        elementHighlights.removeAll()

        let neededIdentities = Set(newHintedElements.map { $0.identity })

        for (identity, view) in hintViews where !neededIdentities.contains(identity) {
            view.removeFromSuperview()
            hintViews[identity] = nil
        }

        self.hintedElements = newHintedElements
        let style = HintStyle()
        var engine = HintPlacementEngine(windowSize: self.frame.size)
        for hintedElement in hintedElements {
            let identity = hintedElement.identity
            if let existingView = hintViews[identity] {
                if let textField = MatchHighlightRenderer.findTextField(in: existingView) {
                    textField.stringValue = hintedElement.hint
                }
                let newFrame = engine.place(
                    element: hintedElement.element,
                    labelSize: existingView.frame.size,
                    horizontalOffset: style.horizontalOffset
                )
                existingView.frame = newFrame
            } else {
                let hintView = HintLabelRenderer.createHintLabel(for: hintedElement, style: style, engine: &engine)
                self.contentView?.addSubview(hintView)
                hintViews[identity] = hintView
            }
        }

        updateSearchBar(text: "")
        updateMatchCount(-1)

        self.contentView?.needsDisplay = true
        self.displayIfNeeded()
    }

    func filterHints(matching prefix: String) {
        filterHints(matching: prefix, textMatches: [], numberedMode: false)
    }

    func filterHints(matching prefix: String, textMatches: [HintedElement], numberedMode: Bool = false) {
        for (_, highlightView) in elementHighlights {
            highlightView.removeFromSuperview()
        }
        elementHighlights.removeAll()

        let textHex = UserDefaults.standard.string(forKey: AppSettings.Keys.hintTextHex) ?? AppSettings.Defaults.hintTextHex
        let textColor = NSColor(hex: textHex)

        if !textMatches.isEmpty {
            if numberedMode {
                for (_, view) in hintViews { view.isHidden = true }

                let style = HintStyle()
                var engine = HintPlacementEngine(windowSize: self.frame.size)
                for hintedElement in textMatches {
                    let hintView = HintLabelRenderer.createHintLabel(for: hintedElement, style: style, engine: &engine)
                    self.contentView?.addSubview(hintView)
                    elementHighlights[hintedElement.element.id] = hintView
                }
            } else {
                for hintedElement in textMatches {
                    let highlightView = MatchHighlightRenderer.createHighlightView(for: hintedElement.element)
                    self.contentView?.addSubview(highlightView)
                    elementHighlights[hintedElement.element.id] = highlightView
                }
                for (_, view) in hintViews { view.isHidden = true }
            }
        } else {
            for (identity, view) in hintViews {
                guard let hintedElement = hintedElements.first(where: { $0.identity == identity }) else {
                    view.isHidden = true
                    continue
                }
                let hint = hintedElement.hint
                if prefix.isEmpty {
                    view.isHidden = false
                    if let textField = MatchHighlightRenderer.findTextField(in: view) {
                        textField.textColor = textColor
                    }
                } else if hint.hasPrefix(prefix) {
                    view.isHidden = false
                    if let textField = MatchHighlightRenderer.findTextField(in: view) {
                        MatchHighlightRenderer.highlightPrefix(in: textField, prefix: prefix, hint: hint)
                    }
                } else {
                    view.isHidden = true
                }
            }
        }
    }
}
