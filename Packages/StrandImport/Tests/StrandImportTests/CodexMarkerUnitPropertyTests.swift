import XCTest
@testable import StrandImport

final class CodexMarkerUnitPropertyTests: XCTestCase {
    func testEveryCatalogueUnitRoundTripsGeneratedFiniteValues() throws {
        var state: UInt64 = 0xC01613
        for definition in MarkerCatalog.builtIn + MarkerCatalog.bodyRecord {
            for tier in [MarkerUnitTier.legacy, .extended] {
                for option in MarkerUnitTable.options(for: definition.key, tier: tier) {
                    for _ in 0..<80 {
                        state = state &* 6364136223846793005 &+ 1442695040888963407
                        let value = Double(Int(state % 2_000_001) - 1_000_000) / 1_000
                        let stored = try XCTUnwrap(MarkerUnitTable.toStored(value, key: definition.key, from: option.label, tier: tier))
                        let returned = try XCTUnwrap(MarkerUnitTable.fromStored(stored, key: definition.key, to: option.label, tier: tier))
                        XCTAssertTrue(stored.isFinite && returned.isFinite)
                        XCTAssertEqual(returned, value, accuracy: max(1e-9, abs(value) * 1e-12),
                                       "\(definition.key) / \(option.label)")
                    }
                    for bad in [Double.nan, .infinity, -.infinity] {
                        XCTAssertNil(MarkerUnitTable.toStored(bad, key: definition.key, from: option.label, tier: tier))
                        XCTAssertNil(MarkerUnitTable.fromStored(bad, key: definition.key, to: option.label, tier: tier))
                    }
                }
            }
        }
    }

    func testEntryParsingGeneratedDecimalRoundTripsAndNormalizesNegativeZero() throws {
        var state: UInt64 = 0xC01614
        for _ in 0..<3_000 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let value = Double(Int(state % 2_000_001) - 1_000_000) / 100
            let text = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
            let dot = try XCTUnwrap(MarkerUnitTable.parseEntry(text, decimalSeparator: "."))
            let comma = try XCTUnwrap(MarkerUnitTable.parseEntry(text.replacingOccurrences(of: ".", with: ","), decimalSeparator: ","))
            XCTAssertEqual(dot, value, accuracy: 1e-9)
            XCTAssertEqual(comma, dot)
        }
        XCTAssertEqual(MarkerUnitTable.parseEntry("-0.00", decimalSeparator: ".")?.sign, .plus)
        for text in ["nan", "inf", "1e309", "", "1,234.5", "1 234", "1\n2"] {
            XCTAssertNil(MarkerUnitTable.parseEntry(text, decimalSeparator: "."))
        }
    }
}
