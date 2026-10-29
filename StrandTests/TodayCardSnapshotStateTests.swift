import XCTest
@testable import Strand

final class TodayCardSnapshotStateTests: XCTestCase {
    private func snapshot(day: String, isToday: Bool, steps: Double) -> TodayCardInputs {
        var inputs = TodayCardInputs()
        inputs.selectedDayKey = day
        inputs.isToday = isToday
        inputs.stepCount = steps
        return inputs
    }

    func testNewDayRejectsAnOlderCompletionAfterTheNewSnapshotIsVisible() {
        var state = TodayCardSnapshotState()
        let older = state.begin(dayKey: "2026-10-29", dayOffset: 0)
        let newer = state.begin(dayKey: "2026-10-28", dayOffset: 1)
        XCTAssertTrue(state.complete(snapshot(day: "2026-10-28", isToday: false, steps: 2800), for: newer,
                                     selectedDayKey: "2026-10-28", selectedDayOffset: 1, isCancelled: false))
        XCTAssertFalse(state.complete(snapshot(day: "2026-10-29", isToday: true, steps: 2900), for: older,
                                      selectedDayKey: "2026-10-28", selectedDayOffset: 1, isCancelled: false))
        XCTAssertEqual(state.inputs?.selectedDayKey, "2026-10-28")
        XCTAssertEqual(state.inputs?.stepCount, 2800)
    }

    func testSameDayRefreshRejectsSupersededRequestEvenWithoutCooperativeCancellation() {
        var state = TodayCardSnapshotState()
        let first = state.begin(dayKey: "2026-10-29", dayOffset: 0)
        let refresh = state.begin(dayKey: "2026-10-29", dayOffset: 0)
        XCTAssertTrue(state.complete(snapshot(day: "2026-10-29", isToday: true, steps: 4000), for: refresh,
                                     selectedDayKey: "2026-10-29", selectedDayOffset: 0, isCancelled: false))
        XCTAssertFalse(state.complete(snapshot(day: "2026-10-29", isToday: true, steps: 1000), for: first,
                                      selectedDayKey: "2026-10-29", selectedDayOffset: 0, isCancelled: false))
        XCTAssertEqual(state.inputs?.stepCount, 4000)
    }

    func testBeginInvalidatesVisibleDataAndCancelledCompletionStaysPending() {
        var state = TodayCardSnapshotState()
        let first = state.begin(dayKey: "2026-10-29", dayOffset: 0)
        let input = snapshot(day: "2026-10-29", isToday: true, steps: 2900)
        XCTAssertTrue(state.complete(input, for: first, selectedDayKey: "2026-10-29",
                                     selectedDayOffset: 0, isCancelled: false))
        let refresh = state.begin(dayKey: "2026-10-29", dayOffset: 0)
        XCTAssertNil(state.inputs)
        XCTAssertFalse(state.complete(input, for: refresh, selectedDayKey: "2026-10-29",
                                      selectedDayOffset: 0, isCancelled: true))
        XCTAssertNil(state.inputs)
    }

    func testChangedSelectionAndMislabeledSnapshotCannotPublish() {
        var state = TodayCardSnapshotState()
        let request = state.begin(dayKey: "2026-10-29", dayOffset: 0)
        let input = snapshot(day: "2026-10-29", isToday: true, steps: 2900)
        XCTAssertFalse(state.complete(input, for: request, selectedDayKey: "2026-10-28",
                                      selectedDayOffset: 1, isCancelled: false))
        XCTAssertFalse(state.complete(input, for: request, selectedDayKey: "2026-10-29",
                                      selectedDayOffset: 1, isCancelled: false))
        XCTAssertFalse(state.complete(snapshot(day: "2026-10-28", isToday: true, steps: 2800), for: request,
                                      selectedDayKey: "2026-10-29", selectedDayOffset: 0, isCancelled: false))
        XCTAssertFalse(state.complete(snapshot(day: "2026-10-29", isToday: false, steps: 2900), for: request,
                                      selectedDayKey: "2026-10-29", selectedDayOffset: 0, isCancelled: false))
        XCTAssertNil(state.inputs)
    }

    func testPublishedSnapshotIsAValueCopyIndependentOfSubsequentMutations() {
        var state = TodayCardSnapshotState()
        let request = state.begin(dayKey: "2026-10-29", dayOffset: 0)
        var input = snapshot(day: "2026-10-29", isToday: true, steps: 2900)
        XCTAssertTrue(state.complete(input, for: request, selectedDayKey: "2026-10-29",
                                     selectedDayOffset: 0, isCancelled: false))
        input.stepCount = 9999
        var rendered = state.inputs
        rendered?.stepCount = 8888
        XCTAssertEqual(state.inputs?.stepCount, 2900)
    }
}
