// API ASSUMED BY THESE TESTS
//
// Written before the implementation exists, from docs/personal/superapp/specs/stage-3.md §6.2.
// This file constructs only the two input value types:
//
//   public enum IntakeNutrient: String, Sendable, CaseIterable { case protein, energy }
//
//   public struct IntakeSample: Equatable, Sendable {
//       public let id: String
//       public let nutrient: IntakeNutrient
//       public let startEpochSeconds: Int
//       public let amount: Double
//       public let sourceId: String
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
// It also uses the existing test helper `CutScorecardFixture.dayNumber(_:)` and `dayKey(_:)`
// (days since 1970-01-01 by the civil-calendar algorithm), which is independent of the engine and of
// `CanonicalDay`.

import XCTest
@testable import StrandAnalytics

/// The synthetic intake fixture of `docs/personal/superapp/specs/stage-3.md` §13.
///
/// Everything here is invented. The person is stage 1's one Fixture Person (`stage-1.md` §13, rulings
/// R48 and addendum A7): protein floor 100 g. This file adds that person's intake settings and the
/// hand-worked samples of §13.2, which are dated 2030-12-09 and 2030-12-10, four weeks before the
/// fixture phase starts, so no day carries two different protein totals across the stages.
///
/// No value was taken from a real person's log, and no food app is named: the two writing apps are
/// "Fixture Food" and "Fixture Other".
enum IntakeFixture {

    // MARK: - Instants

    /// Epoch seconds of a UTC instant written `yyyy-MM-ddTHH:mm:ssZ`. Parsed by hand with the fixture's
    /// own civil-calendar arithmetic, so neither `Calendar`, a formatter nor the code under test decides
    /// what the fixture's instants are.
    static func epoch(_ iso: String) -> Int {
        precondition(iso.utf8.count == 20 && iso.hasSuffix("Z"), "fixture instant must be yyyy-MM-ddTHH:mm:ssZ: \(iso)")
        let day = String(iso.prefix(10))
        let clock = iso.dropFirst(11).dropLast(1).split(separator: ":").compactMap { Int($0) }
        precondition(clock.count == 3, "fixture instant must carry HH:mm:ss: \(iso)")
        return CutScorecardFixture.dayNumber(day) * 86_400 + clock[0] * 3_600 + clock[1] * 60 + clock[2]
    }

    /// The UTC day key of an instant, by the fixture's own arithmetic.
    static func utcDayKey(_ epochSeconds: Int) -> String {
        localDayKey(epochSeconds, offsetSeconds: 0)
    }

    /// The day key of an instant at a fixed offset from UTC, by the fixture's own arithmetic. Used as the
    /// independent model in generated checks; valid only where the zone's offset does not change.
    static func localDayKey(_ epochSeconds: Int, offsetSeconds: Int) -> String {
        let local = epochSeconds + offsetSeconds
        let day = local >= 0 ? local / 86_400 : -((-local + 86_399) / 86_400)
        return CutScorecardFixture.dayKey(day)
    }

    // MARK: - Person and settings (§13.1)

    /// Stage 1's `proteinFloorGrams` for the Fixture Person; a whole number (stage 1 R45).
    static let proteinFloorGrams = 100.0
    static let energyLowKcal = 2400.0
    static let energyHighKcal = 2600.0
    static let energyHardFloorKcal = 2100.0
    /// 20:00 as a minute of the day.
    static let cutoffMinuteOfDay = 1200
    static let supplementName = "Fixture supplement"
    static let supplementQuestion = "Did you take Fixture supplement?"
    static let foodAppName = "Fixture Food"
    static let foodAppId = "app.fixture.food"
    static let otherAppName = "Fixture Other"
    static let otherAppId = "app.fixture.other"
    static let presetName = "Fixture shake"
    static let presetProteinGrams = 30.0
    static let presetEnergyKcal = 150.0

    // MARK: - Window and zone logs (§13.2, §13.3)

    static let firstDay = "2030-12-09"
    static let lastDay = "2030-12-10"

    static let utc = "Etc/UTC"
    static let auckland = "Pacific/Auckland"
    static let losAngeles = "America/Los_Angeles"

