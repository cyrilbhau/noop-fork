import XCTest
import WhoopStore
@testable import Strand

final class TodayCardResolverTests: XCTestCase {
    private let today = "2026-10-29"

    private func day(_ key: String = "2026-10-29", hrv: Double? = nil, rhr: Int? = nil,
                     resp: Double? = nil, spo2: Double? = nil, skin: Double? = nil,
                     steps: Int? = nil, sleep: Double? = nil) -> DailyMetric {
        DailyMetric(day: key, totalSleepMin: sleep, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: rhr, avgHrv: hrv, recovery: nil,
                    strain: nil, exerciseCount: nil, spo2Pct: spo2, skinTempDevC: skin,
                    respRateBpm: resp, steps: steps)
    }

    private func inputs() -> TodayCardInputs {
        var result = TodayCardInputs()
        result.selectedDayKey = today
        result.locale = Locale(identifier: "en_US")
        result.activeIsWhoop4 = false
        return result
    }

    func testImplicitDefaultDeduplicatesOnlyAgainstVisibleKeyMetrics() {
        XCTAssertEqual(TodayCardResolver.selection(raw: " \n", visibleKeyMetrics: KeyMetric.defaultOrder),
                       [.stress, .fitnessAge, .vitality])
        XCTAssertEqual(TodayCardResolver.selection(raw: "", visibleKeyMetrics: nil), DashboardCard.defaultSelection)
        XCTAssertEqual(TodayCardResolver.selection(raw: "", visibleKeyMetrics: [.hrv]),
                       DashboardCard.defaultSelection.filter { $0 != .hrv })
    }

    func testExplicitSelectionKeepsOrderAndTwinsWhileGatesOnlyFilterRendering() {
        let saved: [DashboardCard] = [.coach, .hrv, .hydration, .stress]
        let raw = DashboardCardPrefs.encode(saved)
        XCTAssertEqual(TodayCardResolver.selection(raw: raw, visibleKeyMetrics: [.hrv]), saved)
        XCTAssertEqual(TodayCardResolver.renderList(raw: raw, hydrationEnabled: false, coachEnabled: false,
                                                   visibleKeyMetrics: [.hrv]), [.hrv, .stress])
        XCTAssertEqual(TodayCardResolver.renderList(raw: raw, hydrationEnabled: true, coachEnabled: true,
                                                   visibleKeyMetrics: [.hrv]), saved)
        XCTAssertEqual(TodayCardResolver.renderList(raw: DashboardCardPrefs.encode([.hydration]),
                                                   hydrationEnabled: false, coachEnabled: true,
                                                   visibleKeyMetrics: nil), [])
    }

    func testExplicitUnknownSelectionKeepsExistingDecoderFallback() {
        XCTAssertEqual(TodayCardResolver.selection(raw: "[\"future-card\"]", visibleKeyMetrics: KeyMetric.defaultOrder),
                       DashboardCard.defaultSelection)
    }

    func testOriginalKeyMetricValuesUnitsCaptionsChartKeysAndRoutes() throws {
        var input = inputs()
        input.displayDay = day(hrv: 57.6, rhr: 61, resp: 14.25, spo2: 97.6, skin: 0.3)
        input.caloriesCount = 642.7
        input.caloriesDetail = MetricCatalog.todayCaloriesMetric(hasImportedKcal: true, hasOnDeviceKcal: true)
        let expected: [(KeyMetric, String, String?, String?, TodayCardReadout.Tint, String, TabRoute)] = [
            (.hrv, "58", "ms", nil, .hrv, "hrv", .metric("hrv")),
            (.restingHr, "61", "bpm", nil, .heart, "rhr", .metric("rhr")),
            (.respiratory, 14.25.formatted(.number.precision(.fractionLength(1)).locale(input.locale)), "rpm", nil,
             .breath, "resp_rate", .metric("resp_rate")),
            (.bloodOxygen, "98", "%", nil, .hrv, "spo2", .metric("spo2")),
            (.skinTemp, "+0.3 Δ°C", nil, String(localized: "Relative to baseline"), .temp, "skin_temp", .metric("skin_temp")),
            (.calories, "643", "kcal", nil, .temp, "energy_kcal", .metricSourced(key: "active_kcal", source: "apple-health")),
        ]
        for (metric, value, unit, caption, tint, key, route) in expected {
            let result = try XCTUnwrap(TodayCardResolver.readout(metric, input))
            XCTAssertEqual(result.value, value, metric.rawValue)
            XCTAssertEqual(result.unit, unit, metric.rawValue)
            XCTAssertEqual(result.caption, caption, metric.rawValue)
            XCTAssertEqual(result.tint, tint, metric.rawValue)
            XCTAssertEqual(result.sparkKey, key, metric.rawValue)
            XCTAssertEqual(result.route, route, metric.rawValue)
            XCTAssertEqual(result.tap, .route(route), metric.rawValue)
        }
        for metric in [KeyMetric.weight, .charge, .effort, .rest] {
            XCTAssertNil(TodayCardResolver.readout(metric, input))
        }
    }

