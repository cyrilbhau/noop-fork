// API ASSUMED BY THESE TESTS
//
// Written from docs/personal/superapp/specs/stage-6.md §4.1, §7.2, §8.2, §9.4, §10.7 and §12.3 before
// the implementation exists. The full API block (`CutStressModel`, `CutStressPresenter`) is at the top
// of Stage6TestSupport.swift. Existing API used unchanged: `Repository(deviceId:)`, `Repository.days`,
// `CutScorecardSettings`, `CanonicalDay`, `CutStressTrend.weekly`, and the stage 2 harness clock
// `CoachPacketClock`.
//
// Behaviour assumed where the specification leaves it unstated:
//
//  1. Nights are `Repository.days` in their published order, mapped as
//     `CutStressNight(day: d.day, restingHr: d.restingHr.map(Double.init), hrv: d.avgHrv)`.
//  2. "A cut phase has started" is `CutScorecardSettings.activePhase(on: today)` of kind `.cut`:
//     then `firstWeekStart` is that phase's Monday and `maxWeeks` 26. Otherwise `firstWeekStart` is
//     nil and `maxWeeks` 12. `minNightsPerWeek` is 4 (§15 Q9).
//  3. The loaded presentation is `CutStressPresenter.present` over the model's own result, with the
//     repository's `chargeBaselines` (nil for a fresh repository) and the same `firstWeekStart`.
//  4. The model publishes `.idle` while either its flag or the scorecard flag is off (support file,
//     assumption 6).
//
// Dates are relative to the real clock (stage 1 ruling R31), one day back, through `CoachPacketClock`.
// Synthetic values only.

import XCTest
import StrandAnalytics
import WhoopStore
@testable import Strand

@MainActor
final class CutStressModelTests: XCTestCase {

    private typealias Fx = Stage6Fixture
    private let suites = Stage6Suites()
    private let clock = CoachPacketClock()

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    private func day(rhr: Int?, hrv: Double?, _ offset: Int) -> DailyMetric {
        DailyMetric(day: clock.day(offset), totalSleepMin: 420, efficiency: 0.9, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: rhr, avgHrv: hrv, recovery: 60, strain: 9,
                    exerciseCount: nil, sleepHrOnly: nil)
    }

    /// Nights for the last `count` days ending `endOffset` days from today, with values that move.
    private func nights(count: Int, endOffset: Int = 0) -> [DailyMetric] {
        (0..<count).map { i in
            let offset = endOffset - (count - 1 - i)
            return day(rhr: 55 + i % 6, hrv: 48 + Double(i % 9), offset)
        }
    }

    private struct Setup {
        let repo: Repository
        let defaults: UserDefaults
        let scorecard: CutScorecardSettings
        let model: CutStressModel
    }

    private func setup(cutStress: Bool = true, scorecard: Bool = true, days: [DailyMetric]? = nil,
                       defaults given: UserDefaults? = nil) throws -> Setup {
        let defaults = try given ?? suites.make()
        if cutStress { defaults.set(true, forKey: CutStressModel.enabledKey) }
        if scorecard { defaults.set(true, forKey: CutScorecardSettings.enabledKey) }
        let repo = Repository(deviceId: "stage6-cut-stress")
        repo.days = days ?? nights(count: 40)
        let settings = CutScorecardSettings(defaults: defaults)
        let now = clock.now
        let model = CutStressModel(repository: repo, scorecardSettings: settings, defaults: defaults,
                                   now: { now }, timeZone: { Fx.utc }, locale: { Fx.british })
        return Setup(repo: repo, defaults: defaults, scorecard: settings, model: model)
    }

    private func cut(startOffset: Int, kind: CutScorecardStoredPhase.Kind = .cut) -> CutScorecardStoredPhase {
        CutScorecardStoredPhase(kind: kind, name: "Fixture cut", startDay: clock.day(startOffset), targetWeightKg: 94.0,
                                rateLowPercentPerWeek: 0.40, rateHighPercentPerWeek: 1.20)
    }

    // MARK: Flags

    func testFlagDefaultsToOff() throws {
        XCTAssertEqual(CutStressModel.enabledKey, "noop.cutStressEnabled")
        let s = try setup(cutStress: false)
        XCTAssertFalse(s.defaults.bool(forKey: CutStressModel.enabledKey))
    }

    func testFlagOffComputesNothing() async throws {
        let defaults = suites.recording()
        let s = try setup(cutStress: false, defaults: defaults)
        await s.model.load()
        XCTAssertEqual(s.model.state, .idle)
        XCTAssertNil(s.model.input)
        XCTAssertNil(s.model.result)
        XCTAssertFalse(defaults.reads.contains(CutScorecardSettings.phasesKey), "a flag-off load reads no phase")
    }

