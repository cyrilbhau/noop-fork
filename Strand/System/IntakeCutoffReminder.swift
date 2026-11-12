import Foundation
import UserNotifications

/// When the food cutoff reminder fires and whether it plays a sound (stage 3 specification §7.6).
/// Pure. The wind-down nudge is read, never edited: a cutoff within the quiet window of a wind-down
/// fire time is delivered silently, so the phone sounds once.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
enum IntakeCutoffPlan {
    struct Trigger: Equatable {
        /// Calendar weekday, 1 = Sunday … 7 = Saturday.
        let weekday: Int
        let minuteOfDay: Int
        let playsSound: Bool
    }

    private static let minutesPerDay = 24 * 60
    private static let minutesPerWeek = 7 * 24 * 60

    /// Seven triggers, weekdays 1 to 7 ascending, each at the cutoff minute clamped to 0...1439. A
    /// trigger is silent when any wind-down fire time lies within `quietWindowMinutes` of it on the
    /// week taken as a circle; exactly at the window's edge counts as inside.
    /// `windDownMinuteByWeekday`: the weekday each wind-down fires on, mapped to its minute of the
    /// day. Empty when the nudge is off.
    static func triggers(cutoffMinuteOfDay: Int, windDownMinuteByWeekday: [Int: Int],
                         quietWindowMinutes: Int = 30) -> [Trigger] {
        let minute = min(max(cutoffMinuteOfDay, 0), minutesPerDay - 1)
        let windDowns = windDownMinuteByWeekday.map { weekPosition(weekday: $0.key, minute: $0.value) }
        return (1...7).map { weekday in
            let position = weekPosition(weekday: weekday, minute: minute)
            let near = windDowns.contains { other in
                let apart = abs(position - other) % minutesPerWeek
                return min(apart, minutesPerWeek - apart) <= quietWindowMinutes
            }
            return Trigger(weekday: weekday, minuteOfDay: minute, playsSound: !near)
        }
    }

    /// The wind-down map, from the nudge's public statics, exactly as its own scheduling pins them:
    /// one daily time without per-day overrides; otherwise each wake weekday's nudge on the day it
    /// fires.
    @MainActor
    static func windDownFireTimes(enabled: Bool, hasPerDayOverrides: Bool, dailyMinute: Int,
                                  minuteForWakeWeekday: (Int) -> Int,
                                  dayShiftForWakeWeekday: (Int) -> Int) -> [Int: Int] {
        guard enabled else { return [:] }
        guard hasPerDayOverrides else {
            return Dictionary(uniqueKeysWithValues: (1...7).map { ($0, dailyMinute) })
        }
        var times: [Int: Int] = [:]
        for wake in 1...7 {
            let fires = WindDownNudge.shiftedWeekday(weekday: wake, by: dayShiftForWakeWeekday(wake))
            times[fires] = minuteForWakeWeekday(wake)
        }
        return times
    }

    /// The app's wind-down map now.
    @MainActor
    static func currentWindDownFireTimes() -> [Int: Int] {
        windDownFireTimes(enabled: WindDownNudge.isEnabled, hasPerDayOverrides: WindDownNudge.hasPerDayOverrides,
                          dailyMinute: WindDownNudge.nudgeMinuteOfDay(),
                          minuteForWakeWeekday: { WindDownNudge.nudgeMinuteOfDay(forWeekday: $0) },
                          dayShiftForWakeWeekday: { WindDownNudge.nudgeDayShift(forWeekday: $0) })
    }

    private static func weekPosition(weekday: Int, minute: Int) -> Int {
        let day = ((weekday - 1) % 7 + 7) % 7
        return day * minutesPerDay + minute
    }
}

/// The evening food cutoff reminder (§7.6, §10.7): opt-in, off by default, one a day at most, with a
/// fixed text that carries no amount, floor, judgement or supplement name. Follows `WeighInReminder`:
/// permission is asked only when the owner switches it on, a refusal reverts the switch, and the
/// pending requests are reconciled on app activation. With the intake flag or the switch off,
/// becoming active does nothing at all.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
@MainActor
final class IntakeCutoffReminder {
    enum Outcome: Equatable { case scheduled, denied, off }

