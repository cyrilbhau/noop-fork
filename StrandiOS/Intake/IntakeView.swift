import SwiftUI
import Charts
import StrandAnalytics
import StrandDesign
import WhoopStore

// Stage 3 (protein and intake), specification §10.2 and design round `design/round-s3-intake/`
// frames B1 to B26. Top to bottom: protein ring and numbers, calories eaten, supplements, the last
// 28 days of protein, source and freshness, then the entries (Path B) or the Health note (Path A).
//
// The screen draws an `IntakeScreenModel` and decides nothing: which sections exist, every word and
// every number are `IntakePresenter`'s. No Kotlin twin: iPhone-only (stage 1 ruling R43).

/// The intake screen, pushed from the protein card, the Health tab's row and the scorecard's protein
/// row. It exists only while `noop.intakeEnabled` is on: when the flag goes off the screen leaves
/// the stack.
struct IntakeView: View {
    @EnvironmentObject private var repo: Repository
    @ObservedObject private var flag = IntakeSettings.flag
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if flag.isEnabled {
                IntakeLiveScreen(provider: .live(repository: repo))
            } else {
                NoopTheme.canvas.ignoresSafeArea()
            }
        }
        .onChangeCompat(of: flag.isEnabled) { if !$0 { dismiss() } }
        .onAppear { if !flag.isEnabled { dismiss() } }
    }
}

/// Everything one render of the screen draws, from one clock.
struct IntakeScreenSnapshot: Equatable {
    var model: IntakeScreenModel
    var supplements: [IntakeSupplementRow]
    var day: String
    /// The day the entries card lists: today or one of the seven days before it.
    var entriesDay: String
    var quickAddDays: [String]
    var presets: [IntakeSettings.Preset]
}

/// Loads the live screen: rebanks today and yesterday (§9.3), refreshes the provider, gathers one
/// input and asks the presenter for the model.
@MainActor
final class IntakeScreenState: ObservableObject {
    @Published private(set) var snapshot: IntakeScreenSnapshot?
    /// The day picked in the entries card; nil is today.
    private var shownDay: String?
    let provider: IntakeProvider
    let settings: IntakeSettings
    let quickAdd: IntakeQuickAddStore
    let tick: IntakeSupplementTick

    init(provider: IntakeProvider) {
        self.provider = provider
        self.settings = provider.settings
        self.quickAdd = IntakeQuickAddStore(repository: provider.repository, settings: provider.settings)
        self.tick = IntakeSupplementTick(repository: provider.repository, settings: provider.settings)
    }

    /// The calendar day the screen shows: today under the zone log.
    private var clock: IntakeClock { IntakeClock.current(settings: settings) }

    func load(rebank: Bool) async {
        let clock = clock
        let quickAddDays = IntakePresenter.quickAddDays(today: clock.today)
        let entriesDay = IntakePresenter.entriesDay(requested: shownDay, today: clock.today)
        if rebank, settings.source == .quickAdd {
            for day in Array(quickAddDays.prefix(2)) + (quickAddDays.prefix(2).contains(entriesDay) ? [] : [entriesDay]) {
                try? await quickAdd.rebank(day: day)
            }
        }
        await provider.refresh()
        let input = await IntakePresenterInput.gather(provider: provider, settings: settings, day: clock.today,
                                                      quickAdd: quickAdd, entriesDay: entriesDay)
        let states = await tick.states(day: clock.today)
        let model = IntakePresenter.screen(input, clock: clock, timeZone: .current, locale: AppClock.formattingLocale)
        let rows = IntakePresenter.supplementRows(questions: settings.supplementQuestions, states: states,
                                                  displayName: IntakePresenter.supplementName(question:))
        snapshot = IntakeScreenSnapshot(model: model, supplements: rows, day: clock.today, entriesDay: entriesDay,
                                        quickAddDays: quickAddDays,
                                        presets: settings.quickAddPresets)
        IntakeWidgetPublisher.publish(provider: provider, clock: clock)
    }

    func setTick(_ ticked: Bool, question: String) async {
        guard let day = snapshot?.day else { return }
        await tick.set(ticked, question: question, day: day)
        await load(rebank: false)
    }

    func showDay(_ day: String) async {
        shownDay = day
        await load(rebank: false)
    }

    func chooseSource(_ source: IntakeSourceSetting) async {
        settings.source = source
        await load(rebank: false)
    }
}

