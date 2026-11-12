// API ASSUMED BY THESE TESTS
//
// Written from docs/personal/superapp/specs/stage-6.md §1, §9.5, §10.9, §12.3 and §15 (Q1, Q6) before
// the implementation exists. The stage 6 API used here (`NiggleLogSettings`, `CheckpointTimelineSettings`,
// their keys) is declared in Stage6TestSupport.swift. Existing API used unchanged: `WidgetSnapshot`
// and its `suiteName`, `CutScorecardPresenter.reminderTitle` / `.reminderBody`,
// `StrainTargetNotifier.StrainTargetPolicy.copy(target:dayStrain:)`, `AICoachEngine(repo:)`,
// `buildContext()`, `buildFullContext()`, `CoachPacketSettings.setSection(_:on:)`,
// `CoachPacketSection.allCases`, the stage 2 harness `CoachPacketHarness`, `BackupSettings`.
//
// The stage 6 lists are stored in the runner's standard defaults for these tests, because that is
// where the app keeps them and where a widget, the Coach or the packet would have to read them; the
// keys are saved before each test and restored after it. The harness suite holds them too.
//
// Limits. The widget snapshot is built by the iPhone app (StrandiOS/Widgets/WidgetPublish.swift),
// which the macOS test target does not compile; here the snapshot type is encoded with every field
// set while the lists are populated, and Tools/test_stage6_single_source.py asserts that no widget,
// shared or notification source names a stage 6 type or key. The same scan carries "no
// notification request": a pending-request query needs notification permission the test host does
// not have.
//
// Synthetic values only.

import XCTest
import StrandAnalytics
import WhoopStore
@testable import Strand

@MainActor
final class Stage6PrivacyTests: XCTestCase {

    private typealias Fx = Stage6Fixture
    private let packetSuites = CoachPacketSuites()
    private var standardKeys: Stage6StandardKeys?

    override func setUp() {
        super.setUp()
        standardKeys = Stage6StandardKeys(Fx.enabledKeys + Fx.listKeys)
        Fx.seed(UserDefaults.standard, entries: [Fx.n1, Fx.n2, Fx.n4, Fx.n5])
        for key in Fx.enabledKeys { UserDefaults.standard.set(true, forKey: key) }
    }

    override func tearDown() {
        standardKeys?.restore()
        standardKeys = nil
        packetSuites.removeAll()
        super.tearDown()
    }

    /// Owner text, the stage 6 key names and the words that would mark a niggle section.
    private var needles: [String] { Fx.needles + Fx.listKeys + ["niggle", "Niggle", "Paused by your coach"] }

    private func assertNoNeedle(_ text: String, _ what: String, only list: [String]? = nil,
                                file: StaticString = #filePath, line: UInt = #line) {
        for needle in list ?? needles {
            XCTAssertFalse(text.contains(needle), "\(what) contains \(needle)", file: file, line: line)
        }
    }

    private func assertStored(file: StaticString = #filePath, line: UInt = #line) {
        let settings = NiggleLogSettings(defaults: .standard, today: { "2031-06-16" })
        XCTAssertEqual(settings.entries.count, 4, "the lists are populated: the scans are live", file: file, line: line)
        XCTAssertEqual(settings.rules.rules.count, 5, file: file, line: line)
        XCTAssertEqual(CheckpointTimelineSettings(defaults: .standard).checkpoints.count, 5, file: file, line: line)
    }

