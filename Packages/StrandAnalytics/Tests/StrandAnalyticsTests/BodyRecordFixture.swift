import XCTest
@testable import StrandAnalytics

// API ASSUMED BY THIS FIXTURE
//
// Written before the implementation, from docs/personal/superapp/specs/stage-4.md §6.3. The full
// list is at the top of BodyRecordTests.swift; this file calls only:
//
//   BodyRecordReading.init(value: Double, decimals: Int)
//   BodyRecordDirection (.up, .down, .same)
//   BodyScanComponents.init(armsLean:armLeftLean:armRightLean:legsLean:legLeftLean:legRightLean:)
//       every parameter `Double? = nil`
//   BodyScanCheckInput.init()            every field nil, each a `var … : Double?`

/// The three synthetic scans of `docs/personal/superapp/specs/stage-4.md` §13.1 and the comparison
/// table of §13.3, as zone-free values.
///
/// Everything here is invented. "Fixture Person" does not exist and is the Fixture Person of the
/// stage 1 specification §13: each scan's total mass is that person's stage 1 weight on the scan's
/// day. The expected rows were recomputed from §7.3 and §7.4 with a throwaway calculation before
/// they were written down. They are not the output of any implementation.
enum BodyRecordFixture {

    /// One numeric scan field: its catalogue key and the decimals it is displayed at (§5.2; `weight`
    /// and `body_fat` from the built-in catalogue).
    struct Field {
        let key: String
        let decimals: Int
    }

    /// The numeric fields in the order a report prints them (§7.7).
    static let fields: [Field] = [
        Field(key: "weight", decimals: 1),
        Field(key: "scan_fat_mass", decimals: 1),
        Field(key: "scan_lean_mass", decimals: 1),
        Field(key: "scan_bone_mass", decimals: 2),
        Field(key: "scan_fat_free_mass", decimals: 1),
        Field(key: "body_fat", decimals: 1),
        Field(key: "scan_visceral_fat_mass", decimals: 0),
        Field(key: "scan_visceral_fat_area", decimals: 0),
        Field(key: "scan_android_fat_pct", decimals: 1),
        Field(key: "scan_gynoid_fat_pct", decimals: 1),
        Field(key: "scan_android_gynoid_ratio", decimals: 2),
        Field(key: "scan_arms_lean_mass", decimals: 2),
        Field(key: "scan_arm_left_lean_mass", decimals: 2),
        Field(key: "scan_arm_right_lean_mass", decimals: 2),
        Field(key: "scan_legs_lean_mass", decimals: 2),
        Field(key: "scan_leg_left_lean_mass", decimals: 2),
        Field(key: "scan_leg_right_lean_mass", decimals: 2),
        Field(key: "scan_trunk_lean_mass", decimals: 2),
        Field(key: "scan_bmd", decimals: 3),
        Field(key: "scan_bmd_t_score", decimals: 1),
        Field(key: "scan_bmd_z_score", decimals: 1),
        Field(key: "scan_rmr_lab_estimate", decimals: 0),
    ]

    // MARK: - §13.1 The three scans (stored units; an absent key was not entered)

    /// Scan A, 2031-01-08.
    static let scanA: [String: Double] = [
        "weight": 100.0,
        "scan_fat_mass": 30.0,
        "scan_lean_mass": 67.0,
        "scan_bone_mass": 3.00,
        "scan_fat_free_mass": 70.0,
        "body_fat": 30.0,
        "scan_visceral_fat_mass": 1000,
        "scan_android_fat_pct": 36.0,
        "scan_gynoid_fat_pct": 30.0,
        "scan_android_gynoid_ratio": 1.20,
        "scan_arms_lean_mass": 10.00,
        "scan_arm_left_lean_mass": 4.90,
        "scan_arm_right_lean_mass": 5.10,
        "scan_legs_lean_mass": 20.00,
        "scan_leg_left_lean_mass": 10.00,
        "scan_leg_right_lean_mass": 10.00,
        "scan_trunk_lean_mass": 32.00,
        "scan_bmd": 1.200,
        "scan_bmd_t_score": 0.5,
        "scan_bmd_z_score": 0.4,
        "scan_rmr_lab_estimate": 1900,
    ]

