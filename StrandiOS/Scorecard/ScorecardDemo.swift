#if DEBUG
import SwiftUI
import StrandAnalytics
import StrandDesign
import StrandImport
import WhoopStore

// DEBUG-only. `--demo-screen <name>` (see `DemoScreens` in StrandiOSApp.swift) renders one scorecard
// screen in one state of `design/round6-scorecard/`, so each approved frame can be reproduced in the
// simulator:
//
//   scorecard-b1 … scorecard-b27   the scorecard screen (B26 is the loading skeleton, B27 is AX5)
//   weighin-c1 … weighin-c10       the weigh-in sheet over the scorecard (no c7: see below)
//   history-d1 … history-d5        the history list (d2 is d1; swipe a row by hand)
//   phase-e1 … phase-e4            the phase and rules sheet over the scorecard
//   cards-a1 … cards-a3            the Today card tile in each state (A3 is AX5)
//
// EVERY VALUE IS SYNTHETIC: the "Fixture Person" of the stage 1 specification §13, a fictional cut
// from Mon 6 Jan 2031. Nothing is read from or written to the app's own store or settings: each
// state runs on an in-memory store and its own defaults suite. Stripped from Release.
//
// Not reproducible here: C7 (saving), which lasts only as long as a write.

enum ScorecardDemo {
    static func screen(named name: String) -> AnyView? {
        let parts = name.split(separator: "-")
        guard parts.count == 2, let letter = parts[1].first, let number = Int(parts[1].dropFirst()) else { return nil }
        switch (String(parts[0]), letter) {
        case ("scorecard", "b") where (1...27).contains(number):
            return AnyView(ScorecardDemoHost(frame: .scorecard(number)))
        case ("weighin", "c") where (1...10).contains(number) && number != 7:
            return AnyView(ScorecardDemoHost(frame: .weighIn(number)))
        case ("history", "d") where (1...5).contains(number):
            return AnyView(ScorecardDemoHost(frame: .history(number)))
        case ("phase", "e") where (1...4).contains(number):
            return AnyView(ScorecardDemoHost(frame: .phase(number)))
        case ("cards", "a") where (1...3).contains(number):
            return AnyView(ScorecardCardsDemo(frame: number))
        default:
            return nil
        }
    }
}

// MARK: - The fixture (specification §13)

private enum Fixture {
    static let utc = TimeZone(secondsFromGMT: 0) ?? .current
    static let british = Locale(identifier: "en_GB")
    static let deviceId = "scorecard-demo"

    static let phase = CutScorecardPhase(name: "Fixture cut", startDay: "2031-01-06", targetWeightKg: 94.0,
                                         rateLowPercentPerWeek: 0.40, rateHighPercentPerWeek: 1.20)
    static let parameters = CutScorecardParameters(
        rateWindowWeeks: 4, waistWindowWeeks: 2, waistMinDecreaseCm: 0.5, liftDropTolerancePercent: 5,
        liftDropShare: 0.5, liftDropConsecutiveWeeks: 3, addCaloriesKcal: 300, slowLossThresholdKgPerWeek: 0.4,
        slowLossConsecutiveWeeks: 3, reduceCarbsKcal: 250, proteinFloorGrams: 100, proteinMinDaysPerWeek: 5,
        maxWeighInAgeWeeks: 1, maxProjectionWeeks: 104, targetToleranceKg: 0)

