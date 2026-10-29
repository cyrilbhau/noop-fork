import SwiftUI

/// The redesign's score ring (`docs/personal/REDESIGN-IMPLEMENTATION.md` §3.6 item 1, visual reference
/// `ring()` in `design/system/noop.js`). A full circle starting at 12 o'clock with round caps over a
/// `NoopTheme.track` track. Used from 30 pt (week strip) to 230 pt (live HR).
///
/// A missing value (`nil`, NaN or infinite) draws a dashed track at 45 % of the line width and never
/// animates: no fill and no count-up for data that is absent (§3.5). A present value fills 0→value with
/// `NoopTheme.Motion.ringFill` on every appearance and every change when `animate` is true; callers pass
/// `NoopTheme.Motion.ringsAnimate(reduceMotion:fillOnLoad:)`. Under Reduce Motion the ring appears filled
/// with a 0.15 s fade regardless of `animate`.
public struct NoopRing: View {
    let fraction: Double?
    let color: Color
    let lineWidth: CGFloat
    let diameter: CGFloat
    let label: String?
    let unit: String?
    let icon: String?
    let animate: Bool
    let accessibilityName: String?
    let accessibilityValueText: String?

    /// - Parameters:
    ///   - value: fill fraction 0…1; `nil` (or NaN/infinite) is the missing state. Out-of-range values clamp.
    ///   - lineWidth: stroke width; `nil` uses `defaultLineWidth(diameter:)` (the mockup's 7 % of the size).
    ///   - label: text inside the ring, already formatted by the caller ("78", "11.6", "—"). A purely
    ///     numeric label counts up from zero alongside the fill.
    ///   - unit: smaller secondary suffix after the label ("%").
    ///   - icon: SF Symbol name drawn in `color` (above the label when both are given).
    ///   - accessibilityLabel / accessibilityValue: VoiceOver overrides. The value defaults to label + unit;
    ///     callers should pass a localized "No data" for a missing ring.
    public init(
        value: Double?,
        color: Color,
        lineWidth: CGFloat? = nil,
        diameter: CGFloat,
        label: String? = nil,
        unit: String? = nil,
        icon: String? = nil,
        animate: Bool = true,
        accessibilityLabel: String? = nil,
        accessibilityValue: String? = nil
    ) {
        self.fraction = Self.clampedFraction(value)
        self.color = color
        self.lineWidth = lineWidth ?? Self.defaultLineWidth(diameter: diameter)
        self.diameter = diameter
        self.label = label
        self.unit = unit
        self.icon = icon
        self.animate = animate
        self.accessibilityName = accessibilityLabel
        self.accessibilityValueText = accessibilityValue
    }

