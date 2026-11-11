import XCTest
import WhoopStore
@testable import StrandAnalytics

// API ASSUMED BY THESE TESTS
//
// From the stage-2 implementation (docs/personal/superapp/specs/stage-2.md §6.1):
//
//   struct CoachDayStyle: Equatable {
//       let recoveryLabel: String, strainLabel: String, sleepLabel: String
//       let daySeparator: String, strainFactor: Double
//       init(recoveryLabel: String, strainLabel: String, sleepLabel: String, daySeparator: String,
//            strainFactor: Double)
//       static let coachContext: CoachDayStyle                 // "charge", "effort", "rest", ":, ", 1.0
//       static func packet(strainFactor: Double) -> CoachDayStyle   // "recovery", "strain", "sleep", ": "
//   }
//   enum CoachDayFormat {
//       static let notMeasured: String                         // "—" (U+2014)
//       static func fields(_ day: DailyMetric, style: CoachDayStyle) -> [String]
//       static func dayLine(_ day: DailyMetric, style: CoachDayStyle) -> String
//       static func primaryAveragesLine(_ days: [DailyMetric], style: CoachDayStyle) -> String
//       static func vitalsAveragesLine(_ days: [DailyMetric]) -> String
//       static func efficiencyPercent(_ raw: Double?) -> String
//   }
//
// Existing API: `DailyMetric` (WhoopStore) through its public initialiser. `CoachPacketFixture` (this
// test target) supplies the fixture rows and the fixed-seed generator.

/// The shared per-day formatter of stage 2 §6.1: one formatter, two styles, and byte identity with the
/// in-app Coach context as it stood before the extraction.
final class CoachDayFormatTests: XCTestCase {

    // MARK: - The frozen legacy formatter

    /// A private copy of the day-line and averages helpers of `Strand/AI/AICoach.swift` as they stood
    /// before stage 2's extraction, taking a `DailyMetric`. It is the oracle for byte identity and is
    /// never edited (specification §12.1).
    private enum FrozenLegacy {
        static func dayLine(_ d: DailyMetric) -> String {
            var parts: [String] = [d.day + ":"]
            parts.append("charge " + (d.recovery.map { "\(Int($0.rounded()))" } ?? "—"))
            parts.append("effort " + (d.strain.map { String(format: "%.1f", $0) } ?? "—"))
            parts.append("rest " + (d.totalSleepMin.map { String(format: "%.1fh", $0 / 60) } ?? "—"))
            parts.append("deep " + hoursOrDash(d.deepMin))
            parts.append("REM " + hoursOrDash(d.remMin))
            parts.append("light " + hoursOrDash(d.lightMin))
            parts.append("eff " + efficiencyPercentOrDash(d.efficiency))
            parts.append("HRV " + (d.avgHrv.map { "\(Int($0.rounded()))ms" } ?? "—"))
            parts.append("RHR " + (d.restingHr.map { "\($0)bpm" } ?? "—"))
            return parts.joined(separator: ", ")
        }

        static func hoursOrDash(_ minutes: Double?) -> String {
            minutes.map { String(format: "%.1fh", $0 / 60) } ?? "—"
        }

        static func efficiencyPercentOrDash(_ raw: Double?) -> String {
            guard var e = raw, e > 0 else { return "—" }
            if e > 1.5 { e /= 100 }
            guard e > 0, e <= 1 else { return "—" }
            return "\(Int((e * 100).rounded()))%"
        }

        static func avgOne(_ xs: [Double]) -> String {
            guard !xs.isEmpty else { return "—" }
            return String(format: "%.1f", xs.reduce(0, +) / Double(xs.count))
        }

        static func avgInt(_ xs: [Double]) -> String {
            guard !xs.isEmpty else { return "—" }
            return "\(Int((xs.reduce(0, +) / Double(xs.count)).rounded()))"
        }

