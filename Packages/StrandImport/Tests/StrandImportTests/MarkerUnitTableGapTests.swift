import XCTest
@testable import StrandImport

// Tests added after fault injection (stage 4, faults U19 and U15j), from
// docs/personal/superapp/specs/stage-4.md §6.2 and §7.2.
//
// U19 rests on one reading, stated here so a ruling can overturn it: §6.2 says `toStored` and
// `fromStored` are nil "when the key has no such option in the tier", and names `normalizedLabel`
// only for `storedValue` ("both compared through `normalizedLabel`"). Read by that contrast, the two
// conversion functions match an option's label as `options(for:tier:)` returns it, and only
// `storedValue` folds case, whitespace and the micro sign.
//
// NEEDS A RULING (U15j). §6.2 accepts one leading "-" and then digits, and says nothing of the sign
// of a zero result. Reading one: "-0" is the number the text spells, negative zero. Reading two: the
// parser never returns negative zero, as `BodyRecordMath.quantize` never does. No test here asserts
// the sign.

/// `MarkerUnitTable` label matching and the zero edge of the entry parser (§6.2).
final class MarkerUnitTableGapTests: XCTestCase {

    private let lipidFactor = 1.0 / 38.67

    // MARK: - U19: which labels the conversion functions accept

    /// A label that differs from the option's only by case or surrounding whitespace is not an option
    /// of the key, in either tier and in either direction. The exact label converts.
    func testToStoredAndFromStoredMatchTheOptionLabelExactly() {
        for tier in [MarkerUnitTier.legacy, .extended] {
            XCTAssertEqual(MarkerUnitTable.toStored(100, key: "ldl", from: "mg/dL", tier: tier),
                           100 * lipidFactor, "\(tier)")
            XCTAssertEqual(MarkerUnitTable.fromStored(2.5, key: "ldl", to: "mg/dL", tier: tier),
                           2.5 / lipidFactor, "\(tier)")
            for label in ["MG/DL", "mg/dl", "Mg/dL", " mg/dL", "mg/dL ", "\tmg/dL\n", "MMOL/L", " mmol/L "] {
                XCTAssertNil(MarkerUnitTable.toStored(100, key: "ldl", from: label, tier: tier),
                             "toStored \(tier) \(label.debugDescription)")
                XCTAssertNil(MarkerUnitTable.fromStored(2.5, key: "ldl", to: label, tier: tier),
                             "fromStored \(tier) \(label.debugDescription)")
            }
        }
    }

    /// The Greek mu (U+03BC) in place of the micro sign (U+00B5) is a different label to the two
    /// conversion functions; `normalizedLabel` folds it only for `storedValue`.
    func testToStoredAndFromStoredDoNotFoldTheMicroSign() {
        let stored = MarkerUnitTable.options(for: "creatinine", tier: .extended).first?.label ?? ""
        XCTAssertEqual(stored, "\u{00B5}mol/L")
        let greek = "\u{03BC}mol/L"
        XCTAssertEqual(MarkerUnitTable.toStored(80, key: "creatinine", from: stored, tier: .extended), 80)
        XCTAssertNil(MarkerUnitTable.toStored(80, key: "creatinine", from: greek, tier: .extended))
        XCTAssertNil(MarkerUnitTable.fromStored(80, key: "creatinine", to: greek, tier: .extended))
        XCTAssertNil(MarkerUnitTable.toStored(1, key: "creatinine", from: "MG/DL", tier: .extended))
    }

    /// The contrast §6.2 draws: the same folded labels that the conversion functions refuse are
    /// matched by `storedValue`, which compares through `normalizedLabel`.
    func testStoredValueFoldsTheLabelsTheConversionFunctionsRefuse() {
        XCTAssertEqual(MarkerUnitTable.storedValue(100, key: "ldl", rowUnit: "MG/DL"), 100 * lipidFactor)
        XCTAssertEqual(MarkerUnitTable.storedValue(100, key: "ldl", rowUnit: " mg/dl "), 100 * lipidFactor)
        XCTAssertEqual(MarkerUnitTable.storedValue(2.5, key: "ldl", rowUnit: " MMOL/L "), 2.5)
        XCTAssertEqual(MarkerUnitTable.storedValue(80, key: "creatinine", rowUnit: "\u{03BC}mol/L"), 80)
    }

    // MARK: - U15j: a typed negative zero

    /// What both readings of a typed negative zero share: the text is accepted, with either
    /// separator, and the result equals zero. The sign of that zero needs a ruling and is not
    /// asserted.
    func testNegativeZeroTextIsAcceptedAndEqualsZero() {
        for (text, separator) in [("-0", Character(".")), ("-0.0", "."), ("-0.000", "."), ("-0", ","),
                                  ("-0,0", ","), (" -0 ", ".")] {
            let parsed = MarkerUnitTable.parseEntry(text, decimalSeparator: separator)
            XCTAssertNotNil(parsed, text.debugDescription)
            XCTAssertEqual(parsed, 0, text.debugDescription)
        }
    }
}
