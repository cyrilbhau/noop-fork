import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

// Stage 1 (weigh-in and scorecard), ruling R34 of specification §18. Written before the fix, from
// the ruling and from `LabMarkerStore.upsertLabMarkers`, without reading the weigh-in store's
// implementation.
//
// The finding: the Lab Book upsert is keyed on (deviceId, markerKey, takenAt, source) and, on a
// conflict, replaces category, day, value, valueText, unit, note and referenceText
// (`LabMarkerStore.swift:120-135`). So a write that lands on a stored row's natural key overwrites
// that row's other columns, and a date edit onto another reading's instant destroys that reading
// and then deletes the edited one.
//
// API ASSUMED BY THESE TESTS
//
//  1. `WeighInError` gains `case instantOccupied`.
//  2. `WeighInStore.edit(_:value:unitSystem:takenAt:)`: when the new instant (whole epoch seconds)
//     differs from the row's and another stored row has the same marker, source and device id at
//     that instant, the edit throws `.instantOccupied` and writes nothing: no insert, no update, no
//     delete, and `interruptDateEditForTesting` is not reached.
//  3. A row at that instant under ANOTHER device id, or from ANOTHER source, does not occupy it: the
//     date edit succeeds as specified in `WeighInStoreTests.swift` and leaves that row untouched.
//  4. `WeighInStore.save(weight:waist:unitSystem:takenAt:)`: when a manual row of the marker already
//     exists at the instant under the active device id, the save updates that row's `value` and
//     `unit` only. Its `id`, `category`, `day`, `valueText`, `note` and `referenceText` are kept, and
//     the returned row is the row as stored.
//  5. The rest of `WeighInStore` as assumed at the top of `WeighInStoreTests.swift`.
//
// Synthetic values only: the "Fixture Person" of specification §13. Lab Book rows only, so the
// fixed 2031 fixture applies (ruling R31).
@MainActor
final class WeighInOccupiedInstantTests: XCTestCase {

    // MARK: - Harness

    // Wednesdays at 07:00 UTC, as specification §13.1.
    private let week1 = Date(timeIntervalSince1970: 1_925_622_000)   // 2031-01-08
    private let week2 = Date(timeIntervalSince1970: 1_926_226_800)   // 2031-01-15
    private let week3 = Date(timeIntervalSince1970: 1_926_831_600)   // 2031-01-22
    private let week1Epoch = 1_925_622_000
    private let week2Epoch = 1_926_226_800
    /// 2032-01-01 00:00 UTC: after every instant these tests save.
    private let later = Date(timeIntervalSince1970: 1_956_528_000)

    private let utc = TimeZone(identifier: "UTC")!
    private let categories = ["bloodPanel", "bloodPressure", "bodyMeasurement", "imaging", "appointmentNote", "other"]

