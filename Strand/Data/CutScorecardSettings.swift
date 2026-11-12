import Foundation
import StrandAnalytics

/// One element of `cutScorecard.phases` (specification §9.2).
struct CutScorecardStoredPhase: Equatable {
    enum Kind: String, Codable {
        case cut, other
    }

    var kind: Kind
    var name: String
    /// "yyyy-MM-dd".
    var startDay: String
    /// Nil when the phase has no target; the key is then omitted from the stored JSON.
    var targetWeightKg: Double?
    var rateLowPercentPerWeek: Double
    var rateHighPercentPerWeek: Double

    init(kind: Kind, name: String, startDay: String, targetWeightKg: Double?,
         rateLowPercentPerWeek: Double, rateHighPercentPerWeek: Double) {
        self.kind = kind
        self.name = name
        self.startDay = startDay
        self.targetWeightKg = targetWeightKg
        self.rateLowPercentPerWeek = rateLowPercentPerWeek
        self.rateHighPercentPerWeek = rateHighPercentPerWeek
    }
}

extension CutScorecardStoredPhase: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, name, rateHighPercentPerWeek, rateLowPercentPerWeek, startDay, targetWeightKg, v
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        name = try c.decode(String.self, forKey: .name)
        startDay = try c.decode(String.self, forKey: .startDay)
        targetWeightKg = try c.decodeIfPresent(Double.self, forKey: .targetWeightKg)
        rateLowPercentPerWeek = try c.decode(Double.self, forKey: .rateLowPercentPerWeek)
        rateHighPercentPerWeek = try c.decode(Double.self, forKey: .rateHighPercentPerWeek)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(name, forKey: .name)
        try c.encode(startDay, forKey: .startDay)
        try c.encodeIfPresent(targetWeightKg, forKey: .targetWeightKg)
        try c.encode(rateLowPercentPerWeek, forKey: .rateLowPercentPerWeek)
        try c.encode(rateHighPercentPerWeek, forKey: .rateHighPercentPerWeek)
        try c.encode(CutScorecardSettings.storedVersion, forKey: .v)
    }
}

/// The scorecard's settings in `UserDefaults` (specification §9.2). Every value is read from the
/// defaults at each access and nothing is cached, so a string written under a key by a backup restore
/// is seen by the next read. Reading never writes: an unreadable stored string is left as it is
/// (ruling R30).
final class CutScorecardSettings {
    static let enabledKey = "noop.cutScorecardEnabled"
    static let phasesKey = "cutScorecard.phases"
    static let rulesKey = "cutScorecard.rules"
    static let reminderEnabledKey = "cutScorecard.reminder.enabled"
    static let reminderWeekdayKey = "cutScorecard.reminder.weekday"
    static let reminderMinuteOfDayKey = "cutScorecard.reminder.minuteOfDay"

    /// The `"v"` written into each stored phase and into the rules object.
    static let storedVersion = 1

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Flag and reminder

    /// The feature flag. Off unless switched on.
    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    var reminderEnabled: Bool {
        get { defaults.bool(forKey: Self.reminderEnabledKey) }
        set { defaults.set(newValue, forKey: Self.reminderEnabledKey) }
    }

    /// 1 = Sunday … 7 = Saturday.
    var reminderWeekday: Int {
        get { defaults.object(forKey: Self.reminderWeekdayKey) as? Int ?? 7 }
        set { defaults.set(newValue, forKey: Self.reminderWeekdayKey) }
    }

    /// Minutes after local midnight.
    var reminderMinuteOfDay: Int {
        get { defaults.object(forKey: Self.reminderMinuteOfDayKey) as? Int ?? 480 }
        set { defaults.set(newValue, forKey: Self.reminderMinuteOfDayKey) }
    }

    // MARK: - Phases

    /// Ascending by `startDay`. Stored as a JSON array with sorted keys and `"v":1` per element.
    /// Absent or unreadable: no phases.
    var phases: [CutScorecardStoredPhase] {
        get {
            guard let raw = defaults.string(forKey: Self.phasesKey),
                  let decoded = try? JSONDecoder().decode([CutScorecardStoredPhase].self, from: Data(raw.utf8))
            else { return [] }
            return Self.ascending(decoded)
        }
        set {
            guard let raw = Self.sortedJSON(Self.ascending(newValue)) else { return }
            defaults.set(raw, forKey: Self.phasesKey)
        }
    }

