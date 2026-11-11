import Foundation

// Personal events (stage 5 specification §6 and §7): travel, illness, a diet break, a deload, a
// supplement change, or a kind the owner names, each a run of whole local days. This file is the
// pure half: validation, the one order, overlap with a range and a week, chart slots, and the one
// function that applies the private flag. The store (app target) owns the only encode and decode.
//
// Pure: no store, no clock, no calendar, time-zone, date or locale object. Every function is total:
// it never throws and never traps, whatever it is given. A day is valid exactly when
// `CanonicalDay.number` is not nil; this file declares no day rule of its own.
//
// Events are display context only. Nothing here feeds a score, an estimate or a verdict.
//
// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).

/// What an event is. The raw value is what the store writes and what the coach packet prints.
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public enum PersonalEventKind: String, CaseIterable, Sendable {
    case travel, illness, dietBreak, deload, supplementChange, custom
}

/// One event the owner entered: a kind and an inclusive run of local calendar days.
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public struct PersonalEvent: Equatable, Sendable {
    /// Non-empty. The store issues sixteen lowercase hex characters.
    public let id: String
    public let kind: PersonalEventKind
    /// The owner's name for a `.custom` event; nil for every other kind.
    public let label: String?
    /// The first day, a canonical "yyyy-MM-dd" key.
    public let startDay: String
    /// The last day, inclusive. Nil means ongoing; equal to `startDay` means one day.
    public let endDay: String?
    /// Nil, or text that is not blank.
    public let note: String?
    /// The owner's choice for this event. The only thing a consumer tests; the kind is not.
    public let sensitive: Bool
    /// Epoch seconds. Used only to break a tie in the order.
    public let createdAt: Int

    public init(id: String, kind: PersonalEventKind, label: String?, startDay: String,
                endDay: String?, note: String?, sensitive: Bool, createdAt: Int) {
        self.id = id
        self.kind = kind
        self.label = label
        self.startDay = startDay
        self.endDay = endDay
        self.note = note
        self.sensitive = sensitive
        self.createdAt = createdAt
    }
}

/// What is wrong with an event. `PersonalEvents.issues` reports them in this declared order.
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public enum PersonalEventIssue: Equatable, Sendable {
    case emptyId, invalidStartDay, invalidEndDay, endBeforeStart
    case missingLabel, unexpectedLabel, labelTooLong, emptyNote, noteTooLong
}

/// How an event lies against an inclusive range of days.
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public enum PersonalEventWeekRelation: Equatable, Sendable {
    /// The event ended before the range began.
    case before
    /// The event starts after the range ends.
    case after
    /// The event starts and ends inside the range.
    case within
    /// The event starts inside the range and ends after it, or is ongoing.
    case startsWithin
    /// The event starts before the range and ends inside it.
    case endsWithin
    /// The event starts before the range and ends after it, or is ongoing.
    case covers
}

/// An inclusive run of days that one chart position stands for: a day (first == last) or a week.
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public struct PersonalEventSlot: Equatable, Sendable {
    public let firstDay: String
    public let lastDay: String

    public init(firstDay: String, lastDay: String) {
        self.firstDay = firstDay
        self.lastDay = lastDay
    }
}

