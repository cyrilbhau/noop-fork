import Foundation
import GRDB

extension WhoopStore {
    /// Append a reviewed lifting import atomically. Re-imports never replace an existing log or its edits.
    /// Uses the established lift/workout schema; the personal Apple import UI owns this entry point.
    @discardableResult
    public func appendImportedLift(session: LiftSessionRow, sets: [LiftSetRow], workout: WorkoutRow) async throws -> Bool {
        guard session.deviceId == "lifting", session.id == "lift-import:\(session.startTs)",
              session.sport == "Strength Training", workout.source == "lifting",
              workout.startTs == session.startTs, workout.sport == session.sport,
              workout.strain == nil, !sets.isEmpty,
              sets.enumerated().allSatisfy({ index, row in
                  row.id == "\(session.id):\(index)" && row.sessionId == session.id && row.deviceId == session.deviceId
              }) else {
            throw NSError(domain: "LiftLogImport", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid lifting import."])
        }
        return try syncWrite { db in
            let exists = try Bool.fetchOne(db, sql: """
                SELECT EXISTS(SELECT 1 FROM liftSession WHERE deviceId = ? AND startTs = ? AND sport = ?)
                """, arguments: [session.deviceId, session.startTs, session.sport]) ?? false
            guard !exists else { return false }
            try db.execute(sql: """
                INSERT INTO liftSession (id, deviceId, startTs, endTs, sport, programId, programName, sessionRpe, note)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [session.id, session.deviceId, session.startTs, session.endTs, session.sport,
                                  session.programId, session.programName, session.sessionRpe, session.note])
            for r in sets {
                try db.execute(sql: """
                    INSERT INTO liftSet (id, deviceId, sessionId, ord, exercise, primaryMuscle, secondaryMuscles,
                                         setIndex, weightKg, reps, rpe, isWarmup, startTs, endTs, restSec, note)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [r.id, r.deviceId, r.sessionId, r.ord, r.exercise, r.primaryMuscle?.rawValue,
                                      LiftMuscle.encodeList(r.secondaryMuscles, excluding: r.primaryMuscle),
                                      r.setIndex, r.weightKg, r.reps, r.rpe, r.isWarmup, r.startTs, r.endTs, r.restSec, r.note])
            }
            // An older summary or a captured workout at this key is preserved, including its HR/strain.
            if workout.endTs > workout.startTs {
                try db.execute(sql: """
                INSERT INTO workout (deviceId, startTs, endTs, sport, source, durationS, energyKcal,
                                     avgHr, maxHr, strain, distanceM, zonesJSON, notes, steps)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(deviceId, startTs, sport) DO NOTHING
                """, arguments: [session.deviceId, workout.startTs, workout.endTs, workout.sport, workout.source,
                                  workout.durationS, workout.energyKcal, workout.avgHr, workout.maxHr, workout.strain,
                                  workout.distanceM, workout.zonesJSON, workout.notes, workout.steps])
            }
            return true
        }
    }
}
