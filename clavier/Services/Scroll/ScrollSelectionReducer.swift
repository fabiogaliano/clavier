//
//  ScrollSelectionReducer.swift
//  clavier
//
//  Pure state-transition function for scroll mode input.
//
//  Takes the current `ScrollSession` and a decoded `ScrollInputCommand`,
//  returns the next session state plus a list of side effects the controller
//  must execute.  No I/O, no UserDefaults reads, no timer scheduling.
//
//  Settings required at transition time are snapshotted once at activation
//  into `ScrollInputContext` so the reducer stays testable without UserDefaults.
//

import Foundation

// MARK: - Side effects

/// Side effects produced by `ScrollSelectionReducer.reduce`.
///
/// The controller switches over each element in the returned array and
/// executes the corresponding operation.  Conforms to `ReducerSideEffect`
/// from P4-S1.
enum ScrollSideEffect: ReducerSideEffect {
    /// Scroll in the given direction at the given speed.
    case performScroll(direction: ScrollDirection, speed: Double)
    /// Deactivate scroll mode entirely.
    case deactivate
    /// Select the area at this index (nil clears selection).
    case selectArea(at: Int?)
    /// Update the visible number badge on an area that was renumbered.
    case updateNumber(identity: AreaIdentity, newNumber: String)
    /// Restart the inactivity deactivation countdown.
    case resetDeactivationTimer
    /// Clear the selection highlight without changing area list.
    case clearSelection
}

// MARK: - Input context

/// Caller-supplied settings snapshot for the active scroll session.
///
/// All fields come from UserDefaults and are only safe to read on MainActor,
/// so the controller snapshots them at activation and passes this value to
/// every `reduce` call.
struct ScrollInputContext {
    let scrollKeys: ScrollKeymap
    let arrowMode: ScrollArrowMode
    let scrollSpeed: Double
    let dashSpeed: Double
    let autoDeactivation: Bool
    let deactivationDelay: Double
}

// MARK: - Reducer

/// Stateless reducer mapping `(ScrollSession, ScrollInputCommand) → (ScrollSession, [ScrollSideEffect])`.
///
/// "Stateless" means this enum has no stored state — next state is derived
/// entirely from inputs.  The controller stores and threads the session value.
enum ScrollSelectionReducer {

    // MARK: Public entry point

    /// Compute the next session state and effects for the given command.
    ///
    /// - Parameters:
    ///   - session:  Current scroll session (owned by `ScrollModeController`).
    ///   - command:  Decoded keyboard command (from `ScrollInputDecoder`).
    ///   - context:  Settings snapshot captured at activation.
    /// - Returns:    Next session state and list of effects to execute.
    @MainActor
    static func reduce(
        session: ScrollSession,
        command: ScrollInputCommand,
        context: ScrollInputContext
    ) -> (ScrollSession, [ScrollSideEffect]) {
        guard session.isActive else { return (session, []) }

        switch command {
        case .escape:
            return (.inactive, [.deactivate])

        case .backspace:
            return handleBackspace(session: session)

        case .digit(let n):
            return handleDigit(n, session: session)

        case .arrowKey(let direction, let isShift):
            return handleArrowKey(direction, isShift: isShift, session: session, context: context)

        case .scrollKey(let direction, let isShift):
            return handleScrollKey(direction, isShift: isShift, session: session, context: context)

        case .consume:
            return (session, [])
        }
    }

    // MARK: - Command handlers

    private static func handleBackspace(
        session: ScrollSession
    ) -> (ScrollSession, [ScrollSideEffect]) {
        guard case .active(let areas, _, _) = session else { return (session, []) }
        let next = ScrollSession.active(areas: areas, selected: nil, pendingInput: "")
        return (next, [.clearSelection, .resetDeactivationTimer])
    }

