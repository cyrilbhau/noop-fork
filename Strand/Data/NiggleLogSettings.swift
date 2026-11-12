import Foundation
import StrandAnalytics

// The niggle log's storage (stage 6 specification §9.1, §9.2, §9.4): the owner's complaints and
// standing observations, their own triage rules and the exercises their coach paused, as three JSON
// strings in the standard defaults. This file is the only code that names those keys and the only
// decode of them (§12.4).
//
// The strings hold no device identifier and the store holds no database handle, so removing,
// forgetting or deleting a strap never reaches them (ruling R42). Every value is read at each access
// and nothing is cached; reading never writes. A stored string that cannot be read as a whole makes
// its list read as empty and refuses every save to it until the owner discards it (§9.1).
//
// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).

/// One dated update of a complaint (§9.2). `seq` orders updates that share a day.
struct StoredNiggleUpdate: Equatable {
    var seq: Int
    var day: String
    var trend: NiggleTrend
    var weakness: Bool
    var note: String
}

/// One element of `niggleLog.entries`: a complaint, or a standing observation (decision D8).
struct StoredNiggle: Equatable, Identifiable {
    enum Kind: String, CaseIterable { case complaint, observation }
    enum Side: String, CaseIterable { case left, right, both, notApplicable }

    /// "n-<8 lowercase hex>"; empty in a draft, issued on save.
    var id: String
    var kind: Kind
    var location: String
    var side: Side
    /// Observations store `.other`.
    var character: NiggleCharacter
    /// For an observation, the day it was noted.
    var onsetDay: String
    /// Nil while open.
    var resolvedDay: String?
    /// As recorded at onset.
    var trend: NiggleTrend
    /// As recorded at onset.
    var weakness: Bool
    var updates: [StoredNiggleUpdate]
    var note: String
}

/// One of the owner's triage rules: a `NiggleTriageRule` plus the owner's own label and note.
struct StoredTriageRule: Equatable, Identifiable {
    /// "r-<8 lowercase hex>"; empty in a draft, issued on save.
    var id: String
    /// The owner's own name for the outcome, 1 to 40 characters.
    var label: String
    var action: NiggleAction
    var characters: [NiggleCharacter]
    var trends: [NiggleTrend]
    var weakness: Bool?
    var fromDay: Int?
    var throughDay: Int?
    /// The owner's own words for what they do, at most 200 characters.
    var note: String

    /// The rule as the pure triage sees it: no label, no note.
    var triageRule: NiggleTriageRule {
        NiggleTriageRule(id: id, action: action, characters: characters, trends: trends, weakness: weakness,
                         fromDay: fromDay, throughDay: throughDay)
    }
}

/// `niggleLog.rules`: the owner's rule for seeing a professional, verbatim, and their rules in order.
struct StoredTriageRules: Equatable {
    var professionalRule: String
    var rules: [StoredTriageRule]
}

/// One element of `niggleLog.paused`: an exercise the owner's coach paused, with its reason.
struct StoredPausedExercise: Equatable, Identifiable {
    /// "p-<8 lowercase hex>"; empty in a draft, issued on save.
    var id: String
    var exercise: String
    var reason: String
    var until: String?
    var pausedDay: String
    /// The niggle it belongs to; when that niggle no longer exists the pause is shown without a link.
    var niggleId: String?
    var resumedDay: String?
}

/// The niggle log's three stored lists and its feature flag.
final class NiggleLogSettings {
    static let enabledKey = "noop.niggleLogEnabled"
    static let entriesKey = "niggleLog.entries"
    static let rulesKey = "niggleLog.rules"
    static let pausedKey = "niggleLog.paused"

    /// The one observable copy of the flag (§9.4). Views observe it; the Settings switch calls `set`.
    @MainActor static let flag = ObservableDefaultsFlag(key: enabledKey)

    // Limits of §9.2. A save beyond one is refused, never truncated.
    static let maxEntries = 500
    static let maxUpdates = 100
    static let maxRules = 20
    static let maxPaused = 100
    static let maxLocation = 60
    static let maxNote = 500
    static let maxRuleLabel = 40
    static let maxRuleNote = 200
    static let maxProfessionalRule = 300
    static let maxExercise = 60
    static let maxReason = 200
    static let maxUntil = 100

