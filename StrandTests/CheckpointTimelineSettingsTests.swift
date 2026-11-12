// API ASSUMED BY THESE TESTS
//
// Written from docs/personal/superapp/specs/stage-6.md §7.3 step 4, §9.1, §9.3, §9.4, §12.3 and
// ruling R42 before the implementation exists. `CheckpointTimelineSettings`, `StoredCheckpoint`,
// `CheckpointIssue` and `CheckpointSaveResult` are exactly as §9.3 lists them, with
// `enabledKey`, `checkpointsKey`, `flag` and `init(defaults:)` (API block in Stage6TestSupport.swift).
// Existing API used unchanged: `CutScorecardSettings`, `CheckpointTimeline.governingPhaseIndex`,
// `DeviceRegistry`, `LabBookOwnershipAppFixture`.
//
// Behaviour assumed where the specification leaves it unstated:
//
//  1. `save` of a checkpoint with an empty id inserts it with an issued "c-<8 lowercase hex>" id and
//     returns `.saved` with the stored (trimmed) value; a known id is replaced in place.
//  2. A refused save (`.invalid`, `.limitReached`, `.needsAttention`) writes nothing.
//  3. `issue(_:others:phases:)` checks `title` (`emptyTitle`, `titleTooLong`), then `day`, then the
//     weight cases, then the phase cases, in the order of `CheckpointIssue`'s cases.
//  4. `setDone` returns false and writes nothing for a day after `today`, or for an unknown id.
//
// Synthetic values only (§13.4).

import XCTest
import StrandAnalytics
import WhoopStore
@testable import Strand

final class CheckpointTimelineSettingsTests: XCTestCase {

    private typealias Fx = Stage6Fixture
    private let suites = Stage6Suites()

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    private func draft(_ category: TimelineCheckpointCategory, day: String = "2031-03-19", title: String = "Fixture checkpoint",
                       weight: Double? = nil, phase: String? = nil) -> StoredCheckpoint {
        StoredCheckpoint(id: "", title: title, category: category, day: day, approximate: false, done: false,
                         waypointWeightKg: weight, phaseStartDay: phase)
    }

    private func saved(_ result: CheckpointSaveResult, file: StaticString = #filePath, line: UInt = #line) -> StoredCheckpoint? {
        guard case .saved(let checkpoint) = result else {
            XCTFail("expected a save, got \(result)", file: file, line: line)
            return nil
        }
        return checkpoint
    }

    private func seeded() throws -> (UserDefaults, CheckpointTimelineSettings) {
        let defaults = try suites.make()
        defaults.set(Fx.storedCheckpoints(Fx.checkpoints), forKey: CheckpointTimelineSettings.checkpointsKey)
        return (defaults, CheckpointTimelineSettings(defaults: defaults))
    }

    // MARK: Flag and stored shape

    func testFlagDefaultsToOff() throws {
        XCTAssertEqual(CheckpointTimelineSettings.enabledKey, "noop.checkpointTimelineEnabled")
        XCTAssertEqual(CheckpointTimelineSettings.checkpointsKey, "timeline.checkpoints")
        let defaults = try suites.make()
        XCTAssertFalse(CheckpointTimelineSettings(defaults: defaults).isEnabled)
        XCTAssertNil(defaults.object(forKey: CheckpointTimelineSettings.enabledKey))
    }

