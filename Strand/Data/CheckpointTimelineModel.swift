import Combine
import Foundation
import StrandAnalytics

// The checkpoint timeline (stage 6 specification §7.3, §8.1, §8.3, §8.4, §10.8): the one caller of
// `CheckpointTimeline.build`. It reads stage 1's stored phases, the stored checkpoints, stage 4's scan
// days and stage 5's diet breaks and deloads through the two adapters, and the projection from the
// shared scorecard model's stored evaluation: it never evaluates the scorecard itself (§8.3), so the
// projection day on the timeline is the one the scorecard screen shows.
//
// With `noop.checkpointTimelineEnabled` off it publishes `.idle` and reads nothing: no stored list,
// no adapter, no scorecard load.
//
// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).

@MainActor
final class CheckpointTimelineModel: ObservableObject {
    enum State: Equatable {
        case idle, loading
        case loaded(CheckpointTimelinePresentation)
    }

    @Published private(set) var state: State = .idle
    /// The latest build; nil while idle.
    private(set) var result: CheckpointTimelineResult?
    /// The events the spans were built from, in the same order, so a row leads back to its event (§8.4).
    private(set) var timelineEvents: [PersonalEvent] = []
    /// The stored phases and checkpoints the latest build read, for the sheets a row opens.
    private(set) var phases: [CutScorecardStoredPhase] = []
    private(set) var checkpoints: [StoredCheckpoint] = []
    /// The day the latest load was for.
    private(set) var today: String?

    let settings: CheckpointTimelineSettings
    let scorecardSettings: CutScorecardSettings
    let scorecard: CutScorecardModel
    private let scans: TimelineScanSource
    private let events: TimelineEventSource
    private let now: () -> Date
    private let timeZone: () -> TimeZone
    private let locale: () -> Locale
    let unitSystem: () -> UnitSystem
    /// Counts loads. A load publishes only while it is still the latest one.
    private var generation = 0

    init(settings: CheckpointTimelineSettings, scorecardSettings: CutScorecardSettings, scorecard: CutScorecardModel,
         scans: TimelineScanSource, events: TimelineEventSource, now: @escaping () -> Date = Date.init,
         timeZone: @escaping () -> TimeZone = { .current },
         locale: @escaping () -> Locale = { AppLanguage.activeLocale },
         unitSystem: @escaping () -> UnitSystem = { .metric }) {
        self.settings = settings
        self.scorecardSettings = scorecardSettings
        self.scorecard = scorecard
        self.scans = scans
        self.events = events
        self.now = now
        self.timeZone = timeZone
        self.locale = locale
        self.unitSystem = unitSystem
    }

    func load() async {
        generation += 1
        let request = generation
        guard settings.isEnabled else {
            result = nil
            timelineEvents = []
            if state != .idle { state = .idle }
            return
        }
        // Captured before the first suspension, so one load describes one moment.
        let day = LocalDayWindows(timeZone: timeZone()).dayKey(for: now())
        let shownLocale = locale()
        let system = unitSystem()
        let eventRead = events.read()
        let phasesNeedAttention = scorecardSettings.phasesNeedAttention
        let storedPhases = phasesNeedAttention ? [] : scorecardSettings.phases
        let checkpointsNeedAttention = settings.checkpointsNeedAttention
        let storedCheckpoints = settings.checkpoints
        let scorecardEnabled = scorecardSettings.isEnabled
        if state == .idle { state = .loading }

        var projection: TimelineProjection?
        if scorecardEnabled {
            await scorecard.load()
            if let evaluated = scorecard.evaluation?.result.projection {
                projection = TimelineProjection(status: evaluated.status, targetDay: evaluated.targetDay)
            }
        }
        let scanRead = await scans.read()
        guard request == generation else { return }
        guard settings.isEnabled else {
            result = nil
            timelineEvents = []
            state = .idle
            return
        }
        let built = CheckpointTimeline.build(CheckpointTimelineInput(
            phases: CheckpointTimelineSettings.timelinePhases(storedPhases),
            checkpoints: storedCheckpoints.map {
                TimelineCheckpoint(day: $0.day, isApproximate: $0.approximate, category: $0.category,
                                   waypointWeightKg: $0.waypointWeightKg, phaseStartDay: $0.phaseStartDay,
                                   isDone: $0.done)
            },
            scanDays: scanRead.days, spans: eventRead.events.map(TimelineEventSource.span), projection: projection,
            scans: scanRead.state, events: eventRead.state, today: day))
        result = built
        timelineEvents = eventRead.events
        phases = storedPhases
        checkpoints = storedCheckpoints
        today = day
        let presentation = CheckpointTimelinePresenter.present(
            built, phases: storedPhases, checkpoints: storedCheckpoints, events: eventRead.events,
            scorecardEnabled: scorecardEnabled, phasesNeedAttention: phasesNeedAttention,
            checkpointsNeedAttention: checkpointsNeedAttention, unitSystem: system, locale: shownLocale)
        if state != .loaded(presentation) { state = .loaded(presentation) }
    }

    // MARK: Writes. Each reloads.

    func save(_ checkpoint: StoredCheckpoint) async -> CheckpointSaveResult {
        let saved = settings.save(checkpoint, phases: phasesForChecks)
        await load()
        return saved
    }

    @discardableResult
    func delete(checkpointId: String) async -> Bool {
        let deleted = settings.delete(id: checkpointId)
        await load()
        return deleted
    }

    @discardableResult
    func setDone(checkpointId: String, _ done: Bool) async -> Bool {
        let set = settings.setDone(id: checkpointId, done, today: today ?? LocalDayWindows(timeZone: timeZone()).dayKey(for: now()))
        await load()
        return set
    }

    func discardUnreadableCheckpoints() async {
        settings.discardUnreadableCheckpoints()
        await load()
    }

    /// The stored phases a save is checked against: none while they cannot be read (§9.3).
    var phasesForChecks: [CutScorecardStoredPhase] {
        scorecardSettings.phasesNeedAttention ? [] : scorecardSettings.phases
    }
}

// MARK: - Draft

/// The checkpoint sheet's editable values (§10.8): captured before the write and kept intact when it
/// is refused. The weight is typed in the display unit and converted with stage 1's constants.
struct CheckpointDraft: Equatable {
    var checkpoint: StoredCheckpoint
    /// The waypoint weight as typed, in the display unit.
    var weightText: String

    static func new(today: String, phases: [CutScorecardStoredPhase]) -> CheckpointDraft {
        CheckpointDraft(checkpoint: StoredCheckpoint(id: "", title: "", category: .other, day: today, approximate: false,
                                                     done: false, waypointWeightKg: nil, phaseStartDay: nil),
                        weightText: "")
    }

    /// The checkpoint as it would be saved: the weight in kilograms on a waypoint only, the phase on a
    /// target date only.
    func stored(unitSystem: UnitSystem, locale: Locale) -> StoredCheckpoint {
        var c = checkpoint
        if c.category == .weightWaypoint {
            let text = weightText.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: locale.decimalSeparator ?? ".", with: ".")
            c.waypointWeightKg = Double(text).map {
                unitSystem == .metric ? $0 : $0 / UnitFormatter.poundsPerKilogram
            }
        } else {
            c.waypointWeightKg = nil
        }
        if c.category != .targetDate { c.phaseStartDay = nil }
        return c
    }
}
