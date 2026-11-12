import SwiftUI
import StrandAnalytics
import StrandDesign

// Stage 5 (events layer), specification §10.3, frames S1 to S18 of `design/round-s5-events/`. One
// sheet for add and edit: kind, start, length (one day, until a date, or ongoing), note and the
// Private switch. The sheet draws `PersonalEventSheetModel` and decides nothing: validity, the
// Private default and the remaining count are the model's.

struct PersonalEventSheet: View {
    @StateObject private var model: PersonalEventSheetModel
    /// Edit only: the owner asked to delete this event. The list asks once and deletes.
    let onDelete: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss
    /// Packet v2 (stage 5 §9.6): the coach packet's flag, for the sentence under the Private switch.
    @ObservedObject private var coachPacketFlag = CoachPacketSettings.flag

    init(model: PersonalEventSheetModel, onDelete: ((String) -> Void)? = nil) {
        _model = StateObject(wrappedValue: model)
        self.onDelete = onDelete
    }

    private var isSaving: Bool { model.phase == .saving }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NoopTheme.Layout.l) {
                    failure
                    kindCard
                    datesCard
                    if model.isPlanned {
                        footnote(Text("Planned: this starts in the future"))
                    }
                    noteCard
                    privateCard
                    footnote(Text("Private events show as \"Private event\" outside this screen."))
                    if coachPacketFlag.isEnabled {
                        footnote(Text("Private events stay out of the coach packet unless you include them in Settings."))
                    }
                    if let editing = model.editing, let onDelete {
                        Button(role: .destructive) { onDelete(editing.id) } label: {
                            Label { Text("Delete") } icon: { Image(systemName: "trash") }
                        }
                        .buttonStyle(ScorecardDangerButton())
                        .formKitGutter()
                        .disabled(isSaving)
                    }
                }
                .padding(.vertical, NoopTheme.Layout.l)
                .disabled(isSaving)
                .opacity(isSaving ? ScorecardLayout.busyOpacity : 1)
            }
            .background(NoopTheme.sheet.ignoresSafeArea())
            .navigationTitle(model.isEditing ? Text("Edit event") : Text("New event"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel") }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { model.save() } label: { Text("Save") }
                        .disabled(!model.canSave)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSaving)
        .onChangeCompat(of: model.phase) { phase in
            if phase == .saved { dismiss() }
        }
    }

    // MARK: Cards

    @ViewBuilder
    private var failure: some View {
        if case .failed(let storeUnreadable) = model.phase {
            NoopGlassCard {
                VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                    if storeUnreadable {
                        Text("Your events could not be read").noopFont(.rowTitle)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Nothing has been changed. You can copy the stored text before starting again.")
                            .noopFont(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                        Button { dismiss() } label: {
                            HStack(spacing: NoopTheme.Layout.xs) {
                                Text("Events")
                                FormKitChevron()
                            }
                        }
                        .buttonStyle(.noopPress)
                    } else {
                        Text("Could not save. Try again.").noopFont(.rowTitle)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .formKitGutter()
        }
    }

    private var kindCard: some View {
        FormKitCard {
            FormKitControlRow("Kind", showsDivider: false) {
                Picker(selection: Binding(get: { model.draft.kind }, set: { model.setKind($0) })) {
                    ForEach(PersonalEventKind.allCases, id: \.self) { kind in
                        Text(verbatim: PersonalEventPresenter.kindName(kind, locale: AppLanguage.activeLocale))
                            .tag(kind)
                    }
                } label: { Text("Kind") }
                .pickerStyle(.menu)
                .tint(NoopTheme.textSecondary)
            }
            .padding(.horizontal, NoopTheme.Layout.rowHorizontalPadding)
            if model.draft.kind == .custom {
                FormKitControlRow("Name") {
                    TextField(text: $model.draft.label,
                              prompt: model.needsName ? Text("A name is needed") : nil) { Text("Name") }
                        .multilineTextAlignment(.trailing)
                        .noopFont(.body)
                }
                .padding(.horizontal, NoopTheme.Layout.rowHorizontalPadding)
            }
        }
    }

    private var datesCard: some View {
        FormKitCard {
            FormKitControlRow("Starts", showsDivider: false) {
                DatePicker(selection: $model.draft.start, displayedComponents: .date) { Text("Starts") }
                    .labelsHidden()
            }
            .padding(.horizontal, NoopTheme.Layout.rowHorizontalPadding)
            VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                FormKitDivider()
                Text("Length").noopFont(.listTitle)
                Picker(selection: $model.draft.length) {
                    Text("One day").tag(PersonalEventDraft.Length.oneDay)
                    Text("Until").tag(PersonalEventDraft.Length.until)
                    Text("Ongoing").tag(PersonalEventDraft.Length.ongoing)
                } label: { Text("Length") }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, NoopTheme.Layout.rowHorizontalPadding)
            .padding(.bottom, FormKitLayout.rowVertical)
            if model.draft.length == .until {
                FormKitControlRow("Ends") {
                    DatePicker(selection: $model.draft.end, displayedComponents: .date) { Text("Ends") }
                        .labelsHidden()
                }
                .padding(.horizontal, NoopTheme.Layout.rowHorizontalPadding)
                if model.endIsBeforeStart {
                    Text("Must be on or after the start")
                        .noopFont(.footnote, color: false)
                        .foregroundStyle(NoopTheme.recoveryLow)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, NoopTheme.Layout.rowHorizontalPadding)
                        .padding(.bottom, FormKitLayout.rowVertical)
                }
            }
        }
    }

    private var noteCard: some View {
        FormKitCard {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                Text("Note").noopFont(.listTitle)
                TextField(text: $model.draft.note, axis: .vertical) { Text("Note") }
                    .lineLimit(3...8)
                    .noopFont(.body)
                if let remaining = model.noteRemaining {
                    Text("\(remaining) left")
                        .noopFont(.footnote)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.vertical, FormKitLayout.rowVertical)
            .padding(.horizontal, NoopTheme.Layout.rowHorizontalPadding)
        }
    }

    private var privateCard: some View {
        FormKitCard {
            FormKitToggleRow("Private", isOn: Binding(get: { model.draft.isPrivate },
                                                      set: { model.setPrivate($0) }),
                             showsDivider: false)
                .padding(.horizontal, NoopTheme.Layout.rowHorizontalPadding)
        }
    }

    private func footnote(_ text: Text) -> some View {
        text
            .noopFont(.footnote)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, NoopTheme.Layout.gutter + NoopTheme.Layout.captionInset)
    }
}
