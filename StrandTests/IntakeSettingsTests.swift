// API ASSUMED BY THESE TESTS
//
// Stage 3 specification §9.2, §9.2.1 and §12.3 (`IntakeSettingsTests.swift`). Written before the
// implementation exists. New, in Strand/Data/IntakeSettings.swift, exactly as §9.2.1 gives it:
//
//     final class IntakeSettings {
//         static let enabledKey = "noop.intakeEnabled", sourceKey = "intake.source",
//                    targetsKey = "intake.targets", zoneLogKey = "intake.zoneLog",
//                    healthSourcesKey = "intake.health.sources",
//                    healthKnownSourcesKey = "intake.health.knownSources",
//                    healthBackfilledKey = "intake.health.backfilled",
//                    supplementQuestionsKey = "intake.supplement.questions",
//                    cutoffEnabledKey = "intake.cutoff.enabled",
//                    cutoffMinuteOfDayKey = "intake.cutoff.minuteOfDay",
//                    cutoffTimeSetKey = "intake.cutoff.timeSet",
//                    quickAddPresetsKey = "intake.quickAdd.presets", entriesKeyPrefix = "intake.entries."
//         static let maxSupplements = 4, maxPresets = 6
//         @MainActor static let flag: ObservableDefaultsFlag
//         init(defaults: UserDefaults = .standard, scorecard: CutScorecardSettings? = nil)
//         var isEnabled, source, healthReadEnabled, storedTargets, targetsNeedAttention, setTargets(_:),
//             targets(on:), proteinFloorGrams, setProteinFloorGrams(_:), zoneLog, admittedHealthSources,
//             knownHealthSources, recordHealthSource(bundleId:name:day:), healthBackfilled,
//             supplementQuestions, addSupplementQuestion(_:), removeSupplementQuestion(_:),
//             cutoffEnabled, cutoffMinuteOfDay, cutoffTimeSet, quickAddPresets
//         var hasChosenSource: Bool { get }                                            [assumed]
//     }
//
// Stage 1 ruling R45 (stage-1.md §9.2, work package 1-10) on `CutScorecardSettings`:
// `isWholeGramProteinFloor(_:)`, `proteinFloorWholeGrams`, `proteinFloorMaximumGrams`.
//
// `ObservableDefaultsFlag` is the shared scaffolding class as it exists today.
//
// Behaviour assumed where the specification leaves it open:
//  1. The zone log is stored as a JSON array of objects with the keys "from" and "tz" (§9.2); the
//     test decodes the stored string rather than comparing bytes, so key order is not asserted.
//  2. `cutoffMinuteOfDay` clamps an out-of-range write to 0...1439 (§9.2.1) and stores the clamped
//     value.
//  3. `quickAddPresets` drops items past the sixth on write (§9.2.1).
//
// Synthetic values only.

import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

@MainActor
final class IntakeSettingsTests: XCTestCase {
    private let suites = IntakeSuites()

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    private func fresh() throws -> (IntakeSettings, CutScorecardSettings, IntakeRecordingDefaults) {
        let name = "IntakeSettingsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(IntakeRecordingDefaults(suiteName: name))
        suites.names.append(name)
        let scorecard = CutScorecardSettings(defaults: defaults)
        return (IntakeSettings(defaults: defaults, scorecard: scorecard), scorecard, defaults)
    }

    private func stored(_ defaults: UserDefaults, _ key: String) -> String? { defaults.string(forKey: key) }

    // MARK: - Keys and defaults

