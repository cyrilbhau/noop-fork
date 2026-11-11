import Foundation
import StrandAnalytics
import WhoopStore

/// The one writer of the totals read from Apple Health (stage 3 specification §8.2, §9.1, Path A).
///
/// It imports no HealthKit: the bridge fetches the samples and hands them here, and everything that
/// decides what is written is in this type and the pure `IntakeAggregation`, so it is tested on macOS.
/// Until the owner's go-ahead adds the bridge's read (G1), nothing calls it and `noop-intake-health`
/// stays empty.
///
/// It writes and deletes only under `IntakeProvider.healthSourceId`, and only the day-and-key pairs
/// of its own plan. A failed read writes nothing; an empty window writes nothing; a day that lost all
/// of its samples inside a window that has samples has its rows deleted and reads "not measured".
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
@MainActor
struct IntakeHealthSync {
    enum Outcome: Equatable {
        /// The setting is off: nothing read, nothing written.
        case disabled
        /// The samples could not be read: nothing written.
        case failedRead
        /// The window came back empty: nothing written.
        case preserved
        /// Only the read times advanced.
        case unchanged
        case written(changedDays: [String])
        case failedWrite
    }

    /// Local days before the first written day that the query also covers, so a written day lies
    /// wholly inside the queried instants under any zone log (§7.3).
    static let queryMarginDays = 4

    private let repository: Repository
    private let settings: IntakeSettings
    private let now: () -> Date
    private let zoneIdentifier: () -> String

    init(repository: Repository, settings: IntakeSettings, now: @escaping () -> Date,
         zoneIdentifier: @escaping () -> String) {
        self.repository = repository
        self.settings = settings
        self.now = now
        self.zoneIdentifier = zoneIdentifier
    }

    /// The instants to query for a read covering `days` local days back from today. Appends the
    /// current zone to the zone log and stores it first (§7.1).
    func queryWindow(days: Int) -> (start: Date, end: Date, firstDay: String, lastDay: String) {
        let instant = now()
        let identifier = zoneIdentifier()
        let log = IntakeAggregation.appending(zoneIdentifier: identifier, at: Int(instant.timeIntervalSince1970),
                                              to: settings.zoneLog)
        if log != settings.zoneLog { settings.zoneLog = log }
        let lastDay = IntakeAggregation.dayKey(epochSeconds: Int(instant.timeIntervalSince1970.rounded(.down)),
                                               zoneLog: log)
        let firstDay = CanonicalDay.number(lastDay).map { CanonicalDay.key($0 - days) } ?? lastDay
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier) ?? TimeZone(identifier: "UTC") ?? .current
        let todayStart = calendar.startOfDay(for: instant)
        let end = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? instant
        let start = calendar.date(byAdding: .day, value: -(days + Self.queryMarginDays), to: todayStart) ?? todayStart
        return (start, end, firstDay, lastDay)
    }

    /// Applies one read. `samples` nil is a failed read. `sourceNames` maps a bundle id to the
    /// app's name, when the bridge knows it.
    func apply(samples: [IntakeSample]?, firstDay: String, lastDay: String,
               sourceNames: [String: String] = [:]) async -> Outcome {
        guard settings.healthReadEnabled else { return .disabled }
        let attemptedAt = now()
        let outcome = await write(samples: samples, firstDay: firstDay, lastDay: lastDay, sourceNames: sourceNames)
        IntakeProvider.recordHealthAttempt(outcome, at: attemptedAt, repository: repository)
        return outcome
    }

    private func write(samples: [IntakeSample]?, firstDay: String, lastDay: String,
                       sourceNames: [String: String]) async -> Outcome {
        guard let samples else { return .failedRead }
        let log = settings.zoneLog
        let result = IntakeAggregation.aggregate(samples: samples, zoneLog: log,
                                                 admittedSourceIds: settings.admittedHealthSources,
                                                 firstDay: firstDay, lastDay: lastDay)
        guard !result.totals.isEmpty else { return .preserved }

        let id = IntakeProvider.healthSourceId
        guard let store = await repository.storeHandle(),
              let stored = await Self.storedDays(store: store, deviceId: id, firstDay: firstDay, lastDay: lastDay)
        else { return .failedWrite }

        let readAt = Int(now().timeIntervalSince1970.rounded(.down))
        let plan = IntakeAggregation.plan(result: result, stored: stored, readAtEpochSeconds: readAt)
        do {
            // One call, one transaction: totals and their read time cannot be torn apart (§9.1).
            if !plan.upserts.isEmpty {
                _ = try await store.upsertMetricSeries(
                    plan.upserts.map { MetricPoint(day: $0.day, key: $0.key, value: $0.value) }, deviceId: id)
            }
            for deletion in plan.deletions {
                _ = try await store.deleteMetricSeriesPoint(deviceId: id, day: deletion.day, key: deletion.key)
            }
        } catch {
            IntakeProvider.funnelDidWrite(repository)
            return .failedWrite
        }

        recordSources(samples, log: log, firstDay: firstDay, lastDay: lastDay, names: sourceNames)
        if !settings.healthBackfilled { settings.healthBackfilled = true }
        IntakeProvider.funnelDidWrite(repository)
        return plan.changedDays.isEmpty ? .unchanged : .written(changedDays: plan.changedDays)
    }

    /// Every app that wrote a usable sample inside the window, with the latest day it wrote on,
    /// admitted or not, so the owner can choose among them (§9.2, §10.5).
    private func recordSources(_ samples: [IntakeSample], log: [IntakeZoneSegment], firstDay: String,
                               lastDay: String, names: [String: String]) {
        var lastSeen: [String: String] = [:]
        for sample in samples where sample.amount.isFinite && sample.amount >= 0 {
            let day = IntakeAggregation.dayKey(epochSeconds: sample.startEpochSeconds, zoneLog: log)
            guard day >= firstDay, day <= lastDay else { continue }
            lastSeen[sample.sourceId] = max(lastSeen[sample.sourceId] ?? day, day)
        }
        let known = settings.knownHealthSources
        for (bundleId, day) in lastSeen.sorted(by: { $0.key < $1.key }) {
            let name = names[bundleId] ?? known[bundleId]?.name ?? bundleId
            settings.recordHealthSource(bundleId: bundleId, name: name, day: day)
        }
    }

    /// What the store holds under `deviceId` for the window; nil when the read failed.
    private static func storedDays(store: WhoopStore, deviceId: String, firstDay: String,
                                   lastDay: String) async -> [IntakeStoredDay]? {
        do {
            let protein = try await store.metricSeries(deviceId: deviceId, key: IntakeAggregation.proteinKey,
                                                       from: firstDay, to: lastDay)
            let energy = try await store.metricSeries(deviceId: deviceId, key: IntakeAggregation.energyKey,
                                                      from: firstDay, to: lastDay)
            let times = try await store.metricSeries(deviceId: deviceId, key: IntakeAggregation.readAtKey,
                                                     from: firstDay, to: lastDay)
            var days: [String: (protein: Double?, energy: Double?, readAt: Int?)] = [:]
            for point in protein { days[point.day, default: (nil, nil, nil)].protein = point.value }
            for point in energy { days[point.day, default: (nil, nil, nil)].energy = point.value }
            for point in times where point.value.isFinite && abs(point.value) < 1e15 {
                days[point.day, default: (nil, nil, nil)].readAt = Int(point.value)
            }
            return days.keys.sorted().map {
                IntakeStoredDay(day: $0, proteinGrams: days[$0]?.protein, energyKcal: days[$0]?.energy,
                                readAtEpochSeconds: days[$0]?.readAt)
            }
        } catch {
            return nil
        }
    }
}
