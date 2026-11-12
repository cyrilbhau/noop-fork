import Foundation
import StrandAnalytics

// The words of the checkpoint timeline (stage 6 specification §10.1, §10.8, §11). One row per item of
// the one list `CheckpointTimeline.build` returned, in its order (§7.3); nothing else assembles
// timeline rows. Views draw these values and decide nothing.
//
// "Target" is used only for a phase's stored target weight and for the target date; a checkpoint
// weight is always a waypoint. A break or deload row shows its kind and dates only, never an event's
// label or note, and a private event has no row at all (§8.4). The projection is tagged "estimate".
//
// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).

/// Where a row (or a target-date row's weight) opens.
enum TimelineRowDestination: Equatable {
    case phaseSheet(phaseIndex: Int), checkpointSheet(checkpointId: String), bodyRecord
    case personalEvents(eventId: String), scorecard, none
}

/// One row: one built item.
struct TimelineRow: Equatable {
    var kind: TimelineItemKind
    var position: TimelinePosition
    var day: String
    var title: String
    var dateText: String
    var details: [String]
    var tags: [String]
    var destination: TimelineRowDestination
    /// A target-date row's weight opens the phase sheet.
    var weightDestination: TimelineRowDestination?
    /// A past or current checkpoint the owner marked done: its mark is filled.
    var isMarkedDone: Bool = false
}

struct TimelineFootnote: Equatable {
    var text: String
    var linkTitle: String?
    /// What the link opens.
    var link: TimelineRowDestination? = nil
}

/// The Health tab's row (§10.1): "Timeline" and the date of the next upcoming item, or nothing.
struct CheckpointTimelineHealthRow: Equatable {
    var title: String
    var detail: String?
}

struct CheckpointTimelinePresentation: Equatable {
    var rows: [TimelineRow]
    var todayRowIndex: Int?
    var footnotes: [TimelineFootnote]
    var emptyText: String?
    var offersSetUpPhase: Bool
    var attentionText: String?
    var canAdd: Bool
    var limitText: String?
    /// "Add a checkpoint".
    var addTitle: String
    /// "Discard unreadable data" while the checkpoints need attention.
    var discardTitle: String?
    /// "Set up your phase" while `offersSetUpPhase`.
    var setUpPhaseTitle: String?
    /// The three headings the view derives from each row's position.
    var earlierTitle: String
    var todayTitle: String
    var aheadTitle: String
}

enum CheckpointTimelinePresenter {
    static var title: String { String(localized: "Timeline") }

    static func present(_ result: CheckpointTimelineResult, phases: [CutScorecardStoredPhase],
                        checkpoints: [StoredCheckpoint], events: [PersonalEvent], scorecardEnabled: Bool,
                        phasesNeedAttention: Bool, checkpointsNeedAttention: Bool, unitSystem: UnitSystem,
                        locale: Locale) -> CheckpointTimelinePresentation {
        let words = CutScorecardPresenter.Wording(unitSystem: unitSystem, locale: locale)
        let today = result.todayIndex.map { result.items[$0].day }
        let rows = result.items.map { item in
            row(item, phases: phases, checkpoints: checkpoints, events: events, today: today, words: words)
        }
        var footnotes: [TimelineFootnote] = []
        if result.rejections.waypointBeyondTarget > 0 {
            footnotes.append(TimelineFootnote(text: String(localized: "A waypoint at or past your target weight is not shown"),
                                              linkTitle: String(localized: "Open checkpoint"),
                                              link: overtakenWaypoint(result, checkpoints: checkpoints)
                                                  .map { .checkpointSheet(checkpointId: $0) }))
        }
        if result.scans == .off {
            footnotes.append(TimelineFootnote(text: String(localized: "Scans are not shown while the body record is off"),
                                              linkTitle: nil))
        }
        if result.events == .off {
            footnotes.append(TimelineFootnote(text: String(localized: "Breaks and deloads are not shown while events are off"),
                                              linkTitle: nil))
        }
        if !scorecardEnabled {
            footnotes.append(TimelineFootnote(text: String(localized: "No estimate while the scorecard is off"),
                                              linkTitle: nil))
        }
        if phasesNeedAttention {
            footnotes.append(TimelineFootnote(
                text: String(localized: "Your phases could not be read. Target dates are shown without a phase."),
                linkTitle: String(localized: "Open phase and rules"), link: .phaseSheet(phaseIndex: 0)))
        }
        let full = checkpoints.count >= CheckpointTimelineSettings.maxCheckpoints
        let offersPhase = phases.isEmpty && !phasesNeedAttention && scorecardEnabled
        return CheckpointTimelinePresentation(
            rows: rows, todayRowIndex: result.todayIndex, footnotes: footnotes,
            emptyText: result.items.count <= 1 ? String(localized: "Nothing on your timeline yet") : nil,
            offersSetUpPhase: offersPhase,
            attentionText: checkpointsNeedAttention
                ? String(localized: "Your checkpoints could not be read. Nothing has been changed.") : nil,
            canAdd: !checkpointsNeedAttention && !full,
            limitText: full
                ? String(localized: "The timeline holds up to \(CheckpointTimelineSettings.maxCheckpoints) checkpoints") : nil,
            addTitle: String(localized: "Add a checkpoint"),
            discardTitle: checkpointsNeedAttention ? String(localized: "Discard unreadable data") : nil,
            setUpPhaseTitle: offersPhase ? String(localized: "Set up your phase") : nil,
            earlierTitle: String(localized: "Earlier"), todayTitle: String(localized: "Today"),
            aheadTitle: String(localized: "Ahead"))
    }

