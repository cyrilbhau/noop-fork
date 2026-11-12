#if DEBUG
import SwiftUI
import StrandAnalytics
import StrandDesign

// DEBUG-only. `--demo-screen events-<frame id>` renders one stage 5 screen in one state of
// `design/round-s5-events/`, so each approved frame can be reproduced in the simulator:
//
//   events-h1 … events-h3     the Health tab's "More health" rows (H3: the feature off, no row)
//   events-l1 … events-l9     the Events screen (L6 loading; L9 asks before starting again)
//   events-l11                the Events screen at the largest text size
//   events-d1, events-d2      the delete confirmation
//   events-s1 … events-s18    the event sheet (no S2, S8, S14, S17: an open menu, an open
//                             calendar and a write in flight need a tap; S17 is packet v2's)
//   events-m2, m4, m6, m10    marks on a weekly curve, thirty day bars and a line
//   events-c1 … events-c6     the chart caption
//   events-n1 … events-n13    the scorecard with its event note
//
// Not reproduced: L10 (a swipe; the app offers Edit and Delete on a long press), G1 to G5 (the
// Settings card is drawn by Settings itself), the O options and W1 (an annotation).
//
// EVERY VALUE IS SYNTHETIC: the one Fixture Person of stage 1 §13, whose weights come from
// `ScorecardDemo.fixtureInput`, with the eight events of stage 5 §13.1. Nothing is read from or
// written to the app's own events: each state runs on its own defaults suite. Stripped from Release.

enum PersonalEventsDemo {
    static func screen(named name: String) -> AnyView? {
        guard name.hasPrefix("events-") else { return nil }
        switch name {
        case "events-h1": return AnyView(EventsDemoHealth(today: "2031-03-12", on: true))
        case "events-h2": return AnyView(EventsDemoHealth(today: "2031-01-29", on: true))
        case "events-h3": return AnyView(EventsDemoHealth(today: "2031-03-12", on: false))
        case "events-l1": return events("2031-03-12", EventsDemoFixture.all)
        case "events-l2": return events("2031-05-28", EventsDemoFixture.all)
        case "events-l3": return events("2031-05-28", EventsDemoFixture.endedToday)
        case "events-l4": return events("2031-01-08", EventsDemoFixture.upcoming)
        case "events-l5": return events("2031-03-12", [])
        case "events-l6": return events("2031-03-12", EventsDemoFixture.all, loading: true)
        case "events-l7": return events("2031-03-12", EventsDemoFixture.all, extra: [EventsDemoFixture.unknownKind])
        case "events-l8": return events("2031-03-12", nil)
        case "events-l9": return events("2031-03-12", nil, asksStartAgain: true)
        case "events-l11": return events("2031-05-28", EventsDemoFixture.all, largest: true)
        case "events-d1": return events("2031-03-12", EventsDemoFixture.all, asksDelete: EventsDemoFixture.id(1))
        case "events-d2": return events("2031-03-28", EventsDemoFixture.all, asksDelete: EventsDemoFixture.id(6))
        case "events-s1", "events-s3", "events-s4", "events-s5", "events-s6", "events-s7", "events-s9",
             "events-s10", "events-s11", "events-s12", "events-s13", "events-s15", "events-s16", "events-s18":
            return AnyView(EventsDemoSheet(frame: name))
        case "events-m2": return AnyView(EventsDemoCurve(today: "2031-01-29"))
        case "events-m4": return AnyView(EventsDemoCurve(today: "2031-03-19"))
        case "events-m6": return AnyView(EventsDemoDays(today: "2031-01-29", count: 30, line: false))
        case "events-m10": return AnyView(EventsDemoDays(today: "2031-01-29", count: 30, line: true))
        case "events-c1": return AnyView(EventsDemoDays(today: "2031-01-29", count: 30, line: false))
        case "events-c2": return AnyView(EventsDemoDays(today: "2031-02-05", count: 30, line: false))
        case "events-c3": return AnyView(EventsDemoDays(today: "2031-03-26", count: 90, line: true))
        case "events-c4": return AnyView(EventsDemoDays(today: "2031-03-28", count: 7, line: false))
        case "events-c5": return AnyView(EventsDemoDays(today: "2031-05-28", count: 7, line: false,
                                                        events: EventsDemoFixture.openIllness))
        case "events-c6": return AnyView(EventsDemoDays(today: "2031-05-28", count: 7, line: false))
        case "events-n1": return note("2031-01-29", [])
        case "events-n2": return note("2031-01-22", EventsDemoFixture.all)
        case "events-n3": return note("2031-03-12", EventsDemoFixture.all)
        case "events-n4": return note("2031-03-19", EventsDemoFixture.all)
        case "events-n5": return note("2031-03-26", EventsDemoFixture.all)
        case "events-n6": return note("2031-02-05", EventsDemoFixture.all)
        case "events-n7": return note("2031-04-23", EventsDemoFixture.all)
        case "events-n8": return note("2031-05-28", EventsDemoFixture.all)
        case "events-n9": return note("2031-04-20", EventsDemoFixture.many)
        case "events-n10": return note("2031-02-05", EventsDemoFixture.privateDeload)
        case "events-n11": return note("2031-01-08", EventsDemoFixture.all, without: Set(1...22))
        case "events-n12": return note("2031-03-19", EventsDemoFixture.all, without: [11])
        case "events-n13": return note("2031-03-26", EventsDemoFixture.all, largest: true)
        default: return nil
        }
    }

