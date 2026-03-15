# WS-01: Coordinate Foundation and Multi-Display Correctness

## Status

- **Status**: done
- **Priority**: High
- **Depends on**: none
- **Main plan**: [../README.md](../README.md)

## One-Line Summary

- [x] Replace `NSScreen.main` assumptions with a shared coordinate system used by AX traversal, overlay windows, click posting, and scroll posting.

## Goal

Create one reliable coordinate model for the entire app so that:

- AX element frames are interpreted correctly
- visible-window clipping works off the correct desktop bounds
- hint overlays render on the correct display
- click and scroll events target the correct location on any display

## Audit Findings Addressed

- Multi-display coordinate bugs caused by `NSScreen.main`
- Window clipping against the main screen only
- Overlay windows sized to the main display instead of the actual desktop/display set
- Click/scroll Y conversion performed against the wrong screen height

## Allowed Files

- `clavier/Services/AccessibilityService.swift`
- `clavier/Services/HintModeController.swift`
- `clavier/Services/ScrollModeController.swift`
- `clavier/Services/ScrollableAreaService.swift`
- `clavier/Services/ScrollDetection/Detectors/ChromiumDetector.swift`
- `clavier/Views/HintOverlayWindow.swift`
- `clavier/Views/ScrollOverlayWindow.swift`
- Optional new helper: `clavier/Services/ScreenGeometry.swift`

## Do Not Touch In This Workstream

- Clickability heuristics and deduplication rules
- Hint overlap/collision logic
- Hotkey registration lifecycle
- Settings validation

If one of those becomes necessary, stop and update the main plan before widening scope.

## Suggested Read Order

1. `clavier/Services/AccessibilityService.swift`
2. `clavier/Views/HintOverlayWindow.swift`
3. `clavier/Services/HintModeController.swift`
4. `clavier/Services/ScrollableAreaService.swift`
5. `clavier/Services/ScrollDetection/Detectors/ChromiumDetector.swift`
6. `clavier/Views/ScrollOverlayWindow.swift`
7. `clavier/Services/ScrollModeController.swift`

## Implementation Tasks

- [x] Inventory every use of `NSScreen.main` in the allowed files and classify whether it is used for frame conversion, overlay sizing, clipping, or event posting.
- [x] Introduce a shared geometry helper or equivalent abstraction so all coordinate conversion logic lives in one place.
- [x] Replace main-screen-based AX frame flipping with desktop-aware or per-screen-aware conversion.
- [x] Fix visibility clipping so window bounds are not intersected against the main screen only.
- [x] Update hint overlay sizing/placement so hints can render correctly for elements on non-main displays.
- [x] Update scroll overlay sizing/placement so scroll hints and highlights can render correctly for elements on non-main displays.
- [x] Update click posting in `HintModeController` to use the shared geometry conversion.
- [x] Update scroll event targeting in `ScrollModeController` to use the shared geometry conversion.
- [x] Update `ScrollableAreaService` and `ChromiumDetector` to use the same coordinate helper as `AccessibilityService`.
- [x] Add concise log entries to this file and the main plan after implementation.

## Acceptance Criteria

- Elements on a non-main display can still receive hints.
- Overlay windows no longer assume a single main display.
- Clicks land on the intended element on a non-main display.
- Scroll events target the intended area on a non-main display.
- No remaining `NSScreen.main` coordinate conversions remain in the allowed files unless they are explicitly justified in the log.

## Manual Verification Notes

- Verify hint mode on the main display.
- Verify hint mode on a secondary display.
- Verify scroll mode on the main display.
- Verify scroll mode on a secondary display.
- Verify a browser window on a secondary display.

## Handoff Notes

- Keep this workstream focused on geometry only.
- If hint placement still overlaps after this workstream, leave that for `WS-02`.
- If target discovery still misses elements after this workstream, leave that for `WS-03`.

## Work Log

- **2026-03-14**: Workstream created from the audit findings. No implementation work started yet.
- **2026-03-14**: Implementation complete. All 10 checklist items done, build passes.
  - **New file**: `clavier/Services/ScreenGeometry.swift` — `desktopBoundsInAX`, `desktopBoundsInAppKit`, `axToAppKit(position:size:)`, `appKitCenterToQuartz(_:)`, `toWindowLocal(_:)`.
  - **AccessibilityService**: Clipping now uses `desktopBoundsInAX` (union of all screens in AX coords). Y-flip replaced with `ScreenGeometry.axToAppKit`. Removed `origin >= 0` filter that was silently discarding elements on left-of-main or below-main displays. `screenFrame` parameter removed from `traverseElementOptimized`.
  - **HintOverlayWindow**: `contentRect` changed to `desktopBoundsInAppKit`. Container view sized to `self.frame.size` (local origin). Hint label and highlight positions converted via `ScreenGeometry.toWindowLocal`. Search bar kept on main screen (intentional: it is a global input element).
  - **ScrollOverlayWindow**: Same overlay/container sizing fix. Hint label and selection highlight positions converted via `ScreenGeometry.toWindowLocal`.
  - **HintModeController**: `performClick` and `performRightClick` now use `ScreenGeometry.appKitCenterToQuartz`.
  - **ScrollModeController**: `performScroll` now uses `ScreenGeometry.appKitCenterToQuartz`.
  - **ScrollableAreaService**: `createScrollableArea` uses `ScreenGeometry.axToAppKit`. Both `origin >= 0` filters removed.
  - **ChromiumDetector**: `createScrollableArea` uses `ScreenGeometry.axToAppKit`.