/// The rules of personal events (§7).
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public enum PersonalEvents {
    /// The longest label, in `Character`s (grapheme clusters).
    public static let maxLabelLength = 40
    /// The longest note, in `Character`s.
    public static let maxNoteLength = 280

    /// The kinds whose editor switch starts on (§7.2).
    static let kindsSensitiveByDefault: Set<PersonalEventKind> = [.illness, .custom]
    /// Days from a week's Monday to its Sunday.
    static let weekLastDayOffset = 6

    // MARK: Validation

    /// What the editor's Private switch starts at for a kind. The stored flag is the owner's.
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static func defaultSensitive(_ kind: PersonalEventKind) -> Bool {
        kindsSensitiveByDefault.contains(kind)
    }

    /// Every issue of an event, in the order `PersonalEventIssue` declares them. Empty means valid.
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static func issues(_ event: PersonalEvent) -> [PersonalEventIssue] {
        var found: [PersonalEventIssue] = []
        if event.id.isEmpty { found.append(.emptyId) }

        let startIsValid = CanonicalDay.number(event.startDay) != nil
        if !startIsValid { found.append(.invalidStartDay) }
        if let end = event.endDay {
            if CanonicalDay.number(end) == nil {
                found.append(.invalidEndDay)
            } else if startIsValid, end < event.startDay {
                // Canonical keys order as their days do (§7.1), so this is a string comparison.
                found.append(.endBeforeStart)
            }
        }

        if event.kind == .custom {
            if isBlank(event.label ?? "") { found.append(.missingLabel) }
        } else if event.label != nil {
            found.append(.unexpectedLabel)
        }
        // SPEC-NOTE: §7.3 gives `labelTooLong` and `noteTooLong` no kind and no trimming, so each
        // counts the stored text as given: a label on a kind that takes none can be both unexpected
        // and too long, and 281 spaces are both an empty note and a too-long one.
        if let label = event.label, label.count > maxLabelLength { found.append(.labelTooLong) }
        if let note = event.note {
            if isBlank(note) { found.append(.emptyNote) }
            if note.count > maxNoteLength { found.append(.noteTooLong) }
        }
        return found
    }

    /// The valid events, one per id (the last occurrence in the input wins), ascending by
    /// `(startDay, createdAt, id)`. Equal lists therefore come back in one order.
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static func normalized(_ events: [PersonalEvent]) -> [PersonalEvent] {
        // SPEC-NOTE: §7.3 lists the steps as "keeps events with no issues, removes duplicates by
        // id, and sorts", and they are applied in that order: an invalid event is gone before
        // duplicates are resolved, so it cannot displace a valid event of the same id.
        var newest: [String: PersonalEvent] = [:]
        for event in events where issues(event).isEmpty {
            newest[event.id] = event
        }
        return newest.values.sorted(by: comesBefore)
    }

    // MARK: Overlap

    /// How `event` lies against `[firstDay, lastDay]`. Nil when either day is not a valid day, when
    /// `lastDay` is before `firstDay`, or when the event has any issue.
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static func relation(of event: PersonalEvent, firstDay: String, lastDay: String)
        -> PersonalEventWeekRelation? {
        guard isValidRange(firstDay, lastDay), issues(event).isEmpty else { return nil }
        return relation(ofValid: event, firstDay: firstDay, lastDay: lastDay)
    }

    /// Whether any day of `event` falls in `[firstDay, lastDay]`: `relation` is neither nil,
    /// `.before` nor `.after`.
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static func overlaps(_ event: PersonalEvent, firstDay: String, lastDay: String) -> Bool {
        isOverlap(relation(of: event, firstDay: firstDay, lastDay: lastDay))
    }

    /// The events with a day in `[firstDay, lastDay]`, in `normalized` order. Empty for an invalid
    /// range.
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static func events(overlapping firstDay: String, _ lastDay: String,
                              in events: [PersonalEvent]) -> [PersonalEvent] {
        guard isValidRange(firstDay, lastDay) else { return [] }
        return normalized(events).filter {
            isOverlap(relation(ofValid: $0, firstDay: firstDay, lastDay: lastDay))
        }
    }

    /// The events with a day in the week that starts on `weekStart`, in `normalized` order. Empty
    /// unless `weekStart` is a valid day that is the Monday of its own week.
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static func events(overlappingWeekStarting weekStart: String,
                              in events: [PersonalEvent]) -> [PersonalEvent] {
        guard let monday = CanonicalDay.number(weekStart),
              CanonicalDay.weekStart(containing: weekStart) == weekStart else { return [] }
        // `CanonicalDay.key` clamps at 9999-12-31, so the last week of the calendar is a short,
        // still valid, range.
        return self.events(overlapping: weekStart, CanonicalDay.key(monday + weekLastDayOffset),
                           in: events)
    }

    /// One Bool per slot, in the order given: whether any event has a day in the slot. An invalid
    /// slot is false. Private events count: a chart dot carries no text.
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static func coveredSlots(events: [PersonalEvent], slots: [PersonalEventSlot]) -> [Bool] {
        let valid = normalized(events)
        return slots.map { slot in
            guard isValidRange(slot.firstDay, slot.lastDay) else { return false }
            return valid.contains {
                isOverlap(relation(ofValid: $0, firstDay: slot.firstDay, lastDay: slot.lastDay))
            }
        }
    }

    // MARK: Visibility

    /// `normalized(events)`, without the events the owner marked private unless `includeSensitive`
    /// is true. The one function that applies the flag; the kind plays no part.
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static func visible(_ events: [PersonalEvent], includeSensitive: Bool) -> [PersonalEvent] {
        let valid = normalized(events)
        return includeSensitive ? valid : valid.filter { !$0.sensitive }
    }

    // MARK: Private

    /// Whether text is empty once whitespace and newlines are trimmed from both ends.
    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The order of `normalized`: start day, then `createdAt` as a number, then id.
    private static func comesBefore(_ a: PersonalEvent, _ b: PersonalEvent) -> Bool {
        if a.startDay != b.startDay { return a.startDay < b.startDay }
        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
        return a.id < b.id
    }

    /// Whether both days are valid and the last is not before the first.
    private static func isValidRange(_ firstDay: String, _ lastDay: String) -> Bool {
        CanonicalDay.number(firstDay) != nil && CanonicalDay.number(lastDay) != nil
            && firstDay <= lastDay
    }

    /// Whether a relation means the event has a day in the range.
    private static func isOverlap(_ relation: PersonalEventWeekRelation?) -> Bool {
        switch relation {
        case .none, .before, .after: return false
        case .within, .startsWithin, .endsWithin, .covers: return true
        }
    }

    /// The one overlap rule (§7.4), for an event with no issue and a valid range. Canonical keys
    /// order as their days do, so every comparison is a string comparison.
    private static func relation(ofValid event: PersonalEvent, firstDay: String, lastDay: String)
        -> PersonalEventWeekRelation {
        let start = event.startDay
        if let end = event.endDay, end < firstDay { return .before }
        if start > lastDay { return .after }
        let endsInside = event.endDay.map { $0 <= lastDay } ?? false
        if start >= firstDay { return endsInside ? .within : .startsWithin }
        return endsInside ? .endsWithin : .covers
    }
}
