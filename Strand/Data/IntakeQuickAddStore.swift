import Foundation
import StrandAnalytics
import WhoopStore

/// One food entry made in the app (stage 3 specification §9.3, Path B). It records amounts, not
/// foods; the label stays on the phone and is never written to the database or a widget.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
struct IntakeEntry: Identifiable, Equatable, Codable {
    let id: UUID
    var loggedAt: Date
    /// Decided at save from the zone log; never re-keyed.
    let day: String
    /// Nil: this entry says nothing about protein.
    var proteinGrams: Double?
    var energyKcal: Double?
    /// At most `IntakeQuickAddStore.maxLabelLength` characters.
    var label: String?
}

/// The one writer of the `noop-intake` totals (§9.1, §9.3), on the hydration pattern: a per-day
/// entry list in the defaults, and the day's total in `metricSeries`. Every change writes the list
/// first and the total after it, so an interruption leaves the list ahead of the total and the next
/// `rebank` repairs it. Totals are never written as zero for a day that has no entry: its rows are
/// deleted and the day reads "not measured".
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
@MainActor
final class IntakeQuickAddStore {
    /// `unreadableEntries`: the day's stored list exists and does not decode; nothing overwrites it.
    /// `invalidDay`: a backdated day that no instant under the zone log falls inside.
    enum Failure: Error, Equatable { case nothingToSave, invalidAmount, storeUnavailable, unreadableEntries, invalidDay }

    /// The largest amount an entry may hold, in grams or kilocalories (§9.3).
    nonisolated static let maximumAmount = 100_000.0
    nonisolated static let maxLabelLength = 40

    private static let proteinKey = IntakeAggregation.proteinKey
    private static let energyKey = IntakeAggregation.energyKey
    private static let readAtKey = IntakeAggregation.readAtKey

    private let repository: Repository
    private let settings: IntakeSettings
    private let defaults: UserDefaults
    private let now: () -> Date
    private let zoneIdentifier: () -> String

    init(repository: Repository, settings: IntakeSettings, defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init,
         zoneIdentifier: @escaping () -> String = { TimeZone.current.identifier }) {
        self.repository = repository
        self.settings = settings
        self.defaults = defaults
        self.now = now
        self.zoneIdentifier = zoneIdentifier
    }

    /// True when `amount` may be saved: nil, or finite from 0 to `maximumAmount`.
    nonisolated static func isValidAmount(_ amount: Double?) -> Bool {
        guard let amount else { return true }
        return amount.isFinite && amount >= 0 && amount <= maximumAmount
    }

    // MARK: - The entry list

    /// The day's entries, ascending by `loggedAt`, then id. Empty when none is stored.
    func entries(day: String) -> [IntakeEntry] {
        (storedList(day) ?? []).sorted { ($0.loggedAt, $0.id.uuidString) < ($1.loggedAt, $1.id.uuidString) }
    }

    private func listKey(_ day: String) -> String { IntakeSettings.entriesKeyPrefix + day }

    /// The three states of a day's stored list: absent (a restored total has no list), readable
    /// (possibly empty, when the list was emptied), and present but unreadable.
    private enum StoredList { case absent, list([IntakeEntry]), unreadable }

    private func stored(_ day: String) -> StoredList {
        guard let raw = defaults.string(forKey: listKey(day)) else { return .absent }
        guard let list = try? JSONDecoder().decode([IntakeEntry].self, from: Data(raw.utf8)) else { return .unreadable }
        return .list(list)
    }

    /// The readable list; nil when the key is absent or its value does not decode.
    private func storedList(_ day: String) -> [IntakeEntry]? {
        if case .list(let list) = stored(day) { return list }
        return nil
    }

    /// The list a change starts from. An absent list over a restored total starts from one entry
    /// holding the restored amounts, so a change never silently replaces that total (§9.3). An
    /// unreadable list is refused rather than treated as empty.
    private func listForChange(day: String) async throws -> [IntakeEntry] {
        switch stored(day) {
        case .list(let list): return list
        case .unreadable: throw Failure.unreadableEntries
        case .absent:
            // Without the store the restored total cannot be seen, so it must not be overwritten.
            guard await repository.storeHandle() != nil else { throw Failure.storeUnavailable }
            guard let restored = await restoredTotal(day: day) else { return [] }
            return [try restoredEntry(restored, day: day)]
        }
    }

    private func restoredEntry(_ restored: IntakeStoredDay, day: String) throws -> IntakeEntry {
        try Self.validate(proteinGrams: restored.proteinGrams, energyKcal: restored.energyKcal)
        let loggedAt = restored.readAtEpochSeconds.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? now()
        return IntakeEntry(id: UUID(), loggedAt: loggedAt, day: day, proteinGrams: restored.proteinGrams,
                           energyKcal: restored.energyKcal, label: nil)
    }

