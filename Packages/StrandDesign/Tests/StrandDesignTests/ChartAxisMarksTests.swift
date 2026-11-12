// API ASSUMED BY THESE TESTS
//
// Written from docs/personal/superapp/specs/stage-5.md §10.5, §12.2 and §12.6 (F20, F21) before any
// implementation exists.
//
//   public struct NoopChartAxisMarks: Equatable, Sendable {
//       public var fractions: [Double]          // 0...1 along the plot's x extent; ascending, distinct
//       public var accessibilityText: String?
//       public init(fractions: [Double], accessibilityText: String? = nil)
//       public static func points(covered: [Bool], accessibilityText: String? = nil) -> NoopChartAxisMarks
//       public static func bars(covered: [Bool], accessibilityText: String? = nil) -> NoopChartAxisMarks
//       public static func values(_ xs: [Double], covered: [Bool], domain: ClosedRange<Double>,
//                                 accessibilityText: String? = nil) -> NoopChartAxisMarks
//   }
//   public enum ChartAxisMarkLayout {
//       public static func offsets(_ marks: NoopChartAxisMarks, width: CGFloat, leading: CGFloat,
//                                  trailing: CGFloat, minSpacing: CGFloat) -> [CGFloat]
//   }
//
// Readings these tests rely on:
//   - an offset is measured from the row's own leading edge, so a mark at fraction f sits at
//     leading + f × (width − leading − trailing);
//   - offsets come back ascending;
//   - a `minSpacing` of zero thins nothing.
//
// `NoopChartAxisMarkRow` (the view) is not exercised here.

import XCTest
@testable import StrandDesign

/// Where the quiet event dots sit on a chart's time axis (stage-5.md §10.5).
///
/// The marks carry no text and no value: a covered position gets a dot, and dots that would crowd
/// are thinned. These tests pin the three placement rules and the properties the thinning promises.
/// The thinning algorithm itself is not specified, so only its stated properties are asserted.
final class ChartAxisMarksTests: XCTestCase {

    // MARK: Helpers

    private func assertClose(_ actual: [Double], _ expected: [Double], accuracy: Double = 1e-9,
                             _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        guard actual.count == expected.count else {
            return XCTFail("\(actual) is not \(expected) \(message)", file: file, line: line)
        }
        for (a, e) in zip(actual, expected) {
            XCTAssertEqual(a, e, accuracy: accuracy, "\(actual) is not \(expected) \(message)", file: file, line: line)
        }
    }

    private func offsets(_ marks: NoopChartAxisMarks, width: Double, leading: Double = 0,
                         trailing: Double = 0, minSpacing: Double) -> [Double] {
        ChartAxisMarkLayout.offsets(marks, width: CGFloat(width), leading: CGFloat(leading),
                                    trailing: CGFloat(trailing), minSpacing: CGFloat(minSpacing))
            .map { Double($0) }
    }

    /// `count` positions, covered exactly at the given indices.
    private func covered(_ count: Int, at indices: [Int]) -> [Bool] {
        let set = Set(indices)
        return (0..<count).map { set.contains($0) }
    }

    private func gaps(_ values: [Double]) -> [Double] {
        zip(values, values.dropFirst()).map { $1 - $0 }
    }

    /// Whether every value of `subset` is one of `all`, to within rounding.
    private func isSubset(_ subset: [Double], of all: [Double]) -> Bool {
        subset.allSatisfy { value in all.contains { abs($0 - value) < 1e-6 } }
    }

    private func contains(_ values: [Double], _ wanted: Double) -> Bool {
        values.contains { abs($0 - wanted) < 1e-6 }
    }

    /// A 64-bit linear congruential generator (Knuth's MMIX constants) with a fixed seed, written
    /// out so that every run sees the same inputs.
    private struct Generator {
        var state: UInt64
        mutating func below(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(state >> 33) % bound
        }
    }

    // MARK: - Placement

    func testPointsPlacesIndexOverCountMinusOne() {
        assertClose(NoopChartAxisMarks.points(covered: [true, true, true, true, true]).fractions,
                    [0, 0.25, 0.5, 0.75, 1])
        assertClose(NoopChartAxisMarks.points(covered: [true, false, true, true, false]).fractions,
                    [0, 0.5, 0.75])
        assertClose(NoopChartAxisMarks.points(covered: [false, false, true]).fractions, [1])
        assertClose(NoopChartAxisMarks.points(covered: [true, true]).fractions, [0, 1])
        assertClose(NoopChartAxisMarks.points(covered: [false, true]).fractions, [1])
        assertClose(NoopChartAxisMarks.points(covered: [true, false]).fractions, [0])
        // Twenty-two weekly points with the fixture's covered weeks 3 and 22 (indices 2 and 21).
        assertClose(NoopChartAxisMarks.points(covered: covered(22, at: [2, 21])).fractions, [2.0 / 21.0, 1])
    }

