import XCTest
import StrandAnalytics
@testable import Strand

// Stage 1 (weigh-in and scorecard), specification §9.2 and §12.3. Written before the implementation
// exists, from the specification.
//
// API ASSUMED BY THESE TESTS
//
//     /// One element of `cutScorecard.phases`.
//     struct CutScorecardStoredPhase: Equatable {
//         enum Kind: String { case cut, other }
//         var kind: Kind
//         var name: String
//         var startDay: String                    // "yyyy-MM-dd"
//         var targetWeightKg: Double?             // omitted from the JSON when nil
//         var rateLowPercentPerWeek: Double
//         var rateHighPercentPerWeek: Double
//         init(kind: Kind, name: String, startDay: String, targetWeightKg: Double?,
//              rateLowPercentPerWeek: Double, rateHighPercentPerWeek: Double)
//     }
//
//     /// A reference type (or a struct with nonmutating setters): a `let` instance can be written through.
//     final class CutScorecardSettings {
//         static let enabledKey = "noop.cutScorecardEnabled"
//         static let phasesKey = "cutScorecard.phases"
//         static let rulesKey = "cutScorecard.rules"
//         static let reminderEnabledKey = "cutScorecard.reminder.enabled"
//         static let reminderWeekdayKey = "cutScorecard.reminder.weekday"
//         static let reminderMinuteOfDayKey = "cutScorecard.reminder.minuteOfDay"
//
//         init(defaults: UserDefaults = .standard)
//
//         var isEnabled: Bool { get set }                         // default false
//         var reminderEnabled: Bool { get set }                   // default false
//         var reminderWeekday: Int { get set }                    // default 7 (1 = Sunday ... 7 = Saturday)
//         var reminderMinuteOfDay: Int { get set }                // default 480
//
//         /// Stored ascending by `startDay`, as a JSON array with sorted keys and `"v":1` per element.
//         var phases: [CutScorecardStoredPhase] { get set }       // absent or unreadable: []
//         /// The element with the greatest `startDay` on or before `today`.
//         func activePhase(on today: String) -> CutScorecardStoredPhase?
//         /// What `CutScorecardInput.phase` receives: the active phase when its kind is `cut`, else nil.
//         func evaluationPhase(on today: String) -> CutScorecardPhase?
//
//         /// The stored rules with the generic default for every missing key; `.generic` when the
//         /// string is absent, unreadable or fails the validation of specification §6.5.
//         var parameters: CutScorecardParameters { get set }
//         /// True when a rules string is stored and cannot be used (the "rules need attention" state).
//         /// False when no rules string is stored at all.
//         var rulesNeedAttention: Bool { get }
//     }
//
// Readings of §9.2 that the specification leaves unstated, as these tests take them:
//
//  1. Settings are read from the injected defaults at each access; nothing is cached, so a string
//     written under a key by a backup restore is seen by the next read.
//  2. A rules value of the wrong JSON type for its key (a string where a number belongs, a fractional
//     number where an integer belongs) is a parse failure: absent, and "needs attention".
//  3. A `cutScorecard.phases` string that cannot be read yields no phases and no crash. The
//     specification states the "treated as absent" rule for the rules string only.
//  4. The tests do not pin the number formatting of the stored strings (`94.0` against `94`): they
//     pin the key set, the key order, the version field and that equal settings give equal bytes.
//
// Synthetic values only: the "Fixture Person" of specification §13.1.
final class CutScorecardSettingsTests: XCTestCase {

    // MARK: - Harness

    private var suites: [String] = []

    override func tearDown() {
        for name in suites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        suites = []
        super.tearDown()
    }

    private func freshDefaults() throws -> UserDefaults {
        let name = "CutScorecardSettingsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        suites.append(name)
        return defaults
    }

    private let fixtureCut = CutScorecardStoredPhase(kind: .cut, name: "Fixture cut", startDay: "2031-01-06",
                                                     targetWeightKg: 94.0, rateLowPercentPerWeek: 0.4,
                                                     rateHighPercentPerWeek: 1.2)

