#if os(iOS)
import SwiftUI

/// The Health tab root (redesign round 2 "05 Health"), structural version. It hosts the existing
/// `HealthView` unchanged, so every vitals, Fitness Age and skin-temperature section stays reachable and
/// reads the same data. Phase 6 replaces the presentation with the redesigned vitals; keeping a dedicated
/// root now means that change does not touch the tab shell again.
struct HealthHubView: View {
    var body: some View {
        HealthView()
    }
}

#endif
