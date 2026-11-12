import XCTest
import WhoopStore
@testable import StrandAnalytics

// API ASSUMED BY THESE TESTS
//
// From the stage-2 implementation (docs/personal/superapp/specs/stage-2.md §6.2):
//
//   enum CoachPacketSection: String, CaseIterable, Equatable {
//       case scorecard, weighIns = "weigh-ins", recoverySleep = "recovery-sleep", trends, activity
//       var isOnByDefault: Bool { get }
//   }
//   enum CoachPacket {
//       static let formatName: String          // "NOOP-COACH-PACKET"
//       static let formatVersion: Int          // 1
//       static let weeklyRowLimit: Int         // 8
//       static let workoutRowLimit: Int        // 20
//       static let freeTextByteLimit: Int      // 48
//       static func render(_ input: CoachPacketInput) -> String
//       static func byteBudget(rangeDays: Int) -> Int
//       static func dayKeys(from start: String, to end: String) -> [String]
//       static func sanitize(_ text: String) -> String
//   }
//
// and the input types listed at the top of `CoachPacketFixture.swift`, each through its memberwise
// initialiser in declaration order.
//
// From the shared scaffolding (stage 6 §6.0), treated as given:
//
//   enum CanonicalDay {
//       static func number(_ key: String) -> Int?      // nil unless a canonical "yyyy-MM-dd" key
//       static func key(_ number: Int) -> String
//   }
//
// Existing API: `DailyMetric` (WhoopStore); `CutScorecardResult` and its parts, `CutScorecard.evaluate`
// (StrandAnalytics, stage 1); `CutScorecardFixture` (this test target, stage 1).

/// The packet renderer of stage 2 §6.2 and §7: the goldens, every line template, the grammar of
/// §7.12, input handling, the size budget and stability.
final class CoachPacketTests: XCTestCase {

    private typealias F = CoachPacketFixture
    private typealias G = CoachPacketGolden

    // MARK: - Helpers

    /// Compare two packet texts and, when they differ, name the first line that does.
    private func assertSameText(_ actual: String, _ expected: String, _ note: String = "",
                                file: StaticString = #filePath, line: UInt = #line) {
        guard actual != expected else { return }
        let a = actual.components(separatedBy: "\n")
        let e = expected.components(separatedBy: "\n")
        for index in 0..<max(a.count, e.count) {
            let got = index < a.count ? a[index] : "<no line>"
            let want = index < e.count ? e[index] : "<no line>"
            if got != want {
                XCTFail("\(note) line \(index + 1):\n  got:  \(got)\n  want: \(want)", file: file, line: line)
                return
            }
        }
        XCTFail("\(note) texts differ", file: file, line: line)
    }

    /// The one line of `text` that begins with `prefix`; fails when there is none or more than one.
    private func only(_ prefix: String, in text: String, file: StaticString = #filePath,
                      line: UInt = #line) -> String {
        let found = F.lines(startingWith: prefix, in: text)
        XCTAssertEqual(found.count, 1, "lines starting \"\(prefix)\"", file: file, line: line)
        return found.first ?? ""
    }

    /// The heading lines of a packet text, in order.
    private func headings(_ text: String) -> [String] {
        F.lines(text).filter { $0.hasPrefix("== ") }
    }

    /// The indented rows under `heading`.
    private func rows(_ heading: String, in text: String) -> [String] {
        (F.section(heading, in: text) ?? []).filter { $0.hasPrefix("  ") }
    }

    /// The day keys of the per-day rows under `heading`: rows of the form "  yyyy-MM-dd: …".
    private func dayRowKeys(_ heading: String, in text: String) -> [String] {
        rows(heading, in: text).compactMap { row in
            let chars = Array(row)
            guard chars.count >= 13, chars[12] == ":" else { return nil }
            return String(chars[2..<12])
        }
    }

    /// The workout rows of the activity section: rows of the form "  yyyy-MM-dd HH:MM …".
    private func workoutRows(_ text: String) -> [String] {
        rows("== ACTIVITY ==", in: text).filter { row in
            let chars = Array(row)
            return chars.count >= 13 && chars[12] == " " && chars[2] != "("
        }
    }

