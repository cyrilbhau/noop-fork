import SwiftUI

// MARK: - Rows, range indicator and stat grid (docs/personal/REDESIGN-IMPLEMENTATION.md §3.6 item 6)
//
// A missing value always renders as the em dash in the secondary colour, never as "0", so absent data cannot
// read as a measured zero.

/// The placeholder shown for a missing value.
let noopMissingValue = "—"

/// Row geometry from `design/system/noop.css` that has no `NoopTheme` token yet.
private enum RowMetrics {
    /// `.mrow` trailing column: the sparkline slot (64–72 × 30).
    static let accessoryWidth: CGFloat = 72
    static let accessoryHeight: CGFloat = 30
    static let subtitleGap: CGFloat = 2
    static let unitGap: CGFloat = 2
    /// `.lrow` vertical padding.
    static let listRowVerticalPadding: CGFloat = 12
    /// `.range`: track height, knob diameter and knob ring.
    static let rangeTrack: CGFloat = 4
    static let rangeKnob: CGFloat = 14
    static let rangeKnobRing: CGFloat = 3
    /// `.range` typical band (white 22 %).
    static let rangeBand = Color.white.opacity(0.22)
}

/// A value and its smaller secondary unit ("62 ms"); a nil value is the em dash with no unit.
private struct NoopValueText: View {
    let value: String?
    let unit: String?
    let style: NoopType

    var body: some View {
        if let value {
            HStack(alignment: .firstTextBaseline, spacing: RowMetrics.unitGap) {
                Text(verbatim: value).noopFont(style)
                if let unit, !unit.isEmpty {
                    Text(verbatim: unit).noopFont(.unit)
                }
            }
        } else {
            Text(verbatim: noopMissingValue)
                .noopFont(style, color: false)
                .foregroundStyle(NoopTheme.textSecondary)
        }
    }
}

/// A row hairline in the separator colour.
private struct NoopRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(NoopTheme.separator)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

// MARK: - Metric row

/// A metric row for list cards (`NoopGlassCard(flush: true)`): title in the domain colour, optional
/// sub-line, value plus unit, and an optional trailing accessory (a 72 × 30 sparkline slot). A nil value
/// shows "—". `showsDivider` draws the hairline ABOVE the row, so pass false for the first row in a card.
public struct NoopMetricRow<Accessory: View>: View {
    private let title: LocalizedStringKey
    private let color: Color
    private let subtitle: String?
    private let value: String?
    private let unit: String?
    private let showsDivider: Bool
    private let hasAccessory: Bool
    private let accessory: Accessory

    public init(
        _ title: LocalizedStringKey,
        color: Color,
        subtitle: String? = nil,
        value: String?,
        unit: String? = nil,
        showsDivider: Bool = true,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.init(title, color: color, subtitle: subtitle, value: value, unit: unit, showsDivider: showsDivider,
                  hasAccessory: true, accessory: accessory())
    }

    fileprivate init(
        _ title: LocalizedStringKey, color: Color, subtitle: String?, value: String?, unit: String?,
        showsDivider: Bool, hasAccessory: Bool, accessory: Accessory
    ) {
        self.title = title
        self.color = color
        self.subtitle = subtitle
        self.value = value
        self.unit = unit
        self.showsDivider = showsDivider
        self.hasAccessory = hasAccessory
        self.accessory = accessory
    }

