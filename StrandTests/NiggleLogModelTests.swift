// API ASSUMED BY THESE TESTS
//
// Written from docs/personal/superapp/specs/stage-6.md §8.1, §9.4, §10.2, §10.3 and §12.3 before the
// implementation exists. The full API block (`NiggleLogModel`, `NiggleLogSettings`,
// `NiggleLogPresenter`) is at the top of Stage6TestSupport.swift.
//
// Behaviour assumed where the specification leaves it unstated:
//
//  1. `load()` reads the clock once, as the scorecard model does, and computes "today" as the day
//     key of that instant in the zone `timeZone()` returns.
//  2. The loaded presentation is exactly `NiggleLogPresenter.present` over the settings' stored
//     lists and attention flags for that day, so the model adds no wording of its own.
//  3. While the flag is off the model publishes `.idle` and reads no list key (assumption 5 of the
//     support file: the flag key itself is read).
//
// Synthetic values only; the clock is fixed at 12:00 UTC of a 2031 day (no repository read is
// involved, so ruling R31 does not apply).

import XCTest
import StrandAnalytics
@testable import Strand

@MainActor
final class NiggleLogModelTests: XCTestCase {

    private typealias Fx = Stage6Fixture
    private let suites = Stage6Suites()

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    private final class Clock {
        var reads = 0
        var date: Date
        init(_ day: String) { date = Stage6Fixture.noon(day) }
        func now() -> Date { reads += 1; return date }
    }

    private func model(_ defaults: UserDefaults, clock: Clock) -> NiggleLogModel {
        NiggleLogModel(settings: NiggleLogSettings(defaults: defaults, today: { "2031-12-31" }),
                       now: { clock.now() }, timeZone: { Fx.utc }, locale: { Fx.british })
    }

    func testFlagOffReadsNothingAndPublishesIdle() async {
        let defaults = suites.recording()
        Fx.seed(defaults, entries: [Fx.n1, Fx.n2, Fx.n4])
        defaults.reads = []
        let m = model(defaults, clock: Clock("2031-03-22"))
        await m.load()
        XCTAssertEqual(m.state, .idle)
        let listReads = defaults.reads.filter { Fx.listKeys.contains($0) }
        XCTAssertEqual(listReads, [], "a flag-off load read \(listReads)")
        XCTAssertNil(m.detail(niggleId: Fx.n2.id))
        XCTAssertEqual(defaults.writes.filter { $0 != "noop.niggleLogEnabled" && !Fx.listKeys.contains($0) }.count, 0)
    }

    func testLoadedPresentationIsThePresentersOverTheStoredLists() async throws {
        let defaults = try suites.make()
        Fx.seed(defaults, entries: [Fx.n1, Fx.n2, Fx.n4])
        defaults.set(true, forKey: NiggleLogSettings.enabledKey)
        let m = model(defaults, clock: Clock("2031-03-22"))
        await m.load()
        let expected = NiggleLogPresenter.present(entries: [Fx.n1, Fx.n2, Fx.n4], rules: Fx.rules,
                                                  paused: [Fx.pausedPress, Fx.pausedRow], entriesNeedAttention: false,
                                                  rulesNeedAttention: false, pausedNeedAttention: false,
                                                  today: "2031-03-22", locale: Fx.british)
        XCTAssertEqual(m.state, .loaded(expected))
        XCTAssertEqual(m.detail(niggleId: Fx.n2.id),
                       NiggleLogPresenter.detail(niggleId: Fx.n2.id, entries: [Fx.n1, Fx.n2, Fx.n4], rules: Fx.rules,
                                                 paused: [Fx.pausedPress, Fx.pausedRow], rulesNeedAttention: false,
                                                 today: "2031-03-22", locale: Fx.british))
    }

    func testTodayIsCapturedOncePerLoad() async throws {
        let defaults = try suites.make()
        Fx.seed(defaults, entries: [Fx.n2])
        defaults.set(true, forKey: NiggleLogSettings.enabledKey)
        let clock = Clock("2031-03-21")
        let m = model(defaults, clock: clock)
        await m.load()
        XCTAssertEqual(clock.reads, 1, "one clock reading per load")
        guard case .loaded(let first) = m.state else { return XCTFail("\(m.state)") }
        XCTAssertEqual(first.open.first?.dayCountText, "Day 19")

        clock.date = Fx.noon("2031-03-22")
        await m.load()
        XCTAssertEqual(clock.reads, 2)
        guard case .loaded(let second) = m.state else { return XCTFail("\(m.state)") }
        XCTAssertEqual(second.open.first?.dayCountText, "Day 20", "the next load takes the new day")
        XCTAssertEqual(second.open.first?.label, "Fixture label D")
    }

