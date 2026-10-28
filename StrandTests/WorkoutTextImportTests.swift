import XCTest
import StrandImport
import WhoopStore
@testable import Strand

final class WorkoutTextImportTests: XCTestCase {
    func testSharedTextPreservesUnitsNotesDateAndUnquantifiedExercise() {
        let parsed = WorkoutTextImport.parse("""
        Upper Mix 🏋️
        Thursday, Jan 1, 2026 at 6:15pm
        Rowing Machine
        Dumbbell Press
        "One weight in each hand. Keep the logged weight as written."
        Set 1: 12.5 kg x 8
        Set 2: 15 kg x 6
        Pull Up
        "Controlled reps."
        Set 1: bodyweight x 10
        @hevyapp
        https://example.invalid/workout/test
        /fitness-coach
        """, zone: TimeZone(secondsFromGMT: 19_800)!)
        XCTAssertTrue(parsed.warnings.isEmpty)
        XCTAssertEqual(parsed.title, "Upper Mix 🏋️")
        XCTAssertEqual(parsed.unquantifiedExercises, ["Rowing Machine"])
        XCTAssertEqual(parsed.sets.map(\.reps), [8, 6, 10])
        XCTAssertEqual(parsed.sets.map(\.weightKg), [12.5, 15, nil])
        XCTAssertEqual(parsed.sets[0].note, "One weight in each hand. Keep the logged weight as written.")
        XCTAssertNil(parsed.sets[1].note)
        XCTAssertEqual(parsed.sets[2].note, "Controlled reps.")
        let date = try! XCTUnwrap(parsed.date)
        XCTAssertEqual(date, ISO8601DateFormatter().date(from: "2026-01-01T12:45:00Z"))
        let session = parsed.session(start: date, end: nil)
        XCTAssertEqual(session.volumeLoadKg, 190) // no doubling based on prose
        XCTAssertNil(session.durationS)
        XCTAssertTrue(session.note!.contains("Rowing Machine"))
    }

    func testAmbiguousOrUnboundedSetIsNotSilentlyAccepted() {
        for line in ["Set 1: 20 x 10", "Set 1: 20 kg x 8-10", "Set 1: 1 kg x 999999999999999999999", "Set 1: 20 kg x 10 extra"] {
            let parsed = WorkoutTextImport.parse("Squat\n" + line)
            XCTAssertTrue(parsed.sets.isEmpty)
            XCTAssertEqual(parsed.warnings, [line])
        }
    }

    func testPoundsAreConvertedOnce() {
        let parsed = WorkoutTextImport.parse("Curl\nSet 1: 10 lb × 5")
        XCTAssertEqual(parsed.sets[0].weightKg!, 4.5359237, accuracy: 0.0000001)
    }
}

@MainActor
final class PersonalLiftingImportTests: XCTestCase {
    func testRepeatImportKeepsEditsAndDoesNotDuplicateSets() async throws {
        let store = try await WhoopStore.inMemory()
        let result = LiftingImporter.parseHevy(text: """
        title,start_time,end_time,exercise_title,set_type,weight_kg,reps,exercise_notes
        Sample,2026-01-01 10:00,2026-01-01 11:00,Press,warmup,10,8,Easy
        Sample,2026-01-01 10:00,2026-01-01 11:00,Press,normal,20,6,Steady
        """, zone: TimeZone(secondsFromGMT: 0)!)
        let first = try await PersonalLiftingImport.save(result.sessions[0], store: store)
        XCTAssertTrue(first)
        let id = "lift-import:1767261600"
        var sets = try await store.liftSets(sessionId: id)
        XCTAssertEqual(sets.count, 2)
        XCTAssertTrue(sets[0].isWarmup)
        XCTAssertEqual(sets[1].note, "Steady")
        sets[1].note = "Edited locally"
        try await store.upsertLiftSets(sets)
        let repeated = try await PersonalLiftingImport.save(result.sessions[0], store: store)
        XCTAssertFalse(repeated)
        sets = try await store.liftSets(sessionId: id)
        XCTAssertEqual(sets.count, 2)
        XCTAssertEqual(sets[1].note, "Edited locally")
    }

    func testUnknownDurationDoesNotInventAWorkoutInterval() async throws {
        let store = try await WhoopStore.inMemory()
        let p = WorkoutTextImport.parse("Squat\nSet 1: 40 kg x 5")
        let start = Date(timeIntervalSince1970: 1000)
        let added = try await PersonalLiftingImport.save(p.session(start: start, end: nil), store: store)
        XCTAssertTrue(added)
        let sessions = try await store.liftSessions(deviceId: "lifting", fromTs: 0, toTs: 2000)
        XCTAssertEqual(sessions.count, 1)
        let workouts = try await store.workouts(deviceId: "lifting", from: 0, to: 2000, limit: 100)
        XCTAssertTrue(workouts.isEmpty)
    }

    func testHealthAndCsvSummaryCollapseToOneWithCapturedSignalsKept() {
        let health = WorkoutRow(startTs: 1000, endTs: 4600, sport: LiftingImporter.sport, source: "apple-health",
                                durationS: 3600, energyKcal: 200, avgHr: 110, maxHr: 140, strain: 22,
                                distanceM: nil, zonesJSON: nil, notes: nil, steps: nil)
        let relay = WorkoutRow(startTs: 1010, endTs: 4610, sport: LiftingImporter.sport, source: "apple-health",
                               durationS: 3600, energyKcal: 200, avgHr: 110, maxHr: 140, strain: 22,
                               distanceM: nil, zonesJSON: nil, notes: nil, steps: nil)
        let lifting = WorkoutRow(startTs: 1000, endTs: 4600, sport: LiftingImporter.sport, source: "lifting",
                                 durationS: 3600, energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil,
                                 distanceM: nil, zonesJSON: nil, notes: "Lifting details", steps: nil)
        let kept = WorkoutSource.dedupCrossSource([health, relay, lifting])
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(kept[0].strain, 22)
        XCTAssertEqual(kept[0].avgHr, 110)
        let merged = HealthWorkoutReadMerge.merge([lifting], prior: [health])
        XCTAssertEqual(merged[0].strain, 22)
        XCTAssertEqual(merged[0].avgHr, 110)
        XCTAssertTrue(HealthWorkoutReadMerge.merge([], prior: [health]).isEmpty)
    }
}
