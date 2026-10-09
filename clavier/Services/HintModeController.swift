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
import os

@MainActor
class HintModeController {

    private var session: HintSession = .inactive {
        didSet { publishTapContext(for: session) }
    }
    /// True from the moment the tap + overlay are up until they are torn
    /// down.  Distinct from `session.isActive` because the reducer sets
    /// `session = .inactive` before `applyEffects` runs `.deactivate`.
    private var isSessionOpen = false
    /// Captured just before a click so the post-click plan can tell whether
    /// the click opened a popup (and the one-shot session should follow it).
    private var lastClickOpensPopup = false
    private var activationTask: Task<Void, Never>?
    /// Non-nil while text attributes for the current hints are still being
    /// read; a "no matches" result in that window is not yet trustworthy.
    private var hydrationTask: Task<Void, Never>?
    private var continuousUpgradeRequestedWhileActivating = false

    // Auto-deactivation timer (continuous mode)
    private var deactivationTimer: Timer?

    /// Captured at activation, valid for the lifetime of that session.
    private var config = HintSessionConfig.default

    /// The only hint state the CF run-loop tap callback reads.  Published as
    /// one value so the callback can never observe a half-updated mix of
    /// fields; `nil` means no live session, so every event passes through.
    private nonisolated static let tapContext = OSAllocatedUnfairLock<HintInputDecoder.Context?>(initialState: nil)

    // Shared input infrastructure (P2-S1)
    private let hotkeyRegistrar = GlobalHotkeyRegistrar(signature: "KNAV", hotkeyID: 1)
    private let eventTap = KeyboardEventTap(slotIndex: 0)
    private let dismissalMonitor = SessionDismissalMonitor()

    // Decomposed modules (P4-S2)
    private let renderer = HintOverlayRenderer()
    private let refreshCoordinator = HintRefreshCoordinator(timingPolicy: AppTimingRegistry.shared)

    // Static back-reference for the CF run loop callback path
    private static var sharedInstance: HintModeController?

    /// Lets Preferences start a session on its own window as a self-test.
    static var shared: HintModeController? { sharedInstance }

    // MARK: - Convenience accessors

