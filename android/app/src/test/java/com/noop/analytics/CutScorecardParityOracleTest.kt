package com.noop.analytics

import java.math.BigDecimal
import java.math.RoundingMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pins [CutScorecard] against the Swift source of truth by ORACLE, not by eye
 * (docs/personal/superapp/specs/stage-1.md §12.7).
 *
 * The expected literal is `src/test/resources/cut_scorecard_oracle.txt`: the verbatim standard output of
 * the Swift implementation compiled standalone by `Tools/personal/cut_scorecard_oracle.sh`
 * (`swiftc -O CutScorecard.swift WeeklyDigest.swift ComparisonEngine.swift main.swift`). It is a
 * resource and not a string in this file because it is larger than a class file allows one constant to
 * be. Do not hand-edit it: regenerate it with that script.
 *
 * [CutScorecardOracleCases] is a transliteration of the block between the ORACLE-SHARED markers of
 * `Packages/StrandAnalytics/Tests/StrandAnalyticsTests/CutScorecardOracleTests.swift`: the same
 * fixed-seed generator, the same fixture, the same named edges and the same canonical line. Each line
 * carries a digest of its input, so a line that differs only after `|in=...|` is the engine's and a line
 * whose digest differs is this generator's.
 *
 * The oracle only guards this direction. `CutScorecardOracleTests` on the Swift side reads the same
 * file and is what stops Swift drifting.
 */
class CutScorecardParityOracleTest {

    private fun expectedLines(): List<String> {
        val stream = requireNotNull(javaClass.classLoader!!.getResourceAsStream("cut_scorecard_oracle.txt"))
        val text = stream.use { String(it.readBytes(), Charsets.UTF_8) }
        val lines = text.split("\n")
        return if (lines.isNotEmpty() && lines.last().isEmpty()) lines.dropLast(1) else lines
    }

    @Test
    fun `every line matches the compiled Swift twin`() {
        val expected = expectedLines()
        val actual = CutScorecardOracleCases.allLines()
        val differing = ArrayList<String>()
        for (index in 0 until minOf(expected.size, actual.size)) {
            if (expected[index] != actual[index]) {
                differing.add("line ${index + 1}\n  expected: ${expected[index]}\n  actual:   ${actual[index]}")
            }
        }
        assertTrue(
            "${differing.size} line(s) differ from the Swift oracle; the first:\n" + differing.take(5).joinToString("\n"),
            differing.isEmpty(),
        )
        assertEquals("line count", expected.size, actual.size)
    }

    @Test
    fun `the generated spread is at least five hundred cases with unique labels`() {
        assertTrue(CutScorecardOracleCases.GENERATED_COUNT >= 500)
        val labels = CutScorecardOracleCases.cases().map { it.first }
        assertEquals(labels.size, labels.toSet().size)
    }
}

/**
 * The oracle's inputs and canonical line. A transliteration of the ORACLE-SHARED block of
 * `CutScorecardOracleTests.swift`; change the two together.
 */
internal object CutScorecardOracleCases {

    // MARK: Generator

    /** The Swift `LCG`: the same multiplier and increment, wrapping 64-bit arithmetic. */
    class Lcg(seed: Long) {
        private var state: Long = seed

        /** The next value, in 0 until 2^31. */
        fun next(): Long {
            state = state * 6_364_136_223_846_793_005L + 1_442_695_040_888_963_407L
            return state ushr 33
        }

        /** A value in 0 until n. */
        fun below(n: Int): Int = (next() % n.toLong()).toInt()

        /** True once in [n] draws. */
        fun chance(n: Int): Boolean = below(n) == 0
    }

    const val SEED = 20_311_106L
    const val GENERATED_COUNT = 600

    // MARK: Input digest

    /** FNV-1a over the input: integers and Double bit patterns only. */
    class Digest {
        private var hash: Long = java.lang.Long.parseUnsignedLong("cbf29ce484222325", 16)

        fun byte(value: Long) { hash = (hash xor (value and 0xffL)) * 0x100000001b3L }

        fun int(value: Long) {
            var bits = value
            for (i in 0 until 8) { byte(bits); bits = bits ushr 8 }
        }

        fun double(value: Double) {
            var bits = if (value.isNaN()) 0x7ff8000000000000L else value.toRawBits()
            for (i in 0 until 8) { byte(bits); bits = bits ushr 8 }
        }

        fun optionalDouble(value: Double?) {
            if (value != null) { byte(1L); double(value) } else { byte(0L) }
        }

        fun string(value: String) {
            for (unit in value.toByteArray(Charsets.UTF_8)) byte(unit.toLong() and 0xffL)
            byte(0xffL)
        }

        fun hex(): String = java.lang.Long.toHexString(hash).padStart(16, '0')
    }

    fun digest(input: CutScorecardInput): String {
        val d = Digest()
        d.int(input.weights.size.toLong())
        for (r in input.weights) { d.string(r.day); d.int(r.takenAt); d.double(r.value) }
        d.int(input.waists.size.toLong())
        for (r in input.waists) { d.string(r.day); d.int(r.takenAt); d.double(r.value) }
        d.int(input.lifts.size.toLong())
        for (l in input.lifts) { d.string(l.day); d.string(l.exercise); d.double(l.weightKg) }
        d.int(input.proteinDays.size.toLong())
        for (e in input.proteinDays) { d.string(e.day); d.double(e.grams) }
        val phase = input.phase
        if (phase != null) {
            d.byte(1L)
            d.string(phase.name); d.string(phase.startDay); d.optionalDouble(phase.targetWeightKg)
            d.double(phase.rateLowPercentPerWeek); d.double(phase.rateHighPercentPerWeek)
        } else {
            d.byte(0L)
        }
        val p = input.parameters
        d.int(p.rateWindowWeeks); d.int(p.waistWindowWeeks); d.double(p.waistMinDecreaseCm)
        d.double(p.liftDropTolerancePercent); d.double(p.liftDropShare); d.int(p.liftDropConsecutiveWeeks)
        d.int(p.addCaloriesKcal); d.double(p.slowLossThresholdKgPerWeek); d.int(p.slowLossConsecutiveWeeks)
        d.int(p.reduceCarbsKcal); d.optionalDouble(p.proteinFloorGrams); d.int(p.proteinMinDaysPerWeek)
        d.int(p.maxWeighInAgeWeeks); d.int(p.maxProjectionWeeks); d.double(p.targetToleranceKg)
        d.string(input.today)
        return d.hex()
    }

    // MARK: Day arithmetic (independent of the engine)

