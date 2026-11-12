import Foundation

// Stage 6 of the personal fork: the label and the day count of one logged complaint, worked out from
// rules the owner typed (docs/personal/superapp/specs/stage-6.md §6.1 and §7.1).
//
// The app ships no rule. With no rule entered the result carries a day count and no label. The function
// sees a complaint's character, trend, weakness and days only: no location, side, note or label reaches
// it, so none can leak through logic, logs or tests.
//
// Pure: no store, no clock, no `Date`, `Calendar` or `TimeZone`. "Today" is passed in as a day key and
// every day goes through `CanonicalDay`. Nothing here throws or traps on any input.
//
// No Kotlin twin: the owner has skipped Android for the personal fork (stage 1 ruling R43), so every
// declaration here is unpaired in the parity ledger.

/// How a complaint presents. A fixed list, so that a rule can refer to it.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public enum NiggleCharacter: String, CaseIterable, Equatable, Sendable {
    case diffuse, localised, positional, other
}

/// The direction a complaint was recorded as taking. `notRecorded` is "not recorded", never a guess.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public enum NiggleTrend: String, CaseIterable, Equatable, Sendable {
    case easing, unchanged, worsening, notRecorded
}

/// What one of the owner's rules says to do. Words only; `NiggleTriage.severity(_:)` orders them.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public enum NiggleAction: String, CaseIterable, Equatable, Sendable {
    case watch, modify, seeProfessional
}

/// A dated update to a complaint.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public struct NiggleUpdate: Equatable, Sendable {
    public let day: String
    /// Orders updates that share a day; greater is later.
    public let sequence: Int
    public let trend: NiggleTrend
    public let weakness: Bool

    public init(day: String, sequence: Int, trend: NiggleTrend, weakness: Bool) {
        self.day = day
        self.sequence = sequence
        self.trend = trend
        self.weakness = weakness
    }
}

/// One complaint as the triage sees it.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public struct NiggleComplaint: Equatable, Sendable {
    public let onsetDay: String
    /// Nil while the complaint is open.
    public let resolvedDay: String?
    public let character: NiggleCharacter
    /// As recorded at onset.
    public let trend: NiggleTrend
    /// As recorded at onset.
    public let weakness: Bool
    public let updates: [NiggleUpdate]

    public init(onsetDay: String, resolvedDay: String?, character: NiggleCharacter, trend: NiggleTrend,
                weakness: Bool, updates: [NiggleUpdate] = []) {
        self.onsetDay = onsetDay
        self.resolvedDay = resolvedDay
        self.character = character
        self.trend = trend
        self.weakness = weakness
        self.updates = updates
    }
}

/// One rule the owner typed.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public struct NiggleTriageRule: Equatable, Sendable {
    public var id: String
    public var action: NiggleAction
    /// Empty: any character.
    public var characters: [NiggleCharacter]
    /// Empty: any trend.
    public var trends: [NiggleTrend]
    /// Nil: with or without weakness.
    public var weakness: Bool?
    /// Inclusive lower bound on the day count. Nil: day 1.
    public var fromDay: Int?
    /// Inclusive upper bound on the day count. Nil: none.
    public var throughDay: Int?

    public init(id: String, action: NiggleAction, characters: [NiggleCharacter], trends: [NiggleTrend],
                weakness: Bool?, fromDay: Int?, throughDay: Int?) {
        self.id = id
        self.action = action
        self.characters = characters
        self.trends = trends
        self.weakness = weakness
        self.fromDay = fromDay
        self.throughDay = throughDay
    }
}

/// A complaint, the owner's rules in the owner's order, and the day to judge it on.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public struct NiggleTriageInput: Equatable, Sendable {
    public let complaint: NiggleComplaint
    public let rules: [NiggleTriageRule]
    public let today: String

    public init(complaint: NiggleComplaint, rules: [NiggleTriageRule], today: String) {
        self.complaint = complaint
        self.rules = rules
        self.today = today
    }
}

/// What the triage could say about a complaint.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public enum NiggleTriageStatus: String, Equatable, Sendable {
    case matched, noRuleMatches, noRulesEntered, resolved, invalidInput
}

/// Why an input could not be judged. The first cause in the order of §7.1 steps 1 to 3 is reported.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public enum NiggleTriageInvalid: String, Equatable, Sendable {
    case today, rules, onsetDay, onsetAfterToday, resolvedDay, resolvedBeforeOnset, resolvedAfterToday
}

/// The first later day on which the owner's rules would say something else, if nothing further is
/// recorded. It restates the rules; it predicts nothing.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public struct NiggleTriageNextChange: Equatable, Sendable {
    public let dayCount: Int
    public let day: String
    /// Nil: no rule will match from that day.
    public let ruleId: String?
    public let action: NiggleAction?

    public init(dayCount: Int, day: String, ruleId: String?, action: NiggleAction?) {
        self.dayCount = dayCount
        self.day = day
        self.ruleId = ruleId
        self.action = action
    }
}

