// API ASSUMED BY THESE TESTS
//
// From docs/personal/superapp/specs/labbook-ownership.md §6.2, in the new file
// Strand/Data/LabBookRows.swift:
//
//   enum LabBookRows {
//       static func all(store: WhoopStore, activeDeviceId: String) async -> [LabMarkerRow]
//       static func category(_ category: String, store: WhoopStore, activeDeviceId: String) async -> [LabMarkerRow]
//       static func marker(_ markerKey: String, store: WhoopStore, activeDeviceId: String) async -> [LabMarkerRow]
//       static func stored(marker markerKey: String, store: WhoopStore) async throws -> [LabMarkerRow]
//   }
//
// From §6.1, in Packages/WhoopStore (declared in full in the API blocks of the store tests,
// Packages/WhoopStore/Tests/WhoopStoreTests/LabMarkerUnionTests.swift and
// LabMarkerOwnershipStoreTests.swift):
//
//   public func WhoopStore.allLabMarkers() async throws -> [LabMarkerRow]     ordered by (takenAt, id)
//   public static func LabMarkerUnion.isCopy(_ a: LabMarkerRow, _ b: LabMarkerRow) -> Bool
//
// Existing app API whose BEHAVIOUR changes (signatures stay):
//
//   static func BodyMeasurementProvider.labBookRows(_ kind: BodyMeasurementKind, store: WhoopStore,
//                                                   activeDeviceId: String) async -> [LabMarkerRow]
//       becomes one call to `LabBookRows.marker` (§6.2), so `BodyMeasurementProvider.refresh()`,
//       `WeighInStore.readings(_:)` and the scorecard series see rows under EVERY device id present
//       in `labMarker`, registered or not, any brand.
//   func AICoachEngine.onDeviceSignalsBlock() async -> String
//       reads its Lab Book roll-up through `LabBookRows.category` (§6.3).
//
// Existing API used unchanged: WhoopStore.inMemory(), upsertLabMarkers(_:),
// labMarkers(deviceId:category:), metricSeries(deviceId:key:from:to:), upsertMetricSeries(_:deviceId:),
// registryWriter; DeviceRegistryStore.init(dbQueue:), add(_:), setActive(_:), all(); PairedDevice;
// Repository.init(deviceId:), setStoreForTesting(_:), adoptActiveDeviceId(_:);
// BodyMeasurementProvider.init(repository:defaults:today:), refresh(), series(_:consumer:),
// candidates(_:), current(_:consumer:), resolve(_:asOf:consumer:);
// WeighInStore.init(repository:provider:timeZone:now:), readings(_:);
// CutScorecardSettings, CutScorecardInputBuilder.build(today:), CutScorecard.evaluate(_:);
// AICoachEngine.init(repo:), bodyMeasurements, bodyMeasurementLine(_:); DeviceRegistry.forget(_:store:);
// LabBookFormat.value(_:key:), MarkerCatalog.definition(for:), LabMarkerCategory.
//
// Behaviour assumed where the specification leaves it unstated:
//
//  1. `LabBookRows.all` equals `LabMarkerUnion.merged` over every stored row: ordered by
//     (`takenAt`, `id`) ascending, a set of copies represented by the active id's row, else by the row
//     with the smallest device id (§7.1).
//  2. `LabBookRows.stored(marker:store:)` returns the stored rows in the store's order, (`takenAt`,
//     `id`) ascending, copies included.
//  3. The Coach roll-up keeps its text rules (§6.3 changes the read only): categories in
//     `LabMarkerCategory.allCases` order, the newest reading of each marker, eight summaries at most.
//     The order of two markers inside one category is a dictionary's and is not asserted.
//
// The fixture below is the app-target twin of
// Packages/WhoopStore/Tests/WhoopStoreTests/LabBookOwnershipFixture.swift (specification §13). The
// app test bundle does not link GRDB, so it seeds through the existing `upsertLabMarkers` and writes
// the six projected cells of §13 through `upsertMetricSeries`; the raw-SQL seeding, the rowid-level
// dump and the upgrade of a table the new build did not write are the store tests'.
//
// Specification §12.3 (cases 52 to 55, 67), §12.5 (cases 72 and 79), §12.8 (faults F10 to F12, F28,
// F29) and §13. Synthetic values only: the one "Fixture Person".

import XCTest
import WhoopStore
import StrandAnalytics
import StrandImport
@testable import Strand

// MARK: - Fixture (specification §13)

enum LabBookOwnershipAppFixture {

    // MARK: Device ids

    /// A: registered, paired, brand WHOOP. The row every fresh store is seeded with.
    static let a = "my-whoop"
    /// B: registered, archived, brand WHOOP.
    static let b = "whoop-FIXTURE-OLD"
    /// C: no registry row.
    static let c = "whoop-FIXTURE-GONE"
    /// D: registered, paired, brand Oura.
    static let d = "oura-FIXTURE-RING"
    /// N: registered, active, brand WHOOP.
    static let n = "whoop-FIXTURE-NEW"
    /// Not in §13: the serial id the adoption test re-points N onto, as in the store fixture.
    static let serial = "whoop-FIXTURE-SERIAL"

    /// Every id a test may store a row under.
    static let everyId = [a, b, c, d, n, serial]

    // MARK: Instants (epoch seconds, UTC)

