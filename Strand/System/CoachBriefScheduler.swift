import Foundation
import UserNotifications
#if os(iOS)
import BackgroundTasks
import WidgetKit
#endif

/// PRD-K5: a user-scheduled, LOCAL notification that delivers a one-line morning coaching brief,
/// generated on-device via the user's already-configured Coach provider, at a chosen time each day.
/// Tap → opens Coach with the full brief. No push server, no cloud — the network call is the SAME
/// bring-your-own-key request Coach already makes on every send, just user-armed on a daily timer
/// instead of triggered by a tap. Default OFF, like every NOOP automation.
///
/// Cross-platform (macOS + iOS), same architecture as `ScheduledDebugExport`:
/// - **macOS** — the app is usually running; a foreground `DispatchSourceTimer` fires at the chosen
///   minute, and `catchUpIfDue` covers the time having passed while the app wasn't open.
/// - **iOS** — a sideloaded, backgrounded app can't guarantee a wake at the exact minute. A
///   `BGAppRefreshTaskRequest` is submitted for *no earlier than* the chosen time; iOS decides when it
///   actually runs. If the slot is missed entirely (app never woken), the next foreground open's
///   `activateIfEnabled` catches up and generates then instead — same honest "best-effort" posture
///   `ScheduledDebugExport`'s Settings copy already uses.
///
/// Triple-gated network call: `enabled` (this feature, default OFF) + a saved Coach key + the existing
/// `dataConsent`. `generateBrief` is `AICoachEngine.generateBrief()`, itself gated on both of those; this
/// scheduler additionally never marks a day "done" on a failed generation, so a missing key/consent (or
/// a transient network failure) simply retries next wake rather than going permanently silent.
@MainActor
enum CoachBriefScheduler {

    // MARK: - Persisted settings (own keys; mirrors ScheduledDebugExport's shape)

    private enum K {
        static let enabled = "coachBrief.enabled"          // master enable; default OFF
        static let time = "coachBrief.timeMinutes"         // minutes since local midnight; default 07:00
        static let lastRun = "coachBrief.lastRunDayKey"    // yyyy-MM-dd of the last GENERATED brief (dedup)
        static let storedBrief = "coachBrief.storedText"   // legacy cache without a connection owner
        static let hasUnconsumed = "coachBrief.hasUnconsumedBrief" // legacy consumption flag
        static let connection = "coachBrief.connection"
        static let storedRecord = "coachBrief.storedRecord"
        static let notificationConnection = "coachBrief.connectionID"
        // K10: the brief text mirrored into the App Group so the widget extension (separate process)
        // can read it. The app's own UserDefaults.standard isn't visible to the widget.
        static let widgetBriefKey = "coachBrief.widgetText"
        static let widgetBriefDateKey = "coachBrief.widgetDate"
    }

    /// 07:00 — a brief waiting when you check your phone (matches `ScheduledDebugExport`'s default).
    static let defaultTimeMinutes = 7 * 60
    private static let minutesPerDay = 24 * 60

    /// Category id the posted notification carries, so `NotificationPresenter` can recognise a brief tap
    /// (as opposed to any other local notification) and route it to Coach.
    static let notificationCategoryId = "coach-brief"
    private static let requestIdPrefix = "coach-brief-"
    private static var lastNotificationAlignment: UUID?

    /// The Coach master switch, under the same `noop.` key Android writes and `RootTabView` binds.
    ///
    /// Read through `object(forKey:)` rather than `bool(forKey:)` because this pref defaults to TRUE and
    /// `bool(forKey:)` answers FALSE for a key that was never written. Taking the shorter spelling here
    /// would have disabled the Coach for every install that had never opened the toggle, which is exactly
    /// the population whose behaviour must not change.
    static var coachMasterEnabled: Bool {
        guard UserDefaults.standard.object(forKey: "noop.coachEnabled") != nil else { return true }
        return UserDefaults.standard.bool(forKey: "noop.coachEnabled")
    }

