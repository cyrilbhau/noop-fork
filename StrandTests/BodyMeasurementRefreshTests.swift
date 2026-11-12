import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

// Stage 1 (weigh-in and scorecard), ruling R32 of specification §18. Written before the fix, from the
// ruling and from the existing code the fix sits on (`Repository.refresh()`, `LabMarkerStore`, the
// save and delete paths of `LabBookView`), without reading the provider's implementation.
//
// The finding: a Lab Book write changes none of the caches `Repository.refresh()` compares, so the
// refresh returns at its "unchanged" guard and `refreshSeq` does not move. A provider that listens
// for `refreshSeq` never hears of the write.
//
// API ASSUMED BY THESE TESTS
//
//  1. A provider made with the injectable initialiser
//         BodyMeasurementProvider(repository:defaults:today:)
//     follows its repository exactly as the app's live provider does: after EVERY completed
//     `Repository.refresh()`, including one that found its caches unchanged, the provider's snapshot
//     is current. The test never calls `provider.refresh()`.
//  2. That follow-up may be asynchronous. These tests wait up to `followUpTimeout` for a positive
//     result and wait `settleInterval` before asserting that something did NOT happen.
//  3. With the flag on, `revision` increases when the resolved snapshot changed, and does not
//     increase when a repository refresh changed nothing.
//  4. With the flag off the follow-up does no work: no store read, no profile write, and no
//     `revision` change. "No store read" is observed through `candidates(_:)`, which stays the
//     snapshot the provider held before (see the note above the last test).
//  5. The existing surface: `current(_:consumer:)`, `estimateWeightKg()`, `estimateWaistCm()`,
//     `revision`, the profile keys `profile.weightKg` and `profile.waistCm`, and the flag key
//     `noop.cutScorecardEnabled`.
//
// Dates are relative to the real clock (ruling R31). Synthetic values only.
@MainActor
final class BodyMeasurementRefreshTests: XCTestCase {

    // MARK: - Harness

    /// Records which keys were written, so "never written" can be told from "written with the same value".
    private final class RecordingDefaults: UserDefaults {
        var written: [String] = []
        override func set(_ value: Any?, forKey defaultName: String) {
            written.append(defaultName)
            super.set(value, forKey: defaultName)
        }
        override func set(_ value: Double, forKey defaultName: String) {
            written.append(defaultName)
            super.set(value, forKey: defaultName)
        }
        override func set(_ value: Float, forKey defaultName: String) {
            written.append(defaultName)
            super.set(value, forKey: defaultName)
        }
        override func set(_ value: Int, forKey defaultName: String) {
            written.append(defaultName)
            super.set(value, forKey: defaultName)
        }
        override func removeObject(forKey defaultName: String) {
            written.append(defaultName)
            super.removeObject(forKey: defaultName)
        }
        func wroteProfile() -> Bool { written.contains { $0 == "profile.weightKg" || $0 == "profile.waistCm" } }
    }

