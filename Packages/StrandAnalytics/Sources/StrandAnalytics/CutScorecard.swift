import Foundation

// The cut scorecard: a weekly weigh-in series, a fitted rate of loss, four descriptive signals and the
// three feedback rules of a cut phase, reduced to one verdict.
//
// PURE. No store, no clock, no `Calendar`, no `TimeZone`, no `Date`. "Today" and every other day arrive
// as "yyyy-MM-dd" keys, and all day arithmetic is integer civil-date arithmetic (Julian Day Numbers
// through `WeeklyDigestEngine`), so the Kotlin twin can reproduce every result bit for bit.
//
// Missing data is "not measured" (nil or `unknown`), never zero. No threshold, window or amount is a
// literal here: each comes from `CutScorecardParameters` or from the phase.
//
// Units: kilograms for weight and lift loads, centimetres for waist, grams for protein, kilocalories for
// the calorie amounts, percent of bodyweight per week for the band.

// MARK: - Inputs

/// One dated weight (kg) or waist (cm) reading.
public struct CutScorecardReading: Equatable, Sendable {
    public let day: String      // local day the reading was taken, "yyyy-MM-dd"
    public let takenAt: Int     // epoch seconds; used only to order readings that share a day
    public let value: Double    // kg for weight, cm for waist

    public init(day: String, takenAt: Int, value: Double) {
        self.day = day; self.takenAt = takenAt; self.value = value
    }
}

/// One performed working set, reduced to what the lift signal needs.
public struct CutScorecardLiftObservation: Equatable, Sendable {
    public let day: String      // local day the session started
    public let exercise: String // compared byte for byte: no trimming, no case folding
    public let weightKg: Double

    public init(day: String, exercise: String, weightKg: Double) {
        self.day = day; self.exercise = exercise; self.weightKg = weightKg
    }
}

/// One day's protein total.
public struct CutScorecardProteinDay: Equatable, Sendable {
    public let day: String
    public let grams: Double

    public init(day: String, grams: Double) {
        self.day = day; self.grams = grams
    }
}

/// The active cut phase. The app passes nil when no cut phase is active.
public struct CutScorecardPhase: Equatable, Sendable {
    public let name: String
    public let startDay: String
    public let targetWeightKg: Double?          // nil: no target, so no projection
    public let rateLowPercentPerWeek: Double    // expected band, inclusive
    public let rateHighPercentPerWeek: Double

    public init(name: String, startDay: String, targetWeightKg: Double?,
                rateLowPercentPerWeek: Double, rateHighPercentPerWeek: Double) {
        self.name = name; self.startDay = startDay; self.targetWeightKg = targetWeightKg
        self.rateLowPercentPerWeek = rateLowPercentPerWeek
        self.rateHighPercentPerWeek = rateHighPercentPerWeek
    }
}

/// Every threshold, window and amount the rules use. Nothing in `evaluate` is a literal.
public struct CutScorecardParameters: Equatable, Sendable {
    public var rateWindowWeeks: Int
    public var waistWindowWeeks: Int
    public var waistMinDecreaseCm: Double
    public var liftDropTolerancePercent: Double
    public var liftDropShare: Double
    public var liftDropConsecutiveWeeks: Int
    public var addCaloriesKcal: Int
    public var slowLossThresholdKgPerWeek: Double
    public var slowLossConsecutiveWeeks: Int
    public var reduceCarbsKcal: Int
    public var proteinFloorGrams: Double?           // nil: no floor configured
    public var proteinMinDaysPerWeek: Int
    public var maxWeighInAgeWeeks: Int
    public var maxProjectionWeeks: Int
    public var targetToleranceKg: Double

    public init(rateWindowWeeks: Int = 4,
                waistWindowWeeks: Int = 4,
                waistMinDecreaseCm: Double = 0.1,
                liftDropTolerancePercent: Double = 2.5,
                liftDropShare: Double = 0.5,
                liftDropConsecutiveWeeks: Int = 3,
                addCaloriesKcal: Int = 100,
                slowLossThresholdKgPerWeek: Double = 0.25,
                slowLossConsecutiveWeeks: Int = 3,
                reduceCarbsKcal: Int = 100,
                proteinFloorGrams: Double? = nil,
                proteinMinDaysPerWeek: Int = 5,
                maxWeighInAgeWeeks: Int = 1,
                maxProjectionWeeks: Int = 104,
                targetToleranceKg: Double = 0) {
        self.rateWindowWeeks = rateWindowWeeks
        self.waistWindowWeeks = waistWindowWeeks
        self.waistMinDecreaseCm = waistMinDecreaseCm
        self.liftDropTolerancePercent = liftDropTolerancePercent
        self.liftDropShare = liftDropShare
        self.liftDropConsecutiveWeeks = liftDropConsecutiveWeeks
        self.addCaloriesKcal = addCaloriesKcal
        self.slowLossThresholdKgPerWeek = slowLossThresholdKgPerWeek
        self.slowLossConsecutiveWeeks = slowLossConsecutiveWeeks
        self.reduceCarbsKcal = reduceCarbsKcal
        self.proteinFloorGrams = proteinFloorGrams
        self.proteinMinDaysPerWeek = proteinMinDaysPerWeek
        self.maxWeighInAgeWeeks = maxWeighInAgeWeeks
        self.maxProjectionWeeks = maxProjectionWeeks
        self.targetToleranceKg = targetToleranceKg
    }

    /// The initialiser's defaults. Generic; the owner's values replace them in settings.
    public static var generic: CutScorecardParameters { CutScorecardParameters() }
}

/// Everything `CutScorecard.evaluate` reads. Arrays need not be sorted; the result does not depend on
/// their order, except that the later of two protein entries sharing a day wins.
public struct CutScorecardInput: Equatable, Sendable {
    public let weights: [CutScorecardReading]
    public let waists: [CutScorecardReading]
    public let lifts: [CutScorecardLiftObservation]
    public let proteinDays: [CutScorecardProteinDay]
    public let phase: CutScorecardPhase?
    public let parameters: CutScorecardParameters
    public let today: String

    public init(weights: [CutScorecardReading], waists: [CutScorecardReading],
                lifts: [CutScorecardLiftObservation] = [],
                proteinDays: [CutScorecardProteinDay] = [],
                phase: CutScorecardPhase?, parameters: CutScorecardParameters, today: String) {
        self.weights = weights; self.waists = waists; self.lifts = lifts
        self.proteinDays = proteinDays; self.phase = phase; self.parameters = parameters
        self.today = today
    }
}

// MARK: - Outputs

/// Whether a signal holds, does not hold, or could not be measured.
public enum CutScorecardSignalState: String, Equatable, Sendable { case met, notMet, unknown }

/// One Monday week of the series. A week with no weigh-in has nil values; it is never filled, carried
/// forward or interpolated.
public struct CutScorecardWeek: Equatable, Sendable {
    public let weekStart: String        // the Monday
    public let weightKg: Double?        // nil: no weigh-in that week ("not measured")
    public let weightDay: String?
    public let waistCm: Double?
    public let waistDay: String?
    public let inPhase: Bool
    public let weeklyLossKg: Double?    // previous week's weight minus this week's; nil if either is missing

    public init(weekStart: String, weightKg: Double?, weightDay: String?, waistCm: Double?,
                waistDay: String?, inPhase: Bool, weeklyLossKg: Double?) {
        self.weekStart = weekStart; self.weightKg = weightKg; self.weightDay = weightDay
        self.waistCm = waistCm; self.waistDay = waistDay; self.inPhase = inPhase
        self.weeklyLossKg = weeklyLossKg
    }
}

