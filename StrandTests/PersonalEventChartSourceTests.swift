// API ASSUMED BY THESE TESTS
//
// Written from docs/personal/superapp/specs/stage-5.md §10.5, §10.9 and §13.2 before the
// implementation exists. New, in Strand/Data/PersonalEventChartSource.swift:
//
//     @MainActor final class PersonalEventChartSource: ObservableObject {
//         enum MarkStyle { case points, bars }
//         static let shared: PersonalEventChartSource
//         init(store: PersonalEventStore = .shared, locale: Locale = AppLanguage.activeLocale)
//         func marks(dayKeys: [String], style: MarkStyle) -> NoopChartAxisMarks?
//         func marks(weekStarts: [String]) -> NoopChartAxisMarks?
//         func marks(dayKeys: [String], xs: [Double], domain: ClosedRange<Double>) -> NoopChartAxisMarks?
//         func caption(firstDay: String, lastDay: String, today: String) -> PersonalEventCaption?
//     }
//
// Existing: `NoopChartAxisMarks.points(covered:accessibilityText:)`, `.bars(covered:...)`,
// `.values(_:covered:domain:accessibilityText:)` (committed with its own tests; its module is
// StrandAnalytics on this branch and StrandDesign by the specification, so both are imported).
//
// Behaviour assumed where the specification leaves it unstated:
//
//  1. A day slot is the day itself; a week slot is [weekStart, weekStart + 6]. Every function
//     returns nil when no slot is covered, and nil for an empty key list.
//  2. The fractions a source returns are exactly the ones the `NoopChartAxisMarks` constructor of
//     its style returns for the covered flags (so they are compared through that constructor).
//     `accessibilityText` is not compared here; PersonalEventPrivacyTests scans it.
//  3. The caption's window is the one the site passes; "today" is the caller's.
//  4. A malformed day key in the list is an uncovered slot, never a trap.

import XCTest
import StrandAnalytics
import StrandDesign
import WhoopStore
@testable import Strand

@MainActor
final class PersonalEventChartSourceTests: XCTestCase {

    private typealias Fx = PersonalEventAppFixture

    private var suites: [String] = []

    override func tearDown() {
        for name in suites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        suites = []
        super.tearDown()
    }

    // MARK: Helpers

    private func makeSource(_ events: [PersonalEvent], flag: Bool = true, extra: [String] = [])
        throws -> (PersonalEventChartSource, UserDefaults) {
        let name = "PersonalEventChartSourceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        suites.append(name)
        defaults.set(flag, forKey: PersonalEventStore.enabledKey)
        defaults.set(Fx.stored(events, extra: extra), forKey: PersonalEventStore.itemsKey)
        let store = PersonalEventStore(defaults: defaults)
        return (PersonalEventChartSource(store: store, locale: Fx.british), defaults)
    }

    /// Consecutive day keys from `first`, written by the test's own arithmetic.
    private func days(from first: String, count: Int) -> [String] {
        let keys = LocalDayWindows(timeZone: Fx.utc)
        let start = Fx.noon(first)
        return (0..<count).map { keys.dayKey(for: start.addingTimeInterval(Double($0) * 86_400)) }
    }

    /// The twenty-two fixture weeks of §13.2, written out.
    private let weekStarts = [
        "2031-01-06", "2031-01-13", "2031-01-20", "2031-01-27", "2031-02-03", "2031-02-10",
        "2031-02-17", "2031-02-24", "2031-03-03", "2031-03-10", "2031-03-17", "2031-03-24",
        "2031-03-31", "2031-04-07", "2031-04-14", "2031-04-21", "2031-04-28", "2031-05-05",
        "2031-05-12", "2031-05-19", "2031-05-26", "2031-06-02",
    ]

    private func covered(_ indices: Set<Int>, count: Int) -> [Bool] {
        (0..<count).map { indices.contains($0) }
    }

    // MARK: Flag off (§12.4)

    func testEveryFunctionReturnsNilWhileTheFlagIsOff() throws {
        let (source, defaults) = try makeSource(Fx.all, flag: false)
        let march = days(from: "2031-03-01", count: 31)
        XCTAssertNil(source.marks(dayKeys: march, style: .points))
        XCTAssertNil(source.marks(dayKeys: march, style: .bars))
        XCTAssertNil(source.marks(weekStarts: weekStarts))
        XCTAssertNil(source.marks(dayKeys: march, xs: march.indices.map(Double.init), domain: 0...30))
        XCTAssertNil(source.caption(firstDay: "2031-01-01", lastDay: "2031-06-30", today: "2031-03-12"))

        // The same source follows the flag when it is switched on: nothing is cached.
        defaults.set(true, forKey: PersonalEventStore.enabledKey)
        XCTAssertNotNil(source.marks(weekStarts: weekStarts))
        XCTAssertNotNil(source.caption(firstDay: "2031-01-01", lastDay: "2031-06-30", today: "2031-03-12"))
    }

