import XCTest
@testable import StrandDesign

/// The redesign charts' pure geometry: the line chart's y-domain (where a "typical range" may only widen the
/// scale, never be drawn), its zone-gradient stops, the bar chart's heights (a missing value is a gap, not a
/// zero bar) and the zone bars' fractions (no NaN when nothing was recorded).
final class NoopChartDomainTests: XCTestCase {

    private let eps = 1e-9

    private func assertRange(
        _ range: ClosedRange<Double>?, _ lo: Double, _ hi: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard let range else { return XCTFail("expected \(lo)...\(hi), got nil", file: file, line: line) }
        XCTAssertEqual(range.lowerBound, lo, accuracy: eps, file: file, line: line)
        XCTAssertEqual(range.upperBound, hi, accuracy: eps, file: file, line: line)
    }

    // MARK: - y-domain

    func testYDomainEmptyIsNil() {
        XCTAssertNil(NoopLineChart.yDomain(values: []))
        XCTAssertNil(NoopLineChart.yDomain(values: [], typicalRange: 40...60))
        XCTAssertNil(NoopLineChart.yDomain(values: [.nan, .infinity]))
    }

    func testYDomainSingleValueHasNonZeroSpan() {
        // 10 % of 60 = 6 wide, centred, then 12 % of 6 padding each side.
        assertRange(NoopLineChart.yDomain(values: [60]), 57 - 0.72, 63 + 0.72)
    }

    func testYDomainFlatSeriesHasNonZeroSpan() {
        assertRange(NoopLineChart.yDomain(values: [52, 52, 52], paddingFraction: 0), 49.4, 54.6)
        // A flat series at zero still gets a span of at least 1, centred on zero.
        assertRange(NoopLineChart.yDomain(values: [0, 0], paddingFraction: 0), -0.5, 0.5)
    }

    func testYDomainPadsBySpanFraction() {
        assertRange(NoopLineChart.yDomain(values: [50, 70, 60]), 50 - 2.4, 70 + 2.4)
        assertRange(NoopLineChart.yDomain(values: [50, 70], paddingFraction: 0.25), 45, 75)
        assertRange(NoopLineChart.yDomain(values: [50, 70], paddingFraction: 0), 50, 70)
        // Negative padding is treated as none; the domain never shrinks inside the data.
        assertRange(NoopLineChart.yDomain(values: [50, 70], paddingFraction: -1), 50, 70)
    }

    func testYDomainTypicalRangeWiderThanDataWidens() {
        // Data 58…62 inside a typical 50…75: the domain spans the typical range, padded by its span.
        assertRange(NoopLineChart.yDomain(values: [58, 62], typicalRange: 50...75), 50 - 3, 75 + 3)
    }

    func testYDomainTypicalRangeNarrowerThanDataNeverShrinks() {
        assertRange(
            NoopLineChart.yDomain(values: [40, 90], typicalRange: 55...65, paddingFraction: 0), 40, 90
        )
        // Partly overlapping: only the side that extends past the data widens.
        assertRange(
            NoopLineChart.yDomain(values: [50, 60], typicalRange: 55...80, paddingFraction: 0), 50, 80
        )
    }

    func testYDomainIgnoresNonFiniteValues() {
        assertRange(NoopLineChart.yDomain(values: [50, .nan, 70], paddingFraction: 0), 50, 70)
    }

    func testXDomain() {
        XCTAssertNil(NoopLineChart.xDomain(values: []))
        assertRange(NoopLineChart.xDomain(values: [3, 1, 2]), 1, 3)
        assertRange(NoopLineChart.xDomain(values: [5, 5]), 4.5, 5.5)
    }

    func testPlottableDropsNonFiniteAndSorts() {
        let pts = [
            NoopChartPoint(x: 2, y: 5), NoopChartPoint(x: 0, y: .nan), NoopChartPoint(x: 1, y: 4),
        ]
        XCTAssertEqual(NoopLineChart.plottable(pts).map(\.x), [1, 2])
    }

