import XCTest
import StrandAnalytics
import WhoopStore
@testable import Strand

// Stage 1 (weigh-in and scorecard), work package 1-7: the presenter. Specification §10.1, §10.2,
// §10.6, §11, §17 and the approved frames in design/round6-scorecard (the HTML is the source of
// truth). Written before the implementation exists.
//
// How the expectations were made. Every `ScorecardFrames` literal at the foot of this file is the
// output of the frame builder itself: `present()` in design/round6-scorecard/scorecard.js, run in
// Node over design/round6-scorecard/model.js for the fixture day each frame names. None was typed
// by hand. The `digest` line of each literal is the design model's result for that day; the test
// `testEveryFrameResultCarriesTheFactsItsStringsAreBuiltFrom` compares it with what the real
// `CutScorecard.evaluate` returns for the same input, so a string expected here is never built on
// a number the implementation does not produce.
//
// API ASSUMED BY THESE TESTS (new, in Strand/Data/CutScorecardPresenter.swift)
//
//     /// The one state a scorecard surface is in. Precedence, first match wins:
//     /// rulesNeedAttention, noCutPhase, phaseNotStarted, noReadings, overdue, due, oneReading,
//     /// targetReached, verdictWithheld, building, verdict. `loading` and `pastDay` are card-only.
//     enum CutScorecardStatus: Equatable {
//         case loading, pastDay
//         case rulesNeedAttention     // the stored rules failed validation, or result.invalidInput is set
//         case noCutPhase             // verdict reason noActivePhase
//         case phaseNotStarted        // verdict reason phaseNotStarted
//         case noReadings             // verdict reason noReadings
//         case overdue                // verdict reason weighInOverdue
//         case due                    // a started phase, the judged week is before today's week, not overdue
//         case oneReading             // exactly one in-phase week has a weight
//         case targetReached          // projection status targetReached
//         case verdictWithheld        // verdict reason recompositionCheckIncomplete
//         case building               // verdict reason noRuleEvaluable with more than one weigh-in
//         case verdict                // everything else
//     }
//
//     struct CutScorecardCard: Equatable {
//         var status: CutScorecardStatus
//         var title: String           // "Scorecard"
//         var value: String?          // nil draws the dash; never "0" for a missing weight
//         var unit: String?           // "kg" or "lb"; nil when value is nil
//         var caption: String?        // nil only while loading
//         var isDimmed: Bool          // the value in the tertiary colour (overdue)
//         var opensScorecard: Bool    // false while loading and for a past day
//     }
//
//     struct CutScorecardPresentation: Equatable {
//         struct PhaseHeader: Equatable { var label: String; var name: String; var detail: String }
//         struct Banner: Equatable { var title: String; var detail: String }
//         enum VerdictAction: Equatable { case setUpPhase, openPhaseAndRules }
//         struct Verdict: Equatable {
//             var header: String              // "Verdict · week of 27 Jan", or "Verdict"
//             var signalsSummary: String?     // "4 of 4 signals met"; nil when every signal is unknown
//             var title: String
//             var isWithheld: Bool            // no verdict is given: drawn in the neutral style
//             var lines: [String]
//             var couldNotCheck: [String]
//             var ownRuleNote: String?        // only under addCalories and reduceCarbs
//             var explanation: String?        // only for noCutPhase and rulesNeedAttention
//             var action: VerdictAction?
//             var actionTitle: String?
//         }
//         struct RuleRow: Equatable {
//             var rule: CutScorecardRule; var name: String
//             var state: CutScorecardRuleState; var stateWord: String; var detail: String?
//         }
//         struct SignalRow: Equatable {
//             var title: String; var state: CutScorecardSignalState; var stateWord: String
//             var reason: String; var detail: String?
//         }
//         struct Fact: Equatable { var label: String; var value: String?; var unit: String? }
//         struct Curve: Equatable {
//             var title: String               // "Weight", "Waist"
//             var value: String; var unit: String; var provenance: String
//             var points: [Double?]           // one per week shown, in the display unit; nil = no reading (the line breaks)
//             var firstLabel: String; var lastLabel: String
//             var facts: [Fact]               // two
//             var note: String?
//         }
//         struct Projection: Equatable {
//             var label: String; var isEstimate: Bool; var estimateLabel: String?   // "Estimate"
//             var text: String; var detail: String?
//         }
//
//         var status: CutScorecardStatus
//         var phase: PhaseHeader?
//         var dueBanner: Banner?
//         var targetBanner: Banner?
//         var verdict: Verdict
//         var rules: [RuleRow]                // empty when the rule rows are hidden
//         var signals: [SignalRow]            // always four: waist, lifts, protein, rate
//         var liftFootnote: String
//         var weight: Curve?
//         var waist: Curve?
//         var emptyCurvesText: String?        // set exactly when `weight` is nil
//         var projection: Projection
//         var logWeighInIsPrimary: Bool
//         var historyValue: String            // "5 weigh-ins"
//         var phaseLinkValue: String          // the phase name, or "Not set up"
//         var card: CutScorecardCard
//     }
//
//     struct CutScorecardPresentationContext {
//         var unitSystem: UnitSystem                  // .metric: kg and cm. .imperial: lb and in
//         var weightSource: BodyMeasurementSource     // where result.currentWeightKg came from
//         var rulesNeedAttention: Bool                // CutScorecardSettings.rulesNeedAttention
//         var locale: Locale
//         init(unitSystem: UnitSystem = .metric, weightSource: BodyMeasurementSource = .labBook,
//              rulesNeedAttention: Bool = false, locale: Locale = AppLanguage.activeLocale)
//     }
//
//     enum WeighInReminderStatus: Equatable { case off, on, denied }
//
//     struct CutScorecardSettingsPresentation: Equatable {
//         var toggleTitle: String
//         var reminderTitle: String?      // nil while the flag is off: the row is not shown
//         var reminderIsOn: Bool
//         var day: String?; var time: String?             // only while the reminder is on
//         var footnote: String?
//         var previewTitle: String?; var previewBody: String?   // only while the reminder is on
//         var deniedTitle: String?; var deniedDetail: String?; var deniedActionTitle: String?
//     }
//
//     enum CutScorecardPresenter {
//         /// Pure. `input` is the input `result` was evaluated from (phase, parameters, today).
//         static func present(_ result: CutScorecardResult, input: CutScorecardInput,
//                             context: CutScorecardPresentationContext) -> CutScorecardPresentation
//         static func loadingCard() -> CutScorecardCard
//         static func pastDayCard() -> CutScorecardCard
//         static func sourceCaption(_ source: BodyMeasurementSource) -> String
//         static func settings(flagEnabled: Bool, reminder: WeighInReminderStatus, weekday: Int,
//                              minuteOfDay: Int, locale: Locale) -> CutScorecardSettingsPresentation
//     }
//
// Behaviour assumed where §10 and §11 leave it open (each is what the frame builder does):
//
//  1. Dates are day-first as drawn: "Wed 29 Jan" (weekday, day, month) and "27 Jan" for a week. The
//     tests pass `Locale(identifier: "en_GB")`.
//  2. Weights show one decimal, rates two, percentages two. Pounds are kilograms × 2.20462 and inches
//     centimetres ÷ 2.54 (`UnitFormatter`). A change is converted as a difference. A negative change
//     is written with U+2212, "−1.0". The slow-loss threshold drops trailing zeros: "0.4 kg".
//  3. An absent line is nil, never "". A missing value is nil, never "0".
//  4. The curves show the weeks of the phase once it has started, otherwise every week, up to the
//     week of `today`; a week with no reading is a nil point.
//  5. `historyValue` counts `input.weights` dated on or before `input.today`.
//  6. A rule row's progress is capped at the rule's window ("3 of 3 weeks"), while the reason line
//     under a reduce-carbohydrate verdict gives the uncapped run ("for 5 weeks"), as drawn in B11.
//  7. Rule 1 has no window, so its row has no progress; with nothing else to say its detail is nil.
//  8. The rule rows are hidden (empty) with no cut phase, before the phase starts, and when the
//     rules need attention.
//
// Wording. §11 is the source for every string it lists. The frames draw more than §11 lists (the
// phase header, the banners, the rule rows and why a rule could not be checked, the numbers line
// under each signal, "No current weigh-in", "Not measured yet", the curve captions, the "to go"
// line, the card title, the Settings rows); those are asserted as drawn. README decision 7 marks
// them as the designer's proposals, approved with the frames (§17).
//
// Synthetic values only: the "Fixture Person" of specification §13.

// MARK: - The §13 fixture as an evaluate() input (a port of fixtureInput in design/round6-scorecard/model.js)

enum ScorecardScreenFixture {
    static let phase = CutScorecardPhase(name: "Fixture cut", startDay: "2031-01-06", targetWeightKg: 94.0,
                                         rateLowPercentPerWeek: 0.40, rateHighPercentPerWeek: 1.20)
    static let parameters = CutScorecardParameters(
        rateWindowWeeks: 4, waistWindowWeeks: 2, waistMinDecreaseCm: 0.5, liftDropTolerancePercent: 5,
        liftDropShare: 0.5, liftDropConsecutiveWeeks: 3, addCaloriesKcal: 300,
        slowLossThresholdKgPerWeek: 0.4, slowLossConsecutiveWeeks: 3, reduceCarbsKcal: 250,
        proteinFloorGrams: 100, proteinMinDaysPerWeek: 5, maxWeighInAgeWeeks: 1, maxProjectionWeeks: 104,
        targetToleranceKg: 0)

    /// Weeks 1 to 22; nil is the missed week 10.
    static let weights: [Double?] = [100.0, 99.2, 98.4, 97.6, 97.5, 97.4, 97.3, 97.2, 97.1, nil, 96.0, 95.2,
                                     95.1, 95.0, 94.9, 94.8, 94.7, 94.6, 94.5, 95.5, 94.0, 93.5]
    static let waists: [Double?] = [100.0, 99.5, 99.0, 98.5, 98.0, 97.5, 97.0, 97.0, 97.0, nil, 96.5, 96.0,
                                    95.5, 95.0, 94.5, 94.5, 94.5, 94.5, 94.5, 94.5, 94.0, 93.5]
    /// Week number (the Monday of that week) to Fixture Press and Fixture Row, in kilograms.
    static let lifts: [Int: (Double, Double)] = [
        -1: (60, 50), 0: (60, 50), 1: (60, 50), 2: (60, 50), 3: (60, 50), 4: (60, 50), 5: (62.5, 50),
        6: (62.5, 50), 7: (62.5, 52.5), 8: (62.5, 52.5), 9: (62.5, 52.5), 16: (62.5, 52.5),
        17: (57.5, 47.5), 18: (52.5, 42.5), 19: (47.5, 40), 20: (47.5, 40), 21: (47.5, 40), 22: (50, 40),
    ]
    /// Week number to the seven days before its weigh-in, oldest first.
    static let protein: [Int: [Double?]] = [
        2: [120, 120, 120, 80, 120, 120, 120], 3: [120, 120, 120, 80, 120, 120, 120],
        4: [120, 120, 120, 80, 120, 120, 120], 5: [120, 80, 80, 120, 80, 80, 120],
        6: [120, nil, 120, nil, nil, 120, nil],
    ]

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static let keys: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = utc
        formatter.timeZone = utc.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Midnight UTC of a day key.
    static func date(_ day: String) -> Date { keys.date(from: day)! }

    static func day(_ day: String, plus days: Int) -> String {
        keys.string(from: utc.date(byAdding: .day, value: days, to: date(day))!)
    }

    /// The Wednesday weigh-in day of a fixture week (week 1 is 2031-01-08).
    static func weighDay(_ week: Int) -> String { day("2031-01-08", plus: 7 * (week - 1)) }

    /// 07:00 UTC on a day, epoch seconds (§13.1).
    static func takenAt(_ day: String) -> Int { Int(date(day).timeIntervalSince1970) + 7 * 3_600 }

    static func input(today: String, phase: CutScorecardPhase? = ScorecardScreenFixture.phase,
                      parameters: CutScorecardParameters = ScorecardScreenFixture.parameters,
                      lifts withLifts: Bool = true, without: Set<Int> = []) -> CutScorecardInput {
        var weightReadings: [CutScorecardReading] = []
        var waistReadings: [CutScorecardReading] = []
        for (index, weight) in weights.enumerated() {
            let week = index + 1
            guard let weight, !without.contains(week) else { continue }
            let day = weighDay(week)
            weightReadings.append(CutScorecardReading(day: day, takenAt: takenAt(day), value: weight))
            if let waist = waists[index] {
                waistReadings.append(CutScorecardReading(day: day, takenAt: takenAt(day), value: waist))
            }
        }
        if !without.contains(3) {   // the extra Monday reading of week 3, which must lose to Wednesday's
            weightReadings.append(CutScorecardReading(day: "2031-01-20", takenAt: takenAt("2031-01-20"), value: 98.9))
        }
        var observations: [CutScorecardLiftObservation] = []
        if withLifts {
            for (week, loads) in lifts.sorted(by: { $0.key < $1.key }) {
                let monday = day("2031-01-06", plus: 7 * (week - 1))
                observations.append(CutScorecardLiftObservation(day: monday, exercise: "Fixture Press", weightKg: loads.0))
                observations.append(CutScorecardLiftObservation(day: monday, exercise: "Fixture Row", weightKg: loads.1))
            }
        }
        var proteinDays: [CutScorecardProteinDay] = []
        for (week, grams) in protein.sorted(by: { $0.key < $1.key }) {
            for (offset, value) in grams.enumerated() {
                guard let value else { continue }
                proteinDays.append(CutScorecardProteinDay(day: day(weighDay(week), plus: offset - 7), grams: value))
            }
        }
        return CutScorecardInput(weights: weightReadings, waists: waistReadings, lifts: observations,
                                 proteinDays: proteinDays, phase: phase, parameters: parameters, today: today)
    }

    /// Every String reachable from a value, by reflection, so a scan needs no list of fields.
    static func strings(in value: Any) -> [String] {
        if let text = value as? String { return [text] }
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            return mirror.children.first.map { strings(in: $0.value) } ?? []
        }
        return mirror.children.flatMap { strings(in: $0.value) }
    }
}

extension Array {
    /// The element at an index, or nil, so that a short array fails an assertion instead of trapping.
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// One frame as its builder drew it. In the string lists "" stands for "no such line".
struct ScorecardFrame {
    var digest: String
    var phase: [String]?            // label, name, detail
    var due: [String]?              // title, detail
    var reached: [String]?          // title, detail
    var header: String
    var summary: String?
    var title: String
    var withheld: Bool
    var lines: [String]
    var couldNotCheck: [String]
    var ownRule: Bool
    var rules: [[String]]           // name, state word, detail; empty when the rows are hidden
    var signals: [[String]]         // title, state word, reason, detail
    var weight: [String]?           // value, provenance, points, first label, last label, rate label, rate, percent, note
    var waist: [String]?            // value, provenance, points, first fact label, its value, second fact label, its value
    var projection: [String]        // label, text, detail
    var estimate: Bool
    var logPrimary: Bool
    var history: String
    var phaseLink: String
    var card: [String]              // value, caption
    var cardDimmed: Bool
}

final class CutScorecardPresenterTests: XCTestCase {

    // MARK: - Harness

    private typealias Fixture = ScorecardScreenFixture

    private let british = Locale(identifier: "en_GB")
    private let ownRuleNote = "This is your own rule applied to your own numbers. Nothing has been changed."
    private let liftFootnote = "Compares the heaviest working set of each exercise with the week before."

    private struct Case {
        let name: String
        let frame: ScorecardFrame
        let input: CutScorecardInput
        var unitSystem: UnitSystem = .metric
        var rulesNeedAttention = false
        let status: CutScorecardStatus
        /// False where no frame draws the card for this state: a phase that has not started (B4)
        /// and rules that need attention (B24). Frame A2 draws neither.
        var pinsCard = true
    }

    private static let laterPhase = CutScorecardPhase(name: "Fixture cut", startDay: "2031-02-03", targetWeightKg: 94.0,
                                                      rateLowPercentPerWeek: 0.40, rateHighPercentPerWeek: 1.20)

    private static func phase(target: Double?) -> CutScorecardPhase {
        CutScorecardPhase(name: "Fixture cut", startDay: "2031-01-06", targetWeightKg: target,
                          rateLowPercentPerWeek: 0.40, rateHighPercentPerWeek: 1.20)
    }

    private static func week(_ week: Int) -> CutScorecardInput { Fixture.input(today: Fixture.weighDay(week)) }