        static func avgSleepHours(_ days: [DailyMetric]) -> String {
            let mins = days.compactMap { $0.totalSleepMin }
            guard !mins.isEmpty else { return "—" }
            return String(format: "%.1f", (mins.reduce(0, +) / Double(mins.count)) / 60)
        }

        /// The first averages line of `buildContext()`, without its two-space indent.
        static func primaryAverages(_ last30: [DailyMetric]) -> String {
            "charge: \(avgInt(last30.compactMap { $0.recovery }))"
                + ", effort: \(avgOne(last30.compactMap { $0.strain }))"
                + ", sleep: \(avgSleepHours(last30))h"
                + ", HRV: \(avgInt(last30.compactMap { $0.avgHrv })) ms"
                + ", RHR: \(avgInt(last30.compactMap { $0.restingHr.map(Double.init) })) bpm"
        }

        /// The second averages line of `buildContext()`, without its two-space indent.
        static func vitalsAverages(_ last30: [DailyMetric]) -> String {
            "SpO2: \(avgInt(last30.compactMap { $0.spo2Pct }))%"
                + ", respiration: \(avgOne(last30.compactMap { $0.respRateBpm }))/min"
                + ", skin-temp deviation: \(avgOne(last30.compactMap { $0.skinTempDevC }))°C"
                + ", steps: \(avgInt(last30.compactMap { $0.steps.map(Double.init) }))/day"
                + ", active energy: \(avgInt(last30.compactMap { $0.activeKcalEst }))kcal/day"
        }
    }

    // MARK: - Helpers

    private let dash = "\u{2014}"

