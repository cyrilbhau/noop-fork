import Foundation

// MARK: - Marker unit table (stage 4 specification §6.2, §7.2)
//
// MarkerUnitTable.swift — the units a report may print a catalogue marker in, and how a value typed
// in one of them becomes the stored one. It replaces the multiplicative factor table of the Lab Book
// editor, which could not express percent to mmol/mol for HbA1c (an offset, not a factor).
//
// PURE. No store, no clock, no locale lookup: the decimal separator arrives as an argument. Nothing
// here throws or traps, and no function returns NaN or infinity: a value that cannot be converted is
// `nil`, never zero and never the raw number.
//
// The table states conversions only. It ships no reference range and makes no judgement about any
// value (see the header of MarkerCatalog.swift).

/// How a typed value becomes the stored one. The arithmetic is exactly as written.
/// No Kotlin twin, by ruling R43 of the stage 1 specification.
public enum MarkerUnitConversion: Sendable, Equatable {
    /// stored = typed
    case identity
    /// stored = typed * f
    case multiply(Double)
    /// stored = typed / d
    case divide(Double)
    /// stored = (typed - s) / d
    case affine(subtract: Double, divideBy: Double)

    /// The stored value for a typed one. May be non-finite; callers check.
    fileprivate func toStored(_ typed: Double) -> Double {
        switch self {
        case .identity: return typed
        case .multiply(let f): return typed * f
        case .divide(let d): return typed / d
        case .affine(let s, let d): return (typed - s) / d
        }
    }

    /// The inverse: the typed-unit value for a stored one. May be non-finite; callers check.
    fileprivate func fromStored(_ stored: Double) -> Double {
        switch self {
        case .identity: return stored
        case .multiply(let f): return stored / f
        case .divide(let d): return stored * d
        case .affine(let s, let d): return stored * d + s
        }
    }
}

/// One unit a marker can be entered in.
/// No Kotlin twin, by ruling R43 of the stage 1 specification.
public struct MarkerUnitOption: Sendable, Equatable {
    /// The unit as a report prints it, e.g. "mg/dL", "%".
    public let label: String
    /// How a value typed in this unit becomes the stored one.
    public let conversion: MarkerUnitConversion

    public init(label: String, conversion: MarkerUnitConversion) {
        self.label = label
        self.conversion = conversion
    }
}

/// Which set of options the editor offers.
/// No Kotlin twin, by ruling R43 of the stage 1 specification.
public enum MarkerUnitTier: Sendable {
    /// Exactly the switcher that existed before stage 4: five markers, one extra option each.
    case legacy
    /// Every option of §7.2.
    case extended
}

/// The unit options of every catalogue marker and the conversions between them.
/// No Kotlin twin, by ruling R43 of the stage 1 specification.
public enum MarkerUnitTable {
    /// The constant and the operation (division) the weight resolver uses, so a weight typed in
    /// pounds in any sheet stores the kilograms the resolver would have computed.
    public static let poundsPerKilogram = 2.20462
    /// The constant the waist resolver multiplies inches by.
    public static let centimetersPerInch = 2.54

    // MARK: The table

    /// The legacy rows, bit-identical to the old editor's factors: it multiplied by `1.0 / 38.67`,
    /// `1.0 / 88.57` and `1.0 / 18.0`. Written as multiplications by the reciprocal on purpose:
    /// dividing gives a different double for some inputs, and a stored value must not move.
    private static let legacyExtras: [String: [MarkerUnitOption]] = {
        let lipid = MarkerUnitOption(label: "mg/dL", conversion: .multiply(1.0 / 38.67))
        return [
            "total_cholesterol": [lipid],
            "ldl": [lipid],
            "hdl": [lipid],
            "triglycerides": [MarkerUnitOption(label: "mg/dL", conversion: .multiply(1.0 / 88.57))],
            "fasting_glucose": [MarkerUnitOption(label: "mg/dL", conversion: .multiply(1.0 / 18.0))],
        ]
    }()

