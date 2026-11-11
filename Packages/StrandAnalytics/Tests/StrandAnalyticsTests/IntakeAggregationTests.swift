// API ASSUMED BY THESE TESTS
//
// Written before the implementation exists, from docs/personal/superapp/specs/stage-3.md §6.2 to
// §6.4 and §7.1 to §7.3. Every type, initialiser, member and function the tests in this file call:
//
//   public enum IntakeNutrient: String, Sendable, CaseIterable { case protein, energy }
//
//   public struct IntakeSample: Equatable, Sendable {
//       public init(id: String, nutrient: IntakeNutrient, startEpochSeconds: Int,
//                   amount: Double, sourceId: String)
//   }
//
//   public struct IntakeZoneSegment: Equatable, Sendable, Codable {
//       public let fromEpochSeconds: Int
//       public let zoneIdentifier: String
//       public init(fromEpochSeconds: Int, zoneIdentifier: String)
//   }
//
//   public struct IntakeStoredDay: Equatable, Sendable {
//       public init(day: String, proteinGrams: Double?, energyKcal: Double?, readAtEpochSeconds: Int?)
//   }
//
//   public struct IntakeDayTotal: Equatable, Sendable {            // read only; never constructed here
//       public let day: String
//       public let proteinGrams: Double?
//       public let energyKcal: Double?
//       public let sampleCount: Int
//       public let sourceIds: [String]
//   }
//
//   public struct IntakeRejections: Equatable, Sendable {          // read only
//       public let nonFinite: Int
//       public let negative: Int
//       public let duplicateId: Int
//       public let outsideWindow: Int
//       public let excludedSource: Int
//   }
//
//   public struct IntakeAggregationResult: Equatable, Sendable {   // read only; obtained from aggregate
//       public let totals: [IntakeDayTotal]
//       public let emptyDays: [String]
//       public let rejected: IntakeRejections
//   }
//
//   public enum IntakeWriteReason: String, Sendable { case windowEmpty, unchanged, changed }
//
//   public struct IntakeWritePlan: Equatable, Sendable {           // read only
//       public struct Point: Equatable, Sendable { public let day: String; public let key: String; public let value: Double }
//       public struct Deletion: Equatable, Sendable { public let day: String; public let key: String }
//       public let upserts: [Point]
//       public let deletions: [Deletion]
//       public let reason: IntakeWriteReason
//       public let changedDays: [String]
//   }
//
//   public enum IntakeAggregation {
//       public static let proteinKey = "protein_g"
//       public static let energyKey = "calories_in"
//       public static let readAtKey = "intake_read_at"
//       public static func zone(atEpochSeconds t: Int, zoneLog: [IntakeZoneSegment]) -> TimeZone
//       public static func dayKey(epochSeconds t: Int, zoneLog: [IntakeZoneSegment]) -> String
//       public static func appending(zoneIdentifier: String, at now: Int,
//                                    to zoneLog: [IntakeZoneSegment]) -> [IntakeZoneSegment]
//       public static func aggregate(samples: [IntakeSample], zoneLog: [IntakeZoneSegment],
//                                    admittedSourceIds: Set<String>?,
//                                    firstDay: String, lastDay: String) -> IntakeAggregationResult
//       public static func plan(result: IntakeAggregationResult, stored: [IntakeStoredDay],
//                               readAtEpochSeconds: Int) -> IntakeWritePlan
//   }
//
// Shared scaffolding (orchestrator's step 0, stage 6 specification §6.0), used by one test:
//
//   public enum CanonicalDay {
//       public static func number(_ key: String) -> Int?   // nil unless a canonical real "yyyy-MM-dd" key
//   }
//
// Existing test helpers used: `IntakeFixture` (this stage) and `CutScorecardFixture.day(_:_:)`.

import XCTest
@testable import StrandAnalytics

private typealias X = IntakeFixture

/// `IntakeAggregation`: the day an instant belongs to, the zone log, daily totals, and what a read
/// writes (`docs/personal/superapp/specs/stage-3.md` §6, §7.1 to §7.3, test plan §12.1, fixture §13).
///
/// Expected values were worked by hand from the specification's algorithm. Zone offsets on the fixture's
/// dates were checked with a throwaway calculation that is not committed. Every boundary is tried at
/// its value and one second (or one representable amount) either side.
final class IntakeAggregationTests: XCTestCase {

    // MARK: - Helpers

    /// One day's total, flattened so a whole result compares in one assertion without constructing the
    /// output type.
    private struct Row: Equatable {
        let day: String
        let protein: Double?
        let energy: Double?
        let count: Int
        let sources: [String]
    }

    private func row(_ day: String, _ protein: Double?, _ energy: Double?, _ count: Int,
                     _ sources: [String] = [X.foodAppId]) -> Row {
        Row(day: day, protein: protein, energy: energy, count: count, sources: sources)
    }

    private func rows(_ result: IntakeAggregationResult) -> [Row] {
        result.totals.map {
            Row(day: $0.day, protein: $0.proteinGrams, energy: $0.energyKcal,
                count: $0.sampleCount, sources: $0.sourceIds)
        }
    }

    /// Rejection counts as `[nonFinite, negative, duplicateId, outsideWindow, excludedSource]`.
    private func rejected(_ result: IntakeAggregationResult) -> [Int] {
        let r = result.rejected
        return [r.nonFinite, r.negative, r.duplicateId, r.outsideWindow, r.excludedSource]
    }

    private let noRejections = [0, 0, 0, 0, 0]

    private func aggregate(_ samples: [IntakeSample], log: [IntakeZoneSegment] = X.logU,
                           admitted: Set<String>? = nil,
                           first: String = X.firstDay, last: String = X.lastDay) -> IntakeAggregationResult {
        IntakeAggregation.aggregate(samples: samples, zoneLog: log, admittedSourceIds: admitted,
                                    firstDay: first, lastDay: last)
    }

    private func dayKey(_ iso: String, _ log: [IntakeZoneSegment]) -> String {
        IntakeAggregation.dayKey(epochSeconds: X.epoch(iso), zoneLog: log)
    }

    /// The read time used by the plan tests: 09:00 UTC on the window's last day.
    private let readAt = X.epoch("2030-12-10T09:00:00Z")
    private var readAtValue: String { "\(Double(readAt))" }

    private func stored(_ day: String, _ protein: Double?, _ energy: Double?,
                        readAt: Int? = X.epoch("2030-12-10T06:00:00Z")) -> IntakeStoredDay {
        IntakeStoredDay(day: day, proteinGrams: protein, energyKcal: energy, readAtEpochSeconds: readAt)
    }

    private func plan(_ result: IntakeAggregationResult, _ stored: [IntakeStoredDay]) -> IntakeWritePlan {
        IntakeAggregation.plan(result: result, stored: stored, readAtEpochSeconds: readAt)
    }

    /// Upserts as "day key value" lines, in the plan's own order.
    private func upserts(_ plan: IntakeWritePlan) -> [String] {
        plan.upserts.map { "\($0.day) \($0.key) \($0.value)" }
    }

    /// Deletions as "day key" lines, in the plan's own order.
    private func deletions(_ plan: IntakeWritePlan) -> [String] {
        plan.deletions.map { "\($0.day) \($0.key)" }
    }

    /// What the store holds after the fixture's first read (s1 to s8, log U).
    private var storedAfterFirstRead: [IntakeStoredDay] {
        [stored("2030-12-09", 95, 1450), stored("2030-12-10", 20, 250)]
    }

    // MARK: - The fixture itself

    func testFixtureInstantsAreTheStatedUTCInstants() {
        // 2030-12-09 is 22 257 days after 1970-01-01: 60 years with 15 leap days, then 342 days.
        XCTAssertEqual(X.epoch("2030-12-09T00:00:00Z"), 1_923_004_800)
        XCTAssertEqual(X.epoch("2030-12-09T23:59:59Z"), 1_923_091_199)
        XCTAssertEqual(X.epoch("2030-12-10T00:00:00Z"), 1_923_091_200)
        XCTAssertEqual(X.utcDayKey(1_923_091_199), "2030-12-09")
        XCTAssertEqual(X.utcDayKey(1_923_091_200), "2030-12-10")
        XCTAssertEqual(X.localDayKey(-1, offsetSeconds: 0), "1969-12-31")
    }

    func testStorageKeysAreTheExistingSeriesKeys() {
        XCTAssertEqual(IntakeAggregation.proteinKey, "protein_g")
        XCTAssertEqual(IntakeAggregation.energyKey, "calories_in")
        XCTAssertEqual(IntakeAggregation.readAtKey, "intake_read_at")
    }

    // MARK: - Aggregation (§7.2)

    func testSeveralEntriesInADayAreSummed() {
        let result = aggregate([X.s1, X.s3, X.s5])
        XCTAssertEqual(rows(result), [row("2030-12-09", 95, nil, 3)])
        XCTAssertEqual(result.emptyDays, ["2030-12-10"])
        XCTAssertEqual(rejected(result), noRejections)
    }

    func testProteinAndEnergyAreSummedIndependently() {
        let result = aggregate(X.foodSamples)
        XCTAssertEqual(rows(result), [row("2030-12-09", 95, 1450, 6), row("2030-12-10", 20, 250, 2)])
        // Removing one nutrient's entry moves only that nutrient's total.
        let withoutOneEnergy = aggregate(X.foodSamples.filter { $0.id != "s4" })
        XCTAssertEqual(rows(withoutOneEnergy), [row("2030-12-09", 95, 750, 5), row("2030-12-10", 20, 250, 2)])
        let withoutOneProtein = aggregate(X.foodSamples.filter { $0.id != "s3" })
        XCTAssertEqual(rows(withoutOneProtein), [row("2030-12-09", 55, 1450, 5), row("2030-12-10", 20, 250, 2)])
    }