    /// One request per weekday.
    static let requestIds: [String] = (1...7).map { "intake-cutoff-wd\($0)" }
    static var title: String { String(localized: "Food cutoff") }
    static var body: String { String(localized: "Your cutoff time is now.") }

    /// The app's reminder, over the system notification centre, the standard defaults and the
    /// wind-down nudge's own settings.
    static let live = IntakeCutoffReminder(center: SystemWeighInReminderCenter(), settings: IntakeSettings(),
                                           windDownFireTimes: { IntakeCutoffPlan.currentWindDownFireTimes() })

    private let center: WeighInReminderCenter
    private let settings: IntakeSettings
    private let windDownFireTimes: @MainActor () -> [Int: Int]
    /// The last scheduling pass. Passes run one after another.
    private var applying: Task<Void, Never>?

    init(center: WeighInReminderCenter, settings: IntakeSettings,
         windDownFireTimes: @escaping @MainActor () -> [Int: Int]) {
        self.center = center
        self.settings = settings
        self.windDownFireTimes = windDownFireTimes
    }

    /// The triggers the reminder would schedule now, for the Settings caption.
    var plannedTriggers: [IntakeCutoffPlan.Trigger] {
        IntakeCutoffPlan.triggers(cutoffMinuteOfDay: settings.cutoffMinuteOfDay,
                                  windDownMinuteByWeekday: windDownFireTimes())
    }

    /// On: asks for permission when undecided, schedules and returns `.scheduled`; refused: stores
    /// the switch off and returns `.denied`. Off: removes the seven and returns `.off`. With the
    /// intake flag off nothing is asked, stored or scheduled.
    @discardableResult
    func setEnabled(_ on: Bool) async -> Outcome {
        guard on else {
            settings.cutoffEnabled = false
            center.removePendingRequests(withIdentifiers: Self.requestIds)
            return .off
        }
        guard settings.isEnabled else { return .off }
        let allowed: Bool
        switch await center.authorizationStatus() {
        case .authorized, .provisional, .ephemeral: allowed = true
        case .notDetermined: allowed = await center.requestAuthorization()
        default: allowed = false
        }
        guard allowed else {
            settings.cutoffEnabled = false
            center.removePendingRequests(withIdentifiers: Self.requestIds)
            return .denied
        }
        settings.cutoffEnabled = true
        await reconcile()
        return .scheduled
    }

    /// Removes the seven ids and adds them again from the plan while the flag and the switch are on;
    /// removes them otherwise. Called when the flag, the switch or the time changes.
    func reconcile() async {
        let previous = applying
        let pass = Task { @MainActor in
            await previous?.value
            await self.schedule()
        }
        applying = pass
        await pass.value
    }

    /// True only while the intake flag and the reminder switch are both on.
    var reconcilesOnActive: Bool { settings.isEnabled && settings.cutoffEnabled }

    /// The app became active: returns at once, with no call to the notification centre, unless
    /// `reconcilesOnActive`; otherwise `reconcile()`. A change to the wind-down nudge reaches the
    /// cutoff here.
    func reconcileOnActive() async {
        guard reconcilesOnActive else { return }
        await reconcile()
    }

    private func schedule() async {
        center.removePendingRequests(withIdentifiers: Self.requestIds)
        guard reconcilesOnActive else { return }
        for trigger in plannedTriggers {
            var components = DateComponents()
            components.weekday = trigger.weekday
            components.hour = trigger.minuteOfDay / 60
            components.minute = trigger.minuteOfDay % 60
            await center.add(UNNotificationRequest(
                identifier: Self.requestIds[trigger.weekday - 1], content: Self.content(playsSound: trigger.playsSound),
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)))
        }
        // Switched off while the pass was suspended: what it added goes again.
        if !reconcilesOnActive { center.removePendingRequests(withIdentifiers: Self.requestIds) }
    }

    /// The fixed text and nothing else. A silent day has no sound and is passive; it still appears
    /// in the list.
    private static func content(playsSound: Bool) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if playsSound {
            content.sound = .default
        } else {
            content.sound = nil
            content.interruptionLevel = .passive
        }
        return content
    }
}
