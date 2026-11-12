// API ASSUMED BY THESE TESTS
//
// Written from docs/personal/superapp/specs/stage-6.md §8.2, §10.7, §11, §12.3 and §13.3 before the
// implementation exists. The full API block (`CutStressPresenter`, `CutStressPresentation`,
// `CutStressCard`) is at the top of Stage6TestSupport.swift. Results come from the merged pure
// function `CutStressTrend.weekly` over the §13.3 nights; the typical range comes from the existing
// `ChargeTypicalBand.range(_:)`.
//
// Behaviour assumed where the specification leaves it unstated:
//
//  1. "Latest week average" is the latest week that has a mean; "this week so far" qualifies it
//     when that week is the current week. "First week shown" is the earliest week with a mean
//     (`CutStressChange.from`, the design's reading).
//  2. Means and the change are written to one decimal; the change carries "+" or a minus sign.
//  3. `points` is `result.weeks.map(\.restingHrMean)` (or `hrvMean`): one point per week, nil where
//     the week has no mean, so the line breaks there and nothing is drawn at zero.
//  4. `periodText` is "Since <date>" when the presenter is given the phase's first week, else
//     "Last 12 weeks".
//
// Not pinnable here: Loading (skeleton), the largest text size and Reduce Motion are view behaviour.
//
// Synthetic values only (§13.3; the baselines are invented).

import XCTest
import StrandAnalytics
import StrandDesign
@testable import Strand

final class CutStressPresenterTests: XCTestCase {

    private typealias Fx = Stage6Fixture
    private let gb = Stage6Fixture.british

    private static let framing = "Weekly averages of your nightly resting heart rate and HRV, as context for your "
        + "coach. They are not a score and no score uses them."

    private static let restingBaseline = BaselineState(baseline: 54, spread: 1.6, nValid: 40, nightsSinceUpdate: 0,
                                                       status: .trusted)
    private static let hrvBaseline = BaselineState(baseline: 57, spread: 5.2, nValid: 40, nightsSinceUpdate: 0,
                                                   status: .provisional)
    private static let calibrating = BaselineState(baseline: 55, spread: 2, nValid: 3, nightsSinceUpdate: 0,
                                                   status: .calibrating)

    // MARK: §13.3

    private static func nights(_ days: [String], rhr: [Double?], hrv: [Double?]) -> [CutStressNight] {
        days.indices.map { CutStressNight(day: days[$0], restingHr: rhr[$0], hrv: hrv[$0]) }
    }

    private static func run(_ first: String, _ count: Int) -> [String] {
        (0..<count).map { CanonicalDay.key(CanonicalDay.number(first)! + $0) }
    }

    static let fixtureNights: [CutStressNight] = {
        var out: [CutStressNight] = []
        out += nights(run("2031-01-06", 7), rhr: Array(repeating: 60, count: 7), hrv: Array(repeating: 50, count: 7))
        out += nights(run("2031-01-13", 4), rhr: Array(repeating: 61, count: 4), hrv: Array(repeating: 48, count: 4))
        out += nights(run("2031-01-20", 3), rhr: Array(repeating: 62, count: 3), hrv: Array(repeating: 47, count: 3))
        out += nights(run("2031-01-27", 7), rhr: [63, 63, 64, 64, 65, 65, 66], hrv: [46, 46, 45, 45, 44, 44, 43])
        out += nights(run("2031-02-03", 3), rhr: Array(repeating: 64, count: 3), hrv: Array(repeating: 45, count: 3))
        out.append(CutStressNight(day: "2031-01-17", restingHr: 500, hrv: nil))
        out.append(CutStressNight(day: "2031-01-18", restingHr: nil, hrv: .nan))
        out.append(CutStressNight(day: "2031-02-09", restingHr: 64, hrv: 45))
        out.append(CutStressNight(day: "2030-12-30", restingHr: 60, hrv: 50))
        return out
    }()

    private func result(_ nights: [CutStressNight] = fixtureNights, first: String? = "2031-01-06",
                        today: String = "2031-02-05", maxWeeks: Int = 26) -> CutStressResult {
        CutStressTrend.weekly(CutStressInput(nights: nights, firstWeekStart: first, today: today, maxWeeks: maxWeeks))
    }