    /// True when something is stored under the phases key and it does not decode as a whole: it is
    /// not a string, it does not parse, or one element cannot be read. False when nothing is
    /// stored. `phases` is then empty, and a save built on that would replace every stored phase,
    /// so `ScorecardPhaseDraft.save(to:)` refuses while this is true.
    var phasesNeedAttention: Bool {
        guard defaults.object(forKey: Self.phasesKey) != nil else { return false }
        guard let raw = defaults.string(forKey: Self.phasesKey) else { return true }
        return (try? JSONDecoder().decode([CutScorecardStoredPhase].self, from: Data(raw.utf8))) == nil
    }

    /// The owner's explicit choice to give up stored phases that cannot be read, so that a phase
    /// can be set up again. Removes the stored value only while it is unreadable; readable phases
    /// are never removed here. Returns whether anything was removed.
    @discardableResult
    func discardUnreadablePhases() -> Bool {
        guard phasesNeedAttention else { return false }
        defaults.removeObject(forKey: Self.phasesKey)
        return true
    }

    /// The phase with the greatest `startDay` on or before `today`.
    func activePhase(on today: String) -> CutScorecardStoredPhase? {
        phases.last { $0.startDay <= today }
    }

    /// What `CutScorecardInput.phase` receives: the active phase when it is a cut, else nil. An
    /// earlier cut is not used once a phase of another kind is active.
    func evaluationPhase(on today: String) -> CutScorecardPhase? {
        guard let active = activePhase(on: today), active.kind == .cut else { return nil }
        return CutScorecardPhase(name: active.name, startDay: active.startDay,
                                 targetWeightKg: active.targetWeightKg,
                                 rateLowPercentPerWeek: active.rateLowPercentPerWeek,
                                 rateHighPercentPerWeek: active.rateHighPercentPerWeek)
    }

    private static func ascending(_ phases: [CutScorecardStoredPhase]) -> [CutScorecardStoredPhase] {
        phases.enumerated()
            .sorted { ($0.element.startDay, $0.offset) < ($1.element.startDay, $1.offset) }
            .map(\.element)
    }

    // MARK: - Rules

    /// The stored rules, with the generic default for every missing key. `.generic` when no rules
    /// are stored, and also when the stored string cannot be used (see `rulesNeedAttention`).
    var parameters: CutScorecardParameters {
        get {
            // R45: a floor stored as a fraction before the ruling reads as the nearest whole gram.
            // The stored string is not rewritten by a read (R30).
            var read = storedParameters() ?? .generic
            read.proteinFloorGrams = Self.normalizedProteinFloorGrams(read.proteinFloorGrams)
            return read
        }
        set {
            // R45: whichever editor writes, the stored floor is whole.
            var written = newValue
            written.proteinFloorGrams = Self.normalizedProteinFloorGrams(newValue.proteinFloorGrams)
            guard let raw = Self.sortedJSON(StoredRules(written)) else { return }
            defaults.set(raw, forKey: Self.rulesKey)
        }
    }

    // MARK: - The protein floor (stage 1 ruling R45, work package 1-10)

    /// R45. The greatest floor an editor accepts, in grams.
    static let proteinFloorMaximumGrams = 100_000

    /// R45. The one rule for a floor an editor may save: finite, at least 1, at most
    /// `proteinFloorMaximumGrams`, and equal to its own rounded value. Both editors (the rules sheet
    /// and the intake settings) decide with this function and nothing else.
    static func isWholeGramProteinFloor(_ grams: Double) -> Bool {
        grams.isFinite && grams >= 1 && grams <= Double(proteinFloorMaximumGrams) && grams == grams.rounded()
    }

    /// R45. The whole-gram form of a stored protein floor: nil for nil; for a finite value above zero
    /// the nearest whole gram, halves away from zero, never below 1; any other value unchanged, so
    /// the scorecard's own validation still rejects it.
    static func normalizedProteinFloorGrams(_ grams: Double?) -> Double? {
        guard let grams else { return nil }
        guard grams.isFinite, grams > 0 else { return grams }
        return max(1, grams.rounded(.toNearestOrAwayFromZero))
    }

    /// R45. The floor as every surface prints it; nil when no floor is set.
    var proteinFloorWholeGrams: Int? {
        parameters.proteinFloorGrams.flatMap { Int(exactly: $0) }
    }

    /// True when a rules string is stored and cannot be used: it does not parse, a value has the
    /// wrong type, or the parameters fail the pure function's own validation. False when nothing is
    /// stored.
    var rulesNeedAttention: Bool {
        defaults.string(forKey: Self.rulesKey) != nil && storedParameters() == nil
    }

