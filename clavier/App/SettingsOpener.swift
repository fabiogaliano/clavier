import SwiftUI
import AppKit

/// Hidden SwiftUI view that bridges NSApplicationDelegate menu actions to the
/// SwiftUI `openSettings` environment action. Lives inside the "HiddenWindow"
/// scene so it always has access to the SwiftUI environment.
struct SettingsOpenerView: View {
    @Environment(\.openSettings) private var openSettings
    @State private var windowObserver: NSObjectProtocol?

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onReceive(NotificationCenter.default.publisher(for: .openSettingsRequest)) { _ in
                Task { @MainActor in
                    // Temporarily show dock icon for proper window focus
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)

                    // Detect when the Settings window becomes key so we can front it
                    windowObserver = NotificationCenter.default.addObserver(
                        forName: NSWindow.didBecomeKeyNotification,
                        object: nil,
                        queue: .main
                    ) { notification in
                        guard let window = notification.object as? NSWindow,
                              Self.isSettingsWindow(window) else { return }

                        window.makeKeyAndOrderFront(nil)
                        window.orderFrontRegardless()

                        if let observer = windowObserver {
                            NotificationCenter.default.removeObserver(observer)
                            windowObserver = nil
                        }
                    }

                    openSettings()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .settingsWindowClosed)) { _ in
                NSApp.setActivationPolicy(.accessory)

                if let observer = windowObserver {
                    NotificationCenter.default.removeObserver(observer)
                    windowObserver = nil
                }
            }
    }

    private static func isSettingsWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue == "com.apple.SwiftUI.Settings" ||
        (window.isVisible && window.title.localizedCaseInsensitiveContains("settings"))
    }
}
