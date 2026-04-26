# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

clavier is a macOS menu bar app providing keyboard-driven UI navigation similar to Homerow. It overlays clickable hints on UI elements, allowing users to click anywhere using keyboard shortcuts instead of the mouse.

## Build & Development

```bash
# Build from command line
xcodebuild -project clavier.xcodeproj -scheme clavier -configuration Debug build

# Run tests
xcodebuild -project clavier.xcodeproj -scheme clavierTests -configuration Debug -destination 'platform=macOS,arch=arm64' test

# Run via Xcode
open clavier.xcodeproj
# Then Cmd+R to build and run
```

**Requirements:**
- macOS 14.0+ (uses modern SwiftUI APIs)
- Xcode 15+
- Accessibility permissions must be granted in System Settings > Privacy & Security > Accessibility

## Architecture

### Core Flow - Hint Mode
1. **Activation**: Global hotkey (default ⌘⇧Space, configurable) triggers `HintModeController.toggleHintMode()`
2. **Discovery**: `AccessibilityService` delegates AX-tree traversal to `ClickableElementWalker`; clickability and ancestor dedup live in `ClickabilityPolicy` / `AncestorDedupePolicy`.
3. **Hint Assignment**: `HintAssigner` produces two- or three-character tokens drawn from the configured `hintCharacters` alphabet and wraps each `UIElement` in a `HintedElement`.
4. **Overlay**: `HintOverlayRenderer` owns the `HintOverlayWindow` lifecycle; the window renders hints as positioned labels.
5. **Input Processing**: `KeyboardEventTap` intercepts key events; `HintInputDecoder` → `HintInputReducer` map them into a `HintSession` state transition and a list of `HintSideEffect`s.
6. **Click Execution**: `HintActionPerformer` tries `AXUIElementPerformAction` first and falls back to a synthesized `CGEvent` click via `ClickService`.
7. **Continuous mode**: `HintRefreshCoordinator` schedules an optimistic + fallback refresh cycle after a click, tuned by `HintRefreshTimingPolicy` / `AppTimingRegistry` per frontmost bundle.

### Core Flow - Scroll Mode
1. **Activation**: Global hotkey (default ⌥E, configurable) triggers `ScrollModeController.toggleScrollMode()`
2. **Discovery**: `ScrollDiscoveryCoordinator` drives two-phase discovery via `ScrollableAreaService` + `ScrollableAreaMerger`; app-specific detectors (e.g. `ChromiumDetector`) can short-circuit traversal via `DetectorRegistry`.
3. **Hint Assignment**: Numbered strings ("1", "2", …) are paired with each `ScrollableArea` as a `NumberedArea`.
4. **Area Selection**: `ScrollInputDecoder` → `ScrollSelectionReducer` drive the `ScrollSession` state machine; arrow keys select or scroll depending on `scrollArrowMode`.
5. **Scrolling**: `ScrollCommandExecutor` dispatches `ScrollDirection` commands at configured speeds via `ClickService`.
6. **Speed Control**: Hold Shift for dash speed (faster scrolling).
7. **Auto-deactivation**: Optional timer deactivates scroll mode after inactivity.

### Key Components

**Controllers (singletons, @MainActor):**
- `HintModeController` - Orchestrates hint mode lifecycle; owns the `HintSession` state machine and dispatches `HintSideEffect`s.
- `ScrollModeController` - Orchestrates scroll mode lifecycle; owns the `ScrollSession` state machine and dispatches `ScrollSideEffect`s.

