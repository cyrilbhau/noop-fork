import WidgetKit
import SwiftUI
import StrandDesign

/// Timeline entry backed by the latest `WidgetSnapshot` the app published into the App Group.
struct NOOPEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct NOOPProvider: TimelineProvider {
    func placeholder(in context: Context) -> NOOPEntry {
        NOOPEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (NOOPEntry) -> Void) {
        let fallback: WidgetSnapshot = context.isPreview ? .placeholder : .unavailable
        completion(NOOPEntry(date: Date(), snapshot: WidgetSnapshot.load() ?? fallback))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NOOPEntry>) -> Void) {
        // Gallery previews use `placeholder(in:)` / getSnapshot's preview branch. A real timeline
        // with no shared snapshot must show missing data honestly, never plausible sample numbers.
        let snap = WidgetSnapshot.load() ?? .unavailable
        // Refresh roughly every 15 minutes; the app also forces a reload when it publishes fresh data.
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [NOOPEntry(date: Date(), snapshot: snap)], policy: .after(next)))
    }
}

/// The glanceable score widget, with static ambient artwork on Home Screen families.
///
/// One idea per family: systemSmall is Recovery alone, systemMedium is the Today trio (Sleep · Recovery ·
/// Strain) as gradient rings, systemLarge adds the vitals grid. Lock Screen: a Recovery capacity gauge, the
/// "Recovery 68% · HRV 62 · Sleep 7h 42m" rectangle and an inline line. Every value carries the time the app
/// last published it, and a missing score is a dash over an empty track, never a zero.
struct NOOPWidgetView: View {
    @Environment(\.widgetFamily) private var family
    /// `.fullColor` on the home screen and in the gallery; `.vibrant` or `.accented` on the lock screen,
    /// where the system desaturates any colour it is handed. The accessory cells check this rather than
    /// tinting unconditionally.
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: NOOPEntry

    private var snap: WidgetSnapshot { entry.snapshot }

    var body: some View {
        switch family {
        case .accessoryCircular:
            recoveryGauge
        case .accessoryInline:
            inline
        case .accessoryRectangular:
            rectangular
        case .systemLarge:
            large
        case .systemMedium:
            medium
        default:
            // systemSmall (and any future compact family)
            small
        }
    }

    // MARK: - Values

    /// Recovery's colour comes from its band (`NoopTheme.recoveryColor`, thresholds 34 / 67); grey when unscored.
    private var recoveryTint: Color {
        snap.recovery.map { NoopTheme.recoveryColor(for: $0) } ?? NoopTheme.textTertiary
    }

    /// Strain read-out: the pre-formatted #313 display (0–21 or 0–100, per the app's setting) when present,
    /// else the whole-number 0–100 value.
    private var strainText: String? {
        snap.effortDisplay ?? snap.effort.map(String.init)
    }

    /// When the app last published, or nil before it ever has. Live pushes move it too, so it is labelled
    /// "Updated", not presented as the time a score was computed.
    private var updated: Date? {
        snap.updated == .distantPast ? nil : snap.updated
    }

    private var sleep: PersonalSleepReading? {
        snap.personal?.recentSleep(now: entry.date)
    }

    /// "58 bpm": "bpm" is the same in every locale the catalogs carry.
    private func bpmText(_ bpm: Int) -> String { String(bpm) + " " + "bpm" }

    /// The band's word under the Recovery number, from keys the catalogs already carry.
    private func bandKey(_ score: Int) -> LocalizedStringKey {
        switch NoopTheme.recoveryBand(for: Double(score)) {
        case .low: return "Low"
        case .mid: return "Moderate"
        case .high: return "High"
        }
    }

    // MARK: - Lock Screen accessories

