//
//  HintModeController.swift
//  clavier
//
//  Orchestration-only entry point for hint mode.
//
//  Wires: GlobalHotkeyRegistrar → event tap → HintInputDecoder
//       → HintInputReducer → [HintSideEffect] → HintOverlayRenderer
//                                              → HintRefreshCoordinator
//                                              → ClickService / AXPress
//

import Foundation
import AppKit

@MainActor
class HintModeController {

    private var session: HintSession = .inactive
    private var previousElementCount = 0

    // Auto-deactivation timer (continuous mode)
    private var deactivationTimer: Timer?
    private var autoDeactivation = false
    private var deactivationDelay: Double = 5.0

    // Settings loaded at activation, valid for the lifetime of that session
    private var inputContext = HintInputContext(
        textSearchEnabled: true,
        minSearchChars: 2,
        refreshTrigger: "rr"
    )

    // CF run loop-readable scalars (see threading note in CLAUDE.md)
    private nonisolated(unsafe) static var isHintModeActive = false
    private nonisolated(unsafe) static var isTextSearchActive = false
    private nonisolated(unsafe) static var numberedElementsCount = 0

    // Shared input infrastructure (P2-S1)
    private let hotkeyRegistrar = GlobalHotkeyRegistrar(signature: "KNAV", hotkeyID: 1)
    private let eventTap = KeyboardEventTap(slotIndex: 0)

    // Decomposed modules (P4-S2)
    private let renderer = HintOverlayRenderer()
    private let refreshCoordinator = HintRefreshCoordinator(timingPolicy: AppTimingRegistry.shared)

    // Static back-reference for the CF run loop callback path
    private static var sharedInstance: HintModeController?

    // MARK: - Convenience accessors

    private var isActive: Bool { session.isActive }
    private var currentFilter: String { session.filter }
    private var hintedElements: [HintedElement] { session.hintedElements }

    // MARK: - Registration

    func registerGlobalHotkey() {
        HintModeController.sharedInstance = self
        hotkeyRegistrar.register(
            keyCodeKey: AppSettings.Keys.hintShortcutKeyCode,
            modifiersKey: AppSettings.Keys.hintShortcutModifiers,
            onActivation: { [weak self] in self?.toggleHintMode() }
        )
    }

    func toggleHintMode() {
        if isActive {
            deactivateHintMode()
        } else {
            activateHintMode()
        }
    }

    // MARK: - Lifecycle

    private func activateHintMode() {
        guard !isActive else { return }

        loadSessionSettings()

        let discoveredElements = AccessibilityService.shared.getClickableElements()
        guard !discoveredElements.isEmpty else { return }

        let hintedElements = assignHints(to: discoveredElements)

        renderer.open(session: .active(hintedElements: hintedElements, filter: ""))

        guard startEventTap() else {
            print("⚠️ Failed to create event tap. Check Accessibility permissions in System Settings > Privacy & Security > Accessibility.")
            renderer.close()
            return
        }

        session = .active(hintedElements: hintedElements, filter: "")
        previousElementCount = hintedElements.count
        HintModeController.isHintModeActive = true

        startDeactivationTimer()
        scheduleMainActorHydration()
    }

    private func deactivateHintMode() {
        guard isActive else { return }

        HintModeController.isHintModeActive = false
        HintModeController.isTextSearchActive = false
        HintModeController.numberedElementsCount = 0

        deactivationTimer?.invalidate()
        deactivationTimer = nil

        refreshCoordinator.cancelPending()
        eventTap.stop()
        renderer.close()

        session = .inactive
    }

    // MARK: - Hint refresh (used by refresh coordinator callback and manual refresh)

    /// Identifies which refresh path is running so logging stays distinguishable
    /// between continuous-mode post-click refreshes and the explicit "rr" trigger.
    private enum RefreshKind {
        case continuous
        case manual
    }

