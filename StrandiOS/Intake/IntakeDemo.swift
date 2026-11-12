#if DEBUG
import SwiftUI
import StrandAnalytics
import StrandDesign

// DEBUG-only. `--demo-screen <name>` (see the demo registry in StrandiOSApp.swift) opens one state of
// `design/round-s3-intake/`, so each frame can be reproduced in the simulator:
//
//   intake-a1 … a4   the protein card: below, at and above the floor, stale
//   intake-a5        the card in every state of §10.1
//   intake-b1 … b25  the intake screen in the states of frames B1 to B25 (B15, every calories line,
//                    is b1, b9 to b14 together); intake-b26 is b1, for the largest text size (pair it
//                    with the app's text-size argument)
//   intake-d1        the quick-add sheet over this simulator's own store (simulator only: Save writes)
//   intake-e1        the Settings card over this simulator's own settings (simulator only)
//
// EVERY VALUE IS SYNTHETIC: the one Fixture Person (stage 1 specification §13, stage 3 §13.1 and
// §13.6), read on Wed 29 Jan 2031 at 15:20 UTC. The card and screen frames read and write nothing:
// they are the presenter's output for a fixed input. Stripped from Release.

enum IntakeDemo {
    static func screen(named name: String) -> AnyView? {
        guard name.hasPrefix("intake-") else { return nil }
        switch name {
        case "intake-a1": return tile(Fixture.input(grams: 95))
        case "intake-a2": return tile(Fixture.input(grams: 100))
        case "intake-a3": return tile(Fixture.input(grams: 105))
        case "intake-a4": return tile(Fixture.input(grams: 95, readAt: Fixture.staleRead))
        case "intake-a5": return AnyView(EveryCardState())
        case "intake-b1", "intake-b26": return screen(Fixture.input(grams: 95, kcal: 1_450, history: true))
        case "intake-b2": return screen(Fixture.input(grams: 100, kcal: 1_450, history: true))
        case "intake-b3": return screen(Fixture.input(grams: 105, kcal: 1_450, history: true))
        case "intake-b4": return AnyView(NavigationStack { IntakeScreenContent(snapshot: nil) })
        case "intake-b5": return screen(Fixture.input(grams: nil, source: .none, chosen: false))
        case "intake-b6": return screen(Fixture.input(grams: nil, source: .none), supplements: true)
        case "intake-b7": return screen(Fixture.input(grams: 95, kcal: 1_450, floor: nil, history: true))
        case "intake-b8": return screen(Fixture.input(grams: nil, history: true))
        case "intake-b9": return screen(Fixture.input(grams: 95, history: true))
        case "intake-b10": return screen(Fixture.input(grams: 95, kcal: 1_450, range: false, history: true))
        case "intake-b11": return screen(Fixture.input(grams: 95, kcal: 2_700, history: true))
        case "intake-b12": return screen(Fixture.input(grams: 120, kcal: 2_400, day: Fixture.day(-1), history: true))
        case "intake-b13": return screen(Fixture.input(grams: 120, kcal: 2_100, day: Fixture.day(-2), history: true))
        case "intake-b14": return screen(Fixture.input(grams: 95, kcal: 1_500, history: true), clock: Fixture.afterCutoff)
        case "intake-b16":
            var input = Fixture.input(grams: 105, kcal: 1_450, history: true)
            input.healthAppNamesOnDay = [Fixture.foodApp, Fixture.otherApp]
            return screen(input)
        case "intake-b17": return screen(Fixture.input(grams: 95, kcal: 1_450, readAt: Fixture.staleRead, history: true))
        case "intake-b18":
            var input = Fixture.input(grams: 95, kcal: 1_450, history: true)
            input.lastHealthOutcome = .failedRead
            input.lastHealthAttemptAt = Fixture.now.addingTimeInterval(-5 * 60)
            return screen(input)
        case "intake-b19":
            var input = Fixture.input(grams: nil, history: true)
            input.lastHealthOutcome = .preserved
            input.lastHealthAttemptAt = Fixture.now.addingTimeInterval(-5 * 60)
            return screen(input)
        case "intake-b20": return screen(Fixture.input(grams: 95, kcal: 1_450))
        case "intake-b21": return screen(Fixture.input(grams: 120, valueSource: .nutritionCsv, day: Fixture.day(-1), history: true))
        case "intake-b22":
            var input = Fixture.input(grams: 95, kcal: 1_450, range: false, history: true)
            input.targetsNeedAttention = true
            return screen(input)
        case "intake-b23":
            var input = Fixture.input(grams: 95, kcal: 1_450, source: .quickAdd, history: true)
            input.entries = Fixture.entries
            return screen(input)
        case "intake-b24":
            var input = Fixture.input(grams: 95, kcal: 1_450, source: .quickAdd, history: true)
            input.restoredTotal = IntakeStoredDay(day: Fixture.today, proteinGrams: 95, energyKcal: 1_450,
                                                  readAtEpochSeconds: Fixture.freshRead)
            return screen(input)
        case "intake-b25": return screen(Fixture.input(grams: nil, day: Fixture.day(-3), history: true))
        case "intake-d1":
            #if targetEnvironment(simulator)
            return AnyView(QuickAddLiveDemo())
            #else
            return nil
            #endif
        case "intake-e1":
            #if targetEnvironment(simulator)
            return AnyView(ScrollView { IntakeSettingsSection().padding(NoopTheme.Layout.gutter) }
                .background(NoopTheme.canvas.ignoresSafeArea()))
            #else
            return nil
            #endif
        default: return nil
        }
    }

