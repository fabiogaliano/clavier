# Hint-Discovery Debugging

A live debug mode for understanding **why each element did or did not get a hint**
in any app — especially browsers, where the AX tree is deep and noisy.

This file is the single source of truth pointed at any AI coding agent asked
to help diagnose hint-discovery behavior. It is deliberately self-contained:
after reading it, an agent should be able to (a) locate the snapshot, (b)
interpret every field, (c) correlate a user's visual observation with a node
record, and (d) propose a targeted fix in the right source file.

---

## For AI coding agents — read this first

When the user says anything like *"debug why X"*, *"check the latest snapshot"*,
*"why isn't this clicked"*, *"help me fix Chrome hints"*, or drops a screenshot
of a colored numbered overlay, follow this protocol:

### Step 1 — load the snapshot

```
Read: debug-snapshots/latest.json
```

This file is overwritten on every debug run. It always exists if the user has
triggered debug mode at least once. If it's missing, ask the user to hit
**⌘⇧⌥Space** in the target app first.

The path is stable relative to the repo root. You do **not** need the user to
paste a path, drop the JSON inline, or tell you where anything lives.

### Step 2 — read the user's observation

The user points at nodes by their `id` number (drawn in the top-left corner of
each rectangle) **or** by an element's name / label — hydrated AX text lives on
every record, so identification by meaning works across debug runs even though
ids reshuffle every pass:

- *"Node 47 is red but it's the Bookmarks button — should be hinted"*  → false negative
- *"The Reload button is red — fix it"*                                → grep `title`/`roleDescription`
- *"The green 112 is just a div, shouldn't have a hint"*               → false positive
- *"I see 5 stacked yellows on the refresh button"*                    → dedup too tight
- *"The sidebar has no rectangles at all"*                             → traversal pruned early

When given a textual label, grep the JSON by `title` / `label` /
`roleDescription` first (there will typically be 1–3 matches), then report
the matching record(s). When given an id, jump straight to that record.
Report `role`, `roleDescription`, `title`, `decision`, `outcome`, `parentId`,
`ancestorId`, `childrenVisited`, and `frameAppKit` before proposing changes.

### Step 3 — diagnose using the decision/outcome split

`decision` and `outcome` are independent. `decision` is the `ClickabilityPolicy`
verdict (role/enabled/static-text rules). `outcome` is what the walker actually
did, which additionally considers dedup and min-size.

A node with `decision: "interactiveRole"` can still have
`outcome: "rejectedTooSmall"` — that means clickability policy is fine but the
5-pt geometry filter caught it. Fix lives in the walker, not the policy.

A node with `decision: "roleNotInteractive"` and `outcome: "rejectedNotClickable"`
means the policy doesn't recognize the role. If the user says that element
**should** be clickable, the fix is in `ClickabilityPolicy` — usually either
adding a role to `interactiveRoles` or extending `evaluate` to inspect
`AXSubrole`, `AXActionNames`, or `AXRoleDescription` for that role.

### Step 4 — map the fix to a file

| Symptom                                        | Likely fix site                                               |
| ---------------------------------------------- | ------------------------------------------------------------- |
| Role never gets a hint but should              | `ClickabilityPolicy.interactiveRoles`                          |
| `AXGroup` / `AXGenericElement` should be clickable | extend `ClickabilityPolicy.evaluate` (add subrole/action check) |
| Clickable element dropped as too-small         | `ClickableElementWalker.recordClickable` (5-pt filter)         |
| Stacked duplicate hints                        | `AncestorDedupePolicy.frameTolerance` or add a dedup case       |
| Whole subtree missing                          | `ClickabilityPolicy.skipSubtreeRoles` (remove an entry)         |
| Off-screen culling wrong                       | `ClickableElementWalker.walkNode` clip-bounds guard            |
| Coordinates misaligned                         | `ScreenGeometry.axToAppKit` / `toWindowLocal`                  |

Always read the relevant file before suggesting a change. Do not guess the
current state of the policy.

### Step 5 — propose a minimal change

Keep changes surgical. Add one role, one subrole check, one action lookup —
not a redesign. After proposing the change, offer to re-run the user through
the debug overlay to confirm the specific node flipped color as expected.

### Useful `jq` recipes the agent can run directly