    func testScorecardFlagOffKeepsTheScreenUnreachable() async throws {
        let s = try setup(cutStress: true, scorecard: false)
        await s.model.load()
        XCTAssertEqual(s.model.state, .idle, "a restored route pops")
        XCTAssertNil(s.model.result)
    }

    // MARK: The one source

    func testNightsComeFromRepositoryDays() async throws {
        let days = nights(count: 40) + [day(rhr: nil, hrv: 51, 1)]
        let s = try setup(days: days)
        await s.model.load()
        let input = try XCTUnwrap(s.model.input)
        XCTAssertEqual(input.nights, days.map { CutStressNight(day: $0.day, restingHr: $0.restingHr.map(Double.init),
                                                               hrv: $0.avgHrv) })
        XCTAssertEqual(input.today, clock.today)
        XCTAssertEqual(input.minNightsPerWeek, 4)
        let result = try XCTUnwrap(s.model.result)
        XCTAssertEqual(result, CutStressTrend.weekly(input), "the model adds nothing to the pure function")
        XCTAssertEqual(result.rejections.future, 1, "a night after today is the pure function's to reject")
        XCTAssertEqual(s.model.state, .loaded(CutStressPresenter.present(
            result, restingHrBaseline: s.repo.chargeBaselines?.restingHR, hrvBaseline: s.repo.chargeBaselines?.hrv,
            firstWeekStart: input.firstWeekStart, locale: Fx.british)))

        // A changed night moves the week it belongs to.
        var changed = days
        changed[25] = day(rhr: 90, hrv: 20, -14)  // a night of a full past week
        s.repo.days = changed
        await s.model.load()
        XCTAssertNotEqual(s.model.result, result)
    }

    func testWeeksStartAtThePhaseWeekWhenACutPhaseHasStarted() async throws {
        let s = try setup()
        s.scorecard.phases = [cut(startOffset: -20)]
        await s.model.load()
        let input = try XCTUnwrap(s.model.input)
        XCTAssertEqual(input.firstWeekStart, CanonicalDay.weekStart(containing: clock.day(-20)))
        XCTAssertEqual(input.maxWeeks, 26)
        guard case .loaded(let p) = s.model.state else { return XCTFail("\(s.model.state)") }
        XCTAssertTrue(p.periodText.hasPrefix("Since "), p.periodText)
        XCTAssertEqual(s.model.result?.weeks.first?.weekStart, input.firstWeekStart)
    }

    func testLastTwelveWeeksWithoutAPhase() async throws {
        for phases in [[], [cut(startOffset: 7)], [cut(startOffset: -20, kind: .other)]] {
            let s = try setup(days: nights(count: 120))
            s.scorecard.phases = phases
            await s.model.load()
            let input = try XCTUnwrap(s.model.input)
            XCTAssertNil(input.firstWeekStart, "\(phases)")
            XCTAssertEqual(input.maxWeeks, 12)
            XCTAssertLessThanOrEqual(s.model.result?.weeks.count ?? 99, 12)
            XCTAssertEqual(s.model.result?.weeks.count, 12, "120 nights reach back past twelve weeks")
            guard case .loaded(let p) = s.model.state else { return XCTFail("\(s.model.state)") }
            XCTAssertEqual(p.periodText, "Last 12 weeks")
        }
    }

    func testWeekBelowMinimumIsNotMeasuredNeverZero() async throws {
        // Nights stop eleven days ago: the last weeks have too few nights or none.
        let s = try setup(days: nights(count: 30, endOffset: -11))
        await s.model.load()
        guard case .loaded(let p) = s.model.state else { return XCTFail("\(s.model.state)") }
        XCTAssertNil(p.restingHr.points.last ?? nil, "the current week has no mean")
        XCTAssertFalse(p.restingHr.points.contains(0))
        XCTAssertFalse(p.hrv.points.contains(0))
        XCTAssertTrue(p.restingHr.points.contains { $0 != nil }, "stored nights still show")
    }

    func testTypicalRangeIsCalibratingWithoutAUsableBaseline() async throws {
        let s = try setup()
        XCTAssertNil(s.repo.chargeBaselines, "a fresh repository has resolved no baseline")
        await s.model.load()
        guard case .loaded(let p) = s.model.state else { return XCTFail("\(s.model.state)") }
        XCTAssertNil(p.restingHr.typicalRange)
        XCTAssertTrue(p.restingHr.lines.contains("Typical range: still calibrating"))
    }

    func testLoadingWritesNothing() async throws {
        let defaults = suites.recording()
        let s = try setup(defaults: defaults)
        s.scorecard.phases = [cut(startOffset: -20)]
        defaults.writes = []
        await s.model.load()
        XCTAssertEqual(defaults.writes, [])
    }
}
