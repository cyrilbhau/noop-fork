// API ASSUMED BY THESE TESTS
//
// From docs/personal/superapp/specs/labbook-ownership.md §6.1, in Packages/WhoopStore (declared in
// full in the API blocks of Packages/WhoopStore/Tests/WhoopStoreTests/LabMarkerOwnershipStoreTests.swift
// and LabBookProjectionRepairTests.swift):
//
//   public func WhoopStore.allLabMarkers() async throws -> [LabMarkerRow]
//   @discardableResult public func WhoopStore.upsertOwnerLabMarkers(_ rows: [LabMarkerRow]) async throws -> Int
//   @discardableResult public func WhoopStore.deleteLabMarkerAndCopies(id: String) async throws -> [String]
//   public static func LabMarkerUnion.isCopy(_ a: LabMarkerRow, _ b: LabMarkerRow) -> Bool
//   public func WhoopStore.deleteAllData(deviceId: String) async throws          (exists; no longer touches labMarker)
//   public func DeviceRegistryStore.adoptSerialIdentity(from:to:) throws -> Bool (exists; no longer touches labMarker)
//
// From §6.2, in Strand/Data/LabBookRows.swift: `LabBookRows.all`, `.marker`, `.stored(marker:store:)`
// (declared in full in LabBookRowsTests.swift).
//
// Existing app API whose BEHAVIOUR changes (signatures stay), §7.4:
//
//   WeighInStore.save(weight:waist:unitSystem:takenAt:)
//       with no manual row of the marker at the instant under the active id, a manual row there under
//       ANY other device id, registered or not, any brand, throws `.instantOccupied` and writes nothing.
//   WeighInStore.edit(_:value:unitSystem:takenAt:), same instant
//       the row and each of its copies take the new value and unit, each under its own id.
//   WeighInStore.edit(_:value:unitSystem:takenAt:), another instant
//       occupants are the stored rows of the marker and source at the target instant under any id.
//       None: the replacement is inserted under the edited row's device id, then the old row AND its
//       copies are deleted. Every occupant a copy of the replacement: nothing is written and the old
//       row and its copies are deleted. Otherwise `.instantOccupied`, nothing written.
//   WeighInStore.delete(_:)
//       deletes the row and its copies.
//   DeviceRegistry.deleteDeviceData(_:store:), DeviceRegistry.forget(_:store:),
//   DeviceRegistry.adoptSerialIdentity(from:to:)
//       unchanged code; they inherit the store's new behaviour.
//
// ASSUMED AND NOT IN THE SPECIFICATION. §7.3 says the repository runs the projection repair "once per
// launch, straight after the store opens, in the single-flight open", ignoring a thrown error and
// logging one line only when `inserted + updated > 0`. That open resolves the app's real database
// path, which a test must never open, so these tests need the step as a function of the store:
//
//   extension Repository {
//       /// What the single-flight open runs on the store it has just opened: the repair of §7.3, a
//       /// thrown error ignored. Calls `log` once, with the diagnostic line, only when
//       /// `inserted + updated > 0`. The line carries the four counts and nothing else that is a
//       /// number; any timestamp or prefix is the log sink's, not part of the line.
//       static func repairLabBookProjection(afterOpening store: WhoopStore, log: (String) -> Void) async
//   }
//
// and `Repository.ensureStore()` calls it exactly once, inside the open task, after
// `WhoopStore(path:)` succeeded. A different name or shape needs these two tests (cases 66 and 77)
// edited with it.
//
// Existing API used unchanged: DataBackup.writeBackupForTesting(databaseAt:to:settings:),
// DataBackup.restore(from:toDatabaseAt:settingsDefaults:allowOversize:beforeReplacingDatabase:),
// WhoopStore.init(path:), checkpointWAL(), upsertMetricSeries(_:deviceId:),
// metricSeries(deviceId:key:from:to:), deleteMetricSeriesPoint(deviceId:day:key:);
// DeviceRegistry.init(store:), reload(), archive(_:), setActive(_:), devices, activeDeviceId;
// WeighInStore.interruptDateEditForTesting; LabMarkerCsvImport.sourceId.
//
// What these tests cannot drive. `LabBookView`'s `load`, `save`, `delete` and CSV import are private
// methods of a SwiftUI view. Cases 60, 61 and 67 therefore run the store calls §7.4 names for the
// screen, on rows built the way the screen builds them; that the screen makes those calls is pinned
// by the source scan `Tools/test_lab_book_single_read_path.py`. The two Devices dialogs are pinned by
// a source assertion (case 76), as §12.8 F26 specifies.
//
// `DeviceRegistry.deleteDeviceData` and `forget` also clear the raw IMU session files of the id
// through the process-wide `ImuSessionFileStore`. These tests pass fixture ids only (B, D, N and the
// constructed serial id), which own no such file; they never pass `my-whoop`.
//
// Specification §12.3 (cases 56 to 66), §12.8 (faults F1, F2, F18, F20, F21, F23 to F26), §12.9
// (case 77), §8.3 (upgrade), §8.6 (whole-data removal) and §13. Synthetic values only: the one
// "Fixture Person". The fixture and harness are in LabBookRowsTests.swift.

import XCTest
import WhoopStore
import StrandAnalytics
import StrandImport
@testable import Strand

@MainActor
final class LabBookOwnershipFlowTests: XCTestCase {

    private typealias Fx = LabBookOwnershipAppFixture
    private typealias H = LabBookOwnershipAppHarness