/// The fitted rate of loss over the rate window.
public struct CutScorecardRate: Equatable, Sendable {
    public let lossKgPerWeek: Double    // positive when losing
    public let percentPerWeek: Double   // of `referenceWeightKg`
    public let referenceWeightKg: Double
    public let pointsUsed: Int
    public let spanWeeks: Int
    public let firstWeekStart: String
    public let lastWeekStart: String

    public init(lossKgPerWeek: Double, percentPerWeek: Double, referenceWeightKg: Double,
                pointsUsed: Int, spanWeeks: Int, firstWeekStart: String, lastWeekStart: String) {
        self.lossKgPerWeek = lossKgPerWeek; self.percentPerWeek = percentPerWeek
        self.referenceWeightKg = referenceWeightKg; self.pointsUsed = pointsUsed
        self.spanWeeks = spanWeeks; self.firstWeekStart = firstWeekStart
        self.lastWeekStart = lastWeekStart
    }
}

/// Why no rate could be fitted.
public enum CutScorecardRateUnavailable: String, Equatable, Sendable {
    case noReadings, singleReading, gapLongerThanWindow, weighInOverdue
}

/// The outcome of the target-date projection.
public enum CutScorecardProjectionStatus: String, Equatable, Sendable {
    case projected, noActivePhase, noTarget, targetReached, rateUnknown, notLosing,
         beyondHorizon, needsNewWeighIn, weighInOverdue
}

/// A straight-line extension of the fitted rate to the phase target. An estimate.
public struct CutScorecardProjection: Equatable, Sendable {
    public let status: CutScorecardProjectionStatus
    public let targetDay: String?       // set only when status == .projected
    public let weeksRemaining: Double?  // set only when status == .projected
    public let remainingKg: Double?     // set whenever a phase target and a current weight exist

    public init(status: CutScorecardProjectionStatus, targetDay: String?, weeksRemaining: Double?,
                remainingKg: Double?) {
        self.status = status; self.targetDay = targetDay; self.weeksRemaining = weeksRemaining
        self.remainingKg = remainingKg
    }
}

/// Why the waist signal has the state it has.
public enum CutScorecardWaistReason: String, Equatable, Sendable {
    case shrinking, notShrinking, noWaistThisWeek, noEarlierWaist, weighInOverdue, noReadings
}

/// Whether the waist is shrinking against the earliest reading in its window.
public struct CutScorecardWaistSignal: Equatable, Sendable {
    public let state: CutScorecardSignalState
    public let reason: CutScorecardWaistReason
    public let currentCm: Double?
    public let referenceCm: Double?
    public let referenceWeekStart: String?
    public let changeCm: Double?        // current minus reference; negative when shrinking

    public init(state: CutScorecardSignalState, reason: CutScorecardWaistReason, currentCm: Double?,
                referenceCm: Double?, referenceWeekStart: String?, changeCm: Double?) {
        self.state = state; self.reason = reason; self.currentCm = currentCm
        self.referenceCm = referenceCm; self.referenceWeekStart = referenceWeekStart
        self.changeCm = changeCm
    }
}

/// Why the lift signal has the state it has.
public enum CutScorecardLiftReason: String, Equatable, Sendable {
    case holding, dropping, noLiftData, noSessionsThisWeek, noSessionsPriorWeek,
         noCommonExercises, weighInOverdue, noReadings
}

/// Whether the heaviest working set per exercise is holding or climbing. It sees nothing else: not
/// repetitions, and not whether a lighter week was planned.
public struct CutScorecardLiftSignal: Equatable, Sendable {
    public let state: CutScorecardSignalState
    public let reason: CutScorecardLiftReason
    public let commonExercises: Int
    public let dropped: Int
    public let climbed: Int
    public let held: Int
    public let windowStartDay: String?  // first day of the seven compared
    public let windowEndDay: String?    // last day of the seven compared

    public init(state: CutScorecardSignalState, reason: CutScorecardLiftReason, commonExercises: Int,
                dropped: Int, climbed: Int, held: Int, windowStartDay: String?, windowEndDay: String?) {
        self.state = state; self.reason = reason; self.commonExercises = commonExercises
        self.dropped = dropped; self.climbed = climbed; self.held = held
        self.windowStartDay = windowStartDay; self.windowEndDay = windowEndDay
    }
}

/// Why the protein signal has the state it has.
public enum CutScorecardProteinReason: String, Equatable, Sendable {
    case floorMet, floorMissed, noFloorConfigured, noProteinData, incompleteLogging,
         weighInOverdue, noReadings
}

/// Whether the protein floor was reached on enough of the seven days before the weigh-in. Shown only;
/// it never feeds the verdict.
public struct CutScorecardProteinSignal: Equatable, Sendable {
    public let state: CutScorecardSignalState
    public let reason: CutScorecardProteinReason
    public let daysLogged: Int
    public let daysAtOrAboveFloor: Int
    public let requiredDays: Int
    public let floorGrams: Double?

    public init(state: CutScorecardSignalState, reason: CutScorecardProteinReason, daysLogged: Int,
                daysAtOrAboveFloor: Int, requiredDays: Int, floorGrams: Double?) {
        self.state = state; self.reason = reason; self.daysLogged = daysLogged
        self.daysAtOrAboveFloor = daysAtOrAboveFloor; self.requiredDays = requiredDays
        self.floorGrams = floorGrams
    }
}

/// Why the rate-band signal has the state it has.
public enum CutScorecardRateBandReason: String, Equatable, Sendable {
    case withinBand, belowBand, aboveBand, noActivePhase, rateUnknown, weighInOverdue, noReadings
}

/// Whether the fitted rate lies inside the phase's expected band. Shown only; it never feeds the verdict.
public struct CutScorecardRateBandSignal: Equatable, Sendable {
    public let state: CutScorecardSignalState
    public let reason: CutScorecardRateBandReason
    public let percentPerWeek: Double?
    public let lowPercentPerWeek: Double?
    public let highPercentPerWeek: Double?

    public init(state: CutScorecardSignalState, reason: CutScorecardRateBandReason,
                percentPerWeek: Double?, lowPercentPerWeek: Double?, highPercentPerWeek: Double?) {
        self.state = state; self.reason = reason; self.percentPerWeek = percentPerWeek
        self.lowPercentPerWeek = lowPercentPerWeek; self.highPercentPerWeek = highPercentPerWeek
    }
}

/// The four signals, all describing the judged week.
public struct CutScorecardSignals: Equatable, Sendable {
    public let waist: CutScorecardWaistSignal
    public let lifts: CutScorecardLiftSignal
    public let protein: CutScorecardProteinSignal
    public let rateBand: CutScorecardRateBandSignal

    public init(waist: CutScorecardWaistSignal, lifts: CutScorecardLiftSignal,
                protein: CutScorecardProteinSignal, rateBand: CutScorecardRateBandSignal) {
        self.waist = waist; self.lifts = lifts; self.protein = protein; self.rateBand = rateBand
    }
}

/// The three feedback rules, in precedence order.
public enum CutScorecardRule: String, CaseIterable, Equatable, Sendable {
    case liftsHoldingWaistShrinking     // rule 1: change nothing
    case liftsDropping                  // rule 2: add calories
    case slowLoss                       // rule 3: reduce carbohydrate
}

/// Whether a rule fired, was settled as not firing, or could not be evaluated.
public enum CutScorecardRuleState: String, Equatable, Sendable { case fired, notFired, unknown }

/// Why a rule could not be evaluated.
public enum CutScorecardRuleUnknownReason: String, Equatable, Sendable {
    case liftSignalUnknown, waistSignalUnknown, fewerWeeksThanWindow, missedWeighIn,
         noActivePhase, weighInOverdue, noReadings
}