    func testADayWithEnergyButNoProteinHasNilProtein() {
        let result = aggregate([X.s2, X.s4, X.s7])
        // Not measured is nil, never zero (R25 onward): the 9th has no protein figure, the 10th no energy.
        XCTAssertEqual(rows(result), [row("2030-12-09", nil, 1150, 2), row("2030-12-10", 20, nil, 1)])
        XCTAssertNil(result.totals.first?.proteinGrams)
        XCTAssertNil(result.totals.last?.energyKcal)
        XCTAssertEqual(result.emptyDays, [])
    }

    func testAZeroAmountIsASampleNotAnAbsence() {
        let zero = X.protein("z", "2030-12-10T12:00:00Z", 0)
        let result = aggregate([X.s1, zero])
        XCTAssertEqual(rows(result), [row("2030-12-09", 30, nil, 1), row("2030-12-10", 0, nil, 1)])
        XCTAssertNotNil(result.totals.last?.proteinGrams, "a logged zero is a measurement")
        XCTAssertEqual(result.emptyDays, [], "a day holding a zero-amount sample is not an empty day")
        XCTAssertEqual(rejected(result), noRejections)
        // A measured zero is written; only an *empty* day is never written as zero.
        XCTAssertTrue(upserts(plan(result, [])).contains("2030-12-10 protein_g 0.0"))
        // Zero and the smallest amounts either side of it.
        let tiny = aggregate([X.protein("p", "2030-12-09T12:00:00Z", .leastNonzeroMagnitude)])
        XCTAssertEqual(rows(tiny), [row("2030-12-09", Double.leastNonzeroMagnitude, nil, 1)])
        let below = aggregate([X.protein("n", "2030-12-09T12:00:00Z", -.leastNonzeroMagnitude)])
        XCTAssertEqual(rows(below), [])
        XCTAssertEqual(rejected(below), [0, 1, 0, 0, 0])
    }

    func testTwoSourcesAreBothCountedByDefault() {
        let result = aggregate(X.allSamples)
        XCTAssertEqual(rows(result), [
            row("2030-12-09", 105, 1450, 7, [X.foodAppId, X.otherAppId]),
            row("2030-12-10", 20, 250, 2, [X.foodAppId]),
        ])
        XCTAssertEqual(rejected(result), noRejections)
        // Source ids are distinct and ascending whatever order the samples arrive in.
        let reversed = aggregate(Array(X.allSamples.reversed()))
        XCTAssertEqual(reversed.totals.first?.sourceIds, [X.foodAppId, X.otherAppId])
    }

    func testAnExcludedSourceIsDroppedAndCounted() {
        let foodOnly = aggregate(X.allSamples, admitted: [X.foodAppId])
        XCTAssertEqual(rows(foodOnly), [row("2030-12-09", 95, 1450, 6), row("2030-12-10", 20, 250, 2)])
        XCTAssertEqual(rejected(foodOnly), [0, 0, 0, 0, 1])

        let otherOnly = aggregate(X.allSamples, admitted: [X.otherAppId])
        XCTAssertEqual(rows(otherOnly), [row("2030-12-09", 10, nil, 1, [X.otherAppId])])
        XCTAssertEqual(otherOnly.emptyDays, ["2030-12-10"])
        XCTAssertEqual(rejected(otherOnly), [0, 0, 0, 0, 8])

        let both = aggregate(X.allSamples, admitted: [X.foodAppId, X.otherAppId])
        XCTAssertEqual(both, aggregate(X.allSamples), "naming every source is the same as admitting all")

        // An empty admitted set is a set that admits nothing; only nil admits every source.
        let none = aggregate(X.allSamples, admitted: [])
        XCTAssertEqual(rows(none), [])
        XCTAssertEqual(none.emptyDays, ["2030-12-09", "2030-12-10"])
        XCTAssertEqual(rejected(none), [0, 0, 0, 0, 9])
    }

    func testAnEditedEntryWithANewIdReplacesTheOldAmount() {
        // Each read is a full replacement: the second read holds s3b where the first held s3.
        let second = aggregate([X.s1, X.s2, X.s3b, X.s4, X.s5, X.s6, X.s7, X.s8])
        XCTAssertEqual(rows(second), [row("2030-12-09", 100, 1450, 6), row("2030-12-10", 20, 250, 2)])
        let written = plan(second, storedAfterFirstRead)
        XCTAssertEqual(upserts(written), [
            "2030-12-09 intake_read_at \(readAtValue)", "2030-12-09 protein_g 100.0",
            "2030-12-10 intake_read_at \(readAtValue)",
        ])
        XCTAssertEqual(deletions(written), [])
        XCTAssertEqual(written.changedDays, ["2030-12-09"])
        XCTAssertEqual(written.reason, .changed)
    }

    func testAnEditedEntryKeepingItsIdUsesTheNewAmount() {
        let second = aggregate([X.s1, X.s2, X.s3SameId, X.s4, X.s5, X.s6, X.s7, X.s8])
        XCTAssertEqual(rows(second), [row("2030-12-09", 100, 1450, 6), row("2030-12-10", 20, 250, 2)])
        XCTAssertEqual(rejected(second), noRejections)
        // Whether the food app keeps or replaces the id does not matter.
        XCTAssertEqual(second, aggregate([X.s1, X.s2, X.s3b, X.s4, X.s5, X.s6, X.s7, X.s8]))
    }

    func testADeletedEntryLowersTheTotal() {
        let result = aggregate(X.foodSamples.filter { $0.id != "s5" && $0.id != "s6" })
        XCTAssertEqual(rows(result), [row("2030-12-09", 70, 1150, 4), row("2030-12-10", 20, 250, 2)])
        let written = plan(result, storedAfterFirstRead)
        XCTAssertEqual(upserts(written), [
            "2030-12-09 calories_in 1150.0", "2030-12-09 intake_read_at \(readAtValue)",
            "2030-12-09 protein_g 70.0", "2030-12-10 intake_read_at \(readAtValue)",
        ])
        XCTAssertEqual(written.changedDays, ["2030-12-09"])
    }

    func testADayThatLosesEveryEntryBecomesAnEmptyDay() {
        let result = aggregate(X.foodSamples.filter { $0.id != "s7" && $0.id != "s8" })
        XCTAssertEqual(rows(result), [row("2030-12-09", 95, 1450, 6)])
        XCTAssertEqual(result.emptyDays, ["2030-12-10"])
        XCTAssertFalse(result.totals.contains { $0.day == "2030-12-10" },
                       "an emptied day has no total at all: it is not a zero total")
    }

    func testEntryOneSecondBeforeMidnightBelongsToThatDay() {
        XCTAssertEqual(dayKey("2030-12-09T23:59:59Z", X.logU), "2030-12-09")
        XCTAssertEqual(rows(aggregate([X.s5, X.s6])), [row("2030-12-09", 25, 300, 2)])
        // The same boundary away from UTC: local midnight in Kolkata is 18:30 UTC.
        let kolkata = [X.segment(0, "Asia/Kolkata")]
        XCTAssertEqual(dayKey("2030-12-09T18:29:59Z", kolkata), "2030-12-09")
        // One second before the *first* day of the window is outside it.
        let early = aggregate([X.protein("e", "2030-12-08T23:59:59Z", 5)])
        XCTAssertEqual(rows(early), [])
        XCTAssertEqual(rejected(early), [0, 0, 0, 1, 0])
    }

    func testEntryAtMidnightBelongsToTheNextDay() {
        XCTAssertEqual(dayKey("2030-12-10T00:00:00Z", X.logU), "2030-12-10")
        XCTAssertEqual(dayKey("2030-12-10T00:00:01Z", X.logU), "2030-12-10")
        XCTAssertEqual(rows(aggregate([X.s7, X.s8])), [row("2030-12-10", 20, 250, 2)])
        // The two fixture pairs one second apart land on different days.
        XCTAssertEqual(rows(aggregate([X.s5, X.s7])), [row("2030-12-09", 25, nil, 1), row("2030-12-10", 20, nil, 1)])
        let kolkata = [X.segment(0, "Asia/Kolkata")]
        XCTAssertEqual(dayKey("2030-12-09T18:30:00Z", kolkata), "2030-12-10")
        // Midnight opening the first day of the window is inside it; midnight after the last is outside.
        let first = aggregate([X.protein("f", "2030-12-09T00:00:00Z", 5)])
        XCTAssertEqual(rows(first), [row("2030-12-09", 5, nil, 1)])
        let after = aggregate([X.protein("a", "2030-12-11T00:00:00Z", 5)])
        XCTAssertEqual(rows(after), [])
        XCTAssertEqual(rejected(after), [0, 0, 0, 1, 0])
        let lastSecond = aggregate([X.protein("l", "2030-12-10T23:59:59Z", 5)])
        XCTAssertEqual(rows(lastSecond), [row("2030-12-10", 5, nil, 1)])
    }