    /// R4-2 circular gauge: a capacity ring with the number in the middle. No score leaves the ring empty
    /// and the centre a dash.
    private var recoveryGauge: some View {
        Gauge(value: Double(snap.recovery ?? 0), in: 0...100) {
            Text("Recovery")
        } currentValueLabel: {
            Text(verbatim: snap.recovery.map(String.init) ?? "—")
                .font(WidgetStyle.numberFont(size: NoopType.rowNumber.size))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(renderingMode == .fullColor ? recoveryTint : .primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Recovery"))
        .accessibilityValue(Text(verbatim: snap.recovery.map { "\($0)%" } ?? "—"))
    }

    private var inline: some View {
        Group {
            if let r = snap.recovery {
                Text("Recovery") + Text(verbatim: " " + String(r) + "%" + (snap.bpm.map { " · " + bpmText($0) } ?? ""))
            } else if let b = snap.bpm {
                Text(verbatim: bpmText(b))
            } else {
                Text(verbatim: "NOOP")
            }
        }
    }

    /// R4-2 rectangle: "Recovery 68%" over "HRV 62 · Sleep 7h 42m", then when it was published. Plain
    /// primary/secondary styles, because the lock screen maps those two levels onto the wallpaper and turns
    /// any domain colour into a grey nobody chose.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            (Text("Recovery") + Text(verbatim: " " + (snap.recovery.map { "\($0)%" } ?? "—")))
                .noopFont(.rowTitle, color: false)
                .foregroundStyle(.primary)
            (Text(verbatim: "HRV") + Text(verbatim: " " + (snap.hrv.map(String.init) ?? "—") + " · ")
             + Text("Sleep")
             + Text(verbatim: " ")
             + (sleep.map { WidgetStyle.durationText(minutes: $0.asleepMinutes) } ?? Text(verbatim: "—")))
                .noopFont(.widgetCaption, color: false)
                .foregroundStyle(.secondary)
            if let updated {
                Text("Updated \(WidgetStyle.timeLabel(updated, now: entry.date))")
                    .noopFont(.widgetCaption, color: false)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Home Screen

    /// R4-1 small: Recovery alone — the number, its band, a thin ring.
    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(title: "Recovery", tint: recoveryTint, trailingColor: NoopWidgetArt.timestamp) {
                if let updated { Text(WidgetStyle.timeLabel(updated, now: entry.date)) }
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: NoopTheme.Layout.s) {
                VStack(alignment: .leading, spacing: WidgetStyle.captionGap) {
                    WidgetNumber(value: snap.recovery.map(String.init), unit: "%")
                    Group {
                        if let r = snap.recovery { Text(bandKey(r)) } else { Text("No data") }
                    }
                    .noopFont(.widgetCaption, color: false)
                    .foregroundStyle(NoopWidgetArt.caption)
                }
                Spacer(minLength: 0)
                NoopWidgetScoreRing(fraction: snap.recovery.map { Double($0) / 100 }, tint: recoveryTint,
                                    diameter: NoopWidgetArt.smallRing, lineWidth: NoopWidgetArt.ringWidth,
                                    decorated: renderingMode == .fullColor)
                    .padding(.bottom, NoopTheme.Layout.xs)
                    .accessibilityHidden(true)
            }
        }
        .padding(WidgetStyle.padding)
    }

    /// The Today trio over a compact version of the app's ambient field.
    private var medium: some View {
        VStack(alignment: .leading, spacing: 0) {
            todayHeader
            Spacer(minLength: 0)
            scoreRings(diameter: NoopWidgetArt.mediumRing, lineWidth: NoopWidgetArt.ringWidth)
        }
        .padding(WidgetStyle.padding)
    }

    /// Large: the trio, then the vitals grid (HRV, resting HR, live HR, strap battery).
    private var large: some View {
        VStack(alignment: .leading, spacing: NoopTheme.Layout.l) {
            todayHeader
            scoreRings(diameter: NoopWidgetArt.largeRing, lineWidth: NoopWidgetArt.largeRingWidth)
            Rectangle().fill(NoopTheme.separator).frame(height: 1)
            HStack(alignment: .top, spacing: 0) {
                widgetStatCell("HRV", value: snap.hrv.map { "\($0)" }, unit: "ms",
                         name: "Heart rate variability",
                         spoken: snap.hrv.map { "\($0) milliseconds" })
                widgetStatCell("Rest HR", value: snap.restingHr.map { "\($0)" }, unit: "bpm",
                         name: "Resting heart rate",
                         spoken: snap.restingHr.map { "\($0) beats per minute" })
                widgetStatCell("Heart rate", value: snap.bpm.map { "\($0)" }, unit: "bpm",
                         name: "Heart rate",
                         spoken: snap.bpm.map { "\($0) beats per minute" })
                widgetStatCell("Battery", value: snap.batteryPct.map { "\($0)" }, unit: "%",
                         name: "Strap battery",
                         spoken: snap.batteryPct.map { "\($0) percent" })
            }
            Spacer(minLength: 0)
        }
        .padding(WidgetStyle.padding)
    }

    private var todayHeader: some View {
        HStack(spacing: NoopTheme.Layout.s) {
            Text("Today")
                .noopFont(.rowTitle)
            Spacer(minLength: 0)
            if let updated {
                Text("Updated \(WidgetStyle.timeLabel(updated, now: entry.date))")
                    .noopFont(.widgetCaption, color: false)
                    .foregroundStyle(NoopWidgetArt.timestamp)
                    .minimumScaleFactor(0.8)
            }
        }
        .lineLimit(1)
    }

    /// Order is the round-4 trio: Sleep · Recovery · Strain. Each cell is a dash over an empty track until scored.
    private func scoreRings(diameter: CGFloat, lineWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            scoreCell(label: "Sleep", text: snap.rest.map(String.init),
                      fraction: snap.rest.map { Double($0) / 100 },
                      tint: NoopTheme.sleep, outOf: 100, diameter: diameter, lineWidth: lineWidth)
            scoreCell(label: "Recovery", text: snap.recovery.map(String.init),
                      fraction: snap.recovery.map { Double($0) / 100 },
                      tint: recoveryTint, outOf: 100, diameter: diameter, lineWidth: lineWidth)
            // Fill is always the stored 0–100 axis so WHOOP 0–21 and native 0–100 agree on arc length.
            scoreCell(label: "Strain", text: strainText,
                      fraction: snap.effort.map { Double($0) / 100 },
                      tint: NoopTheme.strain, outOf: (snap.effortWhoop == true) ? 21 : 100,
                      diameter: diameter, lineWidth: lineWidth)
        }
        .frame(maxWidth: .infinity)
    }

