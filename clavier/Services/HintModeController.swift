//
//  HintModeController.swift
//  clavier
//
//  Orchestrates hint mode activation and keyboard input
//

import Foundation
import AppKit

@MainActor
class HintModeController {

    private var overlayWindow: HintOverlayWindow?
    private var isActive = false
    private var currentInput = ""
    private var elements: [UIElement] = []
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
    private static let defaultOptimisticDelay: TimeInterval = 0.050
    private static let defaultFallbackDelay: TimeInterval = 0.100

    // Callback-visible state: simple scalars readable from the CF run loop thread.
    // All string/collection mutation happens on main via DispatchQueue.main.async.
    private nonisolated(unsafe) static var isHintModeActive = false
    private nonisolated(unsafe) static var isTextSearchActive = false
    private nonisolated(unsafe) static var numberedElementsCount = 0

    // Shared infrastructure (P2-S1)
    private let hotkeyRegistrar = GlobalHotkeyRegistrar(signature: "KNAV", hotkeyID: 1)
    private let eventTap = KeyboardEventTap(slotIndex: 0)

    // Static reference kept for the shared infrastructure callback path.
    private static var sharedInstance: HintModeController?

    private var refreshStartTime: CFAbsoluteTime = 0

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

    private func activateHintMode() {
        guard !isActive else { return }

        loadAutoDeactivationSettings()

        elements = AccessibilityService.shared.getClickableElements()
        guard !elements.isEmpty else { return }

        assignHints()

        overlayWindow = HintOverlayWindow(elements: elements)
        overlayWindow?.show()

        guard startEventTap() else {
            print("⚠️ Failed to create event tap. Check Accessibility permissions in System Settings > Privacy & Security > Accessibility.")
            overlayWindow?.orderOut(nil)
            overlayWindow?.close()
            overlayWindow = nil
            elements = []
            return
        }

        isActive = true
        currentInput = ""
        previousElementCount = elements.count
        HintModeController.isHintModeActive = true
        textSearchEnabled = UserDefaults.standard.bool(forKey: AppSettings.Keys.textSearchEnabled)
        minSearchChars = AppSettings.minSearchCharacters
        refreshTrigger = AppSettings.manualRefreshTrigger

        startDeactivationTimer()
        loadTextAttributesAsync()
    }

    private func loadTextAttributesAsync() {
        Task { @MainActor in
            AccessibilityService.shared.loadTextAttributes(for: &self.elements)
        }
    }

    private func deactivateHintMode() {
        guard isActive else { return }

        HintModeController.isHintModeActive = false
        HintModeController.isTextSearchActive = false
        HintModeController.numberedElementsCount = 0

        deactivationTimer?.invalidate()
        deactivationTimer = nil

        eventTap.stop()

        if let window = overlayWindow {
            window.orderOut(nil)
            window.close()
        }
        overlayWindow = nil

        elements = []
        isActive = false
        currentInput = ""
        isTextSearchMode = false
        numberedElements = []
    }

    @discardableResult
    private func performHintRefresh() -> Bool {
        guard isActive else { return false }

        let queryStart = CFAbsoluteTimeGetCurrent()
        let newElements = AccessibilityService.shared.getClickableElements()
        guard !newElements.isEmpty else {
            deactivateHintMode()
            return false
        }

        let queryEnd = CFAbsoluteTimeGetCurrent()
        print("[CONTINUOUS] Query elements: \(String(format: "%.0f", (queryEnd - queryStart) * 1000))ms")

        let uiChanged = newElements.count != previousElementCount

        self.elements = newElements
        self.previousElementCount = newElements.count
        self.assignHints()

        let overlayStart = CFAbsoluteTimeGetCurrent()
        self.overlayWindow?.updateHints(with: self.elements)
        let overlayEnd = CFAbsoluteTimeGetCurrent()
        print("[CONTINUOUS] Update overlay: \(String(format: "%.0f", (overlayEnd - overlayStart) * 1000))ms")

        let totalTime = CFAbsoluteTimeGetCurrent() - refreshStartTime
        print("[CONTINUOUS] Total refresh time: \(String(format: "%.0f", totalTime * 1000))ms\n")

        startDeactivationTimer()
        self.loadTextAttributesAsync()

        return uiChanged
    }

