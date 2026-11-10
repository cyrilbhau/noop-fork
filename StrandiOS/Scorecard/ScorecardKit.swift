import SwiftUI
import StrandAnalytics
import StrandDesign

// Stage 1 (weigh-in and scorecard), specification §10: the pieces the four scorecard screens share.
// Presentation only. Every word a screen shows comes from `CutScorecardPresenter` or from a model in
// `CutScorecardModel.swift`; nothing here formats a number, a date or a sentence.

/// Geometry from `design/round6-scorecard/scorecard.css` that has no `NoopTheme` token.
enum ScorecardLayout {
    /// `.sig svg`: the signal glyph (24 pt at the default text size).
    static let signalGlyph: CGFloat = 24
    /// The check or cross inside the glyph, as a share of the glyph.
    static let signalMarkRatio: CGFloat = 0.46
    /// `.rrow svg`: the rule dot's box and the dot inside it.
    static let ruleDotBox: CGFloat = 18
    static let ruleDot: CGFloat = 10
    /// Ring and dash weights of the glyphs.
    static let ringWidth: CGFloat = 1.6
    static let dash: [CGFloat] = [3, 3.3]
    /// `svg.wk`: plot height with a line, and with a single point.
    static let chartHeight: CGFloat = 126
    static let chartHeightSinglePoint: CGFloat = 80
    /// Chart marks: line, weekly point, latest point and its halo, the open ring of a missed week.
    static let chartLine: CGFloat = 2.5
    static let chartPoint: CGFloat = 2.6
    static let chartLatestPoint: CGFloat = 4
    static let chartHalo: CGFloat = 8
    static let chartPointBorder: CGFloat = 1.2
    static let chartInset: CGFloat = 8
    /// Head room above and below the curve, as a share of its span.
    static let chartPadding: Double = 0.14
    static let chartAreaOpacity: Double = 0.28
    static let chartLineStartOpacity: Double = 0.35
    static let chartHaloOpacity: Double = 0.22
    /// `.fail`, `.btn.danger`: the tint behind a refusal and behind Delete.
    static let dangerTint: Double = 0.16
    /// `.selv`: the highlight behind a value that the next key replaces.
    static let selectionTint: Double = 0.2
    /// `.hrow`: the weight and waist columns of the history list.
    static let historyWeightColumn: CGFloat = 78
    static let historyWaistColumn: CGFloat = 86
    /// `.dim`: a sheet's Cancel while a save is in flight.
    static let busyOpacity: Double = 0.4

    /// The frames' `data-ambient`, in the mockups' 402 pt design space: a green wash that grows with
    /// the count of met signals and an amber one that grows with the count of signals not met.
    static func metAmbient(count: Double) -> AmbientBlob {
        AmbientBlob(hue: .recoveryHigh, x: 70, y: 0, radius: 150 + 45 * count, alpha: 0.10 + 0.06 * count)
    }

    static func notMetAmbient(count: Double) -> AmbientBlob {
        AmbientBlob(hue: .recoveryMid, x: 350, y: 30, radius: 140 + 50 * count, alpha: 0.10 + 0.07 * count)
    }
}

// MARK: - Wiring

/// What the scorecard screens read and write through: the one shared model, the weigh-in store and
/// the clock. The app's is built from the repository and the profile; a debug demo supplies its own
/// through the environment.
@MainActor
struct ScorecardContext {
    let model: CutScorecardModel
    let settings: CutScorecardSettings
    let weighIns: WeighInStore
    let provider: BodyMeasurementProvider
    let unitSystem: () -> UnitSystem
    let now: () -> Date
    let timeZone: () -> TimeZone
    let locale: () -> Locale

    static func live(repository: Repository, profile: ProfileStore) -> ScorecardContext {
        let provider = BodyMeasurementProvider.live(repository: repository, profile: profile)
        return ScorecardContext(
            model: CutScorecardModel.live(repository: repository, profile: profile),
            settings: CutScorecardSettings(),
            weighIns: WeighInStore(repository: repository, provider: provider),
            provider: provider,
            unitSystem: {
                UnitSystem(rawValue: UserDefaults.standard.string(forKey: UnitPrefs.systemKey) ?? "") ?? .metric
            },
            now: { Date() },
            timeZone: { TimeZone.current },
            locale: { AppLanguage.activeLocale })
    }