/// The state of one rule.
public struct CutScorecardRuleEvaluation: Equatable, Sendable {
    public let rule: CutScorecardRule
    public let state: CutScorecardRuleState
    public let unknownReason: CutScorecardRuleUnknownReason?  // set only when state == .unknown
    public let consecutiveWeeks: Int   // weeks, counting back from the judged week, that satisfy the rule's weekly condition
    public let requiredWeeks: Int      // 1 for rule 1; the parameter for rules 2 and 3

    public init(rule: CutScorecardRule, state: CutScorecardRuleState,
                unknownReason: CutScorecardRuleUnknownReason?, consecutiveWeeks: Int, requiredWeeks: Int) {
        self.rule = rule; self.state = state; self.unknownReason = unknownReason
        self.consecutiveWeeks = consecutiveWeeks; self.requiredWeeks = requiredWeeks
    }
}

/// What the verdict advises.
public enum CutScorecardVerdictKind: String, Equatable, Sendable {
    case holdSteady, addCalories, reduceCarbs, insufficientData
}

/// Why the verdict is what it is.
public enum CutScorecardVerdictReason: String, Equatable, Sendable {
    case ruleFired, noChangeRuleFired, recompositionCheckIncomplete, noRuleEvaluable,
         noReadings, noActivePhase, phaseNotStarted, weighInOverdue, invalidInput
}

/// The single outcome of the three rules after precedence.
public struct CutScorecardVerdict: Equatable, Sendable {
    public let kind: CutScorecardVerdictKind
    public let reason: CutScorecardVerdictReason
    public let rule: CutScorecardRule?              // the rule that fired; nil otherwise
    public let calorieChangeKcal: Int?              // +addCaloriesKcal or -reduceCarbsKcal; nil otherwise
    public let overriddenRules: [CutScorecardRule]  // rules that fired but lost on precedence
    public let unevaluatedRules: [CutScorecardRule] // rules that could have changed this verdict and could not be evaluated

    public init(kind: CutScorecardVerdictKind, reason: CutScorecardVerdictReason, rule: CutScorecardRule?,
                calorieChangeKcal: Int?, overriddenRules: [CutScorecardRule],
                unevaluatedRules: [CutScorecardRule]) {
        self.kind = kind; self.reason = reason; self.rule = rule
        self.calorieChangeKcal = calorieChangeKcal; self.overriddenRules = overriddenRules
        self.unevaluatedRules = unevaluatedRules
    }
}

/// Which part of the input made the whole evaluation invalid.
public enum CutScorecardInvalidInput: String, Equatable, Sendable { case parameters, phase, today }

/// How many input items were dropped, by cause. Each dropped item is counted once.
public struct CutScorecardRejections: Equatable, Sendable {
    public let nonFinite: Int
    public let nonPositive: Int
    public let invalidDay: Int
    public let future: Int

    public init(nonFinite: Int, nonPositive: Int, invalidDay: Int, future: Int) {
        self.nonFinite = nonFinite; self.nonPositive = nonPositive
        self.invalidDay = invalidDay; self.future = future
    }
}

/// Everything `CutScorecard.evaluate` returns.
public struct CutScorecardResult: Equatable, Sendable {
    public let weeks: [CutScorecardWeek]            // contiguous, ascending; empty when there is no valid reading
    public let judgedWeekStart: String?
    public let currentWeightKg: Double?             // the newest valid weight on or before today
    public let currentWeightDay: String?
    public let rate: CutScorecardRate?
    public let rateUnavailable: CutScorecardRateUnavailable?  // set exactly when rate is nil
    public let projection: CutScorecardProjection
    public let signals: CutScorecardSignals
    public let rules: [CutScorecardRuleEvaluation]  // always three, in precedence order
    public let verdict: CutScorecardVerdict
    public let evidenceStartDay: String?            // nothing dated before this day can change anything but `weeks`
    public let rejections: CutScorecardRejections
    public let invalidInput: CutScorecardInvalidInput?

    public init(weeks: [CutScorecardWeek], judgedWeekStart: String?, currentWeightKg: Double?,
                currentWeightDay: String?, rate: CutScorecardRate?,
                rateUnavailable: CutScorecardRateUnavailable?, projection: CutScorecardProjection,
                signals: CutScorecardSignals, rules: [CutScorecardRuleEvaluation],
                verdict: CutScorecardVerdict, evidenceStartDay: String?,
                rejections: CutScorecardRejections, invalidInput: CutScorecardInvalidInput?) {
        self.weeks = weeks; self.judgedWeekStart = judgedWeekStart
        self.currentWeightKg = currentWeightKg; self.currentWeightDay = currentWeightDay
        self.rate = rate; self.rateUnavailable = rateUnavailable; self.projection = projection
        self.signals = signals; self.rules = rules; self.verdict = verdict
        self.evidenceStartDay = evidenceStartDay; self.rejections = rejections
        self.invalidInput = invalidInput
    }
}

// MARK: - Evaluation

/// The weekly scorecard of a cut phase: weekly points, the fitted rate of loss, four signals, the three
/// feedback rules and the one verdict their precedence yields.
///
/// The calendar is fixed: proleptic Gregorian, weeks start on Monday. The time zone never reaches this
/// type; each reading arrives with the local day it was taken on.
///
/// Kotlin twin: `CutScorecard`.
public enum CutScorecard {

    // MARK: Public surface

