#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

// Shared pieces for the redesigned Trends, Stress, Breathe, Journal and What-moves-you screens
// (`docs/personal/REDESIGN-IMPLEMENTATION.md` Phase 6, boards C2–C6 in `design/round3/sleep-health.html`).
// Presentation only: every figure drawn here is handed in by the screen, which reads it from the same
// state its classic layout uses. Nothing here computes a metric.

/// Geometry from `design/round3/sleep-health.html` that has no `NoopTheme` token.
enum InsightsLayout {
    /// C2 hero chart and the four small-multiple tiles.
    static let trendsHeroChart: CGFloat = 120
    static let trendsTileChart: CGFloat = 62
    /// C2 week-in-review rings.
    static let weekRing: CGFloat = 72
    /// C3 intraday line and history chart.
    static let stressDayChart: CGFloat = 120
    static let stressTrendChart: CGFloat = 140
    /// C3 level bar and its knob.
    static let levelBarHeight: CGFloat = 10
    static let levelKnob: CGFloat = 18
    static let levelKnobBorder: CGFloat = 4
    static let levelDimmed: Double = 0.35
    static let dot: CGFloat = 8
    /// C4 breathing orb: the stage height, the two discs and the contracted scale.
    static let orbStage: CGFloat = 340
    static let orbOuter: CGFloat = 270
    static let orbInner: CGFloat = 190
    static let orbContracted: CGFloat = 0.62
    static let orbOuterFill: Double = 0.42
    static let orbOuterEdge: Double = 0.08
    static let orbInnerFill: Double = 0.45
    static let orbInnerEdge: Double = 0.10
    static let orbBorder: Double = 0.45
    static let orbGradientEnd: Double = 0.7
    /// C6 diverging bars.
    static let divergingBarHeight: CGFloat = 8
    static let divergingRuleHeight: CGFloat = 20
    static let divergingRuleWidth: CGFloat = 1
    static let divergingMinWidth: CGFloat = 3
    static let divergingTrackWidth: CGFloat = 116
    static let mutedOpacity: Double = 0.6
    /// Stress line stroke and area.
    static let lineWidth: CGFloat = 2.5
    static let areaTop: Double = 0.42
    static let latestHalo: CGFloat = 14
    static let latestDot: CGFloat = 7
    static let haloOpacity: Double = 0.22
    /// C5 progress bar, stepper buttons and numeric field.
    static let progressHeight: CGFloat = 6
    static let stepperButton: CGFloat = 34
    static let numericField: CGFloat = 64
    /// Tinted call-to-action cards (C3 "Take three minutes", C6 "Try an experiment"): the domain colour at
    /// this opacity fading into the card surface.
    static let tintedCardOpacity: Double = 0.2
    static let tintedCardFadeStop: Double = 0.7
}

// MARK: - Headers

/// The screen title block under the navigation bar: a large title and an optional footnote sub-line, as in
/// the mockups' `.lt` / `.sub` rows.
struct InsightsScreenHeader: View {
    private let title: Text
    private let subtitle: Text?

    init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil) {
        self.title = Text(title)
        self.subtitle = subtitle.map { Text($0) }
    }

    init(titleText: Text, subtitleText: Text?) {
        self.title = titleText
        self.subtitle = subtitleText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
            title
                .noopFont(.largeTitle)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                subtitle
                    .noopFont(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, NoopTheme.Layout.sectionSide)
    }
}

/// A sentence-case section title with an optional trailing caption, for titles built at run time (the
/// design system's `NoopSectionHeader` takes a fixed key). Same 26 / 10 / 20 padding.
struct InsightsSectionTitle: View {
    private let title: Text
    private let trailing: String?

    init(_ title: LocalizedStringKey, trailing: String? = nil) {
        self.title = Text(title)
        self.trailing = trailing
    }

    init(titleText: Text, trailing: String? = nil) {
        self.title = titleText
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            title
                .noopFont(.sectionTitle)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: NoopTheme.Layout.s)
            if let trailing {
                Text(verbatim: trailing)
                    .noopFont(.footnote)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.top, NoopTheme.Layout.sectionTop)
        .padding(.bottom, NoopTheme.Layout.sectionBottom)
        .padding(.horizontal, NoopTheme.Layout.sectionSide)
    }
}

// MARK: - Ambient

extension View {
    /// A fixed ambient palette at the user's intensity.
    func insightsAmbient(_ preset: AmbientPreset, intensityRaw: String) -> some View {
        noopAmbientBackground(preset.blobs(intensity: AmbientIntensity(rawValue: intensityRaw) ?? .balanced))
    }

    /// A tinted call-to-action card surface: the domain colour washing into the glass card (C3, C6).
    func insightsTintedCard(_ color: Color) -> some View {
        background {
            LinearGradient(
                stops: [
                    .init(color: color.opacity(InsightsLayout.tintedCardOpacity), location: 0),
                    .init(color: .clear, location: InsightsLayout.tintedCardFadeStop),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: NoopTheme.Layout.cardRadius, style: .continuous))
        }
    }
}