    /// Shared refresh body: re-query elements, re-assign hints, re-render.
    ///
    /// Returns the new element count (0 when the refresh bailed into deactivation).
    @discardableResult
    private func runRefresh(_ kind: RefreshKind) -> Int {
        guard isActive else { return 0 }

        let start = CFAbsoluteTimeGetCurrent()
        let newElements = AccessibilityService.shared.getClickableElements()
        guard !newElements.isEmpty else {
            deactivateHintMode()
            return 0
        }

        if kind == .continuous {
            let queryEnd = CFAbsoluteTimeGetCurrent()
            print("[CONTINUOUS] Query elements: \(String(format: "%.0f", (queryEnd - start) * 1000))ms")
        }

        let newHintedElements = assignHints(to: newElements)
        previousElementCount = newElements.count
        session = .active(hintedElements: newHintedElements, filter: "")

        let overlayStart = CFAbsoluteTimeGetCurrent()
        renderer.updateHints(with: newHintedElements)

        switch kind {
        case .continuous:
            let overlayEnd = CFAbsoluteTimeGetCurrent()
            print("[CONTINUOUS] Update overlay: \(String(format: "%.0f", (overlayEnd - overlayStart) * 1000))ms")
        case .manual:
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            print("[MANUAL] Refreshed \(newElements.count) elements in \(String(format: "%.0f", elapsed))ms\n")
        }

        startDeactivationTimer()
        scheduleMainActorHydration()

        return newElements.count
    }

    // MARK: - Side effect execution

    private func applyEffects(_ effects: [HintSideEffect]) {
        for effect in effects {
            switch effect {
            case .performClick(let element):
                // Reset tap state before clicking so number keys are not intercepted
                // during the refresh window that follows.
                HintModeController.isTextSearchActive = false
                HintModeController.numberedElementsCount = 0
                executeClick(on: element)

            case .performRightClick(let element):
                HintModeController.isTextSearchActive = false
                HintModeController.numberedElementsCount = 0
                executeRightClick(on: element)

            case .deactivate:
                deactivateHintMode()

            case .updateOverlay(let session):
                renderer.present(session: session)
                syncTapState(from: session)

            case .showSearchBar(let text):
                renderer.updateSearchBar(text: text)

            case .updateMatchCount(let count):
                renderer.updateMatchCount(count)

            case .scheduleRefresh:
                handlePostClick()

            case .manualRefresh:
                runRefresh(.manual)
            }
        }
    }

    private func syncTapState(from session: HintSession) {
        // Only expose numbered mode to the event tap when the numbered matches are
        // actually in 1-9 range — >9 matches show green highlights but don't use
        // number key selection (matching the pre-refactor behaviour).
        let numberedCount = session.numberedElements.count
        let inNumberedMode = numberedCount > 0 && numberedCount <= 9
        HintModeController.isTextSearchActive = inNumberedMode
        HintModeController.numberedElementsCount = inNumberedMode ? numberedCount : 0
    }

    // MARK: - Event tap

    @discardableResult
    private func startEventTap() -> Bool {
        let eventMask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        )

