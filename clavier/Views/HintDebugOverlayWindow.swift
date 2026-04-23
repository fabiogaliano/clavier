//
//  HintDebugOverlayWindow.swift
//  clavier
//
//  Visual companion to `HintDebugSnapshot`.  Shows every visited AX
//  node as a color-coded numbered rectangle so the user can point at a
//  specific region ("the red 47 under the URL bar") and Claude can
//  cross-reference the matching record in the JSON snapshot.
//
//  Colors match the event outcome:
//    - green  : accepted (got a hint)
//    - yellow : acceptedDeduped (suppressed by ancestor match)
//    - orange : rejectedTooSmall (clickable but < 5pt)
//    - red    : rejectedNotClickable (clickability policy failed)
//    - gray   : clippedOffscreen (walker bailed before recursing)
//
//  A small pruned-subtree indicator is drawn on nodes whose
//  `childrenVisited == false` (other than clipped), so the user can see
//  which containers cut the traversal short.
//

import AppKit

@MainActor
final class HintDebugOverlayWindow: NSWindow {

    private let events: [HintDiscoveryEvent]
    private let labeledHints: [HintLayout.LabeledView]
    private let snapshotPath: String?

    /// `labeledHints` are the exact views production would render for this
    /// discovery pass.  Attaching them on top of the debug rectangles lets
    /// the user visually compare a node id to the token bubble that would
    /// sit at that position — making placement bugs distinguishable from
    /// discovery or assignment bugs.
    init(
        events: [HintDiscoveryEvent],
        labeledHints: [HintLayout.LabeledView],
        snapshotPath: String?
    ) {
        self.events = events
        self.labeledHints = labeledHints
        self.snapshotPath = snapshotPath

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

        setupContent()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show() {
        self.orderFrontRegardless()
    }

    override func close() {
        self.contentView?.subviews.forEach { $0.removeFromSuperview() }
        self.orderOut(nil)
        super.close()
    }

    private func setupContent() {
        let container = NSView(frame: CGRect(origin: .zero, size: self.frame.size))
        container.wantsLayer = true

        for event in events {
            // Skip nodes with no visible extent — they'd produce zero-area
            // rectangles that just add noise.  Clipped nodes keep their
            // rect; everything else must have area to be meaningful.
            let frame = ScreenGeometry.toWindowLocal(event.frameAppKit)
            if frame.width < 1 || frame.height < 1 { continue }

            let box = DebugNodeView(frame: frame, event: event)
            container.addSubview(box)
        }

        // Overlay the production hint bubbles on top of the rectangles.
        // The views come from `HintLayout.buildLabels` — the same helper
        // `HintOverlayWindow` calls — so they are literally what hint mode
        // would render.  They already carry window-local frames, so we
        // just hand them to the container.
        for labeled in labeledHints {
            container.addSubview(labeled.view)
        }

        container.addSubview(makeBanner())

        self.contentView = container
    }

    private func makeBanner() -> NSView {
        let width: CGFloat = 620
        let height: CGFloat = 56
        let desktop = self.frame
        let banner = NSVisualEffectView(
            frame: NSRect(
                x: desktop.width / 2 - width / 2,
                y: desktop.height - height - 24,
                width: width,
                height: height
            )
        )
        banner.material = .hudWindow
        banner.blendingMode = .behindWindow
        banner.state = .active
        banner.wantsLayer = true
        banner.layer?.cornerRadius = 10
        banner.layer?.borderWidth = 1
        banner.layer?.borderColor = NSColor.separatorColor.cgColor

        let title = NSTextField(labelWithString: "clavier — hint discovery debug  (ESC to exit)")
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        title.frame = NSRect(x: 14, y: 30, width: width - 28, height: 18)
        banner.addSubview(title)

        let legend = Self.summaryLine(events: events)
        let legendField = NSTextField(labelWithString: legend)
        legendField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        legendField.textColor = .secondaryLabelColor
        legendField.frame = NSRect(x: 14, y: 12, width: width - 28, height: 16)
        banner.addSubview(legendField)

        if let path = snapshotPath {
            let pathField = NSTextField(labelWithString: "📄 \(path) (path copied to clipboard)")
            pathField.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
            pathField.textColor = .tertiaryLabelColor
            pathField.frame = NSRect(x: 14, y: -4, width: width - 28, height: 14)
            banner.addSubview(pathField)
        }

        return banner
    }

    private static func summaryLine(events: [HintDiscoveryEvent]) -> String {
        var accepted = 0, deduped = 0, tooSmall = 0, rejected = 0, clipped = 0, pruned = 0
        for e in events {
            switch e.outcome {
            case .accepted: accepted += 1
            case .acceptedDeduped: deduped += 1
            case .rejectedTooSmall: tooSmall += 1
            case .rejectedNotClickable: rejected += 1
            case .clippedOffscreen: clipped += 1
            }
            if !e.childrenVisited && e.outcome != .clippedOffscreen { pruned += 1 }
        }
        return
            "visited:\(events.count)  "
            + "🟢\(accepted)  "
            + "🟡\(deduped)  "
            + "🟠\(tooSmall)  "
            + "🔴\(rejected)  "
            + "⚫\(clipped)  "
            + "✂︎\(pruned)"
    }
}

/// Per-node rectangle view.  Custom-drawn so the color-coded border and
/// the id number stay legible at small sizes.
@MainActor
private final class DebugNodeView: NSView {

    private let event: HintDiscoveryEvent

    init(frame: NSRect, event: HintDiscoveryEvent) {
        self.event = event
        super.init(frame: frame)
        self.wantsLayer = true
        self.layer?.borderWidth = 1
        self.layer?.borderColor = borderColor(for: event).withAlphaComponent(0.9).cgColor
        self.layer?.backgroundColor = borderColor(for: event).withAlphaComponent(0.08).cgColor

        // Label in the top-left of each rect showing the sequence id.
        // Using a stacked NSTextField rather than drawRect so very small
        // rects still show a readable number (label clips gracefully).
        let label = NSTextField(labelWithString: "\(event.id)")
        label.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold)
        label.textColor = textColor(for: event)
        label.backgroundColor = NSColor.black.withAlphaComponent(0.55)
        label.drawsBackground = true
        label.isBezeled = false
        label.isEditable = false
        label.sizeToFit()
        var lf = label.frame
        lf.origin = NSPoint(x: 1, y: max(1, frame.height - lf.height - 1))
        label.frame = lf
        self.addSubview(label)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { false }

    private func borderColor(for event: HintDiscoveryEvent) -> NSColor {
        switch event.outcome {
        case .accepted: return .systemGreen
        case .acceptedDeduped: return .systemYellow
        case .rejectedTooSmall: return .systemOrange
        case .rejectedNotClickable: return .systemRed
        case .clippedOffscreen: return .systemGray
        }
    }

    private func textColor(for event: HintDiscoveryEvent) -> NSColor {
        switch event.outcome {
        case .accepted: return .white
        case .acceptedDeduped: return .white
        case .rejectedTooSmall: return .white
        case .rejectedNotClickable: return .white
        case .clippedOffscreen: return .white
        }
    }
}
