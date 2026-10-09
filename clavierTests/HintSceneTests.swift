import XCTest
@testable import clavier

final class HintSceneTests: XCTestCase {

    private let dummyAX: AXUIElement = AXUIElementCreateApplication(getpid())

    private func hinted(_ hint: String, x: CGFloat) -> HintedElement {
        let frame = CGRect(x: x, y: 100, width: 40, height: 20)
        let element = UIElement(
            stableID: ElementIdentity(pid: getpid(), role: "AXButton", frame: frame),
            axElement: dummyAX,
            frame: frame,
            visibleFrame: frame,
            role: "AXButton"
        )
        return HintedElement(element: element, hint: hint)
    }

    private lazy var elements: [HintedElement] = [
        hinted("aa", x: 0), hinted("as", x: 50), hinted("sa", x: 100), hinted("ss", x: 150),
    ]

    private func labels(_ scene: HintScene) -> [HintScene.Label] {
        guard case .hints(let labels) = scene.content else {
            XCTFail("expected .hints, got \(scene.content)")
            return []
        }
        return labels
    }

    // MARK: - Prefix filtering

    func test_emptyFilter_showsEveryTokenWithoutTypedPrefix() {
        let scene = HintScene.derive(
            from: .active(hintedElements: elements, filter: "", mode: .oneShot),
            chrome: .init()
        )
        let shown = labels(scene)
        XCTAssertEqual(shown.map(\.token), ["aa", "as", "sa", "ss"])
        XCTAssertTrue(shown.allSatisfy { $0.typedPrefix.isEmpty })
        XCTAssertEqual(scene.hintedElements.count, 4, "layout always covers the full assignment")
    }

    func test_prefixFilter_keepsMatchingTokensAndSplitsPrefix() {
        let scene = HintScene.derive(
            from: .active(hintedElements: elements, filter: "s", mode: .oneShot),
            chrome: .init()
        )
        let shown = labels(scene)
        XCTAssertEqual(shown.map(\.token), ["sa", "ss"])
        XCTAssertEqual(shown.map(\.typedPrefix), ["s", "s"])
        XCTAssertEqual(shown.map(\.remainder), ["a", "s"])
    }

    func test_prefixWithNoMatches_showsNothing() {
        let scene = HintScene.derive(
            from: .active(hintedElements: elements, filter: "x", mode: .oneShot),
            chrome: .init()
        )
        XCTAssertTrue(labels(scene).isEmpty)
    }

    // MARK: - Text search

    func test_textSearchWithoutMatches_showsAllTokensUnprefixed() {
        let scene = HintScene.derive(
            from: .textSearch(hintedElements: elements, matches: [], filter: "zz", mode: .oneShot),
            chrome: .init()
        )
        let shown = labels(scene)
        XCTAssertEqual(shown.count, 4)
        XCTAssertTrue(shown.allSatisfy { $0.typedPrefix.isEmpty })
    }

    func test_upToNineMatches_areNumbered() {
        let matches = (1...9).map { hinted("\($0)", x: CGFloat($0) * 50) }
        let scene = HintScene.derive(
            from: .textSearch(hintedElements: elements, matches: matches, filter: "ok", mode: .oneShot),
            chrome: .init()
        )
        guard case .numbered(let numbered) = scene.content else {
            return XCTFail("expected .numbered, got \(scene.content)")
        }
        XCTAssertEqual(numbered.map(\.token), (1...9).map(String.init))
        XCTAssertEqual(numbered.map(\.identity), matches.map(\.identity))
        XCTAssertTrue(numbered.allSatisfy { $0.typedPrefix.isEmpty })
    }

    func test_moreThanNineMatches_areOutlinedNotNumbered() {
        let matches = (0..<10).map { hinted("m\($0)", x: CGFloat($0) * 50) }
        let scene = HintScene.derive(
            from: .textSearch(hintedElements: elements, matches: matches, filter: "ok", mode: .oneShot),
            chrome: .init()
        )
        guard case .highlights(let boxes) = scene.content else {
            return XCTFail("expected .highlights, got \(scene.content)")
        }
        XCTAssertEqual(boxes.map(\.identity), matches.map(\.identity))
        XCTAssertEqual(boxes[0].frame, matches[0].element.visibleFrame.insetBy(dx: -2, dy: -2))
    }

    // MARK: - Chrome

    func test_chromeAndModeArePassedThrough() {
        let chrome = HintScene.Chrome(searchText: ">ab", matchCount: 3, labelsHidden: true)
        let scene = HintScene.derive(
            from: .active(hintedElements: elements, filter: ">ab", mode: .continuous),
            chrome: chrome
        )
        XCTAssertEqual(scene.chrome, chrome)
        XCTAssertTrue(scene.isContinuous)
    }

    func test_inactiveSession_isEmpty() {
        let scene = HintScene.derive(from: .inactive, chrome: .init())
        XCTAssertTrue(scene.hintedElements.isEmpty)
        XCTAssertTrue(labels(scene).isEmpty)
        XCTAssertFalse(scene.isContinuous)
    }

    // MARK: - Search pill visibility

    func test_pill_hiddenForEmptyFilter() {
        let scene = HintScene.derive(
            from: .active(hintedElements: elements, filter: "", mode: .oneShot),
            chrome: .init()
        )
        XCTAssertFalse(scene.isPillVisible)
    }

    func test_pill_hiddenWhileFilterIsAHintPrefix() {
        let scene = HintScene.derive(
            from: .active(hintedElements: elements, filter: "s", mode: .oneShot),
            chrome: .init(searchText: "s")
        )
        XCTAssertFalse(scene.isPillVisible)
    }

