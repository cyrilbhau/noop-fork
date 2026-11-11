import XCTest
import WhoopStore
@testable import StrandAnalytics

// API ASSUMED BY THESE TESTS (stage 2 review fixes, rulings A18 and A20)
//
//   enum CoachPacket {
//       /// Every owner-typed or imported string the renderer passes through `sanitize`, uncut and
//       /// unsanitised: the phase name when the scorecard is evaluated with a phase, and every
//       /// workout's sport, in input order.
//       static func freeText(of input: CoachPacketInput) -> [String]
//       /// The scan the assembler runs (A20): the rendered text and every string of `freeText(of:)`,
//       /// each scanned on its own. `identifiers` nil means the list could not be read; the result is
//       /// then never empty. Descriptions are not repeated.
//       static func scan(_ input: CoachPacketInput, rendered text: String, identifiers: [String]?) -> [String]
//   }
//
// and `privacyViolations(in:identifiers:)` also searching for an identifier in the form `sanitize`
// prints it (white space collapsed, ends trimmed, `"` as `'`), before any cut.

/// Ruling A18: the shared day formatter changes the in-app Coach's text only for impossible values.
final class CoachDayFormatLegacyIdentityTests: XCTestCase {

    /// The in-app Coach's day line and averages as they stood before stage 2's extraction, copied from
    /// the private oracle in `CoachDayFormatTests` (which is never edited).
    private enum Legacy {
        static func dayLine(_ d: DailyMetric) -> String {
            var parts: [String] = [d.day + ":"]
            parts.append("charge " + (d.recovery.map { "\(Int($0.rounded()))" } ?? "—"))
            parts.append("effort " + (d.strain.map { String(format: "%.1f", $0) } ?? "—"))
            parts.append("rest " + (d.totalSleepMin.map { String(format: "%.1fh", $0 / 60) } ?? "—"))
            parts.append("deep " + hours(d.deepMin))
            parts.append("REM " + hours(d.remMin))
            parts.append("light " + hours(d.lightMin))
            parts.append("eff " + efficiency(d.efficiency))
            parts.append("HRV " + (d.avgHrv.map { "\(Int($0.rounded()))ms" } ?? "—"))
            parts.append("RHR " + (d.restingHr.map { "\($0)bpm" } ?? "—"))
            return parts.joined(separator: ", ")
        }
        static func hours(_ minutes: Double?) -> String { minutes.map { String(format: "%.1fh", $0 / 60) } ?? "—" }
        static func efficiency(_ raw: Double?) -> String {
            guard var e = raw, e > 0 else { return "—" }
            if e > 1.5 { e /= 100 }
            guard e > 0, e <= 1 else { return "—" }
            return "\(Int((e * 100).rounded()))%"
        }
        static func avgOne(_ xs: [Double]) -> String {
            guard !xs.isEmpty else { return "—" }
            return String(format: "%.1f", xs.reduce(0, +) / Double(xs.count))
        }
        static func avgSleepHours(_ days: [DailyMetric]) -> String {
            let mins = days.compactMap { $0.totalSleepMin }
            guard !mins.isEmpty else { return "—" }
            return String(format: "%.1f", (mins.reduce(0, +) / Double(mins.count)) / 60)
        }
        static func avgInt(_ xs: [Double]) -> String {
            guard !xs.isEmpty else { return "—" }
            return "\(Int((xs.reduce(0, +) / Double(xs.count)).rounded()))"
        }
        static func primaryAverages(_ rows: [DailyMetric]) -> String {
            "charge: \(avgInt(rows.compactMap { $0.recovery }))"
                + ", effort: \(avgOne(rows.compactMap { $0.strain }))"
                + ", sleep: \(avgSleepHours(rows))h"
                + ", HRV: \(avgInt(rows.compactMap { $0.avgHrv })) ms"
                + ", RHR: \(avgInt(rows.compactMap { $0.restingHr.map(Double.init) })) bpm"
        }
        static func vitalsAverages(_ rows: [DailyMetric]) -> String {
            "SpO2: \(avgInt(rows.compactMap { $0.spo2Pct }))%"
                + ", respiration: \(avgOne(rows.compactMap { $0.respRateBpm }))/min"
                + ", skin-temp deviation: \(avgOne(rows.compactMap { $0.skinTempDevC }))°C"
                + ", steps: \(avgInt(rows.compactMap { $0.steps.map(Double.init) }))/day"
                + ", active energy: \(avgInt(rows.compactMap { $0.activeKcalEst }))kcal/day"
        }
    }

