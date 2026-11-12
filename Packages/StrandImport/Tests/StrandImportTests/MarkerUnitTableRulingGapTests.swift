import XCTest
@testable import StrandImport

// Tests for ruling A16 of docs/personal/superapp/specs/RULINGS-ADDENDUM.md ("Stage 4 overflow and
// sign"), which settles fault-injection gaps U15j and U19 over
// docs/personal/superapp/specs/stage-4.md §6.2 and §7.2. Every expected value is derived from the
// ruling and the §7.2 table.
//
//   U15j  "parseEntry never returns negative zero."
//   U19   "toStored and fromStored match an option label exactly; only storedValue folds labels."
//   All   "No output is ever infinite or NaN."

/// `MarkerUnitTable` at the points ruling A16 decides.
final class MarkerUnitTableRulingGapTests: XCTestCase {

    private let huge = Double.greatestFiniteMagnitude

    /// Keys of the §7.2 table, at least one for each conversion it lists.
    private let tableKeys = ["total_cholesterol", "ldl", "hdl", "triglycerides", "fasting_glucose",
                             "hba1c", "ferritin", "iron", "haemoglobin", "vitamin_d", "vitamin_b12",
                             "folate", "tsh", "free_t4", "crp", "creatinine", "alt", "sodium",
                             "weight", "bench_grip_kg", "waist", "height", "scan_fat_mass",
                             "scan_lean_mass", "scan_visceral_fat_mass", "bench_dead_hang_s",
                             "body_fat", "egfr"]

    // MARK: - U15j: parseEntry never returns negative zero

    /// Fault U15j. Text that spells a negative zero is accepted (§6.2 rules 2 and 3) and the result
    /// is positive zero. The mutant returns `-0.0`, which equals zero but carries a minus sign.
    func testParseEntryNeverReturnsNegativeZero() {
        let cases: [(String, Character)] = [("-0", "."), ("-0.0", "."), ("-0.000", "."), ("-00", "."),
                                            (" -0 ", "."), ("-0", ","), ("-0,0", ","), ("-0,000", ","),
                                            ("-0", ";")]
        for (text, separator) in cases {
            let parsed = MarkerUnitTable.parseEntry(text, decimalSeparator: separator)
            XCTAssertNotNil(parsed, text.debugDescription)
            XCTAssertEqual(parsed, 0, text.debugDescription)
            XCTAssertEqual(parsed?.sign, .plus, "\(text.debugDescription) must be positive zero")
        }
    }

    /// The limit of the ruling: only a zero loses its sign. A negative number keeps it, and a plain
    /// zero is positive zero.
    func testParseEntryKeepsTheSignOfANegativeNumber() {
        XCTAssertEqual(MarkerUnitTable.parseEntry("-0.5", decimalSeparator: "."), -0.5)
        XCTAssertEqual(MarkerUnitTable.parseEntry("-0,001", decimalSeparator: ","), -0.001)
        XCTAssertEqual(MarkerUnitTable.parseEntry("-12", decimalSeparator: "."), -12)
        XCTAssertEqual(MarkerUnitTable.parseEntry("0", decimalSeparator: ".")?.sign, .plus)
        XCTAssertEqual(MarkerUnitTable.parseEntry("0.0", decimalSeparator: ".")?.sign, .plus)
    }

    // MARK: - U19: exact labels for toStored and fromStored

    /// Fault U19, `toStored`. The label must be the option's own, character for character. Pounds to
    /// kilograms is `divide(2.20462)` and HbA1c percent is `affine(subtract: 2.152, divideBy:
    /// 0.09148)` (§7.2); the same label in another case or with whitespace is not an option, so the
    /// result is nil. The mutant folds the label and converts.
    func testToStoredMatchesTheOptionLabelExactly() {
        XCTAssertEqual(MarkerUnitTable.toStored(220.462, key: "weight", from: "lb", tier: .extended),
                       220.462 / 2.20462)
        XCTAssertEqual(MarkerUnitTable.toStored(6.0, key: "hba1c", from: "%", tier: .extended),
                       (6.0 - 2.152) / 0.09148)
        XCTAssertEqual(MarkerUnitTable.toStored(5, key: "ldl", from: "mmol/L", tier: .legacy), 5)
        XCTAssertEqual(MarkerUnitTable.toStored(100, key: "ldl", from: "mg/dL", tier: .legacy),
                       100 * (1.0 / 38.67))

        for label in ["LB", "Lb", " lb", "lb ", "KG", " kg "] {
            XCTAssertNil(MarkerUnitTable.toStored(220.462, key: "weight", from: label, tier: .extended),
                         label.debugDescription)
        }
        for label in [" %", "% ", "MMOL/MOL", "mmol/Mol"] {
            XCTAssertNil(MarkerUnitTable.toStored(6.0, key: "hba1c", from: label, tier: .extended),
                         label.debugDescription)
        }
        for tier in [MarkerUnitTier.legacy, .extended] {
            for label in ["MG/DL", "mg/dl", " mg/dL ", "MMOL/L", "mmol/l"] {
                XCTAssertNil(MarkerUnitTable.toStored(100, key: "ldl", from: label, tier: tier),
                             "\(tier) \(label.debugDescription)")
            }
        }
        // The Greek mu (U+03BC) is not the micro sign (U+00B5) the option carries.
        XCTAssertEqual(MarkerUnitTable.toStored(80, key: "creatinine", from: "\u{00B5}mol/L", tier: .extended), 80)
        XCTAssertNil(MarkerUnitTable.toStored(80, key: "creatinine", from: "\u{03BC}mol/L", tier: .extended))
    }