    /// The parameters of specification §13.1. They differ from the generic defaults in several fields
    /// on purpose, so a round trip that returns them proves they were stored and read.
    private let fixtureParameters = CutScorecardParameters(
        rateWindowWeeks: 4, waistWindowWeeks: 2, waistMinDecreaseCm: 0.5, liftDropTolerancePercent: 5,
        liftDropShare: 0.5, liftDropConsecutiveWeeks: 3, addCaloriesKcal: 300,
        slowLossThresholdKgPerWeek: 0.4, slowLossConsecutiveWeeks: 3, reduceCarbsKcal: 250,
        proteinFloorGrams: 100, proteinMinDaysPerWeek: 5, maxWeighInAgeWeeks: 1, maxProjectionWeeks: 104,
        targetToleranceKg: 0)

    private let parameterKeys = ["addCaloriesKcal", "liftDropConsecutiveWeeks", "liftDropShare",
                                 "liftDropTolerancePercent", "maxProjectionWeeks", "maxWeighInAgeWeeks",
                                 "proteinFloorGrams", "proteinMinDaysPerWeek", "rateWindowWeeks",
                                 "reduceCarbsKcal", "slowLossConsecutiveWeeks", "slowLossThresholdKgPerWeek",
                                 "targetToleranceKg", "waistMinDecreaseCm", "waistWindowWeeks"]

    /// Asserts that the given JSON keys appear in `text` in ascending order, each exactly once.
    private func assertKeysAscending(_ keys: [String], in text: String,
                                     file: StaticString = #filePath, line: UInt = #line) {
        var last = text.startIndex
        for key in keys.sorted() {
            let quoted = "\"\(key)\":"
            guard let range = text.range(of: quoted) else {
                XCTFail("key \(key) is missing from \(text)", file: file, line: line)
                return
            }
            XCTAssertGreaterThanOrEqual(range.lowerBound, last, "key \(key) is out of order in \(text)", file: file, line: line)
            XCTAssertNil(text.range(of: quoted, range: range.upperBound..<text.endIndex),
                         "key \(key) appears twice in \(text)", file: file, line: line)
            last = range.lowerBound
        }
    }

    // MARK: - Keys and defaults

    func testKeysAreTheOnesTheSpecificationNames() {
        XCTAssertEqual(CutScorecardSettings.enabledKey, "noop.cutScorecardEnabled")
        XCTAssertEqual(CutScorecardSettings.phasesKey, "cutScorecard.phases")
        XCTAssertEqual(CutScorecardSettings.rulesKey, "cutScorecard.rules")
        XCTAssertEqual(CutScorecardSettings.reminderEnabledKey, "cutScorecard.reminder.enabled")
        XCTAssertEqual(CutScorecardSettings.reminderWeekdayKey, "cutScorecard.reminder.weekday")
        XCTAssertEqual(CutScorecardSettings.reminderMinuteOfDayKey, "cutScorecard.reminder.minuteOfDay")
    }

    func testFlagDefaultsToOff() throws {
        let defaults = try freshDefaults()
        let settings = CutScorecardSettings(defaults: defaults)
        XCTAssertFalse(settings.isEnabled)
        XCTAssertNil(defaults.object(forKey: "noop.cutScorecardEnabled"), "reading the flag must not write it")
    }

    func testFlagRoundTripsThroughItsKey() throws {
        let defaults = try freshDefaults()
        let settings = CutScorecardSettings(defaults: defaults)
        settings.isEnabled = true
        XCTAssertEqual(defaults.object(forKey: "noop.cutScorecardEnabled") as? Bool, true)
        XCTAssertTrue(CutScorecardSettings(defaults: defaults).isEnabled)
        settings.isEnabled = false
        XCTAssertFalse(CutScorecardSettings(defaults: defaults).isEnabled)

        // Written from outside (the Settings toggle, a test), it is seen by an existing instance.
        defaults.set(true, forKey: "noop.cutScorecardEnabled")
        XCTAssertTrue(settings.isEnabled)
    }

