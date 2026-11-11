import XCTest
import UserNotifications
import StrandAnalytics
@testable import Strand

// Stage 1 (weigh-in and scorecard), work package 1-9: the weekly reminder. Specification §9.2
// (settings keys), §10.6, §10.10, §12.3 and §17 (title and body in force; off by default).
// Written before the implementation exists.
//
// No notification is scheduled by these tests: the reminder talks to a protocol, and the tests
// give it a fake that keeps the requests in memory the way the notification centre does (a request
// added under an identifier already pending replaces it).
//
// API ASSUMED BY THESE TESTS (new, in Strand/System/WeighInReminder.swift)
//
//     /// What the reminder needs from the notification centre. The app's conformance wraps
//     /// `UNUserNotificationCenter.current()`.
//     protocol WeighInReminderCenter: AnyObject {
//         func authorizationStatus() async -> UNAuthorizationStatus
//         /// Shows the system prompt. True when the owner allowed notifications.
//         func requestAuthorization() async -> Bool
//         func add(_ request: UNNotificationRequest) async
//         func removePendingRequests(withIdentifiers identifiers: [String])
//         func pendingRequests() async -> [UNNotificationRequest]
//     }
//
//     @MainActor final class WeighInReminder {
//         enum Outcome: Equatable { case scheduled, denied, off }
//
//         init(center: WeighInReminderCenter, settings: CutScorecardSettings,
//              now: @escaping () -> Date = { Date() },
//              calendar: @escaping () -> Calendar = { Calendar.current })
//
//         /// `settings.reminderEnabled`.
//         var isEnabled: Bool { get }
//
//         /// On: schedules when notifications are allowed (asking once if that was never decided)
//         /// and returns `.scheduled`; otherwise leaves the switch off and returns `.denied`.
//         /// Off: removes the request and returns `.off`.
//         @discardableResult func setEnabled(_ on: Bool) async -> Outcome
//
//         /// Stores the weekday (1 = Sunday … 7 = Saturday) and the minute after local midnight,
//         /// and replaces the pending request when the reminder is on.
//         func setSchedule(weekday: Int, minuteOfDay: Int) async
//
//         /// Brings the pending request into line with the flag, the switch, and the latest
//         /// weigh-in. Called after a weigh-in is saved or deleted, when the flag changes, and
//         /// when the app becomes active. `latestWeighInDay` is the local day of the newest weight.
//         func reconcile(latestWeighInDay: String?) async
//     }
//
// Behaviour assumed where §10.6 leaves it open:
//
//  1. The request is one `UNCalendarNotificationTrigger` with `repeats: true` whose components
//     are the weekday, hour and minute, and nothing else.
//  2. "Not delivered in a week that already has a weigh-in" is asserted on what is pending, not on
//     how it is arranged: after `reconcile` with a weigh-in in the current Monday-to-Sunday week,
//     nothing pending fires before next Monday, and something pending fires in the week after.
//     Once a new week begins with no weigh-in, `reconcile` restores the single repeating request.
//  3. With the scorecard flag off nothing is ever pending. Whether the stored switch is also
//     cleared is not asserted.
//
// Synthetic values only.
@MainActor
final class WeighInReminderTests: XCTestCase {

    // MARK: - Harness

    private final class FakeCenter: WeighInReminderCenter {
        var status: UNAuthorizationStatus = .authorized
        var grantsWhenAsked = true
        private(set) var authorizationRequests = 0
        private(set) var pending: [UNNotificationRequest] = []
        private(set) var mostPendingAtOnce = 0
        private(set) var added: [UNNotificationRequest] = []

        func authorizationStatus() async -> UNAuthorizationStatus { status }

        func requestAuthorization() async -> Bool {
            authorizationRequests += 1
            status = grantsWhenAsked ? .authorized : .denied
            return grantsWhenAsked
        }

        func add(_ request: UNNotificationRequest) async {
            pending.removeAll { $0.identifier == request.identifier }
            pending.append(request)
            added.append(request)
            mostPendingAtOnce = max(mostPendingAtOnce, pending.count)
        }

