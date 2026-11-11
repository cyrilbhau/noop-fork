// API ASSUMED BY THESE TESTS
//
// New, in Strand/Data/CutScorecardInputBuilder.swift (specification §8.2):
//
//     extension CutScorecardInputBuilder {
//         /// The stored state as an evaluation, with an upcoming cut phase passed when none is active.
//         func evaluation(today: String) async -> CutScorecardEvaluation
//     }
//
// `CutScorecardEvaluation` keeps its definition, `(input: CutScorecardInput, result:
// CutScorecardResult)`. `CutScorecardModel` calls `evaluation(today:)` where it called its private
// `evaluateStored(today:)`; the body moves unchanged.
//
// The specification lists these three tests as new methods of
// StrandTests/CutScorecardInputBuilderTests.swift. They are in a file of their own because the
// test author was told to edit no existing test file; they can be folded into that class later.

import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

// Stage 2 (coach packet), specification §8.2 and §12.3: ONE SCORECARD EVALUATION. The screen model
// and the packet both call `CutScorecardInputBuilder.evaluation(today:)`. Written before the move.
//
// Synthetic values only: the Fixture Person.
@MainActor
final class CutScorecardEvaluationFunnelTests: XCTestCase {
    private typealias H = CoachPacketHarness
    private let suites = CoachPacketSuites()

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    private func builder(_ h: CoachPacketHarness) -> CutScorecardInputBuilder {
        CutScorecardInputBuilder(repository: h.repo, provider: h.provider, settings: h.scorecardSettings,
                                 intake: IntakeProvider(repository: h.repo, settings: IntakeSettings(defaults: h.defaults)),
                                 timeZone: { H.utc })
    }

    private func cut(_ h: CoachPacketHarness, startOffset: Int, name: String = "Fixture cut",
                     kind: CutScorecardStoredPhase.Kind = .cut) -> CutScorecardStoredPhase {
        CutScorecardStoredPhase(kind: kind, name: name, startDay: h.clock.day(startOffset), targetWeightKg: 94.0,
                                rateLowPercentPerWeek: 0.40, rateHighPercentPerWeek: 1.20)
    }

    func testEvaluationEqualsEvaluateOfTheBuiltInput() async throws {
        let h = try await H.fixturePerson(scorecard: true, suites: suites)
        let built = await builder(h).build(today: h.today)
        XCTAssertNotNil(built.phase, "the fixture's cut is active")

        let evaluation = await builder(h).evaluation(today: h.today)
        XCTAssertEqual(evaluation.input, built, "with an active phase the input is the built input, unchanged")
        XCTAssertEqual(evaluation.result, CutScorecard.evaluate(built))
        let direct = await builder(h).evaluate(today: h.today)
        XCTAssertEqual(evaluation.result, direct)
        XCTAssertFalse(evaluation.result.weeks.isEmpty)
    }

    func testEvaluationPassesAnUpcomingCutPhaseWhenNoneIsActive() async throws {
        let h = try await H.fixturePerson(scorecard: true, suites: suites)
        h.scorecardSettings.phases = [cut(h, startOffset: 7)]
        let built = await builder(h).build(today: h.today)
        XCTAssertNil(built.phase, "before its start day the settings hand out no phase")

        let evaluation = await builder(h).evaluation(today: h.today)
        XCTAssertEqual(evaluation.input.phase,
                       CutScorecardPhase(name: "Fixture cut", startDay: h.clock.day(7), targetWeightKg: 94.0,
                                         rateLowPercentPerWeek: 0.40, rateHighPercentPerWeek: 1.20))
        XCTAssertEqual(evaluation.result.verdict.reason, .phaseNotStarted)
        // Nothing but the phase differs from the built input.
        XCTAssertEqual(evaluation.input.weights, built.weights)
        XCTAssertEqual(evaluation.input.waists, built.waists)
        XCTAssertEqual(evaluation.input.lifts, built.lifts)
        XCTAssertEqual(evaluation.input.proteinDays, built.proteinDays)
        XCTAssertEqual(evaluation.input.parameters, built.parameters)
        XCTAssertEqual(evaluation.input.today, h.today)

        // An upcoming phase that is not a cut is not passed.
        h.scorecardSettings.phases = [cut(h, startOffset: 7, name: "Fixture maintenance", kind: .other)]
        let other = await builder(h).evaluation(today: h.today)
        XCTAssertNil(other.input.phase)

        // The earliest upcoming phase decides, as the screen model's copy did: a later cut is not
        // reached past an earlier phase of another kind.
        h.scorecardSettings.phases = [cut(h, startOffset: 7, name: "Fixture maintenance", kind: .other),
                                      cut(h, startOffset: 14)]
        let later = await builder(h).evaluation(today: h.today)
        XCTAssertNil(later.input.phase)

        // An active phase is never replaced by a later one.
        h.scorecardSettings.phases = [cut(h, startOffset: -69), cut(h, startOffset: 14, name: "Fixture second cut")]
        let active = await builder(h).evaluation(today: h.today)
        XCTAssertEqual(active.input.phase?.startDay, h.clock.day(-69))
        XCTAssertEqual(active.input.phase?.name, "Fixture cut")
    }

    func testEvaluationCarriesTheInputThatWasJudged() async throws {
        let h = try await H.fixturePerson(scorecard: true, suites: suites)
        for phases in [[cut(h, startOffset: -69)], [cut(h, startOffset: 7)], []] {
            h.scorecardSettings.phases = phases
            let evaluation = await builder(h).evaluation(today: h.today)
            XCTAssertEqual(evaluation.result, CutScorecard.evaluate(evaluation.input),
                           "the result is the evaluation of the input it travels with")
            XCTAssertEqual(evaluation.input.today, h.today)
        }
    }

    /// The screen model's default evaluation is this function: an injected closure that calls it
    /// loads the same state as no closure at all.
    func testTheScreenModelLoadsWhatTheFunnelReturns() async throws {
        let h = try await H.fixturePerson(scorecard: true, suites: suites)
        let now = h.clock.now
        let locale = Locale(identifier: "en_GB")
        func model(_ evaluate: (@MainActor (String) async -> CutScorecardEvaluation)?) -> CutScorecardModel {
            CutScorecardModel(repository: h.repo, provider: h.provider, settings: h.scorecardSettings,
                              unitSystem: { .metric }, now: { now }, timeZone: { H.utc }, locale: { locale },
                              evaluate: evaluate)
        }
        for phases in [[cut(h, startOffset: -69)], [cut(h, startOffset: 7)]] {
            h.scorecardSettings.phases = phases
            let stored = model(nil)
            await stored.load()
            let funnel = builder(h)
            let injected = model { today in await funnel.evaluation(today: today) }
            await injected.load()
            guard case .loaded = stored.state else { return XCTFail("\(stored.state)") }
            XCTAssertEqual(stored.state, injected.state)
        }
    }
}
