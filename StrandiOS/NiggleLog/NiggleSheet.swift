import SwiftUI
import StrandAnalytics
import StrandDesign

// Stage 6 (niggle log), specification §10.4, frames C1 to C10 of `design/round-s6-niggle-timeline/`.
// One sheet to add or edit a complaint or an observation, add an update, or mark a complaint
// resolved. Inputs are captured before the write; a refused save keeps the sheet open with its values
// and says why. Validity is `NiggleDraft`'s and the store's; the sheet decides nothing.

struct NiggleSheet: View {
    enum Mode: Equatable {
        case add
        case edit(StoredNiggle)
        case update(StoredNiggle)
        case resolve(StoredNiggle)
    }

    @ObservedObject var model: NiggleLogModel
    let mode: Mode
    @Environment(\.dismiss) private var dismiss
    @State private var draft: NiggleDraft
    @State private var day: Date
    @State private var trend: NiggleTrend = .notRecorded
    @State private var weakness = false
    @State private var note = ""
    @State private var saving = false
    @State private var refused = false

    private let timeZone = TimeZone.current

    init(model: NiggleLogModel, mode: Mode) {
        self.model = model
        self.mode = mode
        let today = model.today
        switch mode {
        case .add: _draft = State(initialValue: NiggleDraft.new(today: today))
        case .edit(let entry), .update(let entry), .resolve(let entry): _draft = State(initialValue: NiggleDraft(niggle: entry))
        }
        let start: String
        switch mode {
        case .add, .update, .resolve: start = today
        case .edit(let entry): start = entry.onsetDay
        }
        _day = State(initialValue: Stage6DayPicker.date(forDay: start, timeZone: .current) ?? Date())
    }

    private var todayDate: Date { Stage6DayPicker.date(forDay: model.today, timeZone: timeZone) ?? Date() }
    private var onsetDate: Date { Stage6DayPicker.date(forDay: draft.niggle.onsetDay, timeZone: timeZone) ?? todayDate }

