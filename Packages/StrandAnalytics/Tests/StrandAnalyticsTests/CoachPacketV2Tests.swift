import XCTest
import WhoopStore
@testable import StrandAnalytics

// Packet v2 (stage 2 specification §7.12 and §14.5; rulings A5, A17): the intake and events
// sections, added together in one change with one version bump. The API these tests assume is
// listed at the top of `CoachPacketV2Fixture.swift`.

final class CoachPacketV2Tests: XCTestCase {

    private typealias F = CoachPacketFixture
    private typealias V = CoachPacketV2Fixture
    private typealias G = CoachPacketV2Golden

    // MARK: - Helpers

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

    private func headings(_ text: String) -> [String] {
        F.lines(text).filter { $0.hasPrefix("== ") }
    }

    /// The lines under `heading`, up to the next blank line.
    private func body(_ heading: String, in text: String) -> [String]? {
        F.section(heading, in: text)
    }

    private func assertGrammar(_ text: String, _ note: String = "", file: StaticString = #filePath,
                               line: UInt = #line) {
        XCTAssertTrue(text.hasSuffix("\n") && !text.hasSuffix("\n\n"), "\(note) one final newline", file: file, line: line)
        XCTAssertFalse(text.contains("\t") || text.contains("\r") || text.contains("\n\n\n"), note, file: file, line: line)
        XCTAssertFalse(F.lines(text).contains { $0.hasSuffix(" ") }, "\(note) trailing space", file: file, line: line)
        XCTAssertEqual(F.lines(text).first, "NOOP-COACH-PACKET v2", note, file: file, line: line)
        XCTAssertEqual(F.lines(text).last, "end of NOOP-COACH-PACKET v2", note, file: file, line: line)
    }

    private let sevenOrder: [CoachPacketSection] = [.scorecard, .weighIns, .intake, .recoverySleep, .trends,
                                                    .activity, .events]

    // MARK: - The format

    func testVersionIsTwoAndTheSectionsKeepTheFixedOrder() {
        XCTAssertEqual(CoachPacket.formatVersion, 2)
        XCTAssertEqual(CoachPacketSection.allCases, sevenOrder)
        XCTAssertEqual(CoachPacketSection.allCases.map(\.rawValue), G.sectionOrder.map(\.id))
        XCTAssertEqual(CoachPacketSection.intake.rawValue, "intake")
        XCTAssertEqual(CoachPacketSection.events.rawValue, "events")
        XCTAssertTrue(CoachPacketSection.intake.isOnByDefault)
        XCTAssertTrue(CoachPacketSection.events.isOnByDefault)
    }

    func testFullFixtureMatchesGoldenG1() {
        assertSameText(V.full.text, G.g1, "G1 v2")
        XCTAssertEqual(G.g1.utf8.count, 7_173)
    }

    func testNoDataAtAllMatchesGoldenG2() {
        assertSameText(V.empty.text, G.g2, "G2 v2")
    }

    func testFirstAndLastLinesCarryVersionTwo() {
        for text in [G.g1, G.g2, V.full.text, V.empty.text, G.bothSwitchedOff, G.eventsE6] {
            assertGrammar(text)
        }
    }

    func testVersionTwoNamesNothingAsNotRecorded() {
        let text = V.full.text
        XCTAssertEqual(F.lines(startingWith: "not-recorded-by-app: ", in: text), ["not-recorded-by-app: none"])
        XCTAssertTrue(text.contains("\n== INTAKE ==\n"))
        XCTAssertTrue(text.contains("\n== EVENTS ==\n"))
        // Even with both sections off, nothing is named as not recorded any more.
        let off = V.full { $0.base.sections = [] }.text
        XCTAssertEqual(F.lines(startingWith: "not-recorded-by-app: ", in: off), ["not-recorded-by-app: none"])
        XCTAssertEqual(F.lines(startingWith: "switched-off: ", in: off),
                       ["switched-off: scorecard, weigh-ins, intake, recovery-sleep, trends, activity, events"])
    }