    func testEveryFunctionReturnsNilWhenNothingOverlaps() throws {
        let (source, _) = try makeSource(Fx.all)
        let quiet = days(from: "2031-01-01", count: 21)   // E7 ended in 2030; E4 starts on the 22nd
        XCTAssertNil(source.marks(dayKeys: quiet, style: .points))
        XCTAssertNil(source.marks(dayKeys: quiet, style: .bars))
        XCTAssertNil(source.marks(dayKeys: quiet, xs: quiet.indices.map(Double.init), domain: 0...20))
        XCTAssertNil(source.marks(weekStarts: ["2031-03-31", "2031-04-07"]))
        XCTAssertNil(source.caption(firstDay: "2031-01-01", lastDay: "2031-01-21", today: "2031-03-12"))
        XCTAssertNil(source.marks(dayKeys: [], style: .bars))
        XCTAssertNil(source.marks(weekStarts: []))

        let (empty, _) = try makeSource([])
        XCTAssertNil(empty.marks(weekStarts: weekStarts), "no events stored")
    }

    // MARK: Marks

    func testDayBarsAndDayPointsAgreeOnWhichDaysAreCovered() throws {
        let (source, _) = try makeSource(Fx.all)
        let thirty = days(from: "2031-03-01", count: 30)       // 1 to 30 March
        // E1 covers 10 to 16 March (indices 9 to 15); E6 is 26 March (index 25).
        let expected = covered(Set(9...15).union([25]), count: 30)

        let points = try XCTUnwrap(source.marks(dayKeys: thirty, style: .points))
        let bars = try XCTUnwrap(source.marks(dayKeys: thirty, style: .bars))
        XCTAssertEqual(points.fractions, NoopChartAxisMarks.points(covered: expected).fractions)
        XCTAssertEqual(bars.fractions, NoopChartAxisMarks.bars(covered: expected).fractions)
        XCTAssertEqual(points.fractions.count, bars.fractions.count, "the same days, placed by each style")
        XCTAssertEqual(points.fractions.first ?? -1, 9.0 / 29.0, accuracy: 1e-12)
        XCTAssertEqual(bars.fractions.first ?? -1, 9.5 / 30.0, accuracy: 1e-12)

        // Seven day bars (the training hub) and a single day.
        let week = days(from: "2031-03-24", count: 7)
        XCTAssertEqual(try XCTUnwrap(source.marks(dayKeys: week, style: .bars)).fractions,
                       NoopChartAxisMarks.bars(covered: covered([2], count: 7)).fractions)
        XCTAssertEqual(try XCTUnwrap(source.marks(dayKeys: ["2031-03-26"], style: .points)).fractions, [0.5])

        // A malformed key is an uncovered slot.
        let broken = ["2031-03-10", "2031-3-11", "2031-03-12"]
        XCTAssertEqual(try XCTUnwrap(source.marks(dayKeys: broken, style: .bars)).fractions,
                       NoopChartAxisMarks.bars(covered: [true, false, true]).fractions)
    }

    func testValueAxisMarksUseTheValuesConstructor() throws {
        let (source, _) = try makeSource(Fx.all)
        let thirty = days(from: "2031-03-01", count: 30)
        let xs = thirty.indices.map { Double($0) * 86_400 + 1_000 }
        let domain = 0.0...(31.0 * 86_400)
        let expected = covered(Set(9...15).union([25]), count: 30)
        let marks = try XCTUnwrap(source.marks(dayKeys: thirty, xs: xs, domain: domain))
        XCTAssertEqual(marks.fractions, NoopChartAxisMarks.values(xs, covered: expected, domain: domain).fractions)
    }