    private var canSave: Bool {
        switch mode {
        case .add, .edit: return draft.canSave && !saving
        case .update, .resolve: return !saving
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NoopTheme.Layout.l) {
                    if refused {
                        ScorecardFootnote(text: NiggleLogPresenter.couldNotSave, color: NoopTheme.textPrimary)
                    }
                    switch mode {
                    case .add, .edit: entryFields
                    case .update: updateFields
                    case .resolve: resolveFields
                    }
                }
                .padding(.vertical, NoopTheme.Layout.l)
                .disabled(saving)
                .opacity(saving ? ScorecardLayout.busyOpacity : 1)
            }
            .background(NoopTheme.sheet.ignoresSafeArea())
            .navigationTitle(Text(verbatim: title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel") }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Text("Save") }.disabled(!canSave)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(saving)
    }

    private var title: String {
        switch mode {
        case .add: return NiggleLogPresenter.logNiggleTitle
        case .edit: return NiggleLogPresenter.editTitle
        case .update: return NiggleLogPresenter.addUpdateTitle
        case .resolve: return NiggleLogPresenter.markResolvedTitle
        }
    }

    // MARK: Add and edit

    @ViewBuilder
    private var entryFields: some View {
        let isComplaint = draft.niggle.kind == .complaint
        Stage6FormCard {
            if case .add = mode {
                FormKitControlRow("Kind", showsDivider: false) {
                    Picker(selection: $draft.niggle.kind) {
                        Text("Complaint").tag(StoredNiggle.Kind.complaint)
                        Text("Observation").tag(StoredNiggle.Kind.observation)
                    } label: { Text("Kind") }
                    .pickerStyle(.segmented)
                }
            }
            FormKitControlRow("Location", showsDivider: isAdd) {
                TextField(text: $draft.niggle.location) { Text("Location") }
                    .multilineTextAlignment(.trailing)
                    .noopFont(.body)
            }
            FormKitControlRow("Side") {
                Picker(selection: $draft.niggle.side) {
                    ForEach(StoredNiggle.Side.allCases, id: \.self) { side in
                        Text(verbatim: NiggleLogPresenter.sideText(side)).tag(side)
                    }
                } label: { Text("Side") }
                .pickerStyle(.menu)
                .tint(NoopTheme.textSecondary)
            }
            if isComplaint {
                FormKitControlRow("Character") {
                    Picker(selection: $draft.niggle.character) {
                        ForEach(NiggleCharacter.allCases, id: \.self) { character in
                            Text(verbatim: NiggleLogPresenter.characterText(character)).tag(character)
                        }
                    } label: { Text("Character") }
                    .pickerStyle(.menu)
                    .tint(NoopTheme.textSecondary)
                }
                FormKitControlRow("How it is changing") {
                    trendPicker($draft.niggle.trend)
                }
                FormKitControlRow("Any weakness") {
                    Toggle("", isOn: $draft.niggle.weakness).labelsHidden().tint(NoopTheme.recovery)
                }
            }
            FormKitControlRow(isComplaint ? "Started" : "Noted") {
                DatePicker("", selection: $day, in: ...todayDate, displayedComponents: .date)
                    .labelsHidden()
            }
        }
        if let issue = NiggleLogPresenter.draftIssue(draft), !draft.niggle.location.isEmpty || !isAdd {
            ScorecardFootnote(text: issue)
        }
        noteCard($draft.niggle.note)
    }

    private var isAdd: Bool { if case .add = mode { return true } else { return false } }

    // MARK: Update and resolve

    @ViewBuilder
    private var updateFields: some View {
        Stage6FormCard {
            FormKitControlRow("Date", showsDivider: false) {
                DatePicker("", selection: $day, in: onsetDate...max(onsetDate, todayDate), displayedComponents: .date)
                    .labelsHidden()
            }
            FormKitControlRow("How it is changing") { trendPicker($trend) }
            FormKitControlRow("Any weakness") {
                Toggle("", isOn: $weakness).labelsHidden().tint(NoopTheme.recovery)
            }
        }
        noteCard($note)
    }

    private var resolveFields: some View {
        Stage6FormCard {
            FormKitControlRow("Resolved on", showsDivider: false) {
                DatePicker("", selection: $day, in: onsetDate...max(onsetDate, todayDate), displayedComponents: .date)
                    .labelsHidden()
            }
        }
    }

    // MARK: Pieces

    private func trendPicker(_ selection: Binding<NiggleTrend>) -> some View {
        Picker(selection: selection) {
            ForEach(NiggleTrend.allCases, id: \.self) { trend in
                Text(verbatim: NiggleLogPresenter.trendText(trend)).tag(trend)
            }
        } label: { Text("How it is changing") }
        .pickerStyle(.menu)
        .tint(NoopTheme.textSecondary)
    }

    private func noteCard(_ text: Binding<String>) -> some View {
        FormKitCard {
            TextField(text: text, axis: .vertical) { Text("Note") }
                .lineLimit(3...8)
                .noopFont(.body)
                .padding(.vertical, FormKitLayout.rowVertical)
                .padding(.horizontal, NoopTheme.Layout.rowHorizontalPadding)
        }
    }

    /// Captures every input, then writes once. A refused write leaves the sheet as it was.
    private func save() {
        let picked = Stage6DayPicker.day(for: day, timeZone: timeZone)
        var entry = draft.niggle
        let mode = mode
        let trend = trend, weakness = weakness, note = note
        saving = true
        Task {
            let saved: Bool
            switch mode {
            case .add, .edit:
                entry.onsetDay = picked
                saved = await model.save(entry)
            case .update(let stored):
                saved = await model.addUpdate(niggleId: stored.id, day: picked, trend: trend, weakness: weakness, note: note)
            case .resolve(let stored):
                saved = await model.resolve(niggleId: stored.id, on: picked)
            }
            saving = false
            if saved { dismiss() } else { refused = true }
        }
    }
}