    // MARK: - Every section toggled

    func testEachSectionOffMatchesTheGoldenWithThatSectionRemoved() {
        for section in CoachPacketSection.allCases {
            let draft = V.full { $0.base.sections.remove(section) }
            assertSameText(draft.text, G.g1(withSectionsOff: [section.rawValue]), "\(section.rawValue) off")
        }
    }

    func testIntakeSectionOffMatchesGolden() {
        let text = V.full { $0.base.sections.remove(.intake) }.text
        assertSameText(text, G.g1(withSectionsOff: ["intake"]))
        XCTAssertFalse(text.contains("== INTAKE =="))
        XCTAssertTrue(text.contains("\nswitched-off: intake\n"))
    }

    func testEventsSectionOffMatchesGolden() {
        let text = V.full { $0.base.sections.remove(.events) }.text
        assertSameText(text, G.g1(withSectionsOff: ["events"]))
        XCTAssertFalse(text.contains("== EVENTS =="))
        XCTAssertFalse(text.contains("Fixture trip"))
        XCTAssertTrue(text.contains("\nswitched-off: events\n"))
    }

    func testEverySubsetOfTheTwoNewSectionsKeepsEveryOtherLine() {
        for intakeOn in [false, true] {
            for eventsOn in [false, true] {
                var off: Set<String> = []
                if !intakeOn { off.insert("intake") }
                if !eventsOn { off.insert("events") }
                let draft = V.full {
                    if !intakeOn { $0.base.sections.remove(.intake) }
                    if !eventsOn { $0.base.sections.remove(.events) }
                }
                assertSameText(draft.text, G.g1(withSectionsOff: off), "intake \(intakeOn), events \(eventsOn)")
            }
        }
    }

    func testEverySectionOffLeavesHeaderAndNotes() {
        let text = V.full { $0.base.sections = [] }.text
        assertSameText(text, G.g1(withSectionsOff: Set(G.sectionOrder.map(\.id))))
        XCTAssertEqual(headings(text), ["== NOTES =="])
    }

    func testAFeatureSwitchedOffInTheAppSaysSoUnderItsHeadingForIntake() {
        let text = V.full { $0.intake = .switchedOff }.text
        XCTAssertEqual(body("== INTAKE ==", in: text), ["not available: intake is switched off in the app"])
        XCTAssertTrue(text.contains("\nsections: scorecard, weigh-ins, intake, recovery-sleep, trends, activity, events\n"),
                      "a feature off in the app is not a section the owner switched off")
        // Every other block is G1's.
        var expected = G.blocks(G.g1)
        expected[3] = "== INTAKE ==\nnot available: intake is switched off in the app"
        assertSameText(text, expected.joined(separator: "\n\n") + "\n")
    }

    func testAFeatureSwitchedOffInTheAppSaysSoUnderItsHeadingForEvents() {
        let text = V.full { $0.events = .switchedOff }.text
        XCTAssertEqual(body("== EVENTS ==", in: text), ["not available: events is switched off in the app"])
        var expected = G.blocks(G.g1)
        expected[7] = "== EVENTS ==\nnot available: events is switched off in the app"
        assertSameText(text, expected.joined(separator: "\n\n") + "\n")
    }

    func testBothFeaturesSwitchedOffMatchesGolden() {
        let draft = V.compact([.intake, .events], from: F.rangeStart, to: F.rangeEnd,
                              intake: .switchedOff, events: .switchedOff)
        assertSameText(draft.text, G.bothSwitchedOff)
    }

    func testAFeatureSwitchedOffWithItsSectionOffPrintsNothingForIt() {
        let text = V.full {
            $0.intake = .switchedOff
            $0.events = .switchedOff
            $0.base.sections.subtract([.intake, .events])
        }.text
        assertSameText(text, G.g1(withSectionsOff: ["intake", "events"]))
        XCTAssertFalse(text.contains("is switched off in the app"))
    }

    // MARK: - Intake

