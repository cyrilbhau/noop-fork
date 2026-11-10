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
}

/// The write funnel for weigh-ins (specification §9.1): one or two Lab Book rows per weigh-in,
/// written through the existing Lab Book store calls.
///
/// It only ever adds `weight` and `waist` rows and edits or deletes such a row by its id, under the
/// device id that row is stored under. It never touches another marker, another table or the profile,
/// and nothing is re-keyed or moved (ruling R25). The profile mirror belongs to
/// `BodyMeasurementProvider.refresh()`, which every successful write here ends with.
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
    /// deleted. Throwing from it aborts the edit at that point, leaving both readings.
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

        var rows = [Self.newRow(.weight, deviceId: deviceId, epoch: epoch, day: day, value: weightKg)]
        if let waistCm {
            rows.append(Self.newRow(.waist, deviceId: deviceId, epoch: epoch, day: day, value: waistCm))
        }
        try await store.upsertLabMarkers(rows)
        // A save in the same second updates the row already there, which keeps its own id: return
        // what is stored, not what was offered.
        var stored: [LabMarkerRow] = []
        for row in rows {
            stored.append(try await Self.storedRow(matching: row, in: store))
        }
        await finishWrite()
        return stored
    }

    // MARK: - Edit

    /// Edit one stored reading. Same instant: the value is updated in place, and the row keeps its
    /// id, device id, source, note, reference text and stored day. Another instant: a new row is
    /// inserted under the same device id, then the old one is deleted, so an interruption leaves two
    /// readings and never none. Returns the row as stored afterwards.
    @discardableResult
    func edit(_ row: LabMarkerRow, value: Double, unitSystem: UnitSystem, takenAt: Date) async throws -> LabMarkerRow {
        guard let kind = BodyMeasurementKind(markerKey: row.markerKey) else { throw WeighInError.notABodyMeasurement }
        let converted = try Self.validated(value, kind: kind, unitSystem: unitSystem)
        guard takenAt <= now() else { throw WeighInError.futureInstant }
        let epoch = Int(takenAt.timeIntervalSince1970)
        let newDay = LocalDayWindows(timeZone: timeZone()).dayKey(for: takenAt)
        guard let store = await repository.storeHandle() else { throw WeighInError.storeUnavailable }
        guard let current = try await Self.storedRow(id: row.id, deviceId: row.deviceId, kind: kind, in: store) else {
            throw WeighInError.readingNotFound
        }

        var replacement = current
        replacement.value = converted
        replacement.unit = Self.unit(kind)
        if epoch == current.takenAt {
            try await store.upsertLabMarkers([replacement])
            let stored = try await Self.storedRow(matching: replacement, in: store)
            await finishWrite()
            return stored
        }

        replacement.id = Self.newId(kind, epoch: epoch)
        replacement.takenAt = epoch
        replacement.day = newDay
        try await store.upsertLabMarkers([replacement])
        let stored = try await Self.storedRow(matching: replacement, in: store)
        do {
            try interruptDateEditForTesting?()
        } catch {
            await finishWrite()
            throw error
        }
        // The new reading may have landed on a row that already existed at that instant; never
        // delete the row that now holds it.
        if stored.id != current.id {
            try await store.deleteLabMarker(id: current.id)
        }
        await finishWrite()
        return stored
    }

    // MARK: - Delete

    /// Delete one stored weight or waist reading by its id. No other row is touched.
    func delete(_ row: LabMarkerRow) async throws {
        guard let kind = BodyMeasurementKind(markerKey: row.markerKey) else { throw WeighInError.notABodyMeasurement }
        guard let store = await repository.storeHandle() else { throw WeighInError.storeUnavailable }
        guard let current = try await Self.storedRow(id: row.id, deviceId: row.deviceId, kind: kind, in: store) else {
            throw WeighInError.readingNotFound
        }
        try await store.deleteLabMarker(id: current.id)
        await finishWrite()
    }

    // MARK: - Read

    /// Every weight (or waist) Lab Book row across the ids of ruling R25, de-duplicated, oldest
    /// first: the same rows `BodyMeasurementProvider` feeds the resolver.
    func readings(_ kind: BodyMeasurementKind) async -> [LabMarkerRow] {
        let deviceId = repository.deviceId
        guard let store = await repository.storeHandle() else { return [] }
        return await BodyMeasurementProvider.labBookRows(kind, store: store, activeDeviceId: deviceId)
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
