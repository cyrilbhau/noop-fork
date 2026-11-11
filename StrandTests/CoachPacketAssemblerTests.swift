// API ASSUMED BY THESE TESTS
//
// New, in Strand/Data/CoachPacketAssembler.swift (specification §8.4):
//
//     struct CoachPacketDocument: Equatable {
//         let text: String
//         let byteCount: Int                       // text.utf8.count
//         let generatedAt: Date                    // the one clock reading
//         let rangeDays: Int
//         let sections: Set<CoachPacketSection>
//         let nothingMeasured: Bool                // NOT IN §8.4, see behaviour 6
//     }
//     enum CoachPacketOutcome: Equatable {
//         case ready(CoachPacketDocument)
//         case blocked(findings: Int)              // the privacy scan found something; no text exists
//         case unavailable                         // the store could not be read
//     }
//     @MainActor struct CoachPacketAssembler {
//         init(repository: Repository, provider: BodyMeasurementProvider,
//              scorecardSettings: CutScorecardSettings, settings: CoachPacketSettings,
//              now: @escaping () -> Date = { Date() },
//              timeZone: @escaping () -> TimeZone = { TimeZone.current },
//              effortScale: @escaping () -> EffortScale,
//              identifiers: @escaping () -> [String])
//         func input() async -> CoachPacketInput?   // nil when the store could not be read
//         func assemble() async -> CoachPacketOutcome
//     }
//
// Behaviour assumed where the specification leaves it unstated:
//
//  1. `now()` and `timeZone()` are each called exactly once per `input()` and once per
//     `assemble()` (§8.4 step 1, "capture once"). `assemble()` is `input()`, then
//     `CoachPacket.render`, then the privacy scan over the rendered text.
//  2. `generatedAt` in the input is the local time in the captured zone with its numeric UTC offset
//     as "+hh:mm" or "-hh:mm", and "+00:00" for UTC (never "Z", never a zone name).
//  3. `input.days` holds the rows of `repository.days` whose day is inside the range and no other;
//     `input.steps` and `input.workouts` likewise hold nothing outside the range.
//  4. `input.body` holds at most one weight and one waist: `provider.current(kind, consumer:
//     .display)` with a `profileDefault` dropped, `labBook` → `.labBook`, `appleHealth` →
//     `.appleHealth`, `profile` → `.profile`, and the reading's own day (nil for the profile).
//  5. A workout's source token is `WorkoutSource.classify(row.source)` mapped `whoop` → `.whoop`,
//     `apple` → `.appleHealth`, `detected` → `.detected`, `manual` → `.manual`, `lifting` →
//     `.liftLog`, `activityFile` → `.activityFile`. `sport` is passed as stored.
//  6. `CoachPacketDocument.nothingMeasured` is true when the input holds no daily row, no step
//     day and no workout in the range, no body reading, and no weekly weigh-in point; false when
//     it holds any one of them. The sheet's "Nothing was measured in this range" caption (§10.2)
//     needs this fact and §8.4 gives the document no field for it; the design model
//     (design/round-s2-coach-packet/frames.js) carries the same flag on its assembled output.
//     These tests pin only the two ends: an empty store is true, the Fixture Person is false.
//  7. A stored `coachPacket.rangeDays` outside the allowed values assembles a 14-day packet.
//
// Not asserted, because no safe seam exists: `.unavailable` from the assembler itself. A
// repository with no store opens the app's own database path, which a test must not do. The
// model's handling of `.unavailable` is pinned in CoachPacketModelTests with an injected outcome.
// `CoachPacketAssembler.live()` is not called for the same reason (it needs `AppModel.shared`).

import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

// Stage 2 (coach packet), specification §8.4, §7.10, §7.11 and §12.3. Written before the
// implementation exists. Synthetic values only: the Fixture Person.
@MainActor
final class CoachPacketAssemblerTests: XCTestCase {
    private typealias H = CoachPacketHarness
    private let suites = CoachPacketSuites()
    private var savedStandard: [String: Any] = [:]
    private static let standardKeys = ["noop.coachEnabled", "ai.dataConsent"]

    override func setUp() {
        super.setUp()
        savedStandard = [:]
        for key in Self.standardKeys {
            if let value = UserDefaults.standard.object(forKey: key) { savedStandard[key] = value }
        }
    }

    override func tearDown() {
        for key in Self.standardKeys {
            if let value = savedStandard[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        suites.removeAll()
        super.tearDown()
    }

    private func instant(_ iso: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: iso), iso)
    }

    private func zone(_ identifier: String) throws -> TimeZone {
        try XCTUnwrap(TimeZone(identifier: identifier), identifier)
    }

    private func input(_ assembler: CoachPacketAssembler, file: StaticString = #filePath,
                       line: UInt = #line) async throws -> CoachPacketInput {
        let input = await assembler.input()
        return try XCTUnwrap(input, "the store was readable, so there is an input", file: file, line: line)
    }

    // MARK: - One clock, one zone

