# API research notes — typed settings boundary cleanup

## @AppStorage + RawRepresentable enums

Per Apple's SwiftUI `@AppStorage` documentation, a property wrapper initializer
exists for `RawRepresentable` values whose raw value is `String` or `Int`:

- `@AppStorage(_ key: String, store: UserDefaults? = nil) var value: Value`
  where `Value: RawRepresentable, Value.RawValue == String` (and the `Int` twin).

Source: https://developer.apple.com/documentation/swiftui/appstorage

This means we can replace raw `String` storage for `scrollArrowMode` with a
typed enum without changing the on-disk representation:

```swift
enum ScrollArrowMode: String { case select, scroll }

@AppStorage(AppSettings.Keys.scrollArrowMode)
private var scrollArrowMode: ScrollArrowMode = .select
```

### Caveats that affected design choices

1. **String parsing on read:** `@AppStorage` silently falls back to the
   declared default if the stored value cannot be parsed into the enum's
   raw value. That's acceptable for `scrollArrowMode` (only two values).
   For free-form strings (`scrollKeys`, `hintCharacters`,
   `manualRefreshTrigger`) an enum is not appropriate — we validate them
   through a parse-on-read boundary in `AppSettings` instead.

2. **No `didSet` on `@AppStorage`:** There is no storage-layer hook for
   validating writes coming from a `TextField`. We keep lightweight
   `onChange` sanitisation in the view only for interactive text fields,
   but delegate the actual sanitisation logic to pure helpers in
   `AppSettings` so the view no longer holds any domain rules.

3. **Persistence compatibility:** All new typed representations keep the
   existing raw shape on disk (String for `scrollArrowMode`, String for
   `scrollKeys`, etc.), so no migration is required.

## UserDefaults validation patterns for macOS Swift apps

- Treat UserDefaults as *untrusted input*: even defaults that were valid
  yesterday may be invalid after a version change or a user edit of the
  plist.  Parse on read.
- Register defaults once at launch via `UserDefaults.register(defaults:)`
  — already done in `AppSettings.registerDefaults()`.
- Prefer a single typed boundary (`AppSettings.xxx` computed property)
  over sprinkling `UserDefaults.standard.string(forKey:)` across the code
  base.  The reducers and controllers in this app should see parsed
  domain values, not raw strings.

## Accessibility API threading (UIElement hydration cleanup)

### Apple's guidance

Apple DTS has stated publicly that **all Accessibility functions are only
safe to call from an application's main thread**.  This covers
`AXUIElementCopyAttributeValue`, `AXUIElementCopyMultipleAttributeValues`,
`AXUIElementPerformAction`, and the full `AXUIElement.h` surface.