    func test_pill_visibleOnceFilterStopsMatchingPrefixes() {
        let scene = HintScene.derive(
            from: .active(hintedElements: elements, filter: "x", mode: .oneShot),
            chrome: .init(searchText: "x")
        )
        XCTAssertTrue(scene.isPillVisible)
    }

    func test_pill_visibleDuringTextSearch() {
        let scene = HintScene.derive(
            from: .textSearch(hintedElements: elements, matches: [], filter: "zz", mode: .oneShot),
            chrome: .init(searchText: "zz", matchCount: 0)
        )
        XCTAssertTrue(scene.isPillVisible)
    }

    func test_pill_visibleInHidePrefixMode() {
        let scene = HintScene.derive(
            from: .active(hintedElements: elements, filter: "", mode: .oneShot),
            chrome: .init(labelsHidden: true)
        )
        XCTAssertTrue(scene.isPillVisible)
    }

    func test_pill_visibleWithStatus_evenWithoutSession() {
        let scene = HintScene.derive(from: .inactive, chrome: .init(status: .waiting(appName: "Chrome")))
        XCTAssertTrue(scene.isPillVisible)
    }

    func test_pill_visibleInContinuousMode() {
        let scene = HintScene.derive(
            from: .active(hintedElements: elements, filter: "", mode: .continuous),
            chrome: .init()
        )
        XCTAssertTrue(scene.isPillVisible)
    }

    // MARK: - Bar

    func test_bar_waiting_showsProgressAndCancelHint() {
        let bar = HintScene.derive(from: .inactive, chrome: .init(status: .waiting(appName: "Chrome"))).bar
        XCTAssertEqual(bar.icon, .progress)
        XCTAssertEqual(bar.body, .message("Waiting for Chrome", detail: "Esc to cancel"))
        XCTAssertEqual(bar.segments, [])
    }

    func test_bar_nothingToClick_offersHelpOnlyWhenAsked() {
        let spotify = HintScene.derive(
            from: .inactive,
            chrome: .init(status: .nothingToClick(appName: "Spotify", offersHelp: true))
        ).bar
        XCTAssertEqual(spotify.icon, .nothingToClick)
        XCTAssertEqual(spotify.body, .message("Nothing to click in Spotify", detail: nil))
        XCTAssertEqual(spotify.segments, [.help("Why?")])

        let other = HintScene.derive(
            from: .inactive,
            chrome: .init(status: .nothingToClick(appName: "Finder", offersHelp: false))
        ).bar
        XCTAssertEqual(other.segments, [])
    }

    func test_bar_statusWinsOverSearchText() {
        let bar = HintScene.derive(
            from: .active(hintedElements: elements, filter: "a", mode: .oneShot),
            chrome: .init(searchText: "a", status: .waiting(appName: "Arc"))
        ).bar
        XCTAssertEqual(bar.body, .message("Waiting for Arc", detail: "Esc to cancel"))
    }

    func test_bar_search_showsQueryAndCount() {
        let bar = HintScene.derive(
            from: .textSearch(hintedElements: elements, matches: [], filter: "inv", mode: .oneShot),
            chrome: .init(searchText: "inv", matchCount: 3)
        ).bar
        XCTAssertEqual(bar.icon, .search)
        XCTAssertEqual(bar.body, .query("inv"))
        XCTAssertEqual(bar.segments, [.count(MatchCountPresenter.style(forCount: 3))])
    }

    func test_bar_continuous_carriesCountdown() {
        let countdown = HintScene.Countdown(secondsLeft: 4, totalSeconds: 5)
        let bar = HintScene.derive(
            from: .active(hintedElements: elements, filter: "", mode: .continuous),
            chrome: .init(countdown: countdown)
        ).bar
        XCTAssertEqual(bar.icon, .keyboard)
        XCTAssertEqual(bar.body, .placeholder("type to search"))
        XCTAssertEqual(bar.segments, [.continuous(countdown)])
    }

    func test_bar_continuousWithoutAutoDeactivation_hasNoCountdown() {
        let bar = HintScene.derive(
            from: .active(hintedElements: elements, filter: "", mode: .continuous),
            chrome: .init()
        ).bar
        XCTAssertEqual(bar.segments, [.continuous(nil)])
    }

    func test_bar_oneShot_hasNoContinuousSegment() {
        let bar = HintScene.derive(
            from: .textSearch(hintedElements: elements, matches: [], filter: "zz", mode: .oneShot),
            chrome: .init(searchText: "zz")
        ).bar
        XCTAssertEqual(bar.segments, [])
    }

    func test_countdown_fraction_isClamped() {
        XCTAssertEqual(HintScene.Countdown(secondsLeft: 4, totalSeconds: 5).fraction, 0.8, accuracy: 0.0001)
        XCTAssertEqual(HintScene.Countdown(secondsLeft: 9, totalSeconds: 5).fraction, 1)
        XCTAssertEqual(HintScene.Countdown(secondsLeft: 3, totalSeconds: 0).fraction, 0)
    }

    func test_pill_hiddenWhenInactive() {
        XCTAssertFalse(HintScene.derive(from: .inactive, chrome: .init()).isPillVisible)
    }

    // MARK: - Equality drives redraw skipping

    func test_contentEquality_ignoresChromeOnlyChanges() {
        let session = HintSession.active(hintedElements: elements, filter: "a", mode: .oneShot)
        let a = HintScene.derive(from: session, chrome: .init(searchText: "a"))
        let b = HintScene.derive(from: session, chrome: .init(searchText: "a", matchCount: 0))
        XCTAssertEqual(a.content, b.content)

        let c = HintScene.derive(
            from: .active(hintedElements: elements, filter: "as", mode: .oneShot),
            chrome: .init()
        )
        XCTAssertNotEqual(a.content, c.content)
    }
}