    private func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            XCTFail("bad pattern \(pattern)")
            return []
        }
        let whole = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: whole).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    /// A draft with no rows but the ones built from `hrv` and `rhr`, one per fixture day from the
    /// first, and only the trends section on.
    private func trendDraft(hrv: [Double?] = [], rhr: [Int?] = [],
                            hrvBaseline: CoachPacketBaseline? = F.hrvBaseline,
                            rhrBaseline: CoachPacketBaseline? = F.restingHrBaseline) -> F.Draft {
        var draft = F.empty
        draft.sections = [.trends]
        draft.hrvBaseline = hrvBaseline
        draft.restingHrBaseline = rhrBaseline
        draft.days = (0..<max(hrv.count, rhr.count)).map { index in
            F.row(F.rangeDays[index], hrv: index < hrv.count ? hrv[index] : nil,
                  rhr: index < rhr.count ? rhr[index] : nil)
        }
        return draft
    }

    /// The fixture with its scorecard result replaced.
    private func draft(result: CutScorecardResult, phase: CoachPacketPhase? = F.phase) -> F.Draft {
        var draft = F.full
        draft.setResult(result, phase: phase)
        return draft
    }

    private let g1HrvLine = "HRV: baseline 57 ms (typical 51 to 64, trusted, 21 nights); "
        + "range mean 59 ms over 12 nights (+2 vs baseline); "
        + "last 7 days mean 60 ms over 6 nights (+3 vs baseline); outside typical: 1 below, 2 above"
    private let g1RhrLine = "RHR: baseline 54 bpm (typical 52 to 56, trusted, 21 nights); "
        + "range mean 54 bpm over 12 nights (+0 vs baseline); "
        + "last 7 days mean 53 bpm over 6 nights (-1 vs baseline); outside typical: 1 below, 1 above"

    // MARK: - Fixture and constants

    func testFixtureScorecardIsStageOnesEvaluationOnTheReadDay() {
        // §13.3: the hand-built result claims to be stage 1's Fixture Person read on 2031-03-16.
        XCTAssertEqual(F.result(), CutScorecard.evaluate(CutScorecardFixture.input(today: F.rangeEnd)))
        let stageOne = CutScorecardFixture.phase
        XCTAssertEqual(F.phase.name, stageOne.name)
        XCTAssertEqual(F.phase.startDay, stageOne.startDay)
        XCTAssertEqual(F.phase.targetWeightKg, stageOne.targetWeightKg)
        XCTAssertEqual(F.phase.rateLowPercentPerWeek, stageOne.rateLowPercentPerWeek)
        XCTAssertEqual(F.phase.rateHighPercentPerWeek, stageOne.rateHighPercentPerWeek)
    }

    func testConstantsAndSectionIdsAreTheSpecifiedOnes() {
        XCTAssertEqual(CoachPacket.formatName, "NOOP-COACH-PACKET")
        XCTAssertEqual(CoachPacket.formatVersion, 2, "packet v2 (§7.12)")
        XCTAssertEqual(CoachPacket.weeklyRowLimit, 8)
        XCTAssertEqual(CoachPacket.workoutRowLimit, 20)
        XCTAssertEqual(CoachPacket.freeTextByteLimit, 48)
        XCTAssertEqual(CoachPacketSection.allCases.map(\.rawValue),
                       ["scorecard", "weigh-ins", "intake", "recovery-sleep", "trends", "activity", "events"])
        for section in CoachPacketSection.allCases {
            XCTAssertTrue(section.isOnByDefault, section.rawValue)
        }
        XCTAssertEqual(CoachPacketBodySource.labBook.rawValue, "lab-book")
        XCTAssertEqual(CoachPacketBodySource.appleHealth.rawValue, "apple-health")
        XCTAssertEqual(CoachPacketBodySource.profile.rawValue, "profile")
        XCTAssertEqual(CoachPacketStepSource.strap.rawValue, "strap")
        XCTAssertEqual(CoachPacketStepSource.appleHealth.rawValue, "apple-health")
        XCTAssertEqual(CoachPacketStepSource.strapEstimate.rawValue, "strap-estimate")
        XCTAssertEqual(CoachPacketWorkoutSource.whoop.rawValue, "whoop")
        XCTAssertEqual(CoachPacketWorkoutSource.appleHealth.rawValue, "apple-health")
        XCTAssertEqual(CoachPacketWorkoutSource.detected.rawValue, "detected")
        XCTAssertEqual(CoachPacketWorkoutSource.manual.rawValue, "manual")
        XCTAssertEqual(CoachPacketWorkoutSource.liftLog.rawValue, "lift-log")
        XCTAssertEqual(CoachPacketWorkoutSource.activityFile.rawValue, "activity-file")
    }

    // MARK: - Goldens

    func testFullFixtureMatchesGoldenG1() {
        XCTAssertEqual(G.g1.utf8.count, 7_173, "G1 regenerated once as version 2 (§7.12)")
        assertSameText(F.full.text, G.g1)
    }

    private func assertSectionOff(_ section: CoachPacketSection, heading: String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        var draft = F.full
        draft.sections.remove(section)
        let text = draft.text
        assertSameText(text, G.g1(withSectionsOff: [section.rawValue]), section.rawValue,
                       file: file, line: line)
        XCTAssertNil(F.section(heading, in: text), file: file, line: line)
        XCTAssertEqual(only("switched-off: ", in: text, file: file, line: line),
                       "switched-off: " + section.rawValue, file: file, line: line)
        XCTAssertFalse(only("sections: ", in: text, file: file, line: line)
            .contains(section.rawValue), file: file, line: line)
    }

    func testScorecardSectionOffMatchesGolden() {
        assertSectionOff(.scorecard, heading: "== SCORECARD ==")
        // The section switch hides the section only: the weekly block still comes from the result.
        var draft = F.full
        draft.sections.remove(.scorecard)
        XCTAssertEqual(rows("== WEIGH-INS ==", in: draft.text).count, 8)
    }

    func testWeighInsSectionOffMatchesGolden() {
        assertSectionOff(.weighIns, heading: "== WEIGH-INS ==")
    }

    func testRecoverySleepSectionOffMatchesGolden() {
        assertSectionOff(.recoverySleep, heading: "== RECOVERY AND SLEEP ==")
    }

    func testTrendsSectionOffMatchesGolden() {
        assertSectionOff(.trends, heading: "== TRENDS ==")
    }

    func testActivitySectionOffMatchesGolden() {
        assertSectionOff(.activity, heading: "== ACTIVITY ==")
    }

    func testEverySectionOffLeavesHeaderAndNotes() {
        var draft = F.full
        draft.sections = []
        let text = draft.text
        assertSameText(text, G.g1(withSectionsOff: Set(G.sectionOrder.map(\.id))))
        XCTAssertEqual(only("sections: ", in: text), "sections: none")
        XCTAssertEqual(only("switched-off: ", in: text),
                       "switched-off: scorecard, weigh-ins, intake, recovery-sleep, trends, activity, events")
        XCTAssertEqual(headings(text), ["== NOTES =="])
        XCTAssertEqual(F.lines(text).count, 8 + 1 + 7)
    }

    func testTwoSectionsOffAreListedInTheFixedOrder() {
        var draft = F.full
        draft.sections = [.activity, .weighIns, .trends]
        let text = draft.text
        assertSameText(text, G.g1(withSectionsOff: ["scorecard", "intake", "recovery-sleep", "events"]))
        XCTAssertEqual(only("sections: ", in: text), "sections: weigh-ins, trends, activity")
        XCTAssertEqual(only("switched-off: ", in: text), "switched-off: scorecard, intake, recovery-sleep, events")
    }

    func testNoDataAtAllMatchesGoldenG2() {
        assertSameText(F.empty.text, G.g2)
    }

    // MARK: - Header

    func testHeaderIsExactlyTheEightLines() {
        let lines = F.lines(F.full.text)
        XCTAssertEqual(Array(lines.prefix(9)), [
            "NOOP-COACH-PACKET v2",
            "generated: 2031-03-16T07:42:10+01:00",
            "range: 2031-03-03..2031-03-16 (14 days; the last day is today and is partial)",
            "sections: scorecard, weigh-ins, intake, recovery-sleep, trends, activity, events",
            "switched-off: none",
            "not-recorded-by-app: none",
            "units: kg, cm, g, hours (h), ms, bpm, steps, kcal, km; dates are YYYY-MM-DD in the phone's time zone",
            "missing: \"—\" means NOT MEASURED, never zero",
            "",
        ])
        // The generated-at text is printed as given: the renderer has no clock and no time zone.
        let other = F.full { $0.generatedAt = "2031-03-16T23:59:59-08:00" }.text
        XCTAssertEqual(F.line(1, of: other), "generated: 2031-03-16T23:59:59-08:00")
    }

    func testStrainScaleWordsFollowTheFactor() {
        func lead(_ factor: Double) -> String {
            only("per day, oldest first: ", in: F.full { $0.strainFactor = factor }.text)
        }
        let before = "per day, oldest first: recovery (0-100), strain ("
        let after = "), sleep (h), deep/REM/light (h), eff (%), HRV (ms), RHR (bpm)"
        XCTAssertEqual(lead(0.21), before + "0-21 scale" + after)
        XCTAssertEqual(lead(1.0), before + "0-100 scale" + after)
        // "Below 1" is the rule: one step under 1 is the 0-21 wording, 1 and above the 0-100 wording.
        XCTAssertEqual(lead(1.0.nextDown), before + "0-21 scale" + after)
        XCTAssertEqual(lead(1.0.nextUp), before + "0-100 scale" + after)
        // The rows follow the same factor as the words.
        let stored = F.full { $0.strainFactor = 1.0 }.text
        XCTAssertTrue(only("  2031-03-03: recovery", in: stored).contains(", strain 47.0, "))
        XCTAssertTrue(only("averages over ", in: stored).contains(", strain: 39.6, "))
    }

    // MARK: - Ranges and day keys

    func testRangeWithUnmeasuredDaysPrintsALineForEachDay() {
        let text = F.full.text
        XCTAssertEqual(dayRowKeys("== RECOVERY AND SLEEP ==", in: text), F.rangeDays)
        XCTAssertEqual(dayRowKeys("== ACTIVITY ==", in: text), F.rangeDays)
        XCTAssertEqual(only("  2031-03-07: recovery", in: text),
                       "  2031-03-07: recovery —, strain —, sleep —, deep —, REM —, light —, eff —, "
                           + "HRV —, RHR —")
        XCTAssertEqual(only("  2031-03-13: recovery", in: text),
                       "  2031-03-13: recovery —, strain 7.3, sleep —, deep —, REM —, light —, eff —, "
                           + "HRV —, RHR —")
        XCTAssertEqual(only("averages over ", in: text),
                       "averages over 13 of 14 days with data: recovery: 64, strain: 8.3, "
                           + "sleep: 7.3h, HRV: 59 ms, RHR: 54 bpm")
        // A row that exists but measured nothing still counts as a day with a row.
        let withEmptyRow = F.full { $0.days.append(F.row("2031-03-07")) }.text
        XCTAssertTrue(only("averages over ", in: withEmptyRow)
            .hasPrefix("averages over 14 of 14 days with data: "))
    }

    private func assertRange(_ start: String, _ end: String, lists expected: [String],
                             file: StaticString = #filePath, line: UInt = #line) {
        var draft = F.empty
        draft.rangeStartDay = start
        draft.rangeEndDay = end
        let text = draft.text
        XCTAssertEqual(F.line(2, of: text),
                       "range: \(start)..\(end) (\(expected.count) days; the last day is today and is partial)",
                       file: file, line: line)
        XCTAssertEqual(dayRowKeys("== RECOVERY AND SLEEP ==", in: text), expected, file: file, line: line)
        XCTAssertEqual(dayRowKeys("== ACTIVITY ==", in: text), expected, file: file, line: line)
        XCTAssertEqual(CoachPacket.dayKeys(from: start, to: end), expected, file: file, line: line)
    }

    func testRangeAcrossAMonthBoundaryListsEveryDay() {
        assertRange("2031-03-25", "2031-04-07", lists: [
            "2031-03-25", "2031-03-26", "2031-03-27", "2031-03-28", "2031-03-29", "2031-03-30",
            "2031-03-31", "2031-04-01", "2031-04-02", "2031-04-03", "2031-04-04", "2031-04-05",
            "2031-04-06", "2031-04-07",
        ])
    }

    func testRangeAcrossAYearBoundaryListsEveryDay() {
        assertRange("2030-12-26", "2031-01-08", lists: [
            "2030-12-26", "2030-12-27", "2030-12-28", "2030-12-29", "2030-12-30", "2030-12-31",
            "2031-01-01", "2031-01-02", "2031-01-03", "2031-01-04", "2031-01-05", "2031-01-06",
            "2031-01-07", "2031-01-08",
        ])
    }

    func testRangeAcrossTheEndOfFebruaryInALeapYear() {
        assertRange("2032-02-23", "2032-03-07", lists: [
            "2032-02-23", "2032-02-24", "2032-02-25", "2032-02-26", "2032-02-27", "2032-02-28",
            "2032-02-29", "2032-03-01", "2032-03-02", "2032-03-03", "2032-03-04", "2032-03-05",
            "2032-03-06", "2032-03-07",
        ])
        // 2031 is not a leap year, and neither is 2100.
        XCTAssertEqual(CoachPacket.dayKeys(from: "2031-02-27", to: "2031-03-02"),
                       ["2031-02-27", "2031-02-28", "2031-03-01", "2031-03-02"])
        XCTAssertEqual(CoachPacket.dayKeys(from: "2100-02-28", to: "2100-03-01"),
                       ["2100-02-28", "2100-03-01"])
        XCTAssertEqual(CoachPacket.dayKeys(from: "2031-02-29", to: "2031-03-02"), [])
    }

    func testDayKeysAcceptExactlyWhatCanonicalDayAccepts() {
        let valid = "2031-03-10"
        let rejected = [
            "", " ", "2031-3-3", "2031-03-3", "31-03-03", "02031-03-03", " 2031-03-03", "2031-03-03 ",
            "2031-03-03\n", "2031/03/03", "2031-02-30", "2031-13-01", "2031-00-10", "2031-03-00",
            "2031-03-32", "2031-02-29", "0000-01-01", "10000-01-01", "+031-03-03", "-031-03-03",
            "2031-03-0a", "２０３１-03-03", "2031-03-03T00:00", "garbage", "20310303",
        ]
        for key in rejected {
            XCTAssertNil(CanonicalDay.number(key), "the scaffolding rejects \"\(key)\"")
            XCTAssertEqual(CoachPacket.dayKeys(from: key, to: valid), [], "start \"\(key)\"")
            XCTAssertEqual(CoachPacket.dayKeys(from: valid, to: key), [], "end \"\(key)\"")
            XCTAssertEqual(CoachPacket.dayKeys(from: key, to: key), [], "both \"\(key)\"")
        }
        let accepted = ["0001-01-01", "2031-03-03", "2032-02-29", "9999-12-31", "2031-12-31"]
        for key in accepted {
            XCTAssertNotNil(CanonicalDay.number(key), "the scaffolding accepts \"\(key)\"")
            XCTAssertEqual(CoachPacket.dayKeys(from: key, to: key), [key])
        }
        // The equivalence itself, over every pairing of the strings above.
        let all = rejected + accepted
        for start in all {
            for end in all {
                guard let first = CanonicalDay.number(start), let last = CanonicalDay.number(end),
                      first <= last else {
                    XCTAssertEqual(CoachPacket.dayKeys(from: start, to: end), [],
                                   "\"\(start)\" to \"\(end)\"")
                    continue
                }
                // The widest pairings span thousands of years; a short span is enough here.
                guard last - first < 400 else { continue }
                XCTAssertEqual(CoachPacket.dayKeys(from: start, to: end).count, last - first + 1,
                               "\"\(start)\" to \"\(end)\"")
            }
        }
    }

    func testDayKeysAreTheKeysCanonicalDayGives() {
        let ranges = [("2031-03-03", "2031-03-16"), ("2030-12-26", "2031-01-08"),
                      ("2032-02-23", "2032-03-07"), ("2031-02-17", "2031-03-16"),
                      ("2031-03-16", "2031-03-16")]
        for (start, end) in ranges {
            guard let first = CanonicalDay.number(start), let last = CanonicalDay.number(end) else {
                XCTFail("the scaffolding must accept \(start) and \(end)")
                continue
            }
            XCTAssertEqual(CoachPacket.dayKeys(from: start, to: end),
                           (first...last).map { CanonicalDay.key($0) }, "\(start) to \(end)")
        }
        XCTAssertEqual(CoachPacket.dayKeys(from: F.rangeStart, to: F.rangeEnd), F.rangeDays)
        // One day is a range; the day before the start is not.
        XCTAssertEqual(CoachPacket.dayKeys(from: "2031-03-16", to: "2031-03-16"), ["2031-03-16"])
        XCTAssertEqual(CoachPacket.dayKeys(from: "2031-03-16", to: "2031-03-15"), [])
        XCTAssertEqual(CoachPacket.dayKeys(from: "2031-03-15", to: "2031-03-16"),
                       ["2031-03-15", "2031-03-16"])
    }

    func testSevenDayRangeOmitsTheLastSevenClause() {
        let seven = F.full { $0.rangeStartDay = "2031-03-10" }.text
        XCTAssertEqual(F.line(2, of: seven),
                       "range: 2031-03-10..2031-03-16 (7 days; the last day is today and is partial)")
        // 03-10 to 03-16: HRV 57, 55, 59, 62, 64, 61 average 59.67; RHR 54, 55, 54, 52, 52, 53
        // average 53.33. Only 64 lies outside 50.8 to 63.6; nothing lies outside 51.9 to 56.3.
        XCTAssertEqual(only("HRV: ", in: seven),
                       "HRV: baseline 57 ms (typical 51 to 64, trusted, 21 nights); "
                           + "range mean 60 ms over 6 nights (+3 vs baseline); "
                           + "outside typical: 0 below, 1 above")
        XCTAssertEqual(only("RHR: ", in: seven),
                       "RHR: baseline 54 bpm (typical 52 to 56, trusted, 21 nights); "
                           + "range mean 53 bpm over 6 nights (-1 vs baseline); "
                           + "outside typical: 0 below, 0 above")
        XCTAssertFalse(seven.contains("last 7 days"))
        XCTAssertEqual(dayRowKeys("== RECOVERY AND SLEEP ==", in: seven), Array(F.rangeDays.suffix(7)))
        // One day longer and the clause is back: 03-09 adds HRV 66, so 424 / 7 = 60.57.
        let eight = F.full { $0.rangeStartDay = "2031-03-09" }.text
        XCTAssertEqual(only("HRV: ", in: eight),
                       "HRV: baseline 57 ms (typical 51 to 64, trusted, 21 nights); "
                           + "range mean 61 ms over 7 nights (+4 vs baseline); "
                           + "last 7 days mean 60 ms over 6 nights (+3 vs baseline); "
                           + "outside typical: 0 below, 2 above")
    }

    func testLastSevenClauseNeedsAValueInTheLastSevenDays() {
        // Fourteen days, values only in the first seven: the clause is left out, not printed empty.
        let early = trendDraft(hrv: [58, 60, 62, 58, 60, 62, 60]).text
        XCTAssertEqual(only("HRV: ", in: early),
                       "HRV: baseline 57 ms (typical 51 to 64, trusted, 21 nights); "
                           + "range mean 60 ms over 7 nights (+3 vs baseline); "
                           + "outside typical: 0 below, 0 above")
        // One value on the first of the last seven days (2031-03-10) is enough.
        let edge = trendDraft(hrv: [58, 60, 62, 58, 60, 62, 60, 67]).text
        XCTAssertEqual(only("HRV: ", in: edge),
                       "HRV: baseline 57 ms (typical 51 to 64, trusted, 21 nights); "
                           + "range mean 61 ms over 8 nights (+4 vs baseline); "
                           + "last 7 days mean 67 ms over 1 nights (+10 vs baseline); "
                           + "outside typical: 0 below, 1 above")
    }

    func testTwentyEightDayRangeStaysOrdered() {
        var draft = F.full
        draft.rangeStartDay = "2031-02-17"
        draft.days = F.days.reversed() + [F.row("2031-02-17", recovery: 50, hrv: 50, rhr: 60),
                                          F.row("2031-02-28", recovery: 51, hrv: 51, rhr: 59)]
        draft.steps = F.steps.reversed() + [F.step("2031-03-01", 4000, .strap),
                                            F.step("2031-02-20", 3000)]
        draft.workouts = F.workouts.reversed()
            + [F.workout("2031-02-18", 7, 0, "swimming", .manual, min: 20),
               F.workout("2031-03-01", 6, 0, "yoga", .manual, min: 25)]
        let text = draft.text
        XCTAssertEqual(F.line(2, of: text),
                       "range: 2031-02-17..2031-03-16 (28 days; the last day is today and is partial)")
        let expected = (0..<28).map { CutScorecardFixture.day("2031-02-17", $0) }
        XCTAssertEqual(expected.first, "2031-02-17")
        XCTAssertEqual(expected.last, "2031-03-16")
        XCTAssertEqual(dayRowKeys("== RECOVERY AND SLEEP ==", in: text), expected)
        XCTAssertEqual(dayRowKeys("== ACTIVITY ==", in: text), expected)
        let workouts = workoutRows(text)
        XCTAssertEqual(workouts.map { String($0.dropFirst(2).prefix(16)) },
                       ["2031-02-18 07:00", "2031-03-01 06:00", "2031-03-03 18:10", "2031-03-05 07:05",
                        "2031-03-08 09:30", "2031-03-10 06:50", "2031-03-12 18:05"])
        XCTAssertTrue(only("averages over ", in: text).hasPrefix("averages over 15 of 28 days with data: "))
        XCTAssertTrue(only("HRV: ", in: text).contains("; last 7 days mean 60 ms over 6 nights (+3 vs baseline)"))
        // 111670 + 3000 + 4000 over 14 of 27 full days = 8476.4.
        XCTAssertEqual(only("steps average: ", in: text),
                       "steps average: 8476 over 14 of 27 full days (strap 1, apple-health 11, strap-estimate 2)")
        XCTAssertLessThanOrEqual(text.utf8.count, CoachPacket.byteBudget(rangeDays: 28))
    }

    func testInvalidRangePrintsHeaderAndNotesOnly() {
        let cases: [(String, String)] = [
            ("2031-3-3", "2031-03-16"), ("2031-03-03", "garbage"), ("2031-03-16", "2031-03-15"),
            ("", ""), ("2031-02-30", "2031-03-16"), (" 2031-03-03", "2031-03-16"),
        ]
        let notes = G.blocks(G.g1)[8]
        for (start, end) in cases {
            var draft = F.full
            draft.rangeStartDay = start
            draft.rangeEndDay = end
            let text = draft.text
            let lines = F.lines(text)
            XCTAssertEqual(lines.count, 8 + 1 + 7, "\(start)..\(end)")
            guard lines.count == 16 else { continue }
            XCTAssertEqual(lines[0], "NOOP-COACH-PACKET v2")
            XCTAssertEqual(lines[1], "generated: 2031-03-16T07:42:10+01:00")
            XCTAssertEqual(lines[2], "range: invalid")
            // SPEC-AMBIGUITY: §6.2 says "the header with `range: invalid`, no sections, and the notes"
            // and does not say what the two section lines of the header read. Only their labels are
            // pinned here.
            XCTAssertTrue(lines[3].hasPrefix("sections: "), lines[3])
            XCTAssertTrue(lines[4].hasPrefix("switched-off: "), lines[4])
            XCTAssertEqual(lines[5], "not-recorded-by-app: none")
            XCTAssertEqual(lines[6], F.lines(G.g1)[6])
            XCTAssertEqual(lines[7], F.lines(G.g1)[7])
            XCTAssertEqual(lines[8], "")
            XCTAssertEqual(lines[9...].joined(separator: "\n"), notes)
            XCTAssertEqual(headings(text), ["== NOTES =="])
            XCTAssertTrue(text.hasSuffix("end of NOOP-COACH-PACKET v2\n"))
        }
    }

    // MARK: - Scorecard

    func testScorecardSwitchedOffSaysSoInBothSections() {
        let text = F.full { $0.scorecard = .switchedOff }.text
        XCTAssertEqual(F.section("== SCORECARD ==", in: text),
                       ["not available: the scorecard is switched off in the app"])
        XCTAssertEqual(F.section("== WEIGH-INS ==", in: text), [
            "current weight: 97.1 kg (lab-book, 2031-03-05)",
            "current waist: 97.0 cm (lab-book, 2031-03-05)",
            "weekly: not available (the scorecard is switched off in the app)",
        ])
        XCTAssertFalse(text.contains("verdict:"))
        // Every other section is G1's.
        let blocks = G.blocks(text)
        let golden = G.blocks(G.g1)
        XCTAssertEqual(blocks.count, 9)
        guard blocks.count == 9 else { return }
        for index in [0, 3, 4, 5, 6, 7, 8] {
            XCTAssertEqual(blocks[index], golden[index], "block \(index)")
        }
    }

    func testInvalidRulesSaySoAndPrintNoVerdict() {
        for cause in [CutScorecardInvalidInput.parameters, .phase, .today] {
            let text = draft(result: F.result(invalidInput: cause)).text
            XCTAssertEqual(F.section("== SCORECARD ==", in: text),
                           ["not available: the stored rules need attention (\(cause.rawValue))"])
            XCTAssertEqual(F.section("== WEIGH-INS ==", in: text)?.last, "weekly: no weigh-ins yet")
            XCTAssertEqual(rows("== WEIGH-INS ==", in: text), [])
            XCTAssertFalse(text.contains("verdict:"))
            XCTAssertFalse(text.contains("phase:"))
            XCTAssertEqual(F.lines(startingWith: "rule ", in: text), [])
            XCTAssertEqual(F.lines(startingWith: "signal ", in: text), [])
            XCTAssertEqual(F.lines(startingWith: "rate:", in: text), [])
            XCTAssertEqual(F.lines(startingWith: "projection:", in: text), [])
        }
        // What stage 1 itself returns for an invalid `today` renders the same way.
        let real = CutScorecard.evaluate(CutScorecardFixture.make(today: "not a day"))
        XCTAssertEqual(real.invalidInput, .today)
        XCTAssertEqual(F.section("== SCORECARD ==", in: draft(result: real).text),
                       ["not available: the stored rules need attention (today)"])
    }

    func testNoActivePhasePrintsNoneActive() {
        let text = draft(result: F.result(), phase: nil).text
        XCTAssertEqual(only("phase: ", in: text), "phase: none active")
        // The line below it is still printed.
        XCTAssertEqual(only("judged-week: ", in: text), "judged-week: 2031-03-03")
        let noWeek = draft(result: F.result(judgedWeekStart: nil), phase: nil).text
        XCTAssertEqual(only("judged-week: ", in: noWeek), "judged-week: none")
    }

    func testPhaseNotStartedPrintsStarts() {
        let upcoming = CoachPacketPhase(name: "Fixture cut", startDay: "2031-04-07", targetWeightKg: 94.0,
                                        rateLowPercentPerWeek: 0.40, rateHighPercentPerWeek: 1.20)
        let notStarted = F.result(verdict: F.verdict(kind: .insufficientData, reason: .phaseNotStarted))
        XCTAssertEqual(only("phase: ", in: draft(result: notStarted, phase: upcoming).text),
                       "phase: \"Fixture cut\" (cut), starts 2031-04-07, target 94.0 kg, band 0.40 to 1.20 %/week")
        // The word follows the verdict's reason and nothing else: the same phase with another reason
        // reads "started".
        XCTAssertEqual(only("phase: ", in: draft(result: F.result(), phase: upcoming).text),
                       "phase: \"Fixture cut\" (cut), started 2031-04-07, target 94.0 kg, band 0.40 to 1.20 %/week")
        let noTarget = CoachPacketPhase(name: "Fixture cut", startDay: "2031-01-06", targetWeightKg: nil,
                                        rateLowPercentPerWeek: 0.25, rateHighPercentPerWeek: 1.004)
        XCTAssertEqual(only("phase: ", in: draft(result: F.result(), phase: noTarget).text),
                       "phase: \"Fixture cut\" (cut), started 2031-01-06, no target, band 0.25 to 1.00 %/week")
    }

    func testEachVerdictKindAndReasonPrintsItsRawValue() {
        let kinds: [(CutScorecardVerdictKind, String)] = [
            (.holdSteady, "holdSteady"), (.addCalories, "addCalories"), (.reduceCarbs, "reduceCarbs"),
            (.insufficientData, "insufficientData"),
        ]
        let reasons: [(CutScorecardVerdictReason, String)] = [
            (.ruleFired, "ruleFired"), (.noChangeRuleFired, "noChangeRuleFired"),
            (.recompositionCheckIncomplete, "recompositionCheckIncomplete"),
            (.noRuleEvaluable, "noRuleEvaluable"), (.noReadings, "noReadings"),
            (.noActivePhase, "noActivePhase"), (.phaseNotStarted, "phaseNotStarted"),
            (.weighInOverdue, "weighInOverdue"), (.invalidInput, "invalidInput"),
        ]
        for (kind, kindText) in kinds {
            for (reason, reasonText) in reasons {
                let text = draft(result: F.result(verdict: F.verdict(kind: kind, reason: reason))).text
                XCTAssertEqual(only("verdict: ", in: text),
                               "verdict: \(kindText); reason \(reasonText); rule none; "
                                   + "calorie-change none; overridden none; could-not-check none")
            }
        }
        for rule in CutScorecardRule.allCases {
            let text = draft(result: F.result(verdict: F.verdict(rule: rule))).text
            XCTAssertTrue(only("verdict: ", in: text).contains("; rule \(rule.rawValue); "))
        }
    }

    func testCalorieChangeCarriesItsSign() {
        func line(_ calories: Int?) -> String {
            only("verdict: ", in: draft(result: F.result(verdict: F.verdict(calories: calories))).text)
        }
        XCTAssertTrue(line(300).contains("; calorie-change +300 kcal; "), line(300))
        XCTAssertTrue(line(-250).contains("; calorie-change -250 kcal; "), line(-250))
        XCTAssertTrue(line(1).contains("; calorie-change +1 kcal; "), line(1))
        XCTAssertTrue(line(-1).contains("; calorie-change -1 kcal; "), line(-1))
        XCTAssertTrue(line(nil).contains("; calorie-change none; "), line(nil))
        // §7.1: a signed change of zero is "+0".
        XCTAssertTrue(line(0).contains("; calorie-change +0 kcal; "), line(0))
    }

    func testUnknownRulePrintsItsReason() {
        let reasons: [(CutScorecardRuleUnknownReason, String)] = [
            (.liftSignalUnknown, "liftSignalUnknown"), (.waistSignalUnknown, "waistSignalUnknown"),
            (.fewerWeeksThanWindow, "fewerWeeksThanWindow"), (.missedWeighIn, "missedWeighIn"),
            (.noActivePhase, "noActivePhase"), (.weighInOverdue, "weighInOverdue"),
            (.noReadings, "noReadings"),
        ]
        for (reason, reasonText) in reasons {
            let rules = [
                CutScorecardRuleEvaluation(rule: .liftsHoldingWaistShrinking, state: .unknown,
                                           unknownReason: reason, consecutiveWeeks: 0, requiredWeeks: 1),
                CutScorecardRuleEvaluation(rule: .liftsDropping, state: .unknown, unknownReason: reason,
                                           consecutiveWeeks: 2, requiredWeeks: 3),
                CutScorecardRuleEvaluation(rule: .slowLoss, state: .notFired, unknownReason: nil,
                                           consecutiveWeeks: 1, requiredWeeks: 4),
            ]
            let text = draft(result: F.result(rules: rules)).text
            XCTAssertEqual(F.lines(startingWith: "rule ", in: text), [
                "rule liftsHoldingWaistShrinking: unknown (\(reasonText)), 0 of 1 weeks",
                "rule liftsDropping: unknown (\(reasonText)), 2 of 3 weeks",
                "rule slowLoss: notFired, 1 of 4 weeks",
            ])
        }
    }

    func testRulesPrintInTheOrderOfTheResult() {
        let text = draft(result: F.result(rules: F.rules.reversed())).text
        XCTAssertEqual(F.lines(startingWith: "rule ", in: text), [
            "rule slowLoss: fired, 5 of 3 weeks",
            "rule liftsDropping: notFired, 0 of 3 weeks",
            "rule liftsHoldingWaistShrinking: notFired, 0 of 1 weeks",
        ])
    }

    func testCouldNotCheckListsTheUnevaluatedRules() {
        func line(_ rules: [CutScorecardRule]) -> String {
            only("verdict: ", in: draft(result: F.result(verdict: F.verdict(unevaluated: rules))).text)
        }
        XCTAssertTrue(line([]).hasSuffix("; could-not-check none"))
        XCTAssertTrue(line([.liftsDropping]).hasSuffix("; could-not-check liftsDropping"))
        XCTAssertTrue(line([.liftsHoldingWaistShrinking, .slowLoss])
            .hasSuffix("; could-not-check liftsHoldingWaistShrinking, slowLoss"))
        XCTAssertTrue(line([.liftsHoldingWaistShrinking, .liftsDropping])
            .contains("; overridden none; could-not-check liftsHoldingWaistShrinking, liftsDropping"))
    }

    func testOverriddenRulesAreListed() {
        func line(_ rules: [CutScorecardRule]) -> String {
            only("verdict: ", in: draft(result: F.result(verdict: F.verdict(overridden: rules))).text)
        }
        XCTAssertTrue(line([]).contains("; overridden none; could-not-check none"))
        XCTAssertTrue(line([.slowLoss]).contains("; overridden slowLoss; could-not-check none"))
        XCTAssertTrue(line([.liftsDropping, .slowLoss])
            .contains("; overridden liftsDropping, slowLoss; could-not-check none"))
        // Stage 1's week 7: rule 1 fires and overrides rule 3.
        let weekSeven = F.result(verdict: CutScorecardVerdict(
            kind: .holdSteady, reason: .noChangeRuleFired, rule: .liftsHoldingWaistShrinking,
            calorieChangeKcal: nil, overriddenRules: [.slowLoss], unevaluatedRules: []))
        XCTAssertEqual(only("verdict: ", in: draft(result: weekSeven).text),
                       "verdict: holdSteady; reason noChangeRuleFired; rule liftsHoldingWaistShrinking; "
                           + "calorie-change none; overridden slowLoss; could-not-check none")
    }

    func testEachSignalPrintsOnlyTheClausesItHas() {
        func waist(_ signal: CutScorecardWaistSignal) -> String {
            only("signal waist: ", in: draft(result: F.result(waist: signal)).text)
        }
        XCTAssertEqual(waist(CutScorecardWaistSignal(state: .unknown, reason: .noWaistThisWeek,
                                                     currentCm: nil, referenceCm: nil,
                                                     referenceWeekStart: nil, changeCm: nil)),
                       "signal waist: unknown (noWaistThisWeek)")
        XCTAssertEqual(waist(CutScorecardWaistSignal(state: .unknown, reason: .noEarlierWaist,
                                                     currentCm: 96.5, referenceCm: nil,
                                                     referenceWeekStart: nil, changeCm: nil)),
                       "signal waist: unknown (noEarlierWaist); now 96.5 cm")
        XCTAssertEqual(waist(CutScorecardWaistSignal(state: .met, reason: .shrinking, currentCm: 96.5,
                                                     referenceCm: 97.5,
                                                     referenceWeekStart: "2031-02-17", changeCm: -1.0)),
                       "signal waist: met (shrinking); now 96.5 cm; reference 97.5 cm in week 2031-02-17; "
                           + "change -1.0 cm")
        // The reference clause needs both its value and its week.
        XCTAssertEqual(waist(CutScorecardWaistSignal(state: .unknown, reason: .noEarlierWaist,
                                                     currentCm: 96.5, referenceCm: 97.5,
                                                     referenceWeekStart: nil, changeCm: nil)),
                       "signal waist: unknown (noEarlierWaist); now 96.5 cm")
        XCTAssertEqual(waist(CutScorecardWaistSignal(state: .unknown, reason: .noEarlierWaist,
                                                     currentCm: nil, referenceCm: nil,
                                                     referenceWeekStart: "2031-02-17", changeCm: 0.5)),
                       "signal waist: unknown (noEarlierWaist); change +0.5 cm")

        func lifts(_ signal: CutScorecardLiftSignal) -> String {
            only("signal lifts: ", in: draft(result: F.result(lifts: signal)).text)
        }
        XCTAssertEqual(lifts(CutScorecardLiftSignal(state: .unknown, reason: .noLiftData,
                                                    commonExercises: 0, dropped: 0, climbed: 0, held: 0,
                                                    windowStartDay: nil, windowEndDay: nil)),
                       "signal lifts: unknown (noLiftData)")
        XCTAssertEqual(lifts(CutScorecardLiftSignal(state: .unknown, reason: .noCommonExercises,
                                                    commonExercises: 0, dropped: 0, climbed: 0, held: 0,
                                                    windowStartDay: "2031-02-26",
                                                    windowEndDay: "2031-03-04")),
                       "signal lifts: unknown (noCommonExercises); days 2031-02-26..2031-03-04")
        XCTAssertEqual(lifts(CutScorecardLiftSignal(state: .notMet, reason: .dropping,
                                                    commonExercises: 3, dropped: 2, climbed: 0, held: 1,
                                                    windowStartDay: "2031-02-26",
                                                    windowEndDay: "2031-03-04")),
                       "signal lifts: notMet (dropping); 3 exercises in common: 2 dropped, 0 climbed, "
                           + "1 held; days 2031-02-26..2031-03-04")
        // One exercise in common is the edge of the clause; the window needs both of its days.
        XCTAssertEqual(lifts(CutScorecardLiftSignal(state: .met, reason: .holding, commonExercises: 1,
                                                    dropped: 0, climbed: 1, held: 0,
                                                    windowStartDay: "2031-02-26", windowEndDay: nil)),
                       "signal lifts: met (holding); 1 exercises in common: 0 dropped, 1 climbed, 0 held")

        func protein(_ signal: CutScorecardProteinSignal) -> String {
            only("signal protein: ", in: draft(result: F.result(protein: signal)).text)
        }
        XCTAssertEqual(protein(CutScorecardProteinSignal(state: .met, reason: .floorMet, daysLogged: 7,
                                                         daysAtOrAboveFloor: 6, requiredDays: 5,
                                                         floorGrams: 100)),
                       "signal protein: met (floorMet); 6 of 5 days at or above floor; 7 days logged; "
                           + "floor 100 g")
        XCTAssertEqual(protein(CutScorecardProteinSignal(state: .unknown, reason: .noFloorConfigured,
                                                         daysLogged: 3, daysAtOrAboveFloor: 0,
                                                         requiredDays: 4, floorGrams: nil)),
                       "signal protein: unknown (noFloorConfigured); 0 of 4 days at or above floor; "
                           + "3 days logged; floor not set")

        func band(_ signal: CutScorecardRateBandSignal) -> String {
            only("signal rate-band: ", in: draft(result: F.result(rateBand: signal)).text)
        }
        XCTAssertEqual(band(CutScorecardRateBandSignal(state: .unknown, reason: .rateUnknown,
                                                       percentPerWeek: nil, lowPercentPerWeek: nil,
                                                       highPercentPerWeek: nil)),
                       "signal rate-band: unknown (rateUnknown)")
        XCTAssertEqual(band(CutScorecardRateBandSignal(state: .met, reason: .withinBand,
                                                       percentPerWeek: 0.806, lowPercentPerWeek: 0.40,
                                                       highPercentPerWeek: 1.20)),
                       "signal rate-band: met (withinBand); 0.81 %/week; band 0.40 to 1.20 %/week")
        XCTAssertEqual(band(CutScorecardRateBandSignal(state: .unknown, reason: .noActivePhase,
                                                       percentPerWeek: 0.806, lowPercentPerWeek: nil,
                                                       highPercentPerWeek: nil)),
                       "signal rate-band: unknown (noActivePhase); 0.81 %/week")
        // The band clause needs both bounds.
        XCTAssertEqual(band(CutScorecardRateBandSignal(state: .unknown, reason: .rateUnknown,
                                                       percentPerWeek: nil, lowPercentPerWeek: 0.40,
                                                       highPercentPerWeek: nil)),
                       "signal rate-band: unknown (rateUnknown)")
        XCTAssertEqual(band(CutScorecardRateBandSignal(state: .unknown, reason: .rateUnknown,
                                                       percentPerWeek: nil, lowPercentPerWeek: 0.40,
                                                       highPercentPerWeek: 1.20)),
                       "signal rate-band: unknown (rateUnknown); band 0.40 to 1.20 %/week")
    }

    func testWholeGramFloorPrintsUnchanged() {
        for (floor, expected) in [(1.0, "floor 1 g"), (100.0, "floor 100 g"), (250.0, "floor 250 g")] {
            let signal = CutScorecardProteinSignal(state: .unknown, reason: .noProteinData, daysLogged: 0,
                                                   daysAtOrAboveFloor: 0, requiredDays: 5,
                                                   floorGrams: floor)
            let line = only("signal protein: ", in: draft(result: F.result(protein: signal)).text)
            XCTAssertTrue(line.hasSuffix("; " + expected), line)
            XCTAssertFalse(line.contains("."), "a whole-gram floor has no decimal: \(line)")
        }
    }

    func testGainingAndFlatRatesAreWorded() {
        func line(loss: Double, percent: Double, reference: Double = 95.5) -> String {
            let rate = CutScorecardRate(lossKgPerWeek: loss, percentPerWeek: percent,
                                        referenceWeightKg: reference, pointsUsed: 5, spanWeeks: 4,
                                        firstWeekStart: "2031-04-21", lastWeekStart: "2031-05-19")
            return only("rate: ", in: draft(result: F.result(rate: rate)).text)
        }
        let tail = " (0.13 %/week of 95.5 kg); fitted over 5 weigh-ins, weeks 2031-04-21..2031-05-19"
        // Stage 1's week 20: a loss of -0.120 kg/week is a gain, printed without its sign.
        XCTAssertEqual(line(loss: -0.120, percent: -0.127), "rate: gaining 0.12 kg/week" + tail)
        XCTAssertEqual(line(loss: 0.120, percent: 0.127), "rate: losing 0.12 kg/week" + tail)
        XCTAssertEqual(line(loss: 0, percent: 0, reference: 97.1),
                       "rate: flat 0.00 kg/week (0.00 %/week of 97.1 kg); fitted over 5 weigh-ins, "
                           + "weeks 2031-04-21..2031-05-19")
        // The word turns on the loss quantized to three decimals: one quantum either side of zero is a
        // direction, less than half a quantum is flat.
        XCTAssertTrue(line(loss: 0.001, percent: 0.001).hasPrefix("rate: losing 0.00 kg/week (0.00 %/week"))
        XCTAssertTrue(line(loss: -0.001, percent: -0.001).hasPrefix("rate: gaining 0.00 kg/week (0.00 %/week"))
        XCTAssertTrue(line(loss: 0.0004, percent: 0.0004).hasPrefix("rate: flat 0.00 kg/week (0.00 %/week"))
        XCTAssertTrue(line(loss: -0.0004, percent: -0.0004).hasPrefix("rate: flat 0.00 kg/week (0.00 %/week"))
        XCTAssertTrue(line(loss: 0.0006, percent: 0.0006).hasPrefix("rate: losing 0.00 kg/week"))
        XCTAssertTrue(line(loss: -0.0006, percent: -0.0006).hasPrefix("rate: gaining 0.00 kg/week"))
        // The word follows the loss in kilograms, not the percentage.
        XCTAssertTrue(line(loss: 0.2, percent: -0.2).hasPrefix("rate: losing 0.20 kg/week (0.20 %/week"))
    }

    func testRateUnavailablePrintsItsReason() {
        let reasons: [(CutScorecardRateUnavailable, String)] = [
            (.noReadings, "noReadings"), (.singleReading, "singleReading"),
            (.gapLongerThanWindow, "gapLongerThanWindow"), (.weighInOverdue, "weighInOverdue"),
        ]
        for (reason, reasonText) in reasons {
            let text = draft(result: F.result(rate: .some(nil), rateUnavailable: reason)).text
            XCTAssertEqual(only("rate: ", in: text), "rate: not available (\(reasonText))")
        }
    }

    func testEachProjectionStatusPrints() {
        XCTAssertEqual(only("projection: ", in: F.full.text),
                       "projection: 2031-10-08 (estimate), 31.0 weeks, 3.1 kg remaining")
        let statuses: [(CutScorecardProjectionStatus, String)] = [
            (.noActivePhase, "noActivePhase"), (.noTarget, "noTarget"),
            (.targetReached, "targetReached"), (.rateUnknown, "rateUnknown"), (.notLosing, "notLosing"),
            (.beyondHorizon, "beyondHorizon"), (.needsNewWeighIn, "needsNewWeighIn"),
            (.weighInOverdue, "weighInOverdue"),
        ]
        for (status, statusText) in statuses {
            let bare = CutScorecardProjection(status: status, targetDay: nil, weeksRemaining: nil,
                                              remainingKg: nil)
            XCTAssertEqual(only("projection: ", in: draft(result: F.result(projection: bare)).text),
                           "projection: none (\(statusText))")
            let withRemaining = CutScorecardProjection(status: status, targetDay: nil,
                                                       weeksRemaining: nil, remainingKg: 3.14)
            XCTAssertEqual(only("projection: ", in: draft(result: F.result(projection: withRemaining)).text),
                           "projection: none (\(statusText)); 3.1 kg remaining")
        }
        // A projected date is always marked as an estimate (ruling: estimates are labelled).
        let other = CutScorecardProjection(status: .projected, targetDay: "2031-05-27",
                                           weeksRemaining: 14.04, remainingKg: 3.36)
        XCTAssertEqual(only("projection: ", in: draft(result: F.result(projection: other)).text),
                       "projection: 2031-05-27 (estimate), 14.0 weeks, 3.4 kg remaining")
    }

    func testRejectedReadingsAreCounted() {
        XCTAssertEqual(F.lines(startingWith: "ignored-readings", in: F.full.text), [])
        func line(_ a: Int, _ b: Int, _ c: Int, _ d: Int) -> [String] {
            let counts = CutScorecardRejections(nonFinite: a, nonPositive: b, invalidDay: c, future: d)
            return F.lines(startingWith: "ignored-readings", in: draft(result: F.result(rejections: counts)).text)
        }
        XCTAssertEqual(line(1, 2, 3, 4),
                       ["ignored-readings: 10 (nonFinite 1, nonPositive 2, invalidDay 3, future 4)"])
        // One rejected reading of any kind is enough for the line.
        XCTAssertEqual(line(1, 0, 0, 0),
                       ["ignored-readings: 1 (nonFinite 1, nonPositive 0, invalidDay 0, future 0)"])
        XCTAssertEqual(line(0, 1, 0, 0),
                       ["ignored-readings: 1 (nonFinite 0, nonPositive 1, invalidDay 0, future 0)"])
        XCTAssertEqual(line(0, 0, 1, 0),
                       ["ignored-readings: 1 (nonFinite 0, nonPositive 0, invalidDay 1, future 0)"])
        XCTAssertEqual(line(0, 0, 0, 1),
                       ["ignored-readings: 1 (nonFinite 0, nonPositive 0, invalidDay 0, future 1)"])
        XCTAssertEqual(line(0, 0, 0, 0), [])
        // The line closes the scorecard section.
        let text = draft(result: F.result(rejections: CutScorecardRejections(
            nonFinite: 0, nonPositive: 0, invalidDay: 0, future: 2))).text
        XCTAssertEqual(F.section("== SCORECARD ==", in: text)?.last,
                       "ignored-readings: 2 (nonFinite 0, nonPositive 0, invalidDay 0, future 2)")
    }

    // MARK: - Weigh-ins

    func testWeeklyBlockStopsAtEightWeeks() {
        func block(_ count: Int) -> [String] {
            let text = draft(result: F.result(weeks: Array(F.weeks.prefix(count)))).text
            return Array((F.section("== WEIGH-INS ==", in: text) ?? []).dropFirst(2))
        }
        let lead = "weekly, weeks start Monday, the latest reading of a week represents it, last "
        XCTAssertEqual(block(10).first, lead + "8 of 10 weeks:")
        XCTAssertEqual(block(10).count, 1 + 8)
        XCTAssertEqual(block(10).dropFirst().first,
                       "  2031-01-20: weight 98.4 kg (2031-01-22), waist 99.0 cm (2031-01-22), change -0.8 kg")
        XCTAssertEqual(block(9).first, lead + "8 of 9 weeks:")
        XCTAssertEqual(block(9).count, 1 + 8)
        XCTAssertEqual(block(9).dropFirst().first,
                       "  2031-01-13: weight 99.2 kg (2031-01-15), waist 99.5 cm (2031-01-15), change -0.8 kg")
        XCTAssertEqual(block(8).first, lead + "8 of 8 weeks:")
        XCTAssertEqual(block(8).count, 1 + 8)
        XCTAssertEqual(block(8).dropFirst().first,
                       "  2031-01-06: weight 100.0 kg (2031-01-08), waist 100.0 cm (2031-01-08), change —")
        XCTAssertEqual(block(7).first, lead + "7 of 7 weeks:")
        XCTAssertEqual(block(7).count, 1 + 7)
        XCTAssertEqual(block(1), [
            lead + "1 of 1 weeks:",
            "  2031-01-06: weight 100.0 kg (2031-01-08), waist 100.0 cm (2031-01-08), change —",
        ])
        XCTAssertEqual(block(0), ["weekly: no weigh-ins yet"])
        // The rows kept are the latest, oldest first.
        XCTAssertEqual(block(10).last, "  2031-03-10: weight —, waist —, change —")
    }

    func testMissedWeekPrintsDashesAndTheNextChangeIsADash() {
        // Stage 1's weeks 9 to 11: a weigh-in, a missed week, and the first reading after the gap,
        // whose weekly loss stage 1 leaves nil. A week with a weight and no waist follows.
        let weeks = [
            F.week("2031-03-03", 97.1, 97.0, on: "2031-03-05", loss: 0.1),
            F.week("2031-03-10", nil, nil, on: nil, loss: nil),
            F.week("2031-03-17", 96.0, 96.5, on: "2031-03-19", loss: nil),
            F.week("2031-03-24", 95.2, nil, on: "2031-03-26", loss: 0.8),
            CutScorecardWeek(weekStart: "2031-03-31", weightKg: nil, weightDay: nil, waistCm: 95.5,
                             waistDay: "2031-04-02", inPhase: true, weeklyLossKg: nil),
            F.week("2031-04-07", 95.6, 95.0, on: "2031-04-09", loss: -0.4),
        ]
        var packet = draft(result: F.result(weeks: weeks))
        packet.rangeStartDay = "2031-03-28"
        packet.rangeEndDay = "2031-04-10"
        XCTAssertEqual(Array((F.section("== WEIGH-INS ==", in: packet.text) ?? []).dropFirst(2)), [
            "weekly, weeks start Monday, the latest reading of a week represents it, last 6 of 6 weeks:",
            "  2031-03-03: weight 97.1 kg (2031-03-05), waist 97.0 cm (2031-03-05), change -0.1 kg",
            "  2031-03-10: weight —, waist —, change —",
            "  2031-03-17: weight 96.0 kg (2031-03-19), waist 96.5 cm (2031-03-19), change —",
            "  2031-03-24: weight 95.2 kg (2031-03-26), waist —, change -0.8 kg",
            "  2031-03-31: weight —, waist 95.5 cm (2031-04-02), change —",
            "  2031-04-07: weight 95.6 kg (2031-04-09), waist 95.0 cm (2031-04-09), change +0.4 kg",
        ])
    }

    func testCurrentValueFromTheProfileHasNoDay() {
        let text = F.full {
            $0.body = [
                CoachPacketBodyReading(kind: .weight, value: 80.0, source: .profile, day: nil),
                CoachPacketBodyReading(kind: .waist, value: 88.46, source: .appleHealth, day: "2031-01-02"),
            ]
        }.text
        XCTAssertEqual(only("current weight: ", in: text), "current weight: 80.0 kg (profile)")
        // A current value is never filtered by the range: this one is dated long before it.
        XCTAssertEqual(only("current waist: ", in: text), "current waist: 88.5 cm (apple-health, 2031-01-02)")
    }

    func testAbsentCurrentWaistPrintsADash() {
        let weightOnly = F.full { $0.body = [F.body[0]] }.text
        XCTAssertEqual(only("current weight: ", in: weightOnly), "current weight: 97.1 kg (lab-book, 2031-03-05)")
        XCTAssertEqual(only("current waist: ", in: weightOnly), "current waist: —")
        let waistOnly = F.full { $0.body = [F.body[1]] }.text
        XCTAssertEqual(only("current weight: ", in: waistOnly), "current weight: —")
        XCTAssertEqual(only("current waist: ", in: waistOnly), "current waist: 97.0 cm (lab-book, 2031-03-05)")
        let neither = F.full { $0.body = [] }.text
        XCTAssertEqual(Array((F.section("== WEIGH-INS ==", in: neither) ?? []).prefix(2)),
                       ["current weight: —", "current waist: —"])
        // The order the readings arrive in does not matter.
        assertSameText(F.full { $0.body = F.body.reversed() }.text, G.g1)
    }

    // MARK: - Trends

    func testBaselineNotUsablePrintsItsStatus() {
        let calibrating = CoachPacketBaseline(center: 57.2, typical: nil, status: "calibrating", nights: 3)
        let text = F.full { $0.hrvBaseline = calibrating }.text
        XCTAssertEqual(only("HRV: ", in: text),
                       "HRV: baseline not established (calibrating, 3 nights); "
                           + "range mean 59 ms over 12 nights; last 7 days mean 60 ms over 6 nights")
        XCTAssertEqual(only("RHR: ", in: text), g1RhrLine)
        let none = F.full {
            $0.restingHrBaseline = CoachPacketBaseline(center: 54.1, typical: nil, status: "stale",
                                                       nights: 0)
        }.text
        XCTAssertEqual(only("RHR: ", in: none),
                       "RHR: baseline not established (stale, 0 nights); "
                           + "range mean 54 bpm over 12 nights; last 7 days mean 53 bpm over 6 nights")
        XCTAssertEqual(only("HRV: ", in: none), g1HrvLine)
    }

    func testBaselineWithANonFiniteBoundIsNotUsable() {
        // A NaN bound cannot be built at all in a debug build (`ClosedRange` checks its bounds there), so
        // the bounds that can reach the renderer from a test are the infinite ones.
        let bounds: [(Double, Double)] = [
            (-.infinity, 63.6), (50.8, .infinity), (-.infinity, .infinity),
            (-.greatestFiniteMagnitude, .infinity),
        ]
        for (lower, upper) in bounds {
            let typical = lower...upper
            let text = F.full {
                $0.hrvBaseline = CoachPacketBaseline(center: 57.2, typical: typical, status: "trusted",
                                                     nights: 21)
            }.text
            XCTAssertEqual(only("HRV: ", in: text),
                           "HRV: baseline not established (trusted, 21 nights); "
                               + "range mean 59 ms over 12 nights; last 7 days mean 60 ms over 6 nights",
                           "\(lower)...\(upper)")
            XCTAssertEqual(only("RHR: ", in: text), g1RhrLine)
        }
    }

    func testTypicalBoundsPrintedAreTheRoundedBoundsGiven() {
        func hrvLine(_ center: Double, _ typical: ClosedRange<Double>) -> String {
            only("HRV: ", in: F.full {
                $0.hrvBaseline = CoachPacketBaseline(center: center, typical: typical, status: "trusted",
                                                     nights: 21)
            }.text)
        }
        // Halves round away from zero, on the bounds as given.
        XCTAssertTrue(hrvLine(57.2, 50.5...63.5).hasPrefix("HRV: baseline 57 ms (typical 51 to 64, trusted, 21 nights); "))
        XCTAssertTrue(hrvLine(57.2, 50.49...63.49).hasPrefix("HRV: baseline 57 ms (typical 50 to 63, trusted, 21 nights); "))
        // The bounds are printed, not rebuilt from the centre: this range is not centred on 57.2.
        XCTAssertTrue(hrvLine(57.2, 40.2...70.9).hasPrefix("HRV: baseline 57 ms (typical 40 to 71, trusted, 21 nights); "))
        XCTAssertTrue(hrvLine(56.5, 50.8...63.6).hasPrefix("HRV: baseline 57 ms (typical 51 to 64, trusted, 21 nights); "))
        XCTAssertTrue(hrvLine(56.49, 50.8...63.6).hasPrefix("HRV: baseline 56 ms (typical 51 to 64, trusted, 21 nights); "))
        let rhr = only("RHR: ", in: F.full {
            $0.restingHrBaseline = CoachPacketBaseline(center: 54.5, typical: 48.5...61.4,
                                                       status: "provisional", nights: 9)
        }.text)
        XCTAssertTrue(rhr.hasPrefix("RHR: baseline 55 bpm (typical 49 to 61, provisional, 9 nights); "), rhr)
    }

    func testBaselineNilPrintsNotAvailable() {
        let text = F.full { $0.hrvBaseline = nil }.text
        XCTAssertEqual(only("HRV: ", in: text),
                       "HRV: baseline not available; range mean 59 ms over 12 nights; "
                           + "last 7 days mean 60 ms over 6 nights")
        XCTAssertEqual(only("RHR: ", in: text), g1RhrLine)
        let both = F.full {
            $0.hrvBaseline = nil
            $0.restingHrBaseline = nil
        }.text
        XCTAssertEqual(only("RHR: ", in: both),
                       "RHR: baseline not available; range mean 54 bpm over 12 nights; "
                           + "last 7 days mean 53 bpm over 6 nights")
        // A baseline with no night in the range still states itself; the mean is a dash, not a zero.
        XCTAssertEqual(only("HRV: ", in: trendDraft().text),
                       "HRV: baseline 57 ms (typical 51 to 64, trusted, 21 nights); range mean — over 0 nights")
    }

    func testOutsideTypicalCountsUseTheUnroundedBand() {
        // Typical 50.6 to 63.4 prints as 51 to 63. A value on a bound is inside; one step beyond it is
        // outside. Counting against the printed 51 and 63 would give 3 below and 3 above.
        let hrvBaseline = CoachPacketBaseline(center: 57.0, typical: 50.6...63.4, status: "trusted",
                                              nights: 21)
        let hrv: [Double?] = [50.6, 50.6.nextDown, 50.8, 63.4, 63.4.nextUp, 63.3, 57]
        // 52.4 to 55.6 prints as 52 to 56: 52 is below and 56 is above, though neither is outside the
        // printed bounds.
        let rhrBaseline = CoachPacketBaseline(center: 54.1, typical: 52.4...55.6, status: "trusted",
                                              nights: 21)
        let text = trendDraft(hrv: hrv, rhr: [52, 53, 55, 56], hrvBaseline: hrvBaseline,
                              rhrBaseline: rhrBaseline).text
        // HRV: 399.1 / 7 = 57.01. RHR: 216 / 4 = 54.
        XCTAssertEqual(only("HRV: ", in: text),
                       "HRV: baseline 57 ms (typical 51 to 63, trusted, 21 nights); "
                           + "range mean 57 ms over 7 nights (+0 vs baseline); "
                           + "outside typical: 1 below, 1 above")
        XCTAssertEqual(only("RHR: ", in: text),
                       "RHR: baseline 54 bpm (typical 52 to 56, trusted, 21 nights); "
                           + "range mean 54 bpm over 4 nights (+0 vs baseline); "
                           + "outside typical: 1 below, 1 above")
    }

    func testDifferencesAreDifferencesOfThePrintedIntegers() {
        // Centre 57.4 prints 57; the mean 58.6 prints 59. The printed difference is 59 − 57 = +2,
        // where rounding 58.6 − 57.4 = 1.2 would give +1.
        let up = CoachPacketBaseline(center: 57.4, typical: 50.0...65.0, status: "trusted", nights: 21)
        XCTAssertEqual(only("HRV: ", in: trendDraft(hrv: [58, 59, 59, 58, 59], hrvBaseline: up).text),
                       "HRV: baseline 57 ms (typical 50 to 65, trusted, 21 nights); "
                           + "range mean 59 ms over 5 nights (+2 vs baseline); "
                           + "outside typical: 0 below, 0 above")
        // Centre 57.6 prints 58; the mean 56.4 prints 56: −2, where −1.2 would round to −1.
        let down = CoachPacketBaseline(center: 57.6, typical: 50.0...65.0, status: "trusted", nights: 21)
        XCTAssertEqual(only("HRV: ", in: trendDraft(hrv: [56, 57, 56, 57, 56], hrvBaseline: down).text),
                       "HRV: baseline 58 ms (typical 50 to 65, trusted, 21 nights); "
                           + "range mean 56 ms over 5 nights (-2 vs baseline); "
                           + "outside typical: 0 below, 0 above")
        // The same rule on the last-seven clause and on resting heart rate (centre 54.4 prints 54;
        // 55, 56, 56 on the last three days average 55.67 and print 56).
        let rhr = CoachPacketBaseline(center: 54.4, typical: 50.0...60.0, status: "trusted", nights: 21)
        var draft = trendDraft(rhrBaseline: rhr)
        draft.days = [F.row("2031-03-14", rhr: 55), F.row("2031-03-15", rhr: 56),
                      F.row("2031-03-16", rhr: 56)]
        XCTAssertEqual(only("RHR: ", in: draft.text),
                       "RHR: baseline 54 bpm (typical 50 to 60, trusted, 21 nights); "
                           + "range mean 56 bpm over 3 nights (+2 vs baseline); "
                           + "last 7 days mean 56 bpm over 3 nights (+2 vs baseline); "
                           + "outside typical: 0 below, 0 above")
    }

    // MARK: - Activity

    func testEstimatedStepsCarryATildeAndTheirSource() {
        let text = F.full.text
        XCTAssertEqual(only("  2031-03-06: ", in: Self.activity(text)), "  2031-03-06: ~7300 strap-estimate")
        XCTAssertEqual(only("  2031-03-13: ", in: Self.activity(text)), "  2031-03-13: ~5200 strap-estimate")
        XCTAssertEqual(only("  2031-03-03: ", in: Self.activity(text)), "  2031-03-03: 9120 apple-health")
        XCTAssertEqual(only("steps per day", in: text),
                       "steps per day; \"strap-estimate\" is an estimate from strap motion, not a count:")
        // Today's estimate keeps both marks; a measured strap count has neither tilde nor "estimate".
        var draft = F.full
        draft.steps = F.steps.dropLast() + [F.step("2031-03-16", 1480, .strapEstimate)]
        draft.steps[0] = F.step("2031-03-03", 9120, .strap)
        let changed = draft.text
        XCTAssertEqual(only("  2031-03-16: ", in: Self.activity(changed)),
                       "  2031-03-16: ~1480 strap-estimate (today so far)")
        XCTAssertEqual(only("  2031-03-03: ", in: Self.activity(changed)), "  2031-03-03: 9120 strap")
        XCTAssertEqual(only("steps average: ", in: changed),
                       "steps average: 9306 over 12 of 13 full days (strap 1, apple-health 9, strap-estimate 2)")
        // In every step row the tilde and the estimate token go together.
        for row in rows("== ACTIVITY ==", in: changed) where Array(row).count > 12 && Array(row)[12] == ":" {
            XCTAssertEqual(row.contains("~"), row.contains("strap-estimate"), row)
        }
    }

    /// The activity section alone, so a day-key prefix cannot match a recovery row.
    private static func activity(_ text: String) -> String {
        (CoachPacketFixture.section("== ACTIVITY ==", in: text) ?? []).joined(separator: "\n")
    }

    func testStepAverageLeavesOutToday() {
        // Twelve full days sum to 111670: 9305.83. With today's 1480 it would be 8703.85.
        XCTAssertEqual(only("steps average: ", in: F.full.text),
                       "steps average: 9306 over 12 of 13 full days (apple-health 10, strap-estimate 2)")
        var draft = F.full
        draft.steps = F.steps.dropLast() + [F.step("2031-03-16", 99_999, .strap)]
        XCTAssertEqual(only("steps average: ", in: draft.text),
                       "steps average: 9306 over 12 of 13 full days (apple-health 10, strap-estimate 2)")
        XCTAssertEqual(only("  2031-03-16: ", in: Self.activity(draft.text)),
                       "  2031-03-16: 99999 strap (today so far)")
        // Today missing changes nothing either.
        draft.steps = Array(F.steps.dropLast())
        XCTAssertEqual(only("steps average: ", in: draft.text),
                       "steps average: 9306 over 12 of 13 full days (apple-health 10, strap-estimate 2)")
    }

    func testStepAverageWithNoFullDaySaysSo() {
        var draft = F.full
        draft.steps = [F.step("2031-03-16", 1480)]
        XCTAssertEqual(only("steps average: ", in: draft.text), "steps average: — (no step data in range)")
        XCTAssertEqual(only("  2031-03-16: ", in: Self.activity(draft.text)),
                       "  2031-03-16: 1480 apple-health (today so far)")
        draft.steps = []
        XCTAssertEqual(only("steps average: ", in: draft.text), "steps average: — (no step data in range)")
        // One full day is enough for an average, and it is that day's count.
        draft.steps = [F.step("2031-03-15", 13_020, .strap)]
        XCTAssertEqual(only("steps average: ", in: draft.text),
                       "steps average: 13020 over 1 of 13 full days (strap 1)")
    }

    func testMissingStepDayPrintsADashNotZero() {
        XCTAssertEqual(only("  2031-03-07: ", in: Self.activity(F.full.text)), "  2031-03-07: —")
        var draft = F.full
        draft.steps = Array(F.steps.dropLast()) + [F.step("2031-03-07", 0)]
        let text = draft.text
        // A measured zero is a count and is printed; it is the missing day that is a dash.
        XCTAssertEqual(only("  2031-03-07: ", in: Self.activity(text)), "  2031-03-07: 0 apple-health")
        // SPEC-AMBIGUITY: §7.7 gives the missing form as "<day>: —" with no "(today so far)" suffix, so
        // a missing today is printed bare.
        XCTAssertEqual(only("  2031-03-16: ", in: Self.activity(text)), "  2031-03-16: —")
        // 111670 over 13 full days, the zero included: 8590.
        XCTAssertEqual(only("steps average: ", in: text),
                       "steps average: 8590 over 13 of 13 full days (apple-health 11, strap-estimate 2)")
        // Counts round halves away from zero.
        draft.steps = [F.step("2031-03-03", 9120.5), F.step("2031-03-04", 9119.49)]
        XCTAssertEqual(only("  2031-03-03: ", in: Self.activity(draft.text)), "  2031-03-03: 9121 apple-health")
        XCTAssertEqual(only("  2031-03-04: ", in: Self.activity(draft.text)), "  2031-03-04: 9119 apple-health")
    }

    func testWorkoutWithNothingButATimePrintsDashes() {
        var draft = F.full
        draft.workouts = [F.workout("2031-03-08", 9, 30, "hiking", .manual)]
        XCTAssertEqual(workoutRows(draft.text), ["  2031-03-08 09:30 hiking, — min, avg HR —, — kcal [manual]"])
        XCTAssertEqual(only("workouts in range", in: draft.text),
                       "workouts in range, oldest first, summaries only:")
        // Every clause present, for comparison (§7.9).
        draft.workouts = [F.workout("2031-03-05", 7, 5, "cycling", .appleHealth, min: 45, hr: 132,
                                    kcal: 410, km: 18.4)]
        XCTAssertEqual(workoutRows(draft.text),
                       ["  2031-03-05 07:05 cycling, 45 min, avg HR 132 bpm, 410 kcal, 18.40 km [apple-health]"])
        // A measured zero is printed as zero; rounding is halves away from zero.
        draft.workouts = [F.workout("2031-03-05", 7, 5, "cycling", .activityFile, min: 0, hr: 1, kcal: 0,
                                    km: 0)]
        XCTAssertEqual(workoutRows(draft.text),
                       ["  2031-03-05 07:05 cycling, 0 min, avg HR 1 bpm, 0 kcal, 0.00 km [activity-file]"])
        draft.workouts = [F.workout("2031-03-05", 7, 5, "cycling", .whoop, min: 44.5, hr: 300,
                                    kcal: 409.5, km: 3.456)]
        XCTAssertEqual(workoutRows(draft.text),
                       ["  2031-03-05 07:05 cycling, 45 min, avg HR 300 bpm, 410 kcal, 3.46 km [whoop]"])
    }

    func testWorkoutHeartRateAndStartMinuteAreBoundedAtTheirEdges() {
        func row(minute: Int, hr: Int?) -> String {
            var draft = F.full
            draft.workouts = [CoachPacketWorkout(day: "2031-03-08", startMinuteOfDay: minute,
                                                 sport: "hiking", source: .manual, durationMinutes: 30,
                                                 avgHr: hr, energyKcal: 200, distanceKm: nil)]
            return workoutRows(draft.text).first ?? ""
        }
        XCTAssertEqual(row(minute: 570, hr: 0), "  2031-03-08 09:30 hiking, 30 min, avg HR —, 200 kcal [manual]")
        XCTAssertEqual(row(minute: 570, hr: 1), "  2031-03-08 09:30 hiking, 30 min, avg HR 1 bpm, 200 kcal [manual]")
        XCTAssertEqual(row(minute: 570, hr: 300), "  2031-03-08 09:30 hiking, 30 min, avg HR 300 bpm, 200 kcal [manual]")
        XCTAssertEqual(row(minute: 570, hr: 301), "  2031-03-08 09:30 hiking, 30 min, avg HR —, 200 kcal [manual]")
        XCTAssertEqual(row(minute: 570, hr: -60), "  2031-03-08 09:30 hiking, 30 min, avg HR —, 200 kcal [manual]")
        XCTAssertEqual(row(minute: 0, hr: nil), "  2031-03-08 00:00 hiking, 30 min, avg HR —, 200 kcal [manual]")
        XCTAssertEqual(row(minute: 1439, hr: nil), "  2031-03-08 23:59 hiking, 30 min, avg HR —, 200 kcal [manual]")
        XCTAssertEqual(row(minute: 1440, hr: nil), "  2031-03-08 --:-- hiking, 30 min, avg HR —, 200 kcal [manual]")
        XCTAssertEqual(row(minute: -1, hr: nil), "  2031-03-08 --:-- hiking, 30 min, avg HR —, 200 kcal [manual]")
        XCTAssertEqual(row(minute: Int.max, hr: Int.max), "  2031-03-08 --:-- hiking, 30 min, avg HR —, 200 kcal [manual]")
        XCTAssertEqual(row(minute: Int.min, hr: Int.min), "  2031-03-08 --:-- hiking, 30 min, avg HR —, 200 kcal [manual]")
    }

    /// `count` workouts in the fixture range, two a day at 10:00 and 16:40, named by their position
    /// once ordered.
    private func manyWorkouts(_ count: Int) -> [CoachPacketWorkout] {
        (0..<count).map { index in
            CoachPacketWorkout(day: F.rangeDays[index / 2], startMinuteOfDay: index % 2 == 0 ? 600 : 1000,
                               sport: "run\(index)", source: .manual, durationMinutes: 30, avgHr: nil,
                               energyKcal: nil, distanceKm: nil)
        }
    }

    private func manyWorkoutRow(_ index: Int) -> String {
        "  \(F.rangeDays[index / 2]) \(index % 2 == 0 ? "10:00" : "16:40") run\(index), 30 min, avg HR —, — kcal [manual]"
    }

    func testMoreThanTwentyWorkoutsPrintsTheCount() {
        func block(_ count: Int) -> [String] {
            var draft = F.full
            // Handed over newest first, so the order printed is the renderer's own.
            draft.workouts = manyWorkouts(count).reversed()
            let section = F.section("== ACTIVITY ==", in: draft.text) ?? []
            guard let lead = section.firstIndex(of: "workouts in range, oldest first, summaries only:") else {
                XCTFail("no workout lead line for \(count)")
                return []
            }
            return Array(section[(lead + 1)...])
        }
        XCTAssertEqual(block(20), (0..<20).map(manyWorkoutRow))
        XCTAssertEqual(block(21), ["  (1 earlier workouts in range not shown)"] + (1..<21).map(manyWorkoutRow))
        XCTAssertEqual(block(25), ["  (5 earlier workouts in range not shown)"] + (5..<25).map(manyWorkoutRow))
        XCTAssertEqual(block(19), (0..<19).map(manyWorkoutRow))
        XCTAssertEqual(block(1), [manyWorkoutRow(0)])
    }

    func testWorkoutsAreOrderedByDayThenStartMinute() {
        var draft = F.full
        draft.workouts = [
            F.workout("2031-03-05", 18, 0, "third", .manual, min: 10),
            F.workout("2031-03-05", 6, 0, "second", .manual, min: 10),
            F.workout("2031-03-04", 23, 59, "first", .manual, min: 10),
            F.workout("2031-03-16", 0, 0, "fourth", .manual, min: 10),
        ]
        XCTAssertEqual(workoutRows(draft.text).map { String($0.dropFirst(2).prefix(16)) },
                       ["2031-03-04 23:59", "2031-03-05 06:00", "2031-03-05 18:00", "2031-03-16 00:00"])
    }

    func testNoWorkoutsSaysSo() {
        let text = F.full { $0.workouts = [] }.text
        XCTAssertEqual(F.section("== ACTIVITY ==", in: text)?.last, "workouts: none recorded in range")
        XCTAssertEqual(F.lines(startingWith: "workouts in range", in: text), [])
        XCTAssertEqual(workoutRows(text), [])
        // Workouts outside the range are not "in range".
        let outside = F.full { $0.workouts = [F.workout("2031-03-02", 9, 0, "hiking", .manual, min: 30)] }.text
        XCTAssertEqual(F.section("== ACTIVITY ==", in: outside)?.last, "workouts: none recorded in range")
    }

    // MARK: - Free text

    func testFreeTextIsOneLineQuotedSafelyAndCutAtFortyEightBytes() {
        XCTAssertEqual(CoachPacket.sanitize("Fixture cut"), "Fixture cut")
        XCTAssertEqual(CoachPacket.sanitize("  two\n lines\t\"quoted\"  "), "two lines 'quoted'")
        XCTAssertEqual(CoachPacket.sanitize("a\r\nb\u{0}c\u{7F}d\u{2028}e\u{1B}f"), "a b c d e f")
        XCTAssertEqual(CoachPacket.sanitize("a   b     c"), "a b c")
        XCTAssertEqual(CoachPacket.sanitize("\"\""), "''")
        XCTAssertEqual(CoachPacket.sanitize(""), "unnamed")
        // SPEC-AMBIGUITY: §6.2 says "Empty input gives unnamed". Text that is empty once cleaned is
        // read the same way, so no line ever carries an empty name.
        XCTAssertEqual(CoachPacket.sanitize(" \n\t "), "unnamed")

        // The cut: 48 bytes pass whole, 49 lose one, and a character is never split.
        let a48 = String(repeating: "a", count: 48)
        XCTAssertEqual(CoachPacket.sanitize(a48), a48)
        XCTAssertEqual(CoachPacket.sanitize(a48 + "a"), a48)
        XCTAssertEqual(CoachPacket.sanitize(String(repeating: "a", count: 47)), String(repeating: "a", count: 47))
        XCTAssertEqual(CoachPacket.sanitize(String(repeating: "a", count: 4000)), a48)
        let e24 = String(repeating: "é", count: 24)
        XCTAssertEqual(e24.utf8.count, 48)
        XCTAssertEqual(CoachPacket.sanitize(e24), e24)
        XCTAssertEqual(CoachPacket.sanitize(e24 + "é"), e24)
        XCTAssertEqual(CoachPacket.sanitize(String(repeating: "a", count: 46) + "é"),
                       String(repeating: "a", count: 46) + "é")
        XCTAssertEqual(CoachPacket.sanitize(String(repeating: "a", count: 47) + "é"),
                       String(repeating: "a", count: 47))
        let smile11 = String(repeating: "😀", count: 11)
        XCTAssertEqual(CoachPacket.sanitize(smile11 + "aaaaa"), smile11 + "aaaa")
        XCTAssertEqual(CoachPacket.sanitize(String(repeating: "😀", count: 13)),
                       String(repeating: "😀", count: 12))

        // In the packet: a phase name cannot break out of its quotes or its line.
        let phase = CoachPacketPhase(name: "Cut\n\"A\"\r\n== NOTES ==", startDay: "2031-01-06",
                                     targetWeightKg: 94.0, rateLowPercentPerWeek: 0.40,
                                     rateHighPercentPerWeek: 1.20)
        let named = draft(result: F.result(), phase: phase).text
        XCTAssertEqual(only("phase: ", in: named),
                       "phase: \"Cut 'A' == NOTES ==\" (cut), started 2031-01-06, target 94.0 kg, band 0.40 to 1.20 %/week")
        XCTAssertEqual(F.lines(named).count, F.lines(G.g1).count)
        XCTAssertEqual(headings(named), headings(G.g1))
        let long = CoachPacketPhase(name: String(repeating: "N", count: 300), startDay: "2031-01-06",
                                    targetWeightKg: nil, rateLowPercentPerWeek: 0.40,
                                    rateHighPercentPerWeek: 1.20)
        XCTAssertEqual(only("phase: ", in: draft(result: F.result(), phase: long).text),
                       "phase: \"" + String(repeating: "N", count: 48)
                           + "\" (cut), started 2031-01-06, no target, band 0.40 to 1.20 %/week")
        let unnamed = CoachPacketPhase(name: "", startDay: "2031-01-06", targetWeightKg: nil,
                                       rateLowPercentPerWeek: 0.40, rateHighPercentPerWeek: 1.20)
        XCTAssertTrue(only("phase: ", in: draft(result: F.result(), phase: unnamed).text)
            .hasPrefix("phase: \"unnamed\" (cut), "))

        // And a sport name is one line of at most 48 bytes.
        var sports = F.full
        sports.workouts = [
            F.workout("2031-03-08", 9, 30, "trail\nrun \"long\"\n== SCORECARD ==", .manual, min: 30),
            F.workout("2031-03-09", 9, 30, String(repeating: "s", count: 200), .manual, min: 30),
            F.workout("2031-03-10", 9, 30, "", .manual, min: 30),
        ]
        XCTAssertEqual(workoutRows(sports.text), [
            "  2031-03-08 09:30 trail run 'long' == SCORECARD ==, 30 min, avg HR —, — kcal [manual]",
            "  2031-03-09 09:30 " + String(repeating: "s", count: 48) + ", 30 min, avg HR —, — kcal [manual]",
            "  2031-03-10 09:30 unnamed, 30 min, avg HR —, — kcal [manual]",
        ])
        XCTAssertEqual(headings(sports.text), headings(G.g1))
    }

    func testGeneratedFreeTextIsAlwaysOneSafeLineWithinTheLimit() {
        var g = F.Generator(seed: 0x5A17_12E5_0002)
        let pieces = ["a", "B", " ", "  ", "\n", "\r\n", "\t", "\"", "'", "é", "ß", "😀", "\u{0}",
                      "\u{7F}", "\u{2028}", "\u{2029}", "\u{85}", "==", "—", ",", ";", "x1", "Fixture"]
        for round in 0..<400 {
            var raw = ""
            for _ in 0..<g.int(0...40) { raw += g.pick(pieces) }
            let clean = CoachPacket.sanitize(raw)
            XCTAssertFalse(clean.isEmpty, "round \(round)")
            XCTAssertLessThanOrEqual(clean.utf8.count, 48, "round \(round)")
            XCTAssertFalse(clean.contains("\""), "round \(round)")
            XCTAssertFalse(clean.contains("  "), "round \(round)")
            XCTAssertFalse(clean.hasPrefix(" "), "round \(round)")
            for scalar in clean.unicodeScalars {
                XCTAssertFalse(scalar.properties.generalCategory == .control, "round \(round)")
                XCTAssertFalse(scalar == "\u{2028}" || scalar == "\u{2029}", "round \(round)")
            }
            XCTAssertEqual(CoachPacket.sanitize(raw), clean, "round \(round): same input, same text")
        }
    }

    // MARK: - Missing is never zero

    func testNegativeZeroNeverPrints() {
        let weeks = [
            F.week("2031-02-24", 97.2, 97.0, on: "2031-02-26", loss: 0.04),
            F.week("2031-03-03", 97.1, 97.0, on: "2031-03-05", loss: 0.0),
            F.week("2031-03-10", 97.1, 97.0, on: "2031-03-12", loss: -0.04),
        ]
        let result = F.result(
            weeks: weeks,
            rate: CutScorecardRate(lossKgPerWeek: -0.0004, percentPerWeek: -0.004,
                                   referenceWeightKg: 97.3, pointsUsed: 5, spanWeeks: 4,
                                   firstWeekStart: "2031-02-03", lastWeekStart: "2031-03-03"),
            projection: CutScorecardProjection(status: .targetReached, targetDay: nil,
                                               weeksRemaining: nil, remainingKg: -0.04),
            waist: CutScorecardWaistSignal(state: .notMet, reason: .notShrinking, currentCm: 97.0,
                                           referenceCm: 97.0, referenceWeekStart: "2031-02-17",
                                           changeCm: -0.04),
            rateBand: CutScorecardRateBandSignal(state: .notMet, reason: .belowBand,
                                                 percentPerWeek: -0.004, lowPercentPerWeek: 0.40,
                                                 highPercentPerWeek: 1.20))
        let text = draft(result: result).text
        XCTAssertTrue(only("signal waist: ", in: text).hasSuffix("; change +0.0 cm"))
        XCTAssertTrue(only("signal rate-band: ", in: text).contains("; 0.00 %/week; "))
        XCTAssertTrue(only("rate: ", in: text).hasPrefix("rate: flat 0.00 kg/week (0.00 %/week of 97.3 kg)"))
        XCTAssertEqual(only("projection: ", in: text), "projection: none (targetReached); 0.0 kg remaining")
        XCTAssertEqual(rows("== WEIGH-INS ==", in: text).map { String($0.suffix(14)) },
                       ["change +0.0 kg", "change +0.0 kg", "change +0.0 kg"])
        XCTAssertTrue(only("RHR: ", in: text).contains("(+0 vs baseline)"))
        XCTAssertEqual(matches("-0(\\.0+)?(?![0-9.])", in: text), [], "a negative zero was printed")
        // One step further from zero the sign is real and is kept.
        let real = F.result(
            weeks: [F.week("2031-03-03", 97.1, 97.0, on: "2031-03-05", loss: 0.06),
                    F.week("2031-03-10", 97.1, 97.0, on: "2031-03-12", loss: -0.06)],
            waist: CutScorecardWaistSignal(state: .met, reason: .shrinking, currentCm: 97.0,
                                           referenceCm: 97.0, referenceWeekStart: "2031-02-17",
                                           changeCm: -0.06))
        let realText = draft(result: real).text
        XCTAssertTrue(only("signal waist: ", in: realText).hasSuffix("; change -0.1 cm"))
        XCTAssertEqual(rows("== WEIGH-INS ==", in: realText).map { String($0.suffix(14)) },
                       ["change -0.1 kg", "change +0.1 kg"])
    }

    func testNoZeroIsPrintedForAMissingValue() {
        // Every numeric field the packet can leave unmeasured is nil here; the counts the scorecard
        // always states are set to non-zero numbers so that any zero left in the text is a fault.
        var draft = F.empty
        draft.days = F.rangeDays.dropLast(3).map { F.row($0) }
        draft.workouts = [F.workout("2031-03-08", 12, 34, "hiking", .manual)]
        let unknown = { (rule: CutScorecardRule, required: Int) in
            CutScorecardRuleEvaluation(rule: rule, state: .unknown, unknownReason: .noReadings,
                                       consecutiveWeeks: 1, requiredWeeks: required)
        }
        let result = F.result(
            weeks: [F.week("2031-03-03", nil, nil, on: nil, loss: nil),
                    F.week("2031-03-10", nil, nil, on: nil, loss: nil)],
            judgedWeekStart: nil, rate: .some(nil), rateUnavailable: .noReadings,
            projection: CutScorecardProjection(status: .rateUnknown, targetDay: nil,
                                               weeksRemaining: nil, remainingKg: nil),
            waist: CutScorecardWaistSignal(state: .unknown, reason: .noReadings, currentCm: nil,
                                           referenceCm: nil, referenceWeekStart: nil, changeCm: nil),
            lifts: CutScorecardLiftSignal(state: .unknown, reason: .noLiftData, commonExercises: 0,
                                          dropped: 0, climbed: 0, held: 0, windowStartDay: nil,
                                          windowEndDay: nil),
            protein: CutScorecardProteinSignal(state: .unknown, reason: .noFloorConfigured,
                                               daysLogged: 1, daysAtOrAboveFloor: 1, requiredDays: 5,
                                               floorGrams: nil),
            rateBand: CutScorecardRateBandSignal(state: .unknown, reason: .rateUnknown,
                                                 percentPerWeek: nil, lowPercentPerWeek: nil,
                                                 highPercentPerWeek: nil),
            rules: [unknown(.liftsHoldingWaistShrinking, 1), unknown(.liftsDropping, 3),
                    unknown(.slowLoss, 3)],
            verdict: F.verdict(kind: .insufficientData, reason: .noReadings))
        draft.scorecard = .evaluated(phase: CoachPacketPhase(name: "Fixture cut", startDay: "2031-01-06",
                                                             targetWeightKg: nil,
                                                             rateLowPercentPerWeek: 0.45,
                                                             rateHighPercentPerWeek: 1.25),
                                     result: result)
        var text = draft.text
        XCTAssertEqual(only("HRV: ", in: text), "HRV: baseline not available; range mean — over 0 nights")
        // SPEC-AMBIGUITY: §12.1 says the text "has no standalone 0", but §7.6 itself mandates "over 0
        // nights" for a metric with no value: a count of nights, not a value. That one clause is taken
        // out before the scan, and a zero is a token that is nothing but zero digits with an optional
        // sign, tilde, decimal part and unit ("0", "0.0h", "0%", "~0", "+0.0"); "(0-100)" and the digits
        // of a date or a time are not such tokens.
        text = text.replacingOccurrences(of: "range mean — over 0 nights", with: "range mean — over no nights")
        let separators = CharacterSet(charactersIn: " ,;()[]\n\"")
        let zero = "^[+~-]?0+(\\.0+)?(h|ms|bpm|%|kg|cm|g|km|kcal|min)?$"
        for token in text.components(separatedBy: separators) where !token.isEmpty {
            XCTAssertEqual(matches(zero, in: token), [], "a zero was printed for a missing value: \(token)")
        }
        // The dashes are where the values would be.
        XCTAssertEqual(only("  2031-03-03: recovery", in: text),
                       "  2031-03-03: recovery —, strain —, sleep —, deep —, REM —, light —, eff —, "
                           + "HRV —, RHR —")
        XCTAssertEqual(only("averages over ", in: text),
                       "averages over 11 of 14 days with data: recovery: —, strain: —, sleep: —h, "
                           + "HRV: — ms, RHR: — bpm")
        XCTAssertEqual(workoutRows(text), ["  2031-03-08 12:34 hiking, — min, avg HR —, — kcal [manual]"])
        XCTAssertEqual(only("current weight: ", in: text), "current weight: —")
        XCTAssertEqual(rows("== WEIGH-INS ==", in: text),
                       ["  2031-03-03: weight —, waist —, change —", "  2031-03-10: weight —, waist —, change —"])
        // The scan itself does find a planted zero in each of the shapes a fault would give it.
        for planted in ["recovery 0,", "strain 0.0,", "sleep 0.0h,", "eff 0%,", "HRV 0ms,", "RHR 0bpm",
                        ": 0 apple-health", ": ~0 strap-estimate", "weight 0.0 kg", "change +0.0 kg",
                        "0 min,", "avg HR 0 bpm", "0 kcal", "mean 0 ms"] {
            let found = planted.components(separatedBy: separators)
                .contains { !matches(zero, in: $0).isEmpty }
            XCTAssertTrue(found, "the scan must see \"\(planted)\"")
        }
    }

    // MARK: - Determinism, order and input handling

    func testSameInputGivesTheSameBytes() {
        for draft in [F.full, F.empty, F.full { $0.sections = [] }, F.full { $0.rangeEndDay = "nope" }] {
            let first = CoachPacket.render(draft.input)
            let second = CoachPacket.render(draft.input)
            XCTAssertEqual(Data(first.utf8), Data(second.utf8))
            // An equal input built separately gives the same bytes as well.
            var copy = F.Draft()
            copy.rangeEndDay = draft.rangeEndDay
            copy.sections = draft.sections
            copy.days = Array(draft.days)
            copy.scorecard = draft.scorecard
            copy.body = draft.body
            copy.hrvBaseline = draft.hrvBaseline
            copy.restingHrBaseline = draft.restingHrBaseline
            copy.steps = draft.steps
            copy.workouts = draft.workouts
            copy.intake = draft.intake
            copy.events = draft.events
            XCTAssertEqual(copy.input, draft.input)
            XCTAssertEqual(Data(CoachPacket.render(copy.input).utf8), Data(first.utf8))
        }
    }

    func testInputOrderDoesNotChangeTheBytes() {
        // Rows, steps, workouts and body readings with distinct keys print in the renderer's order,
        // whatever order they arrive in.
        var g = F.Generator(seed: 0x0D0E_0002)
        for round in 0..<25 {
            var draft = F.full
            draft.days = g.shuffled(F.days)
            draft.steps = g.shuffled(F.steps)
            draft.workouts = g.shuffled(F.workouts)
            draft.body = g.shuffled(F.body)
            assertSameText(draft.text, G.g1, "shuffle \(round)")
        }
    }

    func testDuplicateDayKeepsTheLastRow() {
        let late = F.row("2031-03-03", recovery: 10, strain: 100, sleep: 60, hrv: 20, rhr: 90)
        let appended = F.full { $0.days = F.days + [late] }.text
        XCTAssertEqual(only("  2031-03-03: recovery", in: appended),
                       "  2031-03-03: recovery 10, strain 21.0, sleep 1.0h, deep —, REM —, light —, eff —, "
                           + "HRV 20ms, RHR 90bpm")
        // The day is counted once, and the row that lost is in no average.
        XCTAssertTrue(only("averages over ", in: appended).hasPrefix("averages over 13 of 14 days with data: "))
        XCTAssertEqual(dayRowKeys("== RECOVERY AND SLEEP ==", in: appended), F.rangeDays)
        // HRV: 704 − 58 + 20 = 666 over 12 nights = 55.5, which prints 56; 20 and 47 are below 50.8.
        XCTAssertTrue(only("HRV: ", in: appended)
            .contains("range mean 56 ms over 12 nights (-1 vs baseline)"), only("HRV: ", in: appended))
        XCTAssertTrue(only("HRV: ", in: appended).hasSuffix("outside typical: 2 below, 2 above"))
        // The other way round, the fixture's row is last and the text is G1.
        assertSameText(F.full { $0.days = [late] + F.days }.text, G.g1)

        // Steps: 111670 − 9120 + 5000 = 107550 over 12 days = 8962.5, which prints 8963.
        let steps = F.full { $0.steps = F.steps + [F.step("2031-03-03", 5000, .strap)] }.text
        XCTAssertEqual(only("  2031-03-03: ", in: Self.activity(steps)), "  2031-03-03: 5000 strap")
        XCTAssertEqual(only("steps average: ", in: steps),
                       "steps average: 8963 over 12 of 13 full days (strap 1, apple-health 9, strap-estimate 2)")
        assertSameText(F.full { $0.steps = [F.step("2031-03-03", 5000, .strap)] + F.steps }.text, G.g1)
    }

    func testItemsOutsideTheRangeAreIgnored() {
        let strays = ["2031-03-02", "2031-03-17", "2030-03-10", "garbage", "2031-3-4", "", " 2031-03-04",
                      "2031-02-30"]
        var draft = F.full
        for day in strays {
            draft.days.append(F.row(day, recovery: 1, strain: 99, sleep: 30, deep: 5, rem: 5, light: 5,
                                    eff: 0.5, hrv: 200, rhr: 30))
            draft.steps.append(F.step(day, 50_000, .strap))
            draft.workouts.append(F.workout(day, 12, 0, "stray", .whoop, min: 500, hr: 190, kcal: 900,
                                            km: 42))
        }
        assertSameText(draft.text, G.g1)
        XCTAssertFalse(draft.text.contains("stray"))
        // The day before the range and the first day of it sit either side of the edge.
        var edge = F.full
        edge.steps = [F.step("2031-03-02", 4000), F.step("2031-03-03", 6000)]
        XCTAssertEqual(only("steps average: ", in: edge.text),
                       "steps average: 6000 over 1 of 13 full days (apple-health 1)")
        // Workouts outside the range are not counted as "earlier workouts in range" either.
        var many = F.full
        many.workouts = manyWorkouts(20) + [F.workout("2031-03-02", 9, 0, "stray", .manual, min: 30),
                                            F.workout("2031-03-17", 9, 0, "stray", .manual, min: 30)]
        XCTAssertFalse(many.text.contains("not shown"))
        XCTAssertEqual(workoutRows(many.text).count, 20)
    }

    func testNonFiniteInputsAreAbsentAndNothingTraps() {
        let bad: [Double] = [.nan, .infinity, -.infinity]

        for value in bad + [0, -1, -97.1] {
            let text = F.full {
                $0.body = [CoachPacketBodyReading(kind: .weight, value: value, source: .labBook,
                                                  day: "2031-03-05"),
                           CoachPacketBodyReading(kind: .waist, value: value, source: .labBook,
                                                  day: "2031-03-05")]
                $0.hrvBaseline = CoachPacketBaseline(center: value, typical: 50.8...63.6,
                                                     status: "trusted", nights: 21)
            }.text
            XCTAssertEqual(only("current weight: ", in: text), "current weight: —", "\(value)")
            XCTAssertEqual(only("current waist: ", in: text), "current waist: —", "\(value)")
            // A baseline whose centre is not a positive finite number is absent.
            XCTAssertEqual(only("HRV: ", in: text),
                           "HRV: baseline not available; range mean 59 ms over 12 nights; "
                               + "last 7 days mean 60 ms over 6 nights", "\(value)")
        }
        // The smallest positive values are values.
        let small = F.full {
            $0.body = [CoachPacketBodyReading(kind: .weight, value: 0.1, source: .labBook, day: nil)]
        }.text
        XCTAssertEqual(only("current weight: ", in: small), "current weight: 0.1 kg (lab-book)")

        for value in bad + [-1, -0.5] {
            var draft = F.full
            draft.steps = [F.step("2031-03-03", value), F.step("2031-03-04", 6000)]
            draft.workouts = [F.workout("2031-03-08", 9, 30, "hiking", .manual, min: value, hr: 120,
                                        kcal: value, km: value)]
            let text = draft.text
            XCTAssertEqual(only("  2031-03-03: ", in: Self.activity(text)), "  2031-03-03: —", "\(value)")
            XCTAssertEqual(only("steps average: ", in: text),
                           "steps average: 6000 over 1 of 13 full days (apple-health 1)", "\(value)")
            XCTAssertEqual(workoutRows(text),
                           ["  2031-03-08 09:30 hiking, — min, avg HR 120 bpm, — kcal [manual]"], "\(value)")
        }

        // Daily rows: rule F1 of the shared formatter, and the trend means leave the value out.
        for value in bad + [1e300, -1e300] {
            var draft = F.full
            draft.days = F.days + [F.row("2031-03-07", recovery: value, strain: value, sleep: value,
                                         deep: value, rem: value, light: value, eff: value, hrv: value,
                                         rhr: 54)]
            let text = draft.text
            XCTAssertEqual(only("  2031-03-07: recovery", in: text),
                           "  2031-03-07: recovery —, strain —, sleep —, deep —, REM —, light —, eff —, "
                               + "HRV —, RHR 54bpm", "\(value)")
            XCTAssertEqual(only("HRV: ", in: text), g1HrvLine, "\(value)")
        }

        // Weekly points: a weight or waist that is not a positive finite number is a dash.
        for value in bad + [0, -5] {
            let weeks = [CutScorecardWeek(weekStart: "2031-03-03", weightKg: value, weightDay: "2031-03-05",
                                          waistCm: value, waistDay: "2031-03-05", inPhase: true,
                                          weeklyLossKg: nil)]
            XCTAssertEqual(rows("== WEIGH-INS ==", in: draft(result: F.result(weeks: weeks)).text),
                           ["  2031-03-03: weight —, waist —, change —"], "\(value)")
        }

        // Everything else: `render` is total. A scorecard result full of non-finite numbers, a
        // non-finite strain factor and absurd counts produce a packet and do not trap.
        for value in bad + [.greatestFiniteMagnitude, -.greatestFiniteMagnitude, 1e19] {
            let result = F.result(
                weeks: [CutScorecardWeek(weekStart: "2031-03-03", weightKg: 97.1, weightDay: "2031-03-05",
                                         waistCm: 97.0, waistDay: "2031-03-05", inPhase: true,
                                         weeklyLossKg: value)],
                rate: CutScorecardRate(lossKgPerWeek: value, percentPerWeek: value,
                                       referenceWeightKg: value, pointsUsed: Int.max, spanWeeks: Int.min,
                                       firstWeekStart: "2031-02-03", lastWeekStart: "2031-03-03"),
                projection: CutScorecardProjection(status: .projected, targetDay: "2031-10-08",
                                                   weeksRemaining: value, remainingKg: value),
                waist: CutScorecardWaistSignal(state: .met, reason: .shrinking, currentCm: value,
                                               referenceCm: value, referenceWeekStart: "2031-02-17",
                                               changeCm: value),
                protein: CutScorecardProteinSignal(state: .unknown, reason: .noProteinData,
                                                   daysLogged: Int.max, daysAtOrAboveFloor: Int.min,
                                                   requiredDays: Int.max, floorGrams: value),
                rateBand: CutScorecardRateBandSignal(state: .met, reason: .withinBand,
                                                     percentPerWeek: value, lowPercentPerWeek: value,
                                                     highPercentPerWeek: value),
                verdict: F.verdict(calories: Int.min),
                rejections: CutScorecardRejections(nonFinite: Int.max, nonPositive: Int.max,
                                                   invalidDay: Int.max, future: Int.max))
            var draft = F.full
            draft.strainFactor = value
            draft.scorecard = .evaluated(
                phase: CoachPacketPhase(name: "Fixture cut", startDay: "2031-01-06", targetWeightKg: value,
                                        rateLowPercentPerWeek: value, rateHighPercentPerWeek: value),
                result: result)
            draft.hrvBaseline = CoachPacketBaseline(center: 57.2, typical: 50.8...63.6, status: "trusted",
                                                    nights: Int.max)
            draft.steps = [F.step("2031-03-03", 1e19), F.step("2031-03-04", .greatestFiniteMagnitude)]
            draft.workouts = [F.workout("2031-03-08", 9, 30, "hiking", .manual, min: 1e19, hr: 120,
                                        kcal: .greatestFiniteMagnitude, km: 1e19)]
            let text = draft.text
            XCTAssertEqual(F.lines(text).first, "NOOP-COACH-PACKET v2", "\(value)")
            XCTAssertTrue(text.hasSuffix("end of NOOP-COACH-PACKET v2\n"), "\(value)")
            XCTAssertEqual(headings(text), headings(G.g1), "\(value)")
        }
    }

    // MARK: - Grammar (§7 and §7.12)

    private var grammarSamples: [(String, String)] {
        [("G1", F.full.text), ("G2", F.empty.text), ("all off", F.full { $0.sections = [] }.text),
         ("invalid range", F.full { $0.rangeStartDay = "" }.text),
         ("switched off", F.full { $0.scorecard = .switchedOff }.text),
         ("widest 28", widest(days: 28).text)]
    }

    func testTextEndsWithOneNewlineAndHasNoTrailingSpacesOrTabs() {
        for (name, text) in grammarSamples {
            XCTAssertTrue(text.hasSuffix("\n"), name)
            XCTAssertFalse(text.hasSuffix("\n\n"), name)
            XCTAssertFalse(text.contains("\t"), name)
            XCTAssertFalse(text.contains("\r"), name)
            XCTAssertFalse(text.hasPrefix("\n"), name)
            for line in F.lines(text) {
                XCTAssertFalse(line.hasSuffix(" "), "\(name): trailing space in \"\(line)\"")
            }
        }
    }

    func testFirstAndLastLinesCarryTheVersion() {
        let first = "\(CoachPacket.formatName) v\(CoachPacket.formatVersion)"
        XCTAssertEqual(first, "NOOP-COACH-PACKET v2")
        for (name, text) in grammarSamples {
            XCTAssertEqual(F.lines(text).first, "NOOP-COACH-PACKET v2", name)
            XCTAssertEqual(F.lines(text).last, "end of NOOP-COACH-PACKET v2", name)
        }
    }

    func testHeadingsAreUpperCaseAsciiInTheFixedOrder() {
        let order = G.sectionOrder.map(\.heading) + ["== NOTES =="]
        XCTAssertEqual(headings(F.full.text), order)
        for (name, text) in grammarSamples {
            for heading in headings(text) {
                XCTAssertEqual(matches("^== [A-Z][A-Z -]*[A-Z] ==$", in: heading), [heading], name)
            }
            // No other heading style: nothing else begins with "=" or "#", and there are no bullets.
            for line in F.lines(text) where !line.hasPrefix("== ") {
                XCTAssertFalse(line.hasPrefix("="), "\(name): \(line)")
                XCTAssertFalse(line.hasPrefix("#"), "\(name): \(line)")
                XCTAssertFalse(line.hasPrefix("- "), "\(name): \(line)")
                XCTAssertFalse(line.hasPrefix("  - "), "\(name): \(line)")
            }
        }
        // Every subset of sections keeps the fixed order.
        for mask in 0..<(1 << CoachPacketSection.allCases.count) {
            var sections = Set<CoachPacketSection>()
            var expected: [String] = []
            for (bit, section) in CoachPacketSection.allCases.enumerated() where mask & (1 << bit) != 0 {
                sections.insert(section)
                expected.append(G.sectionOrder[bit].heading)
            }
            let text = F.full { $0.sections = sections }.text
            XCTAssertEqual(headings(text), expected + ["== NOTES =="], "mask \(mask)")
            assertSameText(text, G.g1(withSectionsOff: Set(G.sectionOrder.map(\.id))
                .subtracting(sections.map(\.rawValue))), "mask \(mask)")
        }
    }

    func testBodyRowsAreIndentedByExactlyTwoSpacesAndSectionsBySingleBlankLines() {
        for (name, text) in grammarSamples {
            let lines = F.lines(text)
            for (index, line) in lines.enumerated() {
                if line.hasPrefix(" ") {
                    XCTAssertTrue(line.hasPrefix("  "), "\(name): \(line)")
                    XCTAssertFalse(line.hasPrefix("   "), "\(name): \(line)")
                }
                if line.isEmpty {
                    // A blank line is always followed by a heading, and never by another blank line.
                    XCTAssertTrue(index + 1 < lines.count && lines[index + 1].hasPrefix("== "),
                                  "\(name): blank line \(index + 1)")
                }
                if line.hasPrefix("== ") {
                    XCTAssertTrue(index > 0 && lines[index - 1].isEmpty, "\(name): \(line)")
                    XCTAssertTrue(index + 1 < lines.count && !lines[index + 1].isEmpty, "\(name): \(line)")
                }
            }
        }
    }

    // `testIntakeAndEventsNeverAppearAsSections` is replaced by packet v2 (§7.12, "Tests") with
    // `testVersionTwoNamesNothingAsNotRecorded` and the two feature-off tests in CoachPacketV2Tests.

    func testNotesAreConstantAndMakeNoMedicalClaim() {
        let notes = G.blocks(G.g1)[8]
        for (name, text) in grammarSamples {
            XCTAssertEqual(G.blocks(text).last, notes, name)
        }
        XCTAssertTrue(notes.contains("makes no medical claim"))
        XCTAssertTrue(notes.contains("steps marked strap-estimate"))
    }

    // MARK: - Size budget

    func testFullFixtureIsWithinTheBudget() {
        // Version 2 (ruling A5): 8000 + 290 × days + the events allowance of 2,000.
        XCTAssertEqual(CoachPacket.byteBudget(rangeDays: 7), 12_030)
        XCTAssertEqual(CoachPacket.byteBudget(rangeDays: 14), 14_060)
        XCTAssertEqual(CoachPacket.byteBudget(rangeDays: 28), 18_120)
        XCTAssertEqual(CoachPacket.byteBudget(rangeDays: 1), 10_290)
        XCTAssertEqual(F.full.text.utf8.count, 7_173)
        XCTAssertLessThanOrEqual(F.full.text.utf8.count, CoachPacket.byteBudget(rangeDays: 14))
        XCTAssertLessThanOrEqual(F.empty.text.utf8.count, CoachPacket.byteBudget(rangeDays: 14))
    }

    /// The widest input the renderer can be handed for a range ending on the fixture's day: every
    /// clause present, every free-text field far over its limit, many more weeks and workouts than the
    /// limits, and every number at the top of the range the app produces.
    ///
    /// SPEC-AMBIGUITY: §7.10 says "every other line has a fixed widest form" without bounding the
    /// numbers. The bounds used here are the app's: scores to 100, a day of 1,439 minutes, 300 bpm,
    /// five-digit steps, four-digit kilocalories, three-digit kilograms and kilometres.
    private func widest(days count: Int) -> F.Draft {
        let keys = (0..<count).map { CutScorecardFixture.day(F.rangeEnd, $0 - (count - 1)) }
        let wideName = String(repeating: "Ŵ", count: 2000) + "\n\"" + String(repeating: "w", count: 2000)
        var draft = F.Draft()
        draft.rangeStartDay = keys[0]
        draft.strainFactor = 1.0
        draft.days = keys.map {
            F.row($0, recovery: 100, strain: 100, sleep: 1439, deep: 1439, rem: 1439, light: 1439,
                  eff: 1.0, hrv: 300, rhr: 300, hrOnly: true)
        }
        draft.steps = keys.map { F.step($0, 99_999, .strapEstimate) }
        draft.workouts = keys.flatMap { key in
            (0..<20).map { slot in
                CoachPacketWorkout(day: key, startMinuteOfDay: 600 + slot * 30, sport: wideName,
                                   source: .activityFile, durationMinutes: 1439, avgHr: 300,
                                   energyKcal: 9999, distanceKm: 999.99)
            }
        }
        draft.body = [
            CoachPacketBodyReading(kind: .weight, value: 199.9, source: .appleHealth, day: keys[0]),
            CoachPacketBodyReading(kind: .waist, value: 199.9, source: .appleHealth, day: keys[0]),
        ]
        draft.hrvBaseline = CoachPacketBaseline(center: 299.6, typical: 199.5...299.4,
                                                status: "provisional", nights: 9999)
        draft.restingHrBaseline = CoachPacketBaseline(center: 299.6, typical: 199.5...299.4,
                                                      status: "provisional", nights: 9999)
        let weeks = (0..<200).map { index -> CutScorecardWeek in
            let monday = CutScorecardFixture.day("2027-06-07", index * 7)
            return CutScorecardWeek(weekStart: monday, weightKg: 199.9,
                                    weightDay: CutScorecardFixture.day(monday, 6), waistCm: 199.9,
                                    waistDay: CutScorecardFixture.day(monday, 6), inPhase: true,
                                    weeklyLossKg: -19.9)
        }
        let rules = CutScorecardRule.allCases.map {
            CutScorecardRuleEvaluation(rule: $0, state: .unknown, unknownReason: .fewerWeeksThanWindow,
                                       consecutiveWeeks: 99, requiredWeeks: 99)
        }
        let result = F.result(
            weeks: weeks,
            rate: CutScorecardRate(lossKgPerWeek: -19.99, percentPerWeek: -19.99, referenceWeightKg: 199.9,
                                   pointsUsed: 99, spanWeeks: 99, firstWeekStart: "2031-02-03",
                                   lastWeekStart: "2031-03-03"),
            projection: CutScorecardProjection(status: .projected, targetDay: "2033-03-16",
                                               weeksRemaining: 104.0, remainingKg: 199.9),
            waist: CutScorecardWaistSignal(state: .unknown, reason: .noWaistThisWeek, currentCm: 199.9,
                                           referenceCm: 199.9, referenceWeekStart: "2031-02-17",
                                           changeCm: -199.9),
            lifts: CutScorecardLiftSignal(state: .unknown, reason: .noSessionsPriorWeek,
                                          commonExercises: 99, dropped: 99, climbed: 99, held: 99,
                                          windowStartDay: "2031-02-26", windowEndDay: "2031-03-04"),
            protein: CutScorecardProteinSignal(state: .unknown, reason: .incompleteLogging,
                                               daysLogged: 7, daysAtOrAboveFloor: 7, requiredDays: 7,
                                               floorGrams: 999),
            rateBand: CutScorecardRateBandSignal(state: .unknown, reason: .weighInOverdue,
                                                 percentPerWeek: -19.99, lowPercentPerWeek: 10.0,
                                                 highPercentPerWeek: 10.0),
            rules: rules,
            verdict: CutScorecardVerdict(kind: .insufficientData, reason: .recompositionCheckIncomplete,
                                         rule: .liftsHoldingWaistShrinking, calorieChangeKcal: -9999,
                                         overriddenRules: CutScorecardRule.allCases,
                                         unevaluatedRules: CutScorecardRule.allCases),
            rejections: CutScorecardRejections(nonFinite: 9999, nonPositive: 9999, invalidDay: 9999,
                                               future: 9999))
        draft.scorecard = .evaluated(
            phase: CoachPacketPhase(name: wideName, startDay: "2031-01-06", targetWeightKg: 199.9,
                                    rateLowPercentPerWeek: 10.0, rateHighPercentPerWeek: 10.0),
            result: result)
        return draft
    }

    func testWidestPossibleInputIsWithinTheBudgetForEachRange() {
        for count in [7, 14, 28] {
            let draft = widest(days: count)
            let text = draft.text
            XCTAssertEqual(CoachPacket.dayKeys(from: draft.rangeStartDay, to: draft.rangeEndDay).count, count)
            XCTAssertLessThanOrEqual(text.utf8.count, CoachPacket.byteBudget(rangeDays: count),
                                     "\(count) days: \(text.utf8.count) bytes")
            // The bound holds because of the limits, not by truncating the text: every section is
            // whole, and the limits are the ones that did the work.
            XCTAssertEqual(headings(text), headings(G.g1), "\(count) days")
            XCTAssertEqual(rows("== WEIGH-INS ==", in: text).count, 8, "\(count) days")
            XCTAssertEqual(workoutRows(text).count, 20, "\(count) days")
            XCTAssertEqual(F.lines(startingWith: "  (", in: text),
                           ["  (\(count * 20 - 20) earlier workouts in range not shown)"], "\(count) days")
            XCTAssertEqual(dayRowKeys("== RECOVERY AND SLEEP ==", in: text).count, count)
            XCTAssertEqual(dayRowKeys("== ACTIVITY ==", in: text).count, count)
            // It really is wider than the fixture, line for line, in the per-day sections.
            XCTAssertTrue(text.contains(" [sleep staged from heart rate only]"))
            XCTAssertTrue(text.contains(": ~99999 strap-estimate (today so far)"))
        }
        XCTAssertGreaterThan(widest(days: 14).text.utf8.count, F.full.text.utf8.count)
    }

    // MARK: - Generated inputs

    private func generatedDraft(_ g: inout F.Generator) -> F.Draft {
        let count = g.pick([7, 14, 28])
        let keys = (0..<count).map { CutScorecardFixture.day(F.rangeEnd, $0 - (count - 1)) }
        let names = ["strength", "trail\nrun", "\"quoted\"", "", "😀 ride", String(repeating: "x", count: 90),
                     "row\tergometer", "walk  slow"]
        func maybe(_ g: inout F.Generator, _ range: ClosedRange<Double>) -> Double? {
            g.chance(25) ? nil : g.double(range)
        }
        var draft = F.Draft()
        draft.rangeStartDay = keys[0]
        draft.strainFactor = g.pick([1.0, 0.21])
        draft.sections = Set(CoachPacketSection.allCases.filter { _ in g.chance(70) })
        draft.days = keys.filter { _ in g.chance(80) }.map { key in
            F.row(key, recovery: maybe(&g, 0...100), strain: maybe(&g, 0...100), sleep: maybe(&g, 0...900),
                  deep: maybe(&g, 0...300), rem: maybe(&g, 0...300), light: maybe(&g, 0...600),
                  eff: maybe(&g, 0...1), hrv: maybe(&g, 10...200), rhr: g.chance(25) ? nil : g.int(35...110),
                  hrOnly: g.chance(15) ? true : nil)
        }
        draft.steps = keys.filter { _ in g.chance(75) }.map { key in
            F.step(key, g.double(0...40_000), g.pick([.strap, .appleHealth, .strapEstimate]))
        }
        draft.workouts = (0..<g.int(0...30)).map { index in
            CoachPacketWorkout(day: g.pick(keys), startMinuteOfDay: index * 40 + g.int(0...39),
                               sport: g.pick(names),
                               source: g.pick([.whoop, .appleHealth, .detected, .manual, .liftLog,
                                               .activityFile]),
                               durationMinutes: maybe(&g, 0...600), avgHr: g.chance(25) ? nil : g.int(40...200),
                               energyKcal: maybe(&g, 0...3000), distanceKm: maybe(&g, 0...200))
        }
        if g.chance(30) { draft.scorecard = .switchedOff }
        if g.chance(30) { draft.body = [] }
        if g.chance(30) { draft.hrvBaseline = nil }
        if g.chance(30) {
            draft.restingHrBaseline = CoachPacketBaseline(center: 54.1, typical: nil, status: "calibrating",
                                                          nights: g.int(0...6))
        }
        return draft
    }

    func testGeneratedInputsKeepTheGrammarTheBudgetAndTheirBytes() {
        var g = F.Generator(seed: 0xC0AC_4BAC_0002)
        for round in 0..<200 {
            let draft = generatedDraft(&g)
            let text = draft.text
            let lines = F.lines(text)
            let count = CoachPacket.dayKeys(from: draft.rangeStartDay, to: draft.rangeEndDay).count
            XCTAssertEqual(text, CoachPacket.render(draft.input), "round \(round)")
            XCTAssertLessThanOrEqual(text.utf8.count, CoachPacket.byteBudget(rangeDays: count), "round \(round)")
            XCTAssertEqual(lines.first, "NOOP-COACH-PACKET v2", "round \(round)")
            XCTAssertEqual(lines.last, "end of NOOP-COACH-PACKET v2", "round \(round)")
            XCTAssertTrue(text.hasSuffix("\n") && !text.hasSuffix("\n\n"), "round \(round)")
            XCTAssertFalse(text.contains("\t") || text.contains("\r") || text.contains("\n\n\n"),
                           "round \(round)")
            XCTAssertFalse(lines.contains { $0.hasSuffix(" ") }, "round \(round)")
            XCTAssertFalse(text.contains("nan") || text.contains("inf "), "round \(round)")
            let expected = G.sectionOrder.enumerated()
                .filter { draft.sections.contains(CoachPacketSection.allCases[$0.offset]) }
                .map(\.element.heading)
            XCTAssertEqual(headings(text), expected + ["== NOTES =="], "round \(round)")
            if draft.sections.contains(.recoverySleep) {
                XCTAssertEqual(dayRowKeys("== RECOVERY AND SLEEP ==", in: text).count, count, "round \(round)")
            }
            if draft.sections.contains(.activity) {
                XCTAssertEqual(dayRowKeys("== ACTIVITY ==", in: text).count, count, "round \(round)")
                XCTAssertLessThanOrEqual(workoutRows(text).count, 20, "round \(round)")
                let stamps = workoutRows(text).map { String($0.dropFirst(2).prefix(16)) }
                XCTAssertEqual(stamps, stamps.sorted(), "round \(round)")
            }
            // Handing the same items over in another order changes nothing.
            var shuffled = draft
            shuffled.days = g.shuffled(draft.days)
            shuffled.steps = g.shuffled(draft.steps)
            shuffled.workouts = g.shuffled(draft.workouts)
            shuffled.body = g.shuffled(draft.body)
            XCTAssertEqual(shuffled.text, text, "round \(round)")
        }
    }
}