    func testOneClockGivesGeneratedAtTodayAndTheRange() async throws {
        let h = try await H.empty(scorecard: true, suites: suites)
        let fixed = try instant("2031-03-16T06:42:10Z")
        // A clock that jumps three days every time it is read: a second read would show.
        let clock = CoachPacketBox(fixed)
        clock.afterRead = { $0 = $0.addingTimeInterval(3 * 86_400) }
        let zoneBox = CoachPacketBox(try XCTUnwrap(TimeZone(secondsFromGMT: 3_600)))
        let assembler = h.assembler(now: { clock.read() }, zone: { zoneBox.read() })

        let built = try await input(assembler)
        XCTAssertEqual(clock.reads, 1, "one clock reading gives generatedAt, today and the range")
        XCTAssertEqual(zoneBox.reads, 1, "the zone is captured once")
        XCTAssertEqual(built.generatedAt, "2031-03-16T07:42:10+01:00")
        XCTAssertEqual(built.rangeEndDay, "2031-03-16")
        XCTAssertEqual(built.rangeStartDay, "2031-03-03")
        XCTAssertEqual(CoachPacket.dayKeys(from: built.rangeStartDay, to: built.rangeEndDay).count, 14)

        clock.value = fixed
        let document = try await h.document(assembler)
        XCTAssertEqual(clock.reads, 2, "one more reading for one more assembly")
        XCTAssertEqual(document.generatedAt, fixed)
        XCTAssertEqual(document.rangeDays, 14)
        let lines = CoachPacketText.lines(document.text)
        XCTAssertEqual(lines.first, "NOOP-COACH-PACKET v1")
        XCTAssertEqual(lines.dropFirst().first, "generated: 2031-03-16T07:42:10+01:00")
        XCTAssertEqual(lines.dropFirst(2).first,
                       "range: 2031-03-03..2031-03-16 (14 days; the last day is today and is partial)")
    }

    func testGeneratedAtCarriesTheOffsetAndNoZoneName() async throws {
        let h = try await H.empty(scorecard: false, suites: suites)
        let fixed = try instant("2031-03-16T06:42:10Z")
        let expected: [(String, String)] = [
            ("Asia/Kolkata", "2031-03-16T12:12:10+05:30"),
            ("America/St_Johns", "2031-03-16T04:12:10-02:30"),
            ("Pacific/Kiritimati", "2031-03-16T20:42:10+14:00"),
            ("UTC", "2031-03-16T06:42:10+00:00"),
        ]
        let shape = try NSRegularExpression(pattern: "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}[+-]\\d{2}:\\d{2}$")
        for (identifier, text) in expected {
            let zone = try zone(identifier)
            let built = try await input(h.assembler(now: { fixed }, zone: { zone }))
            XCTAssertEqual(built.generatedAt, text, identifier)
            let whole = NSRange(built.generatedAt.startIndex..., in: built.generatedAt)
            XCTAssertEqual(shape.numberOfMatches(in: built.generatedAt, range: whole), 1, built.generatedAt)
            for name in [identifier, "GMT", "UTC", "IST", "Z"] {
                XCTAssertFalse(built.generatedAt.contains(name), "\(built.generatedAt) names a zone (\(name))")
            }
        }
    }

    func testRangeAcrossADaylightSavingChangeHasTheRightDays() async throws {
        let h = try await H.empty(scorecard: false, suites: suites)
        let berlin = try zone("Europe/Berlin")          // clocks go forward on 2031-03-30
        let newYork = try zone("America/New_York")      // clocks go back on 2031-11-02

        // Three days after the spring change, at 08:30 local.
        var now = try instant("2031-04-02T06:30:00Z")
        var built = try await input(h.assembler(now: { now }, zone: { berlin }))
        XCTAssertEqual(built.generatedAt, "2031-04-02T08:30:00+02:00")
        XCTAssertEqual([built.rangeStartDay, built.rangeEndDay], ["2031-03-20", "2031-04-02"])
        XCTAssertEqual(CoachPacket.dayKeys(from: built.rangeStartDay, to: built.rangeEndDay).count, 14)

        // Half an hour into the day after the change: today is the local day, not the UTC one.
        now = try instant("2031-03-30T22:30:00Z")
        built = try await input(h.assembler(now: { now }, zone: { berlin }))
        XCTAssertEqual([built.rangeStartDay, built.rangeEndDay], ["2031-03-18", "2031-03-31"])

        // Twenty-eight days ending after the autumn change, late in the local evening.
        h.packetSettings.rangeDays = 28
        now = try instant("2031-11-05T04:30:00Z")
        built = try await input(h.assembler(now: { now }, zone: { newYork }))
        XCTAssertEqual(built.generatedAt, "2031-11-04T23:30:00-05:00")
        XCTAssertEqual([built.rangeStartDay, built.rangeEndDay], ["2031-10-08", "2031-11-04"])
        XCTAssertEqual(CoachPacket.dayKeys(from: built.rangeStartDay, to: built.rangeEndDay).count, 28)
    }

