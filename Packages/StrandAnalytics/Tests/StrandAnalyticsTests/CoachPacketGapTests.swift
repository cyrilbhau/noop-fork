import XCTest
import WhoopStore
@testable import StrandAnalytics

// Tests that close gaps found by fault injection in the packet renderer of stage 2
// (docs/personal/superapp/specs/stage-2.md §6.2, §7 and §7.11). Each expected value is derived from
// the specification and names the sentence it rests on. Where the specification decides only part of
// a case (that something must not print, and not what prints in its place) the test asserts that part
// and no more.
//
// Every value is synthetic and belongs to the Fixture Person of §13.

/// Gap tests for `CoachPacket`: one test for each fault that no earlier test caught and that the
/// specification decides.
final class CoachPacketGapTests: XCTestCase {

    private typealias F = CoachPacketFixture

    // MARK: - Helpers

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

    /// The fixture with its scorecard result replaced.
    private func draft(result: CutScorecardResult, phase: CoachPacketPhase? = F.phase) -> F.Draft {
        var draft = F.full
        draft.setResult(result, phase: phase)
        return draft
    }

    private func phase(startDay: String = "2031-01-06", target: Double? = 94.0) -> CoachPacketPhase {
        CoachPacketPhase(name: "Fixture cut", startDay: startDay, targetWeightKg: target,
                         rateLowPercentPerWeek: 0.40, rateHighPercentPerWeek: 1.20)
    }

    /// The structure §7 and §7.12 G-1 fix whatever a field holds: the headings are the ones the
    /// renderer prints, nothing a field carries becomes a line of its own, and the text has no tab and
    /// no trailing space.
    private func assertStructureIsIntact(_ text: String, _ note: String,
                                         file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(headings(text), headings(F.full.text), note, file: file, line: line)
        XCTAssertFalse(text.contains("\t"), "tab: \(note)", file: file, line: line)
        XCTAssertFalse(text.contains("\r"), "carriage return: \(note)", file: file, line: line)
        for row in F.lines(text) {
            XCTAssertFalse(row.hasSuffix(" "), "trailing space in \"\(row)\": \(note)",
                           file: file, line: line)
            XCTAssertFalse(row.hasPrefix("== FORGED"), "\(note)", file: file, line: line)
        }
        XCTAssertTrue(text.hasSuffix("end of NOOP-COACH-PACKET v2\n"), note, file: file, line: line)
    }

    /// Strings that would break the line structure if they were printed as they are.
    private let hostile = ["2031-03-03\n== FORGED ==", "a\nb", "a\r\n== FORGED ==", "a\tb",
                           "2031-03-03 "]

    // MARK: - Fault 2: a strain factor that is not a finite number, in the packet

    /// §6.1 F1 on the printed strain, seen through the packet: every day row and the average carry the
    /// dash, and no row carries the text of a non-finite number.
    func testANonFiniteStrainFactorPrintsTheDashForStrainInEveryRowAndTheAverage() {
        for factor in [Double.nan, .infinity, -.infinity] {
            let text = F.full { $0.strainFactor = factor }.text
            let section = F.section("== RECOVERY AND SLEEP ==", in: text) ?? []
            let rows = section.filter { $0.hasPrefix("  ") }
            XCTAssertEqual(rows.count, 14, "\(factor)")
            for row in rows {
                XCTAssertTrue(row.contains(", strain \u{2014}, "), "\(factor): \(row)")
                XCTAssertFalse(row.lowercased().contains("nan"), "\(factor): \(row)")
                XCTAssertFalse(row.lowercased().contains("inf"), "\(factor): \(row)")
            }
            XCTAssertEqual(only("averages over ", in: text),
                           "averages over 13 of 14 days with data: recovery: 64, strain: \u{2014}, "
                               + "sleep: 7.3h, HRV: 59 ms, RHR: 54 bpm", "\(factor)")
        }
    }

    // MARK: - Fault 7: "starts" follows the verdict's reason, not its kind