    /// Tear down whatever the brief has left lying around when the Coach master switch goes off.
    ///
    /// Gating `isEnabled` alone stops the NEXT brief being generated, which is the network half, but it
    /// leaves the LAST one on the wearer's home screen: the widget renders whatever was last published,
    /// so AI output would go on being displayed after the AI was switched off. Mirrors what
    /// `setEnabled(false)` already does for the brief's own flag, and what Android's `reschedule` does
    /// when it sees the master switch is off.
    ///
    /// Deliberately one-directional. Re-arming is not done here because this type is armed by
    /// `activateIfEnabled`, which `CoachView` calls when it appears -- a route that is reachable again the
    /// moment the switch goes back on, since the tab returns with it. Android re-arms on the flip instead,
    /// because there the brief is armed from app start rather than from the Coach screen.
    static func applyMasterSwitch(_ on: Bool) {
        guard !on else { return }
        cancel()
        // A brief already DELIVERED sits in Notification Centre until the wearer clears it, and tapping it
        // routes to Coach. Same leak as the widget, one surface over: AI output still on display, and in
        // this case still interactive, after the AI was switched off. Pending requests go too, so nothing
        // already queued can arrive afterwards.
        let centre = UNUserNotificationCenter.current()
        centre.getDeliveredNotifications { delivered in
            let ids = delivered.map(\.request.identifier).filter { $0.hasPrefix(requestIdPrefix) }
            guard !ids.isEmpty else { return }
            centre.removeDeliveredNotifications(withIdentifiers: ids)
        }
        centre.getPendingNotificationRequests { pending in
            let ids = pending.map(\.identifier).filter { $0.hasPrefix(requestIdPrefix) }
            guard !ids.isEmpty else { return }
            centre.removePendingNotificationRequests(withIdentifiers: ids)
        }
        #if os(iOS)
        publishToWidget(nil)
        #endif
    }

    /// Whether the daily brief should run. Both gates, so the brief's own default-off flag keeps its
    /// meaning while the master switch can veto it outright.
    static var isEnabled: Bool { coachMasterEnabled && UserDefaults.standard.bool(forKey: K.enabled) }

    /// Time-of-day to generate, minutes since local midnight. Clamped to a valid minute. Default 07:00.
    static var timeMinutes: Int {
        let v = UserDefaults.standard.object(forKey: K.time) as? Int ?? defaultTimeMinutes
        return min(max(v, 0), minutesPerDay - 1)
    }

    /// A connection generation also distinguishes A → B → A from an uninterrupted connection to A.
    /// Owners contain only a provider name and, for ChatGPT, its opaque local profile identifier.
    struct Connection: Codable, Equatable {
        let owner: String?
        let generation: UUID
    }

    private struct StoredBrief: Codable {
        let connection: Connection
        let text: String
        var unconsumed: Bool
    }

    /// Align before using a restored session as well as after a selected provider/profile changes.
    /// Persisting the owner first makes a crash before cache removal fail closed on the next read.
    static func alignStoredBriefOwner(_ owner: String?) {
        var retired = false
        let connection = alignStoredBriefOwner(owner, defaults: .standard, clearPresentation: {
            retired = true
            #if os(iOS)
            publishToWidget(nil)
            #endif
        })
        if retired || lastNotificationAlignment != connection.generation {
            lastNotificationAlignment = connection.generation
            removeNotifications(except: connection.generation.uuidString)
        }
    }

    @discardableResult
    static func alignStoredBriefOwner(_ owner: String?, defaults: UserDefaults,
                                      clearPresentation: () -> Void) -> Connection {
        let previous = storedConnection(defaults: defaults)
        let normalizedOwner = owner.flatMap { $0.isEmpty ? nil : $0 }
        let connection = previous.flatMap { $0.owner == normalizedOwner ? $0 : nil }
            ?? Connection(owner: normalizedOwner, generation: UUID())
        if connection != previous, let data = try? JSONEncoder().encode(connection) {
            defaults.set(data, forKey: K.connection)
            // A different selected connection gets its own daily generation, keeping its schedule.
            defaults.removeObject(forKey: K.lastRun)
        }
        let cached = decodedBrief(defaults: defaults)
        let hasLegacy = defaults.object(forKey: K.storedBrief) != nil || defaults.object(forKey: K.hasUnconsumed) != nil
        let invalidRecord = defaults.object(forKey: K.storedRecord) != nil
            && (cached?.connection != connection || connection.owner == nil)
        if connection != previous || hasLegacy || invalidRecord {
            // Clear visible output before removing the invalid record, so a crash in between still
            // leaves evidence for the next launch to repeat the retirement.
            clearPresentation()
            retireStoredBrief(defaults: defaults)
        }
        return connection
    }

