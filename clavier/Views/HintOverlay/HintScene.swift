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

    /// State the reducer emits as separate effects rather than storing in
    /// the session.
    struct Chrome: Equatable {
        var searchText: String = ""
        /// -1 means "no search active" (see `MatchCountPresenter`).
        var matchCount: Int = -1
        /// Hide-prefix mode: hint tokens hidden while search keeps working.
        var labelsHidden: Bool = false
    }

    /// The full token assignment the overlay lays out; `content` decides
    /// which of them are visible.
    let hintedElements: [HintedElement]
    let content: Content
    let chrome: Chrome
    let isContinuous: Bool

    static let maxNumberedMatches = 9

    static func derive(from session: HintSession, chrome: Chrome) -> HintScene {
        HintScene(
            hintedElements: session.hintedElements,
            content: content(for: session),
            chrome: chrome,
            isContinuous: session.isContinuous
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
