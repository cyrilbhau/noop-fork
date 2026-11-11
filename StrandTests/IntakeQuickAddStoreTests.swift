// API ASSUMED BY THESE TESTS
//
// Stage 3 specification §9.1, §9.3 and §12.3 (`IntakeQuickAddStoreTests.swift`). Written before the
// implementation exists. New, in Strand/Data/IntakeQuickAddStore.swift, as §9.3 gives it:
//
//     struct IntakeEntry: Identifiable, Equatable, Codable {
//         let id: UUID; var loggedAt: Date; let day: String
//         var proteinGrams: Double?; var energyKcal: Double?; var label: String?
//     }
//     @MainActor final class IntakeQuickAddStore {
//         enum Failure: Error, Equatable { case nothingToSave, invalidAmount, storeUnavailable }
//         init(repository: Repository, settings: IntakeSettings, defaults: UserDefaults = .standard,
//              now: @escaping () -> Date = Date.init,
//              zoneIdentifier: @escaping () -> String = { TimeZone.current.identifier })
//         func entries(day: String) -> [IntakeEntry]
//         @discardableResult func add(proteinGrams: Double?, energyKcal: Double?, label: String?,
//                                     at instant: Date) async throws -> IntakeEntry
//         func update(_ entry: IntakeEntry) async throws
//         func delete(id: UUID, day: String) async throws
//         func rebank(day: String) async throws
//         func restoredTotal(day: String) async -> IntakeStoredDay?                       [assumed]
//         @discardableResult func replaceRestoredTotal(day: String) async throws -> IntakeEntry   [assumed]
//     }
//
// `IntakeSettings` and `IntakeProvider` as at the top of IntakeTestSupport.swift.
//
// Behaviour assumed where §9.3 leaves it open:
//  1. The entry list of a day is stored under `intake.entries.<day>` in the store's `defaults`.
//  2. `rebank` of a day whose list key is ABSENT (a restored total, §9.3) leaves the stored rows as
//     they are; only a day whose list exists and is empty has its three rows deleted. Otherwise
//     opening the screen (which rebanks today and yesterday) would erase a restored total.
//  3. `intake_read_at` is `now()` in whole epoch seconds at the change.
//  4. A label longer than 40 characters is cut to 40 (§9.3: "at most 40 characters").
//  5. `replaceRestoredTotal` makes the day's list hold exactly one entry with the restored amounts,
//     after which `restoredTotal(day:)` is nil and the stored totals are unchanged in value.
//
// Synthetic values only.

import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

@MainActor
final class IntakeQuickAddStoreTests: XCTestCase {
    private let suites = IntakeSuites()
    private let id = IntakeFixture.quickAddId

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    private func harness() async throws -> IntakeHarness {
        let h = try await IntakeHarness.make(flag: true, source: .quickAdd, suites: suites)
        try await h.seedUnrelated()
        return h
    }

    /// Only the given day's rows under `noop-intake` may differ between two snapshots.
    private func onlyQuickAddDayChanged(_ day: String) -> (IntakeRow) -> Bool {
        { $0.deviceId == IntakeFixture.quickAddId && $0.day == day }
    }

    func testAddEditAndDeleteRederiveTheDayTotal() async throws {
        let h = try await harness()
        let store = h.quickAdd()
        let today = h.today
        let before = try await h.rows()

        let first = try await store.add(proteinGrams: 30, energyKcal: 150, label: "Fixture shake",
                                        at: h.clock.at(0, hour: 8))
        XCTAssertEqual(first.day, today)
        let second = try await store.add(proteinGrams: 40, energyKcal: 700, label: nil, at: h.clock.at(0, hour: 13))
        let third = try await store.add(proteinGrams: 25, energyKcal: nil, label: nil, at: h.clock.at(0, hour: 14))
        let readAt = Double(Int(h.clock.now.timeIntervalSince1970))
        var value = try await h.value(id, today, "protein_g")
        XCTAssertEqual(value, 95)
        value = try await h.value(id, today, "calories_in")
        XCTAssertEqual(value, 850, "an entry with no energy says nothing about energy")
        value = try await h.value(id, today, "intake_read_at")
        XCTAssertEqual(value, readAt)
        XCTAssertEqual(store.entries(day: today).map(\.id), [first.id, second.id, third.id],
                       "ascending by loggedAt")

        var after = try await h.rows()
        assertOnlyRowsChanged(before: before, after: after, allowed: onlyQuickAddDayChanged(today))
        XCTAssertEqual(after.filter { $0.deviceId == id }.count, 3, "three rows for one day: protein, energy, read time")

        // Edit: the total follows.
        var edited = second
        edited.proteinGrams = 45
        edited.energyKcal = nil
        try await store.update(edited)
        value = try await h.value(id, today, "protein_g")
        XCTAssertEqual(value, 100)
        value = try await h.value(id, today, "calories_in")
        XCTAssertEqual(value, 150)
        XCTAssertEqual(store.entries(day: today).first { $0.id == second.id }?.proteinGrams, 45)

        // Delete: the total follows.
        try await store.delete(id: first.id, day: today)
        value = try await h.value(id, today, "protein_g")
        XCTAssertEqual(value, 70)
        value = try await h.value(id, today, "calories_in")
        XCTAssertNil(value, "no remaining entry says anything about energy: the row is deleted, never zero")
        XCTAssertEqual(store.entries(day: today).map(\.id), [second.id, third.id])

        after = try await h.rows()
        assertOnlyRowsChanged(before: before, after: after, allowed: onlyQuickAddDayChanged(today))
        XCTAssertEqual(IntakeHarness.counts(after)[IntakeFixture.healthId], nil, "nothing under the Health id")
    }