    func testDuplicateIdsAreCountedOnceFirstWins() {
        let again = X.protein("s1", "2030-12-09T09:00:00Z", 99)
        let result = aggregate([X.s1, again, X.s3])
        XCTAssertEqual(rows(result), [row("2030-12-09", 70, nil, 2)])
        XCTAssertEqual(rejected(result), [0, 0, 1, 0, 0])
        // The first in the input array is the one kept, not the earliest instant or the larger amount.
        let other = aggregate([again, X.s1, X.s3])
        XCTAssertEqual(rows(other), [row("2030-12-09", 139, nil, 2)])
        XCTAssertEqual(rejected(other), [0, 0, 1, 0, 0])
        // An exact repeat delivered three times counts once.
        let thrice = aggregate([X.s1, X.s1, X.s1])
        XCTAssertEqual(rows(thrice), [row("2030-12-09", 30, nil, 1)])
        XCTAssertEqual(rejected(thrice), [0, 0, 2, 0, 0])
        // A duplicate on another day is still a duplicate: the id is the identity, not the day.
        let moved = aggregate([X.s1, X.protein("s1", "2030-12-10T09:00:00Z", 30)])
        XCTAssertEqual(rows(moved), [row("2030-12-09", 30, nil, 1)])
        XCTAssertEqual(moved.emptyDays, ["2030-12-10"])
        XCTAssertEqual(rejected(moved), [0, 0, 1, 0, 0])
    }

    func testTheSameIdForTwoNutrientsIsNotADuplicate() {
        let protein = X.protein("meal", "2030-12-09T12:00:00Z", 30)
        let energy = X.energy("meal", "2030-12-09T12:00:00Z", 450)
        let result = aggregate([protein, energy])
        XCTAssertEqual(rows(result), [row("2030-12-09", 30, 450, 2)])
        XCTAssertEqual(rejected(result), noRejections)
    }

    func testNonFiniteAndNegativeAmountsAreRejectedAndCounted() {
        let bad = [
            X.protein("nan", "2030-12-09T09:00:00Z", .nan),
            X.protein("inf", "2030-12-09T09:00:00Z", .infinity),
            X.energy("ninf", "2030-12-09T09:00:00Z", -.infinity),
            X.protein("neg", "2030-12-09T09:00:00Z", -1),
            X.energy("small", "2030-12-09T09:00:00Z", -0.001),
        ]
        let result = aggregate(bad + [X.s1])
        XCTAssertEqual(rows(result), [row("2030-12-09", 30, nil, 1)])
        // Negative infinity is not finite, and that check comes first.
        XCTAssertEqual(rejected(result), [3, 2, 0, 0, 0])
        // A day whose only samples were rejected is an empty day, not a zero.
        let onlyBad = aggregate(bad)
        XCTAssertEqual(rows(onlyBad), [])
        XCTAssertEqual(onlyBad.emptyDays, ["2030-12-09", "2030-12-10"])
        XCTAssertEqual(rejected(onlyBad), [3, 2, 0, 0, 0])
    }

    func testEachSampleIsCountedUnderItsFirstFailingCheckOnly() {
        // §6.4 order: nonFinite, negative, excludedSource, outsideWindow, duplicateId.
        let admitted: Set<String> = [X.foodAppId]
        let nanExcludedOutside = X.protein("a", "2030-12-01T09:00:00Z", .nan, source: X.otherAppId)
        XCTAssertEqual(rejected(aggregate([nanExcludedOutside], admitted: admitted)), [1, 0, 0, 0, 0])
        let negativeExcludedOutside = X.protein("b", "2030-12-01T09:00:00Z", -3, source: X.otherAppId)
        XCTAssertEqual(rejected(aggregate([negativeExcludedOutside], admitted: admitted)), [0, 1, 0, 0, 0])
        let excludedOutside = X.protein("c", "2030-12-01T09:00:00Z", 3, source: X.otherAppId)
        XCTAssertEqual(rejected(aggregate([excludedOutside], admitted: admitted)), [0, 0, 0, 0, 1])
        let outside = X.protein("d", "2030-12-01T09:00:00Z", 3)
        XCTAssertEqual(rejected(aggregate([outside, outside], admitted: admitted)), [0, 0, 0, 2, 0],
                       "a repeat of a sample outside the window is outside the window, not a duplicate")
        let all = aggregate([nanExcludedOutside, negativeExcludedOutside, excludedOutside, outside, X.s1, X.s1],
                            admitted: admitted)
        XCTAssertEqual(rejected(all), [1, 1, 1, 1, 1])
        XCTAssertEqual(rows(all), [row("2030-12-09", 30, nil, 1)])
    }

    func testARejectedSampleDoesNotMakeALaterSampleWithItsIdADuplicate() {
        // SPEC-AMBIGUITY: §6.4 calls a duplicate "same id and nutrient as an earlier sample in the input
        // array; the first is kept". When the earlier sample was itself rejected, nothing was kept, so
        // the later valid one is read here as admitted: a corrupt twin must not erase a real reading.
        let corrupt = X.protein("s1", "2030-12-09T08:00:00Z", .nan)
        let result = aggregate([corrupt, X.s1])
        XCTAssertEqual(rows(result), [row("2030-12-09", 30, nil, 1)])
        XCTAssertEqual(rejected(result), [1, 0, 0, 0, 0])
    }

    func testAmountsAboveTheArithmeticLimitAreRejected() {
        let at = aggregate([X.protein("at", "2030-12-09T09:00:00Z", 1e100)])
        XCTAssertEqual(rows(at), [row("2030-12-09", 1e100, nil, 1)], "exactly the limit is admitted")
        XCTAssertEqual(rejected(at), noRejections)
        let under = aggregate([X.energy("under", "2030-12-09T09:00:00Z", (1e100).nextDown)])
        XCTAssertEqual(rejected(under), noRejections)
        let over = aggregate([X.protein("over", "2030-12-09T09:00:00Z", (1e100).nextUp)])
        XCTAssertEqual(rows(over), [])
        XCTAssertEqual(rejected(over), [1, 0, 0, 0, 0])
        XCTAssertEqual(rejected(aggregate([X.energy("max", "2030-12-09T09:00:00Z", .greatestFiniteMagnitude)])),
                       [1, 0, 0, 0, 0])
        // The limit is on magnitude: a huge negative amount is `nonFinite`; one at the limit is `negative`.
        XCTAssertEqual(rejected(aggregate([X.protein("n", "2030-12-09T09:00:00Z", -(1e100).nextUp)])),
                       [1, 0, 0, 0, 0])
        XCTAssertEqual(rejected(aggregate([X.protein("n", "2030-12-09T09:00:00Z", -1e100)])), [0, 1, 0, 0, 0])
        // Many amounts at the limit still sum to a finite total.
        let many = (0..<50).map { X.protein("m\($0)", "2030-12-09T09:00:00Z", 1e100) }
        let total = aggregate(many).totals.first?.proteinGrams
        XCTAssertEqual(total ?? .nan, 5e101, accuracy: 1e88)
        XCTAssertTrue(total?.isFinite ?? false)
    }

    func testSamplesOutsideTheWindowAreRejectedAndCounted() {
        let firstOnly = aggregate(X.foodSamples, last: "2030-12-09")
        XCTAssertEqual(rows(firstOnly), [row("2030-12-09", 95, 1450, 6)])
        XCTAssertEqual(firstOnly.emptyDays, [])
        XCTAssertEqual(rejected(firstOnly), [0, 0, 0, 2, 0])

        let lastOnly = aggregate(X.foodSamples, first: "2030-12-10")
        XCTAssertEqual(rows(lastOnly), [row("2030-12-10", 20, 250, 2)])
        XCTAssertEqual(rejected(lastOnly), [0, 0, 0, 6, 0])

        // A wider window admits everything and reports the unlogged days around it as empty.
        let wide = aggregate(X.foodSamples, first: "2030-12-08", last: "2030-12-12")
        XCTAssertEqual(rows(wide), [row("2030-12-09", 95, 1450, 6), row("2030-12-10", 20, 250, 2)])
        XCTAssertEqual(wide.emptyDays, ["2030-12-08", "2030-12-11", "2030-12-12"])
        XCTAssertEqual(rejected(wide), noRejections)

        // An entry dated after the last day is outside, however near.
        let later = aggregate([X.s1, X.protein("later", "2030-12-11T00:00:00Z", 40)])
        XCTAssertEqual(rejected(later), [0, 0, 0, 1, 0])
        XCTAssertEqual(later.emptyDays, ["2030-12-10"])
    }

    func testTheWindowIsJudgedByTheLocalDayNotTheUTCDay() {
        // 2030-12-10T12:00Z is the 11th in Auckland: outside a window ending on the 10th.
        let auckland = [X.segment(0, X.auckland)]
        let sample = X.protein("p", "2030-12-10T12:00:00Z", 30)
        XCTAssertEqual(rejected(aggregate([sample], log: auckland)), [0, 0, 0, 1, 0])
        XCTAssertEqual(rows(aggregate([sample], log: X.logU)), [row("2030-12-10", 30, nil, 1)])
        // 2030-12-08T12:00Z is the 9th in Auckland: inside, though its UTC day is before the window.
        let early = X.protein("q", "2030-12-08T12:00:00Z", 30)
        XCTAssertEqual(rows(aggregate([early], log: auckland)), [row("2030-12-09", 30, nil, 1)])
        XCTAssertEqual(rejected(aggregate([early], log: X.logU)), [0, 0, 0, 1, 0])
    }

