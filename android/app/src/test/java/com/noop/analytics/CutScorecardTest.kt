package com.noop.analytics

import com.noop.analytics.CutScorecardOracleCases.FIXTURE_MONDAY
import com.noop.analytics.CutScorecardOracleCases.FIXTURE_PARAMETERS
import com.noop.analytics.CutScorecardOracleCases.fixtureInput
import com.noop.analytics.CutScorecardOracleCases.fixturePhase
import com.noop.analytics.CutScorecardOracleCases.holding
import com.noop.analytics.CutScorecardOracleCases.press
import com.noop.analytics.CutScorecardOracleCases.scenario
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Readable cases for [CutScorecard], mirroring the named cases of
 * `Packages/StrandAnalytics/Tests/StrandAnalyticsTests/CutScorecardTests.swift`: the verdict sequence of
 * the synthetic fixture (docs/personal/superapp/specs/stage-1.md §13.3) and each line of §7.7.
 *
 * Everything here is invented; no value was taken from a real person's log. Byte-for-byte agreement
 * with Swift is [CutScorecardParityOracleTest]'s job, not this file's.
 */
class CutScorecardTest {

    private val r1 = CutScorecardRule.LIFTS_HOLDING_WAIST_SHRINKING
    private val r2 = CutScorecardRule.LIFTS_DROPPING
    private val r3 = CutScorecardRule.SLOW_LOSS

    private val base = FIXTURE_MONDAY
    private val phase = fixturePhase(base)
    private val parameters = FIXTURE_PARAMETERS
    private val noWaists = emptyList<Double?>()
    private val noLifts = emptyList<CutScorecardLiftObservation>()
    private val noProtein = emptyList<CutScorecardProteinDay>()

    private fun verdict(
        kind: CutScorecardVerdictKind, reason: CutScorecardVerdictReason, rule: CutScorecardRule? = null,
        kcal: Long? = null, overridden: List<CutScorecardRule> = emptyList(),
        unevaluated: List<CutScorecardRule> = emptyList(),
    ) = CutScorecardVerdict(kind, reason, rule, kcal, overridden, unevaluated)

    /** "F" fired, "N" not fired, "U" unknown, in the order rule 1, rule 2, rule 3. */
    private fun ruleStates(result: CutScorecardResult): String = result.rules.joinToString("") {
        when (it.state) {
            CutScorecardRuleState.FIRED -> "F"
            CutScorecardRuleState.NOT_FIRED -> "N"
            CutScorecardRuleState.UNKNOWN -> "U"
        }
    }

    @Test
    fun `fixture verdict sequence`() {
        val kinds = (1..22).map { CutScorecard.evaluate(fixtureInput(it)).verdict.kind }
        val hold = CutScorecardVerdictKind.HOLD_STEADY
        val reduce = CutScorecardVerdictKind.REDUCE_CARBS
        val withheld = CutScorecardVerdictKind.INSUFFICIENT_DATA
        val add = CutScorecardVerdictKind.ADD_CALORIES
        assertEquals(
            List(8) { hold } + List(2) { reduce } + List(4) { hold } + List(2) { withheld } +
                List(2) { reduce } + listOf(add, reduce) + List(2) { hold },
            kinds,
        )
    }

    @Test
    fun `fixture rule states week by week`() {
        val expected = listOf(
            "UNU", "FNN", "FNN", "FNN", "FNN", "FNN", "FNF", "FNF", "NNF", "NNF", "UNU",
            "UUN", "UUN", "UUN", "UUF", "UUF", "NUF", "NUF", "NFF", "NNF", "FNN", "FNN",
        )
        assertEquals(expected, (1..22).map { ruleStates(CutScorecard.evaluate(fixtureInput(it))) })
    }

    @Test
    fun `fixture week 3 uses the later of two readings and week 10 has none`() {
        val result = CutScorecard.evaluate(fixtureInput(11))
        assertEquals(98.4, result.weeks[2].weightKg!!, 0.0)
        assertEquals("2031-01-22", result.weeks[2].weightDay)
        assertNull(result.weeks[9].weightKg)
        assertNull(result.weeks[10].weeklyLossKg)
    }

    // §7.7 line 0: a precondition failed.