    /// Evaluate the scorecard. Total: never throws and never traps, for any input.
    ///
    /// Kotlin twin: `CutScorecard.evaluate`.
    public static func evaluate(_ input: CutScorecardInput) -> CutScorecardResult {
        let p = input.parameters
        guard parametersAreValid(p) else { return invalidResult(.parameters, p) }
        if let phase = input.phase, !phaseIsValid(phase) { return invalidResult(.phase, p) }
        guard let today = dayNumber(input.today) else { return invalidResult(.today, p) }

        // §7.1 step 1: drop and count.
        var counts = Counts()
        var weightByWeek: [Int: Point] = [:]
        var newestWeight: Point?
        for r in input.weights {
            guard let d = admit(value: r.value, zeroIsValid: false, nameIsEmpty: false, day: r.day,
                                today: today, counts: &counts) else { continue }
            let point = Point(day: d, takenAt: r.takenAt, value: r.value, dayKey: r.day)
            if let held = weightByWeek[d / 7] {
                if held.sortsBefore(point) { weightByWeek[d / 7] = point }
            } else {
                weightByWeek[d / 7] = point
            }
            if let held = newestWeight {
                if held.sortsBefore(point) { newestWeight = point }
            } else {
                newestWeight = point
            }
        }
        var waistByWeek: [Int: Point] = [:]
        for r in input.waists {
            guard let d = admit(value: r.value, zeroIsValid: false, nameIsEmpty: false, day: r.day,
                                today: today, counts: &counts) else { continue }
            let point = Point(day: d, takenAt: r.takenAt, value: r.value, dayKey: r.day)
            if let held = waistByWeek[d / 7] {
                if held.sortsBefore(point) { waistByWeek[d / 7] = point }
            } else {
                waistByWeek[d / 7] = point
            }
        }
        // Greatest working weight per exercise per day.
        var liftsByDay: [Int: [String: Double]] = [:]
        for l in input.lifts {
            guard let d = admit(value: l.weightKg, zeroIsValid: false, nameIsEmpty: l.exercise.isEmpty,
                                day: l.day, today: today, counts: &counts) else { continue }
            if let held = liftsByDay[d]?[l.exercise] {
                if l.weightKg > held { liftsByDay[d]?[l.exercise] = l.weightKg }
            } else {
                liftsByDay[d, default: [:]][l.exercise] = l.weightKg
            }
        }
        // §7.1 step 7: the entry later in the input array wins a shared day.
        var proteinByDay: [Int: Double] = [:]
        for e in input.proteinDays {
            guard let d = admit(value: e.grams, zeroIsValid: true, nameIsEmpty: false, day: e.day,
                                today: today, counts: &counts) else { continue }
            proteinByDay[d] = e.grams
        }
        let rejections = CutScorecardRejections(nonFinite: counts.nonFinite, nonPositive: counts.nonPositive,
                                                invalidDay: counts.invalidDay, future: counts.future)

        // §7.2: phase and domain. `phase.startDay` was validated above, so a nil here cannot occur; it
        // is treated as "no active phase" rather than unwrapped.
        let todayWeek = today / 7
        var activePhase: CutScorecardPhase?
        var domainStart = 0             // week index; 0 lies before every valid week: unclipped
        var notStarted = false
        if let phase = input.phase, let start = dayNumber(phase.startDay) {
            if today < start {
                notStarted = true
            } else {
                activePhase = phase
                domainStart = start / 7
            }
        }
        let isActive = activePhase != nil

        // Weekly points inside the domain, ascending.
        let weightWeeks = weightByWeek.keys.filter { $0 >= domainStart }.sorted()
        let waistWeeks = waistByWeek.keys.filter { $0 >= domainStart }.sorted()

        // §7.3: weekly loss. A missed week is not bridged, and the baseline week has none.
        var lossByWeek: [Int: Double] = [:]
        for w in weightWeeks where w - 1 >= domainStart {
            if let previous = weightByWeek[w - 1], let current = weightByWeek[w] {
                lossByWeek[w] = quantize(previous.value - current.value)
            }
        }

        // §7.1 step 5: one entry per week, earliest reading to today, no gaps.
        var weeks: [CutScorecardWeek] = []
        var firstWeek: Int?
        for w in weightByWeek.keys { if firstWeek.map({ w < $0 }) ?? true { firstWeek = w } }
        for w in waistByWeek.keys { if firstWeek.map({ w < $0 }) ?? true { firstWeek = w } }
        if let first = firstWeek, first <= todayWeek {
            weeks.reserveCapacity(todayWeek - first + 1)
            for w in first...todayWeek {
                let weight = weightByWeek[w]
                let waist = waistByWeek[w]
                weeks.append(CutScorecardWeek(weekStart: dayKey(w * 7),
                                              weightKg: weight?.value, weightDay: weight?.dayKey,
                                              waistCm: waist?.value, waistDay: waist?.dayKey,
                                              inPhase: isActive && w >= domainStart,
                                              weeklyLossKg: lossByWeek[w]))
            }
        }

        // The preconditions of §7.2, in the order the section states them.
        let verdictPrecondition: CutScorecardVerdictReason?
        let judged: Judged?
        let isOverdue: Bool
        if let j = weightWeeks.last, let point = weightByWeek[j] {
            judged = Judged(week: j, point: point)
            isOverdue = todayWeek - j > p.maxWeighInAgeWeeks
        } else {
            judged = nil
            isOverdue = false
        }
        if input.phase == nil {
            verdictPrecondition = .noActivePhase
        } else if notStarted || !isActive {
            verdictPrecondition = notStarted ? .phaseNotStarted : .noActivePhase
        } else if judged == nil {
            verdictPrecondition = .noReadings
        } else if isOverdue {
            verdictPrecondition = .weighInOverdue
        } else {
            verdictPrecondition = nil
        }

        let evidenceStartDay = judged.map { evidenceStart(judgedWeek: $0.week, p) }
        let judgedWeekStart = judged.map { dayKey($0.week * 7) }

        // §18 R6: §7.2 states the overdue rule under an active phase only. It is applied here without
        // a phase as well (rate nil, and the waist, lift and protein signals unknown, with
        // `.weighInOverdue`), because a signal about a stale week is not a current statement whether or
        // not a phase exists. The rate-band signal, the rules, the projection and the verdict still
        // report `.noActivePhase`, as §7.2 says.
        guard let judged = judged, !isOverdue else {
            let noReadings = judged == nil
            let bandReason: CutScorecardRateBandReason =
                !isActive ? .noActivePhase : (noReadings ? .noReadings : .weighInOverdue)
            let ruleReason: CutScorecardRuleUnknownReason =
                !isActive ? .noActivePhase : (noReadings ? .noReadings : .weighInOverdue)
            let signals = CutScorecardSignals(
                waist: CutScorecardWaistSignal(state: .unknown,
                                               reason: noReadings ? .noReadings : .weighInOverdue,
                                               currentCm: nil, referenceCm: nil, referenceWeekStart: nil,
                                               changeCm: nil),
                lifts: CutScorecardLiftSignal(state: .unknown,
                                              reason: noReadings ? .noReadings : .weighInOverdue,
                                              commonExercises: 0, dropped: 0, climbed: 0, held: 0,
                                              windowStartDay: nil, windowEndDay: nil),
                protein: CutScorecardProteinSignal(state: .unknown,
                                                   reason: noReadings ? .noReadings : .weighInOverdue,
                                                   daysLogged: 0, daysAtOrAboveFloor: 0,
                                                   requiredDays: p.proteinMinDaysPerWeek,
                                                   floorGrams: p.proteinFloorGrams),
                rateBand: CutScorecardRateBandSignal(state: .unknown, reason: bandReason,
                                                     percentPerWeek: nil,
                                                     lowPercentPerWeek: activePhase?.rateLowPercentPerWeek,
                                                     highPercentPerWeek: activePhase?.rateHighPercentPerWeek))
            // §18 R8: §7.8 has no status for "an active phase with no in-phase weigh-in" (§7.2 says
            // "everything else is unknown(.noReadings)", and the projection has no such case). The list
            // is followed in order with no weight to evaluate: `noTarget` without a target, otherwise
            // `rateUnknown`, the first later status that is true.
            let projection: CutScorecardProjection
            if let phase = activePhase {
                if let judged = judged {
                    // §18 R9: §6.4 sets `remainingKg` "whenever a phase target and a current weight
                    // exist", so it is reported while overdue too, although §7.8 computes it after the
                    // overdue status.
                    projection = CutScorecardProjection(
                        status: .weighInOverdue, targetDay: nil, weeksRemaining: nil,
                        remainingKg: phase.targetWeightKg.map { quantize(judged.point.value - $0) })
                } else {
                    projection = CutScorecardProjection(
                        status: phase.targetWeightKg == nil ? .noTarget : .rateUnknown,
                        targetDay: nil, weeksRemaining: nil, remainingKg: nil)
                }
            } else {
                projection = CutScorecardProjection(status: .noActivePhase, targetDay: nil,
                                                    weeksRemaining: nil, remainingKg: nil)
            }
            return CutScorecardResult(
                weeks: weeks, judgedWeekStart: judgedWeekStart,
                currentWeightKg: newestWeight?.value, currentWeightDay: newestWeight?.dayKey,
                rate: nil, rateUnavailable: noReadings ? .noReadings : .weighInOverdue,
                projection: projection, signals: signals,
                rules: unknownRules(ruleReason, p),
                verdict: insufficient(verdictPrecondition ?? (noReadings ? .noReadings : .weighInOverdue)),
                evidenceStartDay: evidenceStartDay, rejections: rejections, invalidInput: nil)
        }

        let j = judged.week
        let span = j - domainStart      // whole weeks from the start of the domain to the judged week

        // §7.4: rate of loss.
        let rateWindowStart = p.rateWindowWeeks >= span ? domainStart : j - p.rateWindowWeeks
        var fitWeeks: [Int] = []
        var fitValues: [Double] = []
        for w in weightWeeks where w >= rateWindowStart {
            if let point = weightByWeek[w] { fitWeeks.append(w); fitValues.append(point.value) }
        }
        var rate: CutScorecardRate?
        var rateUnavailable: CutScorecardRateUnavailable?
        if fitWeeks.count >= 2, let firstFitWeek = fitWeeks.first, let lastFitWeek = fitWeeks.last {
            let n = Double(fitWeeks.count)
            var sumX = 0.0, sumY = 0.0
            for i in fitWeeks.indices {
                sumX += Double(fitWeeks[i] - firstFitWeek)
                sumY += fitValues[i]
            }
            let meanX = sumX / n, meanY = sumY / n
            var sxy = 0.0, sxx = 0.0
            for i in fitWeeks.indices {
                let dx = Double(fitWeeks[i] - firstFitWeek) - meanX
                sxy += dx * (fitValues[i] - meanY)
                sxx += dx * dx
            }
            // `sxx` is positive: at least two points, in distinct weeks.
            let loss = quantize(-(sxy / sxx))
            rate = CutScorecardRate(lossKgPerWeek: loss,
                                    percentPerWeek: quantize(100 * loss / meanY),
                                    referenceWeightKg: meanY,
                                    pointsUsed: fitWeeks.count,
                                    spanWeeks: lastFitWeek - firstFitWeek,
                                    firstWeekStart: dayKey(firstFitWeek * 7),
                                    lastWeekStart: dayKey(lastFitWeek * 7))
        } else {
            rateUnavailable = weightWeeks.count <= 1 ? .singleReading : .gapLongerThanWindow
        }

        // §7.5: the four signals, for the judged week.
        let anchor = judged.point.day

        let waistSignal: CutScorecardWaistSignal
        if let current = waistByWeek[j] {
            let waistWindowStart = p.waistWindowWeeks >= span ? domainStart : j - p.waistWindowWeeks
            var reference: (week: Int, point: Point)?
            for w in waistWeeks where w >= waistWindowStart && w < j {
                if let point = waistByWeek[w] { reference = (w, point) }
                break   // ascending: the first week in the window is the earliest
            }
            if let reference = reference {
                let change = quantize(current.value - reference.point.value)
                // §18 R14: a minimum of zero is valid and makes an unchanged waist `met`.
                let shrinking = change <= -quantize(p.waistMinDecreaseCm)
                waistSignal = CutScorecardWaistSignal(state: shrinking ? .met : .notMet,
                                                      reason: shrinking ? .shrinking : .notShrinking,
                                                      currentCm: current.value,
                                                      referenceCm: reference.point.value,
                                                      referenceWeekStart: dayKey(reference.week * 7),
                                                      changeCm: change)
            } else {
                waistSignal = CutScorecardWaistSignal(state: .unknown, reason: .noEarlierWaist,
                                                      currentCm: current.value, referenceCm: nil,
                                                      referenceWeekStart: nil, changeCm: nil)
            }
        } else {
            waistSignal = CutScorecardWaistSignal(state: .unknown, reason: .noWaistThisWeek,
                                                  currentCm: nil, referenceCm: nil,
                                                  referenceWeekStart: nil, changeCm: nil)
        }

        let liftSignal = liftSignalForWeek(anchor: anchor, liftsByDay: liftsByDay, p)

        let proteinSignal: CutScorecardProteinSignal
        do {
            var logged = 0, atOrAbove = 0
            let floor = p.proteinFloorGrams
            for d in (anchor - 7)...(anchor - 1) {
                guard let grams = proteinByDay[d] else { continue }
                logged += 1
                if let floor = floor, quantize(grams) >= quantize(floor) { atOrAbove += 1 }
            }
            let state: CutScorecardSignalState
            let reason: CutScorecardProteinReason
            if floor == nil {
                state = .unknown; reason = .noFloorConfigured
            } else if logged == 0 {
                state = .unknown; reason = .noProteinData
            } else if atOrAbove >= p.proteinMinDaysPerWeek {
                state = .met; reason = .floorMet
            } else if atOrAbove + (7 - logged) < p.proteinMinDaysPerWeek {
                state = .notMet; reason = .floorMissed
            } else {
                state = .unknown; reason = .incompleteLogging
            }
            proteinSignal = CutScorecardProteinSignal(state: state, reason: reason, daysLogged: logged,
                                                      daysAtOrAboveFloor: atOrAbove,
                                                      requiredDays: p.proteinMinDaysPerWeek,
                                                      floorGrams: floor)
        }

        let rateBandSignal: CutScorecardRateBandSignal
        if let phase = activePhase {
            if let rate = rate {
                // §18 R10: §7.5 item 4 writes the band comparison on the raw bounds; §7.1 step 2 says
                // every threshold comparison compares quantized values. The bounds are quantized here.
                let low = quantize(phase.rateLowPercentPerWeek)
                let high = quantize(phase.rateHighPercentPerWeek)
                let reason: CutScorecardRateBandReason =
                    rate.percentPerWeek < low ? .belowBand : (rate.percentPerWeek > high ? .aboveBand : .withinBand)
                rateBandSignal = CutScorecardRateBandSignal(state: reason == .withinBand ? .met : .notMet,
                                                            reason: reason,
                                                            percentPerWeek: rate.percentPerWeek,
                                                            lowPercentPerWeek: phase.rateLowPercentPerWeek,
                                                            highPercentPerWeek: phase.rateHighPercentPerWeek)
            } else {
                rateBandSignal = CutScorecardRateBandSignal(state: .unknown, reason: .rateUnknown,
                                                            percentPerWeek: nil,
                                                            lowPercentPerWeek: phase.rateLowPercentPerWeek,
                                                            highPercentPerWeek: phase.rateHighPercentPerWeek)
            }
        } else {
            rateBandSignal = CutScorecardRateBandSignal(state: .unknown, reason: .noActivePhase,
                                                        percentPerWeek: nil, lowPercentPerWeek: nil,
                                                        highPercentPerWeek: nil)
        }
        let signals = CutScorecardSignals(waist: waistSignal, lifts: liftSignal, protein: proteinSignal,
                                          rateBand: rateBandSignal)

        // No active phase: the series, the rate and three signals stand; nothing is judged.
        guard let phase = activePhase else {
            return CutScorecardResult(
                weeks: weeks, judgedWeekStart: judgedWeekStart,
                currentWeightKg: newestWeight?.value, currentWeightDay: newestWeight?.dayKey,
                rate: rate, rateUnavailable: rateUnavailable,
                projection: CutScorecardProjection(status: .noActivePhase, targetDay: nil,
                                                   weeksRemaining: nil, remainingKg: nil),
                signals: signals, rules: unknownRules(.noActivePhase, p),
                verdict: insufficient(verdictPrecondition ?? .noActivePhase),
                evidenceStartDay: evidenceStartDay, rejections: rejections, invalidInput: nil)
        }

        // §7.6: rule states.
        let rule1: CutScorecardRuleEvaluation
        do {
            let state: CutScorecardRuleState
            var reason: CutScorecardRuleUnknownReason?
            if liftSignal.state == .met && waistSignal.state == .met {
                state = .fired
            } else if liftSignal.state == .notMet || waistSignal.state == .notMet {
                state = .notFired
            } else {
                state = .unknown
                reason = liftSignal.state == .unknown ? .liftSignalUnknown : .waistSignalUnknown
            }
            rule1 = CutScorecardRuleEvaluation(rule: .liftsHoldingWaistShrinking, state: state,
                                               unknownReason: reason,
                                               consecutiveWeeks: state == .fired ? 1 : 0, requiredWeeks: 1)
        }

        let rule2: CutScorecardRuleEvaluation
        do {
            let required = p.liftDropConsecutiveWeeks
            let startsBeforeDomain = required - 1 > span
            let first = startsBeforeDomain ? domainStart : j - (required - 1)
            var anyHolding = false, allDropping = true, anyMissed = false
            var run = 0, runOpen = true
            // §18 R1: the run is not capped at the window. The scan covers the window, then continues
            // back while the run is unbroken. It never leaves the domain, so it is bounded by the
            // number of weeks between the phase start and the judged week.
            var w = j
            while w >= domainStart && (w >= first || runOpen) {
                var status = CutScorecardSignalState.unknown
                if let point = weightByWeek[w] {
                    status = w == j ? liftSignal.state
                                    : liftSignalForWeek(anchor: point.day, liftsByDay: liftsByDay, p).state
                } else if w >= first {
                    anyMissed = true
                }
                if w >= first {
                    if status == .met { anyHolding = true }
                    if status != .notMet { allDropping = false }
                }
                if runOpen { if status == .notMet { run += 1 } else { runOpen = false } }
                w -= 1
            }
            let state: CutScorecardRuleState
            var reason: CutScorecardRuleUnknownReason?
            if anyHolding {
                state = .notFired
            } else if !startsBeforeDomain && allDropping {
                state = .fired
            } else {
                state = .unknown
                reason = startsBeforeDomain ? .fewerWeeksThanWindow
                                            : (anyMissed ? .missedWeighIn : .liftSignalUnknown)
            }
            rule2 = CutScorecardRuleEvaluation(rule: .liftsDropping, state: state, unknownReason: reason,
                                               consecutiveWeeks: run, requiredWeeks: required)
        }

        let rule3: CutScorecardRuleEvaluation
        do {
            let required = p.slowLossConsecutiveWeeks
            let reachesBeforeDomain = required > span   // week J − N₃ lies before the domain
            let first = reachesBeforeDomain ? domainStart : j - (required - 1)
            let threshold = quantize(p.slowLossThresholdKgPerWeek)
            var anyAtOrAbove = false, allKnown = true
            var run = 0, runOpen = true
            // §18 R1: as for rule 2, the run continues past the window while it is unbroken, and stops
            // inside the domain (the baseline week has no weekly loss).
            var w = j
            while w >= domainStart && (w >= first || runOpen) {
                if let loss = lossByWeek[w] {
                    if loss >= threshold {
                        if w >= first { anyAtOrAbove = true }
                        runOpen = false
                    } else if runOpen {
                        run += 1
                    }
                } else {
                    if w >= first { allKnown = false }
                    runOpen = false
                }
                w -= 1
            }
            let state: CutScorecardRuleState
            var reason: CutScorecardRuleUnknownReason?
            if anyAtOrAbove {
                state = .notFired
            } else if !reachesBeforeDomain && allKnown {
                state = .fired
            } else {
                state = .unknown
                reason = reachesBeforeDomain ? .fewerWeeksThanWindow : .missedWeighIn
            }
            rule3 = CutScorecardRuleEvaluation(rule: .slowLoss, state: state, unknownReason: reason,
                                               consecutiveWeeks: run, requiredWeeks: required)
        }

        // §7.7: verdict. Precedence is rule 1, then rule 2, then rule 3; the first matching line wins.
        let verdict: CutScorecardVerdict
        if rule1.state == .fired {
            verdict = CutScorecardVerdict(kind: .holdSteady, reason: .ruleFired,
                                          rule: .liftsHoldingWaistShrinking, calorieChangeKcal: nil,
                                          overriddenRules: rule3.state == .fired ? [.slowLoss] : [],
                                          unevaluatedRules: [])
        } else if rule2.state == .fired {
            verdict = CutScorecardVerdict(kind: .addCalories, reason: .ruleFired, rule: .liftsDropping,
                                          calorieChangeKcal: p.addCaloriesKcal,
                                          overriddenRules: rule3.state == .fired ? [.slowLoss] : [],
                                          unevaluatedRules: [])
        } else if rule3.state == .fired {
            if rule1.state == .unknown {
                var unevaluated: [CutScorecardRule] = [.liftsHoldingWaistShrinking]
                if rule2.state == .unknown { unevaluated.append(.liftsDropping) }
                verdict = CutScorecardVerdict(kind: .insufficientData, reason: .recompositionCheckIncomplete,
                                              rule: nil, calorieChangeKcal: nil, overriddenRules: [],
                                              unevaluatedRules: unevaluated)
            } else {
                verdict = CutScorecardVerdict(kind: .reduceCarbs, reason: .ruleFired, rule: .slowLoss,
                                              calorieChangeKcal: -p.reduceCarbsKcal, overriddenRules: [],
                                              unevaluatedRules: rule2.state == .unknown ? [.liftsDropping] : [])
            }
        } else {
            let unevaluated = [rule1, rule2, rule3].filter { $0.state == .unknown }.map { $0.rule }
            if unevaluated.count == CutScorecardRule.allCases.count {
                verdict = CutScorecardVerdict(kind: .insufficientData, reason: .noRuleEvaluable, rule: nil,
                                              calorieChangeKcal: nil, overriddenRules: [],
                                              unevaluatedRules: unevaluated)
            } else {
                verdict = CutScorecardVerdict(kind: .holdSteady, reason: .noChangeRuleFired, rule: nil,
                                              calorieChangeKcal: nil, overriddenRules: [],
                                              unevaluatedRules: unevaluated)
            }
        }

        // §7.8: projection. The first matching status wins.
        let projection: CutScorecardProjection
        if let target = phase.targetWeightKg {
            let remaining = quantize(judged.point.value - target)
            var status: CutScorecardProjectionStatus
            var targetDay: String?
            var weeksRemaining: Double?
            if remaining <= quantize(p.targetToleranceKg) {
                status = .targetReached
            } else if let rate = rate {
                if rate.lossKgPerWeek <= 0 {
                    status = .notLosing
                } else {
                    let weeksLeft = remaining / rate.lossKgPerWeek
                    // §18 R10: §7.8 step 7 compares the raw quotient with the horizon; §7.1 step 2
                    // says every threshold comparison compares quantized values. The quotient is
                    // quantized for this comparison only; the reported `weeksRemaining` is the raw one.
                    if !weeksLeft.isFinite || quantize(weeksLeft) > Double(p.maxProjectionWeeks) {
                        status = .beyondHorizon
                    } else {
                        var daysNeeded = quantize(weeksLeft * 7).rounded(.up)
                        if daysNeeded < 1 { daysNeeded = 1 }
                        // §18 R11: with an absurd `maxProjectionWeeks` the projected day can lie past
                        // the last representable day key (9999-12-31). §7.8 does not cover it; it is
                        // reported as `beyondHorizon` rather than as a date that cannot be written.
                        if daysNeeded > Double(lastDayNumber - anchor) {
                            status = .beyondHorizon
                        } else {
                            let projected = anchor + Int(daysNeeded)
                            if projected < today {
                                status = .needsNewWeighIn
                            } else {
                                status = .projected
                                targetDay = dayKey(projected)
                                weeksRemaining = weeksLeft
                            }
                        }
                    }
                }
            } else {
                status = .rateUnknown
            }
            projection = CutScorecardProjection(status: status, targetDay: targetDay,
                                                weeksRemaining: weeksRemaining, remainingKg: remaining)
        } else {
            projection = CutScorecardProjection(status: .noTarget, targetDay: nil, weeksRemaining: nil,
                                                remainingKg: nil)
        }

        return CutScorecardResult(
            weeks: weeks, judgedWeekStart: judgedWeekStart,
            currentWeightKg: newestWeight?.value, currentWeightDay: newestWeight?.dayKey,
            rate: rate, rateUnavailable: rateUnavailable, projection: projection, signals: signals,
            rules: [rule1, rule2, rule3], verdict: verdict, evidenceStartDay: evidenceStartDay,
            rejections: rejections, invalidInput: nil)
    }

