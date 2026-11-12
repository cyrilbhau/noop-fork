// API ASSUMED BY THESE TESTS
//
// None that is new. Every call below exists today and must keep its signature across the stage 2
// extraction (specification §8.1):
//
//     AICoachEngine.init(repo:)                       // the engine over a repository
//     AICoachEngine.buildContext() -> String          // the per-day lines and the averages
//     AICoachEngine.buildFullContext() async -> String
//     AICoachEngine.dayLine(_:) -> String             // stays an internal method
//     AICoachEngine.efficiencyPercentOrDash(_:) -> String
//     AICoachEngine.bodyMeasurements                  // the provider behind ruling R41
//     AICoachEngine.includeOnDeviceSignals
//     Repository.days                                 // settable
//
// The one new name is a string, the stage 2 flag key "noop.coachPacketEnabled", written straight
// into the defaults so that this file compiles before `CoachPacketSettings` exists.

import XCTest
import WhoopStore
import StrandAnalytics
import StrandImport
@testable import Strand

// Stage 2 (coach packet), specification §8.1, §12.1 ("frozen legacy") and §12.2: THE IN-APP COACH
// CONTEXT IS BYTE-IDENTICAL BEFORE AND AFTER THE SHARED-FORMATTER EXTRACTION.
//
// These tests pass on the code as it stands before the extraction. That is their purpose. They
// must still pass after it, and after stage 3's line and stage 4's edit to the same file.
//
// Two proofs, because a recording alone cannot cover an input it does not list:
//
//  1. RECORDED TEXT. `CoachContextRecorded.texts` (CoachContextByteIdentityRecorded.swift) holds
//     the text the untouched code produced for each store state in `stateNames`, captured by
//     running that code in a throwaway test on the tree after the Lab Book ownership change had
//     merged (commit 2353b02d) and pasted without edits. Nothing in it was typed by hand.
//  2. FROZEN COPY. `FrozenLegacyCoachContext` below is a verbatim copy of `buildContext()` and of
//     the day-line and averages helpers of `Strand/AI/AICoach.swift` at that commit, taking the
//     rows as a parameter. Seeded random rows and row lists are run through both. It is the
//     oracle and is never edited.
//
// Day tokens. `buildContext()` reads `Repository.days`, which is settable, so most states use the
// fixed 2031 Fixture Person (specification §13.2) and their recordings are literal. The states
// that read the store (workouts, the Lab Book, a refreshed repository) are windowed on the real
// clock (stage 1 ruling R31), so their days move. Their recordings carry a token where a day was
// printed: `{D-3}` is the UTC day key three days before the harness's "today", `{W-3}` the
// device-zone day of 12:00 UTC on that day. The test substitutes the tokens and compares whole
// strings; no other part of a recording is ever rewritten.
//
// Synthetic values only: the one Fixture Person.

// MARK: - The frozen copy

/// `AICoachEngine.buildContext()` and its formatting helpers as they stood before the extraction,
/// copied verbatim (comments shortened), with `repo.days` as the parameter `days`. NEVER EDITED.
private enum FrozenLegacyCoachContext {
    static func buildContext(_ days: [DailyMetric]) -> String {
        var lines: [String] = ["USER BIOMETRIC SUMMARY (the user's own wearable data):"]

        guard !days.isEmpty else {
            return """
            USER BIOMETRIC SUMMARY:
            No wearable data is available yet. Acknowledge this and give general, encouraging guidance \
            while inviting the user to sync their device so future advice can reference real numbers.
            """
        }

        // Last ~14 days, newest first for readability.
        let recent = Array(days.suffix(14)).reversed()
        lines.append("")
        lines.append("Recent days (newest first) — charge(0-100), effort(0-100), rest/sleep(h), "
                     + "deep/REM/light(h), eff(%), HRV(ms), RHR(bpm). A dash means NOT MEASURED, not zero:")
        for d in recent {
            lines.append("  " + dayLine(d))
        }

        // 30-day averages.
        let last30 = Array(days.suffix(30))
        lines.append("")
        lines.append("30-day averages:")
        lines.append("  charge: \(avgInt(last30.compactMap { $0.recovery }))"
                     + ", effort: \(avgOne(last30.compactMap { $0.strain }))"
                     + ", sleep: \(avgSleepHours(last30))h"
                     + ", HRV: \(avgInt(last30.compactMap { $0.avgHrv })) ms"
                     + ", RHR: \(avgInt(last30.compactMap { $0.restingHr.map(Double.init) })) bpm")
        lines.append("  SpO2: \(avgInt(last30.compactMap { $0.spo2Pct }))%"
                     + ", respiration: \(avgOne(last30.compactMap { $0.respRateBpm }))/min"
                     + ", skin-temp deviation: \(avgOne(last30.compactMap { $0.skinTempDevC }))°C"
                     + ", steps: \(avgInt(last30.compactMap { $0.steps.map(Double.init) }))/day"
                     + ", active energy: \(avgInt(last30.compactMap { $0.activeKcalEst }))kcal/day")

        return lines.joined(separator: "\n")
    }

