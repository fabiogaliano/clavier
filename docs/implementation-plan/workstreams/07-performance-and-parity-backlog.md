# WS-07: Overlay Performance and Parity/Extensibility Backlog

## Status

- **Status**: pending
- **Priority**: Medium
- **Depends on**: `WS-01`, `WS-02`, `WS-03`
- **Main plan**: [../README.md](../README.md)

## One-Line Summary

- [ ] Improve overlay rendering efficiency and prepare targeted extensibility/parity work after the core fixes are stable.

## Goal

Handle the post-stability improvements that are valuable but should not distract from the core reliability work: view reuse, rendering efficiency, app-specific detection hooks, and more advanced search parity.

## Audit Findings Addressed

- Full overlay teardown/rebuild on refresh
- Heavy one-view-per-hint rendering strategy
- Missing app-specific click-detection extension points
- Search/parity gaps versus more mature tools

## Allowed Files

- `keynave/Views/HintOverlayWindow.swift`
- `keynave/Views/ScrollOverlayWindow.swift`
- `keynave/Services/HintModeController.swift`
- `keynave/Services/AccessibilityService.swift`
- `keynave/Services/ScrollDetection/DetectorRegistry.swift`
- Optional new helpers/detectors inside `keynave/Services/ScrollDetection/`

## Do Not Touch In This Workstream

- Base coordinate conversion logic
- Global input lifecycle hardening
- Settings validation unless directly needed by the new feature

## Suggested Read Order

1. `keynave/Views/HintOverlayWindow.swift`
2. `keynave/Views/ScrollOverlayWindow.swift`
3. `keynave/Services/HintModeController.swift`
4. `keynave/Services/AccessibilityService.swift`
5. `keynave/Services/ScrollDetection/DetectorRegistry.swift`

## Implementation Tasks

- [ ] Decide whether to pursue view reuse, pooling, layer-backed drawing, or another minimal rendering optimization.
- [ ] If optimizing overlays, keep the work bounded and avoid changing target-discovery semantics.
- [ ] Evaluate whether click detection needs an app-specific detector registry similar to scroll detection.
- [ ] If app-specific click detectors are added, keep them additive and low-risk.
- [ ] Evaluate lightweight search improvements such as role/type indexing before attempting broader parity work.
- [ ] Record any intentionally deferred parity ideas in the log rather than expanding scope mid-session.
- [ ] Add concise log entries to this file and the main plan after implementation.

## Acceptance Criteria

- Overlay refresh work is measurably less wasteful or better structured.
- Any new extensibility hook is clearly bounded and does not destabilize core detection.
- Core reliability behavior from earlier workstreams remains unchanged.

## Manual Verification Notes

- Compare refresh behavior before and after in a dense UI.
- Verify no regressions in hint filtering, text search, and scroll overlays.
- Verify any new detector registration remains optional and app-specific.

## Handoff Notes

- This is intentionally the last workstream.
- Do not start it before the higher-priority reliability workstreams are stable.

## Work Log

- **2026-03-14**: Workstream created from the audit findings. No implementation work started yet.
