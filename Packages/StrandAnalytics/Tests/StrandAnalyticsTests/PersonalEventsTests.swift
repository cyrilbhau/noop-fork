// API ASSUMED BY THESE TESTS
//
// Written from docs/personal/superapp/specs/stage-5.md §6, §7.1 to §7.5, §12.1, §12.6 and §13
// before any implementation exists. Every function is assumed total: no throw, no trap.
//
//   public enum PersonalEventKind: String, CaseIterable, Sendable {
//       case travel, illness, dietBreak, deload, supplementChange, custom   // in this order
//   }
//   public struct PersonalEvent: Equatable, Sendable {
//       public let id: String, kind: PersonalEventKind, label: String?, startDay: String,
//                  endDay: String?, note: String?, sensitive: Bool, createdAt: Int
//       public init(id: String, kind: PersonalEventKind, label: String?, startDay: String,
//                   endDay: String?, note: String?, sensitive: Bool, createdAt: Int)
//   }
//   public enum PersonalEventIssue: Equatable, Sendable {
//       case emptyId, invalidStartDay, invalidEndDay, endBeforeStart
//       case missingLabel, unexpectedLabel, labelTooLong, emptyNote, noteTooLong
//   }
//   public enum PersonalEventWeekRelation: Equatable, Sendable {
//       case before, after, within, startsWithin, endsWithin, covers
//   }
//   public struct PersonalEventSlot: Equatable, Sendable {
//       public let firstDay: String, lastDay: String
//       public init(firstDay: String, lastDay: String)
//   }
//   public enum PersonalEvents {
//       public static let maxLabelLength: Int   // 40
//       public static let maxNoteLength: Int    // 280
//       public static func defaultSensitive(_ kind: PersonalEventKind) -> Bool
//       public static func issues(_ event: PersonalEvent) -> [PersonalEventIssue]
//       public static func normalized(_ events: [PersonalEvent]) -> [PersonalEvent]
//       public static func relation(of event: PersonalEvent, firstDay: String, lastDay: String)
//           -> PersonalEventWeekRelation?
//       public static func overlaps(_ event: PersonalEvent, firstDay: String, lastDay: String) -> Bool
//       public static func events(overlapping firstDay: String, _ lastDay: String,
//                                 in events: [PersonalEvent]) -> [PersonalEvent]
//       public static func events(overlappingWeekStarting weekStart: String,
//                                 in events: [PersonalEvent]) -> [PersonalEvent]
//       public static func coveredSlots(events: [PersonalEvent], slots: [PersonalEventSlot]) -> [Bool]
//       public static func visible(_ events: [PersonalEvent], includeSensitive: Bool) -> [PersonalEvent]
//   }
//
// Shared scaffolding (stage 6 §6.0), treated as given:
//
//   public enum CanonicalDay {
//       public static func number(_ key: String) -> Int?   // nil unless a canonical "yyyy-MM-dd" key
//       public static func key(_ number: Int) -> String    // inverse of `number` for a valid day
//   }
//
// `packetLines` and its two constants are tested in PersonalEventsPacketTests.swift, which also
// needs stage 2's `CoachPacket.sanitize`.

import XCTest
@testable import StrandAnalytics

private typealias F = PersonalEventsFixture

/// `PersonalEvents`: validation, normalisation, overlap with a range and a week, chart slots and the
/// one function that applies the private flag (stage-5.md §7.1 to §7.5, test plan §12.1).
///
/// The storage encoding is not a pure function in the specification: `PersonalEventStore` (app
/// target, §9.2) owns the only encode and decode, so its byte-stability tests live with the store
/// (§12.3). What the encoding relies on here, one order for equal lists, is asserted below.
final class PersonalEventsTests: XCTestCase {

    // The one week most overlap cases use: fixture week 10, Monday to Sunday.
    private let monday = "2031-03-10"
    private let sunday = "2031-03-16"

    private func relation(_ start: String, _ end: String?) -> PersonalEventWeekRelation? {
        PersonalEvents.relation(of: F.make("a", .travel, start, end), firstDay: monday, lastDay: sunday)
    }

    private func overlaps(_ start: String, _ end: String?) -> Bool {
        PersonalEvents.overlaps(F.make("a", .travel, start, end), firstDay: monday, lastDay: sunday)
    }

    private func inWeek(_ start: String, _ end: String?) -> Bool {
        let event = F.make("a", .travel, start, end)
        return PersonalEvents.events(overlappingWeekStarting: monday, in: [event]) == [event]
    }

    /// Every case of the overlap section against the week, with the relation §7.4 gives it.
    private static let weekCases: [(start: String, end: String?, expected: PersonalEventWeekRelation)] = [
        ("2031-03-01", "2031-03-09", .before),
        ("2031-03-09", "2031-03-09", .before),
        ("2031-03-17", "2031-03-20", .after),
        ("2031-03-17", "2031-03-17", .after),
        ("2031-03-17", nil, .after),
        ("2031-03-11", "2031-03-15", .within),
        ("2031-03-10", "2031-03-16", .within),
        ("2031-03-10", "2031-03-10", .within),
        ("2031-03-13", "2031-03-13", .within),
        ("2031-03-16", "2031-03-16", .within),
        ("2031-03-09", "2031-03-17", .covers),
        ("2030-01-01", "2032-01-01", .covers),
        ("2031-03-09", nil, .covers),
        ("2030-01-01", nil, .covers),
        ("2031-03-12", "2031-03-20", .startsWithin),
        ("2031-03-10", "2031-03-17", .startsWithin),
        ("2031-03-16", "2031-03-17", .startsWithin),
        ("2031-03-10", nil, .startsWithin),
        ("2031-03-16", nil, .startsWithin),
        ("2031-03-05", "2031-03-12", .endsWithin),
        ("2031-03-09", "2031-03-10", .endsWithin),
        ("2031-03-09", "2031-03-16", .endsWithin),
    ]

    private func sortKeyAscending(_ a: PersonalEvent, _ b: PersonalEvent) -> Bool {
        if a.startDay != b.startDay { return a.startDay < b.startDay }
        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
        return a.id < b.id
    }

    private func isInNormalizedOrder(_ events: [PersonalEvent]) -> Bool {
        zip(events, events.dropFirst()).allSatisfy { sortKeyAscending($0, $1) }
    }

    // MARK: - Validation (§7.3)

    func testCanonicalDaysPassAndUnpaddedOrImpossibleDaysAreInvalidStartOrEndDays() {
        XCTAssertEqual(PersonalEvents.issues(F.make("a", .travel, "2031-03-10", nil)), [])
        XCTAssertEqual(PersonalEvents.issues(F.make("a", .travel, "2031-03-10", "2031-03-10")), [])
        // The ends of the valid year range, a leap day, and a planned (future) start (§7.1).
        for day in ["0001-01-01", "9999-12-31", "2032-02-29", "2000-02-29", "2099-07-04"] {
            XCTAssertEqual(PersonalEvents.issues(F.make("a", .travel, day, day)), [], day)
        }
        let invalid = ["2031-3-10", "2031-02-30", "0000-01-01", "",
                       "2031-02-29", "1900-02-29", "2031-13-01", "2031-00-10", "2031-01-00",
                       "2031-04-31", "10000-01-01", "2031-03-10 ", " 2031-03-10", "2031/03/10",
                       "20310310", "ongoing"]
        for day in invalid {
            XCTAssertEqual(PersonalEvents.issues(F.make("a", .travel, day, nil)), [.invalidStartDay],
                           "start \(day.debugDescription)")
            XCTAssertEqual(PersonalEvents.issues(F.make("a", .travel, "2031-03-10", day)), [.invalidEndDay],
                           "end \(day.debugDescription)")
            // Both wrong: both named, and no end-before-start, which needs two valid days.
            XCTAssertEqual(PersonalEvents.issues(F.make("a", .travel, day, day)),
                           [.invalidStartDay, .invalidEndDay], "both \(day.debugDescription)")
        }
    }

