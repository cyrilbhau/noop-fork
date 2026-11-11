#if DEBUG
import SwiftUI
import StrandAnalytics
import StrandDesign
import StrandImport
import WhoopStore

// DEBUG-only. `--demo-screen <name>` (see `DemoScreens` in StrandiOSApp.swift) opens one state of
// `design/round-s4-body-record/`, so each frame of stage-4.md §10 can be reproduced in the simulator
// (§12.10). The names use only this stage's reserved prefixes (ruling A4):
//
//   bodyrecord-g1 … g10, g5b      the body-record screen            (§10.1)
//   scan-h1 … h14                 the scan sheet                    (§10.2)
//   scan-i1 … i8, i5b             the scan detail                   (§10.3)
//   compare-j1 … j11, j10b        the comparison                    (§10.4)
//   bench-k1 … k8                 the benchmark sheet and detail    (§10.5)
//   labunits-l1 … l7              the Lab Book editor               (§10.6). These follow the
//                                 simulator's own switch: launch with `-noop.labReportUnitsEnabled YES`
//                                 (an argument, so nothing is written) for L1 to L6; without it for L7
//   bodyrecord-history-on, -off   the weigh-in history's scan row   (§10.7)
//
// EVERY VALUE IS SYNTHETIC: the one Fixture Person (stage 1 §13, stage 4 §13), the combined seed of
// stage 1's weigh-ins and this stage's scans and benchmarks, "today" Wed 4 Jun 2031. Each frame runs on
// its own in-memory store; nothing is read from or written to the app's own store or settings.
// Stripped from Release.

