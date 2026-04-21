//
//  ScrollModeController.swift
//  clavier
//
//  Orchestrates scroll mode activation and keyboard input
//

import Foundation
import AppKit
import Carbon

@MainActor
class ScrollModeController {

    private var overlayWindow: ScrollOverlayWindow?
    private var session: ScrollSession = .inactive
    private var deactivationTimer: Timer?

    // Callback-visible state: only simple scalars that are practically atomic on arm64.
    // Read on the CF run loop thread from the isActiveGate closure and the tap handler.
    private nonisolated(unsafe) static var isScrollModeActive = false

    // Retained for the CF-thread dispatch path inside KeyboardEventTap's handler closure.
    private static var sharedInstance: ScrollModeController?

    private let merger = ScrollableAreaMerger()

    // Shared input infrastructure (P2-S3)
    private let hotkeyRegistrar = GlobalHotkeyRegistrar(signature: "SCRL", hotkeyID: 2)
    private let eventTap = KeyboardEventTap(slotIndex: 1)

    // Scroll-decoder context accessible from the CF run loop thread.
    // Refreshed from UserDefaults when scroll mode activates (main thread only).
    private nonisolated(unsafe) static var scrollKeysCache = "hjkl"

    // Settings cache (main thread only)
    private var scrollKeys = "hjkl"
    private var arrowMode = "select"
    private var scrollSpeed: Double = 5.0
    private var dashSpeed: Double = 9.0
    private var autoDeactivation = true
    private var deactivationDelay: Double = 5.0

    // MARK: - Convenience accessors into session

    private var isActive: Bool { session.isActive }
    private var areas: [NumberedArea] { session.areas }
    private var selectedIndex: Int? { session.selectedIndex }

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

    private func activateScrollMode() {
        let activationStartTime = Date()
        guard !isActive else { return }

        loadSettings()

        // PHASE 1: Quick focus check (5-10ms)
        if let focusedArea = ScrollableAreaService.shared.findFocusedScrollableArea() {
            let numbered = NumberedArea(area: focusedArea, number: "1")
            session = .active(areas: [numbered], selected: nil, pendingInput: "")

            print("[HINT] #1 → \(focusedArea.frame)")

            overlayWindow = ScrollOverlayWindow(numberedAreas: areas)
            overlayWindow?.show()

            guard startEventTap() else {
                overlayWindow?.orderOut(nil)
                overlayWindow?.close()
                overlayWindow = nil
                session = .inactive
                return
            }

            ScrollModeController.isScrollModeActive = true

            selectArea(at: 0)
            startDeactivationTimer()

            continueProgressiveDiscovery()
            return
        }

        // PHASE 2: No focus found — synchronous progressive discovery on main actor
        var firstAreaFound = false
        var nextHintNumber = 1
        let maxAreas = 15

        _ = ScrollableAreaService.shared.getScrollableAreas(onAreaFound: { [weak self] area in
            guard let self = self else { return }
            let hintNumber = nextHintNumber
            nextHintNumber += 1

            if !firstAreaFound {
                firstAreaFound = true

                let numbered = NumberedArea(area: area, number: "\(hintNumber)")
                self.session = .active(areas: [numbered], selected: nil, pendingInput: "")

                print("[HINT] #\(hintNumber) → \(area.frame)")

                self.overlayWindow = ScrollOverlayWindow(numberedAreas: self.areas)
                self.overlayWindow?.show()

                guard self.startEventTap() else {
                    self.overlayWindow?.orderOut(nil)
                    self.overlayWindow?.close()
                    self.overlayWindow = nil
                    self.session = .inactive
                    return
                }

                ScrollModeController.isScrollModeActive = true
                self.startDeactivationTimer()

                let initialElapsed = Date().timeIntervalSince(activationStartTime)
                print("[PERF] Scroll mode activated with first area in \(String(format: "%.2f", initialElapsed * 1000))ms")

                let cursorLocation = NSEvent.mouseLocation
                if area.frame.contains(cursorLocation) {
                    self.selectArea(at: 0)
                    print("[PERF] Auto-selected first area via cursor position")
                }
            } else {
                let numbered = NumberedArea(area: area, number: "\(hintNumber)")
                if case .active(let current, let sel, let input) = self.session {
                    self.session = .active(areas: current + [numbered], selected: sel, pendingInput: input)
                }
                self.overlayWindow?.addArea(numbered)

                print("[HINT] #\(hintNumber) → \(area.frame)")
            }
        }, maxAreas: maxAreas)
    }