    /// A clock two days behind the real one, fixed for the length of a test.
    private struct Clock {
        let start: Date         // 00:00 UTC of "today"
        init() {
            let seconds = Int(Date().timeIntervalSince1970) - 2 * 86_400
            start = Date(timeIntervalSince1970: Double(seconds - seconds % 86_400))
        }
        var today: String { day(0) }
        func day(_ offset: Int) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: start.addingTimeInterval(Double(offset) * 86_400))
        }
        /// 07:00 UTC on `day(offset)`, epoch seconds.
        func instant(_ offset: Int) -> Int { Int(start.timeIntervalSince1970) + offset * 86_400 + 7 * 3_600 }
    }

    private struct Harness {
        let store: WhoopStore
        let repo: Repository
        let defaults: RecordingDefaults
        let provider: BodyMeasurementProvider
    }

    private let weightKey = "profile.weightKg"
    private let waistKey = "profile.waistCm"
    private let followUpTimeout: TimeInterval = 3.0
    private let settleInterval: UInt64 = 400_000_000

    private var suites: [String] = []

    override func tearDown() {
        for name in suites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        suites = []
        super.tearDown()
    }

    private func makeDefaults(flag: Bool) throws -> RecordingDefaults {
        let name = "BodyMeasurementRefreshTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(RecordingDefaults(suiteName: name))
        suites.append(name)
        if flag { defaults.set(true, forKey: "noop.cutScorecardEnabled") }
        defaults.written = []
        return defaults
    }

    private func makeHarness(today: String, flag: Bool) async throws -> Harness {
        let defaults = try makeDefaults(flag: flag)
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: "my-whoop")
        repo.setStoreForTesting(store)
        let provider = BodyMeasurementProvider(repository: repo, defaults: defaults, today: { today })
        return Harness(store: store, repo: repo, defaults: defaults, provider: provider)
    }

    private func labRow(_ key: String, day: String, takenAt: Int, value: Double) -> LabMarkerRow {
        LabMarkerRow(id: "\(key)-\(takenAt)-0A1B2C3D", deviceId: "my-whoop", markerKey: key,
                     category: "bodyMeasurement", day: day, takenAt: takenAt, value: value, valueText: nil,
                     unit: key == "weight" ? "kg" : "cm", source: "manual", note: nil, referenceText: nil)
    }

    /// What `LabBookView.save` does (`LabBookView.swift:475-479`): the store write, then a repository refresh.
    private func labBookSave(_ h: Harness, _ rows: [LabMarkerRow]) async throws {
        try await h.store.upsertLabMarkers(rows)
        await h.repo.refresh()
    }

    /// What `LabBookView.delete` does (`LabBookView.swift:482-486`).
    private func labBookDelete(_ h: Harness, id: String) async throws {
        let deleted = try await h.store.deleteLabMarker(id: id)
        XCTAssertTrue(deleted, "the fixture row \(id) was not stored")
        await h.repo.refresh()
    }

    /// Polls until `condition` holds or the timeout passes. The main actor is free between polls.
    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(followUpTimeout)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return true
    }

    /// Long enough for a follow-up that was going to happen to have happened.
    private func settle() async {
        try? await Task.sleep(nanoseconds: settleInterval)
    }

    /// The repository's first refresh always publishes. Run it before the write under test, so the
    /// refresh after the write is the one that finds its caches unchanged.
    private func prime(_ h: Harness) async {
        await h.repo.refresh()
        await settle()
    }

    private func profileDouble(_ h: Harness, _ key: String) -> Double? {
        h.defaults.object(forKey: key) as? Double
    }

    // MARK: - Flag on: a Lab Book write reaches every reader

    /// A weight saved through the Lab Book path, and then corrected through it, is the value of the
    /// display, of the estimates and of the profile mirror, with no call to `provider.refresh()`.
    func testLabBookWeightWriteReachesDisplayEstimateAndMirrorWithoutAProviderRefresh() async throws {
        let clock = Clock()
        let h = try await makeHarness(today: clock.today, flag: true)
        h.defaults.set(80.0, forKey: weightKey)
        await prime(h)

        let row = labRow("weight", day: clock.today, takenAt: clock.instant(0), value: 99.2)
        try await labBookSave(h, [row])

        let followed = await waitUntil {
            h.provider.current(.weight, consumer: .display)?.value == 99.2
                && self.profileDouble(h, self.weightKey) == 99.2
        }
        XCTAssertTrue(followed, "the provider did not follow a repository refresh that found its caches unchanged")
        XCTAssertEqual(h.provider.current(.weight, consumer: .display),
                       ResolvedBodyMeasurement(kind: .weight, value: 99.2, source: .labBook, day: clock.today))
        XCTAssertEqual(h.provider.current(.weight, consumer: .estimate)?.value, 99.2)
        XCTAssertEqual(h.provider.estimateWeightKg(), 99.2)
        XCTAssertEqual(profileDouble(h, weightKey), 99.2, "the profile mirror")

        // The same reading corrected in the Lab Book editor: same natural key, another value.
        var corrected = row
        corrected.value = 98.8
        try await labBookSave(h, [corrected])

        let followedAgain = await waitUntil {
            h.provider.current(.weight, consumer: .display)?.value == 98.8
                && self.profileDouble(h, self.weightKey) == 98.8
        }
        XCTAssertTrue(followedAgain, "the provider did not follow a Lab Book correction")
        XCTAssertEqual(h.provider.current(.weight, consumer: .estimate)?.value, 98.8)
        XCTAssertEqual(h.provider.estimateWeightKg(), 98.8)
        XCTAssertEqual(profileDouble(h, weightKey), 98.8)
    }

    /// A first waist reading: a profile waist of 0 (never set, or stored as 0) becomes the reading.
    func testFirstLabBookWaistReplacesAProfileWaistOfZeroWithoutAProviderRefresh() async throws {
        for storedZero in [false, true] {
            let label = storedZero ? "profile waist stored as 0" : "profile waist never set"
            let clock = Clock()
            let h = try await makeHarness(today: clock.today, flag: true)
            h.defaults.set(80.0, forKey: weightKey)
            if storedZero { h.defaults.set(0.0, forKey: waistKey) }
            await prime(h)
            XCTAssertEqual(h.provider.estimateWaistCm(), 0, "\(label): before the reading")

            try await labBookSave(h, [labRow("waist", day: clock.today, takenAt: clock.instant(0), value: 96.0)])

            let followed = await waitUntil {
                h.provider.current(.waist, consumer: .display)?.value == 96.0
                    && self.profileDouble(h, self.waistKey) == 96.0
            }
            XCTAssertTrue(followed, "\(label): the provider did not follow the repository refresh")
            XCTAssertEqual(h.provider.current(.waist, consumer: .display),
                           ResolvedBodyMeasurement(kind: .waist, value: 96.0, source: .labBook, day: clock.today), label)
            XCTAssertEqual(h.provider.current(.waist, consumer: .estimate)?.value, 96.0, label)
            XCTAssertEqual(h.provider.estimateWaistCm(), 96.0, label)
            XCTAssertEqual(profileDouble(h, waistKey), 96.0, "\(label): the profile mirror")
            XCTAssertEqual(profileDouble(h, weightKey), 80.0, "\(label): a waist reading does not touch the weight")
        }
    }

    /// A Lab Book delete moves every reader back to the reading before it.
    func testLabBookDeleteReachesDisplayEstimateAndMirrorWithoutAProviderRefresh() async throws {
        let clock = Clock()
        let h = try await makeHarness(today: clock.today, flag: true)
        h.defaults.set(80.0, forKey: weightKey)
        await prime(h)
        let earlier = labRow("weight", day: clock.day(-7), takenAt: clock.instant(-7), value: 100.0)
        let latest = labRow("weight", day: clock.today, takenAt: clock.instant(0), value: 99.2)
        try await labBookSave(h, [earlier, latest])
        let saved = await waitUntil { self.profileDouble(h, self.weightKey) == 99.2 }
        XCTAssertTrue(saved, "the provider did not follow the save this test starts from")

        try await labBookDelete(h, id: latest.id)

        let followed = await waitUntil {
            h.provider.current(.weight, consumer: .display)?.value == 100.0
                && self.profileDouble(h, self.weightKey) == 100.0
        }
        XCTAssertTrue(followed, "the provider did not follow a Lab Book delete")
        XCTAssertEqual(h.provider.current(.weight, consumer: .display),
                       ResolvedBodyMeasurement(kind: .weight, value: 100.0, source: .labBook, day: clock.day(-7)))
        XCTAssertEqual(h.provider.current(.weight, consumer: .estimate)?.value, 100.0)
        XCTAssertEqual(h.provider.estimateWeightKg(), 100.0)
        XCTAssertEqual(profileDouble(h, weightKey), 100.0, "the profile mirror")
    }

    // MARK: - Flag on: revision

    /// `revision` is what the views re-resolve on. It moves when the snapshot changed and stays when
    /// a repository refresh changed nothing, so an unchanged refresh costs no view reload.
    func testRevisionIncreasesWhenTheSnapshotChangedAndNotWhenARefreshChangedNothing() async throws {
        let clock = Clock()
        let h = try await makeHarness(today: clock.today, flag: true)
        h.defaults.set(80.0, forKey: weightKey)
        await prime(h)
        let atStart = h.provider.revision

        let row = labRow("weight", day: clock.today, takenAt: clock.instant(0), value: 99.2)
        try await labBookSave(h, [row])
        let moved = await waitUntil { h.provider.revision > atStart }
        XCTAssertTrue(moved, "revision did not increase after a Lab Book save (was \(atStart), is \(h.provider.revision))")
        await settle()
        let afterSave = h.provider.revision
        XCTAssertGreaterThan(afterSave, atStart)

        // Three refreshes with nothing new in the store.
        for _ in 0..<3 { await h.repo.refresh() }
        await settle()
        XCTAssertEqual(h.provider.revision, afterSave, "a refresh that changed nothing increased revision")
        XCTAssertEqual(h.provider.current(.weight, consumer: .display)?.value, 99.2)

        try await labBookDelete(h, id: row.id)
        let movedAgain = await waitUntil { h.provider.revision > afterSave }
        XCTAssertTrue(movedAgain, "revision did not increase after a Lab Book delete")
    }

    // MARK: - Flag off

    /// With the flag off the same writes change nothing: no profile write, the estimates and the
    /// display as before, and no `revision` change.
    func testFlagOffLabBookWritesChangeNoReaderAndWriteNoProfileValue() async throws {
        let clock = Clock()
        let h = try await makeHarness(today: clock.today, flag: false)
        h.defaults.set(80.0, forKey: weightKey)
        h.defaults.set(90.0, forKey: waistKey)
        await prime(h)
        h.defaults.written = []
        let displayBefore = h.provider.current(.weight, consumer: .display)
        let waistBefore = h.provider.current(.waist, consumer: .estimate)
        let revisionBefore = h.provider.revision
        XCTAssertEqual(h.provider.estimateWeightKg(), 80.0)
        XCTAssertEqual(h.provider.estimateWaistCm(), 90.0)

        let weight = labRow("weight", day: clock.today, takenAt: clock.instant(0), value: 99.2)
        let waist = labRow("waist", day: clock.today, takenAt: clock.instant(0), value: 96.0)
        try await labBookSave(h, [weight, waist])
        await settle()
        var corrected = weight
        corrected.value = 98.8
        try await labBookSave(h, [corrected])
        await settle()
        try await labBookDelete(h, id: waist.id)
        await settle()

        XCTAssertFalse(h.defaults.wroteProfile(), "the profile keys were written with the flag off: \(h.defaults.written)")
        XCTAssertEqual(profileDouble(h, weightKey), 80.0)
        XCTAssertEqual(profileDouble(h, waistKey), 90.0)
        XCTAssertEqual(h.provider.estimateWeightKg(), 80.0)
        XCTAssertEqual(h.provider.estimateWaistCm(), 90.0)
        XCTAssertEqual(h.provider.current(.weight, consumer: .display), displayBefore)
        XCTAssertEqual(h.provider.current(.weight, consumer: .estimate),
                       ResolvedBodyMeasurement(kind: .weight, value: 80.0, source: .profile, day: nil))
        XCTAssertEqual(h.provider.current(.waist, consumer: .estimate), waistBefore)
        XCTAssertEqual(h.provider.revision, revisionBefore, "with the flag off no view is asked to reload")
    }

    private func appleDaily(_ day: String, weightKg: Double) -> AppleDaily {
        AppleDaily(day: day, steps: nil, activeKcal: nil, basalKcal: nil, vo2max: nil, avgHr: nil,
                   maxHr: nil, walkingHr: nil, weightKg: weightKg)
    }

    /// An Apple Health weight and a Lab Book weight and waist, written as the app writes them, then
    /// one repository refresh.
    private func writeEverySource(_ h: Harness, _ clock: Clock) async throws {
        try await h.store.upsertAppleDaily([appleDaily(clock.day(-1), weightKg: 101.5)], deviceId: "apple-health")
        try await labBookSave(h, [labRow("weight", day: clock.today, takenAt: clock.instant(0), value: 99.2),
                                  labRow("waist", day: clock.today, takenAt: clock.instant(0), value: 96.0)])
    }

    // Ruling R32: "With the flag off none of this does any work: no store read".
    //
    // A store read cannot be observed directly from this bundle: the store has no read hook, and a
    // GRDB statement trace needs GRDB linked into StrandTests, which `project.yml` does not do (a
    // version of this test that used one compiled and failed at link). What is observed instead is
    // the consequence. `candidates(_:)` is a synchronous read of the snapshot the provider last
    // took, so a provider that read nothing still holds the snapshot it held before. This catches a
    // follow-up that reads and keeps what it read. It cannot catch one that reads and discards the
    // result; that is left to review.

    /// With the flag off the provider's snapshot is untouched by a repository refresh; with the
    /// flag on the same writes arrive in it, which shows the observation can see a read.
    func testFlagOffProviderTakesNoSnapshotAfterARepositoryRefresh() async throws {
        let clock = Clock()

        let on = try await makeHarness(today: clock.today, flag: true)
        await prime(on)
        try await writeEverySource(on, clock)
        let arrived = await waitUntil {
            on.provider.candidates(.weight).labBook.count == 1
                && on.provider.candidates(.weight).appleHealth.count == 1
                && on.provider.candidates(.waist).labBook.count == 1
        }
        XCTAssertTrue(arrived, "flag on: the provider's snapshot did not follow the repository refresh")

        let off = try await makeHarness(today: clock.today, flag: false)
        off.defaults.set(80.0, forKey: weightKey)
        await prime(off)
        off.defaults.written = []
        XCTAssertTrue(off.provider.candidates(.weight).labBook.isEmpty, "before any write")
        XCTAssertTrue(off.provider.candidates(.weight).appleHealth.isEmpty, "before any write")
        try await writeEverySource(off, clock)
        await settle()
        await off.repo.refresh()
        await settle()

        XCTAssertTrue(off.provider.candidates(.weight).labBook.isEmpty,
                      "flag off: the provider read the Lab Book weights after a repository refresh")
        XCTAssertTrue(off.provider.candidates(.waist).labBook.isEmpty,
                      "flag off: the provider read the Lab Book waists after a repository refresh")
        XCTAssertTrue(off.provider.candidates(.weight).appleHealth.isEmpty,
                      "flag off: the provider read the Apple Health weights after a repository refresh")
        XCTAssertFalse(off.defaults.wroteProfile())
    }
}
