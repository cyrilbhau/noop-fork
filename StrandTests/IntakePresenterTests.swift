// API ASSUMED BY THESE TESTS
//
// Stage 3 specification §9.5, §10.1, §10.2, §11 and §12.3 (`IntakePresenterTests.swift`). Written
// before the implementation exists. The specification names `IntakePresenter`, `IntakeCard`,
// `IntakeScreenModel` and `IntakeClock` (Strand/Data/IntakePresenter.swift, IntakeModel.swift) and
// gives only `IntakeClock`'s fields; everything else below is fixed here [assumed] so the states of
// §10.1 and §10.2 can be tested through the presenter. Views draw these values and decide nothing.
//
//     struct IntakeClock: Equatable {                                                    [spec §9.5]
//         let now: Date; let today: String; let minuteOfDay: Int; let dayIsOpen: Bool
//         /// `today` is `IntakeAggregation.dayKey` of `now` under `zoneLog`; `minuteOfDay` is `now`'s
//         /// minute in `timeZone`; `dayIsOpen` is true when `cutoffMinuteOfDay` is nil or
//         /// `minuteOfDay` is before it (§7.5).
//         static func resolve(now: Date, zoneLog: [IntakeZoneSegment], timeZone: TimeZone,
//                             cutoffMinuteOfDay: Int?) -> IntakeClock                      [assumed]
//     }
//
//     /// Everything one render needs, gathered once (§9.5).                              [assumed]
//     struct IntakePresenterInput: Equatable {
//         init(source: IntakeSourceSetting, day: String)    // every other field takes its default
//         var source: IntakeSourceSetting
//         var sourceChosen: Bool = true                     // IntakeSettings.hasChosenSource
//         var day: String                                   // the calendar day shown
//         var resolved: ResolvedIntakeDay? = nil            // the provider's day; nil: nothing stored
//         var history: [ResolvedIntakeDay] = []             // the provider's series
//         var floorGrams: Double? = nil                     // IntakeSettings.proteinFloorGrams
//         var targets: IntakeTargets = IntakeTargets()      // IntakeSettings.targets(on: day)
//         var targetsNeedAttention: Bool = false
//         var lastHealthOutcome: IntakeHealthSync.Outcome? = nil
//         var lastHealthAttemptAt: Date? = nil
//         var healthAppNamesOnDay: [String] = []            // the Health apps that wrote on `day`
//         var foodAppName: String? = nil                    // the app named in "From %@" and "Edit this in %@"
//         var entries: [IntakeEntry] = []                   // Path B, the day's entries
//         var restoredTotal: IntakeStoredDay? = nil         // Path B, §9.3
//         var isLoading: Bool = false
//         /// The one place a render's input is gathered from the provider and the settings.
//         @MainActor static func gather(provider: IntakeProvider, settings: IntakeSettings,
//                                       day: String) -> IntakePresenterInput
//     }
//
//     struct IntakeCard: Equatable {                                                     [assumed]
//         enum Status: Equatable { case loading, noSource, noFloor, notMeasured, below, atFloor, above,
//                                  stale, readFailed, pastDay, pastDayNotMeasured, targetsNeedAttention }
//         var status: Status
//         var value: String?        // whole grams; nil draws the dash, never "0" for not measured
//         var unit: String?         // "g" with a value
//         var caption: String?      // nil only while loading
//         var ring: Double?         // nil: no ring; 0 is the empty ring; never above 1
//         var floorGrams: Int?      // the printed floor (stage 1 R45)
//         var isDimmed: Bool        // the tertiary colour (stale)
//         var opensIntake: Bool
//     }
//
//     struct IntakeScreenModel: Equatable {                                              [assumed]
//         enum Layout: Equatable { case loading, setup, supplementsOnly, full }
//         struct Protein: Equatable { var value: String?; var floorGrams: Int?; var line: String;
//                                     var ring: Double?; var showsSetFloorRow: Bool }
//         struct Energy: Equatable { var title: String; var state: IntakeEnergyState; var value: String?;
//                                    var line: String? }
//         struct ChartPoint: Equatable { let day: String; let grams: Double?; let meetsFloor: Bool? }
//         struct Chart: Equatable { var points: [ChartPoint]; var message: String? }
//         var layout: Layout
//         var setupChoices: [String]       // the three sentences of §11 "Setup", in order
//         var protein: Protein?
//         var energy: Energy?
//         var chart: Chart?                // 28 days ending `day`, oldest first
//         var sourceLine: String?
//         var freshness: String?
//         var freshnessIsStale: Bool
//         var showsReadAgain: Bool
//         var twoApps: String?
//         var showsChooseOne: Bool
//         var problem: String?
//         var correction: String?
//         var showsDataSourcesRow: Bool
//         var attention: String?
//         var entries: [IntakeEntry]
//         var showsRestoredTotal: Bool
//         var showsCutoffRow: Bool
//     }
//
//     enum IntakePresenter {
//         static func card(_ input: IntakePresenterInput, clock: IntakeClock, timeZone: TimeZone,
//                          locale: Locale) -> IntakeCard
//         static func loadingCard() -> IntakeCard
//         static func screen(_ input: IntakePresenterInput, clock: IntakeClock, timeZone: TimeZone,
//                            locale: Locale) -> IntakeScreenModel
//         /// "HH:mm" for en_GB.
//         static func timeText(_ date: Date, timeZone: TimeZone, locale: Locale) -> String
//     }
//
// Behaviour assumed where the specification leaves it open:
//  1. Card caption precedence where two states apply (design round S3, README decision 5): no source,
//     past day, read failed with nothing stored, targets unreadable, no floor, not measured, stale,
//     then below / at / above. Each test below sets up one state only, except where a test names
//     the precedence it checks.
//  2. A caption joins its state and its time with " · ". A CSV value's time is "imported".
//  3. "Stale" is a Health value for today read more than three hours before `clock.now`.
//  4. The freshness time on the card and the screen is the time stored with the protein value.
//  5. Energy lines are the §11 strings with whole kilocalories; the soFar value is "%lld kcal so far".
//
// Expected sentences with a figure of four or more digits are built with `String(localized:)` and
// interpolation, the mechanism the app uses, so the expectation does not depend on the test
// machine's grouping separator. Synthetic values only: the Fixture Person (§13.1, §13.6).