    func testDayValidityAgreesWithCanonicalDayForGeneratedStrings() {
        var generator = F.Generator(seed: 0x5EED_0501)
        var validSeen = 0
        var invalidSeen = 0
        for _ in 0..<500 {
            let text = generator.dayLikeString()
            let expectedInvalid = CanonicalDay.number(text) == nil
            if expectedInvalid { invalidSeen += 1 } else { validSeen += 1 }
            let asStart = PersonalEvents.issues(F.make("a", .travel, text, nil))
            XCTAssertEqual(asStart.contains(.invalidStartDay), expectedInvalid, text.debugDescription)
            XCTAssertEqual(asStart, expectedInvalid ? [.invalidStartDay] : [], text.debugDescription)
            let asEnd = PersonalEvents.issues(F.make("a", .travel, "0001-01-01", text))
            XCTAssertEqual(asEnd, expectedInvalid ? [.invalidEndDay] : [], text.debugDescription)
        }
        // The generator must exercise both outcomes, or the agreement above proves nothing.
        XCTAssertGreaterThan(validSeen, 50)
        XCTAssertGreaterThan(invalidSeen, 50)
    }

    func testEndBeforeStartIsAnIssue() {
        // The day before the start, the start itself, and the day after.
        XCTAssertEqual(PersonalEvents.issues(F.make("a", .travel, "2031-03-10", "2031-03-09")), [.endBeforeStart])
        XCTAssertEqual(PersonalEvents.issues(F.make("a", .travel, "2031-03-10", "2031-03-10")), [])
        XCTAssertEqual(PersonalEvents.issues(F.make("a", .travel, "2031-03-10", "2031-03-11")), [])
        // Across a month and a year boundary, where a comparison of day-of-month alone would be wrong.
        XCTAssertEqual(PersonalEvents.issues(F.make("a", .travel, "2031-03-01", "2031-02-28")), [.endBeforeStart])
        XCTAssertEqual(PersonalEvents.issues(F.make("a", .travel, "2031-02-28", "2031-03-01")), [])
        XCTAssertEqual(PersonalEvents.issues(F.make("a", .travel, "2031-01-01", "2030-12-31")), [.endBeforeStart])
        XCTAssertEqual(PersonalEvents.issues(F.make("a", .travel, "2030-12-31", "2031-01-01")), [])
        // Fixture variant V3: E1 ending the day before it starts.
        XCTAssertEqual(PersonalEvents.issues(F.make(F.id(1), .travel, "2031-03-10", "2031-03-09",
                                                    note: "Fixture trip", createdAt: 1000)),
                       [.endBeforeStart])
        // An ongoing event has no end to be before anything.
        XCTAssertEqual(PersonalEvents.issues(F.make("a", .travel, "9999-12-31", nil)), [])
    }

    func testCustomKindNeedsALabelAndOtherKindsRejectOne() {
        XCTAssertEqual(PersonalEvents.issues(F.make("a", .custom, "2031-03-10", nil, label: nil)), [.missingLabel])
        XCTAssertEqual(PersonalEvents.issues(F.make("a", .custom, "2031-03-10", nil, label: "")), [.missingLabel])
        XCTAssertEqual(PersonalEvents.issues(F.make("a", .custom, "2031-03-10", nil, label: "Fixture change")), [])
        XCTAssertEqual(PersonalEvents.issues(F.make("a", .custom, "2031-03-10", nil, label: "x")), [])
        for kind in PersonalEventKind.allCases where kind != .custom {
            XCTAssertEqual(PersonalEvents.issues(F.make("a", kind, "2031-03-10", nil, label: nil)), [],
                           kind.rawValue)
            XCTAssertEqual(PersonalEvents.issues(F.make("a", kind, "2031-03-10", nil, label: "Fixture change")),
                           [.unexpectedLabel], kind.rawValue)
            // "Any other kind with a non-nil label": an empty label is still a label.
            XCTAssertEqual(PersonalEvents.issues(F.make("a", kind, "2031-03-10", nil, label: "")),
                           [.unexpectedLabel], kind.rawValue)
        }
    }

    func testLabelAndNoteLengthsAreCountedInCharacters() {
        XCTAssertEqual(PersonalEvents.maxLabelLength, 40)
        XCTAssertEqual(PersonalEvents.maxNoteLength, 280)

        // One Character, seven Unicode scalars, twenty-five UTF-8 bytes.
        let family = "👨‍👩‍👧‍👦"
        XCTAssertEqual(family.count, 1)
        func custom(_ label: String) -> PersonalEvent { F.make("a", .custom, "2031-03-10", nil, label: label) }
        XCTAssertEqual(PersonalEvents.issues(custom(String(repeating: family, count: 39))), [])
        XCTAssertEqual(PersonalEvents.issues(custom(String(repeating: family, count: 40))), [])
        XCTAssertEqual(PersonalEvents.issues(custom(String(repeating: family, count: 41))), [.labelTooLong])
        XCTAssertEqual(PersonalEvents.issues(custom(String(repeating: "a", count: 40))), [])
        XCTAssertEqual(PersonalEvents.issues(custom(String(repeating: "a", count: 41))), [.labelTooLong])

        // One Character, two scalars: "e" and a combining acute accent.
        let accented = "e\u{301}"
        XCTAssertEqual(accented.count, 1)
        func noted(_ note: String) -> PersonalEvent { F.make("a", .travel, "2031-03-10", nil, note: note) }
        XCTAssertEqual(PersonalEvents.issues(noted(String(repeating: accented, count: 279))), [])
        XCTAssertEqual(PersonalEvents.issues(noted(String(repeating: accented, count: 280))), [])
        XCTAssertEqual(PersonalEvents.issues(noted(String(repeating: accented, count: 281))), [.noteTooLong])
        XCTAssertEqual(PersonalEvents.issues(noted(String(repeating: "a", count: 280))), [])
        XCTAssertEqual(PersonalEvents.issues(noted(String(repeating: "a", count: 281))), [.noteTooLong])
        XCTAssertEqual(PersonalEvents.issues(noted("x")), [])
    }

    func testWhitespaceOnlyLabelIsMissing() {
        for blank in [" ", "   ", "\n", "\t", " \n\t\r\n ", "\u{00A0}", "\u{3000} "] {
            XCTAssertEqual(PersonalEvents.issues(F.make("a", .custom, "2031-03-10", nil, label: blank)),
                           [.missingLabel], blank.debugDescription)
        }
        // Padding around real words is not "missing".
        XCTAssertEqual(PersonalEvents.issues(F.make("a", .custom, "2031-03-10", nil, label: "  Fixture change\n")), [])
    }

    func testEmptyOrWhitespaceOnlyNoteIsAnIssueAndAnAbsentNoteIsNot() {
        XCTAssertEqual(PersonalEvents.issues(F.make("a", .travel, "2031-03-10", nil, note: nil)), [])
        for blank in ["", " ", "\n", " \t\r\n ", "\u{00A0}"] {
            XCTAssertEqual(PersonalEvents.issues(F.make("a", .travel, "2031-03-10", nil, note: blank)),
                           [.emptyNote], blank.debugDescription)
        }
        XCTAssertEqual(PersonalEvents.issues(F.make("a", .travel, "2031-03-10", nil, note: " Fixture trip ")), [])
    }

    func testEmptyIdIsAnIssueAndAnyNonEmptyIdIsNot() {
        XCTAssertEqual(PersonalEvents.issues(F.make("", .travel, "2031-03-10", nil)), [.emptyId])
        // "Non-empty" is the whole rule here; sixteen hex characters is what the store issues.
        XCTAssertEqual(PersonalEvents.issues(F.make("a", .travel, "2031-03-10", nil)), [])
        XCTAssertEqual(PersonalEvents.issues(F.make(F.id(1), .travel, "2031-03-10", nil)), [])
    }

    func testIssuesAreReportedInDeclarationOrder() {
        let everythingWrong = PersonalEvent(id: "", kind: .custom, label: nil, startDay: "2031-3-10",
                                            endDay: "2031-02-30", note: "", sensitive: false, createdAt: 0)
        XCTAssertEqual(PersonalEvents.issues(everythingWrong),
                       [.emptyId, .invalidStartDay, .invalidEndDay, .missingLabel, .emptyNote])

        let tooLong = PersonalEvent(id: "", kind: .custom, label: String(repeating: "a", count: 41),
                                    startDay: "2031-03-10", endDay: "2031-03-09",
                                    note: String(repeating: "b", count: 281), sensitive: true, createdAt: 0)
        XCTAssertEqual(PersonalEvents.issues(tooLong),
                       [.emptyId, .endBeforeStart, .labelTooLong, .noteTooLong])

        // Feeding the fields in a different order of "wrongness" must not change the order reported.
        let lateOnly = PersonalEvent(id: "a", kind: .travel, label: nil, startDay: "2031-03-10",
                                     endDay: "bad", note: " ", sensitive: false, createdAt: 0)
        XCTAssertEqual(PersonalEvents.issues(lateOnly), [.invalidEndDay, .emptyNote])
    }

