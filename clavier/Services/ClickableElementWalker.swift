//
//  ClickableElementWalker.swift
//  clavier
//
//  Recursive AX-tree walker that discovers clickable elements for a single
//  root (typically a window).  Owns the batched IPC read, the visibility
//  clip propagation, the subtree-pruning decision, and the ancestor
//  propagation that feeds dedup.
//
//  Extracted from `AccessibilityService` so the service can stay a thin
//  facade that resolves "which app, which windows" and hands each root to
//  the walker.
//
//  Threading: every call path touches `AXUIElementCopyMultipleAttributeValues`,
//  which Apple DTS requires be called from the main thread (see
//  `claudedocs/api-research.md`).  This type is therefore `@MainActor`.
//

import Foundation
import AppKit
import ApplicationServices

/// Traversal-local wrapper pairing a discovered element with the
/// `CFHash`-based tombstone used to collapse ancestor-frame duplicates
/// after the walk completes.  Intentionally file-scoped to this module —
/// callers that need the collapsed `[UIElement]` call
/// `ClickableElementWalker.collect(pending:)`.
struct PendingElement {
    var element: UIElement
    /// Non-nil when this element's frame matched its nearest clickable
    /// ancestor's frame within `AncestorDedupePolicy.frameTolerance`.  The
    /// value is `Int(CFHash(ancestorAXElement))` — opaque to callers; only
    /// nil-ness is consulted during collection.
    var clickableAncestorHash: Int?
}

@MainActor
struct ClickableElementWalker {

    let clickability: ClickabilityPolicy
    let dedupe: AncestorDedupePolicy

    init(
        clickability: ClickabilityPolicy = .default,
        dedupe: AncestorDedupePolicy = .default
    ) {
        self.clickability = clickability
        self.dedupe = dedupe
    }

    /// Walk the AX tree rooted at `root`, appending each discovered
    /// clickable element (wrapped in `PendingElement`) to `pending`.
    ///
    /// `clipBounds` is in AX coordinates (top-left origin, y down).  The
    /// walker intersects it with the current element's frame before
    /// recursing — children inherit the tighter clip so partially off-
    /// screen subtrees are trimmed early.
    ///
    /// `clickableAncestor` is nil at the entry point; the walker sets it
    /// whenever it decides the current node is clickable, so descendants
    /// can be dedup-marked against it.
    ///
    /// `recorder` is nil on the production path (zero overhead) and
    /// non-nil during debug mode to capture per-node observation events.
    func walk(
        _ root: AXUIElement,
        pid: pid_t,
        clipBounds: CGRect,
        into pending: inout [PendingElement],
        recorder: HintDiscoveryRecorder? = nil
    ) {
        walkNode(
            root,
            pid: pid,
            clickableAncestor: nil,
            clipBounds: clipBounds,
            depth: 0,
            inWebArea: false,
            parentRecorderId: nil,
            recorder: recorder,
            into: &pending
        )
    }

    /// Collapse the traversal-local wrappers into the stable
    /// `[UIElement]` view consumed by hint mode.  Any element whose
    /// `clickableAncestorHash` is non-nil is dropped — its ancestor is
    /// already in the list.
    ///
    /// The same real AX node can be reached more than once through
    /// different structural parents (for example a web table exposing both
    /// row and column children).  The overlay already keys reuse by
    /// `stableID`, so duplicates must be collapsed here before hint
    /// assignment or a single on-screen element can pick up multiple tokens.
    static func collect(pending: [PendingElement]) -> [UIElement] {
        var seen = Set<ElementIdentity>()

        return pending.compactMap { candidate in
            guard candidate.clickableAncestorHash == nil else { return nil }

            let identity = candidate.element.stableID
            guard seen.insert(identity).inserted else { return nil }

            return candidate.element
        }
    }

    // MARK: - Recursion

    private func walkNode(
        _ element: AXUIElement,
        pid: pid_t,
        clickableAncestor: (element: AXUIElement, frame: CGRect, recorderId: Int?)?,
        clipBounds: CGRect,
        depth: Int,
        inWebArea: Bool,
        parentRecorderId: Int?,
        recorder: HintDiscoveryRecorder?,
        into pending: inout [PendingElement]
    ) {
        // BATCH FETCH: Get role, position, size, children, enabled in ONE IPC call.
        // Missing attributes arrive as AXValueError sentinels; Swift `as?` yields
        // nil for those slots without failing the overall call — see
        // claudedocs/api-research.md for the documented semantics we rely on.
        let attributes = [
            kAXRoleAttribute as CFString,
            kAXPositionAttribute as CFString,
            kAXSizeAttribute as CFString,
            kAXChildrenAttribute as CFString,
            kAXEnabledAttribute as CFString
        ] as CFArray

        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, attributes, [], &values) == .success,
              let valuesArray = values as? [Any],
              valuesArray.count == 5 else {
            return
        }

