import XCTest
@testable import StrandImport

// API ASSUMED BY THESE TESTS
//
// Written before the implementation, from docs/personal/superapp/specs/stage-4.md §5.2, §5.3 and
// §6.1. Everything below is the API these tests call; the existing declarations are marked.
//
//   public struct MarkerDefinition                      (existing, unchanged)
//       let key: String
//       let displayName: String
//       let category: LabMarkerCategory
//       let canonicalUnit: String
//       let decimals: Int
//       let referenceTextHint: String?
//       let higherIsBetter: Bool?
//   public enum LabMarkerCategory: String               (existing, unchanged; `.imaging`, `.other`)
//
//   public enum MarkerCatalogScope: Sendable { case builtIn, withBodyRecord }
//
//   extension MarkerCatalog
//       public static let builtIn: [MarkerDefinition]                      (existing, NOT edited)
//       public static let bodyRecord: [MarkerDefinition]
//       public static let scanSource: String                  // "body-scan"
//       public static let scanTotalMassKey: String            // "weight"
//       public static let scanBodyFatKey: String              // "body_fat"
//       public static let scanNoteKey: String                 // "scan_note"
//       public static let customBenchmarkPrefix: String       // "custom_bench_"
//       public static func definitions(in scope: MarkerCatalogScope) -> [MarkerDefinition]
//       public static func definition(for key: String) -> MarkerDefinition?  (existing; now also
//                                                                             resolves `bodyRecord`)
//       public static func isScanOnlyMarker(_ key: String) -> Bool
//       public static func isBenchmark(_ key: String) -> Bool
//
// No Kotlin twin, by ruling R43 of the stage 1 specification: `testBodyRecordCatalogueIsPinned` is
// the written record of the Swift-only list (stage 4 specification §12.7).

/// The second catalogue list, `MarkerCatalog.bodyRecord`, and the helpers beside it (stage 4
/// specification §5.2, §5.3, §6.1, test plan §12.1).
final class MarkerCatalogBodyRecordTests: XCTestCase {

    // MARK: - Helpers

    /// One catalogue entry as `key|displayName|category|unit|decimals`.
    private func line(_ d: MarkerDefinition) -> String {
        "\(d.key)|\(d.displayName)|\(d.category.rawValue)|\(d.canonicalUnit)|\(d.decimals)"
    }

    /// The 30 built-in entries as they stand before stage 4, in picker order. The micro sign is
    /// U+00B5 and the superscript two is U+00B2, written as escapes so the literal cannot drift to a
    /// look-alike.
    private static let builtInLiteral: [String] = [
        "total_cholesterol|Total cholesterol|bloodPanel|mmol/L|2",
        "ldl|LDL cholesterol|bloodPanel|mmol/L|2",
        "hdl|HDL cholesterol|bloodPanel|mmol/L|2",
        "triglycerides|Triglycerides|bloodPanel|mmol/L|2",
        "fasting_glucose|Fasting glucose|bloodPanel|mmol/L|1",
        "hba1c|HbA1c|bloodPanel|mmol/mol|0",
        "ferritin|Ferritin|bloodPanel|\u{00B5}g/L|0",
        "iron|Serum iron|bloodPanel|\u{00B5}mol/L|1",
        "transferrin_saturation|Transferrin saturation|bloodPanel|%|0",
        "haemoglobin|Haemoglobin|bloodPanel|g/L|0",
        "vitamin_d|Vitamin D|bloodPanel|nmol/L|0",
        "vitamin_b12|Vitamin B12|bloodPanel|ng/L|0",
        "folate|Folate|bloodPanel|\u{00B5}g/L|1",
        "tsh|TSH|bloodPanel|mIU/L|2",
        "free_t4|Free T4|bloodPanel|pmol/L|1",
        "crp|C-reactive protein (CRP)|bloodPanel|mg/L|1",
        "egfr|eGFR|bloodPanel|mL/min/1.73m\u{00B2}|0",
        "creatinine|Creatinine|bloodPanel|\u{00B5}mol/L|0",
        "alt|ALT|bloodPanel|U/L|0",
        "ast|AST|bloodPanel|U/L|0",
        "ggt|GGT|bloodPanel|U/L|0",
        "sodium|Sodium|bloodPanel|mmol/L|0",
        "potassium|Potassium|bloodPanel|mmol/L|1",
        "bp_systolic|Blood pressure (systolic)|bloodPressure|mmHg|0",
        "bp_diastolic|Blood pressure (diastolic)|bloodPressure|mmHg|0",
        "resting_pulse|Resting pulse|bloodPressure|bpm|0",
        "weight|Weight|bodyMeasurement|kg|1",
        "body_fat|Body fat|bodyMeasurement|%|1",
        "waist|Waist circumference|bodyMeasurement|cm|1",
        "height|Height|bodyMeasurement|cm|1",
    ]

