//
//  HintModeController.swift
//  clavier
//
//  Orchestrates hint mode activation and keyboard input
//

import Foundation
import AppKit
import Carbon

@MainActor
class HintModeController {

    private var overlayWindow: HintOverlayWindow?
    private var isActive = false
    private var currentInput = ""
    private var elements: [UIElement] = []
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hotKeyRef: EventHotKeyRef?
    private var isTextSearchMode = false
    private var numberedElements: [UIElement] = []
    private var previousElementCount = 0

    // Auto-deactivation timer (for continuous mode)
    private var deactivationTimer: Timer?
    private var autoDeactivation = false
    private var deactivationDelay: Double = 5.0

    // Text search settings (loaded from UserDefaults at activation, used on main thread only)
    private var textSearchEnabled = true
    private var minSearchChars = 2
    private var refreshTrigger = "rr"

    // Default refresh delays for continuous mode
    private static let defaultOptimisticDelay: TimeInterval = 0.050 // 50ms
    private static let defaultFallbackDelay: TimeInterval = 0.100   // 100ms additional

    // Callback-visible state: only simple scalars that are practically atomic on arm64.
    // The callback dispatches ALL string manipulation to main — no shared String state.
    private nonisolated(unsafe) static var isHintModeActive = false
    private nonisolated(unsafe) static var currentEventTap: CFMachPort?
    private nonisolated(unsafe) static var isTextSearchActive = false
    private nonisolated(unsafe) static var numberedElementsCount = 0

    // Static reference for C callback
    private static var sharedInstance: HintModeController?

    // Carbon event handler installed once, reused across hotkey re-registrations
    private var eventHandlerRef: EventHandlerRef?

