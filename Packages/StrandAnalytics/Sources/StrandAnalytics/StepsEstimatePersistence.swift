import WhoopProtocol

/// Plans independent WHOOP 4.0 motion-estimate writes. Health references calibrate the model; their
/// presence never suppresses a day's separate estimate. No plan entry means no write, never a deletion.
/// Kotlin twin: `StepsEstimatePersistence`.
public enum StepsEstimatePersistence {
    public struct DayInput: Sendable {
        public let owner: String
        public let family: DeviceFamily?
        /// nil when the motion read failed; zero when a successful read found no movement.
        public let motion: Double?

        public init(owner: String, family: DeviceFamily?, motion: Double?) {
            self.owner = owner; self.family = family; self.motion = motion
        }
    }

    public struct Estimate: Equatable, Sendable {
        public let day: String
        public let deviceId: String
        public let motion: Double
        public let steps: Int
    }

    /// Kotlin twin: `StepsEstimatePersistence.plan`.
    public static func plan(scoredDays: [String], inputs: [String: DayInput],
                            calibration: StepsEstimateEngine.Calibration?) -> [Estimate] {
        guard let calibration, calibration.coefficient.isFinite, calibration.coefficient > 0 else { return [] }
        return scoredDays.compactMap { day in
            guard let input = inputs[day], input.family == .whoop4, !input.owner.isEmpty,
                  let motion = input.motion, motion.isFinite else { return nil }
            // The existing estimator rounds to Int before clamping. Reject corrupt/overflowing inputs
            // before that conversion. Kotlin narrows to Int32, so use its stricter bound on both sides.
            let raw = motion * calibration.coefficient
            guard raw.isFinite, raw >= 0, raw.rounded() < 2_147_483_648.0,
                  let steps = StepsEstimateEngine.estimate(motion: motion, calibration: calibration) else { return nil }
            return Estimate(day: day, deviceId: input.owner + "-noop", motion: motion, steps: steps)
        }
    }
}