    func testAnInvalidWindowYieldsNothing() {
        let windows: [(String, String)] = [
            ("2030-12-10", "2030-12-09"),      // first after last
            ("2030-12-9", "2030-12-10"),       // not ten characters
            ("2030-12-09", "2030-13-01"),      // not a real month
            ("2030-02-30", "2030-12-10"),      // not a real date
            ("", "2030-12-10"),
            ("2030-12-09", ""),
            ("0000-12-09", "2030-12-10"),      // year 0 is outside 0001 to 9999
        ]
        for (first, last) in windows {
            let result = aggregate(X.allSamples, first: first, last: last)
            XCTAssertEqual(rows(result), [], "\(first) ... \(last)")
            XCTAssertEqual(result.emptyDays, [], "\(first) ... \(last)")
            XCTAssertEqual(rejected(result), [0, 0, 0, 9, 0], "\(first) ... \(last)")
            // Nothing can be written from it.
            let written = plan(result, storedAfterFirstRead)
            XCTAssertEqual(upserts(written), [])
            XCTAssertEqual(deletions(written), [])
            XCTAssertEqual(written.reason, .windowEmpty)
        }
        XCTAssertEqual(rejected(aggregate([], first: "2030-12-10", last: "2030-12-09")), noRejections)
        // A one-day window is valid: first may equal last.
        XCTAssertEqual(rows(aggregate(X.foodSamples, first: "2030-12-10", last: "2030-12-10")),
                       [row("2030-12-10", 20, 250, 2)])
    }

    func testAnInvalidWindowCountsEverySampleAsOutsideTheWindow() {
        // SPEC-AMBIGUITY: §6.4 gives a check order that starts with `nonFinite`, and also says that with
        // an invalid window "every sample [is] counted as outsideWindow". The second sentence is the
        // more specific one and is followed here: no other cause is counted when no window exists.
        let samples = [
            X.s1,
            X.protein("nan", "2030-12-09T09:00:00Z", .nan),
            X.protein("neg", "2030-12-09T09:00:00Z", -1),
            X.s1,
            X.s9,
        ]
        let result = aggregate(samples, admitted: [X.foodAppId], first: "2030-12-10", last: "2030-12-09")
        XCTAssertEqual(rejected(result), [0, 0, 0, 5, 0])
        XCTAssertEqual(rows(result), [])
        XCTAssertEqual(result.emptyDays, [])
    }

    func testWindowValidityFollowsCanonicalDay() {
        let keys = [
            "2030-12-08", "2030-12-09", "2030-12-10", "2030-12-31", "2031-01-01",
            "2032-02-29",                       // a real leap day
            "2031-02-29", "2030-02-30", "2030-04-31", "2030-13-01", "2030-00-10", "2030-12-00",
            "2030-12-9", "2030-1-09", "30-12-09", "02030-12-09", "20301209", "2030/12/09",
            "2030-12-09 ", " 2030-12-09", "2030-12-09T00:00:00Z", "", "today", "yyyy-MM-dd",
            "٢٠٣٠-١٢-٠٩",                       // not ASCII digits
            "0000-01-01", "0001-01-01", "9999-12-31", "10000-01-01",
        ]
        let sample = X.protein("p", "2030-12-09T12:00:00Z", 30)
        var accepted = 0
        for first in keys {
            for last in keys {
                let a = CanonicalDay.number(first), b = CanonicalDay.number(last)
                // Far-apart valid ends are skipped: the window would hold millions of empty days.
                if let a = a, let b = b, b - a > 800 { continue }
                let result = aggregate([sample], first: first, last: last)
                let days = result.totals.count + result.emptyDays.count
                if let a = a, let b = b, a <= b {
                    accepted += 1
                    XCTAssertEqual(days, b - a + 1, "'\(first)' ... '\(last)' is a valid window")
                } else {
                    XCTAssertEqual(days, 0, "'\(first)' ... '\(last)' is not a valid window")
                    XCTAssertEqual(rejected(result), [0, 0, 0, 1, 0], "'\(first)' ... '\(last)'")
                }
            }
        }
        // The spread must exercise both outcomes, whatever `CanonicalDay` decides for each key.
        XCTAssertGreaterThanOrEqual(accepted, 20)
        // The canonical keys of this spread, pinned so the test cannot pass against a rule that accepts
        // or refuses everything (stage 1 R5).
        XCTAssertNotNil(CanonicalDay.number("2030-12-09"))
        XCTAssertNotNil(CanonicalDay.number("2032-02-29"))
        XCTAssertNotNil(CanonicalDay.number("0001-01-01"))
        XCTAssertNotNil(CanonicalDay.number("9999-12-31"))
        XCTAssertNil(CanonicalDay.number("2031-02-29"))
        XCTAssertNil(CanonicalDay.number("2030-12-9"))
        XCTAssertNil(CanonicalDay.number("0000-01-01"))
        XCTAssertNil(CanonicalDay.number("10000-01-01"))
        XCTAssertNil(CanonicalDay.number(""))
    }

    func testResultDoesNotDependOnInputOrder() {
        let extra = [
            X.protein("nan", "2030-12-09T09:00:00Z", .nan),
            X.energy("neg", "2030-12-10T09:00:00Z", -4),
            X.protein("out", "2030-12-13T09:00:00Z", 12),
        ]
        let samples = X.allSamples + extra
        for (log, admitted) in [(X.logU, nil), (X.logE, nil), (X.logW, Set([X.foodAppId]))] as [([IntakeZoneSegment], Set<String>?)] {
            let reference = aggregate(samples, log: log, admitted: admitted)
            XCTAssertEqual(aggregate(Array(samples.reversed()), log: log, admitted: admitted), reference)
            var generator = X.Generator(state: 0x5EED_0003)
            for _ in 0..<40 {
                XCTAssertEqual(aggregate(generator.shuffled(samples), log: log, admitted: admitted), reference)
            }
        }
    }

    func testSumsAreTakenInAscendingInstantThenIdOrder() {
        // (0.1 + 0.2) + 0.3 is 0.6000000000000001; (0.3 + 0.2) + 0.1 is 0.6. Summing in input order
        // would give a different last bit for each arrival order.
        let ascending = (0.1 + 0.2) + 0.3
        XCTAssertNotEqual(ascending, (0.3 + 0.2) + 0.1, "the three amounts must distinguish the orders")
        let byInstant = [
            X.protein("c", "2030-12-09T08:00:00Z", 0.1),
            X.protein("a", "2030-12-09T09:00:00Z", 0.2),
            X.protein("b", "2030-12-09T10:00:00Z", 0.3),
        ]
        // The same instant: the id decides.
        let byId = [
            X.energy("a", "2030-12-09T08:00:00Z", 0.1),
            X.energy("b", "2030-12-09T08:00:00Z", 0.2),
            X.energy("c", "2030-12-09T08:00:00Z", 0.3),
        ]
        let orders = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
        for order in orders {
            let protein = aggregate(order.map { byInstant[$0] }).totals.first?.proteinGrams
            XCTAssertEqual(protein, ascending, "instant order, input order \(order)")
            let energy = aggregate(order.map { byId[$0] }).totals.first?.energyKcal
            XCTAssertEqual(energy, ascending, "id order, input order \(order)")
        }
    }

    func testTotalsAreNotRoundedOrQuantized() {
        let result = aggregate([X.protein("a", "2030-12-09T08:00:00Z", 30.0004),
                                X.protein("b", "2030-12-09T09:00:00Z", 0.0001)])
        XCTAssertEqual(result.totals.first?.proteinGrams, 30.0004 + 0.0001)
    }

    func testAggregationIsDeterministic() {
        let first = aggregate(X.allSamples, log: X.logE, admitted: [X.foodAppId])
        for _ in 0..<5 {
            XCTAssertEqual(aggregate(X.allSamples, log: X.logE, admitted: [X.foodAppId]), first)
        }
        XCTAssertEqual(plan(first, storedAfterFirstRead), plan(first, storedAfterFirstRead))
    }

    func testFixtureDayTotals() {
        // §13.3, every row of the log U table.
        let food = aggregate(X.foodSamples)
        XCTAssertEqual(rows(food), [row("2030-12-09", 95, 1450, 6), row("2030-12-10", 20, 250, 2)])
        XCTAssertEqual(food.emptyDays, [])
        XCTAssertEqual(rejected(food), noRejections)

        XCTAssertEqual(rows(aggregate(X.allSamples)), [
            row("2030-12-09", 105, 1450, 7, [X.foodAppId, X.otherAppId]), row("2030-12-10", 20, 250, 2),
        ])

        let admitted = aggregate(X.allSamples, admitted: [X.foodAppId])
        XCTAssertEqual(rows(admitted), rows(food))
        XCTAssertEqual(rejected(admitted), [0, 0, 0, 0, 1])

        // The edit lands exactly on the 100 g floor.
        let edited = aggregate([X.s1, X.s2, X.s3b, X.s4, X.s5, X.s6, X.s7, X.s8])
        XCTAssertEqual(rows(edited), [row("2030-12-09", 100, 1450, 6), row("2030-12-10", 20, 250, 2)])
        XCTAssertEqual(edited.totals.first?.proteinGrams, X.proteinFloorGrams)

        XCTAssertEqual(rows(aggregate([X.s1, X.s2, X.s3, X.s4, X.s7, X.s8])),
                       [row("2030-12-09", 70, 1150, 4), row("2030-12-10", 20, 250, 2)])

        let emptied = aggregate([X.s1, X.s2, X.s3, X.s4, X.s5, X.s6])
        XCTAssertEqual(rows(emptied), [row("2030-12-09", 95, 1450, 6)])
        XCTAssertEqual(emptied.emptyDays, ["2030-12-10"])
        XCTAssertEqual(deletions(plan(emptied, storedAfterFirstRead)), [
            "2030-12-10 calories_in", "2030-12-10 intake_read_at", "2030-12-10 protein_g",
        ])

        let nothing = aggregate([])
        XCTAssertEqual(rows(nothing), [])
        XCTAssertEqual(nothing.emptyDays, ["2030-12-09", "2030-12-10"])
        let untouched = plan(nothing, storedAfterFirstRead)
        XCTAssertEqual(upserts(untouched), [])
        XCTAssertEqual(deletions(untouched), [])

        // Zone log E: the UTC day holds s1 to s4, the Auckland day s5 to s8.
        XCTAssertEqual(rows(aggregate(X.foodSamples, log: X.logE)),
                       [row("2030-12-09", 70, 1150, 4), row("2030-12-10", 45, 550, 4)])

        // Zone log W: the later instant is on the earlier day, and each is counted once.
        XCTAssertEqual(rows(aggregate([X.westX, X.westY], log: X.logW)),
                       [row("2030-12-09", 15, nil, 1), row("2030-12-10", 10, nil, 1)])
    }

