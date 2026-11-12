import SwiftUI
import StrandDesign

// Stage 4 (body record), docs/personal/superapp/specs/stage-4.md §10.2, frames H1 to H14 of
// `design/round-s4-body-record/`: one sheet for a whole scan, typed in the order a report prints it.
// The sheet draws `BodyScanSheetModel` and decides nothing: which fields exist, what each says,
// whether Save is enabled and the weigh-in line are the presenter's.

struct BodyScanSheetScreen: View {
    private let context: BodyRecordContext
    @StateObject private var model: BodyScanSheetModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var confirmingDelete = false
    private let onDeleted: () -> Void
    /// The scan as saved: an edit that changes the day gives it a new id.
    private let onSaved: (BodyScan) -> Void

    /// `model` is for the debug demo, which opens the sheet in a given state.
    init(context: BodyRecordContext, editing: BodyScan?, model: BodyScanSheetModel? = nil,
         confirmingDelete: Bool = false, onDeleted: @escaping () -> Void = {},
         onSaved: @escaping (BodyScan) -> Void = { _ in }) {
        self.context = context
        self.onDeleted = onDeleted
        self.onSaved = onSaved
        _model = StateObject(wrappedValue: model ?? context.sheetModel(editing: editing))
        _confirmingDelete = State(initialValue: confirmingDelete)
    }

    private var state: BodyScanSheetState { model.state }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
                header
                BodyRecordNote(text: state.introText)
                DatePicker(selection: Binding(get: { model.date }, set: { model.date = $0 }),
                           in: ...context.now(), displayedComponents: [.date]) {
                    Text(verbatim: BodyRecordPresenter.dateTitle).noopFont(.bodySmall)
                }
                .disabled(state.controlsDisabled)
                if let status = state.statusMessage { BodyRecordNote(text: status) }
                ForEach(state.sections, id: \.section) { section in
                    sectionCard(section)
                }
                noteCard
                if let message = state.formMessage { BodyRecordNote(text: message) }
                actions
            }
            .padding(.horizontal, NoopTheme.Layout.gutter)
            .padding(.vertical, NoopTheme.Layout.l)
            .opacity(state.controlsDisabled ? BodyRecordLayout.busyOpacity : 1)
        }
        .background(NoopTheme.sheet.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(state.controlsDisabled)
        .task(id: model.entry) { await model.evaluate() }
        .confirmationDialog(Text(verbatim: BodyRecordPresenter.scanDeleteConfirmation().title),
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(role: .destructive) {
                Task {
                    if await model.delete() {
                        onDeleted()
                        dismiss()
                    }
                }
            } label: { Text(verbatim: BodyRecordPresenter.scanDeleteConfirmation().confirmTitle) }
            Button(role: .cancel) {} label: { Text(verbatim: BodyRecordPresenter.scanDeleteConfirmation().cancelTitle) }
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Text(verbatim: BodyRecordPresenter.cancelTitle)
                    .noopFont(.body, color: false)
                    .foregroundStyle(NoopTheme.textPrimary)
                    .frame(minHeight: NoopTheme.Layout.minTouchTarget)
            }
            .buttonStyle(.noopPress)
            .disabled(state.controlsDisabled)
            Spacer()
            Text(verbatim: model.isEditing ? BodyRecordPresenter.editScanTitle : BodyRecordPresenter.addScanTitle)
                .noopFont(.navTitle)
            Spacer()
        }
    }

    private func sectionCard(_ section: BodyScanSheetSection) -> some View {
        VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
            BodyRecordSectionTitle(title: section.title)
            NoopGlassCard {
                VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
                    ForEach(section.fields, id: \.key) { field in
                        fieldRow(field)
                        if field.key == section.fields.first?.key, section.section == .wholeBody,
                           let line = state.weighInLine {
                            BodyRecordNote(text: line)
                        }
                    }
                }
            }
            if let mismatch = section.mismatchText { BodyRecordNote(text: mismatch) }
        }
    }

    private func fieldRow(_ field: BodyScanSheetField) -> some View {
        VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
            let stacks = dynamicTypeSize.isAccessibilitySize
            let input = HStack(spacing: NoopTheme.Layout.s) {
                if field.hasSignToggle {
                    Button { model.toggleSign(field.key) } label: {
                        Image(systemName: "plus.forwardslash.minus")
                            .noopFont(.body, color: false)
                            .foregroundStyle(NoopTheme.textPrimary)
                            .frame(minWidth: NoopTheme.Layout.minTouchTarget, minHeight: NoopTheme.Layout.minTouchTarget)
                    }
                    .buttonStyle(.noopPress)
                    .accessibilityLabel(Text(verbatim: BodyRecordPresenter.signToggleTitle))
                }
                TextField("", text: Binding(get: { model.text(field.key) }, set: { model.setText($0, for: field.key) }))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .noopFont(.rowNumber, color: false)
                    .foregroundStyle(NoopTheme.textPrimary)
                    .accessibilityLabel(Text(verbatim: field.label))
                if field.unitOptions.count > 1 {
                    Picker(selection: Binding(get: { field.unit }, set: { model.setUnit($0, for: field.key) })) {
                        ForEach(field.unitOptions, id: \.self) { Text(verbatim: $0).tag($0) }
                    } label: { Text(verbatim: field.unit) }
                    .pickerStyle(.menu)
                    .tint(NoopTheme.textSecondary)
                } else {
                    Text(verbatim: field.unit).noopFont(.unit)
                }
            }
            .disabled(state.controlsDisabled)
            if stacks {
                Text(verbatim: field.label).noopFont(.bodySmall)
                input
            } else {
                HStack(spacing: NoopTheme.Layout.s) {
                    Text(verbatim: field.label).noopFont(.bodySmall)
                    Spacer(minLength: NoopTheme.Layout.s)
                    input
                }
            }
            if let stored = field.storedAsText { BodyRecordNote(text: stored) }
            if let error = field.errorText { BodyRecordNote(text: error) }
        }
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
            BodyRecordSectionTitle(title: BodyScanSection.note.title)
            NoopGlassCard {
                TextField("", text: Binding(get: { model.entry.note }, set: { model.setNote($0) }), axis: .vertical)
                    .noopFont(.body, color: false)
                    .foregroundStyle(NoopTheme.textPrimary)
                    .lineLimit(1...6)
                    .accessibilityLabel(Text(verbatim: BodyScanSection.note.title))
                    .disabled(state.controlsDisabled)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: NoopTheme.Layout.s) {
            Button {
                Task {
                    if let saved = await model.save() {
                        onSaved(saved)
                        dismiss()
                    }
                }
            } label: {
                Text(verbatim: BodyRecordPresenter.saveTitle).frame(maxWidth: .infinity)
            }
            .buttonStyle(.noopPrimary)
            .disabled(!state.canSave)
            if model.isEditing {
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Text(verbatim: BodyRecordPresenter.deleteTitle)
                        .noopFont(.button, color: false)
                        .frame(maxWidth: .infinity, minHeight: NoopTheme.Layout.minTouchTarget)
                }
                .disabled(state.controlsDisabled)
            }
        }
        .padding(.top, NoopTheme.Layout.l)
    }
}
