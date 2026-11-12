// API ASSUMED BY THESE TESTS (packet v2: stage 2 specification §7.12; stage 5 §9.6)
//
//     @MainActor struct CoachPacketAssembler {
//         init(repository:provider:scorecardSettings:settings:now:timeZone:effortScale:identifiers:
//              intake: IntakeProvider? = nil, events: PersonalEventStore? = nil)
//     }
//     struct CoachPacketDocument { ...; var privateEventsIncluded: Bool? = nil }
//         // the captured choice the text was built with; nil when the events feature is off or the
//         // Events section is switched off
//     extension PersonalEventStore {
//         static let packetSensitiveKey = "personalEvents.packetIncludesSensitive"
//         var packetIncludesSensitive: Bool { get set }     // reads and writes at each access
//     }
//     struct CoachPacketSheetPresentation { ...; var privateEventsCaption: String? = nil
//                                             var privateEventsHint: String? = nil }
//     enum CoachPacketPresenter { static var privateEventsLeftOut, privateEventsIncluded,
//                                 privateEventsChangeInSettings: String }
//
// Stage 5 §9.6 names three of these tests for `PersonalEventStoreTests.swift` and
// `BackupSettingsTests.swift`. The packet v2 brief asks for new files, so they live here under the
// names the specification gives them.
//
// Synthetic values only. Every defaults domain is a throwaway suite.

import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

@MainActor
final class CoachPacketV2AppTests: XCTestCase {

    private let suites = CoachPacketSuites()

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    // MARK: - Harness

    /// The stage 2 harness with an events store and an intake provider over the harness's own suite.
    private struct V2 {
        let h: CoachPacketHarness
        let events: PersonalEventStore
        let intake: IntakeProvider

        func assembler(identifiers: [String] = []) -> CoachPacketAssembler {
            let now = h.clock.now
            return CoachPacketAssembler(repository: h.repo, provider: h.provider, scorecardSettings: h.scorecardSettings,
                                        settings: h.packetSettings, now: { now },
                                        timeZone: { CoachPacketHarness.utc }, effortScale: { .hundred },
                                        identifiers: { identifiers }, intake: intake, events: events)
        }
    }

    private func harness(eventsOn: Bool = true, intakeOn: Bool = true) async throws -> V2 {
        let h = try await CoachPacketHarness.empty(scorecard: false, suites: suites)
        if eventsOn { h.defaults.set(true, forKey: PersonalEventStore.enabledKey) }
        if intakeOn { h.defaults.set(true, forKey: IntakeSettings.enabledKey) }
        var counter = 0
        let events = PersonalEventStore(defaults: h.defaults, now: { Date(timeIntervalSince1970: 1_000) },
                                        makeId: { counter += 1; return String(format: "%016x", counter) })
        let intake = IntakeProvider(repository: h.repo, settings: IntakeSettings(defaults: h.defaults))
        return V2(h: h, events: events, intake: intake)
    }

    /// Two events in the range (one private, with a note) and one outside it.
    private func seedEvents(_ v: V2) throws {
        try v.events.add(kind: .travel, label: nil, startDay: v.h.clock.day(-4), endDay: v.h.clock.day(-2),
                         note: "Fixture trip", sensitive: false)
        try v.events.add(kind: .custom, label: "Fixture change", startDay: v.h.clock.day(-1), endDay: v.h.clock.day(-1),
                         note: "Fixture note", sensitive: true)
        try v.events.add(kind: .deload, label: nil, startDay: v.h.clock.day(-60), endDay: v.h.clock.day(-54),
                         note: nil, sensitive: false)
    }

    private func document(_ v: V2, identifiers: [String] = []) async throws -> CoachPacketDocument {
        try await v.h.document(v.assembler(identifiers: identifiers))
    }

    // MARK: - Events

    func testEventRowsAreStageFivesRowsForTheSameEventsAndRange() async throws {
        let v = try await harness()
        try seedEvents(v)
        for include in [false, true] {
            v.events.packetIncludesSensitive = include
            let document = try await document(v)
            let first = v.h.clock.day(-(v.h.packetSettings.rangeDays - 1))
            let expected = PersonalEvents.packetLines(events: v.events.events, firstDay: first, lastDay: v.h.today,
                                                      includeSensitive: include)
            XCTAssertEqual(CoachPacketText.section(document.text, "== EVENTS =="), expected, "include \(include)")
            let input = await v.assembler().input()
            XCTAssertEqual(input?.events, .rows(expected))
        }
    }

