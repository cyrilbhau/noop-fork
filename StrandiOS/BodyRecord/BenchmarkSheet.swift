import SwiftUI
import StrandDesign

// Stage 4 (body record), docs/personal/superapp/specs/stage-4.md §10.5, frames K1 to K4 of
// `design/round-s4-body-record/`: the benchmark picker (the eight, then "Custom benchmark"), the
// value, the date and time, and the condition the test was done under. The sheet draws
// `BenchmarkSheetModel` and decides nothing.

struct BenchmarkSheetScreen: View {
    private let context: BodyRecordContext
    @StateObject private var model: BenchmarkSheetModel
    @Environment(\.dismiss) private var dismiss

    /// `key` preselects a benchmark; nil starts at the first of the list. `model` is for the demo.
    init(context: BodyRecordContext, key: String?, model: BenchmarkSheetModel? = nil) {
        self.context = context
        let firstKey = BodyRecordPresenter.benchmarkChoices().first?.key
        _model = StateObject(wrappedValue: model ?? context.benchmarkModel(key: key ?? firstKey))
    }

    var body: some View {
        let state = model.state
        ScrollView {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
                header
                NoopGlassCard {
                    VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
                        Picker(selection: Binding(get: { model.entry.key }, set: { model.entry.key = $0 })) {
                            ForEach(BodyRecordPresenter.benchmarkChoices(), id: \.name) { choice in
                                Text(verbatim: choice.name).tag(choice.key)
                            }
                        } label: { Text(verbatim: BodyRecordPresenter.benchmarkTitle) }
                        .pickerStyle(.menu)
                        .tint(NoopTheme.textPrimary)
                        if model.entry.key == nil { customFields(state) }
                        HStack(spacing: NoopTheme.Layout.s) {
                            Text(verbatim: BodyRecordPresenter.valueTitle).noopFont(.bodySmall)
                            Spacer(minLength: NoopTheme.Layout.s)
                            TextField("", text: Binding(get: { model.entry.text }, set: { model.entry.text = $0 }))
                                .keyboardType(state.acceptsDuration ? .numbersAndPunctuation : .decimalPad)
                                .multilineTextAlignment(.trailing)
                                .noopFont(.rowNumber, color: false)
                                .foregroundStyle(NoopTheme.textPrimary)
                                .accessibilityLabel(Text(verbatim: BodyRecordPresenter.valueTitle))
                            Text(verbatim: state.unit).noopFont(.unit)
                        }
                        if state.acceptsDuration { BodyRecordNote(text: BodyRecordPresenter.durationHint) }
                        if let error = state.errorText { BodyRecordNote(text: error) }
                        DatePicker(selection: Binding(get: { model.takenAt }, set: { model.takenAt = $0 }),
                                   in: ...context.now(), displayedComponents: [.date, .hourAndMinute]) {
                            Text(verbatim: BodyRecordPresenter.dateTitle).noopFont(.bodySmall)
                        }
                        TextField(BodyRecordPresenter.conditionPrompt,
                                  text: Binding(get: { model.note }, set: { model.note = $0 }))
                            .noopFont(.body, color: false)
                            .foregroundStyle(NoopTheme.textPrimary)
                            .accessibilityLabel(Text(verbatim: BodyRecordPresenter.conditionTitle))
                    }
                }
                Button {
                    Task { if await model.save() != nil { dismiss() } }
                } label: {
                    Text(verbatim: BodyRecordPresenter.saveTitle).frame(maxWidth: .infinity)
                }
                .buttonStyle(.noopPrimary)
                .disabled(!state.canSave || model.isSaving)
            }
            .padding(.horizontal, NoopTheme.Layout.gutter)
            .padding(.vertical, NoopTheme.Layout.l)
        }
        .background(NoopTheme.sheet.ignoresSafeArea())
        .task { await model.prepare() }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
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
            Spacer()
            Text(verbatim: BodyRecordPresenter.addBenchmarkTitle).noopFont(.navTitle)
            Spacer()
        }
    }

    @ViewBuilder
    private func customFields(_ state: BenchmarkEntryState) -> some View {
        TextField(BodyRecordPresenter.nameTitle,
                  text: Binding(get: { model.entry.customName }, set: { model.entry.customName = $0 }))
            .noopFont(.body, color: false)
            .foregroundStyle(NoopTheme.textPrimary)
        Picker(selection: Binding(get: { model.entry.customUnit }, set: { model.entry.customUnit = $0 })) {
            ForEach(state.unitOptions, id: \.self) { Text(verbatim: $0).tag($0) }
        } label: { Text(verbatim: BodyRecordPresenter.unitTitle) }
        .pickerStyle(.segmented)
    }
}
