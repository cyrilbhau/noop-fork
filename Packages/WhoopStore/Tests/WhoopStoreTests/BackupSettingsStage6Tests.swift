// API ASSUMED BY THESE TESTS
//
// Written from docs/personal/superapp/specs/stage-6.md §9.5 and §12.2 before the implementation
// exists. Work package 6-8a adds four entries to `BackupSettings.whitelist` (kind `.string`) and four
// to `BackupSettings.appleDefaultsKey` (each mapped to itself): `niggleLog.entries`,
// `niggleLog.rules`, `niggleLog.paused`, `timeline.checkpoints`. The three `noop.*` flags of stage 6
// join neither. Existing API used unchanged: `whitelist`, `appleDefaultsKey`, `snapshot(from:)`,
// `apply(_:to:)`, `encode(_:)`, `decode(_:)`.
//
// §12.2 names these three as new methods of BackupSettingsTests.swift. They are in a file of their
// own because the test author edits no existing test file; they can be folded into that class in
// stage 6's place in the shared-file order (§14.1, ruling A6).
//
// Synthetic values only (stage 6 §9.2, §9.3 example shapes).

import XCTest
@testable import WhoopStore

final class BackupSettingsStage6Tests: XCTestCase {

    private static let lists: [String: String] = [
        "niggleLog.entries": "[{\"character\":\"positional\",\"id\":\"n-0a1b2c3d\",\"kind\":\"complaint\","
            + "\"location\":\"Fixture location B\",\"note\":\"Fixture note\",\"onsetDay\":\"2031-03-03\",\"side\":\"right\","
            + "\"trend\":\"unchanged\",\"updates\":[{\"day\":\"2031-03-22\",\"note\":\"\",\"seq\":1,\"trend\":\"worsening\","
            + "\"weakness\":false}],\"v\":1,\"weakness\":false}]",
        "niggleLog.rules": "{\"professionalRule\":\"Fixture rule text.\",\"rules\":[{\"action\":\"watch\","
            + "\"characters\":[\"diffuse\"],\"fromDay\":1,\"id\":\"r-00000001\",\"label\":\"Fixture label A\",\"note\":\"\","
            + "\"throughDay\":10,\"trends\":[\"easing\"]}],\"v\":1}",
        "niggleLog.paused": "[{\"exercise\":\"Fixture Press\",\"id\":\"p-0000000a\",\"niggleId\":\"n-0a1b2c3d\","
            + "\"pausedDay\":\"2031-03-10\",\"reason\":\"Fixture reason A\",\"until\":\"Fixture until text\",\"v\":1}]",
        "timeline.checkpoints": "[{\"approximate\":true,\"category\":\"weightWaypoint\",\"day\":\"2031-03-19\","
            + "\"done\":false,\"id\":\"c-000000a1\",\"title\":\"Fixture waypoint\",\"v\":1,\"waypointWeightKg\":96.0}]",
    ]

    private static let flags = ["noop.niggleLogEnabled", "noop.cutStressEnabled", "noop.checkpointTimelineEnabled"]

    private var suites: [String] = []

    override func tearDown() {
        for name in suites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        suites = []
        super.tearDown()
    }

    private func freshDefaults() throws -> UserDefaults {
        let name = "BackupSettingsStage6Tests-\(UUID().uuidString)"
        suites.append(name)
        return try XCTUnwrap(UserDefaults(suiteName: name))
    }

    func testStage6ListsRoundTripAsStrings() throws {
        for key in Self.lists.keys {
            XCTAssertEqual(BackupSettings.whitelist[key], .string, key)
            XCTAssertEqual(BackupSettings.appleDefaultsKey[key], key, key)
        }
        let deviceA = try freshDefaults()
        for (key, text) in Self.lists { deviceA.set(text, forKey: key) }
        let snap = BackupSettings.snapshot(from: deviceA)
        for (key, text) in Self.lists { XCTAssertEqual(snap[key] as? String, text, key) }

        let data = try XCTUnwrap(BackupSettings.encode(snap))
        let decoded = BackupSettings.decode(data)
        let deviceB = try freshDefaults()
        BackupSettings.apply(decoded, to: deviceB)
        for (key, text) in Self.lists {
            XCTAssertEqual(deviceB.string(forKey: key), text, "\(key) is carried unparsed")
        }
        for key in Self.lists.keys {
            XCTAssertNil(BackupSettings.encode([key: 1]), "\(key): a value of the wrong kind is dropped")
            XCTAssertNil(BackupSettings.snapshot(from: try freshDefaults())[key], "\(key): a never-set key is omitted")
        }
    }

    func testStage6FlagsAreNotExported() throws {
        for key in Self.flags {
            XCTAssertNil(BackupSettings.whitelist[key], key)
            XCTAssertNil(BackupSettings.appleDefaultsKey[key], key)
            XCTAssertFalse(BackupSettings.appleDefaultsKey.values.contains(key), key)
            let deviceA = try freshDefaults()
            deviceA.set(true, forKey: key)
            XCTAssertNil(BackupSettings.snapshot(from: deviceA)[key], key)
            XCTAssertNil(BackupSettings.encode([key: 1]), key)
            let deviceB = try freshDefaults()
            BackupSettings.apply([key: 1], to: deviceB)
            XCTAssertNil(deviceB.object(forKey: key), key)
        }
    }

    func testRestoreWithoutStage6KeysLeavesStoredListsUntouched() throws {
        let device = try freshDefaults()
        for (key, text) in Self.lists { device.set(text, forKey: key) }
        // A backup made where the lists did not exist (an Android backup, or an older iPhone one).
        let payload = try XCTUnwrap(BackupSettings.encode(["units.system": "metric"]))
        BackupSettings.apply(BackupSettings.decode(payload), to: device)
        for (key, text) in Self.lists { XCTAssertEqual(device.string(forKey: key), text, key) }
        // A backup carrying one list replaces that list only.
        let incoming = "[]"
        BackupSettings.apply(["timeline.checkpoints": incoming], to: device)
        XCTAssertEqual(device.string(forKey: "timeline.checkpoints"), incoming)
        for (key, text) in Self.lists where key != "timeline.checkpoints" {
            XCTAssertEqual(device.string(forKey: key), text, key)
        }
    }
}
