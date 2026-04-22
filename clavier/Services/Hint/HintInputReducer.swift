//
//  HintInputReducer.swift
//  clavier
//
//  Pure state-transition function for hint mode input.
//
//  Takes the current `HintSession` and a decoded `HintInputCommand`,
//  returns the next session state plus a list of side effects the
//  controller must execute.  No I/O, no UserDefaults reads, no timer
//  scheduling — those concerns stay in the caller.
//
//  Inputs that require caller-supplied values (text-search settings,
//  refresh trigger string) are passed via `HintInputContext` so the
//  reducer itself remains testable without UserDefaults.
//

import Foundation

// MARK: - Side effects

/// Side effects produced by `HintInputReducer.reduce`.
///
/// The controller switches over each element in the returned array and
/// executes the corresponding operation.  Conforms to `ReducerSideEffect`
/// from P4-S1.
enum HintSideEffect: ReducerSideEffect {
    /// Perform a primary (left) click on the given element.
    case performClick(on: UIElement)
    /// Perform a right-click (AXShowMenu or CGEvent) on the given element.
    case performRightClick(on: UIElement)
    /// Deactivate hint mode entirely.
    case deactivate
    /// Update the overlay to reflect the current session state.
    case updateOverlay(session: HintSession)
    /// Update the search bar text displayed in the overlay.
    case showSearchBar(text: String)
    /// Update the match count badge in the overlay.
    case updateMatchCount(Int)
    /// Schedule a post-click refresh (continuous mode handling).
    case scheduleRefresh
    /// Perform an immediate manual refresh (re-query elements).
    case manualRefresh
    /// Rotate overlap z-order in the overlay (Space with empty filter).
    case rotateOverlap
}

// MARK: - Input context

/// Caller-supplied context values that the reducer needs but must not read
/// directly (they come from UserDefaults and are only valid on MainActor).
struct HintInputContext {
    let textSearchEnabled: Bool
    let minSearchChars: Int
    let refreshTrigger: String

    init(
        textSearchEnabled: Bool,
        minSearchChars: Int,
        refreshTrigger: String
    ) {
        self.textSearchEnabled = textSearchEnabled
        self.minSearchChars = minSearchChars
        self.refreshTrigger = refreshTrigger
    }
}

// MARK: - Reducer

/// Stateless reducer mapping `(HintSession, HintInputCommand) → (HintSession, [HintSideEffect])`.
///
/// "Stateless" means the function has no stored state — it derives the next
/// state entirely from its inputs.  The session value is the single source of
/// truth; the caller stores and threads it.
enum HintInputReducer {

    // MARK: Public entry point

    /// Compute the next session state and effects for the given command.
    ///
    /// - Parameters:
    ///   - session:  Current hint session (owned by `HintModeController`).
    ///   - command:  Decoded keyboard command (from `HintInputDecoder`).
    ///   - context:  Caller-supplied settings snapshot (UserDefaults values
    ///               already read on the main actor before calling in).
    /// - Returns:    Next session state and list of effects to execute.
    @MainActor
    static func reduce(
        session: HintSession,
        command: HintInputCommand,
        context: HintInputContext
    ) -> (HintSession, [HintSideEffect]) {
        guard session.isActive else { return (session, []) }

        switch command {
        case .escape:
            return handleEscape(session: session)

        case .backspace:
            return handleBackspace(session: session, context: context)

        case .character(let char):
            let newFilter = session.filter + char
            return handleInput(session: sessionWithFilter(session, newFilter), context: context)

        case .spaceKey:
            return handleSpaceKey(session: session, context: context)

        case .clearSearch:
            return handleClearSearch(session: session)

        case .selectNumbered(let number):
            return handleSelectNumbered(number: number, session: session)

        case .enter(let withControl):
            return handleEnter(session: session, withControl: withControl, context: context)

        case .passThrough:
            return (session, [])
        }
    }

    // MARK: - Command handlers

