import SwiftUI

/// The redesign's detail-hero gauge (`docs/personal/REDESIGN-IMPLEMENTATION.md` §3.6 item 2, visual
/// reference `arcGauge()` in `design/system/noop.js`). A 240° sweep that starts at 150° (between 7 and
/// 8 o'clock) and runs clockwise to 390°/30° (between 4 and 5 o'clock), stroked with a gradient from the
/// colour at 55 % to 100 %, with a white knob at the value. An optional target band draws a tick at each
/// end (Strain's 12–15 of 21). Used for the Recovery and Strain detail heroes.
///
/// Fill, count-up, haptic, Reduce Motion and missing-value rules match `NoopRing`: a `nil` value draws a
/// dashed empty track with no knob and no animation.
public struct NoopArcGauge<Center: View>: View {
    let fraction: Double?
    let color: Color
    let radius: CGFloat
    let lineWidth: CGFloat
    let targetBand: ClosedRange<Double>?
    let number: String?
    let caption: String?
    let numberColor: Color?
    let animate: Bool
    let accessibilityName: String?
    let accessibilityValueText: String?
    let center: Center

    /// The non-generic geometry namespace (statics live on the `EmptyView` specialisation).
    private typealias Geometry = NoopArcGauge<EmptyView>

    /// Gauge with caller-supplied centre content (not counted up; the caller owns its formatting).
    /// - Parameters:
    ///   - value: fill fraction 0…1; `nil` (or NaN/infinite) is the missing state. Out-of-range values clamp.
    ///   - radius: radius of the stroke's centre line. The view sizes itself to `frameSize(radius:lineWidth:)`.
    ///   - targetBand: band ends as fractions of the scale (Strain 12–15 of 21 is `12/21...15/21`).
    public init(
        value: Double?,
        color: Color,
        radius: CGFloat = NoopArcGauge<EmptyView>.defaultRadius,
        lineWidth: CGFloat = NoopArcGauge<EmptyView>.defaultLineWidth,
        targetBand: ClosedRange<Double>? = nil,
        animate: Bool = true,
        accessibilityLabel: String? = nil,
        accessibilityValue: String? = nil,
        @ViewBuilder center: () -> Center
    ) {
        self.fraction = NoopRing.clampedFraction(value)
        self.color = color
        self.radius = radius
        self.lineWidth = lineWidth
        self.targetBand = targetBand
        self.number = nil
        self.caption = nil
        self.numberColor = nil
        self.animate = animate
        self.accessibilityName = accessibilityLabel
        self.accessibilityValueText = accessibilityValue
        self.center = center()
    }

    public var body: some View {
        let size = Geometry.frameSize(radius: radius, lineWidth: lineWidth)
        let origin = Geometry.center(radius: radius, lineWidth: lineWidth)
        NoopFillAnimator(target: fraction, animate: animate) { shown, revealed in
            ZStack {
                arcs(shown: shown, origin: origin)
                centreContent(revealed: revealed)
                    .frame(width: max(0, (radius - lineWidth / 2) * 2 * 0.9))
                    .position(origin)
            }
            .frame(width: size.width, height: size.height)
        }
        .modifier(GaugeAccessibility(
            builtIn: number != nil,
            label: accessibilityName ?? caption,
            value: accessibilityValueText ?? number
        ))
    }