    private let defaults: UserDefaults
    private let today: () -> String

    /// `today` is the day "not after today" is judged against when saving.
    init(defaults: UserDefaults = .standard,
         today: @escaping () -> String = { LocalDayWindows(timeZone: .current).dayKey(for: Date()) }) {
        self.defaults = defaults
        self.today = today
    }

    // MARK: Reading

    /// The feature flag. Reading it never writes the key.
    var isEnabled: Bool { defaults.bool(forKey: Self.enabledKey) }

    /// The stored entries in stored order; empty when absent or unreadable.
    var entries: [StoredNiggle] { readEntries() ?? [] }
    /// Something is stored under the entries key and it cannot be read as a whole.
    var entriesNeedAttention: Bool { readEntries() == nil }

    /// The stored rules; none when absent or unreadable. The app ships no rule (decision D3).
    var rules: StoredTriageRules { readRules() ?? StoredTriageRules(professionalRule: "", rules: []) }
    var rulesNeedAttention: Bool { readRules() == nil }

    var paused: [StoredPausedExercise] { readPaused() ?? [] }
    var pausedNeedAttention: Bool { readPaused() == nil }

    // MARK: Entries

    /// Inserts a new entry (an empty or unknown id) or replaces the entry with the same id.
    @discardableResult
    func save(_ niggle: StoredNiggle) -> Bool {
        guard var list = readEntries(), let cleaned = validated(niggle) else { return false }
        if let index = list.firstIndex(where: { $0.id == cleaned.id }), !cleaned.id.isEmpty {
            list[index] = cleaned
        } else {
            guard list.count < Self.maxEntries else { return false }
            var inserted = cleaned
            if !Stage6StoredJSON.isId(inserted.id, prefix: "n") || list.contains(where: { $0.id == inserted.id }) {
                inserted.id = Stage6StoredJSON.newId(prefix: "n", taken: Set(list.map(\.id)))
            }
            list.append(inserted)
        }
        return writeEntries(list)
    }

    /// Removes the entry. Its paused exercises stay, without the link (§9.2).
    @discardableResult
    func delete(niggleId: String) -> Bool {
        guard var list = readEntries(), let index = list.firstIndex(where: { $0.id == niggleId }) else { return false }
        list.remove(at: index)
        guard writeEntries(list) else { return false }
        if var pauses = readPaused(), pauses.contains(where: { $0.niggleId == niggleId }) {
            for i in pauses.indices where pauses[i].niggleId == niggleId { pauses[i].niggleId = nil }
            writePaused(pauses)
        }
        return true
    }

    /// Marks a complaint resolved on `day`: from its onset to today.
    @discardableResult
    func resolve(niggleId: String, on day: String) -> Bool {
        update(niggleId) { niggle in
            guard niggle.kind == .complaint else { return false }
            niggle.resolvedDay = day
            return true
        }
    }

    /// Opens a resolved complaint again.
    @discardableResult
    func reopen(niggleId: String) -> Bool {
        update(niggleId) { niggle in
            guard niggle.resolvedDay != nil else { return false }
            niggle.resolvedDay = nil
            return true
        }
    }

    /// Adds a dated update with `seq` 1 + the greatest in the entry, dated from onset to today.
    @discardableResult
    func addUpdate(niggleId: String, day: String, trend: NiggleTrend, weakness: Bool, note: String) -> Bool {
        update(niggleId) { niggle in
            guard niggle.kind == .complaint, niggle.updates.count < Self.maxUpdates,
                  CanonicalDay.isValid(day), day >= niggle.onsetDay, day <= today() else { return false }
            let seq = (niggle.updates.map(\.seq).max() ?? 0) + 1
            niggle.updates.append(StoredNiggleUpdate(seq: seq, day: day, trend: trend, weakness: weakness, note: note))
            return true
        }
    }

    @discardableResult
    func deleteUpdate(niggleId: String, seq: Int) -> Bool {
        update(niggleId) { niggle in
            guard let index = niggle.updates.firstIndex(where: { $0.seq == seq }) else { return false }
            niggle.updates.remove(at: index)
            return true
        }
    }