    /// Scan B, 2031-04-09.
    static let scanB: [String: Double] = [
        "weight": 95.0,
        "scan_fat_mass": 26.0,
        "scan_lean_mass": 66.0,
        "scan_bone_mass": 3.00,
        "scan_fat_free_mass": 69.0,
        "body_fat": 27.4,
        "scan_visceral_fat_mass": 800,
        "scan_visceral_fat_area": 80,
        "scan_android_fat_pct": 30.0,
        "scan_gynoid_fat_pct": 26.0,
        "scan_android_gynoid_ratio": 1.15,
        "scan_arms_lean_mass": 10.40,
        "scan_arm_left_lean_mass": 5.20,
        "scan_arm_right_lean_mass": 5.20,
        "scan_legs_lean_mass": 19.60,
        "scan_leg_left_lean_mass": 9.80,
        "scan_leg_right_lean_mass": 9.80,
        "scan_trunk_lean_mass": 31.50,
        "scan_rmr_lab_estimate": 1850,
    ]

    /// Scan C, 2031-05-28: totals, both arm sides and the legs total only.
    static let scanC: [String: Double] = [
        "weight": 94.0,
        "scan_fat_mass": 25.0,
        "scan_lean_mass": 66.0,
        "scan_bone_mass": 3.00,
        "scan_arm_left_lean_mass": 5.30,
        "scan_arm_right_lean_mass": 5.30,
        "scan_legs_lean_mass": 19.50,
    ]

    // MARK: - Builders

    /// The displayed reading of one field of a scan, or nil when the field was not entered.
    static func reading(_ scan: [String: Double], _ key: String) -> BodyRecordReading? {
        guard let value = scan[key], let field = fields.first(where: { $0.key == key }) else { return nil }
        return BodyRecordReading(value: value, decimals: field.decimals)
    }

    /// The segment lean masses of a scan, as `BodyScanDerivation.derive` takes them.
    static func components(_ scan: [String: Double]) -> BodyScanComponents {
        BodyScanComponents(armsLean: scan["scan_arms_lean_mass"],
                           armLeftLean: scan["scan_arm_left_lean_mass"],
                           armRightLean: scan["scan_arm_right_lean_mass"],
                           legsLean: scan["scan_legs_lean_mass"],
                           legLeftLean: scan["scan_leg_left_lean_mass"],
                           legRightLean: scan["scan_leg_right_lean_mass"])
    }

    /// The printed figures of a scan, as `BodyScanChecks.mismatches` takes them.
    static func checkInput(_ scan: [String: Double]) -> BodyScanCheckInput {
        var input = BodyScanCheckInput()
        input.totalMass = scan["weight"]
        input.fatMass = scan["scan_fat_mass"]
        input.leanMass = scan["scan_lean_mass"]
        input.boneMass = scan["scan_bone_mass"]
        input.fatFreeMass = scan["scan_fat_free_mass"]
        input.bodyFatPercent = scan["body_fat"]
        input.armsLean = scan["scan_arms_lean_mass"]
        input.armLeftLean = scan["scan_arm_left_lean_mass"]
        input.armRightLean = scan["scan_arm_right_lean_mass"]
        input.legsLean = scan["scan_legs_lean_mass"]
        input.legLeftLean = scan["scan_leg_left_lean_mass"]
        input.legRightLean = scan["scan_leg_right_lean_mass"]
        input.androidFatPercent = scan["scan_android_fat_pct"]
        input.gynoidFatPercent = scan["scan_gynoid_fat_pct"]
        input.androidGynoidRatio = scan["scan_android_gynoid_ratio"]
        return input
    }

    // MARK: - §13.3 Expected comparison, scan A to scan B

