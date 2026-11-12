// Gap tests for `NoopChartAxisMarks` and `ChartAxisMarkLayout` (stage-5.md §10.5, §12.2).
//
// Each test pins one fault that the fault-injection pass found no test for. Expected values come
// from the specification, not from the implementation.
//
// The specification places the type in StrandDesign; at the time of writing the source file sits
// in StrandAnalytics. The import below follows the file, so this test moves with it unchanged.

import XCTest
#if canImport(StrandDesign)
@testable import StrandDesign
#else
@testable import StrandAnalytics
#endif

final class ChartAxisMarksRulingGapTests: XCTestCase {

    private func assertClose(_ actual: [CGFloat], _ expected: [CGFloat],
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, "\(actual) is not \(expected)",
                       file: file, line: line)
        for (a, e) in zip(actual, expected) {
            XCTAssertEqual(a, e, accuracy: 1e-6, "\(actual) is not \(expected)", file: file, line: line)
        }
    }

    /// 97 positions at one point pitch over a plot 96 points wide, covered only at `indices`.
    private func points97(coveredAt indices: Set<Int>) -> NoopChartAxisMarks {
        NoopChartAxisMarks.points(covered: (0..<97).map { indices.contains($0) })
    }

    // MARK: - Fault C11a: §12.2 a zero width gives no offsets, whatever the insets

    func testZeroWidthGivesNoOffsetsEvenWhenNegativeInsetsWouldLeaveAPlot() {
        let marks = NoopChartAxisMarks.points(covered: [true, true, true])
        XCTAssertEqual(ChartAxisMarkLayout.offsets(marks, width: 0, leading: -10, trailing: -10,
                                                   minSpacing: 6), [])
    }

    // MARK: - Fault C14: marks exactly `minSpacing` apart are already "at least" that far apart

    func testAMarkExactlyTheMinimumSpacingFromItsNeighbourIsNotThinnedAgainstIt() {
        // Marks at 0, 6 and 9 points with a minimum of 6. Read from the covered flags, the three
        // are separate runs of one. Read from positions, 0 and 6 already satisfy "at least 6
        // apart", so the only crowded stretch is 6…9, and 6 is its first mark. Either way §10.5
        // keeps all three: a first or last mark of a run is always kept.
        let offsets = ChartAxisMarkLayout.offsets(points97(coveredAt: [0, 6, 9]), width: 96,
                                                  leading: 0, trailing: 0, minSpacing: 6)
        assertClose(offsets, [0, 6, 9])
    }

    // MARK: - Fault C23: offsets come back in axis order

    func testOffsetsAreAscendingWhenFractionsWereSetByHandOutOfOrder() {
        // §10.5 documents `fractions` as ascending and speaks of the "neighbours" of an offset;
        // the returned list is read left to right by the row that draws it.
        let marks = NoopChartAxisMarks(fractions: [0.75, 0.25])
        let offsets = ChartAxisMarkLayout.offsets(marks, width: 100, leading: 0, trailing: 0,
                                                  minSpacing: 6)
        assertClose(offsets, [25, 75])
    }

    // MARK: - Fault C24: a value with no covered flag is not covered

    func testValuesBeyondTheEndOfTheCoveredListAreNeverMarked() {
        // §10.5: "positions of covered x values". Only x = 0 has a flag, and it maps to 0.
        // Whether a list of the wrong length marks its paired head ([0]) or nothing ([]) is not
        // decided by the specification; both readings pass. Marking 1 or 2 fails.
        let fractions = NoopChartAxisMarks.values([0, 1, 2], covered: [true], domain: 0...2).fractions
        XCTAssertTrue(fractions.allSatisfy { abs($0) < 1e-9 }, "\(fractions)")
        XCTAssertLessThanOrEqual(fractions.count, 1, "\(fractions)")
    }
}
