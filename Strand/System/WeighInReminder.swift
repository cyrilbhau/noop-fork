import Foundation
import UserNotifications
import StrandAnalytics

/// What the weekly reminder needs from the notification centre. The app's conformance wraps
/// `UNUserNotificationCenter.current()`; tests keep the requests in memory.
protocol WeighInReminderCenter: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    /// Shows the system prompt. True when the owner allowed notifications.
    func requestAuthorization() async -> Bool
    func add(_ request: UNNotificationRequest) async
    func removePendingRequests(withIdentifiers identifiers: [String])
    func pendingRequests() async -> [UNNotificationRequest]
}

/// The app's notification centre, as the reminder sees it.
final class SystemWeighInReminderCenter: WeighInReminderCenter {
    private var center: UNUserNotificationCenter { .current() }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func add(_ request: UNNotificationRequest) async {
        try? await center.add(request)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func pendingRequests() async -> [UNNotificationRequest] {
        await center.pendingNotificationRequests()
    }
}

/// The weekly weigh-in reminder (specification §10.6, §10.10): one calm local notification a week,
/// on the weekday and at the time the owner chose. Off by default, and never scheduled while the
/// scorecard flag is off. On-device only, by the same mechanism as the wind-down nudge: a calendar
/// trigger held by the notification centre.
///
/// A week that already has a weigh-in is not reminded. A repeating trigger cannot skip one
/// occurrence, so for such a week the repeating request is replaced by dated one-off requests for
/// the weeks after it; `reconcile` restores the repeating request once a new week begins without a
/// weigh-in.
@MainActor
final class WeighInReminder {
    /// `superseded`: a newer `setEnabled`, or the scorecard flag going off, arrived while this
    /// call was suspended on the notification centre. That newer choice stands; this call wrote
    /// nothing, scheduled nothing and has no state to report.
    enum Outcome: Equatable { case scheduled, denied, off, superseded }

    /// The repeating weekly request.
    private static let weeklyId = "weigh-in-reminder"
    /// How many following weeks are covered by dated requests while this week is skipped. The app
    /// reconciles every time it becomes active (`reconcileOnActive`, called from the scene-phase
    /// handler of the iPhone shell), so these are only reached when it is not brought to the
    /// front for that long.
    private static let skippedWeekCover = 4

    private static var datedIds: [String] {
        (1...skippedWeekCover).map { "\(weeklyId)-week-\($0)" }
    }

    /// The app's reminder, over the system notification centre and the standard defaults.
    static let live = WeighInReminder(center: SystemWeighInReminderCenter(), settings: CutScorecardSettings())

    private let center: WeighInReminderCenter
    private let settings: CutScorecardSettings
    private let now: () -> Date
    private let calendar: () -> Calendar
    /// The newest weigh-in day this process was last told about. Every entry point that can
    /// schedule carries it (`reconcile`, `reconcileOnActive`, `setSchedule`), so what is pending
    /// never depends on which of them happened to run first after a launch.
    private var latestWeighInDay: String?
    /// The last scheduling pass. Passes run one after another: one that was suspended on the
    /// notification centre can then never finish over a later one.
    private var applying: Task<Void, Never>?
    /// Counts `setEnabled` calls. A call is the owner's latest choice only while this still holds
    /// the value it took on entry.
    private var choice = 0

    init(center: WeighInReminderCenter, settings: CutScorecardSettings,
         now: @escaping () -> Date = { Date() },
         calendar: @escaping () -> Calendar = { Calendar.current }) {
        self.center = center
        self.settings = settings
        self.now = now
        self.calendar = calendar
    }

    /// The stored switch.
    var isEnabled: Bool { settings.reminderEnabled }

    /// On: schedules when notifications are allowed, asking once if that was never decided, and
    /// returns `.scheduled`; otherwise the switch stays off and the caller is told `.denied`, so
    /// Settings can say so instead of showing a switch that cannot fire. Off: removes every
    /// request. With the scorecard flag off nothing is asked, stored or scheduled.
    ///
    /// The owner's latest choice wins. When a newer call, or the scorecard flag going off, arrives
    /// while this one awaits the notification centre, this one returns `.superseded` without
    /// writing the switch, scheduling or prompting.
    @discardableResult
    func setEnabled(_ on: Bool) async -> Outcome {
        choice &+= 1
        let mine = choice
        guard on else {
            settings.reminderEnabled = false
            removeAll()
            return .off
        }
        guard settings.isEnabled else { return .off }
        var allowed: Bool
        switch await center.authorizationStatus() {
        case .authorized, .provisional, .ephemeral: allowed = true
        case .notDetermined:
            guard isLatest(mine) else { return .superseded }
            allowed = await center.requestAuthorization()
        default: allowed = false
        }
        guard isLatest(mine) else { return .superseded }
        guard allowed else {
            settings.reminderEnabled = false
            removeAll()
            return .denied
        }
        settings.reminderEnabled = true
        await apply()
        // A newer choice that arrived during the pass has already brought what is pending into
        // line (the pass removes what it added behind an off switch); it is the one reported.
        return isLatest(mine) ? .scheduled : .superseded
    }

    /// True while the `setEnabled` call that took `mine` is still the latest one and the
    /// scorecard flag is still on: the only condition under which it may write or report.
    private func isLatest(_ mine: Int) -> Bool {
        choice == mine && settings.isEnabled
    }

    /// Stores the weekday (1 = Sunday to 7 = Saturday) and the minute after local midnight, and
    /// replaces what is pending when the reminder is on. The latest weigh-in day is the one this
    /// process was last told; a caller that knows it passes it with the schedule instead.
    func setSchedule(weekday: Int, minuteOfDay: Int) async {
        settings.reminderWeekday = min(max(weekday, 1), 7)
        settings.reminderMinuteOfDay = min(max(minuteOfDay, 0), 24 * 60 - 1)
        await apply()
    }