    /// Reads the list, changes one entry, checks it and writes the list once.
    private func update(_ niggleId: String, _ change: (inout StoredNiggle) -> Bool) -> Bool {
        guard var list = readEntries(), let index = list.firstIndex(where: { $0.id == niggleId }) else { return false }
        var niggle = list[index]
        guard change(&niggle), let cleaned = validated(niggle) else { return false }
        list[index] = cleaned
        return writeEntries(list)
    }

    /// The entry trimmed and checked against §9.2; nil when it may not be stored.
    private func validated(_ niggle: StoredNiggle) -> StoredNiggle? {
        var n = niggle
        n.location = Stage6StoredJSON.trimmed(n.location)
        n.note = Stage6StoredJSON.trimmed(n.note)
        if n.kind == .observation { n.character = .other }
        n.updates = n.updates.map { update in
            var u = update
            u.note = Stage6StoredJSON.trimmed(u.note)
            return u
        }
        let now = today()
        guard !n.location.isEmpty, n.location.count <= Self.maxLocation, n.note.count <= Self.maxNote,
              CanonicalDay.isValid(n.onsetDay), n.onsetDay <= now, n.updates.count <= Self.maxUpdates,
              n.updates.allSatisfy({ $0.note.count <= Self.maxNote }) else { return nil }
        if let resolved = n.resolvedDay {
            guard n.kind == .complaint, CanonicalDay.isValid(resolved), resolved >= n.onsetDay, resolved <= now
            else { return nil }
        }
        return n
    }

    // MARK: Rules

    /// Replaces the stored rules. Ids are issued for new rules; an invalid list is refused (§9.2).
    @discardableResult
    func saveRules(_ rules: StoredTriageRules) -> Bool {
        guard readRules() != nil else { return false }
        var cleaned = rules
        cleaned.professionalRule = Stage6StoredJSON.trimmed(cleaned.professionalRule)
        guard cleaned.professionalRule.count <= Self.maxProfessionalRule, cleaned.rules.count <= Self.maxRules
        else { return false }
        var taken = Set(cleaned.rules.map(\.id).filter { !$0.isEmpty })
        for i in cleaned.rules.indices {
            cleaned.rules[i].label = Stage6StoredJSON.trimmed(cleaned.rules[i].label)
            cleaned.rules[i].note = Stage6StoredJSON.trimmed(cleaned.rules[i].note)
            if cleaned.rules[i].id.isEmpty {
                cleaned.rules[i].id = Stage6StoredJSON.newId(prefix: "r", taken: taken)
                taken.insert(cleaned.rules[i].id)
            }
        }
        guard cleaned.rules.allSatisfy(Self.ruleTextIsValid),
              NiggleTriage.rulesAreValid(cleaned.rules.map(\.triageRule)) else { return false }
        return Stage6StoredJSON.write(Self.encode(cleaned), key: Self.rulesKey, to: defaults)
    }

    private static func ruleTextIsValid(_ rule: StoredTriageRule) -> Bool {
        !rule.label.isEmpty && rule.label.count <= maxRuleLabel && rule.note.count <= maxRuleNote
    }

    // MARK: Paused exercises

    /// Inserts a new pause (an empty or unknown id) or replaces the one with the same id.
    @discardableResult
    func save(_ paused: StoredPausedExercise) -> Bool {
        guard var list = readPaused(), let cleaned = validated(paused) else { return false }
        if !cleaned.id.isEmpty, let index = list.firstIndex(where: { $0.id == cleaned.id }) {
            list[index] = cleaned
        } else {
            guard list.count < Self.maxPaused else { return false }
            var inserted = cleaned
            if !Stage6StoredJSON.isId(inserted.id, prefix: "p") || list.contains(where: { $0.id == inserted.id }) {
                inserted.id = Stage6StoredJSON.newId(prefix: "p", taken: Set(list.map(\.id)))
            }
            list.append(inserted)
        }
        return writePaused(list)
    }

