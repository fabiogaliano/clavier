# Clavier Architecture Refactor — Implementation Phases

_Last updated: 2026-04-21_

## Framing note

This is a **future-state implementation plan** based on the architecture analysis completed in this conversation on 2026-04-21.

The goal is to improve structure, coupling, and maintainability **without changing product behavior** (shortcuts, hint/scroll UX, settings semantics) unless explicitly called out.

This file is the source of truth for sequencing this refactor.

---

## Current repo state (grounded snapshot)

Primary Swift modules reviewed:

- `clavier/Services/HintModeController.swift` (~771 LOC)
- `clavier/Services/ScrollModeController.swift` (~626 LOC)
- `clavier/Services/ScrollableAreaService.swift` (~532 LOC)
- `clavier/Services/AccessibilityService.swift` (~423 LOC)
- `clavier/Views/HintOverlayWindow.swift` (~397 LOC)
- `clavier/Views/PreferencesView.swift` (~550 LOC)
- `clavier/clavierApp.swift` (~234 LOC)

Key current-state findings that drive dependencies:

1. Hotkey/event-tap infrastructure is duplicated across hint + scroll controllers.
2. Scroll area dedupe/nesting heuristics are duplicated in service + controller.
3. Settings/defaults/validation are spread across `@AppStorage`, `UserDefaults`, and app bootstrap.
4. AX extraction/parsing logic is duplicated and includes unsafe cast paths.
5. Models (`UIElement`, `ScrollableArea`) mix discovery data with presentation state (`hint`, mutable flags).
6. Overlays key some view reuse by hint token instead of stable entity identity.
7. Several modules are oversized and multi-responsibility (>200–300 LOC).

---

## Non-negotiable implementation rules

1. Keep behavior parity unless a phase explicitly states a behavior change.
2. Land shared contracts before branch parallelization.
3. Prefer additive refactors with adapter shims, then remove legacy code in follow-up PRs.
4. No force casts in newly touched AX parsing paths.
5. Each phase must remain reviewable in bounded PRs.

---

## Dependency map (what must exist before what)

### Shared-contract gate (must land first)
These contracts are prerequisites for safe parallel work:

- Typed settings contract (keys/defaults/validation in one place)
- Key/shortcut mapping contract
- AX value/frame reader contract
- Scroll-area merge policy contract
- Stable identity contract for discovered entities

Without these, parallel branches will reintroduce duplicated rules.

---

## Complete findings inventory (scope lock)

All items below are in scope for this refactor. None are optional.

### High-impact findings (must be fully resolved)

- **F01 — Hint mode god object decomposition**
  - Location: `clavier/Services/HintModeController.swift` (~53–127, ~138–221, ~313–448, ~450–619, ~632–748)
  - Required outcome: `HintModeController` becomes orchestration-only; hotkey/tap/input/reducer/refresh/render concerns split.

- **F02 — Scroll mode god object decomposition**
  - Location: `clavier/Services/ScrollModeController.swift` (~43–117, ~128–336, ~417–483, ~485–617)
  - Required outcome: `ScrollModeController` becomes orchestration-only with shared infrastructure.

- **F03 — Duplicate scroll merge/dedupe logic unification**
  - Location: `clavier/Services/ScrollableAreaService.swift` (~28–149), `clavier/Services/ScrollModeController.swift` (~255–336)
  - Required outcome: single `ScrollableAreaMerger` policy reused for initial + progressive discovery.

- **F04 — Stringly settings centralization**
  - Location: `clavier/Views/PreferencesView.swift` (~13–43), `clavier/clavierApp.swift` (~114–148), runtime reads in controllers/overlays
  - Required outcome: typed settings contract/store with one source of truth for keys/defaults/validation.

- **F05 — Domain/presentation model separation**
  - Location: `clavier/Models/UIElement.swift`, `clavier/Models/ScrollableArea.swift`, hint assignment in controllers
  - Required outcome: immutable discovered entities + separate hinted/selected presentation mapping.

