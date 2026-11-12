// Regression tests for the confirmed stage 6 review findings (stage-6.md §8.3, §9.1, §9.2, §10.2,
// §10.7 and §10.8). Each test fails on the code before its fix. Synthetic values only; the 2031
// fixture of Stage6TestSupport.swift, and the stage 1 scorecard fixture where an evaluation is
// injected (no repository read, so ruling R31 does not apply).

import XCTest
import StrandAnalytics
import WhoopStore
@testable import Strand

@MainActor
final class Stage6ReviewFixTests: XCTestCase {

    private typealias Fx = Stage6Fixture
    private let suites = Stage6Suites()
    private let packetSuites = CoachPacketSuites()

    override func tearDown() {
        suites.removeAll()
        packetSuites.removeAll()
        super.tearDown()
    }

    // MARK: Finding 1: "Discard unreadable data" removes only the list whose card was tapped

    private func unreadableLog() throws -> (UserDefaults, NiggleLogModel) {
        let defaults = try suites.make()
        defaults.set(true, forKey: NiggleLogSettings.enabledKey)
        defaults.set("not json entries", forKey: NiggleLogSettings.entriesKey)
        defaults.set("not json rules", forKey: NiggleLogSettings.rulesKey)
        defaults.set("not json paused", forKey: NiggleLogSettings.pausedKey)
        let model = NiggleLogModel(settings: NiggleLogSettings(defaults: defaults, today: { "2031-03-22" }),
                                   now: { Fx.noon("2031-03-22") }, timeZone: { Fx.utc }, locale: { Fx.british })
        return (defaults, model)
    }

    private func assertKept(_ defaults: UserDefaults, _ keys: [String: String],
                            file: StaticString = #filePath, line: UInt = #line) {
        for (key, raw) in keys {
            XCTAssertEqual(defaults.string(forKey: key), raw, "\(key) was not chosen and must be kept",
                           file: file, line: line)
        }
    }

    func testDiscardingUnreadableRulesKeepsTheOtherUnreadableLists() async throws {
        let (defaults, model) = try unreadableLog()
        await model.discardUnreadableRules()
        XCTAssertNil(defaults.object(forKey: NiggleLogSettings.rulesKey))
        XCTAssertFalse(model.settings.rulesNeedAttention)
        assertKept(defaults, [NiggleLogSettings.entriesKey: "not json entries",
                              NiggleLogSettings.pausedKey: "not json paused"])
        XCTAssertTrue(model.settings.entriesNeedAttention)
        XCTAssertTrue(model.settings.pausedNeedAttention)
    }

    func testDiscardingUnreadableEntriesKeepsTheOtherUnreadableLists() async throws {
        let (defaults, model) = try unreadableLog()
        await model.discardUnreadableEntries()
        XCTAssertNil(defaults.object(forKey: NiggleLogSettings.entriesKey))
        XCTAssertFalse(model.settings.entriesNeedAttention)
        assertKept(defaults, [NiggleLogSettings.rulesKey: "not json rules",
                              NiggleLogSettings.pausedKey: "not json paused"])
        XCTAssertTrue(model.settings.rulesNeedAttention)
        XCTAssertTrue(model.settings.pausedNeedAttention)
    }

    func testDiscardingUnreadablePausedKeepsTheOtherUnreadableLists() async throws {
        let (defaults, model) = try unreadableLog()
        await model.discardUnreadablePaused()
        XCTAssertNil(defaults.object(forKey: NiggleLogSettings.pausedKey))
        XCTAssertFalse(model.settings.pausedNeedAttention)
        assertKept(defaults, [NiggleLogSettings.entriesKey: "not json entries",
                              NiggleLogSettings.rulesKey: "not json rules"])
        XCTAssertTrue(model.settings.entriesNeedAttention)
        XCTAssertTrue(model.settings.rulesNeedAttention)
    }

    // MARK: Finding 2: "Since <date>" names the first week the curve shows

    func testCappedPhaseSaysSinceTheFirstWeekShown() {
        let nights = (0..<30).map { offset -> CutStressNight in
            let day = CanonicalDay.adding(offset, to: "2031-07-28") ?? "2031-07-28"
            return CutStressNight(day: day, restingHr: 60, hrv: 50)
        }
        let result = CutStressTrend.weekly(CutStressInput(nights: nights, firstWeekStart: "2031-01-06",
                                                          today: "2031-09-01",
                                                          maxWeeks: CutStressPresenter.maxWeeksWithPhase))
        XCTAssertEqual(result.weeks.first?.weekStart, "2031-03-10", "the 26-week cap moves the first week")
        let p = CutStressPresenter.present(result, restingHrBaseline: nil, hrvBaseline: nil,
                                           firstWeekStart: "2031-01-06", locale: Fx.british)
        let words = CutScorecardPresenter.Wording(unitSystem: .metric, locale: Fx.british)
        XCTAssertEqual(p.periodText, String(localized: "Since \(words.shortDate("2031-03-10"))"))
        XCTAssertEqual(p.restingHr.firstLabel, words.shortDate("2031-03-10"))
        XCTAssertFalse(p.periodText.contains("Jan"), p.periodText)
    }