/// The screen over the live provider.
private struct IntakeLiveScreen: View {
    @EnvironmentObject private var repo: Repository
    @StateObject private var state: IntakeScreenState
    @State private var editing: IntakeQuickAddSheet.Mode?
    @State private var showsSettings = false

    init(provider: IntakeProvider) {
        _state = StateObject(wrappedValue: IntakeScreenState(provider: provider))
    }

    var body: some View {
        IntakeScreenContent(
            snapshot: state.snapshot,
            actions: IntakeScreenActions(
                choose: { source in Task { await state.chooseSource(source) } },
                tick: { ticked, question in Task { await state.setTick(ticked, question: question) } },
                add: { editing = .add },
                edit: { editing = .edit($0) },
                replaceRestored: { editing = .restored },
                openSettings: { showsSettings = true },
                readAgain: { Task { await state.load(rebank: false) } },
                showDay: { day in Task { await state.showDay(day) } }))
            .task(id: repo.refreshSeq) { await state.load(rebank: true) }
            // A screen left open past midnight rolls its "Today" over.
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                Task { await state.load(rebank: true) }
            }
            .onReceive(state.provider.$revision.dropFirst()) { _ in Task { await state.load(rebank: false) } }
            .sheet(item: $editing) { mode in
                IntakeQuickAddSheet(mode: mode, store: state.quickAdd,
                                    days: state.snapshot?.quickAddDays ?? [],
                                    presets: state.snapshot?.presets ?? [],
                                    shownDay: state.snapshot?.entriesDay) {
                    Task { await state.load(rebank: false) }
                }
            }
            .sheet(isPresented: $showsSettings) {
                NavigationStack {
                    ScrollView {
                        IntakeSettingsSection()
                            .padding(NoopTheme.Layout.gutter)
                    }
                    .background(NoopTheme.canvas.ignoresSafeArea())
                    .navigationTitle(Text("Intake"))
                    .navigationBarTitleDisplayMode(.inline)
                }
                .onDisappear { Task { await state.load(rebank: false) } }
            }
    }
}

/// What the screen's controls do. The demo passes inert closures.
struct IntakeScreenActions {
    var choose: (IntakeSourceSetting) -> Void = { _ in }
    var tick: (Bool, String) -> Void = { _, _ in }
    var add: () -> Void = {}
    var edit: (IntakeEntry) -> Void = { _ in }
    var replaceRestored: () -> Void = {}
    var openSettings: () -> Void = {}
    var readAgain: () -> Void = {}
    var showDay: (String) -> Void = { _ in }
}

