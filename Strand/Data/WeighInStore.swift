import Foundation
import StrandAnalytics
import WhoopStore

/// Why a weigh-in write was refused. Nothing is written when one of these is thrown.
enum WeighInError: Error, Equatable {
    /// Not finite, or outside `WeighInStore.weightRangeKg` after conversion to kilograms.
    case weightOutOfRange
    /// Not finite, or outside `WeighInStore.waistRangeCm` after conversion to centimetres.
    case waistOutOfRange
    /// The instant is after now.
    case futureInstant
    /// Edit or delete of a Lab Book row whose marker is neither weight nor waist.
    case notABodyMeasurement
    /// Edit or delete of a row that is no longer stored.
    case readingNotFound
    /// The store could not be opened.
    case storeUnavailable
    /// The instant already holds another reading of the same marker and source under any device id,
    /// registered or not (rulings R34 and R36, widened by R42): the target of a date edit, or the
    /// instant of a save that has no row of its own there to update.
    case instantOccupied
}

/// The write funnel for weigh-ins (specification §9.1): one or two Lab Book rows per weigh-in,
/// written through the existing Lab Book store calls.
///
/// It only ever adds `weight` and `waist` rows and edits or deletes such a row by its id, under the
/// device id that row is stored under. It never touches another marker, another table or the profile,
/// and nothing is re-keyed or moved (ruling R25). The profile mirror belongs to
/// `BodyMeasurementProvider.refresh()`, which every successful write here ends with.
///
/// Ruling R42 (labbook-ownership.md §7.4): the readings are the owner's under whichever strap id
/// they were entered, and every id is listed. So an instant counts as taken when ANY device id
/// holds it, and a reading stored twice (equal rows under two ids, listed once) is saved onto,
/// edited and deleted as one: its copies follow, each under its own id. A different reading at the
/// same instant under another id is another reading and no write here changes it (ruling A10).
@MainActor
final class WeighInStore {
    /// Accepted weight, in kilograms, inclusive (specification §10.3).
    static let weightRangeKg: ClosedRange<Double> = 30...250
    /// Accepted waist, in centimetres, inclusive.
    static let waistRangeCm: ClosedRange<Double> = 40...200

    private static let manualSource = "manual"
    private static let bodyMeasurementCategory = "bodyMeasurement"

    private let repository: Repository
    private let provider: BodyMeasurementProvider?
    private let timeZone: () -> TimeZone
    private let now: () -> Date

    /// Test seam. Called during a date edit after the new row is inserted and before the old row is
    /// deleted. Throwing from it aborts the edit at that point, leaving both readings. Not called
    /// when the edit completes an interrupted one, which inserts nothing.
    var interruptDateEditForTesting: (() throws -> Void)?

    init(repository: Repository, provider: BodyMeasurementProvider? = nil,
         timeZone: @escaping () -> TimeZone = { TimeZone.current },
         now: @escaping () -> Date = { Date() }) {
        self.repository = repository
        self.provider = provider
        self.timeZone = timeZone
        self.now = now
    }

    // MARK: - Save

