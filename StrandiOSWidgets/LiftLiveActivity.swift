import WidgetKit
import SwiftUI
import ActivityKit
import StrandDesign

/// Live Activity for a running Lift Log session — the minimised session bar, on the Lock Screen and
/// in the Dynamic Island (round 4: R4-3 compact and expanded).
///
/// It carries the same four things the in-app bar does: what am I doing, on what, with what numbers, and
/// how long. One colour for the activity, the Lift orange; the clock is in it through a rest (the number
/// you act on) and white through a working set.
///
/// THE CLOCK TICKS WITHOUT THE APP. Both timers are `Text(timerInterval:)`, and the rest ring is a
/// `ProgressView(timerInterval:)`, all driven by dates in the content state, so the Lock Screen counts and
/// drains on its own between pushes. The app only sends a new state when something actually changes
/// (stage, set, heart rate), never once a second to animate a number.
struct LiftLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiftActivityAttributes.self) { context in
            LiftPanel(state: context.state)
                .padding(WidgetStyle.padding)
                .activityBackgroundTint(WidgetStyle.activityBackground)
                .activitySystemActionForegroundColor(NoopTheme.textPrimary)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    LiftPanel(state: state)
                        .padding(.horizontal, NoopTheme.Layout.xs)
                }
            } compactLeading: {
                // The heart rate, where the island has the room for it, with the dumbbell standing in until
                // the strap reports one — so this side is never the blank it was (Utku, 22 Sep 2026).
                HStack(spacing: NoopTheme.Layout.xs) {
                    Image(systemName: state.bpm == nil ? "dumbbell.fill" : "heart.fill")
                        .foregroundStyle(state.bpm == nil ? NoopTheme.lift : NoopTheme.heart)
                    if let bpm = state.bpm {
                        Text(verbatim: "\(bpm)")
                            .foregroundStyle(WidgetStyle.ringLabel)
                    }
                }
                .font(LiftClock.islandFont)
            } compactTrailing: {
                // R4-3: the rest ring draining beside the clock, only when a rest has a length to drain.
                HStack(spacing: NoopTheme.Layout.xs) {
                    if let range = LiftClock.restRange(state) {
                        ProgressView(timerInterval: range, countsDown: true) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        }
                        .progressViewStyle(.circular)
                        .tint(NoopTheme.lift)
                        .frame(width: LiftClock.compactRing, height: LiftClock.compactRing)
                    }
                    // Sized like the Lock Screen's clock: a running `Text(timerInterval:)` takes every point it
                    // is offered, which stretched the island (Utku, 22 Sep 2026). A hidden "00:00" in the same
                    // font gives the region the width of the clock itself, and the live one sits over it.
                    LiftClock.sized(state, font: LiftClock.islandFont)
                }
            } minimal: {
                Image(systemName: "dumbbell.fill").foregroundStyle(NoopTheme.lift)
            }
        }
    }
}

/// R4-3 lift panel, shared by the Lock Screen banner and the expanded island.
///
/// Row one: the dumbbell and the stage ("Resting after set 2"), the heart rate on the right — ALWAYS present,
/// dash and all, because a readout that vanishes when the strap stops reading looks like a missing feature.
/// Row two: the exercise and the set coming up, the light clock on the right. Then, only through a rest with a
/// length, the rest bar draining in real time and the rest's full length. Every word arrives pre-localized from
/// the app (`status`, `detail`, `next`).
private struct LiftPanel: View {
    let state: LiftActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: NoopTheme.Layout.s) {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(NoopTheme.lift)
                Text(verbatim: state.status)
                    .foregroundStyle(WidgetStyle.ringLabel)
                    .lineLimit(1)
                Spacer(minLength: NoopTheme.Layout.s)
                Image(systemName: "heart.fill")
                    .foregroundStyle(state.bpm == nil ? NoopTheme.textTertiary : NoopTheme.heart)
                Text(verbatim: state.bpm.map(String.init) ?? "—")
                    .monospacedDigit()
                    .foregroundStyle(state.bpm == nil ? NoopTheme.textTertiary : WidgetStyle.ringLabel)
            }
            .noopFont(.widgetCaption, color: false)

            HStack(alignment: .bottom, spacing: NoopTheme.Layout.m) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: state.exercise)
                        .noopFont(.rowTitle, color: false)
                        .fontWeight(.medium)
                        .foregroundStyle(NoopTheme.textPrimary)
                    // The set coming up. It puts the set number before the exercise, so the tail truncation a
                    // long name needs cuts the name and keeps the number.
                    Text(verbatim: state.next)
                        .noopFont(.widgetCaption)
                        .truncationMode(.tail)
                }
                .lineLimit(1)
                Spacer(minLength: NoopTheme.Layout.s)
                LiftClock.sized(state, font: LiftClock.panelFont)
                    .tracking(NoopType.widgetNumber.tracking)
            }
            .padding(.top, NoopTheme.Layout.s)

            if let range = LiftClock.restRange(state) {
                ProgressView(timerInterval: range, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(NoopTheme.lift)
                .padding(.top, WidgetStyle.barGap)
            }

            if state.detail != nil || LiftClock.restRange(state) != nil {
                HStack {
                    if let detail = state.detail {
                        Text(verbatim: detail)
                    }
                    Spacer(minLength: NoopTheme.Layout.s)
                    if let range = LiftClock.restRange(state) {
                        Text("of \(LiftClock.lengthText(range))")
                    }
                }
                .noopFont(.widgetCaption)
                .lineLimit(1)
                .padding(.top, NoopTheme.Layout.s)
            }
        }
    }
}

