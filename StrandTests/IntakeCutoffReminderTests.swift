// API ASSUMED BY THESE TESTS
//
// Stage 3 specification §7.6, §10.7, §12.3 (`IntakeCutoffReminderTests.swift`) and §12.8. Written
// before the implementation exists. New, in Strand/System/IntakeCutoffReminder.swift:
//
//     enum IntakeCutoffPlan {                                                           [spec §7.6]
//         struct Trigger: Equatable { let weekday: Int; let minuteOfDay: Int; let playsSound: Bool }
//         static func triggers(cutoffMinuteOfDay: Int, windDownMinuteByWeekday: [Int: Int],
//                              quietWindowMinutes: Int = 30) -> [Trigger]
//         static func windDownFireTimes(enabled: Bool, hasPerDayOverrides: Bool, dailyMinute: Int,
//                                       minuteForWakeWeekday: (Int) -> Int,
//                                       dayShiftForWakeWeekday: (Int) -> Int) -> [Int: Int]
//     }
//
//     @MainActor final class IntakeCutoffReminder {
//         enum Outcome: Equatable { case scheduled, denied, off }                       [spec §7.6]
//         static let requestIds: [String]   // "intake-cutoff-wd1" … "intake-cutoff-wd7"  [assumed name]
//         static let title: String          // "Food cutoff"                              [assumed name]
//         static let body: String           // "Your cutoff time is now."                [assumed name]
//         init(center: WeighInReminderCenter, settings: IntakeSettings,
//              windDownFireTimes: @escaping @MainActor () -> [Int: Int])                 [assumed]
//             // the wind-down map read at each scheduling pass; production passes
//             // `IntakeCutoffPlan.windDownFireTimes` over `WindDownNudge`'s public statics
//         /// On: asks for permission when undecided, schedules and returns `.scheduled`;
//         /// refused: stores the switch off and returns `.denied`. Off: removes the seven and
//         /// returns `.off`. With the intake flag off nothing is asked, stored or scheduled.
//         @discardableResult func setEnabled(_ on: Bool) async -> Outcome
//         /// Removes the seven ids and adds them again from `triggers` while the flag and the switch
//         /// are on; removes them otherwise. Called when the flag, the switch or the time changes.
//         func reconcile() async
//         /// True only while the flag and the switch are both on.
//         var reconcilesOnActive: Bool { get }
//         /// The app became active: returns at once, with no call to the notification centre,
//         /// unless `reconcilesOnActive`; otherwise `reconcile()`.
//         func reconcileOnActive() async
//     }
//
// `WeighInReminderCenter` (the protocol of Strand/System/WeighInReminder.swift) and
// `WindDownNudge.shiftedWeekday(weekday:by:)` are used as they exist today. No notification is
// scheduled: the centre is a fake that keeps requests in memory.
//
// Behaviour assumed where the specification leaves it open:
//  1. Each request is a repeating `UNCalendarNotificationTrigger` whose components are exactly the
//     weekday, hour and minute.
//  2. An audible request plays the default sound; a silent one has no sound and the `.passive`
//     interruption level (§7.6).
//
// Synthetic values only (§13.5).

import XCTest
import UserNotifications
@testable import Strand

