import SwiftUI
import StrandDesign

// Stage 4 (body record), docs/personal/superapp/specs/stage-4.md §10.5, frames K5 to K8 of
// `design/round-s4-body-record/`: one benchmark's readings, newest first, each with its note and the
// change against the reading before it, and a delete on each. The screen draws `BenchmarkDetail`.

/// One benchmark, pushed with its key.
struct BenchmarkDetailView: View {
    let key: String

    var body: some View {
        BodyRecordGate {
            BodyRecordContextReader { BenchmarkDetailScreen(context: $0, key: key) }
        }
    }
}

struct BenchmarkDetailScreen: View {
    private let context: BodyRecordContext
    private let key: String
    @StateObject private var model: BodyRecordModel
    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDelete: String?
    @State private var adding = false

    init(context: BodyRecordContext, key: String, model: BodyRecordModel? = nil) {
        self.context = context
        self.key = key
        _model = StateObject(wrappedValue: model ?? context.model())
    }

    var body: some View {
        let detail = model.benchmarkDetail(key: key)
        ScrollView {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.cardGap) {
                if let detail {
                    NoopGlassCard {
                        VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                            ForEach(Array(detail.rows.enumerated()), id: \.element.rowId) { index, row in
                                if index > 0 { Divider().overlay(NoopTheme.separator) }
                                readingRow(row)
                            }
                        }
                    }
                    .padding(.top, NoopTheme.Layout.l)
                    if let one = detail.oneReadingText { BodyRecordNote(text: one) }
                }
                BodyRecordButton(title: BodyRecordPresenter.addBenchmarkTitle) { adding = true }
            }
            .padding(.horizontal, NoopTheme.Layout.gutter)
            .padding(.bottom, NoopTheme.Layout.xl)
        }
        .background(NoopTheme.canvas.ignoresSafeArea())
        .navigationTitle(Text(verbatim: detail?.title ?? BodyRecordPresenter.benchmarkName(key)))
        .task(id: repo.refreshSeq) {
            await model.load()
            if model.benchmark(key: key) == nil { dismiss() }
        }
        .sheet(isPresented: $adding, onDismiss: { Task { await model.load() } }) {
            BenchmarkSheetScreen(context: context, key: key)
        }
        .confirmationDialog(Text(verbatim: BodyRecordPresenter.benchmarkDeleteConfirmation().title),
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button(role: .destructive) {
                guard let rowId = pendingDelete else { return }
                Task {
                    _ = await model.deleteBenchmarkReading(rowId: rowId, key: key)
                    if model.benchmark(key: key) == nil { dismiss() }
                }
            } label: { Text(verbatim: BodyRecordPresenter.benchmarkDeleteConfirmation().confirmTitle) }
            Button(role: .cancel) {} label: {
                Text(verbatim: BodyRecordPresenter.benchmarkDeleteConfirmation().cancelTitle)
            }
        }
    }

    private func readingRow(_ row: BenchmarkReadingRow) -> some View {
        HStack(alignment: .top, spacing: NoopTheme.Layout.s) {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
                BodyRecordValue(text: row.valueText, unit: row.unit)
                Text(verbatim: row.dateText).noopFont(.caption)
                if let note = row.note { BodyRecordNote(text: note) }
                if let change = row.changeText { Text(verbatim: change).noopFont(.footnote) }
            }
            Spacer(minLength: NoopTheme.Layout.s)
            Button(role: .destructive) { pendingDelete = row.rowId } label: {
                Image(systemName: "trash")
                    .frame(minWidth: NoopTheme.Layout.minTouchTarget, minHeight: NoopTheme.Layout.minTouchTarget)
            }
            .accessibilityLabel(Text(verbatim: BodyRecordPresenter.deleteTitle))
        }
    }
}