    private var suites: [String] = []
    private var tmp: URL?

    override func tearDown() {
        for name in suites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        suites = []
        if let tmp { try? FileManager.default.removeItem(at: tmp) }
        tmp = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private struct Interrupted: Error {}

    /// Collects the lines a log closure receives.
    private final class Lines {
        var all: [String] = []
    }

    /// A strap-recorded value under `deviceId`: a `metricSeries` point, which a strap delete clears
    /// and an adoption moves. It shows that the strap operation under test really ran.
    private func seedStrapSeries(_ store: WhoopStore, deviceId: String) async throws {
        try await store.upsertMetricSeries([MetricPoint(day: Fx.day1, key: "fixture_strap_series", value: 1)],
                                           deviceId: deviceId)
    }

    private func strapSeriesCount(_ store: WhoopStore, deviceId: String) async throws -> Int {
        try await store.metricSeries(deviceId: deviceId, key: "fixture_strap_series",
                                     from: "0000-01-01", to: "9999-12-31").count
    }

    private func assertThrows(_ expected: WeighInError, _ message: String = "",
                              file: StaticString = #filePath, line: UInt = #line,
                              _ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("expected \(expected) \(message)", file: file, line: line)
        } catch let error as WeighInError {
            XCTAssertEqual(error, expected, message, file: file, line: line)
        } catch {
            XCTFail("expected \(expected), got \(error) \(message)", file: file, line: line)
        }
    }

