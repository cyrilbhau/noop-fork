import WidgetKit
import SwiftUI
import StrandDesign

/// K10: A Lock Screen / Home Screen widget showing the stored Coach morning brief.
///
/// Design contract (see PRD-K10 + D8):
/// - The widget reads **stored** brief text from the App Group — it NEVER calls the network.
///   The brief is generated on a schedule by `CoachBriefScheduler` (K5) and mirrored into the
///   App Group via `publishToWidget`. The widget just displays whatever text is there.
/// - Tap → opens the Coach tab (via the app's URL scheme / deeplink).
/// - Supported families: `accessoryRectangular` / `accessoryInline` (Lock Screen), `systemSmall` /
///   `systemMedium` (Home Screen). The Lock Screen accessory shows the first lines; the Home Screen more.
struct CoachBriefEntry: TimelineEntry {
    let date: Date
    let briefText: String?
    let briefDate: Date?
}

struct CoachBriefProvider: TimelineProvider {
    /// App Group keys — must match `CoachBriefScheduler.K.widgetBriefKey` / `.widgetBriefDateKey`.
    private static let briefKey = "coachBrief.widgetText"
    private static let briefDateKey = "coachBrief.widgetDate"

    func placeholder(in context: Context) -> CoachBriefEntry {
        CoachBriefEntry(
            date: Date(),
            briefText: "Recovery is strong today — consider a higher-intensity session this afternoon.",
            briefDate: Date()
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CoachBriefEntry) -> Void) {
        let entry = loadEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CoachBriefEntry>) -> Void) {
        let entry = loadEntry()
        // Refresh every 30 minutes — the app pushes a reload via WidgetCenter when a new brief is
        // published, so this is just a safety net for when the app isn't running.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date())
            ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> CoachBriefEntry {
        let defaults = UserDefaults(suiteName: WidgetSnapshot.suiteName)
        let text = defaults?.string(forKey: CoachBriefProvider.briefKey)
        let date = defaults?.object(forKey: CoachBriefProvider.briefDateKey) as? Date
        return CoachBriefEntry(date: Date(), briefText: text, briefDate: date)
    }
}

struct CoachBriefWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CoachBriefEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangular
        case .accessoryInline:
            inline
        default:
            home
        }
    }

    // MARK: - Lock Screen: accessoryRectangular

    /// Plain primary/secondary on the lock screen, which maps those two levels onto the wallpaper.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: NoopTheme.Layout.xs) {
                Image(systemName: "sparkles")
                Text("Coach")
                Spacer(minLength: 0)
                if let date = entry.briefDate {
                    Text(WidgetStyle.timeLabel(date, now: entry.date))
                }
            }
            .noopFont(.widgetLabel, color: false)
            .foregroundStyle(.secondary)
            Text(briefDisplay)
                .noopFont(.widgetCaption, color: false)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: - Lock Screen: accessoryInline

    private var inline: some View {
        Text(briefOneLine)
    }

    // MARK: - Home Screen: systemSmall / systemMedium

    /// R4-1: "Morning brief" in the Coach colour with the brief's time, then the stored text.
    private var home: some View {
        VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
            WidgetHeader(title: "Morning brief", tint: NoopTheme.coach) {
                if let date = entry.briefDate { Text(WidgetStyle.timeLabel(date, now: entry.date)) }
            }
            if entry.briefText == nil {
                VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
                    Text("No brief yet")
                        .noopFont(.rowTitle, color: false)
                        .foregroundStyle(NoopTheme.textSecondary)
                    Text("Enable Morning Brief in Coach settings to see today's readiness here.")
                        .noopFont(.widgetCaption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(briefDisplay)
                    .noopFont(.bodySmall, color: false)
                    .foregroundStyle(NoopTheme.textPrimary)
                    .lineLimit(family == .systemSmall ? 5 : 4)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(WidgetStyle.padding)
    }

    // MARK: - Text helpers

    /// The full brief text for the widget body, or a placeholder when there's no brief.
    private var briefDisplay: String {
        entry.briefText ?? "No brief available."
    }

    /// One-line summary for the inline accessory (capped at ~100 chars).
    private var briefOneLine: String {
        guard let text = entry.briefText else { return "Coach: no brief yet" }
        let firstLine = text.split(separator: "\n", omittingEmptySubsequences: true)
            .first.map(String.init) ?? text
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 100 else { return "Coach: \(trimmed)" }
        let cut = trimmed.index(trimmed.startIndex, offsetBy: 100)
        return "Coach: \(trimmed[..<cut].trimmingCharacters(in: .whitespaces))…"
    }
}

struct CoachBriefWidget: Widget {
    static let kind = "CoachBriefWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: CoachBriefProvider()) { entry in
            if #available(iOS 17.0, *) {
                CoachBriefWidgetView(entry: entry)
                    .containerBackground(WidgetStyle.background, for: .widget)
            } else {
                CoachBriefWidgetView(entry: entry)
                    .background(WidgetStyle.background)
            }
        }
        .configurationDisplayName("Coach Brief")
        .description("Today's coaching brief at a glance. Tap to open Coach.")
        .supportedFamilies([
            .systemSmall,
            // systemMedium added for R4-1's wide "Morning brief" card; same stored text, more of it.
            .systemMedium,
            .accessoryRectangular,
            .accessoryInline,
        ])
        .contentMarginsDisabled()
    }
}
