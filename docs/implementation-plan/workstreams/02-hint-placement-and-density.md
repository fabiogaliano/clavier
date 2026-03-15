# WS-02: Hint Placement and Density Control

## Status

- **Status**: done
- **Priority**: High
- **Depends on**: `WS-01`
- **Main plan**: [../README.md](../README.md)

## One-Line Summary

- [x] Make hint placement bounds-safe, overlap-aware, and fully respectful of a real `0px` horizontal offset.

## Goal

Improve hint placement so labels are easier to read and less likely to overlap or render offscreen in dense interfaces.

## Audit Findings Addressed

- Fixed-position hint labels with no collision avoidance
- Offscreen hints near the left edge because of the default negative offset
- `hintHorizontalOffset = 0` behaving like an unset sentinel instead of a real value

## Allowed Files

- `clavier/Views/HintOverlayWindow.swift`
- `clavier/Views/PreferencesView.swift`
- `clavier/clavierApp.swift`
- Optional new helper: `clavier/Views/HintPlacementEngine.swift`

## Do Not Touch In This Workstream

- Coordinate foundation changes from `WS-01`
- Clickability heuristics
- Event tap and hotkey lifecycle
- Scroll mode behavior

## Suggested Read Order

1. `clavier/Views/HintOverlayWindow.swift`
2. `clavier/Views/PreferencesView.swift`
3. `clavier/clavierApp.swift`

## Implementation Tasks

- [x] Remove the `0`-means-default sentinel behavior for `hintHorizontalOffset`.
- [x] Ensure stored defaults come from app defaults registration rather than special-case runtime fallback logic.
- [x] Add viewport clamping so hint labels cannot render outside the visible overlay bounds.
- [x] Add a placement strategy with multiple candidate positions per element instead of a single fixed anchor.
- [x] Add simple collision reduction so already-placed hints influence the next hint placement.
- [x] Preserve current hint styling and search/highlight behavior while improving placement.
- [x] Ensure numbered text-search results still render correctly under the new placement rules.
- [x] Update preferences copy or behavior only as needed to match the real placement semantics.
- [x] Add concise log entries to this file and the main plan after implementation.

## Acceptance Criteria

- Setting `hintHorizontalOffset` to `0` results in an actual `0px` offset.
- Hints near the screen edge are clamped into view.
- Dense views show fewer overlapping hints than before.
- Text-search and numbered-result rendering still works.
- No unrelated behavior changes occur outside hint placement.

## Manual Verification Notes

- Verify a toolbar with densely packed controls.
- Verify a list with repeated row actions.
- Verify a left-edge control where the old negative offset would push the hint offscreen.
- Verify numbered text-search matches.

## Handoff Notes

- This workstream should not change which elements are discovered.
- If placement improvements expose performance problems, record them and leave view reuse for `WS-07`.

## Work Log

- **2026-03-14**: Workstream created from the audit findings. No implementation work started yet.
- **2026-03-14**: Implementation complete. All 9 checklist items done, build passes.
  - **New file**: `clavier/Views/HintPlacementEngine.swift` — stateful engine with `place(element:labelSize:horizontalOffset:)`. Tries 4 candidate positions (primary, nudge-right, vertically-centred, top-right), picks the first non-colliding one, clamps to window bounds.
  - **HintOverlayWindow**: Removed `horizontalOffset != 0 ? ... : -25.0` sentinel; the registered default in `AppDelegate` now takes effect. `createHintLabel` signature changed to `engine: inout HintPlacementEngine`. `setupHintViews`, `updateHints`, and the numbered-mode branch in `filterHints` each create a fresh engine and pass it through. Highlight and prefix-filter paths unchanged.
