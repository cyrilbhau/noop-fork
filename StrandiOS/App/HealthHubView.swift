#if os(iOS)
import SwiftUI
import StrandDesign

/// The Health tab root. With the redesign on (the default) it is the round 2 "05 Health" screen,
/// `RedesignHealthView`, which reads the same vital-sign, Fitness Age and skin-temperature data as the
/// classic screen and keeps every classic section one tap away. With it off, the classic `HealthView`.
/// Only the root content swaps, so flipping the preference does not remount the tab's navigation stack.
struct HealthHubView: View {
    @AppStorage(NoopTheme.Keys.redesignEnabled) private var redesignEnabled = true

    var body: some View {
        if redesignEnabled {
            RedesignHealthView()
        } else {
            HealthView()
        }
    }
}

#endif