    func testWidgetSnapshotContainsNoStage6Text() throws {
        assertStored()
        let snapshot = WidgetSnapshot(recovery: 72, bpm: 58, batteryPct: 84, bonded: true,
                                      updated: Fx.noon("2031-03-22"), effort: 38, rest: 81, hrv: 64, restingHr: 52,
                                      effortDisplay: "38", effortWhoop: false, hrSeries: nil, stressSeries: nil,
                                      stressDay: nil, personal: nil)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let text = String(decoding: try encoder.encode(snapshot), as: UTF8.self)
        assertNoNeedle(text, "the widget snapshot")
        for word in ["niggle", "checkpoint", "timeline", "cutStress", "triage"] {
            XCTAssertNil(text.range(of: word, options: .caseInsensitive), "\(word) in the snapshot: \(text)")
        }

        // The App Group suite the widgets read holds no stage 6 key and none of the fixture's owner
        // text. Only the fixture's own strings are searched here: the suite is shared with whatever
        // else the runner's account has stored, and a generic word may occur in unrelated text.
        let group = try XCTUnwrap(UserDefaults(suiteName: WidgetSnapshot.suiteName))
        let keys = Array(group.dictionaryRepresentation().keys)
        XCTAssertFalse(keys.contains { Fx.listKeys.contains($0) || Fx.enabledKeys.contains($0) },
                       "a stage 6 key in the App Group suite")
        let owned = Fx.needles + Fx.listKeys
        for value in group.dictionaryRepresentation().values {
            if let text = value as? String { assertNoNeedle(text, "an App Group value", only: owned) }
            if let data = value as? Data {
                assertNoNeedle(String(decoding: data, as: UTF8.self), "an App Group blob", only: owned)
            }
        }
    }

    func testNoNotificationRequestIsAddedByStage6() {
        assertStored()
        let texts = [CutScorecardPresenter.reminderTitle, CutScorecardPresenter.reminderBody]
            + [StrainTargetNotifier.StrainTargetPolicy.copy(target: 14, dayStrain: 15.2)].flatMap { [$0.title, $0.body] }
        for text in texts { assertNoNeedle(text, "notification text \(text)") }
    }

    func testCoachContextContainsNoStage6Text() async throws {
        assertStored()
        let plain = AICoachEngine(repo: Repository(deviceId: "stage6-privacy"))
        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: "my-whoop")
        repo.setStoreForTesting(store)
        let backed = AICoachEngine(repo: repo)
        for context in [plain.buildContext(), backed.buildContext(), await backed.buildFullContext()] {
            assertNoNeedle(context, "the in-app Coach context")
            for word in ["Resting heart rate week average", "Recovery context", "Waypoint", "Timeline"] {
                XCTAssertFalse(context.contains(word), "\(word) in the Coach context")
            }
        }
    }

    func testCoachPacketContainsNoStage6Text() async throws {
        assertStored()
        let h = try await CoachPacketHarness.fixturePerson(scorecard: true, suites: packetSuites)
        Fx.seed(h.defaults, entries: [Fx.n1, Fx.n2, Fx.n4, Fx.n5])
        for key in Fx.enabledKeys { h.defaults.set(true, forKey: key) }
        for section in CoachPacketSection.allCases { h.packetSettings.setSection(section, on: true) }
        let document = try await h.document()
        assertNoNeedle(document.text, "the coach packet")
        for word in ["Waypoint", "waypoint", "Recovery context", "checkpoint", "Checkpoint"] {
            XCTAssertFalse(document.text.contains(word), "\(word) in the packet")
        }
    }

    func testBackupSettingsCarryStage6ListsAndNoFlag() throws {
        for key in Fx.listKeys {
            XCTAssertEqual(BackupSettings.whitelist[key], .string, key)
            XCTAssertEqual(BackupSettings.appleDefaultsKey[key], key, key)
        }
        for key in Fx.enabledKeys {
            XCTAssertNil(BackupSettings.whitelist[key], key)
            XCTAssertNil(BackupSettings.appleDefaultsKey[key], key)
            XCTAssertFalse(BackupSettings.appleDefaultsKey.values.contains(key), key)
        }
        let snapshot = BackupSettings.snapshot(from: .standard)
        for key in Fx.listKeys {
            XCTAssertEqual(snapshot[key] as? String, UserDefaults.standard.string(forKey: key), key)
        }
        for key in Fx.enabledKeys { XCTAssertNil(snapshot[key], key) }
    }
}
