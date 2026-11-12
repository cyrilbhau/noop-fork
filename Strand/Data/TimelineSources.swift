import Foundation
import StrandAnalytics

// The timeline's two adapters (stage 6 specification §8.4): the only stage 6 code that names a
// stage 4 or stage 5 type (decision D20). Each is a value built from closures, so a test or the debug
// demo supplies its own; `live` is the app's. Stage 6 never writes a scan or an event.
//
// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).

/// The recorded scan days (stage 4), for the timeline.
@MainActor
struct TimelineScanSource {
    private let state: () -> TimelineSourceState
    private let scans: () async -> [BodyScan]

    init(state: @escaping () -> TimelineSourceState, scans: @escaping () async -> [BodyScan]) {
        self.state = state
        self.scans = scans
    }

    /// State from `noop.bodyRecordEnabled` (read without writing it), scans from
    /// `BodyRecordStore.scans()`, which spans every device id.
    static func live(repository: Repository, defaults: UserDefaults = .standard) -> TimelineScanSource {
        TimelineScanSource(
            state: { defaults.bool(forKey: BodyRecordSettings.enabledKey) ? .on : .off },
            scans: { await BodyRecordStore(repository: repository).scans() })
    }

    /// Stage 4 not in this build.
    static let notBuilt = TimelineScanSource(state: { .notBuilt }, scans: { [] })

    /// `.on`: the distinct scan days. `.off` or `.notBuilt`: an empty list, and `scans` is not called.
    func read() async -> (state: TimelineSourceState, days: [String]) {
        let current = state()
        guard current == .on else { return (current, []) }
        return (current, Self.days(of: await scans()))
    }

    /// Each scan's own `day`, as stage 4 reports it, with repeats removed in first-seen order. A day
    /// is never derived from the scan's instant.
    static func days(of scans: [BodyScan]) -> [String] {
        var seen = Set<String>()
        return scans.map(\.day).filter { seen.insert($0).inserted }
    }
}

/// The diet breaks and deloads (stage 5), for the timeline.
@MainActor
struct TimelineEventSource {
    private let state: () -> TimelineSourceState
    private let events: () -> [PersonalEvent]

    init(state: @escaping () -> TimelineSourceState, events: @escaping () -> [PersonalEvent]) {
        self.state = state
        self.events = events
    }

    /// State from `store.isEnabled`, events from the synchronous property `store.events`.
    static func live(store: PersonalEventStore = .shared) -> TimelineEventSource {
        TimelineEventSource(state: { store.isEnabled ? .on : .off }, events: { store.events })
    }

    /// Stage 5 not in this build.
    static let notBuilt = TimelineEventSource(state: { .notBuilt }, events: { [] })

    /// `.on`: the events the timeline may show, read once. `.off` or `.notBuilt`: empty, and the
    /// events are not read.
    func read() -> (state: TimelineSourceState, events: [PersonalEvent]) {
        let current = state()
        guard current == .on else { return (current, []) }
        return (current, Self.timelineEvents(events()))
    }

    /// Private events removed first, whatever their kind, then only diet breaks and deloads, order
    /// kept. A private break or deload has no row, no placeholder and no count (§8.4).
    static func timelineEvents(_ events: [PersonalEvent]) -> [PersonalEvent] {
        PersonalEvents.visible(events, includeSensitive: false).filter { $0.kind == .dietBreak || $0.kind == .deload }
    }

    /// Kind, start day and end day only: no label, no note, no id.
    static func span(_ event: PersonalEvent) -> TimelineSpan {
        TimelineSpan(kind: event.kind == .deload ? .deload : .dietBreak, startDay: event.startDay, endDay: event.endDay)
    }
}
