import XCTest
@testable import StrandDesign

/// Pins the redesign's Recovery banding to `RecoveryScorer.bandRedMax` / `bandYellowMax` (34 / 67) in
/// StrandAnalytics. StrandDesign cannot import StrandAnalytics, so the constants are mirrored; if the scorer's
/// thresholds ever move, this test is the reminder to move `NoopTheme` with them.
final class NoopThemeTests: XCTestCase {

    func testRecoveryThresholdsMirrorScorer() {
        XCTAssertEqual(NoopTheme.recoveryLowMax, 34)
        XCTAssertEqual(NoopTheme.recoveryMidMax, 67)
    }

    func testRecoveryBandBoundaries() {
        XCTAssertEqual(NoopTheme.recoveryBand(for: 0), .low)
        XCTAssertEqual(NoopTheme.recoveryBand(for: 33.9), .low)
        XCTAssertEqual(NoopTheme.recoveryBand(for: 34), .mid)
        XCTAssertEqual(NoopTheme.recoveryBand(for: 66.9), .mid)
        XCTAssertEqual(NoopTheme.recoveryBand(for: 67), .high)
        XCTAssertEqual(NoopTheme.recoveryBand(for: 100), .high)
    }

    func testZoneColorClamps() {
        // Out-of-range zone numbers must not trap; they clamp to zone 1 / zone 5.
        _ = NoopTheme.zoneColor(0)
        _ = NoopTheme.zoneColor(9)
        XCTAssertEqual(NoopTheme.zones.count, 5)
    }

    func testReduceMotionDisablesRingFill() {
        XCTAssertTrue(NoopTheme.Motion.ringsAnimate(reduceMotion: false, fillOnLoad: true))
        XCTAssertFalse(NoopTheme.Motion.ringsAnimate(reduceMotion: true, fillOnLoad: true))
        XCTAssertFalse(NoopTheme.Motion.ringsAnimate(reduceMotion: false, fillOnLoad: false))
    }

    func testHeartbeatInterval() {
        XCTAssertEqual(NoopTheme.Motion.heartbeatInterval(bpm: 60, reduceMotion: false), 1.0)
        XCTAssertNil(NoopTheme.Motion.heartbeatInterval(bpm: 60, reduceMotion: true))
        XCTAssertNil(NoopTheme.Motion.heartbeatInterval(bpm: nil, reduceMotion: false))
        XCTAssertNil(NoopTheme.Motion.heartbeatInterval(bpm: 0, reduceMotion: false))
    }

    func testTypeRampIsNotRounded() {
        // The redesign uses SF Pro default; widget numerals are Light and in-app numerals semibold or bold.
        XCTAssertEqual(NoopType.widgetNumber.weight, .light)
        XCTAssertEqual(NoopType.heroNumber.weight, .bold)
        XCTAssertEqual(NoopType.tileNumber.weight, .semibold)
        XCTAssertTrue(NoopType.heroNumber.isNumeric)
    }
}