    public var body: some View {
        VStack(spacing: 0) {
            if showsDivider { NoopRowDivider() }
            HStack(spacing: NoopTheme.Layout.m) {
                VStack(alignment: .leading, spacing: RowMetrics.subtitleGap) {
                    Text(title)
                        .noopFont(.rowTitle, color: false)
                        .foregroundStyle(color)
                    if let subtitle {
                        Text(verbatim: subtitle).noopFont(.footnote)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                NoopValueText(value: value, unit: unit, style: .rowNumber)
                    .layoutPriority(1)
                if hasAccessory {
                    accessory
                        .frame(width: RowMetrics.accessoryWidth, height: RowMetrics.accessoryHeight)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, NoopTheme.Layout.rowVerticalPadding)
        }
        .accessibilityElement(children: .combine)
    }
}

public extension NoopMetricRow where Accessory == EmptyView {
    /// A metric row with no trailing accessory.
    init(
        _ title: LocalizedStringKey,
        color: Color,
        subtitle: String? = nil,
        value: String?,
        unit: String? = nil,
        showsDivider: Bool = true
    ) {
        self.init(title, color: color, subtitle: subtitle, value: value, unit: unit, showsDivider: showsDivider,
                  hasAccessory: false, accessory: EmptyView())
    }
}

// MARK: - Range indicator

/// A gauge row: a track, an optional typical band and a value dot (Recovery "What shaped it"). A gauge
/// rather than a chart, so it may show a band. A nil value draws no dot; a nil band draws no band.
public struct RangeIndicator: View {
    private let value: Double?
    private let range: ClosedRange<Double>
    private let band: ClosedRange<Double>?
    private let color: Color

    public init(value: Double?, range: ClosedRange<Double>, band: ClosedRange<Double>? = nil, color: Color) {
        self.value = value
        self.range = range
        self.band = band
        self.color = color
    }

    /// Where `value` sits along `range`, 0…1, clamped. nil for a missing or non-finite value; 0.5 for a
    /// zero-width range.
    public static func position(of value: Double?, in range: ClosedRange<Double>) -> Double? {
        guard let value, value.isFinite, range.lowerBound.isFinite, range.upperBound.isFinite else { return nil }
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0.5 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    /// The band's start and end along `range`, each clamped to 0…1. nil when the band is missing or not
    /// finite.
    public static func bandPositions(of band: ClosedRange<Double>?, in range: ClosedRange<Double>) -> ClosedRange<Double>? {
        guard let band,
              let lower = position(of: band.lowerBound, in: range),
              let upper = position(of: band.upperBound, in: range) else { return nil }
        return lower...upper
    }

    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let midY = RowMetrics.rangeKnob / 2
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(NoopTheme.track)
                    .frame(width: width, height: RowMetrics.rangeTrack)
                    .position(x: width / 2, y: midY)
                if let span = Self.bandPositions(of: band, in: range) {
                    let bandWidth = CGFloat(span.upperBound - span.lowerBound) * width
                    Capsule()
                        .fill(RowMetrics.rangeBand)
                        .frame(width: bandWidth, height: RowMetrics.rangeTrack)
                        .position(x: CGFloat(span.lowerBound) * width + bandWidth / 2, y: midY)
                }
                if let p = Self.position(of: value, in: range) {
                    Circle()
                        .fill(color)
                        .overlay(Circle().strokeBorder(NoopTheme.sheet, lineWidth: RowMetrics.rangeKnobRing))
                        .frame(width: RowMetrics.rangeKnob, height: RowMetrics.rangeKnob)
                        .position(x: CGFloat(p) * width, y: midY)
                }
            }
        }
        .frame(height: RowMetrics.rangeKnob)
        .accessibilityHidden(true)
    }
}

// MARK: - Stat grid

/// One cell of a `StatGrid`. A nil value shows "—".
public struct StatGridItem {
    public let label: LocalizedStringKey
    public let value: String?
    public let unit: String?

    public init(_ label: LocalizedStringKey, value: String?, unit: String? = nil) {
        self.label = label
        self.value = value
        self.unit = unit
    }
}

/// A 2- or 3-column grid of label / value / unit stats (workout and session summaries).
public struct StatGrid: View {
    private let items: [StatGridItem]
    private let columns: Int

    /// `columns` is clamped to 2…3.
    public init(_ items: [StatGridItem], columns: Int = 2) {
        self.items = items
        self.columns = min(max(columns, 2), 3)
    }