**Services & coordinators (@MainActor):**
- `AccessibilityService` - Facade for clickable-element discovery; delegates to `ClickableElementWalker`.
- `ClickableElementWalker` / `ClickabilityPolicy` / `AncestorDedupePolicy` - Pure policies around AX traversal.
- `AXReader` / `AXTextHydrator` - Batched AX reads and lazy text-attribute hydration (both `@MainActor`; AX is main-thread-only).
- `ScrollableAreaService` / `ScrollableAreaMerger` / `ScrollableAXProbe` - Scrollable-area discovery, merging, and shared AX probe.
- `HintOverlayRenderer` / `ScrollOverlayRenderer` - Overlay window lifecycle wrappers.
- `HintRefreshCoordinator` - Optimistic + fallback refresh after a click (continuous mode).
- `ScrollDiscoveryCoordinator` / `ScrollCommandExecutor` - Two-phase discovery driver and scroll-event dispatcher.
- `HintInputDecoder` / `ScrollInputDecoder` - CF run-loop-safe `CGEvent` decoders.
- `HintInputReducer` / `ScrollSelectionReducer` - Pure state reducers (session + command → next session + effects).
- `HintActionPerformer` - AX primary/secondary action with `CGEvent` fallback.
- `HintAssigner` - Pure hint-token mapping.
- `ClickService` - Posts `CGEvent` mouse and scroll wheel events.
- `GlobalHotkeyRegistrar` / `KeyboardEventTap` - Carbon hotkey and event-tap wrappers.
- `ChromiumAccessibilityWaker` - Sets `AXManualAccessibility` on known Electron apps so their dormant AX tree populates. See `docs/chromium-apps.md`.

**Models:**
- `UIElement` - Immutable discovery record: AX element, frame, visible frame, role, stable ID, and optional hydrated `textAttributes`. Does **not** carry the hint token — see `HintedElement`.
- `HintedElement` - Presentation pairing of a `UIElement` with its session-scoped hint string.
- `HintSession` - Explicit state for hint mode: `.inactive`, `.active(hintedElements, filter)`, `.textSearch(hintedElements, matches, filter)`.
- `ScrollableArea` - Immutable discovery record for scroll containers (AX element, frame, stable ID).
- `NumberedArea` - Presentation pairing of a `ScrollableArea` with its numeric hint.
- `ScrollSession` - Explicit state for scroll mode: `.inactive`, `.active(areas, selected, pendingInput)`.
- `ElementTextAttributes`, `ElementIdentity`, `AreaIdentity` - Supporting value types.

**Views:**
- `HintOverlayWindow` - Borderless `.screenSaver`-level `NSWindow` rendering hint labels and highlights.
- `ScrollOverlayWindow` - Overlay window for numbered scroll-area indicators and selection highlight.
- `PreferencesView` - SwiftUI Settings form with four tabs (Clicking, Scrolling, Appearance, General).
- `ShortcutRecorderView` - SwiftUI component for recording custom keyboard shortcuts with live preview.

**App infrastructure:**
- `clavierApp` - SwiftUI App entry point with hidden window bridge for opening Settings.
- `AppDelegate` - Sets up menu bar status item; registers defaults and hotkeys.
- `Logging.swift` - Shared `os.Logger` instances under subsystem `fabiogaliano.clavier` (categories: `app`, `hintMode`, `scrollMode`, `accessibility`, `scrollDetect`).

### Important Patterns

**Coordinate systems:**
- macOS Accessibility API uses bottom-left origin (Quartz coordinates).
- `ScreenGeometry` performs the Y flip to AppKit top-left for UI positioning, and the reverse flip back to Quartz for synthesized clicks.

**Event tap threading:**
- Event-tap callback runs on the CF run loop, not on the main actor.
- `nonisolated(unsafe)` static scalars are used for thread-safe gate state.
- UI/state mutations are dispatched back to the main queue via `DispatchQueue.main.async`.
- All Accessibility API calls are confined to `@MainActor` per Apple DTS guidance (see `claudedocs/api-research.md`).

**Settings persistence:**
- `UserDefaults` + `@AppStorage` for preferences.
- `AppSettings` is the typed boundary: parse-on-read accessors return validated domain values (`HintCharacters`, `ScrollKeymap`, `ScrollArrowMode`) rather than raw strings.
- Defaults are registered in `AppSettings.registerDefaults()` at app launch.

**Chromium-based app support:**
- Electron apps (Slack, Discord, Notion, etc.) ship with their AX tree dormant. `ChromiumAccessibilityWaker` writes `AXManualAccessibility = true` on the app element to wake it; `AppDelegate` triggers the wake on `NSWorkspace.didActivateApplicationNotification`, and `AccessibilityService` re-applies it before each walk as a fallback.
- Toggleable via `chromiumAccessibilityWakeEnabled` (default true).
- CEF apps (Spotify) need a different approach — currently unimplemented; see `docs/chromium-apps.md`.
- Full background, allow-list maintenance, and known dead ends: `docs/chromium-apps.md`.

