import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

// Stage 1 (weigh-in and scorecard), ruling R36 of specification §18 (second review). Written before
// the fix, from the ruling, without reading the weigh-in store's implementation.
//
// The finding: ruling R34 checked the target instant of a date edit under the edited row's own
// device id only. The readers (the weigh-in list, the provider, and so the weekly series) take the
// union of ruling R25 and de-duplicate it by marker, instant and source. A date edit onto an instant
// that another unioned id already holds therefore leaves two stored rows of which the readers show
// one: a reading disappears from every screen without having been deleted.
//
// API ASSUMED BY THESE TESTS
//
//  1. `WeighInStore.edit(_:value:unitSystem:takenAt:)`: when the new instant (whole epoch seconds)
//     differs from the row's and another stored row of the same marker and source holds that instant
//     under ANY id of the R25 union (the active id, every other registered WHOOP, the canonical id),
//     the edit throws `WeighInError.instantOccupied` and writes nothing: no insert, no update, no
//     delete, and `interruptDateEditForTesting` is not reached.
//  2. The one exception: when the occupying row equals the replacement in every column except `id`
//     (`deviceId`, `markerKey`, `category`, `day`, `takenAt`, `value`, `valueText`, `unit`, `source`,
//     `note`, `referenceText`), the edit completes by deleting the old row and writing nothing new.
//     The row it returns is the occupying row as stored. The replacement is the edited row with the
//     new `takenAt`, the `day` of the new instant, the converted `value` and its unit, as assumed in
//     `WeighInStoreTests.swift` (assumption 6): `deviceId`, `category`, `valueText`, `source`, `note`
//     and `referenceText` are the edited row's. Superseded by ruling R42 and labbook-ownership.md
//     §7.4: the device id is not compared either. When every row at the target instant, under any
//     id, is a copy of the replacement, the edit completes; one row there that is not a copy refuses
//     it.
//  3. `WeighInStore.save(weight:waist:unitSystem:takenAt:)`: a manual row at the instant under the
//     ACTIVE id is updated as ruling R34 says, whatever the other ids hold. A manual row at the
//     instant held ONLY under another unioned id makes the save throw `.instantOccupied`.
//  4. A refused save writes nothing at all. Where the weight's instant is free and the waist's is
//     held under another unioned id, neither row is written: the check precedes every write, as the
//     range validation does (`WeighInStoreTests.swift`, assumption 4). This is this file's reading of
//     "writes nothing"; it is pinned by its own test so that a different decision fails one test.
//  5. Superseded by ruling R42 and labbook-ownership.md §7.4: there is no id outside the union. A
//     row under an unregistered id, or under an id registered to another brand, is listed like any
//     other, so it occupies its instant for an edit and for a save.
//  6. The rest of `WeighInStore`, `BodyMeasurementProvider` and `CutScorecard` as assumed at the top
//     of `WeighInStoreTests.swift` and `BodyMeasurementSingleSourceTests.swift`.
//
// Synthetic values only: the "Fixture Person" of specification §13. Lab Book rows only, so the fixed
// 2031 fixture applies (ruling R31).
@MainActor
final class WeighInCrossIdOccupancyTests: XCTestCase {

    // MARK: - Harness

    // Wednesdays at 07:00 UTC, as specification §13.1.
    private let week1 = Date(timeIntervalSince1970: 1_925_622_000)   // 2031-01-08
    private let week2 = Date(timeIntervalSince1970: 1_926_226_800)   // 2031-01-15
    private let week3 = Date(timeIntervalSince1970: 1_926_831_600)   // 2031-01-22
    private let week1Epoch = 1_925_622_000
    private let week2Epoch = 1_926_226_800
    private let week3Epoch = 1_926_831_600
    /// 2032-01-01 00:00 UTC: after every instant these tests save.
    private let later = Date(timeIntervalSince1970: 1_956_528_000)

    private let utc = TimeZone(identifier: "UTC")!
    private let categories = ["bloodPanel", "bloodPressure", "bodyMeasurement", "imaging", "appointmentNote", "other"]
    /// Every id a test may store a row under: the canonical id, two registered straps, an id nothing
    /// registered and another brand's id.
    private let allIds = ["my-whoop", "whoop-old", "whoop-new", "whoop-gone", "oura-ring"]

    private var suites: [String] = []

    override func tearDown() {
        for name in suites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        suites = []
        super.tearDown()
    }

