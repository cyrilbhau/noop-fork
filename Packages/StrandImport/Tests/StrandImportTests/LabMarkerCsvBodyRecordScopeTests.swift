import XCTest
@testable import StrandImport

// Stage 4 (body record), docs/personal/superapp/specs/stage-4.md §7.1 and §12.1: the markers CSV
// import's catalogue scope. `.builtIn`, the default, is exactly the import as it was; `.withBodyRecord`
// consults a second alias table after the first. No Kotlin twin, by ruling R43 of the stage 1
// specification: the drift is recorded in §12.7 (P4).
//
// Synthetic values only: the Fixture Person's scan A (§13.1).

final class LabMarkerCsvBodyRecordScopeTests: XCTestCase {

    private let file = """
        date,marker,value,unit
        2031-01-08,Total mass,100.0,kg
        2031-01-08,Fat mass (scan),30.0,kg
        2031-01-08,Visceral fat area,80,cm2
        2031-01-08,Dead hang,45,s
        2031-01-08,LDL,2.6,mmol/L
        """

    func testBuiltInScopeOutputIsUnchangedForAFileNamingScanMarkers() {
        let builtIn = LabMarkerCsvImport.parse(text: file, scope: .builtIn)
        XCTAssertEqual(builtIn, LabMarkerCsvImport.parse(text: file))
        XCTAssertEqual(Set(builtIn.rows.map(\.markerKey)),
                       ["custom_total_mass", "custom_fat_mass_scan", "custom_visceral_fat_area", "custom_dead_hang",
                        "ldl"])
        XCTAssertFalse(builtIn.rows.contains { MarkerCatalog.isScanOnlyMarker($0.markerKey) })
    }

    func testDefaultScopeIsBuiltIn() {
        XCTAssertEqual(LabMarkerCsvImport.parse(text: file), LabMarkerCsvImport.parse(text: file, scope: .builtIn))
        XCTAssertEqual(LabMarkerCsvImport.parse(data: Data(file.utf8)),
                       LabMarkerCsvImport.parse(data: Data(file.utf8), scope: .builtIn))
        XCTAssertNotEqual(LabMarkerCsvImport.parse(text: file),
                          LabMarkerCsvImport.parse(text: file, scope: .withBodyRecord))
    }

    func testEveryBodyRecordKeyRoundTripsInTheWideScope() {
        for definition in MarkerCatalog.bodyRecord {
            XCTAssertEqual(LabMarkerCsvImport.resolveMarker(definition.key, scope: .withBodyRecord).key,
                           definition.key, definition.key)
        }
    }

    func testEveryBodyRecordDisplayNameRoundTripsInTheWideScope() {
        for definition in MarkerCatalog.bodyRecord {
            XCTAssertEqual(LabMarkerCsvImport.resolveMarker(definition.displayName, scope: .withBodyRecord).key,
                           definition.key, definition.displayName)
        }
    }