import XCTest
import WhoopStore
import StrandAnalytics
@testable import Strand

@MainActor
final class IntakePresenterTests: XCTestCase {
    private let suites = IntakeSuites()
    private let utc = TimeZone(identifier: "UTC")!
    private let gb = Locale(identifier: "en_GB")
    private let clockFixture = IntakeTestClock()

    override func tearDown() {
        suites.removeAll()
        super.tearDown()
    }

    // MARK: - Fixture

    private var today: String { clockFixture.today }
    private var yesterday: String { clockFixture.day(-1) }
    /// 15:20, the day open (no cutoff passed).
    private var clock: IntakeClock {
        IntakeClock(now: clockFixture.now, today: today, minuteOfDay: 15 * 60 + 20, dayIsOpen: true)
    }
    /// Ten minutes before now: 15:10.
    private var fresh: Int { clockFixture.epoch(0, hour: 15, minute: 10) }
    /// Four hours before now: 11:20.
    private var stale: Int { clockFixture.epoch(0, hour: 11, minute: 20) }

    private func value(_ v: Double?, _ source: IntakeSource, _ readAt: Int?) -> ResolvedIntakeValue? {
        v.map { ResolvedIntakeValue(value: $0, source: source, readAtEpochSeconds: source == .nutritionCsv ? nil : readAt) }
    }

    /// A render of `day` with `grams` and `kcal` from `valueSource`, the floor 100 and the §13.1 range.
    private func input(grams: Double?, kcal: Double? = nil, source: IntakeSourceSetting = .appleHealth,
                       valueSource: IntakeSource? = nil, readAt: Int? = nil, day: String? = nil,
                       floor: Double? = 100) -> IntakePresenterInput {
        let shown = day ?? today
        var input = IntakePresenterInput(source: source, day: shown)
        let from = valueSource ?? (source == .quickAdd ? .quickAdd : .appleHealth)
        let time = readAt ?? fresh
        if grams != nil || kcal != nil {
            input.resolved = ResolvedIntakeDay(day: shown, protein: value(grams, from, time), energy: value(kcal, from, time))
        }
        input.floorGrams = floor
        var targets = IntakeFixture.targets
        targets.proteinFloorGrams = floor
        input.targets = targets
        input.foodAppName = IntakeFixture.foodApp.name
        if from == .appleHealth, grams != nil { input.healthAppNamesOnDay = [IntakeFixture.foodApp.name] }
        return input
    }