enum BodyRecordDemo {
    static func screen(named name: String) -> AnyView? {
        guard DemoScreenPrefixes.bodyRecord.contains(where: { name.hasPrefix($0) }) else { return nil }
        switch name {
        // §10.1
        case "bodyrecord-g1": return host(.screen(loads: false), seed: [])
        case "bodyrecord-g2": return host(.screen(), seed: [])
        case "bodyrecord-g3": return host(.screen(), seed: [.scanA])
        case "bodyrecord-g4", "bodyrecord-g10": return host(.screen(), seed: [.scanA, .scanC, .scanB, .benchmarks])
        case "bodyrecord-g5": return host(.screen(), seed: [.scanA, .unreadableFat])
        case "bodyrecord-g5b": return host(.screen(), seed: [.scanA, .conflictingFat])
        case "bodyrecord-g6": return host(.screen(), seed: [.importedA])
        case "bodyrecord-g7": return host(.screen(), seed: [.benchmarks])
        case "bodyrecord-g8": return host(.screen(), seed: [.customBenchmark])
        case "bodyrecord-g9": return host(.unavailable, seed: [])
        // §10.2
        case "scan-h1": return host(.sheet(.empty), seed: [.weighIns])
        case "scan-h2", "scan-h14": return host(.sheet(.typedA), seed: [])
        case "scan-h3": return host(.sheet(.pounds), seed: [])
        case "scan-h4": return host(.sheet(.outOfRange), seed: [])
        case "scan-h5": return host(.sheet(.notANumber), seed: [])
        case "scan-h6": return host(.sheet(.mismatch), seed: [])
        case "scan-h7": return host(.sheet(.totalOnly), seed: [])
        case "scan-h8": return host(.sheet(.typedA), seed: [.weighIns])
        case "scan-h9": return host(.sheet(.editA), seed: [.scanA])
        case "scan-h10": return host(.sheet(.occupied), seed: [.scanA, .scanB])
        case "scan-h11": return host(.sheet(.saving), seed: [])
        case "scan-h12": return host(.sheet(.failed), seed: [])
        case "scan-h13": return host(.sheet(.confirmDelete), seed: [.scanA])
        // §10.3
        case "scan-i1", "scan-i8": return host(.detail(.a), seed: [.scanA])
        case "scan-i2", "scan-i4": return host(.detail(.c), seed: [.scanC])
        case "scan-i3": return host(.detail(.a), seed: [.scanANoLegs])
        case "scan-i5": return host(.detail(.a), seed: [.scanA, .unreadableFat])
        case "scan-i5b": return host(.detail(.a), seed: [.scanA, .conflictingFat])
        case "scan-i6": return host(.detail(.importedA), seed: [.importedA])
        case "scan-i7": return host(.screen(), seed: [.scanB])
        // §10.4
        case "compare-j1", "compare-j3", "compare-j11": return host(.compare(nil, nil), seed: [.scanA, .scanB])
        case "compare-j2": return host(.compare(nil, nil), seed: [.scanA, .scanB, .scanC])
        case "compare-j4": return host(.compare(nil, nil), seed: [.scanA, .scanC])
        case "compare-j5", "compare-j10": return host(.compare(nil, nil), seed: [.scanB, .scanC])
        case "compare-j6": return host(.compare(nil, nil), seed: [.scanA])
        case "compare-j7": return host(.compare(nil, nil), seed: [])
        case "compare-j8": return host(.compare(.a, .c), seed: [.scanA, .scanB, .scanC])
        case "compare-j9": return host(.compare(.a, .b), seed: [.scanA, .scanC, .scanB])
        case "compare-j10b": return host(.compare(nil, nil), seed: [.scanA, .unreadableFat, .scanB])
        // §10.5
        case "bench-k1": return host(.benchmarkSheet(BenchmarkEntry(key: nil)), seed: [])
        case "bench-k2": return host(.benchmarkSheet(BenchmarkEntry(key: BenchmarkRules.demoDeadHang, text: "1:30")),
                                     seed: [])
        case "bench-k3": return host(.benchmarkSheet(BenchmarkEntry(key: nil, customName: "Fixture carry",
                                                                    customUnit: "s", text: "60")), seed: [])
        case "bench-k4": return host(.benchmarkSheet(BenchmarkEntry(key: BenchmarkRules.demoPushups, text: "12.5")),
                                     seed: [])
        case "bench-k5", "bench-k7", "bench-k8": return host(.benchmarkDetail(BenchmarkRules.demoDeadHang),
                                                             seed: [.benchmarks])
        case "bench-k6": return host(.benchmarkDetail(Fixture.customKey), seed: [.customBenchmark])
        // §10.6
        case "labunits-l1", "labunits-l2", "labunits-l3", "labunits-l4", "labunits-l5", "labunits-l6":
            return host(.labEditor, seed: [])
        case "labunits-l7": return host(.labEditor, seed: [])
        // §10.7
        case "bodyrecord-history-on": return host(.history(bodyRecordOn: true), seed: [.weighIns, .scanA])
        case "bodyrecord-history-off": return host(.history(bodyRecordOn: false), seed: [.weighIns, .scanA])
        default: return nil
        }
    }

    private static func host(_ frame: DemoFrame, seed: [DemoSeed]) -> AnyView {
        AnyView(BodyRecordDemoHost(frame: frame, seed: seed))
    }
}

// MARK: - Fixture

/// The Fixture Person's figures (stage-4.md §13), by field in `BodyScanField.all` order, so this file
/// names no catalogue key.
private enum Fixture {
    static let deviceId = "whoop-FIXTURE-NEW"
    static let otherDeviceId = "whoop-FIXTURE-OLD"
    static let utc = TimeZone(identifier: "UTC") ?? .current
    static let british = Locale(identifier: "en_GB")
    /// Wed 4 Jun 2031 07:42 UTC.
    static let clock = Date(timeIntervalSince1970: 1_938_325_320)
    static let customKey = LabMarkerCsvImport.customKey("bench Fixture carry")

    static let dayA = "2031-01-08", dayB = "2031-04-09", dayC = "2031-05-28"
    static let noonA = 1_925_640_000