    func testIntakeFourteenDayGolden() {
        assertSameText(V.compact([.intake], from: "2031-01-29", to: "2031-02-11").text, G.intake14)
    }

    func testIntakeTwentyEightDayGolden() {
        assertSameText(V.compact([.intake], from: "2031-01-09", to: "2031-02-05").text, G.intake28)
    }

    func testIntakeWithNoDataPrintsADashRowForEveryDayAndNoZero() {
        let text = V.compact([.intake], from: F.rangeStart, to: F.rangeEnd, intake: .days([])).text
        let rows = body("== INTAKE ==", in: text) ?? []
        XCTAssertEqual(rows.first, G.intakeLead)
        XCTAssertEqual(Array(rows.dropFirst()), F.rangeDays.map { "  \($0): protein —, energy —" })
        XCTAssertFalse(rows.contains { $0.contains(" 0 g") || $0.contains(" 0 kcal") })
        // G1's range has no intake for the Fixture Person: the same rows.
        XCTAssertEqual(body("== INTAKE ==", in: G.g1), rows)
    }

    func testIntakeDaysOutsideTheRangeOrWithAnInvalidKeyAreIgnored() {
        let days = [
            V.intakeDay("2031-03-02", 150, 2500, .quickAdd),
            V.intakeDay("2031-03-17", 150, 2500, .quickAdd),
            V.intakeDay("2031-3-05", 150, 2500, .quickAdd),
            V.intakeDay("2031-02-30", 150, 2500, .quickAdd),
            V.intakeDay("", 150, 2500, .quickAdd),
        ]
        let text = V.full { $0.intake = .days(days) }.text
        XCTAssertEqual(body("== INTAKE ==", in: text), body("== INTAKE ==", in: G.g1))
    }

    func testTwoIntakeDaysForOneDayKeepTheLast() {
        let days = [V.intakeDay("2031-03-05", 100, 2000, .quickAdd), V.intakeDay("2031-03-05", 130, nil, .appleHealth)]
        let text = V.full { $0.intake = .days(days) }.text
        XCTAssertEqual(F.lines(startingWith: "  2031-03-05: protein", in: text),
                       ["  2031-03-05: protein 130 g, energy — [apple-health]"])
    }

    func testIntakeValuesRoundHalvesAwayFromZero() {
        let days = [V.intakeDay("2031-03-05", 79.5, 2399.5, .quickAdd), V.intakeDay("2031-03-06", 80.49, 2400.4, .quickAdd)]
        let text = V.full { $0.intake = .days(days) }.text
        XCTAssertEqual(F.lines(startingWith: "  2031-03-05: protein", in: text),
                       ["  2031-03-05: protein 80 g, energy 2400 kcal [quick-add]"])
        XCTAssertEqual(F.lines(startingWith: "  2031-03-06: protein", in: text),
                       ["  2031-03-06: protein 80 g, energy 2400 kcal [quick-add]"])
    }

    func testIntakeValuesThatAreNotAPlausibleDayAreAbsentAndNothingTraps() {
        let cases: [(Double?, String)] = [
            (.nan, "—"), (.infinity, "—"), (-.infinity, "—"), (-1, "—"), (-0.0, "0 g"),
            (1e300, "—"), (100_000, "100000 g"), (99_999.5, "100000 g"), (99_999.4, "99999 g"), (0, "0 g"),
        ]
        for (value, printed) in cases {
            let text = V.full { $0.intake = .days([V.intakeDay("2031-03-05", value, nil, .quickAdd)]) }.text
            let expected = printed == "—" ? "  2031-03-05: protein —, energy —"
                                          : "  2031-03-05: protein \(printed), energy — [quick-add]"
            XCTAssertEqual(F.lines(startingWith: "  2031-03-05: protein", in: text), [expected], "\(String(describing: value))")
            let energy = V.full { $0.intake = .days([V.intakeDay("2031-03-05", nil, value, .quickAdd)]) }.text
            let energyPrinted = printed.replacingOccurrences(of: " g", with: " kcal")
            let expectedEnergy = printed == "—" ? "  2031-03-05: protein —, energy —"
                                                : "  2031-03-05: protein —, energy \(energyPrinted) [quick-add]"
            XCTAssertEqual(F.lines(startingWith: "  2031-03-05: protein", in: energy), [expectedEnergy])
        }
    }

