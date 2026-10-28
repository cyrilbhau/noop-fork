import WhoopStore

/// Narrowing Health permissions must not erase previously captured signals or user notes.
enum HealthWorkoutReadMerge {
    static func merge(_ incoming: [WorkoutRow], prior: [WorkoutRow]) -> [WorkoutRow] {
        let previous = Dictionary(prior.map { ("\($0.startTs)|\($0.sport)", $0) }, uniquingKeysWith: { first, _ in first })
        return incoming.map { row in
            guard let old = previous["\(row.startTs)|\(row.sport)"] else { return row }
            return WorkoutRow(startTs: row.startTs, endTs: row.endTs, sport: row.sport, source: row.source,
                              durationS: row.durationS ?? old.durationS,
                              energyKcal: row.energyKcal ?? old.energyKcal,
                              avgHr: row.avgHr ?? old.avgHr, maxHr: row.maxHr ?? old.maxHr,
                              strain: row.strain ?? old.strain, distanceM: row.distanceM ?? old.distanceM,
                              zonesJSON: row.zonesJSON ?? old.zonesJSON, notes: row.notes ?? old.notes,
                              steps: row.steps ?? old.steps)
        }
    }
}
