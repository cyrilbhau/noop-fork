import Foundation
import Combine
import StrandAnalytics
import StrandImport
import WhoopStore

// Stage 4 (body record), docs/personal/superapp/specs/stage-4.md §10: the screen and sheet models.
// They read and write through `BodyRecordStore` and hand everything to `BodyRecordPresenter`; the
// views bind to what these publish.

/// The body-record screen (§10.1), the scan detail (§10.3), the comparison (§10.4) and the benchmark
/// detail (§10.5) all read the one load this model holds.
@MainActor
final class BodyRecordModel: ObservableObject {
    /// G1 until the first load ends.
    @Published private(set) var screen: BodyRecordScreen
    @Published private(set) var load: BodyRecordLoad = .loading

    private let store: BodyRecordStore
    private let unitSystem: () -> UnitSystem
    private let locale: () -> Locale
    private var generation = 0

    init(store: BodyRecordStore, unitSystem: @escaping () -> UnitSystem, locale: @escaping () -> Locale) {
        self.store = store
        self.unitSystem = unitSystem
        self.locale = locale
        screen = BodyRecordPresenter.screen(.loading, unitSystem: unitSystem(), locale: locale())
    }

    /// Reads every scan and every benchmark. A later load always wins over an earlier one.
    func load() async {
        generation += 1
        let request = generation
        let next: BodyRecordLoad
        if await store.isAvailable() {
            let scans = await store.scans()
            var histories: [BenchmarkHistory] = []
            for key in await store.benchmarkKeysPresent() {
                histories.append(BenchmarkHistory(key: key, readings: await store.benchmarkReadings(key: key)))
            }
            next = .loaded(scans: scans, benchmarks: histories)
        } else {
            next = .storeUnavailable
        }
        guard request == generation else { return }
        if load != next { load = next }
        let shown = BodyRecordPresenter.screen(next, unitSystem: unitSystem(), locale: locale())
        if screen != shown { screen = shown }
    }

    #if DEBUG
    /// The debug demo shows the screen in a given state (frame G9).
    func showLoadForDemo(_ shown: BodyRecordLoad) {
        load = shown
        screen = BodyRecordPresenter.screen(shown, unitSystem: unitSystem(), locale: locale())
    }
    #endif

    /// The scans of the last load, in the §7.6 order.
    var scans: [BodyScan] {
        if case .loaded(let scans, _) = load { return scans }
        return []
    }

    /// I7: nil once the scan is gone.
    func scan(id: String) -> BodyScan? { scans.first { $0.id == id } }

    /// One benchmark's readings from the last load; nil once it has none.
    func benchmark(key: String) -> BenchmarkHistory? {
        guard case .loaded(_, let benchmarks) = load else { return nil }
        return benchmarks.first { $0.key == key }
    }

    func detail(id: String) -> BodyScanDetail? {
        scan(id: id).map { BodyRecordPresenter.detail($0, unitSystem: unitSystem(), locale: locale()) }
    }

    func comparison(earlierId: String?, laterId: String?) -> BodyScanComparison {
        BodyRecordPresenter.comparison(scans: scans, earlierId: earlierId, laterId: laterId,
                                       unitSystem: unitSystem(), locale: locale())
    }

    func benchmarkDetail(key: String) -> BenchmarkDetail? {
        benchmark(key: key).map { BodyRecordPresenter.benchmarkDetail($0, unitSystem: unitSystem(), locale: locale()) }
    }

    /// Deletes a typed scan. False when nothing was deleted.
    func delete(_ scan: BodyScan) async -> Bool {
        do {
            try await store.delete(scan)
        } catch {
            await load()
            return false
        }
        await load()
        return true
    }

    /// Deletes one benchmark reading. False when nothing was deleted.
    func deleteBenchmarkReading(rowId: String, key: String) async -> Bool {
        guard let row = benchmark(key: key)?.readings.first(where: { $0.id == rowId }) else { return false }
        do {
            try await store.deleteBenchmark(row)
        } catch {
            await load()
            return false
        }
        await load()
        return true
    }
}

