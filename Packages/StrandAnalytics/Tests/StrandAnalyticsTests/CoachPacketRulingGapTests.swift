import XCTest
import WhoopStore
@testable import StrandAnalytics

// Tests that pin the five points of ruling A17 (docs/personal/superapp/specs/RULINGS-ADDENDUM.md) on
// the packet renderer of stage 2 (docs/personal/superapp/specs/stage-2.md §6.2, §7.2, §7.4, §7.11).
// The ruling settles the fault-injection items 3, 4, 6, 8 and 9 of the stage 2 report. Each expected
// value is derived from the ruling and the specification sentence it names, never from what the
// renderer prints today.
//
// No new API is assumed: only `CoachPacket.sanitize`, `CoachPacket.privacyViolations` and
// `CoachPacket.render`, through the fixture of `CoachPacketFixture.swift`.
//
// Every value is synthetic and belongs to the Fixture Person of §13.

/// Ruling A17: one named test for each ruled point of the stage 2 packet.
final class CoachPacketRulingGapTests: XCTestCase {

    private typealias F = CoachPacketFixture

    // MARK: - Helpers

    /// The one line of `text` that begins with `prefix`; fails when there is none or more than one.
    private func only(_ prefix: String, in text: String, file: StaticString = #filePath,
                      line: UInt = #line) -> String {
        let found = F.lines(startingWith: prefix, in: text)
        XCTAssertEqual(found.count, 1, "lines starting \"\(prefix)\"", file: file, line: line)
        return found.first ?? ""
    }

    private func weight(_ value: Double, _ source: CoachPacketBodySource,
                        _ day: String?) -> CoachPacketBodyReading {
        CoachPacketBodyReading(kind: .weight, value: value, source: source, day: day)
    }

    private func waist(_ value: Double, _ source: CoachPacketBodySource,
                       _ day: String?) -> CoachPacketBodyReading {
        CoachPacketBodyReading(kind: .waist, value: value, source: source, day: day)
    }

    /// The fixture with an invalid range and the given sections switched on.
    private func invalidRange(_ start: String, _ end: String,
                              sections: Set<CoachPacketSection>) -> String {
        F.full {
            $0.rangeStartDay = start
            $0.rangeEndDay = end
            $0.sections = sections
        }.text
    }

    private let invalidRanges: [(String, String)] = [
        ("2031-3-3", "2031-03-16"), ("2031-03-03", "garbage"), ("2031-03-16", "2031-03-15"),
        ("", ""), ("2031-02-30", "2031-03-16"),
    ]

    /// Day strings that are not canonical keys (stage 1 ruling R5: exactly `YYYY-MM-DD` of a real day).
    private let nonCanonicalDays = ["garbage", "2031-3-5", "2031-02-30", "", " 2031-03-05",
                                    "2031-03-05 ", "2031/03/05", "2031-03-05\n== FORGED =="]

    // MARK: - A17, point 1 (fault 3): free text is trimmed again after the 48-byte cut

    /// A17: "Free text is trimmed again after the 48-byte cut, so it never ends in a space." The cut
    /// of 47 letters, a space and a letter falls after the space; the space then goes too.
    func testFreeTextIsTrimmedAgainAfterTheFortyEightByteCut() {
        let a47 = String(repeating: "a", count: 47)
        XCTAssertEqual(CoachPacket.sanitize(a47 + " b"), a47)
        XCTAssertEqual(CoachPacket.sanitize(a47 + " bbbbbbbbbbbb"), a47)
        // Collapsing comes first, so a run of white space at the cut is the same one space.
        XCTAssertEqual(CoachPacket.sanitize(a47 + "   b"), a47)
        XCTAssertEqual(CoachPacket.sanitize(a47 + "\n\tb"), a47)
        // A character that does not fit after the space: 46 + 1 + 2 bytes is 49, the two-byte letter
        // is dropped whole, and the space it leaves at the end is trimmed.
        let a46 = String(repeating: "a", count: 46)
        XCTAssertEqual(CoachPacket.sanitize(a46 + " \u{E9}"), a46)
        // One byte earlier nothing is cut and the inner space stays.
        XCTAssertEqual(CoachPacket.sanitize(a46 + " b"), a46 + " b")
        XCTAssertEqual(CoachPacket.sanitize(String(repeating: "a", count: 45) + " \u{E9}"),
                       String(repeating: "a", count: 45) + " \u{E9}")
    }