    /// The 21 scan entries of §5.2 in order.
    private static let scanLiteral: [String] = [
        "scan_fat_mass|Fat mass (scan)|imaging|kg|1",
        "scan_lean_mass|Lean mass (scan)|imaging|kg|1",
        "scan_bone_mass|Bone mineral content (scan)|imaging|kg|2",
        "scan_fat_free_mass|Fat-free mass (scan)|imaging|kg|1",
        "scan_visceral_fat_mass|Visceral fat mass (scan)|imaging|g|0",
        "scan_visceral_fat_area|Visceral fat area (scan)|imaging|cm\u{00B2}|0",
        "scan_android_fat_pct|Android fat (scan)|imaging|%|1",
        "scan_gynoid_fat_pct|Gynoid fat (scan)|imaging|%|1",
        "scan_android_gynoid_ratio|Android to gynoid ratio (scan)|imaging|ratio|2",
        "scan_arms_lean_mass|Arms lean mass, total (scan)|imaging|kg|2",
        "scan_arm_left_lean_mass|Left arm lean mass (scan)|imaging|kg|2",
        "scan_arm_right_lean_mass|Right arm lean mass (scan)|imaging|kg|2",
        "scan_legs_lean_mass|Legs lean mass, total (scan)|imaging|kg|2",
        "scan_leg_left_lean_mass|Left leg lean mass (scan)|imaging|kg|2",
        "scan_leg_right_lean_mass|Right leg lean mass (scan)|imaging|kg|2",
        "scan_trunk_lean_mass|Trunk lean mass (scan)|imaging|kg|2",
        "scan_bmd|Bone mineral density (scan)|imaging|g/cm\u{00B2}|3",
        "scan_bmd_t_score|Bone density T-score (scan)|imaging|SD|1",
        "scan_bmd_z_score|Bone density Z-score (scan)|imaging|SD|1",
        "scan_rmr_lab_estimate|Resting metabolic rate (laboratory estimate)|imaging|kcal/day|0",
        "scan_note|Scan note|imaging||0",
    ]

    /// The 8 benchmark entries of §5.3 in order.
    private static let benchmarkLiteral: [String] = [
        "bench_pushup_reps|Push-ups, most in one set|other|reps|0",
        "bench_incline_pushup_reps|Incline push-ups, most in one set|other|reps|0",
        "bench_knee_pushup_reps|Knee push-ups, most in one set|other|reps|0",
        "bench_pullup_reps|Pull-ups, most in one set|other|reps|0",
        "bench_dead_hang_s|Dead hang, longest hold|other|s|0",
        "bench_plank_s|Plank, longest hold|other|s|0",
        "bench_wall_sit_s|Wall sit, longest hold|other|s|0",
        "bench_grip_kg|Grip strength|other|kg|1",
    ]

    private static func key(of literalLine: String) -> String {
        String(literalLine.split(separator: "|", omittingEmptySubsequences: false)[0])
    }

    private static let scanKeys = scanLiteral.map(key(of:))
    private static let benchmarkKeys = benchmarkLiteral.map(key(of:))

    // MARK: - The two lists

    /// Fault F24: a body-record entry added to `builtIn` breaks the byte-identity with the Kotlin
    /// catalogue. The literal is the list as it stood before stage 4.
    func testBuiltInListIsUnchanged() {
        XCTAssertEqual(MarkerCatalog.builtIn.map(line), Self.builtInLiteral)
        XCTAssertEqual(MarkerCatalog.builtIn.count, 30)

        // The neutral "copy it from your own report" hint stays on the 26 laboratory and
        // blood-pressure entries and stays absent on the 4 body measurements.
        for d in MarkerCatalog.builtIn {
            if d.category == .bodyMeasurement {
                XCTAssertNil(d.referenceTextHint, d.key)
            } else {
                XCTAssertEqual(d.referenceTextHint, "From your own report (optional)", d.key)
            }
            XCTAssertNil(d.higherIsBetter, d.key)
        }
    }