    /// One weigh-in: a weight row, and a waist row unless `waist` is nil (a skipped waist was not
    /// measured and writes no row). `.metric` means kilograms and centimetres, `.imperial` pounds and
    /// inches; kilograms and centimetres are stored, unrounded. Both values are validated before
    /// anything is written, and both rows go in one transaction. Returns the rows as stored, weight
    /// first.
    ///
    /// A manual row of the marker already stored at that instant under the active id is the row the
    /// save lands on: its value and unit are replaced and every other column is written back as it
    /// was (ruling R34). Each stored copy of that row under another id takes the same value and unit
    /// under its own id, in the same write, so the reading stays one line; a different reading at
    /// that instant is not touched (ruling A10). With no such row, a manual row of the marker at that instant under ANY other
    /// device id, registered or not, any brand, refuses the whole weigh-in with `.instantOccupied`,
    /// before anything is written (ruling R36, widened by R42).
    @discardableResult
    func save(weight: Double, waist: Double?, unitSystem: UnitSystem, takenAt: Date) async throws -> [LabMarkerRow] {
        let weightKg = try Self.validated(weight, kind: .weight, unitSystem: unitSystem)
        let waistCm = try waist.map { try Self.validated($0, kind: .waist, unitSystem: unitSystem) }
        guard takenAt <= now() else { throw WeighInError.futureInstant }
        // Captured before the first suspension: the id and the zone of this write.
        let deviceId = repository.deviceId
        let epoch = Int(takenAt.timeIntervalSince1970)
        let day = LocalDayWindows(timeZone: timeZone()).dayKey(for: takenAt)
        guard let store = await repository.storeHandle() else { throw WeighInError.storeUnavailable }

        // Both markers are settled, and either refusal thrown, before the one write below. Each
        // entry is the active id's row first, then the copies that follow it.
        var writes = [try await Self.rowsToWrite(.weight, deviceId: deviceId, epoch: epoch,
                                                 day: day, value: weightKg, in: store)]
        if let waistCm {
            writes.append(try await Self.rowsToWrite(.waist, deviceId: deviceId, epoch: epoch,
                                                     day: day, value: waistCm, in: store))
        }
        try await store.upsertLabMarkers(writes.flatMap { $0 })
        // Return what is stored, not what was offered: the active id's row of each marker.
        var stored: [LabMarkerRow] = []
        for row in writes.compactMap(\.first) {
            stored.append(try await Self.storedRow(matching: row, in: store))
        }
        await finishWrite()
        return stored
    }

    // MARK: - Edit

    /// Edit one stored reading. Same instant: the value is updated in place, and the row keeps its
    /// id, device id, source, note, reference text and stored day; each stored copy of the row under
    /// another id takes the same value and unit under its own id, in the same write, so the reading
    /// stays one line. Another instant: a new row is inserted under the same device id, then the old
    /// one and its copies are deleted, so an interruption leaves two readings and never none.
    ///
    /// Another instant that already holds a reading of the same marker and source, under ANY device
    /// id, is refused with `.instantOccupied` before anything is written (rulings R34 and R36,
    /// widened by R42): every id is listed, so the edit would put two different readings on one
    /// instant, or overwrite one. The one exception is the state an interrupted date edit leaves
    /// behind, where every row at that instant already equals the replacement in every column
    /// except `id`, `deviceId` and the stored `day`: the edit then completes by deleting the old
    /// row and its copies and writes nothing new. The day is left out because it follows from the
    /// instant and the zone of the original write, so a retry after the device changed zone still
    /// completes (ruling R39), and the surviving row keeps the day that write stored. Returns the
    /// row as stored afterwards.
    @discardableResult
    func edit(_ row: LabMarkerRow, value: Double, unitSystem: UnitSystem, takenAt: Date) async throws -> LabMarkerRow {
        guard let kind = BodyMeasurementKind(markerKey: row.markerKey) else { throw WeighInError.notABodyMeasurement }
        let converted = try Self.validated(value, kind: kind, unitSystem: unitSystem)
        guard takenAt <= now() else { throw WeighInError.futureInstant }
        let epoch = Int(takenAt.timeIntervalSince1970)
        let newDay = LocalDayWindows(timeZone: timeZone()).dayKey(for: takenAt)
        // Captured before the first suspension: which copy stands for a set belongs to the moment
        // of the edit.
        let activeDeviceId = repository.deviceId
        guard let store = await repository.storeHandle() else { throw WeighInError.storeUnavailable }
        guard let current = try await Self.storedRow(id: row.id, deviceId: row.deviceId, kind: kind, in: store) else {
            throw WeighInError.readingNotFound
        }
        // Every stored row of the marker, under every device id: the copies of the edited row and
        // the occupants of the target instant are both found here.
        let everyRow = try await LabBookRows.stored(marker: kind.markerKey, store: store)

        var replacement = current
        replacement.value = converted
        replacement.unit = Self.unit(kind)
        if epoch == current.takenAt {
            // The row and each of its copies, each under its own id and device id, in one write.
            var writes = [replacement]
            for var copy in LabMarkerUnion.copies(of: current, in: everyRow) where copy.id != current.id {
                copy.value = converted
                copy.unit = Self.unit(kind)
                writes.append(copy)
            }
            try await store.upsertLabMarkers(writes)
            let stored = try await Self.storedRow(matching: replacement, in: store)
            await finishWrite()
            return stored
        }

        replacement.takenAt = epoch
        replacement.day = newDay
        // The row's own id: the upsert is keyed on (device id, marker, instant, source) and would
        // overwrite the row already at that key, after which the delete below would remove the
        // edited one. Every other id, registered or not: the readers list every id, so they would
        // show two readings where the owner entered one.
        let occupants = everyRow.filter { $0.takenAt == epoch && $0.source == current.source }
        if !occupants.isEmpty {
            // Ruling R36's exception, for any number of occupants: every one of them is this edit's
            // own replacement. `isCopy` leaves out the id, the device id and the stored day (ruling
            // R39: the zone may have changed since that write).
            guard occupants.allSatisfy({ LabMarkerUnion.isCopy($0, replacement) }),
                  !occupants.contains(where: { $0.id == current.id }) else {
                throw WeighInError.instantOccupied
            }
            // The row that stands for them: the edited row's own id's, else the one the readers list.
            let standing = occupants.first { $0.deviceId == current.deviceId }
                ?? LabMarkerUnion.merged(occupants, activeDeviceId: activeDeviceId).first
            guard let occupant = standing else { throw WeighInError.instantOccupied }
            try await store.deleteLabMarkerAndCopies(id: current.id)
            await finishWrite()
            return occupant
        }
        replacement.id = Self.newId(kind, epoch: epoch)
        try await store.upsertLabMarkers([replacement])
        let stored = try await Self.storedRow(matching: replacement, in: store)
        do {
            try interruptDateEditForTesting?()
        } catch {
            await finishWrite()
            throw error
        }
        // Never delete the row that holds the new reading. The old row's copies sit at the old
        // instant, so removing them cannot reach it either.
        if stored.id != current.id {
            try await store.deleteLabMarkerAndCopies(id: current.id)
        }
        await finishWrite()
        return stored
    }

