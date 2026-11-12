// API ASSUMED BY THESE TESTS
//
// Written from docs/personal/superapp/specs/stage-6.md §7.3, §8.1, §8.3, §8.4, §10.8 and §12.3
// before the implementation exists. The full API block (`CheckpointTimelineModel`,
// `CheckpointTimelinePresenter`, `CheckpointTimelineSettings`, `TimelineScanSource`,
// `TimelineEventSource`, and `CutScorecardModel.evaluation`) is at the top of
// Stage6TestSupport.swift. Existing API used unchanged: `CutScorecardModel(repository:provider:
// settings:unitSystem:now:timeZone:locale:intake:evaluate:)`, `CutScorecardInputBuilder.evaluation(today:)`,
// `CutScorecard.evaluate`, the stage 1 fixture `ScorecardScreenFixture.input(today:)` and the stage 2
// harness `CoachPacketHarness`.
//
// Behaviour assumed where the specification leaves it unstated:
//
//  1. `load()` awaits `scorecard.load()` once and reads `scorecard.evaluation?.result.projection`;
//     the model passes a projection only when the scorecard flag is on and an evaluation exists.
//  2. The pure input is assembled per assumption 1 of the support file: stored phases (none while
//     `phasesNeedAttention`), stored checkpoints, the scan source's days, the event source's events
//     through `TimelineEventSource.span`, the projection, the two source states and the model's day.
//  3. The loaded presentation is `CheckpointTimelinePresenter.present` over that result with the
//     same stored lists, `timelineEvents`, flags and unit system.
//  4. The timeline flag off: `.idle`, no source read, no stored list read, no scorecard load.
//
// The 2031 fixture is used where the scorecard's evaluation is injected (no repository read); the
// two single-resolver tests that run the scorecard's own funnel use dates relative to the real clock
// (stage 1 ruling R31). Synthetic values only.

import XCTest
import StrandAnalytics
import WhoopStore
@testable import Strand

@MainActor
final class CheckpointTimelineModelTests: XCTestCase {

    private typealias Fx = Stage6Fixture
    private let packetSuites = CoachPacketSuites()

    override func tearDown() {
        packetSuites.removeAll()
        super.tearDown()
    }

    private final class Counter { var calls = 0 }

    @MainActor
    private struct Setup {
        let h: CoachPacketHarness
        let scorecard: CutScorecardModel
        let evaluations: Counter
        let scanReads: Counter
        let eventReads: Counter
        let model: CheckpointTimelineModel
        var settings: CheckpointTimelineSettings { CheckpointTimelineSettings(defaults: h.defaults) }
    }

    /// A timeline over the 2031 fixture, "today" 2031-02-05 unless given, with the scorecard's
    /// evaluation injected from stage 1's fixture input.
    private func setup(today: String = "2031-02-05", timeline: Bool = true, scorecardOn: Bool = true,
                       scans: TimelineSourceState = .on, scanDays: [String] = Fx.scanDays,
                       events: TimelineSourceState = .on, eventList: [PersonalEvent] = Fx.events,
                       phases: [CutScorecardStoredPhase] = Fx.phases,
                       checkpoints: [StoredCheckpoint] = Fx.checkpoints) async throws -> Setup {
        let h = try await CoachPacketHarness.empty(scorecard: scorecardOn, suites: packetSuites)
        if timeline { h.defaults.set(true, forKey: CheckpointTimelineSettings.enabledKey) }
        h.scorecardSettings.phases = phases
        h.defaults.set(Fx.storedCheckpoints(checkpoints), forKey: CheckpointTimelineSettings.checkpointsKey)
        let now = Fx.noon(today)
        let evaluations = Counter()
        let scorecard = CutScorecardModel(
            repository: h.repo, provider: h.provider, settings: h.scorecardSettings, unitSystem: { .metric },
            now: { now }, timeZone: { Fx.utc }, locale: { Fx.british },
            evaluate: { day in
                evaluations.calls += 1
                let input = ScorecardScreenFixture.input(today: day)
                return (input: input, result: CutScorecard.evaluate(input))
            })
        let scanReads = Counter()
        let eventReads = Counter()
        let scanSource = scans == .notBuilt ? TimelineScanSource.notBuilt : TimelineScanSource(
            state: { scans },
            scans: { scanReads.calls += 1; return scanDays.enumerated().map { Fx.scan(day: $1, takenAt: 1_925_000_000 + $0) } })
        let eventSource = events == .notBuilt ? TimelineEventSource.notBuilt : TimelineEventSource(
            state: { events }, events: { eventReads.calls += 1; return eventList })
        let model = CheckpointTimelineModel(
            settings: CheckpointTimelineSettings(defaults: h.defaults), scorecardSettings: h.scorecardSettings,
            scorecard: scorecard, scans: scanSource, events: eventSource, now: { now }, timeZone: { Fx.utc },
            locale: { Fx.british }, unitSystem: { .metric })
        return Setup(h: h, scorecard: scorecard, evaluations: evaluations, scanReads: scanReads, eventReads: eventReads,
                     model: model)
    }

