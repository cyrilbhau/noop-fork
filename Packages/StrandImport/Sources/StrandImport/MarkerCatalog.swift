import Foundation

// MARK: - Marker dictionary (non-diagnostic)
//
// MarkerCatalog.swift — a small dictionary of common, NON-DIAGNOSTIC marker
// definitions so the user can pick a marker by name (with a sensible canonical unit
// and decimal precision prefilled) instead of typing everything free-hand.
//
// Per the Health Records design spec (2026-06-19-v5-health-records-design.md,
// §"New" and §"Non-clinical / legal framing"):
//   - This ships NO reference-range tables. `referenceTextHint` is a neutral
//     placeholder prompting the user to copy the range FROM THEIR OWN REPORT — NOOP
//     never defines, computes, or asserts a normal range.
//   - `higherIsBetter` is intentionally `nil` for every entry: NOOP makes no value
//     judgement about a marker's direction. The field exists only so a future
//     descriptive sparkline could phrase a trend, never a clinical verdict.
//   - The catalog is NOT a gate: a user can always add a custom marker (free name +
//     unit), so the store is never limited by this dictionary.
//
// Pure data — no DB, no I/O. Mirrors the flat, deterministic style of the other
// StrandImport model files.

/// A non-diagnostic marker definition: how to label and format one marker the user
/// chooses from the picker. Carries NO clinical thresholds.
public struct MarkerDefinition: Sendable, Equatable, Codable {
    /// Stable key stored on every `LabMarker` (e.g. `"ldl"`, `"bp_systolic"`).
    public let key: String
    /// Human display name (e.g. `"LDL cholesterol"`).
    public let displayName: String
    /// Organisational category for grouping in the Lab Book.
    public let category: LabMarkerCategory
    /// Canonical unit prefilled in the editor (e.g. `"mmol/L"`, `"mmHg"`).
    public let canonicalUnit: String
    /// How many decimal places to show for this marker's values.
    public let decimals: Int
    /// Neutral placeholder prompting the user to copy the range from their own
    /// report. NOT a shipped reference range (see file header). `nil` where a range
    /// makes no sense (e.g. body measurements, notes).
    public let referenceTextHint: String?
    /// Direction hint — ALWAYS `nil` (NOOP makes no value judgement). Present only as
    /// a deliberate, documented placeholder so no caller infers a default of `true`.
    public let higherIsBetter: Bool?

    public init(
        key: String,
        displayName: String,
        category: LabMarkerCategory,
        canonicalUnit: String,
        decimals: Int,
        referenceTextHint: String? = nil,
        higherIsBetter: Bool? = nil
    ) {
        self.key = key
        self.displayName = displayName
        self.category = category
        self.canonicalUnit = canonicalUnit
        self.decimals = decimals
        self.referenceTextHint = referenceTextHint
        self.higherIsBetter = higherIsBetter
    }
}

/// The built-in, non-diagnostic marker dictionary. Extensible at runtime via custom
/// markers — see `custom(key:displayName:unit:)`.
public enum MarkerCatalog {

    /// A neutral hint shown in the range field — the user copies their own report's
    /// range here; NOOP ships none.
    private static let fromReport = "From your own report (optional)"

