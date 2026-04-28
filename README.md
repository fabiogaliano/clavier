<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/icon-dark.png?v=2">
    <source media="(prefers-color-scheme: light)" srcset="assets/icon-light.png?v=2">
    <img alt="clavier app icon" src="assets/icon-light.png?v=2" width="160">
  </picture>
</p>

# clavier

Navigate any macOS app without touching the mouse.

Press a shortcut, type a hint or search by word — clavier clicks for you.  
Free, open source, and opinionated about how it works. Alternative to Homerow, Shortcat, Wooshy, and Mouseless.

## Features

### Hint Mode
- **Hint codes**: Letter codes over every element; type one to click instantly
- **Search by name**: Type any word; one match auto-clicks, several are numbered, press one to select
- **Two-stage ESC**: first press clears search, second exits
- **Continuous mode**: stay in hint mode across multiple clicks; hints refresh automatically

### Scroll Mode *(in alpha)*

- **Keyboard scrolling**: hjkl or arrow keys; Shift for faster
- **Smart area detection**: auto-selects the scrollable region under focus; numbered hints to pick another
- **Auto-deactivation**: optional timer exits after inactivity

### App compatibility

- **Electron apps**: works with Slack, Discord, Notion, and others out of the box
- **Spotify**: one-click relaunch to enable accessibility; auto-relaunch option for every launch

> Apps using fully custom rendering without Accessibility API support (e.g. Zed) won't expose elements to hint.

### Customization

- **Customizable**: hotkeys, hint alphabet, colors, and sizes

## Requirements

- macOS 14.0+
- Xcode 15+ (for building from source)
- Accessibility permissions (prompted on first launch)

## Building

```bash
# Clone the repository
git clone https://github.com/fabiogaliano/clavier
cd clavier

# Build from command line
xcodebuild -project clavier.xcodeproj -scheme clavier -configuration Debug build

# Or open in Xcode
open clavier.xcodeproj
# Press Cmd+R to build and run
```

## Setup

1. Launch clavier (it lives in the menu bar)
2. Grant Accessibility permissions when prompted (System Settings > Privacy & Security > Accessibility)

## Usage

### Default Shortcuts

| Action | Shortcut |
|--------|----------|
| **Hint Mode** | |
| Activate Hint Mode | Cmd + Shift + Space |
| Clear search text | ESC (first press) or Option |
| Exit hint mode | ESC (second press) |
| Select numbered match | 1-9 (when text search shows 2-9 matches) |
| Click first match | Enter |
| Right-click first match | Ctrl + Enter |
| Manual refresh | Type "rr" (configurable) |
| **Scroll Mode** | |
| Activate Scroll Mode | Option + E |
| Select scroll area | 1-9 or arrow keys |
| Scroll | hjkl |
| Dash speed (faster) | Shift + hjkl or Shift + arrows |
| Exit scroll mode | ESC |


## Configuration

Open via menu bar > Preferences or Cmd+,.

- **Clicking**: activation hotkey, hint alphabet, text search, continuous mode
- **Scrolling**: activation hotkey, scroll keys, speeds, arrow key behavior
- **Appearance**: colors, opacity, hint size and offset
- **General**: accessibility permissions, Electron and Spotify settings

## Architecture

Two explicit state machines — `HintSession` and `ScrollSession` — each driven by a pure reducer: (session + input) → (next session + side effects). Controllers own the lifecycle; services handle side effects.

**Notable constraints:**

- **Threading**: The keyboard event tap runs on a CFRunLoop thread. All AX calls and UI mutations are confined to `@MainActor`. Shared state uses `nonisolated(unsafe)` static scalars dispatched back to main.
- **Coordinate systems**: AX API uses bottom-left origin (Quartz). Overlay positioning flips to top-left (AppKit). Synthesized clicks flip back. `ScreenGeometry` owns both transforms.
- **App compatibility**: Electron apps get their dormant AX tree woken via `AXManualAccessibility`. CEF apps (Spotify) can't be woken at runtime — detected and surfaced as a one-click relaunch instead.

## Roadmap

- Configurable right-click shortcut (currently hardcoded to Ctrl+Enter)

## License

MIT License
