import SwiftUI
import StrandDesign

// Stage 4 (body record), docs/personal/superapp/specs/stage-4.md §10.3, frames I1 to I8 of
// `design/round-s4-body-record/`: one scan in report order, the derived block and the note. Only the
// fields entered are shown; nothing is drawn as a zero. The screen draws `BodyRecordModel` and
// decides nothing.

/// One scan, pushed with its id. Leaves the stack when the scan no longer exists (I7).
struct BodyScanDetailView: View {
    let scanId: String

    var body: some View {
        BodyRecordGate {
            BodyRecordContextReader { BodyScanDetailScreen(context: $0, scanId: scanId) }
        }
    }
}

struct BodyScanDetailScreen: View {
    private let context: BodyRecordContext
    private let scanId: String
    @StateObject private var model: BodyRecordModel
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    @Environment(\.dismiss) private var dismiss
    @State private var editing: BodyScan?
    @State private var confirmingDelete = false

    init(context: BodyRecordContext, scanId: String, model: BodyRecordModel? = nil) {
        self.context = context
        self.scanId = scanId
        _model = StateObject(wrappedValue: model ?? context.model())
    }

    private var detail: BodyScanDetail? { model.detail(id: scanId) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.cardGap) {
                if let detail { content(detail) }
            }
            .padding(.horizontal, NoopTheme.Layout.gutter)
            .padding(.bottom, NoopTheme.Layout.xl)
        }
        .background(NoopTheme.canvas.ignoresSafeArea())
        .navigationTitle(Text(verbatim: detail?.dateText ?? ""))
        .toolbar {
            if detail?.canEdit == true {
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = model.scan(id: scanId) } label: {
                        Text(verbatim: BodyRecordPresenter.editTitle)
                    }
                }
            }
        }
        .task(id: repo.refreshSeq) {
            await model.load()
            if model.scan(id: scanId) == nil { dismiss() }
        }
        .sheet(item: Binding(get: { editing.map(EditingScan.init) }, set: { editing = $0?.scan }),
               onDismiss: { Task { await model.load(); if model.scan(id: scanId) == nil { dismiss() } } }) { item in
            BodyScanSheetScreen(context: context, editing: item.scan)
        }
        .confirmationDialog(Text(verbatim: BodyRecordPresenter.scanDeleteConfirmation().title),
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(role: .destructive) {
                Task {
                    guard let scan = model.scan(id: scanId) else { return }
                    if await model.delete(scan) { dismiss() }
                }
            } label: { Text(verbatim: BodyRecordPresenter.scanDeleteConfirmation().confirmTitle) }
            Button(role: .cancel) {} label: { Text(verbatim: BodyRecordPresenter.scanDeleteConfirmation().cancelTitle) }
        }
    }

    @ViewBuilder
    private func content(_ detail: BodyScanDetail) -> some View {
        if let imported = detail.importedText {
            NoopGlassCard { BodyRecordNote(text: imported) }.padding(.top, NoopTheme.Layout.l)
        }
        ForEach(detail.sections, id: \.section) { section in
            BodyRecordSectionTitle(title: section.title)
            NoopGlassCard {
                VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                    ForEach(Array(section.figures.enumerated()), id: \.element.key) { index, figure in
                        BodyRecordFigureRow(figure: figure, showsDivider: index > 0)
                    }
                }
            }
        }
        if !detail.derived.isEmpty {
            NoopGlassCard {
                VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                    ForEach(Array(detail.derived.enumerated()), id: \.element.title) { index, row in
                        if index > 0 { Divider().overlay(NoopTheme.separator) }
                        HStack(alignment: .firstTextBaseline, spacing: NoopTheme.Layout.s) {
                            Text(verbatim: row.title).noopFont(.bodySmall)
                            Spacer(minLength: NoopTheme.Layout.s)
                            Text(verbatim: row.valueText)
                                .noopFont(.bodySmall, color: false)
                                .foregroundStyle(NoopTheme.textPrimary)
                                .multilineTextAlignment(.trailing)
                        }
                        if let caption = row.caption { BodyRecordNote(text: caption) }
                    }
                }
            }
            .padding(.top, NoopTheme.Layout.l)
        }
        if let note = detail.note {
            BodyRecordSectionTitle(title: BodyScanSection.note.title)
            NoopGlassCard {
                Text(verbatim: note)
                    .noopFont(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if let unreadable = detail.unreadableText {
            BodyRecordNote(text: unreadable)
            ForEach(detail.unreadableLabels, id: \.self) { BodyRecordNote(text: $0) }
        }
        if let conflicting = detail.conflictingText {
            BodyRecordNote(text: conflicting)
            ForEach(detail.conflictingLabels, id: \.self) { BodyRecordNote(text: $0) }
        }
        if let open = detail.openLabBookTitle {
            BodyRecordButton(title: open) { router.openLabBook() }
        }
        if detail.canDelete {
            Button(role: .destructive) { confirmingDelete = true } label: {
                Text(verbatim: BodyRecordPresenter.deleteTitle)
                    .noopFont(.button, color: false)
                    .frame(maxWidth: .infinity, minHeight: NoopTheme.Layout.minTouchTarget)
            }
            .padding(.top, NoopTheme.Layout.l)
        }
    }
}

/// The scan being edited, as a sheet item.
private struct EditingScan: Identifiable {
    let scan: BodyScan
    var id: String { scan.id }
}
