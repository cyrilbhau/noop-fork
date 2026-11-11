import SwiftUI
import StrandAnalytics
import StrandDesign

// Stage 1 (weigh-in and scorecard), specification §10.2, frames B1 to B27 of
// `design/round6-scorecard/`. Top to bottom: phase, verdict with the three rules, four signals,
// weight curve, waist curve, projection, "Log weigh-in", links to history and to phase and rules.
//
// The screen draws a `CutScorecardPresentation` and decides nothing: which sections exist, every
// word and every number are the presenter's. Loading shows a skeleton of the same layout.

/// The scorecard screen, pushed from its Today card, the Today weight row and the Health tab's row.
/// It exists only while the feature is on: when `noop.cutScorecardEnabled` goes off, wherever that
/// was done, the screen and every sheet it presents are torn down and it leaves the stack.
struct ScorecardView: View {
    @ObservedObject private var flag = CutScorecardFlag.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let reachable = CutScorecardPresenter.screenIsReachable(flagEnabled: flag.isEnabled)
        Group {
            if reachable {
                ScorecardContextReader { ScorecardScreen(context: $0) }
            } else {
                NoopTheme.canvas.ignoresSafeArea()
            }
        }
        .onChangeCompat(of: reachable) { if !$0 { dismiss() } }
        // The flag can go off while this screen is on a tab that is not showing.
        .onAppear { if !reachable { dismiss() } }
    }
}

/// The sheets the scorecard presents.
private enum ScorecardSheet: String, Identifiable {
    case weighIn, phase
    var id: String { rawValue }
}

struct ScorecardScreen: View {
    private let context: ScorecardContext
    @ObservedObject private var model: CutScorecardModel
    @State private var sheet: ScorecardSheet?
    @State private var showHistory = false
    /// The coach packet flag (stage 2 specification §10.1): its toolbar item shows only while on.
    @ObservedObject private var coachPacketFlag = CoachPacketSettings.flag
    @State private var showsCoachPacket = false
    /// Set only by the debug demo, whose screens run on a synthetic context and not on the flag.
    @Environment(\.scorecardContextOverride) private var demoContext
    @AppStorage(NoopTheme.Keys.ambientIntensity) private var ambientIntensityRaw = AmbientIntensity.balanced.rawValue

    init(context: ScorecardContext) {
        self.context = context
        _model = ObservedObject(wrappedValue: context.model)
    }

    private var shown: CutScorecardPresentation? {
        if case .loaded(let presentation) = model.state { return presentation }
        return nil
    }

    var body: some View {
        ScrollView {
            Group {
                if let shown {
                    ScorecardContent(
                        shown: shown,
                        onLogWeighIn: { sheet = .weighIn },
                        onHistory: { showHistory = true },
                        onPhase: { sheet = .phase })
                } else {
                    ScorecardSkeleton()
                }
            }
            .padding(.bottom, NoopTheme.Layout.xl)
        }
        .scorecardDemoScroll()
        .noopAmbientBackground(ambient)
        .navigationTitle(Text(verbatim: CutScorecardPresenter.cardTitle))
        .toolbar {
            // Beside the weigh-in button, and absent with the coach packet flag off.
            if coachPacketFlag.isEnabled {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsCoachPacket = true } label: { Image(systemName: "doc.plaintext") }
                        .accessibilityLabel(Text(verbatim: CoachPacketPresenter.toolbarAccessibilityLabel))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { sheet = .weighIn } label: { Image(systemName: "plus") }
                    .accessibilityLabel(Text(verbatim: CutScorecardPresenter.logWeighInTitle))
            }
        }
        .navigationDestination(isPresented: $showHistory) {
            Group {
                // In the app the pushed history follows the flag as this screen does.
                if demoContext == nil { WeighInHistoryView() } else { WeighInHistoryScreen(context: context) }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .weighIn:
                WeighInSheetScreen(context: context)
            case .phase:
                ScorecardPhaseSheet(context: context) {
                    Task { await model.load() }
                }
            }
        }
        .sheet(isPresented: $showsCoachPacket) { CoachPacketSheet() }
        .task { await model.load() }
    }

    /// The ambient wash is sized by how many signals are met and not met, and absent when all four
    /// are unknown.
    private var ambient: [AmbientBlob] {
        guard let shown else { return [] }
        let met = Double(shown.signals.filter { $0.state == .met }.count)
        let notMet = Double(shown.signals.filter { $0.state == .notMet }.count)
        let intensity = AmbientIntensity(rawValue: ambientIntensityRaw) ?? .balanced
        var blobs: [AmbientBlob] = []
        if met > 0 { blobs.append(ScorecardLayout.metAmbient(count: met)) }
        if notMet > 0 { blobs.append(ScorecardLayout.notMetAmbient(count: notMet)) }
        return blobs.map { $0.scaled(by: intensity) }
    }
}