    private func scoreCell(label: LocalizedStringKey, text: String?, fraction: Double?, tint: Color, outOf: Int,
                           diameter: CGFloat, lineWidth: CGFloat) -> some View {
        VStack(spacing: NoopTheme.Layout.s) {
            ZStack {
                NoopWidgetScoreRing(fraction: fraction, tint: tint, diameter: diameter, lineWidth: lineWidth,
                                    decorated: renderingMode == .fullColor)
                Text(verbatim: text ?? "—")
                    .font(WidgetStyle.numberFont(size: diameter * 0.4))
                    .tracking(NoopType.widgetNumber.tracking * diameter / 100)
                    .foregroundStyle(text == nil ? NoopTheme.textTertiary : NoopTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, lineWidth + 2)
            }
            Text(label)
                .noopFont(.widgetLabel, color: false)
                .foregroundStyle(NoopWidgetArt.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(text.map { "\($0) out of \(outOf)" } ?? "No data"))
    }

    /// One labelled stat in the large grid: a light value with its unit, the label under it.
    ///
    /// `name` and `spoken` exist because the on-screen label is abbreviated for width and the unit is a
    /// separate view: collapsing to one element lets the cell speak "Heart rate variability, 64 milliseconds".
    private func widgetStatCell(_ label: LocalizedStringKey, value: String?, unit: String,
                          name: LocalizedStringKey, spoken: String?) -> some View {
        VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(verbatim: value ?? "—")
                    .font(WidgetStyle.numberFont(size: NoopType.statNumber.size))
                    .tracking(NoopType.widgetNumber.tracking / 2)
                    .foregroundStyle(value == nil ? NoopTheme.textTertiary : NoopTheme.textPrimary)
                if value != nil {
                    Text(verbatim: unit)
                        .noopFont(.widgetCaption)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Text(label)
                .noopFont(.widgetCaption)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(name))
        .accessibilityValue(Text(spoken ?? "No data"))
    }
}

struct NOOPWidget: Widget {
    let kind = "NOOPWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NOOPProvider()) { entry in
            if #available(iOS 17.0, *) {
                NOOPWidgetView(entry: entry)
                    .containerBackground(for: .widget) { ScoreWidgetBackground(snapshot: entry.snapshot) }
            } else {
                NOOPWidgetView(entry: entry)
                    .background(WidgetStyle.background)
            }
        }
        .configurationDisplayName("NOOP")
        .description("Recovery, Strain and Sleep as score rings, plus live HR and strap battery at a glance.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryInline, .accessoryRectangular
        ])
        // The round-4 layouts carry their own 18 pt padding (`WidgetStyle.padding`) on the Home Screen
        // families; the Lock Screen accessories have no system margin to lose.
        .contentMarginsDisabled()
    }
}

