import Foundation
import StrandAnalytics
import WhoopProtocol

/// Local, held-out checks of the existing motion estimate. These values never become measured steps
/// or calibration inputs. One passing walk describes that walk only; it does not validate a pedometer.
enum StepWalkValidation {
    static let countedStepRange = 500...1_000
    static let maximumAbsoluteErrorPercent = 10.0

    enum InputError: Error, Equatable {
        case invalidIdentifier, invalidSource, invalidDate, invalidCalibration, invalidCount, invalidCoveragePolicy
    }

    struct CalibrationSnapshot: Codable, Equatable {
        let coefficient: Double
        let sampleDays: Int
        let confidence: Double
        let manual: Bool

        init(_ calibration: StepsEstimateEngine.Calibration) throws {
            try self.init(coefficient: calibration.coefficient, sampleDays: calibration.sampleDays,
                          confidence: calibration.confidence, manual: calibration.manual)
        }

        init(coefficient: Double, sampleDays: Int, confidence: Double, manual: Bool) throws {
            guard coefficient.isFinite, coefficient > 0, sampleDays >= 0,
                  confidence.isFinite, (0...1).contains(confidence) else { throw InputError.invalidCalibration }
            self.coefficient = coefficient; self.sampleDays = sampleDays
            self.confidence = confidence; self.manual = manual
        }

        fileprivate var isValid: Bool {
            coefficient.isFinite && coefficient > 0 && sampleDays >= 0
                && confidence.isFinite && (0...1).contains(confidence)
        }

        fileprivate var calibration: StepsEstimateEngine.Calibration {
            .init(coefficient: coefficient, sampleDays: sampleDays, confidence: confidence, manual: manual)
        }
    }

    struct Trial: Codable, Equatable, Identifiable {
        let id: String
        let sourceDeviceId: String
        let startedAt: Date
        let calibration: CalibrationSnapshot
        private(set) var endedAt: Date?
        private(set) var countedSteps: Int?

        init(id: String = UUID().uuidString, sourceDeviceId: String, startedAt: Date,
             calibration: CalibrationSnapshot) throws {
            guard validIdentifier(id) else { throw InputError.invalidIdentifier }
            guard validIdentifier(sourceDeviceId) else { throw InputError.invalidSource }
            guard validDate(startedAt) else { throw InputError.invalidDate }
            guard calibration.isValid else { throw InputError.invalidCalibration }
            self.id = id; self.sourceDeviceId = sourceDeviceId; self.startedAt = startedAt
            self.calibration = calibration
            endedAt = nil; countedSteps = nil
        }

        private enum CodingKeys: String, CodingKey {
            case id, sourceDeviceId, startedAt, calibration, endedAt, countedSteps
        }

        /// Persistence is an input boundary too: reject corrupted bounds before callers convert
        /// dates to integer timestamps for a database query.
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(id: values.decode(String.self, forKey: .id),
                          sourceDeviceId: values.decode(String.self, forKey: .sourceDeviceId),
                          startedAt: values.decode(Date.self, forKey: .startedAt),
                          calibration: values.decode(CalibrationSnapshot.self, forKey: .calibration))
            let end = try values.decodeIfPresent(Date.self, forKey: .endedAt)
            let count = try values.decodeIfPresent(Int.self, forKey: .countedSteps)
            if let end, let count { self = try completed(endedAt: end, countedSteps: count) }
            else if end != nil || count != nil {
                throw DecodingError.dataCorruptedError(forKey: .endedAt, in: values,
                    debugDescription: "A completed walk requires both its end and counted steps.")
            }
        }

        func completed(endedAt: Date, countedSteps: Int) throws -> Trial {
            guard validDate(startedAt), validDate(endedAt), endedAt > startedAt else { throw InputError.invalidDate }
            guard StepWalkValidation.countedStepRange.contains(countedSteps) else { throw InputError.invalidCount }
            guard validIdentifier(id) else { throw InputError.invalidIdentifier }
            guard validIdentifier(sourceDeviceId) else { throw InputError.invalidSource }
            guard calibration.isValid else { throw InputError.invalidCalibration }
            var result = self
            result.endedAt = endedAt; result.countedSteps = countedSteps
            return result
        }