    /// A row with every printed field set, including the vitals the in-app Coach averages.
    private func metric(_ day: String = "2031-03-03", recovery: Double? = 62, strain: Double? = 47,
                        sleep: Double? = 444, deep: Double? = 78, rem: Double? = 102,
                        light: Double? = 264, eff: Double? = 0.91, hrv: Double? = 58,
                        rhr: Int? = 54, spo2: Double? = nil, skin: Double? = nil,
                        resp: Double? = nil, steps: Int? = nil, kcal: Double? = nil) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: sleep, efficiency: eff, deepMin: deep, remMin: rem,
                    lightMin: light, disturbances: nil, restingHr: rhr, avgHrv: hrv,
                    recovery: recovery, strain: strain, exerciseCount: nil, spo2Pct: spo2,
                    skinTempDevC: skin, respRateBpm: resp, steps: steps, activeKcalEst: kcal)
    }

    /// A row with a day key and nothing else.
    private func emptyMetric(_ day: String = "2031-03-07") -> DailyMetric {
        metric(day, recovery: nil, strain: nil, sleep: nil, deep: nil, rem: nil, light: nil, eff: nil,
               hrv: nil, rhr: nil)
    }

    private let packetStyle = CoachDayStyle.packet(strainFactor: 0.21)

    /// Field `index` of a day's nine, or an empty string when the formatter returned fewer, so a short
    /// answer fails the assertion instead of stopping the run.
    private func field(_ index: Int, of day: DailyMetric, style: CoachDayStyle) -> String {
        let fields = CoachDayFormat.fields(day, style: style)
        return index < fields.count ? fields[index] : ""
    }

    // MARK: - Styles

    func testCoachStyleLineMatchesTheFrozenLegacyLine() {
        XCTAssertEqual(CoachDayStyle.coachContext,
                       CoachDayStyle(recoveryLabel: "charge", strainLabel: "effort", sleepLabel: "rest",
                                     daySeparator: ":, ", strainFactor: 1.0))
        let literal = "2031-03-03:, charge 62, effort 47.0, rest 7.4h, deep 1.3h, REM 1.7h, "
            + "light 4.4h, eff 91%, HRV 58ms, RHR 54bpm"
        XCTAssertEqual(CoachDayFormat.dayLine(metric(), style: .coachContext), literal)
        XCTAssertEqual(FrozenLegacy.dayLine(metric()), literal, "the frozen copy must not drift")
        for day in CoachPacketFixture.days + [emptyMetric()] {
            XCTAssertEqual(CoachDayFormat.dayLine(day, style: .coachContext),
                           FrozenLegacy.dayLine(day), day.day)
        }
    }

    func testPacketStyleLineUsesRecoveryStrainSleepAndAPlainColon() {
        XCTAssertEqual(CoachDayStyle.packet(strainFactor: 0.21),
                       CoachDayStyle(recoveryLabel: "recovery", strainLabel: "strain",
                                     sleepLabel: "sleep", daySeparator: ": ", strainFactor: 0.21))
        XCTAssertEqual(CoachDayFormat.dayLine(metric(), style: packetStyle),
                       "2031-03-03: recovery 62, strain 9.9, sleep 7.4h, deep 1.3h, REM 1.7h, "
                           + "light 4.4h, eff 91%, HRV 58ms, RHR 54bpm")
        let line = CoachDayFormat.dayLine(metric(), style: .packet(strainFactor: 1.0))
        XCTAssertFalse(line.contains("charge"))
        XCTAssertFalse(line.contains("effort"))
        XCTAssertFalse(line.contains("rest "))
        XCTAssertFalse(line.contains(":,"), "the packet has no comma after the day's colon")
    }

    func testDayLineIsTheDayTheSeparatorAndTheFieldsJoinedByCommas() {
        for style in [CoachDayStyle.coachContext, packetStyle] {
            let day = metric()
            XCTAssertEqual(CoachDayFormat.dayLine(day, style: style),
                           day.day + style.daySeparator
                               + CoachDayFormat.fields(day, style: style).joined(separator: ", "))
        }
    }

    func testBothStylesShareTheSameValueTokens() {
        let labels: [(coach: String, packet: String)] = [
            ("charge", "recovery"), ("effort", "strain"), ("rest", "sleep"), ("deep", "deep"),
            ("REM", "REM"), ("light", "light"), ("eff", "eff"), ("HRV", "HRV"), ("RHR", "RHR"),
        ]
        for day in CoachPacketFixture.days + [metric(), emptyMetric()] {
            let coach = CoachDayFormat.fields(day, style: .coachContext)
            let packet = CoachDayFormat.fields(day, style: .packet(strainFactor: 1.0))
            XCTAssertEqual(coach.count, 9, day.day)
            XCTAssertEqual(packet.count, 9, day.day)
            guard coach.count == 9, packet.count == 9 else { continue }
            for (index, label) in labels.enumerated() {
                XCTAssertTrue(coach[index].hasPrefix(label.coach + " "), coach[index])
                XCTAssertTrue(packet[index].hasPrefix(label.packet + " "), packet[index])
                XCTAssertEqual(String(coach[index].dropFirst(label.coach.count + 1)),
                               String(packet[index].dropFirst(label.packet.count + 1)),
                               "\(day.day) field \(index)")
            }
        }
    }

    // MARK: - Absent values

    func testEveryAbsentFieldPrintsTheDashAndNoFieldIsDropped() {
        XCTAssertEqual(CoachDayFormat.notMeasured, dash)
        XCTAssertEqual(CoachDayFormat.fields(emptyMetric(), style: packetStyle),
                       ["recovery \(dash)", "strain \(dash)", "sleep \(dash)", "deep \(dash)",
                        "REM \(dash)", "light \(dash)", "eff \(dash)", "HRV \(dash)", "RHR \(dash)"])
        XCTAssertEqual(CoachDayFormat.dayLine(emptyMetric(), style: packetStyle),
                       "2031-03-07: recovery —, strain —, sleep —, deep —, REM —, light —, eff —, "
                           + "HRV —, RHR —")
        XCTAssertEqual(CoachDayFormat.dayLine(emptyMetric(), style: .coachContext),
                       "2031-03-07:, charge —, effort —, rest —, deep —, REM —, light —, eff —, "
                           + "HRV —, RHR —")
    }

    func testEachSingleAbsentFieldPrintsItsOwnDashAndLeavesTheOthers() {
        let full = CoachDayFormat.fields(metric(), style: packetStyle)
        let variants: [DailyMetric] = [
            metric(recovery: nil), metric(strain: nil), metric(sleep: nil), metric(deep: nil),
            metric(rem: nil), metric(light: nil), metric(eff: nil), metric(hrv: nil), metric(rhr: nil),
        ]
        let labels = ["recovery", "strain", "sleep", "deep", "REM", "light", "eff", "HRV", "RHR"]
        for (index, variant) in variants.enumerated() {
            var expected = full
            guard expected.count == 9 else { return XCTFail("nine fields expected") }
            expected[index] = labels[index] + " " + dash
            XCTAssertEqual(CoachDayFormat.fields(variant, style: packetStyle), expected, labels[index])
        }
    }

    func testAnAbsentValueNeverPrintsAsZero() {
        let fields = CoachDayFormat.fields(emptyMetric(), style: packetStyle)
            + CoachDayFormat.fields(emptyMetric(), style: .coachContext)
        for field in fields {
            XCTAssertFalse(field.contains("0"), field)
        }
        XCTAssertFalse(CoachDayFormat.primaryAveragesLine([], style: packetStyle).contains("0"))
        XCTAssertFalse(CoachDayFormat.vitalsAveragesLine([]).contains("0"))
    }

    func testAMeasuredZeroIsPrintedAsZeroAndNotAsTheDash() {
        let zero = metric(recovery: 0, strain: 0, sleep: 0, deep: 0, rem: 0, light: 0, hrv: 0, rhr: 0)
        XCTAssertEqual(CoachDayFormat.dayLine(zero, style: packetStyle),
                       "2031-03-03: recovery 0, strain 0.0, sleep 0.0h, deep 0.0h, REM 0.0h, "
                           + "light 0.0h, eff 91%, HRV 0ms, RHR 0bpm")
    }

    // MARK: - Strain factor

    func testStrainFactorScalesTheLineAndTheAverage() {
        let day = metric(strain: 47)
        XCTAssertEqual(field(1, of: day, style: .packet(strainFactor: 0.21)), "strain 9.9")
        XCTAssertEqual(field(1, of: day, style: .packet(strainFactor: 1.0)), "strain 47.0")
        XCTAssertEqual(field(1, of: day, style: .packet(strainFactor: 0.5)), "strain 23.5")
        // Stored 20 and 60: the mean of the scaled values is 40 × 0.21 = 8.4.
        let rows = [metric("2031-03-03", strain: 20), metric("2031-03-04", strain: 60)]
        XCTAssertTrue(CoachDayFormat.primaryAveragesLine(rows, style: .packet(strainFactor: 0.21))
            .contains("strain: 8.4,"))
        XCTAssertTrue(CoachDayFormat.primaryAveragesLine(rows, style: .packet(strainFactor: 1.0))
            .contains("strain: 40.0,"))
        // The factor touches strain and nothing else.
        let scaled = CoachDayFormat.fields(day, style: .packet(strainFactor: 0.21))
        let plain = CoachDayFormat.fields(day, style: .packet(strainFactor: 1.0))
        XCTAssertEqual(scaled.count, 9)
        XCTAssertEqual(plain.count, 9)
        guard scaled.count == 9, plain.count == 9 else { return }
        for index in [0, 2, 3, 4, 5, 6, 7, 8] {
            XCTAssertEqual(scaled[index], plain[index])
        }
    }

    func testStrainFactorOfOneReproducesTheStoredValue() {
        for stored in [0.0, 0.04, 0.05, 6.25, 12.345, 47.0, 99.95, 100.0] {
            let day = metric(strain: stored)
            XCTAssertEqual(field(1, of: day, style: .coachContext),
                           "effort " + String(format: "%.1f", stored))
            XCTAssertEqual(field(1, of: day, style: .packet(strainFactor: 1.0)),
                           "strain " + String(format: "%.1f", stored))
        }
    }

    // MARK: - Rounding (F3)

    func testHalvesRoundAwayFromZero() {
        XCTAssertEqual(field(0, of: metric(recovery: 62.5), style: packetStyle), "recovery 63")
        XCTAssertEqual(field(0, of: metric(recovery: 61.5), style: packetStyle), "recovery 62")
        XCTAssertEqual(field(0, of: metric(recovery: 62.49), style: packetStyle), "recovery 62")
        XCTAssertEqual(field(7, of: metric(hrv: 58.5), style: packetStyle), "HRV 59ms")
        XCTAssertEqual(field(7, of: metric(hrv: 57.5), style: packetStyle), "HRV 58ms")
        // Two rows of 62 and 63 average 62.5, which rounds up; banker's rounding would give 62.
        let rows = [metric("2031-03-03", recovery: 62), metric("2031-03-04", recovery: 63)]
        XCTAssertTrue(CoachDayFormat.primaryAveragesLine(rows, style: packetStyle)
            .hasPrefix("recovery: 63,"))
    }

    // MARK: - Efficiency

    func testEfficiencyStoredAsAPercentageIsNotMultipliedAgain() {
        XCTAssertEqual(CoachDayFormat.efficiencyPercent(0.94), "94%")
        XCTAssertEqual(CoachDayFormat.efficiencyPercent(94), "94%")
        XCTAssertEqual(CoachDayFormat.efficiencyPercent(91.4), "91%")
        XCTAssertEqual(CoachDayFormat.efficiencyPercent(100), "100%")
        XCTAssertEqual(field(6, of: metric(eff: 94), style: packetStyle), "eff 94%")
        XCTAssertEqual(field(6, of: metric(eff: 0.94), style: .coachContext), "eff 94%")
    }

    func testEfficiencyOutsideItsRangePrintsTheDash() {
        XCTAssertEqual(CoachDayFormat.efficiencyPercent(nil), dash)
        // The lower edge: zero and below are absent, the smallest positive fraction is a value.
        XCTAssertEqual(CoachDayFormat.efficiencyPercent(0), dash)
        XCTAssertEqual(CoachDayFormat.efficiencyPercent(-0.5), dash)
        XCTAssertEqual(CoachDayFormat.efficiencyPercent(-94), dash)
        XCTAssertEqual(CoachDayFormat.efficiencyPercent(0.01), "1%")
        // The upper edge of a fraction: exactly 1 is 100%, one step above is outside (0, 1].
        XCTAssertEqual(CoachDayFormat.efficiencyPercent(1.0), "100%")
        XCTAssertEqual(CoachDayFormat.efficiencyPercent(1.0.nextUp), dash)
        XCTAssertEqual(CoachDayFormat.efficiencyPercent(1.2), dash)
        // The percentage threshold: exactly 1.5 is not divided, one step above is.
        XCTAssertEqual(CoachDayFormat.efficiencyPercent(1.5), dash)
        XCTAssertEqual(CoachDayFormat.efficiencyPercent(1.5.nextUp), "2%")
        // A percentage above 100 is outside the range after division.
        XCTAssertEqual(CoachDayFormat.efficiencyPercent(101), dash)
        XCTAssertEqual(CoachDayFormat.efficiencyPercent(150), dash)
        XCTAssertEqual(CoachDayFormat.efficiencyPercent(9400), dash)
        // Every one of these equals what the in-app Coach printed before the extraction.
        for raw in [0, -0.5, 0.01, 1.0, 1.0.nextUp, 1.2, 1.5, 1.5.nextUp, 94, 100, 101, 150, 9400] {
            XCTAssertEqual(CoachDayFormat.efficiencyPercent(raw),
                           FrozenLegacy.efficiencyPercentOrDash(raw), "\(raw)")
        }
    }

    // MARK: - Non-finite values (F1)

    func testNonFiniteAndHugeValuesPrintTheDashAndDoNotTrap() {
        let bad: [Double] = [.nan, .signalingNaN, .infinity, -.infinity, 1e300, -1e300,
                             1e15.nextUp, -(1e15.nextUp), .greatestFiniteMagnitude]
        for value in bad {
            let day = metric(recovery: value, strain: value, sleep: value, deep: value, rem: value,
                             light: value, eff: value, hrv: value, rhr: 54)
            for style in [CoachDayStyle.coachContext, packetStyle] {
                let fields = CoachDayFormat.fields(day, style: style)
                XCTAssertEqual(fields.count, 9, "\(value)")
                guard fields.count == 9 else { continue }
                for index in 0..<8 {
                    XCTAssertTrue(fields[index].hasSuffix(" " + dash), "\(value): \(fields[index])")
                }
                XCTAssertEqual(fields[8], "RHR 54bpm")
            }
            XCTAssertEqual(CoachDayFormat.efficiencyPercent(value), dash, "\(value)")
        }
    }

    func testAValueOfExactlyTenToTheFifteenthIsStillPrinted() {
        // F1 drops a magnitude ABOVE 1e15; the bound itself is a value.
        let day = metric(recovery: 1e15, strain: -1e15, hrv: -1e15)
        let fields = CoachDayFormat.fields(day, style: .coachContext)
        XCTAssertEqual(fields.count, 9)
        guard fields.count == 9 else { return }
        XCTAssertEqual(fields[0], "charge 1000000000000000")
        XCTAssertEqual(fields[1], "effort -1000000000000000.0")
        XCTAssertEqual(fields[7], "HRV -1000000000000000ms")
        XCTAssertEqual(CoachDayFormat.dayLine(day, style: .coachContext), FrozenLegacy.dayLine(day))
    }

    func testNonFiniteValuesAreLeftOutOfTheAverages() {
        let rows = [
            metric("2031-03-03", recovery: .nan, strain: .infinity, sleep: -.infinity, hrv: 1e300,
                   spo2: .nan, skin: .infinity, resp: .nan, kcal: 1e300),
            metric("2031-03-04", recovery: 60, strain: 40, sleep: 420, hrv: 50, rhr: 52, spo2: 96,
                   skin: 0.4, resp: 14.5, steps: 8000, kcal: 500),
        ]
        // Recovery, strain, sleep and HRV average over the one finite row; RHR is a whole number on
        // both rows (54 and 52) and averages 53.
        XCTAssertEqual(CoachDayFormat.primaryAveragesLine(rows, style: .coachContext),
                       "charge: 60, effort: 40.0, sleep: 7.0h, HRV: 50 ms, RHR: 53 bpm")
        XCTAssertEqual(CoachDayFormat.vitalsAveragesLine(rows),
                       "SpO2: 96%, respiration: 14.5/min, skin-temp deviation: 0.4°C, "
                           + "steps: 8000/day, active energy: 500kcal/day")
        let allBad = [metric(recovery: .nan, strain: .nan, sleep: .nan, hrv: .nan, rhr: nil)]
        XCTAssertEqual(CoachDayFormat.primaryAveragesLine(allBad, style: packetStyle),
                       "recovery: —, strain: —, sleep: —h, HRV: — ms, RHR: — bpm")
    }

    // MARK: - Averages

    func testPrimaryAveragesMatchTheFrozenLegacyLine() {
        let rows = CoachPacketFixture.days
        // Hand-computed over the thirteen fixture rows with factor 1.0: recovery 766 / 12 = 63.83,
        // strain 515 / 13 = 39.62, sleep 5280 / 12 = 440 min = 7.33 h, HRV 704 / 12 = 58.67,
        // RHR 644 / 12 = 53.67.
        let literal = "charge: 64, effort: 39.6, sleep: 7.3h, HRV: 59 ms, RHR: 54 bpm"
        XCTAssertEqual(CoachDayFormat.primaryAveragesLine(rows, style: .coachContext), literal)
        XCTAssertEqual(FrozenLegacy.primaryAverages(rows), literal, "the frozen copy must not drift")
        // SPEC-AMBIGUITY: §6.1 writes the template as "<sleep>: Ch", which with the Coach style's sleep
        // label would print "rest:". The in-app Coach prints "sleep:" on this line (and "rest" only on
        // the day line), and §8 requires its bytes unchanged, so the word here is "sleep" in both styles.
        XCTAssertTrue(CoachDayFormat.primaryAveragesLine(rows, style: .coachContext).contains(", sleep: "))
        XCTAssertFalse(CoachDayFormat.primaryAveragesLine(rows, style: .coachContext).contains("rest"))
    }

    func testPacketStyleAveragesUseThePacketLabelsAndFactor() {
        XCTAssertEqual(CoachDayFormat.primaryAveragesLine(CoachPacketFixture.days, style: packetStyle),
                       "recovery: 64, strain: 8.3, sleep: 7.3h, HRV: 59 ms, RHR: 54 bpm")
    }

    func testVitalsAveragesMatchTheFrozenLegacyLine() {
        let rows = [
            metric("2031-03-03", spo2: 96, skin: 0.2, resp: 14.0, steps: 9120, kcal: 510),
            metric("2031-03-04", spo2: 97, skin: -0.4, resp: 15.6, steps: 11240, kcal: 640),
            metric("2031-03-05", spo2: nil, skin: nil, resp: nil, steps: nil, kcal: nil),
        ]
        // SpO2 193 / 2 = 96.5 rounds to 97; respiration 29.6 / 2 = 14.8; skin (0.2 − 0.4) / 2 = −0.1;
        // steps 20360 / 2 = 10180; energy 1150 / 2 = 575. The third row measured none of them.
        let literal = "SpO2: 97%, respiration: 14.8/min, skin-temp deviation: -0.1°C, "
            + "steps: 10180/day, active energy: 575kcal/day"
        XCTAssertEqual(FrozenLegacy.vitalsAverages(rows), literal, "the frozen copy must not drift")
        XCTAssertEqual(CoachDayFormat.vitalsAveragesLine(rows), literal)
    }

    func testAveragesOfNoRowsPrintDashesWithTheirUnits() {
        XCTAssertEqual(CoachDayFormat.primaryAveragesLine([], style: .coachContext),
                       "charge: —, effort: —, sleep: —h, HRV: — ms, RHR: — bpm")
        XCTAssertEqual(CoachDayFormat.primaryAveragesLine([], style: packetStyle),
                       "recovery: —, strain: —, sleep: —h, HRV: — ms, RHR: — bpm")
        XCTAssertEqual(CoachDayFormat.vitalsAveragesLine([]),
                       "SpO2: —%, respiration: —/min, skin-temp deviation: —°C, steps: —/day, "
                           + "active energy: —kcal/day")
        // Rows that exist but measured nothing average to the same dashes, never to zero.
        let unmeasured = [emptyMetric("2031-03-07"), emptyMetric("2031-03-08")]
        XCTAssertEqual(CoachDayFormat.primaryAveragesLine(unmeasured, style: packetStyle),
                       "recovery: —, strain: —, sleep: —h, HRV: — ms, RHR: — bpm")
        XCTAssertEqual(CoachDayFormat.primaryAveragesLine([], style: .coachContext),
                       FrozenLegacy.primaryAverages([]))
        XCTAssertEqual(CoachDayFormat.vitalsAveragesLine([]), FrozenLegacy.vitalsAverages([]))
    }

    func testAnAverageSkipsAbsentValuesInsteadOfCountingThemAsZero() {
        // 60 and an unmeasured night average 60, not 30.
        let rows = [metric("2031-03-03", recovery: 60, strain: 40, sleep: 420, hrv: 50, rhr: 52),
                    emptyMetric("2031-03-04")]
        XCTAssertEqual(CoachDayFormat.primaryAveragesLine(rows, style: .coachContext),
                       "charge: 60, effort: 40.0, sleep: 7.0h, HRV: 50 ms, RHR: 52 bpm")
    }

    // MARK: - Determinism and order

    func testTheSameRowsGiveTheSameTextAndAveragesIgnoreRowOrder() {
        let rows = CoachPacketFixture.days
        XCTAssertEqual(CoachDayFormat.primaryAveragesLine(rows, style: packetStyle),
                       CoachDayFormat.primaryAveragesLine(rows, style: packetStyle))
        XCTAssertEqual(CoachDayFormat.dayLine(rows[0], style: packetStyle),
                       CoachDayFormat.dayLine(rows[0], style: packetStyle))
        // The fixture's values are whole numbers, so their sums are exact in any order.
        XCTAssertEqual(CoachDayFormat.primaryAveragesLine(Array(rows.reversed()), style: packetStyle),
                       CoachDayFormat.primaryAveragesLine(rows, style: packetStyle))
    }

    // MARK: - Generated inputs

    /// A random row in the range real rows take, with each field absent about one time in five.
    /// Values stay finite and far below 1e15, where the legacy code is defined.
    private func generatedMetric(_ g: inout CoachPacketFixture.Generator, index: Int) -> DailyMetric {
        func maybe(_ g: inout CoachPacketFixture.Generator, _ range: ClosedRange<Double>) -> Double? {
            g.chance(20) ? nil : g.double(range)
        }
        let efficiency: Double?
        switch g.int(0...9) {
        case 0: efficiency = nil
        case 1: efficiency = g.pick([0, 1.0, 1.5, 1.5.nextUp, 1.0.nextUp, 100, 101, -0.2])
        case 2, 3, 4: efficiency = g.double(30...110)
        default: efficiency = g.double(0...1.6)
        }
        return DailyMetric(
            day: CutScorecardFixture.day("2031-01-01", index),
            totalSleepMin: maybe(&g, 0...900), efficiency: efficiency,
            deepMin: maybe(&g, 0...300), remMin: maybe(&g, 0...300), lightMin: maybe(&g, 0...600),
            disturbances: nil, restingHr: g.chance(20) ? nil : g.int(30...120),
            avgHrv: maybe(&g, 0...250), recovery: maybe(&g, -5...105), strain: maybe(&g, -1...101),
            exerciseCount: nil, spo2Pct: maybe(&g, 80...100), skinTempDevC: maybe(&g, -3...3),
            respRateBpm: maybe(&g, 8...30), steps: g.chance(20) ? nil : g.int(0...40_000),
            activeKcalEst: maybe(&g, 0...3000))
    }

    func testGeneratedSpreadMatchesTheFrozenLegacyFormatter() {
        var g = CoachPacketFixture.Generator(seed: 0x5EED_C0AC_0002)
        var index = 0
        for round in 0..<500 {
            let day = generatedMetric(&g, index: index)
            index += 1
            XCTAssertEqual(CoachDayFormat.dayLine(day, style: .coachContext),
                           FrozenLegacy.dayLine(day), "row \(round)")
            XCTAssertEqual(CoachDayFormat.efficiencyPercent(day.efficiency),
                           FrozenLegacy.efficiencyPercentOrDash(day.efficiency), "row \(round)")
            var list: [DailyMetric] = []
            for _ in 0..<g.int(0...30) {
                list.append(generatedMetric(&g, index: index))
                index += 1
            }
            XCTAssertEqual(CoachDayFormat.primaryAveragesLine(list, style: .coachContext),
                           FrozenLegacy.primaryAverages(list), "list \(round)")
            XCTAssertEqual(CoachDayFormat.vitalsAveragesLine(list),
                           FrozenLegacy.vitalsAverages(list), "list \(round)")
            // The packet style changes labels, the separator and the strain factor, and nothing else.
            let coach = CoachDayFormat.fields(day, style: .coachContext)
            let packet = CoachDayFormat.fields(day, style: .packet(strainFactor: 1.0))
            XCTAssertEqual(coach.count, 9)
            XCTAssertEqual(packet.count, 9)
            guard coach.count == 9, packet.count == 9 else { continue }
            XCTAssertEqual(Array(coach[3...]), Array(packet[3...]), "row \(round)")
        }
    }
}