    private static func events(_ today: String, _ list: [PersonalEvent]?, extra: [[String: Any]] = [],
                               loading: Bool = false, largest: Bool = false, asksDelete: String? = nil,
                               asksStartAgain: Bool = false) -> AnyView {
        AnyView(EventsDemoList(today: today, list: list, extra: extra, loading: loading, asksDelete: asksDelete,
                               asksStartAgain: asksStartAgain)
            .dynamicTypeSize(largest ? DynamicTypeSize.accessibility5...DynamicTypeSize.accessibility5
                                     : DynamicTypeSize.xSmall...DynamicTypeSize.accessibility5))
    }

    private static func note(_ today: String, _ list: [PersonalEvent], without: Set<Int> = [],
                             largest: Bool = false) -> AnyView {
        let input = ScorecardDemo.fixtureInput(today: today, without: without)
        var context = CutScorecardPresentationContext(locale: EventsDemoFixture.british)
        context.events = list
        let shown = CutScorecardPresenter.present(CutScorecard.evaluate(input), input: input, context: context)
        return AnyView(NavigationStack {
            ScrollView {
                ScorecardContent(shown: shown, onLogWeighIn: {}, onHistory: {}, onPhase: {})
                    .padding(.bottom, NoopTheme.Layout.xl)
            }
            .background(NoopTheme.canvas.ignoresSafeArea())
            .navigationTitle(Text(verbatim: CutScorecardPresenter.cardTitle))
            .navigationBarTitleDisplayMode(.inline)
        }
        .dynamicTypeSize(largest ? DynamicTypeSize.accessibility5...DynamicTypeSize.accessibility5
                                 : DynamicTypeSize.xSmall...DynamicTypeSize.accessibility5))
    }
}

// MARK: - The fixture (stage 5 §13.1)

