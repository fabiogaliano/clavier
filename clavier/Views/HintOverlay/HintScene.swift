import CoreGraphics

/// Everything the hint overlay draws, as a pure value.
///
/// Derived from a `HintSession` plus the chrome state the reducer emits
/// alongside it, so filtering, numbered re-labelling and highlight boxes are
/// decided here (and unit-tested) instead of inside `HintOverlayWindow`.
struct HintScene {

    /// One hint bubble. `typedPrefix` is the part of `token` the user has
    /// already typed and is drawn in the highlight colour.
    struct Label {
        let hinted: HintedElement
        let typedPrefix: String

        var identity: ElementIdentity { hinted.identity }
        var token: String { hinted.hint }
        var remainder: String { String(token.dropFirst(typedPrefix.count)) }
    }

    /// A text-search match drawn as a box rather than a label (screen
    /// coordinates, already inset for the outline).
    struct HighlightBox: Equatable {
        let identity: ElementIdentity
        let frame: CGRect
    }

    enum Content {
        /// Prefix-filtered hint tokens; elements not listed are hidden.
        case hints([Label])
        /// ≤ 9 text-search matches re-labelled "1"…"9"; hint tokens hidden.
        case numbered([Label])
        /// > 9 text-search matches outlined; hint tokens hidden.
        case highlights([HighlightBox])
    }

    /// A controller message that takes over the bar while there are no
    /// hints to act on.
    enum Status: Equatable {
        /// Discovery is still waiting for the app's accessibility tree.
        case waiting(appName: String)
        /// Discovery finished empty. `offersHelp` when the app is one with a
        /// known fix (Spotify's dormant CEF tree).
        case nothingToClick(appName: String, offersHelp: Bool)
    }

    /// Time left before continuous mode deactivates itself.
    struct Countdown: Equatable {
        let secondsLeft: Int
        let totalSeconds: Int

        /// Ring fill, 1 when freshly reset and 0 at deactivation.
        var fraction: Double {
            guard totalSeconds > 0 else { return 0 }
            return min(max(Double(secondsLeft) / Double(totalSeconds), 0), 1)
        }
    }

    /// What the bar draws, decided here so the view only lays it out.
    struct Bar: Equatable {
        enum Icon: Equatable { case keyboard, search, progress, nothingToClick }

        enum Body: Equatable {
            case query(String)
            case placeholder(String)
            case message(String, detail: String?)
        }

        enum Segment: Equatable {
            case count(MatchCountPresenter.Style)
            /// `nil` countdown: continuous without auto-deactivation, so
            /// there is nothing to drain.
            case continuous(Countdown?)
            /// Opens the help for an app that cannot be hinted as-is.
            case help(String)
        }

        let icon: Icon
        let body: Body
        let segments: [Segment]
    }

    /// State the reducer emits as separate effects rather than storing in
    /// the session.
    struct Chrome: Equatable {
        var searchText: String = ""
        /// -1 means "no search active" (see `MatchCountPresenter`).
        var matchCount: Int = -1
        /// Text hydration still running: a zero count is "unknown", not "none".
        var isHydrating: Bool = false
        /// Hide-prefix mode: hint tokens hidden while search keeps working.
        var labelsHidden: Bool = false
        /// Controller message shown in the bar in place of the search text.
        var status: Status? = nil
        /// Continuous-mode auto-deactivation; `nil` when it is off.
        var countdown: Countdown? = nil
    }

    /// The full token assignment the overlay lays out; `content` decides
    /// which of them are visible.
    let hintedElements: [HintedElement]
    let content: Content
    let chrome: Chrome
    let isContinuous: Bool
    /// Most sessions are a two-key token and never search, so the bar stays
    /// out of the way until typing stops being a hint prefix, a status needs
    /// saying, or continuous mode needs its countdown.
    let isPillVisible: Bool

    static let maxNumberedMatches = 9

    static func derive(from session: HintSession, chrome: Chrome) -> HintScene {
        HintScene(
            hintedElements: session.hintedElements,
            content: content(for: session),
            chrome: chrome,
            isContinuous: session.isContinuous,
            isPillVisible: pillVisible(for: session, chrome: chrome)
        )
    }

    private static func pillVisible(for session: HintSession, chrome: Chrome) -> Bool {
        if chrome.status != nil || chrome.labelsHidden || session.isContinuous { return true }
        switch session {
        case .inactive:
            return false
        case .active(let elements, let filter, _):
            return !filter.isEmpty && !elements.contains { $0.hint.hasPrefix(filter) }
        case .textSearch:
            return true
        }
    }

    var bar: Bar {
        switch chrome.status {
        case .waiting(let appName):
            return Bar(icon: .progress, body: .message("Waiting for \(appName)", detail: "Esc to cancel"), segments: [])
        case .nothingToClick(let appName, let offersHelp):
            return Bar(
                icon: .nothingToClick,
                body: .message("Nothing to click in \(appName)", detail: nil),
                segments: offersHelp ? [.help("Why?")] : []
            )
        case nil:
            break
        }

        let searching = chrome.labelsHidden || !chrome.searchText.isEmpty
        var segments: [Bar.Segment] = []
        let count = MatchCountPresenter.style(forCount: chrome.matchCount, isHydrating: chrome.isHydrating)
        if !count.labelText.isEmpty {
            segments.append(.count(count))
        }
        if isContinuous {
            segments.append(.continuous(chrome.countdown))
        }
        return Bar(
            icon: searching ? .search : .keyboard,
            body: chrome.searchText.isEmpty ? .placeholder("type to search") : .query(chrome.searchText),
            segments: segments
        )
    }

    private static func content(for session: HintSession) -> Content {
        switch session {
        case .inactive:
            return .hints([])

        case .active(let elements, let filter, _):
            return .hints(prefixFiltered(elements, by: filter))

        case .textSearch(let elements, let matches, _, _):
            if matches.isEmpty {
                return .hints(prefixFiltered(elements, by: ""))
            }
            if matches.count <= maxNumberedMatches {
                return .numbered(matches.map { Label(hinted: $0, typedPrefix: "") })
            }
            return .highlights(matches.map {
                HighlightBox(identity: $0.identity, frame: $0.element.visibleFrame.insetBy(dx: -2, dy: -2))
            })
        }
    }

    private static func prefixFiltered(_ elements: [HintedElement], by prefix: String) -> [Label] {
        elements
            .filter { prefix.isEmpty || $0.hint.hasPrefix(prefix) }
            .map { Label(hinted: $0, typedPrefix: prefix) }
    }
}

// Equality is what lets the window skip redrawing content when only chrome
// changed; it compares what is drawn (identity, token, prefix, geometry), not
// the AX handles behind it.
extension HintScene.Label: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.identity == rhs.identity
            && lhs.token == rhs.token
            && lhs.typedPrefix == rhs.typedPrefix
            && lhs.hinted.element.visibleFrame == rhs.hinted.element.visibleFrame
    }
}

extension HintScene.Content: Equatable {}