        guard let role = valuesArray[0] as? String else { return }
        guard let position = AXReader.decodeCGPoint(from: valuesArray[1]) else { return }
        guard let size = AXReader.decodeCGSize(from: valuesArray[2]) else { return }

        let elementFrame = CGRect(origin: position, size: size)

        // enabled may be AXValueError for non-interactive elements — treated as "not disabled".
        let enabled = valuesArray[4] as? Bool

        // Convert AX coordinates (top-left origin, y down) to AppKit (bottom-left origin, y up).
        let frame = ScreenGeometry.axToAppKit(position: position, size: size)

        // VISIBILITY CLIPPING: Skip entire subtree if element is off-screen.
        if !elementFrame.intersects(clipBounds) {
            recorder?.record(
                parentId: parentRecorderId,
                depth: depth,
                role: role,
                frameAX: elementFrame,
                frameAppKit: frame,
                enabled: enabled,
                decision: .roleNotInteractive,
                outcome: .clippedOffscreen,
                childrenVisited: false
            )
            return
        }

        // Web-area context is propagated in from the parent so AXWebArea
        // *itself* classifies without the narrowing rules (its role is
        // never AXStaticText).  Descendants see inWebArea == true.
        let webContext = ClickabilityPolicy.WebContext(
            inWebArea: inWebArea,
            hasClickableAncestor: clickableAncestor != nil
        )
        let decision = clickability.evaluate(
            role: role,
            element: element,
            enabled: enabled,
            webContext: webContext
        )
        let isClickable = decision.isClickable

        // Determine the node's final outcome (independent of pruning decision).
        var outcome: HintDiscoveryEvent.Outcome
        var ancestorRecorderId: Int? = nil
        if isClickable {
            if frame.width <= 5 || frame.height <= 5 {
                outcome = .rejectedTooSmall
            } else if let ancestor = clickableAncestor,
                      dedupe.framesMatch(frame, ancestor.frame) {
                outcome = .acceptedDeduped
                ancestorRecorderId = ancestor.recorderId
            } else {
                outcome = .accepted
            }
        } else {
            outcome = .rejectedNotClickable
        }

        let willPrune = clickability.canPruneSubtree(role: role)

        // Hydrate AX text attributes ONLY when a recorder is present.
        // Production hint mode hydrates lazily (after the overlay paints)
        // via `AXTextHydrator`; paying for it inline during traversal
        // would regress hint-mode latency.  Debug mode doesn't care about
        // the extra IPC since it runs on-demand and is never on the
        // hot path.
        let textAttrs = recorder.map { _ in ClickableElementWalker.readDebugText(element) }

        // Action names are also debug-only.  Diagnoses ambiguous
        // static-text decisions — in particular whether a surviving
        // pressable candidate carried `AXPress` or only `AXShowMenu`.
        // `flatMap` collapses the outer "recorder present?" optional into
        // the inner "action read succeeded?" optional.
        let actionNames = recorder.flatMap { _ in ClickableElementWalker.readActionNames(element) }

        let thisRecorderId = recorder?.record(
            parentId: parentRecorderId,
            depth: depth,
            role: role,
            roleDescription: textAttrs?.roleDescription,
            title: textAttrs?.title,
            label: textAttrs?.label,
            value: textAttrs?.value,
            description: textAttrs?.description,
            frameAX: elementFrame,
            frameAppKit: frame,
            enabled: enabled,
            actions: actionNames,
            decision: decision,
            outcome: outcome,
            ancestorId: ancestorRecorderId,
            childrenVisited: !willPrune
        )

        // Production behaviour: record accepted/deduped clickables into
        // `pending`.  Deduped entries carry a non-nil `clickableAncestorHash`
        // so `collect(pending:)` drops them.
        if isClickable && outcome != .rejectedTooSmall {
            recordClickable(
                element: element,
                pid: pid,
                role: role,
                frame: frame,
                elementFrameAX: elementFrame,
                clipBounds: clipBounds,
                outcome: outcome,
                clickableAncestor: clickableAncestor,
                into: &pending
            )
        }

