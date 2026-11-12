// API ASSUMED BY THESE TESTS
//
// New. `CoachPacketAssembler`, `CoachPacketDocument` and `CoachPacketOutcome` as assumed at the top
// of CoachPacketAssemblerTests.swift, and from specification §8.2:
//
//     extension CutScorecardInputBuilder {
//         /// The stored state as an evaluation, with an upcoming cut phase passed when none is active.
//         func evaluation(today: String) async -> CutScorecardEvaluation
//     }
//     // `CutScorecardEvaluation`, the alias `(input: CutScorecardInput, result: CutScorecardResult)`,
//     // keeps its definition and moves beside the builder.
//
// Behaviour assumed where the specification leaves it unstated:
//
//  1. The packet's phase is `evaluation.input.phase`, field for field, as a `CoachPacketPhase`.
//  2. The protein floor the packet prints is the floor inside the evaluation's protein signal. On
//     this branch `CutScorecardSettings.proteinFloorWholeGrams` (stage 1 ruling R45) does not
//     exist yet, so `testPacketFloorEqualsTheSettingsWholeGramFloor` ties the printed integer to
//     `CutScorecardSettings.parameters.proteinFloorGrams`, the value that property will hand out.
//     When R45 lands, one assertion against `proteinFloorWholeGrams` should be added there.
//
// Not reachable from this target: the Recovery detail's factor band lives in
// StrandiOS/Redesign/ScoreDetailData.swift, which the macOS test target does not compile.
// `testPacketBaselineBandEqualsTheRecoveryFactorBand` therefore ties the packet to
// `ChargeTypicalBand.range`, the one function that file calls, and the source scan
// (Tools/test_coach_packet_single_formatter.py) asserts that it does call it.

import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

// Stage 2 (coach packet), specification §4 and §12.3: THE PACKET HAS NO NUMBER OF ITS OWN. Every
// fact in it is read through the function the app's screens read it through, so the packet and a
// screen cannot disagree. Written before the implementation exists.
//
// Synthetic values only: the Fixture Person.
@MainActor
final class CoachPacketSingleSourceTests: XCTestCase {
    private typealias H = CoachPacketHarness
    private let suites = CoachPacketSuites()
    private static let british = Locale(identifier: "en_GB")

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    private func input(_ assembler: CoachPacketAssembler, file: StaticString = #filePath,
                       line: UInt = #line) async throws -> CoachPacketInput {
        let input = await assembler.input()
        return try XCTUnwrap(input, file: file, line: line)
    }

    private func builder(_ h: CoachPacketHarness) -> CutScorecardInputBuilder {
        CutScorecardInputBuilder(repository: h.repo, provider: h.provider, settings: h.scorecardSettings,
                                 intake: IntakeProvider(repository: h.repo, settings: IntakeSettings(defaults: h.defaults)),
                                 timeZone: { H.utc })
    }

    private func packetPhase(_ phase: CutScorecardPhase?) -> CoachPacketPhase? {
        phase.map {
            CoachPacketPhase(name: $0.name, startDay: $0.startDay, targetWeightKg: $0.targetWeightKg,
                             rateLowPercentPerWeek: $0.rateLowPercentPerWeek,
                             rateHighPercentPerWeek: $0.rateHighPercentPerWeek)
        }
    }