    func testZoneChangeBetweenTwoAssembliesMovesTheRangeWithTheNewToday() async throws {
        let h = try await H.empty(scorecard: false, suites: suites)
        let now = try instant("2031-03-16T23:30:00Z")
        let zoneBox = CoachPacketBox(H.utc)
        let assembler = h.assembler(now: { now }, zone: { zoneBox.read() })

        let first = try await input(assembler)
        XCTAssertEqual([first.rangeStartDay, first.rangeEndDay], ["2031-03-03", "2031-03-16"])
        XCTAssertEqual(first.generatedAt, "2031-03-16T23:30:00+00:00")

        zoneBox.value = try zone("Asia/Tokyo")
        let second = try await input(assembler)
        XCTAssertEqual([second.rangeStartDay, second.rangeEndDay], ["2031-03-04", "2031-03-17"])
        XCTAssertEqual(second.generatedAt, "2031-03-17T08:30:00+09:00")
    }

    // MARK: - Settings: sections and range

    func testSectionSwitchesAndRangeComeFromTheStoredSettings() async throws {
        let h = try await H.fixturePerson(scorecard: true, suites: suites)
        var built = try await input(h.assembler())
        XCTAssertEqual(built.sections, Set(CoachPacketSection.allCases), "every section is on by default")
        XCTAssertEqual([built.rangeStartDay, built.rangeEndDay], [h.clock.day(-13), h.today])

        h.packetSettings.setSection(.activity, on: false)
        h.packetSettings.setSection(.trends, on: false)
        h.packetSettings.rangeDays = 7
        built = try await input(h.assembler())
        XCTAssertEqual(built.sections, [.scorecard, .weighIns, .recoverySleep])
        XCTAssertEqual([built.rangeStartDay, built.rangeEndDay], [h.clock.day(-6), h.today])

        let document = try await h.document()
        XCTAssertEqual(document.rangeDays, 7)
        XCTAssertEqual(document.sections, [.scorecard, .weighIns, .recoverySleep])
        XCTAssertEqual(CoachPacketText.line(document.text, startingWith: "sections: "),
                       "sections: scorecard, weigh-ins, recovery-sleep")
        XCTAssertEqual(CoachPacketText.line(document.text, startingWith: "switched-off: "), "switched-off: trends, activity")
        XCTAssertFalse(document.text.contains("== ACTIVITY =="))
        XCTAssertFalse(document.text.contains("== TRENDS =="))
        XCTAssertTrue(document.text.contains("== RECOVERY AND SLEEP =="))
    }

    func testEachAllowedRangeCoversTodayAndTheDaysBeforeIt() async throws {
        let h = try await H.fixturePerson(scorecard: true, suites: suites)
        let rows = h.fixtureDays()
        for days in CoachPacketSettings.allowedRanges {
            h.packetSettings.rangeDays = days
            let built = try await input(h.assembler())
            let start = h.clock.day(-(days - 1))
            XCTAssertEqual([built.rangeStartDay, built.rangeEndDay], [start, h.today], "\(days) days")
            XCTAssertEqual(built.days, rows.filter { $0.day >= start && $0.day <= h.today },
                           "the rows inside the range, oldest first, and no other")
            XCTAssertTrue(built.steps.allSatisfy { $0.day >= start && $0.day <= h.today })
            XCTAssertTrue(built.workouts.allSatisfy { $0.day >= start && $0.day <= h.today })
            let document = try await h.document()
            XCTAssertEqual(document.rangeDays, days)
            XCTAssertEqual(CoachPacketText.section(document.text, "== RECOVERY AND SLEEP ==").filter { $0.hasPrefix("  ") }.count,
                           days, "one line for every calendar day of the range")
        }
        h.defaults.set(10, forKey: CoachPacketSettings.rangeDaysKey)
        let built = try await input(h.assembler())
        XCTAssertEqual(built.rangeStartDay, h.clock.day(-13), "a stored range that is not allowed assembles 14 days")
    }

    func testEverySectionOffStillAssemblesHeaderAndNotes() async throws {
        let h = try await H.fixturePerson(scorecard: true, suites: suites)
        for section in CoachPacketSection.allCases { h.packetSettings.setSection(section, on: false) }
        let document = try await h.document()
        XCTAssertEqual(document.sections, [])
        XCTAssertEqual(CoachPacketText.line(document.text, startingWith: "sections: "), "sections: none")
        XCTAssertEqual(CoachPacketText.lines(document.text).filter { $0.hasPrefix("== ") }, ["== NOTES =="])
    }

    // MARK: - Scorecard