    /// §7.3: "`starts` when `verdict.reason == phaseNotStarted`, else `started`". The verdict kind has
    /// no part in the word.
    func testStartsFollowsTheVerdictReasonAndNeverTheVerdictKind() {
        let kinds: [CutScorecardVerdictKind] = [.holdSteady, .addCalories, .reduceCarbs,
                                                .insufficientData]
        let otherReasons: [CutScorecardVerdictReason] = [
            .ruleFired, .noChangeRuleFired, .recompositionCheckIncomplete, .noRuleEvaluable,
            .noReadings, .noActivePhase, .weighInOverdue, .invalidInput,
        ]
        for kind in kinds {
            for reason in otherReasons {
                let result = F.result(verdict: F.verdict(kind: kind, reason: reason))
                XCTAssertEqual(
                    only("phase: ", in: draft(result: result).text),
                    "phase: \"Fixture cut\" (cut), started 2031-01-06, target 94.0 kg, "
                        + "band 0.40 to 1.20 %/week", "\(kind) \(reason)")
            }
            let notStarted = F.result(verdict: F.verdict(kind: kind, reason: .phaseNotStarted))
            XCTAssertEqual(
                only("phase: ", in: draft(result: notStarted).text),
                "phase: \"Fixture cut\" (cut), starts 2031-01-06, target 94.0 kg, "
                    + "band 0.40 to 1.20 %/week", "\(kind)")
        }
    }

    // MARK: - Fault 9: a body reading whose day is not a canonical key

    /// §6.2: "a row, step day, workout or body reading whose day is … invalid is ignored". Only the
    /// range filter is lifted for body readings, so an invalid day leaves the value absent and the day
    /// text never reaches the packet.
    func testABodyReadingWithANonCanonicalDayIsIgnored() {
        for day in ["garbage", "2031-3-5", "2031-02-30", "", " 2031-03-05", "2031-03-05\n== FORGED =="] {
            let text = F.full {
                $0.body = [CoachPacketBodyReading(kind: .weight, value: 97.1, source: .labBook, day: day),
                           CoachPacketBodyReading(kind: .waist, value: 97.0, source: .labBook,
                                                  day: "2031-03-05")]
            }.text
            XCTAssertEqual(only("current weight: ", in: text), "current weight: \u{2014}", "\"\(day)\"")
            XCTAssertEqual(only("current waist: ", in: text),
                           "current waist: 97.0 cm (lab-book, 2031-03-05)", "\"\(day)\"")
            XCTAssertFalse(text.contains("garbage"))
            assertStructureIsIntact(text, "body day \"\(day)\"")
        }
    }

    /// The other half of the same sentence: a body reading is a current value and is never filtered by
    /// the range, and the undated profile value has no day to check.
    func testABodyReadingWithACanonicalDayOutsideTheRangeIsKept() {
        let text = F.full {
            $0.body = [CoachPacketBodyReading(kind: .weight, value: 97.1, source: .appleHealth,
                                              day: "2029-12-31"),
                       CoachPacketBodyReading(kind: .waist, value: 97.0, source: .profile, day: nil)]
        }.text
        XCTAssertEqual(only("current weight: ", in: text),
                       "current weight: 97.1 kg (apple-health, 2029-12-31)")
        XCTAssertEqual(only("current waist: ", in: text), "current waist: 97.0 cm (profile)")
    }

    // MARK: - Fault 10: the heart-rate-only suffix

    /// §7.5: "the suffix appears when the row's `sleepHrOnly` is true". False and nil print no suffix.
    func testTheHeartRateOnlySuffixIsPrintedOnlyWhenTheFlagIsTrue() {
        let plain = "  2031-03-11: recovery 58, strain 8.6, sleep 7.0h, deep \u{2014}, REM \u{2014}, "
            + "light \u{2014}, eff \u{2014}, HRV 55ms, RHR 55bpm"
        let cases: [(Bool?, String)] = [
            (false, plain), (nil, plain), (true, plain + " [sleep staged from heart rate only]"),
        ]
        for (flag, expected) in cases {
            let text = F.full {
                $0.days = F.days.map { row in
                    row.day == "2031-03-11"
                        ? F.row("2031-03-11", recovery: 58, strain: 41, sleep: 420, hrv: 55, rhr: 55,
                                hrOnly: flag)
                        : row
                }
            }.text
            XCTAssertEqual(only("  2031-03-11: recovery", in: text), expected, "\(String(describing: flag))")
            XCTAssertEqual(text.contains("[sleep staged from heart rate only]"), flag == true,
                           "\(String(describing: flag))")
        }
    }

