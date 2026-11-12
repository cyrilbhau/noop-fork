import SwiftUI
import UIKit
import StrandAnalytics
import StrandDesign

// Stage 3 (protein and intake), specification §10.5 and §10.7, combined frames S6 to S10 and
// design round `design/round-s3-intake/` frames E1 to E17: the content of the Intake card in
// Settings. The switch is always drawn; every other row exists only while the flag is on. Which rows
// exist and every sentence come from `IntakePresenter`. No Kotlin twin: iPhone-only (R43).

struct IntakeSettingsSection: View {
    @ObservedObject private var flag = IntakeSettings.flag
    @State private var source: IntakeSourceSetting = .none
    @State private var floorText = ""
    /// The floor text `load()` put in the field: leaving any field writes the floor only when the
    /// owner changed this text, so a calorie edit never rewrites the scorecard rules.
    @State private var loadedFloorText = ""
    @State private var floorMessage: String?
    @State private var lowText = ""
    @State private var highText = ""
    @State private var hardText = ""
    @State private var rangeMessage: String?
    @State private var supplements: [String] = []
    @State private var newSupplement = ""
    @State private var cutoffMinute = IntakeSettings.defaultCutoffMinuteOfDay
    @State private var reminderOn = false
    @State private var reminderDenied = false
    @State private var reminderCaption: String?
    @State private var knownApps: [(id: String, name: String)] = []
    @State private var admitted: Set<String>?
    @FocusState private var focused: Bool

    private let settings = IntakeSettings()

