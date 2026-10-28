import Foundation
import XCTest
@testable import Strand

@MainActor
final class CoachBriefCancellationTests: XCTestCase {
    private actor Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var opened = false
        func wait() async {
            if opened { return }
            await withCheckedContinuation { continuation = $0 }
        }
        func open() {
            opened = true
            continuation?.resume()
            continuation = nil
        }
    }

    private final class Delivery {
        var enabled = true
        var lastRun: String?
        var texts: [String] = []
        var retries = 0
        var connection: CoachBriefScheduler.Connection? = .init(owner: "chatGPT:profile-a", generation: UUID())
        var dependencies: CoachBriefScheduler.Dependencies {
            .init(isEnabled: { self.enabled }, timeMinutes: { 0 }, lastRunDay: { self.lastRun },
                  connection: { self.connection },
                  publish: { day, text, _ in self.lastRun = day; self.texts.append(text); return true },
                  unavailable: { _ in self.retries += 1 })
        }
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testExpirationCancelsWorkerAndDiscardsEvenAnUncooperativePartialResult() async {
        let delivery = Delivery()
        let gate = Gate()
        let entered = expectation(description: "provider is awaiting its stream")
        var completions: [Bool] = []
        let completion = CoachBriefScheduler.TaskCompletionGuard { completions.append($0) }
        let worker = Task {
            let succeeded = await CoachBriefScheduler.catchUpIfDue(generateBrief: {
                entered.fulfill()
                await gate.wait()
                return "Incomplete text returned by a cancelled provider"
            }, now: now, calendar: calendar, dependencies: delivery.dependencies)
            completion.finish(success: succeeded)
            return succeeded
        }
        completion.installCancellation { worker.cancel() }
        await fulfillment(of: [entered], timeout: 2)
        completion.expire()
        await gate.open()
        let succeeded = await worker.value
        XCTAssertFalse(succeeded)
        XCTAssertEqual(completions, [false])
        XCTAssertTrue(delivery.texts.isEmpty)
        XCTAssertNil(delivery.lastRun)
        XCTAssertEqual(delivery.retries, 0)

        // An expired generation must release the in-flight slot so foreground catch-up can retry.
        let retried = await CoachBriefScheduler.catchUpIfDue(generateBrief: { "Complete brief" },
            now: now, calendar: calendar, dependencies: delivery.dependencies)
        XCTAssertTrue(retried)
        XCTAssertEqual(delivery.texts, ["Complete brief"])
        XCTAssertNotNil(delivery.lastRun)
    }

    func testCancellationBeforeStartingDoesNotGenerateOrPublish() async {
        let delivery = Delivery()
        var calls = 0
        let worker = Task {
            await CoachBriefScheduler.catchUpIfDue(generateBrief: { calls += 1; return "Brief" },
                now: now, calendar: calendar, dependencies: delivery.dependencies)
        }
        worker.cancel()
        let succeeded = await worker.value
        XCTAssertFalse(succeeded)
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(delivery.texts.isEmpty)
        XCTAssertNil(delivery.lastRun)
        XCTAssertEqual(delivery.retries, 0)
    }

    func testCancelledNilResultDoesNotPostUnavailableNotification() async {
        let delivery = Delivery()
        let gate = Gate()
        let entered = expectation(description: "provider started")
        let worker = Task {
            await CoachBriefScheduler.catchUpIfDue(generateBrief: {
                entered.fulfill()
                await gate.wait()
                return nil
            }, now: now, calendar: calendar, dependencies: delivery.dependencies)
        }
        await fulfillment(of: [entered], timeout: 2)
        worker.cancel()
        await gate.open()
        let succeeded = await worker.value
        XCTAssertFalse(succeeded)
        XCTAssertEqual(delivery.retries, 0)
        XCTAssertNil(delivery.lastRun)
    }

    func testDisablingDuringGenerationPreventsLatePublication() async {
        let delivery = Delivery()
        let gate = Gate()
        let entered = expectation(description: "provider started")
        let worker = Task {
            await CoachBriefScheduler.catchUpIfDue(generateBrief: {
                entered.fulfill()
                await gate.wait()
                return "Complete but no longer requested"
            }, now: now, calendar: calendar, dependencies: delivery.dependencies)
        }
        await fulfillment(of: [entered], timeout: 2)
        delivery.enabled = false
        await gate.open()
        let succeeded = await worker.value
        XCTAssertFalse(succeeded)
        XCTAssertTrue(delivery.texts.isEmpty)
        XCTAssertNil(delivery.lastRun)
        XCTAssertEqual(delivery.retries, 0)
    }

    func testSuccessfulGenerationKeepsDailyDedupAndFailedGenerationLeavesRetryOpen() async {
        let delivery = Delivery()
        let failed = await CoachBriefScheduler.catchUpIfDue(generateBrief: { nil },
            now: now, calendar: calendar, dependencies: delivery.dependencies)
        XCTAssertFalse(failed)
        XCTAssertNil(delivery.lastRun)
        XCTAssertEqual(delivery.retries, 1)

        let success = await CoachBriefScheduler.catchUpIfDue(generateBrief: { "Complete brief" },
            now: now, calendar: calendar, dependencies: delivery.dependencies)
        XCTAssertTrue(success)
        var secondCalls = 0
        let deduplicated = await CoachBriefScheduler.catchUpIfDue(generateBrief: {
            secondCalls += 1
            return "Duplicate brief"
        }, now: now, calendar: calendar, dependencies: delivery.dependencies)
        XCTAssertTrue(deduplicated)
        XCTAssertEqual(secondCalls, 0)
        XCTAssertEqual(delivery.texts, ["Complete brief"])
    }

    func testExpirationBeforeCancellationInstallationStillCancelsAndCompletesOnce() {
        var completions: [Bool] = []
        var cancellations = 0
        let completion = CoachBriefScheduler.TaskCompletionGuard { completions.append($0) }
        completion.expire()
        completion.installCancellation { cancellations += 1 }
        completion.installCancellation { cancellations += 1 }
        completion.finish(success: true)
        completion.expire()
        XCTAssertTrue(completion.isExpired)
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(completions, [false])
    }

    func testExpirationAfterCompletionCannotCancelOrCompleteAgain() {
        var completions: [Bool] = []
        var cancellations = 0
        let completion = CoachBriefScheduler.TaskCompletionGuard { completions.append($0) }
        completion.installCancellation { cancellations += 1 }
        completion.finish(success: true)
        completion.expire()
        completion.finish(success: false)
        XCTAssertFalse(completion.isExpired)
        XCTAssertEqual(cancellations, 0)
        XCTAssertEqual(completions, [true])
    }

    func testGenerateNowDiscardsResultWhenCallerCancels() async {
        let gate = Gate()
        let entered = expectation(description: "manual generation started")
        let worker = Task {
            await CoachBriefScheduler.generateNow {
                entered.fulfill()
                await gate.wait()
                return "Cancelled manual brief"
            }
        }
        await fulfillment(of: [entered], timeout: 2)
        worker.cancel()
        await gate.open()
        let text = await worker.value
        XCTAssertNil(text)
    }

    func testAccountChangeDuringGenerationDiscardsOldAccountTextWithoutRetryNotification() async {
        let delivery = Delivery()
        let gate = Gate()
        let entered = expectation(description: "old account request started")
        let worker = Task {
            await CoachBriefScheduler.catchUpIfDue(generateBrief: {
                entered.fulfill()
                await gate.wait()
                return "Old account advice"
            }, now: now, calendar: calendar, dependencies: delivery.dependencies)
        }
        await fulfillment(of: [entered], timeout: 2)
        delivery.connection = .init(owner: "chatGPT:profile-b", generation: UUID())
        await gate.open()
        let succeeded = await worker.value
        XCTAssertFalse(succeeded)
        XCTAssertTrue(delivery.texts.isEmpty)
        XCTAssertNil(delivery.lastRun)
        XCTAssertEqual(delivery.retries, 0)
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let name = "com.noop.tests.coach-brief.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    func testOwnerMismatchRetiresCacheButPreservesScheduleSettings() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "coachBrief.enabled")
        defaults.set(480, forKey: "coachBrief.timeMinutes")
        var presentationClears = 0
        let first = CoachBriefScheduler.alignStoredBriefOwner("chatGPT:profile-a", defaults: defaults) {
            presentationClears += 1
        }
        XCTAssertTrue(CoachBriefScheduler.storeCompletedBrief("Advice for A", day: "2027-01-15", connection: first, defaults: defaults))
        _ = CoachBriefScheduler.alignStoredBriefOwner("chatGPT:profile-b", defaults: defaults) {
            presentationClears += 1
        }
        XCTAssertNil(CoachBriefScheduler.consumeStoredBrief(defaults: defaults, clearPresentation: {}))
        XCTAssertNil(defaults.data(forKey: "coachBrief.storedRecord"))
        XCTAssertNil(defaults.string(forKey: "coachBrief.lastRunDayKey"))
        XCTAssertTrue(defaults.bool(forKey: "coachBrief.enabled"))
        XCTAssertEqual(defaults.integer(forKey: "coachBrief.timeMinutes"), 480)
        XCTAssertEqual(presentationClears, 2)
    }

    func testColdConsumeRejectsOldRecordAfterOwnerCommitBeforeCleanup() throws {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let old = CoachBriefScheduler.alignStoredBriefOwner("chatGPT:profile-a", defaults: defaults, clearPresentation: {})
        XCTAssertTrue(CoachBriefScheduler.storeCompletedBrief("Private advice for A", day: "2027-01-15", connection: old, defaults: defaults))
        // Simulate process death after the new selected owner is durable but before cache retirement.
        let new = CoachBriefScheduler.Connection(owner: "chatGPT:profile-b", generation: UUID())
        defaults.set(try JSONEncoder().encode(new), forKey: "coachBrief.connection")
        var presentationClears = 0
        XCTAssertNil(CoachBriefScheduler.consumeStoredBrief(defaults: defaults) { presentationClears += 1 })
        XCTAssertEqual(presentationClears, 1)
        XCTAssertNil(defaults.data(forKey: "coachBrief.storedRecord"))
        XCTAssertEqual(CoachBriefScheduler.storedConnection(defaults: defaults), new)
    }

    func testSameOwnerRestorationKeepsBriefAndConsumesItOnce() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let first = CoachBriefScheduler.alignStoredBriefOwner("chatGPT:profile-a", defaults: defaults, clearPresentation: {})
        XCTAssertTrue(CoachBriefScheduler.storeCompletedBrief("Advice for A", day: "2027-01-15", connection: first, defaults: defaults))
        var presentationClears = 0
        let restored = CoachBriefScheduler.alignStoredBriefOwner("chatGPT:profile-a", defaults: defaults) {
            presentationClears += 1
        }
        XCTAssertEqual(restored, first)
        XCTAssertEqual(CoachBriefScheduler.consumeStoredBrief(defaults: defaults, clearPresentation: {}), "Advice for A")
        XCTAssertNil(CoachBriefScheduler.consumeStoredBrief(defaults: defaults, clearPresentation: {}))
        XCTAssertEqual(presentationClears, 0)
        XCTAssertEqual(defaults.string(forKey: "coachBrief.lastRunDayKey"), "2027-01-15")
    }

    func testReturningToSameAccountCannotReviveAnEarlierConnectionResult() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let old = CoachBriefScheduler.alignStoredBriefOwner("chatGPT:profile-a", defaults: defaults, clearPresentation: {})
        _ = CoachBriefScheduler.alignStoredBriefOwner("chatGPT:profile-b", defaults: defaults, clearPresentation: {})
        let current = CoachBriefScheduler.alignStoredBriefOwner("chatGPT:profile-a", defaults: defaults, clearPresentation: {})
        XCTAssertNotEqual(current.generation, old.generation)
        XCTAssertFalse(CoachBriefScheduler.storeCompletedBrief("Stale A result", day: "2027-01-15", connection: old, defaults: defaults))
        XCTAssertNil(CoachBriefScheduler.consumeStoredBrief(defaults: defaults, clearPresentation: {}))
    }

    func testLegacyUntaggedBriefIsDiscardedInsteadOfAttributedToCurrentAccount() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("Unattributed old advice", forKey: "coachBrief.storedText")
        defaults.set(true, forKey: "coachBrief.hasUnconsumedBrief")
        _ = CoachBriefScheduler.alignStoredBriefOwner("chatGPT:profile-a", defaults: defaults, clearPresentation: {})
        XCTAssertNil(CoachBriefScheduler.consumeStoredBrief(defaults: defaults, clearPresentation: {}))
        XCTAssertNil(defaults.object(forKey: "coachBrief.storedText"))
        XCTAssertNil(defaults.object(forKey: "coachBrief.hasUnconsumedBrief"))
    }

    func testNoSelectedOwnerDiscardsPriorCacheAndCannotStoreNewAdvice() {
        let (defaults, name) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let old = CoachBriefScheduler.alignStoredBriefOwner("chatGPT:profile-a", defaults: defaults, clearPresentation: {})
        XCTAssertTrue(CoachBriefScheduler.storeCompletedBrief("Advice for A", day: "2027-01-15", connection: old, defaults: defaults))
        let signedOut = CoachBriefScheduler.alignStoredBriefOwner(nil, defaults: defaults, clearPresentation: {})
        XCTAssertNil(CoachBriefScheduler.consumeStoredBrief(defaults: defaults, clearPresentation: {}))
        XCTAssertFalse(CoachBriefScheduler.storeCompletedBrief("Unowned advice", day: "2027-01-15", connection: signedOut, defaults: defaults))
    }
}
