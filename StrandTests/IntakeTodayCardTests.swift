// API ASSUMED BY THESE TESTS
//
// Stage 3 specification §10.1 and §12.3: the two methods the specification adds to
// TodayCardResolverTests.swift (written here as a new file), and the card's identity. Written
// before the implementation exists.
//
//     enum DashboardCard { ...; case protein }      // rawValue "protein"; a value card; redesign-only;
//                                                   // absent from `defaultSelection`          [spec §5, §10.1]
//     TodayCardResolver.renderList(raw:hydrationEnabled:coachEnabled:visibleKeyMetrics:
//                                  scorecardEnabled: Bool = false, intakeEnabled: Bool = false)  [spec §10.1]
//     TodayCardsEditorPresentation.availableCards(redesign: Bool, scorecardEnabled: Bool,
//                                                 intakeEnabled: Bool = false) -> [DashboardCard] [assumed]
//         // the editor hides the card while the flag is off, as it hides the scorecard (§10.1)
//     TodayCardInputs.intake: IntakeCard?           // nil: not loaded yet                       [assumed]
//     TodayCardReadout.Tap.intake                   // pushes the intake screen                  [spec §10.1]
//     IntakeCard as at the top of IntakePresenterTests.swift.
//
// Behaviour assumed: the protein readout copies the card's value, unit, caption and dimming, taps
// through to the intake screen whenever the card says so, and shows a past day's figure (unlike the
// scorecard card, a past day has a closed total, §9.5). With no card yet it draws the skeleton with a
// non-empty caption, as every registry card must (`testAllRegistryCardsResolveWithoutInventingMissingValues`).
//
// Synthetic values only.

import XCTest
import WhoopStore
@testable import Strand

final class IntakeTodayCardTests: XCTestCase {
    private let baselineCardIds = ["hrv", "restingHr", "respiratory", "steps", "stepsAverage30", "stress", "fitnessAge",
                                   "vo2max", "vitality", "bloodOxygen", "skinTemp", "sleep", "calories", "hydration",
                                   "coupled", "coach"]

    private func inputs(isToday: Bool = true) -> TodayCardInputs {
        var result = TodayCardInputs()
        result.selectedDayKey = "2031-01-29"
        result.isToday = isToday
        result.locale = Locale(identifier: "en_GB")
        return result
    }

    private func card(_ status: IntakeCard.Status, value: String?, caption: String?, dimmed: Bool = false,
                      opens: Bool = true) -> IntakeCard {
        IntakeCard(status: status, value: value, unit: value == nil ? nil : "g", caption: caption, ring: 0.95,
                   floorGrams: 100, isDimmed: dimmed, opensIntake: opens)
    }

    func testProteinCardIsARedesignOnlyValueCardWithAStableId() {
        XCTAssertEqual(DashboardCard.protein.rawValue, "protein")
        XCTAssertEqual(DashboardCard(rawValue: "protein"), .protein)
        XCTAssertFalse(DashboardCard.protein.isShortcut)
        XCTAssertTrue(DashboardCard.protein.isRedesignOnly)
        XCTAssertNil(TodayCardResolver.keyMetricTwin(for: .protein))
        XCTAssertEqual(DashboardCard.protein.title, "Protein")
        XCTAssertEqual(DashboardCard.protein.subtitle, "Today against your floor")
        XCTAssertEqual(TodayCardResolver.cardTitle(.protein), "Protein")
        XCTAssertFalse(DashboardCard.protein.icon.isEmpty)
        XCTAssertFalse(DashboardCard.defaultSelection.contains(.protein))
        XCTAssertNotEqual(DashboardCard.protein.title, DashboardCard.calories.title,
                          "intake energy is never titled 'Calories' (C9); the card is protein")
    }

    func testProteinCardRendersOnlyWithTheFlagOn() {
        let saved: [DashboardCard] = [.protein, .stress, .scorecard, .hrv]
        let raw = DashboardCardPrefs.encode(saved)
        let withoutIt = DashboardCardPrefs.encode(saved.filter { $0 != .protein })
        for scorecard in [false, true] {
            for visible in [nil, [KeyMetric.hrv]] as [[KeyMetric]?] {
                let off = TodayCardResolver.renderList(raw: raw, hydrationEnabled: true, coachEnabled: true,
                                                       visibleKeyMetrics: visible, scorecardEnabled: scorecard,
                                                       intakeEnabled: false)
                XCTAssertFalse(off.contains(.protein))
                XCTAssertEqual(off, TodayCardResolver.renderList(raw: withoutIt, hydrationEnabled: true, coachEnabled: true,
                                                                 visibleKeyMetrics: visible, scorecardEnabled: scorecard),
                               "flag off: the list as if the card had never been added")
                let on = TodayCardResolver.renderList(raw: raw, hydrationEnabled: true, coachEnabled: true,
                                                      visibleKeyMetrics: visible, scorecardEnabled: scorecard,
                                                      intakeEnabled: true)
                XCTAssertEqual(on.first, .protein, "the owner's position is kept")
                XCTAssertEqual(on.filter { $0 == .protein }.count, 1)
            }
        }
        XCTAssertFalse(TodayCardResolver.renderList(raw: "", hydrationEnabled: true, coachEnabled: true,
                                                   visibleKeyMetrics: nil, scorecardEnabled: true, intakeEnabled: true)
            .contains(.protein), "not in the default selection: the owner adds it")
    }

