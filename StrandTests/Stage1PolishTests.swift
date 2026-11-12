import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

// Stage 1 (weigh-in and scorecard): the last open items before the stage closes. Written before
// the repairs exist. Synthetic values only.
//
// API ASSUMED BY THESE TESTS (new; everything else is used as it exists today)
//
//     /// The two keys of the Liquid Today weight tile. `ktile` used one `key` for both the
//     /// catalogue page a tap pushes and the series its detailed-mode sparkline draws, so a route
//     /// that is not a catalogue page (the weigh-in sheet, flag on) took the sparkline away.
//     struct LiquidWeightTileKeys: Equatable {
//         /// The catalogue key the tile pushes: `route.metricKey`. Nil for every other route.
//         let navigationKey: String?
//         /// The key `ktile` hands to `TodayDayModel.windowedSpark(_:windowDays:)`, and the key
//         /// `TodayDayModel` banks the weight series under in `kSparks`: "weight", whatever the route.
//         let sparklineKey: String
//         init(route: BodyMeasurementCorrectionRoute)
//     }
//
// `LiquidTodayView`'s weight tile builds `LiquidWeightTileKeys(route:)` from its correction route
// and passes the two keys to `ktile` separately. With the flag off both are "weight", which is the
// one `key: "weight"` the tile passed at the base commit.
//
// Assumed of the sources, checked by scan because the code is iPhone-only or DEBUG-only and so is
// not compiled into this macOS-hosted bundle:
//
//  - `StrandiOS/Scorecard/ScorecardDemo.swift`: the `flow-` route is still recognised on a device
//    (its `hasPrefix("flow-")` check is outside any simulator condition), and every line that names
//    `ScorecardFlowHost` or a live handle (see `liveHandles` below) sits inside
//    `#if targetEnvironment(simulator)`. No other app source names `ScorecardFlowHost`.
//
// Item 4 of this round (no word breaks mid-word at the largest accessibility size, in the redesign
// Today Weight row, the weigh-in sheet's "done" row and the phase sheet's value-and-unit column) is
// VIEW-ONLY. The three rows are SwiftUI layout in `StrandiOS/`, which this bundle does not compile,
// and what decides the layout is the environment's `dynamicTypeSize`, which those views already
// read. There is no presenter value below them to pin; they are checked on the simulator at AX5.
//
// Item 5 is a check, and both halves hold at the commit these tests were written against:
//
//  - The redesign's card editor offers the scorecard card with the flag on. It is the LAST entry of
//    the list of cards that can be added (`DashboardCard.canonicalOrder` is the declaration order),
//    which is why it is several screens down.
//  - The approved frame B3 (`design/round6-scorecard/scorecard.js`, "B3 Scorecard · no cut phase")
//    draws the count in its verdict header. The frame's rule is `known ? "<met> of 4 signals met" :
//    ""`, where `known` counts the signals that are not unknown. With no cut phase the waist, the
//    working weights and the protein floor are still judged, so the header reads "3 of 4 signals
//    met" beside "Verdict".

// MARK: - Shared

private enum PolishSource {
    struct NotReachable: Error, CustomStringConvertible {
        let path: String
        var description: String { "\(path) is not reachable from the test sources" }
    }