    /// The written record of the Swift-only list: every key, display name, category, stored unit and
    /// decimal count of §5.2 and §5.3, scans first, in the specified order.
    func testBodyRecordCatalogueIsPinned() {
        XCTAssertEqual(MarkerCatalog.bodyRecord.map(line), Self.scanLiteral + Self.benchmarkLiteral)
        XCTAssertEqual(MarkerCatalog.bodyRecord.count, 29)
    }

    /// The fixed identifiers a scan is written with. Total mass and body-fat percentage reuse the
    /// existing keys, so neither variable gains a second number (ruling R41).
    func testScanConstantsArePinned() {
        XCTAssertEqual(MarkerCatalog.scanSource, "body-scan")
        XCTAssertEqual(MarkerCatalog.scanTotalMassKey, "weight")
        XCTAssertEqual(MarkerCatalog.scanBodyFatKey, "body_fat")
        XCTAssertEqual(MarkerCatalog.scanNoteKey, "scan_note")
        XCTAssertEqual(MarkerCatalog.customBenchmarkPrefix, "custom_bench_")
    }

    func testNoBodyRecordKeyCollidesWithABuiltInKey() {
        let builtIn = Set(MarkerCatalog.builtIn.map(\.key))
        let added = MarkerCatalog.bodyRecord.map(\.key)
        XCTAssertFalse(added.isEmpty, "the body-record list must exist for this test to mean anything")
        XCTAssertEqual(Set(added).count, added.count, "a key is listed twice in bodyRecord")
        XCTAssertTrue(builtIn.isDisjoint(with: added), "shared keys: \(builtIn.intersection(added).sorted())")

        // In particular the scan's total mass and body-fat percentage get no key of their own.
        for key in added {
            XCTAssertFalse(key.contains("total_mass"), key)
            XCTAssertNotEqual(key, "scan_body_fat")
            XCTAssertNotEqual(key, "scan_weight")
        }
    }

    /// The catalogue's rule stands for the new list: no reference range is suggested and no entry
    /// says which direction is better.
    func testEveryEntryHasNoReferenceHintAndNoDirection() {
        XCTAssertEqual(MarkerCatalog.bodyRecord.count, 29)
        for d in MarkerCatalog.bodyRecord {
            XCTAssertNil(d.referenceTextHint, d.key)
            XCTAssertNil(d.higherIsBetter, d.key)
        }
        for d in MarkerCatalog.definitions(in: .withBodyRecord) {
            XCTAssertNil(d.higherIsBetter, d.key)
        }
    }

    /// No new category: an older build lists rows category by category over the enum's cases, so a
    /// scan row must sit in `imaging` and a benchmark row in `other` to stay listed.
    func testScanEntriesUseTheImagingCategoryAndBenchmarksUseOther() {
        let byKey = Dictionary(uniqueKeysWithValues: MarkerCatalog.bodyRecord.map { ($0.key, $0) })
        for key in Self.scanKeys {
            XCTAssertEqual(byKey[key]?.category, .imaging, key)
        }
        for key in Self.benchmarkKeys {
            XCTAssertEqual(byKey[key]?.category, .other, key)
        }
        let used = Set(MarkerCatalog.bodyRecord.map(\.category))
        XCTAssertEqual(used, [.imaging, .other])
    }

    // MARK: - Lookups

