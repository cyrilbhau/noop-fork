import XCTest
@testable import StrandAnalytics

final class CodexContextPropertyTests: XCTestCase {
    func testNiggleInclusiveDaysAndUniqueUpdatePermutation() {
        var seed = CodexPropertySeed(state: 0xC01610)
        for _ in 0..<1_000 {
            let age = seed.next(100)
            let onset = CanonicalDay.adding(-age, to: "2031-03-26")!
            let updates = (0..<10).map { index in
                NiggleUpdate(day: CanonicalDay.adding(index, to: onset)!, sequence: index,
                             trend: NiggleTrend.allCases[seed.next(NiggleTrend.allCases.count)], weakness: seed.next(2) == 0)
            }
            let character = NiggleCharacter.allCases[seed.next(NiggleCharacter.allCases.count)]
            func input(_ list: [NiggleUpdate]) -> NiggleTriageInput {
                NiggleTriageInput(complaint: NiggleComplaint(onsetDay: onset, resolvedDay: nil,
                                                            character: character, trend: .unchanged,
                                                            weakness: false, updates: list), rules: [], today: "2031-03-26")
            }
            let result = NiggleTriage.evaluate(input(updates))
            XCTAssertEqual(result.dayCount, age + 1)
            XCTAssertEqual(result, NiggleTriage.evaluate(input(updates)))
            XCTAssertEqual(result, NiggleTriage.evaluate(input(updates.reversed())))
            codexAssertFinite(result)
        }
    }

    func testCutStressFiniteBoundedAndUniqueNightOrderIndependent() {
        var seed = CodexPropertySeed(state: 0xC01611)
        for _ in 0..<400 {
            let nights = (0..<70).map { index in
                CutStressNight(day: CanonicalDay.adding(index - 69, to: "2031-03-26")!,
                               restingHr: seed.number(), hrv: seed.number())
            }
            let weeks = 1 + seed.next(26)
            func input(_ rows: [CutStressNight]) -> CutStressInput {
                CutStressInput(nights: rows, firstWeekStart: nil, today: "2031-03-26", maxWeeks: weeks)
            }
            let result = CutStressTrend.weekly(input(nights))
            codexAssertFinite(result)
            XCTAssertLessThanOrEqual(result.weeks.count, weeks)
            XCTAssertEqual(result, CutStressTrend.weekly(input(nights)))
            XCTAssertEqual(result, CutStressTrend.weekly(input(nights.reversed())))
            for week in result.weeks {
                XCTAssertTrue((0...7).contains(week.restingHrNights))
                XCTAssertTrue((0...7).contains(week.hrvNights))
                if week.restingHrNights < 4 { XCTAssertNil(week.restingHrMean) }
                if week.hrvNights < 4 { XCTAssertNil(week.hrvMean) }
            }
        }
    }

    func testTimelineGeneratedCheckpointsKeepOneTodayAndCanonicalOrderedItems() {
        var seed = CodexPropertySeed(state: 0xC01612)
        for _ in 0..<500 {
            let checkpoints = (0..<32).map { _ in
                TimelineCheckpoint(day: CanonicalDay.adding(seed.next(101) - 50, to: "2031-03-26")!,
                                   isApproximate: seed.next(2) == 0,
                                   category: TimelineCheckpointCategory.allCases[seed.next(TimelineCheckpointCategory.allCases.count)],
                                   waypointWeightKg: seed.number(), phaseStartDay: nil, isDone: seed.next(2) == 0)
            }
            let input = CheckpointTimelineInput(phases: [], checkpoints: checkpoints,
                                                 scanDays: ["bad", "2031-01-01", "2032-01-01"], spans: [],
                                                 projection: nil, scans: .on, events: .off, today: "2031-03-26")
            let result = CheckpointTimeline.build(input)
            codexAssertFinite(result)
            XCTAssertEqual(result, CheckpointTimeline.build(input))
            XCTAssertEqual(result.items.filter { $0.kind == .today }.count, 1)
            XCTAssertTrue(result.items.allSatisfy { CanonicalDay.isValid($0.day) })
            XCTAssertEqual(result.items.map(\.day), result.items.map(\.day).sorted())
            if let index = result.todayIndex { XCTAssertEqual(result.items[index].kind, .today) }
        }
    }
}