// MARK: - Loaded

/// Everything below the navigation bar, for one presentation.
struct ScorecardContent: View {
    let shown: CutScorecardPresentation
    let onLogWeighIn: () -> Void
    let onHistory: () -> Void
    let onPhase: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Stage 3: the intake flag (§10.4). Off: the protein row is exactly stage 1's.
    @ObservedObject private var intakeFlag = IntakeSettings.flag

    private var stacks: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let phase = shown.phase {
                phaseHeader(phase).noopEntrance(index: 0)
            }
            if let due = shown.dueBanner {
                banner(due, action: CutScorecardPresenter.logWeighInTitle)
                    .padding(.top, NoopTheme.Layout.l)
                    .noopEntrance(index: 1)
            }
            if let reached = shown.targetBanner {
                banner(reached, action: nil)
                    .padding(.top, NoopTheme.Layout.l)
                    .noopEntrance(index: 1)
            }
            verdictCard
                .padding(.horizontal, NoopTheme.Layout.gutter)
                .padding(.top, NoopTheme.Layout.l)
                .noopEntrance(index: 2)

            ScorecardSectionHeader(title: CutScorecardPresenter.signalsTitle, trailing: shown.weekLabel)
            signalsCard
                .padding(.horizontal, NoopTheme.Layout.gutter)
                .noopEntrance(index: 3)
            ScorecardFootnote(text: shown.liftFootnote)

            ScorecardSectionHeader(title: CutScorecardPresenter.curvesTitle,
                                   trailing: CutScorecardPresenter.historyTitle, action: onHistory)
            VStack(spacing: NoopTheme.Layout.cardGap) {
                if let weight = shown.weight {
                    curveCard(weight).noopEntrance(index: 4)
                } else if let empty = shown.emptyCurvesText {
                    emptyCurves(empty).noopEntrance(index: 4)
                }
                if let waist = shown.waist {
                    curveCard(waist).noopEntrance(index: 5)
                }
                projectionCard.noopEntrance(index: 6)
            }
            .padding(.horizontal, NoopTheme.Layout.gutter)