    @Test
    fun `line 0 - no readings`() {
        val input = CutScorecardInput(emptyList(), emptyList(), noLifts, noProtein, phase, parameters, "2031-01-08")
        val result = CutScorecard.evaluate(input)
        assertEquals(verdict(CutScorecardVerdictKind.INSUFFICIENT_DATA, CutScorecardVerdictReason.NO_READINGS), result.verdict)
        assertEquals(emptyList<CutScorecardWeek>(), result.weeks)
    }

    @Test
    fun `line 0 - no active phase keeps the rate`() {
        val result = CutScorecard.evaluate(fixtureInput(4).copy(phase = null))
        assertEquals(verdict(CutScorecardVerdictKind.INSUFFICIENT_DATA, CutScorecardVerdictReason.NO_ACTIVE_PHASE), result.verdict)
        assertEquals(0.8, result.rate!!.lossKgPerWeek, 0.0)
    }

    @Test
    fun `line 0 - phase not started`() {
        val later = phase.copy(startDay = "2031-06-02")
        val result = CutScorecard.evaluate(fixtureInput(4).copy(phase = later))
        assertEquals(verdict(CutScorecardVerdictKind.INSUFFICIENT_DATA, CutScorecardVerdictReason.PHASE_NOT_STARTED), result.verdict)
    }

    @Test
    fun `line 0 - weigh-in overdue`() {
        val result = CutScorecard.evaluate(scenario(base, listOf(100.0, 99.2), noWaists, noLifts, noProtein, phase, parameters, 14))
        assertEquals(verdict(CutScorecardVerdictKind.INSUFFICIENT_DATA, CutScorecardVerdictReason.WEIGH_IN_OVERDUE), result.verdict)
        assertEquals(CutScorecardRateUnavailable.WEIGH_IN_OVERDUE, result.rateUnavailable)
    }

    @Test
    fun `line 0 - invalid input is reported as parameters, then phase, then today`() {
        val badParameters = parameters.copy(rateWindowWeeks = 0L)
        val badPhase = phase.copy(startDay = "2031-13-01")
        val week1 = fixtureInput(1)
        val all = CutScorecard.evaluate(week1.copy(parameters = badParameters, phase = badPhase, today = "today"))
        assertEquals(CutScorecardInvalidInput.PARAMETERS, all.invalidInput)
        assertEquals(verdict(CutScorecardVerdictKind.INSUFFICIENT_DATA, CutScorecardVerdictReason.INVALID_INPUT), all.verdict)
        assertEquals(CutScorecardInvalidInput.PHASE, CutScorecard.evaluate(week1.copy(phase = badPhase, today = "today")).invalidInput)
        assertEquals(CutScorecardInvalidInput.TODAY, CutScorecard.evaluate(week1.copy(today = "2031-1-8")).invalidInput)
    }

    // §7.7 line 1: rule 1 fired.

    @Test
    fun `line 1 - lifts holding and waist shrinking is hold steady`() {
        val result = CutScorecard.evaluate(fixtureInput(2))
        assertEquals(verdict(CutScorecardVerdictKind.HOLD_STEADY, CutScorecardVerdictReason.RULE_FIRED, rule = r1), result.verdict)
    }

    @Test
    fun `line 1 - recomposition records slow loss as overridden`() {
        val result = CutScorecard.evaluate(fixtureInput(7))
        assertEquals(
            verdict(CutScorecardVerdictKind.HOLD_STEADY, CutScorecardVerdictReason.RULE_FIRED, rule = r1, overridden = listOf(r3)),
            result.verdict,
        )
    }

    // §7.7 line 2: rule 2 fired.

    @Test
    fun `line 2 - lifts dropping for the window is add calories`() {
        val input = scenario(
            base, listOf(100.0, 99.2, 98.4, 97.6), noWaists,
            press(base, -1, listOf(100.0, 100.0, 90.0, 80.0, 70.0, 60.0)), noProtein, phase, parameters, 0,
        )
        assertEquals(
            verdict(CutScorecardVerdictKind.ADD_CALORIES, CutScorecardVerdictReason.RULE_FIRED, rule = r2, kcal = 300L),
            CutScorecard.evaluate(input).verdict,
        )
    }

