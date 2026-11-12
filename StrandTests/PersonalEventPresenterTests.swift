// API ASSUMED BY THESE TESTS
//
// Written from docs/personal/superapp/specs/stage-5.md §10.2, §10.4, §10.5, §10.9 and §11, and the
// approved frames of design/round-s5-events (model.js is the source of every expected string here),
// before the implementation exists. New, in Strand/Data/PersonalEventPresenter.swift:
//
//     struct PersonalEventRow: Equatable, Identifiable {
//         var id: String; var title: String; var dateText: String; var noteFirstLine: String?
//         var isPrivate: Bool; var offersEndToday: Bool
//     }
//     struct PersonalEventsPresentation: Equatable {
//         enum State: Equatable { case empty, rows, storeUnreadable }
//         var state: State
//         var now: [PersonalEventRow]; var upcoming: [PersonalEventRow]; var earlier: [PersonalEventRow]
//         var unreadableEntriesText: String?; var healthRowValue: String?
//     }
//     struct PersonalEventCaption: Equatable { var lines: [String]; var moreText: String?; var spokenText: String }
//     struct PersonalEventDeleteConfirmation: Equatable {
//         var title: String; var detail: String; var warning: String; var confirmTitle: String; var cancelTitle: String
//     }
//     enum PersonalEventPresenter {
//         static func present(events:today:unreadableEntryCount:needsAttention:locale:) -> PersonalEventsPresentation
//         static func outsideLine(for:locale:) -> String
//         static func caption(events:firstDay:lastDay:today:locale:) -> PersonalEventCaption?
//         static func deleteConfirmation(for:locale:) -> PersonalEventDeleteConfirmation
//         static func kindName(_:locale:) -> String
//     }
//
// New, in Strand/Data/PersonalEventsModel.swift:
//
//     @MainActor final class PersonalEventsModel: ObservableObject {
//         init(store:now:timeZone:locale:)
//         @Published private(set) var presentation: PersonalEventsPresentation   // rebuilt on store.revision
//         func reload(); func deleteConfirmation(id:) -> PersonalEventDeleteConfirmation?
//         func delete(id:) throws; func endToday(id:) throws
//         var rawStoredText: String? { get }; @discardableResult func discardUnreadableStore() -> Bool
//     }
//
// Behaviour assumed where the specification leaves it unstated, each taken from the approved design
// model (design/round-s5-events/model.js) and the frames it draws:
//
//  1. Dates: en_GB day and short month. A range within one month prints the first day as a number
//     ("10 – 16 Mar"); across months, both dates ("28 Feb – 3 Mar"). The year is appended to a date
//     only when it differs from today's year ("1 – 7 Dec 2030"). A one-day event prints one date.
//     The Events screen and the delete confirmation say "Since 19 May"; a line outside the Events
//     screen says "since 19 May"; an ongoing event that has not started says "From 19 May" in both.
//     The range separator is " – " (U+2013 between two spaces); the name separator is " · ".
//  2. `outsideLine` outside the Events screen takes the "today" of the call it is used in. Here a
//     year-sensitive expectation passes `today` through `present` or `caption`; `outsideLine(for:)`
//     itself has no `today` parameter, so its expectations avoid a cross-year event.
//  3. `noteFirstLine` is the note up to its first line break.
//  4. The delete confirmation's detail is "<title> · <dateText>" with the Events screen's wording,
//     so a private event shows the owner's own label there (frame D2).
//  5. `spokenText` is "Events: " followed by the lines and the "more" text joined by ", ".
//  6. `needsAttention` gives the state `.storeUnreadable` with every list empty, no unreadable-entries
//     text and no Health row value.
//  7. `PersonalEventsModel.presentation` follows `store.revision` on the main actor without a call to
//     `reload()`, within one second of the change.
//
// Not pinnable here: the Loading skeleton, Reduce Motion and the largest text size (§10.2, §10.5) are
// view behaviour with no presenter output.

import XCTest
import StrandAnalytics
import WhoopStore
@testable import Strand

@MainActor
final class PersonalEventPresenterTests: XCTestCase {

    private typealias Fx = PersonalEventAppFixture
    private let gb = PersonalEventAppFixture.british

    private var suites: [String] = []