    func testDeletingTheLastEntryRemovesTheDayRows() async throws {
        let h = try await harness()
        let store = h.quickAdd()
        let yesterday = h.clock.day(-1)
        let keep = try await store.add(proteinGrams: 120, energyKcal: 2_400, label: nil, at: h.clock.at(-1, hour: 12))
        let entry = try await store.add(proteinGrams: 30, energyKcal: 150, label: nil, at: h.clock.at(0, hour: 9))
        let before = try await h.rows()
        XCTAssertEqual(before.filter { $0.deviceId == id && $0.day == h.today }.count, 3)

        try await store.delete(id: entry.id, day: h.today)
        let after = try await h.rows()
        XCTAssertEqual(after.filter { $0.deviceId == id && $0.day == h.today }.count, 0,
                       "the day reads not measured: all three rows are gone, none written as zero")
        assertOnlyRowsChanged(before: before, after: after, allowed: onlyQuickAddDayChanged(h.today))
        XCTAssertEqual(after.filter { $0.deviceId == id && $0.day == yesterday }.count, 3, "another day is untouched")
        XCTAssertEqual(store.entries(day: h.today), [])
        XCTAssertEqual(store.entries(day: yesterday).map(\.id), [keep.id])
    }

    func testAnEntryWithNoAmountIsRejected() async throws {
        let h = try await harness()
        let store = h.quickAdd()
        let before = try await h.rows()
        h.defaults.written = []
        do {
            try await store.add(proteinGrams: nil, energyKcal: nil, label: "Fixture shake", at: h.clock.at(0, hour: 9))
            XCTFail("an entry with neither amount must be refused")
        } catch let failure as IntakeQuickAddStore.Failure {
            XCTAssertEqual(failure, .nothingToSave)
        }
        let after = try await h.rows()
        XCTAssertEqual(after, before)
        XCTAssertFalse(h.defaults.written.contains { $0.hasPrefix(IntakeSettings.entriesKeyPrefix) })
    }

    func testInvalidAmountsAreRejectedAndWriteNothing() async throws {
        let h = try await harness()
        let store = h.quickAdd()
        let existing = try await store.add(proteinGrams: 30, energyKcal: 150, label: nil, at: h.clock.at(0, hour: 8))
        let before = try await h.rows()
        let listBefore = h.defaults.string(forKey: IntakeSettings.entriesKeyPrefix + h.today)
        h.defaults.written = []

        let bad: [(Double?, Double?)] = [(-1, nil), (nil, -0.5), (.nan, nil), (nil, .infinity), (100_000.5, nil),
                                         (nil, 100_001), (30, -1), (-.infinity, 150)]
        for (protein, energy) in bad {
            do {
                try await store.add(proteinGrams: protein, energyKcal: energy, label: nil, at: h.clock.at(0, hour: 10))
                XCTFail("refused: \(String(describing: protein)) \(String(describing: energy))")
            } catch let failure as IntakeQuickAddStore.Failure {
                XCTAssertEqual(failure, .invalidAmount, "\(String(describing: protein)) \(String(describing: energy))")
            }
            var edit = existing
            edit.proteinGrams = protein
            edit.energyKcal = energy
            do {
                try await store.update(edit)
                XCTFail("an edit to an invalid amount is refused too")
            } catch let failure as IntakeQuickAddStore.Failure {
                XCTAssertEqual(failure, .invalidAmount)
            }
        }
        let after = try await h.rows()
        XCTAssertEqual(after, before)
        XCTAssertEqual(h.defaults.written, [], "a refused entry writes neither the list nor a total")
        XCTAssertEqual(h.defaults.string(forKey: IntakeSettings.entriesKeyPrefix + h.today), listBefore)

        // Zero and exactly 100 000 are allowed.
        try await store.add(proteinGrams: 0, energyKcal: nil, label: nil, at: h.clock.at(0, hour: 11))
        try await store.add(proteinGrams: nil, energyKcal: 100_000, label: nil, at: h.clock.at(0, hour: 12))
        let protein = try await h.value(id, h.today, "protein_g")
        XCTAssertEqual(protein, 30, "a zero amount is a sample, not an absence")
        let energy = try await h.value(id, h.today, "calories_in")
        XCTAssertEqual(energy, 100_150)
    }

