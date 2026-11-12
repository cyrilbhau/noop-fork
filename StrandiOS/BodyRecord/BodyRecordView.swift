import SwiftUI
import StrandDesign

// Stage 4 (body record), docs/personal/superapp/specs/stage-4.md §10.1, frames G1 to G10 of
// `design/round-s4-body-record/`: the latest scan, the list of scans, the benchmarks and the way to
// Lab Book for blood results. The screen draws `BodyRecordModel` and decides nothing. It shows no
// current weight: a scan's total mass appears with the scan's date.

/// The body-record screen, pushed from the Health tab's row. Exists only while the flag is on.
struct BodyRecordView: View {
    var body: some View {
        BodyRecordGate {
            BodyRecordContextReader { BodyRecordScreenView(context: $0) }
        }
    }
}

struct BodyRecordScreenView: View {
    private let context: BodyRecordContext
    private let loadsOnAppear: Bool
    @StateObject private var model: BodyRecordModel
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    @State private var addingScan = false
    @State private var addingBenchmark = false

    /// `model` and `loadsOnAppear` are for the debug demo, which shows the screen in a given state.
    init(context: BodyRecordContext, model: BodyRecordModel? = nil, loadsOnAppear: Bool = true) {
        self.context = context
        self.loadsOnAppear = loadsOnAppear
        _model = StateObject(wrappedValue: model ?? context.model())
    }

    private var screen: BodyRecordScreen { model.screen }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if screen.isLoading {
                    skeleton
                } else if let message = screen.storeMessage {
                    NoopGlassCard { BodyRecordNote(text: message) }
                        .padding(.top, NoopTheme.Layout.l)
                } else {
                    scansSection
                    benchmarksSection
                    bloodSection
                    BodyRecordNote(text: BodyRecordPresenter.screenNote)
                        .padding(.top, NoopTheme.Layout.l)
                }
            }
            .padding(.horizontal, NoopTheme.Layout.gutter)
            .padding(.bottom, NoopTheme.Layout.xl)
        }
        .background(NoopTheme.canvas.ignoresSafeArea())
        .navigationTitle(Text(verbatim: screen.title))
        .task(id: loadsOnAppear ? repo.refreshSeq : -1) {
            if loadsOnAppear { await model.load() }
        }
        .sheet(isPresented: $addingScan, onDismiss: reload) {
            BodyScanSheetScreen(context: context, editing: nil)
        }
        .sheet(isPresented: $addingBenchmark, onDismiss: reload) {
            BenchmarkSheetScreen(context: context, key: nil)
        }
    }

    private func reload() { Task { await model.load() } }

    // MARK: G1

    private var skeleton: some View {
        VStack(spacing: NoopTheme.Layout.cardGap) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: NoopTheme.Layout.cardRadius, style: .continuous)
                    .fill(NoopTheme.card)
                    .frame(height: BodyRecordLayout.skeletonHeight)
                    .opacity(BodyRecordLayout.skeletonOpacity)
            }
        }
        .padding(.top, NoopTheme.Layout.l)
        .accessibilityHidden(true)
    }

    // MARK: Scans

    private var scansSection: some View {
        VStack(alignment: .leading, spacing: NoopTheme.Layout.cardGap) {
            BodyRecordSectionTitle(title: BodyRecordPresenter.scansTitle)
            if let card = screen.latestScan {
                NavigationLink(value: RedesignRoute.bodyScan(id: card.scanId)) { scanCard(card) }
                    .buttonStyle(.noopPress)
            }
            if let empty = screen.scansEmptyText {
                NoopGlassCard { BodyRecordNote(text: empty) }
            }
            if let second = screen.addSecondScanText { BodyRecordNote(text: second) }
            if let compare = screen.compareTitle {
                NavigationLink(value: RedesignRoute.bodyScanCompare(earlierId: nil, laterId: nil)) {
                    NoopListRow(LocalizedStringKey(compare), systemImage: "arrow.left.arrow.right",
                                color: NoopTheme.textPrimary, showsDivider: false)
                }
                .buttonStyle(.noopPress)
            }
            if !screen.scanRows.isEmpty {
                NoopGlassCard(flush: true) {
                    VStack(spacing: 0) {
                        ForEach(Array(screen.scanRows.enumerated()), id: \.element.scanId) { index, row in
                            NavigationLink(value: RedesignRoute.bodyScan(id: row.scanId)) {
                                NoopListRow(LocalizedStringKey(row.dateText), color: NoopTheme.textPrimary,
                                            showsDivider: index > 0)
                            }
                        }
                    }
                    .buttonStyle(.noopPress)
                }
            }
            if let add = screen.addScanTitle {
                BodyRecordButton(title: add) { addingScan = true }
            }
        }
    }

    private func scanCard(_ card: BodyScanCard) -> some View {
        NoopGlassCard {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                Text(verbatim: card.dateText).noopFont(.rowTitle)
                if let imported = card.importedText { BodyRecordNote(text: imported) }
                ForEach(Array(card.figures.enumerated()), id: \.element.key) { index, figure in
                    BodyRecordFigureRow(figure: figure, showsDivider: index > 0)
                }
                if let derived = card.derivedLine { BodyRecordNote(text: derived) }
                if let unreadable = card.unreadableText { BodyRecordNote(text: unreadable) }
                if let conflicting = card.conflictingText { BodyRecordNote(text: conflicting) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Benchmarks

    private var benchmarksSection: some View {
        VStack(alignment: .leading, spacing: NoopTheme.Layout.cardGap) {
            BodyRecordSectionTitle(title: BodyRecordPresenter.benchmarksTitle)
            if let empty = screen.benchmarksEmptyText {
                NoopGlassCard { BodyRecordNote(text: empty) }
            }
            if !screen.benchmarks.isEmpty {
                NoopGlassCard {
                    VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
                        ForEach(Array(screen.benchmarks.enumerated()), id: \.element.key) { index, row in
                            NavigationLink(value: RedesignRoute.benchmark(key: row.key)) {
                                benchmarkRow(row, showsDivider: index > 0)
                            }
                            .buttonStyle(.noopPress)
                        }
                    }
                }
            }
            if let add = screen.addBenchmarkTitle {
                BodyRecordButton(title: add) { addingBenchmark = true }
            }
        }
    }

    private func benchmarkRow(_ row: BenchmarkRow, showsDivider: Bool) -> some View {
        VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
            if showsDivider { Divider().overlay(NoopTheme.separator) }
            HStack(alignment: .firstTextBaseline, spacing: NoopTheme.Layout.s) {
                Text(verbatim: row.name)
                    .noopFont(.rowTitle)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: NoopTheme.Layout.s)
                BodyRecordValue(text: row.valueText, unit: row.unit)
            }
            Text(verbatim: row.dateText).noopFont(.caption)
            if let previous = row.sincePreviousText {
                BodyRecordLabelledLine(label: BodyRecordPresenter.sincePreviousTitle, value: previous)
            }
            if let first = row.sinceFirstText {
                BodyRecordLabelledLine(label: BodyRecordPresenter.sinceFirstTitle, value: first)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: Blood results

    @ViewBuilder
    private var bloodSection: some View {
        if let open = screen.openLabBookTitle {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.cardGap) {
                BodyRecordSectionTitle(title: BodyRecordPresenter.bloodResultsTitle)
                NoopGlassCard(flush: true) {
                    Button { router.openLabBook() } label: {
                        NoopListRow(LocalizedStringKey(open), systemImage: "books.vertical.fill",
                                    color: NoopTheme.hrv, showsDivider: false)
                    }
                    .buttonStyle(.noopPress)
                }
            }
        }
    }
}