// MARK: - Diverging bar (C6)

/// A bar growing left or right of a centre rule in proportion to `fraction` (−1…1). The centre rule is the
/// one vertical zero line; there is no horizontal gridline. `muted` dims a not-yet-significant effect.
struct InsightsDivergingBar: View {
    let fraction: Double
    let color: Color
    var muted: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    var body: some View {
        GeometryReader { geo in
            let half = geo.size.width / 2
            let clamped = fraction.isFinite ? min(max(fraction, -1), 1) : 0
            let length = max(InsightsLayout.divergingMinWidth, half * CGFloat(abs(clamped)))
            let shown = (grown || reduceMotion) ? length : 0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(NoopTheme.track)
                    .frame(height: InsightsLayout.divergingBarHeight)
                Capsule()
                    .fill(color.opacity(muted ? InsightsLayout.mutedOpacity : 1))
                    .frame(width: shown, height: InsightsLayout.divergingBarHeight)
                    .offset(x: clamped >= 0 ? half : half - shown)
                Rectangle()
                    .fill(NoopTheme.textTertiary)
                    .frame(width: InsightsLayout.divergingRuleWidth, height: geo.size.height)
                    .offset(x: half - InsightsLayout.divergingRuleWidth / 2)
            }
            .frame(height: geo.size.height)
        }
        .frame(height: InsightsLayout.divergingRuleHeight)
        .accessibilityHidden(true)
        .onAppear {
            guard !grown else { return }
            withAnimation(NoopTheme.Motion.resolved(NoopTheme.Motion.bar, reduceMotion: reduceMotion)) { grown = true }
        }
    }

    /// Each value as a share of the largest magnitude in the set, so the strongest row spans its half.
    static func fractions(_ values: [Double]) -> [Double] {
        let peak = values.filter(\.isFinite).map(abs).max() ?? 0
        guard peak > 0 else { return values.map { _ in 0 } }
        return values.map { $0.isFinite ? $0 / peak : 0 }
    }
}

// MARK: - Stress level bar (C3)

/// The 0–3 stress level on a green → amber → red track with a white knob. A nil level draws the track
/// dimmed and no knob, never a knob at zero.
struct InsightsStressLevelBar: View {
    /// 0…1 position on the track, or nil when there is no reading.
    let fraction: Double?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: [NoopTheme.recovery, NoopTheme.recoveryMid, NoopTheme.recoveryLow],
                                         startPoint: .leading, endPoint: .trailing))
                    .opacity(fraction == nil ? InsightsLayout.levelDimmed : 1)
                    .frame(height: InsightsLayout.levelBarHeight)
                if let fraction, fraction.isFinite {
                    let f = CGFloat(min(max(fraction, 0), 1))
                    Circle()
                        .fill(NoopTheme.knob)
                        .overlay(Circle().strokeBorder(NoopTheme.cardSolid, lineWidth: InsightsLayout.levelKnobBorder))
                        .frame(width: InsightsLayout.levelKnob, height: InsightsLayout.levelKnob)
                        .offset(x: f * (w - InsightsLayout.levelKnob))
                }
            }
            .frame(height: InsightsLayout.levelKnob)
        }
        .frame(height: InsightsLayout.levelKnob)
        .accessibilityHidden(true)
    }
}

// MARK: - Intraday stress line (C3)

/// Today's stress proxy on the fixed 0–3 scale, drawn run by run so an hour with no reading stays a gap
/// (the classic `DaytimeLoadLine` contract). Gradient-filled, no baseline rule, no gridlines.
struct InsightsStressDayLine: View {
    let points: [DaytimeStress.HourPoint]
    let color: Color

