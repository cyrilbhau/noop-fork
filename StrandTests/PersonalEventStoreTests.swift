// API ASSUMED BY THESE TESTS
//
// Written from docs/personal/superapp/specs/stage-5.md (§5, §9.1 to §9.5, §10.9, §12.3, §13) and
// RULINGS-ADDENDUM.md before the implementation exists. New, in Strand/Data/PersonalEventStore.swift:
//
//     enum PersonalEventStoreError: Error, Equatable {
//         case storeUnreadable
//         case invalid([PersonalEventIssue])
//         case notFound
//     }
//
//     @MainActor
//     final class PersonalEventStore: ObservableObject {
//         static let enabledKey = "noop.personalEventsEnabled"
//         static let itemsKey = "personalEvents.items"
//         static let shared: PersonalEventStore
//         static let flag: ObservableDefaultsFlag            // ObservableDefaultsFlag(key: enabledKey)
//         static func randomId() -> String                   // 16 lowercase hex characters
//         init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
//              makeId: @escaping () -> String = PersonalEventStore.randomId)
//         @Published private(set) var revision: Int
//         var isEnabled: Bool { get }
//         var events: [PersonalEvent] { get }
//         var unreadableEntryCount: Int { get }
//         var needsAttention: Bool { get }
//         var rawStoredText: String? { get }
//         @discardableResult func add(kind:label:startDay:endDay:note:sensitive:) throws -> PersonalEvent
//         func update(_ event: PersonalEvent) throws
//         func delete(id: String) throws
//         @discardableResult func discardUnreadableStore() -> Bool
//     }
//
// New, in Strand/Data/PersonalEventsModel.swift (§10.9), used here for the day-key cases:
//
//     struct PersonalEventDraft { kind, label, start: Date, length: Length (.oneDay/.until/.ongoing),
//                                 end: Date, note, isPrivate }
//     @MainActor final class PersonalEventSheetModel: ObservableObject {
//         init(store:editing:now:timeZone:); var draft; var phase; func save()
//     }
//
// New, in Strand/Data/DemoScreenRegistry.swift (ruling A4, debug builds only):
//
//     extension DemoScreenPrefixes { static let events = ["events-"] }
//
// Behaviour assumed where the specification leaves it unstated:
//
//  1. `add` stamps `createdAt` as `Int(now().timeIntervalSince1970)`; every `now` used here is a
//     whole second, so truncation and rounding agree.
//  2. The stored string is exactly what `JSONSerialization` writes with `.sortedKeys` and no other
//     option, for the values of these fixtures (none contains a slash or a non-ASCII character).
//  3. `PersonalEventSheetModel.save()` completes synchronously: when it returns, `phase` is `.saved`
//     or `.failed`. The store is synchronous (§9.3), so nothing in the save needs to suspend.
//  4. "Not read" is observed through a `UserDefaults` subclass that records the keys passed to its
//     getters (`object`, `string`, `data`, `array`, `dictionary`, `value(forKey:)`). An
//     implementation that reaches the stored value by another route (`dictionaryRepresentation`,
//     `persistentDomain`) would not be seen by this check.
//  5. An unreadable element is written back as the same JSON object it was parsed as. Its place in
//     the array relative to the readable elements is not asserted.
//
// Synthetic values only: the one Fixture Person (stage 1 §13) with the eight events of §13.1.

import XCTest
import StrandAnalytics
import WhoopStore
@testable import Strand

// MARK: - The §13.1 fixture, for the app target

/// The eight events of stage-5.md §13.1, the JSON shape of §9.2, and the defaults helpers every
/// stage 5 app test shares. Every value is invented.
enum PersonalEventAppFixture {

    static let british = Locale(identifier: "en_GB")
    static let utc = TimeZone(identifier: "UTC")!

    /// `e1` … `e8` padded to sixteen lowercase hex characters (§13.1).
    static func id(_ n: Int) -> String {
        let head = "e" + String(n, radix: 16)
        return head + String(repeating: "0", count: 16 - head.count)
    }

    static func make(_ id: String, _ kind: PersonalEventKind, _ startDay: String, _ endDay: String?,
                     label: String? = nil, note: String? = nil, sensitive: Bool = false,
                     createdAt: Int = 0) -> PersonalEvent {
        PersonalEvent(id: id, kind: kind, label: label, startDay: startDay, endDay: endDay,
                      note: note, sensitive: sensitive, createdAt: createdAt)
    }

    static let e1 = make(id(1), .travel, "2031-03-10", "2031-03-16", note: "Fixture trip", createdAt: 1000)
    static let e2 = make(id(2), .deload, "2031-02-03", "2031-02-09", createdAt: 1001)
    static let e3 = make(id(3), .dietBreak, "2031-04-14", "2031-04-27", createdAt: 1002)
    static let e4 = make(id(4), .supplementChange, "2031-01-22", "2031-01-22", createdAt: 1003)
    static let e5 = make(id(5), .illness, "2031-05-19", nil, sensitive: true, createdAt: 1004)
    static let e6 = make(id(6), .custom, "2031-03-26", "2031-03-26", label: "Fixture change",
                         note: "Fixture note", sensitive: true, createdAt: 1005)
    static let e7 = make(id(7), .travel, "2030-12-01", "2030-12-07", createdAt: 1006)
    static let e8 = make(id(8), .travel, "2031-02-22", "2031-02-24", createdAt: 1007)

    /// §13.1 in table order.
    static let all = [e1, e2, e3, e4, e5, e6, e7, e8]
    /// The same eight in `normalized` order (ascending start day; no two share one).
    static let allNormalized = [e7, e4, e2, e8, e1, e6, e3, e5]

    /// V9: E2 and E3 marked private.
    static let v9: [PersonalEvent] = all.map { event in
        guard event.id == id(2) || event.id == id(3) else { return event }
        return make(event.id, event.kind, event.startDay, event.endDay, label: event.label, note: event.note,
                    sensitive: true, createdAt: event.createdAt)
    }

