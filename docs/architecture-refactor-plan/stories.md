# Clavier Architecture Refactor — Implementation Stories

_Last updated: 2026-04-21_

Source used for this pass: `docs/architecture-refactor-plan/phases.md` (per your confirmation).
Sizing mode: **medium PRs per phase sub-area**.

---

## Story index (dependency-aware, with checkboxes)

- [x] **P1-S1 — Typed settings + keymap contract**  
  Depends on: _none_  
  Blocks: P2-S1, P2-S3, P5-S1

- [x] **P1-S2 — Shared AX reader + cast-safety baseline**  
  Depends on: _none_  
  Blocks: P2-S2, P4-S3

- [x] **P1-S3 — Scroll merge policy contract + stable identity primitives**  
  Depends on: _none_  
  Blocks: P2-S2, P3-S1, P3-S2

- [x] **P2-S1 — Shared input infrastructure + hint-mode adoption**  
  Depends on: P1-S1, P1-S2, P1-S3  
  Blocks: P2-S3, P3-S1, P4-S2

- [x] **P2-S2 — Scroll progressive discovery converges on shared merger**  
  Depends on: P1-S2, P1-S3  
  Blocks: P2-S3, P3-S2, P4-S3

- [x] **P2-S3 — Scroll-mode adoption of shared input + command boundary**  
  Depends on: P2-S1, P2-S2  
  Blocks: P3-S2, P4-S1, P4-S3

- [ ] **P3-S1 — Hint domain/presentation split + identity-keyed overlay diff**  
  Depends on: P2-S1, P1-S3  
  Blocks: P4-S1, P4-S2, P5-S2

- [ ] **P3-S2 — Scroll domain/presentation split + explicit session state**  
  Depends on: P2-S3, P1-S3  
  Blocks: P4-S1, P4-S3, P5-S2

- [ ] **P4-S1 — Shared decomposition contracts + detector boundary split**  
  Depends on: P3-S1, P3-S2  
  Blocks: P4-S2, P4-S3, P5-S3

- [ ] **P4-S2 — Hint controller decomposition to thin orchestrator**  
  Depends on: P4-S1, P3-S1  
  Blocks: P5-S1, P5-S2

- [ ] **P4-S3 — Scroll controller decomposition + service decomposition alignment**  
  Depends on: P4-S1, P3-S2, P2-S2  
  Blocks: P5-S1, P5-S2

- [ ] **P5-S1 — Preferences + shortcut recorder modularization**  
  Depends on: P4-S2, P4-S3  
  Blocks: P5-S3

- [ ] **P5-S2 — App shell + overlay modularization**  
  Depends on: P4-S2, P4-S3  
  Blocks: P5-S3

- [ ] **P5-S3 — Dead-surface disposition + HintPlacementEngine tests + parity closeout**  
  Depends on: P5-S1, P5-S2, P4-S1  
  Blocks: _final story_

---

## Stories

### [x] P1-S1 — Typed settings + keymap contract

**Goal**  
Create one typed source of truth for settings keys/defaults/validation and shortcut key mapping.

**Depends on / blocks**  
Depends on: none.  
Blocks: P2-S1, P2-S3, P5-S1.

**Scope / out of scope**
- In scope:
  - Add typed settings schema/access layer for hint/scroll/appearance/general settings.
  - Centralize defaults registration and validation.
  - Extract shared keycode/modifier formatting + mapping utilities used by controllers and `ShortcutRecorderView`.
  - Add adapters so existing call sites can migrate incrementally.
- Out of scope:
  - UI redesign in Preferences.
  - Behavior changes to shortcut semantics or defaults.

**Likely touchpoints**
- `clavier/clavierApp.swift`
- `clavier/Views/PreferencesView.swift`
- `clavier/Views/ShortcutRecorderView.swift`
- `clavier/Services/HintModeController.swift`
- `clavier/Services/ScrollModeController.swift`
- New settings/keymap contract module(s)

**Constraints and decisions to honor**
- `phases.md` → **Non-negotiable implementation rules** (parity, additive refactor first).
- `phases.md` → **Shared-contract gate** (typed settings + key mapping are prerequisites).
- `phases.md` → **Phase 1 outputs/exit criteria** (no duplicated key maps).

**Acceptance criteria**
- All touched settings reads/writes go through typed contract APIs.
- One defaults/validation source exists for touched domains.
- Key formatting/mapping is not duplicated across view/controller code.
- Build passes and shortcut behavior remains unchanged.

**Risks / ambiguity**
- Existing user defaults may contain values outside new validation rules.
- Default drift risk if migration misses any bootstrap path.

