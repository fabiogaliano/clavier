import Foundation

extension Notification.Name {
    static let openSettingsRequest = Notification.Name("openSettingsRequest")
    static let settingsWindowClosed = Notification.Name("settingsWindowClosed")
    static let disableGlobalHotkeys = Notification.Name("disableGlobalHotkeys")
    static let enableGlobalHotkeys = Notification.Name("enableGlobalHotkeys")
}
