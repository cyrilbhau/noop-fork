#if os(iOS)
import SwiftUI
import StrandDesign

/// What the B6 add sheet asked for. The Training hub runs it after the sheet has dismissed, routing each
/// to an existing flow (`TrainingHubView.runPendingAdd`).
enum TrainingAddAction: Equatable {
    /// Live workout: name a sport, then `LiveWorkoutView` (or reopen the running one).
    case record
    /// Lift Log, where a program is started (or the running lift session is reopened).
    case liftSession
    /// The preview-before-save `WorkoutTextImportSheet`.
    case paste
    /// Data Sources, whose "Lifting log (Hevy / Liftosaur)" card holds the CSV importer.
    case hevyCSV
    /// `ManualWorkoutSheet`, the past-workout form.
    case pastWorkout
}

/// B6 "Add training" (`design/round3/training.html`): five ways a session gets into NOOP. Each row only
/// reports the choice; nothing is imported or started here.
struct TrainingAddSheet: View {
    /// Whether a lift session is already running, so its row says it reopens rather than starts.
    let liftSessionActive: Bool
    let onPick: (TrainingAddAction) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                Text("Add training")
                    .noopFont(.sectionTitle)
                    .accessibilityAddTraits(.isHeader)
                Text("Choose how this session gets into NOOP.")
                    .noopFont(.footnote)
                VStack(spacing: 0) {
                    row(.record, icon: "heart.fill", color: NoopTheme.heart,
                        title: "Record a workout", detail: "Live heart rate and Strain from your strap",
                        divider: false)
                    row(.liftSession, icon: "dumbbell.fill", color: NoopTheme.lift,
                        title: liftSessionActive ? "Return to your lift session" : "Start a lift session",
                        detail: liftSessionActive ? "A session is already running"
                                                  : "Tap through a program in Lift Log, set by set")
                    row(.paste, icon: "doc.on.clipboard", color: NoopTheme.textPrimary,
                        title: "Paste workout text", detail: "From Hevy or notes · preview before saving")
                    row(.hevyCSV, icon: "doc.text", color: NoopTheme.textPrimary,
                        title: "Import Hevy CSV", detail: "Full sets · skips sessions already imported")
                    row(.pastWorkout, icon: "timer", color: NoopTheme.strain,
                        title: "Add a past workout", detail: "Sport, start and end time")
                }
                .padding(.horizontal, NoopTheme.Layout.l)
                .noopGlassBackground()
                .padding(.top, NoopTheme.Layout.xs)
                Text("Apple Health workouts arrive on their own as summaries.")
                    .noopFont(.footnote)
                    .padding(.top, NoopTheme.Layout.s)
            }
            .padding(.horizontal, NoopTheme.Layout.gutter)
            .padding(.top, NoopTheme.Layout.xl)
            .padding(.bottom, NoopTheme.Layout.l)
        }
        .background(NoopTheme.sheet.ignoresSafeArea())
    }

    private func row(_ action: TrainingAddAction, icon: String, color: Color,
                     title: LocalizedStringKey, detail: LocalizedStringKey, divider: Bool = true) -> some View {
        Button { onPick(action) } label: {
            VStack(spacing: 0) {
                if divider { TrainingDivider() }
                HStack(spacing: NoopTheme.Layout.m) {
                    DomainIcon(systemImage: icon, color: color)
                    VStack(alignment: .leading, spacing: NoopTheme.Layout.xs / 2) {
                        Text(title).noopFont(.rowTitle)
                        Text(detail).noopFont(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .noopFont(.footnote, color: false)
                        .foregroundStyle(NoopTheme.textTertiary)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, NoopTheme.Layout.rowVerticalPadding)
                .frame(minHeight: NoopTheme.Layout.minTouchTarget)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.noopPress)
        .accessibilityElement(children: .combine)
    }
}
#endif