- **F06 — Hint overlay identity correctness**
  - Location: `clavier/Views/HintOverlayWindow.swift` (`hintViews: [String: NSView]`, `updateHints(with:)`), `UIElement.id = UUID()`
  - Required outcome: overlay diff keyed by stable element identity, not hint token string.

- **F07 — AX extraction dedupe + cast safety**
  - Location: `ScrollableAreaService.createScrollableArea`, `ChromiumDetector.createScrollableArea`, force-cast paths in AX code
  - Required outcome: shared typed AX reader (`AXFrameReader`/equivalent), no force casts in touched AX paths.

- **F08 — Detector boundary decoupling**
  - Location: `AppSpecificDetector` delay fields (`optimisticRefreshDelay`, `fallbackRefreshDelay`), `HintModeController` via `DetectorRegistry.refreshDelays(...)`
  - Required outcome: split scroll detection from hint refresh timing policy (separate contracts/registries).

- **F09 — Preferences module decomposition + utility extraction**
  - Location: `clavier/Views/PreferencesView.swift` (550 LOC), includes unrelated helper views/extensions; unused `hintColor` key exists
  - Required outcome: tab/component/util split + color utilities extracted + remove dead `hintColor` setting.

- **F10 — Dead/unused surface cleanup**
  - Location examples:
    - `AccessibilityService` observer API (`startObservingUIChanges`, `stopObservingUIChanges`, `handleUIChangeNotification`)
    - `ScrollOverlayWindow.updateAllAreas`, `ScrollOverlayWindow.filterHints`
    - `ScrollableAreaService.findFocusedScrollableAreaIndex`, `findScrollableAreaUnderCursorIndex`
    - `SettingsOpenerView.findSettingsWindow`
  - Required outcome: each API is either wired+covered or removed.

### File-size decomposition findings (>200 LOC)

- **F11** `HintModeController.swift` (771) split by infra/state/render/refresh.
- **F12** `ScrollModeController.swift` (626) split similarly + shared infra.
- **F13** `PreferencesView.swift` (550) split by tabs/components/utilities.
- **F14** `ScrollableAreaService.swift` (532) split traversal/focus helpers/merger.
- **F15** `AccessibilityService.swift` (423) split traversal/text hydration/observer concerns.
- **F16** `HintOverlayWindow.swift` (397) split renderer/searchbar/highlight lifecycle.
- **F17** `ScrollOverlayWindow.swift` (253) isolate selection/highlight + trim unused APIs.
- **F18** `clavierApp.swift` (234) split app entry/settings bridge/app delegate infra.
- **F19** `ShortcutRecorderView.swift` (232) split recorder sheet + key formatting map.
- **F20** `ChromiumDetector.swift` (202) split AX frame reading helper.

### Additional architecture improvements (<200 LOC and cross-cutting)

- **F21** Models: enforce domain vs presentation separation (`UIElement`, `ScrollableArea`).
- **F22** Move `ScrollDirection` out of `ClickService` into a neutral domain/input namespace.
- **F23** Replace bool-based detector continuation flags with explicit enum decision type.
- **F24** Split `DetectorRegistry` responsibilities: scroll detector registry vs hint refresh timing policy.
- **F25** Add focused tests for `HintPlacementEngine` placement/collision/clamping behavior.
- **F26** Keep `ScreenGeometry` architecture intact (no decomposition needed; preserve as shared coordinate boundary).

### Finding-to-phase mapping

- **Phase 1:** F04, F07, F03 (contract layer), F21 (identity primitives), F20 (AX helper extraction start)
- **Phase 2:** F03 (integration), F12 (shared infra portion), F19 (key map extraction/use), F22 (command/input boundary prep)
- **Phase 3:** F05, F06, F21
- **Phase 4:** F01, F02, F08, F11, F12, F14, F15, F20, F22, F23, F24
- **Phase 5:** F09, F10, F13, F16, F17, F18, F19 (remaining split), F25, F26 (explicitly preserved)

---

## Phase breakdown

## Phase 1 — Shared Contracts Foundation (Gate)

**Goal**
Create shared contracts that remove duplicated logic and define stable boundaries.