    private func present(_ result: CutStressResult, first: String? = "2031-01-06",
                         rhr: BaselineState? = restingBaseline, hrv: BaselineState? = hrvBaseline) -> CutStressPresentation {
        CutStressPresenter.present(result, restingHrBaseline: rhr, hrvBaseline: hrv, firstWeekStart: first, locale: gb)
    }

    private func lines(_ card: CutStressCard) -> String { card.lines.joined(separator: "\n") }

    // MARK: §10.7 states

    func testDefaultState() {
        let r = result()
        XCTAssertEqual(r.weeks.map(\.weekStart), ["2031-01-06", "2031-01-13", "2031-01-20", "2031-01-27", "2031-02-03"])
        let p = present(r)
        XCTAssertEqual(p.framing, Self.framing)
        XCTAssertEqual(p.restingHr.title, "Resting heart rate")
        XCTAssertEqual(p.hrv.title, "HRV")
        XCTAssertEqual(p.restingHr.points, [60.0, 61.0, nil, 64.286, nil])
        XCTAssertEqual(p.hrv.points, [50.0, 48.0, nil, 44.714, nil])

        let rhr = lines(p.restingHr)
        for part in ["Latest week average", "64.3", "7 of 7 nights", "First week shown", "60.0", "Change", "4.3",
                     "Your typical range"] {
            XCTAssertTrue(rhr.contains(part), "\(part) missing from:\n\(rhr)")
        }
        XCTAssertTrue(rhr.contains("+4.3"), "the change is signed:\n\(rhr)")
        let hrv = lines(p.hrv)
        for part in ["44.7", "50.0", "5.3", "7 of 7 nights"] {
            XCTAssertTrue(hrv.contains(part), "\(part) missing from:\n\(hrv)")
        }
        XCTAssertTrue(hrv.contains("\u{2212}5.3") || hrv.contains("-5.3"), "a fall carries its sign:\n\(hrv)")
    }

    func testCurrentWeekBelowTheMinimum() {
        let p = present(result())
        XCTAssertNil(p.restingHr.points.last ?? nil, "the curve ends at the last full week")
        XCTAssertTrue(p.restingHr.lines.contains("This week so far: 3 nights. A weekly average needs 4."),
                      lines(p.restingHr))
        XCTAssertTrue(p.hrv.lines.contains("This week so far: 3 nights. A weekly average needs 4."))
        XCTAssertFalse(lines(p.restingHr).contains("this week so far"), "the latest mean is a past week's")
    }

    func testCurrentWeekAtOrAboveTheMinimum() {
        let r = result(Self.fixtureNights.filter { $0.day <= "2031-01-16" && $0.day >= "2031-01-06" }, today: "2031-01-16")
        XCTAssertEqual(r.weeks.last?.restingHrNights, 4)
        let p = present(r)
        XCTAssertEqual(p.restingHr.points, [60.0, 61.0])
        let rhr = lines(p.restingHr)
        XCTAssertTrue(rhr.contains("61.0"), rhr)
        XCTAssertTrue(rhr.contains("this week so far"), rhr)
        XCTAssertTrue(rhr.contains("4 of 7 nights"), rhr)
        XCTAssertFalse(rhr.contains("A weekly average needs"), rhr)
    }

    func testAWeekBelowTheMinimumInTheMiddleBreaksTheLine() {
        let p = present(result())
        XCTAssertNotNil(p.restingHr.points[1])
        XCTAssertNil(p.restingHr.points[2], "the week of 20 Jan has three nights: no point, never drawn across")
        XCTAssertNotNil(p.restingHr.points[3])
    }

    func testOnlyOneWeekHasAMean() {
        let r = result(Self.fixtureNights.filter { $0.day >= "2031-01-06" && $0.day <= "2031-01-12" }, today: "2031-01-14")
        let p = present(r)
        let rhr = lines(p.restingHr)
        XCTAssertTrue(rhr.contains("60.0"), rhr)
        XCTAssertTrue(p.restingHr.lines.contains("Needs a second week"), rhr)
        XCTAssertFalse(p.restingHr.lines.contains("Change"), "no change line")
    }

