import Foundation
import WhoopStore
@testable import StrandAnalytics

// API ASSUMED BY THESE TESTS (packet v2, stage 2 specification §7.12)
//
//   enum CoachPacketSection: String, CaseIterable {
//       case scorecard, weighIns = "weigh-ins", intake, recoverySleep = "recovery-sleep", trends,
//            activity, events
//   }
//   enum CoachPacketEvents: Equatable { case switchedOff; case rows([String]) }
//   enum CoachPacketIntakeSource: String { case appleHealth = "apple-health", quickAdd = "quick-add",
//       nutritionFile = "nutrition-file", mixed }
//   struct CoachPacketIntakeDay { init(day: String, proteinGrams: Double?, energyKcal: Double?,
//       source: CoachPacketIntakeSource?) }
//   enum CoachPacketIntake: Equatable { case switchedOff; case days([CoachPacketIntakeDay]) }
//   CoachPacketInput.init gains `intake: CoachPacketIntake, events: CoachPacketEvents` after
//       `workouts:`.
//   CoachPacket.formatVersion == 2
//   CoachPacket.byteBudget(rangeDays:) == 8000 + 290 × rangeDays + PersonalEvents.packetByteAllowance
//   CoachPacket.scan(_:rendered:identifiers:freeText:) — `freeText` is every raw string the
//       assembler gathered beside the input (ruling A20: event labels and notes before the cut).
//
// The intake source tokens are this test author's resolution of §18 "The intake row of packet
// v2": one token a day, from a closed enum, never a stored source id. A day whose protein and
// energy came from two different sources is `mixed`, because the row has room for one token and
// the budget fixes its widest form.

/// The packet v2 additions to the one Fixture Person (stage 1 §13, stage 2 §13, stage 3 §13,
/// stage 5 §13). Every value is invented.
///
/// Intake: stage 1 §13.2 states protein for the seven days before the weigh-ins of weeks 2 to 6
/// and no protein on any other day; the series below carries exactly those amounts. Stage 1 states
/// no energy figure and no source, so the energy amounts and the sources of weeks 5 and 6 are this
/// file's own round numbers, inside stage 3's calorie range of 2400 to 2600 kcal where they can be.
/// The fixture's G1 range (2031-03-03 to 2031-03-16) holds no intake at all, which is why G1's
/// scorecard reports `noProteinData` and its intake section prints dashes.
///
/// Events: stage 5 §13.1's eight events, unchanged (`PersonalEventsFixture`).
enum CoachPacketV2Fixture {

    typealias F = CoachPacketFixture

    // MARK: - Intake

    static func intakeDay(_ day: String, _ protein: Double?, _ energy: Double?,
                          _ source: CoachPacketIntakeSource?) -> CoachPacketIntakeDay {
        CoachPacketIntakeDay(day: day, proteinGrams: protein, energyKcal: energy, source: source)
    }

    /// Weeks 2 to 4 (the seven days before the weigh-ins of 2031-01-15, 01-22 and 01-29): stage 1's
    /// protein pattern 120, 120, 120, 80, 120, 120, 120, quick-added, with no energy.
    static let weeksTwoToFour: [CoachPacketIntakeDay] = {
        let pattern: [Double] = [120, 120, 120, 80, 120, 120, 120]
        return [0, 7, 14].flatMap { weekOffset in
            pattern.enumerated().map { index, grams in
                intakeDay(CutScorecardFixture.day("2031-01-08", weekOffset + index), grams, nil, .quickAdd)
            }
        }
    }()

    /// Weeks 5 and 6: stage 1's protein (120, 80, 80, 120, 80, 80, 120, then 120, none, 120, none,
    /// none, 120, none) with energy and every source token, one day energy only.
    static let weeksFiveAndSix: [CoachPacketIntakeDay] = [
        intakeDay("2031-01-29", 120, 2500, .quickAdd),
        intakeDay("2031-01-30", 80, 2450, .quickAdd),
        intakeDay("2031-01-31", 80, nil, .quickAdd),
        intakeDay("2031-02-01", 120, 2600, .appleHealth),
        intakeDay("2031-02-02", 80, 2400, .mixed),
        intakeDay("2031-02-03", 80, nil, .nutritionFile),
        intakeDay("2031-02-04", 120, 2550, .appleHealth),
        intakeDay("2031-02-05", 120, nil, .quickAdd),
        intakeDay("2031-02-07", 120, 2500, .quickAdd),
        intakeDay("2031-02-09", nil, 2300, .appleHealth),
        intakeDay("2031-02-10", 120, nil, .quickAdd),
    ]

    /// The whole intake series of the Fixture Person, oldest first.
    static let intakeSeries: [CoachPacketIntakeDay] = weeksTwoToFour + weeksFiveAndSix

    // MARK: - Events

    /// Stage 5's rows for `events` over a range, as the assembler asks for them.
    static func eventRows(_ events: [PersonalEvent] = PersonalEventsFixture.all, from first: String,
                          to last: String, includeSensitive: Bool = false) -> CoachPacketEvents {
        .rows(PersonalEvents.packetLines(events: events, firstDay: first, lastDay: last,
                                         includeSensitive: includeSensitive))
    }

    // MARK: - Drafts

    static let allSections = Set(CoachPacketSection.allCases)

    /// A version 2 input: a version 1 draft plus the two new sections.
    struct Draft {
        var base: F.Draft
        var intake: CoachPacketIntake
        var events: CoachPacketEvents

        var input: CoachPacketInput {
            CoachPacketInput(generatedAt: base.generatedAt, rangeStartDay: base.rangeStartDay,
                             rangeEndDay: base.rangeEndDay, sections: base.sections, days: base.days,
                             strainFactor: base.strainFactor, scorecard: base.scorecard, body: base.body,
                             hrvBaseline: base.hrvBaseline, restingHrBaseline: base.restingHrBaseline,
                             steps: base.steps, workouts: base.workouts, intake: intake, events: events)
        }

        var text: String { CoachPacket.render(input) }
    }

    /// The input of golden G1 v2: the full fixture, every section on, the intake feature on (and
    /// nothing logged in the range), the events feature on with private events left out.
    static var full: Draft {
        var base = F.full
        base.sections = allSections
        return Draft(base: base, intake: .days(intakeSeries),
                     events: eventRows(from: F.rangeStart, to: F.rangeEnd))
    }

    /// The input of golden G2 v2: no data at all, both features on.
    static var empty: Draft {
        var base = F.empty
        base.sections = allSections
        return Draft(base: base, intake: .days([]), events: eventRows([], from: F.rangeStart, to: F.rangeEnd))
    }

    /// The full fixture with one change.
    static func full(_ change: (inout Draft) -> Void) -> Draft {
        var draft = full
        change(&draft)
        return draft
    }

    /// A short packet with only `sections` on over `first`…`last`, generated on the last day at
    /// 07:42:10 +01:00. Every v1 section's data is the fixture's; it is not printed.
    static func compact(_ sections: Set<CoachPacketSection>, from first: String, to last: String,
                        intake: CoachPacketIntake = .days(intakeSeries),
                        events: CoachPacketEvents? = nil, includeSensitive: Bool = false) -> Draft {
        var base = F.full
        base.sections = sections
        base.rangeStartDay = first
        base.rangeEndDay = last
        base.generatedAt = "\(last)T07:42:10+01:00"
        return Draft(base: base, intake: intake,
                     events: events ?? eventRows(from: first, to: last, includeSensitive: includeSensitive))
    }
}
