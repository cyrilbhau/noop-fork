import Foundation

// Stage 6 of the personal fork: the one dated list of phases, recorded scans, owner-entered
// checkpoints, diet breaks, deloads, today and the scorecard's projection
// (docs/personal/superapp/specs/stage-6.md §6.3 and §7.3).
//
// This list is the only one: the view draws it in order and derives its headings from each item's
// position. The function sees days, kinds and numbers only. No title, note or label reaches it, so no
// text can reach a row through it.
//
// One target weight (stage 1 ruling R47): `targetWeightKg` exists only on a phase and on the
// `phaseStart` item built from it. A checkpoint's weight is a waypoint, never a target, and it is
// dropped from its row when the phase target has reached or passed it.
//
// Pure: no store, no clock, no `Date`, `Calendar` or `TimeZone`. "Today" is passed in as a day key and
// every day goes through `CanonicalDay`. Nothing here throws or traps on any input, and no output is
// NaN or infinite.
//
// No Kotlin twin: the owner has skipped Android for the personal fork (stage 1 ruling R43), so every
// declaration here is unpaired in the parity ledger.

/// What a timeline row is. `CheckpointTimeline.kindOrder(_:)` orders the kinds within one day.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public enum TimelineItemKind: String, CaseIterable, Equatable, Sendable {
    case phaseStart, scan, checkpoint, dietBreak, deload, today, projection
}

/// What an owner-entered checkpoint is for.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public enum TimelineCheckpointCategory: String, CaseIterable, Equatable, Sendable {
    case scan, bloodPanel, benchmark, weightWaypoint, targetDate, appointment, other
}

/// The two kinds of event the timeline shows as a span.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public enum TimelineSpanKind: String, CaseIterable, Equatable, Sendable {
    case dietBreak, deload
}

/// Whether a source of timeline entries exists in this build and is switched on.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public enum TimelineSourceState: String, Equatable, Sendable {
    case notBuilt, off, on
}

/// Where an item stands relative to today.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public enum TimelinePosition: String, Equatable, Sendable {
    case past, current, upcoming
}

/// Why a weight may not stand as a waypoint.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public enum TimelineWaypointIssue: String, Equatable, Sendable {
    case nonFinite, atOrBeyondTarget
}

/// A stored phase as the timeline sees it.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public struct TimelinePhase: Equatable, Sendable {
    public let startDay: String
    public let isCut: Bool
    /// The one stored target weight (stage 1).
    public let targetWeightKg: Double?

    public init(startDay: String, isCut: Bool, targetWeightKg: Double?) {
        self.startDay = startDay
        self.isCut = isCut
        self.targetWeightKg = targetWeightKg
    }
}

/// An owner-entered checkpoint. It never carries a target weight.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public struct TimelineCheckpoint: Equatable, Sendable {
    public let day: String
    public let isApproximate: Bool
    public let category: TimelineCheckpointCategory
    /// Only meaningful for `weightWaypoint`.
    public let waypointWeightKg: Double?
    /// Only meaningful for `targetDate`: the start day of the phase it belongs to.
    public let phaseStartDay: String?
    public let isDone: Bool

    public init(day: String, isApproximate: Bool, category: TimelineCheckpointCategory,
                waypointWeightKg: Double?, phaseStartDay: String?, isDone: Bool) {
        self.day = day
        self.isApproximate = isApproximate
        self.category = category
        self.waypointWeightKg = waypointWeightKg
        self.phaseStartDay = phaseStartDay
        self.isDone = isDone
    }
}

/// A diet break or a deload: kind and days only.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public struct TimelineSpan: Equatable, Sendable {
    public let kind: TimelineSpanKind
    public let startDay: String
    /// Nil: open-ended.
    public let endDay: String?

    public init(kind: TimelineSpanKind, startDay: String, endDay: String?) {
        self.kind = kind
        self.startDay = startDay
        self.endDay = endDay
    }
}

/// The scorecard's projection as the timeline sees it.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public struct TimelineProjection: Equatable, Sendable {
    public let status: CutScorecardProjectionStatus
    public let targetDay: String?

    public init(status: CutScorecardProjectionStatus, targetDay: String?) {
        self.status = status
        self.targetDay = targetDay
    }
}

/// Everything the timeline is built from.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public struct CheckpointTimelineInput: Equatable, Sendable {
    public let phases: [TimelinePhase]
    public let checkpoints: [TimelineCheckpoint]
    public let scanDays: [String]
    public let spans: [TimelineSpan]
    /// Nil: the scorecard is off or not loaded.
    public let projection: TimelineProjection?
    public let scans: TimelineSourceState
    public let events: TimelineSourceState
    public let today: String

    public init(phases: [TimelinePhase], checkpoints: [TimelineCheckpoint], scanDays: [String],
                spans: [TimelineSpan], projection: TimelineProjection?, scans: TimelineSourceState,
                events: TimelineSourceState, today: String) {
        self.phases = phases
        self.checkpoints = checkpoints
        self.scanDays = scanDays
        self.spans = spans
        self.projection = projection
        self.scans = scans
        self.events = events
        self.today = today
    }
}

