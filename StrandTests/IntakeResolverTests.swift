// API ASSUMED BY THESE TESTS
//
// Stage 3 specification §9.4 and §12.3 (`IntakeResolverTests.swift`). Written before the
// implementation exists. New, in Strand/Data/IntakeResolver.swift, exactly as §9.4 gives it:
//
//     enum IntakeSource: String { case appleHealth, quickAdd, nutritionCsv }
//     enum IntakeSourceSetting: String { case none, appleHealth, quickAdd }
//     enum IntakePolicy: Equatable { case legacy, unified(active: IntakeSourceSetting) }
//     struct ResolvedIntakeValue: Equatable { let value: Double; let source: IntakeSource; let readAtEpochSeconds: Int? }
//     struct ResolvedIntakeDay: Equatable { let day: String; let protein: ResolvedIntakeValue?; let energy: ResolvedIntakeValue? }
//     struct IntakeCandidates { var appleHealth: [IntakeStoredDay]; var quickAdd: [IntakeStoredDay];
//                               var nutritionCsv: [IntakeStoredDay] }   (memberwise initialiser)
//     enum IntakeResolver {
//         static func policy(flagEnabled: Bool, sourceSetting: IntakeSourceSetting) -> IntakePolicy
//         static func order(_ policy: IntakePolicy) -> [IntakeSource]
//         static func series(candidates: IntakeCandidates, policy: IntakePolicy) -> [ResolvedIntakeDay]
//         static func resolve(day: String, candidates: IntakeCandidates, policy: IntakePolicy) -> ResolvedIntakeDay?
//     }
//
// `ResolvedIntakeValue` and `ResolvedIntakeDay` are built with their memberwise initialisers.
// `IntakeStoredDay` is the package type (already in the tree).
//
// Behaviour assumed where §9.4 leaves it open: a resolved value carries the read time stored with
// the source it came from (the `readAtEpochSeconds` of that source's `IntakeStoredDay`), and a CSV
// value carries none.
//
// Synthetic values only.

import XCTest
import StrandAnalytics
@testable import Strand

final class IntakeResolverTests: XCTestCase {
    private typealias Day = IntakeStoredDay

    private func day(_ key: String, _ protein: Double?, _ energy: Double? = nil, readAt: Int? = nil) -> Day {
        Day(day: key, proteinGrams: protein, energyKcal: energy, readAtEpochSeconds: readAt)
    }

    /// The §13.6 three-source day, with read times on the two sources that have them.
    private let threeSources = IntakeCandidates(
        appleHealth: [IntakeStoredDay(day: "2031-01-28", proteinGrams: 120, energyKcal: 2_400, readAtEpochSeconds: 1_927_700_000)],
        quickAdd: [IntakeStoredDay(day: "2031-01-28", proteinGrams: 80, energyKcal: 1_900, readAtEpochSeconds: 1_927_600_000)],
        nutritionCsv: [IntakeStoredDay(day: "2031-01-28", proteinGrams: 60, energyKcal: 2_100, readAtEpochSeconds: nil)])

    private let allSettings: [IntakeSourceSetting] = [.none, .appleHealth, .quickAdd]

    func testPolicyIsLegacyWheneverTheFlagIsOff() {
        for setting in allSettings {
            XCTAssertEqual(IntakeResolver.policy(flagEnabled: false, sourceSetting: setting), .legacy, "\(setting)")
            XCTAssertEqual(IntakeResolver.policy(flagEnabled: true, sourceSetting: setting), .unified(active: setting))
        }
    }

