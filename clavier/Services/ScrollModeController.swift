//
//  ScrollModeController.swift
//  clavier
//
//  Orchestration-only entry point for scroll mode.
//
//  Wires: GlobalHotkeyRegistrar → event tap → ScrollInputDecoder
//       → ScrollSelectionReducer → [ScrollSideEffect]
//       → ScrollCommandExecutor     (scroll events)
//       → ScrollDiscoveryCoordinator (two-phase area discovery)
//       → ScrollOverlayRenderer     (overlay updates)
//

import Foundation
import AppKit
import Carbon
import os

@MainActor
class ScrollModeController {

    private let renderer = ScrollOverlayRenderer()
    private var session: ScrollSession = .inactive
    private var deactivationTimer: Timer?
    private var activationStart = Date()

    // CF run-loop readable scalars (see CLAUDE.md threading note).
    private nonisolated(unsafe) static var isScrollModeActive = false
    private nonisolated(unsafe) static var scrollKeysCache = "hjkl"

    // Back-reference for CF run-loop callback dispatch.
    private static var sharedInstance: ScrollModeController?

    // Shared input infrastructure
    private let hotkeyRegistrar = GlobalHotkeyRegistrar(signature: "SCRL", hotkeyID: 2)
    private let eventTap = KeyboardEventTap(slotIndex: 1)

    // Decomposed scroll modules (P4-S3)
    private let discoveryCoordinator = ScrollDiscoveryCoordinator(
        service: ScrollableAreaService.shared,
        merger: ScrollableAreaMerger()
    )
    private let commandExecutor = ScrollCommandExecutor(clickService: ClickService.shared)

    // Session settings (main-actor only; refreshed at each activation)
    private var inputContext = ScrollInputContext(
        scrollKeys: .default,
        arrowMode: AppSettings.Defaults.scrollArrowMode,
        scrollSpeed: AppSettings.Defaults.scrollSpeed,
        dashSpeed: AppSettings.Defaults.dashSpeed,
        autoDeactivation: AppSettings.Defaults.autoScrollDeactivation,
        deactivationDelay: AppSettings.Defaults.scrollDeactivationDelay
    )

    // MARK: - Convenience accessors

    private var isActive: Bool { session.isActive }
    private var areas: [NumberedArea] { session.areas }
    private var selectedIndex: Int? { session.selectedIndex }

    // MARK: - Registration

    func registerGlobalHotkey() {
        ScrollModeController.sharedInstance = self
        hotkeyRegistrar.register(
            keyCodeKey: AppSettings.Keys.scrollShortcutKeyCode,
            modifiersKey: AppSettings.Keys.scrollShortcutModifiers,
            onActivation: { [weak self] in self?.toggleScrollMode() }
        )
    }

    func toggleScrollMode() {
        if isActive {
            deactivateScrollMode()
        } else {
            activateScrollMode()
        }
    }

    // MARK: - Lifecycle

    private func activateScrollMode() {
        guard !isActive else { return }

        loadSettings()

        activationStart = Date()

        discoveryCoordinator.discover { [weak self] event in
            guard let self else { return }
            let (nextSession, effects) = ScrollSelectionReducer.reduce(session: self.session, discovery: event)
            self.session = nextSession
            self.applyEffects(effects)
        }
    }

    /// Open the overlay window for the session's areas and start the event tap.
    ///
    /// Returns false if the tap failed to start (permission denied); in that case the
    /// session is reset to `.inactive` and the caller should not proceed.
    private func openOverlayAndStartTap() -> Bool {
        renderer.open(initialAreas: areas)

        guard startEventTap() else {
            renderer.close()
            session = .inactive
            return false
        }

        ScrollModeController.isScrollModeActive = true
        startDeactivationTimer()

        let elapsed = Date().timeIntervalSince(activationStart)
        Logger.scrollMode.debug("scroll mode activated with first area in \(Int(elapsed * 1000), privacy: .public)ms")
        return true
    }

    private func deactivateScrollMode() {
        // Gated on the static flag rather than `session.isActive` because the
        // reducer sets `session = .inactive` before `applyEffects` fires
        // `.deactivate`; a session-based guard would early-return here and
        // leak the event tap + overlay.
        guard ScrollModeController.isScrollModeActive else { return }

        deactivationTimer?.invalidate()
        deactivationTimer = nil

        ScrollModeController.isScrollModeActive = false

        eventTap.stop()

        renderer.close()

        session = .inactive
    }

    // MARK: - Event tap