    func testUncappedPhaseStillSaysSinceThePhasesFirstWeek() {
        let result = CutStressTrend.weekly(CutStressInput(nights: [], firstWeekStart: "2031-01-06",
                                                          today: "2031-02-05",
                                                          maxWeeks: CutStressPresenter.maxWeeksWithPhase))
        let p = CutStressPresenter.present(result, restingHrBaseline: nil, hrvBaseline: nil,
                                           firstWeekStart: "2031-01-06", locale: Fx.british)
        let words = CutScorecardPresenter.Wording(unitSystem: .metric, locale: Fx.british)
        XCTAssertEqual(p.periodText, String(localized: "Since \(words.shortDate("2031-01-06"))"))
    }

    // MARK: Finding 3: the Health row counts what the log lists as open

    func testHealthRowCountsEveryComplaintTheLogListsAsOpen() {
        var resolvedLater = Fx.n6
        resolvedLater.resolvedDay = "2031-06-16"
        let fixtures: [(String, [StoredNiggle])] = [
            ("onset after today", [Fx.n7]),
            ("resolved after today", [resolvedLater]),
            ("normal open and resolved", [Fx.n1, Fx.n2, Fx.n4]),
            ("all together", [Fx.n1, Fx.n2, Fx.n4, Fx.n7, resolvedLater]),
        ]
        for (label, entries) in fixtures {
            let shown = NiggleLogPresenter.present(
                entries: entries, rules: Fx.rules, paused: [], entriesNeedAttention: false, rulesNeedAttention: false,
                pausedNeedAttention: false, today: "2031-06-15", locale: Fx.british)
            let row = NiggleLogPresenter.healthRow(enabled: true, entries: entries, today: "2031-06-15",
                                                   locale: Fx.british)
            let expected = shown.open.isEmpty ? nil : String(localized: "\(shown.open.count) open")
            XCTAssertEqual(row?.detail, expected, label)
        }
        let one = NiggleLogPresenter.present(
            entries: [Fx.n7], rules: Fx.rules, paused: [], entriesNeedAttention: false, rulesNeedAttention: false,
            pausedNeedAttention: false, today: "2031-06-15", locale: Fx.british)
        XCTAssertEqual(one.open.count, 1, "a complaint dated tomorrow is still listed")
        XCTAssertEqual(NiggleLogPresenter.healthRow(enabled: true, entries: [Fx.n7], today: "2031-06-15",
                                                    locale: Fx.british)?.detail, "1 open")
    }

    // MARK: Finding 4: the timeline follows the scorecard result that wins

    private final class Gate {
        var pending: [CheckedContinuation<CutScorecardEvaluation, Never>] = []
    }

    private func evaluation(_ input: CutScorecardInput) -> CutScorecardEvaluation {
        (input: input, result: CutScorecard.evaluate(input))
    }