/// WidgetKit owns background removal and tinting. Artwork is only meaningful in full colour;
/// the Lock Screen and tinted Home Screen keep the system's simpler treatment.
struct ScoreWidgetBackground: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let snapshot: WidgetSnapshot

    var body: some View {
        if renderingMode == .fullColor && (family == .systemSmall || family == .systemMedium || family == .systemLarge) {
            NoopWidgetBackdrop(colors: colors)
        } else {
            WidgetStyle.background
        }
    }

    private var colors: [Color] {
        let recovery = snapshot.recovery.map { NoopTheme.recoveryColor(for: $0) } ?? NoopTheme.textTertiary
        if family == .systemSmall { return [recovery] }
        return [snapshot.rest == nil ? NoopTheme.textTertiary : NoopTheme.sleep,
                recovery,
                snapshot.effort == nil ? NoopTheme.textTertiary : NoopTheme.strain]
    }
}

// MARK: - Shared round-4 widget pieces

/// Round-4 surface values for widgets and Live Activities (`design/round4/system.html`, R4-1…R4-4).
///
/// Everything colour- and type-shaped comes from `NoopTheme` / `NoopType` in StrandDesign, which this
/// extension links. The few white-alpha levels below are the R4-1/R4-2 CSS values that have no in-app
/// equivalent (widgets are deliberately lighter than in-app cards), kept here in one place rather than in
/// the views.
enum WidgetStyle {
    /// R4-1: 18 pt padding on every Home Screen widget and Lock Screen banner.
    static let padding: CGFloat = NoopTheme.Layout.cardPadding
    /// The widget body. Opaque: a widget cannot blur the wallpaper the way the mockup's glass does.
    static let background = NoopTheme.cardSolid
    /// The Lock Screen Live Activity banner (`.livebanner`: rgba(20,20,24,.78)).
    static let activityBackground = NoopTheme.cardSolid.opacity(0.78)
    /// The header's right-hand time/source label (`.wg .h span:last-child`).
    static let headerTrailing = Color.white.opacity(0.38)
    /// Ring captions and the strongest secondary label (`rgba(255,255,255,.72)`).
    static let ringLabel = Color.white.opacity(0.72)
    /// Thin progress-bar track (`.thin`).
    static let barTrack = Color.white.opacity(0.10)
    static let barHeight: CGFloat = 4
    /// Gap between a big number and its caption (`.wg .c { margin-top: 6px }`).
    static let captionGap: CGFloat = 6
    /// Gap above a thin bar (`margin-top: 12px`).
    static let barGap: CGFloat = NoopTheme.Layout.m
    /// Inactive zone segments (R4-2 `opacity:.3`).
    static let zoneDim: Double = 0.3

    /// A light numeral at a ramp size — the widget weight (`NoopType.widgetNumber`) at a smaller step,
    /// for values that sit beside or inside other marks.
    static func numberFont(size: CGFloat) -> Font {
        Font.system(size: size, weight: NoopType.widgetNumber.weight, design: .default).monospacedDigit()
    }

