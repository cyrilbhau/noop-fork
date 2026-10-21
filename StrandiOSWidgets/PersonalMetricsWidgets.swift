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

private struct PersonalStepsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PersonalMetricsEntry

    private var reading: PersonalStepReading? { entry.metrics?.todaySteps(now: entry.date) }
    private var compact: Bool { family == .accessoryRectangular }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            Label("Steps", systemImage: "figure.walk")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
            Text(reading.map { countText($0.count) } ?? "—")
                .font(compact ? StrandFont.title2 : StrandFont.title1)
                .monospacedDigit()
                .foregroundStyle(StrandPalette.textPrimary)
            Text(LocalizedStringKey(reading == nil ? "Band estimate unavailable" : "Estimated • WHOOP 4.0"))
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
            if !compact {
                Text(LocalizedStringKey(reading == nil ? "No estimate for today" : "Freshness unknown"))
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                if let goal = entry.metrics?.stepGoal, (1...50_000).contains(goal) {
                    Text("Goal \(goal.formatted())")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                    if let reading {
                        ProgressView(value: min(Double(reading.count) / Double(goal), 1))
                            .tint(StrandPalette.metricCyan)
                    }
                } else {
                    Text("Goal not set")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            } else if reading != nil {
                Text("Freshness unknown")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func countText(_ count: Int) -> String {
        if compact, let goal = entry.metrics?.stepGoal, (1...50_000).contains(goal) {
            return "\(count.formatted()) / \(goal.formatted())"
        }
        return count.formatted()
    }
}

private struct PersonalSleepWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PersonalMetricsEntry

    private var reading: PersonalSleepReading? { entry.metrics?.recentSleep(now: entry.date) }
    private var compact: Bool { family == .accessoryRectangular }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            Label("Sleep", systemImage: "moon.fill")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
            if let reading {
                Text("\(reading.asleepMinutes / 60)h \(reading.asleepMinutes % 60)m")
                    .font(compact ? StrandFont.title2 : StrandFont.title1)
                    .monospacedDigit()
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(LocalizedStringKey(reading.source == .localEstimate ? "Local estimate" : "WHOOP history"))
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                if reading.incomplete {
                    Text("May be incomplete")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                Text("Ended \(reading.end.formatted(date: .abbreviated, time: .shortened))")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                if !compact {
                    if reading.userEdited {
                        Text("Manually corrected")
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                }
            } else {
                Text("—")
                    .font(compact ? StrandFont.title2 : StrandFont.title1)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("No recent sleep")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct PersonalStepsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PersonalStepsWidget", provider: PersonalMetricsProvider()) { entry in
            PersonalStepsWidgetView(entry: entry)
                .containerBackground(StrandPalette.surfaceBase, for: .widget)
        }
        .configurationDisplayName("Band Steps")
        .description("Today's band-motion estimate and chosen goal. Estimates are labelled; refresh timing is controlled by iOS.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct PersonalSleepWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PersonalSleepWidget", provider: PersonalMetricsProvider()) { entry in
            PersonalSleepWidgetView(entry: entry)
                .containerBackground(StrandPalette.surfaceBase, for: .widget)
        }
        .configurationDisplayName("Recent Sleep")
        .description("Recent sleep duration with its source and wake time. Local estimates may be incomplete.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