    static let t1 = 1_925_622_000    // 2031-01-08 07:00
    static let t2 = 1_926_226_800    // 2031-01-15 07:00
    static let t3a = 1_926_828_000   // 2031-01-22 06:00, one hour before t3
    static let t3 = 1_926_831_600    // 2031-01-22 07:00
    static let t4 = 1_927_436_400    // 2031-01-29 07:00
    /// Not in §13: one day after t4, a free instant for the date-edit tests.
    static let t5 = 1_927_522_800    // 2031-01-30 07:00

    static let day1 = "2031-01-08"
    static let day2 = "2031-01-15"
    static let day3 = "2031-01-22"
    static let day4 = "2031-01-29"
    static let day5 = "2031-01-30"

    /// 2032-01-01 00:00 UTC: after every instant these tests write.
    static let later = Date(timeIntervalSince1970: 1_956_528_000)
    static let utc = TimeZone(identifier: "UTC")!

    static func date(_ epoch: Int) -> Date { Date(timeIntervalSince1970: Double(epoch)) }

    // MARK: Rows

    static func row(
        id: String, deviceId: String, markerKey: String, category: String, day: String, takenAt: Int,
        value: Double?, valueText: String? = nil, unit: String, source: String = "manual",
        note: String? = nil, referenceText: String? = nil
    ) -> LabMarkerRow {
        LabMarkerRow(id: id, deviceId: deviceId, markerKey: markerKey, category: category, day: day,
                     takenAt: takenAt, value: value, valueText: valueText, unit: unit, source: source,
                     note: note, referenceText: referenceText)
    }

    static let f1 = row(id: "weight-1925622000-F0000001", deviceId: a, markerKey: "weight",
                        category: "bodyMeasurement", day: day1, takenAt: t1, value: 100.0, unit: "kg")
    static let f2 = row(id: "weight-1926226800-F0000002", deviceId: b, markerKey: "weight",
                        category: "bodyMeasurement", day: day2, takenAt: t2, value: 99.2, unit: "kg")
    static let f3 = row(id: "weight-1926831600-F0000003", deviceId: c, markerKey: "weight",
                        category: "bodyMeasurement", day: day3, takenAt: t3, value: 98.0, unit: "kg")
    static let f4 = row(id: "weight-1927436400-F0000004", deviceId: n, markerKey: "weight",
                        category: "bodyMeasurement", day: day4, takenAt: t4, value: 97.6, unit: "kg")
    static let f5 = row(id: "waist-1925622000-F0000005", deviceId: d, markerKey: "waist",
                        category: "bodyMeasurement", day: day1, takenAt: t1, value: 100.0, unit: "cm")
    static let f6 = row(id: "ldl-1926226800-F0000006", deviceId: b, markerKey: "ldl",
                        category: "bloodPanel", day: day2, takenAt: t2, value: 3.0, unit: "mmol/L",
                        source: "lab-csv", note: "fixture panel")
    static let f7 = row(id: "ldl-1926226800-F0000007", deviceId: n, markerKey: "ldl",
                        category: "bloodPanel", day: day2, takenAt: t2, value: 3.0, unit: "mmol/L",
                        source: "lab-csv", note: "fixture panel")
    static let f8 = row(id: "weight-1926831600-F0000008", deviceId: n, markerKey: "weight",
                        category: "bodyMeasurement", day: day3, takenAt: t3, value: 98.4, unit: "kg")
    static let f9 = row(id: "weight-1926828000-F0000009", deviceId: b, markerKey: "weight",
                        category: "bodyMeasurement", day: day3, takenAt: t3a, value: 98.2, unit: "kg")
    static let f10 = row(id: "fixture_note-1926226800-F0000010", deviceId: c, markerKey: "fixture_note",
                         category: "other", day: day2, takenAt: t2, value: nil, valueText: "clear",
                         unit: "text")

    /// The ten rows in table order, F1 to F10.
    static let all: [LabMarkerRow] = [f1, f2, f3, f4, f5, f6, f7, f8, f9, f10]

    /// The ten rows ordered by (`takenAt`, `id`) ascending.
    static let storedOrder: [LabMarkerRow] = [f5, f1, f10, f6, f7, f2, f9, f3, f8, f4]

    /// §13: the nine readings listed with N active. F7 stands for the pair F6 and F7.
    static let mergedWithNActive: [LabMarkerRow] = [f5, f1, f10, f7, f2, f9, f3, f8, f4]

    /// §13: the nine readings listed with B active. F6 stands for the pair.
    static let mergedWithBActive: [LabMarkerRow] = [f5, f1, f10, f6, f2, f9, f3, f8, f4]

    /// §13: the weight history, oldest first. Stage 1 listed F1, F2, F9, F8, F4.
    static let weightHistory: [LabMarkerRow] = [f1, f2, f9, f3, f8, f4]

    /// A single-id install: every reading under A. F7 and F3 are left out because the unique index
    /// (deviceId, markerKey, takenAt, source) cannot hold them beside F6 and F8 under one id.
    static let singleIdRows: [LabMarkerRow] = [f5, f1, f10, f6, f2, f9, f8, f4].map { row in
        var moved = row
        moved.deviceId = a
        return moved
    }

    /// A copy of F4 (same content) stored under B, for the copy cases of the weigh-in store. The
    /// weight fixture of §13 holds a conflict and no copy; this id is constructed for these tests.
    static let f4CopyUnderB: LabMarkerRow = {
        var copy = f4
        copy.id = "weight-1927436400-F00000C4"
        copy.deviceId = b
        return copy
    }()

    // MARK: Projected cells

    /// One `metricSeries` row under `lab-book`.
    struct Cell: Hashable, CustomStringConvertible {
        let key: String
        let day: String
        let value: Double
        var description: String { "\(key)/\(day)=\(value)" }
    }

