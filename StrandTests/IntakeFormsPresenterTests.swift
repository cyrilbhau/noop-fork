// API ASSUMED BY THESE TESTS
//
// Stage 3 specification §10.3 (quick-add sheet), §10.4 (scorecard protein row), §10.5 (Settings),
// §10.6 (supplement tick), §10.7 (cutoff reminder) and §11. Written before the implementation
// exists. The specification gives the states and the strings, not the functions; these are fixed
// here [assumed] so each state is decided once, in `IntakePresenter`, and the views decide nothing:
//
//     enum IntakeAmountEntry: Equatable { case empty, amount(Double), invalid(message: String) }
//     enum IntakeFloorEntry: Equatable { case noFloor, grams(Double), invalid(message: String) }
//     enum IntakeRangeEntry: Equatable { case valid(IntakeTargets), invalid }
//     enum IntakeSettingsRow: Equatable { case featureSwitch, source, proteinFloor, calorieRange, hardFloor,
//                                         appsToCount, supplements, addSupplement, cutoffTime, cutoffReminder }
//     struct IntakeSupplementRow: Equatable { let question: String; let name: String; let isTicked: Bool;
//                                             let caption: String? }
//
//     extension IntakePresenter {
//         /// One quick-add field. Empty: no amount. Valid: a finite number from 0 to 100 000.
//         static func amountEntry(_ text: String) -> IntakeAmountEntry
//         /// Save is enabled when at least one field holds an amount and neither is invalid.
//         static func canSaveQuickAdd(protein: IntakeAmountEntry, energy: IntakeAmountEntry) -> Bool
//         /// The backdating picker: today and the seven days before it, today first.
//         static func quickAddDays(today: String) -> [String]
//         static let quickAddSaveFailed: String     // "Could not save. Nothing was changed."
//         /// The floor field (§9.2.1): empty is no floor; otherwise valid exactly when
//         /// `CutScorecardSettings.isWholeGramProteinFloor` is true; refused entries carry
//         /// "Enter whole grams". The typed value is never rounded.
//         static func floorEntry(_ text: String) -> IntakeFloorEntry
//         /// The calorie range and hard floor fields; an empty field leaves its key absent.
//         static func rangeEntry(low: String, high: String, hardFloor: String) -> IntakeRangeEntry
//         /// The rows of the Intake card in Settings, top to bottom (§10.5).
//         static func settingsRows(flagEnabled: Bool, source: IntakeSourceSetting, knownHealthAppCount: Int,
//                                  supplementCount: Int) -> [IntakeSettingsRow]
//         /// The caption under the source row while the source is None; nil otherwise.
//         static func sourceNoneCaption(flagEnabled: Bool, source: IntakeSourceSetting) -> String?
//         static let supplementsCaption: String     // "Supplements listed here are left out of the Coach."
//         static func supplementRows(questions: [String], states: [String: Bool?],
//                                    displayName: (String) -> String) -> [IntakeSupplementRow]
//         /// The caption under the reminder row: present when any weekday is silent.
//         static func cutoffReminderCaption(_ triggers: [IntakeCutoffPlan.Trigger]) -> String?
//         /// The scorecard protein row's source caption (§10.4); nil with the intake flag off.
//         static func scorecardProteinCaption(flagEnabled: Bool, sources: [IntakeSource]) -> String?
//     }
//
// Numbers are typed in the en_US_POSIX form in these tests ("100", "2400"); the field's parsing of
// a grouping separator is not asserted. Synthetic values only.

import XCTest
import StrandAnalytics
@testable import Strand

final class IntakeFormsPresenterTests: XCTestCase {
    private let invalidAmount = "Enter a number from 0 to 100000"

    // MARK: - §10.3 Quick-add sheet

    func testAmountFieldStates() {
        XCTAssertEqual(IntakePresenter.amountEntry(""), .empty)
        XCTAssertEqual(IntakePresenter.amountEntry("  "), .empty)
        XCTAssertEqual(IntakePresenter.amountEntry("30"), .amount(30))
        XCTAssertEqual(IntakePresenter.amountEntry("0"), .amount(0), "zero is allowed")
        XCTAssertEqual(IntakePresenter.amountEntry("100000"), .amount(100_000))
        for bad in ["100001", "-1", "abc", "1e400", "nan", "inf", "30g"] {
            XCTAssertEqual(IntakePresenter.amountEntry(bad), .invalid(message: invalidAmount), bad)
        }
    }