        return eventTap.start(
            eventMask: eventMask,
            isActiveGate: { HintModeController.isHintModeActive },
            handler: { type, event in
                let context = HintInputDecoder.Context(
                    isTextSearchActive: HintModeController.isTextSearchActive,
                    numberedElementsCount: HintModeController.numberedElementsCount
                )
                let command = HintInputDecoder.decode(type: type, event: event, context: context)

                switch command {
                case .passThrough:
                    return Unmanaged.passRetained(event)

                case .clearSearch:
                    DispatchQueue.main.async {
                        HintModeController.sharedInstance?.dispatch(.clearSearch)
                    }
                    return Unmanaged.passRetained(event)

                default:
                    DispatchQueue.main.async {
                        HintModeController.sharedInstance?.dispatch(command)
                    }
                    return nil
                }
            }
        )
    }

    // MARK: - Dispatch (main actor command entry)

    private func dispatch(_ command: HintInputCommand) {
        guard isActive else { return }
        let (nextSession, effects) = HintInputReducer.reduce(
            session: session,
            command: command,
            context: inputContext
        )
        session = nextSession
        applyEffects(effects)
    }

    // MARK: - Click execution

    private func executeClick(on element: UIElement) {
        HintActionPerformer.performPrimary(on: element)
        startDeactivationTimer()
    }

    private func executeRightClick(on element: UIElement) {
        HintActionPerformer.performSecondary(on: element)
        startDeactivationTimer()
    }

    // MARK: - Post-click

    private func handlePostClick() {
        let continuousMode = UserDefaults.standard.bool(forKey: AppSettings.Keys.continuousClickMode)
        if continuousMode {
            scheduleRefresh()
        } else {
            deactivateHintMode()
        }
    }

    private func scheduleRefresh() {
        print("[CONTINUOUS] Click performed, starting refresh...")
        let capturedCount = previousElementCount
        if case .active(let elements, _) = session {
            session = .active(hintedElements: elements, filter: "")
        }
        refreshCoordinator.scheduleRefresh(previousCount: capturedCount) { [weak self] in
            self?.runRefresh(.continuous) ?? 0
        }
    }

    // MARK: - Hint assignment

    /// Assign hint tokens to discovered elements for a session.
    ///
    /// Reads the current alphabet from `AppSettings` and delegates to
    /// `HintAssigner` (pure mapping — no AX / UserDefaults interior state).
    private func assignHints(to elements: [UIElement]) -> [HintedElement] {
        HintAssigner.assign(to: elements, alphabet: AppSettings.hintCharacters)
    }

    // MARK: - Text attribute hydration

    /// Schedule a main-actor hydration pass that fills in `textAttributes`
    /// on each discovered element for text-search lookups.
    ///
    /// The AX API requires main-thread access (see claudedocs/api-research.md),
    /// so the hop here is *not* about moving work off-main — it is purely about
    /// yielding to the current run loop turn so the overlay paints first, then
    /// performing the AX reads synchronously on the main actor.  The name
    /// `scheduleMainActorHydration` is kept deliberately unambiguous about that.
    private func scheduleMainActorHydration() {
        Task { @MainActor in
            var domainElements = self.hintedElements.map { $0.element }
            AXTextHydrator.hydrate(&domainElements)
            guard self.isActive else { return }
            let updatedHinted = zip(self.hintedElements, domainElements).map { hinted, updated in
                HintedElement(element: updated, hint: hinted.hint)
            }
            switch self.session {
            case .active(_, let filter):
                self.session = .active(hintedElements: updatedHinted, filter: filter)
            case .textSearch(_, let matches, let filter):
                let matchIDs = Set(matches.map { $0.identity })
                let updatedMatches = updatedHinted.filter { matchIDs.contains($0.identity) }
                self.session = .textSearch(hintedElements: updatedHinted, matches: updatedMatches, filter: filter)
            case .inactive:
                break
            }
        }
    }

    // MARK: - Auto-deactivation

    private func startDeactivationTimer() {
        let continuousMode = UserDefaults.standard.bool(forKey: AppSettings.Keys.continuousClickMode)
        guard continuousMode && autoDeactivation else { return }

        deactivationTimer?.invalidate()
        deactivationTimer = Timer.scheduledTimer(withTimeInterval: deactivationDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.deactivateHintMode()
            }
        }
    }

    private func loadSessionSettings() {
        autoDeactivation = UserDefaults.standard.bool(forKey: AppSettings.Keys.autoHintDeactivation)
        deactivationDelay = UserDefaults.standard.double(forKey: AppSettings.Keys.hintDeactivationDelay)
        if deactivationDelay == 0 { deactivationDelay = 5.0 }

        inputContext = HintInputContext(
            textSearchEnabled: UserDefaults.standard.bool(forKey: AppSettings.Keys.textSearchEnabled),
            minSearchChars: AppSettings.minSearchCharacters,
            refreshTrigger: AppSettings.manualRefreshTrigger
        )
    }
}
