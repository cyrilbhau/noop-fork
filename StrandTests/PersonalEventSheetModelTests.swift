// API ASSUMED BY THESE TESTS
//
// Written from docs/personal/superapp/specs/stage-5.md §10.3 and §10.9 before the implementation
// exists. New, in Strand/Data/PersonalEventsModel.swift:
//
//     struct PersonalEventDraft: Equatable {
//         enum Length: Equatable { case oneDay, until, ongoing }
//         var kind: PersonalEventKind = .travel
//         var label: String = ""
//         var start: Date
//         var length: Length = .oneDay
//         var end: Date                  // read only when length == .until
//         var note: String = ""
//         var isPrivate: Bool
//     }
//
//     @MainActor final class PersonalEventSheetModel: ObservableObject {
//         enum Phase: Equatable { case editing, saving, failed(storeUnreadable: Bool), saved }
//         init(store: PersonalEventStore = .shared, editing: PersonalEvent? = nil,
//              now: @escaping () -> Date = Date.init, timeZone: @escaping () -> TimeZone = { .current })
//         @Published var draft: PersonalEventDraft
//         @Published private(set) var phase: Phase
//         func setKind(_ kind: PersonalEventKind)
//         func setPrivate(_ value: Bool)
//         var issues: [PersonalEventIssue] { get }
//         var canSave: Bool { get }
//         var isPlanned: Bool { get }
//         var noteRemaining: Int? { get }
//         func save()
//     }
//
//     PersonalEventsModel.endToday(id:) throws    (Strand/Data/PersonalEventsModel.swift)
//
// The store is `PersonalEventStore` (see PersonalEventStoreTests.swift for its API block).
//
// Behaviour assumed where the specification leaves it unstated:
//
//  1. `save()` completes synchronously (the store is synchronous): when it returns, `phase` is
//     `.saved` or `.failed`. `.saving` is observable only during the store's write.
//  2. A new draft's `start` and `end` are the `now()` instant; a draft opened for editing holds, for
//     each stored day, an instant that falls on that day in `timeZone()`.
//  3. `issues` validates the draft as `add`/`update` would store it: the label only for `.custom`
//     (any other kind stores no label, whatever the field holds), the note trimmed with a blank note
//     stored as nil.
//  4. `noteRemaining` is `280 - count` from a count of 240 characters on, nil below.
//  5. A save that fails with `.notFound` (the event was deleted elsewhere) is
//     `.failed(storeUnreadable: false)`; with `.storeUnreadable`, `.failed(storeUnreadable: true)`.
//     Strings of the sheet (§11 "Sheet" row) have no presenter API in §10.9 and are not asserted.
//
// Not pinnable here: the largest text size (each control on its own row) and the disabled look of
// the controls while saving; the view owns both and decides nothing else.

import XCTest
import StrandAnalytics
import WhoopStore
@testable import Strand

@MainActor
final class PersonalEventSheetModelTests: XCTestCase {

    private typealias Fx = PersonalEventAppFixture

    private var suites: [String] = []
    private let today = PersonalEventAppFixture.noon("2031-03-12")

    override func tearDown() {
        for name in suites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        suites = []
        super.tearDown()
    }

    // MARK: Helpers

    private func makeDefaults(_ stored: Any? = nil, flag: Bool = true) throws -> PersonalEventRecordingDefaults {
        let name = "PersonalEventSheetModelTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(PersonalEventRecordingDefaults(suiteName: name))
        suites.append(name)
        defaults.set(flag, forKey: PersonalEventStore.enabledKey)
        if let stored { defaults.set(stored, forKey: PersonalEventStore.itemsKey) }
        defaults.writes = []
        defaults.reads = []
        return defaults
    }

    private func makeStore(_ defaults: UserDefaults) -> PersonalEventStore {
        let now = today
        return PersonalEventStore(defaults: defaults, now: { now }, makeId: { Fx.id(9) })
    }

    private func sheet(_ store: PersonalEventStore, editing: PersonalEvent? = nil) -> PersonalEventSheetModel {
        let now = today
        return PersonalEventSheetModel(store: store, editing: editing, now: { now }, timeZone: { Fx.utc })
    }

    private func days(_ n: Int) -> Date { today.addingTimeInterval(Double(n) * 86_400) }

    // MARK: §10.3, one test per state