    static let a: [Double?] = [100.0, 30.0, 67.0, 3.00, 70.0, 30.0, 1000, nil, 36.0, 30.0, 1.20, 10.00, 4.90, 5.10,
                               20.00, 10.00, 10.00, 32.00, 1.200, 0.5, 0.4, 1900]
    static let b: [Double?] = [95.0, 26.0, 66.0, 3.00, 69.0, 27.4, 800, 80, 30.0, 26.0, 1.15, 10.40, 5.20, 5.20,
                               19.60, 9.80, 9.80, 31.50, nil, nil, nil, 1850]
    static let c: [Double?] = [94.0, 25.0, 66.0, 3.00, nil, nil, nil, nil, nil, nil, nil, nil, 5.30, 5.30, 19.50, nil,
                               nil, nil, nil, nil, nil, nil]

    static var numericFields: [BodyScanField] { BodyScanField.all.filter { $0.range != nil } }

    static func values(_ column: [Double?]) -> [String: Double] {
        var out: [String: Double] = [:]
        for (field, value) in zip(numericFields, column) { out[field.key] = value }
        return out
    }

    static var draftA: BodyScanDraft { BodyScanDraft(day: dayA, values: values(a), note: "Fixture note") }
    static var draftB: BodyScanDraft { BodyScanDraft(day: dayB, values: values(b), note: nil) }
    static var draftC: BodyScanDraft { BodyScanDraft(day: dayC, values: values(c), note: nil) }

    /// Stage 1's weigh-ins (stage-1.md §13.3): Wednesdays at 07:00 UTC from 2031-01-08; week 10 missed.
    static let weighIns: [(week: Int, weight: Double, waist: Double)] = [
        (1, 100.0, 100.0), (2, 99.2, 99.5), (3, 98.4, 99.0), (4, 97.6, 98.5), (5, 97.5, 98.0), (6, 97.4, 97.5),
        (7, 97.3, 97.0), (8, 97.2, 97.0), (9, 97.1, 97.0), (11, 96.0, 96.5), (12, 95.2, 96.0), (13, 95.1, 95.5),
        (14, 95.0, 95.0), (15, 94.9, 94.5), (16, 94.8, 94.5), (17, 94.7, 94.5), (18, 94.6, 94.5),
        (19, 94.5, 94.5), (20, 95.5, 94.5), (21, 94.0, 94.0), (22, 93.5, 93.5),
    ]
    static func weighInDate(week: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(1_925_622_000 + (week - 1) * 7 * 86_400))
    }

    /// The benchmarks of §13.5 at 12:00 UTC.
    static let jan06 = Date(timeIntervalSince1970: 1_925_467_200)
    static let feb17 = Date(timeIntervalSince1970: 1_929_096_000)
    static let mar31 = Date(timeIntervalSince1970: 1_932_724_800)

    /// The sheet's typed text for a stored value, in the stored unit.
    static func texts(_ values: [String: Double]) -> [String: String] {
        var out: [String: String] = [:]
        for field in numericFields {
            guard let value = values[field.key] else { continue }
            out[field.key] = BodyRecordPresenter.displayed(value, field: field, unitSystem: .metric).text
        }
        return out
    }
}

private enum DemoSeed {
    case scanA, scanB, scanC, scanANoLegs, unreadableFat, conflictingFat, importedA, benchmarks, customBenchmark,
         weighIns
}

private enum DemoScan { case a, b, c, importedA }

private enum DemoSheet {
    case empty, typedA, pounds, outOfRange, notANumber, mismatch, totalOnly, editA, occupied, saving, failed,
         confirmDelete
}

private enum DemoFrame {
    case screen(loads: Bool = true)
    case unavailable
    case sheet(DemoSheet)
    case detail(DemoScan)
    case compare(DemoScan?, DemoScan?)
    case benchmarkSheet(BenchmarkEntry)
    case benchmarkDetail(String)
    case labEditor
    case history(bodyRecordOn: Bool)
}

