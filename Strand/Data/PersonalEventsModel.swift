import Combine
import Foundation
import StrandAnalytics

// The Events screen and the event sheet (stage 5 specification §10.2, §10.3, §10.9). These two models
// are the only callers of the store's writes (§4.3). A day key for "today" and for a picked date is
// taken with `LocalDayWindows` in the zone of the moment, once per operation (§7.1): travelling never
// moves a saved event.
//
// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).

/// The event sheet's values while the owner edits them.
struct PersonalEventDraft: Equatable {
    enum Length: Equatable { case oneDay, until, ongoing }
    var kind: PersonalEventKind = .travel
    /// The name of a "Something else" event; ignored for every other kind.
    var label: String = ""
    var start: Date
    var length: Length = .oneDay
    /// Read only when `length == .until`.
    var end: Date
    var note: String = ""
    var isPrivate: Bool
}

/// One "Copy stored text": the raw stored list, when it was copied and when the system removes it.
/// The text can hold private names and notes, so, like the coach packet's copy, it is never offered
/// to another device, and the system removes it after the same ten minutes as the packet's copy
/// (ruling A24: one local-only, expiring clipboard write).
struct PersonalEventStoredTextCopyPlan: Equatable {
    static let lifetimeSeconds: TimeInterval = 600
    let text: String
    let copiedAt: Date
    var expiresAt: Date { copiedAt.addingTimeInterval(Self.lifetimeSeconds) }
    /// Never offered to another device.
    var localOnly: Bool { true }
}

/// Puts a copy plan on the system pasteboard. The iPhone's writer is
/// `SystemPersonalEventStoredTextPasteboard`; tests pass a recorder.
protocol PersonalEventStoredTextPasteboardWriting {
    func write(_ plan: PersonalEventStoredTextCopyPlan)
}

/// The Events screen: its rows, the delete and end-today actions and the unreadable-store path.
@MainActor
final class PersonalEventsModel: ObservableObject {
    /// Rebuilt whenever the store's revision moves, whoever changed the list.
    @Published private(set) var presentation: PersonalEventsPresentation

    private let store: PersonalEventStore
    private let now: () -> Date
    private let timeZone: () -> TimeZone
    private let locale: Locale
    private let pasteboard: PersonalEventStoredTextPasteboardWriting?
    private var revisionObserver: AnyCancellable?

    /// `pasteboard` is nil where nothing is copied: the Health row, the debug demo and macOS.
    init(store: PersonalEventStore? = nil, now: @escaping () -> Date = Date.init,
         timeZone: @escaping () -> TimeZone = { .current }, locale: Locale = AppLanguage.activeLocale,
         notificationCenter: NotificationCenter = .default,
         pasteboard: PersonalEventStoredTextPasteboardWriting? = nil) {
        self.store = store ?? .shared
        self.pasteboard = pasteboard
        self.now = now
        self.timeZone = timeZone
        self.locale = locale
        presentation = PersonalEventsPresentation(state: .empty, now: [], upcoming: [], earlier: [],
                                                  unreadableEntriesText: nil, healthRowValue: nil)
        reload()
        // A change of the list or the flag, or of the local day (midnight, a new time zone): "today"
        // is taken again on each reload. The views also reload on returning to the foreground, since
        // the day notification is not delivered while the app is suspended.
        revisionObserver = Publishers.Merge3(
            self.store.$revision.dropFirst().map { _ in () },
            notificationCenter.publisher(for: .NSCalendarDayChanged).map { _ in () },
            notificationCenter.publisher(for: .NSSystemTimeZoneDidChange).map { _ in () }
        ).sink { [weak self] _ in
            // After the change has been published, so the read sees it.
            Task { @MainActor [weak self] in self?.reload() }
        }
    }

    func reload() {
        let today = todayKey()
        let next = PersonalEventPresenter.present(
            events: store.events, today: today, unreadableEntryCount: store.unreadableEntryCount,
            needsAttention: store.needsAttention, locale: locale)
        if next != presentation { presentation = next }
    }

    /// The question asked before a delete; nil for an id the store does not hold.
    func deleteConfirmation(id: String) -> PersonalEventDeleteConfirmation? {
        guard let event = store.events.first(where: { $0.id == id }) else { return nil }
        return PersonalEventPresenter.deleteConfirmation(for: event, today: todayKey(), locale: locale)
    }

    func delete(id: String) throws {
        try store.delete(id: id)
        reload()
    }

    /// The same delete, for a confirmed row of the Events screen.
    func delete(_ id: String) throws {
        try delete(id: id)
    }

    /// The stored event behind a row, for the edit sheet.
    func event(id: String) -> PersonalEvent? {
        store.events.first { $0.id == id }
    }

    /// Ends an ongoing event on today's day key. `.notFound` when the store has no such event.
    func endToday(id: String) throws {
        let today = todayKey()
        guard let event = store.events.first(where: { $0.id == id }) else {
            throw PersonalEventStoreError.notFound
        }
        try store.update(PersonalEvent(id: event.id, kind: event.kind, label: event.label,
                                       startDay: event.startDay, endDay: today, note: event.note,
                                       sensitive: event.sensitive, createdAt: event.createdAt))
        reload()
    }

    /// For "Copy stored text".
    var rawStoredText: String? { store.rawStoredText }

    /// "Copy stored text": the raw stored list as a local-only item that expires. Nothing is written
    /// when there is no stored text.
    func copyStoredText() {
        guard let text = store.rawStoredText else { return }
        pasteboard?.write(PersonalEventStoredTextCopyPlan(text: text, copiedAt: now()))
    }

