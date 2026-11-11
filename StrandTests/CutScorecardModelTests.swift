import XCTest
import StrandAnalytics
import WhoopStore
import StrandImport
@testable import Strand

// Stage 1 (weigh-in and scorecard), work package 1-7: everything below the views. Specification
// §10 (screen states), §10.3 (weigh-in sheet), §10.4 (history), §10.5 (phase and rules sheet), §9
// and rulings R25, R30, R32. Frames C1 to C10, D1 to D5 and E1 to E4 of design/round6-scorecard.
// Written before the implementation exists.
//
// The views live in StrandiOS, which the macOS-hosted StrandTests bundle cannot load, so every rule
// a view follows is held by a type in Strand/Data that these tests can reach.
//
// API ASSUMED BY THESE TESTS (new, in Strand/Data/CutScorecardModel.swift unless stated; the
// presentation types are assumed at the top of CutScorecardPresenterTests.swift)
//
//     typealias CutScorecardEvaluation = (input: CutScorecardInput, result: CutScorecardResult)
//
//     /// The scorecard screen and the Today card read this one object.
//     @MainActor final class CutScorecardModel: ObservableObject {
//         enum State: Equatable { case idle, loading, loaded(CutScorecardPresentation) }
//
//         /// `.idle` until the first load, and whenever the flag is off.
//         @Published private(set) var state: State
//
//         /// `evaluate` nil: `CutScorecardInputBuilder(repository:provider:settings:timeZone:).build(today:)`
//         /// followed by `CutScorecard.evaluate`. Tests pass a closure to hold a load open.
//         init(repository: Repository, provider: BodyMeasurementProvider, settings: CutScorecardSettings,
//              unitSystem: @escaping () -> UnitSystem,
//              now: @escaping () -> Date = { Date() },
//              timeZone: @escaping () -> TimeZone = { TimeZone.current },
//              locale: @escaping () -> Locale = { AppLanguage.activeLocale },
//              evaluate: (@MainActor (_ today: String) async -> CutScorecardEvaluation)? = nil)
//
//         /// Flag off: sets `.idle` and reads nothing. Flag on: `.loading` on the first load, then
//         /// `.loaded`. A load that finishes after a later one began publishes nothing.
//         func load() async
//     }
//
//     enum WeighInFieldIssue: Equatable { case notANumber, belowMinimum, aboveMaximum }
//
//     /// The weigh-in sheet: step 1 weight, step 2 waist, one instant for both.
//     @MainActor final class WeighInSheetModel: ObservableObject {
//         enum Step: Equatable { case weight, waist }
//         enum Phase: Equatable { case editing, saving, failed, saved }
//
//         init(weighIns: WeighInStore, unitSystem: UnitSystem,
//              now: @escaping () -> Date = { Date() },
//              timeZone: @escaping () -> TimeZone = { TimeZone.current },
//              locale: Locale = AppLanguage.activeLocale,
//              editing: WeighInHistoryRow? = nil)
//
//         @Published var weightText: String
//         @Published var waistText: String
//         @Published var takenAt: Date
//         @Published private(set) var step: Step
//         @Published private(set) var phase: Phase
//
//         /// Reads the earlier readings (prefill, hints, the week note). Writes nothing.
//         func prepare() async
//
//         var weightUnit: String                  // "kg" or "lb"
//         var waistUnit: String                   // "cm" or "in"
//         var weightIssue: WeighInFieldIssue?     // nil for an empty field and for a valid one
//         var waistIssue: WeighInFieldIssue?
//         var weightHint: String
//         var weightHintIsError: Bool
//         var waistHint: String
//         var waistHintIsError: Bool
//         var dateIsInTheFuture: Bool
//         var dateHint: String                    // "Future dates cannot be picked."
//         var dateNote: String?                   // the week the reading falls in, and what is already there
//         var canAdvance: Bool                    // "Next" on step 1
//         var canSave: Bool                       // "Save" on step 2
//         var primaryTitle: String                // "Next", "Save", "Saving…", "Try again"
//         var failureMessage: String?             // only in phase .failed
//         var skipNote: String
//
//         func advance()                          // step 1 to step 2 when canAdvance. Writes nothing
//         func back()
//         func save() async                       // step 2: weight and waist
//         func skipWaist() async                  // step 2: the weight only
//     }
//
//     struct WeighInHistoryRow: Equatable, Identifiable {
//         var id: String
//         var day: String
//         var takenAt: Int?               // nil for an Apple Health day
//         var dateText: String            // "Wed 5 Feb"
//         var weightText: String?
//         var waistText: String?          // nil is drawn as `WeighInHistory.notMeasuredText`
//         var source: BodyMeasurementSource
//         var caption: String             // "Represents its week · Lab Book"
//         var representsWeek: Bool
//         var canEdit: Bool
//         var canDelete: Bool
//         var weightRow: LabMarkerRow?    // the stored rows an edit or delete acts on
//         var waistRow: LabMarkerRow?
//     }
//
//     struct WeighInHistory: Equatable {
//         var rows: [WeighInHistoryRow]   // newest first
//         var weightUnit: String
//         var waistUnit: String
//         var notMeasuredText: String     // "not measured"
//         var emptyText: String?          // "No weigh-ins yet" exactly when rows is empty
//         var legend: String?             // what the dot means; nil when rows is empty
//         var unlistedCount: Int          // weight and waist rows in a unit that is not recognised
//         var unlistedNote: String?       // nil when unlistedCount is 0
//     }
//
//     struct WeighInDeleteConfirmation: Equatable {
//         var title: String; var detail: String; var confirmTitle: String; var cancelTitle: String
//     }
//
//     extension CutScorecardPresenter {
//         /// Pure. `weights` and `waists` are `WeighInStore.readings(_:)`, the R25 union.
//         static func history(weights: [LabMarkerRow], waists: [LabMarkerRow],
//                             appleHealth: [(day: String, value: Double)],
//                             unitSystem: UnitSystem, locale: Locale) -> WeighInHistory
//         static func deleteConfirmation(for row: WeighInHistoryRow, unitSystem: UnitSystem,
//                                        locale: Locale) -> WeighInDeleteConfirmation
//     }
//
//     @MainActor final class WeighInHistoryModel: ObservableObject {
//         enum State: Equatable { case loading, loaded(WeighInHistory) }
//         @Published private(set) var state: State                    // .loading until the first load
//         @Published private(set) var pendingDelete: WeighInHistoryRow?
//
//         init(weighIns: WeighInStore, provider: BodyMeasurementProvider,
//              unitSystem: @escaping () -> UnitSystem,
//              locale: @escaping () -> Locale = { AppLanguage.activeLocale })
//
//         func load() async
//         var deleteConfirmation: WeighInDeleteConfirmation?          // set exactly while pendingDelete is
//         func requestDelete(_ row: WeighInHistoryRow)                // ignored when !row.canDelete
//         func cancelDelete()
//         func confirmDelete() async                                  // deletes, clears pendingDelete, reloads
//     }
//
//     /// The phase and rules sheet's values. Weights are kilograms here; the view converts.
//     struct ScorecardPhaseDraft: Equatable {
//         enum Field: String, CaseIterable {
//             case name, startDay, targetWeight, rateLow, rateHigh
//             case waistWindowWeeks, waistMinDecreaseCm
//             case liftDropTolerancePercent, liftDropShare, liftDropConsecutiveWeeks, addCaloriesKcal
//             case slowLossThresholdKgPerWeek, slowLossConsecutiveWeeks, reduceCarbsKcal
//             case rateWindowWeeks, maxProjectionWeeks, targetToleranceKg
//             case proteinFloorGrams, proteinMinDaysPerWeek
//             case maxWeighInAgeWeeks
//             var label: String
//         }
//         struct Group: Equatable { var title: String; var fields: [Field] }
//
//         var isNewPhase: Bool
//         var kind: CutScorecardStoredPhase.Kind
//         var name: String
//         var startDay: String
//         var targetWeightKg: Double?
//         var rateLowPercentPerWeek: Double
//         var rateHighPercentPerWeek: Double
//         var parameters: CutScorecardParameters
//
//         static func firstUse(today: String) -> ScorecardPhaseDraft
//         /// The active phase and the stored rules; `firstUse` when no phase is stored.
//         static func current(settings: CutScorecardSettings, today: String) -> ScorecardPhaseDraft
//         /// "Start a new phase": a draft that will be appended, starting today.
//         func startingNewPhase(today: String) -> ScorecardPhaseDraft
//
//         var title: String               // "New phase" or "Phase and rules"
//         var groups: [Group]
//         var invalidFields: [Field]      // in `Field.allCases` order
//         var validationMessage: String?  // nil exactly when invalidFields is empty
//         var canSave: Bool
//         /// Writes nothing and returns false when !canSave.
//         @discardableResult func save(to settings: CutScorecardSettings) -> Bool
//     }
//
// Behaviour assumed where §10 leaves it open:
//
//  1. The model's day is `LocalDayWindows(timeZone: timeZone()).dayKey(for: now())`.
//  2. After its first load the model follows `provider.$revision`: a change reloads it. A
//     `WeighInStore` built with that provider refreshes it after every write (ruling R32), which
//     is how a saved weigh-in reaches the screen.
//  3. The weigh-in sheet accepts the locale's decimal separator. Its hints, as drawn:
//     no earlier reading "30 to 250 kg" (step 2: "40 to 200 cm"); an earlier reading, field
//     untouched "Last: 97.6 kg · Wed 29 Jan. Type to replace." (step 2 appends " 40 to 200 cm.");
//     once typed over "Last: 97.6 kg · Wed 29 Jan"; out of range "Enter 250 kg or less." or
//     "Enter 30 kg or more.".
//  4. A history row joins a weight and a waist stored at the same instant from the same source.
//     Its caption is "Represents its week" or "Not the weekly point", then " · ", then the source:
//     "Lab Book", "Lab Book · CSV import" (source `LabMarkerCsvImport.sourceId`), or
//     "Apple Health · read-only". The reading that represents a week is its latest weight.
//  5. A new phase is appended to `cutScorecard.phases`; editing replaces the active phase in place.
//     A phase of kind other is stored with no target and leaves `cutScorecard.rules` untouched.
//  6. "Phase not started" (§10.2) needs a phase the settings do not hand out: before its start day
//     `CutScorecardSettings.evaluationPhase(on:)` is nil, so the committed input builder evaluates
//     with no phase. With no active phase and a cut phase stored for a later day, the model
//     evaluates with that phase, which is what makes the result say `phaseNotStarted`.
//  7. The sheet opened from a history row (`editing:`) starts with that reading's values and
//     instant, and Save edits the stored rows through `WeighInStore.edit` instead of adding any.
//
// Synthetic values only: the "Fixture Person" of specification §13. Lab Book rows only, so the 2031
// dates are safe (ruling R31): no lift sessions and no protein exist in these tests.
@MainActor
final class CutScorecardModelTests: XCTestCase {

