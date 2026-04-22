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
