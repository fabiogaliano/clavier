# clavier

A macOS menu bar application for keyboard-driven UI navigation. Click anywhere on your screen using keyboard shortcuts instead of the mouse.

## Overview

clavier displays alphabetic hints over clickable UI elements, allowing you to interact with any application without reaching for the mouse. Similar to Vimium for browsers, but for the entire macOS desktop.

## Features

### Hint Mode
- **Alphabetic hints** - Overlay hints on all clickable elements in the frontmost app
- **Smart typing** - Type hint characters (e.g., "AJ") to click elements instantly
- **Text search** - Type element names to find and click them
  - Numbered hints (1-9) appear for 2-9 matches - type the number to select
  - Green highlight boxes for 10+ matches
  - Auto-click when exactly one match remains
- **Two-stage ESC** - First ESC clears search text, second ESC exits hint mode
- **Continuous click mode** - Stay active for multiple clicks without reactivating
  - Manual refresh trigger (default: type "rr") to update hints on demand
  - Auto-deactivation timer after inactivity (configurable)
- **Customizable appearance** - Glass effect UI with full color control and transparency
- **Horizontal offset** - Position hints left/right of elements to avoid covering text

### Scroll Mode
- **Keyboard scrolling** - Use vim-style keys (hjkl) or arrow keys
- **Smart area detection** - Progressive discovery of scrollable regions
  - Auto-selects focused element's scrollable parent
  - App-specific optimizations (e.g., Chromium DevTools)
  - Numbered hints for area selection
- **Configurable speeds** - Normal and dash speed (Shift for faster)
- **Flexible controls** - Arrow keys can select areas or scroll directly
- **Auto-deactivation** - Optional timer exits scroll mode after inactivity

### Customization
- **Global hotkeys** - Configurable activation shortcuts for both modes
- **Hint characters** - Customize available characters (default: "asdfhjkl")
- **Full color control** - Background, border, text, and highlight colors with live preview
- **Adjustable sizing** - Hint size (10-20pt) and positioning
- **Behavior tuning** - Arrow key mode, auto-deactivation timers, scroll speeds

## Requirements

- macOS 14.0+
- Xcode 15+ (for building)
- Accessibility permissions

## Building

```bash
# Clone the repository
git clone <repository-url>
cd clavier

# Build from command line
xcodebuild -project clavier.xcodeproj -scheme clavier -configuration Debug build

# Or open in Xcode
open clavier.xcodeproj
# Press Cmd+R to build and run
```

## Setup

1. Launch clavier
2. Grant Accessibility permissions when prompted (System Settings > Privacy & Security > Accessibility)
3. The app appears in the menu bar

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
| Select scroll area | 1-9 or arrow keys (if arrow mode = "select") |
| Scroll | hjkl or arrow keys (if arrow mode = "scroll") |
| Dash speed (faster) | Shift + hjkl or Shift + arrows |
| Exit scroll mode | ESC |

### Hint Mode Workflow

**Alphabetic Hints:**
1. Press activation shortcut (Cmd + Shift + Space)
2. Hints appear over clickable elements
3. Type the hint characters (e.g., "A", "AJ")
4. Element is clicked automatically
5. Mode deactivates (unless continuous mode is enabled)

**Text Search:**
1. Press activation shortcut
2. Start typing element text (e.g., "Submit", "Login")
3. Search bar appears showing match count
4. When behavior differs based on matches:
   - **1 match**: Auto-clicks immediately (green border)
   - **2-9 matches**: Shows numbered hints (1-9) - type number to select
   - **10+ matches**: Shows green highlight boxes around all matches
   - **No matches**: Shows red border, type more or press ESC to clear
5. Press ESC once to clear search, ESC again to exit

**Continuous Mode:**
- Hints refresh after each click
- Type manual refresh trigger ("rr" by default) to force refresh
- Auto-deactivates after inactivity (if enabled)

### Scroll Mode Workflow

1. Press activation shortcut
2. Numbered hints appear over scrollable areas
3. Select area by typing number or using arrow keys
4. Scroll with hjkl keys (or configured keys)
5. Hold Shift for faster scrolling
6. Press ESC to exit

## Configuration