    func testAnOverlongLabelOnAKindThatTakesNoLabelIsBothUnexpectedAndTooLong() {
        // SPEC-AMBIGUITY: §7.3 gives `labelTooLong` no kind restriction ("more than 40 Characters"),
        // and `issues` "returns every applicable issue", so a 41-character label on a travel event
        // is read as both unexpected and too long, in declaration order.
        let event = F.make("a", .travel, "2031-03-10", "2031-03-09", label: String(repeating: "a", count: 41))
        XCTAssertEqual(PersonalEvents.issues(event), [.endBeforeStart, .unexpectedLabel, .labelTooLong])
    }

    func testABlankNoteOverTheLimitIsBothEmptyAndTooLong() {
        // SPEC-AMBIGUITY: §7.3 does not say whether `noteTooLong` counts the note as given or after
        // trimming. `issues` does not trim what it is given (the store trims before it validates,
        // §9.3), so the length is read as the length of the stored value: 281 spaces are both an
        // empty note and a too-long one, in declaration order (`emptyNote` is declared first).
        let event = F.make("a", .travel, "2031-03-10", nil, note: String(repeating: " ", count: 281))
        XCTAssertEqual(PersonalEvents.issues(event), [.emptyNote, .noteTooLong])
        let label = F.make("a", .custom, "2031-03-10", nil, label: String(repeating: " ", count: 41))
        XCTAssertEqual(PersonalEvents.issues(label), [.missingLabel, .labelTooLong])
    }

    func testDefaultSensitiveIsTrueOnlyForIllnessAndCustom() {
        XCTAssertFalse(PersonalEvents.defaultSensitive(.travel))
        XCTAssertTrue(PersonalEvents.defaultSensitive(.illness))
        XCTAssertFalse(PersonalEvents.defaultSensitive(.dietBreak))
        XCTAssertFalse(PersonalEvents.defaultSensitive(.deload))
        XCTAssertFalse(PersonalEvents.defaultSensitive(.supplementChange))
        XCTAssertTrue(PersonalEvents.defaultSensitive(.custom))
        XCTAssertEqual(PersonalEventKind.allCases.filter(PersonalEvents.defaultSensitive), [.illness, .custom])
    }

    func testKindRawValuesAreTheStoredAndPrintedSpellings() {
        // §7.2: the raw value is what the store writes and what the packet prints.
        XCTAssertEqual(PersonalEventKind.allCases.map(\.rawValue),
                       ["travel", "illness", "dietBreak", "deload", "supplementChange", "custom"])
        XCTAssertNil(PersonalEventKind(rawValue: "somethingNew"))
        XCTAssertNil(PersonalEventKind(rawValue: "Travel"))
    }

    func testTheSensitiveFlagIsTheOwnersChoiceAndNeverAnIssue() {
        // The default only presets the editor's switch (§7.2): any flag is valid on any kind.
        for kind in PersonalEventKind.allCases {
            for sensitive in [false, true] {
                let event = F.make("a", kind, "2031-03-10", nil, label: kind == .custom ? "Fixture change" : nil,
                                   sensitive: sensitive)
                XCTAssertEqual(PersonalEvents.issues(event), [], "\(kind.rawValue) \(sensitive)")
            }
        }
    }

    func testEveryFixtureEventIsValid() {
        for event in F.all {
            XCTAssertEqual(PersonalEvents.issues(event), [], event.id)
        }
    }

    // MARK: - Normalisation (§7.3)

    func testNormalizedDropsInvalidEvents() {
        // Fixture variant V3: E1 with an end day before its start.
        let broken = F.make(F.id(1), .travel, "2031-03-10", "2031-03-09", note: "Fixture trip", createdAt: 1000)
        XCTAssertEqual(PersonalEvents.normalized([broken]), [])
        XCTAssertEqual(PersonalEvents.normalized([F.e2, broken, F.e4]), [F.e4, F.e2])

        let invalid = [
            F.make("", .travel, "2031-03-10", nil),
            F.make("b", .travel, "2031-3-10", nil),
            F.make("c", .travel, "2031-03-10", "2031-02-30"),
            F.make("d", .custom, "2031-03-10", nil),
            F.make("e", .deload, "2031-03-10", nil, label: "Fixture change"),
            F.make("f", .travel, "2031-03-10", nil, note: " "),
            F.make("g", .travel, "2031-03-10", nil, note: String(repeating: "a", count: 281)),
            F.make("h", .custom, "2031-03-10", nil, label: String(repeating: "a", count: 41)),
        ]
        XCTAssertEqual(PersonalEvents.normalized(invalid), [])
        XCTAssertEqual(PersonalEvents.normalized(invalid + F.all + invalid), F.allNormalized)
        XCTAssertEqual(PersonalEvents.normalized([]), [])
    }

    func testNormalizedKeepsTheLastOfADuplicatedId() {
        // Fixture variant V4: a second event with E1's id and a different start.
        let later = F.make(F.id(1), .travel, "2031-03-20", "2031-03-21", createdAt: 1000)
        XCTAssertEqual(PersonalEvents.normalized([F.e1, later]), [later])
        XCTAssertEqual(PersonalEvents.normalized([later, F.e1]), [F.e1])
        // Three of one id, with other events between: only the last survives, in sorted position.
        let middle = F.make(F.id(1), .deload, "2031-01-01", nil, createdAt: 5)
        XCTAssertEqual(PersonalEvents.normalized([F.e1, F.e2, middle, F.e8, later]), [F.e2, F.e8, later])
        // An exact repeat collapses to one.
        XCTAssertEqual(PersonalEvents.normalized([F.e1, F.e1, F.e1]), [F.e1])
    }

    func testNormalizedKeepsAValidEventWhenALaterDuplicateOfItsIdIsInvalid() {
        // SPEC-AMBIGUITY: §7.3 lists the steps as "keeps events with no issues, removes duplicates
        // by id (the last occurrence wins), and sorts". Read in that order, an invalid event is
        // gone before duplicates are resolved, so it cannot displace a valid event of the same id.
        // The other order would drop a valid entry because of a broken one, which is the reading
        // least in keeping with "nothing the owner entered is hidden".
        let broken = F.make(F.id(1), .travel, "2031-03-10", "2031-03-09", createdAt: 1000)
        XCTAssertEqual(PersonalEvents.normalized([F.e1, broken]), [F.e1])
        XCTAssertEqual(PersonalEvents.normalized([broken, F.e1]), [F.e1])
    }

    func testNormalizedOrdersByStartThenCreatedAtThenId() {
        let a = F.make("0000000000000003", .travel, "2031-03-10", nil, createdAt: 50)
        let b = F.make("0000000000000002", .deload, "2031-03-10", "2031-03-12", createdAt: 60)
        let c = F.make("0000000000000001", .travel, "2031-03-10", "2031-03-11", createdAt: 60)
        let d = F.make("0000000000000009", .travel, "2031-03-09", "2031-12-31", createdAt: 999)
        let e = F.make("0000000000000000", .travel, "2031-03-11", "2031-03-11", createdAt: -5)
        // d: earliest start, although its createdAt and id are the largest.
        // a: same start as b and c, smaller createdAt. c before b: same start and createdAt, smaller id.
        // e: latest start, although its createdAt and id are the smallest.
        let expected = [d, a, c, b, e]
        XCTAssertEqual(PersonalEvents.normalized([a, b, c, d, e]), expected)
        XCTAssertEqual(PersonalEvents.normalized([e, d, c, b, a]), expected)
        XCTAssertEqual(PersonalEvents.normalized([b, e, a, d, c]), expected)
        // The end day and the kind play no part in the order.
        XCTAssertEqual(PersonalEvents.normalized(F.all), F.allNormalized)
    }

    func testNormalizedComparesCreatedAtAsANumber() {
        // 9 < 10 as numbers; as text "10" < "9".
        let nine = F.make("b", .travel, "2031-03-10", nil, createdAt: 9)
        let ten = F.make("a", .travel, "2031-03-10", nil, createdAt: 10)
        let negative = F.make("c", .travel, "2031-03-10", nil, createdAt: -1)
        XCTAssertEqual(PersonalEvents.normalized([ten, nine, negative]), [negative, nine, ten])
    }