    /// §13: the six cells, ordered by (key, day). No cell for `fixture_note`.
    static let cells: [Cell] = [
        Cell(key: "ldl", day: day2, value: 3.0),
        Cell(key: "waist", day: day1, value: 100.0),
        Cell(key: "weight", day: day1, value: 100.0),
        Cell(key: "weight", day: day2, value: 99.2),
        Cell(key: "weight", day: day3, value: 98.4),
        Cell(key: "weight", day: day4, value: 97.6),
    ]

    static let markerKeys = ["fixture_note", "ldl", "waist", "weight"]

    // MARK: Stores

    static func registry(_ store: WhoopStore) -> DeviceRegistryStore {
        DeviceRegistryStore(dbQueue: store.registryWriter)
    }

    static func registerFixtureDevices(in store: WhoopStore) throws {
        let devices = registry(store)
        try devices.add(PairedDevice(id: b, brand: "WHOOP", model: "WHOOP 4.0", sourceKind: .liveBLE,
                                      capabilities: [.hr], status: .archived, addedAt: 2, lastSeenAt: 2))
        try devices.add(PairedDevice(id: d, brand: "Oura", model: "Oura Ring 3", sourceKind: .oura,
                                      capabilities: [.hr, .sleep], status: .paired, addedAt: 3, lastSeenAt: 3))
        try devices.add(PairedDevice(id: n, brand: "WHOOP", model: "WHOOP 4.0", sourceKind: .liveBLE,
                                      capabilities: [.hr], status: .paired, addedAt: 4, lastSeenAt: 4))
        try devices.setActive(n)
    }

    /// An in-memory store holding the §13 registry and no Lab Book row: A paired, B archived, D paired
    /// (brand Oura), N active, and no row for C.
    static func emptyStoreWithRegistry() async throws -> WhoopStore {
        let store = try await WhoopStore.inMemory()
        try registerFixtureDevices(in: store)
        return store
    }

    /// The §13 state: the registry, the ten rows and the six projected cells.
    static func seededStore() async throws -> WhoopStore {
        let store = try await emptyStoreWithRegistry()
        try await seed(all, into: store)
        return store
    }

    /// Stores `rows` and sets every cell of §13 that one of them backs to its §13 value, so no
    /// expectation depends on which projection rule the seeding write used.
    static func seed(_ rows: [LabMarkerRow], into store: WhoopStore) async throws {
        try await store.upsertLabMarkers(rows)
        for cell in cells where rows.contains(where: { $0.markerKey == cell.key && $0.day == cell.day && $0.value != nil }) {
            try await setCell(cell, in: store)
        }
    }

    static func setCell(_ cell: Cell, in store: WhoopStore) async throws {
        try await store.upsertMetricSeries([MetricPoint(day: cell.day, key: cell.key, value: cell.value)],
                                           deviceId: WhoopStore.labBookSourceId)
    }

    // MARK: Reads through the existing per-id API

    /// Every Lab Book row under every fixture id, read one id and one category at a time through the
    /// per-id calls that exist today, ordered by (`takenAt`, `id`). Two equal snapshots mean that no
    /// row was deleted, added, moved to another id or changed in any of its twelve columns.
    static func snapshot(_ store: WhoopStore) async throws -> [LabMarkerRow] {
        var rows: [LabMarkerRow] = []
        for id in everyId {
            for category in LabMarkerCategory.allCases {
                rows += try await store.labMarkers(deviceId: id, category: category.rawValue)
            }
        }
        return rows.sorted { ($0.takenAt, $0.id) < ($1.takenAt, $1.id) }
    }

    /// Stored row count per fixture id, ids with no row left out.
    static func countsById(_ store: WhoopStore) async throws -> [String: Int] {
        var counts: [String: Int] = [:]
        for row in try await snapshot(store) { counts[row.deviceId, default: 0] += 1 }
        return counts
    }

    /// Rows per device id in the §13 state.
    static let countsById: [String: Int] = [a: 1, b: 3, c: 2, d: 1, n: 3]

    /// The `lab-book` cells of the fixture's marker keys, ordered by (key, day).
    static func labBookCells(_ store: WhoopStore) async throws -> [Cell] {
        var out: [Cell] = []
        for key in markerKeys {
            let points = try await store.metricSeries(deviceId: WhoopStore.labBookSourceId, key: key,
                                                      from: "0000-01-01", to: "9999-12-31")
            out += points.sorted { $0.day < $1.day }.map { Cell(key: $0.key, day: $0.day, value: $0.value) }
        }
        return out
    }

    static func registryIds(_ store: WhoopStore) throws -> [String] {
        try registry(store).all().map(\.id).sorted()
    }
}

// MARK: - Harness

/// The stage 1 readers over one store: the weigh-in store, the provider (scorecard flag on) and the
/// scorecard input builder, with "today" on 2031-01-30, the day after the fixture's last reading.
@MainActor
struct LabBookOwnershipAppHarness {
    typealias Fx = LabBookOwnershipAppFixture

    let store: WhoopStore
    let repo: Repository
    let defaults: UserDefaults
    let provider: BodyMeasurementProvider
    let weighIns: WeighInStore
    let builder: CutScorecardInputBuilder
    let registry: DeviceRegistry

    static let today = Fx.day5

