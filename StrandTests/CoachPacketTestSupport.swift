// API ASSUMED BY THESE TESTS
//
// Shared by the stage 2 app-target tests. New, from specification §8.3 and §8.4 unless marked:
//
//     final class CoachPacketSettings {
//         static let enabledKey = "noop.coachPacketEnabled"
//         init(defaults: UserDefaults = .standard)
//         var isEnabled: Bool { get set }
//     }
//
//     @MainActor struct CoachPacketAssembler {
//         init(repository: Repository, provider: BodyMeasurementProvider,
//              scorecardSettings: CutScorecardSettings, settings: CoachPacketSettings,
//              now: @escaping () -> Date = { Date() },
//              timeZone: @escaping () -> TimeZone = { TimeZone.current },
//              effortScale: @escaping () -> EffortScale,
//              identifiers: @escaping () -> [String])
//     }
//
// Everything else in this file is used as it exists today.

import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

// Stage 2 (coach packet): the harness the assembler, single-source and model tests share.
//
// Dates are relative to the real clock, one day back (stage 1 ruling R31): `Repository.workoutRows`
// and `Repository.refresh` are windowed on the real clock, so a fixed 2031 date would fall outside
// both. One day back keeps every seeded instant in the real past, and keeps a 14-day range inside
// the `rangeDays + 1` days the assembler asks the workout read for. The values are the Fixture
// Person's (specification §13), with 2031-03-16 mapped to the harness's "today".
//
// Synthetic values only.

/// A clock one day behind the real one, fixed for the length of a test.
struct CoachPacketClock {
    let start: Date         // 00:00 UTC of "today"
    init() {
        let seconds = Int(Date().timeIntervalSince1970) - 86_400
        start = Date(timeIntervalSince1970: Double(seconds - seconds % 86_400))
    }
    /// 12:00 UTC of "today".
    var now: Date { start.addingTimeInterval(12 * 3_600) }
    var today: String { day(0) }
    func day(_ offset: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: start.addingTimeInterval(Double(offset) * 86_400))
    }
    /// `hour`:`minute` UTC on `day(offset)`, as epoch seconds.
    func epoch(_ offset: Int, hour: Int = 7, minute: Int = 0) -> Int {
        Int(start.timeIntervalSince1970) + offset * 86_400 + hour * 3_600 + minute * 60
    }
}

/// The defaults suites one test class created, removed in its `tearDown`.
final class CoachPacketSuites {
    var names: [String] = []
    func removeAll() {
        for name in names { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        names = []
    }
}

/// A mutable value a clock or zone closure reads, and a count of how often it was read. Used on
/// the main actor only.
final class CoachPacketBox<Value> {
    var value: Value
    private(set) var reads = 0
    /// Applied to `value` after every read; lets a clock move between two reads.
    var afterRead: ((inout Value) -> Void)?
    init(_ value: Value) { self.value = value }
    func read() -> Value {
        reads += 1
        let current = value
        afterRead?(&value)
        return current
    }
}

@MainActor
struct CoachPacketHarness {
    let store: WhoopStore
    let repo: Repository
    let defaults: UserDefaults
    let provider: BodyMeasurementProvider
    let weighIns: WeighInStore
    let scorecardSettings: CutScorecardSettings
    let packetSettings: CoachPacketSettings
    let clock: CoachPacketClock

    static let deviceId = "my-whoop"
    static let utc = TimeZone(identifier: "UTC")!

    var today: String { clock.today }

    /// An empty store. `scorecard` is `noop.cutScorecardEnabled`, `packet` is
    /// `noop.coachPacketEnabled`; both live in the harness's own defaults suite.
    static func empty(scorecard: Bool, packet: Bool = true, suites: CoachPacketSuites) async throws -> CoachPacketHarness {
        let name = "CoachPacketTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        suites.names.append(name)
        if scorecard { defaults.set(true, forKey: CutScorecardSettings.enabledKey) }
        if packet { defaults.set(true, forKey: "noop.coachPacketEnabled") }
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: deviceId)
        repo.setStoreForTesting(store)
        let clock = CoachPacketClock()
        let today = clock.today
        let now = clock.now
        let provider = BodyMeasurementProvider(repository: repo, defaults: defaults, today: { today })
        let weighIns = WeighInStore(repository: repo, provider: provider, timeZone: { utc }, now: { now })
        return CoachPacketHarness(store: store, repo: repo, defaults: defaults, provider: provider, weighIns: weighIns,
                                  scorecardSettings: CutScorecardSettings(defaults: defaults),
                                  packetSettings: CoachPacketSettings(defaults: defaults), clock: clock)
    }

