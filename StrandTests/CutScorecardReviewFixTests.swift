import XCTest
import Combine
import StrandAnalytics
import WhoopStore
@testable import Strand

// Stage 1 (weigh-in and scorecard): the confirmed review findings on the screens, pinned below the
// SwiftUI layer. Each test states the correct behaviour for one finding of
// build/personal/stage1-screens-confirmed-findings.md and is named for it. The reminder findings
// (8, 14, 15) are in WeighInReminderReviewFixTests.swift. Written before the fixes exist.
//
// API ASSUMED BY THESE TESTS (new members; everything else is the committed API)
//
//     extension WeighInSheetModel {                       // Strand/Data/CutScorecardModel.swift
//         /// Finding 1. False exactly when the sheet edits a reading that has a weight and no
//         /// waist: Save is then the weight-only save, and Skip is not offered.
//         var offersSkip: Bool { get }
//         /// Finding 2. Becomes optional: the note describes a NEW weigh-in, so it is nil
//         /// whenever the sheet is editing a reading. Unchanged for a new weigh-in.
//         var skipNote: String? { get }
//     }
//     // Findings 1, 6 and 18 change behaviour only: `canSave` is true for a valid weight when
//     // editing a weight-only reading, and a prefilled field whose text was not changed is
//     // written back as the row's stored value, never as the parsed display text.
//
//     extension CutScorecardSettings {                    // Strand/Data/CutScorecardSettings.swift
//         /// Finding 10. True when a string is stored under `cutScorecard.phases` and it does not
//         /// decode as a whole. False when the key is absent and when the string is readable.
//         var phasesNeedAttention: Bool { get }
//     }
//     // `ScorecardPhaseDraft.save(to:)` writes nothing and returns false while it is true.
//
//     extension CutScorecardPresenter {                   // Strand/Data/CutScorecardPresenter.swift
//         /// Finding 10. `phasesNeedAttention` true: `canSave` is false and `storedPhasesNote`
//         /// says the stored phases cannot be read. The parameter may default to false.
//         static func phaseSheet(_ draft: ScorecardPhaseDraft, today: String, previousPhaseName: String?,
//                                unitSystem: UnitSystem, locale: Locale,
//                                phasesNeedAttention: Bool) -> ScorecardPhaseSheetPresentation
//         /// Finding 7. The scorecard screen and the history screen exist only while this is
//         /// true; both wrappers in StrandiOS/Scorecard read it and dismiss when it is false.
//         static func screenIsReachable(flagEnabled: Bool) -> Bool
//         /// Finding 13. The reminder row's state from the stored switch, the system's present
//         /// answer and what the row shows now.
//         static func reminderStatus(storedOn: Bool, systemDenied: Bool,
//                                    current: WeighInReminderStatus) -> WeighInReminderStatus
//     }
//     extension ScorecardPhaseSheetPresentation {
//         /// Finding 10. Nil unless the stored phases need attention.
//         var storedPhasesNote: String? { get }
//     }
//
//     extension ScorecardPhaseDraft {                     // Strand/Data/CutScorecardModel.swift
//         /// Finding 12. The start day of the stored phase before the one this draft writes: the
//         /// phase before the edited one, or the edited one itself for "Start a new phase". Nil
//         /// when there is none. A `startDay` before it puts `.startDay` in `invalidFields`.
//         var earliestStartDay: String? { get }
//     }
//
//     extension TodayCardsEditorPresentation {            // Strand/Data/TodayCardsEditorPresentation.swift
//         /// Finding 11. `edited` with every withheld card put back directly after the nearest
//         /// saved card before it that is still present, or first when none is.
//         static func mergedSelection(edited: [DashboardCard], raw: String,
//                                     available: [DashboardCard]) -> [DashboardCard]
//     }
//
//     extension TodayCardResolver {                       // Strand/Data/TodayCardReadout.swift
//         /// Finding 5. Why nothing renders, when a gate is the reason; nil otherwise. The
//         /// decision `RedesignTodayView.gatedDashboardCaption` makes today, plus the scorecard.
//         static func gatedCaption(raw: String, hydrationEnabled: Bool, coachEnabled: Bool,
//                                  scorecardEnabled: Bool, visibleKeyMetrics: [KeyMetric]?) -> String?
//     }
//
// Behaviour pinned without a new member:
//
//   - Finding 16: `CutScorecardModel.load()` follows the provider before it reads the snapshot.
//   - Finding 19: a no-readings result has no card value and makes "Log weigh-in" primary.
//   - Finding 20: `Wording.date`, `shortDate`, `dateWithYear` and `weighInDateText` use the
//     locale's own field order for Chinese; every other locale keeps the fixed day-first pattern.
//   - Finding 17: `weighInDateText` honours the hour cycle of the locale it is given, and
//     `ScorecardContext.live` (StrandiOS/Scorecard/ScorecardKit.swift, which this macOS-hosted
//     bundle cannot load) hands it `AppClock.formattingLocale`. The second half is a source scan.
//   - Finding 7: likewise a source scan that ScorecardView.swift and WeighInHistoryView.swift
//     observe `CutScorecardFlag` and read `screenIsReachable`.
//
// View-only, left to review and the simulator pass: finding 3 (verdict title size cap), finding 4
// (percent suffix spacing) and finding 9 (skeleton shapes and the curve count-up).
//
// Synthetic values only: the "Fixture Person" of specification §13.
@MainActor
final class CutScorecardReviewFixTests: XCTestCase {

    // MARK: - Harness

    private typealias Fixture = ScorecardScreenFixture

    private final class Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private struct Harness {
        let store: WhoopStore
        let repo: Repository
        let defaults: UserDefaults
        let settings: CutScorecardSettings
        let provider: BodyMeasurementProvider
        let weighIns: WeighInStore
        let clock: Clock
    }

    private let utc = TimeZone(identifier: "UTC")!
    private let british = Locale(identifier: "en_GB")
    private let deviceId = "my-whoop"
    private var suites: [String] = []