    @discardableResult
    private func startEventTap() -> Bool {
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        let started = eventTap.start(
            eventMask: eventMask,
            isActiveGate: { ScrollModeController.isScrollModeActive },
            handler: { type, event in
                let context = ScrollInputDecoder.Context(
                    scrollKeys: ScrollModeController.scrollKeysCache
                )
                let command = ScrollInputDecoder.decode(type: type, event: event, context: context)

                DispatchQueue.main.async {
                    ScrollModeController.sharedInstance?.dispatch(command)
                }
                return nil
            }
        )

        if !started {
            Logger.scrollMode.warning("Failed to create event tap for scroll mode. Check Accessibility permissions in System Settings > Privacy & Security > Accessibility.")
        }
        return started
    }

    // MARK: - Dispatch (main actor command entry)

    private func dispatch(_ command: ScrollInputCommand) {
        guard isActive else { return }

        let (nextSession, effects) = ScrollSelectionReducer.reduce(
            session: session,
            command: command,
            context: inputContext
        )
        session = nextSession
        applyEffects(effects)
    }

    // MARK: - Side effect execution

    private func applyEffects(_ effects: [ScrollSideEffect]) {
        for effect in effects {
            switch effect {
            case .performScroll(let direction, let speed):
                executeScroll(direction: direction, speed: speed)

            case .deactivate:
                deactivateScrollMode()

            case .selectArea(let index):
                selectArea(at: index)

            case .updateNumber(let identity, let newNumber):
                renderer.updateNumber(forIdentity: identity, newNumber: newNumber)

            case .resetDeactivationTimer:
                resetDeactivationTimer()

            case .clearSelection:
                renderer.clearSelection()

            case .openOverlay:
                if let first = areas.first {
                    Logger.scrollMode.debug("hint #1 → \(String(describing: first.area.frame), privacy: .public)")
                }
                // Later effects assume a live overlay and an active session.
                guard openOverlayAndStartTap() else { return }

            case .addArea(let numbered):
                renderer.addArea(numbered)
                Logger.scrollMode.debug("hint #\(numbered.number, privacy: .public) → \(String(describing: numbered.area.frame), privacy: .public)")

            case .removeArea(let identity):
                renderer.removeArea(withIdentity: identity)
            }
        }
    }

    // MARK: - Selection

    private func selectArea(at index: Int) {
        guard case .active(let current, _, _) = session,
              index >= 0 && index < current.count else { return }
        session = .active(areas: current, selected: index, pendingInput: "")
        renderer.selectArea(at: index)
        Logger.scrollMode.debug("selected scroll area \(index + 1, privacy: .public)")
    }

    // MARK: - Scroll execution

    private func executeScroll(direction: ScrollDirection, speed: Double) {
        guard let idx = selectedIndex, idx < areas.count else { return }
        let area = areas[idx]
        let clickPoint = ScreenGeometry.appKitCenterToQuartz(area.area.centerPoint)
        commandExecutor.execute(direction: direction, speed: speed, at: clickPoint)
    }

    // MARK: - Settings

    private func loadSettings() {
        let scrollKeys = AppSettings.scrollKeys
        let arrowMode = AppSettings.scrollArrowMode
        let scrollSpeed = UserDefaults.standard.double(forKey: AppSettings.Keys.scrollSpeed)
        let dashSpeed = UserDefaults.standard.double(forKey: AppSettings.Keys.dashSpeed)
        let autoDeactivation = UserDefaults.standard.bool(forKey: AppSettings.Keys.autoScrollDeactivation)
        let deactivationDelay = UserDefaults.standard.double(forKey: AppSettings.Keys.scrollDeactivationDelay)

        inputContext = ScrollInputContext(
            scrollKeys: scrollKeys,
            arrowMode: arrowMode,
            scrollSpeed: scrollSpeed == 0 ? AppSettings.Defaults.scrollSpeed : scrollSpeed,
            dashSpeed: dashSpeed == 0 ? AppSettings.Defaults.dashSpeed : dashSpeed,
            autoDeactivation: autoDeactivation,
            deactivationDelay: deactivationDelay == 0 ? AppSettings.Defaults.scrollDeactivationDelay : deactivationDelay
        )

        ScrollModeController.scrollKeysCache = scrollKeys.rawString
    }

    // MARK: - Deactivation timer

    private func startDeactivationTimer() {
        guard inputContext.autoDeactivation else { return }

        deactivationTimer?.invalidate()
        deactivationTimer = Timer.scheduledTimer(
            withTimeInterval: inputContext.deactivationDelay,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.deactivateScrollMode()
            }
        }
    }

    private func resetDeactivationTimer() {
        guard inputContext.autoDeactivation else { return }
        startDeactivationTimer()
    }
}
