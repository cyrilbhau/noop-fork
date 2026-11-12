// API ASSUMED BY THESE TESTS
//
// Written from docs/personal/superapp/specs/stage-6.md §8.4, §10.8, §12.3 and §13.4 (the adapter
// fixture) before the implementation exists. `TimelineScanSource` and `TimelineEventSource` are
// exactly as §8.4 lists them, in Strand/Data/TimelineSources.swift. Existing API used unchanged:
// `BodyScan` (stage 4), `BodyRecordSettings.enabledKey`, `PersonalEvent`, `PersonalEventKind`,
// `PersonalEventStore(defaults:)` (stage 5), `CheckpointTimeline.build`, `Repository(deviceId:)`,
// `WhoopStore.inMemory()`. The presenter call in `testSpanCopiesKindAndDaysOnly` uses
// `CheckpointTimelinePresenter.present` from the API block in Stage6TestSupport.swift.
//
// Behaviour assumed where the specification leaves it unstated:
//
//  1. `live(store:)` reads the store's `isEnabled` for its state, so a store over a private suite
//     with the stage 5 flag on gives `.on`.
//  2. `live(repository:defaults:)` reads `noop.bodyRecordEnabled` from the `defaults` it is given.
//
// Synthetic values only (§13.4).

import XCTest
import StrandAnalytics
import WhoopStore
@testable import Strand

@MainActor
final class TimelineSourcesTests: XCTestCase {

    private typealias Fx = Stage6Fixture
    private let suites = Stage6Suites()

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    private final class Counter { var calls = 0 }

    // MARK: Scans

    func testScanDaysAreDistinctInFirstSeenOrder() async {
        let scans = [Fx.scan(day: "2031-01-08", takenAt: 1_925_622_000), Fx.scan(day: "2031-03-17", takenAt: 1_931_756_400),
                     Fx.scan(day: "2031-01-08", takenAt: 1_925_625_600)]
        XCTAssertEqual(TimelineScanSource.days(of: scans), ["2031-01-08", "2031-03-17"])
        let source = TimelineScanSource(state: { .on }, scans: { scans })
        let read = await source.read()
        XCTAssertEqual(read.state, .on)
        XCTAssertEqual(read.days, ["2031-01-08", "2031-03-17"])
    }

    func testScanDayIsTakenFromTheScanAndNotFromItsInstant() async {
        // takenAt is 2031-01-08 23:30 UTC, which is 2031-01-09 in many zones; the scan says 2031-01-08.
        let scan = Fx.scan(day: "2031-01-08", takenAt: 1_925_681_400)
        let other = Fx.scan(day: "2031-01-10", takenAt: 1_925_500_000)   // an instant on 2031-01-06
        XCTAssertEqual(TimelineScanSource.days(of: [scan, other]), ["2031-01-08", "2031-01-10"])
        let read = await TimelineScanSource(state: { .on }, scans: { [scan, other] }).read()
        XCTAssertEqual(read.days, ["2031-01-08", "2031-01-10"])
    }

    func testScanSourceOffReturnsNothingAndNeverCallsScans() async {
        let counter = Counter()
        let scans = [Fx.scan(day: "2031-01-08", takenAt: 1_925_622_000)]
        let off = TimelineScanSource(state: { .off }, scans: { counter.calls += 1; return scans })
        let read = await off.read()
        XCTAssertEqual(read.state, .off)
        XCTAssertEqual(read.days, [])
        XCTAssertEqual(counter.calls, 0)
        let on = TimelineScanSource(state: { .on }, scans: { counter.calls += 1; return scans })
        _ = await on.read()
        XCTAssertEqual(counter.calls, 1)
    }

