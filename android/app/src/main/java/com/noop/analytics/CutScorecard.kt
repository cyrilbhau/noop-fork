package com.noop.analytics

import java.text.Normalizer
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor

// The cut scorecard: a weekly weigh-in series, a fitted rate of loss, four descriptive signals and the
// three feedback rules of a cut phase, reduced to one verdict.
//
// PURE. No store, no clock, no java.time, no Calendar, no locale. "Today" and every other day arrive as
// "yyyy-MM-dd" keys, and all day arithmetic is integer civil-date arithmetic (Julian Day Numbers
// through WeeklyDigestEngine).
//
// This file mirrors Packages/StrandAnalytics/Sources/StrandAnalytics/CutScorecard.swift operation for
// operation: the same accumulation order, the same quantize expression, the same limits. Every Swift
// `Int` is a `Long` here, because a Swift `Int` is 64 bits wide. Change the two files together and
// regenerate the oracle (Tools/personal/cut_scorecard_oracle.sh).
//
// Missing data is "not measured" (null or UNKNOWN), never zero. No threshold, window or amount is a
// literal here: each comes from CutScorecardParameters or from the phase.
//
// Units: kilograms for weight and lift loads, centimetres for waist, grams for protein, kilocalories for
// the calorie amounts, percent of bodyweight per week for the band.

// MARK: - Inputs

/** One dated weight (kg) or waist (cm) reading. */
data class CutScorecardReading(
    /** Local day the reading was taken, "yyyy-MM-dd". */
    val day: String,
    /** Epoch seconds; used only to order readings that share a day. */
    val takenAt: Long,
    /** kg for weight, cm for waist. */
    val value: Double,
)

/** One performed working set, reduced to what the lift signal needs. */
data class CutScorecardLiftObservation(
    /** Local day the session started. */
    val day: String,
    /** Compared the way Swift compares a `String`: by canonical equivalence, no trimming, no case folding. */
    val exercise: String,
    val weightKg: Double,
)

/** One day's protein total. */
data class CutScorecardProteinDay(val day: String, val grams: Double)

/** The active cut phase. The app passes null when no cut phase is active. */
data class CutScorecardPhase(
    val name: String,
    val startDay: String,
    /** null: no target, so no projection. */
    val targetWeightKg: Double?,
    /** Expected band, inclusive. */
    val rateLowPercentPerWeek: Double,
    val rateHighPercentPerWeek: Double,
)

/** Every threshold, window and amount the rules use. Nothing in `evaluate` is a literal. */
data class CutScorecardParameters(
    val rateWindowWeeks: Long = 4,
    val waistWindowWeeks: Long = 4,
    val waistMinDecreaseCm: Double = 0.1,
    val liftDropTolerancePercent: Double = 2.5,
    val liftDropShare: Double = 0.5,
    val liftDropConsecutiveWeeks: Long = 3,
    val addCaloriesKcal: Long = 100,
    val slowLossThresholdKgPerWeek: Double = 0.25,
    val slowLossConsecutiveWeeks: Long = 3,
    val reduceCarbsKcal: Long = 100,
    /** null: no floor configured. */
    val proteinFloorGrams: Double? = null,
    val proteinMinDaysPerWeek: Long = 5,
    val maxWeighInAgeWeeks: Long = 1,
    val maxProjectionWeeks: Long = 104,
    val targetToleranceKg: Double = 0.0,
) {
    companion object {
        /** The constructor's defaults. Generic; the owner's values replace them in settings. */
        val GENERIC: CutScorecardParameters get() = CutScorecardParameters()
    }
}

/**
 * Everything `CutScorecard.evaluate` reads. Lists need not be sorted; the result does not depend on
 * their order, except that the later of two protein entries sharing a day wins.
 */
data class CutScorecardInput(
    val weights: List<CutScorecardReading>,
    val waists: List<CutScorecardReading>,
    val lifts: List<CutScorecardLiftObservation> = emptyList(),
    val proteinDays: List<CutScorecardProteinDay> = emptyList(),
    val phase: CutScorecardPhase?,
    val parameters: CutScorecardParameters,
    val today: String,
)

// MARK: - Outputs

/** Whether a signal holds, does not hold, or could not be measured. */
enum class CutScorecardSignalState(val raw: String) { MET("met"), NOT_MET("notMet"), UNKNOWN("unknown") }

/**
 * One Monday week of the series. A week with no weigh-in has null values; it is never filled, carried
 * forward or interpolated.
 */
data class CutScorecardWeek(
    /** The Monday. */
    val weekStart: String,
    /** null: no weigh-in that week ("not measured"). */
    val weightKg: Double?,
    val weightDay: String?,
    val waistCm: Double?,
    val waistDay: String?,
    val inPhase: Boolean,
    /** Previous week's weight minus this week's; null if either is missing. */
    val weeklyLossKg: Double?,
)

/** The fitted rate of loss over the rate window. */
data class CutScorecardRate(
    /** Positive when losing. */
    val lossKgPerWeek: Double,
    /** Of [referenceWeightKg]. */
    val percentPerWeek: Double,
    val referenceWeightKg: Double,
    val pointsUsed: Long,
    val spanWeeks: Long,
    val firstWeekStart: String,
    val lastWeekStart: String,
)

/** Why no rate could be fitted. */
enum class CutScorecardRateUnavailable(val raw: String) {
    NO_READINGS("noReadings"),
    SINGLE_READING("singleReading"),
    GAP_LONGER_THAN_WINDOW("gapLongerThanWindow"),
    WEIGH_IN_OVERDUE("weighInOverdue"),
}

/** The outcome of the target-date projection. */
enum class CutScorecardProjectionStatus(val raw: String) {
    PROJECTED("projected"),
    NO_ACTIVE_PHASE("noActivePhase"),
    NO_TARGET("noTarget"),
    TARGET_REACHED("targetReached"),
    RATE_UNKNOWN("rateUnknown"),
    NOT_LOSING("notLosing"),
    BEYOND_HORIZON("beyondHorizon"),
    NEEDS_NEW_WEIGH_IN("needsNewWeighIn"),
    WEIGH_IN_OVERDUE("weighInOverdue"),
}

/** A straight-line extension of the fitted rate to the phase target. An estimate. */
data class CutScorecardProjection(
    val status: CutScorecardProjectionStatus,
    /** Set only when status is PROJECTED. */
    val targetDay: String?,
    /** Set only when status is PROJECTED. */
    val weeksRemaining: Double?,
    /** Set whenever a phase target and a current weight exist. */
    val remainingKg: Double?,
)

/** Why the waist signal has the state it has. */
enum class CutScorecardWaistReason(val raw: String) {
    SHRINKING("shrinking"),
    NOT_SHRINKING("notShrinking"),
    NO_WAIST_THIS_WEEK("noWaistThisWeek"),
    NO_EARLIER_WAIST("noEarlierWaist"),
    WEIGH_IN_OVERDUE("weighInOverdue"),
    NO_READINGS("noReadings"),
}

/** Whether the waist is shrinking against the earliest reading in its window. */
data class CutScorecardWaistSignal(
    val state: CutScorecardSignalState,
    val reason: CutScorecardWaistReason,
    val currentCm: Double?,
    val referenceCm: Double?,
    val referenceWeekStart: String?,
    /** Current minus reference; negative when shrinking. */
    val changeCm: Double?,
)

/** Why the lift signal has the state it has. */
enum class CutScorecardLiftReason(val raw: String) {
    HOLDING("holding"),
    DROPPING("dropping"),
    NO_LIFT_DATA("noLiftData"),
    NO_SESSIONS_THIS_WEEK("noSessionsThisWeek"),
    NO_SESSIONS_PRIOR_WEEK("noSessionsPriorWeek"),
    NO_COMMON_EXERCISES("noCommonExercises"),
    WEIGH_IN_OVERDUE("weighInOverdue"),
    NO_READINGS("noReadings"),
}

/**
 * Whether the heaviest working set per exercise is holding or climbing. It sees nothing else: not
 * repetitions, and not whether a lighter week was planned.
 */
