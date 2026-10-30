import XCTest
import Foundation
import WhoopStore
@testable import Strand

/// #833/v7.7.2 (Apple Health per-source freeze): the load-once contract behind the AppleHealthView re-mount
/// cache. On macOS the NavigationSplitView detail is keyed with `.id`, so every sidebar switch cold-mounts the
/// screen and tears down its `@State`; without the repo-level cache each visit re-ran the whole apple-health
/// history read on the @MainActor, which is the freeze. The fix parks the snapshot on the long-lived
/// `Repository` (`performAppleHealthLoad`), so a same-state re-mount RESTORES it in-memory instead of
/// re-querying.
///
/// These tests drive the shared seam directly (the view just copies its result into `@State`, which can't be
/// exercised headlessly) and pin two things:
///   1. Load-once: TWO `allowCache: true` loads at an UNCHANGED `refreshSeq` fire the heavy store read exactly
///      ONCE (the second short-circuits from cache). This is the regression guard for the freeze.
///   2. Invalidation: nulling the cache (what the import / delete handlers do, since body-composition series
///      live in metricSeries OUTSIDE refresh()'s diff) forces the next load to re-read.
@MainActor
final class AppleHealthCacheTests: XCTestCase {

    private let appleSource = "apple-health"

    func testStepOnlyImportReachesDailyTotalsDetailChartsAndInvalidatesEmptyCache() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: "my-whoop")
        repo.setStoreForTesting(store)
        let empty = await repo.performAppleHealthLoad(seriesKeys: ["steps"], allowCache: true)
        XCTAssertFalse(empty.hasAnyData)
        let day = Repository.localDayKey(Date())
        try await store.upsertAppleDailySteps([(day: day, steps: 6500)], deviceId: appleSource)
        repo.invalidateWorkoutViews()

        let snapshot = await repo.performAppleHealthLoad(seriesKeys: ["steps"], allowCache: true)
        XCTAssertEqual(snapshot.appleRows.first?.steps, 6500)
        XCTAssertEqual(snapshot.series["steps"]?.map(\.value), [6500])
        XCTAssertTrue(snapshot.hasAnyData)
        let resolved = await repo.resolvedSeries(key: "steps", source: appleSource, from: day, to: day)
        XCTAssertEqual(resolved.points.first?.value, 6500)
    }

    /// Seed a handful of apple-health body-composition + vitals series days into an in-memory store and hand it
    /// to a fresh Repository. Body-comp keys (weight/body_fat/lean_mass/bmi/vo2max) are the ones that live ONLY
    /// in metricSeries, so they exercise the exact staleness path the invalidation fix guards.
    private func makeRepo() async throws -> Repository {
        let store = try await WhoopStore.inMemory()
        try await store.upsertDevice(id: "my-whoop", mac: nil, name: "WHOOP")

        var rows: [MetricPoint] = []
        let days = ["2026-06-24", "2026-06-25", "2026-06-26", "2026-06-27", "2026-06-28"]
        for (i, day) in days.enumerated() {
            rows.append(MetricPoint(day: day, key: "weight", value: 74.0 + Double(i) * 0.1))
            rows.append(MetricPoint(day: day, key: "body_fat", value: 18.0 - Double(i) * 0.1))
            rows.append(MetricPoint(day: day, key: "steps", value: 8_000 + Double(i) * 100))
            rows.append(MetricPoint(day: day, key: "hrv", value: 60 + Double(i)))
        }
        _ = try await store.upsertMetricSeries(rows, deviceId: appleSource)

        let repo = Repository(deviceId: "my-whoop")
        repo.setStoreForTesting(store)
        return repo
    }

    /// The keys AppleHealthView pulls, so the seam reads the same set the screen does.
    private let seriesKeys = [
        "steps", "active_kcal", "vo2max",
        "resting_hr", "hrv", "spo2", "resp_rate", "asleep_min",
        "weight", "body_fat", "lean_mass", "bmi"
    ]

    func testWorkoutsOnlyImportIsDataAndSurvivesCapturedActivityMerge() async throws {
        let store = try await WhoopStore.inMemory()
        let start = Int(Date().timeIntervalSince1970) - 7200
        let health = WorkoutRow(startTs: start, endTs: start + 3600, sport: "Strength Training",
                                source: "apple-health", durationS: 3600, energyKcal: nil,
                                avgHr: nil, maxHr: nil, strain: nil, distanceM: nil,
                                zonesJSON: nil, notes: nil, steps: nil)
        let captured = WorkoutRow(startTs: start, endTs: start + 3600, sport: "Strength Training",
                                  source: "manual", durationS: 3600, energyKcal: nil,
                                  avgHr: 120, maxHr: 155, strain: 25, distanceM: nil,
                                  zonesJSON: nil, notes: nil, steps: nil)
        try await store.upsertWorkouts([health], deviceId: appleSource)
        try await store.upsertWorkouts([captured], deviceId: "my-whoop")
        let repo = Repository(deviceId: "my-whoop")
        repo.setStoreForTesting(store)

        let activities = await repo.workoutRows()
        XCTAssertEqual(activities.count, 1, "the activity list still merges the same workout")
        XCTAssertEqual(activities.first?.source, "manual")
        let snapshot = await repo.performAppleHealthLoad(seriesKeys: seriesKeys, allowCache: false)
        XCTAssertEqual(snapshot.workoutCount, 1, "the source page must still report the stored Health import")
        XCTAssertTrue(snapshot.appleRows.isEmpty)
        XCTAssertTrue(snapshot.series.values.allSatisfy(\.isEmpty))
        XCTAssertTrue(snapshot.hasAnyData, "workout-only access must not show the generic empty state")
    }

    func testNoHealthWorkoutsIsEmptyEvenWithAnUnrelatedCapturedWorkout() async throws {
        let store = try await WhoopStore.inMemory()
        let start = Int(Date().timeIntervalSince1970) - 7200
        let captured = WorkoutRow(startTs: start, endTs: start + 3600, sport: "Strength Training",
                                  source: "manual", durationS: 3600, energyKcal: nil,
                                  avgHr: 120, maxHr: 155, strain: 25, distanceM: nil,
                                  zonesJSON: nil, notes: nil, steps: nil)
        try await store.upsertWorkouts([captured], deviceId: "my-whoop")
        let repo = Repository(deviceId: "my-whoop")
        repo.setStoreForTesting(store)
        let snapshot = await repo.performAppleHealthLoad(seriesKeys: seriesKeys, allowCache: false)
        XCTAssertEqual(snapshot.workoutCount, 0)
        XCTAssertFalse(snapshot.hasAnyData)
    }

    func testWorkoutImportInvalidatesCachedCountWithoutDailyMetricChanges() async throws {
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: "my-whoop")
        repo.setStoreForTesting(store)
        let empty = await repo.performAppleHealthLoad(seriesKeys: seriesKeys, allowCache: true)
        XCTAssertEqual(empty.workoutCount, 0)
        let previousSequence = repo.refreshSeq
        let start = Int(Date().timeIntervalSince1970) - 7200
        let row = WorkoutRow(startTs: start, endTs: start + 3600, sport: "Strength Training",
                             source: "apple-health", durationS: 3600, energyKcal: nil,
                             avgHr: nil, maxHr: nil, strain: nil, distanceM: nil,
                             zonesJSON: nil, notes: nil, steps: nil)
        try await store.upsertWorkouts([row], deviceId: appleSource)
        repo.invalidateWorkoutViews()

        XCTAssertGreaterThan(repo.refreshSeq, previousSequence)
        let updated = await repo.performAppleHealthLoad(seriesKeys: seriesKeys, allowCache: true)
        XCTAssertEqual(updated.workoutCount, 1)
        XCTAssertTrue(updated.hasAnyData)
    }

    /// The core regression guard: two same-state re-mount loads run the heavy store read ONCE. The second call
    /// (unchanged `refreshSeq`, same dayKey, cache present) must short-circuit and NOT bump the fire tally.
    func testSecondLoadAtUnchangedSeqShortCircuitsFromCache() async throws {
        let repo = try await makeRepo()

        // First cold-mount: genuine heavy load, populates the cache and returns real data.
        let first = await repo.performAppleHealthLoad(seriesKeys: seriesKeys, allowCache: true)
        XCTAssertEqual(repo.loadFireCounts["appleHealth"], 1, "the first load must run the heavy read")
        XCTAssertEqual(first.series["weight"]?.count, 5, "the body-composition series loaded")
        XCTAssertEqual(first.series["weight"]?.last?.value ?? 0, 74.4, accuracy: 0.001)

        // Second same-state re-mount: MUST restore from cache, NOT re-read the store.
        let second = await repo.performAppleHealthLoad(seriesKeys: seriesKeys, allowCache: true)
        XCTAssertEqual(repo.loadFireCounts["appleHealth"], 1,
                       "the same-state re-mount must short-circuit from cache (the freeze regression guard)")
        // Restored snapshot is identical to the first load's result.
        XCTAssertEqual(second.series["weight"]?.map(\.value), first.series["weight"]?.map(\.value))
        XCTAssertEqual(second.appleRows.count, first.appleRows.count)
    }

    /// `allowCache: false` (the live-sync path, Enable / Sync now) always re-reads even at an unchanged seq, so
    /// a fresh sync's data is never masked by the cache.
    func testDirectLoadAlwaysReReadsRegardlessOfCache() async throws {
        let repo = try await makeRepo()
        _ = await repo.performAppleHealthLoad(seriesKeys: seriesKeys, allowCache: true)
        XCTAssertEqual(repo.loadFireCounts["appleHealth"], 1)

        // A non-cache load re-fires even though the seq is unchanged and a cache exists.
        _ = await repo.performAppleHealthLoad(seriesKeys: seriesKeys, allowCache: false)
        XCTAssertEqual(repo.loadFireCounts["appleHealth"], 2,
                       "a direct (non-cached) load must always re-read so a live sync is never masked")
    }

    /// Invalidation contract: dropping the cache (exactly what the Apple Health import / delete handlers do,
    /// because body-composition series live outside refresh()'s diff and refresh() may not bump `refreshSeq`)
    /// forces the next `allowCache: true` load to re-read the store, so post-import / post-delete data is fresh.
    func testNulledCacheForcesReReadEvenAtUnchangedSeq() async throws {
        let repo = try await makeRepo()
        _ = await repo.performAppleHealthLoad(seriesKeys: seriesKeys, allowCache: true)
        _ = await repo.performAppleHealthLoad(seriesKeys: seriesKeys, allowCache: true)
        XCTAssertEqual(repo.loadFireCounts["appleHealth"], 1, "cached, so still one heavy read")

        // Mimic the import / delete handlers' invalidation (they set exactly these two).
        repo.appleHealthCache = nil
        repo.appleHealthLoadedSeq = -1

        // Same `refreshSeq`, but the cache is gone → the next load MUST re-read.
        _ = await repo.performAppleHealthLoad(seriesKeys: seriesKeys, allowCache: true)
        XCTAssertEqual(repo.loadFireCounts["appleHealth"], 2,
                       "after invalidation the next load must re-read, so post-import/delete data is fresh")
    }
}
