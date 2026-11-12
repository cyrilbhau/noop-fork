// API ASSUMED BY THESE TESTS
//
// Written from docs/personal/superapp/specs/stage-6.md §8.3, §9.4, §10.1, §12.3 and §12.5 before the
// implementation exists. The full API block is at the top of Stage6TestSupport.swift. Existing API
// used unchanged: `ObservableDefaultsFlag` (its `key` and `isEnabled`), `CutScorecardModel`,
// `CutScorecardPresenter.present`, `CutScorecardPresentationContext`, `PersonalEventStore`,
// `BodyRecordSettings.enabledKey`, `Repository`, the stage 2 harness `CoachPacketHarness` and the
// stage 1 fixture `ScorecardScreenFixture`.
//
// Behaviour assumed where the specification leaves it unstated: as in the support file (a flag-off
// part reads its own flag key and no list key; the flag statics are `static let` and so one instance
// each). The scorecard link and the four routes are in the iPhone-only target, which the macOS test
// target does not compile: Tools/test_stage6_single_source.py asserts that each is guarded by its
// flag. Here the Health rows and every model are asserted.
//
// Synthetic values only.

import Combine
import XCTest
import StrandAnalytics
import WhoopStore
@testable import Strand

@MainActor
final class Stage6FlagOffTests: XCTestCase {

    private typealias Fx = Stage6Fixture
    private let suites = Stage6Suites()
    private let packetSuites = CoachPacketSuites()
    private var standardKeys: Stage6StandardKeys?

    override func tearDown() {
        standardKeys?.restore()
        standardKeys = nil
        suites.removeAll()
        packetSuites.removeAll()
        super.tearDown()
    }

    private final class Counter { var calls = 0 }

    private struct Parts {
        let niggle: NiggleLogModel
        let cutStress: CutStressModel
        let timeline: CheckpointTimelineModel
        let scanReads: Counter
        let eventReads: Counter
    }

    private func parts(_ defaults: UserDefaults) -> Parts {
        let repo = Repository(deviceId: "stage6-flag-off")
        repo.days = [DailyMetric(day: "2031-02-04", totalSleepMin: 420, efficiency: 0.9, deepMin: nil, remMin: nil,
                                 lightMin: nil, disturbances: nil, restingHr: 55, avgHrv: 50, recovery: 60, strain: 8,
                                 exerciseCount: nil, sleepHrOnly: nil)]
        let now = Fx.noon("2031-02-05")
        let scorecardSettings = CutScorecardSettings(defaults: defaults)
        let provider = BodyMeasurementProvider(repository: repo, defaults: defaults, today: { "2031-02-05" })
        let scorecard = CutScorecardModel(repository: repo, provider: provider, settings: scorecardSettings,
                                          unitSystem: { .metric }, now: { now }, timeZone: { Fx.utc },
                                          locale: { Fx.british },
                                          evaluate: { day in
                                              let input = ScorecardScreenFixture.input(today: day)
                                              return (input: input, result: CutScorecard.evaluate(input))
                                          })
        let scanReads = Counter()
        let eventReads = Counter()
        let timeline = CheckpointTimelineModel(
            settings: CheckpointTimelineSettings(defaults: defaults), scorecardSettings: scorecardSettings,
            scorecard: scorecard,
            scans: TimelineScanSource(state: { .on }, scans: { scanReads.calls += 1; return [] }),
            events: TimelineEventSource(state: { .on }, events: { eventReads.calls += 1; return Fx.events }),
            now: { now }, timeZone: { Fx.utc }, locale: { Fx.british }, unitSystem: { .metric })
        return Parts(
            niggle: NiggleLogModel(settings: NiggleLogSettings(defaults: defaults, today: { "2031-02-05" }),
                                   now: { now }, timeZone: { Fx.utc }, locale: { Fx.british }),
            cutStress: CutStressModel(repository: repo, scorecardSettings: scorecardSettings, defaults: defaults,
                                      now: { now }, timeZone: { Fx.utc }, locale: { Fx.british }),
            timeline: timeline, scanReads: scanReads, eventReads: eventReads)
    }

    private func loadAll(_ p: Parts) async {
        await p.niggle.load()
        await p.cutStress.load()
        await p.timeline.load()
    }