data class CutScorecardLiftSignal(
    val state: CutScorecardSignalState,
    val reason: CutScorecardLiftReason,
    val commonExercises: Long,
    val dropped: Long,
    val climbed: Long,
    val held: Long,
    /** First day of the seven compared. */
    val windowStartDay: String?,
    /** Last day of the seven compared. */
    val windowEndDay: String?,
)

/** Why the protein signal has the state it has. */
enum class CutScorecardProteinReason(val raw: String) {
    FLOOR_MET("floorMet"),
    FLOOR_MISSED("floorMissed"),
    NO_FLOOR_CONFIGURED("noFloorConfigured"),
    NO_PROTEIN_DATA("noProteinData"),
    INCOMPLETE_LOGGING("incompleteLogging"),
    WEIGH_IN_OVERDUE("weighInOverdue"),
    NO_READINGS("noReadings"),
}

/**
 * Whether the protein floor was reached on enough of the seven days before the weigh-in. Shown only;
 * it never feeds the verdict.
 */
data class CutScorecardProteinSignal(
    val state: CutScorecardSignalState,
    val reason: CutScorecardProteinReason,
    val daysLogged: Long,
    val daysAtOrAboveFloor: Long,
    val requiredDays: Long,
    val floorGrams: Double?,
)

/** Why the rate-band signal has the state it has. */
enum class CutScorecardRateBandReason(val raw: String) {
    WITHIN_BAND("withinBand"),
    BELOW_BAND("belowBand"),
    ABOVE_BAND("aboveBand"),
    NO_ACTIVE_PHASE("noActivePhase"),
    RATE_UNKNOWN("rateUnknown"),
    WEIGH_IN_OVERDUE("weighInOverdue"),
    NO_READINGS("noReadings"),
}

/** Whether the fitted rate lies inside the phase's expected band. Shown only; it never feeds the verdict. */
data class CutScorecardRateBandSignal(
    val state: CutScorecardSignalState,
    val reason: CutScorecardRateBandReason,
    val percentPerWeek: Double?,
    val lowPercentPerWeek: Double?,
    val highPercentPerWeek: Double?,
)

/** The four signals, all describing the judged week. */
data class CutScorecardSignals(
    val waist: CutScorecardWaistSignal,
    val lifts: CutScorecardLiftSignal,
    val protein: CutScorecardProteinSignal,
    val rateBand: CutScorecardRateBandSignal,
)

/** The three feedback rules, in precedence order. */
enum class CutScorecardRule(val raw: String) {
    /** Rule 1: change nothing. */
    LIFTS_HOLDING_WAIST_SHRINKING("liftsHoldingWaistShrinking"),
    /** Rule 2: add calories. */
    LIFTS_DROPPING("liftsDropping"),
    /** Rule 3: reduce carbohydrate. */
    SLOW_LOSS("slowLoss"),
}

/** Whether a rule fired, was settled as not firing, or could not be evaluated. */
enum class CutScorecardRuleState(val raw: String) { FIRED("fired"), NOT_FIRED("notFired"), UNKNOWN("unknown") }

/** Why a rule could not be evaluated. */
enum class CutScorecardRuleUnknownReason(val raw: String) {
    LIFT_SIGNAL_UNKNOWN("liftSignalUnknown"),
    WAIST_SIGNAL_UNKNOWN("waistSignalUnknown"),
    FEWER_WEEKS_THAN_WINDOW("fewerWeeksThanWindow"),
    MISSED_WEIGH_IN("missedWeighIn"),
    NO_ACTIVE_PHASE("noActivePhase"),
    WEIGH_IN_OVERDUE("weighInOverdue"),
    NO_READINGS("noReadings"),
}

/** The state of one rule. */
data class CutScorecardRuleEvaluation(
    val rule: CutScorecardRule,
    val state: CutScorecardRuleState,
    /** Set only when state is UNKNOWN. */
    val unknownReason: CutScorecardRuleUnknownReason?,
    /** Weeks, counting back from the judged week, that satisfy the rule's weekly condition. */
    val consecutiveWeeks: Long,
    /** 1 for rule 1; the parameter for rules 2 and 3. */
    val requiredWeeks: Long,
)

/** What the verdict advises. */
enum class CutScorecardVerdictKind(val raw: String) {
    HOLD_STEADY("holdSteady"),
    ADD_CALORIES("addCalories"),
    REDUCE_CARBS("reduceCarbs"),
    INSUFFICIENT_DATA("insufficientData"),
}

/** Why the verdict is what it is. */
enum class CutScorecardVerdictReason(val raw: String) {
    RULE_FIRED("ruleFired"),
    NO_CHANGE_RULE_FIRED("noChangeRuleFired"),
    RECOMPOSITION_CHECK_INCOMPLETE("recompositionCheckIncomplete"),
    NO_RULE_EVALUABLE("noRuleEvaluable"),
    NO_READINGS("noReadings"),
    NO_ACTIVE_PHASE("noActivePhase"),
    PHASE_NOT_STARTED("phaseNotStarted"),
    WEIGH_IN_OVERDUE("weighInOverdue"),
    INVALID_INPUT("invalidInput"),
}

/** The single outcome of the three rules after precedence. */
data class CutScorecardVerdict(
    val kind: CutScorecardVerdictKind,
    val reason: CutScorecardVerdictReason,
    /** The rule that fired; null otherwise. */
    val rule: CutScorecardRule?,
    /** +addCaloriesKcal or -reduceCarbsKcal; null otherwise. */
    val calorieChangeKcal: Long?,
    /** Rules that fired but lost on precedence. */
    val overriddenRules: List<CutScorecardRule>,
    /** Rules that could have changed this verdict and could not be evaluated. */
    val unevaluatedRules: List<CutScorecardRule>,
)

/** Which part of the input made the whole evaluation invalid. */
enum class CutScorecardInvalidInput(val raw: String) { PARAMETERS("parameters"), PHASE("phase"), TODAY("today") }

/** How many input items were dropped, by cause. Each dropped item is counted once. */
data class CutScorecardRejections(
    val nonFinite: Long,
    val nonPositive: Long,
    val invalidDay: Long,
    val future: Long,
)

/** Everything `CutScorecard.evaluate` returns. */
data class CutScorecardResult(
    /** Contiguous, ascending; empty when there is no valid reading. */
    val weeks: List<CutScorecardWeek>,
    val judgedWeekStart: String?,
    /** The newest valid weight on or before today. */
    val currentWeightKg: Double?,
    val currentWeightDay: String?,
    val rate: CutScorecardRate?,
    /** Set exactly when [rate] is null. */
    val rateUnavailable: CutScorecardRateUnavailable?,
    val projection: CutScorecardProjection,
    val signals: CutScorecardSignals,
    /** Always three, in precedence order. */
    val rules: List<CutScorecardRuleEvaluation>,
    val verdict: CutScorecardVerdict,
    /** Nothing dated before this day can change anything but [weeks]. */
    val evidenceStartDay: String?,
    val rejections: CutScorecardRejections,
    val invalidInput: CutScorecardInvalidInput?,
)

// MARK: - Evaluation

/**
 * The weekly scorecard of a cut phase: weekly points, the fitted rate of loss, four signals, the three
 * feedback rules and the one verdict their precedence yields.
 *
 * The calendar is fixed: proleptic Gregorian, weeks start on Monday. The time zone never reaches this
 * type; each reading arrives with the local day it was taken on.
 *
 * Swift twin: `CutScorecard`.
 */
object CutScorecard {

    // MARK: Public surface