    func testScorecardFlagOffYieldsSwitchedOff() async throws {
        let off = try await H.fixturePerson(scorecard: false, suites: suites)
        let built = try await input(off.assembler())
        XCTAssertEqual(built.scorecard, .switchedOff)
        let text = try await off.document().text
        XCTAssertEqual(CoachPacketText.section(text, "== SCORECARD =="),
                       ["not available: the scorecard is switched off in the app"])
        XCTAssertTrue(text.contains("weekly: not available (the scorecard is switched off in the app)"), text)

        let on = try await H.fixturePerson(scorecard: true, suites: suites)
        guard case .evaluated = try await input(on.assembler()).scorecard else {
            return XCTFail("with the scorecard flag on the packet carries the evaluation")
        }
    }

    // MARK: - Steps

    func testStepsAreClassifiedByKeyAndSource() async throws {
        let h = try await H.fixturePerson(scorecard: false, suites: suites)
        // A measured strap count on the day the fixture leaves empty, and one that outranks the
        // phone's count for the same day.
        _ = try await h.store.upsertMetricSeries(
            [MetricPoint(day: h.clock.day(-9), key: "steps", value: 4_400),
             MetricPoint(day: h.clock.day(-13), key: "steps", value: 9_050)], deviceId: Repository.whoopSource)
        // An estimate on a day the phone also counted: the phone's count is the day's value.
        _ = try await h.store.upsertMetricSeries(
            [MetricPoint(day: h.clock.day(-12), key: "steps_est", value: 3_000)], deviceId: Repository.whoopSource)

        let built = try await input(h.assembler())
        let steps = built.steps.sorted { $0.day < $1.day }
        XCTAssertEqual(Set(steps.map(\.day)).count, steps.count, "one value a day")

        func expected(_ offset: Int, _ value: Double, _ source: CoachPacketStepSource) -> CoachPacketStepDay {
            CoachPacketStepDay(day: h.clock.day(offset), steps: value, source: source)
        }
        XCTAssertTrue(steps.contains(expected(-9, 4_400, .strap)), "\(steps)")
        XCTAssertTrue(steps.contains(expected(-13, 9_050, .strap)), "measured strap steps outrank the phone's")
        XCTAssertTrue(steps.contains(expected(-12, 11_240, .appleHealth)), "the phone's count outranks an estimate")
        XCTAssertTrue(steps.contains(expected(-10, 7_300, .strapEstimate)), "steps_est is the estimate")
        XCTAssertTrue(steps.contains(expected(0, 1_480, .appleHealth)))
        XCTAssertEqual(steps.count, 14, "every day of the range now has one value")

        let text = try await h.document().text
        XCTAssertTrue(text.contains("  \(h.clock.day(-9)): 4400 strap\n"), text)
        XCTAssertTrue(text.contains("  \(h.clock.day(-10)): ~7300 strap-estimate\n"), text)
        XCTAssertTrue(text.contains("  \(h.clock.day(-12)): 11240 apple-health\n"), text)
        XCTAssertTrue(text.contains("  \(h.today): 1480 apple-health (today so far)\n"), text)
    }

    // MARK: - Workouts

    func testWorkoutsTakeTheirLocalDayAndMinuteInTheGivenZone() async throws {
        let h = try await H.empty(scorecard: false, suites: suites)
        // 23:30 UTC three days before today.
        _ = try await h.store.upsertWorkouts(
            [h.workout(-3, hour: 23, minute: 30, sport: "walking", source: "manual", minutes: 30, avgHr: 96,
                       kcal: 170, distanceM: 3_600)], deviceId: H.deviceId)
        let cases: [(TimeZone, Int, Int)] = [
            (H.utc, -3, 23 * 60 + 30),
            (try zone("Asia/Tokyo"), -2, 8 * 60 + 30),
            (try zone("Asia/Kolkata"), -2, 5 * 60),
            (try XCTUnwrap(TimeZone(secondsFromGMT: -5 * 3_600)), -3, 18 * 60 + 30),
        ]
        for (zone, offset, minute) in cases {
            let built = try await input(h.assembler(zone: { zone }))
            XCTAssertEqual(built.workouts, [
                CoachPacketWorkout(day: h.clock.day(offset), startMinuteOfDay: minute, sport: "walking",
                                   source: .manual, durationMinutes: 30, avgHr: 96, energyKcal: 170, distanceKm: 3.6),
            ], zone.identifier)
        }
        let text = try await h.document().text
        XCTAssertTrue(text.contains("  \(h.clock.day(-3)) 23:30 walking, 30 min, avg HR 96 bpm, 170 kcal, 3.60 km [manual]\n"), text)
    }

