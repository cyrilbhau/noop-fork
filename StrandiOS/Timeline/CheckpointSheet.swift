import SwiftUI
import StrandAnalytics
import StrandDesign

// Stage 6 (checkpoint timeline), specification §10.8 "Checkpoint sheet", frames H1 to H12 of
// `design/round-s6-niggle-timeline/`. Title, category, date, "approximate", "done" (only on or before
// today), a waypoint weight in the display unit (never a target), or the phase a target date belongs
// to with that phase's own target shown read-only. Every message is the store's `CheckpointIssue`
// for the draft, worded by the presenter; the sheet decides nothing.

struct CheckpointSheet: View {
    @ObservedObject var model: CheckpointTimelineModel
    let editing: StoredCheckpoint?
    /// Opens stage 1's phase sheet in place of this one.
    let onEditPhase: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CheckpointDraft
    @State private var day: Date
    @State private var asksDelete = false
    @State private var saving = false
    @State private var refusal: String?

    private let timeZone = TimeZone.current

    init(model: CheckpointTimelineModel, editing: StoredCheckpoint? = nil, asksDelete: Bool = false,
         onEditPhase: @escaping () -> Void) {
        self.model = model
        self.editing = editing
        self.onEditPhase = onEditPhase
        let today = model.today ?? Stage6DayPicker.day(for: Date(), timeZone: .current)
        var draft = CheckpointDraft.new(today: today, phases: model.phases)
        if let editing {
            draft = CheckpointDraft(checkpoint: editing,
                                    weightText: CheckpointTimelinePresenter.weightFieldText(
                                        editing.waypointWeightKg, unitSystem: model.unitSystem(), locale: AppLanguage.activeLocale))
        }
        _draft = State(initialValue: draft)
        _day = State(initialValue: Stage6DayPicker.date(forDay: draft.checkpoint.day, timeZone: .current) ?? Date())
        _asksDelete = State(initialValue: asksDelete)
    }

    private var unitSystem: UnitSystem { model.unitSystem() }
    private var today: String { model.today ?? Stage6DayPicker.day(for: Date(), timeZone: timeZone) }

    /// The checkpoint as it would be saved now.
    private var candidate: StoredCheckpoint {
        var c = draft.stored(unitSystem: unitSystem, locale: AppLanguage.activeLocale)
        c.day = Stage6DayPicker.day(for: day, timeZone: timeZone)
        if c.day > today { c.done = false }
        return c
    }

    private var issue: CheckpointIssue? {
        let c = candidate
        return CheckpointTimelineSettings.issue(c, others: model.checkpoints.filter { $0.id != c.id || c.id.isEmpty },
                                                phases: model.phasesForChecks)
    }

    var body: some View {
        let issue = issue
        let message = CheckpointTimelinePresenter.sheetIssueText(issue, checkpoint: candidate, phases: model.phasesForChecks,
                                                                 unitSystem: unitSystem, locale: AppLanguage.activeLocale)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NoopTheme.Layout.l) {
                    if let refusal { ScorecardFootnote(text: refusal, color: NoopTheme.textPrimary) }
                    Stage6FormCard {
                        FormKitControlRow("Title", showsDivider: false) {
                            TextField(text: $draft.checkpoint.title) { Text("Title") }
                                .multilineTextAlignment(.trailing)
                                .noopFont(.body)
                        }
                        FormKitControlRow("Category") {
                            Picker(selection: $draft.checkpoint.category) {
                                ForEach(TimelineCheckpointCategory.allCases, id: \.self) { category in
                                    Text(verbatim: CheckpointTimelinePresenter.categoryText(category)).tag(category)
                                }
                            } label: { Text("Category") }
                            .pickerStyle(.menu)
                            .tint(NoopTheme.textSecondary)
                        }
                        FormKitControlRow("Date") {
                            DatePicker("", selection: $day, displayedComponents: .date).labelsHidden()
                        }
                        FormKitControlRow("Approximate date") {
                            Toggle("", isOn: $draft.checkpoint.approximate).labelsHidden().tint(NoopTheme.recovery)
                        }
                        if candidate.day <= today {
                            FormKitControlRow(LocalizedStringKey(CheckpointTimelinePresenter.doneTitle)) {
                                Toggle("", isOn: $draft.checkpoint.done).labelsHidden().tint(NoopTheme.recovery)
                            }
                        }
                    }
                    if draft.checkpoint.category == .weightWaypoint { waypointFields(issue: issue, message: message) }
                    if draft.checkpoint.category == .targetDate { targetDateFields(message: message) }
                    if draft.checkpoint.category != .weightWaypoint && draft.checkpoint.category != .targetDate,
                       let message, !draft.checkpoint.title.isEmpty || editing != nil {
                        ScorecardFootnote(text: message)
                    }
                    if editing != nil {
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
            .navigationTitle(Text(verbatim: editing == nil ? CheckpointTimelinePresenter.addCheckpointTitle
                                                           : CheckpointTimelinePresenter.editCheckpointTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel") }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Text("Save") }.disabled(issue != nil || saving)
                }
            }
            .confirmationDialog(Text(verbatim: CheckpointTimelinePresenter.deleteCheckpointTitle), isPresented: $asksDelete,
                                titleVisibility: .visible) {
                Button(role: .destructive) { delete() } label: { Text(verbatim: NiggleLogPresenter.deleteTitle) }
                Button(role: .cancel) {} label: { Text("Cancel") }
            } message: {
                Text(verbatim: CheckpointTimelinePresenter.deleteCheckpointDetail)
            }
        }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(saving)
        .onChangeCompat(of: draft.checkpoint.category) { category in
            if category == .targetDate, draft.checkpoint.phaseStartDay == nil {
                draft.checkpoint.phaseStartDay = CheckpointDraft.defaultPhaseStartDay(phases: model.phasesForChecks,
                                                                                      today: today)
            }
        }
    }