/// One row of the timeline. A field that does not apply to the item's kind holds its empty value.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public struct TimelineItem: Equatable, Sendable {
    public let kind: TimelineItemKind
    /// The sort day; a span's start.
    public let day: String
    /// Spans only.
    public let endDay: String?
    /// A span with no end.
    public let isOpenEnded: Bool
    public let position: TimelinePosition
    /// Index into the input array of this kind. Nil for today and the projection.
    public let sourceIndex: Int?
    public let isApproximate: Bool
    public let isDone: Bool
    /// True only for the projection.
    public let isEstimate: Bool
    public let category: TimelineCheckpointCategory?
    /// `phaseStart` items only: that phase's stored target.
    public let targetWeightKg: Double?
    /// `weightWaypoint` checkpoints only.
    public let waypointWeightKg: Double?
    /// `targetDate` checkpoints only: index into the input's phases.
    public let phaseIndex: Int?
    /// `phaseStart` items only.
    public let phaseIsCut: Bool?

    public init(kind: TimelineItemKind, day: String, endDay: String?, isOpenEnded: Bool,
                position: TimelinePosition, sourceIndex: Int?, isApproximate: Bool, isDone: Bool,
                isEstimate: Bool, category: TimelineCheckpointCategory?, targetWeightKg: Double?,
                waypointWeightKg: Double?, phaseIndex: Int?, phaseIsCut: Bool?) {
        self.kind = kind
        self.day = day
        self.endDay = endDay
        self.isOpenEnded = isOpenEnded
        self.position = position
        self.sourceIndex = sourceIndex
        self.isApproximate = isApproximate
        self.isDone = isDone
        self.isEstimate = isEstimate
        self.category = category
        self.targetWeightKg = targetWeightKg
        self.waypointWeightKg = waypointWeightKg
        self.phaseIndex = phaseIndex
        self.phaseIsCut = phaseIsCut
    }
}

/// What was left out of the list or stripped from a row, and why.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public struct TimelineRejections: Equatable, Sendable {
    public let invalidDay: Int
    public let endBeforeStart: Int
    public let futureScan: Int
    public let duplicate: Int
    public let nonFinite: Int
    public let waypointBeyondTarget: Int

    public init(invalidDay: Int, endBeforeStart: Int, futureScan: Int, duplicate: Int, nonFinite: Int,
                waypointBeyondTarget: Int) {
        self.invalidDay = invalidDay
        self.endBeforeStart = endBeforeStart
        self.futureScan = futureScan
        self.duplicate = duplicate
        self.nonFinite = nonFinite
        self.waypointBeyondTarget = waypointBeyondTarget
    }
}

/// The timeline.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public struct CheckpointTimelineResult: Equatable, Sendable {
    /// The single list, ascending.
    public let items: [TimelineItem]
    /// Index of the today item. Nil exactly when `today` is invalid.
    public let todayIndex: Int?
    public let scans: TimelineSourceState
    public let events: TimelineSourceState
    public let rejections: TimelineRejections
    public let invalidToday: Bool

    public init(items: [TimelineItem], todayIndex: Int?, scans: TimelineSourceState,
                events: TimelineSourceState, rejections: TimelineRejections, invalidToday: Bool) {
        self.items = items
        self.todayIndex = todayIndex
        self.scans = scans
        self.events = events
        self.rejections = rejections
        self.invalidToday = invalidToday
    }
}

