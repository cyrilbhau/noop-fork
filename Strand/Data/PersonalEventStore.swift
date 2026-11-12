import Combine
import Foundation
import StrandAnalytics

// Personal events (stage 5 specification §8.2, §9): the owner's own record of travel, illness, a
// diet break, a deload, a supplement change or a named event, stored as one JSON array in the
// standard defaults and carried by the iPhone backup. This file is the only code that reads or
// writes that key and the only decode of it (§4.3).
//
// The store holds no device identifier and no database handle (§9.5): disconnecting, forgetting or
// deleting a strap never reaches it. With the feature flag off the list is never read.
//
// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).

/// Why a write was refused. Nothing is written when one is thrown.
enum PersonalEventStoreError: Error, Equatable {
    /// The stored value is not a JSON array: every write is refused until the owner discards it.
    case storeUnreadable
    /// The event would be stored with these issues (`PersonalEvents.issues`).
    case invalid([PersonalEventIssue])
    /// No stored event has the id.
    case notFound
}

@MainActor
final class PersonalEventStore: ObservableObject {
    static let enabledKey = "noop.personalEventsEnabled"
    static let itemsKey = "personalEvents.items"
    /// The version every element is written with; an element of a higher version is kept unread.
    private static let elementVersion = 1

    static let shared = PersonalEventStore()

    /// Moves on every change to the stored list, whoever writes it (a backup restore included), and
    /// when the feature flag changes what `events` returns.
    @Published private(set) var revision = 0

    private let defaults: UserDefaults
    private let now: () -> Date
    private let makeId: () -> String
    private var observer: NSObjectProtocol?
    /// What `revision` last followed: the flag, and the stored value while the flag was on. The
    /// stored value is never read while the flag is off.
    private var seen: (enabled: Bool, stored: NSObject?)

