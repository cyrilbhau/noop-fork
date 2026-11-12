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
    // Stage 3: the intake screen (stage 3 specification §10.2), pushed from the protein card, the
    // Health tab's row and the scorecard's protein row while `noop.intakeEnabled` is on.
    case intake
    // Stage 4: the body record (stage-4.md §5.1), reachable only while `noop.bodyRecordEnabled` is on.
    case bodyRecord
    case bodyScan(id: String)
    case bodyScanCompare(earlierId: String?, laterId: String?)
    case benchmark(key: String)
    // Stage 5: the Events screen (stage 5 §10.2), pushed from the Health tab's row. Reachable only
    // while `noop.personalEventsEnabled` is on.
    case personalEvents
    // Stage 6: the niggle log and one entry (pushed from the Health tab's row), Recovery context and
    // the timeline (pushed from the scorecard's links; the timeline also from the Health tab's row).
    // Each is reachable only while its own `noop.*` flag is on.
    case niggleLog
    case niggle(id: String)
    case cutStress
    case checkpointTimeline

    @ViewBuilder var destination: some View {
        switch self {
        case .recovery(let dayKey): RecoveryDetailView(dayKey: dayKey)
        case .strain(let dayKey): StrainDetailView(dayKey: dayKey)
        case .scorecard: ScorecardView()
        case .weighInHistory: WeighInHistoryView()
        case .intake: IntakeView() // Stage 3
        // Stage 4: the body-record screens.
        case .bodyRecord: BodyRecordView()
        case .bodyScan(let id): BodyScanDetailView(scanId: id)
        case .bodyScanCompare(let earlierId, let laterId): BodyScanCompareView(earlierId: earlierId, laterId: laterId)
        case .benchmark(let key): BenchmarkDetailView(key: key)
        case .personalEvents: PersonalEventsView()   // Stage 5
        // Stage 6: the niggle log, Recovery context and the timeline.
        case .niggleLog: NiggleLogView()
        case .niggle(let id): NiggleDetailView(niggleId: id)
        case .cutStress: CutStressView()
        case .checkpointTimeline: CheckpointTimelineView()
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