    /// The Fixture Person: weekly weigh-ins, a started cut phase, two weeks of daily rows, steps
    /// from two sources and five workout summaries.
    static func fixturePerson(scorecard: Bool, suites: CoachPacketSuites) async throws -> CoachPacketHarness {
        let h = try await empty(scorecard: scorecard, suites: suites)
        try await h.seedWeighIns()
        h.seedPhaseAndRules()
        h.repo.days = h.fixtureDays()
        try await h.seedSteps()
        try await h.seedWorkouts()
        await h.provider.refresh()
        return h
    }

    // MARK: Seeds

    /// Stage 1's weekly weights and waists, nine weeks ending eleven days before today.
    static let weeklyWeights = [100.0, 99.2, 98.4, 97.6, 97.5, 97.4, 97.3, 97.2, 97.1]
    static let weeklyWaists = [100.0, 99.5, 99.0, 98.5, 98.0, 97.5, 97.0, 97.0, 97.0]
    static let lastWeighInOffset = -11

    func lab(_ key: String, _ offset: Int, _ value: Double) -> LabMarkerRow {
        let takenAt = clock.epoch(offset)
        return LabMarkerRow(id: "\(key)-\(takenAt)-0A1B2C3D", deviceId: Self.deviceId, markerKey: key,
                            category: "bodyMeasurement", day: clock.day(offset), takenAt: takenAt, value: value,
                            valueText: nil, unit: key == "weight" ? "kg" : "cm", source: "manual", note: nil,
                            referenceText: nil)
    }

    func seedWeighIns() async throws {
        var rows: [LabMarkerRow] = []
        for (index, weight) in Self.weeklyWeights.enumerated() {
            let offset = Self.lastWeighInOffset - 7 * (Self.weeklyWeights.count - 1 - index)
            rows.append(lab("weight", offset, weight))
            rows.append(lab("waist", offset, Self.weeklyWaists[index]))
        }
        try await store.upsertLabMarkers(rows)
    }

    func seedPhaseAndRules(name: String = "Fixture cut") {
        scorecardSettings.phases = [CutScorecardStoredPhase(kind: .cut, name: name, startDay: clock.day(-69),
                                                            targetWeightKg: 94.0, rateLowPercentPerWeek: 0.40,
                                                            rateHighPercentPerWeek: 1.20)]
        var parameters = CutScorecardParameters.generic
        parameters.proteinFloorGrams = 100
        scorecardSettings.parameters = parameters
    }