            logWeighInButton
                .padding(.horizontal, NoopTheme.Layout.gutter)
                .padding(.top, NoopTheme.Layout.l)
            linksCard
                .padding(.horizontal, NoopTheme.Layout.gutter)
                .padding(.top, NoopTheme.Layout.l)
        }
    }

    // MARK: Phase

    private func phaseHeader(_ phase: CutScorecardPresentation.PhaseHeader) -> some View {
        VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
            Text(verbatim: phase.label).noopFont(.footnote)
            Text(verbatim: phase.name)
                .noopFont(.screenHeadline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: phase.detail)
                .noopFont(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, NoopTheme.Layout.gutter)
        .padding(.top, NoopTheme.Layout.s)
    }

    // MARK: Banners

    private func banner(_ banner: CutScorecardPresentation.Banner, action: String?) -> some View {
        let layout = stacks
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: NoopTheme.Layout.m))
            : AnyLayout(HStackLayout(spacing: NoopTheme.Layout.m))
        return layout {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
                Text(verbatim: banner.title)
                    .noopFont(.rowTitle)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: banner.detail)
                    .noopFont(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let action {
                Button(action: onLogWeighIn) {
                    Text(verbatim: action)
                        .noopFont(.pill, color: false)
                        .foregroundStyle(NoopTheme.canvas)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, NoopTheme.Layout.rowVerticalPadding)
                        .frame(minHeight: NoopTheme.Layout.pillHeight)
                        .background(Capsule().fill(NoopTheme.textPrimary))
                        .frame(minHeight: NoopTheme.Layout.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.noopPress)
            }
        }
        .padding(.vertical, NoopTheme.Layout.rowVerticalPadding)
        .padding(.horizontal, NoopTheme.Layout.l)
        .background {
            RoundedRectangle(cornerRadius: NoopTheme.Layout.tileRadius, style: .continuous)
                .fill(NoopTheme.control)
                .overlay {
                    RoundedRectangle(cornerRadius: NoopTheme.Layout.tileRadius, style: .continuous)
                        .strokeBorder(NoopTheme.cardBorder, lineWidth: NoopTheme.Layout.yourCardBorderWidth)
                }
        }
        .padding(.horizontal, NoopTheme.Layout.gutter)
    }

    // MARK: Verdict

    private var verdictCard: some View {
        let verdict = shown.verdict
        return NoopGlassCard {
            VStack(alignment: .leading, spacing: 0) {
                let layout = stacks
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: NoopTheme.Layout.xs))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: NoopTheme.Layout.m))
                layout {
                    Text(verbatim: verdict.header)
                        .noopFont(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let summary = verdict.signalsSummary {
                        Text(verbatim: summary)
                            .noopFont(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                verdictTitle(verdict)
                    .padding(.top, NoopTheme.Layout.s)
                ForEach(verdict.lines, id: \.self) { line in
                    Text(verbatim: line)
                        .noopFont(.bodySmall)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, NoopTheme.Layout.s)
                }
                ForEach(verdict.couldNotCheck, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: NoopTheme.Layout.s) {
                        ScorecardRuleDot(state: .unknown)
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + $0.height / 4 }
                        Text(verbatim: line)
                            .noopFont(.bodySmall, color: false)
                            .foregroundStyle(NoopTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, NoopTheme.Layout.s)
                }
                if let note = verdict.ownRuleNote {
                    Text(verbatim: note)
                        .noopFont(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, NoopTheme.Layout.m)
                }
                if let explanation = verdict.explanation {
                    Text(verbatim: explanation)
                        .noopFont(.bodySmall, color: false)
                        .foregroundStyle(NoopTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, NoopTheme.Layout.s)
                }
                if let action = verdict.action, let title = verdict.actionTitle {
                    verdictAction(action, title: title)
                }
                if !shown.rules.isEmpty {
                    FormKitDivider()
                        .padding(.top, NoopTheme.Layout.rowVerticalPadding)
                        .padding(.bottom, NoopTheme.Layout.s)
                    Text(verbatim: CutScorecardPresenter.rulesTitle)
                        .noopFont(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(shown.rules, id: \.rule) { rule in
                        ruleRow(rule)
                    }
                }
            }
        }
    }

    /// The verdict in the large title style on one line where it fits, and in the smaller style,
    /// wrapping, where it does not.
    private func verdictTitle(_ verdict: CutScorecardPresentation.Verdict) -> some View {
        let color = verdict.isWithheld ? NoopTheme.textSecondary : NoopTheme.textPrimary
        return ViewThatFits(in: .horizontal) {
            Text(verbatim: verdict.title)
                .noopFont(.largeTitle, color: false)
                .lineLimit(1)
            Text(verbatim: verdict.title)
                .noopFont(.statNumber, color: false)
                .fontWeight(.bold)
                .minimumScaleFactor(ScorecardLayout.verdictTitleMinScale)
                .fixedSize(horizontal: false, vertical: true)
                // A verdict can hold one long word ("carbohydrate"), which cannot wrap: past this
                // size it would run off the card. Up to it the title stays the largest text here.
                .dynamicTypeSize(...ScorecardLayout.verdictTitleMaxTextSize)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func verdictAction(_ action: CutScorecardPresentation.VerdictAction, title: String) -> some View {
        switch action {
        case .setUpPhase:
            Button(action: onPhase) { Text(verbatim: title) }
                .buttonStyle(NoopPrimaryButton())
                .padding(.top, NoopTheme.Layout.rowVerticalPadding)
        case .openPhaseAndRules:
            Button(action: onPhase) {
                HStack(spacing: NoopTheme.Layout.xs) {
                    Text(verbatim: title)
                        .noopFont(.rowTitle)
                        .fixedSize(horizontal: false, vertical: true)
                    FormKitChevron()
                }
                .frame(minHeight: NoopTheme.Layout.minTouchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.noopPress)
            .padding(.top, NoopTheme.Layout.xs)
        }
    }

    private func ruleRow(_ rule: CutScorecardPresentation.RuleRow) -> some View {
        let wordColor: Color
        switch rule.state {
        case .fired: wordColor = NoopTheme.textPrimary
        case .notFired: wordColor = NoopTheme.textSecondary
        case .unknown: wordColor = NoopTheme.textTertiary
        }
        let word = Text(verbatim: rule.stateWord)
            .noopFont(.pill, color: false)
            .foregroundStyle(wordColor)
            .fixedSize(horizontal: false, vertical: true)
        let names = VStack(alignment: .leading, spacing: FormKitLayout.detailGap) {
            Text(verbatim: rule.name)
                .noopFont(.rowTitle)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = rule.detail {
                Text(verbatim: detail)
                    .noopFont(.caption, color: false)
                    .foregroundStyle(NoopTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        return Group {
            if stacks {
                VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
                    ScorecardRuleDot(state: rule.state)
                    names
                    word
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: NoopTheme.Layout.s) {
                    ScorecardRuleDot(state: rule.state)
                    names.frame(maxWidth: .infinity, alignment: .leading)
                    word
                }
            }
        }
        .padding(.vertical, NoopTheme.Layout.s)
        .accessibilityElement(children: .combine)
    }

    // MARK: Signals

    private var signalsCard: some View {
        NoopGlassCard(flush: true) {
            VStack(spacing: 0) {
                ForEach(Array(shown.signals.enumerated()), id: \.offset) { index, signal in
                    if index > 0 { FormKitDivider() }
                    // Stage 3: the protein row (third of four) names its source and opens Intake.
                    if index == 2, intakeFlag.isEnabled {
                        ScorecardIntakeProteinRow { signalRow(signal) }
                    } else {
                        signalRow(signal)
                    }
                }
            }
        }
    }

    private func signalRow(_ signal: CutScorecardPresentation.SignalRow) -> some View {
        let word = Text(verbatim: signal.stateWord)
            .noopFont(.pill, color: false)
            .foregroundStyle(signal.state.scorecardColor)
            .fixedSize(horizontal: false, vertical: true)
        let words = VStack(alignment: .leading, spacing: FormKitLayout.detailGap) {
            Text(verbatim: signal.title)
                .noopFont(.rowTitle)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: signal.reason)
                .noopFont(.footnote, color: false)
                .foregroundStyle(NoopTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = signal.detail {
                Text(verbatim: detail)
                    .noopFont(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        return Group {
            if stacks {
                VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
                    ScorecardSignalGlyph(state: signal.state)
                    words
                    word
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: NoopTheme.Layout.m) {
                    ScorecardSignalGlyph(state: signal.state)
                    words.frame(maxWidth: .infinity, alignment: .leading)
                    word
                }
            }
        }
        .padding(.vertical, NoopTheme.Layout.rowVerticalPadding)
        .accessibilityElement(children: .combine)
    }

    // MARK: Curves

    private func curveCard(_ curve: CutScorecardPresentation.Curve) -> some View {
        NoopGlassCard {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: curve.title).noopFont(.footnote)
                ScorecardValueText(value: curve.value, unit: curve.unit, style: .tileNumber, countsUp: true)
                    .padding(.top, NoopTheme.Layout.xs)
                SourceCaption(verbatim: curve.provenance)
                    .padding(.top, NoopTheme.Layout.s)
                ScorecardWeekChart(points: curve.points, firstLabel: curve.firstLabel, lastLabel: curve.lastLabel)
                    .padding(.top, NoopTheme.Layout.m)
                factGrid(curve.facts)
                    .padding(.top, NoopTheme.Layout.rowVerticalPadding)
                if let note = curve.note {
                    Text(verbatim: note)
                        .noopFont(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, NoopTheme.Layout.s)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func factGrid(_ facts: [CutScorecardPresentation.Fact]) -> some View {
        let layout = stacks
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: NoopTheme.Layout.m))
            : AnyLayout(HStackLayout(alignment: .top, spacing: NoopTheme.Layout.m))
        return layout {
            ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                VStack(alignment: .leading, spacing: FormKitLayout.detailGap) {
                    Text(verbatim: fact.label)
                        .noopFont(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                    ScorecardValueText(value: fact.value, unit: fact.unit, style: .rowNumber)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func emptyCurves(_ text: String) -> some View {
        NoopGlassCard {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                Text(verbatim: CutScorecardPresenter.emptyCurvesTitle).noopFont(.footnote)
                ScorecardValueText(value: nil, unit: nil, style: .tileNumber)
                Text(verbatim: text).noopFont(.footnote)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Projection

    private var projectionCard: some View {
        let projection = shown.projection
        return NoopGlassCard {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
                let layout = stacks
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: NoopTheme.Layout.xs))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: NoopTheme.Layout.s))
                layout {
                    Text(verbatim: projection.label)
                        .noopFont(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                    if let estimate = projection.estimateLabel {
                        FormKitBadge(verbatim: estimate, tint: NoopTheme.textSecondary)
                    }
                }
                Text(verbatim: projection.text)
                    .noopFont(projection.isEstimate ? .rowTitle : .bodySmall, color: false)
                    .foregroundStyle(projection.isEstimate ? NoopTheme.textPrimary : NoopTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = projection.detail {
                    Text(verbatim: detail)
                        .noopFont(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions and links

    @ViewBuilder
    private var logWeighInButton: some View {
        let label = Text(verbatim: CutScorecardPresenter.logWeighInTitle)
        if shown.logWeighInIsPrimary {
            Button(action: onLogWeighIn) { label }.buttonStyle(NoopPrimaryButton())
        } else {
            Button(action: onLogWeighIn) { label }.buttonStyle(NoopSecondaryButton())
        }
    }

    private var linksCard: some View {
        NoopGlassCard(flush: true) {
            VStack(spacing: 0) {
                Button(action: onHistory) {
                    ScorecardLinkRow(title: CutScorecardPresenter.historyTitle, value: shown.historyValue,
                                     showsDivider: false)
                }
                Button(action: onPhase) {
                    ScorecardLinkRow(title: CutScorecardPresenter.phaseAndRulesTitle, value: shown.phaseLinkValue)
                }
            }
            .buttonStyle(.noopPress)
        }
    }
}

// MARK: - Loading

/// The loading state (frame B26): the loaded layout as shimmering blocks, each as tall as the text
/// it stands for.
struct ScorecardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScorecardSkeletonLines(styles: [.footnote, .screenHeadline, .footnote])
                .noopSkeleton(true, cornerRadius: NoopTheme.Layout.tileRadius)
                .padding(.horizontal, NoopTheme.Layout.gutter)
                .padding(.top, NoopTheme.Layout.s)
            block([.footnote, .largeTitle, .bodySmall, .bodySmall])
                .padding(.top, NoopTheme.Layout.l)
            sectionTitle
            block([.rowTitle, .footnote, .rowTitle, .footnote, .rowTitle, .footnote, .rowTitle, .footnote])
            sectionTitle
            NoopGlassCard {
                VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
                    ScorecardSkeletonLines(styles: [.footnote, .tileNumber])
                    Color.clear.frame(height: ScorecardLayout.chartHeight)
                }
            }
            .noopSkeleton(true)
            .padding(.horizontal, NoopTheme.Layout.gutter)
            block([.footnote, .rowTitle])
                .padding(.top, NoopTheme.Layout.cardGap)
        }
        .accessibilityHidden(true)
    }

    private func block(_ styles: [NoopType]) -> some View {
        NoopGlassCard { ScorecardSkeletonLines(styles: styles) }
            .noopSkeleton(true)
            .padding(.horizontal, NoopTheme.Layout.gutter)
    }

    private var sectionTitle: some View {
        ScorecardSkeletonLines(styles: [.sectionTitle])
            .frame(width: ScorecardLayout.skeletonSectionTitleWidth)
            .noopSkeleton(true, cornerRadius: NoopTheme.Layout.tileRadius)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, NoopTheme.Layout.sectionTop)
            .padding(.bottom, NoopTheme.Layout.sectionBottom)
            .padding(.horizontal, NoopTheme.Layout.sectionSide)
    }
}
