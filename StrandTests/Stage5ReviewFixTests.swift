// Regression tests for three confirmed review findings on stage 5's app side.
//
//  1. A chart passed sparse day keys (only the days with a reading) printed a caption for an event
//     that fell in a gap and had no dot, while its spoken text said nothing.
//  2. The Events model kept the "today" of its last reload across midnight and zone changes.
//  3. "Copy stored text" put the raw stored list on the general pasteboard as an item other devices
//     could receive, with no expiry.
//
// API added for these tests, in Strand/Data/PersonalEventsModel.swift:
//
//     struct PersonalEventStoredTextCopyPlan: Equatable {
//         static let lifetimeSeconds: TimeInterval
//         let text: String; let copiedAt: Date
//         var expiresAt: Date { get }; var localOnly: Bool { get }
//     }
//     protocol PersonalEventStoredTextPasteboardWriting { func write(_ plan: PersonalEventStoredTextCopyPlan) }
//     PersonalEventsModel.init(store:now:timeZone:locale:notificationCenter:pasteboard:)
//     PersonalEventsModel.copyStoredText()
//
// Every value is invented.

import XCTest
import StrandAnalytics
import StrandDesign
import WhoopStore
@testable import Strand

@MainActor
final class Stage5ReviewFixTests: XCTestCase {

    private typealias Fx = PersonalEventAppFixture

    private var suites: [String] = []

    override func tearDown() {
        for name in suites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        suites = []
        super.tearDown()
    }

    private func suite(_ events: [PersonalEvent]? = nil, raw: String? = nil) throws -> UserDefaults {
        let name = "Stage5ReviewFixTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        suites.append(name)
        defaults.set(true, forKey: PersonalEventStore.enabledKey)
        if let events { defaults.set(Fx.stored(events), forKey: PersonalEventStore.itemsKey) }
        if let raw { defaults.set(raw, forKey: PersonalEventStore.itemsKey) }
        return defaults
    }

    private func eventually(_ condition: () -> Bool, _ message: String,
                            file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail(message, file: file, line: line)
    }

    // MARK: 1. Sparse chart keys

    private let trip = Fx.make(Fx.id(1), .travel, "2031-03-10", "2031-03-12", createdAt: 1000)

    func testSparseDayKeysNeverCaptionAnEventWithoutMarks() throws {
        let source = PersonalEventChartSource(store: PersonalEventStore(defaults: try suite([trip])),
                                              locale: Fx.british)
        let weighIns = ["2031-03-07", "2031-03-14"]

        XCTAssertNil(source.marks(dayKeys: weighIns, style: .points), "the trip falls between the readings")
        XCTAssertNil(source.marks(dayKeys: weighIns, xs: [0, 7], domain: 0...7))
        XCTAssertNil(source.caption(dayKeys: weighIns), "no dot, so no caption naming the trip")
    }

    func testSparseKeysCaptionExactlyWhenThereAreMarksAndTheMarksSpeakEveryLine() throws {
        let events = [trip, Fx.make(Fx.id(2), .deload, "2031-03-20", "2031-03-21", createdAt: 1001)]
        let source = PersonalEventChartSource(store: PersonalEventStore(defaults: try suite(events)),
                                              locale: Fx.british)
        let lists: [[String]] = [
            ["2031-03-07", "2031-03-14"],
            ["2031-03-07", "2031-03-14", "2031-03-21"],
            ["2031-03-01", "2031-03-11", "2031-03-30"],
            ["2031-03-13", "2031-03-19", "2031-03-22"],
            ["2031-03-09"],
            ["2031-03-12"],
        ]
        for keys in lists {
            let xs = keys.indices.map(Double.init)
            let caption = source.caption(dayKeys: keys)
            for marks in [source.marks(dayKeys: keys, style: .points), source.marks(dayKeys: keys, style: .bars),
                          source.marks(dayKeys: keys, xs: xs, domain: 0...Double(max(keys.count - 1, 1)))] {
                XCTAssertEqual(marks == nil, caption == nil, "\(keys): a caption exactly when there are marks")
                if let marks, let caption {
                    let spoken = try XCTUnwrap(marks.accessibilityText, "\(keys)")
                    for line in caption.lines { XCTAssertTrue(spoken.contains(line), "\(keys): \(line)") }
                    XCTAssertEqual(spoken, caption.spokenText, "\(keys): one funnel for both readouts")
                }
            }
        }
    }

    // MARK: 2. Today follows the calendar

    private final class Clock {
        var now: Date
        var zone: TimeZone
        init(_ now: Date, _ zone: TimeZone) { self.now = now; self.zone = zone }
    }

    func testHealthRowFollowsTheDayChangeWithoutAWrite() async throws {
        let oneDay = Fx.make(Fx.id(1), .travel, "2031-03-12", "2031-03-12", createdAt: 1000)
        let clock = Clock(Fx.noon("2031-03-12"), Fx.utc)
        let center = NotificationCenter()
        let store = PersonalEventStore(defaults: try suite([oneDay]), now: { clock.now })
        let model = PersonalEventsModel(store: store, now: { clock.now }, timeZone: { clock.zone },
                                        locale: Fx.british, notificationCenter: center)
        XCTAssertNotNil(model.presentation.healthRowValue)
        XCTAssertEqual(model.presentation.now.map(\.id), [oneDay.id])

        clock.now = Fx.noon("2031-03-13")
        center.post(name: .NSCalendarDayChanged, object: nil)
        await eventually({ model.presentation.healthRowValue == nil }, "the row stops counting yesterday's event")
        XCTAssertEqual(model.presentation.earlier.map(\.id), [oneDay.id])
        XCTAssertEqual(model.presentation.now, [])
    }

    func testTheScreenFollowsAZoneChangeWithoutAWrite() async throws {
        // 2031-03-12 at 20:00 UTC is already 2031-03-13 in Kolkata.
        let tomorrow = Fx.make(Fx.id(2), .deload, "2031-03-13", "2031-03-14", createdAt: 1001)
        let clock = Clock(Fx.instant("2031-03-12T20:00:00Z"), Fx.utc)
        let center = NotificationCenter()
        let store = PersonalEventStore(defaults: try suite([tomorrow]), now: { clock.now })
        let model = PersonalEventsModel(store: store, now: { clock.now }, timeZone: { clock.zone },
                                        locale: Fx.british, notificationCenter: center)
        XCTAssertEqual(model.presentation.upcoming.map(\.id), [tomorrow.id])

        clock.zone = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
        center.post(name: .NSSystemTimeZoneDidChange, object: nil)
        await eventually({ model.presentation.now.map(\.id) == [tomorrow.id] }, "the event has started here")
        XCTAssertEqual(model.presentation.upcoming, [])
    }
}
