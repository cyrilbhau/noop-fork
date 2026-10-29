import Foundation
@testable import Strand
import StrandAnalytics
import WhoopProtocol
import XCTest

final class StepWalkValidationTests: XCTestCase {
    private typealias Validation = StepWalkValidation
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func calibration(_ coefficient: Double = 10) throws -> Validation.CalibrationSnapshot {
        try .init(coefficient: coefficient, sampleDays: 5, confidence: 0.7, manual: false)
    }

    private func trial(seconds: Int = 100, actual: Int = 1_000, coefficient: Double = 10) throws -> Validation.Trial {
        try Validation.Trial(id: "walk-1", sourceDeviceId: "owned-whoop-4", startedAt: start,
            calibration: calibration(coefficient)).completed(endedAt: start.addingTimeInterval(Double(seconds)),
                                                           countedSteps: actual)
    }

    private func policy(gap: Double = 2, boundary: Double = 0) throws -> Validation.CoveragePolicy {
        try .init(maximumGapSeconds: gap, maximumBoundaryGapSeconds: boundary)
    }

    private func motion(seconds: Int = 100, amplitude: Double = 1) -> [GravitySample] {
        (0...seconds).map { .init(ts: Int(start.timeIntervalSince1970) + $0,
                                 x: $0.isMultiple(of: 2) ? 0 : amplitude, y: 0, z: 1) }
    }

    func testVaryingInjectedMotionAndFixedCoefficientsRecoverDifferentTotals() throws {
        for (seconds, amplitude, coefficient, actual) in [(100, 1.0, 5.0, 500), (120, 0.5, 10.0, 600), (100, 1.0, 10.0, 1_000)] {
            let walk = try trial(seconds: seconds, actual: actual, coefficient: coefficient)
            let result = Validation.analyze(trial: walk, gravity: motion(seconds: seconds, amplitude: amplitude),
                                            coveragePolicy: try policy())
            XCTAssertEqual(result.verdict, .pass)
            XCTAssertEqual(result.estimatedSteps, actual)
            XCTAssertEqual(result.absoluteErrorPercent, 0)
            XCTAssertEqual(result.sourceDeviceId, "owned-whoop-4")
            XCTAssertEqual(result.calibration, walk.calibration)
            XCTAssertEqual(result.diagnostics.usableMotionSampleCount, seconds + 1)
            XCTAssertEqual(result.diagnostics.supportedSpanFraction, 1)
        }
    }

    func testAgreedTenPercentBoundaryAndSignedError() throws {
        let walk = try trial(actual: 500, coefficient: 5.5)
        let result = Validation.analyze(trial: walk, gravity: motion(), coveragePolicy: try policy())
        XCTAssertEqual(result.verdict, .pass)
        XCTAssertEqual(result.estimatedSteps, 550)
        XCTAssertEqual(result.signedErrorSteps, 50)
        XCTAssertEqual(result.absoluteErrorPercent, 10)
        let failed = Validation.analyze(trial: try trial(actual: 500, coefficient: 4.49),
                                        gravity: motion(), coveragePolicy: try policy())
        XCTAssertEqual(failed.verdict, .fail)
        XCTAssertEqual(failed.signedErrorSteps, -51)
        XCTAssertEqual(failed.absoluteErrorSteps, 51)
        XCTAssertEqual(failed.signedErrorPercent!, -10.2, accuracy: 0.0001)
    }

    func testEmptyAndSingleSampleNeverPassAsZeroMotion() throws {
        for samples in [[], Array(motion().prefix(1))] {
            let result = Validation.analyze(trial: try trial(), gravity: samples, coveragePolicy: try policy())
            XCTAssertEqual(result.verdict, .incomplete)
            XCTAssertNil(result.estimatedSteps)
            XCTAssertNil(result.absoluteErrorPercent)
            XCTAssertTrue(result.incompleteReasons.contains(.insufficientMotionSamples))
            XCTAssertEqual(result.diagnostics.usableMotionSampleCount, samples.count)
        }
    }

