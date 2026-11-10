import SwiftUI
import StrandAnalytics
import StrandDesign

// Stage 1 (weigh-in and scorecard), specification §10.4, frames D1 to D5 of
// `design/round6-scorecard/`. Newest first; the weight and the waist of one weigh-in on one row; a
// dot on the reading that represents its week. A Lab Book row swipes to Edit and Delete; an Apple
// Health value is read-only. Delete asks once.
//
// The list draws `WeighInHistoryModel` and decides nothing: which rows exist, what each says and
// whether it can be edited are the presenter's.

/// The weigh-in history, pushed from the scorecard.
struct WeighInHistoryView: View {
    var body: some View {
        ScorecardContextReader { WeighInHistoryScreen(context: $0) }
    }
}

struct WeighInHistoryScreen: View {
    private let context: ScorecardContext
    @StateObject private var model: WeighInHistoryModel
    @State private var editing: WeighInHistoryRow?
    @State private var logging = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var weightColumn = ScorecardLayout.historyWeightColumn
    @ScaledMetric(relativeTo: .subheadline) private var waistColumn = ScorecardLayout.historyWaistColumn
    @ScaledMetric(relativeTo: .subheadline) private var dot = NoopTheme.Layout.s

    private let loadsOnAppear: Bool

    /// `model` and `loadsOnAppear` are for the debug demo, which shows the list in a given state.
    init(context: ScorecardContext, model: WeighInHistoryModel? = nil, loadsOnAppear: Bool = true) {
        self.context = context
        self.loadsOnAppear = loadsOnAppear
        _model = StateObject(wrappedValue: model ?? context.historyModel())
    }

