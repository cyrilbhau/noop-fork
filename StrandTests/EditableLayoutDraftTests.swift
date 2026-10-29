import XCTest
@testable import Strand

final class EditableLayoutDraftTests: XCTestCase {
    func testLastHostedCardCanBeRemovedOnlyWithExplicitOptIn() {
        var draft = EditableLayoutDraft(visible: [HostedCard.stressToday], allItems: HostedCard.canonicalOrder)
        let original = draft
        draft.hide(.stressToday)
        XCTAssertEqual(draft, original)

        draft.hide(.stressToday, allowEmpty: true)
        XCTAssertTrue(draft.visible.isEmpty)
        XCTAssertEqual(Set(draft.hidden), Set(HostedCard.allCases))
        XCTAssertEqual(HostedCardPrefs.encode(draft.visible), "[]")
        XCTAssertEqual(HostedCardPrefs.decodeEnabled(HostedCardPrefs.encode(draft.visible)), [])

        draft.show(.stressToday)
        XCTAssertEqual(draft.visible, [.stressToday])
        XCTAssertFalse(draft.hidden.contains(.stressToday))
    }

    func testSectionsAndMetricsKeepTheirLastVisibleItemByDefault() {
        var sections = EditableLayoutDraft(visible: [TodaySection.yourCards], allItems: TodaySection.defaultOrder)
        sections.hide(.yourCards)
        XCTAssertEqual(sections.visible, [.yourCards])
        var metrics = EditableLayoutDraft(visible: [KeyMetric.hrv], allItems: KeyMetric.defaultOrder)
        metrics.hide(.hrv)
        XCTAssertEqual(metrics.visible, [.hrv])
        var cards = EditableLayoutDraft(visible: [DashboardCard.stress], allItems: DashboardCard.canonicalOrder)
        cards.hide(.stress)
        XCTAssertEqual(cards.visible, [.stress])
    }
}
