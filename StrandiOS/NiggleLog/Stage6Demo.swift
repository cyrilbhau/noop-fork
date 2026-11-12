#if DEBUG
import SwiftUI
import StrandAnalytics
import StrandDesign
import WhoopStore

// DEBUG-only. `--demo-screen <name>` renders one stage 6 screen in one state of
// `design/round-s6-niggle-timeline/`, so each frame can be reproduced in the simulator. One element
// of the demo registry, answering only its three reserved prefixes (ruling A4):
//
//   niggle-log-1 … 16         the niggle log, frames A1 … A16 (2 loading, 16 at the largest text size)
//   niggle-detail-1 … 9       the detail screen, frames B1 … B9 (8 asks before deleting)
//   niggle-sheet-1 … 7        the niggle sheet: add, add an observation, empty location, location too
//                             long, edit, add update, mark resolved (C1 … C7)
//   niggle-rules-1 … 3        the rules sheet: first use, the five rules, one rule's fields
//   niggle-paused-1 … 3       the paused-exercise sheet: add, edit, delete asks once
//   niggle-flow-live          the real log on this simulator's own store (simulator only)
//   cutstress-1 … 12          Recovery context, frames F1 … F12 (2 loading, 12 at the largest size)
//   timeline-1 … 16           the timeline, frames G1 … G16 (2 loading, 16 at the largest size)
//   timeline-sheet-1 … 8      the checkpoint sheet: add, edit done, waypoint, waypoint at the target,
//                             target date, no stored phase, not after the phase start, second target date
//   timeline-flow-live        the real timeline on this simulator's own store (simulator only)
//
// Typing, reordering, pausing, resuming and ticking are exercised by tapping in these states; the
// `-flow-live` names are the only ones that touch the app's own store, and they are compiled for the
// simulator only.
//
// EVERY VALUE IS SYNTHETIC: the one Fixture Person of stage 1 §13 (the scorecard's evaluation comes
// from `ScorecardDemo`), extended by stage 6 §13: the owner-typed rules, complaints, pauses, nights,
// checkpoints, scan days and events. Each state runs on its own defaults suite and an in-memory
// repository; scan days and events reach the timeline through the adapters' closure initialisers.
// Recovery context shows "still calibrating" for its range: a demo repository resolves no baseline.
// Stripped from Release.

enum Stage6Demo {
    static func screen(named name: String) -> AnyView? {
        guard DemoScreenPrefixes.stage6.contains(where: { name.hasPrefix($0) }) else { return nil }
        if name == "niggle-flow-live" || name == "timeline-flow-live" {
            #if targetEnvironment(simulator)
            return AnyView(NavigationStack {
                Group {
                    if name == "niggle-flow-live" { NiggleLogView() } else { CheckpointTimelineView() }
                }
                .redesignDestinations()
            })
            #else
            return nil
            #endif
        }
        let parts = name.split(separator: "-")
        guard let number = parts.last.flatMap({ Int($0) }) else { return nil }
        let kind = parts.dropLast().joined(separator: "-")
        let ranges: [String: ClosedRange<Int>] = [
            "niggle-log": 1...16, "niggle-detail": 1...9, "niggle-sheet": 1...7, "niggle-rules": 1...3,
            "niggle-paused": 1...3, "cutstress": 1...12, "timeline": 1...16, "timeline-sheet": 1...8,
        ]
        guard ranges[kind]?.contains(number) == true else { return nil }
        return AnyView(S6DemoRoot(kind: kind, number: number))
    }

    /// A fresh defaults suite for one state, with only `keys` set.
    @MainActor
    static func defaults(_ name: String, _ values: [String: Any]) -> UserDefaults {
        let suite = "noop.stage6.demo." + name
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        for (key, value) in values { defaults.set(value, forKey: key) }
        return defaults
    }

