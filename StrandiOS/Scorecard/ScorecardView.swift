import SwiftUI
import StrandDesign

// PLACEHOLDER (stage 1, work package 1-7, screens). This file exists only so that
// `RedesignRoute.scorecard` has a destination and the app compiles. The scorecard screen of
// specification §10.2 (frames B1 to B27) replaces it; everything it will draw is already resolved by
// `CutScorecardModel` and worded by `CutScorecardPresenter`.

/// The scorecard screen. Placeholder: the verdict title and the card's caption only.
struct ScorecardView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore

    var body: some View {
        ScorecardPlaceholderContent(model: CutScorecardModel.live(repository: repo, profile: profile))
    }
}

private struct ScorecardPlaceholderContent: View {
    @ObservedObject var model: CutScorecardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.cardGap) {
                if case .loaded(let shown) = model.state {
                    NoopGlassCard {
                        VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                            Text(verbatim: shown.verdict.header).noopFont(.footnote)
                            Text(verbatim: shown.verdict.title).noopFont(.sectionTitle)
                            ForEach(shown.verdict.lines, id: \.self) { line in
                                Text(verbatim: line).noopFont(.bodySmall)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    NoopGlassCard { Color.clear.frame(height: NoopTheme.Layout.yourCardMinHeight) }
                        .noopSkeleton(true)
                }
            }
            .padding(.horizontal, NoopTheme.Layout.gutter)
        }
        .navigationTitle(Text(verbatim: CutScorecardPresenter.cardTitle))
        .task { await model.load() }
    }
}
