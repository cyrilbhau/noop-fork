// API ASSUMED BY THESE TESTS
//
// Written from docs/personal/superapp/specs/stage-5.md §10.5, §10.6, §10.8, §12.5 and C7 before the
// implementation exists. New API used (declared in the API blocks of PersonalEventStoreTests.swift,
// PersonalEventPresenterTests.swift, PersonalEventChartSourceTests.swift and
// CutScorecardEventNoteTests.swift): `PersonalEventStore`, `PersonalEventChartSource`,
// `PersonalEventPresenter.caption(events:firstDay:lastDay:today:locale:)`, `.outsideLine(for:locale:)`,
// `CutScorecardPresentationContext.events`, `CutScorecardPresentation.eventNote`.
//
// Existing, used unchanged: `PersonalEvents.packetLines(events:firstDay:lastDay:includeSensitive:)`,
// `WidgetSnapshot` and its `suiteName`, `CutScorecardPresenter.reminderTitle` / `.reminderBody` (the
// weigh-in reminder's content), `StrainTargetNotifier.StrainTargetPolicy.copy(target:dayStrain:)`,
// `AICoachEngine(repo:)`, `buildContext()`, `buildFullContext()`, `Repository(deviceId:)`,
// `setStoreForTesting(_:)`, `WhoopStore.inMemory()`.
//
// The needles are the fixture's private label ("Fixture change"), its private note ("Fixture note")
// and the ordinary note ("Fixture trip"). The `.shared` store reads the runner's standard defaults,
// so the two stage 5 keys there are set for each test and restored after it.
//
// Limits. A widget snapshot is built by the iPhone app (StrandiOS/Widgets/WidgetPublish.swift), which
// the macOS test target does not compile; here the snapshot type is encoded with every field set while
// the store is populated, and Tools/test_personal_events_boundaries.py asserts that no widget, shared
// or watch source names an event. Of the notification producers only the texts reachable without
// posting are read here; the source scan covers the rest.

import XCTest
import StrandAnalytics
import WhoopStore
@testable import Strand

@MainActor
final class PersonalEventPrivacyTests: XCTestCase {

    private typealias Fx = PersonalEventAppFixture

    private var standardKeys: PersonalEventStandardKeys?

    override func setUp() {
        super.setUp()
        standardKeys = PersonalEventStandardKeys()
        UserDefaults.standard.set(true, forKey: PersonalEventStore.enabledKey)
        UserDefaults.standard.set(Fx.stored(Fx.allNormalized), forKey: PersonalEventStore.itemsKey)
    }

    override func tearDown() {
        standardKeys?.restore()
        standardKeys = nil
        super.tearDown()
    }

    private var allNeedles: [String] { Fx.privateNeedles + [Fx.ordinaryNote] }

    private func assertNoNeedle(_ text: String, _ needles: [String], _ what: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        for needle in needles {
            XCTAssertFalse(text.contains(needle), "\(what) contains \(needle)", file: file, line: line)
        }
    }

    // MARK: Leaves the app

    func testWidgetSnapshotEncodingContainsNoEventText() throws {
        XCTAssertEqual(PersonalEventStore.shared.events, Fx.allNormalized, "the store is populated")
        let snapshot = WidgetSnapshot(recovery: 72, bpm: 58, batteryPct: 84, bonded: true,
                                      updated: Fx.noon("2031-03-26"), effort: 38, rest: 81, hrv: 64, restingHr: 52,
                                      effortDisplay: "38", effortWhoop: false, hrSeries: nil, stressSeries: nil,
                                      stressDay: nil, personal: nil)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let text = String(decoding: try encoder.encode(snapshot), as: UTF8.self)
        assertNoNeedle(text, allNeedles + Fx.kindWords + ["personalEvents", "Private event"], "the widget snapshot")
        XCTAssertNil(text.range(of: "event", options: .caseInsensitive), "no snapshot field names an event: \(text)")
        let fields = Mirror(reflecting: snapshot).children.compactMap(\.label)
        XCTAssertFalse(fields.contains { $0.lowercased().contains("event") }, "fields: \(fields)")
    }

    func testEveryNotificationTextContainsNoEventText() {
        let texts = [CutScorecardPresenter.reminderTitle, CutScorecardPresenter.reminderBody]
            + [StrainTargetNotifier.StrainTargetPolicy.copy(target: 14, dayStrain: 15.2)].flatMap { [$0.title, $0.body] }
        for text in texts {
            assertNoNeedle(text, allNeedles + ["Private event", "Travel", "Illness", "Diet break", "Deload",
                                               "Supplement change", "Something else"], "notification text \(text)")
        }
    }

    func testInAppCoachContextContainsNoEventText() async throws {
        XCTAssertEqual(PersonalEventStore.shared.events.count, 8)
        let plain = AICoachEngine(repo: Repository(deviceId: "test-personal-events-privacy"))
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: "my-whoop")
        repo.setStoreForTesting(store)
        let backed = AICoachEngine(repo: repo)

