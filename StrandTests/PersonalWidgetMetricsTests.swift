import Foundation
import XCTest

final class PersonalWidgetMetricsTests: XCTestCase {
    private func calendar(_ zone: String = "UTC") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    func testEstimateRejectsInvalidValuesAndPreservesRealZero() {
        for value in [-1, Double.nan, .infinity, Double(Int.max)] {
            XCTAssertNil(PersonalStepReading.estimate(value: value, day: "2026-10-21"))
        }
        XCTAssertEqual(PersonalStepReading.estimate(value: 0, day: "2026-10-21")?.count, 0)
        XCTAssertEqual(PersonalStepReading.estimate(value: 512.4, day: "2026-10-21")?.count, 512)
    }

    func testEstimateNeverInventsMeasurementTime() {
        let reading = PersonalStepReading.estimate(value: 500, day: "2026-10-21")
        XCTAssertEqual(reading?.source, .whoop4MotionEstimate)
        XCTAssertNil(reading?.observedAt)
    }

    func testGoalRequiresExplicitValidPreferenceEvenWithoutSteps() {
        XCTAssertNil(PersonalWidgetMetrics().stepGoal)
        for goal in [0, -1, 50_001, Int.max] {
            XCTAssertNil(PersonalWidgetMetrics(stepGoal: goal).stepGoal)
        }
        XCTAssertEqual(PersonalWidgetMetrics(stepGoal: 10_000).stepGoal, 10_000)
        XCTAssertNil(PersonalWidgetMetrics(stepGoal: 10_000).steps)
    }

    func testYesterdayStepsExpireWhenAppHasNotRepublished() {
        let metrics = PersonalWidgetMetrics(steps: .estimate(value: 1200, day: "2026-10-21"), stepGoal: 8000)
        XCTAssertEqual(metrics.todaySteps(now: date("2026-10-21T23:59:00Z"), calendar: calendar())?.count, 1200)
        XCTAssertNil(metrics.todaySteps(now: date("2026-10-22T00:00:00Z"), calendar: calendar()))
        XCTAssertEqual(metrics.stepGoal, 8000)
    }

    func testStepDayUsesLocalMidnightInsteadOfUTC() {
        let now = date("2026-10-21T19:00:00Z")
        XCTAssertEqual(PersonalWidgetMetrics.dayKey(now, calendar: calendar("Asia/Kolkata")), "2026-10-22")
        let metrics = PersonalWidgetMetrics(steps: .estimate(value: 12, day: "2026-10-21"))
        XCTAssertNil(metrics.todaySteps(now: now, calendar: calendar("Asia/Kolkata")))
        XCTAssertNotNil(metrics.todaySteps(now: now, calendar: calendar()))
    }

    func testSleepRequiresActualStageDurationAndSensibleBounds() {
        let start = date("2026-10-20T22:00:00Z")
        let end = date("2026-10-21T06:00:00Z")
        for minutes in [0, -1, .nan, .infinity, 482] {
            XCTAssertNil(PersonalSleepReading.reading(asleepMinutes: minutes, start: start, end: end,
                                                     source: .localEstimate, incomplete: true, userEdited: false))
        }
        XCTAssertNil(PersonalSleepReading.reading(asleepMinutes: 20, start: end, end: start,
                                                 source: .localEstimate, incomplete: false, userEdited: false))
        let reading = PersonalSleepReading.reading(asleepMinutes: 420, start: start, end: end,
                                                  source: .localEstimate, incomplete: true, userEdited: true)
        XCTAssertEqual(reading?.asleepMinutes, 420)
        XCTAssertEqual(reading?.end, end)
        XCTAssertEqual(reading?.source, .localEstimate)
        XCTAssertEqual(reading?.incomplete, true)
        XCTAssertEqual(reading?.userEdited, true)
    }

    func testFutureAndOldSleepNeverAppearAsRecentSleep() {
        let reading = PersonalSleepReading.reading(asleepMinutes: 420,
            start: date("2026-10-20T22:00:00Z"), end: date("2026-10-21T06:00:00Z"),
            source: .whoopImport, incomplete: false, userEdited: false)
        let metrics = PersonalWidgetMetrics(sleep: reading)
        XCTAssertNil(metrics.recentSleep(now: date("2026-10-21T05:00:00Z"), calendar: calendar()))
        XCTAssertNotNil(metrics.recentSleep(now: date("2026-10-21T07:00:00Z"), calendar: calendar()))
        XCTAssertNotNil(metrics.recentSleep(now: date("2026-10-22T21:00:00Z"), calendar: calendar()))
        XCTAssertNil(metrics.recentSleep(now: date("2026-10-23T00:00:00Z"), calendar: calendar()))
    }