    func testIntakeSourceIsPrintedOnlyBesideAValue() {
        let text = V.full { $0.intake = .days([V.intakeDay("2031-03-05", nil, nil, .appleHealth),
                                                 V.intakeDay("2031-03-06", 90, nil, nil)]) }.text
        XCTAssertEqual(F.lines(startingWith: "  2031-03-05: protein", in: text), ["  2031-03-05: protein —, energy —"])
        XCTAssertEqual(F.lines(startingWith: "  2031-03-06: protein", in: text), ["  2031-03-06: protein 90 g, energy —"])
    }

    func testIntakeSourceTokensAreTheClosedEnum() {
        XCTAssertEqual(CoachPacketIntakeSource.appleHealth.rawValue, "apple-health")
        XCTAssertEqual(CoachPacketIntakeSource.quickAdd.rawValue, "quick-add")
        XCTAssertEqual(CoachPacketIntakeSource.nutritionFile.rawValue, "nutrition-file")
        XCTAssertEqual(CoachPacketIntakeSource.mixed.rawValue, "mixed")
    }

    func testTheWidestIntakeRowFitsItsPerDayWidth() {
        let text = V.full { $0.intake = .days(F.rangeDays.map { V.intakeDay($0, 99_999, 99_999, .nutritionFile) }) }.text
        let rows = (body("== INTAKE ==", in: text) ?? []).dropFirst()
        XCTAssertEqual(rows.count, 14)
        for row in rows {
            XCTAssertLessThanOrEqual(row.utf8.count + 1, 70, row)
        }
        XCTAssertEqual(rows.first, "  2031-03-03: protein 99999 g, energy 99999 kcal [nutrition-file]")
    }

    // MARK: - Events

    func testEventsGoldensForStageFivesFourteenDayRange() {
        assertSameText(V.compact([.events], from: "2031-03-13", to: "2031-03-26").text, G.eventsE1Off, "G-E1 off")
        assertSameText(V.compact([.events], from: "2031-03-13", to: "2031-03-26", includeSensitive: true).text,
                       G.eventsE1On, "G-E1 on")
    }

    func testEventsGoldensForStageFivesTwentyEightDayRanges() {
        assertSameText(V.compact([.events], from: "2031-05-08", to: "2031-06-04").text, G.eventsE3Off, "G-E3 off")
        assertSameText(V.compact([.events], from: "2031-05-08", to: "2031-06-04", includeSensitive: true).text,
                       G.eventsE3On, "G-E3 on")
        let fifteen = (0..<15).map { index in
            PersonalEventsFixture.make("f\(index)" + String(repeating: "0", count: 14), .travel,
                                       CutScorecardFixture.day("2031-03-01", index),
                                       CutScorecardFixture.day("2031-03-01", index), createdAt: 2000 + index)
        }
        let draft = V.compact([.events], from: "2031-02-27", to: "2031-03-26",
                              events: V.eventRows(fifteen, from: "2031-02-27", to: "2031-03-26"))
        assertSameText(draft.text, G.eventsE6, "G-E6")
    }

    func testEventsSectionIsStageFivesRowsForEveryGoldenRange() {
        let ranges = [("2031-03-13", "2031-03-26"), ("2031-01-30", "2031-02-26"), ("2031-05-08", "2031-06-04"),
                      ("2031-01-09", "2031-01-22"), ("2031-04-10", "2031-04-23"), ("2031-02-27", "2031-03-26")]
        for (first, last) in ranges {
            for include in [false, true] {
                let rows = PersonalEvents.packetLines(events: PersonalEventsFixture.all, firstDay: first,
                                                      lastDay: last, includeSensitive: include)
                let text = V.compact(Set(CoachPacketSection.allCases), from: first, to: last,
                                     includeSensitive: include).text
                XCTAssertEqual(body("== EVENTS ==", in: text), rows, "\(first)..\(last) sensitive \(include)")
            }
        }
    }