    func testLargeGapCannotBeHiddenByManyDenseSamplesOrMeanInterval() throws {
        let samples = motion().filter { $0.ts < Int(start.timeIntervalSince1970) + 30 || $0.ts > Int(start.timeIntervalSince1970) + 60 }
        let result = Validation.analyze(trial: try trial(), gravity: samples, coveragePolicy: try policy())
        XCTAssertEqual(result.verdict, .incomplete)
        XCTAssertEqual(result.diagnostics.maximumGapSeconds, 32)
        XCTAssertTrue(result.incompleteReasons.contains(.motionGap))
        XCTAssertEqual(result.diagnostics.supportedSpanFraction!, 0.68, accuracy: 0.0001)
        XCTAssertNil(result.absoluteErrorPercent)
    }

    func testSparseSamplesAreReportedAsIncompleteUnderDeclaredPolicy() throws {
        let result = Validation.analyze(trial: try trial(), gravity: [motion()[0], motion()[50], motion()[100]],
                                        coveragePolicy: try policy())
        XCTAssertEqual(result.verdict, .incomplete)
        XCTAssertTrue(result.incompleteReasons.contains(.motionGap))
        XCTAssertEqual(result.diagnostics.supportedSpanFraction, 0)
    }

    func testBoundaryCoverageIsSeparateFromInternalGap() throws {
        let result = Validation.analyze(trial: try trial(), gravity: Array(motion()[10...90]),
                                        coveragePolicy: try policy())
        XCTAssertEqual(result.verdict, .incomplete)
        XCTAssertEqual(result.diagnostics.maximumGapSeconds, 1)
        XCTAssertEqual(result.diagnostics.startGapSeconds, 10)
        XCTAssertEqual(result.diagnostics.endGapSeconds, 10)
        XCTAssertTrue(result.incompleteReasons.contains(.startNotCovered))
        XCTAssertTrue(result.incompleteReasons.contains(.endNotCovered))
    }

    func testUnsortedSamplesAndExactDuplicatesDoNotAddMovement() throws {
        var samples = Array(motion().reversed())
        samples.append(samples[30])
        let result = Validation.analyze(trial: try trial(), gravity: samples, coveragePolicy: try policy())
        XCTAssertEqual(result.verdict, .pass)
        XCTAssertEqual(result.estimatedSteps, 1_000)
        XCTAssertEqual(result.diagnostics.duplicateSampleCount, 1)
        XCTAssertEqual(result.diagnostics.usableMotionSampleCount, 101)
    }

    func testConflictingDuplicateTimestampWithholdsVerdict() throws {
        var samples = motion()
        samples.append(.init(ts: samples[30].ts, x: 2, y: 0, z: 1))
        let result = Validation.analyze(trial: try trial(), gravity: samples, coveragePolicy: try policy())
        XCTAssertEqual(result.verdict, .incomplete)
        XCTAssertTrue(result.incompleteReasons.contains(.conflictingTimestamps))
        XCTAssertEqual(result.diagnostics.conflictingTimestampCount, 1)
    }

    func testNonFiniteAndWrongUnitSamplesCannotDisappearIntoPassingTrial() throws {
        for invalid in [GravitySample(ts: motion()[30].ts, x: .nan, y: 0, z: 1),
                        .init(ts: motion()[30].ts, x: 0, y: 0, z: 1, unit: "raw")] {
            var samples = motion()
            samples[30] = invalid
            let result = Validation.analyze(trial: try trial(), gravity: samples, coveragePolicy: try policy())
            XCTAssertEqual(result.verdict, .incomplete)
            XCTAssertTrue(result.incompleteReasons.contains(.invalidMotionSamples))
            XCTAssertEqual(result.diagnostics.rejectedMotionSampleCount, 1)
        }
    }

    func testFiniteInputsThatOverflowMotionOrEstimateDoNotTrap() throws {
        let overflowingMotion = Validation.analyze(trial: try trial(), gravity: motion(amplitude: 1e300),
                                                  coveragePolicy: try policy())
        XCTAssertEqual(overflowingMotion.verdict, .incomplete)
        XCTAssertTrue(overflowingMotion.incompleteReasons.contains(.nonFiniteMotion))
        let overflowingEstimate = Validation.analyze(trial: try trial(coefficient: 1e300), gravity: motion(),
                                                    coveragePolicy: try policy())
        XCTAssertEqual(overflowingEstimate.verdict, .incomplete)
        XCTAssertNil(overflowingEstimate.estimatedSteps)
    }