    private let fixturePhase = CutScorecardStoredPhase(kind: .cut, name: "Fixture cut", startDay: "2031-01-06",
                                                       targetWeightKg: 94.0, rateLowPercentPerWeek: 0.40,
                                                       rateHighPercentPerWeek: 1.20)

    override func tearDown() {
        for name in suites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        suites = []
        super.tearDown()
    }

    private func at(_ day: String, _ hour: Int = 7, _ minute: Int = 0) -> Date {
        Fixture.date(day).addingTimeInterval(Double(hour * 3_600 + minute * 60))
    }

    private func marker(_ key: String, _ day: String, _ value: Double, hour: Int = 7,
                        unit: String? = nil) -> LabMarkerRow {
        let takenAt = Int(at(day, hour).timeIntervalSince1970)
        return LabMarkerRow(id: "\(key)-\(takenAt)-manu", deviceId: deviceId, markerKey: key,
                            category: "bodyMeasurement", day: day, takenAt: takenAt, value: value,
                            valueText: nil, unit: unit ?? (key == "weight" ? "kg" : "cm"), source: "manual",
                            note: nil, referenceText: nil)
    }

    /// The Wednesday weight and waist of each fixture week given.
    private func weekRows(_ weeks: [Int]) -> [LabMarkerRow] {
        weeks.flatMap { week -> [LabMarkerRow] in
            guard let weight = Fixture.weights[week - 1], let waist = Fixture.waists[week - 1] else { return [] }
            let day = Fixture.weighDay(week)
            return [marker("weight", day, weight), marker("waist", day, waist)]
        }
    }

    private func freshDefaults() throws -> UserDefaults {
        let name = "CutScorecardReviewFixTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        suites.append(name)
        return defaults
    }

