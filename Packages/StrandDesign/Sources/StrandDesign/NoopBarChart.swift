import SwiftUI

// MARK: - NoopBarChart (redesign §3.6 item 4)
//
// Rounded capsule bars, one per slot, in a single colour or a colour per value (Recovery takes its band
// colour). The highlighted bar (by default the last slot, the latest day) is full opacity and the rest
// 75 %. The visual reference is `colorBars()` in `design/system/noop.js`.
//
// A missing value is a gap: no bar, not a zero bar, so an unworn day never reads as a measured zero. A
// measured zero still gets a short stub so it stays distinguishable from that gap. Like NoopLineChart there
// are no gridlines or axes; captions under the bars come from `xLabels`.

public struct NoopBarChart: View {

    public var values: [Double?]
    /// The value a full-height bar represents (100 for Recovery, 21 for Strain). Nil scales to the largest
    /// value in the series.
    public var maxValue: Double?
    /// Fixed bar width; nil sizes bars to half their slot, between 3 and 14 pt.
    public var barWidth: CGFloat?
    /// The slot drawn at full opacity; the others are 75 %. Defaults to the last slot. A highlighted slot
    /// with no value highlights nothing (an earlier day is never promoted to "latest").
    public var highlightedIndex: Int?
    /// Captions under the bars. When there is one per value each sits under its bar; otherwise they are
    /// spread edge to edge.
    public var xLabels: [String]
    /// False renders the final state immediately (widgets, snapshots, already-seen content).
    public var animates: Bool
    public var accessibilityLabel: Text?
    public var valueFormat: (Double) -> String
    private var colorFor: (Double) -> Color

    /// Single-colour bars.
    public init(
        values: [Double?],
        color: Color,
        maxValue: Double? = nil,
        barWidth: CGFloat? = nil,
        highlightedIndex: Int? = nil,
        xLabels: [String] = [],
        animates: Bool = true,
        accessibilityLabel: Text? = nil,
        valueFormat: @escaping (Double) -> String = { NoopBarChart.defaultValueString($0) }
    ) {
        self.init(
            values: values, colorForValue: { _ in color }, maxValue: maxValue, barWidth: barWidth,
            highlightedIndex: highlightedIndex, xLabels: xLabels, animates: animates,
            accessibilityLabel: accessibilityLabel, valueFormat: valueFormat
        )
    }