    private func card(_ input: IntakePresenterInput, clock: IntakeClock? = nil) -> IntakeCard {
        IntakePresenter.card(input, clock: clock ?? self.clock, timeZone: utc, locale: gb)
    }

    private func screen(_ input: IntakePresenterInput, clock: IntakeClock? = nil) -> IntakeScreenModel {
        IntakePresenter.screen(input, clock: clock ?? self.clock, timeZone: utc, locale: gb)
    }

    // MARK: - The clock (§9.5)

    func testTheClockResolvesTodayAndWhetherTheDayIsOpen() {
        let log = [IntakeZoneSegment(fromEpochSeconds: 0, zoneIdentifier: "Etc/UTC")]
        let open = IntakeClock.resolve(now: clockFixture.now, zoneLog: log, timeZone: utc, cutoffMinuteOfDay: 1_200)
        XCTAssertEqual(open, IntakeClock(now: clockFixture.now, today: today, minuteOfDay: 920, dayIsOpen: true))
        let atCutoff = IntakeClock.resolve(now: clockFixture.at(0, hour: 20), zoneLog: log, timeZone: utc,
                                           cutoffMinuteOfDay: 1_200)
        XCTAssertFalse(atCutoff.dayIsOpen, "the cutoff closes the day")
        let late = IntakeClock.resolve(now: clockFixture.at(0, hour: 20, minute: 40), zoneLog: log, timeZone: utc,
                                       cutoffMinuteOfDay: nil)
        XCTAssertTrue(late.dayIsOpen, "with no cutoff set the day closes only at midnight")
        // Today follows the zone log, not the zone passed for the minute.
        let auckland = [IntakeZoneSegment(fromEpochSeconds: 0, zoneIdentifier: "Pacific/Auckland")]
        let ahead = IntakeClock.resolve(now: clockFixture.at(0, hour: 15, minute: 20), zoneLog: auckland,
                                        timeZone: TimeZone(identifier: "Pacific/Auckland")!, cutoffMinuteOfDay: nil)
        XCTAssertEqual(ahead.today, clockFixture.day(1))
    }

    // MARK: - §10.1 The card, one test per state

    func testCardLoading() {
        let loading = IntakePresenter.loadingCard()
        XCTAssertEqual(loading.status, .loading)
        XCTAssertNil(loading.value)
        XCTAssertNil(loading.caption)
        XCTAssertNil(loading.ring)
        XCTAssertFalse(loading.opensIntake)
        var waiting = input(grams: 95)
        waiting.isLoading = true
        XCTAssertEqual(card(waiting).status, .loading)
    }

    func testCardNoSourceChosen() {
        for chosen in [false, true] {
            var none = input(grams: nil, source: .none)
            none.sourceChosen = chosen
            let result = card(none)
            XCTAssertEqual(result.status, .noSource)
            XCTAssertNil(result.value, "a dash")
            XCTAssertNil(result.ring)
            XCTAssertEqual(result.caption, "Choose where intake comes from")
            XCTAssertTrue(result.opensIntake)
        }
    }

    func testCardNoFloorSet() {
        let result = card(input(grams: 95, floor: nil))
        XCTAssertEqual(result.status, .noFloor)
        XCTAssertEqual(result.value, "95", "grams so far")
        XCTAssertEqual(result.unit, "g")
        XCTAssertNil(result.ring, "no ring")
        XCTAssertNil(result.floorGrams)
        XCTAssertEqual(result.caption, "No floor set")
    }

    func testCardNotMeasuredToday() {
        let result = card(input(grams: nil))
        XCTAssertEqual(result.status, .notMeasured)
        XCTAssertNil(result.value, "a dash, never 0")
        XCTAssertEqual(result.ring, 0, "the empty ring")
        XCTAssertEqual(result.caption, "Nothing logged today")
        // Energy alone logged: protein is still not measured.
        XCTAssertEqual(card(input(grams: nil, kcal: 1_450)).caption, "Nothing logged today")
    }