    /**
     * Evaluate the scorecard. Total: never throws, for any input.
     *
     * Swift twin: `CutScorecard.evaluate`.
     */
    fun evaluate(input: CutScorecardInput): CutScorecardResult {
        val p = input.parameters
        if (!parametersAreValid(p)) return invalidResult(CutScorecardInvalidInput.PARAMETERS, p)
        val inputPhase = input.phase
        if (inputPhase != null && !phaseIsValid(inputPhase)) return invalidResult(CutScorecardInvalidInput.PHASE, p)
        val today: Long = dayNumber(input.today) ?: return invalidResult(CutScorecardInvalidInput.TODAY, p)

        // §7.1 step 1: drop and count.
        val counts = Counts()
        val weightByWeek = HashMap<Long, Point>()
        var newestWeight: Point? = null
        for (r in input.weights) {
            val d: Long = admit(r.value, false, false, r.day, today, counts) ?: continue
            val point = Point(d, r.takenAt, r.value, r.day)
            val heldInWeek = weightByWeek[d / 7]
            if (heldInWeek != null) {
                if (heldInWeek.sortsBefore(point)) weightByWeek[d / 7] = point
            } else {
                weightByWeek[d / 7] = point
            }
            val heldNewest = newestWeight
            if (heldNewest != null) {
                if (heldNewest.sortsBefore(point)) newestWeight = point
            } else {
                newestWeight = point
            }
        }
        val waistByWeek = HashMap<Long, Point>()
        for (r in input.waists) {
            val d: Long = admit(r.value, false, false, r.day, today, counts) ?: continue
            val point = Point(d, r.takenAt, r.value, r.day)
            val heldInWeek = waistByWeek[d / 7]
            if (heldInWeek != null) {
                if (heldInWeek.sortsBefore(point)) waistByWeek[d / 7] = point
            } else {
                waistByWeek[d / 7] = point
            }
        }
        // Greatest working weight per exercise per day.
        val liftsByDay = HashMap<Long, HashMap<String, Double>>()
        for (l in input.lifts) {
            val d: Long = admit(l.weightKg, false, l.exercise.isEmpty(), l.day, today, counts) ?: continue
            // A Swift `String` is equal to, and hashes with, every canonically equivalent string, so
            // Swift's dictionary treats "é" and "e" + U+0301 as one exercise. A Kotlin `String` compares
            // UTF-16 code units. The key is normalised to NFC here so both platforms group alike.
            val exercise = Normalizer.normalize(l.exercise, Normalizer.Form.NFC)
            val day = liftsByDay.getOrPut(d) { HashMap() }
            val heldOrNull: Double? = day[exercise]
            if (heldOrNull != null) {
                val held: Double = heldOrNull
                if (l.weightKg > held) day[exercise] = l.weightKg
            } else {
                day[exercise] = l.weightKg
            }
        }
        // §7.1 step 7: the entry later in the input list wins a shared day.
        val proteinByDay = HashMap<Long, Double>()
        for (e in input.proteinDays) {
            val d: Long = admit(e.grams, true, false, e.day, today, counts) ?: continue
            proteinByDay[d] = e.grams
        }
        val rejections = CutScorecardRejections(counts.nonFinite, counts.nonPositive, counts.invalidDay, counts.future)

        // §7.2: phase and domain. `phase.startDay` was validated above, so a null here cannot occur; it
        // is treated as "no active phase".
        val todayWeek = today / 7
        var startedPhase: CutScorecardPhase? = null
        var domainStartWeek = 0L        // week index; 0 lies before every valid week: unclipped
        var notStarted = false
        if (inputPhase != null) {
            val start: Long? = dayNumber(inputPhase.startDay)
            if (start != null) {
                if (today < start) {
                    notStarted = true
                } else {
                    startedPhase = inputPhase
                    domainStartWeek = start / 7
                }
            }
        }
        val activePhase: CutScorecardPhase? = startedPhase
        val domainStart: Long = domainStartWeek
        val isActive = activePhase != null

        // Weekly points inside the domain, ascending.
        val weightWeeks: List<Long> = weightByWeek.keys.filter { it >= domainStart }.sorted()
        val waistWeeks: List<Long> = waistByWeek.keys.filter { it >= domainStart }.sorted()

        // §7.3: weekly loss. A missed week is not bridged, and the baseline week has none.
        val lossByWeek = HashMap<Long, Double>()
        for (w in weightWeeks) {
            if (w - 1 < domainStart) continue
            val previous = weightByWeek[w - 1]
            val current = weightByWeek[w]
            if (previous != null && current != null) {
                lossByWeek[w] = quantize(previous.value - current.value)
            }
        }

        // §7.1 step 5: one entry per week, earliest reading to today, no gaps.
        val weeks = ArrayList<CutScorecardWeek>()
        var firstWeek: Long? = null
        for (w in weightByWeek.keys) {
            val held = firstWeek
            if (held == null || w < held) firstWeek = w
        }
        for (w in waistByWeek.keys) {
            val held = firstWeek
            if (held == null || w < held) firstWeek = w
        }
        val first: Long? = firstWeek
        if (first != null && first <= todayWeek) {
            var w = first
            while (w <= todayWeek) {
                val weight = weightByWeek[w]
                val waist = waistByWeek[w]
                weeks.add(
                    CutScorecardWeek(
                        weekStart = dayKey(w * 7),
                        weightKg = weight?.value, weightDay = weight?.dayKey,
                        waistCm = waist?.value, waistDay = waist?.dayKey,
                        inPhase = isActive && w >= domainStart,
                        weeklyLossKg = lossByWeek[w],
                    )
                )
                w += 1
            }
        }

        // The preconditions of §7.2, in the order the section states them.
        val verdictPrecondition: CutScorecardVerdictReason?
        val judged: Judged?
        val isOverdue: Boolean
        val lastWeightWeek: Long? = weightWeeks.lastOrNull()
        val lastWeightPoint: Point? = if (lastWeightWeek != null) weightByWeek[lastWeightWeek] else null
        if (lastWeightWeek != null && lastWeightPoint != null) {
            judged = Judged(lastWeightWeek, lastWeightPoint)
            isOverdue = todayWeek - lastWeightWeek > p.maxWeighInAgeWeeks
        } else {
            judged = null
            isOverdue = false
        }
        if (inputPhase == null) {
            verdictPrecondition = CutScorecardVerdictReason.NO_ACTIVE_PHASE
        } else if (notStarted || !isActive) {
            verdictPrecondition =
                if (notStarted) CutScorecardVerdictReason.PHASE_NOT_STARTED else CutScorecardVerdictReason.NO_ACTIVE_PHASE
        } else if (judged == null) {
            verdictPrecondition = CutScorecardVerdictReason.NO_READINGS
        } else if (isOverdue) {
            verdictPrecondition = CutScorecardVerdictReason.WEIGH_IN_OVERDUE
        } else {
            verdictPrecondition = null
        }

        val evidenceStartDay: String? = if (judged != null) evidenceStart(judged.week, p) else null
        val judgedWeekStart: String? = if (judged != null) dayKey(judged.week * 7) else null

        // §18 R6: the overdue rule is applied without a phase as well (rate null, and the waist, lift
        // and protein signals unknown, with WEIGH_IN_OVERDUE). The rate-band signal, the rules, the
        // projection and the verdict still report NO_ACTIVE_PHASE, as §7.2 says.
        if (judged == null || isOverdue) {
            val noReadings = judged == null
            val bandReason: CutScorecardRateBandReason =
                if (!isActive) CutScorecardRateBandReason.NO_ACTIVE_PHASE
                else (if (noReadings) CutScorecardRateBandReason.NO_READINGS else CutScorecardRateBandReason.WEIGH_IN_OVERDUE)
            val ruleReason: CutScorecardRuleUnknownReason =
                if (!isActive) CutScorecardRuleUnknownReason.NO_ACTIVE_PHASE
                else (if (noReadings) CutScorecardRuleUnknownReason.NO_READINGS else CutScorecardRuleUnknownReason.WEIGH_IN_OVERDUE)
            val signals = CutScorecardSignals(
                waist = CutScorecardWaistSignal(
                    state = CutScorecardSignalState.UNKNOWN,
                    reason = if (noReadings) CutScorecardWaistReason.NO_READINGS else CutScorecardWaistReason.WEIGH_IN_OVERDUE,
                    currentCm = null, referenceCm = null, referenceWeekStart = null, changeCm = null,
                ),
                lifts = CutScorecardLiftSignal(
                    state = CutScorecardSignalState.UNKNOWN,
                    reason = if (noReadings) CutScorecardLiftReason.NO_READINGS else CutScorecardLiftReason.WEIGH_IN_OVERDUE,
                    commonExercises = 0L, dropped = 0L, climbed = 0L, held = 0L,
                    windowStartDay = null, windowEndDay = null,
                ),
                protein = CutScorecardProteinSignal(
                    state = CutScorecardSignalState.UNKNOWN,
                    reason = if (noReadings) CutScorecardProteinReason.NO_READINGS else CutScorecardProteinReason.WEIGH_IN_OVERDUE,
                    daysLogged = 0L, daysAtOrAboveFloor = 0L,
                    requiredDays = p.proteinMinDaysPerWeek,
                    floorGrams = p.proteinFloorGrams,
                ),
                rateBand = CutScorecardRateBandSignal(
                    state = CutScorecardSignalState.UNKNOWN, reason = bandReason,
                    percentPerWeek = null,
                    lowPercentPerWeek = activePhase?.rateLowPercentPerWeek,
                    highPercentPerWeek = activePhase?.rateHighPercentPerWeek,
                ),
            )
            // §18 R8: with an active phase and no in-phase weigh-in the status is NO_TARGET without a
            // target, otherwise RATE_UNKNOWN.
            val projection: CutScorecardProjection
            if (activePhase != null) {
                if (judged != null) {
                    // §18 R9: `remainingKg` is reported while overdue too.
                    val target: Double? = activePhase.targetWeightKg
                    projection = CutScorecardProjection(
                        status = CutScorecardProjectionStatus.WEIGH_IN_OVERDUE, targetDay = null, weeksRemaining = null,
                        remainingKg = if (target != null) quantize(judged.point.value - target) else null,
                    )
                } else {
                    projection = CutScorecardProjection(
                        status = if (activePhase.targetWeightKg == null) CutScorecardProjectionStatus.NO_TARGET
                        else CutScorecardProjectionStatus.RATE_UNKNOWN,
                        targetDay = null, weeksRemaining = null, remainingKg = null,
                    )
                }
            } else {
                projection = CutScorecardProjection(CutScorecardProjectionStatus.NO_ACTIVE_PHASE, null, null, null)
            }
            return CutScorecardResult(
                weeks = weeks, judgedWeekStart = judgedWeekStart,
                currentWeightKg = newestWeight?.value, currentWeightDay = newestWeight?.dayKey,
                rate = null,
                rateUnavailable = if (noReadings) CutScorecardRateUnavailable.NO_READINGS else CutScorecardRateUnavailable.WEIGH_IN_OVERDUE,
                projection = projection, signals = signals,
                rules = unknownRules(ruleReason, p),
                verdict = insufficient(
                    verdictPrecondition
                        ?: (if (noReadings) CutScorecardVerdictReason.NO_READINGS else CutScorecardVerdictReason.WEIGH_IN_OVERDUE)
                ),
                evidenceStartDay = evidenceStartDay, rejections = rejections, invalidInput = null,
            )
        }

        val j: Long = judged.week
        val span: Long = j - domainStart    // whole weeks from the start of the domain to the judged week

        // §7.4: rate of loss.
        val rateWindowStart: Long = if (p.rateWindowWeeks >= span) domainStart else j - p.rateWindowWeeks
        val fitWeeks = ArrayList<Long>()
        val fitValues = ArrayList<Double>()
        for (w in weightWeeks) {
            if (w < rateWindowStart) continue
            val point = weightByWeek[w]
            if (point != null) { fitWeeks.add(w); fitValues.add(point.value) }
        }
        var fittedRate: CutScorecardRate? = null
        var rateUnavailable: CutScorecardRateUnavailable? = null
        if (fitWeeks.size >= 2) {
            val firstFitWeek: Long = fitWeeks[0]
            val lastFitWeek: Long = fitWeeks[fitWeeks.size - 1]
            val n: Double = fitWeeks.size.toDouble()
            var sumX = 0.0
            var sumY = 0.0
            for (i in fitWeeks.indices) {
                sumX += (fitWeeks[i] - firstFitWeek).toDouble()
                sumY += fitValues[i]
            }
            val meanX: Double = sumX / n
            val meanY: Double = sumY / n
            var sxy = 0.0
            var sxx = 0.0
            for (i in fitWeeks.indices) {
                val dx: Double = (fitWeeks[i] - firstFitWeek).toDouble() - meanX
                sxy += dx * (fitValues[i] - meanY)
                sxx += dx * dx
            }
            // `sxx` is positive: at least two points, in distinct weeks.
            val loss: Double = quantize(-(sxy / sxx))
            fittedRate = CutScorecardRate(
                lossKgPerWeek = loss,
                percentPerWeek = quantize(100.0 * loss / meanY),
                referenceWeightKg = meanY,
                pointsUsed = fitWeeks.size.toLong(),
                spanWeeks = lastFitWeek - firstFitWeek,
                firstWeekStart = dayKey(firstFitWeek * 7),
                lastWeekStart = dayKey(lastFitWeek * 7),
            )
        } else {
            rateUnavailable =
                if (weightWeeks.size <= 1) CutScorecardRateUnavailable.SINGLE_READING
                else CutScorecardRateUnavailable.GAP_LONGER_THAN_WINDOW
        }
        val rate: CutScorecardRate? = fittedRate

        // §7.5: the four signals, for the judged week.
        val anchor: Long = judged.point.day

        val waistSignal: CutScorecardWaistSignal
        val currentWaist: Point? = waistByWeek[j]
        if (currentWaist != null) {
            val waistWindowStart: Long = if (p.waistWindowWeeks >= span) domainStart else j - p.waistWindowWeeks
            var referenceWeek = 0L
            var referencePoint: Point? = null
            for (w in waistWeeks) {
                if (!(w >= waistWindowStart && w < j)) continue
                val point = waistByWeek[w]
                if (point != null) { referenceWeek = w; referencePoint = point }
                break   // ascending: the first week in the window is the earliest
            }
            val reference: Point? = referencePoint
            if (reference != null) {
                val change: Double = quantize(currentWaist.value - reference.value)
                // §18 R14: a minimum of zero is valid and makes an unchanged waist MET.
                val shrinking = change <= -quantize(p.waistMinDecreaseCm)
                waistSignal = CutScorecardWaistSignal(
                    state = if (shrinking) CutScorecardSignalState.MET else CutScorecardSignalState.NOT_MET,
                    reason = if (shrinking) CutScorecardWaistReason.SHRINKING else CutScorecardWaistReason.NOT_SHRINKING,
                    currentCm = currentWaist.value,
                    referenceCm = reference.value,
                    referenceWeekStart = dayKey(referenceWeek * 7),
                    changeCm = change,
                )
            } else {
                waistSignal = CutScorecardWaistSignal(
                    CutScorecardSignalState.UNKNOWN, CutScorecardWaistReason.NO_EARLIER_WAIST,
                    currentCm = currentWaist.value, referenceCm = null, referenceWeekStart = null, changeCm = null,
                )
            }
        } else {
            waistSignal = CutScorecardWaistSignal(
                CutScorecardSignalState.UNKNOWN, CutScorecardWaistReason.NO_WAIST_THIS_WEEK,
                currentCm = null, referenceCm = null, referenceWeekStart = null, changeCm = null,
            )
        }

        val liftSignal = liftSignalForWeek(anchor, liftsByDay, p)

        val proteinSignal: CutScorecardProteinSignal = run {
            var logged = 0L
            var atOrAbove = 0L
            val floor: Double? = p.proteinFloorGrams
            var d = anchor - 7
            while (d <= anchor - 1) {
                val gramsOrNull: Double? = proteinByDay[d]
                d += 1
                if (gramsOrNull == null) continue
                val grams: Double = gramsOrNull
                logged += 1
                if (floor != null) {
                    val configured: Double = floor
                    if (quantize(grams) >= quantize(configured)) atOrAbove += 1
                }
            }
            val state: CutScorecardSignalState
            val reason: CutScorecardProteinReason
            if (floor == null) {
                state = CutScorecardSignalState.UNKNOWN; reason = CutScorecardProteinReason.NO_FLOOR_CONFIGURED
            } else if (logged == 0L) {
                state = CutScorecardSignalState.UNKNOWN; reason = CutScorecardProteinReason.NO_PROTEIN_DATA
            } else if (atOrAbove >= p.proteinMinDaysPerWeek) {
                state = CutScorecardSignalState.MET; reason = CutScorecardProteinReason.FLOOR_MET
            } else if (atOrAbove + (7 - logged) < p.proteinMinDaysPerWeek) {
                state = CutScorecardSignalState.NOT_MET; reason = CutScorecardProteinReason.FLOOR_MISSED
            } else {
                state = CutScorecardSignalState.UNKNOWN; reason = CutScorecardProteinReason.INCOMPLETE_LOGGING
            }
            CutScorecardProteinSignal(
                state = state, reason = reason, daysLogged = logged,
                daysAtOrAboveFloor = atOrAbove,
                requiredDays = p.proteinMinDaysPerWeek,
                floorGrams = floor,
            )
        }

        val rateBandSignal: CutScorecardRateBandSignal
        if (activePhase != null) {
            if (rate != null) {
                // §18 R10: the band bounds are quantized for the comparison.
                val low: Double = quantize(activePhase.rateLowPercentPerWeek)
                val high: Double = quantize(activePhase.rateHighPercentPerWeek)
                val percent: Double = rate.percentPerWeek
                val reason: CutScorecardRateBandReason =
                    if (percent < low) CutScorecardRateBandReason.BELOW_BAND
                    else (if (percent > high) CutScorecardRateBandReason.ABOVE_BAND else CutScorecardRateBandReason.WITHIN_BAND)
                rateBandSignal = CutScorecardRateBandSignal(
                    state = if (reason == CutScorecardRateBandReason.WITHIN_BAND) CutScorecardSignalState.MET
                    else CutScorecardSignalState.NOT_MET,
                    reason = reason,
                    percentPerWeek = rate.percentPerWeek,
                    lowPercentPerWeek = activePhase.rateLowPercentPerWeek,
                    highPercentPerWeek = activePhase.rateHighPercentPerWeek,
                )
            } else {
                rateBandSignal = CutScorecardRateBandSignal(
                    CutScorecardSignalState.UNKNOWN, CutScorecardRateBandReason.RATE_UNKNOWN,
                    percentPerWeek = null,
                    lowPercentPerWeek = activePhase.rateLowPercentPerWeek,
                    highPercentPerWeek = activePhase.rateHighPercentPerWeek,
                )
            }
        } else {
            rateBandSignal = CutScorecardRateBandSignal(
                CutScorecardSignalState.UNKNOWN, CutScorecardRateBandReason.NO_ACTIVE_PHASE,
                percentPerWeek = null, lowPercentPerWeek = null, highPercentPerWeek = null,
            )
        }
        val signals = CutScorecardSignals(waistSignal, liftSignal, proteinSignal, rateBandSignal)

        // No active phase: the series, the rate and three signals stand; nothing is judged.
        if (activePhase == null) {
            return CutScorecardResult(
                weeks = weeks, judgedWeekStart = judgedWeekStart,
                currentWeightKg = newestWeight?.value, currentWeightDay = newestWeight?.dayKey,
                rate = rate, rateUnavailable = rateUnavailable,
                projection = CutScorecardProjection(CutScorecardProjectionStatus.NO_ACTIVE_PHASE, null, null, null),
                signals = signals, rules = unknownRules(CutScorecardRuleUnknownReason.NO_ACTIVE_PHASE, p),
                verdict = insufficient(verdictPrecondition ?: CutScorecardVerdictReason.NO_ACTIVE_PHASE),
                evidenceStartDay = evidenceStartDay, rejections = rejections, invalidInput = null,
            )
        }
        val phase: CutScorecardPhase = activePhase

        // §7.6: rule states.
        val rule1: CutScorecardRuleEvaluation = run {
            val state: CutScorecardRuleState
            var reason: CutScorecardRuleUnknownReason? = null
            if (liftSignal.state == CutScorecardSignalState.MET && waistSignal.state == CutScorecardSignalState.MET) {
                state = CutScorecardRuleState.FIRED
            } else if (liftSignal.state == CutScorecardSignalState.NOT_MET ||
                waistSignal.state == CutScorecardSignalState.NOT_MET) {
                state = CutScorecardRuleState.NOT_FIRED
            } else {
                state = CutScorecardRuleState.UNKNOWN
                reason =
                    if (liftSignal.state == CutScorecardSignalState.UNKNOWN) CutScorecardRuleUnknownReason.LIFT_SIGNAL_UNKNOWN
                    else CutScorecardRuleUnknownReason.WAIST_SIGNAL_UNKNOWN
            }
            CutScorecardRuleEvaluation(
                rule = CutScorecardRule.LIFTS_HOLDING_WAIST_SHRINKING, state = state,
                unknownReason = reason,
                consecutiveWeeks = if (state == CutScorecardRuleState.FIRED) 1L else 0L, requiredWeeks = 1L,
            )
        }

        val rule2: CutScorecardRuleEvaluation = run {
            val required: Long = p.liftDropConsecutiveWeeks
            val startsBeforeDomain = required - 1 > span
            val firstInWindow: Long = if (startsBeforeDomain) domainStart else j - (required - 1)
            var anyHolding = false
            var allDropping = true
            var anyMissed = false
            var runLength = 0L
            var runOpen = true
            // §18 R1: the run is not capped at the window. The scan covers the window, then continues
            // back while the run is unbroken. It never leaves the domain.
            var w = j
            while (w >= domainStart && (w >= firstInWindow || runOpen)) {
                var status = CutScorecardSignalState.UNKNOWN
                val point = weightByWeek[w]
                if (point != null) {
                    status = if (w == j) liftSignal.state else liftSignalForWeek(point.day, liftsByDay, p).state
                } else if (w >= firstInWindow) {
                    anyMissed = true
                }
                if (w >= firstInWindow) {
                    if (status == CutScorecardSignalState.MET) anyHolding = true
                    if (status != CutScorecardSignalState.NOT_MET) allDropping = false
                }
                if (runOpen) { if (status == CutScorecardSignalState.NOT_MET) runLength += 1 else runOpen = false }
                w -= 1
            }
            val state: CutScorecardRuleState
            var reason: CutScorecardRuleUnknownReason? = null
            if (anyHolding) {
                state = CutScorecardRuleState.NOT_FIRED
            } else if (!startsBeforeDomain && allDropping) {
                state = CutScorecardRuleState.FIRED
            } else {
                state = CutScorecardRuleState.UNKNOWN
                reason =
                    if (startsBeforeDomain) CutScorecardRuleUnknownReason.FEWER_WEEKS_THAN_WINDOW
                    else (if (anyMissed) CutScorecardRuleUnknownReason.MISSED_WEIGH_IN
                    else CutScorecardRuleUnknownReason.LIFT_SIGNAL_UNKNOWN)
            }
            CutScorecardRuleEvaluation(
                rule = CutScorecardRule.LIFTS_DROPPING, state = state, unknownReason = reason,
                consecutiveWeeks = runLength, requiredWeeks = required,
            )
        }

        val rule3: CutScorecardRuleEvaluation = run {
            val required: Long = p.slowLossConsecutiveWeeks
            val reachesBeforeDomain = required > span   // week J − N₃ lies before the domain
            val firstInWindow: Long = if (reachesBeforeDomain) domainStart else j - (required - 1)
            val threshold: Double = quantize(p.slowLossThresholdKgPerWeek)
            var anyAtOrAbove = false
            var allKnown = true
            var runLength = 0L
            var runOpen = true
            // §18 R1: as for rule 2, the run continues past the window while it is unbroken, and stops
            // inside the domain (the baseline week has no weekly loss).
            var w = j
            while (w >= domainStart && (w >= firstInWindow || runOpen)) {
                val lossOrNull: Double? = lossByWeek[w]
                if (lossOrNull != null) {
                    val loss: Double = lossOrNull
                    if (loss >= threshold) {
                        if (w >= firstInWindow) anyAtOrAbove = true
                        runOpen = false
                    } else if (runOpen) {
                        runLength += 1
                    }
                } else {
                    if (w >= firstInWindow) allKnown = false
                    runOpen = false
                }
                w -= 1
            }
            val state: CutScorecardRuleState
            var reason: CutScorecardRuleUnknownReason? = null
            if (anyAtOrAbove) {
                state = CutScorecardRuleState.NOT_FIRED
            } else if (!reachesBeforeDomain && allKnown) {
                state = CutScorecardRuleState.FIRED
            } else {
                state = CutScorecardRuleState.UNKNOWN
                reason =
                    if (reachesBeforeDomain) CutScorecardRuleUnknownReason.FEWER_WEEKS_THAN_WINDOW
                    else CutScorecardRuleUnknownReason.MISSED_WEIGH_IN
            }
            CutScorecardRuleEvaluation(
                rule = CutScorecardRule.SLOW_LOSS, state = state, unknownReason = reason,
                consecutiveWeeks = runLength, requiredWeeks = required,
            )
        }

        // §7.7: verdict. Precedence is rule 1, then rule 2, then rule 3; the first matching line wins.
        val slowLossOverridden: List<CutScorecardRule> =
            if (rule3.state == CutScorecardRuleState.FIRED) listOf(CutScorecardRule.SLOW_LOSS) else emptyList()
        val verdict: CutScorecardVerdict
        if (rule1.state == CutScorecardRuleState.FIRED) {
            verdict = CutScorecardVerdict(
                kind = CutScorecardVerdictKind.HOLD_STEADY, reason = CutScorecardVerdictReason.RULE_FIRED,
                rule = CutScorecardRule.LIFTS_HOLDING_WAIST_SHRINKING, calorieChangeKcal = null,
                overriddenRules = slowLossOverridden, unevaluatedRules = emptyList(),
            )
        } else if (rule2.state == CutScorecardRuleState.FIRED) {
            verdict = CutScorecardVerdict(
                kind = CutScorecardVerdictKind.ADD_CALORIES, reason = CutScorecardVerdictReason.RULE_FIRED,
                rule = CutScorecardRule.LIFTS_DROPPING, calorieChangeKcal = p.addCaloriesKcal,
                overriddenRules = slowLossOverridden, unevaluatedRules = emptyList(),
            )
        } else if (rule3.state == CutScorecardRuleState.FIRED) {
            if (rule1.state == CutScorecardRuleState.UNKNOWN) {
                val unevaluated = ArrayList<CutScorecardRule>()
                unevaluated.add(CutScorecardRule.LIFTS_HOLDING_WAIST_SHRINKING)
                if (rule2.state == CutScorecardRuleState.UNKNOWN) unevaluated.add(CutScorecardRule.LIFTS_DROPPING)
                verdict = CutScorecardVerdict(
                    kind = CutScorecardVerdictKind.INSUFFICIENT_DATA,
                    reason = CutScorecardVerdictReason.RECOMPOSITION_CHECK_INCOMPLETE,
                    rule = null, calorieChangeKcal = null, overriddenRules = emptyList(),
                    unevaluatedRules = unevaluated,
                )
            } else {
                verdict = CutScorecardVerdict(
                    kind = CutScorecardVerdictKind.REDUCE_CARBS, reason = CutScorecardVerdictReason.RULE_FIRED,
                    rule = CutScorecardRule.SLOW_LOSS,
                    calorieChangeKcal = -p.reduceCarbsKcal, overriddenRules = emptyList(),
                    unevaluatedRules =
                    if (rule2.state == CutScorecardRuleState.UNKNOWN) listOf(CutScorecardRule.LIFTS_DROPPING)
                    else emptyList(),
                )
            }
        } else {
            val unevaluated: List<CutScorecardRule> =
                listOf(rule1, rule2, rule3).filter { it.state == CutScorecardRuleState.UNKNOWN }.map { it.rule }
            if (unevaluated.size == CutScorecardRule.values().size) {
                verdict = CutScorecardVerdict(
                    kind = CutScorecardVerdictKind.INSUFFICIENT_DATA,
                    reason = CutScorecardVerdictReason.NO_RULE_EVALUABLE, rule = null,
                    calorieChangeKcal = null, overriddenRules = emptyList(),
                    unevaluatedRules = unevaluated,
                )
            } else {
                verdict = CutScorecardVerdict(
                    kind = CutScorecardVerdictKind.HOLD_STEADY,
                    reason = CutScorecardVerdictReason.NO_CHANGE_RULE_FIRED, rule = null,
                    calorieChangeKcal = null, overriddenRules = emptyList(),
                    unevaluatedRules = unevaluated,
                )
            }
        }

        // §7.8: projection. The first matching status wins.
        val projection: CutScorecardProjection
        val targetOrNull: Double? = phase.targetWeightKg
        if (targetOrNull != null) {
            val target: Double = targetOrNull
            val remaining: Double = quantize(judged.point.value - target)
            val status: CutScorecardProjectionStatus
            var targetDay: String? = null
            var weeksRemaining: Double? = null
            if (remaining <= quantize(p.targetToleranceKg)) {
                status = CutScorecardProjectionStatus.TARGET_REACHED
            } else if (rate != null) {
                val lossPerWeek: Double = rate.lossKgPerWeek
                if (lossPerWeek <= 0.0) {
                    status = CutScorecardProjectionStatus.NOT_LOSING
                } else {
                    val weeksLeft: Double = remaining / lossPerWeek
                    // §18 R10: the quotient is quantized for this comparison only; the reported
                    // `weeksRemaining` is the raw one.
                    if (!weeksLeft.isFinite() || quantize(weeksLeft) > p.maxProjectionWeeks.toDouble()) {
                        status = CutScorecardProjectionStatus.BEYOND_HORIZON
                    } else {
                        var daysNeeded: Double = ceil(quantize(weeksLeft * 7.0))
                        if (daysNeeded < 1.0) daysNeeded = 1.0
                        // §18 R11: a projected day past 9999-12-31 is BEYOND_HORIZON.
                        if (daysNeeded > (LAST_DAY_NUMBER - anchor).toDouble()) {
                            status = CutScorecardProjectionStatus.BEYOND_HORIZON
                        } else {
                            val projected: Long = anchor + daysNeeded.toLong()
                            if (projected < today) {
                                status = CutScorecardProjectionStatus.NEEDS_NEW_WEIGH_IN
                            } else {
                                status = CutScorecardProjectionStatus.PROJECTED
                                targetDay = dayKey(projected)
                                weeksRemaining = weeksLeft
                            }
                        }
                    }
                }
            } else {
                status = CutScorecardProjectionStatus.RATE_UNKNOWN
            }
            projection = CutScorecardProjection(status, targetDay, weeksRemaining, remaining)
        } else {
            projection = CutScorecardProjection(CutScorecardProjectionStatus.NO_TARGET, null, null, null)
        }

        return CutScorecardResult(
            weeks = weeks, judgedWeekStart = judgedWeekStart,
            currentWeightKg = newestWeight?.value, currentWeightDay = newestWeight?.dayKey,
            rate = rate, rateUnavailable = rateUnavailable, projection = projection, signals = signals,
            rules = listOf(rule1, rule2, rule3), verdict = verdict, evidenceStartDay = evidenceStartDay,
            rejections = rejections, invalidInput = null,
        )
    }