    func testNoWeekHasAMean() {
        let r = result(Self.fixtureNights.filter { $0.day >= "2031-01-06" && $0.day <= "2031-01-08" }, today: "2031-01-10")
        let p = present(r)
        XCTAssertTrue(p.restingHr.points.allSatisfy { $0 == nil })
        XCTAssertTrue(p.restingHr.lines.contains("Not measured yet"), lines(p.restingHr))
        XCTAssertTrue(lines(p.restingHr).contains("3"), "the night count is shown")
        XCTAssertFalse(p.restingHr.lines.contains("Latest week average"))
    }

    func testNoNightsAtAll() {
        let p = present(result([], first: nil, today: "2031-02-05"), first: nil)
        XCTAssertEqual(p.restingHr.points, [])
        XCTAssertTrue(p.restingHr.lines.contains("Not measured yet. These come from nights recorded by your strap."),
                      lines(p.restingHr))
        XCTAssertTrue(p.hrv.lines.contains("Not measured yet. These come from nights recorded by your strap."))
    }

    func testTypicalRangeNotAvailable() {
        let p = present(result(), rhr: Self.calibrating, hrv: nil)
        XCTAssertNil(p.restingHr.typicalRange)
        XCTAssertNil(p.hrv.typicalRange)
        XCTAssertTrue(p.restingHr.lines.contains("Typical range: still calibrating"), lines(p.restingHr))
        XCTAssertTrue(p.hrv.lines.contains("Typical range: still calibrating"))
        XCTAssertFalse(lines(p.restingHr).contains("Your typical range"))
    }

    func testHrvPresentRestingHeartRateAbsent() {
        let hrvOnly = Self.fixtureNights.map { CutStressNight(day: $0.day, restingHr: nil, hrv: $0.hrv) }
        let p = present(result(hrvOnly))
        XCTAssertTrue(p.restingHr.points.allSatisfy { $0 == nil })
        XCTAssertTrue(lines(p.restingHr).contains("Not measured yet"), lines(p.restingHr))
        XCTAssertEqual(p.hrv.points, [50.0, 48.0, nil, 44.714, nil], "each card stands alone")
        XCTAssertTrue(lines(p.hrv).contains("44.7"))
    }

    func testNoCutPhaseStartedSaysLastTwelveWeeks() {
        let p = present(result(first: nil, maxWeeks: 12), first: nil)
        XCTAssertEqual(p.periodText, "Last 12 weeks")
    }

    func testPhaseStartedSaysSinceItsFirstWeek() {
        let p = present(result())
        XCTAssertTrue(p.periodText.hasPrefix("Since "), p.periodText)
        XCTAssertTrue(p.periodText.contains("6") && p.periodText.contains("Jan"), p.periodText)
    }

    func testStrapDisconnectedStoredNightsStillShow() {
        let r = result(Self.fixtureNights.filter { $0.day <= "2031-02-05" }, today: "2031-02-26")
        let p = present(r)
        XCTAssertEqual(Array(p.restingHr.points.prefix(4)), [60.0, 61.0, nil, 64.286])
        XCTAssertTrue(p.restingHr.points.dropFirst(4).allSatisfy { $0 == nil }, "later weeks read not measured")
        XCTAssertTrue(lines(p.restingHr).contains("64.3"))
    }

    // MARK: §8.2: no score, no judgement, no zero

    private func everyState() -> [CutStressPresentation] {
        let filters: [(CutStressNight) -> Bool] = [{ _ in true }, { $0.day <= "2031-01-12" }, { $0.day <= "2031-01-08" },
                                                   { _ in false }]
        var out: [CutStressPresentation] = []
        for keep in filters {
            for today in ["2031-01-10", "2031-01-16", "2031-02-05", "2031-02-26"] {
                let nights = Self.fixtureNights.filter(keep).filter { $0.day <= today }
                for first in ["2031-01-06", nil] as [String?] {
                    for baselines in [(Self.restingBaseline, Self.hrvBaseline), (Self.calibrating, Self.calibrating)] {
                        out.append(present(result(nights, first: first, today: today), first: first,
                                           rhr: baselines.0, hrv: baselines.1))
                    }
                }
            }
        }
        return out
    }