    func testTodayIsTheDayInTheGivenZone() async throws {
        let defaults = try suites.make()
        Fx.seed(defaults, entries: [Fx.n2])
        defaults.set(true, forKey: NiggleLogSettings.enabledKey)
        // 23:30 UTC on 21 March is 22 March in a zone ahead of UTC.
        let late = Fx.noon("2031-03-21").addingTimeInterval(11.5 * 3_600)
        let ahead = NiggleLogModel(settings: NiggleLogSettings(defaults: defaults, today: { "2031-12-31" }),
                                   now: { late }, timeZone: { TimeZone(secondsFromGMT: 3_600)! },
                                   locale: { Fx.british })
        await ahead.load()
        guard case .loaded(let p) = ahead.state else { return XCTFail("\(ahead.state)") }
        XCTAssertEqual(p.open.first?.dayCountText, "Day 20")
    }

    func testFlagSwitchedOffReturnsToIdleAndDeletesNothing() async throws {
        let defaults = try suites.make()
        Fx.seed(defaults)
        defaults.set(true, forKey: NiggleLogSettings.enabledKey)
        let before = Stage6Text.raw(defaults)
        let m = model(defaults, clock: Clock("2031-03-22"))
        await m.load()
        guard case .loaded = m.state else { return XCTFail("\(m.state)") }
        defaults.set(false, forKey: NiggleLogSettings.enabledKey)
        await m.load()
        XCTAssertEqual(m.state, .idle)
        XCTAssertEqual(Stage6Text.raw(defaults), before)
    }

    func testAttentionStatesReachThePresentation() async throws {
        let defaults = try suites.make()
        Fx.seed(defaults, entries: [Fx.n2])
        defaults.set("not json", forKey: NiggleLogSettings.rulesKey)
        defaults.set(true, forKey: NiggleLogSettings.enabledKey)
        let m = model(defaults, clock: Clock("2031-03-22"))
        await m.load()
        guard case .loaded(let p) = m.state else { return XCTFail("\(m.state)") }
        XCTAssertEqual(p.rulesAttentionText, "Your rules could not be read. Nothing has been changed.")
        XCTAssertEqual(p.open.first?.triageLine, "Your rules need attention")

        defaults.set("not json", forKey: NiggleLogSettings.entriesKey)
        await m.load()
        guard case .loaded(let q) = m.state else { return XCTFail("\(m.state)") }
        XCTAssertEqual(q.state, .entriesNeedAttention)
        XCTAssertFalse(q.canAdd)
    }

    func testDetailPopsWhenTheEntryIsDeletedElsewhere() async throws {
        let defaults = try suites.make()
        Fx.seed(defaults)
        defaults.set(true, forKey: NiggleLogSettings.enabledKey)
        let m = model(defaults, clock: Clock("2031-03-22"))
        await m.load()
        XCTAssertNotNil(m.detail(niggleId: Fx.n2.id))
        XCTAssertTrue(NiggleLogSettings(defaults: defaults, today: { "2031-03-22" }).delete(niggleId: Fx.n2.id))
        await m.load()
        XCTAssertNil(m.detail(niggleId: Fx.n2.id))
    }

    func testOpenRowsSortBySeverityThenDayCountThroughTheModel() async throws {
        let defaults = try suites.make()
        Fx.seed(defaults, entries: [Fx.n7, Fx.n6, Fx.n5, Fx.n3, Fx.n2, Fx.n1])
        defaults.set(true, forKey: NiggleLogSettings.enabledKey)
        let m = model(defaults, clock: Clock("2031-06-16"))
        await m.load()
        guard case .loaded(let p) = m.state else { return XCTFail("\(m.state)") }
        XCTAssertEqual(p.open.map(\.id), [Fx.n2.id, Fx.n3.id, Fx.n5.id, Fx.n6.id, Fx.n7.id])
    }

    func testTheLabelIsTheTriageOfTheStoredComplaint() async throws {
        // §8.1: the label and day count have one source, `NiggleTriage.evaluate`. The model's row
        // agrees with the pure function over the stored complaint and rules, day after day.
        let defaults = try suites.make()
        Fx.seed(defaults, entries: [Fx.n2])
        defaults.set(true, forKey: NiggleLogSettings.enabledKey)
        let clock = Clock("2031-03-03")
        let m = model(defaults, clock: clock)
        let complaint = NiggleComplaint(onsetDay: Fx.n2.onsetDay, resolvedDay: nil, character: Fx.n2.character,
                                        trend: Fx.n2.trend, weakness: Fx.n2.weakness,
                                        updates: Fx.n2.updates.map {
                                            NiggleUpdate(day: $0.day, sequence: $0.seq, trend: $0.trend, weakness: $0.weakness)
                                        })
        for offset in 0..<40 {
            let day = CanonicalDay.key(CanonicalDay.number("2031-03-03")! + offset)
            clock.date = Fx.noon(day)
            await m.load()
            guard case .loaded(let p) = m.state, let row = p.open.first else { return XCTFail("\(day)") }
            let triage = NiggleTriage.evaluate(NiggleTriageInput(complaint: complaint,
                                                                 rules: Fx.rules.rules.map(\.triageRule), today: day))
            XCTAssertEqual(row.dayCountText, "Day \(triage.dayCount ?? -1)", day)
            let label = Fx.rules.rules.first { $0.id == triage.ruleId }?.label
            XCTAssertEqual(row.label, label, day)
        }
    }
}
