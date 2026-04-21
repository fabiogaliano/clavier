//
//  GlobalHotkeyRegistrar.swift
//  clavier
//
//  Shared Carbon hotkey registration abstraction.
//
//  Both hint mode and scroll mode (P2-S3) need identical boilerplate:
//  install a Carbon event handler once per app lifetime, register/unregister
//  a hotkey whose keyCode and modifier flags come from UserDefaults, and
//  pause/resume around the shortcut-recorder sheet.
//
//  Each controller creates one instance with its mode-specific signature and
//  hotkey ID, then hands it a callback to invoke on the main actor when the
//  hotkey fires.
//
//  Threading: InstallEventHandler callbacks run on the main Carbon event loop,
//  so dispatching to @MainActor via Task is safe, matching the original code.
//
//  C function pointer constraint: the EventHandlerProcPtr passed to
//  InstallEventHandler is a C function pointer and cannot capture local
//  variables.  This implementation passes `self` as userData (unretained) so
//  the callback can retrieve all state from the registrar without captures.
//

import Foundation
import Carbon

/// Manages one global Carbon hotkey for a single app mode.
///
/// - Initialize with a 4-character ASCII `signature` that uniquely identifies
///   the mode (e.g. `"KNAV"` for hint mode, `"KSCR"` for scroll mode).
/// - Call `register(keyCodeKey:modifiersKey:onActivation:)` once per app
///   session (typically during `AppDelegate.applicationDidFinishLaunching`).
/// - The `onActivation` closure is dispatched to `@MainActor` each time the
///   hotkey fires.
final class GlobalHotkeyRegistrar {

    let signature: OSType
    let hotkeyID: UInt32

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var keyCodeKey: String = ""
    private var modifiersKey: String = ""
    // Stored as a property so the C callback can retrieve it via userData without capture.
    private var onActivation: (@MainActor () -> Void)?
    // Guards against duplicate NotificationCenter observer installation when register()
    // is called more than once on the same instance (e.g. during settings reload paths).
    private var observersInstalled = false

    init(signature: String, hotkeyID: UInt32) {
        self.signature = OSType(signature.utf8.reduce(0) { ($0 << 8) + OSType($1) })
        self.hotkeyID = hotkeyID
    }

    /// Register the hotkey and start listening for enable/disable notifications.
    ///
    /// Safe to call multiple times — the Carbon event handler is installed only
    /// once (guarded by `eventHandlerRef == nil`).
    ///
    /// - Parameters:
    ///   - keyCodeKey: `UserDefaults` key for the Carbon virtual key code.
    ///   - modifiersKey: `UserDefaults` key for the Carbon modifier flags.
    ///   - onActivation: Closure called on `@MainActor` each time the hotkey fires.
    func register(keyCodeKey: String, modifiersKey: String, onActivation: @escaping @MainActor () -> Void) {
        self.keyCodeKey = keyCodeKey
        self.modifiersKey = modifiersKey
        self.onActivation = onActivation

        installEventHandlerIfNeeded()
        observeShortcutRecorderNotifications()
        registerHotkey()
    }

    // MARK: - Internal

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Pass `self` as userData (unretained).  The callback reads all state
        // from the registrar via this pointer — no local variables are captured.
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData, let event else {
                    return OSStatus(eventNotHandledErr)
                }

                let registrar = Unmanaged<GlobalHotkeyRegistrar>.fromOpaque(userData).takeUnretainedValue()

                var pressedID = EventHotKeyID()
                let err = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressedID
                )

                guard err == noErr,
                      pressedID.signature == registrar.signature,
                      pressedID.id == registrar.hotkeyID else {
                    return OSStatus(eventNotHandledErr)
                }

                guard let activation = registrar.onActivation else {
                    return OSStatus(eventNotHandledErr)
                }

                Task { @MainActor in
                    activation()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    private func observeShortcutRecorderNotifications() {
        guard !observersInstalled else { return }
        observersInstalled = true

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
            self?.registerHotkey()
        }
    }

    private func registerHotkey() {
        guard hotKeyRef == nil else { return }

        let keyCode = UserDefaults.standard.integer(forKey: keyCodeKey)
        let modifiers = UserDefaults.standard.integer(forKey: modifiersKey)

        var hotKeyIDValue = EventHotKeyID()
        hotKeyIDValue.signature = signature
        hotKeyIDValue.id = hotkeyID

        RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            hotKeyIDValue,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func unregisterHotkey() {
        guard let ref = hotKeyRef else { return }
        UnregisterEventHotKey(ref)
        hotKeyRef = nil
    }
}
