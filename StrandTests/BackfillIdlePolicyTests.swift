import XCTest
@testable import Strand

final class BackfillIdlePolicyTests: XCTestCase {
    func testOnlyIntactHistoryRecordsAndBoundariesExtendTheDeadline() {
        // Exhaustive wire-type oracle, shared with Kotlin. Includes both envelope families and
        // Android's already-supported historical IMU stream (52).
        let accepted = (0...255).filter {
            BackfillIdlePolicy.shouldExtendTimeout(packetType: $0, integrityOK: true)
        }
        XCTAssertEqual(accepted, [47, 49, 52, 56])
        XCTAssertTrue((0...255).allSatisfy {
            !BackfillIdlePolicy.shouldExtendTimeout(packetType: $0, integrityOK: false)
        })
    }

    func testLiveChatterAfterHistoryEndsCannotKeepTheSyncAlive() {
        var deadline = 60
        // A genuine history frame at t=30 earns the existing full 60-second idle allowance.
        if BackfillIdlePolicy.shouldExtendTimeout(packetType: 47, integrityOK: true) {
            deadline = 30 + 60
        }
        // The strap omits HISTORY_COMPLETE but keeps talking every second for 15 minutes.
        // Under the old routing-as-progress gate, events and console logs kept moving this deadline.
        for second in 31...900 {
            for type in [40, 43, 48, 50] {
                if BackfillIdlePolicy.shouldExtendTimeout(packetType: type, integrityOK: true) {
                    deadline = second + 60
                }
            }
        }
        XCTAssertEqual(deadline, 90)
    }

    func testSlowProductiveHistoryAndConsoleChunkBoundariesKeepTheirAllowance() {
        var deadline = 60
        // A long productive backlog remains valid even with 59-second gaps. Metadata protects
        // historical console-only chunks too; no absolute session cap is introduced.
        for second in stride(from: 59, through: 1180, by: 59) {
            XCTAssertLessThan(second, deadline)
            let type = second % 118 == 0 ? 49 : 47
            if BackfillIdlePolicy.shouldExtendTimeout(packetType: type, integrityOK: true) {
                deadline = second + 60
            }
        }
        XCTAssertEqual(deadline, 1240)
    }

    @MainActor func testEventsConsoleAndDamagedHistoryStillReachTheArchivalRoute() {
        for type in [UInt8(47), 48, 49, 50, 56] {
            // Raw routing deliberately does not require integrity: rejection archival needs the
            // damaged bytes before any trim acknowledgement. The timeout gate must not replace it.
            var whoop4 = [UInt8](repeating: 0, count: 5)
            whoop4[4] = type
            XCTAssertTrue(BLEManager.isOffloadFrame(whoop4, family: .whoop4))
            var whoop5 = [UInt8](repeating: 0, count: 9)
            whoop5[8] = type
            XCTAssertTrue(BLEManager.isOffloadFrame(whoop5, family: .whoop5))
        }
    }
}