    func testPrivateEventsAreLeftOutUnlessTheSettingIncludesThem() async throws {
        let v = try await harness()
        try seedEvents(v)
        let off = try await document(v)
        XCTAssertFalse(off.text.contains("Fixture change"))
        XCTAssertFalse(off.text.contains("Fixture note"))
        XCTAssertTrue(off.text.contains("travel; note \"Fixture trip\""))
        v.events.packetIncludesSensitive = true
        let on = try await document(v)
        XCTAssertTrue(on.text.contains("custom \"Fixture change\"; note \"Fixture note\""))
    }

    func testTheDocumentCarriesThePrivateEventsChoiceTheTextWasBuiltWith() async throws {
        let v = try await harness()
        try seedEvents(v)
        let off = try await document(v)
        XCTAssertEqual(off.privateEventsIncluded, false)
        v.events.packetIncludesSensitive = true
        let on = try await document(v)
        XCTAssertEqual(on.privateEventsIncluded, true)
        XCTAssertNotEqual(on.text, off.text)
    }

    func testThePrivateEventsChoiceIsNilWhenEventsAreOffOrTheSectionIsOff() async throws {
        let off = try await harness(eventsOn: false)
        off.events.packetIncludesSensitive = true
        let featureOff = try await document(off)
        XCTAssertNil(featureOff.privateEventsIncluded)
        XCTAssertEqual(CoachPacketText.section(featureOff.text, "== EVENTS =="),
                       ["not available: events is switched off in the app"])

        let v = try await harness()
        v.events.packetIncludesSensitive = true
        v.h.packetSettings.setSection(.events, on: false)
        let sectionOff = try await document(v)
        XCTAssertNil(sectionOff.privateEventsIncluded)
        XCTAssertFalse(sectionOff.text.contains("== EVENTS =="))
        let input = await v.assembler().input()
        XCTAssertFalse(input?.sections.contains(.events) ?? true)
    }

    func testNoEventsListedSaysNoneListed() async throws {
        let v = try await harness()
        let document = try await document(v)
        XCTAssertEqual(CoachPacketText.section(document.text, "== EVENTS =="), ["events: none listed in range"])
    }

    func testANoteThatLooksLikeAnEmailAddressBlocksThePacket() async throws {
        let v = try await harness()
        try v.events.add(kind: .travel, label: nil, startDay: v.h.clock.day(-3), endDay: nil,
                         note: "fixture.person@example.invalid", sensitive: false)
        let outcome = await v.assembler().assemble()
        guard case .blocked = outcome else { return XCTFail("expected blocked, got \(outcome)") }
    }

    func testARawNoteIsScannedBeforeItIsCut() async throws {
        let v = try await harness()
        let note = String(repeating: "x", count: 60) + " fixture.person@example.invalid"
        try v.events.add(kind: .travel, label: nil, startDay: v.h.clock.day(-3), endDay: nil, note: note, sensitive: false)
        let outcome = await v.assembler().assemble()
        guard case .blocked = outcome else { return XCTFail("ruling A20: expected blocked, got \(outcome)") }
    }

    func testAPrivateEventLeftOutDoesNotBlockThePacket() async throws {
        let v = try await harness()
        try v.events.add(kind: .illness, label: nil, startDay: v.h.clock.day(-3), endDay: nil,
                         note: "fixture.person@example.invalid", sensitive: true)
        let document = try await document(v)
        XCTAssertFalse(document.text.contains("fixture.person"))
    }

    // MARK: - Intake

    private func seedIntake(_ v: V2) async throws {
        let protein = IntakeAggregation.proteinKey, energy = IntakeAggregation.energyKey
        _ = try await v.h.store.upsertMetricSeries([
            MetricPoint(day: v.h.clock.day(-3), key: protein, value: 120),
            MetricPoint(day: v.h.clock.day(-3), key: energy, value: 2500),
            MetricPoint(day: v.h.clock.day(-2), key: protein, value: 80),
            MetricPoint(day: v.h.clock.day(-40), key: protein, value: 99),
        ], deviceId: IntakeProvider.quickAddSourceId)
        _ = try await v.h.store.upsertMetricSeries([
            MetricPoint(day: v.h.clock.day(-2), key: energy, value: 2400),
            MetricPoint(day: v.h.clock.day(-1), key: energy, value: 2300),
        ], deviceId: IntakeProvider.healthSourceId)
        await v.intake.refresh()
    }

