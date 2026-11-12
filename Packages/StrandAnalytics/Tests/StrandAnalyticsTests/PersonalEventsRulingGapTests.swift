// Gap tests for `PersonalEvents` and its packet rows (stage-5.md §7.3, §8; rulings addendum A17).
//
// Each test pins one fault that the fault-injection pass found no test for, or one ruled point.
// Expected values come from the specification and the rulings, not from the implementation.

import XCTest
@testable import StrandAnalytics

final class PersonalEventsRulingGapTests: XCTestCase {

    private typealias F = PersonalEventsFixture

    // MARK: - Fault P14b: §7.3 `endBeforeStart` needs BOTH days valid

    func testEndBeforeStartIsNotReportedWhenTheStartDayIsInvalid() {
        // "2031-3-10" is not a canonical ten-character key. The end is valid and, read as text or
        // as a date, lies before it. §7.3: `endBeforeStart` applies only when both days are valid.
        let event = F.make(F.id(1), .travel, "2031-3-10", "2031-03-09")
        XCTAssertEqual(PersonalEvents.issues(event), [.invalidStartDay])
    }

    // MARK: - Ruling A17: free text is trimmed again after the 48-byte cut

    func testPacketNoteCutAtASpaceDoesNotEndInASpace() {
        // Byte 48 of the note is a space, so the cut alone would leave 47 letters and a space.
        let head = String(repeating: "a", count: 47)
        let event = F.make(F.id(1), .travel, "2031-03-10", "2031-03-10", note: head + " bbbb")
        let rows = PersonalEvents.packetLines(events: [event], firstDay: "2031-03-10",
                                              lastDay: "2031-03-10", includeSensitive: true)
        XCTAssertEqual(rows, ["entered by the owner, whole local days, oldest first:",
                              "  2031-03-10: travel; note \"\(head)\""])
    }

    func testPacketCustomLabelCutAtASpaceDoesNotEndInASpace() {
        // The stored label is 40 characters at most (§7.3), so the 48-byte cut needs wider
        // characters: 23 two-byte letters (46 bytes), a space (byte 47), then one more two-byte
        // letter that does not fit. The cut falls after the space.
        let head = String(repeating: "é", count: 23)
        let event = F.make(F.id(6), .custom, "2031-03-26", "2031-03-26", label: head + " é",
                           sensitive: true)
        XCTAssertEqual(PersonalEvents.issues(event), [])
        let rows = PersonalEvents.packetLines(events: [event], firstDay: "2031-03-26",
                                              lastDay: "2031-03-26", includeSensitive: true)
        XCTAssertEqual(rows, ["entered by the owner, whole local days, oldest first:",
                              "  2031-03-26: custom \"\(head)\""])
    }
}
