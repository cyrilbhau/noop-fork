import Foundation
import StrandAnalytics
import StrandImport
import WhoopStore

// Stage 1 (weigh-in and scorecard), specification §10 and §11: the wording of every scorecard
// surface. `CutScorecard.evaluate` returns enum cases and numbers; this file is the one place they
// become strings, so the Today card, the Health row, the scorecard screen, the history list and the
// Settings rows cannot word one fact two ways.
//
// Pure: no store, no defaults, no clock. Every string goes through the String Catalog. A missing
// value is nil, never "0" and never an empty string. A sentence that carries a count has a singular
// and a plural source string, since the catalogue is edited by another work package.

/// The one state a scorecard surface is in. First match wins, in the order of the cases after
/// `pastDay`. `loading` and `pastDay` belong to the Today card only.
enum CutScorecardStatus: Equatable {
    case loading, pastDay
    /// The stored rules failed validation, or the result itself is marked invalid.
    case rulesNeedAttention
    case noCutPhase
    case phaseNotStarted
    case noReadings
    case overdue
    /// A started phase whose judged week is before this week, and not yet overdue.
    case due
    /// Exactly one week of the phase has a weight.
    case oneReading
    case targetReached
    case verdictWithheld
    /// No rule can be evaluated yet, with more than one weigh-in logged.
    case building
    case verdict
}

/// The Today card (specification §10.1).
struct CutScorecardCard: Equatable {
    var status: CutScorecardStatus
    var title: String
    /// Nil draws the dash. Never "0" for a missing weight.
    var value: String?
    /// "kg" or "lb"; nil when `value` is nil.
    var unit: String?
    /// Nil only while loading.
    var caption: String?
    /// The value in the tertiary colour (an overdue weigh-in).
    var isDimmed: Bool
    /// False while loading and for a past day.
    var opensScorecard: Bool
}

/// Everything the scorecard screen draws (specification §10.2), already worded.
struct CutScorecardPresentation: Equatable {
    struct PhaseHeader: Equatable {
        var label: String
        var name: String
        var detail: String
    }

    struct Banner: Equatable {
        var title: String
        var detail: String
    }

    enum VerdictAction: Equatable { case setUpPhase, openPhaseAndRules }

    struct Verdict: Equatable {
        /// "Verdict · week of 27 Jan", or "Verdict".
        var header: String
        /// "4 of 4 signals met"; nil when every signal is unknown.
        var signalsSummary: String?
        var title: String
        /// No verdict is given: drawn in the neutral style.
        var isWithheld: Bool
        var lines: [String]
        var couldNotCheck: [String]
        /// Only under an add-calories or reduce-carbohydrate verdict.
        var ownRuleNote: String?
        /// Only with no cut phase and when the rules need attention.
        var explanation: String?
        var action: VerdictAction?
        var actionTitle: String?
    }

    struct RuleRow: Equatable {
        var rule: CutScorecardRule
        var name: String
        var state: CutScorecardRuleState
        var stateWord: String
        var detail: String?
    }

    struct SignalRow: Equatable {
        var title: String
        var state: CutScorecardSignalState
        var stateWord: String
        var reason: String
        var detail: String?
    }

    struct Fact: Equatable {
        var label: String
        var value: String?
        var unit: String?
    }

    struct Curve: Equatable {
        var title: String
        var value: String
        var unit: String
        var provenance: String
        /// One per week shown, in the display unit. Nil is a week with no reading: the line breaks.
        var points: [Double?]
        var firstLabel: String
        var lastLabel: String
        var facts: [Fact]
        var note: String?
    }

    struct Projection: Equatable {
        var label: String
        var isEstimate: Bool
        /// "Estimate", exactly when `isEstimate`.
        var estimateLabel: String?
        var text: String
        var detail: String?
    }

    var status: CutScorecardStatus
    /// "week of 27 Jan": the week the verdict and the four signals are about. Nil with no started
    /// phase or no judged week.
    var weekLabel: String? = nil
    var phase: PhaseHeader?
    var dueBanner: Banner?
    var targetBanner: Banner?
    var verdict: Verdict
    /// Empty when the rule rows are hidden.
    var rules: [RuleRow]
    /// Always four: waist, lifts, protein, rate.
    var signals: [SignalRow]
    var liftFootnote: String
    var weight: Curve?
    var waist: Curve?
    /// Set exactly when `weight` is nil.
    var emptyCurvesText: String?
    var projection: Projection
    var logWeighInIsPrimary: Bool
    var historyValue: String
    var phaseLinkValue: String
    var card: CutScorecardCard
}

/// What the presenter needs beyond the result and its input.
struct CutScorecardPresentationContext {
    /// `.metric`: kg and cm. `.imperial`: lb and in.
    var unitSystem: UnitSystem
    /// Where `result.currentWeightKg` came from.
    var weightSource: BodyMeasurementSource
    /// `CutScorecardSettings.rulesNeedAttention`.
    var rulesNeedAttention: Bool
    var locale: Locale
    /// The name of the stored phase the "Phase and rules" link names when the evaluation has no
    /// phase of its own: an active phase of another kind. Nil: none.
    var storedPhaseName: String?

    init(unitSystem: UnitSystem = .metric, weightSource: BodyMeasurementSource = .labBook,
         rulesNeedAttention: Bool = false, locale: Locale = AppLanguage.activeLocale,
         storedPhaseName: String? = nil) {
        self.unitSystem = unitSystem
        self.weightSource = weightSource
        self.rulesNeedAttention = rulesNeedAttention
        self.locale = locale
        self.storedPhaseName = storedPhaseName
    }
}

/// The reminder row's state in Settings (specification §10.6).
enum WeighInReminderStatus: Equatable { case off, on, denied }

/// The Settings rows for the feature switch and the weekly reminder.
struct CutScorecardSettingsPresentation: Equatable {
    var toggleTitle: String
    /// Nil while the flag is off: the row is not shown.
    var reminderTitle: String?
    var reminderIsOn: Bool
    var day: String?
    var time: String?
    var footnote: String?
    var previewTitle: String?
    var previewBody: String?
    var deniedTitle: String?
    var deniedDetail: String?
    var deniedActionTitle: String?
}

/// One row of the weigh-in history (specification §10.4).
struct WeighInHistoryRow: Equatable, Identifiable {
    var id: String
    var day: String
    /// Nil for an Apple Health day, which has no instant.
    var takenAt: Int?
    var dateText: String
    var weightText: String?
    /// Nil is drawn as `WeighInHistory.notMeasuredText`.
    var waistText: String?
    var source: BodyMeasurementSource
    var caption: String
    var representsWeek: Bool
    var canEdit: Bool
    var canDelete: Bool
    /// The stored rows an edit or a delete acts on.
    var weightRow: LabMarkerRow?
    var waistRow: LabMarkerRow?
}

/// The weigh-in history list, newest first.
struct WeighInHistory: Equatable {
    var rows: [WeighInHistoryRow]
    var weightUnit: String
    var waistUnit: String
    var notMeasuredText: String
    /// Set exactly when `rows` is empty.
    var emptyText: String?
    /// What the dot means; nil when `rows` is empty.
    var legend: String?
    /// Weight and waist rows in a unit that is not recognised.
    var unlistedCount: Int
    /// Nil when `unlistedCount` is 0.
    var unlistedNote: String?
}

/// The one question asked before a weigh-in is deleted.
struct WeighInDeleteConfirmation: Equatable {
    var title: String
    var detail: String
    var confirmTitle: String
    var cancelTitle: String
}

enum CutScorecardPresenter {

    // MARK: - Scorecard screen and card

