#if DEBUG
import SwiftUI
import StrandAnalytics
import StrandDesign
import WhoopStore

// DEBUG-only. `--demo-screen <name>` (see `DemoScreens` in StrandiOSApp.swift) opens the packet
// sheet in one state of `design/round-s2-coach-packet/`, so each frame can be reproduced in the
// simulator:
//
//   packet-b1    loading                          packet-b8    regenerating after a change
//   packet-b2    ready, 14 days                   packet-b9    copied
//   packet-b3    ready, 7 days                    packet-b10   copied, then a control changed
//   packet-b4    nothing measured in the range    packet-b11   share
//   packet-b5    scorecard off in the app         packet-b12   blocked
//   packet-b6    a section switched off           packet-b13   unavailable
//   packet-b7    every section off                packet-b14   larger than the budget
//   packet-b15, packet-b16, packet-b17            b2, b9 and b12 again, for the largest text size
//                                                 (pair them with the app's text-size argument)
//   packet-live  the real sheet on this simulator's own store and settings (not synthetic: pair it
//                with `-noop.coachPacketEnabled YES`). Compiled for the simulator only, because its
//                switches store the owner's choices
//
// EVERY VALUE IS SYNTHETIC: the "Fixture Person" all stages share (stage 1 specification §13,
// stage 2 §13), read on Sun 16 Mar 2031 at 07:42:10. Nothing is read from or written to the app's
// own store, settings or pasteboard: each state runs on a text rendered from the fixture, its own
// defaults suite and a pasteboard writer that writes nothing. Stripped from Release.

enum CoachPacketDemo {
    static func screen(named name: String) -> AnyView? {
        guard name.hasPrefix("packet-") else { return nil }
        switch name {
        case "packet-live":
            #if targetEnvironment(simulator)
            return AnyView(CoachPacketLiveDemo())
            #else
            return nil
            #endif
        case "packet-b1": return host(DemoFrame(holdsFromCall: 1))
        case "packet-b2", "packet-b15": return host(DemoFrame())
        case "packet-b3": return host(DemoFrame(rangeDays: 7))
        case "packet-b4": return host(DemoFrame(data: .none))
        case "packet-b5": return host(DemoFrame(scorecardOff: true))
        case "packet-b6": return host(DemoFrame(off: [.activity]))
        case "packet-b7": return host(DemoFrame(off: Set(CoachPacketSection.allCases)))
        case "packet-b8": return host(DemoFrame(holdsFromCall: 2, script: .changeRange(7)))
        case "packet-b9", "packet-b16": return host(DemoFrame(script: .copy))
        case "packet-b10": return host(DemoFrame(script: .copyThenSwitchOff(.trends)))
        case "packet-b11": return host(DemoFrame(sharesAtOnce: true))
        case "packet-b12", "packet-b17": return host(DemoFrame(phaseName: Fixture.accountAddress))
        case "packet-b13": return host(DemoFrame(data: .unreadable))
        case "packet-b14": return host(DemoFrame(overBudget: true))
        default: return nil
        }
    }

    private static func host(_ frame: DemoFrame) -> AnyView { AnyView(CoachPacketDemoHost(frame: frame)) }
}

// MARK: - A frame

/// What one demo frame fixes: the stored choices, the data, and what happens after the first load.
private struct DemoFrame {
    enum Source { case fixture, none, unreadable }
    enum Script { case none, copy, copyThenSwitchOff(CoachPacketSection), changeRange(Int) }

    var rangeDays = CoachPacketSettings.defaultRangeDays
    var off: Set<CoachPacketSection> = []
    var data = Source.fixture
    var scorecardOff = false
    var phaseName = Fixture.phaseName
    /// The first assembly, counted from 1, that never returns. Nil: every assembly returns.
    var holdsFromCall: Int?
    var overBudget = false
    var sharesAtOnce = false
    var script = Script.none
}

/// A pasteboard writer that writes nothing: the demo leaves the simulator's clipboard alone.
private struct SilentPasteboard: CoachPacketPasteboardWriting {
    func write(_ plan: CoachPacketCopyPlan) {}
}

/// Counts the assemblies of one frame.
@MainActor
private final class AssemblyCount {
    var value = 0
}

private struct CoachPacketDemoHost: View {
    let frame: DemoFrame
    @State private var model: CoachPacketModel?