    func testGeneratedSamplesMatchAnIndependentModel() {
        // The model keys each instant with the fixture's own arithmetic: UTC before the eastward change,
        // a fixed thirteen hours ahead after it (Auckland keeps one offset over these days). Amounts are
        // whole numbers, so sums are exact in any order.
        let windowDays = ["2030-12-08", "2030-12-09", "2030-12-10", "2030-12-11"]
        let base = X.epoch("2030-12-07T00:00:00Z")
        var generator = X.Generator(state: 0x5EED_0301)
        for round in 0..<30 {
            let admitted: Set<String>? = round % 2 == 0 ? nil : [X.foodAppId]
            var samples: [IntakeSample] = []
            var protein: [String: Double] = [:], energy: [String: Double] = [:]
            var count: [String: Int] = [:], sources: [String: Set<String>] = [:]
            var expected = [0, 0, 0, 0, 0]
            for index in 0..<60 {
                // One instant in twelve sits exactly on the change, or one second before it.
                let pick = generator.next(12)
                let t = pick == 0 ? X.eastwardChange : pick == 1 ? X.eastwardChange - 1
                    : base + generator.next(6 * 86_400)
                let nutrient: IntakeNutrient = generator.next(2) == 0 ? .protein : .energy
                let source = generator.next(3) == 0 ? X.otherAppId : X.foodAppId
                let kind = generator.next(12)
                let amount: Double = kind == 0 ? .nan : kind == 1 ? -5 : Double(generator.next(61))
                samples.append(IntakeSample(id: "g\(index)", nutrient: nutrient, startEpochSeconds: t,
                                            amount: amount, sourceId: source))
                let day = X.localDayKey(t, offsetSeconds: t >= X.eastwardChange ? X.aucklandOffsetSeconds : 0)
                if amount.isNaN { expected[0] += 1; continue }
                if amount < 0 { expected[1] += 1; continue }
                if let admitted = admitted, !admitted.contains(source) { expected[4] += 1; continue }
                if !windowDays.contains(day) { expected[3] += 1; continue }
                if nutrient == .protein { protein[day, default: 0] += amount } else { energy[day, default: 0] += amount }
                count[day, default: 0] += 1
                sources[day, default: []].insert(source)
            }
            let result = aggregate(samples, log: X.logE, admitted: admitted,
                                   first: windowDays[0], last: windowDays[3])
            let expectedRows = windowDays.filter { count[$0] != nil }.map {
                Row(day: $0, protein: protein[$0], energy: energy[$0], count: count[$0] ?? 0,
                    sources: (sources[$0] ?? []).sorted())
            }
            XCTAssertEqual(rows(result), expectedRows, "round \(round)")
            XCTAssertEqual(result.emptyDays, windowDays.filter { count[$0] == nil }, "round \(round)")
            XCTAssertEqual(rejected(result), expected, "round \(round)")
            // Conservation: every sample is admitted once or rejected once.
            XCTAssertEqual(result.totals.reduce(0) { $0 + $1.sampleCount } + rejected(result).reduce(0, +),
                           samples.count, "round \(round)")
            // What the plan writes is exactly what was measured: no value for an unmeasured nutrient,
            // nothing for an empty day.
            let written = plan(result, [])
            let expectedUpserts = expectedRows.flatMap { r -> [String] in
                var lines: [String] = []
                if let kcal = r.energy { lines.append("\(r.day) calories_in \(kcal)") }
                lines.append("\(r.day) intake_read_at \(readAtValue)")
                if let grams = r.protein { lines.append("\(r.day) protein_g \(grams)") }
                return lines
            }
            XCTAssertEqual(upserts(written), expectedUpserts, "round \(round)")
            XCTAssertEqual(deletions(written), [], "round \(round)")
        }
    }

    // MARK: - Zones (§7.1)

    func testEmptyZoneLogCountsDaysInUTC() {
        XCTAssertEqual(dayKey("2030-12-09T23:59:59Z", []), "2030-12-09")
        XCTAssertEqual(dayKey("2030-12-10T00:00:00Z", []), "2030-12-10")
        let zone = IntakeAggregation.zone(atEpochSeconds: X.epoch("2030-12-09T12:00:00Z"), zoneLog: [])
        XCTAssertEqual(zone.secondsFromGMT(for: Date(timeIntervalSince1970: 1_923_048_000)), 0)
        XCTAssertEqual(aggregate(X.foodSamples, log: []), aggregate(X.foodSamples, log: X.logU))
    }