    static func root(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)").deletingLastPathComponent().deletingLastPathComponent()
    }

    static func text(_ relative: String) throws -> String {
        let url = root().appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else { throw NotReachable(path: relative) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Every Swift file under the app-target folders, as paths relative to the repository root.
    static func appSwiftFiles() -> [String] {
        let base = root()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []
        let folders = names.filter { $0 == "Strand" || $0.hasPrefix("StrandiOS") || $0.hasPrefix("NOOPWatch") }
        var found: [String] = []
        for folder in folders.sorted() {
            guard let walker = FileManager.default.enumerator(atPath: base.appendingPathComponent(folder).path) else {
                continue
            }
            for case let item as String in walker where item.hasSuffix(".swift") {
                found.append("\(folder)/\(item)")
            }
        }
        return found.sorted()
    }

    /// The file's lines with `//` comments removed. String literals are kept, so a `//` inside one
    /// is not taken for a comment.
    static func codeLines(_ text: String) -> [String] {
        text.components(separatedBy: "\n").map { line in
            var kept = ""
            var inString = false
            var previous: Character?
            var index = line.startIndex
            while index < line.endIndex {
                let character = line[index]
                let next = line.index(after: index)
                if character == "\"", previous != "\\" { inString.toggle() }
                if !inString, character == "/", next < line.endIndex, line[next] == "/" { break }
                kept.append(character)
                previous = character
                index = next
            }
            return kept
        }
    }

    /// For each line, true when it is compiled only for the simulator: it sits in the true branch
    /// of an `#if` whose condition requires `targetEnvironment(simulator)`, or in the `#else`
    /// branch of `#if !targetEnvironment(simulator)`.
    static func simulatorOnly(_ lines: [String]) -> [Bool] {
        // One entry per open `#if`: whether the current branch is simulator-only, and whether its
        // `#else` branch would be.
        var stack: [(now: Bool, otherwise: Bool)] = []
        var result: [Bool] = []
        func branch(_ condition: String) -> (now: Bool, otherwise: Bool) {
            let compact = condition.replacingOccurrences(of: " ", with: "")
            if compact == "!targetEnvironment(simulator)" { return (false, true) }
            let requires = compact.contains("targetEnvironment(simulator)")
                && !compact.contains("!targetEnvironment(simulator)") && !compact.contains("||")
            return (requires, false)
        }
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#if ") {
                stack.append(branch(String(trimmed.dropFirst(4))))
                result.append(stack.dropLast().contains { $0.now })
            } else if trimmed.hasPrefix("#elseif ") {
                if !stack.isEmpty { stack[stack.count - 1] = branch(String(trimmed.dropFirst(8))) }
                result.append(stack.dropLast().contains { $0.now })
            } else if trimmed.hasPrefix("#else") {
                if let top = stack.last { stack[stack.count - 1] = (top.otherwise, false) }
                result.append(stack.dropLast().contains { $0.now })
            } else if trimmed.hasPrefix("#endif") {
                _ = stack.popLast()
                result.append(stack.contains { $0.now })
            } else {
                result.append(stack.contains { $0.now })
            }
        }
        return result
    }
}

/// A store with an Apple Health weight ten days back and a Lab Book weigh-in today, on a clock two
/// days behind the real one (the repository's Apple Health reads are windowed on the real clock).
@MainActor
private struct PolishHarness {
    let store: WhoopStore
    let repo: Repository
    let provider: BodyMeasurementProvider
    let suite: String
    let appleDay: String
    let labDay: String

    static let deviceId = "my-whoop"
    static let appleWeight = 101.5
    static let labWeight = 99.2

    static func make(flag: Bool, readings: Bool = true) async throws -> PolishHarness {
        let suite = "Stage1PolishTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        if flag { defaults.set(true, forKey: "noop.cutScorecardEnabled") }
        defaults.set(80.0, forKey: "profile.weightKg")
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: deviceId)
        repo.setStoreForTesting(store)