    private func makeRepo(deviceId: String = "my-whoop") async throws -> (WhoopStore, Repository) {
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: deviceId)
        repo.setStoreForTesting(store)
        return (store, repo)
    }

    private func makeWeighIns(_ repo: Repository) -> WeighInStore {
        let zone = utc
        let now = later
        return WeighInStore(repository: repo, provider: nil, timeZone: { zone }, now: { now })
    }

    private func register(_ store: WhoopStore, _ id: String, status: DeviceStatus) throws {
        try DeviceRegistryStore(dbQueue: store.registryWriter).add(
            PairedDevice(id: id, brand: "WHOOP", model: "4.0", sourceKind: .liveBLE, capabilities: [.hr],
                         status: status, addedAt: 1, lastSeenAt: 1))
    }

    private func row(_ key: String, id: String, deviceId: String = "my-whoop", category: String = "bodyMeasurement",
                     day: String, takenAt: Int, value: Double, valueText: String? = nil, unit: String,
                     source: String = "manual", note: String? = nil, referenceText: String? = nil) -> LabMarkerRow {
        LabMarkerRow(id: id, deviceId: deviceId, markerKey: key, category: category, day: day, takenAt: takenAt,
                     value: value, valueText: valueText, unit: unit, source: source, note: note,
                     referenceText: referenceText)
    }

    /// Every Lab Book row under the given ids, in a stable order.
    private func everything(_ store: WhoopStore, ids: [String] = ["my-whoop"]) async throws -> [LabMarkerRow] {
        var all: [LabMarkerRow] = []
        for id in ids {
            for category in categories {
                all += try await store.labMarkers(deviceId: id, category: category)
            }
        }
        return all.sorted { $0.id < $1.id }
    }

    private func stored(_ store: WhoopStore, id: String, ids: [String] = ["my-whoop"]) async throws -> LabMarkerRow? {
        try await everything(store, ids: ids).first { $0.id == id }
    }

    /// Column by column, so a failure names the column that changed. The twelve fields are the
    /// twelve columns of the `labMarker` table (`Database.swift:331-344`).
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

    private func isHex8(_ text: Substring) -> Bool {
        text.count == 8 && text.allSatisfy { $0.isHexDigit }
    }

    // MARK: - Date edit onto an occupied instant

    /// Two manual weights under one device id. Moving the first onto the instant of the second is
    /// refused, and both rows are exactly as they were, column by column.
    func testDateEditOntoAnInstantTakenBySameMarkerSourceAndDeviceThrowsAndWritesNothing() async throws {
        let (store, repo) = try await makeRepo()
        let first = row("weight", id: "weight-1925622000-0000AAAA", day: "2031-01-08", takenAt: week1Epoch,
                        value: 100.0, unit: "kg", note: "first week", referenceText: "home scale")
        let second = row("weight", id: "weight-1926226800-0000BBBB", day: "2031-01-15", takenAt: week2Epoch,
                         value: 99.2, unit: "kg", note: "after travel", referenceText: "clinic scale")
        let waist = row("waist", id: "waist-1926226800-0000CCCC", day: "2031-01-15", takenAt: week2Epoch,
                        value: 99.5, unit: "cm", note: "at the navel")
        try await store.upsertLabMarkers([first, second, waist])
        let weighIns = makeWeighIns(repo)
        var seamFired = 0
        weighIns.interruptDateEditForTesting = { seamFired += 1 }
        let before = try await everything(store)
        XCTAssertEqual(before.count, 3)

        await assertThrows(.instantOccupied, "moving the week 1 weight onto week 2") {
            try await weighIns.edit(first, value: 98.0, unitSystem: .metric, takenAt: self.week2)
        }
        // The stored instant is whole seconds, so a fraction of a second later is the same instant.
        await assertThrows(.instantOccupied, "moving it 0.4 s after the week 2 instant") {
            try await weighIns.edit(first, value: 98.0, unitSystem: .metric,
                                    takenAt: self.week2.addingTimeInterval(0.4))
        }
        // The other direction: the later reading moved onto the earlier one.
        await assertThrows(.instantOccupied, "moving the week 2 weight onto week 1") {
            try await weighIns.edit(second, value: 99.2, unitSystem: .imperial, takenAt: self.week1)
        }

        XCTAssertEqual(seamFired, 0, "a refused date edit must not get as far as the insert")
        let firstAfter = try await stored(store, id: first.id)
        let secondAfter = try await stored(store, id: second.id)
        let waistAfter = try await stored(store, id: waist.id)
        assertSameColumns(firstAfter, first, "the edited reading")
        assertSameColumns(secondAfter, second, "the reading whose instant was targeted")
        assertSameColumns(waistAfter, waist, "the waist at the targeted instant")
        let after = try await everything(store)
        XCTAssertEqual(after, before, "a refused date edit added, removed or changed a row")
        let listed = await weighIns.readings(.weight)
        XCTAssertEqual(listed, [first, second], "both readings are still listed")
    }

    /// The same for a waist, with rows the weigh-in flow itself wrote.
    func testDateEditOfAWaistOntoAnotherWaistThrowsAndWritesNothing() async throws {
        let (store, repo) = try await makeRepo()
        let weighIns = makeWeighIns(repo)
        let first = try await weighIns.save(weight: 100.0, waist: 100.0, unitSystem: .metric, takenAt: week1)
        let second = try await weighIns.save(weight: 99.2, waist: 99.5, unitSystem: .metric, takenAt: week2)
        let before = try await everything(store)
        XCTAssertEqual(before.count, 4)

        await assertThrows(.instantOccupied) {
            try await weighIns.edit(first[1], value: 98.0, unitSystem: .metric, takenAt: self.week2)
        }

        let firstAfter = try await stored(store, id: first[1].id)
        let secondAfter = try await stored(store, id: second[1].id)
        assertSameColumns(firstAfter, first[1], "the edited waist")
        assertSameColumns(secondAfter, second[1], "the waist whose instant was targeted")
        let after = try await everything(store)
        XCTAssertEqual(after, before)

        // The weight of the same weigh-in can still be moved to a free instant, and a value edit of
        // a row at its own instant is not "occupied" by itself.
        let moved = try await weighIns.edit(first[0], value: 100.0, unitSystem: .metric, takenAt: week3)
        XCTAssertEqual(moved.takenAt, 1_926_831_600)
        let edited = try await weighIns.edit(second[1], value: 99.0, unitSystem: .metric, takenAt: week2)
        XCTAssertEqual(edited.id, second[1].id)
        XCTAssertEqual(edited.value, 99.0)
    }

    // MARK: - Instants that are not occupied

    /// The natural key includes the device id. A reading at the target instant under another
    /// registered strap does not occupy it: the edit succeeds under the edited row's own id and the
    /// other strap's row is untouched.
    func testDateEditOntoAnInstantTakenOnlyUnderAnotherDeviceIdSucceeds() async throws {
        let (store, repo) = try await makeRepo()
        try register(store, "whoop-old", status: .archived)
        let ids = ["my-whoop", "whoop-old"]
        let mine = row("weight", id: "weight-1925622000-0000AAAA", day: "2031-01-08", takenAt: week1Epoch,
                       value: 100.0, unit: "kg", note: "first week", referenceText: "home scale")
        let other = row("weight", id: "weight-1926226800-0000BBBB", deviceId: "whoop-old", day: "2031-01-15",
                        takenAt: week2Epoch, value: 99.2, unit: "kg", note: "old strap", referenceText: "ref")
        try await store.upsertLabMarkers([mine, other])
        let weighIns = makeWeighIns(repo)

        let moved = try await weighIns.edit(mine, value: 99.6, unitSystem: .metric, takenAt: week2)

        XCTAssertEqual(moved.deviceId, "my-whoop")
        XCTAssertEqual(moved.takenAt, week2Epoch)
        XCTAssertEqual(moved.day, "2031-01-15")
        XCTAssertEqual(moved.value, 99.6)
        XCTAssertEqual(moved.source, "manual")
        XCTAssertNotEqual(moved.id, mine.id)
        XCTAssertNotEqual(moved.id, other.id)
        let otherAfter = try await stored(store, id: other.id, ids: ids)
        assertSameColumns(otherAfter, other, "the other strap's reading")
        let mineRows = try await store.labMarkers(deviceId: "my-whoop", markerKey: "weight")
        XCTAssertEqual(mineRows, [moved], "one reading under the edited row's id, at the new instant")
        let otherRows = try await store.labMarkers(deviceId: "whoop-old", markerKey: "weight")
        XCTAssertEqual(otherRows, [other])
    }

    /// The natural key includes the source. An imported reading at the target instant does not
    /// occupy it for a manual one.
    func testDateEditOntoAnInstantTakenOnlyByAnotherSourceSucceeds() async throws {
        let (store, repo) = try await makeRepo()
        let manual = row("weight", id: "weight-1925622000-0000AAAA", day: "2031-01-08", takenAt: week1Epoch,
                         value: 100.0, unit: "kg")
        let imported = row("weight", id: "weight-csv-1", day: "2031-01-15", takenAt: week2Epoch, value: 218.5,
                           unit: "lb", source: "csv", note: "imported", referenceText: "ref")
        try await store.upsertLabMarkers([manual, imported])
        let weighIns = makeWeighIns(repo)

        let moved = try await weighIns.edit(manual, value: 99.6, unitSystem: .metric, takenAt: week2)

        XCTAssertEqual(moved.takenAt, week2Epoch)
        XCTAssertEqual(moved.source, "manual")
        XCTAssertEqual(moved.value, 99.6)
        XCTAssertNotEqual(moved.id, imported.id)
        let importedAfter = try await stored(store, id: imported.id)
        assertSameColumns(importedAfter, imported, "the imported reading")
        let all = try await store.labMarkers(deviceId: "my-whoop", markerKey: "weight")
        XCTAssertEqual(all.sorted { $0.id < $1.id }, [moved, imported].sorted { $0.id < $1.id },
                       "the moved manual reading and the imported one, and no trace of the old instant")
    }

    // MARK: - Save onto an existing row

    /// A weigh-in saved at the instant of manual Lab Book rows that carry a note, a reference text,
    /// a day from another zone and (for the waist) another category: value and unit change, nothing
    /// else does.
    func testSaveOntoAnExistingManualLabBookRowUpdatesValueAndUnitOnly() async throws {
        let (store, repo) = try await makeRepo()
        // Entered in the Lab Book editor in pounds and inches, in a zone where the instant was still
        // the 7th.
        let weight = row("weight", id: "weight-1925622000-0000AAAA", day: "2031-01-07", takenAt: week1Epoch,
                         value: 220.5, unit: "lb", note: "fasted, before breakfast", referenceText: "clinic scale")
        let waist = row("waist", id: "waist-1925622000-0000BBBB", category: "other", day: "2031-01-07",
                        takenAt: week1Epoch, value: 38.0, valueText: "taken standing", unit: "in",
                        note: "at the navel", referenceText: "tape")
        try await store.upsertLabMarkers([weight, waist])
        let weighIns = makeWeighIns(repo)

        let saved = try await weighIns.save(weight: 99.2, waist: 96.0, unitSystem: .metric, takenAt: week1)

        var expectedWeight = weight
        expectedWeight.value = 99.2
        expectedWeight.unit = "kg"
        var expectedWaist = waist
        expectedWaist.value = 96.0
        expectedWaist.unit = "cm"
        let weightAfter = try await stored(store, id: weight.id)
        let waistAfter = try await stored(store, id: waist.id)
        assertSameColumns(weightAfter, expectedWeight, "the weight row")
        assertSameColumns(waistAfter, expectedWaist, "the waist row")
        let all = try await everything(store)
        XCTAssertEqual(all.count, 2, "the save updated the two stored rows and added none")
        XCTAssertEqual(saved, [expectedWeight, expectedWaist], "the returned rows are the rows as stored, weight first")

        // In pounds and inches: converted, and still only value and unit.
        let imperial = try await weighIns.save(weight: 218.0, waist: 37.5, unitSystem: .imperial, takenAt: week1)
        expectedWeight.value = 218.0 / UnitFormatter.poundsPerKilogram
        expectedWaist.value = 37.5 * UnitFormatter.centimetersPerInch
        let weightAgain = try await stored(store, id: weight.id)
        let waistAgain = try await stored(store, id: waist.id)
        assertSameColumns(weightAgain, expectedWeight, "the weight row after an imperial save")
        assertSameColumns(waistAgain, expectedWaist, "the waist row after an imperial save")
        XCTAssertEqual(imperial, [expectedWeight, expectedWaist])
    }

    /// A weight-only save onto the same instant leaves the waist row at that instant alone.
    func testSaveOfAWeightOnlyOntoAnExistingInstantLeavesTheWaistRowAlone() async throws {
        let (store, repo) = try await makeRepo()
        let weight = row("weight", id: "weight-1925622000-0000AAAA", day: "2031-01-07", takenAt: week1Epoch,
                         value: 100.0, unit: "kg", note: "fasted", referenceText: "clinic scale")
        let waist = row("waist", id: "waist-1925622000-0000BBBB", day: "2031-01-07", takenAt: week1Epoch,
                        value: 100.0, unit: "cm", note: "at the navel", referenceText: "tape")
        try await store.upsertLabMarkers([weight, waist])
        let weighIns = makeWeighIns(repo)

        try await weighIns.save(weight: 99.2, waist: nil, unitSystem: .metric, takenAt: week1)

        var expectedWeight = weight
        expectedWeight.value = 99.2
        let weightAfter = try await stored(store, id: weight.id)
        let waistAfter = try await stored(store, id: waist.id)
        assertSameColumns(weightAfter, expectedWeight, "the weight row")
        assertSameColumns(waistAfter, waist, "the waist row")
    }

    /// A row of another source, or under another device id, at the save's instant is not the row the
    /// save lands on: it is untouched and the save writes its own manual row.
    func testSaveAtAnInstantTakenByAnotherSourceOrDeviceWritesItsOwnRow() async throws {
        let (store, repo) = try await makeRepo()
        try register(store, "whoop-old", status: .archived)
        let ids = ["my-whoop", "whoop-old"]
        let imported = row("weight", id: "weight-csv-1", day: "2031-01-08", takenAt: week1Epoch, value: 220.5,
                           unit: "lb", source: "csv", note: "imported", referenceText: "ref")
        let other = row("weight", id: "weight-1925622000-0000BBBB", deviceId: "whoop-old", day: "2031-01-08",
                        takenAt: week1Epoch, value: 100.4, unit: "kg", note: "old strap")
        try await store.upsertLabMarkers([imported, other])
        let weighIns = makeWeighIns(repo)

        let saved = try await weighIns.save(weight: 99.2, waist: nil, unitSystem: .metric, takenAt: week1)

        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.deviceId, "my-whoop")
        XCTAssertEqual(saved.first?.source, "manual")
        XCTAssertNotEqual(saved.first?.id, imported.id)
        XCTAssertNotEqual(saved.first?.id, other.id)
        let importedAfter = try await stored(store, id: imported.id, ids: ids)
        let otherAfter = try await stored(store, id: other.id, ids: ids)
        assertSameColumns(importedAfter, imported, "the imported reading")
        assertSameColumns(otherAfter, other, "the other strap's reading")
        let all = try await everything(store, ids: ids)
        XCTAssertEqual(all.count, 3)
    }

    // MARK: - A free instant

    /// A save at an instant nothing holds is as before: a new manual row with a fresh id, no note
    /// and no reference text, and the rows already stored are untouched.
    func testSaveAtAFreeInstantIsUnaffected() async throws {
        let (store, repo) = try await makeRepo()
        let weight = row("weight", id: "weight-1925622000-0000AAAA", day: "2031-01-07", takenAt: week1Epoch,
                         value: 220.5, unit: "lb", note: "fasted, before breakfast", referenceText: "clinic scale")
        let waist = row("waist", id: "waist-1925622000-0000BBBB", category: "other", day: "2031-01-07",
                        takenAt: week1Epoch, value: 38.0, unit: "in", note: "at the navel", referenceText: "tape")
        try await store.upsertLabMarkers([weight, waist])
        let weighIns = makeWeighIns(repo)

        let saved = try await weighIns.save(weight: 99.2, waist: 96.0, unitSystem: .metric, takenAt: week2)

        XCTAssertEqual(saved.map(\.markerKey), ["weight", "waist"])
        let expectedValue = ["weight": 99.2, "waist": 96.0]
        let expectedUnit = ["weight": "kg", "waist": "cm"]
        for new in saved {
            let key = new.markerKey
            let prefix = "\(key)-1926226800-"
            XCTAssertTrue(new.id.hasPrefix(prefix), "\(key): id \(new.id)")
            XCTAssertTrue(isHex8(new.id.dropFirst(prefix.count)), "\(key): id \(new.id)")
            XCTAssertEqual(new.deviceId, "my-whoop", key)
            XCTAssertEqual(new.category, "bodyMeasurement", key)
            XCTAssertEqual(new.day, "2031-01-15", key)
            XCTAssertEqual(new.takenAt, week2Epoch, key)
            XCTAssertEqual(new.value, expectedValue[key], key)
            XCTAssertEqual(new.unit, expectedUnit[key], key)
            XCTAssertEqual(new.source, "manual", key)
            XCTAssertNil(new.valueText, key)
            XCTAssertNil(new.note, key)
            XCTAssertNil(new.referenceText, key)
        }
        let weightAfter = try await stored(store, id: weight.id)
        let waistAfter = try await stored(store, id: waist.id)
        assertSameColumns(weightAfter, weight, "the earlier weight")
        assertSameColumns(waistAfter, waist, "the earlier waist")
        let all = try await everything(store)
        XCTAssertEqual(all.count, 4)

        // A date edit to a free instant is unaffected too.
        var seamFired = 0
        weighIns.interruptDateEditForTesting = { seamFired += 1 }
        let moved = try await weighIns.edit(saved[0], value: 99.2, unitSystem: .metric, takenAt: week3)
        XCTAssertEqual(seamFired, 1)
        XCTAssertEqual(moved.takenAt, 1_926_831_600)
        XCTAssertEqual(moved.day, "2031-01-22")
        let weights = try await store.labMarkers(deviceId: "my-whoop", markerKey: "weight")
        XCTAssertEqual(weights, [weight, moved])
    }
}