    // MARK: - Delete

    /// Delete one stored weight or waist reading by its id, and every stored copy of it under
    /// another device id: the history lists a set of copies once, so deleting only the listed row
    /// would let the reading come back. A different reading at the same instant is not touched.
    func delete(_ row: LabMarkerRow) async throws {
        guard let kind = BodyMeasurementKind(markerKey: row.markerKey) else { throw WeighInError.notABodyMeasurement }
        guard let store = await repository.storeHandle() else { throw WeighInError.storeUnavailable }
        guard let current = try await Self.storedRow(id: row.id, deviceId: row.deviceId, kind: kind, in: store) else {
            throw WeighInError.readingNotFound
        }
        try await store.deleteLabMarkerAndCopies(id: current.id)
        await finishWrite()
    }

    // MARK: - Read

    /// Every weight (or waist) Lab Book reading under every device id (ruling R42), copies listed
    /// once, oldest first: the same rows `BodyMeasurementProvider` feeds the resolver.
    func readings(_ kind: BodyMeasurementKind) async -> [LabMarkerRow] {
        let deviceId = repository.deviceId
        guard let store = await repository.storeHandle() else { return [] }
        return await BodyMeasurementProvider.labBookRows(kind, store: store, activeDeviceId: deviceId)
    }

    /// Stage 4: the ids of the body scans stored (stage 4 §7.6), so the history opens only a scan
    /// that exists. Read only while the body record is on.
    func bodyScanIds() async -> Set<String> {
        let scans = await BodyRecordStore(repository: repository, provider: provider, timeZone: timeZone, now: now).scans()
        return Set(scans.map(\.id))
    }

    // MARK: - Helpers

    private func finishWrite() async {
        await repository.refresh()
        await provider?.refresh()
    }

