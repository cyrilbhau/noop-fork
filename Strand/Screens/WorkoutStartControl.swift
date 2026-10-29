import SwiftUI
import StrandDesign

/// #459: "Start Workout" used to live ONLY on the Live screen, so a user reaching Workouts (via the
/// Quick-action FAB or the tab) had no way to begin one from the obvious place. This button starts a live
/// session and presents the in-exercise view directly.
///
/// PERF (chart-invalidation): this is the ONE place `WorkoutsView` needs live `AppModel` state
/// (`activeWorkout`) — everything else it needs (`hrMax`, `analyzeRecent()`) lives on sub-objects that
/// don't publish at live-tick frequency. `AppModel` publishes `bpm` at ~1 Hz (AppModel.swift:202), and
/// `@EnvironmentObject` subscribes to the WHOLE object's `objectWillChange`, so if `WorkoutsView` itself
/// held `model: AppModel`, every tick would re-evaluate its entire ~1900-line body (chart + grids +
/// sorting) even though only this button's label and its two sheets read `model`. Isolating it here
/// (mirroring `HealthView`'s live-observing-leaf pattern, HealthView.swift:17-22, 44-46) means a tick
/// re-renders only this small leaf. Owns its own sheet-presentation state so nothing about it needs to
/// live on the parent either.
struct WorkoutStartControl: View {
    @EnvironmentObject var model: AppModel
    @State private var showLiveWorkout = false
    @State private var showStartSport = false
    #if os(iOS)
    @AppStorage(NoopTheme.Keys.redesignEnabled) private var workoutsRedesign = true
    #endif

    var body: some View {
        startWorkoutButton
        .accessibilityLabel(model.activeWorkout == nil ? "Start a workout" : "View the active workout")
        // #459: the in-exercise view, presented when Start Workout is tapped here (same screen LiveView
        // shows). activeWorkout is global on AppModel, so ending it from either surface stays in sync.
        .sheet(isPresented: $showLiveWorkout) {
            LiveWorkoutView(onClose: { showLiveWorkout = false })
                // Inject the shared live snapshot so the in-exercise sensor readout (speed/cadence/power)
                // resolves here too, matching how LiveView presents the same screen.
                .environmentObject(model.live)
        }
        // #519: name the sport before a live session starts, then open the in-exercise view directly
        // (same direct present as the button's already-active path — no cross-view auto-present race).
        .workoutSelectionCover(isPresented: $showStartSport) {
            StartWorkoutSheet { name in
                model.startWorkout(sport: name)
                showLiveWorkout = true
            }
        }
    }

    @ViewBuilder private var startWorkoutButton: some View {
        #if os(iOS)
        if workoutsRedesign {
            Button(action: presentWorkout) {
                Label(model.activeWorkout == nil ? "Start workout" : "View active workout",
                      systemImage: model.activeWorkout == nil ? "figure.run" : "timer")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(NoopPrimaryButton())
        } else {
            classicStartWorkoutButton
        }
        #else
        classicStartWorkoutButton
        #endif
    }

    private var classicStartWorkoutButton: some View {
        NoopButton(model.activeWorkout == nil ? "Start workout" : "View active workout",
                   systemImage: model.activeWorkout == nil ? "figure.run" : "timer",
                   kind: .primary, fullWidth: true, action: presentWorkout)
    }

    private func presentWorkout() {
        // An active session opens directly; otherwise the named-sport picker starts it first.
        if model.activeWorkout == nil { showStartSport = true }
        else { showLiveWorkout = true }
    }
}