    private func writeList(_ entries: [IntakeEntry], day: String) {
        guard let raw = IntakeSettings.sortedJSON(entries) else { return }
        defaults.set(raw, forKey: listKey(day))
    }

    // MARK: - Changes

    @discardableResult
    func add(proteinGrams: Double?, energyKcal: Double?, label: String?, at instant: Date) async throws -> IntakeEntry {
        try Self.validate(proteinGrams: proteinGrams, energyKcal: energyKcal)
        let log = logCurrentZone()
        let day = IntakeAggregation.dayKey(epochSeconds: Int(instant.timeIntervalSince1970.rounded(.down)), zoneLog: log)
        return try await insert(proteinGrams: proteinGrams, energyKcal: energyKcal, label: label, at: instant, day: day)
    }

    /// The backdating entry point of the quick-add sheet. `today` is the day the sheet labels
    /// "Today": that choice is logged now, on the real current day, even when the sheet was opened
    /// before midnight. Any other day is logged at an instant that the zone log keys to that day, so
    /// the instant and its key come from one log.
    @discardableResult
    func add(proteinGrams: Double?, energyKcal: Double?, label: String?, on day: String,
             today: String) async throws -> IntakeEntry {
        try Self.validate(proteinGrams: proteinGrams, energyKcal: energyKcal)
        let log = logCurrentZone()
        let current = now()
        let currentDay = IntakeAggregation.dayKey(epochSeconds: Int(current.timeIntervalSince1970.rounded(.down)), zoneLog: log)
        if day == today || day == currentDay {
            return try await insert(proteinGrams: proteinGrams, energyKcal: energyKcal, label: label, at: current,
                                    day: currentDay)
        }
        guard let seconds = Self.instant(inside: day, zoneLog: log) else { throw Failure.invalidDay }
        return try await insert(proteinGrams: proteinGrams, energyKcal: energyKcal, label: label,
                                at: Date(timeIntervalSince1970: TimeInterval(seconds)), day: day)
    }

    /// The zone in force is logged before an entry is keyed (§7.1). Returns the log to key with.
    private func logCurrentZone() -> [IntakeZoneSegment] {
        let log = IntakeAggregation.appending(zoneIdentifier: zoneIdentifier(),
                                              at: Int(now().timeIntervalSince1970), to: settings.zoneLog)
        if log != settings.zoneLog { settings.zoneLog = log }
        return log
    }

    private func insert(proteinGrams: Double?, energyKcal: Double?, label: String?, at instant: Date,
                        day: String) async throws -> IntakeEntry {
        var list = try await listForChange(day: day)
        let entry = IntakeEntry(id: UUID(), loggedAt: instant, day: day, proteinGrams: proteinGrams,
                                energyKcal: energyKcal, label: Self.cut(label))
        list.append(entry)
        writeList(list, day: day)
        try await rebank(day: day, stamp: true)
        return entry
    }

    /// Noon of `day` in the zone the log puts in force there, or, when that instant keys to another
    /// day (a zone change of more than twelve hours nearby), the hour nearest noon, in that zone or
    /// another logged one, that keys back to `day`. Nil when `day` is not a canonical key or no
    /// candidate keys to it.
    nonisolated static func instant(inside day: String, zoneLog: [IntakeZoneSegment]) -> Int? {
        guard CanonicalDay.isValid(day), let (year, month, date) = WeeklyDigestEngine.parseYMD(day) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        func noon(in zone: TimeZone, hour: Int = 12) -> Int? {
            calendar.timeZone = zone
            return calendar.date(from: DateComponents(year: year, month: month, day: date, hour: hour))
                .map { Int($0.timeIntervalSince1970) }
        }
        var zones: [TimeZone] = []
        if let utcNoon = noon(in: TimeZone(identifier: "UTC")!) {
            zones.append(IntakeAggregation.zone(atEpochSeconds: utcNoon, zoneLog: zoneLog))
        }
        for segment in zoneLog.reversed() {
            if let zone = TimeZone(identifier: segment.zoneIdentifier) { zones.append(zone) }
        }
        // Noon first, then outwards an hour at a time: 12, 11, 13, 10, 14, ... 0, 23.
        let hours = [12] + (1...12).flatMap { [12 - $0, 12 + $0] }.filter { (0...23).contains($0) }
        for hour in hours {
            for zone in zones {
                if let candidate = noon(in: zone, hour: hour),
                   IntakeAggregation.dayKey(epochSeconds: candidate, zoneLog: zoneLog) == day {
                    return candidate
                }
            }
        }
        return nil
    }

    func update(_ entry: IntakeEntry) async throws {
        try Self.validate(proteinGrams: entry.proteinGrams, energyKcal: entry.energyKcal)
        var list = try await listForChange(day: entry.day)
        var edited = entry
        edited.label = Self.cut(entry.label)
        if let index = list.firstIndex(where: { $0.id == entry.id }) {
            list[index] = edited
        } else {
            list.append(edited)
        }
        writeList(list, day: entry.day)
        try await rebank(day: entry.day, stamp: true)
    }