    // MARK: - Fault 11: a waist in the waist signal that is not a positive number

    /// §6.2: "any non-finite or non-positive weight, waist or baseline centre makes that item absent".
    /// In the waist signal an absent value is a clause that is not printed (§7.3: "when set").
    func testANonPositiveWaistInTheWaistSignalPrintsNoClause() {
        for bad in [-5.0, 0.0, -0.0] {
            let noCurrent = CutScorecardWaistSignal(state: .notMet, reason: .notShrinking,
                                                    currentCm: bad, referenceCm: 97.0,
                                                    referenceWeekStart: "2031-02-17", changeCm: nil)
            XCTAssertEqual(only("signal waist: ", in: draft(result: F.result(waist: noCurrent)).text),
                           "signal waist: notMet (notShrinking); reference 97.0 cm in week 2031-02-17",
                           "current \(bad)")
            let noReference = CutScorecardWaistSignal(state: .notMet, reason: .notShrinking,
                                                      currentCm: 97.0, referenceCm: bad,
                                                      referenceWeekStart: "2031-02-17", changeCm: nil)
            XCTAssertEqual(only("signal waist: ", in: draft(result: F.result(waist: noReference)).text),
                           "signal waist: notMet (notShrinking); now 97.0 cm", "reference \(bad)")
        }
    }

    // MARK: - Fault 12: a phase target that is not a positive number

    /// §6.2 makes a non-positive weight absent, so the target is never printed as a number. Whether an
    /// absent target reads `no target` or carries the dash is not decided by the specification; both
    /// are accepted here.
    func testANonPositivePhaseTargetIsNeverPrintedAsANumber() {
        for bad in [0.0, -0.0, -1.0, -94.0] {
            let line = only("phase: ", in: draft(result: F.result(), phase: phase(target: bad)).text)
            XCTAssertTrue(line.hasPrefix("phase: \"Fixture cut\" (cut), started 2031-01-06, "), line)
            XCTAssertTrue(line.hasSuffix(", band 0.40 to 1.20 %/week"), line)
            let middle = line.dropFirst("phase: \"Fixture cut\" (cut), started 2031-01-06, ".count)
                .dropLast(", band 0.40 to 1.20 %/week".count)
            XCTAssertNil(middle.rangeOfCharacter(from: .decimalDigits),
                         "\(bad): the target clause \"\(middle)\" carries a number")
        }
    }

    // MARK: - Fault 13: `generatedAt` cannot add or break a line

    /// §7.2: the header is "exactly these eight lines". Whatever `generatedAt` holds, the second line
    /// is still the one `generated:` line, the third is the range line, and everything after the
    /// header is unchanged. §7: no tab and no trailing space anywhere.
    func testGeneratedAtCannotBreakTheHeaderOrForgeASection() {
        let full = F.lines(F.full.text)
        for value in hostile + ["x\n== NOTES ==", "", "   ", "\n", "x\u{0B}y"] {
            let text = F.full { $0.generatedAt = value }.text
            let lines = F.lines(text)
            XCTAssertEqual(lines.count, full.count, "\"\(value)\"")
            guard lines.count == full.count else { continue }
            XCTAssertEqual(lines[0], "NOOP-COACH-PACKET v2")
            XCTAssertTrue(lines[1].hasPrefix("generated:"), lines[1])
            XCTAssertEqual(Array(lines[2...]), Array(full[2...]), "\"\(value)\"")
            XCTAssertEqual(lines.filter { $0 == "== NOTES ==" }.count, 1, "\"\(value)\"")
            assertStructureIsIntact(text, "generatedAt \"\(value)\"")
        }
    }

    // MARK: - Fault 14: a day key carried by the scorecard cannot add or break a line