@MainActor
final class IntakeCutoffReminderTests: XCTestCase {
    private let suites = IntakeSuites()

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    private final class FakeCenter: WeighInReminderCenter {
        var status: UNAuthorizationStatus = .notDetermined
        var grantsWhenAsked = true
        private(set) var calls = 0
        private(set) var authorizationRequests = 0
        private(set) var pending: [UNNotificationRequest] = []

        func authorizationStatus() async -> UNAuthorizationStatus { calls += 1; return status }
        func requestAuthorization() async -> Bool {
            calls += 1
            authorizationRequests += 1
            status = grantsWhenAsked ? .authorized : .denied
            return grantsWhenAsked
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
        func pendingRequests() async -> [UNNotificationRequest] { calls += 1; return pending }
    }

    private typealias Plan = IntakeCutoffPlan

    private func everyDay(_ minute: Int) -> [Int: Int] { Dictionary(uniqueKeysWithValues: (1...7).map { ($0, minute) }) }

    private func make(flag: Bool = true, cutoff: Int = IntakeFixture.cutoffMinute, windDown: [Int: Int] = [:])
        throws -> (IntakeCutoffReminder, FakeCenter, IntakeSettings, IntakeRecordingDefaults) {
        let name = "IntakeCutoffReminderTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(IntakeRecordingDefaults(suiteName: name))
        suites.names.append(name)
        let settings = IntakeSettings(defaults: defaults)
        settings.isEnabled = flag
        settings.cutoffMinuteOfDay = cutoff
        settings.cutoffTimeSet = true
        let center = FakeCenter()
        let reminder = IntakeCutoffReminder(center: center, settings: settings, windDownFireTimes: { windDown })
        defaults.written = []
        return (reminder, center, settings, defaults)
    }

    private func components(_ request: UNNotificationRequest) -> DateComponents? {
        (request.trigger as? UNCalendarNotificationTrigger)?.dateComponents
    }

    // MARK: - The plan (pure)

    func testSevenTriggersAtTheCutoffMinute() {
        let triggers = Plan.triggers(cutoffMinuteOfDay: 1_200, windDownMinuteByWeekday: [:])
        XCTAssertEqual(triggers, (1...7).map { Plan.Trigger(weekday: $0, minuteOfDay: 1_200, playsSound: true) })
        XCTAssertEqual(Plan.triggers(cutoffMinuteOfDay: -5, windDownMinuteByWeekday: [:]).map(\.minuteOfDay),
                       Array(repeating: 0, count: 7), "clamped to 0…1439")
        XCTAssertEqual(Plan.triggers(cutoffMinuteOfDay: 2_000, windDownMinuteByWeekday: [:]).map(\.minuteOfDay),
                       Array(repeating: 1_439, count: 7))
    }

    func testWithinTheQuietWindowIsSilent() {
        // §13.5: cutoff 20:00, wind-down 20:20 every day.
        let triggers = Plan.triggers(cutoffMinuteOfDay: 1_200, windDownMinuteByWeekday: everyDay(1_220))
        XCTAssertEqual(triggers.map(\.playsSound), Array(repeating: false, count: 7))
        XCTAssertEqual(triggers.map(\.minuteOfDay), Array(repeating: 1_200, count: 7), "the cutoff never moves")
        // Before the cutoff counts too.
        XCTAssertEqual(Plan.triggers(cutoffMinuteOfDay: 1_200, windDownMinuteByWeekday: everyDay(1_175))
            .map(\.playsSound), Array(repeating: false, count: 7))
    }

    func testExactlyAtTheWindowEdgeIsSilent() {
        XCTAssertEqual(Plan.triggers(cutoffMinuteOfDay: 1_200, windDownMinuteByWeekday: everyDay(1_230))
            .map(\.playsSound), Array(repeating: false, count: 7), "20:30 is inside")
        XCTAssertEqual(Plan.triggers(cutoffMinuteOfDay: 1_200, windDownMinuteByWeekday: everyDay(1_170))
            .map(\.playsSound), Array(repeating: false, count: 7), "19:30 is inside")
        XCTAssertEqual(Plan.triggers(cutoffMinuteOfDay: 1_200, windDownMinuteByWeekday: everyDay(1_230),
                                     quietWindowMinutes: 29).map(\.playsSound),
                       Array(repeating: true, count: 7), "the window is a parameter")
    }

    func testOutsideTheWindowPlaysSound() {
        XCTAssertEqual(Plan.triggers(cutoffMinuteOfDay: 1_200, windDownMinuteByWeekday: everyDay(1_231))
            .map(\.playsSound), Array(repeating: true, count: 7), "20:31")
        XCTAssertEqual(Plan.triggers(cutoffMinuteOfDay: 1_200, windDownMinuteByWeekday: everyDay(1_169))
            .map(\.playsSound), Array(repeating: true, count: 7), "19:29")
    }

    func testDistanceWrapsAcrossMidnightAndTheWeek() {
        // §13.5: cutoff 23:50, wind-down 00:10 fired on the following weekday. A wind-down that
        // fires at 00:10 on weekday w+1 is 20 minutes after the cutoff on weekday w.
        let windDown = everyDay(10)
        let triggers = Plan.triggers(cutoffMinuteOfDay: 1_430, windDownMinuteByWeekday: windDown)
        XCTAssertEqual(triggers.map(\.playsSound), Array(repeating: false, count: 7))
        // Only Monday's 00:10 wind-down: silent is Sunday's cutoff (weekday 1), nothing else.
        let monday = Plan.triggers(cutoffMinuteOfDay: 1_430, windDownMinuteByWeekday: [2: 10])
        XCTAssertEqual(monday.map(\.playsSound), [false, true, true, true, true, true, true])
        // Only Sunday's 00:10 wind-down: silent is Saturday's cutoff, across the end of the week.
        let sunday = Plan.triggers(cutoffMinuteOfDay: 1_430, windDownMinuteByWeekday: [1: 10])
        XCTAssertEqual(sunday.map(\.playsSound), [true, true, true, true, true, true, false])
        // And the other way: a cutoff at 00:05 is 15 minutes after a 23:50 wind-down the evening before.
        let early = Plan.triggers(cutoffMinuteOfDay: 5, windDownMinuteByWeekday: [7: 1_430])
        XCTAssertEqual(early.map(\.playsSound), [false, true, true, true, true, true, true])
    }

    func testPerWeekdayWindDownSilencesOnlyThoseWeekdays() {
        // §13.5: wind-down 20:10 on weekday 2 only, 22:00 otherwise.
        var windDown = everyDay(1_320)
        windDown[2] = 1_210
        let triggers = Plan.triggers(cutoffMinuteOfDay: 1_200, windDownMinuteByWeekday: windDown)
        XCTAssertEqual(triggers.map(\.playsSound), [true, false, true, true, true, true, true])
    }

    func testWindDownOffLeavesEveryTriggerAudible() {
        XCTAssertEqual(Plan.windDownFireTimes(enabled: false, hasPerDayOverrides: true, dailyMinute: 1_210,
                                              minuteForWakeWeekday: { _ in 1_210 }, dayShiftForWakeWeekday: { _ in 0 }),
                       [:])
        XCTAssertEqual(Plan.triggers(cutoffMinuteOfDay: 1_200, windDownMinuteByWeekday: [:]).map(\.playsSound),
                       Array(repeating: true, count: 7))
    }

    func testFireTimesMatchWhatTheNudgeSchedules() {
        // Without overrides: every weekday at the daily minute.
        XCTAssertEqual(Plan.windDownFireTimes(enabled: true, hasPerDayOverrides: false, dailyMinute: 1_290,
                                              minuteForWakeWeekday: { _ in 0 }, dayShiftForWakeWeekday: { _ in -1 }),
                       everyDay(1_290))
        // With overrides: each wake weekday's nudge, pinned to the day it fires on, as `schedule()` does.
        let minutes: [Int: Int] = [1: 1_290, 2: 1_170, 3: 1_350, 4: 1_295, 5: 1_300, 6: 1_310, 7: 1_380]
        let evening = Plan.windDownFireTimes(enabled: true, hasPerDayOverrides: true, dailyMinute: 0,
                                             minuteForWakeWeekday: { minutes[$0]! }, dayShiftForWakeWeekday: { _ in -1 })
        var expected: [Int: Int] = [:]
        for wake in 1...7 { expected[WindDownNudge.shiftedWeekday(weekday: wake, by: -1)] = minutes[wake]! }
        XCTAssertEqual(evening, expected)
        XCTAssertEqual(evening[7], 1_290, "Sunday's wake is preceded by Saturday evening's nudge")
        XCTAssertEqual(evening[1], 1_170, "Monday's by Sunday evening's")
        // A nudge after midnight stays on its wake day.
        let early: [Int: Int] = [1: 30, 2: 40, 3: 50, 4: 60, 5: 70, 6: 80, 7: 90]
        XCTAssertEqual(Plan.windDownFireTimes(enabled: true, hasPerDayOverrides: true, dailyMinute: 0,
                                              minuteForWakeWeekday: { early[$0]! }, dayShiftForWakeWeekday: { _ in 0 }),
                       early)
    }

    // MARK: - The reminder

    func testEnablingAsksPermissionAndDenialRevertsTheSwitch() async throws {
        let (reminder, center, settings, _) = try make()
        XCTAssertEqual(center.calls, 0, "constructing it asks nothing")
        let outcome = await reminder.setEnabled(true)
        XCTAssertEqual(outcome, .scheduled)
        XCTAssertEqual(center.authorizationRequests, 1, "asked once, only when switched on")
        XCTAssertTrue(settings.cutoffEnabled)
        XCTAssertEqual(Set(center.pending.map(\.identifier)), Set(IntakeCutoffReminder.requestIds))
        XCTAssertEqual(IntakeCutoffReminder.requestIds, (1...7).map { "intake-cutoff-wd\($0)" })
        for request in center.pending {
            let weekday = Int(request.identifier.dropFirst("intake-cutoff-wd".count))
            XCTAssertEqual(components(request)?.weekday, weekday)
            XCTAssertEqual(components(request)?.hour, 20)
            XCTAssertEqual(components(request)?.minute, 0)
            XCTAssertEqual((request.trigger as? UNCalendarNotificationTrigger)?.repeats, true)
            XCTAssertNotNil(request.content.sound, "no wind-down nearby: audible")
        }

        // Denied by the system: the switch reverts and nothing is pending.
        let (denied, deniedCenter, deniedSettings, _) = try make()
        deniedCenter.grantsWhenAsked = false
        let refused = await denied.setEnabled(true)
        XCTAssertEqual(refused, .denied)
        XCTAssertFalse(deniedSettings.cutoffEnabled)
        XCTAssertEqual(deniedCenter.pending, [])

        // Already denied: not asked again.
        let (again, againCenter, _, _) = try make()
        againCenter.status = .denied
        let second = await again.setEnabled(true)
        XCTAssertEqual(second, .denied)
        XCTAssertEqual(againCenter.authorizationRequests, 0)

        // Switched off: all seven removed.
        let off = await reminder.setEnabled(false)
        XCTAssertEqual(off, .off)
        XCTAssertFalse(settings.cutoffEnabled)
        XCTAssertEqual(center.pending, [])
    }

    func testSilentWeekdaysAreDeliveredQuietly() async throws {
        var windDown = everyDay(1_320)
        windDown[2] = 1_210
        let (reminder, center, _, _) = try make(windDown: windDown)
        center.status = .authorized
        _ = await reminder.setEnabled(true)
        for request in center.pending {
            let monday = request.identifier == "intake-cutoff-wd2"
            XCTAssertEqual(request.content.sound == nil, monday, request.identifier)
            if #available(macOS 12.0, *) {
                XCTAssertEqual(request.content.interruptionLevel == .passive, monday, request.identifier)
            }
            XCTAssertEqual(request.content.title, "Food cutoff", "the same text, silent or not")
        }
    }

