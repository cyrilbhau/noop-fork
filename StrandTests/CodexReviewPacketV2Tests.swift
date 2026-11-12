// The caption finding of the independent C12 review (packet version 2), pinned by tests that failed
// on the defect before its fix (ruling A26).
//
// With an otherwise empty store, intake on and one 30 g quick-add in the range, the packet printed a
// protein row while the sheet said "Nothing was measured in this range": the assembler's flag
// counted every version 1 section but not intake. The caption now appears only when no section
// that is switched on prints a measured value. An intake amount the packet prints counts; an event
// does not. (The amount finding of the same review is pinned in the StrandAnalytics package, in
// `CodexReviewPacketV2AmountTests`.)
//
// Synthetic values only. Every defaults domain is a throwaway suite.

import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

@MainActor
final class CodexReviewPacketV2Tests: XCTestCase {

    private let suites = CoachPacketSuites()

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    @MainActor
    private struct V2 {
        let h: CoachPacketHarness
        let events: PersonalEventStore
        let intake: IntakeProvider

        func document() async throws -> CoachPacketDocument {
            let now = h.clock.now
            return try await h.document(CoachPacketAssembler(
                repository: h.repo, provider: h.provider, scorecardSettings: h.scorecardSettings,
                settings: h.packetSettings, now: { now }, timeZone: { CoachPacketHarness.utc },
                effortScale: { .hundred }, identifiers: { [] }, intake: intake, events: events))
        }
    }

    /// An empty store: no daily row, step, workout, body reading or weekly point.
    private func harness(intakeOn: Bool = true, eventsOn: Bool = true) async throws -> V2 {
        let h = try await CoachPacketHarness.empty(scorecard: false, suites: suites)
        if intakeOn { h.defaults.set(true, forKey: IntakeSettings.enabledKey) }
        if eventsOn { h.defaults.set(true, forKey: PersonalEventStore.enabledKey) }
        var counter = 0
        let events = PersonalEventStore(defaults: h.defaults, now: { Date(timeIntervalSince1970: 1_000) },
                                        makeId: { counter += 1; return String(format: "%016x", counter) })
        let intake = IntakeProvider(repository: h.repo, settings: IntakeSettings(defaults: h.defaults))
        return V2(h: h, events: events, intake: intake)
    }

    /// One 30 g quick-add three days back, and nothing else.
    private func seedProtein(_ v: V2, _ grams: Double = 30) async throws {
        _ = try await v.h.store.upsertMetricSeries(
            [MetricPoint(day: v.h.clock.day(-3), key: IntakeAggregation.proteinKey, value: grams)],
            deviceId: IntakeProvider.quickAddSourceId)
        await v.intake.refresh()
    }

    private func caption(_ document: CoachPacketDocument) -> String? {
        CoachPacketPresenter.sheet(state: .ready(document), copyState: .none, isRegenerating: false,
                                   clipboardHoldsEarlierPacket: false, scorecardEnabled: false,
                                   timeZone: CoachPacketHarness.utc, locale: Locale(identifier: "en_GB")).caption
    }

    func testAnIntakeOnlyPacketDoesNotSayNothingWasMeasured() async throws {
        let v = try await harness()
        try await seedProtein(v)
        let document = try await v.document()
        XCTAssertTrue(CoachPacketText.section(document.text, "== INTAKE ==")
            .contains("  \(v.h.clock.day(-3)): protein 30 g, energy — [quick-add]"), document.text)
        XCTAssertFalse(document.nothingMeasured, "the packet prints a measured intake value")
        XCTAssertNotEqual(caption(document), CoachPacketPresenter.nothingMeasured)
    }

    func testAnIntakeAmountAboveTheOldPrivateLimitAlsoCounts() async throws {
        // Ruling A25 prints it, so ruling A26 counts it.
        let v = try await harness()
        try await seedProtein(v, 100_000)
        let document = try await v.document()
        XCTAssertTrue(document.text.contains("protein 100000 g"), document.text)
        XCTAssertFalse(document.nothingMeasured)
    }

    func testEventsAloneAreNotAMeasurement() async throws {
        let v = try await harness()
        try v.events.add(kind: .travel, label: nil, startDay: v.h.clock.day(-4), endDay: v.h.clock.day(-2),
                         note: "Fixture trip", sensitive: false)
        let document = try await v.document()
        XCTAssertTrue(document.text.contains("travel; note \"Fixture trip\""), document.text)
        XCTAssertTrue(document.nothingMeasured)
        XCTAssertEqual(caption(document), CoachPacketPresenter.nothingMeasured)
    }

    func testIntakeThatIsNotPrintedDoesNotCount() async throws {
        // The intake feature off in the app: the section says so and prints no value.
        let off = try await harness(intakeOn: false)
        try await seedProtein(off)
        let featureOff = try await off.document()
        XCTAssertEqual(CoachPacketText.section(featureOff.text, "== INTAKE =="),
                       ["not available: intake is switched off in the app"])
        XCTAssertTrue(featureOff.nothingMeasured)
        XCTAssertEqual(caption(featureOff), CoachPacketPresenter.nothingMeasured)

        // The Intake section switched off in the packet's own settings.
        let v = try await harness()
        try await seedProtein(v)
        v.h.packetSettings.setSection(.intake, on: false)
        let sectionOff = try await v.document()
        XCTAssertFalse(sectionOff.text.contains("== INTAKE =="))
        XCTAssertTrue(sectionOff.nothingMeasured)

        // Intake on with no amount in the range: dashes are not a measurement.
        let empty = try await harness()
        let dashes = try await empty.document()
        XCTAssertTrue(CoachPacketText.section(dashes.text, "== INTAKE ==").dropFirst()
            .allSatisfy { $0.hasSuffix(": protein —, energy —") }, dashes.text)
        XCTAssertTrue(dashes.nothingMeasured)
    }
}
