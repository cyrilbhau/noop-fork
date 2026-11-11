// API ASSUMED BY THESE TESTS
//
// Stage 3 specification §8.4, §10.8, §12.3 (the additions listed for PersonalWidgetMetricsTests,
// written here as a new file), §12.5 and §12.8. Written before the implementation exists.
//
// New, in StrandiOSShared/PersonalWidgetMetrics.swift (Foundation only; compiled into the test
// bundle by name, project.yml:170-189, so these types are used without a module prefix):
//
//     public struct IntakeProteinValues: Equatable {                                   [spec §10.8]
//         public let shownGrams: Int?; public let shownFloorGrams: Int?; public let remainingGrams: Int?
//         public init(shownGrams: Int?, shownFloorGrams: Int?, remainingGrams: Int?)
//     }
//     public struct PersonalIntakeReading: Codable, Equatable {                        [spec §10.8]
//         public enum Source: String, Codable { case appleHealth, quickAdd }
//         public let day: String; public let proteinGrams: Int?; public let floorGrams: Int?
//         public let source: Source?; public let readAt: Date?
//         public static func reading(day: String, progress: IntakeProteinValues, source: Source?,
//                                    readAt: Date?) -> Self
//         public static let staleAfter: TimeInterval     // 3 × 3600
//         public var widgetState: PersonalIntakeWidgetState { get }                     [assumed]
//         public func isStale(now: Date) -> Bool                                         [assumed]
//             // a Health figure at or after readAt + staleAfter
//         public func timelineDates(now: Date, calendar: Calendar = .current) -> [Date]  [assumed]
//             // now; readAt + staleAfter when later than now; the next local midnight. Ascending.
//     }
//     public enum PersonalIntakeWidgetState: Equatable {                                [assumed]
//         case notSetUp
//         case nothingLogged(floorGrams: Int?)
//         case noFloor(grams: Int)
//         case below(grams: Int, floorGrams: Int, remainingGrams: Int)
//         case atFloor(grams: Int, floorGrams: Int)
//         case above(grams: Int, floorGrams: Int, overGrams: Int)
//     }
//     PersonalWidgetMetrics gains `public var intake: PersonalIntakeReading?` and
//     `public func todayIntake(now: Date, calendar: Calendar = .current) -> PersonalIntakeReading?`
//
// New in the app module (Strand/Data/IntakePresenter.swift). `PersonalWidgetMetrics.swift` is not
// part of the macOS `Strand` target and `project.yml` may not change in this stage, so the
// presenter returns a value of its own that the iPhone publisher copies into the payload: [assumed]
//
//     enum IntakeWidgetSource: String, Equatable { case appleHealth, quickAdd }
//     struct IntakeWidgetValues: Equatable {
//         let day: String; let proteinGrams: Int?; let floorGrams: Int?; let remainingGrams: Int?
//         let source: IntakeWidgetSource?; let readAt: Date?
//     }
//     extension IntakePresenter {
//         /// What the widget may show for `input.day`; nil when Intake is off or has no source.
//         static func widgetReading(_ input: IntakePresenterInput, clock: IntakeClock,
//                                   flagEnabled: Bool) -> IntakeWidgetValues?
//     }
//
// `IntakePresenterInput` and `IntakeClock` as at the top of IntakePresenterTests.swift.
//
// Synthetic values only.

import XCTest
import StrandAnalytics
@testable import Strand

@MainActor
final class IntakeWidgetPayloadTests: XCTestCase {
    private let clockFixture = IntakeTestClock()
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    private var today: String { clockFixture.today }
    private var fresh: Date { clockFixture.at(0, hour: 15, minute: 10) }

    private func reading(_ grams: Int?, floor: Int? = 100, source: PersonalIntakeReading.Source? = .appleHealth,
                         readAt: Date? = nil, day: String? = nil) -> PersonalIntakeReading {
        let remaining = grams.flatMap { g in floor.map { f in g < f ? max(1, f - g) : 0 } }
        return PersonalIntakeReading.reading(day: day ?? today,
                                             progress: IntakeProteinValues(shownGrams: grams, shownFloorGrams: floor,
                                                                           remainingGrams: remaining),
                                             source: source, readAt: readAt ?? fresh)
    }

    // MARK: - The payload (§10.8, §12.5)

