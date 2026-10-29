import XCTest
@testable import Strand

final class TodayCardsEditorTests: XCTestCase {
    private let metrics: [KeyMetric] = [.hrv, .restingHr, .steps]

    private var sections: EditableLayoutDraft<TodaySection> {
        EditableLayoutDraft(visible: [.heartRate, .keyMetrics, .addedCards], hidden: [.yourCards])
    }

    func testImplicitDefaultsMatchVisibleMetricsOnlyInRedesign() {
        XCTAssertEqual(TodayCardsEditorPresentation.selection(raw: " \n", redesign: true,
                                                              sections: sections, metrics: metrics),
                       [.stress, .fitnessAge, .vitality])
        XCTAssertEqual(TodayCardsEditorPresentation.selection(raw: "", redesign: false,
                                                              sections: sections, metrics: metrics),
                       DashboardCard.defaultSelection)
        var hiddenMetrics = sections
        hiddenMetrics.hide(.keyMetrics)
        XCTAssertEqual(TodayCardsEditorPresentation.selection(raw: "", redesign: true,
                                                              sections: hiddenMetrics, metrics: metrics),
                       DashboardCard.defaultSelection)
    }

    func testExplicitSelectionKeepsDuplicatesAndGatedCardsInPlace() {
        let raw = "[\"coach\",\"hrv\",\"hydration\",\"stress\"]"
        let selection = TodayCardsEditorPresentation.selection(raw: raw, redesign: true,
                                                               sections: sections, metrics: metrics)
        XCTAssertEqual(selection, [.coach, .hrv, .hydration, .stress])
        XCTAssertEqual(TodayCardsEditorPresentation.note(for: .coach, visibleKeyMetrics: metrics,
                                                        hydrationEnabled: false, coachEnabled: false), .coachOff)
        XCTAssertEqual(TodayCardsEditorPresentation.note(for: .hydration, visibleKeyMetrics: metrics,
                                                        hydrationEnabled: false, coachEnabled: false), .hydrationOff)
        XCTAssertEqual(TodayCardsEditorPresentation.note(for: .hrv, visibleKeyMetrics: metrics,
                                                        hydrationEnabled: false, coachEnabled: false), .duplicate)
        XCTAssertEqual(TodayCardsEditorPresentation.note(for: .coach, visibleKeyMetrics: metrics,
                                                        hydrationEnabled: false, coachEnabled: true), .coachShortcut)
        XCTAssertEqual(TodayCardsEditorPresentation.note(for: .hrv, visibleKeyMetrics: nil,
                                                        hydrationEnabled: true, coachEnabled: true), .description)
    }

    func testOnlyNavigationCardsBelongToShortcutGroup() {
        XCTAssertEqual(DashboardCard.canonicalOrder.filter(\.isShortcut), [.coupled, .coach])
        XCTAssertEqual(TodayCardsEditorPresentation.note(for: .coupled, visibleKeyMetrics: metrics,
                                                        hydrationEnabled: true, coachEnabled: true), .coupledShortcut)
    }

    func testChangingCardsDoesNotUnhideTheirSectionOnSave() {
        let saved = save(sections: sections, cards: [.calories, .hrv])
        XCTAssertEqual(saved.hiddenSectionsRaw, "yourCards")
        XCTAssertFalse(TodayLayoutPrefs.visibleOrder(orderRaw: saved.sectionOrderRaw,
                                                    hiddenRaw: saved.hiddenSectionsRaw).contains(.yourCards))
        XCTAssertEqual(DashboardCardPrefs.decodeEnabled(saved.dashboardCardsRaw), [.calories, .hrv])
        XCTAssertEqual(saved.keyMetricsRaw, "hrv,restingHr,steps")
        XCTAssertEqual(saved.hostedCardsRaw, "[\"stress.today\"]")
    }

    func testExplicitShowEditsDraftAndSavePreservesItsPosition() {
        let original = sections
        var draft = original
        XCTAssertEqual(TodayCardsEditorPresentation.position(in: draft), .hidden)
        draft.show(.yourCards)
        XCTAssertEqual(TodayCardsEditorPresentation.position(in: draft), .after(.addedCards))
        XCTAssertEqual(original.hidden, [.yourCards], "Discarding the edited copy leaves the original untouched")
        let saved = save(sections: draft, cards: [.calories])
        XCTAssertEqual(saved.hiddenSectionsRaw, "")
        XCTAssertEqual(saved.sectionOrderRaw, "heartRate,keyMetrics,addedCards,yourCards")

        draft.moveVisible(from: IndexSet(integer: 3), to: 0)
        XCTAssertEqual(TodayCardsEditorPresentation.position(in: draft), .first)
        XCTAssertEqual(save(sections: draft, cards: [.calories]).sectionOrderRaw,
                       "yourCards,heartRate,keyMetrics,addedCards")
    }

    func testResettingCardsKeepsOtherDraftSettingsAndHiddenSection() {
        let before = save(sections: sections, cards: [.coach, .calories])
        let reset = TodayCardsEditorPresentation.selection(raw: "", redesign: true,
                                                           sections: sections, metrics: metrics)
        let after = save(sections: sections, cards: reset)
        XCTAssertEqual(DashboardCardPrefs.decodeEnabled(after.dashboardCardsRaw), [.stress, .fitnessAge, .vitality])
        XCTAssertEqual(after.sectionOrderRaw, before.sectionOrderRaw)
        XCTAssertEqual(after.hiddenSectionsRaw, before.hiddenSectionsRaw)
        XCTAssertEqual(after.keyMetricsRaw, before.keyMetricsRaw)
        XCTAssertEqual(after.keyMetricsDetailed, before.keyMetricsDetailed)
        XCTAssertEqual(after.keyMetricsWindowDays, before.keyMetricsWindowDays)
        XCTAssertEqual(after.hostedCardsRaw, before.hostedCardsRaw)
    }

    private func save(sections: EditableLayoutDraft<TodaySection>, cards: [DashboardCard]) -> TodayCustomizationSaveValues {
        TodayCustomizationSaveValues(sections: sections, metrics: metrics, detailed: true,
                                     windowDays: 30, dashboardCards: cards, hostedCards: [.stressToday])
    }
}