    /// `suites` collects the defaults suite created here, for the caller's `tearDown`.
    static func make(store: WhoopStore, activeDeviceId: String, suites: inout [String]) throws -> LabBookOwnershipAppHarness {
        let name = "LabBookOwnershipTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        suites.append(name)
        defaults.set(true, forKey: "noop.cutScorecardEnabled")
        let repo = Repository(deviceId: activeDeviceId)
        repo.setStoreForTesting(store)
        let today = Self.today
        let provider = BodyMeasurementProvider(repository: repo, defaults: defaults, today: { today })
        let weighIns = WeighInStore(repository: repo, provider: provider, timeZone: { Fx.utc }, now: { Fx.later })
        let settings = CutScorecardSettings(defaults: defaults)
        let builder = CutScorecardInputBuilder(repository: repo, provider: provider, settings: settings,
                                               timeZone: { Fx.utc })
        let registry = DeviceRegistry(store: Fx.registry(store))
        registry.reload()
        return LabBookOwnershipAppHarness(store: store, repo: repo, defaults: defaults, provider: provider,
                                          weighIns: weighIns, builder: builder, registry: registry)
    }

    /// The weekly weights of the scorecard as built from the provider now.
    func weeklyWeights() async -> [Double] {
        await provider.refresh()
        return CutScorecard.evaluate(await builder.build(today: Self.today)).weeks.compactMap(\.weightKg)
    }
}

// MARK: - Tests

@MainActor
final class LabBookRowsTests: XCTestCase {

    private typealias Fx = LabBookOwnershipAppFixture
    private typealias H = LabBookOwnershipAppHarness

    private var suites: [String] = []

    override func tearDown() {
        for name in suites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        suites = []
        super.tearDown()
    }

    private static let labBookHeader =
        "LAB BOOK (the user's own logged health numbers — not medical advice; do not interpret as clinical findings):"

    /// One marker's summary as the Coach roll-up words it.
    private func summary(_ row: LabMarkerRow) -> String {
        let name = MarkerCatalog.definition(for: row.markerKey)?.displayName ?? row.markerKey
        let value = row.value.map { "\(LabBookFormat.value($0, key: row.markerKey)) \(row.unit)" }
            ?? row.valueText ?? "—"
        return "\(name) \(value)"
    }

    /// The summaries of the roll-up's one line, in the order sent. Empty when no roll-up was sent.
    private func rollUpSummaries(_ text: String) -> [String] {
        let lines = text.components(separatedBy: "\n")
        guard let header = lines.firstIndex(of: Self.labBookHeader), header + 1 < lines.count else { return [] }
        return lines[header + 1].trimmingCharacters(in: .whitespaces).components(separatedBy: ", ")
    }

    /// The roll-up text built from the per-id read that exists today, for a store whose rows all sit
    /// under `deviceId` and hold at most one marker per category (so no dictionary order is involved).
    private func perIdRollUp(_ store: WhoopStore, deviceId: String) async throws -> String {
        var summaries: [String] = []
        for category in LabMarkerCategory.allCases {
            let rows = try await store.labMarkers(deviceId: deviceId, category: category.rawValue)
            XCTAssertLessThanOrEqual(Set(rows.map(\.markerKey)).count, 1, "one marker per category in this fixture")
            guard let latest = rows.sorted(by: { $0.takenAt < $1.takenAt }).last else { continue }
            summaries.append(summary(latest))
        }
        guard !summaries.isEmpty else { return "" }
        return ["", Self.labBookHeader, "  " + summaries.prefix(8).joined(separator: ", ")].joined(separator: "\n")
    }

    // MARK: - §12.3 case 52: the list

    /// Protects F10 and F11: the list holds the readings under the active id, an archived strap, an
    /// id with no registry row and another brand's id, with a set of copies shown once.
    func testLabBookListShowsReadingsUnderEveryId() async throws {
        let store = try await Fx.seededStore()
        let before = try await Fx.snapshot(store)
        XCTAssertEqual(before, Fx.storedOrder, "the fixture as stored")

        let listed = await LabBookRows.all(store: store, activeDeviceId: Fx.n)

        XCTAssertEqual(listed, Fx.mergedWithNActive)
        XCTAssertEqual(Set(listed.map(\.deviceId)), [Fx.a, Fx.b, Fx.c, Fx.d, Fx.n],
                       "a reading is listed whichever id it sits under, registered or not, any brand")
        XCTAssertTrue(listed.contains(Fx.f3) && listed.contains(Fx.f10), "the rows under the id with no registry row")
        XCTAssertTrue(listed.contains(Fx.f5), "the row under another brand's id")
        XCTAssertEqual(listed.filter { $0.markerKey == "ldl" }, [Fx.f7], "the pair of copies is one line: the active id's row")
        let after = try await Fx.snapshot(store)
        XCTAssertEqual(after, before, "listing is a read: nothing is merged, moved or deleted")
    }

    /// The list does not depend on which strap is active, apart from which stored row stands for a
    /// set of copies: the active id's, else the smallest device id's.
    func testLabBookListIsTheSameAfterTheActiveIdIsRepointed() async throws {
        let store = try await Fx.seededStore()

        let underB = await LabBookRows.all(store: store, activeDeviceId: Fx.b)
        XCTAssertEqual(underB, Fx.mergedWithBActive, "with B active its own copy stands for the pair")
        for active in [Fx.a, Fx.c, Fx.d, Fx.serial, "no-such-device", ""] {
            let listed = await LabBookRows.all(store: store, activeDeviceId: active)
            XCTAssertEqual(listed, Fx.mergedWithNActive,
                           "active \(active): nine readings; whoop-FIXTURE-NEW sorts before whoop-FIXTURE-OLD")
        }
        // Compared without the device id, the list is one list.
        func content(_ rows: [LabMarkerRow]) -> [String] {
            rows.map { "\($0.markerKey)|\($0.takenAt)|\($0.source)|\(String(describing: $0.value))|\(String(describing: $0.valueText))" }
        }
        XCTAssertEqual(content(underB), content(Fx.mergedWithNActive))
    }