    static func dayLine(_ d: DailyMetric) -> String {
        var parts: [String] = [d.day + ":"]
        parts.append("charge " + (d.recovery.map { "\(Int($0.rounded()))" } ?? "—"))
        parts.append("effort " + (d.strain.map { String(format: "%.1f", $0) } ?? "—"))
        parts.append("rest " + (d.totalSleepMin.map { String(format: "%.1fh", $0 / 60) } ?? "—"))
        parts.append("deep " + hoursOrDash(d.deepMin))
        parts.append("REM " + hoursOrDash(d.remMin))
        parts.append("light " + hoursOrDash(d.lightMin))
        parts.append("eff " + efficiencyPercentOrDash(d.efficiency))
        parts.append("HRV " + (d.avgHrv.map { "\(Int($0.rounded()))ms" } ?? "—"))
        parts.append("RHR " + (d.restingHr.map { "\($0)bpm" } ?? "—"))
        return parts.joined(separator: ", ")
    }

    static func hoursOrDash(_ minutes: Double?) -> String {
        minutes.map { String(format: "%.1fh", $0 / 60) } ?? "—"
    }

    static func efficiencyPercentOrDash(_ raw: Double?) -> String {
        guard var e = raw, e > 0 else { return "—" }
        if e > 1.5 { e /= 100 }
        guard e > 0, e <= 1 else { return "—" }
        return "\(Int((e * 100).rounded()))%"
    }

    static func avgOne(_ xs: [Double]) -> String {
        guard !xs.isEmpty else { return "—" }
        return String(format: "%.1f", xs.reduce(0, +) / Double(xs.count))
    }

    static func avgInt(_ xs: [Double]) -> String {
        guard !xs.isEmpty else { return "—" }
        return "\(Int((xs.reduce(0, +) / Double(xs.count)).rounded()))"
    }

    static func avgSleepHours(_ days: [DailyMetric]) -> String {
        let mins = days.compactMap { $0.totalSleepMin }
        guard !mins.isEmpty else { return "—" }
        return String(format: "%.1f", (mins.reduce(0, +) / Double(mins.count)) / 60)
    }
}

// MARK: - Fixture rows

