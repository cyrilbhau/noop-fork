import XCTest
@testable import StrandDesign

/// `RangeIndicator` maps a value and a typical band onto its track. A missing value must draw no dot, so the
/// mapping returns nil for it rather than a position at the start of the track.
final class RangeIndicatorTests: XCTestCase {

    private let accuracy = 1e-9

    func testPositionAcrossTheRange() {
        XCTAssertEqual(RangeIndicator.position(of: 35, in: 35...75) ?? -1, 0, accuracy: accuracy)
        XCTAssertEqual(RangeIndicator.position(of: 55, in: 35...75) ?? -1, 0.5, accuracy: accuracy)
        XCTAssertEqual(RangeIndicator.position(of: 75, in: 35...75) ?? -1, 1, accuracy: accuracy)
        XCTAssertEqual(RangeIndicator.position(of: 62, in: 35...75) ?? -1, 27.0 / 40.0, accuracy: accuracy)
    }

    func testPositionIsClamped() {
        XCTAssertEqual(RangeIndicator.position(of: 10, in: 35...75), 0)
        XCTAssertEqual(RangeIndicator.position(of: 100, in: 35...75), 1)
    }

    func testMissingOrNonFiniteValueHasNoPosition() {
        XCTAssertNil(RangeIndicator.position(of: nil, in: 0...1))
        XCTAssertNil(RangeIndicator.position(of: .nan, in: 0...1))
        XCTAssertNil(RangeIndicator.position(of: .infinity, in: 0...1))
    }

    func testZeroWidthRangeCentres() {
        XCTAssertEqual(RangeIndicator.position(of: 5, in: 5...5), 0.5)
        XCTAssertEqual(RangeIndicator.position(of: 9, in: 5...5), 0.5)
    }

    func testNegativeRange() {
        XCTAssertEqual(RangeIndicator.position(of: 0, in: -2...2) ?? -1, 0.5, accuracy: accuracy)
        XCTAssertEqual(RangeIndicator.position(of: -1, in: -2...2) ?? -1, 0.25, accuracy: accuracy)
    }

    func testBandPositions() {
        let band = RangeIndicator.bandPositions(of: 46...60, in: 35...75)
        XCTAssertEqual(band?.lowerBound ?? -1, 11.0 / 40.0, accuracy: accuracy)
        XCTAssertEqual(band?.upperBound ?? -1, 25.0 / 40.0, accuracy: accuracy)
    }

    func testBandIsClampedToTheTrack() {
        let band = RangeIndicator.bandPositions(of: 20...90, in: 35...75)
        XCTAssertEqual(band, 0...1)
    }

    func testMissingBandHasNoPositions() {
        XCTAssertNil(RangeIndicator.bandPositions(of: nil, in: 35...75))
    }
}