    func testCardBelowTheFloor() {
        let result = card(input(grams: 95))
        XCTAssertEqual(result.status, .below)
        XCTAssertEqual(result.value, "95")
        XCTAssertEqual(result.unit, "g")
        XCTAssertEqual(try XCTUnwrap(result.ring), 0.95, accuracy: 1e-9)
        XCTAssertEqual(result.floorGrams, 100)
        XCTAssertEqual(result.caption, "5 g to your floor · 15:10")
        XCTAssertFalse(result.isDimmed)
        XCTAssertTrue(result.opensIntake)
        // Never "0 g remaining" before the floor is met (§7.4).
        XCTAssertEqual(card(input(grams: 99.9994)).caption, "1 g to your floor · 15:10")
        XCTAssertEqual(card(input(grams: 99.9994)).value, "99")
    }

    func testCardAtTheFloor() {
        for grams in [100, 99.9996] {
            let result = card(input(grams: grams))
            XCTAssertEqual(result.status, .atFloor, "\(grams)")
            XCTAssertEqual(result.value, "100")
            XCTAssertEqual(result.ring, 1, "complete")
            XCTAssertEqual(result.caption, "Floor met · 15:10")
        }
    }

    func testCardAboveTheFloor() {
        let result = card(input(grams: 105))
        XCTAssertEqual(result.status, .above)
        XCTAssertEqual(result.value, "105", "the number keeps counting")
        XCTAssertEqual(result.ring, 1, "complete, and no second lap")
        XCTAssertEqual(result.caption, "+5 g over your floor · 15:10")
    }

    func testCardStale() {
        let result = card(input(grams: 95, readAt: stale))
        XCTAssertEqual(result.status, .stale)
        XCTAssertEqual(result.value, "95")
        XCTAssertTrue(result.isDimmed, "the tertiary colour")
        XCTAssertEqual(result.caption, "Last read 11:20")
        // Under three hours is fresh; only a Health value goes stale.
        XCTAssertEqual(card(input(grams: 95, readAt: clockFixture.epoch(0, hour: 12, minute: 30))).status, .below)
        let quick = card(input(grams: 95, source: .quickAdd, readAt: stale))
        XCTAssertEqual(quick.status, .below)
        XCTAssertFalse(quick.isDimmed)
        XCTAssertEqual(quick.caption, "5 g to your floor · 11:20")
    }

    func testCardHealthReadFailedWithNothingStored() {
        var failed = input(grams: nil)
        failed.lastHealthOutcome = .failedRead
        failed.lastHealthAttemptAt = clockFixture.at(0, hour: 15, minute: 15)
        let result = card(failed)
        XCTAssertEqual(result.status, .readFailed)
        XCTAssertNil(result.value)
        XCTAssertEqual(result.caption, "Could not read Apple Health")
        // With a figure stored, the figure is shown as usual.
        var kept = input(grams: 95)
        kept.lastHealthOutcome = .failedRead
        XCTAssertEqual(card(kept).caption, "5 g to your floor · 15:10")
    }

    func testCardPastDayMeasured() {
        let past = input(grams: 95, readAt: clockFixture.epoch(-1, hour: 21), day: yesterday)
        let result = card(past)
        XCTAssertEqual(result.status, .pastDay)
        XCTAssertEqual(result.value, "95", "that day's grams")
        XCTAssertEqual(try XCTUnwrap(result.ring), 0.95, accuracy: 1e-9, "the ring as it ended")
        XCTAssertEqual(result.caption, "Day total", "no remaining, no time, never stale")
        XCTAssertFalse(result.isDimmed)
        XCTAssertEqual(card(input(grams: 120, day: yesterday)).ring, 1)
    }

    func testCardPastDayNotMeasured() {
        let result = card(input(grams: nil, day: yesterday))
        XCTAssertEqual(result.status, .pastDayNotMeasured)
        XCTAssertNil(result.value)
        XCTAssertNil(result.ring)
        XCTAssertEqual(result.caption, "Not measured")
    }

    func testCardTargetsUnreadable() {
        var broken = input(grams: 95)
        broken.targetsNeedAttention = true
        let result = card(broken)
        XCTAssertEqual(result.status, .targetsNeedAttention)
        XCTAssertEqual(result.value, "95", "grams")
        XCTAssertEqual(result.caption, "Your targets need attention")
    }

