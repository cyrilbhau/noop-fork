#if !os(watchOS)
// NoopLineChart is a Swift Charts view; like TrendChart and OverviewHRChart the watch never shows it, so
// the whole file is excluded there. iOS/macOS only.
import SwiftUI
import Charts

// MARK: - NoopLineChart (redesign §3.6 item 3)
//
// The redesign's line chart, from a full-width detail chart down to a 64–72 × 30 pt sparkline in a
// MetricRow. Catmull-Rom line with a left-to-right opacity gradient, an optional area wash and a
// latest-point dot with a halo. The visual reference is `lineChart()` in `design/system/noop.js`.
//
// Deliberately absent: horizontal gridlines, horizontal rule marks and range bands. The owner rejected
// straight horizontal lines across charts, so a "typical range" only widens the y-domain and is never
// drawn. Axes are hidden; any axis text is a row of captions under the plot (`xLabels`). The one line
// that may cross the plot is the vertical selection rule.

/// One point on a `NoopLineChart`. `x` is a plain `Double` so the chart needs no generic parameter:
/// dates go through `init(date:y:)` (seconds since 1970), indices or minutes can be passed directly.
public struct NoopChartPoint: Identifiable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    /// Content-derived identity (one point per x), so Swift Charts diffs by data instead of replaying
    /// every mark on each render.
    public var id: Double { x }

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public init(date: Date, y: Double) {
        self.init(x: date.timeIntervalSince1970, y: y)
    }

    public var date: Date { Date(timeIntervalSince1970: x) }
}

/// One stop of the heart-rate-zone stroke gradient, expressed for Swift Charts.
///
/// Swift Charts maps a mark's gradient onto the bounding box of the line it strokes, not onto the plot
/// area. A z5→z1 gradient handed over as-is would therefore paint the top of every line red whatever its
/// heart rate. These stops re-express the zone ramp in that bounding box: `location` runs 0 (the line's
/// highest value) to 1 (its lowest), and `zonePosition` is where that value sits on the zone ramp, 0 at
/// the top of the zone range (zone 5) to 1 at the bottom (zone 1).
public struct NoopChartZoneStop: Equatable, Sendable {
    public var location: Double
    public var zonePosition: Double

    public init(location: Double, zonePosition: Double) {
        self.location = location
        self.zonePosition = zonePosition
    }
}

public struct NoopLineChart: View {

    public var points: [NoopChartPoint]
    public var color: Color
    /// Widens the y-domain so a quiet series is read against its usual spread. Never drawn.
    public var typicalRange: ClosedRange<Double>?
    /// Colours the line by heart-rate zone (vertical gradient z5 at the top to z1 at the bottom).
    public var zones: Bool
    /// The values at the bottom of zone 1 and the top of zone 5. Nil maps the zone ramp onto the y-domain.
    public var zoneBounds: ClosedRange<Double>?
    public var showsArea: Bool
    public var showsLatestDot: Bool
    /// Sparkline mode (64–72 × 30 pt): thinner stroke, smaller dot, no selection gesture.
    public var compact: Bool
    /// Caption row under the plot, spread edge to edge. Empty draws no row.
    public var xLabels: [String]
    /// The selected x. Non-nil binding (and not `compact`) enables tap/drag selection; the dot moves to the
    /// nearest point and a vertical rule marks it.
    public var selection: Binding<Double?>?
    /// Tooltip text for the selected point. Nil shows the rule and dot without a tooltip.
    public var selectionLabel: ((NoopChartPoint) -> String)?
    /// False renders the final state immediately (widgets, snapshots, already-seen content).
    public var animates: Bool
    /// Whether a change of data replays the draw. Pass false for a live series that updates in place
    /// (live heart rate), where a redraw every sample would never let the line settle.
    public var redrawOnChange: Bool
    public var accessibilityLabel: Text?
    /// Formats a value for the spoken summary, so units match the call site.
    public var valueFormat: (Double) -> String