    private var stacks: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        content
            .background(NoopTheme.canvas.ignoresSafeArea())
            .navigationTitle(Text(verbatim: CutScorecardPresenter.historyTitle))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { logging = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel(Text(verbatim: CutScorecardPresenter.logWeighInTitle))
                }
            }
            .sheet(isPresented: $logging) { WeighInSheetScreen(context: context) }
            .sheet(item: $editing) { row in WeighInSheetScreen(context: context, editing: row) }
            .sheet(item: pendingDelete) { _ in
                if let question = model.deleteConfirmation {
                    WeighInDeleteSheet(question: question,
                                       onDelete: { Task { await model.confirmDelete() } },
                                       onCancel: { model.cancelDelete() })
                }
            }
            .task { if loadsOnAppear { await model.load() } }
    }

    /// The row whose deletion is being confirmed. Dismissing the question cancels it.
    private var pendingDelete: Binding<WeighInHistoryRow?> {
        Binding(get: { model.pendingDelete }, set: { if $0 == nil { model.cancelDelete() } })
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ScrollView { loading }
        case .loaded(let history):
            if let empty = history.emptyText {
                ScrollView { emptyCard(empty) }
            } else {
                list(history)
            }
        }
    }

    // MARK: Rows

    private func list(_ history: WeighInHistory) -> some View {
        List {
            Section {
                ForEach(history.rows) { row in
                    rowView(row, history: history)
                        .listRowBackground(NoopTheme.card)
                        .listRowSeparatorTint(NoopTheme.separator)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if row.canDelete {
                                Button { model.requestDelete(row) } label: {
                                    Label { Text(verbatim: CutScorecardPresenter.deleteTitle) }
                                        icon: { Image(systemName: "trash") }
                                }
                                .tint(NoopTheme.recoveryLow)
                            }
                            if row.canEdit {
                                Button { editing = row } label: {
                                    Label { Text(verbatim: CutScorecardPresenter.editTitle) }
                                        icon: { Image(systemName: "pencil") }
                                }
                                .tint(NoopTheme.textTertiary)
                            }
                        }
                }
            } header: {
                if !stacks { columnTitles }
            } footer: {
                if let note = CutScorecardPresenter.historyFootnote(history) {
                    Text(verbatim: note)
                        .noopFont(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, NoopTheme.Layout.s)
                }
            }
            .textCase(nil)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var columnTitles: some View {
        HStack(spacing: NoopTheme.Layout.s) {
            Spacer(minLength: 0)
            Text(verbatim: CutScorecardPresenter.weightTitle)
                .noopFont(.caption)
                .frame(width: weightColumn, alignment: .trailing)
            Text(verbatim: CutScorecardPresenter.waistTitle)
                .noopFont(.caption)
                .frame(width: waistColumn, alignment: .trailing)
        }
        .accessibilityHidden(true)
    }

    private func rowView(_ row: WeighInHistoryRow, history: WeighInHistory) -> some View {
        let valueColor = row.representsWeek ? NoopTheme.textPrimary : NoopTheme.textSecondary
        let when = VStack(alignment: .leading, spacing: FormKitLayout.detailGap) {
            HStack(spacing: NoopTheme.Layout.s) {
                if row.representsWeek {
                    Circle().fill(NoopTheme.textPrimary)
                        .frame(width: dot, height: dot)
                        .accessibilityHidden(true)
                }
                Text(verbatim: row.dateText)
                    .noopFont(.rowTitle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(verbatim: row.caption)
                .noopFont(.caption, color: false)
                .foregroundStyle(NoopTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        let weight = reading(row.weightText, unit: history.weightUnit, missing: history.notMeasuredText,
                             color: valueColor)
        let waist = reading(row.waistText, unit: history.waistUnit, missing: history.notMeasuredText,
                            color: valueColor)
        return Group {
            if stacks {
                VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                    when
                    labelled(CutScorecardPresenter.weightTitle, weight)
                    labelled(CutScorecardPresenter.waistTitle, waist)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: NoopTheme.Layout.s) {
                    when.frame(maxWidth: .infinity, alignment: .leading)
                    weight.frame(width: weightColumn, alignment: .trailing)
                    waist.frame(width: waistColumn, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, NoopTheme.Layout.xs)
        .accessibilityElement(children: .combine)
    }

    /// One reading with its unit, or the words for a reading that was not taken. Never a zero.
    @ViewBuilder
    private func reading(_ value: String?, unit: String, missing: String, color: Color) -> some View {
        if let value {
            HStack(alignment: .firstTextBaseline, spacing: FormKitLayout.detailGap) {
                Text(verbatim: value)
                    .noopFont(.navTitle, color: false)
                    .monospacedDigit()
                    .foregroundStyle(color)
                Text(verbatim: unit).noopFont(.caption, color: false)
                    .foregroundStyle(NoopTheme.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(verbatim: missing)
                .noopFont(.caption)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func labelled(_ label: String, _ value: some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: NoopTheme.Layout.s) {
            Text(verbatim: label).noopFont(.footnote)
            value
        }
    }

    // MARK: Empty and loading

    private func emptyCard(_ text: String) -> some View {
        NoopGlassCard {
            VStack(spacing: NoopTheme.Layout.m) {
                Image(systemName: DashboardCard.scorecard.icon)
                    .noopFont(.screenHeadline, color: false)
                    .foregroundStyle(NoopTheme.textSecondary)
                    .accessibilityHidden(true)
                Text(verbatim: text)
                    .noopFont(.sectionTitle)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button { logging = true } label: {
                    Text(verbatim: CutScorecardPresenter.logWeighInTitle)
                }
                .buttonStyle(NoopPrimaryButton())
                .padding(.top, NoopTheme.Layout.s)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, NoopTheme.Layout.s)
        }
        .padding(.horizontal, NoopTheme.Layout.gutter)
        .padding(.top, NoopTheme.Layout.sectionTop)
    }

    private var loading: some View {
        VStack(spacing: NoopTheme.Layout.cardGap) {
            ForEach(0..<5, id: \.self) { _ in
                NoopGlassCard { ScorecardSkeletonLines(styles: [.rowTitle, .caption]) }
                    .noopSkeleton(true)
            }
        }
        .padding(.horizontal, NoopTheme.Layout.gutter)
        .padding(.top, NoopTheme.Layout.sectionTop)
        .accessibilityHidden(true)
    }
}

// MARK: - Delete

/// The one question before a weigh-in is deleted (frame D3): what goes, then Delete and Cancel.
private struct WeighInDeleteSheet: View {
    let question: WeighInDeleteConfirmation
    let onDelete: () -> Void
    let onCancel: () -> Void
    @State private var height: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                Text(verbatim: question.title)
                    .noopFont(.sectionTitle)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: question.detail)
                    .noopFont(.bodySmall, color: false)
                    .foregroundStyle(NoopTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onDelete) {
                    HStack(spacing: NoopTheme.Layout.s) {
                        Image(systemName: "trash").accessibilityHidden(true)
                        Text(verbatim: question.confirmTitle)
                    }
                }
                .buttonStyle(ScorecardDangerButton())
                .padding(.top, NoopTheme.Layout.m)
                Button(action: onCancel) { Text(verbatim: question.cancelTitle) }
                    .buttonStyle(NoopSecondaryButton())
            }
            .padding(.horizontal, NoopTheme.Layout.gutter)
            .padding(.top, NoopTheme.Layout.xl)
            .padding(.bottom, NoopTheme.Layout.l)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: WeighInDeleteSheetHeight.self, value: geometry.size.height)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .onPreferenceChange(WeighInDeleteSheetHeight.self) { height = $0 }
        .background(NoopTheme.sheet.ignoresSafeArea())
        .presentationDetents(height > 0 ? [.height(height)] : [.medium])
        .presentationDragIndicator(.visible)
    }
}

private struct WeighInDeleteSheetHeight: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