    private func loaded(_ s: Setup, file: StaticString = #filePath, line: UInt = #line) -> CheckpointTimelinePresentation? {
        guard case .loaded(let p) = s.model.state else {
            XCTFail("expected a loaded timeline, got \(s.model.state)", file: file, line: line)
            return nil
        }
        return p
    }

    private func expectedProjection(_ today: String) -> TimelineProjection {
        let projection = CutScorecard.evaluate(ScorecardScreenFixture.input(today: today)).projection
        return TimelineProjection(status: projection.status, targetDay: projection.targetDay)
    }

    // MARK: One list from stages 1, 4 and 5

    func testTheSingleListIsBuiltFromPhasesScansEventsAndTheProjection() async throws {
        let s = try await setup()
        await s.model.load()
        let expected = CheckpointTimeline.build(CheckpointTimelineInput(
            phases: Fx.timelinePhases(Fx.phases), checkpoints: Fx.timelineCheckpoints(Fx.checkpoints),
            scanDays: Fx.scanDays, spans: Fx.spans([Fx.e1, Fx.e3]), projection: expectedProjection("2031-02-05"),
            scans: .on, events: .on, today: "2031-02-05"))
        XCTAssertEqual(s.model.result, expected)
        XCTAssertEqual(s.model.timelineEvents, [Fx.e1, Fx.e3], "kept beside the spans")
        let p = try XCTUnwrap(loaded(s))
        XCTAssertEqual(p, CheckpointTimelinePresenter.present(
            expected, phases: Fx.phases, checkpoints: Fx.checkpoints, events: [Fx.e1, Fx.e3], scorecardEnabled: true,
            phasesNeedAttention: false, checkpointsNeedAttention: false, unitSystem: .metric, locale: Fx.british))
        XCTAssertEqual(p.rows.map(\.kind), expected.items.map(\.kind))
    }

    func testEachSourceMayBeEmpty() async throws {
        // No scans recorded.
        let noScans = try await setup(scanDays: [])
        await noScans.model.load()
        XCTAssertFalse(noScans.model.result?.items.contains { $0.kind == .scan } ?? true)
        XCTAssertEqual(noScans.model.result?.scans, .on)
        XCTAssertEqual(try XCTUnwrap(loaded(noScans)).footnotes, [], "an empty source on is not a source off")

        // No events.
        let noEvents = try await setup(eventList: [])
        await noEvents.model.load()
        XCTAssertFalse(noEvents.model.result?.items.contains { $0.kind == .deload || $0.kind == .dietBreak } ?? true)
        XCTAssertEqual(noEvents.model.timelineEvents, [])

        // No phases: no phase items, and the target date stands without one.
        let noPhases = try await setup(phases: [])
        await noPhases.model.load()
        XCTAssertFalse(noPhases.model.result?.items.contains { $0.kind == .phaseStart } ?? true)
        let target = noPhases.model.result?.items.first { $0.category == .targetDate }
        XCTAssertNotNil(target)
        XCTAssertNil(target?.phaseIndex)

        // No checkpoints.
        let noCheckpoints = try await setup(checkpoints: [])
        await noCheckpoints.model.load()
        XCTAssertFalse(noCheckpoints.model.result?.items.contains { $0.kind == .checkpoint } ?? true)

        // Nothing at all but the scorecard off: only today.
        let nothing = try await setup(scorecardOn: false, scanDays: [], eventList: [], phases: [], checkpoints: [])
        await nothing.model.load()
        XCTAssertEqual(nothing.model.result?.items.map(\.kind), [.today])
        XCTAssertEqual(try XCTUnwrap(loaded(nothing)).emptyText, "Nothing on your timeline yet")
    }