    /// Ruling R42, decision D3: two readings at one instant under two strap ids, with different
    /// values, are different readings. Both are listed by every reader. Protects F5 at app level.
    func testConflictingSameInstantReadingsAreBothListedByEveryReader() async throws {
        let store = try await Fx.seededStore()
        XCTAssertEqual(Fx.f3.takenAt, Fx.f8.takenAt)
        XCTAssertNotEqual(Fx.f3.value, Fx.f8.value)

        for active in [Fx.n, Fx.a, Fx.c] {
            let all = await LabBookRows.all(store: store, activeDeviceId: active)
            XCTAssertTrue(all.contains(Fx.f3) && all.contains(Fx.f8), "the Lab Book list, active \(active)")
            let marker = await LabBookRows.marker("weight", store: store, activeDeviceId: active)
            XCTAssertEqual(marker.filter { $0.takenAt == Fx.t3 }, [Fx.f3, Fx.f8], "one marker, active \(active)")
            let h = try H.make(store: store, activeDeviceId: active, suites: &suites)
            let history = await h.weighIns.readings(.weight)
            XCTAssertEqual(history.filter { $0.takenAt == Fx.t3 }, [Fx.f3, Fx.f8], "the weigh-in history, active \(active)")
            await h.provider.refresh()
            let fed = h.provider.candidates(.weight).labBook
            XCTAssertTrue(fed.contains(Fx.f3) && fed.contains(Fx.f8), "the resolver's candidates, active \(active)")
        }
    }

    func testCategoryAndMarkerReadsFilterOnly() async throws {
        let store = try await Fx.seededStore()

        let body = await LabBookRows.category("bodyMeasurement", store: store, activeDeviceId: Fx.n)
        XCTAssertEqual(body, [Fx.f5, Fx.f1, Fx.f2, Fx.f9, Fx.f3, Fx.f8, Fx.f4])
        let blood = await LabBookRows.category("bloodPanel", store: store, activeDeviceId: Fx.n)
        XCTAssertEqual(blood, [Fx.f7])
        let bloodUnderB = await LabBookRows.category("bloodPanel", store: store, activeDeviceId: Fx.b)
        XCTAssertEqual(bloodUnderB, [Fx.f6])
        let other = await LabBookRows.category("other", store: store, activeDeviceId: Fx.n)
        XCTAssertEqual(other, [Fx.f10], "a qualitative reading under an id with no registry row")
        let none = await LabBookRows.category("imaging", store: store, activeDeviceId: Fx.n)
        XCTAssertEqual(none, [])

        let weight = await LabBookRows.marker("weight", store: store, activeDeviceId: Fx.n)
        XCTAssertEqual(weight, Fx.weightHistory)
        let waist = await LabBookRows.marker("waist", store: store, activeDeviceId: Fx.n)
        XCTAssertEqual(waist, [Fx.f5])
        let ldl = await LabBookRows.marker("ldl", store: store, activeDeviceId: Fx.n)
        XCTAssertEqual(ldl, [Fx.f7])
        let unknown = await LabBookRows.marker("no_such_marker", store: store, activeDeviceId: Fx.n)
        XCTAssertEqual(unknown, [])

        // The categories together are the whole list.
        var joined: [LabMarkerRow] = []
        for category in LabMarkerCategory.allCases {
            joined += await LabBookRows.category(category.rawValue, store: store, activeDeviceId: Fx.n)
        }
        XCTAssertEqual(joined.sorted { ($0.takenAt, $0.id) < ($1.takenAt, $1.id) }, Fx.mergedWithNActive)
    }

    /// The write-side read of §6.3: every stored row of the marker, copies included, under any id.
    func testStoredReturnsEveryStoredRowOfTheMarkerUnmerged() async throws {
        let store = try await Fx.seededStore()

        let ldl = try await LabBookRows.stored(marker: "ldl", store: store)
        XCTAssertEqual(ldl, [Fx.f6, Fx.f7], "both copies: a write has to see each stored row")
        let weight = try await LabBookRows.stored(marker: "weight", store: store)
        XCTAssertEqual(weight, Fx.weightHistory)
        let note = try await LabBookRows.stored(marker: "fixture_note", store: store)
        XCTAssertEqual(note, [Fx.f10])
        let unknown = try await LabBookRows.stored(marker: "no_such_marker", store: store)
        XCTAssertEqual(unknown, [])
    }

