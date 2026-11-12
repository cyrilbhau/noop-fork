// The stage 6 finding of the independent C11 review, pinned by tests that failed on the defect
// before its fix (ruling A27).
//
// A screen left open across midnight kept yesterday's day: the niggle log's model resolved its list
// and detail against the day of its last load, so a complaint read "Day 3" after the calendar day
// had changed, and an owner's `fromDay` threshold stayed on yesterday's label. The same shape was in
// the timeline (its today marker) and the recovery context ("this week so far"). Each model now
// re-reads when the local calendar day or time zone changes, or the app returns to the foreground,
// once it has been loaded (that is, while a screen holds it). A model never loaded reads nothing.
//
// Synthetic values only: the stage 6 fixture (2031 days, 12:00 UTC) and, for the recovery context,
// dates relative to the real clock (stage 1 ruling R31).

import XCTest
import StrandAnalytics
import WhoopStore
@testable import Strand

@MainActor
final class CodexReviewStage6Tests: XCTestCase {
    private typealias Fx = Stage6Fixture
    private let suites = Stage6Suites()
    private let packetSuites = CoachPacketSuites()

    override func tearDown() {
        suites.removeAll()
        packetSuites.removeAll()
        super.tearDown()
    }

    private final class Clock {
        var date: Date
        init(_ date: Date) { self.date = date }
    }

    /// Waits for a reload the notification scheduled; fails after two seconds.
    private func eventually(_ what: String, file: StaticString = #filePath, line: UInt = #line,
                            _ condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("never: \(what)", file: file, line: line)
    }