    func testDatePointRoundTrips() {
        let date = Date(timeIntervalSince1970: 1_761_700_000)
        XCTAssertEqual(NoopChartPoint(date: date, y: 1).date, date)
    }

    func testNearestIndex() {
        XCTAssertNil(NoopLineChart.nearestIndex(to: 1, in: []))
        XCTAssertEqual(NoopLineChart.nearestIndex(to: 2.4, in: [0, 1, 2, 3]), 2)
        XCTAssertEqual(NoopLineChart.nearestIndex(to: 2.5, in: [0, 1, 2, 3]), 2, "ties go to the earlier point")
        XCTAssertEqual(NoopLineChart.nearestIndex(to: -10, in: [0, 1, 2]), 0)
        XCTAssertEqual(NoopLineChart.nearestIndex(to: 99, in: [0, 1, 2]), 2)
    }

    // MARK: - Zone gradient

    func testZonePositionClampsToRamp() {
        XCTAssertEqual(NoopLineChart.zonePosition(of: 200, zoneRange: 100...200), 0, accuracy: eps)
        XCTAssertEqual(NoopLineChart.zonePosition(of: 100, zoneRange: 100...200), 1, accuracy: eps)
        XCTAssertEqual(NoopLineChart.zonePosition(of: 150, zoneRange: 100...200), 0.5, accuracy: eps)
        XCTAssertEqual(NoopLineChart.zonePosition(of: 250, zoneRange: 100...200), 0, accuracy: eps)
        XCTAssertEqual(NoopLineChart.zonePosition(of: 50, zoneRange: 100...200), 1, accuracy: eps)
    }

    func testZoneStopsWhenLineFillsTheZoneRange() {
        let stops = NoopLineChart.zoneGradientStops(dataRange: 100...200, zoneRange: 100...200)
        XCTAssertEqual(stops.map(\.location), [0, 0.25, 0.5, 0.75, 1])
        XCTAssertEqual(stops.map(\.zonePosition), [0, 0.25, 0.5, 0.75, 1])
    }

    func testZoneStopsForALineInTheMiddleOfTheZones() {
        // A line spanning 140…160 of 100…200 sits around zone 3: top at ramp 0.4, bottom at 0.6, with the
        // zone-3 stop (ramp 0.5, value 150) halfway down its bounding box.
        let stops = NoopLineChart.zoneGradientStops(dataRange: 140...160, zoneRange: 100...200)
        XCTAssertEqual(stops.count, 3)
        XCTAssertEqual(stops[0].location, 0, accuracy: eps)
        XCTAssertEqual(stops[0].zonePosition, 0.4, accuracy: eps)
        XCTAssertEqual(stops[1].location, 0.5, accuracy: eps)
        XCTAssertEqual(stops[1].zonePosition, 0.5, accuracy: eps)
        XCTAssertEqual(stops[2].location, 1, accuracy: eps)
        XCTAssertEqual(stops[2].zonePosition, 0.6, accuracy: eps)
    }

    func testZoneStopsForAFlatLineAreOneColour() {
        let stops = NoopLineChart.zoneGradientStops(dataRange: 175...175, zoneRange: 100...200)
        XCTAssertEqual(stops, [
            NoopChartZoneStop(location: 0, zonePosition: 0.25),
            NoopChartZoneStop(location: 1, zonePosition: 0.25),
        ])
    }

    // MARK: - Bar heights

    func testBarHeightsKeepGapsAsNil() {
        let heights = NoopBarChart.normalizedHeights([50, nil, 100, 25])
        XCTAssertEqual(heights.count, 4)
        XCTAssertEqual(heights[0] ?? -1, 0.5, accuracy: eps)
        XCTAssertNil(heights[1], "a missing value is a gap, never a zero bar")
        XCTAssertEqual(heights[2] ?? -1, 1, accuracy: eps)
        XCTAssertEqual(heights[3] ?? -1, 0.25, accuracy: eps)
    }