        /// Safe database bounds for this finished, valid trial. The fractional endpoints are checked
        /// again by `analyze`; the query may include the integer second containing the start.
        var motionQueryBounds: ClosedRange<Int>? {
            guard validIdentifier(id), validIdentifier(sourceDeviceId), calibration.isValid,
                  validDate(startedAt), let endedAt, validDate(endedAt), endedAt > startedAt,
                  let countedSteps, StepWalkValidation.countedStepRange.contains(countedSteps) else { return nil }
            return Int(startedAt.timeIntervalSince1970)...Int(endedAt.timeIntervalSince1970)
        }
    }

    /// The caller explicitly chooses a recording-continuity assumption. There is no default cadence:
    /// a mean interval cannot establish that a walk was recorded continuously. These limits qualify
    /// data availability only, and cannot turn sparse gravity samples into individual footfalls.
    struct CoveragePolicy: Codable, Equatable {
        let maximumGapSeconds: TimeInterval
        let maximumBoundaryGapSeconds: TimeInterval
        let minimumUsableSamples: Int

        init(maximumGapSeconds: TimeInterval, maximumBoundaryGapSeconds: TimeInterval,
             minimumUsableSamples: Int = 2) throws {
            guard maximumGapSeconds.isFinite, maximumGapSeconds > 0,
                  maximumBoundaryGapSeconds.isFinite, maximumBoundaryGapSeconds >= 0,
                  minimumUsableSamples >= 2 else { throw InputError.invalidCoveragePolicy }
            self.maximumGapSeconds = maximumGapSeconds
            self.maximumBoundaryGapSeconds = maximumBoundaryGapSeconds
            self.minimumUsableSamples = minimumUsableSamples
        }

        fileprivate var isValid: Bool {
            maximumGapSeconds.isFinite && maximumGapSeconds > 0
                && maximumBoundaryGapSeconds.isFinite && maximumBoundaryGapSeconds >= 0
                && minimumUsableSamples >= 2
        }
    }

    enum Verdict: String, Codable { case pass, fail, incomplete }

    enum IncompleteReason: String, Codable, Equatable {
        case invalidIdentifier, invalidSource, invalidDates, unfinishedTrial, invalidCount, invalidCalibration
        case invalidCoveragePolicy, insufficientMotionSamples, invalidMotionSamples, conflictingTimestamps
        case motionGap, startNotCovered, endNotCovered, insufficientMotion, nonFiniteMotion
    }

    struct Diagnostics: Codable, Equatable {
        let usableMotionSampleCount: Int
        let rejectedMotionSampleCount: Int
        let duplicateSampleCount: Int
        let conflictingTimestampCount: Int
        let firstSampleAt: Date?
        let lastSampleAt: Date?
        let maximumGapSeconds: TimeInterval?
        let startGapSeconds: TimeInterval?
        let endGapSeconds: TimeInterval?
        /// Sum of adjacent sample spans within the supplied maximum-gap limit, divided by the
        /// trial duration. This is temporal support under that assumption, not a sampling rate.
        let supportedSpanFraction: Double?
        let motionIntensity: Double?

        fileprivate static let empty = Diagnostics(usableMotionSampleCount: 0, rejectedMotionSampleCount: 0,
            duplicateSampleCount: 0, conflictingTimestampCount: 0, firstSampleAt: nil, lastSampleAt: nil,
            maximumGapSeconds: nil, startGapSeconds: nil, endGapSeconds: nil,
            supportedSpanFraction: nil, motionIntensity: nil)
    }

    struct Result: Codable, Equatable {
        let trialId: String
        let sourceDeviceId: String
        let calibration: CalibrationSnapshot
        let coveragePolicy: CoveragePolicy
        let verdict: Verdict
        let incompleteReasons: [IncompleteReason]
        let estimatedSteps: Int?
        let signedErrorSteps: Int?
        let absoluteErrorSteps: Int?
        let signedErrorPercent: Double?
        let absoluteErrorPercent: Double?
        let diagnostics: Diagnostics
    }

    /// Input must come from `trial.sourceDeviceId` alone. GravitySample has no source identifier, so
    /// source selection belongs at the repository call; samples from multiple straps must never be unioned.
    static func analyze(trial: Trial, gravity: [GravitySample], coveragePolicy: CoveragePolicy) -> Result {
        var reasons = [IncompleteReason]()
        if !validIdentifier(trial.id) { reasons.append(.invalidIdentifier) }
        if !validIdentifier(trial.sourceDeviceId) { reasons.append(.invalidSource) }
        if !trial.calibration.isValid { reasons.append(.invalidCalibration) }
        if !coveragePolicy.isValid { reasons.append(.invalidCoveragePolicy) }
        guard validDate(trial.startedAt), let end = trial.endedAt, validDate(end), end > trial.startedAt else {
            reasons.append(trial.endedAt == nil ? .unfinishedTrial : .invalidDates)
            return result(trial, coveragePolicy, reasons: reasons, diagnostics: .empty)
        }
        guard let actual = trial.countedSteps, countedStepRange.contains(actual) else {
            reasons.append(.invalidCount)
            return result(trial, coveragePolicy, reasons: reasons, diagnostics: .empty)
        }
        guard coveragePolicy.isValid else {
            return result(trial, coveragePolicy, reasons: reasons, diagnostics: .empty)
        }

        let startTs = trial.startedAt.timeIntervalSince1970, endTs = end.timeIntervalSince1970
        let bounded = gravity.filter { Double($0.ts) >= startTs && Double($0.ts) <= endTs }
        let finite = bounded.filter { $0.unit == "g" && $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }
        let rejected = bounded.count - finite.count
        if rejected > 0 { reasons.append(.invalidMotionSamples) }

        var byTime = [Int: GravitySample](), duplicates = 0, conflicts = Set<Int>()
        for sample in finite {
            if let previous = byTime[sample.ts] {
                duplicates += 1
                if previous.x != sample.x || previous.y != sample.y || previous.z != sample.z {
                    conflicts.insert(sample.ts)
                }
            } else { byTime[sample.ts] = sample }
        }
        let samples = byTime.values.sorted { $0.ts < $1.ts }
        if !conflicts.isEmpty { reasons.append(.conflictingTimestamps) }
        if samples.count < coveragePolicy.minimumUsableSamples { reasons.append(.insufficientMotionSamples) }

        let first = samples.first.map { Date(timeIntervalSince1970: Double($0.ts)) }
        let last = samples.last.map { Date(timeIntervalSince1970: Double($0.ts)) }
        let startGap = first.map { $0.timeIntervalSince(trial.startedAt) }
        let endGap = last.map { end.timeIntervalSince($0) }
        let gaps = zip(samples, samples.dropFirst()).map { Double($0.1.ts) - Double($0.0.ts) }
        let maximumGap = gaps.max()
        if let maximumGap, maximumGap > coveragePolicy.maximumGapSeconds { reasons.append(.motionGap) }
        if startGap == nil || startGap! > coveragePolicy.maximumBoundaryGapSeconds { reasons.append(.startNotCovered) }
        if endGap == nil || endGap! > coveragePolicy.maximumBoundaryGapSeconds { reasons.append(.endNotCovered) }
        let supported = gaps.filter { $0 <= coveragePolicy.maximumGapSeconds }.reduce(0, +) / (endTs - startTs)
        let motion = StepsEstimateEngine.dayMotionIntensity(samples)
        if !motion.isFinite { reasons.append(.nonFiniteMotion) }
        else if motion < StepsEstimateEngine.minMotionForFit { reasons.append(.insufficientMotion) }
        let diagnostics = Diagnostics(usableMotionSampleCount: samples.count, rejectedMotionSampleCount: rejected,
            duplicateSampleCount: duplicates, conflictingTimestampCount: conflicts.count,
            firstSampleAt: first, lastSampleAt: last, maximumGapSeconds: maximumGap,
            startGapSeconds: startGap, endGapSeconds: endGap, supportedSpanFraction: supported,
            motionIntensity: motion.isFinite ? motion : nil)

        // The existing engine converts to Int before clamping, so reject overflow before invoking it.
        let rawEstimate = motion * trial.calibration.coefficient
        if trial.calibration.isValid && (!rawEstimate.isFinite || rawEstimate >= Double(Int.max)) {
            reasons.append(.nonFiniteMotion)
        }
        guard reasons.isEmpty,
              let estimate = StepsEstimateEngine.estimate(motion: motion, calibration: trial.calibration.calibration) else {
            return result(trial, coveragePolicy, reasons: reasons, diagnostics: diagnostics)
        }
        let signed = estimate - actual, absolute = abs(signed)
        let signedPercent = Double(signed) * 100 / Double(actual)
        let absolutePercent = Double(absolute) * 100 / Double(actual)
        return Result(trialId: trial.id, sourceDeviceId: trial.sourceDeviceId, calibration: trial.calibration,
            coveragePolicy: coveragePolicy, verdict: absolutePercent <= maximumAbsoluteErrorPercent ? .pass : .fail,
            incompleteReasons: [], estimatedSteps: estimate, signedErrorSteps: signed, absoluteErrorSteps: absolute,
            signedErrorPercent: signedPercent, absoluteErrorPercent: absolutePercent, diagnostics: diagnostics)
    }

    private static func result(_ trial: Trial, _ policy: CoveragePolicy, reasons: [IncompleteReason],
                               diagnostics: Diagnostics) -> Result {
        Result(trialId: trial.id, sourceDeviceId: trial.sourceDeviceId, calibration: trial.calibration,
            coveragePolicy: policy, verdict: .incomplete, incompleteReasons: reasons, estimatedSteps: nil,
            signedErrorSteps: nil, absoluteErrorSteps: nil, signedErrorPercent: nil, absoluteErrorPercent: nil,
            diagnostics: diagnostics)
    }

    private static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    private static func validDate(_ value: Date) -> Bool {
        value.timeIntervalSince1970.isFinite && value.timeIntervalSince1970 >= 0
            && value.timeIntervalSince1970 < Double(Int.max)
    }
}
