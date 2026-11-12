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
    /// Set by the first load; a model no screen has loaded reads nothing on a day change.
    private var hasLoaded = false
    private var dayObserver: AnyCancellable?

    init(settings: CheckpointTimelineSettings, scorecardSettings: CutScorecardSettings, scorecard: CutScorecardModel,
         scans: TimelineScanSource, events: TimelineEventSource, now: @escaping () -> Date = Date.init,
         timeZone: @escaping () -> TimeZone = { .current },
         locale: @escaping () -> Locale = { AppLanguage.activeLocale },
         unitSystem: @escaping () -> UnitSystem = { .metric },
         notificationCenter: NotificationCenter = .default) {
        self.settings = settings
        self.scorecardSettings = scorecardSettings
        self.scorecard = scorecard
        self.scans = scans
        self.events = events
        self.now = now
        self.timeZone = timeZone
        self.locale = locale
        self.unitSystem = unitSystem
        // Ruling A27: once a screen has loaded it, a new local day (midnight, a new time zone, or a return
        // to the foreground) reads again, so no day count or day-derived label stays on yesterday.
        dayObserver = LocalDayChange.observe(notificationCenter) { [weak self] in
            guard let self, self.hasLoaded else { return }
            Task { await self.load() }
        }
    }

    func load() async {
        hasLoaded = true
        generation += 1
        let request = generation
        guard settings.isEnabled else {
            result = nil
            timelineEvents = []
            latest = nil
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

        if scorecardEnabled {
            followScorecard()
            await scorecard.load()
        }
        let scanRead = await scans.read()
        guard request == generation else { return }
        guard settings.isEnabled else {
            result = nil
            timelineEvents = []
            latest = nil
            state = .idle
            return
        }
        let inputs = Inputs(
            phases: storedPhases, checkpoints: storedCheckpoints, events: eventRead, scanRead: scanRead,
            scorecardEnabled: scorecardEnabled, phasesNeedAttention: phasesNeedAttention,
            checkpointsNeedAttention: checkpointsNeedAttention, today: day, unitSystem: system, locale: shownLocale)
        latest = inputs
        publishedGeneration = request
        publish(inputs)
    }

    /// What a load read, kept so a later scorecard result can be shown without reading anything again.
    private struct Inputs {
        let phases: [CutScorecardStoredPhase]
        let checkpoints: [StoredCheckpoint]
        let events: (state: TimelineSourceState, events: [PersonalEvent])
        let scanRead: (state: TimelineSourceState, days: [String])
        let scorecardEnabled: Bool
        let phasesNeedAttention: Bool
        let checkpointsNeedAttention: Bool
        let today: String
        let unitSystem: UnitSystem
        let locale: Locale
    }

    /// The inputs of the latest load that published; nil while idle or before the first one.
    private var latest: Inputs?
    /// The load `latest` came from; a timeline load is in flight while it is not `generation`.
    private var publishedGeneration = 0
    private var scorecardObserver: AnyCancellable?

    /// Builds and publishes from `inputs` and the shared scorecard model's evaluation as it stands now
    /// (§8.3): the projection is read in the same step that publishes, never across a suspension.
    private func publish(_ inputs: Inputs) {
        var projection: TimelineProjection?
        if inputs.scorecardEnabled, let evaluated = scorecard.evaluation?.result.projection {
            projection = TimelineProjection(status: evaluated.status, targetDay: evaluated.targetDay)
        }
        let built = CheckpointTimeline.build(CheckpointTimelineInput(
            phases: CheckpointTimelineSettings.timelinePhases(inputs.phases),
            checkpoints: inputs.checkpoints.map {
                TimelineCheckpoint(day: $0.day, isApproximate: $0.approximate, category: $0.category,
                                   waypointWeightKg: $0.waypointWeightKg, phaseStartDay: $0.phaseStartDay,
                                   isDone: $0.done)
            },
            scanDays: inputs.scanRead.days, spans: inputs.events.events.map(TimelineEventSource.span),
            projection: projection, scans: inputs.scanRead.state, events: inputs.events.state, today: inputs.today))
        result = built
        timelineEvents = inputs.events.events
        phases = inputs.phases
        checkpoints = inputs.checkpoints
        today = inputs.today
        let presentation = CheckpointTimelinePresenter.present(
            built, phases: inputs.phases, checkpoints: inputs.checkpoints, events: inputs.events.events,
            scorecardEnabled: inputs.scorecardEnabled, phasesNeedAttention: inputs.phasesNeedAttention,
            checkpointsNeedAttention: inputs.checkpointsNeedAttention, unitSystem: inputs.unitSystem,
            locale: inputs.locale)
        if state != .loaded(presentation) { state = .loaded(presentation) }
    }

    /// From the first load with the scorecard on, every result the shared scorecard model publishes
    /// re-presents the latest load's inputs, so a scorecard load that overtook this model's own (a
    /// weigh-in saved, a sync) still reaches the timeline. The scorecard sets `evaluation` before
    /// `state`, so the value read here is the published one. Nothing is read or evaluated again, and
    /// a timeline load still in flight is left to read the evaluation itself.
    private func followScorecard() {
        guard scorecardObserver == nil else { return }
        scorecardObserver = scorecard.$state.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.scorecardDidPublish() }
        }
    }

    private func scorecardDidPublish() {
        guard publishedGeneration == generation, let inputs = latest, settings.isEnabled,
              case .loaded = state else { return }
        publish(inputs)
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

    /// The stored checkpoint with this id, as the latest load read it.
    func checkpoint(id: String) -> StoredCheckpoint? { checkpoints.first { $0.id == id } }

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

    /// The phase a new target date is attached to by default: the phase in force today, else the first.
    static func defaultPhaseStartDay(phases: [CutScorecardStoredPhase], today: String) -> String? {
        phases.last { $0.startDay <= today }?.startDay ?? phases.first?.startDay
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
