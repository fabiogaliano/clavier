import SwiftUI

@main
struct clavierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Hidden window provides SwiftUI context for openSettings()
        Window("Hidden", id: "HiddenWindow") {
            SettingsOpenerView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1, height: 1)

        Settings {
            PreferencesView()
                .onDisappear {
                    NotificationCenter.default.post(name: .settingsWindowClosed, object: nil)
                }
        }
    }
}