    var body: some View {
        NoopTheme.canvas.ignoresSafeArea()
            .task { if model == nil { model = await Self.prepare(frame) } }
            .sheet(isPresented: Binding(get: { model != nil }, set: { _ in })) {
                if let model {
                    CoachPacketSheet(model: model, demo: CoachPacketSheetDemo(
                        scorecardEnabled: !frame.scorecardOff, timeZone: Fixture.zone, locale: Fixture.british,
                        sharesAtOnce: frame.sharesAtOnce))
                }
            }
    }

    /// The model of a frame, already walked to the state the frame shows.
    private static func prepare(_ scene: DemoFrame) async -> CoachPacketModel {
        let suite = "CoachPacketDemo"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let settings = CoachPacketSettings(defaults: defaults)
        settings.isEnabled = true
        settings.rangeDays = scene.rangeDays
        for section in scene.off { settings.setSection(section, on: false) }

        let count = AssemblyCount()
        let model = CoachPacketModel(
            assemble: {
                count.value += 1
                if let hold = scene.holdsFromCall, count.value >= hold {
                    // Never returns: the frame shows the sheet waiting.
                    while !Task.isCancelled { try? await Task.sleep(nanoseconds: 60_000_000_000) }
                }
                return Fixture.outcome(scene, settings: settings)
            },
            settings: settings, pasteboard: SilentPasteboard(),
            // Copy is tapped 20 seconds after the packet appears, as in the frames.
            now: { Fixture.generatedAt.addingTimeInterval(20) })

        switch scene.script {
        case .none:
            break
        case .copy:
            await model.load()
            model.copy()
        case .copyThenSwitchOff(let section):
            await model.load()
            model.copy()
            await model.setSection(section, on: false)
        case .changeRange(let days):
            await model.load()
            // Held at the second assembly: the earlier text stays on screen, dimmed.
            Task { await model.setRangeDays(days) }
            await Task.yield()
        }
        return model
    }
}

#if targetEnvironment(simulator)
/// The real sheet over the simulator's own store and settings.
private struct CoachPacketLiveDemo: View {
    var body: some View {
        NoopTheme.canvas.ignoresSafeArea()
            .sheet(isPresented: .constant(true)) { CoachPacketSheet() }
    }
}
#endif

// MARK: - The fixture (stage 1 specification §13, stage 2 §13)

private enum Fixture {
    static let zone = TimeZone(secondsFromGMT: 3_600) ?? .current
    static let british = Locale(identifier: "en_GB")
    /// 2031-03-16T07:42:10+01:00.
    static let generatedAt = Date(timeIntervalSince1970: 1_931_409_730)
    static let generatedAtText = "2031-03-16T07:42:10+01:00"
    static let today = "2031-03-16"
    static let phaseName = "Fixture cut"
    /// The invented account of specification §13.4. As a phase name it makes the scan block.
    static let accountAddress = "fixture.person@example.invalid"
    static let identifiers = ["FIXTURE-STRAP-0001", "Fixture Band", "00000000-0000-4000-8000-000000000001",
                              accountAddress, "Fixture Phone", "/Users/fixture"]

    static func day(_ from: String, _ offset: Int) -> String {
        CanonicalDay.key((CanonicalDay.number(from) ?? 0) + offset)
    }

    // MARK: Stage 1's person: weekly weigh-ins, lifts, protein, phase and rules

    static let weights = [100.0, 99.2, 98.4, 97.6, 97.5, 97.4, 97.3, 97.2, 97.1]
    static let waists = [100.0, 99.5, 99.0, 98.5, 98.0, 97.5, 97.0, 97.0, 97.0]
    /// Week number to the working sets of "Fixture Press" and "Fixture Row" on that week's Monday.
    static let lifts: [Int: (Double, Double)] = [
        -1: (60, 50), 0: (60, 50), 1: (60, 50), 2: (60, 50), 3: (60, 50), 4: (60, 50), 5: (62.5, 50),
        6: (62.5, 50), 7: (62.5, 52.5), 8: (62.5, 52.5), 9: (62.5, 52.5),
    ]
    /// Week number to the protein of the seven days before its weigh-in, oldest first.
    static let protein: [Int: [Double?]] = [
        2: [120, 120, 120, 80, 120, 120, 120], 3: [120, 120, 120, 80, 120, 120, 120],
        4: [120, 120, 120, 80, 120, 120, 120], 5: [120, 80, 80, 120, 80, 80, 120],
        6: [120, nil, 120, nil, nil, 120, nil],
    ]
    static let parameters = CutScorecardParameters(
        rateWindowWeeks: 4, waistWindowWeeks: 2, waistMinDecreaseCm: 0.5, liftDropTolerancePercent: 5,
        liftDropShare: 0.5, liftDropConsecutiveWeeks: 3, addCaloriesKcal: 300, slowLossThresholdKgPerWeek: 0.4,
        slowLossConsecutiveWeeks: 3, reduceCarbsKcal: 250, proteinFloorGrams: 100, proteinMinDaysPerWeek: 5,
        maxWeighInAgeWeeks: 1, maxProjectionWeeks: 104, targetToleranceKg: 0)

