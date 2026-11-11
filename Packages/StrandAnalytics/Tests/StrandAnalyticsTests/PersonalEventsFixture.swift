// API ASSUMED BY THESE TESTS
//
// Written from docs/personal/superapp/specs/stage-5.md §6 and §13 before any implementation exists.
// This file calls only:
//
//   public enum PersonalEventKind: String, CaseIterable, Sendable {
//       case travel, illness, dietBreak, deload, supplementChange, custom
//   }
//   public struct PersonalEvent: Equatable, Sendable {
//       public let id: String
//       public let kind: PersonalEventKind
//       public let label: String?
//       public let startDay: String
//       public let endDay: String?
//       public let note: String?
//       public let sensitive: Bool
//       public let createdAt: Int
//       public init(id: String, kind: PersonalEventKind, label: String?, startDay: String,
//                   endDay: String?, note: String?, sensitive: Bool, createdAt: Int)
//   }
//   public struct PersonalEventSlot: Equatable, Sendable {
//       public let firstDay: String
//       public let lastDay: String
//       public init(firstDay: String, lastDay: String)
//   }
//
// Nothing here calls `CanonicalDay`: the day arithmetic below is written out so that the expected
// values do not come from the code under test.

import XCTest
@testable import StrandAnalytics

/// The stage 5 events of the one Fixture Person (stage-5.md §13; the person is stage 1 §13's).
/// Every value is invented.
enum PersonalEventsFixture {

    // MARK: Builders

    /// A fixture id: `e1` … `e8` padded to sixteen lowercase hex characters (§13.1).
    static func id(_ n: Int) -> String {
        let head = "e" + String(n, radix: 16)
        return head + String(repeating: "0", count: 16 - head.count)
    }

    /// An event with the fields a test does not care about defaulted.
    static func make(_ id: String, _ kind: PersonalEventKind, _ startDay: String, _ endDay: String?,
                     label: String? = nil, note: String? = nil, sensitive: Bool = false,
                     createdAt: Int = 0) -> PersonalEvent {
        PersonalEvent(id: id, kind: kind, label: label, startDay: startDay, endDay: endDay,
                      note: note, sensitive: sensitive, createdAt: createdAt)
    }

    // MARK: The eight events of §13.1

    static let e1 = make(id(1), .travel, "2031-03-10", "2031-03-16", note: "Fixture trip", createdAt: 1000)
    static let e2 = make(id(2), .deload, "2031-02-03", "2031-02-09", createdAt: 1001)
    static let e3 = make(id(3), .dietBreak, "2031-04-14", "2031-04-27", createdAt: 1002)
    static let e4 = make(id(4), .supplementChange, "2031-01-22", "2031-01-22", createdAt: 1003)
    static let e5 = make(id(5), .illness, "2031-05-19", nil, sensitive: true, createdAt: 1004)
    static let e6 = make(id(6), .custom, "2031-03-26", "2031-03-26", label: "Fixture change",
                         note: "Fixture note", sensitive: true, createdAt: 1005)
    static let e7 = make(id(7), .travel, "2030-12-01", "2030-12-07", createdAt: 1006)
    static let e8 = make(id(8), .travel, "2031-02-22", "2031-02-24", createdAt: 1007)

    /// §13.1 in table order, which is not `normalized` order.
    static let all = [e1, e2, e3, e4, e5, e6, e7, e8]

    /// The same eight in `normalized` order: ascending start day (no two share one).
    static let allNormalized = [e7, e4, e2, e8, e1, e6, e3, e5]

    /// The private text of the fixture: nothing outside the Events screen may print either.
    static let privateNeedles = ["Fixture change", "Fixture note"]

    // MARK: The twenty-two weeks of §13.2

    /// Week n (1-based) starts on 2031-01-06 plus 7 × (n − 1) days. Written out by hand.
    static let weekStarts = [
        "2031-01-06", "2031-01-13", "2031-01-20", "2031-01-27", "2031-02-03", "2031-02-10",
        "2031-02-17", "2031-02-24", "2031-03-03", "2031-03-10", "2031-03-17", "2031-03-24",
        "2031-03-31", "2031-04-07", "2031-04-14", "2031-04-21", "2031-04-28", "2031-05-05",
        "2031-05-12", "2031-05-19", "2031-05-26", "2031-06-02",
    ]

    /// The Sunday that ends each of those weeks. Written out by hand.
    static let weekEnds = [
        "2031-01-12", "2031-01-19", "2031-01-26", "2031-02-02", "2031-02-09", "2031-02-16",
        "2031-02-23", "2031-03-02", "2031-03-09", "2031-03-16", "2031-03-23", "2031-03-30",
        "2031-04-06", "2031-04-13", "2031-04-20", "2031-04-27", "2031-05-04", "2031-05-11",
        "2031-05-18", "2031-05-25", "2031-06-01", "2031-06-08",
    ]

    /// One slot per fixture week.
    static var weekSlots: [PersonalEventSlot] {
        zip(weekStarts, weekEnds).map { PersonalEventSlot(firstDay: $0, lastDay: $1) }
    }

