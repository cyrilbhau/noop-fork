import Foundation
import StrandAnalytics
import StrandImport
import WhoopStore

// Stage 4 (body record), docs/personal/superapp/specs/stage-4.md §7.6, §7.8, §8.2 and §9.1: the one
// read and write funnel of scans and benchmarks. Every read goes through `LabBookRows` (every device
// id present in the table, copies once, conflicting rows both kept); every scan write is ONE
// `replaceLabMarkers` call, so a scan appears, moves and disappears whole. A scan's total mass is an
// ordinary `weight` reading (ruling R41) and is read back through the weigh-in store.
//
// No Kotlin twin, by ruling R43 of the stage 1 specification.

/// One scan: every merged Lab Book row that shares one `source` and one `takenAt`, where at least one
/// row has a scan-only key, plus the `weight` and `body_fat` rows of that `(source, takenAt)` (§7.6).
struct BodyScan: Equatable, Identifiable {
    /// `"<source>\u{1F}<takenAt>"`.
    let id: String
    let source: String
    let takenAt: Int
    /// The stored day of the first member in field order (§7.6).
    let day: String
    /// Key -> stored-unit value, for readable keys with exactly one member.
    let values: [String: Double]
    /// Key -> the merged member rows, ordered by id. Two or more: the key is conflicting.
    let rows: [String: [LabMarkerRow]]
    /// Nil when there is no note row or the note key is conflicting.
    let note: String?
    /// Sorted. One member whose value is missing, in an unknown unit or out of range.
    let unreadableKeys: [String]
    /// Sorted. Two or more members.
    let conflictingKeys: [String]

    var isEditable: Bool { source == MarkerCatalog.scanSource && conflictingKeys.isEmpty }
    var isDeletable: Bool { source == MarkerCatalog.scanSource }

    /// The id of the scan at `(source, takenAt)`.
    static func id(source: String, takenAt: Int) -> String { "\(source)\u{1F}\(takenAt)" }
}

/// What a scan sheet saves: figures already in their stored units.
struct BodyScanDraft: Equatable {
    /// "yyyy-MM-dd", the chosen local day.
    var day: String
    /// Key -> stored-unit value; an absent key was not entered.
    var values: [String: Double]
    var note: String?
}

enum BodyRecordError: Error, Equatable {
    /// No scan-only numeric value in the draft.
    case nothingToSave
    case outOfRange(key: String)
    case noteTooLong
    /// The draft's day is not a canonical day key.
    case invalidDay
    case futureDay
    /// A body-scan row already holds the target instant, under any device id.
    case instantOccupied
    case scanNotFound
    /// The source is not `body-scan`, or a key is conflicting.
    case notEditable
    case storeUnavailable
}

@MainActor
final class BodyRecordStore {
    private let repository: Repository
    private let provider: BodyMeasurementProvider?
    private let timeZone: () -> TimeZone
    private let now: () -> Date
    /// The read a scan's total mass comes back through (§9.1).
    private let weighIns: WeighInStore

    init(repository: Repository, provider: BodyMeasurementProvider? = nil,
         timeZone: @escaping () -> TimeZone = { TimeZone.current },
         now: @escaping () -> Date = { Date() }) {
        self.repository = repository
        self.provider = provider
        self.timeZone = timeZone
        self.now = now
        self.weighIns = WeighInStore(repository: repository, timeZone: timeZone, now: now)
    }

    // MARK: - Scans

    /// Whether the local store can be opened (G9).
    func isAvailable() async -> Bool { await repository.storeHandle() != nil }

    /// Every scan, whatever its source, ordered by `takenAt` then `source`. Empty when the store
    /// cannot be read. It does not consult `noop.bodyRecordEnabled`: a caller outside the body
    /// record checks the flag first.
    func scans() async -> [BodyScan] {
        let activeDeviceId = repository.deviceId
        guard let store = await repository.storeHandle() else { return [] }
        let scanOnly = await LabBookRows.category(LabMarkerCategory.imaging.rawValue, store: store,
                                                  activeDeviceId: activeDeviceId)
            .filter { MarkerCatalog.isScanOnlyMarker($0.markerKey) }
        guard !scanOnly.isEmpty else { return [] }
        let totals = await weighIns.readings(.weight)
        let bodyFat = await LabBookRows.marker(MarkerCatalog.scanBodyFatKey, store: store,
                                               activeDeviceId: activeDeviceId)

        var membersByScan: [String: [LabMarkerRow]] = [:]
        for row in scanOnly {
            membersByScan[BodyScan.id(source: row.source, takenAt: row.takenAt), default: []].append(row)
        }
        for row in totals + bodyFat {
            let id = BodyScan.id(source: row.source, takenAt: row.takenAt)
            if membersByScan[id] != nil { membersByScan[id]?.append(row) }
        }
        return membersByScan.values.compactMap(Self.scan(from:))
            .sorted { ($0.takenAt, $0.source) < ($1.takenAt, $1.source) }
    }