    // MARK: - Harness

    private typealias Fixture = ScorecardScreenFixture

    private final class Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    /// Holds one caller until `open()`.
    private final class Gate {
        private var waiting: CheckedContinuation<Void, Never>?
        private var isOpen = false
        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiting = $0 }
        }
        func open() {
            isOpen = true
            waiting?.resume()
            waiting = nil
        }
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

    private func marker(_ key: String, _ day: String, _ value: Double, hour: Int = 7, unit: String? = nil,
                        source: String = "manual", device: String? = nil) -> LabMarkerRow {
        let takenAt = Int(at(day, hour).timeIntervalSince1970)
        return LabMarkerRow(id: "\(key)-\(takenAt)-\(source.prefix(4))\(device ?? "")", deviceId: device ?? deviceId,
                            markerKey: key, category: "bodyMeasurement", day: day, takenAt: takenAt, value: value,
                            valueText: nil, unit: unit ?? (key == "weight" ? "kg" : "cm"), source: source,
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

    /// `phase` nil: no phase stored. `now`: 07:02 UTC on `today` unless given.
    private func makeHarness(today: String, weeks: [Int] = [], flag: Bool = true,
                             phase: CutScorecardStoredPhase? = nil, storesFixturePhase: Bool = true,
                             now: Date? = nil) async throws -> Harness {
        let name = "CutScorecardModelTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        suites.append(name)
        defaults.set(flag, forKey: "noop.cutScorecardEnabled")
        let settings = CutScorecardSettings(defaults: defaults)
        if let phase {
            settings.phases = [phase]
        } else if storesFixturePhase {
            settings.phases = [fixturePhase]
        }
        settings.parameters = Fixture.parameters

        let store = try await WhoopStore.inMemory()
        let repo = Repository(deviceId: deviceId)
        repo.setStoreForTesting(store)
        let clock = Clock(now ?? at(today, 7, 2))
        let zone = utc
        let provider = BodyMeasurementProvider(repository: repo, defaults: defaults,
                                               today: { LocalDayWindows(timeZone: zone).dayKey(for: clock.now) })
        let weighIns = WeighInStore(repository: repo, provider: provider, timeZone: { zone }, now: { clock.now })
        if !weeks.isEmpty { try await store.upsertLabMarkers(weekRows(weeks)) }
        await provider.refresh()
        return Harness(store: store, repo: repo, defaults: defaults, settings: settings, provider: provider,
                       weighIns: weighIns, clock: clock)
    }

    private func makeModel(_ h: Harness, unitSystem: UnitSystem = .metric,
                           evaluate: (@MainActor (String) async -> CutScorecardEvaluation)? = nil) -> CutScorecardModel {
        let zone = utc
        let locale = british
        let clock = h.clock
        return CutScorecardModel(repository: h.repo, provider: h.provider, settings: h.settings,
                                 unitSystem: { unitSystem }, now: { clock.now }, timeZone: { zone },
                                 locale: { locale }, evaluate: evaluate)
    }

    private struct NotLoaded: Error {}

    private func screen(_ model: CutScorecardModel) throws -> CutScorecardPresentation {
        guard case .loaded(let presentation) = model.state else { throw NotLoaded() }
        return presentation
    }

    /// A harness with the given weeks stored, loaded once.
    private func loaded(today: String, weeks: [Int], phase: CutScorecardStoredPhase? = nil,
                        storesFixturePhase: Bool = true) async throws -> CutScorecardPresentation {
        let h = try await makeHarness(today: today, weeks: weeks, phase: phase, storesFixturePhase: storesFixturePhase)
        let model = makeModel(h)
        await model.load()
        return try screen(model)
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

    private func cardValue(_ model: CutScorecardModel) -> String? {
        if case .loaded(let presentation) = model.state { return presentation.card.value }
        return nil
    }

    private func rows(_ h: Harness, _ key: String, device: String? = nil) async throws -> [LabMarkerRow] {
        try await h.store.labMarkers(deviceId: device ?? deviceId, markerKey: key)
            .sorted { ($0.takenAt, $0.id) < ($1.takenAt, $1.id) }
    }

    private func evaluation(_ input: CutScorecardInput) -> CutScorecardEvaluation {
        (input: input, result: CutScorecard.evaluate(input))
    }

    // MARK: - §10 screen states

    func testStateIsIdleBeforeTheFirstLoadAndLoadingWhileItIsInFlight() async throws {
        let h = try await makeHarness(today: Fixture.weighDay(4), weeks: [1, 2, 3, 4])
        let gate = Gate()
        var calls = 0
        let result = evaluation(Fixture.input(today: Fixture.weighDay(4)))
        let model = makeModel(h) { _ in
            calls += 1
            await gate.wait()
            return result
        }
        XCTAssertEqual(model.state, .idle)

        let load = Task { await model.load() }
        await waitUntil("the load to start") { calls == 1 }
        XCTAssertEqual(model.state, .loading, "a skeleton shows while the first load is in flight")

        gate.open()
        await load.value
        XCTAssertEqual(try screen(model).status, .verdict)
        XCTAssertEqual(calls, 1)
    }

    func testTheModelEvaluatesTheModelsOwnDay() async throws {
        let h = try await makeHarness(today: "2031-01-29", weeks: [1, 2, 3, 4], now: at("2031-01-29", 23, 59))
        var asked: [String] = []
        let result = evaluation(Fixture.input(today: "2031-01-29"))
        let model = makeModel(h) { today in
            asked.append(today)
            return result
        }
        await model.load()
        h.clock.now = at("2031-01-30", 0, 1)
        await model.load()
        XCTAssertEqual(asked, ["2031-01-29", "2031-01-30"], "the local day of now() in the injected zone, read per load")
    }

    func testNoCutPhase() async throws {
        let shown = try await loaded(today: "2031-01-29", weeks: [1, 2, 3, 4], storesFixturePhase: false)
        XCTAssertEqual(shown.status, .noCutPhase)
        XCTAssertEqual(shown.verdict.title, "No cut phase is active")
        XCTAssertNil(shown.phase)
        XCTAssertEqual(shown.card.caption, "Set up your phase")
        XCTAssertNil(shown.card.value)
        XCTAssertEqual(shown.weight?.value, "97.6", "readings exist, so the curves still show")
        XCTAssertEqual(shown.phaseLinkValue, "Not set up")
    }

    /// §9.2: only a phase of kind cut is passed to the evaluation.
    func testAnActivePhaseOfKindOtherIsNoCutPhase() async throws {
        let other = CutScorecardStoredPhase(kind: .other, name: "Maintenance", startDay: "2031-01-06",
                                            targetWeightKg: nil, rateLowPercentPerWeek: 0.25,
                                            rateHighPercentPerWeek: 0.75)
        let shown = try await loaded(today: "2031-01-29", weeks: [1, 2, 3, 4], phase: other)
        XCTAssertEqual(shown.status, .noCutPhase)
        XCTAssertEqual(shown.verdict.title, "No cut phase is active")
        XCTAssertEqual(shown.rules, [])
    }

    func testPhaseNotStarted() async throws {
        let later = CutScorecardStoredPhase(kind: .cut, name: "Fixture cut", startDay: "2031-02-03",
                                            targetWeightKg: 94.0, rateLowPercentPerWeek: 0.40,
                                            rateHighPercentPerWeek: 1.20)
        // `activePhase(on:)` is nil before the start day, so the model must look ahead to say this.
        let shown = try await loaded(today: "2031-01-29", weeks: [1, 2, 3, 4], phase: later)
        XCTAssertEqual(shown.status, .phaseNotStarted)
        XCTAssertEqual(shown.verdict.title, "Your phase starts Mon 3 Feb")
        XCTAssertEqual(shown.phase?.label, "Phase · not started")
        XCTAssertEqual(shown.phase?.name, "Fixture cut")
        XCTAssertTrue(shown.verdict.isWithheld)
        XCTAssertEqual(shown.weight?.value, "97.6")
    }

    func testNoReadings() async throws {
        let shown = try await loaded(today: "2031-01-08", weeks: [])
        XCTAssertEqual(shown.status, .noReadings)
        XCTAssertEqual(shown.verdict.title, "Log a weigh-in to begin")
        XCTAssertNil(shown.weight)
        XCTAssertEqual(shown.emptyCurvesText, "Not measured yet")
        XCTAssertTrue(shown.logWeighInIsPrimary)
        XCTAssertNil(shown.card.value, "no weigh-in is a dash, not the profile weight and not zero")
        XCTAssertEqual(shown.card.caption, "Log your first weigh-in")
        XCTAssertEqual(shown.historyValue, "0 weigh-ins")
    }

    func testOneReading() async throws {
        let shown = try await loaded(today: Fixture.weighDay(1), weeks: [1])
        XCTAssertEqual(shown.status, .oneReading)
        XCTAssertEqual(shown.card.value, "100.0")
        XCTAssertEqual(shown.card.caption, "First weigh-in logged")
        XCTAssertEqual(shown.signals[safe: 3]?.reason, "Needs a second weigh-in")
        XCTAssertEqual(shown.verdict.title, "Not enough to judge yet", "no lift sessions exist in this store")
        XCTAssertEqual(shown.historyValue, "1 weigh-in")
    }

    /// The fixture with its phase starting on the Monday of week 5 and no lift sessions (frame B7).
    func testBuilding() async throws {
        let later = CutScorecardStoredPhase(kind: .cut, name: "Fixture cut", startDay: "2031-02-03",
                                            targetWeightKg: 94.0, rateLowPercentPerWeek: 0.40,
                                            rateHighPercentPerWeek: 1.20)
        let shown = try await loaded(today: "2031-02-19", weeks: Array(1...7), phase: later)
        XCTAssertEqual(shown.status, .building)
        XCTAssertEqual(shown.verdict.title, "Not enough to judge yet")
        XCTAssertEqual(shown.card.value, "97.3")
        XCTAssertEqual(shown.card.caption, "Building: 2 of 3 weeks")
        XCTAssertEqual(shown.phase?.label, "Phase · week 3")
    }

    func testVerdictAvailable() async throws {
        let shown = try await loaded(today: Fixture.weighDay(4), weeks: [1, 2, 3, 4])
        XCTAssertEqual(shown.status, .verdict)
        XCTAssertEqual(shown.verdict.title, "Change nothing")
        XCTAssertEqual(shown.verdict.lines, ["None of your change rules fired."], "no lift sessions in this store")
        XCTAssertEqual(shown.verdict.couldNotCheck, ["Could not check: lifts holding and waist shrinking",
                                                     "Could not check: lifts dropping"])
        XCTAssertFalse(shown.verdict.isWithheld)
        XCTAssertEqual(shown.card.value, "97.6")
        XCTAssertEqual(shown.card.caption, "Change nothing")
        XCTAssertEqual(shown.phase?.name, "Fixture cut")
        XCTAssertEqual(shown.weight?.provenance, "Weighed Wed 29 Jan · Lab Book")
        XCTAssertEqual(shown.signals[safe: 1]?.reason, "Not known: no imported sessions")
    }

    func testDueThisWeek() async throws {
        let shown = try await loaded(today: "2031-02-05", weeks: [1, 2, 3, 4])
        XCTAssertEqual(shown.status, .due)
        XCTAssertEqual(shown.dueBanner?.title, "Weigh-in due this week")
        XCTAssertEqual(shown.dueBanner?.detail, "The verdict below is from the week of 27 Jan.")
        XCTAssertEqual(shown.verdict.title, "Change nothing", "last week's verdict stands for one week")
        XCTAssertEqual(shown.card.value, "97.6")
        XCTAssertEqual(shown.card.caption, "Weigh-in due this week")
        XCTAssertTrue(shown.logWeighInIsPrimary)
    }

    func testOverdue() async throws {
        let shown = try await loaded(today: "2031-02-12", weeks: [1, 2, 3, 4])
        XCTAssertEqual(shown.status, .overdue)
        XCTAssertEqual(shown.verdict.title, "Last weigh-in Wed 29 Jan")
        XCTAssertTrue(shown.verdict.isWithheld)
        XCTAssertNil(shown.dueBanner)
        XCTAssertEqual(shown.signals.map(\.state), [.unknown, .unknown, .unknown, .unknown])
        XCTAssertEqual(shown.card.value, "97.6")
        XCTAssertTrue(shown.card.isDimmed)
        XCTAssertEqual(shown.card.caption, "Last weigh-in Wed 29 Jan")
        XCTAssertTrue(shown.logWeighInIsPrimary)
    }

    /// §9.2: a rules string that does not parse is treated as absent and the screen says so.
    func testRulesNeedAttention() async throws {
        let h = try await makeHarness(today: Fixture.weighDay(4), weeks: [1, 2, 3, 4])
        h.defaults.set("{\"rateWindowWeeks\":", forKey: "cutScorecard.rules")
        XCTAssertTrue(h.settings.rulesNeedAttention, "the fixture for this test")
        let model = makeModel(h)
        await model.load()
        let shown = try screen(model)
        XCTAssertEqual(shown.status, .rulesNeedAttention)
        XCTAssertEqual(shown.verdict.title, "Your rules need attention")
        XCTAssertTrue(shown.verdict.isWithheld)
        XCTAssertEqual(shown.verdict.action, .openPhaseAndRules)
        XCTAssertEqual(shown.verdict.lines, [])
        XCTAssertEqual(shown.rules, [])
        XCTAssertEqual(shown.weight?.value, "97.6", "the weigh-ins are unaffected")
        XCTAssertEqual(h.defaults.string(forKey: "cutScorecard.rules"), "{\"rateWindowWeeks\":",
                       "reading never rewrites a stored string (ruling R30)")
    }

    func testTargetReached() async throws {
        let reached = CutScorecardStoredPhase(kind: .cut, name: "Fixture cut", startDay: "2031-01-06",
                                              targetWeightKg: 98.0, rateLowPercentPerWeek: 0.40,
                                              rateHighPercentPerWeek: 1.20)
        let shown = try await loaded(today: Fixture.weighDay(4), weeks: [1, 2, 3, 4], phase: reached)
        XCTAssertEqual(shown.status, .targetReached)
        XCTAssertEqual(shown.targetBanner?.title, "Target reached")
        XCTAssertEqual(shown.targetBanner?.detail, "97.6 kg on Wed 29 Jan · target 98.0 kg")
        XCTAssertEqual(shown.projection.text, "Target reached")
        XCTAssertEqual(shown.verdict.title, "Change nothing", "the verdict remains below the banner")
        XCTAssertEqual(shown.card.caption, "Target reached")
    }

    func testUnitsComeFromTheInjectedUnitSystemOnEveryLoad() async throws {
        let h = try await makeHarness(today: Fixture.weighDay(4), weeks: [1, 2, 3, 4])
        var system = UnitSystem.metric
        let zone = utc
        let locale = british
        let clock = h.clock
        let model = CutScorecardModel(repository: h.repo, provider: h.provider, settings: h.settings,
                                      unitSystem: { system }, now: { clock.now }, timeZone: { zone },
                                      locale: { locale })
        await model.load()
        XCTAssertEqual(try screen(model).card.unit, "kg")
        system = .imperial
        await model.load()
        XCTAssertEqual(try screen(model).card.unit, "lb")
        XCTAssertEqual(try screen(model).card.value, "215.2")
        XCTAssertEqual(try screen(model).waist?.unit, "in")
    }

    // MARK: - Reloading

    func testReloadsAfterAWeighInStoreWrite() async throws {
        let h = try await makeHarness(today: Fixture.weighDay(4), weeks: [1, 2, 3])
        let model = makeModel(h)
        await model.load()
        XCTAssertEqual(cardValue(model), "98.4")

        try await h.weighIns.save(weight: 97.6, waist: 98.5, unitSystem: .metric, takenAt: at(Fixture.weighDay(4)))
        await waitUntil("the model to show the saved weigh-in") { self.cardValue(model) == "97.6" }
        XCTAssertEqual(try screen(model).historyValue, "4 weigh-ins")
        XCTAssertEqual(try screen(model).waist?.value, "98.5")

        // A delete reaches the screen the same way: the week becomes the latest one with a reading.
        let saved = try await rows(h, "weight").last { $0.day == Fixture.weighDay(4) }
        try await h.weighIns.delete(try XCTUnwrap(saved))
        await waitUntil("the model to drop the deleted weigh-in") { self.cardValue(model) == "98.4" }
    }

    /// Ruling R32: a Lab Book write made elsewhere reaches the model when the provider's revision moves.
    func testReloadsWhenTheProvidersRevisionChanges() async throws {
        let h = try await makeHarness(today: Fixture.weighDay(4), weeks: [1, 2, 3])
        let model = makeModel(h)
        await model.load()
        XCTAssertEqual(cardValue(model), "98.4")
        let before = h.provider.revision

        try await h.store.upsertLabMarkers([marker("weight", Fixture.weighDay(4), 97.6)])
        await h.provider.refresh()
        XCTAssertGreaterThan(h.provider.revision, before, "the fixture for this test")
        await waitUntil("the model to follow the provider") { self.cardValue(model) == "97.6" }
    }

    func testAnUnchangedRevisionDoesNotReload() async throws {
        let h = try await makeHarness(today: Fixture.weighDay(4), weeks: [1, 2, 3, 4])
        var calls = 0
        let result = evaluation(Fixture.input(today: Fixture.weighDay(4)))
        let model = makeModel(h) { _ in
            calls += 1
            return result
        }
        await model.load()
        XCTAssertEqual(calls, 1)
        await h.provider.refresh()      // nothing changed: the revision does not move
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(calls, 1, "a refresh that found nothing new costs no evaluation")
    }

    /// Two loads, completed out of order: the one that began first finishes last and must not publish.
    func testAnObsoleteLoadNeverPublishes() async throws {
        let h = try await makeHarness(today: Fixture.weighDay(4), weeks: [1, 2, 3, 4])
        let gate = Gate()
        var calls = 0
        let stale = evaluation(Fixture.input(today: Fixture.weighDay(1), lifts: false))
        let fresh = evaluation(Fixture.input(today: Fixture.weighDay(4), lifts: false))
        let model = makeModel(h) { _ in
            calls += 1
            if calls == 1 {
                await gate.wait()
                return stale
            }
            return fresh
        }
        var published: [CutScorecardModel.State] = []
        let observer = model.$state.sink { published.append($0) }
        defer { observer.cancel() }

        let first = Task { await model.load() }
        await waitUntil("the first load to start") { calls == 1 }
        await model.load()
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(cardValue(model), "97.6", "the later load published")

        gate.open()
        await first.value
        XCTAssertEqual(cardValue(model), "97.6", "the earlier load finished last and published nothing")
        XCTAssertFalse(published.contains { state in
            if case .loaded(let presentation) = state { return presentation.card.value == "100.0" }
            return false
        }, "the stale result was never shown, even for a frame")
    }

    // MARK: - Flag off

    func testDoesNothingWhileTheFlagIsOff() async throws {
        let h = try await makeHarness(today: Fixture.weighDay(4), weeks: [1, 2, 3, 4], flag: false)
        var calls = 0
        let result = evaluation(Fixture.input(today: Fixture.weighDay(4)))
        let model = makeModel(h) { _ in
            calls += 1
            return result
        }
        let before = h.provider.revision
        await model.load()
        await model.load()
        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(calls, 0, "nothing is read or evaluated while the flag is off")
        XCTAssertEqual(h.provider.revision, before)
        XCTAssertNil(h.defaults.object(forKey: "profile.weightKg"), "and nothing is mirrored into the profile")

        // The same model over the same store: only the flag stood in the way.
        h.settings.isEnabled = true
        await model.load()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(try screen(model).status, .verdict)
    }

    func testSwitchingTheFlagOffClearsALoadedScreen() async throws {
        let h = try await makeHarness(today: Fixture.weighDay(4), weeks: [1, 2, 3, 4])
        let model = makeModel(h)
        await model.load()
        XCTAssertEqual(cardValue(model), "97.6")
        h.settings.isEnabled = false
        await model.load()
        XCTAssertEqual(model.state, .idle, "off: no card and no screen (§9.2)")
    }

    // MARK: - §10.3 weigh-in sheet

    private func makeSheet(_ h: Harness, unitSystem: UnitSystem = .metric, locale: Locale? = nil,
                           weighIns: WeighInStore? = nil, editing: WeighInHistoryRow? = nil) -> WeighInSheetModel {
        let zone = utc
        let clock = h.clock
        return WeighInSheetModel(weighIns: weighIns ?? h.weighIns, unitSystem: unitSystem, now: { clock.now },
                                 timeZone: { zone }, locale: locale ?? british, editing: editing)
    }

    /// "Now" is Wed 5 Feb 2031, 07:02, with weeks 1 to 4 logged, as in frames C2 to C8.
    private func week5Harness() async throws -> Harness {
        try await makeHarness(today: "2031-02-05", weeks: [1, 2, 3, 4])
    }

    func testC1FirstUseStartsEmptyAtNowWithTheRangeAsTheHint() async throws {
        let h = try await makeHarness(today: Fixture.weighDay(1))
        let sheet = makeSheet(h)
        await sheet.prepare()
        XCTAssertEqual(sheet.step, .weight)
        XCTAssertEqual(sheet.phase, .editing)
        XCTAssertEqual(sheet.weightText, "")
        XCTAssertEqual(sheet.weightUnit, "kg")
        XCTAssertEqual(sheet.takenAt, h.clock.now, "date and time default to now")
        XCTAssertEqual(sheet.weightHint, "30 to 250 kg")
        XCTAssertFalse(sheet.weightHintIsError)
        XCTAssertNil(sheet.weightIssue, "an empty field is not an error")
        XCTAssertFalse(sheet.canAdvance)
        XCTAssertEqual(sheet.primaryTitle, "Next")
        XCTAssertNil(sheet.dateNote)
        XCTAssertNil(sheet.failureMessage)

        sheet.weightText = "100"
        sheet.advance()
        XCTAssertEqual(sheet.step, .waist)
        XCTAssertEqual(sheet.waistText, "")
        XCTAssertEqual(sheet.waistHint, "40 to 200 cm")
        XCTAssertFalse(sheet.canSave, "an empty waist is skipped, not saved")
    }

    /// Frame C2. The last value is an offer in the field and a hint under it; nothing is stored
    /// until Save or Skip.
    func testC2TheLastWeightIsOfferedAndNeverSavedByOpeningOrAdvancing() async throws {
        let h = try await week5Harness()
        let before = try await rows(h, "weight") + rows(h, "waist")
        let sheet = makeSheet(h)
        await sheet.prepare()
        XCTAssertEqual(sheet.weightText, "97.6")
        XCTAssertEqual(sheet.weightHint, "Last: 97.6 kg · Wed 29 Jan. Type to replace.")
        XCTAssertFalse(sheet.weightHintIsError)
        XCTAssertTrue(sheet.canAdvance)
        XCTAssertNil(sheet.dateNote, "no reading yet this week")

        sheet.weightText = "97.5"
        XCTAssertEqual(sheet.weightHint, "Last: 97.6 kg · Wed 29 Jan", "typed over: the offer is gone, the hint stays")
        sheet.advance()
        XCTAssertEqual(sheet.step, .waist)
        let after = try await rows(h, "weight") + rows(h, "waist")
        XCTAssertEqual(after, before, "opening the sheet and pressing Next write nothing")
        XCTAssertEqual(sheet.phase, .editing)

        sheet.back()
        XCTAssertEqual(sheet.step, .weight)
        XCTAssertEqual(sheet.weightText, "97.5", "going back keeps what was typed")
    }

    func testC3AWeightAboveTheRangeNamesTheUpperBound() async throws {
        let h = try await week5Harness()
        let sheet = makeSheet(h)
        await sheet.prepare()
        sheet.weightText = "975"
        XCTAssertEqual(sheet.weightIssue, .aboveMaximum)
        XCTAssertEqual(sheet.weightHint, "Enter 250 kg or less.")
        XCTAssertTrue(sheet.weightHintIsError)
        XCTAssertFalse(sheet.canAdvance)
        sheet.advance()
        XCTAssertEqual(sheet.step, .weight, "Next is disabled")

        sheet.weightText = "250"
        XCTAssertNil(sheet.weightIssue, "the range is inclusive")
        XCTAssertTrue(sheet.canAdvance)
        sheet.weightText = "250.1"
        XCTAssertEqual(sheet.weightIssue, .aboveMaximum)
    }

    func testAWeightBelowTheRangeNamesTheLowerBound() async throws {
        let h = try await week5Harness()
        let sheet = makeSheet(h)
        await sheet.prepare()
        sheet.weightText = "29.9"
        XCTAssertEqual(sheet.weightIssue, .belowMinimum)
        XCTAssertEqual(sheet.weightHint, "Enter 30 kg or more.")
        XCTAssertTrue(sheet.weightHintIsError)
        XCTAssertFalse(sheet.canAdvance)
        sheet.weightText = "0"
        XCTAssertEqual(sheet.weightIssue, .belowMinimum)
        XCTAssertFalse(sheet.canAdvance)
        sheet.weightText = "30"
        XCTAssertNil(sheet.weightIssue)
        XCTAssertTrue(sheet.canAdvance)
    }

    func testANonNumericWeightCannotAdvance() async throws {
        let h = try await week5Harness()
        let sheet = makeSheet(h)
        await sheet.prepare()
        for text in ["abc", "9.7.5", "97.5kg", "--", "."] {
            sheet.weightText = text
            XCTAssertEqual(sheet.weightIssue, .notANumber, text)
            XCTAssertTrue(sheet.weightHintIsError, text)
            XCTAssertFalse(sheet.weightHint.isEmpty, text)
            XCTAssertFalse(sheet.canAdvance, text)
        }
        sheet.weightText = ""
        XCTAssertNil(sheet.weightIssue)
        XCTAssertFalse(sheet.canAdvance, "an empty weight cannot advance either")
    }

    func testAFutureDateCannotBeSaved() async throws {
        let h = try await week5Harness()
        let sheet = makeSheet(h)
        await sheet.prepare()
        XCTAssertFalse(sheet.dateIsInTheFuture)
        XCTAssertEqual(sheet.dateHint, "Future dates cannot be picked.")

        sheet.takenAt = h.clock.now.addingTimeInterval(60)
        XCTAssertTrue(sheet.dateIsInTheFuture)
        XCTAssertFalse(sheet.canAdvance, "a valid weight does not make a future instant savable")
        sheet.advance()
        XCTAssertEqual(sheet.step, .weight)

        sheet.takenAt = h.clock.now
        XCTAssertFalse(sheet.dateIsInTheFuture, "now itself is allowed")
        XCTAssertTrue(sheet.canAdvance)
    }

    /// Frame C4: Thu 16 Jan, the day after week 2's weigh-in.
    func testC4BackdatingNamesTheWeekAndSavesAtTheChosenInstant() async throws {
        let h = try await week5Harness()
        let sheet = makeSheet(h)
        await sheet.prepare()
        sheet.takenAt = at("2031-01-16", 7, 2)
        XCTAssertEqual(sheet.dateNote,
                       "Falls in the week of 13 Jan. You logged 99.2 kg on Wed 15 Jan. This reading will represent the week.")
        sheet.weightText = "98.0"
        XCTAssertTrue(sheet.canAdvance)
        sheet.advance()
        await sheet.skipWaist()
        XCTAssertEqual(sheet.phase, .saved)

        let saved = try await rows(h, "weight").filter { $0.day == "2031-01-16" }
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.takenAt, Int(at("2031-01-16", 7, 2).timeIntervalSince1970))
        XCTAssertEqual(saved.first?.value, 98.0)
        XCTAssertEqual(saved.first?.source, "manual")
    }

    func testBackdatingIntoAWeekWithNoReadingNamesOnlyTheWeek() async throws {
        let h = try await makeHarness(today: Fixture.weighDay(11), weeks: Array(1...9))
        let sheet = makeSheet(h)
        await sheet.prepare()
        XCTAssertNil(sheet.dateNote, "today, in a week with no reading")
        sheet.takenAt = at("2031-03-12", 7, 2)      // the missed week 10
        XCTAssertEqual(sheet.dateNote, "Falls in the week of 10 Mar.")
    }

    /// Frame C5: Fri 31 Jan, two days after week 4's weigh-in.
    func testC5AlreadyLoggedThisWeek() async throws {
        let h = try await makeHarness(today: "2031-01-31", weeks: [1, 2, 3, 4], now: at("2031-01-31", 7, 10))
        let sheet = makeSheet(h)
        await sheet.prepare()
        XCTAssertEqual(sheet.dateNote, "You logged 97.6 kg on Wed 29 Jan. This reading will represent the week.")
        XCTAssertTrue(sheet.canAdvance, "saving is allowed")
        sheet.weightText = "97.4"
        sheet.advance()
        await sheet.skipWaist()
        XCTAssertEqual(sheet.phase, .saved)
        let weights = try await rows(h, "weight")
        XCTAssertEqual(weights.filter { $0.day >= "2031-01-27" }.map(\.value), [97.6, 97.4],
                       "a second row; the earlier reading is kept")
    }

    /// Frames C6 and C7.
    func testC6Step2OffersTheLastWaistAndItsRange() async throws {
        let h = try await week5Harness()
        let sheet = makeSheet(h)
        await sheet.prepare()
        sheet.weightText = "97.5"
        sheet.advance()
        XCTAssertEqual(sheet.step, .waist)
        XCTAssertEqual(sheet.waistUnit, "cm")
        XCTAssertEqual(sheet.waistText, "98.5")
        XCTAssertEqual(sheet.waistHint, "Last: 98.5 cm · Wed 29 Jan. Type to replace. 40 to 200 cm.")
        XCTAssertEqual(sheet.primaryTitle, "Save")
        XCTAssertTrue(sheet.canSave)
        XCTAssertEqual(sheet.skipNote, "Saves the weight only. Waist for this week will read \"Not measured this week\".")

        sheet.waistText = "98.0"
        XCTAssertEqual(sheet.waistHint, "Last: 98.5 cm · Wed 29 Jan")
        XCTAssertFalse(sheet.waistHintIsError)

        sheet.waistText = "39.9"
        XCTAssertEqual(sheet.waistIssue, .belowMinimum)
        XCTAssertEqual(sheet.waistHint, "Enter 40 cm or more.")
        XCTAssertTrue(sheet.waistHintIsError)
        XCTAssertFalse(sheet.canSave)
        sheet.waistText = "200.5"
        XCTAssertEqual(sheet.waistIssue, .aboveMaximum)
        XCTAssertEqual(sheet.waistHint, "Enter 200 cm or less.")
        XCTAssertFalse(sheet.canSave)
        sheet.waistText = "tape"
        XCTAssertEqual(sheet.waistIssue, .notANumber)
        XCTAssertFalse(sheet.canSave)
        for edge in ["40", "200"] {
            sheet.waistText = edge
            XCTAssertNil(sheet.waistIssue, edge)
            XCTAssertTrue(sheet.canSave, edge)
        }
    }

    func testSaveWritesTheWeightAndTheWaistAtOneInstant() async throws {
        let h = try await week5Harness()
        let sheet = makeSheet(h)
        await sheet.prepare()
        sheet.weightText = "97.5"
        sheet.advance()
        sheet.waistText = "98.0"
        await sheet.save()
        XCTAssertEqual(sheet.phase, .saved)
        XCTAssertNil(sheet.failureMessage)

        let instant = Int(h.clock.now.timeIntervalSince1970)
        let weightRows1 = try await rows(h, "weight")
        let weight = try XCTUnwrap(weightRows1.first { $0.takenAt == instant })
        let waistRows2 = try await rows(h, "waist")
        let waist = try XCTUnwrap(waistRows2.first { $0.takenAt == instant })
        XCTAssertEqual(weight.value, 97.5)
        XCTAssertEqual(weight.unit, "kg")
        XCTAssertEqual(weight.day, "2031-02-05")
        XCTAssertEqual(weight.source, "manual")
        XCTAssertEqual(weight.category, "bodyMeasurement")
        XCTAssertEqual(waist.value, 98.0)
        XCTAssertEqual(waist.unit, "cm")
        let weightRows3 = try await rows(h, "weight")
        XCTAssertEqual(weightRows3.count, 5)
        let waistRows4 = try await rows(h, "waist")
        XCTAssertEqual(waistRows4.count, 5)
    }

    /// §10.3 "Step 2 skipped": even with the last waist still offered in the field.
    func testASkippedWaistSavesNoWaist() async throws {
        let h = try await week5Harness()
        let sheet = makeSheet(h)
        await sheet.prepare()
        sheet.weightText = "97.5"
        sheet.advance()
        XCTAssertEqual(sheet.waistText, "98.5", "the offer is in the field")
        await sheet.skipWaist()
        XCTAssertEqual(sheet.phase, .saved)
        let weightRows5 = try await rows(h, "weight")
        XCTAssertEqual(weightRows5.count, 5)
        let waistRows6 = try await rows(h, "waist")
        XCTAssertEqual(waistRows6.count, 4, "no waist row was written for the skipped step")
        let waistRows7 = try await rows(h, "waist")
        XCTAssertEqual(waistRows7.filter { $0.day == "2031-02-05" }, [])
    }

    /// Frame C9: pounds, and a comma as the decimal separator (the app's `en_DE` convention).
    func testC9PoundsAndInchesAreStoredAsKilogramsAndCentimetres() async throws {
        let h = try await week5Harness()
        let sheet = makeSheet(h, unitSystem: .imperial, locale: Locale(identifier: "en_DE"))
        await sheet.prepare()
        XCTAssertEqual(sheet.weightUnit, "lb")
        XCTAssertEqual(sheet.waistUnit, "in")
        XCTAssertEqual(sheet.weightText, "215,2")
        XCTAssertEqual(sheet.weightHint, "Last: 215,2 lb · Wed 29 Jan. Type to replace.")
        sheet.weightText = "215,0"
        XCTAssertEqual(sheet.weightHint, "Last: 215,2 lb · Wed 29 Jan")
        XCTAssertNil(sheet.weightIssue)
        sheet.advance()
        XCTAssertEqual(sheet.waistText, "38,8")
        sheet.waistText = "38,0"
        XCTAssertNil(sheet.waistIssue)
        await sheet.save()
        XCTAssertEqual(sheet.phase, .saved)

        let instant = Int(h.clock.now.timeIntervalSince1970)
        let weightRows8 = try await rows(h, "weight")
        let weight = try XCTUnwrap(weightRows8.first { $0.takenAt == instant })
        let waistRows9 = try await rows(h, "waist")
        let waist = try XCTUnwrap(waistRows9.first { $0.takenAt == instant })
        XCTAssertEqual(weight.unit, "kg")
        XCTAssertEqual(try XCTUnwrap(weight.value), 215.0 / UnitFormatter.poundsPerKilogram, accuracy: 1e-9)
        XCTAssertEqual(waist.unit, "cm")
        XCTAssertEqual(try XCTUnwrap(waist.value), 38.0 * UnitFormatter.centimetersPerInch, accuracy: 1e-9)
    }

    /// The range is applied to the converted value: 60 lb is 27.2 kg, 560 lb is 254 kg.
    func testTheRangeIsCheckedInKilogramsWhateverTheUnit() async throws {
        let h = try await makeHarness(today: Fixture.weighDay(1))
        let sheet = makeSheet(h, unitSystem: .imperial)
        await sheet.prepare()
        sheet.weightText = "60"
        XCTAssertEqual(sheet.weightIssue, .belowMinimum)
        sheet.weightText = "560"
        XCTAssertEqual(sheet.weightIssue, .aboveMaximum)
        sheet.weightText = "215"
        XCTAssertNil(sheet.weightIssue)
        for text in ["", "60", "560", "215"] {
            sheet.weightText = text
            XCTAssertFalse(sheet.weightHint.contains("kg"), "an imperial sheet names no metric unit: \(sheet.weightHint)")
        }
    }

    func testTheDecimalSeparatorFollowsTheLocale() async throws {
        let h = try await makeHarness(today: Fixture.weighDay(1))
        let point = makeSheet(h, locale: british)
        await point.prepare()
        point.weightText = "97.5"
        XCTAssertNil(point.weightIssue)
        XCTAssertTrue(point.canAdvance)

        let comma = makeSheet(h, locale: Locale(identifier: "en_DE"))
        await comma.prepare()
        comma.weightText = "97,5"
        XCTAssertNil(comma.weightIssue)
        XCTAssertTrue(comma.canAdvance)
        comma.advance()
        await comma.skipWaist()
        let weightRows10 = try await rows(h, "weight")
        XCTAssertEqual(weightRows10.map(\.value), [97.5], "97,5 is ninety-seven and a half, not 975")
    }

    /// Frame C8. The store refuses the write (its clock is behind the sheet's); the sheet stays open.
    func testC8ASaveFailureLeavesTheEntriesInPlaceAndOffersARetry() async throws {
        let h = try await week5Harness()
        let storeClock = Clock(h.clock.now.addingTimeInterval(-120))
        let zone = utc
        let refusing = WeighInStore(repository: h.repo, provider: h.provider, timeZone: { zone },
                                    now: { storeClock.now })
        let sheet = makeSheet(h, weighIns: refusing)
        await sheet.prepare()
        sheet.weightText = "97.5"
        sheet.advance()
        sheet.waistText = "98.0"
        await sheet.save()

        XCTAssertEqual(sheet.phase, .failed)
        XCTAssertEqual(sheet.failureMessage, "Could not save. Your entries are still here.")
        XCTAssertEqual(sheet.primaryTitle, "Try again")
        XCTAssertEqual(sheet.step, .waist)
        XCTAssertEqual(sheet.weightText, "97.5")
        XCTAssertEqual(sheet.waistText, "98.0")
        XCTAssertEqual(sheet.takenAt, h.clock.now)
        XCTAssertTrue(sheet.canSave, "the retry is enabled")
        let weightRows11 = try await rows(h, "weight")
        XCTAssertEqual(weightRows11.count, 4, "nothing was written")
        let waistRows12 = try await rows(h, "waist")
        XCTAssertEqual(waistRows12.count, 4)

        storeClock.now = h.clock.now
        await sheet.save()
        XCTAssertEqual(sheet.phase, .saved)
        XCTAssertNil(sheet.failureMessage)
        let weightRows13 = try await rows(h, "weight")
        XCTAssertEqual(weightRows13.count, 5, "one weigh-in, not two")
        let waistRows14 = try await rows(h, "waist")
        XCTAssertEqual(waistRows14.count, 5)
    }

    /// §10.4 "Edit": the sheet opens with that reading's values and instant, and saving updates it.
    func testEditingOpensWithTheReadingsValuesAndUpdatesThemInPlace() async throws {
        let h = try await week5Harness()
        let history = CutScorecardPresenter.history(weights: try await rows(h, "weight"),
                                                    waists: try await rows(h, "waist"), appleHealth: [],
                                                    unitSystem: .metric, locale: british)
        let row = try XCTUnwrap(history.rows.first { $0.day == Fixture.weighDay(2) })
        let sheet = makeSheet(h, editing: row)
        await sheet.prepare()
        XCTAssertEqual(sheet.weightText, "99.2")
        XCTAssertEqual(sheet.takenAt, at(Fixture.weighDay(2)))
        sheet.weightText = "99.0"
        sheet.advance()
        XCTAssertEqual(sheet.waistText, "99.5")
        await sheet.save()
        XCTAssertEqual(sheet.phase, .saved)

        let weights = try await rows(h, "weight")
        XCTAssertEqual(weights.count, 4, "an edit adds no row")
        let edited = try XCTUnwrap(weights.first { $0.day == Fixture.weighDay(2) })
        XCTAssertEqual(edited.value, 99.0)
        XCTAssertEqual(edited.id, row.weightRow?.id)
        let waistRows15 = try await rows(h, "waist")
        XCTAssertEqual(waistRows15.count, 4)
    }

    // MARK: - §10.4 history

    /// Frame D1: the fixture after week 5, with the extra Monday of week 3, an Apple Health day, a
    /// CSV-imported row and one reading in a unit that is not recognised.
    private func d1History() -> WeighInHistory {
        var weights = weekRows([1, 2, 3, 4, 5]).filter { $0.markerKey == "weight" }
        var waists = weekRows([1, 2, 3, 4, 5]).filter { $0.markerKey == "waist" }
        weights.append(marker("weight", "2031-01-20", 98.9))
        weights.append(marker("weight", "2031-01-01", 101.0, source: LabMarkerCsvImport.sourceId))
        waists.append(marker("waist", "2031-01-01", 100.5, source: LabMarkerCsvImport.sourceId))
        weights.append(marker("weight", "2030-12-18", 16.0, unit: "st"))
        return CutScorecardPresenter.history(weights: weights.shuffled(), waists: waists.shuffled(),
                                             appleHealth: [(day: "2031-01-04", value: 100.6)],
                                             unitSystem: .metric, locale: british)
    }

    func testD1RowsAreNewestFirstWithWeightAndWaistOfOneWeighInOnOneRow() {
        let history = d1History()
        XCTAssertEqual(history.rows.map(\.dateText), ["Wed 5 Feb", "Wed 29 Jan", "Wed 22 Jan", "Mon 20 Jan",
                                                      "Wed 15 Jan", "Wed 8 Jan", "Sat 4 Jan", "Wed 1 Jan"])
        XCTAssertEqual(history.rows.map(\.weightText), ["97.5", "97.6", "98.4", "98.9", "99.2", "100.0", "100.6", "101.0"])
        XCTAssertEqual(history.rows.map(\.waistText), ["98.0", "98.5", "99.0", nil, "99.5", "100.0", nil, "100.5"])
        XCTAssertEqual(history.weightUnit, "kg")
        XCTAssertEqual(history.waistUnit, "cm")
        XCTAssertEqual(history.notMeasuredText, "not measured", "a missing waist is words, never 0")
        XCTAssertNil(history.emptyText)
        XCTAssertEqual(Set(history.rows.map(\.id)).count, history.rows.count, "row ids are unique")
    }

    func testD1TheLatestReadingOfAWeekRepresentsIt() {
        let history = d1History()
        XCTAssertEqual(history.rows.map(\.representsWeek), [true, true, true, false, true, true, true, false])
        XCTAssertEqual(history.rows[safe: 2]?.caption, "Represents its week · Lab Book")
        XCTAssertEqual(history.rows[safe: 3]?.caption, "Not the weekly point · Lab Book")
        XCTAssertEqual(history.legend, "The dot marks the reading that represents its week: the latest one.")
    }

    func testTwoReadingsOnOneDayTheLaterRepresentsTheWeek() {
        let morning = marker("weight", "2031-01-22", 98.4, hour: 7)
        let evening = marker("weight", "2031-01-22", 99.0, hour: 19)
        let history = CutScorecardPresenter.history(weights: [evening, morning], waists: [], appleHealth: [],
                                                    unitSystem: .metric, locale: british)
        XCTAssertEqual(history.rows.map(\.weightText), ["99.0", "98.4"], "newest first within the day")
        XCTAssertEqual(history.rows.map(\.representsWeek), [true, false])
    }

    func testD1OtherSourcesAreNamedAndAppleHealthIsReadOnly() throws {
        let history = d1History()
        let apple = try XCTUnwrap(history.rows[safe: 6])
        XCTAssertEqual(apple.source, .appleHealth)
        XCTAssertEqual(apple.caption, "Represents its week · Apple Health · read-only")
        XCTAssertFalse(apple.canEdit)
        XCTAssertFalse(apple.canDelete)
        XCTAssertNil(apple.weightRow)
        XCTAssertNil(apple.takenAt)

        let imported = try XCTUnwrap(history.rows[safe: 7])
        XCTAssertEqual(imported.source, .labBook)
        XCTAssertEqual(imported.caption, "Not the weekly point · Lab Book · CSV import")
        XCTAssertTrue(imported.canEdit, "a Lab Book row can be edited and deleted whatever wrote it")
        XCTAssertTrue(imported.canDelete)
    }

    func testEditAndDeleteAreOfferedOnlyForLabBookWeightAndWaistReadings() {
        let history = d1History()
        for row in history.rows {
            let isLabBook = row.source == .labBook
            XCTAssertEqual(row.canEdit, isLabBook, row.dateText)
            XCTAssertEqual(row.canDelete, isLabBook, row.dateText)
            XCTAssertEqual(row.weightRow != nil, isLabBook, row.dateText)
            if let stored = row.weightRow { XCTAssertEqual(stored.markerKey, "weight", row.dateText) }
            if let stored = row.waistRow { XCTAssertEqual(stored.markerKey, "waist", row.dateText) }
        }
        XCTAssertEqual(history.rows.count, 8)
        XCTAssertEqual(history.rows[safe: 0]?.waistRow?.value, 98.0)
        XCTAssertEqual(history.rows.filter { $0.waistRow == nil }.map(\.dateText), ["Mon 20 Jan", "Sat 4 Jan"])
    }

    func testD1AReadingInAnUnrecognisedUnitIsCountedNotListed() {
        let history = d1History()
        XCTAssertEqual(history.unlistedCount, 1)
        XCTAssertEqual(history.unlistedNote,
                       "1 reading in a unit that is not recognised is not listed. It remains in Lab Book.")
        XCTAssertFalse(history.rows.contains { $0.day == "2030-12-18" })

        let two = CutScorecardPresenter.history(
            weights: [marker("weight", "2031-01-01", 16.0, unit: "st"), marker("weight", "2031-01-02", 16.0, unit: "st"),
                      marker("weight", "2031-01-08", 100.0)],
            waists: [], appleHealth: [], unitSystem: .metric, locale: british)
        XCTAssertEqual(two.unlistedCount, 2)
        XCTAssertEqual(two.unlistedNote?.hasPrefix("2 readings"), true)
        XCTAssertEqual(two.rows.count, 1)

        let none = CutScorecardPresenter.history(weights: [marker("weight", "2031-01-08", 100.0)], waists: [],
                                                 appleHealth: [], unitSystem: .metric, locale: british)
        XCTAssertEqual(none.unlistedCount, 0)
        XCTAssertNil(none.unlistedNote)
    }

    /// Ruling R30: a weight is admitted in kg, lb or lbs, a waist in cm or in.
    func testHistoryConvertsRowsStoredInPoundsAndInches() {
        let history = CutScorecardPresenter.history(
            weights: [marker("weight", "2031-01-08", 220.462, unit: "lb")],
            waists: [marker("waist", "2031-01-08", 39.37, unit: "in")],
            appleHealth: [], unitSystem: .metric, locale: british)
        XCTAssertEqual(history.rows.map(\.weightText), ["100.0"])
        XCTAssertEqual(history.rows.map(\.waistText), ["100.0"])
        XCTAssertEqual(history.unlistedCount, 0)

        let imperial = CutScorecardPresenter.history(weights: [marker("weight", "2031-01-08", 100.0)],
                                                     waists: [marker("waist", "2031-01-08", 100.0)],
                                                     appleHealth: [], unitSystem: .imperial, locale: british)
        XCTAssertEqual(imperial.weightUnit, "lb")
        XCTAssertEqual(imperial.waistUnit, "in")
        XCTAssertEqual(imperial.rows.map(\.weightText), ["220.5"])
        XCTAssertEqual(imperial.rows.map(\.waistText), ["39.4"])
    }

    func testD4Empty() {
        let history = CutScorecardPresenter.history(weights: [], waists: [], appleHealth: [], unitSystem: .metric,
                                                    locale: british)
        XCTAssertEqual(history.rows, [])
        XCTAssertEqual(history.emptyText, "No weigh-ins yet")
        XCTAssertNil(history.legend)
        XCTAssertNil(history.unlistedNote)
    }

    func testD3TheDeleteConfirmationNamesTheReading() throws {
        let row = try XCTUnwrap(d1History().rows[safe: 3])
        let asked = CutScorecardPresenter.deleteConfirmation(for: row, unitSystem: .metric, locale: british)
        XCTAssertEqual(asked.title, "Delete this weigh-in?")
        XCTAssertEqual(asked.detail,
                       "Mon 20 Jan · 98.9 kg. The weekly series and the verdict are worked out again without it.")
        XCTAssertEqual(asked.confirmTitle, "Delete")
        XCTAssertEqual(asked.cancelTitle, "Cancel")
    }

    private func makeHistory(_ h: Harness) -> WeighInHistoryModel {
        let locale = british
        return WeighInHistoryModel(weighIns: h.weighIns, provider: h.provider, unitSystem: { .metric },
                                   locale: { locale })
    }

    private func list(_ model: WeighInHistoryModel) throws -> WeighInHistory {
        guard case .loaded(let history) = model.state else { throw NotLoaded() }
        return history
    }

    func testD5HistoryIsLoadingUntilItsFirstLoad() async throws {
        let h = try await week5Harness()
        let model = makeHistory(h)
        XCTAssertEqual(model.state, .loading)
        XCTAssertNil(model.pendingDelete)
        await model.load()
        XCTAssertEqual(try list(model).rows.count, 4)
    }

    /// Ruling R25: the rows are the union across the active id and every other registered WHOOP.
    func testHistoryListsReadingsFromTheUnionOfDeviceIdsNewestFirst() async throws {
        let h = try await week5Harness()
        try DeviceRegistryStore(dbQueue: h.store.registryWriter).add(
            PairedDevice(id: "whoop-old", brand: "WHOOP", model: "4.0", sourceKind: .liveBLE, capabilities: [.hr],
                         status: .archived, addedAt: 1, lastSeenAt: 1))
        try await h.store.upsertLabMarkers([marker("weight", "2030-12-25", 101.5, device: "whoop-old"),
                                            marker("waist", "2030-12-25", 101.0, device: "whoop-old")])
        let model = makeHistory(h)
        await model.load()
        let history = try list(model)
        XCTAssertEqual(history.rows.map(\.dateText), ["Wed 29 Jan", "Wed 22 Jan", "Wed 15 Jan", "Wed 8 Jan", "Wed 25 Dec"])
        XCTAssertEqual(history.rows.last?.weightText, "101.5")
        XCTAssertEqual(history.rows.last?.waistText, "101.0")
        XCTAssertEqual(history.rows.last?.weightRow?.deviceId, "whoop-old",
                       "edit and delete act on the row under the id it was stored under")
        XCTAssertEqual(history.rows.last?.canDelete, true)
    }

    func testD3DeleteAsksOnce() async throws {
        let h = try await week5Harness()
        let model = makeHistory(h)
        await model.load()
        let row = try XCTUnwrap(try list(model).rows.first { $0.day == Fixture.weighDay(2) })

        model.requestDelete(row)
        XCTAssertEqual(model.pendingDelete, row)
        XCTAssertEqual(model.deleteConfirmation?.title, "Delete this weigh-in?")
        XCTAssertEqual(model.deleteConfirmation?.detail,
                       "Wed 15 Jan · 99.2 kg. The weekly series and the verdict are worked out again without it.")
        let weightRows16 = try await rows(h, "weight")
        XCTAssertEqual(weightRows16.count, 4, "asking deletes nothing")

        await model.confirmDelete()
        XCTAssertNil(model.pendingDelete, "one confirmation, and the question is gone")
        XCTAssertNil(model.deleteConfirmation)
        let weightRows17 = try await rows(h, "weight")
        XCTAssertEqual(weightRows17.map(\.day), [1, 3, 4].map(Fixture.weighDay))
        let waistRows18 = try await rows(h, "waist")
        XCTAssertEqual(waistRows18.map(\.day), [1, 3, 4].map(Fixture.weighDay),
                       "the weigh-in's waist goes with its weight")
        XCTAssertEqual(try list(model).rows.map(\.dateText), ["Wed 29 Jan", "Wed 22 Jan", "Wed 8 Jan"])

        await model.confirmDelete()
        let weightRows19 = try await rows(h, "weight")
        XCTAssertEqual(weightRows19.count, 3, "a second confirmation has nothing to act on")
    }

    func testCancellingADeleteDeletesNothing() async throws {
        let h = try await week5Harness()
        let model = makeHistory(h)
        await model.load()
        let row = try XCTUnwrap(try list(model).rows.first)
        model.requestDelete(row)
        model.cancelDelete()
        XCTAssertNil(model.pendingDelete)
        XCTAssertNil(model.deleteConfirmation)
        await model.confirmDelete()
        let weightRows20 = try await rows(h, "weight")
        XCTAssertEqual(weightRows20.count, 4)
        let waistRows21 = try await rows(h, "waist")
        XCTAssertEqual(waistRows21.count, 4)
        XCTAssertEqual(try list(model).rows.count, 4)
    }

    func testAReadOnlyRowCannotBePutUpForDeletion() async throws {
        let h = try await week5Harness()
        let model = makeHistory(h)
        await model.load()
        let apple = try XCTUnwrap(d1History().rows[safe: 6])
        XCTAssertFalse(apple.canDelete, "the fixture for this test")
        model.requestDelete(apple)
        XCTAssertNil(model.pendingDelete)
        XCTAssertNil(model.deleteConfirmation)
    }

    /// §10.4: deleting the only reading of a week makes it a missed week on the scorecard.
    func testDeletingTheOnlyReadingOfAWeekLeavesAMissedWeek() async throws {
        let h = try await makeHarness(today: Fixture.weighDay(4), weeks: [1, 2, 3, 4])
        let scorecard = makeModel(h)
        await scorecard.load()
        XCTAssertEqual(try screen(scorecard).weight?.points.map { $0 != nil }, [true, true, true, true])

        let history = makeHistory(h)
        await history.load()
        let row = try XCTUnwrap(try list(history).rows.first { $0.day == Fixture.weighDay(2) })
        history.requestDelete(row)
        await history.confirmDelete()
        await waitUntil("the scorecard to recompute") {
            if case .loaded(let presentation) = scorecard.state {
                return presentation.weight?.points.map { $0 != nil } == [true, false, true, true]
            }
            return false
        }
        XCTAssertEqual(try screen(scorecard).weight?.points.map { $0 != nil }, [true, false, true, true],
                       "the line breaks at the week that lost its reading")
        XCTAssertEqual(try screen(scorecard).historyValue, "3 weigh-ins")
    }

    // MARK: - §10.5 phase and rules sheet

    private func makeSettings() throws -> (CutScorecardSettings, UserDefaults) {
        let name = "CutScorecardModelTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        suites.append(name)
        return (CutScorecardSettings(defaults: defaults), defaults)
    }

    private func fixtureDraft(today: String = "2031-01-06") -> ScorecardPhaseDraft {
        var draft = ScorecardPhaseDraft.firstUse(today: today)
        draft.name = "Fixture cut"
        draft.targetWeightKg = 94.0
        draft.rateLowPercentPerWeek = 0.40
        draft.rateHighPercentPerWeek = 1.20
        draft.parameters = Fixture.parameters
        return draft
    }

    func testE1FirstUseIsPrefilledWithTheGenericDefaults() throws {
        let draft = ScorecardPhaseDraft.firstUse(today: "2031-01-06")
        XCTAssertEqual(draft.title, "New phase")
        XCTAssertTrue(draft.isNewPhase)
        XCTAssertEqual(draft.kind, .cut)
        XCTAssertEqual(draft.name, "Cut")
        XCTAssertEqual(draft.startDay, "2031-01-06", "the start date is today")
        XCTAssertNil(draft.targetWeightKg, "the target is optional and starts unset, not at zero")
        XCTAssertEqual(draft.rateLowPercentPerWeek, 0.25)
        XCTAssertEqual(draft.rateHighPercentPerWeek, 0.75)
        XCTAssertEqual(draft.parameters, CutScorecardParameters.generic)
        XCTAssertNil(draft.parameters.proteinFloorGrams)
        XCTAssertEqual(draft.invalidFields, [])
        XCTAssertNil(draft.validationMessage)
        XCTAssertTrue(draft.canSave)

        let (settings, _) = try makeSettings()
        XCTAssertEqual(ScorecardPhaseDraft.current(settings: settings, today: "2031-01-06"), draft,
                       "with nothing stored the sheet opens as first use")
    }

    func testE2GroupsAndLabelsAreAsDrawn() {
        let draft = fixtureDraft()
        XCTAssertEqual(draft.groups.map(\.title), ["Phase", "Expected rate of loss", "Rule 1 · change nothing",
                                                   "Rule 2 · lifts dropping", "Rule 3 · slow loss",
                                                   "Rate and projection", "Protein", "Weigh-ins"])
        XCTAssertEqual(draft.groups.map(\.fields), [
            [.name, .startDay, .targetWeight],
            [.rateLow, .rateHigh],
            [.waistWindowWeeks, .waistMinDecreaseCm],
            [.liftDropTolerancePercent, .liftDropShare, .liftDropConsecutiveWeeks, .addCaloriesKcal],
            [.slowLossThresholdKgPerWeek, .slowLossConsecutiveWeeks, .reduceCarbsKcal],
            [.rateWindowWeeks, .maxProjectionWeeks, .targetToleranceKg],
            [.proteinFloorGrams, .proteinMinDaysPerWeek],
            [.maxWeighInAgeWeeks],
        ])
        XCTAssertEqual(Set(draft.groups.flatMap(\.fields)), Set(ScorecardPhaseDraft.Field.allCases),
                       "every value the rules use is on the sheet")
        let labels: [ScorecardPhaseDraft.Field: String] = [
            .name: "Name", .startDay: "Start date", .targetWeight: "Target weight",
            .rateLow: "At least", .rateHigh: "At most",
            .waistWindowWeeks: "Waist compared over", .waistMinDecreaseCm: "Waist must be down at least",
            .liftDropTolerancePercent: "A lift has dropped below", .liftDropShare: "Share of lifts that dropped",
            .liftDropConsecutiveWeeks: "For", .addCaloriesKcal: "Then add",
            .slowLossThresholdKgPerWeek: "Loss under", .slowLossConsecutiveWeeks: "For",
            .reduceCarbsKcal: "Then take from carbohydrate",
            .rateWindowWeeks: "Rate fitted over", .maxProjectionWeeks: "Projection stops at",
            .targetToleranceKg: "Target counts as reached within",
            .proteinFloorGrams: "Daily floor", .proteinMinDaysPerWeek: "Days a week at or above it",
            .maxWeighInAgeWeeks: "A verdict lapses after",
        ]
        for field in ScorecardPhaseDraft.Field.allCases {
            XCTAssertEqual(field.label, labels[field], field.rawValue)
        }
    }

    func testEveryParameterGroupIsEditableAndIsStored() throws {
        let (settings, _) = try makeSettings()
        let draft = fixtureDraft()
        XCTAssertTrue(draft.canSave)
        XCTAssertTrue(draft.save(to: settings))

        XCTAssertEqual(settings.phases, [fixturePhase])
        XCTAssertEqual(settings.parameters, Fixture.parameters)
        XCTAssertFalse(settings.rulesNeedAttention)
        XCTAssertEqual(settings.evaluationPhase(on: "2031-01-29"), Fixture.phase)

        // One field of each group, changed and stored again.
        var edited = ScorecardPhaseDraft.current(settings: settings, today: "2031-01-29")
        XCTAssertEqual(edited.title, "Phase and rules")
        XCTAssertFalse(edited.isNewPhase)
        XCTAssertEqual(edited.name, "Fixture cut")
        XCTAssertEqual(edited.startDay, "2031-01-06")
        XCTAssertEqual(edited.targetWeightKg, 94.0)
        XCTAssertEqual(edited.parameters, Fixture.parameters)
        edited.targetWeightKg = 93.0                        // Phase
        edited.rateHighPercentPerWeek = 1.00                // Expected rate of loss
        edited.parameters.waistWindowWeeks = 3              // Rule 1
        edited.parameters.addCaloriesKcal = 200             // Rule 2
        edited.parameters.reduceCarbsKcal = 150             // Rule 3
        edited.parameters.maxProjectionWeeks = 52           // Rate and projection
        edited.parameters.proteinFloorGrams = 110           // Protein
        edited.parameters.maxWeighInAgeWeeks = 2            // Weigh-ins
        XCTAssertTrue(edited.save(to: settings))

        XCTAssertEqual(settings.phases.count, 1, "editing replaces the active phase, it does not add one")
        XCTAssertEqual(settings.phases.first?.targetWeightKg, 93.0)
        XCTAssertEqual(settings.phases.first?.rateHighPercentPerWeek, 1.00)
        XCTAssertEqual(settings.phases.first?.rateLowPercentPerWeek, 0.40)
        var expected = Fixture.parameters
        expected.waistWindowWeeks = 3
        expected.addCaloriesKcal = 200
        expected.reduceCarbsKcal = 150
        expected.maxProjectionWeeks = 52
        expected.proteinFloorGrams = 110
        expected.maxWeighInAgeWeeks = 2
        XCTAssertEqual(settings.parameters, expected)
        XCTAssertEqual(ScorecardPhaseDraft.current(settings: settings, today: "2031-01-29"), edited)
    }

    /// Frame E3.
    func testE3ABandWithLowAboveHighNamesBothEndsAndCannotBeSaved() throws {
        let (settings, defaults) = try makeSettings()
        XCTAssertTrue(fixtureDraft().save(to: settings))
        let phasesBefore = defaults.string(forKey: "cutScorecard.phases")
        let rulesBefore = defaults.string(forKey: "cutScorecard.rules")

        var draft = ScorecardPhaseDraft.current(settings: settings, today: "2031-01-29")
        draft.rateLowPercentPerWeek = 1.40
        XCTAssertEqual(draft.invalidFields, [.rateLow, .rateHigh])
        XCTAssertEqual(draft.validationMessage, "\"At least\" is above \"At most\". Fix one of them to save.")
        XCTAssertFalse(draft.canSave)
        XCTAssertFalse(draft.save(to: settings))
        XCTAssertEqual(defaults.string(forKey: "cutScorecard.phases"), phasesBefore, "nothing was written")
        XCTAssertEqual(defaults.string(forKey: "cutScorecard.rules"), rulesBefore)

        draft.rateLowPercentPerWeek = 1.20
        XCTAssertEqual(draft.invalidFields, [], "low equal to high is a valid band")
        XCTAssertTrue(draft.canSave)
    }

    /// §10.5 "Invalid": a field that fails §6.5 is marked, named, and Save is disabled.
    func testAValueThatCannotBeSavedNamesItsField() {
        typealias Field = ScorecardPhaseDraft.Field
        let cases: [(Field, (inout ScorecardPhaseDraft) -> Void)] = [
            (.startDay, { $0.startDay = "2031-02-30" }),
            (.targetWeight, { $0.targetWeightKg = 0 }),
            (.rateLow, { $0.rateLowPercentPerWeek = -0.1 }),
            (.waistWindowWeeks, { $0.parameters.waistWindowWeeks = 0 }),
            (.waistMinDecreaseCm, { $0.parameters.waistMinDecreaseCm = -0.1 }),
            (.liftDropTolerancePercent, { $0.parameters.liftDropTolerancePercent = 100 }),
            (.liftDropShare, { $0.parameters.liftDropShare = 0 }),
            (.liftDropShare, { $0.parameters.liftDropShare = 1.01 }),
            (.liftDropConsecutiveWeeks, { $0.parameters.liftDropConsecutiveWeeks = 0 }),
            (.addCaloriesKcal, { $0.parameters.addCaloriesKcal = -1 }),
            (.slowLossThresholdKgPerWeek, { $0.parameters.slowLossThresholdKgPerWeek = -0.1 }),
            (.slowLossConsecutiveWeeks, { $0.parameters.slowLossConsecutiveWeeks = 0 }),
            (.reduceCarbsKcal, { $0.parameters.reduceCarbsKcal = -1 }),
            (.rateWindowWeeks, { $0.parameters.rateWindowWeeks = 0 }),
            (.maxProjectionWeeks, { $0.parameters.maxProjectionWeeks = 0 }),
            (.targetToleranceKg, { $0.parameters.targetToleranceKg = -0.5 }),
            (.targetToleranceKg, { $0.parameters.targetToleranceKg = .nan }),
            (.proteinFloorGrams, { $0.parameters.proteinFloorGrams = 0 }),
            (.proteinMinDaysPerWeek, { $0.parameters.proteinMinDaysPerWeek = 8 }),
            (.proteinMinDaysPerWeek, { $0.parameters.proteinMinDaysPerWeek = 0 }),
            (.maxWeighInAgeWeeks, { $0.parameters.maxWeighInAgeWeeks = -1 }),
        ]
        for (field, change) in cases {
            var draft = fixtureDraft()
            change(&draft)
            XCTAssertEqual(draft.invalidFields, [field], field.rawValue)
            XCTAssertFalse(draft.canSave, field.rawValue)
            let message = draft.validationMessage ?? ""
            XCTAssertTrue(message.contains(field.label), "\(field.rawValue): \"\(message)\" names the field")
        }
        // The boundaries §6.5 allows are not marked.
        var edges = fixtureDraft()
        edges.parameters.maxWeighInAgeWeeks = 0
        edges.parameters.waistMinDecreaseCm = 0
        edges.parameters.liftDropTolerancePercent = 0
        edges.parameters.liftDropShare = 1
        edges.parameters.addCaloriesKcal = 0
        edges.parameters.proteinMinDaysPerWeek = 7
        XCTAssertEqual(edges.invalidFields, [])
        XCTAssertTrue(edges.canSave)
    }

    func testTheProteinFloorAndTheTargetMayBeLeftEmpty() throws {
        let (settings, _) = try makeSettings()
        var draft = fixtureDraft()
        draft.parameters.proteinFloorGrams = nil
        draft.targetWeightKg = nil
        XCTAssertEqual(draft.invalidFields, [])
        XCTAssertTrue(draft.save(to: settings))
        XCTAssertNil(settings.parameters.proteinFloorGrams)
        XCTAssertNil(settings.phases.first?.targetWeightKg)
    }

    func testStartingANewPhaseKeepsTheOldOneInTheList() throws {
        let (settings, _) = try makeSettings()
        XCTAssertTrue(fixtureDraft().save(to: settings))

        var next = ScorecardPhaseDraft.current(settings: settings, today: "2031-06-05").startingNewPhase(today: "2031-06-05")
        XCTAssertTrue(next.isNewPhase)
        XCTAssertEqual(next.title, "New phase")
        XCTAssertEqual(next.startDay, "2031-06-05")
        next.name = "Second cut"
        next.targetWeightKg = 90.0
        XCTAssertTrue(next.save(to: settings))

        XCTAssertEqual(settings.phases.count, 2)
        XCTAssertEqual(settings.phases.first, fixturePhase, "the earlier phase is stored unchanged")
        XCTAssertEqual(settings.phases.last?.name, "Second cut")
        XCTAssertEqual(settings.phases.last?.startDay, "2031-06-05")
        XCTAssertEqual(settings.activePhase(on: "2031-06-04")?.name, "Fixture cut")
        XCTAssertEqual(settings.activePhase(on: "2031-06-05")?.name, "Second cut")
        XCTAssertEqual(ScorecardPhaseDraft.current(settings: settings, today: "2031-06-05").name, "Second cut")
    }

    /// Frame E4.
    func testE4APhaseOfKindOtherHasNoTargetNoBandAndNoRules() throws {
        let (settings, defaults) = try makeSettings()
        XCTAssertTrue(fixtureDraft().save(to: settings))
        let rulesBefore = defaults.string(forKey: "cutScorecard.rules")

        var other = ScorecardPhaseDraft.current(settings: settings, today: "2031-06-05").startingNewPhase(today: "2031-06-05")
        other.kind = .other
        other.name = "Maintenance"
        XCTAssertEqual(other.groups.map(\.title), ["Phase"])
        XCTAssertEqual(other.groups.first?.fields, [.name, .startDay])
        other.rateLowPercentPerWeek = 9
        other.rateHighPercentPerWeek = 1
        XCTAssertEqual(other.invalidFields, [], "a band that is not shown cannot block the save")
        XCTAssertTrue(other.save(to: settings))

        XCTAssertEqual(settings.phases.count, 2)
        let stored = try XCTUnwrap(settings.phases.last)
        XCTAssertEqual(stored.kind, .other)
        XCTAssertEqual(stored.name, "Maintenance")
        XCTAssertNil(stored.targetWeightKg)
        XCTAssertEqual(defaults.string(forKey: "cutScorecard.rules"), rulesBefore, "the rules are left as they were")
        XCTAssertNil(settings.evaluationPhase(on: "2031-06-05"), "no cut phase is active from that day")
        XCTAssertNotNil(settings.evaluationPhase(on: "2031-06-04"))
        XCTAssertEqual(settings.phases.first, fixturePhase)
    }
}