    func testPayloadWithoutIntakeStillDecodes() throws {
        let older = Data(#"{"steps":{"count":6500,"day":"2031-01-29","source":"appleHealth"},"stepGoal":8000}"#.utf8)
        let decoded = try JSONDecoder().decode(PersonalWidgetMetrics.self, from: older)
        XCTAssertNil(decoded.intake)
        XCTAssertEqual(decoded.steps?.count, 6_500)
        let legacy = Data(#"{"recovery":72,"bpm":58,"batteryPct":80,"bonded":true,"updated":0,"personal":{"stepGoal":8000}}"#.utf8)
        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: legacy)
        XCTAssertNil(snapshot.personal?.intake)
    }

    func testPayloadWithNilIntakeEncodesNoIntakeKey() throws {
        let metrics = PersonalWidgetMetrics(steps: .health(value: 6_500, day: today), stepGoal: 8_000)
        let bytes = try JSONEncoder().encode(metrics)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertNil(object["intake"], "flag off: the payload bytes are what they were")
        XCTAssertEqual(Set(object.keys), ["steps", "stepGoal"])
        // The bytes equal those of the same payload decoded from an older build's JSON.
        let reencoded = try JSONEncoder().encode(try JSONDecoder().decode(PersonalWidgetMetrics.self, from: bytes))
        XCTAssertEqual(reencoded, bytes)

        var with = metrics
        with.intake = reading(95)
        let encoded = try JSONEncoder().encode(with)
        XCTAssertEqual(try JSONDecoder().decode(PersonalWidgetMetrics.self, from: encoded), with, "round-trips")
    }

    func testTodayIntakeDropsAnyOtherDay() {
        var metrics = PersonalWidgetMetrics()
        metrics.intake = reading(95, day: today)
        XCTAssertEqual(metrics.todayIntake(now: clockFixture.at(0, hour: 23, minute: 59), calendar: utcCalendar)?.proteinGrams, 95)
        XCTAssertNil(metrics.todayIntake(now: clockFixture.at(1, hour: 0), calendar: utcCalendar),
                     "yesterday's figure is never shown as today's")
        XCTAssertNil(metrics.todayIntake(now: clockFixture.at(-1, hour: 12), calendar: utcCalendar))
        XCTAssertNil(PersonalWidgetMetrics().todayIntake(now: clockFixture.now, calendar: utcCalendar))
    }

    func testIntakeChangeCountsAsRenderedContent() {
        var previous = WidgetSnapshot.unavailable
        previous.personal = PersonalWidgetMetrics(stepGoal: 8_000)
        var withIntake = previous
        withIntake.personal?.intake = reading(95)
        XCTAssertTrue(WidgetSnapshot.renderedContentChanged(from: previous, to: withIntake))
        var changedGrams = withIntake
        changedGrams.personal?.intake = reading(100)
        XCTAssertTrue(WidgetSnapshot.renderedContentChanged(from: withIntake, to: changedGrams))
        var changedTime = withIntake
        changedTime.personal?.intake = reading(95, readAt: clockFixture.at(0, hour: 15, minute: 15))
        XCTAssertTrue(WidgetSnapshot.renderedContentChanged(from: withIntake, to: changedTime), "the time is drawn")
        var same = withIntake
        same.updated = clockFixture.now
        XCTAssertFalse(WidgetSnapshot.renderedContentChanged(from: withIntake, to: same))
    }

    func testReadingCarriesTheShownValues() {
        let r = PersonalIntakeReading.reading(day: today,
                                              progress: IntakeProteinValues(shownGrams: 95, shownFloorGrams: 100,
                                                                            remainingGrams: 5),
                                              source: .quickAdd, readAt: fresh)
        XCTAssertEqual(r.day, today)
        XCTAssertEqual(r.proteinGrams, 95)
        XCTAssertEqual(r.floorGrams, 100)
        XCTAssertEqual(r.source, .quickAdd)
        XCTAssertEqual(r.readAt, fresh)
        XCTAssertEqual(PersonalIntakeReading.staleAfter, 3 * 3_600)
    }

    // MARK: - Widget states (§10.8), one per row

    func testWidgetBelowTheFloor() {
        XCTAssertEqual(reading(95).widgetState, .below(grams: 95, floorGrams: 100, remainingGrams: 5))
        XCTAssertEqual(reading(99).widgetState, .below(grams: 99, floorGrams: 100, remainingGrams: 1))
    }

    func testWidgetAtOrAboveTheFloor() {
        XCTAssertEqual(reading(100).widgetState, .atFloor(grams: 100, floorGrams: 100))
        XCTAssertEqual(reading(105).widgetState, .above(grams: 105, floorGrams: 100, overGrams: 5))
    }

    func testWidgetNoFloorSet() {
        XCTAssertEqual(reading(95, floor: nil).widgetState, .noFloor(grams: 95))
    }

    func testWidgetNothingLoggedToday() {
        XCTAssertEqual(reading(nil).widgetState, .nothingLogged(floorGrams: 100))
        XCTAssertEqual(reading(nil, floor: nil).widgetState, .nothingLogged(floorGrams: nil))
    }

    func testWidgetStale() {
        let health = reading(95, readAt: clockFixture.at(0, hour: 11, minute: 20))
        XCTAssertFalse(health.isStale(now: clockFixture.at(0, hour: 14, minute: 19)))
        XCTAssertTrue(health.isStale(now: clockFixture.at(0, hour: 14, minute: 20)), "at three hours")
        XCTAssertTrue(health.isStale(now: clockFixture.now))
        let quick = reading(95, source: .quickAdd, readAt: clockFixture.at(0, hour: 11, minute: 20))
        XCTAssertFalse(quick.isStale(now: clockFixture.now), "only a Health figure goes stale")
    }

    func testWidgetNotSetUp() {
        let figureWithoutTime = PersonalIntakeReading.reading(
            day: today, progress: IntakeProteinValues(shownGrams: 95, shownFloorGrams: 100, remainingGrams: 5),
            source: .appleHealth, readAt: nil)
        XCTAssertEqual(figureWithoutTime.widgetState, .notSetUp, "a value is never drawn without its time")
        let noSource = PersonalIntakeReading.reading(
            day: today, progress: IntakeProteinValues(shownGrams: 95, shownFloorGrams: 100, remainingGrams: 5),
            source: nil, readAt: fresh)
        XCTAssertEqual(noSource.widgetState, .notSetUp)
    }

    func testWidgetTimelineRefreshesForStaleAndMidnight() {
        let readAt = clockFixture.at(0, hour: 13)
        let health = reading(95, readAt: readAt)
        let midnight = clockFixture.at(1, hour: 0)
        XCTAssertEqual(health.timelineDates(now: clockFixture.now, calendar: utcCalendar),
                       [clockFixture.now, readAt.addingTimeInterval(3 * 3_600), midnight])
        let old = reading(95, readAt: clockFixture.at(0, hour: 9))
        XCTAssertEqual(old.timelineDates(now: clockFixture.now, calendar: utcCalendar), [clockFixture.now, midnight],
                       "a stale time already past is not scheduled")
        XCTAssertEqual(reading(95, source: .quickAdd, readAt: readAt).timelineDates(now: clockFixture.now, calendar: utcCalendar),
                       [clockFixture.now, midnight])
    }

    // MARK: - The presenter's reading (§8.4, §12.3)

    private func input(grams: Double?, source: IntakeSourceSetting = .appleHealth, valueSource: IntakeSource? = nil,
                       readAt: Int?, floor: Double? = 100) -> IntakePresenterInput {
        var input = IntakePresenterInput(source: source, day: today)
        let from = valueSource ?? (source == .quickAdd ? .quickAdd : .appleHealth)
        if let grams {
            input.resolved = ResolvedIntakeDay(day: today,
                                               protein: ResolvedIntakeValue(value: grams, source: from, readAtEpochSeconds: readAt),
                                               energy: ResolvedIntakeValue(value: 1_450, source: from, readAtEpochSeconds: readAt))
        }
        input.floorGrams = floor
        input.targets = IntakeTargets(proteinFloorGrams: floor, energyLowKcal: 2_400, energyHighKcal: 2_600,
                                      energyHardFloorKcal: 2_100)
        input.foodAppName = IntakeFixture.foodApp.name
        input.healthAppNamesOnDay = [IntakeFixture.foodApp.name, IntakeFixture.otherApp.name]
        return input
    }

    private var clock: IntakeClock { IntakeClock(now: clockFixture.now, today: today, minuteOfDay: 920, dayIsOpen: true) }

    func testPresenterReadingCarriesTheShownGramsFloorAndTime() {
        let epoch = Int(fresh.timeIntervalSince1970)
        let values = IntakePresenter.widgetReading(input(grams: 95.6, readAt: epoch), clock: clock, flagEnabled: true)
        XCTAssertEqual(values?.day, today)
        XCTAssertEqual(values?.proteinGrams, 95, "the shown grams, rounded down (§7.4)")
        XCTAssertEqual(values?.floorGrams, 100)
        XCTAssertEqual(values?.remainingGrams, 5)
        XCTAssertEqual(values?.source, .appleHealth)
        XCTAssertEqual(values?.readAt, fresh)
        let nothing = IntakePresenter.widgetReading(input(grams: nil, readAt: nil), clock: clock, flagEnabled: true)
        XCTAssertNil(nothing?.proteinGrams, "nothing logged is published as not measured, never zero")
        XCTAssertEqual(nothing?.floorGrams, 100)
    }

    func testPresenterPublishesNothingWithIntakeOffOrNoSource() {
        let epoch = Int(fresh.timeIntervalSince1970)
        XCTAssertNil(IntakePresenter.widgetReading(input(grams: 95, readAt: epoch), clock: clock, flagEnabled: false))
        XCTAssertNil(IntakePresenter.widgetReading(input(grams: nil, source: .none, readAt: nil), clock: clock,
                                                   flagEnabled: true))
    }

    func testAValueIsNeverPublishedWithoutItsTime() {
        let values = IntakePresenter.widgetReading(input(grams: 95, source: .quickAdd, readAt: nil), clock: clock,
                                                   flagEnabled: true)
        if let values, values.proteinGrams != nil {
            XCTAssertNotNil(values.readAt, "a figure without its time is not published: \(values)")
        }
    }

    func testACsvValueIsNeverPublishedToTheWidget() {
        let values = IntakePresenter.widgetReading(input(grams: 120, valueSource: .nutritionCsv, readAt: nil),
                                                   clock: clock, flagEnabled: true)
        XCTAssertNil(values?.proteinGrams, "a CSV value has no read time and is never published")
    }

    // MARK: - Privacy (§12.8)

    func testWidgetPayloadCarriesNoCaloriesLabelsOrSourceNames() throws {
        let epoch = Int(fresh.timeIntervalSince1970)
        let values = try XCTUnwrap(IntakePresenter.widgetReading(input(grams: 95, readAt: epoch), clock: clock,
                                                                 flagEnabled: true))
        let source = values.source.flatMap { PersonalIntakeReading.Source(rawValue: $0.rawValue) }
        var snapshot = WidgetSnapshot.unavailable
        var metrics = PersonalWidgetMetrics(stepGoal: 8_000)
        metrics.intake = PersonalIntakeReading.reading(
            day: values.day,
            progress: IntakeProteinValues(shownGrams: values.proteinGrams, shownFloorGrams: values.floorGrams,
                                          remainingGrams: values.remainingGrams),
            source: source, readAt: values.readAt)
        snapshot.personal = metrics
        let text = try XCTUnwrap(String(data: JSONEncoder().encode(snapshot), encoding: .utf8))
        XCTAssertTrue(text.contains("\"intake\""), "the reading is in the payload")
        // Names and words, searched in the whole payload. (Figures are checked on the reading below:
        // the payload's dates are numbers that could contain any digits.)
        for forbidden in ["kcal", "calorie", "Calorie", "energy", "Energy",
                          IntakeFixture.foodApp.name, IntakeFixture.foodApp.bundleId, IntakeFixture.otherApp.name,
                          IntakeFixture.otherApp.bundleId, IntakeFixture.preset.label, IntakeFixture.supplementName,
                          "Did you take", "supplement"] {
            XCTAssertFalse(text.contains(forbidden), "\(forbidden) leaked into the widget payload: \(text)")
        }
        // The reading's own keys: no room for anything else.
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(metrics.intake)) as? [String: Any])
        XCTAssertTrue(Set(object.keys).isSubset(of: ["day", "proteinGrams", "floorGrams", "source", "readAt"]),
                      "\(object.keys.sorted())")
        XCTAssertEqual(object["proteinGrams"] as? Int, 95)
        XCTAssertEqual(object["floorGrams"] as? Int, 100)
        for (key, value) in object where key != "readAt" {
            for figure in ["1450", "2400", "2600", "2100", "150"] {
                XCTAssertFalse("\(value)".contains(figure), "\(key) carries an energy figure: \(value)")
            }
        }
    }
}