    /// One scan from its merged member rows (§7.6).
    private static func scan(from members: [LabMarkerRow]) -> BodyScan? {
        guard let first = members.first else { return nil }
        let byKey = Dictionary(grouping: members, by: \.markerKey).mapValues { $0.sorted { $0.id < $1.id } }
        var values: [String: Double] = [:]
        var note: String?
        var unreadable: [String] = []
        var conflicting: [String] = []
        var day: String?
        for field in BodyScanField.all {
            guard let rows = byKey[field.key], let row = rows.first else { continue }
            if day == nil { day = row.day }
            if rows.count > 1 {
                conflicting.append(field.key)
                continue
            }
            if field.key == MarkerCatalog.scanNoteKey {
                note = row.valueText
                continue
            }
            if let value = readableValue(row, field: field) {
                values[field.key] = value
            } else {
                unreadable.append(field.key)
            }
        }
        return BodyScan(id: BodyScan.id(source: first.source, takenAt: first.takenAt), source: first.source,
                        takenAt: first.takenAt, day: day ?? first.day, values: values, rows: byKey, note: note,
                        unreadableKeys: unreadable.sorted(), conflictingKeys: conflicting.sorted())
    }

    /// The stored-unit value of a member, or nil when it is unreadable: no value, a unit that is not
    /// recognised, or a stored value outside the field's range.
    private static func readableValue(_ row: LabMarkerRow, field: BodyScanField) -> Double? {
        guard let raw = row.value, let range = field.range,
              let stored = MarkerUnitTable.storedValue(raw, key: field.key, rowUnit: row.unit),
              range.contains(stored) else { return nil }
        return stored
    }

    /// Saves a new scan, or replaces `existing` (§9.1). Everything is validated before anything is
    /// written, and the write is one transaction. Returns the scan as stored.
    @discardableResult
    func save(_ draft: BodyScanDraft, replacing existing: BodyScan?) async throws -> BodyScan {
        // Captured before the first suspension: the id, the zone and the clock of this write.
        let activeDeviceId = repository.deviceId
        let zone = timeZone()
        let instantNow = now()
        let note = try validate(draft, zone: zone, now: instantNow)
        guard let store = await repository.storeHandle() else { throw BodyRecordError.storeUnavailable }

        var current: BodyScan?
        if let existing {
            guard let found = await scans().first(where: { $0.id == existing.id }) else {
                throw BodyRecordError.scanNotFound
            }
            guard found.isEditable else { throw BodyRecordError.notEditable }
            current = found
        }

        let keepsDay = current.map { $0.day == draft.day } ?? false
        let takenAt = keepsDay ? current!.takenAt : Self.instant(day: draft.day, zone: zone, now: instantNow)
        let day = keepsDay ? current!.day : LocalDayWindows(timeZone: zone)
            .dayKey(for: Date(timeIntervalSince1970: TimeInterval(takenAt)))
        if !keepsDay, try await isOccupied(takenAt, store: store) { throw BodyRecordError.instantOccupied }

        var deleteIds: [String] = []
        var upserts: [LabMarkerRow] = []
        for field in BodyScanField.all {
            let isNote = field.key == MarkerCatalog.scanNoteKey
            let value = isNote ? nil : draft.values[field.key]
            let text = isNote ? note : nil
            let entered = isNote ? text != nil : value != nil
            let member = current?.rows[field.key]?.first
            let isUnreadable = current?.unreadableKeys.contains(field.key) ?? false

            if keepsDay, let member {
                if entered {
                    var updated = member
                    updated.value = value
                    updated.valueText = text
                    updated.unit = field.storedUnit
                    upserts.append(updated)
                } else if !isUnreadable {
                    // A figure the owner removed. An unreadable one cannot be shown in the sheet, so
                    // leaving it out of the draft is not a removal: it stays where it is (Lab Book).
                    deleteIds.append(member.id)
                }
                continue
            }
            if let member { deleteIds.append(member.id) }
            if entered {
                upserts.append(Self.newRow(field, value: value, text: text, deviceId: activeDeviceId,
                                           takenAt: takenAt, day: day))
            } else if isUnreadable, let member {
                // Moving the scan carries an unreadable figure along exactly as stored.
                var moved = Self.newRow(field, value: member.value, text: member.valueText,
                                        deviceId: activeDeviceId, takenAt: takenAt, day: day)
                moved.unit = member.unit
                upserts.append(moved)
            }
        }

        try await store.replaceLabMarkers(deleteIds: deleteIds, upsert: upserts)
        await finishWrite()
        let id = BodyScan.id(source: MarkerCatalog.scanSource, takenAt: takenAt)
        guard let saved = await scans().first(where: { $0.id == id }) else { throw BodyRecordError.scanNotFound }
        return saved
    }