    /// Nil while the flag is off. The detail is the date of the first upcoming item of the built list,
    /// and nothing else: never a title, a weight, a label or a private event.
    static func healthRow(enabled: Bool, result: CheckpointTimelineResult?, locale: Locale) -> CheckpointTimelineHealthRow? {
        guard enabled else { return nil }
        let words = CutScorecardPresenter.Wording(unitSystem: .metric, locale: locale)
        let next = result?.items.first { $0.position == .upcoming }
        return CheckpointTimelineHealthRow(title: title,
                                           detail: next.map { String(localized: "Next: \(words.shortDate($0.day))") })
    }

    // MARK: Checkpoint sheet (§10.8)

    /// The waypoint field's caption.
    static var waypointCaption: String {
        String(localized: "A waypoint on the way. Your target weight is set in your phase.")
    }

    /// The message for a checkpoint that cannot be saved; nil when it can, or when the field itself
    /// says nothing (an invalid day cannot be picked).
    static func sheetIssueText(_ issue: CheckpointIssue?, checkpoint: StoredCheckpoint,
                               phases: [CutScorecardStoredPhase], unitSystem: UnitSystem, locale: Locale) -> String? {
        guard let issue else { return nil }
        let words = CutScorecardPresenter.Wording(unitSystem: unitSystem, locale: locale)
        switch issue {
        case .emptyTitle: return String(localized: "Enter a title.")
        case .titleTooLong: return String(localized: "A title can be up to 60 characters.")
        case .invalidDay, .weightNotAllowed, .phaseNotAllowed: return nil
        case .weightMissing: return String(localized: "Enter a weight.")
        case .weightOutOfRange: return String(localized: "Enter 30 to 250 kg.")
        case .waypointAtOrBeyondTarget:
            let timeline = CheckpointTimelineSettings.timelinePhases(phases)
            guard let index = CheckpointTimeline.governingPhaseIndex(on: checkpoint.day, phases: timeline),
                  let target = phases[index].targetWeightKg else { return nil }
            return String(localized: "A waypoint has to be short of your target (\(words.weight(target))).")
        case .phaseMissing: return phases.isEmpty ? String(localized: "Set up your phase first") : nil
        case .targetDateNotAfterPhaseStart: return String(localized: "Choose a date after the phase starts")
        case .phaseAlreadyHasTargetDate: return String(localized: "This phase already has a target date")
        }
    }

    /// "Target 94.0 kg" for the phase a target date belongs to, read-only in the sheet.
    static func phaseTargetText(_ phase: CutScorecardStoredPhase, unitSystem: UnitSystem, locale: Locale) -> String? {
        phase.targetWeightKg.map { targetText($0, CutScorecardPresenter.Wording(unitSystem: unitSystem, locale: locale)) }
    }

    /// The waypoint field's unit, and its text for a stored weight.
    static func weightUnit(_ unitSystem: UnitSystem) -> String {
        CutScorecardPresenter.Wording(unitSystem: unitSystem, locale: .current).weightUnit
    }

    static func weightFieldText(_ kg: Double?, unitSystem: UnitSystem, locale: Locale) -> String {
        kg.map { CutScorecardPresenter.Wording(unitSystem: unitSystem, locale: locale).weightNumber($0) } ?? ""
    }

    static var editPhaseTitle: String { String(localized: "Edit phase") }
    static var setUpPhaseTitle: String { String(localized: "Set up your phase") }
    static var doneTitle: String { String(localized: "Done") }
    static var addCheckpointTitle: String { String(localized: "Add a checkpoint") }
    static var editCheckpointTitle: String { String(localized: "Edit checkpoint") }
    static var deleteCheckpointTitle: String { String(localized: "Delete this checkpoint?") }
    static var deleteCheckpointDetail: String { String(localized: "Nothing else on the timeline changes.") }

    // MARK: Words