private enum EventsDemoFixture {
    static let utc = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0) ?? .current
    static let british = Locale(identifier: "en_GB")

    static func id(_ n: Int) -> String {
        let head = "e" + String(n, radix: 16)
        return head + String(repeating: "0", count: 16 - head.count)
    }

    private static func make(_ n: Int, _ kind: PersonalEventKind, _ start: String, _ end: String?,
                             label: String? = nil, note: String? = nil, sensitive: Bool = false) -> PersonalEvent {
        PersonalEvent(id: id(n), kind: kind, label: label, startDay: start, endDay: end, note: note,
                      sensitive: sensitive, createdAt: 999 + n)
    }

    static let all: [PersonalEvent] = [
        make(1, .travel, "2031-03-10", "2031-03-16", note: "Fixture trip"),
        make(2, .deload, "2031-02-03", "2031-02-09"),
        make(3, .dietBreak, "2031-04-14", "2031-04-27"),
        make(4, .supplementChange, "2031-01-22", "2031-01-22"),
        make(5, .illness, "2031-05-19", nil, sensitive: true),
        make(6, .custom, "2031-03-26", "2031-03-26", label: "Fixture change", note: "Fixture note", sensitive: true),
        make(7, .travel, "2030-12-01", "2030-12-07"),
        make(8, .travel, "2031-02-22", "2031-02-24"),
    ]

    /// Frame L3: the ongoing illness ended on 28 May.
    static var endedToday: [PersonalEvent] {
        all.map { $0.id == id(5) ? replaced($0, endDay: "2031-05-28") : $0 }
    }

    /// Frame L4: three planned events seen from 8 Jan.
    static var upcoming: [PersonalEvent] { all.filter { [id(1), id(3), id(5)].contains($0.id) } }

    /// Frame C5: the owner switched Private off on the ongoing illness.
    static var openIllness: [PersonalEvent] {
        all.map { $0.id == id(5) ? replaced($0, sensitive: false) : $0 }
    }

    /// Variant V9: the deload and the diet break marked private.
    static var privateDeload: [PersonalEvent] {
        all.map { $0.id == id(2) || $0.id == id(3) ? replaced($0, sensitive: true) : $0 }
    }

    /// Frame N9: three more events in week 15 beside the diet break.
    static var many: [PersonalEvent] {
        all + [
            PersonalEvent(id: "d100000000000000", kind: .deload, label: nil, startDay: "2031-04-15",
                          endDay: "2031-04-15", note: nil, sensitive: false, createdAt: 1010),
            PersonalEvent(id: "d200000000000000", kind: .travel, label: nil, startDay: "2031-04-16",
                          endDay: "2031-04-17", note: nil, sensitive: false, createdAt: 1011),
            PersonalEvent(id: "d300000000000000", kind: .supplementChange, label: nil, startDay: "2031-04-18",
                          endDay: "2031-04-18", note: nil, sensitive: false, createdAt: 1012),
        ]
    }

    /// Variant V6: an entry of a kind this version does not know.
    static let unknownKind: [String: Any] = [
        "createdAt": 1100, "id": "00000000000000ff", "kind": "somethingNew", "sensitive": false,
        "startDay": "2031-03-01", "v": 1,
    ]

    private static func replaced(_ e: PersonalEvent, endDay: String?? = .none, sensitive: Bool? = nil) -> PersonalEvent {
        PersonalEvent(id: e.id, kind: e.kind, label: e.label, startDay: e.startDay, endDay: endDay ?? e.endDay,
                      note: e.note, sensitive: sensitive ?? e.sensitive, createdAt: e.createdAt)
    }

    static func noon(_ day: String) -> Date {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        var components = DateComponents()
        components.year = parts.first
        components.month = parts.count > 1 ? parts[1] : nil
        components.day = parts.count > 2 ? parts[2] : nil
        components.hour = 12
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    /// A store over the demo's own defaults suite, holding `list` (nil: a stored value that cannot
    /// be read), with the feature on. The app's own events are never touched.
    @MainActor
    static func store(_ list: [PersonalEvent]?, extra: [[String: Any]] = [], suite: String = "noop.events.demo")
        -> PersonalEventStore {
        let defaults = UserDefaults(suiteName: suite) ?? UserDefaults()
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: PersonalEventStore.enabledKey)
        if let list {
            let elements: [Any] = list.map(element) + extra
            if let data = try? JSONSerialization.data(withJSONObject: elements, options: [.sortedKeys]) {
                defaults.set(String(decoding: data, as: UTF8.self), forKey: PersonalEventStore.itemsKey)
            }
        } else {
            defaults.set("{", forKey: PersonalEventStore.itemsKey)
        }
        return PersonalEventStore(defaults: defaults, now: { noon("2031-03-12") })
    }

    private static func element(_ e: PersonalEvent) -> [String: Any] {
        var out: [String: Any] = ["createdAt": e.createdAt, "id": e.id, "kind": e.kind.rawValue,
                                  "sensitive": e.sensitive, "startDay": e.startDay, "v": 1]
        if let end = e.endDay { out["endDay"] = end }
        if let label = e.label { out["label"] = label }
        if let note = e.note { out["note"] = note }
        return out
    }
}