    /**
     * The Monday of the week containing [day]. Forwards to `WeeklyDigestEngine.mondayOfWeek`.
     *
     * null unless [day] is a canonical "yyyy-MM-dd" key of a real date in years 0001 to 9999.
     *
     * Swift twin: `CutScorecard.weekStart`.
     */
    fun weekStart(day: String): String? {
        if (dayNumber(day) == null) return null
        return WeeklyDigestEngine.mondayOfWeek(day)
    }

    /**
     * Round to three decimals, halves away from zero. Every comparison in `evaluate` uses it.
     *
     * `sign(x) × floor(|x| × 1000 + 0.5) ÷ 1000`, written out because library rounding functions
     * disagree on halves across platforms.
     *
     * Swift twin: `CutScorecard.quantize`.
     */
    fun quantize(x: Double): Double {
        val scaled: Double = abs(x) * 1000.0 + 0.5
        // §18 R4: a magnitude that overflows the expression has no fractional part to round, so it is
        // returned unchanged. NaN is returned as NaN.
        if (!scaled.isFinite()) return x
        val magnitude: Double = floor(scaled) / 1000.0
        // §18 R4: positive zero is returned, never negative zero.
        if (magnitude == 0.0) return 0.0
        return if (x < 0.0) -magnitude else magnitude
    }