    static let weights: [Double?] = [100.0, 99.2, 98.4, 97.6, 97.5, 97.4, 97.3, 97.2, 97.1, nil, 96.0, 95.2, 95.1,
                                     95.0, 94.9, 94.8, 94.7, 94.6, 94.5, 95.5, 94.0, 93.5]
    static let waists: [Double?] = [100.0, 99.5, 99.0, 98.5, 98.0, 97.5, 97.0, 97.0, 97.0, nil, 96.5, 96.0, 95.5,
                                    95.0, 94.5, 94.5, 94.5, 94.5, 94.5, 94.5, 94.0, 93.5]
    /// Week number to the working sets of "Fixture Press" and "Fixture Row" on that week's Monday.
    static let lifts: [Int: (Double, Double)] = [
        -1: (60, 50), 0: (60, 50), 1: (60, 50), 2: (60, 50), 3: (60, 50), 4: (60, 50), 5: (62.5, 50),
        6: (62.5, 50), 7: (62.5, 52.5), 8: (62.5, 52.5), 9: (62.5, 52.5), 16: (62.5, 52.5), 17: (57.5, 47.5),
        18: (52.5, 42.5), 19: (47.5, 40), 20: (47.5, 40), 21: (47.5, 40), 22: (50, 40),
    ]
    /// Week number to the protein of the seven days before its weigh-in, oldest first.
    static let protein: [Int: [Double?]] = [
        2: [120, 120, 120, 80, 120, 120, 120], 3: [120, 120, 120, 80, 120, 120, 120],
        4: [120, 120, 120, 80, 120, 120, 120], 5: [120, 80, 80, 120, 80, 80, 120],
        6: [120, nil, 120, nil, nil, 120, nil],
    ]

    private static let keys: DateFormatter = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = utc
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Midnight UTC of a day key.
    static func date(_ day: String) -> Date { keys.date(from: day) ?? Date(timeIntervalSince1970: 0) }

    static func at(_ day: String, _ hour: Int = 7, _ minute: Int = 0) -> Date {
        date(day).addingTimeInterval(Double(hour * 3_600 + minute * 60))
    }

    static func day(_ base: String, _ offset: Int) -> String {
        keys.string(from: date(base).addingTimeInterval(Double(offset) * 86_400))
    }

    /// The Wednesday of fixture week `week`: the weigh-in day.
    static func weighDay(_ week: Int) -> String { day("2031-01-08", 7 * (week - 1)) }

    struct Options {
        var today: String
        var phase: CutScorecardPhase? = Fixture.phase
        var parameters = Fixture.parameters
        var noLifts = false
        var without: Set<Int> = []
    }

    static func week(_ week: Int) -> Options { Options(today: weighDay(week)) }

    /// The fixture as the pure function's input, with everything up to `today`.
    static func input(_ options: Options) -> CutScorecardInput {
        var weightReadings: [CutScorecardReading] = []
        var waistReadings: [CutScorecardReading] = []
        func reading(_ day: String, _ value: Double) -> CutScorecardReading {
            CutScorecardReading(day: day, takenAt: Int(at(day).timeIntervalSince1970), value: value)
        }
        for (index, weight) in weights.enumerated() {
            let number = index + 1
            let day = weighDay(number)
            guard let weight, !options.without.contains(number), day <= options.today else { continue }
            weightReadings.append(reading(day, weight))
            if let waist = waists[index] { waistReadings.append(reading(day, waist)) }
        }
        // The extra Monday reading of week 3, which must lose to Wednesday's.
        if !options.without.contains(3), "2031-01-20" <= options.today {
            weightReadings.append(reading("2031-01-20", 98.9))
        }
        var observations: [CutScorecardLiftObservation] = []
        if !options.noLifts {
            for (number, sets) in lifts {
                let monday = day("2031-01-06", 7 * (number - 1))
                guard monday <= options.today else { continue }
                observations.append(.init(day: monday, exercise: "Fixture Press", weightKg: sets.0))
                observations.append(.init(day: monday, exercise: "Fixture Row", weightKg: sets.1))
            }
        }
        var proteinDays: [CutScorecardProteinDay] = []
        for (number, grams) in protein {
            for (index, amount) in grams.enumerated() {
                let eaten = day(weighDay(number), index - 7)
                guard let amount, eaten <= options.today else { continue }
                proteinDays.append(.init(day: eaten, grams: amount))
            }
        }
        return CutScorecardInput(weights: weightReadings, waists: waistReadings, lifts: observations,
                                 proteinDays: proteinDays, phase: options.phase, parameters: options.parameters,
                                 today: options.today)
    }

    /// A Lab Book row as the weigh-in store writes one.
    static func row(_ key: String, _ day: String, _ value: Double, unit: String? = nil,
                    source: String = "manual") -> LabMarkerRow {
        let takenAt = Int(at(day).timeIntervalSince1970)
        return LabMarkerRow(id: "\(key)-\(takenAt)-\(source.prefix(4))", deviceId: deviceId, markerKey: key,
                            category: "bodyMeasurement", day: day, takenAt: takenAt, value: value, valueText: nil,
                            unit: unit ?? (key == "weight" ? "kg" : "cm"), source: source, note: nil,
                            referenceText: nil)
    }