    /// The stored rules when they are present, readable and valid. One invalid field makes the whole
    /// object unusable; it is not merged field by field with the defaults.
    private func storedParameters() -> CutScorecardParameters? {
        guard let raw = defaults.string(forKey: Self.rulesKey),
              let stored = try? JSONDecoder().decode(StoredRules.self, from: Data(raw.utf8)) else { return nil }
        let parameters = stored.parameters
        // The pure function is the one authority on what a valid parameter set is (§6.5).
        let probe = CutScorecardInput(weights: [], waists: [], phase: nil, parameters: parameters,
                                      today: "2000-01-01")
        return CutScorecard.evaluate(probe).invalidInput == nil ? parameters : nil
    }

    /// `cutScorecard.rules`: the property names of `CutScorecardParameters`, plus `"v"`.
    private struct StoredRules: Codable {
        var parameters: CutScorecardParameters

        init(_ parameters: CutScorecardParameters) { self.parameters = parameters }

        private enum CodingKeys: String, CodingKey {
            case addCaloriesKcal, liftDropConsecutiveWeeks, liftDropShare, liftDropTolerancePercent
            case maxProjectionWeeks, maxWeighInAgeWeeks, proteinFloorGrams, proteinMinDaysPerWeek
            case rateWindowWeeks, reduceCarbsKcal, slowLossConsecutiveWeeks, slowLossThresholdKgPerWeek
            case targetToleranceKg, v, waistMinDecreaseCm, waistWindowWeeks
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            var p = CutScorecardParameters.generic
            // A missing key keeps the generic default. A present key of the wrong JSON type throws.
            func read<T: Decodable>(_ key: CodingKeys, into path: WritableKeyPath<CutScorecardParameters, T>) throws {
                if let value = try c.decodeIfPresent(T.self, forKey: key) { p[keyPath: path] = value }
            }
            try read(.rateWindowWeeks, into: \.rateWindowWeeks)
            try read(.waistWindowWeeks, into: \.waistWindowWeeks)
            try read(.waistMinDecreaseCm, into: \.waistMinDecreaseCm)
            try read(.liftDropTolerancePercent, into: \.liftDropTolerancePercent)
            try read(.liftDropShare, into: \.liftDropShare)
            try read(.liftDropConsecutiveWeeks, into: \.liftDropConsecutiveWeeks)
            try read(.addCaloriesKcal, into: \.addCaloriesKcal)
            try read(.slowLossThresholdKgPerWeek, into: \.slowLossThresholdKgPerWeek)
            try read(.slowLossConsecutiveWeeks, into: \.slowLossConsecutiveWeeks)
            try read(.reduceCarbsKcal, into: \.reduceCarbsKcal)
            p.proteinFloorGrams = try c.decodeIfPresent(Double.self, forKey: .proteinFloorGrams)
            try read(.proteinMinDaysPerWeek, into: \.proteinMinDaysPerWeek)
            try read(.maxWeighInAgeWeeks, into: \.maxWeighInAgeWeeks)
            try read(.maxProjectionWeeks, into: \.maxProjectionWeeks)
            try read(.targetToleranceKg, into: \.targetToleranceKg)
            parameters = p
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            let p = parameters
            try c.encode(p.rateWindowWeeks, forKey: .rateWindowWeeks)
            try c.encode(p.waistWindowWeeks, forKey: .waistWindowWeeks)
            try c.encode(p.waistMinDecreaseCm, forKey: .waistMinDecreaseCm)
            try c.encode(p.liftDropTolerancePercent, forKey: .liftDropTolerancePercent)
            try c.encode(p.liftDropShare, forKey: .liftDropShare)
            try c.encode(p.liftDropConsecutiveWeeks, forKey: .liftDropConsecutiveWeeks)
            try c.encode(p.addCaloriesKcal, forKey: .addCaloriesKcal)
            try c.encode(p.slowLossThresholdKgPerWeek, forKey: .slowLossThresholdKgPerWeek)
            try c.encode(p.slowLossConsecutiveWeeks, forKey: .slowLossConsecutiveWeeks)
            try c.encode(p.reduceCarbsKcal, forKey: .reduceCarbsKcal)
            try c.encodeIfPresent(p.proteinFloorGrams, forKey: .proteinFloorGrams)
            try c.encode(p.proteinMinDaysPerWeek, forKey: .proteinMinDaysPerWeek)
            try c.encode(p.maxWeighInAgeWeeks, forKey: .maxWeighInAgeWeeks)
            try c.encode(p.maxProjectionWeeks, forKey: .maxProjectionWeeks)
            try c.encode(p.targetToleranceKg, forKey: .targetToleranceKg)
            try c.encode(CutScorecardSettings.storedVersion, forKey: .v)
        }
    }

    // MARK: - Encoding

    /// Sorted keys, so the same settings give the same bytes.
    private static func sortedJSON<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