    override func tearDown() {
        for name in suites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        suites = []
        super.tearDown()
    }

    // MARK: Helpers

    private func present(_ events: [PersonalEvent], today: String, unreadable: Int = 0,
                         needsAttention: Bool = false) -> PersonalEventsPresentation {
        PersonalEventPresenter.present(events: events, today: today, unreadableEntryCount: unreadable,
                                       needsAttention: needsAttention, locale: gb)
    }

    private func caption(_ events: [PersonalEvent], _ first: String, _ last: String,
                         today: String = "2031-05-28") -> PersonalEventCaption? {
        PersonalEventPresenter.caption(events: events, firstDay: first, lastDay: last, today: today, locale: gb)
    }

    private func row(_ id: String, _ title: String, _ dateText: String, note: String? = nil, isPrivate: Bool = false,
                     endToday: Bool = false) -> PersonalEventRow {
        PersonalEventRow(id: id, title: title, dateText: dateText, noteFirstLine: note, isPrivate: isPrivate,
                         offersEndToday: endToday)
    }

    private func suite(flag: Bool = true) throws -> UserDefaults {
        let name = "PersonalEventPresenterTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        suites.append(name)
        defaults.set(flag, forKey: PersonalEventStore.enabledKey)
        return defaults
    }

    private func makeModel(_ defaults: UserDefaults, today: String) -> (PersonalEventStore, PersonalEventsModel) {
        let now = Fx.noon(today)
        let store = PersonalEventStore(defaults: defaults, now: { now })
        let model = PersonalEventsModel(store: store, now: { now }, timeZone: { Fx.utc }, locale: gb)
        model.reload()
        return (store, model)
    }

    /// Waits up to a second for the model to follow a store change made outside it.
    private func eventually(_ condition: () -> Bool, _ message: String,
                            file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail(message, file: file, line: line)
    }

    // Rows of §10.2 on Wed 12 Mar 2031 (frame L1).
    private var rows12Mar: (now: [PersonalEventRow], upcoming: [PersonalEventRow], earlier: [PersonalEventRow]) {
        (now: [row(Fx.id(1), "Travel", "10 – 16 Mar", note: "Fixture trip")],
         upcoming: [row(Fx.id(5), "Illness", "From 19 May", isPrivate: true),
                    row(Fx.id(3), "Diet break", "14 – 27 Apr"),
                    row(Fx.id(6), "Fixture change", "26 Mar", note: "Fixture note", isPrivate: true)],
         earlier: [row(Fx.id(8), "Travel", "22 – 24 Feb"),
                   row(Fx.id(2), "Deload", "3 – 9 Feb"),
                   row(Fx.id(4), "Supplement change", "22 Jan"),
                   row(Fx.id(7), "Travel", "1 – 7 Dec 2030")])
    }

    // MARK: §10.2 Events screen, one test per state

    func testEmptyState() {
        let p = present([], today: "2031-03-12")
        XCTAssertEqual(p, PersonalEventsPresentation(state: .empty, now: [], upcoming: [], earlier: [],
                                                     unreadableEntriesText: nil, healthRowValue: nil))
        // Events that are all invalid are not rows either.
        let invalid = Fx.make(Fx.id(9), .travel, "2031-03-10", "2031-03-01")
        XCTAssertEqual(present([invalid], today: "2031-03-12").state, .empty)
    }

    func testRowsStateListsNowUpcomingAndEarlierNewestStartFirst() {
        let p = present(Fx.all, today: "2031-03-12")
        XCTAssertEqual(p.state, .rows)
        XCTAssertEqual(p.now, rows12Mar.now)
        XCTAssertEqual(p.upcoming, rows12Mar.upcoming)
        XCTAssertEqual(p.earlier, rows12Mar.earlier)
        XCTAssertNil(p.unreadableEntriesText)
        XCTAssertEqual(p.healthRowValue, "1 now")
        XCTAssertEqual(present(Fx.all.reversed(), today: "2031-03-12"), p, "input order does not matter")
    }

    func testRowShowsOnlyTheFirstLineOfTheNote() {
        let event = Fx.make(Fx.id(9), .deload, "2031-03-11", "2031-03-11", note: "Fixture line one\nFixture line two")
        let p = present([event], today: "2031-03-12")
        XCTAssertEqual(p.earlier, [row(Fx.id(9), "Deload", "11 Mar", note: "Fixture line one")])
    }