    /// The stored rows behind an input: its weights and waists.
    static func rows(_ input: CutScorecardInput) -> [LabMarkerRow] {
        input.weights.map { row("weight", $0.day, $0.value) } + input.waists.map { row("waist", $0.day, $0.value) }
    }

    static func stored(_ phase: CutScorecardPhase, kind: CutScorecardStoredPhase.Kind = .cut) -> CutScorecardStoredPhase {
        CutScorecardStoredPhase(kind: kind, name: phase.name, startDay: phase.startDay,
                                targetWeightKg: phase.targetWeightKg,
                                rateLowPercentPerWeek: phase.rateLowPercentPerWeek,
                                rateHighPercentPerWeek: phase.rateHighPercentPerWeek)
    }

    static func phase(startDay: String = Fixture.phase.startDay, target: Double? = 94.0,
                      low: Double = 0.40) -> CutScorecardPhase {
        CutScorecardPhase(name: "Fixture cut", startDay: startDay, targetWeightKg: target,
                          rateLowPercentPerWeek: low, rateHighPercentPerWeek: 1.20)
    }
}

// MARK: - An isolated context

private struct DemoSetup {
    var clock: Date
    var unitSystem: UnitSystem = .metric
    var locale: Locale = Fixture.british
    var phases: [CutScorecardStoredPhase] = [Fixture.stored(Fixture.phase)]
    var parameters = Fixture.parameters
    /// A stored rules string that cannot be read (frame B24).
    var unreadableRules = false
    var rows: [LabMarkerRow] = []
    /// The store's own clock, when it must differ from the screen's (frame C8: the save is refused).
    var storeClock: Date?
    /// The evaluation the scorecard shows. Nil: what the in-memory store holds.
    var evaluate: (@MainActor (String) async -> CutScorecardEvaluation)?

    @MainActor
    func context() async throws -> ScorecardContext {
        let suite = "noop.scorecard.demo"
        guard let defaults = UserDefaults(suiteName: suite) else { throw CocoaError(.featureUnsupported) }
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: CutScorecardSettings.enabledKey)
        let settings = CutScorecardSettings(defaults: defaults)
        settings.phases = phases
        settings.parameters = parameters
        if unreadableRules { defaults.set("{", forKey: CutScorecardSettings.rulesKey) }

        let store = try await WhoopStore.inMemory()
        let repository = Repository(deviceId: Fixture.deviceId)
        repository.setStoreForTesting(store)
        let clock = clock
        let storeClock = storeClock ?? clock
        let today = LocalDayWindows(timeZone: Fixture.utc).dayKey(for: clock)
        let provider = BodyMeasurementProvider(repository: repository, defaults: defaults, today: { today })
        if !rows.isEmpty { _ = try await store.upsertLabMarkers(rows) }
        await provider.refresh()
        let unitSystem = unitSystem
        let locale = locale
        let model = CutScorecardModel(repository: repository, provider: provider, settings: settings,
                                      unitSystem: { unitSystem }, now: { clock }, timeZone: { Fixture.utc },
                                      locale: { locale }, evaluate: evaluate)
        return ScorecardContext(
            model: model, settings: settings,
            weighIns: WeighInStore(repository: repository, provider: provider, timeZone: { Fixture.utc },
                                   now: { storeClock }),
            provider: provider, unitSystem: { unitSystem }, now: { clock }, timeZone: { Fixture.utc },
            locale: { locale })
    }

    /// A scorecard showing the fixture under `options`, with the same readings stored.
    static func fixture(_ options: Fixture.Options, unitSystem: UnitSystem = .metric,
                        unreadableRules: Bool = false) -> DemoSetup {
        let input = Fixture.input(options)
        return DemoSetup(clock: Fixture.at(options.today, 7, 2), unitSystem: unitSystem,
                         phases: options.phase.map { [Fixture.stored($0)] } ?? [],
                         parameters: options.parameters, unreadableRules: unreadableRules,
                         rows: Fixture.rows(input),
                         evaluate: { _ in (input: input, result: CutScorecard.evaluate(input)) })
    }

    /// Weeks 1 to 4 stored and nothing injected: the state behind frames C2 to C10 and E2.
    static func weekFive(clock: Date = Fixture.at("2031-02-05", 7, 2)) -> DemoSetup {
        DemoSetup(clock: clock, rows: Fixture.rows(Fixture.input(Fixture.week(4))))
    }
}

