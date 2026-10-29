import Foundation

/// Data dependencies only: changing card order must not restart Today's data task.
struct HostedCardLoadNeeds: Hashable {
    let sleep: Bool
    let stress: Bool

    init(raw: String) {
        let cards = HostedCardPrefs.decodeEnabled(raw)
        sleep = cards.contains { $0.rawValue.hasPrefix("sleep.") }
        stress = cards.contains(.stressToday)
    }

    var signature: String { "\(sleep)-\(stress)" }
}
