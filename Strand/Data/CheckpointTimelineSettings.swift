import Foundation
import StrandAnalytics

// The timeline's owner-entered checkpoints (stage 6 specification §9.3, §9.4): planned scans, blood
// panels, benchmarks, weight waypoints, target dates, appointments and anything else the owner dates,
// as one JSON array in the standard defaults. This file is the only code that names that key and the
// only decode of it (§12.4).
//
// A checkpoint never carries a target weight: the one target weight is the active phase's (stage 1
// ruling R47). A weight on a checkpoint is a waypoint, refused at or beyond the phase target; a target
// date is a checkpoint with no weight, attached to a phase by its start day.
//
// The string holds no device identifier (ruling R42). Read at each access; reading never writes.
//
// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).

/// One element of `timeline.checkpoints`.
struct StoredCheckpoint: Equatable, Identifiable {
    /// "c-<8 lowercase hex>"; empty in a draft, issued on save.
    var id: String
    var title: String
    var category: TimelineCheckpointCategory
    var day: String
    /// A date the owner has only roughly fixed; shown as "around".
    var approximate: Bool
    var done: Bool
    /// `weightWaypoint` only; kilograms. A waypoint, never a target.
    var waypointWeightKg: Double?
    /// `targetDate` only: the start day of the phase it belongs to.
    var phaseStartDay: String?
}

/// Why a checkpoint may not be saved, in the order `issue` checks.
enum CheckpointIssue: Equatable {
    case emptyTitle, titleTooLong, invalidDay
    /// A weight waypoint with no weight.
    case weightMissing
    /// A weight on any other category.
    case weightNotAllowed
    /// Outside stage 1's 30–250 kg.
    case weightOutOfRange
    /// §7.3 step 4a: at or beyond the target of the phase in force on that day.
    case waypointAtOrBeyondTarget
    /// A target date with no phase start day, or one no stored phase has.
    case phaseMissing
    /// A phase start day on any other category.
    case phaseNotAllowed
    case targetDateNotAfterPhaseStart
    /// Another checkpoint is that phase's target date.
    case phaseAlreadyHasTargetDate
}

enum CheckpointSaveResult: Equatable {
    case saved(StoredCheckpoint)
    case invalid(CheckpointIssue)
    case limitReached
    /// The stored list is unreadable; nothing was written.
    case needsAttention
}

/// The checkpoints and the timeline's feature flag.
final class CheckpointTimelineSettings {
    static let enabledKey = "noop.checkpointTimelineEnabled"
    static let checkpointsKey = "timeline.checkpoints"

    /// The one observable copy of the flag (§9.4). Views observe it; the Settings switch calls `set`.
    @MainActor static let flag = ObservableDefaultsFlag(key: enabledKey)

    static let maxCheckpoints = 200
    static let maxTitle = 60
    /// Every key a stored element may carry. An element with any other key (a target weight among
    /// them: a weight on a checkpoint is never a target) is unreadable (§9.3).
    private static let storedKeys: Set<String> = ["approximate", "category", "day", "done", "id", "phaseStartDay",
                                                  "title", "v", "waypointWeightKg"]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Reading

    /// The feature flag. Reading it never writes the key.
    var isEnabled: Bool { defaults.bool(forKey: Self.enabledKey) }

    /// In stored order; empty while absent or unreadable.
    var checkpoints: [StoredCheckpoint] { read() ?? [] }
    var checkpointsNeedAttention: Bool { read() == nil }

    // MARK: Checking

    /// The first issue found, in the order of `CheckpointIssue`'s cases; nil when the checkpoint may
    /// be saved. `others` is the stored list without the element being replaced. `phases` is
    /// `CutScorecardSettings().phases`, or none while those cannot be read.
    static func issue(_ checkpoint: StoredCheckpoint, others: [StoredCheckpoint],
                      phases: [CutScorecardStoredPhase]) -> CheckpointIssue? {
        let title = Stage6StoredJSON.trimmed(checkpoint.title)
        if title.isEmpty { return .emptyTitle }
        if title.count > maxTitle { return .titleTooLong }
        guard CanonicalDay.isValid(checkpoint.day) else { return .invalidDay }
        let isWaypoint = checkpoint.category == .weightWaypoint
        if isWaypoint, checkpoint.waypointWeightKg == nil { return .weightMissing }
        if !isWaypoint, checkpoint.waypointWeightKg != nil { return .weightNotAllowed }
        if isWaypoint, let weight = checkpoint.waypointWeightKg {
            guard weight.isFinite, WeighInStore.weightRangeKg.contains(weight) else { return .weightOutOfRange }
            if CheckpointTimeline.waypointIssue(weightKg: weight, on: checkpoint.day, phases: timelinePhases(phases)) != nil {
                return .waypointAtOrBeyondTarget
            }
        }
        let isTargetDate = checkpoint.category == .targetDate
        if isTargetDate {
            guard let start = checkpoint.phaseStartDay, phases.contains(where: { $0.startDay == start }) else {
                return .phaseMissing
            }
        } else if checkpoint.phaseStartDay != nil {
            return .phaseNotAllowed
        }
        if isTargetDate, let start = checkpoint.phaseStartDay {
            if checkpoint.day <= start { return .targetDateNotAfterPhaseStart }
            if others.contains(where: { $0.category == .targetDate && $0.phaseStartDay == start && $0.id != checkpoint.id }) {
                return .phaseAlreadyHasTargetDate
            }
        }
        return nil
    }

