import StrandDesign
import SwiftUI
import WidgetKit

/// Home-screen widget: today's stress as the intraday curve the Stress screen draws (#2040).
///
/// Swift twin of the Android `StressGlanceWidget`, but the drawing is NOT a port. Glance compiles to
/// RemoteViews and cannot draw, so Android renders the curve to a Bitmap under a payload budget and a
/// reduced pixel depth, and has to composite every translucent colour by hand because 565 carries no
/// alpha. WidgetKit is SwiftUI: stroked `Path`s, resolution-independent, with real opacity. What IS
/// shared is `StressTrace` — the fixed domain, the gap rule, the band threshold and the tick choices —
/// because those are the same reading of the same day.
///
/// Honest-blank throughout, matching the twin: an unscored hour is a GAP rather than an interpolation,
/// an hour the motion gate masked gets a faint mark along the base instead of a score, and a day with
/// nothing scored shows no chart at all rather than a flat line at zero.
struct StressEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot?
}

struct StressProvider: TimelineProvider {
    func placeholder(in context: Context) -> StressEntry {
        StressEntry(date: Date(), snap: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (StressEntry) -> Void) {
        completion(StressEntry(date: Date(), snap: WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StressEntry>) -> Void) {
        let entry = StressEntry(date: Date(), snap: WidgetSnapshot.load())
        // Half an hour, where the heart-rate widget takes fifteen minutes. This curve gains at most one
        // point an hour, so a tighter net would spend budget on entries identical to the one before it.
        // The app reloads timelines when it scores an hour, so this is only the safety net for when it
        // is not running — and it also carries the card across midnight, when the day number changes and
        // yesterday's curve stops being drawn.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date())
            ?? Date().addingTimeInterval(1_800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

/// The curve: every contiguous run of scored hours as its own subpath.
///
/// Runs rather than one path because an unscored hour is a hole, and a line drawn across it would
/// invent a reading. When `filled` each run is closed to the baseline SEPARATELY, so the area cannot
/// spread under hours that were never scored, which would undo the gap the broken line exists to draw.
private struct StressCurveShape: Shape {
    let series: [StressPoint]
    let filled: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for run in StressTrace.segments(series, width: rect.width, height: rect.height) {
            guard let first = run.first else { continue }
            if run.count == 1 {
                // A run of one hour is not a line. A dot says "one scored hour"; an empty box says
                // "no data", and those are different things.
                guard !filled else { continue }
                let r: CGFloat = 2.5
                path.addEllipse(in: CGRect(x: max(first.x, r) - r, y: first.y - r,
                                           width: r * 2, height: r * 2))
                continue
            }
            path.move(to: CGPoint(x: first.x, y: first.y))
            for p in run.dropFirst() { path.addLine(to: CGPoint(x: p.x, y: p.y)) }
            if filled {
                path.addLine(to: CGPoint(x: run[run.count - 1].x, y: rect.maxY))
                path.addLine(to: CGPoint(x: first.x, y: rect.maxY))
                path.closeSubpath()
            }
        }
        return path
    }
}

/// The hours sitting in the HIGH band, dotted above the line as the screen marks them.
private struct StressHighDotsShape: Shape {
    let series: [StressPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r: CGFloat = 2
        for p in StressTrace.highPoints(series, width: rect.width, height: rect.height) {
            // Lifted clear of the stroke so a dot is never half-hidden under the line it marks.
            let y = max(p.y - 5, r)
            path.addEllipse(in: CGRect(x: min(max(p.x, r), rect.maxX - r) - r, y: y - r,
                                       width: r * 2, height: r * 2))
        }
        return path
    }
}

/// The stretches the motion gate masked, marked along the base rather than scored.
private struct StressMovingMarksShape: Shape {
    let series: [StressPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // A span arrives covering its hours edge to edge, so the only width left to decide is the
        // FLOOR, for a degenerate series with no width to spread across. It is the width the mark used
        // to have unconditionally, kept so the smallest mark is no less visible than before.
        let minWidth: CGFloat = 6
        let radius = rect.height / 2
        for span in StressTrace.movingSpans(series, width: rect.width) {
            let lo = min(max(span.lowerBound, 0), rect.width)
            let hi = min(max(span.upperBound, 0), rect.width)
            // Floored by GROWING right, then left if that ran into the edge, so a mark at either end
            // of the day keeps its width instead of being trimmed away by the box.
            let x1 = max(hi, min(lo + minWidth, rect.width))
            let x0 = min(lo, max(x1 - minWidth, 0))
            path.addRoundedRect(
                in: CGRect(x: x0, y: rect.minY, width: x1 - x0, height: rect.height),
                cornerSize: CGSize(width: radius, height: radius),
            )
        }
        return path
    }
}

struct StressWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StressEntry
    private let scaleWidth: CGFloat = 14
    private let scaleGap: CGFloat = NoopTheme.Layout.s

    /// Resolved on read, so a curve scored for a day that is over is dropped rather than drawn. Measured
    /// from `entry.date` rather than `Date()` because WidgetKit renders an entry at ITS date, which is
    /// the same reasoning the heart-rate widget's prune follows.
    private var series: [StressPoint] {
        entry.snap?.stressCurve(now: entry.date) ?? []
    }
    private var stats: StressTrace.Stats? { StressTrace.stats(series) }
    private var latestPoint: StressPoint? { series.last(where: { $0.level != nil }) }
    private var latest: Double? { latestPoint?.level }

    // R4-1's ramp, calm to tense: the Recovery band colours read the other way up (green low, red high).
    private var calm: Color { NoopTheme.recovery }
    private var steady: Color { NoopTheme.recoveryMid }
    private var tense: Color { NoopTheme.recoveryLow }

    /// Vertical, because `StressTrace.segments` maps the score onto Y off a FIXED domain: height already
    /// encodes level, so one top-to-bottom gradient paints every run the colour its own score deserves.
    private var rampGradient: LinearGradient {
        LinearGradient(colors: [tense, steady, calm], startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(title: "Stress", tint: NoopTheme.stress) {
                // The hour the number was scored for, which is the time the value carries.
                if let ts = latestPoint?.ts {
                    Text(WidgetStyle.timeLabel(Date(timeIntervalSince1970: TimeInterval(ts)), now: entry.date))
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline, spacing: NoopTheme.Layout.s) {
                WidgetNumber(value: latest.map { StressTrace.formatLevel($0) })
                if latest != nil {
                    Text("of 3").noopFont(.widgetCaption)
                }
                if family != .systemSmall, let stats, let peak = stats.peak.level {
                    // "Peak" is a catalog key; the value and the time are DATA, shown verbatim.
                    let peakTime = Date(timeIntervalSince1970: TimeInterval(stats.peak.ts))
                        .formatted(date: .omitted, time: .shortened)
                    // `Peak` and `avg %@` are both catalog keys; the separators carry nothing to translate.
                    HStack(spacing: NoopTheme.Layout.xs) {
                        Text("Peak")
                        Text(verbatim: StressTrace.formatLevel(peak) + " · " + peakTime + " · ")
                        Text("avg \(StressTrace.formatLevel(stats.mean))")
                    }
                    .noopFont(.widgetCaption)
                    .lineLimit(1)
                }
            }
            if family == .systemSmall {
                // R4-1 small: where the latest hour sits on the fixed 0–3 domain. Track alone when unscored.
                StressRangeBar(level: latest, colors: [calm, steady, tense])
                    .padding(.top, WidgetStyle.barGap)
            } else if stats != nil {
                HStack(alignment: .top, spacing: scaleGap) {
                    // The scale sits on the LEFT, where the Stress screen puts it. Fixed rather than
                    // derived, because that is what the domain is: an axis that moved with the day
                    // would make two days impossible to compare.
                    let ticks = StressTrace.levelTicks()
                    VStack(alignment: .trailing) {
                        ForEach(Array(ticks.enumerated()), id: \.offset) { index, tick in
                            Text(verbatim: "\(tick)")
                                .noopFont(.widgetCaption)
                            if index < ticks.count - 1 { Spacer(minLength: 0) }
                        }
                    }
                    .frame(width: scaleWidth)
                    StressCurveChart(series: series, ramp: rampGradient,
                                     fillTint: steady, dotTint: tense)
                }
                .padding(.top, NoopTheme.Layout.s)
                StressTimeAxis(series: series)
                    .padding(.leading, scaleWidth + scaleGap)
            }
        }
        .padding(WidgetStyle.padding)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    /// One spoken sentence rather than a run of loose numbers, the same choice the heart-rate widget
    /// makes. `String(localized:)` rather than bare literals: the audit matches a literal sitting
    /// immediately after `.accessibilityLabel(`, and this is a computed property, so hardcoded English
    /// here would ship to every locale with the gate green.
    private var accessibilityText: String {
        guard let latest else { return String(localized: "Stress, no reading today") }
        let now = StressTrace.formatLevel(latest)
        guard let stats, let peak = stats.peak.level else {
            return String(localized: "Stress \(now) of 3")
        }
        let peakText = StressTrace.formatLevel(peak)
        let meanText = StressTrace.formatLevel(stats.mean)
        return String(localized: "Stress \(now) of 3, average \(meanText), peak \(peakText)")
    }
}

/// R4-1's stress bar: the calm-to-tense ramp across the fixed 0–3 domain, with a white knob at the
/// latest scored hour. No knob when nothing is scored, so an empty day is not drawn as a calm zero.
private struct StressRangeBar: View {
    let level: Double?
    let colors: [Color]
    private let knob: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(height: WidgetStyle.barHeight)
                if let level {
                    let x = geo.size.width * CGFloat(min(max(level / StressTrace.domainMax, 0), 1))
                    Circle()
                        .fill(NoopTheme.knob)
                        .frame(width: knob, height: knob)
                        .offset(x: min(max(x - knob / 2, 0), geo.size.width - knob))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: knob)
    }
}

/// The chart: fill, stroke, high-band dots, and the movement strip beneath them.
///
/// The marks get their OWN row rather than a reserved band inside the chart's coordinate space. The
/// Glance twin has to carve the band out of one bitmap and normalise around it, which is exactly where
/// that side went wrong once; here a `VStack` gives each part its own rect and the arithmetic
/// disappears.
private struct StressCurveChart: View {
    let series: [StressPoint]
    let ramp: LinearGradient
    let fillTint: Color
    let dotTint: Color

    private var hasMarks: Bool { series.contains(where: \.moving) }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                StressCurveShape(series: series, filled: true)
                    .fill(LinearGradient(
                        colors: [fillTint.opacity(0.3), fillTint.opacity(0)],
                        startPoint: .top, endPoint: .bottom,
                    ))
                StressCurveShape(series: series, filled: false)
                    .stroke(ramp, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                StressHighDotsShape(series: series)
                    .fill(dotTint)
            }
            if hasMarks {
                StressMovingMarksShape(series: series)
                    .fill(WidgetStyle.headerTrailing)
                    .frame(height: 3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct StressTimeAxis: View {
    let series: [StressPoint]

    var body: some View {
        let ticks = StressTrace.timeTicks(series)
        // One instant pinned to the left edge reads as a stray rather than an axis, so it waits for a
        // span to label, matching the twin.
        if ticks.count >= 2 {
            HStack {
                ForEach(Array(ticks.enumerated()), id: \.offset) { i, ts in
                    Text(Date(timeIntervalSince1970: TimeInterval(ts)),
                         format: .dateTime.hour().minute())
                        .noopFont(.widgetCaption)
                    if i < ticks.count - 1 { Spacer(minLength: 0) }
                }
            }
        }
    }
}

struct StressWidget: Widget {
    static let kind = "StressWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: StressProvider()) { entry in
            if #available(iOS 17.0, *) {
                StressWidgetView(entry: entry)
                    .containerBackground(WidgetStyle.background, for: .widget)
            } else {
                StressWidgetView(entry: entry)
                    .background(WidgetStyle.background)
            }
        }
        .configurationDisplayName("Stress")
        .description("Today's stress as an hour-by-hour curve.")
        // systemSmall added for R4-1 (latest hour on the 0–3 bar); systemMedium keeps the curve.
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