    func testScanSourceStateFollowsTheBodyRecordKeyWithoutWritingIt() async throws {
        let defaults = suites.recording()
        let repo = Repository(deviceId: "stage6-timeline-sources")
        repo.setStoreForTesting(try await WhoopStore.inMemory())
        let source = TimelineScanSource.live(repository: repo, defaults: defaults)
        let off = await source.read()
        XCTAssertEqual(off.state, .off)
        XCTAssertEqual(off.days, [])
        XCTAssertNil(defaults.object(forKey: BodyRecordSettings.enabledKey), "reading the key writes nothing")
        defaults.set(true, forKey: BodyRecordSettings.enabledKey)
        defaults.writes = []
        let on = await source.read()
        XCTAssertEqual(on.state, .on)
        XCTAssertEqual(on.days, [], "an empty store has no scan")
        XCTAssertEqual(defaults.writes, [])
        XCTAssertTrue(defaults.reads.contains(BodyRecordSettings.enabledKey))
    }

    func testNotBuiltSourcesReturnNothing() async {
        let scans = await TimelineScanSource.notBuilt.read()
        XCTAssertEqual(scans.state, .notBuilt)
        XCTAssertEqual(scans.days, [])
        let events = TimelineEventSource.notBuilt.read()
        XCTAssertEqual(events.state, .notBuilt)
        XCTAssertEqual(events.events, [])
    }

    // MARK: Events

    func testEventSourceReadsTheStorePropertyOncePerRead() {
        let counter = Counter()
        let source = TimelineEventSource(state: { .on }, events: { counter.calls += 1; return Fx.events })
        _ = source.read()
        XCTAssertEqual(counter.calls, 1)
        _ = source.read()
        XCTAssertEqual(counter.calls, 2)
    }

    func testEventSourceOffReturnsNothingAndNeverReadsEvents() throws {
        let counter = Counter()
        let off = TimelineEventSource(state: { .off }, events: { counter.calls += 1; return Fx.events })
        let read = off.read()
        XCTAssertEqual(read.state, .off)
        XCTAssertEqual(read.events, [])
        XCTAssertEqual(counter.calls, 0)

        // The live adapter over a stage 5 store whose flag is off.
        let defaults = try suites.make()
        let store = PersonalEventStore(defaults: defaults)
        let live = TimelineEventSource.live(store: store)
        XCTAssertEqual(live.read().state, .off)
        XCTAssertEqual(live.read().events, [])
        defaults.set(true, forKey: PersonalEventStore.enabledKey)
        XCTAssertEqual(live.read().state, .on)
    }

    func testOnlyDietBreaksAndDeloadsBecomeSpans() {
        let one: [PersonalEvent] = PersonalEventKind.allCases.enumerated().map { index, kind in
            PersonalEvent(id: String(format: "%016x", index + 1), kind: kind, label: kind == .custom ? "Fixture change" : nil,
                          startDay: "2031-03-0\(index + 1)", endDay: "2031-03-0\(index + 2)", note: nil,
                          sensitive: false, createdAt: index)
        }
        let kept = TimelineEventSource.timelineEvents(one)
        XCTAssertEqual(Set(kept.map(\.kind)), [.dietBreak, .deload])
        XCTAssertEqual(kept.count, 2)
        XCTAssertEqual(kept, one.filter { $0.kind == .dietBreak || $0.kind == .deload }, "order kept")
        XCTAssertEqual(TimelineEventSource.timelineEvents(Fx.events), [Fx.e1, Fx.e3], "§13.4 adapter fixture")
    }

    func testPrivateDeloadIsAbsentFromTheTimeline() {
        let kept = TimelineEventSource.timelineEvents([Fx.e1, Fx.e2])
        XCTAssertEqual(kept, [Fx.e1], "the private deload is filtered before the kind")
        let spans = kept.map(TimelineEventSource.span)
        XCTAssertEqual(spans, [TimelineSpan(kind: .deload, startDay: "2031-02-17", endDay: "2031-02-23")])
        let result = CheckpointTimeline.build(CheckpointTimelineInput(
            phases: [], checkpoints: [], scanDays: [], spans: spans, projection: nil, scans: .on, events: .on,
            today: "2031-04-10"))
        XCTAssertEqual(result.items.filter { $0.kind == .deload }.count, 1)
        XCTAssertFalse(result.items.contains { $0.day == "2031-04-07" }, "nothing on the private event's days")
    }