        // Clickable accepted nodes (not deduped) become the dedup ancestor
        // for their descendants.  We keep the original clickableAncestor
        // for deduped children so they continue comparing against the
        // already-survived outer ancestor.
        let newClickableAncestor: (element: AXUIElement, frame: CGRect, recorderId: Int?)?
        if outcome == .accepted {
            newClickableAncestor = (element, frame, thisRecorderId)
        } else {
            newClickableAncestor = clickableAncestor
        }

        // SMART PRUNING: skip subtrees for roles that never contain clickable children.
        if willPrune { return }

        guard let children = valuesArray[3] as? [AXUIElement] else { return }

        // Children inherit the tighter clip (intersection with current element).
        let childClipBounds = elementFrame.intersection(clipBounds)

        // Children inherit web-area context: once we cross into an
        // AXWebArea every descendant sees inWebArea == true.
        let childInWebArea = inWebArea || role == "AXWebArea"

        for child in children {
            walkNode(
                child,
                pid: pid,
                clickableAncestor: newClickableAncestor,
                clipBounds: childClipBounds,
                depth: depth + 1,
                inWebArea: childInWebArea,
                parentRecorderId: thisRecorderId,
                recorder: recorder,
                into: &pending
            )
        }
    }

    /// Debug-only: fetch the five text-shaped AX attributes in a single
    /// batched call so the snapshot / overlay can identify elements by
    /// their human-readable label instead of by opaque id.
    ///
    /// Not on the production path — only invoked when a
    /// `HintDiscoveryRecorder` is attached.
    private static func readDebugText(_ element: AXUIElement) -> DebugTextAttributes {
        let attributes = [
            kAXRoleDescriptionAttribute as CFString,
            kAXTitleAttribute as CFString,
            "AXLabel" as CFString,
            kAXValueAttribute as CFString,
            kAXDescriptionAttribute as CFString,
        ] as CFArray

        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, attributes, [], &values) == .success,
              let arr = values as? [Any], arr.count == 5 else {
            return DebugTextAttributes()
        }

        func nonEmptyString(_ raw: Any) -> String? {
            guard let s = raw as? String, !s.isEmpty else { return nil }
            return s
        }

        return DebugTextAttributes(
            roleDescription: nonEmptyString(arr[0]),
            title: nonEmptyString(arr[1]),
            label: nonEmptyString(arr[2]),
            value: nonEmptyString(arr[3]),
            description: nonEmptyString(arr[4])
        )
    }

    private struct DebugTextAttributes {
        var roleDescription: String? = nil
        var title: String? = nil
        var label: String? = nil
        var value: String? = nil
        var description: String? = nil
    }

    /// Debug-only: fetch the AX action names the element advertises.
    /// Returns an empty array when the element supports no actions, or
    /// nil when the AX call itself failed (disambiguates "knows it has
    /// none" from "couldn't ask").
    private static func readActionNames(_ element: AXUIElement) -> [String]? {
        var actions: CFArray?
        guard AXUIElementCopyActionNames(element, &actions) == .success,
              let names = actions as? [String] else {
            return nil
        }
        return names
    }

    private func recordClickable(
        element: AXUIElement,
        pid: pid_t,
        role: String,
        frame: CGRect,
        elementFrameAX: CGRect,
        clipBounds: CGRect,
        outcome: HintDiscoveryEvent.Outcome,
        clickableAncestor: (element: AXUIElement, frame: CGRect, recorderId: Int?)?,
        into pending: inout [PendingElement]
    ) {
        // Anchor the hint to the visibly-clipped region so partially-
        // occluded elements don't get hints placed off-screen or behind
        // containers.  Matches Vimium's visible-rect anchoring.
        let visibleAX = elementFrameAX.intersection(clipBounds)
        let visibleFrame = ScreenGeometry.axToAppKit(
            position: visibleAX.origin,
            size: visibleAX.size
        )

        let uiElement = UIElement(
            stableID: ElementIdentity(pid: pid, role: role, frame: frame),
            axElement: element,
            frame: frame,
            visibleFrame: visibleFrame,
            role: role
        )

        let ancestorHash: Int?
        if outcome == .acceptedDeduped, let ancestor = clickableAncestor {
            ancestorHash = Int(CFHash(ancestor.element))
        } else {
            ancestorHash = nil
        }

        pending.append(PendingElement(element: uiElement, clickableAncestorHash: ancestorHash))
    }
}
