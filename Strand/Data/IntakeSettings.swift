import Foundation
import StrandAnalytics
import WhoopStore

/// Stage 3 (protein and intake): every setting of the feature, in `UserDefaults` (specification
/// §9.2, §9.2.1). Every getter reads the defaults at each access and caches nothing, so a restored
/// backup is seen by the next read, and no getter writes (stage 1 ruling R30).
///
/// The protein floor is not stored here. It has one home, the scorecard rules (stage 1 ruling R45):
/// `proteinFloorGrams` reads `CutScorecardSettings.parameters` and `setProteinFloorGrams(_:)` writes
/// through the same setter the rules sheet uses.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
final class IntakeSettings {
    static let enabledKey = "noop.intakeEnabled"
    static let sourceKey = "intake.source"
    static let targetsKey = "intake.targets"
    static let zoneLogKey = "intake.zoneLog"
    static let healthSourcesKey = "intake.health.sources"
    static let healthKnownSourcesKey = "intake.health.knownSources"
    static let healthBackfilledKey = "intake.health.backfilled"
    static let supplementQuestionsKey = "intake.supplement.questions"
    static let cutoffEnabledKey = "intake.cutoff.enabled"
    static let cutoffMinuteOfDayKey = "intake.cutoff.minuteOfDay"
    static let cutoffTimeSetKey = "intake.cutoff.timeSet"
    static let quickAddPresetsKey = "intake.quickAdd.presets"
    static let entriesKeyPrefix = "intake.entries."
    static let maxSupplements = 4
    static let maxPresets = 6
    /// The cutoff minute when none was stored: 21:00.
    static let defaultCutoffMinuteOfDay = 1_260

    /// Whether this build can read dietary protein and energy from Apple Health (Path A, §8). False
    /// until the owner's go-ahead (G1, G2) adds the bridge's read: the source setting keeps its
    /// `appleHealth` case, so Path A is then this constant, the bridge and the permission sentence.
    static let appleHealthReadAvailable = false

    /// The one observable copy of `noop.intakeEnabled`.
    @MainActor static let flag = ObservableDefaultsFlag(key: enabledKey)

    private let defaults: UserDefaults
    private let scorecard: CutScorecardSettings

    /// `scorecard` nil: a `CutScorecardSettings` over the same `defaults`.
    init(defaults: UserDefaults = .standard, scorecard: CutScorecardSettings? = nil) {
        self.defaults = defaults
        self.scorecard = scorecard ?? CutScorecardSettings(defaults: defaults)
    }

    // MARK: - Flag and source

    /// The feature flag. Off unless switched on.
    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    /// An absent or unknown stored string reads as `.none`.
    var source: IntakeSourceSetting {
        get { defaults.string(forKey: Self.sourceKey).flatMap(IntakeSourceSetting.init(rawValue:)) ?? .none }
        set { defaults.set(newValue.rawValue, forKey: Self.sourceKey) }
    }

    /// True when the owner has chosen a source, `None` included. Tells "no source chosen yet" (the
    /// setup prompt) from "None kept" (Path C).
    var hasChosenSource: Bool {
        defaults.string(forKey: Self.sourceKey).flatMap(IntakeSourceSetting.init(rawValue:)) != nil
    }

    /// The Health read of Path A runs only while this is true.
    var healthReadEnabled: Bool { isEnabled && source == .appleHealth }

    // MARK: - Targets

    /// The stored range and hard floor, without the protein floor. Nil when absent or unusable.
    var storedTargets: IntakeTargets? {
        guard let raw = defaults.string(forKey: Self.targetsKey) else { return nil }
        return Self.decodeTargets(raw)
    }

    /// True when `intake.targets` holds something that does not parse or is not valid.
    var targetsNeedAttention: Bool {
        guard defaults.object(forKey: Self.targetsKey) != nil else { return false }
        guard let raw = defaults.string(forKey: Self.targetsKey) else { return true }
        return Self.decodeTargets(raw) == nil
    }

    /// Writes `intake.targets` with sorted keys and `"v":1`. Ignores `proteinFloorGrams`. Returns
    /// false and writes nothing when the range is not valid.
    @discardableResult
    func setTargets(_ targets: IntakeTargets) -> Bool {
        var range = targets
        range.proteinFloorGrams = nil
        guard range.isValid, let raw = Self.sortedJSON(StoredTargets(range)) else { return false }
        defaults.set(raw, forKey: Self.targetsKey)
        return true
    }

    /// The floor from the scorecard rules plus `storedTargets`. The same for every `day`: the
    /// parameter exists so that a later dated override changes no call site.
    func targets(on day: String) -> IntakeTargets {
        var targets = storedTargets ?? IntakeTargets()
        targets.proteinFloorGrams = proteinFloorGrams
        return targets
    }

