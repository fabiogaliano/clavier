//
//  HintDebugModeController.swift
//  clavier
//
//  Debug overlay for hint discovery: one recorded discovery pass, a colored
//  overlay of every visited element, and a JSON snapshot on disk.
//
//  Lives apart from `HintModeController` so the production controller only
//  has to expose `deactivateHintMode()` to keep the two overlays exclusive.
//

import Foundation
import AppKit
import os

@MainActor
final class HintDebugModeController {

    private let hintModeController: HintModeController
    private let hotkeyRegistrar = GlobalHotkeyRegistrar(signature: "KDBG", hotkeyID: 2)

    // Independent of normal hint mode so ESC and its own overlay don't
    // collide with the production path.
    private var overlay: HintDebugOverlayWindow?
    private let eventTap = KeyboardEventTap(slotIndex: 2)
    private nonisolated(unsafe) static var isDebugActive = false

    // Static back-reference for the CF run loop callback path
    private static var sharedInstance: HintDebugModeController?

    init(hintModeController: HintModeController) {
        self.hintModeController = hintModeController
    }

    func registerGlobalHotkey() {
        HintDebugModeController.sharedInstance = self
        hotkeyRegistrar.register(
            keyCodeKey: AppSettings.Keys.hintDebugShortcutKeyCode,
            modifiersKey: AppSettings.Keys.hintDebugShortcutModifiers,
            onActivation: { [weak self] in self?.toggleDebugHintMode() }
        )
    }

    /// Public entry: runs one discovery pass with a recorder, opens the
    /// colored debug overlay, and writes a JSON snapshot.  Pressing ESC
    /// (or the debug hotkey again) dismisses the overlay.
    func toggleDebugHintMode() {
        if HintDebugModeController.isDebugActive {
            deactivateDebugMode()
        } else {
            activateDebugMode()
        }
    }

    private func activateDebugMode() {
        // Tearing down normal hint mode keeps the two overlays exclusive.
        hintModeController.deactivateHintMode()

        let recorder = HintDiscoveryRecorder()
        // Capture the same `[UIElement]` hint mode would consume so the
        // debug path can replay production hint assignment + placement
        // and join the results back onto the event stream.  Any drift
        // between the two paths is automatically impossible because the
        // walker, assigner, and layout helper used here are identical.
        let elements = AccessibilityService.shared.getClickableElements(recorder: recorder)
        let hinted = HintAssigner.assign(to: elements, alphabet: AppSettings.hintCharacters)
        let desktopSize = ScreenGeometry.desktopBoundsInAppKit.size
        let labeled = HintLayout.buildLabels(for: hinted, windowSize: desktopSize)

        // `view.frame` is window-local; event frames are screen-global.
        // Convert once so the snapshot stores a frame in the same
        // coordinate system as every other frame field.
        let windowOrigin = ScreenGeometry.desktopBoundsInAppKit.origin
        let hintInfo: [ElementIdentity: HintDebugSnapshot.HintInfo] = Dictionary(
            uniqueKeysWithValues: labeled.map { entry in
                let screenFrame = entry.view.frame.offsetBy(dx: windowOrigin.x, dy: windowOrigin.y)
                return (
                    entry.hinted.identity,
                    HintDebugSnapshot.HintInfo(hint: entry.hinted.hint, frame: screenFrame)
                )
            }
        )

        let frontApp = NSWorkspace.shared.frontmostApplication
        let snapshotURL = HintDebugSnapshot.write(
            recorder: recorder,
            app: frontApp,
            hintInfo: hintInfo
        )

        let summary = recorder.summary()
        Logger.hintMode.debug("debug: visited=\(summary.visited, privacy: .public) accepted=\(summary.accepted, privacy: .public) deduped=\(summary.deduped, privacy: .public) tooSmall=\(summary.rejectedTooSmall, privacy: .public) rejected=\(summary.rejectedNotClickable, privacy: .public) clipped=\(summary.clipped, privacy: .public) pruned=\(summary.prunedSubtrees, privacy: .public) hinted=\(hinted.count, privacy: .public)")
        if let snapshotURL {
            Logger.hintMode.debug("debug: snapshot \(snapshotURL.path, privacy: .public)")
        }

        let overlay = HintDebugOverlayWindow(
            events: recorder.events,
            labeledHints: labeled,
            snapshotPath: snapshotURL?.path
        )
        overlay.show()
        self.overlay = overlay
        HintDebugModeController.isDebugActive = true

        // Use a CGEvent tap (same pattern as hint mode) because a menu-bar
        // app never becomes key and `NSEvent.addLocalMonitorForEvents`
        // therefore never fires.  The tap is gated by `isDebugActive` so
        // it's inert the moment we deactivate.
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let started = eventTap.start(
            eventMask: eventMask,
            isActiveGate: { HintDebugModeController.isDebugActive },
            handler: { type, event in
                guard type == .keyDown else { return Unmanaged.passRetained(event) }
                let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
                if keyCode == 53 {
                    DispatchQueue.main.async {
                        HintDebugModeController.sharedInstance?.deactivateDebugMode()
                    }
                    return nil
                }
                return Unmanaged.passRetained(event)
            }
        )

        if !started {
            Logger.hintMode.warning("Failed to start debug event tap. ESC will not dismiss — use the menu or the debug hotkey.")
        }
    }

    private func deactivateDebugMode() {
        guard HintDebugModeController.isDebugActive else { return }
        HintDebugModeController.isDebugActive = false

        eventTap.stop()

        overlay?.close()
        overlay = nil
    }
}