**Why it exists**
All later decomposition depends on consistent settings, input mapping, AX parsing, and merge behavior.

**Inputs / dependencies**
- Existing controllers/services/views as currently implemented.
- No prior refactor phases required.

**Outputs**
- Central settings schema/access layer (typed read/write + defaults + validation) for hint/scroll/appearance domains.
- Shared keycode/shortcut mapping utilities used by both controllers and shortcut UI.
- Shared AX extraction helpers for frame/attribute decoding (`AXFrameReader`-style boundary).
- Shared scroll-area relationship/merge policy contract/module (single policy source).
- Stable ID type(s) for discovered element/area identity.

**Findings resolved in this phase**
- F04, F07, F03 (contract layer), F21 (identity primitives), F20 (AX helper extraction start).

**Key touchpoints**
- `clavier/clavierApp.swift`
- `clavier/Views/PreferencesView.swift`
- `clavier/Views/ShortcutRecorderView.swift`
- `clavier/Services/AccessibilityService.swift`
- `clavier/Services/ScrollableAreaService.swift`
- `clavier/Services/ScrollDetection/Detectors/ChromiumDetector.swift`
- `clavier/Models/UIElement.swift`
- `clavier/Models/ScrollableArea.swift`

**Risks**
- Default-value drift if migration is incomplete.
- Hidden behavior differences from central validation.

**Parallelizable within phase**
- A: settings/keymap extraction
- B: AX reader extraction
- C: area-merge policy extraction
- Integration/adoption is serial at phase end.

**Exit criteria**
- No duplicated key maps across controllers/views.
- AX frame parsing is centralized in touched modules.
- Scroll merge policy exists as single implementation.
- Settings defaults/validation are defined in one contract layer.
- No force casts remain in newly touched AX parsing paths.

---

## Phase 2 — Infrastructure Consolidation (Two Branches)

**Goal**
Replace duplicated runtime infrastructure while preserving behavior.

**Why it exists**
Controllers are currently overloaded by infrastructure concerns.

**Inputs / dependencies**
- Phase 1 complete.

**Outputs**
- Shared hotkey registrar abstraction.
- Shared keyboard event-tap lifecycle abstraction.
- Shared command decoding entry point (hint/scroll adapters).
- Shared `ModeController`-style lifecycle/command boundary for hint + scroll orchestration.
- Scroll progressive-discovery path uses the shared merge policy only.

**Findings resolved in this phase**
- F03 (integration), F12 (shared infra portion), F19 (key formatting/map extraction start), F22 (input boundary prep).

**Key touchpoints**
- `clavier/Services/HintModeController.swift`
- `clavier/Services/ScrollModeController.swift`
- `clavier/Services/ScrollableAreaService.swift`
- `clavier/Views/ScrollOverlayWindow.swift`

**Risks**
- Input regression (ESC/backspace/numeric behavior).
- Subtle area ordering changes during progressive discovery.

**Parallelizable within phase**
- Branch 2A (Input infra): hotkeys + event taps + command decoding adapters.
- Branch 2B (Scroll pipeline): progressive discovery + dedupe convergence.
- Final integration check is serial.

**Exit criteria**
- Hint + scroll controllers both use shared input infra.
- Scroll controller no longer reimplements dedupe/nesting geometry logic.

---

## Phase 3 — Domain Model & Session State Normalization

**Goal**
Separate discovered domain entities from UI presentation/session state.

**Why it exists**
Current mutable models and sentinel flags make state transitions error-prone.

**Inputs / dependencies**
- Phase 1 contracts.
- Phase 2 input and scroll infrastructure in place.

**Outputs**
- Distinct domain snapshots vs presentation mappings (e.g., hinted/selected wrappers).
- Explicit state models for hint and scroll sessions (no illegal mixed states).
- Removal/reduction of sentinel index + multi-flag state coupling.
- Stable identity-based overlay diff strategy (not hint-token keyed reuse).

**Findings resolved in this phase**
- F05, F06, F21.