        func removePendingRequests(withIdentifiers identifiers: [String]) {
            pending.removeAll { identifiers.contains($0.identifier) }
        }

        func pendingRequests() async -> [UNNotificationRequest] { pending }
    }

    /// Records which keys were written.
    private final class RecordingDefaults: UserDefaults {
        var written: [String] = []
        override func set(_ value: Any?, forKey defaultName: String) {
            written.append(defaultName)
            super.set(value, forKey: defaultName)
        }
        override func set(_ value: Int, forKey defaultName: String) {
            written.append(defaultName)
            super.set(value, forKey: defaultName)
        }
        override func set(_ value: Bool, forKey defaultName: String) {
            written.append(defaultName)
            super.set(value, forKey: defaultName)
        }
        override func removeObject(forKey defaultName: String) {
            written.append(defaultName)
            super.removeObject(forKey: defaultName)
        }
    }

    private final class Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private struct Harness {
        let center: FakeCenter
        let defaults: RecordingDefaults
        let settings: CutScorecardSettings
        let clock: Clock
        let reminder: WeighInReminder
    }

    private let title = "Weekly weigh-in"
    private let body = "Weight, then waist. It takes under a minute."
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

    /// Wednesday 29 January 2031, 07:05 UTC, unless given. `flag` nil: the key was never written.
    private func makeHarness(flag: Bool? = true, now: Date? = nil) throws -> Harness {
        let name = "WeighInReminderTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(RecordingDefaults(suiteName: name))
        suites.append(name)
        if let flag { defaults.set(flag, forKey: "noop.cutScorecardEnabled") }
        let settings = CutScorecardSettings(defaults: defaults)
        let center = FakeCenter()
        let clock = Clock(now ?? at("2031-01-29", 7, 5))
        let calendar = utc
        let reminder = WeighInReminder(center: center, settings: settings, now: { clock.now },
                                       calendar: { calendar })
        defaults.written = []
        return Harness(center: center, defaults: defaults, settings: settings, clock: clock, reminder: reminder)
    }