    func testNormalizedIsIdempotentAndIndependentOfInputOrder() {
        // Equal lists must give one order, whatever order they arrive in: this is what lets the
        // store write equal lists as equal bytes (§9.2).
        var generator = F.Generator(seed: 0x5EED_0502)
        for round in 0..<60 {
            let events = (0..<(1 + generator.below(12))).map { generator.validEvent(index: $0) }
            let once = PersonalEvents.normalized(events)
            XCTAssertEqual(once.count, events.count, "round \(round)")
            XCTAssertTrue(isInNormalizedOrder(once), "round \(round)")
            XCTAssertEqual(PersonalEvents.normalized(once), once, "round \(round)")
            for _ in 0..<4 {
                XCTAssertEqual(PersonalEvents.normalized(generator.shuffled(events)), once, "round \(round)")
            }
        }
    }

    // MARK: - Overlap against the week [2031-03-10, 2031-03-16] (§7.4)

    func testEventEndingTheDayBeforeTheWeekIsBefore() {
        XCTAssertEqual(relation("2031-03-01", "2031-03-09"), .before)
        XCTAssertFalse(overlaps("2031-03-01", "2031-03-09"))
        XCTAssertFalse(inWeek("2031-03-01", "2031-03-09"))
        // One day later it reaches the Monday and is no longer before.
        XCTAssertEqual(relation("2031-03-01", "2031-03-10"), .endsWithin)
    }

    func testEventStartingTheDayAfterTheWeekIsAfter() {
        XCTAssertEqual(relation("2031-03-17", "2031-03-20"), .after)
        XCTAssertFalse(overlaps("2031-03-17", "2031-03-20"))
        // The week has seven days, not eight: the next Monday is outside it.
        XCTAssertFalse(inWeek("2031-03-17", "2031-03-20"))
        XCTAssertFalse(inWeek("2031-03-17", "2031-03-17"))
        // One day earlier it starts on the Sunday and is no longer after.
        XCTAssertEqual(relation("2031-03-16", "2031-03-20"), .startsWithin)
    }

    func testEventInsideTheWeekIsWithin() {
        XCTAssertEqual(relation("2031-03-11", "2031-03-15"), .within)
        XCTAssertTrue(overlaps("2031-03-11", "2031-03-15"))
        XCTAssertTrue(inWeek("2031-03-11", "2031-03-15"))
    }

    func testEventOnExactlyTheWeekIsWithin() {
        XCTAssertEqual(relation(monday, sunday), .within)
        XCTAssertTrue(overlaps(monday, sunday))
        XCTAssertTrue(inWeek(monday, sunday))
        // The fixture's own case: E1 is exactly week 10 and E2 exactly week 5.
        XCTAssertEqual(PersonalEvents.relation(of: F.e1, firstDay: monday, lastDay: sunday), .within)
        XCTAssertEqual(PersonalEvents.relation(of: F.e2, firstDay: "2031-02-03", lastDay: "2031-02-09"), .within)
    }

    func testEventSpanningTheWeekCovers() {
        XCTAssertEqual(relation("2031-03-09", "2031-03-17"), .covers)
        XCTAssertEqual(relation("2030-01-01", "2032-01-01"), .covers)
        XCTAssertTrue(overlaps("2031-03-09", "2031-03-17"))
        XCTAssertTrue(inWeek("2031-03-09", "2031-03-17"))
        // Pulling either end in by one day stops it covering: it must start before the first day
        // and end after the last.
        XCTAssertEqual(relation("2031-03-10", "2031-03-17"), .startsWithin)
        XCTAssertEqual(relation("2031-03-09", "2031-03-16"), .endsWithin)
    }

    func testEventStartingInTheWeekAndEndingAfterStartsWithin() {
        XCTAssertEqual(relation("2031-03-12", "2031-03-20"), .startsWithin)
        XCTAssertEqual(relation("2031-03-10", "2031-03-17"), .startsWithin)
        XCTAssertEqual(relation("2031-03-16", "2031-03-17"), .startsWithin)
        XCTAssertTrue(overlaps("2031-03-12", "2031-03-20"))
        // Ending on the Sunday instead, it is wholly inside.
        XCTAssertEqual(relation("2031-03-12", "2031-03-16"), .within)
    }

    func testEventStartingBeforeAndEndingInTheWeekEndsWithin() {
        XCTAssertEqual(relation("2031-03-05", "2031-03-12"), .endsWithin)
        XCTAssertEqual(relation("2031-03-09", "2031-03-10"), .endsWithin)
        XCTAssertEqual(relation("2031-03-09", "2031-03-16"), .endsWithin)
        XCTAssertTrue(overlaps("2031-03-05", "2031-03-12"))
        // Starting on the Monday instead, it is wholly inside.
        XCTAssertEqual(relation("2031-03-10", "2031-03-12"), .within)
    }

    func testEventEndingOnTheMondayOverlaps() {
        // The lower bound is inclusive: an event whose last day is the range's first day overlaps.
        XCTAssertTrue(overlaps("2031-03-05", monday))
        XCTAssertEqual(relation("2031-03-05", monday), .endsWithin)
        XCTAssertTrue(inWeek("2031-03-05", monday))
        let event = F.make("a", .travel, "2031-03-05", monday)
        XCTAssertEqual(PersonalEvents.events(overlapping: monday, sunday, in: [event]), [event])
        XCTAssertEqual(PersonalEvents.coveredSlots(events: [event],
                                                   slots: [PersonalEventSlot(firstDay: monday, lastDay: sunday)]),
                       [true])
        // One day short of the Monday it does not.
        XCTAssertFalse(overlaps("2031-03-05", "2031-03-09"))
        XCTAssertEqual(relation("2031-03-05", "2031-03-09"), .before)
    }

    func testEventStartingOnTheSundayOverlaps() {
        // The upper bound is inclusive: an event whose first day is the range's last day overlaps.
        XCTAssertTrue(overlaps(sunday, "2031-03-20"))
        XCTAssertEqual(relation(sunday, "2031-03-20"), .startsWithin)
        XCTAssertTrue(inWeek(sunday, "2031-03-20"))
        let event = F.make("a", .travel, sunday, "2031-03-20")
        XCTAssertEqual(PersonalEvents.events(overlapping: monday, sunday, in: [event]), [event])
        XCTAssertEqual(PersonalEvents.coveredSlots(events: [event],
                                                   slots: [PersonalEventSlot(firstDay: monday, lastDay: sunday)]),
                       [true])
        // One day past the Sunday it does not.
        XCTAssertFalse(overlaps("2031-03-17", "2031-03-20"))
        XCTAssertEqual(relation("2031-03-17", "2031-03-20"), .after)
    }

    func testOngoingEventStartedBeforeTheWeekCovers() {
        // An ongoing event has no end: it is not an event that ended on its start day.
        XCTAssertEqual(relation("2031-03-09", nil), .covers)
        XCTAssertEqual(relation("2030-01-01", nil), .covers)
        XCTAssertEqual(relation("0001-01-01", nil), .covers)
        XCTAssertTrue(overlaps("2030-01-01", nil))
        XCTAssertTrue(inWeek("2030-01-01", nil))
        let event = F.make("a", .travel, "2030-01-01", nil)
        XCTAssertEqual(PersonalEvents.events(overlapping: monday, sunday, in: [event]), [event])
        XCTAssertEqual(PersonalEvents.coveredSlots(events: [event],
                                                   slots: [PersonalEventSlot(firstDay: monday, lastDay: sunday)]),
                       [true])
    }

    func testOngoingEventStartedInTheWeekStartsWithin() {
        XCTAssertEqual(relation(monday, nil), .startsWithin)
        XCTAssertEqual(relation("2031-03-13", nil), .startsWithin)
        XCTAssertEqual(relation(sunday, nil), .startsWithin)
        XCTAssertTrue(overlaps(sunday, nil))
        XCTAssertTrue(inWeek(sunday, nil))
    }

    func testOngoingEventStartingAfterTheWeekIsAfter() {
        XCTAssertEqual(relation("2031-03-17", nil), .after)
        XCTAssertEqual(relation("9999-12-31", nil), .after)
        XCTAssertFalse(overlaps("2031-03-17", nil))
        XCTAssertFalse(inWeek("2031-03-17", nil))
    }

    func testOneDayEventOnEachDayOfTheWeekIsWithin() {
        let days = ["2031-03-10", "2031-03-11", "2031-03-12", "2031-03-13", "2031-03-14",
                    "2031-03-15", "2031-03-16"]
        for day in days {
            XCTAssertEqual(relation(day, day), .within, day)
            XCTAssertTrue(overlaps(day, day), day)
            // Through the week function, which derives the Sunday itself: a six-day week would
            // lose the last of these.
            XCTAssertTrue(inWeek(day, day), day)
        }
        // And an eight-day week would gain the next Monday.
        XCTAssertFalse(inWeek("2031-03-17", "2031-03-17"))
        XCTAssertEqual(relation("2031-03-17", "2031-03-17"), .after)
    }