    /// Contiguous runs of scored points as (index, level). A nil level ends a run.
    static func scoredRuns(_ points: [DaytimeStress.HourPoint]) -> [[(index: Int, level: Double)]] {
        var out: [[(index: Int, level: Double)]] = []
        var run: [(index: Int, level: Double)] = []
        for (i, p) in points.enumerated() {
            guard let level = p.level, level.isFinite else {
                if !run.isEmpty { out.append(run); run = [] }
                continue
            }
            run.append((i, min(max(level, 0), 3)))
        }
        if !run.isEmpty { out.append(run) }
        return out
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let n = max(points.count, 1)
            let place: ((index: Int, level: Double)) -> CGPoint = { p in
                CGPoint(x: n <= 1 ? w / 2 : w * CGFloat(p.index) / CGFloat(n - 1),
                        y: h - h * CGFloat(p.level / 3))
            }
            let runs = Self.scoredRuns(points).map { $0.map(place) }
            ZStack {
                ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                    if run.count >= 2 {
                        Self.area(run, height: h)
                            .fill(LinearGradient(colors: [color.opacity(InsightsLayout.areaTop), color.opacity(0)],
                                                 startPoint: .top, endPoint: .bottom))
                        Self.line(run)
                            .stroke(color, style: StrokeStyle(lineWidth: InsightsLayout.lineWidth,
                                                              lineCap: .round, lineJoin: .round))
                    } else if let only = run.first {
                        Circle().fill(color)
                            .frame(width: InsightsLayout.latestDot, height: InsightsLayout.latestDot)
                            .position(only)
                    }
                }
                if let latest = runs.last?.last {
                    Circle().fill(color.opacity(InsightsLayout.haloOpacity))
                        .frame(width: InsightsLayout.latestHalo, height: InsightsLayout.latestHalo)
                        .position(latest)
                    Circle().fill(color)
                        .frame(width: InsightsLayout.latestDot, height: InsightsLayout.latestDot)
                        .position(latest)
                }
            }
        }
    }

    private static func line(_ pts: [CGPoint]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        for i in 1..<pts.count {
            let prev = pts[i - 1], cur = pts[i]
            let midX = (prev.x + cur.x) / 2
            path.addCurve(to: cur, control1: CGPoint(x: midX, y: prev.y), control2: CGPoint(x: midX, y: cur.y))
        }
        return path
    }

    private static func area(_ pts: [CGPoint], height: CGFloat) -> Path {
        var path = line(pts)
        if let first = pts.first, let last = pts.last {
            path.addLine(to: CGPoint(x: last.x, y: height))
            path.addLine(to: CGPoint(x: first.x, y: height))
            path.closeSubpath()
        }
        return path
    }
}

// MARK: - Breathing orb (C4)

/// Two concentric breath-coloured discs that expand with `progress` (0 contracted … 1 expanded). The
/// motion comes from the caller's state; when `still` is true (Reduce Motion, Low Power, quiet motion) the
/// discs hold a steady mid size and the phase word and haptics carry the pace.
struct InsightsBreathOrb<Center: View>: View {
    let progress: CGFloat
    let still: Bool
    @ViewBuilder let center: () -> Center

    private var scale: CGFloat {
        let p = still ? 0.5 : min(max(progress, 0), 1)
        return InsightsLayout.orbContracted + (1 - InsightsLayout.orbContracted) * p
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    stops: [.init(color: NoopTheme.breath.opacity(InsightsLayout.orbOuterFill), location: 0),
                            .init(color: NoopTheme.breath.opacity(InsightsLayout.orbOuterEdge),
                                  location: InsightsLayout.orbGradientEnd)],
                    center: .center, startRadius: 0, endRadius: InsightsLayout.orbOuter / 2))
                .overlay(Circle().strokeBorder(NoopTheme.breath.opacity(InsightsLayout.orbBorder), lineWidth: 1))
                .frame(width: InsightsLayout.orbOuter, height: InsightsLayout.orbOuter)
                .scaleEffect(scale)
            Circle()
                .fill(RadialGradient(
                    stops: [.init(color: NoopTheme.hrv.opacity(InsightsLayout.orbInnerFill), location: 0),
                            .init(color: NoopTheme.hrv.opacity(InsightsLayout.orbInnerEdge),
                                  location: InsightsLayout.orbGradientEnd)],
                    center: .center, startRadius: 0, endRadius: InsightsLayout.orbInner / 2))
                .frame(width: InsightsLayout.orbInner, height: InsightsLayout.orbInner)
                .scaleEffect(scale)
            center()
        }
        .frame(maxWidth: .infinity)
        .frame(height: InsightsLayout.orbStage)
    }
}

// MARK: - Toggle row

/// A settings-style row with a title, optional detail line and a switch, for glass list cards (C4).
struct InsightsToggleRow: View {
    let title: Text
    let detail: Text?
    @Binding var isOn: Bool
    var showsDivider: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            if showsDivider {
                Rectangle().fill(NoopTheme.separator).frame(height: 1).accessibilityHidden(true)
            }
            Toggle(isOn: $isOn) {
                VStack(alignment: .leading, spacing: NoopTheme.Layout.xs / 2) {
                    title.noopFont(.listTitle)
                    if let detail { detail.noopFont(.footnote) }
                }
            }
            .tint(NoopTheme.recovery)
            .padding(.vertical, NoopTheme.Layout.m)
            .frame(minHeight: NoopTheme.Layout.minTouchTarget)
        }
    }
}
// MARK: - Progress bar

/// A thin capsule progress bar on the track colour. A nil fraction draws the empty track only (never an
/// invented fill); the fill eases to its value unless Reduce Motion is on.
struct InsightsProgressBar: View {
    let fraction: Double?
    let color: Color
    var height: CGFloat = InsightsLayout.progressHeight

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(NoopTheme.track)
                if let fraction, fraction.isFinite {
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(min(max(fraction, 0), 1)))
                        .animation(NoopTheme.Motion.resolved(NoopTheme.Motion.bar, reduceMotion: reduceMotion),
                                   value: fraction)
                }
            }
        }
        .frame(height: height)
    }
}
#endif
