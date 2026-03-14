# WS-03: Clickable Detection and Deduplication

## Status

- **Status**: done
- **Priority**: High
- **Depends on**: none
- **Main plan**: [../README.md](../README.md)

## One-Line Summary

- [x] Replace role-only clickability with capability-based detection and preserve distinct nested targets during deduplication.

## Goal

Improve element discovery quality so hint mode finds more real targets, ignores more inert targets, and stops collapsing valid nested targets into a single outer hint.

## Audit Findings Addressed

- Hardcoded role-only clickability heuristics
- Disabled controls being eligible for hints
- `AXStaticText` treated as both clickable and a subtree-prune boundary
- Ancestor-based deduplication removing valid child targets

## Allowed Files

- `keynave/Services/AccessibilityService.swift`
- `keynave/Models/UIElement.swift`
- Optional new helper: `keynave/Services/AXElementSemantics.swift`

## Do Not Touch In This Workstream

- Overlay placement and geometry
- Event tap/hotkey lifecycle
- Scroll detection logic
- Settings validation

## Suggested Read Order

1. `keynave/Services/AccessibilityService.swift`
2. `keynave/Models/UIElement.swift`

## Implementation Tasks

- [x] Inventory the existing `clickableRoles` and `skipSubtreeRoles` usage.
- [x] Define a capability-first notion of clickability using available AX actions, enabled state, focusability, or settable attributes.
- [x] Remove unconditional `AXStaticText` clickability unless a concrete actionable rule justifies it.
- [x] Ensure subtree pruning does not conflict with roles that can still contain actionable descendants.
- [x] Refine deduplication so child targets with distinct frames or distinct action surfaces survive.
- [x] Preserve performance by keeping batch-fetch patterns where possible.
- [x] Keep the public behavior of `HintModeController` unchanged unless absolutely necessary.
- [x] Add concise log entries to this file and the main plan after implementation.

## Acceptance Criteria

- Disabled or inert controls are less likely to receive hints.
- Distinct nested controls are no longer collapsed into one outer hint by default.
- Plain static text is not broadly treated as clickable without actionable evidence.
- The traversal still performs reasonably on large AX trees.

## Manual Verification Notes

- Verify a toolbar with nested buttons.
- Verify a sidebar or table with nested row content.
- Verify a browser or web-app view with link-like descendants.
- Verify that disabled controls do not receive hints.

## Handoff Notes

- Do not add app-specific click detectors yet. That belongs to `WS-07` if still needed.
- Keep this workstream focused on generic AX semantics first.

## Work Log

- **2026-03-14**: Workstream created from the audit findings. No implementation work started yet.
- **2026-03-14**: WS-03 complete. All changes in `AccessibilityService.swift` only; `UIElement.swift` unchanged. Changes: (1) Renamed `clickableRoles` → `interactiveRoles`, removed `AXStaticText` from the set. (2) Added `kAXEnabledAttribute` to batch fetch; disabled elements are now skipped. (3) Added `isElementClickable()` with capability-based fallback: `AXStaticText` is only clickable if it has AXPress/AXShowMenu actions via `AXUIElementCopyActionNames`. (4) Replaced ancestor-only dedup with frame-aware dedup: child elements are only marked as duplicates if their frame edges are within 10px of the ancestor's frame, preserving distinct nested targets. (5) `skipSubtreeRoles` unchanged — reviewed and confirmed no conflicts with actionable descendants. Build passes.