    func testAddFirstOpenHasTheDefaults() throws {
        let model = sheet(makeStore(try makeDefaults()))
        XCTAssertEqual(model.draft.kind, .travel)
        XCTAssertEqual(model.draft.label, "")
        XCTAssertEqual(model.draft.length, .oneDay)
        XCTAssertEqual(model.draft.note, "")
        XCTAssertFalse(model.draft.isPrivate, "travel is not private by default")
        XCTAssertEqual(LocalDayWindows(timeZone: Fx.utc).dayKey(for: model.draft.start), "2031-03-12", "starts today")
        XCTAssertEqual(model.phase, .editing)
        XCTAssertEqual(model.issues, [])
        XCTAssertTrue(model.canSave)
        XCTAssertFalse(model.isPlanned)
        XCTAssertNil(model.noteRemaining)
    }

    func testKindChangeMovesThePrivateSwitchUntilTheOwnerTouchesIt() throws {
        let model = sheet(makeStore(try makeDefaults()))
        model.setKind(.illness)
        XCTAssertTrue(model.draft.isPrivate, "illness is private by default")
        model.setKind(.deload)
        XCTAssertFalse(model.draft.isPrivate)
        model.setKind(.custom)
        XCTAssertTrue(model.draft.isPrivate, "something else is private by default")
        model.setKind(.supplementChange)
        XCTAssertFalse(model.draft.isPrivate)

        model.setPrivate(true)                      // the owner's choice
        model.setKind(.deload)
        XCTAssertTrue(model.draft.isPrivate, "kept as the owner set it (frame S4)")
        model.setKind(.illness)
        model.setPrivate(false)
        model.setKind(.custom)
        XCTAssertFalse(model.draft.isPrivate, "still the owner's choice")
    }

    func testCustomKindNeedsAName() throws {
        let model = sheet(makeStore(try makeDefaults()))
        model.setKind(.custom)
        XCTAssertEqual(model.issues, [.missingLabel])
        XCTAssertFalse(model.canSave)
        model.draft.label = "   "
        XCTAssertEqual(model.issues, [.missingLabel], "a blank name is no name")
        XCTAssertFalse(model.canSave)
        model.draft.label = "Fixture change"
        XCTAssertEqual(model.issues, [])
        XCTAssertTrue(model.canSave)
        model.draft.label = String(repeating: "x", count: 41)
        XCTAssertEqual(model.issues, [.labelTooLong], "forty characters at most")
        model.draft.label = String(repeating: "👨‍👩‍👧", count: 40)
        XCTAssertEqual(model.issues, [], "counted in characters")
    }

    func testANameTypedForAnotherKindIsNotStored() throws {
        let store = makeStore(try makeDefaults())
        let model = sheet(store)
        model.setKind(.custom)
        model.draft.label = "Fixture change"
        model.setKind(.travel)
        XCTAssertEqual(model.issues, [], "a leftover name is not an unexpected label")
        model.save()
        XCTAssertEqual(model.phase, .saved)
        XCTAssertEqual(store.events.map(\.label), [nil])
    }

    func testLengthChoicesGiveOneDayARangeOrOngoing() throws {
        for (length, expectedEnd) in [(PersonalEventDraft.Length.oneDay, "2031-03-12" as String?),
                                      (.until, "2031-03-15"), (.ongoing, nil)] {
            let store = makeStore(try makeDefaults())
            let model = sheet(store)
            model.draft.length = length
            model.draft.end = days(3)
            model.save()
            XCTAssertEqual(model.phase, .saved, "\(length)")
            XCTAssertEqual(store.events.map(\.startDay), ["2031-03-12"])
            XCTAssertEqual(store.events.map(\.endDay), [expectedEnd], "\(length)")
        }
    }

    func testEndBeforeStartDisablesSave() throws {
        let store = makeStore(try makeDefaults())
        let model = sheet(store)
        model.draft.length = .until
        model.draft.end = days(-1)
        XCTAssertEqual(model.issues, [.endBeforeStart])
        XCTAssertFalse(model.canSave)
        model.draft.end = today
        XCTAssertEqual(model.issues, [], "the end may be the start day")
        model.draft.end = days(-1)
        model.draft.length = .oneDay
        XCTAssertEqual(model.issues, [], "the end is read only for Until")
        model.draft.length = .ongoing
        XCTAssertEqual(model.issues, [])
    }

