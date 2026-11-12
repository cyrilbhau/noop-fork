// API ASSUMED BY THESE TESTS
//
// Stage 3 specification §4.2, §7.4, §9.4, §12.3 (`IntakeSingleSourceTests.swift`, the behavioural
// single-resolver assertion; stage 1 ruling R41, one number per variable). Written before the
// implementation exists.
//
//     CutScorecardInputBuilder.init(repository: Repository, provider: BodyMeasurementProvider,
//                                   settings: CutScorecardSettings, intake: IntakeProvider,
//                                   timeZone: @escaping () -> TimeZone = { TimeZone.current })   [spec §9.4]
//     CutScorecardInputBuilder.evaluation(today:) as it exists today (stage 2).
//     IntakeProvider, IntakeSettings: as at the top of IntakeTestSupport.swift.
//     IntakePresenterInput.gather(provider:settings:day:), IntakePresenter.card / .screen,
//     IntakeClock: as at the top of IntakePresenterTests.swift.
//     IntakePresenter.widgetReading(_:clock:flagEnabled:): as at the top of IntakeWidgetPayloadTests.swift.
//     CutScorecardSettings.proteinFloorWholeGrams: stage 1 R45 (work package 1-10).
//
// `BodyMeasurementProvider` and `LabMarkerRow` are used as they exist today. A weigh-in on "today"
// anchors the scorecard's protein window on the seven days before it (CutScorecard.swift:704).
//
// Synthetic values only: the §13.6 three-source day and stage 1's floor.

import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

@MainActor
final class IntakeSingleSourceTests: XCTestCase {
    private let suites = IntakeSuites()
    private let utc = TimeZone(identifier: "UTC")!
    private let gb = Locale(identifier: "en_GB")

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    /// The harness plus a weigh-in today and the scorecard builder over the intake provider.
    private func make(flag: Bool = true, source: IntakeSourceSetting = .appleHealth,
                      floor: Double? = 100) async throws -> (IntakeHarness, CutScorecardInputBuilder) {
        let h = try await IntakeHarness.make(flag: flag, source: source, floor: floor, suites: suites)
        let takenAt = h.clock.epoch(0, hour: 7)
        try await h.store.upsertLabMarkers([
            LabMarkerRow(id: "weight-\(takenAt)-0A1B2C3D", deviceId: IntakeFixture.strapId, markerKey: "weight",
                         category: "bodyMeasurement", day: h.today, takenAt: takenAt, value: 97.1, valueText: nil,
                         unit: "kg", source: "manual", note: nil, referenceText: nil)])
        let today = h.today
        let body = BodyMeasurementProvider(repository: h.repo, defaults: h.defaults, today: { today })
        await body.refresh()
        let zone = utc
        let builder = CutScorecardInputBuilder(repository: h.repo, provider: body, settings: h.scorecard,
                                               intake: h.provider, timeZone: { zone })
        return (h, builder)
    }

    private func clock(_ h: IntakeHarness) -> IntakeClock {
        IntakeClock(now: h.clock.now, today: h.today, minuteOfDay: 920, dayIsOpen: true)
    }

    /// The four readouts of one day's protein: card, screen, widget, scorecard.
    private func readouts(_ h: IntakeHarness, _ builder: CutScorecardInputBuilder,
                          day: String) async -> (card: String?, screen: String?, widget: Int?, scorecard: Double?) {
        await h.provider.refresh()
        let input = IntakePresenterInput.gather(provider: h.provider, settings: h.settings, day: day)
        let card = IntakePresenter.card(input, clock: clock(h), timeZone: utc, locale: gb)
        let screen = IntakePresenter.screen(input, clock: clock(h), timeZone: utc, locale: gb)
        let widget = IntakePresenter.widgetReading(input, clock: clock(h), flagEnabled: h.settings.isEnabled)
        let evaluation = await builder.evaluation(today: h.today)
        let scorecard = evaluation.input.proteinDays.first { $0.day == day }?.grams
        return (card.value, screen.protein?.value, widget?.proteinGrams, scorecard)
    }