    /// The same sentence over every position of the space: the result is the first 48 bytes of the
    /// cleaned text without a final space, whatever the position.
    func testFreeTextNeverEndsInASpaceWhereverTheCutFalls() {
        for count in 1...60 {
            let cleaned = String(repeating: "a", count: count) + " " + String(repeating: "b", count: 20)
            var expected = String(cleaned.prefix(48))
            if expected.hasSuffix(" ") { expected.removeLast() }
            let got = CoachPacket.sanitize(cleaned)
            XCTAssertEqual(got, expected, "\(count) letters before the space")
            XCTAssertFalse(got.hasSuffix(" "), "\(count) letters before the space")
            XCTAssertLessThanOrEqual(got.utf8.count, 48)
        }
    }

    /// The same point seen in the packet: a phase name cut at its space closes its quotes straight
    /// after the last letter.
    func testACutPhaseNameInThePacketDoesNotEndInASpace() {
        let a47 = String(repeating: "a", count: 47)
        let phase = CoachPacketPhase(name: a47 + " b", startDay: "2031-01-06", targetWeightKg: 94.0,
                                     rateLowPercentPerWeek: 0.40, rateHighPercentPerWeek: 1.20)
        let text = F.full { $0.setResult(F.result(), phase: phase) }.text
        XCTAssertEqual(only("phase: ", in: text),
                       "phase: \"\(a47)\" (cut), started 2031-01-06, target 94.0 kg, "
                           + "band 0.40 to 1.20 %/week")
    }

    // MARK: - A17, point 2 (fault 4): a hardware address with mixed separators

    /// A17: "six hexadecimal pairs separated by colons or dashes in any mixture" are a hardware
    /// address, and the scan fails closed. Each of these is six pairs with both separators.
    func testSixHexadecimalPairsWithMixedSeparatorsAreAFinding() {
        let mixed = [
            "07:42:10-08:00-11", "AA:BB-CC:DD-EE:FF", "aa-bb:cc-dd:ee-ff", "AA-BB-CC-DD-EE:FF",
            "AA:BB:CC:DD:EE-FF", "00-11:22:33:44:55", "aB:Cd-Ef:01-23:45",
        ]
        for item in mixed {
            XCTAssertFalse(CoachPacket.privacyViolations(in: item, identifiers: []).isEmpty,
                           "alone: \(item)")
            XCTAssertFalse(CoachPacket.privacyViolations(in: "strap (\(item)) seen",
                                                         identifiers: []).isEmpty,
                           "in a sentence: \(item)")
            // In a packet, through the one free-text field wide enough to carry it.
            let phase = CoachPacketPhase(name: item, startDay: "2031-01-06", targetWeightKg: 94.0,
                                         rateLowPercentPerWeek: 0.40, rateHighPercentPerWeek: 1.20)
            let text = F.full { $0.setResult(F.result(), phase: phase) }.text
            XCTAssertTrue(text.contains(item), "the fixture did not carry \(item)")
            XCTAssertFalse(CoachPacket.privacyViolations(in: text, identifiers: []).isEmpty,
                           "in a packet: \(item)")
        }
    }

    /// The other side of the same sentence: "six" pairs. A time with a negative offset is five pairs
    /// with both separators, so the ruling does not turn the packet's own `generated:` line into a
    /// finding.
    func testFivePairsWithMixedSeparatorsAreNotAFinding() {
        for item in ["07:42:10-08:00", "AA:BB-CC:DD-EE", "2031-03-16T07:42:10-08:00"] {
            XCTAssertEqual(CoachPacket.privacyViolations(in: item, identifiers: []), [], item)
        }
        let text = F.full { $0.generatedAt = "2031-03-16T07:42:10-08:00" }.text
        XCTAssertEqual(only("generated: ", in: text), "generated: 2031-03-16T07:42:10-08:00")
        XCTAssertEqual(CoachPacket.privacyViolations(in: text, identifiers: F.identifiers), [])
    }