    func testSinglePointSitsInTheMiddle() {
        assertClose(NoopChartAxisMarks.points(covered: [true]).fractions, [0.5])
        assertClose(NoopChartAxisMarks.points(covered: [false]).fractions, [])
    }

    func testBarsPlacesIndexPlusHalfOverCount() {
        assertClose(NoopChartAxisMarks.bars(covered: [true, true, true, true]).fractions,
                    [0.125, 0.375, 0.625, 0.875])
        assertClose(NoopChartAxisMarks.bars(covered: [false, true, false, true]).fractions, [0.375, 0.875])
        assertClose(NoopChartAxisMarks.bars(covered: [true]).fractions, [0.5])
        assertClose(NoopChartAxisMarks.bars(covered: [true, true]).fractions, [0.25, 0.75])
        // A bar's dot is under the middle of its bar: never on the plot's edge, which is where
        // index / (count − 1) would put the first and the last.
        let thirty = NoopChartAxisMarks.bars(covered: [Bool](repeating: true, count: 30)).fractions
        XCTAssertEqual(thirty.count, 30)
        assertClose([thirty.first ?? -1, thirty.last ?? -1], [0.5 / 30.0, 29.5 / 30.0])
        assertClose(gaps(thirty), [Double](repeating: 1.0 / 30.0, count: 29))
        // The same covered list as points and as bars gives different positions.
        let asPoints = NoopChartAxisMarks.points(covered: [true, true, true, true]).fractions
        XCTAssertNotEqual(NoopChartAxisMarks.bars(covered: [true, true, true, true]).fractions, asPoints)
    }

    func testValuesMapsOntoTheDomainAndDropsValuesOutsideIt() {
        let all = [true, true, true, true, true]
        assertClose(NoopChartAxisMarks.values([10, 12.5, 15, 17.5, 20], covered: all, domain: 10...20).fractions,
                    [0, 0.25, 0.5, 0.75, 1])
        // Outside the domain on either side: dropped, not clamped onto the edge.
        assertClose(NoopChartAxisMarks.values([5, 10, 15, 20, 25], covered: all, domain: 10...20).fractions,
                    [0, 0.5, 1])
        // Only covered values are marked.
        assertClose(NoopChartAxisMarks.values([10, 12.5, 15, 17.5, 20], covered: [false, true, false, true, false],
                                              domain: 10...20).fractions,
                    [0.25, 0.75])
        // A domain that does not start at zero, and one that crosses it.
        assertClose(NoopChartAxisMarks.values([-5, 0, 15], covered: [true, true, true], domain: -5...15).fractions,
                    [0, 0.25, 1])

        // The bounds are inside the domain; the nearest value beyond either is not.
        let low = 10.0
        let high = 20.0
        XCTAssertEqual(NoopChartAxisMarks.values([low], covered: [true], domain: low...high).fractions.count, 1)
        XCTAssertEqual(NoopChartAxisMarks.values([low.nextDown], covered: [true], domain: low...high).fractions, [])
        XCTAssertEqual(NoopChartAxisMarks.values([low.nextUp], covered: [true], domain: low...high).fractions.count, 1)
        XCTAssertEqual(NoopChartAxisMarks.values([high], covered: [true], domain: low...high).fractions.count, 1)
        XCTAssertEqual(NoopChartAxisMarks.values([high.nextUp], covered: [true], domain: low...high).fractions, [])
        XCTAssertEqual(NoopChartAxisMarks.values([high.nextDown], covered: [true], domain: low...high).fractions.count, 1)
    }

    func testValuesGivesAscendingDistinctFractionsWhateverTheOrderOfTheInput() {
        // The type's stated invariant is "ascending, distinct"; the x values of a chart need not
        // arrive sorted, and two points may share an x.
        assertClose(NoopChartAxisMarks.values([30, 10, 20, 10, 30], covered: [true, true, true, true, true],
                                              domain: 0...40).fractions,
                    [0.25, 0.5, 0.75])
        // A repeated x counts as covered when any of its entries is.
        assertClose(NoopChartAxisMarks.values([10, 10, 20], covered: [false, true, false], domain: 0...40).fractions,
                    [0.25])
    }