    private func row(_ day: String, _ v: [Double?]) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: v[0], efficiency: v[1], deepMin: v[2], remMin: v[3], lightMin: v[4],
                    disturbances: nil, restingHr: 54, avgHrv: v[5], recovery: v[6], strain: v[7],
                    exerciseCount: nil, spo2Pct: v[8], skinTempDevC: v[9], respRateBpm: v[10], steps: 8_000,
                    activeKcalEst: v[11])
    }

    /// True for a value F1 prints as the dash: non-finite, or a magnitude above 1e15.
    private func impossible(_ x: Double) -> Bool { !x.isFinite || abs(x) > 1e15 }

    func testOnlyNonFiniteOrOverTenToTheFifteenthValuesChangeTheInAppCoachText() {
        // Finite and within 1e15, the bound itself included: byte-identical, field for field.
        let inRange: [Double] = [0, -0, 0.04, 0.05, 0.25, 1, 1.5, 1.5.nextUp, 47.25, 62.5, 444, 9_999.95,
                                 -3.75, 1.234_567e9, 98_765_432_101.5, 9.99e14, 1e15, -1e15, 1e15.nextDown,
                                 .leastNonzeroMagnitude, -.leastNonzeroMagnitude]
        var g = SplitMix(seed: 0xA18)
        for index in 0..<400 {
            let values: [Double?] = (0..<12).map { _ in
                if g.next() % 6 == 0 { return nil }
                return inRange[Int(g.next() % UInt64(inRange.count))]
            }
            let day = row("2031-03-\(String(format: "%02d", 1 + index % 28))", values)
            XCTAssertEqual(CoachDayFormat.dayLine(day, style: .coachContext), Legacy.dayLine(day), "row \(index)")
            let list = [day, row("2031-03-02", values.reversed())]
            XCTAssertEqual(CoachDayFormat.primaryAveragesLine(list, style: .coachContext),
                           Legacy.primaryAverages(list), "list \(index)")
            XCTAssertEqual(CoachDayFormat.vitalsAveragesLine(list), Legacy.vitalsAverages(list), "list \(index)")
        }

        // The impossible values: the new text is the legacy text with each such field printed as the
        // dash, which is exactly the legacy text for the same row with that field absent. Whole-number
        // fields get only impossible values below Int.max, because the legacy code traps on any other.
        let bad: [Double] = [.infinity, -.infinity, .nan, 2e15, -2e15, 1e15.nextUp, 1e300]
        for value in bad {
            let wholeNumber: Double? = abs(value) < 9e18 ? value : nil
            let raw: [Double?] = [value, 0.91, value, value, value, wholeNumber, wholeNumber, value,
                                  value, value, value, wholeNumber]
            let cleaned = raw.map { $0.flatMap { impossible($0) ? nil : $0 } }
            let day = row("2031-03-03", raw)
            let dashed = row("2031-03-03", cleaned)
            XCTAssertEqual(CoachDayFormat.dayLine(day, style: .coachContext), Legacy.dayLine(dashed), "\(value)")
            XCTAssertNotEqual(CoachDayFormat.dayLine(day, style: .coachContext), Legacy.dayLine(day),
                              "\(value) is impossible, so the legacy text differs")
            // In an average the impossible value is left out; the finite row alone is the mean.
            let fine = row("2031-03-04", [420, 0.9, 60, 90, 240, 50, 60, 40, 96, 0.4, 14.5, 500])
            XCTAssertEqual(CoachDayFormat.primaryAveragesLine([day, fine], style: .coachContext),
                           Legacy.primaryAverages([dashed, fine]), "\(value)")
            XCTAssertEqual(CoachDayFormat.vitalsAveragesLine([day, fine]), Legacy.vitalsAverages([dashed, fine]),
                           "\(value)")
        }
    }
}

/// A deterministic generator, so a failure names a reproducible row.
private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Ruling A20: the privacy scan sees what the owner typed, before it is sanitised and cut, and fails
/// closed when the identifier list cannot be read.
final class CoachPacketReviewFixTests: XCTestCase {

    private typealias F = CoachPacketFixture

    private func input(phase name: String? = nil, sports: [String] = []) -> CoachPacketInput {
        F.full { draft in
            if let name {
                let p = F.phase
                draft.setResult(F.result(), phase: CoachPacketPhase(
                    name: name, startDay: p.startDay, targetWeightKg: p.targetWeightKg,
                    rateLowPercentPerWeek: p.rateLowPercentPerWeek, rateHighPercentPerWeek: p.rateHighPercentPerWeek))
            }
            if !sports.isEmpty {
                draft.workouts = sports.enumerated().map { index, sport in
                    F.workout("2031-03-1\(index % 6)", 7, 0, sport, .manual, min: 30)
                }
            }
        }.input
    }

    // MARK: Finding 3: the identifier in the form sanitize prints it

