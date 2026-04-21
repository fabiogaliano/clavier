//
//  HintOverlayWindow.swift
//  clavier
//
//  Transparent overlay window for displaying hints
//

import AppKit
import SwiftUI

// Snapshot of appearance preferences, read once per activation/refresh
private struct HintStyle {
    let fontSize: CGFloat
    let backgroundColor: NSColor
    let borderColor: NSColor
    let textColor: NSColor
    let bgOpacity: CGFloat
    let bdrOpacity: CGFloat
    let horizontalOffset: CGFloat

    init() {
        let size = UserDefaults.standard.double(forKey: AppSettings.Keys.hintSize)
        fontSize = size > 0 ? CGFloat(size) : CGFloat(AppSettings.Defaults.hintSize)
        let bgHex = UserDefaults.standard.string(forKey: AppSettings.Keys.hintBackgroundHex) ?? AppSettings.Defaults.hintBackgroundHex
        let brHex = UserDefaults.standard.string(forKey: AppSettings.Keys.hintBorderHex) ?? AppSettings.Defaults.hintBorderHex
        let txHex = UserDefaults.standard.string(forKey: AppSettings.Keys.hintTextHex) ?? AppSettings.Defaults.hintTextHex
        backgroundColor = NSColor(hex: bgHex)
        borderColor = NSColor(hex: brHex)
        textColor = NSColor(hex: txHex)
        let bgOp = UserDefaults.standard.double(forKey: AppSettings.Keys.hintBackgroundOpacity)
        bgOpacity = bgOp > 0 ? CGFloat(bgOp) : CGFloat(AppSettings.Defaults.hintBackgroundOpacity)
        let bdOp = UserDefaults.standard.double(forKey: AppSettings.Keys.hintBorderOpacity)
        bdrOpacity = bdOp > 0 ? CGFloat(bdOp) : CGFloat(AppSettings.Defaults.hintBorderOpacity)
        horizontalOffset = CGFloat(UserDefaults.standard.double(forKey: AppSettings.Keys.hintHorizontalOffset))
    }
}

@MainActor
class HintOverlayWindow: NSWindow {

    private var hintedElements: [HintedElement]
    /// Keyed by stable element identity so view reuse survives hint-token
    /// reassignment across session refreshes (F06).
    private var hintViews: [ElementIdentity: NSView] = [:]
    private var elementHighlights: [UUID: NSView] = [:]
    private var searchBarView: NSView?
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
        self.isReleasedWhenClosed = false // We manage lifecycle manually