---

### [x] P1-S2 — Shared AX reader + cast-safety baseline

**Goal**  
Centralize AX attribute/frame decoding behind a typed boundary and remove force-cast usage in touched AX paths.

**Depends on / blocks**  
Depends on: none.  
Blocks: P2-S2, P4-S3.

**Scope / out of scope**
- In scope:
  - Introduce shared AX reader (`AXFrameReader`-style boundary).
  - Replace duplicated AX frame/attribute decode logic in touched services/detector code.
  - Return structured decode failures as values.
- Out of scope:
  - Full rewrite of AX traversal strategy.

**Likely touchpoints**
- `clavier/Services/AccessibilityService.swift`
- `clavier/Services/ScrollableAreaService.swift`
- `clavier/Services/ScrollDetection/Detectors/ChromiumDetector.swift`
- New AX reader module(s)

**Constraints and decisions to honor**
- `phases.md` → **Non-negotiable rules #4** (no force casts in newly touched AX parsing).
- `phases.md` → **Phase 1 outputs** (shared AX extraction helper).

**Acceptance criteria**
- Touched AX parsing paths use shared reader APIs.
- No force casts remain in touched AX decode code.
- Build passes; hint/scroll discovery behavior is unchanged in manual parity checks.

**Risks / ambiguity**
- Coordinate conversion bugs can surface when decode paths are unified.
- Error-value plumbing may expose hidden assumptions in callers.

---

### [x] P1-S3 — Scroll merge policy contract + stable identity primitives

**Goal**  
Introduce one reusable scroll-area merge policy and stable identity types for discovered entities.

**Depends on / blocks**  
Depends on: none.  
Blocks: P2-S2, P3-S1, P3-S2.

**Scope / out of scope**
- In scope:
  - Add shared `ScrollableAreaMerger` policy contract/module.
  - Define stable identity primitives for discovered UI entities/areas.
  - Wire initial adoption in discovery pipeline where lowest risk.
- Out of scope:
  - Full overlay diff migration (handled in Phase 3).

**Likely touchpoints**
- `clavier/Services/ScrollableAreaService.swift`
- `clavier/Models/UIElement.swift`
- `clavier/Models/ScrollableArea.swift`
- `clavier/Services/ScrollModeController.swift` (contract hookup only)
- New merger/identity module(s)

**Constraints and decisions to honor**
- `phases.md` → **Shared-contract gate** (merge policy + stable identity required before parallelization).
- `phases.md` → **Phase 1 findings mapping** (F03 contract layer, F21 identity primitives).

**Acceptance criteria**
- A single merger implementation exists and is referenced as the canonical policy.
- Stable identity types are introduced and used by touched discovery models.
- Build passes; no behavior changes in area discovery output ordering for unchanged inputs.

**Risks / ambiguity**
- Identity derivation may be unstable if tied to transient AX details.
- Merge policy edge cases can impact progressive discovery later.

---

### [x] P2-S1 — Shared input infrastructure + hint-mode adoption

**Goal**  
Replace hint-mode-specific hotkey/event-tap plumbing with shared input infrastructure.

**Depends on / blocks**  
Depends on: P1-S1, P1-S2, P1-S3.  
Blocks: P2-S3, P3-S1, P4-S2.

**Scope / out of scope**
- In scope:
  - Add shared hotkey registrar abstraction.
  - Add shared keyboard event-tap lifecycle abstraction.
  - Add shared command decode entry for mode-specific adapters.
  - Migrate hint controller to this shared infrastructure.
- Out of scope:
  - Scroll-mode migration (handled in P2-S3).

**Likely touchpoints**
- `clavier/Services/HintModeController.swift`
- Shared input infra module(s)

**Constraints and decisions to honor**
- `phases.md` → **Phase 2 outputs** (shared hotkey + tap + command decoding).
- `phases.md` → behavior parity requirement (ESC/backspace semantics unchanged).

**Acceptance criteria**
- Hint mode uses shared input infra for registration/tap lifecycle.
- Hint behavior parity holds for activation, typing, backspace, ESC, click execution.
- Build passes.

**Risks / ambiguity**
- Event tap threading behavior may regress if callback ownership changes.

---

### [x] P2-S2 — Scroll progressive discovery converges on shared merger

**Goal**  
Remove duplicated scroll dedupe/nesting geometry logic and route progressive updates through the shared merger policy.

**Depends on / blocks**  
Depends on: P1-S2, P1-S3.  
Blocks: P2-S3, P3-S2, P4-S3.

