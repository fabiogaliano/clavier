//
//  SessionDismissalMonitor.swift
//  clavier
//
//  Ends a hint or scroll session when the user leaves it without the
//  keyboard: switching to another app, or clicking with the mouse.
//
//  Both overlays describe one app's windows at one moment.  Once the user
//  moves elsewhere the labels point at stale frames and the event tap keeps
//  eating keys meant for the new target, so the session has to go.
//

import AppKit

@MainActor
final class SessionDismissalMonitor {

    private var activationObserver: NSObjectProtocol?
    private var mouseMonitor: Any?

    /// Begin observing; `onDismiss` runs on the main actor each time the user
    /// leaves.  Replaces any previous observation.
    func start(onDismiss: @escaping @MainActor () -> Void) {
        stop()

        let ownPID = ProcessInfo.processInfo.processIdentifier
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            // Opening clavier's own Settings or About from the menu bar must
            // not count as leaving.
            guard app?.processIdentifier != ownPID else { return }
            MainActor.assumeIsolated { onDismiss() }
        }

        // A global monitor observes without consuming, so the click still
        // lands where the user aimed it.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { event in
            // Hint mode's own CGEvent click fallback would otherwise end the
            // session it is acting for.
            guard !SyntheticClickTag.isSynthesized(event.cgEvent) else { return }
            MainActor.assumeIsolated { onDismiss() }
        }
    }

    func stop() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        mouseMonitor = nil
    }
}

/// Marks mouse events clavier posts itself so observers can tell them apart
/// from the user's hardware clicks.
enum SyntheticClickTag {
    /// Arbitrary constant ("CLAV" in ASCII) written to `eventSourceUserData`.
    static let userData: Int64 = 0x434C_4156

    static func tag(_ event: CGEvent?) {
        event?.setIntegerValueField(.eventSourceUserData, value: userData)
    }

    static func isSynthesized(_ event: CGEvent?) -> Bool {
        guard let event else { return false }
        if event.getIntegerValueField(.eventSourceUserData) == userData { return true }
        // Belt and braces in case the user-data field is not carried through
        // to the monitor: posted events report the posting process.
        let sourcePID = event.getIntegerValueField(.eventSourceUnixProcessID)
        return sourcePID == Int64(ProcessInfo.processInfo.processIdentifier)
    }
}