    func testEveryKeyHasItsDocumentedDefault() throws {
        XCTAssertEqual(IntakeSettings.enabledKey, "noop.intakeEnabled")
        XCTAssertEqual(IntakeSettings.sourceKey, "intake.source")
        XCTAssertEqual(IntakeSettings.targetsKey, "intake.targets")
        XCTAssertEqual(IntakeSettings.zoneLogKey, "intake.zoneLog")
        XCTAssertEqual(IntakeSettings.healthSourcesKey, "intake.health.sources")
        XCTAssertEqual(IntakeSettings.healthKnownSourcesKey, "intake.health.knownSources")
        XCTAssertEqual(IntakeSettings.healthBackfilledKey, "intake.health.backfilled")
        XCTAssertEqual(IntakeSettings.supplementQuestionsKey, "intake.supplement.questions")
        XCTAssertEqual(IntakeSettings.cutoffEnabledKey, "intake.cutoff.enabled")
        XCTAssertEqual(IntakeSettings.cutoffMinuteOfDayKey, "intake.cutoff.minuteOfDay")
        XCTAssertEqual(IntakeSettings.cutoffTimeSetKey, "intake.cutoff.timeSet")
        XCTAssertEqual(IntakeSettings.quickAddPresetsKey, "intake.quickAdd.presets")
        XCTAssertEqual(IntakeSettings.entriesKeyPrefix, "intake.entries.")
        XCTAssertEqual(IntakeSettings.maxSupplements, 4)
        XCTAssertEqual(IntakeSettings.maxPresets, 6)

        let (settings, _, defaults) = try fresh()
        XCTAssertFalse(settings.isEnabled)
        XCTAssertEqual(settings.source, .none)
        XCTAssertFalse(settings.hasChosenSource)
        XCTAssertFalse(settings.healthReadEnabled)
        XCTAssertNil(settings.storedTargets)
        XCTAssertFalse(settings.targetsNeedAttention)
        XCTAssertNil(settings.proteinFloorGrams, "the generic scorecard rules carry no floor")
        XCTAssertEqual(settings.targets(on: "2031-01-29"), IntakeTargets())
        XCTAssertEqual(settings.zoneLog, [])
        XCTAssertNil(settings.admittedHealthSources, "absent: every source is admitted")
        XCTAssertEqual(settings.knownHealthSources, [:])
        XCTAssertFalse(settings.healthBackfilled)
        XCTAssertEqual(settings.supplementQuestions, [])
        XCTAssertFalse(settings.cutoffEnabled)
        XCTAssertEqual(settings.cutoffMinuteOfDay, 1_260)
        XCTAssertFalse(settings.cutoffTimeSet)
        XCTAssertEqual(settings.quickAddPresets, [])
        XCTAssertEqual(defaults.written, [], "reading every default writes nothing")
        XCTAssertEqual(defaults.snapshot(), [:])
    }

    func testAnUnknownStoredSourceReadsAsNone() throws {
        let (settings, _, defaults) = try fresh()
        defaults.set("myFoodApp", forKey: IntakeSettings.sourceKey)
        defaults.written = []
        XCTAssertEqual(settings.source, .none)
        XCTAssertFalse(settings.hasChosenSource, "an unknown string is not a choice")
        XCTAssertEqual(stored(defaults, IntakeSettings.sourceKey), "myFoodApp", "reading never rewrites (R30)")
        XCTAssertEqual(defaults.written, [])
        for setting in [IntakeSourceSetting.none, .appleHealth, .quickAdd] {
            settings.source = setting
            XCTAssertEqual(stored(defaults, IntakeSettings.sourceKey), setting.rawValue)
            XCTAssertEqual(settings.source, setting)
            XCTAssertTrue(settings.hasChosenSource, "\(setting) stored is a choice, None included")
        }
    }

    // MARK: - Targets

