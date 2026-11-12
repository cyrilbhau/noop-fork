import XCTest
@testable import StrandAnalytics

// Codex review round 3, finding C16: the packet holds its byte budget whatever the event rows, as
// the specification's row limit and allowance promise. Synthetic values only.
final class CodexReviewRound3Tests: XCTestCase {
    private func packet(eventRows: [String]) -> CoachPacketInput {
        CoachPacketInput(generatedAt: "2031-01-08T07:00:00+00:00", rangeStartDay: "2031-01-02",
                         rangeEndDay: "2031-01-08", sections: [.events], days: [], strainFactor: 1,
                         scorecard: .switchedOff, body: [], hrvBaseline: nil, restingHrBaseline: nil,
                         steps: [], workouts: [], intake: .switchedOff, events: .rows(eventRows))
    }

    private func eventSection(_ rendered: String) -> [String] {
        rendered.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            .filter { $0 == PersonalEvents.packetIntroRow || $0 == PersonalEvents.packetNoneListedRow
                || $0.hasPrefix(PersonalEvents.packetRowIndent) }
    }

    /// The shrunk input of C16: 202 repeated lead lines rendered 12,067 bytes against 12,030.
    func testRepeatedLeadLinesStayWithinTheBudget() {
        let budget = CoachPacket.byteBudget(rangeDays: 7)
        for count in [2, 201, 202, 400, 2_000] {
            let rendered = CoachPacket.render(packet(eventRows: Array(repeating: PersonalEvents.packetIntroRow,
                                                                     count: count)))
            XCTAssertLessThanOrEqual(rendered.utf8.count, budget, "\(count) lead lines")
            XCTAssertEqual(eventSection(rendered).filter { $0 == PersonalEvents.packetIntroRow }.count, 1)
        }
    }

    func testRepeatedNoneListedRowsArePrintedOnce() {
        let rendered = CoachPacket.render(packet(eventRows: Array(repeating: PersonalEvents.packetNoneListedRow,
                                                                 count: 500)))
        XCTAssertLessThanOrEqual(rendered.utf8.count, CoachPacket.byteBudget(rangeDays: 7))
        XCTAssertEqual(eventSection(rendered), [PersonalEvents.packetNoneListedRow])
    }

    /// The worst case the allowance names: both lead lines mixed with every widest indented row the
    /// renderer keeps, repeated far past the row limit.
    func testMixedSentinelsAndWidestRowsStayWithinTheBudget() {
        let widest = PersonalEvents.packetRowIndent + String(repeating: "W", count: 400)
        var rows: [String] = []
        for _ in 0..<300 {
            rows.append(PersonalEvents.packetIntroRow)
            rows.append(widest)
            rows.append(PersonalEvents.packetNoneListedRow)
        }
        let rendered = CoachPacket.render(packet(eventRows: rows))
        XCTAssertLessThanOrEqual(rendered.utf8.count, CoachPacket.byteBudget(rangeDays: 7))
        let section = eventSection(rendered)
        XCTAssertEqual(section.first, PersonalEvents.packetIntroRow, "the first sentinel is the one kept")
        XCTAssertFalse(section.contains(PersonalEvents.packetNoneListedRow))
        XCTAssertEqual(section.filter { $0.hasPrefix(PersonalEvents.packetRowIndent) }.count,
                       PersonalEvents.packetRowLimit + 1)
    }

    /// What stage 5 itself returns renders exactly as before: one lead line and its rows.
    func testTheProducersOwnRowsAreUnchanged() {
        let rows = [PersonalEvents.packetIntroRow, "  2031-01-03 to 2031-01-04: travel", "  2031-01-06: illness"]
        let section = eventSection(CoachPacket.render(packet(eventRows: rows)))
        XCTAssertEqual(section, rows)
        XCTAssertEqual(eventSection(CoachPacket.render(packet(eventRows: [PersonalEvents.packetNoneListedRow]))),
                       [PersonalEvents.packetNoneListedRow])
    }
}
