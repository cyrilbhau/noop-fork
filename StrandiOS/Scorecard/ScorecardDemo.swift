#if DEBUG
import SwiftUI
import UserNotifications
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
//   scorecard-live                 the real screen on this simulator's own store (not synthetic:
//                                  pair it with `-noop.cutScorecardEnabled YES`)
//   flow-<step>                    one step of a scripted flow on this simulator's own store, driven
//                                  through the models the buttons call (see "Scripted flows" below).
//                                  Compiled for the simulator only: on a device it shows a message
//
// `--demo-scroll <0…1>` opens the scorecard, the weigh-in sheet and the phase sheet part-way down.
//
// EVERY VALUE IS SYNTHETIC: the "Fixture Person" of the stage 1 specification §13, a fictional cut
// from Mon 6 Jan 2031. Nothing is read from or written to the app's own store or settings: each
// state runs on an in-memory store and its own defaults suite. Stripped from Release.
//
// Not reproducible here: C7 (saving), which lasts only as long as a write.

enum ScorecardDemo {
    static func screen(named name: String) -> AnyView? {
        // The real screen on the simulator's own store and settings, to exercise the live wiring.
        if name == "scorecard-live" { return AnyView(ScorecardView()) }
        // A scripted flow step on the simulator's own store (see "Scripted flows" below).
        // The steps write to and delete from the app's own store and settings, so they are compiled
        // for the simulator only. On a device the name is still recognised, and nothing runs.
        if name.hasPrefix("flow-") {
            #if targetEnvironment(simulator)
            return AnyView(ScorecardFlowHost(step: String(name.dropFirst(5))))
            #else
            return AnyView(ScorecardFlowUnavailable())
            #endif
        }
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

    private var textSizes: ClosedRange<DynamicTypeSize> {
        isLargestText ? DynamicTypeSize.accessibility5...DynamicTypeSize.accessibility5
                      : DynamicTypeSize.xSmall...DynamicTypeSize.accessibility5
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
        .dynamicTypeSize(textSizes)
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
                    // A sheet does not take the text size of the view that presents it.
                    WeighInSheetScreen(context: built.context, model: built.sheetModel,
                                       showsCalendar: built.showsCalendar)
                        .dynamicTypeSize(textSizes)
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
        .scorecardDemoScroll()
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

// MARK: - Scripted flows (simulator verification)

#if !targetEnvironment(simulator)
/// What a `flow-` name shows on a device: a message. It reads and writes nothing.
private struct ScorecardFlowUnavailable: View {
    var body: some View {
        Text(verbatim: "Scripted flows run on the simulator only. Nothing was read or written.")
            .noopFont(.bodySmall, color: false)
            .foregroundStyle(NoopTheme.textSecondary)
            .multilineTextAlignment(.center)
            .padding(NoopTheme.Layout.gutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NoopTheme.canvas.ignoresSafeArea())
    }
}
#else
/// DEBUG-only and simulator-only. `--demo-screen flow-<step>` runs ONE step of a scripted flow through the same model
/// objects the buttons call (`WeighInSheetModel`, `WeighInHistoryModel`, `ScorecardPhaseDraft`,
/// `CutScorecardFlag`, `WeighInReminder` over a stub centre), on this simulator's OWN store and
/// settings and on the real clock, then shows the screen that step leaves behind. The store keeps
/// what a step wrote, so a flow is a sequence of launches with a screenshot after each. A step whose
/// name ends in a sheet state replays the earlier calls of its flow and stops before the write.
///
/// What each step observed is appended to `Documents/scorecard-flow.log` in the app's container.
/// This drives the models, not the controls: gestures, the keyboard, focus, sheet presentation and
/// navigation are not exercised. Every value is the synthetic fixture's. Never run it on a store
/// that holds real readings.
private struct ScorecardFlowHost: View {
    let step: String
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @State private var outcome: Outcome?
    @State private var showsSheet = true

    private enum Shown {
        case scorecard, gatedScorecard, log
        case history(WeighInHistoryModel?)
        case sheet(WeighInSheetModel, calendar: Bool)
        case phase(ScorecardPhaseDraft)
        /// Another surface of the app on the same store, for the one-number check.
        case surface(String)
    }

    /// `show-<surface>` draws the surface this tall (`--demo-tall <points>`) inside an outer scroll
    /// view, so that `--demo-scroll` can reach the part of it below the first screenful.
    private static var surfaceHeight: CGFloat {
        let arguments = CommandLine.arguments
        return arguments.firstIndex(of: "--demo-tall")
            .flatMap { arguments.indices.contains($0 + 1) ? Double(arguments[$0 + 1]) : nil }
            .map { CGFloat($0) } ?? 4_000
    }

    private struct Outcome {
        var context: ScorecardContext
        var shown: Shown
        var lines: [String]
    }

    /// A notification centre that only records, with a fixed permission.
    private final class StubCenter: WeighInReminderCenter {
        var status: UNAuthorizationStatus
        var requests: [UNNotificationRequest] = []
        init(status: UNAuthorizationStatus) { self.status = status }
        func authorizationStatus() async -> UNAuthorizationStatus { status }
        func requestAuthorization() async -> Bool { status == .authorized }
        func add(_ request: UNNotificationRequest) async {
            requests.removeAll { $0.identifier == request.identifier }
            requests.append(request)
        }
        func removePendingRequests(withIdentifiers identifiers: [String]) {
            requests.removeAll { identifiers.contains($0.identifier) }
        }
        func pendingRequests() async -> [UNNotificationRequest] { requests }
    }

    var body: some View {
        Group {
            if let outcome {
                screen(outcome)
                    .environment(\.scorecardContextOverride, outcome.context)
                    .toolbarBackground(.hidden, for: .navigationBar)
            } else {
                NoopTheme.canvas.ignoresSafeArea()
            }
        }
        .task {
            guard outcome == nil else { return }
            // The app opens its store during launch.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let context = ScorecardContext.live(repository: repo, profile: profile)
            var result = await run(context)
            result.lines += await Self.snapshot(context)
            Self.write(step, result.lines)
            outcome = result
        }
    }

    @ViewBuilder
    private func screen(_ outcome: Outcome) -> some View {
        switch outcome.shown {
        case .scorecard:
            ScorecardScreen(context: outcome.context)
        case .gatedScorecard:
            ScorecardView()
        case .history(let model):
            WeighInHistoryScreen(context: outcome.context, model: model)
        case .sheet(let model, let calendar):
            ScorecardScreen(context: outcome.context)
                .sheet(isPresented: $showsSheet) {
                    WeighInSheetScreen(context: outcome.context, model: model, showsCalendar: calendar)
                }
        case .phase(let draft):
            ScorecardScreen(context: outcome.context)
                .sheet(isPresented: $showsSheet) {
                    ScorecardPhaseSheet(context: outcome.context, draft: draft) {}
                }
        case .surface(let name):
            ScrollView {
                surface(name).frame(height: Self.surfaceHeight)
            }
            .scorecardDemoScroll()
            .background(NoopTheme.canvas.ignoresSafeArea())
        case .log:
            ScrollView {
                Text(verbatim: outcome.lines.joined(separator: "\n"))
                    .noopFont(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(NoopTheme.Layout.gutter)
            }
            .background(NoopTheme.canvas.ignoresSafeArea())
        }
    }

    @ViewBuilder
    private func surface(_ name: String) -> some View {
        switch name {
        case "today": RedesignTodayView()
        case "health": RedesignHealthView()
        case "profile": ProfileSheet(path: .constant(NavigationPath()), onClose: {})
        // The Your cards editor on the stored selection, and on a selection never edited.
        case "editor", "editor-default":
            let raw = name == "editor" ? UserDefaults.standard.string(forKey: DashboardCardPrefs.selectionKey) ?? "" : ""
            TodayCustomizationSheet(
                initialDestination: .yourCards, sectionOrderRaw: .constant(""), hiddenSectionsRaw: .constant(""),
                keyMetricsRaw: .constant(""), keyMetricsDetailed: .constant(false),
                keyMetricsWindowDays: .constant(14), dashboardCardsRaw: .constant(raw),
                hostedCardsRaw: .constant(""), redesign: true)
        default: SettingsView()
        }
    }

    // MARK: The steps

    /// 07:02 local, `offset` days from today.
    private static func at(_ offset: Int) -> Date {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: Date())) ?? Date()
        return day.addingTimeInterval(7 * 3_600 + 120)
    }

    private static func dayKey(_ offset: Int) -> String {
        LocalDayWindows(timeZone: .current).dayKey(for: at(offset))
    }

    private static func describe(_ model: WeighInSheetModel) -> [String] {
        ["sheet: step=\(model.step) phase=\(model.phase) weightText=\"\(model.weightText)\" waistText=\"\(model.waistText)\"",
         "sheet: canAdvance=\(model.canAdvance) canSave=\(model.canSave) primaryTitle=\"\(model.primaryTitle)\" offersSkip=\(model.offersSkip) canEditWaist=\(model.canEditWaist)",
         "sheet: weightHint=\"\(model.weightHint)\" waistHint=\"\(model.waistHint)\"",
         "sheet: dateNote=\(model.dateNote ?? "nil") skipNote=\(model.skipNote ?? "nil") failure=\(model.failureMessage ?? "nil")"]
    }

    /// A new weigh-in through the sheet's model, up to `stop`. 0: weight typed. 1: Next pressed and
    /// the waist typed. 2: Save (or Skip when `waist` is nil).
    @MainActor
    private func weighIn(_ context: ScorecardContext, offset: Int?, weight: String, waist: String?,
                         stop: Int, lines: inout [String]) async -> WeighInSheetModel {
        let model = context.sheetModel()
        await model.prepare()
        lines.append("prepare(): offered weightText=\"\(model.weightText)\" waistText=\"\(model.waistText)\"")
        if let offset { model.takenAt = Self.at(offset) }
        model.weightText = weight
        lines.append("typed weight \(weight)" + (offset.map { ", takenAt \(Self.dayKey($0)) 07:02" } ?? ", takenAt now"))
        if stop >= 1 {
            lines += Self.describe(model)
            model.advance()
            lines.append("advance()")
            if let waist { model.waistText = waist; lines.append("typed waist \(waist)") }
        }
        if stop >= 2 {
            lines += Self.describe(model)
            if waist != nil { await model.save(); lines.append("save()") } else { await model.skipWaist(); lines.append("skipWaist()") }
            if model.phase == .saved { await context.model.load() }
        }
        lines += Self.describe(model)
        return model
    }

    @MainActor
    private func historyRow(_ context: ScorecardContext, offset: Int, lines: inout [String])
        async -> (WeighInHistoryModel, WeighInHistoryRow?) {
        let model = context.historyModel()
        await model.load()
        guard case .loaded(let history) = model.state else { return (model, nil) }
        let row = history.rows.first { $0.day == Self.dayKey(offset) }
        lines.append("history row for \(Self.dayKey(offset)): " + (row.map {
            "\($0.dateText) weight=\($0.weightText ?? "nil") waist=\($0.waistText ?? "nil") canEdit=\($0.canEdit) canDelete=\($0.canDelete) represents=\($0.representsWeek)"
        } ?? "none"))
        return (model, row)
    }

    @MainActor
    private func run(_ context: ScorecardContext) async -> Outcome {
        var lines: [String] = []
        let flag = CutScorecardFlag.shared
        func done(_ shown: Shown) -> Outcome { Outcome(context: context, shown: shown, lines: lines) }
        if step.hasPrefix("show-") { return done(.surface(String(step.dropFirst(5)))) }
        switch step {
        case "state":
            return done(.log)
        case "scorecard":
            await context.model.load()
            return done(.scorecard)
        case "history":
            return done(.history(nil))

        // Settings switch.
        case "flag-on", "flag-off":
            lines.append("flag before: \(flag.isEnabled)")
            flag.set(step == "flag-on")
            lines.append("CutScorecardFlag.set(\(step == "flag-on")); flag after: \(flag.isEnabled); stored: \(UserDefaults.standard.bool(forKey: CutScorecardSettings.enabledKey))")
            return done(.gatedScorecard)

        // Your cards editor: the stored selection with the scorecard card first.
        case "card-add":
            let defaults = UserDefaults.standard
            let raw = defaults.string(forKey: DashboardCardPrefs.selectionKey) ?? ""
            let current = DashboardCardPrefs.decodeEnabled(raw)
            let edited = [.scorecard] + current.filter { $0 != .scorecard }
            defaults.set(DashboardCardPrefs.encode(edited), forKey: DashboardCardPrefs.selectionKey)
            lines.append("selection before: \(current.map(\.rawValue))")
            lines.append("selection after: \(DashboardCardPrefs.decodeEnabled(defaults.string(forKey: DashboardCardPrefs.selectionKey) ?? "").map(\.rawValue))")
            return done(.log)

        // First phase and rules.
        case "phase-first-open", "phase-first-save":
            var draft = ScorecardPhaseDraft.current(settings: context.settings, today: context.today)
            lines.append("draft opened: isNewPhase=\(draft.isNewPhase) name=\(draft.name) start=\(draft.startDay) target=\(String(describing: draft.targetWeightKg)) band=\(draft.rateLowPercentPerWeek)-\(draft.rateHighPercentPerWeek)")
            guard step == "phase-first-save" else { return done(.phase(draft)) }
            draft.name = Fixture.phase.name
            draft.startDay = Self.dayKey(-23)
            draft.targetWeightKg = Fixture.phase.targetWeightKg
            draft.rateLowPercentPerWeek = Fixture.phase.rateLowPercentPerWeek
            draft.rateHighPercentPerWeek = Fixture.phase.rateHighPercentPerWeek
            draft.parameters = Fixture.parameters
            lines.append("edited to the fixture: canSave=\(draft.canSave) invalid=\(draft.invalidFields.map(\.rawValue)) message=\(draft.validationMessage ?? "nil")")
            lines.append("save(to:) returned \(draft.save(to: context.settings)); stored phases: \(context.settings.phases.map { "\($0.kind.rawValue) \($0.name) \($0.startDay)" })")
            await context.model.load()
            return done(.scorecard)
        case "phase-edit-open":
            let draft = ScorecardPhaseDraft.current(settings: context.settings, today: context.today)
            lines.append("draft opened: isNewPhase=\(draft.isNewPhase) name=\(draft.name) start=\(draft.startDay)")
            return done(.phase(draft))
        case "phase-new-open", "phase-new-save":
            var draft = ScorecardPhaseDraft.current(settings: context.settings, today: context.today)
                .startingNewPhase(today: context.today)
            draft.kind = .other
            draft.name = "Maintenance"
            lines.append("startingNewPhase: isNewPhase=\(draft.isNewPhase) kind=\(draft.kind.rawValue) start=\(draft.startDay) canSave=\(draft.canSave)")
            guard step == "phase-new-save" else { return done(.phase(draft)) }
            lines.append("save(to:) returned \(draft.save(to: context.settings)); stored phases: \(context.settings.phases.map { "\($0.kind.rawValue) \($0.name) \($0.startDay)" })")
            await context.model.load()
            return done(.scorecard)

        // A weigh-in today: weight, then waist.
        case "weighin-weight":
            return done(.sheet(await weighIn(context, offset: nil, weight: "97.6", waist: "98.5", stop: 0, lines: &lines), calendar: false))
        case "weighin-waist":
            return done(.sheet(await weighIn(context, offset: nil, weight: "97.6", waist: "98.5", stop: 1, lines: &lines), calendar: false))
        case "weighin-save":
            _ = await weighIn(context, offset: nil, weight: "97.6", waist: "98.5", stop: 2, lines: &lines)
            return done(.scorecard)

        // Backdated into earlier weeks.
        case "backdate-open":
            return done(.sheet(await weighIn(context, offset: -14, weight: "99.2", waist: "99.5", stop: 0, lines: &lines), calendar: true))
        case "backdate-save":
            for (offset, weight, waist) in [(-14, "99.2", "99.5"), (-21, "100.0", "100.0"), (-7, "98.4", "99.0")] {
                _ = await weighIn(context, offset: offset, weight: weight, waist: waist, stop: 2, lines: &lines)
            }
            return done(.scorecard)

        // A weight with the waist skipped.
        case "skip-open":
            return done(.sheet(await weighIn(context, offset: -9, weight: "98.9", waist: nil, stop: 1, lines: &lines), calendar: false))
        case "skip-save":
            _ = await weighIn(context, offset: -9, weight: "98.9", waist: nil, stop: 2, lines: &lines)
            return done(.history(nil))

        // Edit a value, then a date.
        case "edit-value-open", "edit-value-save":
            let (_, row) = await historyRow(context, offset: -7, lines: &lines)
            guard let row else { return done(.log) }
            let model = context.sheetModel(editing: row)
            await model.prepare()
            lines += Self.describe(model)
            model.weightText = "98.3"
            lines.append("typed weight 98.3")
            guard step == "edit-value-save" else { lines += Self.describe(model); return done(.sheet(model, calendar: false)) }
            model.advance()
            lines.append("advance()")
            lines += Self.describe(model)
            await model.save()
            lines.append("save()")
            lines += Self.describe(model)
            if model.phase == .saved { await context.model.load() }
            return done(.history(nil))
        case "edit-date-open", "edit-date-save":
            let (_, row) = await historyRow(context, offset: -9, lines: &lines)
            guard let row else { return done(.log) }
            let model = context.sheetModel(editing: row)
            await model.prepare()
            model.takenAt = Self.at(-8)
            lines.append("takenAt moved to \(Self.dayKey(-8)) 07:02")
            lines += Self.describe(model)
            guard step == "edit-date-save" else { return done(.sheet(model, calendar: true)) }
            model.advance()
            lines.append("advance()")
            lines += Self.describe(model)
            await model.save()
            lines.append("save()")
            lines += Self.describe(model)
            if model.phase == .saved { await context.model.load() }
            return done(.history(nil))

        // Delete a reading: ask, then confirm.
        case "delete-ask", "delete-confirm":
            let (model, row) = await historyRow(context, offset: -8, lines: &lines)
            guard let row else { return done(.log) }
            model.requestDelete(row)
            let question = model.deleteConfirmation
            lines.append("requestDelete: pending=\(model.pendingDelete?.dateText ?? "nil") confirmation=\(String(describing: question))")
            guard step == "delete-confirm" else { return done(.history(model)) }
            await model.confirmDelete()
            lines.append("confirmDelete(): pending=\(model.pendingDelete?.dateText ?? "nil")")
            await context.model.load()
            return done(.history(nil))

        // The weekly reminder over a stub centre: allowed, then refused.
        case "reminder-on", "reminder-denied", "reminder-off":
            let center = StubCenter(status: step == "reminder-denied" ? .denied : .authorized)
            let reminder = WeighInReminder(center: center, settings: context.settings)
            let outcome = await reminder.setEnabled(step != "reminder-off")
            lines.append("setEnabled(\(step != "reminder-off")) with the stub centre \(step == "reminder-denied" ? "denied" : "authorized") -> \(outcome); stored switch: \(context.settings.reminderEnabled)")
            await reminder.reconcile(latestWeighInDay: WeighInReminder.latestWeighInDay(in: context.provider, today: context.today))
            lines.append("reconcile(): \(center.requests.count) pending")
            for request in center.requests {
                lines.append("pending \(request.identifier): \"\(request.content.title)\" / \"\(request.content.body)\" \((request.trigger as? UNCalendarNotificationTrigger).map { "\($0.dateComponents) repeats=\($0.repeats)" } ?? "no calendar trigger")")
            }
            return done(.log)

        default:
            lines.append("unknown flow step")
            return done(.log)
        }
    }

    // MARK: The record

    /// What the one resolver calls current after the step, and what the list holds.
    @MainActor
    private static func snapshot(_ context: ScorecardContext) async -> [String] {
        await context.provider.refresh()
        func current(_ kind: BodyMeasurementKind) -> String {
            guard let reading = context.provider.current(kind, consumer: .display) else { return "nil" }
            return "\(reading.value) from \(reading.source) on \(reading.day ?? "no day")"
        }
        var lines = ["after: flag=\(CutScorecardFlag.shared.isEnabled) today=\(context.today)",
                     "after: resolver weight (display) = \(current(.weight)); waist = \(current(.waist))"]
        let history = context.historyModel()
        await history.load()
        if case .loaded(let loaded) = history.state {
            lines.append("after: history has \(loaded.rows.count) rows")
            lines += loaded.rows.map {
                "  \($0.dateText) | \($0.weightText ?? "-") | \($0.waistText ?? "not measured") | \($0.caption) | represents=\($0.representsWeek)"
            }
        }
        return lines
    }

    private static func write(_ step: String, _ lines: [String]) {
        guard let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = folder.appendingPathComponent("scorecard-flow.log")
        let text = (["## flow-\(step)"] + lines).joined(separator: "\n") + "\n\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? Data(text.utf8).write(to: url)
        }
    }
}
#endif
#endif