    func testAnIdentifierIsFoundInTheFormSanitizePrintsIt() {
        for id in ["Fixture \"FP\" Strap", "Fixture  Strap", "Fixture\nStrap", " Fixture Band ", "Fixture\u{00A0}Band"] {
            let text = "phase: \"\(CoachPacket.sanitize(id))\" (cut)"
            XCTAssertFalse(CoachPacket.privacyViolations(in: text, identifiers: [id]).isEmpty,
                           "\(id.debugDescription) printed as \(text.debugDescription) was not found")
        }
        // The rendered packet, the identifier typed as the phase name and as a sport.
        for id in ["Fixture \"FP\" Strap", "Fixture  Strap", "Fixture\tStrap"] {
            for packet in [input(phase: id), input(sports: [id])] {
                let text = CoachPacket.render(packet)
                XCTAssertFalse(CoachPacket.privacyViolations(in: text, identifiers: [id]).isEmpty, id.debugDescription)
            }
        }
        // Normalising the identifier never shortens it below the minimum, nor turns blank into "unnamed".
        XCTAssertEqual(CoachPacket.privacyViolations(in: "phase: \"unnamed\"", identifiers: ["   ", "\n\n\n\n"]), [])
        XCTAssertEqual(CoachPacket.privacyViolations(in: "a b c", identifiers: [" a b "]), [])
    }

    // MARK: Finding 4: the uncut free text

    func testFreeTextReturnsTheUncutPhaseNameAndEverySport() {
        let long = "Spring cut, numbers taken from a long description of the plan"
        let packet = input(phase: long, sports: ["rowing", "Fixture \"FP\"\nStrap"])
        XCTAssertEqual(CoachPacket.freeText(of: packet), [long, "rowing", "Fixture \"FP\"\nStrap"])
        XCTAssertEqual(CoachPacket.freeText(of: F.full { $0.scorecard = .switchedOff; $0.workouts = [] }.input), [])
        XCTAssertEqual(CoachPacket.freeText(of: F.full { $0.setResult(F.result(), phase: nil); $0.workouts = [] }.input), [])
        // A text whose section is off does not leave, so it is not scanned.
        let noScorecard = F.full { $0.sections.remove(.scorecard) }.input
        XCTAssertEqual(CoachPacket.freeText(of: noScorecard), F.workouts.map(\.sport))
        let noActivity = F.full { $0.sections.remove(.activity) }.input
        XCTAssertEqual(CoachPacket.freeText(of: noActivity), [F.phase.name])
    }

    func testASensitiveValueCutByTheFreeTextLimitIsFound() {
        let nickname = "Fixture Person's Strap"
        let planted = [
            "Cut block planned with fixture.person@example-mail.com",
            "Spring cut, numbers taken from \(nickname)",
            "Phase one of the cut 12345678-1234-1234-1234-123456789ABC",
        ]
        for value in planted {
            XCTAssertGreaterThan(value.utf8.count, CoachPacket.freeTextByteLimit)
            for packet in [input(phase: value), input(sports: [value])] {
                let text = CoachPacket.render(packet)
                // The rendered text alone misses it: the cut removed what identifies.
                XCTAssertEqual(CoachPacket.privacyViolations(in: text, identifiers: [nickname]), [], value)
                XCTAssertFalse(CoachPacket.scan(packet, rendered: text, identifiers: [nickname]).isEmpty,
                               "\(value) was cut before the scan saw it")
            }
        }
        // A harmless long name is still a packet.
        let harmless = input(phase: "A long and entirely harmless phase name for the spring cut block")
        XCTAssertEqual(CoachPacket.scan(harmless, rendered: CoachPacket.render(harmless), identifiers: [nickname]), [])
    }

    func testTheScanStillReadsTheRenderedText() {
        let packet = input()
        let text = CoachPacket.render(packet) + "planted fixture.person@example.invalid\n"
        XCTAssertFalse(CoachPacket.scan(packet, rendered: text, identifiers: []).isEmpty)
        XCTAssertEqual(CoachPacket.scan(packet, rendered: CoachPacket.render(packet), identifiers: F.identifiers), [])
    }

    func testAFindingInTheTextAndInTheTypedValueIsCountedOnce() {
        let packet = input(phase: "Fixture Band cut")
        let findings = CoachPacket.scan(packet, rendered: CoachPacket.render(packet), identifiers: [F.nickname])
        XCTAssertEqual(findings.count, 1, "\(findings)")
    }

    // MARK: Finding 2: an unreadable identifier list

    func testAnUnreadableIdentifierListIsAFinding() {
        let packet = input()
        XCTAssertFalse(CoachPacket.scan(packet, rendered: CoachPacket.render(packet), identifiers: nil).isEmpty)
        XCTAssertEqual(CoachPacket.scan(packet, rendered: CoachPacket.render(packet), identifiers: []), [])
    }
}