    static func host<V: View>(_ view: V, largest: Bool = false) -> AnyView {
        AnyView(NavigationStack { view.redesignDestinations() }
            .dynamicTypeSize(largest ? DynamicTypeSize.accessibility5...DynamicTypeSize.accessibility5
                                     : DynamicTypeSize.xSmall...DynamicTypeSize.accessibility5))
    }

    static let utc = TimeZone(secondsFromGMT: 0) ?? .current
    static let british = Locale(identifier: "en_GB")

    /// 12:00 UTC of a day key.
    static func noon(_ day: String) -> Date {
        Stage6DayPicker.date(forDay: day, timeZone: utc) ?? Date(timeIntervalSince1970: 0)
    }
}

/// Builds one state's screen once, on the main actor, where its models live.
private struct S6DemoRoot: View {
    let kind: String
    let number: Int
    @State private var built: AnyView?

    var body: some View {
        Group {
            if let built { built } else { NoopTheme.canvas.ignoresSafeArea() }
        }
        .onAppear { if built == nil { built = make() } }
    }

    private func make() -> AnyView {
        switch kind {
        case "niggle-log": return S6NiggleDemo.log(number)
        case "niggle-detail": return S6NiggleDemo.detail(number)
        case "niggle-sheet": return S6NiggleDemo.sheet(number)
        case "niggle-rules": return S6NiggleDemo.rules(number)
        case "niggle-paused": return S6NiggleDemo.paused(number)
        case "cutstress": return S6CutStressDemo.screen(number)
        case "timeline": return S6TimelineDemo.screen(number)
        default: return S6TimelineDemo.sheet(number)
        }
    }
}

// MARK: - The fixture (stage 6 §13)

private enum S6Fixture {
    static func rule(_ letter: String, _ action: NiggleAction, characters: [NiggleCharacter] = [],
                     trends: [NiggleTrend] = [], weakness: Bool? = nil, from: Int, through: Int? = nil) -> StoredTriageRule {
        StoredTriageRule(id: "r-0000000\(letter)", label: "Fixture label \(letter.uppercased())", action: action,
                         characters: characters, trends: trends, weakness: weakness, fromDay: from, throughDay: through,
                         note: "Fixture rule note \(letter.uppercased())")
    }

    static let rules = StoredTriageRules(professionalRule: "Fixture rule text.", rules: [
        rule("a", .watch, characters: [.diffuse], trends: [.easing], from: 1, through: 10),
        rule("b", .modify, characters: [.positional], from: 5),
        rule("c", .seeProfessional, from: 30),
        rule("d", .seeProfessional, trends: [.worsening], from: 20),
        rule("e", .modify, characters: [.localised], weakness: true, from: 1),
    ])

    static func complaint(_ n: Int, _ location: String, _ side: StoredNiggle.Side, _ character: NiggleCharacter,
                          _ trend: NiggleTrend, weakness: Bool = false, onset: String, resolved: String? = nil,
                          updates: [StoredNiggleUpdate] = [], note: String = "") -> StoredNiggle {
        StoredNiggle(id: "n-0000000\(n)", kind: .complaint, location: location, side: side, character: character,
                     onsetDay: onset, resolvedDay: resolved, trend: trend, weakness: weakness, updates: updates, note: note)
    }

    static let entries: [StoredNiggle] = [
        complaint(1, "Fixture location A", .left, .diffuse, .easing, onset: "2031-02-03", resolved: "2031-02-12"),
        complaint(2, "Fixture location B", .right, .positional, .unchanged, onset: "2031-03-03",
                  updates: [StoredNiggleUpdate(seq: 1, day: "2031-03-22", trend: .worsening, weakness: false, note: "")],
                  note: "Fixture note"),
        complaint(3, "Fixture location C", .both, .localised, .unchanged, weakness: true, onset: "2031-04-07"),
        StoredNiggle(id: "n-00000004", kind: .observation, location: "Fixture observation", side: .notApplicable,
                     character: .other, onsetDay: "2031-01-13", resolvedDay: nil, trend: .notRecorded, weakness: false,
                     updates: [], note: "Fixture observation note"),
        complaint(5, "Fixture location D", .right, .diffuse, .notRecorded, onset: "2031-05-05"),
        complaint(6, "Fixture location E", .left, .diffuse, .easing, onset: "2031-06-02"),
        complaint(7, "Fixture location B", .right, .positional, .unchanged, onset: "2031-06-16"),
    ]