    /// The three needles of §12.5: the private label, the private note, and the ordinary note.
    static let privateLabel = "Fixture change"
    static let privateNote = "Fixture note"
    static let ordinaryNote = "Fixture trip"
    static let privateNeedles = [privateLabel, privateNote]

    /// The words of §11 that name a kind, and the raw values.
    static let kindWords = ["Travel", "Illness", "Diet break", "Deload", "Supplement change", "Something else",
                            "travel", "illness", "dietBreak", "deload", "supplementChange", "custom"]

    /// The line every fixture event prints outside the Events screen in a 2031 "today" on or after its
    /// start (§10.5, the design model of design/round-s5-events/model.js). E5 is the ongoing case.
    static let outsideLine2031: [String: String] = [
        id(1): "Travel · 10 – 16 Mar",
        id(2): "Deload · 3 – 9 Feb",
        id(3): "Diet break · 14 – 27 Apr",
        id(4): "Supplement change · 22 Jan",
        id(5): "Private event · since 19 May",
        id(6): "Private event · 26 Mar",
        id(7): "Travel · 1 – 7 Dec 2030",
        id(8): "Travel · 22 – 24 Feb",
    ]

    // MARK: The stored shape of §9.2

    private static func quoted(_ text: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed])
        return String(decoding: data, as: UTF8.self)
    }

    /// One stored element, written out key by key in sorted order, `endDay`, `label` and `note`
    /// omitted when nil, `v` 1.
    static func element(_ e: PersonalEvent) -> String {
        var parts = ["\"createdAt\":\(e.createdAt)"]
        if let end = e.endDay { parts.append("\"endDay\":\(quoted(end))") }
        parts.append("\"id\":\(quoted(e.id))")
        parts.append("\"kind\":\(quoted(e.kind.rawValue))")
        if let label = e.label { parts.append("\"label\":\(quoted(label))") }
        if let note = e.note { parts.append("\"note\":\(quoted(note))") }
        parts.append("\"sensitive\":\(e.sensitive ? "true" : "false")")
        parts.append("\"startDay\":\(quoted(e.startDay))")
        parts.append("\"v\":1")
        return "{" + parts.joined(separator: ",") + "}"
    }

    /// The stored string of a list, elements in the order given.
    static func stored(_ events: [PersonalEvent], extra: [String] = []) -> String {
        "[" + (events.map(element) + extra).joined(separator: ",") + "]"
    }

    /// An element no reader understands: kind `somethingNew` (V6).
    static let unknownKindElement =
        #"{"createdAt":1100,"id":"00000000000000ff","kind":"somethingNew","sensitive":false,"startDay":"2031-03-01","v":1}"#
    static let higherVersionElement =
        #"{"createdAt":1101,"id":"00000000000000fe","kind":"travel","sensitive":false,"startDay":"2031-03-02","v":2}"#
    static let wrongTypeElement =
        #"{"createdAt":1102,"id":"00000000000000fd","kind":"travel","sensitive":"no","startDay":"2031-03-03","v":1}"#
    static let issueElement =
        #"{"createdAt":1103,"endDay":"2031-03-01","id":"00000000000000fc","kind":"travel","sensitive":false,"startDay":"2031-03-04","v":1}"#

    /// The array a stored string parses to, as Foundation objects (for order-free comparisons).
    static func parsed(_ text: String?) -> [NSDictionary]? {
        guard let text, let data = text.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return nil }
        return array.compactMap { $0 as? NSDictionary }
    }

    static func parsedElement(_ text: String) -> NSDictionary {
        try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! NSDictionary
    }

    // MARK: Clocks

    /// A whole-second instant from an ISO 8601 string with a zone.
    static func instant(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    /// Noon UTC of a day key: a day-key test's "now" with no midnight near it.
    static func noon(_ day: String) -> Date { instant(day + "T12:00:00Z") }
}

/// A defaults suite that records the keys its getters and setters are given, and can run a closure
/// at the moment a value is written (to act "during" a store write).
final class PersonalEventRecordingDefaults: UserDefaults {
    var reads: [String] = []
    var writes: [String] = []
    var onWrite: ((String) -> Void)?

    override func object(forKey defaultName: String) -> Any? {
        reads.append(defaultName); return super.object(forKey: defaultName)
    }
    override func string(forKey defaultName: String) -> String? {
        reads.append(defaultName); return super.string(forKey: defaultName)
    }
    override func data(forKey defaultName: String) -> Data? {
        reads.append(defaultName); return super.data(forKey: defaultName)
    }
    override func array(forKey defaultName: String) -> [Any]? {
        reads.append(defaultName); return super.array(forKey: defaultName)
    }
    override func dictionary(forKey defaultName: String) -> [String: Any]? {
        reads.append(defaultName); return super.dictionary(forKey: defaultName)
    }
    override func value(forKey key: String) -> Any? {
        reads.append(key); return super.value(forKey: key)
    }
    override func set(_ value: Any?, forKey defaultName: String) {
        writes.append(defaultName); onWrite?(defaultName); super.set(value, forKey: defaultName)
    }
    override func set(_ value: Bool, forKey defaultName: String) {
        writes.append(defaultName); onWrite?(defaultName); super.set(value, forKey: defaultName)
    }
    override func removeObject(forKey defaultName: String) {
        writes.append(defaultName); onWrite?(defaultName); super.removeObject(forKey: defaultName)
    }
}

/// Saves and restores the two stage 5 keys of the runner's standard defaults around a test that has
/// to use them (the `.shared` store and the static flag are over `.standard`).
@MainActor
struct PersonalEventStandardKeys {
    private let saved: [String: Any?]

    init() {
        var saved: [String: Any?] = [:]
        for key in [PersonalEventStore.enabledKey, PersonalEventStore.itemsKey] {
            saved[key] = UserDefaults.standard.object(forKey: key)
        }
        self.saved = saved
    }