**Key touchpoints**
- `clavier/Models/UIElement.swift`
- `clavier/Models/ScrollableArea.swift`
- `clavier/Services/HintModeController.swift`
- `clavier/Services/ScrollModeController.swift`
- `clavier/Views/HintOverlayWindow.swift`
- `clavier/Views/ScrollOverlayWindow.swift`

**Risks**
- State transition edge-case regressions (text-search numbered mode, selection clearing).

**Parallelizable within phase**
- Hint state model and scroll state model can be developed in parallel after shared state primitives are defined.

**Exit criteria**
- Session state is represented by explicit types/state enums.
- Domain entities no longer own mutable presentation concern fields by default.

---

## Phase 4 — Controller Decomposition (Hint + Scroll)

**Goal**
Shrink controllers into orchestrators and move logic into cohesive modules.

**Why it exists**
Current controllers are large multi-responsibility classes and major coupling hubs.

**Inputs / dependencies**
- Phase 2 and Phase 3 complete.

**Outputs**
- Hint mode decomposition into focused components (input reducer, click/refresh coordinator, renderer adapter).
- Scroll mode decomposition into focused components (selection reducer, scroll executor, discovery coordinator).
- Reduced direct knowledge between controllers and low-level services.
- Detector boundary split: scroll detection contract separated from hint refresh timing policy.
- `ScrollDirection` moved out of `ClickService` into shared domain/input namespace.
- Detector continuation modeled as explicit enum decision type.

**Findings resolved in this phase**
- F01, F02, F08, F11, F12, F14, F15, F20, F22, F23, F24.

**Key touchpoints**
- `clavier/Services/HintModeController.swift`
- `clavier/Services/ScrollModeController.swift`
- `clavier/Services/ClickService.swift`
- `clavier/Services/AccessibilityService.swift`
- `clavier/Services/ScrollableAreaService.swift`
- `clavier/Services/ScrollDetection/DetectorRegistry.swift`
- `clavier/Services/ScrollDetection/AppSpecificDetector.swift`

**Risks**
- Coordination bugs at module seams.
- Temporary adapter duplication during migration.

**Parallelizable within phase**
- Branch 4A: Hint controller decomposition.
- Branch 4B: Scroll controller decomposition.
- Shared reducer/service interfaces must be frozen before both branches diverge.

**Exit criteria**
- Controllers are orchestration-only entry points.
- Core logic moved into testable, domain-cohesive modules.
- Duplicate controller-level infrastructure code removed.

---

## Phase 5 — UI/App Shell Modularization + Dead-Surface Cleanup

**Goal**
Finalize structural cleanup after behavior-critical refactors stabilize.

**Why it exists**
UI/app entry files remain oversized and currently carry utility/dead surface concerns.

**Inputs / dependencies**
- Phase 4 complete (to reduce merge churn).

**Outputs**
- `PreferencesView` split by tab/components/helpers/utilities.
- `clavierApp.swift` split into app entry, settings bridge, app delegate/menu composition.
- `HintOverlayWindow` and `ScrollOverlayWindow` split into focused submodules where needed.
- `ShortcutRecorderView` split (sheet vs key-formatting helpers).
- Dead/unwired APIs removed or intentionally connected.
- Overlay refresh/reuse keyed by stable identity where applicable.
- Remove unused `hintColor` key/default wiring.
- Extract shared color-hex conversion utilities into dedicated module.
- Add focused tests for `HintPlacementEngine` candidate placement/collision/clamping behavior.

**Findings resolved in this phase**
- F09, F10, F13, F16, F17, F18, F19 (remaining split), F25, F26 (explicitly preserved as-is).

**Key touchpoints**
- `clavier/Views/PreferencesView.swift`
- `clavier/clavierApp.swift`
- `clavier/Views/HintOverlayWindow.swift`
- `clavier/Views/ScrollOverlayWindow.swift`
- Any extracted helper modules introduced in prior phases.

**Risks**
- Mostly merge/churn risk; lower runtime risk if done after prior phases.

**Parallelizable within phase**
- Preferences split and app-shell split can run in parallel.
- Dead-surface cleanup can run in parallel once ownership is clear.

