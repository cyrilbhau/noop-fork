import SwiftUI

/// Pushes into the iPhone redesign's score-detail screens (`docs/personal/REDESIGN-IMPLEMENTATION.md`
/// Phase 4). Registered once per tab stack by `RootTabView.tabStack`, next to `TabRoute` and
/// `MoreDestination`. `dayKey` is a `Repository` day key ("yyyy-MM-dd"); nil means today.
enum RedesignRoute: Hashable {
    case recovery(dayKey: String?)
    case strain(dayKey: String?)
    /// The weekly weigh-in scorecard (stage 1 specification §10.2), pushed from its Today card, the
    /// Today weight row and the Health tab's row. Reachable only while `noop.cutScorecardEnabled` is on.
    case scorecard
    /// The weigh-in history (specification §10.4), pushed from the scorecard.
    case weighInHistory

    @ViewBuilder var destination: some View {
        switch self {
        case .recovery(let dayKey): RecoveryDetailView(dayKey: dayKey)
        case .strain(let dayKey): StrainDetailView(dayKey: dayKey)
        case .scorecard: ScorecardView()
        case .weighInHistory: WeighInHistoryView()
        }
    }
}

extension View {
    /// Registers `RedesignRoute` on the enclosing NavigationStack. Call once per stack.
    func redesignDestinations() -> some View {
        navigationDestination(for: RedesignRoute.self) { route in
            route.destination
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}
