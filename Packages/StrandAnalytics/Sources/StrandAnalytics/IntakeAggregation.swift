import Foundation

// Stage 3 of the personal fork: daily protein and energy intake, as pure logic
// (`docs/personal/superapp/specs/stage-3.md` §6, §7.1 to §7.3).
//
// No store, no clock, no current calendar and no current zone. Instants are epoch seconds, days are
// canonical "yyyy-MM-dd" keys validated and moved only through `CanonicalDay`, and the day an instant
// falls on is `LocalDayWindows`' answer for a zone named by the caller's zone log. `TimeZone` appears
// only as `TimeZone(identifier:)`, the zone database lookup, never as the device's zone.
//
// Nothing here throws or traps on any input, and no output holds NaN or infinity.

/// The two nutrients this stage reads.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public enum IntakeNutrient: String, Sendable, CaseIterable {
    case protein
    case energy
}

/// One logged amount of one nutrient.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public struct IntakeSample: Equatable, Sendable {
    /// Stable identity: a HealthKit uuid string or a quick-add entry id.
    public let id: String
    public let nutrient: IntakeNutrient
    /// The instant the food is logged for, in epoch seconds.
    public let startEpochSeconds: Int
    /// Grams for protein, kilocalories for energy.
    public let amount: Double
    /// The writing app's bundle id, or "noop-intake".
    public let sourceId: String

    public init(id: String, nutrient: IntakeNutrient, startEpochSeconds: Int,
                amount: Double, sourceId: String) {
        self.id = id
        self.nutrient = nutrient
        self.startEpochSeconds = startEpochSeconds
        self.amount = amount
        self.sourceId = sourceId
    }
}

/// From `fromEpochSeconds` on, days are counted in `zoneIdentifier`.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public struct IntakeZoneSegment: Equatable, Sendable, Codable {
    public let fromEpochSeconds: Int
    public let zoneIdentifier: String

    public init(fromEpochSeconds: Int, zoneIdentifier: String) {
        self.fromEpochSeconds = fromEpochSeconds
        self.zoneIdentifier = zoneIdentifier
    }
}

/// What the store holds for one day under one source id. A nil field is a row the store does not hold.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public struct IntakeStoredDay: Equatable, Sendable {
    public let day: String
    public let proteinGrams: Double?
    public let energyKcal: Double?
    public let readAtEpochSeconds: Int?

    public init(day: String, proteinGrams: Double?, energyKcal: Double?, readAtEpochSeconds: Int?) {
        self.day = day
        self.proteinGrams = proteinGrams
        self.energyKcal = energyKcal
        self.readAtEpochSeconds = readAtEpochSeconds
    }
}

/// One day's intake. A nil nutrient was not measured on that day; it is never zero for that reason.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public struct IntakeDayTotal: Equatable, Sendable {
    public let day: String
    /// Nil: no admitted protein sample on this day.
    public let proteinGrams: Double?
    /// Nil: no admitted energy sample on this day.
    public let energyKcal: Double?
    /// Admitted samples of either nutrient.
    public let sampleCount: Int
    /// Distinct, ascending.
    public let sourceIds: [String]

    public init(day: String, proteinGrams: Double?, energyKcal: Double?, sampleCount: Int,
                sourceIds: [String]) {
        self.day = day
        self.proteinGrams = proteinGrams
        self.energyKcal = energyKcal
        self.sampleCount = sampleCount
        self.sourceIds = sourceIds
    }
}

/// How many samples were dropped, by the first check each failed (§6.4).
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public struct IntakeRejections: Equatable, Sendable {
    public let nonFinite: Int
    public let negative: Int
    public let duplicateId: Int
    /// Day key before `firstDay` or after `lastDay`.
    public let outsideWindow: Int
    public let excludedSource: Int

    public init(nonFinite: Int, negative: Int, duplicateId: Int, outsideWindow: Int, excludedSource: Int) {
        self.nonFinite = nonFinite
        self.negative = negative
        self.duplicateId = duplicateId
        self.outsideWindow = outsideWindow
        self.excludedSource = excludedSource
    }
}

/// The outcome of one aggregation over a window of days.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public struct IntakeAggregationResult: Equatable, Sendable {
    /// Ascending; only days with at least one admitted sample.
    public let totals: [IntakeDayTotal]
    /// Ascending; days in the window with none.
    public let emptyDays: [String]
    public let rejected: IntakeRejections

    public init(totals: [IntakeDayTotal], emptyDays: [String], rejected: IntakeRejections) {
        self.totals = totals
        self.emptyDays = emptyDays
        self.rejected = rejected
    }
}

