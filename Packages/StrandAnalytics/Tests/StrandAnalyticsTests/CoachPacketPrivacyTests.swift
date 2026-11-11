import XCTest
@testable import StrandAnalytics

// API ASSUMED BY THESE TESTS
//
// From the stage-2 implementation (docs/personal/superapp/specs/stage-2.md §6.2 and §7.11):
//
//   enum CoachPacket {
//       /// One description per finding; empty means the text may leave the phone.
//       static func privacyViolations(in text: String, identifiers: [String]) -> [String]
//       static func render(_ input: CoachPacketInput) -> String
//   }
//
// and the input types listed at the top of `CoachPacketFixture.swift`. The wording of a description is
// not specified and is not asserted; only whether there are findings, and how many where §7.11 fixes
// the number.

/// The privacy scan of stage 2 §7.11. It fails closed: any finding at all means no text may leave.
///
/// Every identifier here is the invented one of §13.4.
final class CoachPacketPrivacyTests: XCTestCase {

    private typealias F = CoachPacketFixture
    private typealias G = CoachPacketGolden

    private func findings(_ text: String, _ identifiers: [String] = []) -> [String] {
        CoachPacket.privacyViolations(in: text, identifiers: identifiers)
    }

    /// G1 with `planted` put inside one of its lines, so the scan has to find it in the middle of a
    /// real packet and not in a text of its own.
    private func g1(with planted: String, atLine index: Int = 40) -> String {
        var lines = F.lines(G.g1)
        lines[index % lines.count] += " " + planted
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - A clean packet

    func testCleanFixtureHasNoFindings() {
        XCTAssertEqual(findings(G.g1, F.identifiers), [])
        XCTAssertEqual(findings(G.g2, F.identifiers), [])
        XCTAssertEqual(findings(F.full.text, F.identifiers), [])
        XCTAssertEqual(findings(F.empty.text, F.identifiers), [])
        XCTAssertEqual(findings(F.full { $0.sections = [] }.text, F.identifiers), [])
        XCTAssertEqual(findings(F.full { $0.rangeEndDay = "invalid" }.text, F.identifiers), [])
        XCTAssertEqual(findings("", F.identifiers), [])
        XCTAssertEqual(findings(G.g1, []), [])
    }

    func testDatesTimesAndNumbersOfAPacketAreNotFindings() {
        // Shapes that are near a MAC address, a UUID or an email address and are none of them.
        let harmless = [
            "generated: 2031-03-16T07:42:10+01:00",
            "range: 2031-03-03..2031-03-16 (14 days; the last day is today and is partial)",
            "weeks 2031-02-03..2031-03-03",
            "AA:BB:CC:DD:EE",                              // five pairs
            "0000000-0000-4000-8000-000000000001",         // seven digits in the first group
            "00000000-0000-4000-8000-00000000000",         // eleven digits in the last group
            "fixture.person@example",                      // no dot after the @
            "a @ b.c",
            "~7300 strap-estimate",
            "band 0.40 to 1.20 %/week",
        ]
        for text in harmless {
            XCTAssertEqual(findings(text), [], text)
        }
    }

    // MARK: - Identifiers

    func testEachKnownIdentifierIsFoundWhateverItsCase() {
        for identifier in F.identifiers {
            for form in [identifier, identifier.lowercased(), identifier.uppercased()] {
                XCTAssertFalse(findings(g1(with: form), F.identifiers).isEmpty, form)
                XCTAssertFalse(findings(g1(with: form), [identifier]).isEmpty, form)
                XCTAssertFalse(findings(form, [identifier.uppercased()]).isEmpty, form)
                XCTAssertFalse(findings(form, [identifier.lowercased()]).isEmpty, form)
            }
        }
        // An identifier that is no path, UUID, address or email is one finding, and two are two.
        XCTAssertEqual(findings(g1(with: "fixture-strap-0001"), F.identifiers).count, 1)
        XCTAssertEqual(findings(g1(with: "FIXTURE BAND"), F.identifiers).count, 1)
        XCTAssertEqual(findings(g1(with: "fixture phone"), F.identifiers).count, 1)
        XCTAssertEqual(findings(g1(with: "Fixture Band on FIXTURE-STRAP-0001"), F.identifiers).count, 2)
        // It is found anywhere in the text, inside a longer word as well.
        XCTAssertFalse(findings("xxFIXTURE-STRAP-0001yy", [F.deviceId]).isEmpty)
        for index in [0, 1, 17, 40, 88] {
            XCTAssertFalse(findings(g1(with: F.deviceId, atLine: index), [F.deviceId]).isEmpty, "line \(index)")
        }
        // Every description says something.
        for description in findings(g1(with: F.deviceId), F.identifiers) {
            XCTAssertFalse(description.isEmpty)
        }
        // An identifier that is not in the text is not a finding.
        XCTAssertEqual(findings(G.g1, ["FIXTURE-STRAP-0002", "Another Band"]), [])
    }

    func testShortIdentifiersAreNotSearchedFor() {
        // Four characters is the shortest identifier searched for; three is not.
        XCTAssertEqual(findings("the abc of it", ["abc"]), [])
        XCTAssertEqual(findings("the abcd of it", ["abcd"]).count, 1)
        XCTAssertEqual(findings("the ABCD of it", ["abcd"]).count, 1)
        XCTAssertEqual(findings("the abcd of it", ["abc"]), [])
        // The length is in characters, not bytes: three two-byte letters are still three.
        XCTAssertEqual(findings("the ééé of it", ["ééé"]), [])
        XCTAssertEqual(findings("the éééé of it", ["éééé"]).count, 1)
        // Degenerate identifiers match nothing; an empty one in particular must not match everything.
        XCTAssertEqual(findings(G.g1, ["", " ", "a", "kg", "cm", "—", "\n"]), [])
        XCTAssertEqual(findings("", ["", "abc"]), [])
        // A short identifier does not stop a long one in the same list from being found.
        XCTAssertEqual(findings(g1(with: F.deviceId), ["abc", "", F.deviceId]).count, 1)
    }

    // MARK: - Fixed patterns

    func testRawNamespacesAreFound() {
        XCTAssertFalse(findings("source my-whoop").isEmpty)
        XCTAssertFalse(findings("owner-noop").isEmpty)
        XCTAssertFalse(findings(g1(with: "[my-whoop]")).isEmpty)
        XCTAssertFalse(findings(g1(with: "[owner-noop]")).isEmpty)
        XCTAssertFalse(findings(g1(with: "apple-health-noop")).isEmpty)
        // The renderer cannot be handed a raw source string: every source it prints is a token of a
        // closed enum, so no rendered text holds a namespace.
        for text in [F.full.text, F.empty.text] {
            XCTAssertFalse(text.contains("my-whoop"))
            XCTAssertFalse(text.contains("-noop"))
        }
    }

    func testPathsUuidsMacAddressesAndEmailsAreFound() {
        let planted = [
            "/Users/fixture/Library/x.sqlite", "/var/mobile/Containers", "/private/var/x",
            "file:///x/y", "~/Documents",
            "00000000-0000-4000-8000-000000000001", "ABCDEF12-3456-4ABC-8DEF-ABCDEF123456",
            "abcdef12-3456-4abc-8def-abcdef123456",
            "AA:BB:CC:DD:EE:FF", "aa:bb:cc:dd:ee:ff", "AA-BB-CC-DD-EE-FF", "00:11:22:33:44:55",
            "fixture.person@example.invalid", "a@b.c",
        ]
        for item in planted {
            XCTAssertFalse(findings(item).isEmpty, "alone: \(item)")
            XCTAssertFalse(findings(g1(with: item)).isEmpty, "in a packet: \(item)")
            XCTAssertFalse(findings("(\(item))").isEmpty, "in brackets: \(item)")
        }
        // Each of the five path literals of §7.11 on its own.
        for literal in ["/Users/", "/var/", "/private/", "file://", "~/"] {
            XCTAssertFalse(findings("x " + literal + " y").isEmpty, literal)
        }
        // Four different kinds in one text are at least four findings: nothing is reported once and
        // the rest dropped.
        let several = g1(with: "/Users/x 00000000-0000-4000-8000-000000000001 AA:BB:CC:DD:EE:FF a@b.c")
        XCTAssertGreaterThanOrEqual(findings(several).count, 4)
        // The fixed patterns need no identifier list.
        XCTAssertFalse(findings(F.peripheral, []).isEmpty)
        XCTAssertFalse(findings(F.account, []).isEmpty)
        XCTAssertFalse(findings(F.home, []).isEmpty)
    }

    func testThePacketsOwnSourceTokensAreNotFindings() {
        let tokens = ["lab-book", "apple-health", "profile", "strap", "strap-estimate", "whoop",
                      "detected", "manual", "lift-log", "activity-file"]
        XCTAssertEqual(findings(tokens.joined(separator: " "), F.identifiers), [])
        for token in tokens {
            XCTAssertEqual(findings("  2031-03-05 07:05 cycling, 45 min [\(token)]", F.identifiers), [], token)
            XCTAssertEqual(findings("current weight: 97.1 kg (\(token), 2031-03-05)", F.identifiers), [], token)
        }
        // A packet that uses every source token is clean.
        var draft = F.full
        draft.body = [CoachPacketBodyReading(kind: .weight, value: 97.1, source: .appleHealth, day: "2031-03-05"),
                      CoachPacketBodyReading(kind: .waist, value: 97.0, source: .profile, day: nil)]
        draft.steps[0] = F.step("2031-03-03", 9120, .strap)
        draft.workouts.append(F.workout("2031-03-14", 8, 0, "running", .activityFile, min: 30))
        let text = draft.text
        for token in tokens where token != "lab-book" {
            XCTAssertTrue(text.contains(token), token)
        }
        XCTAssertEqual(findings(text, F.identifiers), [])
    }

    // MARK: - Free text is the way in

    func testFixtureIdentifiersPlantedInFreeTextAreFound() {
        func phaseNamed(_ name: String) -> String {
            F.full {
                $0.scorecard = .evaluated(
                    phase: CoachPacketPhase(name: name, startDay: "2031-01-06", targetWeightKg: 94.0,
                                            rateLowPercentPerWeek: 0.40, rateHighPercentPerWeek: 1.20),
                    result: F.result())
            }.text
        }
        func sportNamed(_ name: String) -> String {
            F.full { $0.workouts = [F.workout("2031-03-08", 9, 30, name, .manual, min: 30)] }.text
        }
        // A device name as a phase name, an email address as a sport name (§12.1).
        XCTAssertFalse(findings(phaseNamed(F.nickname), F.identifiers).isEmpty)
        XCTAssertFalse(findings(phaseNamed(F.deviceName.uppercased()), F.identifiers).isEmpty)
        XCTAssertFalse(findings(sportNamed(F.account), F.identifiers).isEmpty)
        XCTAssertFalse(findings(sportNamed(F.account), []).isEmpty, "an email needs no identifier list")
        // The other four identifiers, each through both free-text fields.
        for planted in [F.deviceId, F.peripheral, F.home, F.deviceName] {
            XCTAssertFalse(findings(phaseNamed(planted), F.identifiers).isEmpty, "phase \(planted)")
            XCTAssertFalse(findings(sportNamed(planted), F.identifiers).isEmpty, "sport \(planted)")
        }
        // Raw namespaces and paths typed into a name are caught the same way.
        XCTAssertFalse(findings(sportNamed("run my-whoop"), []).isEmpty)
        XCTAssertFalse(findings(phaseNamed("cut ~/notes"), []).isEmpty)
        // The same packets with harmless names are clean, so it is the planted text that is found.
        XCTAssertEqual(findings(phaseNamed("Fixture cut"), F.identifiers), [])
        XCTAssertEqual(findings(sportNamed("hiking"), F.identifiers), [])
    }

    // MARK: - Determinism and generated plants

    func testTheScanGivesTheSameFindingsEveryTime() {
        let text = g1(with: "FIXTURE-STRAP-0001 /Users/fixture a@b.c")
        XCTAssertEqual(findings(text, F.identifiers), findings(text, F.identifiers))
        // The order of the identifier list decides nothing about whether there are findings.
        XCTAssertEqual(findings(text, F.identifiers).count, findings(text, F.identifiers.reversed()).count)
    }

    func testAnythingPlantedAnywhereInAGeneratedPositionIsFound() {
        var g = F.Generator(seed: 0x9E1F_AC1D_0002)
        let plants = F.identifiers + ["my-whoop", "owner-noop", "/var/x", "/private/x", "file://x", "~/x",
                                      "AA:BB:CC:DD:EE:FF", "a@b.c",
                                      "12345678-90ab-4cde-8f01-234567890abc"]
        let lineCount = F.lines(G.g1).count
        for round in 0..<300 {
            let plant = g.pick(plants)
            let form = g.pick([plant, plant.uppercased(), plant.lowercased()])
            // Upper-casing a fixed literal such as "my-whoop" is outside §7.11; identifiers are compared
            // without case, the literals as written.
            let text = F.identifiers.contains(plant) ? form : plant
            let planted = g1(with: text, atLine: g.int(0...(lineCount - 1)))
            XCTAssertFalse(findings(planted, F.identifiers).isEmpty, "round \(round): \(text)")
        }
    }
}