    func testRoundTripWithSortedKeysAndVersion() throws {
        let (defaults, settings) = try seeded()
        let text = defaults.string(forKey: CheckpointTimelineSettings.checkpointsKey)
        XCTAssertEqual(settings.checkpoints, Fx.checkpoints)
        XCTAssertFalse(settings.checkpointsNeedAttention)
        XCTAssertNotNil(saved(settings.save(Fx.c2, phases: Fx.phases)))
        XCTAssertEqual(defaults.string(forKey: CheckpointTimelineSettings.checkpointsKey), text, "same value, same bytes")

        let new = try XCTUnwrap(saved(settings.save(draft(.benchmark, day: "2031-04-01"), phases: Fx.phases)))
        XCTAssertNotNil(new.id.range(of: "^c-[0-9a-f]{8}$", options: .regularExpression), new.id)
        let elements = try XCTUnwrap(Stage6Text.array(defaults, CheckpointTimelineSettings.checkpointsKey))
        XCTAssertEqual(elements.count, 6)
        for element in elements { XCTAssertEqual(element["v"] as? Int, 1) }
        XCTAssertEqual(defaults.string(forKey: CheckpointTimelineSettings.checkpointsKey), Fx.json(elements), "sorted keys")
        let newElement = try XCTUnwrap(elements.first { $0["id"] as? String == new.id })
        XCTAssertNil(newElement["waypointWeightKg"], "nil is omitted")
        XCTAssertNil(newElement["phaseStartDay"])
    }

    func testReadingNeverWrites() {
        let defaults = suites.recording()
        defaults.set("not json", forKey: CheckpointTimelineSettings.checkpointsKey)
        defaults.writes = []
        let settings = CheckpointTimelineSettings(defaults: defaults)
        _ = settings.isEnabled
        _ = settings.checkpoints
        _ = settings.checkpointsNeedAttention
        _ = CheckpointTimelineSettings.issue(Fx.c1, others: [], phases: Fx.phases)
        XCTAssertEqual(defaults.writes, [])
        XCTAssertEqual(defaults.string(forKey: CheckpointTimelineSettings.checkpointsKey), "not json")
    }

    func testUnreadableListReadsAsEmptyAndRefusesSaves() throws {
        let defaults = try suites.make()
        defaults.set("[{\"v\":1}]", forKey: CheckpointTimelineSettings.checkpointsKey)
        let settings = CheckpointTimelineSettings(defaults: defaults)
        XCTAssertEqual(settings.checkpoints, [])
        XCTAssertTrue(settings.checkpointsNeedAttention)
        XCTAssertEqual(settings.save(draft(.benchmark), phases: Fx.phases), .needsAttention)
        XCTAssertFalse(settings.delete(id: Fx.c1.id))
        XCTAssertFalse(settings.setDone(id: Fx.c1.id, true, today: "2031-12-31"))
        XCTAssertEqual(defaults.string(forKey: CheckpointTimelineSettings.checkpointsKey), "[{\"v\":1}]")

        // One unreadable element makes the whole list unreadable.
        var elements = Fx.checkpoints.map(Fx.element)
        elements[2]["category"] = "somethingElse"
        defaults.set(Fx.json(elements), forKey: CheckpointTimelineSettings.checkpointsKey)
        XCTAssertEqual(settings.checkpoints, [])
        XCTAssertTrue(settings.checkpointsNeedAttention)
    }

    func testDiscardRemovesOnlyUnreadableData() throws {
        let (defaults, settings) = try seeded()
        Fx.seed(defaults)
        let before = Stage6Text.raw(defaults)
        XCTAssertFalse(settings.discardUnreadableCheckpoints())
        XCTAssertEqual(Stage6Text.raw(defaults), before)
        defaults.set("not json", forKey: CheckpointTimelineSettings.checkpointsKey)
        XCTAssertTrue(settings.discardUnreadableCheckpoints())
        XCTAssertNil(defaults.object(forKey: CheckpointTimelineSettings.checkpointsKey))
        XCTAssertFalse(settings.checkpointsNeedAttention)
        for key in ["niggleLog.entries", "niggleLog.rules", "niggleLog.paused"] {
            XCTAssertEqual(defaults.string(forKey: key), before[key], key)
        }
    }

    // MARK: Operations, with per-row counts