**Hotkey coordination:**
- `Notification.Name.disableGlobalHotkeys` — posted when the shortcut recorder opens.
- `Notification.Name.enableGlobalHotkeys` — posted when the shortcut recorder closes.
- `GlobalHotkeyRegistrar` observes these and unregisters/re-registers.

**Structured logging:**
- Use `Logger.hintMode`, `Logger.scrollMode`, etc. from `App/Logging.swift`.
- `.warning` for operational failures (event-tap creation, missing permissions).
- `.debug` for perf traces; stream with `log stream --level debug --predicate 'subsystem == "fabiogaliano.clavier"'`.
- Do not use `print(...)` in production paths.

### User Preferences

Stored in `UserDefaults` — keys live in `AppSettings.Keys`, defaults in `AppSettings.Defaults`.

**Hint Mode (activation & behaviour):**
- `hintShortcutKeyCode` (Int): Virtual key code (default: 49 = Space).
- `hintShortcutModifiers` (Int): Carbon modifier flags (default: cmdKey | shiftKey).
- `hintCharacters` (String): Alphabet used for hint tokens (default: `"asdfhjkl"`).
- `textSearchEnabled` (Bool): Enable text-search sub-mode (default: true).
- `minSearchCharacters` (Int): Characters typed before text search engages (default: 2).
- `manualRefreshTrigger` (String): Characters typed to force a refresh in continuous mode (default: `"rr"`).
- `continuousClickMode` (Bool): Stay in hint mode after clicking; hints are refreshed for the next click.
- `autoHintDeactivation` (Bool): Auto-exit continuous mode after inactivity (default: true).
- `hintDeactivationDelay` (Double): Seconds before auto-deactivation (default: 5.0).

**Hint Mode (appearance):**
- `hintSize` (Double): Font size (10–20pt, default: 12).
- `hintBackgroundHex`, `hintBorderHex`, `hintTextHex`, `highlightTextHex` (String): Hex colors for the four overlay surfaces.
- `hintBackgroundOpacity`, `hintBorderOpacity` (Double): 0–1 opacity for tint/border (defaults: 0.3 / 0.6).
- `hintHorizontalOffset` (Double): Pixel offset for hint placement, −200…+200 (default: −25).

**Scroll Mode:**
- `scrollShortcutKeyCode` (Int): Virtual key code (default: 14 = E).
- `scrollShortcutModifiers` (Int): Carbon modifier flags (default: optionKey).
- `scrollKeys` (String): Four characters for directions; persisted raw, parsed through `ScrollKeymap` (default: `"hjkl"`).
- `scrollArrowMode` (String → `ScrollArrowMode` enum): `"select"` or `"scroll"` (default: `.select`).
- `scrollSpeed` (Double): Normal scroll speed multiplier (default: 5.0).
- `dashSpeed` (Double): Fast scroll speed with Shift (default: 9.0).
- `autoScrollDeactivation` (Bool): Auto-exit scroll mode after inactivity (default: true).
- `scrollDeactivationDelay` (Double): Seconds before auto-deactivation (default: 5.0).
- `showScrollAreaNumbers` (Bool): Display numbered hints on scroll areas (default: true).

**Chromium app support (General tab):**
- `chromiumAccessibilityWakeEnabled` (Bool, default: true): Wake the AX tree of known Electron apps via `AXManualAccessibility`. Disable to minimise CPU/memory impact in those apps when not using clavier with them. No effect on Chrome / Arc / Edge / Brave / VS Code (they manage their own).

## Key Technical Details

- Carbon Event Manager registers the global hotkeys (supports custom shortcuts).
- The event tap requires Accessibility permissions to intercept keyboard events.
- Overlay windows use `.screenSaver` level to appear above all content.
- Hints use a monospaced system font for consistent sizing.
- Backspace deletes the last typed character; ESC has two-stage behaviour in hint mode (clear search, then exit) and single-stage in scroll mode.
- Scroll mode uses `CGEvent` scroll-wheel events at configurable speed multipliers.
- `ShortcutRecorderView` uses `NSEvent` monitors to capture key combinations in real time.
- Carbon modifier constants (`cmdKey`, `shiftKey`, `optionKey`, `controlKey`) are used for hotkey storage.