    private var rows: [IntakeSettingsRow] {
        IntakePresenter.settingsRows(flagEnabled: flag.isEnabled, source: source,
                                     knownHealthAppCount: knownApps.count, supplementCount: supplements.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2 + 2) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Divider().overlay(StrandPalette.hairline) }
                self.row(row)
            }
        }
        .onAppear(perform: load)
        .onChangeCompat(of: flag.isEnabled) { _ in load() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshReminderState() }
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func row(_ row: IntakeSettingsRow) -> some View {
        switch row {
        case .featureSwitch:
            Toggle(isOn: Binding(get: { flag.isEnabled }, set: { flagChanged($0) })) {
                Text("Intake").font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
            }
            .toggleStyle(.switch)
            .tint(StrandPalette.accent)
        case .source:
            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                FormRow(label: "Source") {
                    Picker("Source", selection: Binding(get: { source }, set: { sourceChanged($0) })) {
                        ForEach(selectableSources, id: \.self) { option in
                            Text(verbatim: IntakePresenter.sourceName(option)).tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(StrandPalette.accent)
                }
                if let note = IntakePresenter.sourceNoneCaption(flagEnabled: flag.isEnabled, source: source) {
                    caption(note)
                }
            }
        case .proteinFloor:
            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                FormRow(label: "Protein floor") {
                    HStack(spacing: NoopMetrics.space1) {
                        TextField("", text: $floorText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focused)
                            .foregroundStyle(floorMessage == nil ? StrandPalette.textPrimary : NoopTheme.recoveryLow)
                            .onSubmit(saveFloor)
                            .accessibilityLabel(Text("Protein floor"))
                        Text(verbatim: "g").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    }
                }
                if let floorMessage { caption(floorMessage, danger: true) }
            }
        case .calorieRange:
            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                FormRow(label: "Calorie range") {
                    HStack(spacing: NoopMetrics.space1) {
                        numberField($lowText)
                        Text(verbatim: "–").foregroundStyle(StrandPalette.textTertiary)
                        numberField($highText)
                        Text(verbatim: "kcal").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    }
                }
                if let rangeMessage { caption(rangeMessage, danger: true) }
            }
        case .hardFloor:
            FormRow(label: "Hard floor") {
                HStack(spacing: NoopMetrics.space1) {
                    numberField($hardText)
                    Text(verbatim: "kcal").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
            }
        case .appsToCount:
            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                Text("Apps to count").font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                ForEach(knownApps, id: \.id) { app in
                    Toggle(isOn: Binding(get: { admitted?.contains(app.id) ?? true },
                                         set: { appChanged(app.id, $0) })) {
                        Text(verbatim: app.name).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                    }
                    .toggleStyle(.switch)
                    .tint(StrandPalette.accent)
                }
            }
        case .supplements:
            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                Text("Supplements").font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                ForEach(supplements, id: \.self) { question in
                    HStack {
                        Text(verbatim: IntakePresenter.supplementName(question: question))
                            .font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                        Spacer()
                        Button { removeSupplement(question) } label: {
                            Image(systemName: "minus.circle").foregroundStyle(StrandPalette.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: IntakePresenter.supplementName(question: question)))
                    }
                }
                caption(IntakePresenter.supplementsCaption)
            }
        case .addSupplement:
            HStack {
                TextField("Add a supplement", text: $newSupplement)
                    .font(StrandFont.subhead)
                    .onSubmit(addSupplement)
                Button(action: addSupplement) { Image(systemName: "plus.circle") }
                    .disabled(newSupplement.trimmingCharacters(in: .whitespaces).isEmpty)
                    .tint(StrandPalette.accent)
                    .accessibilityLabel(Text("Add a supplement"))
            }
        case .cutoffTime:
            FormRow(label: "Cutoff time") {
                DatePicker("Cutoff time", selection: Binding(
                    get: {
                        Calendar.current.date(bySettingHour: cutoffMinute / 60, minute: cutoffMinute % 60,
                                              second: 0, of: Date()) ?? Date()
                    },
                    set: { picked in
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: picked)
                        cutoffChanged((parts.hour ?? 21) * 60 + (parts.minute ?? 0))
                    }), displayedComponents: .hourAndMinute)
                .labelsHidden()
                .tint(StrandPalette.accent)
            }
        case .cutoffReminder:
            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                Toggle(isOn: Binding(get: { reminderOn }, set: { reminderChanged($0) })) {
                    Text("Cutoff reminder").font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                }
                .toggleStyle(.switch)
                .tint(StrandPalette.accent)
                caption(IntakePresenter.cutoffReminderNote(isOn: reminderOn))
                if reminderOn, let reminderCaption { caption(reminderCaption) }
                if reminderDenied {
                    Text("Notifications are off for NOOP").font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                    caption(String(localized: "The reminder cannot be delivered until they are allowed."))
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .font(StrandFont.subhead)
                    .tint(StrandPalette.accent)
                }
            }
        }
    }

    private var selectableSources: [IntakeSourceSetting] {
        IntakeSettings.appleHealthReadAvailable ? [.none, .appleHealth, .quickAdd] : [.none, .quickAdd]
    }

    private func numberField(_ text: Binding<String>) -> some View {
        TextField("", text: text)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(minWidth: 56)
            .focused($focused)
            .foregroundStyle(rangeMessage == nil ? StrandPalette.textPrimary : NoopTheme.recoveryLow)
            .onSubmit(saveRange)
            .onChangeCompat(of: focused) { if !$0 { saveRange(); saveFloor() } }
    }

    private func caption(_ text: String, danger: Bool = false) -> some View {
        Text(verbatim: text)
            .font(StrandFont.caption)
            .foregroundStyle(danger ? NoopTheme.recoveryLow : StrandPalette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: State

    private func load() {
        source = settings.source
        let stored = settings.proteinFloorGrams
        floorText = stored.flatMap { Int(exactly: $0) }.map(String.init) ?? ""
        // A stored floor an editor would refuse (a hand-edited value above stage 1's maximum) opens
        // marked until a floor in range is typed.
        floorMessage = stored.map { CutScorecardSettings.isWholeGramProteinFloor($0) } == false
            ? IntakePresenter.refusedFloorMessage : nil
        loadedFloorText = floorText
        // Unusable stored rules are repaired in the rules sheet; this field writes nothing over them.
        if settings.floorRulesNeedAttention { floorMessage = IntakePresenter.rulesNeedAttention }
        let targets = settings.storedTargets
        lowText = targets?.energyLowKcal.map(IntakePresenter.editableAmountText) ?? ""
        highText = targets?.energyHighKcal.map(IntakePresenter.editableAmountText) ?? ""
        hardText = targets?.energyHardFloorKcal.map(IntakePresenter.editableAmountText) ?? ""
        rangeMessage = settings.targetsNeedAttention ? IntakePresenter.targetsNeedAttention : nil
        supplements = settings.supplementQuestions
        cutoffMinute = settings.cutoffMinuteOfDay
        reminderOn = settings.cutoffEnabled
        knownApps = settings.knownHealthSources.map { (id: $0.key, name: $0.value.name) }.sorted { $0.name < $1.name }
        admitted = settings.admittedHealthSources
        reminderCaption = IntakePresenter.cutoffReminderCaption(IntakeCutoffReminder.live.plannedTriggers)
    }

    private func flagChanged(_ on: Bool) {
        IntakeSettings.flag.set(on)
        Task {
            // Off: the reminder's requests go and the widget draws "Set up in NOOP".
            await IntakeCutoffReminder.live.reconcile()
            if !on { WidgetSnapshot.publishIntake(nil) }
        }
        load()
    }

    private func sourceChanged(_ new: IntakeSourceSetting) {
        settings.source = new
        source = new
    }

    private func saveFloor() {
        guard floorText != loadedFloorText else { return }
        let refused = settings.floorRulesNeedAttention ? IntakePresenter.rulesNeedAttention : IntakePresenter.refusedFloorMessage
        switch IntakePresenter.floorEntry(floorText) {
        case .noFloor:
            floorMessage = settings.setProteinFloorGrams(nil) ? nil : refused
        case .grams(let grams):
            floorMessage = settings.setProteinFloorGrams(grams) ? nil : refused
        case .invalid(let message):
            floorMessage = message
        }
        if floorMessage == nil { loadedFloorText = floorText }
    }

    private func saveRange() {
        switch IntakePresenter.rangeEntry(low: lowText, high: highText, hardFloor: hardText) {
        case .valid(let targets):
            rangeMessage = settings.setTargets(targets) ? nil : IntakePresenter.targetsNeedAttention
        case .invalid:
            rangeMessage = IntakePresenter.rangeMessage(low: lowText, high: highText, hardFloor: hardText)
        }
    }

    private func appChanged(_ id: String, _ on: Bool) {
        var set = admitted ?? Set(knownApps.map(\.id))
        if on { set.insert(id) } else { set.remove(id) }
        let everyApp = Set(knownApps.map(\.id))
        settings.admittedHealthSources = set == everyApp ? nil : set
        admitted = settings.admittedHealthSources
    }

    private func addSupplement() {
        let name = newSupplement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let repository = AppModel.shared?.repo else { return }
        IntakeSupplementTick(repository: repository, settings: settings)
            .addSupplement(named: name, catalog: JournalCatalogStore())
        newSupplement = ""
        supplements = settings.supplementQuestions
    }

    private func removeSupplement(_ question: String) {
        settings.removeSupplementQuestion(question)
        supplements = settings.supplementQuestions
    }

    private func cutoffChanged(_ minute: Int) {
        settings.cutoffMinuteOfDay = minute
        settings.cutoffTimeSet = true
        cutoffMinute = settings.cutoffMinuteOfDay
        reminderCaption = IntakePresenter.cutoffReminderCaption(IntakeCutoffReminder.live.plannedTriggers)
        Task { await IntakeCutoffReminder.live.reconcile() }
    }

    private func reminderChanged(_ on: Bool) {
        Task {
            let outcome = await IntakeCutoffReminder.live.setEnabled(on)
            reminderOn = outcome == .scheduled
            reminderDenied = outcome == .denied
            reminderCaption = IntakePresenter.cutoffReminderCaption(IntakeCutoffReminder.live.plannedTriggers)
        }
    }

    private func refreshReminderState() async {
        reminderOn = settings.cutoffEnabled
    }
}