    func restore() {
        for (key, value) in saved {
            if let value { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }
}

// MARK: - Store tests

@MainActor
final class PersonalEventStoreTests: XCTestCase {

    private typealias Fx = PersonalEventAppFixture

    private var suites: [String] = []
    private var standardKeys: PersonalEventStandardKeys?

    override func tearDown() {
        for name in suites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        suites = []
        standardKeys?.restore()
        standardKeys = nil
        super.tearDown()
    }

    // MARK: Helpers

    private func suite(flag: Bool? = nil) throws -> UserDefaults {
        let name = "PersonalEventStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        suites.append(name)
        if let flag { defaults.set(flag, forKey: PersonalEventStore.enabledKey) }
        return defaults
    }

    private func recordingSuite(flag: Bool? = nil) throws -> PersonalEventRecordingDefaults {
        let name = "PersonalEventStoreTests-recording-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(PersonalEventRecordingDefaults(suiteName: name))
        suites.append(name)
        if let flag { defaults.set(flag, forKey: PersonalEventStore.enabledKey) }
        defaults.reads = []
        defaults.writes = []
        return defaults
    }

    /// A store whose ids come from `ids` in order and whose clock reads `now`.
    private func makeStore(_ defaults: UserDefaults, ids: [String] = [], now: Date = Fx.instant("2031-03-12T09:00:00Z"))
        -> PersonalEventStore {
        var queue = ids
        return PersonalEventStore(defaults: defaults, now: { now }, makeId: {
            queue.isEmpty ? PersonalEventStore.randomId() : queue.removeFirst()
        })
    }

    private func storedText(_ defaults: UserDefaults) -> String? {
        defaults.object(forKey: PersonalEventStore.itemsKey) as? String
    }

    private func assertThrows(_ expected: PersonalEventStoreError, _ message: String = "",
                              file: StaticString = #filePath, line: UInt = #line, _ body: () throws -> Void) {
        do {
            try body()
            XCTFail("expected \(expected) \(message)", file: file, line: line)
        } catch let error as PersonalEventStoreError {
            XCTAssertEqual(error, expected, message, file: file, line: line)
        } catch {
            XCTFail("expected \(expected), got \(error) \(message)", file: file, line: line)
        }
    }

    /// The stored elements by id, so a test can say "this one changed and no other did".
    private func elementsById(_ defaults: UserDefaults) -> [String: NSDictionary] {
        var out: [String: NSDictionary] = [:]
        for element in Fx.parsed(storedText(defaults)) ?? [] {
            if let id = element["id"] as? String { out[id] = element }
        }
        return out
    }

    // MARK: Keys and flag (§9.1, §9.3)

    func testKeysAreTheSpecifiedOnes() {
        XCTAssertEqual(PersonalEventStore.enabledKey, "noop.personalEventsEnabled")
        XCTAssertEqual(PersonalEventStore.itemsKey, "personalEvents.items")
    }

    func testFlagDefaultsToOff() throws {
        let defaults = try suite()
        let store = makeStore(defaults)
        XCTAssertFalse(store.isEnabled)
        XCTAssertEqual(store.events, [])
        XCTAssertNil(defaults.object(forKey: PersonalEventStore.enabledKey), "reading the flag stores nothing")
        XCTAssertNil(defaults.object(forKey: PersonalEventStore.itemsKey), "reading the list stores nothing")
    }

    func testStoreFlagIsAnObservableDefaultsFlagOverTheEnabledKey() {
        standardKeys = PersonalEventStandardKeys()
        UserDefaults.standard.removeObject(forKey: PersonalEventStore.enabledKey)
        let flag: ObservableDefaultsFlag = PersonalEventStore.flag
        XCTAssertTrue(PersonalEventStore.flag === flag, "one observable copy")
        XCTAssertEqual(flag.key, PersonalEventStore.enabledKey)
        XCTAssertFalse(flag.isEnabled)

        UserDefaults.standard.set(true, forKey: PersonalEventStore.enabledKey)   // another writer
        XCTAssertTrue(flag.isEnabled, "the flag follows a write it did not make")
        XCTAssertTrue(PersonalEventStore.shared.isEnabled, "the shared store reads the same key")

        flag.set(false)
        XCTAssertEqual(UserDefaults.standard.object(forKey: PersonalEventStore.enabledKey) as? Bool, false)
        XCTAssertFalse(PersonalEventStore.shared.isEnabled)
        flag.set(true)
        XCTAssertEqual(UserDefaults.standard.object(forKey: PersonalEventStore.enabledKey) as? Bool, true)
    }

    /// Fault F11. With the flag off the items key is neither read nor written, whatever it holds.
    func testEventsAreEmptyAndTheKeyIsNotReadWhileTheFlagIsOff() throws {
        for flag in [false, nil] as [Bool?] {
            let defaults = try recordingSuite(flag: flag)
            let text = Fx.stored(Fx.allNormalized)
            defaults.set(text, forKey: PersonalEventStore.itemsKey)
            defaults.reads = []
            defaults.writes = []

            let store = makeStore(defaults)
            XCTAssertFalse(store.isEnabled)
            XCTAssertEqual(store.events, [], "flag \(String(describing: flag)): no events")
            XCTAssertEqual(store.events, [], "a second read is the same")
            XCTAssertFalse(defaults.reads.contains(PersonalEventStore.itemsKey),
                           "flag \(String(describing: flag)): the items key was read: \(defaults.reads)")
            XCTAssertEqual(defaults.writes, [], "nothing is written")
            XCTAssertEqual(storedText(defaults), text, "the stored list is kept")
        }
    }

    // MARK: Writes (§9.2, §9.3)

    func testAddWritesSortedKeysAndNormalizedOrder() throws {
        let defaults = try suite(flag: true)
        let store = makeStore(defaults, ids: [Fx.id(1), Fx.id(7), Fx.id(6)], now: Date(timeIntervalSince1970: 1_930_000_000))

        let first = try store.add(kind: .travel, label: nil, startDay: "2031-03-10", endDay: "2031-03-16",
                                  note: "Fixture trip", sensitive: false)
        XCTAssertEqual(first, Fx.make(Fx.id(1), .travel, "2031-03-10", "2031-03-16", note: "Fixture trip",
                                      createdAt: 1_930_000_000))
        XCTAssertEqual(storedText(defaults),
                       #"[{"createdAt":1930000000,"endDay":"2031-03-16","id":"e100000000000000","kind":"travel","note":"Fixture trip","sensitive":false,"startDay":"2031-03-10","v":1}]"#,
                       "§9.2: sorted keys, no whitespace, nil fields omitted, v 1")

        try store.add(kind: .travel, label: nil, startDay: "2030-12-01", endDay: "2030-12-07", note: nil, sensitive: false)
        try store.add(kind: .custom, label: "Fixture change", startDay: "2031-03-26", endDay: "2031-03-26",
                      note: "Fixture note", sensitive: true)

        let e7 = Fx.make(Fx.id(7), .travel, "2030-12-01", "2030-12-07", createdAt: 1_930_000_000)
        let e1 = Fx.make(Fx.id(1), .travel, "2031-03-10", "2031-03-16", note: "Fixture trip", createdAt: 1_930_000_000)
        let e6 = Fx.make(Fx.id(6), .custom, "2031-03-26", "2031-03-26", label: "Fixture change", note: "Fixture note",
                         sensitive: true, createdAt: 1_930_000_000)
        XCTAssertEqual(storedText(defaults), Fx.stored([e7, e1, e6]), "elements in normalized order")
        XCTAssertEqual(store.events, [e7, e1, e6])
    }

    func testAddTrimsLabelAndNoteAndTurnsAnEmptyNoteIntoNil() throws {
        let defaults = try suite(flag: true)
        let store = makeStore(defaults, ids: [Fx.id(6), Fx.id(1)], now: Date(timeIntervalSince1970: 1005))

        let custom = try store.add(kind: .custom, label: " \n Fixture change\t ", startDay: "2031-03-26",
                                   endDay: "2031-03-26", note: "\n Fixture note  \n", sensitive: true)
        XCTAssertEqual(custom.label, "Fixture change")
        XCTAssertEqual(custom.note, "Fixture note")

        let travel = try store.add(kind: .travel, label: nil, startDay: "2031-03-10", endDay: "2031-03-16",
                                   note: " \n\t ", sensitive: false)
        XCTAssertNil(travel.note, "a blank note is stored as no note")
        XCTAssertEqual(store.events, [
            Fx.make(Fx.id(1), .travel, "2031-03-10", "2031-03-16", createdAt: 1005),
            Fx.make(Fx.id(6), .custom, "2031-03-26", "2031-03-26", label: "Fixture change", note: "Fixture note",
                    sensitive: true, createdAt: 1005),
        ])
        XCTAssertFalse(storedText(defaults)?.contains("\"note\":\"\"") ?? true, "no empty note is stored")
        XCTAssertEqual(elementsById(defaults)[Fx.id(1)]?["note"] as? String, nil, "the key is omitted")
    }

    func testAddOfAnInvalidEventThrowsAndWritesNothing() throws {
        // An empty store: nothing is created.
        let empty = try suite(flag: true)
        let emptyStore = makeStore(empty)
        assertThrows(.invalid([.endBeforeStart])) {
            try emptyStore.add(kind: .travel, label: nil, startDay: "2031-03-10", endDay: "2031-03-09", note: nil,
                               sensitive: false)
        }
        XCTAssertNil(empty.object(forKey: PersonalEventStore.itemsKey), "no key is created by a refused add")

        // A stored list: its bytes are unchanged by every refusal.
        let defaults = try suite(flag: true)
        let text = Fx.stored(Fx.allNormalized)
        defaults.set(text, forKey: PersonalEventStore.itemsKey)
        let store = makeStore(defaults)
        let revision = store.revision
        let cases: [(PersonalEventStoreError, () throws -> Void)] = [
            (.invalid([.endBeforeStart]), {   // V3
                try store.add(kind: .travel, label: nil, startDay: "2031-03-10", endDay: "2031-03-09", note: nil,
                              sensitive: false)
            }),
            (.invalid([.missingLabel]), {
                try store.add(kind: .custom, label: "  ", startDay: "2031-03-10", endDay: nil, note: nil, sensitive: true)
            }),
            (.invalid([.unexpectedLabel]), {
                try store.add(kind: .deload, label: "Fixture label", startDay: "2031-03-10", endDay: nil, note: nil,
                              sensitive: false)
            }),
            (.invalid([.invalidStartDay]), {
                try store.add(kind: .travel, label: nil, startDay: "2031-3-10", endDay: nil, note: nil, sensitive: false)
            }),
            (.invalid([.invalidEndDay]), {
                try store.add(kind: .travel, label: nil, startDay: "2031-03-10", endDay: "2031-02-30", note: nil,
                              sensitive: false)
            }),
            (.invalid([.labelTooLong]), {
                try store.add(kind: .custom, label: String(repeating: "x", count: 41), startDay: "2031-03-10",
                              endDay: nil, note: nil, sensitive: true)
            }),
            (.invalid([.noteTooLong]), {
                try store.add(kind: .travel, label: nil, startDay: "2031-03-10", endDay: nil,
                              note: String(repeating: "n", count: 281), sensitive: false)
            }),
        ]
        for (expected, body) in cases {
            assertThrows(expected) { try body() }
            XCTAssertEqual(storedText(defaults), text, "\(expected): nothing written")
        }
        XCTAssertEqual(store.revision, revision, "a refused write does not move the revision")
        XCTAssertEqual(store.events, Fx.allNormalized)
    }

    func testUpdateKeepsIdAndCreatedAt() throws {
        let defaults = try suite(flag: true)
        defaults.set(Fx.stored(Fx.allNormalized), forKey: PersonalEventStore.itemsKey)
        let store = makeStore(defaults)
        let before = elementsById(defaults)

        // The owner turns the trip into a deload with a new range; the caller's createdAt is ignored.
        let edited = Fx.make(Fx.id(1), .deload, "2031-03-11", "2031-03-17", note: "  Fixture trip  ",
                             sensitive: true, createdAt: 99)
        try store.update(edited)

        let expected = Fx.make(Fx.id(1), .deload, "2031-03-11", "2031-03-17", note: "Fixture trip",
                               sensitive: true, createdAt: 1000)
        XCTAssertEqual(store.events.first { $0.id == Fx.id(1) }, expected, "id and createdAt kept; note trimmed")
        let after = elementsById(defaults)
        XCTAssertEqual(after.count, 8, "one element per id, before and after")
        XCTAssertEqual(Fx.parsed(storedText(defaults))?.count, 8)
        for id in before.keys where id != Fx.id(1) {
            XCTAssertEqual(after[id], before[id], "\(id) is untouched")
        }
        XCTAssertEqual(after[Fx.id(1)], Fx.parsedElement(Fx.element(expected)))

        // An update that would make the event invalid is refused and changes nothing.
        let text = storedText(defaults)
        assertThrows(.invalid([.endBeforeStart])) {
            try store.update(Fx.make(Fx.id(1), .deload, "2031-03-11", "2031-03-01", createdAt: 1000))
        }
        XCTAssertEqual(storedText(defaults), text)
    }

    func testUpdateOfAMissingIdThrowsNotFound() throws {
        let defaults = try suite(flag: true)
        let text = Fx.stored(Fx.allNormalized)
        defaults.set(text, forKey: PersonalEventStore.itemsKey)
        let store = makeStore(defaults)
        assertThrows(.notFound) {
            try store.update(Fx.make("0123456789abcdef", .travel, "2031-03-10", nil, createdAt: 1))
        }
        XCTAssertEqual(storedText(defaults), text)
        assertThrows(.notFound) { try store.delete(id: "0123456789abcdef") }
        XCTAssertEqual(storedText(defaults), text)
    }

    func testDeleteRemovesOnlyThatEvent() throws {
        let defaults = try suite(flag: true)
        defaults.set(Fx.stored(Fx.allNormalized), forKey: PersonalEventStore.itemsKey)
        let store = makeStore(defaults)
        let before = elementsById(defaults)
        XCTAssertEqual(before.count, 8)

        try store.delete(id: Fx.id(6))

        let after = elementsById(defaults)
        XCTAssertEqual(after.count, 7, "eight elements before, seven after")
        XCTAssertNil(after[Fx.id(6)])
        for id in before.keys where id != Fx.id(6) {
            XCTAssertEqual(after[id], before[id], "\(id) is untouched")
        }
        XCTAssertEqual(store.events, Fx.allNormalized.filter { $0.id != Fx.id(6) })
        XCTAssertEqual(storedText(defaults), Fx.stored(Fx.allNormalized.filter { $0.id != Fx.id(6) }))

        assertThrows(.notFound, "a second delete of the same id") { try store.delete(id: Fx.id(6)) }
        XCTAssertEqual(elementsById(defaults).count, 7)
    }

    func testSameListGivesSameBytes() throws {
        let now = Date(timeIntervalSince1970: 1_930_000_000)
        let a = try suite(flag: true)
        let b = try suite(flag: true)
        let storeA = makeStore(a, ids: [Fx.id(1), Fx.id(2), Fx.id(3)], now: now)
        let storeB = makeStore(b, ids: [Fx.id(3), Fx.id(2), Fx.id(1)], now: now)

        try storeA.add(kind: .travel, label: nil, startDay: "2031-03-10", endDay: "2031-03-16", note: "Fixture trip",
                       sensitive: false)
        try storeA.add(kind: .deload, label: nil, startDay: "2031-02-03", endDay: "2031-02-09", note: nil, sensitive: false)
        try storeA.add(kind: .dietBreak, label: nil, startDay: "2031-04-14", endDay: "2031-04-27", note: nil,
                       sensitive: false)
        // The same three, entered in the other order.
        try storeB.add(kind: .dietBreak, label: nil, startDay: "2031-04-14", endDay: "2031-04-27", note: nil,
                       sensitive: false)
        try storeB.add(kind: .deload, label: nil, startDay: "2031-02-03", endDay: "2031-02-09", note: nil, sensitive: false)
        try storeB.add(kind: .travel, label: nil, startDay: "2031-03-10", endDay: "2031-03-16", note: "Fixture trip",
                       sensitive: false)

        XCTAssertNotNil(storedText(a))
        XCTAssertEqual(storedText(a), storedText(b), "equal lists give equal bytes")

        // A delete and a re-add of an equal event returns to the same bytes.
        let text = storedText(a)
        let removed = try XCTUnwrap(storeA.events.first { $0.id == Fx.id(2) })
        try storeA.delete(id: Fx.id(2))
        a.set(Fx.stored([removed] + storeA.events), forKey: PersonalEventStore.itemsKey)   // out of order on purpose
        try storeA.update(removed)
        XCTAssertEqual(storedText(a), text, "a save rewrites the list in normalized order")
    }

    // MARK: Unreadable entries and an unreadable store (§9.2, faults F9 and F10)

    func testUnreadableElementIsKeptVerbatimAcrossAddUpdateAndDelete() throws {
        let defaults = try suite(flag: true)
        defaults.set(Fx.stored([Fx.e1], extra: [Fx.unknownKindElement]), forKey: PersonalEventStore.itemsKey)
        let store = makeStore(defaults, ids: [Fx.id(2)], now: Date(timeIntervalSince1970: 1001))
        let kept = Fx.parsedElement(Fx.unknownKindElement)

        func assertKept(_ stage: String, file: StaticString = #filePath, line: UInt = #line) {
            let elements = Fx.parsed(storedText(defaults)) ?? []
            XCTAssertEqual(elements.filter { $0 == kept }.count, 1, "\(stage): the unreadable element is kept once",
                           file: file, line: line)
            XCTAssertTrue(storedText(defaults)?.contains(Fx.unknownKindElement) ?? false,
                          "\(stage): its bytes are written back unchanged", file: file, line: line)
            XCTAssertEqual(store.unreadableEntryCount, 1, stage, file: file, line: line)
            XCTAssertFalse(store.needsAttention, stage, file: file, line: line)
            XCTAssertFalse(store.events.contains { $0.id == "00000000000000ff" }, "\(stage): never shown",
                           file: file, line: line)
        }

        assertKept("before")
        try store.add(kind: .deload, label: nil, startDay: "2031-02-03", endDay: "2031-02-09", note: nil, sensitive: false)
        assertKept("after add")
        XCTAssertEqual(store.events.map(\.id), [Fx.id(2), Fx.id(1)])
        try store.update(Fx.make(Fx.id(1), .travel, "2031-03-10", "2031-03-17", createdAt: 1000))
        assertKept("after update")
        try store.delete(id: Fx.id(2))
        assertKept("after delete")
        try store.delete(id: Fx.id(1))
        assertKept("after the last readable event is deleted")
        XCTAssertEqual(store.events, [])
        XCTAssertEqual(Fx.parsed(storedText(defaults))?.count, 1, "the key still holds the unreadable element")
    }

    /// V6 and the other unreadable shapes: kept, counted, never shown, preserved through a save.
    func testElementWithAHigherVersionOrUnknownKindIsKeptAndNotShown() throws {
        let defaults = try suite(flag: true)
        let extras = [Fx.unknownKindElement, Fx.higherVersionElement, Fx.wrongTypeElement, Fx.issueElement]
        defaults.set(Fx.stored(Fx.all, extra: extras), forKey: PersonalEventStore.itemsKey)
        let store = makeStore(defaults)

        XCTAssertEqual(store.events, Fx.allNormalized, "the eight fixture events are read")
        XCTAssertEqual(store.unreadableEntryCount, 4)
        XCTAssertFalse(store.needsAttention)

        try store.delete(id: Fx.id(7))
        let elements = Fx.parsed(storedText(defaults)) ?? []
        XCTAssertEqual(elements.count, 7 + 4, "seven readable and four unreadable after the delete")
        for extra in extras {
            XCTAssertEqual(elements.filter { $0 == Fx.parsedElement(extra) }.count, 1, "\(extra) is kept")
        }
        XCTAssertEqual(store.unreadableEntryCount, 4)
    }

    func testNonArrayStoredValueNeedsAttentionAndRefusesEveryWrite() throws {
        let unreadable: [Any] = ["{", #"{"a":1}"#, "\"text\"", "", 5, Data([0x5B, 0x5D]), ["not", "a", "string"]]
        for value in unreadable {
            let defaults = try suite(flag: true)
            defaults.set(value, forKey: PersonalEventStore.itemsKey)
            let stored = defaults.object(forKey: PersonalEventStore.itemsKey) as? NSObject
            let store = makeStore(defaults)
            let label = "\(value)"

            XCTAssertTrue(store.needsAttention, label)
            XCTAssertEqual(store.events, [], label)
            if let text = value as? String {
                XCTAssertEqual(store.rawStoredText, text, "\(label): the raw text is offered for copying")
            }
            assertThrows(.storeUnreadable, label) {
                try store.add(kind: .travel, label: nil, startDay: "2031-03-10", endDay: nil, note: nil, sensitive: false)
            }
            assertThrows(.storeUnreadable, label) { try store.update(Fx.e1) }
            assertThrows(.storeUnreadable, label) { try store.delete(id: Fx.id(1)) }
            XCTAssertEqual(defaults.object(forKey: PersonalEventStore.itemsKey) as? NSObject, stored,
                           "\(label): nothing is overwritten")
        }
    }

    func testDiscardRemovesTheKeyOnlyWhileUnreadable() throws {
        // Readable: refused, nothing removed.
        let readable = try suite(flag: true)
        let text = Fx.stored(Fx.allNormalized, extra: [Fx.unknownKindElement])
        readable.set(text, forKey: PersonalEventStore.itemsKey)
        let readableStore = makeStore(readable)
        XCTAssertFalse(readableStore.discardUnreadableStore())
        XCTAssertEqual(storedText(readable), text, "a readable list with an unreadable entry is never discarded")

        // No key at all: nothing to discard.
        let absent = try suite(flag: true)
        XCTAssertFalse(makeStore(absent).discardUnreadableStore())

        // Unreadable: removed, and the store is usable again.
        let broken = try suite(flag: true)
        broken.set("{", forKey: PersonalEventStore.itemsKey)
        let brokenStore = makeStore(broken, ids: [Fx.id(1)], now: Date(timeIntervalSince1970: 1000))
        XCTAssertTrue(brokenStore.discardUnreadableStore())
        XCTAssertNil(broken.object(forKey: PersonalEventStore.itemsKey))
        XCTAssertFalse(brokenStore.needsAttention)
        XCTAssertEqual(brokenStore.events, [])
        try brokenStore.add(kind: .travel, label: nil, startDay: "2031-03-10", endDay: "2031-03-16",
                            note: "Fixture trip", sensitive: false)
        XCTAssertEqual(brokenStore.events, [Fx.e1])
        XCTAssertFalse(brokenStore.discardUnreadableStore(), "readable again: refused")
    }

    func testReadingNeverWrites() throws {
        let values: [Any?] = [nil, Fx.stored(Fx.all), Fx.stored(Fx.all, extra: [Fx.unknownKindElement]), "{", 5]
        for value in values {
            let defaults = try recordingSuite(flag: true)
            if let value { defaults.set(value, forKey: PersonalEventStore.itemsKey) }
            let before = defaults.persistentDomain(forName: suites.last!) as NSDictionary?
            defaults.writes = []

            let store = makeStore(defaults)
            _ = store.isEnabled
            _ = store.events
            _ = store.unreadableEntryCount
            _ = store.needsAttention
            _ = store.rawStoredText
            _ = store.revision
            _ = store.events

            XCTAssertEqual(defaults.writes, [], "\(String(describing: value)): reading wrote \(defaults.writes)")
            XCTAssertEqual(defaults.persistentDomain(forName: suites.last!) as NSDictionary?, before)
        }
    }

    /// The restore path: a string written by someone else is seen at once, and the revision moves.
    func testRevisionMovesWhenAnotherWriterChangesTheKey() throws {
        let defaults = try suite(flag: true)
        defaults.set(Fx.stored([Fx.e1]), forKey: PersonalEventStore.itemsKey)
        let store = makeStore(defaults, ids: [Fx.id(2)])
        XCTAssertEqual(store.events, [Fx.e1])

        let r0 = store.revision
        defaults.set(Fx.stored([Fx.e2, Fx.e1]), forKey: PersonalEventStore.itemsKey)   // a restore
        let r1 = store.revision
        XCTAssertNotEqual(r1, r0, "another writer's change moves the revision")
        XCTAssertEqual(store.events, [Fx.e2, Fx.e1], "and is read at the next access: nothing is cached")

        defaults.set("an unrelated value", forKey: "personalEventsTests.unrelated")
        XCTAssertEqual(store.revision, r1, "a change to another key does not move it")
        defaults.set(Fx.stored([Fx.e2, Fx.e1]), forKey: PersonalEventStore.itemsKey)
        XCTAssertEqual(store.revision, r1, "writing the same string again does not move it")

        try store.add(kind: .dietBreak, label: nil, startDay: "2031-04-14", endDay: "2031-04-27", note: nil,
                      sensitive: false)
        let r2 = store.revision
        XCTAssertNotEqual(r2, r1, "the store's own write moves it")

        defaults.removeObject(forKey: PersonalEventStore.itemsKey)
        XCTAssertNotEqual(store.revision, r2, "a removal moves it")
        XCTAssertEqual(store.events, [])
    }

    func testSwitchingTheFlagOffKeepsTheStoredEvents() throws {
        let defaults = try suite(flag: true)
        let store = makeStore(defaults, ids: [Fx.id(1), Fx.id(5)], now: Date(timeIntervalSince1970: 1000))
        try store.add(kind: .travel, label: nil, startDay: "2031-03-10", endDay: "2031-03-16", note: "Fixture trip",
                      sensitive: false)
        try store.add(kind: .illness, label: nil, startDay: "2031-05-19", endDay: nil, note: nil, sensitive: true)
        let text = storedText(defaults)
        let events = store.events
        XCTAssertEqual(events.count, 2)

        defaults.set(false, forKey: PersonalEventStore.enabledKey)
        XCTAssertFalse(store.isEnabled)
        XCTAssertEqual(store.events, [])
        XCTAssertEqual(storedText(defaults), text, "switching off deletes nothing")

        defaults.set(true, forKey: PersonalEventStore.enabledKey)
        XCTAssertEqual(store.events, events, "switching back on shows them again")
    }

    /// Fault F12. Contrast `moments`, which deletes beyond 500.
    func testNothingIsTrimmedAtFiveHundredAndOneEvents() throws {
        let defaults = try suite(flag: true)
        let five = (0..<500).map { index -> PersonalEvent in
            Fx.make(String(format: "%016x", index), .travel, "2031-03-10", "2031-03-10", createdAt: index)
        }
        defaults.set(Fx.stored(five), forKey: PersonalEventStore.itemsKey)
        let store = makeStore(defaults, ids: ["ffffffffffffffff"], now: Date(timeIntervalSince1970: 5000))
        XCTAssertEqual(store.events.count, 500)

        try store.add(kind: .deload, label: nil, startDay: "2030-01-01", endDay: nil, note: nil, sensitive: false)

        XCTAssertEqual(store.events.count, 501)
        XCTAssertEqual(Fx.parsed(storedText(defaults))?.count, 501)
        XCTAssertEqual(store.events.first?.id, "ffffffffffffffff", "the oldest start is first, and kept")
        XCTAssertEqual(Set(store.events.map(\.id)), Set(five.map(\.id) + ["ffffffffffffffff"]))
    }

    func testRandomIdIsSixteenLowercaseHexCharacters() {
        var seen = Set<String>()
        for _ in 0..<200 {
            let id = PersonalEventStore.randomId()
            XCTAssertEqual(id.count, 16)
            XCTAssertTrue(id.allSatisfy { "0123456789abcdef".contains($0) }, id)
            seen.insert(id)
        }
        XCTAssertEqual(seen.count, 200, "no repeat in two hundred")
    }

    // MARK: Days, not instants (§7.1, C6)

    private func sheet(_ store: PersonalEventStore, now: Date, zone: @escaping () -> TimeZone) -> PersonalEventSheetModel {
        PersonalEventSheetModel(store: store, editing: nil, now: { now }, timeZone: zone)
    }

    /// Fault F13. The picked date is turned into a key in the zone at the moment of saving.
    func testDayKeyOfThePickedDateUsesTheZoneAtSaveTime() throws {
        let instant = Fx.instant("2031-03-10T20:00:00Z")   // 01:30 on the 11th in Kolkata
        let cases: [(String, String)] = [("UTC", "2031-03-10"), ("Asia/Kolkata", "2031-03-11"),
                                         ("America/Los_Angeles", "2031-03-10"), ("Pacific/Kiritimati", "2031-03-11")]
        for (zoneName, expected) in cases {
            let defaults = try suite(flag: true)
            let store = makeStore(defaults)
            var zone = TimeZone(identifier: "Pacific/Pago_Pago")!   // the zone when the sheet opened
            let model = sheet(store, now: instant, zone: { zone })
            model.draft.start = instant
            model.draft.length = .oneDay
            zone = TimeZone(identifier: zoneName)!                  // the zone when Save is tapped
            model.save()
            XCTAssertEqual(model.phase, .saved, zoneName)
            XCTAssertEqual(store.events.map(\.startDay), [expected], zoneName)
            XCTAssertEqual(store.events.map(\.endDay), [expected], "\(zoneName): one day")
        }
    }

    /// The roadmap's time-zone case (§12.3): saved in one zone, read and overlapped in another.
    func testChangingTheZoneAfterSavingDoesNotMoveAnEvent() throws {
        let defaults = try suite(flag: true)
        let store = makeStore(defaults)
        let kolkata = TimeZone(identifier: "Asia/Kolkata")!
        let model = sheet(store, now: Fx.instant("2031-03-10T04:00:00Z"), zone: { kolkata })
        model.draft.start = Fx.instant("2031-03-10T04:00:00Z")
        model.draft.length = .until
        model.draft.end = Fx.instant("2031-03-16T04:00:00Z")
        model.save()
        XCTAssertEqual(model.phase, .saved)
        let saved = try XCTUnwrap(store.events.first)
        XCTAssertEqual(saved.startDay, "2031-03-10")
        XCTAssertEqual(saved.endDay, "2031-03-16")

        // Read back by a fresh store, a model in another zone and the overlap rules: the same days.
        for zoneName in ["America/Los_Angeles", "Pacific/Kiritimati", "UTC"] {
            let zone = TimeZone(identifier: zoneName)!
            let again = PersonalEventStore(defaults: defaults)
            XCTAssertEqual(again.events, [saved], zoneName)
            let screen = PersonalEventsModel(store: again, now: { Fx.instant("2031-03-12T12:00:00Z") },
                                             timeZone: { zone }, locale: Fx.british)
            screen.reload()
            XCTAssertEqual(screen.presentation.now.map(\.dateText), ["10 – 16 Mar"], zoneName)
            XCTAssertEqual(PersonalEvents.relation(of: saved, firstDay: "2031-03-10", lastDay: "2031-03-16"), .within)
            XCTAssertTrue(PersonalEvents.overlaps(saved, firstDay: "2031-03-16", lastDay: "2031-03-16"))
            XCTAssertFalse(PersonalEvents.overlaps(saved, firstDay: "2031-03-17", lastDay: "2031-03-23"))
        }
    }

    func testEventSavedJustBeforeAndJustAfterLocalMidnightLandsOnDifferentDays() throws {
        let kolkata = TimeZone(identifier: "Asia/Kolkata")!
        let before = Fx.instant("2031-03-10T23:59:59+05:30")
        let after = Fx.instant("2031-03-11T00:00:00+05:30")
        var keys: [String] = []
        for instant in [before, after] {
            let defaults = try suite(flag: true)
            let store = makeStore(defaults)
            let model = sheet(store, now: instant, zone: { kolkata })
            model.draft.start = instant
            model.save()
            XCTAssertEqual(model.phase, .saved)
            keys += store.events.map(\.startDay)
        }
        XCTAssertEqual(keys, ["2031-03-10", "2031-03-11"])
    }

    func testEventAcrossADaylightSavingChangeKeepsItsDays() throws {
        let newYork = TimeZone(identifier: "America/New_York")!
        // 2031: clocks go forward on Sunday 9 March and back on Sunday 2 November.
        let ranges: [(Date, Date, String, String)] = [
            (Fx.instant("2031-03-08T00:30:00-05:00"), Fx.instant("2031-03-10T23:30:00-04:00"), "2031-03-08", "2031-03-10"),
            (Fx.instant("2031-11-01T00:30:00-04:00"), Fx.instant("2031-11-03T23:30:00-05:00"), "2031-11-01", "2031-11-03"),
        ]
        for (start, end, startKey, endKey) in ranges {
            let defaults = try suite(flag: true)
            let store = makeStore(defaults)
            let model = sheet(store, now: start, zone: { newYork })
            model.draft.start = start
            model.draft.length = .until
            model.draft.end = end
            model.save()
            XCTAssertEqual(model.phase, .saved)
            let saved = try XCTUnwrap(store.events.first)
            XCTAssertEqual(saved.startDay, startKey)
            XCTAssertEqual(saved.endDay, endKey)

            // Opening it again for editing and saving it unchanged moves neither day.
            let edit = PersonalEventSheetModel(store: store, editing: saved, now: { end }, timeZone: { newYork })
            edit.save()
            XCTAssertEqual(edit.phase, .saved)
            XCTAssertEqual(store.events, [saved], "an unchanged edit keeps its days across the change")
        }
    }

    #if DEBUG
    /// Ruling A4: this stage reserves `events-` alone, overlapping no other stage's prefix.
    func testTheEventsDemoPrefixIsReservedAndOverlapsNoOther() {
        XCTAssertEqual(DemoScreenPrefixes.events, ["events-"])
        let registry = DemoScreenRegistry<String>([
            .init(prefixes: DemoScreenPrefixes.scorecard, resolve: { _ in nil }),
            .init(prefixes: DemoScreenPrefixes.packet, resolve: { _ in nil }),
            .init(prefixes: DemoScreenPrefixes.events, resolve: { "answered " + $0 }),
        ])
        XCTAssertEqual(registry.conflicts, [])
        XCTAssertEqual(registry.screen(named: "events-l1"), "answered events-l1")
        XCTAssertNil(registry.screen(named: "packet-ready"))
        XCTAssertNil(registry.screen(named: "eventsl1"))
    }
    #endif
}