    func testIntakeDaysEqualTheProvidersSeries() async throws {
        let v = try await harness()
        try await seedIntake(v)
        let input = try XCTUnwrap(await v.assembler().input())
        guard case .days(let days) = input.intake else { return XCTFail("intake is on: \(input.intake)") }
        let first = v.h.clock.day(-(v.h.packetSettings.rangeDays - 1))
        let series = v.intake.series().filter { $0.day >= first && $0.day <= v.h.today }
        XCTAssertEqual(days.map(\.day), series.map(\.day))
        XCTAssertEqual(days.map(\.proteinGrams), series.map { $0.protein?.value })
        XCTAssertEqual(days.map(\.energyKcal), series.map { $0.energy?.value })
        XCTAssertFalse(days.contains { $0.day == v.h.clock.day(-40) }, "filtered to the range")
    }

    func testIntakeRowsCarryTheClosedSourceTokens() async throws {
        let v = try await harness()
        try await seedIntake(v)
        let text = try await document(v).text
        let rows = CoachPacketText.section(text, "== INTAKE ==")
        XCTAssertTrue(rows.contains("  \(v.h.clock.day(-3)): protein 120 g, energy 2500 kcal [quick-add]"), "\(rows)")
        XCTAssertTrue(rows.contains("  \(v.h.clock.day(-2)): protein 80 g, energy 2400 kcal [mixed]"), "\(rows)")
        XCTAssertTrue(rows.contains("  \(v.h.clock.day(-1)): protein —, energy 2300 kcal [apple-health]"), "\(rows)")
        XCTAssertTrue(rows.contains("  \(v.h.today): protein —, energy —"))
        XCTAssertFalse(text.contains("noop-intake"))
    }

    func testIntakeFeatureOffSaysSoAndReadsNoIntake() async throws {
        let v = try await harness(intakeOn: false)
        try await seedIntake(v)
        let input = await v.assembler().input()
        XCTAssertEqual(input?.intake, .switchedOff)
        let text = try await document(v).text
        XCTAssertEqual(CoachPacketText.section(text, "== INTAKE =="), ["not available: intake is switched off in the app"])
    }

    func testIntakeWithNoDataPrintsDashesForEveryDay() async throws {
        let v = try await harness()
        let text = try await document(v).text
        let rows = CoachPacketText.section(text, "== INTAKE ==")
        XCTAssertEqual(rows.count, v.h.packetSettings.rangeDays + 1)
        XCTAssertTrue(rows.dropFirst().allSatisfy { $0.hasSuffix(": protein —, energy —") }, "\(rows)")
    }

    // MARK: - The setting (stage 5 §9.6)

    func testPacketSwitchDefaultsToOffAndRoundTripsThroughTheStore() async throws {
        let v = try await harness()
        XCTAssertEqual(PersonalEventStore.packetSensitiveKey, "personalEvents.packetIncludesSensitive")
        XCTAssertFalse(v.events.packetIncludesSensitive)
        XCTAssertNil(v.h.defaults.object(forKey: PersonalEventStore.packetSensitiveKey), "reading never writes")
        v.events.packetIncludesSensitive = true
        XCTAssertTrue(v.h.defaults.bool(forKey: PersonalEventStore.packetSensitiveKey))
        let second = PersonalEventStore(defaults: v.h.defaults)
        XCTAssertTrue(second.packetIncludesSensitive, "nothing cached")
        v.h.defaults.set(false, forKey: PersonalEventStore.packetSensitiveKey)
        XCTAssertFalse(v.events.packetIncludesSensitive)
    }

    func testPacketSwitchIsIndependentOfTheEventsFlag() async throws {
        let v = try await harness(eventsOn: false)
        v.events.packetIncludesSensitive = true
        XCTAssertTrue(v.events.packetIncludesSensitive)
        XCTAssertFalse(v.events.isEnabled)
        v.h.defaults.set(true, forKey: PersonalEventStore.enabledKey)
        XCTAssertTrue(v.events.packetIncludesSensitive)
    }

    func testPersonalEventsPacketSwitchIsNotExported() throws {
        let name = "CoachPacketV2Backup-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        suites.names.append(name)
        defaults.set(true, forKey: "personalEvents.packetIncludesSensitive")
        let snapshot = BackupSettings.snapshot(from: defaults)
        XCTAssertNil(snapshot["personalEvents.packetIncludesSensitive"])
        XCTAssertFalse(snapshot.keys.contains { $0.contains("packetIncludesSensitive") })
    }