    private func settle(until done: () -> Bool) async {
        for _ in 0..<500 where !done() {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    private func gatedTimeline() async throws -> (CheckpointTimelineModel, CutScorecardModel, Gate) {
        let h = try await CoachPacketHarness.empty(scorecard: true, suites: packetSuites)
        h.defaults.set(true, forKey: CheckpointTimelineSettings.enabledKey)
        h.scorecardSettings.phases = Fx.phases
        let now = Fx.noon("2031-02-05")
        let gate = Gate()
        let scorecard = CutScorecardModel(
            repository: h.repo, provider: h.provider, settings: h.scorecardSettings, unitSystem: { .metric },
            now: { now }, timeZone: { Fx.utc }, locale: { Fx.british },
            evaluate: { _ in await withCheckedContinuation { gate.pending.append($0) } })
        let model = CheckpointTimelineModel(
            settings: CheckpointTimelineSettings(defaults: h.defaults), scorecardSettings: h.scorecardSettings,
            scorecard: scorecard, scans: .notBuilt, events: .notBuilt, now: { now }, timeZone: { Fx.utc },
            locale: { Fx.british }, unitSystem: { .metric })
        return (model, scorecard, gate)
    }

    private func projectionDay(_ model: CheckpointTimelineModel) -> String? {
        model.result?.items.first { $0.kind == .projection }?.day
    }

    /// X and Y: two evaluations whose projections are on different days.
    private func twoProjections() -> (x: CutScorecardEvaluation, y: CutScorecardEvaluation) {
        let x = evaluation(ScorecardScreenFixture.input(today: "2031-02-05"))
        let y = evaluation(ScorecardScreenFixture.input(today: "2031-02-05", without: [5]))
        return (x, y)
    }

    private func runOvertake(warm: Bool) async throws {
        let (model, scorecard, gate) = try await gatedTimeline()
        let (x, y) = twoProjections()
        XCTAssertEqual(y.result.projection.status, .projected, "fixture precondition")
        XCTAssertNotEqual(x.result.projection.targetDay, y.result.projection.targetDay, "fixture precondition")
        if warm {
            let first = Task { await scorecard.load() }
            await settle { gate.pending.count == 1 }
            gate.pending.removeFirst().resume(returning: x)
            await first.value
        }
        let timeline = Task { await model.load() }
        await settle { gate.pending.count == 1 }
        let later = Task { await scorecard.load() }
        await settle { gate.pending.count == 2 }
        XCTAssertEqual(gate.pending.count, 2)
        // The timeline's own load (A) finishes first and is overtaken; the later one (B) wins.
        gate.pending[0].resume(returning: x)
        await timeline.value
        gate.pending[1].resume(returning: y)
        gate.pending.removeAll()
        await later.value
        await settle { projectionDay(model) == y.result.projection.targetDay }
        XCTAssertEqual(scorecard.evaluation?.result.projection.targetDay, y.result.projection.targetDay)
        XCTAssertEqual(projectionDay(model), y.result.projection.targetDay,
                       "the timeline shows the projection the scorecard screen shows")
    }

    func testTimelineFollowsAScorecardLoadThatOvertakesItsOwn() async throws {
        try await runOvertake(warm: true)
    }

    func testTimelineFollowsAnOvertakingLoadOnAColdScorecard() async throws {
        try await runOvertake(warm: false)
    }

    // MARK: Finding 5: the checkpoint sheet's messages come from the presenter

    private func waypoint(title: String, weightKg: Double?) -> StoredCheckpoint {
        StoredCheckpoint(id: "", title: title, category: .weightWaypoint, day: "2031-03-19", approximate: false,
                         done: false, waypointWeightKg: weightKg, phaseStartDay: nil)
    }

    private func message(_ checkpoint: StoredCheckpoint, weightText: String,
                         isEditing: Bool) -> CheckpointSheetMessages {
        let issue = CheckpointTimelineSettings.issue(checkpoint, others: [], phases: Fx.phases)
        return CheckpointTimelinePresenter.sheetMessages(issue: issue, checkpoint: checkpoint, weightText: weightText,
                                                         isEditing: isEditing, phases: Fx.phases,
                                                         unitSystem: .metric, locale: Fx.british)
    }

    func testWaypointWithATooLongTitleSaysWhy() {
        let long = String(repeating: "x", count: 61)
        let shown = message(waypoint(title: long, weightKg: 96), weightText: "96", isEditing: false)
        XCTAssertEqual(shown.titleText, "A title can be up to 60 characters.")
        XCTAssertEqual(shown.fieldText, CheckpointTimelinePresenter.waypointCaption)
        XCTAssertFalse(shown.showsEditPhase)
    }

    func testEditedWaypointWithAnEmptyTitleSaysEnterATitle() {
        let shown = message(waypoint(title: "", weightKg: 96), weightText: "96", isEditing: true)
        XCTAssertEqual(shown.titleText, "Enter a title.")
    }

    func testNewCheckpointWithNoTitleYetSaysNothingAboutTheTitle() {
        let shown = message(waypoint(title: "", weightKg: 96), weightText: "96", isEditing: false)
        XCTAssertNil(shown.titleText)
    }

    func testWaypointBeyondTheTargetSaysSoBeforeATitleIsTyped() {
        let shown = message(waypoint(title: "", weightKg: 93), weightText: "93", isEditing: false)
        XCTAssertNil(shown.titleText)
        XCTAssertEqual(shown.fieldText, "A waypoint has to be short of your target (94.0 kg).")
        XCTAssertTrue(shown.showsEditPhase)
    }

    func testWaypointWithNoWeightTypedShowsTheCaption() {
        let shown = message(waypoint(title: "Fixture waypoint", weightKg: nil), weightText: "", isEditing: false)
        XCTAssertNil(shown.titleText)
        XCTAssertEqual(shown.fieldText, CheckpointTimelinePresenter.waypointCaption)
    }

    func testWaypointWithAnOutOfRangeWeightSaysTheRange() {
        let shown = message(waypoint(title: "Fixture waypoint", weightKg: 20), weightText: "20", isEditing: false)
        XCTAssertEqual(shown.fieldText, "Enter 30 to 250 kg.")
    }
}
