import SwiftUI
import StrandDesign
import StrandImport
import WhoopStore

struct WorkoutTextImportSheet: View {
    var onImported: () async -> Void
    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var preview: WorkoutTextImport.Preview?
    @State private var start = Date()
    @State private var addDuration = false
    @State private var minutes = 60
    @State private var saving = false
    @State private var message: String?
    @State private var knownWorkouts: [WorkoutRow] = []

    private var matchedWorkout: WorkoutRow? {
        let matches = knownWorkouts.filter {
            WorkoutSource.sportKey($0.sport) == WorkoutSource.sportKey(LiftingImporter.sport)
                && abs(Double($0.startTs) - start.timeIntervalSince1970) <= 120 && $0.endTs > $0.startTs
        }
        return matches.count == 1 ? matches.first : nil
    }

    #if os(iOS)
    /// The iPhone redesign (B4) restyles this sheet unless the user chose the classic look.
    @AppStorage(NoopTheme.Keys.redesignEnabled) private var redesignEnabled = true
    @AppStorage(NoopTheme.Keys.ambientIntensity) private var ambientIntensityRaw = AmbientIntensity.balanced.rawValue
    #endif

    var body: some View {
        NavigationStack {
            Group {
                #if os(iOS)
                if redesignEnabled { redesignForm } else { classicForm }
                #else
                classicForm
                #endif
            }
            .navigationTitle("Paste workout text")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .task { knownWorkouts = await repo.workoutRows(days: 4000) }
        }
    }

    /// The classic layout (macOS, and iPhone with the redesign off).
    private var classicForm: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                    Text("Paste your Hevy workout text, then review it before saving. Notes stay on this device.")
                        .font(StrandFont.body)
                    TextEditor(text: $text)
                        .font(StrandFont.body).frame(minHeight: 220)
                        .accessibilityLabel("Workout text")
                        .onChangeCompat(of: text) { _ in preview = nil; message = nil }
                    Button("Preview") { runPreview() }
                    .buttonStyle(NoopButtonStyle(.primary))
                    .disabled(previewDisabled)
                    if let preview {
                        previewCard(preview)
                        DatePicker("Start", selection: $start)
                        if let matchedWorkout {
                            Text("Matched workout duration: \(Int((matchedWorkout.endTs - matchedWorkout.startTs) / 60)) min")
                                .font(StrandFont.caption)
                        } else {
                            Toggle("Add duration", isOn: $addDuration)
                            if addDuration { Stepper("\(minutes) min", value: $minutes, in: 1...1440) }
                            else { Text("Duration not provided").font(StrandFont.caption) }
                        }
                        Button("Save workout") { Task { await save(preview) } }
                            .buttonStyle(NoopButtonStyle(.primary))
                            .disabled(saveDisabled(preview))
                    }
                    if let message { Text(message).font(StrandFont.body) }
                }
                .padding(NoopMetrics.screenPadding)
            }
            .background(StrandPalette.surfaceBase)
    }

    /// Parse the pasted text for review. Both layouts call this, so the preview step is one code path.
    private func runPreview() {
        let parsed = WorkoutTextImport.parse(text)
        preview = parsed
        if let date = parsed.date { start = date }
        message = nil
    }

    private var previewDisabled: Bool { text.isEmpty || text.utf8.count > 1_000_000 || saving }

    /// Saving is blocked until there are sets and no unrecognised set line remains.
    private func saveDisabled(_ preview: WorkoutTextImport.Preview) -> Bool {
        preview.sets.isEmpty || !preview.warnings.isEmpty || saving
    }

    private func previewCard(_ preview: WorkoutTextImport.Preview) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                if let title = preview.title { Text(title).font(StrandFont.headline) }
                ForEach(Array(preview.sets.enumerated()), id: \.offset) { _, set in
                    VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                        Text(set.exercise).font(StrandFont.subhead)
                        Text("\(set.setIndex): \(set.weightKg.map { LiftFormat.trim($0) + " kg" } ?? "—") × \(set.reps.map(String.init) ?? "—")")
                            .font(StrandFont.body)
                        if let note = set.note { Text(note).font(StrandFont.caption) }
                    }
                }
                ForEach(preview.unquantifiedExercises, id: \.self) { name in
                    Text("\(name): no set details provided").font(StrandFont.caption)
                }
                if !preview.warnings.isEmpty {
                    Text("Check these set lines before saving:").foregroundStyle(StrandPalette.statusWarning)
                    ForEach(Array(preview.warnings.enumerated()), id: \.offset) { _, line in Text(line) }
                }
                if preview.sets.isEmpty { Text("No sets found. Use lines like Set 1: 20 kg x 10 under an exercise name.") }
            }
        }
    }

    private func save(_ preview: WorkoutTextImport.Preview) async {
        guard let store = await repo.storeHandle() else { return }
        saving = true
        defer { saving = false }
        let actualStart = matchedWorkout.map { Date(timeIntervalSince1970: Double($0.startTs)) } ?? start
        let end = matchedWorkout.map { Date(timeIntervalSince1970: Double($0.endTs)) }
            ?? (addDuration ? actualStart.addingTimeInterval(Double(minutes * 60)) : nil)
        do {
            let added = try await PersonalLiftingImport.save(preview.session(start: actualStart, end: end), store: store)
            await onImported()
            if added { dismiss() }
            else { message = String(localized: "This workout already has lifting details. Open it in Lift Log to review or edit it.") }
        } catch {
            message = String(localized: "Couldn't save the workout. Your existing log is unchanged.")
        }
    }
}