    func testEventRowsArePrintedExactlyAsGiven() {
        let rows = ["entered by the owner, whole local days, oldest first:",
                    "  (2 earlier events in range not shown)",
                    "  2031-03-10..2031-03-16: travel; note \"Fixture trip\"",
                    "  2031-03-26: custom \"Fixture change\"; note \"Fixture note\""]
        let text = V.full { $0.events = .rows(rows) }.text
        XCTAssertEqual(body("== EVENTS ==", in: text), rows)
        XCTAssertEqual(body("== EVENTS ==", in: V.full { $0.events = .rows(["events: none listed in range"]) }.text),
                       ["events: none listed in range"])
    }

    func testAMalformedEventRowIsDroppedAndNothingTraps() {
        let long = "  2031-03-10: custom \"" + String(repeating: "é", count: 200) + "\""
        let rows = ["", "no indent", " one space", "\t2031-03-10: travel", "  2031-03-10: travel",
                    "  2031-03-11: travel\n  injected line", "  2031-03-12: travel\r", "  2031-03-13: tab\there",
                    "entered by the owner, whole local days, oldest first: extra", long]
        let text = V.full { $0.events = .rows(rows) }.text
        assertGrammar(text)
        let printed = body("== EVENTS ==", in: text) ?? []
        XCTAssertEqual(printed.first, "  2031-03-10: travel")
        XCTAssertEqual(printed.count, 2, "\(printed)")
        let cut = printed.last ?? ""
        XCTAssertTrue(cut.hasPrefix("  2031-03-10: custom \"é"))
        XCTAssertLessThanOrEqual(cut.utf8.count, 141)
        XCTAssertFalse(cut.hasSuffix(" "))
        XCTAssertFalse(text.contains("injected line"))
    }

    func testEventRowsThatLeaveNothingSayNoneListed() {
        for rows in [[String](), ["", "no indent"]] {
            let text = V.full { $0.events = .rows(rows) }.text
            XCTAssertEqual(body("== EVENTS ==", in: text), ["events: none listed in range"], "\(rows)")
        }
    }

    func testMoreEventRowsThanTheLimitAreCutSoTheBudgetHolds() {
        let rows = ["entered by the owner, whole local days, oldest first:"]
            + (0..<500).map { "  2031-03-10: custom \"\(String(repeating: "w", count: 48))\"; note \"\(String(repeating: "n", count: 48)) \($0)\"" }
        let text = V.full { $0.events = .rows(rows) }.text
        let printed = body("== EVENTS ==", in: text) ?? []
        XCTAssertEqual(printed.first, rows[0])
        XCTAssertEqual(printed.count, 1 + PersonalEvents.packetRowLimit + 1)
        XCTAssertLessThanOrEqual(text.utf8.count, CoachPacket.byteBudget(rangeDays: 14))
    }

    func testPrivateEventsAreLeftOutUnlessTheSwitchIncludesThem() {
        let ranges = [("2031-03-13", "2031-03-26"), ("2031-05-08", "2031-06-04"), ("2030-11-01", "2031-06-30")]
        for (first, last) in ranges {
            let off = V.compact(Set(CoachPacketSection.allCases), from: first, to: last).text
            for needle in PersonalEventsFixture.privateNeedles + ["illness"] {
                XCTAssertFalse(off.contains(needle), "\(needle) in \(first)..\(last)")
            }
        }
        let on = V.compact([.events], from: "2030-11-01", to: "2031-06-30", includeSensitive: true).text
        XCTAssertTrue(on.contains("custom \"Fixture change\"; note \"Fixture note\""))
        XCTAssertTrue(on.contains("2031-05-19..ongoing: illness"))
    }