    func testDefinitionForResolvesBothLists() {
        // Built-in keys resolve to the built-in entry, unchanged.
        for d in MarkerCatalog.builtIn {
            XCTAssertEqual(MarkerCatalog.definition(for: d.key), d, d.key)
        }
        // Body-record keys resolve too, in every scope: the lookup takes no scope.
        XCTAssertEqual(MarkerCatalog.bodyRecord.count, 29)
        for d in MarkerCatalog.bodyRecord {
            XCTAssertEqual(MarkerCatalog.definition(for: d.key), d, d.key)
        }
        XCTAssertEqual(MarkerCatalog.definition(for: "scan_bmd")?.decimals, 3)
        XCTAssertEqual(MarkerCatalog.definition(for: "scan_bmd")?.canonicalUnit, "g/cm\u{00B2}")
        XCTAssertEqual(MarkerCatalog.definition(for: "bench_grip_kg")?.canonicalUnit, "kg")
        XCTAssertEqual(MarkerCatalog.definition(for: "weight")?.category, .bodyMeasurement)

        // A custom marker, a custom benchmark and an unknown key still have no definition.
        XCTAssertNil(MarkerCatalog.definition(for: "custom_fixture_marker"))
        XCTAssertNil(MarkerCatalog.definition(for: "custom_bench_fixture_carry"))
        XCTAssertNil(MarkerCatalog.definition(for: "scan_total_mass"))
        XCTAssertNil(MarkerCatalog.definition(for: ""))
    }

    /// A scan's total mass and body-fat percentage are ordinary `weight` and `body_fat` readings. If
    /// either counted as scan-only, a manual weigh-in would be grouped as a scan.
    func testIsScanOnlyMarkerIsFalseForWeightAndBodyFat() {
        XCTAssertFalse(MarkerCatalog.isScanOnlyMarker("weight"))
        XCTAssertFalse(MarkerCatalog.isScanOnlyMarker("body_fat"))

        XCTAssertEqual(Self.scanKeys.count, 21)
        for key in Self.scanKeys {
            XCTAssertTrue(MarkerCatalog.isScanOnlyMarker(key), key)
        }
        XCTAssertTrue(MarkerCatalog.isScanOnlyMarker(MarkerCatalog.scanNoteKey))

        // True for the 21 keys and for no other key.
        for d in MarkerCatalog.builtIn {
            XCTAssertFalse(MarkerCatalog.isScanOnlyMarker(d.key), d.key)
        }
        for key in Self.benchmarkKeys + ["custom_bench_fixture_carry", "custom_scan_fat_mass",
                                         "scan_total_mass", "scan_", "scan", "", "SCAN_FAT_MASS"] {
            XCTAssertFalse(MarkerCatalog.isScanOnlyMarker(key), key)
        }
    }

    func testIsBenchmarkCoversTheEightAndTheCustomPrefix() {
        XCTAssertEqual(Self.benchmarkKeys.count, 8)
        for key in Self.benchmarkKeys {
            XCTAssertTrue(MarkerCatalog.isBenchmark(key), key)
        }
        // A custom benchmark is any key carrying the prefix (§5.3, fixture §13.5).
        XCTAssertTrue(MarkerCatalog.isBenchmark("custom_bench_fixture_carry"))
        XCTAssertTrue(MarkerCatalog.isBenchmark(MarkerCatalog.customBenchmarkPrefix + "x"))

        // Nothing else is a benchmark: not a scan marker, not a built-in marker, not another custom
        // marker, and not a key that merely starts with "bench_".
        for key in Self.scanKeys + MarkerCatalog.builtIn.map(\.key) {
            XCTAssertFalse(MarkerCatalog.isBenchmark(key), key)
        }
        for key in ["custom_fixture_marker", "custom_benchfixture", "custom_bench", "bench_fixture_reps",
                    "bench_", "x_custom_bench_y", ""] {
            XCTAssertFalse(MarkerCatalog.isBenchmark(key), key)
        }
    }

    /// Fault F25 (catalogue half): the narrow scope is exactly the built-in list, and the wide scope
    /// is the built-in list followed by the body-record list.
    func testDefinitionsInScope() {
        XCTAssertEqual(MarkerCatalog.definitions(in: .builtIn), MarkerCatalog.builtIn)
        XCTAssertEqual(MarkerCatalog.definitions(in: .builtIn).map(line), Self.builtInLiteral)

        let wide = MarkerCatalog.definitions(in: .withBodyRecord)
        XCTAssertEqual(wide, MarkerCatalog.builtIn + MarkerCatalog.bodyRecord)
        XCTAssertEqual(wide.map(line), Self.builtInLiteral + Self.scanLiteral + Self.benchmarkLiteral)
        XCTAssertEqual(wide.count, 59)
        XCTAssertEqual(Set(wide.map(\.key)).count, 59, "every key is unique across the two lists")
    }
}