    func testCardScreenWidgetAndScorecardShareOneProteinNumber() async throws {
        let (h, builder) = try await make()
        let day = h.clock.day(-1)
        try await h.seed(IntakeFixture.healthId, day: day, protein: 120, readAt: h.clock.epoch(-1, hour: 21))
        try await h.seed(IntakeFixture.quickAddId, day: day, protein: 80, readAt: h.clock.epoch(-1, hour: 20))
        try await h.seed(IntakeFixture.csvId, day: day, protein: 60)

        let first = await readouts(h, builder, day: day)
        XCTAssertEqual(first.card, "120")
        XCTAssertEqual(first.screen, "120")
        XCTAssertEqual(first.widget, 120)
        XCTAssertEqual(first.scorecard, 120, "the scorecard reads the same resolved list, never the store")

        // The Health rows go: all four move to the quick-add figure together.
        for key in IntakeFixture.intakeKeys {
            _ = try await h.store.deleteMetricSeriesPoint(deviceId: IntakeFixture.healthId, day: day, key: key)
        }
        let second = await readouts(h, builder, day: day)
        XCTAssertEqual(second.card, "80")
        XCTAssertEqual(second.screen, "80")
        XCTAssertEqual(second.widget, 80)
        XCTAssertEqual(second.scorecard, 80)

        // And to the CSV figure when quick-add goes too; the widget never shows a CSV value.
        for key in IntakeFixture.intakeKeys {
            _ = try await h.store.deleteMetricSeriesPoint(deviceId: IntakeFixture.quickAddId, day: day, key: key)
        }
        let third = await readouts(h, builder, day: day)
        XCTAssertEqual(third.card, "60")
        XCTAssertEqual(third.screen, "60")
        XCTAssertNil(third.widget)
        XCTAssertEqual(third.scorecard, 60)
    }

    func testTheActiveSourceDecidesForEveryReadout() async throws {
        let (h, builder) = try await make(source: .quickAdd)
        let day = h.clock.day(-1)
        try await h.seed(IntakeFixture.healthId, day: day, protein: 120, readAt: h.clock.epoch(-1, hour: 21))
        try await h.seed(IntakeFixture.quickAddId, day: day, protein: 80, readAt: h.clock.epoch(-1, hour: 20))
        let shown = await readouts(h, builder, day: day)
        XCTAssertEqual(shown.card, "80")
        XCTAssertEqual(shown.screen, "80")
        XCTAssertEqual(shown.widget, 80)
        XCTAssertEqual(shown.scorecard, 80)
    }

    func testFlagOffTheScorecardReadsTheCsvSeriesAsBefore() async throws {
        let (h, builder) = try await make(flag: false)
        let day = h.clock.day(-1)
        try await h.seed(IntakeFixture.healthId, day: day, protein: 120, readAt: h.clock.epoch(-1, hour: 21))
        try await h.seed(IntakeFixture.quickAddId, day: day, protein: 80, readAt: h.clock.epoch(-1, hour: 20))
        try await h.seed(IntakeFixture.csvId, day: day, protein: 60)
        try await h.seed(IntakeFixture.csvId, day: h.clock.day(-3), protein: 110)
        let evaluation = await builder.evaluation(today: h.today)
        XCTAssertEqual(evaluation.input.proteinDays,
                       [CutScorecardProteinDay(day: h.clock.day(-3), grams: 110), CutScorecardProteinDay(day: day, grams: 60)],
                       "legacy policy: the nutrition-csv series, value for value")
        let input = IntakePresenterInput.gather(provider: h.provider, settings: h.settings, day: day)
        XCTAssertNil(IntakePresenter.widgetReading(input, clock: clock(h), flagEnabled: false), "nothing is published")
    }

    func testFloorHasOneStoredCopy() async throws {
        let (h, _) = try await make(floor: nil)
        XCTAssertTrue(h.settings.setProteinFloorGrams(130))
        XCTAssertEqual(CutScorecardSettings(defaults: h.defaults).parameters.proteinFloorGrams, 130,
                       "set through the intake settings, read through the scorecard settings")
        var parameters = h.scorecard.parameters
        parameters.proteinFloorGrams = 140
        h.scorecard.parameters = parameters
        XCTAssertEqual(IntakeSettings(defaults: h.defaults).proteinFloorGrams, 140, "and the reverse")
        XCTAssertEqual(h.settings.targets(on: h.today).proteinFloorGrams, 140)
        XCTAssertTrue(h.settings.setTargets(IntakeFixture.targets))
        let raw = h.defaults.string(forKey: IntakeSettings.targetsKey) ?? ""
        XCTAssertFalse(raw.lowercased().contains("protein"), "intake.targets never holds a protein key: \(raw)")
        let holders = h.defaults.dictionaryRepresentation().filter { "\($0.value)".contains("proteinFloor") }.map(\.key)
        XCTAssertEqual(holders, [CutScorecardSettings.rulesKey], "one stored copy")
    }

