import XCTest
import UserNotifications
import StrandAnalytics
@testable import Strand

// Stage 1 independent review (build/superapp-coordination/review/stage-1.md, P2): turning the weekly
// reminder on awaits the notification centre's authorization, and Settings starts each switch move
// as its own task. A call that was suspended on that authorization and completes after a newer
// choice (the switch turned off, the scorecard flag turned off and reconciled, or a newer enable)
// used to write the reminder preference and report a state, so the obsolete call won.
//
// Pinned here: the owner's latest choice always wins. An obsolete completion writes no preference,
// schedules nothing and reports none of `.scheduled`, `.denied` or `.off`, which Settings would
// otherwise show over the newer choice.
//
// No notification is scheduled by these tests: the reminder talks to a protocol, and the fake
// keeps the requests in memory. Synthetic values only.
@MainActor
final class WeighInReminderRaceTests: XCTestCase {

    // MARK: - Harness

    /// Keeps requests in memory, and can hold `authorizationStatus()` calls open until the test
    /// releases each one with the status it should answer.
    private final class GatedCenter: WeighInReminderCenter {
        /// The answer of a call that is not held.
        var status: UNAuthorizationStatus = .authorized
        /// The next `authorizationStatus()` call is held.
        var holdsNextAuthorization = false
        private(set) var pending: [UNNotificationRequest] = []
        private(set) var added: [UNNotificationRequest] = []
        private var held: [CheckedContinuation<UNAuthorizationStatus, Never>?] = []

        /// How many calls have been held so far, released or not.
        var heldCount: Int { held.count }

        func release(_ index: Int, with status: UNAuthorizationStatus) {
            held[index]?.resume(returning: status)
            held[index] = nil
        }

        func authorizationStatus() async -> UNAuthorizationStatus {
            guard holdsNextAuthorization else { return status }
            holdsNextAuthorization = false
            return await withCheckedContinuation { held.append($0) }
        }

        func requestAuthorization() async -> Bool { status == .authorized }

        func add(_ request: UNNotificationRequest) async {
            pending.removeAll { $0.identifier == request.identifier }
            pending.append(request)
            added.append(request)
        }

        func removePendingRequests(withIdentifiers identifiers: [String]) {
            pending.removeAll { identifiers.contains($0.identifier) }
        }

        func pendingRequests() async -> [UNNotificationRequest] { pending }
    }

    private struct Harness {
        let center: GatedCenter
        let settings: CutScorecardSettings
        let reminder: WeighInReminder
    }

    private let weeklyId = "weigh-in-reminder"
    private var suites: [String] = []

    override func tearDown() {
        for name in suites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        suites = []
        super.tearDown()
    }

    /// Scorecard flag on, reminder off. Wednesday 29 January 2031, 07:05 UTC.
    private func makeHarness() throws -> Harness {
        let name = "WeighInReminderRaceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        suites.append(name)
        defaults.set(true, forKey: "noop.cutScorecardEnabled")
        let settings = CutScorecardSettings(defaults: defaults)
        let center = GatedCenter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        let now = ScorecardScreenFixture.date("2031-01-29").addingTimeInterval(7 * 3_600 + 5 * 60)
        let reminder = WeighInReminder(center: center, settings: settings, now: { now }, calendar: { calendar })
        return Harness(center: center, settings: settings, reminder: reminder)
    }