// MARK: - Hosts

private struct ScorecardDemoHost: View {
    enum Frame { case scorecard(Int), weighIn(Int), history(Int), phase(Int) }

    let frame: Frame
    @State private var built: Built?
    @State private var showsSheet = true

    /// What one frame needs once its context exists.
    private struct Built {
        var context: ScorecardContext
        var sheetModel: WeighInSheetModel?
        var showsCalendar = false
        var historyModel: WeighInHistoryModel?
        var loadsHistory = true
        var draft: ScorecardPhaseDraft?
    }

    private var isLargestText: Bool {
        switch frame {
        case .scorecard(27), .weighIn(10): return true
        default: return false
        }
    }

    var body: some View {
        Group {
            if let built {
                screen(built)
                    .environment(\.scorecardContextOverride, built.context)
                    .toolbarBackground(.hidden, for: .navigationBar)
            } else {
                NoopTheme.canvas.ignoresSafeArea()
            }
        }
        .dynamicTypeSize(isLargestText ? DynamicTypeSize.accessibility5...DynamicTypeSize.accessibility5
                                       : DynamicTypeSize.xSmall...DynamicTypeSize.accessibility5)
        .task {
            guard built == nil else { return }
            built = try? await build()
        }
    }

    @ViewBuilder
    private func screen(_ built: Built) -> some View {
        switch frame {
        case .scorecard:
            ScorecardScreen(context: built.context)
        case .weighIn:
            ScorecardScreen(context: built.context)
                .sheet(isPresented: $showsSheet) {
                    WeighInSheetScreen(context: built.context, model: built.sheetModel,
                                       showsCalendar: built.showsCalendar)
                }
        case .history:
            WeighInHistoryScreen(context: built.context, model: built.historyModel,
                                 loadsOnAppear: built.loadsHistory)
        case .phase:
            ScorecardScreen(context: built.context)
                .sheet(isPresented: $showsSheet) {
                    ScorecardPhaseSheet(context: built.context, draft: built.draft) {}
                }
        }
    }

    // MARK: Building one frame

    @MainActor
    private func build() async throws -> Built {
        switch frame {
        case .scorecard(let number): return Built(context: try await scorecardSetup(number).context())
        case .weighIn(let number): return try await weighIn(number)
        case .history(let number): return try await history(number)
        case .phase(let number): return try await phase(number)
        }
    }

    private func scorecardSetup(_ number: Int) -> DemoSetup {
        typealias Options = Fixture.Options
        let noLiftsLate = Options(today: "2031-02-19", phase: Fixture.phase(startDay: "2031-02-03"), noLifts: true)
        switch number {
        case 1: return .fixture(Fixture.week(4))
        case 2: return .fixture(Options(today: "2031-01-08", without: Set(1...22)))
        case 3: return .fixture(Options(today: "2031-01-29", phase: nil))
        case 4: return .fixture(Options(today: "2031-01-29", phase: Fixture.phase(startDay: "2031-02-03")))
        case 5: return .fixture(Fixture.week(1))
        case 6: return .fixture(Options(today: "2031-01-08", noLifts: true))
        case 7: return .fixture(noLiftsLate)
        case 8: return .fixture(Fixture.week(5))
        case 9: return .fixture(Fixture.week(6))
        case 10: return .fixture(Fixture.week(7))
        case 11: return .fixture(Fixture.week(9))
        case 12: return .fixture(Options(today: "2031-03-12"))
        case 13: return .fixture(Fixture.week(11))
        case 14: return .fixture(Fixture.week(13))
        case 15: return .fixture(Fixture.week(15))
        case 16: return .fixture(Fixture.week(17))
        case 17: return .fixture(Fixture.week(19))
        case 18: return .fixture(Fixture.week(20))
        case 19: return .fixture(Fixture.week(21))
        case 20: return .fixture(Options(today: "2031-03-19", without: [11]))
        case 21:
            var parameters = Fixture.parameters
            parameters.proteinFloorGrams = nil
            return .fixture(Options(today: "2031-01-29", phase: Fixture.phase(target: nil), parameters: parameters))
        case 22: return .fixture(Options(today: "2031-02-26", phase: Fixture.phase(target: 80)))
        case 23: return .fixture(Options(today: "2031-02-05", phase: Fixture.phase(target: 97), without: [5]))
        case 24: return .fixture(Fixture.week(4), unreadableRules: true)
        case 25: return .fixture(Fixture.week(4), unitSystem: .imperial)
        case 26:
            // The load never finishes: the skeleton stays.
            var setup = DemoSetup.fixture(Fixture.week(4))
            let input = Fixture.input(Fixture.week(4))
            setup.evaluate = { _ in
                try? await Task.sleep(nanoseconds: 3_600_000_000_000)
                return (input: input, result: CutScorecard.evaluate(input))
            }
            return setup
        default: return .fixture(Fixture.week(17))
        }
    }

