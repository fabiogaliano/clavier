//
//  AXTextHydrator.swift
//  clavier
//
//  Main-actor hydration of `UIElement.textAttributes` from the AX API.
//
//  Why main actor: Apple DTS guidance and community experience (see
//  claudedocs/api-research.md) say all `AXUIElement` functions must be
//  called from the main thread.  This hydrator therefore performs its reads
//  on `MainActor` — the `@MainActor` annotation is the entire point of the
//  type, not an incidental attribute.
//
//  Why a dedicated type: the old `AccessibilityService.loadTextAttributes`
//  sat on a service that also did traversal.  Pulling hydration into its
//  own name makes the threading contract visible at the call site:
//  `AXTextHydrator.hydrate(...)` reads as "main-actor AX reads", whereas
//  "service.loadTextAttributes" read as "probably async, probably safe".
//
//  Why synchronous: the caller (`HintModeController`) already hops through
//  `Task { @MainActor in ... }` before invoking this API so the overlay can
//  paint first.  The hydrator itself stays synchronous — moving the reads
//  off-main would be a correctness regression.
//

import Foundation
import ApplicationServices

@MainActor
enum AXTextHydrator {

    /// Populate `textAttributes` for any elements that still have `nil`
    /// attributes.  Already-hydrated entries are left untouched so repeat
    /// calls (e.g. on continuous-click refresh) don't re-issue AX reads.
    static func hydrate(_ elements: inout [UIElement]) {
        for i in 0..<elements.count {
            guard elements[i].textAttributes == nil else { continue }
            elements[i].textAttributes = read(elements[i].axElement)
        }
    }

    /// Read the four AX text attributes for a single element.  Returns a
    /// value with all-nil fields if the element exposes none of them.
    static func read(_ axElement: AXUIElement) -> ElementTextAttributes {
        ElementTextAttributes(
            title: axString(axElement, kAXTitleAttribute as CFString),
            label: axString(axElement, "AXLabel" as CFString),
            value: axString(axElement, kAXValueAttribute as CFString),
            description: axString(axElement, kAXDescriptionAttribute as CFString)
        )
    }

    private static func axString(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(element, attribute, &ref)
        return ref as? String
    }
}