    /// The Wednesday of week `number`, counted from 1.
    static func weighDay(_ number: Int) -> String { day("2031-01-08", 7 * (number - 1)) }

    /// The scorecard as the app's one evaluation gives it for this person on `today`.
    static func scorecard(phaseName: String, measured: Bool) -> CoachPacketScorecard {
        var weightReadings: [CutScorecardReading] = []
        var waistReadings: [CutScorecardReading] = []
        var observations: [CutScorecardLiftObservation] = []
        var proteinDays: [CutScorecardProteinDay] = []
        if measured {
            for (index, weight) in weights.enumerated() {
                let weighed = weighDay(index + 1)
                weightReadings.append(CutScorecardReading(day: weighed, takenAt: index, value: weight))
                waistReadings.append(CutScorecardReading(day: weighed, takenAt: index, value: waists[index]))
            }
            // The extra Monday reading of week 3, which loses to Wednesday's.
            weightReadings.append(CutScorecardReading(day: "2031-01-20", takenAt: 0, value: 98.9))
            for (number, sets) in lifts {
                let monday = day("2031-01-06", 7 * (number - 1))
                observations.append(.init(day: monday, exercise: "Fixture Press", weightKg: sets.0))
                observations.append(.init(day: monday, exercise: "Fixture Row", weightKg: sets.1))
            }
            for (number, grams) in protein {
                for (index, amount) in grams.enumerated() {
                    guard let amount else { continue }
                    proteinDays.append(.init(day: day(weighDay(number), index - 7), grams: amount))
                }
            }
        }
        let phase = measured
            ? CutScorecardPhase(name: phaseName, startDay: "2031-01-06", targetWeightKg: 94.0,
                                rateLowPercentPerWeek: 0.40, rateHighPercentPerWeek: 1.20)
            : nil
        let input = CutScorecardInput(weights: weightReadings, waists: waistReadings, lifts: observations,
                                      proteinDays: proteinDays, phase: phase, parameters: parameters, today: today)
        let packetPhase = phase.map {
            CoachPacketPhase(name: $0.name, startDay: $0.startDay, targetWeightKg: $0.targetWeightKg,
                             rateLowPercentPerWeek: $0.rateLowPercentPerWeek,
                             rateHighPercentPerWeek: $0.rateHighPercentPerWeek)
        }
        return .evaluated(phase: packetPhase, result: CutScorecard.evaluate(input))
    }

    // MARK: Stage 2's additions: two weeks of daily rows, baselines, steps, workouts

    private static func row(_ offset: Int, _ recovery: Double?, _ strain: Double?, _ sleep: Double?,
                            _ deep: Double?, _ rem: Double?, _ light: Double?, _ efficiency: Double?,
                            _ hrv: Double?, _ restingHr: Int?, hrOnly: Bool? = nil) -> DailyMetric {
        DailyMetric(day: day(today, offset), totalSleepMin: sleep, efficiency: efficiency, deepMin: deep,
                    remMin: rem, lightMin: light, disturbances: nil, restingHr: restingHr, avgHrv: hrv,
                    recovery: recovery, strain: strain, exerciseCount: nil, sleepHrOnly: hrOnly)
    }

    /// Specification §13.2: 2031-03-07 has no row, 03-11 is staged from heart rate only and 03-13
    /// carries strain alone.
    static let days: [DailyMetric] = [
        row(-13, 62, 47, 444, 78, 102, 264, 0.91, 58, 54),
        row(-12, 71, 38, 462, 84, 108, 270, 0.93, 63, 52),
        row(-11, 55, 62, 402, 66, 90, 246, 0.88, 52, 56),
        row(-10, 48, 30, 378, 60, 84, 234, 0.86, 47, 58),
        row(-8, 66, 44, 450, 81, 105, 264, 0.92, 60, 53),
        row(-7, 74, 25, 480, 90, 114, 276, 0.94, 66, 51),
        row(-6, 60, 50, 432, 75, 99, 258, 0.90, 57, 54),
        row(-5, 58, 41, 420, nil, nil, nil, nil, 55, 55, hrOnly: true),
        row(-4, 64, 58, 438, 78, 96, 264, 0.91, 59, 54),
        row(-3, nil, 35, nil, nil, nil, nil, nil, nil, nil),
        row(-2, 69, 46, 456, 84, 102, 270, 0.92, 62, 52),
        row(-1, 72, 33, 468, 87, 108, 273, 0.93, 64, 52),
        row(0, 67, 6, 450, 81, 102, 267, 0.92, 61, 53),
    ]

