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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                    Text("Paste your Hevy workout text, then review it before saving. Notes stay on this device.")
                        .font(StrandFont.body)
                    TextEditor(text: $text)
                        .font(StrandFont.body).frame(minHeight: 220)
                        .accessibilityLabel("Workout text")
                        .onChangeCompat(of: text) { _ in preview = nil; message = nil }
                    Button("Preview") {
                        let parsed = WorkoutTextImport.parse(text)
                        preview = parsed
                        if let date = parsed.date { start = date }
                        message = nil
                    }
                    .buttonStyle(NoopButtonStyle(.primary))
                    .disabled(text.isEmpty || text.utf8.count > 1_000_000 || saving)
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
                            .disabled(preview.sets.isEmpty || !preview.warnings.isEmpty || saving)
                    }
                    if let message { Text(message).font(StrandFont.body) }
                }
                .padding(NoopMetrics.screenPadding)
            }
            .background(StrandPalette.surfaceBase)
            .navigationTitle("Paste workout text")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .task { knownWorkouts = await repo.workoutRows(days: 4000) }
        }
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