    func testTargetsRoundTripWithSortedKeys() throws {
        let (settings, _, defaults) = try fresh()
        XCTAssertTrue(settings.setTargets(IntakeFixture.targets))
        XCTAssertEqual(stored(defaults, IntakeSettings.targetsKey),
                       #"{"energyHardFloorKcal":2100,"energyHighKcal":2600,"energyLowKcal":2400,"v":1}"#,
                       "§9.2: sorted keys and the version")
        XCTAssertEqual(settings.storedTargets, IntakeFixture.targets)
        XCTAssertFalse(settings.targetsNeedAttention)

        // Any key may be omitted.
        XCTAssertTrue(settings.setTargets(IntakeTargets(energyLowKcal: 2_400)))
        XCTAssertEqual(stored(defaults, IntakeSettings.targetsKey), #"{"energyLowKcal":2400,"v":1}"#)
        XCTAssertEqual(settings.storedTargets, IntakeTargets(energyLowKcal: 2_400))

        // An invalid range writes nothing and leaves the stored string as it was.
        let before = stored(defaults, IntakeSettings.targetsKey)
        XCTAssertFalse(settings.setTargets(IntakeTargets(energyLowKcal: 2_600, energyHighKcal: 2_400)))
        XCTAssertFalse(settings.setTargets(IntakeTargets(energyLowKcal: 2_400, energyHighKcal: 2_600,
                                                         energyHardFloorKcal: 2_500)))
        XCTAssertFalse(settings.setTargets(IntakeTargets(energyLowKcal: .nan)))
        XCTAssertEqual(stored(defaults, IntakeSettings.targetsKey), before)
    }

    func testUnreadableTargetsAreTreatedAsAbsentAndNotRewritten() throws {
        let unreadable = ["not json", #"{"energyLowKcal":"2400","v":1}"#,
                          #"{"energyHighKcal":2400,"energyLowKcal":2600,"v":1}"#,
                          #"{"energyHardFloorKcal":2500,"energyLowKcal":2400,"v":1}"#,
                          #"{"energyLowKcal":-5,"v":1}"#, "[]"]
        for raw in unreadable {
            let (settings, scorecard, defaults) = try fresh()
            var parameters = CutScorecardParameters.generic
            parameters.proteinFloorGrams = 100
            scorecard.parameters = parameters
            defaults.set(raw, forKey: IntakeSettings.targetsKey)
            defaults.written = []
            XCTAssertNil(settings.storedTargets, raw)
            XCTAssertTrue(settings.targetsNeedAttention, raw)
            XCTAssertEqual(settings.targets(on: "2031-01-29"), IntakeTargets(proteinFloorGrams: 100),
                           "the range is treated as absent; the floor still reads: \(raw)")
            XCTAssertEqual(stored(defaults, IntakeSettings.targetsKey), raw, "never rewritten by a read")
            XCTAssertEqual(defaults.written, [], raw)
        }
    }

    func testTargetsAreTheSameOnEveryDay() throws {
        let (settings, scorecard, _) = try fresh()
        var parameters = CutScorecardParameters.generic
        parameters.proteinFloorGrams = 100
        scorecard.parameters = parameters
        XCTAssertTrue(settings.setTargets(IntakeFixture.targets))
        let expected = IntakeTargets(proteinFloorGrams: 100, energyLowKcal: 2_400, energyHighKcal: 2_600,
                                     energyHardFloorKcal: 2_100)
        for day in ["2030-12-09", "2031-01-06", "2031-01-29", "2031-02-12", "1970-01-01", "9999-12-31",
                    "2031-02-30", "", "not a day", "2031-1-6"] {
            XCTAssertEqual(settings.targets(on: day), expected, "day \(day)")
        }
    }

    func testSetTargetsNeverWritesAProteinKey() throws {
        let (settings, scorecard, defaults) = try fresh()
        var targets = IntakeFixture.targets
        targets.proteinFloorGrams = 140
        XCTAssertTrue(settings.setTargets(targets))
        let raw = try XCTUnwrap(stored(defaults, IntakeSettings.targetsKey))
        XCTAssertFalse(raw.lowercased().contains("protein"), raw)
        XCTAssertNil(scorecard.parameters.proteinFloorGrams, "the floor is not set through the targets")
        XCTAssertNil(settings.proteinFloorGrams)
        XCTAssertEqual(settings.storedTargets?.proteinFloorGrams, nil)
    }

    // MARK: - The source and the Health read

    func testHealthReadEnabledNeedsBothTheFlagAndTheSource() throws {
        let (settings, _, _) = try fresh()
        for flag in [false, true] {
            for source in [IntakeSourceSetting.none, .appleHealth, .quickAdd] {
                settings.isEnabled = flag
                settings.source = source
                XCTAssertEqual(settings.healthReadEnabled, flag && source == .appleHealth, "flag \(flag), \(source)")
            }
        }
    }

    // MARK: - The flag

    func testReadingTheFlagWritesNothing() throws {
        let (settings, _, defaults) = try fresh()
        for _ in 0..<3 {
            _ = settings.isEnabled
            _ = settings.healthReadEnabled
            _ = settings.source
        }
        let observed = ObservableDefaultsFlag(key: IntakeSettings.enabledKey, defaults: defaults)
        XCTAssertFalse(observed.isEnabled)
        XCTAssertEqual(defaults.written, [])
        XCTAssertNil(defaults.object(forKey: IntakeSettings.enabledKey), "the key stays absent")
    }

    func testTheFlagIsAnObservableDefaultsFlagOverTheIntakeKey() throws {
        let (settings, _, defaults) = try fresh()
        let flag = ObservableDefaultsFlag(key: IntakeSettings.enabledKey, defaults: defaults)
        XCTAssertEqual(flag.key, "noop.intakeEnabled")
        settings.isEnabled = true
        XCTAssertTrue(flag.isEnabled, "the observable copy follows a write made through the settings")
        flag.set(false)
        XCTAssertFalse(settings.isEnabled, "and the settings read back a write made through the flag")
        flag.set(true)
        XCTAssertTrue(settings.isEnabled)
        // The app's one observable copy is an ObservableDefaultsFlag over the same key.
        XCTAssertEqual(IntakeSettings.flag.key, IntakeSettings.enabledKey)
        XCTAssertTrue((IntakeSettings.flag as AnyObject) is ObservableDefaultsFlag)
    }

    // MARK: - The protein floor (one home: stage 1 R45)

    func testFloorSetterWritesThroughTheScorecardSetter() throws {
        let (settings, scorecard, defaults) = try fresh()
        XCTAssertTrue(settings.setProteinFloorGrams(100))
        XCTAssertEqual(scorecard.parameters.proteinFloorGrams, 100)
        XCTAssertEqual(scorecard.proteinFloorWholeGrams, 100)
        XCTAssertEqual(settings.proteinFloorGrams, 100)
        XCTAssertNotNil(stored(defaults, CutScorecardSettings.rulesKey))

        XCTAssertTrue(settings.setProteinFloorGrams(nil))
        XCTAssertNil(scorecard.parameters.proteinFloorGrams)
        XCTAssertNil(settings.proteinFloorGrams)
        let raw = try XCTUnwrap(stored(defaults, CutScorecardSettings.rulesKey))
        XCTAssertFalse(raw.contains("proteinFloorGrams"), "nil clears the floor: \(raw)")
        XCTAssertFalse(defaults.written.contains { $0.hasPrefix("intake.") },
                       "the floor is stored nowhere under intake.*")
    }

    func testFloorSetterWritesThroughTheScorecardSetterWhateverTheScorecardFlag() throws {
        for scorecardFlag in [false, true] {
            let (settings, scorecard, defaults) = try fresh()
            defaults.set(scorecardFlag, forKey: CutScorecardSettings.enabledKey)
            XCTAssertTrue(settings.setProteinFloorGrams(120))
            XCTAssertEqual(scorecard.parameters.proteinFloorGrams, 120, "scorecard flag \(scorecardFlag)")
        }
    }

    func testFloorSetterAcceptsExactlyWhatStageOnesRuleAccepts() throws {
        let values: [Double] = [1, 100, 100_000, 0, 0.5, 99.4, 99.5, -5, 100_001, .nan, .infinity, -.infinity]
        for value in values {
            let (settings, scorecard, defaults) = try fresh()
            var parameters = CutScorecardParameters.generic
            parameters.proteinFloorGrams = 80
            scorecard.parameters = parameters
            let before = stored(defaults, CutScorecardSettings.rulesKey)
            let accepted = settings.setProteinFloorGrams(value)
            XCTAssertEqual(accepted, CutScorecardSettings.isWholeGramProteinFloor(value), "value \(value)")
            if accepted {
                XCTAssertEqual(scorecard.parameters.proteinFloorGrams, value, "value \(value)")
            } else {
                XCTAssertEqual(stored(defaults, CutScorecardSettings.rulesKey), before,
                               "a refused value leaves the rules string byte-identical: \(value)")
                XCTAssertEqual(scorecard.parameters.proteinFloorGrams, 80, "value \(value)")
            }
        }
        // The rule's own boundaries, as stage 1 states them (§9.2): 1 to 100 000 whole grams.
        XCTAssertEqual(CutScorecardSettings.proteinFloorMaximumGrams, 100_000)
    }

    func testAFractionalFloorStoredEarlierReadsWholeThroughIntakeSettings() throws {
        let (settings, scorecard, defaults) = try fresh()
        let raw = #"{"proteinFloorGrams":99.4,"v":1}"#
        defaults.set(raw, forKey: CutScorecardSettings.rulesKey)
        defaults.written = []
        XCTAssertEqual(settings.proteinFloorGrams, 99)
        XCTAssertEqual(settings.targets(on: "2031-01-29").proteinFloorGrams, 99)
        XCTAssertEqual(scorecard.proteinFloorWholeGrams, 99)
        XCTAssertEqual(stored(defaults, CutScorecardSettings.rulesKey), raw, "byte-equal after every getter")
        XCTAssertEqual(defaults.written, [])
    }

    // MARK: - Zone log, Health sources, backfill

    func testZoneLogRoundTripsAsTheDocumentedJson() throws {
        let (settings, _, defaults) = try fresh()
        let log = [IntakeZoneSegment(fromEpochSeconds: 0, zoneIdentifier: "Etc/UTC"),
                   IntakeZoneSegment(fromEpochSeconds: 1_923_501_600, zoneIdentifier: "Pacific/Auckland")]
        settings.zoneLog = log
        XCTAssertEqual(settings.zoneLog, log)
        let raw = try XCTUnwrap(stored(defaults, IntakeSettings.zoneLogKey))
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: Any]])
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded.first?["from"] as? Int, 0)
        XCTAssertEqual(decoded.first?["tz"] as? String, "Etc/UTC")
        XCTAssertEqual(decoded.last?["from"] as? Int, 1_923_501_600)
        XCTAssertEqual(decoded.last?["tz"] as? String, "Pacific/Auckland")

        // An unreadable stored log reads as empty and is not rewritten.
        defaults.set("[{]", forKey: IntakeSettings.zoneLogKey)
        defaults.written = []
        XCTAssertEqual(settings.zoneLog, [])
        XCTAssertEqual(stored(defaults, IntakeSettings.zoneLogKey), "[{]")
        XCTAssertEqual(defaults.written, [])
    }

    func testAdmittedSourcesAndKnownSourcesRoundTrip() throws {
        let (settings, _, defaults) = try fresh()
        settings.admittedHealthSources = [IntakeFixture.foodApp.bundleId]
        XCTAssertEqual(settings.admittedHealthSources, [IntakeFixture.foodApp.bundleId])
        settings.admittedHealthSources = nil
        XCTAssertNil(settings.admittedHealthSources)
        XCTAssertNil(defaults.object(forKey: IntakeSettings.healthSourcesKey), "nil: every source, stored as absent")

        settings.recordHealthSource(bundleId: IntakeFixture.foodApp.bundleId, name: IntakeFixture.foodApp.name,
                                    day: "2030-12-09")
        settings.recordHealthSource(bundleId: IntakeFixture.foodApp.bundleId, name: IntakeFixture.foodApp.name,
                                    day: "2030-12-10")
        settings.recordHealthSource(bundleId: IntakeFixture.otherApp.bundleId, name: IntakeFixture.otherApp.name,
                                    day: "2030-12-09")
        XCTAssertEqual(settings.knownHealthSources, [
            IntakeFixture.foodApp.bundleId: IntakeSettings.KnownSource(name: "Fixture Food", lastSeenDay: "2030-12-10"),
            IntakeFixture.otherApp.bundleId: IntakeSettings.KnownSource(name: "Fixture Other", lastSeenDay: "2030-12-09"),
        ])
        let raw = try XCTUnwrap(stored(defaults, IntakeSettings.healthKnownSourcesKey))
        XCTAssertTrue(raw.contains(#""lastSeenDay":"2030-12-10""#), raw)

        XCTAssertFalse(settings.healthBackfilled)
        settings.healthBackfilled = true
        XCTAssertTrue(defaults.bool(forKey: IntakeSettings.healthBackfilledKey))
    }

    // MARK: - Supplements

    func testSupplementListHoldsAtMostFourAndNoDuplicates() throws {
        let (settings, _, defaults) = try fresh()
        let questions = (1...4).map { "Did you take Fixture supplement \($0)?" }
        for question in questions { XCTAssertTrue(settings.addSupplementQuestion(question)) }
        XCTAssertEqual(settings.supplementQuestions, questions, "display order is the order added")

        let full = stored(defaults, IntakeSettings.supplementQuestionsKey)
        defaults.written = []
        XCTAssertFalse(settings.addSupplementQuestion("Did you take Fixture supplement 5?"), "the list is full")
        XCTAssertFalse(settings.addSupplementQuestion(questions[1]), "already listed")
        XCTAssertEqual(defaults.written, [], "a refused add writes nothing")
        XCTAssertEqual(stored(defaults, IntakeSettings.supplementQuestionsKey), full)

        settings.removeSupplementQuestion(questions[1])
        XCTAssertEqual(settings.supplementQuestions, [questions[0], questions[2], questions[3]])
        XCTAssertTrue(settings.addSupplementQuestion(questions[1]))
        XCTAssertEqual(settings.supplementQuestions.count, 4)

        // A hand-edited list longer than four reads as its first four.
        defaults.set(try String(data: JSONEncoder().encode((1...6).map { "Q\($0)?" }), encoding: .utf8),
                     forKey: IntakeSettings.supplementQuestionsKey)
        XCTAssertEqual(settings.supplementQuestions, ["Q1?", "Q2?", "Q3?", "Q4?"])
    }

    // MARK: - Cutoff and presets

    func testCutoffMinuteIsClampedOnWrite() throws {
        let (settings, _, defaults) = try fresh()
        settings.cutoffMinuteOfDay = IntakeFixture.cutoffMinute
        XCTAssertEqual(settings.cutoffMinuteOfDay, 1_200)
        settings.cutoffMinuteOfDay = -30
        XCTAssertEqual(settings.cutoffMinuteOfDay, 0)
        settings.cutoffMinuteOfDay = 1_440
        XCTAssertEqual(settings.cutoffMinuteOfDay, 1_439)
        XCTAssertEqual(defaults.integer(forKey: IntakeSettings.cutoffMinuteOfDayKey), 1_439)
        settings.cutoffTimeSet = true
        settings.cutoffEnabled = true
        XCTAssertTrue(settings.cutoffTimeSet)
        XCTAssertTrue(settings.cutoffEnabled)
    }

    func testPresetsHoldAtMostSixAndRoundTrip() throws {
        let (settings, _, defaults) = try fresh()
        let shake = IntakeSettings.Preset(label: IntakeFixture.preset.label, proteinGrams: 30, energyKcal: 150)
        settings.quickAddPresets = [shake]
        XCTAssertEqual(settings.quickAddPresets, [shake])
        let raw = try XCTUnwrap(stored(defaults, IntakeSettings.quickAddPresetsKey))
        XCTAssertTrue(raw.contains(#""label":"Fixture shake""#), raw)

        settings.quickAddPresets = (1...8).map { IntakeSettings.Preset(label: "P\($0)", proteinGrams: Double($0), energyKcal: nil) }
        XCTAssertEqual(settings.quickAddPresets.map(\.label), ["P1", "P2", "P3", "P4", "P5", "P6"])
    }

    // MARK: - No caching

    func testGettersReadTheDefaultsAtEachAccess() throws {
        let (settings, _, defaults) = try fresh()
        XCTAssertFalse(settings.isEnabled)
        defaults.set(true, forKey: IntakeSettings.enabledKey)
        XCTAssertTrue(settings.isEnabled, "a restored backup is seen by the next read")
        defaults.set("quickAdd", forKey: IntakeSettings.sourceKey)
        XCTAssertEqual(settings.source, .quickAdd)
        defaults.set(#"{"energyLowKcal":2400,"v":1}"#, forKey: IntakeSettings.targetsKey)
        XCTAssertEqual(settings.storedTargets, IntakeTargets(energyLowKcal: 2_400))
    }
}