    /// The scorecard screen and its Today card for one evaluation. `input` is the input `result`
    /// was evaluated from.
    static func present(_ result: CutScorecardResult, input: CutScorecardInput,
                        context: CutScorecardPresentationContext) -> CutScorecardPresentation {
        let words = Wording(unitSystem: context.unitSystem, locale: context.locale)
        let invalid = context.rulesNeedAttention || result.invalidInput != nil
        let parameters = input.parameters
        let phase = input.phase
        let today = input.today
        let judged = result.judgedWeekStart
        let reason = result.verdict.reason
        // A phase whose start day or today cannot be read is an invalid input: nothing is "started".
        let started = result.invalidInput == nil && phase.map { today >= $0.startDay } ?? false
        func evaluation(_ rule: CutScorecardRule) -> CutScorecardRuleEvaluation? {
            result.rules.first { $0.rule == rule }
        }

        // The weeks the curves show: the phase's weeks once it has started, else every week.
        let domainStart = started ? phase.flatMap { CutScorecard.weekStart(containing: $0.startDay) } : nil
        let weeks = result.weeks.filter { week in domainStart.map { week.weekStart >= $0 } ?? true }
        let judgedWeek = judged.flatMap { key in result.weeks.first { $0.weekStart == key } }
        let weeksWithWeight = weeks.filter { $0.weightKg != nil }.count
        let weekOfJudged = started ? judged.map { String(localized: "week of \(words.shortDate($0))") } : nil

        // Phase header.
        var header: CutScorecardPresentation.PhaseHeader?
        if let phase, result.invalidInput != .phase {
            let label = started
                ? String(localized: "Phase · week \((words.weeksBetween(phase.startDay, today) ?? 0) + 1)")
                : String(localized: "Phase · not started")
            let target = phase.targetWeightKg.map { String(localized: "Target \(words.weight($0))") }
                ?? String(localized: "No target set")
            let start = started ? String(localized: "started \(words.date(phase.startDay))")
                : String(localized: "starts \(words.date(phase.startDay))")
            let band = String(localized: "band \(words.band(phase.rateLowPercentPerWeek, phase.rateHighPercentPerWeek))% per week")
            header = .init(label: label, name: phase.name, detail: [target, start, band].joined(separator: " · "))
        }

        // Verdict.
        let lastWeighIn = String(localized: "Last weigh-in \(words.date(result.currentWeightDay ?? today))")
        var title: String
        var lines: [String] = []
        var couldNotCheck = result.verdict.unevaluatedRules.map(couldNotCheckText)
        var isWithheld = result.verdict.kind == .insufficientData
        var isAdvice = false
        if invalid {
            title = String(localized: "Your rules need attention")
            isWithheld = true
            couldNotCheck = []
        } else if reason == .ruleFired, result.verdict.kind == .holdSteady {
            title = String(localized: "Change nothing")
            lines.append(String(localized: "Lifts are holding and your waist is shrinking."))
            if !result.verdict.overriddenRules.isEmpty {
                let run = evaluation(.slowLoss)?.consecutiveWeeks ?? 0
                lines.append(run == 1
                    ? String(localized: "The scale was slow for \(run) week. That is expected when waist and lifts are on track.")
                    : String(localized: "The scale was slow for \(run) weeks. That is expected when waist and lifts are on track."))
            }
        } else if reason == .noChangeRuleFired {
            title = String(localized: "Change nothing")
            lines.append(String(localized: "None of your change rules fired."))
        } else if result.verdict.kind == .addCalories {
            title = String(localized: "Your rule: add \(result.verdict.calorieChangeKcal ?? parameters.addCaloriesKcal) kcal")
            isAdvice = true
            let run = evaluation(.liftsDropping)?.consecutiveWeeks ?? 0
            lines.append(run == 1 ? String(localized: "Working weights dropped \(run) week running.")
                : String(localized: "Working weights dropped \(run) weeks running."))
            if !result.verdict.overriddenRules.isEmpty {
                lines.append(String(localized: "The scale was also slow. Your lifts rule comes first."))
            }
        } else if result.verdict.kind == .reduceCarbs {
            let amount = result.verdict.calorieChangeKcal.map { -$0 } ?? parameters.reduceCarbsKcal
            title = String(localized: "Your rule: take \(amount) kcal from carbohydrate")
            isAdvice = true
            let run = evaluation(.slowLoss)?.consecutiveWeeks ?? 0
            let threshold = words.threshold(parameters.slowLossThresholdKgPerWeek)
            lines.append(run == 1 ? String(localized: "Loss was under \(threshold) per week for \(run) week.")
                : String(localized: "Loss was under \(threshold) per week for \(run) weeks."))
        } else if reason == .recompositionCheckIncomplete {
            title = String(localized: "No verdict this week")
            lines.append(String(localized: "The scale was slow, but lifts are not known, so a good week cannot be told from a stall."))
        } else {
            switch reason {
            case .noReadings: title = String(localized: "Log a weigh-in to begin")
            case .noActivePhase: title = String(localized: "No cut phase is active")
            case .phaseNotStarted: title = String(localized: "Your phase starts \(words.date(phase?.startDay ?? today))")
            case .weighInOverdue: title = lastWeighIn
            default: title = String(localized: "Not enough to judge yet")
            }
        }

        // Signals.
        let signals = signalRows(result, parameters: parameters, words: words)
        let met = signals.filter { $0.state == .met }.count
        let known = signals.filter { $0.state != .unknown }.count
        var verdict = CutScorecardPresentation.Verdict(
            header: weekOfJudged.map { String(localized: "Verdict · \($0)") } ?? String(localized: "Verdict"),
            signalsSummary: known > 0 ? String(localized: "\(met) of 4 signals met") : nil,
            title: title, isWithheld: isWithheld, lines: lines, couldNotCheck: couldNotCheck,
            ownRuleNote: isAdvice
                ? String(localized: "This is your own rule applied to your own numbers. Nothing has been changed.") : nil,
            explanation: nil, action: nil, actionTitle: nil)
        if invalid {
            verdict.explanation = String(localized: "A stored rule value is not valid, so no verdict is shown. Your weigh-ins are unaffected.")
            verdict.action = .openPhaseAndRules
            verdict.actionTitle = String(localized: "Open phase and rules")
        } else if phase == nil {
            verdict.explanation = String(localized: "Verdicts are given during a cut phase. Your weigh-ins and curves are kept either way.")
            verdict.action = .setUpPhase
            verdict.actionTitle = String(localized: "Set up phase")
        }

        // Rule rows: hidden with no started phase and when the rules need attention.
        let rules: [CutScorecardPresentation.RuleRow] = started && !invalid ? result.rules.map { rule in
            var parts: [String] = []
            if rule.requiredWeeks > 1 {
                parts.append(String(localized: "\(min(rule.consecutiveWeeks, rule.requiredWeeks)) of \(rule.requiredWeeks) weeks"))
            }
            if rule.state == .unknown, let why = rule.unknownReason { parts.append(ruleUnknownText(why)) }
            return .init(rule: rule.rule, name: ruleName(rule.rule), state: rule.state,
                         stateWord: ruleStateWord(rule.state),
                         detail: parts.isEmpty ? nil : parts.joined(separator: " · "))
        } : []

        // Curves.
        let rateReason = signals.count == 4 ? signals[3].reason : String(localized: "Not measured yet")
        var weightCurve: CutScorecardPresentation.Curve?
        if let current = result.currentWeightKg, let first = weeks.first, let last = weeks.last {
            let gaining = (result.rate?.lossKgPerWeek ?? 0) < 0
            let rate = result.rate
            weightCurve = .init(
                title: String(localized: "Weight"), value: words.weightNumber(current), unit: words.weightUnit,
                provenance: provenance(String(localized: "Weighed \(words.date(result.currentWeightDay ?? today))"),
                                       source: context.weightSource),
                points: weeks.map { $0.weightKg.map(words.weightValue) },
                firstLabel: words.shortDate(first.weekStart), lastLabel: words.shortDate(last.weekStart),
                facts: [
                    .init(label: gaining ? String(localized: "Rate of gain") : String(localized: "Rate of loss"),
                          value: rate.map { words.rateNumber(abs($0.lossKgPerWeek)) },
                          unit: rate == nil ? nil : String(localized: "\(words.weightUnit)/week")),
                    .init(label: String(localized: "Of bodyweight"),
                          value: rate.map { words.fixed(abs($0.percentPerWeek), 2) },
                          unit: rate == nil ? nil : String(localized: "%/week")),
                ],
                note: rate.map {
                    String(localized: "Line fitted to \($0.pointsUsed) weekly points, weeks of \(words.shortDate($0.firstWeekStart)) – \(words.shortDate($0.lastWeekStart))")
                } ?? rateReason)
        }
        var waistCurve: CutScorecardPresentation.Curve?
        let waistWeeks = weeks.filter { $0.waistCm != nil }
        if let lastWaist = waistWeeks.last, let firstWaist = waistWeeks.first, let latest = lastWaist.waistCm,
           let first = weeks.first, let last = weeks.last {
            let signal = result.signals.waist
            var recent = CutScorecardPresentation.Fact(label: String(localized: "Change"), value: nil, unit: nil)
            if let change = signal.changeCm, let reference = signal.referenceWeekStart {
                recent = .init(label: String(localized: "Since the week of \(words.shortDate(reference))"),
                               value: words.signedLength(change), unit: words.lengthUnit)
            }
            var whole = CutScorecardPresentation.Fact(label: String(localized: "Since the first reading"),
                                                      value: nil, unit: nil)
            if firstWaist.weekStart != lastWaist.weekStart, let earliest = firstWaist.waistCm {
                whole = .init(label: String(localized: "Since the week of \(words.shortDate(firstWaist.weekStart))"),
                              value: words.signedLength(latest - earliest), unit: words.lengthUnit)
            }
            waistCurve = .init(
                title: String(localized: "Waist"), value: words.lengthNumber(latest), unit: words.lengthUnit,
                provenance: provenance(String(localized: "Measured \(words.date(lastWaist.waistDay ?? lastWaist.weekStart))"),
                                       source: .labBook),
                points: weeks.map { $0.waistCm.map(words.lengthValue) },
                firstLabel: words.shortDate(first.weekStart), lastLabel: words.shortDate(last.weekStart),
                facts: [recent, whole], note: nil)
        }

        // Projection.
        let target = result.invalidInput == .phase ? nil : phase?.targetWeightKg.map(words.weight)
        let projected = result.projection.status == .projected
        let projectionText: String
        if result.invalidInput != nil {
            projectionText = title
        } else {
            switch result.projection.status {
            case .projected:
                projectionText = String(localized: "Estimated \(words.date(result.projection.targetDay ?? today)) at this rate")
            case .targetReached: projectionText = String(localized: "Target reached")
            case .noTarget: projectionText = String(localized: "No target set")
            case .notLosing: projectionText = String(localized: "No date while weight is not falling")
            case .beyondHorizon:
                projectionText = parameters.maxProjectionWeeks == 1
                    ? String(localized: "More than \(parameters.maxProjectionWeeks) week at this rate")
                    : String(localized: "More than \(parameters.maxProjectionWeeks) weeks at this rate")
            case .needsNewWeighIn: projectionText = String(localized: "Log a weigh-in to check the target")
            case .noActivePhase: projectionText = String(localized: "No cut phase is active")
            case .weighInOverdue: projectionText = lastWeighIn
            case .rateUnknown:
                projectionText = rateUnavailableText(result.rateUnavailable, parameters: parameters)
            }
        }
        var projectionDetail: String?
        if let remaining = result.projection.remainingKg, remaining > 0, result.rate != nil,
           result.projection.status != .needsNewWeighIn {
            let toGo = words.weight(remaining)
            if projected, let weeksLeft = result.projection.weeksRemaining {
                let count = max(1, Int(weeksLeft.rounded()))
                projectionDetail = count == 1 ? String(localized: "\(toGo) to go · about \(count) week")
                    : String(localized: "\(toGo) to go · about \(count) weeks")
            } else {
                projectionDetail = String(localized: "\(toGo) to go")
            }
        }
        let projection = CutScorecardPresentation.Projection(
            label: target.map { String(localized: "Projection · target \($0)") } ?? String(localized: "Projection"),
            isEstimate: projected, estimateLabel: projected ? String(localized: "Estimate") : nil,
            text: projectionText, detail: projectionDetail)

        // Banners.
        let isDue = started && reason != .weighInOverdue
            && (judged.flatMap { words.weeksBetween($0, today) } ?? 0) >= 1
        var dueBanner: CutScorecardPresentation.Banner?
        if isDue, let weekOfJudged {
            dueBanner = .init(title: String(localized: "Weigh-in due this week"),
                              detail: String(localized: "The verdict below is from the \(weekOfJudged)."))
        }
        var targetBanner: CutScorecardPresentation.Banner?
        if result.projection.status == .targetReached, let target,
           let weight = judgedWeek?.weightKg ?? result.currentWeightKg {
            let day = judgedWeek?.weightDay ?? result.currentWeightDay ?? today
            targetBanner = .init(title: String(localized: "Target reached"),
                                 detail: String(localized: "\(words.weight(weight)) on \(words.date(day)) · target \(target)"))
        }

        // Status, in its order of precedence.
        let status: CutScorecardStatus
        if invalid { status = .rulesNeedAttention }
        else if reason == .noActivePhase { status = .noCutPhase }
        else if reason == .phaseNotStarted { status = .phaseNotStarted }
        else if reason == .noReadings { status = .noReadings }
        else if reason == .weighInOverdue { status = .overdue }
        else if isDue { status = .due }
        else if weeksWithWeight == 1 { status = .oneReading }
        else if result.projection.status == .targetReached { status = .targetReached }
        else if reason == .recompositionCheckIncomplete { status = .verdictWithheld }
        else if reason == .noRuleEvaluable { status = .building }
        else { status = .verdict }

        // The Today card: the current weight and one caption.
        let value = result.currentWeightKg.map(words.weightNumber)
        let caption: String
        var cardValue = value
        switch status {
        case .rulesNeedAttention, .phaseNotStarted, .overdue, .verdict: caption = title
        case .noCutPhase:
            caption = String(localized: "Set up your phase")
            cardValue = nil
        case .noReadings: caption = String(localized: "Log your first weigh-in")
        case .due: caption = String(localized: "Weigh-in due this week")
        case .oneReading: caption = String(localized: "First weigh-in logged")
        case .targetReached: caption = String(localized: "Target reached")
        case .verdictWithheld: caption = String(localized: "Lifts not known this week")
        case .building:
            let slow = evaluation(.slowLoss)
            caption = String(localized: "Building: \(min(slow?.consecutiveWeeks ?? 0, slow?.requiredWeeks ?? 0)) of \(slow?.requiredWeeks ?? 0) weeks")
        case .loading, .pastDay: caption = title
        }
        if status == .phaseNotStarted { cardValue = nil }
        let card = CutScorecardCard(status: status, title: cardTitle, value: cardValue,
                                    unit: cardValue == nil ? nil : words.weightUnit, caption: caption,
                                    isDimmed: status == .overdue, opensScorecard: true)

        let logged = input.weights.filter { $0.day <= today }.count
        return CutScorecardPresentation(
            status: status, weekLabel: weekOfJudged, phase: header, dueBanner: dueBanner, targetBanner: targetBanner, verdict: verdict,
            rules: rules, signals: signals,
            liftFootnote: String(localized: "Compares the heaviest working set of each exercise with the week before."),
            weight: weightCurve, waist: waistCurve,
            emptyCurvesText: weightCurve == nil ? String(localized: "Not measured yet") : nil,
            projection: projection,
            logWeighInIsPrimary: isDue || weightCurve == nil || reason == .weighInOverdue,
            historyValue: logged == 1 ? String(localized: "\(logged) weigh-in") : String(localized: "\(logged) weigh-ins"),
            phaseLinkValue: header?.name ?? context.storedPhaseName ?? String(localized: "Not set up"),
            card: card)
    }

