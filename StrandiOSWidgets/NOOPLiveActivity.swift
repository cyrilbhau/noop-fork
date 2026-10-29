import WidgetKit
import SwiftUI
import ActivityKit
import StrandDesign

/// Live Activity for an active live-HR session — shown on the Lock Screen and in the Dynamic Island
/// (round 4: R4-2 banner, R4-3 island, R4-4 expanded over the app).
struct NOOPLiveActivity: Widget {
    /// The heart rate to draw: none once iOS has marked the banner stale. Each push is fresh for 30 s
    /// (`LiveActivityController.staleAfter`) and NOOP re-pushes a steady number well inside that, so a stale banner
    /// means the readings stopped — the strap off the wrist, or out of reach — even while NOOP itself is asleep and
    /// cannot say so: iOS redraws the banner at the stale date on its own.
    static func shownBpm(_ context: ActivityViewContext<NOOPActivityAttributes>) -> Int? {
        context.isStale ? nil : context.state.bpm
    }

    /// The zone to colour by, under the same rule as the number: none once the number is gone, so a dash is
    /// never drawn in a zone colour. Nil too for an activity an older build started, which carries no zone.
    static func shownZone(_ context: ActivityViewContext<NOOPActivityAttributes>) -> Int? {
        shownBpm(context) == nil ? nil : context.state.zone
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NOOPActivityAttributes.self) { context in
            // Lock Screen / banner presentation (R4-2).
            LiveHRPanel(bpm: Self.shownBpm(context), zone: Self.shownZone(context),
                        recovery: context.state.recovery, strain: context.state.effort, title: "Live heart rate")
                .padding(WidgetStyle.padding)
                .activityBackgroundTint(WidgetStyle.activityBackground)
                .activitySystemActionForegroundColor(NoopTheme.textPrimary)
        } dynamicIsland: { context in
            let bpm = Self.shownBpm(context)
            let zone = Self.shownZone(context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    // R4-3 expanded: the same panel as the banner, with the shorter "Live" title.
                    LiveHRPanel(bpm: bpm, zone: zone, recovery: context.state.recovery,
                                strain: context.state.effort, title: "Live")
                        .padding(.horizontal, NoopTheme.Layout.xs)
                }
            } compactLeading: {
                Image(systemName: "heart.fill").foregroundStyle(NoopTheme.heart)
            } compactTrailing: {
                // R4-3 compact: the number in its zone's colour, white without a zone.
                Text(verbatim: bpm.map(String.init) ?? "–")
                    .font(WidgetStyle.numberFont(size: NoopType.listTitle.size))
                    .fontWeight(.medium)
                    .foregroundStyle(liveZoneColor(zone) ?? NoopTheme.textPrimary)
            } minimal: {
                Image(systemName: "heart.fill").foregroundStyle(liveZoneColor(zone) ?? NoopTheme.heart)
            }
        }
    }
}

/// The zone colour for a 1–5 zone; nil below Zone 1 or with no zone, where nothing is coloured by zone.
private func liveZoneColor(_ zone: Int?) -> Color? {
    guard let zone, (1...5).contains(zone) else { return nil }
    return NoopTheme.zoneColor(zone)
}

/// R4-2 / R4-3 live heart-rate panel: heart and title with the zone on the right; the light number beside
/// Recovery and Strain; the five zone segments with the current one lit. File-scope because the
/// `ActivityConfiguration` closures are not methods of `NOOPLiveActivity`.
private struct LiveHRPanel: View {
    let bpm: Int?
    let zone: Int?
    let recovery: Int?
    /// NOOP's 0–100 axis (`ContentState.effort`), shown as the whole number the app sends.
    let strain: Int?
    let title: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: NoopTheme.Layout.s) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(NoopTheme.heart)
                Text(title)
                    .foregroundStyle(WidgetStyle.ringLabel)
                Spacer(minLength: NoopTheme.Layout.s)
                zoneLabel
                    .foregroundStyle(NoopType.widgetCaption.defaultColor)
            }
            .noopFont(.widgetCaption, color: false)
            .lineLimit(1)

            HStack(alignment: .bottom, spacing: NoopTheme.Layout.l) {
                WidgetNumber(value: bpm.map(String.init), unit: "bpm")
                Spacer(minLength: 0)
                // Centre-aligned with `fixedSize` so each value sits under its own label (#759).
                stat("Recovery", value: recovery.map { "\($0)%" },
                     tint: recovery.map { NoopTheme.recoveryColor(for: $0) })
                stat("Strain", value: strain.map(String.init), tint: NoopTheme.strain)
            }
            .padding(.top, NoopTheme.Layout.s)

            ZoneSegments(zone: zone)
                .padding(.top, WidgetStyle.barGap)
        }
    }

    @ViewBuilder private var zoneLabel: some View {
        if let zone, (1...5).contains(zone) {
            Text("Zone") + Text(verbatim: " " + String(zone))
        } else if zone == 0 {
            Text("Below Zone 1")
        }
    }

    private func stat(_ label: LocalizedStringKey, value: String?, tint: Color?) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(label)
                .noopFont(.widgetCaption)
            Text(verbatim: value ?? "—")
                .font(WidgetStyle.numberFont(size: NoopType.body.size))
                .fontWeight(.regular)
                .foregroundStyle(value == nil ? NoopTheme.textTertiary : (tint ?? NoopTheme.textPrimary))
        }
        .multilineTextAlignment(.center)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// R4-2's five zone segments: the current zone at full colour, the others dimmed. All dimmed with no zone,
/// so a missing reading does not light anything.
private struct ZoneSegments: View {
    let zone: Int?

    var body: some View {
        HStack(spacing: NoopTheme.Layout.xs) {
            ForEach(1...5, id: \.self) { z in
                Capsule()
                    .fill(NoopTheme.zoneColor(z))
                    .opacity(z == zone ? 1 : WidgetStyle.zoneDim)
            }
        }
        .frame(height: WidgetStyle.barHeight)
        .accessibilityHidden(true)
    }
}