    static let paused = [
        StoredPausedExercise(id: "p-00000001", exercise: "Fixture Press", reason: "Fixture reason A",
                             until: "Fixture until text", pausedDay: "2031-03-10", niggleId: "n-00000002", resumedDay: nil),
        StoredPausedExercise(id: "p-00000002", exercise: "Fixture Row", reason: "Fixture reason B", until: nil,
                             pausedDay: "2031-01-20", niggleId: nil, resumedDay: "2031-02-10"),
    ]

    static let checkpoints = [
        StoredCheckpoint(id: "c-000000a1", title: "Fixture waypoint", category: .weightWaypoint, day: "2031-03-19",
                         approximate: true, done: false, waypointWeightKg: 96.0, phaseStartDay: nil),
        StoredCheckpoint(id: "c-000000a2", title: "Fixture panel", category: .bloodPanel, day: "2031-02-10",
                         approximate: false, done: true, waypointWeightKg: nil, phaseStartDay: nil),
        StoredCheckpoint(id: "c-000000a3", title: "Fixture second scan", category: .scan, day: "2031-03-17",
                         approximate: false, done: false, waypointWeightKg: nil, phaseStartDay: nil),
        StoredCheckpoint(id: "c-000000a4", title: "Fixture benchmark", category: .benchmark, day: "2031-02-05",
                         approximate: false, done: false, waypointWeightKg: nil, phaseStartDay: nil),
        StoredCheckpoint(id: "c-000000a5", title: "Fixture target date", category: .targetDate, day: "2031-06-02",
                         approximate: false, done: false, waypointWeightKg: nil, phaseStartDay: "2031-01-06"),
    ]

    static let phases = [
        CutScorecardStoredPhase(kind: .cut, name: "Fixture cut", startDay: "2031-01-06", targetWeightKg: 94.0,
                                rateLowPercentPerWeek: 0.40, rateHighPercentPerWeek: 1.20),
        CutScorecardStoredPhase(kind: .other, name: "Fixture hold", startDay: "2031-06-16", targetWeightKg: nil,
                                rateLowPercentPerWeek: 0.40, rateHighPercentPerWeek: 1.20),
    ]

    static let scanDays = ["2031-01-08", "2031-03-17"]

    static let events = [
        PersonalEvent(id: "e100000000000000", kind: .deload, label: nil, startDay: "2031-02-17", endDay: "2031-02-23",
                      note: nil, sensitive: false, createdAt: 1000),
        PersonalEvent(id: "e200000000000000", kind: .deload, label: nil, startDay: "2031-04-07", endDay: "2031-04-13",
                      note: "Fixture note", sensitive: true, createdAt: 1001),
        PersonalEvent(id: "e300000000000000", kind: .dietBreak, label: nil, startDay: "2031-03-24", endDay: nil,
                      note: nil, sensitive: false, createdAt: 1002),
        PersonalEvent(id: "e400000000000000", kind: .travel, label: nil, startDay: "2031-05-05", endDay: "2031-05-09",
                      note: "Fixture trip", sensitive: false, createdAt: 1003),
    ]

    /// The stored shape of each list, written through the stores themselves.
    @MainActor
    static func seed(_ defaults: UserDefaults, entries: [StoredNiggle], rules: StoredTriageRules?,
                     paused: [StoredPausedExercise]) {
        let settings = NiggleLogSettings(defaults: defaults, today: { "9999-12-31" })
        for entry in entries { settings.save(entry) }
        if let rules { settings.saveRules(rules) }
        for pause in paused { settings.save(pause) }
    }
}