    // MARK: - A17, point 3 (fault 6): the header of an invalid range

    /// A17: "For an invalid range the header reads `sections: none`", whatever the owner switched on.
    func testAnInvalidRangeHeaderReadsSectionsNone() {
        let choices: [Set<CoachPacketSection>] = [
            F.allSections, [.scorecard], [.activity, .weighIns, .trends], [],
        ]
        for (start, end) in invalidRanges {
            for sections in choices {
                let text = invalidRange(start, end, sections: sections)
                XCTAssertEqual(F.line(2, of: text), "range: invalid", "\(start)..\(end)")
                XCTAssertEqual(F.line(3, of: text), "sections: none",
                               "\(start)..\(end) with \(sections.count) on")
                XCTAssertEqual(F.lines(startingWith: "sections: ", in: text).count, 1)
            }
        }
    }

    /// A17: for an invalid range "the switched-off line reports the owner's switches as usual": the
    /// version-1 sections the owner switched off, in the fixed order of §7.2, or `none`. It is not
    /// all five because nothing was rendered.
    func testAnInvalidRangeSwitchedOffLineReportsTheOwnersSwitches() {
        let cases: [(Set<CoachPacketSection>, String)] = [
            (F.allSections, "switched-off: none"),
            ([.activity, .weighIns, .trends], "switched-off: scorecard, recovery-sleep"),
            ([.scorecard, .weighIns, .recoverySleep, .trends], "switched-off: activity"),
            ([.recoverySleep], "switched-off: scorecard, weigh-ins, trends, activity"),
            ([], "switched-off: scorecard, weigh-ins, recovery-sleep, trends, activity"),
        ]
        for (start, end) in invalidRanges {
            for (sections, expected) in cases {
                let text = invalidRange(start, end, sections: sections)
                XCTAssertEqual(F.line(4, of: text), expected, "\(start)..\(end)")
                XCTAssertEqual(F.lines(startingWith: "switched-off: ", in: text).count, 1)
                // "As usual": the same line a valid range prints for the same switches.
                let valid = F.full { $0.sections = sections }.text
                XCTAssertEqual(F.line(4, of: text), F.line(4, of: valid), "\(start)..\(end)")
            }
        }
    }

    // MARK: - A17, point 4 (fault 8): two body readings of one kind on one day

    /// A17: "When two body readings of one kind fall on one day the later in the input wins, as for
    /// days and steps." The value and the source are those of the later reading.
    func testTheLaterOfTwoBodyReadingsOfOneKindOnOneDayWins() {
        let first = F.full {
            $0.body = [weight(98.4, .labBook, "2031-03-05"), weight(97.1, .appleHealth, "2031-03-05"),
                       waist(99.0, .appleHealth, "2031-03-05"), waist(97.0, .labBook, "2031-03-05")]
        }.text
        XCTAssertEqual(only("current weight: ", in: first),
                       "current weight: 97.1 kg (apple-health, 2031-03-05)")
        XCTAssertEqual(only("current waist: ", in: first),
                       "current waist: 97.0 cm (lab-book, 2031-03-05)")

        // The same four readings with each pair turned round: the other one of each pair wins.
        let second = F.full {
            $0.body = [weight(97.1, .appleHealth, "2031-03-05"), weight(98.4, .labBook, "2031-03-05"),
                       waist(97.0, .labBook, "2031-03-05"), waist(99.0, .appleHealth, "2031-03-05")]
        }.text
        XCTAssertEqual(only("current weight: ", in: second),
                       "current weight: 98.4 kg (lab-book, 2031-03-05)")
        XCTAssertEqual(only("current waist: ", in: second),
                       "current waist: 99.0 cm (apple-health, 2031-03-05)")

        // Three on one day, and the other kind between them, change nothing: still the last.
        let third = F.full {
            $0.body = [weight(99.9, .labBook, "2031-03-05"), waist(97.0, .labBook, "2031-03-05"),
                       weight(98.4, .labBook, "2031-03-05"), weight(97.1, .labBook, "2031-03-05")]
        }.text
        XCTAssertEqual(only("current weight: ", in: third),
                       "current weight: 97.1 kg (lab-book, 2031-03-05)")
        XCTAssertEqual(only("current waist: ", in: third),
                       "current waist: 97.0 cm (lab-book, 2031-03-05)")
    }

