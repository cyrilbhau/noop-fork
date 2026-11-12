import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

// Stage 1 (weigh-in and scorecard), specification §9.1, §10.3 (ranges), §12.3, fault line F27 and
// ruling R25. Written before the implementation exists, from the specification.
//
// API ASSUMED BY THESE TESTS
//
//     enum WeighInError: Error, Equatable {
//         case weightOutOfRange       // not finite, or outside 30...250 kg after conversion
//         case waistOutOfRange        // not finite, or outside 40...200 cm after conversion
//         case futureInstant          // takenAt is after now()
//         case notABodyMeasurement    // edit or delete of a row whose marker is not weight or waist
//         case readingNotFound        // edit or delete of a row that is no longer stored
//         case storeUnavailable       // repository.storeHandle() returned nil
//     }
//
//     @MainActor final class WeighInStore {
//         static let weightRangeKg: ClosedRange<Double>    // 30...250 (specification §10.3)
//         static let waistRangeCm: ClosedRange<Double>     // 40...200
//
//         init(repository: Repository, provider: BodyMeasurementProvider? = nil,
//              timeZone: @escaping () -> TimeZone = { TimeZone.current },
//              now: @escaping () -> Date = { Date() })
//
//         /// One weigh-in: a weight row, and a waist row unless `waist` is nil. Returns the rows as
//         /// stored, weight first.
//         @discardableResult
//         func save(weight: Double, waist: Double?, unitSystem: UnitSystem, takenAt: Date) async throws -> [LabMarkerRow]
//
//         /// Edit one stored reading. Same instant: the value is updated in place. Another instant:
//         /// a new row is inserted, then the old one deleted. Returns the row as stored afterwards.
//         @discardableResult
//         func edit(_ row: LabMarkerRow, value: Double, unitSystem: UnitSystem, takenAt: Date) async throws -> LabMarkerRow
//
//         func delete(_ row: LabMarkerRow) async throws
//
//         /// Every weight (or waist) Lab Book row under every device id present in `labMarker`
//         /// (ruling R42, labbook-ownership.md §6.2), a set of copies listed once, oldest first.
//         func readings(_ kind: BodyMeasurementKind) async -> [LabMarkerRow]
//
//         /// Test seam (may be DEBUG-only). Called during a date edit after the new row is inserted
//         /// and before the old row is deleted. Throwing from it aborts the edit at that point.
//         var interruptDateEditForTesting: (() throws -> Void)?
//     }
//
// Behaviour assumed where specification §9.1 and ruling R25 leave it unstated:
//
//  1. `unitSystem` is the app's existing `UnitSystem` (`Units.swift:16`): `.metric` means the numbers
//     are kilograms and centimetres, `.imperial` pounds and inches. Stored values are always
//     kilograms and centimetres with unit `kg` or `cm`, unrounded.
//  2. `takenAt` is stored as `Int(takenAt.timeIntervalSince1970)`, as the Lab Book editor does.
//  3. `repository.deviceId` and `timeZone()` are read when a write happens, not captured at `init`.
//  4. Validation happens before any write. A weigh-in with a valid weight and an invalid waist writes
//     NEITHER row. The ranges are inclusive and are applied to the converted value.
//  5. A value edit keeps the row's `id`, `deviceId`, `takenAt`, `source`, `category`, `note`,
//     `referenceText` and stored `day`; only `value` and `unit` change.
//  6. A date edit writes the new row under the SAME device id as the row it replaces (so no reading
//     changes id by being edited), with a fresh id and the `day` of the new instant in `timeZone()`,
//     and keeps the old row's `source`, `note` and `referenceText`.
//  7. `readings` returns rows under EVERY device id present in `labMarker`, registered or not, any
//     brand (ruling R42 and labbook-ownership.md, which supersede the union of R25 and R29). Rows
//     equal in every column except `id`, `deviceId` and `day` are one reading, listed once with the
//     active id's row standing for it; rows at one instant that differ in content are both listed.
//     Reading never writes to, re-keys or removes a row.
//  8. After every successful write the store calls `repository.refresh()` and then
//     `provider?.refresh()`.
//
// Synthetic values only: the "Fixture Person" of specification §13.
@MainActor
final class WeighInStoreTests: XCTestCase {

    // MARK: - Harness

    // Wednesdays at 07:00 UTC, as specification §13.1.
    private let week1 = Date(timeIntervalSince1970: 1_925_622_000)   // 2031-01-08
    private let week2 = Date(timeIntervalSince1970: 1_926_226_800)   // 2031-01-15
    private let week3 = Date(timeIntervalSince1970: 1_926_831_600)   // 2031-01-22
    /// 2032-01-01 00:00 UTC: after every instant these tests save.
    private let later = Date(timeIntervalSince1970: 1_956_528_000)

    private let utc = TimeZone(identifier: "UTC")!
    private let bodyCategories = ["bloodPanel", "bloodPressure", "bodyMeasurement", "imaging", "appointmentNote", "other"]

    /// A zone that tests can change between two writes.
    private final class Zone {
        var current: TimeZone
        init(_ identifier: String) { current = TimeZone(identifier: identifier)! }
    }

    private var suites: [String] = []

    override func tearDown() {
        for name in suites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        suites = []
        super.tearDown()
    }

