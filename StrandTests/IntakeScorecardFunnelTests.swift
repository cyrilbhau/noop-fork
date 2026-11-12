// API ASSUMED BY THESE TESTS
//
// Stage 3 specification §9.4 and §12.3: the two methods the specification adds to
// CutScorecardInputBuilderTests.swift, written here as a new file so that no existing test changes.
// Written before the implementation exists.
//
//     CutScorecardInputBuilder.init(repository: Repository, provider: BodyMeasurementProvider,
//                                   settings: CutScorecardSettings, intake: IntakeProvider,
//                                   timeZone: @escaping () -> TimeZone = { TimeZone.current })   [spec §9.4]
//     CutScorecardInputBuilder.build(today:) and evaluation(today:) as they exist today.
//     IntakeProvider.proteinDays() -> [CutScorecardProteinDay]                                   [spec §9.4]
//     IntakeProvider and IntakeSettings as at the top of IntakeTestSupport.swift.
//
// Behaviour assumed: `build` refreshes the intake provider before reading it (§9.4: "takes
// `intake.proteinDays()` after `await intake.refresh()`"), so a row stored after the provider's
// last refresh is still seen.
//
// Synthetic values only.

import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

@MainActor
final class IntakeScorecardFunnelTests: XCTestCase {
    private let suites = IntakeSuites()
    private let utc = TimeZone(identifier: "UTC")!

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    private func builder(_ h: IntakeHarness) -> CutScorecardInputBuilder {
        let today = h.today
        let body = BodyMeasurementProvider(repository: h.repo, defaults: h.defaults, today: { today })
        let zone = utc
        return CutScorecardInputBuilder(repository: h.repo, provider: body, settings: h.scorecard, intake: h.provider,
                                        timeZone: { zone })
    }

    private func seedThreeSources(_ h: IntakeHarness) async throws {
        // Health on -3 and -1, quick-add on -2 and -1, the CSV on -4 and -1.
        try await h.seed(IntakeFixture.healthId, day: h.clock.day(-3), protein: 125, readAt: h.clock.epoch(-3, hour: 21))
        try await h.seed(IntakeFixture.healthId, day: h.clock.day(-1), protein: 120, readAt: h.clock.epoch(-1, hour: 21))
        try await h.seed(IntakeFixture.quickAddId, day: h.clock.day(-2), protein: 90, readAt: h.clock.epoch(-2, hour: 21))
        try await h.seed(IntakeFixture.quickAddId, day: h.clock.day(-1), protein: 80, readAt: h.clock.epoch(-1, hour: 21))
        try await h.seed(IntakeFixture.csvId, day: h.clock.day(-4), protein: 70)
        try await h.seed(IntakeFixture.csvId, day: h.clock.day(-1), protein: 60)
    }

    func testProteinDaysFollowTheIntakeResolverWhenTheFlagIsOn() async throws {
        let h = try await IntakeHarness.make(flag: true, source: .appleHealth, suites: suites)
        try await seedThreeSources(h)
        let input = await builder(h).build(today: h.today)
        XCTAssertEqual(input.proteinDays, [CutScorecardProteinDay(day: h.clock.day(-4), grams: 70),
                                           CutScorecardProteinDay(day: h.clock.day(-3), grams: 125),
                                           CutScorecardProteinDay(day: h.clock.day(-2), grams: 90),
                                           CutScorecardProteinDay(day: h.clock.day(-1), grams: 120)])
        XCTAssertEqual(input.proteinDays, h.provider.proteinDays(), "the provider's list, unchanged")

        // Off: the CSV series only, as before this stage.
        h.settings.isEnabled = false
        let legacy = await builder(h).build(today: h.today)
        XCTAssertEqual(legacy.proteinDays, [CutScorecardProteinDay(day: h.clock.day(-4), grams: 70),
                                            CutScorecardProteinDay(day: h.clock.day(-1), grams: 60)])
    }

    func testEvaluationCarriesTheResolvedProteinDays() async throws {
        let h = try await IntakeHarness.make(flag: true, source: .quickAdd, suites: suites)
        try await seedThreeSources(h)
        let evaluation = await builder(h).evaluation(today: h.today)
        XCTAssertEqual(evaluation.input.proteinDays.first { $0.day == h.clock.day(-1) }?.grams, 80,
                       "quick-add first under its own setting")
        XCTAssertEqual(evaluation.input.proteinDays.map(\.day), [h.clock.day(-4), h.clock.day(-3), h.clock.day(-2),
                                                                 h.clock.day(-1)])
        XCTAssertEqual(evaluation.input.proteinDays, h.provider.proteinDays())
    }

    func testProteinDaysHaveOneEntryPerDayWithAProteinValue() async throws {
        let h = try await IntakeHarness.make(flag: true, source: .appleHealth, suites: suites)
        // Energy alone on a day is not a protein day.
        try await h.seed(IntakeFixture.healthId, day: h.clock.day(-2), energy: 2_400, readAt: h.clock.epoch(-2, hour: 21))
        try await h.seed(IntakeFixture.healthId, day: h.clock.day(-1), protein: 0, readAt: h.clock.epoch(-1, hour: 21))
        await h.provider.refresh()
        XCTAssertEqual(h.provider.proteinDays(), [CutScorecardProteinDay(day: h.clock.day(-1), grams: 0)],
                       "a logged zero is a protein day; an energy-only day is not")
    }
}