    private var isActive: Bool { session.isActive }
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
            upgradeToContinuous()
            return
        }
        if activationTask != nil {
            continuousUpgradeRequestedWhileActivating = true
            return
        }

        continuousUpgradeRequestedWhileActivating = false
        activationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.activationTask = nil
                self.continuousUpgradeRequestedWhileActivating = false
            }
            await self.activateHintMode()
        }
    }

    // MARK: - Lifecycle

    private func activateHintMode() async {
        guard !isActive else { return }

        config = .load()
        var presentedProvisionalBrowserHints = false

        let discoveredElements = await AccessibilityService.shared.getClickableElementsWhenReady(
            onBrowserRendererPending: { [weak self] nativeElements in
                guard let self else { return }
                presentedProvisionalBrowserHints = self.openInitialSession(
                    with: nativeElements,
                    minimumTokenLength: 3
                )
                if presentedProvisionalBrowserHints {
                    Logger.hintMode.debug(
                        "browser: presented \(nativeElements.count, privacy: .public) native controls while renderer AX settles"
                    )
                }
            }
        )
        guard !Task.isCancelled else { return }

        if presentedProvisionalBrowserHints {
            guard isActive else { return }
            guard !discoveredElements.isEmpty else {
                deactivateHintMode()
                return
            }
            guard session.filter.isEmpty else { return }
            let merged = HintAssigner.assignPreservingHints(
                to: discoveredElements,
                previous: hintedElements,
                alphabet: AppSettings.hintCharacters,
                minimumTokenLength: 3
            )
            session = .active(hintedElements: merged, filter: "", mode: session.mode)
            renderer.updateHints(with: merged)
            Logger.hintMode.debug(
                "browser: merged renderer controls into \(merged.count, privacy: .public) stable hints"
            )
            startDeactivationTimer()
            scheduleMainActorHydration()
            return
        }

        // CEF-app branch: Spotify can't be woken at runtime; if we
        // detect the empty-tree signature there, hand off to the help
        // sheet (which offers a one-click relaunch with the
        // accessibility flag) and don't proceed with normal hint mode.
        if SpotifyAccessibilityHelper.shared.presentIfApplicable(elements: discoveredElements) {
            return
        }

        guard !discoveredElements.isEmpty else { return }
        _ = openInitialSession(with: discoveredElements)
    }

    @discardableResult
    private func openInitialSession(
        with elements: [UIElement],
        minimumTokenLength: Int = 2
    ) -> Bool {
        guard !elements.isEmpty, !isActive else { return false }

        let initialMode: HintSessionMode = continuousUpgradeRequestedWhileActivating
            ? .continuous : config.initialMode
        let hintedElements = HintAssigner.assign(
            to: elements,
            alphabet: AppSettings.hintCharacters,
            minimumTokenLength: minimumTokenLength
        )
        renderer.open(session: .active(hintedElements: hintedElements, filter: "", mode: initialMode))

        guard startEventTap() else {
            Logger.hintMode.warning("Failed to create event tap. Check Accessibility permissions in System Settings > Privacy & Security > Accessibility.")
            renderer.close()
            return false
        }

        isSessionOpen = true
        session = .active(hintedElements: hintedElements, filter: "", mode: initialMode)
        dismissalMonitor.start { [weak self] in self?.dispatch(.dismiss) }

        startDeactivationTimer()
        scheduleMainActorHydration()
        return true
    }

    /// Cancels an activation still in flight too, so a caller that needs
    /// hint mode gone (debug mode's exclusivity) gets it from one call.
    func deactivateHintMode() {
        activationTask?.cancel()
        activationTask = nil

        // A session-based guard would early-return after the reducer's
        // `.inactive` transition and leak the event tap + overlay.
        guard isSessionOpen else { return }
        isSessionOpen = false

        deactivationTimer?.invalidate()
        deactivationTimer = nil

        refreshCoordinator.cancelPending()
        hydrationTask?.cancel()
        hydrationTask = nil
        dismissalMonitor.stop()
        eventTap.stop()
        renderer.close()

        session = .inactive
    }

    // MARK: - Hint refresh

    private var displayedSignature: HintTreeSignature {
        HintTreeSignature(hintedElements.map(\.identity))
    }

    /// Manual refresh ("rr"): re-query immediately and supersede any
    /// post-click sampling still in flight.
    private func refreshNow() {
        guard isActive else { return }
        refreshCoordinator.cancelPending()

        let start = CFAbsoluteTimeGetCurrent()
        let elements = AccessibilityService.shared.getClickableElements()
        guard !elements.isEmpty else {
            deactivateHintMode()
            return
        }
        replaceHints(with: elements)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        Logger.hintMode.debug("manual: refreshed \(elements.count, privacy: .public) elements in \(Int(elapsed), privacy: .public)ms")
    }

    /// One post-click sample: re-query, and re-render only when the element
    /// set actually changed.  Returns nil to stop sampling — the session
    /// ended, or the user is already typing against the hints on screen.
    private func sampleAfterClick() -> HintTreeSignature? {
        guard isActive, session.filter.isEmpty else { return nil }

        let elements = AccessibilityService.shared.getClickableElements()
        guard !elements.isEmpty else {
            deactivateHintMode()
            return nil
        }

        let signature = HintTreeSignature(elements.map(\.stableID))
        if signature != displayedSignature {
            replaceHints(with: elements)
        }
        return signature
    }

    /// Re-render with fresh elements.  Elements still on screen keep their
    /// tokens, so labels don't reshuffle under the user while the UI settles.
    private func replaceHints(with elements: [UIElement]) {
        let hinted = HintAssigner.assignPreservingHints(
            to: elements,
            previous: hintedElements,
            alphabet: AppSettings.hintCharacters
        )
        session = .active(hintedElements: hinted, filter: "", mode: session.mode)
        renderer.updateHints(with: hinted)
        startDeactivationTimer()
        scheduleMainActorHydration()
    }

    // MARK: - Side effect execution

    private func applyEffects(_ effects: [HintSideEffect]) {
        for effect in effects {
            switch effect {
            case .perform(let kind, let element):
                lastClickOpensPopup = HintPostClickPolicy.clickOpensPopup(kind: kind) {
                    HintPopupTriggerProbe.opensPopup(element)
                }
                HintActionPerformer.perform(kind, on: element)
                startDeactivationTimer()

            case .deactivate:
                deactivateHintMode()

            case .updateOverlay(let session):
                renderer.present(session: session)

            case .showSearchBar(let text):
                renderer.updateSearchBar(text: text)

            case .updateMatchCount(let count):
                renderer.updateMatchCount(count, isHydrating: hydrationTask != nil)

            case .scheduleRefresh:
                handlePostClick()

            case .manualRefresh:
                refreshNow()

            case .rotateOverlap:
                renderer.rotateOverlap()

            case .setLabelsHidden(let hidden):
                renderer.setLabelsHidden(hidden)
            }
        }
    }

    private func publishTapContext(for session: HintSession) {
        let context = HintInputDecoder.Context(
            session: session,
            hidePrefix: config.inputContext.hidePrefix,
            hotkey: HotkeyChord(
                keyCodeKey: AppSettings.Keys.hintShortcutKeyCode,
                modifiersKey: AppSettings.Keys.hintShortcutModifiers
            ),
            hintAlphabet: AppSettings.hintCharacters.rawString
        )
        HintModeController.tapContext.withLock { $0 = context }
    }

    // MARK: - Event tap

    @discardableResult
    private func startEventTap() -> Bool {
        let eventMask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        )

        return eventTap.start(
            eventMask: eventMask,
            isActiveGate: { HintModeController.tapContext.withLock { $0 != nil } },
            handler: { type, event in
                // The session can end between the gate and this read.
                guard let context = HintModeController.tapContext.withLock({ $0 }) else {
                    return Unmanaged.passRetained(event)
                }
                let command = HintInputDecoder.decode(type: type, event: event, context: context)

                switch command {
                case .passThrough:
                    return Unmanaged.passRetained(event)

                case .clearSearch, .dismiss:
                    DispatchQueue.main.async {
                        HintModeController.sharedInstance?.dispatch(command)
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

    /// ⌥ clears the search only when tapped on its own.  The decoder reports
    /// the release, so the controller remembers whether ⌥ took part in a
    /// hover chord (⌥+letter, ⌥+Enter) since it went down.
    private var optionChordUsed = false

    private func dispatch(_ command: HintInputCommand) {
        guard isActive else { return }
        switch command {
        case .character(_, modifier: .option), .enter(.option), .selectNumbered(_, modifier: .option):
            optionChordUsed = true
        case .clearSearch:
            if optionChordUsed {
                optionChordUsed = false
                return
            }
        default:
            break
        }
        let (nextSession, effects) = HintInputReducer.reduce(
            session: session,
            command: command,
            context: config.inputContext
        )
        session = nextSession
        applyEffects(effects)
    }

    // MARK: - Post-click

    private func handlePostClick() {
        let plan = HintPostClickPolicy.plan(mode: session.mode, clickOpensPopup: lastClickOpensPopup)
        lastClickOpensPopup = false

        switch plan {
        case .close:
            deactivateHintMode()
        case .refresh(let closeIfUnchanged):
            scheduleRefresh(closeIfUnchanged: closeIfUnchanged)
        }
    }

    private func scheduleRefresh(closeIfUnchanged: Bool) {
        Logger.hintMode.debug("post-click: sampling UI (closeIfUnchanged=\(closeIfUnchanged, privacy: .public))")
        clearFilterAfterClick()
        refreshCoordinator.scheduleRefresh(
            baseline: displayedSignature,
            sample: { [weak self] in self?.sampleAfterClick() },
            completion: { [weak self] outcome in
                guard outcome == .unchanged, closeIfUnchanged else { return }
                self?.deactivateHintMode()
            }
        )
    }

    /// The typed filter has done its job once a click fires.  Reset it (and
    /// any text-search highlight boxes) so the overlay shows the full hint
    /// set and post-click sampling isn't mistaken for the user still typing.
    private func clearFilterAfterClick() {
        guard isActive else { return }
        let cleared = HintSession.active(hintedElements: hintedElements, filter: "", mode: session.mode)
        session = cleared
        renderer.present(session: cleared)
        renderer.updateSearchBar(text: "")
        renderer.updateMatchCount(-1)
        renderer.setLabelsHidden(false)
    }

    // MARK: - Text attribute hydration

    /// Schedule a main-actor hydration pass that fills in `textAttributes`
    /// on each discovered element for text-search lookups.
    ///
    /// The AX API requires main-thread access,
    /// so the hop here is *not* about moving work off-main — it is purely about
    /// yielding to the current run loop turn so the overlay paints first, then
    /// performing the AX reads synchronously on the main actor.  The name
    /// `scheduleMainActorHydration` is kept deliberately unambiguous about that.
    ///
    /// Keys typed before the pass starts are matched against elements with
    /// no text yet, so once it lands the current filter is re-run and the
    /// matches update in place instead of leaving a stale "0".
    private func scheduleMainActorHydration() {
        hydrationTask?.cancel()
        hydrationTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            var domainElements = self.hintedElements.map { $0.element }
            AXTextHydrator.hydrate(&domainElements)
            self.hydrationTask = nil
            guard self.isActive else { return }
            let updatedHinted = zip(self.hintedElements, domainElements).map { hinted, updated in
                HintedElement(element: updated, hint: hinted.hint)
            }
            let filter = self.session.filter
            self.session = .active(hintedElements: updatedHinted, filter: filter, mode: self.session.mode)
            if !filter.isEmpty {
                self.dispatch(.reapplyFilter)
            }
        }
    }

    // MARK: - Auto-deactivation

    private func startDeactivationTimer() {
        guard let delay = config.autoDeactivationDelay(for: session.mode) else { return }

        deactivationTimer?.invalidate()
        deactivationTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.deactivateHintMode()
            }
        }
    }

    private func upgradeToContinuous() {
        guard !session.isContinuous else { return }

        switch session {
        case .inactive:
            return
        case .active(let elements, let filter, _):
            session = .active(hintedElements: elements, filter: filter, mode: .continuous)
        case .textSearch(let elements, let matches, let filter, _):
            session = .textSearch(hintedElements: elements, matches: matches, filter: filter, mode: .continuous)
        }

        renderer.setContinuousMode(true)
        startDeactivationTimer()
    }
}