    func testOneDayEventOnTheSundayBeforeIsBefore() {
        XCTAssertEqual(relation("2031-03-09", "2031-03-09"), .before)
        XCTAssertFalse(overlaps("2031-03-09", "2031-03-09"))
        XCTAssertFalse(inWeek("2031-03-09", "2031-03-09"))
        // That Sunday belongs to the week before, and to no other.
        let event = F.make("a", .travel, "2031-03-09", "2031-03-09")
        XCTAssertEqual(PersonalEvents.events(overlappingWeekStarting: "2031-03-03", in: [event]), [event])
        XCTAssertEqual(PersonalEvents.events(overlappingWeekStarting: "2031-02-24", in: [event]), [])
    }

    func testWeekStartThatIsNotAMondayReturnsNothing() {
        let everyDay = F.make("a", .travel, "2031-01-01", nil)
        XCTAssertEqual(PersonalEvents.events(overlappingWeekStarting: monday, in: [everyDay]), [everyDay])
        for notMonday in ["2031-03-09", "2031-03-11", "2031-03-12", "2031-03-13", "2031-03-14",
                          "2031-03-15", "2031-03-16"] {
            XCTAssertEqual(PersonalEvents.events(overlappingWeekStarting: notMonday, in: [everyDay]), [],
                           notMonday)
        }
        for invalid in ["", "2031-3-10", "2031-02-30", "0000-01-01", "monday"] {
            XCTAssertEqual(PersonalEvents.events(overlappingWeekStarting: invalid, in: [everyDay]), [],
                           invalid.debugDescription)
        }
    }

    func testInvalidRangeOrInvalidEventNeverOverlaps() {
        let everyDay = F.make("a", .travel, "0001-01-01", nil)
        let badRanges: [(String, String)] = [
            ("2031-3-10", sunday), (monday, "2031-02-30"), ("", ""), ("0000-01-01", sunday),
            (sunday, monday),                    // the last day before the first
            ("2031-03-11", "2031-03-10"),        // by one day
        ]
        for (first, last) in badRanges {
            XCTAssertNil(PersonalEvents.relation(of: everyDay, firstDay: first, lastDay: last), "\(first)..\(last)")
            XCTAssertFalse(PersonalEvents.overlaps(everyDay, firstDay: first, lastDay: last), "\(first)..\(last)")
            XCTAssertEqual(PersonalEvents.events(overlapping: first, last, in: [everyDay]), [], "\(first)..\(last)")
        }
        // A one-day range is valid: the first day may equal the last.
        XCTAssertEqual(PersonalEvents.relation(of: everyDay, firstDay: monday, lastDay: monday), .covers)
        XCTAssertTrue(PersonalEvents.overlaps(everyDay, firstDay: monday, lastDay: monday))

        // An event with any issue is absent from every answer, even where its days would overlap.
        let badEvents = [
            F.make("", .travel, monday, sunday),
            F.make("a", .travel, sunday, monday),
            F.make("a", .travel, "2031-3-12", nil),
            F.make("a", .travel, monday, "2031-03-32"),
            F.make("a", .custom, monday, sunday),
            F.make("a", .travel, monday, sunday, label: "Fixture change"),
            F.make("a", .travel, monday, sunday, note: ""),
            F.make("a", .travel, monday, sunday, note: String(repeating: "a", count: 281)),
        ]
        for event in badEvents {
            XCTAssertFalse(PersonalEvents.issues(event).isEmpty)
            XCTAssertNil(PersonalEvents.relation(of: event, firstDay: monday, lastDay: sunday))
            XCTAssertFalse(PersonalEvents.overlaps(event, firstDay: monday, lastDay: sunday))
            XCTAssertEqual(PersonalEvents.events(overlapping: monday, sunday, in: [event]), [])
            XCTAssertEqual(PersonalEvents.events(overlappingWeekStarting: monday, in: [event]), [])
            XCTAssertEqual(PersonalEvents.coveredSlots(events: [event],
                                                       slots: [PersonalEventSlot(firstDay: monday, lastDay: sunday)]),
                           [false])
        }
    }

    func testRelationAgainstAOneDayRange() {
        func against(_ start: String, _ end: String?) -> PersonalEventWeekRelation? {
            PersonalEvents.relation(of: F.make("a", .travel, start, end),
                                    firstDay: "2031-03-12", lastDay: "2031-03-12")
        }
        XCTAssertEqual(against("2031-03-11", "2031-03-11"), .before)
        XCTAssertEqual(against("2031-03-12", "2031-03-12"), .within)
        XCTAssertEqual(against("2031-03-13", "2031-03-13"), .after)
        XCTAssertEqual(against("2031-03-11", "2031-03-12"), .endsWithin)
        XCTAssertEqual(against("2031-03-12", "2031-03-13"), .startsWithin)
        XCTAssertEqual(against("2031-03-11", "2031-03-13"), .covers)
        XCTAssertEqual(against("2031-03-12", nil), .startsWithin)
        XCTAssertEqual(against("2031-03-11", nil), .covers)
        XCTAssertEqual(against("2031-03-13", nil), .after)
    }

    func testOverlapAcrossAYearBoundaryAndALeapDay() {
        // The week of Monday 2031-12-29 ends on Sunday 2032-01-04.
        let newYear = F.make("a", .travel, "2031-12-31", "2032-01-01")
        XCTAssertEqual(PersonalEvents.relation(of: newYear, firstDay: "2031-12-29", lastDay: "2032-01-04"), .within)
        XCTAssertEqual(PersonalEvents.relation(of: newYear, firstDay: "2032-01-01", lastDay: "2032-01-07"), .endsWithin)
        XCTAssertEqual(PersonalEvents.relation(of: newYear, firstDay: "2031-12-25", lastDay: "2031-12-31"), .startsWithin)
        XCTAssertEqual(PersonalEvents.relation(of: newYear, firstDay: "2032-01-02", lastDay: "2032-01-08"), .before)
        XCTAssertEqual(PersonalEvents.relation(of: newYear, firstDay: "2031-12-24", lastDay: "2031-12-30"), .after)
        func week(_ start: String, has day: String) -> Bool {
            let event = F.make("a", .travel, day, day)
            return PersonalEvents.events(overlappingWeekStarting: start, in: [event]) == [event]
        }
        XCTAssertTrue(week("2031-12-29", has: "2031-12-29"))
        XCTAssertTrue(week("2031-12-29", has: "2032-01-04"))
        XCTAssertFalse(week("2031-12-29", has: "2032-01-05"))
        XCTAssertFalse(week("2031-12-29", has: "2031-12-28"))

        // 2032 is a leap year: the week of Monday 2032-02-23 ends on the leap day.
        XCTAssertTrue(week("2032-02-23", has: "2032-02-29"))
        XCTAssertFalse(week("2032-02-23", has: "2032-03-01"))
        let leap = F.make("a", .travel, "2032-02-28", "2032-03-01")
        XCTAssertEqual(PersonalEvents.relation(of: leap, firstDay: "2032-02-29", lastDay: "2032-02-29"), .covers)
        XCTAssertEqual(PersonalEvents.relation(of: leap, firstDay: "2032-02-23", lastDay: "2032-02-29"), .startsWithin)
        XCTAssertEqual(PersonalEvents.relation(of: leap, firstDay: "2032-03-01", lastDay: "2032-03-07"), .endsWithin)
        // 2031 is not: the week of Monday 2031-02-24 ends on Sunday 2031-03-02.
        XCTAssertTrue(week("2031-02-24", has: "2031-02-28"))
        XCTAssertTrue(week("2031-02-24", has: "2031-03-02"))
        XCTAssertFalse(week("2031-02-24", has: "2031-03-03"))
        // A 29 February that does not exist is not a day at all.
        XCTAssertNil(PersonalEvents.relation(of: F.make("a", .travel, "2031-02-29", nil),
                                             firstDay: "2031-02-24", lastDay: "2031-03-02"))
    }