    func testReminderDefaultsAndRoundTrip() throws {
        let defaults = try freshDefaults()
        let settings = CutScorecardSettings(defaults: defaults)
        XCTAssertFalse(settings.reminderEnabled, "the reminder is off by default")
        XCTAssertEqual(settings.reminderWeekday, 7, "Saturday, in the 1 = Sunday numbering")
        XCTAssertEqual(settings.reminderMinuteOfDay, 480, "08:00")

        settings.reminderEnabled = true
        settings.reminderWeekday = 4
        settings.reminderMinuteOfDay = 390
        XCTAssertEqual(defaults.object(forKey: "cutScorecard.reminder.enabled") as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: "cutScorecard.reminder.weekday") as? Int, 4)
        XCTAssertEqual(defaults.object(forKey: "cutScorecard.reminder.minuteOfDay") as? Int, 390)
        let reread = CutScorecardSettings(defaults: defaults)
        XCTAssertTrue(reread.reminderEnabled)
        XCTAssertEqual(reread.reminderWeekday, 4)
        XCTAssertEqual(reread.reminderMinuteOfDay, 390)
    }

    func testEverythingIsAbsentOnAFreshInstall() throws {
        let defaults = try freshDefaults()
        let settings = CutScorecardSettings(defaults: defaults)
        XCTAssertTrue(settings.phases.isEmpty)
        XCTAssertNil(settings.activePhase(on: "2031-01-08"))
        XCTAssertNil(settings.evaluationPhase(on: "2031-01-08"))
        XCTAssertEqual(settings.parameters, .generic)
        XCTAssertFalse(settings.rulesNeedAttention, "no rules stored is not 'rules need attention'")
        XCTAssertNil(defaults.object(forKey: "cutScorecard.phases"), "reading must not write")
        XCTAssertNil(defaults.object(forKey: "cutScorecard.rules"))
    }

    /// The settings under test live in the injected defaults and never in the standard ones.
    func testSettingsNeverTouchTheStandardDefaults() throws {
        let keys = [CutScorecardSettings.enabledKey, CutScorecardSettings.phasesKey, CutScorecardSettings.rulesKey,
                    CutScorecardSettings.reminderEnabledKey, CutScorecardSettings.reminderWeekdayKey,
                    CutScorecardSettings.reminderMinuteOfDayKey]
        let before = keys.map { UserDefaults.standard.object(forKey: $0).map { "\($0)" } }
        let settings = CutScorecardSettings(defaults: try freshDefaults())
        settings.isEnabled = true
        settings.phases = [fixtureCut]
        settings.parameters = fixtureParameters
        settings.reminderEnabled = true
        settings.reminderWeekday = 2
        settings.reminderMinuteOfDay = 600
        let after = keys.map { UserDefaults.standard.object(forKey: $0).map { "\($0)" } }
        XCTAssertEqual(after, before)
    }

    // MARK: - Phases

    func testPhasesRoundTripWithSortedKeys() throws {
        let defaults = try freshDefaults()
        let settings = CutScorecardSettings(defaults: defaults)
        settings.phases = [fixtureCut]

        XCTAssertEqual(settings.phases, [fixtureCut])
        XCTAssertEqual(CutScorecardSettings(defaults: defaults).phases, [fixtureCut], "read back by a new instance")

        let raw = try XCTUnwrap(defaults.string(forKey: "cutScorecard.phases"), "stored as a String")
        assertKeysAscending(["kind", "name", "rateHighPercentPerWeek", "rateLowPercentPerWeek", "startDay",
                             "targetWeightKg", "v"], in: raw)

        let array = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: Any]])
        XCTAssertEqual(array.count, 1)
        let element = try XCTUnwrap(array.first)
        XCTAssertEqual(Set(element.keys), ["kind", "name", "rateHighPercentPerWeek", "rateLowPercentPerWeek",
                                           "startDay", "targetWeightKg", "v"])
        XCTAssertEqual(element["kind"] as? String, "cut")
        XCTAssertEqual(element["name"] as? String, "Fixture cut")
        XCTAssertEqual(element["startDay"] as? String, "2031-01-06")
        XCTAssertEqual(element["targetWeightKg"] as? Double, 94.0)
        XCTAssertEqual(element["rateLowPercentPerWeek"] as? Double, 0.4)
        XCTAssertEqual(element["rateHighPercentPerWeek"] as? Double, 1.2)
        XCTAssertEqual(element["v"] as? Int, 1)
    }

    /// The documented element (specification §9.2), written under the key by something else — a
    /// backup restore, the Android side — is read as the fixture phase.
    func testTheDocumentedPhaseStringIsRead() throws {
        let defaults = try freshDefaults()
        let documented = "[{\"kind\":\"cut\",\"name\":\"Fixture cut\",\"rateHighPercentPerWeek\":1.2,"
            + "\"rateLowPercentPerWeek\":0.4,\"startDay\":\"2031-01-06\",\"targetWeightKg\":94.0,\"v\":1}]"
        defaults.set(documented, forKey: "cutScorecard.phases")
        let settings = CutScorecardSettings(defaults: defaults)
        XCTAssertEqual(settings.phases, [fixtureCut])
        XCTAssertEqual(settings.evaluationPhase(on: "2031-01-08"),
                       CutScorecardPhase(name: "Fixture cut", startDay: "2031-01-06", targetWeightKg: 94.0,
                                         rateLowPercentPerWeek: 0.4, rateHighPercentPerWeek: 1.2))
    }

    func testPhaseWithoutATargetOmitsTheKey() throws {
        let defaults = try freshDefaults()
        let settings = CutScorecardSettings(defaults: defaults)
        var noTarget = fixtureCut
        noTarget.targetWeightKg = nil
        settings.phases = [noTarget]

        let raw = try XCTUnwrap(defaults.string(forKey: "cutScorecard.phases"))
        XCTAssertFalse(raw.contains("targetWeightKg"), "an absent target is omitted, not written as null or 0: \(raw)")
        XCTAssertEqual(settings.phases, [noTarget])
        XCTAssertNil(settings.evaluationPhase(on: "2031-01-08")?.targetWeightKg)
    }

    func testPhasesAreStoredAscendingByStartDay() throws {
        let defaults = try freshDefaults()
        let settings = CutScorecardSettings(defaults: defaults)
        let maintenance = CutScorecardStoredPhase(kind: .other, name: "Fixture maintenance", startDay: "2031-06-09",
                                                  targetWeightKg: nil, rateLowPercentPerWeek: 0, rateHighPercentPerWeek: 0)
        let earlier = CutScorecardStoredPhase(kind: .cut, name: "Fixture first cut", startDay: "2030-09-02",
                                              targetWeightKg: 98.0, rateLowPercentPerWeek: 0.25, rateHighPercentPerWeek: 0.75)
        settings.phases = [maintenance, fixtureCut, earlier]

        XCTAssertEqual(settings.phases.map(\.startDay), ["2030-09-02", "2031-01-06", "2031-06-09"])
        XCTAssertEqual(settings.phases.map(\.name), ["Fixture first cut", "Fixture cut", "Fixture maintenance"])
        let raw = try XCTUnwrap(defaults.string(forKey: "cutScorecard.phases"))
        let array = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [[String: Any]])
        XCTAssertEqual(array.compactMap { $0["startDay"] as? String }, ["2030-09-02", "2031-01-06", "2031-06-09"],
                       "the stored array itself is ascending")
        XCTAssertEqual(array.compactMap { $0["kind"] as? String }, ["cut", "cut", "other"])
    }

    /// "Both strings are written with sorted keys so that the same settings give the same bytes."
    func testTheSameSettingsGiveTheSameBytes() throws {
        let maintenance = CutScorecardStoredPhase(kind: .other, name: "Fixture maintenance", startDay: "2031-06-09",
                                                  targetWeightKg: nil, rateLowPercentPerWeek: 0, rateHighPercentPerWeek: 0)
        let first = try freshDefaults()
        let second = try freshDefaults()
        let a = CutScorecardSettings(defaults: first)
        let b = CutScorecardSettings(defaults: second)

        a.phases = [fixtureCut, maintenance]
        a.parameters = fixtureParameters
        // The other instance receives them in another order, twice over.
        b.parameters = .generic
        b.phases = [maintenance]
        b.phases = [maintenance, fixtureCut]
        b.parameters = fixtureParameters

        XCTAssertEqual(first.string(forKey: "cutScorecard.phases"), second.string(forKey: "cutScorecard.phases"))
        XCTAssertEqual(first.string(forKey: "cutScorecard.rules"), second.string(forKey: "cutScorecard.rules"))

        // Writing what was read changes no byte.
        let phasesBytes = try XCTUnwrap(first.string(forKey: "cutScorecard.phases"))
        let rulesBytes = try XCTUnwrap(first.string(forKey: "cutScorecard.rules"))
        a.phases = a.phases
        a.parameters = a.parameters
        XCTAssertEqual(first.string(forKey: "cutScorecard.phases"), phasesBytes)
        XCTAssertEqual(first.string(forKey: "cutScorecard.rules"), rulesBytes)
    }

    func testActivePhaseIsTheLatestStartedOnOrBeforeToday() throws {
        let settings = CutScorecardSettings(defaults: try freshDefaults())
        let earlier = CutScorecardStoredPhase(kind: .cut, name: "Fixture first cut", startDay: "2030-09-02",
                                              targetWeightKg: 98.0, rateLowPercentPerWeek: 0.25, rateHighPercentPerWeek: 0.75)
        let later = CutScorecardStoredPhase(kind: .cut, name: "Fixture later cut", startDay: "2031-09-01",
                                            targetWeightKg: 90.0, rateLowPercentPerWeek: 0.3, rateHighPercentPerWeek: 0.9)
        settings.phases = [later, earlier, fixtureCut]

        XCTAssertNil(settings.activePhase(on: "2030-09-01"), "no phase has started yet")
        XCTAssertEqual(settings.activePhase(on: "2030-09-02")?.name, "Fixture first cut", "the start day itself counts")
        XCTAssertEqual(settings.activePhase(on: "2031-01-05")?.name, "Fixture first cut")
        XCTAssertEqual(settings.activePhase(on: "2031-01-06")?.name, "Fixture cut")
        XCTAssertEqual(settings.activePhase(on: "2031-08-31")?.name, "Fixture cut")
        XCTAssertEqual(settings.activePhase(on: "2031-09-01")?.name, "Fixture later cut")
        XCTAssertEqual(settings.activePhase(on: "2040-01-01")?.name, "Fixture later cut")
        XCTAssertNil(settings.evaluationPhase(on: "2030-09-01"))
        XCTAssertEqual(settings.evaluationPhase(on: "2031-01-08")?.name, "Fixture cut")
    }

    func testCutPhaseBecomesTheEvaluationPhaseFieldForField() throws {
        let settings = CutScorecardSettings(defaults: try freshDefaults())
        settings.phases = [fixtureCut]
        XCTAssertEqual(settings.evaluationPhase(on: "2031-01-08"),
                       CutScorecardPhase(name: "Fixture cut", startDay: "2031-01-06", targetWeightKg: 94.0,
                                         rateLowPercentPerWeek: 0.4, rateHighPercentPerWeek: 1.2))
    }

    /// A phase of any other kind produces no verdict: the function is passed nil, and an earlier cut
    /// is not resurrected in its place.
    func testNonCutPhaseYieldsNoPhaseForEvaluation() throws {
        let settings = CutScorecardSettings(defaults: try freshDefaults())
        let maintenance = CutScorecardStoredPhase(kind: .other, name: "Fixture maintenance", startDay: "2031-06-09",
                                                  targetWeightKg: nil, rateLowPercentPerWeek: 0, rateHighPercentPerWeek: 0)
        settings.phases = [fixtureCut, maintenance]

        XCTAssertEqual(settings.evaluationPhase(on: "2031-06-08")?.name, "Fixture cut", "the cut is active until the day before")
        XCTAssertEqual(settings.activePhase(on: "2031-06-09")?.kind, .other)
        XCTAssertNil(settings.evaluationPhase(on: "2031-06-09"))
        XCTAssertNil(settings.evaluationPhase(on: "2031-12-31"), "the earlier cut must not be used once another phase is active")
        XCTAssertEqual(settings.phases.count, 2, "the previous phase stays in the stored list")
    }

    /// Assumption 3 at the top of this file.
    func testUnreadablePhasesYieldNoPhases() throws {
        for garbage in ["not json", "{\"kind\":\"cut\"}", "[1,2,3]", "", "[{\"kind\":\"cut\"}]"] {
            let defaults = try freshDefaults()
            defaults.set(garbage, forKey: "cutScorecard.phases")
            let settings = CutScorecardSettings(defaults: defaults)
            XCTAssertTrue(settings.phases.isEmpty, "phases string \(garbage.debugDescription)")
            XCTAssertNil(settings.activePhase(on: "2031-01-08"))
            XCTAssertNil(settings.evaluationPhase(on: "2031-01-08"))
            XCTAssertEqual(defaults.string(forKey: "cutScorecard.phases"), garbage,
                           "reading an unreadable string must not overwrite it")
        }
    }

    // MARK: - Rules

    func testRulesRoundTripAndMissingKeysTakeDefaults() throws {
        let defaults = try freshDefaults()
        let settings = CutScorecardSettings(defaults: defaults)
        settings.parameters = fixtureParameters

        XCTAssertEqual(settings.parameters, fixtureParameters)
        XCTAssertEqual(CutScorecardSettings(defaults: defaults).parameters, fixtureParameters)
        XCTAssertFalse(settings.rulesNeedAttention)

        let raw = try XCTUnwrap(defaults.string(forKey: "cutScorecard.rules"), "stored as a String")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(parameterKeys + ["v"]),
                       "the keys are the property names of CutScorecardParameters, plus v")
        XCTAssertEqual(object["v"] as? Int, 1)
        XCTAssertEqual(object["addCaloriesKcal"] as? Int, 300)
        XCTAssertEqual(object["slowLossThresholdKgPerWeek"] as? Double, 0.4)
        XCTAssertEqual(object["proteinFloorGrams"] as? Double, 100)
        assertKeysAscending(parameterKeys + ["v"], in: raw)

        // A missing key takes the generic default; the keys present are honoured.
        let partial = try freshDefaults()
        partial.set("{\"rateWindowWeeks\":6,\"reduceCarbsKcal\":150,\"v\":1}", forKey: "cutScorecard.rules")
        let partialSettings = CutScorecardSettings(defaults: partial)
        var expected = CutScorecardParameters.generic
        expected.rateWindowWeeks = 6
        expected.reduceCarbsKcal = 150
        XCTAssertEqual(partialSettings.parameters, expected)
        XCTAssertFalse(partialSettings.rulesNeedAttention)
        XCTAssertNil(partialSettings.parameters.proteinFloorGrams, "a missing protein floor is 'no floor configured'")

        // An object with only the version is every default.
        let empty = try freshDefaults()
        empty.set("{\"v\":1}", forKey: "cutScorecard.rules")
        XCTAssertEqual(CutScorecardSettings(defaults: empty).parameters, .generic)
        XCTAssertFalse(CutScorecardSettings(defaults: empty).rulesNeedAttention)
    }

    func testUnsetProteinFloorIsOmitted() throws {
        let defaults = try freshDefaults()
        let settings = CutScorecardSettings(defaults: defaults)
        var parameters = fixtureParameters
        parameters.proteinFloorGrams = nil
        settings.parameters = parameters

        let raw = try XCTUnwrap(defaults.string(forKey: "cutScorecard.rules"))
        XCTAssertFalse(raw.contains("proteinFloorGrams"), "an unset floor is omitted, not written as null or 0: \(raw)")
        XCTAssertEqual(settings.parameters, parameters)
        XCTAssertNil(settings.parameters.proteinFloorGrams)
    }

    /// A rules string that does not parse is treated as absent — the generic parameters — and is
    /// reported, so the screen shows "rules need attention" in place of a verdict built on defaults
    /// the owner did not choose.
    func testCorruptRulesAreTreatedAsAbsent() throws {
        let corrupt = ["not json", "[]", "[1,2]", "\"rules\"", "{\"rateWindowWeeks\":",
                       "{\"rateWindowWeeks\":\"four\",\"v\":1}",
                       "{\"rateWindowWeeks\":4.5,\"v\":1}",
                       "{\"liftDropShare\":true,\"v\":1}"]
        for raw in corrupt {
            let defaults = try freshDefaults()
            defaults.set(raw, forKey: "cutScorecard.rules")
            let settings = CutScorecardSettings(defaults: defaults)
            XCTAssertEqual(settings.parameters, .generic, "rules string \(raw.debugDescription)")
            XCTAssertTrue(settings.rulesNeedAttention, "rules string \(raw.debugDescription)")
            XCTAssertEqual(defaults.string(forKey: "cutScorecard.rules"), raw,
                           "reading a corrupt string must not overwrite it: the owner's intent may be recoverable")
        }
    }

    /// The same for a string that parses and fails the validation of specification §6.5: one bad
    /// field makes the whole object unusable; it is not merged field by field with the defaults.
    func testRulesThatFailValidationAreTreatedAsAbsentAndNeedAttention() throws {
        let invalid = ["{\"liftDropShare\":0,\"v\":1}",
                       "{\"liftDropShare\":1.5,\"v\":1}",
                       "{\"rateWindowWeeks\":0,\"v\":1}",
                       "{\"slowLossConsecutiveWeeks\":0,\"v\":1}",
                       "{\"liftDropTolerancePercent\":100,\"v\":1}",
                       "{\"waistMinDecreaseCm\":-0.1,\"v\":1}",
                       "{\"proteinMinDaysPerWeek\":8,\"v\":1}",
                       "{\"proteinFloorGrams\":0,\"v\":1}",
                       "{\"maxProjectionWeeks\":0,\"v\":1}",
                       "{\"addCaloriesKcal\":-100,\"rateWindowWeeks\":6,\"v\":1}"]
        for raw in invalid {
            let defaults = try freshDefaults()
            defaults.set(raw, forKey: "cutScorecard.rules")
            let settings = CutScorecardSettings(defaults: defaults)
            XCTAssertEqual(settings.parameters, .generic,
                           "rules string \(raw): a valid sibling field must not survive an invalid one")
            XCTAssertTrue(settings.rulesNeedAttention, "rules string \(raw)")
            // The generic parameters it falls back to are themselves valid input.
            let probe = CutScorecardInput(weights: [], waists: [], phase: nil, parameters: settings.parameters,
                                          today: "2031-01-08")
            XCTAssertNil(CutScorecard.evaluate(probe).invalidInput)
        }
    }

    /// Storing valid rules clears the "needs attention" state.
    func testWritingValidRulesReplacesACorruptString() throws {
        let defaults = try freshDefaults()
        defaults.set("not json", forKey: "cutScorecard.rules")
        let settings = CutScorecardSettings(defaults: defaults)
        XCTAssertTrue(settings.rulesNeedAttention)

        settings.parameters = fixtureParameters
        XCTAssertFalse(settings.rulesNeedAttention)
        XCTAssertEqual(settings.parameters, fixtureParameters)
    }

    /// The fixture parameters are valid by the pure function's own validation, so the "valid" side of
    /// the tests above is not vacuous.
    func testFixtureParametersAreValidInput() {
        let probe = CutScorecardInput(weights: [], waists: [], phase: nil, parameters: fixtureParameters,
                                      today: "2031-01-08")
        XCTAssertNil(CutScorecard.evaluate(probe).invalidInput)
        XCTAssertNotEqual(fixtureParameters, .generic)
    }
}