        let seconds = Int(Date().timeIntervalSince1970) - 2 * 86_400
        let start = Date(timeIntervalSince1970: Double(seconds - seconds % 86_400))
        func day(_ offset: Int) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: start.addingTimeInterval(Double(offset) * 86_400))
        }
        let today = day(0)
        let provider = BodyMeasurementProvider(repository: repo, defaults: defaults, today: { today })
        if readings {
            try await store.upsertAppleDaily(
                [AppleDaily(day: day(-10), steps: nil, activeKcal: nil, basalKcal: nil, vo2max: nil, avgHr: nil,
                            maxHr: nil, walkingHr: nil, weightKg: appleWeight)], deviceId: "apple-health")
            try await store.upsertMetricSeries([MetricPoint(day: day(-10), key: "weight", value: appleWeight)],
                                               deviceId: "apple-health")
            let takenAt = Int(start.timeIntervalSince1970) + 7 * 3_600
            try await store.upsertLabMarkers([
                LabMarkerRow(id: "weight-\(takenAt)-0A1B2C3D", deviceId: deviceId, markerKey: "weight",
                             category: "bodyMeasurement", day: today, takenAt: takenAt, value: labWeight,
                             valueText: nil, unit: "kg", source: "manual", note: nil, referenceText: nil),
            ])
        }
        await provider.refresh()
        return PolishHarness(store: store, repo: repo, provider: provider, suite: suite, appleDay: day(-10),
                             labDay: today)
    }

    func removeSuite() { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

    /// What the Liquid Today weight tile draws in detailed mode: the provider's series, banked by
    /// the day model under the tile's sparkline key and read back through `windowedSpark`.
    func tileSparkline(_ keys: LiquidWeightTileKeys, windowDays: Int = 30) async -> (series: BodyWeightSeries,
                                                                                 drawn: [Double]) {
        let series = await provider.displayWeightSeries(days: 91)
        let model = TodayDayModel()
        model.kSparks["weight"] = series.points.map { ($0.day, $0.value) }
        return (series, model.windowedSpark(keys.sparklineKey, windowDays: windowDays))
    }
}

// MARK: - Item 2. The Liquid Today weight tile keeps its sparkline

@MainActor
final class Stage1PolishLiquidSparklineTests: XCTestCase {
    private var harnesses: [PolishHarness] = []

    override func tearDown() {
        harnesses.forEach { $0.removeSuite() }
        harnesses = []
        super.tearDown()
    }

    private func harness(flag: Bool, readings: Bool = true) async throws -> PolishHarness {
        let made = try await PolishHarness.make(flag: flag, readings: readings)
        harnesses.append(made)
        return made
    }

    private func keys(_ h: PolishHarness) -> LiquidWeightTileKeys {
        LiquidWeightTileKeys(route: BodyMeasurementCorrection.route(for: .liquidTodayWeightTile,
                                                                    policy: h.provider.displayPolicy))
    }

    func testFlagOnTheSparklineKeyIsTheWeightSeriesAlthoughTheRouteIsNotACataloguePage() async throws {
        let h = try await harness(flag: true)
        let route = BodyMeasurementCorrection.route(for: .liquidTodayWeightTile, policy: h.provider.displayPolicy)
        XCTAssertEqual(route, .weighInSheet)
        XCTAssertNil(route.metricKey, "the route that took the sparkline away: it has no catalogue key")
        let keys = LiquidWeightTileKeys(route: route)
        XCTAssertNil(keys.navigationKey, "no catalogue page is pushed")
        XCTAssertEqual(keys.sparklineKey, "weight", "and the sparkline does not depend on that")
    }

    func testFlagOnTheSparklineIsTheProvidersUnifiedSeriesAndIsNotEmpty() async throws {
        let h = try await harness(flag: true)
        let (series, drawn) = await h.tileSparkline(keys(h))
        XCTAssertEqual(series.policy, .unified)
        XCTAssertEqual(series.points.map(\.day), [h.appleDay, h.labDay])
        XCTAssertEqual(drawn, series.points.map(\.value), "the tile draws the provider's unified series")
        XCTAssertEqual(drawn, [PolishHarness.appleWeight, PolishHarness.labWeight])
        XCTAssertGreaterThanOrEqual(drawn.count, 2, "two readings exist, so the tile has a line to draw")

        // The same series the tile's value comes from, in one reading (ruling R40).
        let display = await h.provider.displayWeight(days: 91, asOf: .day(h.labDay, isCurrent: true),
                                                     appleRows: await h.repo.appleDailyRows())
        XCTAssertEqual(drawn, display.sparkline.map(\.value))
        XCTAssertEqual(drawn.last, display.value.value, "the line ends on the number the tile prints")
    }

    func testFlagOnTheChosenWindowStillFiltersTheSeries() async throws {
        let h = try await harness(flag: true)
        let (_, week) = await h.tileSparkline(keys(h), windowDays: 7)
        XCTAssertEqual(week, [PolishHarness.labWeight], "the Apple Health point of ten days back is outside one week")
    }