    /// The Monday of the week containing `day`. Forwards to `WeeklyDigestEngine.mondayOfWeek`.
    ///
    /// Nil unless `day` is a canonical "yyyy-MM-dd" key of a real date in years 0001 to 9999.
    ///
    /// Kotlin twin: `CutScorecard.weekStart`.
    public static func weekStart(containing day: String) -> String? {
        guard dayNumber(day) != nil else { return nil }
        return WeeklyDigestEngine.mondayOfWeek(containing: day)
    }

    /// Round to three decimals, halves away from zero. Every comparison in `evaluate` uses it.
    ///
    /// `sign(x) × floor(|x| × 1000 + 0.5) ÷ 1000`, written out because library rounding functions
    /// disagree on halves across platforms. The Kotlin twin implements this expression.
    ///
    /// Kotlin twin: `CutScorecard.quantize`.
    public static func quantize(_ x: Double) -> Double {
        let scaled = abs(x) * 1000 + 0.5
        // §18 R4: §7.1's expression overflows to infinity for magnitudes above about 1.8e305. Such a
        // value has no fractional part to round, so it is returned unchanged. NaN is returned as NaN.
        guard scaled.isFinite else { return x }
        let magnitude = scaled.rounded(.down) / 1000
        // §18 R4: the expression yields negative zero for a small negative input. Positive zero is
        // returned instead, so a formatted result (the parity oracle prints "%.6f") cannot differ by
        // sign alone.
        if magnitude == 0 { return 0 }
        return x < 0 ? -magnitude : magnitude
    }