    /// Auckland is thirteen hours ahead of UTC on the fixture's dates (daylight time).
    static let aucklandOffsetSeconds = 13 * 3_600
    /// Los Angeles is eight hours behind UTC on the fixture's dates (standard time).
    static let losAngelesOffsetSeconds = -8 * 3_600

    /// The instant the phone is first seen in Auckland in zone log E.
    static let eastwardChange = epoch("2030-12-09T18:00:00Z")
    /// The instant the phone is first seen in Los Angeles in zone log W.
    static let westwardChange = epoch("2030-12-09T20:00:00Z")

    static func segment(_ from: Int, _ zone: String) -> IntakeZoneSegment {
        IntakeZoneSegment(fromEpochSeconds: from, zoneIdentifier: zone)
    }

    /// Zone log U: UTC throughout.
    static let logU = [segment(0, utc)]
    /// Zone log E: UTC, then Auckland from 18:00 UTC on 2030-12-09 (an eastward change mid-day).
    static let logE = [segment(0, utc), segment(eastwardChange, auckland)]
    /// Zone log W: Auckland, then Los Angeles from 20:00 UTC on 2030-12-09 (a westward change).
    static let logW = [segment(0, auckland), segment(westwardChange, losAngeles)]

    // MARK: - Samples (§13.2)

    static func protein(_ id: String, _ iso: String, _ grams: Double,
                        source: String = foodAppId) -> IntakeSample {
        IntakeSample(id: id, nutrient: .protein, startEpochSeconds: epoch(iso), amount: grams, sourceId: source)
    }

    static func energy(_ id: String, _ iso: String, _ kcal: Double,
                       source: String = foodAppId) -> IntakeSample {
        IntakeSample(id: id, nutrient: .energy, startEpochSeconds: epoch(iso), amount: kcal, sourceId: source)
    }

    static let s1 = protein("s1", "2030-12-09T08:00:00Z", 30)
    static let s2 = energy("s2", "2030-12-09T08:00:00Z", 450)
    static let s3 = protein("s3", "2030-12-09T13:00:00Z", 40)
    static let s4 = energy("s4", "2030-12-09T13:00:00Z", 700)
    static let s5 = protein("s5", "2030-12-09T23:59:59Z", 25)
    static let s6 = energy("s6", "2030-12-09T23:59:59Z", 300)
    static let s7 = protein("s7", "2030-12-10T00:00:00Z", 20)
    static let s8 = energy("s8", "2030-12-10T00:00:00Z", 250)
    /// The one sample written by the second app.
    static let s9 = protein("s9", "2030-12-09T10:00:00Z", 10, source: otherAppId)

    /// The edit of §13.3: s3 replaced by an entry at the same instant with 45 g and a new id.
    static let s3b = protein("s3b", "2030-12-09T13:00:00Z", 45)
    /// The same edit where the food app keeps the sample id.
    static let s3SameId = protein("s3", "2030-12-09T13:00:00Z", 45)

    /// s1 to s8: everything the food app wrote.
    static let foodSamples = [s1, s2, s3, s4, s5, s6, s7, s8]
    /// s1 to s9: both apps.
    static let allSamples = foodSamples + [s9]

    /// The two protein samples of the westward case: `x` is the earlier instant and falls on the later
    /// day; `y` is the later instant and falls on the earlier day.
    static let westX = protein("x", "2030-12-09T19:00:00Z", 10)
    static let westY = protein("y", "2030-12-09T21:00:00Z", 15)

    // MARK: - A fixed-seed generator

    /// A 64-bit linear congruential generator (Knuth's MMIX constants), written out so the same stream
    /// is reproduced on every run and every machine. Nothing in the intake tests draws system randomness.
    struct Generator {
        var state: UInt64

        /// A value in `0 ..< bound`.
        mutating func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(state >> 33) % bound
        }

        /// `items` in a generated order (Fisher–Yates over this stream).
        mutating func shuffled<T>(_ items: [T]) -> [T] {
            var out = items
            guard out.count > 1 else { return out }
            for i in stride(from: out.count - 1, to: 0, by: -1) {
                out.swapAt(i, next(i + 1))
            }
            return out
        }
    }
}