    func testRenderListIsUnchangedWhenIntakeIsNotPassed() {
        let selections: [[DashboardCard]] = [[], DashboardCard.defaultSelection, [.protein], [.protein, .hydration, .coach],
                                             [.scorecard, .protein, .stress], DashboardCard.allCases]
        for selection in selections {
            let raw = selection.isEmpty ? "" : DashboardCardPrefs.encode(selection)
            for flags in [(false, false, false), (true, true, true), (true, false, true)] {
                let implicit = TodayCardResolver.renderList(raw: raw, hydrationEnabled: flags.0, coachEnabled: flags.1,
                                                            visibleKeyMetrics: nil, scorecardEnabled: flags.2)
                let explicitOff = TodayCardResolver.renderList(raw: raw, hydrationEnabled: flags.0, coachEnabled: flags.1,
                                                               visibleKeyMetrics: nil, scorecardEnabled: flags.2,
                                                               intakeEnabled: false)
                XCTAssertEqual(implicit, explicitOff, "the parameter defaults to off: \(selection.map(\.rawValue))")
                XCTAssertFalse(implicit.contains(.protein))
            }
        }
    }

    func testTheEditorOffersTheCardOnlyOnTheRedesignWithTheFlagOn() {
        for redesign in [false, true] {
            for scorecard in [false, true] {
                let off = TodayCardsEditorPresentation.availableCards(redesign: redesign, scorecardEnabled: scorecard)
                XCTAssertFalse(off.contains(.protein), "flag off (by default): redesign \(redesign)")
                XCTAssertEqual(off, TodayCardsEditorPresentation.availableCards(redesign: redesign, scorecardEnabled: scorecard,
                                                                                intakeEnabled: false))
            }
        }
        XCTAssertEqual(TodayCardsEditorPresentation.availableCards(redesign: false, scorecardEnabled: true,
                                                                   intakeEnabled: true).map(\.rawValue),
                       baselineCardIds, "classic and Liquid Today never offer it")
        let offered = TodayCardsEditorPresentation.availableCards(redesign: true, scorecardEnabled: false, intakeEnabled: true)
        XCTAssertEqual(offered.filter { $0 == .protein }.count, 1)
        XCTAssertEqual(offered.filter { $0 != .protein }.map(\.rawValue), baselineCardIds, "the existing cards keep their order")
        XCTAssertEqual(DashboardCard.allCases.filter { !$0.isRedesignOnly }.map(\.rawValue), baselineCardIds)
    }

    func testProteinReadoutIsTheCardsValueCaptionAndTap() {
        var today = inputs()
        today.intake = card(.below, value: "95", caption: "5 g to your floor · 15:10")
        let readout = TodayCardResolver.readout(.protein, today)
        XCTAssertEqual(readout.value, "95")
        XCTAssertEqual(readout.unit, "g")
        XCTAssertEqual(readout.caption, "5 g to your floor · 15:10")
        XCTAssertEqual(readout.tap, .intake)
        XCTAssertFalse(readout.valueIsDimmed)
        XCTAssertFalse(readout.isLoading)

        today.intake = card(.stale, value: "95", caption: "Last read 11:20", dimmed: true)
        XCTAssertTrue(TodayCardResolver.readout(.protein, today).valueIsDimmed)

        today.intake = card(.notMeasured, value: nil, caption: "Nothing logged today")
        XCTAssertNil(TodayCardResolver.readout(.protein, today).value, "a dash, never 0")

        var past = inputs(isToday: false)
        past.intake = card(.pastDay, value: "120", caption: "Day total")
        let pastReadout = TodayCardResolver.readout(.protein, past)
        XCTAssertEqual(pastReadout.value, "120", "a past day shows its closed total")
        XCTAssertEqual(pastReadout.caption, "Day total")

        let waiting = TodayCardResolver.readout(.protein, inputs())
        XCTAssertTrue(waiting.isLoading, "no card yet: the skeleton")
        XCTAssertNil(waiting.value)
        XCTAssertNotNil(waiting.caption)
    }
}