    /// Every number in `text` that directly precedes `unit`.
    private func figures(_ text: String, unit: String) throws -> [Double] {
        let regex = try NSRegularExpression(pattern: "(?<![\\w.])(\\d+(?:\\.\\d+)?) \(unit)\\b")
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: 1), in: text).flatMap { Double(text[$0]) }
        }
    }

    private func firstGroup(_ pattern: String, in text: String) throws -> String? {
        let regex = try NSRegularExpression(pattern: pattern)
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    // MARK: - Weight and waist

    func testPacketWeightAndWaistEqualTheProviderAndTheCoachContextNumber() async throws {
        let h = try await H.fixturePerson(scorecard: true, suites: suites)
        let weight = try XCTUnwrap(h.provider.current(.weight, consumer: .display))
        let waist = try XCTUnwrap(h.provider.current(.waist, consumer: .display))
        XCTAssertEqual([weight.value, waist.value], [97.1, 97.0], "the fixture's newest weigh-in")

        let built = try await input(h.assembler())
        XCTAssertEqual(built.body.first { $0.kind == .weight },
                       CoachPacketBodyReading(kind: .weight, value: weight.value, source: .labBook, day: weight.day))
        XCTAssertEqual(built.body.first { $0.kind == .waist },
                       CoachPacketBodyReading(kind: .waist, value: waist.value, source: .labBook, day: waist.day))
        XCTAssertEqual(built.body.count, 2)

        let text = try await h.document().text
        let day = h.clock.day(H.lastWeighInOffset)
        XCTAssertTrue(text.contains("current weight: 97.1 kg (lab-book, \(day))\n"), text)
        XCTAssertTrue(text.contains("current waist: 97.0 cm (lab-book, \(day))\n"), text)

        // The in-app Coach states the same two numbers (ruling R41). Its line is localised and is
        // not reused by the packet (specification §3 C9); the numbers are what must agree.
        let engine = AICoachEngine(repo: h.repo)
        engine.bodyMeasurements = h.provider
        let coach = await engine.onDeviceSignalsBlock()
        XCTAssertEqual(try figures(coach, unit: "kg"), [weight.value], coach)
        XCTAssertEqual(try figures(coach, unit: "cm"), [waist.value], coach)
        let packetWeight = try XCTUnwrap(CoachPacketText.line(text, startingWith: "current weight: "))
        let packetWaist = try XCTUnwrap(CoachPacketText.line(text, startingWith: "current waist: "))
        XCTAssertEqual(try figures(packetWeight, unit: "kg"), try figures(coach, unit: "kg"))
        XCTAssertEqual(try figures(packetWaist, unit: "cm"), try figures(coach, unit: "cm"))
    }

    /// A newer Apple Health weight is the current value on every surface, the packet included,
    /// under the packet's own source token.
    func testPacketNamesAppleHealthWhenItHoldsTheNewestWeight() async throws {
        let h = try await H.fixturePerson(scorecard: true, suites: suites)
        let day = h.clock.day(-2)
        _ = try await h.store.upsertAppleDaily(
            [AppleDaily(day: day, steps: nil, activeKcal: nil, basalKcal: nil, vo2max: nil, avgHr: nil, maxHr: nil,
                        walkingHr: nil, weightKg: 96.8)], deviceId: "apple-health")
        _ = try await h.store.upsertMetricSeries([MetricPoint(day: day, key: "weight", value: 96.8)],
                                                 deviceId: "apple-health")
        let built = try await input(h.assembler())
        let current = try XCTUnwrap(h.provider.current(.weight, consumer: .display))
        XCTAssertEqual(current.source, .appleHealth, "the provider was refreshed by the assembly")
        XCTAssertEqual(built.body.first { $0.kind == .weight },
                       CoachPacketBodyReading(kind: .weight, value: current.value, source: .appleHealth, day: current.day))
        let text = try await h.document().text
        XCTAssertTrue(text.contains("current weight: 96.8 kg (apple-health, \(day))\n"), text)
        XCTAssertFalse(text.contains("Apple Health"), "the packet prints its own token, never a localised name")
    }

    func testPacketFollowsADeletedWeighIn() async throws {
        let h = try await H.fixturePerson(scorecard: true, suites: suites)
        var text = try await h.document().text
        XCTAssertTrue(text.contains("current weight: 97.1 kg (lab-book, \(h.clock.day(-11)))\n"), text)

        let stored = await h.weighIns.readings(.weight)
        let newest = try XCTUnwrap(stored.first { $0.value == 97.1 })
        try await h.weighIns.delete(newest)
        XCTAssertEqual(h.provider.current(.weight, consumer: .display)?.value, 97.2)

        text = try await h.document().text
        XCTAssertTrue(text.contains("current weight: 97.2 kg (lab-book, \(h.clock.day(-18)))\n"), text)
        XCTAssertFalse(text.contains("97.1 kg"), "the deleted reading is in no section: \(text)")
    }

    // MARK: - Scorecard

    func testPacketScorecardEqualsTheScreenModelsEvaluation() async throws {
        let h = try await H.fixturePerson(scorecard: true, suites: suites)
        let evaluation = await builder(h).evaluation(today: h.today)
        XCTAssertNotNil(evaluation.input.phase, "the fixture's cut has started")

        let built = try await input(h.assembler())
        XCTAssertEqual(built.scorecard, .evaluated(phase: packetPhase(evaluation.input.phase), result: evaluation.result))

        // The screen: the model's default evaluation is the same function, so what it presents is
        // the presentation of that evaluation.
        let now = h.clock.now
        let model = CutScorecardModel(repository: h.repo, provider: h.provider, settings: h.scorecardSettings,
                                      unitSystem: { .metric }, now: { now }, timeZone: { H.utc },
                                      locale: { Self.british })
        await model.load()
        let context = CutScorecardPresentationContext(unitSystem: .metric, weightSource: .labBook,
                                                      rulesNeedAttention: false, locale: Self.british,
                                                      storedPhaseName: "Fixture cut")
        XCTAssertEqual(model.state, .loaded(CutScorecardPresenter.present(evaluation.result, input: evaluation.input,
                                                                          context: context)))

        // And the text carries that result's verdict and judged week.
        let text = try await h.document().text
        let verdict = evaluation.result.verdict
        XCTAssertTrue(text.contains("verdict: \(verdict.kind.rawValue); reason \(verdict.reason.rawValue); "), text)
        XCTAssertTrue(text.contains("judged-week: \(evaluation.result.judgedWeekStart ?? "none")\n"), text)
        XCTAssertTrue(text.contains("phase: \"Fixture cut\" (cut), started \(h.clock.day(-69)), target 94.0 kg, band 0.40 to 1.20 %/week\n"), text)
    }

    /// Before a stored cut starts, the screen says it has not started and names its start day. The
    /// packet prints the phase that was judged, which is that upcoming one.
    func testPacketPrintsTheUpcomingPhaseTheScreenJudged() async throws {
        let h = try await H.fixturePerson(scorecard: true, suites: suites)
        h.scorecardSettings.phases = [CutScorecardStoredPhase(kind: .cut, name: "Fixture cut", startDay: h.clock.day(7),
                                                              targetWeightKg: 94.0, rateLowPercentPerWeek: 0.40,
                                                              rateHighPercentPerWeek: 1.20)]
        let evaluation = await builder(h).evaluation(today: h.today)
        XCTAssertEqual(evaluation.input.phase?.startDay, h.clock.day(7))
        XCTAssertEqual(evaluation.result.verdict.reason, .phaseNotStarted)

        let built = try await input(h.assembler())
        XCTAssertEqual(built.scorecard, .evaluated(phase: packetPhase(evaluation.input.phase), result: evaluation.result))
        let text = try await h.document().text
        XCTAssertTrue(text.contains("phase: \"Fixture cut\" (cut), starts \(h.clock.day(7)), target 94.0 kg, band 0.40 to 1.20 %/week\n"), text)
    }

    func testPacketWeeklyPointsEqualTheScorecardWeeks() async throws {
        let h = try await H.fixturePerson(scorecard: true, suites: suites)
        let weeks = await builder(h).evaluation(today: h.today).result.weeks
        XCTAssertGreaterThan(weeks.count, 8, "the fixture spans more weeks than the packet lists")

        let text = try await h.document().text
        let section = CoachPacketText.section(text, "== WEIGH-INS ==")
        XCTAssertTrue(section.contains("weekly, weeks start Monday, the latest reading of a week represents it, last 8 of \(weeks.count) weeks:"), text)
        let rows = section.filter { $0.hasPrefix("  ") }
        XCTAssertEqual(rows.count, CoachPacket.weeklyRowLimit)
        for (row, week) in zip(rows, weeks.suffix(CoachPacket.weeklyRowLimit)) {
            let weight = week.weightKg.map { String(format: "%.1f kg", $0) + " (\(week.weightDay ?? ""))" } ?? "—"
            let waist = week.waistCm.map { String(format: "%.1f cm", $0) + " (\(week.waistDay ?? ""))" } ?? "—"
            XCTAssertTrue(row.hasPrefix("  \(week.weekStart): weight \(weight), waist \(waist), change "), row)
        }
        // The current value and the newest weekly point are one reading of one series.
        let newest = try XCTUnwrap(weeks.last { $0.weightKg != nil })
        XCTAssertTrue(text.contains(String(format: "current weight: %.1f kg (lab-book, %@)\n", newest.weightKg ?? 0,
                                           newest.weightDay ?? "")), text)
    }

    func testPacketFloorEqualsTheSettingsWholeGramFloor() async throws {
        let h = try await H.fixturePerson(scorecard: true, suites: suites)

        func floorInPacket() async throws -> String? {
            let text = try await h.document().text
            XCTAssertNil(try firstGroup("floor (\\d+[.,]\\d+)", in: text), "the floor is never printed with a decimal")
            return try firstGroup("; floor (\\d+) g$", in: CoachPacketText.line(text, startingWith: "signal protein: ") ?? "")
        }

        // A stored floor of 100.
        XCTAssertEqual(h.scorecardSettings.parameters.proteinFloorGrams, 100)
        var evaluation = await builder(h).evaluation(today: h.today)
        XCTAssertEqual(evaluation.result.signals.protein.floorGrams, 100)
        var printed = try await floorInPacket()
        XCTAssertEqual(printed, "100")

        // A fraction written straight into the stored rules string, as no editor would.
        let stored = try XCTUnwrap(h.defaults.string(forKey: CutScorecardSettings.rulesKey))
        XCTAssertTrue(stored.contains("\"proteinFloorGrams\":100"), stored)
        h.defaults.set(stored.replacingOccurrences(of: "\"proteinFloorGrams\":100", with: "\"proteinFloorGrams\":100.6"),
                       forKey: CutScorecardSettings.rulesKey)
        if h.scorecardSettings.rulesNeedAttention {
            // The settings may refuse such a string outright; then no verdict and no floor is printed.
            let text = try await h.document().text
            XCTAssertTrue(text.contains("not available: the stored rules need attention ("), text)
            return
        }
        let floor = try XCTUnwrap(h.scorecardSettings.parameters.proteinFloorGrams)
        evaluation = await builder(h).evaluation(today: h.today)
        XCTAssertEqual(evaluation.result.signals.protein.floorGrams, floor,
                       "the evaluation carries the floor the settings hand out")
        printed = try await floorInPacket()
        XCTAssertEqual(printed, "\(Int(floor.rounded()))",
                       "the packet prints the evaluation's floor, not a second reading of the stored string")
    }

    // MARK: - Steps

    func testPacketStepsEqualResolvedSteps() async throws {
        let h = try await H.fixturePerson(scorecard: false, suites: suites)
        _ = try await h.store.upsertMetricSeries(
            [MetricPoint(day: h.clock.day(-9), key: "steps", value: 4_400),
             MetricPoint(day: h.clock.day(-13), key: "steps", value: 9_050)], deviceId: Repository.whoopSource)
        // A different number in the daily row's own steps column, which the packet must not read.
        h.repo.days = h.fixtureDays().map { row in
            DailyMetric(day: row.day, totalSleepMin: row.totalSleepMin, efficiency: row.efficiency,
                        deepMin: row.deepMin, remMin: row.remMin, lightMin: row.lightMin, disturbances: nil,
                        restingHr: row.restingHr, avgHrv: row.avgHrv, recovery: row.recovery, strain: row.strain,
                        exerciseCount: nil, steps: 22_222, sleepHrOnly: row.sleepHrOnly)
        }

        for days in CoachPacketSettings.allowedRanges {
            h.packetSettings.rangeDays = days
            let start = h.clock.day(-(days - 1))
            let resolved = await h.repo.resolvedSteps(from: start, to: h.today)
            let expected = resolved.points.map { point -> CoachPacketStepDay in
                let source: CoachPacketStepSource = point.sourceKey == "steps_est" ? .strapEstimate
                    : point.source == Repository.appleHealthSource ? .appleHealth : .strap
                return CoachPacketStepDay(day: point.day, steps: point.value, source: source)
            }
            XCTAssertFalse(expected.isEmpty)
            let built = try await input(h.assembler())
            XCTAssertEqual(built.steps.sorted { $0.day < $1.day }, expected.sorted { $0.day < $1.day }, "\(days) days")
            XCTAssertFalse(built.steps.contains { $0.steps == 22_222 }, "DailyMetric.steps is not the packet's source")
        }
        let text = try await h.document().text
        XCTAssertFalse(text.contains("22222"), text)
    }

    // MARK: - Baseline band

    func testPacketBaselineBandEqualsTheRecoveryFactorBand() async throws {
        let h = try await H.empty(scorecard: false, suites: suites)
        let nights = (0..<19).map { index in
            DailyMetric(day: h.clock.day(index - 18), totalSleepMin: 440, efficiency: 0.9, deepMin: 60, remMin: 90,
                        lightMin: 250, disturbances: nil, restingHr: 52 + index % 5,
                        avgHrv: 52 + Double((index * 7) % 12), recovery: 60, strain: 40, exerciseCount: nil)
        }
        _ = try await h.store.upsertDailyMetrics(nights, deviceId: H.deviceId + "-noop")
        await h.repo.refresh()
        let resolved = try XCTUnwrap(h.repo.chargeBaselines)

        let built = try await input(h.assembler())
        let text = try await h.document().text
        for (state, baseline, label) in [(resolved.hrv, built.hrvBaseline, "HRV"),
                                         (resolved.restingHR, built.restingHrBaseline, "RHR")] {
            // The band the Recovery screen draws: the baseline plus or minus one sigma, from the one
            // function that screen calls.
            let band = try XCTUnwrap(ChargeTypicalBand.range(state), label)
            let sigma = Baselines.sigma(state)
            XCTAssertEqual(band, (state.baseline - sigma)...(state.baseline + sigma), label)
            XCTAssertEqual(baseline?.typical, band, "\(label): the packet carries that band and computes none")
            XCTAssertEqual(baseline?.center, state.baseline, label)

            let line = try XCTUnwrap(CoachPacketText.line(text, startingWith: "\(label): "))
            XCTAssertEqual(try firstGroup("\\(typical (\\d+ to \\d+),", in: line),
                           "\(Int(band.lowerBound.rounded())) to \(Int(band.upperBound.rounded()))", line)
        }
    }

    // MARK: - Strain scale and day values

    private func dayLine(_ text: String, _ day: String) throws -> String {
        try XCTUnwrap(CoachPacketText.line(text, startingWith: "  \(day): recovery "), "no line for \(day)")
    }

    func testPacketStrainEqualsTheEffortDisplayOnEachScale() async throws {
        let h = try await H.fixturePerson(scorecard: false, suites: suites)
        for scale in EffortScale.allCases {
            let assembler = h.assembler(scale: scale)
            let built = try await input(assembler)
            XCTAssertEqual(built.strainFactor, scale == .whoop ? UnitFormatter.effortScaleFactor : 1.0, "\(scale)")

            let text = try await h.document(assembler).text
            XCTAssertTrue(text.contains("strain (\(scale == .whoop ? "0-21 scale" : "0-100 scale"))"), text)
            for row in h.fixtureDays() {
                let printed = try firstGroup("strain ([^,]+),", in: try dayLine(text, row.day))
                let shown = row.strain.map {
                    // The app's readout, with the decimal separator of whatever locale the host uses.
                    UnitFormatter.effortDisplay($0, scale: scale).replacingOccurrences(of: ",", with: ".")
                } ?? "—"
                XCTAssertEqual(printed, shown, "\(row.day) on \(scale)")
            }
        }
    }

    func testPacketDayValuesEqualTheCoachContextValuesForTheSameRows() async throws {
        let h = try await H.fixturePerson(scorecard: false, suites: suites)
        let text = try await h.document(h.assembler(scale: .hundred)).text
        let engine = AICoachEngine(repo: h.repo)
        for row in h.fixtureDays() {
            let packet = try dayLine(text, row.day)
                .replacingOccurrences(of: " [sleep staged from heart rate only]", with: "")
            // The Coach's line for the same row, with the packet's three labels and day separator.
            let coach = "  " + engine.dayLine(row)
                .replacingOccurrences(of: ":, charge ", with: ": recovery ")
                .replacingOccurrences(of: ", effort ", with: ", strain ")
                .replacingOccurrences(of: ", rest ", with: ", sleep ")
            XCTAssertEqual(packet, coach, row.day)
        }
        // And the averages: the same rows, the same formatter, the packet's labels.
        let rows = h.fixtureDays()
        XCTAssertTrue(text.contains("averages over 13 of 14 days with data: "
            + CoachDayFormat.primaryAveragesLine(rows, style: .packet(strainFactor: 1.0)) + "\n"), text)
    }
}
