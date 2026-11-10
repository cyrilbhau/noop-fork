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
    enum Outcome: Equatable { case scheduled, denied, off }

    /// The repeating weekly request.
    private static let weeklyId = "weigh-in-reminder"
    /// How many following weeks are covered by dated requests while this week is skipped. The app
    /// reconciles every time it becomes active, so these are only reached when it stays closed.
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
    /// The newest weigh-in day `reconcile` was last told about, so that a changed time keeps
    /// honouring a week that already has its weigh-in.
    private var latestWeighInDay: String?

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
    @discardableResult
    func setEnabled(_ on: Bool) async -> Outcome {
        guard on else {
            settings.reminderEnabled = false
            removeAll()
            return .off
        }
        guard settings.isEnabled else { return .off }
        var allowed: Bool
        switch await center.authorizationStatus() {
        case .authorized, .provisional, .ephemeral: allowed = true
        case .notDetermined: allowed = await center.requestAuthorization()
        default: allowed = false
        }
        guard allowed else {
            settings.reminderEnabled = false
            removeAll()
            return .denied
        }
        settings.reminderEnabled = true
        await apply()
        return .scheduled
    }

    /// Stores the weekday (1 = Sunday to 7 = Saturday) and the minute after local midnight, and
    /// replaces what is pending when the reminder is on.
    func setSchedule(weekday: Int, minuteOfDay: Int) async {
        settings.reminderWeekday = min(max(weekday, 1), 7)
        settings.reminderMinuteOfDay = min(max(minuteOfDay, 0), 24 * 60 - 1)
        await apply()
    }

    /// Brings what is pending into line with the flag, the switch and the latest weigh-in. Called
    /// after a weigh-in is saved or deleted, when the flag changes, and when the app becomes
    /// active. `latestWeighInDay` is the local day of the newest weight. Reads the settings and
    /// writes none.
    func reconcile(latestWeighInDay: String?) async {
        self.latestWeighInDay = latestWeighInDay
        await apply()
    }

    // MARK: - Scheduling

    private func removeAll() {
        center.removePendingRequests(withIdentifiers: [Self.weeklyId] + Self.datedIds)
    }

    private func apply() async {
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