    func testFlagOffRemovesEveryRequestAndReconcileDoesNothing() async throws {
        let (reminder, center, settings, defaults) = try make()
        center.status = .authorized
        _ = await reminder.setEnabled(true)
        XCTAssertEqual(center.pending.count, 7)

        settings.isEnabled = false
        await reminder.reconcile()
        XCTAssertEqual(center.pending, [], "the flag switched off removes all seven")
        XCTAssertFalse(reminder.reconcilesOnActive)
        let calls = center.calls
        await reminder.reconcileOnActive()
        XCTAssertEqual(center.calls, calls, "with the flag off, becoming active makes no call at all")

        // Flag off from the start: switching the reminder on asks, stores and schedules nothing.
        let (cold, coldCenter, coldSettings, coldDefaults) = try make(flag: false)
        let outcome = await cold.setEnabled(true)
        XCTAssertEqual(outcome, .off)
        XCTAssertEqual(coldCenter.authorizationRequests, 0)
        XCTAssertEqual(coldCenter.pending, [])
        XCTAssertFalse(coldSettings.cutoffEnabled)
        XCTAssertFalse(coldDefaults.written.contains(IntakeSettings.cutoffEnabledKey))
        await cold.reconcileOnActive()
        _ = defaults
    }

    func testTheSwitchOffMeansNoWorkOnActive() async throws {
        let (reminder, center, settings, _) = try make()
        settings.cutoffEnabled = false
        XCTAssertFalse(reminder.reconcilesOnActive)
        await reminder.reconcileOnActive()
        XCTAssertEqual(center.calls, 0)
        settings.cutoffEnabled = true
        XCTAssertTrue(reminder.reconcilesOnActive)
        center.status = .authorized
        await reminder.reconcileOnActive()
        XCTAssertEqual(center.pending.count, 7, "reconciliation removes the seven ids and adds them again")
        await reminder.reconcileOnActive()
        XCTAssertEqual(center.pending.count, 7, "never more than one request per weekday")
    }

