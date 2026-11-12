import XCTest
@testable import StrandAnalytics

// Shared scaffolding ahead of stages 2 to 6 (cross-stage review, item X19): one day-key helper.
// Written before the implementation exists. Synthetic values only.
//
// Stage 1 holds the day-key rule privately (`CutScorecard.dayNumber` and `CutScorecard.dayKey`,
// ruling R5 of the stage 1 specification). Three later stages each planned their own copy. These
// tests pin the one public form every stage is to call, and pin it to `CutScorecard.weekStart`,
// which is the only place the private rule can be observed today.
//
// API ASSUMED BY THESE TESTS (new, in Packages/StrandAnalytics/Sources/StrandAnalytics/CanonicalDay.swift)
//
//     /// The canonical day key: the ten-character "yyyy-MM-dd" form of a real proleptic-Gregorian
//     /// date in years 0001 to 9999, ASCII digits only. A day has exactly one key, and string order
//     /// is calendar order. Pure integer civil-date arithmetic: no Date, Calendar, TimeZone or clock.
//     public enum CanonicalDay {
//         /// "0001-01-01" as a Julian Day Number: 1_721_426. It is a Monday.
//         public static let firstDayNumber: Int
//         /// "9999-12-31" as a Julian Day Number: 5_373_484.
//         public static let lastDayNumber: Int
//
//         /// True when `key` is a canonical day key.
//         public static func isValid(_ key: String) -> Bool
//
//         /// The Julian Day Number of a canonical key, else nil. Numbers divisible by seven are
//         /// Mondays. This is what `CutScorecard.dayNumber` returns today.
//         public static func dayNumber(_ key: String) -> Int?
//
//         /// The key of a Julian Day Number, or nil outside firstDayNumber...lastDayNumber.
//         public static func key(dayNumber: Int) -> String?
//
//         /// The key of a Julian Day Number clamped into firstDayNumber...lastDayNumber. This is
//         /// what `CutScorecard.dayKey` returns today.
//         public static func clampedKey(dayNumber: Int) -> String
//
//         /// `key` moved by `days` (negative moves back). Nil when `key` is not canonical or the
//         /// result is outside years 0001 to 9999. Never traps, whatever `days` is.
//         public static func adding(_ days: Int, to key: String) -> String?
//
//         /// Whole days from `from` to `to` (positive when `to` is later). Nil unless both are
//         /// canonical.
//         public static func daysBetween(_ from: String, _ to: String) -> Int?
//
//         /// -1 when `a` is earlier than `b`, 0 when they are the same day, 1 when later. Nil
//         /// unless both are canonical.
//         public static func compare(_ a: String, _ b: String) -> Int?
//
//         /// The Monday of the week containing `key`. Nil unless `key` is canonical. Equal to
//         /// `CutScorecard.weekStart(containing:)` for every string.
//         public static func weekStart(containing key: String) -> String?
//     }
//
// `CutScorecard` is to call these in place of its private copies, with its results unchanged; its
// own suites and the parity oracle are the check of that, and are not repeated here.
//
// The expected values come from `CutScorecardFixture`'s day arithmetic (days since 1970 by the
// civil-calendar algorithm), which is deliberately not the engine's Julian Day Number code.
final class CanonicalDayTests: XCTestCase {
    private typealias F = CutScorecardFixture

    /// 1970-01-01 as a Julian Day Number.
    private let epochDayNumber = 2_440_588

    /// The Julian Day Number of a valid key, by the fixture's independent arithmetic.
    private func number(_ key: String) -> Int { F.dayNumber(key) + epochDayNumber }

    /// The key of a Julian Day Number inside the valid range, by the fixture's independent arithmetic.
    private func key(_ number: Int) -> String { F.dayKey(number - epochDayNumber) }