    func registerGlobalHotkey() {
        HintModeController.sharedInstance = self

        // Install Carbon event handler once — it persists for the app lifetime
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

                let expectedSignature = OSType("KNAV".utf8.reduce(0) { ($0 << 8) + OSType($1) })
                guard pressedHotKeyID.signature == expectedSignature && pressedHotKeyID.id == 1 else {
                    return OSStatus(eventNotHandledErr)
                }

                let controller = Unmanaged<HintModeController>.fromOpaque(userData).takeUnretainedValue()

                Task { @MainActor in
                    controller.toggleHintMode()
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

        let keyCode = UserDefaults.standard.integer(forKey: AppSettings.Keys.hintShortcutKeyCode)
        let modifiers = UserDefaults.standard.integer(forKey: AppSettings.Keys.hintShortcutModifiers)

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType("KNAV".utf8.reduce(0) { ($0 << 8) + OSType($1) })
        hotKeyID.id = 1

        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func unregisterHotkey() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    func toggleHintMode() {
        if isActive {
            deactivateHintMode()
        } else {
            activateHintMode()
        }
    }

    private func activateHintMode() {
        guard !isActive else { return }

        // Load auto-deactivation settings
        loadAutoDeactivationSettings()

        // Get clickable elements
        elements = AccessibilityService.shared.getClickableElements()

        guard !elements.isEmpty else {
            return
        }

        // Assign hints
        assignHints()

        // Show overlay with search bar
        overlayWindow = HintOverlayWindow(elements: elements)
        overlayWindow?.show()

        // Start intercepting keyboard events — abort if tap creation fails
        guard startEventTap() else {
            print("⚠️ Failed to create event tap. Check Accessibility permissions in System Settings > Privacy & Security > Accessibility.")
            overlayWindow?.orderOut(nil)
            overlayWindow?.close()
            overlayWindow = nil
            elements = []
            return
        }

        // Update state after event tap is confirmed
        isActive = true
        currentInput = ""
        previousElementCount = elements.count
        HintModeController.isHintModeActive = true
        textSearchEnabled = UserDefaults.standard.bool(forKey: AppSettings.Keys.textSearchEnabled)
        minSearchChars = AppSettings.minSearchCharacters
        refreshTrigger = AppSettings.manualRefreshTrigger

        // Start auto-deactivation timer (if enabled)
        startDeactivationTimer()

        // Load text attributes in background for text search
        loadTextAttributesAsync()
    }

    private func loadTextAttributesAsync() {
        Task { @MainActor in
            AccessibilityService.shared.loadTextAttributes(for: &self.elements)
        }
    }

    private func deactivateHintMode() {
        guard isActive else { return }

        // Update static state first
        HintModeController.isHintModeActive = false
        HintModeController.isTextSearchActive = false
        HintModeController.numberedElementsCount = 0

        // Stop deactivation timer
        deactivationTimer?.invalidate()
        deactivationTimer = nil

        // Stop event tap
        stopEventTap()

        // Close and remove window
        if let window = overlayWindow {
            window.orderOut(nil)
            window.close()
        }
        overlayWindow = nil

        // Reset state
        elements = []
        isActive = false
        currentInput = ""
        isTextSearchMode = false
        numberedElements = []
    }

    private var refreshStartTime: CFAbsoluteTime = 0

    @discardableResult
    private func performHintRefresh() -> Bool {
        guard isActive else { return false }

        let queryStart = CFAbsoluteTimeGetCurrent()

        // Re-query clickable elements
        let newElements = AccessibilityService.shared.getClickableElements()

        guard !newElements.isEmpty else {
            deactivateHintMode()
            return false
        }

        let queryEnd = CFAbsoluteTimeGetCurrent()
        print("[CONTINUOUS] Query elements: \(String(format: "%.0f", (queryEnd - queryStart) * 1000))ms")

        // Check if UI actually changed (compare element count)
        let uiChanged = newElements.count != previousElementCount

        // Update elements and reassign hints
        self.elements = newElements
        self.previousElementCount = newElements.count
        self.assignHints()

        let overlayStart = CFAbsoluteTimeGetCurrent()
        // Update the overlay window
        self.overlayWindow?.updateHints(with: self.elements)

        let overlayEnd = CFAbsoluteTimeGetCurrent()
        print("[CONTINUOUS] Update overlay: \(String(format: "%.0f", (overlayEnd - overlayStart) * 1000))ms")

        let totalTime = CFAbsoluteTimeGetCurrent() - refreshStartTime
        print("[CONTINUOUS] Total refresh time: \(String(format: "%.0f", totalTime * 1000))ms\n")

        // Restart auto-deactivation timer after refresh
        startDeactivationTimer()

        // Load text attributes for new elements (enables text search)
        self.loadTextAttributesAsync()

        return uiChanged
    }

    private func assignHints() {
        var hintCharacters = AppSettings.hintCharacters
        if hintCharacters.count < 2 { hintCharacters = AppSettings.Defaults.hintCharacters }
        let chars = Array(hintCharacters)
        let count = elements.count

        // Generate hints based on element count
        // Always use 2-letter hints minimum, expand to 3-letter if needed
        var hints: [String] = []

        let n = chars.count
        let twoCharCombos = n * n
        let threeCharCombos = n * n * n
        // Cap at the 3-char alphabet maximum to prevent index overflow on dense pages.
        let hintCount = min(count, threeCharCombos)

        if count <= twoCharCombos {
            for i in 0..<hintCount {
                let first = chars[i / n]
                let second = chars[i % n]
                hints.append("\(first)\(second)")
            }
        } else {
            for i in 0..<hintCount {
                let first = chars[i / (n * n)]
                let second = chars[(i / n) % n]
                let third = chars[i % n]
                hints.append("\(first)\(second)\(third)")
            }
        }

        for i in 0..<hintCount {
            elements[i].hint = hints[i]
        }
        if hintCount < elements.count {
            elements = Array(elements.prefix(hintCount))
        }
    }

    private func assignNumberedHints(to elements: inout [UIElement]) {
        // Assign numbered hints (1-9) to elements
        for i in 0..<min(elements.count, 9) {
            elements[i].hint = "\(i + 1)"
        }
    }

    @discardableResult
    private func startEventTap() -> Bool {
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        // Thin dispatcher: only reads simple scalar statics, dispatches all
        // string/state work to main thread. No shared String mutation.
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (_, type, event, _) -> Unmanaged<CGEvent>? in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = HintModeController.currentEventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passRetained(event)
                }

                guard HintModeController.isHintModeActive else {
                    return Unmanaged.passRetained(event)
                }

                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags

                // Option key press — clear search
                if type == .flagsChanged && (keyCode == 58 || keyCode == 61) {
                    if flags.contains(.maskAlternate) {
                        DispatchQueue.main.async {
                            HintModeController.sharedInstance?.handleClearSearch()
                        }
                    }
                    return Unmanaged.passRetained(event)
                }

                guard type == .keyDown else {
                    return Unmanaged.passRetained(event)
                }

                // ESC — dispatch to main for two-stage handling
                if keyCode == 53 {
                    DispatchQueue.main.async {
                        HintModeController.sharedInstance?.handleEscapeKey()
                    }
                    return nil
                }

                // Enter
                if keyCode == 36 {
                    let hasControl = flags.contains(.maskControl)
                    DispatchQueue.main.async {
                        HintModeController.sharedInstance?.handleEnterKey(withControl: hasControl)
                    }
                    return nil
                }

                // Backspace
                if keyCode == 51 {
                    DispatchQueue.main.async {
                        HintModeController.sharedInstance?.handleBackspace()
                    }
                    return nil
                }

                // Space
                if keyCode == 49 {
                    DispatchQueue.main.async {
                        HintModeController.sharedInstance?.handleCharacterInput(" ")
                    }
                    return nil
                }

                // Number keys during text search
                if HintModeController.isTextSearchActive {
                    let numberKeyMap: [Int64: Int] = [
                        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9
                    ]
                    if let number = numberKeyMap[keyCode], number <= HintModeController.numberedElementsCount {
                        DispatchQueue.main.async {
                            HintModeController.sharedInstance?.selectNumberedElement(number)
                        }
                        return nil
                    }
                }

                // Character keys
                guard var character = HintModeController.keyCodeToCharacter(keyCode) else {
                    return Unmanaged.passRetained(event)
                }

                if keyCode == 27 && flags.contains(.maskShift) {
                    character = "_"
                }

                let lowerChar = character.lowercased()

                guard lowerChar.count == 1,
                      let char = lowerChar.first,
                      char.isLetter || char.isNumber || "-._".contains(char) else {
                    return Unmanaged.passRetained(event)
                }

                DispatchQueue.main.async {
                    HintModeController.sharedInstance?.handleCharacterInput(lowerChar)
                }

                return nil
            },
            userInfo: nil
        )