    @ViewBuilder
    private func waypointFields(issue: CheckpointIssue?, message: String?) -> some View {
        Stage6FormCard {
            FormKitControlRow("Weight", showsDivider: false) {
                HStack(spacing: NoopTheme.Layout.xs) {
                    TextField(text: $draft.weightText) { Text("Weight") }
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .noopFont(.body)
                    Text(verbatim: CheckpointTimelinePresenter.weightUnit(unitSystem)).noopFont(.footnote)
                }
            }
        }
        if issue == .waypointAtOrBeyondTarget, let message {
            ScorecardFootnote(text: message)
            editPhaseLink
        } else if let message, issue == .weightMissing || issue == .weightOutOfRange, !draft.weightText.isEmpty {
            ScorecardFootnote(text: message)
        } else {
            ScorecardFootnote(text: CheckpointTimelinePresenter.waypointCaption)
        }
    }

    @ViewBuilder
    private func targetDateFields(message: String?) -> some View {
        let phases = model.phasesForChecks
        if phases.isEmpty {
            NoopGlassCard {
                VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                    if let message { Text(verbatim: message).noopFont(.footnote) }
                    editPhaseLink
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .formKitGutter()
        } else {
            Stage6FormCard {
                FormKitControlRow("Phase", showsDivider: false) {
                    Picker(selection: Binding(get: { draft.checkpoint.phaseStartDay ?? "" },
                                              set: { draft.checkpoint.phaseStartDay = $0.isEmpty ? nil : $0 })) {
                        ForEach(phases, id: \.startDay) { phase in
                            Text(verbatim: phase.name).tag(phase.startDay)
                        }
                    } label: { Text("Phase") }
                    .pickerStyle(.menu)
                    .tint(NoopTheme.textSecondary)
                }
            }
            if let phase = phases.first(where: { $0.startDay == draft.checkpoint.phaseStartDay }),
               let target = CheckpointTimelinePresenter.phaseTargetText(phase, unitSystem: unitSystem,
                                                                        locale: AppLanguage.activeLocale) {
                ScorecardFootnote(text: target)
            }
            if let message { ScorecardFootnote(text: message) }
            editPhaseLink
        }
    }

    private var editPhaseLink: some View {
        Button {
            dismiss()
            onEditPhase()
        } label: {
            HStack(spacing: NoopTheme.Layout.xs) {
                Text(verbatim: model.phasesForChecks.isEmpty ? CheckpointTimelinePresenter.setUpPhaseTitle
                                                             : CheckpointTimelinePresenter.editPhaseTitle)
                FormKitChevron()
            }
        }
        .buttonStyle(.noopPress)
        .formKitGutter()
    }

    /// Captures the candidate, then writes once. A refused write leaves the sheet as it was, with why.
    private func save() {
        let checkpoint = candidate
        saving = true
        Task {
            let result = await model.save(checkpoint)
            saving = false
            switch result {
            case .saved: dismiss()
            case .invalid(let issue):
                refusal = CheckpointTimelinePresenter.sheetIssueText(issue, checkpoint: checkpoint,
                                                                     phases: model.phasesForChecks, unitSystem: unitSystem,
                                                                     locale: AppLanguage.activeLocale)
                    ?? NiggleLogPresenter.couldNotSave
            case .limitReached, .needsAttention: refusal = NiggleLogPresenter.couldNotSave
            }
        }
    }

    private func delete() {
        guard let id = editing?.id else { return }
        Task {
            await model.delete(checkpointId: id)
            dismiss()
        }
    }
}