    private struct StoredTargets: Codable {
        var energyHardFloorKcal: Double?
        var energyHighKcal: Double?
        var energyLowKcal: Double?
        var v: Int?

        init(_ targets: IntakeTargets) {
            energyHardFloorKcal = targets.energyHardFloorKcal
            energyHighKcal = targets.energyHighKcal
            energyLowKcal = targets.energyLowKcal
            v = 1
        }

        var targets: IntakeTargets {
            IntakeTargets(energyLowKcal: energyLowKcal, energyHighKcal: energyHighKcal,
                          energyHardFloorKcal: energyHardFloorKcal)
        }
    }

    private static func decodeTargets(_ raw: String) -> IntakeTargets? {
        guard let stored = try? JSONDecoder().decode(StoredTargets.self, from: Data(raw.utf8)) else { return nil }
        let targets = stored.targets
        return targets.isValid ? targets : nil
    }

    // MARK: - The protein floor (one home: stage 1 ruling R45)

    /// `scorecard.parameters.proteinFloorGrams`: whole grams by stage 1 R45, or nil.
    var proteinFloorGrams: Double? { scorecard.parameters.proteinFloorGrams }

    /// True when the stored scorecard rules cannot be used. The floor is then repaired in the rules
    /// sheet, which shows every rule; this editor writes nothing over them.
    var floorRulesNeedAttention: Bool { scorecard.rulesNeedAttention }

    /// Nil clears the floor. Otherwise assigns `grams` through the scorecard's `parameters` setter.
    /// Returns false and writes nothing when `CutScorecardSettings.isWholeGramProteinFloor` refuses
    /// it, or when the stored rules cannot be used (writing would replace every other rule with the
    /// generic defaults). A floor equal to the one read writes nothing (R30: the stored string is
    /// not rewritten for no change).
    @discardableResult
    func setProteinFloorGrams(_ grams: Double?) -> Bool {
        if let grams, !CutScorecardSettings.isWholeGramProteinFloor(grams) { return false }
        guard !scorecard.rulesNeedAttention else { return false }
        if grams == scorecard.parameters.proteinFloorGrams { return true }
        var parameters = scorecard.parameters
        parameters.proteinFloorGrams = grams
        scorecard.parameters = parameters
        return true
    }

    // MARK: - Zone log

    /// Ascending. Absent or unreadable: empty.
    var zoneLog: [IntakeZoneSegment] {
        get {
            guard let raw = defaults.string(forKey: Self.zoneLogKey),
                  let stored = try? JSONDecoder().decode([StoredSegment].self, from: Data(raw.utf8)) else { return [] }
            return stored.map { IntakeZoneSegment(fromEpochSeconds: $0.from, zoneIdentifier: $0.tz) }
        }
        set {
            let stored = newValue.map { StoredSegment(from: $0.fromEpochSeconds, tz: $0.zoneIdentifier) }
            guard let raw = Self.sortedJSON(stored) else { return }
            defaults.set(raw, forKey: Self.zoneLogKey)
        }
    }

    private struct StoredSegment: Codable {
        let from: Int
        let tz: String
    }

    // MARK: - Apple Health sources (Path A)