    /// §7.12 G-1: a heading is printed by the renderer and by nothing else. A day key the scorecard
    /// result carries is printed inside its own line or not at all.
    func testAScorecardDayKeyCannotBreakALineOrForgeASection() {
        let fullScorecard = F.section("== SCORECARD ==", in: F.full.text) ?? []
        for value in hostile {
            let week = CutScorecardWeek(weekStart: value, weightKg: 97.1, weightDay: value,
                                        waistCm: 97.0, waistDay: value, inPhase: true,
                                        weeklyLossKg: 0.1)
            let results: [(String, CutScorecardResult, CoachPacketPhase)] = [
                ("judgedWeekStart", F.result(judgedWeekStart: value), F.phase),
                ("phase.startDay", F.result(), phase(startDay: value)),
                ("rate week starts",
                 F.result(rate: CutScorecardRate(lossKgPerWeek: 0.100, percentPerWeek: 0.103,
                                                 referenceWeightKg: 97.3, pointsUsed: 5, spanWeeks: 4,
                                                 firstWeekStart: value, lastWeekStart: value)),
                 F.phase),
                ("projection.targetDay",
                 F.result(projection: CutScorecardProjection(status: .projected, targetDay: value,
                                                             weeksRemaining: 31.0, remainingKg: 3.1)),
                 F.phase),
                ("waist.referenceWeekStart",
                 F.result(waist: CutScorecardWaistSignal(state: .notMet, reason: .notShrinking,
                                                         currentCm: 97.0, referenceCm: 97.0,
                                                         referenceWeekStart: value, changeCm: 0.0)),
                 F.phase),
                ("lift window days",
                 F.result(lifts: CutScorecardLiftSignal(state: .met, reason: .holding,
                                                        commonExercises: 2, dropped: 0, climbed: 0,
                                                        held: 2, windowStartDay: value,
                                                        windowEndDay: value)),
                 F.phase),
                ("weekly point days", F.result(weeks: [week]), F.phase),
            ]
            for (name, result, phase) in results {
                let text = draft(result: result, phase: phase).text
                assertStructureIsIntact(text, "\(name) \"\(value)\"")
                // The scorecard section keeps its fixed lines: a key adds none.
                XCTAssertEqual((F.section("== SCORECARD ==", in: text) ?? []).count,
                               fullScorecard.count, "\(name) \"\(value)\"")
                XCTAssertEqual(F.lines(startingWith: "judged-week: ", in: text).count, 1,
                               "\(name) \"\(value)\"")
            }
        }
    }

    // MARK: - Fault 15: a baseline status cannot add or break a line

    /// §7.6: the trends section is its lead line, the HRV line and the RHR line. A status string is
    /// printed inside its own line, in the usable form and in the not-established form alike.
    func testABaselineStatusCannotBreakALineOrForgeASection() {
        for value in hostile {
            for typical in [50.8...63.6, nil] as [ClosedRange<Double>?] {
                let text = F.full {
                    $0.hrvBaseline = CoachPacketBaseline(center: 57.2, typical: typical, status: value,
                                                         nights: 21)
                    $0.restingHrBaseline = CoachPacketBaseline(center: 54.1, typical: typical,
                                                               status: value, nights: 21)
                }.text
                let section = F.section("== TRENDS ==", in: text) ?? []
                XCTAssertEqual(section.count, 3, "\"\(value)\"")
                XCTAssertEqual(section.filter { $0.hasPrefix("HRV: ") }.count, 1, "\"\(value)\"")
                XCTAssertEqual(section.filter { $0.hasPrefix("RHR: ") }.count, 1, "\"\(value)\"")
                assertStructureIsIntact(text, "baseline status \"\(value)\"")
            }
        }
    }

    // MARK: - Fault 16: the budget never traps

    /// §6: "every function is total: it never throws and never traps". The formula of §7.10 holds for
    /// every range whose budget fits a whole number; beyond that the call still returns. What it
    /// returns there is not decided by the specification and is not asserted.
    func testTheByteBudgetIsTotalAtTheEdgesOfTheWholeNumbers() {
        // Packet v2 (ruling A5): 8000 + 290 × days + the events allowance.
        let allowance = PersonalEvents.packetByteAllowance
        XCTAssertEqual(CoachPacket.byteBudget(rangeDays: 0), 8000 + allowance)
        XCTAssertEqual(CoachPacket.byteBudget(rangeDays: 7), 12_030)
        XCTAssertEqual(CoachPacket.byteBudget(rangeDays: 14), 14_060)
        XCTAssertEqual(CoachPacket.byteBudget(rangeDays: 28), 18_120)
        // The largest range whose budget is representable: the formula still holds exactly.
        let largest = (Int.max - 8000 - allowance) / 290
        XCTAssertEqual(CoachPacket.byteBudget(rangeDays: largest), 8000 + 290 * largest + allowance)
        // Past it the product overflows. Reaching the next line is the assertion.
        _ = CoachPacket.byteBudget(rangeDays: largest + 1)
        _ = CoachPacket.byteBudget(rangeDays: Int.max)
        _ = CoachPacket.byteBudget(rangeDays: Int.min)
    }