    /// The extended rows of §7.2: the legacy rows plus every other extra option, in printed order.
    /// The micro sign is U+00B5, as in the catalogue's stored units.
    private static let extendedExtras: [String: [MarkerUnitOption]] = {
        typealias O = MarkerUnitOption
        var t = legacyExtras
        // HbA1c: the published master equation, percent = 0.09148 × mmol/mol + 2.152.
        t["hba1c"] = [O(label: "%", conversion: .affine(subtract: 2.152, divideBy: 0.09148))]
        t["ferritin"] = [O(label: "ng/mL", conversion: .identity)]
        t["iron"] = [O(label: "\u{00B5}g/dL", conversion: .multiply(0.1791))]
        t["haemoglobin"] = [O(label: "g/dL", conversion: .multiply(10))]
        t["vitamin_d"] = [O(label: "ng/mL", conversion: .multiply(2.496))]
        t["vitamin_b12"] = [O(label: "pg/mL", conversion: .identity),
                            O(label: "pmol/L", conversion: .multiply(1.355))]
        t["folate"] = [O(label: "ng/mL", conversion: .identity),
                       O(label: "nmol/L", conversion: .divide(2.266))]
        t["tsh"] = [O(label: "\u{00B5}IU/mL", conversion: .identity)]
        t["free_t4"] = [O(label: "ng/dL", conversion: .multiply(12.87))]
        t["crp"] = [O(label: "mg/dL", conversion: .multiply(10))]
        t["creatinine"] = [O(label: "mg/dL", conversion: .multiply(88.4))]
        for key in ["alt", "ast", "ggt"] { t[key] = [O(label: "IU/L", conversion: .identity)] }
        for key in ["sodium", "potassium"] { t[key] = [O(label: "mEq/L", conversion: .identity)] }

        let pounds = O(label: "lb", conversion: .divide(poundsPerKilogram))
        for key in ["weight", "bench_grip_kg"] { t[key] = [pounds] }
        for key in ["waist", "height"] { t[key] = [O(label: "in", conversion: .multiply(centimetersPerInch))] }
        let grams = O(label: "g", conversion: .divide(1000))
        for key in ["scan_fat_mass", "scan_lean_mass", "scan_bone_mass", "scan_fat_free_mass",
                    "scan_arms_lean_mass", "scan_arm_left_lean_mass", "scan_arm_right_lean_mass",
                    "scan_legs_lean_mass", "scan_leg_left_lean_mass", "scan_leg_right_lean_mass",
                    "scan_trunk_lean_mass"] {
            t[key] = [pounds, grams]
        }
        t["scan_visceral_fat_mass"] = [O(label: "kg", conversion: .multiply(1000)),
                                       O(label: "lb", conversion: .multiply(1000.0 / poundsPerKilogram))]
        for key in ["bench_dead_hang_s", "bench_plank_s", "bench_wall_sit_s"] {
            t[key] = [O(label: "min", conversion: .multiply(60))]
        }
        return t
    }()

    // MARK: Options

    /// The options for a catalogue key, the stored unit first with `.identity`. A key with no
    /// catalogue definition has no options (empty array).
    public static func options(for key: String, tier: MarkerUnitTier) -> [MarkerUnitOption] {
        guard let definition = MarkerCatalog.definition(for: key) else { return [] }
        // SPEC-NOTE: §6.2 gives every key with a catalogue definition its stored unit as the first
        // option, and §7.2 lists "every other body-record key" as single-unit. `scan_note` has a
        // definition whose stored unit is the empty string, so read literally it has one option
        // labelled "". That reading is taken; a note row has no numeric value, so nothing converts
        // through it.
        let stored = MarkerUnitOption(label: definition.canonicalUnit, conversion: .identity)
        let extras: [MarkerUnitOption]
        switch tier {
        case .legacy: extras = legacyExtras[key] ?? []
        case .extended: extras = extendedExtras[key] ?? []
        }
        return [stored] + extras
    }

    /// The option of `key` whose label is exactly `label`, in the tier.
    private static func option(for key: String, label: String, tier: MarkerUnitTier) -> MarkerUnitOption? {
        // SPEC-NOTE: §6.2 does not say whether `toStored` and `fromStored` fold case or whitespace
        // in the label. They match exactly: the editor passes back a label `options` returned, and
        // rows carrying a free-form unit string go through `storedValue`, which does normalise.
        options(for: key, tier: tier).first { $0.label == label }
    }

    // MARK: Conversion

    /// The stored value for `value` typed in the unit `label`. Nil when the key has no such option
    /// in the tier, or when `value` or the result is not finite.
    public static func toStored(_ value: Double, key: String, from label: String,
                                tier: MarkerUnitTier) -> Double? {
        guard value.isFinite, let option = option(for: key, label: label, tier: tier) else { return nil }
        let stored = option.conversion.toStored(value)
        return stored.isFinite ? stored : nil
    }