    /// The canonical id is active, and `whoop-old` is a registered earlier strap: the union of
    /// ruling R25 is `my-whoop` and `whoop-old`.
    private func makeRepo(deviceId: String = "my-whoop") async throws -> (WhoopStore, Repository) {
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: deviceId)
        repo.setStoreForTesting(store)
        try register(store, "whoop-old", status: .archived)
        return (store, repo)
    }

    private func makeWeighIns(_ repo: Repository, provider: BodyMeasurementProvider? = nil) -> WeighInStore {
        let zone = utc
        let now = later
        return WeighInStore(repository: repo, provider: provider, timeZone: { zone }, now: { now })
    }

    private func flagOnProvider(_ repo: Repository, today: String) throws -> BodyMeasurementProvider {
        let name = "WeighInCrossIdOccupancyTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        suites.append(name)
        defaults.set(true, forKey: "noop.cutScorecardEnabled")
        return BodyMeasurementProvider(repository: repo, defaults: defaults, today: { today })
    }

    private func register(_ store: WhoopStore, _ id: String, brand: String = "WHOOP", status: DeviceStatus) throws {
        try DeviceRegistryStore(dbQueue: store.registryWriter).add(
            PairedDevice(id: id, brand: brand, model: "4.0", sourceKind: .liveBLE, capabilities: [.hr],
                         status: status, addedAt: 1, lastSeenAt: 1))
    }

    private func row(_ key: String = "weight", id: String, deviceId: String = "my-whoop",
                     category: String = "bodyMeasurement", day: String, takenAt: Int, value: Double,
                     valueText: String? = nil, unit: String = "kg", source: String = "manual",
                     note: String? = nil, referenceText: String? = nil) -> LabMarkerRow {
        LabMarkerRow(id: id, deviceId: deviceId, markerKey: key, category: category, day: day, takenAt: takenAt,
                     value: value, valueText: valueText, unit: unit, source: source, note: note,
                     referenceText: referenceText)
    }

    /// Every Lab Book row under every id these tests use, in a stable order.
    private func everything(_ store: WhoopStore) async throws -> [LabMarkerRow] {
        var all: [LabMarkerRow] = []
        for id in allIds {
            for category in categories {
                all += try await store.labMarkers(deviceId: id, category: category)
            }
        }
        return all.sorted { $0.id < $1.id }
    }

    private func stored(_ store: WhoopStore, id: String) async throws -> LabMarkerRow? {
        try await everything(store).first { $0.id == id }
    }

    /// Rows per device id, over every category.
    private func counts(_ store: WhoopStore) async throws -> [String: Int] {
        var out: [String: Int] = [:]
        for id in allIds {
            var n = 0
            for category in categories {
                n += try await store.labMarkers(deviceId: id, category: category).count
            }
            out[id] = n
        }
        return out
    }

    /// Column by column, so a failure names the column that changed. The twelve fields are the
    /// twelve columns of the `labMarker` table.
    private func assertSameColumns(_ actual: LabMarkerRow?, _ expected: LabMarkerRow, _ what: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        guard let actual else {
            XCTFail("\(what): the row \(expected.id) is no longer stored", file: file, line: line)
            return
        }
        XCTAssertEqual(actual.id, expected.id, "\(what): id", file: file, line: line)
        XCTAssertEqual(actual.deviceId, expected.deviceId, "\(what): deviceId", file: file, line: line)
        XCTAssertEqual(actual.markerKey, expected.markerKey, "\(what): markerKey", file: file, line: line)
        XCTAssertEqual(actual.category, expected.category, "\(what): category", file: file, line: line)
        XCTAssertEqual(actual.day, expected.day, "\(what): day", file: file, line: line)
        XCTAssertEqual(actual.takenAt, expected.takenAt, "\(what): takenAt", file: file, line: line)
        XCTAssertEqual(actual.value, expected.value, "\(what): value", file: file, line: line)
        XCTAssertEqual(actual.valueText, expected.valueText, "\(what): valueText", file: file, line: line)
        XCTAssertEqual(actual.unit, expected.unit, "\(what): unit", file: file, line: line)
        XCTAssertEqual(actual.source, expected.source, "\(what): source", file: file, line: line)
        XCTAssertEqual(actual.note, expected.note, "\(what): note", file: file, line: line)
        XCTAssertEqual(actual.referenceText, expected.referenceText, "\(what): referenceText", file: file, line: line)
        XCTAssertEqual(actual, expected, "\(what): the whole row", file: file, line: line)
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

    // MARK: - Date edit onto an instant held under another unioned id

    /// One weight under the active id, one under an earlier registered strap. Moving either onto the
    /// instant of the other is refused, and both rows are exactly as they were, column by column.
    func testDateEditOntoAnInstantHeldUnderAnotherUnionedIdThrowsAndWritesNothing() async throws {
        let (store, repo) = try await makeRepo()
        let mine = row(id: "weight-1925622000-0000AAAA", day: "2031-01-08", takenAt: week1Epoch, value: 100.0,
                       note: "first week", referenceText: "home scale")
        let other = row(id: "weight-1926226800-0000BBBB", deviceId: "whoop-old", day: "2031-01-15",
                        takenAt: week2Epoch, value: 99.2, note: "old strap", referenceText: "clinic scale")
        try await store.upsertLabMarkers([mine, other])
        let weighIns = makeWeighIns(repo)
        var seamFired = 0
        weighIns.interruptDateEditForTesting = { seamFired += 1 }
        let before = try await everything(store)
        let countsBefore = try await counts(store)
        XCTAssertEqual(before.count, 2)
        XCTAssertEqual(countsBefore["my-whoop"], 1)
        XCTAssertEqual(countsBefore["whoop-old"], 1)

        await assertThrows(.instantOccupied, "the active id's reading onto the earlier strap's instant") {
            try await weighIns.edit(mine, value: 99.6, unitSystem: .metric, takenAt: self.week2)
        }
        // The stored instant is whole seconds, so a fraction of a second later is the same instant.
        await assertThrows(.instantOccupied, "0.4 s after the earlier strap's instant") {
            try await weighIns.edit(mine, value: 99.6, unitSystem: .metric,
                                    takenAt: self.week2.addingTimeInterval(0.4))
        }
        // The other direction: the row under the earlier strap's id onto the active id's instant.
        await assertThrows(.instantOccupied, "the earlier strap's reading onto the active id's instant") {
            try await weighIns.edit(other, value: 99.2, unitSystem: .metric, takenAt: self.week1)
        }
        // The same value as the occupying row is still another reading: its note and its reference
        // text differ from the edited row's.
        await assertThrows(.instantOccupied, "with the occupying row's own value") {
            try await weighIns.edit(mine, value: 99.2, unitSystem: .metric, takenAt: self.week2)
        }

        XCTAssertEqual(seamFired, 0, "a refused date edit must not get as far as the insert")
        let mineAfter = try await stored(store, id: mine.id)
        let otherAfter = try await stored(store, id: other.id)
        assertSameColumns(mineAfter, mine, "the edited reading")
        assertSameColumns(otherAfter, other, "the reading whose instant was targeted")
        let after = try await everything(store)
        XCTAssertEqual(after, before, "a refused date edit added, removed or changed a row")
        let countsAfter = try await counts(store)
        XCTAssertEqual(countsAfter, countsBefore, "the row count under each id")
    }

    /// "Any unioned id": neither row is under the active id. One is under the canonical id, the other
    /// under an earlier registered strap, and a third strap is active.
    func testDateEditBetweenTwoUnionedIdsNeitherOfWhichIsActiveThrowsAndWritesNothing() async throws {
        let (store, repo) = try await makeRepo(deviceId: "whoop-new")
        try register(store, "whoop-new", status: .active)
        let canonical = row(id: "weight-1925622000-0000AAAA", day: "2031-01-08", takenAt: week1Epoch, value: 100.0,
                            note: "imported era")
        let old = row(id: "weight-1926226800-0000BBBB", deviceId: "whoop-old", day: "2031-01-15",
                      takenAt: week2Epoch, value: 99.2, referenceText: "clinic scale")
        let active = row(id: "weight-1926831600-0000CCCC", deviceId: "whoop-new", day: "2031-01-22",
                         takenAt: week3Epoch, value: 98.4)
        let waist = row("waist", id: "waist-1926226800-0000DDDD", deviceId: "whoop-old", day: "2031-01-15",
                        takenAt: week2Epoch, value: 99.5, unit: "cm")
        try await store.upsertLabMarkers([canonical, old, active, waist])
        let weighIns = makeWeighIns(repo)
        let before = try await everything(store)
        let countsBefore = try await counts(store)

        await assertThrows(.instantOccupied, "canonical onto the earlier strap's instant") {
            try await weighIns.edit(canonical, value: 100.0, unitSystem: .metric, takenAt: self.week2)
        }
        await assertThrows(.instantOccupied, "the earlier strap's onto the canonical instant") {
            try await weighIns.edit(old, value: 99.2, unitSystem: .metric, takenAt: self.week1)
        }
        await assertThrows(.instantOccupied, "the earlier strap's onto the active id's instant") {
            try await weighIns.edit(old, value: 99.2, unitSystem: .metric, takenAt: self.week3)
        }
        await assertThrows(.instantOccupied, "the active id's onto the canonical instant") {
            try await weighIns.edit(active, value: 98.4, unitSystem: .metric, takenAt: self.week1)
        }

        let after = try await everything(store)
        XCTAssertEqual(after, before)
        for expected in [canonical, old, active, waist] {
            let now = try await stored(store, id: expected.id)
            assertSameColumns(now, expected, "the row \(expected.id)")
        }
        let countsAfter = try await counts(store)
        XCTAssertEqual(countsAfter, countsBefore, "the row count under each id")

        // The occupancy is per marker: a waist may move onto an instant that only weights hold.
        let movedWaist = try await weighIns.edit(waist, value: 99.5, unitSystem: .metric, takenAt: week1)
        XCTAssertEqual(movedWaist.takenAt, week1Epoch)
        XCTAssertEqual(movedWaist.deviceId, "whoop-old")
    }

    /// What the refusal protects. After a refused cross-id date edit the weigh-in list, the provider's
    /// series, the resolver and the weekly points all still show both readings.
    func testAfterARefusedCrossIdEditTheListTheResolverAndTheWeeklySeriesStillShowBothReadings() async throws {
        let (store, repo) = try await makeRepo()
        let mine = row(id: "weight-1925622000-0000AAAA", day: "2031-01-08", takenAt: week1Epoch, value: 100.0)
        let other = row(id: "weight-1926226800-0000BBBB", deviceId: "whoop-old", day: "2031-01-15",
                        takenAt: week2Epoch, value: 99.2)
        try await store.upsertLabMarkers([mine, other])
        let provider = try flagOnProvider(repo, today: "2031-01-15")
        let weighIns = makeWeighIns(repo, provider: provider)

        await assertThrows(.instantOccupied) {
            try await weighIns.edit(mine, value: 99.6, unitSystem: .metric, takenAt: self.week2)
        }
        await assertThrows(.instantOccupied) {
            try await weighIns.edit(other, value: 99.0, unitSystem: .metric, takenAt: self.week1)
        }
        // Read the store as it now is, whether or not the refused edits triggered a refresh.
        await provider.refresh()

        let listed = await weighIns.readings(.weight)
        XCTAssertEqual(listed, [mine, other], "the weigh-in list: both readings, oldest first, unchanged")

        let series = provider.series(.weight, consumer: .display)
        XCTAssertEqual(series.map(\.day), ["2031-01-08", "2031-01-15"], "the provider's series")
        XCTAssertEqual(series.map(\.value), [100.0, 99.2])
        XCTAssertEqual(series.map(\.rowId), [mine.id, other.id])

        XCTAssertEqual(provider.resolve(.weight, asOf: "2031-01-08", consumer: .display),
                       ResolvedBodyMeasurement(kind: .weight, value: 100.0, source: .labBook, day: "2031-01-08"),
                       "the resolver as of week 1")
        XCTAssertEqual(provider.resolve(.weight, asOf: "2031-01-14", consumer: .display)?.value, 100.0,
                       "the week 1 reading still stands until week 2's")
        XCTAssertEqual(provider.resolve(.weight, asOf: "2031-01-15", consumer: .display),
                       ResolvedBodyMeasurement(kind: .weight, value: 99.2, source: .labBook, day: "2031-01-15"),
                       "the resolver as of week 2")
        XCTAssertEqual(provider.current(.weight, consumer: .estimate)?.value, 99.2)

        let input = CutScorecardInput(
            weights: series.map { CutScorecardReading(day: $0.day, takenAt: $0.takenAt ?? 0, value: $0.value) },
            waists: [], phase: nil, parameters: .generic, today: "2031-01-15")
        let result = CutScorecard.evaluate(input)
        XCTAssertEqual(result.weeks.compactMap(\.weightKg), [100.0, 99.2], "the weekly points: one per reading")
        XCTAssertEqual(result.currentWeightKg, 99.2)
    }

    // MARK: - Save onto an instant held under another unioned id

    /// A save writes under the active id. A manual row at its instant held only under another unioned
    /// id is refused: the list would otherwise show one of the two.
    func testSaveOntoAnInstantHeldOnlyUnderAnotherUnionedIdThrowsAndWritesNothing() async throws {
        let (store, repo) = try await makeRepo()
        let other = row(id: "weight-1925622000-0000BBBB", deviceId: "whoop-old", day: "2031-01-08",
                        takenAt: week1Epoch, value: 100.4, note: "old strap", referenceText: "clinic scale")
        let otherWaist = row("waist", id: "waist-1925622000-0000CCCC", deviceId: "whoop-old", day: "2031-01-08",
                             takenAt: week1Epoch, value: 100.0, unit: "cm", note: "at the navel")
        try await store.upsertLabMarkers([other, otherWaist])
        let weighIns = makeWeighIns(repo)
        let before = try await everything(store)
        let countsBefore = try await counts(store)

        await assertThrows(.instantOccupied, "a weight-only save") {
            try await weighIns.save(weight: 99.2, waist: nil, unitSystem: .metric, takenAt: self.week1)
        }
        await assertThrows(.instantOccupied, "a weight and waist save") {
            try await weighIns.save(weight: 99.2, waist: 96.0, unitSystem: .metric, takenAt: self.week1)
        }
        await assertThrows(.instantOccupied, "0.4 s into the same second, in pounds") {
            try await weighIns.save(weight: 218.0, waist: nil, unitSystem: .imperial,
                                    takenAt: self.week1.addingTimeInterval(0.4))
        }

        let after = try await everything(store)
        XCTAssertEqual(after, before, "a refused save added, removed or changed a row")
        let otherAfter = try await stored(store, id: other.id)
        let otherWaistAfter = try await stored(store, id: otherWaist.id)
        assertSameColumns(otherAfter, other, "the earlier strap's weight")
        assertSameColumns(otherWaistAfter, otherWaist, "the earlier strap's waist")
        let countsAfter = try await counts(store)
        XCTAssertEqual(countsAfter, countsBefore)
        XCTAssertEqual(countsAfter["my-whoop"], 0, "nothing was written under the active id")

        // The next free instant is unaffected.
        let saved = try await weighIns.save(weight: 99.2, waist: 96.0, unitSystem: .metric, takenAt: week2)
        XCTAssertEqual(saved.map(\.deviceId), ["my-whoop", "my-whoop"])
        XCTAssertEqual(saved.map(\.takenAt), [week2Epoch, week2Epoch])
    }

    /// Assumption 4 at the top of this file. The weight's instant is free and the waist's is held
    /// under another unioned id: the weigh-in is refused whole, as an out-of-range waist refuses it.
    func testSaveWhoseWaistInstantIsHeldUnderAnotherUnionedIdWritesNeitherRow() async throws {
        let (store, repo) = try await makeRepo()
        let otherWaist = row("waist", id: "waist-1925622000-0000CCCC", deviceId: "whoop-old", day: "2031-01-08",
                             takenAt: week1Epoch, value: 100.0, unit: "cm", note: "at the navel")
        try await store.upsertLabMarkers([otherWaist])
        let weighIns = makeWeighIns(repo)
        let before = try await everything(store)

        await assertThrows(.instantOccupied) {
            try await weighIns.save(weight: 99.2, waist: 96.0, unitSystem: .metric, takenAt: self.week1)
        }

        let after = try await everything(store)
        XCTAssertEqual(after, before, "the weight row must not be written when the waist is refused")
        let weights = try await store.labMarkers(deviceId: "my-whoop", markerKey: "weight")
        XCTAssertTrue(weights.isEmpty)

        // The waist was the obstacle, not the instant: a weight-only save there is free.
        let saved = try await weighIns.save(weight: 99.2, waist: nil, unitSystem: .metric, takenAt: week1)
        XCTAssertEqual(saved.map(\.markerKey), ["weight"])
        let waistAfter = try await stored(store, id: otherWaist.id)
        assertSameColumns(waistAfter, otherWaist, "the earlier strap's waist")
    }

    /// "A save keeps R34's behaviour for a row under the active id." Both the active id and another
    /// unioned id hold the instant (a duplicate across ids, which the readers already collapse onto
    /// the active copy): the save updates the active id's row, value and unit only.
    func testSaveOntoAnInstantHeldUnderTheActiveIdAndAnotherUnionedIdUpdatesTheActiveRowOnly() async throws {
        let (store, repo) = try await makeRepo()
        let mine = row(id: "weight-1925622000-0000AAAA", day: "2031-01-07", takenAt: week1Epoch, value: 220.5,
                       unit: "lb", note: "fasted", referenceText: "home scale")
        let other = row(id: "weight-1925622000-0000BBBB", deviceId: "whoop-old", day: "2031-01-08",
                        takenAt: week1Epoch, value: 100.4, note: "old strap")
        try await store.upsertLabMarkers([mine, other])
        let weighIns = makeWeighIns(repo)
        let countsBefore = try await counts(store)

        let saved = try await weighIns.save(weight: 99.2, waist: nil, unitSystem: .metric, takenAt: week1)

        var expected = mine
        expected.value = 99.2
        expected.unit = "kg"
        XCTAssertEqual(saved, [expected], "the returned row is the active id's row as stored")
        let mineAfter = try await stored(store, id: mine.id)
        let otherAfter = try await stored(store, id: other.id)
        assertSameColumns(mineAfter, expected, "the active id's row")
        assertSameColumns(otherAfter, other, "the earlier strap's row")
        let countsAfter = try await counts(store)
        XCTAssertEqual(countsAfter, countsBefore, "the save updated one row and added none")
    }

    // MARK: - An unregistered id and another brand's id

    /// Superseded by ruling R42 and labbook-ownership.md §7.4. A row at the target instant under an
    /// id nothing registered, or under another brand's id, is a listed reading, so it blocks a date
    /// edit and a save exactly as a row under a registered strap does. Before R42 this test
    /// (`testAnInstantHeldUnderAnIdOutsideTheUnionDoesNotBlockAnEditOrASave`) pinned the opposite.
    func testAnInstantHeldUnderAnUnregisteredOrOtherBrandIdBlocksAnEditAndASave() async throws {
        let (store, repo) = try await makeRepo()
        try register(store, "oura-ring", brand: "Oura", status: .paired)
        let mine = row(id: "weight-1925622000-0000AAAA", day: "2031-01-08", takenAt: week1Epoch, value: 100.0,
                       note: "first week", referenceText: "home scale")
        let unregistered = row(id: "weight-1926226800-0000BBBB", deviceId: "whoop-gone", day: "2031-01-15",
                               takenAt: week2Epoch, value: 99.2, note: "unknown strap")
        let otherBrand = row(id: "weight-1926226800-0000CCCC", deviceId: "oura-ring", day: "2031-01-15",
                             takenAt: week2Epoch, value: 99.3)
        let unregisteredLater = row(id: "weight-1926831600-0000DDDD", deviceId: "whoop-gone", day: "2031-01-22",
                                    takenAt: week3Epoch, value: 98.4)
        try await store.upsertLabMarkers([mine, unregistered, otherBrand, unregisteredLater])
        let weighIns = makeWeighIns(repo)
        var seamFired = 0
        weighIns.interruptDateEditForTesting = { seamFired += 1 }
        let before = try await everything(store)
        let countsBefore = try await counts(store)
        XCTAssertEqual(countsBefore, ["my-whoop": 1, "whoop-old": 0, "whoop-new": 0, "whoop-gone": 2, "oura-ring": 1])

        await assertThrows(.instantOccupied, "a date edit onto the instant the unregistered id and the ring hold") {
            try await weighIns.edit(mine, value: 99.6, unitSystem: .metric, takenAt: self.week2)
        }
        await assertThrows(.instantOccupied, "a date edit onto the instant only the unregistered id holds") {
            try await weighIns.edit(mine, value: 99.6, unitSystem: .metric, takenAt: self.week3)
        }
        await assertThrows(.instantOccupied, "a save onto the instant only the unregistered id holds") {
            try await weighIns.save(weight: 98.0, waist: nil, unitSystem: .metric, takenAt: self.week3)
        }
        await assertThrows(.instantOccupied, "a save onto the instant the ring holds") {
            try await weighIns.save(weight: 98.0, waist: nil, unitSystem: .metric, takenAt: self.week2)
        }

        XCTAssertEqual(seamFired, 0, "a refused date edit must not get as far as the insert")
        for expected in [mine, unregistered, otherBrand, unregisteredLater] {
            let now = try await stored(store, id: expected.id)
            assertSameColumns(now, expected, "the row \(expected.id)")
        }
        let after = try await everything(store)
        XCTAssertEqual(after, before, "a refused write added, removed or changed a row")
        let countsAfter = try await counts(store)
        XCTAssertEqual(countsAfter, countsBefore)
        let listed = await weighIns.readings(.weight)
        XCTAssertEqual(listed, [mine, unregistered, otherBrand, unregisteredLater],
                       "the list shows every reading, under whichever id it is stored")
    }

    // MARK: - The exception: completing an interrupted date edit

    private struct Interrupted: Error {}

    /// Interrupt a date edit between its insert and its delete, then retry the same edit. The retry
    /// finds its own replacement at the target instant and completes: one row, at the new instant,
    /// and none at the old one. Run for a row under the active id and for one under an earlier strap.
    func testRetryingAnInterruptedDateEditCompletesAndLeavesOneRow() async throws {
        for deviceId in ["my-whoop", "whoop-old"] {
            let (store, repo) = try await makeRepo()
            let original = row(id: "weight-1925622000-0000AAAA", deviceId: deviceId, day: "2031-01-08",
                               takenAt: week1Epoch, value: 100.0, note: "first week", referenceText: "home scale")
            // A bystander under the other unioned id, at an instant the edit does not touch.
            let bystanderId = deviceId == "my-whoop" ? "whoop-old" : "my-whoop"
            let bystander = row(id: "weight-1926831600-0000EEEE", deviceId: bystanderId, day: "2031-01-22",
                                takenAt: week3Epoch, value: 98.4, note: "bystander")
            try await store.upsertLabMarkers([original, bystander])
            let weighIns = makeWeighIns(repo)

            var seamFired = 0
            weighIns.interruptDateEditForTesting = {
                seamFired += 1
                throw Interrupted()
            }
            do {
                _ = try await weighIns.edit(original, value: 99.5, unitSystem: .metric, takenAt: week2)
                XCTFail("\(deviceId): the injected failure must surface to the caller")
            } catch is Interrupted {
                // expected
            } catch {
                XCTFail("\(deviceId): expected the injected failure, got \(error)")
            }
            XCTAssertEqual(seamFired, 1, "\(deviceId): the seam is reached exactly once")
            let interrupted = try await store.labMarkers(deviceId: deviceId, markerKey: "weight")
            XCTAssertEqual(interrupted.count, 2, "\(deviceId): the interruption leaves both rows")
            XCTAssertEqual(interrupted.first, original, "\(deviceId): the old row is intact")
            let inserted = try XCTUnwrap(interrupted.last)
            // The state the exception is defined on: the replacement, in every column except id.
            var replacement = original
            replacement.id = inserted.id
            replacement.takenAt = week2Epoch
            replacement.day = "2031-01-15"
            replacement.value = 99.5
            replacement.unit = "kg"
            assertSameColumns(inserted, replacement, "\(deviceId): the row the interrupted edit inserted")

            weighIns.interruptDateEditForTesting = nil
            let moved = try await weighIns.edit(original, value: 99.5, unitSystem: .metric, takenAt: week2)

            let afterRetry = try await store.labMarkers(deviceId: deviceId, markerKey: "weight")
            XCTAssertEqual(afterRetry.count, 1, "\(deviceId): exactly one row after the retry")
            XCTAssertEqual(afterRetry.first?.takenAt, week2Epoch, "\(deviceId): at the new instant")
            XCTAssertFalse(afterRetry.contains { $0.takenAt == week1Epoch }, "\(deviceId): no row at the old instant")
            let oldRow = try await stored(store, id: original.id)
            XCTAssertNil(oldRow, "\(deviceId): the old row was deleted")
            assertSameColumns(afterRetry.first, inserted,
                              "\(deviceId): the surviving row is the one already inserted; nothing new was written")
            XCTAssertEqual(moved, inserted, "\(deviceId): the returned row is the row as stored")
            let bystanderAfter = try await stored(store, id: bystander.id)
            assertSameColumns(bystanderAfter, bystander, "\(deviceId): the bystander")
            let countsAfter = try await counts(store)
            XCTAssertEqual(countsAfter[deviceId], 1, deviceId)
            XCTAssertEqual(countsAfter[bystanderId], 1, deviceId)
            let listed = await weighIns.readings(.weight)
            XCTAssertEqual(listed, [inserted, bystander], "\(deviceId): the list after the retry")
        }
    }

    /// The exception is for the SAME edit. After an interrupted date edit, a retry with another
    /// value finds a row that is not its replacement and is refused; both rows stay.
    func testRetryingAnInterruptedDateEditWithAnotherValueIsRefused() async throws {
        let (store, repo) = try await makeRepo()
        let weighIns = makeWeighIns(repo)
        let saved = try await weighIns.save(weight: 100.0, waist: nil, unitSystem: .metric, takenAt: week1)
        weighIns.interruptDateEditForTesting = { throw Interrupted() }
        do {
            _ = try await weighIns.edit(saved[0], value: 99.5, unitSystem: .metric, takenAt: week2)
            XCTFail("the injected failure must surface to the caller")
        } catch is Interrupted {
            // expected
        } catch {
            XCTFail("expected the injected failure, got \(error)")
        }
        weighIns.interruptDateEditForTesting = nil
        let before = try await everything(store)
        XCTAssertEqual(before.count, 2)

        await assertThrows(.instantOccupied, "a retry with 99.4 instead of 99.5") {
            try await weighIns.edit(saved[0], value: 99.4, unitSystem: .metric, takenAt: self.week2)
        }

        let after = try await everything(store)
        XCTAssertEqual(after, before, "a refused retry changes nothing")

        // The same edit still completes afterwards.
        let moved = try await weighIns.edit(saved[0], value: 99.5, unitSystem: .metric, takenAt: week2)
        let weights = try await store.labMarkers(deviceId: "my-whoop", markerKey: "weight")
        XCTAssertEqual(weights, [moved])
        XCTAssertEqual(moved.value, 99.5)
    }

    // MARK: - The exception after a zone change (ruling R39)

    /// The injected zone, switchable between the interrupted edit and its retry.
    private final class ZoneBox {
        var zone: TimeZone
        init(_ zone: TimeZone) { self.zone = zone }
    }

    /// 07:00 UTC on 2031-01-15 is 21:00 on 2031-01-14 in Honolulu (UTC-10, no daylight saving).
    private let honolulu = TimeZone(identifier: "Pacific/Honolulu")!

    /// A date edit of a week 1 weight onto week 2, interrupted after its insert while the injected
    /// zone is UTC; the injected zone is then switched to Honolulu, where the target instant falls on
    /// the previous local day. Returns the old row and the row the interrupted edit inserted.
    private func interruptedInUTCThenMovedToHonolulu() async throws
        -> (store: WhoopStore, weighIns: WeighInStore, original: LabMarkerRow, inserted: LabMarkerRow) {
        let (store, repo) = try await makeRepo()
        let original = row(id: "weight-1925622000-0000AAAA", day: "2031-01-08", takenAt: week1Epoch, value: 100.0,
                           note: "first week", referenceText: "home scale")
        try await store.upsertLabMarkers([original])
        let box = ZoneBox(utc)
        let now = later
        let weighIns = WeighInStore(repository: repo, provider: nil, timeZone: { box.zone }, now: { now })

        var seamFired = 0
        weighIns.interruptDateEditForTesting = {
            seamFired += 1
            throw Interrupted()
        }
        do {
            _ = try await weighIns.edit(original, value: 99.5, unitSystem: .metric, takenAt: week2)
            XCTFail("the injected failure must surface to the caller")
        } catch is Interrupted {
            // expected
        } catch {
            XCTFail("expected the injected failure, got \(error)")
        }
        weighIns.interruptDateEditForTesting = nil
        XCTAssertEqual(seamFired, 1, "the seam is reached exactly once")
        let interrupted = try await store.labMarkers(deviceId: "my-whoop", markerKey: "weight")
        XCTAssertEqual(interrupted.count, 2, "the interruption leaves both rows")
        XCTAssertEqual(interrupted.first, original, "the old row is intact")
        let inserted = try XCTUnwrap(interrupted.last)
        XCTAssertEqual(inserted.takenAt, week2Epoch)
        XCTAssertEqual(inserted.day, "2031-01-15", "the original write stored the day of the instant in UTC")

        box.zone = honolulu
        // The premise of the ruling: in the new zone the same instant is another local day.
        XCTAssertEqual(LocalDayWindows(timeZone: honolulu).dayKey(for: week2), "2031-01-14")
        return (store, weighIns, original, inserted)
    }

    /// Ruling R39: the stored day derives from the instant and the zone of the original write, so it
    /// is not compared. The same edit retried after the device changed zone still completes, and the
    /// surviving row keeps the day the original write stored.
    func testRetryingAnInterruptedDateEditAfterAZoneChangeCompletes() async throws {
        let (store, weighIns, original, inserted) = try await interruptedInUTCThenMovedToHonolulu()

        let moved = try await weighIns.edit(original, value: 99.5, unitSystem: .metric, takenAt: week2)

        let afterRetry = try await store.labMarkers(deviceId: "my-whoop", markerKey: "weight")
        XCTAssertEqual(afterRetry.count, 1, "exactly one row after the retry")
        XCTAssertEqual(afterRetry.first?.takenAt, week2Epoch, "at the new instant")
        XCTAssertFalse(afterRetry.contains { $0.takenAt == week1Epoch }, "no row at the old instant")
        let oldRow = try await stored(store, id: original.id)
        XCTAssertNil(oldRow, "the old row was deleted")
        XCTAssertEqual(afterRetry.first?.day, "2031-01-15", "the day stored by the original write is kept")
        assertSameColumns(afterRetry.first, inserted,
                          "the surviving row is the one already inserted; nothing new was written")
        XCTAssertEqual(moved, inserted, "the returned row is the row as stored")
        let all = try await everything(store)
        XCTAssertEqual(all, [inserted], "one row in the whole store")
    }

    /// Ruling R39 relaxes the day only. After the same zone change, a retry carrying another value
    /// is still refused, and both rows are byte-identical afterwards.
    func testRetryAfterAZoneChangeIsStillRefusedWhenAnotherColumnDiffers() async throws {
        let (store, weighIns, original, inserted) = try await interruptedInUTCThenMovedToHonolulu()
        var seamFired = 0
        weighIns.interruptDateEditForTesting = { seamFired += 1 }
        let before = try await everything(store)
        XCTAssertEqual(before.count, 2)

        await assertThrows(.instantOccupied, "a retry with 99.4 instead of 99.5, after the zone change") {
            try await weighIns.edit(original, value: 99.4, unitSystem: .metric, takenAt: self.week2)
        }

        XCTAssertEqual(seamFired, 0, "a refused retry must not reach the insert")
        let originalAfter = try await stored(store, id: original.id)
        let insertedAfter = try await stored(store, id: inserted.id)
        assertSameColumns(originalAfter, original, "the old row")
        assertSameColumns(insertedAfter, inserted, "the row the interrupted edit inserted")
        let after = try await everything(store)
        XCTAssertEqual(after, before, "a refused retry added, removed or changed a row")
    }

    // MARK: - The exception is exact

    /// The replacement of the edit below, in every column except `id`: the edited row with the new
    /// instant, its day, the new value and the stored unit.
    private func replacementOccupier(of edited: LabMarkerRow) -> LabMarkerRow {
        var occupier = edited
        occupier.id = "weight-1926226800-0000FFFF"
        occupier.takenAt = week2Epoch
        occupier.day = "2031-01-15"
        occupier.value = 99.5
        occupier.unit = "kg"
        return occupier
    }

    /// The control for the test below: an occupying row that equals the replacement in every column
    /// except `id` lets the edit complete, by deleting the old row and writing nothing new.
    func testEditOntoAnInstantWhoseRowEqualsTheReplacementCompletes() async throws {
        let (store, repo) = try await makeRepo()
        let edited = row(id: "weight-1925622000-0000AAAA", day: "2031-01-08", takenAt: week1Epoch, value: 100.0,
                         note: "first week", referenceText: "home scale")
        let occupier = replacementOccupier(of: edited)
        try await store.upsertLabMarkers([edited, occupier])
        let weighIns = makeWeighIns(repo)

        let moved = try await weighIns.edit(edited, value: 99.5, unitSystem: .metric, takenAt: week2)

        let all = try await everything(store)
        XCTAssertEqual(all, [occupier], "the old row is gone and the occupying row is byte-identical")
        XCTAssertEqual(moved, occupier, "the returned row is the row as stored")

        // Ruling R42 and labbook-ownership.md §7.4: the device id is not part of the comparison. The
        // same occupying row stored under another id is the same reading, so the edit completes the
        // same way. Before R42 this was a variant of the refusal test below.
        let (store2, repo2) = try await makeRepo()
        var elsewhere = occupier
        elsewhere.deviceId = "whoop-old"
        try await store2.upsertLabMarkers([edited, elsewhere])
        let weighIns2 = makeWeighIns(repo2)
        var seamFired = 0
        weighIns2.interruptDateEditForTesting = { seamFired += 1 }

        let moved2 = try await weighIns2.edit(edited, value: 99.5, unitSystem: .metric, takenAt: week2)

        XCTAssertEqual(seamFired, 0, "nothing new is written")
        let all2 = try await everything(store2)
        XCTAssertEqual(all2, [elsewhere], "the old row is gone and the row under the other id is byte-identical")
        XCTAssertEqual(moved2, elsewhere, "the returned row is the row as stored")
    }

    /// One content column of the occupying row differs from the replacement, one column at a time:
    /// every one of them is another reading, and the edit is refused with both rows untouched.
    func testEditOntoAnOccupiedInstantWhoseRowDiffersInAnySingleColumnStillThrows() async throws {
        let variants: [(column: String, change: (inout LabMarkerRow) -> Void)] = [
            ("value", { $0.value = 99.4 }),
            ("value (absent)", { $0.value = nil }),
            ("unit", { $0.unit = "lb" }),
            ("note", { $0.note = "after travel" }),
            ("note (absent)", { $0.note = nil }),
            ("referenceText", { $0.referenceText = "clinic scale" }),
            ("referenceText (absent)", { $0.referenceText = nil }),
            ("category", { $0.category = "other" }),
            // No "day" variant: ruling R39 leaves the stored day out of the comparison, because it
            // derives from the instant and the zone of the original write. The zone-change tests below
            // pin that case.
            ("valueText", { $0.valueText = "taken standing" }),
            // No "deviceId" variant: ruling R42 and labbook-ownership.md §7.4 leave the device id out
            // of the comparison too. The control test above pins that the edit then completes.
        ]
        for variant in variants {
            let (store, repo) = try await makeRepo()
            let edited = row(id: "weight-1925622000-0000AAAA", day: "2031-01-08", takenAt: week1Epoch, value: 100.0,
                             note: "first week", referenceText: "home scale")
            var occupier = replacementOccupier(of: edited)
            variant.change(&occupier)
            XCTAssertNotEqual(occupier, replacementOccupier(of: edited), "\(variant.column): the fixture differs")
            try await store.upsertLabMarkers([edited, occupier])
            let weighIns = makeWeighIns(repo)
            var seamFired = 0
            weighIns.interruptDateEditForTesting = { seamFired += 1 }
            let before = try await everything(store)
            XCTAssertEqual(before.count, 2, variant.column)
            let countsBefore = try await counts(store)

            await assertThrows(.instantOccupied, "the occupying row differs in \(variant.column)") {
                try await weighIns.edit(edited, value: 99.5, unitSystem: .metric, takenAt: self.week2)
            }

            XCTAssertEqual(seamFired, 0, "\(variant.column): a refused edit must not reach the insert")
            let editedAfter = try await stored(store, id: edited.id)
            let occupierAfter = try await stored(store, id: occupier.id)
            assertSameColumns(editedAfter, edited, "\(variant.column): the edited row")
            assertSameColumns(occupierAfter, occupier, "\(variant.column): the occupying row")
            let after = try await everything(store)
            XCTAssertEqual(after, before, "\(variant.column): a refused edit added, removed or changed a row")
            let countsAfter = try await counts(store)
            XCTAssertEqual(countsAfter, countsBefore, variant.column)
        }
    }
}