    static func storedConnection(defaults: UserDefaults) -> Connection? {
        guard let data = defaults.data(forKey: K.connection) else { return nil }
        return try? JSONDecoder().decode(Connection.self, from: data)
    }

    private static func decodedBrief(defaults: UserDefaults) -> StoredBrief? {
        guard let data = defaults.data(forKey: K.storedRecord) else { return nil }
        return try? JSONDecoder().decode(StoredBrief.self, from: data)
    }

    private static func validBrief(defaults: UserDefaults) -> StoredBrief? {
        guard let connection = storedConnection(defaults: defaults), connection.owner != nil,
              let record = decodedBrief(defaults: defaults), record.connection == connection else { return nil }
        return record
    }

    private static func retireStoredBrief(defaults: UserDefaults) {
        defaults.removeObject(forKey: K.storedRecord)
        defaults.removeObject(forKey: K.storedBrief)
        defaults.removeObject(forKey: K.hasUnconsumed)
    }

    /// The last completed brief for the currently selected connection only.
    static var storedBrief: String? { validBrief(defaults: .standard)?.text }

    /// True when a generated brief hasn't yet been surfaced in the Coach transcript. Set right after a
    /// successful generation; cleared by `consumeStoredBrief()`.
    static var hasUnconsumedBrief: Bool { validBrief(defaults: .standard)?.unconsumed == true }

    /// Coach reads this once (on appear, with an empty transcript) to surface the stored brief as its
    /// first message without re-generating or re-sending anything. Returns nil (and leaves state
    /// untouched) when there's nothing unconsumed, so a normal open is unaffected.
    static func consumeStoredBrief() -> String? {
        var retired = false
        let text = consumeStoredBrief(defaults: .standard, clearPresentation: {
            retired = true
            #if os(iOS)
            publishToWidget(nil)
            #endif
        })
        let generation = storedConnection(defaults: .standard)?.generation
        if retired || lastNotificationAlignment != generation {
            lastNotificationAlignment = generation
            removeNotifications(except: generation?.uuidString)
        }
        return text
    }

    static func consumeStoredBrief(defaults: UserDefaults, clearPresentation: () -> Void) -> String? {
        guard var record = validBrief(defaults: defaults) else {
            if defaults.object(forKey: K.storedRecord) != nil || defaults.object(forKey: K.storedBrief) != nil {
                clearPresentation()
                retireStoredBrief(defaults: defaults)
            }
            return nil
        }
        guard record.unconsumed else { return nil }
        record.unconsumed = false
        guard let data = try? JSONEncoder().encode(record) else { return nil }
        defaults.set(data, forKey: K.storedRecord)
        return record.text
    }

    /// Owner and text are one encoded value, so interruption cannot attribute an old text to a new owner.
    @discardableResult
    static func storeCompletedBrief(_ text: String, day: String, connection: Connection,
                                    defaults: UserDefaults) -> Bool {
        guard connection.owner != nil, storedConnection(defaults: defaults) == connection,
              let data = try? JSONEncoder().encode(StoredBrief(connection: connection, text: text, unconsumed: true)) else {
            return false
        }
        defaults.set(data, forKey: K.storedRecord)
        defaults.set(day, forKey: K.lastRun)
        return true
    }

