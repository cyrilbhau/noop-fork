import SwiftUI
import Foundation
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Insights Hub (v5)
//
// The headline n-of-1 "what actually moves YOUR recovery" surface. Two halves, both
// pure association on the user's own logged days — never advice, diagnosis, or cause:
//
//  1. WHAT MOVES YOUR CHARGE — the unified, LAG-AWARE EffectRanker feed. For each
//     journal behaviour × the selected outcome it keeps the strongest honest lag
//     ({0,+1,+2} days), so each row reads "shows up the next morning" rather than
//     pretending everything is same-day. Each card carries the sign-aware sentence,
//     with/without means, a lead/lag chip, the effect-size word, and a Solid /
//     Building / Calibrating confidence pill — NOT a bare "significant" stamp.
//
//  2. ALCOHOL / CAFFEINE DOSE-RESPONSE — the personal DoseResponseEngine curve. A
//     per-user slope that SHRINKS toward a documented population prior until enough
//     nights accrue. The card plots the shrunk curve, states "each extra drink ≈ −N
//     for you" (honest when still prior-dominated, or when YOUR data contradicts the
//     prior), and an evening "damage forecast" preview — "a 2nd drink tonight ≈ −X
//     Charge tomorrow" — composed from the curve's per-unit Δ on the latest Charge.
//
// SELF-CONTAINED: this screen owns its own load/derive (InsightsHubViewModel) and takes
// the Repository via @EnvironmentObject — it does NOT edit AppModel / the central nav.
// Wave 3 surfaces it as the head of the Insights hub (see 'wiringNeeded').
//
// All maths lives in StrandAnalytics (EffectRanker / DoseResponseEngine / DoseResponsePriors);
// this view loads the series, shapes the engine inputs, and presents honestly.

struct InsightsHubView: View {
    @EnvironmentObject private var repo: Repository
    @StateObject private var model = InsightsHubViewModel()

    /// The currently-selected outcome for the ranked feed (Charge / HRV / Rest / RHR).
    @State private var outcome: InsightsHubViewModel.Outcome = .recovery

    #if os(iOS)
    /// The iPhone redesign switch (Settings). On by default; off restores the classic screen.
    @AppStorage(NoopTheme.Keys.redesignEnabled) private var redesignEnabled = true
    @AppStorage(NoopTheme.Keys.ambientIntensity) private var ambientIntensityRaw = AmbientIntensity.balanced.rawValue
    #endif

    var body: some View {
        Group {
            #if os(iOS)
            // iPhone redesign (C6): the same view model, ranking and dose cards, drawn as diverging bars.
            if redesignEnabled { hubRedesignScreen } else { classicScaffold }
            #else
            classicScaffold
            #endif
        }
        .task(id: repo.refreshSeq) { await model.load(repo: repo) }
        .onChangeCompat(of: outcome) { model.rankFor($0) }
    }

