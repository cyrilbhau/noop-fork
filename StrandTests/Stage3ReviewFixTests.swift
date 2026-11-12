// Stage 3 (protein and intake): regression tests for the confirmed review findings on the app
// side. Each test fails on the defect it names. Synthetic values only (the Fixture Person).

import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

// MARK: - The quick-add store

@MainActor
final class Stage3QuickAddReviewFixTests: XCTestCase {
    private let suites = IntakeSuites()
    private let id = IntakeFixture.quickAddId

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    private func harness() async throws -> IntakeHarness {
        let h = try await IntakeHarness.make(flag: true, source: .quickAdd, suites: suites)
        try await h.seedUnrelated()
        return h
    }

    /// Finding: adding food on a day with a restored total replaced that total.
    func testAddingToARestoredDayKeepsTheRestoredTotal() async throws {
        let h = try await harness()
        let store = h.quickAdd()
        try await h.seed(id, day: h.today, protein: 95, energy: 1_450, readAt: h.clock.epoch(0, hour: 7))

        try await store.add(proteinGrams: 30, energyKcal: 500, label: nil, at: h.clock.at(0, hour: 9))

        let protein = try await h.value(id, h.today, "protein_g")
        let energy = try await h.value(id, h.today, "calories_in")
        XCTAssertEqual(protein, 125, "the restored 95 g is kept beside the new entry")
        XCTAssertEqual(energy, 1_950)
        let entries = store.entries(day: h.today)
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.contains { $0.proteinGrams == 95 && $0.energyKcal == 1_450 })
        let restored = await store.restoredTotal(day: h.today)
        XCTAssertNil(restored, "the restored total became a real entry")
    }

    func testAddingToARestoredBackdatedDayKeepsTheRestoredTotal() async throws {
        let h = try await harness()
        let store = h.quickAdd()
        let yesterday = h.clock.day(-1)
        try await store.add(proteinGrams: 20, energyKcal: 300, label: nil, at: h.clock.at(0, hour: 8))
        try await h.seed(id, day: yesterday, protein: 95, energy: 1_450, readAt: h.clock.epoch(-1, hour: 21))

        try await store.add(proteinGrams: 30, energyKcal: 500, label: nil, at: h.clock.at(-1, hour: 12))

        let protein = try await h.value(id, yesterday, "protein_g")
        let energy = try await h.value(id, yesterday, "calories_in")
        XCTAssertEqual(protein, 125)
        XCTAssertEqual(energy, 1_950)
        XCTAssertEqual(store.entries(day: yesterday).count, 2)
        let today = try await h.value(id, h.today, "protein_g")
        XCTAssertEqual(today, 20, "today is untouched")
    }

    /// Finding: an unreadable entry list counted as empty, so its stored total was deleted.
    func testUnreadableEntryListLeavesStoredTotalsAndRawValueAlone() async throws {
        let h = try await harness()
        let store = h.quickAdd()
        let key = IntakeSettings.entriesKeyPrefix + h.today
        try await h.seed(id, day: h.today, protein: 120, energy: 900, readAt: h.clock.epoch(0, hour: 7))
        h.defaults.set("not json", forKey: key)
        let before = try await h.rows()

        try await store.rebank(day: h.today)
        let afterRebank = try await h.rows()
        XCTAssertEqual(afterRebank, before, "opening the screen must not delete the day's totals")

        do {
            try await store.add(proteinGrams: 10, energyKcal: nil, label: nil, at: h.clock.at(0, hour: 9))
            XCTFail("adding to an unreadable list must be refused")
        } catch {}
        XCTAssertEqual(h.defaults.string(forKey: key), "not json", "the raw value is never overwritten")
        let afterAdd = try await h.rows()
        XCTAssertEqual(afterAdd, before)
    }

    /// Finding: opening the screen reset "Entered HH:mm" to the time the screen was opened.
    func testRebankWithoutAChangeKeepsTheEntryTime() async throws {
        let h = try await harness()
        var clock = h.clock.at(0, hour: 8)
        let store = h.quickAdd(now: { clock })
        try await store.add(proteinGrams: 30, energyKcal: 150, label: nil, at: h.clock.at(0, hour: 8))
        let stamped = try await h.value(id, h.today, "intake_read_at")
        XCTAssertEqual(stamped, Double(h.clock.epoch(0, hour: 8)))
        let before = try await h.rows()

        clock = h.clock.at(0, hour: 14, minute: 32)
        try await store.rebank(day: h.today)
        try await store.rebank(day: h.clock.day(-1))
        let after = try await h.rows()
        XCTAssertEqual(after, before, "a rebank that changes no amount keeps the entry time")

        // A repair still stamps: the total lagged its list.
        try await h.seed(id, day: h.today, protein: 10)
        try await store.rebank(day: h.today)
        let repaired = try await h.value(id, h.today, "protein_g")
        XCTAssertEqual(repaired, 30)
        let repairedAt = try await h.value(id, h.today, "intake_read_at")
        XCTAssertEqual(repairedAt, Double(h.clock.epoch(0, hour: 14, minute: 32)))
    }
}