    /// Fault U19, `fromStored`. The inverse of `divide(d)` is `stored * d` and of `affine(s, d)` is
    /// `stored * d + s` (§6.2). A folded form of the label is nil.
    func testFromStoredMatchesTheOptionLabelExactly() {
        XCTAssertEqual(MarkerUnitTable.fromStored(100, key: "weight", to: "lb", tier: .extended),
                       100 * 2.20462)
        XCTAssertEqual(MarkerUnitTable.fromStored(42, key: "hba1c", to: "%", tier: .extended),
                       42 * 0.09148 + 2.152)
        XCTAssertEqual(MarkerUnitTable.fromStored(2.5, key: "ldl", to: "mmol/L", tier: .legacy), 2.5)
        XCTAssertEqual(MarkerUnitTable.fromStored(2.5, key: "ldl", to: "mg/dL", tier: .legacy),
                       2.5 / (1.0 / 38.67))

        for label in ["LB", "Lb", " lb", "lb ", "KG", " kg "] {
            XCTAssertNil(MarkerUnitTable.fromStored(100, key: "weight", to: label, tier: .extended),
                         label.debugDescription)
        }
        for label in [" %", "% ", "MMOL/MOL", "mmol/Mol"] {
            XCTAssertNil(MarkerUnitTable.fromStored(42, key: "hba1c", to: label, tier: .extended),
                         label.debugDescription)
        }
        for tier in [MarkerUnitTier.legacy, .extended] {
            for label in ["MG/DL", "mg/dl", " mg/dL ", "MMOL/L", "mmol/l"] {
                XCTAssertNil(MarkerUnitTable.fromStored(2.5, key: "ldl", to: label, tier: tier),
                             "\(tier) \(label.debugDescription)")
            }
        }
        XCTAssertEqual(MarkerUnitTable.fromStored(80, key: "creatinine", to: "\u{00B5}mol/L", tier: .extended), 80)
        XCTAssertNil(MarkerUnitTable.fromStored(80, key: "creatinine", to: "\u{03BC}mol/L", tier: .extended))
    }

    /// The other half of the U19 ruling: `storedValue` is the one function that folds. The labels
    /// the two conversion functions refuse above give the converted value here.
    func testOnlyStoredValueFoldsLabels() {
        XCTAssertEqual(MarkerUnitTable.storedValue(220.462, key: "weight", rowUnit: "LB"), 220.462 / 2.20462)
        XCTAssertEqual(MarkerUnitTable.storedValue(220.462, key: "weight", rowUnit: " lb "), 220.462 / 2.20462)
        XCTAssertEqual(MarkerUnitTable.storedValue(100, key: "weight", rowUnit: " KG "), 100)
        XCTAssertEqual(MarkerUnitTable.storedValue(6.0, key: "hba1c", rowUnit: " % "), (6.0 - 2.152) / 0.09148)
        XCTAssertEqual(MarkerUnitTable.storedValue(42, key: "hba1c", rowUnit: "MMOL/MOL"), 42)
        XCTAssertEqual(MarkerUnitTable.storedValue(100, key: "ldl", rowUnit: "MG/DL"), 100 * (1.0 / 38.67))
        XCTAssertEqual(MarkerUnitTable.storedValue(80, key: "creatinine", rowUnit: "\u{03BC}MOL/L"), 80)
        XCTAssertEqual(MarkerUnitTable.storedValue(1, key: "creatinine", rowUnit: "Mg/Dl"), 1 * 88.4)
    }

    // MARK: - No output is ever infinite or NaN