    func testPrivateDietBreakIsAbsentFromTheTimeline() {
        let privateBreak = PersonalEvent(id: "e500000000000000", kind: .dietBreak, label: nil, startDay: "2031-05-12",
                                         endDay: "2031-05-25", note: nil, sensitive: true, createdAt: 1004)
        let kept = TimelineEventSource.timelineEvents([Fx.e3, privateBreak])
        XCTAssertEqual(kept, [Fx.e3])
        let result = CheckpointTimeline.build(CheckpointTimelineInput(
            phases: [], checkpoints: [], scanDays: [], spans: kept.map(TimelineEventSource.span), projection: nil,
            scans: .on, events: .on, today: "2031-05-20"))
        XCTAssertEqual(result.items.filter { $0.kind == .dietBreak }.map(\.day), ["2031-03-24"])
    }

    func testSpanCopiesKindAndDaysOnly() {
        let labelled = PersonalEvent(id: "e600000000000000", kind: .deload, label: "Fixture label secret",
                                     startDay: "2031-02-17", endDay: "2031-02-23", note: "Fixture note secret",
                                     sensitive: false, createdAt: 1)
        let span = TimelineEventSource.span(labelled)
        XCTAssertEqual(span, TimelineSpan(kind: .deload, startDay: "2031-02-17", endDay: "2031-02-23"))
        let needles = ["Fixture label secret", "Fixture note secret", "e600000000000000"]
        let described = String(describing: span) + String(reflecting: span)
        for needle in needles { XCTAssertFalse(described.contains(needle), needle) }

        let result = CheckpointTimeline.build(CheckpointTimelineInput(
            phases: [], checkpoints: [], scanDays: [], spans: [span], projection: nil, scans: .on, events: .on,
            today: "2031-02-20"))
        for needle in needles.prefix(2) {
            XCTAssertFalse(String(reflecting: result).contains(needle), needle)
        }
        let rows = CheckpointTimelinePresenter.present(result, phases: [], checkpoints: [], events: [labelled],
                                                       scorecardEnabled: true, phasesNeedAttention: false,
                                                       checkpointsNeedAttention: false, unitSystem: .metric,
                                                       locale: Fx.british)
        let text = Stage6Text.joined(rows)
        for needle in needles.prefix(2) { XCTAssertFalse(text.contains(needle), "\(needle) in a row:\n\(text)") }
        XCTAssertTrue(rows.rows.contains { $0.kind == .deload }, "the span itself is shown")
    }

    func testOngoingEventBecomesAnOpenEndedSpan() {
        let span = TimelineEventSource.span(Fx.e3)
        XCTAssertEqual(span, TimelineSpan(kind: .dietBreak, startDay: "2031-03-24", endDay: nil))
        let result = CheckpointTimeline.build(CheckpointTimelineInput(
            phases: [], checkpoints: [], scanDays: [], spans: [span], projection: nil, scans: .on, events: .on,
            today: "2031-04-10"))
        let item = result.items.first { $0.kind == .dietBreak }
        XCTAssertEqual(item?.isOpenEnded, true)
        XCTAssertEqual(item?.position, .current)
    }

    func testLiveEventSourceHidesPrivateEventsFromAStage5Store() throws {
        let defaults = try suites.make()
        defaults.set(true, forKey: PersonalEventStore.enabledKey)
        let store = PersonalEventStore(defaults: defaults)
        for event in Fx.events {
            _ = try store.add(kind: event.kind, label: event.label, startDay: event.startDay, endDay: event.endDay,
                              note: event.note, sensitive: event.sensitive)
        }
        let read = TimelineEventSource.live(store: store).read()
        XCTAssertEqual(read.state, .on)
        XCTAssertEqual(read.events.map(\.kind), [.deload, .dietBreak])
        XCTAssertEqual(read.events.map(\.startDay), ["2031-02-17", "2031-03-24"])
        XCTAssertFalse(read.events.contains { $0.sensitive })
    }
}