```bash
# Everything that was clickable by role but dropped by dedup:
jq '.nodes[] | select(.outcome == "acceptedDeduped")' debug-snapshots/latest.json

# How many of each role made it to accepted:
jq -r '.nodes[] | select(.outcome == "accepted") | .role' debug-snapshots/latest.json | sort | uniq -c

# All AXGroup nodes that were rejected (prime browser false-negative class):
jq '.nodes[] | select(.role == "AXGroup" and .outcome == "rejectedNotClickable")' debug-snapshots/latest.json

# Look up a single node by id (the usual "user said node 47 is red"):
jq '.nodes[] | select(.id == 47)' debug-snapshots/latest.json

# Find a node by user-supplied label (reshuffle-safe across runs):
jq '.nodes[] | select(.title == "Reload this page" or .roleDescription == "Reload this page")' debug-snapshots/latest.json

# Fuzzy text search across title/label/value/description/roleDescription:
jq --arg q "reload" '.nodes[] | select(
  ([.title, .label, .value, .description, .roleDescription] | map(ascii_downcase // "") | map(contains($q)) | any)
)' debug-snapshots/latest.json

# All descendants of a given parent (walk down from an id):
jq --argjson p 47 '.nodes[] | select(.parentId == $p)' debug-snapshots/latest.json

# Node's full ancestor chain (walk up via parentId):
jq --argjson n 47 '
  [ .nodes as $all
  | $n as $start
  | until(. == null; ($all[] | select(.id == .)) .parentId)
  ]' debug-snapshots/latest.json

# Role histogram by outcome:
jq -r '.nodes[] | "\(.outcome)\t\(.role)"' debug-snapshots/latest.json | sort | uniq -c | sort -rn | head -30

# Summary section only (fast overview before drilling in):
jq '.summary' debug-snapshots/latest.json
```

---

## TL;DR (human quick-start)

1. Activate the debug overlay: **⌘⇧⌥Space** (or menu bar → *Debug Hints*).
2. The screen fills with colored numbered rectangles — one per visited AX node.
3. A JSON snapshot is written to `debug-snapshots/latest.json` inside the repo
   (with a timestamped archive sibling). `debug-snapshots/` is `.gitignore`d.
4. Press **ESC** (or the same hotkey again) to dismiss.
5. To share with Claude: screenshot the overlay and say *"check the latest
   snapshot"* — Claude reads `debug-snapshots/latest.json` directly and knows
   the schema from this file.

---

## What the overlay shows

Every AX element the walker *visits* is drawn with a color-coded 1-pt border
and a small numbered label in its top-left corner. The number is the node's
`id` in the JSON snapshot, so you can point at "the red 47 near the URL bar"
and the agent looks up the full record by id.

| Color       | Outcome                 | Meaning                                                                 |
| ----------- | ----------------------- | ----------------------------------------------------------------------- |
| 🟢 green    | `accepted`              | Got a hint. Clickable, big enough, not deduped.                         |
| 🟡 yellow   | `acceptedDeduped`       | Was clickable but its frame matched a clickable ancestor within 10 pt.  |
| 🟠 orange   | `rejectedTooSmall`      | Clickable, but visible frame < 5 pt in width or height.                 |
| 🔴 red      | `rejectedNotClickable`  | Failed `ClickabilityPolicy` (role not interactive, disabled, etc.).     |
| ⚫ gray     | `clippedOffscreen`      | Walker reached the node but its frame didn't intersect visible bounds.  |
| ✂︎ (count)  | pruned subtree          | Node's children were *not* visited (role is in `skipSubtreeRoles`).     |

The banner at the top of the screen shows running totals and the snapshot
path.

> Pruning is orthogonal to outcome. A node can be `accepted` *and* pruned
> (children not visited). Pruning only affects whether the walker descended,
> not whether this element itself got a hint.

---

## How to trigger debug mode

Three equivalent paths:

- **Global hotkey** — `⌘⇧⌥Space` (defaults live in
  `AppSettings.Defaults.hintDebugShortcut*`).
- **Menu bar** — click the keyboard icon → *Debug Hints*.
- **Programmatic** — `HintModeController.toggleDebugHintMode()`.

Normal hint mode is torn down automatically when debug mode activates — the
two overlays are mutually exclusive so ESC and the event tap don't collide.

