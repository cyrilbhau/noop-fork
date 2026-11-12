// API ASSUMED BY THESE TESTS
//
// Stage 3 specification §10.6 and §12.3 (`IntakeSupplementTickTests.swift`). Written before the
// implementation exists. New, in Strand/Data/IntakeSupplementTick.swift:
//
//     @MainActor struct IntakeSupplementTick {
//         init(repository: Repository, settings: IntakeSettings)                         [spec]
//         /// question → true (ticked), false (answered no in the Journal), nil (not recorded)
//         func states(day: String) async -> [String: Bool?]                              [spec]
//         func set(_ ticked: Bool, question: String, day: String) async                  [spec]
//         /// "Did you take <name>?", the canonical Journal question for a supplement name. Data,
//         /// never localised (§10.6).
//         static func question(forName name: String) -> String                           [assumed]
//         /// Creates the question through `catalog.addCustom(_:kind: .bool, group: .supplements)`
//         /// unless the catalogue already holds it, and lists it in `intake.supplement.questions`.
//         /// False and no write when the list is full or already holds the question.
//         @discardableResult
//         func addSupplement(named name: String, catalog: JournalCatalogStore) -> Bool   [assumed]
//     }
//
// `Repository.saveJournalAnswer`, `clearJournalAnswer`, `nativeJournalAnswers(day:)` (what the
// Journal card reads) and `JournalCatalogStore(defaults:)` are used as they exist today.
//
// Behaviour assumed where §10.6 leaves it open: `states(day:)` has one key per listed question,
// in any order, and reads the native Journal answer (`noop-journal`), which is the row the Journal
// card writes.
//
// Synthetic values only.

import XCTest
import WhoopStore
@testable import Strand

@MainActor
final class IntakeSupplementTickTests: XCTestCase {
    private let suites = IntakeSuites()
    private let question = IntakeFixture.supplementQuestion

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    private func make() async throws -> (IntakeSupplementTick, IntakeHarness) {
        let h = try await IntakeHarness.make(flag: true, source: .quickAdd, suites: suites)
        XCTAssertTrue(h.settings.addSupplementQuestion(question))
        return (IntakeSupplementTick(repository: h.repo, settings: h.settings), h)
    }

    /// Every native Journal row for `day`, as stored.
    private func native(_ h: IntakeHarness, _ day: String) async throws -> [JournalEntry] {
        try await h.store.journalEntries(deviceId: Repository.journalDeviceId, from: day, to: day)
    }

    func testTickWritesAYesAnswerUnderTheJournalId() async throws {
        let (tick, h) = try await make()
        let day = h.today
        let before = try await h.rows()
        await tick.set(true, question: question, day: day)
        let rows = try await native(h, day)
        XCTAssertEqual(rows.map(\.question), [question])
        XCTAssertEqual(rows.first?.answeredYes, true)
        XCTAssertNotEqual(Repository.journalDeviceId, IntakeFixture.strapId, "R42: not a strap id")
        let strapRows = try await h.store.journalEntries(deviceId: IntakeFixture.strapId, from: day, to: day)
        XCTAssertEqual(strapRows, [])
        let states = await tick.states(day: day)
        XCTAssertEqual(states[question], .some(true))
        let after = try await h.rows()
        XCTAssertEqual(after, before, "a tick writes no metric series row")
    }

    func testUntickClearsTheAnswerAndNeverWritesNo() async throws {
        let (tick, h) = try await make()
        let day = h.clock.day(-1)
        await tick.set(true, question: question, day: day)
        await tick.set(false, question: question, day: day)
        let rows = try await native(h, day)
        XCTAssertEqual(rows, [], "an unticked box is 'not recorded', never a recorded no")
        let states = await tick.states(day: day)
        XCTAssertEqual(states[question], .some(nil))
        // Unticking a box that was never ticked writes nothing either.
        await tick.set(false, question: question, day: h.today)
        let today = try await native(h, h.today)
        XCTAssertEqual(today, [])
    }