    /// As `setSchedule(weekday:minuteOfDay:)`, carrying the local day of the newest weight, so the
    /// new request honours a week that already has its weigh-in whoever last called `reconcile`.
    func setSchedule(weekday: Int, minuteOfDay: Int, latestWeighInDay: String?) async {
        self.latestWeighInDay = latestWeighInDay
        await setSchedule(weekday: weekday, minuteOfDay: minuteOfDay)
    }

    /// Brings what is pending into line with the flag, the switch and the latest weigh-in. Called
    /// after a weigh-in is saved or deleted, when the flag or the switch changes, and through
    /// `reconcileOnActive` when the app becomes active. `latestWeighInDay` is the local day of the
    /// newest weight. Reads the settings and writes none.
    func reconcile(latestWeighInDay: String?) async {
        self.latestWeighInDay = latestWeighInDay
        await apply()
    }

    /// True only while the scorecard flag and the reminder switch are both on: the one condition
    /// under which becoming active does any work.
    var reconcilesOnActive: Bool { settings.isEnabled && settings.reminderEnabled }

    /// The app became active. Returns at once, before any call to the notification centre and
    /// without evaluating `latestWeighInDay`, unless the scorecard flag and the reminder switch
    /// are both on; otherwise `reconcile` with its value. This is what restores the repeating
    /// request in a new week when no scorecard surface has been opened since the last weigh-in.
    func reconcileOnActive(latestWeighInDay: @MainActor () async -> String?) async {
        guard reconcilesOnActive else { return }
        await reconcile(latestWeighInDay: await latestWeighInDay())
    }

    /// The local day of the newest weight the scorecard would call current, as every caller of
    /// `reconcile` outside the scorecard model reads it: the provider's display series up to today.
    static func latestWeighInDay(in provider: BodyMeasurementProvider, today: String) -> String? {
        provider.series(.weight, consumer: .display).last { $0.day <= today }?.day
    }

    // MARK: - Scheduling

    private func removeAll() {
        center.removePendingRequests(withIdentifiers: [Self.weeklyId] + Self.datedIds)
    }

    /// One scheduling pass, after every pass requested before it has finished.
    private func apply() async {
        let previous = applying
        let pass = Task { @MainActor in
            await previous?.value
            await self.schedule()
        }
        applying = pass
        await pass.value
    }

    /// Reads the settings and the latest weigh-in day when it runs, not when it was requested, so
    /// the last pass always works from the newest state.
    private func schedule() async {
        guard settings.isEnabled, settings.reminderEnabled else {
            removeAll()
            return
        }
        let weekday = min(max(settings.reminderWeekday, 1), 7)
        let minute = min(max(settings.reminderMinuteOfDay, 0), 24 * 60 - 1)
        let calendar = calendar()

        // Weeks run Monday to Sunday, as the scorecard's do.
        let today = Self.dayKey(now(), calendar)
        let thisWeek = CutScorecard.weekStart(containing: today)
        let weekHasWeighIn = thisWeek != nil
            && latestWeighInDay.flatMap { CutScorecard.weekStart(containing: $0) } == thisWeek

        if weekHasWeighIn, let thisWeek, let monday = Self.date(thisWeek, calendar) {
            center.removePendingRequests(withIdentifiers: [Self.weeklyId])
            // Monday is day 0 of the week; Sunday, weekday 1, is day 6.
            let offset = (weekday + 5) % 7
            for (index, identifier) in Self.datedIds.enumerated() {
                guard let day = calendar.date(byAdding: .day, value: 7 * (index + 1) + offset, to: monday) else {
                    continue
                }
                var components = calendar.dateComponents([.year, .month, .day], from: day)
                components.hour = minute / 60
                components.minute = minute % 60
                await center.add(UNNotificationRequest(
                    identifier: identifier, content: Self.content(),
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
            }
            removeAllIfSwitchedOff()
            return
        }

        center.removePendingRequests(withIdentifiers: Self.datedIds)
        var components = DateComponents()
        components.weekday = weekday
        components.hour = minute / 60
        components.minute = minute % 60
        // A request already pending for this weekday and time is left as it is.
        let pending = await center.pendingRequests().first { $0.identifier == Self.weeklyId }
        if let held = (pending?.trigger as? UNCalendarNotificationTrigger), held.repeats,
           held.dateComponents.weekday == components.weekday, held.dateComponents.hour == components.hour,
           held.dateComponents.minute == components.minute {
            return
        }
        await center.add(UNNotificationRequest(
            identifier: Self.weeklyId, content: Self.content(),
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)))
        removeAllIfSwitchedOff()
    }

    /// The flag or the switch went off while a pass was suspended on the notification centre:
    /// what that pass added is removed again, so nothing stays pending behind an off switch.
    private func removeAllIfSwitchedOff() {
        if !(settings.isEnabled && settings.reminderEnabled) { removeAll() }
    }

    /// The approved text and nothing else: no measurement, no verdict and no phase name, in the
    /// text or in the payload.
    private static func content() -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = CutScorecardPresenter.reminderTitle
        content.body = CutScorecardPresenter.reminderBody
        content.sound = .default
        return content
    }

    /// The local day of `instant` in `calendar`, as a day key.
    private static func dayKey(_ instant: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: instant)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Local midnight of a day key in `calendar`.
    private static func date(_ day: String, _ calendar: Calendar) -> Date? {
        let fields = day.split(separator: "-").compactMap { Int($0) }
        guard fields.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: fields[0], month: fields[1], day: fields[2]))
    }
}