        let contexts = [plain.buildContext(), backed.buildContext(), await backed.buildFullContext()]
        for context in contexts {
            assertNoNeedle(context, allNeedles + ["Private event", "personalEvents", "Diet break", "Supplement change",
                                                  "dietBreak", "supplementChange", "Something else"],
                           "the in-app Coach context")
        }
    }

    func testPacketRowsWithSensitiveExcludedContainNoSensitiveLabelOrNote() {
        for (first, last) in [("2031-03-13", "2031-03-26"), ("2030-01-01", "2031-12-31"), ("2031-05-08", "2031-06-04")] {
            let rows = PersonalEvents.packetLines(events: Fx.all, firstDay: first, lastDay: last, includeSensitive: false)
            let text = rows.joined(separator: "\n")
            assertNoNeedle(text, Fx.privateNeedles + ["illness", "custom"], "packet rows \(first)..\(last)")
        }
        let wide = PersonalEvents.packetLines(events: Fx.all, firstDay: "2030-01-01", lastDay: "2031-12-31",
                                              includeSensitive: false).joined(separator: "\n")
        XCTAssertTrue(wide.contains(Fx.ordinaryNote), "an ordinary note is in the packet: the scan above is live")
    }

    // MARK: Inside the app, outside the Events screen

    func testChartCaptionAndScorecardNoteContainNoSensitiveLabelOrNote() {
        let source = PersonalEventChartSource(store: .shared, locale: Fx.british)
        for events in [Fx.all, Fx.v9] {
            UserDefaults.standard.set(Fx.stored(events), forKey: PersonalEventStore.itemsKey)
            for today in ["2031-03-26", "2031-05-28", "2032-01-01"] {
                for (first, last) in [("2030-01-01", "2031-12-31"), ("2031-03-20", "2031-03-31"), ("2031-05-01", "2031-05-31")] {
                    let captions = [source.caption(firstDay: first, lastDay: last, today: today),
                                    PersonalEventPresenter.caption(events: events, firstDay: first, lastDay: last,
                                                                   today: today, locale: Fx.british)]
                    for caption in captions.compactMap({ $0 }) {
                        let text = ScorecardScreenFixture.strings(in: caption).joined(separator: "\n")
                        assertNoNeedle(text, allNeedles, "caption \(first)..\(last) on \(today)")
                    }
                }
            }
        }
        for week in 1...22 {
            let input = ScorecardScreenFixture.input(today: ScorecardScreenFixture.weighDay(week))
            var context = CutScorecardPresentationContext(locale: Fx.british)
            context.events = Fx.all
            let p = CutScorecardPresenter.present(CutScorecard.evaluate(input), input: input, context: context)
            let text = ScorecardScreenFixture.strings(in: p).joined(separator: "\n")
            assertNoNeedle(text, allNeedles, "the scorecard of week \(week)")
        }
        // The private event does reach a caption, worded as such: the scan is live.
        XCTAssertEqual(PersonalEventPresenter.caption(events: Fx.all, firstDay: "2031-03-26", lastDay: "2031-03-26",
                                                      today: "2031-03-26", locale: Fx.british)?.lines,
                       ["Private event · 26 Mar"])
    }

    func testAccessibilityTextOfMarksContainsNoSensitiveLabelOrNote() {
        let source = PersonalEventChartSource(store: .shared, locale: Fx.british)
        let keys = LocalDayWindows(timeZone: Fx.utc)
        let days = (0..<200).map { keys.dayKey(for: Fx.noon("2030-11-20").addingTimeInterval(Double($0) * 86_400)) }
        let weeks = ["2031-03-10", "2031-03-17", "2031-03-24", "2031-05-19", "2031-05-26"]
        let marks = [source.marks(dayKeys: days, style: .points), source.marks(dayKeys: days, style: .bars),
                     source.marks(weekStarts: weeks),
                     source.marks(dayKeys: days, xs: days.indices.map(Double.init), domain: 0...199)]
        XCTAssertTrue(marks.allSatisfy { $0 != nil }, "every window is marked")
        for mark in marks.compactMap({ $0 }) {
            assertNoNeedle(mark.accessibilityText ?? "", allNeedles, "the spoken text of the marks")
        }
    }

    func testAppGroupDefaultsContainNoEventKey() throws {
        // Every store operation, then the App Group suite the widgets read.
        let store = PersonalEventStore.shared
        let added = try store.add(kind: .custom, label: "Fixture change", startDay: "2031-03-27", endDay: nil,
                                  note: "Fixture note", sensitive: true)
        try store.update(Fx.make(Fx.id(1), .travel, "2031-03-10", "2031-03-17", note: "Fixture trip", createdAt: 1000))
        try store.delete(id: added.id)
        _ = PersonalEventChartSource(store: store, locale: Fx.british).marks(weekStarts: ["2031-03-10"])

        let group = try XCTUnwrap(UserDefaults(suiteName: WidgetSnapshot.suiteName))
        let keys = Array(group.dictionaryRepresentation().keys)
        XCTAssertFalse(keys.contains { $0.hasPrefix("personalEvents.") || $0 == PersonalEventStore.enabledKey },
                       "an events key in the App Group suite: \(keys.filter { $0.lowercased().contains("event") })")
        for value in group.dictionaryRepresentation().values {
            if let text = value as? String { assertNoNeedle(text, allNeedles, "an App Group value") }
            if let data = value as? Data { assertNoNeedle(String(decoding: data, as: UTF8.self), allNeedles, "an App Group blob") }
        }
    }
}