    func testAnUnknownZoneIdentifierIsSkipped() {
        let noon = X.epoch("2030-12-09T12:00:00Z")
        // Unknown after a known segment: the known one stays in force.
        let trailing = [X.segment(0, X.auckland), X.segment(X.epoch("2030-12-09T06:00:00Z"), "Not/AZone")]
        XCTAssertEqual(IntakeAggregation.zone(atEpochSeconds: noon, zoneLog: trailing).identifier, X.auckland)
        XCTAssertEqual(dayKey("2030-12-09T12:00:00Z", trailing), "2030-12-10")
        // Only unknown segments: no usable segment, so UTC.
        let onlyUnknown = [X.segment(0, "Not/AZone"), X.segment(1_000, "")]
        let fallback = IntakeAggregation.zone(atEpochSeconds: noon, zoneLog: onlyUnknown)
        XCTAssertEqual(fallback.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(noon))), 0)
        XCTAssertEqual(dayKey("2030-12-09T12:00:00Z", onlyUnknown), "2030-12-09")
        // Unknown first: the earliest *usable* segment covers the instants before it.
        let leading = [X.segment(0, "Not/AZone"), X.segment(X.epoch("2030-12-09T18:00:00Z"), X.auckland)]
        XCTAssertEqual(IntakeAggregation.zone(atEpochSeconds: noon, zoneLog: leading).identifier, X.auckland)
        // Aggregation never traps on it.
        XCTAssertEqual(rows(aggregate(X.foodSamples, log: onlyUnknown)), rows(aggregate(X.foodSamples)))
    }

    func testInstantsBeforeTheFirstSegmentUseTheFirstSegment() {
        let log = [X.segment(X.eastwardChange, X.auckland)]
        let before = X.epoch("2030-12-09T13:00:00Z")
        XCTAssertEqual(IntakeAggregation.zone(atEpochSeconds: before, zoneLog: log).identifier, X.auckland)
        XCTAssertEqual(IntakeAggregation.zone(atEpochSeconds: 0, zoneLog: log).identifier, X.auckland)
        XCTAssertEqual(IntakeAggregation.zone(atEpochSeconds: -86_400, zoneLog: log).identifier, X.auckland)
        // 13:00 UTC is 02:00 on the 10th in Auckland; 08:00 UTC is 21:00 on the 9th.
        XCTAssertEqual(dayKey("2030-12-09T13:00:00Z", log), "2030-12-10")
        XCTAssertEqual(dayKey("2030-12-09T08:00:00Z", log), "2030-12-09")
        // With two segments, both starting after the instant, it is the earliest that applies.
        let two = [X.segment(X.eastwardChange, X.auckland), X.segment(X.eastwardChange + 3_600, X.losAngeles)]
        XCTAssertEqual(IntakeAggregation.zone(atEpochSeconds: before, zoneLog: two).identifier, X.auckland)
    }

    func testEastwardChangeMidDayMovesLaterEntriesToTheNextDay() {
        let result = aggregate(X.foodSamples, log: X.logE)
        XCTAssertEqual(rows(result), [row("2030-12-09", 70, 1150, 4), row("2030-12-10", 45, 550, 4)])
        XCTAssertEqual(rejected(result), noRejections)
        // The change instant itself is counted in the new zone; one second earlier in the old one.
        XCTAssertEqual(IntakeAggregation.zone(atEpochSeconds: X.eastwardChange, zoneLog: X.logE).identifier, X.auckland)
        XCTAssertEqual(IntakeAggregation.zone(atEpochSeconds: X.eastwardChange - 1, zoneLog: X.logE).identifier, X.utc)
        XCTAssertEqual(IntakeAggregation.zone(atEpochSeconds: X.eastwardChange + 1, zoneLog: X.logE).identifier, X.auckland)
        XCTAssertEqual(dayKey("2030-12-09T18:00:00Z", X.logE), "2030-12-10")
        XCTAssertEqual(dayKey("2030-12-09T17:59:59Z", X.logE), "2030-12-09")
        let edge = aggregate([X.protein("at", "2030-12-09T18:00:00Z", 7), X.protein("before", "2030-12-09T17:59:59Z", 3)],
                             log: X.logE)
        XCTAssertEqual(rows(edge), [row("2030-12-09", 3, nil, 1), row("2030-12-10", 7, nil, 1)])
    }

    func testWestwardChangeCanPutALaterInstantOnAnEarlierDay() {
        XCTAssertLessThan(X.westX.startEpochSeconds, X.westY.startEpochSeconds)
        XCTAssertEqual(dayKey("2030-12-09T19:00:00Z", X.logW), "2030-12-10")
        XCTAssertEqual(dayKey("2030-12-09T21:00:00Z", X.logW), "2030-12-09")
        let result = aggregate([X.westX, X.westY], log: X.logW)
        XCTAssertEqual(rows(result), [row("2030-12-09", 15, nil, 1), row("2030-12-10", 10, nil, 1)])
        XCTAssertEqual(rejected(result), noRejections)
        // Either side of the change instant: 19:59:59 UTC is still Auckland's 10th, 20:00:00 UTC is noon
        // on Los Angeles's 9th.
        XCTAssertEqual(dayKey("2030-12-09T19:59:59Z", X.logW), "2030-12-10")
        XCTAssertEqual(dayKey("2030-12-09T20:00:00Z", X.logW), "2030-12-09")
    }

    func testEveryInstantMapsToExactlyOneDayAcrossAChange() {
        let base = X.epoch("2030-12-08T00:00:00Z")
        let cases: [(log: [IntakeZoneSegment], change: Int, before: Int, after: Int)] = [
            (X.logE, X.eastwardChange, 0, X.aucklandOffsetSeconds),
            (X.logW, X.westwardChange, X.aucklandOffsetSeconds, X.losAngelesOffsetSeconds),
        ]
        var generator = X.Generator(state: 0x5EED_0302)
        for (index, c) in cases.enumerated() {
            var instants = [c.change - 1, c.change, c.change + 1]
            for _ in 0..<200 { instants.append(base + generator.next(3 * 86_400)) }
            let samples = instants.enumerated().map {
                IntakeSample(id: "i\($0.offset)", nutrient: .protein, startEpochSeconds: $0.element,
                             amount: 1, sourceId: X.foodAppId)
            }
            for t in instants {
                let key = IntakeAggregation.dayKey(epochSeconds: t, zoneLog: c.log)
                XCTAssertEqual(key, X.localDayKey(t, offsetSeconds: t >= c.change ? c.after : c.before),
                               "case \(index), instant \(t)")
                XCTAssertEqual(IntakeAggregation.dayKey(epochSeconds: t, zoneLog: c.log), key, "one key per instant")
            }
            // Over a window wide enough for every instant, each entry is counted once: none twice, none
            // dropped by the change.
            let result = aggregate(samples, log: c.log, first: "2030-12-06", last: "2030-12-13")
            XCTAssertEqual(rejected(result), noRejections, "case \(index)")
            XCTAssertEqual(result.totals.reduce(0) { $0 + $1.sampleCount }, samples.count, "case \(index)")
            XCTAssertEqual(result.totals.reduce(0.0) { $0 + ($1.proteinGrams ?? 0) }, Double(samples.count),
                           "case \(index)")
        }
    }

    func testADayStoredBeforeAChangeKeepsItsTotalAfterIt() {
        let before = aggregate(X.foodSamples, log: X.logU)
        XCTAssertEqual(rows(before), [row("2030-12-09", 95, 1450, 6), row("2030-12-10", 20, 250, 2)])
        // Two days later the phone is seen in Auckland, then in Los Angeles. The same samples are read
        // again: the days already lived keep their keys and their totals.
        for zone in [X.auckland, X.losAngeles] {
            let seenAt = X.epoch("2030-12-12T09:00:00Z")
            let later = IntakeAggregation.appending(zoneIdentifier: zone, at: seenAt, to: X.logU)
            XCTAssertEqual(later, [X.segment(0, X.utc), X.segment(seenAt, zone)])
            let after = aggregate(X.foodSamples, log: later)
            XCTAssertEqual(after, before, "after a change to \(zone)")
            let written = plan(after, storedAfterFirstRead)
            XCTAssertEqual(written.reason, .unchanged)
            XCTAssertEqual(written.changedDays, [])
            XCTAssertEqual(deletions(written), [])
            // An instant after the change is counted in the new zone.
            XCTAssertEqual(IntakeAggregation.zone(atEpochSeconds: seenAt, zoneLog: later).identifier, zone)
        }
    }

    func testDaylightSavingShiftIsExactWithinOneSegment() {
        let log = [X.segment(0, X.losAngeles)]
        // Clocks go back on 2030-11-03: that local day is 25 hours, 07:00 UTC to 08:00 UTC the next day.
        XCTAssertEqual(dayKey("2030-11-03T06:59:59Z", log), "2030-11-02")
        XCTAssertEqual(dayKey("2030-11-03T07:00:00Z", log), "2030-11-03")
        XCTAssertEqual(dayKey("2030-11-04T07:59:59Z", log), "2030-11-03")
        XCTAssertEqual(dayKey("2030-11-04T08:00:00Z", log), "2030-11-04")
        // Clocks go forward on 2030-03-10: that local day is 23 hours, 08:00 UTC to 07:00 UTC the next.
        XCTAssertEqual(dayKey("2030-03-10T07:59:59Z", log), "2030-03-09")
        XCTAssertEqual(dayKey("2030-03-10T08:00:00Z", log), "2030-03-10")
        XCTAssertEqual(dayKey("2030-03-11T06:59:59Z", log), "2030-03-10")
        XCTAssertEqual(dayKey("2030-03-11T07:00:00Z", log), "2030-03-11")
        // The whole 25-hour day is one day's total.
        let samples = [
            X.protein("a", "2030-11-03T07:00:00Z", 10),
            X.protein("b", "2030-11-03T09:30:00Z", 10),    // the repeated hour
            X.protein("c", "2030-11-04T07:59:59Z", 10),
            X.protein("d", "2030-11-04T08:00:00Z", 5),
        ]
        let result = aggregate(samples, log: log, first: "2030-11-03", last: "2030-11-04")
        XCTAssertEqual(rows(result), [row("2030-11-03", 30, nil, 3), row("2030-11-04", 5, nil, 1)])
    }

    func testAppendingToAnEmptyLogStartsItAtZero() {
        // The first segment starts at 0, not at `now`, so every earlier instant has a zone.
        XCTAssertEqual(IntakeAggregation.appending(zoneIdentifier: X.auckland, at: X.eastwardChange, to: []),
                       [X.segment(0, X.auckland)])
        XCTAssertEqual(IntakeAggregation.appending(zoneIdentifier: X.utc, at: 0, to: []), [X.segment(0, X.utc)])
    }

    func testAppendingTheSameZoneReturnsTheLogUnchanged() {
        XCTAssertEqual(IntakeAggregation.appending(zoneIdentifier: X.utc, at: X.eastwardChange, to: X.logU), X.logU)
        XCTAssertEqual(IntakeAggregation.appending(zoneIdentifier: X.auckland, at: X.eastwardChange + 86_400, to: X.logE),
                       X.logE)
        // Unchanged even when the clock moved back: the last segment already names that zone.
        XCTAssertEqual(IntakeAggregation.appending(zoneIdentifier: X.auckland, at: X.eastwardChange - 500, to: X.logE),
                       X.logE)
        // Only the *last* segment is compared: returning to an earlier zone is a new segment.
        XCTAssertEqual(IntakeAggregation.appending(zoneIdentifier: X.utc, at: X.eastwardChange + 60, to: X.logE),
                       X.logE + [X.segment(X.eastwardChange + 60, X.utc)])
    }

    func testAppendingANewZoneAddsASegmentAtNow() {
        let log = IntakeAggregation.appending(zoneIdentifier: X.auckland, at: X.eastwardChange, to: X.logU)
        XCTAssertEqual(log, X.logE)
        // The new zone is in force from `now` itself, and not a second sooner.
        XCTAssertEqual(IntakeAggregation.zone(atEpochSeconds: X.eastwardChange, zoneLog: log).identifier, X.auckland)
        XCTAssertEqual(IntakeAggregation.zone(atEpochSeconds: X.eastwardChange - 1, zoneLog: log).identifier, X.utc)
        XCTAssertEqual(IntakeAggregation.dayKey(epochSeconds: X.eastwardChange, zoneLog: log), "2030-12-10")
        XCTAssertEqual(IntakeAggregation.dayKey(epochSeconds: X.eastwardChange - 1, zoneLog: log), "2030-12-09")
        // The input is not altered and the call is repeatable.
        XCTAssertEqual(IntakeAggregation.appending(zoneIdentifier: X.auckland, at: X.eastwardChange, to: X.logU), log)
    }

    func testAppendingWhenTheClockMovedBackReplacesTheLastSegment() {
        let replaced = [X.segment(0, X.utc), X.segment(X.eastwardChange, X.losAngeles)]
        XCTAssertEqual(IntakeAggregation.appending(zoneIdentifier: X.losAngeles, at: X.eastwardChange - 1, to: X.logE),
                       replaced)
        XCTAssertEqual(IntakeAggregation.appending(zoneIdentifier: X.losAngeles, at: X.eastwardChange - 86_400, to: X.logE),
                       replaced)
        // Exactly at the last segment's start counts as "at or before": replaced, not appended.
        XCTAssertEqual(IntakeAggregation.appending(zoneIdentifier: X.losAngeles, at: X.eastwardChange, to: X.logE),
                       replaced)
        // One second later the clock has moved on: appended.
        XCTAssertEqual(IntakeAggregation.appending(zoneIdentifier: X.losAngeles, at: X.eastwardChange + 1, to: X.logE),
                       X.logE + [X.segment(X.eastwardChange + 1, X.losAngeles)])
        // A one-segment log: its only segment is the last.
        XCTAssertEqual(IntakeAggregation.appending(zoneIdentifier: X.auckland, at: 0, to: X.logU),
                       [X.segment(0, X.auckland)])
        XCTAssertEqual(IntakeAggregation.appending(zoneIdentifier: X.auckland, at: -10, to: X.logU),
                       [X.segment(0, X.auckland)])
    }

    func testTheLogKeepsItsFirstSegmentWhenTrimmedTo32() {
        // Alternate two zones, one change every 1000 seconds.
        func zone(_ i: Int) -> String { i % 2 == 0 ? X.utc : X.auckland }
        func expected(appended range: ClosedRange<Int>) -> [IntakeZoneSegment] {
            [X.segment(0, X.utc)] + range.map { X.segment(1_000 * $0, zone($0)) }
        }
        var log = IntakeAggregation.appending(zoneIdentifier: X.utc, at: 500, to: [])
        XCTAssertEqual(log, [X.segment(0, X.utc)])
        for i in 1...31 { log = IntakeAggregation.appending(zoneIdentifier: zone(i), at: 1_000 * i, to: log) }
        XCTAssertEqual(log.count, 32, "32 segments are kept whole")
        XCTAssertEqual(log, expected(appended: 1...31))
        // The 33rd segment drops the second, never the first.
        log = IntakeAggregation.appending(zoneIdentifier: zone(32), at: 32_000, to: log)
        XCTAssertEqual(log, expected(appended: 2...32))
        for i in 33...40 { log = IntakeAggregation.appending(zoneIdentifier: zone(i), at: 1_000 * i, to: log) }
        XCTAssertEqual(log.count, 32)
        XCTAssertEqual(log, expected(appended: 10...40))
        // Old instants still have a zone: the first segment's.
        XCTAssertEqual(IntakeAggregation.zone(atEpochSeconds: 100, zoneLog: log).identifier, X.utc)
        XCTAssertEqual(IntakeAggregation.zone(atEpochSeconds: 40_000, zoneLog: log).identifier, zone(40))
    }

    // MARK: - Write plan (§7.3)

    func testAFirstReadWritesEveryMeasuredValueAndItsReadTime() {
        let written = plan(aggregate(X.foodSamples), [])
        XCTAssertEqual(upserts(written), [
            "2030-12-09 calories_in 1450.0", "2030-12-09 intake_read_at \(readAtValue)", "2030-12-09 protein_g 95.0",
            "2030-12-10 calories_in 250.0", "2030-12-10 intake_read_at \(readAtValue)", "2030-12-10 protein_g 20.0",
        ])
        XCTAssertEqual(deletions(written), [])
        XCTAssertEqual(written.reason, .changed)
        XCTAssertEqual(written.changedDays, ["2030-12-09", "2030-12-10"])
        XCTAssertEqual(written.upserts.first?.value, 1450)
        XCTAssertEqual(written.upserts.first { $0.key == IntakeAggregation.readAtKey }?.value, Double(readAt))
    }

    func testAWholeEmptyWindowWritesAndDeletesNothing() {
        // An empty window may mean access was declined, the food app was removed, or nothing was logged.
        // None of those is evidence that stored days are wrong, so nothing stored is touched.
        let empty = aggregate([])
        XCTAssertEqual(empty.emptyDays, ["2030-12-09", "2030-12-10"])
        let written = plan(empty, storedAfterFirstRead)
        XCTAssertEqual(upserts(written), [])
        XCTAssertEqual(deletions(written), [])
        XCTAssertEqual(written.reason, .windowEmpty)
        XCTAssertEqual(written.changedDays, [])
        // The same when every sample was rejected, and when nothing is stored either.
        let rejectedOnly = aggregate([X.protein("nan", "2030-12-09T09:00:00Z", .nan), X.s9], admitted: [X.foodAppId])
        let second = plan(rejectedOnly, storedAfterFirstRead)
        XCTAssertEqual(upserts(second), [])
        XCTAssertEqual(deletions(second), [])
        XCTAssertEqual(second.reason, .windowEmpty)
        let third = plan(empty, [])
        XCTAssertEqual(upserts(third), [])
        XCTAssertEqual(deletions(third), [])
        XCTAssertEqual(third.reason, .windowEmpty)
    }

    func testAnEmptyDayInsideANonEmptyWindowDeletesItsStoredRows() {
        let result = aggregate([X.s1, X.s2, X.s3, X.s4, X.s5, X.s6])
        let written = plan(result, storedAfterFirstRead)
        XCTAssertEqual(deletions(written), [
            "2030-12-10 calories_in", "2030-12-10 intake_read_at", "2030-12-10 protein_g",
        ])
        XCTAssertEqual(upserts(written), ["2030-12-09 intake_read_at \(readAtValue)"])
        XCTAssertEqual(written.changedDays, ["2030-12-10"])
        XCTAssertEqual(written.reason, .changed)
        // One total day is enough for the window to be non-empty, wherever in the window it is.
        let onlyLast = plan(aggregate([X.s7]), storedAfterFirstRead)
        XCTAssertTrue(deletions(onlyLast).contains("2030-12-09 protein_g"))
        XCTAssertTrue(deletions(onlyLast).contains("2030-12-09 calories_in"))
        XCTAssertFalse(upserts(onlyLast).contains { $0.hasPrefix("2030-12-09") })
    }

    func testAnEmptyDayWithNothingStoredIsLeftAlone() {
        let result = aggregate([X.s1, X.s2, X.s3, X.s4, X.s5, X.s6])
        let written = plan(result, [stored("2030-12-09", 95, 1450)])
        XCTAssertEqual(deletions(written), [])
        XCTAssertEqual(upserts(written), ["2030-12-09 intake_read_at \(readAtValue)"])
        XCTAssertEqual(written.changedDays, [])
        XCTAssertEqual(written.reason, .unchanged)
        XCTAssertEqual(deletions(plan(result, [])), [])
    }

    func testNoDayIsEverWrittenAsZeroBecauseItIsEmpty() {
        // A four-day window with intake on the two middle days only. Stored rows exist for the empty
        // days in one run and not in the other.
        let result = aggregate(X.foodSamples, first: "2030-12-08", last: "2030-12-11")
        XCTAssertEqual(result.emptyDays, ["2030-12-08", "2030-12-11"])
        let storedSets = [
            [],
            storedAfterFirstRead,
            [stored("2030-12-08", 80, 2000), stored("2030-12-11", 0, 0)] + storedAfterFirstRead,
        ]
        for (index, storedDays) in storedSets.enumerated() {
            let written = plan(result, storedDays)
            for point in written.upserts {
                XCTAssertFalse(result.emptyDays.contains(point.day),
                               "set \(index): an empty day is deleted or left alone, never upserted (\(point.day) \(point.key))")
                if point.key != IntakeAggregation.readAtKey {
                    XCTAssertNotEqual(point.value, 0, "set \(index): nothing in this window measured zero")
                }
            }
        }
        // A day with one nutrient unmeasured gets no value for that nutrient, zero or otherwise.
        let energyOnly = plan(aggregate([X.s2]), [])
        XCTAssertEqual(upserts(energyOnly), ["2030-12-09 calories_in 450.0", "2030-12-09 intake_read_at \(readAtValue)"])
        XCTAssertFalse(energyOnly.upserts.contains { $0.key == IntakeAggregation.proteinKey })
    }

    func testAnUnchangedTotalStillAdvancesItsReadTime() {
        let written = plan(aggregate(X.foodSamples), storedAfterFirstRead)
        XCTAssertEqual(upserts(written), [
            "2030-12-09 intake_read_at \(readAtValue)", "2030-12-10 intake_read_at \(readAtValue)",
        ])
        XCTAssertEqual(deletions(written), [])
        XCTAssertEqual(written.reason, .unchanged)
        XCTAssertEqual(written.changedDays, [])
        // Also when the stored read time already equals this one: freshness is always restated.
        let sameTime = [stored("2030-12-09", 95, 1450, readAt: readAt), stored("2030-12-10", 20, 250, readAt: readAt)]
        XCTAssertEqual(upserts(plan(aggregate(X.foodSamples), sameTime)).count, 2)
    }

    func testATotalWithinToleranceIsNotRewritten() {
        // Stored zero against tiny measured amounts, so the difference is exact in binary.
        func written(_ grams: Double) -> IntakeWritePlan {
            plan(aggregate([X.protein("p", "2030-12-09T09:00:00Z", grams)]), [stored("2030-12-09", 0, nil)])
        }
        let at = written(1e-9)
        XCTAssertEqual(upserts(at), ["2030-12-09 intake_read_at \(readAtValue)"], "a difference of exactly 1e-9 is within tolerance")
        XCTAssertEqual(at.reason, .unchanged)
        XCTAssertEqual(at.changedDays, [])
        let under = written((1e-9).nextDown)
        XCTAssertEqual(upserts(under), ["2030-12-09 intake_read_at \(readAtValue)"])
        let over = written((1e-9).nextUp)
        XCTAssertEqual(upserts(over), [
            "2030-12-09 intake_read_at \(readAtValue)", "2030-12-09 protein_g \((1e-9).nextUp)",
        ])
        XCTAssertEqual(over.reason, .changed)
        XCTAssertEqual(over.changedDays, ["2030-12-09"])
        // The tolerance is symmetric, and applies to energy as to protein.
        let lower = plan(aggregate([X.energy("e", "2030-12-09T09:00:00Z", 0)]), [stored("2030-12-09", nil, 1e-9)])
        XCTAssertEqual(upserts(lower), ["2030-12-09 intake_read_at \(readAtValue)"])
        let lowerOver = plan(aggregate([X.energy("e", "2030-12-09T09:00:00Z", 0)]), [stored("2030-12-09", nil, (1e-9).nextUp)])
        XCTAssertEqual(upserts(lowerOver), ["2030-12-09 calories_in 0.0", "2030-12-09 intake_read_at \(readAtValue)"])
        // Ordinary sizes: a millionth of a gram is a change, a trillionth is not.
        let coarse = plan(aggregate(X.foodSamples), [stored("2030-12-09", 95.000001, 1450), stored("2030-12-10", 20, 250.000000000001)])
        XCTAssertEqual(coarse.changedDays, ["2030-12-09"])
        XCTAssertTrue(upserts(coarse).contains("2030-12-09 protein_g 95.0"))
        XCTAssertFalse(coarse.upserts.contains { $0.day == "2030-12-10" && $0.key != IntakeAggregation.readAtKey })
    }

    func testAStoredNilIsNeverWithinToleranceOfAMeasuredValue() {
        // Stored "not measured" against a measured zero: a value appears, so it is written.
        let written = plan(aggregate([X.protein("z", "2030-12-09T09:00:00Z", 0)]), [stored("2030-12-09", nil, nil)])
        XCTAssertEqual(upserts(written), ["2030-12-09 intake_read_at \(readAtValue)", "2030-12-09 protein_g 0.0"])
        XCTAssertEqual(written.changedDays, ["2030-12-09"])
        XCTAssertEqual(written.reason, .changed)
    }

    func testProteinDisappearingFromADayDeletesOnlyTheProteinRow() {
        let result = aggregate([X.s2, X.s4, X.s6, X.s7, X.s8])
        XCTAssertEqual(rows(result), [row("2030-12-09", nil, 1450, 3), row("2030-12-10", 20, 250, 2)])
        let written = plan(result, storedAfterFirstRead)
        XCTAssertEqual(deletions(written), ["2030-12-09 protein_g"])
        XCTAssertEqual(upserts(written), [
            "2030-12-09 intake_read_at \(readAtValue)", "2030-12-10 intake_read_at \(readAtValue)",
        ])
        XCTAssertEqual(written.changedDays, ["2030-12-09"])
        XCTAssertEqual(written.reason, .changed)
        // The mirror case: energy disappears, protein stays.
        let proteinOnly = plan(aggregate([X.s1, X.s3, X.s5, X.s7, X.s8]), storedAfterFirstRead)
        XCTAssertEqual(deletions(proteinOnly), ["2030-12-09 calories_in"])
        // Nothing stored for the missing nutrient: nothing to delete.
        let neverStored = plan(result, [stored("2030-12-09", nil, 1450), stored("2030-12-10", 20, 250)])
        XCTAssertEqual(deletions(neverStored), [])
        XCTAssertEqual(neverStored.reason, .unchanged)
    }

    func testChangedDaysListsOnlyDaysWhoseValuesMoved() {
        let result = aggregate(X.foodSamples, first: "2030-12-08", last: "2030-12-11")
        // 8th: stored, now empty (moved). 9th: protein differs (moved). 10th: equal. 11th: never stored.
        let storedDays = [stored("2030-12-08", 50, 900), stored("2030-12-09", 90, 1450), stored("2030-12-10", 20, 250)]
        let written = plan(result, storedDays)
        XCTAssertEqual(written.changedDays, ["2030-12-08", "2030-12-09"])
        XCTAssertEqual(written.reason, .changed)
        XCTAssertEqual(upserts(written), [
            "2030-12-09 intake_read_at \(readAtValue)", "2030-12-09 protein_g 95.0",
            "2030-12-10 intake_read_at \(readAtValue)",
        ])
        XCTAssertEqual(deletions(written), [
            "2030-12-08 calories_in", "2030-12-08 intake_read_at", "2030-12-08 protein_g",
        ])
        // A read time alone advancing is not a changed day.
        XCTAssertFalse(written.changedDays.contains("2030-12-10"))
        // Energy alone moving is a changed day.
        let energyMoved = plan(aggregate(X.foodSamples), [stored("2030-12-09", 95, 1400), stored("2030-12-10", 20, 250)])
        XCTAssertEqual(energyMoved.changedDays, ["2030-12-09"])
    }

    func testDaysOutsideTheWindowAreNeverPlanned() {
        let outside = [
            stored("2030-12-01", 110, 2500), stored("2030-12-08", 60, 1800),
            stored("2030-12-11", 75, 1900), stored("2031-01-08", 120, 2450),
        ]
        let inWindow: Set<String> = ["2030-12-09", "2030-12-10"]
        let results = [
            aggregate(X.foodSamples),
            aggregate([X.s1, X.s2]),                                              // the 10th is empty
            aggregate(X.foodSamples + [X.protein("far", "2030-12-01T12:00:00Z", 30)]),   // an outside sample
            aggregate([]),
        ]
        for (index, result) in results.enumerated() {
            let written = plan(result, outside + storedAfterFirstRead)
            XCTAssertTrue(written.upserts.allSatisfy { inWindow.contains($0.day) }, "result \(index)")
            XCTAssertTrue(written.deletions.allSatisfy { inWindow.contains($0.day) }, "result \(index)")
            XCTAssertTrue(written.changedDays.allSatisfy { inWindow.contains($0) }, "result \(index)")
        }
    }

    func testPlanIsSortedAndStable() {
        let result = aggregate(X.foodSamples, first: "2030-12-07", last: "2030-12-12")
        let storedDays = [
            stored("2030-12-07", 40, 800), stored("2030-12-08", 50, 900), stored("2030-12-09", 90, 1400),
            stored("2030-12-10", 21, 251), stored("2030-12-11", 60, 1000), stored("2030-12-12", 70, 1100),
        ]
        let reference = plan(result, storedDays)
        XCTAssertEqual(upserts(reference), [
            "2030-12-09 calories_in 1450.0", "2030-12-09 intake_read_at \(readAtValue)", "2030-12-09 protein_g 95.0",
            "2030-12-10 calories_in 250.0", "2030-12-10 intake_read_at \(readAtValue)", "2030-12-10 protein_g 20.0",
        ])
        XCTAssertEqual(deletions(reference), [
            "2030-12-07 calories_in", "2030-12-07 intake_read_at", "2030-12-07 protein_g",
            "2030-12-08 calories_in", "2030-12-08 intake_read_at", "2030-12-08 protein_g",
            "2030-12-11 calories_in", "2030-12-11 intake_read_at", "2030-12-11 protein_g",
            "2030-12-12 calories_in", "2030-12-12 intake_read_at", "2030-12-12 protein_g",
        ])
        XCTAssertEqual(reference.changedDays, ["2030-12-07", "2030-12-08", "2030-12-09", "2030-12-10", "2030-12-11", "2030-12-12"])
        // The order of the stored rows, and of the samples behind the result, does not move the plan.
        var generator = X.Generator(state: 0x5EED_0303)
        for _ in 0..<25 {
            let shuffledResult = aggregate(generator.shuffled(X.foodSamples), first: "2030-12-07", last: "2030-12-12")
            XCTAssertEqual(plan(shuffledResult, generator.shuffled(storedDays)), reference)
        }
        XCTAssertEqual(plan(result, Array(storedDays.reversed())), reference)
    }

    func testAPartlyStoredEmptyDayHasItsStoredValuesDeletedAndNothingWritten() {
        // SPEC-AMBIGUITY: §7.3 step 3 says an empty day with a stored row has "its `protein_g`,
        // `calories_in` and `intake_read_at`" deleted. Whether a key the row never held is listed as a
        // deletion is not stated; deleting an absent row is harmless either way. This test asserts only
        // what both readings share: every stored value is deleted and nothing is upserted for the day.
        let result = aggregate([X.s1, X.s2])
        let written = plan(result, [stored("2030-12-09", 30, 450), stored("2030-12-10", 20, nil)])
        XCTAssertTrue(deletions(written).contains("2030-12-10 protein_g"))
        XCTAssertTrue(deletions(written).contains("2030-12-10 intake_read_at"))
        XCTAssertFalse(written.upserts.contains { $0.day == "2030-12-10" })
        XCTAssertTrue(written.deletions.allSatisfy { $0.day == "2030-12-10" })
        XCTAssertEqual(written.changedDays, ["2030-12-10"])
    }
}
