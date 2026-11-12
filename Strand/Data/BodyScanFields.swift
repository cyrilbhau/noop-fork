import Foundation
import StrandImport

// Stage 4 (body record), docs/personal/superapp/specs/stage-4.md §7.7: the scan fields in the order a
// report prints them, with their sections, entry units and plausibility ranges. This is the one app
// file that spells the catalogue's scan and benchmark keys (`Tools/test_body_record_single_source.py`);
// every other file reads them from here or from `MarkerCatalog`.

/// The sections of a scan, in report order.
enum BodyScanSection: String, CaseIterable {
    case wholeBody, fatDistribution, leanMassByRegion, boneDensity, energy, note

    var title: String {
        switch self {
        case .wholeBody: return String(localized: "Whole body")
        case .fatDistribution: return String(localized: "Fat distribution")
        case .leanMassByRegion: return String(localized: "Lean mass by region")
        case .boneDensity: return String(localized: "Bone density")
        case .energy: return String(localized: "Energy")
        case .note: return String(localized: "Note")
        }
    }
}

/// One figure a scan sheet asks for (§7.7). Ranges are inclusive, in the stored unit. They guard
/// against a slipped decimal point and are not a statement about any body.
struct BodyScanField: Equatable {
    let key: String
    let section: BodyScanSection
    /// The §11 field label.
    let label: String
    /// The catalogue's canonical unit; "" for the note.
    let storedUnit: String
    /// The units a figure may be typed in, the stored unit first; [] for the note.
    let entryUnits: [String]
    /// Nil for the note.
    let range: ClosedRange<Double>?
    /// The catalogue's decimals.
    let decimals: Int
    /// False for percentages and scores, whose change is shown in points or not as a percentage.
    let showsPercentChange: Bool

    /// The longest note a scan keeps, in characters.
    static let noteMaxLength = 500

    /// The 23 fields of §7.7 in report order, the note last.
    static let all: [BodyScanField] = [
        mass(MarkerCatalog.scanTotalMassKey, .wholeBody, String(localized: "Total mass"), WeighInStore.weightRangeKg,
             units: ["kg", "lb"]),
        mass("scan_fat_mass", .wholeBody, String(localized: "Fat mass"), 1...200),
        mass("scan_lean_mass", .wholeBody, String(localized: "Lean mass"), 10...150),
        mass("scan_bone_mass", .wholeBody, String(localized: "Bone mineral content"), 0.5...6),
        mass("scan_fat_free_mass", .wholeBody, String(localized: "Fat-free mass"), 10...160),
        plain(MarkerCatalog.scanBodyFatKey, .wholeBody, String(localized: "Body fat"), 1...75, percent: false),
        plain("scan_visceral_fat_mass", .fatDistribution, String(localized: "Visceral fat mass"), 0...10_000,
              units: ["g", "kg", "lb"]),
        plain("scan_visceral_fat_area", .fatDistribution, String(localized: "Visceral fat area"), 0...1_000),
        plain("scan_android_fat_pct", .fatDistribution, String(localized: "Android fat"), 1...80, percent: false),
        plain("scan_gynoid_fat_pct", .fatDistribution, String(localized: "Gynoid fat"), 1...80, percent: false),
        plain("scan_android_gynoid_ratio", .fatDistribution, String(localized: "Android to gynoid ratio"), 0.1...5),
        mass(BodyScanKeys.armsLean, .leanMassByRegion, String(localized: "Arms, total"), 1...30),
        mass(BodyScanKeys.armLeftLean, .leanMassByRegion, String(localized: "Left arm"), 0.5...15),
        mass(BodyScanKeys.armRightLean, .leanMassByRegion, String(localized: "Right arm"), 0.5...15),
        mass(BodyScanKeys.legsLean, .leanMassByRegion, String(localized: "Legs, total"), 5...60),
        mass(BodyScanKeys.legLeftLean, .leanMassByRegion, String(localized: "Left leg"), 2...30),
        mass(BodyScanKeys.legRightLean, .leanMassByRegion, String(localized: "Right leg"), 2...30),
        mass("scan_trunk_lean_mass", .leanMassByRegion, String(localized: "Trunk"), 5...80),
        plain("scan_bmd", .boneDensity, String(localized: "Bone mineral density"), 0.3...2.5),
        plain(BodyScanKeys.tScore, .boneDensity, String(localized: "T-score"), -8...8, percent: false),
        plain(BodyScanKeys.zScore, .boneDensity, String(localized: "Z-score"), -8...8, percent: false),
        plain(BodyScanKeys.rmrEstimate, .energy, String(localized: "Resting metabolic rate"), 500...5_000),
        BodyScanField(key: MarkerCatalog.scanNoteKey, section: .note, label: String(localized: "Note"), storedUnit: "",
                      entryUnits: [], range: nil, decimals: 0, showsPercentChange: false),
    ]