// MARK: - Niggle log

@MainActor
private enum S6NiggleDemo {
    /// A model over a fresh suite seeded with the entries onset by `today`.
    static func model(_ name: String, today: String, entries: [StoredNiggle] = S6Fixture.entries,
                      rules: StoredTriageRules? = S6Fixture.rules, paused: [StoredPausedExercise] = S6Fixture.paused,
                      unreadable: [String] = []) -> NiggleLogModel {
        let defaults = Stage6Demo.defaults(name, [NiggleLogSettings.enabledKey: true])
        S6Fixture.seed(defaults, entries: entries.filter { $0.onsetDay <= today }.map { entry in
            var e = entry
            if let resolved = e.resolvedDay, resolved > today { e.resolvedDay = nil }
            return e
        }, rules: rules, paused: paused.filter { $0.pausedDay <= today })
        for key in unreadable { defaults.set("not json", forKey: key) }
        let now = Stage6Demo.noon(today)
        return NiggleLogModel(settings: NiggleLogSettings(defaults: defaults, today: { today }), now: { now },
                              timeZone: { Stage6Demo.utc }, locale: { Stage6Demo.british })
    }

    static func log(_ n: Int) -> AnyView {
        let name = "niggle-log-\(n)"
        let only = { (ids: [Int]) in S6Fixture.entries.filter { e in ids.contains { e.id == "n-0000000\($0)" } } }
        switch n {
        case 1: return Stage6Demo.host(NiggleLogView(model: model(name, today: "2031-03-22"), followsFlag: false))
        case 2: return Stage6Demo.host(NiggleLogView(model: model(name, today: "2031-03-22"), isLoading: true,
                                                     followsFlag: false))
        case 3: return Stage6Demo.host(NiggleLogView(model: model(name, today: "2031-03-22", entries: [], rules: nil,
                                                                  paused: []), followsFlag: false))
        case 4: return Stage6Demo.host(NiggleLogView(model: model(name, today: "2031-03-22", rules: nil),
                                                     followsFlag: false))
        case 5:
            var rules = S6Fixture.rules
            rules.professionalRule = ""
            return Stage6Demo.host(NiggleLogView(model: model(name, today: "2031-03-22", rules: rules), followsFlag: false))
        case 6: return Stage6Demo.host(NiggleLogView(model: model(name, today: "2031-05-14", entries: only([5])),
                                                     followsFlag: false))
        case 7: return Stage6Demo.host(NiggleLogView(model: model(name, today: "2031-06-11", entries: only([6])),
                                                     followsFlag: false))
        case 8: return Stage6Demo.host(NiggleLogView(model: model(name, today: "2031-06-16", entries: only([2, 7])),
                                                     followsFlag: false))
        case 9, 10, 11, 15:
            return Stage6Demo.host(NiggleLogView(model: model(name, today: "2031-06-16"), followsFlag: false))
        case 12: return Stage6Demo.host(NiggleLogView(model: model(name, today: "2031-02-05", paused: []),
                                                      followsFlag: false))
        case 13: return Stage6Demo.host(NiggleLogView(model: model(name, today: "2031-03-22",
                                                                   unreadable: [NiggleLogSettings.entriesKey]),
                                                      followsFlag: false))
        case 14: return Stage6Demo.host(NiggleLogView(model: model(name, today: "2031-03-22",
                                                                   unreadable: [NiggleLogSettings.rulesKey]),
                                                      followsFlag: false))
        default: return Stage6Demo.host(NiggleLogView(model: model(name, today: "2031-06-16"), followsFlag: false),
                                        largest: true)
        }
    }