    func testOverlapsAgreesWithRelationForEveryCaseAbove() {
        for (start, end, expected) in Self.weekCases {
            let name = "\(start)..\(end ?? "ongoing")"
            XCTAssertEqual(relation(start, end), expected, name)
            let shouldOverlap = expected != .before && expected != .after
            XCTAssertEqual(overlaps(start, end), shouldOverlap, name)
            // §7.4's closed form, on the stored strings.
            XCTAssertEqual(overlaps(start, end), start <= sunday && (end == nil || end! >= monday), name)
            XCTAssertEqual(inWeek(start, end), shouldOverlap, name)
            let event = F.make("a", .travel, start, end)
            XCTAssertEqual(PersonalEvents.events(overlapping: monday, sunday, in: [event]),
                           shouldOverlap ? [event] : [], name)
        }
        // Every relation is exercised by the table.
        let seen = Self.weekCases.map(\.expected)
        for relation in [PersonalEventWeekRelation.before, .after, .within, .startsWithin, .endsWithin, .covers] {
            XCTAssertTrue(seen.contains(relation))
        }
    }

    func testEventsOverlappingReturnsNormalizedOrderWhateverTheInputOrder() {
        // The whole fixture span: every event but E7, which ended before it.
        let expected = [F.e4, F.e2, F.e8, F.e1, F.e6, F.e3, F.e5]
        XCTAssertEqual(PersonalEvents.events(overlapping: "2031-01-06", "2031-06-08", in: F.all), expected)
        XCTAssertEqual(PersonalEvents.events(overlapping: "2031-01-06", "2031-06-08", in: F.all.reversed()), expected)
        var generator = F.Generator(seed: 0x5EED_0503)
        for _ in 0..<20 {
            XCTAssertEqual(PersonalEvents.events(overlapping: "2031-01-06", "2031-06-08",
                                                 in: generator.shuffled(F.all)), expected)
        }
        // "Treats its input as if `normalized` had been applied": a superseded duplicate and an
        // invalid event are not returned.
        let superseded = F.make(F.id(1), .travel, "2031-03-01", "2031-03-02", createdAt: 1000)
        let invalid = F.make("z", .travel, "2031-03-10", "2031-03-09")
        XCTAssertEqual(PersonalEvents.events(overlapping: "2031-01-06", "2031-06-08",
                                             in: [superseded, invalid] + F.all), expected)
        XCTAssertEqual(PersonalEvents.events(overlapping: "2031-03-01", "2031-03-02",
                                             in: [superseded, invalid] + F.all), [])
    }

    func testEventsOverlappingEachFixtureWeekMatchTheFixtureTable() {
        XCTAssertEqual(F.weekStarts.count, 22)
        for (index, weekStart) in F.weekStarts.enumerated() {
            let week = index + 1
            let expected = F.idsByWeek[week] ?? []
            XCTAssertEqual(PersonalEvents.events(overlappingWeekStarting: weekStart, in: F.all).map(\.id),
                           expected, "week \(week)")
            XCTAssertEqual(PersonalEvents.events(overlapping: weekStart, F.weekEnds[index], in: F.all).map(\.id),
                           expected, "week \(week)")
        }
        // E7 lies before every week and overlaps none of them.
        for (weekStart, weekEnd) in zip(F.weekStarts, F.weekEnds) {
            XCTAssertEqual(PersonalEvents.relation(of: F.e7, firstDay: weekStart, lastDay: weekEnd), .before)
        }
    }

    func testRelationOfEachFixtureEventToItsWeeksMatchesTheFixtureTable() {
        func relation(_ event: PersonalEvent, week: Int) -> PersonalEventWeekRelation? {
            PersonalEvents.relation(of: event, firstDay: F.weekStarts[week - 1], lastDay: F.weekEnds[week - 1])
        }
        XCTAssertEqual(relation(F.e4, week: 3), .within)        // one day inside a week
        XCTAssertEqual(relation(F.e2, week: 5), .within)        // exactly on a week
        XCTAssertEqual(relation(F.e8, week: 7), .startsWithin)  // starts on the Saturday of week 7
        XCTAssertEqual(relation(F.e8, week: 8), .endsWithin)    // ends on the Monday of week 8
        XCTAssertEqual(relation(F.e1, week: 10), .within)
        XCTAssertEqual(relation(F.e6, week: 12), .within)
        XCTAssertEqual(relation(F.e3, week: 15), .startsWithin)
        XCTAssertEqual(relation(F.e3, week: 16), .endsWithin)
        XCTAssertEqual(relation(F.e5, week: 19), .after)
        XCTAssertEqual(relation(F.e5, week: 20), .startsWithin)
        XCTAssertEqual(relation(F.e5, week: 21), .covers)
        XCTAssertEqual(relation(F.e5, week: 22), .covers)
        XCTAssertEqual(relation(F.e3, week: 14), .after)
        XCTAssertEqual(relation(F.e3, week: 17), .before)
    }

    func testTheFixtureWeekListAgreesWithCanonicalDay() throws {
        // The hand-written week table against the shared day helper: week n starts 7 × (n − 1)
        // days after 2031-01-06, and ends six days later.
        let first = try XCTUnwrap(CanonicalDay.number("2031-01-06"))
        for index in 0..<22 {
            XCTAssertEqual(CanonicalDay.key(first + 7 * index), F.weekStarts[index])
            XCTAssertEqual(CanonicalDay.key(first + 7 * index + 6), F.weekEnds[index])
            XCTAssertEqual(F.day(5 + 7 * index), F.weekStarts[index])
        }
    }

    func testAnEventIsItsStoredDayKeysSoTheSameInstantInAnotherZoneDoesNotMoveIt() throws {
        // The roadmap's time-zone case, restated for whole days (§3 C6, §7.1). The instant
        // 2031-03-16T20:00:00Z is Monday 17 March in Asia/Kolkata and Sunday 16 March in
        // America/Los_Angeles. The editor fixes the key at saving; nothing here takes a zone.
        let instant = Date(timeIntervalSince1970: TimeInterval(F.dayNumber(2031, 3, 16) * 86_400 + 20 * 3600))
        func localKey(_ zone: String) throws -> String {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
            let parts = calendar.dateComponents([.year, .month, .day], from: instant)
            return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        }
        let kolkataKey = try localKey("Asia/Kolkata")
        let losAngelesKey = try localKey("America/Los_Angeles")
        XCTAssertEqual(kolkataKey, "2031-03-17")
        XCTAssertEqual(losAngelesKey, "2031-03-16")

        // Saved in Kolkata, then read on a phone that has since moved to Los Angeles: the event is
        // the same value, so every answer is the same. It stays in week 11 and never joins week 10.
        let saved = F.make("a", .travel, kolkataKey, kolkataKey)
        XCTAssertEqual(saved.startDay, "2031-03-17")
        XCTAssertEqual(PersonalEvents.relation(of: saved, firstDay: monday, lastDay: sunday), .after)
        XCTAssertEqual(PersonalEvents.relation(of: saved, firstDay: "2031-03-17", lastDay: "2031-03-23"), .within)
        XCTAssertEqual(PersonalEvents.events(overlappingWeekStarting: "2031-03-17", in: [saved]), [saved])
        XCTAssertEqual(PersonalEvents.events(overlappingWeekStarting: monday, in: [saved]), [])
        // An event spanning the zone change keeps both of its stored days.
        let trip = F.make("b", .travel, "2031-03-14", kolkataKey)
        XCTAssertEqual(PersonalEvents.relation(of: trip, firstDay: monday, lastDay: sunday), .startsWithin)
        XCTAssertEqual(PersonalEvents.relation(of: trip, firstDay: "2031-03-17", lastDay: "2031-03-23"), .endsWithin)
        XCTAssertEqual(PersonalEvents.normalized([trip, saved]), [trip, saved])
    }

    func testRelationAgreesWithADayNumberOracleForGeneratedEventsAndRanges() {
        // The specification compares key strings; this oracle compares day counts computed by the
        // fixture's own arithmetic. The two must agree for every valid event and range.
        var generator = F.Generator(seed: 0x5EED_0504)
        var seen = Set<String>()
        for round in 0..<1000 {
            let s = generator.below(80)
            let e: Int? = generator.below(5) == 0 ? nil : s + generator.below(20)
            let a = generator.below(80)
            let b = a + generator.below(20)
            let expected: PersonalEventWeekRelation
            if let e, e < a {
                expected = .before
            } else if s > b {
                expected = .after
            } else if s >= a {
                expected = (e != nil && e! <= b) ? .within : .startsWithin
            } else {
                expected = (e != nil && e! <= b) ? .endsWithin : .covers
            }
            seen.insert("\(expected)")
            let event = F.make("a", .travel, F.day(s), e.map(F.day))
            let name = "round \(round): \(event.startDay)..\(event.endDay ?? "ongoing") in \(F.day(a))..\(F.day(b))"
            XCTAssertEqual(PersonalEvents.relation(of: event, firstDay: F.day(a), lastDay: F.day(b)), expected, name)
            XCTAssertEqual(PersonalEvents.overlaps(event, firstDay: F.day(a), lastDay: F.day(b)),
                           expected != .before && expected != .after, name)
        }
        XCTAssertEqual(seen.count, 6, "the generator must reach every relation")
    }