    func testSaveReplacesById() throws {
        let (_, settings) = try seeded()
        var edited = Fx.c4
        edited.title = "Fixture benchmark edited"
        XCTAssertNotNil(saved(settings.save(edited, phases: Fx.phases)))
        XCTAssertEqual(settings.checkpoints.count, 5, "a replace adds no row")
        XCTAssertEqual(settings.checkpoints.first { $0.id == Fx.c4.id }?.title, "Fixture benchmark edited")
        XCTAssertEqual(settings.checkpoints.filter { $0.id != Fx.c4.id }, [Fx.c1, Fx.c2, Fx.c3, Fx.c5])
    }

    func testDeleteRemovesOnlyThatCheckpoint() throws {
        let (_, settings) = try seeded()
        XCTAssertTrue(settings.delete(id: Fx.c3.id))
        XCTAssertEqual(settings.checkpoints, [Fx.c1, Fx.c2, Fx.c4, Fx.c5])
        XCTAssertFalse(settings.delete(id: "c-ffffffff"))
        XCTAssertEqual(settings.checkpoints.count, 4)
    }

    func testLimitRefusesAndNeverTruncates() throws {
        let defaults = try suites.make()
        let many = (0..<200).map { i -> StoredCheckpoint in
            var c = Fx.c4
            c.id = String(format: "c-%08x", i + 0x100)
            return c
        }
        defaults.set(Fx.storedCheckpoints(many), forKey: CheckpointTimelineSettings.checkpointsKey)
        let before = defaults.string(forKey: CheckpointTimelineSettings.checkpointsKey)
        let settings = CheckpointTimelineSettings(defaults: defaults)
        XCTAssertEqual(settings.save(draft(.benchmark), phases: Fx.phases), .limitReached)
        XCTAssertEqual(defaults.string(forKey: CheckpointTimelineSettings.checkpointsKey), before)
        XCTAssertNotNil(saved(settings.save(many[0], phases: Fx.phases)), "a replace is not an addition")
    }

    func testTitleIsTrimmedAndBounded() throws {
        let defaults = try suites.make()
        let settings = CheckpointTimelineSettings(defaults: defaults)
        XCTAssertEqual(settings.save(draft(.other, title: "  \n"), phases: []), .invalid(.emptyTitle))
        XCTAssertEqual(settings.save(draft(.other, title: String(repeating: "t", count: 61)), phases: []),
                       .invalid(.titleTooLong))
        XCTAssertNil(defaults.object(forKey: CheckpointTimelineSettings.checkpointsKey))
        let stored = try XCTUnwrap(saved(settings.save(draft(.other, title: "  Fixture panel \n"), phases: [])))
        XCTAssertEqual(stored.title, "Fixture panel")
        XCTAssertEqual(settings.checkpoints.first?.title, "Fixture panel")
        XCTAssertNotNil(saved(settings.save(draft(.other, title: String(repeating: "t", count: 60)), phases: [])))
        XCTAssertEqual(settings.save(draft(.other, day: "2031-02-30"), phases: []), .invalid(.invalidDay))
    }

    // MARK: Waypoints (§7.3 step 4a, §9.3)

    func testWaypointRoundTripsUnderTheKeyWaypointWeightKg() throws {
        let defaults = try suites.make()
        let settings = CheckpointTimelineSettings(defaults: defaults)
        let stored = try XCTUnwrap(saved(settings.save(draft(.weightWaypoint, weight: 96.0), phases: Fx.phases)))
        XCTAssertEqual(stored.waypointWeightKg, 96.0)
        let element = try XCTUnwrap(Stage6Text.array(defaults, CheckpointTimelineSettings.checkpointsKey)?.first)
        XCTAssertEqual(element["waypointWeightKg"] as? Double, 96.0)
        XCTAssertNil(element["targetWeightKg"])
        let text = try XCTUnwrap(defaults.string(forKey: CheckpointTimelineSettings.checkpointsKey))
        XCTAssertFalse(text.contains("targetWeightKg"))
        XCTAssertEqual(settings.checkpoints.first?.waypointWeightKg, 96.0)
    }

