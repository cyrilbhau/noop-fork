import SwiftUI
import StrandAnalytics
import StrandDesign

// Stage 6 ("Recovery context"), specification §8.2 and §10.7, frames F1 to F12 of
// `design/round-s6-niggle-timeline/`. The framing sentence, then one card per metric: the weekly
// curve in the neutral colour with no rule, band or event mark, and the presenter's lines (latest
// week average with its night count, first week shown, the signed change, the typical range as
// text). No current value, no adjective, no colour state.
//
// Reachable from the scorecard only, so the screen leaves the stack when either its own flag or the
// scorecard's goes off. It draws `CutStressModel`'s presentation and decides nothing.

struct CutStressView: View {
    @EnvironmentObject private var repo: Repository
    @ObservedObject private var flag = CutStressModel.flag
    @ObservedObject private var scorecardFlag = CutScorecardFlag.shared
    @Environment(\.dismiss) private var dismiss
    private let injected: CutStressModel?
    private let isLoading: Bool

    /// `model` and `isLoading` are for the debug demo; the app builds the model over the repository.
    init(model: CutStressModel? = nil, isLoading: Bool = false) {
        injected = model
        self.isLoading = isLoading
    }

    var body: some View {
        CutStressScreen(model: injected ?? CutStressModel(repository: repo), isLoading: isLoading,
                        refreshSequence: repo.refreshSeq)
            .onChangeCompat(of: flag.isEnabled && scorecardFlag.isEnabled) { on in
                if !on && injected == nil { dismiss() }
            }
            .onAppear { if injected == nil && !(flag.isEnabled && scorecardFlag.isEnabled) { dismiss() } }
    }
}

private struct CutStressScreen: View {
    @StateObject private var model: CutStressModel
    private let isLoading: Bool
    private let refreshSequence: Int

    init(model: CutStressModel, isLoading: Bool, refreshSequence: Int) {
        _model = StateObject(wrappedValue: model)
        self.isLoading = isLoading
        self.refreshSequence = refreshSequence
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !isLoading, case .loaded(let shown) = model.state {
                    content(shown)
                } else {
                    skeleton
                }
            }
            .padding(.bottom, NoopTheme.Layout.xl)
        }
        .background(NoopTheme.canvas.ignoresSafeArea())
        .navigationTitle(Text(verbatim: CutStressPresenter.title))
        .task(id: refreshSequence) { if !isLoading { await model.load() } }
    }

    @ViewBuilder
    private func content(_ shown: CutStressPresentation) -> some View {
        VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
            Text(verbatim: shown.periodText).noopFont(.footnote)
            Text(verbatim: shown.framing).noopFont(.bodySmall).fixedSize(horizontal: false, vertical: true)
        }
        .formKitGutter()
        .padding(.top, NoopTheme.Layout.s)
        .noopEntrance(index: 0)
        card(shown.restingHr).noopEntrance(index: 1)
        card(shown.hrv).noopEntrance(index: 2)
    }

    private func card(_ card: CutStressCard) -> some View {
        NoopGlassCard {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                Text(verbatim: card.title).noopFont(.rowTitle)
                if card.points.contains(where: { $0 != nil }) {
                    ScorecardWeekChart(points: card.points, firstLabel: card.firstLabel, lastLabel: card.lastLabel,
                                       color: NoopTheme.textPrimary, axisMarks: card.axisMarks)
                }
                ForEach(Array(card.lines.enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line).noopFont(.footnote).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .formKitGutter()
        .padding(.top, NoopTheme.Layout.l)
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: NoopTheme.Layout.l) {
            ScorecardSkeletonLines(styles: [.footnote, .bodySmall, .bodySmall])
            ScorecardSkeletonLines(styles: [.rowTitle, .largeTitle, .footnote, .footnote])
            ScorecardSkeletonLines(styles: [.rowTitle, .largeTitle, .footnote, .footnote])
        }
        .noopSkeleton(true, cornerRadius: NoopTheme.Layout.tileRadius)
        .formKitGutter()
        .padding(.top, NoopTheme.Layout.l)
        .accessibilityHidden(true)
    }
}