    private static func removeNotifications(except connectionID: String?) {
        let centre = UNUserNotificationCenter.current()
        centre.getDeliveredNotifications { delivered in
            Task { @MainActor in
                guard storedConnection(defaults: .standard)?.generation.uuidString == connectionID else { return }
                let ids = delivered.map(\.request).filter {
                    $0.identifier.hasPrefix(requestIdPrefix)
                        && (connectionID == nil || ($0.content.userInfo[K.notificationConnection] as? String) != connectionID)
                }.map(\.identifier)
                if !ids.isEmpty { centre.removeDeliveredNotifications(withIdentifiers: ids) }
            }
        }
        centre.getPendingNotificationRequests { pending in
            Task { @MainActor in
                guard storedConnection(defaults: .standard)?.generation.uuidString == connectionID else { return }
                let ids = pending.filter {
                    $0.identifier.hasPrefix(requestIdPrefix)
                        && (connectionID == nil || ($0.content.userInfo[K.notificationConnection] as? String) != connectionID)
                }.map(\.identifier)
                if !ids.isEmpty { centre.removePendingNotificationRequests(withIdentifiers: ids) }
            }
        }
    }

    // MARK: - K10: Widget-facing API (App Group, iOS only)

    #if os(iOS)
    /// Publish (or clear) the brief into the App Group so the widget extension can read it. Called
    /// from `catchUpIfDue` / `generateNow` after a successful generation, and from `setEnabled(false)`
    /// to clear the widget when the user turns the feature off.
    static func publishToWidget(_ text: String?) {
        guard let defaults = UserDefaults(suiteName: WidgetSnapshot.suiteName) else { return }
        if let text {
            defaults.set(text, forKey: K.widgetBriefKey)
            defaults.set(Date(), forKey: K.widgetBriefDateKey)
        } else {
            defaults.removeObject(forKey: K.widgetBriefKey)
            defaults.removeObject(forKey: K.widgetBriefDateKey)
        }
        // Nudge WidgetKit to reload the coach-brief widget's timeline so it picks up the new text
        // without waiting for the next scheduled refresh. The kind string must match the widget's
        // `kind` property (see CoachBriefWidget.swift in StrandiOSWidgets).
        WidgetCenter.shared.reloadTimelines(ofKind: Self.widgetKind)
    }
    #endif

    /// The WidgetKit kind string for the coach-brief widget. Must match the `kind` property on
    /// `CoachBriefWidget` in `StrandiOSWidgets/`. Declared here so `publishToWidget` can reload
    /// timelines without importing the widget extension's type (the app target can't see it).
    static let widgetKind = "CoachBriefWidget"

    // MARK: - Enable / configure (Settings calls these)

    /// The result of enabling the schedule — mirrors `WindDownNudge.EnableOutcome` so the UI can revert
    /// the toggle and point at Settings on denial instead of persisting a dead "on" state.
    enum EnableOutcome { case scheduled, denied, off }

