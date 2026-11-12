import XCTest
import WhoopStore
@testable import Strand

// Stage 1 (weigh-in and scorecard), specification §8.1 to §8.3, §12.3, §12.5 and fault lines F24, F25.
// Written before the implementation exists, from the specification.
//
// API ASSUMED BY THESE TESTS
//
// `Strand/Data/BodyMeasurementResolver.swift`, exactly as specification §8.1 declares it, every type
// internal with its memberwise initialiser in declaration order:
//
//     enum BodyMeasurementKind { case weight, waist }
//     enum BodyMeasurementSource: String { case labBook, appleHealth, profile, profileDefault }
//     enum BodyMeasurementConsumer { case display, estimate }
//     enum BodyMeasurementPolicy { case unified, legacyDisplay, legacyEstimate }
//     struct DatedBodyMeasurement: Equatable {
//         let day: String; let takenAt: Int?; let value: Double
//         let source: BodyMeasurementSource; let rowId: String?
//     }
//     struct ResolvedBodyMeasurement: Equatable {
//         let kind: BodyMeasurementKind; let value: Double
//         let source: BodyMeasurementSource; let day: String?
//     }
//     struct BodyMeasurementCandidates {
//         var labBook: [LabMarkerRow]; var appleHealth: [(day: String, value: Double)]
//         var profileValue: Double; var profileIsSet: Bool
//     }
//     enum BodyMeasurementResolver {
//         static func policy(flagEnabled: Bool, consumer: BodyMeasurementConsumer) -> BodyMeasurementPolicy
//         static func series(_ kind: BodyMeasurementKind, candidates: BodyMeasurementCandidates,
//                            policy: BodyMeasurementPolicy) -> [DatedBodyMeasurement]
//         static func resolve(_ kind: BodyMeasurementKind, asOf day: String,
//                             candidates: BodyMeasurementCandidates,
//                             policy: BodyMeasurementPolicy) -> ResolvedBodyMeasurement?
//     }
//
// Readings of §8.1 and §8.2 that the specification leaves unstated, as these tests take them:
//
//  1. `series` holds ONE element per day, ascending by day. A Lab Book element carries the row's
//     `takenAt` and `id` (as `rowId`) and source `.labBook`; an Apple Health element carries nil for
//     both and source `.appleHealth`. The element's `day` is the row's stored `day`, never a day
//     recomputed from `takenAt`.
//  2. `series` under `.legacyDisplay` is the Apple Health values only; under `.legacyEstimate` it is empty.
//  3. A weight row is admitted in `kg`, `lb` or `lbs` only, a waist row in `cm` or `in` only. A
//     weight row in `cm` is "any other unit" for a weight and is ignored, and the reverse.
//  4. `profileDefault` is reported under every policy when `profileIsSet` is false, and a waist of 0
//     resolves to nil under every policy.
//  5. Under `.unified` an Apple Health value that is not finite or not positive is ignored, as a Lab
//     Book row with such a value is. (Not stated for Apple Health; without it a NaN could reach the
//     calorie estimates.) The legacy policies pass Apple Health values through as the app does today.
//
// The two "never a candidate" tests at the end go through `BodyMeasurementProvider`, because the
// excluded stores have no slot in `BodyMeasurementCandidates` to be excluded from. They assume:
//
//     @MainActor final class BodyMeasurementProvider: ObservableObject {
//         init(repository: Repository, defaults: UserDefaults = .standard,
//              today: @escaping () -> String = { Repository.localDayKey(Date()) })
//         func refresh() async
//         func candidates(_ kind: BodyMeasurementKind) -> BodyMeasurementCandidates
//         func series(_ kind: BodyMeasurementKind, consumer: BodyMeasurementConsumer) -> [DatedBodyMeasurement]
//         func current(_ kind: BodyMeasurementKind, consumer: BodyMeasurementConsumer) -> ResolvedBodyMeasurement?
//         func resolve(_ kind: BodyMeasurementKind, asOf day: String,
//                      consumer: BodyMeasurementConsumer) -> ResolvedBodyMeasurement?
//     }
//
// (the full statement of the provider's assumed behaviour is at the top of
// `BodyMeasurementSingleSourceTests.swift`).
//
// Synthetic values only: the "Fixture Person" of specification §13.
final class BodyMeasurementResolverTests: XCTestCase {

    // MARK: - Builders

    private let d1 = "2031-01-08", d2 = "2031-01-15", d3 = "2031-01-22", d4 = "2031-01-29"

