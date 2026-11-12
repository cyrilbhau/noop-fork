import SwiftUI
import StrandAnalytics
import StrandDesign

// Stage 6 (checkpoint timeline), specification §10.8, frames G1 to G16 of
// `design/round-s6-niggle-timeline/`. One list, oldest first, opened at the today marker: phases,
// scans, checkpoints, diet breaks and deloads, and the scorecard's estimate. The list itself is the
// time axis: no horizontal rule, band or bar. A break or deload row shows its kind and dates only;
// a private event has no row.
//
// The screen draws `CheckpointTimelineModel`'s presentation, one row per built item in order, and
// decides nothing but which heading each row sits under, from its position.

/// The timeline, pushed from the Health tab's row and the scorecard's link. Leaves the stack when the
/// feature is switched off.
struct CheckpointTimelineView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @ObservedObject private var flag = CheckpointTimelineSettings.flag
    @Environment(\.dismiss) private var dismiss
    private let injected: CheckpointTimelineModel?
    private let isLoading: Bool
    private let opens: CheckpointTimelineSheet?

    /// Every parameter is for the debug demo, which opens the screen in a given state.
    init(model: CheckpointTimelineModel? = nil, isLoading: Bool = false, opens: CheckpointTimelineSheet? = nil) {
        injected = model
        self.isLoading = isLoading
        self.opens = opens
    }

    var body: some View {
        CheckpointTimelineScreen(model: injected ?? CheckpointTimelineModel.live(repository: repo, profile: profile),
                                 isLoading: isLoading, opens: opens, refreshSequence: repo.refreshSeq)
            .onChangeCompat(of: flag.isEnabled) { on in if !on && injected == nil { dismiss() } }
    }
}

extension CheckpointTimelineModel {
    /// The app's timeline: the standard stores, the shared scorecard model and the two live adapters.
    static func live(repository: Repository, profile: ProfileStore) -> CheckpointTimelineModel {
        CheckpointTimelineModel(
            settings: CheckpointTimelineSettings(), scorecardSettings: CutScorecardSettings(),
            scorecard: CutScorecardModel.live(repository: repository, profile: profile),
            scans: .live(repository: repository), events: .live(),
            unitSystem: { UnitSystem(rawValue: UserDefaults.standard.string(forKey: UnitPrefs.systemKey) ?? "") ?? .metric })
    }
}

/// What the timeline presents over itself.
enum CheckpointTimelineSheet: Identifiable, Equatable {
    /// Add (nil) or edit a checkpoint.
    case checkpoint(String?)
    case phase

    var id: String {
        switch self {
        case .checkpoint(let id): return "checkpoint-\(id ?? "new")"
        case .phase: return "phase"
        }
    }
}

private struct CheckpointTimelineScreen: View {
    @StateObject private var model: CheckpointTimelineModel
    private let isLoading: Bool
    private let refreshSequence: Int
    @State private var sheet: CheckpointTimelineSheet?

    init(model: CheckpointTimelineModel, isLoading: Bool, opens: CheckpointTimelineSheet?, refreshSequence: Int) {
        _model = StateObject(wrappedValue: model)
        self.isLoading = isLoading
        self.refreshSequence = refreshSequence
        _sheet = State(initialValue: opens)
    }