    private static func handleDigit(
        _ number: Int,
        session: ScrollSession
    ) -> (ScrollSession, [ScrollSideEffect]) {
        guard case .active(let areas, let sel, let pending) = session else { return (session, []) }

        let newInput = pending + "\(number)"

        if let index = Int(newInput), index >= 1 && index <= areas.count {
            let couldExtend = (index * 10) <= areas.count
            if !couldExtend {
                // Unambiguous commit: select immediately.
                let next = ScrollSession.active(areas: areas, selected: index - 1, pendingInput: "")
                return (next, [.selectArea(at: index - 1), .resetDeactivationTimer])
            } else {
                // Could be a prefix of a larger number — accumulate.
                let next = ScrollSession.active(areas: areas, selected: sel, pendingInput: newInput)
                return (next, [.resetDeactivationTimer])
            }
        } else {
            // No matching area — discard pending.
            let next = ScrollSession.active(areas: areas, selected: sel, pendingInput: "")
            return (next, [.resetDeactivationTimer])
        }
    }

    private static func handleArrowKey(
        _ direction: ScrollDirection,
        isShift: Bool,
        session: ScrollSession,
        context: ScrollInputContext
    ) -> (ScrollSession, [ScrollSideEffect]) {
        let (afterCommit, commitEffects) = commitPendingInput(session: session)
        var effects = commitEffects

        if context.arrowMode == .select {
            let (next, selEffects) = handleArrowSelection(direction: direction, session: afterCommit)
            return (next, effects + selEffects)
        } else {
            guard let _ = afterCommit.selectedIndex else {
                return (afterCommit, effects + [.resetDeactivationTimer])
            }
            let speed = isShift ? context.dashSpeed : context.scrollSpeed
            effects.append(.performScroll(direction: direction, speed: speed))
            effects.append(.resetDeactivationTimer)
            return (afterCommit, effects)
        }
    }

    private static func handleScrollKey(
        _ direction: ScrollDirection,
        isShift: Bool,
        session: ScrollSession,
        context: ScrollInputContext
    ) -> (ScrollSession, [ScrollSideEffect]) {
        let (afterCommit, commitEffects) = commitPendingInput(session: session)
        var effects = commitEffects

        guard let _ = afterCommit.selectedIndex else {
            return (afterCommit, effects + [.resetDeactivationTimer])
        }
        let speed = isShift ? context.dashSpeed : context.scrollSpeed
        effects.append(.performScroll(direction: direction, speed: speed))
        effects.append(.resetDeactivationTimer)
        return (afterCommit, effects)
    }

    // MARK: - Arrow-selection sub-handler

    private static func handleArrowSelection(
        direction: ScrollDirection,
        session: ScrollSession
    ) -> (ScrollSession, [ScrollSideEffect]) {
        guard case .active(let areas, let sel, _) = session else {
            return (session, [.resetDeactivationTimer])
        }

        guard let currentSel = sel else {
            let next = ScrollSession.active(areas: areas, selected: 0, pendingInput: "")
            return (next, [.selectArea(at: 0), .resetDeactivationTimer])
        }

        let newIndex: Int
        switch direction {
        case .up, .left:
            newIndex = max(0, currentSel - 1)
        case .down, .right:
            newIndex = min(areas.count - 1, currentSel + 1)
        }

        let next = ScrollSession.active(areas: areas, selected: newIndex, pendingInput: "")
        return (next, [.selectArea(at: newIndex), .resetDeactivationTimer])
    }

    // MARK: - Pending-input commit (pure)

    /// Commit any accumulated digit input, or clear it if it doesn't resolve to a valid index.
    ///
    /// Returns the updated session and any effects required (select if resolving, nothing otherwise).
    static func commitPendingInput(
        session: ScrollSession
    ) -> (ScrollSession, [ScrollSideEffect]) {
        guard case .active(let areas, let sel, let pending) = session, !pending.isEmpty else {
            return (session, [])
        }

        guard let index = Int(pending), index >= 1, index <= areas.count else {
            let next = ScrollSession.active(areas: areas, selected: sel, pendingInput: "")
            return (next, [])
        }

        let next = ScrollSession.active(areas: areas, selected: index - 1, pendingInput: "")
        return (next, [.selectArea(at: index - 1)])
    }
}