    func testAJournalNoShowsAsUnticked() async throws {
        let (tick, h) = try await make()
        let day = h.today
        await h.repo.saveJournalAnswer(day: day, question: question, answeredYes: false)
        let states = await tick.states(day: day)
        XCTAssertEqual(states[question], .some(false), "drawn as an empty box with the caption 'Marked not taken in Journal'")
        XCTAssertEqual(states.count, 1, "one state per listed supplement")
    }

    func testTickAndJournalCardReadTheSameRow() async throws {
        let (tick, h) = try await make()
        let day = h.today
        await tick.set(true, question: question, day: day)
        let card = await h.repo.nativeJournalAnswers(day: day)
        XCTAssertEqual(card[question], true, "the Journal card sees the tick")
        // The Journal card answers no; the tick follows.
        await h.repo.saveJournalAnswer(day: day, question: question, answeredYes: false)
        var states = await tick.states(day: day)
        XCTAssertEqual(states[question], .some(false))
        // The Journal card clears; the tick follows.
        await h.repo.clearJournalAnswer(day: day, question: question)
        states = await tick.states(day: day)
        XCTAssertEqual(states[question], .some(nil))
        // A past day within the Journal's reach is editable and independent of today.
        await tick.set(true, question: question, day: h.clock.day(-7))
        let past = await tick.states(day: h.clock.day(-7))
        XCTAssertEqual(past[question], .some(true))
        let now = await tick.states(day: day)
        XCTAssertEqual(now[question], .some(nil))
    }

    func testAddingASupplementCreatesOneJournalItemInTheSupplementsGroup() async throws {
        let h = try await IntakeHarness.make(flag: true, source: .quickAdd, suites: suites)
        let tick = IntakeSupplementTick(repository: h.repo, settings: h.settings)
        let catalog = JournalCatalogStore(defaults: h.defaults)
        let before = catalog.items.count
        XCTAssertEqual(IntakeSupplementTick.question(forName: IntakeFixture.supplementName), question)

        XCTAssertTrue(tick.addSupplement(named: IntakeFixture.supplementName, catalog: catalog))
        let added = catalog.items.filter { $0.canonical == question }
        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(catalog.items.count, before + 1)
        XCTAssertEqual(added.first?.group, .supplements)
        XCTAssertEqual(added.first?.kind, .bool)
        XCTAssertEqual(added.first?.custom, true)
        XCTAssertEqual(h.settings.supplementQuestions, [question])

        // Adding it again creates nothing.
        XCTAssertFalse(tick.addSupplement(named: IntakeFixture.supplementName, catalog: catalog))
        XCTAssertEqual(catalog.items.filter { $0.canonical == question }.count, 1)
        XCTAssertEqual(h.settings.supplementQuestions, [question])

        // The list holds four; a fifth is refused and creates no Journal item.
        for n in 2...4 { XCTAssertTrue(tick.addSupplement(named: "Fixture supplement \(n)", catalog: catalog)) }
        let count = catalog.items.count
        XCTAssertFalse(tick.addSupplement(named: "Fixture supplement 5", catalog: catalog))
        XCTAssertEqual(catalog.items.count, count)
        XCTAssertEqual(h.settings.supplementQuestions.count, 4)
    }

    func testAdoptingAnExistingJournalItemCreatesNoSecondItem() async throws {
        let h = try await IntakeHarness.make(flag: true, source: .quickAdd, suites: suites)
        let tick = IntakeSupplementTick(repository: h.repo, settings: h.settings)
        let catalog = JournalCatalogStore(defaults: h.defaults)
        catalog.addCustom(question, kind: .bool, group: .other)
        let before = catalog.items.count
        XCTAssertTrue(tick.addSupplement(named: IntakeFixture.supplementName, catalog: catalog))
        XCTAssertEqual(catalog.items.count, before, "the owner's existing question is adopted, not duplicated")
        XCTAssertEqual(h.settings.supplementQuestions, [question])
    }

    func testNoSupplementListedHasNoStates() async throws {
        let h = try await IntakeHarness.make(flag: true, source: .quickAdd, suites: suites)
        let tick = IntakeSupplementTick(repository: h.repo, settings: h.settings)
        await h.repo.saveJournalAnswer(day: h.today, question: question, answeredYes: true)
        let states = await tick.states(day: h.today)
        XCTAssertTrue(states.isEmpty, "with no supplement configured the section is absent")
    }
}
