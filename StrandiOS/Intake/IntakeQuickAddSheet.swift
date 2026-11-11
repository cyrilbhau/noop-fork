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
                        Text(verbatim: IntakeDayText.label(key, today: days.first ?? key)).tag(key)
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
        day = days.first ?? ""
        if case .edit(let entry) = mode {
            proteinText = entry.proteinGrams.map(Self.text) ?? ""
            energyText = entry.energyKcal.map(Self.text) ?? ""
            label = entry.label ?? ""
        }
    }

    private static func text(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }

    private func apply(_ preset: IntakeSettings.Preset) {
        proteinText = preset.proteinGrams.map(Self.text) ?? ""
        energyText = preset.energyKcal.map(Self.text) ?? ""
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
                try await store.add(proteinGrams: amount(protein), energyKcal: amount(energy),
                                    label: label.isEmpty ? nil : label, at: IntakeDayText.instant(for: day))
            case .edit(var entry):
                entry.proteinGrams = amount(protein)
                entry.energyKcal = amount(energy)
                entry.label = label.isEmpty ? nil : label
                try await store.update(entry)
            case .restored:
                // The screen offers the restored total of the day it shows, today.
                try await store.replaceRestoredTotal(day: days.first ?? day)
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

/// The backdating picker's words and instants.
enum IntakeDayText {
    /// "Today", or the day's short date.
    static func label(_ day: String, today: String) -> String {
        if day == today { return String(localized: "Today") }
        guard let date = instant(forKey: day) else { return day }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(AppClock.formattingLocale))
    }

    /// The instant an entry is logged at: now for today, noon of the day otherwise, so that a
    /// backdated entry falls inside its day in the phone's zone.
    static func instant(for day: String, now: Date = Date()) -> Date {
        guard day != Repository.localDayKey(now), let noon = instant(forKey: day) else { return now }
        return noon
    }

    private static func instant(forKey day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
}