    /// The value in kilograms or centimetres, or the kind's range error.
    private static func validated(_ value: Double, kind: BodyMeasurementKind, unitSystem: UnitSystem) throws -> Double {
        let converted: Double
        switch (kind, unitSystem) {
        case (_, .metric): converted = value
        case (.weight, .imperial): converted = value / UnitFormatter.poundsPerKilogram
        case (.waist, .imperial): converted = value * UnitFormatter.centimetersPerInch
        }
        switch kind {
        case .weight:
            guard converted.isFinite, weightRangeKg.contains(converted) else { throw WeighInError.weightOutOfRange }
        case .waist:
            guard converted.isFinite, waistRangeCm.contains(converted) else { throw WeighInError.waistOutOfRange }
        }
        return converted
    }

    private static func unit(_ kind: BodyMeasurementKind) -> String {
        switch kind {
        case .weight: return "kg"
        case .waist: return "cm"
        }
    }

    /// `"<markerKey>-<takenAt>-<8 hex>"`, the form the Lab Book editor uses.
    private static func newId(_ kind: BodyMeasurementKind, epoch: Int) -> String {
        "\(kind.markerKey)-\(epoch)-\(UUID().uuidString.prefix(8))"
    }

    private static func newRow(_ kind: BodyMeasurementKind, deviceId: String, epoch: Int, day: String,
                               value: Double) -> LabMarkerRow {
        LabMarkerRow(id: newId(kind, epoch: epoch), deviceId: deviceId, markerKey: kind.markerKey,
                     category: bodyMeasurementCategory, day: day, takenAt: epoch, value: value,
                     valueText: nil, unit: unit(kind), source: manualSource, note: nil, referenceText: nil)
    }

    /// What a save writes for `kind`, the active id's row first: the manual row already stored at
    /// this instant under `deviceId` with only its value and unit replaced, then each stored copy of
    /// that row under another id with the same two columns replaced, under its own id and device id
    /// (ruling A10: a save updates the row it lands on and that row's copies, and never a different
    /// reading at the instant). With no row under `deviceId`, one new row. Throws `.instantOccupied`
    /// when there is no such row and ANY other device id, registered or not, holds a manual row of
    /// the marker at this instant (ruling R36, widened by R42). Reads only.
    private static func rowsToWrite(_ kind: BodyMeasurementKind, deviceId: String,
                                    epoch: Int, day: String, value: Double,
                                    in store: WhoopStore) async throws -> [LabMarkerRow] {
        let everyRow = try await LabBookRows.stored(marker: kind.markerKey, store: store)
        guard let existing = try await storedRow(deviceId: deviceId, kind: kind, epoch: epoch,
                                                 source: manualSource, in: store) else {
            let elsewhere = everyRow.filter { $0.takenAt == epoch && $0.source == manualSource }
            guard elsewhere.isEmpty else { throw WeighInError.instantOccupied }
            return [newRow(kind, deviceId: deviceId, epoch: epoch, day: day, value: value)]
        }
        // `copies` is found against the row as stored, before its value is replaced.
        let followers = LabMarkerUnion.copies(of: existing, in: everyRow).filter { $0.id != existing.id }
        return ([existing] + followers).map { row in
            var write = row
            write.value = value
            write.unit = unit(kind)
            return write
        }
    }

    /// The stored row at this natural key (device id, marker, instant, source), nil when it is free.
    private static func storedRow(deviceId: String, kind: BodyMeasurementKind, epoch: Int, source: String,
                                  in store: WhoopStore) async throws -> LabMarkerRow? {
        try await store.labMarkers(deviceId: deviceId, markerKey: kind.markerKey)
            .first { $0.takenAt == epoch && $0.source == source }
    }

    /// The stored row with this id, under the device id it was stored under.
    private static func storedRow(id: String, deviceId: String, kind: BodyMeasurementKind,
                                  in store: WhoopStore) async throws -> LabMarkerRow? {
        try await store.labMarkers(deviceId: deviceId, markerKey: kind.markerKey).first { $0.id == id }
    }

    /// The stored row at `row`'s natural key (device id, marker, instant, source).
    private static func storedRow(matching row: LabMarkerRow, in store: WhoopStore) async throws -> LabMarkerRow {
        let stored = try await store.labMarkers(deviceId: row.deviceId, markerKey: row.markerKey)
            .first { $0.takenAt == row.takenAt && $0.source == row.source }
        guard let stored else { throw WeighInError.readingNotFound }
        return stored
    }
}