    func testCardQuickAddTimeIsTheLastEntryTime() {
        let result = card(input(grams: 95, source: .quickAdd, readAt: clockFixture.epoch(0, hour: 13, minute: 5)))
        XCTAssertEqual(result.caption, "5 g to your floor · 13:05")
    }

    func testCardCsvValueEndsImported() {
        let csv = input(grams: 95, valueSource: .nutritionCsv)
        XCTAssertEqual(card(csv).caption, "5 g to your floor · imported")
        XCTAssertFalse(card(csv).isDimmed, "a CSV value has no read time and is never stale")
        XCTAssertEqual(card(input(grams: 120, valueSource: .nutritionCsv, day: yesterday)).caption, "Day total · imported")
    }

    func testCardRingNeverExceedsOneAndNeverShowsZeroForMissing() {
        for grams in [0.0, 1, 50, 99.4, 100, 140, 1_000] {
            let ring = card(input(grams: grams)).ring
            XCTAssertNotNil(ring)
            XCTAssertLessThanOrEqual(ring ?? 2, 1)
            XCTAssertGreaterThanOrEqual(ring ?? -1, 0)
        }
        XCTAssertEqual(card(input(grams: 0)).value, "0", "a logged zero is a measured zero")
        XCTAssertNil(card(input(grams: nil)).value)
    }

    func testCardAndFreshnessLineUseOneClock() {
        let readAt = clockFixture.epoch(0, hour: 12, minute: 20)
        let shown = input(grams: 95, readAt: readAt)
        // At 15:19 the figure is under three hours old on both surfaces.
        let early = IntakeClock(now: clockFixture.at(0, hour: 15, minute: 19), today: today, minuteOfDay: 919, dayIsOpen: true)
        XCTAssertEqual(card(shown, clock: early).status, .below)
        XCTAssertEqual(screen(shown, clock: early).freshness, "Read 12:20")
        XCTAssertFalse(screen(shown, clock: early).freshnessIsStale)
        // At 15:21 both turn stale together, from the clock passed in and not from the real time.
        let late = IntakeClock(now: clockFixture.at(0, hour: 15, minute: 21), today: today, minuteOfDay: 921, dayIsOpen: true)
        XCTAssertEqual(card(shown, clock: late).status, .stale)
        XCTAssertEqual(card(shown, clock: late).caption, "Last read 12:20")
        XCTAssertEqual(screen(shown, clock: late).freshness, "Last read 12:20")
        XCTAssertTrue(screen(shown, clock: late).freshnessIsStale)
        // A clock years ahead of the real one: only the clock passed in decides "today".
        let future = IntakeClock(now: Date(timeIntervalSince1970: 4_102_444_800), today: "2100-01-01", minuteOfDay: 0,
                                 dayIsOpen: true)
        XCTAssertEqual(card(shown, clock: future).status, .pastDay, "the shown day is not the clock's today")
        XCTAssertEqual(IntakePresenter.timeText(Date(timeIntervalSince1970: TimeInterval(readAt)), timeZone: utc, locale: gb),
                       "12:20")
    }

    // MARK: - §10.2 The screen, one test per state with text

    func testScreenLoading() {
        var loading = input(grams: 95)
        loading.isLoading = true
        XCTAssertEqual(screen(loading).layout, .loading)
    }

    func testScreenSetupPromptWhenNoSourceWasChosen() {
        var setup = input(grams: nil, source: .none)
        setup.sourceChosen = false
        let model = screen(setup)
        XCTAssertEqual(model.layout, .setup)
        XCTAssertEqual(model.setupChoices, ["Apple Health: read what your food app writes",
                                            "Enter here: add protein and calories yourself",
                                            "None: supplements and the cutoff reminder only"])
        XCTAssertNil(model.protein)
    }

    func testScreenPathCShowsOnlySupplementsAndTheCutoffRow() {
        let model = screen(input(grams: nil, source: .none))
        XCTAssertEqual(model.layout, .supplementsOnly)
        XCTAssertNil(model.protein, "no ring")
        XCTAssertNil(model.chart, "no chart")
        XCTAssertNil(model.energy)
        XCTAssertTrue(model.showsCutoffRow)
    }