    /// Ruling A16, last sentence, at the named overflows. Each conversion below leaves the double
    /// range, and §6.2 makes a non-finite result nil: `multiply(88.4)` and `multiply(1000)` forward,
    /// the inverse of `divide(2.20462)` (times 2.20462) and the inverse of `multiply(1.0 / 38.67)`
    /// (divided by it).
    func testAConversionThatOverflowsIsNil() {
        XCTAssertNil(MarkerUnitTable.toStored(huge, key: "creatinine", from: "mg/dL", tier: .extended))
        XCTAssertNil(MarkerUnitTable.toStored(-huge, key: "creatinine", from: "mg/dL", tier: .extended))
        XCTAssertNil(MarkerUnitTable.toStored(huge, key: "scan_visceral_fat_mass", from: "kg", tier: .extended))
        XCTAssertNil(MarkerUnitTable.fromStored(huge, key: "weight", to: "lb", tier: .extended))
        XCTAssertNil(MarkerUnitTable.fromStored(huge, key: "ldl", to: "mg/dL", tier: .legacy))
        XCTAssertNil(MarkerUnitTable.fromStored(-huge, key: "ldl", to: "mg/dL", tier: .extended))
        XCTAssertNil(MarkerUnitTable.storedValue(huge, key: "creatinine", rowUnit: "mg/dL"))
        XCTAssertNil(MarkerUnitTable.storedValue(huge, key: "scan_visceral_fat_mass", rowUnit: "kg"))
        // The same value in the stored unit does not overflow and is returned as it is.
        XCTAssertEqual(MarkerUnitTable.toStored(huge, key: "creatinine", from: "\u{00B5}mol/L", tier: .extended), huge)
        XCTAssertEqual(MarkerUnitTable.storedValue(huge, key: "creatinine", rowUnit: "\u{00B5}mol/L"), huge)
    }

    /// Ruling A16, last sentence, swept: for every table key, every option of both tiers and a range
    /// of extreme and non-finite inputs, each of the three conversion functions returns nil or a
    /// finite number. A non-finite input is always nil (§6.2).
    func testNoConversionReturnsANonFiniteNumber() {
        let values: [Double] = [-.infinity, -huge, -1e308, -1e300, -1, -0.0, 0, .leastNonzeroMagnitude, 1,
                                1e300, 1e308, huge, .infinity, .nan]
        var optionsSeen = 0
        for key in tableKeys {
            for tier in [MarkerUnitTier.legacy, .extended] {
                for option in MarkerUnitTable.options(for: key, tier: tier) {
                    optionsSeen += 1
                    for v in values {
                        let label = "\(key) \(option.label) \(tier) \(v)"
                        let forward = MarkerUnitTable.toStored(v, key: key, from: option.label, tier: tier)
                        let back = MarkerUnitTable.fromStored(v, key: key, to: option.label, tier: tier)
                        let row = MarkerUnitTable.storedValue(v, key: key, rowUnit: option.label)
                        for result in [forward, back, row] {
                            if let r = result { XCTAssertTrue(r.isFinite, "\(label): \(r)") }
                        }
                        if !v.isFinite {
                            XCTAssertNil(forward, label)
                            XCTAssertNil(back, label)
                            XCTAssertNil(row, label)
                        }
                    }
                }
            }
        }
        // Every key has its stored unit in the extended tier, so the sweep cannot pass by being empty.
        XCTAssertGreaterThanOrEqual(optionsSeen, tableKeys.count)
    }

    /// Ruling A16, last sentence, for the entry parser: digits that spell a number beyond the double
    /// range are nil (§6.2 rule 6), with or without a sign or a fraction, and the largest text that is
    /// still in range is a finite number.
    func testParseEntryNeverReturnsANonFiniteNumber() {
        let tooLong = String(repeating: "9", count: 400)
        for (text, separator) in [(tooLong, Character(".")), ("-" + tooLong, "."), (tooLong + ".5", "."),
                                  (tooLong + ",5", ","), (" " + tooLong + " ", ".")] {
            XCTAssertNil(MarkerUnitTable.parseEntry(text, decimalSeparator: separator),
                         "\(text.count) characters")
        }
        let inRange = "1" + String(repeating: "0", count: 308)
        XCTAssertEqual(MarkerUnitTable.parseEntry(inRange, decimalSeparator: "."), 1e308)
        XCTAssertEqual(MarkerUnitTable.parseEntry("-" + inRange, decimalSeparator: "."), -1e308)
        // 0.000…1 underflows to zero: the result is a finite zero and, by the same ruling, positive.
        let tiny = "-0." + String(repeating: "0", count: 400) + "1"
        let underflow = MarkerUnitTable.parseEntry(tiny, decimalSeparator: ".")
        XCTAssertNotNil(underflow)
        if let u = underflow {
            XCTAssertTrue(u.isFinite)
            XCTAssertFalse(u == 0 && u.sign == .minus, "an underflow to zero must not be negative zero")
        }
    }
}
