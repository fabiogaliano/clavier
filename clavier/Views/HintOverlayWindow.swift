import AppKit
import SwiftUI

@MainActor
class HintOverlayWindow: NSWindow {

    /// Token assignment currently laid out; compared against each incoming
    /// scene to decide whether placement has to run again.
    private var hintedElements: [HintedElement] = []
    /// Keyed by stable element identity so view reuse survives hint-token
    /// reassignment across session refreshes (F06).
    private var hintViews: [ElementIdentity: NSView] = [:]
    /// Numbered labels or outline boxes for the current text-search results.
    private var elementHighlights: [ElementIdentity: NSView] = [:]
    private var searchBarView: NSView?
    private var searchTextField: NSTextField?
    private var matchCountBadge: NSView?
    private var matchCountLabel: NSTextField?
    private var continuousModeIndicator: NSView?
    /// Last scene applied, so chrome-only changes (search text, match count)
    /// don't rebuild labels on every keystroke.
    private var renderedScene: HintScene?
    /// Monotonically increasing Space-press count used to rotate z-order in
    /// overlap groups. Reset on every fresh layout so pressing Space after
    /// a refresh starts from the natural z-order.
    private var overlapRotationStep: Int = 0
    /// Placement frames from the previous render pass, keyed by stable
    /// identity.  Used by the placement engine to bias toward prior
    /// positions when valid and so reduce label jitter across refreshes.
    private var previousPlacements: [ElementIdentity: CGRect] = [:]

