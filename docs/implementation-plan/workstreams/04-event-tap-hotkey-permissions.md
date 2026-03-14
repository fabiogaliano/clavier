# WS-04: Event Tap, Hotkey, and Permission Hardening

## Status

- **Status**: pending
- **Priority**: High
- **Depends on**: none
- **Main plan**: [../README.md](../README.md)

## One-Line Summary

- [ ] Make input interception reliable by hardening event-tap state, hotkey lifecycle, and permission guidance.

## Goal

Stabilize the keyboard interception path so hint mode and scroll mode can activate, capture input, and recover from permission issues or re-registration without accumulating subtle bugs.

## Audit Findings Addressed

- `nonisolated(unsafe)` shared state mutated across threads
- Repeated `InstallEventHandler` calls without corresponding removal
- Partial activation when `CGEvent.tapCreate` fails
- Accessibility permission checks without clear Input Monitoring guidance

## Allowed Files

- `keynave/Services/HintModeController.swift`
- `keynave/Services/ScrollModeController.swift`
- `keynave/keynaveApp.swift`
- `keynave/Views/PreferencesView.swift`
- Optional new helper: `keynave/Services/InputPermissionService.swift`

## Do Not Touch In This Workstream

- Coordinate conversion logic
- Clickability heuristics
- Scroll detection heuristics
- Hint placement logic

## Suggested Read Order

1. `keynave/Services/HintModeController.swift`
2. `keynave/Services/ScrollModeController.swift`
3. `keynave/keynaveApp.swift`
4. `keynave/Views/PreferencesView.swift`

## Implementation Tasks

- [ ] Inventory all shared callback-visible state in both controllers.
- [ ] Replace `nonisolated(unsafe)` string/reference state with a safer synchronization model.
- [ ] Ensure any remaining callback-visible shared state has a clear ownership and synchronization strategy.
- [ ] Refactor hotkey registration so the application event handler is installed once or explicitly removed when re-registering.
- [ ] Ensure re-recording shortcuts does not accumulate duplicate handlers.
- [ ] Convert activation into a transaction so overlays do not become active if event-tap creation fails.
- [ ] Add explicit input-listening permission checks or guidance alongside the existing accessibility flow.
- [ ] Surface actionable user-facing status when input capture cannot start.
- [ ] Add concise log entries to this file and the main plan after implementation.

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