    func testAStoredElementCarryingTargetWeightKgIsUnreadable() throws {
        let defaults = try suites.make()
        var elements = Fx.checkpoints.map(Fx.element)
        elements[0]["targetWeightKg"] = 96.0
        defaults.set(Fx.json(elements), forKey: CheckpointTimelineSettings.checkpointsKey)
        let settings = CheckpointTimelineSettings(defaults: defaults)
        XCTAssertEqual(settings.checkpoints, [])
        XCTAssertTrue(settings.checkpointsNeedAttention)
    }

    func testWaypointWithoutAWeightIsRefused() {
        XCTAssertEqual(CheckpointTimelineSettings.issue(draft(.weightWaypoint), others: [], phases: Fx.phases), .weightMissing)
    }

    func testWeightOnAnotherCategoryIsRefused() {
        for category in TimelineCheckpointCategory.allCases where category != .weightWaypoint {
            let phase = category == .targetDate ? "2031-01-06" : nil
            XCTAssertEqual(CheckpointTimelineSettings.issue(draft(category, day: "2031-06-02", weight: 96.0, phase: phase),
                                                            others: [], phases: Fx.phases),
                           .weightNotAllowed, "\(category)")
        }
    }

    func testWaypointOutsideThirtyToTwoHundredFiftyKgIsRefused() {
        // 2030-12-01 lies before every phase, so no target governs the day.
        for weight in [29.9, 250.1, 0, -1] {
            XCTAssertEqual(CheckpointTimelineSettings.issue(draft(.weightWaypoint, day: "2030-12-01", weight: weight),
                                                            others: [], phases: Fx.phases),
                           .weightOutOfRange, "\(weight)")
        }
        for weight in [30.0, 250.0] {
            XCTAssertNil(CheckpointTimelineSettings.issue(draft(.weightWaypoint, day: "2030-12-01", weight: weight),
                                                          others: [], phases: Fx.phases), "\(weight)")
        }
    }

    func testWaypointEqualToTheCutTargetIsRefused() throws {
        let defaults = try suites.make()
        let settings = CheckpointTimelineSettings(defaults: defaults)
        XCTAssertEqual(settings.save(draft(.weightWaypoint, weight: 94.0), phases: Fx.phases),
                       .invalid(.waypointAtOrBeyondTarget))
        XCTAssertNil(defaults.object(forKey: CheckpointTimelineSettings.checkpointsKey))
    }

    func testWaypointBelowTheCutTargetIsRefused() {
        XCTAssertEqual(CheckpointTimelineSettings.issue(draft(.weightWaypoint, weight: 93.9), others: [], phases: Fx.phases),
                       .waypointAtOrBeyondTarget)
    }

    func testWaypointShortOfTheCutTargetIsSaved() throws {
        let defaults = try suites.make()
        let settings = CheckpointTimelineSettings(defaults: defaults)
        XCTAssertNotNil(saved(settings.save(draft(.weightWaypoint, weight: 94.1), phases: Fx.phases)))
        // A phase of kind other refuses only equality.
        let hold = CutScorecardStoredPhase(kind: .other, name: "Fixture hold", startDay: "2031-06-16", targetWeightKg: 95.0,
                                           rateLowPercentPerWeek: 0.4, rateHighPercentPerWeek: 1.2)
        XCTAssertEqual(CheckpointTimelineSettings.issue(draft(.weightWaypoint, day: "2031-07-01", weight: 95.0), others: [],
                                                        phases: [Fx.p0, hold]), .waypointAtOrBeyondTarget)
        for weight in [94.0, 96.0] {
            XCTAssertNil(CheckpointTimelineSettings.issue(draft(.weightWaypoint, day: "2031-07-01", weight: weight),
                                                          others: [], phases: [Fx.p0, hold]), "\(weight)")
        }
    }

