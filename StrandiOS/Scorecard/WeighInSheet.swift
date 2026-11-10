import SwiftUI
import StrandDesign

// PLACEHOLDER (stage 1, work package 1-7, screens). This file exists only so that the "Log weigh-in"
// action in Settings (specification §10.7) has a sheet to present and the app compiles. The weigh-in
// sheet of specification §10.3 (frames C1 to C10) replaces it, on `WeighInSheetModel`. Settings
// presents it as `WeighInSheet()`, with the repository and the profile in the environment.

/// The weigh-in sheet. Placeholder: an empty sheet with its title.
struct WeighInSheet: View {
    var body: some View {
        NavigationStack {
            Color.clear
                .navigationTitle(Text("Weigh-in"))
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}