    private func continueProgressiveDiscovery() {
        // Run on main actor — ScrollableAreaService is @MainActor and AX calls must run on main thread.
        // The onAreaFound callback fires inline during traversal, providing progressive UI updates.
        //
        // The service's shouldAddArea gate already deduplicates areas within a single traversal
        // wave, but it starts with an empty local list and therefore cannot see the focused area
        // we pre-loaded in Phase 1.  We therefore evaluate each incoming area against our live
        // cross-wave list using the same ScrollableAreaMerger policy.

        var areasFound = 0
        let maxAreas = 15

        _ = ScrollableAreaService.shared.getScrollableAreas(onAreaFound: { [weak self] area in
            guard let self = self else { return }
            if areasFound >= maxAreas { return }
            areasFound += 1

            let existingFrames = self.areas.map(\.area.frame)
            let decision = self.merger.decision(for: area.frame, against: existingFrames)

            switch decision {
            case .discard, .nestedInExisting:
                return

            case .replaceExisting(let indices):
                for index in indices.sorted().reversed() {
                    if case .active(var current, var sel, let input) = self.session {
                        let removedIdentity = current[index].identity
                        self.overlayWindow?.removeArea(withIdentity: removedIdentity)
                        current.remove(at: index)
                        // Shift selected index down if the removed area was before it
                        if let s = sel {
                            if index < s {
                                sel = s - 1
                            } else if index == s {
                                sel = nil
                            }
                        }
                        self.session = .active(areas: current, selected: sel, pendingInput: input)
                    }
                }
                self.reassignNumbers()

            case .add:
                break
            }

            let nextNumber = "\(self.areas.count + 1)"
            let numbered = NumberedArea(area: area, number: nextNumber)
            if case .active(let current, let sel, let input) = self.session {
                self.session = .active(areas: current + [numbered], selected: sel, pendingInput: input)
            }
            self.overlayWindow?.addArea(numbered)
            print("[HINT] #\(nextNumber) → \(area.frame)")
        }, maxAreas: maxAreas)
    }

    private func deactivateScrollMode() {
        guard isActive else { return }

        deactivationTimer?.invalidate()
        deactivationTimer = nil

        // Update static state before stopping the tap so the gate sees false immediately.
        ScrollModeController.isScrollModeActive = false

        eventTap.stop()

        if let window = overlayWindow {
            window.orderOut(nil)
            window.close()
        }
        overlayWindow = nil

        session = .inactive
    }

    private func loadSettings() {
        scrollKeys = AppSettings.scrollKeys
        arrowMode = AppSettings.scrollArrowMode
        scrollSpeed = UserDefaults.standard.double(forKey: AppSettings.Keys.scrollSpeed)
        dashSpeed = UserDefaults.standard.double(forKey: AppSettings.Keys.dashSpeed)
        autoDeactivation = UserDefaults.standard.bool(forKey: AppSettings.Keys.autoScrollDeactivation)
        deactivationDelay = UserDefaults.standard.double(forKey: AppSettings.Keys.scrollDeactivationDelay)

        if scrollSpeed == 0 { scrollSpeed = 5.0 }
        if dashSpeed == 0 { dashSpeed = 9.0 }
        if deactivationDelay == 0 { deactivationDelay = 5.0 }

        ScrollModeController.scrollKeysCache = scrollKeys
    }

    /// Reassign sequential numbers after a replaceExisting merge removes areas.
    ///
    /// Gaps in numbering are eliminated so visible hints remain contiguous
    /// (1, 2, 3… rather than 1, 3, 4…).
    private func reassignNumbers() {
        guard case .active(var current, let sel, let input) = session else { return }
        for i in 0..<current.count {
            let newNumber = "\(i + 1)"
            if current[i].number != newNumber {
                let oldIdentity = current[i].identity
                current[i] = NumberedArea(area: current[i].area, number: newNumber)
                overlayWindow?.updateNumber(forIdentity: oldIdentity, newNumber: newNumber)
            }
        }
        session = .active(areas: current, selected: sel, pendingInput: input)
    }