    /// Marks a pause resumed on `day`: from the paused day to today.
    @discardableResult
    func resume(pausedId: String, on day: String) -> Bool {
        guard var list = readPaused(), let index = list.firstIndex(where: { $0.id == pausedId }) else { return false }
        var pause = list[index]
        pause.resumedDay = day
        guard let cleaned = validated(pause) else { return false }
        list[index] = cleaned
        return writePaused(list)
    }

    @discardableResult
    func delete(pausedId: String) -> Bool {
        guard var list = readPaused(), let index = list.firstIndex(where: { $0.id == pausedId }) else { return false }
        list.remove(at: index)
        return writePaused(list)
    }

    private func validated(_ paused: StoredPausedExercise) -> StoredPausedExercise? {
        var p = paused
        p.exercise = Stage6StoredJSON.trimmed(p.exercise)
        p.reason = Stage6StoredJSON.trimmed(p.reason)
        p.until = p.until.map(Stage6StoredJSON.trimmed).flatMap { $0.isEmpty ? nil : $0 }
        let now = today()
        guard !p.exercise.isEmpty, p.exercise.count <= Self.maxExercise, !p.reason.isEmpty,
              p.reason.count <= Self.maxReason, (p.until?.count ?? 0) <= Self.maxUntil,
              CanonicalDay.isValid(p.pausedDay), p.pausedDay <= now else { return nil }
        if let resumed = p.resumedDay {
            guard CanonicalDay.isValid(resumed), resumed >= p.pausedDay, resumed <= now else { return nil }
        }
        return p
    }

    // MARK: Discarding unreadable data

    /// Removes the entries key, only while it is unreadable. True when something was removed.
    @discardableResult
    func discardUnreadableEntries() -> Bool { discard(Self.entriesKey, unreadable: entriesNeedAttention) }
    @discardableResult
    func discardUnreadableRules() -> Bool { discard(Self.rulesKey, unreadable: rulesNeedAttention) }
    @discardableResult
    func discardUnreadablePaused() -> Bool { discard(Self.pausedKey, unreadable: pausedNeedAttention) }

    private func discard(_ key: String, unreadable: Bool) -> Bool {
        guard unreadable else { return false }
        defaults.removeObject(forKey: key)
        return true
    }

    // MARK: The stored shapes (§9.2)

    /// Nil when unreadable; empty when absent.
    private func readEntries() -> [StoredNiggle]? {
        Stage6StoredJSON.readArray(Self.entriesKey, from: defaults, element: Self.decodeNiggle)
    }

    private func readRules() -> StoredTriageRules? {
        switch Stage6StoredJSON.read(Self.rulesKey, from: defaults) {
        case .absent: return StoredTriageRules(professionalRule: "", rules: [])
        case .unreadable: return nil
        case .parsed(let value):
            guard let object = value as? [String: Any], Stage6StoredJSON.integer(object["v"]) == 1,
                  let professional = object["professionalRule"] as? String,
                  let elements = object["rules"] as? [Any] else { return nil }
            var rules: [StoredTriageRule] = []
            for element in elements {
                guard let rule = Self.decodeRule(element) else { return nil }
                rules.append(rule)
            }
            guard NiggleTriage.rulesAreValid(rules.map(\.triageRule)) else { return nil }
            return StoredTriageRules(professionalRule: professional, rules: rules)
        }
    }

    private func readPaused() -> [StoredPausedExercise]? {
        Stage6StoredJSON.readArray(Self.pausedKey, from: defaults, element: Self.decodePaused)
    }

    @discardableResult
    private func writeEntries(_ list: [StoredNiggle]) -> Bool {
        Stage6StoredJSON.write(list.map(Self.encode), key: Self.entriesKey, to: defaults)
    }

    @discardableResult
    private func writePaused(_ list: [StoredPausedExercise]) -> Bool {
        Stage6StoredJSON.write(list.map(Self.encode), key: Self.pausedKey, to: defaults)
    }