    /// The stored phases as the pure timeline sees them, in stored order.
    static func timelinePhases(_ phases: [CutScorecardStoredPhase]) -> [TimelinePhase] {
        phases.map { TimelinePhase(startDay: $0.startDay, isCut: $0.kind == .cut, targetWeightKg: $0.targetWeightKg) }
    }

    // MARK: Writing

    /// Inserts (an empty or unknown id) or replaces by id. Nothing is written unless `.saved`.
    func save(_ checkpoint: StoredCheckpoint, phases: [CutScorecardStoredPhase]) -> CheckpointSaveResult {
        guard var list = read() else { return .needsAttention }
        var cleaned = checkpoint
        cleaned.title = Stage6StoredJSON.trimmed(cleaned.title)
        let existing = cleaned.id.isEmpty ? nil : list.firstIndex(where: { $0.id == cleaned.id })
        let others = list.enumerated().filter { $0.offset != existing }.map(\.element)
        if let issue = Self.issue(cleaned, others: others, phases: phases) { return .invalid(issue) }
        if let existing {
            list[existing] = cleaned
        } else {
            guard list.count < Self.maxCheckpoints else { return .limitReached }
            if !Stage6StoredJSON.isId(cleaned.id, prefix: "c") || list.contains(where: { $0.id == cleaned.id }) {
                cleaned.id = Stage6StoredJSON.newId(prefix: "c", taken: Set(list.map(\.id)))
            }
            list.append(cleaned)
        }
        return write(list) ? .saved(cleaned) : .needsAttention
    }

    @discardableResult
    func delete(id: String) -> Bool {
        guard var list = read(), let index = list.firstIndex(where: { $0.id == id }) else { return false }
        list.remove(at: index)
        return write(list)
    }

    /// Done may be set only when the checkpoint's day is `today` or earlier.
    @discardableResult
    func setDone(id: String, _ done: Bool, today: String) -> Bool {
        guard var list = read(), let index = list.firstIndex(where: { $0.id == id }) else { return false }
        if done, list[index].day > today { return false }
        list[index].done = done
        return write(list)
    }

    /// Removes the stored value, only while it is unreadable. True when something was removed.
    @discardableResult
    func discardUnreadableCheckpoints() -> Bool {
        guard checkpointsNeedAttention else { return false }
        defaults.removeObject(forKey: Self.checkpointsKey)
        return true
    }

    // MARK: The stored shape (§9.3)

    private func read() -> [StoredCheckpoint]? {
        Stage6StoredJSON.readArray(Self.checkpointsKey, from: defaults, element: Self.decode)
    }

    private func write(_ list: [StoredCheckpoint]) -> Bool {
        Stage6StoredJSON.write(list.map(Self.encode), key: Self.checkpointsKey, to: defaults)
    }

    private static func encode(_ c: StoredCheckpoint) -> [String: Any] {
        var object: [String: Any] = ["approximate": c.approximate, "category": c.category.rawValue, "day": c.day,
                                     "done": c.done, "id": c.id, "title": c.title, "v": Stage6StoredJSON.version]
        if let weight = c.waypointWeightKg { object["waypointWeightKg"] = weight }
        if let phase = c.phaseStartDay { object["phaseStartDay"] = phase }
        return object
    }

    /// A checkpoint when the element is a version-1 object of the right types and shape; else nil.
    private static func decode(_ element: Any) -> StoredCheckpoint? {
        typealias J = Stage6StoredJSON
        guard let o = element as? [String: Any], J.integer(o["v"]) == J.version, Set(o.keys).isSubset(of: storedKeys),
              let id = o["id"] as? String, let title = o["title"] as? String,
              let category = (o["category"] as? String).flatMap(TimelineCheckpointCategory.init(rawValue:)),
              let day = o["day"] as? String, let approximate = J.boolean(o["approximate"]),
              let done = J.boolean(o["done"]), let phase = J.optionalString(o, "phaseStartDay") else { return nil }
        var weight: Double?
        if let raw = o["waypointWeightKg"] {
            guard let value = J.number(raw) else { return nil }
            weight = value
        }
        guard weight == nil || category == .weightWaypoint, phase.value == nil || category == .targetDate else {
            return nil
        }
        return StoredCheckpoint(id: id, title: title, category: category, day: day, approximate: approximate,
                                done: done, waypointWeightKg: weight, phaseStartDay: phase.value)
    }
}
