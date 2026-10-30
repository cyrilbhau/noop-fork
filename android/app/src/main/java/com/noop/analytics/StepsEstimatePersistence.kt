package com.noop.analytics

import com.noop.protocol.DeviceFamily

/** Independent WHOOP 4.0 estimate writes. Health references never suppress a separate estimate.
 * An absent plan entry means no write, never deletion. Swift twin: StepsEstimatePersistence. */
object StepsEstimatePersistence {
    data class DayInput(
        val owner: String,
        val family: DeviceFamily?,
        /** null is a failed motion read; zero is a successful read with no movement. */
        val motion: Double?,
    )

    data class Estimate(val day: String, val deviceId: String, val motion: Double, val steps: Int)

    /** Swift twin: `StepsEstimatePersistence.plan`. */
    fun plan(
        scoredDays: List<String>,
        inputs: Map<String, DayInput>,
        calibration: StepsEstimateEngine.Calibration?,
    ): List<Estimate> {
        if (calibration == null || !calibration.coefficient.isFinite() || calibration.coefficient <= 0) return emptyList()
        return scoredDays.mapNotNull { day ->
            val input = inputs[day] ?: return@mapNotNull null
            if (input.family != DeviceFamily.WHOOP4 || input.owner.isEmpty()) return@mapNotNull null
            val motion = input.motion ?: return@mapNotNull null
            if (!motion.isFinite()) return@mapNotNull null
            // Match Swift's guard before the existing estimator narrows to Int32.
            val raw = motion * calibration.coefficient
            if (!raw.isFinite() || raw < 0 || Math.round(raw).toDouble() >= 2_147_483_648.0) {
                return@mapNotNull null
            }
            val steps = StepsEstimateEngine.estimate(motion, calibration) ?: return@mapNotNull null
            Estimate(day, input.owner + "-noop", motion, steps)
        }
    }
}