    func testPhaseItemsEqualStoredPhases() async throws {
        let s = try await setup()
        await s.model.load()
        let phaseItems = s.model.result?.items.filter { $0.kind == .phaseStart } ?? []
        XCTAssertEqual(phaseItems.map(\.day), s.h.scorecardSettings.phases.map(\.startDay))
        XCTAssertEqual(phaseItems.map(\.sourceIndex), [0, 1])
        XCTAssertEqual(phaseItems.map(\.targetWeightKg), s.h.scorecardSettings.phases.map(\.targetWeightKg))
        XCTAssertEqual(phaseItems.map(\.phaseIsCut), [true, false])
    }

    func testPhasesNeedAttentionShowsNoPhaseItems() async throws {
        let s = try await setup()
        s.h.defaults.set("not json", forKey: CutScorecardSettings.phasesKey)
        XCTAssertTrue(s.h.scorecardSettings.phasesNeedAttention)
        await s.model.load()
        XCTAssertFalse(s.model.result?.items.contains { $0.kind == .phaseStart } ?? true)
        let p = try XCTUnwrap(loaded(s))
        XCTAssertEqual(p.footnotes.count, 1)
    }

    // MARK: §8.3 the scorecard's one evaluation

    func testTimelineNeverEvaluatesTheScorecardItself() async throws {
        let s = try await setup()
        await s.model.load()
        XCTAssertEqual(s.evaluations.calls, 1, "one evaluation, the scorecard model's own")
        await s.model.load()
        XCTAssertEqual(s.evaluations.calls, 2, "one per load")
        XCTAssertEqual(s.model.result?.items.first { $0.kind == .projection }?.day,
                       s.scorecard.evaluation?.result.projection.targetDay)
    }

    func testProjectionDayEqualsTheScorecardModelsProjectionDay() async throws {
        let h = try await CoachPacketHarness.fixturePerson(scorecard: true, suites: packetSuites)
        h.defaults.set(true, forKey: CheckpointTimelineSettings.enabledKey)
        let now = h.clock.now
        let scorecard = CutScorecardModel(repository: h.repo, provider: h.provider, settings: h.scorecardSettings,
                                          unitSystem: { .metric }, now: { now }, timeZone: { CoachPacketHarness.utc },
                                          locale: { Fx.british },
                                          intake: IntakeProvider(repository: h.repo, settings: IntakeSettings(defaults: h.defaults)))
        let model = CheckpointTimelineModel(settings: CheckpointTimelineSettings(defaults: h.defaults),
                                            scorecardSettings: h.scorecardSettings, scorecard: scorecard,
                                            scans: .notBuilt, events: .notBuilt, now: { now },
                                            timeZone: { CoachPacketHarness.utc }, locale: { Fx.british },
                                            unitSystem: { .metric })
        await model.load()
        let projection = try XCTUnwrap(scorecard.evaluation?.result.projection, "the shared model was loaded")
        let item = model.result?.items.first { $0.kind == .projection }
        if projection.status == .projected {
            XCTAssertEqual(item?.day, projection.targetDay, "one projection day across the app")
        } else {
            XCTAssertNil(item, "status \(projection.status): no projection item")
        }
    }