    /// Every read of the funnel, the provider, the weigh-in store, the scorecard and the Coach leaves
    /// each stored row and each projected cell exactly as it was.
    func testReadsMoveCopyOrChangeNoRowAndNoCell() async throws {
        let store = try await Fx.seededStore()
        let rowsBefore = try await Fx.snapshot(store)
        let cellsBefore = try await Fx.labBookCells(store)
        XCTAssertEqual(cellsBefore, Fx.cells)
        let registryBefore = try Fx.registryIds(store)

        for active in Fx.everyId {
            _ = await LabBookRows.all(store: store, activeDeviceId: active)
            for category in LabMarkerCategory.allCases {
                _ = await LabBookRows.category(category.rawValue, store: store, activeDeviceId: active)
            }
            for key in Fx.markerKeys {
                _ = await LabBookRows.marker(key, store: store, activeDeviceId: active)
                _ = try await LabBookRows.stored(marker: key, store: store)
            }
            let h = try H.make(store: store, activeDeviceId: active, suites: &suites)
            _ = await h.weighIns.readings(.weight)
            _ = await h.weighIns.readings(.waist)
            _ = await h.weeklyWeights()
            _ = await AICoachEngine(repo: h.repo).onDeviceSignalsBlock()
        }

        let rowsAfter = try await Fx.snapshot(store)
        XCTAssertEqual(rowsAfter, rowsBefore)
        let countsAfter = try await Fx.countsById(store)
        XCTAssertEqual(countsAfter, Fx.countsById, "no row changed id by being read")
        let cellsAfter = try await Fx.labBookCells(store)
        XCTAssertEqual(cellsAfter, cellsBefore)
        XCTAssertEqual(try Fx.registryIds(store), registryBefore, "reading registers nothing")
    }

    // MARK: - The one read path under stage 1's readers

    /// §6.2: `BodyMeasurementProvider.labBookRows` is one call to `LabBookRows.marker`. Protects F28.
    func testProviderLabBookRowsIsTheFunnelsMarkerRead() async throws {
        let store = try await Fx.seededStore()
        for active in Fx.everyId + ["no-such-device"] {
            for kind in [BodyMeasurementKind.weight, .waist] {
                let fromProvider = await BodyMeasurementProvider.labBookRows(kind, store: store, activeDeviceId: active)
                let fromFunnel = await LabBookRows.marker(kind.markerKey, store: store, activeDeviceId: active)
                XCTAssertEqual(fromProvider, fromFunnel, "\(kind.markerKey), active \(active)")
            }
            let weights = await BodyMeasurementProvider.labBookRows(.weight, store: store, activeDeviceId: active)
            XCTAssertEqual(weights, Fx.weightHistory, "active \(active)")
            let waists = await BodyMeasurementProvider.labBookRows(.waist, store: store, activeDeviceId: active)
            XCTAssertEqual(waists, [Fx.f5], "the waist under another brand's id, active \(active)")
        }
    }

    /// §12.3 case 54, protects F10 and F28. A store whose only weight sits under an id with no
    /// registry row, and whose only waist sits under another brand's id: stage 1 listed neither.
    func testWeighInHistoryAndResolverSeeAReadingUnderAnUnregisteredId() async throws {
        let store = try await Fx.emptyStoreWithRegistry()
        try await Fx.seed([Fx.f3, Fx.f5], into: store)
        XCTAssertFalse(try Fx.registryIds(store).contains(Fx.c), "the premise: C has no registry row")
        let h = try H.make(store: store, activeDeviceId: Fx.n, suites: &suites)

        let weights = await h.weighIns.readings(.weight)
        XCTAssertEqual(weights, [Fx.f3], "the weigh-in history")
        let waists = await h.weighIns.readings(.waist)
        XCTAssertEqual(waists, [Fx.f5])

        await h.provider.refresh()
        XCTAssertEqual(h.provider.candidates(.weight).labBook, [Fx.f3], "the resolver's candidates")
        XCTAssertEqual(h.provider.candidates(.waist).labBook, [Fx.f5])
        let series = h.provider.series(.weight, consumer: .display)
        XCTAssertEqual(series.map(\.day), [Fx.day3])
        XCTAssertEqual(series.map(\.value), [98.0])
        XCTAssertEqual(series.map(\.rowId), [Fx.f3.id])
        XCTAssertEqual(h.provider.resolve(.weight, asOf: Fx.day3, consumer: .display),
                       ResolvedBodyMeasurement(kind: .weight, value: 98.0, source: .labBook, day: Fx.day3))
        XCTAssertEqual(h.provider.current(.weight, consumer: .estimate)?.value, 98.0)
        XCTAssertEqual(h.provider.current(.waist, consumer: .display)?.value, 100.0)
        XCTAssertNil(h.provider.resolve(.weight, asOf: Fx.day2, consumer: .display)?.day,
                     "no dated reading before the first one")

        let result = CutScorecard.evaluate(await h.builder.build(today: H.today))
        XCTAssertEqual(result.weeks.compactMap(\.weightKg), [98.0], "the scorecard's weekly series")
        XCTAssertEqual(result.weeks.compactMap(\.waistCm), [100.0])
        XCTAssertEqual(result.currentWeightKg, 98.0)

        let after = try await Fx.snapshot(store)
        XCTAssertEqual(after, [Fx.f5, Fx.f3], "neither row was moved to the active id")
    }

    /// The whole fixture through stage 1's readers: one history, one series, one weekly series.
    func testWeighInHistoryProviderAndScorecardSeriesReadEveryIdOfTheFixture() async throws {
        let store = try await Fx.seededStore()
        for active in [Fx.n, Fx.a, Fx.serial] {
            let h = try H.make(store: store, activeDeviceId: active, suites: &suites)

            let weights = await h.weighIns.readings(.weight)
            XCTAssertEqual(weights, Fx.weightHistory, "active \(active)")
            let waists = await h.weighIns.readings(.waist)
            XCTAssertEqual(waists, [Fx.f5], "active \(active)")

            await h.provider.refresh()
            XCTAssertEqual(h.provider.candidates(.weight).labBook, Fx.weightHistory, "active \(active)")
            let series = h.provider.series(.weight, consumer: .display)
            XCTAssertEqual(series.map(\.day), [Fx.day1, Fx.day2, Fx.day3, Fx.day4], "active \(active)")
            XCTAssertEqual(series.map(\.value), [100.0, 99.2, 98.4, 97.6],
                           "active \(active): on 2031-01-22 the latest instant, then the greatest id")
            XCTAssertEqual(series.map(\.rowId), [Fx.f1.id, Fx.f2.id, Fx.f8.id, Fx.f4.id], "active \(active)")
            XCTAssertEqual(h.provider.series(.waist, consumer: .display).map(\.value), [100.0], "active \(active)")

            let weekly = await h.weeklyWeights()
            XCTAssertEqual(weekly, [100.0, 99.2, 98.4, 97.6], "active \(active): the scorecard series")
        }
    }