    // MARK: - Slots (§7.4)

    func testCoveredSlotsMarksEachDayOfARange() {
        // E8 runs 22 to 24 February; one slot per day from the 20th to the 26th.
        let days = ["2031-02-20", "2031-02-21", "2031-02-22", "2031-02-23", "2031-02-24",
                    "2031-02-25", "2031-02-26"]
        let slots = days.map { PersonalEventSlot(firstDay: $0, lastDay: $0) }
        XCTAssertEqual(PersonalEvents.coveredSlots(events: F.all, slots: slots),
                       [false, false, true, true, true, false, false])
        // Slots are answered in the order given, not sorted.
        XCTAssertEqual(PersonalEvents.coveredSlots(events: F.all, slots: slots.reversed()),
                       [false, false, true, true, true, false, false])
        XCTAssertEqual(PersonalEvents.coveredSlots(events: F.all, slots: [slots[2], slots[0], slots[2], slots[6]]),
                       [true, false, true, false])
    }

    func testCoveredSlotsOverWeeksMatchesTheFixtureTable() {
        let expected = F.covered(weeks: [3, 5, 7, 8, 10, 12, 15, 16, 20, 21, 22])
        XCTAssertEqual(PersonalEvents.coveredSlots(events: F.all, slots: F.weekSlots), expected)
        XCTAssertEqual(PersonalEvents.coveredSlots(events: F.all.reversed(), slots: F.weekSlots), expected)
        // Variant V5: E5 given an end on the Sunday of week 20. Weeks 21 and 22 lose their mark.
        let ended = F.make(F.id(5), .illness, "2031-05-19", "2031-05-25", sensitive: true, createdAt: 1004)
        let v5 = F.all.map { $0.id == F.id(5) ? ended : $0 }
        XCTAssertEqual(PersonalEvents.coveredSlots(events: v5, slots: F.weekSlots),
                       F.covered(weeks: [3, 5, 7, 8, 10, 12, 15, 16, 20]))
    }

    func testCoveredSlotsCountsSensitiveEvents() {
        // Variant V2: only the two private events. A dot carries no text, so they still mark.
        XCTAssertTrue(F.e5.sensitive && F.e6.sensitive)
        XCTAssertEqual(PersonalEvents.coveredSlots(events: [F.e5, F.e6], slots: F.weekSlots),
                       F.covered(weeks: [12, 20, 21, 22]))
        // Variant V9: a private deload and a private diet break keep their marks.
        let privateDeload = F.make(F.id(2), .deload, "2031-02-03", "2031-02-09", sensitive: true, createdAt: 1001)
        let privateBreak = F.make(F.id(3), .dietBreak, "2031-04-14", "2031-04-27", sensitive: true, createdAt: 1002)
        XCTAssertEqual(PersonalEvents.coveredSlots(events: [privateDeload, privateBreak], slots: F.weekSlots),
                       F.covered(weeks: [5, 15, 16]))
        // Flipping the flag on every fixture event changes no mark.
        let allPrivate = F.all.map {
            PersonalEvent(id: $0.id, kind: $0.kind, label: $0.label, startDay: $0.startDay, endDay: $0.endDay,
                          note: $0.note, sensitive: true, createdAt: $0.createdAt)
        }
        XCTAssertEqual(PersonalEvents.coveredSlots(events: allPrivate, slots: F.weekSlots),
                       PersonalEvents.coveredSlots(events: F.all, slots: F.weekSlots))
    }

    func testCoveredSlotsOfNoEventsIsAllFalseAndOfNoSlotsIsEmpty() {
        XCTAssertEqual(PersonalEvents.coveredSlots(events: [], slots: F.weekSlots),
                       [Bool](repeating: false, count: 22))
        XCTAssertEqual(PersonalEvents.coveredSlots(events: F.all, slots: []), [])
        XCTAssertEqual(PersonalEvents.coveredSlots(events: [], slots: []), [])
        // Only events that overlap nothing shown: still one false per slot.
        XCTAssertEqual(PersonalEvents.coveredSlots(events: [F.e7], slots: F.weekSlots),
                       [Bool](repeating: false, count: 22))
    }

    func testInvalidSlotIsFalse() {
        let everyDay = F.make("a", .travel, "0001-01-01", nil)
        let slots = [
            PersonalEventSlot(firstDay: "2031-03-10", lastDay: "2031-03-16"),
            PersonalEventSlot(firstDay: "2031-3-10", lastDay: "2031-03-16"),    // invalid first day
            PersonalEventSlot(firstDay: "2031-03-10", lastDay: "2031-02-30"),   // invalid last day
            PersonalEventSlot(firstDay: "2031-03-16", lastDay: "2031-03-10"),   // last before first
            PersonalEventSlot(firstDay: "", lastDay: ""),
            PersonalEventSlot(firstDay: "2031-03-11", lastDay: "2031-03-10"),   // last before first by a day
            PersonalEventSlot(firstDay: "2031-03-10", lastDay: "2031-03-10"),   // one day: valid
        ]
        // An invalid slot is false and does not disturb its neighbours' positions.
        XCTAssertEqual(PersonalEvents.coveredSlots(events: [everyDay], slots: slots),
                       [true, false, false, false, false, false, true])
    }

    // MARK: - Visibility (§7.5)

    func testVisibleRemovesSensitiveEventsUnlessIncluded() {
        XCTAssertEqual(PersonalEvents.visible(F.all, includeSensitive: false),
                       [F.e7, F.e4, F.e2, F.e8, F.e1, F.e3])
        XCTAssertEqual(PersonalEvents.visible(F.all, includeSensitive: true), F.allNormalized)
        // Variant V2: only private events.
        XCTAssertEqual(PersonalEvents.visible([F.e5, F.e6], includeSensitive: false), [])
        XCTAssertEqual(PersonalEvents.visible([F.e5, F.e6], includeSensitive: true), [F.e6, F.e5])
        XCTAssertEqual(PersonalEvents.visible([], includeSensitive: false), [])
        XCTAssertEqual(PersonalEvents.visible([], includeSensitive: true), [])
    }

    func testVisibleRemovesAPrivateDeloadAndAPrivateDietBreak() {
        // Variant V9: the flag decides, not the kind. Neither kind is private by default.
        XCTAssertFalse(PersonalEvents.defaultSensitive(.deload))
        XCTAssertFalse(PersonalEvents.defaultSensitive(.dietBreak))
        let privateDeload = F.make(F.id(2), .deload, "2031-02-03", "2031-02-09", sensitive: true, createdAt: 1001)
        let privateBreak = F.make(F.id(3), .dietBreak, "2031-04-14", "2031-04-27", sensitive: true, createdAt: 1002)
        let v9 = F.all.map { event -> PersonalEvent in
            if event.id == F.id(2) { return privateDeload }
            if event.id == F.id(3) { return privateBreak }
            return event
        }
        XCTAssertEqual(PersonalEvents.visible(v9, includeSensitive: false), [F.e7, F.e4, F.e8, F.e1])
        XCTAssertEqual(PersonalEvents.visible([privateDeload, privateBreak], includeSensitive: false), [])
        XCTAssertEqual(PersonalEvents.visible([privateDeload, privateBreak], includeSensitive: true),
                       [privateDeload, privateBreak])
    }

    func testVisibleKeepsAnIllnessOrCustomEventTheOwnerMarkedNotPrivate() {
        // The other direction of "the flag decides": a kind that is private by default is shown
        // when the owner switched the flag off for that event.
        let openIllness = F.make("a", .illness, "2031-05-19", nil, sensitive: false)
        let openCustom = F.make("b", .custom, "2031-03-26", "2031-03-26", label: "Fixture change", sensitive: false)
        XCTAssertEqual(PersonalEvents.visible([openIllness, openCustom], includeSensitive: false),
                       [openCustom, openIllness])
    }

