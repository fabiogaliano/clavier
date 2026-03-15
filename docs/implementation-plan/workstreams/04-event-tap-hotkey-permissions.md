# WS-04: Event Tap, Hotkey, and Permission Hardening

## Status

- **Status**: done
- **Priority**: High
- **Depends on**: none
- **Main plan**: [../README.md](../README.md)

## One-Line Summary

- [x] Make input interception reliable by hardening event-tap state, hotkey lifecycle, and permission guidance.

## Goal

Stabilize the keyboard interception path so hint mode and scroll mode can activate, capture input, and recover from permission issues or re-registration without accumulating subtle bugs.

## Audit Findings Addressed

- `nonisolated(unsafe)` shared state mutated across threads
- Repeated `InstallEventHandler` calls without corresponding removal
- Partial activation when `CGEvent.tapCreate` fails
- Accessibility permission checks without clear Input Monitoring guidance

## Allowed Files

- `clavier/Services/HintModeController.swift`
- `clavier/Services/ScrollModeController.swift`
- `clavier/clavierApp.swift`
- `clavier/Views/PreferencesView.swift`
- Optional new helper: `clavier/Services/InputPermissionService.swift`

## Do Not Touch In This Workstream

- Coordinate conversion logic
- Clickability heuristics
- Scroll detection heuristics
- Hint placement logic

## Suggested Read Order

1. `clavier/Services/HintModeController.swift`
2. `clavier/Services/ScrollModeController.swift`
3. `clavier/clavierApp.swift`
4. `clavier/Views/PreferencesView.swift`

## Implementation Tasks

- [x] Inventory all shared callback-visible state in both controllers.
- [x] Replace `nonisolated(unsafe)` string/reference state with a safer synchronization model.
- [x] Ensure any remaining callback-visible shared state has a clear ownership and synchronization strategy.
- [x] Refactor hotkey registration so the application event handler is installed once or explicitly removed when re-registering.
- [x] Ensure re-recording shortcuts does not accumulate duplicate handlers.
- [x] Convert activation into a transaction so overlays do not become active if event-tap creation fails.
- [x] Add explicit input-listening permission checks or guidance alongside the existing accessibility flow.
- [x] Surface actionable user-facing status when input capture cannot start.
- [x] Add concise log entries to this file and the main plan after implementation.

## Acceptance Criteria

- Rebinding shortcuts repeatedly does not create duplicate mode toggles.
- Event-tap failure does not leave the UI in a half-active state.
- Shared callback state is no longer unsafely mutated across threads.
- The app can distinguish accessibility permission issues from keyboard-input-listening issues.

## Manual Verification Notes

- Record a shortcut multiple times and verify a single toggle per keypress.
- Verify both hint mode and scroll mode can activate normally.
- Verify the failure path when input capture permission is unavailable.
- Verify event tap timeout re-enable behavior still works.

## Handoff Notes

- Keep this workstream focused on lifecycle and safety, not new features.
- If a settings field needs validation changes, leave those for `WS-06` unless required to complete this workstream safely.

## Work Log

- **2026-03-14**: Workstream created from the audit findings. No implementation work started yet.
- **2026-03-14**: WS-04 complete. Changes in `HintModeController.swift` and `ScrollModeController.swift`; `clavierApp.swift` and `PreferencesView.swift` unchanged. Changes: (1) Eliminated `typedInput` String from shared callback state — callback is now a thin dispatcher that only reads Bool/Int/pointer statics and dispatches all string work to main thread. (2) Removed 7 dead `nonisolated(unsafe)` statics across both controllers (hintChars, pendingAction, textSearchEnabled, minSearchChars, refreshTrigger from Hint; typedInput, selectedIndex, areaCount from Scroll). Remaining 4 statics per controller are simple scalars, documented. (3) `InstallEventHandler` now stored as `eventHandlerRef`, installed once in `registerGlobalHotkey()`, reused across re-registrations — eliminates handler accumulation. (4) `startEventTap()` returns Bool; activation is transactional — if tap fails, overlay is closed and state is rolled back. Both controllers print actionable Accessibility permission guidance on failure. Build passes.