    /// "6:12 AM" for a time today, "Tue 6:12 AM" otherwise, so a value from another day says so.
    static func timeLabel(_ date: Date, now: Date) -> String {
        Calendar.current.isDate(date, inSameDayAs: now)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    /// "7h 42m", localized by Foundation (no catalog key), with the unit runs drawn smaller and dimmer
    /// (`.wg .n small`). Applied over the caller's number font, which styles the digits.
    static func durationText(minutes: Int, unitsSmall: Bool = false) -> Text {
        let style = Duration.UnitsFormatStyle(allowedUnits: [.hours, .minutes], width: .narrow)
        var attributed = Duration.seconds(minutes * 60).formatted(style.attributed)
        if unitsSmall {
            for run in attributed.runs where run.measurement == .unit {
                attributed[run.range].font = NoopType.unit.fixedFont
                attributed[run.range].foregroundColor = NoopType.widgetCaption.defaultColor
            }
        }
        return Text(attributed)
    }
}

/// R4-1 header: the domain label in Medium 12, its time or source on the right at white 38%.
struct WidgetHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    let tint: Color
    var trailingColor: Color = WidgetStyle.headerTrailing
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: NoopTheme.Layout.s) {
            Text(title)
                .noopFont(.widgetLabel, color: false)
                .foregroundStyle(tint)
                .lineLimit(1)
            Spacer(minLength: 0)
            trailing()
                .noopFont(.widgetCaption, color: false)
                .foregroundStyle(trailingColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// R4-1 number: Light 42 with −1.4 tracking, an optional small unit at white 50%. Nil is a dash in the
/// tertiary colour, never a zero.
struct WidgetNumber: View {
    let value: String?
    var unit: String? = nil
    /// A carried-over reading: still shown, no longer drawn as current.
    var dimmed: Bool = false

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 3) {
            Text(verbatim: value ?? "—")
                .noopFont(.widgetNumber, color: false)
                .foregroundStyle(value == nil ? NoopTheme.textTertiary
                                 : (dimmed ? NoopTheme.textSecondary : NoopTheme.textPrimary))
            if let unit, value != nil {
                Text(verbatim: unit)
                    .noopFont(.unit, color: false)
                    .foregroundStyle(NoopType.widgetCaption.defaultColor)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// R4-1 `.thin` bar. Nil draws the track alone.
struct WidgetThinBar: View {
    let fraction: Double?
    let tint: Color
    var height: CGFloat = WidgetStyle.barHeight

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(WidgetStyle.barTrack)
                if let fraction {
                    Capsule().fill(tint)
                        .frame(width: max(height, geo.size.width * CGFloat(min(max(fraction, 0), 1))))
                }
            }
        }
        .frame(height: height)
    }
}

/// A static, widget-safe thin ring. Avoids any draw-in animation: WidgetKit timelines do not reliably fire
/// `onAppear`, so an animated ring can freeze empty. Nil fraction draws the dashed empty track (the
/// redesign's missing-value ring) and a dash in the centre when a label is asked for.
struct WidgetRing: View {
    let fraction: Double?
    let tint: Color
    let diameter: CGFloat
    let lineWidth: CGFloat
    /// Centre read-out, already formatted. Nil on a labelled ring with no value draws a dash.
    var text: String? = nil
    /// False for a decorative ring beside a number that already says the value.
    var labelled: Bool = true

    var body: some View {
        ZStack {
            if let fraction {
                Circle().stroke(NoopTheme.track, lineWidth: lineWidth)
                Circle()
                    // A genuine zero still draws a round-cap bead so scored-0 reads as data, not absence.
                    .trim(from: 0, to: max(0.0001, CGFloat(min(max(fraction, 0), 1))))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                Circle().stroke(NoopTheme.trackEmpty,
                                style: StrokeStyle(lineWidth: max(1, lineWidth / 3), dash: [2, 3]))
            }
            if labelled {
                Text(verbatim: text ?? "—")
                    .font(WidgetStyle.numberFont(size: diameter * 0.4))
                    .tracking(NoopType.widgetNumber.tracking * diameter / 100)
                    .foregroundStyle(text == nil ? NoopTheme.textTertiary : NoopTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, lineWidth + 2)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}