    func testVisibleKeepsNormalizedOrder() {
        XCTAssertEqual(PersonalEvents.visible(F.all.reversed(), includeSensitive: true), F.allNormalized)
        var generator = F.Generator(seed: 0x5EED_0505)
        for _ in 0..<20 {
            let shuffled = generator.shuffled(F.all)
            XCTAssertEqual(PersonalEvents.visible(shuffled, includeSensitive: true), F.allNormalized)
            XCTAssertEqual(PersonalEvents.visible(shuffled, includeSensitive: false),
                           [F.e7, F.e4, F.e2, F.e8, F.e1, F.e3])
        }
        // It is `normalized` first: an invalid event and a superseded duplicate are not visible.
        let invalid = F.make("z", .travel, "2031-03-10", "2031-03-09")
        let superseded = F.make(F.id(1), .travel, "2031-03-01", "2031-03-02", createdAt: 1000)
        XCTAssertEqual(PersonalEvents.visible([superseded, invalid] + F.all, includeSensitive: true), F.allNormalized)
        // A private last occurrence replaces a visible earlier one of the same id, and is hidden.
        let nowPrivate = F.make(F.id(1), .travel, "2031-03-10", "2031-03-16", sensitive: true, createdAt: 1000)
        XCTAssertEqual(PersonalEvents.visible([F.e1, nowPrivate], includeSensitive: false), [])
    }

    // MARK: - Properties

    func testAddingAnEventOutsideARangeNeverChangesThatRangesResult() {
        var generator = F.Generator(seed: 0x5EED_0506)
        for round in 0..<200 {
            let events = (0..<generator.below(10)).map { generator.validEvent(index: $0) }
            let a = generator.below(150)
            let b = a + generator.below(30)
            let first = F.day(a)
            let last = F.day(b)
            // An event wholly before the range (it ends the day before, or earlier) or wholly after
            // it (it starts the day after, or later; ongoing or not). Its id is new.
            let outside: PersonalEvent
            if generator.bool() {
                let end = a - 1 - generator.below(40)
                outside = F.make("00000000000000ff", .travel, F.day(end - generator.below(40)), F.day(end),
                                 sensitive: generator.bool(), createdAt: generator.below(5000))
            } else {
                let start = b + 1 + generator.below(40)
                outside = F.make("00000000000000ff", .travel, F.day(start),
                                 generator.bool() ? nil : F.day(start + generator.below(40)),
                                 sensitive: generator.bool(), createdAt: generator.below(5000))
            }
            XCTAssertFalse(PersonalEvents.overlaps(outside, firstDay: first, lastDay: last), "round \(round)")
            let withOutside = generator.bool() ? events + [outside] : [outside] + events
            XCTAssertEqual(PersonalEvents.events(overlapping: first, last, in: withOutside),
                           PersonalEvents.events(overlapping: first, last, in: events), "round \(round)")
            let slots = [PersonalEventSlot(firstDay: first, lastDay: last),
                         PersonalEventSlot(firstDay: first, lastDay: first),
                         PersonalEventSlot(firstDay: last, lastDay: last)]
            XCTAssertEqual(PersonalEvents.coveredSlots(events: withOutside, slots: slots),
                           PersonalEvents.coveredSlots(events: events, slots: slots), "round \(round)")
        }
    }

    func testSameInputGivesSameOutput() {
        var generator = F.Generator(seed: 0x5EED_0507)
        for round in 0..<100 {
            let events = (0..<generator.below(12)).map { index in
                generator.below(4) == 0 ? generator.garbageEvent() : generator.validEvent(index: index)
            }
            let first = F.day(generator.below(150))
            let last = F.day(generator.below(180))
            let slots = [PersonalEventSlot(firstDay: first, lastDay: last)] + F.weekSlots
            for _ in 0..<2 {
                XCTAssertEqual(PersonalEvents.normalized(events), PersonalEvents.normalized(events), "round \(round)")
                XCTAssertEqual(PersonalEvents.events(overlapping: first, last, in: events),
                               PersonalEvents.events(overlapping: first, last, in: events), "round \(round)")
                XCTAssertEqual(PersonalEvents.coveredSlots(events: events, slots: slots),
                               PersonalEvents.coveredSlots(events: events, slots: slots), "round \(round)")
                XCTAssertEqual(PersonalEvents.visible(events, includeSensitive: false),
                               PersonalEvents.visible(events, includeSensitive: false), "round \(round)")
                for event in events {
                    XCTAssertEqual(PersonalEvents.issues(event), PersonalEvents.issues(event))
                    XCTAssertEqual(PersonalEvents.relation(of: event, firstDay: first, lastDay: last),
                                   PersonalEvents.relation(of: event, firstDay: first, lastDay: last))
                }
            }
            // Distinct ids: the answer cannot depend on the order the events arrive in.
            let valid = PersonalEvents.normalized(events)
            let shuffled = generator.shuffled(valid)
            XCTAssertEqual(PersonalEvents.events(overlapping: first, last, in: shuffled),
                           PersonalEvents.events(overlapping: first, last, in: valid), "round \(round)")
            XCTAssertEqual(PersonalEvents.coveredSlots(events: shuffled, slots: slots),
                           PersonalEvents.coveredSlots(events: valid, slots: slots), "round \(round)")
            XCTAssertEqual(PersonalEvents.visible(shuffled, includeSensitive: false),
                           PersonalEvents.visible(valid, includeSensitive: false), "round \(round)")
        }
    }

    func testNoFunctionTrapsOnGeneratedGarbage() {
        var generator = F.Generator(seed: 0x5EED_0508)
        var withIssues = 0
        for round in 0..<500 {
            let events = (0..<generator.below(8)).map { _ in generator.garbageEvent() }
            let first = generator.dayLikeString()
            let last = generator.dayLikeString()
            let rangeIsValid = CanonicalDay.number(first) != nil && CanonicalDay.number(last) != nil && first <= last

            for event in events {
                let issues = PersonalEvents.issues(event)
                let relation = PersonalEvents.relation(of: event, firstDay: first, lastDay: last)
                let overlaps = PersonalEvents.overlaps(event, firstDay: first, lastDay: last)
                if !issues.isEmpty { withIssues += 1 }
                if !issues.isEmpty || !rangeIsValid {
                    XCTAssertNil(relation, "round \(round)")
                    XCTAssertFalse(overlaps, "round \(round)")
                } else {
                    XCTAssertNotNil(relation, "round \(round)")
                }
                XCTAssertEqual(overlaps, relation != nil && relation != .before && relation != .after,
                               "round \(round)")
                // No issue is reported twice.
                XCTAssertEqual(issues.count, Set(issues.map { "\($0)" }).count, "round \(round)")
            }

            let normalized = PersonalEvents.normalized(events)
            XCTAssertTrue(normalized.allSatisfy { PersonalEvents.issues($0).isEmpty }, "round \(round)")
            XCTAssertEqual(Set(normalized.map(\.id)).count, normalized.count, "round \(round)")
            XCTAssertTrue(isInNormalizedOrder(normalized), "round \(round)")
            XCTAssertTrue(normalized.allSatisfy(events.contains), "round \(round)")

            let overlapping = PersonalEvents.events(overlapping: first, last, in: events)
            XCTAssertTrue(overlapping.allSatisfy(normalized.contains), "round \(round)")
            XCTAssertTrue(isInNormalizedOrder(overlapping), "round \(round)")
            if !rangeIsValid { XCTAssertEqual(overlapping, [], "round \(round)") }

            let inWeek = PersonalEvents.events(overlappingWeekStarting: first, in: events)
            XCTAssertTrue(inWeek.allSatisfy(normalized.contains), "round \(round)")
            if CanonicalDay.number(first) == nil { XCTAssertEqual(inWeek, [], "round \(round)") }

            let slots = [PersonalEventSlot(firstDay: first, lastDay: last),
                         PersonalEventSlot(firstDay: last, lastDay: first),
                         PersonalEventSlot(firstDay: generator.dayLikeString(), lastDay: generator.dayLikeString())]
            let covered = PersonalEvents.coveredSlots(events: events, slots: slots)
            XCTAssertEqual(covered.count, slots.count, "round \(round)")
            XCTAssertEqual(covered.first, !overlapping.isEmpty, "round \(round)")

            let visible = PersonalEvents.visible(events, includeSensitive: false)
            XCTAssertTrue(visible.allSatisfy { !$0.sensitive }, "round \(round)")
            XCTAssertEqual(visible, normalized.filter { !$0.sensitive }, "round \(round)")
            XCTAssertEqual(PersonalEvents.visible(events, includeSensitive: true), normalized, "round \(round)")
        }
        XCTAssertGreaterThan(withIssues, 500, "the generator must produce invalid events")
    }
}