Sources:
- [AXUIElementCopyAttributeValue reference](https://developer.apple.com/documentation/applicationservices/1462085-axuielementcopyattributevalue)
- [Apple Developer Forums: "Thread safety of AXUIElement.h functions"](https://developer.apple.com/forums/thread/94878)

The docs themselves are silent on threading; the main-thread rule is
enforced through DTS guidance and field experience.  Treating AX as
main-thread-only is the safe default.

### Consequences for this codebase

- `AccessibilityService.getClickableElements()` is already `@MainActor`
  and must stay that way.
- `loadTextAttributes(for:)` performs four `AXUIElementCopyAttributeValue`
  calls per element.  It **must** run on the main actor.  Moving it to a
  detached background `Task` would be a correctness regression.
- The existing implementation runs hydration inside `Task { @MainActor in
  ... }` — i.e. it re-hops to the main actor but does NOT actually run
  off-main.  The only benefit of the `Task` wrapper is scheduling the
  work at the tail of the current run loop turn so the overlay can paint
  first.  That design intent should be reflected in naming and comments
  rather than hidden behind a generic "async" pattern.

### Decision

- Keep text-attribute hydration on `@MainActor`.
- Rename the hydration path so the threading model is visible in the
  code (e.g. `MainActorTextHydrator.hydrate(...)` or a similarly
  suggestive name).  Document the reason inline.
- If blocking becomes a problem in the future, the correct mitigation is
  cooperative yielding via `await Task.yield()` between per-element
  reads, not moving off the main actor.

## AccessibilityService decomposition (P?-S?, current session)

### Batched AX reads — error sentinel semantics

`AXUIElementCopyMultipleAttributeValues(element, attrs, options, &values)` has
a per-attribute error model that matters for the walker refactor:

- With `options = 0` (the flag we pass — an empty `AXCopyMultipleAttributeOptions`
  option set), the overall function still returns `.success` even when some
  of the requested attributes are unsupported on the element. The mis-
  matched slots in the returned array are filled with either a `CFNull`
  or an `AXValueRef` of type `kAXValueAXErrorType` carrying the per-
  attribute error.
- With `options = kAXCopyMultipleAttributeOptionStopOnError`, the function
  returns immediately on the first missing attribute — we do NOT use this
  option, because non-interactive elements legitimately lack
  `kAXEnabledAttribute`.

Sources:
- [AXUIElementCopyMultipleAttributeValues — Apple reference](https://developer.apple.com/documentation/applicationservices/1462025-axuielementcopymultipleattribute)
- [AXUIElement.h header comments mirror (cdelouya/champ)](https://github.com/cdelouya/champ/blob/master/sdk/MacOSX10.9.sdk/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/Versions/A/Headers/AXUIElement.h)

Consequences the walker must preserve:

1. `valuesArray[i] as? Bool` / `as? [AXUIElement]` on an `AXValueError`
   slot returns Swift `nil`. The existing code treats both of
   "missing" and "present but wrong type" identically, which is the
   intended behavior for `enabled` (non-interactive elements) and
   `children` (leaf elements).
2. For `position` / `size` the existing `AXReader.decodeCGPoint` /
   `decodeCGSize` check `CFGetTypeID(ref) == AXValueGetTypeID()`. A
   `kAXValueAXErrorType` sentinel IS an `AXValue`, so the type-ID check
   passes; `AXValueGetValue(_, .cgPoint, &out)` silently returns false
   for the wrong AXValue subtype, leaving the inout at `.zero`. The
   walker then filters these via the `frame.width > 5 && frame.height > 5`
   guard. This is a latent-but-harmless behavior and must not change
   in this refactor (fixing it is out of scope and would alter what
   gets discovered).
3. We never request `options = kAXCopyMultipleAttributeOptionStopOnError`.
   The walker extraction must keep the `[]` empty option set to preserve
   "continue on missing attribute" semantics.

### AXUIElementCopyActionNames

- Returns an empty array (not an `AXError`) for elements with no actions.
- `.success` with an empty list is the common case for static containers.
- `hasClickAction` therefore only has to guard the overall return code
  and the cast; it does not need a separate "no actions" branch.

Source: [AXUIElement.h — AXUIElementCopyActionNames header](https://github.com/cdelouya/champ/blob/master/sdk/MacOSX10.9.sdk/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/Versions/A/Headers/AXUIElement.h)

### Threading (re-confirmation)

All `AXUIElement.h` functions — including
`AXUIElementCopyMultipleAttributeValues`, `AXUIElementPerformAction`, and
`AXUIElementCopyActionNames` — are documented by Apple DTS as
main-thread-only.

Source: [Apple Developer Forums thread 94878 — "Thread safety of AXUIElement.h functions"](https://developer.apple.com/forums/thread/94878)

Consequence: the new `ClickableElementWalker` and `ClickabilityPolicy`
types that call these APIs must be `@MainActor`. No off-main hops.

### Xcode 16 synchronized root groups

`clavier.xcodeproj/project.pbxproj` uses `PBXFileSystemSynchronizedRootGroup`
for both `clavier` and `clavierTests`. New `.swift` files dropped under
those folder trees are automatically picked up by the target on the next
build — no `pbxproj` edit is required, and exceptions only need to be
recorded when a file must be excluded.

Sources:
- [Pedro Piñera — "How synchronized groups work at the .pbxproj level"](https://pepicrft.me/blog/how-synchronized-groups-work-at-the-pbxproj-level/)
- [EvanBacon/xcode issue #17 — PBXFileSystemSynchronizedRootGroup](https://github.com/EvanBacon/xcode/issues/17)

## Files touched (summary)

- `clavier/Settings/AppSettings.swift` — introduce `ScrollArrowMode`,
  `ScrollKeymap`, `HintCharacters` typed views; add sanitisers; typed
  computed properties.
- `clavier/Services/HintInputReducer.swift` — accept typed context values
  (`HintCharacters`, still-typed refresh trigger) transparently.
- `clavier/Services/Scroll/ScrollSelectionReducer.swift` — `arrowMode`
  becomes `ScrollArrowMode`; scroll keys carried as `ScrollKeymap`.
- `clavier/Views/Preferences/*TabView.swift` — call the sanitiser
  helpers instead of inlining regex-style filters; use typed
  `@AppStorage` for the arrow-mode picker.
- `clavier/Services/HintModeController.swift` +
  `clavier/Services/ScrollModeController.swift` — construct the typed
  contexts from `AppSettings`.