    static func detail(_ n: Int) -> AnyView {
        let name = "niggle-detail-\(n)"
        let (id, today): (String, String)
        var rules: StoredTriageRules? = S6Fixture.rules
        var unreadable: [String] = []
        switch n {
        case 2: (id, today) = ("n-00000005", "2031-05-14")
        case 3: (id, today) = ("n-00000002", "2031-03-22"); rules = nil
        case 4: (id, today) = ("n-00000002", "2031-03-22"); unreadable = [NiggleLogSettings.rulesKey]
        case 5: (id, today) = ("n-00000001", "2031-03-01")
        case 6: (id, today) = ("n-00000004", "2031-03-22")
        case 7: (id, today) = ("n-00000002", "2031-03-21")
        default: (id, today) = ("n-00000002", "2031-03-22")
        }
        // N2c (frame B7): the stored update is dated after this day, so it is kept, shown and not used.
        let m = model(name, today: today, rules: rules, unreadable: unreadable)
        return Stage6Demo.host(NiggleDetailView(niggleId: id, model: m, asksDelete: n == 8, followsFlag: false),
                               largest: n == 9)
    }

    static func sheet(_ n: Int) -> AnyView {
        let m = model("niggle-sheet-\(n)", today: "2031-03-22")
        let entry = S6Fixture.entries[1]
        return AnyView(S6SheetHost(load: { await m.load() }) {
            switch n {
            case 2:
                NiggleSheet(model: m, mode: .edit(StoredNiggle(id: "", kind: .observation, location: "", side: .notApplicable,
                                                               character: .other, onsetDay: "2031-03-22", resolvedDay: nil,
                                                               trend: .notRecorded, weakness: false, updates: [], note: "")))
            case 3:
                NiggleSheet(model: m, mode: .edit(StoredNiggle(id: "", kind: .complaint, location: " ", side: .left,
                                                               character: .diffuse, onsetDay: "2031-03-22", resolvedDay: nil,
                                                               trend: .notRecorded, weakness: false, updates: [], note: "")))
            case 4:
                NiggleSheet(model: m, mode: .edit(StoredNiggle(id: "", kind: .complaint,
                                                               location: String(repeating: "Fixture ", count: 9),
                                                               side: .left, character: .diffuse, onsetDay: "2031-03-22",
                                                               resolvedDay: nil, trend: .notRecorded, weakness: false,
                                                               updates: [], note: "")))
            case 5: NiggleSheet(model: m, mode: .edit(entry))
            case 6: NiggleSheet(model: m, mode: .update(entry))
            case 7: NiggleSheet(model: m, mode: .resolve(entry))
            default: NiggleSheet(model: m, mode: .add)
            }
        })
    }

    static func rules(_ n: Int) -> AnyView {
        let m = model("niggle-rules-\(n)", today: "2031-03-22", rules: n == 1 ? nil : S6Fixture.rules)
        return AnyView(S6SheetHost(load: { await m.load() }) {
            NiggleRulesSheet(model: m, editing: n == 3 ? 0 : nil)
        })
    }

    static func paused(_ n: Int) -> AnyView {
        let m = model("niggle-paused-\(n)", today: "2031-03-22")
        return AnyView(S6SheetHost(load: { await m.load() }) {
            PausedExerciseSheet(model: m, editing: n == 1 ? nil : S6Fixture.paused[0], asksDelete: n == 3)
        })
    }
}

/// Loads a model before showing the sheet that reads it.
private struct S6SheetHost<Content: View>: View {
    let load: () async -> Void
    @ViewBuilder let content: () -> Content
    @State private var ready = false

    var body: some View {
        Group {
            if ready { content() } else { NoopTheme.sheet.ignoresSafeArea() }
        }
        .task {
            await load()
            ready = true
        }
    }
}

// MARK: - Recovery context