    func testTwinTilesReuseReadingsAndOnlyEnrichEmptyRowCaptions() throws {
        var input = inputs()
        input.displayDay = day(hrv: 50, rhr: 60, resp: 14, spo2: 98, skin: -0.2, steps: 6240)
        input.stepCount = 6240
        input.stepsDetail = MetricCatalog.todayStepsMetric(hasMeasuredSteps: true, hasImportedSteps: false)
        input.caloriesCount = 456
        input.hasImportedKcal = true
        input.caloriesDetail = MetricCatalog.todayCaloriesMetric(hasImportedKcal: true, hasOnDeviceKcal: false)
        for card in DashboardCard.allCases {
            guard let metric = TodayCardResolver.keyMetricTwin(for: card) else { continue }
            let row = try XCTUnwrap(TodayCardResolver.readout(metric, input))
            let tile = TodayCardResolver.readout(card, input)
            XCTAssertEqual(tile.value, row.value, card.rawValue)
            XCTAssertEqual(tile.unit, row.unit, card.rawValue)
            XCTAssertEqual(tile.tint, row.tint, card.rawValue)
            XCTAssertEqual(tile.route, row.route, card.rawValue)
            XCTAssertEqual(tile.sparkKey, row.sparkKey, card.rawValue)
            XCTAssertEqual(tile.tap, row.tap, card.rawValue)
            if row.caption != nil { XCTAssertEqual(tile.caption, row.caption, card.rawValue) }
        }
        XCTAssertNil(TodayCardResolver.readout(KeyMetric.hrv, input)?.caption)
        XCTAssertEqual(TodayCardResolver.readout(DashboardCard.hrv, input).caption, String(localized: "Last night"))
        XCTAssertEqual(TodayCardResolver.readout(DashboardCard.calories, input).caption, "Apple Health")
    }

    func testCarryIsCaptionOnlyAndNeverLeaksIntoPastDay() throws {
        var input = inputs()
        let prior = day("2026-10-27", hrv: 58, rhr: 60, resp: 15.2, spo2: 97, skin: 0.2)
        input.hrvCarry = prior
        input.restingHrCarry = prior
        input.respCarry = prior
        input.vitalsCarry = prior
        input.skinTempCarry = prior
        let stamp = TodayView.carriedCaption(priorDayKey: prior.day, todayKey: today)
        XCTAssertEqual(TodayCardResolver.readout(KeyMetric.hrv, input)?.caption,
                       String(localized: "Last: \("58 ms") · \(stamp)"))
        for card in [DashboardCard.hrv, .restingHr, .respiratory, .bloodOxygen, .skinTemp] {
            let tile = TodayCardResolver.readout(card, input)
            XCTAssertNil(tile.value)
            XCTAssertEqual(tile.caption, TodayCardResolver.readout(try XCTUnwrap(TodayCardResolver.keyMetricTwin(for: card)), input)?.caption)
        }
        input.isToday = false
        for metric in [KeyMetric.hrv, .restingHr, .respiratory, .bloodOxygen] {
            let result = try XCTUnwrap(TodayCardResolver.readout(metric, input))
            XCTAssertNil(result.value)
            XCTAssertNil(result.caption)
        }
        XCTAssertEqual(TodayCardResolver.readout(KeyMetric.skinTemp, input)?.caption, String(localized: "Relative to baseline"))
    }

    func testRespiratoryCarryFallsBackPerFieldAndOwnReadingWins() throws {
        var input = inputs()
        input.vitalsCarry = day("2026-10-28", hrv: 60)
        input.respCarry = day("2026-10-27", resp: 15.2)
        let carried = try XCTUnwrap(TodayCardResolver.readout(KeyMetric.respiratory, input))
        XCTAssertNotNil(carried.caption)
        XCTAssertNil(carried.value)
        input.displayDay = day(resp: 14.0)
        XCTAssertEqual(TodayCardResolver.readout(KeyMetric.respiratory, input)?.value, "14.0")
        XCTAssertNil(TodayCardResolver.readout(KeyMetric.respiratory, input)?.caption)
    }

