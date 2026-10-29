import WidgetKit
import SwiftUI
import ActivityKit
import StrandDesign

/// Live Activity for a strap history sync — the Lock Screen banner and the Dynamic Island (round 4, R4-3),
/// in the Breath colour.
///
/// Shows what the app's own Today sync control shows: that a sync is running, how many chunks it has
/// pulled, how long it has been going, and the strap's connect-time backlog when it reported one. THERE IS
/// NO PERCENT: the strap never says how much is pending (see `SyncActivityAttributes`), so where R4-3 draws
/// "62%" and a filling bar this draws the chunk count and an indeterminate striped bar instead.
struct SyncLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SyncActivityAttributes.self) { context in
            SyncPanel(title: context.attributes.title, state: context.state)
                .padding(WidgetStyle.padding)
                .activityBackgroundTint(WidgetStyle.activityBackground)
                .activitySystemActionForegroundColor(NoopTheme.textPrimary)
        } dynamicIsland: { context in
            // ONE short row, deliberately. iOS shows the expanded layout for a few seconds whenever an activity
            // starts and offers no way to start compact, so the only lever on that flash is how tall the
            // expanded layout is. The backlog detail and the bar live on the Lock Screen banner instead.
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label { Text(verbatim: context.state.status) } icon: { syncGlyph(context.state.phase) }
                        .noopFont(.widgetLabel, color: false)
                        .foregroundStyle(WidgetStyle.ringLabel)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if isActive(context.state.phase) {
                        elapsed(since: context.state.startedAt)
                            .noopFont(.widgetLabel, color: false)
                            .monospacedDigit()
                            .foregroundStyle(NoopTheme.breath)
                    }
                }
            } compactLeading: {
                // Same footprint as the live-HR island's heart: one symbol, no label.
                syncGlyph(context.state.phase)
            } compactTrailing: {
                // "…" while connecting and until the first chunk lands; then the chunk count, the only
                // live number a sync has. Never "0", so the island never claims progress the strap has
                // not made, and never a percentage, because there is no total.
                Text(verbatim: context.state.chunks > 0 ? "\(context.state.chunks)" : "…")
                    .font(WidgetStyle.numberFont(size: NoopType.listTitle.size))
                    .fontWeight(.medium)
                    .foregroundStyle(NoopTheme.breath)
            } minimal: {
                syncGlyph(context.state.phase)
            }
        }
    }
}

/// R4-3 sync panel for the Lock Screen: glyph and title with the elapsed clock; the status (or the backlog)
/// beside "25 chunks" in light Breath numerals; then the bar — striped while running (a count, no total),
/// full once the strap said it was done, none if it stopped.
private struct SyncPanel: View {
    let title: String
    let state: SyncActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: NoopTheme.Layout.s) {
                syncGlyph(state.phase)
                Text(verbatim: title)
                    .foregroundStyle(WidgetStyle.ringLabel)
                Spacer(minLength: NoopTheme.Layout.s)
                if isActive(state.phase) {
                    elapsed(since: state.startedAt)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(NoopType.widgetCaption.defaultColor)
                }
            }
            .noopFont(.widgetCaption, color: false)
            .lineLimit(1)

            HStack(alignment: .lastTextBaseline, spacing: NoopTheme.Layout.m) {
                VStack(alignment: .leading, spacing: 2) {
                    // The status already names the chunk count ("Syncing… 25 chunks"), so while the count is
                    // on the right the left says something else: the backlog when known, else nothing twice.
                    if state.chunks == 0 || !isActive(state.phase) {
                        Text(verbatim: state.status)
                            .noopFont(.bodySmall, color: false)
                            .foregroundStyle(NoopTheme.textPrimary)
                    }
                    if let detail = state.detail {
                        Text(verbatim: detail)
                            .noopFont(.widgetCaption)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: NoopTheme.Layout.s)
                if state.chunks > 0 {
                    Text("\(state.chunks) chunks")
                        .font(WidgetStyle.numberFont(size: NoopType.statNumber.size))
                        .foregroundStyle(NoopTheme.breath)
                        .lineLimit(1)
                }
            }
            .padding(.top, NoopTheme.Layout.s)

            switch state.phase {
            case .connecting, .syncing:
                IndeterminateBar(tint: NoopTheme.breath)
                    .padding(.top, WidgetStyle.barGap)
            case .done:
                WidgetThinBar(fraction: 1, tint: NoopTheme.breath)
                    .padding(.top, WidgetStyle.barGap)
            case .interrupted:
                EmptyView()
            }
        }
    }
}

/// A bar that says "in progress" without a fraction: evenly spaced dashes the full width of the track. A
/// widget cannot animate a marquee, and a partial fill would read as a percentage the strap never gave.
private struct IndeterminateBar: View {
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
            }
            .stroke(tint, style: StrokeStyle(lineWidth: WidgetStyle.barHeight, lineCap: .round,
                                             dash: [NoopTheme.Layout.m, NoopTheme.Layout.s]))
        }
        .frame(height: WidgetStyle.barHeight)
        .background(Capsule().fill(WidgetStyle.barTrack))
        .accessibilityHidden(true)
    }
}

private func isActive(_ phase: SyncActivityAttributes.Phase) -> Bool {
    phase == .connecting || phase == .syncing
}

/// Counts up on its own from the run's start; no pushes needed to keep it moving.
private func elapsed(since start: Date) -> some View {
    Text(timerInterval: start...Date.distantFuture, countsDown: false)
}

/// One glyph per phase, in the Breath colour while running and once done, and the low-Recovery red when the
/// strap went quiet. The connecting/syncing distinction is carried by the trailing "…" vs count, not by
/// swapping symbols, which keeps the compact pill's width steady.
@ViewBuilder
private func syncGlyph(_ phase: SyncActivityAttributes.Phase) -> some View {
    switch phase {
    case .connecting, .syncing:
        Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(NoopTheme.breath)
    case .done:
        Image(systemName: "checkmark.circle.fill").foregroundStyle(NoopTheme.breath)
    case .interrupted:
        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(NoopTheme.recoveryLow)
    }
}
