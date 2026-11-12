// Stage 3 (protein and intake): the two findings of the independent review C8, each pinned by a
// test that fails on the defect it names. Synthetic values only.

import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

@MainActor
final class CodexReviewStage3Tests: XCTestCase {
    private let suites = IntakeSuites()

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    // MARK: - C8 P2: two first quick-adds on one day

    /// Two adds launched together on a day with no entry list each start from an absent list. Both
    /// report success, so both entries must be kept and the total must be their sum. Several days
    /// are tried, because which add's write survives an unserialised race varies.
    func testOverlappingFirstAddsOnOneDayKeepBothEntries() async throws {
        let h = try await IntakeHarness.make(flag: true, source: .quickAdd, suites: suites)
        let store = h.quickAdd()
        for offset in -5...0 {
            async let first = store.add(proteinGrams: 30, energyKcal: nil, label: "Fixture A",
                                        at: h.clock.at(offset, hour: 8))
            async let second = store.add(proteinGrams: 40, energyKcal: nil, label: "Fixture B",
                                         at: h.clock.at(offset, hour: 8))
            let added = try await [first, second]
            let day = h.clock.day(offset)
            XCTAssertEqual(Set(store.entries(day: day).map(\.id)), Set(added.map(\.id)),
                           "both adds reported success on \(day), so both entries are kept")
            let total = try await h.value(IntakeFixture.quickAddId, day, "protein_g")
            XCTAssertEqual(total, 70, "the banked total of \(day) is the sum of both entries")
        }
    }

    // MARK: - C8 P2: a decimal-comma keypad

    /// A French keypad types "30,5" for thirty and a half; the field must read it as that amount.
    func testAmountFieldReadsTheLocaleDecimalSeparator() {
        let french = Locale(identifier: "fr_FR")
        XCTAssertEqual(IntakePresenter.amountEntry("30,5", locale: french), .amount(30.5))
        XCTAssertEqual(IntakePresenter.amountEntry("1250,25", locale: french), .amount(1_250.25), "calories too")
        XCTAssertEqual(IntakePresenter.amountEntry("30", locale: french), .amount(30))
        let english = Locale(identifier: "en_US")
        XCTAssertEqual(IntakePresenter.amountEntry("30.5", locale: english), .amount(30.5))
    }

    /// No thousands separator is guessed: a grouped figure stays invalid rather than becoming another
    /// number, in a point locale and in a locale that groups with a point.
    func testAmountFieldGuessesNoThousandsSeparator() {
        let invalid = IntakeAmountEntry.invalid(message: "Enter a number from 0 to 100000")
        XCTAssertEqual(IntakePresenter.amountEntry("1,500", locale: Locale(identifier: "en_US")), invalid)
        XCTAssertEqual(IntakePresenter.amountEntry("1.500", locale: Locale(identifier: "de_DE")), invalid)
        XCTAssertEqual(IntakePresenter.amountEntry("30,5,1", locale: Locale(identifier: "fr_FR")), invalid)
    }

    /// The edit sheet's prefill uses the same separator, so a stored fraction reads back as it saves.
    func testEditablePrefillUsesTheLocaleDecimalSeparatorAndRoundTrips() {
        let french = Locale(identifier: "fr_FR")
        XCTAssertEqual(IntakePresenter.editableAmountText(30.5, locale: french), "30,5")
        XCTAssertEqual(IntakePresenter.editableAmountText(30, locale: french), "30")
        XCTAssertEqual(IntakePresenter.amountEntry(IntakePresenter.editableAmountText(30.5, locale: french),
                                                   locale: french), .amount(30.5))
    }
}