    func testAChangedCutoffTimeIsRescheduled() async throws {
        let (reminder, center, settings, _) = try make()
        center.status = .authorized
        _ = await reminder.setEnabled(true)
        settings.cutoffMinuteOfDay = 19 * 60 + 45
        await reminder.reconcile()
        XCTAssertEqual(center.pending.count, 7)
        XCTAssertTrue(center.pending.allSatisfy { components($0)?.hour == 19 && components($0)?.minute == 45 })
    }

    // MARK: - Privacy (§10.7, §12.8)

    func testNotificationTextCarriesNoNumber() async throws {
        let (reminder, center, settings, defaults) = try make()
        // The Fixture Person has a floor, a supplement, targets and entries; none may reach the text.
        defaults.set(#"{"proteinFloorGrams":100,"v":1}"#, forKey: "cutScorecard.rules")
        settings.addSupplementQuestion(IntakeFixture.supplementQuestion)
        settings.setTargets(IntakeFixture.targets)
        center.status = .authorized
        _ = await reminder.setEnabled(true)
        XCTAssertEqual(IntakeCutoffReminder.title, "Food cutoff")
        XCTAssertEqual(IntakeCutoffReminder.body, "Your cutoff time is now.")
        XCTAssertEqual(center.pending.count, 7)
        for request in center.pending {
            let text = [request.content.title, request.content.subtitle, request.content.body]
            XCTAssertEqual(request.content.title, "Food cutoff")
            XCTAssertEqual(request.content.body, "Your cutoff time is now.")
            XCTAssertEqual(request.content.subtitle, "")
            for part in text {
                XCTAssertNil(part.rangeOfCharacter(from: .decimalDigits), "no number: \(part)")
                for forbidden in ["Fixture", "supplement", "protein", "Protein", "kcal", " g", "floor", "Did you take"] {
                    XCTAssertFalse(part.contains(forbidden), "\(forbidden) in \(part)")
                }
            }
            XCTAssertTrue(request.content.userInfo.isEmpty, "nothing rides along in the payload")
            XCTAssertNil(request.content.badge)
        }
    }
}