    /// Enable/disable and (re)schedule. Enabling gates on notification authorization first (asks once if
    /// undetermined; reports `.denied` rather than silently scheduling something the OS will never
    /// deliver). `completion` always runs on the main actor.
    static func setEnabled(_ on: Bool,
                            generateBrief: @escaping () async -> String?,
                            completion: (@MainActor (EnableOutcome) -> Void)? = nil) {
        guard on else {
            UserDefaults.standard.set(false, forKey: K.enabled)
            cancel()
            #if os(iOS)
            publishToWidget(nil)  // K10: clear the widget when the feature is turned off
            #endif
            completion?(.off)
            return
        }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    UserDefaults.standard.set(true, forKey: K.enabled)
                    scheduleNext(generateBrief: generateBrief)
                    completion?(.scheduled)
                case .notDetermined:
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                        Task { @MainActor in
                            if granted {
                                UserDefaults.standard.set(true, forKey: K.enabled)
                                scheduleNext(generateBrief: generateBrief)
                                completion?(.scheduled)
                            } else {
                                UserDefaults.standard.set(false, forKey: K.enabled)
                                completion?(.denied)
                            }
                        }
                    }
                default:
                    UserDefaults.standard.set(false, forKey: K.enabled)
                    completion?(.denied)
                }
            }
        }
    }

    /// Update the time-of-day and reschedule so the new time takes effect immediately.
    static func setTimeMinutes(_ minutes: Int, generateBrief: @escaping () async -> String?) {
        UserDefaults.standard.set(min(max(minutes, 0), minutesPerDay - 1), forKey: K.time)
        if isEnabled { scheduleNext(generateBrief: generateBrief) }
    }

    /// Call whenever Coach (or its settings) appears so the schedule self-heals (re-arms the macOS timer
    /// after a relaunch, re-submits the iOS request) and a slot missed while the app wasn't open still
    /// generates once. No-op when the feature is off.
    static func activateIfEnabled(generateBrief: @escaping () async -> String?) {
        guard isEnabled else { return }
        scheduleNext(generateBrief: generateBrief)
        Task { await catchUpIfDue(generateBrief: generateBrief) }
    }

    /// The explicit "Generate now" button: always generates and stores, ignoring the once-per-day dedup,
    /// so a tap produces a fresh brief there and then. Does NOT post a notification (the user is already
    /// looking at Coach) and does NOT touch `lastRun`, so today's scheduled slot still fires normally.
    /// Returns the brief text, or nil on failure (no key/consent/network) — the caller surfaces that.
    @discardableResult
    static func generateNow(generateBrief: () async -> String?) async -> String? {
        guard !Task.isCancelled else { return nil }
        let text = await generateBrief()
        guard !Task.isCancelled else { return nil }
        return text
    }

    // MARK: - Due check + generation

    /// Whether a generation attempt is already running, so only one can be in flight at a time.
    ///
    /// `lastRun` is written only AFTER a successful generation, deliberately, so a failure retries at the
    /// next wake rather than marking the day done. That leaves the day guard open across a suspension:
    /// a caller reads `lastRun`, `await generateBrief()` suspends, and a second caller reaching the same
    /// guard still sees yesterday's value. Two call sites now arm the schedule (Coach's own `.task` and
    /// the scene-phase entry), so a cold launch straight onto the Coach tab could run two generations at
    /// once, paying for two provider calls and posting two brief notifications for the same day.
    ///
    /// Claiming is what makes the day guard hold across that await. MainActor-isolated because the two
    /// callers arrive on different executors: `activateIfEnabled` starts an unstructured `Task` with no
    /// isolation, while the BGTask handler runs its worker on the MainActor.
    @MainActor private static var generationInFlight = false

    /// Take the single generation slot, or report that another attempt already holds it.
    @MainActor private static func claimGeneration() -> Bool {
        guard !generationInFlight else { return false }
        generationInFlight = true
        return true
    }

    /// Give the generation slot back on every exit, including cancellation and failed generation.
    @MainActor private static func releaseGeneration() { generationInFlight = false }

    /// If today's brief is due (we're at/after the chosen time and haven't generated today), generate it
    /// once: store the text, mark today done, and post the notification. Covers macOS launches where the
    /// time passed while the app wasn't open, and the iOS foreground/BGTask paths.
    ///
    /// Returns whether this call can be considered successful: `true` when there was nothing to do
    /// (feature off, not yet time, or already ran today) or generation succeeded; `false` when cancelled
    /// or generation failed (so the iOS BGTask handler can report the real outcome and
    /// retry on the next wake instead of marking the day done on a failure).
    @discardableResult
    static func catchUpIfDue(generateBrief: () async -> String?) async -> Bool {
        let dependencies = Dependencies(
            isEnabled: { isEnabled }, timeMinutes: { timeMinutes },
            lastRunDay: { UserDefaults.standard.string(forKey: K.lastRun) },
            connection: { storedConnection(defaults: .standard) },
            publish: { day, text, connection in
                guard storeCompletedBrief(text, day: day, connection: connection, defaults: .standard) else { return false }
                #if os(iOS)
                publishToWidget(text)
                #endif
                postNotification(title: String(localized: "Your morning brief"),
                                  body: oneLineSummary(from: text), connectionID: connection.generation.uuidString)
                return true
            },
            unavailable: { connection in
                postNotification(title: String(localized: "Coach brief unavailable"),
                                  body: String(localized: "Couldn't generate today's brief. Tap to try again in Coach."),
                                  isRetry: true, connectionID: connection.generation.uuidString)
            })
        return await catchUpIfDue(generateBrief: generateBrief, now: Date(), calendar: .current,
                                  dependencies: dependencies)
    }

    /// The publication boundary is injected so cancellation can be tested without posting notifications
    /// or changing the install's persisted brief. Production keeps storage and publication together.
    struct Dependencies {
        let isEnabled: () -> Bool
        let timeMinutes: () -> Int
        let lastRunDay: () -> String?
        let connection: () -> Connection?
        let publish: (_ day: String, _ text: String, _ connection: Connection) -> Bool
        let unavailable: (_ connection: Connection) -> Void
    }

    static func catchUpIfDue(generateBrief: () async -> String?, now: Date, calendar: Calendar,
                             dependencies: Dependencies) async -> Bool {
        guard !Task.isCancelled else { return false }
        guard dependencies.isEnabled() else { return true }
        guard let connection = dependencies.connection(), connection.owner != nil else { return false }
        let comps = calendar.dateComponents([.hour, .minute], from: now)
        let nowMinutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        guard nowMinutes >= dependencies.timeMinutes() else { return true } // not yet time today
        let day = dayKey(now, timeZone: calendar.timeZone)
        guard dependencies.lastRunDay() != day else { return true } // already ran today

        // One attempt at a time; see `generationInFlight` for why the day guard alone is not enough.
        guard claimGeneration() else { return true }
        defer { releaseGeneration() }
        let generated = await generateBrief()
        // Providers may swallow cancellation and return nil, or even return the text accumulated so
        // far. Neither result is a completed brief after expiration. Revoking the schedule while the
        // request is suspended must also prevent a late notification or widget repopulation.
        guard !Task.isCancelled, dependencies.isEnabled(), dependencies.connection() == connection else { return false }

        guard let text = generated, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // No key/consent/network, or the provider returned nothing. Never mark the day done, so the
            // next wake (BGTask retry, or the next foreground open) tries again. Post a low-key retry
            // notification rather than silently doing nothing — the PRD's "unavailable, tap to retry".
            dependencies.unavailable(connection)
            return false
        }

        // No suspension between the cancellation check and this synchronous publication boundary.
        return dependencies.publish(day, text, connection)
    }

    /// Pure: the notification body is the brief's first non-empty line, trimmed and length-capped so it
    /// fits a notification banner. Unit-testable without any I/O.
    static func oneLineSummary(from brief: String, maxLength: Int = 120) -> String {
        let firstLine = brief
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? brief
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }
        let cut = trimmed.index(trimmed.startIndex, offsetBy: maxLength)
        return trimmed[..<cut].trimmingCharacters(in: .whitespaces) + "…"
    }

    private static func postNotification(title: String, body: String, isRetry: Bool = false, connectionID: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = notificationCategoryId
        content.userInfo[K.notificationConnection] = connectionID
        // Immediate delivery (trigger nil) — this fires the moment generation completes, it is not a
        // pre-scheduled fixed-content trigger like `WindDownNudge`'s. One id per connection/day keeps
        // retries together, while delayed cleanup for an old connection cannot delete a new one's brief.
        let request = UNNotificationRequest(identifier: requestIdPrefix + connectionID + "-" + dayKey(Date()),
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// yyyy-MM-dd local-day key for the once-per-day dedup. POSIX locale so the key is stable everywhere.
    private static func dayKey(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Seconds from now until the next wall-clock occurrence of `minuteOfDay` (today if still ahead, else
    /// tomorrow). Mirrors `ScheduledDebugExport.secondsToNextOccurrence`.
    private static func secondsToNextOccurrence(_ minuteOfDay: Int, now: Date = Date()) -> TimeInterval {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = minuteOfDay / 60
        comps.minute = minuteOfDay % 60
        comps.second = 0
        var target = cal.date(from: comps) ?? now
        if target <= now { target = cal.date(byAdding: .day, value: 1, to: target) ?? target }
        return max(1, target.timeIntervalSince(now))
    }

    // MARK: - Scheduling

    private static var macTimer: DispatchSourceTimer?

    /// (Re)arm the next occurrence. macOS uses a foreground `DispatchSourceTimer`; iOS submits a
    /// background-refresh request. Both target the next wall-clock occurrence of `timeMinutes`.
    private static func scheduleNext(generateBrief: @escaping () async -> String?) {
        #if os(macOS)
        macTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        let delay = secondsToNextOccurrence(timeMinutes)
        timer.schedule(deadline: .now() + delay)
        timer.setEventHandler {
            Task { @MainActor in
                guard isEnabled else { return }
                _ = await catchUpIfDue(generateBrief: generateBrief)
                scheduleNext(generateBrief: generateBrief)
            }
        }
        timer.resume()
        macTimer = timer
        #elseif os(iOS)
        submitBackgroundRequest()
        #endif
    }

    /// Cancel any armed schedule.
    private static func cancel() {
        #if os(macOS)
        macTimer?.cancel()
        macTimer = nil
        #elseif os(iOS)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: bgTaskIdentifier)
        #endif
    }

    // MARK: - iOS background task plumbing

    /// Settles a background run once, including expiration before its worker cancellation is installed.
    /// This contains no BGTask dependency so the real expiration race is testable with closures.
    final class TaskCompletionGuard: @unchecked Sendable {
        private let lock = NSLock()
        private let complete: (Bool) -> Void
        private var finished = false
        private var expired = false
        private var cancellationInstalled = false
        private var cancelWorker: (() -> Void)?

        init(complete: @escaping (Bool) -> Void) { self.complete = complete }

        var isExpired: Bool {
            lock.lock()
            defer { lock.unlock() }
            return expired
        }

        func installCancellation(_ cancel: @escaping () -> Void) {
            lock.lock()
            guard !cancellationInstalled else { lock.unlock(); return }
            cancellationInstalled = true
            let cancelImmediately = expired
            if !finished { cancelWorker = cancel }
            lock.unlock()
            if cancelImmediately { cancel() }
        }

        func expire() {
            lock.lock()
            guard !finished else { lock.unlock(); return }
            finished = true
            expired = true
            let cancel = cancelWorker
            cancelWorker = nil
            lock.unlock()
            cancel?()
            complete(false)
        }

        func finish(success: Bool) {
            lock.lock()
            guard !finished else { lock.unlock(); return }
            finished = true
            cancelWorker = nil
            lock.unlock()
            complete(success)
        }
    }

    #if os(iOS)
    /// iOS BGTask identifier, derived from the running bundle id so it tracks `BUNDLE_ID_PREFIX` and
    /// matches the iOS target's `BGTaskSchedulerPermittedIdentifiers` (Info.plist / project.yml).
    static let bgTaskIdentifier = (Bundle.main.bundleIdentifier ?? "com.noopapp.noop") + ".coachbrief"
    private static var logBackgroundFailure: ((String) -> Void)?

    /// Register the BGTask handler. MUST be called from the app's launch (before launch finishes) — call
    /// this from `StrandiOSApp.init()` with the app-owned Coach and strap log.
    static func register(generateBrief: @escaping () async -> String?, log: @escaping (String) -> Void) {
        logBackgroundFailure = log
        BGTaskScheduler.shared.register(forTaskWithIdentifier: bgTaskIdentifier, using: nil) { task in
            let completion = TaskCompletionGuard { success in
                task.setTaskCompleted(success: success)
                task.expirationHandler = nil
            }
            // Install exactly once, before creating a worker which could otherwise overwrite it or
            // start after expiration. The guard remembers early expiration until cancellation exists.
            task.expirationHandler = { completion.expire() }
            let worker = Task { @MainActor in
                guard !completion.isExpired, !Task.isCancelled else {
                    completion.finish(success: false)
                    return
                }
                guard isEnabled else {
                    completion.finish(success: true)
                    return
                }
                // Submit before awaiting a network operation: expiration must still leave the next
                // best-effort wake armed, even if this worker cannot finish its provider request.
                submitBackgroundRequest()
                let succeeded = await catchUpIfDue(generateBrief: generateBrief)
                completion.finish(success: succeeded && !Task.isCancelled)
            }
            completion.installCancellation { worker.cancel() }
        }
    }

    /// Submit a background-refresh request for *no earlier than* the next chosen time. iOS decides when
    /// (and whether) to actually run it — best-effort, same honesty as `ScheduledDebugExport`.
    private static func submitBackgroundRequest() {
        let request = BGAppRefreshTaskRequest(identifier: bgTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: secondsToNextOccurrence(timeMinutes))
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logBackgroundFailure?("coach brief: background request refused (\(error.localizedDescription))")
        }
    }
    #endif
}