    /// Specification §13.2 with 2031-03-16 as today: offset -9 has no row, -5 is staged from heart
    /// rate only and -3 carries strain alone.
    func fixtureDays() -> [DailyMetric] {
        func row(_ offset: Int, _ recovery: Double?, _ strain: Double?, _ sleep: Double?, _ deep: Double?,
                 _ rem: Double?, _ light: Double?, _ efficiency: Double?, _ hrv: Double?, _ restingHr: Int?,
                 hrOnly: Bool? = nil) -> DailyMetric {
            DailyMetric(day: clock.day(offset), totalSleepMin: sleep, efficiency: efficiency, deepMin: deep,
                        remMin: rem, lightMin: light, disturbances: nil, restingHr: restingHr, avgHrv: hrv,
                        recovery: recovery, strain: strain, exerciseCount: nil, sleepHrOnly: hrOnly)
        }
        return [
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
    }

    /// The steps of specification §7.9: Apple Health on most days, the strap's estimate on two,
    /// nothing on one. Keyed by day offset.
    static let appleSteps: [Int: Double] = [-13: 9_120, -12: 11_240, -11: 8_460, -8: 12_080, -7: 6_540, -6: 9_870,
                                            -5: 10_310, -4: 8_890, -2: 9_640, -1: 13_020, 0: 1_480]
    static let estimatedSteps: [Int: Double] = [-10: 7_300, -3: 5_200]

    func seedSteps() async throws {
        _ = try await store.upsertMetricSeries(
            Self.appleSteps.map { MetricPoint(day: clock.day($0.key), key: "steps", value: $0.value) },
            deviceId: Repository.appleHealthSource)
        _ = try await store.upsertMetricSeries(
            Self.estimatedSteps.map { MetricPoint(day: clock.day($0.key), key: "steps_est", value: $0.value) },
            deviceId: Repository.whoopSource)
    }

    func workout(_ offset: Int, hour: Int, minute: Int, sport: String, source: String, minutes: Double?,
                 avgHr: Int?, kcal: Double?, distanceM: Double?) -> WorkoutRow {
        let start = clock.epoch(offset, hour: hour, minute: minute)
        return WorkoutRow(startTs: start, endTs: start + Int((minutes ?? 30) * 60), sport: sport, source: source,
                          durationS: minutes.map { $0 * 60 }, energyKcal: kcal, avgHr: avgHr, maxHr: nil,
                          strain: nil, distanceM: distanceM, zonesJSON: nil, notes: nil, steps: nil)
    }

    /// The five workout summaries of specification §7.9, one per source the fixture names.
    func seedWorkouts() async throws {
        _ = try await store.upsertWorkouts(
            [workout(-13, hour: 18, minute: 10, sport: "strength", source: "lifting", minutes: 62, avgHr: 108,
                     kcal: 380, distanceM: nil)], deviceId: "lifting")
        _ = try await store.upsertWorkouts(
            [workout(-11, hour: 7, minute: 5, sport: "cycling", source: "apple-health", minutes: 45, avgHr: 132,
                     kcal: 410, distanceM: 18_400)], deviceId: "apple-health")
        _ = try await store.upsertWorkouts(
            [workout(-8, hour: 9, minute: 30, sport: "hiking", source: "manual", minutes: 95, avgHr: nil,
                     kcal: nil, distanceM: nil),
             workout(-4, hour: 18, minute: 5, sport: "rowing", source: "whoop", minutes: 30, avgHr: 128,
                     kcal: 300, distanceM: nil)], deviceId: Self.deviceId)
        _ = try await store.upsertWorkouts(
            [workout(-6, hour: 6, minute: 50, sport: "walking", source: "my-whoop-noop", minutes: 40, avgHr: 96,
                     kcal: 170, distanceM: 3_600)], deviceId: "my-whoop-noop")
    }

    // MARK: The assembler

    /// The assembler over this harness. `now` and `zone` default to the harness clock and UTC.
    func assembler(now: (() -> Date)? = nil, zone: (() -> TimeZone)? = nil, scale: EffortScale = .hundred,
                   identifiers: [String] = []) -> CoachPacketAssembler {
        let fixedNow = clock.now
        return CoachPacketAssembler(repository: repo, provider: provider, scorecardSettings: scorecardSettings,
                                    settings: packetSettings, now: now ?? { fixedNow },
                                    timeZone: zone ?? { CoachPacketHarness.utc },
                                    effortScale: { scale }, identifiers: { identifiers })
    }

    /// The document of a packet that was assembled, or a failure.
    func document(_ assembler: CoachPacketAssembler? = nil, file: StaticString = #filePath,
                  line: UInt = #line) async throws -> CoachPacketDocument {
        let outcome = await (assembler ?? self.assembler()).assemble()
        guard case let .ready(document) = outcome else {
            XCTFail("expected a ready packet, got \(outcome)", file: file, line: line)
            throw CoachPacketTestFailure.notReady
        }
        return document
    }
}

enum CoachPacketTestFailure: Error { case notReady }

/// Reading a packet's text in tests.
enum CoachPacketText {
    static func lines(_ text: String) -> [String] { text.components(separatedBy: "\n") }

    /// The lines under `heading` up to the next blank line, the heading itself left out.
    static func section(_ text: String, _ heading: String) -> [String] {
        let all = lines(text)
        guard let start = all.firstIndex(of: heading) else { return [] }
        return Array(all[(start + 1)...].prefix { !$0.isEmpty })
    }

    /// The first line that begins with `prefix`.
    static func line(_ text: String, startingWith prefix: String) -> String? {
        lines(text).first { $0.hasPrefix(prefix) }
    }

    /// A document for a model or presenter test that needs no store: the header's first line, one
    /// line that tells two documents apart, and the closing line.
    static func sample(_ marker: String) -> String {
        "\(CoachPacket.formatName) v\(CoachPacket.formatVersion)\nfixture \(marker)\nend of \(CoachPacket.formatName) v\(CoachPacket.formatVersion)\n"
    }
}