    func testLegacyPolicyReadsOnlyTheCsvSeries() {
        XCTAssertEqual(IntakeResolver.order(.legacy), [.nutritionCsv])
        let resolved = IntakeResolver.series(candidates: threeSources, policy: .legacy)
        XCTAssertEqual(resolved, [ResolvedIntakeDay(
            day: "2031-01-28",
            protein: ResolvedIntakeValue(value: 60, source: .nutritionCsv, readAtEpochSeconds: nil),
            energy: ResolvedIntakeValue(value: 2_100, source: .nutritionCsv, readAtEpochSeconds: nil))])

        // A day that only Health or quick-add holds does not exist under the legacy policy.
        let noCsv = IntakeCandidates(appleHealth: [day("2031-01-27", 120, readAt: 1)], quickAdd: [day("2031-01-26", 90, readAt: 2)],
                                     nutritionCsv: [])
        XCTAssertEqual(IntakeResolver.series(candidates: noCsv, policy: .legacy), [])
        XCTAssertNil(IntakeResolver.resolve(day: "2031-01-27", candidates: noCsv, policy: .legacy))

        // Value for value what the builder passed before this stage: the CSV series.
        let csv = [day("2031-01-20", 110), day("2031-01-21", 0), day("2031-01-23", 95.5)]
        let onlyCsv = IntakeCandidates(appleHealth: [], quickAdd: [], nutritionCsv: csv)
        XCTAssertEqual(IntakeResolver.series(candidates: onlyCsv, policy: .legacy).map { $0.protein?.value },
                       [110, 0, 95.5])
    }

    func testUnifiedOrderForEachSourceSetting() {
        XCTAssertEqual(IntakeResolver.order(.unified(active: .appleHealth)), [.appleHealth, .quickAdd, .nutritionCsv])
        XCTAssertEqual(IntakeResolver.order(.unified(active: .quickAdd)), [.quickAdd, .appleHealth, .nutritionCsv])
        XCTAssertEqual(IntakeResolver.order(.unified(active: .none)), [.appleHealth, .quickAdd, .nutritionCsv])

        let expected: [IntakeSourceSetting: (Double, IntakeSource, Int?)] = [
            .appleHealth: (120, .appleHealth, 1_927_700_000),
            .quickAdd: (80, .quickAdd, 1_927_600_000),
            .none: (120, .appleHealth, 1_927_700_000),
        ]
        for setting in allSettings {
            let resolved = IntakeResolver.resolve(day: "2031-01-28", candidates: threeSources,
                                                  policy: .unified(active: setting))
            let want = expected[setting]!
            XCTAssertEqual(resolved?.protein, ResolvedIntakeValue(value: want.0, source: want.1, readAtEpochSeconds: want.2),
                           "\(setting)")
        }
    }

    func testSourcesAreNeverSummed() {
        for policy in [IntakePolicy.legacy] + allSettings.map({ IntakePolicy.unified(active: $0) }) {
            let resolved = IntakeResolver.series(candidates: threeSources, policy: policy)
            XCTAssertEqual(resolved.count, 1)
            let protein = resolved.first?.protein?.value
            XCTAssertTrue([120, 80, 60].contains(protein ?? -1), "one source's value, never a sum: \(String(describing: protein))")
            let energy = resolved.first?.energy?.value
            XCTAssertTrue([2_400, 1_900, 2_100].contains(energy ?? -1), "\(String(describing: energy))")
        }
    }

    func testProteinAndEnergyResolveIndependently() {
        // Health holds energy only; quick-add holds protein only; the CSV holds both.
        let candidates = IntakeCandidates(appleHealth: [day("2031-01-28", nil, 2_300, readAt: 10)],
                                          quickAdd: [day("2031-01-28", 95, nil, readAt: 20)],
                                          nutritionCsv: [day("2031-01-28", 60, 2_100)])
        let health = IntakeResolver.resolve(day: "2031-01-28", candidates: candidates, policy: .unified(active: .appleHealth))
        XCTAssertEqual(health?.protein, ResolvedIntakeValue(value: 95, source: .quickAdd, readAtEpochSeconds: 20))
        XCTAssertEqual(health?.energy, ResolvedIntakeValue(value: 2_300, source: .appleHealth, readAtEpochSeconds: 10))

        let onlyCsvEnergy = IntakeCandidates(appleHealth: [], quickAdd: [day("2031-01-28", 95, nil, readAt: 20)],
                                             nutritionCsv: [day("2031-01-28", nil, 2_100)])
        let quick = IntakeResolver.resolve(day: "2031-01-28", candidates: onlyCsvEnergy, policy: .unified(active: .quickAdd))
        XCTAssertEqual(quick?.protein?.source, .quickAdd)
        XCTAssertEqual(quick?.energy, ResolvedIntakeValue(value: 2_100, source: .nutritionCsv, readAtEpochSeconds: nil))
    }