    /// The classic Insights hub (macOS, and iOS with the redesign switched off). Unchanged layout.
    private var classicScaffold: some View {
        ScreenScaffold(title: "Insights",
                       subtitle: "Patterns in your own data: association, not cause.",
                       // PERF (scroll): lazy column — byte-identical layout (LazyVStack == eager VStack
                       // alignment/spacing/header). The content is one inner eager VStack, so the staggered
                       // mover reveal is unchanged; this only defers building that stack until it scrolls in.
                       lazy: true) {
            if !model.loaded {
                ComingSoon(what: "Reading your journal and outcomes…")
            } else {
                VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                    moversSection
                    doseSection
                    methodNote
                }
            }
        }
    }

    // MARK: - What moves your Charge (ranked, lag-aware)

    private var moversSection: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            // Header and the 4-segment outcome control each get their own row — one HStack
            // crushed the pill control on narrow widths and truncated the segment labels.
            SectionHeader("What moves your \(outcome.outcomeName.lowercased())",
                          overline: "Ranked · your data")
            SegmentedPillControl(InsightsHubViewModel.Outcome.allCases, selection: $outcome) { $0.label }
                .accessibilityLabel("Outcome metric")
                .frame(maxWidth: .infinity, alignment: .leading)

            if model.ranked.isEmpty {
                NoopCard {
                    Text(String(localized: "Not enough overlap between your journal answers and \(outcome.outcomeName.lowercased()) yet. Keep logging. Each behaviour needs days both with and without it before NOOP can read its effect."))
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ForEach(model.ranked.indices, id: \.self) { i in
                    moverCard(model.ranked[i])
                        .staggeredAppear(index: i)
                }
            }
        }
    }

    /// One ranked, lag-aware mover row: behaviour → effect on the outcome, with the
    /// best lead/lag, with/without means, effect-size word, and a confidence pill.
    private func moverCard(_ r: RankedEffect) -> some View {
        let e = r.effect
        // Sign-aware tint: did this behaviour move the outcome the GOOD way?
        let movedGood: Bool? = e.delta == 0 ? nil : ((e.delta > 0) == outcome.higherIsBetter)
        let tint: StrandTone = {
            guard let good = movedGood else { return .neutral }
            if e.significant { return good ? .positive : .critical }
            return good ? .positive : .warning
        }()
        let tintColor = toneColor(tint)
        let deltaText: String = {
            let arrow = e.delta > 0 ? "↑" : (e.delta < 0 ? "↓" : "→")
            if let pct = e.pctChange { return "\(arrow) \(Int(abs(pct).rounded()))%" }
            return "\(arrow) \(String(format: "%.1f", abs(e.delta)))"
        }()

        return NoopCard(tint: outcome.domain.color) {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                // Header: behaviour name + lead/lag chip + confidence pill.
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 8) {
                        Circle().fill(tintColor).frame(width: 8, height: 8)
                        Text(r.behavior)
                            .font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    StatePill(LocalizedStringKey(r.leadLagText), tone: .accent, showsDot: false)
                    ScoreStatePill(Self.scoreState(r.confidence))
                }

                // The engine's sign-aware sentence (includes the lead/lag clause).
                Text(MetricCatalog.scoreDisplayText(r.sentence()))
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // With / without means as uniform StatTiles.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 168), spacing: NoopMetrics.gap)],
                          alignment: .leading, spacing: NoopMetrics.gap) {
                    StatTile(label: "With",
                             value: outcome.format(e.meanWith),
                             caption: "n = \(e.nWith)",
                             accent: tintColor,
                             delta: deltaText,
                             deltaColor: tintColor)
                    StatTile(label: "Without",
                             value: outcome.format(e.meanWithout),
                             caption: "n = \(e.nWithout)",
                             accent: StrandPalette.textPrimary)
                }

                Divider().overlay(StrandPalette.hairline)

                // Effect-size footer: Cohen's d + magnitude word.
                HStack {
                    Text("Effect size").strandOverline()
                    Spacer()
                    HStack(spacing: 6) {
                        Text(String(format: "d = %.2f", e.cohensD))
                            .font(StrandFont.captionNumber)
                            .foregroundStyle(tintColor)
                        Text(Self.effectMagnitudeWord(e.cohensD))
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        // One whole-string key; the args are complete sentences, never concatenated tails.
        .accessibilityLabel(String(localized: "\(MetricCatalog.scoreDisplayText(r.sentence())) Cohen's d \(String(format: "%.2f", e.cohensD)). \(Self.scoreState(r.confidence).accessibilityWord)"))
    }

    // MARK: - Alcohol / caffeine dose-response

    private var doseSection: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Dose-response", overline: "Personal curve · prior-shrunk")
            if model.doseCards.isEmpty {
                NoopCard {
                    Text(String(localized: "Log alcohol or late caffeine with an amount and NOOP fits a personal dose curve: how much each extra unit tends to move your numbers. Until then it shows typical patterns, clearly labelled as not yet yours."))
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ForEach(Array(model.doseCards.enumerated()), id: \.element.id) { index, card in
                    DoseResponseCardView(card: card)
                        .staggeredAppear(index: index)
                }
            }
        }
    }

    // MARK: - Method / honesty note

    private var methodNote: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("How to read this").strandOverline()
                Text(String(localized: "Everything here is a pattern in your own logged days: an association with an effect size and confidence, never a cause or a diagnosis. Population patterns are shown as \u{201C}typical\u{201D} and are always overridden by your own data once you have enough of it. Approximations, not WHOOP\u{2019}s scores; not a medical device."))
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Helpers

    private func toneColor(_ tone: StrandTone) -> Color {
        switch tone {
        case .neutral:  return StrandPalette.textSecondary
        case .accent:   return StrandPalette.accent
        case .positive: return StrandPalette.statusPositive
        case .warning:  return StrandPalette.statusWarning
        case .critical: return StrandPalette.statusCritical
        }
    }

    /// Map the engine's ScoreConfidence tier to the design-system ScoreState pill.
    static func scoreState(_ c: ScoreConfidence) -> ScoreState {
        switch c {
        case .solid:       return .solid
        case .building:    return .building
        case .calibrating: return .calibrating
        }
    }

    /// Cohen's d → conventional magnitude word.
    static func effectMagnitudeWord(_ d: Double) -> String {
        switch abs(d) {
        case ..<0.2: return String(localized: "negligible")
        case ..<0.5: return String(localized: "small")
        case ..<0.8: return String(localized: "moderate")
        default:     return String(localized: "large")
        }
    }
}

private extension ScoreState {
    /// VoiceOver-only certainty phrase for a mover row.
    var accessibilityWord: String {
        switch self {
        case .solid:       return String(localized: "Solid signal.")
        case .building:    return String(localized: "Building. Keep logging.")
        case .calibrating: return String(localized: "Calibrating. Too thin to read yet.")
        case .live:        return ""
        }
    }
}

// MARK: - Dose-response card
//
// The headline alcohol/caffeine surface: the prior-shrunk curve, the per-unit read,
// the confidence pill, the honesty banner, and an evening "damage forecast" preview
// driven by a tiny dose stepper. The forecast is a what-if on the user's own latest
// Charge — "a 2nd drink tonight tends to line up with about −7 on tomorrow's Charge
// for you" — never a recommendation to drink or abstain.

private struct DoseResponseCardView: View {
    let card: InsightsHubViewModel.DoseCard
    /// Draws the iPhone redesign (C6) instead of the classic card; same state and copy.
    var redesign = false

    /// The "what if I have one more" preview dose, defaulting to one above the typical
    /// starting point so the headline reads as a 2nd-drink forecast out of the box.
    @State private var previewDose: Int = 2

