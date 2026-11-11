#if DEBUG
import SwiftUI
import StrandDesign
import WhoopStore

// DEBUG-only. `--demo-screen <name>` renders the Lab Book screen on a synthetic store whose readings
// sit under several device ids, to check by eye that a strap being archived, unregistered or
// forgotten hides none of them (stage 1 ruling R42; labbook-ownership.md §12.11):
//
//   labbook-ownership          the ten rows of §13 and its registry, N active
//   labbook-ownership-forgot   the same after the archived strap B is forgotten
//
// EVERY VALUE IS SYNTHETIC: the "Fixture Person" of stage 1 §13, spread over the device ids of
// labbook-ownership.md §13. Each state runs on its own in-memory store; nothing is read from or
// written to the app's own store. The screen itself still reads the app's own display settings
// (the first-use notice and the scorecard flag), as the real screen does. Stripped from Release.
//
// This provider answers exactly the two names above and nil for every other. Its element in the
// demo registry of StrandiOSApp.swift is added separately (work package LO-3h), with `prefixes`.

enum LabBookOwnershipDemo {
    /// The demo-name prefix reserved for this change (rulings addendum A4).
    static let prefixes = ["labbook-"]

    /// The view for a demo name this provider owns, else nil.
    static func screen(named name: String) -> AnyView? {
        switch name {
        case "labbook-ownership": return AnyView(LabBookOwnershipDemoHost(forgetArchivedStrap: false))
        case "labbook-ownership-forgot": return AnyView(LabBookOwnershipDemoHost(forgetArchivedStrap: true))
        default: return nil
        }
    }
}

// MARK: - The fixture (labbook-ownership.md §13)

private enum LabBookOwnershipDemoFixture {
    static let a = "my-whoop"             // registered, paired (every fresh store has it)
    static let b = "whoop-FIXTURE-OLD"    // registered, archived
    static let c = "whoop-FIXTURE-GONE"   // no registry row
    static let d = "oura-FIXTURE-RING"    // registered, paired, another brand
    static let n = "whoop-FIXTURE-NEW"    // registered, active

    static let t1 = 1_925_622_000    // 2031-01-08 07:00 UTC
    static let t2 = 1_926_226_800    // 2031-01-15 07:00
    static let t3a = 1_926_828_000   // 2031-01-22 06:00
    static let t3 = 1_926_831_600    // 2031-01-22 07:00
    static let t4 = 1_927_436_400    // 2031-01-29 07:00

    static func row(_ suffix: String, _ deviceId: String, _ markerKey: String, _ category: String,
                    _ day: String, _ takenAt: Int, _ value: Double?, _ unit: String,
                    source: String = "manual", text: String? = nil, note: String? = nil) -> LabMarkerRow {
        LabMarkerRow(id: "\(markerKey)-\(takenAt)-\(suffix)", deviceId: deviceId, markerKey: markerKey,
                     category: category, day: day, takenAt: takenAt, value: value, valueText: text,
                     unit: unit, source: source, note: note, referenceText: nil)
    }

    /// F1 to F10. F7 is a copy of F6 (listed once); F8 conflicts with F3 (both listed).
    static let rows: [LabMarkerRow] = [
        row("F0000001", a, "weight", "bodyMeasurement", "2031-01-08", t1, 100.0, "kg"),
        row("F0000002", b, "weight", "bodyMeasurement", "2031-01-15", t2, 99.2, "kg"),
        row("F0000003", c, "weight", "bodyMeasurement", "2031-01-22", t3, 98.0, "kg"),
        row("F0000004", n, "weight", "bodyMeasurement", "2031-01-29", t4, 97.6, "kg"),
        row("F0000005", d, "waist", "bodyMeasurement", "2031-01-08", t1, 100.0, "cm"),
        row("F0000006", b, "ldl", "bloodPanel", "2031-01-15", t2, 3.0, "mmol/L", source: "lab-csv", note: "fixture panel"),
        row("F0000007", n, "ldl", "bloodPanel", "2031-01-15", t2, 3.0, "mmol/L", source: "lab-csv", note: "fixture panel"),
        row("F0000008", n, "weight", "bodyMeasurement", "2031-01-22", t3, 98.4, "kg"),
        row("F0000009", b, "weight", "bodyMeasurement", "2031-01-22", t3a, 98.2, "kg"),
        row("F0000010", c, "fixture_note", "other", "2031-01-15", t2, nil, "text", text: "clear"),
    ]

    /// An in-memory store in the §13 state, and optionally with strap B forgotten: its strap data
    /// deleted and its registry row removed, which is what "Forget device" does to the store.
    static func store(forgetArchivedStrap: Bool) async throws -> WhoopStore {
        let store = try await WhoopStore.inMemory()
        let registry = DeviceRegistryStore(dbQueue: store.registryWriter)
        try registry.add(PairedDevice(id: b, brand: "WHOOP", model: "WHOOP 4.0", sourceKind: .liveBLE,
                                      capabilities: [.hr], status: .archived, addedAt: 2, lastSeenAt: 2))
        try registry.add(PairedDevice(id: d, brand: "Oura", model: "Oura Ring 3", sourceKind: .oura,
                                      capabilities: [.hr, .sleep], status: .paired, addedAt: 3, lastSeenAt: 3))
        try registry.add(PairedDevice(id: n, brand: "WHOOP", model: "WHOOP 4.0", sourceKind: .liveBLE,
                                      capabilities: [.hr], status: .paired, addedAt: 4, lastSeenAt: 4))
        try registry.setActive(n)
        _ = try await store.upsertLabMarkers(rows)
        if forgetArchivedStrap {
            try await store.deleteAllData(deviceId: b)
            try registry.remove(b)
        }
        return store
    }
}

// MARK: - Host

private struct LabBookOwnershipDemoHost: View {
    let forgetArchivedStrap: Bool

    @State private var repository: Repository?
    @State private var failed = false
    @StateObject private var live = LiveState()

    var body: some View {
        Group {
            if let repository {
                NavigationStack { LabBookView() }
                    .environmentObject(repository)
                    .environmentObject(live)
            } else if failed {
                Text(verbatim: "The demo store could not be built.")
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textSecondary)
            } else {
                ProgressView()
            }
        }
        .task {
            guard repository == nil else { return }
            do {
                let store = try await LabBookOwnershipDemoFixture.store(forgetArchivedStrap: forgetArchivedStrap)
                let repo = Repository(deviceId: LabBookOwnershipDemoFixture.n)
                repo.setStoreForTesting(store)
                repository = repo
            } catch {
                failed = true
            }
        }
    }
}
#endif