    /// The local day the clock is on.
    var today: String { LocalDayWindows(timeZone: timeZone()).dayKey(for: now()) }

    func sheetModel(editing: WeighInHistoryRow? = nil) -> WeighInSheetModel {
        WeighInSheetModel(weighIns: weighIns, unitSystem: unitSystem(), now: now, timeZone: timeZone,
                          locale: locale(), editing: editing)
    }

    func historyModel() -> WeighInHistoryModel {
        WeighInHistoryModel(weighIns: weighIns, provider: provider, unitSystem: unitSystem, locale: locale)
    }
}

private struct ScorecardContextKey: EnvironmentKey {
    static let defaultValue: ScorecardContext? = nil
}

extension EnvironmentValues {
    /// Set only by the debug demo, so that a pushed screen and a presented sheet read the demo's
    /// synthetic store. Nil in the app: each screen builds the live context.
    var scorecardContextOverride: ScorecardContext? {
        get { self[ScorecardContextKey.self] }
        set { self[ScorecardContextKey.self] = newValue }
    }
}

/// Resolves the context a scorecard screen runs on and hands it to `content`.
struct ScorecardContextReader<Content: View>: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.scorecardContextOverride) private var override
    @ViewBuilder let content: (ScorecardContext) -> Content

    var body: some View {
        content(override ?? ScorecardContext.live(repository: repo, profile: profile))
    }
}

// MARK: - Signal and rule marks

extension CutScorecardSignalState {
    /// Met: Recovery green. Not met: Recovery mid amber. Unknown: neutral tertiary text.
    var scorecardColor: Color {
        switch self {
        case .met: return NoopTheme.recovery
        case .notMet: return NoopTheme.recoveryMid
        case .unknown: return NoopTheme.textTertiary
        }
    }
}

/// A signal's state as a shape: a check, a cross, or a dashed ring for unknown. The word beside it
/// carries the state; the colour repeats it.
struct ScorecardSignalGlyph: View {
    let state: CutScorecardSignalState
    @ScaledMetric(relativeTo: .subheadline) private var size = ScorecardLayout.signalGlyph

