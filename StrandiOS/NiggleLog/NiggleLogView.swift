import SwiftUI
import StrandAnalytics
import StrandDesign

// Stage 6 (niggle log), specification §10.2, frames A1 to A16 of `design/round-s6-niggle-timeline/`.
// Sections top to bottom: the owner's rule for seeing a professional, open complaints, paused
// exercises, observations, resolved. A label is the owner's text and its action is a plain word:
// nothing on this screen is coloured by what a rule says (decision D6).
//
// The screen draws `NiggleLogModel`'s presentation and decides nothing.

/// The niggle log, pushed from the Health tab's row. Leaves the stack when the feature is switched off.
struct NiggleLogView: View {
    @StateObject private var model: NiggleLogModel
    @ObservedObject private var flag = NiggleLogSettings.flag
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    private let isLoading: Bool
    private let followsFlag: Bool
    @State private var sheet: NiggleLogSheet?
    @State private var showsResolved = false
    @State private var showsResumed = false

    /// Every parameter is for the debug demo, which opens the screen in a given state on its own store.
    init(model: NiggleLogModel? = nil, isLoading: Bool = false, opens sheet: NiggleLogSheet? = nil,
         followsFlag: Bool = true) {
        _model = StateObject(wrappedValue: model ?? NiggleLogModel())
        self.isLoading = isLoading
        self.followsFlag = followsFlag
        _sheet = State(initialValue: sheet)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if isLoading {
                    NiggleLogSkeleton()
                } else if case .loaded(let shown) = model.state {
                    content(shown)
                } else {
                    NiggleLogSkeleton()
                }
            }
            .padding(.bottom, NoopTheme.Layout.xl)
        }
        .background(NoopTheme.canvas.ignoresSafeArea())
        .navigationTitle(Text(verbatim: NiggleLogPresenter.title))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { sheet = .niggle(nil) } label: { Image(systemName: "plus") }
                    .accessibilityLabel(Text(verbatim: NiggleLogPresenter.logNiggleTitle))
                    .disabled(!canAdd)
            }
        }
        .sheet(item: $sheet) { which in NiggleLogSheetHost(sheet: which, model: model) }
        .task { if !isLoading { await model.load() } }
        .onChangeCompat(of: flag.isEnabled) { enabled in if !enabled && followsFlag { dismiss() } }
        .onChangeCompat(of: scenePhase) { phase in
            if phase == .active { Task { await model.load() } }
        }
    }

    private var canAdd: Bool {
        if case .loaded(let shown) = model.state { return shown.canAdd }
        return false
    }

    @ViewBuilder
    private func content(_ shown: NiggleLogPresentation) -> some View {
        switch shown.state {
        case .firstUse:
            NiggleFirstUse(shown: shown, onLog: { sheet = .niggle(nil) }, onRules: { sheet = .rules })
        case .entriesNeedAttention, .list:
            professionalSection(shown).noopEntrance(index: 0)
            if let attention = shown.entriesAttentionText {
                Stage6AttentionCard(text: attention, actionTitle: shown.discardTitle) {
                    Task { await model.discardUnreadable() }
                }
                .padding(.top, NoopTheme.Layout.l)
            }
            if !shown.open.isEmpty {
                ScorecardSectionHeader(title: NiggleLogPresenter.openTitle, trailing: "\(shown.open.count)")
                FormKitCard {
                    ForEach(Array(shown.open.enumerated()), id: \.element.id) { index, row in
                        NavigationLink(value: RedesignRoute.niggle(id: row.id)) {
                            NiggleOpenRowView(row: row, showsDivider: index > 0)
                        }
                        .buttonStyle(.noopPress)
                    }
                }
                .noopEntrance(index: 1)
            }
            pausedSection(shown)
            if !shown.observations.isEmpty {
                ScorecardSectionHeader(title: NiggleLogPresenter.observationsTitle)
                FormKitCard {
                    ForEach(Array(shown.observations.enumerated()), id: \.element.id) { index, row in
                        NavigationLink(value: RedesignRoute.niggle(id: row.id)) {
                            NiggleTextRow(title: row.location, lines: [row.sideText, row.note, row.notedText],
                                          showsDivider: index > 0)
                        }
                        .buttonStyle(.noopPress)
                    }
                }
            }
            if !shown.resolved.isEmpty {
                NiggleDisclosure(title: NiggleLogPresenter.resolvedTitle, count: shown.resolved.count,
                                 isOpen: $showsResolved) {
                    ForEach(shown.resolved) { row in
                        NavigationLink(value: RedesignRoute.niggle(id: row.id)) {
                            NiggleTextRow(title: row.location, lines: [row.sideText, row.durationText, row.datesText],
                                          showsDivider: true)
                        }
                        .buttonStyle(.noopPress)
                    }
                }
            }
            VStack(spacing: NoopTheme.Layout.s) {
                Button { sheet = .niggle(nil) } label: { Text(verbatim: NiggleLogPresenter.logNiggleTitle) }
                    .buttonStyle(NoopSecondaryButtonStyle())
                    .disabled(!shown.canAdd)
                if let limit = shown.limitText { ScorecardFootnote(text: limit) }
                Button { sheet = .pause(nil) } label: { Text(verbatim: NiggleLogPresenter.pauseExerciseTitle) }
                    .buttonStyle(NoopSecondaryButtonStyle())
                    .disabled(shown.pausedNeedAttention)
            }
            .formKitGutter()
            .padding(.top, NoopTheme.Layout.l)
        }
    }

    @ViewBuilder
    private func professionalSection(_ shown: NiggleLogPresentation) -> some View {
        ScorecardSectionHeader(title: NiggleLogPresenter.professionalTitle,
                               trailing: shown.professionalRule == nil ? nil : NiggleLogPresenter.editTitle,
                               action: shown.professionalRule == nil ? nil : { sheet = .rules })
        if let attention = shown.rulesAttentionText {
            Stage6AttentionCard(text: attention, actionTitle: shown.discardTitle) {
                Task { await model.discardUnreadable() }
            }
        } else {
            NoopGlassCard {
                VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                    if let rule = shown.professionalRule {
                        Text(verbatim: rule).noopFont(.body).fixedSize(horizontal: false, vertical: true)
                    }
                    if let notice = shown.professionalNotice {
                        Text(verbatim: notice).noopFont(.footnote).fixedSize(horizontal: false, vertical: true)
                    }
                    if let setUp = shown.setUpRulesTitle {
                        Button { sheet = .rules } label: {
                            HStack(spacing: NoopTheme.Layout.xs) { Text(verbatim: setUp); FormKitChevron() }
                        }
                        .buttonStyle(.noopPress)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .formKitGutter()
        }
    }

    @ViewBuilder
    private func pausedSection(_ shown: NiggleLogPresentation) -> some View {
        if !shown.paused.isEmpty || !shown.resumed.isEmpty {
            ScorecardSectionHeader(title: NiggleLogPresenter.pausedTitle)
            FormKitCard {
                ForEach(Array(shown.paused.enumerated()), id: \.element.id) { index, row in
                    Button { sheet = .pause(row.id) } label: {
                        NiggleTextRow(title: row.exercise, lines: [row.reason, row.sinceText] + [row.untilText].compactMap { $0 },
                                      showsDivider: index > 0)
                    }
                    .buttonStyle(.noopPress)
                }
                if !shown.resumed.isEmpty {
                    NiggleDisclosureRow(title: NiggleLogPresenter.resumedTitle, count: shown.resumed.count,
                                        isOpen: $showsResumed, showsDivider: !shown.paused.isEmpty)
                    if showsResumed {
                        ForEach(shown.resumed) { row in
                            Button { sheet = .pause(row.id) } label: {
                                NiggleTextRow(title: row.exercise, lines: [row.reason] + [row.resumedText].compactMap { $0 },
                                              showsDivider: true)
                            }
                            .buttonStyle(.noopPress)
                        }
                    }
                }
            }
        } else if shown.pausedNeedAttention {
            ScorecardSectionHeader(title: NiggleLogPresenter.pausedTitle)
            Stage6AttentionCard(text: nil, actionTitle: shown.discardTitle) {
                Task { await model.discardUnreadable() }
            }
        }
    }
}

/// What the log presents over itself.
enum NiggleLogSheet: Identifiable, Equatable {
    /// Add (nil) or edit a niggle.
    case niggle(String?)
    case rules
    /// Add (nil) or edit a paused exercise.
    case pause(String?)
    /// Add an update to, or mark resolved, the complaint with this id.
    case update(String)
    case resolve(String)

    var id: String {
        switch self {
        case .niggle(let id): return "niggle-\(id ?? "new")"
        case .rules: return "rules"
        case .pause(let id): return "pause-\(id ?? "new")"
        case .update(let id): return "update-\(id)"
        case .resolve(let id): return "resolve-\(id)"
        }
    }
}

/// Opens the right sheet over one model.
struct NiggleLogSheetHost: View {
    let sheet: NiggleLogSheet
    @ObservedObject var model: NiggleLogModel

    var body: some View {
        switch sheet {
        case .niggle(let id):
            NiggleSheet(model: model, mode: id.flatMap { model.entry(id: $0) }.map { .edit($0) } ?? .add)
        case .update(let id):
            if let entry = model.entry(id: id) { NiggleSheet(model: model, mode: .update(entry)) }
        case .resolve(let id):
            if let entry = model.entry(id: id) { NiggleSheet(model: model, mode: .resolve(entry)) }
        case .rules:
            NiggleRulesSheet(model: model)
        case .pause(let id):
            PausedExerciseSheet(model: model, editing: id.flatMap { model.pause(id: $0) })
        }
    }
}

// MARK: - Rows

private struct NiggleOpenRowView: View {
    let row: NiggleOpenRow
    let showsDivider: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsDivider { FormKitDivider() }
            VStack(alignment: .leading, spacing: FormKitLayout.detailGap) {
                // At the largest sizes the day count stacks under the location: nothing truncates a number.
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: NoopTheme.Layout.xs))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: NoopTheme.Layout.m))
                layout {
                    VStack(alignment: .leading, spacing: FormKitLayout.detailGap) {
                        Text(verbatim: row.location).noopFont(.listTitle).fixedSize(horizontal: false, vertical: true)
                        Text(verbatim: row.sideText).noopFont(.footnote)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    FormKitValue(verbatim: row.dayCountText).monospacedDigit().fixedSize()
                }
                if let label = row.label {
                    Text(verbatim: label).noopFont(.rowTitle).fixedSize(horizontal: false, vertical: true)
                }
                ForEach([row.actionText, row.disclaimer, row.triageLine, row.nextChangeLine, row.recurrenceText]
                    .compactMap { $0 }, id: \.self) { line in
                    Text(verbatim: line).noopFont(.footnote).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, FormKitLayout.rowVertical)
            .padding(.horizontal, NoopTheme.Layout.rowHorizontalPadding)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A title and up to a few plain lines, owner text verbatim.
struct NiggleTextRow: View {
    let title: String
    let lines: [String]
    let showsDivider: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsDivider { FormKitDivider() }
            VStack(alignment: .leading, spacing: FormKitLayout.detailGap) {
                Text(verbatim: title).noopFont(.listTitle).fixedSize(horizontal: false, vertical: true)
                ForEach(Array(lines.filter { !$0.isEmpty }.enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line).noopFont(.footnote).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, FormKitLayout.rowVertical)
            .padding(.horizontal, NoopTheme.Layout.rowHorizontalPadding)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A closed-by-default list behind one row ("Resolved", "Resumed").
private struct NiggleDisclosure<Content: View>: View {
    let title: String
    let count: Int
    @Binding var isOpen: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        FormKitCard {
            NiggleDisclosureRow(title: title, count: count, isOpen: $isOpen, showsDivider: false)
            if isOpen { content() }
        }
        .padding(.top, NoopTheme.Layout.l)
    }
}

private struct NiggleDisclosureRow: View {
    let title: String
    let count: Int
    @Binding var isOpen: Bool
    let showsDivider: Bool

    var body: some View {
        Button { isOpen.toggle() } label: {
            VStack(spacing: 0) {
                if showsDivider { FormKitDivider() }
                HStack(spacing: NoopTheme.Layout.m) {
                    Text(verbatim: title).noopFont(.listTitle).frame(maxWidth: .infinity, alignment: .leading)
                    FormKitValue(verbatim: "\(count)").monospacedDigit()
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .noopFont(.footnote)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, FormKitLayout.rowVertical)
                .padding(.horizontal, NoopTheme.Layout.rowHorizontalPadding)
                .frame(minHeight: NoopTheme.Layout.minTouchTarget)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.noopPress)
    }
}

/// A form card whose rows carry the row inset (the sheets' controls).
struct Stage6FormCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        FormKitCard {
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.horizontal, NoopTheme.Layout.rowHorizontalPadding)
        }
    }
}