/// Builds the one dated list (stage 6 specification §7.3).
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public enum CheckpointTimeline {
    /// phaseStart 0, scan 1, checkpoint 2, dietBreak 3, deload 4, today 5, projection 6.
    ///
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static func kindOrder(_ kind: TimelineItemKind) -> Int {
        switch kind {
        case .phaseStart: return 0
        case .scan: return 1
        case .checkpoint: return 2
        case .dietBreak: return 3
        case .deload: return 4
        case .today: return 5
        case .projection: return 6
        }
    }

    /// Index of the phase in force on `day`: the phase with the greatest canonical `startDay` on or
    /// before `day`; among equal start days the greater index. Nil when `day` is not canonical or no
    /// phase has started by then. The rule of `CutScorecardSettings.activePhase(on:)`.
    ///
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static func governingPhaseIndex(on day: String, phases: [TimelinePhase]) -> Int? {
        guard let dayNumber = CanonicalDay.number(day) else { return nil }
        var governing: (index: Int, start: Int)?
        for (index, phase) in phases.enumerated() {
            guard let start = CanonicalDay.number(phase.startDay), start <= dayNumber else { continue }
            if let held = governing, start < held.start { continue }
            governing = (index, start)
        }
        return governing?.index
    }

    /// Nil when `weightKg` may stand as a waypoint on `day` (§7.3 step 4a). A weight that is not finite
    /// or not positive is `.nonFinite`. Against a usable target of the phase in force on `day`: in a
    /// cut, a weight at or below the target is `.atOrBeyondTarget`; in any other phase, which has no
    /// direction, only a weight equal to the target is.
    ///
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static func waypointIssue(weightKg: Double, on day: String,
                                     phases: [TimelinePhase]) -> TimelineWaypointIssue? {
        guard isUsableWeight(weightKg) else { return .nonFinite }
        guard let index = governingPhaseIndex(on: day, phases: phases),
              let target = phases[index].targetWeightKg, isUsableWeight(target) else { return nil }
        if phases[index].isCut {
            return weightKg <= target ? .atOrBeyondTarget : nil
        }
        return weightKg == target ? .atOrBeyondTarget : nil
    }

    /// The timeline for `input` (§7.3). Never throws or traps.
    ///
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static func build(_ input: CheckpointTimelineInput) -> CheckpointTimelineResult {
        // Step 1: nothing is judged, so nothing is counted.
        guard let todayNumber = CanonicalDay.number(input.today) else {
            return CheckpointTimelineResult(
                items: [], todayIndex: nil, scans: input.scans, events: input.events,
                rejections: TimelineRejections(invalidDay: 0, endBeforeStart: 0, futureScan: 0,
                                               duplicate: 0, nonFinite: 0, waypointBeyondTarget: 0),
                invalidToday: true)
        }

        var invalidDay = 0, endBeforeStart = 0, futureScan = 0, duplicate = 0, nonFinite = 0
        var waypointBeyondTarget = 0
        var placed: [Placed] = []

        /// The position of an item dated on one day (§7.3 step 8).
        func position(_ number: Int) -> TimelinePosition {
            number < todayNumber ? .past : (number == todayNumber ? .current : .upcoming)
        }

        // Step 2: phases.
        for (index, phase) in input.phases.enumerated() {
            guard let number = CanonicalDay.number(phase.startDay) else {
                invalidDay += 1
                continue
            }
            var target = phase.targetWeightKg
            if let weight = target, !isUsableWeight(weight) {
                target = nil
                nonFinite += 1
            }
            placed.append(Placed(number, item(.phaseStart, phase.startDay, position(number),
                                              sourceIndex: index, targetWeightKg: target,
                                              phaseIsCut: phase.isCut)))
        }

        // Step 3: recorded scan days, read only while their source is on. The first occurrence of a
        // day stands for it.
        var scanNumbers = Set<Int>()
        if input.scans == .on {
            for (index, day) in input.scanDays.enumerated() {
                guard let number = CanonicalDay.number(day) else {
                    invalidDay += 1
                    continue
                }
                guard number <= todayNumber else {
                    futureScan += 1
                    continue
                }
                guard scanNumbers.insert(number).inserted else {
                    duplicate += 1
                    continue
                }
                placed.append(Placed(number, item(.scan, day, position(number), sourceIndex: index)))
            }
        }

        // Step 4: checkpoints.
        var targetDatePhaseStarts = Set<String>()
        for (index, checkpoint) in input.checkpoints.enumerated() {
            guard let number = CanonicalDay.number(checkpoint.day) else {
                invalidDay += 1
                continue
            }
            // 4c: the recorded scan stands for a planned scan on the same day.
            if checkpoint.category == .scan, scanNumbers.contains(number) {
                duplicate += 1
                continue
            }
            // 4b: a phase has at most one target date; the earlier kept one in input order stands.
            var phaseIndex: Int?
            if checkpoint.category == .targetDate, let phaseStartDay = checkpoint.phaseStartDay {
                // SPEC-NOTE: §7.3 step 4b drops a target date "whose non-nil `phaseStartDay` equals that
                // of an earlier kept `targetDate` checkpoint". Read as written: the two strings are
                // compared, whether or not any phase starts on that day.
                guard targetDatePhaseStarts.insert(phaseStartDay).inserted else {
                    duplicate += 1
                    continue
                }
                phaseIndex = input.phases.firstIndex {
                    CanonicalDay.number($0.startDay) != nil && $0.startDay == phaseStartDay
                }
            }
            // 4a: a waypoint keeps its row and loses a weight that may not stand.
            var waypoint: Double?
            if checkpoint.category == .weightWaypoint, let weight = checkpoint.waypointWeightKg {
                switch waypointIssue(weightKg: weight, on: checkpoint.day, phases: input.phases) {
                case nil: waypoint = weight
                case .nonFinite?: nonFinite += 1
                case .atOrBeyondTarget?: waypointBeyondTarget += 1
                }
            }
            // SPEC-NOTE: §6.3 gives `phaseIsCut` no comment and §7.3 names it only in step 2 (phase
            // starts). Read as: nil on every checkpoint item, a target date included; the presenter
            // reads the phase through `phaseIndex`, as it reads the phase's weight.
            placed.append(Placed(number, item(.checkpoint, checkpoint.day, position(number),
                                              sourceIndex: index,
                                              isApproximate: checkpoint.isApproximate,
                                              isDone: checkpoint.isDone, category: checkpoint.category,
                                              waypointWeightKg: waypoint, phaseIndex: phaseIndex)))
        }

        // Step 5: diet breaks and deloads, read only while their source is on.
        if input.events == .on {
            for (index, span) in input.spans.enumerated() {
                guard let start = CanonicalDay.number(span.startDay) else {
                    invalidDay += 1
                    continue
                }
                var end: Int?
                if let endDay = span.endDay {
                    guard let number = CanonicalDay.number(endDay) else {
                        invalidDay += 1
                        continue
                    }
                    guard number >= start else {
                        endBeforeStart += 1
                        continue
                    }
                    end = number
                }
                // Step 8 for spans: upcoming until it starts, past once its end is behind today,
                // current otherwise; a span with no end never becomes past.
                let spanPosition: TimelinePosition
                if start > todayNumber {
                    spanPosition = .upcoming
                } else if let end, end < todayNumber {
                    spanPosition = .past
                } else {
                    spanPosition = .current
                }
                let kind: TimelineItemKind
                switch span.kind {
                case .dietBreak: kind = .dietBreak
                case .deload: kind = .deload
                }
                placed.append(Placed(start, item(kind, span.startDay, spanPosition, endDay: span.endDay,
                                                 isOpenEnded: span.endDay == nil, sourceIndex: index)))
            }
        }

        // Step 6: the projection, only when the scorecard projected a canonical day.
        if let projection = input.projection, projection.status == .projected,
           let targetDay = projection.targetDay, let number = CanonicalDay.number(targetDay) {
            placed.append(Placed(number, item(.projection, targetDay, position(number), isEstimate: true)))
        }

        // Step 7: one today item, always.
        placed.append(Placed(todayNumber, item(.today, input.today, .current)))

        // Step 9. No two items share a whole key, so the order does not depend on the sort's stability.
        placed.sort { a, b in
            if a.number != b.number { return a.number < b.number }
            let orderA = kindOrder(a.item.kind), orderB = kindOrder(b.item.kind)
            if orderA != orderB { return orderA < orderB }
            return (a.item.sourceIndex ?? 0) < (b.item.sourceIndex ?? 0)
        }
        let items = placed.map(\.item)

        return CheckpointTimelineResult(
            items: items,
            // Step 10.
            todayIndex: items.firstIndex { $0.kind == .today },
            scans: input.scans, events: input.events,
            rejections: TimelineRejections(invalidDay: invalidDay, endBeforeStart: endBeforeStart,
                                           futureScan: futureScan, duplicate: duplicate,
                                           nonFinite: nonFinite,
                                           waypointBeyondTarget: waypointBeyondTarget),
            invalidToday: false)
    }

    /// An item with the day number it is sorted by.
    private struct Placed {
        let number: Int
        let item: TimelineItem

        init(_ number: Int, _ item: TimelineItem) {
            self.number = number
            self.item = item
        }
    }

    /// A weight that can be shown and compared: finite and above zero.
    private static func isUsableWeight(_ weight: Double) -> Bool {
        weight.isFinite && weight > 0
    }

    /// An item whose fields hold their empty value unless given.
    private static func item(_ kind: TimelineItemKind, _ day: String, _ position: TimelinePosition,
                             endDay: String? = nil, isOpenEnded: Bool = false, sourceIndex: Int? = nil,
                             isApproximate: Bool = false, isDone: Bool = false, isEstimate: Bool = false,
                             category: TimelineCheckpointCategory? = nil, targetWeightKg: Double? = nil,
                             waypointWeightKg: Double? = nil, phaseIndex: Int? = nil,
                             phaseIsCut: Bool? = nil) -> TimelineItem {
        TimelineItem(kind: kind, day: day, endDay: endDay, isOpenEnded: isOpenEnded, position: position,
                     sourceIndex: sourceIndex, isApproximate: isApproximate, isDone: isDone,
                     isEstimate: isEstimate, category: category, targetWeightKg: targetWeightKg,
                     waypointWeightKg: waypointWeightKg, phaseIndex: phaseIndex, phaseIsCut: phaseIsCut)
    }
}