@MainActor
private enum S6CutStressDemo {
    /// The nights of §13.3, plus the three that change only the counters.
    static let nights: [(String, Int?, Double?)] = {
        func run(_ first: String, _ count: Int) -> [String] {
            (0..<count).map { CanonicalDay.key(CanonicalDay.number(first)! + $0) }
        }
        var out: [(String, Int?, Double?)] = []
        out += run("2031-01-06", 7).map { ($0, 60, 50) }
        out += run("2031-01-13", 4).map { ($0, 61, 48) }
        out += run("2031-01-20", 3).map { ($0, 62, 47) }
        out += zip(run("2031-01-27", 7), zip([63, 63, 64, 64, 65, 65, 66], [46, 46, 45, 45, 44, 44, 43]))
            .map { ($0.0, $0.1.0, Double($0.1.1)) }
        out += run("2031-02-03", 3).map { ($0, 64, 45) }
        out.append(("2031-01-17", 500, nil))
        out.append(("2030-12-30", 60, 50))
        return out
    }()

    static func screen(_ n: Int) -> AnyView {
        var today = "2031-02-05"
        var phases = [S6Fixture.phases[0]]
        var keep: (String) -> Bool = { _ in true }
        var rhr = true
        switch n {
        case 3: today = "2031-01-16"
        case 4: today = "2031-02-02"
        case 5: today = "2031-01-14"; keep = { $0 <= "2031-01-12" }
        case 6: today = "2031-01-10"; keep = { $0 <= "2031-01-08" }
        case 7: keep = { _ in false }
        case 9: rhr = false
        case 10: phases = []
        case 11: today = "2031-02-26"
        default: break
        }
        let defaults = Stage6Demo.defaults("cutstress-\(n)", [CutStressModel.enabledKey: true,
                                                               CutScorecardSettings.enabledKey: true])
        let settings = CutScorecardSettings(defaults: defaults)
        settings.phases = phases
        let repo = Repository(deviceId: "stage6-demo")
        repo.days = nights.filter { keep($0.0) && $0.0 <= today }.map { night in
            DailyMetric(day: night.0, totalSleepMin: 420, efficiency: 0.9, deepMin: nil, remMin: nil, lightMin: nil,
                        disturbances: nil, restingHr: rhr ? night.1 : nil, avgHrv: night.2, recovery: nil, strain: nil,
                        exerciseCount: nil, sleepHrOnly: nil)
        }
        let now = Stage6Demo.noon(today)
        let model = CutStressModel(repository: repo, scorecardSettings: settings, defaults: defaults, now: { now },
                                   timeZone: { Stage6Demo.utc }, locale: { Stage6Demo.british })
        return Stage6Demo.host(CutStressView(model: model, isLoading: n == 2).environmentObject(repo), largest: n == 12)
    }
}

// MARK: - Timeline

@MainActor
private enum S6TimelineDemo {
    struct Options {
        var today = "2031-02-05"
        var phases = S6Fixture.phases
        var checkpoints = S6Fixture.checkpoints
        var scanDays = S6Fixture.scanDays
        var events = [S6Fixture.events[0], S6Fixture.events[2]]
        var scans = TimelineSourceState.on
        var eventsState = TimelineSourceState.on
        var scorecard = true
        var unreadable: [String] = []
    }