    /** Days since 1970-01-01 of a civil date in years 0001 to 9999. Every division is of non-negative integers. */
    fun dayNumber(year: Int, month: Int, day: Int): Int {
        val y = if (month <= 2) year - 1 else year
        val era = y / 400
        val yoe = y - era * 400
        val mp = (month + 9) % 12
        val doy = (153 * mp + 2) / 5 + day - 1
        val doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    fun pad(value: Int, width: Int): String = value.toString().padStart(width, '0')

    /** The "yyyy-MM-dd" key of a day number from [dayNumber]. */
    fun key(number: Int): String {
        val z = number + 719_468
        val era = z / 146_097
        val doe = z - era * 146_097
        val yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        val doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        val mp = (5 * doy + 2) / 153
        val d = doy - (153 * mp + 2) / 5 + 1
        val m = if (mp < 10) mp + 3 else mp - 9
        val y = yoe + era * 400 + (if (m <= 2) 1 else 0)
        return pad(y, 4) + "-" + pad(m, 2) + "-" + pad(d, 2)
    }

    /** Epoch seconds at [hour]:00 UTC of a day number. */
    fun epoch(number: Int, hour: Int): Long = number.toLong() * 86_400L + hour.toLong() * 3_600L

    fun reading(number: Int, value: Double, hour: Int) = CutScorecardReading(key(number), epoch(number, hour), value)

    fun lift(number: Int, exercise: String, kg: Double) = CutScorecardLiftObservation(key(number), exercise, kg)

    fun protein(number: Int, grams: Double) = CutScorecardProteinDay(key(number), grams)

    // MARK: Canonical line

    /**
     * C's "%.6f", which is what Swift's `String(format:)` prints: the exact binary value rounded half to
     * even, and a minus sign kept on a negative that rounds to zero. `String.format` is not used because
     * it rounds the shortest decimal form half up, which differs on ties.
     */
    fun f(value: Double): String {
        if (value.isNaN()) return "nan"
        if (value.isInfinite()) return if (value > 0.0) "inf" else "-inf"
        val text = BigDecimal(value).setScale(6, RoundingMode.HALF_EVEN).toPlainString()
        return if (value.toRawBits() < 0L && !text.startsWith("-")) "-$text" else text
    }

    fun fo(value: Double?): String = if (value == null) "nil" else f(value)
    fun so(value: String?): String = value ?: "nil"
    fun io(value: Long?): String = value?.toString() ?: "nil"

    fun rules(list: List<CutScorecardRule>): String = "[" + list.joinToString("+") { it.raw } + "]"

    /** Every field of the result, in declaration order. Doubles as "%.6f", null as "nil", enums as raw values. */
    fun format(r: CutScorecardResult): String {
        val weeks = ArrayList<String>()
        for (w in r.weeks) {
            weeks.add(
                listOf(
                    w.weekStart, fo(w.weightKg), so(w.weightDay), fo(w.waistCm), so(w.waistDay),
                    if (w.inPhase) "true" else "false", fo(w.weeklyLossKg),
                ).joinToString(",")
            )
        }
        var rate = "nil"
        val x = r.rate
        if (x != null) {
            rate = listOf(
                f(x.lossKgPerWeek), f(x.percentPerWeek), f(x.referenceWeightKg), x.pointsUsed.toString(),
                x.spanWeeks.toString(), x.firstWeekStart, x.lastWeekStart,
            ).joinToString(",")
        }
        val projection = listOf(
            r.projection.status.raw, so(r.projection.targetDay),
            fo(r.projection.weeksRemaining), fo(r.projection.remainingKg),
        ).joinToString(",")
        val waist = r.signals.waist
        val lifts = r.signals.lifts
        val protein = r.signals.protein
        val band = r.signals.rateBand
        val ruleParts = ArrayList<String>()
        for (e in r.rules) {
            ruleParts.add(
                listOf(
                    e.rule.raw, e.state.raw, so(e.unknownReason?.raw),
                    e.consecutiveWeeks.toString(), e.requiredWeeks.toString(),
                ).joinToString(":")
            )
        }
        val v = r.verdict
        val fields = ArrayList<String>()
        fields.add("weeks=" + r.weeks.size.toString() + "[" + weeks.joinToString(";") + "]")
        fields.add("judged=" + so(r.judgedWeekStart))
        fields.add("current=" + fo(r.currentWeightKg) + "," + so(r.currentWeightDay))
        fields.add("rate=$rate")
        fields.add("rateUnavailable=" + so(r.rateUnavailable?.raw))
        fields.add("projection=$projection")
        fields.add(
            "waist=" + listOf(
                waist.state.raw, waist.reason.raw, fo(waist.currentCm),
                fo(waist.referenceCm), so(waist.referenceWeekStart), fo(waist.changeCm),
            ).joinToString(",")
        )
        fields.add(
            "lifts=" + listOf(
                lifts.state.raw, lifts.reason.raw, lifts.commonExercises.toString(),
                lifts.dropped.toString(), lifts.climbed.toString(), lifts.held.toString(),
                so(lifts.windowStartDay), so(lifts.windowEndDay),
            ).joinToString(",")
        )
        fields.add(
            "protein=" + listOf(
                protein.state.raw, protein.reason.raw, protein.daysLogged.toString(),
                protein.daysAtOrAboveFloor.toString(), protein.requiredDays.toString(), fo(protein.floorGrams),
            ).joinToString(",")
        )
        fields.add(
            "rateBand=" + listOf(
                band.state.raw, band.reason.raw, fo(band.percentPerWeek),
                fo(band.lowPercentPerWeek), fo(band.highPercentPerWeek),
            ).joinToString(",")
        )
        fields.add("rules=" + ruleParts.joinToString(";"))
        fields.add(
            "verdict=" + listOf(
                v.kind.raw, v.reason.raw, so(v.rule?.raw),
                io(v.calorieChangeKcal), rules(v.overriddenRules), rules(v.unevaluatedRules),
            ).joinToString(",")
        )
        fields.add("evidence=" + so(r.evidenceStartDay))
        fields.add(
            "rejections=" + listOf(
                r.rejections.nonFinite.toString(), r.rejections.nonPositive.toString(),
                r.rejections.invalidDay.toString(), r.rejections.future.toString(),
            ).joinToString(",")
        )
        fields.add("invalid=" + so(r.invalidInput?.raw))
        return fields.joinToString("|")
    }

    fun line(label: String, input: CutScorecardInput): String =
        label + "|in=" + digest(input) + "|" + format(CutScorecard.evaluate(input))

    fun bitsHex(value: Double): String {
        val bits = if (value.isNaN()) 0x7ff8000000000000L else value.toRawBits()
        return java.lang.Long.toHexString(bits).padStart(16, '0')
    }

    // MARK: Fixture (§13)

    val FIXTURE_MONDAY = dayNumber(2031, 1, 6)
    const val FIXTURE_WEEK_COUNT = 22
    const val PRESS_NAME = "Fixture Press"
    const val ROW_NAME = "Fixture Row"

    val FIXTURE_WEIGHTS: List<Double?> = listOf(
        100.0, 99.2, 98.4, 97.6, 97.5, 97.4, 97.3, 97.2, 97.1, null, 96.0,
        95.2, 95.1, 95.0, 94.9, 94.8, 94.7, 94.6, 94.5, 95.5, 94.0, 93.5,
    )
    val FIXTURE_WAISTS: List<Double?> = listOf(
        100.0, 99.5, 99.0, 98.5, 98.0, 97.5, 97.0, 97.0, 97.0, null, 96.5,
        96.0, 95.5, 95.0, 94.5, 94.5, 94.5, 94.5, 94.5, 94.5, 94.0, 93.5,
    )

    /** One Monday session per entry: fixture week, Fixture Press kg, Fixture Row kg. */
    val FIXTURE_SESSION_WEEKS: List<Int> = listOf(-1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 16, 17, 18, 19, 20, 21, 22)
    val FIXTURE_PRESS_KG: List<Double> = listOf(
        60.0, 60.0, 60.0, 60.0, 60.0, 60.0, 62.5, 62.5, 62.5, 62.5, 62.5,
        62.5, 57.5, 52.5, 47.5, 47.5, 47.5, 50.0,
    )
    val FIXTURE_ROW_KG: List<Double> = listOf(
        50.0, 50.0, 50.0, 50.0, 50.0, 50.0, 50.0, 50.0, 52.5, 52.5, 52.5,
        52.5, 47.5, 42.5, 40.0, 40.0, 40.0, 40.0,
    )

    /** Protein for the seven days before the weigh-in of fixture weeks 2 to 6, oldest first. */
    val FIXTURE_PROTEIN_WEEKS: List<Int> = listOf(2, 3, 4, 5, 6)
    val FIXTURE_PROTEIN: List<List<Double?>> = listOf(
        listOf(120.0, 120.0, 120.0, 80.0, 120.0, 120.0, 120.0),
        listOf(120.0, 120.0, 120.0, 80.0, 120.0, 120.0, 120.0),
        listOf(120.0, 120.0, 120.0, 80.0, 120.0, 120.0, 120.0),
        listOf(120.0, 80.0, 80.0, 120.0, 80.0, 80.0, 120.0),
        listOf(120.0, null, 120.0, null, null, 120.0, null),
    )

    val FIXTURE_PARAMETERS = CutScorecardParameters(
        rateWindowWeeks = 4L, waistWindowWeeks = 2L, waistMinDecreaseCm = 0.5,
        liftDropTolerancePercent = 5.0, liftDropShare = 0.5, liftDropConsecutiveWeeks = 3L,
        addCaloriesKcal = 300L, slowLossThresholdKgPerWeek = 0.4, slowLossConsecutiveWeeks = 3L,
        reduceCarbsKcal = 250L, proteinFloorGrams = 100.0, proteinMinDaysPerWeek = 5L,
        maxWeighInAgeWeeks = 1L, maxProjectionWeeks = 104L, targetToleranceKg = 0.0,
    )

    /** The fixture's data, uncut. */
    class Data(
        var weights: MutableList<CutScorecardReading> = ArrayList(),
        var waists: MutableList<CutScorecardReading> = ArrayList(),
        var lifts: MutableList<CutScorecardLiftObservation> = ArrayList(),
        var proteinDays: MutableList<CutScorecardProteinDay> = ArrayList(),
    ) {
        /** An independent copy, as assigning a Swift struct makes. */
        fun copy(): Data = Data(ArrayList(weights), ArrayList(waists), ArrayList(lifts), ArrayList(proteinDays))
    }

    /** The Monday of fixture week [week] (weeks before week 1 are 0, -1, and so on). */
    fun monday(base: Int, week: Int): Int = base + 7 * (week - 1)

    /** The Wednesday of fixture week [week]: the weigh-in day. */
    fun weighIn(base: Int, week: Int): Int = monday(base, week) + 2

    fun fixtureData(base: Int): Data {
        val data = Data()
        for (i in 0 until FIXTURE_WEEK_COUNT) {
            val kg = FIXTURE_WEIGHTS[i]
            if (kg != null) data.weights.add(reading(weighIn(base, i + 1), kg, 7))
            val cm = FIXTURE_WAISTS[i]
            if (cm != null) data.waists.add(reading(weighIn(base, i + 1), cm, 7))
        }
        // The one extra reading: Monday of week 3. It must lose to Wednesday's 98.4.
        data.weights.add(reading(monday(base, 3), 98.9, 7))
        for (i in FIXTURE_SESSION_WEEKS.indices) {
            val day = monday(base, FIXTURE_SESSION_WEEKS[i])
            data.lifts.add(lift(day, PRESS_NAME, FIXTURE_PRESS_KG[i]))
            data.lifts.add(lift(day, ROW_NAME, FIXTURE_ROW_KG[i]))
        }
        for (i in FIXTURE_PROTEIN_WEEKS.indices) {
            val anchor = weighIn(base, FIXTURE_PROTEIN_WEEKS[i])
            for (k in 0 until 7) {
                val grams = FIXTURE_PROTEIN[i][k]
                if (grams != null) data.proteinDays.add(protein(anchor + k - 7, grams))
            }
        }
        return data
    }

    fun fixturePhase(base: Int) = CutScorecardPhase(
        name = "Fixture cut", startDay = key(base), targetWeightKg = 94.0,
        rateLowPercentPerWeek = 0.40, rateHighPercentPerWeek = 1.20,
    )

    /**
     * [data] as it stood on day number [today]: every list cut to the items dated on or before it.
     * [data] holds canonical ASCII keys only, so string order is calendar order on both platforms.
     */
    fun cut(data: Data, today: Int, phase: CutScorecardPhase?, parameters: CutScorecardParameters): CutScorecardInput {
        val todayKey = key(today)
        return CutScorecardInput(
            weights = data.weights.filter { it.day <= todayKey },
            waists = data.waists.filter { it.day <= todayKey },
            lifts = data.lifts.filter { it.day <= todayKey },
            proteinDays = data.proteinDays.filter { it.day <= todayKey },
            phase = phase, parameters = parameters, today = todayKey,
        )
    }

    /** The fixture on the weigh-in day of [week]. */
    fun fixtureInput(week: Int): CutScorecardInput =
        cut(fixtureData(FIXTURE_MONDAY), weighIn(FIXTURE_MONDAY, week), fixturePhase(FIXTURE_MONDAY), FIXTURE_PARAMETERS)

    /** §13.4, V1 to V12, plus the corrected V8 of §18 R16. */
    fun fixtureVariants(): List<Pair<String, CutScorecardInput>> {
        val base = FIXTURE_MONDAY
        val phase = fixturePhase(base)
        val p = FIXTURE_PARAMETERS
        val data = fixtureData(base)
        val out = ArrayList<Pair<String, CutScorecardInput>>()

        out.add(
            "fixture-V1" to CutScorecardInput(
                weights = emptyList(), waists = emptyList(), lifts = emptyList(), proteinDays = emptyList(),
                phase = phase, parameters = p, today = key(weighIn(base, 1)),
            )
        )

        val v2 = data.copy()
        v2.lifts = ArrayList()
        out.add("fixture-V2" to cut(v2, weighIn(base, 1), phase, p))

        val v3 = data.copy()
        v3.weights = ArrayList(data.weights.filter { it.day != key(weighIn(base, 11)) })
        v3.waists = ArrayList(data.waists.filter { it.day != key(weighIn(base, 11)) })
        out.add("fixture-V3" to cut(v3, weighIn(base, 11), phase, p))

        out.add("fixture-V4" to cut(data, weighIn(base, 4), null, p))

        val v5Phase = CutScorecardPhase("Fixture cut", key(monday(base, 5)), 94.0, 0.40, 1.20)
        out.add("fixture-V5" to cut(data, weighIn(base, 7), v5Phase, p))

        val v6Phase = CutScorecardPhase("Fixture cut", key(base), null, 0.40, 1.20)
        out.add("fixture-V6" to cut(data, weighIn(base, 4), v6Phase, p))

        val v7 = data.copy()
        v7.weights.add(reading(dayNumber(2031, 1, 16), 98.0, 7))
        out.add("fixture-V7" to cut(v7, weighIn(base, 9), phase, p))

        val v8 = data.copy()
        v8.weights = ArrayList()
        for (r in data.weights) {
            v8.weights.add(if (r.day == key(weighIn(base, 6))) reading(weighIn(base, 6), 99.9, 7) else r)
        }
        out.add("fixture-V8" to cut(v8, weighIn(base, 8), phase, p))
        // §18 R16: the outlier as the last point of the fit window.
        out.add("fixture-V8-R16" to cut(v8, weighIn(base, 6), phase, p))

        val v9 = data.copy()
        v9.weights.add(reading(monday(base, 4) + 1, Double.NaN, 7))
        v9.weights.add(reading(monday(base, 4) + 3, -5.0, 7))
        out.add("fixture-V9" to cut(v9, weighIn(base, 4), phase, p))

        val v10 = data.copy()
        v10.weights.add(reading(dayNumber(2029, 6, 6), 101.0, 7))
        out.add("fixture-V10" to cut(v10, weighIn(base, 22), phase, p))

        val v11 = data.copy()
        v11.lifts = ArrayList()
        for (i in FIXTURE_SESSION_WEEKS.indices) {
            val day = monday(base, FIXTURE_SESSION_WEEKS[i])
            v11.lifts.add(lift(day, if (FIXTURE_SESSION_WEEKS[i] >= 17) "fixture press" else PRESS_NAME, FIXTURE_PRESS_KG[i]))
            v11.lifts.add(lift(day, ROW_NAME, FIXTURE_ROW_KG[i]))
        }
        out.add("fixture-V11-w17" to cut(v11, weighIn(base, 17), phase, p))
        out.add("fixture-V11-w18" to cut(v11, weighIn(base, 18), phase, p))

        val v12Phase = CutScorecardPhase("Fixture cut", key(base), 80.0, 0.40, 1.20)
        out.add("fixture-V12" to cut(data, weighIn(base, 8), v12Phase, p))
        return out
    }

    // MARK: Named edges (§12.7 item 3, §18 R1 to R16)

    /** One Wednesday reading per week from week 1 of [base]; null leaves the week empty. */
    fun weekly(base: Int, values: List<Double?>): List<CutScorecardReading> {
        val out = ArrayList<CutScorecardReading>()
        for (i in values.indices) {
            val value = values[i]
            if (value != null) out.add(reading(weighIn(base, i + 1), value, 7))
        }
        return out
    }

    /** Monday sessions at an unchanging 60.0 / 50.0 for fixture weeks [first] through [last]. */
    fun holding(base: Int, first: Int, last: Int): List<CutScorecardLiftObservation> {
        val out = ArrayList<CutScorecardLiftObservation>()
        var week = first
        while (week <= last) {
            out.add(lift(monday(base, week), PRESS_NAME, 60.0))
            out.add(lift(monday(base, week), ROW_NAME, 50.0))
            week += 1
        }
        return out
    }

    /** Monday sessions of Fixture Press alone: `kg[i]` in fixture week `first + i`. */
    fun press(base: Int, first: Int, kg: List<Double>): List<CutScorecardLiftObservation> {
        val out = ArrayList<CutScorecardLiftObservation>()
        for (i in kg.indices) out.add(lift(monday(base, first + i), PRESS_NAME, kg[i]))
        return out
    }

    /** A scenario of weekly Wednesday readings; `today` is the Wednesday of the last week plus [after] days. */
    fun scenario(
        base: Int, weights: List<Double?>, waists: List<Double?>, lifts: List<CutScorecardLiftObservation>,
        proteinDays: List<CutScorecardProteinDay>, phase: CutScorecardPhase?,
        parameters: CutScorecardParameters, after: Int,
    ): CutScorecardInput = CutScorecardInput(
        weights = weekly(base, weights), waists = weekly(base, waists), lifts = lifts,
        proteinDays = proteinDays, phase = phase, parameters = parameters,
        today = key(weighIn(base, if (weights.isNotEmpty()) weights.size else 1) + after),
    )

    fun phase(start: Int, target: Double?, low: Double, high: Double) = CutScorecardPhase(
        name = "Edge cut", startDay = key(start), targetWeightKg = target,
        rateLowPercentPerWeek = low, rateHighPercentPerWeek = high,
    )

    fun edgeCases(): List<Pair<String, CutScorecardInput>> {
        val base = FIXTURE_MONDAY
        val fp = FIXTURE_PARAMETERS
        val ph = fixturePhase(base)
        val wed = weighIn(base, 1)
        val none = emptyList<Double?>()
        val noLifts = emptyList<CutScorecardLiftObservation>()
        val noProtein = emptyList<CutScorecardProteinDay>()
        val noReadings = emptyList<CutScorecardReading>()
        val out = ArrayList<Pair<String, CutScorecardInput>>()
        fun add(label: String, input: CutScorecardInput) { out.add(label to input) }
        fun only(weights: List<CutScorecardReading>, today: Int) = CutScorecardInput(
            weights = weights, waists = noReadings, lifts = noLifts, proteinDays = noProtein, phase = ph,
            parameters = fp, today = key(today),
        )

        // The tie order in "latest reading of the week", in both input orders.
        add("tie-later-day-a", only(listOf(reading(wed - 1, 98.9, 7), reading(wed + 1, 98.4, 7)), wed + 1))
        add("tie-later-day-b", only(listOf(reading(wed + 1, 98.4, 7), reading(wed - 1, 98.9, 7)), wed + 1))
        add("tie-same-day-instant-a", only(listOf(reading(wed, 100.0, 7), reading(wed, 99.0, 9)), wed))
        add("tie-same-day-instant-b", only(listOf(reading(wed, 99.0, 9), reading(wed, 100.0, 7)), wed))
        add("tie-same-instant-value-a", only(listOf(reading(wed, 100.0, 7), reading(wed, 99.5, 7)), wed))
        add("tie-same-instant-value-b", only(listOf(reading(wed, 99.5, 7), reading(wed, 100.0, 7)), wed))
        // `takenAt` beyond 32 bits: truncated to 32 bits the first would sort before the second.
        add(
            "taken-at-beyond-32-bits",
            only(
                listOf(
                    CutScorecardReading(key(wed), 4_294_967_301L, 99.0),
                    CutScorecardReading(key(wed), 10L, 100.0),
                ),
                wed,
            ),
        )
        add(
            "taken-at-extremes",
            only(
                listOf(
                    CutScorecardReading(key(wed), Long.MIN_VALUE, 99.0),
                    CutScorecardReading(key(wed), Long.MAX_VALUE, 100.0),
                    CutScorecardReading(key(wed), -1L, 101.0),
                ),
                wed,
            ),
        )

        // Day keys before 1970: the whole fixture moved to a Monday in 1968, so every `takenAt` is negative.
        val old = dayNumber(1968, 12, 30)
        val oldData = fixtureData(old)
        for (week in listOf(1, 3, 9, 11, 19, 22)) {
            add("pre-1970-w" + pad(week, 2), cut(oldData, weighIn(old, week), fixturePhase(old), fp))
        }

        // Exercise names that differ only by case or by a trailing space are different exercises.
        val names = listOf(lift(wed - 9, "Squat", 100.0), lift(wed - 2, "squat", 100.0), lift(wed - 2, "Squat ", 100.0))
        add(
            "names-case-and-space",
            CutScorecardInput(listOf(reading(wed, 100.0, 7)), noReadings, names, noProtein, ph, fp, key(wed)),
        )
        // Canonically equivalent names: precomposed against decomposed. One exercise to a Swift `String`.
        val accents = listOf(
            lift(wed - 9, "Caf\u00E9 Press", 100.0), lift(wed - 2, "Cafe\u0301 Press", 90.0),
            lift(wed - 3, "Caf\u00E9 Press", 80.0),
        )
        add(
            "names-canonical-equivalence",
            CutScorecardInput(listOf(reading(wed, 100.0, 7)), noReadings, accents, noProtein, ph, fp, key(wed)),
        )
        add(
            "names-empty",
            CutScorecardInput(
                listOf(reading(wed, 100.0, 7)), noReadings,
                listOf(lift(wed - 2, "", 100.0), lift(wed - 9, "", Double.NaN)),
                noProtein, ph, fp, key(wed),
            ),
        )

        // The ends of the calendar (§18 R5, R11).
        val first = dayNumber(1, 1, 1)
        val wide = fp.copy(
            rateWindowWeeks = Long.MAX_VALUE, waistWindowWeeks = Long.MAX_VALUE,
            liftDropConsecutiveWeeks = Long.MAX_VALUE, slowLossConsecutiveWeeks = Long.MAX_VALUE,
        )
        add(
            "year-0001",
            CutScorecardInput(
                weights = listOf(reading(first + 2, 100.0, 7), reading(first + 9, 99.5, 7)),
                waists = listOf(reading(first + 2, 100.0, 7), reading(first + 9, 99.0, 7)),
                lifts = listOf(lift(first, PRESS_NAME, 60.0), lift(first + 7, PRESS_NAME, 60.0)),
                proteinDays = listOf(protein(first, 120.0), protein(first + 8, 120.0)),
                phase = phase(first, 94.0, 0.4, 1.2), parameters = fp, today = key(first + 9),
            ),
        )
        add(
            "year-0001-widest-windows",
            CutScorecardInput(
                weights = listOf(reading(first + 2, 100.0, 7), reading(first + 9, 99.5, 7)), waists = noReadings,
                lifts = noLifts, proteinDays = noProtein, phase = phase(first, 94.0, 0.4, 1.2), parameters = wide,
                today = key(first + 9),
            ),
        )
        val last = dayNumber(9999, 12, 31)
        val far = fp.copy(maxProjectionWeeks = Long.MAX_VALUE, maxWeighInAgeWeeks = Long.MAX_VALUE)
        add(
            "year-9999-projection-past-the-calendar",
            CutScorecardInput(
                weights = listOf(reading(last - 11, 100.0, 7), reading(last - 4, 99.5, 7)), waists = noReadings,
                lifts = noLifts, proteinDays = noProtein, phase = phase(last - 20, 94.0, 0.4, 1.2), parameters = far,
                today = key(last),
            ),
        )
        add(
            "year-9999-projection-on-the-last-day",
            CutScorecardInput(
                weights = listOf(reading(last - 11, 100.0, 7), reading(last - 4, 99.5, 7)), waists = noReadings,
                lifts = noLifts, proteinDays = noProtein, phase = phase(last - 20, 99.3, 0.4, 1.2), parameters = far,
                today = key(last),
            ),
        )
        add(
            "day-keys-outside-the-calendar",
            CutScorecardInput(
                weights = listOf(
                    CutScorecardReading("0000-12-31", 0L, 100.0),
                    CutScorecardReading("10000-01-01", 0L, 100.0),
                    CutScorecardReading("2031-1-8", 0L, 100.0),
                    CutScorecardReading("+2031-01-08", 0L, 100.0),
                    CutScorecardReading("2031-02-29", 0L, 100.0),
                    CutScorecardReading("2031-01-08 ", 0L, 100.0),
                    CutScorecardReading("", 0L, 100.0),
                    CutScorecardReading("\u0662\u0660\u0663\u0661-01-08", 0L, 100.0),
                    CutScorecardReading("2032-02-29", 0L, 100.0),
                ),
                waists = noReadings, lifts = noLifts, proteinDays = noProtein, phase = null, parameters = fp,
                today = "2032-03-01",
            ),
        )

        // A `ceil` on a value that is an integer but for floating-point error: 0.3 / 0.1 × 7.
        add(
            "ceil-near-integer",
            scenario(base, listOf(80.3, 80.2), none, noLifts, noProtein, phase(base, 79.9, 0.0, 5.0), fp, 0),
        )
        // 0.1 / 0.35 × 7 is 2.0000000000000004: two days once quantized, three if the raw product were rounded up.
        add(
            "ceil-just-above-integer",
            scenario(base, listOf(80.35, 80.0), none, noLifts, noProtein, phase(base, 79.9, 0.0, 5.0), fp, 0),
        )

        // §18 R3: the arithmetic limit.
        val over = Double.fromBits(1e100.toRawBits() + 1L)
        add("limit-accepted", only(listOf(reading(wed, 1e100, 7), reading(wed + 7, 1e100, 7)), wed + 7))
        add(
            "limit-rejected",
            only(
                listOf(
                    reading(wed, over, 7), reading(wed + 1, -over, 7), reading(wed + 2, -1e100, 7),
                    reading(wed + 3, 100.0, 7),
                ),
                wed + 3,
            ),
        )
        add(
            "limit-target",
            scenario(base, listOf(100.0, 99.0), none, noLifts, noProtein, phase(base, 1e100, 0.0, 1e100), fp, 0),
        )
        add(
            "limit-phase-bound-over",
            scenario(base, listOf(100.0, 99.0), none, noLifts, noProtein, phase(base, 94.0, 0.0, over), fp, 0),
        )
        add(
            "limit-phase-target-over",
            scenario(base, listOf(100.0, 99.0), none, noLifts, noProtein, phase(base, over, 0.0, 1.0), fp, 0),
        )

        // §18 R4: a weekly loss that rounds to zero from below is positive zero.
        add(
            "negative-zero-loss",
            scenario(
                base, listOf(80.0001, 80.0002, 80.0003), listOf(100.0, 100.0001, 100.0002),
                noLifts, noProtein, phase(base, 79.0, 0.0, 5.0), fp, 0,
            ),
        )

        // §18 R12: the order in which invalid input is reported, and one count per item.
        val bad = fp.copy(rateWindowWeeks = 0L)
        val badPhase = CutScorecardPhase("Edge cut", "2031-13-01", 94.0, 0.4, 1.2)
        add(
            "invalid-parameters-phase-today",
            CutScorecardInput(weekly(base, listOf(100.0)), noReadings, noLifts, noProtein, badPhase, bad, "today"),
        )
        add(
            "invalid-phase-today",
            CutScorecardInput(weekly(base, listOf(100.0)), noReadings, noLifts, noProtein, badPhase, fp, "today"),
        )
        for (today in listOf("today", "", "2031-1-8", "+2031-01-08", "2031-02-29", "2031-01-08T00:00", "20310108", "0000-01-01")) {
            add(
                "invalid-today-$today",
                CutScorecardInput(weekly(base, listOf(100.0)), noReadings, noLifts, noProtein, ph, fp, today),
            )
        }
        add(
            "one-count-per-item",
            CutScorecardInput(
                weights = listOf(
                    CutScorecardReading("nonsense", 0L, Double.NaN),
                    CutScorecardReading("nonsense", 0L, -1.0),
                    CutScorecardReading("nonsense", 0L, 100.0),
                    CutScorecardReading(key(wed + 30), 0L, Double.NEGATIVE_INFINITY),
                    CutScorecardReading(key(wed + 30), 0L, 0.0),
                    CutScorecardReading(key(wed + 30), 0L, 100.0),
                    reading(wed, 100.0, 7),
                ),
                waists = listOf(
                    CutScorecardReading(key(wed + 1), 0L, 100.0),
                    CutScorecardReading(key(wed), 0L, Double.POSITIVE_INFINITY),
                ),
                lifts = listOf(
                    lift(wed + 1, PRESS_NAME, 60.0), lift(wed - 2, PRESS_NAME, 0.0), lift(wed - 2, "", -1.0),
                    lift(wed - 2, "", 60.0),
                ),
                proteinDays = listOf(
                    protein(wed - 1, -0.0), protein(wed - 2, 0.0), protein(wed - 3, -1.0),
                    protein(wed + 1, 100.0), protein(wed - 4, Double.NaN),
                    CutScorecardProteinDay("2031-01-32", 100.0),
                ),
                phase = ph, parameters = fp, today = key(wed),
            ),
        )

        // §6.5 and §18 R13: every invalid parameter, one at a time.
        for (kind in 0 until 30) {
            val p = when (kind) {
                0 -> fp.copy(rateWindowWeeks = 0L)
                1 -> fp.copy(waistWindowWeeks = 0L)
                2 -> fp.copy(liftDropConsecutiveWeeks = 0L)
                3 -> fp.copy(slowLossConsecutiveWeeks = -3L)
                4 -> fp.copy(maxWeighInAgeWeeks = -1L)
                5 -> fp.copy(maxProjectionWeeks = 0L)
                6 -> fp.copy(liftDropTolerancePercent = 100.0)
                7 -> fp.copy(liftDropTolerancePercent = -0.5)
                8 -> fp.copy(liftDropShare = 0.0)
                9 -> fp.copy(liftDropShare = 1.001)
                10 -> fp.copy(waistMinDecreaseCm = -0.1)
                11 -> fp.copy(slowLossThresholdKgPerWeek = -0.25)
                12 -> fp.copy(targetToleranceKg = -1.0)
                13 -> fp.copy(addCaloriesKcal = -1L)
                14 -> fp.copy(reduceCarbsKcal = Long.MIN_VALUE)
                15 -> fp.copy(proteinMinDaysPerWeek = 0L)
                16 -> fp.copy(proteinMinDaysPerWeek = 8L)
                17 -> fp.copy(proteinFloorGrams = 0.0)
                18 -> fp.copy(proteinFloorGrams = -5.0)
                19 -> fp.copy(proteinFloorGrams = Double.NaN)
                20 -> fp.copy(proteinFloorGrams = Double.POSITIVE_INFINITY)
                21 -> fp.copy(proteinFloorGrams = over)
                22 -> fp.copy(waistMinDecreaseCm = Double.NaN)
                23 -> fp.copy(liftDropTolerancePercent = Double.POSITIVE_INFINITY)
                24 -> fp.copy(liftDropShare = Double.NaN)
                25 -> fp.copy(slowLossThresholdKgPerWeek = over)
                26 -> fp.copy(targetToleranceKg = Double.POSITIVE_INFINITY)
                27 -> fp.copy(waistMinDecreaseCm = over)
                28 -> fp.copy(
                    rateWindowWeeks = Long.MIN_VALUE, liftDropConsecutiveWeeks = Long.MAX_VALUE,
                    proteinMinDaysPerWeek = Long.MAX_VALUE,
                )
                else -> fp.copy(targetToleranceKg = over)
            }
            add(
                "invalid-parameter-" + pad(kind, 2),
                scenario(base, listOf(100.0, 99.2), listOf(100.0, 99.0), holding(base, -1, 2), noProtein, ph, p, 0),
            )
        }
        // Valid at the edge of validity.
        for (kind in 0 until 6) {
            val p = when (kind) {
                0 -> fp.copy(liftDropTolerancePercent = 0.0)
                1 -> fp.copy(liftDropShare = 1.0)
                2 -> fp.copy(maxWeighInAgeWeeks = 0L)
                3 -> fp.copy(proteinFloorGrams = 1e100, targetToleranceKg = 1e100)
                4 -> fp.copy(addCaloriesKcal = Long.MAX_VALUE, reduceCarbsKcal = Long.MAX_VALUE, liftDropConsecutiveWeeks = 1L)
                else -> fp.copy(proteinMinDaysPerWeek = 1L, waistMinDecreaseCm = 1e100, slowLossThresholdKgPerWeek = 1e100)
            }
            add(
                "valid-parameter-edge-$kind",
                scenario(
                    base, listOf(100.0, 99.2, 99.1, 99.0, 98.9), listOf(100.0, 99.0, 98.0, 97.0, 96.0),
                    press(base, -1, listOf(60.0, 60.0, 60.0, 55.0, 50.0, 45.0, 40.0)),
                    listOf(protein(weighIn(base, 5) - 1, 120.0)), ph, p, 0,
                ),
            )
        }

        // §6.5: every way a phase is invalid.
        for (kind in 0 until 10) {
            var start = key(base)
            var target: Double? = 94.0
            var low = 0.4
            var high = 1.2
            when (kind) {
                0 -> start = "2031-02-30"
                1 -> start = ""
                2 -> target = Double.NaN
                3 -> target = 0.0
                4 -> target = -94.0
                5 -> target = Double.POSITIVE_INFINITY
                6 -> low = Double.NaN
                7 -> low = -0.1
                8 -> low = 1.3
                else -> high = Double.POSITIVE_INFINITY
            }
            add(
                "invalid-phase-$kind",
                CutScorecardInput(
                    weights = weekly(base, listOf(100.0, 99.2)), waists = noReadings, lifts = noLifts,
                    proteinDays = noProtein,
                    phase = CutScorecardPhase("Edge cut", start, target, low, high),
                    parameters = fp, today = key(weighIn(base, 2)),
                ),
            )
        }
        add(
            "phase-band-equal-bounds",
            scenario(base, listOf(100.0, 99.2), none, noLifts, noProtein, phase(base, 94.0, 0.803, 0.803), fp, 0),
        )
        add(
            "phase-band-zero",
            scenario(base, listOf(100.0, 99.2), none, noLifts, noProtein, phase(base, 94.0, 0.0, 0.0), fp, 0),
        )

        // §18 R14: a waist minimum of zero makes an unchanged waist `met`.
        val flat = fp.copy(waistMinDecreaseCm = 0.0)
        add(
            "waist-minimum-zero-flat",
            scenario(base, listOf(100.0, 99.2), listOf(100.0, 100.0), holding(base, -1, 2), noProtein, ph, flat, 0),
        )
        add(
            "waist-minimum-zero-growing",
            scenario(base, listOf(100.0, 99.2), listOf(100.0, 100.001), holding(base, -1, 2), noProtein, ph, flat, 0),
        )
        add(
            "waist-minimum-exact",
            scenario(base, listOf(100.0, 99.2), listOf(100.0, 99.5), holding(base, -1, 2), noProtein, ph, fp, 0),
        )
        add(
            "waist-minimum-one-thousandth-short",
            scenario(base, listOf(100.0, 99.2), listOf(100.0, 99.501), holding(base, -1, 2), noProtein, ph, fp, 0),
        )
        add(
            "waist-none-this-week",
            scenario(base, listOf(100.0, 99.2), listOf(100.0, null), holding(base, -1, 2), noProtein, ph, fp, 0),
        )
        add(
            "waist-outside-window",
            scenario(
                base, listOf(100.0, 99.2, 98.4, 97.6, 96.8), listOf(100.0, null, null, null, 98.0),
                holding(base, -1, 5), noProtein, ph, fp, 0,
            ),
        )

        // §18 R10: the lift share, the lift tolerance, the band and the horizon compare quantized values.
        val threeLifts = listOf(
            lift(wed - 9, "A", 100.0), lift(wed - 9, "B", 100.0), lift(wed - 9, "C", 100.0),
            lift(wed - 2, "A", 90.0), lift(wed - 2, "B", 100.0), lift(wed - 2, "C", 105.0),
        )
        add(
            "lift-share-one-third-meets-0.333",
            CutScorecardInput(
                listOf(reading(wed, 100.0, 7)), noReadings, threeLifts, noProtein, ph,
                fp.copy(liftDropShare = 0.333), key(wed),
            ),
        )
        // One third against 0.3334: met only because both sides are quantized to 0.333.
        add(
            "lift-share-one-third-meets-0.3334",
            CutScorecardInput(
                listOf(reading(wed, 100.0, 7)), noReadings, threeLifts, noProtein, ph,
                fp.copy(liftDropShare = 0.3334), key(wed),
            ),
        )
        add(
            "lift-share-one-third-misses-0.334",
            CutScorecardInput(
                listOf(reading(wed, 100.0, 7)), noReadings, threeLifts, noProtein, ph,
                fp.copy(liftDropShare = 0.334), key(wed),
            ),
        )
        add(
            "lift-tolerance-exact",
            CutScorecardInput(
                listOf(reading(wed, 100.0, 7)), noReadings,
                listOf(lift(wed - 9, "A", 100.0), lift(wed - 2, "A", 95.0)), noProtein, ph, fp, key(wed),
            ),
        )
        add(
            "lift-tolerance-one-thousandth-under",
            CutScorecardInput(
                listOf(reading(wed, 100.0, 7)), noReadings,
                listOf(lift(wed - 9, "A", 100.0), lift(wed - 2, "A", 94.999)), noProtein, ph, fp, key(wed),
            ),
        )
        add(
            "lift-window-edges",
            CutScorecardInput(
                listOf(reading(wed, 100.0, 7)), noReadings,
                listOf(
                    lift(wed - 14, "A", 100.0), lift(wed - 15, "A", 500.0), lift(wed - 8, "A", 101.0),
                    lift(wed - 7, "A", 101.0), lift(wed - 1, "A", 90.0), lift(wed, "A", 500.0),
                    lift(wed - 7, "A", 99.0),
                ),
                noProtein, ph, fp, key(wed),
            ),
        )
        add(
            "lift-no-sessions-prior-week",
            CutScorecardInput(
                listOf(reading(wed, 100.0, 7)), noReadings, listOf(lift(wed - 2, "A", 100.0)), noProtein,
                ph, fp, key(wed),
            ),
        )
        add(
            "lift-no-sessions-this-week",
            CutScorecardInput(
                listOf(reading(wed, 100.0, 7)), noReadings, listOf(lift(wed - 9, "A", 100.0)), noProtein,
                ph, fp, key(wed),
            ),
        )
        add(
            "band-low-quantized-equal",
            scenario(base, listOf(100.0, 99.2), none, noLifts, noProtein, phase(base, 94.0, 0.8034, 1.2), fp, 0),
        )
        add(
            "band-high-quantized-equal",
            scenario(base, listOf(100.0, 99.2), none, noLifts, noProtein, phase(base, 94.0, 0.1, 0.8025), fp, 0),
        )
        add(
            "band-above",
            scenario(base, listOf(100.0, 99.2), none, noLifts, noProtein, phase(base, 94.0, 0.1, 0.802), fp, 0),
        )
        val horizon = fp.copy(maxProjectionWeeks = 4L)
        add(
            "horizon-exact",
            scenario(base, listOf(100.0, 99.5), none, noLifts, noProtein, phase(base, 97.5, 0.0, 5.0), horizon, 0),
        )
        add(
            "horizon-one-thousandth-over",
            scenario(base, listOf(100.0, 99.5), none, noLifts, noProtein, phase(base, 97.4995, 0.0, 5.0), horizon, 0),
        )
        // 10.001 / 2.5 is 4.0004: inside a four-week horizon only because the quotient is quantized.
        add(
            "horizon-quantized-equal",
            scenario(base, listOf(102.501, 100.001), none, noLifts, noProtein, phase(base, 90.0, 0.0, 5.0), horizon, 0),
        )
        val tolerance = fp.copy(targetToleranceKg = 0.5)
        add(
            "target-tolerance-exact",
            scenario(base, listOf(100.0, 99.5), none, noLifts, noProtein, phase(base, 99.0, 0.0, 5.0), tolerance, 0),
        )
        add(
            "target-tolerance-one-thousandth-over",
            scenario(base, listOf(100.0, 99.5), none, noLifts, noProtein, phase(base, 98.999, 0.0, 5.0), tolerance, 0),
        )

        // §18 R1: a run longer than its window is counted in full.
        val slow: List<Double?> = listOf(100.0, 99.9, 99.8, 99.7, 99.6, 99.5, 99.4, 99.3, 99.2)
        add("long-slow-run", scenario(base, slow, none, holding(base, -1, 9), noProtein, ph, fp, 0))
        add(
            "long-drop-run",
            scenario(
                base, slow, none,
                press(base, -1, listOf(100.0, 100.0, 90.0, 80.0, 70.0, 60.0, 50.0, 40.0, 30.0, 20.0, 10.0)),
                noProtein, ph, fp, 0,
            ),
        )
        add(
            "slow-loss-at-threshold",
            scenario(base, listOf(100.0, 99.6, 99.2, 98.8), none, holding(base, -1, 4), noProtein, ph, fp, 0),
        )
        add(
            "slow-loss-one-thousandth-under",
            scenario(base, listOf(100.0, 99.601, 99.202, 98.803), none, holding(base, -1, 4), noProtein, ph, fp, 0),
        )

        // §7.7, the lines the fixture does not reach.
        add(
            "verdict-rule-2-alone",
            scenario(
                base, listOf(100.0, 99.2, 98.4, 97.6), none,
                press(base, -1, listOf(100.0, 100.0, 90.0, 80.0, 70.0, 60.0)), noProtein, ph, fp, 0,
            ),
        )
        add(
            "verdict-withheld-naming-rule-1-only",
            scenario(base, listOf(100.0, 99.9, 99.8, 99.7), none, holding(base, -1, 4), noProtein, ph, fp, 0),
        )
        add(
            "verdict-reduce-with-flat-waist",
            scenario(
                base, listOf(100.0, 99.9, 99.8, 99.7), listOf(100.0, 100.0, 100.0, 100.0), noLifts,
                noProtein, ph, fp, 0,
            ),
        )
        add(
            "verdict-rule-2-missed-weigh-in",
            scenario(
                base, listOf(100.0, null, 98.4, 97.6), none,
                press(base, -1, listOf(100.0, 100.0, 90.0, 80.0, 70.0, 60.0)), noProtein, ph, fp, 0,
            ),
        )

        // §7.2 and §18 R6 to R9: the preconditions.
        add(
            "no-phase-overdue",
            scenario(base, listOf(100.0, 99.2), listOf(100.0, 99.0), holding(base, -1, 2), noProtein, null, fp, 14),
        )
        add(
            "no-phase-no-readings",
            CutScorecardInput(noReadings, listOf(reading(wed, 100.0, 7)), noLifts, noProtein, null, fp, key(wed)),
        )
        add(
            "phase-not-started",
            scenario(
                base, listOf(100.0, 99.2, 98.4), listOf(100.0, 99.0, 98.0), holding(base, -1, 3), noProtein,
                phase(weighIn(base, 3) + 1, 94.0, 0.4, 1.2), fp, 0,
            ),
        )
        add(
            "phase-not-started-overdue",
            scenario(
                base, listOf(100.0, 99.2, 98.4), none, noLifts, noProtein,
                phase(weighIn(base, 3) + 40, 94.0, 0.4, 1.2), fp, 21,
            ),
        )
        add(
            "phase-starts-today",
            scenario(
                base, listOf(100.0, 99.2, 98.4), none, noLifts, noProtein,
                phase(weighIn(base, 3), 94.0, 0.4, 1.2), fp, 0,
            ),
        )
        add(
            "phase-without-in-phase-weigh-in",
            scenario(
                base, listOf(100.0, 99.2), listOf(100.0, 99.0), noLifts, noProtein,
                phase(monday(base, 3), 94.0, 0.4, 1.2), fp, 6,
            ),
        )
        add(
            "phase-without-in-phase-weigh-in-or-target",
            scenario(
                base, listOf(100.0, 99.2), none, noLifts, noProtein,
                phase(monday(base, 3), null, 0.4, 1.2), fp, 6,
            ),
        )
        add("overdue-with-target", scenario(base, listOf(100.0, 99.2), none, noLifts, noProtein, ph, fp, 14))
        add(
            "overdue-without-target",
            scenario(base, listOf(100.0, 99.2), none, noLifts, noProtein, phase(base, null, 0.4, 1.2), fp, 14),
        )
        val strict = fp.copy(maxWeighInAgeWeeks = 0L)
        add("age-zero-same-week", scenario(base, listOf(100.0, 99.2), none, noLifts, noProtein, ph, strict, 4))
        add("age-zero-next-week", scenario(base, listOf(100.0, 99.2), none, noLifts, noProtein, ph, strict, 5))
        val patient = fp.copy(maxWeighInAgeWeeks = 60L)
        add(
            "needs-new-weigh-in",
            scenario(base, listOf(100.0, 99.0), none, noLifts, noProtein, phase(base, 98.0, 0.0, 5.0), patient, 40),
        )
        add(
            "projected-on-today",
            scenario(base, listOf(100.0, 99.0), none, noLifts, noProtein, phase(base, 98.0, 0.0, 5.0), patient, 7),
        )
        add(
            "phase-starts-mid-week",
            scenario(
                base, listOf(100.0, 99.2, 98.4), listOf(100.0, 99.0, 98.0), holding(base, -1, 3), noProtein,
                phase(weighIn(base, 2) + 2, 94.0, 0.4, 1.2), fp, 0,
            ),
        )

        // §7.4: the rate window.
        add(
            "rate-gap-inside-window",
            scenario(base, listOf(100.0, null, 99.0, 98.5), none, noLifts, noProtein, ph, fp, 0),
        )
        val narrow = fp.copy(rateWindowWeeks = 2L)
        add(
            "rate-gap-longer-than-window",
            scenario(base, listOf(100.0, null, null, null, 99.0), none, noLifts, noProtein, ph, narrow, 0),
        )
        add(
            "rate-window-clips",
            scenario(base, listOf(100.0, 90.0, 89.0, 88.0), none, noLifts, noProtein, ph, narrow, 0),
        )
        add("rate-gaining", scenario(base, listOf(100.0, 100.5, 101.0), none, noLifts, noProtein, ph, fp, 0))

        // §7.5 item 3: protein.
        val anchor = weighIn(base, 2)
        val floorDays = ArrayList<CutScorecardProteinDay>()
        for (k in 1..7) floorDays.add(protein(anchor - k, if (k <= 5) 99.9995 else 99.9994))
        add("protein-floor-quantized", scenario(base, listOf(100.0, 99.2), none, noLifts, floorDays, ph, fp, 0))
        add(
            "protein-later-entry-wins",
            scenario(
                base, listOf(100.0, 99.2), none, noLifts,
                listOf(
                    protein(anchor - 1, 50.0), protein(anchor - 1, 150.0),
                    protein(anchor - 2, 150.0), protein(anchor - 2, 50.0),
                    protein(anchor, 150.0), protein(anchor - 8, 150.0),
                ),
                ph, fp, 0,
            ),
        )
        add(
            "protein-zero-days",
            scenario(
                base, listOf(100.0, 99.2), none, noLifts,
                listOf(protein(anchor - 1, 0.0), protein(anchor - 2, -0.0), protein(anchor - 3, 0.0)),
                ph, fp, 0,
            ),
        )
        val noFloor = fp.copy(proteinFloorGrams = null)
        add(
            "protein-no-floor",
            scenario(base, listOf(100.0, 99.2), none, noLifts, listOf(protein(anchor - 1, 150.0)), ph, noFloor, 0),
        )
        return out
    }

    // MARK: Generated spread

    val EXERCISE_POOL: List<String> = listOf("Squat", "squat", "Squat ", "Bench", "Row", "Caf\u00E9", "Cafe\u0301")

    /** One generated input. Every draw is taken in the order the Swift generator takes it, one statement per draw. */
    fun generated(rng: Lcg): CutScorecardInput {
        val bases = listOf(dayNumber(2031, 1, 6), dayNumber(1968, 12, 30), dayNumber(2024, 2, 26), dayNumber(1999, 12, 27))
        val base = bases[rng.below(4)]
        val weekCount = 1 + rng.below(14)

        // Parameters.
        val rateWindow = 1 + rng.below(6)
        val waistWindow = 1 + rng.below(5)
        val waistMinimum = listOf(0.0, 0.1, 0.5, 1.0)[rng.below(4)]
        val liftTolerance = listOf(0.0, 2.5, 5.0, 10.0)[rng.below(4)]
        val liftShare = listOf(0.25, 0.333, 0.5, 1.0)[rng.below(4)]
        val liftWeeks = 1 + rng.below(4)
        val addKcal = listOf(0, 100, 300)[rng.below(3)]
        val slowThreshold = listOf(0.0, 0.25, 0.4, 0.5)[rng.below(4)]
        val slowWeeks = 1 + rng.below(4)
        val reduceKcal = listOf(0, 100, 250)[rng.below(3)]
        val floorChoice = rng.below(4)
        val proteinDaysRequired = 1 + rng.below(7)
        val maxAge = listOf(0, 1, 1, 2, 3, 60)[rng.below(6)]
        val maxProjection = listOf(1, 4, 52, 104, 100_000)[rng.below(5)]
        val targetTolerance = listOf(0.0, 0.0, 0.1, 0.5)[rng.below(4)]
        var parameters = CutScorecardParameters(
            rateWindowWeeks = rateWindow.toLong(), waistWindowWeeks = waistWindow.toLong(),
            waistMinDecreaseCm = waistMinimum,
            liftDropTolerancePercent = liftTolerance, liftDropShare = liftShare,
            liftDropConsecutiveWeeks = liftWeeks.toLong(),
            addCaloriesKcal = addKcal.toLong(), slowLossThresholdKgPerWeek = slowThreshold,
            slowLossConsecutiveWeeks = slowWeeks.toLong(),
            reduceCarbsKcal = reduceKcal.toLong(),
            proteinFloorGrams = if (floorChoice == 0) null else listOf(100.0, 120.5, 80.0)[floorChoice - 1],
            proteinMinDaysPerWeek = proteinDaysRequired.toLong(), maxWeighInAgeWeeks = maxAge.toLong(),
            maxProjectionWeeks = maxProjection.toLong(), targetToleranceKg = targetTolerance,
        )
        if (rng.chance(25)) {
            parameters = when (rng.below(8)) {
                0 -> parameters.copy(rateWindowWeeks = 0L)
                1 -> parameters.copy(waistWindowWeeks = -1L)
                2 -> parameters.copy(liftDropConsecutiveWeeks = 0L)
                3 -> parameters.copy(maxProjectionWeeks = 0L)
                4 -> parameters.copy(liftDropTolerancePercent = 100.0)
                5 -> parameters.copy(liftDropShare = 0.0)
                6 -> parameters.copy(proteinMinDaysPerWeek = 8L)
                else -> parameters.copy(targetToleranceKg = Double.NaN)
            }
        }

        // Weights and waists.
        val weights = ArrayList<CutScorecardReading>()
        val waists = ArrayList<CutScorecardReading>()
        val startGrams = 60_000 + rng.below(60_001)
        var grams = startGrams
        var waistMillimetres = 800 + rng.below(400)
        val weightMode = rng.below(5)
        var lastWeighDay = base
        for (w in 0 until weekCount) {
            var step = 0
            when (weightMode) {
                0 -> step = 300 + rng.below(700)
                1 -> step = rng.below(300)
                2 -> step = 0 - rng.below(400)
                3 -> step = rng.below(1_600) - 800
                else -> step = listOf(250, 249, 251, 400, 0, 500)[rng.below(6)]
            }
            if (w > 0) grams -= step
            val missedDraw = rng.chance(6)
            val missed = w > 0 && missedDraw
            val weekday = rng.below(7)
            val day = base + 7 * w + weekday
            if (!missed) {
                weights.add(reading(day, grams.toDouble() / 1000.0, 7))
                lastWeighDay = day
                if (rng.chance(8)) {
                    val kind = rng.below(3)
                    val other = (grams + 100 + rng.below(900)).toDouble() / 1000.0
                    if (kind == 0) {
                        weights.add(reading(base + 7 * w + rng.below(7), other, 7))
                    } else if (kind == 1) {
                        weights.add(reading(day, other, 6 + 2 * rng.below(2)))
                    } else {
                        weights.add(reading(day, other, 7))
                    }
                }
            }
            val waistStep = listOf(10, 5, 1, 0, -5, 4)[rng.below(6)]
            if (w > 0) waistMillimetres -= waistStep
            if (rng.below(4) != 0) waists.add(reading(day, waistMillimetres.toDouble() / 10.0, 7))
        }

        // Lifts: sessions from two weeks before the first weigh-in week.
        val lifts = ArrayList<CutScorecardLiftObservation>()
        val liftMode = rng.below(6)
        val exerciseCount = 1 + rng.below(4)
        val poolStart = rng.below(7)
        val halfKilograms = IntArray(exerciseCount)
        for (k in 0 until exerciseCount) halfKilograms[k] = 40 + rng.below(200)
        if (liftMode != 0) {
            for (w in 0 until weekCount + 2) {
                val day = base + 7 * w - 14 + rng.below(7)
                val skipped = liftMode == 5 && rng.chance(2)
                for (k in 0 until exerciseCount) {
                    when (liftMode) {
                        1 -> {}
                        2 -> halfKilograms[k] -= 2 + rng.below(8)
                        3 -> halfKilograms[k] += rng.below(5)
                        else -> halfKilograms[k] += rng.below(11) - 5
                    }
                    if (halfKilograms[k] < 1) halfKilograms[k] = 1
                    if (!skipped) {
                        lifts.add(lift(day, EXERCISE_POOL[(poolStart + k) % 7], halfKilograms[k].toDouble() / 2.0))
                    }
                }
            }
        }

        // Protein: the days from a week before the first weigh-in week to the end of the last.
        val proteinDays = ArrayList<CutScorecardProteinDay>()
        val proteinMode = rng.below(4)
        if (proteinMode != 0) {
            for (i in 0 until 7 * weekCount + 7) {
                val day = base - 7 + i
                val logged = proteinMode == 1 || rng.below(3) != 0
                val halfGrams = 120 + rng.below(180)
                if (logged) proteinDays.add(protein(day, halfGrams.toDouble() / 2.0))
                if (proteinMode == 3 && rng.chance(5)) {
                    proteinDays.add(protein(day, (120 + rng.below(180)).toDouble() / 2.0))
                }
            }
        }

        // Phase.
        var phase: CutScorecardPhase? = null
        val phaseDraw = rng.below(8)
        val startWeek = rng.below(weekCount + 3)
        val startMidWeek = rng.chance(3)
        val startWeekday = rng.below(7)
        val targetDraw = rng.below(5)
        val targetGrams = startGrams - 12_000 + rng.below(14_000)
        val low = listOf(0.0, 0.25, 0.4, 0.5)[rng.below(4)]
        val high = listOf(0.5, 1.0, 1.2, 0.4)[rng.below(4)]
        if (phaseDraw != 0) {
            phase = CutScorecardPhase(
                name = "Generated cut",
                startDay = key(base + 7 * startWeek - 14 + (if (startMidWeek) startWeekday else 0)),
                targetWeightKg = if (targetDraw == 0) null else targetGrams.toDouble() / 1000.0,
                rateLowPercentPerWeek = low, rateHighPercentPerWeek = high,
            )
        }

        // Today.
        var today = lastWeighDay
        val todayDraw = rng.below(10)
        val todayOffset = rng.below(126)
        if (todayDraw == 5 || todayDraw == 6) {
            today = lastWeighDay + todayOffset % 7
        } else if (todayDraw == 7) {
            today = lastWeighDay + 7 + todayOffset % 21
        } else if (todayDraw == 8) {
            today = base + todayOffset % (7 * weekCount)
        } else if (todayDraw == 9) {
            today = lastWeighDay + todayOffset
        }
        var todayKey = key(today)
        if (rng.chance(40)) todayKey = "2031-02-30"

        // Items that must be dropped and counted.
        if (rng.chance(5)) {
            val junkCount = 1 + rng.below(4)
            for (n in 0 until junkCount) {
                val day = base + rng.below(7 * weekCount)
                when (rng.below(10)) {
                    0 -> weights.add(reading(day, Double.NaN, 7))
                    1 -> weights.add(reading(day, Double.POSITIVE_INFINITY, 7))
                    2 -> weights.add(reading(day, -70.5, 7))
                    3 -> weights.add(reading(day, 0.0, 7))
                    4 -> weights.add(reading(day, 1e101, 7))
                    5 -> weights.add(CutScorecardReading("2031-1-8", 0L, 70.5))
                    6 -> waists.add(reading(day, Double.NEGATIVE_INFINITY, 7))
                    7 -> lifts.add(lift(day, "", 50.0))
                    8 -> proteinDays.add(protein(day, -1.0))
                    else -> weights.add(reading(today + 1 + rng.below(30), 70.5, 7))
                }
            }
        }

        // The result does not depend on input order (protein: the later of two entries on a day wins).
        var i = weights.size - 1
        while (i > 0) { java.util.Collections.swap(weights, i, rng.below(i + 1)); i -= 1 }
        i = waists.size - 1
        while (i > 0) { java.util.Collections.swap(waists, i, rng.below(i + 1)); i -= 1 }
        i = lifts.size - 1
        while (i > 0) { java.util.Collections.swap(lifts, i, rng.below(i + 1)); i -= 1 }
        i = proteinDays.size - 1
        while (i > 0) { java.util.Collections.swap(proteinDays, i, rng.below(i + 1)); i -= 1 }

        return CutScorecardInput(weights, waists, lifts, proteinDays, phase, parameters, todayKey)
    }

    // MARK: Every case, in order

    fun cases(): List<Pair<String, CutScorecardInput>> {
        val out = ArrayList<Pair<String, CutScorecardInput>>()
        for (week in 1..FIXTURE_WEEK_COUNT) out.add(("fixture-w" + pad(week, 2)) to fixtureInput(week))
        out.addAll(fixtureVariants())
        out.addAll(edgeCases())
        val rng = Lcg(SEED)
        for (index in 0 until GENERATED_COUNT) out.add(("generated-" + pad(index, 4)) to generated(rng))
        return out
    }

    /** `quantize` on exact halves, on negatives, on zero of either sign and on the unrepresentable. */
    fun quantizeLines(): List<String> {
        val values = arrayListOf(
            0.0, -0.0, 0.0005, -0.0005, 0.0015, -0.0015, 0.0025, -0.0025, 0.0004, -0.0004,
            0.00049999, -0.00049999, 1.0005, -1.0005, 1.005, -1.005, 2.5, -2.5, 4.35, 0.1 + 0.2,
            0.8034, 0.8025, 99.9995, 99.9994, 1e100, -1e100, 1e305, 1.7e308, -1.7e308,
            Double.MAX_VALUE, java.lang.Double.MIN_VALUE,
            -java.lang.Double.MIN_VALUE, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY, Double.NaN,
            4_503_599_627_370_496.5, 9_007_199_254_740_992.0, 1e15, 123_456_789.0005,
        )
        val rng = Lcg(SEED + 1L)
        for (n in 0 until 200) {
            // An odd count of half-thousandths: an exact half in the third decimal, as nearly as a Double holds it.
            val halves = 2 * rng.below(200_000) + 1
            val negative = rng.chance(2)
            val value = halves.toDouble() / 2000.0
            values.add(if (negative) -value else value)
        }
        val out = ArrayList<String>()
        for (value in values) {
            val result = CutScorecard.quantize(value)
            out.add("quantize|" + bitsHex(value) + "|" + bitsHex(result) + "|" + f(result))
        }
        return out
    }

    /** `weekStart` across valid and invalid keys. */
    fun weekStartLines(): List<String> {
        val keys = arrayListOf(
            "2031-01-08", "2031-01-06", "2031-01-12", "2031-1-8", "+2031-01-08", "0001-01-01", "0001-01-07",
            "0000-12-31", "9999-12-31", "10000-01-01", "2031-02-29", "2032-02-29", "1900-02-29",
            "2000-02-29", "1969-12-31", "1970-01-01", "", "2031-01-08 ", " 2031-01-08", "2031/01/08",
            "2031-13-01", "2031-00-10", "2031-01-00", "2031-01-32", "-031-01-08", "0031-01-08",
            "2031-01-08-01", "20310108", "\u0662\u0660\u0663\u0661-01-08", "2031-01-0\u0663",
        )
        val rng = Lcg(SEED + 2L)
        for (n in 0 until 60) keys.add(key(dayNumber(1, 1, 1) + rng.below(3_652_059)))
        val out = ArrayList<String>()
        for (k in keys) out.add("weekStart|" + k + "|" + so(CutScorecard.weekStart(k)))
        return out
    }

    /** The formatter itself: ties, signed zero and large magnitudes, so "%.6f" is pinned on both sides. */
    fun formatLines(): List<String> {
        val values = listOf(
            0.0078125, 0.0234375, -0.0078125, -0.0, -1e-9, 1e-9, 0.1 + 0.2, 2.5e-7, 1e21,
            123_456_789.123456789, 0.0000005, 0.0000015, 2.9999999999999996, 1e100,
        )
        val out = ArrayList<String>()
        for (value in values) out.add("format|" + bitsHex(value) + "|" + f(value))
        return out
    }

    /** The whole oracle: one line per case. */
    fun allLines(): List<String> {
        val out = ArrayList<String>()
        out.addAll(formatLines())
        out.addAll(quantizeLines())
        out.addAll(weekStartLines())
        for ((label, input) in cases()) out.add(line(label, input))
        return out
    }
}
