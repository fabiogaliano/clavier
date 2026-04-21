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
    private var session: HintSession = .inactive
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

    // MARK: - Convenience accessors into session

    private var isActive: Bool { session.isActive }
    private var currentInput: String { session.filter }
    private var hintedElements: [HintedElement] { session.hintedElements }

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

        let discoveredElements = AccessibilityService.shared.getClickableElements()
        guard !discoveredElements.isEmpty else { return }

        let hintedElements = assignHints(to: discoveredElements)

        overlayWindow = HintOverlayWindow(hintedElements: hintedElements)
        overlayWindow?.show()

        guard startEventTap() else {
            print("⚠️ Failed to create event tap. Check Accessibility permissions in System Settings > Privacy & Security > Accessibility.")
            overlayWindow?.orderOut(nil)
            overlayWindow?.close()
            overlayWindow = nil
            return
        }

        session = .active(hintedElements: hintedElements, filter: "")
        previousElementCount = hintedElements.count
        HintModeController.isHintModeActive = true
        textSearchEnabled = UserDefaults.standard.bool(forKey: AppSettings.Keys.textSearchEnabled)
        minSearchChars = AppSettings.minSearchCharacters
        refreshTrigger = AppSettings.manualRefreshTrigger

        startDeactivationTimer()
        loadTextAttributesAsync()
    }

    private func loadTextAttributesAsync() {
        Task { @MainActor in
            // Extract domain elements, load text attributes, then sync back
            var domainElements = self.hintedElements.map { $0.element }
            AccessibilityService.shared.loadTextAttributes(for: &domainElements)
            guard self.isActive else { return }
            // Rebuild hinted elements with updated domain data, preserving hints
            let updatedHinted = zip(self.hintedElements, domainElements).map { hinted, updated in
                HintedElement(element: updated, hint: hinted.hint)
            }
            switch self.session {
            case .active(_, let filter):
                self.session = .active(hintedElements: updatedHinted, filter: filter)
            case .textSearch(_, let matches, let filter):
                // Text search matches are a subset — re-derive from updated elements
                let matchIDs = Set(matches.map { $0.identity })
                let updatedMatches = updatedHinted.filter { matchIDs.contains($0.identity) }
                self.session = .textSearch(hintedElements: updatedHinted, matches: updatedMatches, filter: filter)
            case .inactive:
                break
            }
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

        session = .inactive
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

        let newHintedElements = assignHints(to: newElements)
        previousElementCount = newElements.count
        session = .active(hintedElements: newHintedElements, filter: "")

        let overlayStart = CFAbsoluteTimeGetCurrent()
        self.overlayWindow?.updateHints(with: newHintedElements)
        let overlayEnd = CFAbsoluteTimeGetCurrent()
        print("[CONTINUOUS] Update overlay: \(String(format: "%.0f", (overlayEnd - overlayStart) * 1000))ms")

        let totalTime = CFAbsoluteTimeGetCurrent() - refreshStartTime
        print("[CONTINUOUS] Total refresh time: \(String(format: "%.0f", totalTime * 1000))ms\n")

        startDeactivationTimer()
        self.loadTextAttributesAsync()

        return uiChanged
    }

    /// Produce a `[HintedElement]` mapping from raw discovered elements.
    ///
    /// No mutation of the domain elements — hint tokens live only in the
    /// returned `HintedElement` wrappers (F05/P3-S1).
    private func assignHints(to elements: [UIElement]) -> [HintedElement] {
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

        return zip(elements.prefix(hintCount), hints).map { element, hint in
            HintedElement(element: element, hint: hint)
        }
    }

    private func assignNumberedHints(to elements: [UIElement]) -> [HintedElement] {
        elements.prefix(9).enumerated().map { index, element in
            HintedElement(element: element, hint: "\(index + 1)")
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

        overlayWindow?.updateSearchBar(text: input)

        if input == refreshTrigger {
            print("[MANUAL] Refresh trigger detected: \"\(input)\"")
            clearInputState()
            performManualRefresh()
            return
        }

        if let matched = hintedElements.first(where: { $0.hint == input }) {
            overlayWindow?.filterHints(matching: input, textMatches: [])
            performClick(on: matched.element)
            clearInputState()
            handlePostClick()
            return
        }

        let hintMatchingElements = hintedElements.filter { $0.hint.hasPrefix(input) }
        if !hintMatchingElements.isEmpty {
            overlayWindow?.filterHints(matching: input, textMatches: [])
            // Update filter in session
            switch session {
            case .active(let elements, _):
                session = .active(hintedElements: elements, filter: input)
            default:
                break
            }
            return
        }

        if textSearchEnabled && input.count >= minSearchChars {
            let textMatchElements = searchElementsByText(input)
            var textMatches = textMatchElements

            if textMatches.count == 1 {
                performClick(on: textMatches[0].element)
                clearInputState()
                handlePostClick()
            } else if textMatches.isEmpty {
                overlayWindow?.filterHints(matching: "", textMatches: [])
                overlayWindow?.updateMatchCount(0)
                switch session {
                case .active(let elements, _):
                    session = .active(hintedElements: elements, filter: input)
                default:
                    break
                }
                HintModeController.isTextSearchActive = false
                HintModeController.numberedElementsCount = 0
            } else if textMatches.count <= 9 {
                let numberedMatches = assignNumberedHints(to: textMatches.map { $0.element })
                HintModeController.isTextSearchActive = true
                HintModeController.numberedElementsCount = numberedMatches.count
                session = .textSearch(hintedElements: hintedElements, matches: numberedMatches, filter: input)
                overlayWindow?.filterHints(matching: "", textMatches: numberedMatches, numberedMode: true)
                overlayWindow?.updateMatchCount(numberedMatches.count)
            } else {
                overlayWindow?.filterHints(matching: "", textMatches: textMatches)
                overlayWindow?.updateMatchCount(textMatches.count)
                switch session {
                case .active(let elements, _):
                    session = .active(hintedElements: elements, filter: input)
                default:
                    break
                }
                HintModeController.isTextSearchActive = false
                HintModeController.numberedElementsCount = 0
            }
        } else {
            overlayWindow?.filterHints(matching: "", textMatches: [])
            switch session {
            case .active(let elements, _):
                session = .active(hintedElements: elements, filter: input)
            case .textSearch(let elements, _, _):
                session = .active(hintedElements: elements, filter: input)
            default:
                break
            }
            HintModeController.isTextSearchActive = false
            HintModeController.numberedElementsCount = 0
        }
    }

    private func clearInputState() {
        overlayWindow?.updateSearchBar(text: "")
        overlayWindow?.updateMatchCount(-1)
        switch session {
        case .active(let elements, _):
            session = .active(hintedElements: elements, filter: "")
        case .textSearch(let elements, _, _):
            session = .active(hintedElements: elements, filter: "")
        case .inactive:
            break
        }
        HintModeController.isTextSearchActive = false
        HintModeController.numberedElementsCount = 0
    }

    // MARK: - Event handlers (main thread only)

    private func handleCharacterInput(_ char: String) {
        guard isActive else { return }
        let newInput = currentInput + char
        updateSessionFilter(newInput)
        processInput(newInput)
    }

    private func handleBackspace() {
        guard isActive, !currentInput.isEmpty else { return }
        var newInput = currentInput
        newInput.removeLast()
        updateSessionFilter(newInput)
        processInput(newInput)
    }

    private func handleEscapeKey() {
        guard isActive else { return }
        if !currentInput.isEmpty {
            updateSessionFilter("")
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
        guard case .textSearch(let elements, let matches, _) = session,
              number > 0, number <= matches.count else { return }
        let hintedElement = matches[number - 1]
        performClick(on: hintedElement.element)
        session = .active(hintedElements: elements, filter: "")
        overlayWindow?.updateSearchBar(text: "")
        overlayWindow?.updateMatchCount(-1)
        HintModeController.isTextSearchActive = false
        HintModeController.numberedElementsCount = 0
        handlePostClick()
    }

    private func searchElementsByText(_ searchText: String) -> [HintedElement] {
        let lowercasedSearch = searchText.lowercased()
        return hintedElements.filter { $0.element.searchableText.lowercased().contains(lowercasedSearch) }
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
        overlayWindow?.updateSearchBar(text: "")
        overlayWindow?.filterHints(matching: "", textMatches: [])
        overlayWindow?.updateMatchCount(-1)
        switch session {
        case .active(let elements, _):
            session = .active(hintedElements: elements, filter: "")
        case .textSearch(let elements, _, _):
            session = .active(hintedElements: elements, filter: "")
        case .inactive:
            break
        }
        HintModeController.isTextSearchActive = false
        HintModeController.numberedElementsCount = 0
    }

    private func handleEnterKey(withControl: Bool) {
        if currentInput.count >= minSearchChars {
            let textMatches = searchElementsByText(currentInput)
            if let firstMatch = textMatches.first {
                if withControl {
                    performRightClick(on: firstMatch.element)
                } else {
                    performClick(on: firstMatch.element)
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

        let currentHintedElements = hintedElements
        previousElementCount = currentHintedElements.count

        // Reset filter without changing the hinted elements
        if case .active(let elements, _) = session {
            session = .active(hintedElements: elements, filter: "")
        }

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
                    print("[CONTINUOUS] UI changed: YES (\(self.hintedElements.count) elements)")
                    return
                }

                print("[CONTINUOUS] UI changed: NO (still \(self.hintedElements.count) elements)")
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

        let newHintedElements = assignHints(to: newElements)
        previousElementCount = newElements.count
        session = .active(hintedElements: newHintedElements, filter: "")
        self.overlayWindow?.updateHints(with: newHintedElements)

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

    // MARK: - Session helpers

    /// Update only the filter component of the current session without touching hinted elements.
    private func updateSessionFilter(_ newFilter: String) {
        switch session {
        case .active(let elements, _):
            session = .active(hintedElements: elements, filter: newFilter)
        case .textSearch(let elements, let matches, _):
            session = .textSearch(hintedElements: elements, matches: matches, filter: newFilter)
        case .inactive:
            break
        }
    }
}