    func testScreenNoFloorSet() {
        let model = screen(input(grams: 95, floor: nil))
        XCTAssertEqual(model.layout, .full)
        XCTAssertEqual(model.protein?.value, "95")
        XCTAssertNil(model.protein?.ring, "numbers without a ring")
        XCTAssertNil(model.protein?.floorGrams)
        XCTAssertEqual(model.protein?.line, "No floor set")
        XCTAssertEqual(model.protein?.showsSetFloorRow, true)
    }

    func testScreenNotMeasuredToday() {
        let model = screen(input(grams: nil))
        XCTAssertNil(model.protein?.value)
        XCTAssertEqual(model.protein?.ring, 0, "the empty ring")
        XCTAssertEqual(model.protein?.line, "Nothing logged today")
        XCTAssertEqual(model.sourceLine, "Apple Health", "the source line, with no time to give")
        XCTAssertNil(model.freshness)
    }

    func testScreenBelowAtAndAboveTheFloor() {
        let below = screen(input(grams: 95))
        XCTAssertEqual(below.protein?.value, "95")
        XCTAssertEqual(below.protein?.floorGrams, 100)
        XCTAssertEqual(below.protein?.line, "5 g to your floor")
        XCTAssertEqual(try XCTUnwrap(below.protein?.ring), 0.95, accuracy: 1e-9)
        XCTAssertEqual(below.protein?.showsSetFloorRow, false)
        let at = screen(input(grams: 100))
        XCTAssertEqual(at.protein?.line, "Floor met")
        XCTAssertEqual(at.protein?.ring, 1)
        let above = screen(input(grams: 105))
        XCTAssertEqual(above.protein?.line, "+5 g over your floor")
        XCTAssertEqual(above.protein?.value, "105")
        XCTAssertEqual(above.protein?.ring, 1)
        let past = screen(input(grams: 105, day: yesterday))
        XCTAssertEqual(past.protein?.line, "Day total", "a past day's closed total, without remaining")
        XCTAssertEqual(screen(input(grams: nil, day: yesterday)).protein?.line, "Not measured")
    }

    func testScreenEnergyLines() {
        let closed = IntakeClock(now: clockFixture.at(0, hour: 20, minute: 40), today: today, minuteOfDay: 1_240,
                                 dayIsOpen: false)
        // §13.4 with the §13.1 range and hard floor.
        let notMeasured = screen(input(grams: 95)).energy
        XCTAssertEqual(notMeasured?.title, "Calories eaten", "never 'Calories' alone (C9)")
        XCTAssertEqual(notMeasured?.state, .notMeasured)
        XCTAssertNil(notMeasured?.value)
        XCTAssertEqual(notMeasured?.line, "Not measured")

        let soFar = screen(input(grams: 95, kcal: 1_450)).energy
        XCTAssertEqual(soFar?.state, .soFar)
        XCTAssertEqual(soFar?.value, String(localized: "\(1_450) kcal so far"))
        XCTAssertEqual(soFar?.line, String(localized: "\(950) kcal to the bottom of your range"))

        let aboveOpen = screen(input(grams: 95, kcal: 2_700)).energy
        XCTAssertEqual(aboveOpen?.state, .aboveRange, "reported while the day is still open")
        XCTAssertEqual(aboveOpen?.line, String(localized: "\(100) kcal above your range"))

        let hard = screen(input(grams: 95, kcal: 1_500), clock: closed).energy
        XCTAssertEqual(hard?.state, .belowHardFloor)
        XCTAssertEqual(hard?.line, String(localized: "Below your floor of \(2_100) kcal"))

        let below = screen(input(grams: 95, kcal: 2_100), clock: closed).energy
        XCTAssertEqual(below?.state, .belowRange)
        XCTAssertEqual(below?.line, String(localized: "Below your range of \(2_400) to \(2_600) kcal"))

        for kcal in [2_400.0, 2_600] {
            let inRange = screen(input(grams: 95, kcal: kcal), clock: closed).energy
            XCTAssertEqual(inRange?.state, .inRange, "\(kcal), inclusive")
            XCTAssertEqual(inRange?.line, String(localized: "In your range of \(2_400) to \(2_600) kcal"))
        }

        var noRange = input(grams: 95, kcal: 1_450)
        noRange.targets = IntakeTargets(proteinFloorGrams: 100)
        XCTAssertEqual(screen(noRange).energy?.state, .noRange)
        XCTAssertEqual(screen(noRange).energy?.line, "No range set")

        // A past day is closed whatever the clock says.
        let past = screen(input(grams: 95, kcal: 1_500, day: yesterday)).energy
        XCTAssertEqual(past?.state, .belowHardFloor)
        // The note below the hard floor never appears while today is open (§7.5).
        XCTAssertEqual(screen(input(grams: 95, kcal: 1_500)).energy?.state, .soFar)
    }