/// The clock and rest-ring rules, shared by every region.
private enum LiftClock {
    /// The panel's clock: the widget numeral weight at the R4-3 rest size.
    static let panelFont = WidgetStyle.numberFont(size: NoopType.tileNumber.size - 2)
    /// The Dynamic Island's compact face, shared by its heart rate, its clock and that clock's template.
    static let islandFont = Font.system(size: NoopType.listTitle.size, weight: .medium, design: .default)
        .monospacedDigit()
    static let compactRing: CGFloat = 16

    /// The running rest, when it has a length to count down and drain. Nil while working, and for a rest with
    /// no length (the sheet is complete), which shows 0:00 and no ring.
    static func restRange(_ state: LiftActivityAttributes.ContentState) -> ClosedRange<Date>? {
        guard let ends = state.restEndsAt, ends > state.stageStartedAt else { return nil }
        return state.stageStartedAt...ends
    }

    /// "2:15" — the rest's full length.
    static func lengthText(_ range: ClosedRange<Date>) -> String {
        Duration.seconds(range.upperBound.timeIntervalSince(range.lowerBound).rounded())
            .formatted(.time(pattern: .minuteSecond))
    }

    /// The clock in `font`, given the width of a hidden "00:00" in the same font — the widest a set or a rest
    /// shows under an hour — and right-aligned over it, because a running `Text(timerInterval:)` takes all the
    /// width it is offered.
    static func sized(_ state: LiftActivityAttributes.ContentState, font: Font) -> some View {
        Text(verbatim: "00:00")
            .font(font)
            .monospacedDigit()
            .hidden()
            .overlay(alignment: .trailing) {
                liftClock(state)
                    .font(font)
                    .multilineTextAlignment(.trailing)
            }
    }

    /// Counts DOWN through a rest (the number you act on) and UP through a set, both self-ticking.
    ///
    /// Both branches use `Text(timerInterval:)`, which is the API widgets are given for a clock that
    /// advances without the app pushing. `Text(date, style: .timer)` looks equivalent and is not: on
    /// the Lock Screen it rendered "25 minutes" — a rounded, prose duration — where a gym timer has
    /// to read 25:02. Verified in the simulator, which is the only reason it was caught.
    ///
    /// A rest that is over reads 0:00 and stays there, as the in-app bar does
    /// (`LiftSessionEngine.restRemaining` floors at zero). It used to count UP past the end, and a
    /// clock climbing from zero on the Lock Screen read as a new timer rather than a finished rest
    /// (gym session, 16 Sep 2026). The countdown's range therefore starts at the REST'S start, not at
    /// `.now`: a widget re-rendered after the end — for a heart-rate push, say — still gets a range
    /// that is entirely past, which `Text(timerInterval:)` shows as its end value instead of switching
    /// to a count-up. A rest with no length (the sheet is complete) has no range to count and shows
    /// the same 0:00. A working set counts up from its start; a zero-length range would render
    /// nothing, so that end is pushed a day out — well beyond any session.
    static func liftClock(_ state: LiftActivityAttributes.ContentState) -> some View {
        Group {
            if let ends = state.restEndsAt {
                if ends > state.stageStartedAt {
                    Text(timerInterval: state.stageStartedAt...ends, countsDown: true)
                } else {
                    Text(verbatim: "0:00")
                }
            } else {
                Text(timerInterval: state.stageStartedAt...state.stageStartedAt.addingTimeInterval(86_400),
                     countsDown: false)
            }
        }
        .monospacedDigit()
        .foregroundStyle(state.isResting ? NoopTheme.lift : NoopTheme.textPrimary)
    }
}