    func testOlderSourcesFillDaysTheActiveSourceLacks() {
        // Quick-add history before a move to Apple Health, and CSV history before either.
        let candidates = IntakeCandidates(
            appleHealth: [day("2031-01-27", 120, readAt: 3), day("2031-01-28", 105, readAt: 4)],
            quickAdd: [day("2031-01-24", 90, readAt: 1), day("2031-01-27", 70, readAt: 2)],
            nutritionCsv: [day("2031-01-20", 60), day("2031-01-24", 50)])
        let series = IntakeResolver.series(candidates: candidates, policy: .unified(active: .appleHealth))
        XCTAssertEqual(series.map(\.day), ["2031-01-20", "2031-01-24", "2031-01-27", "2031-01-28"], "ascending, one per day")
        XCTAssertEqual(series.map { $0.protein?.value }, [60, 90, 120, 105])
        XCTAssertEqual(series.map { $0.protein?.source }, [.nutritionCsv, .quickAdd, .appleHealth, .appleHealth])
        for resolved in series {
            XCTAssertEqual(IntakeResolver.resolve(day: resolved.day, candidates: candidates,
                                                  policy: .unified(active: .appleHealth)), resolved,
                           "resolve is the series entry for the day")
        }
        XCTAssertNil(IntakeResolver.resolve(day: "2031-01-25", candidates: candidates, policy: .unified(active: .appleHealth)))
    }

    func testANonFiniteOrNegativeStoredValueIsSkipped() {
        for bad in [-1.0, -0.001, .nan, .infinity, -.infinity] {
            let candidates = IntakeCandidates(appleHealth: [day("2031-01-28", bad, bad, readAt: 5)],
                                              quickAdd: [day("2031-01-28", 80, 1_900, readAt: 6)],
                                              nutritionCsv: [])
            let resolved = IntakeResolver.resolve(day: "2031-01-28", candidates: candidates,
                                                  policy: .unified(active: .appleHealth))
            XCTAssertEqual(resolved?.protein, ResolvedIntakeValue(value: 80, source: .quickAdd, readAtEpochSeconds: 6), "\(bad)")
            XCTAssertEqual(resolved?.energy?.value, 1_900, "\(bad)")
        }
        // A day whose only values are unusable is absent, not zero.
        let onlyBad = IntakeCandidates(appleHealth: [day("2031-01-28", .nan, -3, readAt: 5)], quickAdd: [], nutritionCsv: [])
        XCTAssertEqual(IntakeResolver.series(candidates: onlyBad, policy: .unified(active: .appleHealth)), [])
        // Zero is a value.
        let zero = IntakeCandidates(appleHealth: [day("2031-01-28", 0, readAt: 5)], quickAdd: [day("2031-01-28", 80, readAt: 6)],
                                    nutritionCsv: [])
        XCTAssertEqual(IntakeResolver.resolve(day: "2031-01-28", candidates: zero, policy: .unified(active: .appleHealth))?
            .protein?.value, 0)
    }

    func testResolutionDoesNotDependOnCandidateOrder() {
        let a = IntakeCandidates(appleHealth: [day("2031-01-28", 105, readAt: 4), day("2031-01-27", 120, readAt: 3)],
                                 quickAdd: [day("2031-01-27", 70, readAt: 2), day("2031-01-24", 90, readAt: 1)],
                                 nutritionCsv: [day("2031-01-24", 50), day("2031-01-20", 60)])
        let b = IntakeCandidates(appleHealth: a.appleHealth.reversed(), quickAdd: a.quickAdd.reversed(),
                                 nutritionCsv: a.nutritionCsv.reversed())
        for policy in [IntakePolicy.legacy] + allSettings.map({ IntakePolicy.unified(active: $0) }) {
            XCTAssertEqual(IntakeResolver.series(candidates: a, policy: policy),
                           IntakeResolver.series(candidates: b, policy: policy), "\(policy)")
        }
    }
}