/// The scan sheet (§10.2): what is typed, whether the weigh-in line applies, and the save.
@MainActor
final class BodyScanSheetModel: ObservableObject {
    @Published var entry: BodyScanEntry {
        didSet { if phase == .occupied || phase == .failed { phase = .editing } }
    }
    @Published private(set) var phase: BodyScanSheetPhase = .editing
    @Published private(set) var weighInOutranks = false

    let editing: BodyScan?
    private let store: BodyRecordStore
    private let weighIns: WeighInStore
    private let unitSystem: UnitSystem
    private let decimalSeparator: Character
    private let today: () -> String
    /// The entry as first prefilled, so that a figure left as it was keeps its exact stored value.
    private let prefilled: BodyScanEntry?
    private var evaluation = 0

    init(store: BodyRecordStore, weighIns: WeighInStore, editing: BodyScan?, unitSystem: UnitSystem,
         decimalSeparator: Character, today: @escaping () -> String) {
        self.store = store
        self.weighIns = weighIns
        self.editing = editing
        self.unitSystem = unitSystem
        self.decimalSeparator = decimalSeparator
        self.today = today
        let first = editing.map { BodyScanEntry(editing: $0, unitSystem: unitSystem) }
        prefilled = first
        entry = first ?? BodyScanEntry(day: today())
    }

    var state: BodyScanSheetState {
        BodyRecordPresenter.sheet(entry, unitSystem: unitSystem, decimalSeparator: decimalSeparator, phase: phase,
                                  weighInOutranks: weighInOutranks)
    }

    var isEditing: Bool { editing != nil }

