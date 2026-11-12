import SwiftUI
import StrandAnalytics
import StrandDesign

// Stage 6 (niggle log), specification §10.5, frames D1 to D8 of `design/round-s6-niggle-timeline/`.
// The owner's rule for seeing a professional, in their own words, and their own triage rules, each
// read back as a sentence. The app ships no rule: the sheet starts empty (decision D3). Order breaks
// ties only between rules with the same action, and the sheet says so.

struct NiggleRulesSheet: View {
    @ObservedObject var model: NiggleLogModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TriageRulesDraft
    @State private var editing: Int?
    @State private var asksDelete: Int?
    @State private var saving = false
    @State private var refused = false

    init(model: NiggleLogModel, editing: Int? = nil) {
        self.model = model
        _draft = State(initialValue: TriageRulesDraft(rules: model.rules))
        _editing = State(initialValue: editing)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(text: $draft.rules.professionalRule, axis: .vertical) {
                        Text(verbatim: NiggleLogPresenter.professionalTitle)
                    }
                    .lineLimit(2...6)
                    .noopFont(.body)
                } header: {
                    Text(verbatim: NiggleLogPresenter.professionalTitle)
                } footer: {
                    Text(verbatim: NiggleLogPresenter.professionalRuleCaption)
                }
                Section {
                    ForEach(Array(draft.rules.rules.enumerated()), id: \.offset) { index, rule in
                        Button { editing = index } label: {
                            VStack(alignment: .leading, spacing: FormKitLayout.detailGap) {
                                Text(verbatim: rule.label.isEmpty ? NiggleLogPresenter.ruleTitle : rule.label)
                                    .noopFont(.listTitle)
                                Text(verbatim: NiggleLogPresenter.actionText(rule.action, locale: AppLanguage.activeLocale))
                                    .noopFont(.footnote)
                                Text(verbatim: NiggleLogPresenter.rulePreview(rule, locale: AppLanguage.activeLocale))
                                    .noopFont(.footnote)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let issue = NiggleLogPresenter.ruleIssue(rule) {
                                    Text(verbatim: issue).noopFont(.footnote, color: false)
                                        .foregroundStyle(NoopTheme.recoveryLow)
                                }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) { asksDelete = index } label: {
                                Label { Text(verbatim: NiggleLogPresenter.deleteTitle) } icon: { Image(systemName: "trash") }
                            }
                        }
                    }
                    .onMove { from, to in draft.rules.rules.move(fromOffsets: from, toOffset: to) }
                    Button {
                        draft.rules.rules.append(TriageRulesDraft.newRule())
                        editing = draft.rules.rules.count - 1
                    } label: { Text(verbatim: NiggleLogPresenter.addRuleTitle) }
                    .disabled(!draft.canAddRule)
                } footer: {
                    VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
                        Text(verbatim: NiggleLogPresenter.tieNote)
                        if !draft.canAddRule { Text(verbatim: NiggleLogPresenter.rulesLimitText) }
                        if refused { Text(verbatim: NiggleLogPresenter.couldNotSave) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(NoopTheme.sheet.ignoresSafeArea())
            .environment(\.editMode, .constant(.active))
            .navigationTitle(Text(verbatim: NiggleLogPresenter.rulesTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel") }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Text("Save") }.disabled(!draft.canSave || saving)
                }
            }
            .sheet(item: Binding(get: { editing.map(RuleIndex.init) }, set: { editing = $0?.index })) { which in
                if draft.rules.rules.indices.contains(which.index) {
                    NiggleRuleEditor(rule: $draft.rules.rules[which.index])
                }
            }
            .confirmationDialog(Text(verbatim: NiggleLogPresenter.deleteRuleTitle),
                                isPresented: Binding(get: { asksDelete != nil }, set: { if !$0 { asksDelete = nil } }),
                                titleVisibility: .visible) {
                Button(role: .destructive) {
                    if let index = asksDelete, draft.rules.rules.indices.contains(index) {
                        draft.rules.rules.remove(at: index)
                    }
                } label: { Text(verbatim: NiggleLogPresenter.deleteTitle) }
                Button(role: .cancel) {} label: { Text("Cancel") }
            } message: {
                Text(verbatim: NiggleLogPresenter.deleteRuleDetail)
            }
        }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(saving)
    }