    // MARK: §12.5

    func testAllFlagsOffAddsNoHealthRowNoScorecardLinkAndNoRoute() async throws {
        let defaults = try suites.make()
        Fx.seed(defaults)
        defaults.set(true, forKey: CutScorecardSettings.enabledKey)
        let p = parts(defaults)
        await loadAll(p)
        XCTAssertEqual(p.niggle.state, .idle)
        XCTAssertEqual(p.cutStress.state, .idle)
        XCTAssertEqual(p.timeline.state, .idle)
        let niggles = NiggleLogSettings(defaults: defaults, today: { "2031-02-05" })
        let timeline = CheckpointTimelineSettings(defaults: defaults)
        XCTAssertNil(NiggleLogPresenter.healthRow(enabled: niggles.isEnabled, entries: [Fx.n2], today: "2031-03-22",
                                                  locale: Fx.british))
        XCTAssertNil(CheckpointTimelinePresenter.healthRow(enabled: timeline.isEnabled, result: Fx.build(today: "2031-02-05"),
                                                           locale: Fx.british))
        // And on: each row appears, so the off result above is the flag's doing.
        XCTAssertNotNil(NiggleLogPresenter.healthRow(enabled: true, entries: [Fx.n2], today: "2031-03-22", locale: Fx.british))
        XCTAssertNotNil(CheckpointTimelinePresenter.healthRow(enabled: true, result: Fx.build(today: "2031-02-05"),
                                                              locale: Fx.british))
    }

    func testAllFlagsOffReadsNoStage6Key() async throws {
        let defaults = suites.recording()
        Fx.seed(defaults)
        defaults.set(true, forKey: CutScorecardSettings.enabledKey)
        let p = parts(defaults)
        defaults.reads = []
        await loadAll(p)
        let listReads = defaults.reads.filter { Fx.listKeys.contains($0) }
        XCTAssertEqual(listReads, [], "a flag-off part read \(listReads)")
        XCTAssertEqual(p.scanReads.calls, 0)
        XCTAssertEqual(p.eventReads.calls, 0)
        XCTAssertNil(p.cutStress.result, "nothing computed")
        XCTAssertNil(p.timeline.result)
    }

    func testSwitchingAFlagOffDeletesNothing() async throws {
        let defaults = try suites.make()
        Fx.seed(defaults)
        defaults.set(true, forKey: CutScorecardSettings.enabledKey)
        CutScorecardSettings(defaults: defaults).phases = Fx.phases
        for key in Fx.enabledKeys { defaults.set(true, forKey: key) }
        let before = Stage6Text.raw(defaults)
        let p = parts(defaults)
        await loadAll(p)
        guard case .loaded = p.niggle.state, case .loaded = p.timeline.state, case .loaded = p.cutStress.state else {
            return XCTFail("every part loads with its flag on: \(p.niggle.state) \(p.timeline.state) \(p.cutStress.state)")
        }
        for key in Fx.enabledKeys { defaults.set(false, forKey: key) }
        await loadAll(p)
        XCTAssertEqual(p.niggle.state, .idle)
        XCTAssertEqual(p.cutStress.state, .idle)
        XCTAssertEqual(p.timeline.state, .idle)
        XCTAssertEqual(Stage6Text.raw(defaults), before, "switching off deletes nothing")
        for key in Fx.enabledKeys { XCTAssertEqual(defaults.object(forKey: key) as? Bool, false, key) }
    }