    func delete(id: UUID, day: String) async throws {
        guard var list = storedList(day), list.contains(where: { $0.id == id }) else { return }
        list.removeAll { $0.id == id }
        writeList(list, day: day)
        try await rebank(day: day, stamp: true)
    }

    /// Re-derives the stored totals for `day` from its entries: the repair the screen runs. A day
    /// whose list key is absent (a total restored from a backup, which carries no list) or whose
    /// list does not decode is left as it is; a day whose list is empty has its three rows deleted.
    /// When the stored totals already follow the list, nothing is written, so `intake_read_at`
    /// stays the time of the last entry change (§9.1).
    func rebank(day: String) async throws {
        try await rebank(day: day, stamp: false)
    }

    /// `stamp`: a change to the list was just written, so `intake_read_at` becomes now.
    private func rebank(day: String, stamp: Bool) async throws {
        guard let list = storedList(day) else { return }
        guard let store = await repository.storeHandle() else { throw Failure.storeUnavailable }
        let protein = Self.sum(list.compactMap(\.proteinGrams))
        let energy = Self.sum(list.compactMap(\.energyKcal))
        let readAt = Double(Int(now().timeIntervalSince1970.rounded(.down)))
        let id = IntakeProvider.quickAddSourceId
        if !stamp, !list.isEmpty {
            func value(_ key: String) async throws -> Double? {
                try await store.metricSeries(deviceId: id, key: key, from: day, to: day).first?.value
            }
            let storedProtein = try await value(Self.proteinKey)
            let storedEnergy = try await value(Self.energyKey)
            let storedReadAt = try await value(Self.readAtKey)
            if storedProtein == protein, storedEnergy == energy, storedReadAt != nil { return }
        }
        if list.isEmpty {
            for key in [Self.proteinKey, Self.energyKey, Self.readAtKey] {
                _ = try await store.deleteMetricSeriesPoint(deviceId: id, day: day, key: key)
            }
        } else {
            // One call, one transaction: a total and its time cannot be torn apart (§9.1).
            var points = [MetricPoint(day: day, key: Self.readAtKey, value: readAt)]
            if let protein { points.append(MetricPoint(day: day, key: Self.proteinKey, value: protein)) }
            if let energy { points.append(MetricPoint(day: day, key: Self.energyKey, value: energy)) }
            _ = try await store.upsertMetricSeries(points, deviceId: id)
            if protein == nil { _ = try await store.deleteMetricSeriesPoint(deviceId: id, day: day, key: Self.proteinKey) }
            if energy == nil { _ = try await store.deleteMetricSeriesPoint(deviceId: id, day: day, key: Self.energyKey) }
        }
        IntakeProvider.funnelDidWrite(repository)
    }

    // MARK: - A restored total (§9.3)

    /// The stored `noop-intake` total of a day that has no entry list, else nil.
    func restoredTotal(day: String) async -> IntakeStoredDay? {
        guard case .absent = stored(day), let store = await repository.storeHandle() else { return nil }
        let id = IntakeProvider.quickAddSourceId
        func value(_ key: String) async -> Double? {
            let points = (try? await store.metricSeries(deviceId: id, key: key, from: day, to: day)) ?? []
            return points.first?.value
        }
        let protein = await value(Self.proteinKey)
        let energy = await value(Self.energyKey)
        let readAt = await value(Self.readAtKey)
        guard protein != nil || energy != nil else { return nil }
        return IntakeStoredDay(day: day, proteinGrams: protein, energyKcal: energy,
                               readAtEpochSeconds: readAt.flatMap { $0.isFinite && abs($0) < 1e15 ? Int($0) : nil })
    }

    /// Writes one real entry holding the restored amounts and rebanks, so the day then proceeds as
    /// any edit. The entry is logged at the restored total's stored time, or now when it has none.
    @discardableResult
    func replaceRestoredTotal(day: String) async throws -> IntakeEntry {
        guard let restored = await restoredTotal(day: day) else { throw Failure.nothingToSave }
        let entry = try restoredEntry(restored, day: day)
        writeList([entry], day: day)
        try await rebank(day: day, stamp: true)
        return entry
    }

    // MARK: - Rules

    private static func validate(proteinGrams: Double?, energyKcal: Double?) throws {
        guard proteinGrams != nil || energyKcal != nil else { throw Failure.nothingToSave }
        guard isValidAmount(proteinGrams), isValidAmount(energyKcal) else { throw Failure.invalidAmount }
    }

    /// The sum of the amounts, nil when there is none (§7.2 step 3).
    private static func sum(_ amounts: [Double]) -> Double? {
        amounts.isEmpty ? nil : amounts.reduce(0, +)
    }

    private static func cut(_ label: String?) -> String? {
        guard let label else { return nil }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxLabelLength))
    }
}