    func testSaveIsDisabledForAnEmptyCustomNameAndForAnEndBeforeTheStart() throws {
        let defaults = try makeDefaults()
        let store = makeStore(defaults)
        let model = sheet(store)
        model.setKind(.custom)
        XCTAssertFalse(model.canSave)
        model.draft.label = "Fixture change"
        model.draft.length = .until
        model.draft.end = days(-2)
        XCTAssertFalse(model.canSave)
        XCTAssertEqual(model.issues, [.endBeforeStart])

        // A save attempted anyway writes nothing.
        model.save()
        XCTAssertNotEqual(model.phase, .saved)
        XCTAssertEqual(store.events, [])
        XCTAssertFalse(defaults.writes.contains(PersonalEventStore.itemsKey))
    }

    func testFutureStartIsAllowedAndSaysPlanned() throws {
        let store = makeStore(try makeDefaults())
        let model = sheet(store)
        XCTAssertFalse(model.isPlanned)
        model.draft.start = days(1)
        XCTAssertTrue(model.isPlanned)
        XCTAssertTrue(model.canSave)
        model.save()
        XCTAssertEqual(model.phase, .saved)
        XCTAssertEqual(store.events.map(\.startDay), ["2031-03-13"])
    }

    func testNoteShowsARemainingCountFrom240Characters() throws {
        let model = sheet(makeStore(try makeDefaults()))
        model.draft.note = String(repeating: "n", count: 239)
        XCTAssertNil(model.noteRemaining)
        model.draft.note = String(repeating: "n", count: 240)
        XCTAssertEqual(model.noteRemaining, 40)
        model.draft.note = String(repeating: "é", count: 280)
        XCTAssertEqual(model.noteRemaining, 0)
        XCTAssertTrue(model.canSave)
        model.draft.note = String(repeating: "n", count: 281)
        XCTAssertEqual(model.issues, [.noteTooLong])
        XCTAssertFalse(model.canSave)
        model.draft.note = "  \n "
        XCTAssertEqual(model.issues, [], "a blank note is no note, not an empty one")
    }

    func testEditOpensWithTheEventsValuesAndCanChangeTheKind() throws {
        let store = makeStore(try makeDefaults(Fx.stored(Fx.allNormalized)))
        let model = sheet(store, editing: Fx.e1)
        let keys = LocalDayWindows(timeZone: Fx.utc)
        XCTAssertEqual(model.draft.kind, .travel)
        XCTAssertEqual(model.draft.label, "")
        XCTAssertEqual(keys.dayKey(for: model.draft.start), "2031-03-10")
        XCTAssertEqual(model.draft.length, .until)
        XCTAssertEqual(keys.dayKey(for: model.draft.end), "2031-03-16")
        XCTAssertEqual(model.draft.note, "Fixture trip")
        XCTAssertFalse(model.draft.isPrivate)

        let custom = sheet(store, editing: Fx.e6)
        XCTAssertEqual(custom.draft.kind, .custom)
        XCTAssertEqual(custom.draft.label, "Fixture change")
        XCTAssertEqual(custom.draft.length, .oneDay)
        XCTAssertTrue(custom.draft.isPrivate)
        XCTAssertEqual(sheet(store, editing: Fx.e5).draft.length, .ongoing)

        model.setKind(.deload)
        model.save()
        XCTAssertEqual(model.phase, .saved)
        let edited = try XCTUnwrap(store.events.first { $0.id == Fx.id(1) })
        XCTAssertEqual(edited, Fx.make(Fx.id(1), .deload, "2031-03-10", "2031-03-16", note: "Fixture trip",
                                       createdAt: 1000), "id and createdAt kept")
        XCTAssertEqual(store.events.count, 8, "an edit adds nothing")
        XCTAssertEqual(store.events.filter { $0.id != Fx.id(1) }, Fx.allNormalized.filter { $0.id != Fx.id(1) })
    }

    func testInputsAreCapturedBeforeTheWrite() throws {
        let defaults = try makeDefaults()
        let store = makeStore(defaults)
        let model = sheet(store)
        model.draft.note = "Fixture trip"
        model.draft.length = .until
        model.draft.end = days(4)

        var phaseDuringWrite: PersonalEventSheetModel.Phase?
        var canSaveDuringWrite: Bool?
        defaults.onWrite = { key in
            guard key == PersonalEventStore.itemsKey, phaseDuringWrite == nil else { return }
            MainActor.assumeIsolated {
                phaseDuringWrite = model.phase
                canSaveDuringWrite = model.canSave
                // The owner keeps typing while the write is in flight.
                model.draft.note = "Fixture changed while saving"
                model.draft.end = self.days(9)
                model.setKind(.deload)
            }
        }
        model.save()
        defaults.onWrite = nil

        XCTAssertEqual(phaseDuringWrite, .saving, "Saving while the write runs")
        XCTAssertEqual(canSaveDuringWrite, false, "buttons disabled while saving")
        XCTAssertEqual(model.phase, .saved)
        XCTAssertEqual(store.events, [Fx.make(Fx.id(9), .travel, "2031-03-12", "2031-03-16", note: "Fixture trip",
                                              createdAt: Int(today.timeIntervalSince1970))],
                       "the values captured when Save was tapped are the ones written")
        XCTAssertEqual(defaults.writes.filter { $0 == PersonalEventStore.itemsKey }.count, 1, "written once")
    }