    // MARK: - §12.3 case 53 and case 55: the Coach roll-up

    /// Protects F12. A is active and holds only the oldest weight; the roll-up states the newest
    /// reading of each marker wherever it is stored.
    func testCoachRollUpUsesTheLatestReadingAcrossIds() async throws {
        let store = try await Fx.seededStore()
        let h = try H.make(store: store, activeDeviceId: Fx.a, suites: &suites)

        // No provider attached: the engine's flag-off text, where weight and waist are in the roll-up.
        let text = await AICoachEngine(repo: h.repo).onDeviceSignalsBlock()

        let summaries = rollUpSummaries(text)
        XCTAssertEqual(Set(summaries), [summary(Fx.f7), summary(Fx.f4), summary(Fx.f5), summary(Fx.f10)],
                       "the newest reading of each of the four markers, in:\n\(text)")
        XCTAssertEqual(summaries.count, 4, "the pair of copies is one summary, in:\n\(text)")
        XCTAssertEqual(summaries.first, summary(Fx.f7), "blood panel first, as the categories are ordered")
        XCTAssertEqual(summaries.last, summary(Fx.f10), "the qualitative reading under the unregistered id")
        XCTAssertTrue(text.contains("Weight 97.6 kg"), text)
        XCTAssertFalse(text.contains(summary(Fx.f1)), "the active id's own, older weight is not the latest: \(text)")

        // Provider attached and the flag on: weight and waist come from the provider, which reads the
        // same rows; the other markers stay in the roll-up.
        await h.provider.refresh()
        let engine = AICoachEngine(repo: h.repo)
        engine.bodyMeasurements = h.provider
        let attached = await engine.onDeviceSignalsBlock()
        XCTAssertEqual(Set(rollUpSummaries(attached)), [summary(Fx.f7), summary(Fx.f10)], attached)
        let weight = try XCTUnwrap(h.provider.current(.weight, consumer: .display))
        let waist = try XCTUnwrap(h.provider.current(.waist, consumer: .display))
        XCTAssertEqual(weight.value, 97.6)
        XCTAssertEqual(waist.value, 100.0, "the waist under another brand's id")
        XCTAssertTrue(attached.contains(AICoachEngine.bodyMeasurementLine(weight)), attached)
        XCTAssertTrue(attached.contains(AICoachEngine.bodyMeasurementLine(waist)), attached)
    }

    /// §12.3 case 55, the behavioural half of the single read path: the Lab Book list, the Coach
    /// roll-up, the weigh-in history, the resolver and the scorecard name one newest weight. Checked
    /// with the newest reading under a registered id, then again after that strap is forgotten.
    func testListCoachHistoryAndResolverAgreeOnTheNewestWeight() async throws {
        let store = try await Fx.seededStore()
        let h = try H.make(store: store, activeDeviceId: Fx.a, suites: &suites)

        func newestEverywhere(_ stage: String) async throws {
            let listed = await LabBookRows.all(store: store, activeDeviceId: h.repo.deviceId)
            XCTAssertEqual(listed.last { $0.markerKey == "weight" }, Fx.f4, "\(stage): the Lab Book list")
            let coach = await AICoachEngine(repo: h.repo).onDeviceSignalsBlock()
            XCTAssertTrue(rollUpSummaries(coach).contains(summary(Fx.f4)), "\(stage): the Coach roll-up, in:\n\(coach)")
            let history = await h.weighIns.readings(.weight)
            XCTAssertEqual(history.last, Fx.f4, "\(stage): the weigh-in history")
            await h.provider.refresh()
            XCTAssertEqual(h.provider.current(.weight, consumer: .display),
                           ResolvedBodyMeasurement(kind: .weight, value: 97.6, source: .labBook, day: Fx.day4),
                           "\(stage): the resolver")
            XCTAssertEqual(h.provider.series(.weight, consumer: .display).last?.rowId, Fx.f4.id, "\(stage): the series")
            let result = CutScorecard.evaluate(await h.builder.build(today: H.today))
            XCTAssertEqual(result.currentWeightKg, 97.6, "\(stage): the scorecard")
        }

        try await newestEverywhere("N registered")
        // N holds the newest weight. Forget it: its id is then in no registry row.
        await h.registry.forget(Fx.n, store: store)
        XCTAssertFalse(try Fx.registryIds(store).contains(Fx.n))
        try await newestEverywhere("N forgotten")
    }

    // MARK: - §12.5: a single-id install is unchanged

    /// Case 72 at app level: with every row under the active id, the funnel returns exactly the rows
    /// the per-id read returns.
    func testSingleIdInstallListsExactlyTheRowsThePerIdReadReturns() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.upsertLabMarkers(Fx.singleIdRows)
        let expected = Fx.singleIdRows.sorted { ($0.takenAt, $0.id) < ($1.takenAt, $1.id) }
        var perId: [LabMarkerRow] = []
        for category in LabMarkerCategory.allCases {
            perId += try await store.labMarkers(deviceId: Fx.a, category: category.rawValue)
        }
        XCTAssertEqual(perId.sorted { ($0.takenAt, $0.id) < ($1.takenAt, $1.id) }, expected, "the per-id read")