    func testRingCompleteAndScorecardDayCountedAgree() async throws {
        let (h, builder) = try await make(source: .quickAdd)
        let grams = [99.9994, 99.9996, 100, 120, 80, 100.0004, 50]
        for (index, value) in grams.enumerated() {
            try await h.seed(IntakeFixture.quickAddId, day: h.clock.day(index - 7), protein: value,
                             readAt: h.clock.epoch(index - 7, hour: 21))
        }
        await h.provider.refresh()
        var complete = 0
        for offset in -7...(-1) {
            let input = IntakePresenterInput.gather(provider: h.provider, settings: h.settings, day: h.clock.day(offset))
            if IntakePresenter.card(input, clock: clock(h), timeZone: utc, locale: gb).ring == 1 { complete += 1 }
        }
        let evaluation = await builder.evaluation(today: h.today)
        XCTAssertEqual(evaluation.result.signals.protein.daysLogged, 7)
        XCTAssertEqual(evaluation.result.signals.protein.daysAtOrAboveFloor, complete,
                       "'the ring is complete' and 'this day counted' cannot disagree")
        XCTAssertEqual(complete, 4)
    }

    func testTheFixtureWeekReadsSixOfSeven() async throws {
        let (h, builder) = try await make(source: .quickAdd)
        for (index, value) in IntakeFixture.weekProtein.enumerated() {
            try await h.seed(IntakeFixture.quickAddId, day: h.clock.day(index - 7), protein: value,
                             readAt: h.clock.epoch(index - 7, hour: 21))
        }
        // Today in progress is never judged.
        try await h.seed(IntakeFixture.quickAddId, day: h.today, protein: 10, readAt: h.clock.epoch(0, hour: 9))
        let evaluation = await builder.evaluation(today: h.today)
        XCTAssertEqual(evaluation.result.signals.protein.daysAtOrAboveFloor, 6)
        XCTAssertEqual(evaluation.result.signals.protein.daysLogged, 7)
    }

    func testShownFloorIsTheScorecardsWholeGramFloor() async throws {
        let cases: [(String?, Int?)] = [(#"{"proteinFloorGrams":99.4,"v":1}"#, 99), (#"{"proteinFloorGrams":99.5,"v":1}"#, 100),
                                        (#"{"proteinFloorGrams":100,"v":1}"#, 100), (nil, nil)]
        for (raw, expected) in cases {
            let (h, _) = try await make(source: .quickAdd, floor: nil)
            if let raw { h.defaults.set(raw, forKey: CutScorecardSettings.rulesKey) }
            try await h.seed(IntakeFixture.quickAddId, day: h.today, protein: 95, readAt: h.clock.epoch(0, hour: 15, minute: 10))
            await h.provider.refresh()
            XCTAssertEqual(h.scorecard.proteinFloorWholeGrams, expected, raw ?? "no floor")
            let input = IntakePresenterInput.gather(provider: h.provider, settings: h.settings, day: h.today)
            let card = IntakePresenter.card(input, clock: clock(h), timeZone: utc, locale: gb)
            let screen = IntakePresenter.screen(input, clock: clock(h), timeZone: utc, locale: gb)
            let widget = IntakePresenter.widgetReading(input, clock: clock(h), flagEnabled: true)
            XCTAssertEqual(card.floorGrams, expected, "card, \(raw ?? "no floor")")
            XCTAssertEqual(screen.protein?.floorGrams, expected, "screen, \(raw ?? "no floor")")
            XCTAssertEqual(widget?.floorGrams, expected, "widget, \(raw ?? "no floor")")
            if let raw { XCTAssertEqual(h.defaults.string(forKey: CutScorecardSettings.rulesKey), raw, "never rewritten") }
        }
    }
}