    // MARK: Private model

    /** A valid reading with its day as a Julian Day Number. */
    private class Point(val day: Long, val takenAt: Long, val value: Double, val dayKey: String) {
        /**
         * Ascending order by `(day, takenAt, value)`; the reading that sorts last represents its week.
         *
         * Swift twin: `Point.sortsBefore`.
         */
        fun sortsBefore(other: Point): Boolean {
            if (day != other.day) return day < other.day
            if (takenAt != other.takenAt) return takenAt < other.takenAt
            return value < other.value
        }
    }

    /** The judged week and its representative weight reading. */
    private class Judged(val week: Long, val point: Point)

    /** Running rejection counters. */
    private class Counts {
        var nonFinite = 0L
        var nonPositive = 0L
        var invalidDay = 0L
        var future = 0L
    }

    // §18 R3: a finite value above this magnitude is rejected as `nonFinite` (and a parameter or phase
    // bound above it is invalid input), so the sums and products of §7.4 cannot overflow into the
    // output. It is an arithmetic limit, not a plausibility range.
    /** The largest reading magnitude the arithmetic accepts. */
    private const val LARGEST_VALUE_MAGNITUDE = 1e100

    // §18 R5: only the canonical ten-character day key in years 0001 to 9999 is accepted.
    /** 0001-01-01 as a Julian Day Number. It is a Monday, so no week starts before it. */
    private const val FIRST_DAY_NUMBER = 1_721_426L
    /** 9999-12-31 as a Julian Day Number. */
    private const val LAST_DAY_NUMBER = 5_373_484L