    @Test
    fun `line 2 - lifts dropping overrides slow loss`() {
        val result = CutScorecard.evaluate(fixtureInput(19))
        assertEquals(
            verdict(
                CutScorecardVerdictKind.ADD_CALORIES, CutScorecardVerdictReason.RULE_FIRED, rule = r2, kcal = 300L,
                overridden = listOf(r3),
            ),
            result.verdict,
        )
    }

    // §7.7 line 3: rule 3 fired.

    @Test
    fun `line 3a - slow loss with rule 1 unknown withholds the verdict`() {
        val result = CutScorecard.evaluate(fixtureInput(15))
        assertEquals(
            verdict(
                CutScorecardVerdictKind.INSUFFICIENT_DATA, CutScorecardVerdictReason.RECOMPOSITION_CHECK_INCOMPLETE,
                unevaluated = listOf(r1, r2),
            ),
            result.verdict,
        )
    }

    @Test
    fun `line 3a - only rule 1 is named when rule 2 is settled`() {
        val input = scenario(base, listOf(100.0, 99.9, 99.8, 99.7), noWaists, holding(base, -1, 4), noProtein, phase, parameters, 0)
        assertEquals(
            verdict(
                CutScorecardVerdictKind.INSUFFICIENT_DATA, CutScorecardVerdictReason.RECOMPOSITION_CHECK_INCOMPLETE,
                unevaluated = listOf(r1),
            ),
            CutScorecard.evaluate(input).verdict,
        )
    }

    @Test
    fun `line 3b - slow loss with a flat waist is reduce carbs`() {
        val result = CutScorecard.evaluate(fixtureInput(9))
        assertEquals(
            verdict(CutScorecardVerdictKind.REDUCE_CARBS, CutScorecardVerdictReason.RULE_FIRED, rule = r3, kcal = -250L),
            result.verdict,
        )
    }

    @Test
    fun `line 3b - reduce carbs names rule 2 when it could not be evaluated`() {
        val result = CutScorecard.evaluate(fixtureInput(17))
        assertEquals(
            verdict(
                CutScorecardVerdictKind.REDUCE_CARBS, CutScorecardVerdictReason.RULE_FIRED, rule = r3, kcal = -250L,
                unevaluated = listOf(r2),
            ),
            result.verdict,
        )
    }

    // §7.7 line 4: no rule fired.

    @Test
    fun `line 4a - one reading without lifts is no rule evaluable`() {
        val result = CutScorecard.evaluate(fixtureInput(1).copy(lifts = emptyList()))
        assertEquals(
            verdict(
                CutScorecardVerdictKind.INSUFFICIENT_DATA, CutScorecardVerdictReason.NO_RULE_EVALUABLE,
                unevaluated = listOf(r1, r2, r3),
            ),
            result.verdict,
        )
    }

    @Test
    fun `line 4b - no rule fired is hold steady naming the unevaluated rules`() {
        val result = CutScorecard.evaluate(fixtureInput(1))
        assertEquals(
            verdict(
                CutScorecardVerdictKind.HOLD_STEADY, CutScorecardVerdictReason.NO_CHANGE_RULE_FIRED,
                unevaluated = listOf(r1, r3),
            ),
            result.verdict,
        )
    }

    // The pure helpers.

    @Test
    fun `quantize rounds halves away from zero and never returns negative zero`() {
        assertEquals(0.001, CutScorecard.quantize(0.0005), 0.0)
        assertEquals(-0.001, CutScorecard.quantize(-0.0005), 0.0)
        assertEquals(2.5, CutScorecard.quantize(2.5), 0.0)
        // `toRawBits` tells positive zero from negative zero, which `==` does not.
        assertEquals(0L, CutScorecard.quantize(-0.0004).toRawBits())
        assertEquals(0L, CutScorecard.quantize(-0.0).toRawBits())
    }

    @Test
    fun `weekStart accepts only the canonical day key`() {
        assertEquals("2031-01-06", CutScorecard.weekStart("2031-01-08"))
        assertEquals("2031-01-06", CutScorecard.weekStart("2031-01-12"))
        assertNull(CutScorecard.weekStart("2031-1-8"))
        assertNull(CutScorecard.weekStart("+2031-01-08"))
        assertNull(CutScorecard.weekStart("2031-02-29"))
        assertNull(CutScorecard.weekStart("0000-12-31"))
    }
}