    static func categoryText(_ category: TimelineCheckpointCategory) -> String {
        switch category {
        case .scan: return String(localized: "Scan")
        case .bloodPanel: return String(localized: "Blood panel")
        case .benchmark: return String(localized: "Benchmark")
        case .weightWaypoint: return String(localized: "Weight waypoint")
        case .targetDate: return String(localized: "Target date")
        case .appointment: return String(localized: "Appointment")
        case .other: return String(localized: "Other")
        }
    }

    // MARK: Rows

    private static func row(_ item: TimelineItem, phases: [CutScorecardStoredPhase], checkpoints: [StoredCheckpoint],
                            events: [PersonalEvent], today: String?, words: CutScorecardPresenter.Wording) -> TimelineRow {
        let date = words.shortDate(item.day)
        var title = ""
        var dateText = date
        var details: [String] = []
        var tags: [String] = []
        var destination = TimelineRowDestination.none
        var weightDestination: TimelineRowDestination?
        var isMarkedDone = false
        switch item.kind {
        case .phaseStart:
            let name = item.sourceIndex.flatMap { phases.indices.contains($0) ? phases[$0].name : nil } ?? ""
            title = item.position == .upcoming ? String(localized: "\(name) starts \(date)")
                                               : String(localized: "\(name) started \(date)")
            dateText = ""
            if let target = item.targetWeightKg { details.append(targetText(target, words)) }
            if let index = item.sourceIndex { destination = .phaseSheet(phaseIndex: index) }
        case .scan:
            title = String(localized: "Scan")
            destination = .bodyRecord
        case .checkpoint:
            let stored = item.sourceIndex.flatMap { checkpoints.indices.contains($0) ? checkpoints[$0] : nil }
            if item.isApproximate { dateText = String(localized: "around \(date)") }
            if item.category == .targetDate {
                if let index = item.phaseIndex, phases.indices.contains(index) {
                    title = String(localized: "Target date for \(phases[index].name)")
                    if let target = phases[index].targetWeightKg {
                        details.append(targetText(target, words))
                        weightDestination = .phaseSheet(phaseIndex: index)
                    }
                } else {
                    title = String(localized: "Target date")
                    if let stored { details.append(stored.title) }
                }
            } else {
                title = stored?.title ?? ""
                if let category = item.category { details.append(categoryText(category)) }
            }
            if let waypoint = item.waypointWeightKg {
                details.append(String(localized: "Waypoint \(words.weight(waypoint))"))
            }
            if item.isDone && item.position != .upcoming {
                isMarkedDone = true
                details.append(String(localized: "Done"))
            } else if item.position == .past {
                details.append(String(localized: "Not marked done"))
            }
            if let stored { destination = .checkpointSheet(checkpointId: stored.id) }
        case .dietBreak, .deload:
            title = item.kind == .deload ? String(localized: "Deload") : String(localized: "Diet break")
            if let end = item.endDay {
                dateText = String(localized: "\(date) to \(words.shortDate(end))")
            } else {
                dateText = String(localized: "Since \(date)")
            }
            if item.position == .current { tags.append(String(localized: "now")) }
            if let index = item.sourceIndex, events.indices.contains(index) {
                destination = .personalEvents(eventId: events[index].id)
            }
        case .today:
            title = String(localized: "Today")
            destination = .none
        case .projection:
            title = String(localized: "Estimated \(date) at this rate")
            dateText = ""
            tags.append(String(localized: "estimate"))
            let timeline = CheckpointTimelineSettings.timelinePhases(phases)
            if let today, let index = CheckpointTimeline.governingPhaseIndex(on: today, phases: timeline),
               let target = phases[index].targetWeightKg {
                details.append(targetText(target, words))
            }
            destination = .scorecard
        }
        return TimelineRow(kind: item.kind, position: item.position, day: item.day, title: title, dateText: dateText,
                           details: details, tags: tags, destination: destination, weightDestination: weightDestination,
                           isMarkedDone: isMarkedDone)
    }

    /// The first stored waypoint whose weight the build dropped because the phase target overtook it.
    private static func overtakenWaypoint(_ result: CheckpointTimelineResult, checkpoints: [StoredCheckpoint]) -> String? {
        for item in result.items where item.kind == .checkpoint && item.category == .weightWaypoint
            && item.waypointWeightKg == nil {
            if let index = item.sourceIndex, checkpoints.indices.contains(index),
               checkpoints[index].waypointWeightKg != nil {
                return checkpoints[index].id
            }
        }
        return nil
    }

    /// "Target 94.0 kg": the phase's stored target, worded as the scorecard words it.
    private static func targetText(_ kg: Double, _ words: CutScorecardPresenter.Wording) -> String {
        String(localized: "Target \(words.weight(kg))")
    }
}