    func testFailedSaveKeepsTheValues() throws {
        // The store is unreadable: the failure says so.
        let broken = try makeDefaults("{")
        let model = sheet(makeStore(broken))
        model.setKind(.custom)
        model.draft.label = "Fixture change"
        model.draft.note = "Fixture note"
        let draft = model.draft
        model.save()
        XCTAssertEqual(model.phase, .failed(storeUnreadable: true))
        XCTAssertEqual(model.draft, draft, "the values are intact")
        XCTAssertTrue(model.canSave, "Save is the retry")
        XCTAssertEqual(broken.object(forKey: PersonalEventStore.itemsKey) as? String, "{", "nothing overwritten")

        // The event being edited was deleted elsewhere: a plain failure.
        let defaults = try makeDefaults(Fx.stored([Fx.e1]))
        let store = makeStore(defaults)
        let edit = sheet(store, editing: Fx.e1)
        edit.draft.note = "Fixture trip, longer"
        try store.delete(id: Fx.id(1))
        let editDraft = edit.draft
        edit.save()
        XCTAssertEqual(edit.phase, .failed(storeUnreadable: false))
        XCTAssertEqual(edit.draft, editDraft)
        XCTAssertTrue(edit.canSave)
        XCTAssertEqual(store.events, [], "a failed edit does not bring the event back")
    }

    func testSavedMovesTheRevisionOnce() throws {
        let store = makeStore(try makeDefaults())
        let model = sheet(store)
        let revision = store.revision
        model.save()
        XCTAssertEqual(model.phase, .saved)
        XCTAssertNotEqual(store.revision, revision, "the list, charts and note update from the revision")
        XCTAssertEqual(store.events.count, 1)
        XCTAssertFalse(model.canSave, "a saved sheet does not save twice")
    }

    func testEndTodayTurnsAnOngoingEventIntoARange() throws {
        let defaults = try makeDefaults(Fx.stored(Fx.allNormalized))
        let now = Fx.noon("2031-05-28")
        let store = PersonalEventStore(defaults: defaults, now: { now })
        let model = PersonalEventsModel(store: store, now: { now }, timeZone: { Fx.utc }, locale: Fx.british)
        model.reload()
        XCTAssertEqual(model.presentation.now.map(\.offersEndToday), [true])

        try model.endToday(id: Fx.id(5))

        XCTAssertEqual(store.events.first { $0.id == Fx.id(5) },
                       Fx.make(Fx.id(5), .illness, "2031-05-19", "2031-05-28", sensitive: true, createdAt: 1004))
        XCTAssertEqual(store.events.filter { $0.id != Fx.id(5) }, Fx.allNormalized.filter { $0.id != Fx.id(5) },
                       "no other event changes")
        model.reload()
        XCTAssertEqual(model.presentation.now.map(\.dateText), ["19 – 28 May"])
        XCTAssertEqual(model.presentation.now.map(\.offersEndToday), [false], "no action left (frame L3)")

        XCTAssertThrowsError(try model.endToday(id: "0123456789abcdef")) { error in
            XCTAssertEqual(error as? PersonalEventStoreError, .notFound)
        }
    }

    func testEndTodayUsesTheZoneOfTheCall() throws {
        let defaults = try makeDefaults(Fx.stored([Fx.e5]))
        let now = Fx.instant("2031-05-28T20:00:00Z")      // already the 29th in Kolkata
        let store = PersonalEventStore(defaults: defaults, now: { now })
        let model = PersonalEventsModel(store: store, now: { now }, timeZone: { TimeZone(identifier: "Asia/Kolkata")! },
                                        locale: Fx.british)
        try model.endToday(id: Fx.id(5))
        XCTAssertEqual(store.events.map(\.endDay), ["2031-05-29"])
    }
}