    func testNothingCoveredGivesNoFractions() {
        let none = [Bool](repeating: false, count: 30)
        XCTAssertEqual(NoopChartAxisMarks.points(covered: none).fractions, [])
        XCTAssertEqual(NoopChartAxisMarks.bars(covered: none).fractions, [])
        XCTAssertEqual(NoopChartAxisMarks.values((0..<30).map(Double.init), covered: none, domain: 0...29).fractions, [])
        XCTAssertEqual(NoopChartAxisMarks.points(covered: []).fractions, [])
        XCTAssertEqual(NoopChartAxisMarks.bars(covered: []).fractions, [])
        XCTAssertEqual(NoopChartAxisMarks.values([], covered: [], domain: 0...1).fractions, [])
        // No fractions means no row and no height (§10.5): the layout has nothing to place.
        XCTAssertEqual(offsets(NoopChartAxisMarks.points(covered: none), width: 300, minSpacing: 6), [])
        XCTAssertEqual(offsets(NoopChartAxisMarks(fractions: []), width: 300, leading: 8, trailing: 8, minSpacing: 6), [])
    }

    func testFractionsOfEveryConstructorAreAscendingDistinctAndWithinZeroToOne() {
        var generator = Generator(state: 0x5EED_05A1)
        for round in 0..<300 {
            let count = generator.below(60)
            let flags = (0..<count).map { _ in generator.below(3) != 0 }
            let xs = (0..<count).map { _ in Double(generator.below(200)) - 50 }
            let low = Double(generator.below(60)) - 30
            let domain = low...(low + 1 + Double(generator.below(120)))
            let built = [
                NoopChartAxisMarks.points(covered: flags),
                NoopChartAxisMarks.bars(covered: flags),
                NoopChartAxisMarks.values(xs, covered: flags, domain: domain),
            ]
            for (index, marks) in built.enumerated() {
                let name = "round \(round) constructor \(index)"
                XCTAssertTrue(marks.fractions.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 }, name)
                XCTAssertTrue(gaps(marks.fractions).allSatisfy { $0 > 0 }, name)
                XCTAssertLessThanOrEqual(marks.fractions.count, flags.filter { $0 }.count, name)
            }
            // Points and bars place one mark per covered position, no more and no fewer.
            XCTAssertEqual(built[0].fractions.count, flags.filter { $0 }.count, "round \(round)")
            XCTAssertEqual(built[1].fractions.count, flags.filter { $0 }.count, "round \(round)")
            // The same input gives the same marks.
            XCTAssertEqual(NoopChartAxisMarks.points(covered: flags), built[0])
            XCTAssertEqual(NoopChartAxisMarks.bars(covered: flags), built[1])
            XCTAssertEqual(NoopChartAxisMarks.values(xs, covered: flags, domain: domain), built[2])
        }
    }

    func testAccessibilityTextIsCarriedAndDoesNotMoveAMark() {
        let flags = [true, false, true]
        XCTAssertNil(NoopChartAxisMarks.points(covered: flags).accessibilityText)
        XCTAssertNil(NoopChartAxisMarks(fractions: [0.5]).accessibilityText)
        let spoken = "Events: Fixture caption"
        let points = NoopChartAxisMarks.points(covered: flags, accessibilityText: spoken)
        let bars = NoopChartAxisMarks.bars(covered: flags, accessibilityText: spoken)
        let values = NoopChartAxisMarks.values([0, 1, 2], covered: flags, domain: 0...2, accessibilityText: spoken)
        XCTAssertEqual(points.accessibilityText, spoken)
        XCTAssertEqual(bars.accessibilityText, spoken)
        XCTAssertEqual(values.accessibilityText, spoken)
        XCTAssertEqual(points.fractions, NoopChartAxisMarks.points(covered: flags).fractions)
        XCTAssertEqual(bars.fractions, NoopChartAxisMarks.bars(covered: flags).fractions)
        // The text is part of the value: two mark sets that speak differently are not equal.
        XCTAssertNotEqual(points, NoopChartAxisMarks.points(covered: flags))
        XCTAssertEqual(NoopChartAxisMarks(fractions: [0, 1], accessibilityText: spoken), points)
    }

    // MARK: - Offsets

    func testOffsetsRespectInsets() {
        let marks = NoopChartAxisMarks(fractions: [0, 0.5, 1])
        assertClose(offsets(marks, width: 120, minSpacing: 6), [0, 60, 120])
        // The plot is 120 − 10 − 30 = 80 points wide and starts 10 points in.
        assertClose(offsets(marks, width: 120, leading: 10, trailing: 30, minSpacing: 6), [10, 50, 90])
        assertClose(offsets(marks, width: 120, leading: 30, trailing: 10, minSpacing: 6), [30, 70, 110])
        assertClose(offsets(marks, width: 120, leading: 40, trailing: 0, minSpacing: 6), [40, 80, 120])
        assertClose(offsets(marks, width: 120, leading: 0, trailing: 40, minSpacing: 6), [0, 40, 80])
        // Four bars across an 80-point plot inset by 10 on each side: the middle of each bar.
        assertClose(offsets(NoopChartAxisMarks.bars(covered: [true, true, true, true]),
                            width: 100, leading: 10, trailing: 10, minSpacing: 6),
                    [20, 40, 60, 80])
        // Five points across the same plot: both ends sit on the plot's edges.
        assertClose(offsets(NoopChartAxisMarks.points(covered: [true, false, true, false, true]),
                            width: 100, leading: 10, trailing: 10, minSpacing: 6),
                    [10, 50, 90])
        // One point sits in the middle of the plot, not of the row.
        assertClose(offsets(NoopChartAxisMarks.points(covered: [true]), width: 100, leading: 20, trailing: 0,
                            minSpacing: 6),
                    [60])
    }

    func testMarksAtLeastTheMinimumSpacingApartAreAllKept() {
        // Nine points across 48 points: neighbours are exactly 6 apart.
        let marks = NoopChartAxisMarks.points(covered: [Bool](repeating: true, count: 9))
        let all = [0.0, 6, 12, 18, 24, 30, 36, 42, 48]
        // Just under, and exactly at, the spacing they have: "at least" keeps every mark.
        assertClose(offsets(marks, width: 48, minSpacing: 6.0.nextDown), all)
        assertClose(offsets(marks, width: 48, minSpacing: 6), all)
        assertClose(offsets(marks, width: 48, minSpacing: 5), all)
        assertClose(offsets(marks, width: 48, minSpacing: 0), all)
        // Asking for the smallest amount more than they have thins them.
        let thinned = offsets(marks, width: 48, minSpacing: 6.0.nextUp)
        XCTAssertLessThan(thinned.count, 9)
        XCTAssertTrue(isSubset(thinned, of: all))
        XCTAssertTrue(gaps(thinned).allSatisfy { $0 > 6 }, "\(thinned)")
        XCTAssertTrue(contains(thinned, 0) && contains(thinned, 48), "\(thinned)")
        // Thirty day bars across 300 points are 10 apart: none is lost at the proposed spacing of 6.
        let bars = NoopChartAxisMarks.bars(covered: [Bool](repeating: true, count: 30))
        assertClose(offsets(bars, width: 300, minSpacing: 6), (0..<30).map { Double($0) * 10 + 5 })
        // Sparse marks far apart are untouched.
        assertClose(offsets(NoopChartAxisMarks.points(covered: covered(97, at: [3, 40, 90])), width: 96, minSpacing: 6),
                    [3, 40, 90])
    }

    func testThinningKeepsMinimumSpacing() {
        // Ninety-seven points across 96 points of plot: neighbours are 1 apart, far too close.
        let marks = NoopChartAxisMarks.points(covered: [Bool](repeating: true, count: 97))
        let unthinned = (0...96).map(Double.init)
        assertClose(offsets(marks, width: 96, minSpacing: 0), unthinned)
        for spacing in [2.0, 6, 10, 48, 96] {
            let kept = offsets(marks, width: 96, minSpacing: spacing)
            XCTAssertTrue(gaps(kept).allSatisfy { $0 >= spacing - 1e-9 }, "spacing \(spacing): \(kept)")
            XCTAssertTrue(isSubset(kept, of: unthinned), "spacing \(spacing): a mark moved")
            XCTAssertTrue(contains(kept, 0) && contains(kept, 96), "spacing \(spacing): \(kept)")
            XCTAssertLessThanOrEqual(kept.count, Int(96 / spacing) + 1, "spacing \(spacing)")
        }
        // SPEC-AMBIGUITY: §10.5 states what thinning guarantees, not how many marks survive it.
        // A long covered run must still read as a run, so more than its two ends are expected to
        // stay when there is room for them (here room for seventeen at the proposed spacing).
        XCTAssertGreaterThanOrEqual(offsets(marks, width: 96, minSpacing: 6).count, 3)

        // The same with insets: the spacing is in points of the row, whatever the plot's inset.
        let inset = offsets(marks, width: 120, leading: 8, trailing: 16, minSpacing: 6)
        XCTAssertTrue(gaps(inset).allSatisfy { $0 >= 6 - 1e-9 }, "\(inset)")
        XCTAssertTrue(isSubset(inset, of: unthinned.map { $0 + 8 }))
        XCTAssertTrue(contains(inset, 8) && contains(inset, 104), "\(inset)")

        // Bars thin the same way.
        let bars = offsets(NoopChartAxisMarks.bars(covered: [Bool](repeating: true, count: 96)), width: 96, minSpacing: 6)
        XCTAssertTrue(gaps(bars).allSatisfy { $0 >= 6 - 1e-9 }, "\(bars)")
        XCTAssertTrue(contains(bars, 0.5) && contains(bars, 95.5), "\(bars)")
    }

    func testThinningKeepsTheFirstAndLastMarkOfEveryRun() {
        // Three runs along 97 points, 1 point apart: indices 0…20, the single index 40, and 60…96.
        let flags = covered(97, at: Array(0...20) + [40] + Array(60...96))
        let kept = offsets(NoopChartAxisMarks.points(covered: flags), width: 96, minSpacing: 6)
        for end in [0.0, 20, 40, 60, 96] {
            XCTAssertTrue(contains(kept, end), "the run end at \(end) was dropped: \(kept)")
        }
        XCTAssertTrue(gaps(kept).allSatisfy { $0 >= 6 - 1e-9 }, "\(kept)")
        XCTAssertTrue(isSubset(kept, of: flags.indices.filter { flags[$0] }.map(Double.init)))
        XCTAssertTrue(gaps(kept).allSatisfy { $0 > 0 }, "offsets must ascend: \(kept)")
        // Nothing is invented in the uncovered stretches between the runs.
        XCTAssertFalse(kept.contains { ($0 > 20.5 && $0 < 39.5) || ($0 > 40.5 && $0 < 59.5) }, "\(kept)")

        // A run whose length is not a multiple of the spacing: stepping by 6 from the first mark
        // would stop at 18 and lose the last, 20.
        let short = offsets(NoopChartAxisMarks.points(covered: covered(97, at: Array(0...20))), width: 96, minSpacing: 6)
        XCTAssertTrue(contains(short, 0) && contains(short, 20), "\(short)")
        XCTAssertTrue(gaps(short).allSatisfy { $0 >= 6 - 1e-9 }, "\(short)")

        // The same for bars, whose runs start half a bar in.
        let bars = offsets(NoopChartAxisMarks.bars(covered: covered(96, at: Array(10...30) + Array(70...95))),
                           width: 96, minSpacing: 6)
        for end in [10.5, 30.5, 70.5, 95.5] {
            XCTAssertTrue(contains(bars, end), "the run end at \(end) was dropped: \(bars)")
        }
        XCTAssertTrue(gaps(bars).allSatisfy { $0 >= 6 - 1e-9 }, "\(bars)")

        // And on a continuous axis.
        let xs = (0...96).map(Double.init)
        let values = offsets(NoopChartAxisMarks.values(xs, covered: flags, domain: 0...96), width: 96, minSpacing: 6)
        for end in [0.0, 20, 40, 60, 96] {
            XCTAssertTrue(contains(values, end), "the run end at \(end) was dropped: \(values)")
        }
    }

    func testARunShorterThanTheMinimumSpacingKeepsBothItsEnds() {
        // SPEC-AMBIGUITY: §10.5 promises both that neighbours are at least `minSpacing` apart and
        // that the first and last mark of every unbroken run are "always kept". For a run shorter
        // than the spacing the two cannot both hold. "Always" is read as the stronger promise: a
        // two-day event keeps both of its dots (they overlap, which is harmless), and only the
        // marks between a run's ends are thinned.
        let pair = offsets(NoopChartAxisMarks.points(covered: covered(97, at: [10, 11])), width: 96, minSpacing: 6)
        assertClose(pair, [10, 11])
        let four = offsets(NoopChartAxisMarks.points(covered: covered(97, at: [10, 11, 12, 13])), width: 96, minSpacing: 6)
        assertClose(four, [10, 13])
        // A run of one is its own first and last mark.
        assertClose(offsets(NoopChartAxisMarks.points(covered: covered(97, at: [10])), width: 96, minSpacing: 6), [10])
    }

    func testZeroOrNegativeWidthGivesNoOffsets() {
        let marks = NoopChartAxisMarks.points(covered: [true, true, true])
        XCTAssertEqual(offsets(marks, width: 0, minSpacing: 6), [])
        XCTAssertEqual(offsets(marks, width: -1, minSpacing: 6), [])
        XCTAssertEqual(offsets(marks, width: -0.001, minSpacing: 6), [])
        XCTAssertEqual(offsets(marks, width: -300, leading: 8, trailing: 8, minSpacing: 6), [])
        XCTAssertEqual(offsets(marks, width: 0, minSpacing: 0), [])
        XCTAssertEqual(offsets(NoopChartAxisMarks.points(covered: [true]), width: 0, minSpacing: 6), [])
        // The smallest width above zero places marks again.
        assertClose(offsets(marks, width: 0.5, minSpacing: 0), [0, 0.25, 0.5])
    }

    func testInsetsThatLeaveNoPlotGiveNoOffsets() {
        // SPEC-AMBIGUITY: §12.2 names only "zero or negative width". The plot is the width less its
        // insets, so insets that use up the whole row are read the same way: there is no plot to
        // mark, and no offset is returned (a dot is never drawn outside the plot).
        let marks = NoopChartAxisMarks.points(covered: [true, true, true])
        XCTAssertEqual(offsets(marks, width: 100, leading: 60, trailing: 40, minSpacing: 6), [])
        XCTAssertEqual(offsets(marks, width: 100, leading: 80, trailing: 40, minSpacing: 6), [])
        // One point of plot left is enough.
        assertClose(offsets(marks, width: 100, leading: 60, trailing: 39, minSpacing: 0), [60, 60.5, 61])
    }

    func testOffsetsAreTheUnthinnedPositionsOrASubsetOfThemForGeneratedMarks() {
        var generator = Generator(state: 0x5EED_05A2)
        for round in 0..<300 {
            let count = 1 + generator.below(200)
            let flags = (0..<count).map { _ in generator.below(4) != 0 }
            let marks = generator.below(2) == 0 ? NoopChartAxisMarks.points(covered: flags)
                                                : NoopChartAxisMarks.bars(covered: flags)
            let leading = Double(generator.below(20))
            let trailing = Double(generator.below(20))
            let width = 60 + Double(generator.below(340))
            let spacing = [0.0, 2, 4, 6, 10, 25][generator.below(6)]
            let plot = width - leading - trailing
            let expected = marks.fractions.map { leading + $0 * plot }

            let unthinned = offsets(marks, width: width, leading: leading, trailing: trailing, minSpacing: 0)
            assertClose(unthinned, expected, accuracy: 1e-6, "round \(round)")

            let kept = offsets(marks, width: width, leading: leading, trailing: trailing, minSpacing: spacing)
            let name = "round \(round): \(kept)"
            XCTAssertTrue(isSubset(kept, of: expected), name)
            XCTAssertTrue(gaps(kept).allSatisfy { $0 > 0 }, name)
            XCTAssertTrue(kept.allSatisfy { $0 >= leading - 1e-6 && $0 <= width - trailing + 1e-6 }, name)
            XCTAssertEqual(kept.isEmpty, expected.isEmpty, name)
            // The very first and the very last mark start and end a run, so they always survive.
            if let first = expected.first, let last = expected.last {
                XCTAssertTrue(contains(kept, first) && contains(kept, last), name)
            }
            // Marks that are already far enough apart are returned whole.
            if gaps(expected).allSatisfy({ $0 >= spacing + 1e-6 }) {
                assertClose(kept, expected, accuracy: 1e-6, name)
            }
            // The same input gives the same offsets.
            XCTAssertEqual(offsets(marks, width: width, leading: leading, trailing: trailing, minSpacing: spacing), kept)
        }
    }

    // MARK: - Non-finite and degenerate input

    func testNonFiniteValuesAreNeverMarked() {
        // NaN and the infinities lie in no domain, so they are dropped like any outside value.
        let xs: [Double] = [.nan, -.infinity, 0, .infinity, 5, .signalingNaN, 10]
        let marks = NoopChartAxisMarks.values(xs, covered: [Bool](repeating: true, count: 7), domain: 0...10)
        assertClose(marks.fractions, [0, 0.5, 1])
        XCTAssertEqual(NoopChartAxisMarks.values([.nan], covered: [true], domain: 0...10).fractions, [])
        XCTAssertEqual(NoopChartAxisMarks.values([.infinity, -.infinity], covered: [true, true], domain: 0...10).fractions, [])
    }

    func testDegenerateDomainsAndMismatchedListsGiveOnlyFiniteFractionsInRange() {
        // SPEC-AMBIGUITY: §10.5 does not say what `values` does with a domain of zero width, an
        // unbounded domain, or lists of different lengths. Whatever it chooses, it must not trap
        // and must not hand the layout a fraction that is not a finite number in 0...1.
        let cases = [
            NoopChartAxisMarks.values([5], covered: [true], domain: 5...5),
            NoopChartAxisMarks.values([4, 5, 6], covered: [true, true, true], domain: 5...5),
            NoopChartAxisMarks.values([0, 1], covered: [true, true], domain: -Double.infinity...Double.infinity),
            NoopChartAxisMarks.values([0, 1], covered: [true, true], domain: 0...Double.infinity),
            NoopChartAxisMarks.values([0, 1, 2], covered: [true], domain: 0...2),
            NoopChartAxisMarks.values([0], covered: [true, true, true], domain: 0...2),
        ]
        for (index, marks) in cases.enumerated() {
            XCTAssertTrue(marks.fractions.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 },
                          "case \(index): \(marks.fractions)")
            XCTAssertTrue(gaps(marks.fractions).allSatisfy { $0 > 0 }, "case \(index): \(marks.fractions)")
            XCTAssertLessThanOrEqual(marks.fractions.count, 3, "case \(index)")
        }
        // A value outside a zero-width domain is still outside it.
        XCTAssertEqual(NoopChartAxisMarks.values([4, 6], covered: [true, true], domain: 5...5).fractions, [])
    }

    func testNonFiniteGeometryGivesNoOffsets() {
        // SPEC-AMBIGUITY: §12.2 names zero and negative widths only. A width or inset that is not
        // a finite number describes no plot either, so it is read the same way: no offsets. The
        // row is drawn from these numbers, and a non-finite offset must never reach it.
        let marks = NoopChartAxisMarks.points(covered: [true, true, true])
        for bad in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(offsets(marks, width: bad, minSpacing: 6), [], "width \(bad)")
            XCTAssertEqual(offsets(marks, width: 100, leading: bad, trailing: 0, minSpacing: 6), [], "leading \(bad)")
            XCTAssertEqual(offsets(marks, width: 100, leading: 0, trailing: bad, minSpacing: 6), [], "trailing \(bad)")
        }
        // A spacing that is not a number, or is negative, cannot be honoured; the result must still
        // be finite, ascending and made only of real mark positions.
        for spacing in [Double.nan, .infinity, -.infinity, -6] {
            let kept = offsets(marks, width: 100, minSpacing: spacing)
            XCTAssertTrue(kept.allSatisfy { $0.isFinite }, "spacing \(spacing): \(kept)")
            XCTAssertTrue(isSubset(kept, of: [0, 50, 100]), "spacing \(spacing): \(kept)")
            XCTAssertTrue(gaps(kept).allSatisfy { $0 > 0 }, "spacing \(spacing): \(kept)")
        }
        // A negative spacing asks for nothing: every mark stays.
        assertClose(offsets(marks, width: 100, minSpacing: -6), [0, 50, 100])
    }

    func testFractionsSetByHandThatAreNotPositionsNeverBecomeOffsets() {
        // SPEC-AMBIGUITY: `fractions` is a public `var` documented as 0...1, ascending and
        // distinct, with no statement of what the layout does when a caller breaks that. A
        // fraction that is not finite or lies outside 0...1 names no position on the plot, so it
        // is read as giving no dot; the layout must not trap on it or return a non-finite offset.
        let marks = NoopChartAxisMarks(fractions: [-0.5, .nan, 0.25, 2, .infinity, 0.75, -.infinity])
        let kept = offsets(marks, width: 100, minSpacing: 6)
        XCTAssertTrue(kept.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 100 }, "\(kept)")
        assertClose(kept, [25, 75])
    }
}