    func testOngoingStateIsUnderNowWithSinceAndEndToday() {
        let p = present(Fx.all, today: "2031-05-28")
        XCTAssertEqual(p.now, [row(Fx.id(5), "Illness", "Since 19 May", isPrivate: true, endToday: true)])
        XCTAssertEqual(p.upcoming, [])
        XCTAssertEqual(p.earlier.map(\.id), [Fx.id(3), Fx.id(6), Fx.id(1), Fx.id(8), Fx.id(2), Fx.id(4), Fx.id(7)])
        XCTAssertTrue(p.earlier.allSatisfy { !$0.offersEndToday })
        // On its first day it is already "now" and can be ended.
        XCTAssertEqual(present([Fx.e5], today: "2031-05-19").now.map(\.offersEndToday), [true])
    }

    func testAfterEndTodayTheEventIsARangeWithNoAction() {
        let ended = Fx.make(Fx.id(5), .illness, "2031-05-19", "2031-05-28", sensitive: true, createdAt: 1004)
        let p = present([ended], today: "2031-05-28")
        XCTAssertEqual(p.now, [row(Fx.id(5), "Illness", "19 – 28 May", isPrivate: true)])
    }

    func testOnlyFutureEventsShowUpcomingAlone() {
        let p = present([Fx.e1, Fx.e3, Fx.e5], today: "2031-01-08")
        XCTAssertEqual(p.state, .rows)
        XCTAssertEqual(p.now, [])
        XCTAssertEqual(p.earlier, [])
        XCTAssertEqual(p.upcoming, [row(Fx.id(5), "Illness", "From 19 May", isPrivate: true),
                                    row(Fx.id(3), "Diet break", "14 – 27 Apr"),
                                    row(Fx.id(1), "Travel", "10 – 16 Mar", note: "Fixture trip")])
        XCTAssertNil(p.healthRowValue)
    }

    func testSomeEntriesUnreadableAddsTheFootnoteAndNothingElse() {
        let p = present(Fx.all, today: "2031-03-12", unreadable: 3)
        XCTAssertEqual(p.unreadableEntriesText, "3 entries could not be read. They are kept.")
        XCTAssertEqual(p.now, rows12Mar.now)
        XCTAssertEqual(p.upcoming, rows12Mar.upcoming)
        XCTAssertEqual(p.earlier, rows12Mar.earlier)
        // The only unreadable entries, with no readable event, still say so.
        let alone = present([], today: "2031-03-12", unreadable: 2)
        XCTAssertEqual(alone.unreadableEntriesText, "2 entries could not be read. They are kept.")
        XCTAssertNil(present(Fx.all, today: "2031-03-12", unreadable: 0).unreadableEntriesText)
    }

    func testStoreUnreadableState() {
        let p = present([], today: "2031-03-12", unreadable: 0, needsAttention: true)
        XCTAssertEqual(p, PersonalEventsPresentation(state: .storeUnreadable, now: [], upcoming: [], earlier: [],
                                                     unreadableEntriesText: nil, healthRowValue: nil))
    }

    // MARK: §10.4 Delete confirmation

    func testDeleteAsksOnceWithTheNameAndDates() {
        let c = PersonalEventPresenter.deleteConfirmation(for: Fx.e1, locale: gb)
        XCTAssertEqual(c, PersonalEventDeleteConfirmation(title: "Delete this event?", detail: "Travel · 10 – 16 Mar",
                                                          warning: "This cannot be undone.", confirmTitle: "Delete",
                                                          cancelTitle: "Cancel"))
        // A private event shows the owner's own name: this is inside the Events screen (frame D2).
        XCTAssertEqual(PersonalEventPresenter.deleteConfirmation(for: Fx.e6, locale: gb).detail, "Fixture change · 26 Mar")
        XCTAssertEqual(PersonalEventPresenter.deleteConfirmation(for: Fx.e4, locale: gb).detail, "Supplement change · 22 Jan")
    }

    // MARK: §10.5 caption, one test per state