    public var body: some View {
        NoopFillAnimator(target: fraction, animate: animate) { shown, revealed in
            ZStack {
                if fraction == nil {
                    Circle()
                        .inset(by: lineWidth / 2)
                        .stroke(NoopTheme.trackEmpty,
                                style: StrokeStyle(lineWidth: Self.missingLineWidth(lineWidth: lineWidth),
                                                   dash: Self.dashPattern(diameter: diameter)))
                } else {
                    Circle()
                        .inset(by: lineWidth / 2)
                        .stroke(NoopTheme.track, lineWidth: lineWidth)
                    Circle()
                        .inset(by: lineWidth / 2)
                        .trim(from: 0, to: shown)
                        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                centre(revealed: revealed)
            }
            .frame(width: diameter, height: diameter)
        }
        .accessibilityElement(children: .ignore)
        .modifier(NoopAccessibilityText(label: accessibilityName, value: resolvedAccessibilityValue))
    }

    @ViewBuilder
    private func centre(revealed: Bool) -> some View {
        let missing = fraction == nil
        VStack(spacing: diameter * 0.02) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: diameter * (label == nil ? Self.iconAloneScale : Self.iconWithLabelScale),
                                  weight: .semibold))
                    .foregroundStyle(missing ? NoopTheme.textTertiary : color)
            }
            if let label, !label.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(displayLabel(label, revealed: revealed))
                        .font(NoopType.ringLabelFont(diameter: diameter))
                        .foregroundStyle(missing ? NoopTheme.textTertiary : NoopTheme.textPrimary)
                        .modifier(NumericTextTransition())
                    if let unit, !unit.isEmpty {
                        Text(unit)
                            .font(NoopType.ringUnitFont(diameter: diameter))
                            .foregroundStyle(NoopTheme.textSecondary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            }
        }
        .frame(maxWidth: max(0, diameter - lineWidth * 2.4))
    }

    /// The zeroed label while the fill is still pending, so the number rolls up with the ring.
    private func displayLabel(_ label: String, revealed: Bool) -> String {
        guard !revealed, fraction != nil, let zero = Self.countUpStartLabel(label) else { return label }
        return zero
    }

    private var resolvedAccessibilityValue: String? {
        if let accessibilityValueText { return accessibilityValueText }
        guard let label, !label.isEmpty else { return nil }
        return label + (unit ?? "")
    }

    // MARK: - Geometry (pure, unit-tested)

    /// Ratio of the dashed missing-state stroke to the normal line width.
    public static let missingWidthRatio: CGFloat = 0.45
    /// Icon size as a fraction of the diameter, alone and above a label.
    static let iconAloneScale: CGFloat = 0.28
    static let iconWithLabelScale: CGFloat = 0.18

    /// The fill fraction to draw: `nil` for a missing value (nil, NaN or infinite), otherwise clamped to 0…1.
    public static func clampedFraction(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return min(max(value, 0), 1)
    }

    /// The mockup's default stroke: 7 % of the ring size, never thinner than 3 pt.
    public static func defaultLineWidth(diameter: CGFloat) -> CGFloat {
        max(3, diameter * 0.07)
    }

    public static func missingLineWidth(lineWidth: CGFloat) -> CGFloat {
        lineWidth * missingWidthRatio
    }

    /// Dash/gap for the missing-state track: the mockup's 3/5 per 100 units, with floors so a 30 pt ring
    /// still reads as dashed.
    public static func dashPattern(diameter: CGFloat) -> [CGFloat] {
        [max(1.5, diameter * 0.03), max(2.5, diameter * 0.05)]
    }

    /// The zero form of a purely numeric label ("78" → "0", "11.6" → "0.0", "4,5" → "0,0"), used as the
    /// count-up start. `nil` (no count-up) for anything else: text, durations ("7h 42m"), signs, or grouped
    /// thousands ("1,234"), where a zero would misrepresent the format.
    public static func countUpStartLabel(_ label: String) -> String? {
        func digitsOnly(_ s: Substring) -> Bool { !s.isEmpty && s.allSatisfy { $0.isASCII && $0.isNumber } }
        let separator: Character? = label.contains(".") ? "." : (label.contains(",") ? "," : nil)
        guard let separator else { return digitsOnly(label[...]) ? "0" : nil }
        let parts = label.split(separator: separator, omittingEmptySubsequences: false)
        guard parts.count == 2, digitsOnly(parts[0]), digitsOnly(parts[1]) else { return nil }
        // Three digits after a comma is a thousands group, not decimals.
        if separator == ",", parts[1].count > 2 { return nil }
        return "0" + String(separator) + String(repeating: "0", count: parts[1].count)
    }
}

// MARK: - Shared fill driver

/// Drives a ring or arc fill: 0→target with `NoopTheme.Motion.ringFill` on every appearance and target
/// change, a count-up flag animated with `NoopTheme.Motion.countUp`, a light haptic when the fill settles,
/// and the Reduce Motion fallback (filled at once, 0.15 s fade). A `nil` target never animates.
/// `content` receives the trim fraction to draw and whether the final label should be shown.
struct NoopFillAnimator<Content: View>: View {
    let target: Double?
    let animate: Bool
    let content: (_ shown: Double, _ revealed: Bool) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double
    @State private var revealed: Bool
    @State private var appeared = false
    @State private var settleCount = 0
    /// Bumped on every run so a superseded fill neither starts late nor fires a haptic.
    @State private var generation = 0