    func testNoCountOfHiddenEventsIsPrinted() {
        // Only the two private events, switch off: the packet says nothing is listed and no number.
        let privateOnly = [PersonalEventsFixture.e5, PersonalEventsFixture.e6]
        let draft = V.compact([.events], from: "2031-03-13", to: "2031-06-04",
                              events: V.eventRows(privateOnly, from: "2031-03-13", to: "2031-06-04"))
        XCTAssertEqual(body("== EVENTS ==", in: draft.text), ["events: none listed in range"])
        XCTAssertFalse(draft.text.lowercased().contains("hidden"))
        XCTAssertFalse(draft.text.lowercased().contains("private"))
    }

    func testNigglesScanMarkersAndBenchmarksStayOut() {
        let text = V.full.text
        XCTAssertEqual(headings(text), G.sectionOrder.map(\.heading) + ["== NOTES =="])
        for word in ["niggle", "scan", "benchmark", "marker"] {
            XCTAssertFalse(text.lowercased().contains(word), word)
        }
    }

    // MARK: - Range

    func testInvalidRangePrintsNoNewSection() {
        let draft = V.full { $0.base.rangeEndDay = "2031-02-30" }
        let text = draft.text
        XCTAssertEqual(headings(text), ["== NOTES =="])
        XCTAssertTrue(text.contains("\nrange: invalid\n"))
        XCTAssertTrue(text.contains("\nsections: none\n"))
        XCTAssertTrue(text.contains("\nswitched-off: none\n"))
        XCTAssertTrue(text.contains("\nnot-recorded-by-app: none\n"))
    }

    // MARK: - Budget (ruling A5)

    func testBudgetIsVersionTwosFormula() {
        for days in [7, 14, 28] {
            XCTAssertEqual(CoachPacket.byteBudget(rangeDays: days), 8000 + 290 * days + PersonalEvents.packetByteAllowance)
        }
        XCTAssertEqual(PersonalEvents.packetByteAllowance, 2000)
        XCTAssertEqual(CoachPacket.byteBudget(rangeDays: 7), 12_030)
        XCTAssertEqual(CoachPacket.byteBudget(rangeDays: 14), 14_060)
        XCTAssertEqual(CoachPacket.byteBudget(rangeDays: 28), 18_120)
    }

    func testFullFixtureAndEveryGoldenAreWithinTheBudget() {
        let goldens: [(String, Int)] = [(G.g1, 14), (G.g2, 14), (G.intake14, 14), (G.intake28, 28),
                                        (G.bothSwitchedOff, 14), (G.eventsE1On, 14), (G.eventsE3On, 28),
                                        (G.eventsE6, 28)]
        for (text, days) in goldens {
            XCTAssertLessThanOrEqual(text.utf8.count, CoachPacket.byteBudget(rangeDays: days))
        }
    }