    @MainActor
    private func weighIn(_ number: Int) async throws -> Built {
        switch number {
        case 1:
            return Built(context: try await DemoSetup(clock: Fixture.at("2031-01-08", 7, 2)).context())
        case 3:
            var built = Built(context: try await DemoSetup.weekFive().context())
            let model = built.context.sheetModel()
            model.weightText = "975"
            built.sheetModel = model
            return built
        case 4:
            var built = Built(context: try await DemoSetup.weekFive().context())
            let model = built.context.sheetModel()
            model.takenAt = Fixture.at("2031-01-16", 7, 2)
            model.weightText = "98.0"
            built.sheetModel = model
            built.showsCalendar = true
            return built
        case 5:
            return Built(context: try await DemoSetup.weekFive(clock: Fixture.at("2031-01-31", 7, 10)).context())
        case 6:
            var built = Built(context: try await DemoSetup.weekFive().context())
            let model = built.context.sheetModel()
            model.weightText = "97.5"
            model.advance()
            built.sheetModel = model
            return built
        case 8:
            // The store's clock is behind the sheet's, so the store refuses the save.
            var setup = DemoSetup.weekFive()
            setup.storeClock = Fixture.at("2031-02-05", 6, 0)
            var built = Built(context: try await setup.context())
            let model = built.context.sheetModel()
            model.weightText = "97.5"
            model.advance()
            model.waistText = "98.0"
            await model.save()
            built.sheetModel = model
            return built
        case 9:
            var setup = DemoSetup.weekFive()
            setup.unitSystem = .imperial
            setup.locale = Locale(identifier: "en_DE")
            var built = Built(context: try await setup.context())
            let model = built.context.sheetModel()
            await model.prepare()
            model.weightText = "215,0"
            built.sheetModel = model
            return built
        default:
            // C2 and C10: the last weight is offered.
            return Built(context: try await DemoSetup.weekFive().context())
        }
    }

    @MainActor
    private func history(_ number: Int) async throws -> Built {
        switch number {
        case 4:
            return Built(context: try await DemoSetup(clock: Fixture.at("2031-01-08", 7, 2)).context())
        case 5:
            return Built(context: try await DemoSetup.weekFive().context(), loadsHistory: false)
        default:
            // As it stands after the week 5 weigh-in, with a CSV import and a reading in a unit that
            // is not recognised, both dated before the phase.
            var setup = DemoSetup(clock: Fixture.at("2031-02-05", 7, 2),
                                  rows: Fixture.rows(Fixture.input(Fixture.week(5))))
            setup.rows += [
                Fixture.row("weight", "2031-01-01", 101.0, source: LabMarkerCsvImport.sourceId),
                Fixture.row("waist", "2031-01-01", 100.5, source: LabMarkerCsvImport.sourceId),
                Fixture.row("weight", "2030-12-28", 16.0, unit: "st"),
            ]
            var built = Built(context: try await setup.context())
            if number == 3 {
                let model = built.context.historyModel()
                await model.load()
                if case .loaded(let history) = model.state,
                   let extra = history.rows.first(where: { $0.day == "2031-01-20" }) {
                    model.requestDelete(extra)
                }
                built.historyModel = model
            }
            return built
        }
    }