    init(defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init,
         makeId: @escaping () -> String = PersonalEventStore.randomId) {
        self.defaults = defaults
        self.now = now
        self.makeId = makeId
        let enabled = defaults.bool(forKey: Self.enabledKey)
        seen = (enabled, enabled ? defaults.object(forKey: Self.itemsKey) as? NSObject : nil)
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: nil
        ) { [weak self] _ in
            // Posted on the thread that wrote. A write on the main thread is followed at once.
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.followStoredValue() }
            } else {
                Task { @MainActor in self?.followStoredValue() }
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Sixteen lowercase hexadecimal characters from the system's random source.
    nonisolated static func randomId() -> String {
        var generator = SystemRandomNumberGenerator()
        return String(format: "%016llx", generator.next() as UInt64)
    }

    // MARK: Reading

    /// The feature flag, read from this store's own defaults.
    var isEnabled: Bool { defaults.bool(forKey: Self.enabledKey) }

    /// The readable events in `normalized` order. Empty while the flag is off (the list is then not
    /// read at all) and while the stored value is unreadable. Read at each access; nothing cached.
    var events: [PersonalEvent] {
        guard isEnabled, case .readable(let decoded) = read() else { return [] }
        return PersonalEvents.normalized(decoded.events)
    }

    /// Stored elements that could not be read as events. They are kept and written back on every save.
    var unreadableEntryCount: Int {
        guard isEnabled, case .readable(let decoded) = read() else { return 0 }
        return decoded.unreadable.count
    }

    /// The stored value is not a JSON array: nothing is shown and every write is refused.
    var needsAttention: Bool {
        guard isEnabled, case .unreadable = read() else { return false }
        return true
    }

    /// The stored text, for the "Copy stored text" action only.
    var rawStoredText: String? {
        guard isEnabled else { return nil }
        return defaults.object(forKey: Self.itemsKey) as? String
    }

    // MARK: Writing

    @discardableResult
    func add(kind: PersonalEventKind, label: String?, startDay: String, endDay: String?,
             note: String?, sensitive: Bool) throws -> PersonalEvent {
        let decoded = try readForWrite()
        let event = try validated(PersonalEvent(
            id: makeId(), kind: kind, label: label, startDay: startDay, endDay: endDay, note: note,
            sensitive: sensitive, createdAt: Int(now().timeIntervalSince1970)))
        write(decoded.events + [event], unreadable: decoded.unreadable)
        return event
    }

    /// Replaces the stored event with the same id. Its `createdAt` is kept.
    func update(_ event: PersonalEvent) throws {
        let decoded = try readForWrite()
        guard let stored = decoded.events.last(where: { $0.id == event.id }) else {
            throw PersonalEventStoreError.notFound
        }
        let updated = try validated(PersonalEvent(
            id: stored.id, kind: event.kind, label: event.label, startDay: event.startDay,
            endDay: event.endDay, note: event.note, sensitive: event.sensitive, createdAt: stored.createdAt))
        write(decoded.events.filter { $0.id != event.id } + [updated], unreadable: decoded.unreadable)
    }

    func delete(id: String) throws {
        let decoded = try readForWrite()
        guard decoded.events.contains(where: { $0.id == id }) else { throw PersonalEventStoreError.notFound }
        write(decoded.events.filter { $0.id != id }, unreadable: decoded.unreadable)
    }

    /// Removes the stored value, only while it is unreadable. True when something was removed.
    @discardableResult
    func discardUnreadableStore() -> Bool {
        guard case .unreadable = read() else { return false }
        defaults.removeObject(forKey: Self.itemsKey)
        return true
    }

    // MARK: The stored shape (§9.2)

    private struct Decoded {
        var events: [PersonalEvent]
        /// Elements held exactly as they were parsed.
        var unreadable: [Any]
    }

    private enum Stored {
        case absent
        case readable(Decoded)
        case unreadable
    }

    /// One parse of the stored value. Reading never writes.
    private func read() -> Stored {
        guard let raw = defaults.object(forKey: Self.itemsKey) else { return .absent }
        guard let text = raw as? String, let data = text.data(using: .utf8),
              let array = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [Any] else {
            return .unreadable
        }
        var decoded = Decoded(events: [], unreadable: [])
        for element in array {
            if let event = Self.decode(element) { decoded.events.append(event) }
            else { decoded.unreadable.append(element) }
        }
        return .readable(decoded)
    }

    private func readForWrite() throws -> Decoded {
        switch read() {
        case .absent: return Decoded(events: [], unreadable: [])
        case .readable(let decoded): return decoded
        case .unreadable: throw PersonalEventStoreError.storeUnreadable
        }
    }

    /// The label and note trimmed, a blank note stored as none, then checked.
    private func validated(_ event: PersonalEvent) throws -> PersonalEvent {
        let label = event.label.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let note = event.note.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let cleaned = PersonalEvent(id: event.id, kind: event.kind, label: label, startDay: event.startDay,
                                    endDay: event.endDay, note: note?.isEmpty == true ? nil : note,
                                    sensitive: event.sensitive, createdAt: event.createdAt)
        let issues = PersonalEvents.issues(cleaned)
        guard issues.isEmpty else { throw PersonalEventStoreError.invalid(issues) }
        return cleaned
    }

    /// The whole array, written once: readable events in `normalized` order, then the unreadable
    /// elements as they were parsed. Sorted keys and no whitespace, so equal lists give equal bytes.
    private func write(_ events: [PersonalEvent], unreadable: [Any]) {
        let elements: [Any] = PersonalEvents.normalized(events).map(Self.encode) + unreadable
        guard let data = try? JSONSerialization.data(withJSONObject: elements, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return }
        defaults.set(text, forKey: Self.itemsKey)
    }

    private static func encode(_ event: PersonalEvent) -> [String: Any] {
        var element: [String: Any] = [
            "createdAt": event.createdAt, "id": event.id, "kind": event.kind.rawValue,
            "sensitive": event.sensitive, "startDay": event.startDay, "v": elementVersion,
        ]
        if let endDay = event.endDay { element["endDay"] = endDay }
        if let label = event.label { element["label"] = label }
        if let note = event.note { element["note"] = note }
        return element
    }

    /// An event when the element is a version-1 object of the right types with no issue; else nil.
    private static func decode(_ element: Any) -> PersonalEvent? {
        guard let object = element as? [String: Any],
              let version = integer(object["v"]), version == elementVersion,
              let id = object["id"] as? String,
              let kindRaw = object["kind"] as? String, let kind = PersonalEventKind(rawValue: kindRaw),
              let startDay = object["startDay"] as? String,
              let sensitive = boolean(object["sensitive"]),
              let createdAt = integer(object["createdAt"]) else { return nil }
        guard let endDay = optionalString(object, "endDay"), let label = optionalString(object, "label"),
              let note = optionalString(object, "note") else { return nil }
        let event = PersonalEvent(id: id, kind: kind, label: label.value, startDay: startDay,
                                  endDay: endDay.value, note: note.value, sensitive: sensitive,
                                  createdAt: createdAt)
        return PersonalEvents.issues(event).isEmpty ? event : nil
    }

    /// An absent key is a present nil; a key of another type is a failed decode (nil).
    private struct OptionalValue { var value: String? }
    private static func optionalString(_ object: [String: Any], _ key: String) -> OptionalValue? {
        guard let raw = object[key] else { return OptionalValue(value: nil) }
        guard let text = raw as? String else { return nil }
        return OptionalValue(value: text)
    }

    /// A JSON boolean only (not a number that bridges to one).
    private static func boolean(_ raw: Any?) -> Bool? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    /// A JSON integer only (not a boolean, not a fraction).
    private static func integer(_ raw: Any?) -> Int? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        guard value.isFinite, value.rounded() == value, abs(value) < 9.0e15 else { return nil }
        return number.intValue
    }

    // MARK: Following other writers

    private func followStoredValue() {
        let enabled = isEnabled
        let stored = enabled ? defaults.object(forKey: Self.itemsKey) as? NSObject : nil
        let unchanged = enabled == seen.enabled && (stored == seen.stored || (stored != nil && seen.stored != nil
            && stored!.isEqual(seen.stored!)))
        seen = (enabled, stored)
        if !unchanged { revision &+= 1 }
    }
}

extension PersonalEventStore {
    /// The one observable copy of the feature flag. Views observe it; the Settings switch calls `set`.
    static let flag = ObservableDefaultsFlag(key: PersonalEventStore.enabledKey)
}