    private func assignHints() {
        var hintCharacters = AppSettings.hintCharacters
        if hintCharacters.count < 2 { hintCharacters = AppSettings.Defaults.hintCharacters }
        let chars = Array(hintCharacters)
        let count = elements.count

        var hints: [String] = []
        let n = chars.count
        let twoCharCombos = n * n
        let threeCharCombos = n * n * n
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
        for i in 0..<min(elements.count, 9) {
            elements[i].hint = "\(i + 1)"
        }
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

                case .escape:
                    DispatchQueue.main.async {
                        HintModeController.sharedInstance?.handleEscapeKey()
                    }
                    return nil

                case .enter(let withControl):
                    DispatchQueue.main.async {
                        HintModeController.sharedInstance?.handleEnterKey(withControl: withControl)
                    }
                    return nil

                case .backspace:
                    DispatchQueue.main.async {
                        HintModeController.sharedInstance?.handleBackspace()
                    }
                    return nil

                case .clearSearch:
                    DispatchQueue.main.async {
                        HintModeController.sharedInstance?.handleClearSearch()
                    }
                    return Unmanaged.passRetained(event)

                case .selectNumbered(let number):
                    DispatchQueue.main.async {
                        HintModeController.sharedInstance?.selectNumberedElement(number)
                    }
                    return nil

                case .character(let char):
                    DispatchQueue.main.async {
                        HintModeController.sharedInstance?.handleCharacterInput(char)
                    }
                    return nil
                }
            }
        )
    }

    // MARK: - Input processing

    private func processInput(_ input: String) {
        guard isActive else { return }

        currentInput = input
        overlayWindow?.updateSearchBar(text: input)

        if input == refreshTrigger {
            print("[MANUAL] Refresh trigger detected: \"\(input)\"")
            clearInputState()
            performManualRefresh()
            return
        }

        if let matchedElement = elements.first(where: { $0.hint == input }) {
            overlayWindow?.filterHints(matching: input, textMatches: [])
            performClick(on: matchedElement)
            clearInputState()
            handlePostClick()
            return
        }

        let hintMatchingElements = elements.filter { $0.hint.hasPrefix(input) }
        if !hintMatchingElements.isEmpty {
            overlayWindow?.filterHints(matching: input, textMatches: [])
            return
        }

        if textSearchEnabled && input.count >= minSearchChars {
            var textMatches = searchElementsByText(input)

            if textMatches.count == 1 {
                performClick(on: textMatches[0])
                clearInputState()
                handlePostClick()
            } else if textMatches.isEmpty {
                overlayWindow?.filterHints(matching: "", textMatches: [])
                overlayWindow?.updateMatchCount(0)
                isTextSearchMode = false
                numberedElements = []
                HintModeController.isTextSearchActive = false
                HintModeController.numberedElementsCount = 0
            } else if textMatches.count <= 9 {
                isTextSearchMode = true
                numberedElements = textMatches
                assignNumberedHints(to: &textMatches)
                HintModeController.isTextSearchActive = true
                HintModeController.numberedElementsCount = textMatches.count
                overlayWindow?.filterHints(matching: "", textMatches: textMatches, numberedMode: true)
                overlayWindow?.updateMatchCount(textMatches.count)
            } else {
                overlayWindow?.filterHints(matching: "", textMatches: textMatches)
                overlayWindow?.updateMatchCount(textMatches.count)
                isTextSearchMode = false
                numberedElements = []
                HintModeController.isTextSearchActive = false
                HintModeController.numberedElementsCount = 0
            }
        } else {
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

    // MARK: - Event handlers (main thread only)

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
        let element = numberedElements[number - 1]
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
        return elements.filter { $0.searchableText.lowercased().contains(lowercasedSearch) }
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
        overlayWindow?.updateMatchCount(-1)
    }

    private func handleEnterKey(withControl: Bool) {
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
        startDeactivationTimer()
    }

    private func refreshHints() {
        refreshStartTime = CFAbsoluteTimeGetCurrent()
        print("[CONTINUOUS] Click performed, starting refresh...")

        currentInput = ""
        previousElementCount = elements.count

        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let delays = DetectorRegistry.shared.refreshDelays(for: bundleId)

        let optimisticDelay = delays?.optimistic ?? HintModeController.defaultOptimisticDelay
        let fallbackDelay = delays?.fallback ?? HintModeController.defaultFallbackDelay

        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
        print("[CONTINUOUS] App: \(appName) | Delays: optimistic=\(Int(optimisticDelay * 1000))ms, fallback=\(Int(fallbackDelay * 1000))ms")

        Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(optimisticDelay))
                guard self.isActive else { return }

                let optimisticTime = CFAbsoluteTimeGetCurrent()
                print("[CONTINUOUS] Optimistic refresh at +\(String(format: "%.0f", (optimisticTime - self.refreshStartTime) * 1000))ms")

                let uiChanged = self.performHintRefresh()
                if uiChanged {
                    print("[CONTINUOUS] UI changed: YES (\(self.elements.count) elements)")
                    return
                }

                print("[CONTINUOUS] UI changed: NO (still \(self.elements.count) elements)")
                try await Task.sleep(for: .seconds(fallbackDelay))
                guard self.isActive else { return }

                let fallbackTime = CFAbsoluteTimeGetCurrent()
                print("[CONTINUOUS] Fallback refresh at +\(String(format: "%.0f", (fallbackTime - self.refreshStartTime) * 1000))ms")

                _ = self.performHintRefresh()
            } catch {
                // Task cancelled — mode deactivated during refresh window
            }
        }
    }

    private func performManualRefresh() {
        guard isActive else { return }

        let manualStartTime = CFAbsoluteTimeGetCurrent()
        let newElements = AccessibilityService.shared.getClickableElements()
        guard !newElements.isEmpty else {
            deactivateHintMode()
            return
        }

        self.elements = newElements
        self.previousElementCount = newElements.count
        self.assignHints()
        self.overlayWindow?.updateHints(with: self.elements)

        let manualEndTime = CFAbsoluteTimeGetCurrent()
        let totalTime = (manualEndTime - manualStartTime) * 1000
        print("[MANUAL] Refreshed \(newElements.count) elements in \(String(format: "%.0f", totalTime))ms\n")

        startDeactivationTimer()
        self.loadTextAttributesAsync()
    }

    private func performClick(on element: UIElement) {
        let axResult = AXUIElementPerformAction(element.axElement, kAXPressAction as CFString)
        if axResult != .success {
            let clickPoint = ScreenGeometry.appKitCenterToQuartz(element.centerPoint)
            ClickService.shared.click(at: clickPoint)
        }
        startDeactivationTimer()
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

    private func loadAutoDeactivationSettings() {
        autoDeactivation = UserDefaults.standard.bool(forKey: AppSettings.Keys.autoHintDeactivation)
        deactivationDelay = UserDefaults.standard.double(forKey: AppSettings.Keys.hintDeactivationDelay)
        if deactivationDelay == 0 { deactivationDelay = 5.0 }
    }
}