    // MARK: Private helpers

    /**
     * The Julian Day Number of a canonical day key, or null. Julian Day Numbers divisible by seven are
     * Mondays, so `number / 7` is a week index and `index * 7` that week's Monday.
     *
     * Swift twin: `CutScorecard.dayNumber`.
     */
    private fun dayNumber(key: String): Long? {
        if (key.toByteArray(Charsets.UTF_8).size != 10) return null
        val ymd = WeeklyDigestEngine.parseYMD(key) ?: return null
        if (ymd[0] < 1 || ymd[0] > 9999) return null
        if (WeeklyDigestEngine.formatYMD(ymd[0], ymd[1], ymd[2]) != key) return null
        return WeeklyDigestEngine.julianDayNumber(ymd[0], ymd[1], ymd[2]).toLong()
    }

    /**
     * The day key of a Julian Day Number, clamped to the representable range.
     *
     * Swift twin: `CutScorecard.dayKey`.
     */
    private fun dayKey(number: Long): String {
        val clamped: Long = minOf(maxOf(number, FIRST_DAY_NUMBER), LAST_DAY_NUMBER)
        val ymd = WeeklyDigestEngine.fromJulianDayNumber(clamped.toInt())
        return WeeklyDigestEngine.formatYMD(ymd[0], ymd[1], ymd[2])
    }

