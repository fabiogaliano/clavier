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

## Track B — Spotify (CEF) — TODO

Spotify uses CEF (Chromium Embedded Framework), not Electron. CEF
does not implement `AXManualAccessibility`, so Track A's wake is a
no-op there: the AX write returns `.attributeUnsupported`. Empirically
the only confirmed mechanism that populates Spotify's tree is
launching it with the Chromium switch `--force-renderer-accessibility`
at process start.

Untested runtime techniques that could plausibly wake CEF without a
relaunch:

- **Read `kAXRoleAttribute` on the application element first.**
  [Chromium CL 2680102](https://chromium-review.googlesource.com/c/chromium/src/+/2680102)
  (Feb 2021) makes any role read on a Chromium AX element escalate
  `kAXModeBasic` → `kAXModeComplete`. Whether Spotify's CEF fork
  carries this patch is unverified.
- **Set `AXEnhancedUserInterface = true` on the application element.**
  [Vimac issue #78](https://github.com/dexterleng/vimac/issues/78)
  removed this attribute when set on *windows* due to window-manager
  regressions; the app-level path is unexplored in any public source.
- **Walk a step deeper proactively** so multiple role reads hit
  Chromium's `OnPropertiesUsedInWebContent` callback in sequence.

Until we prototype and validate these, Spotify is a known limitation.
The full chain of dead ends already eliminated — `AXManualAccessibility`
externally, `AXEnhancedUserInterface` on windows, CDP `Accessibility.enable`
over a debug port, JS injection in the renderer, `CefBrowserHost::SetAccessibilityState` —
is captured in the [Homerow research thread on issue #31](https://github.com/nchudleigh/homerow/issues/31).

## Settings

User-controllable in `Preferences → General`:

- **`chromiumAccessibilityWakeEnabled`** (default `true`) — toggles
  Track A. When off, no app gets `AXManualAccessibility` written;
  Slack/Discord/etc. revert to "no hints visible" behaviour. Useful
  for users who don't use clavier in Chromium apps and want to
  minimise their CPU/memory footprint.

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
| `clavier/Services/ChromiumAccessibilityWaker.swift` | Allow-list + AX write + per-pid cache |
| `clavier/App/AppDelegate.swift` | NSWorkspace activation/termination wiring |
| `clavier/Services/AccessibilityService.swift` | Pre-walk wake + empty-tree retry |
| `clavier/Settings/AppSettings.swift` | Setting key + default |
| `clavier/Views/Preferences/GeneralTabView.swift` | UI surface for the toggle |

## Primary references

- [Electron PR #10305](https://github.com/electron/electron/pull/10305) — introduces `AXManualAccessibility`
- [Electron accessibility docs](https://github.com/electron/electron/blob/main/docs/tutorial/accessibility.md)
- [Vimac issue #78](https://github.com/dexterleng/vimac/issues/78) — `AXEnhancedUserInterface` window side effects
- [Spicetify CLI flags](https://spicetify.app/docs/development/spotify-cli-flags) — `spotify_launch_flags` config
- [CefBrowserHost reference (Spotify's CEF v114)](https://cef-builds.spotifycdn.com/docs/114.2/classCefBrowserHost.html) — `--force-renderer-accessibility` semantics
- [VS Code accessibility flow](https://github.com/microsoft/vscode/blob/main/src/vs/workbench/services/accessibility/electron-browser/accessibilityService.ts) — passive listener, no manual wake (illustrates Chromium's on-demand mechanism)