    /// Every key ruling R5 rejects in the stage 1 suites, the parity oracle's rejected keys, and
    /// further near-misses of the canonical form.
    private let nonCanonical = [
        // CutScorecardRulingTests.testNonCanonicalDayKeysAreInvalidEverywhere
        "2031-1-8", "2031-01-8", "2031-1-08", "+2031-01-08", "2031-+1-08", "2031-01-+8", "-031-01-08",
        "0000-01-01", "10000-01-01", "02031-01-08", "2031/01/08", "20310108", " 2031-01-08",
        "2031-01-08 ", "2031-01-08T00:00", "2031- 1-08", "31-01-08",
        // CutScorecardOracle.weekStartLines
        "0000-12-31", "2031-02-29", "1900-02-29", "", "2031-13-01", "2031-00-10", "2031-01-00",
        "2031-01-32", "2031-01-08-01", "\u{662}\u{660}\u{663}\u{661}-01-08", "2031-01-0\u{663}",
        // Ten characters that are not a day.
        "2031-01-0a", "2031_01_08", "2031-01.08", "2031-0108-", "-2031-1-08", "2031--1-08", "2031-01--8",
        "2031-01-08\n", "\t031-01-08", "aaaa-bb-cc", "0x7f-01-08", "2031-1e-08", "    -  -  ",
        // Not real dates.
        "2031-04-31", "2031-06-31", "2031-09-31", "2031-11-31", "2100-02-29", "2200-02-29", "2031-02-30",
        "2032-02-30", "0001-00-01", "9999-12-32", "0001-13-01",
        // Full-width digits, and a combining mark that leaves the scalar count at ten or the look unchanged.
        "\u{FF12}031-01-08", "2031-01-08\u{301}", "2031-01-0\u{FF18}",
    ]