    init(target: Double?, animate: Bool,
         @ViewBuilder content: @escaping (_ shown: Double, _ revealed: Bool) -> Content) {
        self.target = target
        self.animate = animate
        self.content = content
        _shown = State(initialValue: animate ? 0 : (target ?? 0))
        _revealed = State(initialValue: !animate || target == nil)
    }

    var body: some View {
        content(shown, revealed)
            .opacity(reduceMotion && !appeared ? 0 : 1)
            .onAppear {
                if reduceMotion {
                    withAnimation(NoopTheme.Motion.reduced) { appeared = true }
                } else {
                    appeared = true
                }
                run()
            }
            .onDisappear { generation += 1 }
            .onChangeCompat(of: target) { _ in run() }
            .strandHaptic(.light, trigger: settleCount)
    }

    private func run() {
        generation += 1
        let gen = generation
        var instant = Transaction()
        instant.disablesAnimations = true

        guard let target else {
            withTransaction(instant) { shown = 0; revealed = true }
            return
        }
        guard animate, !reduceMotion else {
            withTransaction(instant) { shown = target; revealed = true }
            return
        }
        // Reset to empty in its own transaction, then fill on the next turn so the spring always starts
        // from zero rather than from whatever was on screen.
        withTransaction(instant) { shown = 0; revealed = false }
        DispatchQueue.main.async {
            guard gen == generation else { return }
            if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
                withAnimation(NoopTheme.Motion.ringFill) {
                    shown = target
                } completion: {
                    if gen == generation { settleCount += 1 }
                }
            } else {
                withAnimation(NoopTheme.Motion.ringFill) { shown = target }
            }
            withAnimation(NoopTheme.Motion.countUp) { revealed = true }
        }
    }
}

/// `.contentTransition(.numericText())` so label digits roll when they change inside an animation. The
/// package floor (iOS 16 / macOS 13 / watchOS 10) already covers the API, so no availability check.
struct NumericTextTransition: ViewModifier {
    func body(content: Content) -> some View {
        content.contentTransition(.numericText())
    }
}

/// Applies VoiceOver label/value only when the caller provided them.
struct NoopAccessibilityText: ViewModifier {
    let label: String?
    let value: String?

    func body(content: Content) -> some View {
        switch (label, value) {
        case let (label?, value?): content.accessibilityLabel(Text(label)).accessibilityValue(Text(value))
        case let (label?, nil): content.accessibilityLabel(Text(label))
        case let (nil, value?): content.accessibilityValue(Text(value))
        case (nil, nil): content
        }
    }
}

#if DEBUG
#Preview("NoopRing") {
    VStack(spacing: 28) {
        HStack(spacing: 24) {
            NoopRing(value: 0.86, color: NoopTheme.sleep, diameter: 96, label: "86", unit: "%")
            NoopRing(value: 0.78, color: NoopTheme.recoveryColor(for: 78), diameter: 96, label: "78", unit: "%")
            NoopRing(value: 11.4 / 21, color: NoopTheme.strain, diameter: 96, label: "11.4")
        }
        HStack(spacing: 24) {
            NoopRing(value: nil, color: NoopTheme.recovery, diameter: 96, label: "—")
            NoopRing(value: 0.4, color: NoopTheme.heart, diameter: 96, icon: "heart.fill")
            ForEach(0..<5) { i in
                NoopRing(value: Double(i) / 4, color: NoopTheme.recoveryColor(for: i * 25), diameter: 30)
            }
        }
        NoopRing(value: 0.62, color: NoopTheme.heart, lineWidth: 14, diameter: 230, label: "72", unit: "bpm")
    }
    .padding(32)
    .background(NoopTheme.canvas)
    .preferredColorScheme(.dark)
}
#endif
