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
            let image = NSImage(systemSymbolName: "keyboard.badge.ellipsis", accessibilityDescription: "clavier")
                ?? NSImage(systemSymbolName: "keyboard", accessibilityDescription: "clavier")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "clavier — keyboard navigation"
        }

        let menu = NSMenu()
        menu.autoenablesItems = false

        // Brand header — disabled, not selectable. Using `headerTitle` on
        // NSMenu would render a section style; using a disabled item gives
        // us more control over typography.
        let header = NSMenuItem()
        header.attributedTitle = NSAttributedString(
            string: "clavier",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        hintMenuItem = buildModeItem(
            title: "Activate Hints",
            symbol: "cursorarrow.click.badge.clock",
            action: #selector(activateHints),
            subtitle: formatHintShortcut()
        )
        scrollMenuItem = buildModeItem(
            title: "Activate Scroll",
            symbol: "arrow.up.and.down.text.horizontal",
            action: #selector(activateScroll),
            subtitle: formatScrollShortcut()
        )
        hintDebugMenuItem = buildModeItem(
            title: "Debug Hints",
            symbol: "ant",
            action: #selector(activateHintDebug),
            subtitle: formatHintDebugShortcut()
        )

        menu.addItem(hintMenuItem!)
        menu.addItem(scrollMenuItem!)
        menu.addItem(.separator())
        menu.addItem(hintDebugMenuItem!)
        menu.addItem(.separator())

        let prefs = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        prefs.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(prefs)

        let about = NSMenuItem(title: "About clavier", action: #selector(openAbout), keyEquivalent: "")
        about.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        menu.addItem(about)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit clavier", action: #selector(quitApp), keyEquivalent: "q")
        quit.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quit)

        statusItem?.menu = menu

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateMenuTitles),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    /// Builds a menu item with an SF Symbol leading glyph, a main title, and
    /// the shortcut rendered as a subtitle (macOS 14.4+). Using the subtitle
    /// API keeps the main title clean while still surfacing the hotkey.
    private func buildModeItem(title: String, symbol: String, action: Selector, subtitle: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        item.subtitle = subtitle
        return item
    }

    @objc private func updateMenuTitles() {
        hintMenuItem?.subtitle = formatHintShortcut()
        scrollMenuItem?.subtitle = formatScrollShortcut()
        hintDebugMenuItem?.subtitle = formatHintDebugShortcut()
    }

    private func formatHintShortcut() -> String {
        let keyCode = UserDefaults.standard.integer(forKey: AppSettings.Keys.hintShortcutKeyCode)
        let modifiers = UserDefaults.standard.integer(forKey: AppSettings.Keys.hintShortcutModifiers)
        return KeymapUtilities.formatShortcut(keyCode: keyCode, modifiers: modifiers)
    }

    private func formatScrollShortcut() -> String {
        let keyCode = UserDefaults.standard.integer(forKey: AppSettings.Keys.scrollShortcutKeyCode)
        let modifiers = UserDefaults.standard.integer(forKey: AppSettings.Keys.scrollShortcutModifiers)
        return KeymapUtilities.formatShortcut(keyCode: keyCode, modifiers: modifiers)
    }

    private func formatHintDebugShortcut() -> String {
        let keyCode = UserDefaults.standard.integer(forKey: AppSettings.Keys.hintDebugShortcutKeyCode)
        let modifiers = UserDefaults.standard.integer(forKey: AppSettings.Keys.hintDebugShortcutModifiers)
        return KeymapUtilities.formatShortcut(keyCode: keyCode, modifiers: modifiers)
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

    @objc private func openAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