    /**
     * Validate one input item in the order §6.5 lists the causes. Returns its day number when it is
     * kept; otherwise counts the one cause and returns null.
     *
     * Swift twin: `CutScorecard.admit`.
     */
    private fun admit(
        value: Double, zeroIsValid: Boolean, nameIsEmpty: Boolean, day: String, today: Long, counts: Counts,
    ): Long? {
        if (!(value.isFinite() && abs(value) <= LARGEST_VALUE_MAGNITUDE)) { counts.nonFinite += 1; return null }
        if (!(value > 0.0 || (zeroIsValid && value == 0.0))) { counts.nonPositive += 1; return null }
        val number: Long? = if (nameIsEmpty) null else dayNumber(day)
        if (number == null) { counts.invalidDay += 1; return null }
        if (!(number <= today)) { counts.future += 1; return null }
        return number
    }

    /**
     * §6.5: invalid parameters.
     *
     * Swift twin: `CutScorecard.parametersAreValid`.
     */
    private fun parametersAreValid(p: CutScorecardParameters): Boolean {
        if (!(p.waistMinDecreaseCm.isFinite() && p.liftDropTolerancePercent.isFinite() && p.liftDropShare.isFinite() &&
                p.slowLossThresholdKgPerWeek.isFinite() && p.targetToleranceKg.isFinite())) return false
        // §18 R3: a Double parameter above the arithmetic limit is invalid input.
        if (!(abs(p.waistMinDecreaseCm) <= LARGEST_VALUE_MAGNITUDE &&
                abs(p.slowLossThresholdKgPerWeek) <= LARGEST_VALUE_MAGNITUDE &&
                abs(p.targetToleranceKg) <= LARGEST_VALUE_MAGNITUDE)) return false
        val floorOrNull: Double? = p.proteinFloorGrams
        if (floorOrNull != null) {
            val floor: Double = floorOrNull
            if (!(floor.isFinite() && floor > 0.0 && floor <= LARGEST_VALUE_MAGNITUDE)) return false
        }
        if (!(p.rateWindowWeeks >= 1 && p.waistWindowWeeks >= 1 && p.liftDropConsecutiveWeeks >= 1 &&
                p.slowLossConsecutiveWeeks >= 1 && p.maxWeighInAgeWeeks >= 0 && p.maxProjectionWeeks >= 1)) return false
        if (!(p.liftDropTolerancePercent >= 0.0 && p.liftDropTolerancePercent < 100.0 &&
                p.liftDropShare > 0.0 && p.liftDropShare <= 1.0)) return false
        if (!(p.waistMinDecreaseCm >= 0.0 && p.slowLossThresholdKgPerWeek >= 0.0 && p.targetToleranceKg >= 0.0 &&
                p.addCaloriesKcal >= 0 && p.reduceCarbsKcal >= 0)) return false
        return p.proteinMinDaysPerWeek >= 1 && p.proteinMinDaysPerWeek <= 7
    }

    /**
     * §6.5: an invalid phase.
     *
     * Swift twin: `CutScorecard.phaseIsValid`.
     */
    private fun phaseIsValid(phase: CutScorecardPhase): Boolean {
        if (dayNumber(phase.startDay) == null) return false
        val targetOrNull: Double? = phase.targetWeightKg
        if (targetOrNull != null) {
            val target: Double = targetOrNull
            if (!(target.isFinite() && target > 0.0 && target <= LARGEST_VALUE_MAGNITUDE)) return false
        }
        // §18 R3: a target or band bound above the arithmetic limit is invalid input.
        val low: Double = phase.rateLowPercentPerWeek
        val high: Double = phase.rateHighPercentPerWeek
        return low.isFinite() && high.isFinite() && low >= 0.0 && high >= 0.0 && low <= high &&
            high <= LARGEST_VALUE_MAGNITUDE
    }