    /// What `BodyRecordComparison.compare` must return for one row.
    enum Expected: Equatable {
        case both(earlier: Double, later: Double, delta: Double, percent: Double?, direction: BodyRecordDirection)
        case onlyEarlier(Double)
        case onlyLater(Double)
        case neither
    }

    /// Every stored field of §13.3. Where the specification's table prints "hidden" for the percent,
    /// `compare` still returns one and the presenter does not show it; the value here is the one §7.3
    /// gives (for body fat, −2.6 ÷ 30.0 × 100 = −8.67, shown at one decimal as −8.7).
    static let expectedAToB: [(key: String, expected: Expected)] = [
        ("weight", .both(earlier: 100.0, later: 95.0, delta: -5.0, percent: -5.0, direction: .down)),
        ("scan_fat_mass", .both(earlier: 30.0, later: 26.0, delta: -4.0, percent: -13.3, direction: .down)),
        ("scan_lean_mass", .both(earlier: 67.0, later: 66.0, delta: -1.0, percent: -1.5, direction: .down)),
        ("scan_bone_mass", .both(earlier: 3.0, later: 3.0, delta: 0.0, percent: 0.0, direction: .same)),
        ("scan_fat_free_mass", .both(earlier: 70.0, later: 69.0, delta: -1.0, percent: -1.4, direction: .down)),
        ("body_fat", .both(earlier: 30.0, later: 27.4, delta: -2.6, percent: -8.7, direction: .down)),
        ("scan_visceral_fat_mass", .both(earlier: 1000, later: 800, delta: -200, percent: -20.0, direction: .down)),
        ("scan_visceral_fat_area", .onlyLater(80)),
        ("scan_android_fat_pct", .both(earlier: 36.0, later: 30.0, delta: -6.0, percent: -16.7, direction: .down)),
        ("scan_gynoid_fat_pct", .both(earlier: 30.0, later: 26.0, delta: -4.0, percent: -13.3, direction: .down)),
        ("scan_android_gynoid_ratio", .both(earlier: 1.2, later: 1.15, delta: -0.05, percent: -4.2, direction: .down)),
        ("scan_arms_lean_mass", .both(earlier: 10.0, later: 10.4, delta: 0.4, percent: 4.0, direction: .up)),
        ("scan_arm_left_lean_mass", .both(earlier: 4.9, later: 5.2, delta: 0.3, percent: 6.1, direction: .up)),
        ("scan_arm_right_lean_mass", .both(earlier: 5.1, later: 5.2, delta: 0.1, percent: 2.0, direction: .up)),
        ("scan_legs_lean_mass", .both(earlier: 20.0, later: 19.6, delta: -0.4, percent: -2.0, direction: .down)),
        ("scan_leg_left_lean_mass", .both(earlier: 10.0, later: 9.8, delta: -0.2, percent: -2.0, direction: .down)),
        ("scan_leg_right_lean_mass", .both(earlier: 10.0, later: 9.8, delta: -0.2, percent: -2.0, direction: .down)),
        ("scan_trunk_lean_mass", .both(earlier: 32.0, later: 31.5, delta: -0.5, percent: -1.6, direction: .down)),
        ("scan_bmd", .onlyEarlier(1.2)),
        ("scan_bmd_t_score", .onlyEarlier(0.5)),
        ("scan_bmd_z_score", .onlyEarlier(0.4)),
        ("scan_rmr_lab_estimate", .both(earlier: 1900, later: 1850, delta: -50, percent: -2.6, direction: .down)),
    ]

    /// The derived row of §13.3: arms to legs, 50.0 then 53.1, shown at one decimal. A change of 3.1
    /// points; the percent `compare` returns for it (3.1 ÷ 50.0 × 100 = 6.2) is not shown.
    static let expectedArmsToLegsAToB = Expected.both(earlier: 50.0, later: 53.1, delta: 3.1, percent: 6.2,
                                                      direction: .up)
}
