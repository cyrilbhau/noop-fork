import XCTest
@testable import StrandImport

// API ASSUMED BY THESE TESTS
//
// Written before the implementation, from docs/personal/superapp/specs/stage-4.md §6.2 and §7.2.
//
//   public enum MarkerUnitConversion: Sendable, Equatable
//       case identity                                      // stored = typed
//       case multiply(Double)                              // stored = typed * f
//       case divide(Double)                                // stored = typed / d
//       case affine(subtract: Double, divideBy: Double)    // stored = (typed - s) / d
//
//   public struct MarkerUnitOption: Sendable, Equatable
//       public let label: String
//       public let conversion: MarkerUnitConversion
//       public init(label: String, conversion: MarkerUnitConversion)
//
//   public enum MarkerUnitTier: Sendable { case legacy, extended }
//
//   public enum MarkerUnitTable
//       public static let poundsPerKilogram: Double        // 2.20462
//       public static let centimetersPerInch: Double       // 2.54
//       public static func options(for key: String, tier: MarkerUnitTier) -> [MarkerUnitOption]
//       public static func toStored(_ value: Double, key: String, from label: String,
//                                   tier: MarkerUnitTier) -> Double?
//       public static func fromStored(_ value: Double, key: String, to label: String,
//                                     tier: MarkerUnitTier) -> Double?
//       public static func normalizedLabel(_ label: String) -> String
//       public static func storedValue(_ value: Double, key: String, rowUnit: String) -> Double?
//       public static func parseEntry(_ text: String, decimalSeparator: Character) -> Double?
//
// Also called, from MarkerCatalogBodyRecordTests' assumed API:
//   MarkerCatalog.builtIn, MarkerCatalog.bodyRecord, MarkerCatalog.definitions(in:),
//   MarkerCatalog.definition(for:), MarkerCatalog.scanNoteKey, MarkerDefinition.canonicalUnit.
//
// Option labels are passed to `toStored` and `fromStored` exactly as `options(for:tier:)` returns
// them. No test here relies on those two functions folding case or whitespace.

/// `MarkerUnitTable`: the conversion table of §7.2, both directions, and the entry parser of §6.2
/// (test plan §12.1).
final class MarkerUnitTableTests: XCTestCase {

    // MARK: - The table of §7.2, written out

    private typealias Option = MarkerUnitOption

    private static let lipid = Option(label: "mg/dL", conversion: .multiply(1.0 / 38.67))
    private static let pounds = Option(label: "lb", conversion: .divide(2.20462))
    private static let grams = Option(label: "g", conversion: .divide(1000))

    /// The five rows of the legacy tier: the extra option of each dual-unit marker.
    private static let legacyExtras: [String: [Option]] = [
        "total_cholesterol": [lipid],
        "ldl": [lipid],
        "hdl": [lipid],
        "triglycerides": [Option(label: "mg/dL", conversion: .multiply(1.0 / 88.57))],
        "fasting_glucose": [Option(label: "mg/dL", conversion: .multiply(1.0 / 18.0))],
    ]

    /// Every key of the extended tier that has more than its stored unit, with its extra options in
    /// the order §7.2 prints them. The micro sign is U+00B5.
    private static let extendedExtras: [String: [Option]] = {
        var t = legacyExtras
        t["hba1c"] = [Option(label: "%", conversion: .affine(subtract: 2.152, divideBy: 0.09148))]
        t["ferritin"] = [Option(label: "ng/mL", conversion: .identity)]
        t["iron"] = [Option(label: "\u{00B5}g/dL", conversion: .multiply(0.1791))]
        t["haemoglobin"] = [Option(label: "g/dL", conversion: .multiply(10))]
        t["vitamin_d"] = [Option(label: "ng/mL", conversion: .multiply(2.496))]
        t["vitamin_b12"] = [Option(label: "pg/mL", conversion: .identity),
                            Option(label: "pmol/L", conversion: .multiply(1.355))]
        t["folate"] = [Option(label: "ng/mL", conversion: .identity),
                       Option(label: "nmol/L", conversion: .divide(2.266))]
        t["tsh"] = [Option(label: "\u{00B5}IU/mL", conversion: .identity)]
        t["free_t4"] = [Option(label: "ng/dL", conversion: .multiply(12.87))]
        t["crp"] = [Option(label: "mg/dL", conversion: .multiply(10))]
        t["creatinine"] = [Option(label: "mg/dL", conversion: .multiply(88.4))]
        for key in ["alt", "ast", "ggt"] { t[key] = [Option(label: "IU/L", conversion: .identity)] }
        for key in ["sodium", "potassium"] { t[key] = [Option(label: "mEq/L", conversion: .identity)] }
        for key in ["weight", "bench_grip_kg"] { t[key] = [pounds] }
        for key in ["waist", "height"] { t[key] = [Option(label: "in", conversion: .multiply(2.54))] }
        for key in ["scan_fat_mass", "scan_lean_mass", "scan_bone_mass", "scan_fat_free_mass",
                    "scan_arms_lean_mass", "scan_arm_left_lean_mass", "scan_arm_right_lean_mass",
                    "scan_legs_lean_mass", "scan_leg_left_lean_mass", "scan_leg_right_lean_mass",
                    "scan_trunk_lean_mass"] {
            t[key] = [pounds, grams]
        }
        t["scan_visceral_fat_mass"] = [Option(label: "kg", conversion: .multiply(1000)),
                                       Option(label: "lb", conversion: .multiply(1000.0 / 2.20462))]
        for key in ["bench_dead_hang_s", "bench_plank_s", "bench_wall_sit_s"] {
            t[key] = [Option(label: "min", conversion: .multiply(60))]
        }
        return t
    }()

    // SPEC-AMBIGUITY: §6.2 says a key with a catalogue definition has its stored unit as the first
    // option, and `scan_note` has a definition whose stored unit is "". Whether that key has one
    // option labelled "" or none is not stated; a note is never converted, so no test asserts it.

    /// Every catalogue key except the scan note, whose stored unit is the empty string.
    private static var convertibleDefinitions: [MarkerDefinition] {
        MarkerCatalog.definitions(in: .withBodyRecord).filter { $0.key != "scan_note" }
    }