**Scope / out of scope**
- In scope:
  - Replace controller-local merge/dedupe logic with `ScrollableAreaMerger`.
  - Ensure initial and progressive discovery use the same policy contract.
- Out of scope:
  - Scroll-mode input infra migration (P2-S3).

**Likely touchpoints**
- `clavier/Services/ScrollModeController.swift`
- `clavier/Services/ScrollableAreaService.swift`

**Constraints and decisions to honor**
- `phases.md` → **Phase 2 exit criteria** (controller no longer reimplements dedupe/nesting).
- `phases.md` → **Critical serial path** (phase 2B required before scroll decomposition).

**Acceptance criteria**
- One merger policy drives both initial and progressive scroll area results.
- Duplicated controller merge geometry logic is removed from touched paths.
- Manual parity checks show expected area ordering and selection continuity.

**Risks / ambiguity**
- Progressive update ordering may shift subtly.

---

### [x] P2-S3 — Scroll-mode adoption of shared input + command boundary

**Goal**  
Move scroll mode to shared input infra and establish a `ModeController`-style lifecycle/command boundary.

**Depends on / blocks**  
Depends on: P2-S1, P2-S2.  
Blocks: P3-S2, P4-S1, P4-S3.

**Scope / out of scope**
- In scope:
  - Migrate scroll hotkey/tap lifecycle onto shared infrastructure.
  - Add scroll command decoding adapter through shared boundary.
  - Keep existing scroll UX semantics intact.
- Out of scope:
  - Scroll session model normalization (P3-S2).

**Likely touchpoints**
- `clavier/Services/ScrollModeController.swift`
- Shared input infra module(s)

**Constraints and decisions to honor**
- `phases.md` → **Phase 2 outputs** (shared command decoding boundary).
- `phases.md` → **Non-negotiable parity** (numeric/arrow/hjkl/ESC behavior unchanged).

**Acceptance criteria**
- Scroll mode no longer owns bespoke hotkey/tap lifecycle code.
- Scroll commands are decoded via shared entry point with scroll adapter.
- Build passes and command behavior matches current UX.

**Risks / ambiguity**
- Input handling differences may appear around modifier combinations and focus state.

---

### [ ] P3-S1 — Hint domain/presentation split + identity-keyed overlay diff

**Goal**  
Separate discovered hintable entities from presentation state and key overlay reuse by stable entity identity.

**Depends on / blocks**  
Depends on: P2-S1, P1-S3.  
Blocks: P4-S1, P4-S2, P5-S2.

**Scope / out of scope**
- In scope:
  - Split domain snapshot model from hint-assignment/presentation mapping.
  - Introduce explicit hint session state types.
  - Migrate overlay diff cache from hint-token keys to stable identity keys.
- Out of scope:
  - Full hint controller decomposition (P4-S2).

**Likely touchpoints**
- `clavier/Models/UIElement.swift`
- `clavier/Services/HintModeController.swift`
- `clavier/Views/HintOverlayWindow.swift`

**Constraints and decisions to honor**
- `phases.md` → **Phase 3 outputs** (distinct domain vs presentation, explicit states).
- `phases.md` → **F06** (overlay identity correctness).

**Acceptance criteria**
- Domain entity type no longer owns mutable hint presentation by default.
- Overlay reuse/diff is keyed by stable identity.
- Typing/backspace filtering and click behavior remain unchanged.

**Risks / ambiguity**
- Incorrect identity mapping may cause stale or flickering hint views.

---

### [ ] P3-S2 — Scroll domain/presentation split + explicit session state

**Goal**  
Model scroll sessions with explicit state types and separate discovery data from UI/session concerns.

**Depends on / blocks**  
Depends on: P2-S3, P1-S3.  
Blocks: P4-S1, P4-S3, P5-S2.

**Scope / out of scope**
- In scope:
  - Separate discovered scrollable area data from numbered/selected presentation state.
  - Replace sentinel index + multi-flag coupling with explicit session state models.
- Out of scope:
  - Full controller/service decomposition (P4-S3).

**Likely touchpoints**
- `clavier/Models/ScrollableArea.swift`
- `clavier/Services/ScrollModeController.swift`
- `clavier/Views/ScrollOverlayWindow.swift`

**Constraints and decisions to honor**
- `phases.md` → **Phase 3 exit criteria** (explicit state models; no illegal mixed states).
- `phases.md` → **F05/F21** (domain vs presentation separation).

**Acceptance criteria**
- Scroll session state is represented with explicit, typed states.
- Sentinel/multi-flag illegal combinations are eliminated in touched flow.
- Area selection, text-search numbering, and clearing behavior match current UX.

