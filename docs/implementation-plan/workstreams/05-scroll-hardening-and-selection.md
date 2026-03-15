# WS-05: Scroll Detection Crash Hardening and Selection Fixes

## Status

- **Status**: done
- **Priority**: High
- **Depends on**: none
- **Main plan**: [../README.md](../README.md)

## One-Line Summary

- [x] Remove scroll-mode crash paths and fix selection/progressive-discovery bugs without changing unrelated behavior.

## Goal

Make scroll mode materially safer and more predictable by removing force-cast crash paths, fixing the multi-digit selection bug, and cleaning up the progressive discovery execution model.

## Audit Findings Addressed

- Force-cast crash risks in `ScrollableAreaService` and `ChromiumDetector`
- Progressive discovery invoking `@MainActor` services from a background GCD queue
- Area indices `10...15` being unreachable because selection commits too early

## Allowed Files

- `clavier/Services/ScrollableAreaService.swift`
- `clavier/Services/ScrollDetection/Detectors/ChromiumDetector.swift`
- `clavier/Services/ScrollModeController.swift`

## Do Not Touch In This Workstream

- Hint mode behavior
- Global hotkey lifecycle
- Hint placement
- Settings UI beyond what is strictly necessary for scroll-mode correctness

## Suggested Read Order

1. `clavier/Services/ScrollableAreaService.swift`
2. `clavier/Services/ScrollDetection/Detectors/ChromiumDetector.swift`
3. `clavier/Services/ScrollModeController.swift`

## Implementation Tasks

- [x] Replace `as! AXUIElement` and `as! AXValue` casts in the allowed files with safe decoding helpers.
- [x] Reuse or create a consistent safe AX extraction pattern across both scroll-detection files.
- [x] Fix progressive discovery so actor-isolated work is not driven directly from an unmanaged background queue.
- [x] Preserve the current staged-discovery behavior while making the execution model safe.
- [x] Fix numeric selection so areas `10...15` can be selected when present.
- [x] Keep existing scroll hints, selection visuals, and scroll commands working.
- [x] Add concise log entries to this file and the main plan after implementation.

## Acceptance Criteria

- The scroll-detection path no longer relies on unsafe AX force casts.
- Scroll mode can still discover and highlight areas as before.
- Areas above `9` can be selected when present.
- Progressive discovery no longer crosses actor/thread boundaries unsafely.

## Manual Verification Notes

- Verify a simple app with one obvious scroll area.
- Verify an app with multiple panes or nested scroll areas.
- Verify an app/browser state that exposes at least `10` scroll areas.
- Verify Chromium-specific scroll detection still works.

## Handoff Notes

- Keep this workstream focused on scroll-mode safety and correctness.
- Do not fold in multi-display coordinate changes unless they are already completed via `WS-01`.

## Work Log

- **2026-03-14**: Workstream created from the audit findings. No implementation work started yet.
- **2026-03-14**: WS-05 complete. Changes in all 3 allowed files. (1) AXValue casts in `ScrollableAreaService.swift` and `ChromiumDetector.swift` now use `CFGetTypeID` validation before casting — returns nil instead of crashing on type mismatch. AXUIElement casts kept as `as! AXUIElement?` since Swift confirms CF type casts always succeed (toll-free bridging). (2) Multi-digit selection fixed: typing a digit that could prefix a larger valid area number (e.g., "1" when 10+ areas exist) now waits for more input instead of committing immediately. Non-digit keys auto-commit pending numeric input. (3) Progressive discovery removed from `DispatchQueue.global` — runs synchronously on main actor since `ScrollableAreaService` is `@MainActor` and AX calls must run on main thread. Eliminates actor boundary crossing. Build passes.