    func testRecentSleepUsesCalendarDaysAcrossDaylightSaving() {
        let reading = PersonalSleepReading.reading(asleepMinutes: 420,
            start: date("2026-10-31T22:00:00-04:00"), end: date("2026-11-01T06:00:00-05:00"),
            source: .localEstimate, incomplete: false, userEdited: false)
        let metrics = PersonalWidgetMetrics(sleep: reading)
        XCTAssertNotNil(metrics.recentSleep(now: date("2026-11-02T00:01:00-05:00"),
                                          calendar: calendar("America/New_York")))
    }

    func testLegacySnapshotDecodesWithNoPersonalFields() throws {
        let legacy = Data(#"{"recovery":72,"bpm":58,"batteryPct":80,"bonded":true,"updated":0}"#.utf8)
        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: legacy)
        XCTAssertEqual(snapshot.recovery, 72)
        XCTAssertNil(snapshot.personal)
    }

    func testSnapshotRoundTripPreservesProvenanceAndUnknownFreshness() throws {
        var snapshot = WidgetSnapshot.unavailable
        snapshot.personal = PersonalWidgetMetrics(steps: .estimate(value: 500, day: "2026-10-21"), stepGoal: 8000)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded, snapshot)
        XCTAssertNil(decoded.personal?.steps?.observedAt)
    }

    func testSnapshotRoundTripPreservesSleepSourceQualityAndWakeEndpoint() throws {
        var snapshot = WidgetSnapshot.unavailable
        let wake = date("2026-10-21T07:00:00Z")
        snapshot.personal = PersonalWidgetMetrics(sleep: .reading(asleepMinutes: 400,
            start: date("2026-10-20T22:00:00Z"), end: wake,
            source: .whoopImport, incomplete: true, userEdited: true))
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded.personal?.sleep?.source, .whoopImport)
        XCTAssertEqual(decoded.personal?.sleep?.incomplete, true)
        XCTAssertEqual(decoded.personal?.sleep?.userEdited, true)
        XCTAssertEqual(decoded.personal?.sleep?.end, wake)
    }

    func testRealLiveUpdateHelperKeepsPayloadAndDoesNotFreshenExpiredSteps() {
        var previous = WidgetSnapshot.unavailable
        previous.personal = PersonalWidgetMetrics(steps: .estimate(value: 500, day: "2026-10-21"), stepGoal: 8000)
        let now = date("2026-10-22T01:00:00Z")
        let next = previous.updatingLive(bpm: 75, batteryPct: 40, bonded: true, at: now)
        XCTAssertEqual(next.personal, previous.personal)
        XCTAssertEqual(next.bpm, 75)
        XCTAssertEqual(next.batteryPct, 40)
        XCTAssertEqual(next.updated, now)
        XCTAssertNil(next.personal?.steps?.observedAt)
        XCTAssertNil(next.personal?.todaySteps(now: now, calendar: calendar()))
    }

    func testMetricOrGoalChangeTriggersReloadButLiveTimestampDoesNot() {
        var previous = WidgetSnapshot.unavailable
        previous.personal = PersonalWidgetMetrics(steps: .estimate(value: 500, day: "2026-10-21"))
        var liveUpdate = previous
        liveUpdate.updated = date("2026-10-21T20:00:00Z")
        XCTAssertFalse(WidgetSnapshot.renderedContentChanged(from: previous, to: liveUpdate))
        XCTAssertEqual(liveUpdate.personal, previous.personal)
        var changedGoal = previous
        changedGoal.personal?.stepGoal = 8000
        XCTAssertTrue(WidgetSnapshot.renderedContentChanged(from: previous, to: changedGoal))
        var changedCount = previous
        changedCount.personal?.steps = .estimate(value: 501, day: "2026-10-21")
        XCTAssertTrue(WidgetSnapshot.renderedContentChanged(from: previous, to: changedCount))
    }
}