    private func startDeactivationTimer() {
        guard autoDeactivation else { return }

        deactivationTimer?.invalidate()
        deactivationTimer = Timer.scheduledTimer(withTimeInterval: deactivationDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.deactivateScrollMode()
            }
        }
    }

    private func resetDeactivationTimer() {
        guard autoDeactivation else { return }
        startDeactivationTimer()
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

                switch command {
                case .escape:
                    DispatchQueue.main.async {
                        ScrollModeController.sharedInstance?.deactivateScrollMode()
                    }
                    return nil

                case .backspace:
                    DispatchQueue.main.async {
                        ScrollModeController.sharedInstance?.handleBackspace()
                    }
                    return nil

                case .digit(let n):
                    DispatchQueue.main.async {
                        ScrollModeController.sharedInstance?.handleDigit(n)
                    }
                    return nil

                case .arrowKey(let direction, let isShift):
                    DispatchQueue.main.async {
                        ScrollModeController.sharedInstance?.handleArrowKey(direction, isShift: isShift)
                    }
                    return nil

                case .scrollKey(let direction, let isShift):
                    DispatchQueue.main.async {
                        ScrollModeController.sharedInstance?.handleScrollKey(direction, isShift: isShift)
                    }
                    return nil

                case .consume:
                    return nil
                }
            }
        )

        if !started {
            print("⚠️ Failed to create event tap for scroll mode. Check Accessibility permissions in System Settings > Privacy & Security > Accessibility.")
        }
        return started
    }

    // MARK: - Input handling (main thread only)

    private func handleDigit(_ number: Int) {
        resetDeactivationTimer()

        guard case .active(let current, let sel, let pending) = session else { return }
        let newInput = pending + "\(number)"

        if let index = Int(newInput), index >= 1 && index <= current.count {
            let couldExtend = (index * 10) <= current.count
            if !couldExtend {
                selectArea(at: index - 1)
                // selectArea updates session; wipe pending input there
            } else {
                session = .active(areas: current, selected: sel, pendingInput: newInput)
            }
        } else {
            // Input doesn't match any area — clear pending
            session = .active(areas: current, selected: sel, pendingInput: "")
        }
    }

    private func handleArrowKey(_ direction: ClickService.ScrollDirection, isShift: Bool) {
        resetDeactivationTimer()

        commitPendingInput()

        if arrowMode == "select" {
            handleArrowSelection(direction: direction)
        } else {
            if selectedIndex != nil {
                let speed = isShift ? dashSpeed : scrollSpeed
                performScroll(direction: direction, speed: speed)
            }
        }
    }

    private func handleScrollKey(_ direction: ClickService.ScrollDirection, isShift: Bool) {
        resetDeactivationTimer()

        commitPendingInput()

        if selectedIndex != nil {
            let speed = isShift ? dashSpeed : scrollSpeed
            performScroll(direction: direction, speed: speed)
        }
    }

    private func handleBackspace() {
        resetDeactivationTimer()

        if case .active(let current, _, _) = session {
            session = .active(areas: current, selected: nil, pendingInput: "")
        }
        overlayWindow?.clearSelection()
    }

    private func commitPendingInput() {
        guard case .active(let current, let sel, let pending) = session,
              !pending.isEmpty,
              let index = Int(pending),
              index >= 1, index <= current.count else {
            // Clear any dangling pending input
            if case .active(let current, let sel, _) = session {
                session = .active(areas: current, selected: sel, pendingInput: "")
            }
            return
        }
        selectArea(at: index - 1)
    }

    private func selectArea(at index: Int) {
        guard case .active(let current, _, _) = session,
              index >= 0 && index < current.count else { return }
        session = .active(areas: current, selected: index, pendingInput: "")
        overlayWindow?.selectArea(at: index)
        print("Selected scroll area \(index + 1)")
    }

    private func handleArrowSelection(direction: ClickService.ScrollDirection) {
        guard case .active(let current, let sel, _) = session else { return }

        guard let current_sel = sel else {
            selectArea(at: 0)
            return
        }

        let newIndex: Int
        switch direction {
        case .up, .left:
            newIndex = max(0, current_sel - 1)
        case .down, .right:
            newIndex = min(current.count - 1, current_sel + 1)
        }

        selectArea(at: newIndex)
    }

    private func performScroll(direction: ClickService.ScrollDirection, speed: Double) {
        guard let idx = selectedIndex, idx < areas.count else { return }

        let area = areas[idx]
        let clickPoint = ScreenGeometry.appKitCenterToQuartz(area.area.centerPoint)
        ClickService.shared.scroll(at: clickPoint, direction: direction, speed: speed)
    }
}