---

## The JSON snapshot

Written to `<repo>/debug-snapshots/snapshot-<ISO-8601>.json` **and** copied to
`<repo>/debug-snapshots/latest.json` (overwrites each run). The timestamped
path is also placed on the clipboard and shown in the overlay banner if you
want to reference a specific historical run. The directory is `.gitignore`d.

### Schema

```jsonc
{
  "schema": "clavier.hint-debug.v1",
  "timestamp": "2026-04-22T11:30:05Z",
  "app": {
    "pid": 8124,
    "bundleId": "com.google.Chrome",
    "localizedName": "Google Chrome"
  },
  "summary": {
    "visited": 842,
    "accepted": 37,
    "deduped": 8,
    "rejectedTooSmall": 12,
    "rejectedNotClickable": 781,
    "clipped": 4,
    "prunedSubtrees": 54
  },
  "nodes": [
    {
      "id": 47,
      "parentId": 46,
      "depth": 11,
      "role": "AXGroup",
      "roleDescription": "button",
      "title": "Reload this page",
      "label": null,
      "value": null,
      "description": null,
      "enabled": true,
      "decision": "roleNotInteractive",
      "outcome": "rejectedNotClickable",
      "ancestorId": null,
      "childrenVisited": true,
      "frameAppKit": { "x": 312, "y": 980, "w": 48, "h": 24 },
      "frameAX":     { "x": 312, "y": 120, "w": 48, "h": 24 }
    }
    // … one record per visited node
  ]
}
```

### Field reference

- **`decision`** (verdict from `ClickabilityPolicy.evaluate`, role-based):
    - `interactiveRole` — role matched `ClickabilityPolicy.interactiveRoles`.
    - `staticTextPressable` — `AXStaticText` with `AXPress` / `AXShowMenu`.
    - `disabled` — `AXEnabled == false`.
    - `staticTextNoAction` — `AXStaticText` without a press action.
    - `roleNotInteractive` — role not in the interactive set (most rejections in browsers).

- **`outcome`** (what the walker actually did, considers geometry + dedup):
    - `accepted`, `acceptedDeduped`, `rejectedTooSmall`,
      `rejectedNotClickable`, `clippedOffscreen`.

- **`parentId`** — recursion parent in the walker. Always set except on the root.

- **`ancestorId`** — nearest *clickable* ancestor whose frame matched within
  `AncestorDedupePolicy.frameTolerance` (default 10 pt). Only set when
  `outcome == acceptedDeduped`.

- **`childrenVisited`** — `false` means the walker stopped here. Cause is
  either `skipSubtreeRoles` (pruned) or `clippedOffscreen`.

- **`frameAX` vs `frameAppKit`** — same rectangle in two coordinate systems.
  AX is top-left origin (y down), AppKit is bottom-left (y up). The overlay
  uses `frameAppKit`; the AX coordinates are there for cross-referencing
  with Accessibility Inspector.

- **`roleDescription`, `title`, `label`, `value`, `description`** — hydrated
  AX text attributes. Key for identifying elements by meaning instead of id:
  *"the node with title 'Reload this page'"* works across debug runs, while
  *"node 47"* does not (ids are DFS-order and reshuffle every pass).
  `roleDescription` is especially useful in browsers where `role` is
  generic (`AXGroup`) but the role description carries the semantic meaning
  (`"button"`, `"link"`, `"text field"`). All fields are null when the
  element exposes no such attribute; empty strings are normalized to null.

### Diagnostic patterns