    func testWaypointIsSavedWhenNoPhaseGovernsItsDay() throws {
        let defaults = try suites.make()
        let settings = CheckpointTimelineSettings(defaults: defaults)
        XCTAssertNotNil(saved(settings.save(draft(.weightWaypoint, day: "2030-12-30", weight: 90.0), phases: Fx.phases)))
        // While the phases cannot be read the caller passes none: the waypoint saves unchecked.
        XCTAssertNotNil(saved(settings.save(draft(.weightWaypoint, day: "2031-03-19", weight: 90.0), phases: [])))
        // A phase with no target governs nothing.
        XCTAssertNil(CheckpointTimelineSettings.issue(draft(.weightWaypoint, day: "2031-07-01", weight: 80.0), others: [],
                                                      phases: Fx.phases))
        XCTAssertEqual(settings.checkpoints.count, 2)
    }

    // MARK: Target dates

    func testTargetDateNeedsAStoredPhase() {
        XCTAssertEqual(CheckpointTimelineSettings.issue(draft(.targetDate, day: "2031-06-02"), others: [], phases: Fx.phases),
                       .phaseMissing)
        XCTAssertEqual(CheckpointTimelineSettings.issue(draft(.targetDate, day: "2031-06-02", phase: "2031-01-13"), others: [],
                                                        phases: Fx.phases), .phaseMissing, "no stored phase starts then")
        XCTAssertEqual(CheckpointTimelineSettings.issue(draft(.targetDate, day: "2031-06-02", phase: "2031-01-06"), others: [],
                                                        phases: []), .phaseMissing, "phases unreadable: none passed")
        XCTAssertNil(CheckpointTimelineSettings.issue(draft(.targetDate, day: "2031-06-02", phase: "2031-01-06"), others: [],
                                                      phases: Fx.phases))
    }

    func testPhaseOnAnotherCategoryIsRefused() {
        for category in TimelineCheckpointCategory.allCases where category != .targetDate {
            let weight = category == .weightWaypoint ? 96.0 : nil
            XCTAssertEqual(CheckpointTimelineSettings.issue(draft(category, weight: weight, phase: "2031-01-06"), others: [],
                                                            phases: Fx.phases), .phaseNotAllowed, "\(category)")
        }
    }

    func testTargetDateOnOrBeforeThePhaseStartIsRefused() {
        for day in ["2031-01-06", "2031-01-05"] {
            XCTAssertEqual(CheckpointTimelineSettings.issue(draft(.targetDate, day: day, phase: "2031-01-06"), others: [],
                                                            phases: Fx.phases), .targetDateNotAfterPhaseStart, day)
        }
        XCTAssertNil(CheckpointTimelineSettings.issue(draft(.targetDate, day: "2031-01-07", phase: "2031-01-06"), others: [],
                                                      phases: Fx.phases))
    }

    func testSecondTargetDateForAPhaseIsRefused() throws {
        let (defaults, settings) = try seeded()
        let before = defaults.string(forKey: CheckpointTimelineSettings.checkpointsKey)
        XCTAssertEqual(settings.save(draft(.targetDate, day: "2031-05-01", phase: "2031-01-06"), phases: Fx.phases),
                       .invalid(.phaseAlreadyHasTargetDate))
        XCTAssertEqual(defaults.string(forKey: CheckpointTimelineSettings.checkpointsKey), before)
        // Another phase may have its own.
        XCTAssertNotNil(saved(settings.save(draft(.targetDate, day: "2031-09-01", phase: "2031-06-16"), phases: Fx.phases)))
    }

    func testEditingThePhasesOwnTargetDateIsNotASecondOne() throws {
        let (_, settings) = try seeded()
        var moved = Fx.c5
        moved.day = "2031-06-09"
        let stored = try XCTUnwrap(saved(settings.save(moved, phases: Fx.phases)))
        XCTAssertEqual(stored.id, Fx.c5.id)
        XCTAssertEqual(settings.checkpoints.filter { $0.category == .targetDate }.map(\.day), ["2031-06-09"])
        XCTAssertNil(CheckpointTimelineSettings.issue(moved, others: settings.checkpoints.filter { $0.id != moved.id },
                                                      phases: Fx.phases))
    }