/// The daily rows these states are built from. Every value is invented.
private enum ContextRows {
    static func row(_ day: String, _ recovery: Double?, _ strain: Double?, _ sleep: Double?,
                    _ deep: Double?, _ rem: Double?, _ light: Double?, _ efficiency: Double?,
                    _ hrv: Double?, _ restingHr: Int?, hrOnly: Bool? = nil,
                    spo2: Double? = nil, skinTemp: Double? = nil, resp: Double? = nil,
                    steps: Int? = nil, kcal: Double? = nil) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: sleep, efficiency: efficiency, deepMin: deep, remMin: rem,
                    lightMin: light, disturbances: nil, restingHr: restingHr, avgHrv: hrv, recovery: recovery,
                    strain: strain, exerciseCount: nil, spo2Pct: spo2, skinTempDevC: skinTemp,
                    respRateBpm: resp, steps: steps, activeKcalEst: kcal, sleepHrOnly: hrOnly)
    }

    static func empty(_ day: String) -> DailyMetric {
        row(day, nil, nil, nil, nil, nil, nil, nil, nil, nil)
    }

    /// Specification §13.2: thirteen rows over fourteen days. 2031-03-07 has no row, 2031-03-11 is
    /// staged from heart rate only and 2031-03-13 carries strain alone.
    static let fixture: [DailyMetric] = [
        row("2031-03-03", 62, 47, 444, 78, 102, 264, 0.91, 58, 54),
        row("2031-03-04", 71, 38, 462, 84, 108, 270, 0.93, 63, 52),
        row("2031-03-05", 55, 62, 402, 66, 90, 246, 0.88, 52, 56),
        row("2031-03-06", 48, 30, 378, 60, 84, 234, 0.86, 47, 58),
        row("2031-03-08", 66, 44, 450, 81, 105, 264, 0.92, 60, 53),
        row("2031-03-09", 74, 25, 480, 90, 114, 276, 0.94, 66, 51),
        row("2031-03-10", 60, 50, 432, 75, 99, 258, 0.90, 57, 54),
        row("2031-03-11", 58, 41, 420, nil, nil, nil, nil, 55, 55, hrOnly: true),
        row("2031-03-12", 64, 58, 438, 78, 96, 264, 0.91, 59, 54),
        row("2031-03-13", nil, 35, nil, nil, nil, nil, nil, nil, nil),
        row("2031-03-14", 69, 46, 456, 84, 102, 270, 0.92, 62, 52),
        row("2031-03-15", 72, 33, 468, 87, 108, 273, 0.93, 64, 52),
        row("2031-03-16", 67, 6, 450, 81, 102, 267, 0.92, 61, 53),
    ]

    /// A fully measured row; `absent` names the one field left out.
    static func full(_ day: String, without absent: String? = nil) -> DailyMetric {
        func keep<T>(_ name: String, _ value: T) -> T? { absent == name ? nil : value }
        return row(day, keep("recovery", 62.0), keep("strain", 47.0), keep("sleep", 444.0), keep("deep", 78.0),
                   keep("rem", 102.0), keep("light", 264.0), keep("efficiency", 0.91), keep("hrv", 58.0),
                   keep("restingHr", 54))
    }

    static let optionalFields = ["recovery", "strain", "sleep", "deep", "rem", "light", "efficiency", "hrv",
                                 "restingHr"]

    /// `count` consecutive days from `start`, every value a fixed function of the index. Every
    /// sixth row has no recovery and no sleep, every third carries steps and the other vitals.
    static func run(from start: String, count: Int) -> [DailyMetric] {
        (0..<count).map { i in
            let unscored = i % 6 == 5
            let vitals = i % 3 == 0
            return row(day(start, plus: i),
                       unscored ? nil : 40 + Double((i * 7) % 45) + (i % 5 == 0 ? 0.5 : 0),
                       Double((i * 13) % 100) + 0.25,
                       unscored ? nil : 360 + Double((i * 17) % 150),
                       60 + Double((i * 3) % 40), 80 + Double((i * 5) % 40), 230 + Double((i * 7) % 50),
                       0.85 + Double(i % 10) / 100, 45 + Double((i * 11) % 25), 50 + (i * 3) % 10,
                       spo2: vitals ? 95 + Double(i % 4) : nil,
                       skinTemp: vitals ? Double(i % 7) / 10 - 0.3 : nil,
                       resp: vitals ? 14 + Double(i % 5) / 4 : nil,
                       steps: vitals ? 8_000 + i * 137 : nil,
                       kcal: vitals ? 400 + Double(i * 9) : nil)
        }
    }

    /// The day key `offset` days after `start`, in the proleptic Gregorian calendar.
    static func day(_ start: String, plus offset: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: start) else { return start }
        return formatter.string(from: date.addingTimeInterval(Double(offset) * 86_400))
    }
}

// MARK: - Seeded generator

/// SplitMix64: the same rows on every run and on every machine.
private struct SeededGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.upperBound - range.lowerBound + 1))
    }

    /// A value in `range` on a grid of `step`, so that exact halves and rounding ties occur.
    mutating func grid(_ range: ClosedRange<Double>, step: Double) -> Double {
        let steps = Int(((range.upperBound - range.lowerBound) / step).rounded(.down))
        return range.lowerBound + Double(int(0...steps)) * step
    }

    /// Nil one time in four.
    mutating func maybe<T>(_ value: T) -> T? { next() % 4 == 0 ? nil : value }

    mutating func efficiency() -> Double {
        switch next() % 8 {
        case 0: return 0
        case 1: return -0.2
        case 2: return 1.2                      // above a fraction, below the percentage split
        case 3: return grid(30...100, step: 0.5)   // stored as a percentage
        case 4: return 150                      // a percentage above 100
        default: return grid(0.5...1.0, step: 0.005)
        }
    }

    mutating func row(day: String) -> DailyMetric {
        ContextRows.row(day,
                        maybe(grid(0...100, step: 0.5)), maybe(grid(0...100, step: 0.05)),
                        maybe(grid(0...900, step: 1.5)), maybe(grid(0...240, step: 1.5)),
                        maybe(grid(0...240, step: 1.5)), maybe(grid(0...480, step: 1.5)),
                        maybe(efficiency()), maybe(grid(5...250, step: 0.5)), maybe(int(30...120)),
                        hrOnly: maybe(next() % 2 == 0),
                        spo2: maybe(grid(85...100, step: 0.5)), skinTemp: maybe(grid(-2...2, step: 0.05)),
                        resp: maybe(grid(8...24, step: 0.05)), steps: maybe(int(0...40_000)),
                        kcal: maybe(grid(0...2_000, step: 0.5)))
    }
}

// MARK: - Store-backed harness