    // MARK: Private model

    /// A valid reading with its day as a Julian Day Number.
    private struct Point {
        let day: Int
        let takenAt: Int
        let value: Double
        let dayKey: String

        /// Ascending order by `(day, takenAt, value)`; the reading that sorts last represents its week.
        ///
        /// Kotlin twin: `Point.sortsBefore`.
        func sortsBefore(_ other: Point) -> Bool {
            if day != other.day { return day < other.day }
            if takenAt != other.takenAt { return takenAt < other.takenAt }
            return value < other.value
        }
    }

    /// The judged week and its representative weight reading.
    private struct Judged {
        let week: Int
        let point: Point
    }

    /// Running rejection counters.
    private struct Counts {
        var nonFinite = 0
        var nonPositive = 0
        var invalidDay = 0
        var future = 0
    }

    // §18 R3: §6.5 names only NaN and infinity as `nonFinite`. A finite value above this magnitude is
    // rejected under the same counter (and a parameter or phase bound above it is invalid input), because the sums and products of §7.4 would otherwise overflow
    // to infinity or NaN and reach the output. It is an arithmetic limit, not a plausibility range: it
    // lies some ninety orders of magnitude above any quantity the units of §6.2 can describe.
    /// The largest reading magnitude the arithmetic accepts.
    private static let largestValueMagnitude = 1e100

