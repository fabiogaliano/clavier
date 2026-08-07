# Chromium-based app support

This document explains why hints don't work in some Chromium-based apps
out of the box, what clavier does about it, and the limits of the
workaround. It's the reference an agent should consult when a user
reports "clavier doesn't work in app X."

## The two-tier reality

Not all "Chromium apps" are the same. Three families behave differently:

| Family | Examples | AX tree default | clavier handling |
| --- | --- | --- | --- |
| Modern Chromium browsers | Chrome, Arc, Edge, Brave, Helium | Dormant until enhanced UI is requested | Application-root `AXEnhancedUserInterface` + structural readiness polling |
| Electron apps | Slack, Discord, Notion, Linear, Obsidian, 1Password 8, Cursor, Teams | Dormant; needs `AXManualAccessibility` | `ChromiumAccessibilityWaker` |
| CEF apps | Spotify | Dormant; **no runtime wake** | `SpotifyAccessibilityHelper` (instructions) |

The split is determined by which Chromium bridge layer the app links
against. Electron exposes `AXManualAccessibility` as a settable AX
attribute via `electron_application.mm`'s `accessibilityAttributeNames`
override (introduced in [Electron PR
#10305](https://github.com/electron/electron/pull/10305)). CEF does
not. Setting `AXManualAccessibility` on Spotify therefore returns
`.attributeUnsupported` — clavier silently logs this at debug level
and falls back to the Spotify-specific help path.

## Track A — runtime Chromium activation (`ChromiumAccessibilityWaker`)

`AppDelegate` subscribes to `NSWorkspace.didActivateApplicationNotification`
so renderer activation and structural readiness polling begin as soon as a
known Chromium-family app comes to the front. The currently frontmost app is
also handled when clavier launches. A hint activation reuses an in-flight
prewarm instead of restarting the cold-renderer wait from the hotkey press.
Activation is idempotent per pid and caches/tasks are invalidated on termination.

Two application-root strategies are used:

- Electron: write `AXManualAccessibility = true`.
- Standalone Chromium browsers: write `AXEnhancedUserInterface = true`.

Helium 0.15.2.1 / Chromium 151 was measured in two isolated processes. Passive
AX traversal stayed at the native 40-node browser skeleton indefinitely;
`AXManualAccessibility` returned `kAXErrorAttributeUnsupported`. An
application-root `AXEnhancedUserInterface` write changed the readable value
from false to true even though the setter returned `kAXErrorNotImplemented`.
`AXWebArea` appeared 2.08 seconds later in both runs. The implementation
therefore verifies the enhanced write by reading the value back instead of
trusting the setter result alone.

Initial hint discovery does not use clickable-count heuristics. Browser chrome
can expose dozens of valid controls while page content is absent. Instead,
`AccessibilityService.getClickableElementsWhenReady` detects whether discovered
controls belong to web content and polls the focused browser window for the
structural `AXWebArea` root, yielding between probes, for up to three seconds.
When a renderer is cold, native browser-control hints are presented immediately
using three-character tokens. Renderer controls are merged later without
changing any visible token, so the user can act on browser chrome while Helium
finishes publishing the page tree.

### Why application-root `AXEnhancedUserInterface` is scoped to browsers

Vimac issue #78 found window-positioning regressions after writing
`AXEnhancedUserInterface` to an **AXWindow**. Clavier never writes it to a
window; the browser strategy writes only to the application AX element, while
Electron continues using its narrower manual attribute. The allow-list keeps
this private compatibility behavior away from unrelated native apps.

### Adding more apps to the allow-list

Add standalone browsers to `ChromiumAccessibilityWaker.knownBrowserBundleIds`
and Electron apps to `knownElectronBundleIds`. The browser set is shared with
`ChromiumDetector`, so hint activation and scroll detection cannot drift. The
bundle id must match `NSRunningApplication.bundleIdentifier` exactly. To find
it for a specific app:

```bash
osascript -e 'id of app "AppName"'
# or
mdls -name kMDItemCFBundleIdentifier /Applications/AppName.app
```

Do not add unrelated apps speculatively: both attributes are private runtime
compatibility signals and activation can increase the target's renderer cost.

## Track B — Spotify (CEF) — relaunch with launch flag

Spotify uses CEF (Chromium Embedded Framework), not Electron. CEF
does not implement `AXManualAccessibility`, so Track A's wake is a
no-op there: the AX write returns `.attributeUnsupported`. We
prototyped two runtime techniques (role-read on the application
element per [Chromium CL 2680102](https://chromium-review.googlesource.com/c/chromium/src/+/2680102),
and `AXEnhancedUserInterface` writes) and neither populated Spotify's
tree — the empty-tree skeleton (window + nested empty `AXGroup`s + 3
chrome buttons) was unchanged after both attempts.

The only confirmed mechanism that populates Spotify's tree is
launching it with the Chromium switch `--force-renderer-accessibility`
at process start. clavier surfaces this via a help sheet whose
primary action is a one-click relaunch.

### Detection trigger

When the frontmost app is `com.spotify.client` and the discovery walk
returns fewer than 5 clickables (the empty-tree signature),
`HintModeController.activateHintMode` short-circuits to
`SpotifyAccessibilityHelper.presentIfApplicable(...)` instead of
opening hint mode for the 3 traffic-light buttons.

### The help sheet — two options

1. **Quick fix — Relaunch button (universal, primary).**
   `relaunchSpotifyWithFlag()` does:
   1. Resolves `/Applications/Spotify.app` via
      `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)`.
   2. Sends `terminate()` to every running `com.spotify.client` instance.
   3. Polls `NSRunningApplication.isTerminated` every 100 ms for up to
      3 seconds, falling back to `forceTerminate()` for holdouts.
   4. Calls `NSWorkspace.shared.openApplication(at:configuration:)`
      with `OpenConfiguration.arguments = ["--force-renderer-accessibility"]`.

   **Why the terminate-and-wait dance is mandatory:**
   `OpenConfiguration.arguments` only takes effect on a *fresh*
   process launch. If Spotify is already running, `openApplication`
   activates the existing instance and silently drops the flag.
   Skipping the wait races LaunchServices into handing back the
   dying instance instead of spawning a new one.

   Active for the lifetime of that Spotify process — quitting Spotify
   yourself reverts the flag.

2. **Make it automatic — auto-relaunch toggle (zero-click persistence).**
   The sheet directs users to *Preferences → General → Spotify →
   "Automatically relaunch Spotify with the flag on every launch"*.
   When enabled, `SpotifyAccessibilityHelper` observes
   `NSWorkspace.didLaunchApplicationNotification`, probes the AX tree
   ~1.5 s after a Spotify launch, and silently re-runs the same
   terminate-and-wait dance whenever it sees an unflagged launch.
   Cooldown of 10 s prevents the kill+relaunch loop on the new pid.

### Sheet dismissal

Three exits:
- *Close* — dismiss the current sheet but allow it to reappear next
  time clavier detects the empty-tree state.
- *Not now* — same as close.
- *Don't show again* — sets `spotifyAccessibilityHelpEnabled = false`,
  silencing the auto-prompt permanently. The sheet remains reachable
  via `Preferences → General → Spotify → "Show Spotify help now…"`.

There's also an in-memory `dismissedThisSession` flag that suppresses
re-display within a single clavier process lifetime, so the sheet
doesn't re-pop on every hint-trigger after a user has acknowledged
it once.

### Known dead ends (do not re-investigate without new evidence)

These are documented for future agents who consider re-prototyping:

- **`AXManualAccessibility` externally on Spotify** — CEF does not
  implement the attribute; returns `.attributeUnsupported`.
- **Role-read on the application element** — empirically tested,
  did not escalate `kAXModeBasic` → `kAXModeComplete`. Likely cause:
  the wrapper `AXGroup`s are NSAccessibility wrappers from Spotify's
  native shell, not `BrowserAccessibilityCocoa` instances; reads
  never reach Chromium's hook.
- **`AXEnhancedUserInterface` externally on Spotify** — community-
  tested via Vimac and the Spotify dev forum thread; failed.
  Setting it on windows additionally caused window-manager regressions
  ([Vimac issue #78](https://github.com/dexterleng/vimac/issues/78),
  [Mozilla bug 1664992](https://bugzilla.mozilla.org/show_bug.cgi?id=1664992)).
- **CDP `Accessibility.enable`** over a debug port — populates the
  in-DevTools tree only, does not create platform NSAccessibility
  objects.
- **JS injection in the renderer** — DOM-side code cannot escalate
  Chromium's process-level AX mode.
- **`CefBrowserHost::SetAccessibilityState`** — in-process C++ API,
  not callable from outside Spotify's process.

## Settings

User-controllable in `Preferences → General`:

- **`chromiumAccessibilityWakeEnabled`** (default `true`) — toggles
  Track A. When off, neither browser enhanced-UI activation nor Electron
  manual activation is requested. Chromium-family apps may expose only native
  chrome or an empty window shell. Useful for users who want to minimise the
  target apps' CPU/memory footprint.
- **`spotifyAccessibilityHelpEnabled`** (default `true`) — toggles
  Track B's auto-presentation. When off, the help sheet still appears
  via the manual *Show Spotify help now…* button but won't auto-fire
  on empty-tree detection.
- **`spotifyAutoRelaunchEnabled`** (default `false`) — when on,
  clavier observes `NSWorkspace.didLaunchApplicationNotification`,
  probes Spotify's AX tree ~1.5 s after a launch, and silently
  relaunches with the flag if the tree is dormant. Provides
  zero-click "Spotify just works" UX at the cost of ~2 s extra
  startup latency on every Spotify launch. Off by default because
  the trade-off is only worth it for users who use hints in Spotify
  daily; occasional users are better served by the manual button
  on the help sheet.

## Performance impact (in target apps)

Electron's own docs note: *"Rendering accessibility tree can
significantly affect the performance of your app. It should not be
enabled by default."* No primary source publishes quantified numbers.
Empirically: an idle Slack with the tree enabled uses a few percent
more CPU than without; an active Slack (typing, scrolling) sees a
larger delta because every DOM mutation traverses the accessibility
layer too.

There is **no** measurable impact on clavier itself — the wake is a
single AX write per app launch.

## What does *not* work (researched dead ends)

These are documented for future agents who consider re-investigating:

- **`AXEnhancedUserInterface` on an AXWindow** — window-manager regressions.
  Application-root writes for allow-listed standalone browsers are the supported
  path; this warning is specifically about the old window-scoped technique.
- **CDP `Accessibility.enable`** over a debug port — populates the
  in-DevTools tree only, does not create platform NSAccessibility
  objects.
- **JS injection in the renderer** — DOM-side code cannot escalate
  Chromium's process-level AX mode.
- **`CefBrowserHost::SetAccessibilityState`** — in-process C++ API,
  not callable from outside Spotify's process.
- **Setting `AXManualAccessibility` on individual windows** — the
  attribute is observed at the application level only.

## File map

| File | Role |
| --- | --- |
| `clavier/Services/ChromiumAccessibilityWaker.swift` | Track A: browser/Electron registries, application-root activation, read-back verification, per-pid cache |
| `clavier/Services/Hint/SpotifyAccessibilityHelper.swift` | Track B: empty-tree detection, relaunch logic, sheet trigger |
| `clavier/Views/SpotifyHelpSheetWindow.swift` | Track B: SwiftUI help sheet UI (one-click relaunch + auto-relaunch pointer) |
| `clavier/App/AppDelegate.swift` | NSWorkspace activation/termination wiring |
| `clavier/Services/AccessibilityService.swift` | Pre-walk activation + bounded structural `AXWebArea` readiness polling |
| `clavier/Services/HintModeController.swift` | Spotify short-circuit in `activateHintMode` |
| `clavier/Settings/AppSettings.swift` | Setting keys + defaults |
| `clavier/Views/Preferences/GeneralTabView.swift` | UI surface for both toggles + manual help-sheet button |

## Primary references

- [Electron PR #10305](https://github.com/electron/electron/pull/10305) — introduces `AXManualAccessibility`
- [Electron accessibility docs](https://github.com/electron/electron/blob/main/docs/tutorial/accessibility.md)
- [Vimac issue #78](https://github.com/dexterleng/vimac/issues/78) — `AXEnhancedUserInterface` window side effects
- [CefBrowserHost reference (Spotify's CEF v114)](https://cef-builds.spotifycdn.com/docs/114.2/classCefBrowserHost.html) — `--force-renderer-accessibility` semantics
- [VS Code accessibility flow](https://github.com/microsoft/vscode/blob/main/src/vs/workbench/services/accessibility/electron-browser/accessibilityService.ts) — passive listener, no manual wake (illustrates Chromium's on-demand mechanism)