    /// The chosen day as a date for the date picker: noon of the day in the device's zone, so the
    /// picker shows the right day in every zone.
    var date: Date {
        get {
            guard let noon = Self.utcNoon(entry.day) else { return Date() }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
            let utcNoon = Date(timeIntervalSince1970: TimeInterval(noon))
            let parts = calendar.dateComponents([.year, .month, .day], from: utcNoon)
            calendar.timeZone = .current
            return calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day,
                                                      hour: 12)) ?? utcNoon
        }
        set { entry.day = Repository.localDayKey(newValue) }
    }

    /// 12:00 UTC of a canonical day key, in seconds since 1970. `CanonicalDay.number` is a Julian
    /// Day Number; 2440588 is 1970-01-01.
    private static func utcNoon(_ day: String) -> Int? {
        CanonicalDay.number(day).map { ($0 - 2_440_588) * 86_400 + 43_200 }
    }

    /// The text of one field, as the field binds it.
    func text(_ key: String) -> String { entry.texts[key] ?? "" }

    func setText(_ text: String, for key: String) { entry.texts[key] = text }

    func setUnit(_ unit: String, for key: String) { entry.units[key] = unit }

    /// The note, never longer than a scan keeps.
    func setNote(_ note: String) { entry.note = String(note.prefix(BodyScanField.noteMaxLength)) }

    /// T-score and Z-score: the decimal keypad has no minus key, so a toggle adds or removes it.
    func toggleSign(_ key: String) {
        let text = entry.texts[key] ?? ""
        entry.texts[key] = text.hasPrefix("-") ? String(text.dropFirst()) : "-" + text
    }

    #if DEBUG
    /// The debug demo shows the sheet in a given phase (frames H10 to H12).
    func showPhaseForDemo(_ phase: BodyScanSheetPhase) { self.phase = phase }
    #endif

    /// H8: asks the resolver, through `BodyRecordPresenter.weighInOutranksDraft`, whether a manual
    /// weigh-in of the chosen day's week would outrank the total mass as typed. Not asked without one.
    func evaluate() async {
        evaluation += 1
        let request = evaluation
        let typed = entry
        guard let kilograms = BodyRecordPresenter.typedTotalMassKg(typed, unitSystem: unitSystem,
                                                                   decimalSeparator: decimalSeparator),
              let utcNoon = Self.utcNoon(typed.day) else {
            weighInOutranks = false
            return
        }
        let keepsInstant = editing.map { $0.day == typed.day } ?? false
        // The instant only orders the draft within its own day, and the rule outranks it whatever
        // its time; noon of the day stands in for a new scan.
        let takenAt = keepsInstant ? editing!.takenAt : utcNoon
        let draftRow = LabMarkerRow(id: "body-record-draft", deviceId: "", markerKey: BodyMeasurementKind.weight.markerKey,
                                    category: LabMarkerCategory.bodyMeasurement.rawValue, day: typed.day,
                                    takenAt: takenAt, value: kilograms, valueText: nil,
                                    unit: MarkerCatalog.definition(for: BodyMeasurementKind.weight.markerKey)?.canonicalUnit ?? "",
                                    source: MarkerCatalog.scanSource, note: nil, referenceText: nil)
        let weighInRows = await weighIns.readings(.weight).filter { $0.source == BodyMeasurementResolver.weighInSource }
        guard request == evaluation else { return }
        // A day after today is refused at save; judging it as of its own day keeps the line honest.
        let asOf = max(today(), typed.day)
        weighInOutranks = BodyRecordPresenter.weighInOutranksDraft(draftRow: draftRow, weighInRows: weighInRows,
                                                                   today: asOf)
    }

    /// Saves the scan. Nil on failure, with the phase saying why: `.occupied` or `.failed`.
    @discardableResult
    func save() async -> BodyScan? {
        guard var draft = state.draft else { return nil }
        // A figure left exactly as prefilled keeps the stored value, so editing one figure never
        // re-rounds the others through the display unit.
        if let editing, let prefilled {
            for (key, text) in entry.texts where prefilled.texts[key] == text
                && prefilled.units[key] == entry.units[key] {
                if let stored = editing.values[key], draft.values[key] != nil { draft.values[key] = stored }
            }
        }
        phase = .saving
        do {
            let saved = try await store.save(draft, replacing: editing)
            phase = .editing
            return saved
        } catch BodyRecordError.instantOccupied {
            phase = .occupied
            return nil
        } catch {
            phase = .failed
            return nil
        }
    }

    /// Deletes the scan being edited. False when nothing was deleted.
    func delete() async -> Bool {
        guard let editing else { return false }
        phase = .saving
        do {
            try await store.delete(editing)
            phase = .editing
            return true
        } catch {
            phase = .failed
            return false
        }
    }
}

/// The benchmark sheet (§10.5): what is typed and the save.
@MainActor
final class BenchmarkSheetModel: ObservableObject {
    @Published var entry: BenchmarkEntry
    @Published var takenAt: Date
    @Published var note = ""
    @Published private(set) var isSaving = false
    @Published private(set) var failed = false

    private let store: BodyRecordStore
    private let decimalSeparator: Character

    init(store: BodyRecordStore, key: String?, decimalSeparator: Character, now: Date) {
        self.store = store
        self.decimalSeparator = decimalSeparator
        entry = BenchmarkEntry(key: key)
        takenAt = now
    }

    var state: BenchmarkEntryState {
        BodyRecordPresenter.benchmarkEntry(entry, decimalSeparator: decimalSeparator)
    }

    /// The reading as saved, or nil when it could not be saved.
    @discardableResult
    func save() async -> LabMarkerRow? {
        let shown = state
        guard shown.canSave, let key = shown.key, let value = shown.value else { return nil }
        isSaving = true
        defer { isSaving = false }
        do {
            let row = try await store.saveBenchmark(key: key, value: value, unit: shown.unit, takenAt: takenAt,
                                                    note: note)
            failed = false
            return row
        } catch {
            failed = true
            return nil
        }
    }
}
