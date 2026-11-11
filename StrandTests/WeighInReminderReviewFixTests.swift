import XCTest
import UserNotifications
import StrandAnalytics
@testable import Strand

// Stage 1 (weigh-in and scorecard): the three confirmed review findings on the weekly reminder
// (8, 14 and 15 of build/personal/stage1-screens-confirmed-findings.md), which are one cluster:
// nothing reconciles when the app becomes active although two comments say so, and the reminder's
// in-memory latest weigh-in day is whatever the last caller of `reconcile` in this process passed.
// Written before the fix exists. The other findings are in CutScorecardReviewFixTests.swift.
//
// API ASSUMED BY THESE TESTS (new, in Strand/System/WeighInReminder.swift)
//
//     extension WeighInReminder {
//         /// The app became active. Returns at once, before any call to the notification centre
//         /// and without evaluating `latestWeighInDay`, unless the scorecard flag and the
//         /// reminder switch are both on. Otherwise `reconcile(latestWeighInDay:)` with its value.
//         /// Called from the `.active` scene-phase handler in StrandiOS/App.
//         func reconcileOnActive(latestWeighInDay: @MainActor () async -> String?) async
//
//         /// `setSchedule(weekday:minuteOfDay:)` that also carries the local day of the newest
//         /// weight, so the new request is right whoever last called `reconcile` in this process.
//         func setSchedule(weekday: Int, minuteOfDay: Int, latestWeighInDay: String?) async
//     }
//
// Behaviour pinned without a new member: two overlapping reconciles never leave the repeating
// request and the dated ones pending together (finding 15, the overlap).
//
// Not pinned here: finding 15's "a weigh-in saved from Settings, with the shared model never
// loaded, reaches the reminder". Both suggested fixes are view wiring (SettingsView's revision
// observer, or the sheet's save path), left to review and the simulator pass.
//
// No notification is scheduled by these tests: the reminder talks to a protocol, and the fake
// keeps the requests in memory. Synthetic values only.
@MainActor
final class WeighInReminderReviewFixTests: XCTestCase {

    // MARK: - Harness

    /// Counts every call, and can hold the first `pendingRequests()` open.
    private final class FakeCenter: WeighInReminderCenter {
        var status: UNAuthorizationStatus = .authorized
        private(set) var pending: [UNNotificationRequest] = []
        private(set) var calls = 0
        var holdsFirstPendingQuery = false
        private(set) var isHoldingAQuery = false
        private var held: CheckedContinuation<Void, Never>?

        func resetCalls() { calls = 0 }

        func release() {
            holdsFirstPendingQuery = false
            held?.resume()
            held = nil
        }

        func authorizationStatus() async -> UNAuthorizationStatus {
            calls += 1
            return status
        }

        func requestAuthorization() async -> Bool {
            calls += 1
            return status == .authorized
        }

        func add(_ request: UNNotificationRequest) async {
            calls += 1
            pending.removeAll { $0.identifier == request.identifier }
            pending.append(request)
        }

        func removePendingRequests(withIdentifiers identifiers: [String]) {
            calls += 1
            pending.removeAll { identifiers.contains($0.identifier) }
        }

        func pendingRequests() async -> [UNNotificationRequest] {
            calls += 1
            if holdsFirstPendingQuery {
                holdsFirstPendingQuery = false
                isHoldingAQuery = true
                await withCheckedContinuation { held = $0 }
                isHoldingAQuery = false
            }
            return pending
        }
    }

    private final class Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private struct Harness {
        let center: FakeCenter
        let defaults: UserDefaults
        let settings: CutScorecardSettings
        let clock: Clock
        let reminder: WeighInReminder
    }

    private let weeklyId = "weigh-in-reminder"
    private var suites: [String] = []

    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    override func tearDown() {
        for name in suites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        suites = []
        super.tearDown()
    }

    private func at(_ day: String, _ hour: Int, _ minute: Int = 0) -> Date {
        ScorecardScreenFixture.date(day).addingTimeInterval(Double(hour * 3_600 + minute * 60))
    }

    /// Wednesday 29 January 2031, 07:05 UTC. `flag` nil: the key was never written.
    private func makeHarness(flag: Bool? = true) throws -> Harness {
        let name = "WeighInReminderReviewFixTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        suites.append(name)
        if let flag { defaults.set(flag, forKey: "noop.cutScorecardEnabled") }
        let settings = CutScorecardSettings(defaults: defaults)
        let center = FakeCenter()
        let clock = Clock(at("2031-01-29", 7, 5))
        return Harness(center: center, defaults: defaults, settings: settings, clock: clock,
                       reminder: reminder(center: center, settings: settings, clock: clock))
    }

    /// A reminder over the same centre and settings: what a relaunch builds.
    private func reminder(center: FakeCenter, settings: CutScorecardSettings, clock: Clock) -> WeighInReminder {
        let calendar = utc
        return WeighInReminder(center: center, settings: settings, now: { clock.now }, calendar: { calendar })
    }

