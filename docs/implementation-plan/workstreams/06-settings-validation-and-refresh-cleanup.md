# WS-06: Settings Validation and Refresh Cleanup

## Status

- **Status**: done
- **Priority**: Medium
- **Depends on**: `WS-02`, `WS-04`
- **Main plan**: [../README.md](../README.md)

## One-Line Summary

- [x] Make settings safe to save and remove dead or half-wired refresh/config paths.

## Goal

Prevent invalid preferences from putting the app into broken states, and either wire up or remove dead code paths that currently add complexity without delivering behavior.

## Audit Findings Addressed

- Unvalidated `hintCharacters` and `scrollKeys`
- Dead `scrollCommandsEnabled` setting
- Unused UI-change observer state in `HintModeController`
- Mixed sentinel/default behavior in settings-driven runtime code

## Allowed Files

- `clavier/Views/PreferencesView.swift`
- `clavier/clavierApp.swift`
- `clavier/Services/HintModeController.swift`
- `clavier/Services/ScrollModeController.swift`
- `clavier/Services/AccessibilityService.swift`
- Optional new helper: `clavier/Services/SettingsValidationService.swift`

## Do Not Touch In This Workstream

- Geometry and multi-display conversion
- Overlay placement algorithms
- Scroll detection heuristics
- Large performance refactors

## Suggested Read Order

1. `clavier/Views/PreferencesView.swift`
2. `clavier/clavierApp.swift`
3. `clavier/Services/HintModeController.swift`
4. `clavier/Services/ScrollModeController.swift`
5. `clavier/Services/AccessibilityService.swift`

## Implementation Tasks

- [x] Define validation rules for `hintCharacters`.
- [x] Define validation rules for `scrollKeys`.
- [x] Prevent invalid values from being saved or normalize them before use.
- [x] Ensure defaults are registered centrally instead of relying on runtime zero/unset sentinels.
- [x] Decide whether `scrollCommandsEnabled` should be implemented or removed; then complete that choice fully.
- [x] Decide whether the UI-change observer path in `HintModeController` should be wired up or removed; then complete that choice fully.
- [x] Remove dead state or dead code paths left behind by the chosen refresh model.
- [x] Add concise log entries to this file and the main plan after implementation.

## Acceptance Criteria

- Invalid settings can no longer crash hint generation or silently break input behavior.
- Any user-facing settings in Preferences correspond to real behavior.
- Dead refresh/config code is either fully wired or fully removed.
- Defaults are explicit and consistent.

## Manual Verification Notes

- Try empty, duplicate, and too-short `hintCharacters` inputs.
- Try invalid `scrollKeys` inputs.
- Verify Preferences still reflects saved values correctly.
- Verify hint mode and scroll mode still start normally after validation changes.

## Handoff Notes

- Prefer minimal behavior changes.
- If a cleanup decision is ambiguous, document it in the log rather than silently changing product behavior.

## Work Log

- **2026-03-14**: Workstream created from the audit findings. No implementation work started yet.
- **2026-03-14**: WS-06 complete. (1) `hintCharacters` and `scrollKeys` TextFields now auto-normalize to lowercase unique alpha on every keystroke; `hintCharacters` caps at 4 chars. Consumer-side guard in `assignHints()` falls back to default if < 2 chars — prevents divide-by-zero. (2) `manualRefreshTrigger` resets to "rr" if cleared. (3) `scrollCommandsEnabled` removed: dead setting never read by any controller — removed from PreferencesView, clavierApp defaults. (4) Dead UI-change observer removed from HintModeController: `startUIChangeObserver()`, `stopUIChangeObserver()`, `handleUIChangeDetected()` and related instance vars (`uiChangeObserver`, `isWaitingForUIChange`, `refreshFallbackTask`) deleted — never called, timer-based refresh is the active path. Build passes.