    /// Space with empty filter → rotate overlap z-order (visual disambiguation).
    /// Space with a non-empty filter → append " " so multi-word text search keeps working.
    private static func handleSpaceKey(
        session: HintSession,
        context: HintInputContext
    ) -> (HintSession, [HintSideEffect]) {
        if session.filter.isEmpty {
            return (session, [.rotateOverlap])
        }
        let newFilter = session.filter + " "
        return handleInput(session: sessionWithFilter(session, newFilter), context: context)
    }

    private static func handleEscape(
        session: HintSession
    ) -> (HintSession, [HintSideEffect]) {
        // First ESC with a non-empty filter: clear filter and restore full hint set.
        // Second ESC (or first when filter is already empty): exit hint mode.
        if !session.filter.isEmpty {
            let cleared = clearFilter(session)
            return (cleared, [
                .showSearchBar(text: ""),
                .updateMatchCount(-1),
                .updateOverlay(session: cleared)
            ])
        } else {
            return (.inactive, [.deactivate])
        }
    }

    private static func handleBackspace(
        session: HintSession,
        context: HintInputContext
    ) -> (HintSession, [HintSideEffect]) {
        guard !session.filter.isEmpty else { return (session, []) }
        var newFilter = session.filter
        newFilter.removeLast()
        let updatedSession = sessionWithFilter(session, newFilter)
        return handleInput(session: updatedSession, context: context)
    }

    private static func handleClearSearch(
        session: HintSession
    ) -> (HintSession, [HintSideEffect]) {
        let cleared = clearFilter(session)
        return (cleared, [
            .showSearchBar(text: ""),
            .updateOverlay(session: cleared),
            .updateMatchCount(-1)
        ])
    }

    private static func handleSelectNumbered(
        number: Int,
        session: HintSession
    ) -> (HintSession, [HintSideEffect]) {
        guard case .textSearch(let elements, let matches, _) = session,
              number > 0, number <= matches.count else { return (session, []) }
        let hintedElement = matches[number - 1]
        let nextSession = HintSession.active(hintedElements: elements, filter: "")
        return (nextSession, [
            .performClick(on: hintedElement.element),
            .showSearchBar(text: ""),
            .updateMatchCount(-1),
            .scheduleRefresh
        ])
    }

    private static func handleEnter(
        session: HintSession,
        withControl: Bool,
        context: HintInputContext
    ) -> (HintSession, [HintSideEffect]) {
        guard session.filter.count >= context.minSearchChars else { return (session, []) }
        let matches = searchElementsByText(session.filter, in: session.hintedElements)
        guard let first = matches.first else { return (session, []) }
        let clickEffect: HintSideEffect = withControl
            ? .performRightClick(on: first.element)
            : .performClick(on: first.element)
        return (session, [clickEffect, .scheduleRefresh])
    }

    // MARK: - Core input dispatch (filter change)

    /// Process the current filter string against the session's hinted elements.
    ///
    /// This is the central branching point that was previously `processInput` in
    /// `HintModeController`.  The logic is unchanged — only the I/O (overlay calls)
    /// is expressed as side effects rather than direct method calls.
    private static func handleInput(
        session: HintSession,
        context: HintInputContext
    ) -> (HintSession, [HintSideEffect]) {
        let input = session.filter
        var effects: [HintSideEffect] = [.showSearchBar(text: input)]

        // Manual refresh trigger
        if input == context.refreshTrigger && !context.refreshTrigger.isEmpty {
            let cleared = clearFilter(session)
            effects.append(.showSearchBar(text: ""))
            effects.append(.manualRefresh)
            return (cleared, effects)
        }

        // Exact hint match → click
        if let matched = session.hintedElements.first(where: { $0.hint == input }) {
            let nextSession = clearFilter(session)
            effects.append(.updateOverlay(session: sessionWithFilter(session, input)))
            effects.append(.showSearchBar(text: ""))
            effects.append(.updateMatchCount(-1))
            effects.append(.performClick(on: matched.element))
            effects.append(.scheduleRefresh)
            return (nextSession, effects)
        }

        // Prefix match → narrow overlay
        // Collapse any .textSearch shape back to .active so the overlay renders
        // alphabetic prefix hints, not stale text-search match boxes.
        let prefixMatches = session.hintedElements.filter { $0.hint.hasPrefix(input) }
        if !prefixMatches.isEmpty {
            let updated = sessionAsActive(session, filter: input)
            effects.append(.updateOverlay(session: updated))
            return (updated, effects)
        }

        // Text search
        if context.textSearchEnabled && input.count >= context.minSearchChars {
            return handleTextSearch(input: input, session: session, effects: effects)
        }

        // No match and text search not triggered — clear results.
        // Collapse .textSearch to .active so no stale match boxes are shown.
        let updated = sessionAsActive(session, filter: input)
        effects.append(.updateOverlay(session: updated))
        effects.append(.updateMatchCount(0))
        return (updated, effects)
    }