    /// Asserts the stored rows and the three listings are those of the untouched §13 fixture.
    private func assertFixtureIntact(_ store: WhoopStore, active: String, _ stage: String,
                                     file: StaticString = #filePath, line: UInt = #line) async throws {
        let rows = try await Fx.snapshot(store)
        XCTAssertEqual(rows, Fx.storedOrder, "\(stage): the stored rows", file: file, line: line)
        let counts = try await Fx.countsById(store)
        XCTAssertEqual(counts, Fx.countsById, "\(stage): the row count under each id", file: file, line: line)
        let everything = try await store.allLabMarkers()
        XCTAssertEqual(everything, Fx.storedOrder, "\(stage): every stored row, under any id", file: file, line: line)
        let listed = await LabBookRows.all(store: store, activeDeviceId: active)
        XCTAssertEqual(listed, active == Fx.b ? Fx.mergedWithBActive : Fx.mergedWithNActive,
                       "\(stage): the Lab Book list", file: file, line: line)
        let h = try H.make(store: store, activeDeviceId: active, suites: &suites)
        let weights = await h.weighIns.readings(.weight)
        XCTAssertEqual(weights, Fx.weightHistory, "\(stage): the weigh-in history", file: file, line: line)
        let waists = await h.weighIns.readings(.waist)
        XCTAssertEqual(waists, [Fx.f5], "\(stage): the waist history", file: file, line: line)
        let weekly = await h.weeklyWeights()
        XCTAssertEqual(weekly, [100.0, 99.2, 98.4, 97.6], "\(stage): the scorecard series", file: file, line: line)
    }

    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// The file's lines that are not whole-line comments, joined.
    private func code(_ relativePath: String) throws -> String {
        try source(relativePath).components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    private func makeTmp() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("labbook-ownership-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tmp = dir
        return dir
    }

    private func freshDefaults() throws -> UserDefaults {
        let name = "LabBookOwnershipTests-restore-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        suites.append(name)
        return defaults
    }

    // MARK: - §12.3 cases 56 to 59: strap operations from the Devices screen

    /// Protects F1. "Delete data" on the archived strap, the other brand's device and the active
    /// strap: each strap's own recordings go, and every Lab Book reading stays stored and listed.
    func testReadingsSurviveDeleteDataOnTheStrapTheyWereEnteredUnder() async throws {
        let store = try await Fx.seededStore()
        let h = try H.make(store: store, activeDeviceId: Fx.n, suites: &suites)
        for id in [Fx.b, Fx.d, Fx.n] { try await seedStrapSeries(store, deviceId: id) }
        try await assertFixtureIntact(store, active: Fx.n, "before")
        let registryBefore = try Fx.registryIds(store)

        for id in [Fx.b, Fx.d, Fx.n] {
            await h.registry.deleteDeviceData(id, store: store)

            let left = try await strapSeriesCount(store, deviceId: id)
            XCTAssertEqual(left, 0, "the delete ran: \(id)'s own recordings are gone")
            try await assertFixtureIntact(store, active: Fx.n, "after Delete data on \(id)")
        }
        XCTAssertEqual(try Fx.registryIds(store), registryBefore, "Delete data keeps the registry rows")
        let cells = try await Fx.labBookCells(store)
        XCTAssertEqual(cells, Fx.cells, "the projected cells of the kept readings are kept")
    }

    /// Protects F1. "Forget device" removes the strap from the list and its recordings, and leaves
    /// the readings entered while it was active, which then sit under an id nothing registers.
    func testReadingsSurviveForgetDevice() async throws {
        let store = try await Fx.seededStore()
        let h = try H.make(store: store, activeDeviceId: Fx.n, suites: &suites)
        for id in [Fx.b, Fx.n] { try await seedStrapSeries(store, deviceId: id) }

        await h.registry.forget(Fx.b, store: store)

        XCTAssertEqual(try Fx.registryIds(store), [Fx.a, Fx.d, Fx.n].sorted(), "B is out of the registry")
        XCTAssertFalse(h.registry.devices.contains { $0.id == Fx.b })
        let leftB = try await strapSeriesCount(store, deviceId: Fx.b)
        XCTAssertEqual(leftB, 0, "the forget ran: B's own recordings are gone")
        try await assertFixtureIntact(store, active: Fx.n, "after forgetting B")

        // Forget the strap that is active, then read as the app does once another id is active.
        await h.registry.forget(Fx.n, store: store)

        XCTAssertEqual(try Fx.registryIds(store), [Fx.a, Fx.d].sorted())
        let leftN = try await strapSeriesCount(store, deviceId: Fx.n)
        XCTAssertEqual(leftN, 0)
        try await assertFixtureIntact(store, active: Fx.n, "after forgetting N, still read as N")
        h.repo.adoptActiveDeviceId(Fx.a)
        try await assertFixtureIntact(store, active: Fx.a, "after forgetting N, read as A")
        let cells = try await Fx.labBookCells(store)
        XCTAssertEqual(cells, Fx.cells)
    }

    /// "Remove" archives the active strap and another becomes active. Nothing is deleted, and every
    /// reading is listed under the new active id.
    func testReadingsSurviveArchiveThenANewActiveStrap() async throws {
        let store = try await Fx.seededStore()
        let h = try H.make(store: store, activeDeviceId: Fx.n, suites: &suites)

        h.registry.archive(Fx.n)
        h.registry.setActive(Fx.a)
        XCTAssertEqual(h.registry.activeDeviceId, Fx.a)
        XCTAssertTrue(h.repo.adoptActiveDeviceId(h.registry.activeDeviceId))

        try await assertFixtureIntact(store, active: Fx.a, "after archiving N and activating A")
        XCTAssertEqual(try Fx.registryIds(store), [Fx.a, Fx.b, Fx.d, Fx.n].sorted(), "archive keeps the registry row")

        // And back: the list is the same list.
        h.registry.setActive(Fx.b)
        XCTAssertTrue(h.repo.adoptActiveDeviceId(Fx.b))
        try await assertFixtureIntact(store, active: Fx.b, "with the archived B re-activated")
    }

    /// Protects F2. N adopts a serial id that already holds a reading at the instant of one of N's
    /// own. The adoption moves the strap's recordings and leaves every Lab Book row where it is, so
    /// the row that `UPDATE OR IGNORE` then `DELETE` used to drop is still stored and still listed.
    func testReadingsSurviveSerialAdoption() async throws {
        let store = try await Fx.seededStore()
        let h = try H.make(store: store, activeDeviceId: Fx.n, suites: &suites)
        // A reading under the serial id at F4's marker, instant and source, with another value.
        var clash = Fx.f4
        clash.id = "weight-1927436400-F00000S4"
        clash.deviceId = Fx.serial
        clash.value = 98.2
        try await store.upsertLabMarkers([clash])
        try await seedStrapSeries(store, deviceId: Fx.n)
        let before = try await Fx.snapshot(store)
        XCTAssertEqual(before.count, 11)

        let moved = h.registry.adoptSerialIdentity(from: Fx.n, to: Fx.serial)

        XCTAssertTrue(moved)
        XCTAssertEqual(try Fx.registryIds(store), [Fx.a, Fx.b, Fx.d, Fx.serial].sorted(), "N's registry row became the serial's")
        let leftUnderN = try await strapSeriesCount(store, deviceId: Fx.n)
        let nowUnderSerial = try await strapSeriesCount(store, deviceId: Fx.serial)
        XCTAssertEqual(leftUnderN, 0, "the adoption ran: the strap's recordings left N")
        XCTAssertEqual(nowUnderSerial, 1, "and are under the serial id")

        let after = try await Fx.snapshot(store)
        XCTAssertEqual(after, before, "no Lab Book row was moved, dropped or changed")
        var expectedCounts = Fx.countsById
        expectedCounts[Fx.serial] = 1
        let counts = try await Fx.countsById(store)
        XCTAssertEqual(counts, expectedCounts, "F4, F7 and F8 are still under N, which no registry row names now")

        h.repo.adoptActiveDeviceId(Fx.serial)
        let listed = await LabBookRows.all(store: store, activeDeviceId: Fx.serial)
        XCTAssertEqual(listed, Fx.mergedWithNActive + [clash], "ten readings: the clashing pair is two readings")
        let history = await h.weighIns.readings(.weight)
        XCTAssertEqual(history, Fx.weightHistory + [clash], "the weigh-in history lists both readings of 2031-01-29")
        await h.provider.refresh()
        XCTAssertEqual(h.provider.series(.weight, consumer: .display).map(\.day), [Fx.day1, Fx.day2, Fx.day3, Fx.day4])
    }

    // MARK: - §8.3: upgrade

    /// A store with rows under several ids, opened by the new build: the launch steps (the repair,
    /// the provider's refresh, every reader) change no row, and afterwards the readers list rows the
    /// stage 1 build did not. The table-level proof, on rows the new build did not write, is
    /// `LabBookOwnershipRehearsalTests` and case 51 in the store tests.
    func testUpgradeFromAStoreWithRowsUnderSeveralIdsChangesNoRow() async throws {
        let store = try await Fx.seededStore()
        let rowsBefore = try await Fx.snapshot(store)
        let registryBefore = try Fx.registryIds(store)
        // A projected cell the old per-id rule left on another of the day's readings (§13 V2).
        try await Fx.setCell(Fx.Cell(key: "weight", day: Fx.day3, value: 98.0), in: store)

        let lines = Lines()
        await Repository.repairLabBookProjection(afterOpening: store) { lines.all.append($0) }
        try await assertFixtureIntact(store, active: Fx.n, "first launch")
        let h = try H.make(store: store, activeDeviceId: Fx.n, suites: &suites)
        _ = await AICoachEngine(repo: h.repo).onDeviceSignalsBlock()
        await Repository.repairLabBookProjection(afterOpening: store) { lines.all.append($0) }

        let rowsAfter = try await Fx.snapshot(store)
        XCTAssertEqual(rowsAfter, rowsBefore, "upgrading deleted, moved, re-keyed or changed a row")
        XCTAssertEqual(try Fx.registryIds(store), registryBefore, "upgrading registered or removed a device")
        let cells = try await Fx.labBookCells(store)
        XCTAssertEqual(cells, Fx.cells, "the one derived cell was corrected and no other cell changed")
        XCTAssertEqual(lines.all.count, 1, "one line for the launch that repaired, none for the next")
    }

    // MARK: - §8.6: whole-data removal still removes everything

    /// Ruling R42 keeps one way to remove every reading: replacing the whole database on purpose.
    /// A backup of a store carries every Lab Book row under every id, and restoring a backup with no
    /// reading over a store that has ten leaves none: nothing is kept outside the database file.
    func testRestoringABackupReplacesEveryReadingAndAnEmptyOneRemovesThemAll() async throws {
        let dir = try makeTmp()
        let seededURL = dir.appendingPathComponent("seeded.sqlite")
        let freshURL = dir.appendingPathComponent("fresh.sqlite")
        let restoredURL = dir.appendingPathComponent("restored.sqlite")

        func build(_ url: URL, seeded: Bool) async throws {
            let store = try await WhoopStore(path: url.path)
            if seeded {
                try Fx.registerFixtureDevices(in: store)
                try await Fx.seed(Fx.all, into: store)
            }
            try await store.checkpointWAL()
        }
        func read(_ url: URL) async throws -> (rows: [LabMarkerRow], everything: [LabMarkerRow],
                                              listed: [LabMarkerRow], cells: [Fx.Cell], registry: [String]) {
            let store = try await WhoopStore(path: url.path)
            return (try await Fx.snapshot(store), try await store.allLabMarkers(),
                    await LabBookRows.all(store: store, activeDeviceId: Fx.n),
                    try await Fx.labBookCells(store), try Fx.registryIds(store))
        }
        try await build(seededURL, seeded: true)
        try await build(freshURL, seeded: false)

        // A backup travels with every row, the unregistered id's included.
        let seededBackup = dir.appendingPathComponent("seeded.noopbak")
        try DataBackup.writeBackupForTesting(databaseAt: seededURL, to: seededBackup)
        let first = DataBackup.restore(from: seededBackup, toDatabaseAt: restoredURL.path,
                                       settingsDefaults: try freshDefaults())
        guard case .imported = first else { return XCTFail("restoring the seeded backup failed: \(first)") }
        let restored = try await read(restoredURL)
        XCTAssertEqual(restored.rows, Fx.storedOrder, "every row under every id, as stored")
        XCTAssertEqual(restored.everything, Fx.storedOrder)
        XCTAssertEqual(restored.listed, Fx.mergedWithNActive)
        XCTAssertEqual(restored.cells, Fx.cells)
        XCTAssertFalse(restored.registry.contains(Fx.c), "C is still an id with no registry row")

        // Erasing on purpose: a backup with no reading, restored over the store that has ten.
        let emptyBackup = dir.appendingPathComponent("fresh.noopbak")
        try DataBackup.writeBackupForTesting(databaseAt: freshURL, to: emptyBackup)
        let second = DataBackup.restore(from: emptyBackup, toDatabaseAt: restoredURL.path,
                                        settingsDefaults: try freshDefaults())
        guard case .imported = second else { return XCTFail("restoring the empty backup failed: \(second)") }
        let erased = try await read(restoredURL)
        XCTAssertEqual(erased.rows, [], "replacing the database removes every reading")
        XCTAssertEqual(erased.everything, [], "under every id, the unregistered one included")
        XCTAssertEqual(erased.listed, [])
        XCTAssertEqual(erased.cells, [], "and every projected cell")
    }

    // MARK: - §12.3 cases 60 and 61: the Lab Book screen's writes

    /// Protects F21. The file that produced F6 and F7 is imported again after the active id changed
    /// to A. The screen builds each row with a fresh id under the active id (`LabBookView` CSV import)
    /// and writes through the owner-scope upsert: the reading is updated where it is stored, and no
    /// third row appears under A.
    func testCsvReimportAfterTheActiveIdChangedUpdatesInsteadOfDoubling() async throws {
        let store = try await Fx.seededStore()
        let h = try H.make(store: store, activeDeviceId: Fx.a, suites: &suites)
        XCTAssertEqual(Fx.f6.source, LabMarkerCsvImport.sourceId, "the fixture's pair is an imported reading")
        func imported(note: String?) -> LabMarkerRow {
            Fx.row(id: "ldl-\(Fx.t2)-\(UUID().uuidString.prefix(8))", deviceId: h.repo.deviceId, markerKey: "ldl",
                   category: "bloodPanel", day: Fx.day2, takenAt: Fx.t2, value: 3.0, unit: "mmol/L",
                   source: LabMarkerCsvImport.sourceId, note: note)
        }

        // The same file again.
        try await store.upsertOwnerLabMarkers([imported(note: "fixture panel")])

        try await assertFixtureIntact(store, active: Fx.a, "after re-importing the same file")
        let cells = try await Fx.labBookCells(store)
        XCTAssertEqual(cells, Fx.cells)

        // The same reading with its note removed in the file: both stored rows follow, each keeping
        // its id and its device id, and the list still shows one line.
        try await store.upsertOwnerLabMarkers([imported(note: nil)])

        var f6 = Fx.f6, f7 = Fx.f7
        f6.note = nil
        f7.note = nil
        let ldl = try await LabBookRows.stored(marker: "ldl", store: store)
        XCTAssertEqual(ldl, [f6, f7], "updated in place: ids and device ids kept, nothing under A")
        let counts = try await Fx.countsById(store)
        XCTAssertEqual(counts, Fx.countsById, "a re-import must not add a row under the active id")
        let listed = await LabBookRows.all(store: store, activeDeviceId: Fx.a)
        XCTAssertEqual(listed.filter { $0.markerKey == "ldl" }, [f7], "one line")
        let others = try await Fx.snapshot(store).filter { $0.markerKey != "ldl" }
        XCTAssertEqual(others, Fx.storedOrder.filter { $0.markerKey != "ldl" }, "no other reading changed")
    }

    /// Protects F20. The list shows the pair F6 and F7 once. Deleting that line removes both stored
    /// rows, so the reading does not reappear from the copy under the other id; and deleting one of
    /// two conflicting readings leaves the other.
    func testLabBookDeleteOfACollapsedReadingRemovesItForGood() async throws {
        let store = try await Fx.seededStore()
        let listed = await LabBookRows.all(store: store, activeDeviceId: Fx.n)
        let shown = try XCTUnwrap(listed.first { $0.markerKey == "ldl" })
        XCTAssertEqual(shown, Fx.f7)

        let deleted = try await store.deleteLabMarkerAndCopies(id: shown.id)

        XCTAssertEqual(deleted, [Fx.f6.id, Fx.f7.id])
        for active in [Fx.n, Fx.b, Fx.a] {
            let after = await LabBookRows.all(store: store, activeDeviceId: active)
            XCTAssertFalse(after.contains { $0.markerKey == "ldl" }, "active \(active): the reading came back")
            XCTAssertEqual(after, Fx.mergedWithNActive.filter { $0.markerKey != "ldl" }, "active \(active)")
        }
        let rows = try await Fx.snapshot(store)
        XCTAssertEqual(rows, Fx.storedOrder.filter { $0.markerKey != "ldl" }, "the other eight rows are untouched")
        let cells = try await Fx.labBookCells(store)
        XCTAssertEqual(cells, Fx.cells.filter { $0.key != "ldl" }, "the reading's projected cell went with it")

        // One of two conflicting readings: that one only.
        let deletedConflict = try await store.deleteLabMarkerAndCopies(id: Fx.f8.id)
        XCTAssertEqual(deletedConflict, [Fx.f8.id])
        let weights = await LabBookRows.marker("weight", store: store, activeDeviceId: Fx.n)
        XCTAssertEqual(weights, [Fx.f1, Fx.f2, Fx.f9, Fx.f3, Fx.f4], "F3, at the same instant, is another reading and stays")
    }

    // MARK: - §12.3 cases 62 to 65: the weigh-in store

    /// Protects F24. F4 is stored twice, under N and under B. A value edit of the listed row changes
    /// both, so the list keeps showing one reading instead of an edited row and a stale twin.
    func testWeighInValueEditKeepsCopiesInStep() async throws {
        let store = try await Fx.seededStore()
        try await store.upsertLabMarkers([Fx.f4CopyUnderB])
        let h = try H.make(store: store, activeDeviceId: Fx.n, suites: &suites)
        let before = await h.weighIns.readings(.weight)
        XCTAssertEqual(before, Fx.weightHistory, "the premise: the copy is not a second line")

        let edited = try await h.weighIns.edit(Fx.f4, value: 98.2, unitSystem: .metric, takenAt: Fx.date(Fx.t4))

        var expected = Fx.f4, expectedCopy = Fx.f4CopyUnderB
        expected.value = 98.2
        expectedCopy.value = 98.2
        XCTAssertEqual(edited, expected, "the edited row keeps its id and its device id")
        let stored = try await LabBookRows.stored(marker: "weight", store: store)
        XCTAssertEqual(stored.filter { $0.takenAt == Fx.t4 }, [expected, expectedCopy],
                       "the copy took the same value under its own id and device id")
        let after = await h.weighIns.readings(.weight)
        XCTAssertEqual(after, [Fx.f1, Fx.f2, Fx.f9, Fx.f3, Fx.f8, expected], "still one reading on 2031-01-29")
        let others = try await Fx.snapshot(store).filter { $0.takenAt != Fx.t4 }
        XCTAssertEqual(others, Fx.storedOrder.filter { $0.takenAt != Fx.t4 }, "no other reading changed")
    }

    /// Protects F25. A date edit of a reading stored twice removes both stored rows of the old
    /// instant, so the old reading does not stay listed from its copy.
    func testWeighInDateEditRemovesTheOldReadingAndItsCopies() async throws {
        let store = try await Fx.seededStore()
        try await store.upsertLabMarkers([Fx.f4CopyUnderB])
        let h = try H.make(store: store, activeDeviceId: Fx.n, suites: &suites)

        let moved = try await h.weighIns.edit(Fx.f4, value: 97.6, unitSystem: .metric, takenAt: Fx.date(Fx.t5))

        XCTAssertEqual(moved.takenAt, Fx.t5)
        XCTAssertEqual(moved.day, Fx.day5)
        XCTAssertEqual(moved.deviceId, Fx.n, "the replacement is written under the edited row's device id")
        XCTAssertEqual(moved.value, 97.6)
        XCTAssertNotEqual(moved.id, Fx.f4.id)
        let stored = try await LabBookRows.stored(marker: "weight", store: store)
        XCTAssertEqual(stored.filter { $0.takenAt == Fx.t4 }, [], "the old row and its copy under B are both gone")
        XCTAssertEqual(stored.filter { $0.takenAt == Fx.t5 }, [moved], "one row at the new instant")
        let after = await h.weighIns.readings(.weight)
        XCTAssertEqual(after, [Fx.f1, Fx.f2, Fx.f9, Fx.f3, Fx.f8, moved])
        let others = try await Fx.snapshot(store).filter { $0.takenAt < Fx.t4 }
        XCTAssertEqual(others, Fx.storedOrder.filter { $0.takenAt < Fx.t4 }, "no other reading changed")

        // A delete of a reading stored twice removes both rows too.
        try await store.upsertLabMarkers([Fx.f4, Fx.f4CopyUnderB])
        try await h.weighIns.delete(Fx.f4)
        let afterDelete = try await LabBookRows.stored(marker: "weight", store: store)
        XCTAssertEqual(afterDelete.filter { $0.takenAt == Fx.t4 }, [], "a deleted weigh-in must not come back from its copy")
    }

    /// Protects F23. The instant is held by a manual reading under an id with no registry row, and
    /// the waist's by one under another brand's id. Stage 1 wrote a second reading there, because
    /// neither id was in its union; now both are listed, so the save is refused whole.
    func testWeighInSaveOntoAnInstantHeldUnderAnUnregisteredIdIsRefused() async throws {
        let store = try await Fx.emptyStoreWithRegistry()
        try await Fx.seed([Fx.f3, Fx.f5], into: store)
        let h = try H.make(store: store, activeDeviceId: Fx.n, suites: &suites)
        let before = try await Fx.snapshot(store)
        XCTAssertEqual(before, [Fx.f5, Fx.f3])

        await assertThrows(.instantOccupied, "a weight at the instant held under the unregistered id") {
            try await h.weighIns.save(weight: 98.4, waist: nil, unitSystem: .metric, takenAt: Fx.date(Fx.t3))
        }
        await assertThrows(.instantOccupied, "a waist at the instant held under the other brand's id") {
            try await h.weighIns.save(weight: 100.0, waist: 100.0, unitSystem: .metric, takenAt: Fx.date(Fx.t1))
        }

        let after = try await Fx.snapshot(store)
        XCTAssertEqual(after, before, "a refused save added, removed or changed a row")
        let everything = try await store.allLabMarkers()
        XCTAssertEqual(everything, before, "nothing was written under the active id")

        // A free instant is unaffected, and a weight alone at t1 is free: only the waist was held.
        let saved = try await h.weighIns.save(weight: 99.2, waist: nil, unitSystem: .metric, takenAt: Fx.date(Fx.t2))
        XCTAssertEqual(saved.map(\.deviceId), [Fx.n], "a new reading is still written under the active id")
        let weightOnly = try await h.weighIns.save(weight: 100.0, waist: nil, unitSystem: .metric, takenAt: Fx.date(Fx.t1))
        XCTAssertEqual(weightOnly.map(\.markerKey), ["weight"])

        // A date edit onto the instant held under the unregistered id, with another value: refused.
        await assertThrows(.instantOccupied, "a date edit onto the unregistered id's instant") {
            try await h.weighIns.edit(saved[0], value: 99.2, unitSystem: .metric, takenAt: Fx.date(Fx.t3))
        }
        let gone = try await store.labMarkers(deviceId: Fx.c, markerKey: "weight")
        XCTAssertEqual(gone, [Fx.f3], "the unregistered id's reading is byte-identical")
        let ring = try await store.labMarkers(deviceId: Fx.d, markerKey: "waist")
        XCTAssertEqual(ring, [Fx.f5], "the other brand's reading is byte-identical")
    }

    /// Protects F25 on the retry path. A date edit of a reading stored twice is interrupted between
    /// its insert and its delete; the same edit retried finds its own replacement at the target
    /// instant, writes nothing and removes the old reading with its copy.
    func testInterruptedDateEditStillCompletesOnRetryWhenCopiesExist() async throws {
        let store = try await Fx.seededStore()
        try await store.upsertLabMarkers([Fx.f4CopyUnderB])
        let h = try H.make(store: store, activeDeviceId: Fx.n, suites: &suites)

        var seamFired = 0
        h.weighIns.interruptDateEditForTesting = {
            seamFired += 1
            throw Interrupted()
        }
        do {
            _ = try await h.weighIns.edit(Fx.f4, value: 97.6, unitSystem: .metric, takenAt: Fx.date(Fx.t5))
            XCTFail("the injected failure must surface to the caller")
        } catch is Interrupted {
            // expected
        } catch {
            XCTFail("expected the injected failure, got \(error)")
        }
        XCTAssertEqual(seamFired, 1)
        let interrupted = try await LabBookRows.stored(marker: "weight", store: store)
        XCTAssertEqual(interrupted.filter { $0.takenAt == Fx.t4 }, [Fx.f4, Fx.f4CopyUnderB],
                       "the interruption leaves the old reading, both rows")
        let inserted = try XCTUnwrap(interrupted.first { $0.takenAt == Fx.t5 })
        XCTAssertEqual(interrupted.filter { $0.takenAt == Fx.t5 }.count, 1)

        h.weighIns.interruptDateEditForTesting = { seamFired += 1 }
        let moved = try await h.weighIns.edit(Fx.f4, value: 97.6, unitSystem: .metric, takenAt: Fx.date(Fx.t5))

        XCTAssertEqual(seamFired, 1, "the retry inserts nothing, so the seam is not reached again")
        XCTAssertEqual(moved, inserted, "the returned row is the row already stored")
        let stored = try await LabBookRows.stored(marker: "weight", store: store)
        XCTAssertEqual(stored.filter { $0.takenAt >= Fx.t4 }, [inserted], "the old row and its copy are gone; one reading remains")
        let after = await h.weighIns.readings(.weight)
        XCTAssertEqual(after, [Fx.f1, Fx.f2, Fx.f9, Fx.f3, Fx.f8, inserted])
    }

    /// §7.4, "every occupant is a copy of the replacement", generalised from one occupant. The
    /// target instant holds the same reading under two ids: the edit writes nothing and removes the
    /// old row. One occupant that is not a copy refuses the edit whole.
    func testDateEditOntoAnInstantWhoseOccupantsAreAllCopiesOfTheReplacementCompletes() async throws {
        let store = try await Fx.seededStore()
        var f2CopyUnderC = Fx.f2
        f2CopyUnderC.id = "weight-1926226800-F00000C2"
        f2CopyUnderC.deviceId = Fx.c
        try await store.upsertLabMarkers([f2CopyUnderC])
        let h = try H.make(store: store, activeDeviceId: Fx.n, suites: &suites)
        var seamFired = 0
        h.weighIns.interruptDateEditForTesting = { seamFired += 1 }

        // F1 (under A) moved onto t2 with F2's value: both occupants equal the replacement in content.
        let moved = try await h.weighIns.edit(Fx.f1, value: 99.2, unitSystem: .metric, takenAt: Fx.date(Fx.t2))

        XCTAssertEqual(seamFired, 0, "nothing was inserted")
        XCTAssertTrue(LabMarkerUnion.isCopy(moved, Fx.f2), "the returned row is the reading as stored")
        XCTAssertTrue([Fx.f2, f2CopyUnderC].contains(moved), "and is one of the rows already there")
        let stored = try await LabBookRows.stored(marker: "weight", store: store)
        XCTAssertEqual(stored, [Fx.f2, f2CopyUnderC, Fx.f9, Fx.f3, Fx.f8, Fx.f4],
                       "the old row is gone, both occupants are byte-identical, nothing was added")

        // F9 (98.2 at t3a) moved onto t3 with F3's value: F3 is a copy of the replacement, F8 is not.
        let before = try await Fx.snapshot(store)
        await assertThrows(.instantOccupied, "one occupant is another reading") {
            try await h.weighIns.edit(Fx.f9, value: 98.0, unitSystem: .metric, takenAt: Fx.date(Fx.t3))
        }
        XCTAssertEqual(seamFired, 0)
        let after = try await Fx.snapshot(store)
        XCTAssertEqual(after, before, "a refused edit added, removed or changed a row")
    }

    // MARK: - §12.3 case 66 and §12.9 case 77: the projection repair at open

    /// Protects F18. The step the single-flight open runs repairs a wrong projected cell, logs once,
    /// and a second run changes nothing and logs nothing. `Repository.ensureStore()` calls it once,
    /// on the store it has just opened.
    func testRepositoryOpenRunsTheProjectionRepairOnce() async throws {
        let store = try await Fx.seededStore()
        _ = try await store.deleteMetricSeriesPoint(deviceId: WhoopStore.labBookSourceId, day: Fx.day3, key: "weight")
        let missing = try await Fx.labBookCells(store)
        XCTAssertEqual(missing.count, 5, "the premise: §13 V1, one cell is missing")
        let rowsBefore = try await Fx.snapshot(store)
        let lines = Lines()

        await Repository.repairLabBookProjection(afterOpening: store) { lines.all.append($0) }

        let repaired = try await Fx.labBookCells(store)
        XCTAssertEqual(repaired, Fx.cells, "the missing cell is back with the day's latest reading across ids")
        XCTAssertEqual(lines.all.count, 1, "one line when something was repaired")

        await Repository.repairLabBookProjection(afterOpening: store) { lines.all.append($0) }

        let again = try await Fx.labBookCells(store)
        XCTAssertEqual(again, Fx.cells)
        XCTAssertEqual(lines.all.count, 1, "no line when there was nothing to repair")
        let rowsAfter = try await Fx.snapshot(store)
        XCTAssertEqual(rowsAfter, rowsBefore, "the repair writes derived cells only")

        // A cell no reading backs (§13 V3) is kept, and keeping it is not worth a line.
        try await Fx.setCell(Fx.Cell(key: "weight", day: Fx.day3, value: 90.0), in: store)
        await Repository.repairLabBookProjection(afterOpening: store) { lines.all.append($0) }
        let unbacked = try await Fx.labBookCells(store)
        XCTAssertEqual(unbacked.first { $0.key == "weight" && $0.day == Fx.day3 }?.value, 90.0)
        XCTAssertEqual(lines.all.count, 1)

        // The call site: once, inside the open, after the store opened.
        let repository = try code("Strand/Data/Repository.swift")
        let open = try XCTUnwrap(repository.range(of: "private func ensureStore()"), "ensureStore was not found")
        let end = try XCTUnwrap(repository.range(of: "func storeHandle()", range: open.upperBound..<repository.endIndex))
        let body = String(repository[open.upperBound..<end.lowerBound])
        let call = "repairLabBookProjection(afterOpening:"
        XCTAssertEqual(occurrences(of: call, in: body), 1, "the open runs the repair exactly once")
        let opened = try XCTUnwrap(body.range(of: "WhoopStore(path:"))
        let called = try XCTUnwrap(body.range(of: call), "the open does not run the repair")
        let published = try XCTUnwrap(body.range(of: "storeOpenTask = task"))
        XCTAssertTrue(opened.upperBound <= called.lowerBound, "the repair runs after the store opened")
        XCTAssertTrue(called.upperBound <= published.lowerBound, "the repair runs inside the single-flight open task")
        XCTAssertEqual(occurrences(of: call, in: repository), 1, "nothing else in Repository.swift runs the repair")
    }

    /// The repair's one log line carries its four counts and nothing of the owner's: no marker, no
    /// value, no unit, no note, no day and no device id.
    func testRepairLogLineCarriesCountsOnly() async throws {
        let store = try await Fx.seededStore()
        // inserted 1 (the ldl cell), updated 1 (the cell left on F3's value), unchanged 4,
        // unbackedKept 1 (§13 V4: a cell with no reading that day).
        _ = try await store.deleteMetricSeriesPoint(deviceId: WhoopStore.labBookSourceId, day: Fx.day2, key: "ldl")
        try await Fx.setCell(Fx.Cell(key: "weight", day: Fx.day3, value: 98.0), in: store)
        try await Fx.setCell(Fx.Cell(key: "weight", day: "2031-02-05", value: 97.5), in: store)
        let lines = Lines()

        await Repository.repairLabBookProjection(afterOpening: store) { lines.all.append($0) }

        XCTAssertEqual(lines.all.count, 1)
        let line = try XCTUnwrap(lines.all.first)
        XCTAssertFalse(line.contains("\n"), "one line")
        let digits = try NSRegularExpression(pattern: "\\d+(?:[.,]\\d+)?")
        let numbers = digits.matches(in: line, range: NSRange(line.startIndex..., in: line))
            .compactMap { Range($0.range, in: line).map { String(line[$0]) } }
        XCTAssertEqual(numbers.sorted(), ["1", "1", "1", "4"],
                       "the four counts (inserted 1, updated 1, unchanged 4, kept 1) and no other number, in: \(line)")
        let lowered = line.lowercased()
        for secret in Fx.everyId + Fx.markerKeys + ["fixture panel", "clear", "bodymeasurement", "bloodpanel", "manual", "lab-csv"] {
            XCTAssertFalse(lowered.contains(secret.lowercased()), "the line names \(secret): \(line)")
        }
        let units = try NSRegularExpression(pattern: "\\b(?:kg|cm|lb|mmol)\\b", options: [.caseInsensitive])
        XCTAssertEqual(units.numberOfMatches(in: line, range: NSRange(line.startIndex..., in: line)), 0,
                       "the line carries a unit: \(line)")
        let cells = try await Fx.labBookCells(store)
        XCTAssertEqual(cells, Fx.cells + [Fx.Cell(key: "weight", day: "2031-02-05", value: 97.5)])
    }

    // MARK: - §12.8 F26: the two confirmation dialogs (case 76)

    /// Both strap dialogs say that Lab Book readings are kept, after their existing sentence, which
    /// is not edited (§10.2, §11).
    func testBothStrapDialogsStateThatLabBookReadingsAreKept() throws {
        let devices = try code("Strand/Screens/DevicesView.swift")
        let kept = "\"Lab Book readings you entered are kept.\""
        let existing = [
            "Delete all of this device's data?":
                "This permanently deletes all data recorded from \\(device.displayName). This can't be undone.",
            "Forget this device?":
                "NOOP removes this device from your list and deletes its recorded data here. You can re-pair the strap to pull its recent history back.",
        ]
        XCTAssertEqual(occurrences(of: kept, in: devices), 2, "the sentence is on the two strap dialogs and nowhere else")
        for (title, sentence) in existing {
            let titleRange = try XCTUnwrap(devices.range(of: ".alert(\"\(title)\""), "the dialog \(title) was not found")
            let sentenceRange = try XCTUnwrap(devices.range(of: sentence, range: titleRange.upperBound..<devices.endIndex),
                                              "\(title): the existing sentence was edited or removed")
            XCTAssertEqual(occurrences(of: sentence, in: devices), 1, title)
            let window = devices[sentenceRange.upperBound...].prefix(400)
            let keptRange = try XCTUnwrap(window.range(of: kept), "\(title): the dialog does not say the readings are kept")
            let between = window[window.startIndex..<keptRange.lowerBound]
            XCTAssertFalse(between.contains(".alert("), "\(title): the sentence belongs to another dialog")
            XCTAssertFalse(between.contains("Button("), "\(title): the sentence is not in the dialog's message")
        }
    }
}