    static let hrvBaseline = CoachPacketBaseline(center: 57.2, typical: 50.8...63.6, status: "trusted", nights: 21)
    static let restingHrBaseline = CoachPacketBaseline(center: 54.1, typical: 51.9...56.3, status: "trusted",
                                                       nights: 21)

    static let appleSteps: [Int: Double] = [-13: 9_120, -12: 11_240, -11: 8_460, -8: 12_080, -7: 6_540, -6: 9_870,
                                            -5: 10_310, -4: 8_890, -2: 9_640, -1: 13_020, 0: 1_480]
    static let estimatedSteps: [Int: Double] = [-10: 7_300, -3: 5_200]

    static var steps: [CoachPacketStepDay] {
        appleSteps.map { CoachPacketStepDay(day: day(today, $0.key), steps: $0.value, source: .appleHealth) }
            + estimatedSteps.map { CoachPacketStepDay(day: day(today, $0.key), steps: $0.value, source: .strapEstimate) }
    }

    static let workouts: [CoachPacketWorkout] = [
        CoachPacketWorkout(day: "2031-03-03", startMinuteOfDay: 18 * 60 + 10, sport: "strength", source: .liftLog,
                           durationMinutes: 62, avgHr: 108, energyKcal: 380, distanceKm: nil),
        CoachPacketWorkout(day: "2031-03-05", startMinuteOfDay: 7 * 60 + 5, sport: "cycling", source: .appleHealth,
                           durationMinutes: 45, avgHr: 132, energyKcal: 410, distanceKm: 18.4),
        CoachPacketWorkout(day: "2031-03-08", startMinuteOfDay: 9 * 60 + 30, sport: "hiking", source: .manual,
                           durationMinutes: 95, avgHr: nil, energyKcal: nil, distanceKm: nil),
        CoachPacketWorkout(day: "2031-03-10", startMinuteOfDay: 6 * 60 + 50, sport: "walking", source: .detected,
                           durationMinutes: 40, avgHr: 96, energyKcal: 170, distanceKm: 3.6),
        CoachPacketWorkout(day: "2031-03-12", startMinuteOfDay: 18 * 60 + 5, sport: "rowing", source: .whoop,
                           durationMinutes: 30, avgHr: 128, energyKcal: 300, distanceKm: nil),
    ]

    // MARK: The packet for a frame

    /// What an assembly would return for this frame's data and the stored choices: rendered by
    /// the app's renderer and scanned by the app's privacy scan.
    static func outcome(_ scene: DemoFrame, settings: CoachPacketSettings) -> CoachPacketOutcome {
        if scene.data == .unreadable { return .unavailable }
        let measured = scene.data == .fixture
        let rangeDays = settings.rangeDays
        let sections = settings.sections
        let input = CoachPacketInput(
            generatedAt: generatedAtText, rangeStartDay: day(today, -(rangeDays - 1)), rangeEndDay: today,
            sections: sections, days: measured ? days : [], strainFactor: UnitFormatter.effortScaleFactor,
            scorecard: scene.scorecardOff ? .switchedOff : scorecard(phaseName: scene.phaseName, measured: measured),
            body: measured ? [
                CoachPacketBodyReading(kind: .weight, value: 97.1, source: .labBook, day: "2031-03-05"),
                CoachPacketBodyReading(kind: .waist, value: 97.0, source: .labBook, day: "2031-03-05"),
            ] : [],
            hrvBaseline: measured ? hrvBaseline : nil, restingHrBaseline: measured ? restingHrBaseline : nil,
            steps: measured ? steps : [], workouts: measured ? workouts : [])
        let text = CoachPacket.render(input)
        let findings = CoachPacket.privacyViolations(in: text, identifiers: identifiers)
        guard findings.isEmpty else { return .blocked(findings: findings.count) }
        let byteCount = scene.overBudget ? CoachPacket.byteBudget(rangeDays: rangeDays) + 1 : text.utf8.count
        return .ready(CoachPacketDocument(text: text, byteCount: byteCount, generatedAt: generatedAt,
                                          rangeDays: rangeDays, sections: sections, nothingMeasured: !measured))
    }
}
#endif