    func testAnEntryKeepsItsDayAcrossAZoneChange() async throws {
        // No zone log yet: the first save starts it with the phone's zone (§7.1).
        let h = try await IntakeHarness.make(flag: true, source: .quickAdd, zoneLog: false, suites: suites)
        var zone = "Pacific/Auckland"
        let store = h.quickAdd(zone: { zone })
        // 13:00 UTC yesterday is 01:00 or 02:00 the next morning in Auckland (UTC+12 or +13):
        // either way, today's date there.
        let instant = h.clock.at(-1, hour: 13)
        let entry = try await store.add(proteinGrams: 30, energyKcal: nil, label: nil, at: instant)
        XCTAssertEqual(entry.day, h.today, "decided at save from the zone log")
        XCTAssertEqual(h.settings.zoneLog.last?.zoneIdentifier, "Pacific/Auckland", "the zone was logged before the save")

        zone = "America/Los_Angeles"
        var edited = entry
        edited.proteinGrams = 35
        try await store.update(edited)
        XCTAssertEqual(store.entries(day: h.today).map(\.id), [entry.id], "never re-keyed")
        XCTAssertEqual(store.entries(day: h.clock.day(-1)), [])
        let today = try await h.value(id, h.today, "protein_g")
        XCTAssertEqual(today, 35)
        let yesterday = try await h.value(id, h.clock.day(-1), "protein_g")
        XCTAssertNil(yesterday)
        // 02:00 UTC tomorrow is tomorrow in Auckland but this evening in Los Angeles (UTC-7 or -8),
        // and the Los Angeles segment, logged at this save, is the one in force for that instant.
        let next = try await store.add(proteinGrams: 10, energyKcal: nil, label: nil, at: h.clock.at(1, hour: 2))
        XCTAssertEqual(next.day, h.today, "a later save is keyed in the zone in force for its instant")
        XCTAssertEqual(store.entries(day: h.today).map(\.id), [entry.id, next.id])
    }

    func testTheListIsWrittenBeforeTheTotal() async throws {
        let h = try await harness()
        // When the list is written, the repository is switched to a second store. A total written
        // after the list lands there; a total written before it would land in the first store.
        let second = try await WhoopStore.inMemory()
        let repo = h.repo
        let prefix = IntakeSettings.entriesKeyPrefix
        var switched = false
        h.defaults.onWrite = { key in
            guard key.hasPrefix(prefix), !switched else { return }
            switched = true
            MainActor.assumeIsolated { repo.setStoreForTesting(second) }
        }
        let store = h.quickAdd()
        try await store.add(proteinGrams: 30, energyKcal: 150, label: nil, at: h.clock.at(0, hour: 9))
        XCTAssertTrue(switched, "the list was written")
        let inFirst = try await h.store.metricSeries(deviceId: id, key: "protein_g", from: h.today, to: h.today)
        let inSecond = try await second.metricSeries(deviceId: id, key: "protein_g", from: h.today, to: h.today)
        XCTAssertEqual(inFirst, [], "nothing was totalled before the list was written")
        XCTAssertEqual(inSecond.map(\.value), [30])
    }