    func testSamplesOutsideWalkCannotAffectResult() throws {
        let samples = motion() + [.init(ts: Int(start.timeIntervalSince1970) - 1, x: 1e100, y: 0, z: 1),
                                  .init(ts: Int(start.timeIntervalSince1970) + 101, x: .nan, y: 0, z: 1)]
        let result = Validation.analyze(trial: try trial(), gravity: samples, coveragePolicy: try policy())
        XCTAssertEqual(result.estimatedSteps, 1_000)
        XCTAssertEqual(result.diagnostics.rejectedMotionSampleCount, 0)
    }

    func testTrialRequiresCompletedDatesAndAgreedCountRange() throws {
        let pending = try Validation.Trial(sourceDeviceId: "owned-whoop-4", startedAt: start, calibration: calibration())
        XCTAssertNil(pending.motionQueryBounds)
        let complete = try pending.completed(endedAt: start.addingTimeInterval(100), countedSteps: 500)
        XCTAssertEqual(complete.motionQueryBounds,
                       Int(start.timeIntervalSince1970)...Int(start.timeIntervalSince1970) + 100)
        let result = Validation.analyze(trial: pending, gravity: motion(), coveragePolicy: try policy())
        XCTAssertEqual(result.verdict, .incomplete)
        XCTAssertTrue(result.incompleteReasons.contains(.unfinishedTrial))
        for count in [0, 499, 1_001, Int.max] {
            XCTAssertThrowsError(try pending.completed(endedAt: start.addingTimeInterval(100), countedSteps: count))
        }
        XCTAssertThrowsError(try pending.completed(endedAt: start, countedSteps: 500))
        XCTAssertThrowsError(try pending.completed(endedAt: start.addingTimeInterval(-1), countedSteps: 500))
    }

    func testInvalidSourceDatesCalibrationAndCoverageAreRejected() throws {
        for source in ["", "  ", " owned-whoop-4"] {
            XCTAssertThrowsError(try Validation.Trial(sourceDeviceId: source, startedAt: start, calibration: calibration()))
        }
        for date in [Date(timeIntervalSince1970: .nan), .init(timeIntervalSince1970: .infinity),
                     .init(timeIntervalSince1970: -1), .init(timeIntervalSince1970: Double(Int.max))] {
            XCTAssertThrowsError(try Validation.Trial(sourceDeviceId: "owned-whoop-4", startedAt: date, calibration: calibration()))
        }
        for coefficient in [0, -1, .nan, .infinity] { XCTAssertThrowsError(try calibration(coefficient)) }
        XCTAssertThrowsError(try Validation.CalibrationSnapshot(coefficient: 10, sampleDays: -1, confidence: 0.5, manual: false))
        XCTAssertThrowsError(try Validation.CalibrationSnapshot(coefficient: 10, sampleDays: 3, confidence: .nan, manual: false))
        XCTAssertThrowsError(try policy(gap: 0))
        XCTAssertThrowsError(try policy(gap: .infinity))
        XCTAssertThrowsError(try policy(boundary: -1))
        XCTAssertThrowsError(try Validation.CoveragePolicy(maximumGapSeconds: 2, maximumBoundaryGapSeconds: 0, minimumUsableSamples: 1))
    }

    func testCodableRoundTripPreservesTrialFrozenCalibrationAndResult() throws {
        let walk = try trial()
        let decoded = try JSONDecoder().decode(Validation.Trial.self, from: JSONEncoder().encode(walk))
        XCTAssertEqual(decoded, walk)
        XCTAssertEqual(decoded.motionQueryBounds, walk.motionQueryBounds)
        let result = Validation.analyze(trial: decoded, gravity: motion(), coveragePolicy: try policy())
        XCTAssertEqual(try JSONDecoder().decode(Validation.Result.self, from: JSONEncoder().encode(result)), result)
    }

    func testCorruptedPersistedBoundsAndIncompleteEndStateAreRejectedBeforeDatabaseRead() throws {
        let walk = try trial()
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(walk)) as? [String: Any])
        for changes: [String: Any] in [["endedAt": original["startedAt"]!], ["endedAt": 1e100],
                                       ["startedAt": 1e100], ["countedSteps": 499],
                                       ["sourceDeviceId": "bad\nsource"], ["endedAt": NSNull()]] {
            let object = original.merging(changes) { _, changed in changed }
            XCTAssertThrowsError(try JSONDecoder().decode(Validation.Trial.self,
                from: JSONSerialization.data(withJSONObject: object)))
        }
    }
}