    /// Deletes every member of a typed scan, and every stored copy of each, in one transaction.
    func delete(_ scan: BodyScan) async throws {
        guard scan.isDeletable else { throw BodyRecordError.notEditable }
        guard let store = await repository.storeHandle() else { throw BodyRecordError.storeUnavailable }
        guard let current = await scans().first(where: { $0.id == scan.id }) else {
            throw BodyRecordError.scanNotFound
        }
        guard current.isDeletable else { throw BodyRecordError.notEditable }
        let ids = current.rows.values.flatMap { $0.map(\.id) }.sorted()
        try await store.replaceLabMarkers(deleteIds: ids, upsert: [])
        await finishWrite()
    }

    /// Checks the draft and returns its trimmed note (nil when empty).
    private func validate(_ draft: BodyScanDraft, zone: TimeZone, now: Date) throws -> String? {
        guard CanonicalDay.number(draft.day) != nil else { throw BodyRecordError.invalidDay }
        let today = LocalDayWindows(timeZone: zone).dayKey(for: now)
        guard draft.day <= today else { throw BodyRecordError.futureDay }
        let hasScanFigure = draft.values.keys.contains {
            MarkerCatalog.isScanOnlyMarker($0) && $0 != MarkerCatalog.scanNoteKey
        }
        guard hasScanFigure else { throw BodyRecordError.nothingToSave }
        for field in BodyScanField.all {
            guard let value = draft.values[field.key] else { continue }
            guard let range = field.range, value.isFinite, range.contains(value) else {
                throw BodyRecordError.outOfRange(key: field.key)
            }
        }
        if let unknown = draft.values.keys.sorted().first(where: { BodyScanField.field(for: $0) == nil }) {
            throw BodyRecordError.outOfRange(key: unknown)
        }
        let note = draft.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard note.count <= BodyScanField.noteMaxLength else { throw BodyRecordError.noteTooLong }
        return note.isEmpty ? nil : note
    }

    /// §7.8: 12:00 local time on `day` in `zone`, or `now` if that is earlier.
    private static func instant(day: String, zone: TimeZone, now: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = day.split(separator: "-").compactMap { Int($0) }
        var components = DateComponents()
        components.year = parts.count == 3 ? parts[0] : nil
        components.month = parts.count == 3 ? parts[1] : nil
        components.day = parts.count == 3 ? parts[2] : nil
        components.hour = 12
        let noon = calendar.date(from: components) ?? now
        return Int(min(noon, now).timeIntervalSince1970)
    }

    /// §9.1: an instant is occupied when any stored row, under any device id, has source
    /// `body-scan`, that `takenAt` and a key of §7.7. Reads the stored rows, not the merged ones.
    private func isOccupied(_ takenAt: Int, store: WhoopStore) async throws -> Bool {
        for field in BodyScanField.all {
            let stored: [LabMarkerRow]
            do {
                stored = try await LabBookRows.stored(marker: field.key, store: store)
            } catch {
                throw BodyRecordError.storeUnavailable
            }
            if stored.contains(where: { $0.source == MarkerCatalog.scanSource && $0.takenAt == takenAt }) {
                return true
            }
        }
        return false
    }