    func testScreenOneSourceWroteToday() {
        let model = screen(input(grams: 95))
        XCTAssertEqual(model.sourceLine, "From Fixture Food")
        XCTAssertEqual(model.freshness, "Read 15:10")
        XCTAssertFalse(model.freshnessIsStale)
        XCTAssertNil(model.twoApps)
        XCTAssertFalse(model.showsChooseOne)
    }

    func testScreenTwoAppsWroteToday() {
        var two = input(grams: 105)
        two.healthAppNamesOnDay = [IntakeFixture.foodApp.name, IntakeFixture.otherApp.name]
        let model = screen(two)
        XCTAssertEqual(model.twoApps, "Two apps wrote today: Fixture Food and Fixture Other. Both are counted.")
        XCTAssertTrue(model.showsChooseOne)
    }

    func testScreenStale() {
        let model = screen(input(grams: 95, readAt: stale))
        XCTAssertEqual(model.freshness, "Last read 11:20")
        XCTAssertTrue(model.freshnessIsStale, "the time in the secondary colour")
        XCTAssertTrue(model.showsReadAgain)
    }

    func testScreenReadFailed() {
        var failed = input(grams: 95)
        failed.lastHealthOutcome = .failedRead
        failed.lastHealthAttemptAt = clockFixture.at(0, hour: 15, minute: 15)
        let model = screen(failed)
        XCTAssertEqual(model.problem, "Apple Health could not be read at 15:15. Showing the last figures.")
        XCTAssertEqual(model.protein?.value, "95", "the last figures stay")
    }

    func testScreenWindowCameBackEmpty() {
        var empty = input(grams: nil)
        empty.lastHealthOutcome = .preserved
        empty.lastHealthAttemptAt = clockFixture.at(0, hour: 15, minute: 15)
        let model = screen(empty)
        XCTAssertEqual(model.problem, "Apple Health returned no food entries. If you log in Fixture Food, "
                       + "check that it is allowed to write to Health.")
        XCTAssertFalse(model.problem?.lowercased().contains("denied") ?? true, "no claim that access was denied")
        XCTAssertFalse(model.problem?.lowercased().contains("permission") ?? true)
    }

    func testScreenHistoryWithFewerThanTwoDays() {
        var first = input(grams: 95)
        first.history = [ResolvedIntakeDay(day: today, protein: value(95, .appleHealth, fresh), energy: nil)]
        XCTAssertEqual(screen(first).chart?.message, "More days will appear here")

        var week = input(grams: 95)
        week.history = IntakeFixture.weekProtein.enumerated().map { index, grams in
            ResolvedIntakeDay(day: clockFixture.day(index - 7), protein: value(grams, .quickAdd, fresh), energy: nil)
        } + [ResolvedIntakeDay(day: today, protein: value(95, .appleHealth, fresh), energy: nil)]
        let chart = try? XCTUnwrap(screen(week).chart)
        XCTAssertNil(chart?.message)
        XCTAssertEqual(chart?.points.count, 28, "the last 28 days")
        XCTAssertEqual(chart?.points.last?.day, today)
        XCTAssertEqual(chart?.points.first?.day, clockFixture.day(-27))
        XCTAssertEqual(chart?.points.filter { $0.grams != nil }.count, 8, "an unmeasured day is a gap, never zero")
        XCTAssertEqual(chart?.points.compactMap(\.meetsFloor).filter { $0 }.count, 6,
                       "6 of the 7 days before today at or above the floor; today's 95 g below it")
        XCTAssertTrue(chart?.points.filter { $0.grams == nil }.allSatisfy { $0.meetsFloor == nil } ?? false)
    }