// MARK: - Hosts

/// Frames L1 to L11, D1 and D2: the Events screen over the demo's own store.
private struct EventsDemoList: View {
    let today: String
    let list: [PersonalEvent]?
    let extra: [[String: Any]]
    let loading: Bool
    let asksDelete: String?
    let asksStartAgain: Bool
    @State private var built: (store: PersonalEventStore, model: PersonalEventsModel)?

    var body: some View {
        Group {
            if let built {
                NavigationStack {
                    PersonalEventsView(store: built.store, model: built.model, isLoading: loading,
                                       asksDelete: asksDelete, asksStartAgain: asksStartAgain)
                }
            } else {
                NoopTheme.canvas.ignoresSafeArea()
            }
        }
        .task {
            guard built == nil else { return }
            let store = EventsDemoFixture.store(list, extra: extra)
            let now = EventsDemoFixture.noon(today)
            built = (store, PersonalEventsModel(store: store, now: { now }, timeZone: { EventsDemoFixture.utc },
                                                locale: EventsDemoFixture.british))
        }
    }
}

/// Frames H1 to H3: the "More health" card's stage rows, with Events in its place of the one order.
private struct EventsDemoHealth: View {
    let today: String
    let on: Bool

    var body: some View {
        let store = EventsDemoFixture.store(EventsDemoFixture.all, suite: "noop.events.demo.health")
        let model = PersonalEventsModel(store: store, now: { EventsDemoFixture.noon(today) },
                                        timeZone: { EventsDemoFixture.utc }, locale: EventsDemoFixture.british)
        return NavigationStack {
            ScrollView {
                NoopGlassCard(flush: true) {
                    VStack(spacing: 0) {
                        if on { PersonalEventsHealthRowLabel(showsDivider: false, model: model) }
                        NoopListRow("Live heart rate", systemImage: "waveform.path.ecg", color: NoopTheme.heart,
                                    showsDivider: on)
                        NoopListRow("All metrics", systemImage: "square.grid.2x2", color: NoopTheme.hrv)
                    }
                }
                .padding(.horizontal, NoopTheme.Layout.gutter)
                .padding(.top, NoopTheme.Layout.l)
            }
            .background(NoopTheme.canvas.ignoresSafeArea())
        }
    }
}

/// Frames S1 to S18: the event sheet with the draft each frame describes. "Today" is 12 March 2031
/// unless the frame says otherwise.
private struct EventsDemoSheet: View {
    let frame: String
    @State private var model: PersonalEventSheetModel?

    var body: some View {
        Group {
            if let model {
                PersonalEventSheet(model: model, onDelete: { _ in })
            } else {
                NoopTheme.sheet.ignoresSafeArea()
            }
        }
        .dynamicTypeSize(frame == "events-s18" ? DynamicTypeSize.accessibility5...DynamicTypeSize.accessibility5
                                        : DynamicTypeSize.xSmall...DynamicTypeSize.accessibility5)
        .task { if model == nil { model = build() } }
    }

    @MainActor
    private func build() -> PersonalEventSheetModel {
        let fixture = EventsDemoFixture.self
        let today = frame == "events-s10" ? "2031-05-19" : "2031-03-12"
        let all = fixture.all
        let trip = all[0]
        switch frame {
        case "events-s13":
            return sheet(today, store: fixture.store(all), editing: trip)
        case "events-s15":
            // The event was deleted elsewhere: the save fails and the values stay.
            let model = sheet(today, store: fixture.store([]), editing: trip)
            model.save()
            return model
        case "events-s16":
            let model = sheet(today, store: fixture.store(nil))
            model.save()
            return model
        default:
            let model = sheet(today, store: fixture.store(all))
            switch frame {
            case "events-s3": model.setKind(.illness)
            case "events-s4":
                model.setPrivate(true)
                model.setKind(.deload)
            case "events-s5": model.setKind(.custom)
            case "events-s6":
                model.setKind(.custom)
                model.draft.label = "Fixture change"
                model.draft.start = fixture.noon("2031-03-26")
                model.draft.note = "Fixture note"
            case "events-s7", "events-s18":
                model.draft.start = fixture.noon("2031-03-10")
                model.draft.length = .until
                model.draft.end = fixture.noon("2031-03-16")
                model.draft.note = "Fixture trip"
            case "events-s9":
                model.draft.start = fixture.noon("2031-03-10")
                model.draft.length = .until
                model.draft.end = fixture.noon("2031-03-09")
            case "events-s10":
                model.setKind(.illness)
                model.draft.length = .ongoing
            case "events-s11":
                model.setKind(.dietBreak)
                model.draft.start = fixture.noon("2031-04-14")
                model.draft.length = .until
                model.draft.end = fixture.noon("2031-04-27")
            case "events-s12":
                model.draft.note = String((1...18).map { "Fixture note line \($0)." }.joined(separator: " ").prefix(252))
            default: break
            }
            return model
        }
    }