    private func calendarTrigger(_ request: UNNotificationRequest, file: StaticString = #filePath,
                                 line: UInt = #line) throws -> UNCalendarNotificationTrigger {
        try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger, "a calendar trigger", file: file, line: line)
    }

    /// Asserts the one pending request is the repeating weekly one for a weekday and minute.
    private func assertOneWeeklyRequest(_ h: Harness, weekday: Int, hour: Int, minute: Int,
                                        file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(h.center.pending.count, 1, "exactly one request is pending", file: file, line: line)
        let request = try XCTUnwrap(h.center.pending.first, file: file, line: line)
        let trigger = try calendarTrigger(request, file: file, line: line)
        XCTAssertTrue(trigger.repeats, "it repeats", file: file, line: line)
        XCTAssertEqual(trigger.dateComponents.weekday, weekday, file: file, line: line)
        XCTAssertEqual(trigger.dateComponents.hour, hour, file: file, line: line)
        XCTAssertEqual(trigger.dateComponents.minute, minute, file: file, line: line)
        XCTAssertNil(trigger.dateComponents.year, "weekly: no date is pinned", file: file, line: line)
        XCTAssertNil(trigger.dateComponents.month, file: file, line: line)
        XCTAssertNil(trigger.dateComponents.day, file: file, line: line)
        XCTAssertEqual(request.content.title, title, file: file, line: line)
        XCTAssertEqual(request.content.body, body, file: file, line: line)
    }

    /// When a pending request next fires after `now`, in the injected calendar.
    private func nextFire(_ request: UNNotificationRequest, after now: Date) -> Date? {
        if let trigger = request.trigger as? UNCalendarNotificationTrigger {
            return utc.nextDate(after: now, matching: trigger.dateComponents, matchingPolicy: .nextTime)
        }
        if let trigger = request.trigger as? UNTimeIntervalNotificationTrigger {
            return now.addingTimeInterval(trigger.timeInterval)
        }
        return nil
    }

    private func fires(_ h: Harness) -> [Date] {
        h.center.pending.compactMap { nextFire($0, after: h.clock.now) }.sorted()
    }

    // MARK: - §9.2 defaults

    func testReminderIsOffByDefault() async throws {
        let h = try makeHarness()
        XCTAssertFalse(h.reminder.isEnabled)
        XCTAssertFalse(h.settings.reminderEnabled)
        XCTAssertEqual(h.settings.reminderWeekday, 7, "Saturday")
        XCTAssertEqual(h.settings.reminderMinuteOfDay, 480, "08:00")

        await h.reminder.reconcile(latestWeighInDay: nil)
        await h.reminder.reconcile(latestWeighInDay: "2031-01-29")
        XCTAssertEqual(h.center.pending.count, 0, "nothing is scheduled until the owner turns it on")
        XCTAssertEqual(h.center.added.count, 0)
        XCTAssertEqual(h.center.authorizationRequests, 0, "and nobody is asked for permission")
        XCTAssertEqual(h.defaults.written, [], "reading the defaults writes nothing")
        XCTAssertFalse(h.reminder.isEnabled)
    }

    // MARK: - Enabling

    func testEnablingSchedulesOneWeeklyRequest() async throws {
        let h = try makeHarness()
        let outcome = await h.reminder.setEnabled(true)
        XCTAssertEqual(outcome, .scheduled)
        XCTAssertTrue(h.reminder.isEnabled)
        XCTAssertTrue(h.settings.reminderEnabled)
        try assertOneWeeklyRequest(h, weekday: 7, hour: 8, minute: 0)
        XCTAssertEqual(h.center.authorizationRequests, 0, "already allowed: no prompt")
        XCTAssertEqual(fires(h), [at("2031-02-01", 8)], "the coming Saturday at 08:00")
    }

    func testEnablingUsesTheStoredWeekdayAndMinute() async throws {
        let h = try makeHarness()
        h.settings.reminderWeekday = 4
        h.settings.reminderMinuteOfDay = 6 * 60 + 30
        await h.reminder.setEnabled(true)
        try assertOneWeeklyRequest(h, weekday: 4, hour: 6, minute: 30)
    }

    func testEnablingTwiceLeavesOneRequest() async throws {
        let h = try makeHarness()
        await h.reminder.setEnabled(true)
        await h.reminder.setEnabled(true)
        await h.reminder.reconcile(latestWeighInDay: nil)
        try assertOneWeeklyRequest(h, weekday: 7, hour: 8, minute: 0)
        XCTAssertEqual(h.center.mostPendingAtOnce, 1, "never two at once")
    }

    func testEnablingAsksOnceWhenPermissionWasNeverDecided() async throws {
        let h = try makeHarness()
        h.center.status = .notDetermined
        let outcome = await h.reminder.setEnabled(true)
        XCTAssertEqual(outcome, .scheduled)
        XCTAssertEqual(h.center.authorizationRequests, 1)
        XCTAssertTrue(h.reminder.isEnabled)
        try assertOneWeeklyRequest(h, weekday: 7, hour: 8, minute: 0)
    }

    func testProvisionalPermissionIsEnough() async throws {
        let h = try makeHarness()
        h.center.status = .provisional
        let outcome = await h.reminder.setEnabled(true)
        XCTAssertEqual(outcome, .scheduled)
        XCTAssertEqual(h.center.authorizationRequests, 0)
        XCTAssertEqual(h.center.pending.count, 1)
    }

    // MARK: - Denied permission

    func testDeniedPermissionLeavesTheSwitchOff() async throws {
        let h = try makeHarness()
        h.center.status = .denied
        let outcome = await h.reminder.setEnabled(true)
        XCTAssertEqual(outcome, .denied, "the caller is told, so Settings can say notifications are off for NOOP")
        XCTAssertFalse(h.reminder.isEnabled)
        XCTAssertFalse(h.settings.reminderEnabled, "a switch that cannot fire is not stored as on")
        XCTAssertEqual(h.center.pending.count, 0)
        XCTAssertEqual(h.center.added.count, 0)
        XCTAssertEqual(h.center.authorizationRequests, 0, "a denied permission cannot be asked for again")
    }

    func testRefusingThePromptLeavesTheSwitchOff() async throws {
        let h = try makeHarness()
        h.center.status = .notDetermined
        h.center.grantsWhenAsked = false
        let outcome = await h.reminder.setEnabled(true)
        XCTAssertEqual(outcome, .denied)
        XCTAssertEqual(h.center.authorizationRequests, 1)
        XCTAssertFalse(h.reminder.isEnabled)
        XCTAssertFalse(h.settings.reminderEnabled)
        XCTAssertEqual(h.center.pending.count, 0)
    }

    func testAllowingLaterLetsTheReminderBeTurnedOn() async throws {
        let h = try makeHarness()
        h.center.status = .denied
        await h.reminder.setEnabled(true)
        h.center.status = .authorized
        let outcome = await h.reminder.setEnabled(true)
        XCTAssertEqual(outcome, .scheduled)
        try assertOneWeeklyRequest(h, weekday: 7, hour: 8, minute: 0)
    }

    // MARK: - Changing the time

    func testChangingTheTimeReplacesTheRequest() async throws {
        let h = try makeHarness()
        await h.reminder.setEnabled(true)
        await h.reminder.setSchedule(weekday: 2, minuteOfDay: 6 * 60 + 45)
        XCTAssertEqual(h.settings.reminderWeekday, 2)
        XCTAssertEqual(h.settings.reminderMinuteOfDay, 405)
        try assertOneWeeklyRequest(h, weekday: 2, hour: 6, minute: 45)
        XCTAssertEqual(h.center.mostPendingAtOnce, 1, "the old request is replaced, never joined by a second")

        await h.reminder.setSchedule(weekday: 1, minuteOfDay: 23 * 60 + 59)
        try assertOneWeeklyRequest(h, weekday: 1, hour: 23, minute: 59)
        await h.reminder.setSchedule(weekday: 7, minuteOfDay: 0)
        try assertOneWeeklyRequest(h, weekday: 7, hour: 0, minute: 0)
        XCTAssertEqual(h.center.mostPendingAtOnce, 1)
        XCTAssertTrue(h.reminder.isEnabled)
    }

    func testChangingTheTimeWhileOffStoresItAndSchedulesNothing() async throws {
        let h = try makeHarness()
        await h.reminder.setSchedule(weekday: 3, minuteOfDay: 7 * 60)
        XCTAssertEqual(h.settings.reminderWeekday, 3)
        XCTAssertEqual(h.settings.reminderMinuteOfDay, 420)
        XCTAssertEqual(h.center.pending.count, 0)
        XCTAssertEqual(h.center.added.count, 0)
        XCTAssertFalse(h.reminder.isEnabled)

        await h.reminder.setEnabled(true)
        try assertOneWeeklyRequest(h, weekday: 3, hour: 7, minute: 0)
    }

    // MARK: - Disabling

    func testDisablingRemovesTheRequest() async throws {
        let h = try makeHarness()
        await h.reminder.setEnabled(true)
        XCTAssertEqual(h.center.pending.count, 1)
        let outcome = await h.reminder.setEnabled(false)
        XCTAssertEqual(outcome, .off)
        XCTAssertEqual(h.center.pending.count, 0)
        XCTAssertFalse(h.reminder.isEnabled)
        XCTAssertFalse(h.settings.reminderEnabled)

        await h.reminder.reconcile(latestWeighInDay: nil)
        XCTAssertEqual(h.center.pending.count, 0, "and it stays removed")
    }

    func testDisablingAlsoRemovesAWeekThatWasBeingSkipped() async throws {
        let h = try makeHarness()
        await h.reminder.setEnabled(true)
        await h.reminder.reconcile(latestWeighInDay: "2031-01-29")
        XCTAssertFalse(h.center.pending.isEmpty, "the week after is still pending while this one is skipped")
        await h.reminder.setEnabled(false)
        XCTAssertEqual(h.center.pending.count, 0, "whatever was pending for the skipped week is removed too")
    }

    // MARK: - The scorecard flag

    func testTurningTheFeatureFlagOffRemovesTheRequest() async throws {
        let h = try makeHarness()
        await h.reminder.setEnabled(true)
        XCTAssertEqual(h.center.pending.count, 1)

        h.settings.isEnabled = false
        await h.reminder.reconcile(latestWeighInDay: nil)
        XCTAssertEqual(h.center.pending.count, 0, "off: no reminder (§9.2)")

        await h.reminder.setSchedule(weekday: 2, minuteOfDay: 600)
        XCTAssertEqual(h.center.pending.count, 0, "changing the time does not bring it back")
    }

    func testNothingIsScheduledWhileTheFeatureFlagIsOff() async throws {
        for flag in [false, nil] as [Bool?] {
            let h = try makeHarness(flag: flag)
            await h.reminder.setEnabled(true)
            await h.reminder.reconcile(latestWeighInDay: nil)
            XCTAssertEqual(h.center.pending.count, 0, "flag \(String(describing: flag))")
            XCTAssertEqual(h.center.added.count, 0, "flag \(String(describing: flag))")
            XCTAssertEqual(h.center.authorizationRequests, 0, "no prompt for a feature that is off")
            XCTAssertNotEqual(h.defaults.object(forKey: "noop.cutScorecardEnabled") as? Bool, true,
                              "the reminder never switches the feature on")

            // The same reminder schedules as soon as the feature is on.
            h.settings.isEnabled = true
            let outcome = await h.reminder.setEnabled(true)
            XCTAssertEqual(outcome, .scheduled, "flag \(String(describing: flag))")
            XCTAssertEqual(h.center.pending.count, 1, "flag \(String(describing: flag))")
        }
    }

    // MARK: - A week that already has a weigh-in

    /// Weighed on Wednesday morning; the reminder is for Saturday 08:00 of the same week.
    func testNotDeliveredInAWeekThatAlreadyHasAWeighIn() async throws {
        let h = try makeHarness()
        await h.reminder.setEnabled(true)
        XCTAssertEqual(fires(h), [at("2031-02-01", 8)], "before the weigh-in it would fire this Saturday")

        await h.reminder.reconcile(latestWeighInDay: "2031-01-29")
        let nextMonday = at("2031-02-03", 0)
        let mondayAfter = at("2031-02-10", 0)
        XCTAssertFalse(fires(h).contains { $0 < nextMonday },
                       "nothing fires in the rest of a week that has its weigh-in: \(fires(h))")
        XCTAssertTrue(fires(h).contains { $0 >= nextMonday && $0 < mondayAfter },
                      "the reminder is still due the week after: \(fires(h))")
        XCTAssertEqual(fires(h).first, at("2031-02-08", 8), "next Saturday at 08:00")
        XCTAssertTrue(h.reminder.isEnabled, "the switch is untouched")
        for request in h.center.pending {
            XCTAssertEqual(request.content.title, title)
            XCTAssertEqual(request.content.body, body)
        }
    }

    func testTheWeeklyRequestReturnsWhenANewWeekBeginsWithoutAWeighIn() async throws {
        let h = try makeHarness()
        await h.reminder.setEnabled(true)
        await h.reminder.reconcile(latestWeighInDay: "2031-01-29")

        h.clock.now = at("2031-02-03", 9)       // Monday of the next week; last week's weigh-in is the latest
        await h.reminder.reconcile(latestWeighInDay: "2031-01-29")
        try assertOneWeeklyRequest(h, weekday: 7, hour: 8, minute: 0)
        XCTAssertEqual(fires(h), [at("2031-02-08", 8)])
    }

    func testAWeighInLastWeekDoesNotSilenceThisWeek() async throws {
        let h = try makeHarness()
        await h.reminder.setEnabled(true)
        await h.reminder.reconcile(latestWeighInDay: "2031-01-22")
        try assertOneWeeklyRequest(h, weekday: 7, hour: 8, minute: 0)
        XCTAssertEqual(fires(h), [at("2031-02-01", 8)], "no weigh-in this week: it fires this Saturday")

        await h.reminder.reconcile(latestWeighInDay: nil)
        try assertOneWeeklyRequest(h, weekday: 7, hour: 8, minute: 0)
    }

    /// The week runs Monday to Sunday, as the scorecard's weeks do: a Sunday weigh-in belongs to the
    /// week that is ending, and a Monday one to the week that is starting.
    func testTheWeekIsMondayToSunday() async throws {
        let sunday = try makeHarness(now: at("2031-02-02", 7, 5))
        sunday.settings.reminderWeekday = 1         // Sunday, 08:00
        await sunday.reminder.setEnabled(true)
        XCTAssertEqual(fires(sunday), [at("2031-02-02", 8)])
        await sunday.reminder.reconcile(latestWeighInDay: "2031-01-27")     // Monday of this same week
        XCTAssertFalse(fires(sunday).contains { $0 < at("2031-02-03", 0) }, "Monday's weigh-in covers Sunday")

        let monday = try makeHarness(now: at("2031-02-03", 7, 5))
        monday.settings.reminderWeekday = 2         // Monday, 08:00
        await monday.reminder.setEnabled(true)
        await monday.reminder.reconcile(latestWeighInDay: "2031-02-02")     // yesterday, but last week
        XCTAssertEqual(fires(monday).first, at("2031-02-03", 8), "Sunday's weigh-in does not cover Monday")
    }

    func testDeletingTheWeeksWeighInBringsTheReminderBack() async throws {
        let h = try makeHarness()
        await h.reminder.setEnabled(true)
        await h.reminder.reconcile(latestWeighInDay: "2031-01-29")
        await h.reminder.reconcile(latestWeighInDay: "2031-01-22")      // this week's reading was deleted
        try assertOneWeeklyRequest(h, weekday: 7, hour: 8, minute: 0)
        XCTAssertEqual(fires(h), [at("2031-02-01", 8)])
    }

    // MARK: - §10.10 privacy

    func testNotificationTextIsExactlyTheApprovedTitleAndBody() async throws {
        let h = try makeHarness()
        await h.reminder.setEnabled(true)
        let content = try XCTUnwrap(h.center.pending.first).content
        XCTAssertEqual(content.title, "Weekly weigh-in")
        XCTAssertEqual(content.body, "Weight, then waist. It takes under a minute.")
        XCTAssertEqual(content.subtitle, "")
    }

    /// No measurement, no verdict and no phase name ever appears in a notification, whatever is stored.
    func testNotificationTextContainsNoNumberOrPhaseName() async throws {
        let h = try makeHarness()
        h.settings.phases = [CutScorecardStoredPhase(kind: .cut, name: "Fixture cut", startDay: "2031-01-06",
                                                     targetWeightKg: 94.0, rateLowPercentPerWeek: 0.40,
                                                     rateHighPercentPerWeek: 1.20)]
        h.settings.parameters = ScorecardScreenFixture.parameters
        h.defaults.set(97.6, forKey: "profile.weightKg")

        await h.reminder.setEnabled(true)
        await h.reminder.setSchedule(weekday: 4, minuteOfDay: 7 * 60 + 15)
        await h.reminder.reconcile(latestWeighInDay: "2031-01-29")
        await h.reminder.reconcile(latestWeighInDay: "2031-01-22")
        XCTAssertFalse(h.center.added.isEmpty)

        let banned = ["fixture", "cut", "kg", "lb", "cm", "kcal", "verdict", "rule", "target", "carb", "calorie",
                      "change nothing", "overdue"]
        for request in h.center.added {
            let content = request.content
            for text in [content.title, content.subtitle, content.body] {
                XCTAssertNil(text.rangeOfCharacter(from: .decimalDigits), "no number in \"\(text)\"")
                for word in banned {
                    XCTAssertFalse(text.lowercased().contains(word), "\"\(text)\" contains \"\(word)\"")
                }
            }
            // The payload is not shown, but it leaves the app: no measurement and no phase name in it either.
            for text in content.userInfo.map({ "\($0.key) \($0.value)" }) {
                XCTAssertNil(text.rangeOfCharacter(from: .decimalDigits), "no number in the payload: \(text)")
                XCTAssertFalse(text.lowercased().contains("fixture"), "no phase name in the payload: \(text)")
            }
            XCTAssertNil(content.badge, "no count on the app icon either")
            XCTAssertTrue(content.attachments.isEmpty)
        }
    }
}