    func testWorkoutSourcesComeFromTheClassifier() async throws {
        let h = try await H.fixturePerson(scorecard: false, suites: suites)
        _ = try await h.store.upsertWorkouts(
            [h.workout(-2, hour: 10, minute: 0, sport: "running", source: "activity-file", minutes: 25, avgHr: 150,
                       kcal: 260, distanceM: 4_200)], deviceId: "activity-file")
        let built = try await input(h.assembler())
        let bySport = Dictionary(uniqueKeysWithValues: built.workouts.map { ($0.sport, $0.source) })
        XCTAssertEqual(bySport, ["strength": .liftLog, "cycling": .appleHealth, "hiking": .manual,
                                 "walking": .detected, "rowing": .whoop, "running": .activityFile])

        // Every row the repository returns for the range, each through the one classifier.
        func token(_ source: WorkoutSource) -> CoachPacketWorkoutSource {
            switch source {
            case .whoop: return .whoop
            case .apple: return .appleHealth
            case .detected: return .detected
            case .manual: return .manual
            case .lifting: return .liftLog
            case .activityFile: return .activityFile
            }
        }
        let rows = await h.repo.workoutRows(days: 15)
        XCTAssertEqual(rows.count, 6)
        XCTAssertEqual(bySport, Dictionary(uniqueKeysWithValues: rows.map { ($0.sport, token(WorkoutSource.classify($0.source))) }))

        let hiking = try XCTUnwrap(built.workouts.first { $0.sport == "hiking" })
        XCTAssertEqual(hiking, CoachPacketWorkout(day: h.clock.day(-8), startMinuteOfDay: 9 * 60 + 30, sport: "hiking",
                                                  source: .manual, durationMinutes: 95, avgHr: nil, energyKcal: nil,
                                                  distanceKm: nil), "an absent value stays absent")
        let cycling = try XCTUnwrap(built.workouts.first { $0.sport == "cycling" })
        XCTAssertEqual(cycling.distanceKm, 18.4)
        XCTAssertEqual(cycling.durationMinutes, 45)

        let text = try await h.document().text
        XCTAssertEqual(CoachPacketText.section(text, "== ACTIVITY ==").filter { $0.contains(" min, ") }, [
            "  \(h.clock.day(-13)) 18:10 strength, 62 min, avg HR 108 bpm, 380 kcal [lift-log]",
            "  \(h.clock.day(-11)) 07:05 cycling, 45 min, avg HR 132 bpm, 410 kcal, 18.40 km [apple-health]",
            "  \(h.clock.day(-8)) 09:30 hiking, 95 min, avg HR —, — kcal [manual]",
            "  \(h.clock.day(-6)) 06:50 walking, 40 min, avg HR 96 bpm, 170 kcal, 3.60 km [detected]",
            "  \(h.clock.day(-4)) 18:05 rowing, 30 min, avg HR 128 bpm, 300 kcal [whoop]",
            "  \(h.clock.day(-2)) 10:00 running, 25 min, avg HR 150 bpm, 260 kcal, 4.20 km [activity-file]",
        ])
    }

    // MARK: - Baselines

    /// Nineteen of the wearer's own nights inside the baseline window, then a refresh: the
    /// repository resolves the baselines the recovery score uses.
    private func seedNights(_ h: CoachPacketHarness, count: Int) async throws {
        let nights = (0..<count).map { index in
            DailyMetric(day: h.clock.day(index - (count - 1)), totalSleepMin: 440, efficiency: 0.9, deepMin: 60,
                        remMin: 90, lightMin: 250, disturbances: nil, restingHr: 52 + index % 5,
                        avgHrv: 52 + Double((index * 7) % 12), recovery: 60, strain: 40, exerciseCount: nil)
        }
        _ = try await h.store.upsertDailyMetrics(nights, deviceId: H.deviceId + "-noop")
        await h.repo.refresh()
    }

    func testBaselinesCarryTheRangeChargeTypicalBandGives() async throws {
        let h = try await H.empty(scorecard: false, suites: suites)
        try await seedNights(h, count: 19)
        let resolved = try XCTUnwrap(h.repo.chargeBaselines)
        XCTAssertTrue(resolved.hrv.usable && resolved.restingHR.usable, "the fixture makes both baselines usable")

        let built = try await input(h.assembler())
        for (state, baseline, unit, label) in [(resolved.hrv, built.hrvBaseline, "ms", "HRV"),
                                               (resolved.restingHR, built.restingHrBaseline, "bpm", "RHR")] {
            let band = try XCTUnwrap(ChargeTypicalBand.range(state))
            XCTAssertEqual(baseline, CoachPacketBaseline(center: state.baseline, typical: band,
                                                         status: state.status.rawValue, nights: state.nValid), label)
            // The text prints the bounds it was given, rounded, and nothing computed a second time.
            let text = try await h.document().text
            let prefix = "\(label): baseline \(Int(state.baseline.rounded())) \(unit) (typical "
                + "\(Int(band.lowerBound.rounded())) to \(Int(band.upperBound.rounded())), "
                + "\(state.status.rawValue), \(state.nValid) nights); "
            XCTAssertTrue(CoachPacketText.line(text, startingWith: "\(label): ")?.hasPrefix(prefix) ?? false,
                          "expected \(prefix) in:\n\(text)")
        }
    }