        guard let eventTap = eventTap else {
            return false
        }

        HintModeController.currentEventTap = eventTap

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
        HintModeController.currentEventTap = nil
    }

    private func processInput(_ input: String) {
        guard isActive else { return }

        currentInput = input

        // Update search bar display
        overlayWindow?.updateSearchBar(text: input)

        // Check for manual refresh trigger
        if input == refreshTrigger {
            print("[MANUAL] Refresh trigger detected: \"\(input)\"")
            clearInputState()
            performManualRefresh()
            return
        }

        // Check for exact hint match first
        if let matchedElement = elements.first(where: { $0.hint == input }) {
            // Update overlay to show the completed match with full highlighting
            overlayWindow?.filterHints(matching: input, textMatches: [])
            // Perform click
            performClick(on: matchedElement)
            // Immediately clear input state before handling post-click
            clearInputState()
            handlePostClick()
            return
        }

        // Check if input matches any hint prefixes
        let hintMatchingElements = elements.filter { $0.hint.hasPrefix(input) }

        if !hintMatchingElements.isEmpty {
            // Update overlay to show only matching hints
            overlayWindow?.filterHints(matching: input, textMatches: [])
            return
        }

        // If no hint matches, try text search (if enabled and input is long enough)
        if textSearchEnabled && input.count >= minSearchChars {
            var textMatches = searchElementsByText(input)

            if textMatches.count == 1 {
                // Single match - auto-click
                performClick(on: textMatches[0])
                // Immediately clear input state before handling post-click
                clearInputState()
                handlePostClick()
            } else if textMatches.isEmpty {
                // No text matches either, show "no matches" state
                overlayWindow?.filterHints(matching: "", textMatches: [])
                overlayWindow?.updateMatchCount(0)
                isTextSearchMode = false
                numberedElements = []
                HintModeController.isTextSearchActive = false
                HintModeController.numberedElementsCount = 0
            } else if textMatches.count <= 9 {
                // 2-9 matches - activate numbered hints mode
                isTextSearchMode = true
                numberedElements = textMatches
                assignNumberedHints(to: &textMatches)
                HintModeController.isTextSearchActive = true
                HintModeController.numberedElementsCount = textMatches.count

                // Pass numbered elements to overlay for rendering
                overlayWindow?.filterHints(matching: "", textMatches: textMatches, numberedMode: true)
                overlayWindow?.updateMatchCount(textMatches.count)
            } else {
                // More than 9 matches - use regular text search highlighting
                overlayWindow?.filterHints(matching: "", textMatches: textMatches)
                overlayWindow?.updateMatchCount(textMatches.count)
                isTextSearchMode = false
                numberedElements = []
                HintModeController.isTextSearchActive = false
                HintModeController.numberedElementsCount = 0
            }
        } else {
            // Not enough characters for text search, reset display
            overlayWindow?.filterHints(matching: "", textMatches: [])
            isTextSearchMode = false
            numberedElements = []
            HintModeController.isTextSearchActive = false
            HintModeController.numberedElementsCount = 0
        }
    }

    private func clearInputState() {
        currentInput = ""
        overlayWindow?.updateSearchBar(text: "")
        overlayWindow?.updateMatchCount(-1)
    }

    // MARK: - Event Tap Dispatch Handlers (called from main thread only)

    private func handleCharacterInput(_ char: String) {
        guard isActive else { return }
        currentInput += char
        processInput(currentInput)
    }

    private func handleBackspace() {
        guard isActive, !currentInput.isEmpty else { return }
        currentInput.removeLast()
        processInput(currentInput)
    }

    private func handleEscapeKey() {
        guard isActive else { return }
        if !currentInput.isEmpty {
            currentInput = ""
            processInput("")
        } else {
            deactivateHintMode()
        }
    }

    private func handleClearSearch() {
        guard isActive else { return }
        clearSearch()
    }

    private func selectNumberedElement(_ number: Int) {
        guard isTextSearchMode, number > 0, number <= numberedElements.count else { return }

        let element = numberedElements[number - 1] // Convert 1-indexed to 0-indexed
        performClick(on: element)
        clearInputState()
        isTextSearchMode = false
        numberedElements = []
        HintModeController.isTextSearchActive = false
        HintModeController.numberedElementsCount = 0
        handlePostClick()
    }

    private func searchElementsByText(_ searchText: String) -> [UIElement] {
        let lowercasedSearch = searchText.lowercased()
        return elements.filter { element in
            element.searchableText.lowercased().contains(lowercasedSearch)
        }
    }

    private func handlePostClick() {
        let continuousMode = UserDefaults.standard.bool(forKey: AppSettings.Keys.continuousClickMode)
        if continuousMode {
            refreshHints()
        } else {
            deactivateHintMode()
        }
    }

    private func clearSearch() {
        currentInput = ""
        overlayWindow?.updateSearchBar(text: "")
        overlayWindow?.filterHints(matching: "", textMatches: [])
        overlayWindow?.updateMatchCount(-1) // -1 means hide count
    }

    private func handleEnterKey(withControl: Bool) {
        // If we have text matches, click the first one
        if currentInput.count >= minSearchChars {
            let textMatches = searchElementsByText(currentInput)
            if let firstMatch = textMatches.first {
                if withControl {
                    performRightClick(on: firstMatch)
                } else {
                    performClick(on: firstMatch)
                }
                handlePostClick()
            }
        }
    }

    private func performRightClick(on element: UIElement) {
        let axResult = AXUIElementPerformAction(element.axElement, "AXShowMenu" as CFString)
        if axResult != .success {
            let clickPoint = ScreenGeometry.appKitCenterToQuartz(element.centerPoint)
            ClickService.shared.rightClick(at: clickPoint)
        }

        // Restart auto-deactivation timer after successful click
        startDeactivationTimer()
    }

    private func refreshHints() {
        refreshStartTime = CFAbsoluteTimeGetCurrent()
        print("[CONTINUOUS] Click performed, starting refresh...")

        // Reset input state
        currentInput = ""

        // Store current element count for comparison
        previousElementCount = elements.count

        // Get app-specific refresh delays
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let delays = DetectorRegistry.shared.refreshDelays(for: bundleId)

        let optimisticDelay = delays?.optimistic ?? HintModeController.defaultOptimisticDelay
        let fallbackDelay = delays?.fallback ?? HintModeController.defaultFallbackDelay

        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
        print("[CONTINUOUS] App: \(appName) | Delays: optimistic=\(Int(optimisticDelay * 1000))ms, fallback=\(Int(fallbackDelay * 1000))ms")

        // Optimistic + fallback refresh strategy with app-specific timing
        Task { @MainActor in
            do {
                // Optimistic attempt with app-specific timing
                try await Task.sleep(for: .seconds(optimisticDelay))
                guard self.isActive else { return }

                let optimisticTime = CFAbsoluteTimeGetCurrent()
                print("[CONTINUOUS] Optimistic refresh at +\(String(format: "%.0f", (optimisticTime - refreshStartTime) * 1000))ms")

                let uiChanged = self.performHintRefresh()

                if uiChanged {
                    // UI changed quickly, we're done!
                    print("[CONTINUOUS] UI changed: YES (\(self.elements.count) elements)")
                    return
                }

                // UI hasn't changed yet, wait longer with app-specific fallback
                print("[CONTINUOUS] UI changed: NO (still \(self.elements.count) elements)")
                try await Task.sleep(for: .seconds(fallbackDelay))
                guard self.isActive else { return }

                let fallbackTime = CFAbsoluteTimeGetCurrent()
                print("[CONTINUOUS] Fallback refresh at +\(String(format: "%.0f", (fallbackTime - refreshStartTime) * 1000))ms")

                // Perform final refresh (assume it worked this time)
                _ = self.performHintRefresh()

            } catch {
                // Task was cancelled, which is fine
            }
        }
    }

    private func performManualRefresh() {
        guard isActive else { return }

        let manualStartTime = CFAbsoluteTimeGetCurrent()

        // Re-query clickable elements
        let newElements = AccessibilityService.shared.getClickableElements()

        guard !newElements.isEmpty else {
            deactivateHintMode()
            return
        }

        // Update elements and reassign hints
        self.elements = newElements
        self.previousElementCount = newElements.count
        self.assignHints()

        // Update the overlay window
        self.overlayWindow?.updateHints(with: self.elements)

        let manualEndTime = CFAbsoluteTimeGetCurrent()
        let totalTime = (manualEndTime - manualStartTime) * 1000
        print("[MANUAL] Refreshed \(newElements.count) elements in \(String(format: "%.0f", totalTime))ms\n")

        // Restart auto-deactivation timer after manual refresh
        startDeactivationTimer()

        // Load text attributes for new elements (enables text search)
        self.loadTextAttributesAsync()
    }

    nonisolated private static func keyCodeToCharacter(_ keyCode: Int64) -> String? {
        // Map common keycodes to characters
        let keyMap: [Int64: String] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
            8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
            16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 37: "l",
            38: "j", 40: "k", 41: ";", 43: ",", 45: "n", 46: "m", 47: ".",
            50: "`"
        ]

        return keyMap[keyCode]
    }

    private func performClick(on element: UIElement) {
        // AXPress works regardless of screen position (handles off-screen popovers,
        // scroll-clipped elements, Electron apps with misreported AX frames).
        // Fall back to CGEvent only when the element has no press action.
        let axResult = AXUIElementPerformAction(element.axElement, kAXPressAction as CFString)
        if axResult != .success {
            let clickPoint = ScreenGeometry.appKitCenterToQuartz(element.centerPoint)
            ClickService.shared.click(at: clickPoint)
        }

        // Restart auto-deactivation timer after successful click
        startDeactivationTimer()
    }

    // MARK: - Auto-Deactivation Timer

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

    private func loadAutoDeactivationSettings() {
        autoDeactivation = UserDefaults.standard.bool(forKey: AppSettings.Keys.autoHintDeactivation)
        deactivationDelay = UserDefaults.standard.double(forKey: AppSettings.Keys.hintDeactivationDelay)

        // Default to 5.0 if not set
        if deactivationDelay == 0 {
            deactivationDelay = 5.0
        }
    }
}