/// The triage of one complaint on one day.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public struct NiggleTriageResult: Equatable, Sendable {
    public let status: NiggleTriageStatus
    /// Set exactly when `status` is `invalidInput`.
    public let invalid: NiggleTriageInvalid?
    public let isOpen: Bool
    /// The onset day is day 1. Nil exactly when the input is invalid.
    public let dayCount: Int?
    public let currentTrend: NiggleTrend
    public let currentWeakness: Bool
    /// The day the current trend and weakness were recorded. Nil when the input is invalid.
    public let stateDay: String?
    /// Set exactly when `status` is `matched`.
    public let ruleId: String?
    /// Set exactly when `status` is `matched`.
    public let action: NiggleAction?
    /// Every matching rule, in the owner's order.
    public let matchedRuleIds: [String]
    public let nextChange: NiggleTriageNextChange?
    public let ignoredUpdates: Int

    public init(status: NiggleTriageStatus, invalid: NiggleTriageInvalid?, isOpen: Bool, dayCount: Int?,
                currentTrend: NiggleTrend, currentWeakness: Bool, stateDay: String?, ruleId: String?,
                action: NiggleAction?, matchedRuleIds: [String], nextChange: NiggleTriageNextChange?,
                ignoredUpdates: Int) {
        self.status = status
        self.invalid = invalid
        self.isOpen = isOpen
        self.dayCount = dayCount
        self.currentTrend = currentTrend
        self.currentWeakness = currentWeakness
        self.stateDay = stateDay
        self.ruleId = ruleId
        self.action = action
        self.matchedRuleIds = matchedRuleIds
        self.nextChange = nextChange
        self.ignoredUpdates = ignoredUpdates
    }
}

