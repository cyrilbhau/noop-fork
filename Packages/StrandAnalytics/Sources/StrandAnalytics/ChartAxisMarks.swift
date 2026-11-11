import Foundation

// Where the quiet event dots sit on a chart's time axis (stage 5 specification §10.5): the mark
// positions and their layout. A mark carries no text and no value.
//
// This file is self-contained (Foundation only, no other declaration of any module), because the
// specification's home for it is `Packages/StrandDesign/Sources/StrandDesign/ChartAxisMarks.swift`,
// beside the row view that draws it; it can be moved there unchanged.
//
// Pure and total: nothing here throws or traps, and no fraction or offset that is not a finite
// number is ever returned.
//
// No Kotlin twin: the design package has no Kotlin counterpart (stage 5 §12.7).

/// The positions of the event dots along a plot's x extent.
public struct NoopChartAxisMarks: Equatable, Sendable {
    /// 0...1 along the plot's x extent; ascending, distinct.
    public var fractions: [Double]
    /// Appended to the chart's spoken summary.
    public var accessibilityText: String?

    public init(fractions: [Double], accessibilityText: String? = nil) {
        self.fractions = fractions
        self.accessibilityText = accessibilityText
    }

    /// Where a single point sits, and where every value of a zero-width domain sits: the middle.
    static let middle = 0.5
    /// How far into its own slot a bar's dot sits: the middle of the bar.
    static let barCentre = 0.5

    /// Positions drawn at index / (count - 1): line and weekly-point charts. One position: 0.5.
    public static func points(covered: [Bool], accessibilityText: String? = nil) -> NoopChartAxisMarks {
        let count = covered.count
        let fractions: [Double] = covered.indices.compactMap { index in
            guard covered[index] else { return nil }
            return count > 1 ? Double(index) / Double(count - 1) : middle
        }
        return NoopChartAxisMarks(fractions: fractions, accessibilityText: accessibilityText)
    }

    /// Positions drawn at (index + 0.5) / count: bar charts.
    public static func bars(covered: [Bool], accessibilityText: String? = nil) -> NoopChartAxisMarks {
        let count = Double(covered.count)
        let fractions: [Double] = covered.indices.compactMap { index in
            covered[index] ? (Double(index) + barCentre) / count : nil
        }
        return NoopChartAxisMarks(fractions: fractions, accessibilityText: accessibilityText)
    }

    /// Positions of covered x values on a continuous x-domain. A value outside the domain is
    /// dropped, not moved onto its edge; so is a value that is not a finite number.
    public static func values(_ xs: [Double], covered: [Bool], domain: ClosedRange<Double>,
                              accessibilityText: String? = nil) -> NoopChartAxisMarks {
        let none = NoopChartAxisMarks(fractions: [], accessibilityText: accessibilityText)
        let low = domain.lowerBound
        let width = domain.upperBound - low
        // SPEC-NOTE: §10.5 does not say what an unbounded domain gives. A domain whose bounds or
        // width are not finite numbers has no scale to place a value on, so it gives no marks.
        guard low.isFinite, domain.upperBound.isFinite, width.isFinite else { return none }

        var fractions: [Double] = []
        // SPEC-NOTE: §10.5 does not say what lists of different lengths give. Positions are paired
        // in order and the unpaired tail of the longer list is ignored.
        for (x, isCovered) in zip(xs, covered) where isCovered && x.isFinite && domain.contains(x) {
            // SPEC-NOTE: a domain of zero width holds one value. It is placed as `points` places a
            // single position: in the middle.
            let fraction = width > 0 ? (x - low) / width : middle
            fractions.append(min(max(fraction, 0), 1))
        }
        // The x values of a chart need not arrive sorted, and two points may share an x: the
        // type's invariant is "ascending, distinct".
        return NoopChartAxisMarks(fractions: ChartAxisMarkLayout.ascendingDistinct(fractions),
                                  accessibilityText: accessibilityText)
    }
}