    func testScreenChartPointsUseTheScorecardComparison() {
        var edge = input(grams: 95)
        edge.history = [ResolvedIntakeDay(day: clockFixture.day(-2), protein: value(99.9994, .quickAdd, fresh), energy: nil),
                        ResolvedIntakeDay(day: clockFixture.day(-1), protein: value(99.9996, .quickAdd, fresh), energy: nil)]
        let points = screen(edge).chart?.points ?? []
        XCTAssertEqual(points.first { $0.day == clockFixture.day(-2) }?.meetsFloor, false)
        XCTAssertEqual(points.first { $0.day == clockFixture.day(-1) }?.meetsFloor, true)
        var noFloor = edge
        noFloor.floorGrams = nil
        XCTAssertTrue((screen(noFloor).chart?.points ?? []).allSatisfy { $0.meetsFloor == nil })
    }

    func testScreenValueFromAnOlderSourceNamesIt() {
        let quick = screen(input(grams: 95, source: .appleHealth, valueSource: .quickAdd))
        XCTAssertEqual(quick.sourceLine, "Entered here")
        XCTAssertEqual(quick.freshness, "Entered 15:10")
        let csv = screen(input(grams: 120, valueSource: .nutritionCsv, day: yesterday))
        XCTAssertEqual(csv.sourceLine, "CSV import")
        XCTAssertEqual(csv.freshness, "imported")
        XCTAssertTrue(csv.showsDataSourcesRow, "a CSV value is corrected in Data Sources")
    }

    func testScreenTargetsUnreadable() {
        var broken = input(grams: 95, kcal: 1_450)
        broken.targetsNeedAttention = true
        broken.targets = IntakeTargets(proteinFloorGrams: 100)
        let model = screen(broken)
        XCTAssertEqual(model.attention, "Your targets need attention")
        XCTAssertNotEqual(model.energy?.line, "No range set", "that would be untrue: a range is stored, unreadable")
        XCTAssertNil(screen(input(grams: 95)).attention)
    }

    func testScreenCorrectingAValue() {
        let health = screen(input(grams: 95))
        XCTAssertEqual(health.correction, "Edit this in Fixture Food. NOOP reads it again when you return.")
        XCTAssertTrue(health.showsReadAgain)
        XCTAssertFalse(health.showsDataSourcesRow)

        var quick = input(grams: 70, source: .quickAdd)
        let entry = IntakeEntry(id: UUID(), loggedAt: clockFixture.at(0, hour: 8), day: today, proteinGrams: 30,
                                energyKcal: 150, label: IntakeFixture.preset.label)
        quick.entries = [entry]
        let model = screen(quick)
        XCTAssertEqual(model.entries, [entry], "every entry opens for edit or delete")
        XCTAssertEqual(model.sourceLine, "Entered here")
        XCTAssertNil(model.correction)
        XCTAssertFalse(model.showsReadAgain, "nothing to read again on Path B")
        XCTAssertFalse(model.showsRestoredTotal)

        var restored = input(grams: 95, source: .quickAdd)
        restored.restoredTotal = IntakeStoredDay(day: today, proteinGrams: 95, energyKcal: 1_450, readAtEpochSeconds: fresh)
        XCTAssertTrue(screen(restored).showsRestoredTotal, "the 'Restored total' row with Replace")
    }

    // MARK: - Gathering one render's input

    func testGatherReadsTheProviderAndTheSettingsOnce() async throws {
        let h = try await IntakeHarness.make(flag: true, source: .quickAdd, suites: suites)
        XCTAssertTrue(h.settings.setTargets(IntakeFixture.targets))
        try await h.seed(IntakeFixture.quickAddId, day: h.today, protein: 95, energy: 1_450, readAt: fresh)
        await h.provider.refresh()
        let gathered = IntakePresenterInput.gather(provider: h.provider, settings: h.settings, day: h.today)
        XCTAssertEqual(gathered.source, .quickAdd)
        XCTAssertTrue(gathered.sourceChosen)
        XCTAssertEqual(gathered.day, h.today)
        XCTAssertEqual(gathered.resolved, h.provider.day(h.today))
        XCTAssertEqual(gathered.history, h.provider.series())
        XCTAssertEqual(gathered.floorGrams, 100)
        XCTAssertEqual(gathered.targets, h.settings.targets(on: h.today))
        XCTAssertFalse(gathered.targetsNeedAttention)
        XCTAssertEqual(h.defaults.written, [IntakeSettings.targetsKey], "gathering writes nothing")
    }
}