    /// "Start again", after the one question. True when the unreadable value was removed.
    @discardableResult
    func discardUnreadableStore() -> Bool {
        let discarded = store.discardUnreadableStore()
        reload()
        return discarded
    }

    private func todayKey() -> String {
        LocalDayWindows(timeZone: timeZone()).dayKey(for: now())
    }
}

/// The add and edit sheet. Nothing is written until `save()`.
@MainActor
final class PersonalEventSheetModel: ObservableObject {
    enum Phase: Equatable { case editing, saving, failed(storeUnreadable: Bool), saved }

    @Published var draft: PersonalEventDraft
    @Published private(set) var phase: Phase = .editing

    /// The event being edited; nil for a new one.
    let editing: PersonalEvent?
    private let store: PersonalEventStore
    private let now: () -> Date
    private let timeZone: () -> TimeZone
    /// The owner has moved the Private switch in this sheet: a kind change no longer moves it.
    private var privateTouched = false

    /// `editing` nil: a new event, travel, starting today, one day, no note, Private at the kind's default.
    init(store: PersonalEventStore? = nil, editing: PersonalEvent? = nil,
         now: @escaping () -> Date = Date.init, timeZone: @escaping () -> TimeZone = { .current }) {
        self.store = store ?? .shared
        self.editing = editing
        self.now = now
        self.timeZone = timeZone
        if let editing {
            let days = LocalDayWindows(timeZone: timeZone())
            let fallback = now()
            let start = Self.instant(on: editing.startDay, days) ?? fallback
            let length: PersonalEventDraft.Length
            switch editing.endDay {
            case nil: length = .ongoing
            case editing.startDay?: length = .oneDay
            default: length = .until
            }
            draft = PersonalEventDraft(
                kind: editing.kind, label: editing.label ?? "", start: start, length: length,
                end: editing.endDay.flatMap { Self.instant(on: $0, days) } ?? start,
                note: editing.note ?? "", isPrivate: editing.sensitive)
        } else {
            let today = now()
            draft = PersonalEventDraft(start: today, end: today,
                                       isPrivate: PersonalEvents.defaultSensitive(.travel))
        }
    }

    var isEditing: Bool { editing != nil }

    /// Moves the Private switch to the new kind's default unless the owner has already moved it.
    func setKind(_ kind: PersonalEventKind) {
        draft.kind = kind
        if !privateTouched { draft.isPrivate = PersonalEvents.defaultSensitive(kind) }
    }

    /// The owner's choice; kind changes keep it from now on.
    func setPrivate(_ value: Bool) {
        privateTouched = true
        draft.isPrivate = value
    }

    /// The issues of the draft as it would be saved.
    var issues: [PersonalEventIssue] {
        PersonalEvents.issues(candidate(LocalDayWindows(timeZone: timeZone())))
    }

    var canSave: Bool {
        guard issues.isEmpty else { return false }
        switch phase {
        case .editing, .failed: return true
        case .saving, .saved: return false
        }
    }

    /// The start day is after today's: "Planned: this starts in the future".
    var isPlanned: Bool {
        let days = LocalDayWindows(timeZone: timeZone())
        return days.dayKey(for: draft.start) > days.dayKey(for: now())
    }

    /// Characters left on the note, from 240 characters on; nil below.
    var noteRemaining: Int? {
        let count = draft.note.count
        return count >= Self.remainingCountFrom ? PersonalEvents.maxNoteLength - count : nil
    }

    var endIsBeforeStart: Bool { issues.contains(.endBeforeStart) }
    var needsName: Bool { issues.contains(.missingLabel) }

    /// Takes the draft as it is now, then writes once. The phase says how it went; a failure keeps
    /// every value so Save is the retry.
    func save() {
        guard canSave else { return }
        let event = candidate(LocalDayWindows(timeZone: timeZone()))
        phase = .saving
        do {
            if editing != nil {
                try store.update(event)
            } else {
                try store.add(kind: event.kind, label: event.label, startDay: event.startDay,
                              endDay: event.endDay, note: event.note, sensitive: event.sensitive)
            }
            phase = .saved
        } catch PersonalEventStoreError.storeUnreadable {
            phase = .failed(storeUnreadable: true)
        } catch {
            phase = .failed(storeUnreadable: false)
        }
    }

    // MARK: Pieces

    private static let remainingCountFrom = 240

    /// The draft as the store would hold it, with its days keyed in `days`' zone.
    private func candidate(_ days: LocalDayWindows) -> PersonalEvent {
        let startDay = days.dayKey(for: draft.start)
        let endDay: String?
        switch draft.length {
        case .oneDay: endDay = startDay
        case .until: endDay = days.dayKey(for: draft.end)
        case .ongoing: endDay = nil
        }
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return PersonalEvent(
            id: editing?.id ?? "new", kind: draft.kind,
            label: draft.kind == .custom ? draft.label.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            startDay: startDay, endDay: endDay, note: note.isEmpty ? nil : note,
            sensitive: draft.isPrivate, createdAt: editing?.createdAt ?? 0)
    }

    /// The middle of a stored day in this zone: an instant that falls on that day whatever the
    /// day's length. Nil for a key that is not canonical or a day the zone skipped.
    private static func instant(on key: String, _ days: LocalDayWindows) -> Date? {
        guard CanonicalDay.isValid(key) else { return nil }
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let window = days.window(of: LocalCalendarDate(year: parts[0], month: parts[1], day: parts[2]))
        else { return nil }
        return window.start.addingTimeInterval(window.nextStart.timeIntervalSince(window.start) / 2)
    }
}