    func testCaptionIsNilWithNoEventInTheWindow() {
        XCTAssertNil(caption([], "2031-03-01", "2031-03-31"))
        XCTAssertNil(caption(Fx.all, "2031-01-01", "2031-01-21"), "E4 starts the next day; E7 ended in 2030")
        XCTAssertNil(caption(Fx.all, "2031-03-31", "2031-03-01"), "an invalid window")
        XCTAssertNil(caption(Fx.all, "2031-3-01", "2031-03-31"))
    }

    func testCaptionWithOneOrTwoEventsHasOneLineEach() {
        XCTAssertEqual(caption(Fx.all, "2031-02-01", "2031-02-28"),
                       PersonalEventCaption(lines: ["Travel · 22 – 24 Feb", "Deload · 3 – 9 Feb"], moreText: nil,
                                            spokenText: "Events: Travel · 22 – 24 Feb, Deload · 3 – 9 Feb"))
        XCTAssertEqual(caption(Fx.all, "2031-03-10", "2031-03-10"),
                       PersonalEventCaption(lines: ["Travel · 10 – 16 Mar"], moreText: nil,
                                            spokenText: "Events: Travel · 10 – 16 Mar"))
    }

    func testCaptionShowsTheTwoLatestStartsThenTheCount() {
        XCTAssertEqual(caption(Fx.all, "2031-01-01", "2031-03-31"),
                       PersonalEventCaption(lines: ["Private event · 26 Mar", "Travel · 10 – 16 Mar"],
                                            moreText: "and 3 more",
                                            spokenText: "Events: Private event · 26 Mar, Travel · 10 – 16 Mar, and 3 more"))
        XCTAssertEqual(caption(Fx.all, "2030-01-01", "2031-12-31")?.moreText, "and 6 more")
    }

    func testCaptionOfASensitiveEventSaysPrivateEvent() {
        XCTAssertEqual(caption(Fx.all, "2031-03-20", "2031-03-31")?.lines, ["Private event · 26 Mar"])
        XCTAssertEqual(caption(Fx.v9, "2031-02-01", "2031-02-28")?.lines,
                       ["Travel · 22 – 24 Feb", "Private event · 3 – 9 Feb"], "V9: the flag decides, not the kind")
    }

    func testCaptionOfAnOngoingEventSaysSince() {
        let open = Fx.make(Fx.id(5), .illness, "2031-05-19", nil, sensitive: false, createdAt: 1004)
        XCTAssertEqual(caption([open], "2031-05-01", "2031-05-31")?.lines, ["Illness · since 19 May"])
        XCTAssertEqual(caption(Fx.all, "2031-05-01", "2031-05-31")?.lines, ["Private event · since 19 May"])
    }

    func testCaptionAddsTheYearOnlyWhenItDiffersFromToday() {
        XCTAssertEqual(caption(Fx.all, "2030-11-01", "2030-12-31", today: "2031-03-12")?.lines,
                       ["Travel · 1 – 7 Dec 2030"])
        XCTAssertEqual(caption(Fx.all, "2030-11-01", "2030-12-31", today: "2030-12-20")?.lines,
                       ["Travel · 1 – 7 Dec"])
        let acrossMonths = Fx.make(Fx.id(9), .travel, "2031-02-28", "2031-03-03")
        XCTAssertEqual(caption([acrossMonths], "2031-03-01", "2031-03-31", today: "2031-03-12")?.lines,
                       ["Travel · 28 Feb – 3 Mar"])
        let acrossYears = Fx.make(Fx.id(9), .travel, "2030-12-30", "2031-01-02")
        XCTAssertEqual(caption([acrossYears], "2031-01-01", "2031-01-31", today: "2031-03-12")?.lines,
                       ["Travel · 30 Dec 2030 – 2 Jan"])
    }

    func testOutsideLineNamesTheKindOrPrivateEventAndNeverANote() {
        XCTAssertEqual(PersonalEventPresenter.outsideLine(for: Fx.e1, locale: gb), "Travel · 10 – 16 Mar")
        XCTAssertEqual(PersonalEventPresenter.outsideLine(for: Fx.e4, locale: gb), "Supplement change · 22 Jan")
        XCTAssertEqual(PersonalEventPresenter.outsideLine(for: Fx.e6, locale: gb), "Private event · 26 Mar")
        let publicCustom = Fx.make(Fx.id(9), .custom, "2031-03-26", "2031-03-26", label: "Fixture change",
                                   note: "Fixture note", sensitive: false)
        let line = PersonalEventPresenter.outsideLine(for: publicCustom, locale: gb)
        XCTAssertFalse(line.contains("Fixture note"), "never a note")
        XCTAssertTrue(line.hasSuffix(" · 26 Mar"), line)
    }