    // §18 R5: §6.1 names the day key "yyyy-MM-dd" without saying whether `WeeklyDigestEngine.parseYMD`'s
    // looser forms ("2031-1-8", "+2031-01-08") are valid. Only the canonical ten-character form in years
    // 0001 to 9999 is accepted, so that a day has exactly one key, string and calendar order agree, and
    // the integer date arithmetic (Sakamoto's weekday, the Julian Day Number) stays inside the range in
    // which it is correct and cannot overflow.
    /// 0001-01-01 as a Julian Day Number. It is a Monday, so no week starts before it.
    private static let firstDayNumber = 1_721_426
    /// 9999-12-31 as a Julian Day Number.
    private static let lastDayNumber = 5_373_484

    // MARK: Private helpers

    /// The Julian Day Number of a canonical day key, or nil. Julian Day Numbers divisible by seven are
    /// Mondays, so `number / 7` is a week index and `index * 7` that week's Monday.
    ///
    /// Kotlin twin: `CutScorecard.dayNumber`.
    private static func dayNumber(_ key: String) -> Int? {
        guard key.utf8.count == 10, let (y, m, d) = WeeklyDigestEngine.parseYMD(key),
              y >= 1, y <= 9999, WeeklyDigestEngine.formatYMD(y, m, d) == key else { return nil }
        return WeeklyDigestEngine.julianDayNumber(y, m, d)
    }

    /// The day key of a Julian Day Number, clamped to the representable range.
    ///
    /// Kotlin twin: `CutScorecard.dayKey`.
    private static func dayKey(_ number: Int) -> String {
        let clamped = min(max(number, firstDayNumber), lastDayNumber)
        let (y, m, d) = WeeklyDigestEngine.fromJulianDayNumber(clamped)
        return WeeklyDigestEngine.formatYMD(y, m, d)
    }

    /// Validate one input item in the order §6.5 lists the causes. Returns its day number when it is
    /// kept; otherwise counts the one cause and returns nil.
    ///
    /// Kotlin twin: `CutScorecard.admit`.
    private static func admit(value: Double, zeroIsValid: Bool, nameIsEmpty: Bool, day: String,
                              today: Int, counts: inout Counts) -> Int? {
        guard value.isFinite, abs(value) <= largestValueMagnitude else { counts.nonFinite += 1; return nil }
        guard value > 0 || (zeroIsValid && value == 0) else { counts.nonPositive += 1; return nil }
        guard !nameIsEmpty, let number = dayNumber(day) else { counts.invalidDay += 1; return nil }
        guard number <= today else { counts.future += 1; return nil }
        return number
    }

    /// §6.5: invalid parameters.
    ///
    /// Kotlin twin: `CutScorecard.parametersAreValid`.
    private static func parametersAreValid(_ p: CutScorecardParameters) -> Bool {
        guard p.waistMinDecreaseCm.isFinite, p.liftDropTolerancePercent.isFinite, p.liftDropShare.isFinite,
              p.slowLossThresholdKgPerWeek.isFinite, p.targetToleranceKg.isFinite else { return false }
        // §18 R3: a Double parameter above the arithmetic limit is invalid input.
        guard abs(p.waistMinDecreaseCm) <= largestValueMagnitude,
              abs(p.slowLossThresholdKgPerWeek) <= largestValueMagnitude,
              abs(p.targetToleranceKg) <= largestValueMagnitude else { return false }
        if let floor = p.proteinFloorGrams {
            guard floor.isFinite, floor > 0, floor <= largestValueMagnitude else { return false }
        }
        guard p.rateWindowWeeks >= 1, p.waistWindowWeeks >= 1, p.liftDropConsecutiveWeeks >= 1,
              p.slowLossConsecutiveWeeks >= 1, p.maxWeighInAgeWeeks >= 0, p.maxProjectionWeeks >= 1
        else { return false }
        guard p.liftDropTolerancePercent >= 0, p.liftDropTolerancePercent < 100,
              p.liftDropShare > 0, p.liftDropShare <= 1 else { return false }
        guard p.waistMinDecreaseCm >= 0, p.slowLossThresholdKgPerWeek >= 0, p.targetToleranceKg >= 0,
              p.addCaloriesKcal >= 0, p.reduceCarbsKcal >= 0 else { return false }
        return (1...7).contains(p.proteinMinDaysPerWeek)
    }

    /// §6.5: an invalid phase.
    ///
    /// Kotlin twin: `CutScorecard.phaseIsValid`.
    private static func phaseIsValid(_ phase: CutScorecardPhase) -> Bool {
        guard dayNumber(phase.startDay) != nil else { return false }
        if let target = phase.targetWeightKg {
            guard target.isFinite, target > 0, target <= largestValueMagnitude else { return false }
        }
        // §18 R3: a target or band bound above the arithmetic limit is invalid input.
        let low = phase.rateLowPercentPerWeek, high = phase.rateHighPercentPerWeek
        return low.isFinite && high.isFinite && low >= 0 && high >= 0 && low <= high
            && high <= largestValueMagnitude
    }