    @ViewBuilder
    private func arcs(shown: Double, origin: CGPoint) -> some View {
        let arc = GaugeArc(center: origin, radius: radius)
        if fraction == nil {
            arc.stroke(NoopTheme.trackEmpty,
                       style: StrokeStyle(lineWidth: NoopRing.missingLineWidth(lineWidth: lineWidth),
                                          dash: NoopRing.dashPattern(diameter: radius * 2)))
        } else {
            arc.stroke(NoopTheme.track, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            arc.trim(from: 0, to: shown)
                .stroke(LinearGradient(colors: [color.opacity(Geometry.gradientStartOpacity), color],
                                       startPoint: .bottomLeading, endPoint: .topTrailing),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
        if let targetBand {
            GaugeTicks(center: origin,
                       angles: Geometry.tickAngles(for: targetBand),
                       inner: radius - lineWidth / 2 - Geometry.tickOverhang,
                       outer: radius + lineWidth / 2 + Geometry.tickOverhang)
                .stroke(NoopTheme.targetTick, style: StrokeStyle(lineWidth: Geometry.tickWidth, lineCap: .round))
        }
        if fraction != nil {
            GaugeKnob(center: origin, radius: radius,
                      knobRadius: Geometry.knobRadius(lineWidth: lineWidth), fraction: shown)
                .fill(NoopTheme.knob)
        }
    }

    @ViewBuilder
    private func centreContent(revealed: Bool) -> some View {
        if let number {
            VStack(spacing: NoopTheme.Layout.xs) {
                Text(displayNumber(number, revealed: revealed))
                    .noopFont(.heroNumber, color: false)
                    .foregroundStyle(fraction == nil ? NoopTheme.textTertiary : (numberColor ?? color))
                    .modifier(NumericTextTransition())
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                if let caption, !caption.isEmpty {
                    Text(caption)
                        .noopFont(.pill, color: false)
                        .foregroundStyle(NoopTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        center
    }

    private func displayNumber(_ number: String, revealed: Bool) -> String {
        guard !revealed, fraction != nil, let zero = NoopRing.countUpStartLabel(number) else { return number }
        return zero
    }
}

public extension NoopArcGauge where Center == EmptyView {
    /// Gauge with the standard centre: a `heroNumber` (counted up from zero when purely numeric) and an
    /// optional caption ("Strain · target 12–15"). `numberColor` defaults to the gauge colour.
    init(
        value: Double?,
        color: Color,
        radius: CGFloat = NoopArcGauge<EmptyView>.defaultRadius,
        lineWidth: CGFloat = NoopArcGauge<EmptyView>.defaultLineWidth,
        targetBand: ClosedRange<Double>? = nil,
        number: String?,
        caption: String? = nil,
        numberColor: Color? = nil,
        animate: Bool = true,
        accessibilityLabel: String? = nil,
        accessibilityValue: String? = nil
    ) {
        self.fraction = NoopRing.clampedFraction(value)
        self.color = color
        self.radius = radius
        self.lineWidth = lineWidth
        self.targetBand = targetBand
        self.number = number
        self.caption = caption
        self.numberColor = numberColor
        self.animate = animate
        self.accessibilityName = accessibilityLabel
        self.accessibilityValueText = accessibilityValue
        self.center = EmptyView()
    }
}

// MARK: - Geometry (pure, unit-tested)

/// Geometry lives on the `EmptyView` specialisation so it has one home independent of the centre content;
/// read it as `NoopArcGauge<EmptyView>.angle(forFraction:)`.
public extension NoopArcGauge where Center == EmptyView {
    /// Arc start in SwiftUI degrees (0° = 3 o'clock, clockwise on screen).
    static var startDegrees: Double { 150 }
    static var sweepDegrees: Double { 240 }
    /// `startDegrees + sweepDegrees`, i.e. 30° past 3 o'clock.
    static var endDegrees: Double { startDegrees + sweepDegrees }
    static var defaultRadius: CGFloat { 112 }
    static var defaultLineWidth: CGFloat { 22 }
    static var gradientStartOpacity: Double { 0.55 }
    /// How far a target tick extends past each edge of the stroke.
    static var tickOverhang: CGFloat { 4 }
    static var tickWidth: CGFloat { 2.5 }

    /// Angle in degrees for a fill fraction: 150° at 0, 390° at 1. Out-of-range clamps; non-finite is 0.
    static func angle(forFraction fraction: Double) -> Double {
        startDegrees + sweepDegrees * (NoopRing.clampedFraction(fraction) ?? 0)
    }

    /// Tick angles at the lower and upper ends of a target band.
    static func tickAngles(for band: ClosedRange<Double>) -> [Double] {
        [angle(forFraction: band.lowerBound), angle(forFraction: band.upperBound)]
    }

    /// Knob radius: the mockup's 7 pt on a 22 pt stroke, scaled with the stroke.
    static func knobRadius(lineWidth: CGFloat) -> CGFloat {
        lineWidth * 7 / 22
    }

    /// Point on the stroke centre line for a fraction.
    static func point(forFraction fraction: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        let radians = angle(forFraction: fraction) * .pi / 180
        return CGPoint(x: center.x + radius * CGFloat(cos(radians)), y: center.y + radius * CGFloat(sin(radians)))
    }

    /// The view's size: full width of the circle plus tick overhang, and from the top of the stroke (plus
    /// overhang) down to the rounded end caps at 150°/30°.
    static func frameSize(radius: CGFloat, lineWidth: CGFloat) -> CGSize {
        let top = radius + lineWidth / 2 + tickOverhang
        let endDrop = radius * CGFloat(sin(startDegrees * .pi / 180))   // sin 150° = 0.5
        let bottom = endDrop + max(lineWidth / 2, knobRadius(lineWidth: lineWidth))
        return CGSize(width: top * 2, height: top + bottom)
    }

    /// Circle centre inside `frameSize`.
    static func center(radius: CGFloat, lineWidth: CGFloat) -> CGPoint {
        let top = radius + lineWidth / 2 + tickOverhang
        return CGPoint(x: top, y: top)
    }
}

// MARK: - Shapes

/// The 240° arc, as a path the trim can animate along.
private struct GaugeArc: Shape {
    let center: CGPoint
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: center, radius: radius,
                    startAngle: .degrees(NoopArcGauge<EmptyView>.startDegrees),
                    endAngle: .degrees(NoopArcGauge<EmptyView>.endDegrees),
                    clockwise: false)
        return path
    }
}

/// The knob, animatable so it rides the fill.
private struct GaugeKnob: Shape {
    let center: CGPoint
    let radius: CGFloat
    let knobRadius: CGFloat
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let p = NoopArcGauge<EmptyView>.point(forFraction: fraction, center: center, radius: radius)
        return Path(ellipseIn: CGRect(x: p.x - knobRadius, y: p.y - knobRadius,
                                      width: knobRadius * 2, height: knobRadius * 2))
    }
}

/// Radial tick marks across the stroke at the given angles.
private struct GaugeTicks: Shape {
    let center: CGPoint
    let angles: [Double]
    let inner: CGFloat
    let outer: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for degrees in angles {
            let radians = degrees * .pi / 180
            let dx = CGFloat(cos(radians)), dy = CGFloat(sin(radians))
            path.move(to: CGPoint(x: center.x + inner * dx, y: center.y + inner * dy))
            path.addLine(to: CGPoint(x: center.x + outer * dx, y: center.y + outer * dy))
        }
        return path
    }
}

/// The built-in centre reads as one element (caption as label, number as value); custom centre content is
/// combined so its own text is read, with any caller overrides on top.
private struct GaugeAccessibility: ViewModifier {
    let builtIn: Bool
    let label: String?
    let value: String?

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: builtIn ? .ignore : .combine)
            .modifier(NoopAccessibilityText(label: label, value: value))
    }
}

#if DEBUG
#Preview("NoopArcGauge") {
    ScrollView {
        VStack(spacing: 32) {
            NoopArcGauge(value: 11.4 / 21, color: NoopTheme.strain, targetBand: 12.0 / 21...15.0 / 21,
                         number: "11.4", caption: "Strain · target 12–15")
            NoopArcGauge(value: 0.78, color: NoopTheme.recoveryColor(for: 78),
                         number: "78", caption: "Recovered")
            NoopArcGauge(value: nil, color: NoopTheme.recovery, number: "—", caption: "No data")
            NoopArcGauge(value: 0.3, color: NoopTheme.hrv, radius: 70, lineWidth: 14) {
                Image(systemName: "waveform.path.ecg").foregroundStyle(NoopTheme.hrv)
            }
        }
        .padding(24)
    }
    .background(NoopTheme.canvas)
    .preferredColorScheme(.dark)
}
#endif
