import UIKit
import UniformTypeIdentifiers

// Stage 2 (coach packet), specification §9.1: the packet's own clipboard writer.

/// Writes a copy plan to the general pasteboard as an item that stays on this iPhone and expires.
///
/// `localOnly` keeps the item out of Universal Clipboard and Handoff; `expirationDate` has the
/// system remove it at the plan's `expiresAt`, the same instant the sheet shows. Neither option can
/// be read back, and the app never clears the pasteboard itself afterwards: that would need the
/// app to be running and could remove something else the owner copied since.
struct SystemCoachPacketPasteboard: CoachPacketPasteboardWriting {
    func write(_ plan: CoachPacketCopyPlan) {
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: plan.text]],
            options: [.localOnly: plan.localOnly, .expirationDate: plan.expiresAt])
    }
}