    /// Every frame of set B, plus the same builder run on four more fixture days (marked "week").
    private static let cases: [Case] = {
        var noFloor = Fixture.parameters
        noFloor.proteinFloorGrams = nil
        return [
            Case(name: "B1", frame: ScorecardFrames.b1, input: week(4), status: .verdict),
            Case(name: "B2", frame: ScorecardFrames.b2, input: Fixture.input(today: "2031-01-08", without: Set(1...22)),
                 status: .noReadings),
            Case(name: "B3", frame: ScorecardFrames.b3, input: Fixture.input(today: "2031-01-29", phase: nil),
                 status: .noCutPhase),
            Case(name: "B4", frame: ScorecardFrames.b4, input: Fixture.input(today: "2031-01-29", phase: laterPhase),
                 status: .phaseNotStarted, pinsCard: false),
            Case(name: "B5", frame: ScorecardFrames.b5, input: week(1), status: .oneReading),
            Case(name: "B6", frame: ScorecardFrames.b6, input: Fixture.input(today: "2031-01-08", lifts: false),
                 status: .oneReading),
            Case(name: "B7", frame: ScorecardFrames.b7,
                 input: Fixture.input(today: "2031-02-19", phase: laterPhase, lifts: false), status: .building),
            Case(name: "B8", frame: ScorecardFrames.b8, input: week(5), status: .verdict),
            Case(name: "B9", frame: ScorecardFrames.b9, input: week(6), status: .verdict),
            Case(name: "B10", frame: ScorecardFrames.b10, input: week(7), status: .verdict),
            Case(name: "B11", frame: ScorecardFrames.b11, input: week(9), status: .verdict),
            Case(name: "B12", frame: ScorecardFrames.b12, input: Fixture.input(today: "2031-03-12"), status: .due),
            Case(name: "B13", frame: ScorecardFrames.b13, input: week(11), status: .verdict),
            Case(name: "B14", frame: ScorecardFrames.b14, input: week(13), status: .verdict),
            Case(name: "B15", frame: ScorecardFrames.b15, input: week(15), status: .verdictWithheld),
            Case(name: "B16", frame: ScorecardFrames.b16, input: week(17), status: .verdict),
            Case(name: "B17", frame: ScorecardFrames.b17, input: week(19), status: .verdict),
            Case(name: "B18", frame: ScorecardFrames.b18, input: week(20), status: .verdict),
            Case(name: "B19", frame: ScorecardFrames.b19, input: week(21), status: .targetReached),
            Case(name: "B20", frame: ScorecardFrames.b20, input: Fixture.input(today: "2031-03-19", without: [11]),
                 status: .overdue),
            Case(name: "B21", frame: ScorecardFrames.b21,
                 input: Fixture.input(today: "2031-01-29", phase: phase(target: nil), parameters: noFloor),
                 status: .verdict),
            Case(name: "B22", frame: ScorecardFrames.b22,
                 input: Fixture.input(today: "2031-02-26", phase: phase(target: 80)), status: .verdict),
            Case(name: "B23", frame: ScorecardFrames.b23,
                 input: Fixture.input(today: "2031-02-05", phase: phase(target: 97), without: [5]), status: .due),
            Case(name: "B24", frame: ScorecardFrames.b24, input: week(4), rulesNeedAttention: true,
                 status: .rulesNeedAttention, pinsCard: false),
            Case(name: "B25", frame: ScorecardFrames.b25, input: week(4), unitSystem: .imperial, status: .verdict),
            Case(name: "week 2", frame: ScorecardFrames.week2, input: week(2), status: .verdict),
            Case(name: "week 8", frame: ScorecardFrames.week8, input: week(8), status: .verdict),
            Case(name: "week 12", frame: ScorecardFrames.week12, input: week(12), status: .verdict),
            Case(name: "week 22", frame: ScorecardFrames.week22, input: week(22), status: .targetReached),
            Case(name: "week 9 imperial", frame: ScorecardFrames.week9Imperial, input: week(9),
                 unitSystem: .imperial, status: .verdict),
            Case(name: "week 20 imperial", frame: ScorecardFrames.week20Imperial, input: week(20),
                 unitSystem: .imperial, status: .verdict),
        ]
    }()

    private func context(_ unitSystem: UnitSystem = .metric, attention: Bool = false,
                         source: BodyMeasurementSource = .labBook) -> CutScorecardPresentationContext {
        CutScorecardPresentationContext(unitSystem: unitSystem, weightSource: source,
                                        rulesNeedAttention: attention, locale: british)
    }

    private func present(_ input: CutScorecardInput, _ context: CutScorecardPresentationContext? = nil)
        -> CutScorecardPresentation {
        CutScorecardPresenter.present(CutScorecard.evaluate(input), input: input, context: context ?? self.context())
    }

    private func present(_ item: Case) -> CutScorecardPresentation {
        present(item.input, context(item.unitSystem, attention: item.rulesNeedAttention))
    }