    func testCutScorecardModelPresentationIsUnchangedByTheNewProperty() async throws {
        let h = try await CoachPacketHarness.empty(scorecard: true, suites: packetSuites)
        let now = Fx.noon("2031-02-05")
        let input = ScorecardScreenFixture.input(today: "2031-02-05")
        let result = CutScorecard.evaluate(input)
        let model = CutScorecardModel(repository: h.repo, provider: h.provider, settings: h.scorecardSettings,
                                      unitSystem: { .metric }, now: { now }, timeZone: { Fx.utc }, locale: { Fx.british },
                                      evaluate: { _ in (input: input, result: result) })
        XCTAssertNil(model.evaluation)
        await model.load()
        // The presentation is the one the base commit computes from the same evaluation and context.
        var context = CutScorecardPresentationContext(unitSystem: .metric, weightSource: .labBook, rulesNeedAttention: false,
                                                      locale: Fx.british, storedPhaseName: nil)
        context.events = PersonalEventStore.shared.events
        XCTAssertEqual(model.state, .loaded(CutScorecardPresenter.present(result, input: input, context: context)))
        XCTAssertEqual(model.evaluation?.input, input)
        XCTAssertEqual(model.evaluation?.result, result)

        // Reading the property publishes nothing and changes nothing.
        var changes = 0
        let watch = model.objectWillChange.sink { changes += 1 }
        let stateBefore = model.state
        for _ in 0..<3 { _ = model.evaluation }
        XCTAssertEqual(changes, 0)
        XCTAssertEqual(model.state, stateBefore)
        watch.cancel()

        h.defaults.set(false, forKey: CutScorecardSettings.enabledKey)
        await model.load()
        XCTAssertEqual(model.state, .idle)
        XCTAssertNil(model.evaluation, "cleared wherever the state becomes idle")
    }

    func testEachFlagIsOneObservableDefaultsFlagOverItsKey() {
        standardKeys = Stage6StandardKeys(Fx.enabledKeys)
        let flags: [(ObservableDefaultsFlag, String)] = [
            (NiggleLogSettings.flag, NiggleLogSettings.enabledKey),
            (CutStressModel.flag, CutStressModel.enabledKey),
            (CheckpointTimelineSettings.flag, CheckpointTimelineSettings.enabledKey),
        ]
        XCTAssertEqual(flags.map(\.1), Fx.enabledKeys)
        for (flag, key) in flags {
            XCTAssertEqual(flag.key, key)
            UserDefaults.standard.removeObject(forKey: key)
            XCTAssertFalse(flag.isEnabled, key)
            XCTAssertNil(UserDefaults.standard.object(forKey: key), "reading \(key) writes nothing")
            UserDefaults.standard.set(true, forKey: key)   // a writer other than the flag
            XCTAssertTrue(flag.isEnabled, "\(key) follows any writer")
            UserDefaults.standard.set(false, forKey: key)
            XCTAssertFalse(flag.isEnabled, key)
        }
        XCTAssertTrue(NiggleLogSettings.flag === NiggleLogSettings.flag, "one instance")
        XCTAssertFalse(NiggleLogSettings.flag === CheckpointTimelineSettings.flag)
        XCTAssertFalse(CutStressModel.flag === CheckpointTimelineSettings.flag)
        XCTAssertFalse(NiggleLogSettings.flag === CutStressModel.flag)
    }

    func testTimelineOffReadsNeitherTheBodyRecordNorTheEventsStore() async throws {
        let defaults = suites.recording()
        defaults.set(true, forKey: BodyRecordSettings.enabledKey)
        defaults.set(true, forKey: PersonalEventStore.enabledKey)
        defaults.set(Fx.storedCheckpoints(Fx.checkpoints), forKey: CheckpointTimelineSettings.checkpointsKey)
        let repo = Repository(deviceId: "stage6-flag-off-sources")
        repo.setStoreForTesting(try await WhoopStore.inMemory())
        let events = PersonalEventStore(defaults: defaults)
        let h = try await CoachPacketHarness.empty(scorecard: false, suites: packetSuites)
        let scorecard = CutScorecardModel(repository: h.repo, provider: h.provider, settings: h.scorecardSettings,
                                          unitSystem: { .metric })
        let model = CheckpointTimelineModel(
            settings: CheckpointTimelineSettings(defaults: defaults), scorecardSettings: h.scorecardSettings,
            scorecard: scorecard, scans: TimelineScanSource.live(repository: repo, defaults: defaults),
            events: TimelineEventSource.live(store: events), now: { Fx.noon("2031-02-05") }, timeZone: { Fx.utc },
            locale: { Fx.british }, unitSystem: { .metric })
        defaults.reads = []
        await model.load()
        XCTAssertEqual(model.state, .idle)
        for key in [BodyRecordSettings.enabledKey, PersonalEventStore.enabledKey, PersonalEventStore.itemsKey,
                    CheckpointTimelineSettings.checkpointsKey] {
            XCTAssertFalse(defaults.reads.contains(key), "\(key) was read with the timeline off")
        }
    }
}
