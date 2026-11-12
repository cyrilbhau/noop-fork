import XCTest
@testable import StrandAnalytics

// Packet v2's privacy scan over the two new sections (stage 2 §7.11, §7.12 G-8; stage 5 §7.5;
// rulings A17 and A20). The scan runs over the whole rendered text, later sections included, and
// over every raw free text the assembler gathered beside the input; it fails closed. The API these
// tests assume is listed at the top of `CoachPacketV2Fixture.swift`.

final class CoachPacketV2PrivacyTests: XCTestCase {

    private typealias F = CoachPacketFixture
    private typealias V = CoachPacketV2Fixture
    private typealias G = CoachPacketV2Golden

    /// The full fixture with the events section carrying `events` over G1's range.
    private func draft(events: [PersonalEvent], includeSensitive: Bool = true) -> V.Draft {
        V.full { $0.events = V.eventRows(events, from: F.rangeStart, to: F.rangeEnd, includeSensitive: includeSensitive) }
    }

    private func event(note: String?, label: String? = nil) -> PersonalEvent {
        PersonalEventsFixture.make("a1b2c3d4e5f60718", label == nil ? .travel : .custom, "2031-03-05",
                                   "2031-03-05", label: label, note: note)
    }

    private func findings(_ draft: V.Draft, freeText: [String] = []) -> [String] {
        CoachPacket.scan(draft.input, rendered: draft.text, identifiers: F.identifiers, freeText: freeText)
    }

    func testCleanVersionTwoFixtureHasNoFindings() {
        for text in [G.g1, G.g2, G.intake14, G.intake28, G.bothSwitchedOff, G.eventsE1Off, G.eventsE1On,
                     G.eventsE3On, G.eventsE6] {
            XCTAssertEqual(CoachPacket.privacyViolations(in: text, identifiers: F.identifiers), [])
        }
        XCTAssertEqual(findings(V.full), [])
    }

    func testThePacketsIntakeTokensAreNotFindings() {
        let text = V.compact([.intake], from: "2031-01-29", to: "2031-02-11").text
        XCTAssertEqual(CoachPacket.privacyViolations(in: text, identifiers: F.identifiers), [])
        for token in ["apple-health", "quick-add", "nutrition-file", "mixed"] {
            XCTAssertEqual(CoachPacket.privacyViolations(in: "[\(token)]", identifiers: F.identifiers), [], token)
        }
    }

    func testANoteThatLooksLikeAnEmailAddressBlocksThePacket() {
        let packet = draft(events: [event(note: "ask fixture.person@example.invalid")])
        XCTAssertTrue(packet.text.contains("fixture.person@example.invalid"),
                      "stage 5 returns the row intact; the scan, not the rows, decides")
        XCTAssertTrue(findings(packet).contains("email address"), "\(findings(packet))")
    }

    func testANoteThatLooksLikeAPathBlocksThePacket() {
        let packet = draft(events: [event(note: "see /Users/fixture/notes")])
        XCTAssertTrue(findings(packet).contains { $0.hasPrefix("file path") }, "\(findings(packet))")
    }

    func testAKnownIdentifierInACustomLabelIsFound() {
        let packet = draft(events: [event(note: nil, label: "fixture band swap")])
        XCTAssertFalse(findings(packet).isEmpty)
    }

    func testAHardwareAddressInANoteIsFound() {
        let packet = draft(events: [event(note: "strap 0A:1B-2C:3D-4E:5F")])
        XCTAssertTrue(findings(packet).contains("MAC address"), "\(findings(packet))")
    }

    func testARawEventNoteIsScannedBeforeItIsCut() {
        // Past the 48-byte cut: the row does not carry the address, the raw note does (ruling A20).
        let note = String(repeating: "x", count: 60) + " fixture.person@example.invalid"
        let packet = draft(events: [event(note: note)])
        XCTAssertFalse(packet.text.contains("@"))
        XCTAssertEqual(findings(packet), [])
        XCTAssertTrue(findings(packet, freeText: [note]).contains("email address"))
    }

    func testAPrivateEventIsNotScannedIntoTheTextWhenItIsLeftOut() {
        // A private event with an address is left out of the rows, so it cannot block or leak.
        var hidden = event(note: "fixture.person@example.invalid")
        hidden = PersonalEvent(id: hidden.id, kind: hidden.kind, label: nil, startDay: hidden.startDay,
                               endDay: hidden.endDay, note: hidden.note, sensitive: true, createdAt: 0)
        let packet = draft(events: [hidden], includeSensitive: false)
        XCTAssertFalse(packet.text.contains("fixture.person"))
        XCTAssertEqual(findings(packet), [])
    }

    func testPrivateEventTextNeverAppearsWithTheSwitchOff() {
        for (first, last) in [("2031-03-13", "2031-03-26"), ("2031-05-08", "2031-06-04"), ("2031-02-27", "2031-03-26")] {
            let text = V.compact(Set(CoachPacketSection.allCases), from: first, to: last).text
            for needle in PersonalEventsFixture.privateNeedles {
                XCTAssertFalse(text.contains(needle), "\(needle) in \(first)..\(last)")
            }
        }
    }

    func testAnUnreadableIdentifierListBlocksAVersionTwoPacket() {
        let packet = V.full
        XCTAssertEqual(CoachPacket.scan(packet.input, rendered: packet.text, identifiers: nil, freeText: []),
                       ["known identifiers could not be read"])
    }

    func testTheScanStaysDeterministic() {
        let packet = draft(events: [event(note: "a@b.cd /var/x 00000000-0000-4000-8000-000000000001")])
        XCTAssertEqual(findings(packet), findings(packet))
        XCTAssertEqual(Set(findings(packet)).count, findings(packet).count, "each finding once")
    }
}