    var body: some View {
        Group {
            switch state {
            case .unknown:
                Circle()
                    .strokeBorder(NoopTheme.trackEmpty,
                                  style: StrokeStyle(lineWidth: ScorecardLayout.ringWidth, dash: ScorecardLayout.dash))
            case .met, .notMet:
                Circle()
                    .fill(state.scorecardColor.opacity(NoopTheme.Layout.shortcutIconOpacity))
                    .overlay {
                        Image(systemName: state == .met ? "checkmark" : "xmark")
                            .font(.system(size: size * ScorecardLayout.signalMarkRatio, weight: .bold))
                            .foregroundStyle(state.scorecardColor)
                    }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A rule's state. Neutral on purpose: a rule that fired is a fact, not a good or a bad week.
struct ScorecardRuleDot: View {
    let state: CutScorecardRuleState
    @ScaledMetric(relativeTo: .subheadline) private var box = ScorecardLayout.ruleDotBox
    @ScaledMetric(relativeTo: .subheadline) private var dot = ScorecardLayout.ruleDot

    var body: some View {
        Group {
            switch state {
            case .fired:
                Circle().fill(NoopTheme.textPrimary)
            case .notFired:
                Circle().strokeBorder(NoopTheme.textSecondary, lineWidth: ScorecardLayout.ringWidth)
            case .unknown:
                Circle().strokeBorder(NoopTheme.trackEmpty,
                                      style: StrokeStyle(lineWidth: ScorecardLayout.ringWidth,
                                                         dash: ScorecardLayout.dash))
            }
        }
        .frame(width: dot, height: dot)
        .frame(width: box, height: box)
        .accessibilityHidden(true)
    }
}

// MARK: - Text pieces

/// A section title with an optional trailing note or link, at `NoopSectionHeader`'s measures. Takes
/// resolved strings, since the scorecard's words come from the presenter.
struct ScorecardSectionHeader: View {
    let title: String
    var trailing: String?
    var action: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: NoopTheme.Layout.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: NoopTheme.Layout.s))
        layout {
            Text(verbatim: title)
                .noopFont(.sectionTitle)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if let trailing {
                if let action {
                    Button(action: action) {
                        HStack(spacing: NoopTheme.Layout.xs) {
                            trailingText(trailing)
                            FormKitChevron()
                        }
                        .frame(minHeight: NoopTheme.Layout.minTouchTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.noopPress)
                } else {
                    trailingText(trailing)
                }
            }
        }
        .padding(.top, NoopTheme.Layout.sectionTop)
        .padding(.bottom, NoopTheme.Layout.sectionBottom)
        .padding(.horizontal, NoopTheme.Layout.sectionSide)
    }

    private func trailingText(_ text: String) -> some View {
        Text(verbatim: text)
            .noopFont(.bodySmall, color: false)
            .foregroundStyle(NoopTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A number and its smaller unit. A nil value is the presenter's mark for "not measured", in the
/// secondary colour, with no unit.
struct ScorecardValueText: View {
    let value: String?
    let unit: String?
    let style: NoopType
    var color: Color = NoopTheme.textPrimary

    var body: some View {
        if let value {
            HStack(alignment: .firstTextBaseline, spacing: NoopTheme.Layout.xs) {
                Text(verbatim: value)
                    .noopFont(style, color: false)
                    .foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
                if let unit, !unit.isEmpty {
                    Text(verbatim: unit).noopFont(.unit)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            Text(verbatim: CutScorecardPresenter.missingValue)
                .noopFont(style, color: false)
                .foregroundStyle(NoopTheme.textSecondary)
        }
    }
}

/// A small caption under a card, aligned with the card's content.
struct ScorecardFootnote: View {
    let text: String
    var color: Color = NoopTheme.textTertiary

    var body: some View {
        Text(verbatim: text)
            .noopFont(.caption, color: false)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, NoopTheme.Layout.gutter + NoopTheme.Layout.captionInset)
            .padding(.top, NoopTheme.Layout.m)
    }
}

/// A row that leads somewhere: title, a value and a chevron. Stacks at accessibility sizes.
struct ScorecardLinkRow: View {
    let title: String
    let value: String?
    var showsDivider = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            if showsDivider { FormKitDivider() }
            HStack(spacing: NoopTheme.Layout.m) {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: NoopTheme.Layout.xs))
                    : AnyLayout(HStackLayout(spacing: NoopTheme.Layout.m))
                layout {
                    Text(verbatim: title)
                        .noopFont(.listTitle)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let value {
                        FormKitValue(verbatim: value)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                FormKitChevron()
            }
            .padding(.vertical, FormKitLayout.rowVertical)
            .frame(minHeight: NoopTheme.Layout.minTouchTarget)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Skeleton

/// Blank lines in the given type styles, so a loading block is as tall as the text it stands for
/// at any text size.
struct ScorecardSkeletonLines: View {
    let styles: [NoopType]

    var body: some View {
        VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
            ForEach(Array(styles.enumerated()), id: \.offset) { _, style in
                Text(verbatim: " ").noopFont(style)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }
}

// MARK: - Delete

/// The one red action (Delete): a full-width capsule, red label on a red tint.
struct ScorecardDangerButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .noopFont(.button, color: false)
            .foregroundStyle(NoopTheme.recoveryLow)
            .frame(maxWidth: .infinity, minHeight: NoopTheme.Layout.buttonHeight)
            .padding(.horizontal, NoopTheme.Layout.xl)
            .background(Capsule().fill(NoopTheme.recoveryLow.opacity(ScorecardLayout.dangerTint)))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? ScorecardLayout.busyOpacity * 2 : 1)
    }
}

// MARK: - Debug demo

extension View {
    /// DEBUG-only: `--demo-scroll <0…1>` opens a scroll view at that share of its content, so a
    /// simulator capture can show the part of a long screen below the first screenful. Without the
    /// argument, and in Release, the scroll view is untouched.
    func scorecardDemoScroll() -> some View {
        #if DEBUG
        let arguments = CommandLine.arguments
        let share = arguments.firstIndex(of: "--demo-scroll")
            .flatMap { arguments.indices.contains($0 + 1) ? Double(arguments[$0 + 1]) : nil }
        return defaultScrollAnchor(share.map { UnitPoint(x: 0.5, y: $0) })
        #else
        return self
        #endif
    }
}