    @MainActor
    private func sheet(_ today: String, store: PersonalEventStore, editing: PersonalEvent? = nil) -> PersonalEventSheetModel {
        PersonalEventSheetModel(store: store, editing: editing, now: { EventsDemoFixture.noon(today) },
                                timeZone: { EventsDemoFixture.utc })
    }
}

/// Frames M2 and M4: the scorecard's weight curve with its event dots.
private struct EventsDemoCurve: View {
    let today: String

    var body: some View {
        let input = ScorecardDemo.fixtureInput(today: today)
        var context = CutScorecardPresentationContext(locale: EventsDemoFixture.british)
        context.events = EventsDemoFixture.all
        let shown = CutScorecardPresenter.present(CutScorecard.evaluate(input), input: input, context: context)
        return ScrollView {
            if let weight = shown.weight {
                NoopGlassCard {
                    ScorecardWeekChart(points: weight.points, firstLabel: weight.firstLabel, lastLabel: weight.lastLabel,
                                       axisMarks: .points(covered: weight.marked))
                }
                .padding(.horizontal, NoopTheme.Layout.gutter)
                .padding(.top, NoopTheme.Layout.l)
            }
        }
        .background(NoopTheme.canvas.ignoresSafeArea())
    }
}

/// Frames M6, M10 and C1 to C6: a day-axis chart ending on `today` with its dots and caption. The
/// values are a fixed synthetic wave; the dots and the caption are the chart source's.
private struct EventsDemoDays: View {
    let today: String
    let count: Int
    let line: Bool
    var events: [PersonalEvent] = EventsDemoFixture.all

    var body: some View {
        let store = EventsDemoFixture.store(events, suite: "noop.events.demo.chart")
        let source = PersonalEventChartSource(store: store, locale: EventsDemoFixture.british)
        let end = EventsDemoFixture.noon(today)
        let dates = (0..<count).map { end.addingTimeInterval(Double($0 - count + 1) * 86_400 - 43_200) }
        let keys = PersonalEventChartSource.dayKeys(utcDayStarts: dates)
        let values = (0..<count).map { 50 + 30 * sin(Double($0) / 3) }
        return ScrollView {
            NoopGlassCard {
                VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
                    if line {
                        let points = zip(dates, values).map { NoopChartPoint(date: $0, y: $1) }
                        let xs = points.map(\.x)
                        NoopLineChart(points: points, color: NoopTheme.sleep, animates: false,
                                      axisMarks: source.marks(dayKeys: keys, xs: xs,
                                                              domain: NoopLineChart.xDomain(values: xs) ?? 0...1))
                            .frame(height: 120)
                    } else {
                        NoopBarChart(values: values.map { Optional($0) },
                                     colorForValue: { NoopTheme.recoveryColor(for: $0) }, maxValue: 100,
                                     animates: false, axisMarks: source.marks(dayKeys: keys, style: .bars))
                            .frame(height: 120)
                    }
                    PersonalEventChartCaption(source.caption(dayKeys: keys))
                }
            }
            .padding(.horizontal, NoopTheme.Layout.gutter)
            .padding(.top, NoopTheme.Layout.l)
        }
        .background(NoopTheme.canvas.ignoresSafeArea())
    }
}
#endif