    /// The card while its first load is in flight: a skeleton, no number and no caption.
    static func loadingCard() -> CutScorecardCard {
        CutScorecardCard(status: .loading, title: cardTitle, value: nil, unit: nil, caption: nil,
                         isDimmed: false, opensScorecard: false)
    }

    /// The card when Today shows a past day: the scorecard is about this week only.
    static func pastDayCard() -> CutScorecardCard {
        CutScorecardCard(status: .pastDay, title: cardTitle, value: nil, unit: nil,
                         caption: String(localized: "Shown for today only"), isDimmed: false,
                         opensScorecard: false)
    }

    /// The name a resolved value's source is shown under (specification §11).
    static func sourceCaption(_ source: BodyMeasurementSource) -> String {
        switch source {
        case .labBook: return String(localized: "Lab Book")
        case .appleHealth: return "Apple Health"
        case .profile, .profileDefault: return String(localized: "from profile")
        }
    }

    /// The card's title, shared with `TodayCardResolver.cardTitle`.
    static var cardTitle: String { String(localized: "Scorecard") }

    /// The one line the Health tab's row shows beside "Scorecard": the card's caption and weight.
    static func rowValue(_ card: CutScorecardCard) -> String? {
        let weight = card.value.map { [$0, card.unit].compactMap { $0 }.joined(separator: " ") }
        let parts = [card.caption, weight].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Signals

    private static func signalRows(_ result: CutScorecardResult, parameters: CutScorecardParameters,
                                   words: Wording) -> [CutScorecardPresentation.SignalRow] {
        let overdue = String(localized: "No current weigh-in")
        let unmeasured = String(localized: "Not measured yet")

        // Waist.
        let waist = result.signals.waist
        let waistReason: String
        switch waist.reason {
        case .weighInOverdue: waistReason = overdue
        case .noReadings: waistReason = unmeasured
        case .shrinking:
            let down = words.length(-(waist.changeCm ?? 0))
            let span = both(waist.referenceWeekStart, result.judgedWeekStart).flatMap { words.weeksBetween($0, $1) } ?? 0
            waistReason = span == 1 ? String(localized: "Down \(down) in \(span) week")
                : String(localized: "Down \(down) in \(span) weeks")
        case .notShrinking: waistReason = String(localized: "Not shrinking")
        case .noWaistThisWeek: waistReason = String(localized: "Not measured this week")
        case .noEarlierWaist: waistReason = String(localized: "Needs an earlier reading")
        }
        var waistDetail: String?
        if let current = waist.currentCm {
            if let reference = waist.referenceCm, let week = waist.referenceWeekStart {
                waistDetail = String(localized: "\(words.length(current)) now · \(words.length(reference)) in the week of \(words.shortDate(week))")
            } else {
                waistDetail = String(localized: "\(words.length(current)) now")
            }
        }

        // Working weights.
        let lifts = result.signals.lifts
        let liftReason: String
        switch lifts.reason {
        case .weighInOverdue: liftReason = overdue
        case .noReadings: liftReason = unmeasured
        case .holding: liftReason = String(localized: "Holding or climbing")
        case .dropping: liftReason = String(localized: "Dropping")
        case .noLiftData: liftReason = String(localized: "Not known: no imported sessions")
        case .noSessionsThisWeek: liftReason = String(localized: "Not known: no sessions in these days")
        case .noSessionsPriorWeek: liftReason = String(localized: "Not known: nothing to compare with")
        case .noCommonExercises: liftReason = String(localized: "Not known: no exercise in common")
        }
        // With no lift data at all there are no compared days to name.
        let window = lifts.reason == .noLiftData ? nil : both(lifts.windowStartDay, lifts.windowEndDay).map {
            "\(words.shortDate($0)) – \(words.shortDate($1))"
        }
        var liftDetail = window
        if lifts.commonExercises > 0 {
            let counts = lifts.commonExercises == 1
                ? String(localized: "\(lifts.climbed) climbed, \(lifts.held) held, \(lifts.dropped) dropped of \(lifts.commonExercises) exercise")
                : String(localized: "\(lifts.climbed) climbed, \(lifts.held) held, \(lifts.dropped) dropped of \(lifts.commonExercises) exercises")
            liftDetail = [counts, window].compactMap { $0 }.joined(separator: " · ")
        }

        // Protein floor.
        let protein = result.signals.protein
        let proteinReason: String
        switch protein.reason {
        case .weighInOverdue: proteinReason = overdue
        case .noReadings: proteinReason = unmeasured
        case .floorMet: proteinReason = String(localized: "\(protein.daysAtOrAboveFloor) of 7 days at or above your floor")
        case .floorMissed:
            let below = protein.daysLogged - protein.daysAtOrAboveFloor
            proteinReason = below == 1 ? String(localized: "Below your floor on \(below) day")
                : String(localized: "Below your floor on \(below) days")
        case .noFloorConfigured: proteinReason = String(localized: "No floor set")
        case .noProteinData: proteinReason = String(localized: "No protein data")
        case .incompleteLogging: proteinReason = String(localized: "Not enough days logged")
        }
        var proteinDetail: String?
        if let floor = protein.floorGrams, protein.reason != .noFloorConfigured {
            let grams = words.trimmed(floor, 2)
            if protein.daysLogged > 0 {
                proteinDetail = String(localized: "Floor \(grams) g · \(protein.daysLogged) of 7 days logged, \(protein.daysAtOrAboveFloor) at or above · needs \(protein.requiredDays)")
            } else if protein.reason == .noProteinData {
                proteinDetail = String(localized: "Floor \(grams) g")
            }
        }

        // Rate of loss.
        let band = result.signals.rateBand
        let rateText = result.rate.map { rate -> String in
            let perWeek = "\(words.rateNumber(abs(rate.lossKgPerWeek))) \(words.weightUnit)"
            let percent = words.fixed(abs(rate.percentPerWeek), 2)
            return String(localized: "\(perWeek) per week, \(percent)% of bodyweight")
        }
        // A gain is worded, never signed.
        let directedRateText = rateText.map { text in
            (result.rate?.lossKgPerWeek ?? 0) < 0 ? String(localized: "Gaining \(text)") : text
        }
        let bandReason: String
        switch band.reason {
        case .weighInOverdue: bandReason = overdue
        case .noReadings: bandReason = unmeasured
        case .noActivePhase: bandReason = String(localized: "No cut phase is active")
        case .rateUnknown: bandReason = rateUnavailableText(result.rateUnavailable, parameters: parameters)
        case .withinBand: bandReason = rateText ?? unmeasured
        case .belowBand: bandReason = String(localized: "Below your band")
        case .aboveBand: bandReason = String(localized: "Above your band")
        }
        var bandDetail: String?
        if band.percentPerWeek != nil, let low = band.lowPercentPerWeek, let high = band.highPercentPerWeek {
            let bounds = String(localized: "band \(words.band(low, high))%")
            bandDetail = band.reason == .withinBand ? bounds
                : [directedRateText, bounds].compactMap { $0 }.joined(separator: " · ")
        } else if band.reason == .noActivePhase {
            bandDetail = directedRateText
        }

        return [
            .init(title: String(localized: "Waist"), state: waist.state, stateWord: signalStateWord(waist.state),
                  reason: waistReason, detail: waistDetail),
            .init(title: String(localized: "Working weights"), state: lifts.state,
                  stateWord: signalStateWord(lifts.state), reason: liftReason, detail: liftDetail),
            .init(title: String(localized: "Protein floor"), state: protein.state,
                  stateWord: signalStateWord(protein.state), reason: proteinReason, detail: proteinDetail),
            .init(title: String(localized: "Rate of loss"), state: band.state, stateWord: signalStateWord(band.state),
                  reason: bandReason, detail: bandDetail),
        ]
    }

    private static func rateUnavailableText(_ cause: CutScorecardRateUnavailable?,
                                            parameters: CutScorecardParameters) -> String {
        switch cause {
        case .noReadings?, nil: return String(localized: "Not measured yet")
        case .singleReading?: return String(localized: "Needs a second weigh-in")
        case .weighInOverdue?: return String(localized: "No current weigh-in")
        case .gapLongerThanWindow?:
            return parameters.rateWindowWeeks == 1
                ? String(localized: "Gap longer than \(parameters.rateWindowWeeks) week")
                : String(localized: "Gap longer than \(parameters.rateWindowWeeks) weeks")
        }
    }

    private static func provenance(_ measured: String, source: BodyMeasurementSource) -> String {
        "\(measured) · \(sourceCaption(source))"
    }

    private static func signalStateWord(_ state: CutScorecardSignalState) -> String {
        switch state {
        case .met: return String(localized: "Met")
        case .notMet: return String(localized: "Not met")
        case .unknown: return String(localized: "Unknown")
        }
    }

    private static func ruleStateWord(_ state: CutScorecardRuleState) -> String {
        switch state {
        case .fired: return String(localized: "Fired")
        case .notFired: return String(localized: "Not fired")
        case .unknown: return String(localized: "Could not check")
        }
    }

    private static func ruleName(_ rule: CutScorecardRule) -> String {
        switch rule {
        case .liftsHoldingWaistShrinking: return String(localized: "Lifts holding and waist shrinking")
        case .liftsDropping: return String(localized: "Lifts dropping")
        case .slowLoss: return String(localized: "Slow loss")
        }
    }

    private static func couldNotCheckText(_ rule: CutScorecardRule) -> String {
        switch rule {
        case .liftsHoldingWaistShrinking: return String(localized: "Could not check: lifts holding and waist shrinking")
        case .liftsDropping: return String(localized: "Could not check: lifts dropping")
        case .slowLoss: return String(localized: "Could not check: slow loss")
        }
    }

    private static func ruleUnknownText(_ reason: CutScorecardRuleUnknownReason) -> String {
        switch reason {
        case .liftSignalUnknown: return String(localized: "lifts not known")
        case .waistSignalUnknown: return String(localized: "waist not known")
        case .fewerWeeksThanWindow: return String(localized: "the phase is younger than this rule needs")
        case .missedWeighIn: return String(localized: "a week has no weigh-in")
        case .noActivePhase: return String(localized: "no cut phase is active")
        case .weighInOverdue: return String(localized: "the last weigh-in is too old")
        case .noReadings: return String(localized: "no weigh-ins yet")
        }
    }

    // MARK: - Settings rows

    /// The feature switch and the reminder rows (specification §10.6). `weekday` is 1 = Sunday to
    /// 7 = Saturday; `minuteOfDay` counts from local midnight.
    static func settings(flagEnabled: Bool, reminder: WeighInReminderStatus, weekday: Int,
                         minuteOfDay: Int, locale: Locale) -> CutScorecardSettingsPresentation {
        var shown = CutScorecardSettingsPresentation(
            toggleTitle: String(localized: "Weekly weigh-in and scorecard"), reminderTitle: nil,
            reminderIsOn: false, day: nil, time: nil, footnote: nil, previewTitle: nil, previewBody: nil,
            deniedTitle: nil, deniedDetail: nil, deniedActionTitle: nil)
        guard flagEnabled else { return shown }
        shown.reminderTitle = String(localized: "Weekly reminder")
        switch reminder {
        case .off:
            shown.footnote = String(localized: "The reminder is off unless you turn it on. One notification a week, on the day and at the time you choose.")
        case .on:
            shown.reminderIsOn = true
            shown.day = weekdayName(weekday, locale: locale)
            shown.time = timeText(minuteOfDay: minuteOfDay, locale: locale)
            shown.footnote = String(localized: "One notification a week. It never contains a measurement, a verdict or the phase name.")
            shown.previewTitle = reminderTitle
            shown.previewBody = reminderBody
        case .denied:
            // A reminder that cannot be delivered does not read as on.
            shown.deniedTitle = String(localized: "Notifications are off for NOOP")
            shown.deniedDetail = String(localized: "The reminder cannot be delivered until they are allowed.")
            shown.deniedActionTitle = String(localized: "Open Settings")
        }
        return shown
    }

    /// The notification's title (specification §10.10). The reminder and its Settings preview share it.
    static var reminderTitle: String { String(localized: "Weekly weigh-in") }

    /// The notification's body. No measurement, verdict or phase name ever appears in it.
    static var reminderBody: String { String(localized: "Weight, then waist. It takes under a minute.") }

    /// The full name of a weekday numbered 1 = Sunday to 7 = Saturday.
    static func weekdayName(_ weekday: Int, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        let names = formatter.standaloneWeekdaySymbols ?? []
        let index = min(max(weekday, 1), 7) - 1
        return names.indices.contains(index) ? names[index] : ""
    }

    /// A minute of the day as a clock time in `locale`'s own hour cycle.
    static func timeText(minuteOfDay: Int, locale: Locale) -> String {
        let minute = min(max(minuteOfDay, 0), 24 * 60 - 1)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter.string(from: Date(timeIntervalSince1970: Double(minute * 60)))
    }

    // MARK: - History

    /// The history list. `weights` and `waists` are `WeighInStore.readings(_:)`, the union across
    /// strap ids of ruling R25; `appleHealth` is the provider's Apple Health weight per day.
    static func history(weights: [LabMarkerRow], waists: [LabMarkerRow],
                        appleHealth: [(day: String, value: Double)],
                        unitSystem: UnitSystem, locale: Locale) -> WeighInHistory {
        let words = Wording(unitSystem: unitSystem, locale: locale)
        var unlisted = 0
        var entries: [HistoryEntry] = []

        // A waist joins the weight stored at the same instant from the same source.
        var waistByKey: [String: (row: LabMarkerRow, cm: Double)] = [:]
        var looseWaists: [(row: LabMarkerRow, cm: Double)] = []
        for row in waists {
            guard let cm = BodyMeasurementResolver.normalizedValue(of: row, as: .waist) else {
                unlisted += 1
                continue
            }
            let key = "\(row.takenAt)\u{1F}\(row.source)"
            if waistByKey[key] == nil { waistByKey[key] = (row, cm) } else { looseWaists.append((row, cm)) }
        }
        for row in weights {
            guard let kg = BodyMeasurementResolver.normalizedValue(of: row, as: .weight) else {
                unlisted += 1
                continue
            }
            let waist = waistByKey.removeValue(forKey: "\(row.takenAt)\u{1F}\(row.source)")
            entries.append(HistoryEntry(day: row.day, takenAt: row.takenAt, rank: 1, tieBreak: row.id,
                                        weightKg: kg, weightRow: row, waistCm: waist?.cm, waistRow: waist?.row,
                                        source: .labBook, labSource: row.source))
        }
        for waist in Array(waistByKey.values) + looseWaists {
            entries.append(HistoryEntry(day: waist.row.day, takenAt: waist.row.takenAt, rank: 1,
                                        tieBreak: waist.row.id, weightKg: nil, weightRow: nil, waistCm: waist.cm,
                                        waistRow: waist.row, source: .labBook, labSource: waist.row.source))
        }
        for entry in appleHealth where entry.value.isFinite && entry.value > 0 {
            entries.append(HistoryEntry(day: entry.day, takenAt: nil, rank: 0, tieBreak: "", weightKg: entry.value,
                                        weightRow: nil, waistCm: nil, waistRow: nil, source: .appleHealth,
                                        labSource: nil))
        }
        entries.sort { $0.sortsBefore($1) }

        // The reading that represents a week is its latest weight: the newest day, a Lab Book reading
        // before an Apple Health value on one day, then the latest instant.
        var representative: [String: Int] = [:]
        for (index, entry) in entries.enumerated() where entry.weightKg != nil {
            guard let week = CutScorecard.weekStart(containing: entry.day) else { continue }
            representative[week] = index
        }
        let representing = Set(representative.values)

        let rows: [WeighInHistoryRow] = entries.enumerated().reversed().map { index, entry in
            let represents = representing.contains(index)
            let lead = represents ? String(localized: "Represents its week") : String(localized: "Not the weekly point")
            let origin: String
            switch entry.source {
            case .appleHealth: origin = String(localized: "Apple Health · read-only")
            default:
                origin = entry.labSource == LabMarkerCsvImport.sourceId
                    ? String(localized: "Lab Book · CSV import") : sourceCaption(.labBook)
            }
            let stored = entry.weightRow ?? entry.waistRow
            let isLabBook = entry.source == .labBook
            return WeighInHistoryRow(
                id: stored.map { "\($0.deviceId)\u{1F}\($0.id)" } ?? "apple-health\u{1F}\(entry.day)",
                day: entry.day, takenAt: entry.takenAt, dateText: words.date(entry.day),
                weightText: entry.weightKg.map(words.weightNumber),
                waistText: entry.waistCm.map(words.lengthNumber), source: entry.source,
                caption: "\(lead) · \(origin)", representsWeek: represents,
                canEdit: isLabBook, canDelete: isLabBook, weightRow: entry.weightRow, waistRow: entry.waistRow)
        }

        var note: String?
        if unlisted == 1 {
            note = String(localized: "\(unlisted) reading in a unit that is not recognised is not listed. It remains in Lab Book.")
        } else if unlisted > 1 {
            note = String(localized: "\(unlisted) readings in a unit that is not recognised are not listed. They remain in Lab Book.")
        }
        return WeighInHistory(
            rows: rows, weightUnit: words.weightUnit, waistUnit: words.lengthUnit,
            notMeasuredText: String(localized: "not measured"),
            emptyText: rows.isEmpty ? String(localized: "No weigh-ins yet") : nil,
            legend: rows.isEmpty ? nil
                : String(localized: "The dot marks the reading that represents its week: the latest one."),
            unlistedCount: unlisted, unlistedNote: note)
    }

    /// The question asked once before `row` is deleted.
    static func deleteConfirmation(for row: WeighInHistoryRow, unitSystem: UnitSystem,
                                   locale: Locale) -> WeighInDeleteConfirmation {
        let words = Wording(unitSystem: unitSystem, locale: locale)
        let reading = row.weightText.map { "\($0) \(words.weightUnit)" }
            ?? row.waistText.map { "\($0) \(words.lengthUnit)" }
        let named = [row.dateText, reading].compactMap { $0 }.joined(separator: " · ")
        return WeighInDeleteConfirmation(
            title: String(localized: "Delete this weigh-in?"),
            detail: String(localized: "\(named). The weekly series and the verdict are worked out again without it."),
            confirmTitle: String(localized: "Delete"), cancelTitle: String(localized: "Cancel"))
    }

    /// One reading on its way into the history list.
    private struct HistoryEntry {
        let day: String
        let takenAt: Int?
        /// 0 for Apple Health, 1 for Lab Book: on one day a Lab Book reading is the later of the two.
        let rank: Int
        let tieBreak: String
        let weightKg: Double?
        let weightRow: LabMarkerRow?
        let waistCm: Double?
        let waistRow: LabMarkerRow?
        let source: BodyMeasurementSource
        let labSource: String?

        func sortsBefore(_ other: HistoryEntry) -> Bool {
            (day, rank, takenAt ?? 0, tieBreak) < (other.day, other.rank, other.takenAt ?? 0, other.tieBreak)
        }
    }

    // MARK: - Numbers, units and dates

    /// How one surface writes numbers, units and dates. Dates are day-first as the frames draw them
    /// ("Wed 29 Jan"), with the locale's own weekday and month words.
    struct Wording {
        let unitSystem: UnitSystem
        let locale: Locale
        private let dayAndDate: DateFormatter
        private let shortDay: DateFormatter
        private let keys: DateFormatter
        private let calendar: Calendar

        init(unitSystem: UnitSystem, locale: Locale) {
            self.unitSystem = unitSystem
            self.locale = locale
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
            calendar = utc
            func formatter(_ pattern: String, _ locale: Locale) -> DateFormatter {
                let formatter = DateFormatter()
                formatter.calendar = utc
                formatter.timeZone = utc.timeZone
                formatter.locale = locale
                formatter.dateFormat = pattern
                return formatter
            }
            dayAndDate = formatter("EEE d MMM", locale)
            shortDay = formatter("d MMM", locale)
            keys = formatter("yyyy-MM-dd", Locale(identifier: "en_US_POSIX"))
        }

        var weightUnit: String { unitSystem == .metric ? "kg" : "lb" }
        var lengthUnit: String { unitSystem == .metric ? "cm" : "in" }

        /// Kilograms in the display unit.
        func weightValue(_ kg: Double) -> Double {
            unitSystem == .metric ? kg : kg * UnitFormatter.poundsPerKilogram
        }

        /// Centimetres in the display unit.
        func lengthValue(_ cm: Double) -> Double {
            unitSystem == .metric ? cm : cm / UnitFormatter.centimetersPerInch
        }

        /// A number with a fixed count of decimals and the locale's decimal separator, ungrouped.
        func fixed(_ value: Double, _ decimals: Int) -> String {
            let text = String(format: "%.\(decimals)f", locale: Locale(identifier: "en_US_POSIX"), value)
            let separator = locale.decimalSeparator ?? "."
            return separator == "." ? text : text.replacingOccurrences(of: ".", with: separator)
        }

        /// As `fixed`, with trailing zeros dropped: "0.4", "100".
        func trimmed(_ value: Double, _ decimals: Int) -> String {
            var text = String(format: "%.\(decimals)f", locale: Locale(identifier: "en_US_POSIX"), value)
            if text.contains(".") {
                while text.hasSuffix("0") { text.removeLast() }
                if text.hasSuffix(".") { text.removeLast() }
            }
            let separator = locale.decimalSeparator ?? "."
            return separator == "." ? text : text.replacingOccurrences(of: ".", with: separator)
        }

        func weightNumber(_ kg: Double) -> String { fixed(weightValue(kg), 1) }
        func lengthNumber(_ cm: Double) -> String { fixed(lengthValue(cm), 1) }
        func rateNumber(_ kgPerWeek: Double) -> String { fixed(weightValue(kgPerWeek), 2) }
        func weight(_ kg: Double) -> String { "\(weightNumber(kg)) \(weightUnit)" }
        func length(_ cm: Double) -> String { "\(lengthNumber(cm)) \(lengthUnit)" }

        /// A change in length with a true minus sign; an increase carries no sign.
        func signedLength(_ cm: Double) -> String {
            let text = lengthNumber(cm)
            return text.hasPrefix("-") ? "\u{2212}" + text.dropFirst() : text
        }

        /// The slow-loss threshold with its unit: "0.4 kg".
        func threshold(_ kgPerWeek: Double) -> String {
            "\(trimmed(weightValue(kgPerWeek), unitSystem == .metric ? 2 : 1)) \(weightUnit)"
        }

        /// A band's two bounds: "0.40–1.20".
        func band(_ low: Double, _ high: Double) -> String { "\(fixed(low, 2))–\(fixed(high, 2))" }

        private func instant(_ day: String) -> Date? { keys.date(from: day) }

        /// "Wed 29 Jan". A key that names no date is returned as it is.
        func date(_ day: String) -> String { instant(day).map(dayAndDate.string(from:)) ?? day }

        /// "29 Jan".
        func shortDate(_ day: String) -> String { instant(day).map(shortDay.string(from:)) ?? day }

        /// Whole weeks from the week of `earlier` to the week of `later`, Monday to Monday.
        func weeksBetween(_ earlier: String, _ later: String) -> Int? {
            guard let from = CutScorecard.weekStart(containing: earlier).flatMap(instant),
                  let to = CutScorecard.weekStart(containing: later).flatMap(instant) else { return nil }
            return calendar.dateComponents([.day], from: from, to: to).day.map { $0 / 7 }
        }
    }
}

/// Both values, or nil when either is missing.
private func both<A, B>(_ first: A?, _ second: B?) -> (A, B)? {
    guard let first, let second else { return nil }
    return (first, second)
}

// MARK: - Screen labels

/// The fixed words of the scorecard screens (frames B, C and D): section titles, actions and the
/// mark for a missing value. They live here so that a view words nothing itself.
extension CutScorecardPresenter {
    /// A value that was not measured. Never "0".
    static var missingValue: String { "—" }

