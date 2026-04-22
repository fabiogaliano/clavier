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
    /// Toggle visibility of all hint labels in the overlay. When hidden,
    /// the search bar and search results still render normally.
    case setLabelsHidden(Bool)
}

// MARK: - Input context

/// Caller-supplied context values that the reducer needs but must not read
/// directly (they come from UserDefaults and are only valid on MainActor).
struct HintInputContext {
    let textSearchEnabled: Bool
    let minSearchChars: Int
    let refreshTrigger: String
    /// Single marker character that, when typed as the first filter
    /// character, hides all hint labels while still feeding the remainder
    /// of the query into the normal search pipeline. Empty disables the
    /// feature.
    let hidePrefix: String

    init(
        textSearchEnabled: Bool,
        minSearchChars: Int,
        refreshTrigger: String,
        hidePrefix: String = ""
    ) {
        self.textSearchEnabled = textSearchEnabled
        self.minSearchChars = minSearchChars
        self.refreshTrigger = refreshTrigger
        self.hidePrefix = hidePrefix
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
                .setLabelsHidden(false),
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
            .setLabelsHidden(false),
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
            .setLabelsHidden(false),
            .scheduleRefresh
        ])
    }

    private static func handleEnter(
        session: HintSession,
        withControl: Bool,
        context: HintInputContext
    ) -> (HintSession, [HintSideEffect]) {
        let effective = effectiveFilter(session.filter, context: context)
        guard effective.count >= context.minSearchChars else { return (session, []) }
        let matches = searchElementsByText(effective, in: session.hintedElements)
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
        let rawInput = session.filter
        let hideActive = isHidePrefixActive(rawInput, context: context)
        let effective = effectiveFilter(rawInput, context: context)

        // Always mirror hidden-mode state in the overlay so backspacing out of
        // the prefix restores labels immediately.
        var effects: [HintSideEffect] = [
            .setLabelsHidden(hideActive),
            .showSearchBar(text: rawInput)
        ]

        // Manual refresh trigger — match against the effective filter so a
        // hidden-mode query can still fire the trigger.  The sanitizer
        // guarantees the hide prefix is non-alphanumeric, so "rr" never
        // collides with "`>rr`".
        if effective == context.refreshTrigger && !context.refreshTrigger.isEmpty {
            let cleared = clearFilter(session)
            effects.append(.showSearchBar(text: ""))
            effects.append(.setLabelsHidden(false))
            effects.append(.manualRefresh)
            return (cleared, effects)
        }

        // Exact hint match → click.  Hide-prefix mode disables this so the
        // user can type a search query that happens to start with hint
        // characters (e.g. ">ad" should search, not auto-click hint "ad").
        if !hideActive, let matched = session.hintedElements.first(where: { $0.hint == effective }) {
            let nextSession = clearFilter(session)
            effects.append(.updateOverlay(session: sessionWithFilter(session, rawInput)))
            effects.append(.showSearchBar(text: ""))
            effects.append(.updateMatchCount(-1))
            effects.append(.setLabelsHidden(false))
            effects.append(.performClick(on: matched.element))
            effects.append(.scheduleRefresh)
            return (nextSession, effects)
        }

        // Prefix match (narrow hint set).  Skipped in hide-mode — the whole
        // point of hide-mode is that hint tokens don't participate.
        if !hideActive {
            let prefixMatches = session.hintedElements.filter { $0.hint.hasPrefix(effective) }
            if !prefixMatches.isEmpty {
                let updated = sessionAsActive(session, filter: rawInput)
                effects.append(.updateOverlay(session: updated))
                return (updated, effects)
            }
        }

        // Text search uses the effective filter so hidden-mode queries work
        // identically to non-hidden ones.
        if context.textSearchEnabled && effective.count >= context.minSearchChars {
            return handleTextSearch(input: effective, rawFilter: rawInput, session: session, effects: effects)
        }

        // No match and text search not triggered — clear results.
        let updated = sessionAsActive(session, filter: rawInput)
        effects.append(.updateOverlay(session: updated))
        effects.append(.updateMatchCount(effective.isEmpty ? -1 : 0))
        return (updated, effects)
    }

    // MARK: - Text search branch

    private static func handleTextSearch(
        input: String,
        rawFilter: String,
        session: HintSession,
        effects: [HintSideEffect]
    ) -> (HintSession, [HintSideEffect]) {
        var effects = effects
        let textMatches = searchElementsByText(input, in: session.hintedElements)

        if textMatches.count == 1 {
            let nextSession = clearFilter(session)
            effects.append(.showSearchBar(text: ""))
            effects.append(.updateMatchCount(-1))
            effects.append(.setLabelsHidden(false))
            effects.append(.performClick(on: textMatches[0].element))
            effects.append(.scheduleRefresh)
            return (nextSession, effects)
        }

        if textMatches.isEmpty {
            let updated = sessionWithFilter(session, rawFilter)
            effects.append(.updateOverlay(session: updated))
            effects.append(.updateMatchCount(0))
            return (updated, effects)
        }

        if textMatches.count <= 9 {
            let numberedMatches = assignNumberedHints(to: textMatches.map { $0.element })
            let nextSession = HintSession.textSearch(
                hintedElements: session.hintedElements,
                matches: numberedMatches,
                filter: rawFilter
            )
            effects.append(.updateOverlay(session: nextSession))
            effects.append(.updateMatchCount(numberedMatches.count))
            return (nextSession, effects)
        }

        // More than 9 matches — show green highlight boxes without numbering
        let nextSession = HintSession.textSearch(
            hintedElements: session.hintedElements,
            matches: textMatches,
            filter: rawFilter
        )
        effects.append(.updateOverlay(session: nextSession))
        effects.append(.updateMatchCount(textMatches.count))
        return (nextSession, effects)
    }

    // MARK: - Helpers (pure)

    /// Return true when the filter begins with the configured hide-prefix.
    /// Returns false when the prefix is disabled (empty).
    static func isHidePrefixActive(_ filter: String, context: HintInputContext) -> Bool {
        guard !context.hidePrefix.isEmpty else { return false }
        return filter.hasPrefix(context.hidePrefix)
    }

    /// The portion of the filter that drives matching — with the hide-prefix
    /// removed when active. The raw filter stays unchanged in session state
    /// so backspace can peel back characters (including the prefix itself).
    static func effectiveFilter(_ filter: String, context: HintInputContext) -> String {
        guard isHidePrefixActive(filter, context: context) else { return filter }
        return String(filter.dropFirst(context.hidePrefix.count))
    }

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