    /// §7.5 item 2: the lift status of a week whose representative weigh-in fell on `anchor`.
    ///
    /// Kotlin twin: `CutScorecard.liftSignalForWeek`.
    private static func liftSignalForWeek(anchor: Int, liftsByDay: [Int: [String: Double]],
                                          _ p: CutScorecardParameters) -> CutScorecardLiftSignal {
        let windowStart = dayKey(anchor - 7), windowEnd = dayKey(anchor - 1)
        /// Kotlin twin: `CutScorecard.unknown`.
        func unknown(_ reason: CutScorecardLiftReason) -> CutScorecardLiftSignal {
            CutScorecardLiftSignal(state: .unknown, reason: reason, commonExercises: 0, dropped: 0,
                                   climbed: 0, held: 0, windowStartDay: windowStart, windowEndDay: windowEnd)
        }
        /// Kotlin twin: `CutScorecard.heaviest`.
        func heaviest(from first: Int, through last: Int) -> [String: Double] {
            var best: [String: Double] = [:]
            for d in first...last {
                guard let day = liftsByDay[d] else { continue }
                for (exercise, kg) in day {
                    if let held = best[exercise] {
                        if kg > held { best[exercise] = kg }
                    } else {
                        best[exercise] = kg
                    }
                }
            }
            return best
        }
        if liftsByDay.isEmpty { return unknown(.noLiftData) }
        let current = heaviest(from: anchor - 7, through: anchor - 1)
        if current.isEmpty { return unknown(.noSessionsThisWeek) }
        let previous = heaviest(from: anchor - 14, through: anchor - 8)
        if previous.isEmpty { return unknown(.noSessionsPriorWeek) }

        var common = 0, dropped = 0, climbed = 0, held = 0
        let keep = 1 - p.liftDropTolerancePercent / 100
        for (exercise, now) in current {
            guard let before = previous[exercise] else { continue }
            common += 1
            let quantizedNow = quantize(now)
            if quantizedNow < quantize(before * keep) {
                dropped += 1
            } else if quantizedNow > quantize(before) {
                climbed += 1
            } else {
                held += 1
            }
        }
        if common == 0 { return unknown(.noCommonExercises) }
        // §18 R10: §7.5 writes `dropped ÷ common >= liftDropShare` on raw values; §7.1 step 2 says
        // every threshold comparison compares quantized values. Both sides are quantized, so a share of
        // one third meets a configured 0.333.
        let dropping = dropped >= 1 && quantize(Double(dropped) / Double(common)) >= quantize(p.liftDropShare)
        return CutScorecardLiftSignal(state: dropping ? .notMet : .met, reason: dropping ? .dropping : .holding,
                                      commonExercises: common, dropped: dropped, climbed: climbed, held: held,
                                      windowStartDay: windowStart, windowEndDay: windowEnd)
    }

    // §18 R2: an item dated before this day never changes a signal state, a rule state, the verdict,
    // the rate or the projection. It may change `weeks`; `rateUnavailable` (§7.4 chooses
    // `.singleReading` or `.gapLongerThanWindow` by whether ANY older in-phase weight exists); the lift
    // reason (§7.5 chooses `.noLiftData` by whether ANY valid lift observation exists); and
    // `consecutiveWeeks`, whose run is not capped (§18 R1).
    // §18 R11: with an absurd window parameter the formula of §7.9 lies before 0001-01-01, which has
    // no day key. It is clamped to "0001-01-01"; no valid item can be dated earlier.
    /// §7.9: `J − 7 × (m + 2)` days, `m` the widest window.
    ///
    /// Kotlin twin: `CutScorecard.evidenceStart`.
    private static func evidenceStart(judgedWeek: Int, _ p: CutScorecardParameters) -> String {
        let widest = max(max(p.rateWindowWeeks, p.waistWindowWeeks),
                         max(p.slowLossConsecutiveWeeks, p.liftDropConsecutiveWeeks))
        let monday = judgedWeek * 7
        let weeksAvailable = (monday - firstDayNumber) / 7
        guard widest <= weeksAvailable - 2 else { return dayKey(firstDayNumber) }
        return dayKey(monday - 7 * (widest + 2))
    }

    /// Three rules that could not be evaluated, all for one reason.
    ///
    /// Kotlin twin: `CutScorecard.unknownRules`.
    private static func unknownRules(_ reason: CutScorecardRuleUnknownReason,
                                     _ p: CutScorecardParameters) -> [CutScorecardRuleEvaluation] {
        [CutScorecardRuleEvaluation(rule: .liftsHoldingWaistShrinking, state: .unknown, unknownReason: reason,
                                    consecutiveWeeks: 0, requiredWeeks: 1),
         CutScorecardRuleEvaluation(rule: .liftsDropping, state: .unknown, unknownReason: reason,
                                    consecutiveWeeks: 0, requiredWeeks: p.liftDropConsecutiveWeeks),
         CutScorecardRuleEvaluation(rule: .slowLoss, state: .unknown, unknownReason: reason,
                                    consecutiveWeeks: 0, requiredWeeks: p.slowLossConsecutiveWeeks)]
    }

    /// §7.7 line 0: a precondition failed.
    ///
    /// Kotlin twin: `CutScorecard.insufficient`.
    private static func insufficient(_ reason: CutScorecardVerdictReason) -> CutScorecardVerdict {
        CutScorecardVerdict(kind: .insufficientData, reason: reason, rule: nil, calorieChangeKcal: nil,
                            overriddenRules: [], unevaluatedRules: [])
    }

    // §18 R13: §6.5 does not say what the invalid result's echoed parameter fields hold.
    // `requiredWeeks` and `requiredDays` echo the parameters as given (integers, possibly the invalid
    // ones); `floorGrams` echoes the floor only when it is finite and positive, so no NaN or infinity
    // reaches the output. `currentWeightKg`, `judgedWeekStart` and `evidenceStartDay` are nil.
    /// §6.5: the result for invalid parameters, an invalid phase or an unparseable `today`.
    ///
    /// Kotlin twin: `CutScorecard.invalidResult`.
    private static func invalidResult(_ cause: CutScorecardInvalidInput,
                                      _ p: CutScorecardParameters) -> CutScorecardResult {
        var floor: Double?
        if let configured = p.proteinFloorGrams, configured.isFinite, configured > 0 { floor = configured }
        let signals = CutScorecardSignals(
            waist: CutScorecardWaistSignal(state: .unknown, reason: .noReadings, currentCm: nil,
                                           referenceCm: nil, referenceWeekStart: nil, changeCm: nil),
            lifts: CutScorecardLiftSignal(state: .unknown, reason: .noReadings, commonExercises: 0,
                                          dropped: 0, climbed: 0, held: 0, windowStartDay: nil,
                                          windowEndDay: nil),
            protein: CutScorecardProteinSignal(state: .unknown, reason: .noReadings, daysLogged: 0,
                                               daysAtOrAboveFloor: 0, requiredDays: p.proteinMinDaysPerWeek,
                                               floorGrams: floor),
            rateBand: CutScorecardRateBandSignal(state: .unknown, reason: .noReadings, percentPerWeek: nil,
                                                 lowPercentPerWeek: nil, highPercentPerWeek: nil))
        return CutScorecardResult(
            weeks: [], judgedWeekStart: nil, currentWeightKg: nil, currentWeightDay: nil,
            rate: nil, rateUnavailable: .noReadings,
            projection: CutScorecardProjection(status: .noActivePhase, targetDay: nil, weeksRemaining: nil,
                                               remainingKg: nil),
            signals: signals, rules: unknownRules(.noReadings, p), verdict: insufficient(.invalidInput),
            evidenceStartDay: nil,
            rejections: CutScorecardRejections(nonFinite: 0, nonPositive: 0, invalidDay: 0, future: 0),
            invalidInput: cause)
    }
}