    func testAnUnusableBaselineHasNoTypicalRange() async throws {
        let h = try await H.empty(scorecard: false, suites: suites)
        try await seedNights(h, count: 2)
        let resolved = try XCTUnwrap(h.repo.chargeBaselines)
        XCTAssertFalse(resolved.hrv.usable, "two nights do not make a baseline")
        XCTAssertNil(ChargeTypicalBand.range(resolved.hrv))

        let built = try await input(h.assembler())
        XCTAssertEqual(built.hrvBaseline, CoachPacketBaseline(center: resolved.hrv.baseline, typical: nil,
                                                              status: resolved.hrv.status.rawValue,
                                                              nights: resolved.hrv.nValid))
        XCTAssertNil(built.restingHrBaseline?.typical)
        let text = try await h.document().text
        let line = try XCTUnwrap(CoachPacketText.line(text, startingWith: "HRV: "))
        XCTAssertTrue(line.hasPrefix("HRV: baseline not established (\(resolved.hrv.status.rawValue), \(resolved.hrv.nValid) nights); "), line)
        XCTAssertFalse(line.contains("typical"), line)
        XCTAssertFalse(line.contains("vs baseline"), line)
    }

    func testARepositoryWithNoResolvedBaselinesHasNone() async throws {
        let h = try await H.empty(scorecard: false, suites: suites)
        XCTAssertNil(h.repo.chargeBaselines, "nothing was refreshed")
        let built = try await input(h.assembler())
        XCTAssertNil(built.hrvBaseline)
        XCTAssertNil(built.restingHrBaseline)
        let text = try await h.document().text
        XCTAssertEqual(CoachPacketText.line(text, startingWith: "HRV: "), "HRV: baseline not available; range mean — over 0 nights")
        XCTAssertEqual(CoachPacketText.line(text, startingWith: "RHR: "), "RHR: baseline not available; range mean — over 0 nights")
    }

    // MARK: - Body measurements

    func testUnsetProfileWeightIsNotPrinted() async throws {
        let h = try await H.empty(scorecard: true, suites: suites)
        await h.provider.refresh()
        XCTAssertEqual(h.provider.current(.weight, consumer: .display)?.source, .profileDefault)
        var built = try await input(h.assembler())
        XCTAssertEqual(built.body, [], "a profile that was never written is not the owner's weight")
        var text = try await h.document().text
        XCTAssertTrue(text.contains("current weight: —\n"), text)
        XCTAssertTrue(text.contains("current waist: —\n"), text)
        XCTAssertFalse(text.contains("75.0 kg"), "the default of 75 kg is never printed: \(text)")

        // Once the owner has set the profile, it is the current value and has no day.
        h.defaults.set(80.0, forKey: "profile.weightKg")
        h.defaults.set(90.0, forKey: "profile.waistCm")
        built = try await input(h.assembler())
        XCTAssertEqual(built.body.sorted { $0.kind.rawValue > $1.kind.rawValue }, [
            CoachPacketBodyReading(kind: .weight, value: 80, source: .profile, day: nil),
            CoachPacketBodyReading(kind: .waist, value: 90, source: .profile, day: nil),
        ])
        text = try await h.document().text
        XCTAssertTrue(text.contains("current weight: 80.0 kg (profile)\n"), text)
        XCTAssertTrue(text.contains("current waist: 90.0 cm (profile)\n"), text)
    }

    // MARK: - Absent data prints nothing

    func testAnEmptyStorePrintsDashesAndNoInventedValue() async throws {
        let h = try await H.empty(scorecard: true, suites: suites)
        let built = try await input(h.assembler())
        XCTAssertEqual(built.days, [])
        XCTAssertEqual(built.body, [])
        XCTAssertEqual(built.steps, [])
        XCTAssertEqual(built.workouts, [])

        let document = try await h.document()
        XCTAssertTrue(document.nothingMeasured)
        let text = document.text
        let dashes = "recovery —, strain —, sleep —, deep —, REM —, light —, eff —, HRV —, RHR —"
        let dayLines = CoachPacketText.section(text, "== RECOVERY AND SLEEP ==").filter { $0.hasPrefix("  ") }
        XCTAssertEqual(dayLines, (0..<14).map { "  \(h.clock.day($0 - 13)): \(dashes)" })
        XCTAssertTrue(text.contains("averages: no data in range\n"), text)
        XCTAssertTrue(text.contains("weekly: no weigh-ins yet\n"), text)
        XCTAssertTrue(text.contains("steps average: — (no step data in range)\n"), text)
        XCTAssertTrue(text.contains("workouts: none recorded in range\n"), text)
        let stepLines = CoachPacketText.section(text, "== ACTIVITY ==").filter { $0.hasPrefix("  ") }
        XCTAssertEqual(stepLines, (0..<14).map { "  \(h.clock.day($0 - 13)): —" }, "a missing day is a dash, never 0")

        let person = try await H.fixturePerson(scorecard: true, suites: suites)
        let measured = try await person.document()
        XCTAssertFalse(measured.nothingMeasured)
    }

