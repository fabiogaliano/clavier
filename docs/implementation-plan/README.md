# Keynave Implementation Plan

## Objective

Implement the audit findings in small, bounded workstreams.

Only **one workstream** may be active at a time.
The agent must not widen scope silently.
If a task needs extra files, the agent must first update this plan and the relevant workstream doc before touching those files.

## Repository Paths

- **Repo root**: `/Users/f/Core/dev/projects/keynave`
- **App source root**: `keynave/`
- **Plan root**: `docs/implementation-plan/`
- **Workstream docs**: `docs/implementation-plan/workstreams/`
- **Prompt library**: `docs/implementation-plan/agent-prompts.md`

## Status Legend

- **pending**: not started yet
- **in-progress**: currently being worked on
- **blocked**: cannot continue until an explicit decision or scope update
- **done**: implemented and verified for that workstream
- **deferred**: intentionally postponed until later

## Current Plan Status

- **Overall status**: in-progress
- **Current active workstream**: none (WS-02 done)
- **Recommended next workstream**: `WS-03`
- **Execution rule**: do not start a second workstream until the current one is `done`, `blocked`, or `deferred`
- **Last updated**: 2026-03-14

## One-Line Summary of the Changes We Are Making

- [x] `WS-01` Build a shared screen-coordinate foundation so overlays, AX frames, clicks, and scrolls work across all displays.
- [x] `WS-02` Make hint placement collision-aware, bounds-safe, and respectful of a true `0px` offset.
- [ ] `WS-03` Replace role-only clickability with capability-based detection and safer deduplication.
- [ ] `WS-04` Harden event taps, hotkeys, and permission handling; remove duplicate handler accumulation.
- [ ] `WS-05` Remove scroll-mode crash paths and fix progressive discovery plus multi-digit selection.
- [ ] `WS-06` Validate user settings and clean up dead refresh/config code.
- [ ] `WS-07` Improve overlay performance and parity/extensibility after the core reliability work is stable.

## Workstream Index

| ID | Title | Priority | Status | Depends on | Doc |
| --- | --- | --- | --- | --- | --- |
| `WS-01` | Coordinate foundation and multi-display correctness | High | done | none | [workstreams/01-coordinate-foundation.md](workstreams/01-coordinate-foundation.md) |
| `WS-02` | Hint placement and density control | High | done | `WS-01` | [workstreams/02-hint-placement-and-density.md](workstreams/02-hint-placement-and-density.md) |
| `WS-03` | Clickable detection and deduplication | High | pending | none | [workstreams/03-clickable-detection-and-deduplication.md](workstreams/03-clickable-detection-and-deduplication.md) |
| `WS-04` | Event tap, hotkey, and permission hardening | High | pending | none | [workstreams/04-event-tap-hotkey-permissions.md](workstreams/04-event-tap-hotkey-permissions.md) |
| `WS-05` | Scroll detection crash hardening and selection fixes | High | pending | none | [workstreams/05-scroll-hardening-and-selection.md](workstreams/05-scroll-hardening-and-selection.md) |
| `WS-06` | Settings validation and refresh cleanup | Medium | pending | `WS-02`, `WS-04` | [workstreams/06-settings-validation-and-refresh-cleanup.md](workstreams/06-settings-validation-and-refresh-cleanup.md) |
| `WS-07` | Overlay performance and parity/extensibility backlog | Medium | pending | `WS-01`, `WS-02`, `WS-03` | [workstreams/07-performance-and-parity-backlog.md](workstreams/07-performance-and-parity-backlog.md) |

## Recommended Execution Order

1. `WS-01` Coordinate foundation and multi-display correctness
2. `WS-03` Clickable detection and deduplication
3. `WS-04` Event tap, hotkey, and permission hardening
4. `WS-05` Scroll detection crash hardening and selection fixes
5. `WS-02` Hint placement and density control
6. `WS-06` Settings validation and refresh cleanup
7. `WS-07` Overlay performance and parity/extensibility backlog

## Agent Operating Rules

- **Read order**
  - First read this file.
  - Then read `docs/implementation-plan/agent-prompts.md`.
  - Then read exactly one workstream doc.
  - Then read only the code files listed in that workstream doc.