- **False negative** (should be hinted, isn't): look for `rejectedNotClickable`
  + `roleNotInteractive`. In browsers these are almost always `AXGroup` with
  a meaningful subrole — fix usually extends `ClickabilityPolicy.evaluate`
  with an `AXSubrole` or `AXActionNames` check.
- **False positive** (shouldn't be hinted, is): `outcome == "accepted"` on
  roles like `AXCell`, `AXStaticText`, or `AXLink` on large non-interactive
  containers. Fix is usually narrowing the policy — `AXCell` for example
  matches all table cells, which include many non-clickable ones.
- **Stacked hints**: filter for `acceptedDeduped`. If most of the stack is
  *not* deduped, bump `frameTolerance`. If there are many deduped nodes that
  still feel stacked, the dedup check only compares against nearest clickable
  ancestor — a transitive dedup may be needed.
- **Missing region**: grep for a known frame range. If nodes aren't in the
  file at all, the walker never reached there — trace upward for a pruned
  `AXImage` / `AXStaticText` / `AXScrollBar` (anything in `skipSubtreeRoles`)
  that blocked recursion.

---

## Workflow (human-facing)

1. Reproduce the issue in any app (Chrome, Safari, Finder, etc.).
2. Hit **⌘⇧⌥Space** while the target window is frontmost.
3. Screenshot the overlay.
4. Drop the screenshot into the chat. Point at node id numbers and say what
   you expected. The agent reads `debug-snapshots/latest.json` automatically.
5. Iterate: the agent proposes a one-file patch, you rebuild, re-trigger
   debug mode, and confirm the color on the target node flipped.

---

## How it works under the hood

The debug path re-uses the production discovery pipeline verbatim — same
walker, same policies, same dedup — and only adds an **observation hook**.

```
HintModeController.toggleDebugHintMode
        │
        ▼
AccessibilityService.getClickableElements(recorder:)
        │
        ▼
ClickableElementWalker.walk(..., recorder:)
        │  per node:
        │     1. batch-fetch role/position/size/children/enabled
        │     2. ClickabilityPolicy.evaluate(...)  → Decision
        │     3. frame / ancestor / min-size checks → Outcome
        │     4. recorder?.record(...)     ← only difference vs production
        │     5. possibly recurse into children
        ▼
HintDiscoveryRecorder.events   ──► HintDebugSnapshot.write   (JSON to disk)
                               ──► HintDebugOverlayWindow    (visual overlay)
```

Design constraints to preserve when modifying:

- **Zero production cost.** `recorder: HintDiscoveryRecorder? = nil` is the
  default on every hook. Production code passes nil; the recorder branches
  compile to no-ops.
- **Observation-only.** The walker makes the same accept/reject/prune
  decisions whether the recorder is present or not. Bugs you see in debug
  mode are real bugs in hint mode.
- **Two separate overlays, two separate hotkeys, two separate event taps.**
  Hint mode's overlay is keystroke-driven and tied to the event tap on
  slot 0. Debug mode's overlay is static, dismissed by ESC via the event
  tap on slot 2.

---

## File map

| File                                                   | Role                                           |
| ------------------------------------------------------ | ---------------------------------------------- |
| `clavier/Services/Hint/HintDiscoveryTracer.swift`      | `HintDiscoveryEvent` + `HintDiscoveryRecorder` |
| `clavier/Services/Hint/HintDebugSnapshot.swift`        | JSON serialization + clipboard + `latest.json` |
| `clavier/Views/HintDebugOverlayWindow.swift`           | Colored numbered overlay + banner              |
| `clavier/Services/ClickableElementWalker.swift`        | Recursive walker (calls tracer per node)       |
| `clavier/Services/ClickabilityPolicy.swift`            | `Decision` enum + `evaluate(...)`              |
| `clavier/Services/AncestorDedupePolicy.swift`          | Frame-match tolerance for dedup                |
| `clavier/Services/AccessibilityService.swift`          | Accepts optional recorder parameter            |
| `clavier/Services/HintModeController.swift`            | `toggleDebugHintMode()` + separate hotkey      |
| `clavier/Input/KeyboardEventTap.swift`                 | Slot 2 owned by the debug-mode ESC tap         |
| `clavier/App/AppDelegate.swift`                        | *Debug Hints* menu item                        |
| `clavier/Settings/AppSettings.swift`                   | `hintDebugShortcut*` keys + defaults           |

---

## Companion tool: Accessibility Inspector

For single-element questions ("what does the AX tree *actually* say about
*this* control?"), Apple's built-in **Accessibility Inspector**
(`/Applications/Utilities/Accessibility Inspector.app`) is faster than the
snapshot. Hover any element and it shows the live `AXRole`, `AXSubrole`,
`AXEnabled`, `AXActionNames`, and full attribute dump.

The two tools are complementary:
- **Accessibility Inspector** → ground truth for one control.
- **Hint debug snapshot** → what clavier saw and decided across the whole tree.

When they disagree, clavier has a bug — and the snapshot tells you exactly
which branch to fix.
