// API ASSUMED BY THESE TESTS
//
// Written from docs/personal/superapp/specs/stage-5.md §6, §7.5, §12.1 ("Packet rows"), §12.6 and
// §13.3, and stage-2.md §6.2 and §7.12, before any implementation exists. This file belongs to work
// package 5-9: it compiles only once stage 2's `CoachPacket` and this stage's
// `PersonalEventsPacket.swift` both exist.
//
//   // PersonalEventsPacket.swift
//   extension PersonalEvents {
//       public static let packetRowLimit: Int        // 12
//       public static let packetByteAllowance: Int   // 2000
//       public static func packetLines(events: [PersonalEvent], firstDay: String, lastDay: String,
//                                      includeSensitive: Bool) -> [String]
//   }
//
//   // Stage 2, CoachPacket.swift
//   public enum CoachPacket {
//       public static func sanitize(_ text: String) -> String
//   }
//
// Also `PersonalEvent`, `PersonalEventKind` and `PersonalEvents.issues`, as listed at the top of
// PersonalEventsTests.swift, and the fixture of PersonalEventsFixture.swift.

import XCTest
@testable import StrandAnalytics

private typealias F = PersonalEventsFixture

private extension Array {
    /// The element at `index`, or nil when the array is shorter: a wrong row count must fail an
    /// assertion, not stop the run.
    func at(_ index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// `PersonalEvents.packetLines`: the body rows of the coach packet's events section, in stage 2's
/// packet grammar (stage-5.md §7.5; goldens §13.3).
final class PersonalEventsPacketTests: XCTestCase {

    private let intro = "entered by the owner, whole local days, oldest first:"
    private let noneListed = "events: none listed in range"

    private func lines(_ events: [PersonalEvent], _ firstDay: String, _ lastDay: String,
                       sensitive: Bool) -> [String] {
        PersonalEvents.packetLines(events: events, firstDay: firstDay, lastDay: lastDay,
                                   includeSensitive: sensitive)
    }

    /// `count` one-day travel events on consecutive days from `firstDay`, `createdAt` from 2000 up.
    private func oneDayTravel(count: Int, from firstDay: (year: Int, month: Int, day: Int) = (2031, 3, 1))
        -> [PersonalEvent] {
        let base = F.dayNumber(firstDay.year, firstDay.month, firstDay.day)
        return (0..<count).map { index in
            let day = F.key(base + index)
            return F.make(String(format: "%016x", 0xA000 + index), .travel, day, day, createdAt: 2000 + index)
        }
    }

    /// Golden G-E6 (§13.3): fifteen one-day travel events on 2031-03-01 to 2031-03-15.
    private let goldenE6 = [
        "entered by the owner, whole local days, oldest first:",
        "  (3 earlier events in range not shown)",
        "  2031-03-04: travel",
        "  2031-03-05: travel",
        "  2031-03-06: travel",
        "  2031-03-07: travel",
        "  2031-03-08: travel",
        "  2031-03-09: travel",
        "  2031-03-10: travel",
        "  2031-03-11: travel",
        "  2031-03-12: travel",
        "  2031-03-13: travel",
        "  2031-03-14: travel",
        "  2031-03-15: travel",
    ]

    // MARK: - Goldens (§13.3)

    func testPacketLinesFourteenDayGoldenWithSensitiveOff() {
        XCTAssertEqual(lines(F.all, "2031-03-13", "2031-03-26", sensitive: false), [
            "entered by the owner, whole local days, oldest first:",
            "  2031-03-10..2031-03-16: travel; note \"Fixture trip\"",
        ])
    }

    func testPacketLinesFourteenDayGoldenWithSensitiveOn() {
        XCTAssertEqual(lines(F.all, "2031-03-13", "2031-03-26", sensitive: true), [
            "entered by the owner, whole local days, oldest first:",
            "  2031-03-10..2031-03-16: travel; note \"Fixture trip\"",
            "  2031-03-26: custom \"Fixture change\"; note \"Fixture note\"",
        ])
    }

    func testPacketLinesTwentyEightDayGolden() {
        let golden = [
            "entered by the owner, whole local days, oldest first:",
            "  2031-02-03..2031-02-09: deload",
            "  2031-02-22..2031-02-24: travel",
        ]
        XCTAssertEqual(lines(F.all, "2031-01-30", "2031-02-26", sensitive: false), golden)
        XCTAssertEqual(lines(F.all, "2031-01-30", "2031-02-26", sensitive: true), golden)
    }

    func testPacketLinesOngoingGoldenWithSensitiveOn() {
        XCTAssertEqual(lines(F.all, "2031-05-08", "2031-06-04", sensitive: true), [
            "entered by the owner, whole local days, oldest first:",
            "  2031-05-19..ongoing: illness",
        ])
    }

    func testPacketLinesOneDayGolden() {
        let golden = [
            "entered by the owner, whole local days, oldest first:",
            "  2031-01-22: supplementChange",
        ]
        XCTAssertEqual(lines(F.all, "2031-01-09", "2031-01-22", sensitive: false), golden)
        XCTAssertEqual(lines(F.all, "2031-01-09", "2031-01-22", sensitive: true), golden)
    }

    func testPacketLinesWithNothingListedSayNoneListed() {
        // Variant V1: no events at all. One row, no intro.
        XCTAssertEqual(lines([], "2031-03-13", "2031-03-26", sensitive: false), [noneListed])
        XCTAssertEqual(lines([], "2031-03-13", "2031-03-26", sensitive: true), [noneListed])
        // Events exist, but none overlaps the range (fixture weeks 13 and 14 are empty).
        XCTAssertEqual(lines(F.all, "2031-03-31", "2031-04-13", sensitive: true), [noneListed])
        // Only invalid events: they are never listed.
        let invalid = F.make("a", .travel, "2031-03-20", "2031-03-19")
        XCTAssertEqual(lines([invalid], "2031-03-13", "2031-03-26", sensitive: true), [noneListed])
    }

    func testPacketLinesWithOnlySensitiveEventsAndSensitiveOffSayNoneListed() {
        // G-E3 with the switch off: the only event in range is private. The single row must be
        // exactly the "none listed" row, with no count of what was left out and no second row.
        XCTAssertEqual(lines(F.all, "2031-05-08", "2031-06-04", sensitive: false), [noneListed])
        // Variant V2: only the two private events, for any range.
        for (first, last) in [("2031-03-13", "2031-03-26"), ("2031-05-08", "2031-06-04"),
                              ("2031-01-06", "2031-06-08"), ("2031-03-26", "2031-03-26")] {
            XCTAssertEqual(lines([F.e5, F.e6], first, last, sensitive: false), [noneListed], "\(first)..\(last)")
        }
        // The wording is the same whether private events exist or not: it neither reveals nor denies.
        XCTAssertEqual(lines([F.e5, F.e6], "2031-05-08", "2031-06-04", sensitive: false),
                       lines([], "2031-05-08", "2031-06-04", sensitive: false))
    }

    func testPacketLinesPrintWholeStoredDaysNotClippedToTheRange() {
        // G-E5: the diet break runs four days past the range and is printed whole.
        let golden = [
            "entered by the owner, whole local days, oldest first:",
            "  2031-04-14..2031-04-27: dietBreak",
        ]
        XCTAssertEqual(lines(F.all, "2031-04-10", "2031-04-23", sensitive: false), golden)
        XCTAssertEqual(lines(F.all, "2031-04-10", "2031-04-23", sensitive: true), golden)
        // G-E1's travel row starts three days before its range, and is printed whole there too.
        XCTAssertEqual(lines([F.e1], "2031-03-13", "2031-03-26", sensitive: false).last,
                       "  2031-03-10..2031-03-16: travel; note \"Fixture trip\"")
    }

    // MARK: - Free text

    func testPacketLabelAndNoteGoThroughCoachPacketSanitize() {
        func row(label: String, note: String) -> String? {
            let event = F.make("a", .custom, "2031-03-12", "2031-03-12", label: label, note: note)
            XCTAssertEqual(PersonalEvents.issues(event), [])
            let rows = lines([event], "2031-03-10", "2031-03-16", sensitive: false)
            XCTAssertEqual(rows.count, 2)
            XCTAssertEqual(rows.first, intro)
            return rows.last
        }
        func expected(label: String, note: String) -> String {
            "  2031-03-12: custom \"\(CoachPacket.sanitize(label))\"; note \"\(CoachPacket.sanitize(note))\""
        }
        /// The two quoted values of a custom row with a note, cut out by the fixed text around them.
        func quoted(_ row: String) -> (label: String, note: String)? {
            let head = "  2031-03-12: custom \""
            let middle = "\"; note \""
            guard row.hasPrefix(head), row.hasSuffix("\""), let cut = row.range(of: middle) else { return nil }
            let label = row[row.index(row.startIndex, offsetBy: head.count)..<cut.lowerBound]
            let note = row[cut.upperBound..<row.index(before: row.endIndex)]
            return (String(label), String(note))
        }

        // A double quote becomes a single one; a line break and a run of spaces become one space.
        let label = "Fix \"ture\""
        let note = "line one\nline   two"
        XCTAssertEqual(row(label: label, note: note), expected(label: label, note: note))
        // The same row, written out by hand from stage 2 §6.2's rule.
        XCTAssertEqual(row(label: label, note: note),
                       "  2031-03-12: custom \"Fix 'ture'\"; note \"line one line two\"")

        // A 280-character note is cut to at most 48 UTF-8 bytes at a character boundary, whatever
        // the width of its characters; so is a 40-character label.
        let notes = [
            String(repeating: "a", count: 280),                       // 1 byte each
            String(repeating: "é", count: 280),                       // 2 bytes each
            String(repeating: "€", count: 280),                       // 3 bytes each
            "a" + String(repeating: "𝔸", count: 279),                 // 4 bytes each, off the 4-byte grid
            String(repeating: "👨‍👩‍👧‍👦", count: 280),                 // 25 bytes each: one fits, two do not
        ]
        let longLabel = String(repeating: "𝔸", count: 40)
        for long in notes {
            guard let actual = row(label: longLabel, note: long) else { return XCTFail("no row") }
            XCTAssertEqual(actual, expected(label: longLabel, note: long))
            guard let parts = quoted(actual) else { return XCTFail("row not in the grammar: \(actual)") }
            XCTAssertLessThanOrEqual(parts.label.utf8.count, 48)
            XCTAssertLessThanOrEqual(parts.note.utf8.count, 48)
            XCTAssertFalse(parts.note.isEmpty)
            // Cut at a character boundary: what is printed is a prefix of the note, in whole characters.
            XCTAssertTrue(long.hasPrefix(parts.note), parts.note)
            XCTAssertTrue(longLabel.hasPrefix(parts.label), parts.label)
            XCTAssertLessThan(parts.note.count, 280)
        }

        // Tabs and other control characters never reach a row, and a quoted value never holds `"`.
        let messy = row(label: "\tFix\u{1}ture\t", note: " \"a\"\r\n\"b\" ")
        XCTAssertEqual(messy, expected(label: "\tFix\u{1}ture\t", note: " \"a\"\r\n\"b\" "))
        XCTAssertEqual(messy, "  2031-03-12: custom \"Fix ture\"; note \"'a' 'b'\"")
    }

    func testARowWhoseNoteLooksLikeAnEmailAddressOrAPathIsReturnedIntact() {
        // Stage 2 rule G-8: the packet's privacy scan blocks such a packet, and says so. This
        // function does not scan, drop the row or rewrite the text to get past the scan.
        let email = "fixture.person@example.invalid"
        let path = "/Users/fixture/notes/fixture.txt"
        let events = [
            F.make("a", .travel, "2031-03-11", "2031-03-11", note: email, createdAt: 1),
            F.make("b", .custom, "2031-03-12", "2031-03-12", label: path, note: path, createdAt: 2),
            F.make("c", .custom, "2031-03-13", "2031-03-13", label: email, createdAt: 3),
        ]
        XCTAssertTrue(events.allSatisfy { PersonalEvents.issues($0).isEmpty })
        XCTAssertEqual(CoachPacket.sanitize(email), email)
        XCTAssertEqual(CoachPacket.sanitize(path), path)
        XCTAssertEqual(lines(events, "2031-03-10", "2031-03-16", sensitive: false), [
            intro,
            "  2031-03-11: travel; note \"fixture.person@example.invalid\"",
            "  2031-03-12: custom \"/Users/fixture/notes/fixture.txt\"; note \"/Users/fixture/notes/fixture.txt\"",
            "  2031-03-13: custom \"fixture.person@example.invalid\"",
        ])
    }

    // MARK: - Row limit

    func testPacketLinesStopAtTheRowLimitWithAnEarlierNotShownRow() {
        let fifteen = oneDayTravel(count: 15)
        XCTAssertEqual(fifteen.first?.startDay, "2031-03-01")
        XCTAssertEqual(fifteen.last?.startDay, "2031-03-15")
        XCTAssertEqual(fifteen.last?.createdAt, 2014)
        let rows = lines(fifteen, "2031-02-27", "2031-03-26", sensitive: false)
        XCTAssertEqual(rows, goldenE6)
        XCTAssertEqual(rows.count, 14)
        // Not sensitive, so the switch changes nothing; and the input order changes nothing.
        XCTAssertEqual(lines(fifteen, "2031-02-27", "2031-03-26", sensitive: true), goldenE6)
        XCTAssertEqual(lines(fifteen.reversed(), "2031-02-27", "2031-03-26", sensitive: false), goldenE6)
    }

    func testEarlierNotShownCountsOnlyListedEvents() {
        // G-E6 plus three private one-day events in range. With the switch off the count stays 3
        // and the rows are exactly G-E6: nothing reveals that anything was left out.
        let hidden = [
            F.make("00000000000000b1", .illness, "2031-03-02", "2031-03-02", sensitive: true, createdAt: 3001),
            F.make("00000000000000b2", .illness, "2031-03-16", "2031-03-16", sensitive: true, createdAt: 3002),
            F.make("00000000000000b3", .custom, "2031-03-17", "2031-03-17", label: "Fixture change",
                   sensitive: true, createdAt: 3003),
        ]
        let events = oneDayTravel(count: 15) + hidden
        XCTAssertEqual(lines(events, "2031-02-27", "2031-03-26", sensitive: false), goldenE6)
        XCTAssertEqual(lines(hidden + oneDayTravel(count: 15), "2031-02-27", "2031-03-26", sensitive: false),
                       goldenE6)
        // With the switch on, eighteen are listed: six earlier, then the last twelve, oldest first.
        XCTAssertEqual(lines(events, "2031-02-27", "2031-03-26", sensitive: true), [
            "entered by the owner, whole local days, oldest first:",
            "  (6 earlier events in range not shown)",
            "  2031-03-06: travel",
            "  2031-03-07: travel",
            "  2031-03-08: travel",
            "  2031-03-09: travel",
            "  2031-03-10: travel",
            "  2031-03-11: travel",
            "  2031-03-12: travel",
            "  2031-03-13: travel",
            "  2031-03-14: travel",
            "  2031-03-15: travel",
            "  2031-03-16: illness",
            "  2031-03-17: custom \"Fixture change\"",
        ])
    }

    func testEarlierNotShownCountsOnlyEventsInTheRange() {
        // Fifteen events, of which the first two lie before the range: thirteen are listed.
        let rows = lines(oneDayTravel(count: 15), "2031-03-03", "2031-03-26", sensitive: false)
        XCTAssertEqual(rows.count, 14)
        XCTAssertEqual(rows.at(1), "  (1 earlier events in range not shown)")
        XCTAssertEqual(rows.at(2), "  2031-03-04: travel")
        XCTAssertEqual(rows.last, "  2031-03-15: travel")
    }

    func testExactlyTheRowLimitPrintsNoEarlierRow() {
        // One under, at, and one over the limit of twelve.
        let eleven = lines(oneDayTravel(count: 11), "2031-02-27", "2031-03-26", sensitive: false)
        XCTAssertEqual(eleven.count, 12)
        XCTAssertEqual(eleven.at(0), intro)
        XCTAssertEqual(eleven.at(1), "  2031-03-01: travel")
        XCTAssertEqual(eleven.at(11), "  2031-03-11: travel")

        let twelve = lines(oneDayTravel(count: 12), "2031-02-27", "2031-03-26", sensitive: false)
        XCTAssertEqual(twelve, [
            "entered by the owner, whole local days, oldest first:",
            "  2031-03-01: travel",
            "  2031-03-02: travel",
            "  2031-03-03: travel",
            "  2031-03-04: travel",
            "  2031-03-05: travel",
            "  2031-03-06: travel",
            "  2031-03-07: travel",
            "  2031-03-08: travel",
            "  2031-03-09: travel",
            "  2031-03-10: travel",
            "  2031-03-11: travel",
            "  2031-03-12: travel",
        ])
        XCTAssertFalse(twelve.contains { $0.contains("earlier") })

        let thirteen = lines(oneDayTravel(count: 13), "2031-02-27", "2031-03-26", sensitive: false)
        XCTAssertEqual(thirteen.count, 14)
        XCTAssertEqual(thirteen.at(0), intro)
        XCTAssertEqual(thirteen.at(1), "  (1 earlier events in range not shown)")
        XCTAssertEqual(thirteen.at(2), "  2031-03-02: travel")
        XCTAssertEqual(thirteen.at(13), "  2031-03-13: travel")
    }

    func testRowLimitIsTwelveAndByteAllowanceIsTwoThousand() {
        XCTAssertEqual(PersonalEvents.packetRowLimit, 12)
        XCTAssertEqual(PersonalEvents.packetByteAllowance, 2000)
    }

    func testWidestPacketRowsStayUnderTheByteAllowance() {
        // Twenty events in range, each as wide as an event can be: custom, a 40-character label
        // and a 280-character note of four-byte characters, and an end day.
        let label = String(repeating: "𝔸", count: 40)
        let note = String(repeating: "𝔸", count: 280)
        XCTAssertEqual(label.utf8.count, 160)
        let base = F.dayNumber(2031, 3, 1)
        let events = (0..<20).map { index in
            F.make(String(format: "%016x", 0xC000 + index), .custom, F.key(base + index), F.key(base + index + 1),
                   label: label, note: note, sensitive: index % 2 == 0, createdAt: 4000 + index)
        }
        XCTAssertTrue(events.allSatisfy { PersonalEvents.issues($0).isEmpty })
        let rows = lines(events, "2031-02-27", "2031-03-26", sensitive: true)

        // Intro, the "earlier" row, and twelve event rows of exactly the widest form (§7.5 "Size").
        XCTAssertEqual(rows.count, 14)
        XCTAssertEqual(rows.at(0)?.utf8.count, 53)
        XCTAssertEqual(rows.at(1), "  (8 earlier events in range not shown)")
        let twelve = String(repeating: "𝔸", count: 12)
        XCTAssertEqual(rows.at(2), "  2031-03-09..2031-03-10: custom \"\(twelve)\"; note \"\(twelve)\"")
        for row in rows.dropFirst(2) {
            XCTAssertEqual(row.utf8.count, 140, row)
        }
        // One "\n" per row, plus 14 bytes for stage 2's heading line and the blank line before it.
        let bytes = rows.reduce(0) { $0 + $1.utf8.count + 1 } + 14
        XCTAssertEqual(bytes, 54 + 40 + 12 * 141 + 14)
        XCTAssertLessThanOrEqual(bytes, PersonalEvents.packetByteAllowance)

        // The bound does not grow with the number of stored events.
        let many = (0..<300).map { index in
            F.make(String(format: "%016x", 0xD000 + index), .custom, F.key(base - 280 + index),
                   F.key(base - 280 + index + 1), label: label, note: note, createdAt: index)
        }
        let manyRows = lines(many, "2030-01-01", "2032-12-31", sensitive: true)
        XCTAssertEqual(manyRows.count, 14)
        XCTAssertEqual(manyRows.at(1), "  (288 earlier events in range not shown)")
        XCTAssertLessThanOrEqual(manyRows.reduce(0) { $0 + $1.utf8.count + 1 } + 14,
                                 PersonalEvents.packetByteAllowance)
    }

    // MARK: - Grammar

    func testEveryRowAfterTheIntroStartsWithTwoSpacesAndNoRowHasATabATrailingSpaceOrALineBreak() {
        let awkward = [
            F.make("a", .custom, "2031-03-11", "2031-03-12", label: "\tFixture\tchange ",
                   note: "Fixture note \n", createdAt: 1),
            F.make("b", .travel, "2031-03-12", nil, note: "trailing spaces   ", createdAt: 2),
            F.make("c", .custom, "2031-03-13", "2031-03-13", label: " padded ", createdAt: 3),
            F.make("d", .illness, "2031-03-14", nil, note: "\r\nline\ttwo\u{0}", sensitive: true, createdAt: 4),
        ]
        let inputs: [[String]] = [
            lines(awkward, "2031-03-10", "2031-03-16", sensitive: true),
            lines(awkward, "2031-03-10", "2031-03-16", sensitive: false),
            lines(F.all, "2031-01-06", "2031-06-08", sensitive: true),
            lines(F.all, "2031-01-06", "2031-06-08", sensitive: false),
            lines(oneDayTravel(count: 15) + awkward, "2031-02-27", "2031-03-26", sensitive: true),
        ]
        for rows in inputs {
            XCTAssertEqual(rows.first, intro)
            XCTAssertGreaterThan(rows.count, 1)
            for row in rows.dropFirst() {
                XCTAssertTrue(row.hasPrefix("  "), row.debugDescription)
                XCTAssertFalse(row.hasPrefix("   "), row.debugDescription)
            }
            for row in rows {
                XCTAssertFalse(row.contains("\t"), row.debugDescription)
                XCTAssertFalse(row.hasSuffix(" "), row.debugDescription)
                XCTAssertFalse(row.contains { $0.isNewline }, row.debugDescription)
                XCTAssertFalse(row.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F },
                               row.debugDescription)
                XCTAssertFalse(row.isEmpty)
            }
        }
        // The two rows that are not indented are the intro and the "none listed" row, and nothing else.
        XCTAssertFalse(intro.hasPrefix(" "))
        XCTAssertFalse(noneListed.hasPrefix(" "))
    }

    func testPacketLinesNeverReturnAHeading() {
        let inputs: [[String]] = [
            lines(F.all, "2031-03-13", "2031-03-26", sensitive: true),
            lines(F.all, "2031-05-08", "2031-06-04", sensitive: false),
            lines([], "2031-03-13", "2031-03-26", sensitive: false),
            lines(F.all, "2031-3-13", "2031-03-26", sensitive: true),
            lines(oneDayTravel(count: 15), "2031-02-27", "2031-03-26", sensitive: false),
        ]
        for rows in inputs {
            XCTAssertFalse(rows.isEmpty)
            for row in rows {
                XCTAssertFalse(row.hasPrefix("=="), row)
                XCTAssertFalse(row.contains("EVENTS"), row)
                XCTAssertFalse(row.trimmingCharacters(in: .whitespaces).isEmpty, "a blank line is the renderer's")
            }
        }
        // Row 1 of a listing is the intro, not a heading.
        XCTAssertEqual(lines(F.all, "2031-03-13", "2031-03-26", sensitive: true).first, intro)
    }

    func testPacketLinesContainNoIdAndNoCreatedAt() {
        let events = [
            F.make("feedfacefeedface", .travel, "2031-03-11", "2031-03-12", note: "Fixture trip", createdAt: 987_654_321),
            F.make("deadbeefdeadbeef", .custom, "2031-03-13", nil, label: "Fixture change", sensitive: true,
                   createdAt: 876_543_219),
        ]
        for sensitive in [false, true] {
            let text = lines(events, "2031-03-10", "2031-03-16", sensitive: sensitive).joined(separator: "\n")
            for needle in ["feedface", "deadbeef", "987654321", "876543219", "987,654,321",
                           "sensitive", "private", "Private", "hidden", "true", "false"] {
                XCTAssertFalse(text.contains(needle), "\(needle) with sensitive \(sensitive)")
            }
        }
        XCTAssertEqual(lines(events, "2031-03-10", "2031-03-16", sensitive: true), [
            intro,
            "  2031-03-11..2031-03-12: travel; note \"Fixture trip\"",
            "  2031-03-13..ongoing: custom \"Fixture change\"",
        ])
    }

    func testPacketLinesForAnInvalidRange() {
        let ranges = [("2031-3-13", "2031-03-26"), ("2031-03-13", "2031-02-30"), ("", ""),
                      ("0000-01-01", "2031-03-26"), ("2031-03-26", "2031-03-13"), ("2031-03-14", "2031-03-13")]
        for (first, last) in ranges {
            XCTAssertEqual(lines(F.all, first, last, sensitive: true), [noneListed], "\(first)..\(last)")
            XCTAssertEqual(lines(F.all, first, last, sensitive: false), [noneListed], "\(first)..\(last)")
        }
        // A one-day range is valid.
        XCTAssertEqual(lines(F.all, "2031-03-13", "2031-03-13", sensitive: false), [
            intro,
            "  2031-03-10..2031-03-16: travel; note \"Fixture trip\"",
        ])
    }

    func testEventsTouchingEitherEndOfTheRangeAreListedAndTheirNeighboursAreNot() {
        let events = [
            F.make("a", .travel, "2031-03-01", "2031-03-12", createdAt: 1),   // ends the day before the range
            F.make("b", .deload, "2031-03-02", "2031-03-13", createdAt: 2),   // ends on its first day
            F.make("c", .dietBreak, "2031-03-26", "2031-03-30", createdAt: 3), // starts on its last day
            F.make("d", .travel, "2031-03-27", nil, createdAt: 4),            // starts the day after
        ]
        XCTAssertEqual(lines(events, "2031-03-13", "2031-03-26", sensitive: false), [
            intro,
            "  2031-03-02..2031-03-13: deload",
            "  2031-03-26..2031-03-30: dietBreak",
        ])
    }

    func testEveryKindPrintsItsRawValueAndOnlyCustomPrintsALabel() {
        let events = [
            F.make("a", .travel, "2031-03-10", "2031-03-10", createdAt: 1),
            F.make("b", .illness, "2031-03-11", "2031-03-11", createdAt: 2),
            F.make("c", .dietBreak, "2031-03-12", "2031-03-12", createdAt: 3),
            F.make("d", .deload, "2031-03-13", "2031-03-13", createdAt: 4),
            F.make("e", .supplementChange, "2031-03-14", "2031-03-14", createdAt: 5),
            F.make("f", .custom, "2031-03-15", "2031-03-15", label: "Fixture change", createdAt: 6),
        ]
        XCTAssertEqual(lines(events, "2031-03-10", "2031-03-16", sensitive: false), [
            intro,
            "  2031-03-10: travel",
            "  2031-03-11: illness",
            "  2031-03-12: dietBreak",
            "  2031-03-13: deload",
            "  2031-03-14: supplementChange",
            "  2031-03-15: custom \"Fixture change\"",
        ])
    }

    func testRowsFollowNormalizedOrderAndIgnoreSupersededAndInvalidEvents() {
        // Same start day: createdAt, then id, decides.
        let a = F.make("0000000000000002", .travel, "2031-03-12", "2031-03-12", note: "second", createdAt: 7)
        let b = F.make("0000000000000001", .deload, "2031-03-12", "2031-03-12", note: "third", createdAt: 8)
        let c = F.make("0000000000000003", .travel, "2031-03-12", "2031-03-14", note: "first", createdAt: 6)
        let superseded = F.make("0000000000000003", .illness, "2031-03-11", nil, createdAt: 1)
        let invalid = F.make("0000000000000004", .custom, "2031-03-12", nil)
        let golden = [
            intro,
            "  2031-03-12..2031-03-14: travel; note \"first\"",
            "  2031-03-12: travel; note \"second\"",
            "  2031-03-12: deload; note \"third\"",
        ]
        XCTAssertEqual(lines([superseded, a, invalid, b, c], "2031-03-10", "2031-03-16", sensitive: true), golden)
        XCTAssertEqual(lines([invalid, b, superseded, a, c], "2031-03-10", "2031-03-16", sensitive: true), golden)
    }

    // MARK: - Privacy

    func testPacketRowsWithSensitiveExcludedContainNoPrivateLabelNoteOrKind() {
        let ranges = [("2031-03-13", "2031-03-26"), ("2031-01-30", "2031-02-26"), ("2031-05-08", "2031-06-04"),
                      ("2031-01-09", "2031-01-22"), ("2031-04-10", "2031-04-23"), ("2031-02-27", "2031-03-26"),
                      ("2030-01-01", "2032-12-31")]
        for (first, last) in ranges {
            let text = lines(F.all, first, last, sensitive: false).joined(separator: "\n")
            // In the fixture the only illness and the only custom event are the private ones.
            for needle in F.privateNeedles + ["illness", "custom", "2031-05-19", "2031-03-26:", "ongoing"] {
                XCTAssertFalse(text.contains(needle), "\(needle) in \(first)..\(last)")
            }
        }
        // And the whole span lists exactly the six events that are not private.
        XCTAssertEqual(lines(F.all, "2030-01-01", "2032-12-31", sensitive: false), [
            intro,
            "  2030-12-01..2030-12-07: travel",
            "  2031-01-22: supplementChange",
            "  2031-02-03..2031-02-09: deload",
            "  2031-02-22..2031-02-24: travel",
            "  2031-03-10..2031-03-16: travel; note \"Fixture trip\"",
            "  2031-04-14..2031-04-27: dietBreak",
        ])
    }

    func testAPrivateDeloadAndAPrivateDietBreakLeaveThePacketWhenSensitiveIsOff() {
        // Variant V9: the flag decides, not the kind.
        let v9 = F.all.map { event -> PersonalEvent in
            guard event.id == F.id(2) || event.id == F.id(3) else { return event }
            return PersonalEvent(id: event.id, kind: event.kind, label: event.label, startDay: event.startDay,
                                 endDay: event.endDay, note: event.note, sensitive: true, createdAt: event.createdAt)
        }
        // G-E2 loses its deload row.
        XCTAssertEqual(lines(v9, "2031-01-30", "2031-02-26", sensitive: false), [
            intro,
            "  2031-02-22..2031-02-24: travel",
        ])
        // G-E5 becomes the single "none listed" row.
        XCTAssertEqual(lines(v9, "2031-04-10", "2031-04-23", sensitive: false), [noneListed])
        // With the switch on both goldens are whole again.
        XCTAssertEqual(lines(v9, "2031-01-30", "2031-02-26", sensitive: true), [
            intro,
            "  2031-02-03..2031-02-09: deload",
            "  2031-02-22..2031-02-24: travel",
        ])
        XCTAssertEqual(lines(v9, "2031-04-10", "2031-04-23", sensitive: true), [
            intro,
            "  2031-04-14..2031-04-27: dietBreak",
        ])
    }

    // MARK: - Properties

    func testPacketLinesAreTheSameForTheSameInputInAnyOrder() {
        var generator = F.Generator(seed: 0x5EED_0509)
        for round in 0..<60 {
            let events = (0..<generator.below(20)).map { generator.validEvent(index: $0) }
            let a = generator.below(120)
            let first = F.day(a)
            let last = F.day(a + generator.below(28))
            for sensitive in [false, true] {
                let rows = lines(events, first, last, sensitive: sensitive)
                XCTAssertEqual(lines(events, first, last, sensitive: sensitive), rows, "round \(round)")
                XCTAssertEqual(lines(generator.shuffled(events), first, last, sensitive: sensitive), rows,
                               "round \(round)")
            }
        }
    }

    func testAnEventOutsideTheRangeNeverChangesThePacketRows() {
        var generator = F.Generator(seed: 0x5EED_050A)
        for round in 0..<100 {
            let events = (0..<generator.below(18)).map { generator.validEvent(index: $0) }
            let a = generator.below(120)
            let b = a + generator.below(28)
            let outside: PersonalEvent
            if generator.bool() {
                let end = a - 1 - generator.below(30)
                outside = F.make("00000000000000ff", .travel, F.day(end - generator.below(30)), F.day(end),
                                 note: "Fixture outside", sensitive: generator.bool(), createdAt: generator.below(5000))
            } else {
                let start = b + 1 + generator.below(30)
                outside = F.make("00000000000000ff", .travel, F.day(start), generator.bool() ? nil : F.day(start + 3),
                                 note: "Fixture outside", sensitive: generator.bool(), createdAt: generator.below(5000))
            }
            for sensitive in [false, true] {
                XCTAssertEqual(lines(events + [outside], F.day(a), F.day(b), sensitive: sensitive),
                               lines(events, F.day(a), F.day(b), sensitive: sensitive), "round \(round)")
            }
        }
    }

    func testGeneratedPacketRowsMatchTheGrammarAndTheListedCount() {
        var generator = F.Generator(seed: 0x5EED_050B)
        for round in 0..<200 {
            let events = (0..<generator.below(30)).map { generator.validEvent(index: $0) }
            let a = generator.below(120)
            let first = F.day(a)
            let last = F.day(a + generator.below(28))
            for sensitive in [false, true] {
                // The count of listed events, from the stored strings alone (§7.4's closed form).
                let listed = events.filter {
                    (sensitive || !$0.sensitive) && $0.startDay <= last && ($0.endDay == nil || $0.endDay! >= first)
                }.count
                let rows = lines(events, first, last, sensitive: sensitive)
                if listed == 0 {
                    XCTAssertEqual(rows, [noneListed], "round \(round)")
                } else if listed <= 12 {
                    XCTAssertEqual(rows.count, listed + 1, "round \(round)")
                    XCTAssertEqual(rows.first, intro, "round \(round)")
                } else {
                    XCTAssertEqual(rows.count, 14, "round \(round)")
                    XCTAssertEqual(rows.first, intro, "round \(round)")
                    XCTAssertEqual(rows.at(1), "  (\(listed - 12) earlier events in range not shown)", "round \(round)")
                }
                // Event rows are oldest first: their ten-character start days never decrease.
                let starts = rows.filter { $0.hasPrefix("  2") }.map { String($0.dropFirst(2).prefix(10)) }
                XCTAssertEqual(starts, starts.sorted(), "round \(round)")
                XCTAssertLessThanOrEqual(starts.count, 12, "round \(round)")
                XCTAssertLessThanOrEqual(rows.reduce(0) { $0 + $1.utf8.count + 1 } + 14,
                                         PersonalEvents.packetByteAllowance, "round \(round)")
            }
        }
    }

    func testPacketLinesNeverTrapOnGeneratedGarbage() {
        var generator = F.Generator(seed: 0x5EED_050C)
        for round in 0..<500 {
            let events = (0..<generator.below(20)).map { _ in generator.garbageEvent() }
            let first = generator.dayLikeString()
            let last = generator.dayLikeString()
            for sensitive in [false, true] {
                let rows = lines(events, first, last, sensitive: sensitive)
                XCTAssertFalse(rows.isEmpty, "round \(round)")
                XCTAssertLessThanOrEqual(rows.count, 14, "round \(round)")
                if rows.count == 1 {
                    XCTAssertEqual(rows, [noneListed], "round \(round)")
                } else {
                    XCTAssertEqual(rows.first, intro, "round \(round)")
                }
                for row in rows {
                    XCTAssertFalse(row.contains { $0.isNewline }, "round \(round)")
                    XCTAssertFalse(row.contains("\t"), "round \(round)")
                    XCTAssertFalse(row.hasSuffix(" "), "round \(round)")
                    XCTAssertFalse(row.hasPrefix("=="), "round \(round)")
                }
                XCTAssertLessThanOrEqual(rows.reduce(0) { $0 + $1.utf8.count + 1 } + 14,
                                         PersonalEvents.packetByteAllowance, "round \(round)")
            }
        }
    }
}