    /// A colour per bar from its value, e.g. `colorForValue: { NoopTheme.recoveryColor(for: $0) }`.
    public init(
        values: [Double?],
        colorForValue: @escaping (Double) -> Color,
        maxValue: Double? = nil,
        barWidth: CGFloat? = nil,
        highlightedIndex: Int? = nil,
        xLabels: [String] = [],
        animates: Bool = true,
        accessibilityLabel: Text? = nil,
        valueFormat: @escaping (Double) -> String = { NoopBarChart.defaultValueString($0) }
    ) {
        self.values = values
        self.colorFor = colorForValue
        self.maxValue = maxValue
        self.barWidth = barWidth
        self.highlightedIndex = highlightedIndex ?? (values.isEmpty ? nil : values.count - 1)
        self.xLabels = xLabels
        self.animates = animates
        self.accessibilityLabel = accessibilityLabel
        self.valueFormat = valueFormat
        _grown = State(initialValue: !animates)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown: Bool

    // MARK: - Pure geometry

    /// Integer when whole, otherwise one decimal, in the current locale.
    public static func defaultValueString(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// Bar heights as fractions 0…1 of the plot. A nil or non-finite value stays nil (a gap). Negative values
    /// clamp to 0 and values above `maxValue` to 1. With no positive scale (every value zero, or a
    /// non-positive `maxValue`) the present values are all 0 rather than NaN.
    public static func normalizedHeights(_ values: [Double?], maxValue: Double? = nil) -> [Double?] {
        let scale: Double
        if let maxValue, maxValue.isFinite, maxValue > 0 {
            scale = maxValue
        } else {
            scale = values.compactMap { $0 }.filter(\.isFinite).max() ?? 0
        }
        return values.map { value in
            guard let value, value.isFinite else { return nil }
            guard scale > 0 else { return 0 }
            return min(max(value / scale, 0), 1)
        }
    }

    // MARK: - Body

    private static let dimmedOpacity: Double = 0.75
    /// Minimum drawn height, so a measured zero is a stub and not mistaken for a gap.
    private static let minimumBarHeight: CGFloat = 3

    public var body: some View {
        let heights = Self.normalizedHeights(values, maxValue: maxValue)
        VStack(spacing: NoopTheme.Layout.s) {
            GeometryReader { geo in
                let slot = values.isEmpty ? 0 : geo.size.width / CGFloat(values.count)
                let width = barWidth ?? min(max(slot * 0.5, 3), 14)
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(Array(heights.enumerated()), id: \.offset) { i, fraction in
                        ZStack(alignment: .bottom) {
                            if let fraction, let value = values[i] {
                                Capsule()
                                    .fill(colorFor(value))
                                    .frame(
                                        width: width,
                                        height: max(CGFloat(fraction) * geo.size.height, Self.minimumBarHeight)
                                    )
                                    .opacity(i == highlightedIndex ? 1 : Self.dimmedOpacity)
                                    .scaleEffect(x: 1, y: grown || reduceMotion ? 1 : 0, anchor: .bottom)
                                    .opacity(grown || !reduceMotion ? 1 : 0)
                                    .animation(barAnimation(index: i), value: grown)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
                }
                .animation(NoopTheme.Motion.resolved(NoopTheme.Motion.bar, reduceMotion: reduceMotion), value: heights)
            }
            if !xLabels.isEmpty {
                captions
            }
        }
        .onAppear { if animates { grown = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel ?? Text(summary))
        .accessibilityValue(accessibilityLabel == nil ? Text(verbatim: "") : Text(summary))
    }

    /// Spring from the baseline with an 18 ms stagger; under Reduce Motion one short fade for every bar.
    private func barAnimation(index: Int) -> Animation {
        reduceMotion
            ? NoopTheme.Motion.reduced
            : NoopTheme.Motion.bar.delay(Double(index) * NoopTheme.Motion.barStagger)
    }

    @ViewBuilder
    private var captions: some View {
        if xLabels.count == values.count {
            HStack(spacing: 0) {
                ForEach(Array(xLabels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .noopFont(.caption)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
        } else {
            HStack(spacing: 0) {
                ForEach(Array(xLabels.enumerated()), id: \.offset) { i, label in
                    Text(label)
                        .noopFont(.caption)
                        .monospacedDigit()
                        .lineLimit(1)
                    if i < xLabels.count - 1 { Spacer(minLength: NoopTheme.Layout.xs) }
                }
            }
            .accessibilityHidden(true)
        }
    }

    private var summary: String {
        let present = values.compactMap { $0 }.filter(\.isFinite)
        guard let last = present.last, let lo = present.min(), let hi = present.max() else {
            return String(localized: "No data", bundle: .module)
        }
        return String(
            localized: "Trend, \(present.count) points, latest \(valueFormat(last)), low \(valueFormat(lo)), high \(valueFormat(hi))",
            bundle: .module
        )
    }
}

#if DEBUG
#Preview("NoopBarChart") {
    VStack(alignment: .leading, spacing: 28) {
        // Recovery: band colour per bar, one unworn day (gap), latest highlighted.
        NoopBarChart(
            values: [72, 45, nil, 28, 66, 81, 58],
            colorForValue: { NoopTheme.recoveryColor(for: $0) },
            maxValue: 100,
            xLabels: ["M", "T", "W", "T", "F", "S", "S"]
        )
        .frame(height: 110)
        // Strain: single colour, a measured zero (stub) beside a gap.
        NoopBarChart(
            values: [8.2, 0, nil, 14.1, 11.6, 9.4, 12.8],
            color: NoopTheme.strain,
            maxValue: 21,
            xLabels: ["Oct 23", "Oct 29"]
        )
        .frame(height: 90)
    }
    .padding(24)
    .frame(width: 402)
    .background(NoopTheme.canvas)
    .preferredColorScheme(.dark)
}
#endif
