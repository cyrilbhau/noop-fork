import Foundation
import StrandImport
import WhoopStore

/// Personal Apple input adapter. Imported rows use the existing cross-platform lifting schema.
enum PersonalLiftingImport {
    static let deviceId = "lifting"

    static func save(_ imported: LiftingSession, store: WhoopStore) async throws -> Bool {
        let start = Int(imported.start.timeIntervalSince1970)
        let end = max(start, Int(imported.end.timeIntervalSince1970))
        let id = "lift-import:\(start)"
        let session = LiftSessionRow(id: id, deviceId: deviceId, startTs: start, endTs: end,
                                     sport: LiftingImporter.sport, programId: nil,
                                     programName: imported.title, sessionRpe: nil, note: imported.note)
        let sets = imported.loggedSets.enumerated().map { index, set in
            var notes = [set.note].compactMap { $0 }.filter { !$0.isEmpty }
            if !set.setType.isEmpty && set.setType != "normal" && !set.isWarmup { notes.append(set.setType) }
            if let duration = set.durationSeconds { notes.append("\(duration) s") }
            if let distance = set.distanceMeters { notes.append("\(distance) m") }
            return LiftSetRow(id: "\(id):\(index)", deviceId: deviceId, sessionId: id, ord: index,
                              exercise: set.exercise, primaryMuscle: nil, setIndex: set.setIndex,
                              weightKg: set.weightKg, reps: set.reps, rpe: set.rpe, isWarmup: set.isWarmup,
                              startTs: nil, endTs: nil, restSec: nil,
                              note: notes.isEmpty ? nil : notes.joined(separator: "\n"))
        }
        let workout = WorkoutRow(startTs: start, endTs: end, sport: LiftingImporter.sport, source: deviceId,
                                 durationS: imported.durationS, energyKcal: nil, avgHr: nil, maxHr: nil,
                                 strain: nil, distanceM: nil, zonesJSON: nil, notes: imported.volumeLoadNote(), steps: nil)
        return try await store.appendImportedLift(session: session, sets: sets, workout: workout)
    }
}

/// Deterministic parser for Hevy's shared workout text. Ambiguous set lines block saving.
enum WorkoutTextImport {
    struct Preview {
        var title: String?
        var date: Date?
        var sets: [ImportedLiftSet]
        var unquantifiedExercises: [String]
        var warnings: [String]
        var original: String

        func session(start: Date, end: Date?) -> LiftingSession {
            let working = sets.filter { !$0.isWarmup }
            return LiftingSession(start: start, end: end ?? start,
                                  volumeLoadKg: working.reduce(0) { $0 + max(0, $1.weightKg ?? 0) * Double($1.reps ?? 0) },
                                  setCount: working.count, exerciseCount: Set(sets.map(\.exercise)).count,
                                  totalReps: working.reduce(0) { $0 + ($1.reps ?? 0) },
                                  topSetKg: working.compactMap(\.weightKg).filter { $0 > 0 }.max(),
                                  title: title, loggedSets: sets, note: original)
        }
    }

    static func parse(_ text: String, zone: TimeZone = .current) -> Preview {
        var result = Preview(sets: [], unquantifiedExercises: [], warnings: [], original: text)
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = zone
        formatter.dateFormat = "EEEE, MMM d, yyyy 'at' h:mma"; formatter.isLenient = false
        var dateIndex: Int?
        for (index, line) in lines.enumerated() {
            if let date = formatter.date(from: line) { result.date = date; dateIndex = index; break }
        }
        if let dateIndex { result.title = lines[..<dateIndex].first { !$0.isEmpty } }
        var exercise: String?
        var exerciseNote: String?
        var headings: [String] = []
        let pattern = #"^Set\s+(\d+)\s*:\s*(?:(\d+(?:\.\d+)?)\s*(kg|kgs|lb|lbs)\s*[x×]\s*(\d+)|(bodyweight|bw)\s*[x×]\s*(\d+))\s*$"#
        let regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        for (index, line) in lines.enumerated() {
            if line.isEmpty || (dateIndex != nil && index <= dateIndex!) { continue }
            if line.hasPrefix("@") || line.hasPrefix("https://") || line.hasPrefix("http://") || line.hasPrefix("/") { continue }
            if line.lowercased().hasPrefix("set ") {
                guard let exercise, let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
                    result.warnings.append(line); continue
                }
                func group(_ n: Int) -> String? { Range(match.range(at: n), in: line).map { String(line[$0]) } }
                guard let number = group(1).flatMap(Int.init), number > 0,
                      let reps = (group(4) ?? group(6)).flatMap(Int.init), reps > 0, reps <= 10_000 else {
                    result.warnings.append(line); continue
                }
                var weight = group(2).flatMap(Double.init)
                if group(3)?.lowercased().hasPrefix("lb") == true { weight = weight.map { $0 * 0.45359237 } }
                guard weight == nil || (weight!.isFinite && weight! >= 0 && weight! <= 100_000) else {
                    result.warnings.append(line); continue
                }
                result.sets.append(ImportedLiftSet(exercise: exercise, setIndex: number, weightKg: weight,
                                                  reps: reps, note: exerciseNote))
                exerciseNote = nil
            } else if line.hasPrefix("\"") || line.hasPrefix("“") || line.lowercased().hasPrefix("notes:") {
                exerciseNote = line.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
            } else {
                exercise = line; exerciseNote = nil; headings.append(line)
            }
        }
        result.unquantifiedExercises = headings.filter { name in !result.sets.contains { $0.exercise == name } }
        return result
    }
}
