// API ASSUMED BY THESE TESTS
//
// Stage 3 specification §10.6.1 and §12.3 (`IntakeCoachExclusionTests.swift`). Written before the
// implementation exists. New, in Strand/Data/IntakeSettings.swift:
//
//     static func coachVisible(_ entries: [JournalEntry], defaults: UserDefaults = .standard) -> [JournalEntry]
//     @discardableResult func addSupplementQuestion(_ question: String) -> Bool
//     func removeSupplementQuestion(_ question: String)
//     var isEnabled: Bool { get set }
//
// `Repository.saveJournalAnswer(day:question:answeredYes:notes:)` and `journalEntries(days:)` are
// used as they exist today. The Coach engine itself reads the standard defaults and is not driven
// here; `Tools/test_intake_single_resolver.py` pins its one Journal read to `coachVisible`.
//
// Synthetic values only.

import XCTest
import WhoopStore
@testable import Strand

@MainActor
final class IntakeCoachExclusionTests: XCTestCase {
    private let suites = IntakeSuites()
    private let supplement = IntakeFixture.supplementQuestion
    private let other = IntakeFixture.otherQuestion

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    private func settings() throws -> (IntakeSettings, UserDefaults) {
        let name = "IntakeCoachExclusionTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        suites.names.append(name)
        return (IntakeSettings(defaults: defaults), defaults)
    }

    private func entry(_ day: String, _ question: String, _ yes: Bool = true) -> JournalEntry {
        JournalEntry(day: day, question: question, answeredYes: yes, notes: nil)
    }

    private var rows: [JournalEntry] {
        [entry("2031-01-27", other), entry("2031-01-27", supplement), entry("2031-01-28", supplement, false),
         entry("2031-01-28", other, false), entry("2031-01-29", "Did you feel stressed?"), entry("2031-01-29", supplement)]
    }

    func testListedSupplementQuestionsAreRemoved() throws {
        let (settings, defaults) = try settings()
        XCTAssertTrue(settings.addSupplementQuestion(supplement))
        let visible = IntakeSettings.coachVisible(rows, defaults: defaults)
        XCTAssertFalse(visible.contains { $0.question == supplement }, "yes and no answers alike are removed")
        XCTAssertEqual(visible.count, 3)
    }

    func testOtherRowsPassThroughUnchangedAndInOrder() throws {
        let (settings, defaults) = try settings()
        settings.addSupplementQuestion(supplement)
        XCTAssertEqual(IntakeSettings.coachVisible(rows, defaults: defaults),
                       [entry("2031-01-27", other), entry("2031-01-28", other, false),
                        entry("2031-01-29", "Did you feel stressed?")])
        let numeric = JournalEntry(day: "2031-01-29", question: "Caffeine (mg)", answeredYes: true, notes: "Fixture note",
                                   numericValue: 120)
        XCTAssertEqual(IntakeSettings.coachVisible([numeric], defaults: defaults), [numeric],
                       "nothing about a row other than its question is examined")
    }

    func testAnAbsentListIsTheIdentity() throws {
        let (_, defaults) = try settings()
        XCTAssertNil(defaults.object(forKey: IntakeSettings.supplementQuestionsKey))
        XCTAssertEqual(IntakeSettings.coachVisible(rows, defaults: defaults), rows)
        XCTAssertEqual(IntakeSettings.coachVisible([], defaults: defaults), [])
        // An empty stored list, and an unreadable one, are the identity too.
        defaults.set("[]", forKey: IntakeSettings.supplementQuestionsKey)
        XCTAssertEqual(IntakeSettings.coachVisible(rows, defaults: defaults), rows)
        defaults.set("[", forKey: IntakeSettings.supplementQuestionsKey)
        XCTAssertEqual(IntakeSettings.coachVisible(rows, defaults: defaults), rows)
    }

    func testMatchingIgnoresCaseAndSurroundingWhitespace() throws {
        let (settings, defaults) = try settings()
        settings.addSupplementQuestion(supplement)
        let variants = [entry("2031-01-27", "did you take fixture supplement?"),
                        entry("2031-01-27", "  Did you take Fixture supplement?\n"),
                        entry("2031-01-27", "DID YOU TAKE FIXTURE SUPPLEMENT?\t")]
        XCTAssertEqual(IntakeSettings.coachVisible(variants, defaults: defaults), [])
        // A different spelling is a different question, to the Journal and to the exclusion alike.
        let different = [entry("2031-01-27", "Did you take Fixture supplements?"),
                         entry("2031-01-27", "Did you take Fixture  supplement?")]
        XCTAssertEqual(IntakeSettings.coachVisible(different, defaults: defaults), different)
    }

    func testExclusionDoesNotDependOnTheIntakeFlag() throws {
        let (settings, defaults) = try settings()
        settings.addSupplementQuestion(supplement)
        for flag in [true, false] {
            settings.isEnabled = flag
            XCTAssertFalse(IntakeSettings.coachVisible(rows, defaults: defaults).contains { $0.question == supplement },
                           "flag \(flag): the exclusion follows the list")
        }
    }

    func testRemovingASupplementEndsItsExclusion() throws {
        let (settings, defaults) = try settings()
        settings.addSupplementQuestion(supplement)
        settings.removeSupplementQuestion(supplement)
        XCTAssertEqual(IntakeSettings.coachVisible(rows, defaults: defaults), rows)
    }

    func testCoachRankingInputNeverContainsAListedSupplement() async throws {
        let (settings, defaults) = try settings()
        settings.addSupplementQuestion(supplement)
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: IntakeFixture.strapId)
        repo.setStoreForTesting(store)
        let clock = IntakeTestClock()
        // The stage's reach: today and the seven days before it.
        for offset in -7...0 {
            await repo.saveJournalAnswer(day: clock.day(offset), question: supplement, answeredYes: offset % 2 == 0)
            await repo.saveJournalAnswer(day: clock.day(offset), question: other, answeredYes: offset % 3 == 0)
        }
        let all = await repo.journalEntries()
        XCTAssertTrue(all.contains { $0.question == supplement }, "the seed is read")
        XCTAssertTrue(all.contains { $0.question == other })
        let visible = IntakeSettings.coachVisible(all, defaults: defaults)
        XCTAssertEqual(visible, all.filter { $0.question == other }, "every row of the other question, in order")
        XCTAssertFalse(visible.contains { $0.question.contains("Fixture supplement") })
    }
}