    func testBarHeightsWithExplicitMaxClamp() {
        let heights = NoopBarChart.normalizedHeights([10.5, 21, 30, -3, .nan], maxValue: 21)
        XCTAssertEqual(heights[0] ?? -1, 0.5, accuracy: eps)
        XCTAssertEqual(heights[1] ?? -1, 1, accuracy: eps)
        XCTAssertEqual(heights[2] ?? -1, 1, accuracy: eps, "above max clamps to full height")
        XCTAssertEqual(heights[3] ?? -1, 0, accuracy: eps, "negative clamps to the baseline")
        XCTAssertNil(heights[4], "a non-finite value is a gap")
    }

    func testBarHeightsMeasuredZeroIsZeroNotNil() {
        let heights = NoopBarChart.normalizedHeights([0, 0, nil])
        XCTAssertEqual(heights[0], 0)
        XCTAssertEqual(heights[1], 0)
        XCTAssertNil(heights[2])
        XCTAssertFalse(heights.compactMap { $0 }.contains { $0.isNaN })
    }

    func testBarHeightsEmptyAndAllMissing() {
        XCTAssertEqual(NoopBarChart.normalizedHeights([]), [])
        XCTAssertEqual(NoopBarChart.normalizedHeights([nil, nil], maxValue: 100), [nil, nil])
    }

    func testBarHeightsIgnoreNonPositiveMax() {
        // A zero or negative max falls back to the series' own largest value.
        let heights = NoopBarChart.normalizedHeights([5, 10], maxValue: 0)
        XCTAssertEqual(heights[0] ?? -1, 0.5, accuracy: eps)
        XCTAssertEqual(heights[1] ?? -1, 1, accuracy: eps)
    }

    // MARK: - Zone fractions

    func testZoneFractionsShareOfTotal() {
        let f = ZoneBars.fractions([60, 240, 600, 780, 180])
        XCTAssertEqual(f.count, 5)
        XCTAssertEqual(f.reduce(0, +), 1, accuracy: eps)
        XCTAssertEqual(f[3], 780.0 / 1860.0, accuracy: eps)
    }

    func testZoneFractionsRelativeToLargest() {
        let f = ZoneBars.fractions([60, 240, 600, 780, 180], scale: .largest)
        XCTAssertEqual(f[3], 1, accuracy: eps)
        XCTAssertEqual(f[2], 600.0 / 780.0, accuracy: eps)
    }

    func testZoneFractionsAllZeroOrMissingAreZeroNotNaN() {
        for scale in [ZoneBars.Scale.total, .largest] {
            XCTAssertEqual(ZoneBars.fractions([0, 0, 0, 0, 0], scale: scale), [0, 0, 0, 0, 0])
            XCTAssertEqual(ZoneBars.fractions([nil, nil, nil, nil, nil], scale: scale), [0, 0, 0, 0, 0])
            XCTAssertEqual(ZoneBars.fractions([], scale: scale), [])
        }
    }

    func testZoneFractionsTreatNegativeAndNonFiniteAsZero() {
        let f = ZoneBars.fractions([-5, .nan, 10, .infinity, 30])
        XCTAssertEqual(f, [0, 0, 0.25, 0, 0.75])
    }

    func testZoneBarsArrayInitDrawsZoneFiveFirst() {
        let bars = ZoneBars(names: ["Z1", "Z2", "Z3", "Z4", "Z5"], values: [1, 2, 3, 4, 5],
                            trailingLabels: ["a", "b", "c", "d", "e"])
        XCTAssertEqual(bars.rows.map(\.zone), [5, 4, 3, 2, 1])
        XCTAssertEqual(bars.rows.map(\.name), ["Z5", "Z4", "Z3", "Z2", "Z1"])
        XCTAssertEqual(bars.rows.map(\.trailing), ["e", "d", "c", "b", "a"])
    }
}