    private static let byKey: [String: BodyScanField] = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })

    static func field(for key: String) -> BodyScanField? { byKey[key] }

    /// A mass stored in kilograms: typed in kg, lb or g unless `units` says otherwise; shown in the
    /// unit system's mass unit.
    private static func mass(_ key: String, _ section: BodyScanSection, _ label: String,
                             _ range: ClosedRange<Double>, units: [String] = ["kg", "lb", "g"]) -> BodyScanField {
        BodyScanField(key: key, section: section, label: label, storedUnit: storedUnit(key), entryUnits: units,
                      range: range, decimals: decimals(key), showsPercentChange: true)
    }

    private static func plain(_ key: String, _ section: BodyScanSection, _ label: String,
                              _ range: ClosedRange<Double>, units: [String]? = nil,
                              percent: Bool = true) -> BodyScanField {
        let stored = storedUnit(key)
        return BodyScanField(key: key, section: section, label: label, storedUnit: stored,
                             entryUnits: units ?? [stored], range: range, decimals: decimals(key),
                             showsPercentChange: percent)
    }

    private static func storedUnit(_ key: String) -> String {
        MarkerCatalog.definition(for: key)?.canonicalUnit ?? ""
    }

    private static func decimals(_ key: String) -> Int {
        MarkerCatalog.definition(for: key)?.decimals ?? 0
    }
}

/// The scan keys other app files need by name: the derived figures' inputs, the score fields that
/// carry a sign toggle, and the laboratory's estimate with its caption.
enum BodyScanKeys {
    static let armsLean = "scan_arms_lean_mass"
    static let armLeftLean = "scan_arm_left_lean_mass"
    static let armRightLean = "scan_arm_right_lean_mass"
    static let legsLean = "scan_legs_lean_mass"
    static let legLeftLean = "scan_leg_left_lean_mass"
    static let legRightLean = "scan_leg_right_lean_mass"
    static let fatMass = "scan_fat_mass"
    static let leanMass = "scan_lean_mass"
    static let boneMass = "scan_bone_mass"
    static let fatFreeMass = "scan_fat_free_mass"
    static let androidFat = "scan_android_fat_pct"
    static let gynoidFat = "scan_gynoid_fat_pct"
    static let androidGynoidRatio = "scan_android_gynoid_ratio"
    static let tScore = "scan_bmd_t_score"
    static let zScore = "scan_bmd_z_score"
    static let rmrEstimate = "scan_rmr_lab_estimate"
}

/// Benchmark rules of §5.3 and §7.7, by stored unit, and the keys the debug demo seeds.
enum BenchmarkRules {
    /// The units a custom benchmark may be recorded in.
    static let customUnits = ["reps", "s", "kg"]

    /// The inclusive range of a benchmark in `unit`: repetitions 0 to 1000, holds 0 to 86400 s,
    /// grip 1 to 150 kg. Nil for any other unit.
    static func range(unit: String) -> ClosedRange<Double>? {
        switch unit {
        case "reps": return 0...1_000
        case "s": return 0...86_400
        case "kg": return 1...150
        default: return nil
        }
    }

    /// Repetitions are whole numbers.
    static func requiresWholeNumber(unit: String) -> Bool { unit == "reps" }

    /// A hold is typed as seconds or as minutes and seconds.
    static func acceptsDuration(unit: String) -> Bool { unit == "s" }

    #if DEBUG
    /// The fixture's benchmarks (stage-4.md §13.5), for the debug demo only.
    static let demoDeadHang = "bench_dead_hang_s"
    static let demoPushups = "bench_pushup_reps"
    #endif
}