    public init(
        points: [NoopChartPoint],
        color: Color,
        typicalRange: ClosedRange<Double>? = nil,
        zones: Bool = false,
        zoneBounds: ClosedRange<Double>? = nil,
        showsArea: Bool = true,
        showsLatestDot: Bool = true,
        compact: Bool = false,
        xLabels: [String] = [],
        selection: Binding<Double?>? = nil,
        selectionLabel: ((NoopChartPoint) -> String)? = nil,
        animates: Bool = true,
        redrawOnChange: Bool = true,
        accessibilityLabel: Text? = nil,
        valueFormat: @escaping (Double) -> String = { NoopLineChart.defaultValueString($0) }
    ) {
        self.points = points
        self.color = color
        self.typicalRange = typicalRange
        self.zones = zones
        self.zoneBounds = zoneBounds
        self.showsArea = showsArea
        self.showsLatestDot = showsLatestDot
        self.compact = compact
        self.xLabels = xLabels
        self.selection = selection
        self.selectionLabel = selectionLabel
        self.animates = animates
        self.redrawOnChange = redrawOnChange
        self.accessibilityLabel = accessibilityLabel
        self.valueFormat = valueFormat
        _reveal = State(initialValue: animates ? 0 : 1)
        _areaOpacity = State(initialValue: animates ? 0 : 1)
        _dotScale = State(initialValue: animates ? 0 : 1)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Fraction of the plot width the line mask uncovers (the "trim" of §3.5).
    @State private var reveal: CGFloat
    @State private var areaOpacity: Double
    @State private var dotScale: CGFloat
    /// Whole-chart opacity; only animated under Reduce Motion, where the draw becomes a short fade.
    @State private var fade: Double = 1
    @State private var tooltipSize: CGSize = .zero

    // MARK: - Pure geometry

    /// Integer when whole, otherwise one decimal, in the current locale.
    public static func defaultValueString(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// The y-domain for `values`: their span plus `typicalRange` (which may only widen it), padded by
    /// `paddingFraction` of that span on each side. Nil when there is no finite value, so a caller can never
    /// end up plotting an invented zero. A flat series gets a non-zero span (10 % of its magnitude, at least
    /// 1) centred on the value, so it draws as a level line mid-plot instead of dividing by zero.
    public static func yDomain(
        values: [Double],
        typicalRange: ClosedRange<Double>? = nil,
        paddingFraction: Double = 0.12
    ) -> ClosedRange<Double>? {
        let finite = values.filter(\.isFinite)
        guard var lo = finite.min(), var hi = finite.max() else { return nil }
        if let typicalRange, typicalRange.lowerBound.isFinite, typicalRange.upperBound.isFinite {
            lo = min(lo, typicalRange.lowerBound)
            hi = max(hi, typicalRange.upperBound)
        }
        var span = hi - lo
        if span <= 0 {
            span = max(abs(lo) * 0.1, 1)
            lo -= span / 2
            hi += span / 2
        }
        let pad = span * (paddingFraction.isFinite ? max(paddingFraction, 0) : 0)
        return (lo - pad)...(hi + pad)
    }

    /// The x-domain: first to last finite x. Nil for no finite x; a single distinct x gets a unit span so
    /// positions stay finite.
    public static func xDomain(values: [Double]) -> ClosedRange<Double>? {
        let finite = values.filter(\.isFinite)
        guard let lo = finite.min(), let hi = finite.max() else { return nil }
        return hi > lo ? lo...hi : (lo - 0.5)...(hi + 0.5)
    }

    /// The finite points, sorted by x, that the chart actually draws. Fewer than two means nothing is drawn.
    public static func plottable(_ points: [NoopChartPoint]) -> [NoopChartPoint] {
        points.filter { $0.x.isFinite && $0.y.isFinite }.sorted { $0.x < $1.x }
    }

    /// Index of the point whose x is nearest `x` in an ascending `xs`. Ties go to the earlier point.
    public static func nearestIndex(to x: Double, in xs: [Double]) -> Int? {
        guard !xs.isEmpty, x.isFinite else { return nil }
        var best = 0
        var bestDistance = abs(xs[0] - x)
        for i in xs.indices.dropFirst() {
            let d = abs(xs[i] - x)
            if d < bestDistance {
                best = i
                bestDistance = d
            }
        }
        return best
    }

    /// Position (0 = top, zone 5; 1 = bottom, zone 1) of `value` on a zone ramp spanning `zoneRange`,
    /// clamped to the ramp.
    public static func zonePosition(of value: Double, zoneRange: ClosedRange<Double>) -> Double {
        let span = zoneRange.upperBound - zoneRange.lowerBound
        guard span > 0, value.isFinite else { return 0.5 }
        return min(max((zoneRange.upperBound - value) / span, 0), 1)
    }

    /// The zone ramp re-expressed in the bounding box of a line spanning `dataRange` (see
    /// `NoopChartZoneStop`). Always starts at location 0 and ends at 1, with the ramp's interior zone stops
    /// (every quarter) that fall inside the line's span in between. A flat line is one solid zone colour.
    public static func zoneGradientStops(
        dataRange: ClosedRange<Double>,
        zoneRange: ClosedRange<Double>
    ) -> [NoopChartZoneStop] {
        let top = zonePosition(of: dataRange.upperBound, zoneRange: zoneRange)
        let bottom = zonePosition(of: dataRange.lowerBound, zoneRange: zoneRange)
        let dataSpan = dataRange.upperBound - dataRange.lowerBound
        let zoneSpan = zoneRange.upperBound - zoneRange.lowerBound
        guard dataSpan > 0, zoneSpan > 0 else {
            return [NoopChartZoneStop(location: 0, zonePosition: top),
                    NoopChartZoneStop(location: 1, zonePosition: top)]
        }
        var stops = [NoopChartZoneStop(location: 0, zonePosition: top)]
        for k in 1...3 {
            let position = Double(k) / 4
            let value = zoneRange.upperBound - position * zoneSpan
            let location = (dataRange.upperBound - value) / dataSpan
            if location > 0, location < 1 {
                stops.append(NoopChartZoneStop(location: location, zonePosition: position))
            }
        }
        stops.append(NoopChartZoneStop(location: 1, zonePosition: bottom))
        return stops
    }

    // MARK: - Body

    public var body: some View {
        let plotted = Self.plottable(points)
        VStack(spacing: NoopTheme.Layout.s) {
            plot(plotted)
            if !xLabels.isEmpty {
                NoopLineChartCaptionRow(labels: xLabels)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel ?? Text(summary(plotted)))
        .accessibilityValue(accessibilityLabel == nil ? Text(verbatim: "") : Text(summary(plotted)))
    }

    @ViewBuilder
    private func plot(_ plotted: [NoopChartPoint]) -> some View {
        if plotted.count >= 2,
           let xd = Self.xDomain(values: plotted.map(\.x)),
           let yd = Self.yDomain(values: plotted.map(\.y), typicalRange: typicalRange) {
            GeometryReader { geo in
                let insets = plotInsets
                let rect = CGRect(
                    x: insets.leading,
                    y: insets.top,
                    width: max(geo.size.width - insets.leading - insets.trailing, 1),
                    height: max(geo.size.height - insets.top, 1)
                )
                ZStack(alignment: .topLeading) {
                    if showsArea {
                        areaChart(plotted, xd: xd, yd: yd)
                            .padding(insets)
                            .opacity(areaOpacity)
                    }
                    lineChart(plotted, xd: xd, yd: yd)
                        .padding(insets)
                        .mask(alignment: .leading) {
                            // Charts cannot trim a line, so a widening rectangle uncovers it left to right.
                            // Taller than the plot so round caps at the extremes are never shaved.
                            Rectangle()
                                .frame(width: geo.size.width * reveal, height: geo.size.height + insets.top * 2)
                        }
                    markers(plotted, xd: xd, yd: yd, rect: rect, container: geo.size)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
            .opacity(fade)
            .onAppear(perform: play)
            .onChangeCompat(of: plotted) { _ in if redrawOnChange { play() } }
        } else {
            // Nothing honest to draw: hold the caller's frame, never a fake zero line.
            Color.clear
        }
    }

    // MARK: - Layers

    private var lineWidth: CGFloat { compact ? 2 : 2.5 }
    private var dotRadius: CGFloat { compact ? 3 : 4 }
    private var haloRadius: CGFloat { compact ? 6 : 8 }

    /// Keeps the line caps and the latest-point halo inside the frame (noop.js insets the plot the same way).
    /// No bottom inset: the area wash runs to the bottom edge.
    private var plotInsets: EdgeInsets {
        EdgeInsets(top: haloRadius, leading: lineWidth, bottom: 0, trailing: haloRadius)
    }

    private func zoneRange(_ yd: ClosedRange<Double>) -> ClosedRange<Double> {
        if let zoneBounds, zoneBounds.upperBound > zoneBounds.lowerBound { return zoneBounds }
        return yd
    }

    /// The zone ramp from zone 5 (position 0) to zone 1 (position 1).
    private static var zoneRamp: [Gradient.Stop] {
        NoopTheme.zones.reversed().enumerated().map { i, c in Gradient.Stop(color: c, location: Double(i) / 4) }
    }

    private func zoneColor(at value: Double, yd: ClosedRange<Double>) -> Color {
        StrandPalette.sample(stops: Self.zoneRamp, at: Self.zonePosition(of: value, zoneRange: zoneRange(yd)))
    }

    private func strokeGradient(_ plotted: [NoopChartPoint], yd: ClosedRange<Double>) -> LinearGradient {
        if zones, let lo = plotted.map(\.y).min(), let hi = plotted.map(\.y).max() {
            let ramp = Self.zoneRamp
            let stops = Self.zoneGradientStops(dataRange: lo...hi, zoneRange: zoneRange(yd)).map {
                Gradient.Stop(color: StrandPalette.sample(stops: ramp, at: $0.zonePosition), location: $0.location)
            }
            return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(
            colors: [color.opacity(Self.strokeStartOpacity), color],
            startPoint: .leading, endPoint: .trailing
        )
    }

    private var areaGradient: LinearGradient {
        if zones {
            // noop.js: z5 at 38 % fading by 6 points a zone, to nothing at the baseline.
            let zs = Array(NoopTheme.zones.reversed())
            return LinearGradient(stops: [
                Gradient.Stop(color: zs[0].opacity(0.38), location: 0),
                Gradient.Stop(color: zs[1].opacity(0.32), location: 0.25),
                Gradient.Stop(color: zs[2].opacity(0.26), location: 0.5),
                Gradient.Stop(color: zs[3].opacity(0.20), location: 0.75),
                Gradient.Stop(color: zs[4].opacity(0), location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(
            colors: [color.opacity(Self.areaTopOpacity), color.opacity(0)],
            startPoint: .top, endPoint: .bottom
        )
    }

    private static let strokeStartOpacity: Double = 0.3
    private static let areaTopOpacity: Double = 0.42
    private static let haloOpacity: Double = 0.22
    private static let selectionRuleOpacity: Double = 0.25

    private func areaChart(_ plotted: [NoopChartPoint], xd: ClosedRange<Double>, yd: ClosedRange<Double>) -> some View {
        let fill = areaGradient
        return Chart(plotted) { p in
            // yStart at the domain floor, not zero: the wash fills to the plot's bottom edge and a series far
            // from zero is not stretched down to an axis nobody sees.
            AreaMark(
                x: .value("x", p.x),
                yStart: .value("floor", yd.lowerBound),
                yEnd: .value("y", p.y)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(fill)
        }
        .noopLineChartChrome(xd: xd, yd: yd)
    }

    private func lineChart(_ plotted: [NoopChartPoint], xd: ClosedRange<Double>, yd: ClosedRange<Double>) -> some View {
        let stroke = strokeGradient(plotted, yd: yd)
        let width = lineWidth
        return Chart(plotted) { p in
            LineMark(x: .value("x", p.x), y: .value("y", p.y))
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                .foregroundStyle(stroke)
        }
        .noopLineChartChrome(xd: xd, yd: yd)
    }

    /// Dot, selection rule and tooltip, positioned with the same linear mapping as the plot (the plot area
    /// of an axis-less Chart is its whole frame), plus the selection gesture.
    private func markers(
        _ plotted: [NoopChartPoint],
        xd: ClosedRange<Double>,
        yd: ClosedRange<Double>,
        rect: CGRect,
        container: CGSize
    ) -> some View {
        let xs = plotted.map(\.x)
        let selectedIndex = selection?.wrappedValue.flatMap { Self.nearestIndex(to: $0, in: xs) }
        let dotIndex = selectedIndex ?? (showsLatestDot ? plotted.count - 1 : nil)
        func position(_ p: NoopChartPoint) -> CGPoint {
            CGPoint(
                x: rect.minX + CGFloat((p.x - xd.lowerBound) / (xd.upperBound - xd.lowerBound)) * rect.width,
                y: rect.minY + CGFloat(1 - (p.y - yd.lowerBound) / (yd.upperBound - yd.lowerBound)) * rect.height
            )
        }
        return ZStack(alignment: .topLeading) {
            if let selectedIndex {
                let at = position(plotted[selectedIndex])
                Rectangle()
                    .fill(NoopTheme.textPrimary.opacity(Self.selectionRuleOpacity))
                    .frame(width: 1, height: container.height)
                    .position(x: at.x, y: container.height / 2)
                if let selectionLabel {
                    let half = tooltipSize.width / 2
                    let x = min(max(at.x, half), max(container.width - half, half))
                    Text(selectionLabel(plotted[selectedIndex]))
                        .noopFont(.caption, color: false)
                        .monospacedDigit()
                        .foregroundStyle(NoopTheme.textPrimary)
                        .padding(.horizontal, NoopTheme.Layout.s)
                        .padding(.vertical, NoopTheme.Layout.xs)
                        .background(Capsule().fill(NoopTheme.cardSolid))
                        .overlay(Capsule().stroke(NoopTheme.cardBorder, lineWidth: 1))
                        .fixedSize()
                        .background(GeometryReader { g in
                            Color.clear.preference(key: NoopLineChartTooltipSizeKey.self, value: g.size)
                        })
                        .position(x: x, y: tooltipSize.height / 2)
                }
            }
            if let dotIndex {
                let p = plotted[dotIndex]
                let at = position(p)
                let dotColor = zones ? zoneColor(at: p.y, yd: yd) : color
                ZStack {
                    Circle()
                        .fill(dotColor.opacity(Self.haloOpacity))
                        .frame(width: haloRadius * 2, height: haloRadius * 2)
                    Circle()
                        .fill(dotColor)
                        .frame(width: dotRadius * 2, height: dotRadius * 2)
                        .overlay(Circle().stroke(NoopTheme.canvas, lineWidth: 1.5))
                }
                .scaleEffect(selectedIndex == nil ? dotScale : 1)
                .position(at)
            }
        }
        .frame(width: container.width, height: container.height, alignment: .topLeading)
        .onPreferenceChange(NoopLineChartTooltipSizeKey.self) { tooltipSize = $0 }
        .contentShape(Rectangle())
        .modifier(NoopLineChartSelectionGesture(
            enabled: selection != nil && !compact,
            select: { locationX in
                guard let selection else { return }
                let fraction = Double((locationX - rect.minX) / rect.width)
                let x = xd.lowerBound + min(max(fraction, 0), 1) * (xd.upperBound - xd.lowerBound)
                guard let i = Self.nearestIndex(to: x, in: xs) else { return }
                selection.wrappedValue = xs[i]
            },
            toggle: { locationX in
                guard let selection else { return }
                let fraction = Double((locationX - rect.minX) / rect.width)
                let x = xd.lowerBound + min(max(fraction, 0), 1) * (xd.upperBound - xd.lowerBound)
                guard let i = Self.nearestIndex(to: x, in: xs) else { return }
                // A second tap on the selected point clears the selection.
                selection.wrappedValue = selection.wrappedValue == xs[i] ? nil : xs[i]
            }
        ))
    }

    // MARK: - Motion

    /// Line draws left to right (0.7 s ease-out), the area fades in 0.2 s later and the dot pops 0→1 on a
    /// spring that overshoots to about 1.13 at the end. Reduce Motion: a 0.15 s fade of the finished chart.
    private func play() {
        guard animates else {
            reveal = 1
            areaOpacity = 1
            dotScale = 1
            fade = 1
            return
        }
        if reduceMotion {
            reveal = 1
            areaOpacity = 1
            dotScale = 1
            fade = 0
            withAnimation(NoopTheme.Motion.reduced) { fade = 1 }
            return
        }
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            fade = 1
            reveal = 0
            areaOpacity = 0
            dotScale = 0
        }
        withAnimation(NoopTheme.Motion.chartDraw) { reveal = 1 }
        withAnimation(NoopTheme.Motion.chartArea.delay(NoopTheme.Motion.chartAreaDelay)) { areaOpacity = 1 }
        withAnimation(NoopTheme.Motion.dotPop.delay(Self.dotDelay)) { dotScale = 1 }
    }

    /// The dot pops as the line arrives at it (noop.js: 0.6 s into the 0.7 s draw).
    private static let dotDelay: Double = 0.6

    private func summary(_ plotted: [NoopChartPoint]) -> String {
        let ys = plotted.map(\.y)
        guard let last = ys.last, let lo = ys.min(), let hi = ys.max() else {
            return String(localized: "No data", bundle: .module)
        }
        return String(
            localized: "Trend, \(ys.count) points, latest \(valueFormat(last)), low \(valueFormat(lo)), high \(valueFormat(hi))",
            bundle: .module
        )
    }
}

// MARK: - Private helpers

private extension View {
    /// Shared chart chrome: explicit domains, no axes, no legend. Nothing here may draw a horizontal line.
    func noopLineChartChrome(xd: ClosedRange<Double>, yd: ClosedRange<Double>) -> some View {
        self
            .chartXScale(domain: xd)
            .chartYScale(domain: yd)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .allowsHitTesting(false)
    }
}

private struct NoopLineChartTooltipSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// Tap selects (or clears) the nearest point; a horizontal drag scrubs. The drag needs a few points of travel
/// so a vertical scroll that starts on the chart still scrolls.
private struct NoopLineChartSelectionGesture: ViewModifier {
    let enabled: Bool
    let select: (CGFloat) -> Void
    let toggle: (CGFloat) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .gesture(DragGesture(minimumDistance: 8).onChanged { select($0.location.x) })
                .simultaneousGesture(SpatialTapGesture().onEnded { toggle($0.location.x) })
        } else {
            content.allowsHitTesting(false)
        }
    }
}

/// Axis captions under the plot, first flush left and last flush right.
private struct NoopLineChartCaptionRow: View {
    let labels: [String]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                Text(label)
                    .noopFont(.caption)
                    .monospacedDigit()
                    .lineLimit(1)
                if i < labels.count - 1 { Spacer(minLength: NoopTheme.Layout.xs) }
            }
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
private func previewHR() -> [NoopChartPoint] {
    (0..<40).map { i in
        NoopChartPoint(x: Double(i), y: 64 + 40 * sin(Double(i) / 6) + Double((i * 7) % 5))
    }
}

private struct NoopLineChartSelectionPreview: View {
    @State private var selected: Double? = 24

    var body: some View {
        NoopLineChart(
            points: previewHR(),
            color: NoopTheme.heart,
            zones: true,
            xLabels: ["0:00", "10:00", "20:00", "31:04"],
            selection: $selected,
            selectionLabel: { "\(Int($0.y.rounded())) bpm" }
        )
        .frame(height: 160)
    }
}

#Preview("NoopLineChart") {
    VStack(alignment: .leading, spacing: 24) {
        NoopLineChart(
            points: [58, 61, 57, 63, 66, 62, 70].enumerated().map { NoopChartPoint(x: Double($0), y: $1) },
            color: NoopTheme.hrv,
            typicalRange: 50...75,
            xLabels: ["Mon", "Wed", "Fri", "Sun"]
        )
        .frame(height: 140)
        NoopLineChartSelectionPreview()
        HStack(spacing: 16) {
            NoopLineChart(
                points: [52, 54, 51, 55, 53, 50].enumerated().map { NoopChartPoint(x: Double($0), y: $1) },
                color: NoopTheme.heart,
                compact: true
            )
            .frame(width: 68, height: 30)
            // One point: nothing is drawn, the frame is held.
            NoopLineChart(points: [NoopChartPoint(x: 0, y: 60)], color: NoopTheme.sleep, compact: true)
                .frame(width: 68, height: 30)
        }
    }
    .padding(24)
    .frame(width: 402)
    .background(NoopTheme.canvas)
    .preferredColorScheme(.dark)
}
#endif
#endif
