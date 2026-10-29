import XCTest
import SwiftUI
@testable import StrandDesign

/// Pins the pure geometry behind `NoopRing` and `NoopArcGauge` (`docs/personal/REDESIGN-IMPLEMENTATION.md`
/// §3.6 items 1–2) and the Reduce Motion gate the callers pass in as `animate`.
final class NoopRingGeometryTests: XCTestCase {

    private typealias Gauge = NoopArcGauge<EmptyView>
    private let accuracy = 1e-9

    // MARK: - Fraction clamping / missing

    func testNilAndNonFiniteAreMissing() {
        XCTAssertNil(NoopRing.clampedFraction(nil))
        XCTAssertNil(NoopRing.clampedFraction(.nan))
        XCTAssertNil(NoopRing.clampedFraction(.infinity))
        XCTAssertNil(NoopRing.clampedFraction(-.infinity))
    }

    func testFractionClampsToUnitRange() {
        XCTAssertEqual(NoopRing.clampedFraction(-0.2), 0)
        XCTAssertEqual(NoopRing.clampedFraction(0), 0)
        XCTAssertEqual(NoopRing.clampedFraction(0.543), 0.543)
        XCTAssertEqual(NoopRing.clampedFraction(1), 1)
        XCTAssertEqual(NoopRing.clampedFraction(1.7), 1)
    }

    func testMissingStrokeIs45PercentOfLineWidth() {
        XCTAssertEqual(NoopRing.missingLineWidth(lineWidth: 10), 4.5, accuracy: accuracy)
        XCTAssertEqual(NoopRing.missingLineWidth(lineWidth: 22), 9.9, accuracy: accuracy)
    }

    func testDefaultLineWidthAndDashScaleWithFloors() {
        XCTAssertEqual(NoopRing.defaultLineWidth(diameter: 100), 7, accuracy: accuracy)
        XCTAssertEqual(NoopRing.defaultLineWidth(diameter: 30), 3, accuracy: accuracy)
        XCTAssertEqual(NoopRing.dashPattern(diameter: 100), [3, 5])
        XCTAssertEqual(NoopRing.dashPattern(diameter: 30), [1.5, 2.5])
    }

    // MARK: - Count-up start label

    func testCountUpStartLabelZeroesPureNumbers() {
        XCTAssertEqual(NoopRing.countUpStartLabel("78"), "0")
        XCTAssertEqual(NoopRing.countUpStartLabel("11.6"), "0.0")
        XCTAssertEqual(NoopRing.countUpStartLabel("4,25"), "0,00")
    }

    func testCountUpStartLabelSkipsNonNumericLabels() {
        XCTAssertNil(NoopRing.countUpStartLabel(""))
        XCTAssertNil(NoopRing.countUpStartLabel("—"))
        XCTAssertNil(NoopRing.countUpStartLabel("7h 42m"))
        XCTAssertNil(NoopRing.countUpStartLabel("-3"))
        XCTAssertNil(NoopRing.countUpStartLabel("1,234"))
        XCTAssertNil(NoopRing.countUpStartLabel("1.2.3"))
        XCTAssertNil(NoopRing.countUpStartLabel("12."))
    }

    // MARK: - Arc geometry

    func testArcStartsAt150AndSweeps240To390() {
        XCTAssertEqual(Gauge.startDegrees, 150)
        XCTAssertEqual(Gauge.sweepDegrees, 240)
        XCTAssertEqual(Gauge.endDegrees, 390)
        XCTAssertEqual(Gauge.angle(forFraction: 0), 150, accuracy: accuracy)
        XCTAssertEqual(Gauge.angle(forFraction: 0.5), 270, accuracy: accuracy)   // 12 o'clock
        XCTAssertEqual(Gauge.angle(forFraction: 1), 390, accuracy: accuracy)
    }

    func testArcAngleClampsAndTreatsNonFiniteAsStart() {
        XCTAssertEqual(Gauge.angle(forFraction: -1), 150, accuracy: accuracy)
        XCTAssertEqual(Gauge.angle(forFraction: 2), 390, accuracy: accuracy)
        XCTAssertEqual(Gauge.angle(forFraction: .nan), 150, accuracy: accuracy)
    }

    func testStrainTargetTicksAt12And15Of21() {
        let ticks = Gauge.tickAngles(for: 12.0 / 21...15.0 / 21)
        XCTAssertEqual(ticks.count, 2)
        XCTAssertEqual(ticks[0], 150 + 240 * 12 / 21, accuracy: accuracy)   // ≈ 287.14°
        XCTAssertEqual(ticks[1], 150 + 240 * 15 / 21, accuracy: accuracy)   // ≈ 321.43°
        XCTAssertEqual(ticks[0], 287.142857142857, accuracy: 1e-6)
        XCTAssertEqual(ticks[1], 321.428571428571, accuracy: 1e-6)
    }

    func testFrameAndKnobGeometryAtMockupSize() {
        // Mockup: r 112, stroke 22, knob r 7.
        XCTAssertEqual(Gauge.knobRadius(lineWidth: 22), 7, accuracy: accuracy)
        let size = Gauge.frameSize(radius: 112, lineWidth: 22)
        XCTAssertEqual(size.width, 2 * (112 + 11 + 4), accuracy: accuracy)
        XCTAssertEqual(size.height, (112 + 11 + 4) + (56 + 11), accuracy: 1e-6)
        let c = Gauge.center(radius: 112, lineWidth: 22)
        XCTAssertEqual(c.x, size.width / 2, accuracy: accuracy)
        // The arc ends (150° and 30°) sit at the bottom edge minus the cap radius, symmetric about the centre.
        let start = Gauge.point(forFraction: 0, center: c, radius: 112)
        let end = Gauge.point(forFraction: 1, center: c, radius: 112)
        XCTAssertEqual(start.y, size.height - 11, accuracy: 1e-6)
        XCTAssertEqual(end.y, start.y, accuracy: 1e-6)
        XCTAssertEqual(start.x + end.x, 2 * c.x, accuracy: 1e-6)
        XCTAssertLessThan(start.x, c.x)
    }

    // MARK: - Reduce Motion gate

    func testRingsAnimateOnlyWithoutReduceMotionAndWithSettingOn() {
        XCTAssertTrue(NoopTheme.Motion.ringsAnimate(reduceMotion: false, fillOnLoad: true))
        XCTAssertFalse(NoopTheme.Motion.ringsAnimate(reduceMotion: true, fillOnLoad: true))
        XCTAssertFalse(NoopTheme.Motion.ringsAnimate(reduceMotion: false, fillOnLoad: false))
        XCTAssertFalse(NoopTheme.Motion.ringsAnimate(reduceMotion: true, fillOnLoad: false))
    }
}
