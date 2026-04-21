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
    private var isActive = false
    private var currentInput = ""
    private var areas: [ScrollableArea] = []
    private var selectedAreaIndex: Int = -1
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

        // Load settings
        loadSettings()

        // PHASE 1: Quick focus check (5-10ms)
        if let focusedArea = ScrollableAreaService.shared.findFocusedScrollableArea() {
            // Assign hint
            var focusedAreaWithHint = focusedArea
            focusedAreaWithHint.hint = "1"
            areas = [focusedAreaWithHint]
            assignHints()

            print("[HINT] #1 → \(focusedArea.frame)")

            // Create overlay with just the focused area
            overlayWindow = ScrollOverlayWindow(areas: areas)
            overlayWindow?.show()

            // Start intercepting keyboard events — abort if tap creation fails
            guard startEventTap() else {
                overlayWindow?.orderOut(nil)
                overlayWindow?.close()
                overlayWindow = nil
                areas = []
                return
            }

            // Update state after event tap is confirmed
            isActive = true
            currentInput = ""
            selectedAreaIndex = 0
            ScrollModeController.isScrollModeActive = true

            // Auto-select the focused area
            selectArea(at: 0)

            // Start deactivation timer if enabled
            startDeactivationTimer()

            // PHASE 2: Continue progressive discovery in background
            continueProgressiveDiscovery()

            return
        }

        // PHASE 2: No focus found — synchronous progressive discovery on main actor
        // (ScrollableAreaService is @MainActor and AX calls must run on main thread)

        var firstAreaFound = false
        var nextHintNumber = 1
        let maxAreas = 15

        _ = ScrollableAreaService.shared.getScrollableAreas(onAreaFound: { [weak self] area in
            guard let self = self else { return }
            let hintNumber = nextHintNumber
            nextHintNumber += 1

            if !firstAreaFound {
                firstAreaFound = true

                var areaWithHint = area
                areaWithHint.hint = "\(hintNumber)"
                self.areas = [areaWithHint]

                print("[HINT] #\(hintNumber) → \(area.frame)")

                self.overlayWindow = ScrollOverlayWindow(areas: self.areas)
                self.overlayWindow?.show()

                guard self.startEventTap() else {
                    self.overlayWindow?.orderOut(nil)
                    self.overlayWindow?.close()
                    self.overlayWindow = nil
                    self.areas = []
                    return
                }

                self.isActive = true
                self.currentInput = ""
                self.selectedAreaIndex = -1
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
                var areaWithHint = area
                areaWithHint.hint = "\(hintNumber)"
                self.areas.append(areaWithHint)
                self.overlayWindow?.addArea(areaWithHint)

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
        // we pre-loaded in Phase 1.  We therefore evaluate each incoming area against self.areas
        // (our live cross-wave list) using the same ScrollableAreaMerger policy.

        var areasFound = 0
        let maxAreas = 15

        _ = ScrollableAreaService.shared.getScrollableAreas(onAreaFound: { [weak self] area in
            guard let self = self else { return }
            if areasFound >= maxAreas { return }
            areasFound += 1

            let existingFrames = self.areas.map(\.frame)
            let decision = self.merger.decision(for: area.frame, against: existingFrames)

            switch decision {
            case .discard, .nestedInExisting:
                return

            case .replaceExisting(let indices):
                for index in indices.sorted().reversed() {
                    self.overlayWindow?.removeArea(withHint: self.areas[index].hint)
                    self.areas.remove(at: index)
                }
                self.reassignHints()

            case .add:
                break
            }

            var areaWithHint = area
            let nextHint = "\(self.areas.count + 1)"
            areaWithHint.hint = nextHint
            self.areas.append(areaWithHint)
            self.overlayWindow?.addArea(areaWithHint)
            print("[HINT] #\(nextHint) → \(area.frame)")
        }, maxAreas: maxAreas)
    }

    private func deactivateScrollMode() {
        guard isActive else { return }

        // Stop timer
        deactivationTimer?.invalidate()
        deactivationTimer = nil

        // Update static state before stopping the tap so the gate sees false immediately.
        ScrollModeController.isScrollModeActive = false

        // Stop event tap
        eventTap.stop()

        // Close overlay
        if let window = overlayWindow {
            window.orderOut(nil)
            window.close()
        }
        overlayWindow = nil

        // Reset state
        areas = []
        isActive = false
        currentInput = ""
        selectedAreaIndex = -1
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

        // Mirror to CF-thread-readable static so the decoder context is current.
        ScrollModeController.scrollKeysCache = scrollKeys
    }

    private func assignHints() {
        for i in 0..<areas.count {
            areas[i].hint = "\(i + 1)"
        }
    }

    /// Reassign hints after removing nested areas (eliminates gaps in numbering)
    private func reassignHints() {
        for i in 0..<areas.count {
            let oldHint = areas[i].hint
            let newHint = "\(i + 1)"

            if oldHint != newHint {
                areas[i].hint = newHint
                overlayWindow?.updateHint(oldHint: oldHint, newHint: newHint)
            }
        }
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

        currentInput += "\(number)"

        if let index = Int(currentInput), index >= 1 && index <= areas.count {
            let couldExtend = (index * 10) <= areas.count
            if !couldExtend {
                selectArea(at: index - 1)
                currentInput = ""
            }
        } else {
            currentInput = ""
        }
    }

    private func handleArrowKey(_ direction: ClickService.ScrollDirection, isShift: Bool) {
        resetDeactivationTimer()

        // Commit any pending numeric input first
        commitPendingInput()

        if arrowMode == "select" {
            handleArrowSelection(direction: direction)
        } else {
            if selectedAreaIndex >= 0 {
                let speed = isShift ? dashSpeed : scrollSpeed
                performScroll(direction: direction, speed: speed)
            }
        }
    }

    private func handleScrollKey(_ direction: ClickService.ScrollDirection, isShift: Bool) {
        resetDeactivationTimer()

        // Commit any pending numeric input first
        commitPendingInput()

        if selectedAreaIndex >= 0 {
            let speed = isShift ? dashSpeed : scrollSpeed
            performScroll(direction: direction, speed: speed)
        }
    }

    private func handleBackspace() {
        resetDeactivationTimer()

        currentInput = ""
        overlayWindow?.clearSelection()
        selectedAreaIndex = -1
    }

    private func commitPendingInput() {
        guard !currentInput.isEmpty,
              let index = Int(currentInput),
              index >= 1, index <= areas.count else {
            currentInput = ""
            return
        }
        selectArea(at: index - 1)
        currentInput = ""
    }

    private func selectArea(at index: Int) {
        guard index >= 0 && index < areas.count else { return }
        selectedAreaIndex = index
        overlayWindow?.selectArea(at: index)
        print("Selected scroll area \(index + 1)")
    }

    private func handleArrowSelection(direction: ClickService.ScrollDirection) {
        if selectedAreaIndex < 0 {
            selectArea(at: 0)
            return
        }

        var newIndex = selectedAreaIndex

        switch direction {
        case .up, .left:
            newIndex = max(0, selectedAreaIndex - 1)
        case .down, .right:
            newIndex = min(areas.count - 1, selectedAreaIndex + 1)
        }

        selectArea(at: newIndex)
    }

    private func performScroll(direction: ClickService.ScrollDirection, speed: Double) {
        guard selectedAreaIndex >= 0 && selectedAreaIndex < areas.count else { return }

        let area = areas[selectedAreaIndex]
        let clickPoint = ScreenGeometry.appKitCenterToQuartz(area.centerPoint)
        ClickService.shared.scroll(at: clickPoint, direction: direction, speed: speed)
    }
}