    private var domain: DomainTheme { card.outcomeName == "HRV" ? .rest : .charge }

    var body: some View {
        #if os(iOS)
        if redesign { redesignBody } else { classicBody }
        #else
        classicBody
        #endif
    }

    private var classicBody: some View {
        let r = card.response
        return NoopCard(tint: domain.color) {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                header(r)

                // The engine's honest read sentence (prior / yours / contradicts-prior).
                Text(MetricCatalog.scoreDisplayText(r.sentence()))
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // The prior-shrunk curve (dose on x, modelled outcome Δ on y).
                DoseCurveChart(points: r.curve, accent: domain.color,
                               unitLabel: card.unitLabel, outcomeName: card.outcomeName)
                    .frame(height: 132)
                    .accessibilityLabel(curveAccessibilityLabel(r))

                if r.priorDominated {
                    honestyBanner(String(localized: "Based mostly on typical patterns, not yet yours. Log a few more \(card.unitLabel.lowercased()) days and this becomes yours."),
                        tone: .neutral)
                } else if r.contradictsPrior {
                    honestyBanner(String(localized: "In your data so far, this doesn\u{2019}t move your \(card.outcomeName) the way it typically does."), tone: .positive)
                }

                if card.timingProxy {
                    Text("\u{201C}Dose\u{201D} here is timing (later in the day = stronger), not milligrams.")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().overlay(StrandPalette.hairline)

                damageForecast(r)
            }
        }
    }

    // MARK: Header

    private func header(_ r: DoseResponse) -> some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 8) {
                Image(systemName: card.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(domain.color)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text(card.title)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
            }
            Spacer(minLength: 8)
            ScoreStatePill(InsightsHubView.scoreState(r.confidence))
        }
    }

    // MARK: Evening damage forecast (what-if on the user's latest Charge)

    @ViewBuilder private func damageForecast(_ r: DoseResponse) -> some View {
        let (delta, projected, stepLabel) = forecastInputs(r)

        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            // Overline and the dose stepper each get their own row — sharing one HStack
            // compressed the 0/1/2/3+ stepper and truncated its segments on narrow widths.
            Text(card.forecastOverline).strandOverline()
                .frame(maxWidth: .infinity, alignment: .leading)
            SegmentedPillControl(card.doseChoices, selection: $previewDose) { card.doseChoiceLabel($0) }
                .accessibilityLabel("Preview dose")
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(forecastSentence(delta: delta, projected: projected, stepLabel: stepLabel))
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: NoopMetrics.gap)],
                      alignment: .leading, spacing: NoopMetrics.gap) {
                StatTile(label: "Per extra \(card.unitNoun)",
                         value: signed(r.perUnit, suffix: card.outcomeSuffix),
                         caption: r.priorDominated ? String(localized: "typical") : String(localized: "your data"),
                         accent: r.perUnit < 0 ? StrandPalette.statusCritical : StrandPalette.statusPositive)
                StatTile(label: "Tomorrow\u{2019}s \(card.outcomeName)",
                         value: projected.map { "\(Int($0.rounded()))\(card.outcomeSuffix)" } ?? "—",
                         caption: projected != nil ? String(localized: "projected · \(stepLabel)") : String(localized: "needs a recent day"),
                         accent: domain.color)
            }
        }
    }

    /// The Δ of going from the typical starting dose (1) to the previewed dose, applied to the user's most
    /// recent outcome value as an honest "where you'd likely land". Shared by both layouts.
    private func forecastInputs(_ r: DoseResponse) -> (delta: Double, projected: Double?, stepLabel: String) {
        let fromDose = 1
        let delta = r.delta(fromDose: fromDose, toDose: previewDose)
        let projected = card.latestOutcome.map { max(0, min(card.outcomeCeiling, $0 + delta)) }
        let stepLabel = previewDose <= 1 ? String(localized: "no extra") : card.stepLabel(previewDose)
        return (delta, projected, stepLabel)
    }

    /// Whole-phrase variants per direction and basis, so translators never see stitched
    /// lower/higher or basis fragments.
    private func forecastSentence(delta: Double, projected: Double?, stepLabel: String) -> String {
        if previewDose <= 1 {
            return String(localized: "No extra tonight. Your \(card.outcomeName.lowercased()) forecast stays where it is.")
        }
        let magText = "\(Int(abs(delta).rounded()))\(card.outcomeSuffix)"
        let lower = delta <= 0
        if card.response.priorDominated {
            return lower
                ? String(localized: "A \(stepLabel) tonight tends to line up with about \(magText) lower on tomorrow\u{2019}s \(card.outcomeName.lowercased()) for you, based on typical patterns.")
                : String(localized: "A \(stepLabel) tonight tends to line up with about \(magText) higher on tomorrow\u{2019}s \(card.outcomeName.lowercased()) for you, based on typical patterns.")
        }
        return lower
            ? String(localized: "A \(stepLabel) tonight tends to line up with about \(magText) lower on tomorrow\u{2019}s \(card.outcomeName.lowercased()) for you, based on \(card.response.nUser) of your \(card.unitLabel.lowercased()) days.")
            : String(localized: "A \(stepLabel) tonight tends to line up with about \(magText) higher on tomorrow\u{2019}s \(card.outcomeName.lowercased()) for you, based on \(card.response.nUser) of your \(card.unitLabel.lowercased()) days.")
    }

    // MARK: Bits

    private func honestyBanner(_ text: String, tone: StrandTone) -> some View {
        HStack(alignment: .top, spacing: NoopMetrics.space2) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tone == .neutral ? StrandPalette.textTertiary : StrandPalette.statusPositive)
            Text(text)
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(NoopMetrics.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoopPanelSurface(cornerRadius: 8))
    }

    private func signed(_ v: Double, suffix: String) -> String {
        let mag = abs(v)
        let rounded = (mag * 10).rounded() / 10
        let sign = v < 0 ? "−" : (v > 0 ? "+" : "")
        // Show whole numbers without a trailing .0 for the small Charge magnitudes.
        let body = rounded == rounded.rounded() ? "\(Int(rounded))" : String(format: "%.1f", rounded)
        return "\(sign)\(body)\(suffix)"
    }

    /// Whole-string key per variant (never a concatenated localized tail on an a11y label).
    private func curveAccessibilityLabel(_ r: DoseResponse) -> String {
        r.priorDominated
            ? String(localized: "Dose-response curve. Each extra \(card.unitNoun) lines up with about \(signed(r.perUnit, suffix: card.outcomeSuffix)) on \(card.outcomeName), typical patterns.")
            : String(localized: "Dose-response curve. Each extra \(card.unitNoun) lines up with about \(signed(r.perUnit, suffix: card.outcomeSuffix)) on \(card.outcomeName), your own data.")
    }
}