        let listed = await LabBookRows.all(store: store, activeDeviceId: Fx.a)
        XCTAssertEqual(listed, expected)
        for category in LabMarkerCategory.allCases {
            let funnel = await LabBookRows.category(category.rawValue, store: store, activeDeviceId: Fx.a)
            let direct = try await store.labMarkers(deviceId: Fx.a, category: category.rawValue)
            XCTAssertEqual(funnel, direct.sorted { ($0.takenAt, $0.id) < ($1.takenAt, $1.id) }, category.rawValue)
        }
        for key in Fx.markerKeys {
            let funnel = await LabBookRows.marker(key, store: store, activeDeviceId: Fx.a)
            let direct = try await store.labMarkers(deviceId: Fx.a, markerKey: key)
            XCTAssertEqual(funnel, direct.sorted { ($0.takenAt, $0.id) < ($1.takenAt, $1.id) }, key)
        }
        let h = try H.make(store: store, activeDeviceId: Fx.a, suites: &suites)
        let weights = await h.weighIns.readings(.weight)
        let directWeights = try await store.labMarkers(deviceId: Fx.a, markerKey: "weight")
        XCTAssertEqual(weights, directWeights, "the weigh-in history of a single-id install")
    }

    /// Case 79, protects F29. With every row under the active id, the Coach roll-up built through
    /// the funnel equals, byte for byte, the text built from the per-id read. Stage 2 takes its
    /// byte-identity baseline after this is green.
    func testSingleIdInstallCoachRollUpTextIsUnchanged() async throws {
        // One marker per category, so the text is fully determined: weight, ldl and the note.
        let rows = Fx.singleIdRows.filter { $0.markerKey != "waist" }
        let store = try await WhoopStore.inMemory()
        try await store.upsertLabMarkers(rows)
        let repo = Repository(deviceId: Fx.a)
        repo.setStoreForTesting(store)

        let expected = try await perIdRollUp(store, deviceId: Fx.a)
        XCTAssertEqual(rollUpSummaries(expected).count, 3, "the per-id text, spelled out: \(expected)")
        XCTAssertTrue(expected.hasPrefix("\n" + Self.labBookHeader + "\n  "), expected)
        XCTAssertTrue(expected.contains("Weight 97.6 kg"), expected)
        XCTAssertTrue(expected.hasSuffix("fixture_note clear"), expected)

        let text = await AICoachEngine(repo: repo).onDeviceSignalsBlock()
        XCTAssertEqual(text, expected)
        let again = await AICoachEngine(repo: repo).onDeviceSignalsBlock()
        XCTAssertEqual(again, expected, "the text is stable between two builds")

        // The whole single-id fixture, where weight and waist share a category and their order is a
        // dictionary's: the same summaries, compared without that order.
        let full = try await WhoopStore.inMemory()
        try await full.upsertLabMarkers(Fx.singleIdRows)
        let fullRepo = Repository(deviceId: Fx.a)
        fullRepo.setStoreForTesting(full)
        let fullText = await AICoachEngine(repo: fullRepo).onDeviceSignalsBlock()
        let summaries = rollUpSummaries(fullText)
        var singleF4 = Fx.f4, singleF5 = Fx.f5, singleF6 = Fx.f6, singleF10 = Fx.f10
        singleF4.deviceId = Fx.a; singleF5.deviceId = Fx.a; singleF6.deviceId = Fx.a; singleF10.deviceId = Fx.a
        XCTAssertEqual(summaries.count, 4, fullText)
        XCTAssertEqual(Set(summaries), [summary(singleF6), summary(singleF4), summary(singleF5), summary(singleF10)], fullText)
        XCTAssertEqual(summaries.first, summary(singleF6), fullText)
        XCTAssertEqual(summaries.last, summary(singleF10), fullText)
        XCTAssertEqual(fullText.components(separatedBy: "\n").count, 3, "an empty line, the header, one line: \(fullText)")
    }

    // MARK: - §12.3 case 67

    /// A store with no Lab Book row at all: every merged read is empty and the write-side read is
    /// empty without throwing. The failing-read half of case 67 is not reachable from this target;
    /// see the hand-off note of this work package.
    func testAnEmptyStoreListsNothingAndStoresNothingByBeingRead() async throws {
        let store = try await Fx.emptyStoreWithRegistry()

        let all = await LabBookRows.all(store: store, activeDeviceId: Fx.n)
        XCTAssertEqual(all, [])
        let category = await LabBookRows.category("bodyMeasurement", store: store, activeDeviceId: Fx.n)
        XCTAssertEqual(category, [])
        let marker = await LabBookRows.marker("weight", store: store, activeDeviceId: Fx.n)
        XCTAssertEqual(marker, [])
        let stored = try await LabBookRows.stored(marker: "weight", store: store)
        XCTAssertEqual(stored, [])
        let h = try H.make(store: store, activeDeviceId: Fx.n, suites: &suites)
        let text = await AICoachEngine(repo: h.repo).onDeviceSignalsBlock()
        XCTAssertEqual(text, "", "no roll-up is sent for an empty Lab Book")
        let snapshot = try await Fx.snapshot(store)
        XCTAssertEqual(snapshot, [])
        let cells = try await Fx.labBookCells(store)
        XCTAssertEqual(cells, [])
    }
}