    func testSaveIsEnabledOnlyWithAnAmountAndNoInvalidField() {
        XCTAssertFalse(IntakePresenter.canSaveQuickAdd(protein: .empty, energy: .empty), "nothing entered")
        XCTAssertTrue(IntakePresenter.canSaveQuickAdd(protein: .amount(30), energy: .empty), "either may be left empty")
        XCTAssertTrue(IntakePresenter.canSaveQuickAdd(protein: .empty, energy: .amount(150)))
        XCTAssertTrue(IntakePresenter.canSaveQuickAdd(protein: .amount(30), energy: .amount(150)), "a preset fills both")
        XCTAssertFalse(IntakePresenter.canSaveQuickAdd(protein: .amount(30), energy: .invalid(message: invalidAmount)))
        XCTAssertFalse(IntakePresenter.canSaveQuickAdd(protein: .invalid(message: invalidAmount), energy: .empty))
    }

    func testBackdatingOffersTodayAndTheSevenDaysBefore() {
        let days = IntakePresenter.quickAddDays(today: "2031-01-29")
        XCTAssertEqual(days, ["2031-01-29", "2031-01-28", "2031-01-27", "2031-01-26", "2031-01-25", "2031-01-24",
                              "2031-01-23", "2031-01-22"])
        XCTAssertEqual(IntakePresenter.quickAddDays(today: "2031-03-02").last, "2031-02-23", "across a month end")
    }

    func testSaveFailedSaysNothingWasChanged() {
        XCTAssertEqual(IntakePresenter.quickAddSaveFailed, "Could not save. Nothing was changed.")
    }

    // MARK: - §10.5 Settings

    func testFloorFieldAcceptsExactlyStageOnesRule() {
        XCTAssertEqual(IntakePresenter.floorEntry(""), .noFloor, "an empty field means no floor")
        XCTAssertEqual(IntakePresenter.floorEntry("100"), .grams(100))
        XCTAssertEqual(IntakePresenter.floorEntry("1"), .grams(1))
        XCTAssertEqual(IntakePresenter.floorEntry("100000"), .grams(100_000))
        for text in ["99.5", "99.4", "0", "-5", "100001", "abc", "0.5"] {
            XCTAssertEqual(IntakePresenter.floorEntry(text), .invalid(message: "Enter whole grams"), text)
        }
        for value in [1.0, 100, 100_000, 0, 0.5, 99.4, 99.5, -5, 100_001] {
            let text = value == value.rounded() ? String(Int(value)) : String(value)
            let accepted: Bool
            if case .grams = IntakePresenter.floorEntry(text) { accepted = true } else { accepted = false }
            XCTAssertEqual(accepted, CutScorecardSettings.isWholeGramProteinFloor(value), text)
        }
    }

    func testRangeFieldMarksAnInvalidRangeAndSavesNothing() {
        XCTAssertEqual(IntakePresenter.rangeEntry(low: "2400", high: "2600", hardFloor: "2100"),
                       .valid(IntakeTargets(energyLowKcal: 2_400, energyHighKcal: 2_600, energyHardFloorKcal: 2_100)))
        XCTAssertEqual(IntakePresenter.rangeEntry(low: "2400", high: "", hardFloor: ""),
                       .valid(IntakeTargets(energyLowKcal: 2_400)))
        XCTAssertEqual(IntakePresenter.rangeEntry(low: "", high: "", hardFloor: ""), .valid(IntakeTargets()))
        XCTAssertEqual(IntakePresenter.rangeEntry(low: "2600", high: "2400", hardFloor: ""), .invalid, "low above high")
        XCTAssertEqual(IntakePresenter.rangeEntry(low: "2400", high: "2600", hardFloor: "2500"), .invalid,
                       "hard floor above the low end")
        XCTAssertEqual(IntakePresenter.rangeEntry(low: "abc", high: "2600", hardFloor: ""), .invalid)
        XCTAssertEqual(IntakePresenter.rangeEntry(low: "0", high: "2600", hardFloor: ""), .invalid, "not positive")
    }

    func testFlagOffShowsOnlyTheSwitch() {
        for source in [IntakeSourceSetting.none, .appleHealth, .quickAdd] {
            XCTAssertEqual(IntakePresenter.settingsRows(flagEnabled: false, source: source, knownHealthAppCount: 2,
                                                        supplementCount: 1), [.featureSwitch])
        }
    }

    func testFlagOnShowsEveryRowInOrder() {
        XCTAssertEqual(IntakePresenter.settingsRows(flagEnabled: true, source: .appleHealth, knownHealthAppCount: 2,
                                                    supplementCount: 1),
                       [.featureSwitch, .source, .proteinFloor, .calorieRange, .hardFloor, .appsToCount, .supplements,
                        .addSupplement, .cutoffTime, .cutoffReminder])
        // Apps to count: Path A only, and only when more than one app is known.
        XCTAssertFalse(IntakePresenter.settingsRows(flagEnabled: true, source: .appleHealth, knownHealthAppCount: 1,
                                                    supplementCount: 0).contains(.appsToCount))
        XCTAssertFalse(IntakePresenter.settingsRows(flagEnabled: true, source: .quickAdd, knownHealthAppCount: 2,
                                                    supplementCount: 0).contains(.appsToCount))
        // Four supplements: the add row is hidden.
        XCTAssertFalse(IntakePresenter.settingsRows(flagEnabled: true, source: .none, knownHealthAppCount: 0,
                                                    supplementCount: 4).contains(.addSupplement))
        XCTAssertTrue(IntakePresenter.settingsRows(flagEnabled: true, source: .none, knownHealthAppCount: 0,
                                                   supplementCount: 0).contains(.addSupplement))
    }

