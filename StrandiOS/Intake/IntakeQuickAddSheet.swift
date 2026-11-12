import SwiftUI
import StrandAnalytics
import StrandDesign

// Stage 3 (protein and intake), specification §10.3 and design round `design/round-s3-intake/`
// frames D1 to D10: add, edit or delete one entry, or replace a restored total. The field states
// and Save's state come from `IntakePresenter`; the sheet decides nothing. No Kotlin twin.

struct IntakeQuickAddSheet: View {
    enum Mode: Identifiable, Equatable {
        case add
        case edit(IntakeEntry)
        case restored

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let entry): return entry.id.uuidString
            case .restored: return "restored"
            }
        }
    }

    let mode: Mode
    let store: IntakeQuickAddStore
    /// Today and the seven days before it, today first.
    let days: [String]
    let presets: [IntakeSettings.Preset]
    /// The day the screen's entries card shows: pre-selected when adding, and the day whose restored
    /// total is replaced. Nil: today.
    var shownDay: String? = nil
    let onChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var proteinText = ""
    @State private var energyText = ""
    @State private var label = ""
    @State private var day = ""
    @State private var failed = false
    @State private var saving = false

    private var protein: IntakeAmountEntry { IntakePresenter.amountEntry(proteinText) }
    private var energy: IntakeAmountEntry { IntakePresenter.amountEntry(energyText) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NoopTheme.Layout.cardGap) {
                    if mode == .restored {
                        NoopGlassCard {
                            Text("Restored total")
                                .noopFont(.bodySmall)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        fields
                        if case .add = mode { presetChips; dayPicker }
                    }
                    if failed {
                        Text(verbatim: IntakePresenter.quickAddSaveFailed)
                            .noopFont(.footnote, color: false)
                            .foregroundStyle(NoopTheme.recoveryLow)
                    }
                    if case .edit(let entry) = mode {
                        Button(role: .destructive) { Task { await delete(entry) } } label: {
                            Text("Delete entry").frame(maxWidth: .infinity)
                        }
                        .noopFont(.button, color: false)
                        .foregroundStyle(NoopTheme.recoveryLow)
                    }
                }
                .padding(NoopTheme.Layout.gutter)
            }
            .background(NoopTheme.canvas.ignoresSafeArea())
            .navigationTitle(Text(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .restored ? "Replace" : "Save") { Task { await save() } }
                        .disabled(saving || (mode != .restored
                                             && !IntakePresenter.canSaveQuickAdd(protein: protein, energy: energy)))
                }
            }
            .onAppear(perform: fill)
        }
    }

    private var title: LocalizedStringKey {
        switch mode {
        case .add: return "Add food"
        case .edit: return "Edit entry"
        case .restored: return "Restored total"
        }
    }

    private var fields: some View {
        NoopGlassCard {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
                amountField("Protein", unit: "g", text: $proteinText, entry: protein)
                amountField("Calories", unit: "kcal", text: $energyText, entry: energy)
                TextField("Label (optional)", text: $label)
                    .noopFont(.body)
                    .textInputAutocapitalization(.sentences)
            }
        }
    }

    private func amountField(_ title: LocalizedStringKey, unit: String, text: Binding<String>,
                             entry: IntakeAmountEntry) -> some View {
        VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
            HStack {
                Text(title).noopFont(.bodySmall)
                Spacer()
                TextField("", text: text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .noopFont(.rowNumber, color: false)
                    .foregroundStyle(isInvalid(entry) ? NoopTheme.recoveryLow : NoopTheme.textPrimary)
                    .accessibilityLabel(Text(title))
                Text(verbatim: unit).noopFont(.unit)
            }
            if case .invalid(let message) = entry {
                Text(verbatim: message)
                    .noopFont(.footnote, color: false)
                    .foregroundStyle(NoopTheme.recoveryLow)
            }
        }
    }

    private func isInvalid(_ entry: IntakeAmountEntry) -> Bool {
        if case .invalid = entry { return true }
        return false
    }

    @ViewBuilder
    private var presetChips: some View {
        VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
            Text("Presets").noopFont(.footnote)
            if presets.isEmpty {
                Text("Add a preset").noopFont(.footnote)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: NoopTheme.Layout.s) {
                        ForEach(Array(presets.enumerated()), id: \.offset) { _, preset in
                            Button { apply(preset) } label: { NoopChip(verbatim: preset.label) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var dayPicker: some View {
        NoopGlassCard {
            HStack {
                Text("Day").noopFont(.bodySmall)
                Spacer()
                Picker("Day", selection: $day) {
                    ForEach(days, id: \.self) { key in
                        Text(verbatim: IntakePresenter.dayLabel(key, today: days.first ?? key, timeZone: .current,
                                                                locale: AppClock.formattingLocale)).tag(key)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(NoopTheme.textPrimary)
            }
        }
    }

    // MARK: Actions

    private func fill() {
        day = shownDay.flatMap { days.contains($0) ? $0 : nil } ?? days.first ?? ""
        if case .edit(let entry) = mode {
            proteinText = entry.proteinGrams.map(IntakePresenter.editableAmountText) ?? ""
            energyText = entry.energyKcal.map(IntakePresenter.editableAmountText) ?? ""
            label = entry.label ?? ""
        }
    }

    private func apply(_ preset: IntakeSettings.Preset) {
        proteinText = preset.proteinGrams.map(IntakePresenter.editableAmountText) ?? ""
        energyText = preset.energyKcal.map(IntakePresenter.editableAmountText) ?? ""
        label = preset.label
    }

    private func amount(_ entry: IntakeAmountEntry) -> Double? {
        if case .amount(let value) = entry { return value }
        return nil
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            switch mode {
            case .add:
                // "Today" is logged now, on the real current day; another day inside that day under
                // the zone log.
                try await store.add(proteinGrams: amount(protein), energyKcal: amount(energy),
                                    label: label.isEmpty ? nil : label, on: day, today: days.first ?? day)
            case .edit(var entry):
                entry.proteinGrams = amount(protein)
                entry.energyKcal = amount(energy)
                entry.label = label.isEmpty ? nil : label
                try await store.update(entry)
            case .restored:
                // The screen offers the restored total of the day its entries card shows.
                try await store.replaceRestoredTotal(day: shownDay ?? days.first ?? day)
            }
            onChange()
            dismiss()
        } catch {
            failed = true
        }
    }

    private func delete(_ entry: IntakeEntry) async {
        do {
            try await store.delete(id: entry.id, day: entry.day)
            onChange()
            dismiss()
        } catch {
            failed = true
        }
    }
}