// MARK: - iPhone redesign (B4)
//
// `design/round3/training.html` B4. The same steps as the classic sheet, in the same order: paste, Preview
// (`runPreview`, the one parser call), review every parsed set, set the start and optional duration, then
// Save (`save`, unchanged). A missing duration is an amber card; unrecognised set lines carry warn icons
// and still block saving.

#if os(iOS)
extension WorkoutTextImportSheet {
    var redesignForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.cardGap) {
                Text("Paste your Hevy workout text, then review it before saving. Notes stay on this device.")
                    .noopFont(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, NoopTheme.Layout.xs)
                NoopGlassCard {
                    VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                        Text("Workout text").noopFont(.rowTitle)
                        TextEditor(text: $text)
                            .noopFont(.bodySmall, color: false)
                            .monospaced()
                            .foregroundStyle(NoopTheme.textSecondary)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: TrainingLayout.editorMinHeight)
                            .accessibilityLabel("Workout text")
                            .onChangeCompat(of: text) { _ in preview = nil; message = nil }
                    }
                }
                Button("Preview") { runPreview() }
                    .buttonStyle(NoopSecondaryButton())
                    .disabled(previewDisabled)
                if let preview {
                    if matchedWorkout == nil && !addDuration {
                        TrainingWarningCard(title: "Duration not provided",
                                            message: "It will save without a duration. Nothing is guessed.")
                    }
                    rdPreviewList(preview)
                    rdTimingCard
                    Text("Saves to Lift Log on this iPhone. Your Strain and Recovery formulas don't change.")
                        .noopFont(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, NoopTheme.Layout.xs)
                    Button("Save workout") { Task { await save(preview) } }
                        .buttonStyle(NoopPrimaryButton())
                        .disabled(saveDisabled(preview))
                }
                if let message {
                    Text(message).noopFont(.bodySmall)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, NoopTheme.Layout.gutter)
            .padding(.vertical, NoopTheme.Layout.l)
        }
        .trainingAmbient(.pasteWorkout, intensityRaw: ambientIntensityRaw)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    /// Exercises in the order they were pasted, each with every parsed set.
    private func rdGroups(_ preview: WorkoutTextImport.Preview) -> [(exercise: String, sets: [ImportedLiftSet])] {
        var order: [String] = []
        var grouped: [String: [ImportedLiftSet]] = [:]
        for set in preview.sets {
            if grouped[set.exercise] == nil { order.append(set.exercise) }
            grouped[set.exercise, default: []].append(set)
        }
        return order.map { ($0, grouped[$0] ?? []) }
    }

    private func rdPreviewList(_ preview: WorkoutTextImport.Preview) -> some View {
        let groups = rdGroups(preview)
        let summary = String(localized: "\(groups.count) exercises · \(preview.sets.count) sets")
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Preview").noopFont(.sectionTitle).accessibilityAddTraits(.isHeader)
                Spacer(minLength: NoopTheme.Layout.s)
                Text(verbatim: summary).noopFont(.footnote)
            }
            .padding(.top, NoopTheme.Layout.m)
            .padding(.bottom, NoopTheme.Layout.sectionBottom)
            .padding(.horizontal, NoopTheme.Layout.xs)
            NoopGlassCard(flush: true) {
                VStack(alignment: .leading, spacing: 0) {
                    if let title = preview.title {
                        // The pasted title is data.
                        Text(verbatim: title).noopFont(.listTitle)
                            .padding(.vertical, NoopTheme.Layout.m)
                    }
                    ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                        if index > 0 || preview.title != nil { TrainingDivider() }
                        rdExerciseRow(group.exercise, sets: group.sets)
                    }
                    ForEach(preview.unquantifiedExercises, id: \.self) { name in
                        TrainingDivider()
                        rdStatusRow(icon: "minus", tint: NoopTheme.textSecondary,
                                    title: name, detail: String(localized: "\(name): no set details provided"))
                    }
                    if !preview.warnings.isEmpty {
                        TrainingDivider()
                        Text("Check these set lines before saving:")
                            .noopFont(.footnote, color: false)
                            .foregroundStyle(NoopTheme.recoveryMid)
                            .padding(.top, NoopTheme.Layout.m)
                        ForEach(Array(preview.warnings.enumerated()), id: \.offset) { _, line in
                            rdStatusRow(icon: "exclamationmark.triangle.fill", tint: NoopTheme.recoveryMid,
                                        title: line, detail: nil)
                        }
                    }
                    if preview.sets.isEmpty {
                        TrainingDivider()
                        Text("No sets found. Use lines like Set 1: 20 kg x 10 under an exercise name.")
                            .noopFont(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, NoopTheme.Layout.m)
                    }
                }
            }
        }
    }

    /// One exercise: a tick, its name, and every set exactly as parsed (weights as logged, never doubled).
    private func rdExerciseRow(_ exercise: String, sets: [ImportedLiftSet]) -> some View {
        HStack(alignment: .top, spacing: NoopTheme.Layout.m) {
            DomainIcon(systemImage: "checkmark", color: NoopTheme.recovery, size: DomainIcon.smallSize)
            VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
                Text(verbatim: exercise).noopFont(.listTitle)
                ForEach(Array(sets.enumerated()), id: \.offset) { _, set in
                    Text("\(set.setIndex): \(set.weightKg.map { LiftFormat.trim($0) + " kg" } ?? "—") × \(set.reps.map(String.init) ?? "—")")
                        .noopFont(.footnote)
                    if let note = set.note { Text(verbatim: note).noopFont(.caption) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, NoopTheme.Layout.m)
        .accessibilityElement(children: .combine)
    }

    private func rdStatusRow(icon: String, tint: Color, title: String, detail: String?) -> some View {
        HStack(alignment: .top, spacing: NoopTheme.Layout.m) {
            DomainIcon(systemImage: icon, color: tint, size: DomainIcon.smallSize)
            VStack(alignment: .leading, spacing: NoopTheme.Layout.xs / 2) {
                Text(verbatim: title).noopFont(.listTitle)
                if let detail { Text(verbatim: detail).noopFont(.footnote) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, NoopTheme.Layout.m)
        .accessibilityElement(children: .combine)
    }

    /// Start time and the optional duration, the same controls as the classic sheet.
    private var rdTimingCard: some View {
        NoopGlassCard {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
                DatePicker("Start", selection: $start)
                    .noopFont(.bodySmall)
                if let matchedWorkout {
                    Text("Matched workout duration: \(Int((matchedWorkout.endTs - matchedWorkout.startTs) / 60)) min")
                        .noopFont(.footnote)
                } else {
                    Toggle("Add duration", isOn: $addDuration)
                        .noopFont(.bodySmall)
                    if addDuration {
                        Stepper("\(minutes) min", value: $minutes, in: 1...1440)
                            .noopFont(.bodySmall)
                    }
                }
            }
        }
    }
}
#endif
