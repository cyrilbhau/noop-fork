import Foundation
import StrandAnalytics
import StrandDesign

// The words of "Recovery context" (stage 6 specification §8.2, §10.7, §11): weekly means of nightly
// resting heart rate and HRV beside the scorecard, as context for the coach. Display only: no score,
// band, tier, colour state or adjective, no current value, and a week below the minimum is "not
// measured", never zero. The typical range is `ChargeTypicalBand.range(_:)`, the one the Recovery
// screen draws, and is printed as text, never drawn on the curve.
//
// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).

/// One metric's card.
struct CutStressCard: Equatable {
    var title: String
    /// One per week of the result: that week's mean, nil where the week has none (the line breaks).
    var points: [Double?]
    /// Always nil (§10.7): no event mark is drawn on these curves.
    var axisMarks: NoopChartAxisMarks?
    /// Exactly `ChargeTypicalBand.range` of the metric's baseline; nil while it is not usable.
    var typicalRange: ClosedRange<Double>?
    /// Every other visible string of the card, top to bottom.
    var lines: [String]
    /// The time axis labels under the curve: the first and the last week shown.
    var firstLabel: String
    var lastLabel: String
}

struct CutStressPresentation: Equatable {
    var framing: String
    /// "Last 12 weeks" or "Since <date>".
    var periodText: String
    var restingHr: CutStressCard
    var hrv: CutStressCard
}

enum CutStressPresenter {
    /// The fewest nights a week needs for a weekly average (§15 Q9).
    static let minNightsPerWeek = 4
    /// Weeks shown from a cut phase's first week, and without one.
    static let maxWeeksWithPhase = 26
    static let weeksWithoutPhase = 12

    /// The screen's title and the scorecard's link.
    static var title: String { String(localized: "Recovery context") }

    static func present(_ result: CutStressResult, restingHrBaseline: BaselineState?, hrvBaseline: BaselineState?,
                        firstWeekStart: String?, locale: Locale) -> CutStressPresentation {
        let words = CutScorecardPresenter.Wording(unitSystem: .metric, locale: locale)
        let period = firstWeekStart.map { String(localized: "Since \(words.shortDate($0))") }
            ?? String(localized: "Last 12 weeks")
        return CutStressPresentation(
            framing: String(localized: "Weekly averages of your nightly resting heart rate and HRV, as context for your coach. They are not a score and no score uses them."),
            periodText: period,
            restingHr: card(result, title: String(localized: "Resting heart rate"), unit: String(localized: "bpm"),
                            mean: \.restingHrMean, nights: \.restingHrNights, change: result.restingHrChange,
                            baseline: restingHrBaseline, words: words),
            hrv: card(result, title: String(localized: "HRV"), unit: String(localized: "ms"),
                      mean: \.hrvMean, nights: \.hrvNights, change: result.hrvChange,
                      baseline: hrvBaseline, words: words))
    }

    private static func card(_ result: CutStressResult, title: String, unit: String,
                             mean: KeyPath<CutStressWeek, Double?>, nights: KeyPath<CutStressWeek, Int>,
                             change: CutStressChange?, baseline: BaselineState?,
                             words: CutScorecardPresenter.Wording) -> CutStressCard {
        let weeks = result.weeks
        let value = { (x: Double) in "\(words.fixed(x, 1)) \(unit)" }
        var lines: [String] = []
        let latest = weeks.last { $0[keyPath: mean] != nil }
        let current = weeks.last.flatMap { $0.isCurrentWeek ? $0 : nil }
        if weeks.allSatisfy({ $0[keyPath: nights] == 0 }) {
            lines.append(String(localized: "Not measured yet. These come from nights recorded by your strap."))
        } else if let latest, let latestMean = latest[keyPath: mean] {
            lines.append(String(localized: "Latest week average"))
            lines.append(value(latestMean))
            if latest.isCurrentWeek { lines.append(String(localized: "this week so far")) }
            lines.append(nightsText(latest[keyPath: nights]))
            if let change {
                lines.append(String(localized: "First week shown"))
                lines.append(value(change.from))
                lines.append(String(localized: "Change"))
                lines.append(value(change.delta).signedForChange(change.delta))
            } else {
                lines.append(String(localized: "Needs a second week"))
            }
        } else {
            lines.append(String(localized: "Not measured yet"))
            if let counted = weeks.last(where: { $0[keyPath: nights] > 0 && !$0.isCurrentWeek }) {
                lines.append(String(localized: "Week of \(words.shortDate(counted.weekStart))"))
                lines.append(nightsText(counted[keyPath: nights]))
            }
        }
        if let current, current[keyPath: mean] == nil, current[keyPath: nights] > 0 {
            lines.append(String(localized: "This week so far: \(current[keyPath: nights]) nights. A weekly average needs \(minNightsPerWeek)."))
        }
        let range = ChargeTypicalBand.range(baseline)
        if let range {
            lines.append(String(localized: "Your typical range"))
            lines.append(String(localized: "\(words.fixed(range.lowerBound, 1)) to \(value(range.upperBound))"))
        } else {
            lines.append(String(localized: "Typical range: still calibrating"))
        }
        let hasCurve = weeks.contains { $0[keyPath: mean] != nil }
        return CutStressCard(
            title: title, points: weeks.map { $0[keyPath: mean] }, axisMarks: nil, typicalRange: range, lines: lines,
            firstLabel: hasCurve ? weeks.first.map { words.shortDate($0.weekStart) } ?? "" : "",
            lastLabel: hasCurve ? weeks.last.map { words.shortDate($0.weekStart) } ?? "" : "")
    }

    private static func nightsText(_ count: Int) -> String {
        String(localized: "\(count) of 7 nights")
    }
}

private extension String {
    /// A change with its sign: "+4.3 bpm", "−5.3 ms" (a true minus sign), "0.0 bpm".
    func signedForChange(_ delta: Double) -> String {
        if hasPrefix("-") { return "\u{2212}" + dropFirst() }
        return delta > 0 ? "+" + self : self
    }
}