    /// The inverse: the value in the unit `label` for a stored `value`. Nil under the same
    /// conditions.
    public static func fromStored(_ value: Double, key: String, to label: String,
                                  tier: MarkerUnitTier) -> Double? {
        guard value.isFinite, let option = option(for: key, label: label, tier: tier) else { return nil }
        let typed = option.conversion.fromStored(value)
        return typed.isFinite ? typed : nil
    }

    // MARK: Row units

    /// A unit label reduced for matching: trimmed, lowercased, "μ" (U+03BC) folded to "µ"
    /// (U+00B5), "^2" and "2" after "cm" folded to "²".
    public static func normalizedLabel(_ label: String) -> String {
        // SPEC-NOTE: §6.2 lists the folds without an order. The label is trimmed and lowercased
        // first and folded second, so "CM2", "cm^2" and "cm²" all normalise to one string, and
        // normalising twice changes nothing.
        label.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\u{03BC}", with: "\u{00B5}")
            .replacingOccurrences(of: "cm^2", with: "cm\u{00B2}")
            .replacingOccurrences(of: "cm2", with: "cm\u{00B2}")
    }

    /// The stored-unit value of a row that carries any unit string: the row's own value when its
    /// unit matches the stored unit, the converted value when it matches an extended option, both
    /// compared through `normalizedLabel`. Nil for any other unit, and for a non-finite value.
    public static func storedValue(_ value: Double, key: String, rowUnit: String) -> Double? {
        // SPEC-NOTE: §6.2 defines this through "the stored unit" of the key. A key with no
        // catalogue definition has none, so it is nil for every unit.
        guard value.isFinite else { return nil }
        let unit = normalizedLabel(rowUnit)
        // `options` puts the stored unit first, so it wins over any extra option.
        guard let option = options(for: key, tier: .extended).first(where: { normalizedLabel($0.label) == unit })
        else { return nil }
        let stored = option.conversion.toStored(value)
        return stored.isFinite ? stored : nil
    }

    // MARK: Entry parsing

    /// A number typed into an entry field. `decimalSeparator` is the device locale's.
    ///
    /// Leading and trailing whitespace is removed; then one optional leading `-`, one or more ASCII
    /// digits, and optionally one separator followed by one or more ASCII digits. The separator is
    /// `decimalSeparator` when that is `.` or `,`, otherwise `.`; the other of the two characters
    /// is not a separator and the text is rejected. Nothing is guessed about thousands groups.
    /// Anything else is nil: an empty string, an exponent, letters ("nan", "inf"), two separators,
    /// a trailing separator, non-ASCII digits, and a number too large to be finite.
    public static func parseEntry(_ text: String, decimalSeparator: Character) -> Double? {
        let separator: UInt8 = decimalSeparator == "," ? UInt8(ascii: ",") : UInt8(ascii: ".")
        let bytes = Array(text.trimmingCharacters(in: .whitespacesAndNewlines).utf8)

        // Rebuilt with a full stop so `Double(_:)` reads it whatever the device separator is. Every
        // byte admitted is ASCII, so a non-ASCII digit (two or more bytes, all >= 0x80) is refused.
        var canonical: [UInt8] = []
        canonical.reserveCapacity(bytes.count)
        var index = 0

        func takeDigits() -> Bool {
            let start = index
            while index < bytes.count, bytes[index] >= UInt8(ascii: "0"), bytes[index] <= UInt8(ascii: "9") {
                canonical.append(bytes[index])
                index += 1
            }
            return index > start
        }

        if index < bytes.count, bytes[index] == UInt8(ascii: "-") {
            canonical.append(bytes[index])
            index += 1
        }
        guard takeDigits() else { return nil }
        if index < bytes.count, bytes[index] == separator {
            canonical.append(UInt8(ascii: "."))
            index += 1
            guard takeDigits() else { return nil }
        }
        guard index == bytes.count else { return nil }

        guard let parsed = Double(String(decoding: canonical, as: UTF8.self)), parsed.isFinite else { return nil }
        // "-0" is zero; a negative zero is never handed on.
        return parsed == 0 ? 0 : parsed
    }
}