// MARK: - Dose curve chart
//
// A compact line+area chart of the prior-shrunk curve: dose on x (0…max), the modelled
// outcome DELTA on y. Drawn with the house Path idiom (no extra dependency) so it sits
// in the design system. Zero-line is marked; the line is tinted to the domain colour.

private struct DoseCurveChart: View {
    let points: [DoseCurvePoint]
    let accent: Color
    let unitLabel: String
    let outcomeName: String

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let deltas = points.map(\.outcomeDelta)
            let maxAbs = max(1.0, (deltas.map(abs).max() ?? 1.0))
            // Symmetric y range around zero so the sign reads honestly.
            let yFor: (Double) -> CGFloat = { d in
                let t = (d / maxAbs + 1) / 2          // 0 (most negative) … 1 (most positive)
                return h - CGFloat(t) * h
            }
            let n = max(1, points.count - 1)
            let xFor: (Int) -> CGFloat = { i in CGFloat(i) / CGFloat(n) * w }
            let zeroY = yFor(0)

            ZStack(alignment: .topLeading) {
                // Zero baseline.
                Path { p in
                    p.move(to: CGPoint(x: 0, y: zeroY))
                    p.addLine(to: CGPoint(x: w, y: zeroY))
                }
                .stroke(StrandPalette.hairlineStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                // Filled area between the curve and the zero line.
                Path { p in
                    guard !points.isEmpty else { return }
                    p.move(to: CGPoint(x: xFor(0), y: zeroY))
                    for (i, pt) in points.enumerated() {
                        p.addLine(to: CGPoint(x: xFor(i), y: yFor(pt.outcomeDelta)))
                    }
                    p.addLine(to: CGPoint(x: xFor(points.count - 1), y: zeroY))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [accent.opacity(0.22), accent.opacity(0.03)],
                                     startPoint: .top, endPoint: .bottom))

                // The curve line.
                Path { p in
                    for (i, pt) in points.enumerated() {
                        let point = CGPoint(x: xFor(i), y: yFor(pt.outcomeDelta))
                        if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
                    }
                }
                .stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                // Dose markers.
                ForEach(points.indices, id: \.self) { i in
                    Circle()
                        .fill(accent)
                        .frame(width: 5, height: 5)
                        .position(x: xFor(i), y: yFor(points[i].outcomeDelta))
                }
            }
        }
        .accessibilityElement()
    }
}

// MARK: - iPhone redesign (C6 What moves you)
//
// `design/round3/sleep-health.html` C6 over the same view model: the lag-aware ranked feed as diverging
// bars around a centre rule, each with its confidence tier and group sizes, tap to expand the existing
// sentence, means and effect size. The dose-response cards keep their curve, honesty banners and
// what-if stepper. The experiment itself lives on the Journal screen, linked from here.