    func testWhoop4AndUnresolvedDeviceSuppressOxygenValueChartAndTap() throws {
        var input = inputs()
        input.displayDay = day(spo2: 98)
        let families: [Bool?] = [true, nil]
        for family in families {
            input.activeIsWhoop4 = family
            let row = try XCTUnwrap(TodayCardResolver.readout(KeyMetric.bloodOxygen, input))
            XCTAssertNil(row.value)
            XCTAssertNil(row.unit)
            XCTAssertNil(row.sparkKey)
            XCTAssertNil(row.route)
            XCTAssertEqual(row.tap, .none)
            XCTAssertEqual(row.tint, .muted)
            XCTAssertEqual(row.caption, family == true ? String(localized: "Not measured on WHOOP 4.0")
                           : String(localized: "Not measured offline"))
            XCTAssertEqual(TodayCardResolver.readout(DashboardCard.bloodOxygen, input), row)
        }
    }

    func testSkinTemperatureKeepsDeviationFormattingAndCarryPrecedence() {
        var input = inputs()
        input.displayDay = day(skin: 1)
        input.fahrenheit = true
        XCTAssertEqual(TodayCardResolver.readout(KeyMetric.skinTemp, input)?.value, "+1.8 Δ°F")
        input.displayDay = nil
        input.vitalsCarry = day("2026-10-28", skin: 0.2)
        input.skinTempCarry = day("2026-10-27", skin: 0.7)
        let expected = TodayView.carriedCaption(priorDayKey: "2026-10-28", todayKey: today)
        XCTAssertEqual(TodayCardResolver.readout(KeyMetric.skinTemp, input)?.caption,
                       String(localized: "Last: \("+0.4 Δ°F") · \(expected)"))
    }

    func testStepsSourceCaptionPrefixChartAndSheetStayTogether() throws {
        var input = inputs()
        input.stepCount = 6240
        var result = try XCTUnwrap(TodayCardResolver.readout(KeyMetric.steps, input))
        XCTAssertEqual(result.value, "~6,240")
        XCTAssertEqual(result.caption, String(localized: "Estimated from strap"))
        XCTAssertEqual(result.sparkKey, "steps_est")
        XCTAssertEqual(result.route, .metricSourced(key: "steps_est", source: Repository.whoopSource))
        XCTAssertEqual(result.tap, .stepSources)
        input.importedStepsDay = 6240
        input.stepsDetail = MetricCatalog.todayStepsMetric(hasMeasuredSteps: false, hasImportedSteps: true)
        result = try XCTUnwrap(TodayCardResolver.readout(KeyMetric.steps, input))
        XCTAssertEqual(result.value, "6,240")
        XCTAssertEqual(result.caption, "Apple Health")
        XCTAssertEqual(result.route, .metricSourced(key: "steps", source: "apple-health"))
        input.displayDay = day(steps: 6240)
        input.stepsDetail = MetricCatalog.todayStepsMetric(hasMeasuredSteps: true, hasImportedSteps: true)
        result = try XCTUnwrap(TodayCardResolver.readout(KeyMetric.steps, input))
        XCTAssertEqual(result.caption, String(localized: "Strap"))
        XCTAssertEqual(result.route, .metricSourced(key: "steps", source: Repository.whoopSource))
        input.stepCount = nil
        XCTAssertEqual(TodayCardResolver.readout(KeyMetric.steps, input)?.caption, String(localized: "No step data for this day"))
    }

    func testLatestPointsExcludeFutureReadingsAndStalenessUsesSelectedDay() {
        let points: [(day: String, value: Double)] = [("2026-10-30", 99), ("2026-10-12", 20), ("2026-10-15", 22)]
        XCTAssertEqual(TodayCardResolver.latestPoint(points, onOrBefore: today)?.day, "2026-10-15")
        XCTAssertNil(TodayCardResolver.latestPoint(points, onOrBefore: "2026-10-01"))
        var input = inputs()
        input.fitnessAgePoint = ("2026-10-15", 20)
        let recent = TodayCardResolver.readout(DashboardCard.fitnessAge, input)
        XCTAssertEqual(recent.value, "≤20")
        XCTAssertFalse(recent.captionIsStale, "Exactly fourteen days is not stale")
        input.fitnessAgePoint = ("2026-10-14", 80)
        let stale = TodayCardResolver.readout(DashboardCard.fitnessAge, input)
        XCTAssertEqual(stale.value, "≥80")
        XCTAssertTrue(stale.captionIsStale)
        input.selectedDayKey = "2026-10-13"
        XCTAssertNil(TodayCardResolver.readout(DashboardCard.fitnessAge, input).value)
        input.vo2maxPoint = ("2026-10-12", 42.6)
        XCTAssertEqual(TodayCardResolver.readout(DashboardCard.vo2max, input).value, "42.6")
        input.vitalityPoint = ("2026-10-12", 71.8)
        XCTAssertEqual(TodayCardResolver.readout(DashboardCard.vitality, input).value, "72")
    }

