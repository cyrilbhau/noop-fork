import XCTest
import WhoopProtocol
@testable import StrandAnalytics

final class StepsEstimatePersistenceTests: XCTestCase {
    private let calibration = StepsEstimateEngine.Calibration(coefficient: 100, sampleDays: 3,
                                                              confidence: 0.6, manual: false)

    func testHealthReferenceDaysRetainIndependentEstimatesAlongsidePhoneFreeDays() {
        let references = ["2026-10-26": 1_000.0, "2026-10-27": 2_000.0, "2026-10-28": 3_000.0]
        let motions = ["2026-10-26": 10.0, "2026-10-27": 20.0, "2026-10-28": 30.0, "2026-10-29": 40.0]
        let points = references.map { StepsEstimateEngine.CalibrationPoint(motion: motions[$0.key]!, steps: $0.value) }
        let fit = StepsEstimateEngine.calibrate(points)
        let inputs = motions.mapValues { StepsEstimatePersistence.DayInput(owner: "strap", family: .whoop4, motion: $0) }
        let plan = StepsEstimatePersistence.plan(scoredDays: motions.keys.sorted(), inputs: inputs, calibration: fit)

        XCTAssertEqual(plan.map(\.day), motions.keys.sorted())
        XCTAssertEqual(plan.map(\.steps), [1_000, 2_000, 3_000, 4_000])
        XCTAssertEqual(Set(plan.map(\.deviceId)), ["strap-noop"])
        XCTAssertEqual(references["2026-10-26"], 1_000, "Health remains a separate unchanged reading")
    }

    func testOnlyConfirmedWhoop4OwnersProduceAttributedWrites() {
        let inputs: [String: StepsEstimatePersistence.DayInput] = [
            "four": .init(owner: "historical-strap", family: .whoop4, motion: 10),
            "five": .init(owner: "active-strap", family: .whoop5, motion: 20),
            "unknown": .init(owner: "ring-or-unknown", family: nil, motion: 30),
            "unowned": .init(owner: "", family: .whoop4, motion: 40),
            "unscored": .init(owner: "historical-strap", family: .whoop4, motion: 50),
        ]
        let plan = StepsEstimatePersistence.plan(scoredDays: ["four", "five", "unknown", "unowned"],
                                                 inputs: inputs, calibration: calibration)
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan.first?.deviceId, "historical-strap-noop")
        XCTAssertEqual(plan.first?.steps, 1_000)
    }

    func testFailedEmptyAndUncalibratedReadsPlanNoReplacementOrDeletion() {
        let inputs: [String: StepsEstimatePersistence.DayInput] = [
            "failed": .init(owner: "strap", family: .whoop4, motion: nil),
            "empty": .init(owner: "strap", family: .whoop4, motion: 0),
            "corrupt": .init(owner: "strap", family: .whoop4, motion: .nan),
        ]
        XCTAssertTrue(StepsEstimatePersistence.plan(scoredDays: inputs.keys.sorted(), inputs: inputs,
                                                   calibration: calibration).isEmpty)
        XCTAssertTrue(StepsEstimatePersistence.plan(scoredDays: ["day"], inputs: [
            "day": .init(owner: "strap", family: .whoop4, motion: 10),
        ], calibration: nil).isEmpty)
    }

    func testLaterStrapMotionRefreshesEstimateOnAReferenceDay() {
        let first = StepsEstimatePersistence.plan(scoredDays: ["reference"], inputs: [
            "reference": .init(owner: "strap", family: .whoop4, motion: 10),
        ], calibration: calibration)
        let afterPhoneFreeWalk = StepsEstimatePersistence.plan(scoredDays: ["reference"], inputs: [
            "reference": .init(owner: "strap", family: .whoop4, motion: 15),
        ], calibration: calibration)
        XCTAssertEqual(first.first?.steps, 1_000)
        XCTAssertEqual(afterPhoneFreeWalk.first?.steps, 1_500)
    }

    func testSwiftKotlinDecisionOracle() {
        let families: [DeviceFamily?] = [nil, .whoop4, .whoop5]
        let motions: [Double?] = [nil, 0, 0.5, 1, 12.345, .infinity, .greatestFiniteMagnitude,
                                  21_474_836.47, 42_949_672.96]
        let huge = StepsEstimateEngine.Calibration(coefficient: 1e308, sampleDays: 3, confidence: 0.6, manual: false)
        let corrupt = StepsEstimateEngine.Calibration(coefficient: .infinity, sampleDays: 3, confidence: 0.6, manual: false)
        var output: [String] = []
        for family in families {
            for owner in ["", "strap"] {
                for motion in motions {
                    for fit in [nil, calibration, huge, corrupt] {
                        let plan = StepsEstimatePersistence.plan(scoredDays: ["day"], inputs: [
                            "day": .init(owner: owner, family: family, motion: motion),
                        ], calibration: fit)
                        output.append(plan.first.map { "\($0.deviceId):\($0.steps)" } ?? "-")
                    }
                }
            }
        }
        // Standalone Swift oracle stdout; copied verbatim to the Kotlin twin.
        XCTAssertEqual(output.joined(separator: "|"), Self.decisionOracle)
    }

    func testInvalidCoefficientsAndFiniteOverflowAreRejectedBeforeIntegerConversion() {
        for coefficient in [Double.nan, .infinity, -.infinity, 0, -1, 1e308] {
            let invalid = StepsEstimateEngine.Calibration(coefficient: coefficient, sampleDays: 3,
                                                          confidence: 0.6, manual: false)
            XCTAssertTrue(StepsEstimatePersistence.plan(scoredDays: ["day"], inputs: [
                "day": .init(owner: "strap", family: .whoop4, motion: 10),
            ], calibration: invalid).isEmpty)
        }
        XCTAssertTrue(StepsEstimatePersistence.plan(scoredDays: ["day"], inputs: [
            "day": .init(owner: "strap", family: .whoop4, motion: 1e308),
        ], calibration: calibration).isEmpty)
    }

    func testInt32NarrowingBoundaryMatchesKotlinBeforeTheExistingClamp() {
        let fit = StepsEstimateEngine.Calibration(coefficient: 1, sampleDays: 3, confidence: 0.6, manual: false)
        func steps(_ motion: Double) -> Int? {
            StepsEstimatePersistence.plan(scoredDays: ["day"], inputs: [
                "day": .init(owner: "strap", family: .whoop4, motion: motion),
            ], calibration: fit).first?.steps
        }
        XCTAssertEqual(steps(2_147_483_647), 60_000)
        XCTAssertEqual(steps(2_147_483_647.49), 60_000)
        XCTAssertNil(steps(2_147_483_647.5))
        XCTAssertNil(steps(2_147_483_648))
        XCTAssertNil(steps(4_294_967_296))
    }

    private static let decisionOracle = "-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|strap-noop:100|-|-|-|strap-noop:1235|-|-|-|-|-|-|-|-|-|-|-|strap-noop:60000|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-|-"
}