    /// The arithmetic of §6.2, "exactly as written", applied by the test itself.
    private func applied(_ conversion: MarkerUnitConversion, to typed: Double) -> Double {
        switch conversion {
        case .identity: return typed
        case .multiply(let f): return typed * f
        case .divide(let d): return typed / d
        case .affine(let s, let d): return (typed - s) / d
        }
    }

    /// A 64-bit linear congruential generator (Knuth's MMIX constants), written out so the same
    /// stream is reproduced on every run. Nothing here draws randomness from the system.
    private struct Generator {
        var state: UInt64
        mutating func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(state >> 33) % bound
        }
        /// A positive value with up to four decimals in `0.0001 ... 5000`.
        mutating func value() -> Double {
            Double(next(50_000_000) + 1) / 10_000
        }
    }

    private func assertBitIdentical(_ actual: Double?, _ expected: Double, _ message: String,
                                    file: StaticString = #filePath, line: UInt = #line) {
        guard let actual else {
            return XCTFail("nil, expected \(expected): \(message)", file: file, line: line)
        }
        XCTAssertEqual(actual.bitPattern, expected.bitPattern,
                       "\(actual) is not bit-identical to \(expected): \(message)", file: file, line: line)
    }

    // MARK: - Legacy tier

    /// With the laboratory-units flag off the editor must offer exactly what it offers today: the
    /// stored unit for every marker, and one extra option, mg/dL, for five of them.
    func testLegacyTierIsExactlyTheFiveMarkerSwitcher() {
        XCTAssertEqual(Self.legacyExtras.count, 5)
        XCTAssertEqual(Self.convertibleDefinitions.count, 58)
        for d in Self.convertibleDefinitions {
            let expected = [Option(label: d.canonicalUnit, conversion: .identity)] + (Self.legacyExtras[d.key] ?? [])
            XCTAssertEqual(MarkerUnitTable.options(for: d.key, tier: .legacy), expected, d.key)
        }
        // None of the extended options leaks into the legacy tier.
        XCTAssertNil(MarkerUnitTable.toStored(5.5, key: "hba1c", from: "%", tier: .legacy))
        XCTAssertNil(MarkerUnitTable.fromStored(37, key: "hba1c", to: "%", tier: .legacy))
        XCTAssertNil(MarkerUnitTable.toStored(220.5, key: "weight", from: "lb", tier: .legacy))
        XCTAssertNil(MarkerUnitTable.toStored(14, key: "haemoglobin", from: "g/dL", tier: .legacy))
        XCTAssertNil(MarkerUnitTable.toStored(80, key: "ferritin", from: "ng/mL", tier: .legacy))
        // The stored unit itself is always accepted.
        XCTAssertEqual(MarkerUnitTable.toStored(37, key: "hba1c", from: "mmol/mol", tier: .legacy), 37)
        XCTAssertEqual(MarkerUnitTable.toStored(100, key: "weight", from: "kg", tier: .legacy), 100)
    }

    /// Faults F21 and the "tidied to a division" variant of it. The old editor multiplied by
    /// `1.0 / 38.67`, `1.0 / 88.57` and `1.0 / 18.0`; a stored value must not change by one bit.
    func testLegacyConversionIsBitIdenticalToMultiplyingByTheOldFactor() {
        let factors: [(key: String, factor: Double, divisor: Double)] = [
            ("total_cholesterol", 1.0 / 38.67, 38.67),
            ("ldl", 1.0 / 38.67, 38.67),
            ("hdl", 1.0 / 38.67, 38.67),
            ("triglycerides", 1.0 / 88.57, 88.57),
            ("fasting_glucose", 1.0 / 18.0, 18.0),
        ]
        let typed: [Double] = [0.5, 7, 40, 50, 90, 100, 123.4, 150, 185, 200, 201, 220.5, 66.1386, 1000]
        for (key, factor, _) in factors {
            for x in typed {
                for tier in [MarkerUnitTier.legacy, .extended] {
                    assertBitIdentical(MarkerUnitTable.toStored(x, key: key, from: "mg/dL", tier: tier),
                                       x * factor, "\(key) \(x) mg/dL, \(tier)")
                }
            }
        }

        // Inputs at which multiplying by the reciprocal and dividing give different doubles, so a
        // conversion rewritten as a division fails here even though it is "the same number".
        let telling: [(key: String, x: Double, divisor: Double)] = [
            ("ldl", 220.5, 38.67), ("triglycerides", 123.4, 88.57), ("fasting_glucose", 150, 18.0),
        ]
        for (key, x, divisor) in telling {
            XCTAssertNotEqual((x * (1.0 / divisor)).bitPattern, (x / divisor).bitPattern,
                              "test precondition: \(x) must tell the two forms apart")
            let stored = MarkerUnitTable.toStored(x, key: key, from: "mg/dL", tier: .legacy)
            XCTAssertNotNil(stored, key)
            XCTAssertNotEqual(stored?.bitPattern, (x / divisor).bitPattern, "\(key): divided, not multiplied")
        }

        // The fixture's typed lipids and glucose (§13.5), by hand.
        XCTAssertEqual(MarkerUnitTable.toStored(100, key: "ldl", from: "mg/dL", tier: .legacy) ?? .nan,
                       2.585983966899405, accuracy: 1e-12)
        XCTAssertEqual(MarkerUnitTable.toStored(50, key: "hdl", from: "mg/dL", tier: .legacy) ?? .nan,
                       1.2929919834497026, accuracy: 1e-12)
        XCTAssertEqual(MarkerUnitTable.toStored(200, key: "total_cholesterol", from: "mg/dL", tier: .legacy) ?? .nan,
                       5.17196793379881, accuracy: 1e-12)
        XCTAssertEqual(MarkerUnitTable.toStored(150, key: "triglycerides", from: "mg/dL", tier: .legacy) ?? .nan,
                       1.693575702833917, accuracy: 1e-12)
        XCTAssertEqual(MarkerUnitTable.toStored(90, key: "fasting_glucose", from: "mg/dL", tier: .legacy) ?? .nan,
                       5.0, accuracy: 1e-12)
    }

    // MARK: - Options

    func testEveryBuiltInKeyHasItsStoredUnitFirst() {
        XCTAssertEqual(MarkerCatalog.builtIn.count, 30)
        for d in MarkerCatalog.builtIn {
            for tier in [MarkerUnitTier.legacy, .extended] {
                let options = MarkerUnitTable.options(for: d.key, tier: tier)
                XCTAssertEqual(options.first, Option(label: d.canonicalUnit, conversion: .identity),
                               "\(d.key), \(tier)")
                // Entry in the stored unit stores the number typed.
                XCTAssertEqual(MarkerUnitTable.toStored(12.5, key: d.key, from: d.canonicalUnit, tier: tier), 12.5,
                               "\(d.key), \(tier)")
                XCTAssertEqual(MarkerUnitTable.fromStored(12.5, key: d.key, to: d.canonicalUnit, tier: tier), 12.5,
                               "\(d.key), \(tier)")
                XCTAssertEqual(Set(options.map(\.label)).count, options.count, "\(d.key): a label is offered twice")
            }
        }
    }

    /// The whole extended tier, option by option: labels, order and conversions of §7.2. A marker
    /// that §7.2 lists as single-unit has exactly its stored unit.
    func testExtendedTierIsPinnedForEveryCatalogueKey() {
        XCTAssertEqual(Self.extendedExtras.count, 40)
        for key in Self.extendedExtras.keys {
            XCTAssertNotNil(MarkerCatalog.definition(for: key), "\(key) is not a catalogue key")
        }
        for d in Self.convertibleDefinitions {
            let expected = [Option(label: d.canonicalUnit, conversion: .identity)] + (Self.extendedExtras[d.key] ?? [])
            XCTAssertEqual(MarkerUnitTable.options(for: d.key, tier: .extended), expected, d.key)
        }
        // The single-unit markers §7.2 names, spelled out.
        for key in ["transferrin_saturation", "egfr", "bp_systolic", "bp_diastolic", "resting_pulse", "body_fat",
                    "scan_visceral_fat_area", "scan_android_fat_pct", "scan_gynoid_fat_pct",
                    "scan_android_gynoid_ratio", "scan_bmd", "scan_bmd_t_score", "scan_bmd_z_score",
                    "scan_rmr_lab_estimate", "bench_pushup_reps", "bench_incline_pushup_reps",
                    "bench_knee_pushup_reps", "bench_pullup_reps"] {
            XCTAssertEqual(MarkerUnitTable.options(for: key, tier: .extended).count, 1, key)
        }
    }

    func testUnknownKeyHasNoOptions() {
        for key in ["not_a_marker", "", "custom_fixture_marker", "custom_bench_fixture_carry", "scan_total_mass",
                    "LDL", "ldl "] {
            for tier in [MarkerUnitTier.legacy, .extended] {
                XCTAssertEqual(MarkerUnitTable.options(for: key, tier: tier), [], "\(key), \(tier)")
                XCTAssertNil(MarkerUnitTable.toStored(1, key: key, from: "kg", tier: tier), key)
                XCTAssertNil(MarkerUnitTable.toStored(1, key: key, from: "mg/dL", tier: tier), key)
                XCTAssertNil(MarkerUnitTable.fromStored(1, key: key, to: "kg", tier: tier), key)
            }
        }
    }

    /// A label the key does not offer converts nothing: it is never treated as the stored unit.
    func testALabelTheKeyDoesNotOfferIsNil() {
        XCTAssertNil(MarkerUnitTable.toStored(16, key: "weight", from: "stone", tier: .extended))
        XCTAssertNil(MarkerUnitTable.fromStored(100, key: "weight", to: "stone", tier: .extended))
        XCTAssertNil(MarkerUnitTable.toStored(5.5, key: "ldl", from: "%", tier: .extended))
        XCTAssertNil(MarkerUnitTable.toStored(30, key: "body_fat", from: "kg", tier: .extended))
        XCTAssertNil(MarkerUnitTable.toStored(1, key: "bench_pushup_reps", from: "min", tier: .extended))
        XCTAssertNil(MarkerUnitTable.toStored(1, key: "scan_fat_mass", from: "", tier: .extended))
        XCTAssertNil(MarkerUnitTable.toStored(1, key: "waist", from: "lb", tier: .extended))
    }

    // MARK: - HbA1c

    /// Fault F20: percent to mmol/mol is the master equation `(percent - 2.152) / 0.09148`, which
    /// has an offset. A multiplication cannot express it.
    func testHbA1cPercentToMmolPerMol() {
        // (5.5 - 2.152) / 0.09148 = 3.348 / 0.09148 = 36.59816…, the fixture row of §13.5.
        XCTAssertEqual(MarkerUnitTable.toStored(5.5, key: "hba1c", from: "%", tier: .extended) ?? .nan,
                       36.598163533012674, accuracy: 1e-9)
        // (6.5 - 2.152) / 0.09148 = 47.5295…; (7.0 - 2.152) / 0.09148 = 52.9952…
        XCTAssertEqual(MarkerUnitTable.toStored(6.5, key: "hba1c", from: "%", tier: .extended) ?? .nan,
                       47.52951464801049, accuracy: 1e-9)
        XCTAssertEqual(MarkerUnitTable.toStored(7.0, key: "hba1c", from: "%", tier: .extended) ?? .nan,
                       52.995190205509395, accuracy: 1e-9)
        // The offset itself: 2.152 % is 0 mmol/mol. A pure factor would give a positive number.
        XCTAssertEqual(MarkerUnitTable.toStored(2.152, key: "hba1c", from: "%", tier: .extended) ?? .nan,
                       0, accuracy: 1e-12)
        // Doubling the percent does not double the stored value: (11 - 2.152) / 0.09148 = 96.72…
        XCTAssertEqual(MarkerUnitTable.toStored(11.0, key: "hba1c", from: "%", tier: .extended) ?? .nan,
                       96.72059466550064, accuracy: 1e-9)
        // And back: 37 * 0.09148 + 2.152 = 5.53676.
        XCTAssertEqual(MarkerUnitTable.fromStored(37, key: "hba1c", to: "%", tier: .extended) ?? .nan,
                       5.53676, accuracy: 1e-9)
        // Typed in the stored unit, the number is kept.
        XCTAssertEqual(MarkerUnitTable.toStored(37, key: "hba1c", from: "mmol/mol", tier: .extended), 37)
    }

    /// A percentage typed at one decimal survives being stored and then shown as a whole number of
    /// mmol/mol: half a mmol/mol is 0.046 points, less than half of the last printed digit.
    func testHbA1cRoundTripsWithinDisplayPrecision() {
        for tenths in 30...200 {
            let percent = Double(tenths) / 10
            guard let stored = MarkerUnitTable.toStored(percent, key: "hba1c", from: "%", tier: .extended),
                  let exact = MarkerUnitTable.fromStored(stored, key: "hba1c", to: "%", tier: .extended),
                  let shown = MarkerUnitTable.fromStored(stored.rounded(), key: "hba1c", to: "%", tier: .extended)
            else { return XCTFail("\(percent) % did not convert") }
            XCTAssertEqual(exact, percent, accuracy: 1e-9, "\(percent) %")
            XCTAssertLessThan(abs(shown - percent), 0.05, "\(percent) % read back from whole mmol/mol")
        }
    }

    // MARK: - Both directions

    /// Every option of every catalogue key converts there and back: typed to stored to typed, and
    /// stored to typed to stored, over fixed values and a fixed-seed generated spread.
    func testEveryExtendedOptionRoundTripsBothWays() {
        var generator = Generator(state: 0x5EED_0004)
        var values: [Double] = [0.001, 0.5, 1, 5.5, 37, 100, 220.5, 1900, 10_000, -0.5, -8]
        for _ in 0..<40 { values.append(generator.value()) }

        var optionsSeen = 0
        for d in Self.convertibleDefinitions {
            let options = MarkerUnitTable.options(for: d.key, tier: .extended)
            XCTAssertFalse(options.isEmpty, d.key)
            for option in options {
                optionsSeen += 1
                for x in values {
                    guard let stored = MarkerUnitTable.toStored(x, key: d.key, from: option.label, tier: .extended),
                          let back = MarkerUnitTable.fromStored(stored, key: d.key, to: option.label, tier: .extended)
                    else { XCTFail("\(d.key) \(x) \(option.label) did not convert"); continue }
                    XCTAssertEqual(back, x, accuracy: abs(x) * 1e-9, "\(d.key) \(x) \(option.label) there and back")
                    // The forward step is the arithmetic of the option's conversion, as written.
                    XCTAssertEqual(stored.bitPattern, applied(option.conversion, to: x).bitPattern,
                                   "\(d.key) \(x) \(option.label)")

                    guard let typed = MarkerUnitTable.fromStored(x, key: d.key, to: option.label, tier: .extended),
                          let again = MarkerUnitTable.toStored(typed, key: d.key, from: option.label, tier: .extended)
                    else { XCTFail("\(d.key) stored \(x) to \(option.label) did not convert"); continue }
                    // An affine option's offset limits the relative precision near zero, so the
                    // bound has a small absolute part as well.
                    XCTAssertEqual(again, x, accuracy: abs(x) * 1e-9 + 1e-9,
                                   "\(d.key) stored \(x) via \(option.label) and back")
                }
            }
        }
        // 58 stored units and the 54 extra options of §7.2.
        XCTAssertEqual(optionsSeen, 112)
    }

    /// One hand-worked value per conversion of §7.2, in both directions.
    func testEachExtendedConversionMatchesAHandCalculation() {
        // (key, label, typed, stored): stored is the hand calculation in the comment.
        let cases: [(String, String, Double, Double)] = [
            ("iron", "\u{00B5}g/dL", 100, 17.91),                 // 100 × 0.1791
            ("haemoglobin", "g/dL", 14, 140),                     // 14 × 10
            ("vitamin_d", "ng/mL", 30, 74.88),                    // 30 × 2.496
            ("vitamin_b12", "pmol/L", 300, 406.5),                // 300 × 1.355
            ("folate", "nmol/L", 22.66, 10),                      // 22.66 ÷ 2.266
            ("free_t4", "ng/dL", 1.2, 15.444),                    // 1.2 × 12.87
            ("crp", "mg/dL", 0.5, 5),                             // 0.5 × 10
            ("creatinine", "mg/dL", 1, 88.4),                     // 1 × 88.4
            ("weight", "lb", 220.462, 100),                       // 220.462 ÷ 2.20462
            ("bench_grip_kg", "lb", 110.231, 50),                 // 110.231 ÷ 2.20462
            ("waist", "in", 40, 101.6),                           // 40 × 2.54
            ("height", "in", 70, 177.8),                          // 70 × 2.54
            ("scan_fat_mass", "g", 30_000, 30),                   // 30000 ÷ 1000
            ("scan_lean_mass", "lb", 66.1386, 30),                // 66.1386 ÷ 2.20462
            ("scan_bone_mass", "g", 3_000, 3),                    // 3000 ÷ 1000
            ("scan_trunk_lean_mass", "lb", 44.0924, 20),          // 44.0924 ÷ 2.20462
            ("scan_visceral_fat_mass", "kg", 1, 1_000),           // 1 × 1000
            ("scan_visceral_fat_mass", "lb", 2.20462, 1_000),     // 2.20462 × (1000 ÷ 2.20462)
            ("bench_dead_hang_s", "min", 1.5, 90),                // 1.5 × 60
            ("bench_plank_s", "min", 2, 120),                     // 2 × 60
            ("bench_wall_sit_s", "min", 0.5, 30),                 // 0.5 × 60
        ]
        for (key, label, typed, stored) in cases {
            XCTAssertEqual(MarkerUnitTable.toStored(typed, key: key, from: label, tier: .extended) ?? .nan,
                           stored, accuracy: stored * 1e-9, "\(typed) \(label) of \(key)")
            XCTAssertEqual(MarkerUnitTable.fromStored(stored, key: key, to: label, tier: .extended) ?? .nan,
                           typed, accuracy: typed * 1e-9, "\(stored) of \(key) as \(label)")
        }
    }

    /// Two labels for one quantity (ng/mL and µg/L, U/L and IU/L, mmol/L and mEq/L, pg/mL and ng/L,
    /// µIU/mL and mIU/L) store the number typed, bit for bit.
    func testIdentityOptionsReturnTheSameNumber() {
        let identities: [(String, String)] = [
            ("ferritin", "ng/mL"), ("vitamin_b12", "pg/mL"), ("folate", "ng/mL"), ("tsh", "\u{00B5}IU/mL"),
            ("alt", "IU/L"), ("ast", "IU/L"), ("ggt", "IU/L"), ("sodium", "mEq/L"), ("potassium", "mEq/L"),
        ]
        for (key, label) in identities {
            for x in [0.1, 2.0, 80.0, 139.0, 0.30000000000000004] {
                assertBitIdentical(MarkerUnitTable.toStored(x, key: key, from: label, tier: .extended), x,
                                   "\(key) \(label)")
                assertBitIdentical(MarkerUnitTable.fromStored(x, key: key, to: label, tier: .extended), x,
                                   "\(key) \(label)")
            }
        }
        // The stored unit of every key is an identity as well.
        for d in Self.convertibleDefinitions {
            assertBitIdentical(MarkerUnitTable.toStored(0.30000000000000004, key: d.key, from: d.canonicalUnit,
                                                        tier: .extended),
                               0.30000000000000004, d.key)
        }
        // The fixture: 80 ng/mL of ferritin is stored as 80 µg/L (§13.5).
        XCTAssertEqual(MarkerUnitTable.toStored(80, key: "ferritin", from: "ng/mL", tier: .extended), 80)
    }

    /// Fault F12. Pounds become kilograms by dividing by 2.20462, the constant and the operation the
    /// weight resolver uses, so a weight typed in pounds in a scan stores the kilograms the resolver
    /// would have computed. Multiplying by a reciprocal or by a rounded factor gives another double.
    func testPoundsUseDivisionByTheSharedConstant() {
        XCTAssertEqual(MarkerUnitTable.poundsPerKilogram, 2.20462)
        XCTAssertEqual(MarkerUnitTable.centimetersPerInch, 2.54)

        let poundKeys = ["weight", "bench_grip_kg", "scan_fat_mass", "scan_lean_mass", "scan_bone_mass",
                         "scan_fat_free_mass", "scan_arms_lean_mass", "scan_arm_left_lean_mass",
                         "scan_arm_right_lean_mass", "scan_legs_lean_mass", "scan_leg_left_lean_mass",
                         "scan_leg_right_lean_mass", "scan_trunk_lean_mass"]
        for key in poundKeys {
            for x in [220.5, 151.5, 157.2, 161.3, 100, 66.1386, 1] {
                assertBitIdentical(MarkerUnitTable.toStored(x, key: key, from: "lb", tier: .extended),
                                   x / 2.20462, "\(key) \(x) lb")
            }
        }

        // 151.5 lb is a value at which dividing and multiplying by the reciprocal differ.
        XCTAssertNotEqual((151.5 / 2.20462).bitPattern, (151.5 * (1.0 / 2.20462)).bitPattern,
                          "test precondition: 151.5 must tell the two forms apart")
        let stored = MarkerUnitTable.toStored(151.5, key: "weight", from: "lb", tier: .extended)
        XCTAssertNotNil(stored)
        XCTAssertNotEqual(stored?.bitPattern, (151.5 * (1.0 / 2.20462)).bitPattern)
        XCTAssertNotEqual(stored?.bitPattern, (151.5 * 0.4536).bitPattern)
        XCTAssertNotEqual(stored?.bitPattern, (151.5 * 0.45359237).bitPattern)

        // Variant V6: scan A's total typed as 220.5 lb is stored as 220.5 / 2.20462 kg, which is
        // 100.0172… and is shown as 100.0 kg.
        let v6 = MarkerUnitTable.toStored(220.5, key: "weight", from: "lb", tier: .extended)
        XCTAssertEqual(v6 ?? .nan, 100.01723653055856, accuracy: 1e-9)
        XCTAssertEqual(((v6 ?? .nan) * 10).rounded() / 10, 100.0)

        // Kilograms to pounds is the inverse: stored × 2.20462.
        assertBitIdentical(MarkerUnitTable.fromStored(100, key: "weight", to: "lb", tier: .extended),
                           100 * 2.20462, "100 kg in lb")
        // Inches use the shared constant by multiplication.
        assertBitIdentical(MarkerUnitTable.toStored(34.5, key: "waist", from: "in", tier: .extended),
                           34.5 * 2.54, "34.5 in")
        // Visceral fat in pounds is `typed × (1000 ÷ 2.20462)`, exactly as §7.2 writes it.
        assertBitIdentical(MarkerUnitTable.toStored(2.2, key: "scan_visceral_fat_mass", from: "lb", tier: .extended),
                           2.2 * (1000.0 / 2.20462), "2.2 lb of visceral fat")
    }

    // MARK: - Rejection

    func testNonFiniteInputIsNil() {
        let bad: [Double] = [.nan, .infinity, -.infinity, .signalingNaN]
        for d in Self.convertibleDefinitions {
            for option in MarkerUnitTable.options(for: d.key, tier: .extended) {
                for x in bad {
                    XCTAssertNil(MarkerUnitTable.toStored(x, key: d.key, from: option.label, tier: .extended),
                                 "\(d.key) \(x) \(option.label)")
                    XCTAssertNil(MarkerUnitTable.fromStored(x, key: d.key, to: option.label, tier: .extended),
                                 "\(d.key) \(x) \(option.label)")
                    XCTAssertNil(MarkerUnitTable.storedValue(x, key: d.key, rowUnit: option.label),
                                 "\(d.key) \(x) \(option.label)")
                }
            }
        }
        XCTAssertNil(MarkerUnitTable.toStored(.nan, key: "ldl", from: "mg/dL", tier: .legacy))
        XCTAssertNil(MarkerUnitTable.toStored(.infinity, key: "ldl", from: "mmol/L", tier: .legacy))

        // A finite input whose result overflows is nil too, in each direction.
        let huge = Double.greatestFiniteMagnitude
        XCTAssertNil(MarkerUnitTable.toStored(huge, key: "creatinine", from: "mg/dL", tier: .extended))
        XCTAssertNil(MarkerUnitTable.toStored(huge, key: "scan_visceral_fat_mass", from: "kg", tier: .extended))
        XCTAssertNil(MarkerUnitTable.fromStored(huge, key: "weight", to: "lb", tier: .extended))
        XCTAssertNil(MarkerUnitTable.fromStored(huge, key: "scan_fat_mass", to: "g", tier: .extended))
        XCTAssertNil(MarkerUnitTable.fromStored(huge, key: "ldl", to: "mg/dL", tier: .legacy))
        XCTAssertNil(MarkerUnitTable.storedValue(huge, key: "creatinine", rowUnit: "mg/dL"))
        // The same input through an identity stays finite and is kept.
        XCTAssertEqual(MarkerUnitTable.toStored(huge, key: "creatinine", from: "\u{00B5}mol/L", tier: .extended), huge)
    }

    // MARK: - Labels

    func testNormalizedLabelFoldsMicroSignsCaseAndSquares() {
        // Trimmed and lowercased.
        XCTAssertEqual(MarkerUnitTable.normalizedLabel("  mg/dL "), "mg/dl")
        XCTAssertEqual(MarkerUnitTable.normalizedLabel("KG"), "kg")
        XCTAssertEqual(MarkerUnitTable.normalizedLabel("kcal/day"), "kcal/day")
        XCTAssertEqual(MarkerUnitTable.normalizedLabel(""), "")
        XCTAssertEqual(MarkerUnitTable.normalizedLabel("   "), "")
        // The Greek small mu (U+03BC) folds to the micro sign (U+00B5), which stays itself.
        XCTAssertEqual(MarkerUnitTable.normalizedLabel("\u{03BC}g/L"), "\u{00B5}g/l")
        XCTAssertEqual(MarkerUnitTable.normalizedLabel("\u{00B5}g/L"), "\u{00B5}g/l")
        XCTAssertEqual(MarkerUnitTable.normalizedLabel("\u{03BC}IU/mL"), "\u{00B5}iu/ml")
        XCTAssertEqual(MarkerUnitTable.normalizedLabel("\u{03BC}mol/L"), MarkerUnitTable.normalizedLabel("\u{00B5}mol/L"))
        // "^2" and "2" after "cm" fold to the superscript two (U+00B2), which stays itself.
        XCTAssertEqual(MarkerUnitTable.normalizedLabel("cm^2"), "cm\u{00B2}")
        XCTAssertEqual(MarkerUnitTable.normalizedLabel("cm2"), "cm\u{00B2}")
        XCTAssertEqual(MarkerUnitTable.normalizedLabel("cm\u{00B2}"), "cm\u{00B2}")
        XCTAssertEqual(MarkerUnitTable.normalizedLabel("g/cm2"), "g/cm\u{00B2}")
        XCTAssertEqual(MarkerUnitTable.normalizedLabel("g/cm^2"), "g/cm\u{00B2}")
        XCTAssertEqual(MarkerUnitTable.normalizedLabel(" G/cm\u{00B2} "), "g/cm\u{00B2}")
        // SPEC-AMBIGUITY: §6.2 lists the folds without an order. This reads "CM2" as lowercased
        // first and folded second, so two spellings of one unit always normalise to one string.
        XCTAssertEqual(MarkerUnitTable.normalizedLabel("CM2"), "cm\u{00B2}")
        XCTAssertEqual(MarkerUnitTable.normalizedLabel("G/CM^2"), "g/cm\u{00B2}")
        // A "2" that does not follow "cm" is left alone.
        XCTAssertEqual(MarkerUnitTable.normalizedLabel("mL/min/1.73m\u{00B2}"), "ml/min/1.73m\u{00B2}")
        XCTAssertEqual(MarkerUnitTable.normalizedLabel("m2"), "m2")
        XCTAssertEqual(MarkerUnitTable.normalizedLabel("h2o"), "h2o")
        XCTAssertEqual(MarkerUnitTable.normalizedLabel("cm"), "cm")
        // Different units stay different.
        XCTAssertNotEqual(MarkerUnitTable.normalizedLabel("mg/dL"), MarkerUnitTable.normalizedLabel("mg/L"))
        XCTAssertNotEqual(MarkerUnitTable.normalizedLabel("kg"), MarkerUnitTable.normalizedLabel("g"))

        // Normalising is idempotent, for every label of the table and for the odd spellings above.
        var labels = ["  mg/dL ", "\u{03BC}g/L", "cm^2", "CM2", "g/cm2", "mL/min/1.73m\u{00B2}", "stone", ""]
        for d in Self.convertibleDefinitions {
            labels += MarkerUnitTable.options(for: d.key, tier: .extended).map(\.label)
        }
        for label in labels {
            let once = MarkerUnitTable.normalizedLabel(label)
            XCTAssertEqual(MarkerUnitTable.normalizedLabel(once), once, "normalising \(label.debugDescription) twice")
        }
    }

    /// Fault F17 at its source: a row whose unit the table does not know has no stored-unit value.
    /// It is not read as its raw number and it is not read as zero.
    func testStoredValueAcceptsStoredUnitAndExtendedOptionsOnly() {
        // The stored unit, however it is spelled, gives the row's own value.
        XCTAssertEqual(MarkerUnitTable.storedValue(30, key: "scan_fat_mass", rowUnit: "kg"), 30)
        XCTAssertEqual(MarkerUnitTable.storedValue(30, key: "scan_fat_mass", rowUnit: " KG "), 30)
        XCTAssertEqual(MarkerUnitTable.storedValue(80, key: "scan_visceral_fat_area", rowUnit: "cm2"), 80)
        XCTAssertEqual(MarkerUnitTable.storedValue(80, key: "scan_visceral_fat_area", rowUnit: "cm^2"), 80)
        XCTAssertEqual(MarkerUnitTable.storedValue(1.2, key: "scan_bmd", rowUnit: "g/cm2"), 1.2)
        XCTAssertEqual(MarkerUnitTable.storedValue(80, key: "ferritin", rowUnit: "\u{03BC}g/L"), 80)
        XCTAssertEqual(MarkerUnitTable.storedValue(0, key: "scan_visceral_fat_mass", rowUnit: "g"), 0)
        XCTAssertEqual(MarkerUnitTable.storedValue(-0.5, key: "scan_bmd_t_score", rowUnit: "sd"), -0.5)

        // An extended option gives the converted value, with no tier to ask for: a row written by a
        // CSV import is read the same whether or not the laboratory-units flag is on.
        XCTAssertEqual(MarkerUnitTable.storedValue(66.1386, key: "scan_fat_mass", rowUnit: "lb") ?? .nan,
                       66.1386 / 2.20462, accuracy: 1e-12)
        XCTAssertEqual(MarkerUnitTable.storedValue(66.1386, key: "scan_fat_mass", rowUnit: "LB") ?? .nan,
                       66.1386 / 2.20462, accuracy: 1e-12)
        XCTAssertEqual(MarkerUnitTable.storedValue(30_000, key: "scan_fat_mass", rowUnit: "g") ?? .nan,
                       30, accuracy: 1e-12)
        XCTAssertEqual(MarkerUnitTable.storedValue(220.5, key: "weight", rowUnit: "lb") ?? .nan,
                       220.5 / 2.20462, accuracy: 1e-12)
        XCTAssertEqual(MarkerUnitTable.storedValue(5.5, key: "hba1c", rowUnit: "%") ?? .nan,
                       36.598163533012674, accuracy: 1e-9)
        XCTAssertEqual(MarkerUnitTable.storedValue(100, key: "ldl", rowUnit: "MG/DL") ?? .nan,
                       2.585983966899405, accuracy: 1e-12)
        XCTAssertEqual(MarkerUnitTable.storedValue(1, key: "scan_visceral_fat_mass", rowUnit: "kg") ?? .nan,
                       1000, accuracy: 1e-9)
        XCTAssertEqual(MarkerUnitTable.storedValue(100, key: "iron", rowUnit: "\u{03BC}g/dL") ?? .nan,
                       17.91, accuracy: 1e-9)

        // Every option of the table is readable as a row unit and agrees with `toStored`.
        for d in Self.convertibleDefinitions {
            for option in MarkerUnitTable.options(for: d.key, tier: .extended) {
                let viaRow = MarkerUnitTable.storedValue(12.5, key: d.key, rowUnit: option.label)
                let viaEntry = MarkerUnitTable.toStored(12.5, key: d.key, from: option.label, tier: .extended)
                XCTAssertNotNil(viaRow, "\(d.key) \(option.label)")
                XCTAssertEqual(viaRow, viaEntry, "\(d.key) \(option.label)")
            }
        }

        // Any other unit is nil: variant V9's fat mass in "stone", a unit of another marker, an
        // empty unit, and a unit that only resembles the stored one.
        XCTAssertNil(MarkerUnitTable.storedValue(4.7, key: "scan_fat_mass", rowUnit: "stone"))
        XCTAssertNil(MarkerUnitTable.storedValue(16, key: "weight", rowUnit: "stone"))
        XCTAssertNil(MarkerUnitTable.storedValue(30, key: "scan_fat_mass", rowUnit: "%"))
        XCTAssertNil(MarkerUnitTable.storedValue(30, key: "scan_fat_mass", rowUnit: ""))
        XCTAssertNil(MarkerUnitTable.storedValue(30, key: "scan_fat_mass", rowUnit: "kgs"))
        XCTAssertNil(MarkerUnitTable.storedValue(30, key: "body_fat", rowUnit: "kg"))
        XCTAssertNil(MarkerUnitTable.storedValue(80, key: "scan_visceral_fat_area", rowUnit: "cm"))
        XCTAssertNil(MarkerUnitTable.storedValue(5.5, key: "ldl", rowUnit: "%"))
        XCTAssertNil(MarkerUnitTable.storedValue(1, key: "bench_pushup_reps", rowUnit: "min"))
        // SPEC-AMBIGUITY: §6.2 defines `storedValue` through "the stored unit" of the key, and a key
        // with no catalogue definition has none. This reads such a key as nil for every unit.
        XCTAssertNil(MarkerUnitTable.storedValue(30, key: "not_a_marker", rowUnit: "kg"))
    }

    // MARK: - parseEntry

    func testParseEntryAcceptsTheLocaleSeparator() {
        XCTAssertEqual(MarkerUnitTable.parseEntry("5.5", decimalSeparator: "."), 5.5)
        XCTAssertEqual(MarkerUnitTable.parseEntry("5,5", decimalSeparator: ","), 5.5)
        XCTAssertEqual(MarkerUnitTable.parseEntry("220,5", decimalSeparator: ","), 220.5)
        XCTAssertEqual(MarkerUnitTable.parseEntry("100", decimalSeparator: "."), 100)
        XCTAssertEqual(MarkerUnitTable.parseEntry("100", decimalSeparator: ","), 100)
        XCTAssertEqual(MarkerUnitTable.parseEntry("0", decimalSeparator: "."), 0)
        XCTAssertEqual(MarkerUnitTable.parseEntry("0.0", decimalSeparator: "."), 0)
        XCTAssertEqual(MarkerUnitTable.parseEntry("007", decimalSeparator: "."), 7)
        XCTAssertEqual(MarkerUnitTable.parseEntry("1.200", decimalSeparator: "."), 1.2)
        XCTAssertEqual(MarkerUnitTable.parseEntry("0,05", decimalSeparator: ","), 0.05)
        // Leading and trailing whitespace is removed.
        XCTAssertEqual(MarkerUnitTable.parseEntry("  5.5 ", decimalSeparator: "."), 5.5)
        XCTAssertEqual(MarkerUnitTable.parseEntry(" 5,5  ", decimalSeparator: ","), 5.5)
        // A separator that is neither "." nor "," (here the Arabic decimal separator U+066B) means
        // the full stop is the separator.
        XCTAssertEqual(MarkerUnitTable.parseEntry("5.5", decimalSeparator: "\u{066B}"), 5.5)
        XCTAssertNil(MarkerUnitTable.parseEntry("5,5", decimalSeparator: "\u{066B}"))
        XCTAssertNil(MarkerUnitTable.parseEntry("5\u{066B}5", decimalSeparator: "\u{066B}"))
        XCTAssertEqual(MarkerUnitTable.parseEntry("5.5", decimalSeparator: " "), 5.5)
    }

    func testParseEntryRejectsTheOtherSeparator() {
        XCTAssertNil(MarkerUnitTable.parseEntry("5,5", decimalSeparator: "."))
        XCTAssertNil(MarkerUnitTable.parseEntry("5.5", decimalSeparator: ","))
        XCTAssertNil(MarkerUnitTable.parseEntry("0,5", decimalSeparator: "."))
        XCTAssertNil(MarkerUnitTable.parseEntry("0.5", decimalSeparator: ","))
        XCTAssertNil(MarkerUnitTable.parseEntry("-5.5", decimalSeparator: ","))
        XCTAssertNil(MarkerUnitTable.parseEntry(" 100.0 ", decimalSeparator: ","))
    }

    /// Fault F23, and the rest of rule 5: `Double("nan")` and `Double("inf")` are numbers to Swift
    /// and are not numbers to an entry field.
    func testParseEntryRejectsNanInfExponentAndTwoSeparators() {
        let rejected = [
            "", " ", "   ", "nan", "NaN", "NAN", "inf", "Inf", "-inf", "infinity", "-nan",
            "1e3", "1E3", "1e-3", "5.5e0", "0x10", "0x1p3",
            "1.2.3", "1..2", "5.", ".5", ".", "5.5.", "-.5", "-",
            "+5", "--5", "5-", "- 5", "5 5", "5. 5", "1 000",
            "5.5kg", "5.5 kg", "abc", "5a", "1/2", "5%",
            "\u{0665}", "\u{0661}\u{0662}", "\u{FF15}", "5.\u{0665}",   // Arabic-Indic and full-width digits
            "\u{2212}5",                                                  // U+2212 minus sign
            "5\u{00A0}5",
        ]
        for text in rejected {
            XCTAssertNil(MarkerUnitTable.parseEntry(text, decimalSeparator: "."), text.debugDescription)
        }
        for text in ["", "nan", "inf", "1e3", "1,2,3", "5,", ",5", ",", "5,5,", "-,5", "+5", "5,5 kg"] {
            XCTAssertNil(MarkerUnitTable.parseEntry(text, decimalSeparator: ","), text.debugDescription)
        }
        // Rule 6: digits only, but too many of them to be a finite number.
        XCTAssertNil(MarkerUnitTable.parseEntry(String(repeating: "9", count: 400), decimalSeparator: "."))
        XCTAssertNil(MarkerUnitTable.parseEntry("-" + String(repeating: "9", count: 400), decimalSeparator: "."))
    }

    func testParseEntryAcceptsALeadingMinus() {
        XCTAssertEqual(MarkerUnitTable.parseEntry("-0.5", decimalSeparator: "."), -0.5)
        XCTAssertEqual(MarkerUnitTable.parseEntry("-0,5", decimalSeparator: ","), -0.5)
        XCTAssertEqual(MarkerUnitTable.parseEntry("-8", decimalSeparator: "."), -8)
        XCTAssertEqual(MarkerUnitTable.parseEntry("  -1.5 ", decimalSeparator: "."), -1.5)
        XCTAssertEqual(MarkerUnitTable.parseEntry("-0", decimalSeparator: "."), 0)
        // One minus, and only at the front.
        XCTAssertNil(MarkerUnitTable.parseEntry("--1", decimalSeparator: "."))
        XCTAssertNil(MarkerUnitTable.parseEntry("1-", decimalSeparator: "."))
        XCTAssertNil(MarkerUnitTable.parseEntry("-", decimalSeparator: "."))
        XCTAssertNil(MarkerUnitTable.parseEntry("- 1", decimalSeparator: "."))
        XCTAssertNil(MarkerUnitTable.parseEntry("+1", decimalSeparator: "."))
    }

    /// Fault F22. Nothing is guessed about thousands groups: with a full-stop separator "1,500" is
    /// neither 1.5 nor 1500, it is refused.
    func testParseEntryNeverReadsAThousandsGroup() {
        XCTAssertNil(MarkerUnitTable.parseEntry("1,500", decimalSeparator: "."))
        XCTAssertNil(MarkerUnitTable.parseEntry("1.500", decimalSeparator: ","))
        XCTAssertNil(MarkerUnitTable.parseEntry("1,500.5", decimalSeparator: "."))
        XCTAssertNil(MarkerUnitTable.parseEntry("1,500.5", decimalSeparator: ","))
        XCTAssertNil(MarkerUnitTable.parseEntry("1.500,5", decimalSeparator: ","))
        XCTAssertNil(MarkerUnitTable.parseEntry("1.500,5", decimalSeparator: "."))
        XCTAssertNil(MarkerUnitTable.parseEntry("1,000,000", decimalSeparator: "."))
        XCTAssertNil(MarkerUnitTable.parseEntry("1,000,000", decimalSeparator: ","))
        XCTAssertNil(MarkerUnitTable.parseEntry("1 500", decimalSeparator: "."))
        XCTAssertNil(MarkerUnitTable.parseEntry("1'500", decimalSeparator: "."))
        XCTAssertNil(MarkerUnitTable.parseEntry("1\u{202F}500", decimalSeparator: ","))
        // With the device's own separator the same characters are a plain decimal, by rule 3: one
        // separator between digits. That is 1.5, never 1500.
        XCTAssertEqual(MarkerUnitTable.parseEntry("1,500", decimalSeparator: ","), 1.5)
        XCTAssertEqual(MarkerUnitTable.parseEntry("1.500", decimalSeparator: "."), 1.5)
    }

    /// Every number written as digits, one separator and digits parses to the same value under
    /// either separator convention, and anything parsed is finite. Fixed-seed generated input.
    func testParseEntryAgreesAcrossSeparatorsForGeneratedNumbers() {
        var generator = Generator(state: 0x5EED_0104)
        for _ in 0..<500 {
            let whole = generator.next(100_000)
            let fractionDigits = generator.next(4)
            let negative = generator.next(4) == 0
            var fraction = ""
            for _ in 0..<fractionDigits { fraction.append(String(generator.next(10))) }
            let sign = negative ? "-" : ""
            let dotted = fraction.isEmpty ? "\(sign)\(whole)" : "\(sign)\(whole).\(fraction)"
            let comma = fraction.isEmpty ? "\(sign)\(whole)" : "\(sign)\(whole),\(fraction)"

            let expected = Double(dotted)
            XCTAssertNotNil(expected, dotted)
            let viaDot = MarkerUnitTable.parseEntry(dotted, decimalSeparator: ".")
            let viaComma = MarkerUnitTable.parseEntry(comma, decimalSeparator: ",")
            XCTAssertEqual(viaDot, expected, dotted)
            XCTAssertEqual(viaComma, expected, comma)
            XCTAssertEqual(viaDot?.isFinite, true, dotted)
            // Parsing the same text twice gives the same answer.
            XCTAssertEqual(MarkerUnitTable.parseEntry(dotted, decimalSeparator: "."), viaDot, dotted)
            if !fraction.isEmpty {
                XCTAssertNil(MarkerUnitTable.parseEntry(dotted, decimalSeparator: ","), dotted)
                XCTAssertNil(MarkerUnitTable.parseEntry(comma, decimalSeparator: "."), comma)
            }
        }
    }
}