    private struct RuleIndex: Identifiable {
        let index: Int
        var id: Int { index }
    }

    private func save() {
        let rules = draft.rules
        saving = true
        Task {
            let saved = await model.saveRules(rules)
            saving = false
            if saved { dismiss() } else { refused = true }
        }
    }
}

/// One rule's fields (§10.5): label, action, characters, changes, weakness, from day, through day, note.
private struct NiggleRuleEditor: View {
    @Binding var rule: StoredTriageRule
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(text: $rule.label) { Text("Label") }
                    Picker(selection: $rule.action) {
                        ForEach(NiggleAction.allCases, id: \.self) { action in
                            Text(verbatim: NiggleLogPresenter.actionText(action, locale: AppLanguage.activeLocale)).tag(action)
                        }
                    } label: { Text("Action") }
                }
                Section {
                    ForEach(NiggleCharacter.allCases, id: \.self) { character in
                        Toggle(isOn: membership(character, in: $rule.characters)) {
                            Text(verbatim: NiggleLogPresenter.characterText(character))
                        }
                    }
                } header: { Text("Which complaints") }
                Section {
                    ForEach(NiggleTrend.allCases, id: \.self) { trend in
                        Toggle(isOn: membership(trend, in: $rule.trends)) {
                            Text(verbatim: NiggleLogPresenter.trendText(trend))
                        }
                    }
                } header: { Text("Which changes") }
                Section {
                    Picker(selection: $rule.weakness) {
                        Text("Either").tag(Bool?.none)
                        Text("With").tag(Bool?.some(true))
                        Text("Without").tag(Bool?.some(false))
                    } label: { Text("Weakness") }
                    Stepper(value: Binding(get: { rule.fromDay ?? 1 }, set: { rule.fromDay = $0 }), in: 1...3650) {
                        HStack {
                            Text("From day")
                            Spacer()
                            Text(verbatim: "\(rule.fromDay ?? 1)").monospacedDigit()
                        }
                    }
                    Toggle(isOn: Binding(get: { rule.throughDay != nil },
                                         set: { rule.throughDay = $0 ? max(rule.fromDay ?? 1, 1) : nil })) {
                        Text("Through day")
                    }
                    if let through = rule.throughDay {
                        Stepper(value: Binding(get: { through }, set: { rule.throughDay = $0 }),
                                in: max(rule.fromDay ?? 1, 1)...3650) {
                            Text(verbatim: "\(through)").monospacedDigit()
                        }
                    }
                }
                Section {
                    TextField(text: $rule.note, axis: .vertical) { Text("Note") }.lineLimit(2...5)
                } footer: {
                    VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
                        Text(verbatim: NiggleLogPresenter.rulePreview(rule, locale: AppLanguage.activeLocale))
                        if let issue = NiggleLogPresenter.ruleIssue(rule) { Text(verbatim: issue) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(NoopTheme.sheet.ignoresSafeArea())
            .navigationTitle(Text(verbatim: NiggleLogPresenter.ruleTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done") }
                }
            }
        }
    }

    /// A switch per value of a multi-select: on adds it, off removes every copy of it.
    private func membership<T: Equatable>(_ value: T, in list: Binding<[T]>) -> Binding<Bool> {
        Binding(get: { list.wrappedValue.contains(value) },
                set: { on in
                    if on { if !list.wrappedValue.contains(value) { list.wrappedValue.append(value) } }
                    else { list.wrappedValue.removeAll { $0 == value } }
                })
    }
}