    // MARK: - Fault 18: a rate that is not a finite number

    /// A non-finite input is absent (§6.2 and the test the plan of §12.1 names for it), so the rate
    /// line never carries the text of a non-finite number. What the line reads in its place is not
    /// decided by the specification and is not asserted.
    func testANonFiniteRateNeverPrintsANonFiniteNumber() {
        for bad in [Double.infinity, -.infinity, .nan] {
            let rates: [(String, CutScorecardRate)] = [
                ("loss", CutScorecardRate(lossKgPerWeek: bad, percentPerWeek: 0.103,
                                          referenceWeightKg: 97.3, pointsUsed: 5, spanWeeks: 4,
                                          firstWeekStart: "2031-02-03", lastWeekStart: "2031-03-03")),
                ("percent", CutScorecardRate(lossKgPerWeek: 0.100, percentPerWeek: bad,
                                             referenceWeightKg: 97.3, pointsUsed: 5, spanWeeks: 4,
                                             firstWeekStart: "2031-02-03", lastWeekStart: "2031-03-03")),
                ("reference", CutScorecardRate(lossKgPerWeek: 0.100, percentPerWeek: 0.103,
                                               referenceWeightKg: bad, pointsUsed: 5, spanWeeks: 4,
                                               firstWeekStart: "2031-02-03", lastWeekStart: "2031-03-03")),
            ]
            for (name, rate) in rates {
                let line = only("rate: ", in: draft(result: F.result(rate: rate)).text).lowercased()
                XCTAssertFalse(line.contains("inf"), "\(name) \(bad): \(line)")
                XCTAssertFalse(line.contains("nan"), "\(name) \(bad): \(line)")
            }
        }
    }

    // MARK: - Fault 5: the email pattern

    /// §7.11 gives the pattern `\S+@\S+\.\S+`: at least one character before the `@`, at least one
    /// between the `@` and a dot, and at least one after that dot.
    func testAnEmailNeedsACharacterOnEachSideOfTheAtSignAndOfTheDot() {
        let notEmails = ["a@.cc", "a@b.", "@b.c", "a@.", "@.", "a@ b.c", "a@bc", "the dose is 5 @ 0.5"]
        for text in notEmails {
            XCTAssertEqual(CoachPacket.privacyViolations(in: text, identifiers: []), [], text)
            XCTAssertEqual(CoachPacket.privacyViolations(in: "x " + text + " y", identifiers: []), [],
                           text)
        }
        // The smallest strings the pattern does match are findings.
        for text in ["a@b.c", "a@..c", "a@b..", "a@.b.c"] {
            XCTAssertFalse(CoachPacket.privacyViolations(in: text, identifiers: []).isEmpty, text)
        }
    }

    // MARK: - Ruling A9: the two CanonicalDay names the packet calls

    /// Ruling A9: `CanonicalDay.number(_:)` and `CanonicalDay.key(_:)` are forwarders to
    /// `dayNumber(_:)` and `key(dayNumber:)`, and carry no rule of their own.
    func testTheCanonicalDayNamesThePacketCallsForwardToTheOneHelper() {
        let keys = ["2031-03-03", "2031-03-16", "2028-02-29", "2031-02-29", "2031-3-3", "garbage", "",
                    " 2031-03-03", "0001-01-01", "9999-12-31", "2031-12-31", "2032-01-01"]
        for key in keys {
            XCTAssertEqual(CanonicalDay.number(key), CanonicalDay.dayNumber(key), "\"\(key)\"")
            guard let number = CanonicalDay.dayNumber(key) else { continue }
            XCTAssertEqual(CanonicalDay.key(number), CanonicalDay.key(dayNumber: number), "\"\(key)\"")
            XCTAssertEqual(CanonicalDay.key(number), key)
        }
    }
}