    func testTargetDateStoresNoWeight() throws {
        let defaults = try suites.make()
        let settings = CheckpointTimelineSettings(defaults: defaults)
        XCTAssertEqual(settings.save(draft(.targetDate, day: "2031-06-02", weight: 94.0, phase: "2031-01-06"), phases: Fx.phases),
                       .invalid(.weightNotAllowed))
        let stored = try XCTUnwrap(saved(settings.save(draft(.targetDate, day: "2031-06-02", phase: "2031-01-06"),
                                                       phases: Fx.phases)))
        XCTAssertNil(stored.waypointWeightKg)
        let element = try XCTUnwrap(Stage6Text.array(defaults, CheckpointTimelineSettings.checkpointsKey)?.first)
        XCTAssertNil(element["waypointWeightKg"])
        XCTAssertNil(element["targetWeightKg"])
        XCTAssertEqual(element["phaseStartDay"] as? String, "2031-01-06")
    }

    func testIssueReportsTheFirstIssueInDeclarationOrder() {
        let issue = { (c: StoredCheckpoint) in CheckpointTimelineSettings.issue(c, others: [Fx.c5], phases: Fx.phases) }
        XCTAssertEqual(issue(draft(.weightWaypoint, day: "bad", title: " ")), .emptyTitle)
        XCTAssertEqual(issue(draft(.weightWaypoint, day: "bad", title: String(repeating: "t", count: 61))), .titleTooLong)
        XCTAssertEqual(issue(draft(.weightWaypoint, day: "bad")), .invalidDay)
        XCTAssertEqual(issue(draft(.weightWaypoint, phase: "2031-01-06")), .weightMissing)
        XCTAssertEqual(issue(draft(.bloodPanel, weight: 96, phase: "2031-01-06")), .weightNotAllowed)
        XCTAssertEqual(issue(draft(.weightWaypoint, weight: 20, phase: "2031-01-06")), .weightOutOfRange)
        XCTAssertEqual(issue(draft(.weightWaypoint, weight: 94, phase: "2031-01-06")), .waypointAtOrBeyondTarget)
        XCTAssertEqual(issue(draft(.targetDate, day: "2031-01-06")), .phaseMissing)
        XCTAssertEqual(issue(draft(.weightWaypoint, weight: 96, phase: "2031-01-06")), .phaseNotAllowed)
        XCTAssertEqual(issue(draft(.targetDate, day: "2031-01-06", phase: "2031-01-06")), .targetDateNotAfterPhaseStart)
        XCTAssertEqual(issue(draft(.targetDate, day: "2031-05-01", phase: "2031-01-06")), .phaseAlreadyHasTargetDate)
    }

    // MARK: Done, and the phase target

    func testSetDoneIsRefusedForAFutureDay() throws {
        let (defaults, settings) = try seeded()
        let before = defaults.string(forKey: CheckpointTimelineSettings.checkpointsKey)
        XCTAssertFalse(settings.setDone(id: Fx.c1.id, true, today: "2031-03-18"))
        XCTAssertEqual(defaults.string(forKey: CheckpointTimelineSettings.checkpointsKey), before)
        XCTAssertTrue(settings.setDone(id: Fx.c1.id, true, today: "2031-03-19"), "on its own day")
        XCTAssertEqual(settings.checkpoints.first { $0.id == Fx.c1.id }?.done, true)
        XCTAssertTrue(settings.setDone(id: Fx.c1.id, false, today: "2031-03-19"))
        XCTAssertEqual(settings.checkpoints.first { $0.id == Fx.c1.id }, Fx.c1)
        XCTAssertFalse(settings.setDone(id: "c-ffffffff", true, today: "2031-12-31"))
    }