- **Scope rule**
  - Do not inspect unrelated files.
  - Do not edit unrelated files.
  - If a fix appears to require more files, stop and update the plan docs first.

- **Status rule**
  - When beginning a workstream, set its status to `in-progress` here and in its workstream doc.
  - When finishing, mark it `done` in both places and tick its one-line summary checkbox above.
  - If blocked, mark it `blocked` and record the reason in the main log and in the workstream log.

- **Logging rule**
  - Append concise, dated notes to the log section below.
  - Record what changed, what was verified, and whether scope widened.

- **Session rule**
  - A single implementation session should target one workstream only.
  - It is acceptable to stop mid-workstream.
  - It is not acceptable to start a second workstream in the same session.

## Workstream-to-File Map

### `WS-01`
- `keynave/Services/AccessibilityService.swift`
- `keynave/Services/HintModeController.swift`
- `keynave/Services/ScrollModeController.swift`
- `keynave/Services/ScrollableAreaService.swift`
- `keynave/Services/ScrollDetection/Detectors/ChromiumDetector.swift`
- `keynave/Views/HintOverlayWindow.swift`
- `keynave/Views/ScrollOverlayWindow.swift`
- Optional new helper if needed: `keynave/Services/ScreenGeometry.swift`

### `WS-02`
- `keynave/Views/HintOverlayWindow.swift`
- `keynave/Views/PreferencesView.swift`
- `keynave/keynaveApp.swift`
- Optional new helper if needed: `keynave/Views/HintPlacementEngine.swift`

### `WS-03`
- `keynave/Services/AccessibilityService.swift`
- `keynave/Models/UIElement.swift`
- Optional new helper if needed: `keynave/Services/AXElementSemantics.swift`

### `WS-04`
- `keynave/Services/HintModeController.swift`
- `keynave/Services/ScrollModeController.swift`
- `keynave/keynaveApp.swift`
- `keynave/Views/PreferencesView.swift`
- Optional new helper if needed: `keynave/Services/InputPermissionService.swift`

### `WS-05`
- `keynave/Services/ScrollableAreaService.swift`
- `keynave/Services/ScrollDetection/Detectors/ChromiumDetector.swift`
- `keynave/Services/ScrollModeController.swift`

### `WS-06`
- `keynave/Views/PreferencesView.swift`
- `keynave/keynaveApp.swift`
- `keynave/Services/HintModeController.swift`
- `keynave/Services/ScrollModeController.swift`
- `keynave/Services/AccessibilityService.swift`
- Optional new helper if needed: `keynave/Services/SettingsValidationService.swift`

### `WS-07`
- `keynave/Views/HintOverlayWindow.swift`
- `keynave/Views/ScrollOverlayWindow.swift`
- `keynave/Services/HintModeController.swift`
- `keynave/Services/AccessibilityService.swift`
- `keynave/Services/ScrollDetection/DetectorRegistry.swift`
- Optional new helpers/detectors inside `keynave/Services/ScrollDetection/`

## How to Start or Resume Work

Use the prompts in [agent-prompts.md](agent-prompts.md).

Recommended first session:
- Start with `WS-01`.
- Keep the session limited to the allowed files in `WS-01`.
- Do not mix in hint placement or clickability work yet.

## Main Log

- **2026-03-14**: Audit completed across all Swift files. Findings were grouped into bounded implementation workstreams.
- **2026-03-14**: Created the implementation-plan package under `docs/implementation-plan/`.
- **2026-03-14**: No implementation work has started yet. `WS-01` is the recommended first workstream.
- **2026-03-14**: `WS-01` complete. Added `ScreenGeometry.swift`; removed all `NSScreen.main`-based coordinate assumptions from the 7 allowed files. Build passes. Recommended next: `WS-03`.
- **2026-03-14**: `WS-02` complete. Added `HintPlacementEngine.swift`; removed sentinel in `HintOverlayWindow`, added viewport clamping and 4-candidate collision reduction. Build passes. Recommended next: `WS-03`.

## Completion Rules

A workstream counts as `done` only when all of the following are true:

- The code changes are complete within the allowed file set.
- The workstream checklist is fully checked off.
- The workstream log records what changed.
- The main log records the completion.
- The workstream status is updated in both the main file and the workstream file.
- The corresponding summary checkbox at the top of this file is checked.