/// Why a write plan holds what it holds (§7.3).
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public enum IntakeWriteReason: String, Sendable {
    case windowEmpty
    case unchanged
    case changed
}

/// What one read writes to the store for one source id (§7.3).
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public struct IntakeWritePlan: Equatable, Sendable {
    /// One value to upsert.
    ///
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public struct Point: Equatable, Sendable {
        public let day: String
        public let key: String
        public let value: Double

        public init(day: String, key: String, value: Double) {
            self.day = day
            self.key = key
            self.value = value
        }
    }

    /// One stored value to delete.
    ///
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public struct Deletion: Equatable, Sendable {
        public let day: String
        public let key: String

        public init(day: String, key: String) {
            self.day = day
            self.key = key
        }
    }

    /// Ascending by day, then key.
    public let upserts: [Point]
    /// Ascending by day, then key.
    public let deletions: [Deletion]
    public let reason: IntakeWriteReason
    /// Days whose protein or energy value differs from stored.
    public let changedDays: [String]

    public init(upserts: [Point], deletions: [Deletion], reason: IntakeWriteReason, changedDays: [String]) {
        self.upserts = upserts
        self.deletions = deletions
        self.reason = reason
        self.changedDays = changedDays
    }
}

/// Daily intake totals from logged samples, and what a read writes.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public enum IntakeAggregation {
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static let proteinKey = "protein_g"
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static let energyKey = "calories_in"
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static let readAtKey = "intake_read_at"

    /// The arithmetic limit of stage 1 ruling R3: an amount or a target whose magnitude is above it is
    /// treated as not finite, so no sum can overflow into an output. Not a plausibility range.
    ///
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static let largestAmountMagnitude = 1e100

    /// A stored value this close to the new one is not rewritten (§7.3 step 4).
    ///
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static let writeTolerance = 1e-9

    /// The most segments a zone log keeps (§7.1).
    ///
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static let maximumZoneSegments = 32

    // SPEC-NOTE: §7.1 gives `dayKey` as `LocalDayWindows.dayKey(for:)` with no bound on the instant.
    // That helper converts through `Int64` and day arithmetic that trap for instants near `Int.max`,
    // and this stage may never trap. The instant is therefore clamped to this magnitude (about 31 700
    // years either side of 1970) before the lookup. Every canonical day (years 0001 to 9999) lies far
    // inside it, so no key a window can admit is affected; an instant beyond it gets a key outside
    // every window and is counted `outsideWindow`.
    private static let largestInstantMagnitude = 1_000_000_000_000

    /// The zone in force at an instant: the segment with the greatest `fromEpochSeconds` at or
    /// before it; before every segment, the earliest segment. A segment whose identifier Foundation
    /// does not know is skipped. With no usable segment the zone is UTC.
    ///
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static func zone(atEpochSeconds t: Int, zoneLog: [IntakeZoneSegment]) -> TimeZone {
        ResolvedZoneLog(zoneLog).zone(at: t)
    }

    /// The local day an instant belongs to (§7.1): the calendar day it fell on in the zone in force
    /// at that instant.
    ///
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static func dayKey(epochSeconds t: Int, zoneLog: [IntakeZoneSegment]) -> String {
        ResolvedZoneLog(zoneLog).dayKey(at: t)
    }

    /// The log to store after observing `zoneIdentifier` at `now` (§7.1). Returns the input
    /// unchanged when the last segment already names that zone.
    ///
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static func appending(zoneIdentifier: String, at now: Int,
                                 to zoneLog: [IntakeZoneSegment]) -> [IntakeZoneSegment] {
        guard let last = zoneLog.last else {
            // The first segment starts at 0, not at `now`, so every earlier instant has a zone.
            return [IntakeZoneSegment(fromEpochSeconds: 0, zoneIdentifier: zoneIdentifier)]
        }
        if last.zoneIdentifier == zoneIdentifier { return zoneLog }
        var log = zoneLog
        if now <= last.fromEpochSeconds {
            // The clock moved back: the last segment's start stands and its zone is replaced.
            log[log.count - 1] = IntakeZoneSegment(fromEpochSeconds: last.fromEpochSeconds,
                                                   zoneIdentifier: zoneIdentifier)
        } else {
            log.append(IntakeZoneSegment(fromEpochSeconds: now, zoneIdentifier: zoneIdentifier))
        }
        // SPEC-NOTE: §7.1 says a log longer than 32 segments drops its second segment. A stored log
        // that is already longer than that (it cannot be produced here) is trimmed the same way,
        // repeatedly, so the result never exceeds the limit. The first segment always stays.
        while log.count > maximumZoneSegments && log.count > 1 {
            log.remove(at: 1)
        }
        return log
    }

    /// Daily totals for the day keys `firstDay ... lastDay` inclusive (§7.2).
    /// `admittedSourceIds == nil` admits every source.
    ///
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static func aggregate(samples: [IntakeSample], zoneLog: [IntakeZoneSegment],
                                 admittedSourceIds: Set<String>?,
                                 firstDay: String, lastDay: String) -> IntakeAggregationResult {
        guard let first = CanonicalDay.number(firstDay), let last = CanonicalDay.number(lastDay),
              first <= last else {
            // §6.4: with no window, every sample is outside it and no other cause is counted.
            return IntakeAggregationResult(
                totals: [], emptyDays: [],
                rejected: IntakeRejections(nonFinite: 0, negative: 0, duplicateId: 0,
                                           outsideWindow: samples.count, excludedSource: 0))
        }

        let log = ResolvedZoneLog(zoneLog)
        var nonFinite = 0, negative = 0, duplicateId = 0, outsideWindow = 0, excludedSource = 0
        var seen: Set<SampleIdentity> = []
        var admitted: [Int: [IntakeSample]] = [:]

        // §6.4: each sample is dropped and counted once, under the first check it fails.
        for sample in samples {
            guard sample.amount.isFinite, abs(sample.amount) <= largestAmountMagnitude else {
                nonFinite += 1
                continue
            }
            guard sample.amount >= 0 else {
                negative += 1
                continue
            }
            if let admittedSourceIds = admittedSourceIds, !admittedSourceIds.contains(sample.sourceId) {
                excludedSource += 1
                continue
            }
            guard let day = CanonicalDay.number(log.dayKey(at: sample.startEpochSeconds)),
                  day >= first, day <= last else {
                outsideWindow += 1
                continue
            }
            // SPEC-NOTE: §6.4 calls a duplicate "same id and nutrient as an earlier sample in the input
            // array; the first is kept". An earlier sample that was itself rejected was not kept, so it
            // does not make a later valid sample a duplicate (the committed tests take this reading).
            guard seen.insert(SampleIdentity(id: sample.id, nutrient: sample.nutrient)).inserted else {
                duplicateId += 1
                continue
            }
            admitted[day, default: []].append(sample)
        }

        var totals: [IntakeDayTotal] = []
        var emptyDays: [String] = []
        for day in first...last {
            let key = CanonicalDay.key(day)
            guard let daySamples = admitted[day], !daySamples.isEmpty else {
                emptyDays.append(key)
                continue
            }
            // §7.2 step 3: ascending (instant, id), so the last bit of a sum does not depend on the
            // order the samples arrived in.
            let ordered = daySamples.sorted {
                $0.startEpochSeconds != $1.startEpochSeconds
                    ? $0.startEpochSeconds < $1.startEpochSeconds
                    : $0.id < $1.id
            }
            var protein: Double?
            var energy: Double?
            var sources: Set<String> = []
            for sample in ordered {
                // Sums start from positive zero, so a logged negative zero totals to positive zero.
                switch sample.nutrient {
                case .protein: protein = (protein ?? 0) + sample.amount
                case .energy: energy = (energy ?? 0) + sample.amount
                }
                sources.insert(sample.sourceId)
            }
            totals.append(IntakeDayTotal(day: key, proteinGrams: protein, energyKcal: energy,
                                         sampleCount: ordered.count, sourceIds: sources.sorted()))
        }

        return IntakeAggregationResult(
            totals: totals, emptyDays: emptyDays,
            rejected: IntakeRejections(nonFinite: nonFinite, negative: negative, duplicateId: duplicateId,
                                       outsideWindow: outsideWindow, excludedSource: excludedSource))
    }

    /// What to write so the store equals `result` over its window (§7.3).
    ///
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static func plan(result: IntakeAggregationResult, stored: [IntakeStoredDay],
                            readAtEpochSeconds: Int) -> IntakeWritePlan {
        // Step 1: an empty window is no evidence that stored days are wrong, so nothing is touched.
        guard !result.totals.isEmpty else {
            return IntakeWritePlan(upserts: [], deletions: [], reason: .windowEmpty, changedDays: [])
        }

        // SPEC-NOTE: §7.3 assumes one stored entry per day. If `stored` names a day twice, the first
        // entry in the array is the one compared.
        var storedByDay: [String: IntakeStoredDay] = [:]
        for row in stored where storedByDay[row.day] == nil {
            storedByDay[row.day] = row
        }

        var upserts: [IntakeWritePlan.Point] = []
        var deletions: [IntakeWritePlan.Deletion] = []
        var changed: Set<String> = []

        // Steps 2 and 4: each measured value is upserted unless the stored one is within tolerance; a
        // nutrient no longer measured has its stored value deleted.
        func reconcile(day: String, key: String, measured: Double?, stored: Double?) {
            if let measured = measured {
                // A total built outside `aggregate` could hold NaN or infinity; it is never written.
                guard measured.isFinite else { return }
                if let stored = stored, abs(stored - measured) <= writeTolerance { return }
                upserts.append(IntakeWritePlan.Point(day: day, key: key, value: measured))
                changed.insert(day)
            } else if stored != nil {
                deletions.append(IntakeWritePlan.Deletion(day: day, key: key))
                changed.insert(day)
            }
        }

        for total in result.totals {
            let row = storedByDay[total.day]
            reconcile(day: total.day, key: proteinKey, measured: total.proteinGrams, stored: row?.proteinGrams)
            reconcile(day: total.day, key: energyKey, measured: total.energyKcal, stored: row?.energyKcal)
            // Freshness advances for every total day, whether or not a value moved.
            upserts.append(IntakeWritePlan.Point(day: total.day, key: readAtKey,
                                                 value: Double(readAtEpochSeconds)))
        }

        // Step 3: an empty day with a stored row loses all three keys and then reads "not measured".
        // SPEC-NOTE: §7.3 step 3 does not say whether a key the stored row never held is listed. All
        // three are listed whenever the row holds anything (deleting an absent value is harmless); a
        // stored entry whose three fields are all nil holds nothing and is not a stored row.
        for day in result.emptyDays {
            guard let row = storedByDay[day],
                  row.proteinGrams != nil || row.energyKcal != nil || row.readAtEpochSeconds != nil else {
                continue
            }
            for key in [proteinKey, energyKey, readAtKey] {
                deletions.append(IntakeWritePlan.Deletion(day: day, key: key))
            }
            // Step 5: only a protein or energy value that existed counts as a changed day.
            if row.proteinGrams != nil || row.energyKcal != nil {
                changed.insert(day)
            }
        }

        upserts.sort { $0.day != $1.day ? $0.day < $1.day : $0.key < $1.key }
        deletions.sort { $0.day != $1.day ? $0.day < $1.day : $0.key < $1.key }
        let changedDays = changed.sorted()
        return IntakeWritePlan(upserts: upserts, deletions: deletions,
                               reason: changedDays.isEmpty ? .unchanged : .changed,
                               changedDays: changedDays)
    }

    // MARK: - Private

    /// The identity a duplicate is judged by: one id may carry one amount of each nutrient.
    private struct SampleIdentity: Hashable {
        let id: String
        let nutrient: IntakeNutrient
    }

    /// A zone log with each identifier looked up once, so a read of many samples does not ask the
    /// zone database again for every sample.
    private struct ResolvedZoneLog {
        private let segments: [(from: Int, zone: TimeZone)]

        init(_ zoneLog: [IntakeZoneSegment]) {
            segments = zoneLog.compactMap { segment in
                TimeZone(identifier: segment.zoneIdentifier).map { (segment.fromEpochSeconds, $0) }
            }
        }

        func zone(at t: Int) -> TimeZone {
            var inForce: (from: Int, zone: TimeZone)?
            var earliest: (from: Int, zone: TimeZone)?
            for segment in segments {
                // Of two segments with the same start, the later in the log is in force.
                if segment.from <= t, inForce.map({ segment.from >= $0.from }) ?? true {
                    inForce = segment
                }
                // Of two segments with the same start, the earlier in the log is the earliest.
                if earliest.map({ segment.from < $0.from }) ?? true {
                    earliest = segment
                }
            }
            if let zone = (inForce ?? earliest)?.zone { return zone }
            return TimeZone(identifier: "UTC") ?? .gmt
        }

        func dayKey(at t: Int) -> String {
            let clamped = min(max(t, -IntakeAggregation.largestInstantMagnitude),
                              IntakeAggregation.largestInstantMagnitude)
            // The reference instant is passed so the helper never reads the clock; no key depends on it.
            let windows = LocalDayWindows(timeZone: zone(at: clamped),
                                          referenceInstant: Date(timeIntervalSince1970: 0))
            return windows.dayKey(for: Date(timeIntervalSince1970: TimeInterval(clamped)))
        }
    }
}
