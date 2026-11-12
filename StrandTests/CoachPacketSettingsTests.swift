// API ASSUMED BY THESE TESTS
//
// New, in Strand/Data/CoachPacketSettings.swift (specification §8.3):
//
//     final class CoachPacketSettings {
//         static let enabledKey = "noop.coachPacketEnabled"
//         static let rangeDaysKey = "coachPacket.rangeDays"
//         static let sectionsKey = "coachPacket.sections"
//         static let allowedRanges = [7, 14, 28]
//         static let defaultRangeDays = 14
//         /// The one observable copy of the flag, over the standard defaults.
//         @MainActor static let flag = ObservableDefaultsFlag(key: enabledKey)
//
//         init(defaults: UserDefaults = .standard)
//         var isEnabled: Bool { get set }
//         var rangeDays: Int { get set }                  // a stored value outside allowedRanges reads as 14
//         var sections: Set<CoachPacketSection> { get }   // stored choices over each section's default
//         func setSection(_ section: CoachPacketSection, on: Bool)
//     }
//
// Behaviour assumed where the specification leaves it unstated:
//
//  1. `coachPacket.sections` is a String holding one JSON object. Its keys are section raw values
//     ("scorecard", "weigh-ins", "recovery-sleep", "trends", "activity") in ascending order and its
//     values are JSON booleans. A section the owner never switched may be absent from the object.
//  2. A stored sections value that is not a string, does not parse, or holds a key that is no
//     section or a value that is no boolean never traps: every section it does not validly name
//     reads as its default (on).
//  3. Setting `rangeDays` to a value outside `allowedRanges` leaves `rangeDays` reading as an
//     allowed value. Whether the write is refused or stored and then read as 14 is not asserted.
//  4. No key of these settings is in the backup whitelist (specification §14.4, P14).
//
// New, in Strand/Data/DemoScreenRegistry.swift (debug builds; specification §14.1, ruling A4):
//
//     extension DemoScreenPrefixes { static let packet = ["packet-"] }

import XCTest
import StrandAnalytics
import WhoopStore
@testable import Strand