    /// The row list has a gap on one day and partly measured rows on two more; the steps have a
    /// gap of their own. Each prints its dash and no neighbour's value.
    func testUnmeasuredDaysOfTheFixturePrintTheirDashes() async throws {
        let h = try await H.fixturePerson(scorecard: true, suites: suites)
        let text = try await h.document(h.assembler(scale: .whoop)).text
        let dashes = "recovery —, strain —, sleep —, deep —, REM —, light —, eff —, HRV —, RHR —"
        XCTAssertTrue(text.contains("  \(h.clock.day(-9)): \(dashes)\n"), text)
        XCTAssertTrue(text.contains("  \(h.clock.day(-3)): recovery —, strain 7.3, sleep —, deep —, REM —, light —, eff —, HRV —, RHR —\n"), text)
        XCTAssertTrue(text.contains("  \(h.clock.day(-5)): recovery 58, strain 8.6, sleep 7.0h, deep —, REM —, light —, eff —, HRV 55ms, RHR 55bpm [sleep staged from heart rate only]\n"), text)
        XCTAssertTrue(text.contains("averages over 13 of 14 days with data: recovery: 64, strain: 8.3, sleep: 7.3h, HRV: 59 ms, RHR: 54 bpm\n"), text)
        XCTAssertTrue(text.contains("  \(h.clock.day(-9)): —\n"), "no step value that day: \(text)")
        XCTAssertTrue(text.contains("steps average: 9306 over 12 of 13 full days (apple-health 10, strap-estimate 2)\n"), text)
    }

    // MARK: - The privacy scan fails closed

    func testAPlantedDeviceIdentifierBlocksThePacket() async throws {
        let h = try await H.fixturePerson(scorecard: true, suites: suites)
        h.seedPhaseAndRules(name: "FIXTURE-STRAP-0001 cut")

        // The name is printed, so without the identifier list the packet exists and carries it.
        let clean = try await h.document(h.assembler())
        XCTAssertTrue(clean.text.contains("phase: \"FIXTURE-STRAP-0001 cut\""), clean.text)

        for identifiers in [["FIXTURE-STRAP-0001"], ["fixture-strap-0001"], ["Fixture Band", "FIXTURE-STRAP-0001"]] {
            let outcome = await h.assembler(identifiers: identifiers).assemble()
            guard case let .blocked(findings) = outcome else {
                XCTFail("the packet names a registered device, so it must not exist: \(outcome)")
                continue
            }
            XCTAssertGreaterThanOrEqual(findings, 1)
        }
    }

    func testAnAccountAddressOrAPeripheralIdentifierInFreeTextBlocksThePacket() async throws {
        for planted in ["fixture.person@example.invalid", "00000000-0000-4000-8000-000000000001",
                        "/Users/fixture/notes"] {
            let h = try await H.fixturePerson(scorecard: true, suites: suites)
            _ = try await h.store.upsertWorkouts(
                [h.workout(-2, hour: 10, minute: 0, sport: planted, source: "manual", minutes: 25, avgHr: nil,
                           kcal: nil, distanceM: nil)], deviceId: H.deviceId)
            let outcome = await h.assembler().assemble()
            guard case .blocked = outcome else {
                XCTFail("\(planted) in a workout name must block the packet: \(outcome)")
                continue
            }
        }
    }

    /// The scan reads the text that would leave. With the section that carries the name switched
    /// off, the name is not in the text and the packet exists.
    func testTheScanReadsTheTextThatWouldLeave() async throws {
        let h = try await H.fixturePerson(scorecard: true, suites: suites)
        h.seedPhaseAndRules(name: "FIXTURE-STRAP-0001 cut")
        h.packetSettings.setSection(.scorecard, on: false)
        let document = try await h.document(h.assembler(identifiers: ["FIXTURE-STRAP-0001"]))
        XCTAssertFalse(document.text.contains("FIXTURE-STRAP-0001"))
        XCTAssertEqual(CoachPacket.privacyViolations(in: document.text, identifiers: ["FIXTURE-STRAP-0001"]), [])
    }

    func testAReadyPacketHasNoPrivacyFindingAndNoRawNamespace() async throws {
        let h = try await H.fixturePerson(scorecard: true, suites: suites)
        let identifiers = ["FIXTURE-STRAP-0001", "Fixture Band", "00000000-0000-4000-8000-000000000001",
                           "fixture.person@example.invalid", "Fixture Phone", "/Users/fixture"]
        let document = try await h.document(h.assembler(identifiers: identifiers))
        XCTAssertEqual(CoachPacket.privacyViolations(in: document.text, identifiers: identifiers), [])
        for raw in ["my-whoop", "-noop", "apple_health", "nutrition-csv"] {
            XCTAssertFalse(document.text.contains(raw), "a raw storage name (\(raw)) reached the text")
        }
    }

    // MARK: - Size, determinism, no writes

    func testTheDocumentCarriesItsSizeAndIsWithinTheBudgetForEachRange() async throws {
        let h = try await H.fixturePerson(scorecard: true, suites: suites)
        for days in CoachPacketSettings.allowedRanges {
            h.packetSettings.rangeDays = days
            let document = try await h.document()
            XCTAssertEqual(document.byteCount, document.text.utf8.count)
            XCTAssertLessThanOrEqual(document.byteCount, CoachPacket.byteBudget(rangeDays: days), "\(days) days")
            XCTAssertEqual(CoachPacket.byteBudget(rangeDays: days), 8_000 + 220 * days)
        }
    }