Access preferences via the menu bar icon > Preferences, or use the standard Cmd+, shortcut.

### Tabs

**Clicking** - Hint Mode Configuration
- Activation hotkey (default: Cmd + Shift + Space)
- Hint characters (default: "asdfhjkl")
- Text search:
  - Enable/disable text search
  - Minimum characters before searching (default: 2)
- Manual refresh trigger (default: "rr")
- Continuous click mode:
  - Enable/disable continuous mode
  - Auto-deactivation after inactivity
  - Deactivation delay (default: 5 seconds)

**Scrolling** - Scroll Mode Configuration
- Activation hotkey (default: Option + E)
- Arrow key behavior: "select" areas or "scroll" directly
- Show/hide scroll area numbers
- Scroll keys (4 characters for left/down/up/right, default: "hjkl")
- Enable/disable scroll commands
- Scroll speed multiplier (1-10, default: 5)
- Dash speed multiplier for Shift (1-10, default: 9)
- Auto-deactivation:
  - Enable/disable auto-deactivation
  - Deactivation delay (default: 5 seconds)

**Appearance** - Visual Customization
- Live preview of current settings
- Color pickers:
  - Background tint (default: blue #3B82F6)
  - Border color (default: blue #3B82F6)
  - Text color (default: white #FFFFFF)
  - Highlight color for matched text (default: yellow #FFFF00)
- Opacity sliders:
  - Background opacity (0-100%, default: 30%)
  - Border opacity (0-100%, default: 60%)
- Hint size (10-20pt, default: 12)
- Horizontal offset (-200 to +200px, default: -25px)
- Reset to defaults button

**General** - System Settings
- Accessibility permissions check
- About section

## Architecture

### Core Technologies
- **SwiftUI** - Settings interface with live preview
- **AppKit** - Overlay windows, menu bar status item
- **Accessibility API** - UI element discovery and observation
- **Carbon Event Manager** - Global hotkey registration
- **CGEvent** - Event tap for keyboard interception and click/scroll simulation
- **NSVisualEffectView** - Glass blur effects for hint overlays

### Key Components

**Services (@MainActor singletons):**
- `HintModeController` - Orchestrates hint mode lifecycle, manages event tap
- `ScrollModeController` - Manages scroll mode, area selection, and scroll commands
- `AccessibilityService` - Queries AX tree for clickable elements
- `ScrollableAreaService` - Discovers scrollable containers with progressive callbacks
- `ClickService` - Posts CGEvent mouse and scroll wheel events

**Models:**
- `UIElement` - Wrapper for AXUIElement with screen frame, role, hint, and searchable text
- `ScrollableArea` - Scrollable region with frame and numbered hint

**Views:**
- `HintOverlayWindow` - Borderless window at `.screenSaver` level displaying hints
- `ScrollOverlayWindow` - Overlay showing numbered scroll areas
- `PreferencesView` - SwiftUI settings with four tabs
- `ShortcutRecorderView` - Live keyboard shortcut capture

### Performance Optimizations
- **Batch IPC calls** - Fetches role, position, size, children in single Accessibility API call
- **Visibility clipping** - Skips elements outside screen bounds
- **Smart pruning** - Avoids traversing non-clickable subtrees (StaticText, Image, etc.)
- **Async text loading** - Loads searchable text attributes in background
- **Debounced UI updates** - 50ms debounce on layout change notifications
- **Progressive discovery** - Scroll areas found incrementally with dynamic UI updates
- **Focus-based fast path** - Quickly finds scrollable parent of focused element
- **App-specific detectors** - Optimized scroll detection (e.g., Chromium DevTools)

### Threading Model
- **Main thread (@MainActor)** - All controllers, services, UI updates
- **CFRunLoop thread** - Event tap for keyboard interception
  - Uses `nonisolated(unsafe)` static variables for thread-safe state sharing
  - Dispatches UI updates to main queue
- **Background threads** - Async scroll area discovery

### Coordinate Systems
- **Accessibility API**: Bottom-left origin (Quartz coordinates)
- **UI positioning**: Top-left origin (Y-axis flipped for display)
- **CGEvent clicks**: Bottom-left origin (Y-axis flipped back for posting events)

## License

MIT License