    private func makeRepo(deviceId: String = "my-whoop") async throws -> (WhoopStore, Repository) {
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: deviceId)
        repo.setStoreForTesting(store)
        return (store, repo)
    }

    private func makeWeighIns(_ repo: Repository, zone: TimeZone? = nil, now: Date? = nil,
                              provider: BodyMeasurementProvider? = nil) -> WeighInStore {
        let zone = zone ?? utc
        let now = now ?? later
        return WeighInStore(repository: repo, provider: provider, timeZone: { zone }, now: { now })
    }

    private func flagOnProvider(_ repo: Repository, today: String) throws -> BodyMeasurementProvider {
        let name = "WeighInStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        suites.append(name)
        defaults.set(true, forKey: "noop.cutScorecardEnabled")
        return BodyMeasurementProvider(repository: repo, defaults: defaults, today: { today })
    }

    private func rows(_ store: WhoopStore, _ key: String, deviceId: String = "my-whoop") async throws -> [LabMarkerRow] {
        try await store.labMarkers(deviceId: deviceId, markerKey: key)
    }

    /// Every Lab Book row under the given ids, in a stable order.
    private func everything(_ store: WhoopStore, ids: [String]) async throws -> [LabMarkerRow] {
        var all: [LabMarkerRow] = []
        for id in ids {
            for category in bodyCategories {
                all += try await store.labMarkers(deviceId: id, category: category)
            }
        }
        return all.sorted { $0.id < $1.id }
    }

    private func counts(_ store: WhoopStore, ids: [String]) async throws -> [String: Int] {
        var out: [String: Int] = [:]
        for id in ids {
            var n = 0
            for category in bodyCategories {
                n += try await store.labMarkers(deviceId: id, category: category).count
            }
            out[id] = n
        }
        return out
    }

    private func register(_ store: WhoopStore, _ id: String, brand: String = "WHOOP", status: DeviceStatus) throws {
        try DeviceRegistryStore(dbQueue: store.registryWriter).add(
            PairedDevice(id: id, brand: brand, model: "4.0", sourceKind: .liveBLE, capabilities: [.hr],
                         status: status, addedAt: 1, lastSeenAt: 1))
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

    // MARK: - §9.1 save

    /// The exact columns of the table in §9.1, for the weight row and the waist row.
    func testSaveWritesManualBodyMeasurementRows() async throws {
        let (store, repo) = try await makeRepo()
        let weighIns = makeWeighIns(repo)

        let saved = try await weighIns.save(weight: 99.9537, waist: 96.25, unitSystem: .metric, takenAt: week1)

        let weights = try await rows(store, "weight")
        let waists = try await rows(store, "waist")
        XCTAssertEqual(weights.count, 1)
        XCTAssertEqual(waists.count, 1)
        XCTAssertEqual(saved, weights + waists, "the returned rows are the stored rows, weight first")

        let expectedUnit = ["weight": "kg", "waist": "cm"]
        let expectedValue = ["weight": 99.9537, "waist": 96.25]
        for row in weights + waists {
            let key = row.markerKey
            XCTAssertEqual(row.deviceId, "my-whoop", "\(key): the id Lab Book writes under")
            XCTAssertEqual(row.category, "bodyMeasurement", key)
            XCTAssertEqual(row.takenAt, 1_925_622_000, "\(key): the actual instant, epoch seconds")
            XCTAssertEqual(row.day, "2031-01-08", key)
            XCTAssertEqual(row.value, expectedValue[key], "\(key): unrounded")
            XCTAssertEqual(row.unit, expectedUnit[key], key)
            XCTAssertEqual(row.source, "manual", key)
            XCTAssertNil(row.valueText, key)
            XCTAssertNil(row.note, key)
            XCTAssertNil(row.referenceText, key)

            // "<markerKey>-<takenAt>-<8 hex>", the form the Lab Book editor uses.
            let prefix = "\(key)-1925622000-"
            XCTAssertTrue(row.id.hasPrefix(prefix), "\(key): id \(row.id)")
            XCTAssertTrue(isHex8(row.id.dropFirst(prefix.count)), "\(key): id \(row.id) must end in 8 hex digits")
        }
        XCTAssertNotEqual(weights[0].id, waists[0].id)
    }

    func testPoundsInKilogramsStored() async throws {
        let (store, repo) = try await makeRepo()
        let weighIns = makeWeighIns(repo)

        try await weighIns.save(weight: 220.462, waist: nil, unitSystem: .imperial, takenAt: week1)

        let rowRows = try await rows(store, "weight")
        let row = try XCTUnwrap(rowRows.first)
        XCTAssertEqual(try XCTUnwrap(row.value), 220.462 / UnitFormatter.poundsPerKilogram, accuracy: 1e-9,
                       "converted with the app's own constant, not rounded")
        XCTAssertEqual(try XCTUnwrap(row.value), 100.0, accuracy: 1e-3)
        XCTAssertEqual(row.unit, "kg", "the stored unit is the stored value's unit")
    }

    func testInchesInCentimetresStored() async throws {
        let (store, repo) = try await makeRepo()
        let weighIns = makeWeighIns(repo)

        try await weighIns.save(weight: 220.462, waist: 37.5, unitSystem: .imperial, takenAt: week1)

        let rowRows = try await rows(store, "waist")
        let row = try XCTUnwrap(rowRows.first)
        XCTAssertEqual(try XCTUnwrap(row.value), 37.5 * UnitFormatter.centimetersPerInch, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(row.value), 95.25, accuracy: 1e-9)
        XCTAssertEqual(row.unit, "cm")
    }

    /// "Skip" on the waist step: the waist was not taken. No waist row exists, least of all a zero one.
    func testSkippedWaistWritesNoWaistRow() async throws {
        let (store, repo) = try await makeRepo()
        let weighIns = makeWeighIns(repo)

        let saved = try await weighIns.save(weight: 100.0, waist: nil, unitSystem: .metric, takenAt: week1)

        XCTAssertEqual(saved.map(\.markerKey), ["weight"])
        let waists = try await rows(store, "waist")
        XCTAssertTrue(waists.isEmpty, "a skipped waist is 'not taken', never a row")
        let all = try await everything(store, ids: ["my-whoop"])
        XCTAssertEqual(all.count, 1)
        XCTAssertFalse(all.contains { $0.value == 0 || $0.value == nil })
        let listed = await weighIns.readings(.waist)
        XCTAssertTrue(listed.isEmpty)
    }

    /// §9.1: "Two saves in the same second for the same marker update one row."
    func testSecondSaveInTheSameSecondUpdatesTheSameRows() async throws {
        let (store, repo) = try await makeRepo()
        let weighIns = makeWeighIns(repo)

        let first = try await weighIns.save(weight: 100.0, waist: 100.0, unitSystem: .metric, takenAt: week1)
        let second = try await weighIns.save(weight: 99.8, waist: 99.5, unitSystem: .metric,
                                             takenAt: week1.addingTimeInterval(0.4))

        let weights = try await rows(store, "weight")
        let waists = try await rows(store, "waist")
        XCTAssertEqual(weights.map(\.value), [99.8])
        XCTAssertEqual(waists.map(\.value), [99.5])
        XCTAssertEqual(second, weights + waists, "the returned rows are the rows as stored")
        XCTAssertEqual(weights.first?.id, first.first?.id, "the stored row keeps its id, so the list's handle stays valid")
    }

    /// §9.1: "A second weigh-in on another instant is a second row."
    func testSecondWeighInAtAnotherInstantIsASecondRow() async throws {
        let (store, repo) = try await makeRepo()
        let weighIns = makeWeighIns(repo)

        try await weighIns.save(weight: 100.4, waist: nil, unitSystem: .metric, takenAt: week1)
        try await weighIns.save(weight: 100.0, waist: nil, unitSystem: .metric, takenAt: week1.addingTimeInterval(3_600))

        let weights = try await rows(store, "weight")
        XCTAssertEqual(weights.map(\.value), [100.4, 100.0], "both are kept, oldest first")
        XCTAssertEqual(weights.map(\.day), ["2031-01-08", "2031-01-08"])
    }

    // MARK: - §9.1 day

    func testDayIsTheLocalDayOfTheInstantInTheGivenZone() async throws {
        // 2031-01-08 20:30 UTC: the 9th in Kolkata, the 8th in UTC and in Los Angeles.
        let instant = Date(timeIntervalSince1970: 1_925_670_600)
        for (identifier, expected) in [("Asia/Kolkata", "2031-01-09"), ("UTC", "2031-01-08"),
                                       ("America/Los_Angeles", "2031-01-08"), ("Pacific/Kiritimati", "2031-01-09")] {
            let (store, repo) = try await makeRepo()
            let zone = try XCTUnwrap(TimeZone(identifier: identifier))
            let weighIns = makeWeighIns(repo, zone: zone)
            try await weighIns.save(weight: 100.0, waist: 100.0, unitSystem: .metric, takenAt: instant)

            let weightRows = try await rows(store, "weight")
            let weight = try XCTUnwrap(weightRows.first)
            let waistRows = try await rows(store, "waist")
            let waist = try XCTUnwrap(waistRows.first)
            XCTAssertEqual(weight.day, expected, identifier)
            XCTAssertEqual(waist.day, expected, "\(identifier): one date for both")
            XCTAssertEqual(weight.day, LocalDayWindows(timeZone: zone).dayKey(for: instant), identifier)
            XCTAssertEqual(weight.takenAt, 1_925_670_600, "\(identifier): the instant is the same in every zone")
        }
    }

    func testReadingAt2359And0001LandOnDifferentDays() async throws {
        let (store, repo) = try await makeRepo()
        let kolkata = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
        let weighIns = makeWeighIns(repo, zone: kolkata)
        let before = Date(timeIntervalSince1970: 1_925_663_340)   // 2031-01-08 23:59 in Kolkata
        let after = Date(timeIntervalSince1970: 1_925_663_460)    // 2031-01-09 00:01 in Kolkata

        try await weighIns.save(weight: 100.0, waist: nil, unitSystem: .metric, takenAt: before)
        try await weighIns.save(weight: 99.9, waist: nil, unitSystem: .metric, takenAt: after)

        let weights = try await rows(store, "weight")
        XCTAssertEqual(weights.map(\.day), ["2031-01-08", "2031-01-09"],
                       "two minutes apart and either side of local midnight: two days (both are the 8th in UTC)")
    }

    /// Clocks forward and back in New York (2031-03-09 and 2031-11-02), and a zone whose clocks skip
    /// local midnight itself (Havana, 2024-03-10 00:00 to 01:00): a reading keeps the local day its
    /// wall clock showed.
    func testReadingAcrossADaylightSavingChangeKeepsItsLocalDay() async throws {
        let cases: [(zone: String, epoch: Int, day: String, what: String)] = [
            ("America/New_York", 1_930_797_000, "2031-03-08", "23:30 on the eve of the spring change"),
            ("America/New_York", 1_930_804_200, "2031-03-09", "01:30, before the clocks jump"),
            ("America/New_York", 1_930_807_800, "2031-03-09", "03:30, after the jump"),
            ("America/New_York", 1_930_879_800, "2031-03-09", "23:30 on the 23-hour day"),
            ("America/New_York", 1_930_883_400, "2031-03-10", "00:30 the next day"),
            ("America/New_York", 1_951_356_600, "2031-11-01", "23:30 on the eve of the autumn change"),
            ("America/New_York", 1_951_363_800, "2031-11-02", "the first 01:30"),
            ("America/New_York", 1_951_367_400, "2031-11-02", "the second 01:30"),
            ("America/New_York", 1_951_446_600, "2031-11-02", "23:30 on the 25-hour day"),
            ("America/New_York", 1_951_450_200, "2031-11-03", "00:30 the next day"),
            ("America/Havana", 1_710_046_500, "2024-03-09", "23:55 before a skipped midnight"),
            ("America/Havana", 1_710_047_100, "2024-03-10", "01:05 after a skipped midnight"),
        ]
        for item in cases {
            let (store, repo) = try await makeRepo()
            let zone = try XCTUnwrap(TimeZone(identifier: item.zone))
            let weighIns = makeWeighIns(repo, zone: zone)
            try await weighIns.save(weight: 100.0, waist: nil, unitSystem: .metric,
                                    takenAt: Date(timeIntervalSince1970: Double(item.epoch)))
            let stored = try await rows(store, "weight")
            XCTAssertEqual(stored.map(\.day), [item.day], "\(item.zone): \(item.what)")
        }
    }

    /// §6.1: "A reading's `day` is stored and is not recomputed when the device changes zone, so
    /// travel cannot move a past reading into another week."
    func testZoneChangeBetweenTwoReadingsDoesNotMoveTheFirst() async throws {
        let (store, repo) = try await makeRepo()
        let zone = Zone("Asia/Kolkata")
        let now = later
        let provider = try flagOnProvider(repo, today: "2031-06-30")
        let weighIns = WeighInStore(repository: repo, provider: provider, timeZone: { zone.current }, now: { now })

        // 2031-01-09 02:00 in Kolkata, which is still the 8th in Los Angeles.
        let first = Date(timeIntervalSince1970: 1_925_670_600)
        let savedFirst = try await weighIns.save(weight: 100.0, waist: 100.0, unitSystem: .metric, takenAt: first)
        XCTAssertEqual(savedFirst.map(\.day), ["2031-01-09", "2031-01-09"])

        zone.current = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        // 2031-01-15 07:00 in Los Angeles.
        try await weighIns.save(weight: 99.2, waist: nil, unitSystem: .metric,
                                takenAt: Date(timeIntervalSince1970: 1_926_255_600))

        let weights = try await rows(store, "weight")
        XCTAssertEqual(weights.map(\.day), ["2031-01-09", "2031-01-15"],
                       "the first reading stays on the day it was saved on; the second takes the new zone's day")
        let waists = try await rows(store, "waist")
        XCTAssertEqual(waists.map(\.day), ["2031-01-09"])
        XCTAssertEqual(weights.first, savedFirst.first, "the first row is byte-identical after the second save")

        // Reading it back, and resolving, uses the stored day in the new zone as well.
        let listed = await weighIns.readings(.weight)
        XCTAssertEqual(listed.map(\.day), ["2031-01-09", "2031-01-15"])
        XCTAssertEqual(provider.series(.weight, consumer: .display).map(\.day), ["2031-01-09", "2031-01-15"])
        XCTAssertNil(provider.resolve(.weight, asOf: "2031-01-08", consumer: .display)?.day,
                     "by its stored day the first reading does not exist on the 8th: only the undated profile value does")
        XCTAssertEqual(provider.resolve(.weight, asOf: "2031-01-09", consumer: .display)?.day, "2031-01-09")
    }

    /// A row saved by the weigh-in sheet and a row saved by the Lab Book editor at the same instant
    /// land on the same day. Recorded for the device's current zone only (specification §16).
    func testDayKeyAgreesWithLabBookFormat() async throws {
        let instants = [1_925_622_000, 1_925_663_340, 1_925_663_460, 1_925_670_600, 1_930_804_200,
                        1_951_363_800, 1_951_367_400, 1_940_587_200]
        for epoch in instants {
            let (store, repo) = try await makeRepo()
            let weighIns = WeighInStore(repository: repo, provider: nil, timeZone: { TimeZone.current },
                                        now: { Date(timeIntervalSince1970: 1_956_528_000) })
            let instant = Date(timeIntervalSince1970: Double(epoch))
            try await weighIns.save(weight: 100.0, waist: nil, unitSystem: .metric, takenAt: instant)
            let stored = try await rows(store, "weight")
            XCTAssertEqual(stored.map(\.day), [LabBookFormat.dayKey(instant)], "instant \(epoch)")
        }
    }

    func testBackdatedSaveUsesTheChosenInstant() async throws {
        let (store, repo) = try await makeRepo()
        // "Now" is 2031-01-22; the reading is entered for 2031-01-08.
        let weighIns = makeWeighIns(repo, now: week3)

        try await weighIns.save(weight: 100.0, waist: 100.0, unitSystem: .metric, takenAt: week1)

        let weightRows = try await rows(store, "weight")
        let weight = try XCTUnwrap(weightRows.first)
        XCTAssertEqual(weight.takenAt, 1_925_622_000, "the chosen instant, not the moment of saving")
        XCTAssertEqual(weight.day, "2031-01-08")
        XCTAssertTrue(weight.id.hasPrefix("weight-1925622000-"))
        let waistRows = try await rows(store, "waist")
        let waist = try XCTUnwrap(waistRows.first)
        XCTAssertEqual(waist.takenAt, 1_925_622_000)
    }

    /// The date control allows no future instant (§10.3), and the pure function would drop such a
    /// reading as `future`: a stored row the scorecard cannot see. The store refuses it.
    func testFutureInstantIsRefusedWithoutWriting() async throws {
        let (store, repo) = try await makeRepo()
        let weighIns = makeWeighIns(repo, now: week2)

        await assertThrows(.futureInstant) {
            try await weighIns.save(weight: 100.0, waist: 100.0, unitSystem: .metric,
                                    takenAt: self.week2.addingTimeInterval(60))
        }
        let all = try await everything(store, ids: ["my-whoop"])
        XCTAssertTrue(all.isEmpty)

        // The present instant itself is allowed.
        try await weighIns.save(weight: 100.0, waist: nil, unitSystem: .metric, takenAt: week2)
        let weights = try await rows(store, "weight")
        XCTAssertEqual(weights.count, 1)
    }

    // MARK: - §10.3 validation

    func testOutOfRangeValuesAreRefused() async throws {
        let (store, repo) = try await makeRepo()
        let weighIns = makeWeighIns(repo)

        for weight in [29.9, 250.1, 600.0, 1.0] {
            await assertThrows(.weightOutOfRange, "weight \(weight) kg") {
                try await weighIns.save(weight: weight, waist: nil, unitSystem: .metric, takenAt: self.week1)
            }
        }
        for waist in [39.9, 200.1, 5.0, 1_000.0] {
            await assertThrows(.waistOutOfRange, "waist \(waist) cm") {
                try await weighIns.save(weight: 100.0, waist: waist, unitSystem: .metric, takenAt: self.week1)
            }
        }
        // The range is applied after conversion: 60 is a valid weight in kilograms and not in pounds
        // (27.2 kg); 30 is a valid waist in inches (76.2 cm) and not in centimetres.
        await assertThrows(.weightOutOfRange, "60 lb") {
            try await weighIns.save(weight: 60.0, waist: nil, unitSystem: .imperial, takenAt: self.week1)
        }
        await assertThrows(.waistOutOfRange, "30 cm") {
            try await weighIns.save(weight: 100.0, waist: 30.0, unitSystem: .metric, takenAt: self.week1)
        }

        let all = try await everything(store, ids: ["my-whoop"])
        XCTAssertTrue(all.isEmpty, "a refused weigh-in writes nothing")
    }

    func testNonFiniteZeroAndNegativeValuesAreRefusedWithoutWriting() async throws {
        let (store, repo) = try await makeRepo()
        let weighIns = makeWeighIns(repo)

        for weight in [Double.nan, .infinity, -.infinity, 0, -0.0, -100.0] {
            for system in [UnitSystem.metric, .imperial] {
                await assertThrows(.weightOutOfRange, "weight \(weight) \(system)") {
                    try await weighIns.save(weight: weight, waist: nil, unitSystem: system, takenAt: self.week1)
                }
            }
        }
        for waist in [Double.nan, .infinity, -.infinity, 0, -96.0] {
            await assertThrows(.waistOutOfRange, "waist \(waist)") {
                try await weighIns.save(weight: 100.0, waist: waist, unitSystem: .metric, takenAt: self.week1)
            }
        }
        let all = try await everything(store, ids: ["my-whoop"])
        XCTAssertTrue(all.isEmpty)
    }

    /// Validation comes before any write: a good weight with a bad waist stores neither, so the sheet
    /// can stay open "with the values intact and a retry" and no half weigh-in exists.
    func testInvalidWaistRefusesTheWholeWeighIn() async throws {
        let (store, repo) = try await makeRepo()
        let weighIns = makeWeighIns(repo)

        await assertThrows(.waistOutOfRange) {
            try await weighIns.save(weight: 100.0, waist: 0, unitSystem: .metric, takenAt: self.week1)
        }
        let all = try await everything(store, ids: ["my-whoop"])
        XCTAssertTrue(all.isEmpty, "the weight row must not be written when the waist is refused")
    }

    func testRangeBoundsAreInclusive() async throws {
        XCTAssertEqual(WeighInStore.weightRangeKg, 30...250)
        XCTAssertEqual(WeighInStore.waistRangeCm, 40...200)

        let (store, repo) = try await makeRepo()
        let weighIns = makeWeighIns(repo)
        try await weighIns.save(weight: 30.0, waist: 40.0, unitSystem: .metric, takenAt: week1)
        try await weighIns.save(weight: 250.0, waist: 200.0, unitSystem: .metric, takenAt: week2)

        let weights = try await rows(store, "weight")
        let waists = try await rows(store, "waist")
        XCTAssertEqual(weights.map(\.value), [30.0, 250.0])
        XCTAssertEqual(waists.map(\.value), [40.0, 200.0])
    }

    // MARK: - §9.1 edit the value

    func testEditingTheValueUpdatesInPlace() async throws {
        let (store, repo) = try await makeRepo()
        let weighIns = makeWeighIns(repo)
        let saved = try await weighIns.save(weight: 100.0, waist: 100.0, unitSystem: .metric, takenAt: week1)
        let before = try await counts(store, ids: ["my-whoop"])

        let edited = try await weighIns.edit(saved[0], value: 99.6, unitSystem: .metric, takenAt: week1)

        var expected = saved[0]
        expected.value = 99.6
        XCTAssertEqual(edited, expected, "only the value changed: same id, instant, day, source and unit")
        let weights = try await rows(store, "weight")
        XCTAssertEqual(weights, [expected], "one row, updated in place")
        let waists = try await rows(store, "waist")
        XCTAssertEqual(waists, [saved[1]], "the waist of the same weigh-in is untouched")
        let after = try await counts(store, ids: ["my-whoop"])
        XCTAssertEqual(after, before, "a value edit neither adds nor removes a row")

        // In pounds: converted, and the stored unit stays kilograms.
        let inPounds = try await weighIns.edit(edited, value: 218.0, unitSystem: .imperial, takenAt: week1)
        XCTAssertEqual(inPounds.id, saved[0].id)
        XCTAssertEqual(try XCTUnwrap(inPounds.value), 218.0 / UnitFormatter.poundsPerKilogram, accuracy: 1e-9)
        XCTAssertEqual(inPounds.unit, "kg")
        let final = try await rows(store, "weight")
        XCTAssertEqual(final, [inPounds])
    }

    /// A value edit made after the device changed zone must not move the reading to another day.
    func testEditingTheValueKeepsTheStoredDayAfterAZoneChange() async throws {
        let (store, repo) = try await makeRepo()
        let zone = Zone("Asia/Kolkata")
        let now = later
        let weighIns = WeighInStore(repository: repo, provider: nil, timeZone: { zone.current }, now: { now })
        let instant = Date(timeIntervalSince1970: 1_925_670_600)   // the 9th in Kolkata, the 8th in Los Angeles
        let saved = try await weighIns.save(weight: 100.0, waist: nil, unitSystem: .metric, takenAt: instant)
        XCTAssertEqual(saved.first?.day, "2031-01-09")

        zone.current = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let edited = try await weighIns.edit(saved[0], value: 99.6, unitSystem: .metric, takenAt: instant)

        XCTAssertEqual(edited.day, "2031-01-09", "the stored day is not recomputed by a value edit")
        let weights = try await rows(store, "weight")
        XCTAssertEqual(weights.map(\.day), ["2031-01-09"])
        XCTAssertEqual(weights.map(\.value), [99.6])
    }

    func testEditRefusesInvalidValuesAndLeavesTheRowUnchanged() async throws {
        let (store, repo) = try await makeRepo()
        let weighIns = makeWeighIns(repo, now: week3)
        let saved = try await weighIns.save(weight: 100.0, waist: 100.0, unitSystem: .metric, takenAt: week1)
        let before = try await everything(store, ids: ["my-whoop"])

        for value in [Double.nan, .infinity, 0, -1.0, 29.9, 250.1] {
            await assertThrows(.weightOutOfRange, "weight \(value)") {
                try await weighIns.edit(saved[0], value: value, unitSystem: .metric, takenAt: self.week1)
            }
        }
        for value in [Double.nan, 0, 39.9, 200.1] {
            await assertThrows(.waistOutOfRange, "waist \(value)") {
                try await weighIns.edit(saved[1], value: value, unitSystem: .metric, takenAt: self.week1)
            }
        }
        // An invalid value with a new date must not get as far as the insert.
        await assertThrows(.weightOutOfRange) {
            try await weighIns.edit(saved[0], value: .nan, unitSystem: .metric, takenAt: self.week2)
        }
        // A date edit into the future is refused as a save is.
        await assertThrows(.futureInstant) {
            try await weighIns.edit(saved[0], value: 100.0, unitSystem: .metric,
                                    takenAt: self.week3.addingTimeInterval(60))
        }
        let after = try await everything(store, ids: ["my-whoop"])
        XCTAssertEqual(after, before, "a refused edit changes nothing")
    }

    // MARK: - §9.1 edit the date

    /// Fault line F27. An injected failure between the two steps of a date edit leaves BOTH readings:
    /// the insert has happened and the delete has not. An implementation that deletes first has no
    /// reading at that moment, and fails here with one row or none.
    func testEditingTheDateInsertsBeforeDeleting() async throws {
        let (store, repo) = try await makeRepo()
        let weighIns = makeWeighIns(repo)
        let saved = try await weighIns.save(weight: 100.0, waist: nil, unitSystem: .metric, takenAt: week1)

        struct Interrupted: Error {}
        var seamFired = 0
        weighIns.interruptDateEditForTesting = {
            seamFired += 1
            throw Interrupted()
        }
        do {
            _ = try await weighIns.edit(saved[0], value: 99.5, unitSystem: .metric, takenAt: week2)
            XCTFail("the injected failure must surface to the caller")
        } catch is Interrupted {
            // expected
        } catch {
            XCTFail("expected the injected failure, got \(error)")
        }
        XCTAssertEqual(seamFired, 1, "the seam is reached exactly once")

        let weights = try await rows(store, "weight")
        XCTAssertEqual(weights.count, 2, "an interruption between the steps leaves two readings, never none")
        XCTAssertEqual(weights.first, saved[0], "the old reading is intact")
        XCTAssertEqual(weights.last?.takenAt, 1_926_226_800, "the new reading was already inserted")
        XCTAssertEqual(weights.last?.value, 99.5)
        let listed = await weighIns.readings(.weight)
        XCTAssertEqual(listed.count, 2, "the owner can see both and delete one")

        // Retrying the same edit completes it and does not leave a third row.
        weighIns.interruptDateEditForTesting = nil
        let moved = try await weighIns.edit(saved[0], value: 99.5, unitSystem: .metric, takenAt: week2)
        let afterRetry = try await rows(store, "weight")
        XCTAssertEqual(afterRetry, [moved], "the returned row is the row as stored")
        XCTAssertEqual(moved.takenAt, 1_926_226_800)
    }

    /// The uninterrupted date edit: one reading afterwards, at the new instant, with a new id.
    func testDateEditReplacesTheRowWithOneAtTheNewInstant() async throws {
        let (store, repo) = try await makeRepo()
        let weighIns = makeWeighIns(repo)
        let saved = try await weighIns.save(weight: 100.0, waist: 100.0, unitSystem: .metric, takenAt: week1)
        let original = saved[0]
        let before = try await counts(store, ids: ["my-whoop"])

        var seamFired = 0
        weighIns.interruptDateEditForTesting = { seamFired += 1 }
        let moved = try await weighIns.edit(original, value: 99.8, unitSystem: .metric, takenAt: week2)
        XCTAssertEqual(seamFired, 1, "a date edit passes the seam once")

        XCTAssertEqual(moved.takenAt, 1_926_226_800)
        XCTAssertEqual(moved.day, "2031-01-15", "the day of the new instant")
        XCTAssertNotEqual(moved.id, original.id, "a new instant needs a new row: the store cannot re-time an id (C4)")
        XCTAssertTrue(moved.id.hasPrefix("weight-1926226800-"), "id \(moved.id)")
        XCTAssertTrue(isHex8(moved.id.dropFirst("weight-1926226800-".count)), "id \(moved.id)")
        XCTAssertEqual(moved.deviceId, original.deviceId)
        XCTAssertEqual(moved.markerKey, "weight")
        XCTAssertEqual(moved.category, "bodyMeasurement")
        XCTAssertEqual(moved.source, "manual")
        XCTAssertEqual(moved.unit, "kg")
        XCTAssertEqual(moved.value, 99.8, "a date edit may change the value in the same step")
        XCTAssertNil(moved.note)
        XCTAssertNil(moved.referenceText)

        let weights = try await rows(store, "weight")
        XCTAssertEqual(weights, [moved], "afterwards exactly one reading, the moved one")
        let waists = try await rows(store, "waist")
        XCTAssertEqual(waists, [saved[1]], "the waist is its own row and is not moved with the weight")
        let after = try await counts(store, ids: ["my-whoop"])
        XCTAssertEqual(after, before)

        // A value edit never reaches the date-edit seam.
        seamFired = 0
        _ = try await weighIns.edit(moved, value: 99.9, unitSystem: .metric, takenAt: week2)
        XCTAssertEqual(seamFired, 0)
    }

    /// The day of a moved reading comes from the zone at the time of the edit, as a save's does.
    func testDateEditTakesTheDayOfTheNewInstantInTheGivenZone() async throws {
        let (store, repo) = try await makeRepo()
        let kolkata = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
        let weighIns = makeWeighIns(repo, zone: kolkata)
        let saved = try await weighIns.save(weight: 100.0, waist: nil, unitSystem: .metric, takenAt: week1)

        // 2031-01-09 00:01 in Kolkata (the 8th in UTC).
        let moved = try await weighIns.edit(saved[0], value: 100.0, unitSystem: .metric,
                                            takenAt: Date(timeIntervalSince1970: 1_925_663_460))
        XCTAssertEqual(moved.day, "2031-01-09")
        let weights = try await rows(store, "weight")
        XCTAssertEqual(weights.map(\.day), ["2031-01-09"])
    }

    // MARK: - §9.1 delete

    /// Delete removes the row, and the series the weekly points are built from loses it.
    func testDeleteRemovesTheRowAndTheWeeklySeriesLosesIt() async throws {
        let (store, repo) = try await makeRepo()
        let provider = try flagOnProvider(repo, today: "2031-01-22")
        let weighIns = makeWeighIns(repo, provider: provider)
        let first = try await weighIns.save(weight: 100.0, waist: 100.0, unitSystem: .metric, takenAt: week1)
        let second = try await weighIns.save(weight: 99.2, waist: 99.5, unitSystem: .metric, takenAt: week2)
        let third = try await weighIns.save(weight: 98.4, waist: 99.0, unitSystem: .metric, takenAt: week3)
        XCTAssertEqual(provider.series(.weight, consumer: .display).map(\.day), ["2031-01-08", "2031-01-15", "2031-01-22"])

        try await weighIns.delete(second[0])

        let weights = try await rows(store, "weight")
        XCTAssertEqual(weights, [first[0], third[0]], "the other readings are byte-identical")
        let waists = try await rows(store, "waist")
        XCTAssertEqual(waists, [first[1], second[1], third[1]], "deleting a weight does not delete its waist")
        XCTAssertEqual(provider.series(.weight, consumer: .display).map(\.day), ["2031-01-08", "2031-01-22"],
                       "the provider was refreshed by the delete")
        XCTAssertEqual(provider.series(.waist, consumer: .display).map(\.day), ["2031-01-08", "2031-01-15", "2031-01-22"])
        let listed = await weighIns.readings(.weight)
        XCTAssertEqual(listed.map(\.id), [first[0].id, third[0].id])

        // The week it was the only reading of becomes a missed week, not a zero and not a bridge.
        let input = CutScorecardInput(
            weights: provider.series(.weight, consumer: .display).map {
                CutScorecardReading(day: $0.day, takenAt: $0.takenAt ?? 0, value: $0.value)
            },
            waists: [], phase: nil, parameters: .generic, today: "2031-01-22")
        let result = CutScorecard.evaluate(input)
        XCTAssertEqual(result.weeks.map(\.weightKg), [100.0, nil, 98.4])

        // Deleting the newest moves the current value back.
        try await weighIns.delete(third[0])
        XCTAssertEqual(provider.current(.weight, consumer: .estimate)?.value, 100.0)
    }

    /// The store edits and deletes weight and waist readings only. Handed any other Lab Book row it
    /// refuses and changes nothing.
    func testEditAndDeleteRefuseRowsThatAreNotWeightOrWaist() async throws {
        let (store, repo) = try await makeRepo()
        let weighIns = makeWeighIns(repo)
        let others = [
            LabMarkerRow(id: "ldl-1", deviceId: "my-whoop", markerKey: "ldl", category: "bloodPanel",
                         day: "2031-01-08", takenAt: 1_925_622_000, value: 3.1, valueText: nil, unit: "mmol/L",
                         source: "manual", note: "fasted", referenceText: "< 3.0"),
            LabMarkerRow(id: "bf-1", deviceId: "my-whoop", markerKey: "body_fat", category: "bodyMeasurement",
                         day: "2031-01-08", takenAt: 1_925_622_000, value: 24.5, valueText: nil, unit: "%",
                         source: "manual", note: nil, referenceText: nil),
            LabMarkerRow(id: "height-1", deviceId: "my-whoop", markerKey: "height", category: "bodyMeasurement",
                         day: "2031-01-08", takenAt: 1_925_622_000, value: 180.0, valueText: nil, unit: "cm",
                         source: "manual", note: nil, referenceText: nil),
        ]
        try await store.upsertLabMarkers(others)
        let before = try await everything(store, ids: ["my-whoop"])

        for row in others {
            await assertThrows(.notABodyMeasurement, "edit \(row.markerKey)") {
                try await weighIns.edit(row, value: 100.0, unitSystem: .metric, takenAt: self.week1)
            }
            await assertThrows(.notABodyMeasurement, "date edit \(row.markerKey)") {
                try await weighIns.edit(row, value: 100.0, unitSystem: .metric, takenAt: self.week2)
            }
            await assertThrows(.notABodyMeasurement, "delete \(row.markerKey)") {
                try await weighIns.delete(row)
            }
        }
        let after = try await everything(store, ids: ["my-whoop"])
        XCTAssertEqual(after, before)
    }

    // MARK: - Data safety: rows the weigh-in flow did not create

    /// Other markers, other sources of the same markers, qualitative rows and rows under another
    /// device id are byte-identical after a save, a value edit, a date edit and a delete.
    func testPreExistingLabBookRowsAreByteIdenticalAfterSaveEditDateEditAndDelete() async throws {
        let (store, repo) = try await makeRepo()
        try register(store, "whoop-old", status: .archived)
        let ids = ["my-whoop", "whoop-old", "stray-id"]
        let bystanders = [
            LabMarkerRow(id: "ldl-1", deviceId: "my-whoop", markerKey: "ldl", category: "bloodPanel",
                         day: "2031-01-08", takenAt: 1_925_622_000, value: 3.1, valueText: nil, unit: "mmol/L",
                         source: "manual", note: "fasted", referenceText: "< 3.0"),
            LabMarkerRow(id: "bf-1", deviceId: "my-whoop", markerKey: "body_fat", category: "bodyMeasurement",
                         day: "2031-01-08", takenAt: 1_925_622_000, value: 24.5, valueText: nil, unit: "%",
                         source: "manual", note: nil, referenceText: nil),
            LabMarkerRow(id: "height-1", deviceId: "my-whoop", markerKey: "height", category: "bodyMeasurement",
                         day: "2031-01-08", takenAt: 1_925_622_000, value: 180.0, valueText: nil, unit: "cm",
                         source: "manual", note: nil, referenceText: nil),
            // The same markers at the very instant the weigh-in will use, from another source, in
            // another unit, with a note: the natural key keeps them apart from the weigh-in's rows.
            LabMarkerRow(id: "weight-csv-1", deviceId: "my-whoop", markerKey: "weight", category: "bodyMeasurement",
                         day: "2031-01-08", takenAt: 1_925_622_000, value: 220.5, valueText: nil, unit: "lb",
                         source: "csv", note: "imported", referenceText: "ref"),
            LabMarkerRow(id: "waist-csv-1", deviceId: "my-whoop", markerKey: "waist", category: "bodyMeasurement",
                         day: "2031-01-08", takenAt: 1_925_622_000, value: 39.5, valueText: nil, unit: "in",
                         source: "csv", note: "imported", referenceText: nil),
            // An earlier manual reading the weigh-in flow did not write in this test.
            LabMarkerRow(id: "weight-1924000000-0000AAAA", deviceId: "my-whoop", markerKey: "weight",
                         category: "bodyMeasurement", day: "2030-12-20", takenAt: 1_924_000_000, value: 101.0,
                         valueText: nil, unit: "kg", source: "manual", note: "before the cut", referenceText: nil),
            LabMarkerRow(id: "note-1", deviceId: "my-whoop", markerKey: "appointment", category: "appointmentNote",
                         day: "2031-01-08", takenAt: 1_925_622_000, value: nil, valueText: "fixture note", unit: "",
                         source: "manual", note: nil, referenceText: nil),
            // Under an earlier registered strap and under an id nothing knows about.
            LabMarkerRow(id: "weight-old-1", deviceId: "whoop-old", markerKey: "weight", category: "bodyMeasurement",
                         day: "2030-12-25", takenAt: 1_924_412_400, value: 100.8, valueText: nil, unit: "kg",
                         source: "manual", note: nil, referenceText: nil),
            LabMarkerRow(id: "waist-stray-1", deviceId: "stray-id", markerKey: "waist", category: "bodyMeasurement",
                         day: "2030-12-25", takenAt: 1_924_412_400, value: 101.0, valueText: nil, unit: "cm",
                         source: "manual", note: nil, referenceText: nil),
        ]
        try await store.upsertLabMarkers(bystanders)
        let bystanderIds = Set(bystanders.map(\.id))
        func others() async throws -> [LabMarkerRow] {
            try await everything(store, ids: ids).filter { bystanderIds.contains($0.id) }
        }
        let before = try await others()
        XCTAssertEqual(before.count, bystanders.count)
        let weighIns = makeWeighIns(repo)

        let saved = try await weighIns.save(weight: 100.0, waist: 100.0, unitSystem: .metric, takenAt: week1)
        let afterSave = try await others()
        XCTAssertEqual(afterSave, before, "save")
        let totalAfterSave = try await everything(store, ids: ids).count
        XCTAssertEqual(totalAfterSave, bystanders.count + 2, "the save added its two rows and replaced none")

        let edited = try await weighIns.edit(saved[0], value: 99.7, unitSystem: .metric, takenAt: week1)
        let afterEdit = try await others()
        XCTAssertEqual(afterEdit, before, "value edit")

        let moved = try await weighIns.edit(edited, value: 99.7, unitSystem: .metric, takenAt: week2)
        let afterMove = try await others()
        XCTAssertEqual(afterMove, before, "date edit")

        // Move it ONTO the instant of the earlier manual reading's neighbour day and back: still nothing else changes.
        let movedAgain = try await weighIns.edit(moved, value: 99.7, unitSystem: .metric, takenAt: week3)
        let afterSecondMove = try await others()
        XCTAssertEqual(afterSecondMove, before, "second date edit")

        try await weighIns.delete(movedAgain)
        try await weighIns.delete(saved[1])
        let afterDelete = try await others()
        XCTAssertEqual(afterDelete, before, "delete")
        let total = try await everything(store, ids: ids).count
        XCTAssertEqual(total, bystanders.count, "only the weigh-in's own rows came and went")
    }

    /// The history list may edit a Lab Book row "whatever wrote it" (§10.4). A value edit of an
    /// imported row keeps its identity, its source, its note and its reference text; a delete removes
    /// that row and no other.
    func testEditingAnImportedRowKeepsItsIdentityNoteAndReference() async throws {
        let (store, repo) = try await makeRepo()
        let imported = LabMarkerRow(id: "weight-csv-1", deviceId: "my-whoop", markerKey: "weight",
                                    category: "bodyMeasurement", day: "2031-01-08", takenAt: 1_925_622_000,
                                    value: 220.5, valueText: nil, unit: "lb", source: "csv",
                                    note: "imported", referenceText: "ref")
        let manual = LabMarkerRow(id: "weight-1925622000-0000AAAA", deviceId: "my-whoop", markerKey: "weight",
                                  category: "bodyMeasurement", day: "2031-01-08", takenAt: 1_925_622_000,
                                  value: 100.0, valueText: nil, unit: "kg", source: "manual", note: nil,
                                  referenceText: nil)
        try await store.upsertLabMarkers([imported, manual])
        let weighIns = makeWeighIns(repo)

        let edited = try await weighIns.edit(imported, value: 99.5, unitSystem: .metric, takenAt: week1)

        var expected = imported
        expected.value = 99.5
        expected.unit = "kg"
        XCTAssertEqual(edited, expected, "value and unit change; id, source, note and reference text do not")
        let weights = try await rows(store, "weight")
        XCTAssertEqual(weights.sorted { $0.id < $1.id }, [manual, expected].sorted { $0.id < $1.id },
                       "the manual row at the same instant is a different row and is untouched")

        try await weighIns.delete(edited)
        let remaining = try await rows(store, "weight")
        XCTAssertEqual(remaining, [manual])
    }

    // MARK: - Ruling R25

    /// Rows stored under earlier strap ids are returned after the active id is re-pointed, and no row
    /// changes id by being read.
    func testReadingsUnderEarlierStrapIdsAreReturnedAfterTheActiveIdIsRepointed() async throws {
        let (store, repo) = try await makeRepo()
        try register(store, "whoop-old", status: .archived)
        try register(store, "whoop-new", status: .active)
        let ids = ["my-whoop", "whoop-old", "whoop-new"]
        let weighIns = makeWeighIns(repo)

        try await weighIns.save(weight: 100.0, waist: 100.0, unitSystem: .metric, takenAt: week1)
        repo.adoptActiveDeviceId("whoop-old")
        try await weighIns.save(weight: 99.2, waist: nil, unitSystem: .metric, takenAt: week2)
        let afterOld = try await counts(store, ids: ids)
        XCTAssertEqual(afterOld, ["my-whoop": 2, "whoop-old": 1, "whoop-new": 0],
                       "a save writes under the id that is active at that moment, and only there")

        repo.adoptActiveDeviceId("whoop-new")
        let beforeRead = try await counts(store, ids: ids)
        let weights = await weighIns.readings(.weight)
        let waists = await weighIns.readings(.waist)

        XCTAssertEqual(weights.map(\.value), [100.0, 99.2], "every earlier reading, oldest first")
        XCTAssertEqual(weights.map(\.deviceId), ["my-whoop", "whoop-old"], "each still under the id it was stored under")
        XCTAssertEqual(waists.map(\.value), [100.0])
        let afterRead = try await counts(store, ids: ids)
        XCTAssertEqual(afterRead, beforeRead, "reading moved or copied a row")

        try await weighIns.save(weight: 98.4, waist: 99.0, unitSystem: .metric, takenAt: week3)
        let afterNew = try await counts(store, ids: ids)
        XCTAssertEqual(afterNew, ["my-whoop": 2, "whoop-old": 1, "whoop-new": 2])
        let all = await weighIns.readings(.weight)
        XCTAssertEqual(all.map(\.value), [100.0, 99.2, 98.4])
        XCTAssertEqual(all.map(\.deviceId), ["my-whoop", "whoop-old", "whoop-new"])
    }

    /// Superseded by ruling R42 and labbook-ownership.md §7.1: only rows equal in content are one
    /// reading. A copy across ids (same marker, instant, source, value and every other column but
    /// `id`, `deviceId` and `day`) is listed once, and the row listed is the active id's. Both copies
    /// stay stored. Two rows at one instant with different values are two readings, both listed.
    func testDuplicateAcrossIdsCollapsesWithTheActiveCopyWinning() async throws {
        let (store, repo) = try await makeRepo(deviceId: "whoop-new")
        try register(store, "whoop-new", status: .active)
        let ids = ["my-whoop", "whoop-new"]
        func row(_ deviceId: String, _ suffix: String, value: Double, source: String = "manual") -> LabMarkerRow {
            LabMarkerRow(id: "weight-1925622000-\(suffix)", deviceId: deviceId, markerKey: "weight",
                         category: "bodyMeasurement", day: "2031-01-08", takenAt: 1_925_622_000, value: value,
                         valueText: nil, unit: "kg", source: source, note: nil, referenceText: nil)
        }
        try await store.upsertLabMarkers([row("my-whoop", "CCCCCCCC", value: 100.0),
                                          row("whoop-new", "AAAAAAAA", value: 100.0),
                                          // Same instant, another source: not a duplicate.
                                          row("my-whoop", "DDDDDDDD", value: 100.2, source: "csv")])
        let weighIns = makeWeighIns(repo)

        let listed = await weighIns.readings(.weight)
        XCTAssertEqual(listed.map(\.id).sorted(), ["weight-1925622000-AAAAAAAA", "weight-1925622000-DDDDDDDD"],
                       "the active id's copy stands for the duplicate; the other source is its own reading")
        XCTAssertFalse(listed.contains { $0.id == "weight-1925622000-CCCCCCCC" })
        let stored = try await counts(store, ids: ids)
        XCTAssertEqual(stored, ["my-whoop": 2, "whoop-new": 1], "de-duplication is a read rule; nothing is deleted")

        // With the canonical id active the same data lists the canonical copy.
        let (store2, repo2) = try await makeRepo(deviceId: "my-whoop")
        try register(store2, "whoop-new", status: .paired)
        try await store2.upsertLabMarkers([row("my-whoop", "CCCCCCCC", value: 100.0),
                                           row("whoop-new", "AAAAAAAA", value: 100.0)])
        let listed2 = await makeWeighIns(repo2).readings(.weight)
        XCTAssertEqual(listed2.map(\.id), ["weight-1925622000-CCCCCCCC"])

        // The data this test held before ruling R42: the two rows differ in value. They are two
        // readings, and neither is hidden behind the other, whichever id is active.
        for active in ["whoop-new", "my-whoop"] {
            let (store3, repo3) = try await makeRepo(deviceId: active)
            try register(store3, "whoop-new", status: active == "whoop-new" ? .active : .paired)
            try await store3.upsertLabMarkers([row("my-whoop", "CCCCCCCC", value: 100.4),
                                               row("whoop-new", "AAAAAAAA", value: 100.0)])
            let listed3 = await makeWeighIns(repo3).readings(.weight)
            XCTAssertEqual(listed3.map(\.id), ["weight-1925622000-AAAAAAAA", "weight-1925622000-CCCCCCCC"],
                           "active \(active): both readings, ordered by instant then id")
            XCTAssertEqual(listed3.map(\.value), [100.0, 100.4], "active \(active)")
        }
    }

    /// Edit and delete act on the row under the id it was stored under. The count under every id is
    /// the same before and after a value edit and a date edit, and a delete lowers exactly one.
    func testEditAndDeleteActOnTheRowUnderItsOwnIdAndMoveNothing() async throws {
        let (store, repo) = try await makeRepo(deviceId: "whoop-new")
        try register(store, "whoop-old", status: .archived)
        try register(store, "whoop-new", status: .active)
        let ids = ["my-whoop", "whoop-old", "whoop-new"]
        func row(_ deviceId: String, _ takenAt: Int, _ day: String, value: Double) -> LabMarkerRow {
            LabMarkerRow(id: "weight-\(takenAt)-0A1B2C3D", deviceId: deviceId, markerKey: "weight",
                         category: "bodyMeasurement", day: day, takenAt: takenAt, value: value, valueText: nil,
                         unit: "kg", source: "manual", note: nil, referenceText: nil)
        }
        let canonical = row("my-whoop", 1_925_622_000, "2031-01-08", value: 100.0)
        let old = row("whoop-old", 1_926_226_800, "2031-01-15", value: 99.2)
        let new = row("whoop-new", 1_926_831_600, "2031-01-22", value: 98.4)
        try await store.upsertLabMarkers([canonical, old, new])
        let weighIns = makeWeighIns(repo)
        let start = try await counts(store, ids: ids)
        XCTAssertEqual(start, ["my-whoop": 1, "whoop-old": 1, "whoop-new": 1])

        // Value edit of the row under the earlier id.
        let edited = try await weighIns.edit(old, value: 99.0, unitSystem: .metric, takenAt: week2)
        XCTAssertEqual(edited.deviceId, "whoop-old")
        XCTAssertEqual(edited.id, old.id)
        let afterEdit = try await counts(store, ids: ids)
        XCTAssertEqual(afterEdit, start, "a value edit created a row under another id, or removed one")
        let oldRows = try await rows(store, "weight", deviceId: "whoop-old")
        XCTAssertEqual(oldRows.map(\.value), [99.0])
        let canonicalRows = try await rows(store, "weight", deviceId: "my-whoop")
        XCTAssertEqual(canonicalRows, [canonical], "the other ids' rows are byte-identical")
        let newRows = try await rows(store, "weight", deviceId: "whoop-new")
        XCTAssertEqual(newRows, [new])

        // Date edit of the row under the canonical id: replaced under the canonical id.
        let moved = try await weighIns.edit(canonical, value: 100.0, unitSystem: .metric,
                                            takenAt: week1.addingTimeInterval(86_400))
        XCTAssertEqual(moved.deviceId, "my-whoop", "a date edit must not carry a reading to the active id")
        XCTAssertEqual(moved.day, "2031-01-09")
        let afterMove = try await counts(store, ids: ids)
        XCTAssertEqual(afterMove, start, "a date edit moved a row between ids")
        let listed = await weighIns.readings(.weight)
        XCTAssertEqual(listed.map(\.deviceId), ["my-whoop", "whoop-old", "whoop-new"])
        XCTAssertEqual(listed.map(\.value), [100.0, 99.0, 98.4])

        // Delete of the row under the earlier id: that row only.
        try await weighIns.delete(edited)
        let afterDelete = try await counts(store, ids: ids)
        XCTAssertEqual(afterDelete, ["my-whoop": 1, "whoop-old": 0, "whoop-new": 1])
        let canonicalAfter = try await rows(store, "weight", deviceId: "my-whoop")
        XCTAssertEqual(canonicalAfter, [moved])
        let newAfter = try await rows(store, "weight", deviceId: "whoop-new")
        XCTAssertEqual(newAfter, [new])
    }

    /// Two rows at one instant under two ids with different values. Superseded by ruling R42 and
    /// labbook-ownership.md §7.1: they are two readings and both are listed from the start. Deleting
    /// one removes that row only; the other id's row is still stored and still listed.
    func testDeletingTheActiveCopyOfADuplicateLeavesTheOtherIdsCopy() async throws {
        let (store, repo) = try await makeRepo(deviceId: "whoop-new")
        try register(store, "whoop-new", status: .active)
        func row(_ deviceId: String, _ suffix: String, value: Double) -> LabMarkerRow {
            LabMarkerRow(id: "weight-1925622000-\(suffix)", deviceId: deviceId, markerKey: "weight",
                         category: "bodyMeasurement", day: "2031-01-08", takenAt: 1_925_622_000, value: value,
                         valueText: nil, unit: "kg", source: "manual", note: nil, referenceText: nil)
        }
        let canonical = row("my-whoop", "CCCCCCCC", value: 100.4)
        let active = row("whoop-new", "AAAAAAAA", value: 100.0)
        try await store.upsertLabMarkers([canonical, active])
        let weighIns = makeWeighIns(repo)

        let listed = await weighIns.readings(.weight)
        XCTAssertEqual(listed, [active, canonical], "different values: neither row hides the other")
        try await weighIns.delete(active)

        let activeRows = try await rows(store, "weight", deviceId: "whoop-new")
        XCTAssertTrue(activeRows.isEmpty)
        let canonicalRows = try await rows(store, "weight", deviceId: "my-whoop")
        XCTAssertEqual(canonicalRows, [canonical], "the canonical copy is byte-identical")
        let after = await weighIns.readings(.weight)
        XCTAssertEqual(after, [canonical])
    }

    /// Assumption 7 at the top of this file, as ruling R42 and labbook-ownership.md set it. A row
    /// under an id nothing registered, or under another brand's id, is the owner's reading like any
    /// other: it is listed, and it is never written to, re-keyed or removed. Before R42 this test
    /// (`testRowsOutsideTheUnionAreNotListedAndNeverTouched`) pinned that such rows were not listed.
    func testRowsUnderAnUnregisteredOrOtherBrandIdAreListedAndNeverTouched() async throws {
        let (store, repo) = try await makeRepo(deviceId: "whoop-new")
        try register(store, "whoop-new", status: .active)
        try register(store, "oura-ring", brand: "Oura", status: .paired)
        let ids = ["my-whoop", "whoop-new", "whoop-gone", "oura-ring"]
        func row(_ deviceId: String, _ takenAt: Int, _ day: String, value: Double) -> LabMarkerRow {
            LabMarkerRow(id: "weight-\(takenAt)-\(deviceId)", deviceId: deviceId, markerKey: "weight",
                         category: "bodyMeasurement", day: day, takenAt: takenAt, value: value, valueText: nil,
                         unit: "kg", source: "manual", note: nil, referenceText: nil)
        }
        let unregistered = row("whoop-gone", 1_925_622_000, "2031-01-08", value: 100.0)
        let otherBrand = row("oura-ring", 1_926_226_800, "2031-01-15", value: 99.2)
        try await store.upsertLabMarkers([unregistered, otherBrand])
        let weighIns = makeWeighIns(repo)

        let listed = await weighIns.readings(.weight)
        XCTAssertEqual(listed, [unregistered, otherBrand],
                       "rows under an unregistered id and under another brand's id are listed, oldest first")

        let saved = try await weighIns.save(weight: 98.4, waist: nil, unitSystem: .metric, takenAt: week3)
        try await weighIns.edit(saved[0], value: 98.2, unitSystem: .metric, takenAt: week3)
        let after = try await counts(store, ids: ids)
        XCTAssertEqual(after, ["my-whoop": 0, "whoop-new": 1, "whoop-gone": 1, "oura-ring": 1])
        let gone = try await rows(store, "weight", deviceId: "whoop-gone")
        XCTAssertEqual(gone, [unregistered])
        let oura = try await rows(store, "weight", deviceId: "oura-ring")
        XCTAssertEqual(oura, [otherBrand])
    }
}