    func testFlagOnWithNoReadingsTheSparklineIsEmpty() async throws {
        let h = try await harness(flag: true, readings: false)
        let (series, drawn) = await h.tileSparkline(keys(h))
        XCTAssertTrue(series.points.isEmpty)
        XCTAssertTrue(drawn.isEmpty, "no point is invented from the profile value")
    }

    func testFlagOffBothKeysAreTheOneKeyTheTilePassedBefore() async throws {
        let h = try await harness(flag: false)
        let route = BodyMeasurementCorrection.route(for: .liquidTodayWeightTile, policy: h.provider.displayPolicy)
        XCTAssertEqual(route, .metricDetail(key: "weight"))
        let keys = LiquidWeightTileKeys(route: route)
        XCTAssertEqual(keys.navigationKey, "weight")
        XCTAssertEqual(keys.sparklineKey, "weight")
        XCTAssertNotNil(MetricCatalog.all.first { $0.key == keys.navigationKey },
                        "the tile still pushes the catalogue page it pushed")
    }

    func testFlagOffTheSparklineIsTheLegacyAppleHealthSeries() async throws {
        let h = try await harness(flag: false)
        let (series, drawn) = await h.tileSparkline(keys(h))
        XCTAssertEqual(series.policy, .legacyDisplay)
        let legacy = await h.repo.series(key: "weight", source: "apple-health", days: 91)
        XCTAssertEqual(drawn, legacy.map(\.value), "the base commit's read")
        XCTAssertEqual(drawn, [PolishHarness.appleWeight], "the Lab Book weigh-in is not drawn")
    }

    func testEveryRouteKeepsTheSparklineKey() {
        let routes: [BodyMeasurementCorrectionRoute] = [.none, .metricDetail(key: "weight"), .weighInSheet,
                                                        .weighInHistory, .scorecard]
        for route in routes {
            let keys = LiquidWeightTileKeys(route: route)
            XCTAssertEqual(keys.sparklineKey, "weight", "\(route)")
            XCTAssertEqual(keys.navigationKey, route.metricKey, "\(route)")
        }
    }

    /// The view reads the pinned member, and no longer hands `ktile` the route's catalogue key as
    /// its one key.
    func testTheLiquidWeightTileReadsTheTwoKeys() throws {
        let code = PolishSource.codeLines(try PolishSource.text("Strand/Liquid/LiquidTodayView.swift"))
            .joined(separator: "\n")
        XCTAssertTrue(code.contains("LiquidWeightTileKeys(route:"),
                      "LiquidTodayView's weight tile must take its keys from LiquidWeightTileKeys(route:)")
        XCTAssertFalse(code.contains("key: correction.metricKey"),
                       "the route's catalogue key must not be the tile's sparkline key")
    }
}

// MARK: - Item 3. Scripted debug flows never reach a device

final class Stage1PolishDebugFlowScanTests: XCTestCase {
    private static let demoFile = "StrandiOS/Scorecard/ScorecardDemo.swift"
    private static let flowHost = "ScorecardFlowHost"