    static func model(_ name: String, _ o: Options) -> CheckpointTimelineModel {
        let defaults = Stage6Demo.defaults(name, [CheckpointTimelineSettings.enabledKey: true,
                                                  CutScorecardSettings.enabledKey: o.scorecard])
        let scorecardSettings = CutScorecardSettings(defaults: defaults)
        scorecardSettings.phases = o.phases
        let settings = CheckpointTimelineSettings(defaults: defaults)
        for checkpoint in o.checkpoints { _ = settings.save(checkpoint, phases: []) }
        for key in o.unreadable { defaults.set("not json", forKey: key) }
        let repo = Repository(deviceId: "stage6-demo")
        let today = o.today
        let now = Stage6Demo.noon(today)
        let provider = BodyMeasurementProvider(repository: repo, defaults: defaults, today: { today })
        let scorecard = CutScorecardModel(repository: repo, provider: provider, settings: scorecardSettings,
                                          unitSystem: { .metric }, now: { now }, timeZone: { Stage6Demo.utc },
                                          locale: { Stage6Demo.british },
                                          evaluate: { day in ScorecardDemo.fixtureEvaluation(today: day) })
        let scanDays = o.scanDays, events = o.events
        let scans = o.scans == .notBuilt ? TimelineScanSource.notBuilt : TimelineScanSource(
            state: { o.scans },
            scans: { scanDays.enumerated().map { index, day in
                BodyScan(id: BodyScan.id(source: "body-scan-demo", takenAt: 1_925_000_000 + index), source: "body-scan-demo",
                         takenAt: 1_925_000_000 + index, day: day, values: [:], rows: [:], note: nil,
                         unreadableKeys: [], conflictingKeys: [])
            } })
        let eventSource = o.eventsState == .notBuilt ? TimelineEventSource.notBuilt
            : TimelineEventSource(state: { o.eventsState }, events: { events })
        return CheckpointTimelineModel(settings: settings, scorecardSettings: scorecardSettings, scorecard: scorecard,
                                       scans: scans, events: eventSource, now: { now }, timeZone: { Stage6Demo.utc },
                                       locale: { Stage6Demo.british }, unitSystem: { .metric })
    }

    static func screen(_ n: Int) -> AnyView {
        var o = Options()
        switch n {
        case 3: o.phases = []; o.checkpoints = []; o.scanDays = []; o.events = []; o.scorecard = true
        case 4: o.today = "2031-03-24"
        case 5: o.today = "2031-02-20"
        case 6: o.phases[0].targetWeightKg = 96.0
        case 7: o.phases = [S6Fixture.phases[1]]
        case 8: o.today = "2031-02-20"; o.eventsState = .off; o.scorecard = false
        case 9: o.scans = .off
        case 10: o.scans = .notBuilt; o.eventsState = .notBuilt
        case 12: o.today = "2031-04-10"; o.events = S6Fixture.events
        case 13: o.unreadable = [CheckpointTimelineSettings.checkpointsKey]
        case 14: o.unreadable = [CutScorecardSettings.phasesKey]
        case 15:
            o.checkpoints = (0..<CheckpointTimelineSettings.maxCheckpoints).map { index in
                var c = S6Fixture.checkpoints[3]
                c.id = ""
                c.title = "Fixture benchmark \(index + 1)"
                c.day = CanonicalDay.key(CanonicalDay.number("2031-02-05")! + index)
                return c
            }
        default: break
        }
        let model = model("timeline-\(n)", o)
        return Stage6Demo.host(CheckpointTimelineView(model: model, isLoading: n == 2), largest: n == 16)
    }

    static func sheet(_ n: Int) -> AnyView {
        var o = Options()
        if n == 6 { o.phases = [] }
        let model = model("timeline-sheet-\(n)", o)
        func draft(_ category: TimelineCheckpointCategory, day: String, weight: Double? = nil, phase: String? = nil,
                   done: Bool = false) -> StoredCheckpoint {
            StoredCheckpoint(id: "", title: "Fixture checkpoint", category: category, day: day, approximate: false,
                             done: done, waypointWeightKg: weight, phaseStartDay: phase)
        }
        let editing: StoredCheckpoint?
        switch n {
        case 2: editing = S6Fixture.checkpoints[3]
        case 3: editing = draft(.weightWaypoint, day: "2031-03-19", weight: 96.0)
        case 4: editing = draft(.weightWaypoint, day: "2031-03-19", weight: 94.0)
        case 5: editing = draft(.targetDate, day: "2031-06-30", phase: "2031-01-06")
        case 6: editing = draft(.targetDate, day: "2031-06-30")
        case 7: editing = draft(.targetDate, day: "2031-01-06", phase: "2031-01-06")
        case 8: editing = draft(.targetDate, day: "2031-05-01", phase: "2031-01-06")
        default: editing = nil
        }
        return AnyView(S6SheetHost(load: { await model.load() }) {
            CheckpointSheet(model: model, editing: editing, onEditPhase: {})
        })
    }
}
#endif
