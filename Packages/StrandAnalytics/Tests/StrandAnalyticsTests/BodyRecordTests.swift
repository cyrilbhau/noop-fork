import XCTest
@testable import StrandAnalytics

// API ASSUMED BY THESE TESTS
//
// Written before the implementation, from docs/personal/superapp/specs/stage-4.md §6.3, §7.3, §7.4
// and §7.5. No Kotlin twin, by ruling R43 of the stage 1 specification.
//
//   public enum BodyRecordMath
//       public static func displayString(_ x: Double, decimals: Int) -> String
//       public static func quantize(_ x: Double, decimals: Int) -> Double
//
//   public struct BodyRecordReading: Equatable, Sendable
//       public let value: Double
//       public let decimals: Int
//       public init(value: Double, decimals: Int)
//
//   public enum BodyRecordDirection: String, Sendable { case up, down, same }
//
//   public struct BodyRecordDelta: Equatable, Sendable        (read only; never constructed here)
//       public let earlier: Double
//       public let later: Double
//       public let delta: Double
//       public let percent: Double?
//       public let direction: BodyRecordDirection
//
//   public enum BodyRecordChange: Equatable, Sendable
//       case both(BodyRecordDelta)
//       case onlyEarlier(Double)
//       case onlyLater(Double)
//       case neither
//
//   public enum BodyRecordComparison
//       public static func compare(earlier: BodyRecordReading?,
//                                  later: BodyRecordReading?) -> BodyRecordChange
//
//   public struct BodyScanComponents: Equatable, Sendable
//       public var armsLean, armLeftLean, armRightLean, legsLean, legLeftLean, legRightLean: Double?
//       public init(armsLean: Double? = nil, armLeftLean: Double? = nil, armRightLean: Double? = nil,
//                   legsLean: Double? = nil, legLeftLean: Double? = nil, legRightLean: Double? = nil)
//
//   public enum BodyScanDerivedGap: String, Sendable { case missingComponent, invalidComponent }
//   public enum BodyScanDerivedValue: Equatable, Sendable
//       case value(Double)
//       case notAvailable(BodyScanDerivedGap)
//   public enum BodyScanComponentSource: String, Sendable { case printedTotal, sumOfSides }
//
//   public struct BodyScanDerived: Equatable, Sendable        (read only; never constructed here)
//       public let armToLegLeanPercent: BodyScanDerivedValue
//       public let armsSource: BodyScanComponentSource?
//       public let legsSource: BodyScanComponentSource?
//       public let armSideDifferencePercent: BodyScanDerivedValue
//       public let legSideDifferencePercent: BodyScanDerivedValue
//
//   public enum BodyScanDerivation
//       public static func derive(_ components: BodyScanComponents) -> BodyScanDerived
//
//   public struct BodyScanCheckInput: Equatable, Sendable
//       public var totalMass, fatMass, leanMass, boneMass, fatFreeMass, bodyFatPercent,
//                  armsLean, armLeftLean, armRightLean, legsLean, legLeftLean, legRightLean,
//                  androidFatPercent, gynoidFatPercent, androidGynoidRatio: Double?
//       public init()                                         // every field nil
//
//   public enum BodyScanCheck: String, CaseIterable, Sendable
//       case totalIsFatLeanBone, fatFreeIsLeanBone, bodyFatPercentIsFatShare,
//            armsIsLeftPlusRight, legsIsLeftPlusRight, ratioIsAndroidOverGynoid
//
//   public enum BodyScanChecks
//       public static let massToleranceKg: Double             // 0.25
//       public static let percentTolerancePoints: Double      // 0.5
//       public static let ratioTolerance: Double              // 0.02
//       public static func mismatches(_ input: BodyScanCheckInput) -> [BodyScanCheck]
//
// None of CanonicalDay, ChargeTypicalBand or ObservableDefaultsFlag is used: §6 has no day, no
// clock and no setting.

private typealias F = BodyRecordFixture

/// `BodyRecordMath`, `BodyRecordComparison`, `BodyScanDerivation` and `BodyScanChecks`: the pure
/// comparison and derived figures of a body-composition scan (stage 4 specification §7.3 to §7.5,
/// test plan §12.2, fixture §13).
final class BodyRecordTests: XCTestCase {

    // MARK: - Helpers