/// Turns mark fractions into x offsets, thinned so the dots do not crowd.
public enum ChartAxisMarkLayout {
    /// x offsets in points for a plot of `width` inset by `leading` and `trailing`, thinned so that
    /// neighbours are at least `minSpacing` apart. The first and last mark of every unbroken run
    /// are always kept.
    ///
    /// An offset is measured from the row's own leading edge: a mark at fraction f sits at
    /// `leading + f × (width − leading − trailing)`. Offsets come back ascending. No offsets are
    /// returned when there is no plot to mark: a width that is zero or negative, insets that use
    /// up the whole width, or any of the three not a finite number.
    public static func offsets(_ marks: NoopChartAxisMarks, width: CGFloat, leading: CGFloat,
                               trailing: CGFloat, minSpacing: CGFloat) -> [CGFloat] {
        let rowWidth = Double(width)
        let inset = Double(leading)
        let plot = rowWidth - inset - Double(trailing)
        // SPEC-NOTE: §12.2 names "zero or negative width" only. Insets that leave no plot, and a
        // width or inset that is not a finite number, are read the same way: nothing to mark.
        guard rowWidth.isFinite, inset.isFinite, plot.isFinite, rowWidth > 0, plot > 0 else { return [] }

        // SPEC-NOTE: `fractions` is a public `var`. A fraction set by hand that is not a finite
        // number in 0...1 names no position on the plot and gives no dot; the rest are put in
        // ascending order with repeats removed, which is what the constructors already hand over.
        let fractions = ascendingDistinct(marks.fractions.filter { $0.isFinite && $0 >= 0 && $0 <= 1 })
        let positions = ascendingDistinct(fractions.map { inset + $0 * plot }.filter { $0.isFinite })
        return thinned(positions, minSpacing: Double(minSpacing)).map { CGFloat($0) }
    }

    /// `values` sorted ascending with exact repeats removed.
    static func ascendingDistinct(_ values: [Double]) -> [Double] {
        var out: [Double] = []
        for value in values.sorted() where out.last != value {
            out.append(value)
        }
        return out
    }

    /// Ascending positions with the marks inside each run thinned to `minSpacing`.
    ///
    /// SPEC-NOTE: the layout is given positions, not the covered flags, so "an unbroken run" is
    /// read from the positions: a run is a stretch of marks in which each is closer than
    /// `minSpacing` to the next. Marks at least `minSpacing` apart need no thinning, and such a gap
    /// ends a run. A break narrower than `minSpacing` cannot be told from crowding and does not
    /// end one.
    ///
    /// SPEC-NOTE: "at least `minSpacing` apart" and "the first and last mark of every run are
    /// always kept" cannot both hold for a run shorter than `minSpacing`. "Always" wins: both ends
    /// stay, and only the marks between them are thinned. A kept mark between the ends is at least
    /// `minSpacing` from the kept mark before it and from the run's last mark.
    ///
    /// SPEC-NOTE: "at least" is compared exactly, with no rounding allowance. A spacing of zero,
    /// below zero or not a number asks for nothing and thins nothing; an infinite one keeps only
    /// the ends of the one run.
    static func thinned(_ positions: [Double], minSpacing: Double) -> [Double] {
        guard minSpacing > 0, positions.count > 2 else { return positions }
        var kept: [Double] = []
        var runStart = 0
        while runStart < positions.count {
            var runEnd = runStart
            while runEnd + 1 < positions.count, positions[runEnd + 1] - positions[runEnd] < minSpacing {
                runEnd += 1
            }
            let last = positions[runEnd]
            var previous = positions[runStart]
            kept.append(previous)
            if runEnd > runStart {
                for position in positions[(runStart + 1)..<runEnd]
                where position - previous >= minSpacing && last - position >= minSpacing {
                    kept.append(position)
                    previous = position
                }
                kept.append(last)
            }
            runStart = runEnd + 1
        }
        return kept
    }
}
