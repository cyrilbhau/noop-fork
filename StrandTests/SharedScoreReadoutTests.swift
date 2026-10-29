import XCTest
import StrandAnalytics
import WhoopStore
@testable import Strand

/// Today and score details share the state-to-copy decisions; their surrounding presentation may differ.
final class SharedScoreReadoutTests: XCTestCase {
    func testReadinessSentencePreservesEveryLevel() {
        let cases: [(ReadinessEngine.Level, String)] = [
            (.primed, "You're primed. A hard session should land well today."),
            (.balanced, "You're in a good spot for training."),
            (.strained, "Signals are down a touch. Keep it easy today."),
            (.rundown, "Several recovery signals are down. Prioritise rest today."),
            (.insufficient, "Still learning your baseline. A few more nights and this fills in."),
        ]
        for (level, expected) in cases {
            XCTAssertEqual(TodayDayModel.readinessSentence(level: level, days: [],
                                                          today: "2026-10-29"), expected)
        }
    }

    func testReadinessSentenceExplainsStaleStrapOnlyAfterThreshold() {
        let learning = "Still learning your baseline. A few more nights and this fills in."
        XCTAssertEqual(TodayDayModel.readinessSentence(level: .insufficient,
                                                      days: [night("2026-10-15", hrv: 42)], today: "2026-10-29"), learning)
        XCTAssertEqual(TodayDayModel.readinessSentence(level: .insufficient,
                                                      days: [night("2026-10-14", hrv: 42)], today: "2026-10-29"),
                       "No new nights from your strap for 15 days. Check it's connected and saving data.")
        XCTAssertEqual(TodayDayModel.readinessSentence(level: .balanced,
                                                      days: [night("2026-10-14", hrv: 42)], today: "2026-10-29"),
                       "You're in a good spot for training.")
        XCTAssertEqual(TodayDayModel.readinessSentence(level: .insufficient,
                                                      days: [night("2026-10-14", hrv: nil)], today: "2026-10-29"), learning)
    }

    func testStrainBandsPreserveBoundariesOnTwentyOneScale() {
        XCTAssertNil(CoupledView.strainBand(strain21: nil))
        let cases: [(Double, CoupledView.StrainBand)] = [
            (0, .light), (5.999, .light),
            (6, .moderate), (9.999, .moderate),
            (10, .strenuous), (13.999, .strenuous),
            (14, .high), (21, .high),
        ]
        for (strain, expected) in cases {
            XCTAssertEqual(CoupledView.strainBand(strain21: strain), expected, "Strain \(strain)")
        }
    }
    private func night(_ day: String, hrv: Double?) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: nil, avgHrv: hrv, recovery: nil,
                    strain: nil, exerciseCount: nil, spo2Pct: nil, skinTempDevC: nil, respRateBpm: nil)
    }

}
