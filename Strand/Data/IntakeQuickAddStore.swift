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
    enum Failure: Error, Equatable { case nothingToSave, invalidAmount, storeUnavailable }

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

    /// Nil when the key is absent (a restored total has no list); empty when the list was emptied.
    private func storedList(_ day: String) -> [IntakeEntry]? {
        guard let raw = defaults.string(forKey: listKey(day)) else { return nil }
        return (try? JSONDecoder().decode([IntakeEntry].self, from: Data(raw.utf8))) ?? []
    }

    private func writeList(_ entries: [IntakeEntry], day: String) {
        guard let raw = IntakeSettings.sortedJSON(entries) else { return }
        defaults.set(raw, forKey: listKey(day))
    }

    // MARK: - Changes

    @discardableResult
    func add(proteinGrams: Double?, energyKcal: Double?, label: String?, at instant: Date) async throws -> IntakeEntry {
        try Self.validate(proteinGrams: proteinGrams, energyKcal: energyKcal)
        // The zone in force is logged before the entry is keyed (§7.1).
        let log = IntakeAggregation.appending(zoneIdentifier: zoneIdentifier(),
                                              at: Int(now().timeIntervalSince1970), to: settings.zoneLog)
        if log != settings.zoneLog { settings.zoneLog = log }
        let day = IntakeAggregation.dayKey(epochSeconds: Int(instant.timeIntervalSince1970.rounded(.down)), zoneLog: log)
        let entry = IntakeEntry(id: UUID(), loggedAt: instant, day: day, proteinGrams: proteinGrams,
                                energyKcal: energyKcal, label: Self.cut(label))
        var list = storedList(day) ?? []
        list.append(entry)
        writeList(list, day: day)
        try await rebank(day: day)
        return entry
    }

    func update(_ entry: IntakeEntry) async throws {
        try Self.validate(proteinGrams: entry.proteinGrams, energyKcal: entry.energyKcal)
        var list = storedList(entry.day) ?? []
        var edited = entry
        edited.label = Self.cut(entry.label)
        if let index = list.firstIndex(where: { $0.id == entry.id }) {
            list[index] = edited
        } else {
            list.append(edited)
        }
        writeList(list, day: entry.day)
        try await rebank(day: entry.day)
    }

    func delete(id: UUID, day: String) async throws {
        guard var list = storedList(day), list.contains(where: { $0.id == id }) else { return }
        list.removeAll { $0.id == id }
        writeList(list, day: day)
        try await rebank(day: day)
    }

    /// Re-derives the stored totals for `day` from its entries. A day whose list key is absent (a
    /// total restored from a backup, which carries no list) is left as it is; a day whose list is
    /// empty has its three rows deleted.
    func rebank(day: String) async throws {
        guard let list = storedList(day) else { return }
        guard let store = await repository.storeHandle() else { throw Failure.storeUnavailable }
        let protein = Self.sum(list.compactMap(\.proteinGrams))
        let energy = Self.sum(list.compactMap(\.energyKcal))
        let readAt = Double(Int(now().timeIntervalSince1970.rounded(.down)))
        let id = IntakeProvider.quickAddSourceId
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
        guard storedList(day) == nil, let store = await repository.storeHandle() else { return nil }
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
        try Self.validate(proteinGrams: restored.proteinGrams, energyKcal: restored.energyKcal)
        let loggedAt = restored.readAtEpochSeconds.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? now()
        let entry = IntakeEntry(id: UUID(), loggedAt: loggedAt, day: day, proteinGrams: restored.proteinGrams,
                                energyKcal: restored.energyKcal, label: nil)
        writeList([entry], day: day)
        try await rebank(day: day)
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