    /// The spellings that reach the app's own store, its standard defaults or the notification
    /// centre from the demo file. The synthetic frames use none of them: they run on an in-memory
    /// store and a defaults suite of their own.
    private static let liveHandles: [(name: String, pattern: String)] = [
        ("the flow host", #"\bScorecardFlowHost\b"#),
        ("the standard defaults", #"UserDefaults\.standard\b"#),
        ("the app's scorecard flag", #"CutScorecardFlag\.shared\b"#),
        ("the live scorecard context", #"ScorecardContext\.live\("#),
        ("the live body-measurement provider", #"BodyMeasurementProvider\.live\("#),
        ("the app's own store and profile", #"@EnvironmentObject\b"#),
        ("the notification centre", #"UNUserNotificationCenter\b"#),
        ("the app's document folder", #"\.documentDirectory\b"#),
    ]

    private func matches(_ pattern: String, _ line: String) -> Bool {
        line.range(of: pattern, options: .regularExpression) != nil
    }

    func testEveryLiveHandleInTheDemoFileIsSimulatorOnly() throws {
        let lines = PolishSource.codeLines(try PolishSource.text(Self.demoFile))
        let gated = PolishSource.simulatorOnly(lines)
        var offenders: [String] = []
        for (index, line) in lines.enumerated() where !gated[index] {
            for handle in Self.liveHandles where matches(handle.pattern, line) {
                offenders.append("\(Self.demoFile):\(index + 1): [\(handle.name)] \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertEqual(offenders, [],
                       "A debug build on a real phone must not be able to write to the owner's data. Put each of "
                       + "these inside #if targetEnvironment(simulator):\n" + offenders.joined(separator: "\n"))
    }

    func testTheFlowHostIsDeclaredOnceAndOnlyForTheSimulator() throws {
        let lines = PolishSource.codeLines(try PolishSource.text(Self.demoFile))
        let gated = PolishSource.simulatorOnly(lines)
        let declarations = lines.indices.filter { matches(#"\bstruct\s+ScorecardFlowHost\b"#, lines[$0]) }
        XCTAssertEqual(declarations.count, 1, "the scan below is about this one type")
        for index in declarations {
            XCTAssertTrue(gated[index], "\(Self.demoFile):\(index + 1): the flow host must not compile for a device")
        }
    }

    /// A device still recognises the name, so it can say that flows run on the simulator only
    /// rather than fall through to another screen.
    func testTheFlowRouteIsStillRecognisedOnADevice() throws {
        let lines = PolishSource.codeLines(try PolishSource.text(Self.demoFile))
        let gated = PolishSource.simulatorOnly(lines)
        let checks = lines.indices.filter { lines[$0].contains(#"hasPrefix("flow-")"#) }
        XCTAssertFalse(checks.isEmpty, "the flow- route is gone; this test and the two beside it need a new anchor")
        XCTAssertTrue(checks.contains { !gated[$0] },
                      "the flow- name must be matched outside the simulator condition, with only what it runs inside it")
    }

    func testNoOtherAppSourceNamesTheFlowHost() {
        var offenders: [String] = []
        let files = PolishSource.appSwiftFiles()
        XCTAssertTrue(files.contains(Self.demoFile), "the app sources are not reachable from the test sources")
        for file in files where file != Self.demoFile {
            guard let text = try? PolishSource.text(file) else { continue }
            for (index, line) in PolishSource.codeLines(text).enumerated() where matches(Self.liveHandles[0].pattern, line) {
                offenders.append("\(file):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertEqual(offenders, [], "the flow host is private to \(Self.demoFile):\n" + offenders.joined(separator: "\n"))
    }

    /// The conditional-compilation reader itself, on the shapes the repair can take.
    func testTheSimulatorConditionReaderFollowsEachBranch() {
        let lines = """
        #if DEBUG
        a
        #if targetEnvironment(simulator)
        b
        #else
        c
        #endif
        d
        #if !targetEnvironment(simulator)
        e
        #else
        f
        #endif
        #if DEBUG && targetEnvironment(simulator)
        g
        #if os(iOS)
        h
        #endif
        #elseif os(macOS)
        i
        #endif
        #if targetEnvironment(simulator) || DEBUG
        j
        #endif
        #endif
        """.components(separatedBy: "\n")
        let gated = PolishSource.simulatorOnly(lines)
        let byName = Dictionary(uniqueKeysWithValues: zip(lines, gated).filter { $0.0.count == 1 })
        XCTAssertEqual(byName.filter(\.value).keys.sorted(), ["b", "f", "g", "h"])
        XCTAssertEqual(byName.filter { !$0.value }.keys.sorted(), ["a", "c", "d", "e", "i", "j"])
        XCTAssertEqual(PolishSource.codeLines(#"let a = "x // y" // z"#), [#"let a = "x // y" "#])
    }
}

// MARK: - Item 5. The card editor's list and frame B3's verdict header

final class Stage1PolishCheckTests: XCTestCase {
    /// The redesign editor's "can be added" list, built as `TodayCustomizationSheet` builds it.
    private func addable(redesign: Bool, scorecardEnabled: Bool, raw: String = "") -> [DashboardCard] {
        let sections = EditableLayoutDraft(visible: TodayLayoutPrefs.decodeOrder(""), hidden: [])
        let available = TodayCardsEditorPresentation.availableCards(redesign: redesign,
                                                                    scorecardEnabled: scorecardEnabled)
        let shown = TodayCardsEditorPresentation.selection(raw: raw, redesign: redesign, sections: sections,
                                                           metrics: KeyMetricPrefs.decodeEnabled(""))
            .filter { available.contains($0) }
        return EditableLayoutDraft(visible: shown, allItems: available).hidden
    }

    func testFlagOnTheRedesignEditorOffersTheScorecardCard() {
        let offered = TodayCardsEditorPresentation.availableCards(redesign: true, scorecardEnabled: true)
        XCTAssertEqual(offered.filter { $0 == .scorecard }.count, 1)

        let list = addable(redesign: true, scorecardEnabled: true)
        XCTAssertEqual(list.filter { $0 == .scorecard }.count, 1,
                       "on a selection never edited the card is among the cards that can be added")
        XCTAssertFalse(DashboardCard.scorecard.title.isEmpty, "and it has a name to be listed under")
    }

    func testOnceAddedTheScorecardCardLeavesTheAddableList() {
        let raw = DashboardCardPrefs.encode([.scorecard, .hrv])
        XCTAssertFalse(addable(redesign: true, scorecardEnabled: true, raw: raw).contains(.scorecard))
    }

    func testFlagOffOrOutsideTheRedesignTheEditorDoesNotOfferIt() {
        XCTAssertFalse(addable(redesign: true, scorecardEnabled: false).contains(.scorecard))
        XCTAssertFalse(addable(redesign: false, scorecardEnabled: true).contains(.scorecard))
        XCTAssertFalse(addable(redesign: false, scorecardEnabled: false).contains(.scorecard))
    }

    // MARK: Frame B3

    private func present(_ input: CutScorecardInput) -> CutScorecardPresentation {
        let context = CutScorecardPresentationContext(unitSystem: .metric, weightSource: .labBook,
                                                      rulesNeedAttention: false, locale: Locale(identifier: "en_GB"))
        return CutScorecardPresenter.present(CutScorecard.evaluate(input), input: input, context: context)
    }

    /// Frame B3 as `scorecard.js` draws it: `Verdict` on the left and, because three signals are
    /// judged without a phase, the count on the right.
    func testFrameB3NoCutPhaseVerdictHeaderCarriesTheSignalCount() {
        let shown = present(ScorecardScreenFixture.input(today: "2031-01-29", phase: nil))
        XCTAssertEqual(shown.verdict.header, "Verdict", "no phase has started, so no week is named")
        XCTAssertEqual(shown.verdict.signalsSummary, "3 of 4 signals met")
        XCTAssertEqual(shown.verdict.title, "No cut phase is active")
        XCTAssertTrue(shown.verdict.isWithheld)
        XCTAssertEqual(shown.verdict.lines, [])
        XCTAssertEqual(shown.verdict.explanation,
                       "Verdicts are given during a cut phase. Your weigh-ins and curves are kept either way.")
        XCTAssertEqual(shown.verdict.action, .setUpPhase)

        // The frame's rule for the count, on this frame's own rows.
        XCTAssertEqual(shown.signals.count, 4)
        XCTAssertEqual(shown.signals.filter { $0.state == .met }.count, 3)
        XCTAssertEqual(shown.signals.filter { $0.state != .unknown }.count, 3)
        XCTAssertEqual(shown.signals.last?.reason, "No cut phase is active", "the rate band is the unknown one")
    }

    /// The other side of the frame's rule: with every signal unknown the header has no count.
    func testWithNoCutPhaseAndNoReadingsTheHeaderHasNoCount() {
        let shown = present(ScorecardScreenFixture.input(today: "2031-01-08", phase: nil, lifts: false,
                                                         without: Set(1...22)))
        XCTAssertEqual(shown.verdict.header, "Verdict")
        XCTAssertEqual(shown.signals.filter { $0.state != .unknown }.count, 0)
        XCTAssertNil(shown.verdict.signalsSummary)
    }
}
