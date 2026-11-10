import SwiftUI
import StrandDesign

/// The scorecard's weekly curve (specification §10.2, `weekChart` in the round 6 design source): a
/// smooth line with a gradient fill and one point per weekly reading. There is no rule, no band and
/// no target line. A week with no reading breaks the line: it is never drawn across, and an open
/// ring on the time axis marks it.
///
/// The colour is neutral: weight and waist have no semantic colour.
struct ScorecardWeekChart: View {
    /// One per week shown. Nil is a week with no reading.
    let points: [Double?]
    let firstLabel: String
    let lastLabel: String
    var color: Color = NoopTheme.textPrimary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = NoopMotionState.shared
    @State private var reveal: CGFloat = 0
    @State private var areaOpacity: Double = 0

    private var plotHeight: CGFloat {
        points.compactMap { $0 }.count > 1 ? ScorecardLayout.chartHeight : ScorecardLayout.chartHeightSinglePoint
    }

    var body: some View {
        VStack(spacing: NoopTheme.Layout.s) {
            GeometryReader { geometry in
                plot(in: geometry.size)
            }
            .frame(height: plotHeight)
            HStack(alignment: .firstTextBaseline) {
                axisLabel(firstLabel)
                Spacer(minLength: NoopTheme.Layout.s)
                if points.count > 1 { axisLabel(lastLabel) }
            }
        }
        .onAppear(perform: play)
        .onChangeCompat(of: points) { _ in play() }
        .accessibilityHidden(true)
    }

    private func axisLabel(_ text: String) -> some View {
        Text(verbatim: text)
            .noopFont(.caption, color: false)
            .foregroundStyle(NoopTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Drawing

    private func plot(in size: CGSize) -> some View {
        let geometry = Geometry(points: points, size: size)
        return ZStack {
            ForEach(Array(geometry.runs.enumerated()), id: \.offset) { _, run in
                if run.count > 1 {
                    area(run, baseline: geometry.baseline)
                        .fill(LinearGradient(
                            colors: [color.opacity(ScorecardLayout.chartAreaOpacity), color.opacity(0)],
                            startPoint: .top, endPoint: .bottom))
                        .opacity(areaOpacity)
                    line(run)
                        .trim(from: 0, to: reveal)
                        .stroke(LinearGradient(
                                    colors: [color.opacity(ScorecardLayout.chartLineStartOpacity), color],
                                    startPoint: .leading, endPoint: .trailing),
                                style: StrokeStyle(lineWidth: ScorecardLayout.chartLine, lineCap: .round,
                                                   lineJoin: .round))
                }
            }
            // A week with no reading: an open ring on the time axis.
            ForEach(geometry.missing, id: \.self) { x in
                Circle()
                    .strokeBorder(NoopTheme.textTertiary, lineWidth: ScorecardLayout.chartPointBorder)
                    .frame(width: ScorecardLayout.chartPoint * 2, height: ScorecardLayout.chartPoint * 2)
                    .position(x: x, y: geometry.baseline - ScorecardLayout.chartPoint)
            }
            let all = geometry.runs.flatMap { $0 }
            ForEach(Array(all.enumerated()), id: \.offset) { index, point in
                let isLatest = index == all.count - 1
                let radius = isLatest ? ScorecardLayout.chartLatestPoint : ScorecardLayout.chartPoint
                ZStack {
                    if isLatest {
                        Circle()
                            .fill(color.opacity(ScorecardLayout.chartHaloOpacity))
                            .frame(width: ScorecardLayout.chartHalo * 2, height: ScorecardLayout.chartHalo * 2)
                    }
                    Circle()
                        .fill(color)
                        .overlay(Circle().strokeBorder(NoopTheme.cardSolid,
                                                       lineWidth: ScorecardLayout.chartPointBorder))
                        .frame(width: radius * 2, height: radius * 2)
                }
                .position(point)
                .opacity(areaOpacity)
            }
        }
    }

    /// The design source's curve: a cubic through each pair of points with tangents from their
    /// neighbours.
    private func line(_ run: [CGPoint]) -> Path {
        var path = Path()
        guard let first = run.first else { return path }
        path.move(to: first)
        for index in 0..<(run.count - 1) {
            let p0 = index > 0 ? run[index - 1] : run[index]
            let p1 = run[index]
            let p2 = run[index + 1]
            let p3 = index + 2 < run.count ? run[index + 2] : p2
            path.addCurve(
                to: p2,
                control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        return path
    }

    private func area(_ run: [CGPoint], baseline: CGFloat) -> Path {
        var path = line(run)
        guard let first = run.first, let last = run.last else { return path }
        path.addLine(to: CGPoint(x: last.x, y: baseline))
        path.addLine(to: CGPoint(x: first.x, y: baseline))
        path.closeSubpath()
        return path
    }

    // MARK: Motion

    /// The line draws left to right, then the fill and the points fade in. Under Reduce Motion, Low
    /// Power or quiet motion the settled chart shows at once.
    private func play() {
        guard !motion.poseStill(reduceMotion) else {
            var settled = Transaction()
            settled.disablesAnimations = true
            withTransaction(settled) {
                reveal = 1
                areaOpacity = 1
            }
            return
        }
        reveal = 0
        areaOpacity = 0
        withAnimation(NoopTheme.Motion.chartDraw) { reveal = 1 }
        withAnimation(NoopTheme.Motion.chartArea.delay(NoopTheme.Motion.chartAreaDelay)) { areaOpacity = 1 }
    }

    // MARK: Geometry

    /// Where each week sits. Pure: the same weeks in the same size give the same drawing.
    private struct Geometry {
        /// Unbroken stretches of weeks with a reading.
        var runs: [[CGPoint]] = []
        /// The x of each week with no reading.
        var missing: [CGFloat] = []
        var baseline: CGFloat

        init(points: [Double?], size: CGSize) {
            baseline = size.height
            let values = points.compactMap { $0 }
            guard let low = values.min(), let high = values.max(), size.width > 0, size.height > 0 else { return }
            let span = high - low == 0 ? 1 : high - low
            let floor = low - span * ScorecardLayout.chartPadding
            let ceiling = high + span * ScorecardLayout.chartPadding
            let inset = ScorecardLayout.chartInset
            let top = ScorecardLayout.chartHalo
            let bottom = size.height - ScorecardLayout.chartHalo
            let step = points.count > 1 ? (size.width - inset * 2) / CGFloat(points.count - 1) : 0
            var run: [CGPoint] = []
            for (index, value) in points.enumerated() {
                let x = inset + CGFloat(index) * step
                guard let value else {
                    if !run.isEmpty { runs.append(run) }
                    run = []
                    missing.append(x)
                    continue
                }
                let share = CGFloat((value - floor) / (ceiling - floor))
                run.append(CGPoint(x: x, y: top + (1 - share) * (bottom - top)))
            }
            if !run.isEmpty { runs.append(run) }
        }
    }
}