        setupHintViews()
        setupSearchBar()
    }

    override var canBecomeKey: Bool {
        return false
    }

    override var canBecomeMain: Bool {
        return false
    }

    private func setupHintViews() {
        let containerView = NSView(frame: CGRect(origin: .zero, size: self.frame.size))
        containerView.wantsLayer = true

        let style = HintStyle()
        var engine = HintPlacementEngine(windowSize: self.frame.size)
        for hintedElement in hintedElements {
            let hintView = createHintLabel(for: hintedElement, style: style, engine: &engine)
            containerView.addSubview(hintView)
            hintViews[hintedElement.identity] = hintView
        }

        self.contentView = containerView
    }

    private func createHintLabel(for hintedElement: HintedElement, style: HintStyle, engine: inout HintPlacementEngine) -> NSView {
        let label = NSTextField(labelWithString: hintedElement.hint)
        label.font = NSFont.monospacedSystemFont(ofSize: style.fontSize, weight: .bold)
        label.textColor = style.textColor
        label.backgroundColor = .clear
        label.isBordered = false
        label.isBezeled = false
        label.drawsBackground = false
        label.alignment = .center
        label.wantsLayer = true
        // Add subtle shadow for better legibility
        label.shadow = {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.shadowBlurRadius = 2
            return shadow
        }()

        label.sizeToFit()

        let padding: CGFloat = 2
        let width = label.frame.width + padding * 2
        let height = label.frame.height + padding

        // Create glass container using NSVisualEffectView
        let glassContainer = NSVisualEffectView(frame: .zero)
        glassContainer.material = .hudWindow
        glassContainer.blendingMode = .behindWindow
        glassContainer.state = .active
        glassContainer.wantsLayer = true
        glassContainer.layer?.cornerRadius = 3
        glassContainer.layer?.masksToBounds = true
        glassContainer.layer?.borderWidth = 1
        glassContainer.layer?.borderColor = style.borderColor.withAlphaComponent(style.bdrOpacity).cgColor

        // Add subtle tint overlay for accent color
        let tintOverlay = NSView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        tintOverlay.wantsLayer = true
        tintOverlay.layer?.backgroundColor = style.backgroundColor.withAlphaComponent(style.bgOpacity).cgColor

        // Position label within container
        label.frame = CGRect(x: 0, y: 0, width: width, height: height)

        glassContainer.addSubview(tintOverlay)
        glassContainer.addSubview(label)

        let hintFrame = engine.place(
            element: hintedElement.element,
            labelSize: CGSize(width: width, height: height),
            horizontalOffset: style.horizontalOffset
        )

        glassContainer.frame = hintFrame

        return glassContainer
    }

    private func setupSearchBar() {
        // The search bar is intentionally anchored to the main display (the screen
        // with the menu bar) because it is a global UI element the user types into,
        // regardless of which display the hinted elements are on.
        let mainFrame = NSScreen.main?.frame ?? .zero
        let windowOrigin = ScreenGeometry.desktopBoundsInAppKit.origin

        // Create container view for search bar
        let containerWidth: CGFloat = 300
        let containerHeight: CGFloat = 40
        // Center horizontally on the main display, translated to window-local coords.
        let containerX = mainFrame.minX + (mainFrame.width - containerWidth) / 2 - windowOrigin.x
        let containerY: CGFloat = 80 - windowOrigin.y // Near bottom of main display

        // Create visual effect view for glass background
        let visualEffectView = NSVisualEffectView(frame: CGRect(x: containerX, y: containerY, width: containerWidth, height: containerHeight))
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 10
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.layer?.borderWidth = 1.5
        visualEffectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor

        // Create search text field (display only)
        let textField = NSTextField(labelWithString: "")
        textField.font = NSFont.monospacedSystemFont(ofSize: 16, weight: .medium)
        textField.textColor = .white
        textField.backgroundColor = .clear
        textField.isBordered = false
        textField.alignment = .center
        textField.frame = CGRect(x: 10, y: 8, width: containerWidth - 80, height: 24)
        textField.placeholderString = "Type to search..."
        textField.placeholderAttributedString = NSAttributedString(
            string: "Type to search...",
            attributes: [.foregroundColor: NSColor.white.withAlphaComponent(0.5), .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)]
        )

        // Create match count label
        let countLabel = NSTextField(labelWithString: "")
        countLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        countLabel.textColor = .systemYellow
        countLabel.backgroundColor = .clear
        countLabel.isBordered = false
        countLabel.alignment = .right
        countLabel.frame = CGRect(x: containerWidth - 70, y: 10, width: 60, height: 20)

        visualEffectView.addSubview(textField)
        visualEffectView.addSubview(countLabel)

        self.searchBarView = visualEffectView
        self.searchTextField = textField
        self.matchCountLabel = countLabel

        self.contentView?.addSubview(visualEffectView)
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
            // Hide count
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
        // Clear all hint views
        hintViews.removeAll()
        self.contentView?.subviews.forEach { $0.removeFromSuperview() }
        self.orderOut(nil)
        super.close()
    }

    /// Diff the overlay against a new hint assignment list.
    ///
    /// Views are keyed by `ElementIdentity` so reuse is stable across refreshes
    /// where only the hint token changed — the F06 bug this fixes.  The diff:
    /// - removes views whose identity is no longer present
    /// - updates the hint text of views whose token changed
    /// - repositions views whose frame changed
    /// - adds views for newly discovered elements
    func updateHints(with newHintedElements: [HintedElement]) {
        // Clear element highlights
        for (_, view) in elementHighlights { view.removeFromSuperview() }
        elementHighlights.removeAll()

        let neededIdentities = Set(newHintedElements.map { $0.identity })

        // Remove views no longer needed
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
                // Update hint text if the token was reassigned
                if let textField = findTextField(in: existingView) {
                    textField.stringValue = hintedElement.hint
                }
                // Reposition to reflect any frame change
                let newFrame = engine.place(
                    element: hintedElement.element,
                    labelSize: existingView.frame.size,
                    horizontalOffset: style.horizontalOffset
                )
                existingView.frame = newFrame
            } else {
                let hintView = createHintLabel(for: hintedElement, style: style, engine: &engine)
                self.contentView?.addSubview(hintView)
                hintViews[identity] = hintView
            }
        }

        // Reset search bar state
        updateSearchBar(text: "")
        updateMatchCount(-1)

        self.contentView?.needsDisplay = true
        self.displayIfNeeded()
    }

    func filterHints(matching prefix: String) {
        filterHints(matching: prefix, textMatches: [], numberedMode: false)
    }

    func filterHints(matching prefix: String, textMatches: [HintedElement], numberedMode: Bool = false) {
        // Clear existing highlights
        for (_, highlightView) in elementHighlights {
            highlightView.removeFromSuperview()
        }
        elementHighlights.removeAll()

        let textHex = UserDefaults.standard.string(forKey: AppSettings.Keys.hintTextHex) ?? AppSettings.Defaults.hintTextHex
        let textColor = NSColor(hex: textHex)

        // If we have text matches
        if !textMatches.isEmpty {
            if numberedMode {
                // Numbered hints mode - show numbered hints instead of green highlights
                // Hide all alphabetic hint labels
                for (_, view) in hintViews {
                    view.isHidden = true
                }

                // Create numbered hint views for each match
                let style = HintStyle()
                var engine = HintPlacementEngine(windowSize: self.frame.size)
                for hintedElement in textMatches {
                    let hintView = createHintLabel(for: hintedElement, style: style, engine: &engine)
                    self.contentView?.addSubview(hintView)
                    elementHighlights[hintedElement.element.id] = hintView
                }
            } else {
                // Regular text search - show green highlight boxes
                for hintedElement in textMatches {
                    let highlightView = createHighlightView(for: hintedElement.element)
                    self.contentView?.addSubview(highlightView)
                    elementHighlights[hintedElement.element.id] = highlightView
                }
                // Hide all hint labels when showing text matches
                for (_, view) in hintViews {
                    view.isHidden = true
                }
            }
        } else {
            // Filter hint labels by prefix using the identity-keyed cache.
            // Each hint label's token is read from the text field so we don't
            // need a separate identity→hint lookup table.
            for (identity, view) in hintViews {
                guard let hintedElement = hintedElements.first(where: { $0.identity == identity }) else {
                    view.isHidden = true
                    continue
                }
                let hint = hintedElement.hint
                if prefix.isEmpty {
                    view.isHidden = false
                    // Reset text color to custom color
                    if let textField = findTextField(in: view) {
                        textField.textColor = textColor
                    }
                } else if hint.hasPrefix(prefix) {
                    view.isHidden = false
                    // Highlight matched portion
                    if let textField = findTextField(in: view) {
                        highlightPrefix(in: textField, prefix: prefix, hint: hint)
                    }
                } else {
                    view.isHidden = true
                }
            }
        }
    }

    private func findTextField(in view: NSView) -> NSTextField? {
        // If it's already an NSTextField, return it
        if let textField = view as? NSTextField {
            return textField
        }
        // Otherwise search subviews (for glass container structure)
        for subview in view.subviews {
            if let textField = subview as? NSTextField {
                return textField
            }
        }
        return nil
    }

    private func createHighlightView(for element: UIElement) -> NSView {
        let localFrame = ScreenGeometry.toWindowLocal(element.visibleFrame.insetBy(dx: -2, dy: -2))
        let highlightView = NSView(frame: localFrame)
        highlightView.wantsLayer = true
        highlightView.layer?.borderWidth = 3
        highlightView.layer?.borderColor = NSColor.systemGreen.cgColor
        highlightView.layer?.cornerRadius = 4
        highlightView.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.1).cgColor
        return highlightView
    }

    private func highlightPrefix(in textField: NSTextField?, prefix: String, hint: String) {
        guard let textField = textField else { return }

        let highlightHex = UserDefaults.standard.string(forKey: AppSettings.Keys.highlightTextHex) ?? AppSettings.Defaults.highlightTextHex
        let textHex = UserDefaults.standard.string(forKey: AppSettings.Keys.hintTextHex) ?? AppSettings.Defaults.hintTextHex
        let highlightColor = NSColor(hex: highlightHex)
        let textColor = NSColor(hex: textHex)

        let attributedString = NSMutableAttributedString(string: hint)

        // Matched portion in highlight color
        attributedString.addAttribute(.foregroundColor, value: highlightColor, range: NSRange(location: 0, length: prefix.count))

        // Remaining portion in text color
        if prefix.count < hint.count {
            attributedString.addAttribute(.foregroundColor, value: textColor, range: NSRange(location: prefix.count, length: hint.count - prefix.count))
        }

        textField.attributedStringValue = attributedString
    }
}
