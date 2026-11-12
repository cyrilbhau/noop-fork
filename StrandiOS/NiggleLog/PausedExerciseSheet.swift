import SwiftUI
import StrandAnalytics
import StrandDesign

// Stage 6 (niggle log), specification §10.6, frames E1 to E5 of `design/round-s6-niggle-timeline/`.
// An exercise the owner's coach paused, with its reason (required), an optional "until" in the
// owner's words, the paused date and an optional link to an open niggle; "Mark resumed" with a date;
// delete asks once. The list is a record: nothing is hidden or flagged in a lift session.

struct PausedExerciseSheet: View {
    @ObservedObject var model: NiggleLogModel
    let editing: StoredPausedExercise?
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PausedExerciseDraft
    @State private var pausedOn: Date
    @State private var resumes = false
    @State private var resumedOn: Date
    @State private var asksDelete = false
    @State private var saving = false
    @State private var refused = false

    private let timeZone = TimeZone.current

    init(model: NiggleLogModel, editing: StoredPausedExercise? = nil, asksDelete: Bool = false) {
        self.model = model
        self.editing = editing
        let today = model.today
        let draft = editing.map { PausedExerciseDraft(pause: $0) } ?? PausedExerciseDraft.new(today: today)
        _draft = State(initialValue: draft)
        _pausedOn = State(initialValue: Stage6DayPicker.date(forDay: draft.pause.pausedDay, timeZone: .current) ?? Date())
        _resumes = State(initialValue: draft.pause.resumedDay != nil)
        _resumedOn = State(initialValue: Stage6DayPicker.date(forDay: draft.pause.resumedDay ?? today, timeZone: .current)
            ?? Date())
        _asksDelete = State(initialValue: asksDelete)
    }

    private var todayDate: Date { Stage6DayPicker.date(forDay: model.today, timeZone: timeZone) ?? Date() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NoopTheme.Layout.l) {
                    if refused { ScorecardFootnote(text: NiggleLogPresenter.couldNotSave, color: NoopTheme.textPrimary) }
                    Stage6FormCard {
                        FormKitControlRow("Exercise", showsDivider: false) {
                            TextField(text: $draft.pause.exercise) { Text("Exercise") }
                                .multilineTextAlignment(.trailing)
                                .noopFont(.body)
                        }
                        FormKitControlRow("Reason") {
                            TextField(text: $draft.pause.reason) { Text("Reason") }
                                .multilineTextAlignment(.trailing)
                                .noopFont(.body)
                        }
                        FormKitControlRow("Until") {
                            TextField(text: Binding(get: { draft.pause.until ?? "" },
                                                    set: { draft.pause.until = $0.isEmpty ? nil : $0 })) { Text("Optional") }
                                .multilineTextAlignment(.trailing)
                                .accessibilityLabel(Text("Until"))
                                .noopFont(.body)
                        }
                        FormKitControlRow("Paused on") {
                            DatePicker("Paused on", selection: $pausedOn, in: ...todayDate, displayedComponents: .date).labelsHidden()
                        }
                        FormKitControlRow("Linked niggle") {
                            Picker(selection: $draft.pause.niggleId) {
                                Text("None").tag(String?.none)
                                ForEach(model.openComplaints) { niggle in
                                    Text(verbatim: niggle.location).tag(String?.some(niggle.id))
                                }
                            } label: { Text("Linked niggle") }
                            .pickerStyle(.menu)
                            .tint(NoopTheme.textSecondary)
                        }
                    }
                    if let issue = NiggleLogPresenter.pauseIssue(draft), editing != nil || !draft.pause.exercise.isEmpty {
                        ScorecardFootnote(text: issue)
                    }
                    if editing != nil {
                        Stage6FormCard {
                            FormKitControlRow(LocalizedStringKey(NiggleLogPresenter.markResumedTitle), showsDivider: false) {
                                Toggle(isOn: $resumes) { Text(verbatim: NiggleLogPresenter.markResumedTitle) }.labelsHidden().tint(NoopTheme.recovery)
                            }
                            if resumes {
                                FormKitControlRow("Resumed on") {
                                    DatePicker("Resumed on", selection: $resumedOn, in: pausedOn...max(pausedOn, todayDate),
                                               displayedComponents: .date).labelsHidden()
                                }
                            }
                        }
                        Button(role: .destructive) { asksDelete = true } label: {
                            Label { Text(verbatim: NiggleLogPresenter.deleteTitle) } icon: { Image(systemName: "trash") }
                        }
                        .buttonStyle(ScorecardDangerButton())
                        .formKitGutter()
                    }
                }
                .padding(.vertical, NoopTheme.Layout.l)
                .disabled(saving)
                .opacity(saving ? ScorecardLayout.busyOpacity : 1)
            }
            .background(NoopTheme.sheet.ignoresSafeArea())
            .navigationTitle(Text(verbatim: editing == nil ? NiggleLogPresenter.pauseExerciseTitle
                                                           : NiggleLogPresenter.editPauseTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel") }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Text("Save") }.disabled(!draft.canSave || saving)
                }
            }
            .confirmationDialog(Text(verbatim: NiggleLogPresenter.deletePauseTitle), isPresented: $asksDelete,
                                titleVisibility: .visible) {
                Button(role: .destructive) { delete() } label: { Text(verbatim: NiggleLogPresenter.deleteTitle) }
                Button(role: .cancel) {} label: { Text("Cancel") }
            } message: {
                Text(verbatim: NiggleLogPresenter.deletePauseDetail)
            }
        }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(saving)
    }

    /// Captures every input, then writes once. A refused write leaves the sheet as it was.
    private func save() {
        var pause = draft.pause
        pause.pausedDay = Stage6DayPicker.day(for: pausedOn, timeZone: timeZone)
        pause.resumedDay = resumes ? Stage6DayPicker.day(for: resumedOn, timeZone: timeZone) : nil
        saving = true
        Task {
            let saved = await model.save(pause)
            saving = false
            if saved { dismiss() } else { refused = true }
        }
    }

    private func delete() {
        guard let id = editing?.id else { return }
        Task {
            await model.delete(pausedId: id)
            dismiss()
        }
    }
}