    func testKindNamesAreTheSpecifiedWords() {
        let names = PersonalEventKind.allCases.map { PersonalEventPresenter.kindName($0, locale: gb) }
        XCTAssertEqual(names, ["Travel", "Illness", "Diet break", "Deload", "Supplement change", "Something else"])
    }

    // MARK: Health row (§10.1)

    func testHealthRowValueCountsEventsOverlappingTodayAndIsEmptyWithNone() {
        XCTAssertEqual(present(Fx.all, today: "2031-03-12").healthRowValue, "1 now")
        XCTAssertNil(present(Fx.all, today: "2031-03-01").healthRowValue, "never \"0 now\"")
        XCTAssertNil(present([], today: "2031-03-12").healthRowValue)
        let second = Fx.make(Fx.id(9), .deload, "2031-03-12", nil)
        XCTAssertEqual(present(Fx.all + [second], today: "2031-03-12").healthRowValue, "2 now")
        XCTAssertEqual(present(Fx.all, today: "2031-03-16").healthRowValue, "1 now", "the last day counts")
        XCTAssertNil(present(Fx.all, today: "2031-03-17").healthRowValue)
        XCTAssertEqual(present(Fx.all, today: "2031-03-26").healthRowValue, "1 now", "a private event is counted")
    }

    // MARK: Privacy and empty text (§10.5, §12.3)

    func testSensitiveLabelAndNoteAppearOnlyInTheEventsScreenPresentation() {
        let screen = ScorecardScreenFixture.strings(in: present(Fx.all, today: "2031-03-12")).joined(separator: "\n")
        XCTAssertTrue(screen.contains(Fx.privateLabel), "the owner's own list shows the label")
        XCTAssertTrue(screen.contains(Fx.privateNote), "and the note")

        var outside: [String] = Fx.all.map { PersonalEventPresenter.outsideLine(for: $0, locale: gb) }
        for today in ["2031-03-12", "2031-03-26", "2031-06-30"] {
            for (first, last) in [("2030-01-01", "2031-12-31"), ("2031-03-26", "2031-03-26"), ("2031-03-20", "2031-04-02")] {
                if let c = caption(Fx.all, first, last, today: today) {
                    outside += ScorecardScreenFixture.strings(in: c)
                }
            }
        }
        for text in outside {
            for needle in Fx.privateNeedles {
                XCTAssertFalse(text.contains(needle), "\(text) carries \(needle)")
            }
            XCTAssertFalse(text.contains(Fx.ordinaryNote), "no note of any event outside the screen: \(text)")
        }
    }

    func testNoStringContainsAnInterpolatedNilOrAnEmptyDate() {
        let lists: [[PersonalEvent]] = [Fx.all, Fx.v9, [Fx.e5], [Fx.e6],
                                        [Fx.make(Fx.id(9), .custom, "2031-12-31", nil, label: "Fixture change",
                                                 sensitive: false)]]
        var strings: [String] = []
        for events in lists {
            for today in ["2030-12-01", "2031-01-01", "2031-03-12", "2031-05-19", "2031-12-31", "2032-01-01"] {
                strings += ScorecardScreenFixture.strings(in: present(events, today: today, unreadable: 1))
                strings += ScorecardScreenFixture.strings(in: present(events, today: today, needsAttention: true))
                if let c = caption(events, "2030-01-01", "2032-12-31", today: today) {
                    strings += ScorecardScreenFixture.strings(in: c)
                }
            }
            for event in PersonalEvents.normalized(events) {
                strings.append(PersonalEventPresenter.outsideLine(for: event, locale: gb))
                strings += ScorecardScreenFixture.strings(in: PersonalEventPresenter.deleteConfirmation(for: event, locale: gb))
            }
        }
        XCTAssertFalse(strings.isEmpty)
        for text in strings {
            XCTAssertFalse(text.isEmpty, "an empty string is shown")
            for bad in ["nil", "Optional(", "(null)", "%@", "%lld", "  ", " · ·", " – –"] {
                XCTAssertFalse(text.contains(bad), "\(text) contains \(bad)")
            }
            for bad in [" · ", " – ", "Since ", "since ", "From "] {
                XCTAssertFalse(text.hasSuffix(bad) || text.hasSuffix(bad.trimmingCharacters(in: .whitespaces)),
                               "\(text) ends without its date")
            }
            XCTAssertFalse(text.hasPrefix(" – ") || text.hasPrefix("– "), "\(text) starts without its date")
            XCTAssertFalse(text.contains(" · –") || text.contains("· ·"), text)
        }
    }