    @MainActor
    private func phase(_ number: Int) async throws -> Built {
        switch number {
        case 1:
            return Built(context: try await DemoSetup(clock: Fixture.at("2031-01-06", 7, 2), phases: []).context())
        case 3:
            var setup = DemoSetup.weekFive()
            setup.phases = [Fixture.stored(Fixture.phase(low: 1.40))]
            return Built(context: try await setup.context())
        case 4:
            let context = try await DemoSetup.weekFive(clock: Fixture.at("2031-06-05", 7, 2)).context()
            var draft = ScorecardPhaseDraft.current(settings: context.settings, today: context.today)
                .startingNewPhase(today: context.today)
            draft.kind = .other
            draft.name = "Maintenance"
            return Built(context: context, draft: draft)
        default:
            return Built(context: try await DemoSetup.weekFive().context())
        }
    }
}

// MARK: - Today card tile

/// The Today card (frames A1 to A3) in each of its states, drawn by the tile Your cards uses.
private struct ScorecardCardsDemo: View {
    let frame: Int

    private var states: [(label: String, card: CutScorecardCard?, isToday: Bool)] {
        typealias Options = Fixture.Options
        func card(_ options: Options) -> CutScorecardCard {
            let input = Fixture.input(options)
            return CutScorecardPresenter.present(
                CutScorecard.evaluate(input), input: input,
                context: CutScorecardPresentationContext(locale: Fixture.british)).card
        }
        let overdue = card(Options(today: "2031-03-19", without: [11]))
        switch frame {
        case 1:
            return [("Verdict available", card(Fixture.week(4)), true), ("One reading", card(Fixture.week(1)), true)]
        case 3:
            return [("Verdict available", card(Fixture.week(4)), true),
                    ("Reduce carbohydrate", card(Fixture.week(9)), true), ("Overdue", overdue, true)]
        default:
            return [
                ("Loading", CutScorecardPresenter.loadingCard(), true),
                ("No cut phase", card(Options(today: "2031-01-29", phase: nil)), true),
                ("No readings", card(Options(today: "2031-01-08", without: Set(1...22))), true),
                ("One reading", card(Fixture.week(1)), true),
                ("Fewer readings than the rules need",
                 card(Options(today: "2031-02-19", phase: Fixture.phase(startDay: "2031-02-03"), noLifts: true)), true),
                ("Weigh-in due this week", card(Options(today: "2031-03-12")), true),
                ("Overdue", overdue, true),
                ("Lifts unknown, verdict withheld", card(Fixture.week(15)), true),
                ("Target reached", card(Fixture.week(21)), true),
                ("Weight rising", card(Fixture.week(20)), true),
                ("Your rule: add", card(Fixture.week(19)), true),
                ("A past day selected", nil, false),
            ]
        }
    }

    var body: some View {
        let largest = frame == 3
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: NoopTheme.Layout.cardGap, alignment: .top),
                                     count: largest ? 1 : 2),
                      spacing: NoopTheme.Layout.cardGap) {
                ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                    VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
                        if !largest { Text(verbatim: state.label).noopFont(.caption) }
                        tile(state.card, isToday: state.isToday, largest: largest)
                    }
                }
            }
            .padding(NoopTheme.Layout.gutter)
        }
        .background(NoopTheme.canvas.ignoresSafeArea())
        .dynamicTypeSize(largest ? DynamicTypeSize.accessibility5...DynamicTypeSize.accessibility5
                                 : DynamicTypeSize.xSmall...DynamicTypeSize.accessibility5)
    }

    private func tile(_ card: CutScorecardCard?, isToday: Bool, largest: Bool) -> some View {
        var inputs = TodayCardInputs()
        inputs.isToday = isToday
        inputs.locale = Fixture.british
        inputs.scorecard = card
        return YourCardTile(card: .scorecard, inputs: inputs, isAccessibilitySize: largest, loading: false,
                            refreshSequence: 0, captionMinimum: 0, onCoach: {}, onStepSources: {},
                            loadStepsAverage: { _ in nil })
    }
}
#endif