    private func relaunched(_ h: Harness) -> WeighInReminder {
        reminder(center: h.center, settings: h.settings, clock: h.clock)
    }

    private func repeats(_ request: UNNotificationRequest) -> Bool {
        (request.trigger as? UNCalendarNotificationTrigger)?.repeats == true
    }

    private func fires(_ h: Harness) -> [Date] {
        h.center.pending.compactMap { request -> Date? in
            guard let trigger = request.trigger as? UNCalendarNotificationTrigger else { return nil }
            return utc.nextDate(after: h.clock.now, matching: trigger.dateComponents, matchingPolicy: .nextTime)
        }.sorted()
    }

    /// Exactly one request is pending: the repeating weekly one.
    private func assertOnlyTheWeeklyRequest(_ h: Harness, weekday: Int, hour: Int, minute: Int = 0,
                                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(h.center.pending.map(\.identifier), [weeklyId], file: file, line: line)
        let trigger = h.center.pending.first?.trigger as? UNCalendarNotificationTrigger
        XCTAssertEqual(trigger?.repeats, true, file: file, line: line)
        XCTAssertEqual(trigger?.dateComponents.weekday, weekday, file: file, line: line)
        XCTAssertEqual(trigger?.dateComponents.hour, hour, file: file, line: line)
        XCTAssertEqual(trigger?.dateComponents.minute, minute, file: file, line: line)
    }

    /// The week has its weigh-in: no repeating request, and nothing fires before next Monday.
    private func assertThisWeekIsSilent(_ h: Harness, nextMonday: String, file: StaticString = #filePath,
                                        line: UInt = #line) {
        XCTAssertFalse(h.center.pending.contains(where: repeats), "no repeating request is pending",
                       file: file, line: line)
        XCTAssertFalse(h.center.pending.contains { $0.identifier == weeklyId }, file: file, line: line)
        XCTAssertFalse(fires(h).contains { $0 < at(nextMonday, 0) },
                       "nothing fires in the rest of a week that has its weigh-in: \(fires(h))", file: file, line: line)
        XCTAssertFalse(fires(h).isEmpty, "the reminder is still due in a later week", file: file, line: line)
    }