    func testModelEvaluationIsTheValueTheBuilderFunnelReturned() async throws {
        let h = try await CoachPacketHarness.fixturePerson(scorecard: true, suites: packetSuites)
        let now = h.clock.now
        let intake = IntakeProvider(repository: h.repo, settings: IntakeSettings(defaults: h.defaults))
        let scorecard = CutScorecardModel(repository: h.repo, provider: h.provider, settings: h.scorecardSettings,
                                          unitSystem: { .metric }, now: { now }, timeZone: { CoachPacketHarness.utc },
                                          locale: { Fx.british }, intake: intake)
        XCTAssertNil(scorecard.evaluation, "nil before the first result")
        await scorecard.load()
        let funnel = await CutScorecardInputBuilder(repository: h.repo, provider: h.provider, settings: h.scorecardSettings,
                                                    intake: intake, timeZone: { CoachPacketHarness.utc })
            .evaluation(today: h.today)
        let stored = try XCTUnwrap(scorecard.evaluation)
        XCTAssertEqual(stored.input, funnel.input)
        XCTAssertEqual(stored.result, funnel.result)

        h.defaults.set(false, forKey: CutScorecardSettings.enabledKey)
        await scorecard.load()
        XCTAssertEqual(scorecard.state, .idle)
        XCTAssertNil(scorecard.evaluation, "nil while idle")
    }

    func testModelEvaluationIsTheInjectedEvaluatorsValue() async throws {
        let s = try await setup()
        await s.scorecard.load()
        let expected = CutScorecard.evaluate(ScorecardScreenFixture.input(today: "2031-02-05"))
        XCTAssertEqual(s.scorecard.evaluation?.result, expected)
        XCTAssertEqual(s.evaluations.calls, 1)
    }

    // MARK: Rows that follow the stored values

    func testTargetDateRowShowsThePhasesStoredTargetWeight() async throws {
        let s = try await setup()
        let checkpointsBefore = s.h.defaults.string(forKey: CheckpointTimelineSettings.checkpointsKey)
        await s.model.load()
        let first = try XCTUnwrap(loaded(s)).rows.first { $0.kind == .checkpoint && $0.day == "2031-06-02" }
        let weight = { (kg: Double) in CutScorecardPresenter.Wording(unitSystem: .metric, locale: Fx.british).weight(kg) }
        XCTAssertTrue(first?.details.contains("Target \(weight(94))") == true, "\(String(describing: first))")

        var changed = Fx.p0
        changed.targetWeightKg = 95.5
        s.h.scorecardSettings.phases = [changed, Fx.p1]
        await s.model.load()
        let second = try XCTUnwrap(loaded(s)).rows.first { $0.kind == .checkpoint && $0.day == "2031-06-02" }
        XCTAssertTrue(second?.details.contains("Target \(weight(95.5))") == true, "\(String(describing: second))")
        XCTAssertEqual(s.h.defaults.string(forKey: CheckpointTimelineSettings.checkpointsKey), checkpointsBefore,
                       "no checkpoint was rewritten")
    }

    func testWaypointPastTheTargetShowsTheRowWithoutWeightAndOneFootnote() async throws {
        var overtaken = Fx.p0
        overtaken.targetWeightKg = 96.0
        let s = try await setup(phases: [overtaken, Fx.p1])
        await s.model.load()
        XCTAssertEqual(s.model.result?.rejections.waypointBeyondTarget, 1)
        let p = try XCTUnwrap(loaded(s))
        XCTAssertEqual(p.footnotes.filter { $0.text == "A waypoint at or past your target weight is not shown" }.count, 1)
        XCTAssertEqual(CheckpointTimelineSettings(defaults: s.h.defaults).checkpoints.first { $0.id == Fx.c1.id }?
            .waypointWeightKg, 96.0, "the stored weight is kept")
    }

    // MARK: Privacy

    func testPrivateEventLeavesNoRowNoFootnoteAndNoCount() async throws {
        let withPrivate = try await setup(today: "2031-04-10", eventList: Fx.events)
        await withPrivate.model.load()
        let without = try await setup(today: "2031-04-10", eventList: Fx.events.filter { !$0.sensitive })
        await without.model.load()
        XCTAssertEqual(withPrivate.model.result, without.model.result, "the private deload changes nothing")
        XCTAssertEqual(withPrivate.model.state, without.model.state)
        let p = try XCTUnwrap(loaded(withPrivate))
        XCTAssertEqual(p.rows.filter { $0.kind == .deload }.map(\.day), ["2031-02-17"])
        XCTAssertFalse(p.rows.contains { $0.day == "2031-04-07" })
        XCTAssertEqual(p.footnotes, [])
        XCTAssertFalse(Stage6Text.joined(p).contains("Private"))
        XCTAssertFalse(Stage6Text.joined(p).contains("Fixture note"))
        XCTAssertFalse(Stage6Text.joined(p).contains("Fixture trip"))
        XCTAssertFalse(withPrivate.model.timelineEvents.contains { $0.sensitive })
    }