    func testRebankRepairsATotalThatLagsItsList() async throws {
        let h = try await harness()
        let store = h.quickAdd()
        try await store.add(proteinGrams: 30, energyKcal: 150, label: nil, at: h.clock.at(0, hour: 8))
        try await store.add(proteinGrams: 40, energyKcal: 700, label: nil, at: h.clock.at(0, hour: 13))
        // An interruption left the stored total behind its list.
        try await h.seed(id, day: h.today, protein: 30, energy: 150)
        let before = try await h.rows()
        try await store.rebank(day: h.today)
        let protein = try await h.value(id, h.today, "protein_g")
        let energy = try await h.value(id, h.today, "calories_in")
        XCTAssertEqual(protein, 70)
        XCTAssertEqual(energy, 850)
        let after = try await h.rows()
        assertOnlyRowsChanged(before: before, after: after, allowed: onlyQuickAddDayChanged(h.today))

        // Rebanking a day that is already right changes no value.
        let settled = try await h.rows()
        try await store.rebank(day: h.today)
        let again = try await h.rows()
        XCTAssertEqual(again.filter { $0.key != "intake_read_at" }, settled.filter { $0.key != "intake_read_at" })
    }

    func testRebankNeverErasesARestoredTotal() async throws {
        let h = try await harness()
        let store = h.quickAdd()
        // After a restore: the database carries the total, the defaults carry no entry list.
        try await h.seed(id, day: h.today, protein: 95, energy: 1_450, readAt: h.clock.epoch(0, hour: 14))
        let before = try await h.rows()
        try await store.rebank(day: h.today)
        try await store.rebank(day: h.clock.day(-1))
        let after = try await h.rows()
        XCTAssertEqual(after, before, "opening the screen rebanks today and yesterday; a restored total survives it")
    }

    func testARestoredTotalWithNoListCanBeReplaced() async throws {
        let h = try await harness()
        let store = h.quickAdd()
        let day = h.clock.day(-2)
        try await h.seed(id, day: day, protein: 95, energy: 1_450, readAt: h.clock.epoch(-2, hour: 21))
        XCTAssertEqual(store.entries(day: day), [], "no list after a restore")
        let restored = await store.restoredTotal(day: day)
        XCTAssertEqual(restored?.proteinGrams, 95)
        XCTAssertEqual(restored?.energyKcal, 1_450)
        let none = await store.restoredTotal(day: h.today)
        XCTAssertNil(none, "a day with nothing stored has no restored total")

        let before = try await h.rows()
        let entry = try await store.replaceRestoredTotal(day: day)
        XCTAssertEqual(entry.day, day)
        XCTAssertEqual(entry.proteinGrams, 95)
        XCTAssertEqual(entry.energyKcal, 1_450)
        XCTAssertEqual(store.entries(day: day), [entry], "one real entry holding the old amounts")
        let after = await store.restoredTotal(day: day)
        XCTAssertNil(after)
        let protein = try await h.value(id, day, "protein_g")
        XCTAssertEqual(protein, 95)
        let rows = try await h.rows()
        assertOnlyRowsChanged(before: before, after: rows, allowed: onlyQuickAddDayChanged(day))

        // It then proceeds as any edit.
        var edited = entry
        edited.proteinGrams = 100
        try await store.update(edited)
        let edited100 = try await h.value(id, day, "protein_g")
        XCTAssertEqual(edited100, 100)
    }

    func testALabelStaysOnThePhoneAndIsCutTo40Characters() async throws {
        let h = try await harness()
        let store = h.quickAdd()
        let long = String(repeating: "Fixture shake ", count: 6)
        let entry = try await store.add(proteinGrams: 30, energyKcal: 150, label: long, at: h.clock.at(0, hour: 8))
        XCTAssertEqual(entry.label?.count, 40)
        XCTAssertEqual(store.entries(day: h.today).first?.label, entry.label)
        let rows = try await h.rows()
        XCTAssertTrue(rows.filter { $0.deviceId == id }.allSatisfy { IntakeFixture.intakeKeys.contains($0.key) },
                      "nothing but the three keys is stored in the database")
    }

    func testEveryWriteRefreshesTheProvider() async throws {
        let h = try await harness()
        let store = h.quickAdd()
        let start = h.provider.revision
        let entry = try await store.add(proteinGrams: 30, energyKcal: 150, label: nil, at: h.clock.at(0, hour: 8))
        await h.provider.refresh()
        XCTAssertEqual(h.provider.day(h.today)?.protein?.value, 30)
        XCTAssertGreaterThan(h.provider.revision, start)
        try await store.delete(id: entry.id, day: h.today)
        await h.provider.refresh()
        XCTAssertNil(h.provider.day(h.today), "the deleted day reads not measured")
    }
}