    /// A 64-bit linear congruential generator (Knuth's MMIX constants), written out so the same
    /// stream is reproduced on every run. Nothing here draws randomness from the system.
    private struct Generator {
        var state: UInt64
        mutating func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(state >> 33) % bound
        }
    }

    private func reading(_ value: Double, _ decimals: Int) -> BodyRecordReading {
        BodyRecordReading(value: value, decimals: decimals)
    }

    /// A zero must be a positive zero: `-0.0 == 0.0` is true, so equality alone cannot see the sign
    /// that would print as "-0.0".
    private func assertNotNegativeZero(_ x: Double, _ message: String,
                                       file: StaticString = #filePath, line: UInt = #line) {
        if x == 0 {
            XCTAssertEqual(x.sign, .plus, "negative zero: \(message)", file: file, line: line)
        }
    }

    private func assertBoth(_ change: BodyRecordChange, earlier: Double, later: Double, delta: Double,
                            percent: Double?, direction: BodyRecordDirection, _ message: String = "",
                            file: StaticString = #filePath, line: UInt = #line) {
        guard case .both(let d) = change else {
            return XCTFail("expected .both, got \(change) \(message)", file: file, line: line)
        }
        XCTAssertEqual(d.earlier, earlier, "earlier \(message)", file: file, line: line)
        XCTAssertEqual(d.later, later, "later \(message)", file: file, line: line)
        XCTAssertEqual(d.delta, delta, "delta \(message)", file: file, line: line)
        XCTAssertEqual(d.percent, percent, "percent \(message)", file: file, line: line)
        XCTAssertEqual(d.direction, direction, "direction \(message)", file: file, line: line)
        assertNotNegativeZero(d.earlier, "earlier \(message)", file: file, line: line)
        assertNotNegativeZero(d.later, "later \(message)", file: file, line: line)
        assertNotNegativeZero(d.delta, "delta \(message)", file: file, line: line)
        if let p = d.percent { assertNotNegativeZero(p, "percent \(message)", file: file, line: line) }
    }

    private func assertMatches(_ change: BodyRecordChange, _ expected: F.Expected, _ message: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        switch expected {
        case .both(let earlier, let later, let delta, let percent, let direction):
            assertBoth(change, earlier: earlier, later: later, delta: delta, percent: percent,
                       direction: direction, message, file: file, line: line)
        case .onlyEarlier(let value):
            XCTAssertEqual(change, .onlyEarlier(value), message, file: file, line: line)
        case .onlyLater(let value):
            XCTAssertEqual(change, .onlyLater(value), message, file: file, line: line)
        case .neither:
            XCTAssertEqual(change, .neither, message, file: file, line: line)
        }
    }

    private func derive(arms: Double? = nil, armLeft: Double? = nil, armRight: Double? = nil,
                        legs: Double? = nil, legLeft: Double? = nil, legRight: Double? = nil) -> BodyScanDerived {
        BodyScanDerivation.derive(BodyScanComponents(armsLean: arms, armLeftLean: armLeft, armRightLean: armRight,
                                                     legsLean: legs, legLeftLean: legLeft, legRightLean: legRight))
    }

    /// The number inside a derived value, or nil when it is not available.
    private func number(_ value: BodyScanDerivedValue) -> Double? {
        if case .value(let x) = value { return x }
        return nil
    }

    private func assertNeverANumber(_ value: BodyScanDerivedValue, _ gap: BodyScanDerivedGap, _ message: String,
                                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(value, .notAvailable(gap), message, file: file, line: line)
        XCTAssertNil(number(value), "a number was returned: \(message)", file: file, line: line)
    }

    // MARK: - Quantize and display

    func testDisplayStringZeroDecimalsRoundsHalfAwayFromZero() {
        XCTAssertEqual(BodyRecordMath.displayString(2.5, decimals: 0), "3")
        XCTAssertEqual(BodyRecordMath.displayString(-2.5, decimals: 0), "-3")
        // A half-to-even rule would give "0", "2" and "4" for the next three.
        XCTAssertEqual(BodyRecordMath.displayString(0.5, decimals: 0), "1")
        XCTAssertEqual(BodyRecordMath.displayString(1.5, decimals: 0), "2")
        XCTAssertEqual(BodyRecordMath.displayString(3.5, decimals: 0), "4")
        XCTAssertEqual(BodyRecordMath.displayString(-0.5, decimals: 0), "-1")
        XCTAssertEqual(BodyRecordMath.displayString(-1.5, decimals: 0), "-2")
        // Either side of the half.
        XCTAssertEqual(BodyRecordMath.displayString(2.49, decimals: 0), "2")
        XCTAssertEqual(BodyRecordMath.displayString(2.51, decimals: 0), "3")
        XCTAssertEqual(BodyRecordMath.displayString(-2.49, decimals: 0), "-2")
        XCTAssertEqual(BodyRecordMath.displayString(-2.51, decimals: 0), "-3")
        // Whole numbers have no separator and no group.
        XCTAssertEqual(BodyRecordMath.displayString(1900, decimals: 0), "1900")
        XCTAssertEqual(BodyRecordMath.displayString(0, decimals: 0), "0")
        XCTAssertEqual(BodyRecordMath.displayString(1_000_000, decimals: 0), "1000000")
    }

    /// One to six decimals are `String(format: "%.<n>f", x)`: a full stop, no grouping, and the
    /// format's own rounding of the binary value (a tie that is exact in binary goes to even).
    func testDisplayStringMatchesFormatForOneToThreeDecimals() {
        // By hand.
        XCTAssertEqual(BodyRecordMath.displayString(30.0, decimals: 1), "30.0")
        XCTAssertEqual(BodyRecordMath.displayString(27.36842, decimals: 1), "27.4")
        XCTAssertEqual(BodyRecordMath.displayString(-13.3333, decimals: 1), "-13.3")
        XCTAssertEqual(BodyRecordMath.displayString(3, decimals: 2), "3.00")
        XCTAssertEqual(BodyRecordMath.displayString(1.153846, decimals: 2), "1.15")
        XCTAssertEqual(BodyRecordMath.displayString(1.2, decimals: 3), "1.200")
        XCTAssertEqual(BodyRecordMath.displayString(1234.5678, decimals: 3), "1234.568")
        // Where the format differs from "multiply, round half away, divide": 0.25 and 0.125 are
        // exact in binary and go to the even digit; 0.35, 2.675 and 1.005 sit just below the half.
        XCTAssertEqual(BodyRecordMath.displayString(0.25, decimals: 1), "0.2")
        XCTAssertEqual(BodyRecordMath.displayString(0.35, decimals: 1), "0.3")
        XCTAssertEqual(BodyRecordMath.displayString(0.125, decimals: 2), "0.12")
        XCTAssertEqual(BodyRecordMath.displayString(2.675, decimals: 2), "2.67")
        XCTAssertEqual(BodyRecordMath.displayString(1.005, decimals: 2), "1.00")
        XCTAssertEqual(BodyRecordMath.displayString(0.0005, decimals: 3), "0.001")
        XCTAssertEqual(BodyRecordMath.displayString(1.0005, decimals: 3), "1.000")

        // Against the format itself, over a spread and a fixed-seed generated set.
        var values: [Double] = [0, 0.04, 0.05, 0.06, 0.15, 0.95, 0.999, 9.995, 10.04, 10.06, 99.95, 100,
                                1900.5, -0.06, -0.15, -4.25, -99.999]
        var generator = Generator(state: 0x5EED_0401)
        for _ in 0..<200 {
            values.append(Double(generator.next(2_000_001) - 1_000_000) / 997)
        }
        for x in values {
            for decimals in 1...3 {
                var expected = String(format: "%.\(decimals)f", x)
                if Double(expected) == 0, expected.hasPrefix("-") { expected.removeFirst() }
                let shown = BodyRecordMath.displayString(x, decimals: decimals)
                XCTAssertEqual(shown, expected, "\(x) at \(decimals)")
                XCTAssertFalse(shown.contains(","), "\(x) at \(decimals)")
            }
        }
    }

    /// Fault F8 at its source. A value that rounds to zero from below is shown without a minus sign.
    func testDisplayStringNeverShowsNegativeZero() {
        XCTAssertEqual(BodyRecordMath.displayString(-0.04, decimals: 1), "0.0")
        XCTAssertEqual(BodyRecordMath.displayString(-0.004, decimals: 2), "0.00")
        XCTAssertEqual(BodyRecordMath.displayString(-0.0004, decimals: 3), "0.000")
        XCTAssertEqual(BodyRecordMath.displayString(-0.4, decimals: 0), "0")
        XCTAssertEqual(BodyRecordMath.displayString(-0.0, decimals: 0), "0")
        XCTAssertEqual(BodyRecordMath.displayString(-0.0, decimals: 1), "0.0")
        XCTAssertEqual(BodyRecordMath.displayString(-0.0, decimals: 6), "0.000000")
        XCTAssertEqual(BodyRecordMath.displayString(-1e-12, decimals: 6), "0.000000")
        // Only a zero loses its sign: one step further from zero the minus stays.
        XCTAssertEqual(BodyRecordMath.displayString(-0.06, decimals: 1), "-0.1")
        XCTAssertEqual(BodyRecordMath.displayString(-0.006, decimals: 2), "-0.01")
        XCTAssertEqual(BodyRecordMath.displayString(-0.6, decimals: 0), "-1")
        XCTAssertEqual(BodyRecordMath.displayString(-0.1, decimals: 1), "-0.1")
        // And a positive value that rounds to zero is the same text.
        XCTAssertEqual(BodyRecordMath.displayString(0.04, decimals: 1), "0.0")
    }

    func testDisplayStringOfNonFiniteAndHugeIsADash() {
        let dash = "\u{2014}"
        for decimals in [0, 1, 3, 6] {
            XCTAssertEqual(BodyRecordMath.displayString(.nan, decimals: decimals), dash)
            XCTAssertEqual(BodyRecordMath.displayString(.infinity, decimals: decimals), dash)
            XCTAssertEqual(BodyRecordMath.displayString(-.infinity, decimals: decimals), dash)
            // The threshold itself, on both sides of zero, and beyond it.
            XCTAssertEqual(BodyRecordMath.displayString(1e15, decimals: decimals), dash)
            XCTAssertEqual(BodyRecordMath.displayString(-1e15, decimals: decimals), dash)
            XCTAssertEqual(BodyRecordMath.displayString(1e15 + 1, decimals: decimals), dash)
            XCTAssertEqual(BodyRecordMath.displayString(.greatestFiniteMagnitude, decimals: decimals), dash)
            XCTAssertEqual(BodyRecordMath.displayString(-.greatestFiniteMagnitude, decimals: decimals), dash)
        }
        // One whole number below the threshold is still a number.
        XCTAssertEqual(BodyRecordMath.displayString(999_999_999_999_999, decimals: 0), "999999999999999")
        XCTAssertEqual(BodyRecordMath.displayString(-999_999_999_999_999, decimals: 0), "-999999999999999")
        XCTAssertEqual(BodyRecordMath.displayString(999_999_999_999_999, decimals: 1), "999999999999999.0")
    }

    func testQuantizeIsTheNumberDisplayed() {
        XCTAssertEqual(BodyRecordMath.quantize(27.36842, decimals: 1), 27.4)
        XCTAssertEqual(BodyRecordMath.quantize(1.153846, decimals: 2), 1.15)
        XCTAssertEqual(BodyRecordMath.quantize(2.5, decimals: 0), 3)
        XCTAssertEqual(BodyRecordMath.quantize(-2.5, decimals: 0), -3)
        XCTAssertEqual(BodyRecordMath.quantize(0.25, decimals: 1), 0.2)
        XCTAssertEqual(BodyRecordMath.quantize(36.598163533012674, decimals: 0), 37)

        var values: [Double] = [0, 0.04, -0.04, 0.05, 0.25, 2.5, -2.5, 10.04, 10.06, 99.95, 1900.5, -13.3333]
        var generator = Generator(state: 0x5EED_0402)
        for _ in 0..<200 {
            values.append(Double(generator.next(2_000_001) - 1_000_000) / 997)
        }
        for x in values {
            for decimals in 0...6 {
                let q = BodyRecordMath.quantize(x, decimals: decimals)
                XCTAssertEqual(q, Double(BodyRecordMath.displayString(x, decimals: decimals)), "\(x) at \(decimals)")
                assertNotNegativeZero(q, "\(x) at \(decimals)")
                // Quantizing what is already quantized changes nothing, and so does asking twice.
                XCTAssertEqual(BodyRecordMath.quantize(q, decimals: decimals), q, "\(x) at \(decimals), twice")
                XCTAssertEqual(BodyRecordMath.quantize(x, decimals: decimals), q, "\(x) at \(decimals), again")
            }
        }

        // Never negative zero.
        XCTAssertEqual(BodyRecordMath.quantize(-0.04, decimals: 1).sign, .plus)
        XCTAssertEqual(BodyRecordMath.quantize(-0.0, decimals: 0).sign, .plus)
        XCTAssertEqual(BodyRecordMath.quantize(-0.4, decimals: 0).sign, .plus)

        // What has no display number comes back unchanged: it is not turned into zero.
        XCTAssertTrue(BodyRecordMath.quantize(.nan, decimals: 1).isNaN)
        XCTAssertEqual(BodyRecordMath.quantize(.infinity, decimals: 1), .infinity)
        XCTAssertEqual(BodyRecordMath.quantize(-.infinity, decimals: 1), -.infinity)
        XCTAssertEqual(BodyRecordMath.quantize(1e15, decimals: 1), 1e15)
        XCTAssertEqual(BodyRecordMath.quantize(-2.5e15, decimals: 0), -2.5e15)
        XCTAssertEqual(BodyRecordMath.quantize(999_999_999_999_999, decimals: 0), 999_999_999_999_999)
    }

    func testDecimalsAreClampedToZeroThroughSix() {
        // Below zero is zero decimals.
        XCTAssertEqual(BodyRecordMath.displayString(2.5, decimals: -1), "3")
        XCTAssertEqual(BodyRecordMath.displayString(2.5, decimals: -100), "3")
        XCTAssertEqual(BodyRecordMath.displayString(2.5, decimals: Int.min), "3")
        XCTAssertEqual(BodyRecordMath.quantize(2.5, decimals: -1), 3)
        // Zero and one are distinct, so the clamp is at zero and not at one.
        XCTAssertEqual(BodyRecordMath.displayString(2.5, decimals: 0), "3")
        XCTAssertEqual(BodyRecordMath.displayString(2.5, decimals: 1), "2.5")
        // Above six is six decimals.
        XCTAssertEqual(BodyRecordMath.displayString(1.23456789, decimals: 5), "1.23457")
        XCTAssertEqual(BodyRecordMath.displayString(1.23456789, decimals: 6), "1.234568")
        XCTAssertEqual(BodyRecordMath.displayString(1.23456789, decimals: 7), "1.234568")
        XCTAssertEqual(BodyRecordMath.displayString(1.23456789, decimals: 100), "1.234568")
        XCTAssertEqual(BodyRecordMath.displayString(1.23456789, decimals: Int.max), "1.234568")
        XCTAssertEqual(BodyRecordMath.quantize(1.23456789, decimals: 7), 1.234568)
    }

    // MARK: - Compare

    func testBothPresentGivesDeltaPercentAndDirection() {
        // 95.0 - 100.0 = -5.0; -5.0 / 100.0 × 100 = -5.0.
        assertBoth(BodyRecordComparison.compare(earlier: reading(100.0, 1), later: reading(95.0, 1)),
                   earlier: 100.0, later: 95.0, delta: -5.0, percent: -5.0, direction: .down)
        // 10.40 - 10.00 = 0.40; 0.40 / 10.00 × 100 = 4.0.
        assertBoth(BodyRecordComparison.compare(earlier: reading(10.0, 2), later: reading(10.4, 2)),
                   earlier: 10.0, later: 10.4, delta: 0.4, percent: 4.0, direction: .up)
        // 800 - 1000 = -200; -20.0 %.
        assertBoth(BodyRecordComparison.compare(earlier: reading(1000, 0), later: reading(800, 0)),
                   earlier: 1000, later: 800, delta: -200, percent: -20.0, direction: .down)
        // The percent has one decimal whatever the field's decimals: -4.0 / 30.0 × 100 = -13.33…
        assertBoth(BodyRecordComparison.compare(earlier: reading(30.0, 1), later: reading(26.0, 1)),
                   earlier: 30.0, later: 26.0, delta: -4.0, percent: -13.3, direction: .down)
        assertBoth(BodyRecordComparison.compare(earlier: reading(30, 0), later: reading(26, 0)),
                   earlier: 30, later: 26, delta: -4, percent: -13.3, direction: .down)
        // One quantum either way from "same" is a direction.
        assertBoth(BodyRecordComparison.compare(earlier: reading(5.0, 1), later: reading(5.1, 1)),
                   earlier: 5.0, later: 5.1, delta: 0.1, percent: 2.0, direction: .up)
        assertBoth(BodyRecordComparison.compare(earlier: reading(5.0, 1), later: reading(4.9, 1)),
                   earlier: 5.0, later: 4.9, delta: -0.1, percent: -2.0, direction: .down)
    }

    func testOnlyEarlier() {
        XCTAssertEqual(BodyRecordComparison.compare(earlier: reading(1.2, 3), later: nil), .onlyEarlier(1.2))
        // The value carried is the displayed one.
        XCTAssertEqual(BodyRecordComparison.compare(earlier: reading(1.2004, 3), later: nil), .onlyEarlier(1.2))
        XCTAssertEqual(BodyRecordComparison.compare(earlier: reading(0.44, 1), later: nil), .onlyEarlier(0.4))
        XCTAssertEqual(BodyRecordComparison.compare(earlier: reading(2.5, 0), later: nil), .onlyEarlier(3))
        // A measured zero is a value, not an absence.
        XCTAssertEqual(BodyRecordComparison.compare(earlier: reading(0, 0), later: nil), .onlyEarlier(0))
        guard case .onlyEarlier(let q) = BodyRecordComparison.compare(earlier: reading(-0.04, 1), later: nil) else {
            return XCTFail("expected .onlyEarlier")
        }
        XCTAssertEqual(q, 0)
        XCTAssertEqual(q.sign, .plus)
    }

    func testOnlyLater() {
        XCTAssertEqual(BodyRecordComparison.compare(earlier: nil, later: reading(80, 0)), .onlyLater(80))
        XCTAssertEqual(BodyRecordComparison.compare(earlier: nil, later: reading(80.4, 0)), .onlyLater(80))
        XCTAssertEqual(BodyRecordComparison.compare(earlier: nil, later: reading(1.153846, 2)), .onlyLater(1.15))
        XCTAssertEqual(BodyRecordComparison.compare(earlier: nil, later: reading(0, 0)), .onlyLater(0))
        // Never the other case, and never a delta against an invented zero.
        XCTAssertNotEqual(BodyRecordComparison.compare(earlier: nil, later: reading(80, 0)), .onlyEarlier(80))
        if case .both = BodyRecordComparison.compare(earlier: nil, later: reading(80, 0)) {
            XCTFail("an absent earlier reading was compared as if it were a number")
        }
    }

    func testNeither() {
        XCTAssertEqual(BodyRecordComparison.compare(earlier: nil, later: nil), .neither)
        // Bone mineral density from scan B to scan C: neither report printed it.
        XCTAssertEqual(BodyRecordComparison.compare(earlier: F.reading(F.scanB, "scan_bmd"),
                                                    later: F.reading(F.scanC, "scan_bmd")), .neither)
    }

    /// Fault F8. "No change" is a positive zero with direction `same`, and so is every other zero the
    /// comparison can produce. A negative zero would be printed as "-0.0" and read as a loss.
    func testNoChangeIsSameWithPositiveZeroDelta() {
        assertBoth(BodyRecordComparison.compare(earlier: reading(3.0, 2), later: reading(3.0, 2)),
                   earlier: 3.0, later: 3.0, delta: 0, percent: 0, direction: .same)
        // Two raw values that are displayed alike have not changed, whichever is the larger.
        assertBoth(BodyRecordComparison.compare(earlier: reading(3.004, 2), later: reading(2.996, 2)),
                   earlier: 3.0, later: 3.0, delta: 0, percent: 0, direction: .same)
        assertBoth(BodyRecordComparison.compare(earlier: reading(2.996, 2), later: reading(3.004, 2)),
                   earlier: 3.0, later: 3.0, delta: 0, percent: 0, direction: .same)
        // Readings displayed as zero are positive zero themselves.
        assertBoth(BodyRecordComparison.compare(earlier: reading(-0.04, 1), later: reading(-0.01, 1)),
                   earlier: 0, later: 0, delta: 0, percent: nil, direction: .same)
        // A real but tiny loss: -0.01 / 100000 × 100 = -0.00001 %, shown as 0.0. The percent is a
        // positive zero while the delta keeps its direction.
        assertBoth(BodyRecordComparison.compare(earlier: reading(100_000, 2), later: reading(99_999.99, 2)),
                   earlier: 100_000, later: 99_999.99, delta: -0.01, percent: 0, direction: .down)
        // The function everything above goes through.
        XCTAssertEqual(BodyRecordMath.quantize(-0.00001, decimals: 1).sign, .plus)
        XCTAssertEqual(BodyRecordMath.displayString(-0.00001, decimals: 1), "0.0")
    }

    /// Fault F5. The owner checks the comparison against the two numbers on the screen, so the
    /// change is the difference of the displayed values, not of the raw ones.
    func testDeltaIsComputedFromDisplayedValues() {
        // Shown as 10.0 and 10.1: the change is 0.1. The raw difference, 0.02, would show as 0.0.
        assertBoth(BodyRecordComparison.compare(earlier: reading(10.04, 1), later: reading(10.06, 1)),
                   earlier: 10.0, later: 10.1, delta: 0.1, percent: 1.0, direction: .up)
        // Shown as 10.1 and 10.1: no change. The raw difference, 0.08, would show as 0.1.
        assertBoth(BodyRecordComparison.compare(earlier: reading(10.06, 1), later: reading(10.14, 1)),
                   earlier: 10.1, later: 10.1, delta: 0, percent: 0, direction: .same)
        // The same going down.
        assertBoth(BodyRecordComparison.compare(earlier: reading(10.06, 1), later: reading(10.04, 1)),
                   earlier: 10.1, later: 10.0, delta: -0.1, percent: -1.0, direction: .down)
        // Whole numbers: 1000.4 and 999.6 show as 1000 and 1000.
        assertBoth(BodyRecordComparison.compare(earlier: reading(1000.4, 0), later: reading(999.6, 0)),
                   earlier: 1000, later: 1000, delta: 0, percent: 0, direction: .same)
        // The percent is taken from the displayed delta and the displayed earlier value:
        // 0.1 / 10.0 × 100 = 1.0, where the raw values would give 0.2.
    }

    /// Fault F7. A percent of a zero or negative base is not a number the owner can read, and a
    /// division by zero must never reach the screen.
    func testPercentIsNilWhenEarlierIsZeroOrNegative() {
        assertBoth(BodyRecordComparison.compare(earlier: reading(0, 0), later: reading(5, 0)),
                   earlier: 0, later: 5, delta: 5, percent: nil, direction: .up)
        assertBoth(BodyRecordComparison.compare(earlier: reading(0, 1), later: reading(0, 1)),
                   earlier: 0, later: 0, delta: 0, percent: nil, direction: .same)
        // A T-score below zero rising above it.
        assertBoth(BodyRecordComparison.compare(earlier: reading(-0.5, 1), later: reading(0.5, 1)),
                   earlier: -0.5, later: 0.5, delta: 1.0, percent: nil, direction: .up)
        assertBoth(BodyRecordComparison.compare(earlier: reading(-1.0, 1), later: reading(-1.5, 1)),
                   earlier: -1.0, later: -1.5, delta: -0.5, percent: nil, direction: .down)

        // The boundary is the displayed earlier value. One quantum below zero: nil.
        assertBoth(BodyRecordComparison.compare(earlier: reading(-0.1, 1), later: reading(0.2, 1)),
                   earlier: -0.1, later: 0.2, delta: 0.3, percent: nil, direction: .up)
        // At zero, including a raw value that is positive but displayed as 0.0: nil.
        assertBoth(BodyRecordComparison.compare(earlier: reading(0.04, 1), later: reading(0.2, 1)),
                   earlier: 0, later: 0.2, delta: 0.2, percent: nil, direction: .up)
        // One quantum above zero: 0.1 / 0.1 × 100 = 100.0.
        assertBoth(BodyRecordComparison.compare(earlier: reading(0.1, 1), later: reading(0.2, 1)),
                   earlier: 0.1, later: 0.2, delta: 0.1, percent: 100.0, direction: .up)
        assertBoth(BodyRecordComparison.compare(earlier: reading(0.06, 1), later: reading(0.2, 1)),
                   earlier: 0.1, later: 0.2, delta: 0.1, percent: 100.0, direction: .up)
        // A zero later value is an ordinary comparison: -100 %.
        assertBoth(BodyRecordComparison.compare(earlier: reading(800, 0), later: reading(0, 0)),
                   earlier: 800, later: 0, delta: -800, percent: -100.0, direction: .down)
    }

    func testNonFiniteReadingIsTreatedAsAbsent() {
        for bad in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(BodyRecordComparison.compare(earlier: reading(bad, 1), later: reading(95.0, 1)),
                           .onlyLater(95.0), "\(bad)")
            XCTAssertEqual(BodyRecordComparison.compare(earlier: reading(100.0, 1), later: reading(bad, 1)),
                           .onlyEarlier(100.0), "\(bad)")
            XCTAssertEqual(BodyRecordComparison.compare(earlier: reading(bad, 1), later: reading(bad, 1)),
                           .neither, "\(bad)")
            XCTAssertEqual(BodyRecordComparison.compare(earlier: reading(bad, 1), later: nil), .neither, "\(bad)")
            XCTAssertEqual(BodyRecordComparison.compare(earlier: nil, later: reading(bad, 1)), .neither, "\(bad)")
        }
    }

    func testDifferentDecimalsUseTheLarger() {
        // 1.2 at one decimal against 1.15 at two: compared at two decimals, 1.15 - 1.20 = -0.05 and
        // -0.05 / 1.20 × 100 = -4.17. At one decimal 1.15 would show as 1.1 and the change as -0.1.
        assertBoth(BodyRecordComparison.compare(earlier: reading(1.2, 1), later: reading(1.15, 2)),
                   earlier: 1.2, later: 1.15, delta: -0.05, percent: -4.2, direction: .down)
        // The other way round: 0.05 / 1.15 × 100 = 4.35.
        assertBoth(BodyRecordComparison.compare(earlier: reading(1.15, 2), later: reading(1.2, 1)),
                   earlier: 1.15, later: 1.2, delta: 0.05, percent: 4.3, direction: .up)
        // A whole number against a one-decimal reading keeps the decimal.
        assertBoth(BodyRecordComparison.compare(earlier: reading(100, 0), later: reading(99.5, 1)),
                   earlier: 100, later: 99.5, delta: -0.5, percent: -0.5, direction: .down)
    }

    /// Faults F6 (earlier and later swapped) and F5, over every row of §13.3.
    func testFixtureScanAToScanBTable() {
        XCTAssertEqual(F.expectedAToB.count, F.fields.count, "every numeric field has a row")
        XCTAssertEqual(F.expectedAToB.map(\.key), F.fields.map(\.key))
        for (key, expected) in F.expectedAToB {
            let change = BodyRecordComparison.compare(earlier: F.reading(F.scanA, key), later: F.reading(F.scanB, key))
            assertMatches(change, expected, key)
        }
        // The derived row: arms to legs, each side shown at one decimal.
        let a = BodyScanDerivation.derive(F.components(F.scanA)).armToLegLeanPercent
        let b = BodyScanDerivation.derive(F.components(F.scanB)).armToLegLeanPercent
        guard let earlier = number(a), let later = number(b) else {
            return XCTFail("arms to legs is not available for scan A (\(a)) or scan B (\(b))")
        }
        assertMatches(BodyRecordComparison.compare(earlier: reading(earlier, 1), later: reading(later, 1)),
                      F.expectedArmsToLegsAToB, "arms to legs")
    }

    /// Fault F6 from the other side: compared in the wrong order, every change has the opposite
    /// sign and direction, and a field only one scan has moves to the other case.
    func testSwappingTheScansMirrorsEveryRow() {
        for (key, expected) in F.expectedAToB {
            let swapped = BodyRecordComparison.compare(earlier: F.reading(F.scanB, key), later: F.reading(F.scanA, key))
            switch expected {
            case .both(let earlier, let later, let delta, _, let direction):
                guard case .both(let d) = swapped else { XCTFail("\(key): \(swapped)"); continue }
                XCTAssertEqual(d.earlier, later, key)
                XCTAssertEqual(d.later, earlier, key)
                XCTAssertEqual(d.delta, -delta, key)
                assertNotNegativeZero(d.delta, key)
                let mirrored: BodyRecordDirection = direction == .up ? .down : (direction == .down ? .up : .same)
                XCTAssertEqual(d.direction, mirrored, key)
            case .onlyEarlier(let value):
                XCTAssertEqual(swapped, .onlyLater(value), key)
            case .onlyLater(let value):
                XCTAssertEqual(swapped, .onlyEarlier(value), key)
            case .neither:
                XCTAssertEqual(swapped, .neither, key)
            }
        }
    }

    /// Generated pairs (fixed seed): the result is a calculation on the displayed numbers, it is the
    /// same on every call, and nothing in it is non-finite or a negative zero.
    func testCompareHoldsItsInvariantsForGeneratedReadings() {
        var generator = Generator(state: 0x5EED_0403)
        func generated() -> BodyRecordReading? {
            switch generator.next(12) {
            case 0: return nil
            case 1: return reading([Double.nan, .infinity, -.infinity][generator.next(3)], generator.next(4))
            default:
                // Up to four raw decimals, between -500 and 2500, displayed at 0 to 3 decimals.
                return reading(Double(generator.next(30_000_001) - 5_000_000) / 10_000, generator.next(4))
            }
        }
        var bothSeen = 0
        for index in 0..<3_000 {
            let earlier = generated(), later = generated()
            let label = "case \(index): \(String(describing: earlier)) to \(String(describing: later))"
            let change = BodyRecordComparison.compare(earlier: earlier, later: later)
            XCTAssertEqual(BodyRecordComparison.compare(earlier: earlier, later: later), change, label)

            let present: (BodyRecordReading?) -> BodyRecordReading? = { $0.flatMap { $0.value.isFinite ? $0 : nil } }
            switch (present(earlier), present(later)) {
            case (nil, nil):
                XCTAssertEqual(change, .neither, label)
            case (let e?, nil):
                XCTAssertEqual(change, .onlyEarlier(BodyRecordMath.quantize(e.value, decimals: e.decimals)), label)
            case (nil, let l?):
                XCTAssertEqual(change, .onlyLater(BodyRecordMath.quantize(l.value, decimals: l.decimals)), label)
            case (let e?, let l?):
                bothSeen += 1
                let d = max(e.decimals, l.decimals)
                let a = BodyRecordMath.quantize(e.value, decimals: d)
                let b = BodyRecordMath.quantize(l.value, decimals: d)
                guard case .both(let delta) = change else { XCTFail("\(label): \(change)"); continue }
                XCTAssertEqual(delta.earlier, a, label)
                XCTAssertEqual(delta.later, b, label)
                XCTAssertEqual(delta.delta, BodyRecordMath.quantize(b - a, decimals: d), label)
                XCTAssertTrue(delta.delta.isFinite, label)
                assertNotNegativeZero(delta.delta, label)
                XCTAssertEqual(delta.direction, delta.delta > 0 ? .up : (delta.delta < 0 ? .down : .same), label)
                // A direction other than `same` exactly when the two displayed numbers differ.
                XCTAssertEqual(delta.direction == .same, a == b, label)
                if a > 0 {
                    XCTAssertEqual(delta.percent, BodyRecordMath.quantize(delta.delta / a * 100, decimals: 1), label)
                    XCTAssertEqual(delta.percent?.isFinite, true, label)
                    if let p = delta.percent { assertNotNegativeZero(p, label) }
                } else {
                    XCTAssertNil(delta.percent, label)
                }
                // Swapping the readings negates the change.
                guard case .both(let back) = BodyRecordComparison.compare(earlier: later, later: earlier) else {
                    XCTFail("\(label): swapped is not .both"); continue
                }
                XCTAssertEqual(back.delta, -delta.delta, label)
                assertNotNegativeZero(back.delta, label)
            }
        }
        XCTAssertGreaterThan(bothSeen, 2_000, "the generator must exercise the both-present path")
    }

    // MARK: - Derive

    func testRatioFromPrintedTotals() {
        // 10 / 20 × 100 = 50.0.
        let d = derive(arms: 10.0, legs: 20.0)
        XCTAssertEqual(d.armToLegLeanPercent, .value(50.0))
        XCTAssertEqual(d.armsSource, .printedTotal)
        XCTAssertEqual(d.legsSource, .printedTotal)
        // One decimal: 10.4 / 19.6 × 100 = 53.06… shows as 53.1.
        XCTAssertEqual(derive(arms: 10.4, legs: 19.6).armToLegLeanPercent, .value(53.1))
        // Arms over legs, not legs over arms (which would be 200.0).
        XCTAssertNotEqual(d.armToLegLeanPercent, .value(200.0))
    }

    func testRatioFromSidesWhenTotalIsAbsent() {
        // Scan C: (5.3 + 5.3) / 19.5 × 100 = 54.36 shows as 54.4.
        let c = derive(armLeft: 5.3, armRight: 5.3, legs: 19.5)
        XCTAssertEqual(c.armToLegLeanPercent, .value(54.4))
        XCTAssertEqual(c.armsSource, .sumOfSides)
        XCTAssertEqual(c.legsSource, .printedTotal)
        // Legs from sides, arms printed: 10 / (10 + 10) × 100 = 50.0.
        let legs = derive(arms: 10.0, legLeft: 10.0, legRight: 10.0)
        XCTAssertEqual(legs.armToLegLeanPercent, .value(50.0))
        XCTAssertEqual(legs.armsSource, .printedTotal)
        XCTAssertEqual(legs.legsSource, .sumOfSides)
        // Both from sides: (5 + 5) / (10 + 10) × 100 = 50.0.
        let both = derive(armLeft: 5.0, armRight: 5.0, legLeft: 10.0, legRight: 10.0)
        XCTAssertEqual(both.armToLegLeanPercent, .value(50.0))
        XCTAssertEqual(both.armsSource, .sumOfSides)
        XCTAssertEqual(both.legsSource, .sumOfSides)
    }

    /// Fault F3. A report's printed total is the authority; the sides are summed only when no total
    /// was entered. Here the sides add up to 10.2, which would give 51.0.
    func testPrintedTotalWinsOverSides() {
        let d = derive(arms: 10.0, armLeft: 4.9, armRight: 5.3, legs: 20.0)
        XCTAssertEqual(d.armToLegLeanPercent, .value(50.0))
        XCTAssertNotEqual(d.armToLegLeanPercent, .value(51.0))
        XCTAssertEqual(d.armsSource, .printedTotal)
        // The same for legs: sides add up to 25, which would give 40.0.
        let legs = derive(arms: 10.0, legs: 20.0, legLeft: 12.0, legRight: 13.0)
        XCTAssertEqual(legs.armToLegLeanPercent, .value(50.0))
        XCTAssertEqual(legs.legsSource, .printedTotal)
        // A usable printed total is used even when a side beside it is not usable: the side
        // difference is unavailable, the ratio is not.
        let oddSide = derive(arms: 10.0, armLeft: -1.0, armRight: 5.0, legs: 20.0)
        XCTAssertEqual(oddSide.armToLegLeanPercent, .value(50.0))
        XCTAssertEqual(oddSide.armsSource, .printedTotal)
        assertNeverANumber(oddSide.armSideDifferencePercent, .invalidComponent, "arm side of -1")
    }

    /// Fault F1. "Not entered" is never zero: with no arms figure the ratio is not 0.0 %.
    func testMissingArmsIsNotAvailableNeverZero() {
        let d = derive(legs: 20.0)
        assertNeverANumber(d.armToLegLeanPercent, .missingComponent, "no arms figure")
        XCTAssertNotEqual(d.armToLegLeanPercent, .value(0))
        XCTAssertNil(d.armsSource)
        XCTAssertEqual(d.legsSource, .printedTotal)
        // Leg sides in place of the legs total change nothing about the missing arms.
        let fromSides = derive(legLeft: 10.0, legRight: 10.0)
        assertNeverANumber(fromSides.armToLegLeanPercent, .missingComponent, "no arms figure, legs from sides")
        XCTAssertNil(fromSides.armsSource)
        XCTAssertEqual(fromSides.legsSource, .sumOfSides)
        // Nothing entered at all.
        let empty = BodyScanDerivation.derive(BodyScanComponents())
        assertNeverANumber(empty.armToLegLeanPercent, .missingComponent, "empty scan")
        assertNeverANumber(empty.armSideDifferencePercent, .missingComponent, "empty scan")
        assertNeverANumber(empty.legSideDifferencePercent, .missingComponent, "empty scan")
        XCTAssertNil(empty.armsSource)
        XCTAssertNil(empty.legsSource)
    }

    func testMissingLegsIsNotAvailableNeverInfinity() {
        let d = derive(arms: 10.0)
        assertNeverANumber(d.armToLegLeanPercent, .missingComponent, "no legs figure")
        XCTAssertEqual(d.armsSource, .printedTotal)
        XCTAssertNil(d.legsSource)
        // Fixture: scan A with its legs total removed and no leg sides (§13.2).
        var a = F.components(F.scanA)
        a.legsLean = nil
        a.legLeftLean = nil
        a.legRightLean = nil
        let derived = BodyScanDerivation.derive(a)
        assertNeverANumber(derived.armToLegLeanPercent, .missingComponent, "scan A without legs")
        assertNeverANumber(derived.legSideDifferencePercent, .missingComponent, "scan A without legs")
        XCTAssertNil(derived.legsSource)
    }

    /// Fault F2. A typed zero for the legs total is not a number to divide by.
    func testZeroLegsIsInvalidNotInfinity() {
        let d = derive(arms: 10.0, legs: 0)
        assertNeverANumber(d.armToLegLeanPercent, .invalidComponent, "legs total of 0")
        XCTAssertNil(d.legsSource)
        XCTAssertEqual(d.armsSource, .printedTotal)
        assertNeverANumber(derive(arms: 10.0, legs: -0.0).armToLegLeanPercent, .invalidComponent, "legs of -0")
        // A printed zero is not replaced by the sum of usable sides: the entry is wrong, not absent.
        let withSides = derive(arms: 10.0, legs: 0, legLeft: 10.0, legRight: 10.0)
        assertNeverANumber(withSides.armToLegLeanPercent, .invalidComponent, "legs total of 0 beside usable sides")
        XCTAssertNil(withSides.legsSource)
        // Fixture: scan A with legs total set to 0 (§13.2).
        var a = F.components(F.scanA)
        a.legsLean = 0
        assertNeverANumber(BodyScanDerivation.derive(a).armToLegLeanPercent, .invalidComponent, "scan A, legs 0")

        // The boundary of "usable" is strictly greater than zero. Just above it the ratio is a
        // number: 10 / 0.01 × 100 = 100000.0.
        XCTAssertEqual(derive(arms: 10.0, legs: 0.01).armToLegLeanPercent, .value(100_000.0))
        // Just below it, it is invalid.
        assertNeverANumber(derive(arms: 10.0, legs: -0.01).armToLegLeanPercent, .invalidComponent, "legs of -0.01")
        // A positive value so small that the quotient overflows is invalid, never infinity.
        assertNeverANumber(derive(arms: 10.0, legs: .leastNonzeroMagnitude).armToLegLeanPercent,
                           .invalidComponent, "legs of the smallest positive number")
        // A zero arms figure is invalid as well: it is not a 0.0 % ratio.
        assertNeverANumber(derive(arms: 0, legs: 20.0).armToLegLeanPercent, .invalidComponent, "arms total of 0")
    }

    func testNegativeOrNonFiniteComponentIsInvalid() {
        for bad in [-1.0, -0.01, 0, Double.nan, .infinity, -.infinity] {
            // As a printed total.
            assertNeverANumber(derive(arms: bad, legs: 20.0).armToLegLeanPercent, .invalidComponent, "arms \(bad)")
            assertNeverANumber(derive(arms: 10.0, legs: bad).armToLegLeanPercent, .invalidComponent, "legs \(bad)")
            XCTAssertNil(derive(arms: bad, legs: 20.0).armsSource, "arms \(bad)")
            // As a side, with no printed total to fall back on.
            assertNeverANumber(derive(armLeft: bad, armRight: 5.0, legs: 20.0).armToLegLeanPercent,
                               .invalidComponent, "left arm \(bad)")
            assertNeverANumber(derive(armLeft: 5.0, armRight: bad, legs: 20.0).armToLegLeanPercent,
                               .invalidComponent, "right arm \(bad)")
            assertNeverANumber(derive(arms: 10.0, legLeft: bad, legRight: 10.0).armToLegLeanPercent,
                               .invalidComponent, "left leg \(bad)")
            // A lone unusable side is invalid, not missing.
            assertNeverANumber(derive(armLeft: bad, legs: 20.0).armToLegLeanPercent,
                               .invalidComponent, "only a left arm of \(bad)")
            // In the side differences.
            assertNeverANumber(derive(armLeft: bad, armRight: 5.0).armSideDifferencePercent,
                               .invalidComponent, "left arm \(bad)")
            assertNeverANumber(derive(armLeft: 5.0, armRight: bad).armSideDifferencePercent,
                               .invalidComponent, "right arm \(bad)")
            assertNeverANumber(derive(legLeft: bad, legRight: 10.0).legSideDifferencePercent,
                               .invalidComponent, "left leg \(bad)")
            assertNeverANumber(derive(legLeft: 10.0, legRight: bad).legSideDifferencePercent,
                               .invalidComponent, "right leg \(bad)")
        }
    }

    func testInvalidOutranksMissing() {
        // Arms missing, legs invalid.
        assertNeverANumber(derive(legs: 0).armToLegLeanPercent, .invalidComponent, "arms missing, legs 0")
        // Arms invalid, legs missing.
        assertNeverANumber(derive(arms: -1.0).armToLegLeanPercent, .invalidComponent, "arms -1, legs missing")
        assertNeverANumber(derive(arms: .nan).armToLegLeanPercent, .invalidComponent, "arms NaN, legs missing")
        // One arm side alone (missing) beside an invalid legs side.
        assertNeverANumber(derive(armLeft: 5.0, legLeft: -2.0, legRight: 10.0).armToLegLeanPercent,
                           .invalidComponent, "one arm side, a leg side of -2")
        // In a side difference: one side invalid and the other not entered.
        assertNeverANumber(derive(armLeft: 0).armSideDifferencePercent, .invalidComponent, "left 0, right missing")
        assertNeverANumber(derive(armRight: .infinity).armSideDifferencePercent,
                           .invalidComponent, "left missing, right infinite")
        assertNeverANumber(derive(legRight: -1.0).legSideDifferencePercent, .invalidComponent, "left missing, right -1")
    }

    func testOneSideAloneIsMissing() {
        let left = derive(armLeft: 5.0, legs: 20.0)
        assertNeverANumber(left.armToLegLeanPercent, .missingComponent, "left arm only")
        XCTAssertNil(left.armsSource)
        let right = derive(armRight: 5.0, legs: 20.0)
        assertNeverANumber(right.armToLegLeanPercent, .missingComponent, "right arm only")
        XCTAssertNil(right.armsSource)
        // One side is never doubled and never used as the total: neither 25.0 nor 50.0.
        XCTAssertNotEqual(left.armToLegLeanPercent, .value(25.0))
        XCTAssertNotEqual(left.armToLegLeanPercent, .value(50.0))
        let leg = derive(arms: 10.0, legLeft: 10.0)
        assertNeverANumber(leg.armToLegLeanPercent, .missingComponent, "left leg only")
        XCTAssertNil(leg.legsSource)
    }

    func testSideDifferenceSignAndMagnitude() {
        // Scan A: (4.9 - 5.1) / 5.1 × 100 = -3.92: the right arm is larger.
        XCTAssertEqual(derive(armLeft: 4.9, armRight: 5.1).armSideDifferencePercent, .value(-3.9))
        // Mirrored: (5.1 - 4.9) / 5.1 × 100 = +3.92: the left arm is larger. The divisor is the
        // larger side either way, so the magnitude is the same.
        XCTAssertEqual(derive(armLeft: 5.1, armRight: 4.9).armSideDifferencePercent, .value(3.9))
        // Legs: (9.0 - 10.0) / 10.0 × 100 = -10.0, and +10.0 mirrored. Dividing by the smaller side
        // would give 11.1; by the mean, 10.5.
        XCTAssertEqual(derive(legLeft: 9.0, legRight: 10.0).legSideDifferencePercent, .value(-10.0))
        XCTAssertEqual(derive(legLeft: 10.0, legRight: 9.0).legSideDifferencePercent, .value(10.0))
        // Arms and legs do not leak into each other.
        let d = derive(armLeft: 4.9, armRight: 5.1, legLeft: 10.0, legRight: 9.0)
        XCTAssertEqual(d.armSideDifferencePercent, .value(-3.9))
        XCTAssertEqual(d.legSideDifferencePercent, .value(10.0))
        // A printed total takes no part in a side difference.
        XCTAssertEqual(derive(arms: 99.0, armLeft: 4.9, armRight: 5.1).armSideDifferencePercent, .value(-3.9))
    }

    func testEqualSidesGiveZeroNotNegativeZero() {
        for value in [derive(armLeft: 5.2, armRight: 5.2).armSideDifferencePercent,
                      derive(legLeft: 10.0, legRight: 10.0).legSideDifferencePercent,
                      // (5.0 - 5.0001) / 5.0001 × 100 = -0.002, shown as 0.0 and not as -0.0.
                      derive(armLeft: 5.0, armRight: 5.0001).armSideDifferencePercent,
                      derive(legLeft: 10.0, legRight: 10.0004).legSideDifferencePercent] {
            XCTAssertEqual(value, .value(0))
            XCTAssertEqual(number(value)?.sign, .plus, "the zero is a negative zero")
        }
    }

    func testSideDifferenceNeedsBothSides() {
        assertNeverANumber(derive(armLeft: 5.0).armSideDifferencePercent, .missingComponent, "left arm only")
        assertNeverANumber(derive(armRight: 5.0).armSideDifferencePercent, .missingComponent, "right arm only")
        assertNeverANumber(derive(legLeft: 10.0).legSideDifferencePercent, .missingComponent, "left leg only")
        assertNeverANumber(derive(legRight: 10.0).legSideDifferencePercent, .missingComponent, "right leg only")
        // A lone side is not compared with zero: neither 100.0 nor -100.0.
        XCTAssertNotEqual(derive(armLeft: 5.0).armSideDifferencePercent, .value(100.0))
        XCTAssertNotEqual(derive(armRight: 5.0).armSideDifferencePercent, .value(-100.0))
        // A printed total does not stand in for a side.
        assertNeverANumber(derive(arms: 10.0, armLeft: 5.0).armSideDifferencePercent,
                           .missingComponent, "total and left arm only")
        assertNeverANumber(derive(arms: 10.0).armSideDifferencePercent, .missingComponent, "total only")
        // Arm sides say nothing about legs.
        assertNeverANumber(derive(armLeft: 5.0, armRight: 5.0).legSideDifferencePercent,
                           .missingComponent, "arm sides only")
    }

    /// Fault F4 (ratio inverted) and the table of §13.2.
    func testFixtureDerivedValuesForScansABAndC() {
        let a = BodyScanDerivation.derive(F.components(F.scanA))
        XCTAssertEqual(a.armToLegLeanPercent, .value(50.0))
        XCTAssertEqual(a.armsSource, .printedTotal)
        XCTAssertEqual(a.legsSource, .printedTotal)
        XCTAssertEqual(a.armSideDifferencePercent, .value(-3.9))
        XCTAssertEqual(a.legSideDifferencePercent, .value(0.0))
        XCTAssertEqual(number(a.legSideDifferencePercent)?.sign, .plus)
        XCTAssertNotEqual(a.armToLegLeanPercent, .value(200.0), "legs over arms")

        let b = BodyScanDerivation.derive(F.components(F.scanB))
        XCTAssertEqual(b.armToLegLeanPercent, .value(53.1))
        XCTAssertEqual(b.armsSource, .printedTotal)
        XCTAssertEqual(b.legsSource, .printedTotal)
        XCTAssertEqual(b.armSideDifferencePercent, .value(0.0))
        XCTAssertEqual(b.legSideDifferencePercent, .value(0.0))

        let c = BodyScanDerivation.derive(F.components(F.scanC))
        XCTAssertEqual(c.armToLegLeanPercent, .value(54.4))
        XCTAssertEqual(c.armsSource, .sumOfSides)
        XCTAssertEqual(c.legsSource, .printedTotal)
        XCTAssertEqual(c.armSideDifferencePercent, .value(0.0))
        assertNeverANumber(c.legSideDifferencePercent, .missingComponent, "scan C has no leg sides")

        // Scan A with its legs total removed: the leg sides, 10.00 + 10.00, stand in for it.
        var fromSides = F.components(F.scanA)
        fromSides.legsLean = nil
        let s = BodyScanDerivation.derive(fromSides)
        XCTAssertEqual(s.armToLegLeanPercent, .value(50.0))
        XCTAssertEqual(s.legsSource, .sumOfSides)

        // The same scan gives the same figures on every call.
        XCTAssertEqual(BodyScanDerivation.derive(F.components(F.scanA)), a)
        XCTAssertEqual(BodyScanDerivation.derive(F.components(F.scanC)), c)
    }

    /// Independent restatement of §7.4's classification, used only by the generated check below.
    private enum PairState { case usable, invalid, missing }

    private func isUsable(_ v: Double?) -> Bool {
        guard let v else { return false }
        return v.isFinite && v > 0
    }

    private func pairState(total: Double?, left: Double?, right: Double?) -> PairState {
        if isUsable(total) { return .usable }
        if total == nil, isUsable(left), isUsable(right) { return .usable }
        if total != nil { return .invalid }
        if (left != nil && !isUsable(left)) || (right != nil && !isUsable(right)) { return .invalid }
        return .missing
    }

    /// A generated spread (fixed seed) of every kind of component: absent, zero, negative zero,
    /// negative, ordinary, tiny, huge, infinite, NaN. No figure is ever non-finite, a figure appears
    /// only when its components are usable, and the reason given for a gap is the one §7.4 names.
    func testNoResultIsEverNonFinite() {
        let pool: [Double?] = [nil, nil, nil, 0, -0.0, -1, -0.01, 0.01, 0.5, 4.9, 5.1, 5.2, 10, 19.6, 20, 1_000,
                               .leastNonzeroMagnitude, .greatestFiniteMagnitude, .infinity, -.infinity, .nan]
        var generator = Generator(state: 0x5EED_0404)
        var valuesSeen = 0
        for index in 0..<6_000 {
            var pick: [Double?] = []
            for _ in 0..<6 { pick.append(pool[generator.next(pool.count)]) }
            let components = BodyScanComponents(armsLean: pick[0], armLeftLean: pick[1], armRightLean: pick[2],
                                                legsLean: pick[3], legLeftLean: pick[4], legRightLean: pick[5])
            let label = "case \(index): \(pick)"
            let d = BodyScanDerivation.derive(components)
            XCTAssertEqual(BodyScanDerivation.derive(components), d, "\(label): not deterministic")

            for value in [d.armToLegLeanPercent, d.armSideDifferencePercent, d.legSideDifferencePercent] {
                if let x = number(value) {
                    XCTAssertTrue(x.isFinite, "\(label): \(x)")
                    assertNotNegativeZero(x, label)
                }
            }

            // Arms to legs.
            let arms = pairState(total: pick[0], left: pick[1], right: pick[2])
            let legs = pairState(total: pick[3], left: pick[4], right: pick[5])
            if arms == .invalid || legs == .invalid {
                XCTAssertEqual(d.armToLegLeanPercent, .notAvailable(.invalidComponent), label)
            } else if arms == .missing || legs == .missing {
                XCTAssertEqual(d.armToLegLeanPercent, .notAvailable(.missingComponent), label)
            } else if number(d.armToLegLeanPercent) != nil {
                valuesSeen += 1
                XCTAssertNotNil(d.armsSource, label)
                XCTAssertNotNil(d.legsSource, label)
            } else {
                // Both pairs usable and no number: only an overflowing quotient explains it.
                XCTAssertEqual(d.armToLegLeanPercent, .notAvailable(.invalidComponent), label)
            }
            if arms != .usable { XCTAssertNil(d.armsSource, label) }
            if legs != .usable { XCTAssertNil(d.legsSource, label) }
            if isUsable(pick[0]) { XCTAssertEqual(d.armsSource, .printedTotal, label) }
            if isUsable(pick[3]) { XCTAssertEqual(d.legsSource, .printedTotal, label) }

            // Side differences.
            for (left, right, value) in [(pick[1], pick[2], d.armSideDifferencePercent),
                                         (pick[4], pick[5], d.legSideDifferencePercent)] {
                if (left != nil && !isUsable(left)) || (right != nil && !isUsable(right)) {
                    XCTAssertEqual(value, .notAvailable(.invalidComponent), label)
                } else if left == nil || right == nil {
                    XCTAssertEqual(value, .notAvailable(.missingComponent), label)
                } else if let x = number(value), let l = left, let r = right {
                    XCTAssertLessThanOrEqual(abs(x), 100, label)
                    if l > r { XCTAssertGreaterThanOrEqual(x, 0, label) }
                    if l < r { XCTAssertLessThanOrEqual(x, 0, label) }
                } else {
                    XCTFail("\(label): two usable sides gave \(value)")
                }
            }
        }
        XCTAssertGreaterThan(valuesSeen, 50, "the generator must reach the available path")
    }

    // MARK: - Checks

    /// The operands each check names (§7.5). Lean mass is optional for the body-fat check.
    private static let operands: [(check: BodyScanCheck, paths: [WritableKeyPath<BodyScanCheckInput, Double?>])] = [
        (.totalIsFatLeanBone, [\.totalMass, \.fatMass, \.leanMass, \.boneMass]),
        (.fatFreeIsLeanBone, [\.fatFreeMass, \.leanMass, \.boneMass]),
        (.bodyFatPercentIsFatShare, [\.bodyFatPercent, \.fatMass, \.totalMass]),
        (.armsIsLeftPlusRight, [\.armsLean, \.armLeftLean, \.armRightLean]),
        (.legsIsLeftPlusRight, [\.legsLean, \.legLeftLean, \.legRightLean]),
        (.ratioIsAndroidOverGynoid, [\.androidGynoidRatio, \.androidFatPercent, \.gynoidFatPercent]),
    ]

    /// An input in which every check has all its operands and none of them holds.
    private func everythingWrong() -> BodyScanCheckInput {
        var input = BodyScanCheckInput()
        input.totalMass = 100       // fat + lean + bone = 33
        input.fatMass = 10
        input.leanMass = 20
        input.boneMass = 3
        input.fatFreeMass = 50      // lean + bone = 23
        input.bodyFatPercent = 50   // 10 / 100 = 10 %, 10 / 30 = 33.3 %
        input.armsLean = 10         // 1 + 1
        input.armLeftLean = 1
        input.armRightLean = 1
        input.legsLean = 20         // 2 + 2
        input.legLeftLean = 2
        input.legRightLean = 2
        input.androidFatPercent = 30
        input.gynoidFatPercent = 30
        input.androidGynoidRatio = 2    // 30 / 30 = 1
        return input
    }

    private func input(_ build: (inout BodyScanCheckInput) -> Void) -> BodyScanCheckInput {
        var input = BodyScanCheckInput()
        build(&input)
        return input
    }

    func testTolerancesArePinned() {
        XCTAssertEqual(BodyScanChecks.massToleranceKg, 0.25)
        XCTAssertEqual(BodyScanChecks.percentTolerancePoints, 0.5)
        XCTAssertEqual(BodyScanChecks.ratioTolerance, 0.02)
        XCTAssertEqual(BodyScanCheck.allCases, [.totalIsFatLeanBone, .fatFreeIsLeanBone, .bodyFatPercentIsFatShare,
                                                .armsIsLeftPlusRight, .legsIsLeftPlusRight,
                                                .ratioIsAndroidOverGynoid])
    }

    func testConsistentFixtureScanHasNoMismatch() {
        XCTAssertEqual(BodyScanChecks.mismatches(F.checkInput(F.scanA)), [], "scan A")
        XCTAssertEqual(BodyScanChecks.mismatches(F.checkInput(F.scanB)), [], "scan B")
        XCTAssertEqual(BodyScanChecks.mismatches(F.checkInput(F.scanC)), [], "scan C")
        XCTAssertEqual(BodyScanChecks.mismatches(BodyScanCheckInput()), [], "nothing entered")
    }

    /// The variants of §13.4 that concern the checks.
    func testFixtureVariantsV3V4AndV5() {
        // V3: scan B with fat-free mass typed 96.0 (lean 66.0 + bone 3.00 = 69.0).
        var v3 = F.checkInput(F.scanB)
        v3.fatFreeMass = 96.0
        XCTAssertEqual(BodyScanChecks.mismatches(v3), [.fatFreeIsLeanBone])
        // V4: scan B with body fat typed 28.3, which is fat over fat plus lean (26 / 92 = 28.26 %).
        var v4 = F.checkInput(F.scanB)
        v4.bodyFatPercent = 28.3
        XCTAssertEqual(BodyScanChecks.mismatches(v4), [])
        // V5: scan B with body fat typed 31.0, which is neither reading (27.37 % and 28.26 %).
        var v5 = F.checkInput(F.scanB)
        v5.bodyFatPercent = 31.0
        XCTAssertEqual(BodyScanChecks.mismatches(v5), [.bodyFatPercentIsFatShare])
    }

    // In the six boundary tests below the operands are chosen so that the difference at the
    // tolerance is exact in binary (0.25, 0.5, and 0.04 - 0.02), and "just beyond" is one printed
    // quantum further (0.01). Fault F31 (a tolerance of zero) fails each "silent at it" line, and a
    // comparison flipped from > to >= fails it too.

    func testTotalIsFatLeanBoneFiresJustBeyondItsToleranceAndIsSilentAtIt() {
        // fat 30 + lean 67 + bone 3 = 100.
        func total(_ total: Double) -> [BodyScanCheck] {
            BodyScanChecks.mismatches(input { $0.totalMass = total; $0.fatMass = 30; $0.leanMass = 67; $0.boneMass = 3 })
        }
        XCTAssertEqual(total(100), [])
        XCTAssertEqual(total(100.24), [], "inside the tolerance")
        XCTAssertEqual(total(100.25), [], "at the tolerance, above")
        XCTAssertEqual(total(100.26), [.totalIsFatLeanBone], "just beyond, above")
        XCTAssertEqual(total(99.76), [], "inside the tolerance")
        XCTAssertEqual(total(99.75), [], "at the tolerance, below")
        XCTAssertEqual(total(99.74), [.totalIsFatLeanBone], "just beyond, below")
        XCTAssertEqual(total(105), [.totalIsFatLeanBone])
    }

    func testFatFreeIsLeanBoneFiresJustBeyondItsToleranceAndIsSilentAtIt() {
        // lean 67 + bone 3 = 70.
        func fatFree(_ fatFree: Double) -> [BodyScanCheck] {
            BodyScanChecks.mismatches(input { $0.fatFreeMass = fatFree; $0.leanMass = 67; $0.boneMass = 3 })
        }
        XCTAssertEqual(fatFree(70), [])
        XCTAssertEqual(fatFree(70.24), [], "inside the tolerance")
        XCTAssertEqual(fatFree(70.25), [], "at the tolerance, above")
        XCTAssertEqual(fatFree(70.26), [.fatFreeIsLeanBone], "just beyond, above")
        XCTAssertEqual(fatFree(69.75), [], "at the tolerance, below")
        XCTAssertEqual(fatFree(69.74), [.fatFreeIsLeanBone], "just beyond, below")
    }

    func testBodyFatPercentIsFatShareFiresJustBeyondItsToleranceAndIsSilentAtIt() {
        // No lean mass entered: one reading, fat 25 / total 100 = 25 %.
        func percent(_ p: Double) -> [BodyScanCheck] {
            BodyScanChecks.mismatches(input { $0.bodyFatPercent = p; $0.fatMass = 25; $0.totalMass = 100 })
        }
        XCTAssertEqual(percent(25), [])
        XCTAssertEqual(percent(25.49), [], "inside the tolerance")
        XCTAssertEqual(percent(25.5), [], "at the tolerance, above")
        XCTAssertEqual(percent(25.51), [.bodyFatPercentIsFatShare], "just beyond, above")
        XCTAssertEqual(percent(24.5), [], "at the tolerance, below")
        XCTAssertEqual(percent(24.49), [.bodyFatPercentIsFatShare], "just beyond, below")
    }

    func testArmsIsLeftPlusRightFiresJustBeyondItsToleranceAndIsSilentAtIt() {
        // left 5 + right 5 = 10.
        func arms(_ arms: Double) -> [BodyScanCheck] {
            BodyScanChecks.mismatches(input { $0.armsLean = arms; $0.armLeftLean = 5; $0.armRightLean = 5 })
        }
        XCTAssertEqual(arms(10), [])
        XCTAssertEqual(arms(10.24), [], "inside the tolerance")
        XCTAssertEqual(arms(10.25), [], "at the tolerance, above")
        XCTAssertEqual(arms(10.26), [.armsIsLeftPlusRight], "just beyond, above")
        XCTAssertEqual(arms(9.75), [], "at the tolerance, below")
        XCTAssertEqual(arms(9.74), [.armsIsLeftPlusRight], "just beyond, below")
    }

    func testLegsIsLeftPlusRightFiresJustBeyondItsToleranceAndIsSilentAtIt() {
        // left 10 + right 10 = 20.
        func legs(_ legs: Double) -> [BodyScanCheck] {
            BodyScanChecks.mismatches(input { $0.legsLean = legs; $0.legLeftLean = 10; $0.legRightLean = 10 })
        }
        XCTAssertEqual(legs(20), [])
        XCTAssertEqual(legs(20.24), [], "inside the tolerance")
        XCTAssertEqual(legs(20.25), [], "at the tolerance, above")
        XCTAssertEqual(legs(20.26), [.legsIsLeftPlusRight], "just beyond, above")
        XCTAssertEqual(legs(19.75), [], "at the tolerance, below")
        XCTAssertEqual(legs(19.74), [.legsIsLeftPlusRight], "just beyond, below")
    }

    func testRatioIsAndroidOverGynoidFiresJustBeyondItsToleranceAndIsSilentAtIt() {
        // SPEC-AMBIGUITY: §7.5 writes the test as `abs(ratio - android / gynoid) > 0.02` on doubles,
        // and 0.02 is not exact in binary. With ordinary figures the written arithmetic does not
        // give "silent at the tolerance": for android 36, gynoid 30 and a printed ratio of 1.22,
        // `abs(1.22 - 36.0 / 30.0)` is 0.020000000000000018, which is greater than 0.02 and fires.
        // This test therefore pins the boundary only where the difference is exact:
        // android 1 / gynoid 50 is the double 0.02, and the double 0.04 is exactly twice it.
        XCTAssertEqual(0.04 - 1.0 / 50.0, 0.02, "test precondition: the difference is exactly the tolerance")
        XCTAssertEqual(2.0 / 50.0 - 0.02, 0.02, "test precondition: the difference is exactly the tolerance")
        func ratio(_ ratio: Double, android: Double) -> [BodyScanCheck] {
            BodyScanChecks.mismatches(input {
                $0.androidGynoidRatio = ratio; $0.androidFatPercent = android; $0.gynoidFatPercent = 50
            })
        }
        XCTAssertEqual(ratio(0.02, android: 1), [])
        XCTAssertEqual(ratio(0.03, android: 1), [], "inside the tolerance")
        XCTAssertEqual(ratio(0.04, android: 1), [], "at the tolerance, above")
        XCTAssertEqual(ratio(0.05, android: 1), [.ratioIsAndroidOverGynoid], "just beyond, above")
        XCTAssertEqual(ratio(0.03, android: 2), [], "inside the tolerance")
        XCTAssertEqual(ratio(0.02, android: 2), [], "at the tolerance, below")
        XCTAssertEqual(ratio(0.01, android: 2), [.ratioIsAndroidOverGynoid], "just beyond, below")

        // Ordinary figures, clear of the tolerance on both sides: android 36 / gynoid 30 = 1.20.
        func printed(_ ratio: Double) -> [BodyScanCheck] {
            BodyScanChecks.mismatches(input {
                $0.androidGynoidRatio = ratio; $0.androidFatPercent = 36; $0.gynoidFatPercent = 30
            })
        }
        XCTAssertEqual(printed(1.20), [])
        XCTAssertEqual(printed(1.21), [])
        XCTAssertEqual(printed(1.19), [])
        XCTAssertEqual(printed(1.25), [.ratioIsAndroidOverGynoid])
        XCTAssertEqual(printed(1.15), [.ratioIsAndroidOverGynoid])
        // The inverse ratio, gynoid over android (0.83), does not pass.
        XCTAssertEqual(printed(0.83), [.ratioIsAndroidOverGynoid])
    }

    /// Fault F32. Reports differ on whether bone is in the denominator, so a printed body-fat
    /// percentage passes when it matches fat over total or fat over fat plus lean.
    func testBodyFatPercentAcceptsEitherDenominator() {
        // fat 25, total 100, lean 55: fat / total = 25 %, fat / (fat + lean) = 31.25 %.
        func percent(_ p: Double, lean: Double? = 55) -> [BodyScanCheck] {
            BodyScanChecks.mismatches(input {
                $0.bodyFatPercent = p; $0.fatMass = 25; $0.totalMass = 100; $0.leanMass = lean
            })
        }
        XCTAssertEqual(percent(25), [], "fat over total")
        XCTAssertEqual(percent(31.25), [], "fat over fat plus lean")
        // The tolerance applies to each reading: at it and one quantum either side.
        XCTAssertEqual(percent(25.5), [], "at the tolerance of the first reading")
        XCTAssertEqual(percent(25.51), [.bodyFatPercentIsFatShare])
        XCTAssertEqual(percent(24.5), [])
        XCTAssertEqual(percent(24.49), [.bodyFatPercentIsFatShare])
        XCTAssertEqual(percent(31.75), [], "at the tolerance of the second reading, above")
        XCTAssertEqual(percent(31.76), [.bodyFatPercentIsFatShare])
        XCTAssertEqual(percent(31.74), [])
        XCTAssertEqual(percent(30.75), [], "at the tolerance of the second reading, below")
        XCTAssertEqual(percent(30.74), [.bodyFatPercentIsFatShare])
        XCTAssertEqual(percent(30.76), [])
        // Between the two readings and near neither: a mismatch.
        XCTAssertEqual(percent(28), [.bodyFatPercentIsFatShare])

        // The second reading exists only when lean mass is usable. Without it, 31.25 % is 6.25
        // points from the only reading there is.
        XCTAssertEqual(percent(31.25, lean: nil), [.bodyFatPercentIsFatShare])
        XCTAssertEqual(percent(31.25, lean: 0), [.bodyFatPercentIsFatShare])
        XCTAssertEqual(percent(31.25, lean: -55), [.bodyFatPercentIsFatShare])
        XCTAssertEqual(percent(31.25, lean: .nan), [.bodyFatPercentIsFatShare])
        // And the first reading still passes whatever the lean mass is.
        XCTAssertEqual(percent(25, lean: nil), [])
        XCTAssertEqual(percent(25, lean: .nan), [])
    }

    /// A check speaks only when every figure it needs was entered. An empty field is "not entered",
    /// never a zero to compare against.
    func testACheckWithAMissingOperandIsSilent() {
        XCTAssertEqual(BodyScanChecks.mismatches(everythingWrong()), BodyScanCheck.allCases,
                       "test precondition: every check fires on the full input")
        for (_, paths) in Self.operands {
            for path in paths {
                var input = everythingWrong()
                input[keyPath: path] = nil
                let expected = Self.operands.filter { !$0.paths.contains(path) }.map(\.check)
                XCTAssertEqual(BodyScanChecks.mismatches(input), expected, "without \(path)")
            }
        }
        // Lean mass is optional for the body-fat check: without it the check still speaks.
        var noLean = everythingWrong()
        noLean.leanMass = nil
        XCTAssertTrue(BodyScanChecks.mismatches(noLean).contains(.bodyFatPercentIsFatShare))
        // Scan C has totals only: nothing but the total check can be evaluated, and it holds.
        var c = F.checkInput(F.scanC)
        c.totalMass = 99.0
        XCTAssertEqual(BodyScanChecks.mismatches(c), [.totalIsFatLeanBone])
    }

    /// An operand that is zero, negative or not finite is not usable, and its check is silent
    /// exactly as if the field were empty. No check divides by it.
    func testACheckWithAnUnusableOperandIsSilent() {
        for bad in [0, -0.0, -1, Double.nan, .infinity, -.infinity] {
            for (_, paths) in Self.operands {
                for path in paths {
                    var input = everythingWrong()
                    input[keyPath: path] = bad
                    let expected = Self.operands.filter { !$0.paths.contains(path) }.map(\.check)
                    XCTAssertEqual(BodyScanChecks.mismatches(input), expected, "\(path) = \(bad)")
                }
            }
        }
        // A gynoid figure of zero, in particular, is never divided by.
        XCTAssertEqual(BodyScanChecks.mismatches(input {
            $0.androidGynoidRatio = 1.2; $0.androidFatPercent = 36; $0.gynoidFatPercent = 0
        }), [])
        // A total of zero is never divided by in the body-fat check.
        XCTAssertEqual(BodyScanChecks.mismatches(input {
            $0.bodyFatPercent = 30; $0.fatMass = 30; $0.totalMass = 0
        }), [])
    }

    func testMismatchesComeInDeclarationOrder() {
        XCTAssertEqual(BodyScanChecks.mismatches(everythingWrong()),
                       [.totalIsFatLeanBone, .fatFreeIsLeanBone, .bodyFatPercentIsFatShare,
                        .armsIsLeftPlusRight, .legsIsLeftPlusRight, .ratioIsAndroidOverGynoid])
        // A subset keeps the order, whichever fields were set first.
        let subset = input {
            $0.legsLean = 20; $0.legLeftLean = 2; $0.legRightLean = 2
            $0.androidGynoidRatio = 2; $0.androidFatPercent = 30; $0.gynoidFatPercent = 30
            $0.totalMass = 100; $0.fatMass = 10; $0.leanMass = 20; $0.boneMass = 3
        }
        XCTAssertEqual(BodyScanChecks.mismatches(subset),
                       [.totalIsFatLeanBone, .legsIsLeftPlusRight, .ratioIsAndroidOverGynoid])
        // No check is reported twice.
        let all = BodyScanChecks.mismatches(everythingWrong())
        XCTAssertEqual(Set(all).count, all.count)
    }

    /// Generated scans (fixed seed) built to be consistent have no mismatch, the answer is the same
    /// on every call, and a one-kilogram slip in the total is caught by the total check alone.
    func testGeneratedConsistentScansHaveNoMismatchAndASlippedTotalIsCaught() {
        var generator = Generator(state: 0x5EED_0405)
        for index in 0..<500 {
            // Tenths of a kilogram for the masses, hundredths for the segments.
            let fat = Double(generator.next(600) + 50) / 10
            let lean = Double(generator.next(600) + 300) / 10
            let bone = Double(generator.next(40) + 15) / 10
            let armLeft = Double(generator.next(600) + 200) / 100
            let armRight = Double(generator.next(600) + 200) / 100
            let legLeft = Double(generator.next(1_200) + 600) / 100
            let legRight = Double(generator.next(1_200) + 600) / 100
            let android = Double(generator.next(400) + 100) / 10
            let gynoid = Double(generator.next(400) + 100) / 10

            var consistent = BodyScanCheckInput()
            consistent.fatMass = fat
            consistent.leanMass = lean
            consistent.boneMass = bone
            consistent.totalMass = fat + lean + bone
            consistent.fatFreeMass = lean + bone
            // Alternate between the two denominators a report may use.
            consistent.bodyFatPercent = index % 2 == 0 ? fat / (fat + lean + bone) * 100 : fat / (fat + lean) * 100
            consistent.armLeftLean = armLeft
            consistent.armRightLean = armRight
            consistent.armsLean = armLeft + armRight
            consistent.legLeftLean = legLeft
            consistent.legRightLean = legRight
            consistent.legsLean = legLeft + legRight
            consistent.androidFatPercent = android
            consistent.gynoidFatPercent = gynoid
            consistent.androidGynoidRatio = android / gynoid

            let label = "case \(index): \(consistent)"
            XCTAssertEqual(BodyScanChecks.mismatches(consistent), [], label)
            XCTAssertEqual(BodyScanChecks.mismatches(consistent), BodyScanChecks.mismatches(consistent), label)

            var slipped = consistent
            slipped.totalMass = fat + lean + bone + 1
            slipped.bodyFatPercent = nil
            XCTAssertEqual(BodyScanChecks.mismatches(slipped), [.totalIsFatLeanBone], label)

            var slippedLegs = consistent
            slippedLegs.legsLean = legLeft + legRight - 1
            XCTAssertEqual(BodyScanChecks.mismatches(slippedLegs), [.legsIsLeftPlusRight], label)
        }
    }
}