    // MARK: - Presenter

    private func ready(_ privateEvents: Bool?, sections: Set<CoachPacketSection> = Set(CoachPacketSection.allCases))
        -> CoachPacketSheetPresentation {
        let text = CoachPacketText.sample("v2")
        var document = CoachPacketDocument(text: text, byteCount: text.utf8.count,
                                           generatedAt: Date(timeIntervalSince1970: 1_931_409_730), rangeDays: 14,
                                           sections: sections, nothingMeasured: false)
        document.privateEventsIncluded = privateEvents
        return CoachPacketPresenter.sheet(state: .ready(document), copyState: .none, isRegenerating: false,
                                          clipboardHoldsEarlierPacket: false, scorecardEnabled: true,
                                          timeZone: CoachPacketHarness.utc, locale: Locale(identifier: "en_GB"))
    }

    func testPrivateEventsCaptionFollowsTheDocumentAndGivesNoCount() {
        let left = ready(false)
        XCTAssertEqual(left.privateEventsCaption, "Private events: left out")
        XCTAssertEqual(left.privateEventsHint, "Change this in Settings.")
        let included = ready(true)
        XCTAssertEqual(included.privateEventsCaption, "Private events: included")
        XCTAssertEqual(included.privateEventsHint, "Change this in Settings.")
        for caption in [left.privateEventsCaption, included.privateEventsCaption, left.privateEventsHint] {
            XCTAssertFalse((caption ?? "").contains { $0.isNumber }, "no count of private events")
        }
    }

    func testPrivateEventsCaptionIsAbsentWhenEventsAreOffOrTheSectionIsOff() {
        let none = ready(nil)
        XCTAssertNil(none.privateEventsCaption)
        XCTAssertNil(none.privateEventsHint)
        for state in [CoachPacketModel.State.idle, .loading, .blocked, .unavailable] {
            let sheet = CoachPacketPresenter.sheet(state: state, copyState: .none, isRegenerating: false,
                                                   clipboardHoldsEarlierPacket: false, scorecardEnabled: true,
                                                   timeZone: CoachPacketHarness.utc, locale: Locale(identifier: "en_GB"))
            XCTAssertNil(sheet.privateEventsCaption, "\(state): no document, no caption")
        }
    }

    func testTheSheetHasSevenSectionSwitchesInTheFixedOrder() {
        XCTAssertEqual(CoachPacketSection.allCases.map(CoachPacketPresenter.sectionLabel),
                       ["Scorecard", "Weigh-ins", "Intake", "Recovery and sleep", "Trends", "Activity", "Events"])
        XCTAssertEqual(CoachPacketSettings(defaults: UserDefaults(suiteName: "v2-unused-\(UUID().uuidString)") ?? .standard)
                        .sections, Set(CoachPacketSection.allCases), "both new sections are on by default")
    }

    // MARK: - The in-app Coach is unchanged

    func testInAppCoachContextIsUnchangedWithIntakeEventsAndThePrivateSwitchOn() {
        let keys = [PersonalEventStore.enabledKey, IntakeSettings.enabledKey, CoachPacketSettings.enabledKey,
                    "personalEvents.packetIncludesSensitive"]
        var saved: [String: Any] = [:]
        for key in keys {
            if let value = UserDefaults.standard.object(forKey: key) { saved[key] = value }
        }
        defer {
            for key in keys {
                if let value = saved[key] { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }
        let repo = Repository(deviceId: "test-coach-packet-v2")
        let clock = CoachPacketClock()
        repo.days = (0..<14).map { offset in
            DailyMetric(day: clock.day(-offset), totalSleepMin: 444, efficiency: 0.91, deepMin: 78, remMin: 102,
                        lightMin: 264, disturbances: nil, restingHr: 54, avgHrv: 58, recovery: 62, strain: 47,
                        exerciseCount: nil)
        }
        let engine = AICoachEngine(repo: repo)
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }
        let before = engine.buildContext()
        for key in keys { UserDefaults.standard.set(true, forKey: key) }
        let after = engine.buildContext()
        XCTAssertEqual(before, after)
        XCTAssertFalse(after.contains("NOOP-COACH-PACKET"))
    }
}