    private func named(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> Case {
        try XCTUnwrap(Self.cases.first { $0.name == name }, "no case \(name)", file: file, line: line)
    }

    private func points(_ values: [Double?]) -> String {
        values.map { $0.map { String(format: "%.1f", $0) } ?? "x" }.joined(separator: ",")
    }

    private func word(_ state: CutScorecardSignalState) -> String {
        switch state {
        case .met: return "Met"
        case .notMet: return "Not met"
        case .unknown: return "Unknown"
        }
    }

    private func word(_ state: CutScorecardRuleState) -> String {
        switch state {
        case .fired: return "Fired"
        case .notFired: return "Not fired"
        case .unknown: return "Could not check"
        }
    }

    /// Asserts everything a frame draws, field by field, so a failure names the field.
    private func check(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let item = try named(name, file: file, line: line)
        let frame = item.frame
        let shown = present(item)
        let weightUnit = item.unitSystem == .metric ? "kg" : "lb"
        let lengthUnit = item.unitSystem == .metric ? "cm" : "in"

        XCTAssertEqual(shown.status, item.status, "\(name) status", file: file, line: line)

        XCTAssertEqual(shown.phase.map { [$0.label, $0.name, $0.detail] }, frame.phase, "\(name) phase header",
                       file: file, line: line)
        XCTAssertEqual(shown.dueBanner.map { [$0.title, $0.detail] }, frame.due, "\(name) due banner",
                       file: file, line: line)
        XCTAssertEqual(shown.targetBanner.map { [$0.title, $0.detail] }, frame.reached, "\(name) target banner",
                       file: file, line: line)

        XCTAssertEqual(shown.verdict.header, frame.header, "\(name) verdict header", file: file, line: line)
        XCTAssertEqual(shown.verdict.signalsSummary, frame.summary, "\(name) signals met", file: file, line: line)
        XCTAssertEqual(shown.verdict.title, frame.title, "\(name) verdict title", file: file, line: line)
        XCTAssertEqual(shown.verdict.isWithheld, frame.withheld, "\(name) verdict withheld", file: file, line: line)
        XCTAssertEqual(shown.verdict.lines, frame.lines, "\(name) reason lines", file: file, line: line)
        XCTAssertEqual(shown.verdict.couldNotCheck, frame.couldNotCheck, "\(name) could not check",
                       file: file, line: line)
        XCTAssertEqual(shown.verdict.ownRuleNote, frame.ownRule ? ownRuleNote : nil, "\(name) own-rule note",
                       file: file, line: line)

        XCTAssertEqual(shown.rules.map { [$0.name, $0.stateWord, $0.detail ?? ""] }, frame.rules,
                       "\(name) rule rows", file: file, line: line)
        for row in shown.rules {
            XCTAssertEqual(row.stateWord, word(row.state), "\(name) rule \(row.name) word and state agree",
                           file: file, line: line)
        }
        XCTAssertEqual(shown.rules.map(\.rule), frame.rules.isEmpty ? [] : CutScorecardRule.allCases,
                       "\(name) rule order", file: file, line: line)

        XCTAssertEqual(shown.signals.map { [$0.title, $0.stateWord, $0.reason, $0.detail ?? ""] }, frame.signals,
                       "\(name) signal rows", file: file, line: line)
        for row in shown.signals {
            XCTAssertEqual(row.stateWord, word(row.state), "\(name) signal \(row.title) word and state agree",
                           file: file, line: line)
        }
        XCTAssertEqual(shown.liftFootnote, liftFootnote, "\(name) lift footnote", file: file, line: line)

        if let expected = frame.weight {
            if let curve = shown.weight {
                XCTAssertEqual(curve.title, "Weight", file: file, line: line)
                XCTAssertEqual([curve.value, curve.provenance, points(curve.points), curve.firstLabel, curve.lastLabel],
                               Array(expected[0...4]), "\(name) weight curve", file: file, line: line)
                XCTAssertEqual(curve.unit, weightUnit, "\(name) weight unit", file: file, line: line)
                XCTAssertEqual(curve.facts.map(\.label), [expected[5], "Of bodyweight"], "\(name) weight fact labels",
                               file: file, line: line)
                XCTAssertEqual(curve.facts.map { $0.value ?? "" }, [expected[6], expected[7]],
                               "\(name) rate and percentage", file: file, line: line)
                if !expected[6].isEmpty {
                    XCTAssertEqual(curve.facts.map(\.unit), ["\(weightUnit)/week", "%/week"], "\(name) rate units",
                                   file: file, line: line)
                }
                XCTAssertEqual(curve.note, expected[8], "\(name) weight note", file: file, line: line)
            } else {
                XCTFail("\(name): the weight curve is missing", file: file, line: line)
            }
            XCTAssertNil(shown.emptyCurvesText, "\(name) no empty-curves text beside a curve", file: file, line: line)
        } else {
            XCTAssertNil(shown.weight, "\(name) no weight curve", file: file, line: line)
            XCTAssertEqual(shown.emptyCurvesText, "Not measured yet", "\(name) empty curves", file: file, line: line)
        }

        if let expected = frame.waist {
            if let curve = shown.waist {
                XCTAssertEqual(curve.title, "Waist", file: file, line: line)
                XCTAssertEqual([curve.value, curve.provenance, points(curve.points)], Array(expected[0...2]),
                               "\(name) waist curve", file: file, line: line)
                XCTAssertEqual(curve.unit, lengthUnit, "\(name) waist unit", file: file, line: line)
                XCTAssertEqual(curve.facts.map(\.label), [expected[3], expected[5]], "\(name) waist fact labels",
                               file: file, line: line)
                XCTAssertEqual(curve.facts.map { $0.value ?? "" }, [expected[4], expected[6]], "\(name) waist changes",
                               file: file, line: line)
            } else {
                XCTFail("\(name): the waist curve is missing", file: file, line: line)
            }
        } else {
            XCTAssertNil(shown.waist, "\(name) no waist curve", file: file, line: line)
        }

        XCTAssertEqual([shown.projection.label, shown.projection.text, shown.projection.detail ?? ""],
                       frame.projection, "\(name) projection", file: file, line: line)
        XCTAssertEqual(shown.projection.isEstimate, frame.estimate, "\(name) projection is an estimate",
                       file: file, line: line)
        XCTAssertEqual(shown.projection.estimateLabel, frame.estimate ? "Estimate" : nil, "\(name) estimate label",
                       file: file, line: line)

        XCTAssertEqual(shown.logWeighInIsPrimary, frame.logPrimary, "\(name) Log weigh-in is primary",
                       file: file, line: line)
        XCTAssertEqual(shown.historyValue, frame.history, "\(name) history link", file: file, line: line)
        XCTAssertEqual(shown.phaseLinkValue, frame.phaseLink, "\(name) phase link", file: file, line: line)

        XCTAssertEqual(shown.card.title, "Scorecard", "\(name) card title", file: file, line: line)
        if item.pinsCard {
            XCTAssertEqual([shown.card.value ?? "", shown.card.caption ?? ""], frame.card, "\(name) card",
                           file: file, line: line)
            XCTAssertEqual(shown.card.unit, frame.card[0].isEmpty ? nil : weightUnit, "\(name) card unit",
                           file: file, line: line)
            XCTAssertEqual(shown.card.isDimmed, frame.cardDimmed, "\(name) card dimmed", file: file, line: line)
            XCTAssertEqual(shown.card.status, item.status, "\(name) card status", file: file, line: line)
            XCTAssertTrue(shown.card.opensScorecard, "\(name) card opens the scorecard", file: file, line: line)
        }
    }

    /// The design model's result, written the way `digest(_:)` writes the real one.
    private func digest(_ result: CutScorecardResult) -> String {
        func number(_ value: Double?) -> String { value.map { String(format: "%.3f", $0) } ?? "-" }
        func text(_ value: String?) -> String { value ?? "-" }
        let verdict = result.verdict
        let signals = result.signals
        var parts: [String] = []
        parts.append("v \(verdict.kind.rawValue) \(verdict.reason.rawValue) \(text(verdict.rule?.rawValue)) "
            + "\(number(verdict.calorieChangeKcal.map(Double.init))) "
            + "o[\(verdict.overriddenRules.map(\.rawValue).joined(separator: ","))] "
            + "u[\(verdict.unevaluatedRules.map(\.rawValue).joined(separator: ","))]")
        parts.append("r " + result.rules.map {
            "\($0.state.rawValue):\(text($0.unknownReason?.rawValue)):\($0.consecutiveWeeks):\($0.requiredWeeks)"
        }.joined(separator: " "))
        let waist = signals.waist
        parts.append("w \(waist.state.rawValue) \(waist.reason.rawValue) \(number(waist.currentCm)) "
            + "\(number(waist.referenceCm)) \(text(waist.referenceWeekStart)) \(number(waist.changeCm))")
        let lifts = signals.lifts
        var liftLine = "l \(lifts.state.rawValue) \(lifts.reason.rawValue) \(lifts.commonExercises) \(lifts.dropped) "
            + "\(lifts.climbed) \(lifts.held)"
        // The design model gives no window with no lift data at all; ruling R13 gives one. No string uses it.
        if ![.noLiftData, .noReadings, .weighInOverdue].contains(lifts.reason),
           let from = lifts.windowStartDay, let to = lifts.windowEndDay {
            liftLine += " \(from) \(to)"
        }
        parts.append(liftLine)
        let protein = signals.protein
        // With no floor the design model counts nothing; ruling R13 still counts logged days. No string uses them.
        let counted = protein.reason != .noFloorConfigured
        parts.append("p \(protein.state.rawValue) \(protein.reason.rawValue) \(counted ? protein.daysLogged : 0) "
            + "\(counted ? protein.daysAtOrAboveFloor : 0)")
        parts.append("b \(signals.rateBand.state.rawValue) \(signals.rateBand.reason.rawValue) "
            + "\(number(signals.rateBand.percentPerWeek))")
        if let rate = result.rate {
            parts.append("rate \(number(rate.lossKgPerWeek)) \(number(rate.percentPerWeek)) \(rate.pointsUsed) "
                + "\(rate.firstWeekStart) \(rate.lastWeekStart)")
        } else {
            parts.append("rate - \(text(result.rateUnavailable?.rawValue))")
        }
        // Ruling R9 keeps remainingKg while overdue; the design model drops it. The overdue frame shows neither.
        let remaining = result.projection.status == .weighInOverdue ? nil : result.projection.remainingKg
        parts.append("pj \(result.projection.status.rawValue) \(text(result.projection.targetDay)) \(number(remaining))")
        parts.append("cur \(number(result.currentWeightKg)) \(text(result.currentWeightDay)) "
            + "J \(text(result.judgedWeekStart))")
        return parts.joined(separator: " | ")
    }

    // MARK: - The fixture behind the frames

    /// Guards every expectation below: the result the implementation returns for each frame's day
    /// is the result the frame was drawn from.
    func testEveryFrameResultCarriesTheFactsItsStringsAreBuiltFrom() {
        for item in Self.cases {
            XCTAssertEqual(digest(CutScorecard.evaluate(item.input)), item.frame.digest, item.name)
        }
    }

    // MARK: - §10.2 scorecard screen, one test per frame of set B

    func testB1SteadyLossInTheBand() throws { try check("B1") }
    func testB2NoReadings() throws { try check("B2") }
    func testB3NoCutPhase() throws { try check("B3") }
    func testB4PhaseNotStarted() throws { try check("B4") }
    func testB5OneReading() throws { try check("B5") }
    func testB6OneReadingNoLiftSessions() throws { try check("B6") }
    func testB7FewerReadingsThanARuleNeeds() throws { try check("B7") }
    func testB8ProteinBelowTheFloor() throws { try check("B8") }
    func testB9ProteinLoggingIncomplete() throws { try check("B9") }
    func testB10RecompositionWeek() throws { try check("B10") }
    func testB11ReduceCarbohydrate() throws { try check("B11") }
    func testB12WeighInDueLastVerdictStands() throws { try check("B12") }
    func testB13AfterAMissedWeek() throws { try check("B13") }
    func testB14NoRuleFiredLiftsNotKnown() throws { try check("B14") }
    func testB15VerdictWithheld() throws { try check("B15") }
    func testB16ReduceCarbohydrateLiftsRuleNotChecked() throws { try check("B16") }
    func testB17AddCaloriesSlowLossOverridden() throws { try check("B17") }
    func testB18WeightRising() throws { try check("B18") }
    func testB19TargetReached() throws { try check("B19") }
    func testB20WeighInOverdue() throws { try check("B20") }
    func testB21NoTargetSetNoProteinFloor() throws { try check("B21") }
    func testB22ProjectionBeyondTheHorizon() throws { try check("B22") }
    func testB23ProjectedDayPassed() throws { try check("B23") }
    func testB24RulesNeedAttention() throws { try check("B24") }
    func testB25PoundsAndInches() throws { try check("B25") }

    /// B27 is B16's content at the largest text size: the presenter gives the same strings.
    func testB27LargestTextSizeHasTheSameContentAsB16() throws { try check("B16") }

    // The same builder on four more fixture days, for wording no frame of set B reaches.

    func testASpanOfOneWeekIsSingular() throws { try check("week 2") }
    func testARecompositionRunLongerThanTheWindowIsCountedInFull() throws { try check("week 8") }
    func testNoRuleFiredAfterAMissedWeekNamesBothUncheckedRules() throws { try check("week 12") }
    func testATargetAlreadyPassedStillLeadsWithTargetReached() throws { try check("week 22") }
    func testReduceCarbohydrateInPoundsConvertsTheThreshold() throws { try check("week 9 imperial") }
    func testAGainInPoundsIsStillWordedAsAGain() throws { try check("week 20 imperial") }

    // MARK: - §10.2 the lines that sit beside a verdict

    func testNoCutPhaseExplainsAndOffersSetUpPhase() throws {
        let shown = present(try named("B3"))
        XCTAssertEqual(shown.verdict.explanation,
                       "Verdicts are given during a cut phase. Your weigh-ins and curves are kept either way.")
        XCTAssertEqual(shown.verdict.action, .setUpPhase)
        XCTAssertEqual(shown.verdict.actionTitle, "Set up phase")
        XCTAssertNotNil(shown.weight, "readings exist, so the curves still show")
    }

    func testRulesNeedAttentionExplainsAndLinksToTheRulesSheet() throws {
        let shown = present(try named("B24"))
        XCTAssertEqual(shown.verdict.explanation,
                       "A stored rule value is not valid, so no verdict is shown. Your weigh-ins are unaffected.")
        XCTAssertEqual(shown.verdict.action, .openPhaseAndRules)
        XCTAssertEqual(shown.verdict.actionTitle, "Open phase and rules")
        XCTAssertTrue(shown.verdict.isWithheld)
    }

    func testOnlyNoCutPhaseAndRulesNeedAttentionCarryAnExplanationOrAction() {
        for item in Self.cases where item.status != .noCutPhase && item.status != .rulesNeedAttention {
            let shown = present(item)
            XCTAssertEqual(shown.status, item.status, item.name)
            XCTAssertNil(shown.verdict.explanation, item.name)
            XCTAssertNil(shown.verdict.action, item.name)
            XCTAssertNil(shown.verdict.actionTitle, item.name)
        }
    }

    /// A result the pure function itself marks invalid (§6.5) is the same state as stored rules that
    /// failed to parse: no verdict, no curve, and nothing drawn as zero.
    func testAnInvalidResultReadsAsRulesNeedAttention() {
        var broken = Fixture.parameters
        broken.rateWindowWeeks = 0
        let input = Fixture.input(today: Fixture.weighDay(4), parameters: broken)
        XCTAssertEqual(CutScorecard.evaluate(input).invalidInput, .parameters, "the fixture for this test")
        let shown = present(input)
        XCTAssertEqual(shown.status, .rulesNeedAttention)
        XCTAssertEqual(shown.verdict.title, "Your rules need attention")
        XCTAssertTrue(shown.verdict.isWithheld)
        XCTAssertEqual(shown.verdict.action, .openPhaseAndRules)
        XCTAssertEqual(shown.rules, [])
        XCTAssertNil(shown.verdict.signalsSummary)
        XCTAssertNil(shown.weight)
        XCTAssertNil(shown.waist)
        XCTAssertNil(shown.card.value)
        XCTAssertFalse(shown.projection.isEstimate)
        XCTAssertEqual(shown.signals.map(\.state), [.unknown, .unknown, .unknown, .unknown])
    }

    // MARK: - §11 reasons no frame reaches

    private func replacing(_ base: CutScorecardInput, weights: [CutScorecardReading]? = nil,
                           waists: [CutScorecardReading]? = nil, lifts: [CutScorecardLiftObservation]? = nil,
                           phase: CutScorecardPhase?? = nil, parameters: CutScorecardParameters? = nil)
        -> CutScorecardInput {
        CutScorecardInput(weights: weights ?? base.weights, waists: waists ?? base.waists,
                          lifts: lifts ?? base.lifts, proteinDays: base.proteinDays,
                          phase: phase ?? base.phase, parameters: parameters ?? base.parameters, today: base.today)
    }

    func testWaistNotMeasuredThisWeek() throws {
        let base = Self.week(4)
        let input = replacing(base, waists: base.waists.filter { $0.day != Fixture.weighDay(4) })
        let row = try XCTUnwrap(present(input).signals[safe: 0])
        XCTAssertEqual(row.title, "Waist")
        XCTAssertEqual(row.state, .unknown)
        XCTAssertEqual(row.stateWord, "Unknown")
        XCTAssertEqual(row.reason, "Not measured this week")
        XCTAssertNil(row.detail, "nothing was measured, so no number is shown")
    }

    func testLiftsWithNothingToCompareWith() throws {
        let base = Self.week(1)
        let input = replacing(base, lifts: [
            CutScorecardLiftObservation(day: "2031-01-06", exercise: "Fixture Press", weightKg: 60),
        ])
        let row = try XCTUnwrap(present(input).signals[safe: 1])
        XCTAssertEqual(row.title, "Working weights")
        XCTAssertEqual(row.state, .unknown)
        XCTAssertEqual(row.reason, "Not known: nothing to compare with")
        XCTAssertEqual(row.detail, "1 Jan – 7 Jan")
    }

    func testLiftsWithNoExerciseInCommon() throws {
        let base = Self.week(1)
        let input = replacing(base, lifts: [
            CutScorecardLiftObservation(day: "2030-12-30", exercise: "Fixture Press", weightKg: 60),
            CutScorecardLiftObservation(day: "2031-01-06", exercise: "Fixture Row", weightKg: 50),
        ])
        let row = try XCTUnwrap(present(input).signals[safe: 1])
        XCTAssertEqual(row.state, .unknown)
        XCTAssertEqual(row.reason, "Not known: no exercise in common")
        XCTAssertEqual(row.detail, "1 Jan – 7 Jan")
    }

    func testRateAboveTheBand() throws {
        let narrow = CutScorecardPhase(name: "Fixture cut", startDay: "2031-01-06", targetWeightKg: 94.0,
                                       rateLowPercentPerWeek: 0.40, rateHighPercentPerWeek: 0.50)
        let row = try XCTUnwrap(present(replacing(Self.week(4), phase: .some(narrow))).signals[safe: 3])
        XCTAssertEqual(row.title, "Rate of loss")
        XCTAssertEqual(row.state, .notMet)
        XCTAssertEqual(row.stateWord, "Not met")
        XCTAssertEqual(row.reason, "Above your band")
        XCTAssertEqual(row.detail, "0.80 kg per week, 0.81% of bodyweight · band 0.40–0.50%")
    }

    /// Two weigh-ins five weeks apart with a four-week rate window: no rate, and the number in the
    /// sentence is the parameter.
    func testAGapLongerThanTheRateWindow() {
        let base = Fixture.input(today: Fixture.weighDay(7), without: Set(2...6))
        XCTAssertEqual(CutScorecard.evaluate(base).rateUnavailable, .gapLongerThanWindow, "the fixture for this test")
        let shown = present(base)
        XCTAssertEqual(shown.signals[safe: 3]?.reason, "Gap longer than 4 weeks")
        XCTAssertEqual(shown.signals[safe: 3]?.state, .unknown)
        XCTAssertEqual(shown.projection.text, "Gap longer than 4 weeks")
        XCTAssertFalse(shown.projection.isEstimate)
        XCTAssertEqual(shown.weight?.note, "Gap longer than 4 weeks")
        XCTAssertEqual(shown.weight?.facts.map(\.value), [nil, nil], "no rate is not a rate of zero")

        var wider = Fixture.parameters
        wider.rateWindowWeeks = 2
        let narrowGap = Fixture.input(today: Fixture.weighDay(5), parameters: wider, without: Set(2...4))
        XCTAssertEqual(present(narrowGap).signals[safe: 3]?.reason, "Gap longer than 2 weeks")
    }

    func testTheHorizonInTheProjectionLineIsTheParameter() {
        var shorter = Fixture.parameters
        shorter.maxProjectionWeeks = 52
        let input = Fixture.input(today: "2031-02-26", phase: Self.phase(target: 80), parameters: shorter)
        XCTAssertEqual(present(input).projection.text, "More than 52 weeks at this rate")
    }

    /// The amounts in an advice title are the owner's own parameters, whatever they are.
    func testAdviceAmountsAreTheOwnersParameters() {
        var other = Fixture.parameters
        other.addCaloriesKcal = 175
        other.reduceCarbsKcal = 125
        XCTAssertEqual(present(Fixture.input(today: Fixture.weighDay(19), parameters: other)).verdict.title,
                       "Your rule: add 175 kcal")
        XCTAssertEqual(present(Fixture.input(today: Fixture.weighDay(9), parameters: other)).verdict.title,
                       "Your rule: take 125 kcal from carbohydrate")
    }

    // MARK: - §11 the projection line for every status

    func testProjectionLineForEveryProjectionStatus() throws {
        let expected: [(String, CutScorecardProjectionStatus, String)] = [
            ("B1", .projected, "Estimated Sun 2 Mar at this rate"),
            ("B3", .noActivePhase, "No cut phase is active"),
            ("B21", .noTarget, "No target set"),
            ("B19", .targetReached, "Target reached"),
            ("B5", .rateUnknown, "Needs a second weigh-in"),
            ("B2", .rateUnknown, "Not measured yet"),
            ("B18", .notLosing, "No date while weight is not falling"),
            ("B22", .beyondHorizon, "More than 104 weeks at this rate"),
            ("B23", .needsNewWeighIn, "Log a weigh-in to check the target"),
            ("B20", .weighInOverdue, "Last weigh-in Wed 5 Mar"),
        ]
        for (name, status, text) in expected {
            let item = try named(name)
            XCTAssertEqual(CutScorecard.evaluate(item.input).projection.status, status, "\(name) fixture")
            let projection = present(item).projection
            XCTAssertEqual(projection.text, text, name)
            XCTAssertEqual(projection.isEstimate, status == .projected, name)
        }
    }

    /// §11: "Estimated" marks the projection, and nothing else is marked as an estimate.
    func testOnlyAProjectedDateIsLabelledAnEstimate() {
        XCTAssertEqual(Self.cases.filter { present($0).projection.isEstimate }.map(\.name),
                       Self.cases.filter(\.frame.estimate).map(\.name), "the states with a projected date")
        for item in Self.cases {
            let projection = present(item).projection
            XCTAssertEqual(projection.text.hasPrefix("Estimated "), projection.isEstimate, item.name)
            XCTAssertEqual(projection.estimateLabel, projection.isEstimate ? "Estimate" : nil, item.name)
            if projection.isEstimate {
                XCTAssertTrue(projection.text.hasSuffix(" at this rate"), item.name)
            }
        }
    }

    // MARK: - Rates and units

    func testALossIsWrittenAsALossAndAGainAsAGainNeverWithASign() throws {
        let losing = try XCTUnwrap(present(try named("B1")).weight)
        XCTAssertEqual(losing.facts[safe: 0]?.label, "Rate of loss")
        XCTAssertEqual(losing.facts[safe: 0]?.value, "0.80")

        let gaining = present(try named("B18"))
        let curve = try XCTUnwrap(gaining.weight)
        XCTAssertEqual(curve.facts[safe: 0]?.label, "Rate of gain")
        XCTAssertEqual(curve.facts[safe: 0]?.value, "0.12", "the size of the gain, unsigned")
        XCTAssertEqual(curve.facts[safe: 1]?.value, "0.13")
        XCTAssertEqual(gaining.signals[safe: 3]?.detail, "Gaining 0.12 kg per week, 0.13% of bodyweight · band 0.40–1.20%")
        let shownAsAGain = curve.facts.compactMap(\.value) + gaining.signals.compactMap(\.detail)
        for text in shownAsAGain {
            XCTAssertFalse(text.contains("-0.") || text.contains("−0."), "a gain is worded, not signed: \(text)")
        }
    }

    func testAWaistDecreaseCarriesATrueMinusSign() throws {
        let waist = try XCTUnwrap(present(try named("B1")).waist)
        XCTAssertEqual(waist.facts.map(\.value), ["−1.0", "−1.5"])
        XCTAssertEqual(waist.facts.map(\.unit), ["cm", "cm"])
    }

    func testEveryWeightAndWaistFollowsTheUnitSystem() throws {
        let metric = present(try named("B1"))
        let imperial = present(try named("B25"))
        XCTAssertEqual(metric.card.unit, "kg")
        XCTAssertEqual(imperial.card.unit, "lb")
        XCTAssertEqual(imperial.card.value, "215.2")
        XCTAssertEqual(imperial.weight?.unit, "lb")
        XCTAssertEqual(imperial.waist?.unit, "in")
        XCTAssertEqual(imperial.waist?.value, "38.8")
        XCTAssertEqual(imperial.weight?.facts[safe: 0]?.unit, "lb/week")
        XCTAssertEqual(imperial.waist?.facts.map(\.unit), ["in", "in"])
        XCTAssertEqual(imperial.phase?.detail, "Target 207.2 lb · started Mon 6 Jan · band 0.40–1.20% per week")
        XCTAssertEqual(imperial.projection.label, "Projection · target 207.2 lb")
        XCTAssertEqual(imperial.projection.detail, "7.9 lb to go · about 5 weeks")
        let strings = Fixture.strings(in: imperial)
        XCTAssertFalse(strings.contains { $0.contains(" kg") || $0.contains(" cm") },
                       "no metric unit is left on an imperial screen")
        // Percentages, dates, counts and kilocalories do not change with the unit system.
        XCTAssertEqual(imperial.verdict, metric.verdict)
        XCTAssertEqual(imperial.weight?.facts[safe: 1]?.value, metric.weight?.facts[safe: 1]?.value)
        XCTAssertEqual(imperial.signals[safe: 2], metric.signals[safe: 2])
    }

    // MARK: - Provenance and source captions (§11)

    func testProvenanceNamesTheDayAndTheSource() throws {
        let item = try named("B1")
        XCTAssertEqual(present(item).weight?.provenance, "Weighed Wed 29 Jan · Lab Book")
        XCTAssertEqual(present(item).waist?.provenance, "Measured Wed 29 Jan · Lab Book")
        XCTAssertEqual(present(item.input, context(source: .appleHealth)).weight?.provenance,
                       "Weighed Wed 29 Jan · Apple Health")
        XCTAssertEqual(present(item.input, context(source: .appleHealth)).waist?.provenance,
                       "Measured Wed 29 Jan · Lab Book", "a waist is only ever a Lab Book reading")
    }

    func testSourceCaptions() {
        XCTAssertEqual(CutScorecardPresenter.sourceCaption(.labBook), "Lab Book")
        XCTAssertEqual(CutScorecardPresenter.sourceCaption(.appleHealth), "Apple Health")
        XCTAssertEqual(CutScorecardPresenter.sourceCaption(.profile), "from profile")
        XCTAssertFalse(CutScorecardPresenter.sourceCaption(.profileDefault).isEmpty)
    }

    // MARK: - §10.1 entry card: frame A1 and every state of frame A2

    private func card(_ name: String) throws -> CutScorecardCard { present(try named(name)).card }

    private func assertCard(_ card: CutScorecardCard, _ status: CutScorecardStatus, value: String?, caption: String,
                            dimmed: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(card.status, status, file: file, line: line)
        XCTAssertEqual(card.title, "Scorecard", file: file, line: line)
        XCTAssertEqual(card.value, value, file: file, line: line)
        XCTAssertEqual(card.unit, value == nil ? nil : "kg", file: file, line: line)
        XCTAssertEqual(card.caption, caption, file: file, line: line)
        XCTAssertEqual(card.isDimmed, dimmed, file: file, line: line)
    }

    func testA1CardVerdictAvailable() throws {
        assertCard(try card("B1"), .verdict, value: "97.6", caption: "Change nothing")
    }

    func testA2CardLoading() {
        let card = CutScorecardPresenter.loadingCard()
        XCTAssertEqual(card.status, .loading)
        XCTAssertEqual(card.title, "Scorecard")
        XCTAssertNil(card.value, "a skeleton, not a number")
        XCTAssertNil(card.unit)
        XCTAssertNil(card.caption)
        XCTAssertFalse(card.opensScorecard)
    }

    func testA2CardNoCutPhase() throws {
        assertCard(try card("B3"), .noCutPhase, value: nil, caption: "Set up your phase")
    }

    func testA2CardNoReadings() throws {
        assertCard(try card("B2"), .noReadings, value: nil, caption: "Log your first weigh-in")
    }

    func testA2CardOneReading() throws {
        assertCard(try card("B5"), .oneReading, value: "100.0", caption: "First weigh-in logged")
    }

    func testA2CardFewerReadingsThanTheRulesNeed() throws {
        assertCard(try card("B7"), .building, value: "97.3", caption: "Building: 2 of 3 weeks")
    }

    func testA2CardWeighInDueThisWeek() throws {
        assertCard(try card("B12"), .due, value: "97.1", caption: "Weigh-in due this week")
    }

    func testA2CardOverdueShowsTheLastWeightDimmed() throws {
        assertCard(try card("B20"), .overdue, value: "97.1", caption: "Last weigh-in Wed 5 Mar", dimmed: true)
    }

    func testA2CardLiftsUnknownVerdictWithheld() throws {
        assertCard(try card("B15"), .verdictWithheld, value: "94.9", caption: "Lifts not known this week")
    }

    func testA2CardTargetReached() throws {
        assertCard(try card("B19"), .targetReached, value: "94.0", caption: "Target reached")
    }

    /// §10.1: the short verdict, with no colour change and no warning.
    func testA2CardWeightRising() throws {
        assertCard(try card("B18"), .verdict, value: "95.5", caption: "Your rule: take 250 kcal from carbohydrate")
    }

    func testA2CardYourRuleAdd() throws {
        assertCard(try card("B17"), .verdict, value: "94.5", caption: "Your rule: add 300 kcal")
    }

    func testA2CardAPastDaySelected() {
        let card = CutScorecardPresenter.pastDayCard()
        XCTAssertEqual(card.status, .pastDay)
        XCTAssertEqual(card.title, "Scorecard")
        XCTAssertNil(card.value, "a past day shows a dash, as Hydration does")
        XCTAssertNil(card.unit)
        XCTAssertEqual(card.caption, "Shown for today only")
        XCTAssertFalse(card.isDimmed)
        XCTAssertFalse(card.opensScorecard)
    }

    /// Frame A3 (largest text size) draws weeks 4 and 9 and the overdue state: the same strings.
    func testA3LargestTextSizeHasTheSameCardContent() throws {
        assertCard(try card("B1"), .verdict, value: "97.6", caption: "Change nothing")
        assertCard(try card("B11"), .verdict, value: "97.1", caption: "Your rule: take 250 kcal from carbohydrate")
        assertCard(try card("B20"), .overdue, value: "97.1", caption: "Last weigh-in Wed 5 Mar", dimmed: true)
    }

    /// README decision 8: overdue, due, one reading, target reached, verdict withheld, building,
    /// then the short verdict.
    func testCardCaptionPrecedence() {
        // Due beats target reached: week 21 reached the target, and week 22 has no reading yet.
        let dueAfterTarget = Fixture.input(today: Fixture.weighDay(22), without: [22])
        XCTAssertEqual(present(dueAfterTarget).card.caption, "Weigh-in due this week")
        XCTAssertEqual(present(dueAfterTarget).status, .due)
        // One reading beats target reached: a single weigh-in already at the target.
        let reachedAtOnce = Fixture.input(today: Fixture.weighDay(1), phase: Self.phase(target: 100))
        XCTAssertEqual(CutScorecard.evaluate(reachedAtOnce).projection.status, .targetReached, "the fixture")
        XCTAssertEqual(present(reachedAtOnce).card.caption, "First weigh-in logged")
        // Target reached beats the short verdict (week 21 is "Change nothing").
        XCTAssertEqual(present(Self.week(21)).card.caption, "Target reached")
    }

    // MARK: - §12.3 scans over every state

    /// The token "0", "0.0" or "0,00" standing alone: a number, not part of one.
    private func hasBareZero(_ text: String) -> Bool {
        text.range(of: #"(?<![0-9.,])0([.,]0+)?(?![0-9.,])"#, options: .regularExpression) != nil
    }

    private func unknownStates() -> [(String, CutScorecardPresentation)] {
        var broken = Fixture.parameters
        broken.rateWindowWeeks = 0
        let base = Self.week(4)
        var states = Self.cases.map { ($0.name, present($0)) }
        states.append(("invalid", present(Fixture.input(today: Fixture.weighDay(4), parameters: broken))))
        states.append(("no waist", present(replacing(base, waists: []))))
        states.append(("gap", present(Fixture.input(today: Fixture.weighDay(7), without: Set(2...6)))))
        return states
    }

    func testNoStateRendersAMissingValueAsZero() {
        for (name, shown) in unknownStates() {
            XCTAssertEqual(shown.signals.count, 4, "\(name): the four signal rows are what this test scans")
            // An unknown signal has no number of its own to show as zero. (A count such as
            // "0 climbed" or "0 of 3 weeks" belongs to a known signal or to a rule row.)
            for row in shown.signals where row.state == .unknown {
                XCTAssertFalse(hasBareZero(row.reason), "\(name) \(row.title): \(row.reason)")
                if let detail = row.detail {
                    XCTAssertFalse(hasBareZero(detail), "\(name) \(row.title): \(detail)")
                }
            }
            if let value = shown.card.value { XCTAssertFalse(hasBareZero(value), "\(name) card \(value)") }
            for curve in [shown.weight, shown.waist].compactMap({ $0 }) {
                XCTAssertFalse(hasBareZero(curve.value), "\(name) \(curve.title) \(curve.value)")
                XCTAssertFalse(curve.points.contains { $0 == 0 }, "\(name) \(curve.title): a missed week is nil, not 0")
            }
            if !shown.projection.isEstimate {
                XCTAssertFalse(hasBareZero(shown.projection.text), "\(name) \(shown.projection.text)")
            }
            XCTAssertFalse(hasBareZero(shown.verdict.title), "\(name) \(shown.verdict.title)")
            XCTAssertFalse(hasBareZero(shown.projection.label), "\(name) \(shown.projection.label)")
            if let header = shown.phase { XCTAssertFalse(hasBareZero(header.detail), "\(name) \(header.detail)") }
        }
    }

    /// With nothing measured there is no curve at all, and with no rate there is no rate value.
    func testAnUnmeasuredValueIsAbsentNotANumber() throws {
        let empty = present(try named("B2"))
        XCTAssertNil(empty.weight)
        XCTAssertNil(empty.waist)
        XCTAssertNil(empty.card.value)
        XCTAssertNil(empty.card.unit)
        XCTAssertNil(empty.verdict.signalsSummary, "with every signal unknown there is no \"0 of 4\"")

        let single = present(try named("B5"))
        XCTAssertEqual(single.weight?.facts.map(\.value), [nil, nil])
        XCTAssertEqual(single.waist?.facts.map(\.label), ["Change", "Since the first reading"])
        XCTAssertEqual(single.waist?.facts.map(\.value), [nil, nil])

        let noWaist = present(replacing(Self.week(4), waists: []))
        XCTAssertNil(noWaist.waist, "no waist reading at all: no waist curve, not a curve at zero")
        XCTAssertNotNil(noWaist.weight)

        let missed = try XCTUnwrap(present(try named("B13")).weight)
        XCTAssertEqual(missed.points.map { $0 == nil },
                       [false, false, false, false, false, false, false, false, false, true, false],
                       "the missed week 10 is a break in the curve, between two runs of readings")
    }

    func testNoStringContainsAnInterpolatedNilOrNaN() {
        for (name, shown) in unknownStates() {
            XCTAssertGreaterThan(Fixture.strings(in: shown).count, 15, "\(name): the screen's strings were collected")
            for text in Fixture.strings(in: shown) {
                XCTAssertFalse(text.isEmpty, "\(name): an absent line is nil, not an empty string")
                XCTAssertEqual(text, text.trimmingCharacters(in: .whitespacesAndNewlines), "\(name): \"\(text)\"")
                for fragment in ["nil", "Optional", "NaN", "nan", "null", "undefined", "inf", "%@", "%lld", "\\("] {
                    XCTAssertFalse(text.contains(fragment), "\(name): \"\(text)\" contains \(fragment)")
                }
                XCTAssertFalse(text.contains("  "), "\(name): \"\(text)\" has a doubled space")
            }
        }
    }

    /// §11: none of the strings states or implies a health outcome; no streaks, nagging or warnings.
    func testNoStringMakesAMedicalClaimOrNags() {
        let banned = ["health", "medical", "doctor", "diagnos", "disease", "risk", "danger", "warning", "unsafe",
                      "obes", "overweight", "underweight", "bmi", "body fat", "should", "must", "need to", "don't",
                      "streak", "in a row", "keep it up", "well done", "great", "congrat", "fail", "bad week",
                      "deficit", "diet", "recommend", "advise"]
        for (name, shown) in unknownStates() {
            XCTAssertGreaterThan(Fixture.strings(in: shown).count, 15, "\(name): the screen's strings were collected")
            for text in Fixture.strings(in: shown) {
                // The source caption "Apple Health" is a product name, not a claim.
                let lowered = text.replacingOccurrences(of: "Apple Health", with: "").lowercased()
                for word in banned {
                    XCTAssertFalse(lowered.contains(word), "\(name): \"\(text)\" contains \"\(word)\"")
                }
                XCTAssertFalse(text.contains("!"), "\(name): \"\(text)\"")
            }
        }
    }

    /// The only kilocalorie figures on any surface are the owner's own rule amounts, in the title
    /// that names them as the owner's rule (and on the card that repeats that title).
    func testTheOnlyCaloriesShownAreTheOwnersOwnRuleAmounts() {
        let adviceStates = unknownStates().filter { $0.1.verdict.title.hasPrefix("Your rule:") }.map(\.0)
        XCTAssertEqual(adviceStates, ["B11", "B12", "B16", "B17", "B18", "week 9 imperial", "week 20 imperial"],
                       "the states this test is about")
        for (name, shown) in unknownStates() {
            for text in Fixture.strings(in: shown) where text.lowercased().contains("kcal") || text.lowercased().contains("calorie") {
                XCTAssertTrue(text == "Your rule: add 300 kcal" || text == "Your rule: take 250 kcal from carbohydrate",
                              "\(name): \"\(text)\"")
            }
            let advised = shown.verdict.title.hasPrefix("Your rule:")
            XCTAssertEqual(shown.verdict.ownRuleNote != nil, advised, "\(name): the own-rule note sits under advice only")
        }
    }

    // MARK: - §10.6 settings rows (frames F1 to F3)

    private func settings(flag: Bool, _ reminder: WeighInReminderStatus, weekday: Int = 7, minute: Int = 480)
        -> CutScorecardSettingsPresentation {
        CutScorecardPresenter.settings(flagEnabled: flag, reminder: reminder, weekday: weekday,
                                       minuteOfDay: minute, locale: british)
    }

    func testSettingsWithTheFlagOffShowsOnlyTheSwitch() {
        let shown = settings(flag: false, .off)
        XCTAssertEqual(shown.toggleTitle, "Weekly weigh-in and scorecard")
        XCTAssertNil(shown.reminderTitle, "the reminder row is visible only while the flag is on")
        XCTAssertFalse(shown.reminderIsOn)
        XCTAssertNil(shown.day)
        XCTAssertNil(shown.time)
        XCTAssertNil(shown.footnote)
        XCTAssertNil(shown.previewTitle)
        XCTAssertNil(shown.deniedTitle)
    }

    func testF1ScorecardOnReminderOff() {
        let shown = settings(flag: true, .off)
        XCTAssertEqual(shown.toggleTitle, "Weekly weigh-in and scorecard")
        XCTAssertEqual(shown.reminderTitle, "Weekly reminder")
        XCTAssertFalse(shown.reminderIsOn)
        XCTAssertNil(shown.day)
        XCTAssertNil(shown.time)
        XCTAssertEqual(shown.footnote,
                       "The reminder is off unless you turn it on. One notification a week, on the day and at the time you choose.")
        XCTAssertNil(shown.previewTitle)
        XCTAssertNil(shown.previewBody)
        XCTAssertNil(shown.deniedTitle)
    }

    func testF2ReminderOnWithTheNotification() {
        let shown = settings(flag: true, .on)
        XCTAssertEqual(shown.reminderTitle, "Weekly reminder")
        XCTAssertTrue(shown.reminderIsOn)
        XCTAssertEqual(shown.day, "Saturday")
        XCTAssertEqual(shown.time, "08:00")
        XCTAssertEqual(shown.footnote, "One notification a week. It never contains a measurement, a verdict or the phase name.")
        XCTAssertEqual(shown.previewTitle, "Weekly weigh-in")
        XCTAssertEqual(shown.previewBody, "Weight, then waist. It takes under a minute.")
        XCTAssertNil(shown.deniedTitle)

        let monday = settings(flag: true, .on, weekday: 2, minute: 6 * 60 + 45)
        XCTAssertEqual(monday.day, "Monday", "1 is Sunday, as WindDownNudge numbers weekdays")
        XCTAssertEqual(monday.time, "06:45")
        XCTAssertEqual(settings(flag: true, .on, weekday: 1, minute: 0).day, "Sunday")
    }

    /// Frame F3 draws the switch on; §12.3 and the reminder tests leave it off. See the report.
    func testF3NotificationsDenied() {
        let shown = settings(flag: true, .denied)
        XCTAssertEqual(shown.reminderTitle, "Weekly reminder")
        XCTAssertFalse(shown.reminderIsOn, "a denied reminder cannot fire, so the switch does not read as on")
        XCTAssertNil(shown.day)
        XCTAssertNil(shown.time)
        XCTAssertEqual(shown.deniedTitle, "Notifications are off for NOOP")
        XCTAssertEqual(shown.deniedDetail, "The reminder cannot be delivered until they are allowed.")
        XCTAssertEqual(shown.deniedActionTitle, "Open Settings")
        XCTAssertNil(shown.previewTitle)
    }
}

// MARK: - The frames, as design/round6-scorecard/scorecard.js draws them

enum ScorecardFrames {
    static let b1 = ScorecardFrame(
        digest: "v holdSteady ruleFired liftsHoldingWaistShrinking - o[] u[] | r fired:-:1:1 notFired:-:0:3 notFired:-:0:3 | w met shrinking 98.500 99.500 2031-01-13 -1.000 | l met holding 2 0 0 2 2031-01-22 2031-01-28 | p met floorMet 7 6 | b met withinBand 0.810 | rate 0.800 0.810 4 2031-01-06 2031-01-27 | pj projected 2031-03-02 3.600 | cur 97.600 2031-01-29 J 2031-01-27",
        phase: ["Phase · week 4", "Fixture cut", "Target 94.0 kg · started Mon 6 Jan · band 0.40–1.20% per week"],
        due: nil,
        reached: nil,
        header: "Verdict · week of 27 Jan", summary: "4 of 4 signals met",
        title: "Change nothing", withheld: false,
        lines: ["Lifts are holding and your waist is shrinking."],
        couldNotCheck: [], ownRule: false,
        rules: [["Lifts holding and waist shrinking", "Fired", ""],
                ["Lifts dropping", "Not fired", "0 of 3 weeks"],
                ["Slow loss", "Not fired", "0 of 3 weeks"]],
        signals: [["Waist", "Met", "Down 1.0 cm in 2 weeks", "98.5 cm now · 99.5 cm in the week of 13 Jan"],
                  ["Working weights", "Met", "Holding or climbing", "0 climbed, 2 held, 0 dropped of 2 exercises · 22 Jan – 28 Jan"],
                  ["Protein floor", "Met", "6 of 7 days at or above your floor", "Floor 100 g · 7 of 7 days logged, 6 at or above · needs 5"],
                  ["Rate of loss", "Met", "0.80 kg per week, 0.81% of bodyweight", "band 0.40–1.20%"]],
        weight: ["97.6", "Weighed Wed 29 Jan · Lab Book", "100.0,99.2,98.4,97.6", "6 Jan", "27 Jan", "Rate of loss", "0.80", "0.81", "Line fitted to 4 weekly points, weeks of 6 Jan – 27 Jan"],
        waist: ["98.5", "Measured Wed 29 Jan · Lab Book", "100.0,99.5,99.0,98.5", "Since the week of 13 Jan", "−1.0", "Since the week of 6 Jan", "−1.5"],
        projection: ["Projection · target 94.0 kg", "Estimated Sun 2 Mar at this rate", "3.6 kg to go · about 5 weeks"], estimate: true,
        logPrimary: false, history: "5 weigh-ins", phaseLink: "Fixture cut",
        card: ["97.6", "Change nothing"], cardDimmed: false)

    static let b2 = ScorecardFrame(
        digest: "v insufficientData noReadings - - o[] u[] | r unknown:noReadings:0:1 unknown:noReadings:0:3 unknown:noReadings:0:3 | w unknown noReadings - - - - | l unknown noReadings 0 0 0 0 | p unknown noReadings 0 0 | b unknown noReadings - | rate - noReadings | pj rateUnknown - - | cur - - J -",
        phase: ["Phase · week 1", "Fixture cut", "Target 94.0 kg · started Mon 6 Jan · band 0.40–1.20% per week"],
        due: nil,
        reached: nil,
        header: "Verdict", summary: nil,
        title: "Log a weigh-in to begin", withheld: true,
        lines: [],
        couldNotCheck: [], ownRule: false,
        rules: [["Lifts holding and waist shrinking", "Could not check", "no weigh-ins yet"],
                ["Lifts dropping", "Could not check", "0 of 3 weeks · no weigh-ins yet"],
                ["Slow loss", "Could not check", "0 of 3 weeks · no weigh-ins yet"]],
        signals: [["Waist", "Unknown", "Not measured yet", ""],
                  ["Working weights", "Unknown", "Not measured yet", ""],
                  ["Protein floor", "Unknown", "Not measured yet", ""],
                  ["Rate of loss", "Unknown", "Not measured yet", ""]],
        weight: nil,
        waist: nil,
        projection: ["Projection · target 94.0 kg", "Not measured yet", ""], estimate: false,
        logPrimary: true, history: "0 weigh-ins", phaseLink: "Fixture cut",
        card: ["", "Log your first weigh-in"], cardDimmed: false)

    static let b3 = ScorecardFrame(
        digest: "v insufficientData noActivePhase - - o[] u[] | r unknown:noActivePhase:0:1 unknown:noActivePhase:0:3 unknown:noActivePhase:0:3 | w met shrinking 98.500 99.500 2031-01-13 -1.000 | l met holding 2 0 0 2 2031-01-22 2031-01-28 | p met floorMet 7 6 | b unknown noActivePhase - | rate 0.800 0.810 4 2031-01-06 2031-01-27 | pj noActivePhase - - | cur 97.600 2031-01-29 J 2031-01-27",
        phase: nil,
        due: nil,
        reached: nil,
        header: "Verdict", summary: "3 of 4 signals met",
        title: "No cut phase is active", withheld: true,
        lines: [],
        couldNotCheck: [], ownRule: false,
        rules: [],
        signals: [["Waist", "Met", "Down 1.0 cm in 2 weeks", "98.5 cm now · 99.5 cm in the week of 13 Jan"],
                  ["Working weights", "Met", "Holding or climbing", "0 climbed, 2 held, 0 dropped of 2 exercises · 22 Jan – 28 Jan"],
                  ["Protein floor", "Met", "6 of 7 days at or above your floor", "Floor 100 g · 7 of 7 days logged, 6 at or above · needs 5"],
                  ["Rate of loss", "Unknown", "No cut phase is active", "0.80 kg per week, 0.81% of bodyweight"]],
        weight: ["97.6", "Weighed Wed 29 Jan · Lab Book", "100.0,99.2,98.4,97.6", "6 Jan", "27 Jan", "Rate of loss", "0.80", "0.81", "Line fitted to 4 weekly points, weeks of 6 Jan – 27 Jan"],
        waist: ["98.5", "Measured Wed 29 Jan · Lab Book", "100.0,99.5,99.0,98.5", "Since the week of 13 Jan", "−1.0", "Since the week of 6 Jan", "−1.5"],
        projection: ["Projection", "No cut phase is active", ""], estimate: false,
        logPrimary: false, history: "5 weigh-ins", phaseLink: "Not set up",
        card: ["", "Set up your phase"], cardDimmed: false)

    static let b4 = ScorecardFrame(
        digest: "v insufficientData phaseNotStarted - - o[] u[] | r unknown:noActivePhase:0:1 unknown:noActivePhase:0:3 unknown:noActivePhase:0:3 | w met shrinking 98.500 99.500 2031-01-13 -1.000 | l met holding 2 0 0 2 2031-01-22 2031-01-28 | p met floorMet 7 6 | b unknown noActivePhase - | rate 0.800 0.810 4 2031-01-06 2031-01-27 | pj noActivePhase - - | cur 97.600 2031-01-29 J 2031-01-27",
        phase: ["Phase · not started", "Fixture cut", "Target 94.0 kg · starts Mon 3 Feb · band 0.40–1.20% per week"],
        due: nil,
        reached: nil,
        header: "Verdict", summary: "3 of 4 signals met",
        title: "Your phase starts Mon 3 Feb", withheld: true,
        lines: [],
        couldNotCheck: [], ownRule: false,
        rules: [],
        signals: [["Waist", "Met", "Down 1.0 cm in 2 weeks", "98.5 cm now · 99.5 cm in the week of 13 Jan"],
                  ["Working weights", "Met", "Holding or climbing", "0 climbed, 2 held, 0 dropped of 2 exercises · 22 Jan – 28 Jan"],
                  ["Protein floor", "Met", "6 of 7 days at or above your floor", "Floor 100 g · 7 of 7 days logged, 6 at or above · needs 5"],
                  ["Rate of loss", "Unknown", "No cut phase is active", "0.80 kg per week, 0.81% of bodyweight"]],
        weight: ["97.6", "Weighed Wed 29 Jan · Lab Book", "100.0,99.2,98.4,97.6", "6 Jan", "27 Jan", "Rate of loss", "0.80", "0.81", "Line fitted to 4 weekly points, weeks of 6 Jan – 27 Jan"],
        waist: ["98.5", "Measured Wed 29 Jan · Lab Book", "100.0,99.5,99.0,98.5", "Since the week of 13 Jan", "−1.0", "Since the week of 6 Jan", "−1.5"],
        projection: ["Projection · target 94.0 kg", "No cut phase is active", ""], estimate: false,
        logPrimary: false, history: "5 weigh-ins", phaseLink: "Fixture cut",
        card: ["", "Set up your phase"], cardDimmed: false)

    static let b5 = ScorecardFrame(
        digest: "v holdSteady noChangeRuleFired - - o[] u[liftsHoldingWaistShrinking,slowLoss] | r unknown:waistSignalUnknown:0:1 notFired:-:0:3 unknown:fewerWeeksThanWindow:0:3 | w unknown noEarlierWaist 100.000 - - - | l met holding 2 0 0 2 2031-01-01 2031-01-07 | p unknown noProteinData 0 0 | b unknown rateUnknown - | rate - singleReading | pj rateUnknown - 6.000 | cur 100.000 2031-01-08 J 2031-01-06",
        phase: ["Phase · week 1", "Fixture cut", "Target 94.0 kg · started Mon 6 Jan · band 0.40–1.20% per week"],
        due: nil,
        reached: nil,
        header: "Verdict · week of 6 Jan", summary: "1 of 4 signals met",
        title: "Change nothing", withheld: false,
        lines: ["None of your change rules fired."],
        couldNotCheck: ["Could not check: lifts holding and waist shrinking", "Could not check: slow loss"], ownRule: false,
        rules: [["Lifts holding and waist shrinking", "Could not check", "waist not known"],
                ["Lifts dropping", "Not fired", "0 of 3 weeks"],
                ["Slow loss", "Could not check", "0 of 3 weeks · the phase is younger than this rule needs"]],
        signals: [["Waist", "Unknown", "Needs an earlier reading", "100.0 cm now"],
                  ["Working weights", "Met", "Holding or climbing", "0 climbed, 2 held, 0 dropped of 2 exercises · 1 Jan – 7 Jan"],
                  ["Protein floor", "Unknown", "No protein data", "Floor 100 g"],
                  ["Rate of loss", "Unknown", "Needs a second weigh-in", ""]],
        weight: ["100.0", "Weighed Wed 8 Jan · Lab Book", "100.0", "6 Jan", "6 Jan", "Rate of loss", "", "", "Needs a second weigh-in"],
        waist: ["100.0", "Measured Wed 8 Jan · Lab Book", "100.0", "Change", "", "Since the first reading", ""],
        projection: ["Projection · target 94.0 kg", "Needs a second weigh-in", ""], estimate: false,
        logPrimary: false, history: "1 weigh-in", phaseLink: "Fixture cut",
        card: ["100.0", "First weigh-in logged"], cardDimmed: false)

    static let b6 = ScorecardFrame(
        digest: "v insufficientData noRuleEvaluable - - o[] u[liftsHoldingWaistShrinking,liftsDropping,slowLoss] | r unknown:liftSignalUnknown:0:1 unknown:fewerWeeksThanWindow:0:3 unknown:fewerWeeksThanWindow:0:3 | w unknown noEarlierWaist 100.000 - - - | l unknown noLiftData 0 0 0 0 | p unknown noProteinData 0 0 | b unknown rateUnknown - | rate - singleReading | pj rateUnknown - 6.000 | cur 100.000 2031-01-08 J 2031-01-06",
        phase: ["Phase · week 1", "Fixture cut", "Target 94.0 kg · started Mon 6 Jan · band 0.40–1.20% per week"],
        due: nil,
        reached: nil,
        header: "Verdict · week of 6 Jan", summary: nil,
        title: "Not enough to judge yet", withheld: true,
        lines: [],
        couldNotCheck: ["Could not check: lifts holding and waist shrinking", "Could not check: lifts dropping", "Could not check: slow loss"], ownRule: false,
        rules: [["Lifts holding and waist shrinking", "Could not check", "lifts not known"],
                ["Lifts dropping", "Could not check", "0 of 3 weeks · the phase is younger than this rule needs"],
                ["Slow loss", "Could not check", "0 of 3 weeks · the phase is younger than this rule needs"]],
        signals: [["Waist", "Unknown", "Needs an earlier reading", "100.0 cm now"],
                  ["Working weights", "Unknown", "Not known: no imported sessions", ""],
                  ["Protein floor", "Unknown", "No protein data", "Floor 100 g"],
                  ["Rate of loss", "Unknown", "Needs a second weigh-in", ""]],
        weight: ["100.0", "Weighed Wed 8 Jan · Lab Book", "100.0", "6 Jan", "6 Jan", "Rate of loss", "", "", "Needs a second weigh-in"],
        waist: ["100.0", "Measured Wed 8 Jan · Lab Book", "100.0", "Change", "", "Since the first reading", ""],
        projection: ["Projection · target 94.0 kg", "Needs a second weigh-in", ""], estimate: false,
        logPrimary: false, history: "1 weigh-in", phaseLink: "Fixture cut",
        card: ["100.0", "First weigh-in logged"], cardDimmed: false)

    static let b7 = ScorecardFrame(
        digest: "v insufficientData noRuleEvaluable - - o[] u[liftsHoldingWaistShrinking,liftsDropping,slowLoss] | r unknown:liftSignalUnknown:0:1 unknown:liftSignalUnknown:0:3 unknown:fewerWeeksThanWindow:2:3 | w met shrinking 97.000 98.000 2031-02-03 -1.000 | l unknown noLiftData 0 0 0 0 | p unknown noProteinData 0 0 | b notMet belowBand 0.103 | rate 0.100 0.103 3 2031-02-03 2031-02-17 | pj projected 2031-10-08 3.300 | cur 97.300 2031-02-19 J 2031-02-17",
        phase: ["Phase · week 3", "Fixture cut", "Target 94.0 kg · started Mon 3 Feb · band 0.40–1.20% per week"],
        due: nil,
        reached: nil,
        header: "Verdict · week of 17 Feb", summary: "1 of 4 signals met",
        title: "Not enough to judge yet", withheld: true,
        lines: [],
        couldNotCheck: ["Could not check: lifts holding and waist shrinking", "Could not check: lifts dropping", "Could not check: slow loss"], ownRule: false,
        rules: [["Lifts holding and waist shrinking", "Could not check", "lifts not known"],
                ["Lifts dropping", "Could not check", "0 of 3 weeks · lifts not known"],
                ["Slow loss", "Could not check", "2 of 3 weeks · the phase is younger than this rule needs"]],
        signals: [["Waist", "Met", "Down 1.0 cm in 2 weeks", "97.0 cm now · 98.0 cm in the week of 3 Feb"],
                  ["Working weights", "Unknown", "Not known: no imported sessions", ""],
                  ["Protein floor", "Unknown", "No protein data", "Floor 100 g"],
                  ["Rate of loss", "Not met", "Below your band", "0.10 kg per week, 0.10% of bodyweight · band 0.40–1.20%"]],
        weight: ["97.3", "Weighed Wed 19 Feb · Lab Book", "97.5,97.4,97.3", "3 Feb", "17 Feb", "Rate of loss", "0.10", "0.10", "Line fitted to 3 weekly points, weeks of 3 Feb – 17 Feb"],
        waist: ["97.0", "Measured Wed 19 Feb · Lab Book", "98.0,97.5,97.0", "Since the week of 3 Feb", "−1.0", "Since the week of 3 Feb", "−1.0"],
        projection: ["Projection · target 94.0 kg", "Estimated Wed 8 Oct at this rate", "3.3 kg to go · about 33 weeks"], estimate: true,
        logPrimary: false, history: "8 weigh-ins", phaseLink: "Fixture cut",
        card: ["97.3", "Building: 2 of 3 weeks"], cardDimmed: false)

    static let b8 = ScorecardFrame(
        digest: "v holdSteady ruleFired liftsHoldingWaistShrinking - o[] u[] | r fired:-:1:1 notFired:-:0:3 notFired:-:1:3 | w met shrinking 98.000 99.000 2031-01-20 -1.000 | l met holding 2 0 1 1 2031-01-29 2031-02-04 | p notMet floorMissed 7 3 | b met withinBand 0.670 | rate 0.660 0.670 5 2031-01-06 2031-02-03 | pj projected 2031-03-15 3.500 | cur 97.500 2031-02-05 J 2031-02-03",
        phase: ["Phase · week 5", "Fixture cut", "Target 94.0 kg · started Mon 6 Jan · band 0.40–1.20% per week"],
        due: nil,
        reached: nil,
        header: "Verdict · week of 3 Feb", summary: "3 of 4 signals met",
        title: "Change nothing", withheld: false,
        lines: ["Lifts are holding and your waist is shrinking."],
        couldNotCheck: [], ownRule: false,
        rules: [["Lifts holding and waist shrinking", "Fired", ""],
                ["Lifts dropping", "Not fired", "0 of 3 weeks"],
                ["Slow loss", "Not fired", "1 of 3 weeks"]],
        signals: [["Waist", "Met", "Down 1.0 cm in 2 weeks", "98.0 cm now · 99.0 cm in the week of 20 Jan"],
                  ["Working weights", "Met", "Holding or climbing", "1 climbed, 1 held, 0 dropped of 2 exercises · 29 Jan – 4 Feb"],
                  ["Protein floor", "Not met", "Below your floor on 4 days", "Floor 100 g · 7 of 7 days logged, 3 at or above · needs 5"],
                  ["Rate of loss", "Met", "0.66 kg per week, 0.67% of bodyweight", "band 0.40–1.20%"]],
        weight: ["97.5", "Weighed Wed 5 Feb · Lab Book", "100.0,99.2,98.4,97.6,97.5", "6 Jan", "3 Feb", "Rate of loss", "0.66", "0.67", "Line fitted to 5 weekly points, weeks of 6 Jan – 3 Feb"],
        waist: ["98.0", "Measured Wed 5 Feb · Lab Book", "100.0,99.5,99.0,98.5,98.0", "Since the week of 20 Jan", "−1.0", "Since the week of 6 Jan", "−2.0"],
        projection: ["Projection · target 94.0 kg", "Estimated Sat 15 Mar at this rate", "3.5 kg to go · about 5 weeks"], estimate: true,
        logPrimary: false, history: "6 weigh-ins", phaseLink: "Fixture cut",
        card: ["97.5", "Change nothing"], cardDimmed: false)

    static let b9 = ScorecardFrame(
        digest: "v holdSteady ruleFired liftsHoldingWaistShrinking - o[] u[] | r fired:-:1:1 notFired:-:0:3 notFired:-:2:3 | w met shrinking 97.500 98.500 2031-01-27 -1.000 | l met holding 2 0 0 2 2031-02-05 2031-02-11 | p unknown incompleteLogging 3 3 | b met withinBand 0.459 | rate 0.450 0.459 5 2031-01-13 2031-02-10 | pj projected 2031-04-06 3.400 | cur 97.400 2031-02-12 J 2031-02-10",
        phase: ["Phase · week 6", "Fixture cut", "Target 94.0 kg · started Mon 6 Jan · band 0.40–1.20% per week"],
        due: nil,
        reached: nil,
        header: "Verdict · week of 10 Feb", summary: "3 of 4 signals met",
        title: "Change nothing", withheld: false,
        lines: ["Lifts are holding and your waist is shrinking."],
        couldNotCheck: [], ownRule: false,
        rules: [["Lifts holding and waist shrinking", "Fired", ""],
                ["Lifts dropping", "Not fired", "0 of 3 weeks"],
                ["Slow loss", "Not fired", "2 of 3 weeks"]],
        signals: [["Waist", "Met", "Down 1.0 cm in 2 weeks", "97.5 cm now · 98.5 cm in the week of 27 Jan"],
                  ["Working weights", "Met", "Holding or climbing", "0 climbed, 2 held, 0 dropped of 2 exercises · 5 Feb – 11 Feb"],
                  ["Protein floor", "Unknown", "Not enough days logged", "Floor 100 g · 3 of 7 days logged, 3 at or above · needs 5"],
                  ["Rate of loss", "Met", "0.45 kg per week, 0.46% of bodyweight", "band 0.40–1.20%"]],
        weight: ["97.4", "Weighed Wed 12 Feb · Lab Book", "100.0,99.2,98.4,97.6,97.5,97.4", "6 Jan", "10 Feb", "Rate of loss", "0.45", "0.46", "Line fitted to 5 weekly points, weeks of 13 Jan – 10 Feb"],
        waist: ["97.5", "Measured Wed 12 Feb · Lab Book", "100.0,99.5,99.0,98.5,98.0,97.5", "Since the week of 27 Jan", "−1.0", "Since the week of 6 Jan", "−2.5"],
        projection: ["Projection · target 94.0 kg", "Estimated Sun 6 Apr at this rate", "3.4 kg to go · about 8 weeks"], estimate: true,
        logPrimary: false, history: "7 weigh-ins", phaseLink: "Fixture cut",
        card: ["97.4", "Change nothing"], cardDimmed: false)

    static let b10 = ScorecardFrame(
        digest: "v holdSteady ruleFired liftsHoldingWaistShrinking - o[slowLoss] u[] | r fired:-:1:1 notFired:-:0:3 fired:-:3:3 | w met shrinking 97.000 98.000 2031-02-03 -1.000 | l met holding 2 0 1 1 2031-02-12 2031-02-18 | p unknown noProteinData 0 0 | b notMet belowBand 0.246 | rate 0.240 0.246 5 2031-01-20 2031-02-17 | pj projected 2031-05-27 3.300 | cur 97.300 2031-02-19 J 2031-02-17",
        phase: ["Phase · week 7", "Fixture cut", "Target 94.0 kg · started Mon 6 Jan · band 0.40–1.20% per week"],
        due: nil,
        reached: nil,
        header: "Verdict · week of 17 Feb", summary: "2 of 4 signals met",
        title: "Change nothing", withheld: false,
        lines: ["Lifts are holding and your waist is shrinking.", "The scale was slow for 3 weeks. That is expected when waist and lifts are on track."],
        couldNotCheck: [], ownRule: false,
        rules: [["Lifts holding and waist shrinking", "Fired", ""],
                ["Lifts dropping", "Not fired", "0 of 3 weeks"],
                ["Slow loss", "Fired", "3 of 3 weeks"]],
        signals: [["Waist", "Met", "Down 1.0 cm in 2 weeks", "97.0 cm now · 98.0 cm in the week of 3 Feb"],
                  ["Working weights", "Met", "Holding or climbing", "1 climbed, 1 held, 0 dropped of 2 exercises · 12 Feb – 18 Feb"],
                  ["Protein floor", "Unknown", "No protein data", "Floor 100 g"],
                  ["Rate of loss", "Not met", "Below your band", "0.24 kg per week, 0.25% of bodyweight · band 0.40–1.20%"]],
        weight: ["97.3", "Weighed Wed 19 Feb · Lab Book", "100.0,99.2,98.4,97.6,97.5,97.4,97.3", "6 Jan", "17 Feb", "Rate of loss", "0.24", "0.25", "Line fitted to 5 weekly points, weeks of 20 Jan – 17 Feb"],
        waist: ["97.0", "Measured Wed 19 Feb · Lab Book", "100.0,99.5,99.0,98.5,98.0,97.5,97.0", "Since the week of 3 Feb", "−1.0", "Since the week of 6 Jan", "−3.0"],
        projection: ["Projection · target 94.0 kg", "Estimated Tue 27 May at this rate", "3.3 kg to go · about 14 weeks"], estimate: true,
        logPrimary: false, history: "8 weigh-ins", phaseLink: "Fixture cut",
        card: ["97.3", "Change nothing"], cardDimmed: false)

    static let b11 = ScorecardFrame(
        digest: "v reduceCarbs ruleFired slowLoss -250.000 o[] u[] | r notFired:-:0:1 notFired:-:0:3 fired:-:5:3 | w notMet notShrinking 97.000 97.000 2031-02-17 0.000 | l met holding 2 0 0 2 2031-02-26 2031-03-04 | p unknown noProteinData 0 0 | b notMet belowBand 0.103 | rate 0.100 0.103 5 2031-02-03 2031-03-03 | pj projected 2031-10-08 3.100 | cur 97.100 2031-03-05 J 2031-03-03",
        phase: ["Phase · week 9", "Fixture cut", "Target 94.0 kg · started Mon 6 Jan · band 0.40–1.20% per week"],
        due: nil,
        reached: nil,
        header: "Verdict · week of 3 Mar", summary: "1 of 4 signals met",
        title: "Your rule: take 250 kcal from carbohydrate", withheld: false,
        lines: ["Loss was under 0.4 kg per week for 5 weeks."],
        couldNotCheck: [], ownRule: true,
        rules: [["Lifts holding and waist shrinking", "Not fired", ""],
                ["Lifts dropping", "Not fired", "0 of 3 weeks"],
                ["Slow loss", "Fired", "3 of 3 weeks"]],
        signals: [["Waist", "Not met", "Not shrinking", "97.0 cm now · 97.0 cm in the week of 17 Feb"],
                  ["Working weights", "Met", "Holding or climbing", "0 climbed, 2 held, 0 dropped of 2 exercises · 26 Feb – 4 Mar"],
                  ["Protein floor", "Unknown", "No protein data", "Floor 100 g"],
                  ["Rate of loss", "Not met", "Below your band", "0.10 kg per week, 0.10% of bodyweight · band 0.40–1.20%"]],
        weight: ["97.1", "Weighed Wed 5 Mar · Lab Book", "100.0,99.2,98.4,97.6,97.5,97.4,97.3,97.2,97.1", "6 Jan", "3 Mar", "Rate of loss", "0.10", "0.10", "Line fitted to 5 weekly points, weeks of 3 Feb – 3 Mar"],
        waist: ["97.0", "Measured Wed 5 Mar · Lab Book", "100.0,99.5,99.0,98.5,98.0,97.5,97.0,97.0,97.0", "Since the week of 17 Feb", "0.0", "Since the week of 6 Jan", "−3.0"],
        projection: ["Projection · target 94.0 kg", "Estimated Wed 8 Oct at this rate", "3.1 kg to go · about 31 weeks"], estimate: true,
        logPrimary: false, history: "10 weigh-ins", phaseLink: "Fixture cut",
        card: ["97.1", "Your rule: take 250 kcal from carbohydrate"], cardDimmed: false)

    static let b12 = ScorecardFrame(
        digest: "v reduceCarbs ruleFired slowLoss -250.000 o[] u[] | r notFired:-:0:1 notFired:-:0:3 fired:-:5:3 | w notMet notShrinking 97.000 97.000 2031-02-17 0.000 | l met holding 2 0 0 2 2031-02-26 2031-03-04 | p unknown noProteinData 0 0 | b notMet belowBand 0.103 | rate 0.100 0.103 5 2031-02-03 2031-03-03 | pj projected 2031-10-08 3.100 | cur 97.100 2031-03-05 J 2031-03-03",
        phase: ["Phase · week 10", "Fixture cut", "Target 94.0 kg · started Mon 6 Jan · band 0.40–1.20% per week"],
        due: ["Weigh-in due this week", "The verdict below is from the week of 3 Mar."],
        reached: nil,
        header: "Verdict · week of 3 Mar", summary: "1 of 4 signals met",
        title: "Your rule: take 250 kcal from carbohydrate", withheld: false,
        lines: ["Loss was under 0.4 kg per week for 5 weeks."],
        couldNotCheck: [], ownRule: true,
        rules: [["Lifts holding and waist shrinking", "Not fired", ""],
                ["Lifts dropping", "Not fired", "0 of 3 weeks"],
                ["Slow loss", "Fired", "3 of 3 weeks"]],
        signals: [["Waist", "Not met", "Not shrinking", "97.0 cm now · 97.0 cm in the week of 17 Feb"],
                  ["Working weights", "Met", "Holding or climbing", "0 climbed, 2 held, 0 dropped of 2 exercises · 26 Feb – 4 Mar"],
                  ["Protein floor", "Unknown", "No protein data", "Floor 100 g"],
                  ["Rate of loss", "Not met", "Below your band", "0.10 kg per week, 0.10% of bodyweight · band 0.40–1.20%"]],
        weight: ["97.1", "Weighed Wed 5 Mar · Lab Book", "100.0,99.2,98.4,97.6,97.5,97.4,97.3,97.2,97.1,x", "6 Jan", "10 Mar", "Rate of loss", "0.10", "0.10", "Line fitted to 5 weekly points, weeks of 3 Feb – 3 Mar"],
        waist: ["97.0", "Measured Wed 5 Mar · Lab Book", "100.0,99.5,99.0,98.5,98.0,97.5,97.0,97.0,97.0,x", "Since the week of 17 Feb", "0.0", "Since the week of 6 Jan", "−3.0"],
        projection: ["Projection · target 94.0 kg", "Estimated Wed 8 Oct at this rate", "3.1 kg to go · about 31 weeks"], estimate: true,
        logPrimary: true, history: "10 weigh-ins", phaseLink: "Fixture cut",
        card: ["97.1", "Weigh-in due this week"], cardDimmed: false)

    static let b13 = ScorecardFrame(
        digest: "v holdSteady noChangeRuleFired - - o[] u[liftsHoldingWaistShrinking,slowLoss] | r unknown:liftSignalUnknown:0:1 notFired:-:0:3 unknown:missedWeighIn:0:3 | w met shrinking 96.500 97.000 2031-03-03 -0.500 | l unknown noSessionsThisWeek 0 0 0 0 2031-03-12 2031-03-18 | p unknown noProteinData 0 0 | b notMet belowBand 0.342 | rate 0.331 0.342 4 2031-02-17 2031-03-17 | pj projected 2031-05-01 2.000 | cur 96.000 2031-03-19 J 2031-03-17",
        phase: ["Phase · week 11", "Fixture cut", "Target 94.0 kg · started Mon 6 Jan · band 0.40–1.20% per week"],
        due: nil,
        reached: nil,
        header: "Verdict · week of 17 Mar", summary: "1 of 4 signals met",
        title: "Change nothing", withheld: false,
        lines: ["None of your change rules fired."],
        couldNotCheck: ["Could not check: lifts holding and waist shrinking", "Could not check: slow loss"], ownRule: false,
        rules: [["Lifts holding and waist shrinking", "Could not check", "lifts not known"],
                ["Lifts dropping", "Not fired", "0 of 3 weeks"],
                ["Slow loss", "Could not check", "0 of 3 weeks · a week has no weigh-in"]],
        signals: [["Waist", "Met", "Down 0.5 cm in 2 weeks", "96.5 cm now · 97.0 cm in the week of 3 Mar"],
                  ["Working weights", "Unknown", "Not known: no sessions in these days", "12 Mar – 18 Mar"],
                  ["Protein floor", "Unknown", "No protein data", "Floor 100 g"],
                  ["Rate of loss", "Not met", "Below your band", "0.33 kg per week, 0.34% of bodyweight · band 0.40–1.20%"]],
        weight: ["96.0", "Weighed Wed 19 Mar · Lab Book", "100.0,99.2,98.4,97.6,97.5,97.4,97.3,97.2,97.1,x,96.0", "6 Jan", "17 Mar", "Rate of loss", "0.33", "0.34", "Line fitted to 4 weekly points, weeks of 17 Feb – 17 Mar"],
        waist: ["96.5", "Measured Wed 19 Mar · Lab Book", "100.0,99.5,99.0,98.5,98.0,97.5,97.0,97.0,97.0,x,96.5", "Since the week of 3 Mar", "−0.5", "Since the week of 6 Jan", "−3.5"],
        projection: ["Projection · target 94.0 kg", "Estimated Thu 1 May at this rate", "2.0 kg to go · about 6 weeks"], estimate: true,
        logPrimary: false, history: "11 weigh-ins", phaseLink: "Fixture cut",
        card: ["96.0", "Change nothing"], cardDimmed: false)

    static let b14 = ScorecardFrame(
        digest: "v holdSteady noChangeRuleFired - - o[] u[liftsHoldingWaistShrinking,liftsDropping] | r unknown:liftSignalUnknown:0:1 unknown:liftSignalUnknown:0:3 notFired:-:1:3 | w met shrinking 95.500 96.500 2031-03-17 -1.000 | l unknown noSessionsThisWeek 0 0 0 0 2031-03-26 2031-04-01 | p unknown noProteinData 0 0 | b met withinBand 0.554 | rate 0.531 0.554 4 2031-03-03 2031-03-31 | pj projected 2031-04-17 1.100 | cur 95.100 2031-04-02 J 2031-03-31",
        phase: ["Phase · week 13", "Fixture cut", "Target 94.0 kg · started Mon 6 Jan · band 0.40–1.20% per week"],
        due: nil,
        reached: nil,
        header: "Verdict · week of 31 Mar", summary: "2 of 4 signals met",
        title: "Change nothing", withheld: false,
        lines: ["None of your change rules fired."],
        couldNotCheck: ["Could not check: lifts holding and waist shrinking", "Could not check: lifts dropping"], ownRule: false,
        rules: [["Lifts holding and waist shrinking", "Could not check", "lifts not known"],
                ["Lifts dropping", "Could not check", "0 of 3 weeks · lifts not known"],
                ["Slow loss", "Not fired", "1 of 3 weeks"]],
        signals: [["Waist", "Met", "Down 1.0 cm in 2 weeks", "95.5 cm now · 96.5 cm in the week of 17 Mar"],
                  ["Working weights", "Unknown", "Not known: no sessions in these days", "26 Mar – 1 Apr"],
                  ["Protein floor", "Unknown", "No protein data", "Floor 100 g"],
                  ["Rate of loss", "Met", "0.53 kg per week, 0.55% of bodyweight", "band 0.40–1.20%"]],
        weight: ["95.1", "Weighed Wed 2 Apr · Lab Book", "100.0,99.2,98.4,97.6,97.5,97.4,97.3,97.2,97.1,x,96.0,95.2,95.1", "6 Jan", "31 Mar", "Rate of loss", "0.53", "0.55", "Line fitted to 4 weekly points, weeks of 3 Mar – 31 Mar"],
        waist: ["95.5", "Measured Wed 2 Apr · Lab Book", "100.0,99.5,99.0,98.5,98.0,97.5,97.0,97.0,97.0,x,96.5,96.0,95.5", "Since the week of 17 Mar", "−1.0", "Since the week of 6 Jan", "−4.5"],
        projection: ["Projection · target 94.0 kg", "Estimated Thu 17 Apr at this rate", "1.1 kg to go · about 2 weeks"], estimate: true,
        logPrimary: false, history: "13 weigh-ins", phaseLink: "Fixture cut",
        card: ["95.1", "Change nothing"], cardDimmed: false)

    static let b15 = ScorecardFrame(
        digest: "v insufficientData recompositionCheckIncomplete - - o[] u[liftsHoldingWaistShrinking,liftsDropping] | r unknown:liftSignalUnknown:0:1 unknown:liftSignalUnknown:0:3 fired:-:3:3 | w met shrinking 94.500 95.500 2031-03-31 -1.000 | l unknown noSessionsThisWeek 0 0 0 0 2031-04-09 2031-04-15 | p unknown noProteinData 0 0 | b notMet belowBand 0.252 | rate 0.240 0.252 5 2031-03-17 2031-04-14 | pj projected 2031-05-13 0.900 | cur 94.900 2031-04-16 J 2031-04-14",
        phase: ["Phase · week 15", "Fixture cut", "Target 94.0 kg · started Mon 6 Jan · band 0.40–1.20% per week"],
        due: nil,
        reached: nil,
        header: "Verdict · week of 14 Apr", summary: "1 of 4 signals met",
        title: "No verdict this week", withheld: true,
        lines: ["The scale was slow, but lifts are not known, so a good week cannot be told from a stall."],
        couldNotCheck: ["Could not check: lifts holding and waist shrinking", "Could not check: lifts dropping"], ownRule: false,
        rules: [["Lifts holding and waist shrinking", "Could not check", "lifts not known"],
                ["Lifts dropping", "Could not check", "0 of 3 weeks · lifts not known"],
                ["Slow loss", "Fired", "3 of 3 weeks"]],
        signals: [["Waist", "Met", "Down 1.0 cm in 2 weeks", "94.5 cm now · 95.5 cm in the week of 31 Mar"],
                  ["Working weights", "Unknown", "Not known: no sessions in these days", "9 Apr – 15 Apr"],
                  ["Protein floor", "Unknown", "No protein data", "Floor 100 g"],
                  ["Rate of loss", "Not met", "Below your band", "0.24 kg per week, 0.25% of bodyweight · band 0.40–1.20%"]],
        weight: ["94.9", "Weighed Wed 16 Apr · Lab Book", "100.0,99.2,98.4,97.6,97.5,97.4,97.3,97.2,97.1,x,96.0,95.2,95.1,95.0,94.9", "6 Jan", "14 Apr", "Rate of loss", "0.24", "0.25", "Line fitted to 5 weekly points, weeks of 17 Mar – 14 Apr"],
        waist: ["94.5", "Measured Wed 16 Apr · Lab Book", "100.0,99.5,99.0,98.5,98.0,97.5,97.0,97.0,97.0,x,96.5,96.0,95.5,95.0,94.5", "Since the week of 31 Mar", "−1.0", "Since the week of 6 Jan", "−5.5"],
        projection: ["Projection · target 94.0 kg", "Estimated Tue 13 May at this rate", "0.9 kg to go · about 4 weeks"], estimate: true,
        logPrimary: false, history: "15 weigh-ins", phaseLink: "Fixture cut",
        card: ["94.9", "Lifts not known this week"], cardDimmed: false)

    static let b16 = ScorecardFrame(
        digest: "v reduceCarbs ruleFired slowLoss -250.000 o[] u[liftsDropping] | r notFired:-:0:1 unknown:liftSignalUnknown:1:3 fired:-:5:3 | w notMet notShrinking 94.500 94.500 2031-04-14 0.000 | l notMet dropping 2 2 0 0 2031-04-23 2031-04-29 | p unknown noProteinData 0 0 | b notMet belowBand 0.105 | rate 0.100 0.105 5 2031-03-31 2031-04-28 | pj projected 2031-06-18 0.700 | cur 94.700 2031-04-30 J 2031-04-28",
        phase: ["Phase · week 17", "Fixture cut", "Target 94.0 kg · started Mon 6 Jan · band 0.40–1.20% per week"],
        due: nil,
        reached: nil,
        header: "Verdict · week of 28 Apr", summary: "0 of 4 signals met",
        title: "Your rule: take 250 kcal from carbohydrate", withheld: false,
        lines: ["Loss was under 0.4 kg per week for 5 weeks."],
        couldNotCheck: ["Could not check: lifts dropping"], ownRule: true,
        rules: [["Lifts holding and waist shrinking", "Not fired", ""],
                ["Lifts dropping", "Could not check", "1 of 3 weeks · lifts not known"],
                ["Slow loss", "Fired", "3 of 3 weeks"]],
        signals: [["Waist", "Not met", "Not shrinking", "94.5 cm now · 94.5 cm in the week of 14 Apr"],
                  ["Working weights", "Not met", "Dropping", "0 climbed, 0 held, 2 dropped of 2 exercises · 23 Apr – 29 Apr"],
                  ["Protein floor", "Unknown", "No protein data", "Floor 100 g"],
                  ["Rate of loss", "Not met", "Below your band", "0.10 kg per week, 0.10% of bodyweight · band 0.40–1.20%"]],
        weight: ["94.7", "Weighed Wed 30 Apr · Lab Book", "100.0,99.2,98.4,97.6,97.5,97.4,97.3,97.2,97.1,x,96.0,95.2,95.1,95.0,94.9,94.8,94.7", "6 Jan", "28 Apr", "Rate of loss", "0.10", "0.10", "Line fitted to 5 weekly points, weeks of 31 Mar – 28 Apr"],
        waist: ["94.5", "Measured Wed 30 Apr · Lab Book", "100.0,99.5,99.0,98.5,98.0,97.5,97.0,97.0,97.0,x,96.5,96.0,95.5,95.0,94.5,94.5,94.5", "Since the week of 14 Apr", "0.0", "Since the week of 6 Jan", "−5.5"],
        projection: ["Projection · target 94.0 kg", "Estimated Wed 18 Jun at this rate", "0.7 kg to go · about 7 weeks"], estimate: true,
        logPrimary: false, history: "17 weigh-ins", phaseLink: "Fixture cut",
        card: ["94.7", "Your rule: take 250 kcal from carbohydrate"], cardDimmed: false)

    static let b17 = ScorecardFrame(
        digest: "v addCalories ruleFired liftsDropping 300.000 o[slowLoss] u[] | r notFired:-:0:1 fired:-:3:3 fired:-:7:3 | w notMet notShrinking 94.500 94.500 2031-04-28 0.000 | l notMet dropping 2 2 0 0 2031-05-07 2031-05-13 | p unknown noProteinData 0 0 | b notMet belowBand 0.106 | rate 0.100 0.106 5 2031-04-14 2031-05-12 | pj projected 2031-06-18 0.500 | cur 94.500 2031-05-14 J 2031-05-12",
        phase: ["Phase · week 19", "Fixture cut", "Target 94.0 kg · started Mon 6 Jan · band 0.40–1.20% per week"],
        due: nil,
        reached: nil,
        header: "Verdict · week of 12 May", summary: "0 of 4 signals met",
        title: "Your rule: add 300 kcal", withheld: false,
        lines: ["Working weights dropped 3 weeks running.", "The scale was also slow. Your lifts rule comes first."],
        couldNotCheck: [], ownRule: true,
        rules: [["Lifts holding and waist shrinking", "Not fired", ""],
                ["Lifts dropping", "Fired", "3 of 3 weeks"],
                ["Slow loss", "Fired", "3 of 3 weeks"]],
        signals: [["Waist", "Not met", "Not shrinking", "94.5 cm now · 94.5 cm in the week of 28 Apr"],
                  ["Working weights", "Not met", "Dropping", "0 climbed, 0 held, 2 dropped of 2 exercises · 7 May – 13 May"],
                  ["Protein floor", "Unknown", "No protein data", "Floor 100 g"],
                  ["Rate of loss", "Not met", "Below your band", "0.10 kg per week, 0.11% of bodyweight · band 0.40–1.20%"]],
        weight: ["94.5", "Weighed Wed 14 May · Lab Book", "100.0,99.2,98.4,97.6,97.5,97.4,97.3,97.2,97.1,x,96.0,95.2,95.1,95.0,94.9,94.8,94.7,94.6,94.5", "6 Jan", "12 May", "Rate of loss", "0.10", "0.11", "Line fitted to 5 weekly points, weeks of 14 Apr – 12 May"],
        waist: ["94.5", "Measured Wed 14 May · Lab Book", "100.0,99.5,99.0,98.5,98.0,97.5,97.0,97.0,97.0,x,96.5,96.0,95.5,95.0,94.5,94.5,94.5,94.5,94.5", "Since the week of 28 Apr", "0.0", "Since the week of 6 Jan", "−5.5"],
        projection: ["Projection · target 94.0 kg", "Estimated Wed 18 Jun at this rate", "0.5 kg to go · about 5 weeks"], estimate: true,
        logPrimary: false, history: "19 weigh-ins", phaseLink: "Fixture cut",
        card: ["94.5", "Your rule: add 300 kcal"], cardDimmed: false)

    static let b18 = ScorecardFrame(
        digest: "v reduceCarbs ruleFired slowLoss -250.000 o[] u[] | r notFired:-:0:1 notFired:-:0:3 fired:-:8:3 | w notMet notShrinking 94.500 94.500 2031-05-05 0.000 | l met holding 2 0 0 2 2031-05-14 2031-05-20 | p unknown noProteinData 0 0 | b notMet belowBand -0.127 | rate -0.120 -0.127 5 2031-04-21 2031-05-19 | pj notLosing - 1.500 | cur 95.500 2031-05-21 J 2031-05-19",
        phase: ["Phase · week 20", "Fixture cut", "Target 94.0 kg · started Mon 6 Jan · band 0.40–1.20% per week"],
        due: nil,
        reached: nil,
        header: "Verdict · week of 19 May", summary: "1 of 4 signals met",
        title: "Your rule: take 250 kcal from carbohydrate", withheld: false,
        lines: ["Loss was under 0.4 kg per week for 8 weeks."],
        couldNotCheck: [], ownRule: true,
        rules: [["Lifts holding and waist shrinking", "Not fired", ""],
                ["Lifts dropping", "Not fired", "0 of 3 weeks"],
                ["Slow loss", "Fired", "3 of 3 weeks"]],
        signals: [["Waist", "Not met", "Not shrinking", "94.5 cm now · 94.5 cm in the week of 5 May"],
                  ["Working weights", "Met", "Holding or climbing", "0 climbed, 2 held, 0 dropped of 2 exercises · 14 May – 20 May"],
                  ["Protein floor", "Unknown", "No protein data", "Floor 100 g"],
                  ["Rate of loss", "Not met", "Below your band", "Gaining 0.12 kg per week, 0.13% of bodyweight · band 0.40–1.20%"]],
        weight: ["95.5", "Weighed Wed 21 May · Lab Book", "100.0,99.2,98.4,97.6,97.5,97.4,97.3,97.2,97.1,x,96.0,95.2,95.1,95.0,94.9,94.8,94.7,94.6,94.5,95.5", "6 Jan", "19 May", "Rate of gain", "0.12", "0.13", "Line fitted to 5 weekly points, weeks of 21 Apr – 19 May"],
        waist: ["94.5", "Measured Wed 21 May · Lab Book", "100.0,99.5,99.0,98.5,98.0,97.5,97.0,97.0,97.0,x,96.5,96.0,95.5,95.0,94.5,94.5,94.5,94.5,94.5,94.5", "Since the week of 5 May", "0.0", "Since the week of 6 Jan", "−5.5"],
        projection: ["Projection · target 94.0 kg", "No date while weight is not falling", "1.5 kg to go"], estimate: false,
        logPrimary: false, history: "20 weigh-ins", phaseLink: "Fixture cut",
        card: ["95.5", "Your rule: take 250 kcal from carbohydrate"], cardDimmed: false)

    static let b19 = ScorecardFrame(
        digest: "v holdSteady ruleFired liftsHoldingWaistShrinking - o[] u[] | r fired:-:1:1 notFired:-:0:3 notFired:-:0:3 | w met shrinking 94.000 94.500 2031-05-12 -0.500 | l met holding 2 0 0 2 2031-05-21 2031-05-27 | p unknown noProteinData 0 0 | b notMet belowBand 0.053 | rate 0.050 0.053 5 2031-04-28 2031-05-26 | pj targetReached - 0.000 | cur 94.000 2031-05-28 J 2031-05-26",
        phase: ["Phase · week 21", "Fixture cut", "Target 94.0 kg · started Mon 6 Jan · band 0.40–1.20% per week"],
        due: nil,
        reached: ["Target reached", "94.0 kg on Wed 28 May · target 94.0 kg"],
        header: "Verdict · week of 26 May", summary: "2 of 4 signals met",
        title: "Change nothing", withheld: false,
        lines: ["Lifts are holding and your waist is shrinking."],
        couldNotCheck: [], ownRule: false,
        rules: [["Lifts holding and waist shrinking", "Fired", ""],
                ["Lifts dropping", "Not fired", "0 of 3 weeks"],
                ["Slow loss", "Not fired", "0 of 3 weeks"]],
        signals: [["Waist", "Met", "Down 0.5 cm in 2 weeks", "94.0 cm now · 94.5 cm in the week of 12 May"],
                  ["Working weights", "Met", "Holding or climbing", "0 climbed, 2 held, 0 dropped of 2 exercises · 21 May – 27 May"],
                  ["Protein floor", "Unknown", "No protein data", "Floor 100 g"],
                  ["Rate of loss", "Not met", "Below your band", "0.05 kg per week, 0.05% of bodyweight · band 0.40–1.20%"]],
        weight: ["94.0", "Weighed Wed 28 May · Lab Book", "100.0,99.2,98.4,97.6,97.5,97.4,97.3,97.2,97.1,x,96.0,95.2,95.1,95.0,94.9,94.8,94.7,94.6,94.5,95.5,94.0", "6 Jan", "26 May", "Rate of loss", "0.05", "0.05", "Line fitted to 5 weekly points, weeks of 28 Apr – 26 May"],
        waist: ["94.0", "Measured Wed 28 May · Lab Book", "100.0,99.5,99.0,98.5,98.0,97.5,97.0,97.0,97.0,x,96.5,96.0,95.5,95.0,94.5,94.5,94.5,94.5,94.5,94.5,94.0", "Since the week of 12 May", "−0.5", "Since the week of 6 Jan", "−6.0"],
        projection: ["Projection · target 94.0 kg", "Target reached", ""], estimate: false,
        logPrimary: false, history: "21 weigh-ins", phaseLink: "Fixture cut",
        card: ["94.0", "Target reached"], cardDimmed: false)

    static let b20 = ScorecardFrame(
        digest: "v insufficientData weighInOverdue - - o[] u[] | r unknown:weighInOverdue:0:1 unknown:weighInOverdue:0:3 unknown:weighInOverdue:0:3 | w unknown weighInOverdue - - - - | l unknown weighInOverdue 0 0 0 0 | p unknown weighInOverdue 0 0 | b unknown weighInOverdue - | rate - weighInOverdue | pj weighInOverdue - - | cur 97.100 2031-03-05 J 2031-03-03",
        phase: ["Phase · week 11", "Fixture cut", "Target 94.0 kg · started Mon 6 Jan · band 0.40–1.20% per week"],
        due: nil,
        reached: nil,
        header: "Verdict · week of 3 Mar", summary: nil,
        title: "Last weigh-in Wed 5 Mar", withheld: true,
        lines: [],
        couldNotCheck: [], ownRule: false,
        rules: [["Lifts holding and waist shrinking", "Could not check", "the last weigh-in is too old"],
                ["Lifts dropping", "Could not check", "0 of 3 weeks · the last weigh-in is too old"],
                ["Slow loss", "Could not check", "0 of 3 weeks · the last weigh-in is too old"]],
        signals: [["Waist", "Unknown", "No current weigh-in", ""],
                  ["Working weights", "Unknown", "No current weigh-in", ""],
                  ["Protein floor", "Unknown", "No current weigh-in", ""],
                  ["Rate of loss", "Unknown", "No current weigh-in", ""]],
        weight: ["97.1", "Weighed Wed 5 Mar · Lab Book", "100.0,99.2,98.4,97.6,97.5,97.4,97.3,97.2,97.1,x,x", "6 Jan", "17 Mar", "Rate of loss", "", "", "No current weigh-in"],
        waist: ["97.0", "Measured Wed 5 Mar · Lab Book", "100.0,99.5,99.0,98.5,98.0,97.5,97.0,97.0,97.0,x,x", "Change", "", "Since the week of 6 Jan", "−3.0"],
        projection: ["Projection · target 94.0 kg", "Last weigh-in Wed 5 Mar", ""], estimate: false,
        logPrimary: true, history: "10 weigh-ins", phaseLink: "Fixture cut",
        card: ["97.1", "Last weigh-in Wed 5 Mar"], cardDimmed: true)

    static let b21 = ScorecardFrame(
        digest: "v holdSteady ruleFired liftsHoldingWaistShrinking - o[] u[] | r fired:-:1:1 notFired:-:0:3 notFired:-:0:3 | w met shrinking 98.500 99.500 2031-01-13 -1.000 | l met holding 2 0 0 2 2031-01-22 2031-01-28 | p unknown noFloorConfigured 0 0 | b met withinBand 0.810 | rate 0.800 0.810 4 2031-01-06 2031-01-27 | pj noTarget - - | cur 97.600 2031-01-29 J 2031-01-27",
        phase: ["Phase · week 4", "Fixture cut", "No target set · started Mon 6 Jan · band 0.40–1.20% per week"],
        due: nil,
        reached: nil,
        header: "Verdict · week of 27 Jan", summary: "3 of 4 signals met",
        title: "Change nothing", withheld: false,
        lines: ["Lifts are holding and your waist is shrinking."],
        couldNotCheck: [], ownRule: false,
        rules: [["Lifts holding and waist shrinking", "Fired", ""],
                ["Lifts dropping", "Not fired", "0 of 3 weeks"],
                ["Slow loss", "Not fired", "0 of 3 weeks"]],
        signals: [["Waist", "Met", "Down 1.0 cm in 2 weeks", "98.5 cm now · 99.5 cm in the week of 13 Jan"],
                  ["Working weights", "Met", "Holding or climbing", "0 climbed, 2 held, 0 dropped of 2 exercises · 22 Jan – 28 Jan"],
                  ["Protein floor", "Unknown", "No floor set", ""],
                  ["Rate of loss", "Met", "0.80 kg per week, 0.81% of bodyweight", "band 0.40–1.20%"]],
        weight: ["97.6", "Weighed Wed 29 Jan · Lab Book", "100.0,99.2,98.4,97.6", "6 Jan", "27 Jan", "Rate of loss", "0.80", "0.81", "Line fitted to 4 weekly points, weeks of 6 Jan – 27 Jan"],
        waist: ["98.5", "Measured Wed 29 Jan · Lab Book", "100.0,99.5,99.0,98.5", "Since the week of 13 Jan", "−1.0", "Since the week of 6 Jan", "−1.5"],
        projection: ["Projection", "No target set", ""], estimate: false,
        logPrimary: false, history: "5 weigh-ins", phaseLink: "Fixture cut",
        card: ["97.6", "Change nothing"], cardDimmed: false)

    static let b22 = ScorecardFrame(
        digest: "v holdSteady ruleFired liftsHoldingWaistShrinking - o[slowLoss] u[] | r fired:-:1:1 notFired:-:0:3 fired:-:4:3 | w met shrinking 97.000 97.500 2031-02-10 -0.500 | l met holding 2 0 0 2 2031-02-19 2031-02-25 | p unknown noProteinData 0 0 | b notMet belowBand 0.103 | rate 0.100 0.103 5 2031-01-27 2031-02-24 | pj beyondHorizon - 17.200 | cur 97.200 2031-02-26 J 2031-02-24",
        phase: ["Phase · week 8", "Fixture cut", "Target 80.0 kg · started Mon 6 Jan · band 0.40–1.20% per week"],
        due: nil,
        reached: nil,
        header: "Verdict · week of 24 Feb", summary: "2 of 4 signals met",
        title: "Change nothing", withheld: false,
        lines: ["Lifts are holding and your waist is shrinking.", "The scale was slow for 4 weeks. That is expected when waist and lifts are on track."],
        couldNotCheck: [], ownRule: false,
        rules: [["Lifts holding and waist shrinking", "Fired", ""],
                ["Lifts dropping", "Not fired", "0 of 3 weeks"],
                ["Slow loss", "Fired", "3 of 3 weeks"]],
        signals: [["Waist", "Met", "Down 0.5 cm in 2 weeks", "97.0 cm now · 97.5 cm in the week of 10 Feb"],
                  ["Working weights", "Met", "Holding or climbing", "0 climbed, 2 held, 0 dropped of 2 exercises · 19 Feb – 25 Feb"],
                  ["Protein floor", "Unknown", "No protein data", "Floor 100 g"],
                  ["Rate of loss", "Not met", "Below your band", "0.10 kg per week, 0.10% of bodyweight · band 0.40–1.20%"]],
        weight: ["97.2", "Weighed Wed 26 Feb · Lab Book", "100.0,99.2,98.4,97.6,97.5,97.4,97.3,97.2", "6 Jan", "24 Feb", "Rate of loss", "0.10", "0.10", "Line fitted to 5 weekly points, weeks of 27 Jan – 24 Feb"],
        waist: ["97.0", "Measured Wed 26 Feb · Lab Book", "100.0,99.5,99.0,98.5,98.0,97.5,97.0,97.0", "Since the week of 10 Feb", "−0.5", "Since the week of 6 Jan", "−3.0"],
        projection: ["Projection · target 80.0 kg", "More than 104 weeks at this rate", "17.2 kg to go"], estimate: false,
        logPrimary: false, history: "9 weigh-ins", phaseLink: "Fixture cut",
        card: ["97.2", "Change nothing"], cardDimmed: false)

    static let b23 = ScorecardFrame(
        digest: "v holdSteady ruleFired liftsHoldingWaistShrinking - o[] u[] | r fired:-:1:1 notFired:-:0:3 notFired:-:0:3 | w met shrinking 98.500 99.500 2031-01-13 -1.000 | l met holding 2 0 0 2 2031-01-22 2031-01-28 | p met floorMet 7 6 | b met withinBand 0.810 | rate 0.800 0.810 4 2031-01-06 2031-01-27 | pj needsNewWeighIn - 0.600 | cur 97.600 2031-01-29 J 2031-01-27",
        phase: ["Phase · week 5", "Fixture cut", "Target 97.0 kg · started Mon 6 Jan · band 0.40–1.20% per week"],
        due: ["Weigh-in due this week", "The verdict below is from the week of 27 Jan."],
        reached: nil,
        header: "Verdict · week of 27 Jan", summary: "4 of 4 signals met",
        title: "Change nothing", withheld: false,
        lines: ["Lifts are holding and your waist is shrinking."],
        couldNotCheck: [], ownRule: false,
        rules: [["Lifts holding and waist shrinking", "Fired", ""],
                ["Lifts dropping", "Not fired", "0 of 3 weeks"],
                ["Slow loss", "Not fired", "0 of 3 weeks"]],
        signals: [["Waist", "Met", "Down 1.0 cm in 2 weeks", "98.5 cm now · 99.5 cm in the week of 13 Jan"],
                  ["Working weights", "Met", "Holding or climbing", "0 climbed, 2 held, 0 dropped of 2 exercises · 22 Jan – 28 Jan"],
                  ["Protein floor", "Met", "6 of 7 days at or above your floor", "Floor 100 g · 7 of 7 days logged, 6 at or above · needs 5"],
                  ["Rate of loss", "Met", "0.80 kg per week, 0.81% of bodyweight", "band 0.40–1.20%"]],
        weight: ["97.6", "Weighed Wed 29 Jan · Lab Book", "100.0,99.2,98.4,97.6,x", "6 Jan", "3 Feb", "Rate of loss", "0.80", "0.81", "Line fitted to 4 weekly points, weeks of 6 Jan – 27 Jan"],
        waist: ["98.5", "Measured Wed 29 Jan · Lab Book", "100.0,99.5,99.0,98.5,x", "Since the week of 13 Jan", "−1.0", "Since the week of 6 Jan", "−1.5"],
        projection: ["Projection · target 97.0 kg", "Log a weigh-in to check the target", ""], estimate: false,
        logPrimary: true, history: "5 weigh-ins", phaseLink: "Fixture cut",
        card: ["97.6", "Weigh-in due this week"], cardDimmed: false)

    static let b24 = ScorecardFrame(
        digest: "v holdSteady ruleFired liftsHoldingWaistShrinking - o[] u[] | r fired:-:1:1 notFired:-:0:3 notFired:-:0:3 | w met shrinking 98.500 99.500 2031-01-13 -1.000 | l met holding 2 0 0 2 2031-01-22 2031-01-28 | p met floorMet 7 6 | b met withinBand 0.810 | rate 0.800 0.810 4 2031-01-06 2031-01-27 | pj projected 2031-03-02 3.600 | cur 97.600 2031-01-29 J 2031-01-27",
        phase: ["Phase · week 4", "Fixture cut", "Target 94.0 kg · started Mon 6 Jan · band 0.40–1.20% per week"],
        due: nil,
        reached: nil,
        header: "Verdict · week of 27 Jan", summary: "4 of 4 signals met",
        title: "Your rules need attention", withheld: true,
        lines: [],
        couldNotCheck: [], ownRule: false,
        rules: [],
        signals: [["Waist", "Met", "Down 1.0 cm in 2 weeks", "98.5 cm now · 99.5 cm in the week of 13 Jan"],
                  ["Working weights", "Met", "Holding or climbing", "0 climbed, 2 held, 0 dropped of 2 exercises · 22 Jan – 28 Jan"],
                  ["Protein floor", "Met", "6 of 7 days at or above your floor", "Floor 100 g · 7 of 7 days logged, 6 at or above · needs 5"],
                  ["Rate of loss", "Met", "0.80 kg per week, 0.81% of bodyweight", "band 0.40–1.20%"]],
        weight: ["97.6", "Weighed Wed 29 Jan · Lab Book", "100.0,99.2,98.4,97.6", "6 Jan", "27 Jan", "Rate of loss", "0.80", "0.81", "Line fitted to 4 weekly points, weeks of 6 Jan – 27 Jan"],
        waist: ["98.5", "Measured Wed 29 Jan · Lab Book", "100.0,99.5,99.0,98.5", "Since the week of 13 Jan", "−1.0", "Since the week of 6 Jan", "−1.5"],
        projection: ["Projection · target 94.0 kg", "Estimated Sun 2 Mar at this rate", "3.6 kg to go · about 5 weeks"], estimate: true,
        logPrimary: false, history: "5 weigh-ins", phaseLink: "Fixture cut",
        card: ["97.6", "Your rules need attention"], cardDimmed: false)

    static let b25 = ScorecardFrame(
        digest: "v holdSteady ruleFired liftsHoldingWaistShrinking - o[] u[] | r fired:-:1:1 notFired:-:0:3 notFired:-:0:3 | w met shrinking 98.500 99.500 2031-01-13 -1.000 | l met holding 2 0 0 2 2031-01-22 2031-01-28 | p met floorMet 7 6 | b met withinBand 0.810 | rate 0.800 0.810 4 2031-01-06 2031-01-27 | pj projected 2031-03-02 3.600 | cur 97.600 2031-01-29 J 2031-01-27",
        phase: ["Phase · week 4", "Fixture cut", "Target 207.2 lb · started Mon 6 Jan · band 0.40–1.20% per week"],
        due: nil,
        reached: nil,
        header: "Verdict · week of 27 Jan", summary: "4 of 4 signals met",
        title: "Change nothing", withheld: false,
        lines: ["Lifts are holding and your waist is shrinking."],
        couldNotCheck: [], ownRule: false,
        rules: [["Lifts holding and waist shrinking", "Fired", ""],
                ["Lifts dropping", "Not fired", "0 of 3 weeks"],
                ["Slow loss", "Not fired", "0 of 3 weeks"]],
        signals: [["Waist", "Met", "Down 0.4 in in 2 weeks", "38.8 in now · 39.2 in in the week of 13 Jan"],
                  ["Working weights", "Met", "Holding or climbing", "0 climbed, 2 held, 0 dropped of 2 exercises · 22 Jan – 28 Jan"],
                  ["Protein floor", "Met", "6 of 7 days at or above your floor", "Floor 100 g · 7 of 7 days logged, 6 at or above · needs 5"],
                  ["Rate of loss", "Met", "1.76 lb per week, 0.81% of bodyweight", "band 0.40–1.20%"]],
        weight: ["215.2", "Weighed Wed 29 Jan · Lab Book", "220.5,218.7,216.9,215.2", "6 Jan", "27 Jan", "Rate of loss", "1.76", "0.81", "Line fitted to 4 weekly points, weeks of 6 Jan – 27 Jan"],
        waist: ["38.8", "Measured Wed 29 Jan · Lab Book", "39.4,39.2,39.0,38.8", "Since the week of 13 Jan", "−0.4", "Since the week of 6 Jan", "−0.6"],
        projection: ["Projection · target 207.2 lb", "Estimated Sun 2 Mar at this rate", "7.9 lb to go · about 5 weeks"], estimate: true,
        logPrimary: false, history: "5 weigh-ins", phaseLink: "Fixture cut",
        card: ["215.2", "Change nothing"], cardDimmed: false)

    static let week2 = ScorecardFrame(
        digest: "v holdSteady ruleFired liftsHoldingWaistShrinking - o[] u[] | r fired:-:1:1 notFired:-:0:3 notFired:-:0:3 | w met shrinking 99.500 100.000 2031-01-06 -0.500 | l met holding 2 0 0 2 2031-01-08 2031-01-14 | p met floorMet 7 6 | b met withinBand 0.803 | rate 0.800 0.803 2 2031-01-06 2031-01-13 | pj projected 2031-03-02 5.200 | cur 99.200 2031-01-15 J 2031-01-13",
        phase: ["Phase · week 2", "Fixture cut", "Target 94.0 kg · started Mon 6 Jan · band 0.40–1.20% per week"],
        due: nil,
        reached: nil,
        header: "Verdict · week of 13 Jan", summary: "4 of 4 signals met",
        title: "Change nothing", withheld: false,
        lines: ["Lifts are holding and your waist is shrinking."],
        couldNotCheck: [], ownRule: false,
        rules: [["Lifts holding and waist shrinking", "Fired", ""],
                ["Lifts dropping", "Not fired", "0 of 3 weeks"],
                ["Slow loss", "Not fired", "0 of 3 weeks"]],
        signals: [["Waist", "Met", "Down 0.5 cm in 1 week", "99.5 cm now · 100.0 cm in the week of 6 Jan"],
                  ["Working weights", "Met", "Holding or climbing", "0 climbed, 2 held, 0 dropped of 2 exercises · 8 Jan – 14 Jan"],
                  ["Protein floor", "Met", "6 of 7 days at or above your floor", "Floor 100 g · 7 of 7 days logged, 6 at or above · needs 5"],
                  ["Rate of loss", "Met", "0.80 kg per week, 0.80% of bodyweight", "band 0.40–1.20%"]],
        weight: ["99.2", "Weighed Wed 15 Jan · Lab Book", "100.0,99.2", "6 Jan", "13 Jan", "Rate of loss", "0.80", "0.80", "Line fitted to 2 weekly points, weeks of 6 Jan – 13 Jan"],
        waist: ["99.5", "Measured Wed 15 Jan · Lab Book", "100.0,99.5", "Since the week of 6 Jan", "−0.5", "Since the week of 6 Jan", "−0.5"],
        projection: ["Projection · target 94.0 kg", "Estimated Sun 2 Mar at this rate", "5.2 kg to go · about 7 weeks"], estimate: true,
        logPrimary: false, history: "2 weigh-ins", phaseLink: "Fixture cut",
        card: ["99.2", "Change nothing"], cardDimmed: false)

    static let week8 = ScorecardFrame(
        digest: "v holdSteady ruleFired liftsHoldingWaistShrinking - o[slowLoss] u[] | r fired:-:1:1 notFired:-:0:3 fired:-:4:3 | w met shrinking 97.000 97.500 2031-02-10 -0.500 | l met holding 2 0 0 2 2031-02-19 2031-02-25 | p unknown noProteinData 0 0 | b notMet belowBand 0.103 | rate 0.100 0.103 5 2031-01-27 2031-02-24 | pj projected 2031-10-08 3.200 | cur 97.200 2031-02-26 J 2031-02-24",
        phase: ["Phase · week 8", "Fixture cut", "Target 94.0 kg · started Mon 6 Jan · band 0.40–1.20% per week"],
        due: nil,
        reached: nil,
        header: "Verdict · week of 24 Feb", summary: "2 of 4 signals met",
        title: "Change nothing", withheld: false,
        lines: ["Lifts are holding and your waist is shrinking.", "The scale was slow for 4 weeks. That is expected when waist and lifts are on track."],
        couldNotCheck: [], ownRule: false,
        rules: [["Lifts holding and waist shrinking", "Fired", ""],
                ["Lifts dropping", "Not fired", "0 of 3 weeks"],
                ["Slow loss", "Fired", "3 of 3 weeks"]],
        signals: [["Waist", "Met", "Down 0.5 cm in 2 weeks", "97.0 cm now · 97.5 cm in the week of 10 Feb"],
                  ["Working weights", "Met", "Holding or climbing", "0 climbed, 2 held, 0 dropped of 2 exercises · 19 Feb – 25 Feb"],
                  ["Protein floor", "Unknown", "No protein data", "Floor 100 g"],
                  ["Rate of loss", "Not met", "Below your band", "0.10 kg per week, 0.10% of bodyweight · band 0.40–1.20%"]],
        weight: ["97.2", "Weighed Wed 26 Feb · Lab Book", "100.0,99.2,98.4,97.6,97.5,97.4,97.3,97.2", "6 Jan", "24 Feb", "Rate of loss", "0.10", "0.10", "Line fitted to 5 weekly points, weeks of 27 Jan – 24 Feb"],
        waist: ["97.0", "Measured Wed 26 Feb · Lab Book", "100.0,99.5,99.0,98.5,98.0,97.5,97.0,97.0", "Since the week of 10 Feb", "−0.5", "Since the week of 6 Jan", "−3.0"],
        projection: ["Projection · target 94.0 kg", "Estimated Wed 8 Oct at this rate", "3.2 kg to go · about 32 weeks"], estimate: true,
        logPrimary: false, history: "9 weigh-ins", phaseLink: "Fixture cut",
        card: ["97.2", "Change nothing"], cardDimmed: false)

    static let week12 = ScorecardFrame(
        digest: "v holdSteady noChangeRuleFired - - o[] u[liftsHoldingWaistShrinking,liftsDropping] | r unknown:liftSignalUnknown:0:1 unknown:missedWeighIn:0:3 notFired:-:0:3 | w met shrinking 96.000 96.500 2031-03-17 -0.500 | l unknown noSessionsThisWeek 0 0 0 0 2031-03-19 2031-03-25 | p unknown noProteinData 0 0 | b met withinBand 0.529 | rate 0.510 0.529 4 2031-02-24 2031-03-24 | pj projected 2031-04-12 1.200 | cur 95.200 2031-03-26 J 2031-03-24",
        phase: ["Phase · week 12", "Fixture cut", "Target 94.0 kg · started Mon 6 Jan · band 0.40–1.20% per week"],
        due: nil,
        reached: nil,
        header: "Verdict · week of 24 Mar", summary: "2 of 4 signals met",
        title: "Change nothing", withheld: false,
        lines: ["None of your change rules fired."],
        couldNotCheck: ["Could not check: lifts holding and waist shrinking", "Could not check: lifts dropping"], ownRule: false,
        rules: [["Lifts holding and waist shrinking", "Could not check", "lifts not known"],
                ["Lifts dropping", "Could not check", "0 of 3 weeks · a week has no weigh-in"],
                ["Slow loss", "Not fired", "0 of 3 weeks"]],
        signals: [["Waist", "Met", "Down 0.5 cm in 1 week", "96.0 cm now · 96.5 cm in the week of 17 Mar"],
                  ["Working weights", "Unknown", "Not known: no sessions in these days", "19 Mar – 25 Mar"],
                  ["Protein floor", "Unknown", "No protein data", "Floor 100 g"],
                  ["Rate of loss", "Met", "0.51 kg per week, 0.53% of bodyweight", "band 0.40–1.20%"]],
        weight: ["95.2", "Weighed Wed 26 Mar · Lab Book", "100.0,99.2,98.4,97.6,97.5,97.4,97.3,97.2,97.1,x,96.0,95.2", "6 Jan", "24 Mar", "Rate of loss", "0.51", "0.53", "Line fitted to 4 weekly points, weeks of 24 Feb – 24 Mar"],
        waist: ["96.0", "Measured Wed 26 Mar · Lab Book", "100.0,99.5,99.0,98.5,98.0,97.5,97.0,97.0,97.0,x,96.5,96.0", "Since the week of 17 Mar", "−0.5", "Since the week of 6 Jan", "−4.0"],
        projection: ["Projection · target 94.0 kg", "Estimated Sat 12 Apr at this rate", "1.2 kg to go · about 2 weeks"], estimate: true,
        logPrimary: false, history: "12 weigh-ins", phaseLink: "Fixture cut",
        card: ["95.2", "Change nothing"], cardDimmed: false)

    static let week22 = ScorecardFrame(
        digest: "v holdSteady ruleFired liftsHoldingWaistShrinking - o[] u[] | r fired:-:1:1 notFired:-:0:3 notFired:-:0:3 | w met shrinking 93.500 94.500 2031-05-19 -1.000 | l met holding 2 0 1 1 2031-05-28 2031-06-03 | p unknown noProteinData 0 0 | b notMet belowBand 0.286 | rate 0.270 0.286 5 2031-05-05 2031-06-02 | pj targetReached - -0.500 | cur 93.500 2031-06-04 J 2031-06-02",
        phase: ["Phase · week 22", "Fixture cut", "Target 94.0 kg · started Mon 6 Jan · band 0.40–1.20% per week"],
        due: nil,
        reached: ["Target reached", "93.5 kg on Wed 4 Jun · target 94.0 kg"],
        header: "Verdict · week of 2 Jun", summary: "2 of 4 signals met",
        title: "Change nothing", withheld: false,
        lines: ["Lifts are holding and your waist is shrinking."],
        couldNotCheck: [], ownRule: false,
        rules: [["Lifts holding and waist shrinking", "Fired", ""],
                ["Lifts dropping", "Not fired", "0 of 3 weeks"],
                ["Slow loss", "Not fired", "0 of 3 weeks"]],
        signals: [["Waist", "Met", "Down 1.0 cm in 2 weeks", "93.5 cm now · 94.5 cm in the week of 19 May"],
                  ["Working weights", "Met", "Holding or climbing", "1 climbed, 1 held, 0 dropped of 2 exercises · 28 May – 3 Jun"],
                  ["Protein floor", "Unknown", "No protein data", "Floor 100 g"],
                  ["Rate of loss", "Not met", "Below your band", "0.27 kg per week, 0.29% of bodyweight · band 0.40–1.20%"]],
        weight: ["93.5", "Weighed Wed 4 Jun · Lab Book", "100.0,99.2,98.4,97.6,97.5,97.4,97.3,97.2,97.1,x,96.0,95.2,95.1,95.0,94.9,94.8,94.7,94.6,94.5,95.5,94.0,93.5", "6 Jan", "2 Jun", "Rate of loss", "0.27", "0.29", "Line fitted to 5 weekly points, weeks of 5 May – 2 Jun"],
        waist: ["93.5", "Measured Wed 4 Jun · Lab Book", "100.0,99.5,99.0,98.5,98.0,97.5,97.0,97.0,97.0,x,96.5,96.0,95.5,95.0,94.5,94.5,94.5,94.5,94.5,94.5,94.0,93.5", "Since the week of 19 May", "−1.0", "Since the week of 6 Jan", "−6.5"],
        projection: ["Projection · target 94.0 kg", "Target reached", ""], estimate: false,
        logPrimary: false, history: "22 weigh-ins", phaseLink: "Fixture cut",
        card: ["93.5", "Target reached"], cardDimmed: false)

    static let week9Imperial = ScorecardFrame(
        digest: "v reduceCarbs ruleFired slowLoss -250.000 o[] u[] | r notFired:-:0:1 notFired:-:0:3 fired:-:5:3 | w notMet notShrinking 97.000 97.000 2031-02-17 0.000 | l met holding 2 0 0 2 2031-02-26 2031-03-04 | p unknown noProteinData 0 0 | b notMet belowBand 0.103 | rate 0.100 0.103 5 2031-02-03 2031-03-03 | pj projected 2031-10-08 3.100 | cur 97.100 2031-03-05 J 2031-03-03",
        phase: ["Phase · week 9", "Fixture cut", "Target 207.2 lb · started Mon 6 Jan · band 0.40–1.20% per week"],
        due: nil,
        reached: nil,
        header: "Verdict · week of 3 Mar", summary: "1 of 4 signals met",
        title: "Your rule: take 250 kcal from carbohydrate", withheld: false,
        lines: ["Loss was under 0.9 lb per week for 5 weeks."],
        couldNotCheck: [], ownRule: true,
        rules: [["Lifts holding and waist shrinking", "Not fired", ""],
                ["Lifts dropping", "Not fired", "0 of 3 weeks"],
                ["Slow loss", "Fired", "3 of 3 weeks"]],
        signals: [["Waist", "Not met", "Not shrinking", "38.2 in now · 38.2 in in the week of 17 Feb"],
                  ["Working weights", "Met", "Holding or climbing", "0 climbed, 2 held, 0 dropped of 2 exercises · 26 Feb – 4 Mar"],
                  ["Protein floor", "Unknown", "No protein data", "Floor 100 g"],
                  ["Rate of loss", "Not met", "Below your band", "0.22 lb per week, 0.10% of bodyweight · band 0.40–1.20%"]],
        weight: ["214.1", "Weighed Wed 5 Mar · Lab Book", "220.5,218.7,216.9,215.2,215.0,214.7,214.5,214.3,214.1", "6 Jan", "3 Mar", "Rate of loss", "0.22", "0.10", "Line fitted to 5 weekly points, weeks of 3 Feb – 3 Mar"],
        waist: ["38.2", "Measured Wed 5 Mar · Lab Book", "39.4,39.2,39.0,38.8,38.6,38.4,38.2,38.2,38.2", "Since the week of 17 Feb", "0.0", "Since the week of 6 Jan", "−1.2"],
        projection: ["Projection · target 207.2 lb", "Estimated Wed 8 Oct at this rate", "6.8 lb to go · about 31 weeks"], estimate: true,
        logPrimary: false, history: "10 weigh-ins", phaseLink: "Fixture cut",
        card: ["214.1", "Your rule: take 250 kcal from carbohydrate"], cardDimmed: false)

    static let week20Imperial = ScorecardFrame(
        digest: "v reduceCarbs ruleFired slowLoss -250.000 o[] u[] | r notFired:-:0:1 notFired:-:0:3 fired:-:8:3 | w notMet notShrinking 94.500 94.500 2031-05-05 0.000 | l met holding 2 0 0 2 2031-05-14 2031-05-20 | p unknown noProteinData 0 0 | b notMet belowBand -0.127 | rate -0.120 -0.127 5 2031-04-21 2031-05-19 | pj notLosing - 1.500 | cur 95.500 2031-05-21 J 2031-05-19",
        phase: ["Phase · week 20", "Fixture cut", "Target 207.2 lb · started Mon 6 Jan · band 0.40–1.20% per week"],
        due: nil,
        reached: nil,
        header: "Verdict · week of 19 May", summary: "1 of 4 signals met",
        title: "Your rule: take 250 kcal from carbohydrate", withheld: false,
        lines: ["Loss was under 0.9 lb per week for 8 weeks."],
        couldNotCheck: [], ownRule: true,
        rules: [["Lifts holding and waist shrinking", "Not fired", ""],
                ["Lifts dropping", "Not fired", "0 of 3 weeks"],
                ["Slow loss", "Fired", "3 of 3 weeks"]],
        signals: [["Waist", "Not met", "Not shrinking", "37.2 in now · 37.2 in in the week of 5 May"],
                  ["Working weights", "Met", "Holding or climbing", "0 climbed, 2 held, 0 dropped of 2 exercises · 14 May – 20 May"],
                  ["Protein floor", "Unknown", "No protein data", "Floor 100 g"],
                  ["Rate of loss", "Not met", "Below your band", "Gaining 0.26 lb per week, 0.13% of bodyweight · band 0.40–1.20%"]],
        weight: ["210.5", "Weighed Wed 21 May · Lab Book", "220.5,218.7,216.9,215.2,215.0,214.7,214.5,214.3,214.1,x,211.6,209.9,209.7,209.4,209.2,209.0,208.8,208.6,208.3,210.5", "6 Jan", "19 May", "Rate of gain", "0.26", "0.13", "Line fitted to 5 weekly points, weeks of 21 Apr – 19 May"],
        waist: ["37.2", "Measured Wed 21 May · Lab Book", "39.4,39.2,39.0,38.8,38.6,38.4,38.2,38.2,38.2,x,38.0,37.8,37.6,37.4,37.2,37.2,37.2,37.2,37.2,37.2", "Since the week of 5 May", "0.0", "Since the week of 6 Jan", "−2.2"],
        projection: ["Projection · target 207.2 lb", "No date while weight is not falling", "3.3 lb to go"], estimate: false,
        logPrimary: false, history: "20 weigh-ins", phaseLink: "Fixture cut",
        card: ["210.5", "Your rule: take 250 kcal from carbohydrate"], cardDimmed: false)
}