    private var shown: CheckpointTimelinePresentation? {
        if !isLoading, case .loaded(let presentation) = model.state { return presentation }
        return nil
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let shown { content(shown) } else { skeleton }
                }
                .padding(.bottom, NoopTheme.Layout.xl)
            }
            .onChangeCompat(of: shown?.todayRowIndex) { index in
                if let index { proxy.scrollTo(index, anchor: .center) }
            }
        }
        .background(NoopTheme.canvas.ignoresSafeArea())
        .navigationTitle(Text(verbatim: CheckpointTimelinePresenter.title))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { sheet = .checkpoint(nil) } label: { Image(systemName: "plus") }
                    .accessibilityLabel(Text(verbatim: shown?.addTitle ?? ""))
                    .disabled(!(shown?.canAdd ?? false))
            }
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .checkpoint(let id):
                CheckpointSheet(model: model, editing: id.flatMap { model.checkpoint(id: $0) },
                                onEditPhase: { sheet = .phase })
            case .phase:
                ScorecardContextReader { context in
                    ScorecardPhaseSheet(context: context) { Task { await model.load() } }
                }
            }
        }
        .task(id: refreshSequence) { if !isLoading { await model.load() } }
    }

    @ViewBuilder
    private func content(_ shown: CheckpointTimelinePresentation) -> some View {
        if let attention = shown.attentionText {
            Stage6AttentionCard(text: attention, actionTitle: shown.discardTitle) {
                Task { await model.discardUnreadableCheckpoints() }
            }
            .padding(.top, NoopTheme.Layout.l)
        }
        if let empty = shown.emptyText {
            NoopGlassCard {
                VStack(spacing: NoopTheme.Layout.m) {
                    Text(verbatim: empty).noopFont(.rowTitle).multilineTextAlignment(.center)
                    Button { sheet = .checkpoint(nil) } label: { Text(verbatim: shown.addTitle) }
                        .buttonStyle(NoopPrimaryButtonStyle())
                        .disabled(!shown.canAdd)
                    if let setUp = shown.setUpPhaseTitle {
                        Button { sheet = .phase } label: { Text(verbatim: setUp) }
                            .buttonStyle(NoopSecondaryButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .formKitGutter()
            .padding(.top, NoopTheme.Layout.sectionTop)
        } else {
            let groups = Self.groups(shown)
            if !groups.earlier.isEmpty {
                ScorecardSectionHeader(title: shown.earlierTitle)
                rows(groups.earlier, shown)
            }
            ScorecardSectionHeader(title: shown.todayTitle,
                                   trailing: shown.todayRowIndex.map { shown.rows[$0].dateText })
            rows(groups.now, shown)
            if !groups.ahead.isEmpty {
                ScorecardSectionHeader(title: shown.aheadTitle)
                rows(groups.ahead, shown)
            }
        }
        ForEach(Array(shown.footnotes.enumerated()), id: \.offset) { _, note in
            VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
                ScorecardFootnote(text: note.text)
                if let link = note.linkTitle {
                    Button { footnoteTapped(note) } label: {
                        HStack(spacing: NoopTheme.Layout.xs) { Text(verbatim: link); FormKitChevron() }
                    }
                    .buttonStyle(.noopPress)
                    .formKitGutter()
                }
            }
        }
        if shown.emptyText == nil {
            Button { sheet = .checkpoint(nil) } label: { Text(verbatim: shown.addTitle) }
                .buttonStyle(NoopSecondaryButtonStyle())
                .disabled(!shown.canAdd)
                .formKitGutter()
                .padding(.top, NoopTheme.Layout.l)
        }
        if let limit = shown.limitText { ScorecardFootnote(text: limit) }
    }

    /// The rows under each heading: items that are past and anything before the last of them under
    /// "Earlier"; the current items after it and the today marker under "Today"; the rest "Ahead".
    private static func groups(_ shown: CheckpointTimelinePresentation)
        -> (earlier: [Int], now: [Int], ahead: [Int]) {
        guard let today = shown.todayRowIndex else { return (Array(shown.rows.indices), [], []) }
        let before = Array(0..<today)
        let lastPast = before.last { shown.rows[$0].position == .past }
        let earlier = lastPast.map { Array(0...$0) } ?? []
        let now = Array((earlier.count)...today)
        return (earlier, now, Array((today + 1)..<shown.rows.count))
    }

    private func rows(_ indices: [Int], _ shown: CheckpointTimelinePresentation) -> some View {
        FormKitCard {
            ForEach(Array(indices.enumerated()), id: \.element) { position, index in
                rowButton(shown.rows[index], showsDivider: position > 0)
                    .id(index)
                    .noopEntrance(index: min(position, 6))
            }
        }
    }

    @ViewBuilder
    private func rowButton(_ row: TimelineRow, showsDivider: Bool) -> some View {
        let label = TimelineRowView(row: row, showsDivider: showsDivider,
                                    onWeight: row.weightDestination.map { _ in { sheet = .phase } })
        switch row.destination {
        case .phaseSheet: Button { sheet = .phase } label: { label }.buttonStyle(.noopPress)
        case .checkpointSheet(let id): Button { sheet = .checkpoint(id) } label: { label }.buttonStyle(.noopPress)
        case .bodyRecord: NavigationLink(value: RedesignRoute.bodyRecord) { label }.buttonStyle(.noopPress)
        case .personalEvents: NavigationLink(value: RedesignRoute.personalEvents) { label }.buttonStyle(.noopPress)
        case .scorecard: NavigationLink(value: RedesignRoute.scorecard) { label }.buttonStyle(.noopPress)
        case .none: label
        }
    }

    private func footnoteTapped(_ note: TimelineFootnote) {
        switch note.link {
        case .checkpointSheet(let id): sheet = .checkpoint(id)
        case .phaseSheet: sheet = .phase
        default: break
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: NoopTheme.Layout.l) {
            ForEach(0..<3, id: \.self) { _ in
                ScorecardSkeletonLines(styles: [.sectionTitle, .listTitle, .footnote, .listTitle, .footnote])
            }
        }
        .noopSkeleton(true, cornerRadius: NoopTheme.Layout.tileRadius)
        .formKitGutter()
        .padding(.top, NoopTheme.Layout.l)
        .accessibilityHidden(true)
    }
}

/// One timeline row: a quiet neutral mark, the title and details, and the date with its tags. At the
/// largest sizes the date sits above the title so nothing truncates it.
private struct TimelineRowView: View {
    let row: TimelineRow
    let showsDivider: Bool
    let onWeight: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var mark: String {
        switch row.kind {
        case .phaseStart: return "diamond.fill"
        case .scan: return "square"
        case .checkpoint: return row.isMarkedDone ? "checkmark.circle.fill" : "circle"
        case .dietBreak, .deload: return row.position == .current ? "capsule.portrait.fill" : "capsule.portrait"
        case .today: return "smallcircle.filled.circle"
        case .projection: return "circle.dashed"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsDivider { FormKitDivider() }
            HStack(alignment: .firstTextBaseline, spacing: NoopTheme.Layout.m) {
                Image(systemName: mark)
                    .noopFont(.footnote, color: false)
                    .foregroundStyle(NoopTheme.textSecondary)
                    .accessibilityHidden(true)
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: NoopTheme.Layout.xs))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: NoopTheme.Layout.m))
                layout {
                    if dynamicTypeSize.isAccessibilitySize { dates }
                    VStack(alignment: .leading, spacing: FormKitLayout.detailGap) {
                        Text(verbatim: row.title).noopFont(.listTitle).fixedSize(horizontal: false, vertical: true)
                        ForEach(Array(row.details.enumerated()), id: \.offset) { index, detail in
                            if index == 0, let onWeight, row.weightDestination != nil {
                                Button(action: onWeight) { Text(verbatim: detail).noopFont(.footnote) }
                                    .buttonStyle(.noopPress)
                            } else {
                                Text(verbatim: detail).noopFont(.footnote).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !dynamicTypeSize.isAccessibilitySize { dates }
                }
            }
            .padding(.vertical, FormKitLayout.rowVertical)
            .padding(.horizontal, NoopTheme.Layout.rowHorizontalPadding)
            .frame(minHeight: NoopTheme.Layout.minTouchTarget)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var dates: some View {
        if !row.dateText.isEmpty || !row.tags.isEmpty {
            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: NoopTheme.Layout.xs) {
                if !row.dateText.isEmpty {
                    FormKitValue(verbatim: row.dateText).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                }
                ForEach(row.tags, id: \.self) { tag in
                    FormKitBadge(verbatim: tag, tint: NoopTheme.textSecondary)
                }
            }
        }
    }
}

// MARK: - Health row

/// The Health tab's row (§10.1): "Timeline" and the date of the next upcoming item, or nothing.
/// Mounted only while the feature is on.
struct CheckpointTimelineHealthRowLabel: View {
    let showsDivider: Bool
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @State private var row: CheckpointTimelineHealthRow?

    var body: some View {
        NoopListRow(LocalizedStringKey(row?.title ?? CheckpointTimelinePresenter.title), systemImage: "calendar.day.timeline.left",
                    color: NoopTheme.textPrimary, value: row?.detail, showsDivider: showsDivider)
            .task(id: repo.refreshSeq) {
                let model = CheckpointTimelineModel.live(repository: repo, profile: profile)
                await model.load()
                row = CheckpointTimelinePresenter.healthRow(enabled: model.settings.isEnabled, result: model.result,
                                                            locale: AppLanguage.activeLocale)
            }
    }
}