// MARK: - The host

/// Seeds an in-memory store for one frame, then shows the frame in a navigation stack with the
/// body-record routes, the demo's context in the environment and nothing of the app's own state.
private struct BodyRecordDemoHost: View {
    let frame: DemoFrame
    let seed: [DemoSeed]
    @State private var prepared: Prepared?

    struct Prepared {
        let context: BodyRecordContext
        let repository: Repository
        let scans: [BodyScan]
    }

    var body: some View {
        Group {
            if let prepared {
                NavigationStack {
                    content(prepared)
                        .redesignDestinations()
                }
                .environment(\.bodyRecordContextOverride, prepared.context)
                .environmentObject(prepared.repository)
                .environmentObject(NavRouter())
            } else {
                NoopTheme.canvas.ignoresSafeArea()
            }
        }
        .preferredColorScheme(.dark)
        .task { prepared = try? await prepare() }
    }

    @MainActor
    private func prepare() async throws -> Prepared {
        let store = try await WhoopStore.inMemory()
        let repository = Repository(deviceId: Fixture.deviceId)
        repository.setStoreForTesting(store)
        let clock = Fixture.clock
        let context = BodyRecordContext(
            store: BodyRecordStore(repository: repository, timeZone: { Fixture.utc }, now: { clock }),
            weighIns: WeighInStore(repository: repository, timeZone: { Fixture.utc }, now: { clock }),
            unitSystem: { .metric }, locale: { Fixture.british }, now: { clock }, timeZone: { Fixture.utc })
        for item in seed { try await apply(item, store: store, context: context) }
        return Prepared(context: context, repository: repository, scans: await context.store.scans())
    }

    @MainActor
    private func apply(_ item: DemoSeed, store: WhoopStore, context: BodyRecordContext) async throws {
        switch item {
        case .scanA: try await context.store.save(Fixture.draftA, replacing: nil)
        case .scanB: try await context.store.save(Fixture.draftB, replacing: nil)
        case .scanC: try await context.store.save(Fixture.draftC, replacing: nil)
        case .scanANoLegs:
            var values = Fixture.draftA.values
            for key in [BodyScanKeys.legsLean, BodyScanKeys.legLeftLean, BodyScanKeys.legRightLean] {
                values.removeValue(forKey: key)
            }
            try await context.store.save(BodyScanDraft(day: Fixture.dayA, values: values, note: nil), replacing: nil)
        case .unreadableFat:
            // Variant V9: the fat-mass row rewritten in a unit that is not recognised.
            let rows = try await LabBookRows.stored(marker: BodyScanKeys.fatMass, store: store)
            if var fat = rows.first(where: { $0.takenAt == Fixture.noonA }) {
                fat.unit = "stone"
                try await store.upsertOwnerLabMarkers([fat])
            }
        case .conflictingFat:
            // Variant V16: a second fat-mass row of 31.0 under another strap id.
            let rows = try await LabBookRows.stored(marker: BodyScanKeys.fatMass, store: store)
            if var other = rows.first(where: { $0.takenAt == Fixture.noonA }) {
                other.id += "-other"
                other.deviceId = Fixture.otherDeviceId
                other.value = 31.0
                try await store.upsertOwnerLabMarkers([other])
            }
        case .importedA:
            // Variant V10: scan A's rows as a markers CSV import in the wide scope writes them.
            let rows = Fixture.values(Fixture.a).map { key, value in
                LabMarkerRow(id: "\(key)-\(Fixture.noonA)-1A2B3C4D", deviceId: Fixture.deviceId, markerKey: key,
                             category: MarkerCatalog.definition(for: key)?.category.rawValue ?? "",
                             day: Fixture.dayA, takenAt: Fixture.noonA, value: value, valueText: nil,
                             unit: BodyScanField.field(for: key)?.storedUnit ?? "",
                             source: LabMarkerCsvImport.sourceId, note: nil, referenceText: nil)
            }
            try await store.upsertOwnerLabMarkers(rows)
        case .benchmarks:
            let deadHang = BenchmarkRules.demoDeadHang, pushups = BenchmarkRules.demoPushups
            try await context.store.saveBenchmark(key: deadHang, value: 20, unit: "s", takenAt: Fixture.jan06, note: nil)
            try await context.store.saveBenchmark(key: deadHang, value: 30, unit: "s", takenAt: Fixture.feb17, note: nil)
            try await context.store.saveBenchmark(key: deadHang, value: 45, unit: "s", takenAt: Fixture.mar31,
                                                  note: "Fixture bar")
            try await context.store.saveBenchmark(key: pushups, value: 10, unit: "reps", takenAt: Fixture.jan06, note: nil)
            try await context.store.saveBenchmark(key: pushups, value: 14, unit: "reps", takenAt: Fixture.feb17, note: nil)
            try await context.store.saveBenchmark(key: Fixture.customKey, value: 60, unit: "s", takenAt: Fixture.jan06,
                                                  note: nil)
        case .customBenchmark:
            try await context.store.saveBenchmark(key: Fixture.customKey, value: 60, unit: "s", takenAt: Fixture.jan06,
                                                  note: nil)
        case .weighIns:
            for entry in Fixture.weighIns {
                try await context.weighIns.save(weight: entry.weight, waist: entry.waist, unitSystem: .metric,
                                                takenAt: Fixture.weighInDate(week: entry.week))
            }
        }
    }

