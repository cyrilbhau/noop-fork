package com.noop.analytics

import com.noop.protocol.DeviceFamily
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class StepsEstimatePersistenceTest {
    private val calibration = StepsEstimateEngine.Calibration(100.0, 3, 0.6, false)

    @Test
    fun healthReferenceDaysRetainIndependentEstimatesAlongsidePhoneFreeDays() {
        val references = mapOf("2026-10-26" to 1000.0, "2026-10-27" to 2000.0, "2026-10-28" to 3000.0)
        val motions = mapOf("2026-10-26" to 10.0, "2026-10-27" to 20.0, "2026-10-28" to 30.0, "2026-10-29" to 40.0)
        val fit = StepsEstimateEngine.calibrate(references.map { (day, steps) ->
            StepsEstimateEngine.CalibrationPoint(motions.getValue(day), steps)
        })
        val inputs = motions.mapValues { StepsEstimatePersistence.DayInput("strap", DeviceFamily.WHOOP4, it.value) }
        val plan = StepsEstimatePersistence.plan(motions.keys.sorted(), inputs, fit)
        assertEquals(motions.keys.sorted(), plan.map { it.day })
        assertEquals(listOf(1000, 2000, 3000, 4000), plan.map { it.steps })
        assertEquals(setOf("strap-noop"), plan.map { it.deviceId }.toSet())
        assertEquals(1000.0, references["2026-10-26"])
    }

    @Test
    fun onlyConfirmedWhoop4OwnersProduceAttributedWrites() {
        val inputs = mapOf(
            "four" to StepsEstimatePersistence.DayInput("historical-strap", DeviceFamily.WHOOP4, 10.0),
            "five" to StepsEstimatePersistence.DayInput("active-strap", DeviceFamily.WHOOP5, 20.0),
            "unknown" to StepsEstimatePersistence.DayInput("ring-or-unknown", null, 30.0),
            "unowned" to StepsEstimatePersistence.DayInput("", DeviceFamily.WHOOP4, 40.0),
            "unscored" to StepsEstimatePersistence.DayInput("historical-strap", DeviceFamily.WHOOP4, 50.0),
        )
        val plan = StepsEstimatePersistence.plan(listOf("four", "five", "unknown", "unowned"), inputs, calibration)
        assertEquals(1, plan.size)
        assertEquals("historical-strap-noop", plan.single().deviceId)
        assertEquals(1000, plan.single().steps)
    }

    @Test
    fun failedEmptyAndUncalibratedReadsPlanNoReplacementOrDeletion() {
        val inputs = mapOf(
            "failed" to StepsEstimatePersistence.DayInput("strap", DeviceFamily.WHOOP4, null),
            "empty" to StepsEstimatePersistence.DayInput("strap", DeviceFamily.WHOOP4, 0.0),
            "corrupt" to StepsEstimatePersistence.DayInput("strap", DeviceFamily.WHOOP4, Double.NaN),
        )
        assertTrue(StepsEstimatePersistence.plan(inputs.keys.sorted(), inputs, calibration).isEmpty())
        assertTrue(StepsEstimatePersistence.plan(listOf("day"), mapOf(
            "day" to StepsEstimatePersistence.DayInput("strap", DeviceFamily.WHOOP4, 10.0),
        ), null).isEmpty())
    }

    @Test
    fun laterStrapMotionRefreshesEstimateOnAReferenceDay() {
        fun plan(motion: Double) = StepsEstimatePersistence.plan(listOf("reference"), mapOf(
            "reference" to StepsEstimatePersistence.DayInput("strap", DeviceFamily.WHOOP4, motion),
        ), calibration)
        assertEquals(1000, plan(10.0).single().steps)
        assertEquals(1500, plan(15.0).single().steps)
    }

    @Test
    fun swiftKotlinDecisionOracle() {
        val output = arrayListOf<String>()
        val huge = StepsEstimateEngine.Calibration(1e308, 3, 0.6, false)
        val corrupt = StepsEstimateEngine.Calibration(Double.POSITIVE_INFINITY, 3, 0.6, false)
        for (family in listOf(null, DeviceFamily.WHOOP4, DeviceFamily.WHOOP5)) {
            for (owner in listOf("", "strap")) {
                for (motion in listOf(null, 0.0, 0.5, 1.0, 12.345, Double.POSITIVE_INFINITY, Double.MAX_VALUE,
                    21_474_836.47, 42_949_672.96)) {
                    for (fit in listOf(null, calibration, huge, corrupt)) {
                        val plan = StepsEstimatePersistence.plan(listOf("day"), mapOf(
                            "day" to StepsEstimatePersistence.DayInput(owner, family, motion),
                        ), fit)
                        output.add(plan.firstOrNull()?.let { "${it.deviceId}:${it.steps}" } ?: "-")
                    }
                }
            }
        }
        // Standalone Swift oracle stdout, also pinned by the Swift test.
        assertEquals("-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|strap-noop:100|-|-|-|strap-noop:1235|-|-|-|-|-|-|-|-|-|-|-|strap-noop:60000|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-", output.joinToString("|"))
    }

    @Test
    fun invalidCoefficientsAndFiniteOverflowAreRejectedBeforeIntegerConversion() {
        for (coefficient in listOf(Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY, 0.0, -1.0, 1e308)) {
            val invalid = StepsEstimateEngine.Calibration(coefficient, 3, 0.6, false)
            assertTrue(StepsEstimatePersistence.plan(listOf("day"), mapOf(
                "day" to StepsEstimatePersistence.DayInput("strap", DeviceFamily.WHOOP4, 10.0),
            ), invalid).isEmpty())
        }
        assertTrue(StepsEstimatePersistence.plan(listOf("day"), mapOf(
            "day" to StepsEstimatePersistence.DayInput("strap", DeviceFamily.WHOOP4, 1e308),
        ), calibration).isEmpty())
    }

    @Test
    fun int32NarrowingBoundaryMatchesSwiftBeforeTheExistingClamp() {
        val fit = StepsEstimateEngine.Calibration(1.0, 3, 0.6, false)
        fun steps(motion: Double) = StepsEstimatePersistence.plan(listOf("day"), mapOf(
            "day" to StepsEstimatePersistence.DayInput("strap", DeviceFamily.WHOOP4, motion),
        ), fit).firstOrNull()?.steps
        assertEquals(60000, steps(2_147_483_647.0))
        assertEquals(60000, steps(2_147_483_647.49))
        assertEquals(null, steps(2_147_483_647.5))
        assertEquals(null, steps(2_147_483_648.0))
        assertEquals(null, steps(4_294_967_296.0))
    }
}