    private static func encode(_ n: StoredNiggle) -> [String: Any] {
        var object: [String: Any] = [
            "character": n.character.rawValue, "id": n.id, "kind": n.kind.rawValue, "location": n.location,
            "note": n.note, "onsetDay": n.onsetDay, "side": n.side.rawValue, "trend": n.trend.rawValue,
            "updates": n.updates.map { u -> [String: Any] in
                ["day": u.day, "note": u.note, "seq": u.seq, "trend": u.trend.rawValue, "weakness": u.weakness]
            },
            "v": Stage6StoredJSON.version, "weakness": n.weakness,
        ]
        if let resolved = n.resolvedDay { object["resolvedDay"] = resolved }
        return object
    }

    private static func decodeNiggle(_ element: Any) -> StoredNiggle? {
        typealias J = Stage6StoredJSON
        guard let o = element as? [String: Any], J.integer(o["v"]) == J.version,
              let id = o["id"] as? String,
              let kind = (o["kind"] as? String).flatMap(StoredNiggle.Kind.init(rawValue:)),
              let location = o["location"] as? String,
              let side = (o["side"] as? String).flatMap(StoredNiggle.Side.init(rawValue:)),
              let character = (o["character"] as? String).flatMap(NiggleCharacter.init(rawValue:)),
              let onsetDay = o["onsetDay"] as? String,
              let trend = (o["trend"] as? String).flatMap(NiggleTrend.init(rawValue:)),
              let weakness = J.boolean(o["weakness"]),
              let note = o["note"] as? String,
              let resolved = J.optionalString(o, "resolvedDay"),
              let rawUpdates = o["updates"] as? [Any] else { return nil }
        var updates: [StoredNiggleUpdate] = []
        for raw in rawUpdates {
            guard let u = raw as? [String: Any], let seq = J.integer(u["seq"]), let day = u["day"] as? String,
                  let trend = (u["trend"] as? String).flatMap(NiggleTrend.init(rawValue:)),
                  let weakness = J.boolean(u["weakness"]), let note = u["note"] as? String else { return nil }
            updates.append(StoredNiggleUpdate(seq: seq, day: day, trend: trend, weakness: weakness, note: note))
        }
        return StoredNiggle(id: id, kind: kind, location: location, side: side, character: character,
                            onsetDay: onsetDay, resolvedDay: resolved.value, trend: trend, weakness: weakness,
                            updates: updates, note: note)
    }

    private static func encode(_ rules: StoredTriageRules) -> [String: Any] {
        let elements = rules.rules.map { r -> [String: Any] in
            var object: [String: Any] = [
                "action": r.action.rawValue, "characters": r.characters.map(\.rawValue), "id": r.id, "label": r.label,
                "note": r.note, "trends": r.trends.map(\.rawValue),
            ]
            if let weakness = r.weakness { object["weakness"] = weakness }
            if let from = r.fromDay { object["fromDay"] = from }
            if let through = r.throughDay { object["throughDay"] = through }
            return object
        }
        return ["professionalRule": rules.professionalRule, "rules": elements, "v": Stage6StoredJSON.version]
    }

    private static func decodeRule(_ element: Any) -> StoredTriageRule? {
        typealias J = Stage6StoredJSON
        guard let o = element as? [String: Any], let id = o["id"] as? String, let label = o["label"] as? String,
              let action = (o["action"] as? String).flatMap(NiggleAction.init(rawValue:)),
              let rawCharacters = o["characters"] as? [String], let rawTrends = o["trends"] as? [String],
              let note = o["note"] as? String else { return nil }
        let characters = rawCharacters.compactMap(NiggleCharacter.init(rawValue:))
        let trends = rawTrends.compactMap(NiggleTrend.init(rawValue:))
        guard characters.count == rawCharacters.count, trends.count == rawTrends.count else { return nil }
        var weakness: Bool?
        if let raw = o["weakness"] {
            guard let value = J.boolean(raw) else { return nil }
            weakness = value
        }
        var fromDay: Int?
        if let raw = o["fromDay"] {
            guard let value = J.integer(raw) else { return nil }
            fromDay = value
        }
        var throughDay: Int?
        if let raw = o["throughDay"] {
            guard let value = J.integer(raw) else { return nil }
            throughDay = value
        }
        return StoredTriageRule(id: id, label: label, action: action, characters: characters, trends: trends,
                                weakness: weakness, fromDay: fromDay, throughDay: throughDay, note: note)
    }

