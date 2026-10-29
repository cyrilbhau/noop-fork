import SwiftUI
import WidgetKit
import StrandDesign

private struct PersonalMetricsEntry: TimelineEntry {
    let date: Date
    let metrics: PersonalWidgetMetrics?
}

private struct PersonalMetricsProvider: TimelineProvider {
    func placeholder(in context: Context) -> PersonalMetricsEntry {
        // Missing data in the gallery is preferable to a sample estimate mistaken for validation.
        PersonalMetricsEntry(date: Date(), metrics: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (PersonalMetricsEntry) -> Void) {
        completion(PersonalMetricsEntry(date: Date(), metrics: WidgetSnapshot.load()?.personal))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PersonalMetricsEntry>) -> Void) {
        let now = Date()
        let metrics = WidgetSnapshot.load()?.personal
        var entries = [PersonalMetricsEntry(date: now, metrics: metrics)]
        // A second entry expires yesterday's steps even if iOS delays the requested refresh. It never
        // invents a fresh observation; the rendering helper checks the entry's local calendar day.
        if let tomorrow = Calendar.current.date(byAdding: .day, value: 1,
                                               to: Calendar.current.startOfDay(for: now)) {
            entries.append(PersonalMetricsEntry(date: tomorrow, metrics: metrics))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
    }
}

/// R4-1 Steps: the band estimate, labelled as one, against the chosen goal. "Today" is the value's time:
/// `todaySteps` drops any day but the entry's, and the estimate has no calculation timestamp of its own.
private struct PersonalStepsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PersonalMetricsEntry

    private var reading: PersonalStepReading? { entry.metrics?.todaySteps(now: entry.date) }
    private var goal: Int? { entry.metrics?.stepGoal.flatMap { (1...50_000).contains($0) ? $0 : nil } }

    var body: some View {
        if family == .accessoryRectangular {
            rectangular
        } else {
            home
        }
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(title: "Steps", tint: NoopTheme.lift) {
                if reading != nil { Text("Today") }
            }
            Spacer(minLength: 0)
            WidgetNumber(value: reading.map { $0.count.formatted() })
            Text(LocalizedStringKey(reading == nil ? "No estimate for today" : "Estimated • WHOOP 4.0"))
                .noopFont(.widgetCaption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, WidgetStyle.captionGap)
            if family != .systemSmall, reading != nil {
                Text("Freshness unknown")
                    .noopFont(.widgetCaption)
                    .lineLimit(1)
            }
            if let goal {
                Text("of \(goal.formatted())")
                    .noopFont(.widgetCaption)
                    .lineLimit(1)
                WidgetThinBar(fraction: reading.map { Double($0.count) / Double(goal) }, tint: NoopTheme.lift)
                    .padding(.top, WidgetStyle.barGap)
            } else {
                Text("Goal not set")
                    .noopFont(.widgetCaption)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(WidgetStyle.padding)
        .accessibilityElement(children: .combine)
    }

    /// Lock Screen: plain primary/secondary, which the system maps onto the wallpaper.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("Steps", systemImage: "figure.walk")
                .noopFont(.widgetLabel, color: false)
                .foregroundStyle(.secondary)
            Text(verbatim: reading.map { countText($0.count) } ?? "—")
                .font(WidgetStyle.numberFont(size: NoopType.rowNumber.size))
                .foregroundStyle(.primary)
            Text(LocalizedStringKey(reading == nil ? "Band estimate unavailable" : "Estimated • WHOOP 4.0"))
                .noopFont(.widgetCaption, color: false)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func countText(_ count: Int) -> String {
        if let goal { return "\(count.formatted()) / \(goal.formatted())" }
        return count.formatted()
    }
}

/// R4-1 Sleep: last night's asleep time, with where it came from and when it ended. No bar: the snapshot
/// carries no sleep need to measure it against.
private struct PersonalSleepWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PersonalMetricsEntry

    private var reading: PersonalSleepReading? { entry.metrics?.recentSleep(now: entry.date) }

    var body: some View {
        if family == .accessoryRectangular {
            rectangular
        } else {
            home
        }
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(title: "Sleep", tint: NoopTheme.sleep) {
                if let reading { Text("Ended \(WidgetStyle.timeLabel(reading.end, now: entry.date))") }
            }
            Spacer(minLength: 0)
            if let reading {
                WidgetStyle.durationText(minutes: reading.asleepMinutes, unitsSmall: true)
                    .noopFont(.widgetNumber, color: false)
                    .foregroundStyle(NoopTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(LocalizedStringKey(reading.source == .localEstimate ? "Local estimate" : "WHOOP history"))
                    .noopFont(.widgetCaption)
                    .padding(.top, WidgetStyle.captionGap)
                if reading.incomplete {
                    Text("May be incomplete").noopFont(.widgetCaption)
                }
                if family != .systemSmall, reading.userEdited {
                    Text("Manually corrected").noopFont(.widgetCaption)
                }
            } else {
                WidgetNumber(value: nil)
                Text("No recent sleep")
                    .noopFont(.widgetCaption)
                    .padding(.top, WidgetStyle.captionGap)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(WidgetStyle.padding)
        .accessibilityElement(children: .combine)
    }

    /// Lock Screen: plain primary/secondary, which the system maps onto the wallpaper.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("Sleep", systemImage: "moon.fill")
                .noopFont(.widgetLabel, color: false)
                .foregroundStyle(.secondary)
            if let reading {
                WidgetStyle.durationText(minutes: reading.asleepMinutes)
                    .font(WidgetStyle.numberFont(size: NoopType.rowNumber.size))
                    .foregroundStyle(.primary)
                Text("Ended \(reading.end.formatted(date: .abbreviated, time: .shortened))")
                    .noopFont(.widgetCaption, color: false)
                    .foregroundStyle(.secondary)
            } else {
                Text(verbatim: "—")
                    .font(WidgetStyle.numberFont(size: NoopType.rowNumber.size))
                    .foregroundStyle(.primary)
                Text("No recent sleep")
                    .noopFont(.widgetCaption, color: false)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct PersonalStepsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PersonalStepsWidget", provider: PersonalMetricsProvider()) { entry in
            PersonalStepsWidgetView(entry: entry)
                .containerBackground(WidgetStyle.background, for: .widget)
        }
        .configurationDisplayName("Band Steps")
        .description("Today's band-motion estimate and chosen goal. Estimates are labelled; refresh timing is controlled by iOS.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

struct PersonalSleepWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PersonalSleepWidget", provider: PersonalMetricsProvider()) { entry in
            PersonalSleepWidgetView(entry: entry)
                .containerBackground(WidgetStyle.background, for: .widget)
        }
        .configurationDisplayName("Recent Sleep")
        .description("Recent sleep duration with its source and wake time. Local estimates may be incomplete.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}