    /// The widest input for each range: every version 1 section at its widest (the same bounds as
    /// `CoachPacketTests`), a widest intake row for every day, and far more widest events than the
    /// row limit, each label and note far over 48 bytes.
    private func widest(days count: Int) -> V.Draft {
        let keys = (0..<count).map { CutScorecardFixture.day(F.rangeEnd, $0 - (count - 1)) }
        let wideName = String(repeating: "Ŵ", count: 2000) + "\n\"" + String(repeating: "w", count: 2000)
        var base = F.Draft()
        base.sections = V.allSections
        base.rangeStartDay = keys[0]
        base.strainFactor = 1.0
        base.days = keys.map {
            F.row($0, recovery: 100, strain: 100, sleep: 1439, deep: 1439, rem: 1439, light: 1439,
                  eff: 1.0, hrv: 300, rhr: 300, hrOnly: true)
        }
        base.steps = keys.map { F.step($0, 99_999, .strapEstimate) }
        base.workouts = keys.flatMap { key in
            (0..<20).map { slot in
                CoachPacketWorkout(day: key, startMinuteOfDay: 600 + slot * 30, sport: wideName,
                                   source: .activityFile, durationMinutes: 1439, avgHr: 300,
                                   energyKcal: 9999, distanceKm: 999.99)
            }
        }
        base.body = [
            CoachPacketBodyReading(kind: .weight, value: 199.9, source: .appleHealth, day: keys[0]),
            CoachPacketBodyReading(kind: .waist, value: 199.9, source: .appleHealth, day: keys[0]),
        ]
        base.hrvBaseline = CoachPacketBaseline(center: 299.6, typical: 199.5...299.4, status: "provisional", nights: 9999)
        base.restingHrBaseline = CoachPacketBaseline(center: 299.6, typical: 199.5...299.4, status: "provisional",
                                                     nights: 9999)
        let weeks = (0..<200).map { index -> CutScorecardWeek in
            let monday = CutScorecardFixture.day("2027-06-07", index * 7)
            return CutScorecardWeek(weekStart: monday, weightKg: 199.9, weightDay: CutScorecardFixture.day(monday, 6),
                                    waistCm: 199.9, waistDay: CutScorecardFixture.day(monday, 6), inPhase: true,
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
            projection: CutScorecardProjection(status: .projected, targetDay: "2033-03-16", weeksRemaining: 104.0,
                                               remainingKg: 199.9),
            waist: CutScorecardWaistSignal(state: .unknown, reason: .noWaistThisWeek, currentCm: 199.9,
                                           referenceCm: 199.9, referenceWeekStart: "2031-02-17", changeCm: -199.9),
            lifts: CutScorecardLiftSignal(state: .unknown, reason: .noSessionsPriorWeek, commonExercises: 99,
                                          dropped: 99, climbed: 99, held: 99, windowStartDay: "2031-02-26",
                                          windowEndDay: "2031-03-04"),
            protein: CutScorecardProteinSignal(state: .unknown, reason: .incompleteLogging, daysLogged: 7,
                                               daysAtOrAboveFloor: 7, requiredDays: 7, floorGrams: 999),
            rateBand: CutScorecardRateBandSignal(state: .unknown, reason: .weighInOverdue, percentPerWeek: -19.99,
                                                 lowPercentPerWeek: 10.0, highPercentPerWeek: 10.0),
            rules: rules,
            verdict: CutScorecardVerdict(kind: .insufficientData, reason: .recompositionCheckIncomplete,
                                         rule: .liftsHoldingWaistShrinking, calorieChangeKcal: -9999,
                                         overriddenRules: CutScorecardRule.allCases,
                                         unevaluatedRules: CutScorecardRule.allCases),
            rejections: CutScorecardRejections(nonFinite: 9999, nonPositive: 9999, invalidDay: 9999, future: 9999))
        base.scorecard = .evaluated(
            phase: CoachPacketPhase(name: wideName, startDay: "2031-01-06", targetWeightKg: 199.9,
                                    rateLowPercentPerWeek: 10.0, rateHighPercentPerWeek: 10.0),
            result: result)
        let wideEvents = (0..<40).map { index in
            PersonalEvent(id: "w\(index)" + String(repeating: "0", count: 13), kind: .custom,
                          label: String(repeating: "Ŵ", count: 40), startDay: "2020-01-01", endDay: "2099-12-31",
                          note: String(repeating: "w", count: 280), sensitive: false, createdAt: index)
        }
        return V.Draft(base: base,
                       intake: .days(keys.map { V.intakeDay($0, 99_999, 99_999, .nutritionFile) }),
                       events: V.eventRows(wideEvents, from: keys[0], to: F.rangeEnd))
    }

    func testWidestPossibleInputIsWithinTheBudgetForEachRange() {
        for count in [7, 14, 28] {
            let text = widest(days: count).text
            XCTAssertLessThanOrEqual(text.utf8.count, CoachPacket.byteBudget(rangeDays: count),
                                     "\(count) days: \(text.utf8.count) bytes")
            XCTAssertEqual(headings(text), G.sectionOrder.map(\.heading) + ["== NOTES =="], "\(count) days")
            let intakeRows = (body("== INTAKE ==", in: text) ?? []).filter { $0.hasPrefix("  ") }
            XCTAssertEqual(intakeRows.count, count)
            let eventRows = body("== EVENTS ==", in: text) ?? []
            XCTAssertEqual(eventRows.count, 2 + PersonalEvents.packetRowLimit)
            XCTAssertEqual(eventRows[1], "  (28 earlier events in range not shown)")
            XCTAssertTrue(eventRows.dropFirst(2).allSatisfy { $0.utf8.count == 140 }, "\(eventRows.last ?? "")")
            assertGrammar(text, "\(count) days")
        }
    }

    // MARK: - Determinism

    func testSameInputGivesTheSameBytes() {
        XCTAssertEqual(V.full.text, V.full.text)
        XCTAssertEqual(CoachPacket.render(V.full.input), V.full.text)
        XCTAssertEqual(V.compact([.intake], from: "2031-01-09", to: "2031-02-05").text,
                       V.compact([.intake], from: "2031-01-09", to: "2031-02-05").text)
    }

    func testIntakeOrderDoesNotChangeTheText() {
        var g = F.Generator(seed: 0xC0AC_4BAC_0201)
        let base = V.compact([.intake], from: "2031-01-09", to: "2031-02-05")
        for _ in 0..<20 {
            var shuffled = base
            shuffled.intake = .days(g.shuffled(V.intakeSeries))
            XCTAssertEqual(shuffled.text, G.intake28)
        }
    }

    func testGeneratedVersionTwoInputsKeepTheGrammarAndTheBudget() {
        var g = F.Generator(seed: 0xC0AC_4BAC_0202)
        let sources: [CoachPacketIntakeSource?] = [nil, .appleHealth, .quickAdd, .nutritionFile, .mixed]
        for round in 0..<200 {
            let count = g.pick([7, 14, 28])
            let keys = (0..<count).map { CutScorecardFixture.day(F.rangeEnd, $0 - (count - 1)) }
            var draft = V.full
            draft.base.rangeStartDay = keys[0]
            draft.base.sections = Set(CoachPacketSection.allCases.filter { _ in g.chance(70) })
            if g.chance(20) {
                draft.intake = .switchedOff
            } else {
                draft.intake = .days(keys.filter { _ in g.chance(60) }.map { key in
                    V.intakeDay(key, g.chance(30) ? nil : g.double(0...400), g.chance(30) ? nil : g.double(0...6000),
                                g.pick(sources))
                })
            }
            if g.chance(20) {
                draft.events = .switchedOff
            } else {
                let events = (0..<g.int(0...30)).map { index -> PersonalEvent in
                    let start = g.pick(keys)
                    return PersonalEvent(id: "g\(index)" + String(repeating: "0", count: 13),
                                         kind: g.pick(PersonalEventKind.allCases.filter { $0 != .custom }), label: nil,
                                         startDay: start, endDay: g.chance(30) ? nil : start,
                                         note: g.chance(50) ? nil : "note \(index)\nline", sensitive: g.chance(30),
                                         createdAt: index)
                }
                draft.events = V.eventRows(events, from: keys[0], to: F.rangeEnd, includeSensitive: g.chance(50))
            }
            let text = draft.text
            assertGrammar(text, "round \(round)")
            XCTAssertLessThanOrEqual(text.utf8.count, CoachPacket.byteBudget(rangeDays: count), "round \(round)")
            let expected = G.sectionOrder.enumerated()
                .filter { draft.base.sections.contains(CoachPacketSection.allCases[$0.offset]) }
                .map(\.element.heading)
            XCTAssertEqual(headings(text), expected + ["== NOTES =="], "round \(round)")
            if draft.base.sections.contains(.intake), case .days = draft.intake {
                XCTAssertEqual((body("== INTAKE ==", in: text) ?? []).count, count + 1, "round \(round)")
            }
            XCTAssertEqual(text, draft.text, "round \(round)")
        }
    }
}