/// The screen for one snapshot; nil draws the loading skeleton.
struct IntakeScreenContent: View {
    let snapshot: IntakeScreenSnapshot?
    var actions = IntakeScreenActions()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var stacks: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.cardGap) {
                if let snapshot, snapshot.model.layout != .loading {
                    switch snapshot.model.layout {
                    case .setup: setup(snapshot.model)
                    case .supplementsOnly: supplementsOnly(snapshot)
                    case .full, .loading: full(snapshot)
                    }
                } else {
                    skeleton
                }
            }
            .padding(.horizontal, NoopTheme.Layout.gutter)
            .padding(.vertical, NoopTheme.Layout.l)
        }
        .background(NoopTheme.canvas.ignoresSafeArea())
        .navigationTitle(Text("Intake"))
    }

    // MARK: Layouts

    private var skeleton: some View {
        VStack(spacing: NoopTheme.Layout.cardGap) {
            NoopGlassCard { Color.clear.frame(height: 160) }.noopSkeleton(true)
            NoopGlassCard { Color.clear.frame(height: 180) }.noopSkeleton(true)
        }
    }

    private func setup(_ model: IntakeScreenModel) -> some View {
        NoopGlassCard {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
                Text(verbatim: IntakePresenter.setupPrompt).noopFont(.rowTitle)
                ForEach(Array(zip(IntakePresenter.setupSources, model.setupChoices)), id: \.0) { source, sentence in
                    let available = source != .appleHealth || IntakeSettings.appleHealthReadAvailable
                    Button { actions.choose(source) } label: {
                        HStack {
                            Text(verbatim: sentence)
                                .noopFont(.bodySmall, color: false)
                                .foregroundStyle(available ? NoopTheme.textPrimary : NoopTheme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            FormKitChevron()
                        }
                        .padding(.vertical, NoopTheme.Layout.s)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!available)
                }
            }
        }
    }

    private func supplementsOnly(_ snapshot: IntakeScreenSnapshot) -> some View {
        VStack(alignment: .leading, spacing: NoopTheme.Layout.cardGap) {
            supplements(snapshot.supplements)
            NoopGlassCard(flush: true) {
                Button(action: actions.openSettings) {
                    NoopListRow("Cutoff time", systemImage: "clock", color: NoopTheme.textPrimary, showsDivider: false)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func full(_ snapshot: IntakeScreenSnapshot) -> some View {
        let model = snapshot.model
        if let attention = model.attention {
            NoopGlassCard(flush: true) {
                Button(action: actions.openSettings) {
                    IntakeTextRow(title: attention, showsDivider: false)
                }
                .buttonStyle(.plain)
            }
        }
        if let protein = model.protein { proteinCard(protein, model: model) }
        if let energy = model.energy { energyCard(energy) }
        supplements(snapshot.supplements)
        if let chart = model.chart { chartCard(chart) }
        sourceCard(model)
        if !model.entries.isEmpty || model.showsRestoredTotal || snapshot.model.sourceLine == IntakePresenter.enteredHere {
            entriesCard(snapshot)
        }
    }

    // MARK: Sections

    private func proteinCard(_ protein: IntakeScreenModel.Protein, model: IntakeScreenModel) -> some View {
        NoopGlassCard {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
                let numbers = VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
                    Text(verbatim: IntakePresenter.cardTitle).noopFont(.footnote)
                    HStack(alignment: .firstTextBaseline, spacing: NoopTheme.Layout.xs) {
                        Text(verbatim: protein.value ?? "—")
                            .noopFont(.bigNumber, color: false)
                            .foregroundStyle(protein.value == nil || model.freshnessIsStale
                                             ? NoopTheme.textTertiary : NoopTheme.textPrimary)
                        if protein.value != nil { Text(verbatim: "g").noopFont(.unit) }
                    }
                    if let floor = protein.floorGrams {
                        Text("of \(floor) g").noopFont(.footnote)
                    }
                    Text(verbatim: protein.line)
                        .noopFont(.bodySmall, color: false)
                        .foregroundStyle(NoopTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                let ring = NoopRing(value: protein.ring, color: model.freshnessIsStale ? NoopTheme.textTertiary : NoopTheme.textPrimary,
                                    diameter: stacks ? 120 : 96, animate: false,
                                    accessibilityLabel: IntakePresenter.cardTitle, accessibilityValue: protein.line)
                if stacks {
                    VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
                        if protein.ring != nil { ring }
                        numbers
                    }
                } else {
                    HStack(alignment: .center, spacing: NoopTheme.Layout.l) {
                        numbers.frame(maxWidth: .infinity, alignment: .leading)
                        if protein.ring != nil { ring }
                    }
                }
                if protein.showsSetFloorRow {
                    Button(action: actions.openSettings) {
                        NoopListRow("Set your protein floor", color: NoopTheme.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func energyCard(_ energy: IntakeScreenModel.Energy) -> some View {
        NoopGlassCard {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
                Text(verbatim: energy.title).noopFont(.footnote)
                Text(verbatim: energy.value ?? "—")
                    .noopFont(.rowNumber, color: false)
                    .foregroundStyle(energy.value == nil ? NoopTheme.textTertiary : NoopTheme.textPrimary)
                if let line = energy.line {
                    Text(verbatim: line)
                        .noopFont(.bodySmall)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func supplements(_ rows: [IntakeSupplementRow]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                NoopSectionHeader("Supplements")
                NoopGlassCard(flush: true) {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.question) { index, row in
                            if index > 0 { FormKitDivider() }
                            Button { actions.tick(!row.isTicked, row.question) } label: {
                                HStack(spacing: NoopTheme.Layout.m) {
                                    Image(systemName: row.isTicked ? "checkmark.square.fill" : "square")
                                        .noopFont(.rowTitle, color: false)
                                        .foregroundStyle(NoopTheme.textPrimary)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: FormKitLayout.detailGap) {
                                        Text(verbatim: row.name).noopFont(.listTitle)
                                        if let caption = row.caption {
                                            Text(verbatim: caption).noopFont(.footnote)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, NoopTheme.Layout.rowVerticalPadding)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(row.isTicked ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                }
            }
        }
    }

    private func chartCard(_ chart: IntakeScreenModel.Chart) -> some View {
        NoopGlassCard {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                Text("Last 28 days").noopFont(.footnote)
                if let message = chart.message {
                    Text(verbatim: message)
                        .noopFont(.bodySmall)
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                } else {
                    IntakeHistoryChart(points: chart.points)
                        .frame(height: 140)
                    HStack(spacing: NoopTheme.Layout.m) {
                        Label { Text("At or above your floor") } icon: { Image(systemName: "circle.fill") }
                        Label { Text("Below your floor") } icon: { Image(systemName: "circle") }
                    }
                    .noopFont(.caption)
                }
            }
        }
    }

    private func sourceCard(_ model: IntakeScreenModel) -> some View {
        NoopGlassCard {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                HStack(alignment: .firstTextBaseline) {
                    if let source = model.sourceLine {
                        Text(verbatim: source).noopFont(.bodySmall, color: false).foregroundStyle(NoopTheme.textPrimary)
                    }
                    Spacer(minLength: NoopTheme.Layout.s)
                    if let freshness = model.freshness {
                        Text(verbatim: freshness)
                            .noopFont(.footnote, color: false)
                            .foregroundStyle(model.freshnessIsStale ? NoopTheme.textSecondary : NoopTheme.textTertiary)
                    }
                }
                if let problem = model.problem {
                    Text(verbatim: problem).noopFont(.footnote).fixedSize(horizontal: false, vertical: true)
                }
                if let twoApps = model.twoApps {
                    Text(verbatim: twoApps).noopFont(.footnote).fixedSize(horizontal: false, vertical: true)
                }
                if model.showsChooseOne {
                    Button("Choose one", action: actions.openSettings).noopFont(.bodySmall)
                }
                if let correction = model.correction {
                    Text(verbatim: correction).noopFont(.footnote).fixedSize(horizontal: false, vertical: true)
                }
                if model.showsReadAgain {
                    Button("Read again", action: actions.readAgain).noopFont(.bodySmall)
                }
                if model.showsDataSourcesRow {
                    NavigationLink(value: MoreDestination.dataSources) {
                        NoopListRow("Data Sources", color: NoopTheme.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func entriesCard(_ snapshot: IntakeScreenSnapshot) -> some View {
        let model = snapshot.model
        return VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
            HStack(alignment: .firstTextBaseline) {
                NoopSectionHeader("Entries")
                Spacer(minLength: NoopTheme.Layout.s)
                Picker("Day", selection: Binding(get: { snapshot.entriesDay }, set: { actions.showDay($0) })) {
                    ForEach(snapshot.quickAddDays, id: \.self) { key in
                        Text(verbatim: IntakePresenter.dayLabel(key, today: snapshot.day, timeZone: .current,
                                                                locale: AppClock.formattingLocale)).tag(key)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(NoopTheme.textPrimary)
            }
            NoopGlassCard(flush: true) {
                VStack(spacing: 0) {
                    if model.showsRestoredTotal {
                        Button(action: actions.replaceRestored) {
                            NoopListRow("Restored total", color: NoopTheme.textPrimary, value: String(localized: "Replace"),
                                        showsDivider: false)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(Array(model.entries.enumerated()), id: \.element.id) { index, entry in
                        Button { actions.edit(entry) } label: {
                            let amounts = IntakePresenter.entryAmounts(entry, locale: AppClock.formattingLocale)
                            IntakeTextRow(title: entry.label ?? amounts,
                                          detail: entry.label == nil ? nil : amounts,
                                          showsDivider: index > 0 || model.showsRestoredTotal)
                        }
                        .buttonStyle(.plain)
                    }
                    Button(action: actions.add) {
                        NoopListRow("Add food", systemImage: "plus", color: NoopTheme.textPrimary,
                                    showsDivider: !model.entries.isEmpty || model.showsRestoredTotal)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// A list row whose title is data or an already resolved sentence, drawn verbatim.
private struct IntakeTextRow: View {
    let title: String
    var detail: String? = nil
    var showsDivider = true

    var body: some View {
        VStack(spacing: 0) {
            if showsDivider { FormKitDivider() }
            HStack(spacing: NoopTheme.Layout.m) {
                VStack(alignment: .leading, spacing: FormKitLayout.detailGap) {
                    Text(verbatim: title).noopFont(.listTitle).fixedSize(horizontal: false, vertical: true)
                    if let detail { Text(verbatim: detail).noopFont(.footnote) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                FormKitChevron()
            }
            .padding(.vertical, NoopTheme.Layout.rowVerticalPadding)
            .padding(.horizontal, NoopTheme.Layout.cardPadding)
            .contentShape(Rectangle())
        }
    }
}

/// The last 28 days of protein: a curve with its fill, broken at every unmeasured day. A day at or
/// above the floor is a filled point and a day below it an open one. No floor line and no band.
struct IntakeHistoryChart: View {
    let points: [IntakeScreenModel.ChartPoint]

    private struct Plotted: Identifiable {
        let index: Int
        let grams: Double
        let run: Int
        let meetsFloor: Bool?
        var id: Int { index }
    }

    private var plotted: [Plotted] {
        var out: [Plotted] = []
        var run = 0
        var previousMeasured = false
        for (index, point) in points.enumerated() {
            guard let grams = point.grams else {
                if previousMeasured { run += 1 }
                previousMeasured = false
                continue
            }
            out.append(Plotted(index: index, grams: grams, run: run, meetsFloor: point.meetsFloor))
            previousMeasured = true
        }
        return out
    }

    var body: some View {
        Chart(plotted) { point in
            AreaMark(x: .value("Day", point.index), y: .value("Protein", point.grams),
                     series: .value("Run", point.run))
                .foregroundStyle(LinearGradient(colors: [NoopTheme.textPrimary.opacity(0.22), NoopTheme.textPrimary.opacity(0)],
                                                startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
            LineMark(x: .value("Day", point.index), y: .value("Protein", point.grams),
                     series: .value("Run", point.run))
                .foregroundStyle(NoopTheme.textPrimary)
                .interpolationMethod(.monotone)
            PointMark(x: .value("Day", point.index), y: .value("Protein", point.grams))
                .symbol {
                    Circle()
                        .strokeBorder(NoopTheme.textPrimary, lineWidth: 1.5)
                        .background(Circle().fill(point.meetsFloor == true ? NoopTheme.textPrimary : NoopTheme.canvas))
                        .frame(width: 7, height: 7)
                }
        }
        .chartXScale(domain: 0...max(points.count - 1, 1))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Last 28 days"))
        // Codex C19: the curve's data in words, gaps and floor state included.
        .accessibilityValue(Text(verbatim: IntakePresenter.chartAccessibilitySummary(points)))
    }
}

// MARK: - The Today card's reader

/// Feeds the protein card into the cards it wraps, computed by the presenter from one clock, and
/// refreshes the provider when the card appears and after each repository refresh. Mounted only
/// while the card is rendered, so with the flag off, or the card not added, nothing is read.
struct IntakeCardReader<Content: View>: View {
    @ObservedObject var provider: IntakeProvider
    let selectedDayKey: String
    let isToday: Bool
    let refreshSequence: Int
    @ViewBuilder let content: (IntakeCard) -> Content
    @State private var loaded = false

    var body: some View {
        content(card)
            .task(id: refreshSequence) {
                await provider.refresh()
                loaded = true
                IntakeWidgetPublisher.publish(provider: provider, clock: IntakeClock.current(settings: provider.settings))
            }
    }

    private var card: IntakeCard {
        guard loaded else { return IntakePresenter.loadingCard() }
        let clock = IntakeClock.current(settings: provider.settings)
        // The redesign selects the logical day; the current day shows the calendar day (§9.5, R33).
        let day = isToday ? clock.today : selectedDayKey
        let input = IntakePresenterInput.gather(provider: provider, settings: provider.settings, day: day)
        return IntakePresenter.card(input, clock: clock, timeZone: .current, locale: AppClock.formattingLocale)
    }
}

// MARK: - The scorecard's protein row (§10.4)

/// Wraps the scorecard's protein row while the intake flag is on: it names where the seven days'
/// protein came from and opens the intake screen (stage 1 ruling R41: every place that shows the
/// value offers the way to correct it).
struct ScorecardIntakeProteinRow<Row: View>: View {
    /// The judged weigh-in day the protein signal counts back from; nil: no judged week, no caption.
    let anchorDay: String?
    @ViewBuilder let row: () -> Row
    @State private var caption: String?

    var body: some View {
        NavigationLink(value: RedesignRoute.intake) {
            VStack(alignment: .leading, spacing: 0) {
                row()
                if let caption {
                    SourceCaption(verbatim: caption)
                        .padding(.bottom, NoopTheme.Layout.s)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task(id: anchorDay) { await loadCaption() }
    }

    private func loadCaption() async {
        guard let anchorDay, let repository = AppModel.shared?.repo else {
            caption = nil
            return
        }
        let provider = IntakeProvider.live(repository: repository)
        await provider.refresh()
        caption = IntakePresenter.scorecardProteinCaption(
            flagEnabled: provider.settings.isEnabled,
            sources: IntakePresenter.scorecardProteinSources(provider.series(), anchorDay: anchorDay))
    }
}