    /// 07:00 UTC on `day`, plus `plus` seconds.
    private func epoch(_ day: String, plus: Int = 0) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = day.split(separator: "-").compactMap { Int($0) }
        let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 7))!
        return Int(date.timeIntervalSince1970) + plus
    }

    private func lab(_ key: String = "weight", id: String, day: String, plus: Int = 0, value: Double?,
                     unit: String? = nil, source: String = "manual",
                     deviceId: String = "my-whoop") -> LabMarkerRow {
        LabMarkerRow(id: id, deviceId: deviceId, markerKey: key, category: "bodyMeasurement", day: day,
                     takenAt: epoch(day, plus: plus), value: value, valueText: nil,
                     unit: unit ?? (key == "weight" ? "kg" : "cm"), source: source, note: nil,
                     referenceText: nil)
    }

    private func candidates(lab: [LabMarkerRow] = [], apple: [(day: String, value: Double)] = [],
                            profile: Double = 80.0, isSet: Bool = true) -> BodyMeasurementCandidates {
        BodyMeasurementCandidates(labBook: lab, appleHealth: apple, profileValue: profile, profileIsSet: isSet)
    }

    private func resolveWeight(_ c: BodyMeasurementCandidates, asOf day: String = "2031-06-30",
                               policy: BodyMeasurementPolicy = .unified) -> ResolvedBodyMeasurement? {
        BodyMeasurementResolver.resolve(.weight, asOf: day, candidates: c, policy: policy)
    }

    private func resolveWaist(_ c: BodyMeasurementCandidates, asOf day: String = "2031-06-30",
                              policy: BodyMeasurementPolicy = .unified) -> ResolvedBodyMeasurement? {
        BodyMeasurementResolver.resolve(.waist, asOf: day, candidates: c, policy: policy)
    }

    private let allPolicies: [BodyMeasurementPolicy] = [.unified, .legacyDisplay, .legacyEstimate]

    // MARK: - §8.2 precedence (the unified policy)

    /// Rule 1: among dated readings the newest DAY wins, whichever source it came from. Asserted in
    /// both directions so neither "Lab Book first" nor "Apple Health first" can satisfy it.
    func testNewestDayWinsAcrossSources() {
        let appleNewer = candidates(lab: [lab(id: "weight-a", day: d1, value: 100.0)],
                                    apple: [(day: d2, value: 99.0)])
        XCTAssertEqual(resolveWeight(appleNewer),
                       ResolvedBodyMeasurement(kind: .weight, value: 99.0, source: .appleHealth, day: d2),
                       "a months-old manual reading must not hide a newer Apple Health one")

        let labNewer = candidates(lab: [lab(id: "weight-a", day: d3, value: 98.4)],
                                  apple: [(day: d2, value: 99.0)])
        XCTAssertEqual(resolveWeight(labNewer),
                       ResolvedBodyMeasurement(kind: .weight, value: 98.4, source: .labBook, day: d3))
    }

    /// Rule 2, and fault line F24: on the same day Lab Book beats Apple Health.
    func testLabBookWinsTheSameDay() {
        let c = candidates(lab: [lab(id: "weight-a", day: d2, value: 99.2)],
                           apple: [(day: d2, value: 99.9)])
        XCTAssertEqual(resolveWeight(c),
                       ResolvedBodyMeasurement(kind: .weight, value: 99.2, source: .labBook, day: d2))

        let series = BodyMeasurementResolver.series(.weight, candidates: c, policy: .unified)
        XCTAssertEqual(series.count, 1, "one element per day: the Apple Health value of that day is not a second point")
        XCTAssertEqual(series.first?.source, .labBook)
        XCTAssertEqual(series.first?.value, 99.2)
    }

    /// Rule 2: within Lab Book on one day the greatest `takenAt` wins, in either input order.
    func testLatestTakenAtWinsWithinADay() {
        let morning = lab(id: "weight-z-morning", day: d2, plus: 0, value: 99.6)
        let evening = lab(id: "weight-a-evening", day: d2, plus: 3600, value: 99.2)
        for rows in [[morning, evening], [evening, morning]] {
            let resolved = resolveWeight(candidates(lab: rows))
            XCTAssertEqual(resolved?.value, 99.2, "the later instant wins, even with the lesser id")
            let series = BodyMeasurementResolver.series(.weight, candidates: candidates(lab: rows), policy: .unified)
            XCTAssertEqual(series.map(\.rowId), ["weight-a-evening"])
        }
    }

    /// Rule 2: with equal `takenAt` (possible across sources, since the natural key includes the
    /// source) the greatest `id` wins, in either input order.
    func testGreatestIdBreaksATieOnTakenAt() {
        let manual = lab(id: "weight-1-AAAAAAAA", day: d2, value: 99.2, source: "manual")
        let imported = lab(id: "weight-1-BBBBBBBB", day: d2, value: 99.8, source: "csv")
        for rows in [[manual, imported], [imported, manual]] {
            let series = BodyMeasurementResolver.series(.weight, candidates: candidates(lab: rows), policy: .unified)
            XCTAssertEqual(series.map(\.rowId), ["weight-1-BBBBBBBB"])
            XCTAssertEqual(resolveWeight(candidates(lab: rows))?.value, 99.8)
        }
    }

    /// Rule 3: the profile value is the fallback and nothing more. It is undated.
    func testProfileIsUsedOnlyWithoutADatedReading() {
        XCTAssertEqual(resolveWeight(candidates(profile: 82.5)),
                       ResolvedBodyMeasurement(kind: .weight, value: 82.5, source: .profile, day: nil))
        XCTAssertEqual(resolveWaist(candidates(profile: 91.0)),
                       ResolvedBodyMeasurement(kind: .waist, value: 91.0, source: .profile, day: nil))

        // One dated reading anywhere at or before the as-of day replaces it, however old.
        let dated = candidates(lab: [lab(id: "weight-a", day: "2029-06-06", value: 104.0)], profile: 82.5)
        XCTAssertEqual(resolveWeight(dated)?.value, 104.0)
        XCTAssertEqual(resolveWeight(dated)?.source, .labBook)
        let datedApple = candidates(apple: [(day: "2029-06-06", value: 103.0)], profile: 82.5)
        XCTAssertEqual(resolveWeight(datedApple)?.source, .appleHealth)
    }

    /// Rule 3: a profile weight that was never written is the default of 75 and is marked as such, so
    /// no screen can present it as the owner's weight.
    func testUnsetProfileWeightIsMarkedAsDefault() {
        let c = candidates(profile: 75.0, isSet: false)
        XCTAssertEqual(resolveWeight(c),
                       ResolvedBodyMeasurement(kind: .weight, value: 75.0, source: .profileDefault, day: nil))
        // A written 75 is the owner's value, not the default.
        XCTAssertEqual(resolveWeight(candidates(profile: 75.0, isSet: true))?.source, .profile)
    }

    /// Rule 3: a waist of 0 is "not set". It resolves to nil, never to a zero measurement.
    func testUnsetWaistResolvesToNil() {
        XCTAssertNil(resolveWaist(candidates(profile: 0, isSet: false)))
        XCTAssertNil(resolveWaist(candidates(profile: 0, isSet: true)),
                     "a stored 0 is the Settings stepper's 'not set', not a waist of zero")
        for policy in allPolicies {
            XCTAssertNil(resolveWaist(candidates(profile: 0, isSet: true), policy: policy), "\(policy)")
        }
        // A weight is never nil: it always has the profile value or its default.
        XCTAssertNotNil(resolveWeight(candidates(profile: 75.0, isSet: false)))
    }

    /// The as-of day is inclusive, and a later reading does not exist yet as far as that day goes.
    func testAsOfDayExcludesLaterReadings() {
        let c = candidates(lab: [lab(id: "weight-1", day: d1, value: 100.0),
                                 lab(id: "weight-3", day: d3, value: 98.4)],
                           apple: [(day: d2, value: 99.2), (day: d4, value: 97.6)],
                           profile: 82.5)
        XCTAssertEqual(resolveWeight(c, asOf: "2031-01-07"),
                       ResolvedBodyMeasurement(kind: .weight, value: 82.5, source: .profile, day: nil),
                       "before the first dated reading only the profile exists")
        XCTAssertEqual(resolveWeight(c, asOf: d1)?.value, 100.0, "a reading on the as-of day counts")
        XCTAssertEqual(resolveWeight(c, asOf: "2031-01-14")?.value, 100.0)
        XCTAssertEqual(resolveWeight(c, asOf: d2)?.value, 99.2)
        XCTAssertEqual(resolveWeight(c, asOf: "2031-01-28")?.value, 98.4)
        XCTAssertEqual(resolveWeight(c, asOf: d4)?.value, 97.6)
        XCTAssertEqual(resolveWeight(c, asOf: "2031-12-31")?.value, 97.6)
    }

    // MARK: - §8.2 unit normalisation

    func testPoundsRowIsConvertedToKilograms() throws {
        let expected = 220.462 / UnitFormatter.poundsPerKilogram
        for unit in ["lb", "lbs", "LB", "Lbs", " lb ", "\tLBS\n"] {
            let c = candidates(lab: [lab(id: "weight-a", day: d1, value: 220.462, unit: unit)])
            let resolved = try XCTUnwrap(resolveWeight(c), "unit \(unit.debugDescription)")
            XCTAssertEqual(resolved.value, expected, accuracy: 1e-9, "unit \(unit.debugDescription)")
            XCTAssertEqual(resolved.value, 100.0, accuracy: 1e-3)
            XCTAssertEqual(resolved.source, .labBook)
        }
    }

    func testInchesRowIsConvertedToCentimetres() throws {
        let expected = 40.0 * UnitFormatter.centimetersPerInch
        for unit in ["in", "IN", " In "] {
            let c = candidates(lab: [lab("waist", id: "waist-a", day: d1, value: 40.0, unit: unit)], profile: 0)
            let resolved = try XCTUnwrap(resolveWaist(c), "unit \(unit.debugDescription)")
            XCTAssertEqual(resolved.value, expected, accuracy: 1e-9, "unit \(unit.debugDescription)")
            XCTAssertEqual(resolved.value, 101.6, accuracy: 1e-9)
        }
    }

    /// Kilograms and centimetres are taken as they are, with no arithmetic applied, in any case and
    /// with surrounding white space.
    func testKilogramAndCentimetreRowsAreTakenAsTheyAreInAnyCaseAndSpacing() {
        for unit in ["kg", "KG", "Kg", " kg", "kg\n"] {
            let c = candidates(lab: [lab(id: "weight-a", day: d1, value: 99.9537, unit: unit)])
            XCTAssertEqual(resolveWeight(c)?.value, 99.9537, "unit \(unit.debugDescription): the exact stored value")
        }
        for unit in ["cm", "CM", " Cm "] {
            let c = candidates(lab: [lab("waist", id: "waist-a", day: d1, value: 96.25, unit: unit)], profile: 0)
            XCTAssertEqual(resolveWaist(c)?.value, 96.25, "unit \(unit.debugDescription)")
        }
    }

    /// A row in a unit the resolver does not know is not a reading. It is skipped, and an older
    /// usable reading or the profile is used.
    func testUnknownUnitRowIsIgnored() {
        for unit in ["st", "stone", "g", "%", "", "kgs", "pound"] {
            let onlyUnknown = candidates(lab: [lab(id: "weight-a", day: d2, value: 15.7, unit: unit)], profile: 82.5)
            XCTAssertEqual(resolveWeight(onlyUnknown),
                           ResolvedBodyMeasurement(kind: .weight, value: 82.5, source: .profile, day: nil),
                           "unit \(unit.debugDescription)")
            XCTAssertTrue(BodyMeasurementResolver.series(.weight, candidates: onlyUnknown, policy: .unified).isEmpty)

            let behindUsable = candidates(lab: [lab(id: "weight-old", day: d1, value: 100.0),
                                                lab(id: "weight-a", day: d2, value: 15.7, unit: unit)])
            XCTAssertEqual(resolveWeight(behindUsable)?.value, 100.0, "unit \(unit.debugDescription)")
        }
    }

    /// A length is not a weight. A weight row carrying `cm` or `in`, or a waist row carrying `kg` or
    /// `lb`, is a row "in another unit" for its kind.
    func testUnitOfTheOtherKindIsIgnored() {
        for unit in ["cm", "in"] {
            let c = candidates(lab: [lab(id: "weight-a", day: d1, value: 100.0, unit: unit)], profile: 82.5)
            XCTAssertEqual(resolveWeight(c)?.source, .profile, "a weight in \(unit)")
        }
        for unit in ["kg", "lb", "lbs"] {
            let c = candidates(lab: [lab("waist", id: "waist-a", day: d1, value: 100.0, unit: unit)], profile: 0)
            XCTAssertNil(resolveWaist(c), "a waist in \(unit)")
        }
    }

    /// A row with no number, a number that is not finite, or one that is not positive is ignored.
    func testRowsWithNilNonFiniteOrNonPositiveValuesAreIgnored() {
        let bad: [Double?] = [nil, .nan, .infinity, -.infinity, 0, -0.0, -5.0]
        for (index, value) in bad.enumerated() {
            let c = candidates(lab: [lab(id: "weight-good", day: d1, value: 100.0),
                                     lab(id: "weight-bad-\(index)", day: d2, value: value)],
                               profile: 82.5)
            let resolved = resolveWeight(c)
            XCTAssertEqual(resolved?.value, 100.0, "value \(String(describing: value))")
            XCTAssertEqual(resolved?.day, d1)
            let series = BodyMeasurementResolver.series(.weight, candidates: c, policy: .unified)
            XCTAssertEqual(series.map(\.rowId), ["weight-good"])

            // A bad row on the SAME day as a good one does not win by being later either.
            let sameDay = candidates(lab: [lab(id: "weight-good", day: d1, value: 100.0),
                                           lab(id: "weight-bad-\(index)", day: d1, plus: 3600, value: value)])
            XCTAssertEqual(resolveWeight(sameDay)?.value, 100.0, "value \(String(describing: value))")
        }
    }

    /// Assumption 5 at the top of this file.
    func testUnifiedPolicyIgnoresNonFiniteAndNonPositiveAppleHealthValues() {
        for value in [Double.nan, .infinity, 0, -70.0] {
            let c = candidates(apple: [(day: d1, value: 100.0), (day: d2, value: value)], profile: 82.5)
            XCTAssertEqual(resolveWeight(c)?.value, 100.0, "value \(value)")
            XCTAssertEqual(BodyMeasurementResolver.series(.weight, candidates: c, policy: .unified).map(\.day), [d1])
        }
    }

    // MARK: - series

    /// §8.1: "`resolve` is `series(...).last(where: day <= asOf)`, else the profile value" — checked
    /// for every kind, every policy and a spread of as-of days, against a mixed candidate list.
    func testSeriesAndResolveAgreeOnTheCurrentValue() {
        let weight = candidates(
            lab: [lab(id: "weight-1", day: d1, value: 100.0),
                  lab(id: "weight-2a", day: d2, value: 99.6),
                  lab(id: "weight-2b", day: d2, plus: 60, value: 99.2),
                  lab(id: "weight-lb", day: d3, value: 216.9, unit: "lb"),
                  lab(id: "weight-bad", day: d4, value: .nan)],
            apple: [(day: "2030-12-25", value: 101.0), (day: d2, value: 99.9), (day: "2031-02-05", value: 97.5)],
            profile: 82.5)
        let waist = candidates(lab: [lab("waist", id: "waist-1", day: d1, value: 100.0),
                                     lab("waist", id: "waist-in", day: d3, value: 39.0, unit: "in")],
                               profile: 91.0)
        let asOfDays = ["2030-01-01", "2030-12-25", "2031-01-07", d1, "2031-01-10", d2, d3, d4,
                        "2031-02-04", "2031-02-05", "2099-12-31"]

        for policy in allPolicies {
            for (kind, c) in [(BodyMeasurementKind.weight, weight), (BodyMeasurementKind.waist, waist)] {
                let series = BodyMeasurementResolver.series(kind, candidates: c, policy: policy)
                for asOf in asOfDays {
                    let resolved = BodyMeasurementResolver.resolve(kind, asOf: asOf, candidates: c, policy: policy)
                    if let last = series.last(where: { $0.day <= asOf }) {
                        XCTAssertEqual(resolved,
                                       ResolvedBodyMeasurement(kind: kind, value: last.value, source: last.source, day: last.day),
                                       "\(kind) \(policy) as of \(asOf)")
                    } else {
                        XCTAssertEqual(resolved,
                                       ResolvedBodyMeasurement(kind: kind, value: c.profileValue, source: .profile, day: nil),
                                       "\(kind) \(policy) as of \(asOf)")
                    }
                }
            }
        }

        // And the series the loop compared against is the expected one, so the agreement is not
        // two empty lists agreeing with each other.
        let unified = BodyMeasurementResolver.series(.weight, candidates: weight, policy: .unified)
        XCTAssertEqual(unified.map(\.day), ["2030-12-25", d1, d2, d3, "2031-02-05"])
        XCTAssertEqual(unified.map(\.source), [.appleHealth, .labBook, .labBook, .labBook, .appleHealth])
    }

    /// Assumption 1 at the top of this file: ascending, one element per day, with the identity of the
    /// row that represents the day.
    func testSeriesIsAscendingOnePerDayAndCarriesTheRowIdentity() {
        let c = candidates(lab: [lab(id: "weight-3", day: d3, value: 98.4),
                                 lab(id: "weight-1", day: d1, value: 100.0),
                                 lab(id: "weight-1-later", day: d1, plus: 120, value: 99.9)],
                           apple: [(day: d4, value: 97.6), (day: d2, value: 99.2)])
        let series = BodyMeasurementResolver.series(.weight, candidates: c, policy: .unified)
        XCTAssertEqual(series, [
            DatedBodyMeasurement(day: d1, takenAt: epoch(d1, plus: 120), value: 99.9, source: .labBook, rowId: "weight-1-later"),
            DatedBodyMeasurement(day: d2, takenAt: nil, value: 99.2, source: .appleHealth, rowId: nil),
            DatedBodyMeasurement(day: d3, takenAt: epoch(d3), value: 98.4, source: .labBook, rowId: "weight-3"),
            DatedBodyMeasurement(day: d4, takenAt: nil, value: 97.6, source: .appleHealth, rowId: nil),
        ])
    }

    /// The result is a function of the candidates as a set: shuffling them changes nothing.
    func testCandidateOrderDoesNotChangeTheResult() {
        let rows = [lab(id: "weight-1", day: d1, value: 100.0), lab(id: "weight-2", day: d2, value: 99.2),
                    lab(id: "weight-2b", day: d2, plus: 5, value: 99.1), lab(id: "weight-3", day: d3, value: 98.4)]
        let apple: [(day: String, value: Double)] = [(day: d2, value: 99.9), (day: d4, value: 97.6), (day: "2030-12-25", value: 101.0)]
        let reference = BodyMeasurementResolver.series(.weight, candidates: candidates(lab: rows, apple: apple), policy: .unified)
        XCTAssertEqual(reference.count, 5)
        let reorderedLab = [rows[3], rows[1], rows[0], rows[2]]
        let reorderedApple = [apple[2], apple[0], apple[1]]
        XCTAssertEqual(BodyMeasurementResolver.series(.weight, candidates: candidates(lab: reorderedLab, apple: reorderedApple),
                                                      policy: .unified), reference)
        XCTAssertEqual(BodyMeasurementResolver.series(.weight, candidates: candidates(lab: rows.reversed(), apple: apple.reversed()),
                                                      policy: .unified), reference)
    }

    /// §6.1 and §9.1: a reading's day was decided when it was saved. The resolver uses the stored
    /// `day`, not a day worked out again from `takenAt` in whatever zone the device is in now.
    func testStoredDayIsUsedAndNotRecomputedFromTheInstant() {
        // 2031-01-08 20:30 UTC, saved in a zone where that was already the 9th.
        let row = LabMarkerRow(id: "weight-travel", deviceId: "my-whoop", markerKey: "weight",
                               category: "bodyMeasurement", day: "2031-01-09", takenAt: 1_925_670_600,
                               value: 100.0, valueText: nil, unit: "kg", source: "manual", note: nil,
                               referenceText: nil)
        let c = candidates(lab: [row], profile: 82.5)
        XCTAssertEqual(BodyMeasurementResolver.series(.weight, candidates: c, policy: .unified).map(\.day), ["2031-01-09"])
        XCTAssertEqual(resolveWeight(c, asOf: "2031-01-08")?.source, .profile, "not yet taken on the 8th, by its stored day")
        XCTAssertEqual(resolveWeight(c, asOf: "2031-01-09")?.value, 100.0)
    }

    // MARK: - §8.3 flag off

    func testPolicyMapsTheFlagAndTheConsumer() {
        XCTAssertEqual(BodyMeasurementResolver.policy(flagEnabled: true, consumer: .display), .unified)
        XCTAssertEqual(BodyMeasurementResolver.policy(flagEnabled: true, consumer: .estimate), .unified)
        XCTAssertEqual(BodyMeasurementResolver.policy(flagEnabled: false, consumer: .display), .legacyDisplay)
        XCTAssertEqual(BodyMeasurementResolver.policy(flagEnabled: false, consumer: .estimate), .legacyEstimate)
    }

    /// Fault line F25: Lab Book is not consulted under `legacyDisplay`. Apple Health, then the profile.
    func testLegacyDisplayPolicyIgnoresLabBook() {
        let labOnly = candidates(lab: [lab(id: "weight-a", day: d3, value: 98.4)], profile: 82.5)
        XCTAssertEqual(resolveWeight(labOnly, policy: .legacyDisplay),
                       ResolvedBodyMeasurement(kind: .weight, value: 82.5, source: .profile, day: nil))
        XCTAssertTrue(BodyMeasurementResolver.series(.weight, candidates: labOnly, policy: .legacyDisplay).isEmpty)

        // A newer Lab Book reading does not displace an older Apple Health one, and a same-day one
        // does not beat it.
        let both = candidates(lab: [lab(id: "weight-a", day: d3, value: 98.4), lab(id: "weight-b", day: d2, value: 99.0)],
                              apple: [(day: d2, value: 99.9)], profile: 82.5)
        XCTAssertEqual(resolveWeight(both, policy: .legacyDisplay),
                       ResolvedBodyMeasurement(kind: .weight, value: 99.9, source: .appleHealth, day: d2))
        XCTAssertEqual(BodyMeasurementResolver.series(.weight, candidates: both, policy: .legacyDisplay),
                       [DatedBodyMeasurement(day: d2, takenAt: nil, value: 99.9, source: .appleHealth, rowId: nil)])

        // Waist has no Apple Health source: the profile value only.
        let waist = candidates(lab: [lab("waist", id: "waist-a", day: d3, value: 96.0)], profile: 91.0)
        XCTAssertEqual(resolveWaist(waist, policy: .legacyDisplay),
                       ResolvedBodyMeasurement(kind: .waist, value: 91.0, source: .profile, day: nil))
    }

    /// `legacyEstimate` is the profile value and nothing else, whatever the stores hold.
    func testLegacyEstimatePolicyReturnsProfileOnly() {
        let c = candidates(lab: [lab(id: "weight-a", day: d3, value: 98.4)],
                           apple: [(day: d2, value: 99.9)], profile: 82.5)
        for asOf in ["2030-01-01", d2, d3, "2031-06-30"] {
            XCTAssertEqual(resolveWeight(c, asOf: asOf, policy: .legacyEstimate),
                           ResolvedBodyMeasurement(kind: .weight, value: 82.5, source: .profile, day: nil))
        }
        XCTAssertTrue(BodyMeasurementResolver.series(.weight, candidates: c, policy: .legacyEstimate).isEmpty)

        let unset = candidates(lab: [lab(id: "weight-a", day: d3, value: 98.4)], apple: [(day: d2, value: 99.9)],
                               profile: 75.0, isSet: false)
        XCTAssertEqual(resolveWeight(unset, policy: .legacyEstimate),
                       ResolvedBodyMeasurement(kind: .weight, value: 75.0, source: .profileDefault, day: nil),
                       "the estimates use the default of 75 today (Profile.swift:125) and keep doing so")

        let waist = candidates(lab: [lab("waist", id: "waist-a", day: d3, value: 96.0)], profile: 91.0)
        XCTAssertEqual(resolveWaist(waist, policy: .legacyEstimate),
                       ResolvedBodyMeasurement(kind: .waist, value: 91.0, source: .profile, day: nil))
        XCTAssertNil(resolveWaist(candidates(lab: [lab("waist", id: "waist-a", day: d3, value: 96.0)], profile: 0),
                                  policy: .legacyEstimate),
                     "no waist in the profile means no waist for the estimates, as today (HealthView.swift:769)")
    }

    /// The flag-off equivalence test (§12.5). The oracles below are today's code, restated:
    ///
    ///  - display: `LiquidTodayView.swift:3251-3252` with `:1613-1618` (and the redesign, which reuses
    ///    that day model): the Apple Health value of the selected day, else the newest Apple Health
    ///    point on or before it, else `profile.weightKg`;
    ///  - estimate: `IntelligenceEngine.swift:897` and `AppModel.swift:1044`: `profile.weightKg`;
    ///  - waist: `IntelligenceEngine.swift:582` and `HealthView.swift:769`: `profile.waistCm` when above 0.
    ///
    /// For every case the legacy policies must return the oracle's number, and must return the same
    /// thing with and without Lab Book rows in the candidates: with the flag off a weigh-in in the
    /// store changes nothing.
    func testFlagOffPoliciesMatchTheOldTodayAndEstimateBehaviour() {
        func oldDisplayWeight(_ apple: [(day: String, value: Double)], selected: String, profile: Double) -> Double {
            apple.sorted { $0.day < $1.day }.last(where: { $0.day <= selected })?.value ?? profile
        }
        func oldEstimateWeight(profile: Double) -> Double { profile }
        func oldWaist(profile: Double) -> Double? { profile > 0 ? profile : nil }

        let labRows = [lab(id: "weight-1", day: d1, value: 100.0), lab(id: "weight-2", day: d2, value: 99.2),
                       lab(id: "weight-3", day: d3, value: 98.4), lab(id: "weight-far", day: "2031-06-01", value: 60.0),
                       lab(id: "weight-lb", day: d4, value: 215.0, unit: "lb")]
        let waistRows = [lab("waist", id: "waist-1", day: d1, value: 100.0), lab("waist", id: "waist-3", day: d3, value: 99.0)]
        let appleCases: [[(day: String, value: Double)]] = [
            [],
            [(day: d2, value: 99.9)],
            [(day: "2030-12-25", value: 101.0), (day: d2, value: 99.9), (day: d4, value: 97.1)],
        ]
        let profiles: [(value: Double, isSet: Bool)] = [(82.5, true), (75.0, false), (75.0, true)]
        let selectedDays = ["2030-12-01", "2030-12-25", d1, d2, "2031-01-20", d4, "2031-06-30"]

        for apple in appleCases {
            for profile in profiles {
                let without = candidates(lab: [], apple: apple, profile: profile.value, isSet: profile.isSet)
                let with = candidates(lab: labRows, apple: apple, profile: profile.value, isSet: profile.isSet)
                for selected in selectedDays {
                    let label = "apple \(apple.map(\.day)) profile \(profile) selected \(selected)"
                    let display = resolveWeight(with, asOf: selected, policy: .legacyDisplay)
                    XCTAssertEqual(display?.value, oldDisplayWeight(apple, selected: selected, profile: profile.value), label)
                    XCTAssertEqual(display, resolveWeight(without, asOf: selected, policy: .legacyDisplay),
                                   "Lab Book rows changed the Today weight with the flag off: \(label)")
                    XCTAssertNotEqual(display?.source, .labBook, label)

                    let estimate = resolveWeight(with, asOf: selected, policy: .legacyEstimate)
                    XCTAssertEqual(estimate?.value, oldEstimateWeight(profile: profile.value), label)
                    XCTAssertEqual(estimate, resolveWeight(without, asOf: selected, policy: .legacyEstimate),
                                   "Lab Book rows changed the estimates' weight with the flag off: \(label)")
                    XCTAssertNil(estimate?.day, label)
                }
                for policy in [BodyMeasurementPolicy.legacyDisplay, .legacyEstimate] {
                    XCTAssertEqual(BodyMeasurementResolver.series(.weight, candidates: with, policy: policy),
                                   BodyMeasurementResolver.series(.weight, candidates: without, policy: policy))
                }
            }
        }

        for profileWaist in [0.0, 91.0] {
            let without = candidates(profile: profileWaist, isSet: profileWaist > 0)
            let with = candidates(lab: waistRows, profile: profileWaist, isSet: profileWaist > 0)
            for policy in [BodyMeasurementPolicy.legacyDisplay, .legacyEstimate] {
                for selected in selectedDays {
                    let resolved = resolveWaist(with, asOf: selected, policy: policy)
                    XCTAssertEqual(resolved?.value, oldWaist(profile: profileWaist), "waist \(profileWaist) \(policy) \(selected)")
                    XCTAssertEqual(resolved, resolveWaist(without, asOf: selected, policy: policy))
                }
                XCTAssertTrue(BodyMeasurementResolver.series(.waist, candidates: with, policy: policy).isEmpty)
            }
        }
    }

    /// The same candidates under the unified policy DO differ, so the equivalence above is a property
    /// of the legacy policies and not of the data chosen.
    func testTheSameCandidatesResolveDifferentlyOnceTheFlagIsOn() {
        let c = candidates(lab: [lab(id: "weight-3", day: d3, value: 98.4)], apple: [(day: d2, value: 99.9)], profile: 82.5)
        XCTAssertEqual(resolveWeight(c, policy: .legacyDisplay)?.value, 99.9)
        XCTAssertEqual(resolveWeight(c, policy: .legacyEstimate)?.value, 82.5)
        XCTAssertEqual(resolveWeight(c, policy: .unified)?.value, 98.4)
    }

    // MARK: - §8.2 excluded stores (through the provider)

    private var suites: [String] = []

    override func tearDown() {
        for name in suites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        suites = []
        super.tearDown()
    }

    private func flagOnDefaults() throws -> UserDefaults {
        let name = "BodyMeasurementResolverTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        suites.append(name)
        defaults.set(true, forKey: "noop.cutScorecardEnabled")
        defaults.set(82.5, forKey: "profile.weightKg")
        return defaults
    }

    /// A day key `offset` days from `today`, by the UTC calendar.
    private func day(_ today: Date, _ offset: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: today.addingTimeInterval(Double(offset) * 86_400))
    }

    /// The nutrition CSV writes a `weight` series in the export's own unit with no unit recorded
    /// (`NutritionCsvImport.swift:23-24`). It is never a body weight, alone or beside real readings.
    ///
    /// Dates are relative to the real clock, two days back, because the repository's series reads are
    /// windowed on the real clock.
    @MainActor
    func testNutritionCsvWeightIsNeverACandidate() async throws {
        let anchor = Date().addingTimeInterval(-2 * 86_400)
        let today = day(anchor, 0)
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: "my-whoop")
        repo.setStoreForTesting(store)
        try await store.upsertMetricSeries([MetricPoint(day: day(anchor, -1), key: "weight", value: 215.0),
                                            MetricPoint(day: today, key: "weight", value: 214.0)],
                                           deviceId: "nutrition-csv")
        let provider = BodyMeasurementProvider(repository: repo, defaults: try flagOnDefaults(), today: { today })
        await provider.refresh()

        XCTAssertTrue(provider.candidates(.weight).labBook.isEmpty)
        XCTAssertTrue(provider.candidates(.weight).appleHealth.isEmpty, "the nutrition series is not an Apple Health value")
        XCTAssertTrue(provider.series(.weight, consumer: .display).isEmpty)
        XCTAssertEqual(provider.current(.weight, consumer: .display),
                       ResolvedBodyMeasurement(kind: .weight, value: 82.5, source: .profile, day: nil))
        XCTAssertEqual(provider.current(.weight, consumer: .estimate)?.value, 82.5)

        // Beside a real Apple Health reading it is still absent.
        try await store.upsertMetricSeries([MetricPoint(day: day(anchor, -3), key: "weight", value: 99.9)],
                                           deviceId: "apple-health")
        await provider.refresh()
        XCTAssertEqual(provider.series(.weight, consumer: .display).map(\.value), [99.9])
        XCTAssertEqual(provider.current(.weight, consumer: .display)?.value, 99.9)
    }

    /// The `lab-book` series is a projection of the Lab Book rows the resolver already reads. Reading
    /// both would count one reading twice, and a projection left without its row (written here by
    /// hand) must not appear as a reading at all.
    @MainActor
    func testLabBookProjectionSeriesIsNeverACandidate() async throws {
        let anchor = Date().addingTimeInterval(-2 * 86_400)
        let today = day(anchor, 0)
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: "my-whoop")
        repo.setStoreForTesting(store)
        // A projected point with no labMarker row behind it.
        try await store.upsertMetricSeries([MetricPoint(day: day(anchor, -1), key: "weight", value: 150.0),
                                            MetricPoint(day: day(anchor, -1), key: "waist", value: 150.0)],
                                           deviceId: WhoopStore.labBookSourceId)
        let provider = BodyMeasurementProvider(repository: repo, defaults: try flagOnDefaults(), today: { today })
        await provider.refresh()
        XCTAssertTrue(provider.series(.weight, consumer: .display).isEmpty)
        XCTAssertTrue(provider.series(.waist, consumer: .display).isEmpty)
        XCTAssertEqual(provider.current(.weight, consumer: .display)?.source, .profile)

        // A real row, which the store also projects: one reading, from the row.
        let taken = Int(anchor.timeIntervalSince1970) - 86_400
        try await store.upsertLabMarkers([LabMarkerRow(
            id: "weight-\(taken)-0A1B2C3D", deviceId: "my-whoop", markerKey: "weight", category: "bodyMeasurement",
            day: day(anchor, -1), takenAt: taken, value: 99.2, valueText: nil, unit: "kg", source: "manual",
            note: nil, referenceText: nil)])
        await provider.refresh()
        let series = provider.series(.weight, consumer: .display)
        XCTAssertEqual(series.count, 1, "the row and its projection are one reading")
        XCTAssertEqual(series.first?.source, .labBook)
        XCTAssertEqual(series.first?.value, 99.2)
        XCTAssertEqual(series.first?.rowId, "weight-\(taken)-0A1B2C3D")
    }
}
