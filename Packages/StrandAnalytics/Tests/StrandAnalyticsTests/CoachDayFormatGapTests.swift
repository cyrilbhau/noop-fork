import XCTest
import WhoopStore
@testable import StrandAnalytics

// Tests that close gaps found by fault injection in the shared per-day formatter of stage 2
// (docs/personal/superapp/specs/stage-2.md §6.1). Each expected value is derived from the
// specification: §6 ("every function is total: it never throws and never traps") and rule F1 ("a value
// that is NaN or infinite, or whose magnitude is above 1e15, is treated as absent").
//
// Every value is synthetic and belongs to the Fixture Person of §13.

/// Gap tests for `CoachDayFormat`: the totality guards that no earlier test pinned.
final class CoachDayFormatGapTests: XCTestCase {

    private typealias F = CoachPacketFixture

    private let dash = "\u{2014}"

    /// A row carrying only the whole-number fields the averages read.
    private func wholeNumbers(_ day: String, rhr: Int?, steps: Int? = nil) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: rhr, avgHrv: nil, recovery: nil,
                    strain: nil, exerciseCount: nil, steps: steps)
    }

    /// The text after `label` up to the next ", " of an averages line.
    private func value(after label: String, in line: String) -> String {
        guard let start = line.range(of: label) else { return "<no \(label)>" }
        let rest = line[start.upperBound...]
        return String(rest.range(of: ", ").map { rest[..<$0.lowerBound] } ?? rest)
    }

    // MARK: - Fault 1: F1 on the whole-number averages

    /// A stored resting heart rate above 1e15 is absent from the average, and the average does not trap
    /// on converting its mean back to a whole number.
    func testAHugeWholeNumberRestingHeartRateIsAbsentFromTheAverageAndDoesNotTrap() {
        for huge in [Int.max, Int.min, 1_000_000_000_000_001, -1_000_000_000_000_001] {
            for style in [CoachDayStyle.coachContext, CoachDayStyle.packet(strainFactor: 0.21)] {
                let alone = CoachDayFormat.primaryAveragesLine([wholeNumbers("2031-03-03", rhr: huge)],
                                                               style: style)
                XCTAssertEqual(value(after: "RHR: ", in: alone), "\(dash) bpm", "\(huge)")
                let beside = CoachDayFormat.primaryAveragesLine(
                    [wholeNumbers("2031-03-03", rhr: huge), wholeNumbers("2031-03-04", rhr: 52)],
                    style: style)
                XCTAssertEqual(value(after: "RHR: ", in: beside), "52 bpm", "\(huge)")
            }
        }
    }

    /// F1 drops a magnitude above 1e15; the bound itself is still a value in the average.
    func testAWholeNumberOfExactlyTenToTheFifteenthIsStillAveraged() {
        let line = CoachDayFormat.primaryAveragesLine(
            [wholeNumbers("2031-03-03", rhr: 1_000_000_000_000_000)], style: .coachContext)
        XCTAssertEqual(value(after: "RHR: ", in: line), "1000000000000000 bpm")
    }

    /// The same rule on the step average of the in-app Coach's vitals line.
    func testAHugeWholeNumberStepCountIsAbsentFromTheAverageAndDoesNotTrap() {
        for huge in [Int.max, Int.min, 1_000_000_000_000_001] {
            let alone = CoachDayFormat.vitalsAveragesLine(
                [wholeNumbers("2031-03-03", rhr: nil, steps: huge)])
            XCTAssertEqual(value(after: "steps: ", in: alone), "\(dash)/day", "\(huge)")
            let beside = CoachDayFormat.vitalsAveragesLine(
                [wholeNumbers("2031-03-03", rhr: nil, steps: huge),
                 wholeNumbers("2031-03-04", rhr: nil, steps: 8000)])
            XCTAssertEqual(value(after: "steps: ", in: beside), "8000/day", "\(huge)")
        }
    }

    // MARK: - Fault 2: a strain product that is not a finite number

    /// The printed strain is `stored × strainFactor`. When that product is NaN, infinite or above 1e15
    /// the field is the dash, and every other field of the line is untouched.
    func testAStrainProductThatIsNotFinitePrintsTheDashInTheDayLine() {
        let day = F.days[0]     // 2031-03-03, stored strain 47
        for factor in [Double.nan, .infinity, -.infinity, 1e300, -1e300] {
            let style = CoachDayStyle.packet(strainFactor: factor)
            XCTAssertEqual(
                CoachDayFormat.dayLine(day, style: style),
                "2031-03-03: recovery 62, strain \(dash), sleep 7.4h, deep 1.3h, REM 1.7h, light 4.4h, "
                    + "eff 91%, HRV 58ms, RHR 54bpm", "\(factor)")
            let fields = CoachDayFormat.fields(day, style: style)
            XCTAssertEqual(fields.count, 9, "\(factor)")
            XCTAssertEqual(fields.count > 1 ? fields[1] : "", "strain \(dash)", "\(factor)")
        }
    }

    /// The strain average is the mean of the products, so a product that is not finite leaves the
    /// average with nothing to average.
    func testAStrainProductThatIsNotFiniteIsAbsentFromTheAverage() {
        for factor in [Double.nan, .infinity, -.infinity, 1e300] {
            XCTAssertEqual(
                CoachDayFormat.primaryAveragesLine(F.days, style: .packet(strainFactor: factor)),
                "recovery: 64, strain: \(dash), sleep: 7.3h, HRV: 59 ms, RHR: 54 bpm", "\(factor)")
        }
    }
}