    private static func newRow(_ field: BodyScanField, value: Double?, text: String?, deviceId: String,
                               takenAt: Int, day: String) -> LabMarkerRow {
        let category = MarkerCatalog.definition(for: field.key)?.category.rawValue ?? LabMarkerCategory.imaging.rawValue
        return LabMarkerRow(id: "\(field.key)-\(takenAt)-\(newSuffix())", deviceId: deviceId, markerKey: field.key,
                            category: category, day: day, takenAt: takenAt, value: value, valueText: text,
                            unit: field.storedUnit, source: MarkerCatalog.scanSource, note: nil, referenceText: nil)
    }

    private static func newSuffix() -> String { String(UUID().uuidString.prefix(8)) }

    /// §8.2: the same finish as a weigh-in, so every reader of the weight moves with the write.
    private func finishWrite() async {
        await repository.refresh()
        await provider?.refresh()
    }

    // MARK: - Benchmarks

    /// The merged rows of one benchmark, oldest first; conflicting rows are separate readings.
    func benchmarkReadings(key: String) async -> [LabMarkerRow] {
        let activeDeviceId = repository.deviceId
        guard MarkerCatalog.isBenchmark(key), let store = await repository.storeHandle() else { return [] }
        return await LabBookRows.marker(key, store: store, activeDeviceId: activeDeviceId)
    }

    /// The benchmark keys that have a reading: catalogue order, then custom keys ascending.
    func benchmarkKeysPresent() async -> [String] {
        let activeDeviceId = repository.deviceId
        guard let store = await repository.storeHandle() else { return [] }
        let present = Set(await LabBookRows.category(LabMarkerCategory.other.rawValue, store: store,
                                                     activeDeviceId: activeDeviceId)
            .map(\.markerKey).filter(MarkerCatalog.isBenchmark))
        let catalogue = MarkerCatalog.bodyRecord.map(\.key).filter { MarkerCatalog.isBenchmark($0) }
        let known = catalogue.filter(present.contains)
        let custom = present.subtracting(catalogue).sorted()
        return known + custom
    }

    /// Saves one benchmark reading under the active id (§9.1). The value is validated against §7.7.
    @discardableResult
    func saveBenchmark(key: String, value: Double, unit: String, takenAt: Date,
                       note: String?) async throws -> LabMarkerRow {
        let activeDeviceId = repository.deviceId
        let zone = timeZone()
        guard MarkerCatalog.isBenchmark(key) else { throw BodyRecordError.outOfRange(key: key) }
        if let definition = MarkerCatalog.definition(for: key), definition.canonicalUnit != unit {
            throw BodyRecordError.outOfRange(key: key)
        }
        guard let range = BenchmarkRules.range(unit: unit), value.isFinite, range.contains(value),
              !BenchmarkRules.requiresWholeNumber(unit: unit) || value == value.rounded() else {
            throw BodyRecordError.outOfRange(key: key)
        }
        guard let store = await repository.storeHandle() else { throw BodyRecordError.storeUnavailable }
        let epoch = Int(takenAt.timeIntervalSince1970)
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let row = LabMarkerRow(id: "\(key)-\(epoch)-\(Self.newSuffix())", deviceId: activeDeviceId, markerKey: key,
                               category: LabMarkerCategory.other.rawValue,
                               day: LocalDayWindows(timeZone: zone).dayKey(for: takenAt), takenAt: epoch,
                               value: value, valueText: nil, unit: unit,
                               source: BodyMeasurementResolver.weighInSource,
                               note: trimmed.isEmpty ? nil : trimmed, referenceText: nil)
        try await store.upsertOwnerLabMarkers([row])
        await repository.refresh()
        let stored = (try? await LabBookRows.stored(marker: key, store: store)) ?? []
        let atIdentity = stored.filter { $0.takenAt == epoch && $0.source == row.source }
        return atIdentity.first { $0.id == row.id } ?? atIdentity.first { $0.deviceId == activeDeviceId }
            ?? atIdentity.first ?? row
    }

    /// Deletes one benchmark reading and every stored copy of it.
    func deleteBenchmark(_ row: LabMarkerRow) async throws {
        guard let store = await repository.storeHandle() else { throw BodyRecordError.storeUnavailable }
        try await store.deleteLabMarkerAndCopies(id: row.id)
        await repository.refresh()
    }
}
