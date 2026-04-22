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
    func walk(
        _ root: AXUIElement,
        pid: pid_t,
        clipBounds: CGRect,
        into pending: inout [PendingElement]
    ) {
        walkNode(
            root,
            pid: pid,
            clickableAncestor: nil,
            clipBounds: clipBounds,
            into: &pending
        )
    }

    /// Collapse the traversal-local wrappers into the stable
    /// `[UIElement]` view consumed by hint mode.  Any element whose
    /// `clickableAncestorHash` is non-nil is dropped — its ancestor is
    /// already in the list.
    static func collect(pending: [PendingElement]) -> [UIElement] {
        pending.compactMap { $0.clickableAncestorHash == nil ? $0.element : nil }
    }

    // MARK: - Recursion

    private func walkNode(
        _ element: AXUIElement,
        pid: pid_t,
        clickableAncestor: (element: AXUIElement, frame: CGRect)?,
        clipBounds: CGRect,
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

        // VISIBILITY CLIPPING: Skip entire subtree if element is off-screen.
        if !elementFrame.intersects(clipBounds) { return }

        // Convert AX coordinates (top-left origin, y down) to AppKit (bottom-left origin, y up).
        let frame = ScreenGeometry.axToAppKit(position: position, size: size)

        // enabled may be AXValueError for non-interactive elements — treated as "not disabled".
        let enabled = valuesArray[4] as? Bool

        let isClickable = clickability.isClickable(role: role, element: element, enabled: enabled)

        // Clickable nodes become the dedup ancestor for their descendants.
        let newClickableAncestor: (element: AXUIElement, frame: CGRect)? =
            isClickable ? (element, frame) : clickableAncestor

        if isClickable {
            recordClickable(
                element: element,
                pid: pid,
                role: role,
                frame: frame,
                elementFrameAX: elementFrame,
                clipBounds: clipBounds,
                clickableAncestor: clickableAncestor,
                into: &pending
            )
        }

        // SMART PRUNING: skip subtrees for roles that never contain clickable children.
        if clickability.canPruneSubtree(role: role) { return }

        guard let children = valuesArray[3] as? [AXUIElement] else { return }

        // Children inherit the tighter clip (intersection with current element).
        let childClipBounds = elementFrame.intersection(clipBounds)

        for child in children {
            walkNode(
                child,
                pid: pid,
                clickableAncestor: newClickableAncestor,
                clipBounds: childClipBounds,
                into: &pending
            )
        }
    }

    private func recordClickable(
        element: AXUIElement,
        pid: pid_t,
        role: String,
        frame: CGRect,
        elementFrameAX: CGRect,
        clipBounds: CGRect,
        clickableAncestor: (element: AXUIElement, frame: CGRect)?,
        into pending: inout [PendingElement]
    ) {
        // Filter out elements too small to be meaningful click targets.
        // The origin check is intentionally omitted: secondary displays can
        // have negative AppKit coordinates (screens left of or below main).
        guard frame.width > 5, frame.height > 5 else { return }

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

        var ancestorHash: Int? = nil
        if let ancestor = clickableAncestor,
           dedupe.framesMatch(frame, ancestor.frame) {
            ancestorHash = Int(CFHash(ancestor.element))
        }

        pending.append(PendingElement(element: uiElement, clickableAncestorHash: ancestorHash))
    }
}