#if os(iOS)
extension InsightsHubView {
    var hubRedesignScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hubRdHeader
                    .noopEntrance(index: 0)
                SegmentedPills(InsightsHubViewModel.Outcome.allCases, selection: $outcome) { Text(verbatim: $0.label) }
                    .accessibilityLabel(Text("Outcome metric"))
                    .padding(.horizontal, NoopTheme.Layout.gutter)
                    .padding(.top, NoopTheme.Layout.l)
                if !model.loaded {
                    NoopGlassCard {
                        Text("Reading your journal and outcomes…")
                            .noopFont(.bodySmall)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .noopSkeleton(true)
                    .padding(.horizontal, NoopTheme.Layout.gutter)
                    .padding(.top, NoopTheme.Layout.l)
                } else {
                    hubRdMovers
                        .padding(.horizontal, NoopTheme.Layout.gutter)
                        .padding(.top, NoopTheme.Layout.l)
                        .noopEntrance(index: 1)
                    hubRdExperimentLink
                        .noopEntrance(index: 2)
                    InsightsSectionTitle("Dose-response")
                    hubRdDose
                        .padding(.horizontal, NoopTheme.Layout.gutter)
                        .noopEntrance(index: 3)
                    InsightsSectionTitle("How to read this")
                    NoopGlassCard {
                        Text(String(localized: "Everything here is a pattern in your own logged days: an association with an effect size and confidence, never a cause or a diagnosis. Population patterns are shown as \u{201C}typical\u{201D} and are always overridden by your own data once you have enough of it. Approximations, not WHOOP\u{2019}s scores; not a medical device."))
                            .noopFont(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, NoopTheme.Layout.gutter)
                }
            }
            .padding(.bottom, NoopMetrics.tabBarClearance)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .insightsAmbient(.whatMovesYou, intensityRaw: ambientIntensityRaw)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var hubRdHeader: some View {
        let days = model.loaded ? model.answeredOutcomeDayCount(outcome) : 0
        return InsightsScreenHeader(
            titleText: Text("What moves your \(outcome.outcomeName)"),
            subtitleText: days > 0 ? Text("From \(days) logged days of your own data") : nil)
    }

    // MARK: Movers

    @ViewBuilder
    private var hubRdMovers: some View {
        if model.ranked.isEmpty {
            NoopGlassCard {
                Text(verbatim: String(localized: "Not enough overlap between your journal answers and \(outcome.outcomeName.lowercased()) yet. Keep logging. Each behaviour needs days both with and without it before NOOP can read its effect."))
                    .noopFont(.bodySmall)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            let fractions = InsightsDivergingBar.fractions(model.ranked.map { $0.effect.pctChange ?? $0.effect.delta })
            VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
                NoopGlassCard(flush: true) {
                    ForEach(model.ranked.indices, id: \.self) { i in
                        hubRdMoverRow(model.ranked[i], fraction: fractions[i], showsDivider: i > 0)
                    }
                }
                (Text("Average change versus days without it.") + Text(verbatim: " ")
                 + Text("A pattern in your data, not proof of cause."))
                    .noopFont(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, NoopTheme.Layout.xs)
            }
        }
    }

    private func hubRdConfidenceWord(_ c: ScoreConfidence) -> String {
        switch c {
        case .solid: return String(localized: "Solid")
        case .building: return String(localized: "Building")
        case .calibrating: return String(localized: "Calibrating")
        }
    }

    private func hubRdLagWord(_ lag: Int) -> String {
        switch lag {
        case 0: return String(localized: "Same day")
        case 1: return String(localized: "Next morning")
        default: return String(localized: "\(lag) mornings later")
        }
    }

    private func hubRdMoverRow(_ r: RankedEffect, fraction: Double, showsDivider: Bool) -> some View {
        let e = r.effect
        let movedGood: Bool? = e.delta == 0 ? nil : ((e.delta > 0) == outcome.higherIsBetter)
        let color: Color = movedGood.map { good in
            good ? NoopTheme.recovery : (e.significant ? NoopTheme.recoveryLow : NoopTheme.recoveryMid)
        } ?? NoopTheme.textTertiary
        let sign = e.delta > 0 ? "+" : (e.delta < 0 ? "−" : "")
        let value = e.pctChange.map { "\(sign)\(Int(abs($0).rounded()))%" } ?? "\(sign)\(outcome.format(abs(e.delta)))"
        let groups = String(localized: "\(hubRdConfidenceWord(r.confidence)) · \(e.nWith) days with, \(e.nWithout) without")
        return InsightsEffectRow(
            title: r.behavior,
            caption: "\(groups) · \(hubRdLagWord(r.lag))",
            valueText: value, fraction: fraction, color: color, muted: !e.significant,
            showsDivider: showsDivider
        ) {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
                Text(verbatim: MetricCatalog.scoreDisplayText(r.sentence()))
                    .noopFont(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                StatGrid([
                    StatGridItem("With", value: outcome.format(e.meanWith)),
                    StatGridItem("Without", value: outcome.format(e.meanWithout)),
                    StatGridItem("Effect size", value: String(format: "d = %.2f", e.cohensD),
                                 unit: Self.effectMagnitudeWord(e.cohensD)),
                ], columns: 3)
            }
        }
    }

    // MARK: Experiment link

    private var hubRdExperimentLink: some View {
        VStack(alignment: .leading, spacing: 0) {
            InsightsSectionTitle("Try an experiment")
            NavigationLink { InsightsView() } label: {
                NoopGlassCard {
                    VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                        Text("Run a clean personal test").noopFont(.rowTitle)
                        Text("Pick one behaviour you log, one outcome, and a short window. NOOP compares the days you log the behaviour against your behaviour-free days before the start.")
                            .noopFont(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: NoopTheme.Layout.xs) {
                            Text("Personal Experiment").noopFont(.bodySmall, color: false)
                                .foregroundStyle(NoopTheme.coach)
                            Image(systemName: "chevron.right")
                                .noopFont(.footnote, color: false)
                                .foregroundStyle(NoopTheme.coach)
                                .accessibilityHidden(true)
                        }
                        .padding(.top, NoopTheme.Layout.xs)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .insightsTintedCard(NoopTheme.coach)
            }
            .buttonStyle(.noopPress)
            .padding(.horizontal, NoopTheme.Layout.gutter)
        }
    }

    // MARK: Dose-response

    @ViewBuilder
    private var hubRdDose: some View {
        if model.doseCards.isEmpty {
            NoopGlassCard {
                Text(String(localized: "Log alcohol or late caffeine with an amount and NOOP fits a personal dose curve: how much each extra unit tends to move your numbers. Until then it shows typical patterns, clearly labelled as not yet yours."))
                    .noopFont(.bodySmall)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: NoopTheme.Layout.cardGap) {
                ForEach(model.doseCards) { card in
                    DoseResponseCardView(card: card, redesign: true)
                }
            }
        }
    }
}

extension DoseResponseCardView {
    private var rdColor: Color { card.outcomeName == "HRV" ? NoopTheme.hrv : NoopTheme.recovery }

    var redesignBody: some View {
        let r = card.response
        let (delta, projected, stepLabel) = forecastInputs(r)
        return NoopGlassCard {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
                HStack(spacing: NoopTheme.Layout.m) {
                    DomainIcon(systemImage: card.symbol, color: rdColor, size: DomainIcon.smallSize)
                    Text(verbatim: card.title).noopFont(.rowTitle)
                    Spacer(minLength: NoopTheme.Layout.s)
                    Text(verbatim: rdConfidenceWord(r.confidence)).noopFont(.caption)
                }
                Text(verbatim: MetricCatalog.scoreDisplayText(r.sentence()))
                    .noopFont(.bodySmall)
                    .fixedSize(horizontal: false, vertical: true)
                // The prior-shrunk curve: dose on x, modelled change on y. No zero rule, no gridlines.
                NoopLineChart(
                    points: r.curve.map { NoopChartPoint(x: Double($0.dose), y: $0.outcomeDelta) },
                    color: rdColor,
                    xLabels: r.curve.map { card.doseChoiceLabel($0.dose) },
                    accessibilityLabel: Text(verbatim: curveAccessibilityLabel(r)),
                    valueFormat: { signed($0, suffix: card.outcomeSuffix) })
                    .frame(height: InsightsLayout.stressTrendChart)
                if r.priorDominated {
                    rdNote(String(localized: "Based mostly on typical patterns, not yet yours. Log a few more \(card.unitLabel.lowercased()) days and this becomes yours."))
                } else if r.contradictsPrior {
                    rdNote(String(localized: "In your data so far, this doesn\u{2019}t move your \(card.outcomeName) the way it typically does."))
                }
                if card.timingProxy {
                    Text("\u{201C}Dose\u{201D} here is timing (later in the day = stronger), not milligrams.")
                        .noopFont(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Rectangle().fill(NoopTheme.separator).frame(height: 1).accessibilityHidden(true)
                Text(verbatim: card.forecastOverline).noopFont(.footnote)
                SegmentedPills(card.doseChoices, selection: $previewDose) { Text(verbatim: card.doseChoiceLabel($0)) }
                    .accessibilityLabel(Text("Preview dose"))
                Text(verbatim: forecastSentence(delta: delta, projected: projected, stepLabel: stepLabel))
                    .noopFont(.bodySmall)
                    .fixedSize(horizontal: false, vertical: true)
                StatGrid([
                    StatGridItem("Per extra \(card.unitNoun)", value: signed(r.perUnit, suffix: card.outcomeSuffix),
                                 unit: r.priorDominated ? String(localized: "typical") : String(localized: "your data")),
                    StatGridItem("Tomorrow\u{2019}s \(card.outcomeName)",
                                 value: projected.map { "\(Int($0.rounded()))\(card.outcomeSuffix)" }),
                ])
                Text(verbatim: projected != nil ? String(localized: "projected · \(stepLabel)")
                                                : String(localized: "needs a recent day"))
                    .noopFont(.caption)
            }
        }
    }

    private func rdConfidenceWord(_ c: ScoreConfidence) -> String {
        switch c {
        case .solid: return String(localized: "Solid")
        case .building: return String(localized: "Building")
        case .calibrating: return String(localized: "Calibrating")
        }
    }

    private func rdNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: NoopTheme.Layout.s) {
            Image(systemName: "info.circle.fill")
                .noopFont(.caption, color: false)
                .foregroundStyle(NoopTheme.textTertiary)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .noopFont(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
#endif

// MARK: - View-model
//
// Self-contained: loads the journal (behaviour → days), dose rows (under the dedicated
// noop-journal-dose source), and the outcome series (imported metricSeries ∪ DailyMetric
// fallback, exactly as InsightsView), then runs EffectRanker for the ranked feed and
// DoseResponseEngine for each dosed behaviour the user has data for. No edits to AppModel.

@MainActor
final class InsightsHubViewModel: ObservableObject {

    // MARK: Outcome

    enum Outcome: String, CaseIterable, Identifiable {
        case recovery, hrv, sleep, rhr
        var id: String { rawValue }
        var label: String {
            switch self {
            case .recovery: return String(localized: "Charge")
            case .hrv:      return "HRV"
            case .sleep:    return String(localized: "Rest")
            case .rhr:      return "RHR"
            }
        }
        /// metricSeries key.
        var key: String {
            switch self {
            case .recovery: return "recovery"
            case .hrv:      return "hrv"
            case .sleep:    return "sleep_performance"
            case .rhr:      return "rhr"
            }
        }
        /// The engine's outcome label (carried onto each RankedEffect).
        var outcomeName: String {
            switch self {
            case .recovery: return String(localized: "Charge")
            case .hrv:      return "HRV"
            case .sleep:    return String(localized: "Rest")
            case .rhr:      return String(localized: "Resting HR")
            }
        }
        var higherIsBetter: Bool { self != .rhr }
        var domain: DomainTheme {
            switch self {
            case .recovery: return .charge
            case .hrv, .sleep: return .rest
            case .rhr: return .stress
            }
        }
        func format(_ v: Double) -> String {
            switch self {
            case .recovery, .sleep: return "\(Int(v.rounded()))%"
            case .hrv:              return "\(Int(v.rounded())) ms"
            case .rhr:              return "\(Int(v.rounded())) bpm"
            }
        }
    }

    // MARK: Published state

    @Published private(set) var loaded = false
    @Published private(set) var ranked: [RankedEffect] = []
    @Published private(set) var doseCards: [DoseCard] = []

    // MARK: Loaded inputs (kept so the outcome segmented control can re-rank cheaply)

    private var behaviours: [String: Set<String>] = [:]
    /// Per behaviour, the days it was logged NO — the only legitimate control group.
    private var controls: [String: Set<String>] = [:]
    private var outcomeByKey: [String: [String: Double]] = [:]
    private var currentOutcome: Outcome = .recovery

    /// The source id dose rows are parked under (mirrors MoodStore's noop-mood isolation).
    static let doseSource = "noop-journal-dose"

    private let outcomeKeys = ["recovery", "hrv", "sleep_performance", "rhr"]

    // MARK: Load

    func load(repo: Repository) async {
        // Journal → behaviour → days (only "yes" answers count as the behaviour occurring).
        let entries = await repo.journalEntries()
        // Yes days and NO days, kept apart. A day with no journal row for the question lands in
        // neither, so an unanswered day is never counted as a No (BehaviorInsights.effect).
        var byBehaviour: [String: Set<String>] = [:]
        var controlsByBehaviour: [String: Set<String>] = [:]
        for e in entries {
            if e.answeredYes { byBehaviour[e.question, default: []].insert(e.day) }
            else { controlsByBehaviour[e.question, default: []].insert(e.day) }
        }

        // Outcome series: imported metricSeries ∪ the DailyMetric column fallback so an
        // account-free (strap-only) user still gets effects — the exact contract InsightsView uses.
        let mergedDays = repo.days
        var byKey: [String: [String: Double]] = [:]
        for key in outcomeKeys {
            let s = await repo.series(key: key, source: "my-whoop")
            var dict: [String: Double] = [:]
            for row in s { dict[row.day] = row.value }
            for d in mergedDays where dict[d.day] == nil {
                if let v = Self.dailyOutcome(key: key, day: d) { dict[d.day] = v }
            }
            byKey[key] = dict
        }

        // Dose rows per dosed behaviour, under the dedicated dose source, keyed by the
        // behaviour's storage key. A logged "yes" with no dose row reads as dose = 1
        // (back-compatible), so we union the behaviour's logged days at dose 1 with any
        // explicit dose rows (explicit wins).
        var doseByBehaviour: [DosedBehavior: [String: Int]] = [:]
        for behavior in DosedBehavior.allCases {
            let key = Self.doseKey(for: behavior)
            let rows = await repo.series(key: key, source: Self.doseSource)
            var doses: [String: Int] = [:]
            // Back-compat: any logged "yes" day for a matching journal question starts at dose 1.
            for (question, days) in byBehaviour where Self.matches(behavior, question: question) {
                for day in days { doses[day] = max(doses[day] ?? 0, 1) }
            }
            // Explicit dose rows override.
            for row in rows { doses[row.day] = Int(row.value.rounded()) }
            if !doses.isEmpty { doseByBehaviour[behavior] = doses }
        }

        // Build the dose cards from the engine (alcohol first, then caffeine).
        var cards: [DoseCard] = []
        for behavior in DosedBehavior.allCases {
            guard let doses = doseByBehaviour[behavior] else { continue }
            let outcomeName = DoseResponsePriors.defaultOutcome(for: behavior)
            let outcomeKey = Self.outcomeKey(forEngineName: outcomeName)
            let outcomeDays = byKey[outcomeKey] ?? [:]
            guard let response = DoseResponseEngine.estimate(behavior: behavior,
                                                             doseByDay: doses,
                                                             outcomeByDay: outcomeDays) else { continue }
            let latest = outcomeDays.keys.max().flatMap { outcomeDays[$0] }
            cards.append(DoseCard(behavior: behavior, response: response, latestOutcome: latest))
        }

        self.behaviours = byBehaviour
        self.controls = controlsByBehaviour
        self.outcomeByKey = byKey
        self.doseCards = cards
        self.loaded = true
        rankFor(currentOutcome)
    }

    /// Days that carry both a journal answer (yes or no) and a value for `outcome`: the coverage line under
    /// the redesigned hub's title. A count of loaded rows, not a score.
    func answeredOutcomeDayCount(_ outcome: Outcome) -> Int {
        let outcomeDays = outcomeByKey[outcome.key] ?? [:]
        var answered = Set<String>()
        for days in behaviours.values { answered.formUnion(days) }
        for days in controls.values { answered.formUnion(days) }
        return answered.reduce(0) { $0 + (outcomeDays[$1] != nil ? 1 : 0) }
    }

    /// Re-rank the mover feed for a (possibly new) outcome selection — cheap, no DB.
    func rankFor(_ outcome: Outcome) {
        currentOutcome = outcome
        let outcomeDays = outcomeByKey[outcome.key] ?? [:]
        ranked = EffectRanker.rank(behaviors: behaviours,
                                   controls: controls,
                                   outcomeByDay: outcomeDays,
                                   outcome: outcome.outcomeName)
    }

    // MARK: Static shaping helpers

    /// The merged DailyMetric column backing an outcome key (strap-only fallback). sleep_performance
    /// has no daily column, so it stays import-only — never seeded here (matches InsightsView).
    private static func dailyOutcome(key: String, day d: DailyMetric) -> Double? {
        switch key {
        case "recovery": return d.recovery
        case "hrv":      return d.avgHrv
        case "rhr":      return d.restingHr.map(Double.init)
        default:         return nil
        }
    }

    /// The metricSeries key a DoseResponsePriors outcome NAME maps to ("Charge"→recovery, "HRV"→hrv).
    static func outcomeKey(forEngineName name: String) -> String {
        switch name {
        case "Charge": return "recovery"
        case "HRV":    return "hrv"
        case "Rest":   return "sleep_performance"
        case "Resting HR": return "rhr"
        default:       return "recovery"
        }
    }

    /// The dose storage key for a behaviour (its raw enum value — the stable, cross-platform key).
    static func doseKey(for behavior: DosedBehavior) -> String { "dose_\(behavior.rawValue)" }

    /// Whether a journal question is the dosed behaviour (so its yes-days back-fill dose = 1).
    static func matches(_ behavior: DosedBehavior, question: String) -> Bool {
        let q = question.lowercased()
        switch behavior {
        case .alcohol:  return q.contains("alcohol") || q.contains("drink")
        case .caffeine: return q.contains("caffeine") || q.contains("coffee")
        }
    }

    // MARK: Dose card view-data

    struct DoseCard: Identifiable {
        let behavior: DosedBehavior
        let response: DoseResponse
        /// The user's most recent outcome value (for the evening damage forecast anchor).
        let latestOutcome: Double?

        var id: String { behavior.rawValue }
        var outcomeName: String { MetricCatalog.scoreDisplayName(response.outcome) }

        var title: String {
            switch behavior {
            case .alcohol:  return String(localized: "Alcohol")
            case .caffeine: return String(localized: "Caffeine")
            }
        }
        var symbol: String {
            switch behavior {
            case .alcohol:  return "wineglass"
            case .caffeine: return "cup.and.saucer.fill"
            }
        }
        /// The unit shown in copy ("drink" / "later step").
        var unitNoun: String {
            switch behavior {
            case .alcohol:  return String(localized: "drink")
            case .caffeine: return String(localized: "later step")
            }
        }
        /// The plural-ish label used in "N of your X days".
        var unitLabel: String {
            switch behavior {
            case .alcohol:  return String(localized: "drink")
            case .caffeine: return String(localized: "late-caffeine")
            }
        }
        var timingProxy: Bool { behavior == .caffeine }

        /// Outcome units suffix for the forecast tiles.
        var outcomeSuffix: String { outcomeName == "HRV" ? " ms" : "%" }
        /// Clamp ceiling for the projected outcome (Charge/Rest are 0–100; HRV uncapped-ish).
        var outcomeCeiling: Double { outcomeName == "HRV" ? 400 : 100 }

        var forecastOverline: String {
            switch behavior {
            case .alcohol:  return String(localized: "Tonight\u{2019}s forecast")
            case .caffeine: return String(localized: "Timing forecast")
            }
        }

        /// The dose choices the evening stepper offers (0/1/2/3 → 0…maxCurveDose).
        var doseChoices: [Int] { Array(0...DoseResponseEngine.maxCurveDose) }
        func doseChoiceLabel(_ d: Int) -> String {
            switch behavior {
            case .alcohol:  return d >= DoseResponseEngine.maxCurveDose ? "\(d)+" : "\(d)"
            case .caffeine:
                // Timing buckets, not counts.
                switch d {
                case 0: return String(localized: "AM")
                case 1: return String(localized: "Noon")
                case 2: return String(localized: "2pm+")
                default: return String(localized: "Eve")
                }
            }
        }
        /// The whole dose phrase for forecast copy (alcohol counts; caffeine keeps the bare bucket
        /// number). Whole-string keys per variant, never a stitched "+ drinks" suffix.
        func stepLabel(_ d: Int) -> String {
            switch behavior {
            case .alcohol:
                return d >= DoseResponseEngine.maxCurveDose ? String(localized: "\(d)+ drinks")
                                                            : String(localized: "\(d) drinks")
            case .caffeine:
                return "\(d)"
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
@MainActor
private func hubPreviewRepo() -> Repository {
    let repo = Repository(deviceId: "preview")
    repo.loaded = true
    return repo
}

#Preview("Insights Hub") {
    InsightsHubView()
        .environmentObject(hubPreviewRepo())
        .frame(width: 920, height: 980)
        .preferredColorScheme(.dark)
}
#endif