    /**
     * §7.5 item 2: the lift status of a week whose representative weigh-in fell on [anchor].
     *
     * Swift twin: `CutScorecard.liftSignalForWeek`.
     */
    private fun liftSignalForWeek(
        anchor: Long, liftsByDay: HashMap<Long, HashMap<String, Double>>, p: CutScorecardParameters,
    ): CutScorecardLiftSignal {
        val windowStart = dayKey(anchor - 7)
        val windowEnd = dayKey(anchor - 1)

        /** Swift twin: `CutScorecard.unknown`. */
        fun unknown(reason: CutScorecardLiftReason): CutScorecardLiftSignal =
            CutScorecardLiftSignal(
                CutScorecardSignalState.UNKNOWN, reason, commonExercises = 0L, dropped = 0L,
                climbed = 0L, held = 0L, windowStartDay = windowStart, windowEndDay = windowEnd,
            )

        /** Swift twin: `CutScorecard.heaviest`. */
        fun heaviest(first: Long, last: Long): HashMap<String, Double> {
            val best = HashMap<String, Double>()
            var d = first
            while (d <= last) {
                val day = liftsByDay[d]
                d += 1
                if (day == null) continue
                for ((exercise, kgBoxed) in day) {
                    val kg: Double = kgBoxed
                    val heldOrNull: Double? = best[exercise]
                    if (heldOrNull != null) {
                        val held: Double = heldOrNull
                        if (kg > held) best[exercise] = kg
                    } else {
                        best[exercise] = kg
                    }
                }
            }
            return best
        }

        if (liftsByDay.isEmpty()) return unknown(CutScorecardLiftReason.NO_LIFT_DATA)
        val current = heaviest(anchor - 7, anchor - 1)
        if (current.isEmpty()) return unknown(CutScorecardLiftReason.NO_SESSIONS_THIS_WEEK)
        val previous = heaviest(anchor - 14, anchor - 8)
        if (previous.isEmpty()) return unknown(CutScorecardLiftReason.NO_SESSIONS_PRIOR_WEEK)

        var common = 0L
        var dropped = 0L
        var climbed = 0L
        var held = 0L
        val keep: Double = 1.0 - p.liftDropTolerancePercent / 100.0
        for ((exercise, nowBoxed) in current) {
            val now: Double = nowBoxed
            val beforeOrNull: Double? = previous[exercise]
            if (beforeOrNull == null) continue
            val before: Double = beforeOrNull
            common += 1
            val quantizedNow: Double = quantize(now)
            if (quantizedNow < quantize(before * keep)) {
                dropped += 1
            } else if (quantizedNow > quantize(before)) {
                climbed += 1
            } else {
                held += 1
            }
        }
        if (common == 0L) return unknown(CutScorecardLiftReason.NO_COMMON_EXERCISES)
        // §18 R10: both sides of the share comparison are quantized, so a share of one third meets a
        // configured 0.333.
        val dropping = dropped >= 1 && quantize(dropped.toDouble() / common.toDouble()) >= quantize(p.liftDropShare)
        return CutScorecardLiftSignal(
            state = if (dropping) CutScorecardSignalState.NOT_MET else CutScorecardSignalState.MET,
            reason = if (dropping) CutScorecardLiftReason.DROPPING else CutScorecardLiftReason.HOLDING,
            commonExercises = common, dropped = dropped, climbed = climbed, held = held,
            windowStartDay = windowStart, windowEndDay = windowEnd,
        )
    }

    // §18 R2: an item dated before this day never changes a signal state, a rule state, the verdict,
    // the rate or the projection.
    // §18 R11: with an absurd window parameter the formula of §7.9 lies before 0001-01-01, which has
    // no day key. It is clamped to "0001-01-01"; no valid item can be dated earlier.
    /**
     * §7.9: `J − 7 × (m + 2)` days, `m` the widest window.
     *
     * Swift twin: `CutScorecard.evidenceStart`.
     */
    private fun evidenceStart(judgedWeek: Long, p: CutScorecardParameters): String {
        val widest: Long = maxOf(
            maxOf(p.rateWindowWeeks, p.waistWindowWeeks),
            maxOf(p.slowLossConsecutiveWeeks, p.liftDropConsecutiveWeeks),
        )
        val monday: Long = judgedWeek * 7
        val weeksAvailable: Long = (monday - FIRST_DAY_NUMBER) / 7
        if (!(widest <= weeksAvailable - 2)) return dayKey(FIRST_DAY_NUMBER)
        return dayKey(monday - 7 * (widest + 2))
    }

    /**
     * Three rules that could not be evaluated, all for one reason.
     *
     * Swift twin: `CutScorecard.unknownRules`.
     */
    private fun unknownRules(
        reason: CutScorecardRuleUnknownReason, p: CutScorecardParameters,
    ): List<CutScorecardRuleEvaluation> = listOf(
        CutScorecardRuleEvaluation(
            CutScorecardRule.LIFTS_HOLDING_WAIST_SHRINKING, CutScorecardRuleState.UNKNOWN, reason,
            consecutiveWeeks = 0L, requiredWeeks = 1L,
        ),
        CutScorecardRuleEvaluation(
            CutScorecardRule.LIFTS_DROPPING, CutScorecardRuleState.UNKNOWN, reason,
            consecutiveWeeks = 0L, requiredWeeks = p.liftDropConsecutiveWeeks,
        ),
        CutScorecardRuleEvaluation(
            CutScorecardRule.SLOW_LOSS, CutScorecardRuleState.UNKNOWN, reason,
            consecutiveWeeks = 0L, requiredWeeks = p.slowLossConsecutiveWeeks,
        ),
    )

    /**
     * §7.7 line 0: a precondition failed.
     *
     * Swift twin: `CutScorecard.insufficient`.
     */
    private fun insufficient(reason: CutScorecardVerdictReason): CutScorecardVerdict =
        CutScorecardVerdict(
            CutScorecardVerdictKind.INSUFFICIENT_DATA, reason, rule = null, calorieChangeKcal = null,
            overriddenRules = emptyList(), unevaluatedRules = emptyList(),
        )

    // §18 R13: `requiredWeeks` and `requiredDays` echo the parameters as given; `floorGrams` echoes the
    // floor only when it is finite and positive, so no NaN or infinity reaches the output.
    /**
     * §6.5: the result for invalid parameters, an invalid phase or an unparseable `today`.
     *
     * Swift twin: `CutScorecard.invalidResult`.
     */
    private fun invalidResult(cause: CutScorecardInvalidInput, p: CutScorecardParameters): CutScorecardResult {
        var floor: Double? = null
        val configuredOrNull: Double? = p.proteinFloorGrams
        if (configuredOrNull != null) {
            val configured: Double = configuredOrNull
            if (configured.isFinite() && configured > 0.0) floor = configured
        }
        val signals = CutScorecardSignals(
            waist = CutScorecardWaistSignal(
                CutScorecardSignalState.UNKNOWN, CutScorecardWaistReason.NO_READINGS, currentCm = null,
                referenceCm = null, referenceWeekStart = null, changeCm = null,
            ),
            lifts = CutScorecardLiftSignal(
                CutScorecardSignalState.UNKNOWN, CutScorecardLiftReason.NO_READINGS, commonExercises = 0L,
                dropped = 0L, climbed = 0L, held = 0L, windowStartDay = null, windowEndDay = null,
            ),
            protein = CutScorecardProteinSignal(
                CutScorecardSignalState.UNKNOWN, CutScorecardProteinReason.NO_READINGS, daysLogged = 0L,
                daysAtOrAboveFloor = 0L, requiredDays = p.proteinMinDaysPerWeek, floorGrams = floor,
            ),
            rateBand = CutScorecardRateBandSignal(
                CutScorecardSignalState.UNKNOWN, CutScorecardRateBandReason.NO_READINGS, percentPerWeek = null,
                lowPercentPerWeek = null, highPercentPerWeek = null,
            ),
        )
        return CutScorecardResult(
            weeks = emptyList(), judgedWeekStart = null, currentWeightKg = null, currentWeightDay = null,
            rate = null, rateUnavailable = CutScorecardRateUnavailable.NO_READINGS,
            projection = CutScorecardProjection(CutScorecardProjectionStatus.NO_ACTIVE_PHASE, null, null, null),
            signals = signals, rules = unknownRules(CutScorecardRuleUnknownReason.NO_READINGS, p),
            verdict = insufficient(CutScorecardVerdictReason.INVALID_INPUT),
            evidenceStartDay = null,
            rejections = CutScorecardRejections(0L, 0L, 0L, 0L),
            invalidInput = cause,
        )
    }
}