    private static func tile(_ input: IntakePresenterInput) -> AnyView {
        AnyView(DemoTile(card: IntakePresenter.card(input, clock: Fixture.clock, timeZone: Fixture.zone,
                                                    locale: Fixture.british)))
    }

    private static func screen(_ input: IntakePresenterInput, clock: IntakeClock = Fixture.clock,
                               supplements: Bool = false) -> AnyView {
        let model = IntakePresenter.screen(input, clock: clock, timeZone: Fixture.zone, locale: Fixture.british)
        let rows = supplements || model.layout == .full
            ? IntakePresenter.supplementRows(questions: [Fixture.supplementQuestion],
                                             states: [Fixture.supplementQuestion: .some(true)],
                                             displayName: IntakePresenter.supplementName(question:))
            : []
        let snapshot = IntakeScreenSnapshot(model: model, supplements: rows, day: input.day, entriesDay: input.day,
                                            quickAddDays: IntakePresenter.quickAddDays(today: Fixture.today),
                                            presets: [Fixture.preset])
        return AnyView(NavigationStack { IntakeScreenContent(snapshot: snapshot) })
    }
}

// MARK: - The Fixture Person

private enum Fixture {
    static let zone = TimeZone(identifier: "UTC") ?? .current
    static let british = Locale(identifier: "en_GB")
    static let today = "2031-01-29"
    /// Wed 29 Jan 2031, 15:20 UTC.
    static let now = Date(timeIntervalSince1970: 1_927_466_400)
    static let freshRead = 1_927_465_800       // 15:10
    static let staleRead = 1_927_452_000       // 11:20
    static let floor = 100.0
    static let foodApp = "Fixture Food"
    static let otherApp = "Fixture Other"
    static let supplementQuestion = "Did you take Fixture supplement?"
    static let preset = IntakeSettings.Preset(label: "Fixture shake", proteinGrams: 30, energyKcal: 150)
    /// Stage 1 §13.2's week, oldest first: the seven days before today.
    static let week: [Double] = [120, 120, 120, 80, 120, 120, 120]

    static var clock: IntakeClock { IntakeClock(now: now, today: today, minuteOfDay: 920, dayIsOpen: true) }
    static var afterCutoff: IntakeClock {
        IntakeClock(now: now.addingTimeInterval(5 * 3600 + 20 * 60), today: today, minuteOfDay: 1_240, dayIsOpen: false)
    }

    static func day(_ offset: Int) -> String {
        CanonicalDay.number(today).map { CanonicalDay.key($0 + offset) } ?? today
    }

    static var entries: [IntakeEntry] {
        [IntakeEntry(id: UUID(uuidString: "00000000-0000-0000-0000-000000000031") ?? UUID(),
                     loggedAt: now.addingTimeInterval(-7 * 3600), day: today, proteinGrams: 30, energyKcal: 150,
                     label: preset.label),
         IntakeEntry(id: UUID(uuidString: "00000000-0000-0000-0000-000000000032") ?? UUID(),
                     loggedAt: now.addingTimeInterval(-2 * 3600), day: today, proteinGrams: 65, energyKcal: 1_300,
                     label: nil)]
    }