/// Applies the owner's own triage rules to one complaint (stage 6 specification §7.1).
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public enum NiggleTriage {
    /// 0 for watch, 1 for modify, 2 for seeProfessional.
    ///
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static func severity(_ action: NiggleAction) -> Int {
        switch action {
        case .watch: return 0
        case .modify: return 1
        case .seeProfessional: return 2
        }
    }

    /// True when the rule list is usable (§7.1 step 2): every id non-empty and unique, every `fromDay`
    /// that is set at least 1, every `throughDay` that is set at least `fromDay ?? 1`. Repeats inside
    /// `characters` or `trends` are harmless.
    ///
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static func rulesAreValid(_ rules: [NiggleTriageRule]) -> Bool {
        var seen = Set<String>()
        for rule in rules {
            guard !rule.id.isEmpty, seen.insert(rule.id).inserted else { return false }
            let from = rule.fromDay ?? firstDayCount
            guard from >= firstDayCount else { return false }
            if let through = rule.throughDay, through < from { return false }
        }
        return true
    }

    /// The triage of `input.complaint` on `input.today` (§7.1). Never throws or traps.
    ///
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static func evaluate(_ input: NiggleTriageInput) -> NiggleTriageResult {
        let complaint = input.complaint

        // Steps 1 to 3: the first cause in this order is the one reported.
        guard let todayNumber = CanonicalDay.number(input.today) else {
            return invalid(.today, complaint)
        }
        guard rulesAreValid(input.rules) else { return invalid(.rules, complaint) }
        guard let onsetNumber = CanonicalDay.number(complaint.onsetDay) else {
            return invalid(.onsetDay, complaint)
        }
        guard onsetNumber <= todayNumber else { return invalid(.onsetAfterToday, complaint) }
        var resolvedNumber: Int?
        if let resolvedDay = complaint.resolvedDay {
            guard let number = CanonicalDay.number(resolvedDay) else {
                return invalid(.resolvedDay, complaint)
            }
            guard number >= onsetNumber else { return invalid(.resolvedBeforeOnset, complaint) }
            guard number <= todayNumber else { return invalid(.resolvedAfterToday, complaint) }
            resolvedNumber = number
        }

        // Steps 4 and 5: the kept update with the greatest (day, sequence); among equals the later in
        // input order. An update outside onset ... min(today, resolved) is ignored and counted once.
        let lastKeptNumber = resolvedNumber ?? todayNumber
        var ignoredUpdates = 0
        var latest: (number: Int, update: NiggleUpdate)?
        for update in complaint.updates {
            guard let number = CanonicalDay.number(update.day), number >= onsetNumber,
                  number <= lastKeptNumber else {
                ignoredUpdates += 1
                continue
            }
            if let held = latest, (number, update.sequence) < (held.number, held.update.sequence) {
                continue
            }
            latest = (number, update)
        }
        let currentTrend = latest?.update.trend ?? complaint.trend
        let currentWeakness = latest?.update.weakness ?? complaint.weakness
        let stateDay = latest?.update.day ?? complaint.onsetDay

        func result(_ status: NiggleTriageStatus, dayCount: Int, winner: NiggleTriageRule? = nil,
                    matchedRuleIds: [String] = [],
                    nextChange: NiggleTriageNextChange? = nil) -> NiggleTriageResult {
            NiggleTriageResult(status: status, invalid: nil, isOpen: status != .resolved,
                               dayCount: dayCount, currentTrend: currentTrend,
                               currentWeakness: currentWeakness, stateDay: stateDay, ruleId: winner?.id,
                               action: winner?.action, matchedRuleIds: matchedRuleIds,
                               nextChange: nextChange, ignoredUpdates: ignoredUpdates)
        }

        // Step 6: a resolved complaint reports how long it lasted and is not triaged.
        if let resolvedNumber {
            return result(.resolved, dayCount: resolvedNumber - onsetNumber + firstDayCount)
        }

        // Steps 7 and 8.
        let dayCount = todayNumber - onsetNumber + firstDayCount
        guard !input.rules.isEmpty else { return result(.noRulesEntered, dayCount: dayCount) }

        // Step 9. The three conditions that do not depend on the day count are settled once.
        let eligible = input.rules.filter { rule in
            (rule.characters.isEmpty || rule.characters.contains(complaint.character))
                && (rule.trends.isEmpty || rule.trends.contains(currentTrend))
                && (rule.weakness == nil || rule.weakness == currentWeakness)
        }

        // Step 10.
        let matched = eligible.filter { matchesDay($0, dayCount) }
        let current = winner(among: eligible, at: dayCount)
        let change = nextChange(after: dayCount, current: current, eligible: eligible,
                                onsetNumber: onsetNumber)
        return result(current == nil ? .noRuleMatches : .matched, dayCount: dayCount, winner: current,
                      matchedRuleIds: matched.map(\.id), nextChange: change)
    }

    /// The day count of the onset day: day 1, not day 0 (§7.1 step 7, question Q3).
    private static let firstDayCount = 1

    /// Every invalid result has the same shape (§7.1 step 1): closed, no day count, the complaint's own
    /// trend and weakness, no state day, no rule, nothing counted.
    private static func invalid(_ cause: NiggleTriageInvalid,
                                _ complaint: NiggleComplaint) -> NiggleTriageResult {
        NiggleTriageResult(status: .invalidInput, invalid: cause, isOpen: false, dayCount: nil,
                           currentTrend: complaint.trend, currentWeakness: complaint.weakness,
                           stateDay: nil, ruleId: nil, action: nil, matchedRuleIds: [], nextChange: nil,
                           ignoredUpdates: 0)
    }

    /// The day-count conditions of §7.1 step 9: both bounds are inclusive.
    private static func matchesDay(_ rule: NiggleTriageRule, _ dayCount: Int) -> Bool {
        guard dayCount >= (rule.fromDay ?? firstDayCount) else { return false }
        if let through = rule.throughDay, dayCount > through { return false }
        return true
    }

    /// The winner at a day count (§7.1 step 10): the most serious matching rule; among equals the
    /// earliest in the owner's order; nil when nothing matches. `eligible` holds the rules whose
    /// conditions other than the day count are met, in the owner's order.
    private static func winner(among eligible: [NiggleTriageRule], at dayCount: Int) -> NiggleTriageRule? {
        var best: NiggleTriageRule?
        for rule in eligible where matchesDay(rule, dayCount) {
            if let held = best, severity(rule.action) <= severity(held.action) { continue }
            best = rule
        }
        return best
    }

    /// §7.1 step 11. The day counts at which the set of matching rules can change are each eligible
    /// rule's `fromDay` and the day after its `throughDay`. The first of them, in ascending order, at
    /// which the winner is another rule (or none) is the next change; nil when there is none or when
    /// its day lies after 9999-12-31.
    private static func nextChange(after dayCount: Int, current: NiggleTriageRule?,
                                   eligible: [NiggleTriageRule],
                                   onsetNumber: Int) -> NiggleTriageNextChange? {
        var candidates = Set<Int>()
        for rule in eligible {
            if let from = rule.fromDay, from > dayCount { candidates.insert(from) }
            if let through = rule.throughDay, through >= dayCount, through < Int.max {
                candidates.insert(through + 1)
            }
        }
        for candidate in candidates.sorted() {
            let next = winner(among: eligible, at: candidate)
            guard next?.id != current?.id else { continue }
            // `candidate` is greater than `dayCount`, which is at least 1, and `onsetNumber` is at most
            // `lastDayNumber`, so neither subtraction can overflow.
            let offset = candidate - firstDayCount
            guard offset <= CanonicalDay.lastDayNumber - onsetNumber else { return nil }
            return NiggleTriageNextChange(dayCount: candidate, day: CanonicalDay.key(onsetNumber + offset),
                                          ruleId: next?.id, action: next?.action)
        }
        return nil
    }
}