    /// One assertion per row of §7.1.
    func testEveryAliasOfTheSecondTableResolves() {
        let rows: [(String, String)] = [
            ("total_mass", "weight"), ("total_body_mass", "weight"), ("scan_total_mass", "weight"),
            ("scan_body_fat", "body_fat"), ("body_fat_scan", "body_fat"), ("total_body_fat_pct", "body_fat"),
            ("fat_mass", "scan_fat_mass"), ("total_fat_mass", "scan_fat_mass"),
            ("lean_tissue_mass", "scan_lean_mass"), ("lean_soft_tissue_mass", "scan_lean_mass"),
            ("lean_mass_scan", "scan_lean_mass"),
            ("bmc", "scan_bone_mass"), ("bone_mineral_content", "scan_bone_mass"), ("bone_mass", "scan_bone_mass"),
            ("fat_free_mass", "scan_fat_free_mass"), ("ffm", "scan_fat_free_mass"),
            ("visceral_fat_mass", "scan_visceral_fat_mass"), ("vat_mass", "scan_visceral_fat_mass"),
            ("visceral_fat_area", "scan_visceral_fat_area"), ("vat_area", "scan_visceral_fat_area"),
            ("android_fat", "scan_android_fat_pct"), ("android_fat_pct", "scan_android_fat_pct"),
            ("gynoid_fat", "scan_gynoid_fat_pct"), ("gynoid_fat_pct", "scan_gynoid_fat_pct"),
            ("android_gynoid_ratio", "scan_android_gynoid_ratio"), ("a_g_ratio", "scan_android_gynoid_ratio"),
            ("ag_ratio", "scan_android_gynoid_ratio"),
            ("arms_lean_mass", "scan_arms_lean_mass"), ("arms_lean", "scan_arms_lean_mass"),
            ("left_arm_lean_mass", "scan_arm_left_lean_mass"), ("left_arm_lean", "scan_arm_left_lean_mass"),
            ("right_arm_lean_mass", "scan_arm_right_lean_mass"), ("right_arm_lean", "scan_arm_right_lean_mass"),
            ("legs_lean_mass", "scan_legs_lean_mass"), ("legs_lean", "scan_legs_lean_mass"),
            ("left_leg_lean_mass", "scan_leg_left_lean_mass"), ("left_leg_lean", "scan_leg_left_lean_mass"),
            ("right_leg_lean_mass", "scan_leg_right_lean_mass"), ("right_leg_lean", "scan_leg_right_lean_mass"),
            ("trunk_lean_mass", "scan_trunk_lean_mass"), ("trunk_lean", "scan_trunk_lean_mass"),
            ("bmd", "scan_bmd"), ("bone_mineral_density", "scan_bmd"),
            ("t_score", "scan_bmd_t_score"), ("z_score", "scan_bmd_z_score"),
            ("rmr", "scan_rmr_lab_estimate"), ("resting_metabolic_rate", "scan_rmr_lab_estimate"),
            ("push_ups", "bench_pushup_reps"), ("pushups", "bench_pushup_reps"),
            ("incline_push_ups", "bench_incline_pushup_reps"), ("incline_pushups", "bench_incline_pushup_reps"),
            ("knee_push_ups", "bench_knee_pushup_reps"), ("knee_pushups", "bench_knee_pushup_reps"),
            ("pull_ups", "bench_pullup_reps"), ("pullups", "bench_pullup_reps"),
            ("dead_hang", "bench_dead_hang_s"), ("plank", "bench_plank_s"), ("wall_sit", "bench_wall_sit_s"),
            ("grip_strength", "bench_grip_kg"),
        ]
        for (alias, key) in rows {
            XCTAssertEqual(LabMarkerCsvImport.resolveMarker(alias, scope: .withBodyRecord).key, key, alias)
        }
    }

    func testTotalMassAliasResolvesToWeightOnlyInTheWideScope() {
        XCTAssertEqual(LabMarkerCsvImport.resolveMarker("Total mass", scope: .withBodyRecord).key, "weight")
        XCTAssertEqual(LabMarkerCsvImport.resolveMarker("Total mass").key, "custom_total_mass")
    }

    func testLeanMassIsNotAnAlias() {
        XCTAssertEqual(LabMarkerCsvImport.resolveMarker("Lean mass", scope: .withBodyRecord).key, "custom_lean_mass")
        XCTAssertNil(LabMarkerCsvImport.bodyRecordAliasTable["lean_mass"])
    }

    func testNoSecondTableKeyShadowsAFirstTableKey() {
        let shadowed = Set(LabMarkerCsvImport.bodyRecordAliasTable.keys).intersection(LabMarkerCsvImport.builtInAliasKeys)
        XCTAssertEqual(shadowed, [])
    }

    func testUnitsStayVerbatimInTheWideScope() {
        let wide = LabMarkerCsvImport.parse(text: file, scope: .withBodyRecord)
        XCTAssertEqual(wide.rows.first { $0.markerKey == "scan_visceral_fat_area" }?.unit, "cm2")
        XCTAssertEqual(wide.rows.first { $0.markerKey == "weight" }?.unit, "kg")
        XCTAssertEqual(wide.rows.first { $0.markerKey == "scan_fat_mass" }?.category, .imaging)
        XCTAssertEqual(wide.rows.first { $0.markerKey == "bench_dead_hang_s" }?.category, .other)
        XCTAssertEqual(wide.customMarkerKeys, [])
    }

    func testWhoopBiomarkerParserStillUsesTheBuiltInScope() {
        XCTAssertEqual(LabMarkerCsvImport.resolveMarker("Fat mass (scan)").key, "custom_fat_mass_scan")
        XCTAssertEqual(LabMarkerCsvImport.resolveMarker("Fat mass (scan)", scope: .builtIn).key,
                       "custom_fat_mass_scan")
    }
}
