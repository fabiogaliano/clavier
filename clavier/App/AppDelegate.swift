import AppKit
import Carbon
import os

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hintModeController: HintModeController?
    private var scrollModeController: ScrollModeController?
    private var hintMenuItem: NSMenuItem?
    private var scrollMenuItem: NSMenuItem?
    private var hintDebugMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.registerDefaults()

        setupMenuBar()
        setupHintMode()
        setupScrollMode()
        checkAccessibilityPermissions()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "clavier")
        }

        let menu = NSMenu()

        hintMenuItem = NSMenuItem(title: formatHintMenuTitle(), action: #selector(activateHints), keyEquivalent: "")
        scrollMenuItem = NSMenuItem(title: formatScrollMenuTitle(), action: #selector(activateScroll), keyEquivalent: "")
        hintDebugMenuItem = NSMenuItem(title: formatHintDebugMenuTitle(), action: #selector(activateHintDebug), keyEquivalent: "")

        menu.addItem(hintMenuItem!)
        menu.addItem(scrollMenuItem!)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(hintDebugMenuItem!)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit clavier", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem?.menu = menu

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateMenuTitles),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    @objc private func updateMenuTitles() {
        hintMenuItem?.title = formatHintMenuTitle()
        scrollMenuItem?.title = formatScrollMenuTitle()
        hintDebugMenuItem?.title = formatHintDebugMenuTitle()
    }

    private func formatHintMenuTitle() -> String {
        let keyCode = UserDefaults.standard.integer(forKey: AppSettings.Keys.hintShortcutKeyCode)
        let modifiers = UserDefaults.standard.integer(forKey: AppSettings.Keys.hintShortcutModifiers)
        let shortcut = KeymapUtilities.formatShortcut(keyCode: keyCode, modifiers: modifiers)
        return "Activate Hints (\(shortcut))"
    }

    private func formatScrollMenuTitle() -> String {
        let keyCode = UserDefaults.standard.integer(forKey: AppSettings.Keys.scrollShortcutKeyCode)
        let modifiers = UserDefaults.standard.integer(forKey: AppSettings.Keys.scrollShortcutModifiers)
        let shortcut = KeymapUtilities.formatShortcut(keyCode: keyCode, modifiers: modifiers)
        return "Activate Scroll (\(shortcut))"
    }

    private func formatHintDebugMenuTitle() -> String {
        let keyCode = UserDefaults.standard.integer(forKey: AppSettings.Keys.hintDebugShortcutKeyCode)
        let modifiers = UserDefaults.standard.integer(forKey: AppSettings.Keys.hintDebugShortcutModifiers)
        let shortcut = KeymapUtilities.formatShortcut(keyCode: keyCode, modifiers: modifiers)
        return "Debug Hints (\(shortcut))"
    }

    private func setupHintMode() {
        hintModeController = HintModeController()
        hintModeController?.registerGlobalHotkey()
    }

    private func setupScrollMode() {
        scrollModeController = ScrollModeController()
        scrollModeController?.registerGlobalHotkey()
    }

    private func checkAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)

        if !trusted {
            Logger.app.warning("Accessibility permissions not granted. Enable in System Settings > Privacy & Security > Accessibility.")
        }
    }

    @objc private func activateHints() {
        hintModeController?.toggleHintMode()
    }

    @objc private func activateScroll() {
        scrollModeController?.toggleScrollMode()
    }

    @objc private func activateHintDebug() {
        hintModeController?.toggleDebugHintMode()
    }

    @objc private func openPreferences() {
        NotificationCenter.default.post(name: .openSettingsRequest, object: nil)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
