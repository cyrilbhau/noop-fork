import Foundation
import StrandAnalytics

// The words of personal events (stage 5 specification §10.2 to §10.5, §10.9, §11): the Events screen,
// the delete confirmation, the chart caption and the one line an event shows outside the Events
// screen. Views draw these values and decide nothing.
//
// The Events screen is the one place a private event's label or note is turned into text. Everywhere
// else an event is "<kind or Private event> · <dates>", and never a note.
//
// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).

/// One row of the Events screen.
struct PersonalEventRow: Equatable, Identifiable {
    /// The event's id.
    var id: String
    /// The kind's name, or the owner's label. Shown in full here only.
    var title: String
    /// "10 – 16 Mar", "22 Jan", "Since 19 May", "From 2 Jul".
    var dateText: String
    /// Nil when the event has no note.
    var noteFirstLine: String?
    /// Shows the "Private" tag.
    var isPrivate: Bool
    /// True for an ongoing event that has started.
    var offersEndToday: Bool
}

struct PersonalEventsPresentation: Equatable {
    enum State: Equatable { case empty, rows, storeUnreadable }
    var state: State
    /// Overlapping today; newest start first.
    var now: [PersonalEventRow]
    /// Starting after today; newest start first.
    var upcoming: [PersonalEventRow]
    /// Ended before today; newest start first.
    var earlier: [PersonalEventRow]
    /// "%lld entries could not be read. They are kept."
    var unreadableEntriesText: String?
    /// "%lld now"; nil when nothing overlaps today.
    var healthRowValue: String?
}

/// What the dots under a chart mean, since a dot has no text.
struct PersonalEventCaption: Equatable {
    /// At most two: "Travel · 10 – 16 Mar" or "Private event · 26 Mar".
    var lines: [String]
    /// "and %lld more".
    var moreText: String?
    /// "Events:" then the lines and `moreText`, joined by ", ".
    var spokenText: String
}

struct PersonalEventDeleteConfirmation: Equatable {
    var title: String
    var detail: String
    var warning: String
    var confirmTitle: String
    var cancelTitle: String
}

enum PersonalEventPresenter {
    /// The most lines a chart caption names before "and n more".
    static let captionLineLimit = 2

    // MARK: The Events screen

    /// The Events screen. The one place a sensitive label or note is turned into text.
    static func present(events: [PersonalEvent], today: String, unreadableEntryCount: Int,
                        needsAttention: Bool, locale: Locale) -> PersonalEventsPresentation {
        if needsAttention {
            return PersonalEventsPresentation(state: .storeUnreadable, now: [], upcoming: [], earlier: [],
                                              unreadableEntriesText: nil, healthRowValue: nil)
        }
        let newestFirst = Array(PersonalEvents.normalized(events).reversed())
        let now = newestFirst.filter { PersonalEvents.overlaps($0, firstDay: today, lastDay: today) }
        let upcoming = newestFirst.filter { $0.startDay > today }
        let earlier = newestFirst.filter { event in event.endDay.map { $0 < today } ?? false }
        let row = { (event: PersonalEvent) in self.row(event, today: today, locale: locale) }
        var unreadable: String?
        if unreadableEntryCount == 1 {
            unreadable = String(localized: "\(unreadableEntryCount) entry could not be read. It is kept.")
        } else if unreadableEntryCount > 1 {
            unreadable = String(localized: "\(unreadableEntryCount) entries could not be read. They are kept.")
        }
        return PersonalEventsPresentation(
            state: newestFirst.isEmpty ? .empty : .rows,
            now: now.map(row), upcoming: upcoming.map(row), earlier: earlier.map(row),
            unreadableEntriesText: unreadable,
            healthRowValue: now.isEmpty ? nil : String(localized: "\(now.count) now"))
    }

    static func deleteConfirmation(for event: PersonalEvent, locale: Locale) -> PersonalEventDeleteConfirmation {
        deleteConfirmation(for: event, today: nil, locale: locale)
    }

    /// The confirmation with the Events screen's wording for `today` (the row the owner swiped).
    static func deleteConfirmation(for event: PersonalEvent, today: String?,
                                   locale: Locale) -> PersonalEventDeleteConfirmation {
        let dates = dateText(event, today: today, lowercase: false, locale: locale)
        return PersonalEventDeleteConfirmation(
            title: String(localized: "Delete this event?"),
            detail: line(screenTitle(event, locale: locale), dates),
            warning: String(localized: "This cannot be undone."),
            confirmTitle: String(localized: "Delete"),
            cancelTitle: String(localized: "Cancel"))
    }

    static func kindName(_ kind: PersonalEventKind, locale: Locale) -> String {
        switch kind {
        case .travel: return String(localized: "Travel")
        case .illness: return String(localized: "Illness")
        case .dietBreak: return String(localized: "Diet break")
        case .deload: return String(localized: "Deload")
        case .supplementChange: return String(localized: "Supplement change")
        case .custom: return String(localized: "Something else")
        }
    }

    // MARK: Outside the Events screen

    /// One line for an event outside the Events screen: its kind name, or "Private event" when
    /// `sensitive`, then " · " and its dates. Never the label of a sensitive event, never a note.
    /// With no "today" the year is shown only when the dates cross out of the event's start year.
    static func outsideLine(for event: PersonalEvent, locale: Locale) -> String {
        outsideLine(for: event, today: nil, locale: locale)
    }

