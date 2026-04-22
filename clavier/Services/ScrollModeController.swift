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

        let activationStart = Date()
        var tapStarted = false

        discoveryCoordinator.discover { [weak self] event in
            guard let self else { return }

            switch event {
            case .areaAddedPhase1(let area):
                guard self.openOverlayAndStartTap(firstArea: area, activationStart: activationStart) else { return }
                tapStarted = true
                // Phase 1 always auto-selects: the focused area is the user's clear intent.
                self.selectArea(at: 0)
                Logger.scrollMode.debug("auto-selected first area (focused area)")

            case .areaAddedPhase2(let area, let isCursorInside):
                if !tapStarted {
                    guard self.openOverlayAndStartTap(firstArea: area, activationStart: activationStart) else { return }
                    tapStarted = true
                    if isCursorInside {
                        self.selectArea(at: 0)
                        Logger.scrollMode.debug("auto-selected first area via cursor position")
                    }
                } else {
                    self.appendArea(area)
                }

            case .areaReplaced(let area, let replacedIndices, let isCursorInside):
                guard tapStarted else { return }
                self.removeAreas(at: replacedIndices)
                self.appendArea(area)
                if isCursorInside && self.selectedIndex == nil {
                    let newIndex = self.areas.count - 1
                    self.selectArea(at: newIndex)
                }
            }
        }
    }

    /// Open the overlay window and start the event tap for the first discovered area.
    ///
    /// Returns false if the tap failed to start (permission denied); in that case the
    /// session is reset to `.inactive` and the caller should not proceed.
    private func openOverlayAndStartTap(firstArea: ScrollableArea, activationStart: Date) -> Bool {
        let numbered = NumberedArea(area: firstArea, number: "1")
        session = .active(areas: [numbered], selected: nil, pendingInput: "")

        Logger.scrollMode.debug("hint #1 → \(String(describing: firstArea.frame), privacy: .public)")

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

    /// Append a new area to the end of the current session and update the overlay.
    private func appendArea(_ area: ScrollableArea) {
        let nextNumber = "\(areas.count + 1)"
        let numbered = NumberedArea(area: area, number: nextNumber)
        if case .active(let current, let sel, let input) = session {
            session = .active(areas: current + [numbered], selected: sel, pendingInput: input)
        }
        renderer.addArea(numbered)
        Logger.scrollMode.debug("hint #\(nextNumber, privacy: .public) → \(String(describing: area.frame), privacy: .public)")
    }

    /// Remove areas at the given indices and reassign contiguous numbers.
    ///
    /// The coordinator's `replacedIndices` are indices into `crossWaveFrames`,
    /// which mirrors the controller's session areas list.
    private func removeAreas(at indices: [Int]) {
        for index in indices.sorted().reversed() {
            guard case .active(var current, var sel, let input) = session,
                  index < current.count else { continue }
            let removedIdentity = current[index].identity
            renderer.removeArea(withIdentity: removedIdentity)
            current.remove(at: index)
            if let s = sel {
                if index < s { sel = s - 1 }
                else if index == s { sel = nil }
            }
            session = .active(areas: current, selected: sel, pendingInput: input)
        }
        reassignNumbers()
    }

    private func deactivateScrollMode() {
        guard isActive else { return }

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

    // MARK: - Number reassignment

    /// Reassign sequential numbers after a replaceExisting merge removes areas.
    private func reassignNumbers() {
        guard case .active(var current, let sel, let input) = session else { return }
        for i in 0..<current.count {
            let newNumber = "\(i + 1)"
            if current[i].number != newNumber {
                let oldIdentity = current[i].identity
                current[i] = NumberedArea(area: current[i].area, number: newNumber)
                renderer.updateNumber(forIdentity: oldIdentity, newNumber: newNumber)
            }
        }
        session = .active(areas: current, selected: sel, pendingInput: input)
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