    public var body: some View {
        let grid = Array(
            repeating: GridItem(.flexible(), spacing: NoopTheme.Layout.cardGap, alignment: .topLeading),
            count: columns
        )
        LazyVGrid(columns: grid, alignment: .leading, spacing: NoopTheme.Layout.l) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
                    Text(item.label).noopFont(.footnote)
                    NoopValueText(value: item.value, unit: item.unit, style: .statNumber)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - List row

/// A Profile / Settings row: optional small domain icon, title, optional detail line, optional trailing
/// value and a chevron. Wrap in a `NavigationLink` or `Button`. `showsDivider` draws the hairline ABOVE
/// the row, so pass false for the first row in a card.
public struct NoopListRow: View {
    private let title: LocalizedStringKey
    private let systemImage: String?
    private let color: Color
    private let detail: String?
    private let value: String?
    private let showsChevron: Bool
    private let showsDivider: Bool

    public init(
        _ title: LocalizedStringKey,
        systemImage: String? = nil,
        color: Color = NoopTheme.textSecondary,
        detail: String? = nil,
        value: String? = nil,
        showsChevron: Bool = true,
        showsDivider: Bool = true
    ) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
        self.detail = detail
        self.value = value
        self.showsChevron = showsChevron
        self.showsDivider = showsDivider
    }

    public var body: some View {
        VStack(spacing: 0) {
            if showsDivider { NoopRowDivider() }
            HStack(spacing: NoopTheme.Layout.m) {
                if let systemImage {
                    DomainIcon(systemImage: systemImage, color: color, size: DomainIcon.smallSize)
                }
                VStack(alignment: .leading, spacing: RowMetrics.subtitleGap) {
                    Text(title).noopFont(.listTitle)
                    if let detail {
                        Text(verbatim: detail).noopFont(.footnote)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let value {
                    Text(verbatim: value)
                        .noopFont(.bodySmall, color: false)
                        .foregroundStyle(NoopTheme.textSecondary)
                }
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .noopFont(.footnote, color: false)
                        .fontWeight(.semibold)
                        .foregroundStyle(NoopTheme.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, RowMetrics.listRowVerticalPadding)
            .frame(minHeight: NoopTheme.Layout.minTouchTarget)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Noop rows") {
    ScrollView {
        VStack(spacing: NoopTheme.Layout.cardGap) {
            NoopGlassCard(flush: true) {
                VStack(spacing: 0) {
                    NoopMetricRow("HRV", color: NoopTheme.hrv, subtitle: "Above your usual range", value: "62", unit: "ms",
                                  showsDivider: false) {
                        Capsule().fill(NoopTheme.hrv.opacity(0.3))
                    }
                    NoopMetricRow("Resting heart rate", color: NoopTheme.heart, value: "52", unit: "bpm")
                    NoopMetricRow("Skin temperature", color: NoopTheme.temp, subtitle: "No reading", value: nil, unit: "°C")
                }
            }
            NoopGlassCard {
                VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
                    RangeIndicator(value: 62, range: 35...75, band: 46...60, color: NoopTheme.hrv)
                    RangeIndicator(value: nil, range: 44...64, band: 50...56, color: NoopTheme.heart)
                    RangeIndicator(value: 14.8, range: 12...18, color: NoopTheme.breath)
                }
            }
            NoopGlassCard {
                StatGrid([
                    StatGridItem("Duration", value: "1:02", unit: "h"),
                    StatGridItem("Avg HR", value: "128", unit: "bpm"),
                    StatGridItem("Calories", value: nil, unit: "kcal"),
                ], columns: 3)
            }
            NoopGlassCard(flush: true) {
                VStack(spacing: 0) {
                    NoopListRow("Strap", systemImage: "applewatch", color: NoopTheme.recovery, detail: "WHOOP 4.0 · connected",
                                value: "82%", showsDivider: false)
                    NoopListRow("Data sources", systemImage: "folder", color: NoopTheme.hrv)
                    NoopListRow("Settings", systemImage: "gearshape")
                }
            }
        }
        .padding(NoopTheme.Layout.gutter)
    }
    .background(NoopTheme.canvas)
}
#endif