// MARK: - Settings, the Coach exclusion and the rules sheet

@MainActor
final class Stage3SettingsReviewFixTests: XCTestCase {
    private var suiteNames: [String] = []

    override func tearDown() {
        for name in suiteNames { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        suiteNames = []
        super.tearDown()
    }

    private func defaults() throws -> UserDefaults {
        let name = "Stage3SettingsReviewFixTests-\(UUID().uuidString)"
        suiteNames.append(name)
        return try XCTUnwrap(UserDefaults(suiteName: name))
    }

    /// Finding: leaving a calorie field rewrote unreadable shared scorecard rules.
    func testFloorSetterRefusesWhileTheRulesNeedAttention() throws {
        let invalidRules = [#"{"v":1,"proteinMinDaysPerWeek":9,"rateWindowWeeks":5}"#, "not json"]
        for raw in invalidRules {
            let defaults = try defaults()
            defaults.set(raw, forKey: CutScorecardSettings.rulesKey)
            let scorecard = CutScorecardSettings(defaults: defaults)
            XCTAssertTrue(scorecard.rulesNeedAttention, raw)
            let settings = IntakeSettings(defaults: defaults, scorecard: scorecard)
            XCTAssertFalse(settings.setProteinFloorGrams(nil), raw)
            XCTAssertFalse(settings.setProteinFloorGrams(120), raw)
            XCTAssertEqual(defaults.string(forKey: CutScorecardSettings.rulesKey), raw, "byte-identical")
        }
    }

    func testFloorSetterWritesNothingWhenTheFloorIsUnchanged() throws {
        let defaults = try defaults()
        let scorecard = CutScorecardSettings(defaults: defaults)
        var parameters = CutScorecardParameters.generic
        parameters.proteinFloorGrams = 150
        scorecard.parameters = parameters
        let whole = try XCTUnwrap(defaults.string(forKey: CutScorecardSettings.rulesKey))
        let fractional = whole.replacingOccurrences(of: #""proteinFloorGrams":150"#, with: #""proteinFloorGrams":150.4"#)
        XCTAssertNotEqual(fractional, whole)
        defaults.set(fractional, forKey: CutScorecardSettings.rulesKey)
        let settings = IntakeSettings(defaults: defaults, scorecard: scorecard)
        XCTAssertEqual(settings.proteinFloorGrams, 150)
        XCTAssertTrue(settings.setProteinFloorGrams(150))
        XCTAssertEqual(defaults.string(forKey: CutScorecardSettings.rulesKey), fractional, "R30: no rewrite")
    }

    /// Finding: the Coach filter checked only the first four stored supplement questions.
    func testCoachExclusionChecksEveryStoredQuestion() throws {
        let defaults = try defaults()
        let list = ["Q1?", "Q2?", "Q3?", "Q4?", "Did you take Fixture?"]
        let raw = String(decoding: try JSONEncoder().encode(list), as: UTF8.self)
        defaults.set(raw, forKey: IntakeSettings.supplementQuestionsKey)
        let rows = [JournalEntry(day: "2031-01-27", question: "Q1?", answeredYes: true, notes: nil),
                    JournalEntry(day: "2031-01-27", question: "Did you take Fixture?", answeredYes: true, notes: nil),
                    JournalEntry(day: "2031-01-27", question: "Did you drink any alcohol?", answeredYes: false, notes: nil)]
        let visible = IntakeSettings.coachVisible(rows, defaults: defaults)
        XCTAssertFalse(visible.contains { $0.question == "Did you take Fixture?" })
        XCTAssertEqual(visible.map(\.question), ["Did you drink any alcohol?"])
    }

    /// Finding: the Settings card promised that everything stays on this iPhone.
    func testSettingsBlurbMakesNoOnPhonePromise() {
        XCTAssertEqual(IntakePresenter.settingsBlurb, "Protein and calories against your own floor and range. Off by default.")
        XCTAssertFalse(IntakePresenter.settingsBlurb.contains("stays on this iPhone"))
        XCTAssertFalse(IntakePresenter.settingsBlurb.contains("sends it nowhere"))
    }

    /// Finding: the rules sheet rounded a floor the whole-gram rule refuses, without saying so.
    func testRulesSheetRefusesWhatTheWholeGramRuleRefuses() throws {
        let floors: [Double] = [1, 100, 100_000, 0, 0.4, 0.5, 99.4, 99.5, -5, 100_001, .nan, .infinity]
        for floor in floors {
            let defaults = try defaults()
            let settings = CutScorecardSettings(defaults: defaults)
            var draft = ScorecardPhaseDraft.firstUse(today: "2031-01-06")
            draft.name = "Fixture cut"
            draft.targetWeightKg = 94
            draft.parameters.proteinFloorGrams = floor
            let accepted = CutScorecardSettings.isWholeGramProteinFloor(floor)
            XCTAssertEqual(draft.invalidFields.contains(.proteinFloorGrams), !accepted, "\(floor)")
            XCTAssertEqual(draft.canSave, accepted, "\(floor)")
            if !accepted {
                XCTAssertFalse(draft.save(to: settings), "\(floor)")
                XCTAssertNil(defaults.string(forKey: CutScorecardSettings.rulesKey), "\(floor): nothing written")
            }
        }
        var draft = ScorecardPhaseDraft.firstUse(today: "2031-01-06")
        draft.parameters.proteinFloorGrams = 100
        let sheet = CutScorecardPresenter.phaseSheet(draft, today: "2031-01-06", previousPhaseName: nil,
                                                     unitSystem: .metric, locale: Locale(identifier: "en_GB"))
        let row = sheet.groups.flatMap(\.rows).first { $0.field == .proteinFloorGrams }
        XCTAssertEqual(row?.input, .whole, "a whole-number keypad")
        XCTAssertEqual(row?.text, "100")
    }
}

// MARK: - Backdating, the shown day and midnight

@MainActor
final class Stage3BackdatingReviewFixTests: XCTestCase {
    private let suites = IntakeSuites()
    private let id = IntakeFixture.quickAddId

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    private static func epoch(_ iso: String) -> Int {
        Int(ISO8601DateFormatter().date(from: iso)!.timeIntervalSince1970)
    }

    /// Finding: a backdated entry could be stored under a different day than the one picked.
    func testABackdatedEntryLandsOnThePickedDayAcrossAZoneChange() async throws {
        let h = try await IntakeHarness.make(flag: true, source: .quickAdd, zoneLog: false, suites: suites)
        h.settings.zoneLog = [IntakeZoneSegment(fromEpochSeconds: 0, zoneIdentifier: "Asia/Kolkata"),
                              IntakeZoneSegment(fromEpochSeconds: Self.epoch("2026-11-11T16:00:00Z"),
                                                zoneIdentifier: "America/Los_Angeles")]
        let now = Date(timeIntervalSince1970: TimeInterval(Self.epoch("2026-11-12T20:00:00Z")))
        let store = h.quickAdd(now: { now }, zone: { "America/Los_Angeles" })

        let entry = try await store.add(proteinGrams: 30, energyKcal: nil, label: nil, on: "2026-11-09",
                                        today: "2026-11-12")
        XCTAssertEqual(entry.day, "2026-11-09")
        XCTAssertEqual(store.entries(day: "2026-11-10"), [])
        XCTAssertEqual(store.entries(day: "2026-11-09").map(\.id), [entry.id])
        let picked = try await h.value(id, "2026-11-09", "protein_g")
        XCTAssertEqual(picked, 30)
        let next = try await h.value(id, "2026-11-10", "protein_g")
        XCTAssertNil(next)
    }

    func testTheBackdatingInstantKeysBackToItsDayEastward() {
        let log = [IntakeZoneSegment(fromEpochSeconds: 0, zoneIdentifier: "America/Los_Angeles"),
                   IntakeZoneSegment(fromEpochSeconds: Self.epoch("2026-11-09T00:00:00Z"), zoneIdentifier: "Pacific/Kiritimati")]
        for day in ["2026-11-07", "2026-11-08", "2026-11-09", "2026-11-10"] {
            let instant = IntakeQuickAddStore.instant(inside: day, zoneLog: log)
            XCTAssertNotNil(instant, day)
            XCTAssertEqual(instant.map { IntakeAggregation.dayKey(epochSeconds: $0, zoneLog: log) }, day, day)
        }
        XCTAssertNil(IntakeQuickAddStore.instant(inside: "2026-13-40", zoneLog: log))
    }

    /// Finding: a screen left open past midnight saved a "Today" entry to yesterday.
    func testATodayEntryAfterMidnightLandsOnTheRealDay() async throws {
        let h = try await IntakeHarness.make(flag: true, source: .quickAdd, suites: suites)
        let now = h.clock.at(1, hour: 0, minute: 5)
        let store = h.quickAdd(now: { now })
        // The sheet was opened before midnight: its "Today" is the day before the real one.
        let entry = try await store.add(proteinGrams: 30, energyKcal: nil, label: nil, on: h.today, today: h.today)
        XCTAssertEqual(entry.day, h.clock.day(1))
        XCTAssertEqual(entry.loggedAt, now)
        XCTAssertEqual(store.entries(day: h.today), [])
        // A dated day in the same stale list still lands on that date.
        let backdated = try await store.add(proteinGrams: 10, energyKcal: nil, label: nil, on: h.clock.day(-2),
                                            today: h.today)
        XCTAssertEqual(backdated.day, h.clock.day(-2))
    }

    /// Finding: entries on any day other than today could not be seen, edited or deleted.
    func testEntriesOfABackdatedDayCanBeListedAndDeleted() async throws {
        let h = try await IntakeHarness.make(flag: true, source: .quickAdd, suites: suites)
        let store = h.quickAdd()
        let day = h.clock.day(-3)
        XCTAssertEqual(IntakePresenter.entriesDay(requested: day, today: h.today), day)
        XCTAssertEqual(IntakePresenter.entriesDay(requested: h.clock.day(-8), today: h.today), h.today)
        XCTAssertEqual(IntakePresenter.entriesDay(requested: nil, today: h.today), h.today)

        let entry = try await store.add(proteinGrams: 300, energyKcal: nil, label: nil, on: day, today: h.today)
        await h.provider.refresh()
        let input = await IntakePresenterInput.gather(provider: h.provider, settings: h.settings, day: h.today,
                                                      quickAdd: store, entriesDay: day)
        XCTAssertEqual(input.day, h.today, "the ring and totals stay on today")
        XCTAssertEqual(input.entries.map(\.id), [entry.id])

        try await store.delete(id: entry.id, day: day)
        let protein = try await h.value(id, day, "protein_g")
        XCTAssertNil(protein)

        let restoredDay = h.clock.day(-4)
        try await h.seed(id, day: restoredDay, protein: 95, energy: 1_450, readAt: h.clock.epoch(-4, hour: 21))
        let restored = await IntakePresenterInput.gather(provider: h.provider, settings: h.settings, day: h.today,
                                                         quickAdd: store, entriesDay: restoredDay)
        XCTAssertEqual(restored.restoredTotal?.proteinGrams, 95)
        try await store.replaceRestoredTotal(day: restoredDay)
        XCTAssertEqual(store.entries(day: restoredDay).count, 1)
        XCTAssertEqual(store.entries(day: h.today), [])
    }
}

// MARK: - The widget, the scorecard caption and the presenter's text

@MainActor
final class Stage3PresentationReviewFixTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func at(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    /// Finding: after midnight the protein widget said "Set up in NOOP" for a set-up feature.
    func testProteinWidgetAfterMidnightSaysNothingLogged() {
        let reading = PersonalIntakeReading.reading(
            day: "2031-01-27", progress: IntakeProteinValues(shownGrams: 95, shownFloorGrams: 100, remainingGrams: 5),
            source: .appleHealth, readAt: at("2031-01-27T18:00:00Z"))
        let metrics = PersonalWidgetMetrics(intake: reading)
        XCTAssertEqual(metrics.intakeWidgetState(now: at("2031-01-28T00:00:00Z"), calendar: utc),
                       .nothingLogged(floorGrams: 100))
        XCTAssertEqual(metrics.intakeWidgetState(now: at("2031-01-27T23:59:00Z"), calendar: utc),
                       .below(grams: 95, floorGrams: 100, remainingGrams: 5))
        let noSource = PersonalIntakeReading.reading(
            day: "2031-01-27", progress: IntakeProteinValues(shownGrams: nil, shownFloorGrams: 100, remainingGrams: nil),
            source: nil, readAt: nil)
        XCTAssertEqual(PersonalWidgetMetrics(intake: noSource).intakeWidgetState(now: at("2031-01-28T09:00:00Z"), calendar: utc),
                       .notSetUp)
        XCTAssertEqual(PersonalWidgetMetrics().intakeWidgetState(now: at("2031-01-28T09:00:00Z"), calendar: utc), .notSetUp)
    }

    private func resolved(_ day: String, _ source: IntakeSource) -> ResolvedIntakeDay {
        ResolvedIntakeDay(day: day, protein: ResolvedIntakeValue(value: 120, source: source, readAtEpochSeconds: nil),
                          energy: nil)
    }

    /// Finding: the scorecard protein-row caption read different days from the row.
    func testScorecardProteinCaptionReadsTheJudgedWeek() {
        let series = ["2026-12-02", "2026-12-03", "2026-12-04", "2026-12-05", "2026-12-06", "2026-12-07", "2026-12-08"]
            .map { resolved($0, .nutritionCsv) } + ["2026-12-10", "2026-12-11", "2026-12-12"].map { resolved($0, .quickAdd) }
        let judged = IntakePresenter.scorecardProteinSources(series, anchorDay: "2026-12-09")
        XCTAssertEqual(judged, Array(repeating: .nutritionCsv, count: 7))
        XCTAssertEqual(IntakePresenter.scorecardProteinCaption(flagEnabled: true, sources: judged), "CSV import")
        let later = IntakePresenter.scorecardProteinSources(series, anchorDay: "2026-12-13")
        XCTAssertEqual(IntakePresenter.scorecardProteinCaption(flagEnabled: true, sources: later), "Several sources")
        XCTAssertEqual(IntakePresenter.scorecardProteinSources(series, anchorDay: "not a day"), [])
    }

    func testThePresentationCarriesTheDayTheProteinSignalCountsFrom() {
        let weighDay = ScorecardScreenFixture.weighDay(6)
        let today = ScorecardScreenFixture.day(weighDay, plus: 2)
        let input = ScorecardScreenFixture.input(today: today)
        let result = CutScorecard.evaluate(input)
        let context = CutScorecardPresentationContext(unitSystem: .metric, weightSource: .labBook,
                                                      rulesNeedAttention: false, locale: Locale(identifier: "en_GB"))
        let presentation = CutScorecardPresenter.present(result, input: input, context: context)
        XCTAssertEqual(presentation.proteinWindowAnchorDay, weighDay)
        // The caption's window is the signal's: the same days are counted.
        let series = input.proteinDays.map {
            ResolvedIntakeDay(day: $0.day, protein: ResolvedIntakeValue(value: $0.grams, source: .quickAdd,
                                                                        readAtEpochSeconds: nil), energy: nil)
        }
        let anchor = try? XCTUnwrap(presentation.proteinWindowAnchorDay)
        XCTAssertEqual(IntakePresenter.scorecardProteinSources(series, anchorDay: anchor ?? "").count,
                       result.signals.protein.daysLogged)
    }

    /// Finding: views formatted numbers and dates themselves.
    func testThePresenterFormatsEntriesAndDays() {
        let locale = Locale(identifier: "en_GB")
        let entry = IntakeEntry(id: UUID(), loggedAt: Date(), day: "2031-01-27", proteinGrams: 30, energyKcal: 150, label: nil)
        XCTAssertEqual(IntakePresenter.entryAmounts(entry, locale: locale), "30 g · 150 kcal")
        var proteinOnly = entry
        proteinOnly.energyKcal = nil
        XCTAssertEqual(IntakePresenter.entryAmounts(proteinOnly, locale: locale), "30 g")
        var energyOnly = entry
        energyOnly.proteinGrams = nil
        XCTAssertEqual(IntakePresenter.entryAmounts(energyOnly, locale: locale), "150 kcal")
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(IntakePresenter.dayLabel("2031-01-27", today: "2031-01-27", timeZone: utc, locale: locale), "Today")
        let label = IntakePresenter.dayLabel("2031-01-25", today: "2031-01-27", timeZone: utc, locale: locale)
        XCTAssertTrue(label.contains("25") && label.contains("Sat"), label)
        XCTAssertEqual(IntakePresenter.editableAmountText(30), "30")
        XCTAssertEqual(IntakePresenter.editableAmountText(30.5), "30.5")
    }
}