    // MARK: - A17, point 5 (fault 9): a body reading whose day is not a canonical key

    /// A17: "A body reading whose day is not a canonical key is ignored and never printed." Neither
    /// its value nor its day text reaches the packet, and the other kind is untouched.
    func testABodyReadingWhoseDayIsNotACanonicalKeyIsIgnoredAndNeverPrinted() {
        for day in nonCanonicalDays {
            let text = F.full {
                $0.scorecard = .switchedOff
                $0.body = [weight(123.4, .labBook, day), waist(97.0, .labBook, "2031-03-05")]
            }.text
            XCTAssertEqual(only("current weight: ", in: text), "current weight: \u{2014}", "\"\(day)\"")
            XCTAssertEqual(only("current waist: ", in: text),
                           "current waist: 97.0 cm (lab-book, 2031-03-05)", "\"\(day)\"")
            XCTAssertFalse(text.contains("123.4"), "the value was printed for \"\(day)\"")
            XCTAssertFalse(text.contains("garbage"))
            XCTAssertFalse(text.contains("2031/03/05"))
            XCTAssertFalse(text.contains("FORGED"))
            XCTAssertEqual(F.lines(text).count,
                           F.lines(F.full { $0.scorecard = .switchedOff }.text).count, "\"\(day)\"")
        }
        // The waist kind is ignored by the same sentence.
        for day in nonCanonicalDays {
            let text = F.full {
                $0.scorecard = .switchedOff
                $0.body = [weight(97.1, .labBook, "2031-03-05"), waist(123.4, .appleHealth, day)]
            }.text
            XCTAssertEqual(only("current waist: ", in: text), "current waist: \u{2014}", "\"\(day)\"")
            XCTAssertEqual(only("current weight: ", in: text),
                           "current weight: 97.1 kg (lab-book, 2031-03-05)", "\"\(day)\"")
            XCTAssertFalse(text.contains("123.4"), "the value was printed for \"\(day)\"")
        }
    }

    /// "Ignored" means the reading takes no part: one with a non-canonical day, later in the input,
    /// does not displace a reading of the same kind that has a canonical day (points 4 and 5 of A17
    /// together: the later of the readings that are not ignored).
    func testAnIgnoredBodyReadingDoesNotDisplaceOneWithACanonicalDay() {
        for day in nonCanonicalDays {
            let after = F.full {
                $0.body = [weight(97.1, .labBook, "2031-03-05"), weight(123.4, .appleHealth, day),
                           waist(97.0, .labBook, "2031-03-05"), waist(123.4, .appleHealth, day)]
            }.text
            XCTAssertEqual(only("current weight: ", in: after),
                           "current weight: 97.1 kg (lab-book, 2031-03-05)", "\"\(day)\" after")
            XCTAssertEqual(only("current waist: ", in: after),
                           "current waist: 97.0 cm (lab-book, 2031-03-05)", "\"\(day)\" after")
            let before = F.full {
                $0.body = [weight(123.4, .appleHealth, day), weight(97.1, .labBook, "2031-03-05"),
                           waist(123.4, .appleHealth, day), waist(97.0, .labBook, "2031-03-05")]
            }.text
            XCTAssertEqual(only("current weight: ", in: before),
                           "current weight: 97.1 kg (lab-book, 2031-03-05)", "\"\(day)\" before")
            XCTAssertEqual(only("current waist: ", in: before),
                           "current waist: 97.0 cm (lab-book, 2031-03-05)", "\"\(day)\" before")
        }
    }
}