    func testAssembleRendersTheInputItBuilt() async throws {
        let h = try await H.fixturePerson(scorecard: true, suites: suites)
        let assembler = h.assembler(scale: .whoop)
        let built = try await input(assembler)
        let document = try await h.document(assembler)
        XCTAssertEqual(document.text, CoachPacket.render(built), "the text is the renderer's, for the one input")
        XCTAssertEqual(document.generatedAt, h.clock.now)
        XCTAssertTrue(document.text.hasSuffix("end of NOOP-COACH-PACKET v1\n"))
        XCTAssertFalse(document.text.hasSuffix("\n\n"))
    }

    func testAFixedClockGivesTheSameBytesEveryTime() async throws {
        let h = try await H.fixturePerson(scorecard: true, suites: suites)
        let assembler = h.assembler(scale: .whoop)
        let first = await assembler.assemble()
        let second = await assembler.assemble()
        let third = await h.assembler(scale: .whoop).assemble()
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, third, "a second assembler over the same state gives the same packet")
        guard case let .ready(document) = first else { return XCTFail("\(first)") }
        let again = try await h.document(assembler)
        XCTAssertEqual(Data(document.text.utf8), Data(again.text.utf8))
    }

    /// What the store and the defaults hold, as text, for a before-and-after comparison.
    private func snapshot(_ h: CoachPacketHarness) async throws -> [String] {
        var out: [String] = []
        let domain = h.defaults.persistentDomain(forName: try XCTUnwrap(suites.names.last)) ?? [:]
        out.append(try PropertyListSerialization.data(fromPropertyList: domain, format: .xml, options: 0)
            .base64EncodedString())
        for key in ["weight", "waist"] {
            out.append("\(try await h.store.labMarkers(deviceId: H.deviceId, markerKey: key))")
        }
        for id in [H.deviceId, H.deviceId + "-noop", "apple-health", "lifting", "activity-file"] {
            out.append("\(try await h.store.workouts(deviceId: id, from: 0, to: Int.max / 2, limit: 5_000))")
            out.append("\(try await h.store.dailyMetrics(deviceId: id, from: "0000-01-01", to: "9999-12-31"))")
            for key in ["steps", "steps_est", "weight", "protein_g"] {
                out.append("\(try await h.store.metricSeries(deviceId: id, key: key, from: "0000-01-01", to: "9999-12-31"))")
            }
        }
        // Field by field: a device's capabilities are a set, whose printed order is not stable.
        let devices = try DeviceRegistryStore(dbQueue: h.store.registryWriter).all()
        out.append(devices.map { device in
            let capabilities = device.capabilities.map { "\($0)" }.sorted().joined(separator: ",")
            return "\(device.id)|\(device.brand)|\(device.model)|\(device.nickname ?? "-")|\(device.peripheralId ?? "-")"
                + "|\(device.sourceKind)|\(device.status)|\(device.addedAt)|\(device.lastSeenAt)|\(capabilities)"
        }.joined(separator: ";"))
        return out
    }

    func testAssemblyWritesNothing() async throws {
        let h = try await H.fixturePerson(scorecard: true, suites: suites)
        let before = try await snapshot(h)
        _ = try await input(h.assembler())
        _ = await h.assembler(scale: .whoop).assemble()
        _ = await h.assembler(identifiers: ["Fixture cut"]).assemble()     // a blocked assembly too
        let after = try await snapshot(h)
        XCTAssertEqual(after, before, "assembling a packet changed the store or the defaults")
        XCTAssertEqual(h.repo.days, h.fixtureDays(), "the repository's rows are read, not replaced")
        // The assembler refreshes the provider, which reads; the values it holds do not move.
        XCTAssertEqual(h.provider.current(.weight, consumer: .display)?.value, 97.1)
    }

    // MARK: - Independent of the in-app Coach

    /// Specification §8.4 and P11: the packet needs neither the Coach switch nor the Coach's data
    /// consent, because the app sends it nowhere.
    func testAssemblyWorksWithTheCoachSwitchOffAndNoConsent() async throws {
        let h = try await H.fixturePerson(scorecard: true, suites: suites)
        UserDefaults.standard.set(true, forKey: "noop.coachEnabled")
        UserDefaults.standard.set(true, forKey: "ai.dataConsent")
        let with = await h.assembler().assemble()

        UserDefaults.standard.set(false, forKey: "noop.coachEnabled")
        UserDefaults.standard.set(false, forKey: "ai.dataConsent")
        let without = await h.assembler().assemble()
        guard case .ready = without else { return XCTFail("the packet needs no Coach setting: \(without)") }
        XCTAssertEqual(with, without, "neither setting changes a byte of the packet")
    }
}