**Risks / ambiguity**
- Edge-case regressions in numbered search and selection transitions.

---

### [ ] P4-S1 — Shared decomposition contracts + detector boundary split

**Goal**  
Freeze shared contracts required by both controller decompositions and decouple detector concerns.

**Depends on / blocks**  
Depends on: P3-S1, P3-S2.  
Blocks: P4-S2, P4-S3, P5-S3.

**Scope / out of scope**
- In scope:
  - Define/freeze reducer/service interfaces used by both decomposed controllers.
  - Split `DetectorRegistry` responsibilities (scroll detector registry vs hint refresh timing policy).
  - Replace bool continuation flags with explicit enum decision type.
  - Move `ScrollDirection` from `ClickService` to shared domain/input namespace.
- Out of scope:
  - Full extraction of hint/scroll controller internals.

**Likely touchpoints**
- `clavier/Services/ScrollDetection/DetectorRegistry.swift`
- `clavier/Services/ScrollDetection/AppSpecificDetector.swift`
- `clavier/Services/ClickService.swift`
- New shared contract/enums modules

**Constraints and decisions to honor**
- `phases.md` → **Phase 4 outputs** (detector boundary split, enum decision, ScrollDirection move).
- `phases.md` → **Parallelizable branch note** (freeze interfaces before 4A/4B divergence).

**Acceptance criteria**
- Detector registry and refresh timing policy are separated contracts.
- Detector continuation is enum-based (no bool continuation flags in touched path).
- `ScrollDirection` lives in neutral namespace and is consumed by relevant services.

**Risks / ambiguity**
- Wide signature churn across services/controllers.

---

### [ ] P4-S2 — Hint controller decomposition to thin orchestrator

**Goal**  
Refactor hint mode into cohesive modules with `HintModeController` as orchestration-only entry point.

**Depends on / blocks**  
Depends on: P4-S1, P3-S1.  
Blocks: P5-S1, P5-S2.

**Scope / out of scope**
- In scope:
  - Extract `HintInputReducer`, `HintRefreshCoordinator`, and overlay renderer adapter.
  - Keep controller focused on wiring lifecycle + dependencies.
  - Preserve behavior with adapter shims during migration; remove legacy path in same PR if safe.
- Out of scope:
  - Scroll decomposition.

**Likely touchpoints**
- `clavier/Services/HintModeController.swift`
- New hint-mode modules (`Reducer`, `RefreshCoordinator`, renderer adapter)
- Possibly `clavier/Services/AccessibilityService.swift` for seam cleanup

**Constraints and decisions to honor**
- `phases.md` → **Per-file decomposition directives** for `HintModeController`.
- `phases.md` → **Non-negotiable rule #3** (additive first, then cleanup).

**Acceptance criteria**
- `HintModeController` is orchestration-only in responsibility.
- Core logic resides in focused, testable modules.
- Behavior parity checklist passes for hint activation, filtering, click, cancel.

**Risks / ambiguity**
- Refresh timing and render lifecycle seams can produce subtle regressions.

---

### [ ] P4-S3 — Scroll controller decomposition + service decomposition alignment

**Goal**  
Refactor scroll mode and supporting services into cohesive modules, leaving `ScrollModeController` orchestration-only.

**Depends on / blocks**  
Depends on: P4-S1, P3-S2, P2-S2.  
Blocks: P5-S1, P5-S2.

**Scope / out of scope**
- In scope:
  - Extract `ScrollSelectionReducer`, `ScrollDiscoveryCoordinator`, `ScrollCommandExecutor`.
  - Align `ScrollableAreaService`/`AccessibilityService`/`ChromiumDetector` splits with new seams.
  - Remove remaining controller-level duplicated infra/merge logic.
- Out of scope:
  - Preferences/app-shell cleanup.

**Likely touchpoints**
- `clavier/Services/ScrollModeController.swift`
- `clavier/Services/ScrollableAreaService.swift`
- `clavier/Services/AccessibilityService.swift`
- `clavier/Services/ScrollDetection/Detectors/ChromiumDetector.swift`

**Constraints and decisions to honor**
- `phases.md` → **Per-file decomposition directives** for scroll/controller/services.
- `phases.md` → **Critical serial path** (2B + 3 before scroll decomposition).

**Acceptance criteria**
- `ScrollModeController` becomes orchestration-only.
- Scroll logic lives in focused modules with explicit boundaries.
- Progressive discovery and scroll command behavior remain parity-equivalent.

**Risks / ambiguity**
- Discovery timing and coordinator boundaries may introduce races.

---

### [ ] P5-S1 — Preferences + shortcut recorder modularization