    /// ~30 common markers across the categories. Order is the suggested picker order.
    /// Reference hints are neutral prompts only; `higherIsBetter` is `nil` everywhere.
    public static let builtIn: [MarkerDefinition] = [
        // Lipids (blood panel)
        .init(key: "total_cholesterol", displayName: "Total cholesterol", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "ldl", displayName: "LDL cholesterol", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "hdl", displayName: "HDL cholesterol", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "triglycerides", displayName: "Triglycerides", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 2, referenceTextHint: fromReport),
        // Glucose
        .init(key: "fasting_glucose", displayName: "Fasting glucose", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 1, referenceTextHint: fromReport),
        .init(key: "hba1c", displayName: "HbA1c", category: .bloodPanel, canonicalUnit: "mmol/mol", decimals: 0, referenceTextHint: fromReport),
        // Iron studies
        .init(key: "ferritin", displayName: "Ferritin", category: .bloodPanel, canonicalUnit: "µg/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "iron", displayName: "Serum iron", category: .bloodPanel, canonicalUnit: "µmol/L", decimals: 1, referenceTextHint: fromReport),
        .init(key: "transferrin_saturation", displayName: "Transferrin saturation", category: .bloodPanel, canonicalUnit: "%", decimals: 0, referenceTextHint: fromReport),
        .init(key: "haemoglobin", displayName: "Haemoglobin", category: .bloodPanel, canonicalUnit: "g/L", decimals: 0, referenceTextHint: fromReport),
        // Vitamins
        .init(key: "vitamin_d", displayName: "Vitamin D", category: .bloodPanel, canonicalUnit: "nmol/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "vitamin_b12", displayName: "Vitamin B12", category: .bloodPanel, canonicalUnit: "ng/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "folate", displayName: "Folate", category: .bloodPanel, canonicalUnit: "µg/L", decimals: 1, referenceTextHint: fromReport),
        // Thyroid
        .init(key: "tsh", displayName: "TSH", category: .bloodPanel, canonicalUnit: "mIU/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "free_t4", displayName: "Free T4", category: .bloodPanel, canonicalUnit: "pmol/L", decimals: 1, referenceTextHint: fromReport),
        // Inflammation
        .init(key: "crp", displayName: "C-reactive protein (CRP)", category: .bloodPanel, canonicalUnit: "mg/L", decimals: 1, referenceTextHint: fromReport),
        // Kidney
        .init(key: "egfr", displayName: "eGFR", category: .bloodPanel, canonicalUnit: "mL/min/1.73m²", decimals: 0, referenceTextHint: fromReport),
        .init(key: "creatinine", displayName: "Creatinine", category: .bloodPanel, canonicalUnit: "µmol/L", decimals: 0, referenceTextHint: fromReport),
        // Liver
        .init(key: "alt", displayName: "ALT", category: .bloodPanel, canonicalUnit: "U/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "ast", displayName: "AST", category: .bloodPanel, canonicalUnit: "U/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "ggt", displayName: "GGT", category: .bloodPanel, canonicalUnit: "U/L", decimals: 0, referenceTextHint: fromReport),
        // Electrolytes
        .init(key: "sodium", displayName: "Sodium", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "potassium", displayName: "Potassium", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 1, referenceTextHint: fromReport),
        // Blood pressure (the paired marker — see LabBookProjection.bpSystolicKey/bpDiastolicKey)
        .init(key: "bp_systolic", displayName: "Blood pressure (systolic)", category: .bloodPressure, canonicalUnit: "mmHg", decimals: 0, referenceTextHint: fromReport),
        .init(key: "bp_diastolic", displayName: "Blood pressure (diastolic)", category: .bloodPressure, canonicalUnit: "mmHg", decimals: 0, referenceTextHint: fromReport),
        .init(key: "resting_pulse", displayName: "Resting pulse", category: .bloodPressure, canonicalUnit: "bpm", decimals: 0, referenceTextHint: fromReport),
        // Body measurements
        .init(key: "weight", displayName: "Weight", category: .bodyMeasurement, canonicalUnit: "kg", decimals: 1),
        .init(key: "body_fat", displayName: "Body fat", category: .bodyMeasurement, canonicalUnit: "%", decimals: 1),
        .init(key: "waist", displayName: "Waist circumference", category: .bodyMeasurement, canonicalUnit: "cm", decimals: 1),
        .init(key: "height", displayName: "Height", category: .bodyMeasurement, canonicalUnit: "cm", decimals: 1),
    ]

    /// Fast lookup by key. Built once from `builtIn`.
    private static let byKey: [String: MarkerDefinition] = {
        var m: [String: MarkerDefinition] = [:]
        for d in builtIn { m[d.key] = d }
        return m
    }()

    /// The catalogue definition for `key`, or `nil` if it's a custom marker. `builtIn` is consulted
    /// first and `bodyRecord` second, in every scope (stage 4 specification §6.1).
    public static func definition(for key: String) -> MarkerDefinition? {
        byKey[key] ?? bodyRecordByKey[key]
    }

    /// Build a definition for a user-added custom marker. Categorised as `.other`
    /// with no reference hint and no direction judgement — the store is never gated
    /// by the built-in dictionary.
    public static func custom(key: String, displayName: String, unit: String, decimals: Int = 1) -> MarkerDefinition {
        MarkerDefinition(
            key: key,
            displayName: displayName,
            category: .other,
            canonicalUnit: unit,
            decimals: decimals,
            referenceTextHint: nil,
            higherIsBetter: nil
        )
    }
}

// MARK: - Body record (stage 4)
//
// The second catalogue list: the figures a generic whole-body composition report can print and a
// generic set of bodyweight and grip benchmarks (stage 4 specification §5.2, §5.3, §6.1). It is a
// separate list and a separate scope so that `builtIn` stays byte-identical to the Kotlin catalogue.
// Not mirrored on Android, by the owner's decision (ruling R43 of the stage 1 specification).
//
// A scan's total mass and body-fat percentage have NO entry here: they are ordinary `weight` and
// `body_fat` readings, so neither variable gains a second number (ruling R41).

/// Which catalogue lists a name lookup may resolve against.
/// No Kotlin twin, by ruling R43 of the stage 1 specification.
public enum MarkerCatalogScope: Sendable {
    /// The 30 built-in markers only. Byte-identical to the Kotlin catalogue.
    case builtIn
    /// The built-in markers and `MarkerCatalog.bodyRecord`.
    case withBodyRecord
}

extension MarkerCatalog {

    /// The 21 scan markers of §5.2, in the order a report prints them. Category `imaging`: an older
    /// build lists rows category by category over the enum's cases, so no new category is added.
    private static let scanMarkers: [MarkerDefinition] = [
        .init(key: "scan_fat_mass", displayName: "Fat mass (scan)", category: .imaging, canonicalUnit: "kg", decimals: 1),
        .init(key: "scan_lean_mass", displayName: "Lean mass (scan)", category: .imaging, canonicalUnit: "kg", decimals: 1),
        .init(key: "scan_bone_mass", displayName: "Bone mineral content (scan)", category: .imaging, canonicalUnit: "kg", decimals: 2),
        .init(key: "scan_fat_free_mass", displayName: "Fat-free mass (scan)", category: .imaging, canonicalUnit: "kg", decimals: 1),
        .init(key: "scan_visceral_fat_mass", displayName: "Visceral fat mass (scan)", category: .imaging, canonicalUnit: "g", decimals: 0),
        .init(key: "scan_visceral_fat_area", displayName: "Visceral fat area (scan)", category: .imaging, canonicalUnit: "cm\u{00B2}", decimals: 0),
        .init(key: "scan_android_fat_pct", displayName: "Android fat (scan)", category: .imaging, canonicalUnit: "%", decimals: 1),
        .init(key: "scan_gynoid_fat_pct", displayName: "Gynoid fat (scan)", category: .imaging, canonicalUnit: "%", decimals: 1),
        .init(key: "scan_android_gynoid_ratio", displayName: "Android to gynoid ratio (scan)", category: .imaging, canonicalUnit: "ratio", decimals: 2),
        .init(key: "scan_arms_lean_mass", displayName: "Arms lean mass, total (scan)", category: .imaging, canonicalUnit: "kg", decimals: 2),
        .init(key: "scan_arm_left_lean_mass", displayName: "Left arm lean mass (scan)", category: .imaging, canonicalUnit: "kg", decimals: 2),
        .init(key: "scan_arm_right_lean_mass", displayName: "Right arm lean mass (scan)", category: .imaging, canonicalUnit: "kg", decimals: 2),
        .init(key: "scan_legs_lean_mass", displayName: "Legs lean mass, total (scan)", category: .imaging, canonicalUnit: "kg", decimals: 2),
        .init(key: "scan_leg_left_lean_mass", displayName: "Left leg lean mass (scan)", category: .imaging, canonicalUnit: "kg", decimals: 2),
        .init(key: "scan_leg_right_lean_mass", displayName: "Right leg lean mass (scan)", category: .imaging, canonicalUnit: "kg", decimals: 2),
        .init(key: "scan_trunk_lean_mass", displayName: "Trunk lean mass (scan)", category: .imaging, canonicalUnit: "kg", decimals: 2),
        .init(key: "scan_bmd", displayName: "Bone mineral density (scan)", category: .imaging, canonicalUnit: "g/cm\u{00B2}", decimals: 3),
        .init(key: "scan_bmd_t_score", displayName: "Bone density T-score (scan)", category: .imaging, canonicalUnit: "SD", decimals: 1),
        .init(key: "scan_bmd_z_score", displayName: "Bone density Z-score (scan)", category: .imaging, canonicalUnit: "SD", decimals: 1),
        .init(key: "scan_rmr_lab_estimate", displayName: "Resting metabolic rate (laboratory estimate)", category: .imaging, canonicalUnit: "kcal/day", decimals: 0),
        .init(key: "scan_note", displayName: "Scan note", category: .imaging, canonicalUnit: "", decimals: 0),
    ]

    /// The 8 benchmark markers of §5.3. Category `other`, for the same reason as above.
    private static let benchmarkMarkers: [MarkerDefinition] = [
        .init(key: "bench_pushup_reps", displayName: "Push-ups, most in one set", category: .other, canonicalUnit: "reps", decimals: 0),
        .init(key: "bench_incline_pushup_reps", displayName: "Incline push-ups, most in one set", category: .other, canonicalUnit: "reps", decimals: 0),
        .init(key: "bench_knee_pushup_reps", displayName: "Knee push-ups, most in one set", category: .other, canonicalUnit: "reps", decimals: 0),
        .init(key: "bench_pullup_reps", displayName: "Pull-ups, most in one set", category: .other, canonicalUnit: "reps", decimals: 0),
        .init(key: "bench_dead_hang_s", displayName: "Dead hang, longest hold", category: .other, canonicalUnit: "s", decimals: 0),
        .init(key: "bench_plank_s", displayName: "Plank, longest hold", category: .other, canonicalUnit: "s", decimals: 0),
        .init(key: "bench_wall_sit_s", displayName: "Wall sit, longest hold", category: .other, canonicalUnit: "s", decimals: 0),
        .init(key: "bench_grip_kg", displayName: "Grip strength", category: .other, canonicalUnit: "kg", decimals: 1),
    ]

    /// Scan and benchmark markers (stage 4 specification §5.2, §5.3), in that order. No reference
    /// hint and no direction on any entry.
    /// Not updated on Android, by the owner's decision (ruling R43).
    public static let bodyRecord: [MarkerDefinition] = scanMarkers + benchmarkMarkers

    /// The `source` column of every row a scan sheet writes.
    public static let scanSource = "body-scan"
    /// The key a scan's total mass is stored under: the ordinary weight reading (ruling R41).
    public static let scanTotalMassKey = "weight"
    /// The key a scan's body-fat percentage is stored under: the ordinary body-fat reading (R41).
    public static let scanBodyFatKey = "body_fat"
    /// The key of a scan's note row (nil `value`, the note in `valueText`).
    public static let scanNoteKey = "scan_note"
    /// The prefix of every custom benchmark key, as `LabMarkerCsvImport.customKey("bench " + name)`
    /// produces it.
    public static let customBenchmarkPrefix = "custom_bench_"

    /// Fast lookup by key. Built once from `bodyRecord`.
    fileprivate static let bodyRecordByKey: [String: MarkerDefinition] = {
        var m: [String: MarkerDefinition] = [:]
        for d in bodyRecord { m[d.key] = d }
        return m
    }()

    private static let scanOnlyKeys: Set<String> = Set(scanMarkers.map(\.key))
    private static let benchmarkKeys: Set<String> = Set(benchmarkMarkers.map(\.key))

    /// `builtIn`, or `builtIn + bodyRecord`.
    public static func definitions(in scope: MarkerCatalogScope) -> [MarkerDefinition] {
        switch scope {
        case .builtIn: return builtIn
        case .withBodyRecord: return builtIn + bodyRecord
        }
    }

    /// True for the 21 keys of §5.2 and for no other key. False for `weight` and `body_fat`: a
    /// manual weigh-in must never be grouped as a scan.
    public static func isScanOnlyMarker(_ key: String) -> Bool {
        scanOnlyKeys.contains(key)
    }

    /// True for the 8 keys of §5.3 and for any key with the prefix `custom_bench_`.
    public static func isBenchmark(_ key: String) -> Bool {
        benchmarkKeys.contains(key) || key.hasPrefix(customBenchmarkPrefix)
    }
}