// Stage 2 (coach packet), specification §8.3 and §12.3, and §12.5 for the flag. Written before
// the implementation exists.
@MainActor
final class CoachPacketSettingsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var savedStandardFlag: Any?

    override func setUp() {
        super.setUp()
        suiteName = "CoachPacketSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        savedStandardFlag = UserDefaults.standard.object(forKey: "noop.coachPacketEnabled")
        UserDefaults.standard.removeObject(forKey: "noop.coachPacketEnabled")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        if let savedStandardFlag {
            UserDefaults.standard.set(savedStandardFlag, forKey: "noop.coachPacketEnabled")
        } else {
            UserDefaults.standard.removeObject(forKey: "noop.coachPacketEnabled")
        }
        super.tearDown()
    }

    private var settings: CoachPacketSettings { CoachPacketSettings(defaults: defaults) }

    /// What is stored in the suite, key by key, as property-list data.
    private func storedBytes() throws -> Data {
        let domain = defaults.persistentDomain(forName: suiteName) ?? [:]
        return try PropertyListSerialization.data(fromPropertyList: domain, format: .binary, options: 0)
    }

    // MARK: Keys

    func testKeysAndAllowedRangesAreTheSpecifiedOnes() {
        XCTAssertEqual(CoachPacketSettings.enabledKey, "noop.coachPacketEnabled")
        XCTAssertEqual(CoachPacketSettings.rangeDaysKey, "coachPacket.rangeDays")
        XCTAssertEqual(CoachPacketSettings.sectionsKey, "coachPacket.sections")
        XCTAssertEqual(CoachPacketSettings.allowedRanges, [7, 14, 28])
        XCTAssertEqual(CoachPacketSettings.defaultRangeDays, 14)
    }

    // MARK: Flag

    func testFlagDefaultsToOff() {
        XCTAssertFalse(settings.isEnabled)
        XCTAssertNil(defaults.object(forKey: CoachPacketSettings.enabledKey), "reading the flag stores nothing")
    }

    func testFlagIsStoredUnderItsKeyAndNowhereElse() {
        settings.isEnabled = true
        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(defaults.object(forKey: CoachPacketSettings.enabledKey) as? Bool, true)
        XCTAssertEqual(Set((defaults.persistentDomain(forName: suiteName) ?? [:]).keys),
                       [CoachPacketSettings.enabledKey], "switching the flag on writes one key")
        settings.isEnabled = false
        XCTAssertFalse(settings.isEnabled)
    }

    /// Specification §8.3: views observe one static `ObservableDefaultsFlag` over the flag's key.
    func testTheObservableFlagIsOverTheFlagKeyAndFollowsAWrite() {
        let flag = CoachPacketSettings.flag
        XCTAssertEqual(flag.key, CoachPacketSettings.enabledKey)
        XCTAssertFalse(flag.isEnabled, "off unless switched on")
        XCTAssertTrue(CoachPacketSettings.flag === flag, "one observable copy")

        CoachPacketSettings(defaults: .standard).isEnabled = true
        XCTAssertTrue(flag.isEnabled, "a write through the settings reaches the observer")
        CoachPacketSettings(defaults: .standard).isEnabled = false
        XCTAssertFalse(flag.isEnabled)
    }

    // MARK: Range

    func testRangeDefaultsToFourteenAndRejectsOtherValues() {
        XCTAssertEqual(settings.rangeDays, 14)
        for allowed in [7, 28, 14] {
            settings.rangeDays = allowed
            XCTAssertEqual(settings.rangeDays, allowed)
            XCTAssertEqual(defaults.object(forKey: CoachPacketSettings.rangeDaysKey) as? Int, allowed)
        }
        for stored in [0, -7, 1, 10, 15, 29, 365, Int.max] {
            defaults.set(stored, forKey: CoachPacketSettings.rangeDaysKey)
            XCTAssertEqual(settings.rangeDays, 14, "a stored \(stored) reads as the default")
        }
        defaults.set("28", forKey: CoachPacketSettings.rangeDaysKey)
        XCTAssertTrue(CoachPacketSettings.allowedRanges.contains(settings.rangeDays), "a string never traps")
        defaults.removeObject(forKey: CoachPacketSettings.rangeDaysKey)
        settings.rangeDays = 10
        XCTAssertTrue(CoachPacketSettings.allowedRanges.contains(settings.rangeDays),
                      "setting a value that is not allowed leaves an allowed one")
    }

    // MARK: Sections

    func testSectionsDefaultToOnAndStoredChoicesWin() {
        XCTAssertEqual(settings.sections, Set(CoachPacketSection.allCases))
        XCTAssertEqual(CoachPacketSection.allCases.filter(\.isOnByDefault).count, 7)

        settings.setSection(.activity, on: false)
        XCTAssertEqual(settings.sections, [.scorecard, .weighIns, .intake, .recoverySleep, .trends, .events])
        settings.setSection(.scorecard, on: false)
        XCTAssertEqual(settings.sections, [.weighIns, .intake, .recoverySleep, .trends, .events])
        settings.setSection(.activity, on: true)
        XCTAssertEqual(settings.sections, [.weighIns, .intake, .recoverySleep, .trends, .activity, .events])
        XCTAssertEqual(CoachPacketSettings(defaults: defaults).sections, settings.sections,
                       "the choice is stored, not held by the object")

        for section in CoachPacketSection.allCases { settings.setSection(section, on: false) }
        XCTAssertEqual(settings.sections, [], "every section may be off")
        for section in CoachPacketSection.allCases { settings.setSection(section, on: true) }
        XCTAssertEqual(settings.sections, Set(CoachPacketSection.allCases))
    }

    func testSectionsAreStoredWithSortedKeys() throws {
        // Switched in an order that is not the sorted one.
        settings.setSection(.weighIns, on: false)
        settings.setSection(.activity, on: false)
        settings.setSection(.scorecard, on: true)
        settings.setSection(.recoverySleep, on: false)
        settings.setSection(.trends, on: true)

        let raw = try XCTUnwrap(defaults.string(forKey: CoachPacketSettings.sectionsKey), "stored as a String")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Bool],
                                   "one JSON object of booleans: \(raw)")
        XCTAssertEqual(object, ["activity": false, "recovery-sleep": false, "scorecard": true, "trends": true,
                                "weigh-ins": false])
        // The keys appear in the text in ascending order, so the same choices give the same bytes.
        let positions = try object.keys.sorted().map { key in
            try XCTUnwrap(raw.range(of: "\"\(key)\""), "\(key) in \(raw)").lowerBound
        }
        XCTAssertEqual(positions, positions.sorted(), raw)

        let again = CoachPacketSettings(defaults: defaults)
        again.setSection(.trends, on: true)
        XCTAssertEqual(defaults.string(forKey: CoachPacketSettings.sectionsKey), raw,
                       "storing a choice that is already stored changes no byte")
    }

    func testUnreadableStoredSectionsReadAsTheDefaults() {
        for stored in ["", "not json", "[]", "{\"scorecard\":\"no\"}", "{\"niggles\":false,\"scan\":false}", "null"] {
            defaults.set(stored, forKey: CoachPacketSettings.sectionsKey)
            XCTAssertEqual(settings.sections, Set(CoachPacketSection.allCases), "stored: \(stored)")
        }
        defaults.set(7, forKey: CoachPacketSettings.sectionsKey)
        XCTAssertEqual(settings.sections, Set(CoachPacketSection.allCases), "a value that is not a string")
        defaults.set("{\"activity\":false,\"niggles\":false}", forKey: CoachPacketSettings.sectionsKey)
        XCTAssertEqual(settings.sections, [.scorecard, .weighIns, .intake, .recoverySleep, .trends, .events],
                       "a key that is no section is ignored and the valid one is kept")
    }

    // MARK: Reading never writes

    func testReadingNeverWrites() throws {
        let empty = try storedBytes()
        _ = settings.isEnabled
        _ = settings.rangeDays
        _ = settings.sections
        XCTAssertEqual(try storedBytes(), empty, "reading an empty store wrote something")
        XCTAssertTrue((defaults.persistentDomain(forName: suiteName) ?? [:]).isEmpty)

        // Unusable stored values are read as defaults and left exactly as they are.
        defaults.set(10, forKey: CoachPacketSettings.rangeDaysKey)
        defaults.set("not json", forKey: CoachPacketSettings.sectionsKey)
        let unusable = try storedBytes()
        _ = settings.isEnabled
        XCTAssertEqual(settings.rangeDays, 14)
        XCTAssertEqual(settings.sections, Set(CoachPacketSection.allCases))
        XCTAssertEqual(try storedBytes(), unusable, "reading did not repair what it could not use")
    }

    // MARK: Flag off

    /// Specification §12.5: with the flag off the stored range and section choices are kept and
    /// change nothing else. Switching the flag writes its own key only.
    func testSwitchingTheFlagTouchesNoOtherSetting() {
        settings.rangeDays = 28
        settings.setSection(.trends, on: false)
        let range = defaults.object(forKey: CoachPacketSettings.rangeDaysKey) as? Int
        let sections = defaults.string(forKey: CoachPacketSettings.sectionsKey)

        settings.isEnabled = true
        settings.isEnabled = false
        XCTAssertEqual(defaults.object(forKey: CoachPacketSettings.rangeDaysKey) as? Int, range)
        XCTAssertEqual(defaults.string(forKey: CoachPacketSettings.sectionsKey), sections)
        XCTAssertEqual(settings.rangeDays, 28)
        XCTAssertEqual(settings.sections, [.scorecard, .weighIns, .intake, .recoverySleep, .activity, .events])
    }

    /// The packet's flag and the scorecard's flag are two keys: neither switches the other.
    func testThePacketFlagAndTheScorecardFlagAreIndependent() {
        let scorecard = CutScorecardSettings(defaults: defaults)
        settings.isEnabled = true
        XCTAssertFalse(scorecard.isEnabled)
        scorecard.isEnabled = true
        settings.isEnabled = false
        XCTAssertTrue(scorecard.isEnabled)
        XCTAssertNotEqual(CoachPacketSettings.enabledKey, CutScorecardSettings.enabledKey)
    }

    #if DEBUG
    /// Ruling A4: the stage reserves `packet-` and no other prefix, and it overlaps no other stage's.
    func testThePacketDemoPrefixIsReservedAndOverlapsNoOther() {
        XCTAssertEqual(DemoScreenPrefixes.packet, ["packet-"])
        let registry = DemoScreenRegistry<String>([
            .init(prefixes: DemoScreenPrefixes.scorecard, resolve: { _ in nil }),
            .init(prefixes: DemoScreenPrefixes.packet, resolve: { "answered " + $0 }),
        ])
        XCTAssertEqual(registry.conflicts, [])
        XCTAssertEqual(registry.screen(named: "packet-ready"), "answered packet-ready")
        XCTAssertNil(registry.screen(named: "scorecard-ready"), "the packet element is not asked about another prefix")
        XCTAssertNil(registry.screen(named: "packetready"))
    }
    #endif

    /// Specification §14.4 and P14: the three settings are per-install and stay out of backups.
    func testNoPacketSettingIsInTheBackupWhitelist() {
        defaults.set(true, forKey: CoachPacketSettings.enabledKey)
        defaults.set(28, forKey: CoachPacketSettings.rangeDaysKey)
        defaults.set("{\"activity\":false}", forKey: CoachPacketSettings.sectionsKey)
        let snapshot = BackupSettings.snapshot(from: defaults)
        for key in [CoachPacketSettings.enabledKey, CoachPacketSettings.rangeDaysKey, CoachPacketSettings.sectionsKey] {
            XCTAssertNil(snapshot[key], "\(key) must not be backed up")
        }
        // The whitelist names canonical keys, which need not be the storage keys: no name of either
        // kind mentions the packet.
        XCTAssertEqual(snapshot.keys.filter { $0.lowercased().contains("coachpacket") }, [])
        XCTAssertFalse(snapshot.values.contains { ($0 as? String) == "{\"activity\":false}" })
    }
}
