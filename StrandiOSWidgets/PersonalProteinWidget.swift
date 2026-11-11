import SwiftUI
import WidgetKit
import StrandDesign

// Stage 3 (protein and intake), specification §10.8 and design round `design/round-s3-intake/`
// frames W1 to W9: today's grams against the floor, always with the time they were read or
// entered. No calories, supplement, label or app name ever reaches this widget. While Intake is off
// (or has no source, or never published) it draws "Set up in NOOP"; a widget extension cannot hide
// a kind at run time (question I6).

private struct PersonalProteinEntry: TimelineEntry {
    let date: Date
    let reading: PersonalIntakeReading?
}

private struct PersonalProteinProvider: TimelineProvider {
    func placeholder(in context: Context) -> PersonalProteinEntry {
        // No sample figure in the gallery, as the other personal widgets do.
        PersonalProteinEntry(date: Date(), reading: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (PersonalProteinEntry) -> Void) {
        completion(PersonalProteinEntry(date: Date(), reading: WidgetSnapshot.load()?.personal?.intake))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PersonalProteinEntry>) -> Void) {
        let now = Date()
        let reading = WidgetSnapshot.load()?.personal?.intake
        // Entries at now, when a Health figure turns stale, and at the next midnight, so both states
        // appear without the app.
        let dates = reading?.timelineDates(now: now)
            ?? [now, Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))]
                .compactMap { $0 }
        let entries = dates.map { PersonalProteinEntry(date: $0, reading: reading) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
    }
}

private struct PersonalProteinWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PersonalProteinEntry

    /// Only the entry's own day: yesterday's figure is never drawn as today's.
    private var reading: PersonalIntakeReading? { PersonalWidgetMetrics(intake: entry.reading).todayIntake(now: entry.date) }
    private var state: PersonalIntakeWidgetState { reading?.widgetState ?? .notSetUp }
    private var stale: Bool { reading?.isStale(now: entry.date) ?? false }
    private var time: String? { reading?.readAt.map { $0.formatted(date: .omitted, time: .shortened) } }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        default: home
        }
    }

    // MARK: Home Screen

    private var home: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(title: "Protein", tint: NoopTheme.textPrimary) { EmptyView() }
            Spacer(minLength: 0)
            HStack(alignment: .center, spacing: NoopTheme.Layout.m) {
                VStack(alignment: .leading, spacing: 0) {
                    WidgetNumber(value: grams.map { $0.formatted() }, unit: grams == nil ? nil : "g", dimmed: stale)
                    if family == .systemMedium, let floor = floorGrams {
                        Text("of \(floor) g").noopFont(.widgetCaption).lineLimit(1)
                    }
                }
                if family == .systemMedium || ringFraction != nil {
                    Spacer(minLength: 0)
                    WidgetRing(fraction: ringFraction, tint: stale ? NoopTheme.textTertiary : NoopTheme.textPrimary,
                               diameter: family == .systemMedium ? 64 : 44, lineWidth: family == .systemMedium ? 6 : 5,
                               labelled: false)
                }
            }
            lines
                .padding(.top, WidgetStyle.captionGap)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(WidgetStyle.padding)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var lines: some View {
        Group {
            switch state {
            case .notSetUp:
                Text("Set up in NOOP")
            case .nothingLogged:
                Text("Nothing logged today")
            case .noFloor:
                Text("No floor set")
                timeLine
            case .below(_, _, let remaining):
                Text("\(remaining) g to go")
                timeLine
            case .atFloor:
                Text("Floor met")
                timeLine
            case .above(_, _, let over):
                Text("Floor met")
                if family == .systemMedium { Text("+\(over) g over") }
                timeLine
            }
            if stale, family == .systemMedium { Text("Open NOOP to refresh") }
        }
        .noopFont(.widgetCaption)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    @ViewBuilder
    private var timeLine: some View {
        if let time {
            if stale { Text("Last read \(time)") } else { Text("as of \(time)") }
        }
    }

    // MARK: Lock Screen

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("Protein", systemImage: "fork.knife")
                .noopFont(.widgetLabel, color: false)
                .foregroundStyle(.secondary)
            Group {
                switch state {
                case .notSetUp: Text("Set up in NOOP")
                case .nothingLogged: Text("Nothing logged today")
                case .noFloor(let grams): Text(verbatim: "\(grams.formatted()) g")
                case .below(_, _, let remaining): Text("\(remaining) g to go")
                case .atFloor, .above: Text("Floor met")
                }
            }
            .foregroundStyle(.primary)
            if let time, state != .notSetUp {
                if stale { Text("Last read \(time)").foregroundStyle(.secondary) } else {
                    Text(verbatim: time).foregroundStyle(.secondary)
                }
            }
        }
        .noopFont(.widgetCaption, color: false)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var circular: some View {
        Gauge(value: ringFraction ?? 0) {
            Image(systemName: "fork.knife")
        } currentValueLabel: {
            switch state {
            case .below(_, _, let remaining): Text(verbatim: remaining.formatted())
            case .atFloor, .above: Image(systemName: "checkmark")
            case .noFloor(let grams): Text(verbatim: grams.formatted())
            case .notSetUp, .nothingLogged: Text(verbatim: "—")
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .opacity(stale ? 0.5 : 1)
        .accessibilityLabel(Text("Protein"))
    }

    // MARK: Values

    private var grams: Int? {
        switch state {
        case .noFloor(let grams), .below(let grams, _, _), .atFloor(let grams, _), .above(let grams, _, _): return grams
        case .notSetUp, .nothingLogged: return nil
        }
    }

    private var floorGrams: Int? {
        switch state {
        case .below(_, let floor, _), .atFloor(_, let floor), .above(_, let floor, _): return floor
        case .nothingLogged(let floor): return floor
        case .notSetUp, .noFloor: return nil
        }
    }

    /// Complete at the floor and never past it; nil (no ring) with no floor or nothing set up.
    private var ringFraction: Double? {
        switch state {
        case .below(let grams, let floor, _): return min(1, max(0, Double(grams) / Double(floor)))
        case .atFloor, .above: return 1
        case .nothingLogged(let floor): return floor == nil ? nil : 0
        case .notSetUp, .noFloor: return nil
        }
    }
}

struct PersonalProteinWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PersonalProteinWidget", provider: PersonalProteinProvider()) { entry in
            PersonalProteinWidgetView(entry: entry)
                .containerBackground(WidgetStyle.background, for: .widget)
        }
        .configurationDisplayName("Protein")
        .description("Today's protein against your floor, with the time it was read or entered.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
        .contentMarginsDisabled()
    }
}