    // MARK: Sources and flags

    func testSpanAndScanRowsOpenTheirStagesScreens() async throws {
        let s = try await setup()
        await s.model.load()
        let p = try XCTUnwrap(loaded(s))
        XCTAssertEqual(p.rows.first { $0.kind == .scan }?.destination, .bodyRecord)
        XCTAssertEqual(p.rows.first { $0.kind == .deload }?.destination, .personalEvents(eventId: Fx.e1.id))
        XCTAssertEqual(p.rows.first { $0.kind == .dietBreak }?.destination, .personalEvents(eventId: Fx.e3.id))
    }

    func testSourcesOffAreNotReadAndAreFootnoted() async throws {
        let s = try await setup(scans: .off, events: .off)
        await s.model.load()
        XCTAssertEqual(s.scanReads.calls, 0)
        XCTAssertEqual(s.eventReads.calls, 0)
        XCTAssertEqual(s.model.result?.scans, .off)
        XCTAssertEqual(s.model.result?.events, .off)
        let p = try XCTUnwrap(loaded(s))
        XCTAssertEqual(Set(p.footnotes.map(\.text)), ["Scans are not shown while the body record is off",
                                                      "Breaks and deloads are not shown while events are off"])
    }

    func testSourcesNotBuiltAreSilent() async throws {
        let s = try await setup(scans: .notBuilt, events: .notBuilt)
        await s.model.load()
        XCTAssertEqual(s.model.result?.scans, .notBuilt)
        XCTAssertEqual(s.model.result?.events, .notBuilt)
        XCTAssertEqual(try XCTUnwrap(loaded(s)).footnotes, [])
    }

    func testSourcesOnAreReadOncePerLoad() async throws {
        let s = try await setup()
        await s.model.load()
        XCTAssertEqual(s.scanReads.calls, 1)
        XCTAssertEqual(s.eventReads.calls, 1)
    }

    func testScorecardFlagOffKeepsPhasesAndDropsTheEstimate() async throws {
        let s = try await setup(scorecardOn: false)
        await s.model.load()
        XCTAssertEqual(s.model.result?.items.filter { $0.kind == .phaseStart }.count, 2)
        XCTAssertFalse(s.model.result?.items.contains { $0.kind == .projection } ?? true)
        XCTAssertEqual(s.evaluations.calls, 0, "an idle scorecard evaluates nothing")
        XCTAssertEqual(try XCTUnwrap(loaded(s)).footnotes.map(\.text), ["No estimate while the scorecard is off"])
    }

    func testTimelineFlagOffIsIdleAndReadsNothing() async throws {
        let s = try await setup(timeline: false)
        await s.model.load()
        XCTAssertEqual(s.model.state, .idle)
        XCTAssertNil(s.model.result)
        XCTAssertEqual(s.scanReads.calls, 0)
        XCTAssertEqual(s.eventReads.calls, 0)
        XCTAssertEqual(s.evaluations.calls, 0)
    }

    func testTodayIsCapturedOncePerLoad() async throws {
        let s = try await setup()
        var reads = 0
        let model = CheckpointTimelineModel(
            settings: s.settings, scorecardSettings: s.h.scorecardSettings, scorecard: s.scorecard,
            scans: .notBuilt, events: .notBuilt,
            now: { reads += 1; return Fx.noon("2031-02-05") }, timeZone: { Fx.utc }, locale: { Fx.british },
            unitSystem: { .metric })
        await model.load()
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(model.result?.items.first { $0.kind == .today }?.day, "2031-02-05")
    }

    func testHealthRowReadsTheBuiltList() async throws {
        let s = try await setup()
        await s.model.load()
        let row = CheckpointTimelinePresenter.healthRow(enabled: true, result: s.model.result, locale: Fx.british)
        XCTAssertTrue(row?.detail?.hasPrefix("Next: ") == true)
        XCTAssertNil(CheckpointTimelinePresenter.healthRow(enabled: true, result: nil, locale: Fx.british)?.detail)
    }
}
