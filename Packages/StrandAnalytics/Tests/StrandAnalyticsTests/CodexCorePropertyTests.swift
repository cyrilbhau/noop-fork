import XCTest
import WhoopStore
@testable import StrandAnalytics

// Independent fixed-seed generated checks. No wall clock, device data or existing fixtures.
struct CodexPropertySeed {
    var state: UInt64
    mutating func next(_ bound: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int(state % UInt64(bound))
    }
    mutating func number() -> Double {
        switch next(16) {
        case 0: return .nan
        case 1: return .infinity
        case 2: return -.infinity
        case 3: return .greatestFiniteMagnitude
        case 4: return -.greatestFiniteMagnitude
        case 5: return -0.0
        default: return Double(next(200_001) - 100_000) / 100
        }
    }
}

func codexAssertFinite(_ value: Any, file: StaticString = #filePath, line: UInt = #line) {
    if let number = value as? Double {
        XCTAssertTrue(number.isFinite, "Non-finite output: \(number)", file: file, line: line)
        return
    }
    for child in Mirror(reflecting: value).children {
        codexAssertFinite(child.value, file: file, line: line)
    }
}

final class CodexCorePropertyTests: XCTestCase {
    func testCanonicalDayRoundTripsAndWeekArithmetic() throws {
        var seed = CodexPropertySeed(state: 0xC01601)
        let span = CanonicalDay.lastDayNumber - CanonicalDay.firstDayNumber + 1
        for _ in 0..<5_000 {
            let number = CanonicalDay.firstDayNumber + seed.next(span)
            let key = try XCTUnwrap(CanonicalDay.key(dayNumber: number))
            XCTAssertEqual(CanonicalDay.number(key), number)
            XCTAssertTrue(CanonicalDay.isValid(key))
            let week = try XCTUnwrap(CanonicalDay.weekStart(containing: key))
            let distance = try XCTUnwrap(CanonicalDay.daysBetween(week, key))
            XCTAssertTrue((0...6).contains(distance))
            XCTAssertEqual(CanonicalDay.number(week)! % 7, 0)
            let offset = seed.next(731) - 365
            if let shifted = CanonicalDay.adding(offset, to: key) {
                XCTAssertEqual(CanonicalDay.daysBetween(key, shifted), offset)
                XCTAssertEqual(CanonicalDay.adding(-offset, to: shifted), key)
            }
            XCTAssertNil(CanonicalDay.number(" " + key))
            XCTAssertNil(CanonicalDay.number(key + "\n"))
        }
        for extreme in [Int.min, Int.max] {
            XCTAssertNil(CanonicalDay.key(dayNumber: extreme))
            XCTAssertNil(CanonicalDay.adding(extreme, to: "2031-01-08"))
        }
    }

    func testScorecardGeneratedInputsAreFiniteDeterministicAndUniqueDayOrderIndependent() {
        var seed = CodexPropertySeed(state: 0xC01602)
        for _ in 0..<300 {
            let readings = (0..<40).map { index in
                CutScorecardReading(day: CanonicalDay.adding(index - 39, to: "2031-03-26")!,
                                    takenAt: index, value: seed.number())
            }
            let protein = readings.map { CutScorecardProteinDay(day: $0.day, grams: seed.number()) }
            let lifts = readings.enumerated().map { index, reading in
                CutScorecardLiftObservation(day: reading.day, exercise: "fixture-\(index % 4)", weightKg: seed.number())
            }
            var parameters = CutScorecardParameters()
            parameters.proteinFloorGrams = 100
            let phase = CutScorecardPhase(name: "Fixture", startDay: "2031-01-01", targetWeightKg: 70,
                                          rateLowPercentPerWeek: 0.2, rateHighPercentPerWeek: 0.8)
            func input(_ rows: [CutScorecardReading], _ days: [CutScorecardProteinDay]) -> CutScorecardInput {
                CutScorecardInput(weights: rows, waists: [], lifts: lifts, proteinDays: days,
                                  phase: phase, parameters: parameters, today: "2031-03-26")
            }
            let result = CutScorecard.evaluate(input(readings, protein))
            codexAssertFinite(result)
            XCTAssertEqual(result, CutScorecard.evaluate(input(readings, protein)))
            // No duplicate days or instants: last-input tie rules are deliberately not exercised.
            XCTAssertEqual(result, CutScorecard.evaluate(input(readings.reversed(), protein.reversed())))
        }
    }

    func testCoachDayFormatGeneratedExtremesNeverPrintNonFiniteTokens() {
        var seed = CodexPropertySeed(state: 0xC01603)
        for _ in 0..<2_000 {
            let day = DailyMetric(day: "2031-01-08", totalSleepMin: seed.number(), efficiency: seed.number(),
                                  deepMin: seed.number(), remMin: seed.number(), lightMin: seed.number(),
                                  disturbances: nil, restingHr: nil, avgHrv: seed.number(), recovery: seed.number(),
                                  strain: seed.number(), exerciseCount: nil)
            let style = CoachDayStyle.packet(strainFactor: seed.number())
            let line = CoachDayFormat.dayLine(day, style: style)
            XCTAssertEqual(line, CoachDayFormat.dayLine(day, style: style))
            for text in [line, CoachDayFormat.primaryAveragesLine([day], style: style),
                         CoachDayFormat.vitalsAveragesLine([day])] {
                XCTAssertNil(text.range(of: #"(?i)(^|[ ,:])[-+]?(nan|inf)([ ,%]|$)"#, options: .regularExpression))
            }
        }
    }

    func testBodyRecordGeneratedComparisonsAndComponentsHaveFiniteOutputs() {
        var seed = CodexPropertySeed(state: 0xC01604)
        for _ in 0..<3_000 {
            let earlier = BodyRecordReading(value: seed.number(), decimals: seed.next(9) - 2)
            let later = BodyRecordReading(value: seed.number(), decimals: seed.next(9) - 2)
            let result = BodyRecordComparison.compare(earlier: earlier, later: later)
            codexAssertFinite(result)
            XCTAssertEqual(result, BodyRecordComparison.compare(earlier: earlier, later: later))
            if earlier.value.isFinite, later.value.isFinite,
               case .both(let forward) = result,
               case .both(let backward) = BodyRecordComparison.compare(earlier: later, later: earlier) {
                XCTAssertEqual(forward.delta, -backward.delta)
            }
            let components = BodyScanComponents(armsLean: seed.number(), armLeftLean: seed.number(),
                                               armRightLean: seed.number(), legsLean: seed.number(),
                                               legLeftLean: seed.number(), legRightLean: seed.number())
            let derived = BodyScanDerivation.derive(components)
            codexAssertFinite(derived)
            XCTAssertEqual(derived, BodyScanDerivation.derive(components))
        }
    }
}