    func testChangingThePhaseTargetRewritesNoCheckpoint() throws {
        let (defaults, _) = try seeded()
        let scorecard = CutScorecardSettings(defaults: defaults)
        scorecard.phases = Fx.phases
        let before = defaults.string(forKey: CheckpointTimelineSettings.checkpointsKey)
        var overtaken = Fx.p0
        overtaken.targetWeightKg = 96.0
        scorecard.phases = [overtaken, Fx.p1]
        XCTAssertEqual(defaults.string(forKey: CheckpointTimelineSettings.checkpointsKey), before)
        XCTAssertEqual(CheckpointTimelineSettings(defaults: defaults).checkpoints.first { $0.id == Fx.c1.id }?.waypointWeightKg,
                       96.0, "the stored waypoint keeps its weight")
        // Deleting the phase leaves its target date in place.
        scorecard.phases = [Fx.p1]
        XCTAssertEqual(CheckpointTimelineSettings(defaults: defaults).checkpoints, Fx.checkpoints)
    }

    func testGoverningPhaseAgreesWithCutScorecardSettingsActivePhase() throws {
        // Runs against merged code: the pure rule and the settings' own rule pick the same phase.
        let defaults = try suites.make()
        let scorecard = CutScorecardSettings(defaults: defaults)
        let p2 = CutScorecardStoredPhase(kind: .cut, name: "Fixture second cut", startDay: "2031-09-01", targetWeightKg: 90,
                                         rateLowPercentPerWeek: 0.4, rateHighPercentPerWeek: 1.2)
        scorecard.phases = [Fx.p0, Fx.p1, p2]
        let stored = scorecard.phases
        let timeline = Fx.timelinePhases(stored)
        var day = "2030-12-01"
        var checked = 0
        while day <= "2031-12-31" {
            let index = CheckpointTimeline.governingPhaseIndex(on: day, phases: timeline)
            XCTAssertEqual(index.map { stored[$0] }, scorecard.activePhase(on: day), day)
            day = CanonicalDay.key(CanonicalDay.number(day)! + 3)
            checked += 1
        }
        XCTAssertGreaterThan(checked, 100)
    }

    // MARK: Ruling R42

    @MainActor
    func testStoredCheckpointsContainNoDeviceIdentifier() throws {
        let defaults = try suites.make()
        let settings = CheckpointTimelineSettings(defaults: defaults)
        for c in Fx.checkpoints {
            var fresh = c
            fresh.id = ""
            XCTAssertNotNil(saved(settings.save(fresh, phases: Fx.phases)), c.title)
        }
        let text = try XCTUnwrap(defaults.string(forKey: CheckpointTimelineSettings.checkpointsKey))
        XCTAssertFalse(text.contains("deviceId"))
        for id in LabBookOwnershipAppFixture.everyId + [CoachPacketHarness.deviceId] {
            XCTAssertFalse(text.contains(id), id)
        }
    }

    @MainActor
    func testRemovingEveryRegisteredStrapLeavesCheckpointsReadable() async throws {
        typealias LB = LabBookOwnershipAppFixture
        let (defaults, _) = try seeded()
        let before = defaults.string(forKey: CheckpointTimelineSettings.checkpointsKey)
        let store = try await LB.emptyStoreWithRegistry()
        let registry = DeviceRegistry(store: LB.registry(store))
        registry.reload()
        for id in [LB.b, LB.d, LB.n] { await registry.deleteDeviceData(id, store: store) }
        await registry.forget(LB.b, store: store)
        try await store.deleteAllData(deviceId: LB.a)
        XCTAssertEqual(defaults.string(forKey: CheckpointTimelineSettings.checkpointsKey), before)
        XCTAssertEqual(CheckpointTimelineSettings(defaults: defaults).checkpoints, Fx.checkpoints)
    }
}