    private func waitUntil(_ what: String, file: StaticString = #filePath, line: UInt = #line,
                           _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(10)
        while !condition() {
            if Date() > deadline {
                XCTFail("timed out waiting for \(what)", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    /// Starts `setEnabled(true)` with its authorization held, and returns once it is suspended there.
    private func startHeldEnable(_ h: Harness, file: StaticString = #filePath,
                                 line: UInt = #line) async -> Task<WeighInReminder.Outcome, Never> {
        let before = h.center.heldCount
        h.center.holdsNextAuthorization = true
        let reminder = h.reminder
        let task = Task { await reminder.setEnabled(true) }
        await waitUntil("the enable to reach the authorization", file: file, line: line) {
            h.center.heldCount > before
        }
        return task
    }

    /// True for every outcome Settings would show as the reminder's state.
    private func reportsAState(_ outcome: WeighInReminder.Outcome) -> Bool {
        [.scheduled, .denied, .off].contains(outcome)
    }

    // MARK: - An obsolete enable after a newer choice

    func testAnEnableWhoseAuthorizationReturnsAfterANewerDisableChangesNothing() async throws {
        let h = try makeHarness()
        let older = await startHeldEnable(h)

        let newer = await h.reminder.setEnabled(false)
        XCTAssertEqual(newer, .off)
        XCTAssertFalse(h.settings.reminderEnabled)

        h.center.release(0, with: .authorized)
        let outcome = await older.value
        XCTAssertFalse(reportsAState(outcome), "the obsolete enable reports no state, got \(outcome)")
        XCTAssertFalse(h.settings.reminderEnabled, "the newer disable is still the stored choice")
        XCTAssertTrue(h.center.pending.isEmpty, "nothing is pending behind the off switch")
        XCTAssertTrue(h.center.added.isEmpty, "the obsolete enable scheduled nothing")
    }

    func testAnEnableWhoseAuthorizationReturnsAfterTheFeatureWasSwitchedOffChangesNothing() async throws {
        let h = try makeHarness()
        let older = await startHeldEnable(h)

        h.settings.isEnabled = false
        await h.reminder.reconcile(latestWeighInDay: nil)

        h.center.release(0, with: .authorized)
        let outcome = await older.value
        XCTAssertFalse(reportsAState(outcome), "the obsolete enable reports no state, got \(outcome)")
        XCTAssertFalse(h.settings.reminderEnabled, "the reminder preference is not written while the feature is off")
        XCTAssertTrue(h.center.pending.isEmpty)

        // Turning the feature back on does not revive a reminder the owner never got to keep.
        h.settings.isEnabled = true
        await h.reminder.reconcile(latestWeighInDay: nil)
        XCTAssertFalse(h.settings.reminderEnabled)
        XCTAssertTrue(h.center.pending.isEmpty, "no reminder appears when the feature returns")
    }

    // MARK: - An obsolete denial after a newer choice

    func testADenialThatReturnsAfterANewerDisableReportsNothing() async throws {
        let h = try makeHarness()
        let older = await startHeldEnable(h)

        let newer = await h.reminder.setEnabled(false)
        XCTAssertEqual(newer, .off)

        h.center.release(0, with: .denied)
        let outcome = await older.value
        XCTAssertFalse(reportsAState(outcome),
                       "the row shows the newer off, not an obsolete denial, got \(outcome)")
        XCTAssertFalse(h.settings.reminderEnabled)
        XCTAssertTrue(h.center.pending.isEmpty)
    }

    func testADenialThatReturnsAfterANewerEnableLeavesTheReminderOn() async throws {
        let h = try makeHarness()
        let older = await startHeldEnable(h)

        let newer = await h.reminder.setEnabled(true)        // the owner allowed notifications since
        XCTAssertEqual(newer, .scheduled)

        h.center.release(0, with: .denied)
        let outcome = await older.value
        XCTAssertFalse(reportsAState(outcome), "the obsolete denial reports no state, got \(outcome)")
        XCTAssertTrue(h.settings.reminderEnabled, "the newer enable is still the stored choice")
        XCTAssertEqual(h.center.pending.map(\.identifier), [weeklyId], "the newer enable's request stays")
    }

    // MARK: - Two enables

    func testTwoRacingEnablesLeaveOneRequestAndOneReport() async throws {
        let h = try makeHarness()
        let first = await startHeldEnable(h)
        let second = await startHeldEnable(h)

        h.center.release(1, with: .authorized)
        let newer = await second.value
        XCTAssertEqual(newer, .scheduled)

        h.center.release(0, with: .authorized)
        let older = await first.value
        XCTAssertFalse(reportsAState(older), "only the newer enable reports, got \(older)")
        XCTAssertTrue(h.settings.reminderEnabled)
        XCTAssertEqual(h.center.pending.map(\.identifier), [weeklyId], "exactly one weekly request")
    }

    // MARK: - Unchanged without a race

    func testAnUninterruptedEnableAndDisableBehaveAsBefore() async throws {
        let h = try makeHarness()
        let enabled = await h.reminder.setEnabled(true)
        XCTAssertEqual(enabled, .scheduled)
        XCTAssertTrue(h.settings.reminderEnabled)
        XCTAssertEqual(h.center.pending.map(\.identifier), [weeklyId])

        let disabled = await h.reminder.setEnabled(false)
        XCTAssertEqual(disabled, .off)
        XCTAssertFalse(h.settings.reminderEnabled)
        XCTAssertTrue(h.center.pending.isEmpty)

        h.center.status = .denied
        let denied = await h.reminder.setEnabled(true)
        XCTAssertEqual(denied, .denied)
        XCTAssertFalse(h.settings.reminderEnabled)
        XCTAssertTrue(h.center.pending.isEmpty)
    }

    func testAHeldEnableReleasedWithNothingNewerStillSchedules() async throws {
        let h = try makeHarness()
        let enable = await startHeldEnable(h)
        h.center.release(0, with: .authorized)
        let outcome = await enable.value
        XCTAssertEqual(outcome, .scheduled)
        XCTAssertTrue(h.settings.reminderEnabled)
        XCTAssertEqual(h.center.pending.map(\.identifier), [weeklyId])
    }
}