    private static func encode(_ p: StoredPausedExercise) -> [String: Any] {
        var object: [String: Any] = ["exercise": p.exercise, "id": p.id, "pausedDay": p.pausedDay, "reason": p.reason,
                                     "v": Stage6StoredJSON.version]
        if let until = p.until { object["until"] = until }
        if let niggle = p.niggleId { object["niggleId"] = niggle }
        if let resumed = p.resumedDay { object["resumedDay"] = resumed }
        return object
    }

    private static func decodePaused(_ element: Any) -> StoredPausedExercise? {
        typealias J = Stage6StoredJSON
        guard let o = element as? [String: Any], J.integer(o["v"]) == J.version,
              let id = o["id"] as? String, let exercise = o["exercise"] as? String,
              let reason = o["reason"] as? String, let pausedDay = o["pausedDay"] as? String,
              let until = J.optionalString(o, "until"), let niggle = J.optionalString(o, "niggleId"),
              let resumed = J.optionalString(o, "resumedDay") else { return nil }
        return StoredPausedExercise(id: id, exercise: exercise, reason: reason, until: until.value,
                                    pausedDay: pausedDay, niggleId: niggle.value, resumedDay: resumed.value)
    }
}

/// The rules every stage 6 stored string follows (§9.1): sorted keys, `"v":1`, one parse per read,
/// a list that does not read as a whole is unreadable, and reading never writes.
enum Stage6StoredJSON {
    /// The `"v"` every stored element (and the rules object) carries.
    static let version = 1

    enum Stored {
        case absent
        case parsed(Any)
        case unreadable
    }

    /// One parse of the value under `key`. A value that is not a string, or does not parse, is unreadable.
    static func read(_ key: String, from defaults: UserDefaults) -> Stored {
        guard let raw = defaults.object(forKey: key) else { return .absent }
        guard let text = raw as? String, let data = text.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data, options: []) else { return .unreadable }
        return .parsed(value)
    }

    /// The stored array decoded element by element: empty when absent, nil when the value or any one
    /// element cannot be read.
    static func readArray<T>(_ key: String, from defaults: UserDefaults, element: (Any) -> T?) -> [T]? {
        switch read(key, from: defaults) {
        case .absent: return []
        case .unreadable: return nil
        case .parsed(let value):
            guard let array = value as? [Any] else { return nil }
            var out: [T] = []
            out.reserveCapacity(array.count)
            for raw in array {
                guard let decoded = element(raw) else { return nil }
                out.append(decoded)
            }
            return out
        }
    }

    /// Writes the value once, with sorted keys and no whitespace, so equal lists give equal bytes.
    @discardableResult
    static func write(_ value: Any, key: String, to defaults: UserDefaults) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return false }
        defaults.set(text, forKey: key)
        return true
    }

    static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// "<prefix>-<8 lowercase hex>".
    static func isId(_ id: String, prefix: String) -> Bool {
        id.range(of: "^\(prefix)-[0-9a-f]{8}$", options: .regularExpression) != nil
    }

    /// A fresh id of the store's shape that no element in `taken` has.
    static func newId(prefix: String, taken: Set<String>) -> String {
        var generator = SystemRandomNumberGenerator()
        while true {
            let id = String(format: "%@-%08x", prefix, generator.next() as UInt32)
            if !taken.contains(id) { return id }
        }
    }

    /// An absent key is a present nil; a key of another type is a failed decode (nil).
    struct OptionalValue<T> { var value: T? }

    static func optionalString(_ object: [String: Any], _ key: String) -> OptionalValue<String>? {
        guard let raw = object[key] else { return OptionalValue(value: nil) }
        guard let text = raw as? String else { return nil }
        return OptionalValue(value: text)
    }

    /// A JSON boolean only (not a number that bridges to one).
    static func boolean(_ raw: Any?) -> Bool? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    /// A JSON integer only (not a boolean, not a fraction).
    static func integer(_ raw: Any?) -> Int? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        guard value.isFinite, value.rounded() == value, abs(value) < 9.0e15 else { return nil }
        return number.intValue
    }

    /// A JSON number (not a boolean).
    static func number(_ raw: Any?) -> Double? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue
    }
}