    static var rulesTitle: String { String(localized: "Your three rules, in order") }
    static var signalsTitle: String { String(localized: "Four signals") }
    static var curvesTitle: String { String(localized: "Weekly curves") }
    static var emptyCurvesTitle: String { String(localized: "Weight and waist") }
    static var historyTitle: String { String(localized: "History") }
    static var phaseAndRulesTitle: String { String(localized: "Phase and rules") }
    static var logWeighInTitle: String { String(localized: "Log weigh-in") }
    static var weightTitle: String { String(localized: "Weight") }
    static var waistTitle: String { String(localized: "Waist") }
    static var editTitle: String { String(localized: "Edit") }
    static var deleteTitle: String { String(localized: "Delete") }
    static var cancelTitle: String { String(localized: "Cancel") }
    static var saveTitle: String { String(localized: "Save") }

    // MARK: Weigh-in sheet

    static var weighInTitle: String { String(localized: "Weigh-in") }
    static var skipTitle: String { String(localized: "Skip") }

    /// "Step 1 of 2".
    static func weighInStepText(_ step: WeighInSheetModel.Step) -> String {
        let number = step == .weight ? 1 : 2
        return String(localized: "Step \(number) of 2")
    }

    /// The date control's caption: "Today · Wed 5 Feb · 07:02", or "Thu 16 Jan · 07:02" for another day.
    static func weighInDateText(takenAt: Date, now: Date, timeZone: TimeZone, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = DateFormatter()
        day.calendar = calendar
        day.timeZone = timeZone
        day.locale = locale
        day.dateFormat = "EEE d MMM"
        let time = DateFormatter()
        time.calendar = calendar
        time.timeZone = timeZone
        time.locale = locale
        time.setLocalizedDateFormatFromTemplate("jmm")
        var parts = [day.string(from: takenAt), time.string(from: takenAt)]
        if calendar.isDate(takenAt, inSameDayAs: now) { parts.insert(String(localized: "Today"), at: 0) }
        return parts.joined(separator: " · ")
    }