    @MainActor @ViewBuilder
    private func content(_ prepared: Prepared) -> some View {
        let context = prepared.context
        switch frame {
        case .screen(let loads):
            BodyRecordScreenView(context: context, loadsOnAppear: loads)
        case .unavailable:
            BodyRecordScreenView(context: context, model: unavailableModel(context), loadsOnAppear: false)
        case .sheet(let sheet):
            BodyScanSheetScreen(context: context, editing: editing(sheet, prepared.scans),
                                model: sheetModel(sheet, context: context, scans: prepared.scans),
                                confirmingDelete: { if case .confirmDelete = sheet { return true }; return false }())
        case .detail(let scan):
            BodyScanDetailScreen(context: context, scanId: id(scan, prepared.scans) ?? "")
        case .compare(let earlier, let later):
            BodyScanCompareScreen(context: context, earlierId: earlier.flatMap { id($0, prepared.scans) },
                                  laterId: later.flatMap { id($0, prepared.scans) })
        case .benchmarkSheet(let entry):
            BenchmarkSheetScreen(context: context, key: entry.key, model: benchmarkModel(entry, context: context))
        case .benchmarkDetail(let key):
            BenchmarkDetailScreen(context: context, key: key)
        case .labEditor:
            MarkerEditorView { _ in true }
        case .history(let on):
            BodyRecordDemoHistory(weighIns: context.weighIns, bodyRecordOn: on)
        }
    }

    private func id(_ scan: DemoScan, _ scans: [BodyScan]) -> String? {
        switch scan {
        case .a: return scans.first { $0.day == Fixture.dayA && $0.source == MarkerCatalog.scanSource }?.id
        case .b: return scans.first { $0.day == Fixture.dayB }?.id
        case .c: return scans.first { $0.day == Fixture.dayC }?.id
        case .importedA: return scans.first { $0.source == LabMarkerCsvImport.sourceId }?.id
        }
    }

    private func editing(_ sheet: DemoSheet, _ scans: [BodyScan]) -> BodyScan? {
        switch sheet {
        case .editA, .confirmDelete: return scans.first { $0.day == Fixture.dayA }
        case .occupied: return scans.first { $0.day == Fixture.dayB }
        default: return nil
        }
    }