    /// "Now" is 07:02 UTC on `today`. `refreshes` false leaves the provider's snapshot empty.
    private func makeHarness(today: String, rows: [LabMarkerRow] = [],
                             refreshes: Bool = true) async throws -> Harness {
        let defaults = try freshDefaults()
        defaults.set(true, forKey: "noop.cutScorecardEnabled")
        let settings = CutScorecardSettings(defaults: defaults)
        settings.phases = [fixturePhase]
        settings.parameters = Fixture.parameters

        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: deviceId)
        repo.setStoreForTesting(store)
        let clock = Clock(at(today, 7, 2))
        let zone = utc
        let provider = BodyMeasurementProvider(repository: repo, defaults: defaults,
                                               today: { LocalDayWindows(timeZone: zone).dayKey(for: clock.now) })
        let weighIns = WeighInStore(repository: repo, provider: provider, timeZone: { zone }, now: { clock.now })
        if refreshes {
            if !rows.isEmpty { try await store.upsertLabMarkers(rows) }
            await provider.refresh()
        } else {
            await provider.refresh()
            if !rows.isEmpty { try await store.upsertLabMarkers(rows) }
        }
        return Harness(store: store, repo: repo, defaults: defaults, settings: settings, provider: provider,
                       weighIns: weighIns, clock: clock)
    }

    private func rows(_ h: Harness, _ key: String) async throws -> [LabMarkerRow] {
        try await h.store.labMarkers(deviceId: deviceId, markerKey: key)
            .sorted { ($0.takenAt, $0.id) < ($1.takenAt, $1.id) }
    }

    private func history(_ h: Harness, unitSystem: UnitSystem = .metric) async throws -> WeighInHistory {
        CutScorecardPresenter.history(weights: try await rows(h, "weight"), waists: try await rows(h, "waist"),
                                      appleHealth: [], unitSystem: unitSystem, locale: british)
    }

    private func makeSheet(_ h: Harness, unitSystem: UnitSystem = .metric,
                           editing: WeighInHistoryRow? = nil) -> WeighInSheetModel {
        let zone = utc
        let clock = h.clock
        return WeighInSheetModel(weighIns: h.weighIns, unitSystem: unitSystem, now: { clock.now },
                                 timeZone: { zone }, locale: british, editing: editing)
    }

    private func waitUntil(_ what: String, timeout: TimeInterval = 10, file: StaticString = #filePath,
                           line: UInt = #line, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("timed out waiting for \(what)", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// The stored value in kilograms or centimetres, whatever unit the row carries.
    private func stored(_ row: LabMarkerRow?, _ kind: BodyMeasurementKind) -> Double? {
        row.flatMap { BodyMeasurementResolver.normalizedValue(of: $0, as: kind) }
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// One reading on Wed 29 Jan 2031, 07:00, seen from Wed 5 Feb. Returns its history row.
    private func oneReading(weight: Double, waist: Double?, weightUnit: String = "kg", waistUnit: String = "cm",
                            shownIn unitSystem: UnitSystem = .metric) async throws -> (Harness, WeighInHistoryRow) {
        var seeded = [marker("weight", "2031-01-29", weight, unit: weightUnit)]
        if let waist { seeded.append(marker("waist", "2031-01-29", waist, unit: waistUnit)) }
        let h = try await makeHarness(today: "2031-02-05", rows: seeded)
        let listed = try await history(h, unitSystem: unitSystem)
        let row = try XCTUnwrap(listed.rows.first { $0.day == "2031-01-29" })
        XCTAssertTrue(row.canEdit)
        return (h, row)
    }

    // MARK: - Findings 6 and 18: an edit never rewrites a value the owner did not change

    /// Opened and saved with no field touched: nothing the sheet shows is written back.
    func testFinding6SavingAnEditWithNothingChangedKeepsTheExactStoredWeightAndWaist() async throws {
        let (h, row) = try await oneReading(weight: 97.46, waist: 99.46)
        let sheet = makeSheet(h, editing: row)
        await sheet.prepare()
        XCTAssertEqual(sheet.weightText, "97.5", "the field shows one decimal")
        sheet.advance()
        XCTAssertEqual(sheet.waistText, "99.5")
        await sheet.save()
        XCTAssertEqual(sheet.phase, .saved)

        let weights = try await rows(h, "weight")
        let waists = try await rows(h, "waist")
        XCTAssertEqual(weights.count, 1)
        XCTAssertEqual(waists.count, 1)
        XCTAssertEqual(stored(weights.first, .weight), 97.46, "the stored weight, not the rounded display text")
        XCTAssertEqual(stored(waists.first, .waist), 99.46, "the stored waist, not the rounded display text")
    }

    /// §10.4 "Edit the date or time": the reading moves, its values do not change.
    func testFinding6EditingOnlyTheDateKeepsTheExactStoredWeightAndWaist() async throws {
        let (h, row) = try await oneReading(weight: 97.46, waist: 99.46)
        let sheet = makeSheet(h, editing: row)
        await sheet.prepare()
        let moved = at("2031-01-29", 6, 30)
        sheet.takenAt = moved
        sheet.advance()
        await sheet.save()
        XCTAssertEqual(sheet.phase, .saved)

        let instant = Int(moved.timeIntervalSince1970)
        let weights = try await rows(h, "weight")
        let waists = try await rows(h, "waist")
        XCTAssertEqual(weights.map(\.takenAt), [instant], "the weight moved to the chosen instant")
        XCTAssertEqual(waists.map(\.takenAt), [instant], "and the waist followed it")
        XCTAssertEqual(stored(weights.first, .weight), 97.46)
        XCTAssertEqual(stored(waists.first, .waist), 99.46)
    }

    /// The same through Skip, which never touches the waist.
    func testFinding6SkippingOnADateOnlyEditKeepsTheExactStoredWeight() async throws {
        let (h, row) = try await oneReading(weight: 97.46, waist: 99.46)
        let sheet = makeSheet(h, editing: row)
        await sheet.prepare()
        sheet.takenAt = at("2031-01-29", 6, 30)
        sheet.advance()
        await sheet.skipWaist()
        XCTAssertEqual(sheet.phase, .saved)
        let weightRows = try await rows(h, "weight")
        let waistRows = try await rows(h, "waist")
        XCTAssertEqual(stored(weightRows.first, .weight), 97.46)
        XCTAssertEqual(stored(waistRows.first, .waist), 99.46)
    }

    /// Only the field that was typed in goes through the display unit.
    func testFinding6ChangingOneFieldLeavesTheOtherAtItsExactStoredValue() async throws {
        let (h, row) = try await oneReading(weight: 97.46, waist: 99.46)
        let waistEdit = makeSheet(h, editing: row)
        await waistEdit.prepare()
        waistEdit.advance()
        waistEdit.waistText = "99.0"
        await waistEdit.save()
        XCTAssertEqual(waistEdit.phase, .saved)
        var weightRows = try await rows(h, "weight")
        var waistRows = try await rows(h, "waist")
        XCTAssertEqual(stored(weightRows.first, .weight), 97.46, "the untouched weight is not rewritten")
        XCTAssertEqual(stored(waistRows.first, .waist), 99.0, "the typed waist is saved")

        let (h2, row2) = try await oneReading(weight: 97.46, waist: 99.46)
        let weightEdit = makeSheet(h2, editing: row2)
        await weightEdit.prepare()
        weightEdit.weightText = "97.0"
        weightEdit.advance()
        await weightEdit.save()
        XCTAssertEqual(weightEdit.phase, .saved)
        weightRows = try await rows(h2, "weight")
        waistRows = try await rows(h2, "waist")
        XCTAssertEqual(stored(weightRows.first, .weight), 97.0, "the typed weight is saved")
        XCTAssertEqual(stored(waistRows.first, .waist), 99.46, "the untouched waist is not rewritten")
    }

    /// Finding 18, route 1: a value stored in kilograms and centimetres, shown in pounds and inches.
    /// 97.5 kg shows as "215.0" and 99.0 cm as "39.0"; parsed back they are 97.5224 kg and 99.06 cm.
    func testFinding18AnImperialEditWithNothingChangedKeepsTheExactMetricValues() async throws {
        for movesTheDate in [false, true] {
            let (h, row) = try await oneReading(weight: 97.5, waist: 99.0, shownIn: .imperial)
            let sheet = makeSheet(h, unitSystem: .imperial, editing: row)
            await sheet.prepare()
            XCTAssertEqual(sheet.weightText, "215.0")
            if movesTheDate { sheet.takenAt = at("2031-01-29", 6, 30) }
            sheet.advance()
            XCTAssertEqual(sheet.waistText, "39.0")
            await sheet.save()
            XCTAssertEqual(sheet.phase, .saved, "date moved: \(movesTheDate)")

            let weights = try await rows(h, "weight")
            let waists = try await rows(h, "waist")
            XCTAssertEqual(weights.count, 1)
            XCTAssertEqual(waists.count, 1)
            XCTAssertEqual(stored(weights.first, .weight), 97.5, "date moved: \(movesTheDate)")
            XCTAssertEqual(stored(waists.first, .waist), 99.0, "date moved: \(movesTheDate)")
        }
    }

    /// Finding 6, second route: a row stored in pounds and inches, shown in kilograms and
    /// centimetres. 215.0 lb is 97.5224 kg and shows as "97.5"; 39.0 in is 99.06 cm, "99.1".
    func testFinding6AMetricEditOfARowStoredInPoundsAndInchesKeepsItsValue() async throws {
        for movesTheDate in [false, true] {
            let (h, row) = try await oneReading(weight: 215.0, waist: 39.0, weightUnit: "lb", waistUnit: "in")
            let kilograms = try XCTUnwrap(stored(row.weightRow, .weight))
            let centimetres = try XCTUnwrap(stored(row.waistRow, .waist))
            let sheet = makeSheet(h, editing: row)
            await sheet.prepare()
            XCTAssertEqual(sheet.weightText, "97.5")
            if movesTheDate { sheet.takenAt = at("2031-01-29", 6, 30) }
            sheet.advance()
            XCTAssertEqual(sheet.waistText, "99.1")
            await sheet.save()
            XCTAssertEqual(sheet.phase, .saved, "date moved: \(movesTheDate)")

            let weightRows = try await rows(h, "weight")
            let waistRows = try await rows(h, "waist")
            let weight = try XCTUnwrap(stored(weightRows.first, .weight))
            let waist = try XCTUnwrap(stored(waistRows.first, .waist))
            XCTAssertEqual(weight, kilograms, accuracy: 1e-9, "date moved: \(movesTheDate)")
            XCTAssertEqual(waist, centimetres, accuracy: 1e-9, "date moved: \(movesTheDate)")
        }
    }

    // MARK: - Findings 1 and 2: editing, Skip and its note

    /// Finding 1. A reading saved through Skip has a weight and no waist. Its edit is saved from the
    /// primary button, and Skip, with the note written for a new weigh-in, is not offered.
    func testFinding1EditingAReadingWithNoWaistSavesTheWeightFromThePrimaryButton() async throws {
        let h = try await makeHarness(today: "2031-02-05",
                                      rows: weekRows([1, 2, 3, 4]) + [marker("weight", "2031-01-20", 98.9)])
        let listed = try await history(h)
        let row = try XCTUnwrap(listed.rows.first { $0.day == "2031-01-20" })
        XCTAssertNil(row.waistRow)
        XCTAssertTrue(row.canEdit)
        let waistsBefore = try await rows(h, "waist")

        let sheet = makeSheet(h, editing: row)
        await sheet.prepare()
        XCTAssertEqual(sheet.weightText, "98.9")
        sheet.weightText = "98.7"
        sheet.advance()
        XCTAssertEqual(sheet.step, .waist)
        XCTAssertFalse(sheet.canEditWaist, "stage 1 adds a waist only with a new weigh-in")
        XCTAssertEqual(sheet.primaryTitle, "Save")
        XCTAssertTrue(sheet.canSave, "the weight alone can be saved")
        XCTAssertFalse(sheet.offersSkip, "Save is already the weight-only save")
        let note: String? = sheet.skipNote
        XCTAssertNil(note, "the note describes a new weigh-in")

        sheet.weightText = "400"
        XCTAssertFalse(sheet.canSave, "a weight out of range still cannot be saved")
        sheet.weightText = "98.7"

        await sheet.save()
        XCTAssertEqual(sheet.phase, .saved)
        let weights = try await rows(h, "weight")
        XCTAssertEqual(weights.count, 5, "an edit adds no row")
        XCTAssertEqual(weights.first { $0.id == row.weightRow?.id }?.value, 98.7)
        let waistsAfter = try await rows(h, "waist")
        XCTAssertEqual(waistsAfter, waistsBefore, "no waist is written")
    }

    /// Finding 2. Skip on an edit keeps the stored waist, so the note that says the week will read
    /// "Not measured this week" is not shown for it.
    func testFinding2TheSkipNoteIsOnlyShownForANewWeighIn() async throws {
        let h = try await makeHarness(today: "2031-02-05", rows: weekRows([1, 2, 3, 4]))
        let listed = try await history(h)
        let row = try XCTUnwrap(listed.rows.first { $0.day == Fixture.weighDay(2) })
        XCTAssertNotNil(row.waistRow)
        let waistsBefore = try await rows(h, "waist")

        let edit = makeSheet(h, editing: row)
        await edit.prepare()
        edit.advance()
        let editNote: String? = edit.skipNote
        XCTAssertNil(editNote, "the stored waist stays: the week will not read \"Not measured this week\"")
        XCTAssertTrue(edit.offersSkip, "Skip is still offered: it saves the weight and leaves the waist")
        await edit.skipWaist()
        XCTAssertEqual(edit.phase, .saved)
        let waistsAfter = try await rows(h, "waist")
        XCTAssertEqual(waistsAfter, waistsBefore, "the waist row is untouched")

        let new = makeSheet(h)
        await new.prepare()
        new.weightText = "97.5"
        new.advance()
        let newNote: String? = new.skipNote
        XCTAssertEqual(newNote, "Saves the weight only. Waist for this week will read \"Not measured this week\".")
        XCTAssertTrue(new.offersSkip)
    }

    // MARK: - Finding 19: the no-readings state

    /// A phase that starts today, with one weigh-in from before it: the phase has no reading yet.
    /// §10.1 draws a dash on the card, and §10.2 (frame B2) makes "Log weigh-in" the primary action.
    func testFinding19NoReadingsShowsNoCardValueAndMakesLoggingPrimary() {
        let phase = CutScorecardPhase(name: "Fixture cut", startDay: "2031-01-15", targetWeightKg: 94.0,
                                      rateLowPercentPerWeek: 0.40, rateHighPercentPerWeek: 1.20)
        let input = CutScorecardInput(
            weights: [CutScorecardReading(day: "2031-01-08", takenAt: Fixture.takenAt("2031-01-08"), value: 97.5)],
            waists: [], phase: phase, parameters: Fixture.parameters, today: "2031-01-15")
        let shown = CutScorecardPresenter.present(CutScorecard.evaluate(input), input: input,
                                                  context: CutScorecardPresentationContext(locale: british))
        XCTAssertEqual(shown.status, .noReadings)
        XCTAssertEqual(shown.card.status, .noReadings)
        XCTAssertNil(shown.card.value, "the card draws the dash, not the weight from before the phase")
        XCTAssertNil(shown.card.unit)
        XCTAssertEqual(shown.card.caption, "Log your first weigh-in")
        XCTAssertFalse(CutScorecardPresenter.rowValue(shown.card)?.contains("97.5") ?? false,
                       "the Health row does not pair that caption with a weight")
        XCTAssertTrue(shown.logWeighInIsPrimary)
        XCTAssertEqual(shown.verdict.title, "Log a weigh-in to begin")
        XCTAssertEqual(shown.weight?.value, "97.5", "the curve keeps the earlier point")
        XCTAssertEqual(shown.historyValue, "1 weigh-in")
    }

    // MARK: - Finding 10: stored phases that cannot be read

    private func readableDraft(_ settings: CutScorecardSettings, today: String) -> ScorecardPhaseDraft {
        var draft = ScorecardPhaseDraft.current(settings: settings, today: today)
        draft.name = "Replacement cut"
        draft.targetWeightKg = 92.0
        draft.rateLowPercentPerWeek = 0.40
        draft.rateHighPercentPerWeek = 1.20
        draft.parameters = Fixture.parameters
        return draft
    }

    /// Two readable phases and one of a kind this version does not know. The whole string fails to
    /// decode, so a save built on "no phases" would replace all three.
    func testFinding10PhasesWithOneUndecodableElementAreNeverOverwrittenByASave() throws {
        let defaults = try freshDefaults()
        let settings = CutScorecardSettings(defaults: defaults)
        let later = CutScorecardStoredPhase(kind: .cut, name: "Second cut", startDay: "2031-03-03",
                                            targetWeightKg: 90.0, rateLowPercentPerWeek: 0.40,
                                            rateHighPercentPerWeek: 1.20)
        settings.phases = [fixturePhase, later]
        settings.parameters = Fixture.parameters
        XCTAssertFalse(settings.phasesNeedAttention, "a readable string needs no attention")
        let readable = try XCTUnwrap(defaults.string(forKey: "cutScorecard.phases"))
        XCTAssertEqual(readable.last, "]")
        let damaged = String(readable.dropLast()) + ",{\"kind\":\"bulk\",\"name\":\"Fixture bulk\"}]"
        defaults.set(damaged, forKey: "cutScorecard.phases")

        XCTAssertTrue(settings.phases.isEmpty, "ruling R30: an unreadable string yields no phases")
        XCTAssertTrue(settings.phasesNeedAttention)

        let draft = readableDraft(settings, today: "2031-06-05")
        XCTAssertTrue(draft.invalidFields.isEmpty, "the draft's own values are fine")
        XCTAssertFalse(draft.save(to: settings), "nothing is saved over phases that cannot be read")
        XCTAssertEqual(defaults.string(forKey: "cutScorecard.phases"), damaged, "byte-identical after the save")
        XCTAssertFalse(draft.startingNewPhase(today: "2031-06-05").save(to: settings))
        XCTAssertEqual(defaults.string(forKey: "cutScorecard.phases"), damaged)

        let sheet = CutScorecardPresenter.phaseSheet(draft, today: "2031-06-05", previousPhaseName: nil,
                                                     unitSystem: .metric, locale: british,
                                                     phasesNeedAttention: settings.phasesNeedAttention)
        XCTAssertFalse(sheet.canSave, "the sheet does not offer a save that would be refused")
        XCTAssertFalse((sheet.storedPhasesNote ?? "").isEmpty, "and it says the stored phases need attention")
    }

    func testFinding10AStringThatIsNotAPhaseListIsNotOverwrittenEither() throws {
        for garbage in ["not json", "[1,2,3]", "[{\"kind\":\"cut\"}]"] {
            let defaults = try freshDefaults()
            defaults.set(garbage, forKey: "cutScorecard.phases")
            let settings = CutScorecardSettings(defaults: defaults)
            XCTAssertTrue(settings.phasesNeedAttention, garbage)
            XCTAssertFalse(readableDraft(settings, today: "2031-06-05").save(to: settings), garbage)
            XCTAssertEqual(defaults.string(forKey: "cutScorecard.phases"), garbage)
        }
    }

    func testFinding10ReadableOrAbsentPhasesSaveAsBefore() throws {
        let defaults = try freshDefaults()
        let settings = CutScorecardSettings(defaults: defaults)
        XCTAssertFalse(settings.phasesNeedAttention, "nothing stored: nothing needs attention")
        let first = readableDraft(settings, today: "2031-01-06")
        let sheet = CutScorecardPresenter.phaseSheet(first, today: "2031-01-06", previousPhaseName: nil,
                                                     unitSystem: .metric, locale: british,
                                                     phasesNeedAttention: settings.phasesNeedAttention)
        XCTAssertTrue(sheet.canSave)
        XCTAssertNil(sheet.storedPhasesNote)
        XCTAssertTrue(first.save(to: settings))
        XCTAssertEqual(settings.phases.map(\.name), ["Replacement cut"])
        XCTAssertFalse(settings.phasesNeedAttention)
        XCTAssertNil(defaults.object(forKey: "cutScorecard.phases.unreadable"), "no side copy is written")
    }

    // MARK: - Finding 12: a phase cannot start before the one before it

    private func fixtureDraft(today: String = "2031-01-06") -> ScorecardPhaseDraft {
        var draft = ScorecardPhaseDraft.firstUse(today: today)
        draft.name = "Fixture cut"
        draft.targetWeightKg = 94.0
        draft.rateLowPercentPerWeek = 0.40
        draft.rateHighPercentPerWeek = 1.20
        draft.parameters = Fixture.parameters
        return draft
    }

    /// Two stored phases: "Fixture cut" from 2031-01-06 and "Second cut" from 2031-03-03.
    private func twoPhases() throws -> CutScorecardSettings {
        let settings = CutScorecardSettings(defaults: try freshDefaults())
        XCTAssertTrue(fixtureDraft().save(to: settings))
        var next = ScorecardPhaseDraft.current(settings: settings, today: "2031-03-03")
            .startingNewPhase(today: "2031-03-03")
        next.name = "Second cut"
        next.targetWeightKg = 90.0
        XCTAssertTrue(next.save(to: settings))
        XCTAssertEqual(settings.phases.map(\.startDay), ["2031-01-06", "2031-03-03"])
        return settings
    }

    func testFinding12TheActivePhaseCannotBeMovedBeforeThePhaseBeforeIt() throws {
        let settings = try twoPhases()
        let before = settings.phases
        var edit = ScorecardPhaseDraft.current(settings: settings, today: "2031-06-05")
        XCTAssertEqual(edit.name, "Second cut")
        XCTAssertEqual(edit.earliestStartDay, "2031-01-06")

        edit.startDay = "2030-12-01"
        XCTAssertEqual(edit.invalidFields, [.startDay])
        XCTAssertNotNil(edit.validationMessage)
        XCTAssertFalse(edit.canSave)
        XCTAssertFalse(edit.save(to: settings))
        XCTAssertEqual(settings.phases, before, "nothing is written")
        XCTAssertEqual(settings.activePhase(on: "2031-06-05")?.name, "Second cut")

        edit.startDay = "2031-02-03"
        XCTAssertEqual(edit.invalidFields, [], "any day on or after the earlier phase's start is fine")
        XCTAssertTrue(edit.save(to: settings))
        XCTAssertEqual(settings.phases.map(\.startDay), ["2031-01-06", "2031-02-03"])
        XCTAssertEqual(settings.activePhase(on: "2031-06-05")?.name, "Second cut", "it is still the active phase")
    }

    func testFinding12ANewPhaseCannotStartBeforeThePhaseItFollows() throws {
        let settings = try twoPhases()
        let before = settings.phases
        var next = ScorecardPhaseDraft.current(settings: settings, today: "2031-06-05")
            .startingNewPhase(today: "2031-06-05")
        next.name = "Third cut"
        XCTAssertEqual(next.earliestStartDay, "2031-03-03", "the phase it follows")

        next.startDay = "2031-02-01"
        XCTAssertEqual(next.invalidFields, [.startDay])
        XCTAssertFalse(next.save(to: settings))
        XCTAssertEqual(settings.phases, before)

        next.startDay = "2031-06-05"
        XCTAssertTrue(next.save(to: settings))
        XCTAssertEqual(settings.activePhase(on: "2031-06-05")?.name, "Third cut")
    }

    /// V5: with one phase stored, or none, the start date is free.
    func testFinding12ASinglePhaseCanStillBeBackdated() throws {
        let settings = CutScorecardSettings(defaults: try freshDefaults())
        var first = fixtureDraft()
        XCTAssertNil(first.earliestStartDay)
        first.startDay = "2030-06-03"
        XCTAssertTrue(first.save(to: settings))

        var edit = ScorecardPhaseDraft.current(settings: settings, today: "2031-06-05")
        XCTAssertNil(edit.earliestStartDay)
        edit.startDay = "2029-12-31"
        XCTAssertEqual(edit.invalidFields, [])
        XCTAssertTrue(edit.save(to: settings))
        XCTAssertEqual(settings.phases.map(\.startDay), ["2029-12-31"])
    }

    // MARK: - Finding 11: a withheld card keeps its position

    private func merged(_ edited: [DashboardCard], saved: [DashboardCard],
                        scorecardEnabled: Bool = false) -> [DashboardCard] {
        TodayCardsEditorPresentation.mergedSelection(
            edited: edited, raw: DashboardCardPrefs.encode(saved),
            available: TodayCardsEditorPresentation.availableCards(redesign: true, scorecardEnabled: scorecardEnabled))
    }

    func testFinding11AWithheldScorecardCardKeepsItsSavedPositionWhenTheEditorSaves() {
        XCTAssertEqual(merged([.hrv, .stress], saved: [.hrv, .scorecard, .stress]), [.hrv, .scorecard, .stress],
                       "a save that changed nothing writes the selection back as it was")
        XCTAssertEqual(merged([.hrv, .stress], saved: [.scorecard, .hrv, .stress]), [.scorecard, .hrv, .stress],
                       "saved first: it stays first")
        XCTAssertEqual(merged([.hrv, .stress], saved: [.hrv, .stress, .scorecard]), [.hrv, .stress, .scorecard])
        XCTAssertEqual(merged([.stress, .hrv], saved: [.hrv, .scorecard, .stress]), [.stress, .hrv, .scorecard],
                       "after a reorder it follows the card it was saved after")
        XCTAssertEqual(merged([.stress], saved: [.hrv, .scorecard, .stress]), [.scorecard, .stress],
                       "the card before it was removed: it goes first")
        XCTAssertEqual(merged([.hrv, .sleep, .stress], saved: [.hrv, .scorecard, .stress]),
                       [.hrv, .scorecard, .sleep, .stress])
        XCTAssertEqual(merged([], saved: [.hrv, .scorecard, .stress]), [.scorecard],
                       "the choice survives even when every listed card is removed")
    }

    func testFinding11TheEditedCardsAreWrittenAsEdited() {
        let saved: [DashboardCard] = [.hrv, .scorecard, .stress, .sleep]
        for edited: [DashboardCard] in [[.hrv, .stress, .sleep], [.sleep, .stress, .hrv], [.stress], [.vitality, .hrv]] {
            let result = merged(edited, saved: saved)
            XCTAssertEqual(result.filter { $0 != .scorecard }, edited, "\(edited)")
            XCTAssertEqual(result.filter { $0 == .scorecard }.count, 1, "\(edited)")
        }
        // Nothing is withheld while the editor lists the card, or when it was never saved.
        XCTAssertEqual(merged([.stress, .scorecard, .hrv], saved: saved, scorecardEnabled: true),
                       [.stress, .scorecard, .hrv])
        XCTAssertEqual(merged([.hrv, .stress], saved: saved, scorecardEnabled: true), [.hrv, .stress],
                       "removed by the owner with the flag on: it stays removed")
        XCTAssertEqual(merged([.stress, .hrv], saved: [.hrv, .stress]), [.stress, .hrv])
    }

    // MARK: - Finding 5: the caption for a selection emptied by the scorecard gate

    private func caption(_ cards: [DashboardCard], hydration: Bool = false, coach: Bool = false,
                         scorecard: Bool = false) -> String? {
        TodayCardResolver.gatedCaption(raw: DashboardCardPrefs.encode(cards), hydrationEnabled: hydration,
                                       coachEnabled: coach, scorecardEnabled: scorecard, visibleKeyMetrics: nil)
    }

    func testFinding5ASelectionOfOnlyTheScorecardCardWithTheFlagOffExplainsItself() {
        XCTAssertEqual(caption([.scorecard]), "Nothing to show while Scorecard is off.",
                       "not nil, which the tile draws as \"No data\"")
        XCTAssertNil(caption([.scorecard], scorecard: true), "flag on: the card renders")
        XCTAssertNil(caption([.hrv, .scorecard]), "another card renders: nothing to explain")

        let both = caption([.scorecard, .hydration])
        XCTAssertTrue(both?.contains("Scorecard") == true, "both gates are named: \(String(describing: both))")
        XCTAssertTrue(both?.contains("Hydration") == true, "both gates are named: \(String(describing: both))")
        XCTAssertEqual(caption([.scorecard, .hydration], hydration: true), nil, "Hydration renders")
        let all = caption([.scorecard, .hydration, .coach])
        for name in ["Scorecard", "Hydration", "Coach"] {
            XCTAssertTrue(all?.contains(name) == true, "\(name) is named: \(String(describing: all))")
        }
    }

    func testFinding5TheHydrationAndCoachCaptionsAreUnchanged() {
        for scorecard in [false, true] {
            XCTAssertEqual(caption([.hydration], scorecard: scorecard), "Nothing to show while Hydration is off.")
            XCTAssertEqual(caption([.coach], scorecard: scorecard), "Nothing to show while Coach is off.")
            XCTAssertEqual(caption([.hydration, .coach], scorecard: scorecard),
                           "Nothing to show while Hydration and Coach are off.")
            XCTAssertNil(caption([.hydration], hydration: true, scorecard: scorecard))
            XCTAssertNil(caption([.coach], coach: true, scorecard: scorecard))
            XCTAssertNil(caption([.hrv, .hydration, .coach], scorecard: scorecard))
            XCTAssertNil(caption(DashboardCard.defaultSelection, scorecard: scorecard))
        }
    }

    // MARK: - Finding 7: no live scorecard screen while the flag is off

    func testFinding7TheScorecardAndHistoryScreensAreNotReachableWhileTheFlagIsOff() throws {
        XCTAssertFalse(CutScorecardPresenter.screenIsReachable(flagEnabled: false))
        XCTAssertTrue(CutScorecardPresenter.screenIsReachable(flagEnabled: true))

        // The signal a pushed screen dismisses on: the flag object publishes the change at once,
        // whoever wrote the key (Settings is a root-level sheet over a different tab's stack).
        let defaults = try freshDefaults()
        defaults.set(true, forKey: "noop.cutScorecardEnabled")
        let flag = CutScorecardFlag(defaults: defaults)
        var reachable: [Bool] = []
        let observer = flag.$isEnabled.sink { reachable.append(CutScorecardPresenter.screenIsReachable(flagEnabled: $0)) }
        defaults.set(false, forKey: "noop.cutScorecardEnabled")
        XCTAssertEqual(reachable, [true, false], "published before the write returns")
        observer.cancel()
    }

    /// The two pushed screens are in StrandiOS, which this bundle cannot load: the wiring is held
    /// by their source. Each observes the flag and reads the one reachability decision.
    func testFinding7BothPushedScorecardScreensFollowTheFlag() throws {
        for file in ["StrandiOS/Scorecard/ScorecardView.swift", "StrandiOS/Scorecard/WeighInHistoryView.swift"] {
            let text = try source(file)
            XCTAssertTrue(text.contains("CutScorecardFlag"), "\(file) observes the flag")
            XCTAssertTrue(text.contains("screenIsReachable"), "\(file) reads the reachability decision")
            XCTAssertTrue(text.contains("dismiss"), "\(file) leaves the stack when the flag goes off")
        }
    }

    // MARK: - Finding 13: the denied state clears when permission is granted later

    func testFinding13TheDeniedReminderStateClearsWhenPermissionIsGrantedLater() {
        typealias Status = WeighInReminderStatus
        func status(_ storedOn: Bool, _ systemDenied: Bool, _ current: Status) -> Status {
            CutScorecardPresenter.reminderStatus(storedOn: storedOn, systemDenied: systemDenied, current: current)
        }
        XCTAssertEqual(status(false, false, .denied), .off,
                       "allowed since: the row stops saying notifications are off, and the switch stays off")
        XCTAssertEqual(status(false, true, .denied), .denied, "still denied: the row still says so")
        XCTAssertEqual(status(false, false, .on), .off)
        XCTAssertEqual(status(false, false, .off), .off)
        XCTAssertEqual(status(false, true, .off), .off, "never asked for: nothing is reported as denied")
        for current in [Status.off, .on, .denied] {
            XCTAssertEqual(status(true, true, current), .denied, "stored on, denied by the system")
            XCTAssertEqual(status(true, false, current), .on, "stored on and allowed")
        }
    }

    // MARK: - Finding 16: a revision during the first load is not missed

    /// The provider publishes new readings while the first load is still evaluating its (empty)
    /// snapshot. The model must already be following the provider, so it loads again.
    func testFinding16ARevisionChangeDuringTheFirstLoadIsNotLost() async throws {
        let h = try await makeHarness(today: Fixture.weighDay(4), rows: weekRows([1, 2, 3, 4]), refreshes: false)
        let today = Fixture.weighDay(4)
        let empty = Fixture.input(today: today, lifts: false, without: Set(1...22))
        XCTAssertTrue(empty.weights.isEmpty)
        let full = Fixture.input(today: today, lifts: false)
        var calls = 0
        let provider = h.provider
        let zone = utc
        let locale = british
        let clock = h.clock
        let model = CutScorecardModel(
            repository: h.repo, provider: h.provider, settings: h.settings, unitSystem: { .metric },
            now: { clock.now }, timeZone: { zone }, locale: { locale },
            evaluate: { _ in
                calls += 1
                guard calls == 1 else { return (input: full, result: CutScorecard.evaluate(full)) }
                let before = provider.revision
                await provider.refresh()        // the stored weigh-ins arrive mid-load
                XCTAssertGreaterThan(provider.revision, before, "the test's premise: the revision moved")
                return (input: empty, result: CutScorecard.evaluate(empty))
            })

        await model.load()
        // One short wait: a load that was started by the missed revision publishes at once.
        await waitUntil("a second load that shows the stored weight", timeout: 3) {
            guard calls >= 2, case .loaded(let shown) = model.state else { return false }
            return shown.card.value == "97.6"
        }
    }

    // MARK: - Finding 17: the weigh-in sheet's time follows the clock-format setting

    /// `AppClock.formattingLocale` carries the reader's hour cycle as a locale keyword (#1821).
    /// Given such a locale the caption's time obeys it, whatever the region's own default is.
    func testFinding17TheWeighInTimeTextFollowsTheHourCycleOfItsLocale() {
        let taken = at("2031-02-05", 7, 2)
        func text(_ identifier: String) -> String {
            CutScorecardPresenter.weighInDateText(takenAt: taken, now: taken, timeZone: utc,
                                                  locale: Locale(identifier: identifier))
        }
        XCTAssertEqual(text("en_IN@hours=h23"), "Today · Wed 5 Feb · 07:02", "24-hour chosen in a 12-hour region")
        XCTAssertEqual(text("en_US@hours=h23"), "Today · Wed 5 Feb · 07:02")
        XCTAssertEqual(text("en_GB@hours=h23"), "Today · Wed 5 Feb · 07:02")
        let twelve = text("en_GB@hours=h12")
        XCTAssertTrue(twelve.hasPrefix("Today · Wed 5 Feb · 7:02"), "12-hour chosen in a 24-hour region: \(twelve)")
        XCTAssertTrue(twelve.lowercased().hasSuffix("am"), twelve)
    }

    /// The sheet's locale comes from `ScorecardContext.live` in StrandiOS, which this bundle
    /// cannot load: held by its source.
    func testFinding17TheLiveScorecardContextUsesTheClockFormatLocale() throws {
        let text = try source("StrandiOS/Scorecard/ScorecardKit.swift")
        XCTAssertTrue(text.contains("AppClock.formattingLocale"),
                      "the live context hands the presenter the locale that carries the hour cycle")
        XCTAssertFalse(text.contains("locale: { AppLanguage.activeLocale }"),
                       "the bare language locale drops the Clock format setting")
    }

    // MARK: - Finding 20: date field order

    /// Wed 29 Jan 2031. Chinese writes month before day, with 日. The literals are what
    /// `setLocalizedDateFormatFromTemplate` produced in a standalone run; whether a space separates
    /// the weekday differs between zh_Hans_CN, zh_Hant_TW and zh_Hant_HK, so it is not asserted.
    func testFinding20ChineseScorecardDatesPutTheMonthBeforeTheDay() {
        let weekdays = ["zh_Hans_CN": "周三", "zh-Hans": "周三", "zh_Hant_TW": "週三", "zh-Hant": "週三",
                        "zh_Hant_HK": "週三"]
        let taken = at("2031-01-29", 7, 2)
        for (identifier, weekday) in weekdays {
            let locale = Locale(identifier: identifier)
            let words = CutScorecardPresenter.Wording(unitSystem: .metric, locale: locale)
            XCTAssertEqual(words.shortDate("2031-01-29"), "1月29日", identifier)
            let date = words.date("2031-01-29")
            XCTAssertTrue(date.hasPrefix("1月29日") && date.hasSuffix(weekday), "\(identifier): \(date)")
            let withYear = words.dateWithYear("2031-01-29")
            XCTAssertTrue(withYear.hasPrefix("2031年1月29日") && withYear.hasSuffix(weekday), "\(identifier): \(withYear)")
            let caption = CutScorecardPresenter.weighInDateText(takenAt: taken, now: at("2031-02-05", 7, 2),
                                                                timeZone: utc, locale: locale)
            XCTAssertTrue(caption.contains("1月29日"), "\(identifier): \(caption)")
            XCTAssertFalse(caption.contains("29 1月"), "\(identifier): \(caption)")
        }
    }

    /// Every other locale keeps the fixed day-first pattern of the approved frames, with the
    /// locale's own words. The literals are the committed output, from a standalone run.
    func testFinding20OtherLocalesKeepTheirDayFirstDates() {
        let expected: [(String, String, String, String)] = [
            ("en_GB", "Wed 29 Jan", "29 Jan", "Wed 29 Jan 2031"),
            ("en_US", "Wed 29 Jan", "29 Jan", "Wed 29 Jan 2031"),
            ("en_IN", "Wed 29 Jan", "29 Jan", "Wed 29 Jan 2031"),
            ("de_DE", "Mi. 29 Jan.", "29 Jan.", "Mi. 29 Jan. 2031"),
            ("fr_FR", "mer. 29 janv.", "29 janv.", "mer. 29 janv. 2031"),
            ("es_ES", "mié 29 ene", "29 ene", "mié 29 ene 2031"),
            ("ja_JP", "水 29 1月", "29 1月", "水 29 1月 2031"),
        ]
        for (identifier, date, short, withYear) in expected {
            let words = CutScorecardPresenter.Wording(unitSystem: .metric, locale: Locale(identifier: identifier))
            XCTAssertEqual(words.date("2031-01-29"), date, identifier)
            XCTAssertEqual(words.shortDate("2031-01-29"), short, identifier)
            XCTAssertEqual(words.dateWithYear("2031-01-29"), withYear, identifier)
        }
        let taken = at("2031-01-29", 7, 2)
        XCTAssertEqual(CutScorecardPresenter.weighInDateText(takenAt: taken, now: at("2031-02-05", 7, 2), timeZone: utc,
                                                             locale: british), "Wed 29 Jan · 07:02")
    }
}