    private func waitUntil(_ what: String, file: StaticString = #filePath, line: UInt = #line,
                           _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(10)
        while !condition() {
            if Date() > deadline {
                XCTFail("timed out waiting for \(what)", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    // MARK: - Findings 8 and 14: reconcile when the app becomes active

    /// Flag off, or reminder off: becoming active costs nothing. No call reaches the notification
    /// centre and the newest weigh-in is not looked up, so a flag-off launch is as it was before.
    func testFinding8BecomingActiveDoesNothingWhileTheFeatureOrTheReminderIsOff() async throws {
        let cases: [(name: String, flag: Bool?, reminderOn: Bool)] = [
            ("flag off, reminder stored on", false, true),
            ("flag never written, reminder stored on", nil, true),
            ("flag on, reminder off", true, false),
            ("both off", false, false),
        ]
        for testCase in cases {
            let h = try makeHarness(flag: testCase.flag)
            h.settings.reminderEnabled = testCase.reminderOn
            h.center.resetCalls()
            var lookups = 0
            await h.reminder.reconcileOnActive {
                lookups += 1
                return "2031-01-29"
            }
            XCTAssertEqual(h.center.calls, 0, "\(testCase.name): the notification centre is not touched")
            XCTAssertEqual(lookups, 0, "\(testCase.name): the latest weigh-in is not read")
            XCTAssertEqual(h.center.pending.count, 0, testCase.name)
        }
    }

    /// The case the reminder exists for. A weigh-in in week W swaps the repeating request for four
    /// dated ones. With no scorecard surface opened since, only becoming active can bring the
    /// repeating request back before those four run out.
    func testFinding14BecomingActiveRestoresTheWeeklyRequestInAWeekWithNoWeighIn() async throws {
        let h = try makeHarness()
        await h.reminder.setEnabled(true)
        await h.reminder.reconcile(latestWeighInDay: "2031-01-29")
        assertThisWeekIsSilent(h, nextMonday: "2031-02-03")

        h.clock.now = at("2031-03-05", 7, 5)            // five weeks on; the newest weigh-in is unchanged
        var lookups = 0
        await relaunched(h).reconcileOnActive {
            lookups += 1
            return "2031-01-29"
        }
        XCTAssertEqual(lookups, 1)
        assertOnlyTheWeeklyRequest(h, weekday: 7, hour: 8)
        XCTAssertEqual(fires(h), [at("2031-03-08", 8)], "this Saturday")
    }

    /// And in a week that has its weigh-in, becoming active after a relaunch keeps it silent.
    func testFinding14BecomingActiveKeepsAWeekWithAWeighInSilent() async throws {
        let h = try makeHarness()
        await h.reminder.setEnabled(true)
        XCTAssertEqual(fires(h), [at("2031-02-01", 8)], "before the weigh-in it would fire this Saturday")

        await relaunched(h).reconcileOnActive { "2031-01-29" }
        assertThisWeekIsSilent(h, nextMonday: "2031-02-03")
        XCTAssertEqual(fires(h).first, at("2031-02-08", 8), "next Saturday")
        XCTAssertTrue(h.settings.reminderEnabled, "the switch is untouched")
    }

    /// The comments in WeighInReminder.swift say the app reconciles every time it becomes active.
    /// The call site is in StrandiOS, which this bundle cannot load: held by its source.
    func testFinding8TheAppCallsReconcileOnActiveFromItsScenePhaseHandler() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let app = root.appendingPathComponent("StrandiOS/App")
        let files = try FileManager.default.contentsOfDirectory(at: app, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "the test's premise: StrandiOS/App was found at \(app.path)")
        let callers = try files.filter {
            let text = try String(contentsOf: $0, encoding: .utf8)
            return text.contains("reconcileOnActive") && text.contains(".active")
        }
        XCTAssertFalse(callers.isEmpty, "a scene-phase `.active` handler under StrandiOS/App calls reconcileOnActive")
    }

    // MARK: - Finding 15: the latest weigh-in day does not depend on who called reconcile

    /// Weighed on Wednesday, then relaunched: the new process has never been told the latest
    /// weigh-in day. Changing the reminder's day or time must not bring this week's reminder back.
    func testFinding15AScheduleChangeCarriesTheLatestWeighInDay() async throws {
        let h = try makeHarness()
        await h.reminder.setEnabled(true)
        await h.reminder.reconcile(latestWeighInDay: "2031-01-29")
        assertThisWeekIsSilent(h, nextMonday: "2031-02-03")

        await relaunched(h).setSchedule(weekday: 6, minuteOfDay: 9 * 60, latestWeighInDay: "2031-01-29")
        XCTAssertEqual(h.settings.reminderWeekday, 6)
        XCTAssertEqual(h.settings.reminderMinuteOfDay, 9 * 60)
        assertThisWeekIsSilent(h, nextMonday: "2031-02-03")
        XCTAssertEqual(fires(h).first, at("2031-02-07", 9), "next Friday at 09:00, not this one")
    }

    func testFinding15AScheduleChangeInAWeekWithNoWeighInSchedulesTheWeeklyRequest() async throws {
        for latest in [nil, "2031-01-22"] as [String?] {
            let h = try makeHarness()
            await h.reminder.setEnabled(true)
            await h.reminder.reconcile(latestWeighInDay: "2031-01-29")      // stale: that reading was deleted since
            await relaunched(h).setSchedule(weekday: 6, minuteOfDay: 9 * 60, latestWeighInDay: latest)
            assertOnlyTheWeeklyRequest(h, weekday: 6, hour: 9)
            XCTAssertEqual(fires(h), [at("2031-01-31", 9)], "this Friday: \(String(describing: latest))")
        }
    }

    func testFinding15AScheduleChangeWhileTheReminderIsOffSchedulesNothing() async throws {
        let h = try makeHarness()
        await h.reminder.setSchedule(weekday: 6, minuteOfDay: 9 * 60, latestWeighInDay: nil)
        XCTAssertEqual(h.settings.reminderWeekday, 6)
        XCTAssertEqual(h.settings.reminderMinuteOfDay, 9 * 60)
        XCTAssertEqual(h.center.pending.count, 0)
    }

    /// A stale reconcile (no weigh-in) is suspended on the notification centre while a fresh one
    /// (this week's weigh-in) runs. Whichever way the two are ordered, the stale one must not put
    /// the repeating request back beside the dated ones.
    func testFinding15OverlappingReconcilesNeverLeaveTheWeeklyAndTheDatedRequestsPendingTogether() async throws {
        let h = try makeHarness()
        await h.reminder.setEnabled(true)
        await h.reminder.reconcile(latestWeighInDay: "2031-01-29")
        assertThisWeekIsSilent(h, nextMonday: "2031-02-03")

        h.center.holdsFirstPendingQuery = true
        let reminder = h.reminder
        var staleFinished = false
        let stale = Task {
            await reminder.reconcile(latestWeighInDay: nil)
            staleFinished = true
        }
        await waitUntil("the stale reconcile to reach the notification centre") {
            h.center.isHoldingAQuery || staleFinished
        }
        let fresh = Task { await reminder.reconcile(latestWeighInDay: "2031-01-29") }
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 50_000_000)
        h.center.release()
        await stale.value
        await fresh.value

        assertThisWeekIsSilent(h, nextMonday: "2031-02-03")
    }
}
