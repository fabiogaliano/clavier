# Clavier Implementation Plan

## Objective

Implement the audit findings in small, bounded workstreams.

Only **one workstream** may be active at a time.
The agent must not widen scope silently.
If a task needs extra files, the agent must first update this plan and the relevant workstream doc before touching those files.

## Repository Paths

- **Repo root**: `/Users/f/Core/dev/projects/clavier`
- **App source root**: `clavier/`
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

- **Overall status**: done
- **Current active workstream**: none (all complete)
- **Recommended next workstream**: none
- **Execution rule**: do not start a second workstream until the current one is `done`, `blocked`, or `deferred`
- **Last updated**: 2026-03-14

## One-Line Summary of the Changes We Are Making

- [x] `WS-01` Build a shared screen-coordinate foundation so overlays, AX frames, clicks, and scrolls work across all displays.
- [x] `WS-02` Make hint placement collision-aware, bounds-safe, and respectful of a true `0px` offset.
- [x] `WS-03` Replace role-only clickability with capability-based detection and safer deduplication.
- [x] `WS-04` Harden event taps, hotkeys, and permission handling; remove duplicate handler accumulation.
- [x] `WS-05` Remove scroll-mode crash paths and fix progressive discovery plus multi-digit selection.
- [x] `WS-06` Validate user settings and clean up dead refresh/config code.
- [x] `WS-07` Improve overlay performance and parity/extensibility after the core reliability work is stable.

## Workstream Index

| ID | Title | Priority | Status | Depends on | Doc |
| --- | --- | --- | --- | --- | --- |
| `WS-01` | Coordinate foundation and multi-display correctness | High | done | none | [workstreams/01-coordinate-foundation.md](workstreams/01-coordinate-foundation.md) |
| `WS-02` | Hint placement and density control | High | done | `WS-01` | [workstreams/02-hint-placement-and-density.md](workstreams/02-hint-placement-and-density.md) |
| `WS-03` | Clickable detection and deduplication | High | done | none | [workstreams/03-clickable-detection-and-deduplication.md](workstreams/03-clickable-detection-and-deduplication.md) |
| `WS-04` | Event tap, hotkey, and permission hardening | High | done | none | [workstreams/04-event-tap-hotkey-permissions.md](workstreams/04-event-tap-hotkey-permissions.md) |
| `WS-05` | Scroll detection crash hardening and selection fixes | High | done | none | [workstreams/05-scroll-hardening-and-selection.md](workstreams/05-scroll-hardening-and-selection.md) |
| `WS-06` | Settings validation and refresh cleanup | Medium | done | `WS-02`, `WS-04` | [workstreams/06-settings-validation-and-refresh-cleanup.md](workstreams/06-settings-validation-and-refresh-cleanup.md) |
| `WS-07` | Overlay performance and parity/extensibility backlog | Medium | done | `WS-01`, `WS-02`, `WS-03` | [workstreams/07-performance-and-parity-backlog.md](workstreams/07-performance-and-parity-backlog.md) |

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
- `clavier/Services/AccessibilityService.swift`
- `clavier/Services/HintModeController.swift`
- `clavier/Services/ScrollModeController.swift`
- `clavier/Services/ScrollableAreaService.swift`
- `clavier/Services/ScrollDetection/Detectors/ChromiumDetector.swift`
- `clavier/Views/HintOverlayWindow.swift`
- `clavier/Views/ScrollOverlayWindow.swift`
- Optional new helper if needed: `clavier/Services/ScreenGeometry.swift`

### `WS-02`
- `clavier/Views/HintOverlayWindow.swift`
- `clavier/Views/PreferencesView.swift`
- `clavier/clavierApp.swift`
- Optional new helper if needed: `clavier/Views/HintPlacementEngine.swift`

### `WS-03`
- `clavier/Services/AccessibilityService.swift`
- `clavier/Models/UIElement.swift`
- Optional new helper if needed: `clavier/Services/AXElementSemantics.swift`

### `WS-04`
- `clavier/Services/HintModeController.swift`
- `clavier/Services/ScrollModeController.swift`
- `clavier/clavierApp.swift`
- `clavier/Views/PreferencesView.swift`
- Optional new helper if needed: `clavier/Services/InputPermissionService.swift`

### `WS-05`
- `clavier/Services/ScrollableAreaService.swift`
- `clavier/Services/ScrollDetection/Detectors/ChromiumDetector.swift`
- `clavier/Services/ScrollModeController.swift`

### `WS-06`
- `clavier/Views/PreferencesView.swift`
- `clavier/clavierApp.swift`
- `clavier/Services/HintModeController.swift`
- `clavier/Services/ScrollModeController.swift`
- `clavier/Services/AccessibilityService.swift`
- Optional new helper if needed: `clavier/Services/SettingsValidationService.swift`

### `WS-07`
- `clavier/Views/HintOverlayWindow.swift`
- `clavier/Views/ScrollOverlayWindow.swift`
- `clavier/Services/HintModeController.swift`
- `clavier/Services/AccessibilityService.swift`
- `clavier/Services/ScrollDetection/DetectorRegistry.swift`
- Optional new helpers/detectors inside `clavier/Services/ScrollDetection/`

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
- **2026-03-14**: `WS-03` complete. Capability-based clickability in `AccessibilityService.swift`: enabled-state gating via batch-fetched `kAXEnabledAttribute`, `AXStaticText` action-checked via `AXUIElementCopyActionNames`, frame-aware dedup (10px edge tolerance). No new files. Build passes. Recommended next: `WS-04`.
- **2026-03-14**: `WS-04` complete. Hardened event taps and hotkey lifecycle in both controllers. Eliminated shared String state from callbacks (thin dispatcher pattern), removed 7 dead statics, stored EventHandlerRef to prevent handler accumulation, made activation transactional (rollback on tap failure with permission guidance). No new files. Build passes. Recommended next: `WS-05`.
- **2026-03-14**: `WS-05` complete. AXValue casts validated via `CFGetTypeID` in ScrollableAreaService and ChromiumDetector. Multi-digit scroll area selection fixed (waits for more input when digit could prefix a larger area number). Progressive discovery moved from `DispatchQueue.global` to main actor (eliminates actor boundary crossing). No new files. Build passes. Recommended next: `WS-06`.
- **2026-03-14**: `WS-06` complete. Settings validation for hintCharacters/scrollKeys/manualRefreshTrigger. Removed dead `scrollCommandsEnabled` setting. Removed dead UI-change observer code from HintModeController. Consumer-side guard prevents divide-by-zero on invalid hintCharacters. No new files. Build passes. Recommended next: `WS-07`.
- **2026-03-14**: `WS-07` complete. Hoisted UserDefaults reads into `HintStyle` struct (7 prefs read once per refresh instead of per hint). Made `updateHints` incremental (reuses views by hint key). Deferred: click detector registry and search role indexing — not needed based on current capability-based detection. No new files. Build passes. **All 7 workstreams complete.**

## Completion Rules

A workstream counts as `done` only when all of the following are true:

- The code changes are complete within the allowed file set.
- The workstream checklist is fully checked off.
- The workstream log records what changed.
- The main log records the completion.
- The workstream status is updated in both the main file and the workstream file.
- The corresponding summary checkbox at the top of this file is checked.