    /// A typed number with its unit: "97.5 kg". Step 2 shows the weight of step 1 this way.
    static func weighInValueText(_ text: String, unit: String) -> String {
        "\(text.trimmingCharacters(in: .whitespaces)) \(unit)"
    }

    // MARK: History

    /// The note under the history list: what the dot means, then how many readings were left out.
    static func historyFootnote(_ history: WeighInHistory) -> String? {
        let parts = [history.legend, history.unlistedNote].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

// MARK: - Phase and rules sheet

/// One editable value of the phase and rules sheet (specification §10.5).
struct ScorecardPhaseRow: Equatable, Identifiable {
    enum Input: Equatable { case text, decimal, whole, date }

    var field: ScorecardPhaseDraft.Field
    var label: String
    /// The value as typed: a name, or a number in the display unit. Empty when not set.
    var text: String
    /// Shown in an empty field that may stay empty ("Not set"). Nil: the field needs a value.
    var placeholder: String?
    /// What follows the number: "% of bodyweight per week", "weeks running", "kg".
    var suffix: String?
    var input: Input
    var isInvalid: Bool

    var id: String { field.rawValue }
}

/// One section of the sheet: its rows and the note under them.
struct ScorecardPhaseGroup: Equatable, Identifiable {
    var title: String
    var rows: [ScorecardPhaseRow]
    var footnote: String?
    /// Why the sheet cannot be saved, under the section that holds the first value at fault. It
    /// takes the footnote's place.
    var error: String?

    var id: String { title }
}

/// The phase and rules sheet, already worded.
struct ScorecardPhaseSheetPresentation: Equatable {
    var title: String
    var cancelTitle: String
    var saveTitle: String
    var canSave: Bool
    var cutTitle: String
    var otherTitle: String
    var groups: [ScorecardPhaseGroup]
    /// "Start a new phase" and its note. Nil while the draft is itself a new phase.
    var newPhaseTitle: String?
    var newPhaseNote: String?
}

extension CutScorecardPresenter {

    /// The sheet for `draft`. `today` marks a start date of today; `previousPhaseName` is the stored
    /// phase a new phase would follow.
    static func phaseSheet(_ draft: ScorecardPhaseDraft, today: String, previousPhaseName: String?,
                           unitSystem: UnitSystem, locale: Locale) -> ScorecardPhaseSheetPresentation {
        let words = Wording(unitSystem: unitSystem, locale: locale)
        let invalid = Set(draft.invalidFields)
        let message = draft.validationMessage
        let firstInvalid = draft.invalidFields.first
        let isCut = draft.kind == .cut
        let groups = draft.groups

        var shown: [ScorecardPhaseGroup] = groups.enumerated().map { index, group in
            let rows = group.fields.map { field in
                phaseRow(field, draft: draft, today: today, words: words, isInvalid: invalid.contains(field))
            }
            var error: String?
            if let message {
                if let firstInvalid {
                    if group.fields.contains(firstInvalid) { error = message }
                } else if index == groups.count - 1 {
                    error = message
                }
            }
            return ScorecardPhaseGroup(title: group.title, rows: rows,
                                       footnote: phaseFootnote(group, draft: draft, isCut: isCut,
                                                               previousPhaseName: previousPhaseName),
                                       error: error)
        }
        // The same title twice would give two sections one identity.
        var seen: Set<String> = []
        shown = shown.filter { seen.insert($0.title).inserted }

        return ScorecardPhaseSheetPresentation(
            title: draft.title, cancelTitle: cancelTitle, saveTitle: saveTitle, canSave: draft.canSave,
            cutTitle: String(localized: "Cut"), otherTitle: String(localized: "Other"), groups: shown,
            newPhaseTitle: draft.isNewPhase ? nil : String(localized: "Start a new phase"),
            newPhaseNote: draft.isNewPhase ? nil
                : String(localized: "The current phase stays in your list of past phases."))
    }

    private static func phaseFootnote(_ group: ScorecardPhaseDraft.Group, draft: ScorecardPhaseDraft,
                                      isCut: Bool, previousPhaseName: String?) -> String? {
        let fields = group.fields
        if fields.contains(.name) {
            var parts: [String] = []
            parts.append(isCut
                ? String(localized: "The target is optional. With no target there is no projection.")
                : String(localized: "A phase that is not a cut has no target, no band and no rules. While it is active the scorecard shows \"No cut phase is active\". Weigh-ins and curves carry on."))
            if draft.isNewPhase, let previousPhaseName {
                parts.append(String(localized: "Starting this phase keeps \"\(previousPhaseName)\" in your list of past phases."))
            }
            return parts.joined(separator: " ")
        }
        if fields.contains(.rateLow) {
            return String(localized: "The rate signal is met inside this band. The band never changes the verdict.")
        }
        if fields.contains(.waistWindowWeeks) {
            return String(localized: "Fires when lifts are holding and the waist is shrinking. It comes first.")
        }
        if fields.contains(.proteinFloorGrams) {
            return draft.parameters.proteinFloorGrams == nil
                ? String(localized: "With no floor the protein signal reads \"No floor set\". Protein never changes the verdict.")
                : String(localized: "Protein is shown as a signal and never changes the verdict.")
        }
        return nil
    }

    private static func phaseRow(_ field: ScorecardPhaseDraft.Field, draft: ScorecardPhaseDraft, today: String,
                                 words: Wording, isInvalid: Bool) -> ScorecardPhaseRow {
        let p = draft.parameters
        let notSet = String(localized: "Not set")
        func row(_ text: String, _ suffix: String?, _ input: ScorecardPhaseRow.Input,
                 placeholder: String? = nil) -> ScorecardPhaseRow {
            ScorecardPhaseRow(field: field, label: field.label, text: text, placeholder: placeholder,
                              suffix: suffix, input: input, isInvalid: isInvalid)
        }
        func decimal(_ value: Double, _ decimals: Int) -> String {
            value.isFinite ? words.trimmed(value, decimals) : ""
        }
        func whole(_ value: Int) -> String { value < 0 ? "" : String(value) }
        func weeks(_ count: Int) -> String {
            count == 1 ? String(localized: "week") : String(localized: "weeks")
        }
        let percentOfBodyweight = String(localized: "% of bodyweight per week")
        switch field {
        case .name: return row(draft.name, nil, .text)
        case .startDay:
            let date = words.dateWithYear(draft.startDay)
            return row(draft.startDay == today ? String(localized: "Today · \(date)") : date, nil, .date)
        case .targetWeight:
            return row(draft.targetWeightKg.map { $0.isFinite ? words.weightNumber($0) : "" } ?? "",
                       words.weightUnit, .decimal, placeholder: notSet)
        case .rateLow:
            return row(draft.rateLowPercentPerWeek.isFinite ? words.fixed(draft.rateLowPercentPerWeek, 2) : "",
                       percentOfBodyweight, .decimal)
        case .rateHigh:
            return row(draft.rateHighPercentPerWeek.isFinite ? words.fixed(draft.rateHighPercentPerWeek, 2) : "",
                       percentOfBodyweight, .decimal)
        case .waistWindowWeeks: return row(whole(p.waistWindowWeeks), weeks(p.waistWindowWeeks), .whole)
        case .waistMinDecreaseCm:
            return row(decimal(words.lengthValue(p.waistMinDecreaseCm), 2), words.lengthUnit, .decimal)
        case .liftDropTolerancePercent:
            return row(decimal(p.liftDropTolerancePercent, 2), String(localized: "% under last week"), .decimal)
        case .liftDropShare:
            return row(decimal(p.liftDropShare * 100, 0), String(localized: "% or more"), .decimal)
        case .liftDropConsecutiveWeeks:
            return row(whole(p.liftDropConsecutiveWeeks),
                       p.liftDropConsecutiveWeeks == 1 ? String(localized: "week running")
                           : String(localized: "weeks running"), .whole)
        case .addCaloriesKcal: return row(whole(p.addCaloriesKcal), "kcal", .whole)
        case .slowLossThresholdKgPerWeek:
            return row(decimal(words.weightValue(p.slowLossThresholdKgPerWeek), 2),
                       String(localized: "\(words.weightUnit) per week"), .decimal)
        case .slowLossConsecutiveWeeks:
            return row(whole(p.slowLossConsecutiveWeeks),
                       p.slowLossConsecutiveWeeks == 1 ? String(localized: "week running")
                           : String(localized: "weeks running"), .whole)
        case .reduceCarbsKcal: return row(whole(p.reduceCarbsKcal), "kcal", .whole)
        case .rateWindowWeeks: return row(whole(p.rateWindowWeeks), weeks(p.rateWindowWeeks), .whole)
        case .maxProjectionWeeks: return row(whole(p.maxProjectionWeeks), weeks(p.maxProjectionWeeks), .whole)
        case .targetToleranceKg:
            return row(decimal(words.weightValue(p.targetToleranceKg), 2), words.weightUnit, .decimal)
        case .proteinFloorGrams:
            return row(p.proteinFloorGrams.map { decimal($0, 2) } ?? "", "g", .decimal, placeholder: notSet)
        case .proteinMinDaysPerWeek:
            return row(whole(p.proteinMinDaysPerWeek), String(localized: "of 7"), .whole)
        case .maxWeighInAgeWeeks:
            return row(whole(p.maxWeighInAgeWeeks),
                       p.maxWeighInAgeWeeks == 1 ? String(localized: "week without a weigh-in")
                           : String(localized: "weeks without a weigh-in"), .whole)
        }
    }

    /// `draft` with `field` set from what was typed, in the display unit. Text that is not a number
    /// stores a value the draft's own validation refuses, so the field is marked and Save is off; an
    /// empty target or protein floor means "not set". Numbers are read as the weigh-in sheet reads
    /// them, which is why this runs on the main actor.
    @MainActor
    static func phaseDraft(_ draft: ScorecardPhaseDraft, setting field: ScorecardPhaseDraft.Field,
                           to text: String, unitSystem: UnitSystem, locale: Locale) -> ScorecardPhaseDraft {
        var next = draft
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let number = WeighInSheetModel.parse(trimmed, locale: locale) ?? .nan
        let count = Int(trimmed) ?? -1
        let metric = unitSystem == .metric
        let kilograms = metric ? number : number / UnitFormatter.poundsPerKilogram
        let centimetres = metric ? number : number * UnitFormatter.centimetersPerInch
        switch field {
        case .name: next.name = text
        case .startDay: next.startDay = trimmed
        case .targetWeight: next.targetWeightKg = trimmed.isEmpty ? nil : kilograms
        case .rateLow: next.rateLowPercentPerWeek = number
        case .rateHigh: next.rateHighPercentPerWeek = number
        case .waistWindowWeeks: next.parameters.waistWindowWeeks = count
        case .waistMinDecreaseCm: next.parameters.waistMinDecreaseCm = centimetres
        case .liftDropTolerancePercent: next.parameters.liftDropTolerancePercent = number
        case .liftDropShare: next.parameters.liftDropShare = number / 100
        case .liftDropConsecutiveWeeks: next.parameters.liftDropConsecutiveWeeks = count
        case .addCaloriesKcal: next.parameters.addCaloriesKcal = count
        case .slowLossThresholdKgPerWeek: next.parameters.slowLossThresholdKgPerWeek = kilograms
        case .slowLossConsecutiveWeeks: next.parameters.slowLossConsecutiveWeeks = count
        case .reduceCarbsKcal: next.parameters.reduceCarbsKcal = count
        case .rateWindowWeeks: next.parameters.rateWindowWeeks = count
        case .maxProjectionWeeks: next.parameters.maxProjectionWeeks = count
        case .targetToleranceKg: next.parameters.targetToleranceKg = kilograms
        case .proteinFloorGrams: next.parameters.proteinFloorGrams = trimmed.isEmpty ? nil : number
        case .proteinMinDaysPerWeek: next.parameters.proteinMinDaysPerWeek = count
        case .maxWeighInAgeWeeks: next.parameters.maxWeighInAgeWeeks = count
        }
        return next
    }

    /// The start day as an instant the date control can show: noon of that day in `timeZone`.
    static func phaseStartDate(_ draft: ScorecardPhaseDraft, timeZone: TimeZone) -> Date? {
        let parts = draft.startDay.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, CutScorecard.weekStart(containing: draft.startDay) != nil else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// `draft` starting on the day `date` falls on in `timeZone`.
    static func phaseDraft(_ draft: ScorecardPhaseDraft, startingOn date: Date,
                           timeZone: TimeZone) -> ScorecardPhaseDraft {
        var next = draft
        next.startDay = LocalDayWindows(timeZone: timeZone).dayKey(for: date)
        return next
    }
}

extension CutScorecardPresenter.Wording {
    /// "Mon 6 Jan 2031". A key that names no date is returned as it is.
    func dateWithYear(_ day: String) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let keys = DateFormatter()
        keys.calendar = calendar
        keys.timeZone = calendar.timeZone
        keys.locale = Locale(identifier: "en_US_POSIX")
        keys.dateFormat = "yyyy-MM-dd"
        guard let instant = keys.date(from: day) else { return day }
        let shown = DateFormatter()
        shown.calendar = calendar
        shown.timeZone = calendar.timeZone
        shown.locale = locale
        shown.dateFormat = "EEE d MMM yyyy"
        return shown.string(from: instant)
    }
}