    /// The same line, with the year shown on a date only when it is not `today`'s year.
    static func outsideLine(for event: PersonalEvent, today: String?, locale: Locale) -> String {
        let name = event.sensitive ? String(localized: "Private event") : kindName(event.kind, locale: locale)
        return line(name, dateText(event, today: today, lowercase: true, locale: locale))
    }

    /// The chart caption for a window; nil when no event overlaps it.
    static func caption(events: [PersonalEvent], firstDay: String, lastDay: String, today: String,
                        locale: Locale) -> PersonalEventCaption? {
        let shown = Array(PersonalEvents.events(overlapping: firstDay, lastDay, in: events).reversed())
        guard !shown.isEmpty else { return nil }
        let lines = shown.prefix(captionLineLimit).map { outsideLine(for: $0, today: today, locale: locale) }
        let hidden = shown.count - lines.count
        let more = hidden > 0 ? moreText(hidden) : nil
        let spoken = String(localized: "Events:") + " " + (lines + [more].compactMap { $0 }).joined(separator: ", ")
        return PersonalEventCaption(lines: Array(lines), moreText: more, spokenText: spoken)
    }

    /// "and %lld more".
    static func moreText(_ count: Int) -> String {
        String(localized: "and \(count) more")
    }

    // MARK: Pieces

    private static func row(_ event: PersonalEvent, today: String, locale: Locale) -> PersonalEventRow {
        let firstLine = event.note?
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        return PersonalEventRow(
            id: event.id, title: screenTitle(event, locale: locale),
            dateText: dateText(event, today: today, lowercase: false, locale: locale),
            noteFirstLine: firstLine, isPrivate: event.sensitive,
            offersEndToday: event.endDay == nil && event.startDay <= today)
    }

    /// The owner's label for a named event, else the kind's name. The Events screen's own title.
    private static func screenTitle(_ event: PersonalEvent, locale: Locale) -> String {
        if event.kind == .custom, let label = event.label, !label.isEmpty { return label }
        return kindName(event.kind, locale: locale)
    }

    private static func line(_ name: String, _ dates: String) -> String {
        String(localized: "\(name) · \(dates)")
    }

    /// The dates of an event. One day: "22 Jan". A range in one month: "10 – 16 Mar"; across
    /// months: "28 Feb – 3 Mar". Ongoing: "Since 19 May" (or "since" outside the Events screen), and
    /// "From 2 Jul" while it has not started. A year is added to a date only when it is not the
    /// reference year: `today`'s, or with no `today` the event's own start year.
    static func dateText(_ event: PersonalEvent, today: String?, lowercase: Bool, locale: Locale) -> String {
        let referenceYear = String((today ?? event.startDay).prefix(4))
        let start = DayText(key: event.startDay, locale: locale)
        guard let endDay = event.endDay else {
            let date = start.text(withYear: start.year != referenceYear)
            if let today, event.startDay > today { return String(localized: "From \(date)") }
            return lowercase ? String(localized: "since \(date)") : String(localized: "Since \(date)")
        }
        let end = DayText(key: endDay, locale: locale)
        if endDay == event.startDay { return start.text(withYear: start.year != referenceYear) }
        let endText = end.text(withYear: end.year != referenceYear)
        let startText: String
        if event.startDay.prefix(7) == endDay.prefix(7) {
            startText = start.dayOnly
        } else {
            startText = start.text(withYear: start.year != end.year && start.year != referenceYear)
        }
        return String(localized: "\(startText) – \(endText)")
    }
}

/// A canonical day key written for people: day and short month, with the year when asked, in the
/// shown locale. The key names a calendar day, so it is formatted in UTC from the key's own digits.
private struct DayText {
    let year: String
    private let date: Date?
    private let locale: Locale
    private let key: String

    init(key: String, locale: Locale) {
        self.key = key
        self.locale = locale
        year = String(key.prefix(4))
        date = Self.parser.date(from: key)
    }

    func text(withYear: Bool) -> String { format(withYear ? "dMMMy" : "dMMM") }
    var dayOnly: String { format("d") }

    private func format(_ template: String) -> String {
        guard let date else { return key }
        return Self.formatter(template, locale).string(from: date)
    }

    private static let utc = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0) ?? .current

    private static let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = utc
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let cache = FormatterCache()

    private static func formatter(_ template: String, _ locale: Locale) -> DateFormatter {
        cache.formatter(template + "|" + locale.identifier) {
            let formatter = DateFormatter()
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = utc
            formatter.calendar = calendar
            formatter.locale = locale
            formatter.timeZone = utc
            formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: template, options: 0, locale: locale)
                ?? "d MMM"
            return formatter
        }
    }
}

/// Formatters by template and locale, built once each. Formatting with a built formatter is safe
/// from any thread; the dictionary is guarded.
private final class FormatterCache: @unchecked Sendable {
    private let lock = NSLock()
    private var formatters: [String: DateFormatter] = [:]

    func formatter(_ name: String, make: () -> DateFormatter) -> DateFormatter {
        lock.lock()
        defer { lock.unlock() }
        if let cached = formatters[name] { return cached }
        let built = make()
        formatters[name] = built
        return built
    }
}