    /// Gives a scheduled reload every chance to run, for the tests that expect none.
    private func drain() async {
        for _ in 0..<20 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    // MARK: Niggle log

    private func niggleModel(_ defaults: UserDefaults, clock: Clock, center: NotificationCenter) -> NiggleLogModel {
        NiggleLogModel(settings: NiggleLogSettings(defaults: defaults, today: { "2031-12-31" }),
                       now: { clock.date }, timeZone: { Fx.utc }, locale: { Fx.british },
                       notificationCenter: center)
    }

    private func openDayCount(_ model: NiggleLogModel) -> String? {
        guard case .loaded(let p) = model.state else { return nil }
        return p.open.first?.dayCountText
    }

    func testTheNiggleLogRollsOverWhenTheCalendarDayChangesWhileOpen() async throws {
        let defaults = try suites.make()
        Fx.seed(defaults, entries: [Fx.n2])
        defaults.set(true, forKey: NiggleLogSettings.enabledKey)
        let clock = Clock(Fx.noon("2031-03-21"))
        let center = NotificationCenter()
        let model = niggleModel(defaults, clock: clock, center: center)
        await model.load()
        XCTAssertEqual(openDayCount(model), "Day 19")
        XCTAssertEqual(model.detail(niggleId: Fx.n2.id)?.dayCountText, "Day 19")
        XCTAssertEqual(model.today, "2031-03-21")

        clock.date = Fx.noon("2031-03-22")
        center.post(name: .NSCalendarDayChanged, object: nil)
        await eventually("the detail takes the new day") { model.detail(niggleId: Fx.n2.id)?.dayCountText == "Day 20" }
        XCTAssertEqual(openDayCount(model), "Day 20", "the list takes the new day")
        XCTAssertEqual(model.today, "2031-03-22", "a new entry's default day is the new day")
    }

    func testTheNiggleLogRollsOverOnReturningToTheForeground() async throws {
        let defaults = try suites.make()
        Fx.seed(defaults, entries: [Fx.n2])
        defaults.set(true, forKey: NiggleLogSettings.enabledKey)
        let clock = Clock(Fx.noon("2031-03-21"))
        let center = NotificationCenter()
        let model = niggleModel(defaults, clock: clock, center: center)
        await model.load()
        XCTAssertEqual(model.detail(niggleId: Fx.n2.id)?.dayCountText, "Day 19")

        // Suspended over midnight: the day notification never arrived.
        clock.date = Fx.noon("2031-03-22")
        center.post(name: LocalDayChange.foregroundNotification, object: nil)
        await eventually("the detail takes the new day") { model.detail(niggleId: Fx.n2.id)?.dayCountText == "Day 20" }
        XCTAssertEqual(openDayCount(model), "Day 20")
    }

    func testTheNiggleLogRollsOverWhenTheTimeZoneChanges() async throws {
        let defaults = try suites.make()
        Fx.seed(defaults, entries: [Fx.n2])
        defaults.set(true, forKey: NiggleLogSettings.enabledKey)
        // 23:30 UTC on 21 March; a zone an hour ahead puts it on 22 March.
        let clock = Clock(Fx.noon("2031-03-21").addingTimeInterval(11.5 * 3_600))
        var zone = Fx.utc
        let center = NotificationCenter()
        let model = NiggleLogModel(settings: NiggleLogSettings(defaults: defaults, today: { "2031-12-31" }),
                                   now: { clock.date }, timeZone: { zone }, locale: { Fx.british },
                                   notificationCenter: center)
        await model.load()
        XCTAssertEqual(openDayCount(model), "Day 19")
        zone = TimeZone(secondsFromGMT: 3_600)!
        center.post(name: .NSSystemTimeZoneDidChange, object: nil)
        await eventually("the list takes the zone's day") { self.openDayCount(model) == "Day 20" }
    }

    func testANiggleModelNeverLoadedReadsNothingOnADayChange() async throws {
        let defaults = suites.recording()
        Fx.seed(defaults, entries: [Fx.n2])
        defaults.set(true, forKey: NiggleLogSettings.enabledKey)
        defaults.reads = []
        let center = NotificationCenter()
        let model = niggleModel(defaults, clock: Clock(Fx.noon("2031-03-21")), center: center)
        center.post(name: .NSCalendarDayChanged, object: nil)
        center.post(name: LocalDayChange.foregroundNotification, object: nil)
        await drain()
        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(defaults.reads.filter { Fx.listKeys.contains($0) }, [], "no list read before a screen loads it")
    }

    // MARK: Timeline

    func testTheTimelineMovesItsTodayMarkerWhenTheCalendarDayChangesWhileOpen() async throws {
        let h = try await CoachPacketHarness.empty(scorecard: false, suites: packetSuites)
        h.defaults.set(true, forKey: CheckpointTimelineSettings.enabledKey)
        h.defaults.set(Fx.storedCheckpoints(Fx.checkpoints), forKey: CheckpointTimelineSettings.checkpointsKey)
        let clock = Clock(Fx.noon("2031-02-05"))
        let center = NotificationCenter()
        let scorecard = CutScorecardModel(
            repository: h.repo, provider: h.provider, settings: h.scorecardSettings, unitSystem: { .metric },
            now: { clock.date }, timeZone: { Fx.utc }, locale: { Fx.british },
            evaluate: { day in
                let input = ScorecardScreenFixture.input(today: day)
                return (input: input, result: CutScorecard.evaluate(input))
            })
        let model = CheckpointTimelineModel(
            settings: CheckpointTimelineSettings(defaults: h.defaults), scorecardSettings: h.scorecardSettings,
            scorecard: scorecard, scans: TimelineScanSource(state: { .on }, scans: { [] }),
            events: TimelineEventSource(state: { .on }, events: { [] }), now: { clock.date }, timeZone: { Fx.utc },
            locale: { Fx.british }, unitSystem: { .metric }, notificationCenter: center)
        await model.load()
        XCTAssertEqual(model.today, "2031-02-05")
        let firstMarker = try XCTUnwrap(model.result?.todayIndex)

        clock.date = Fx.noon("2031-02-06")
        center.post(name: .NSCalendarDayChanged, object: nil)
        await eventually("the timeline takes the new day") { model.today == "2031-02-06" }
        XCTAssertNotNil(model.result?.todayIndex, "\(firstMarker): the marker is rebuilt for the new day")

        clock.date = Fx.noon("2031-02-07")
        center.post(name: LocalDayChange.foregroundNotification, object: nil)
        await eventually("the timeline takes the day on returning") { model.today == "2031-02-07" }
    }

    // MARK: Recovery context

    func testTheRecoveryContextTakesTheNewDayWhenTheCalendarDayChangesWhileOpen() async throws {
        let calendar = CoachPacketClock()
        let defaults = try suites.make()
        defaults.set(true, forKey: CutStressModel.enabledKey)
        defaults.set(true, forKey: CutScorecardSettings.enabledKey)
        let repo = Repository(deviceId: "codex-stage6-cut-stress")
        repo.days = (0..<20).map { i in
            DailyMetric(day: calendar.day(-19 + i), totalSleepMin: 420, efficiency: 0.9, deepMin: nil, remMin: nil,
                        lightMin: nil, disturbances: nil, restingHr: 55 + i % 5, avgHrv: 48 + Double(i % 7),
                        recovery: 60, strain: 9, exerciseCount: nil, sleepHrOnly: nil)
        }
        let clock = Clock(calendar.now)
        let center = NotificationCenter()
        let model = CutStressModel(repository: repo, scorecardSettings: CutScorecardSettings(defaults: defaults),
                                   defaults: defaults, now: { clock.date }, timeZone: { Fx.utc },
                                   locale: { Fx.british }, notificationCenter: center)
        await model.load()
        let first = try XCTUnwrap(model.input?.today)

        clock.date = calendar.now.addingTimeInterval(86_400)
        let next = LocalDayWindows(timeZone: Fx.utc).dayKey(for: clock.date)
        XCTAssertNotEqual(first, next)
        center.post(name: .NSCalendarDayChanged, object: nil)
        await eventually("the weeks are taken against the new day") { model.input?.today == next }

        clock.date = calendar.now.addingTimeInterval(2 * 86_400)
        let after = LocalDayWindows(timeZone: Fx.utc).dayKey(for: clock.date)
        center.post(name: LocalDayChange.foregroundNotification, object: nil)
        await eventually("the weeks are taken against the day on returning") { model.input?.today == after }
    }
}