    // MARK: The Events screen model (§10.9)

    func testModelPresentsTheStoreAndFollowsItsRevision() async throws {
        let defaults = try suite()
        defaults.set(Fx.stored(Fx.allNormalized, extra: [Fx.unknownKindElement]), forKey: PersonalEventStore.itemsKey)
        let (_, model) = makeModel(defaults, today: "2031-03-12")
        XCTAssertEqual(model.presentation.now, rows12Mar.now)
        XCTAssertNotNil(model.presentation.unreadableEntriesText, "one unreadable entry is reported")

        // A restore replaces the list: the screen follows without a reload.
        defaults.set(Fx.stored([Fx.e2]), forKey: PersonalEventStore.itemsKey)
        await eventually({ model.presentation.earlier.map(\.id) == [Fx.id(2)] && model.presentation.now.isEmpty },
                         "the presentation follows the store's revision")
        XCTAssertNil(model.presentation.unreadableEntriesText)
    }

    func testModelDeleteConfirmationAndDeleteRemoveOneEvent() async throws {
        let defaults = try suite()
        defaults.set(Fx.stored(Fx.allNormalized), forKey: PersonalEventStore.itemsKey)
        let (store, model) = makeModel(defaults, today: "2031-03-12")

        XCTAssertEqual(model.deleteConfirmation(id: Fx.id(1))?.detail, "Travel · 10 – 16 Mar")
        XCTAssertNil(model.deleteConfirmation(id: "0123456789abcdef"), "no confirmation for an unknown id")

        try model.delete(id: Fx.id(1))
        XCTAssertEqual(store.events, Fx.allNormalized.filter { $0.id != Fx.id(1) }, "one event removed, seven kept")
        await eventually({ model.presentation.now.isEmpty }, "the row leaves the screen")
        XCTAssertEqual(model.presentation.upcoming, rows12Mar.upcoming)
        XCTAssertEqual(model.presentation.earlier, rows12Mar.earlier)

        XCTAssertThrowsError(try model.delete(id: Fx.id(1))) { error in
            XCTAssertEqual(error as? PersonalEventStoreError, .notFound)
        }
    }

    func testModelOffersTheRawTextAndDiscardsOnlyAnUnreadableStore() throws {
        let defaults = try suite()
        defaults.set("{", forKey: PersonalEventStore.itemsKey)
        let (store, model) = makeModel(defaults, today: "2031-03-12")
        XCTAssertEqual(model.presentation.state, .storeUnreadable)
        XCTAssertEqual(model.rawStoredText, "{", "Copy stored text")
        XCTAssertTrue(model.discardUnreadableStore(), "Start again, after the one question")
        XCTAssertNil(defaults.object(forKey: PersonalEventStore.itemsKey))
        XCTAssertFalse(store.needsAttention)
        model.reload()
        XCTAssertEqual(model.presentation.state, .empty)
        XCTAssertFalse(model.discardUnreadableStore())
    }

    func testModelWithTheFlagOffShowsNothing() throws {
        let defaults = try suite(flag: false)
        defaults.set(Fx.stored(Fx.allNormalized), forKey: PersonalEventStore.itemsKey)
        let (_, model) = makeModel(defaults, today: "2031-03-12")
        XCTAssertEqual(model.presentation.now + model.presentation.upcoming + model.presentation.earlier, [])
        XCTAssertNil(model.presentation.healthRowValue)
    }
}
