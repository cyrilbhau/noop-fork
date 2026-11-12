// The findings of the independent Codex review, round 3 (C15 and C19), pinned by tests that fail on
// the defect. C16 is pure and is pinned in the StrandAnalytics package's own CodexReviewRound3Tests.
//
// C15 (ruling A29): the shared scorecard model followed body measurements and events only. A quick-add
// changed the intake provider's snapshot and a floor saved in Intake settings changed the one stored
// rule, yet the loaded scorecard kept its earlier protein figures and floor until something else
// reloaded it. It now re-evaluates on both, keeping its generation guard.
//
// C19: five accessibility omissions in views. The words VoiceOver hears are built by presenters these
// tests reach; the views' use of them, and the absence of unnamed controls, is guarded by reading
// the view sources, since the StrandiOS views do not load in this macOS-hosted bundle.
//
// Synthetic values only: the stage 3 fixture, dated relative to the real clock (stage 1 ruling R31).

import XCTest
import StrandAnalytics
import WhoopStore
@testable import Strand

@MainActor
final class CodexReviewRound3Tests: XCTestCase {
    private let suites = IntakeSuites()
    private let utc = TimeZone(identifier: "UTC")!

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    // MARK: - C15: the scorecard follows the intake snapshot and the rules

    private func makeModel(_ h: IntakeHarness,
                           evaluate: (@MainActor (String) async -> CutScorecardEvaluation)? = nil) -> CutScorecardModel {
        h.defaults.set(true, forKey: CutScorecardSettings.enabledKey)
        let today = h.today
        let provider = BodyMeasurementProvider(repository: h.repo, defaults: h.defaults, today: { today })
        let clock = h.clock
        let zone = utc
        return CutScorecardModel(repository: h.repo, provider: provider, settings: h.scorecard,
                                 unitSystem: { .metric }, now: { clock.now }, timeZone: { zone },
                                 locale: { Locale(identifier: "en_GB") }, intake: h.provider, evaluate: evaluate)
    }

    /// The protein of the day before the harness's today, as the scorecard evaluated it.
    private func proteinYesterday(_ model: CutScorecardModel, _ h: IntakeHarness) -> Double? {
        model.evaluation?.input.proteinDays.last { $0.day == h.clock.day(-1) }?.grams
    }

    private func waitUntil(_ what: String, timeout: TimeInterval = 10, file: StaticString = #filePath,
                           line: UInt = #line, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("timed out waiting for \(what)", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// C15's first reproduction: after the funnel notification the provider held 90 g and the
    /// scorecard's evaluation still 30 g.
    func testAQuickAddReachesTheLoadedScorecardsProtein() async throws {
        let h = try await IntakeHarness.make(suites: suites)
        try await h.seed(IntakeFixture.healthId, day: h.clock.day(-1), protein: 30, readAt: h.clock.epoch(-1, hour: 9))
        let model = makeModel(h)
        await model.load()
        XCTAssertEqual(proteinYesterday(model, h), 30)

        try await h.seed(IntakeFixture.healthId, day: h.clock.day(-1), protein: 90, readAt: h.clock.epoch(-1, hour: 21))
        IntakeProvider.funnelDidWrite(h.repo)
        await waitUntil("the scorecard to follow the intake snapshot") { self.proteinYesterday(model, h) == 90 }
        guard case .loaded = model.state else { return XCTFail("the scorecard is still loaded") }
    }

    /// C15's second reproduction: a floor saved in Intake settings left the scorecard on 100 g.
    func testAFloorSavedInIntakeSettingsReachesTheLoadedScorecard() async throws {
        let h = try await IntakeHarness.make(suites: suites)
        let model = makeModel(h)
        await model.load()
        XCTAssertEqual(model.evaluation?.input.parameters.proteinFloorGrams, IntakeFixture.floorGrams)

        XCTAssertTrue(h.settings.setProteinFloorGrams(120))
        await waitUntil("the scorecard to follow the floor") {
            model.evaluation?.input.parameters.proteinFloorGrams == 120
        }
    }

    /// A rules write from the scorecard's own settings object reaches it the same way.
    func testARulesWriteReachesTheLoadedScorecard() async throws {
        let h = try await IntakeHarness.make(suites: suites)
        let model = makeModel(h)
        await model.load()
        var parameters = h.scorecard.parameters
        parameters.proteinFloorGrams = 140
        h.scorecard.parameters = parameters
        await waitUntil("the scorecard to follow the rules") {
            model.evaluation?.input.parameters.proteinFloorGrams == 140
        }
    }

    /// Every defaults write posts the same notification; one that leaves the rules as they were, and
    /// a provider refresh that read nothing new, cost no evaluation.
    func testAnUnrelatedWriteOrUnchangedRefreshCostsNoEvaluation() async throws {
        let h = try await IntakeHarness.make(suites: suites)
        var calls = 0
        let input = CutScorecardInput(weights: [], waists: [], phase: nil, parameters: .generic, today: h.today)
        let result = (input: input, result: CutScorecard.evaluate(input))
        let model = makeModel(h) { _ in
            calls += 1
            return result
        }
        await h.provider.refresh()
        await model.load()
        XCTAssertEqual(calls, 1)
        h.defaults.set("fixture", forKey: "intake.round3.unrelated")
        await h.provider.refresh()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(calls, 1)

        // And the subscription is live: a real floor write does reload.
        XCTAssertTrue(h.settings.setProteinFloorGrams(110))
        await waitUntil("a reload after the floor write") { calls == 2 }
    }

    /// The generation guard is kept: a load overtaken by the reload a rules write starts never
    /// publishes over it.
    func testALoadOvertakenByARulesReloadDoesNotPublish() async throws {
        let h = try await IntakeHarness.make(suites: suites)
        var held: CheckedContinuation<Void, Never>?
        var holdNext = false
        var floors: [Double?] = []
        let model = makeModel(h) { today in
            // Read before the hold, so the held load carries the floor it began with.
            let parameters = h.scorecard.parameters
            if holdNext {
                holdNext = false
                await withCheckedContinuation { held = $0 }
            }
            floors.append(parameters.proteinFloorGrams)
            let input = CutScorecardInput(weights: [], waists: [], phase: nil, parameters: parameters, today: today)
            return (input: input, result: CutScorecard.evaluate(input))
        }
        await model.load()
        holdNext = true
        let stale = Task { await model.load() }   // held open before it reads the rules
        await waitUntil("the held load") { held != nil }
        XCTAssertTrue(h.settings.setProteinFloorGrams(130))
        await waitUntil("the reload the write starts") { model.evaluation?.input.parameters.proteinFloorGrams == 130 }
        held?.resume()
        await stale.value
        XCTAssertEqual(floors.last, IntakeFixture.floorGrams, "the held load did finish, with the old floor")
        XCTAssertEqual(model.evaluation?.input.parameters.proteinFloorGrams, 130,
                       "the overtaken load must not publish its result")
    }
}
