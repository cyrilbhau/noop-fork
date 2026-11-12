import SwiftUI
import StrandAnalytics
import StrandDesign

// Stage 6 (niggle log), specification §10.3, frames B1 to B9 of `design/round-s6-niggle-timeline/`.
// One entry: its day count, the owner's label with the action as a word and the not-a-diagnosis line,
// the other rules that fit, the next change, the updates newest first, the linked pauses and the
// owner's own professional rule, verbatim. The screen pops when the entry no longer exists.
//
// The screen draws `NiggleLogModel.detail(niggleId:)` and decides nothing.

struct NiggleDetailView: View {
    let niggleId: String
    @StateObject private var model: NiggleLogModel
    @ObservedObject private var flag = NiggleLogSettings.flag
    @Environment(\.dismiss) private var dismiss
    private let followsFlag: Bool
    @State private var sheet: NiggleLogSheet?
    @State private var asksDelete = false
    @State private var loaded = false

    /// `model` and `followsFlag` are for the debug demo; the app reads the standard store.
    init(niggleId: String, model: NiggleLogModel? = nil, asksDelete: Bool = false, followsFlag: Bool = true) {
        self.niggleId = niggleId
        _model = StateObject(wrappedValue: model ?? NiggleLogModel())
        self.followsFlag = followsFlag
        _asksDelete = State(initialValue: asksDelete)
    }

    private var shown: NiggleDetailPresentation? { model.detail(niggleId: niggleId) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let shown { content(shown) }
            }
            .padding(.bottom, NoopTheme.Layout.xl)
        }
        .background(NoopTheme.canvas.ignoresSafeArea())
        .sheet(item: $sheet) { which in NiggleLogSheetHost(sheet: which, model: model) }
        .confirmationDialog(Text(verbatim: NiggleLogPresenter.deleteEntryTitle), isPresented: $asksDelete,
                            titleVisibility: .visible) {
            Button(role: .destructive) {
                Task { await model.delete(niggleId: niggleId) }
            } label: { Text(verbatim: NiggleLogPresenter.deleteTitle) }
            Button(role: .cancel) {} label: { Text("Cancel") }
        } message: {
            Text(verbatim: NiggleLogPresenter.deleteEntryDetail)
        }
        .task {
            await model.load()
            loaded = true
        }
        // Deleted here or elsewhere: the screen pops.
        .onChangeCompat(of: shown == nil) { gone in if gone && loaded { dismiss() } }
        .onChangeCompat(of: flag.isEnabled) { enabled in if !enabled && followsFlag { dismiss() } }
    }

    @ViewBuilder
    private func content(_ shown: NiggleDetailPresentation) -> some View {
        VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
            Text(verbatim: shown.location).noopFont(.screenHeadline).fixedSize(horizontal: false, vertical: true)
            Text(verbatim: shown.sideText).noopFont(.footnote)
            if let dates = shown.datesText { Text(verbatim: dates).noopFont(.footnote) }
        }
        .formKitGutter()
        .padding(.top, NoopTheme.Layout.s)
        .noopEntrance(index: 0)

        if shown.kind != .observation {
            NoopGlassCard {
                VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                    if let count = shown.dayCountText {
                        Text(verbatim: count).noopFont(.rowTitle).monospacedDigit()
                    }
                    if let label = shown.label {
                        Text(verbatim: label).noopFont(.rowTitle).fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach([shown.actionText, shown.ruleNote, shown.disclaimer, shown.triageLine,
                             shown.alsoMatchesText, shown.nextChangeLine].compactMap { $0 }, id: \.self) { line in
                        Text(verbatim: line).noopFont(.footnote).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .formKitGutter()
            .padding(.top, NoopTheme.Layout.l)
            .noopEntrance(index: 1)
        }
        if let note = shown.note {
            NoopGlassCard {
                Text(verbatim: note).noopFont(.body).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .formKitGutter()
            .padding(.top, NoopTheme.Layout.l)
        }
        if !shown.updates.isEmpty {
            ScorecardSectionHeader(title: NiggleLogPresenter.updatesTitle)
            FormKitCard {
                ForEach(Array(shown.updates.enumerated()), id: \.element.seq) { index, update in
                    NiggleTextRow(title: update.trendText,
                                  lines: [update.dateText, update.note, update.isUsed ? "" : NiggleLogPresenter.notUsedTag],
                                  showsDivider: index > 0)
                }
            }
            if let ignored = shown.ignoredUpdatesText { ScorecardFootnote(text: ignored) }
        }
        if !shown.pausedExercises.isEmpty {
            ScorecardSectionHeader(title: NiggleLogPresenter.pausedTitle)
            FormKitCard {
                ForEach(Array(shown.pausedExercises.enumerated()), id: \.element.id) { index, row in
                    NiggleTextRow(title: row.exercise,
                                  lines: [row.reason, row.sinceText] + [row.untilText, row.resumedText].compactMap { $0 },
                                  showsDivider: index > 0)
                }
            }
        }
        if let rule = shown.professionalRule {
            ScorecardSectionHeader(title: NiggleLogPresenter.professionalTitle)
            NoopGlassCard {
                Text(verbatim: rule).noopFont(.body).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .formKitGutter()
        }
        actions(shown.actions)
            .formKitGutter()
            .padding(.top, NoopTheme.Layout.l)
    }

    private func actions(_ actions: [NiggleDetailPresentation.Action]) -> some View {
        VStack(spacing: NoopTheme.Layout.s) {
            ForEach(actions.filter { $0 != .delete }, id: \.self) { action in
                Button { perform(action) } label: { Text(verbatim: title(action)) }
                    .buttonStyle(NoopSecondaryButtonStyle())
            }
            if actions.contains(.delete) {
                Button(role: .destructive) { asksDelete = true } label: {
                    Label { Text(verbatim: NiggleLogPresenter.deleteTitle) } icon: { Image(systemName: "trash") }
                }
                .buttonStyle(ScorecardDangerButton())
            }
        }
    }

    private func title(_ action: NiggleDetailPresentation.Action) -> String {
        switch action {
        case .addUpdate: return NiggleLogPresenter.addUpdateTitle
        case .markResolved: return NiggleLogPresenter.markResolvedTitle
        case .reopen: return NiggleLogPresenter.reopenTitle
        case .edit: return NiggleLogPresenter.editTitle
        case .delete: return NiggleLogPresenter.deleteTitle
        }
    }

    private func perform(_ action: NiggleDetailPresentation.Action) {
        switch action {
        case .addUpdate: sheet = .update(niggleId)
        case .markResolved: sheet = .resolve(niggleId)
        case .reopen: Task { await model.reopen(niggleId: niggleId) }
        case .edit: sheet = .niggle(niggleId)
        case .delete: asksDelete = true
        }
    }
}
