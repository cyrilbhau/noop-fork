import XCTest
@testable import Strand

final class HostedCardLoadNeedsTests: XCTestCase {
    func testDependencySignatureChangesOnlyWhenRequiredDataChanges() {
        let empty = HostedCardLoadNeeds(raw: "")
        XCTAssertFalse(empty.sleep)
        XCTAssertFalse(empty.stress)
        XCTAssertEqual(HostedCardLoadNeeds(raw: HostedCardPrefs.encode([.trendHRV])), empty)
        let sleep = HostedCardLoadNeeds(raw: HostedCardPrefs.encode([.nightDetail]))
        XCTAssertTrue(sleep.sleep)
        XCTAssertFalse(sleep.stress)
        XCTAssertNotEqual(sleep.signature, empty.signature)
        XCTAssertEqual(HostedCardLoadNeeds(raw: HostedCardPrefs.encode([.stages, .nightDetail])), sleep)
        let both = HostedCardLoadNeeds(raw: HostedCardPrefs.encode([.stressToday, .nightDetail]))
        XCTAssertTrue(both.sleep)
        XCTAssertTrue(both.stress)
        XCTAssertEqual(HostedCardLoadNeeds(raw: HostedCardPrefs.encode([.nightDetail, .stressToday])), both)
        XCTAssertNotEqual(both.signature, sleep.signature)
        XCTAssertEqual(HostedCardLoadNeeds(raw: "[]"), empty)
        XCTAssertEqual(HostedCardLoadNeeds(raw: "unknown-card"), empty)
    }
}