    func testStressTrendUsesTheSameScaleAndUTCDateIdentity() throws {
        let model = try XCTUnwrap(StressModel(days: [day("2026-10-27"), day("2026-10-28")],
                                             stored: [("2026-10-27", 1.4), ("2026-10-28", 2.2)]))
        XCTAssertEqual(model.score, 2.2)
        XCTAssertEqual(model.fullTrend.map(\.value), [1.4, 2.2])
        XCTAssertEqual(model.fullTrend.map { TodayCardResolver.utcDayKey($0.date) }, ["2026-10-27", "2026-10-28"])
        var input = inputs()
        input.stressToday = model.score
        input.stressPoint = ("2026-10-27", 1.4)
        XCTAssertEqual(TodayCardResolver.readout(DashboardCard.stress, input).value, "2.2")
        input.isToday = false
        input.selectedDayKey = "2026-10-27"
        XCTAssertEqual(TodayCardResolver.readout(DashboardCard.stress, input).value, "1.4")
        XCTAssertEqual(TodayCardResolver.readout(DashboardCard.stress, input).caption, String(localized: "Moderate"))
        input.selectedDayKey = "2026-10-26"
        XCTAssertNil(TodayCardResolver.readout(DashboardCard.stress, input).value)
    }

    func testPastHydrationDoesNotExposeCurrentTotalAndShortcutsStayValueFree() {
        var input = inputs()
        input.hydrationTotalML = 1400
        input.hydrationGoalML = 2500
        XCTAssertNotNil(TodayCardResolver.readout(DashboardCard.hydration, input).value)
        input.isToday = false
        let hydration = TodayCardResolver.readout(DashboardCard.hydration, input)
        XCTAssertNil(hydration.value)
        XCTAssertEqual(hydration.caption, String(localized: "Logged for today only"))
        XCTAssertEqual(hydration.tap, .none)
        XCTAssertNil(hydration.route)
        let coach = TodayCardResolver.readout(DashboardCard.coach, input)
        XCTAssertNil(coach.value)
        XCTAssertEqual(coach.tap, .coachSheet)
        let coupled = TodayCardResolver.readout(DashboardCard.coupled, input)
        XCTAssertNil(coupled.value)
        XCTAssertEqual(coupled.route, .coupled)
    }

    func testSleepAndRollingAverageStayAnchoredToSelectedDay() {
        var input = inputs()
        input.displayDay = day(sleep: 425)
        XCTAssertEqual(TodayCardResolver.readout(DashboardCard.sleep, input).value, UnitFormatter.nightSleepDurationDisplay(minutes: 425))
        XCTAssertEqual(TodayCardResolver.readout(DashboardCard.sleep, input).route, .sleep)
        input.isToday = false
        XCTAssertEqual(TodayCardResolver.readout(DashboardCard.sleep, input).route, .metric("sleep_total_min"))
        input.rollingStepsAverage = RollingStepsAverage.calculate(readings: [("2026-10-28", 6000), ("2026-10-29", 8000), ("2026-10-30", 99999)], ending: today)
        let average = TodayCardResolver.readout(DashboardCard.stepsAverage30, input)
        XCTAssertEqual(average.value, "7,000")
        XCTAssertEqual(average.caption, String(localized: "\(2) of 30 days"))
        XCTAssertEqual(average.route, .metricSourced(key: "steps", source: MetricCatalog.combinedStepsSource))
    }

    func testAllRegistryCardsResolveWithoutInventingMissingValues() {
        let input = inputs()
        for card in DashboardCard.allCases {
            let result = TodayCardResolver.readout(card, input)
            XCTAssertNil(result.value, card.rawValue)
            XCTAssertNotNil(result.caption, card.rawValue)
            XCTAssertFalse(TodayCardResolver.cardTitle(card).isEmpty, card.rawValue)
        }
    }
}
