# Chromium-based app support

This document explains why hints don't work in some Chromium-based apps
out of the box, what clavier does about it, and the limits of the
workaround. It's the reference an agent should consult when a user
reports "clavier doesn't work in app X."

## The two-tier reality

Not all "Chromium apps" are the same. Three families behave differently:

| Family | Examples | AX tree default | clavier handling |
| --- | --- | --- | --- |
| Modern Chromium browsers | Chrome, Arc, Edge, Brave | On-demand; wakes on first AX query | Just works |
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

## Track A — Electron apps (`ChromiumAccessibilityWaker`)

Subscribes to `NSWorkspace.didActivateApplicationNotification` and
sets `AXManualAccessibility = kCFBooleanTrue` on the application AX
element when a known Electron app comes to the front. Idempotent per
pid; the woken-pid set is invalidated on
`didTerminateApplicationNotification`.

`AccessibilityService.getClickableElements` also calls
`wakeIfNeeded(...)` before walking, which catches:

- The first-frontmost case (clavier launched while a Chromium app was
  already focused — `didActivate` doesn't fire for that app).
- The cold-start race (user hits hint hotkey within ~150 ms of
  switching to a fresh Chromium process).

When the wake is fresh, the service sleeps 150 ms before walking and
runs an empty-tree retry once — together they cover Chromium's tree
population latency without making the hint overlay feel laggy.

### Why we only set `AXManualAccessibility`, not also `AXEnhancedUserInterface`

`AXEnhancedUserInterface` is the older attribute Chromium also
responds to, but setting it from outside causes window-management
regressions (Magnet/Rectangle behaviour breaks because macOS treats
the process as VoiceOver). Vimac removed it for that reason — see
[Vimac issue #78](https://github.com/dexterleng/vimac/issues/78). We
follow the same lead: `AXManualAccessibility` only.

### Adding more apps to the allow-list

Edit `ChromiumAccessibilityWaker.knownChromiumBundleIds`. The bundle
id must match `NSRunningApplication.bundleIdentifier` exactly. To find
it for a specific app:

```bash
osascript -e 'id of app "AppName"'
# or
mdls -name kMDItemCFBundleIdentifier /Applications/AppName.app
```

Adding a non-Electron app is harmless — the AX write fails with
`.attributeUnsupported` and the wake is silently skipped on that pid.

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

### The help sheet — three options, ordered by friction

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

2. **Permanent fix — Spicetify (only when detected).**
   If `~/.config/spicetify/config-xpui.ini` exists, the sheet shows:

   ```bash
   spicetify config spotify_launch_flags --force-renderer-accessibility && spicetify apply
   ```

   This adds the flag to `spotify_launch_flags` in `config-xpui.ini`,
   making it stick across every Spicetify-managed Spotify launch.
   Detection is a simple `FileManager.default.fileExists(atPath:)`
   check.

3. **Manual Terminal launch (always shown when Spicetify isn't detected).**

   ```bash
   /Applications/Spotify.app/Contents/MacOS/Spotify --force-renderer-accessibility
   ```

   Equivalent to option 1 done by hand. Useful for users with custom
   shell setups, aliases, or who just prefer terminal launches.

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

### Why we don't run Spicetify commands for the user

- `spicetify apply` regenerates files; if the user has unsaved
  customisations or a custom `xpui` build, it could disrupt them.
- The `spicetify` binary location varies (Homebrew, manual install,
  custom shells) — shelling out invites PATH/version mismatches.

The relaunch path is safe to automate (it uses public NSWorkspace
APIs and only restarts a single, known process). The Spicetify path
is shown + clipboard, never executed.

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
  Track A. When off, no app gets `AXManualAccessibility` written;
  Slack/Discord/etc. revert to "no hints visible" behaviour. Useful
  for users who don't use clavier in Chromium apps and want to
  minimise their CPU/memory footprint.
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

- **`AXEnhancedUserInterface` externally** — window-manager regressions.
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
| `clavier/Services/ChromiumAccessibilityWaker.swift` | Track A: allow-list + AX write + per-pid cache |
| `clavier/Services/Hint/SpotifyAccessibilityHelper.swift` | Track B: empty-tree detection, relaunch logic, sheet trigger |
| `clavier/Views/SpotifyHelpSheetWindow.swift` | Track B: SwiftUI help sheet UI (relaunch + Spicetify + manual paths) |
| `clavier/App/AppDelegate.swift` | NSWorkspace activation/termination wiring |
| `clavier/Services/AccessibilityService.swift` | Pre-walk wake + empty-tree retry |
| `clavier/Services/HintModeController.swift` | Spotify short-circuit in `activateHintMode` |
| `clavier/Settings/AppSettings.swift` | Setting keys + defaults |
| `clavier/Views/Preferences/GeneralTabView.swift` | UI surface for both toggles + manual help-sheet button |

## Primary references

- [Electron PR #10305](https://github.com/electron/electron/pull/10305) — introduces `AXManualAccessibility`
- [Electron accessibility docs](https://github.com/electron/electron/blob/main/docs/tutorial/accessibility.md)
- [Vimac issue #78](https://github.com/dexterleng/vimac/issues/78) — `AXEnhancedUserInterface` window side effects
- [Spicetify CLI flags](https://spicetify.app/docs/development/spotify-cli-flags) — `spotify_launch_flags` config
- [CefBrowserHost reference (Spotify's CEF v114)](https://cef-builds.spotifycdn.com/docs/114.2/classCefBrowserHost.html) — `--force-renderer-accessibility` semantics
- [VS Code accessibility flow](https://github.com/microsoft/vscode/blob/main/src/vs/workbench/services/accessibility/electron-browser/accessibilityService.ts) — passive listener, no manual wake (illustrates Chromium's on-demand mechanism)