    /// Nil: every source is admitted, stored as an absent key.
    var admittedHealthSources: Set<String>? {
        get {
            guard let raw = defaults.string(forKey: Self.healthSourcesKey),
                  let ids = try? JSONDecoder().decode([String].self, from: Data(raw.utf8)) else { return nil }
            return Set(ids)
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Self.healthSourcesKey)
                return
            }
            guard let raw = Self.sortedJSON(newValue.sorted()) else { return }
            defaults.set(raw, forKey: Self.healthSourcesKey)
        }
    }

    struct KnownSource: Equatable, Codable {
        let name: String
        let lastSeenDay: String
    }

    /// Bundle id to the app's name and the last day it wrote. For the source picker and the "two
    /// apps" line.
    var knownHealthSources: [String: KnownSource] {
        guard let raw = defaults.string(forKey: Self.healthKnownSourcesKey),
              let known = try? JSONDecoder().decode([String: KnownSource].self, from: Data(raw.utf8)) else { return [:] }
        return known
    }

    /// Records that `bundleId` wrote on `day`. The last-seen day never moves back.
    func recordHealthSource(bundleId: String, name: String, day: String) {
        var known = knownHealthSources
        let lastSeen = max(known[bundleId]?.lastSeenDay ?? day, day)
        let entry = KnownSource(name: name, lastSeenDay: lastSeen)
        guard known[bundleId] != entry else { return }
        known[bundleId] = entry
        guard let raw = Self.sortedJSON(known) else { return }
        defaults.set(raw, forKey: Self.healthKnownSourcesKey)
    }

    /// The 90-day first read has run (§8.2).
    var healthBackfilled: Bool {
        get { defaults.bool(forKey: Self.healthBackfilledKey) }
        set { defaults.set(newValue, forKey: Self.healthBackfilledKey) }
    }

    // MARK: - Supplements

    /// Canonical Journal questions in display order, at most `maxSupplements`.
    var supplementQuestions: [String] {
        Array(Self.storedQuestions(defaults).prefix(Self.maxSupplements))
    }

    /// False and no write when the list is full or already holds the question.
    @discardableResult
    func addSupplementQuestion(_ question: String) -> Bool {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        var list = supplementQuestions
        guard !trimmed.isEmpty, list.count < Self.maxSupplements,
              !list.contains(where: { Self.sameQuestion($0, trimmed) }) else { return false }
        list.append(trimmed)
        writeQuestions(list)
        return true
    }

    func removeSupplementQuestion(_ question: String) {
        let list = Self.storedQuestions(defaults)
        let kept = list.filter { !Self.sameQuestion($0, question) }
        guard kept.count != list.count else { return }
        if kept.isEmpty {
            defaults.removeObject(forKey: Self.supplementQuestionsKey)
        } else {
            writeQuestions(kept)
        }
    }

    private func writeQuestions(_ list: [String]) {
        guard let raw = Self.sortedJSON(list) else { return }
        defaults.set(raw, forKey: Self.supplementQuestionsKey)
    }

    private static func storedQuestions(_ defaults: UserDefaults) -> [String] {
        guard let raw = defaults.string(forKey: supplementQuestionsKey),
              let list = try? JSONDecoder().decode([String].self, from: Data(raw.utf8)) else { return [] }
        return list
    }

    /// The one comparison of two Journal questions here: surrounding whitespace removed, case ignored.
    private static func sameQuestion(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(b.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    /// Journal rows the in-app Coach may read (§10.6.1): `entries` without every row whose question
    /// is listed in `intake.supplement.questions`, however many entries the stored list holds (a
    /// restored settings file may hold more than the four the editor allows). Order is preserved.
    /// With no list stored, an empty list or an unreadable one, the input is returned unchanged. The
    /// exclusion follows the list, not the feature flag.
    static func coachVisible(_ entries: [JournalEntry], defaults: UserDefaults = .standard) -> [JournalEntry] {
        let listed = storedQuestions(defaults)
        guard !listed.isEmpty else { return entries }
        return entries.filter { entry in !listed.contains { sameQuestion($0, entry.question) } }
    }

    // MARK: - Cutoff

    /// The reminder switch.
    var cutoffEnabled: Bool {
        get { defaults.bool(forKey: Self.cutoffEnabledKey) }
        set { defaults.set(newValue, forKey: Self.cutoffEnabledKey) }
    }

    /// Minutes after local midnight; clamped to 0...1439 on write.
    var cutoffMinuteOfDay: Int {
        get { defaults.object(forKey: Self.cutoffMinuteOfDayKey) as? Int ?? Self.defaultCutoffMinuteOfDay }
        set { defaults.set(min(max(newValue, 0), 24 * 60 - 1), forKey: Self.cutoffMinuteOfDayKey) }
    }

    /// The owner has chosen a cutoff time. False: the day closes only at midnight.
    var cutoffTimeSet: Bool {
        get { defaults.bool(forKey: Self.cutoffTimeSetKey) }
        set { defaults.set(newValue, forKey: Self.cutoffTimeSetKey) }
    }

    /// The minute that closes today for the calories line (§7.5), or nil when no time is set.
    var dayClosingMinute: Int? { cutoffTimeSet ? cutoffMinuteOfDay : nil }

    // MARK: - Presets

    struct Preset: Equatable, Codable {
        let label: String
        let proteinGrams: Double?
        let energyKcal: Double?
    }

    /// At most `maxPresets`; extra items are dropped on write.
    var quickAddPresets: [Preset] {
        get {
            guard let raw = defaults.string(forKey: Self.quickAddPresetsKey),
                  let list = try? JSONDecoder().decode([Preset].self, from: Data(raw.utf8)) else { return [] }
            return Array(list.prefix(Self.maxPresets))
        }
        set {
            guard let raw = Self.sortedJSON(Array(newValue.prefix(Self.maxPresets))) else { return }
            defaults.set(raw, forKey: Self.quickAddPresetsKey)
        }
    }

    // MARK: - Encoding

    /// Sorted keys, so the same settings give the same bytes.
    static func sortedJSON<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
