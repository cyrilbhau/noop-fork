import SwiftUI
import UIKit

// Stage 2 (coach packet), specification §9.2: the system share sheet for the previewed text.

/// The system share sheet with the packet text as its one item and without its own Copy.
///
/// The system's Copy would write the general pasteboard with no local-only flag and no expiry, so
/// the packet sheet's "Copy" stays the only copy path. Every other destination is the owner's own
/// choice.
struct CoachPacketShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        controller.excludedActivityTypes = [.copyToPasteboard]
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
