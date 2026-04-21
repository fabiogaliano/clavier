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
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hotKeyRef: EventHotKeyRef?
    private var deactivationTimer: Timer?

    // Callback-visible state: only simple scalars that are practically atomic on arm64.
    private nonisolated(unsafe) static var isScrollModeActive = false
    private nonisolated(unsafe) static var currentEventTap: CFMachPort?

    // Static reference for C callback
    private static var sharedInstance: ScrollModeController?

    // Carbon event handler installed once, reused across hotkey re-registrations
    private var eventHandlerRef: EventHandlerRef?

    // Settings cache
    private var scrollKeys = "hjkl"
    private var arrowMode = "select"
    private var scrollSpeed: Double = 5.0
    private var dashSpeed: Double = 9.0
    private var autoDeactivation = true
    private var deactivationDelay: Double = 5.0

    func registerGlobalHotkey() {
        ScrollModeController.sharedInstance = self

        // Install Carbon event handler once
        if eventHandlerRef == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

            InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
                guard let userData = userData, let event = event else { return OSStatus(eventNotHandledErr) }

                var pressedHotKeyID = EventHotKeyID()
                let err = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressedHotKeyID
                )

                guard err == noErr else { return OSStatus(eventNotHandledErr) }

                let expectedSignature = OSType("KSCR".utf8.reduce(0) { ($0 << 8) + OSType($1) })
                guard pressedHotKeyID.signature == expectedSignature && pressedHotKeyID.id == 2 else {
                    return OSStatus(eventNotHandledErr)
                }

                let controller = Unmanaged<ScrollModeController>.fromOpaque(userData).takeUnretainedValue()

                Task { @MainActor in
                    controller.toggleScrollMode()
                }
                return noErr
            }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandlerRef)
        }

        // Listen for hotkey disable/enable notifications
        NotificationCenter.default.addObserver(
            forName: .disableGlobalHotkeys,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.unregisterHotkey()
        }

        NotificationCenter.default.addObserver(
            forName: .enableGlobalHotkeys,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.registerHotkeyInternal()
        }

        registerHotkeyInternal()
    }

    private func registerHotkeyInternal() {
        guard hotKeyRef == nil else { return }

        let keyCode = UserDefaults.standard.integer(forKey: AppSettings.Keys.scrollShortcutKeyCode)
        let modifiers = UserDefaults.standard.integer(forKey: AppSettings.Keys.scrollShortcutModifiers)

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType("KSCR".utf8.reduce(0) { ($0 << 8) + OSType($1) })
        hotKeyID.id = 2

        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func unregisterHotkey() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
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

        let focusedAreaFrame = areas.first?.frame
        var areasFound = 0
        let maxAreas = 15

        _ = ScrollableAreaService.shared.getScrollableAreas(onAreaFound: { [weak self] area in
            guard let self = self else { return }
            if areasFound >= maxAreas { return }
            areasFound += 1

            // Skip if this is the focused area we already have
            if let focusedFrame = focusedAreaFrame,
               abs(area.frame.origin.x - focusedFrame.origin.x) < 10 &&
               abs(area.frame.origin.y - focusedFrame.origin.y) < 10 &&
               abs(area.frame.width - focusedFrame.width) < 10 &&
               abs(area.frame.height - focusedFrame.height) < 10 {
                return
            }

            // Check relationships with existing areas
            var shouldAddNewArea = true
            var removedAreas: [(index: Int, hint: String)] = []

            for (index, existing) in self.areas.enumerated() {
                if abs(area.frame.origin.x - existing.frame.origin.x) < 10 &&
                   abs(area.frame.origin.y - existing.frame.origin.y) < 10 &&
                   abs(area.frame.width - existing.frame.width) < 10 &&
                   abs(area.frame.height - existing.frame.height) < 10 {
                    shouldAddNewArea = false
                    break
                }

                if area.frame.minX >= existing.frame.minX - 5 &&
                   area.frame.maxX <= existing.frame.maxX + 5 &&
                   area.frame.minY >= existing.frame.minY - 5 &&
                   area.frame.maxY <= existing.frame.maxY + 5 {

                    let sameXOrigin = abs(area.frame.origin.x - existing.frame.origin.x) < 2
                    if sameXOrigin {
                        shouldAddNewArea = false
                        break
                    }

                    let newSize = area.frame.width * area.frame.height
                    let existingSize = existing.frame.width * existing.frame.height
                    if newSize / existingSize > 0.7 {
                        shouldAddNewArea = false
                        break
                    }
                }

                if existing.frame.minX >= area.frame.minX - 5 &&
                   existing.frame.maxX <= area.frame.maxX + 5 &&
                   existing.frame.minY >= area.frame.minY - 5 &&
                   existing.frame.maxY <= area.frame.maxY + 5 {

                    let sameXOrigin = abs(area.frame.origin.x - existing.frame.origin.x) < 2
                    if sameXOrigin {
                        removedAreas.append((index, existing.hint))
                    } else {
                        let existingSize = existing.frame.width * existing.frame.height
                        let newSize = area.frame.width * area.frame.height
                        if existingSize / newSize > 0.7 {
                            removedAreas.append((index, existing.hint))
                        }
                    }
                }

                if abs(area.frame.origin.x - existing.frame.origin.x) < 10 &&
                   abs(area.frame.width - existing.frame.width) < 10 &&
                   abs(area.frame.origin.y - existing.frame.origin.y) >= 10 {

                    let newSize = area.frame.width * area.frame.height
                    let existingSize = existing.frame.width * existing.frame.height
                    if newSize > existingSize {
                        removedAreas.append((index, existing.hint))
                    } else {
                        shouldAddNewArea = false
                        break
                    }
                }
            }

            if !shouldAddNewArea { return }

            if !removedAreas.isEmpty {
                for (index, hint) in removedAreas.reversed() {
                    self.overlayWindow?.removeArea(withHint: hint)
                    self.areas.remove(at: index)
                }
                self.reassignHints()
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

        // Update static state
        ScrollModeController.isScrollModeActive = false

        // Stop event tap
        stopEventTap()

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
    }

    private func assignHints() {
        for i in 0..<areas.count {
            areas[i].hint = "\(i + 1)"
        }
    }

    /// Reassign hints after removing nested areas (eliminates gaps in numbering)
    private func reassignHints() {
        // Reassign sequential hints
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

    @discardableResult
    private func startEventTap() -> Bool {
        let eventMask = (1 << CGEventType.keyDown.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (_, type, event, _) -> Unmanaged<CGEvent>? in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = ScrollModeController.currentEventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passRetained(event)
                }

                guard ScrollModeController.isScrollModeActive else {
                    return Unmanaged.passRetained(event)
                }

                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags

                // Escape key (53)
                if keyCode == 53 {
                    DispatchQueue.main.async {
                        ScrollModeController.sharedInstance?.deactivateScrollMode()
                    }
                    return nil
                }

                // Process input on main thread
                DispatchQueue.main.async {
                    ScrollModeController.sharedInstance?.handleKeyPress(keyCode: keyCode, flags: flags)
                }

                return nil // Consume all keys in scroll mode
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap = eventTap else {
            print("⚠️ Failed to create event tap for scroll mode. Check Accessibility permissions in System Settings > Privacy & Security > Accessibility.")
            return false
        }

        ScrollModeController.currentEventTap = eventTap

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return true
    }

    private func stopEventTap() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        ScrollModeController.currentEventTap = nil
    }

    private func handleKeyPress(keyCode: Int64, flags: CGEventFlags) {
        resetDeactivationTimer()

        let isShift = flags.contains(.maskShift)

        // Number keys (0-9) for area selection
        if let number = keyCodeToNumber(keyCode) {
            currentInput += "\(number)"

            if let index = Int(currentInput), index >= 1 && index <= areas.count {
                // Commit immediately if this number can't be a prefix of a larger valid area
                let couldExtend = (index * 10) <= areas.count
                if !couldExtend {
                    selectArea(at: index - 1)
                    currentInput = ""
                }
            } else {
                currentInput = ""
            }
            return
        }

        // Commit pending numeric input before processing non-digit keys
        if !currentInput.isEmpty, let index = Int(currentInput), index >= 1 && index <= areas.count {
            selectArea(at: index - 1)
            currentInput = ""
        }

        // Arrow keys
        if let arrowDirection = keyCodeToArrowDirection(keyCode) {
            if arrowMode == "select" {
                // Arrow keys select areas
                handleArrowSelection(direction: arrowDirection)
            } else {
                // Arrow keys scroll
                if selectedAreaIndex >= 0 {
                    let speed = isShift ? dashSpeed : scrollSpeed
                    performScroll(direction: arrowDirection, speed: speed)
                }
            }
            return
        }

        // hjkl scroll keys
        if let scrollDirection = keyCodeToScrollDirection(keyCode) {
            if selectedAreaIndex >= 0 {
                let speed = isShift ? dashSpeed : scrollSpeed
                performScroll(direction: scrollDirection, speed: speed)
            }
            return
        }

        // Backspace (51) - clear input
        if keyCode == 51 {
            currentInput = ""

            overlayWindow?.clearSelection()
            selectedAreaIndex = -1
            return
        }
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

    private func keyCodeToNumber(_ keyCode: Int64) -> Int? {
        let numberMap: [Int64: Int] = [
            18: 1, 19: 2, 20: 3, 21: 4, 23: 5,
            22: 6, 26: 7, 28: 8, 25: 9, 29: 0
        ]
        return numberMap[keyCode]
    }

    private func keyCodeToArrowDirection(_ keyCode: Int64) -> ClickService.ScrollDirection? {
        switch keyCode {
        case 126: return .up
        case 125: return .down
        case 123: return .left
        case 124: return .right
        default: return nil
        }
    }

    private func keyCodeToScrollDirection(_ keyCode: Int64) -> ClickService.ScrollDirection? {
        guard scrollKeys.count == 4 else { return nil }

        let chars = Array(scrollKeys.lowercased())
        let leftKey = chars[0]   // h
        let downKey = chars[1]   // j
        let upKey = chars[2]     // k
        let rightKey = chars[3]  // l

        guard let character = Self.keyCodeToCharacter(keyCode)?.lowercased() else { return nil }

        if character == String(leftKey) { return .left }
        if character == String(downKey) { return .down }
        if character == String(upKey) { return .up }
        if character == String(rightKey) { return .right }

        return nil
    }

    nonisolated private static func keyCodeToCharacter(_ keyCode: Int64) -> String? {
        let keyMap: [Int64: String] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
            8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
            16: "y", 17: "t", 31: "o", 32: "u", 34: "i", 35: "p", 37: "l",
            38: "j", 40: "k", 45: "n", 46: "m"
        ]
        return keyMap[keyCode]
    }
}