    func testSourceNoneCaptionSaysTheCardAndWidgetHaveNothingToShow() {
        XCTAssertNotNil(IntakePresenter.sourceNoneCaption(flagEnabled: true, source: .none))
        XCTAssertNil(IntakePresenter.sourceNoneCaption(flagEnabled: true, source: .quickAdd))
        XCTAssertNil(IntakePresenter.sourceNoneCaption(flagEnabled: false, source: .none), "the row is not shown")
    }

    func testSupplementsCaptionSaysTheyAreLeftOutOfTheCoach() {
        XCTAssertEqual(IntakePresenter.supplementsCaption, "Supplements listed here are left out of the Coach.")
    }

    // MARK: - §10.6 Supplement tick

    func testSupplementRowStates() {
        let q = IntakeFixture.supplementQuestion
        let name: (String) -> String = { _ in IntakeFixture.supplementName }
        XCTAssertEqual(IntakePresenter.supplementRows(questions: [], states: [:], displayName: name), [],
                       "no supplement configured: the section is absent")
        XCTAssertEqual(IntakePresenter.supplementRows(questions: [q], states: [q: Bool?.none], displayName: name),
                       [IntakeSupplementRow(question: q, name: "Fixture supplement", isTicked: false, caption: nil)],
                       "not recorded: empty box")
        XCTAssertEqual(IntakePresenter.supplementRows(questions: [q], states: [q: .some(true)], displayName: name),
                       [IntakeSupplementRow(question: q, name: "Fixture supplement", isTicked: true, caption: nil)],
                       "ticked: no time is shown")
        XCTAssertEqual(IntakePresenter.supplementRows(questions: [q], states: [q: .some(false)], displayName: name),
                       [IntakeSupplementRow(question: q, name: "Fixture supplement", isTicked: false,
                                            caption: "Marked not taken in Journal")])
        let four = (1...4).map { "Did you take Fixture supplement \($0)?" }
        let rows = IntakePresenter.supplementRows(questions: four, states: [:], displayName: { $0 })
        XCTAssertEqual(rows.map(\.question), four, "four rows, in display order")
        XCTAssertTrue(rows.allSatisfy { !$0.isTicked })
        for row in rows + IntakePresenter.supplementRows(questions: [q], states: [q: .some(true)], displayName: name) {
            XCTAssertNil(row.caption?.rangeOfCharacter(from: .decimalDigits), "no count of consecutive days anywhere")
        }
    }

    // MARK: - §10.7 Reminder caption

    func testReminderNearTheWindDownSaysWhenItIsSilent() {
        let audible = IntakeCutoffPlan.triggers(cutoffMinuteOfDay: 1_200, windDownMinuteByWeekday: [:])
        XCTAssertNil(IntakePresenter.cutoffReminderCaption(audible))
        let silentMonday = IntakeCutoffPlan.triggers(cutoffMinuteOfDay: 1_200, windDownMinuteByWeekday: [2: 1_210])
        XCTAssertEqual(IntakePresenter.cutoffReminderCaption(silentMonday),
                       "Silent on days when it falls within 30 minutes of your wind-down reminder.")
    }

    // MARK: - §10.4 Scorecard protein row

    func testScorecardProteinRowCaption() {
        for sources in [[IntakeSource.appleHealth], [.quickAdd], [.nutritionCsv, .appleHealth]] {
            XCTAssertNil(IntakePresenter.scorecardProteinCaption(flagEnabled: false, sources: sources),
                         "flag off: the row is exactly stage 1's")
        }
        XCTAssertEqual(IntakePresenter.scorecardProteinCaption(flagEnabled: true, sources: [.appleHealth, .appleHealth]),
                       "Apple Health")
        XCTAssertEqual(IntakePresenter.scorecardProteinCaption(flagEnabled: true, sources: [.quickAdd]), "Entered here")
        XCTAssertEqual(IntakePresenter.scorecardProteinCaption(flagEnabled: true, sources: [.nutritionCsv]), "CSV import")
        XCTAssertEqual(IntakePresenter.scorecardProteinCaption(flagEnabled: true, sources: [.quickAdd, .appleHealth]),
                       "Several sources")
        XCTAssertNil(IntakePresenter.scorecardProteinCaption(flagEnabled: true, sources: []), "no day logged, no source")
    }
}