/// A clock two days behind the real one, fixed for the length of a test (stage 1 ruling R31).
private struct ContextClock {
    let start: Date         // 00:00 UTC of "today"
    init() {
        let seconds = Int(Date().timeIntervalSince1970) - 2 * 86_400
        start = Date(timeIntervalSince1970: Double(seconds - seconds % 86_400))
    }
    func day(_ offset: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: start.addingTimeInterval(Double(offset) * 86_400))
    }
    /// `hour`:00 UTC on `day(offset)`, as epoch seconds.
    func epoch(_ offset: Int, hour: Int) -> Int { Int(start.timeIntervalSince1970) + offset * 86_400 + hour * 3_600 }
    /// The device-zone day of 12:00 UTC on `day(offset)`, worked out from calendar components and
    /// not with the formatter the Coach uses.
    func deviceDayOfNoon(_ offset: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let parts = calendar.dateComponents([.year, .month, .day],
                                            from: Date(timeIntervalSince1970: Double(epoch(offset, hour: 12))))
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// The text one state produced, and the day tokens its recording carries.
private struct CapturedContext {
    let text: String
    var tokens: [(token: String, value: String)] = []

    /// `recorded` with every token replaced by this run's day.
    func expected(from recorded: String) -> String {
        tokens.reduce(recorded) { $0.replacingOccurrences(of: $1.token, with: $1.value) }
    }
}

@MainActor
final class CoachContextByteIdentityTests: XCTestCase {
    private static let packetFlagKey = "noop.coachPacketEnabled"
    private static let signalsKey = "ai.includeOnDeviceSignals"
    /// Every key of the standard defaults a state reads or writes. Saved, cleared and restored
    /// around each test, so a state never depends on what the test host had stored.
    private static let standardKeys = [packetFlagKey, signalsKey, UnitPrefs.systemKey,
                                       UnitPrefs.distanceSystemKey, UnitPrefs.effortScaleKey]

    private var saved: [String: Any] = [:]
    private var suiteNames: [String] = []

    override func setUp() {
        super.setUp()
        saved = [:]
        for key in Self.standardKeys {
            if let value = UserDefaults.standard.object(forKey: key) { saved[key] = value }
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in Self.standardKeys {
            if let value = saved[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        for name in suiteNames { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        suiteNames = []
        super.tearDown()
    }

    // MARK: States

    /// Every store state with a recording, in the order of the recordings file.
    static let stateNames: [String] = [
        "no-days", "fixture", "one-row-every-field-absent", "day-line-every-field-absent", "day-lines-fixture",
        "more-than-thirty-rows", "month-boundary", "year-boundary", "leap-february",
        "absent-recovery", "absent-strain", "absent-sleep", "absent-deep", "absent-rem", "absent-light",
        "absent-efficiency", "absent-hrv", "absent-restingHr",
        "strain-on-the-stored-scale", "efficiency-as-a-percentage", "vitals-and-steps",
        "fifteen-rows", "thirty-one-rows", "gaps-in-wear", "rounding-ties",
        "full-empty-store", "full-workouts-metric", "full-workouts-imperial", "full-more-than-six-workouts",
        "full-body-line-scorecard-on", "full-body-line-scorecard-off", "full-signals-off",
        "refreshed-steps-strap", "refreshed-steps-apple-health", "refreshed-steps-estimate",
    ]

    /// The rows of a state that only `buildContext()` reads, or nil for a store-backed state.
    private func rows(for name: String) -> [DailyMetric]? {
        switch name {
        case "no-days": return []
        case "fixture", "strain-on-the-stored-scale": return ContextRows.fixture
        case "one-row-every-field-absent": return [ContextRows.empty("2031-03-07")]
        case "more-than-thirty-rows": return ContextRows.run(from: "2030-12-05", count: 35)
        case "month-boundary": return ContextRows.run(from: "2031-02-25", count: 8)
        case "year-boundary": return ContextRows.run(from: "2030-12-25", count: 14)
        case "leap-february": return ContextRows.run(from: "2032-02-26", count: 6)
        case "efficiency-as-a-percentage":
            return [94, 0.94, 1.2, 150, 0, -1, 1.5, 100, 1.0, 0.004].enumerated().map { index, value in
                var row = ContextRows.full(ContextRows.day("2031-03-01", plus: index))
                row = ContextRows.row(row.day, row.recovery, row.strain, row.totalSleepMin, row.deepMin, row.remMin,
                                      row.lightMin, value, row.avgHrv, row.restingHr)
                return row
            }
        case "vitals-and-steps":
            return [
                ContextRows.row("2031-03-14", 69, 46, 456, 84, 102, 270, 0.92, 62, 52,
                                spo2: 96.4, skinTemp: -0.25, resp: 14.6, steps: 9_640, kcal: 512.4),
                ContextRows.row("2031-03-15", 72, 33, 468, 87, 108, 273, 0.93, 64, 52,
                                spo2: 97.5, skinTemp: 0.15, resp: 15.1, steps: 13_020, kcal: 688.5),
                ContextRows.row("2031-03-16", 67, 6, 450, 81, 102, 267, 0.92, 61, 53, steps: 1_480),
            ]
        case "fifteen-rows": return ContextRows.run(from: "2031-03-02", count: 15)
        case "thirty-one-rows": return ContextRows.run(from: "2031-02-14", count: 31)
        case "gaps-in-wear":
            let run = ContextRows.run(from: "2031-01-01", count: 60)
            return run.enumerated().filter { $0.offset % 4 == 0 || $0.offset > 55 }.map(\.element)
        case "rounding-ties":
            return [
                ContextRows.row("2031-03-14", 62.5, 5.25, 75, 45, 15, 105, 0.905, 57.5, 54),
                ContextRows.row("2031-03-15", 63.5, 5.35, 105, 135, 165, 195, 0.915, 58.5, 55),
                ContextRows.row("2031-03-16", 0.5, 0.05, 3, 9, 15, 21, 0.995, 0.5, 53),
            ]
        default:
            if name.hasPrefix("absent-") {
                let field = String(name.dropFirst("absent-".count))
                return [ContextRows.full("2031-03-14"), ContextRows.full("2031-03-15", without: field),
                        ContextRows.full("2031-03-16")]
            }
            return nil
        }
    }

    private func plainEngine(_ days: [DailyMetric]) -> AICoachEngine {
        let repo = Repository(deviceId: "test-coach-context-bytes")
        repo.days = days
        return AICoachEngine(repo: repo)
    }

    private struct Backed {
        let store: WhoopStore
        let repo: Repository
        let defaults: UserDefaults
        let provider: BodyMeasurementProvider
        let clock: ContextClock
    }

    /// An empty in-memory store behind a repository. `scorecardFlag` is `noop.cutScorecardEnabled`.
    private func backed(scorecardFlag: Bool) async throws -> Backed {
        let name = "CoachContextByteIdentityTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        suiteNames.append(name)
        if scorecardFlag { defaults.set(true, forKey: "noop.cutScorecardEnabled") }
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: "my-whoop")
        repo.setStoreForTesting(store)
        let clock = ContextClock()
        let today = clock.day(0)
        let provider = BodyMeasurementProvider(repository: repo, defaults: defaults, today: { today })
        return Backed(store: store, repo: repo, defaults: defaults, provider: provider, clock: clock)
    }

    private func workout(_ clock: ContextClock, _ offset: Int, sport: String, source: String, minutes: Double?,
                         kcal: Double?, avgHr: Int?, strain: Double?, distanceM: Double?) -> WorkoutRow {
        let start = clock.epoch(offset, hour: 12)
        return WorkoutRow(startTs: start, endTs: start + Int((minutes ?? 30) * 60), sport: sport, source: source,
                          durationS: minutes.map { $0 * 60 }, energyKcal: kcal, avgHr: avgHr, maxHr: nil,
                          strain: strain, distanceM: distanceM, zonesJSON: nil, notes: nil, steps: nil)
    }

    /// The workout summaries of specification §7.9, one per source, plus a short swim.
    private func seedWorkouts(_ b: Backed, extra: Int = 0) async throws {
        let c = b.clock
        _ = try await b.store.upsertWorkouts(
            [workout(c, -13, sport: "strength", source: "lifting", minutes: 62, kcal: 380, avgHr: 108,
                     strain: nil, distanceM: nil)], deviceId: "lifting")
        _ = try await b.store.upsertWorkouts(
            [workout(c, -11, sport: "cycling", source: "apple-health", minutes: 45, kcal: 410, avgHr: 132,
                     strain: nil, distanceM: 18_400),
             workout(c, -2, sport: "swimming", source: "apple-health", minutes: 20, kcal: 150.5, avgHr: 118,
                     strain: nil, distanceM: 640)], deviceId: "apple-health")
        _ = try await b.store.upsertWorkouts(
            [workout(c, -8, sport: "hiking", source: "manual", minutes: 95, kcal: nil, avgHr: nil,
                     strain: nil, distanceM: nil),
             workout(c, -4, sport: "rowing", source: "whoop", minutes: 30, kcal: 300, avgHr: 128,
                     strain: 41.25, distanceM: nil)], deviceId: "my-whoop")
        _ = try await b.store.upsertWorkouts(
            [workout(c, -6, sport: "walking", source: "my-whoop-noop", minutes: 40, kcal: 170, avgHr: 96,
                     strain: 12, distanceM: 3_600)], deviceId: "my-whoop-noop")
        if extra > 0 {
            let more = (0..<extra).map { index in
                workout(c, -1 - 2 * index, sport: "running", source: "whoop", minutes: 30 + Double(index), kcal: 250,
                        avgHr: 140, strain: 30.5, distanceM: 5_000)
            }
            _ = try await b.store.upsertWorkouts(more, deviceId: "my-whoop")
        }
    }

    private func workoutTokens(_ clock: ContextClock) -> [(token: String, value: String)] {
        (0...20).map { (token: "{W-\($0)}", value: clock.deviceDayOfNoon(-$0)) }
    }

    private func dayTokens(_ clock: ContextClock) -> [(token: String, value: String)] {
        (0...20).map { (token: "{D-\($0)}", value: clock.day(-$0)) }
    }

    private func labRow(_ b: Backed, _ key: String, _ value: Double, unit: String, category: String) -> LabMarkerRow {
        let takenAt = b.clock.epoch(0, hour: 7)
        return LabMarkerRow(id: "\(key)-\(takenAt)-0A1B2C3D", deviceId: "my-whoop", markerKey: key,
                            category: category, day: b.clock.day(0), takenAt: takenAt, value: value,
                            valueText: nil, unit: unit, source: "manual", note: nil, referenceText: nil)
    }

    /// The text the engine produces for one named state.
    private func capture(_ name: String) async throws -> CapturedContext {
        if name == "day-line-every-field-absent" {
            return CapturedContext(text: plainEngine([]).dayLine(ContextRows.empty("2031-03-07")))
        }
        if name == "day-lines-fixture" {
            let engine = plainEngine([])
            return CapturedContext(text: ContextRows.fixture.map { engine.dayLine($0) }.joined(separator: "\n"))
        }
        if let rows = rows(for: name) {
            // The owner's display scale is WHOOP's 0 to 21; the Coach still prints the stored 0 to 100.
            if name == "strain-on-the-stored-scale" {
                UserDefaults.standard.set(EffortScale.whoop.rawValue, forKey: UnitPrefs.effortScaleKey)
            }
            return CapturedContext(text: plainEngine(rows).buildContext())
        }
        switch name {
        case "full-empty-store":
            let b = try await backed(scorecardFlag: false)
            return CapturedContext(text: await AICoachEngine(repo: b.repo).buildFullContext())
        case "full-workouts-metric", "full-workouts-imperial", "full-more-than-six-workouts":
            let b = try await backed(scorecardFlag: false)
            try await seedWorkouts(b, extra: name == "full-more-than-six-workouts" ? 4 : 0)
            if name == "full-workouts-imperial" {
                UserDefaults.standard.set(UnitSystem.imperial.rawValue, forKey: UnitPrefs.systemKey)
            }
            b.repo.days = ContextRows.fixture
            return CapturedContext(text: await AICoachEngine(repo: b.repo).buildFullContext(),
                                   tokens: workoutTokens(b.clock))
        case "full-body-line-scorecard-on", "full-body-line-scorecard-off", "full-signals-off":
            let flag = name == "full-body-line-scorecard-on"
            let b = try await backed(scorecardFlag: flag)
            // One marker per category with the flag off: the base roll-up walks a dictionary.
            var markers = [labRow(b, "weight", 97.1, unit: "kg", category: "bodyMeasurement"),
                           labRow(b, "zz-custom-marker", 3.1, unit: "mmol/L", category: "bloodPanel")]
            if flag { markers.append(labRow(b, "waist", 97.0, unit: "cm", category: "bodyMeasurement")) }
            try await b.store.upsertLabMarkers(markers)
            await b.provider.refresh()
            b.repo.days = ContextRows.fixture
            let engine = AICoachEngine(repo: b.repo)
            engine.bodyMeasurements = b.provider
            engine.includeOnDeviceSignals = name != "full-signals-off"
            return CapturedContext(text: await engine.buildFullContext(), tokens: dayTokens(b.clock))
        case "refreshed-steps-strap", "refreshed-steps-apple-health", "refreshed-steps-estimate":
            let b = try await backed(scorecardFlag: false)
            let counts = [9_120, 11_240, 8_460]
            let strapRows = (0..<3).map { index -> DailyMetric in
                let full = ContextRows.full(b.clock.day(index - 3))
                return ContextRows.row(full.day, full.recovery, full.strain, full.totalSleepMin, full.deepMin,
                                       full.remMin, full.lightMin, full.efficiency, full.avgHrv, full.restingHr,
                                       steps: name == "refreshed-steps-strap" ? counts[index] : nil)
            }
            _ = try await b.store.upsertDailyMetrics(strapRows, deviceId: "my-whoop")
            if name == "refreshed-steps-apple-health" {
                let apple = (0..<3).map {
                    AppleDaily(day: b.clock.day($0 - 3), steps: counts[$0], activeKcal: nil, basalKcal: nil,
                               vo2max: nil, avgHr: nil, maxHr: nil, walkingHr: nil, weightKg: nil)
                }
                _ = try await b.store.upsertAppleDaily(apple, deviceId: "apple-health")
                _ = try await b.store.upsertMetricSeries(
                    (0..<3).map { MetricPoint(day: b.clock.day($0 - 3), key: "steps", value: Double(counts[$0])) },
                    deviceId: "apple-health")
            }
            if name == "refreshed-steps-estimate" {
                _ = try await b.store.upsertMetricSeries(
                    (0..<3).map { MetricPoint(day: b.clock.day($0 - 3), key: "steps_est", value: Double(counts[$0])) },
                    deviceId: "my-whoop")
            }
            await b.repo.refresh()
            return CapturedContext(text: AICoachEngine(repo: b.repo).buildContext(), tokens: dayTokens(b.clock))
        default:
            XCTFail("no state named \(name)")
            return CapturedContext(text: "")
        }
    }

    /// Every state starts from the same defaults: no unit, scale or signals preference is carried
    /// over from the state before it. `packetFlag` nil leaves the stage 2 flag absent.
    private func assertRecorded(_ name: String, packetFlag: Bool? = nil, file: StaticString = #filePath,
                                line: UInt = #line) async throws {
        for key in Self.standardKeys { UserDefaults.standard.removeObject(forKey: key) }
        if let packetFlag { UserDefaults.standard.set(packetFlag, forKey: Self.packetFlagKey) }
        let captured = try await capture(name)
        let recorded = try XCTUnwrap(CoachContextRecorded.texts[name], "no recording for \(name)", file: file, line: line)
        XCTAssertEqual(captured.text, captured.expected(from: recorded),
                       "the Coach context for \"\(name)\" is not the recorded text", file: file, line: line)
    }

    // MARK: - 1. Recorded text

    /// The table: at least twenty store states, each equal to what the untouched code printed.
    func testEveryStoreStateEqualsItsRecordedText() async throws {
        XCTAssertGreaterThanOrEqual(Self.stateNames.count, 20)
        XCTAssertEqual(Set(Self.stateNames), Set(CoachContextRecorded.texts.keys),
                       "every state has one recording and every recording one state")
        for name in Self.stateNames { try await assertRecorded(name) }
    }

    func testBuildContextForTheFixtureEqualsTheRecordedText() async throws {
        try await assertRecorded("fixture")
    }

    func testBuildContextWithNoDaysEqualsTheRecordedText() async throws {
        try await assertRecorded("no-days")
        XCTAssertFalse(try XCTUnwrap(CoachContextRecorded.texts["no-days"]).contains("averages"),
                       "with no rows the context is the no-data sentence and nothing else")
    }

    func testBuildContextWithMoreThanThirtyRowsEqualsTheRecordedText() async throws {
        try await assertRecorded("more-than-thirty-rows")
        // The windows are rows, not calendar days: fourteen lines, and averages over the last thirty.
        let text = try XCTUnwrap(CoachContextRecorded.texts["more-than-thirty-rows"])
        XCTAssertEqual(text.components(separatedBy: "\n").filter { $0.hasPrefix("  20") }.count, 14)
    }

    func testDayLineForRowsWithEveryFieldAbsentEqualsTheRecordedText() async throws {
        try await assertRecorded("day-line-every-field-absent")
        try await assertRecorded("one-row-every-field-absent")
        // The comma after the colon is part of the text the Coach has always been sent (§3 C2).
        XCTAssertEqual(CoachContextRecorded.texts["day-line-every-field-absent"],
                       "2031-03-07:, charge —, effort —, rest —, deep —, REM —, light —, eff —, HRV —, RHR —")
    }

    func testEachOptionalFieldAbsentInTurnEqualsTheRecordedText() async throws {
        for field in ContextRows.optionalFields { try await assertRecorded("absent-\(field)") }
    }

    func testRangesAcrossAMonthAYearAndALeapDayEqualTheRecordedText() async throws {
        for name in ["month-boundary", "year-boundary", "leap-february"] { try await assertRecorded(name) }
    }

    /// The Coach prints the stored 0 to 100 strain whatever display scale the owner chose (§3 C3).
    func testStrainIsOnTheStoredScaleWhateverTheDisplayScale() async throws {
        try await assertRecorded("strain-on-the-stored-scale")
        XCTAssertEqual(CoachContextRecorded.texts["strain-on-the-stored-scale"], CoachContextRecorded.texts["fixture"])
    }

    func testStepsFromEachSourceEqualTheRecordedText() async throws {
        for name in ["refreshed-steps-strap", "refreshed-steps-apple-health", "refreshed-steps-estimate",
                     "vitals-and-steps"] {
            try await assertRecorded(name)
        }
    }

    func testWorkoutsInMetricAndImperialEqualTheRecordedText() async throws {
        for name in ["full-workouts-metric", "full-workouts-imperial", "full-more-than-six-workouts",
                     "full-empty-store"] {
            try await assertRecorded(name)
        }
        XCTAssertNotEqual(CoachContextRecorded.texts["full-workouts-metric"],
                          CoachContextRecorded.texts["full-workouts-imperial"],
                          "the two unit systems word a distance differently, so both are pinned")
    }

    func testBodyMeasurementLineWithTheScorecardFlagOnAndOffEqualsTheRecordedText() async throws {
        for name in ["full-body-line-scorecard-on", "full-body-line-scorecard-off", "full-signals-off"] {
            try await assertRecorded(name)
        }
        let on = try XCTUnwrap(CoachContextRecorded.texts["full-body-line-scorecard-on"])
        let off = try XCTUnwrap(CoachContextRecorded.texts["full-body-line-scorecard-off"])
        XCTAssertTrue(on.contains("BODY MEASUREMENTS"), on)
        XCTAssertFalse(off.contains("BODY MEASUREMENTS"), off)
    }

    /// The stage 2 flag changes nothing the Coach is told: every state, with the flag on, is the
    /// text recorded with it absent.
    func testCoachContextIsTheSameWithThePacketFlagOnAndOff() async throws {
        for enabled in [true, false] {
            for name in Self.stateNames { try await assertRecorded(name, packetFlag: enabled) }
        }
    }

    // MARK: - 2. The frozen copy

    /// The oracle is tied to the recordings: for every state `buildContext()` alone produces, the
    /// frozen copy prints the recorded text. A slip in copying the old code fails here.
    func testFrozenCopyReproducesEveryRecordedBuildContext() throws {
        var checked = 0
        for name in Self.stateNames {
            guard let rows = rows(for: name) else { continue }
            XCTAssertEqual(FrozenLegacyCoachContext.buildContext(rows), CoachContextRecorded.texts[name], name)
            checked += 1
        }
        XCTAssertGreaterThanOrEqual(checked, 20)
        XCTAssertEqual(ContextRows.fixture.map(FrozenLegacyCoachContext.dayLine).joined(separator: "\n"),
                       CoachContextRecorded.texts["day-lines-fixture"])
    }

    func testGeneratedRowsMatchTheFrozenDayLine() {
        var generator = SeededGenerator(seed: 0x5A6E_2031_0316)
        let engine = plainEngine([])
        for index in 0..<500 {
            let row = generator.row(day: ContextRows.day("2030-06-01", plus: index))
            XCTAssertEqual(engine.dayLine(row), FrozenLegacyCoachContext.dayLine(row), "row \(index): \(row)")
        }
    }

    func testGeneratedRowListsMatchTheFrozenContext() {
        var generator = SeededGenerator(seed: 0x2031_0316_07_42_10)
        for list in 0..<200 {
            // Lengths around both windows: none, under 14, between 14 and 30, and beyond 30.
            let count = [0, 1, 2, 13, 14, 15, 29, 30, 31, 45][list % 10] + (list % 10 == 0 ? 0 : generator.int(0...2))
            let rows = (0..<count).map { generator.row(day: ContextRows.day("2030-06-01", plus: list + $0 * 2)) }
            XCTAssertEqual(plainEngine(rows).buildContext(), FrozenLegacyCoachContext.buildContext(rows),
                           "list \(list) of \(count) rows")
        }
    }

    func testGeneratedEfficienciesMatchTheFrozenHelper() {
        var generator = SeededGenerator(seed: 0x00EF_F1C1_E7C7)
        let engine = plainEngine([])
        let fixed: [Double?] = [nil, 0, -1, 0.004, 0.005, 0.5, 0.945, 0.955, 1.0, 1.2, 1.5, 1.5000001, 50, 94,
                                99.5, 100, 100.5, 150, 9_400]
        for value in fixed + (0..<500).map({ _ in Optional(generator.efficiency()) }) {
            XCTAssertEqual(engine.efficiencyPercentOrDash(value),
                           FrozenLegacyCoachContext.efficiencyPercentOrDash(value), "\(String(describing: value))")
        }
    }

    /// The full context is still the per-day summary, then the workouts block, joined as before:
    /// the extraction touches neither the joins nor the workouts block.
    func testFullContextBeginsWithTheFrozenBuildContextForTheSameRows() async throws {
        let b = try await backed(scorecardFlag: false)
        try await seedWorkouts(b)
        b.repo.days = ContextRows.fixture
        let full = await AICoachEngine(repo: b.repo).buildFullContext()
        let head = FrozenLegacyCoachContext.buildContext(ContextRows.fixture) + "\n\nRecent workouts (newest first):\n"
        XCTAssertTrue(full.hasPrefix(head), full)
    }
}