    func testNoStringCarriesAJudgementWord() {
        let words = ["elevated", "suppressed", "high", "higher", "low", "lower", "good", "bad", "warning", "stress",
                     "stressed", "better", "worse", "improving", "poor"]
        var scanned = 0
        for p in everyState() {
            for text in Stage6Text.strings(in: p) where text != Self.framing {
                scanned += 1
                for word in words {
                    XCTAssertFalse(Stage6Text.containsWord(text, word), "\"\(word)\" in: \(text)")
                }
            }
        }
        XCTAssertGreaterThan(scanned, 100)
    }

    func testTheFramingSentenceSaysItIsNotAScore() {
        for p in everyState() { XCTAssertEqual(p.framing, Self.framing) }
    }

    func testChartIsGivenNoAxisMarks() {
        for p in everyState() {
            XCTAssertNil(p.restingHr.axisMarks)
            XCTAssertNil(p.hrv.axisMarks)
        }
    }

    func testNightCountsAreShownBesideEveryMean() {
        let p = present(result())
        XCTAssertTrue(p.restingHr.lines.contains("7 of 7 nights"), lines(p.restingHr))
        let current = present(result(Self.fixtureNights.filter { $0.day >= "2031-01-06" && $0.day <= "2031-01-16" },
                                     today: "2031-01-16"))
        XCTAssertTrue(current.restingHr.lines.contains("4 of 7 nights"), lines(current.restingHr))
        for state in everyState() {
            for card in [state.restingHr, state.hrv] where card.lines.contains("Latest week average") {
                XCTAssertTrue(card.lines.contains { $0.range(of: "^[1-7] of 7 nights$", options: .regularExpression) != nil },
                              "a mean without its night count:\n\(lines(card))")
            }
        }
    }

    func testWeekBelowMinimumIsNotMeasuredNeverZero() {
        for p in everyState() {
            for card in [p.restingHr, p.hrv] {
                XCTAssertFalse(card.points.contains(0), "a zero point")
                for text in card.lines {
                    XCTAssertNil(text.range(of: "(^|[^0-9.,])0([.,]0)? ?(bpm|ms)", options: .regularExpression),
                                 "a measured-looking zero: \(text)")
                    XCTAssertNotEqual(text, "0")
                    XCTAssertNotEqual(text, "0.0")
                }
            }
        }
    }

    func testTypicalRangeEqualsChargeTypicalBand() {
        // The single resolver, at the presenter: the range the card carries and prints is
        // `ChargeTypicalBand.range` of the same state, for every usable and unusable status.
        // (Recovery detail's factor is in the iPhone-only target; Tools/test_stage6_single_source.py
        // asserts it calls the same function.)
        for status in [BaselineStatus.calibrating, .provisional, .trusted, .stale] {
            let state = BaselineState(baseline: 54, spread: 1.6, nValid: 40, nightsSinceUpdate: 0, status: status)
            let p = present(result(), rhr: state, hrv: state)
            XCTAssertEqual(p.restingHr.typicalRange, ChargeTypicalBand.range(state), "\(status)")
            XCTAssertEqual(p.hrv.typicalRange, ChargeTypicalBand.range(state), "\(status)")
            if let range = ChargeTypicalBand.range(state) {
                let text = lines(p.restingHr)
                let low = [String(format: "%.0f", range.lowerBound), String(format: "%.1f", range.lowerBound)]
                let high = [String(format: "%.0f", range.upperBound), String(format: "%.1f", range.upperBound)]
                XCTAssertTrue(low.contains { text.contains($0) }, "the printed range starts at \(range.lowerBound):\n\(text)")
                XCTAssertTrue(high.contains { text.contains($0) }, "the printed range ends at \(range.upperBound):\n\(text)")
                XCTAssertTrue(text.contains(" to "), text)
            }
        }
    }

    func testResultHasNoScoreFieldThroughThePresentation() {
        // §6.2 and §8.2: nothing in the presentation reads as a state, tier, band or score.
        let p = present(result())
        let names = Mirror(reflecting: p).children.compactMap(\.label)
            + Mirror(reflecting: p.restingHr).children.compactMap(\.label)
        for name in names {
            for word in ["state", "tier", "band", "score", "elevated", "suppressed", "status"] {
                XCTAssertFalse(name.lowercased().contains(word), "field \(name)")
            }
        }
    }
}
