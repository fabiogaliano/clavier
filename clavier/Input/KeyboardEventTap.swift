//
//  KeyboardEventTap.swift
//  clavier
//
//  Shared CGEvent tap lifecycle abstraction.
//
//  Both hint mode and scroll mode (P2-S3) create a CGEvent tap when their
//  mode activates and tear it down on deactivation.  The boilerplate around
//  tap creation, run-loop registration, timeout recovery, and teardown is
//  identical — only the mode-active gate and key-event callback differ.
//
//  Threading contract (preserved from the original controllers):
//  - `CGEventTapCallBack` is a C function pointer — closures that capture
//    local variables cannot be used.  The callback accesses a global slot
//    table (`nonisolated(unsafe) static`) and the slot index is encoded in
//    the `userInfo` raw pointer (bit-cast from Int) so no local variable is
//    captured.
//  - All string/collection mutation is dispatched via `DispatchQueue.main.async`
//    inside the caller-supplied handler.
//  - This class must NOT be annotated @MainActor.
//

import AppKit

/// Manages the CGEvent tap lifecycle for one app mode.
///
/// Usage:
/// 1. Hold one instance for the mode's lifetime.
/// 2. Call `start(eventMask:isActiveGate:handler:)` when the mode activates.
///    Returns `false` if the system cannot create the tap (Accessibility
///    permissions not granted).
/// 3. Call `stop()` when the mode deactivates.
///
/// The `handler` receives raw `(CGEventType, CGEvent)` pairs on the CF run
/// loop thread.  Return a retained `CGEvent` to pass the event through, or
/// `nil` to consume it.  All @MainActor work must be dispatched inside the
/// handler with `DispatchQueue.main.async`.
///
/// The `isActiveGate` closure is evaluated on the CF run loop thread.  It
/// should read a `nonisolated(unsafe)` static Bool (same pattern as the
/// original controllers) to decide whether the mode is currently active.
final class KeyboardEventTap {

    // MARK: - Global slot table
    //
    // Closures passed as C function pointers cannot capture context.
    // The tap callback reads from this static array using the slot index
    // encoded in the userInfo raw pointer, so no local variable is captured.
    //
    // Slot 0 = hint mode (P2-S1), slot 1 = scroll mode (P2-S3).
    // Extended if more than 2 modes need taps concurrently.

    private struct Slot {
        var tap: CFMachPort
        var isActive: () -> Bool
        var handler: (CGEventType, CGEvent) -> Unmanaged<CGEvent>?
    }

    private nonisolated(unsafe) static var slots: [Slot?] = [nil, nil]

    // MARK: - Instance state

    private let slotIndex: Int
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // MARK: - Init

    /// - Parameter slotIndex: Index into the global slot table (0 = hint, 1 = scroll).
    ///   Each mode must use a distinct index.
    init(slotIndex: Int) {
        self.slotIndex = slotIndex
    }

    // MARK: - Lifecycle

    /// Create and activate the CGEvent tap.
    ///
    /// - Parameters:
    ///   - eventMask: CGEvent types to intercept.
    ///   - isActiveGate: Evaluated on the CF run loop thread.  Should read a
    ///     `nonisolated(unsafe)` static Bool.
    ///   - handler: Called for each intercepted event on the CF run loop thread.
    /// - Returns: `true` on success, `false` if the tap could not be created.
    @discardableResult
    func start(
        eventMask: CGEventMask,
        isActiveGate: @escaping () -> Bool,
        handler: @escaping (CGEventType, CGEvent) -> Unmanaged<CGEvent>?
    ) -> Bool {
        // userInfo carries the slot index as an opaque pointer value so the
        // C-function-pointer callback can look up the slot without capturing
        // any local variable.
        let userInfoPtr = UnsafeMutableRawPointer(bitPattern: slotIndex + 1)

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (_, type, event, userInfo) -> Unmanaged<CGEvent>? in
                // Recover from timeout/disable events before doing anything else.
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    let index = Int(bitPattern: userInfo) - 1
                    if index >= 0, index < KeyboardEventTap.slots.count,
                       let slot = KeyboardEventTap.slots[index] {
                        CGEvent.tapEnable(tap: slot.tap, enable: true)
                    }
                    return Unmanaged.passRetained(event)
                }

                let index = Int(bitPattern: userInfo) - 1
                guard index >= 0, index < KeyboardEventTap.slots.count,
                      let slot = KeyboardEventTap.slots[index],
                      slot.isActive() else {
                    return Unmanaged.passRetained(event)
                }

                return slot.handler(type, event)
            },
            userInfo: userInfoPtr
        )

        guard let tap else { return false }

        KeyboardEventTap.slots[slotIndex] = Slot(tap: tap, isActive: isActiveGate, handler: handler)
        eventTap = tap

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// Disable and remove the tap from the run loop.
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        KeyboardEventTap.slots[slotIndex] = nil
        eventTap = nil
        runLoopSource = nil
    }
}