    @MainActor
    private func unavailableModel(_ context: BodyRecordContext) -> BodyRecordModel {
        let model = context.model()
        model.showLoadForDemo(.storeUnavailable)
        return model
    }

    @MainActor
    private func sheetModel(_ sheet: DemoSheet, context: BodyRecordContext, scans: [BodyScan]) -> BodyScanSheetModel {
        let model = context.sheetModel(editing: editing(sheet, scans))
        var entry = BodyScanEntry(day: Fixture.dayA)
        switch sheet {
        case .empty:
            entry = BodyScanEntry(day: context.today)
        case .typedA, .saving, .failed:
            entry.texts = Fixture.texts(Fixture.draftA.values)
            entry.note = "Fixture note"
        case .pounds:
            entry.texts = Fixture.texts(Fixture.draftA.values)
            entry.texts[MarkerCatalog.scanTotalMassKey] = "220.5"
            entry.units[MarkerCatalog.scanTotalMassKey] = "lb"
            entry.texts[BodyScanKeys.boneMass] = "3000"
            entry.units[BodyScanKeys.boneMass] = "g"
        case .outOfRange:
            entry.texts = Fixture.texts(Fixture.draftC.values)
            entry.texts[BodyScanKeys.fatMass] = "250"
        case .notANumber:
            entry.texts = Fixture.texts(Fixture.draftC.values)
            entry.texts[BodyScanKeys.leanMass] = "6,7"
        case .mismatch:
            entry = BodyScanEntry(day: Fixture.dayB)
            entry.texts = Fixture.texts(Fixture.draftB.values)
            entry.texts[BodyScanKeys.fatFreeMass] = "96.0"
        case .totalOnly:
            entry.texts = [MarkerCatalog.scanTotalMassKey: "100.0"]
        case .editA, .confirmDelete:
            return model
        case .occupied:
            model.entry.day = Fixture.dayA
            model.showPhaseForDemo(.occupied)
            return model
        }
        model.entry = entry
        if case .saving = sheet { model.showPhaseForDemo(.saving) }
        if case .failed = sheet { model.showPhaseForDemo(.failed) }
        return model
    }

    @MainActor
    private func benchmarkModel(_ entry: BenchmarkEntry, context: BodyRecordContext) -> BenchmarkSheetModel {
        let model = context.benchmarkModel(key: entry.key)
        model.entry = entry
        return model
    }
}

/// Frames W1 and W2 (§10.7): the weigh-in history's rows with the body record on and off, from the
/// presenter the history screen draws, on the demo's in-memory store.
private struct BodyRecordDemoHistory: View {
    let weighIns: WeighInStore
    let bodyRecordOn: Bool
    @State private var history: WeighInHistory?

    var body: some View {
        List {
            ForEach(history?.rows ?? []) { row in
                if let scanId = row.scanId {
                    NavigationLink(value: RedesignRoute.bodyScan(id: scanId)) { line(row) }
                } else {
                    line(row)
                }
            }
            .listRowBackground(NoopTheme.card)
        }
        .scrollContentBackground(.hidden)
        .background(NoopTheme.canvas.ignoresSafeArea())
        .navigationTitle(Text(verbatim: CutScorecardPresenter.historyTitle))
        .task {
            let weights = await weighIns.readings(.weight)
            let waists = await weighIns.readings(.waist)
            history = CutScorecardPresenter.history(weights: weights, waists: waists, appleHealth: [],
                                                    unitSystem: .metric, locale: Fixture.british,
                                                    today: "2031-06-04", bodyRecordEnabled: bodyRecordOn)
        }
    }

    private func line(_ row: WeighInHistoryRow) -> some View {
        VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
            HStack {
                Text(verbatim: row.dateText).noopFont(.rowTitle)
                Spacer()
                Text(verbatim: row.weightText ?? "").noopFont(.rowNumber)
            }
            Text(verbatim: row.caption).noopFont(.caption)
        }
    }
}
#endif