    /// A fixed-seed generator: the same keys on every run.
    private struct Generator {
        var state: UInt64
        mutating func next() -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(state >> 33)
        }
        mutating func below(_ n: Int) -> Int { next() % n }
    }

    // MARK: - The range

    func testTheRangeIsYearsOneToNineThousandNineHundredAndNinetyNine() {
        XCTAssertEqual(CanonicalDay.firstDayNumber, 1_721_426)
        XCTAssertEqual(CanonicalDay.lastDayNumber, 5_373_484)
        XCTAssertEqual(CanonicalDay.firstDayNumber, number("0001-01-01"), "by the independent arithmetic")
        XCTAssertEqual(CanonicalDay.lastDayNumber, number("9999-12-31"), "by the independent arithmetic")
        XCTAssertEqual(CanonicalDay.firstDayNumber % 7, 0, "0001-01-01 is a Monday, so no week starts before it")

        XCTAssertEqual(CanonicalDay.dayNumber("0001-01-01"), 1_721_426)
        XCTAssertEqual(CanonicalDay.dayNumber("9999-12-31"), 5_373_484)
        XCTAssertEqual(CanonicalDay.dayNumber("1970-01-01"), 2_440_588)
        XCTAssertEqual(CanonicalDay.dayNumber("2000-01-01"), 2_451_545)
        XCTAssertEqual(CanonicalDay.key(dayNumber: 1_721_426), "0001-01-01")
        XCTAssertEqual(CanonicalDay.key(dayNumber: 5_373_484), "9999-12-31")
        XCTAssertEqual(CanonicalDay.key(dayNumber: 2_440_588), "1970-01-01")
    }

    // MARK: - Validation

    func testCanonicalKeysAreValid() {
        let valid = ["0001-01-01", "0001-01-07", "0031-01-08", "0999-12-31", "1000-01-01", "1582-10-10",
                     "1900-02-28", "1969-12-31", "1970-01-01", "2000-02-29", "2028-02-29", "2031-01-08",
                     "2031-02-28", "2031-12-31", "2032-02-29", "2400-02-29", "9999-01-01", "9999-12-31"]
        for key in valid {
            XCTAssertTrue(CanonicalDay.isValid(key), key)
            XCTAssertEqual(CanonicalDay.dayNumber(key), number(key), key)
            XCTAssertNotNil(CutScorecard.weekStart(containing: key), "stage 1 accepts \(key) too")
        }
    }

    func testNonCanonicalKeysAreInvalidInEveryFunction() {
        let good = "2031-01-08"
        for key in nonCanonical {
            let label = "\"\(key)\""
            XCTAssertFalse(CanonicalDay.isValid(key), label)
            XCTAssertNil(CanonicalDay.dayNumber(key), label)
            XCTAssertNil(CanonicalDay.adding(0, to: key), label)
            XCTAssertNil(CanonicalDay.adding(1, to: key), label)
            XCTAssertNil(CanonicalDay.daysBetween(key, good), label)
            XCTAssertNil(CanonicalDay.daysBetween(good, key), label)
            XCTAssertNil(CanonicalDay.daysBetween(key, key), label)
            XCTAssertNil(CanonicalDay.compare(key, good), label)
            XCTAssertNil(CanonicalDay.compare(good, key), label)
            XCTAssertNil(CanonicalDay.compare(key, key), "an invalid key is not equal to itself: \(label)")
            XCTAssertNil(CanonicalDay.weekStart(containing: key), label)
            XCTAssertNil(CutScorecard.weekStart(containing: key), "stage 1 rejects \(label) too")
        }
    }

    /// Every month length in a common year, a leap year, a century year and a four-century year.
    func testMonthLengthsAndLeapYears() {
        let common = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        let leapYears: Set<Int> = [4, 2000, 2028, 2032, 2400, 9996]
        for year in [1, 4, 1900, 2000, 2028, 2031, 2032, 2100, 2400, 9996, 9999] {
            for month in 1...12 {
                let length = common[month - 1] + (month == 2 && leapYears.contains(year) ? 1 : 0)
                let prefix = String(format: "%04d-%02d-", year, month)
                XCTAssertFalse(CanonicalDay.isValid(prefix + "00"), prefix + "00")
                for day in 1...31 {
                    let key = prefix + String(format: "%02d", day)
                    XCTAssertEqual(CanonicalDay.isValid(key), day <= length, key)
                    XCTAssertEqual(CanonicalDay.weekStart(containing: key) != nil, day <= length, key)
                }
            }
        }
    }

    // MARK: - Day numbers and keys

    func testKeyOfADayNumberIsNilOutsideTheRangeAndClampedOnRequest() {
        let first = CanonicalDay.firstDayNumber, last = CanonicalDay.lastDayNumber
        for number in [first - 1, first - 7, 0, -1, Int.min, Int.min + 1, last + 1, last + 366, Int.max, Int.max - 1] {
            XCTAssertNil(CanonicalDay.key(dayNumber: number), "\(number)")
            XCTAssertEqual(CanonicalDay.clampedKey(dayNumber: number), number < first ? "0001-01-01" : "9999-12-31",
                           "\(number)")
        }
        for number in [first, first + 1, 2_440_588, last - 1, last] {
            XCTAssertEqual(CanonicalDay.key(dayNumber: number), key(number), "\(number)")
            XCTAssertEqual(CanonicalDay.clampedKey(dayNumber: number), key(number), "\(number)")
        }
    }

    /// Every day of the first and the last two years, and of the years around 1970 and 2031.
    func testDayNumbersAndKeysRoundTripDayByDay() {
        let first = CanonicalDay.firstDayNumber, last = CanonicalDay.lastDayNumber
        let spans = [first...(first + 800), (last - 800)...last, (number("1969-01-01"))...(number("1971-12-31")),
                     (number("2027-12-25"))...(number("2033-01-07"))]
        for span in spans {
            var previous: String?
            for n in span {
                let expected = key(n)
                XCTAssertEqual(CanonicalDay.key(dayNumber: n), expected, "\(n)")
                XCTAssertEqual(CanonicalDay.dayNumber(expected), n, expected)
                XCTAssertEqual(expected.utf8.count, 10, expected)
                if let previous {
                    XCTAssertLessThan(previous, expected, "string order is calendar order")
                    XCTAssertEqual(CanonicalDay.adding(1, to: previous), expected, previous)
                    XCTAssertEqual(CanonicalDay.adding(-1, to: expected), previous, expected)
                }
                previous = expected
            }
        }
    }

    // MARK: - Adding days

    func testAddingDaysAcrossMonthYearAndLeapBoundaries() {
        let cases: [(String, Int, String)] = [
            ("2031-01-08", 0, "2031-01-08"), ("2031-01-08", 1, "2031-01-09"), ("2031-01-08", -1, "2031-01-07"),
            ("2031-01-08", 7, "2031-01-15"), ("2031-01-08", -7, "2031-01-01"), ("2031-01-08", -8, "2030-12-31"),
            ("2030-12-31", 1, "2031-01-01"), ("2031-01-01", -1, "2030-12-31"), ("2031-12-31", 1, "2032-01-01"),
            ("2031-02-28", 1, "2031-03-01"), ("2031-03-01", -1, "2031-02-28"),
            ("2032-02-28", 1, "2032-02-29"), ("2032-02-28", 2, "2032-03-01"), ("2032-03-01", -1, "2032-02-29"),
            ("2032-02-29", 365, "2033-02-28"), ("2032-02-29", 366, "2033-03-01"), ("2032-02-29", -366, "2031-02-28"),
            ("2032-02-29", 1_461, "2036-02-29"), ("2000-02-29", 36_524, "2100-02-28"),
            ("2100-02-28", 1, "2100-03-01"), ("1900-02-28", 1, "1900-03-01"), ("2000-02-28", 1, "2000-02-29"),
            ("1999-12-31", 1, "2000-01-01"), ("1969-12-31", 1, "1970-01-01"), ("1970-01-01", -1, "1969-12-31"),
            ("2031-01-31", 1, "2031-02-01"), ("2031-04-30", 1, "2031-05-01"), ("2031-01-08", 365, "2032-01-08"),
            ("2031-01-08", 146_097, "2431-01-08"), ("2431-01-08", -146_097, "2031-01-08"),
            ("0001-01-01", 1, "0001-01-02"), ("0001-12-31", 1, "0002-01-01"), ("0999-12-31", 1, "1000-01-01"),
            ("1000-01-01", -1, "0999-12-31"), ("9999-12-30", 1, "9999-12-31"), ("9999-01-01", 364, "9999-12-31"),
            ("0001-01-01", 3_652_058, "9999-12-31"), ("9999-12-31", -3_652_058, "0001-01-01"),
        ]
        for (day, offset, expected) in cases {
            XCTAssertEqual(CanonicalDay.adding(offset, to: day), expected, "\(day) + \(offset)")
            XCTAssertEqual(F.day(day, offset), expected, "the table itself, by the independent arithmetic")
        }
    }

    func testAddingPastEitherEndIsNil() {
        XCTAssertNil(CanonicalDay.adding(-1, to: "0001-01-01"))
        XCTAssertNil(CanonicalDay.adding(1, to: "9999-12-31"))
        XCTAssertNil(CanonicalDay.adding(-8, to: "0001-01-08"))
        XCTAssertNil(CanonicalDay.adding(365, to: "9999-01-01"))
        XCTAssertNil(CanonicalDay.adding(3_652_059, to: "0001-01-01"))
        XCTAssertNil(CanonicalDay.adding(-3_652_059, to: "9999-12-31"))
        XCTAssertEqual(CanonicalDay.adding(-7, to: "0001-01-08"), "0001-01-01")
    }

    /// An offset no calendar holds is answered with nil: the sum is never formed with a trapping add.
    func testHugeAndNegativeOffsetsDoNotTrap() {
        let offsets = [Int.max, Int.max - 1, Int.max - 5_373_484, Int.max - 1_721_426, Int.max / 2,
                       Int.min, Int.min + 1, Int.min + 5_373_484, Int.min + 1_721_426, Int.min / 2,
                       Int(Int32.max), Int(Int32.min), 1_000_000_000_000, -1_000_000_000_000, 3_652_059, -3_652_059]
        for day in ["0001-01-01", "1970-01-01", "2031-01-08", "9999-12-31"] {
            for offset in offsets {
                XCTAssertNil(CanonicalDay.adding(offset, to: day), "\(day) + \(offset)")
            }
        }
        for key in nonCanonical {
            XCTAssertNil(CanonicalDay.adding(Int.max, to: key), "\"\(key)\"")
            XCTAssertNil(CanonicalDay.adding(Int.min, to: key), "\"\(key)\"")
        }
    }

    // MARK: - Days between and compare

    func testDaysBetweenIsSignedAndExact() {
        let cases: [(String, String, Int)] = [
            ("2031-01-08", "2031-01-08", 0), ("2031-01-08", "2031-01-09", 1), ("2031-01-09", "2031-01-08", -1),
            ("2030-12-31", "2031-01-01", 1), ("2031-01-01", "2032-01-01", 365), ("2032-01-01", "2033-01-01", 366),
            ("2032-02-28", "2032-03-01", 2), ("2031-02-28", "2031-03-01", 1), ("2100-02-28", "2100-03-01", 1),
            ("2000-01-01", "2400-01-01", 146_097), ("1970-01-01", "2031-01-08", 22_287),
            ("0001-01-01", "9999-12-31", 3_652_058), ("9999-12-31", "0001-01-01", -3_652_058),
            ("0001-01-01", "0001-01-01", 0), ("9999-12-31", "9999-12-31", 0),
        ]
        for (from, to, expected) in cases {
            XCTAssertEqual(CanonicalDay.daysBetween(from, to), expected, "\(from) to \(to)")
            XCTAssertEqual(F.dayNumber(to) - F.dayNumber(from), expected, "the table itself")
            XCTAssertEqual(CanonicalDay.adding(expected, to: from), to, "adding undoes between")
        }
    }

    func testCompareAgreesWithStringOrderOfCanonicalKeys() {
        let keys = ["0001-01-01", "0001-01-02", "0009-12-31", "0010-01-01", "0999-12-31", "1000-01-01",
                    "1969-12-31", "1970-01-01", "2031-01-08", "2031-01-09", "2031-02-01", "2031-10-01",
                    "2032-02-29", "2032-03-01", "9999-12-30", "9999-12-31"]
        for a in keys {
            for b in keys {
                let expected = a < b ? -1 : (a == b ? 0 : 1)
                XCTAssertEqual(CanonicalDay.compare(a, b), expected, "\(a) against \(b)")
                XCTAssertEqual((F.dayNumber(a) - F.dayNumber(b)).signum(), expected, "the table itself")
            }
        }
    }

    // MARK: - Week start

    func testWeekStartsOnMonday() {
        // 2031-01-06 is a Monday (CutScorecardSeriesTests).
        let week = ["2031-01-06", "2031-01-07", "2031-01-08", "2031-01-09", "2031-01-10", "2031-01-11", "2031-01-12"]
        for day in week { XCTAssertEqual(CanonicalDay.weekStart(containing: day), "2031-01-06", day) }
        XCTAssertEqual(CanonicalDay.weekStart(containing: "2031-01-05"), "2030-12-30", "the Sunday before closes the old week")
        XCTAssertEqual(CanonicalDay.weekStart(containing: "2031-01-13"), "2031-01-13", "the Monday after opens a new one")

        // Across a year boundary, and around both kinds of 29 February.
        for day in ["2030-12-30", "2030-12-31", "2031-01-01", "2031-01-05"] {
            XCTAssertEqual(CanonicalDay.weekStart(containing: day), "2030-12-30", day)
        }
        XCTAssertEqual(CanonicalDay.weekStart(containing: "2030-12-29"), "2030-12-23")
        for day in ["2028-02-28", "2028-02-29", "2028-03-01", "2028-03-05"] {
            XCTAssertEqual(CanonicalDay.weekStart(containing: day), "2028-02-28", day)
        }
        XCTAssertEqual(CanonicalDay.weekStart(containing: "2032-02-29"), "2032-02-23", "a Sunday")
        XCTAssertEqual(CanonicalDay.weekStart(containing: "2032-03-01"), "2032-03-01", "a Monday")

        // The ends of the calendar.
        XCTAssertEqual(CanonicalDay.weekStart(containing: "0001-01-01"), "0001-01-01", "a Monday")
        XCTAssertEqual(CanonicalDay.weekStart(containing: "0001-01-07"), "0001-01-01", "the Sunday after")
        XCTAssertEqual(CanonicalDay.weekStart(containing: "0001-01-08"), "0001-01-08")
        XCTAssertEqual(CanonicalDay.weekStart(containing: "9999-12-31"), "9999-12-27", "a Friday")
        XCTAssertEqual(CanonicalDay.weekStart(containing: "9999-12-26"), "9999-12-20", "a Sunday")
    }

    /// The week start is the latest day number divisible by seven, which is what stage 1 relies on
    /// when it turns a week index back into a key.
    func testWeekStartIsTheDayNumberRoundedDownToAMultipleOfSeven() throws {
        var generator = Generator(state: 0x5CAF_F01D)
        for _ in 0..<2_000 {
            let n = CanonicalDay.firstDayNumber + generator.below(3_652_059)
            let day = key(n)
            let monday = try XCTUnwrap(CanonicalDay.weekStart(containing: day), day)
            let mondayNumber = try XCTUnwrap(CanonicalDay.dayNumber(monday), monday)
            XCTAssertEqual(mondayNumber, n / 7 * 7, day)
            XCTAssertEqual(CanonicalDay.clampedKey(dayNumber: n / 7 * 7), monday, day)
            XCTAssertEqual(CanonicalDay.daysBetween(monday, day), n % 7, day)
            XCTAssertEqual(CanonicalDay.weekStart(containing: monday), monday, "a Monday is its own week start")
        }
    }

    // MARK: - Agreement with stage 1

    /// X19: one test pins `CanonicalDay` to `CutScorecard.weekStart`. A fixed-seed spread over the
    /// whole range, every day of several years, and every rejected key.
    func testWeekStartAgreesWithCutScorecardOverAGeneratedSpread() {
        var keys: [String] = nonCanonical
        var generator = Generator(state: 20_310_108)
        for _ in 0..<5_000 { keys.append(key(CanonicalDay.firstDayNumber + generator.below(3_652_059))) }
        for year in [1, 2, 1900, 2000, 2031, 2032, 9998, 9999] {
            let start = number(String(format: "%04d-01-01", year))
            for offset in 0..<(number(String(format: "%04d-12-31", year)) - start + 1) { keys.append(key(start + offset)) }
        }
        // Generated strings that are mostly not days: wrong separators, lengths and field values.
        let alphabet = Array("0123456789-- /+")
        for _ in 0..<3_000 {
            let length = 8 + generator.below(5)
            keys.append(String((0..<length).map { _ in alphabet[generator.below(alphabet.count)] }))
        }
        for _ in 0..<3_000 {
            keys.append(String(format: "%04d-%02d-%02d", generator.below(10_002), generator.below(14), generator.below(33)))
        }

        var valid = 0
        for key in keys {
            let stageOne = CutScorecard.weekStart(containing: key)
            XCTAssertEqual(CanonicalDay.weekStart(containing: key), stageOne, "\"\(key)\"")
            XCTAssertEqual(CanonicalDay.isValid(key), stageOne != nil, "\"\(key)\"")
            if stageOne != nil { valid += 1 }
        }
        XCTAssertGreaterThan(valid, 8_000, "the spread holds valid days")
        XCTAssertGreaterThan(keys.count - valid, 3_000, "and rejected strings")
    }

    /// `evaluate` reports its weeks and its evidence start by the private day arithmetic. The same
    /// values follow from `CanonicalDay`, at the fixture's dates and at both ends of the calendar.
    func testCutScorecardOutputsFollowFromCanonicalDay() throws {
        for today in ["2031-01-15", "2031-03-09", "2032-02-29", "0001-01-03", "0001-03-01", "9999-12-31"] {
            let start = try XCTUnwrap(CanonicalDay.adding(-2, to: today) ?? CanonicalDay.adding(0, to: today))
            let result = CutScorecard.evaluate(F.make(weights: [F.weight(start, 100.0), F.weight(today, 99.5)],
                                                      phase: F.phase(startDay: start), today: today))
            XCTAssertNil(result.invalidInput, today)
            let thisMonday = try XCTUnwrap(CanonicalDay.weekStart(containing: today))
            let firstMonday = try XCTUnwrap(CanonicalDay.weekStart(containing: start))
            let span = try XCTUnwrap(CanonicalDay.daysBetween(firstMonday, thisMonday))
            let expected = (0...(span / 7)).map { CanonicalDay.adding(7 * $0, to: firstMonday) }
            XCTAssertEqual(result.weeks.map { Optional($0.weekStart) }, expected, today)
            XCTAssertTrue(CanonicalDay.isValid(result.evidenceStartDay ?? ""), "evidence start for \(today)")
        }
    }
}