**Goal**  
Decompose oversized settings UI files and remove known dead setting surface.

**Depends on / blocks**  
Depends on: P4-S2, P4-S3.  
Blocks: P5-S3.

**Scope / out of scope**
- In scope:
  - Split `PreferencesView` into tab shell + per-tab views + helper components.
  - Split `ShortcutRecorderView` into recorder UI vs key-formatting utility.
  - Extract color utilities to dedicated module.
  - Remove unused `hintColor` key/default wiring.
- Out of scope:
  - Functional redesign of settings UX.

**Likely touchpoints**
- `clavier/Views/PreferencesView.swift`
- `clavier/Views/ShortcutRecorderView.swift`
- `clavier/clavierApp.swift` (if default registration cleanup needed)
- New settings UI/util modules

**Constraints and decisions to honor**
- `phases.md` → **Phase 5 outputs** and **F09/F13/F19**.
- Preserve settings semantics while removing dead key.

**Acceptance criteria**
- Preferences and recorder files are decomposed into cohesive modules.
- `hintColor` dead setting surface is removed from active wiring.
- Settings behavior remains unchanged for supported options.

**Risks / ambiguity**
- SwiftUI binding mistakes can cause silent settings regressions.

---

### [ ] P5-S2 — App shell + overlay modularization

**Goal**  
Split app entry/bridge/delegate concerns and modularize overlay windows without behavior changes.

**Depends on / blocks**  
Depends on: P4-S2, P4-S3.  
Blocks: P5-S3.

**Scope / out of scope**
- In scope:
  - Split `clavierApp.swift` into app entrypoint, settings-opener bridge, and app delegate/menu bootstrap concerns.
  - Split `HintOverlayWindow` and `ScrollOverlayWindow` into focused submodules per directive.
- Out of scope:
  - Dead-surface disposition finalization (P5-S3).

**Likely touchpoints**
- `clavier/clavierApp.swift`
- `clavier/Views/HintOverlayWindow.swift`
- `clavier/Views/ScrollOverlayWindow.swift`
- New app shell / overlay helper modules

**Constraints and decisions to honor**
- `phases.md` → **Per-file decomposition directives** for app + overlays.
- `phases.md` → **F26** (preserve `ScreenGeometry` architecture as-is).

**Acceptance criteria**
- App shell responsibilities are separated into smaller cohesive files.
- Overlay responsibilities are split while preserving identity-based update behavior.
- App launch/menu/settings open behavior stays unchanged.

**Risks / ambiguity**
- Window lifecycle and menu bootstrap ordering can regress during extraction.

---

### [ ] P5-S3 — Dead-surface disposition + HintPlacementEngine tests + parity closeout

**Goal**  
Complete cleanup and validation: resolve all dead-surface items explicitly, add missing placement tests, and close refactor parity checks.

**Depends on / blocks**  
Depends on: P5-S1, P5-S2, P4-S1.  
Blocks: final sign-off.

**Scope / out of scope**
- In scope:
  - Apply explicit disposition for each F10 API: **removed** / **kept and wired** / **kept with owner + call site**.
  - Add focused tests for `HintPlacementEngine` placement/collision/clamping behavior.
  - Run final parity/build checks and document results.
- Out of scope:
  - New product features.

**Likely touchpoints**
- `clavier/Services/AccessibilityService.swift`
- `clavier/Views/ScrollOverlayWindow.swift`
- `clavier/Services/ScrollableAreaService.swift`
- `clavier/clavierApp.swift` (`SettingsOpenerView.findSettingsWindow`)
- Hint placement test files under test directory

**Constraints and decisions to honor**
- `phases.md` → **Dead-surface disposition checklist** (must be explicit for each API).
- `phases.md` → **Phase 5 exit criteria** (behavior parity, build passes).

**Acceptance criteria**
- Every API in the dead-surface checklist has a recorded disposition and resulting code state.
- `HintPlacementEngine` focused tests exist and pass.
- Build passes; user-visible behavior parity checklist is complete.

**Risks / ambiguity**
- Removing dead surfaces can accidentally remove latent integration hooks.

---

## Dependency ordering summary

Suggested execution order:
1. P1-S1, P1-S2, P1-S3 (can run in parallel, then converge)
2. P2-S1 and P2-S2 (parallel) → P2-S3
3. P3-S1 and P3-S2 (parallel)
4. P4-S1 → P4-S2 and P4-S3 (parallel)
5. P5-S1 and P5-S2 (parallel) → P5-S3

This ordering preserves the serial/parallel constraints defined in `phases.md` while keeping stories PR-sized and independently reviewable.
