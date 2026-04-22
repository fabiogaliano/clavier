import AppKit
import SwiftUI

@MainActor
class HintOverlayWindow: NSWindow {

    private var hintedElements: [HintedElement]
    /// Keyed by stable element identity so view reuse survives hint-token
    /// reassignment across session refreshes (F06).
    private var hintViews: [ElementIdentity: NSView] = [:]
    private var elementHighlights: [UUID: NSView] = [:]
    private var searchBarView: NSView?
    private var searchTextField: NSTextField?
    private var matchCountBadge: NSView?
    private var matchCountLabel: NSTextField?
    /// Monotonically increasing Space-press count used to rotate z-order in
    /// overlap groups. Reset on every fresh layout so pressing Space after
    /// a refresh starts from the natural z-order.
    private var overlapRotationStep: Int = 0

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
        let obstacles = hintedElements.map { $0.element.visibleFrame }
        var engine = HintPlacementEngine(windowSize: self.frame.size, elementFrames: obstacles)
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
        self.matchCountBadge = components.countBadge
        self.matchCountLabel = components.countLabel
        self.contentView?.addSubview(components.container)
    }

    func show() {
        self.orderFrontRegardless()
    }

    func updateSearchBar(text: String) {
        searchTextField?.stringValue = text
    }

    func updateMatchCount(_ count: Int) {
        let style = MatchCountPresenter.style(forCount: count)
        matchCountLabel?.stringValue = style.labelText
        matchCountLabel?.textColor = style.labelColor
        matchCountBadge?.isHidden = style.labelText.isEmpty
        matchCountBadge?.layer?.backgroundColor = style.labelColor.withAlphaComponent(0.18).cgColor
        matchCountBadge?.layer?.borderColor = style.labelColor.withAlphaComponent(0.4).cgColor
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
        overlapRotationStep = 0
        let style = HintStyle()
        let obstacles = hintedElements.map { $0.element.visibleFrame }
        var engine = HintPlacementEngine(windowSize: self.frame.size, elementFrames: obstacles)
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

    /// Advance overlap z-order by one step.
    ///
    /// Each connected overlap group rotates its front-most member deterministically;
    /// after `group.count` presses the group returns to its initial order.
    /// Non-overlapping labels are untouched.
    func rotateOverlap() {
        guard let containerView = self.contentView, !hintViews.isEmpty else { return }

        let visibleEntries: [(identity: ElementIdentity, view: NSView, frame: CGRect)] =
            hintedElements.compactMap { hinted in
                guard let view = hintViews[hinted.identity], !view.isHidden else { return nil }
                return (hinted.identity, view, view.frame)
            }
        guard visibleEntries.count > 1 else { return }

        let frames = visibleEntries.map { $0.frame }
        let groups = HintOverlapCycler.groups(for: frames)
        guard !groups.isEmpty else { return }

        overlapRotationStep += 1

        for group in groups {
            let members = group.memberIndices.map { visibleEntries[$0] }
            let size = members.count
            let top = HintOverlapCycler.topMember(size: size, step: overlapRotationStep)
            // Desired visual order from top-front to bottom-back:
            //   [members[top], members[top+1], ..., members[top-1]] (mod size)
            // `addSubview(positioned: .above, relativeTo: nil)` raises the
            // given view to the front, so we add bottom-up — the last call
            // wins the frontmost slot.
            for i in stride(from: size - 1, through: 0, by: -1) {
                let entry = members[(top + i) % size]
                containerView.addSubview(entry.view, positioned: .above, relativeTo: nil)
            }
        }

        // Keep search-bar chrome above the hint layer regardless of rotation.
        if let bar = searchBarView {
            containerView.addSubview(bar, positioned: .above, relativeTo: nil)
        }
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
                let obstacles = textMatches.map { $0.element.visibleFrame }
                var engine = HintPlacementEngine(windowSize: self.frame.size, elementFrames: obstacles)
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