    func testWeekMarksMatchTheFixtureTable() throws {
        let (source, _) = try makeSource(Fx.all)
        // §13.2: weeks 3, 5, 7, 8, 10, 12, 15, 16, 20, 21, 22 (1-based).
        let expected = covered([2, 4, 6, 7, 9, 11, 14, 15, 19, 20, 21], count: 22)
        let marks = try XCTUnwrap(source.marks(weekStarts: weekStarts))
        XCTAssertEqual(marks.fractions, NoopChartAxisMarks.points(covered: expected).fractions)

        // V2: only the private events, still marked (a dot carries no text).
        let (privateOnly, _) = try makeSource([Fx.e5, Fx.e6])
        XCTAssertEqual(try XCTUnwrap(privateOnly.marks(weekStarts: weekStarts)).fractions,
                       NoopChartAxisMarks.points(covered: covered([11, 19, 20, 21], count: 22)).fractions)

        // V5: the illness ends on 25 May, so weeks 21 and 22 lose their mark.
        let ended = Fx.make(Fx.id(5), .illness, "2031-05-19", "2031-05-25", sensitive: true, createdAt: 1004)
        let (v5, _) = try makeSource(Fx.all.filter { $0.id != Fx.id(5) } + [ended])
        XCTAssertEqual(try XCTUnwrap(v5.marks(weekStarts: weekStarts)).fractions,
                       NoopChartAxisMarks.points(covered: covered([2, 4, 6, 7, 9, 11, 14, 15, 19], count: 22)).fractions)

        // V9: private deload and diet break keep their weeks.
        let (v9, _) = try makeSource(Fx.v9)
        XCTAssertEqual(try XCTUnwrap(v9.marks(weekStarts: weekStarts)).fractions, marks.fractions)
    }

    func testUnreadableEntriesAndInvalidEventsMarkNothing() throws {
        let (source, _) = try makeSource([Fx.e1], extra: [Fx.unknownKindElement, Fx.issueElement])
        let march = days(from: "2031-03-01", count: 7)     // the unreadable elements start 1 and 4 March
        XCTAssertNil(source.marks(dayKeys: march, style: .bars))
        XCTAssertNil(source.caption(firstDay: "2031-03-01", lastDay: "2031-03-07", today: "2031-03-12"))
    }

    // MARK: One read for marks and caption (fault F22)

    func testMarksAndCaptionAreResolvedFromTheSameEvents() throws {
        let lists: [[PersonalEvent]] = [Fx.all, [Fx.e5, Fx.e6], Fx.v9, [Fx.e6], []]
        let windows: [(String, Int)] = [("2031-03-20", 12), ("2031-05-01", 31), ("2031-01-01", 120),
                                        ("2031-02-01", 28), ("2031-01-01", 21), ("2030-11-25", 14)]
        for events in lists {
            let (source, _) = try makeSource(events)
            for (first, count) in windows {
                let keys = days(from: first, count: count)
                let marks = source.marks(dayKeys: keys, style: .bars)
                let caption = source.caption(firstDay: keys.first!, lastDay: keys.last!, today: "2031-06-30")
                let label = "\(events.map(\.id)) over \(first)+\(count)"
                XCTAssertEqual(marks == nil, caption == nil, "\(label): a caption exactly when there are marks")

                // The caption names as many events as overlap the marked days.
                let overlapping = PersonalEvents.events(overlapping: keys.first!, keys.last!, in: events)
                if let caption {
                    let more = caption.moreText.flatMap { text in
                        Int(text.components(separatedBy: " ").first { Int($0) != nil } ?? "")
                    } ?? 0
                    XCTAssertEqual(caption.lines.count + more, overlapping.count, label)
                }
            }
        }
    }

    func testCaptionThroughTheSourceIsThePresentersCaption() throws {
        let (source, _) = try makeSource(Fx.all)
        for (first, last, today) in [("2031-01-01", "2031-03-31", "2031-03-12"), ("2031-05-01", "2031-05-31", "2031-05-28"),
                                     ("2030-11-01", "2030-12-31", "2031-03-12")] {
            XCTAssertEqual(source.caption(firstDay: first, lastDay: last, today: today),
                           PersonalEventPresenter.caption(events: Fx.all, firstDay: first, lastDay: last, today: today,
                                                          locale: Fx.british))
        }
        XCTAssertEqual(source.caption(firstDay: "2031-01-01", lastDay: "2031-03-31", today: "2031-03-12")?.lines,
                       ["Private event · 26 Mar", "Travel · 10 – 16 Mar"])
    }

    func testSourceFollowsTheStoreWithoutBeingRebuilt() throws {
        let (source, defaults) = try makeSource([Fx.e1])
        XCTAssertNil(source.marks(weekStarts: ["2031-02-03"]))
        defaults.set(Fx.stored([Fx.e1, Fx.e2]), forKey: PersonalEventStore.itemsKey)   // a restore
        XCTAssertEqual(try XCTUnwrap(source.marks(weekStarts: ["2031-02-03"])).fractions, [0.5])
    }
}