// MARK: - States

private struct NiggleFirstUse: View {
    let shown: NiggleLogPresentation
    let onLog: () -> Void
    let onRules: () -> Void

    var body: some View {
        NoopGlassCard {
            VStack(spacing: NoopTheme.Layout.m) {
                Text(verbatim: NiggleLogPresenter.firstUseText)
                    .noopFont(.footnote)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let log = shown.logTitle {
                    Button(action: onLog) { Text(verbatim: log) }.buttonStyle(NoopPrimaryButtonStyle())
                }
                if let rules = shown.setUpRulesTitle {
                    Button(action: onRules) { Text(verbatim: rules) }.buttonStyle(NoopSecondaryButtonStyle())
                }
            }
            .frame(maxWidth: .infinity)
        }
        .formKitGutter()
        .padding(.top, NoopTheme.Layout.sectionTop)
    }
}

/// "… could not be read. Nothing has been changed." with the discard action.
struct Stage6AttentionCard: View {
    let text: String?
    let actionTitle: String?
    let action: () -> Void
    @State private var asks = false

    var body: some View {
        NoopGlassCard {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
                if let text {
                    Text(verbatim: text).noopFont(.rowTitle).fixedSize(horizontal: false, vertical: true)
                }
                if let actionTitle {
                    Button { asks = true } label: { Text(verbatim: actionTitle) }
                        .buttonStyle(NoopSecondaryButtonStyle())
                        .confirmationDialog(Text(verbatim: actionTitle), isPresented: $asks, titleVisibility: .visible) {
                            Button(role: .destructive, action: action) { Text(verbatim: actionTitle) }
                            Button(role: .cancel) {} label: { Text("Cancel") }
                        }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .formKitGutter()
    }
}

private struct NiggleLogSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: NoopTheme.Layout.l) {
            ForEach(0..<4, id: \.self) { _ in
                ScorecardSkeletonLines(styles: [.sectionTitle, .listTitle, .footnote, .footnote])
                    .noopSkeleton(true, cornerRadius: NoopTheme.Layout.tileRadius)
                    .formKitGutter()
            }
        }
        .padding(.top, NoopTheme.Layout.l)
        .accessibilityHidden(true)
    }
}

// MARK: - Health row

/// The Health tab's row (§10.1): "Niggle log" and the open count, or nothing. Mounted only while
/// the feature is on.
struct NiggleLogHealthRowLabel: View {
    let showsDivider: Bool
    let refreshSequence: Int
    @State private var row: NiggleLogHealthRow?

    var body: some View {
        NoopListRow(LocalizedStringKey(row?.title ?? NiggleLogPresenter.title), systemImage: "list.bullet.clipboard",
                    color: NoopTheme.textPrimary, value: row?.detail, showsDivider: showsDivider)
            .task(id: refreshSequence) { row = NiggleLogModel.liveHealthRow() }
    }
}