    init() {
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

        let containerView = NSView(frame: CGRect(origin: .zero, size: self.frame.size))
        containerView.wantsLayer = true
        self.contentView = containerView
        setupSearchBar()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

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

    override func close() {
        hintViews.removeAll()
        elementHighlights.removeAll()
        self.contentView?.subviews.forEach { $0.removeFromSuperview() }
        self.orderOut(nil)
        super.close()
    }

    // MARK: - Rendering

    /// Bring the overlay in line with `scene`.  Placement runs only when the
    /// token assignment changed; label content only when what is drawn
    /// changed; chrome always (it is cheap).
    func render(_ scene: HintScene, style: OverlayStyle) {
        let relaidOut = !sameLayout(hintedElements, scene.hintedElements)
        if relaidOut {
            layOutHints(scene.hintedElements, style: style)
        }

        if relaidOut
            || renderedScene?.content != scene.content
            || renderedScene?.chrome.labelsHidden != scene.chrome.labelsHidden {
            applyContent(scene, style: style)
        }

        applyChrome(scene)
        renderedScene = scene

        if relaidOut {
            self.contentView?.needsDisplay = true
            self.displayIfNeeded()
        }
    }

    private func sameLayout(_ lhs: [HintedElement], _ rhs: [HintedElement]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { a, b in
            a.identity == b.identity
                && a.hint == b.hint
                && a.element.visibleFrame == b.element.visibleFrame
        }
    }

    /// Diff hint views against a new token assignment.
    ///
    /// Views are keyed by `ElementIdentity` so reuse is stable across refreshes
    /// where only the hint token changed — the F06 fix. The diff:
    /// - removes views whose identity is no longer present
    /// - updates the hint text of views whose token changed
    /// - repositions views whose frame changed
    /// - adds views for newly discovered elements
    private func layOutHints(_ newHintedElements: [HintedElement], style: OverlayStyle) {
        let neededIdentities = Set(newHintedElements.map { $0.identity })

        for (identity, view) in hintViews where !neededIdentities.contains(identity) {
            view.removeFromSuperview()
            hintViews[identity] = nil
        }

        self.hintedElements = newHintedElements
        overlapRotationStep = 0

        // A first layout goes through the same builder the debug overlay
        // uses, so debug rectangles match production placement exactly.
        if hintViews.isEmpty {
            let labels = HintLayout.buildLabels(
                for: hintedElements,
                windowSize: self.frame.size,
                previousPlacements: previousPlacements,
                style: style
            )
            for labeled in labels {
                self.contentView?.addSubview(labeled.view)
                hintViews[labeled.hinted.identity] = labeled.view
            }
            snapshotPreviousPlacements()
            bringChromeToFront()
            return
        }

        let obstacles = hintedElements.map { $0.element.visibleFrame }
        var engine = HintPlacementEngine(
            windowSize: self.frame.size,
            elementFrames: obstacles,
            previousPlacements: previousPlacements
        )
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

        snapshotPreviousPlacements()
        bringChromeToFront()
    }

    private func applyContent(_ scene: HintScene, style: OverlayStyle) {
        for (_, highlightView) in elementHighlights {
            highlightView.removeFromSuperview()
        }
        elementHighlights.removeAll()

        switch scene.content {
        case .hints(let labels):
            let visible = Dictionary(labels.map { ($0.identity, $0) }, uniquingKeysWith: { first, _ in first })
            for (identity, view) in hintViews {
                guard !scene.chrome.labelsHidden, let label = visible[identity] else {
                    view.isHidden = true
                    continue
                }
                view.isHidden = false
                guard let textField = MatchHighlightRenderer.findTextField(in: view) else { continue }
                if label.typedPrefix.isEmpty {
                    textField.stringValue = label.token
                    textField.textColor = style.textColor
                } else {
                    MatchHighlightRenderer.highlightPrefix(
                        in: textField, prefix: label.typedPrefix, hint: label.token, style: style
                    )
                }
            }

        case .numbered(let labels):
            for (_, view) in hintViews { view.isHidden = true }
            let obstacles = labels.map { $0.hinted.element.visibleFrame }
            var engine = HintPlacementEngine(windowSize: self.frame.size, elementFrames: obstacles)
            for label in labels {
                let hintView = HintLabelRenderer.createHintLabel(for: label.hinted, style: style, engine: &engine)
                addHighlight(hintView, for: label.identity)
            }

        case .highlights(let boxes):
            for box in boxes {
                addHighlight(MatchHighlightRenderer.createHighlightView(frame: box.frame), for: box.identity)
            }
            for (_, view) in hintViews { view.isHidden = true }
        }
    }

    /// Two matches can share an identity (same pid, role and rounded frame);
    /// they draw on the same spot, so the later one replaces the earlier
    /// rather than leaving an untracked view behind.
    private func addHighlight(_ view: NSView, for identity: ElementIdentity) {
        elementHighlights[identity]?.removeFromSuperview()
        self.contentView?.addSubview(view)
        elementHighlights[identity] = view
    }

    private func applyChrome(_ scene: HintScene) {
        let previous = renderedScene
        if previous?.chrome.searchText != scene.chrome.searchText {
            searchTextField?.stringValue = scene.chrome.searchText
        }
        if previous?.chrome.matchCount != scene.chrome.matchCount {
            applyMatchCount(scene.chrome.matchCount)
        }
        if previous?.isContinuous != scene.isContinuous {
            applyContinuousMode(scene.isContinuous)
        }
    }

    private func applyMatchCount(_ count: Int) {
        let style = MatchCountPresenter.style(forCount: count)
        matchCountLabel?.stringValue = style.labelText
        matchCountLabel?.textColor = style.labelColor
        matchCountBadge?.isHidden = style.labelText.isEmpty
        matchCountBadge?.layer?.backgroundColor = style.labelColor.withAlphaComponent(0.18).cgColor
        matchCountBadge?.layer?.borderColor = style.labelColor.withAlphaComponent(0.4).cgColor
    }

    private func applyContinuousMode(_ isContinuous: Bool) {
        guard isContinuous else {
            continuousModeIndicator?.removeFromSuperview()
            continuousModeIndicator = nil
            return
        }

        let indicator = continuousModeIndicator ?? NSView()
        let size: CGFloat = 6
        indicator.wantsLayer = true
        indicator.layer?.backgroundColor = NSColor.systemGreen.cgColor
        indicator.layer?.cornerRadius = size / 2

        // Anchor to the left edge of the search bar so the indicator
        // stays visible regardless of focused-window geometry.
        if let bar = searchBarView {
            indicator.frame = CGRect(
                x: bar.frame.minX - size - 6,
                y: bar.frame.midY - size / 2,
                width: size,
                height: size
            )
        }

        if indicator.superview == nil {
            contentView?.addSubview(indicator)
        }
        continuousModeIndicator = indicator
        bringChromeToFront()
    }

    /// Raise all persistent chrome (search bar, match badge, continuous-mode
    /// indicator) above the hint layer so overlap rotation and hint refreshes
    /// never bury them.
    private func bringChromeToFront() {
        guard let contentView else { return }
        if let bar = searchBarView {
            contentView.addSubview(bar, positioned: .above, relativeTo: nil)
        }
        if let indicator = continuousModeIndicator {
            contentView.addSubview(indicator, positioned: .above, relativeTo: nil)
        }
    }

    /// Record the current placement frames keyed by element identity so the
    /// next refresh can bias toward stable positions.
    private func snapshotPreviousPlacements() {
        var snapshot: [ElementIdentity: CGRect] = [:]
        for (identity, view) in hintViews {
            snapshot[identity] = view.frame
        }
        previousPlacements = snapshot
    }

    // MARK: - Overlap cycling

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
            let members = group.memberIndices.map { visibleEntries[$0].view }
            HintOverlapCycler.applyZOrder(to: members, in: containerView, step: overlapRotationStep)
        }

        bringChromeToFront()
    }
}