    /// The ids of the events that overlap each week, by 1-based week number (§13.2). A week that is
    /// absent has none. E7 overlaps no week.
    static let idsByWeek: [Int: [String]] = [
        3: [id(4)], 5: [id(2)], 7: [id(8)], 8: [id(8)], 10: [id(1)], 12: [id(6)],
        15: [id(3)], 16: [id(3)], 20: [id(5)], 21: [id(5)], 22: [id(5)],
    ]

    /// `coveredSlots` over the 22 weeks for a set of 1-based week numbers.
    static func covered(weeks: Set<Int>) -> [Bool] {
        (1...22).map { weeks.contains($0) }
    }

    // MARK: Day arithmetic that does not use the code under test

    /// Days since 1970-01-01 of a proleptic Gregorian date (the civil-day algorithm, written out).
    static func dayNumber(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// The canonical key of a day number of `dayNumber`.
    static func key(_ number: Int) -> String {
        let z = number + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let mp = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// The key `offset` days after 2031-01-01 (negative: before).
    static func day(_ offset: Int) -> String {
        key(dayNumber(2031, 1, 1) + offset)
    }

    // MARK: Generated input

    /// SplitMix64, written out, with a seed the caller fixes. Nothing draws from the system, so
    /// every run of a generated test sees the same inputs.
    struct Generator {
        var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        /// A value in `0 ..< bound`; `bound` must be positive.
        mutating func below(_ bound: Int) -> Int {
            Int(next() % UInt64(bound))
        }

        mutating func bool() -> Bool { next() & 1 == 1 }

        mutating func pick<T>(_ items: [T]) -> T { items[below(items.count)] }

        /// The Fisher–Yates shuffle, driven by this generator.
        mutating func shuffled<T>(_ items: [T]) -> [T] {
            var out = items
            guard out.count > 1 else { return out }
            for i in stride(from: out.count - 1, to: 0, by: -1) {
                out.swapAt(i, below(i + 1))
            }
            return out
        }

        /// A valid event whose days lie within `span` days of 2031-01-01, with a unique id built
        /// from `index`. One in five is ongoing; one in five lasts one day.
        mutating func validEvent(index: Int, span: Int = 120) -> PersonalEvent {
            let kind = pick(PersonalEventKind.allCases)
            let start = below(span)
            let end: String?
            switch below(5) {
            case 0: end = nil
            case 1: end = PersonalEventsFixture.day(start)
            default: end = PersonalEventsFixture.day(start + below(30))
            }
            return PersonalEventsFixture.make(
                String(format: "%016x", index), kind, PersonalEventsFixture.day(start), end,
                label: kind == .custom ? "Fixture label \(index)" : nil,
                note: bool() ? "Fixture note \(index)" : nil,
                sensitive: bool(), createdAt: below(5000))
        }

        /// A string that may or may not be a day key: a real key, a near miss, or noise.
        mutating func dayLikeString() -> String {
            switch below(6) {
            case 0:
                return PersonalEventsFixture.day(below(400) - 200)
            case 1, 2:
                // Padded like a key, but the month and day may be out of range.
                return String(format: "%04d-%02d-%02d", below(10_001), below(14), below(33))
            case 3:
                // A real key with one character replaced, removed or added.
                var chars = Array(PersonalEventsFixture.day(below(400) - 200))
                let at = below(chars.count)
                switch below(3) {
                case 0: chars[at] = pick(Array("0123456789-/ .x９"))
                case 1: chars.remove(at: at)
                default: chars.insert(pick(Array("0123456789- ")), at: at)
                }
                return String(chars)
            case 4:
                return pick(["", " ", "ongoing", "2031-3-10", "2031-02-30", "0000-01-01", "2031-03-10 ",
                             " 2031-03-10", "2031/03/10", "20310310", "2031-03-10T00:00:00Z",
                             "２０３１-０３-１０", "2031-03-1\u{0660}", "-031-03-10", "+2031-03-10",
                             "2031-13-01", "2031-00-10", "2031-01-00", "10000-01-01", "\u{0}", "\n"])
            default:
                let alphabet = Array("0123456789--- \n\t\u{0}é🙂")
                return String((0..<below(14)).map { _ in pick(alphabet) })
            }
        }

        /// Free text that may be nil, empty, blank, long, or full of characters a row must not print.
        mutating func textOrNil() -> String? {
            switch below(8) {
            case 0: return nil
            case 1: return ""
            case 2: return " \n\t "
            case 3: return String(repeating: "é", count: below(400))
            case 4: return "Fixture \"quoted\"\nsecond line\ttabbed"
            case 5: return String(repeating: "👨‍👩‍👧‍👦", count: below(60))
            case 6: return "\u{0}\u{1}\u{7F}"
            default: return "Fixture text \(below(1000))"
            }
        }

        /// An event with any field possibly wrong.
        mutating func garbageEvent() -> PersonalEvent {
            PersonalEvent(
                id: pick(["", "a", "b", "c", "00000000000000aa", "\n"]),
                kind: pick(PersonalEventKind.allCases),
                label: textOrNil(),
                startDay: dayLikeString(),
                endDay: below(4) == 0 ? nil : dayLikeString(),
                note: textOrNil(),
                sensitive: bool(),
                createdAt: pick([Int.min, -1, 0, 1, 1_930_000_000, Int.max]))
        }
    }
}