**Exit criteria**
- No single UI/app shell file remains an oversized mixed-responsibility container.
- Dead APIs identified in analysis are either removed or intentionally wired.
- Build passes with identical user-visible behavior.
- Dead-surface decision log includes explicit disposition for each F10 API.

---

## Per-file decomposition directives (implementation targets)

These directives operationalize F11–F20 and must be reflected in PR scope.

- `clavier/Services/HintModeController.swift`
  - Target split: `GlobalHotkeyRegistrar`, `KeyboardEventTap`, `HintInputReducer`, `HintRefreshCoordinator`, `HintOverlayRenderer`, thin `HintModeController` orchestrator.

- `clavier/Services/ScrollModeController.swift`
  - Target split: shared input infra adapters, `ScrollSelectionReducer`, `ScrollDiscoveryCoordinator`, `ScrollCommandExecutor`, thin `ScrollModeController` orchestrator.

- `clavier/Services/ScrollableAreaService.swift`
  - Target split: traversal/discovery component, focused-area lookup helpers, shared `ScrollableAreaMerger` policy module.

- `clavier/Services/AccessibilityService.swift`
  - Target split: clickable traversal/discovery, text hydration, and optional observer functionality as separate cohesive modules.

- `clavier/Views/HintOverlayWindow.swift`
  - Target split: hint rendering/diff adapter, search bar subview, highlight rendering helpers.

- `clavier/Views/ScrollOverlayWindow.swift`
  - Target split: area hint rendering, selection highlight rendering, and remove/relocate dead APIs.

- `clavier/Views/PreferencesView.swift`
  - Target split: tab shell + `ClickingTabView`, `ScrollingTabView`, `AppearanceTabView`, `GeneralTabView`, plus extracted helper components (`HelpButton`, `HintPreviewView`) and color utilities.

- `clavier/clavierApp.swift`
  - Target split: app entrypoint file, settings-opener bridge, app delegate/menu/hotkey bootstrap.

- `clavier/Views/ShortcutRecorderView.swift`
  - Target split: recorder UI/sheet and shared key-formatting/keymap utility.

- `clavier/Services/ScrollDetection/Detectors/ChromiumDetector.swift`
  - Target split: detector logic and shared AX frame reading helper (consumed through common AX reader boundary).

---

## Dead-surface disposition checklist (must be explicit)

For each item, implementation must record one of: **removed** / **kept and wired** / **kept with documented owner + call site**.

- `AccessibilityService.startObservingUIChanges`
- `AccessibilityService.stopObservingUIChanges`
- `AccessibilityService.handleUIChangeNotification`
- `ScrollOverlayWindow.updateAllAreas`
- `ScrollOverlayWindow.filterHints`
- `ScrollableAreaService.findFocusedScrollableAreaIndex`
- `ScrollableAreaService.findScrollableAreaUnderCursorIndex`
- `SettingsOpenerView.findSettingsWindow`

---

## Critical serial path vs parallel branches

## Critical serial path
1. **Phase 1** Shared contracts gate
2. **Phase 2B** Scroll pipeline convergence (needed by scroll decomposition)
3. **Phase 3** Domain/session normalization
4. **Phase 4B** Scroll controller decomposition
5. **Phase 5** UI/app modular cleanup

## Parallelizable branches
- **After Phase 1**:
  - Phase 2A Input infra and Phase 2B Scroll pipeline can run in parallel.
- **After Phase 3**:
  - Phase 4A Hint decomposition and Phase 4B Scroll decomposition can run in parallel.
- **After Phase 4**:
  - Preferences split and app-shell split can run in parallel within Phase 5.

---

## Merge strategy (incremental review)

Recommended PR slicing per phase:

- PR 1.x: Contract introduction (additive) + adapters.
- PR 2.x: Infra migration per controller/service; remove old path after parity check.
- PR 3.x: Model/state normalization with compatibility shims.
- PR 4.x: Controller decomposition by mode.
- PR 5.x: UI/app file splits and dead-surface cleanup.

Each PR should include:
- explicit unchanged behavior checklist,
- touched-file scope statement,
- build verification result.