    // MARK: - Text search branch

    private static func handleTextSearch(
        input: String,
        session: HintSession,
        effects: [HintSideEffect]
    ) -> (HintSession, [HintSideEffect]) {
        var effects = effects
        let textMatches = searchElementsByText(input, in: session.hintedElements)

        if textMatches.count == 1 {
            let nextSession = clearFilter(session)
            effects.append(.showSearchBar(text: ""))
            effects.append(.updateMatchCount(-1))
            effects.append(.performClick(on: textMatches[0].element))
            effects.append(.scheduleRefresh)
            return (nextSession, effects)
        }

        if textMatches.isEmpty {
            let updated = sessionWithFilter(session, input)
            effects.append(.updateOverlay(session: updated))
            effects.append(.updateMatchCount(0))
            return (updated, effects)
        }

        if textMatches.count <= 9 {
            let numberedMatches = assignNumberedHints(to: textMatches.map { $0.element })
            let nextSession = HintSession.textSearch(
                hintedElements: session.hintedElements,
                matches: numberedMatches,
                filter: input
            )
            effects.append(.updateOverlay(session: nextSession))
            effects.append(.updateMatchCount(numberedMatches.count))
            return (nextSession, effects)
        }

        // More than 9 matches — show green highlight boxes without numbering
        let nextSession = HintSession.textSearch(
            hintedElements: session.hintedElements,
            matches: textMatches,
            filter: input
        )
        effects.append(.updateOverlay(session: nextSession))
        effects.append(.updateMatchCount(textMatches.count))
        return (nextSession, effects)
    }

    // MARK: - Helpers (pure)

    private static func searchElementsByText(_ text: String, in hinted: [HintedElement]) -> [HintedElement] {
        let lowercased = text.lowercased()
        return hinted.filter { $0.element.searchableText.lowercased().contains(lowercased) }
    }

    private static func assignNumberedHints(to elements: [UIElement]) -> [HintedElement] {
        elements.prefix(9).enumerated().map { index, element in
            HintedElement(element: element, hint: "\(index + 1)")
        }
    }

    /// Return a copy of `session` with only the filter component changed.
    private static func sessionWithFilter(_ session: HintSession, _ filter: String) -> HintSession {
        switch session {
        case .inactive:
            return .inactive
        case .active(let elements, _):
            return .active(hintedElements: elements, filter: filter)
        case .textSearch(let elements, let matches, _):
            return .textSearch(hintedElements: elements, matches: matches, filter: filter)
        }
    }

    /// Return an `.active` session regardless of the current session shape.
    ///
    /// Use this instead of `sessionWithFilter` when backspacing from `.textSearch`
    /// into a prefix-match or no-match state so that the overlay receives `.active`
    /// and renders alphabetic hint labels rather than stale text-search match boxes.
    private static func sessionAsActive(_ session: HintSession, filter: String) -> HintSession {
        return .active(hintedElements: session.hintedElements, filter: filter)
    }

    /// Return a session with the filter cleared and any text-search state collapsed.
    private static func clearFilter(_ session: HintSession) -> HintSession {
        switch session {
        case .inactive:
            return .inactive
        case .active(let elements, _):
            return .active(hintedElements: elements, filter: "")
        case .textSearch(let elements, _, _):
            return .active(hintedElements: elements, filter: "")
        }
    }

}