    static func input(grams: Double?, kcal: Double? = nil, source: IntakeSourceSetting = .appleHealth,
                      valueSource: IntakeSource? = nil, readAt: Int? = nil, day: String? = nil,
                      floor: Double? = Fixture.floor, range: Bool = true, chosen: Bool = true,
                      history: Bool = false) -> IntakePresenterInput {
        let shown = day ?? today
        var input = IntakePresenterInput(source: source, day: shown)
        input.sourceChosen = chosen
        let from = valueSource ?? (source == .quickAdd ? .quickAdd : .appleHealth)
        let time = from == .nutritionCsv ? nil : (readAt ?? freshRead)
        if grams != nil || kcal != nil {
            input.resolved = ResolvedIntakeDay(
                day: shown, protein: grams.map { ResolvedIntakeValue(value: $0, source: from, readAtEpochSeconds: time) },
                energy: kcal.map { ResolvedIntakeValue(value: $0, source: from, readAtEpochSeconds: time) })
        }
        input.floorGrams = floor
        input.targets = range
            ? IntakeTargets(proteinFloorGrams: floor, energyLowKcal: 2_400, energyHighKcal: 2_600, energyHardFloorKcal: 2_100)
            : IntakeTargets(proteinFloorGrams: floor)
        input.foodAppName = foodApp
        if from == .appleHealth, grams != nil { input.healthAppNamesOnDay = [foodApp] }
        if history {
            input.history = week.enumerated().map { index, value in
                ResolvedIntakeDay(day: Fixture.day(index - 7),
                                  protein: ResolvedIntakeValue(value: value, source: .quickAdd, readAtEpochSeconds: nil),
                                  energy: nil)
            }
        }
        return input
    }
}

// MARK: - Frames

private struct DemoTile: View {
    let card: IntakeCard

    var body: some View {
        var inputs = TodayCardInputs()
        inputs.selectedDayKey = Fixture.today
        inputs.locale = Fixture.british
        inputs.intake = card
        return YourCardTile(card: .protein, inputs: inputs, isAccessibilitySize: false, loading: false,
                            refreshSequence: 0, captionMinimum: 0, onCoach: {}, onStepSources: {},
                            loadStepsAverage: { _ in nil })
            .frame(width: 180, height: 170)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NoopTheme.canvas.ignoresSafeArea())
    }
}

/// Frame A5: the card in every state of §10.1, plus the quick-add time and the CSV caption.
private struct EveryCardState: View {
    private var cards: [IntakeCard] {
        var readFailed = Fixture.input(grams: nil)
        readFailed.lastHealthOutcome = .failedRead
        var attention = Fixture.input(grams: 95)
        attention.targetsNeedAttention = true
        let inputs: [IntakePresenterInput] = [
            Fixture.input(grams: nil, source: .none), Fixture.input(grams: 95, floor: nil), Fixture.input(grams: nil),
            Fixture.input(grams: 95), Fixture.input(grams: 100), Fixture.input(grams: 105),
            Fixture.input(grams: 95, readAt: Fixture.staleRead), readFailed,
            Fixture.input(grams: 120, day: Fixture.day(-1)), Fixture.input(grams: nil, day: Fixture.day(-1)), attention,
            Fixture.input(grams: 95, source: .quickAdd), Fixture.input(grams: 95, valueSource: .nutritionCsv),
        ]
        return inputs.map {
            IntakePresenter.card($0, clock: Fixture.clock, timeZone: Fixture.zone, locale: Fixture.british)
        } + [IntakePresenter.loadingCard()]
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: NoopTheme.Layout.cardGap) {
                ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                    DemoTile(card: card).frame(height: 170)
                }
            }
            .padding(NoopTheme.Layout.gutter)
        }
        .background(NoopTheme.canvas.ignoresSafeArea())
    }
}

#if targetEnvironment(simulator)
/// Frame D1 over the simulator's own store: Save writes a real entry there.
private struct QuickAddLiveDemo: View {
    @EnvironmentObject private var repo: Repository

    var body: some View {
        IntakeQuickAddSheet(mode: .add, store: IntakeQuickAddStore(repository: repo, settings: IntakeSettings()),
                            days: IntakePresenter.quickAddDays(today: Repository.localDayKey(Date())),
                            presets: [Fixture.preset]) {}
    }
}
#endif
#endif
