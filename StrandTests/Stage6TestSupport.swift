// API ASSUMED BY THESE TESTS
//
// Written from docs/personal/superapp/specs/stage-6.md (§5, §8.3, §8.4, §9, §10, §11, §12.3, §13),
// RULINGS-ADDENDUM.md (A1 to A21) and stage-1.md §18, before the implementation exists. This is the
// one API block every stage 6 app-target test file refers to. Pure types (`NiggleTriage*`,
// `CutStress*`, `CheckpointTimeline*`, `Timeline*`) are used exactly as merged in StrandAnalytics.
//
// Strand/Data/NiggleLogSettings.swift (§9.2):
//
//     struct StoredNiggleUpdate: Equatable { var seq: Int; var day: String; var trend: NiggleTrend
//                                            var weakness: Bool; var note: String }
//     struct StoredNiggle: Equatable, Identifiable {
//         enum Kind: String, CaseIterable { case complaint, observation }
//         enum Side: String, CaseIterable { case left, right, both, notApplicable }
//         var id: String                  // "n-<8 lowercase hex>"; empty in a draft, issued on save
//         var kind: Kind; var location: String; var side: Side; var character: NiggleCharacter
//         var onsetDay: String; var resolvedDay: String?; var trend: NiggleTrend; var weakness: Bool
//         var updates: [StoredNiggleUpdate]; var note: String
//     }
//     struct StoredTriageRule: Equatable, Identifiable {
//         var id: String; var label: String; var action: NiggleAction; var characters: [NiggleCharacter]
//         var trends: [NiggleTrend]; var weakness: Bool?; var fromDay: Int?; var throughDay: Int?
//         var note: String
//         var triageRule: NiggleTriageRule { get }
//     }
//     struct StoredTriageRules: Equatable { var professionalRule: String; var rules: [StoredTriageRule] }
//     struct StoredPausedExercise: Equatable, Identifiable {
//         var id: String; var exercise: String; var reason: String; var until: String?
//         var pausedDay: String; var niggleId: String?; var resumedDay: String?
//     }
//     final class NiggleLogSettings {
//         static let enabledKey = "noop.niggleLogEnabled"
//         static let entriesKey = "niggleLog.entries"; static let rulesKey = "niggleLog.rules"
//         static let pausedKey = "niggleLog.paused"
//         @MainActor static let flag: ObservableDefaultsFlag      // ObservableDefaultsFlag(key: enabledKey)
//         init(defaults: UserDefaults = .standard, today: @escaping () -> String = <local day of now>)
//         var isEnabled: Bool { get }
//         var entries: [StoredNiggle] { get };              var entriesNeedAttention: Bool { get }
//         var rules: StoredTriageRules { get };             var rulesNeedAttention: Bool { get }
//         var paused: [StoredPausedExercise] { get };       var pausedNeedAttention: Bool { get }
//         @discardableResult func save(_ niggle: StoredNiggle) -> Bool
//         @discardableResult func delete(niggleId: String) -> Bool
//         @discardableResult func resolve(niggleId: String, on day: String) -> Bool
//         @discardableResult func reopen(niggleId: String) -> Bool
//         @discardableResult func addUpdate(niggleId: String, day: String, trend: NiggleTrend,
//                                           weakness: Bool, note: String) -> Bool
//         @discardableResult func deleteUpdate(niggleId: String, seq: Int) -> Bool
//         @discardableResult func saveRules(_ rules: StoredTriageRules) -> Bool
//         @discardableResult func save(_ paused: StoredPausedExercise) -> Bool
//         @discardableResult func resume(pausedId: String, on day: String) -> Bool
//         @discardableResult func delete(pausedId: String) -> Bool
//         @discardableResult func discardUnreadableEntries() -> Bool
//         @discardableResult func discardUnreadableRules() -> Bool
//         @discardableResult func discardUnreadablePaused() -> Bool
//     }
//
// Strand/Data/NiggleLogPresenter.swift and NiggleLogModel.swift (§10.2, §10.3, §11):
//
//     struct NiggleLogHealthRow: Equatable { var title: String; var detail: String? }
//     struct NiggleOpenRow: Equatable, Identifiable {
//         var id: String; var location: String; var sideText: String; var dayCountText: String
//         var label: String?; var actionText: String?; var disclaimer: String?
//         var triageLine: String?; var nextChangeLine: String?; var recurrenceText: String?
//     }
//     struct NigglePausedRow: Equatable, Identifiable {
//         var id: String; var exercise: String; var reason: String; var sinceText: String
//         var untilText: String?; var resumedText: String?; var niggleId: String?
//     }
//     struct NiggleObservationRow: Equatable, Identifiable {
//         var id: String; var location: String; var sideText: String; var note: String; var notedText: String
//     }
//     struct NiggleResolvedRow: Equatable, Identifiable {
//         var id: String; var location: String; var sideText: String; var durationText: String; var datesText: String
//     }
//     struct NiggleLogPresentation: Equatable {
//         enum State: Equatable { case firstUse, list, entriesNeedAttention }
//         var state: State
//         var professionalRule: String?          // the owner's text, verbatim; nil when none is written
//         var professionalNotice: String?        // "No rules entered yet" / "You have not written a rule …"
//         var open: [NiggleOpenRow]; var paused: [NigglePausedRow]; var resumed: [NigglePausedRow]
//         var observations: [NiggleObservationRow]; var resolved: [NiggleResolvedRow]
//         var entriesAttentionText: String?; var rulesAttentionText: String?
//         var canAdd: Bool; var limitText: String?
//         var logTitle: String?                  // "Log a niggle" on first use
//         var setUpRulesTitle: String?           // "Set up your rules" while no rule is entered
//         var discardTitle: String?              // "Discard unreadable data" while a list needs attention
//     }
//     struct NiggleUpdateRow: Equatable { var seq: Int; var dateText: String; var trendText: String
//                                         var note: String; var isUsed: Bool }
//     struct NiggleDetailPresentation: Equatable {
//         enum Kind: Equatable { case open, resolved, observation }
//         enum Action: Equatable { case addUpdate, markResolved, reopen, edit, delete }
//         var kind: Kind; var location: String; var sideText: String
//         var dayCountText: String?; var label: String?; var actionText: String?; var ruleNote: String?
//         var disclaimer: String?; var triageLine: String?; var alsoMatchesText: String?
//         var nextChangeLine: String?; var updates: [NiggleUpdateRow]   // newest first
//         var ignoredUpdatesText: String?; var pausedExercises: [NigglePausedRow]
//         var professionalRule: String?; var note: String?; var actions: [Action]
//     }
//     enum NiggleLogPresenter {
//         static func present(entries: [StoredNiggle], rules: StoredTriageRules, paused: [StoredPausedExercise],
//                             entriesNeedAttention: Bool, rulesNeedAttention: Bool, pausedNeedAttention: Bool,
//                             today: String, locale: Locale) -> NiggleLogPresentation
//         static func detail(niggleId: String, entries: [StoredNiggle], rules: StoredTriageRules,
//                            paused: [StoredPausedExercise], rulesNeedAttention: Bool, today: String,
//                            locale: Locale) -> NiggleDetailPresentation?       // nil: the entry is gone
//         static func healthRow(enabled: Bool, entries: [StoredNiggle], today: String,
//                               locale: Locale) -> NiggleLogHealthRow?
//         static func rulePreview(_ rule: StoredTriageRule, locale: Locale) -> String
//         static func actionText(_ action: NiggleAction, locale: Locale) -> String
//     }
//     @MainActor final class NiggleLogModel: ObservableObject {
//         enum State: Equatable { case idle, loading, loaded(NiggleLogPresentation) }
//         @Published private(set) var state: State
//         init(settings: NiggleLogSettings, now: @escaping () -> Date = Date.init,
//              timeZone: @escaping () -> TimeZone = { .current },
//              locale: @escaping () -> Locale = { AppLanguage.activeLocale })
//         func load() async                      // may be synchronous; the tests `await` it either way
//         func detail(niggleId: String) -> NiggleDetailPresentation?   // from the latest load
//     }
//
// Strand/Data/CutStressModel.swift and CutStressPresenter.swift (§8.2, §10.7):
//
//     struct CutStressCard: Equatable {
//         var title: String
//         var points: [Double?]                 // one per result week: that week's mean
//         var axisMarks: NoopChartAxisMarks?    // always nil (§10.7)
//         var typicalRange: ClosedRange<Double>?  // exactly ChargeTypicalBand.range(baseline)
//         var lines: [String]                   // every other visible string of the card, in order
//     }
//     struct CutStressPresentation: Equatable {
//         var framing: String; var periodText: String   // "Last 12 weeks" or "Since <date>"
//         var restingHr: CutStressCard; var hrv: CutStressCard
//     }
//     enum CutStressPresenter {
//         static func present(_ result: CutStressResult, restingHrBaseline: BaselineState?,
//                             hrvBaseline: BaselineState?, firstWeekStart: String?,
//                             locale: Locale) -> CutStressPresentation
//     }
//     @MainActor final class CutStressModel: ObservableObject {
//         static let enabledKey = "noop.cutStressEnabled"
//         @MainActor static let flag: ObservableDefaultsFlag
//         enum State: Equatable { case idle, loading, loaded(CutStressPresentation) }
//         @Published private(set) var state: State
//         private(set) var input: CutStressInput?; private(set) var result: CutStressResult?
//         init(repository: Repository, scorecardSettings: CutScorecardSettings,
//              defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
//              timeZone: @escaping () -> TimeZone = { .current },
//              locale: @escaping () -> Locale = { AppLanguage.activeLocale })
//         func load() async
//     }
//
// Strand/Data/CheckpointTimelineSettings.swift (§9.3): `StoredCheckpoint`, `CheckpointIssue`,
// `CheckpointSaveResult` and the operations exactly as §9.3 lists them, plus
//     static let enabledKey = "noop.checkpointTimelineEnabled"; static let checkpointsKey = "timeline.checkpoints"
//     @MainActor static let flag: ObservableDefaultsFlag; init(defaults: UserDefaults = .standard)
//     var isEnabled: Bool { get }
//
// Strand/Data/TimelineSources.swift: exactly §8.4.
//
// Strand/Data/CheckpointTimelineModel.swift and CheckpointTimelinePresenter.swift (§8.3, §10.8):
//
//     enum TimelineRowDestination: Equatable {
//         case phaseSheet(phaseIndex: Int), checkpointSheet(checkpointId: String), bodyRecord
//         case personalEvents(eventId: String), scorecard, none
//     }
//     struct TimelineRow: Equatable {
//         var kind: TimelineItemKind; var position: TimelinePosition; var day: String
//         var title: String; var dateText: String; var details: [String]; var tags: [String]
//         var destination: TimelineRowDestination
//         var weightDestination: TimelineRowDestination?     // a target-date row's weight: the phase sheet
//     }
//     struct TimelineFootnote: Equatable { var text: String; var linkTitle: String? }
//     struct CheckpointTimelineHealthRow: Equatable { var title: String; var detail: String? }
//     struct CheckpointTimelinePresentation: Equatable {
//         var rows: [TimelineRow]; var todayRowIndex: Int?; var footnotes: [TimelineFootnote]
//         var emptyText: String?; var offersSetUpPhase: Bool; var attentionText: String?
//         var canAdd: Bool; var limitText: String?
//         var addTitle: String                   // "Add a checkpoint"
//         var discardTitle: String?              // "Discard unreadable data" while checkpoints need attention
//     }
//     enum CheckpointTimelinePresenter {
//         static func present(_ result: CheckpointTimelineResult, phases: [CutScorecardStoredPhase],
//                             checkpoints: [StoredCheckpoint], events: [PersonalEvent],
//                             scorecardEnabled: Bool, phasesNeedAttention: Bool,
//                             checkpointsNeedAttention: Bool, unitSystem: UnitSystem,
//                             locale: Locale) -> CheckpointTimelinePresentation
//         static func healthRow(enabled: Bool, result: CheckpointTimelineResult?,
//                               locale: Locale) -> CheckpointTimelineHealthRow?
//     }
//     @MainActor final class CheckpointTimelineModel: ObservableObject {
//         enum State: Equatable { case idle, loading, loaded(CheckpointTimelinePresentation) }
//         @Published private(set) var state: State
//         private(set) var result: CheckpointTimelineResult?     // the latest build
//         private(set) var timelineEvents: [PersonalEvent]       // kept beside the spans (§8.4)
//         init(settings: CheckpointTimelineSettings, scorecardSettings: CutScorecardSettings,
//              scorecard: CutScorecardModel, scans: TimelineScanSource, events: TimelineEventSource,
//              now: @escaping () -> Date = Date.init, timeZone: @escaping () -> TimeZone = { .current },
//              locale: @escaping () -> Locale = { AppLanguage.activeLocale },
//              unitSystem: @escaping () -> UnitSystem = { .metric })
//         func load() async
//     }
//
// Strand/Data/CutScorecardModel.swift gains (§8.3, work package 6-8b):
//     private(set) var evaluation: CutScorecardEvaluation?
//
// Behaviour assumed where the specification leaves it unstated:
//
//  1. Model and presenter inputs. The stage 6 models build their pure inputs from the stored lists in
//     stored order: one `TimelinePhase` per `CutScorecardSettings.phases` element, one
//     `TimelineCheckpoint` per stored checkpoint, so a `sourceIndex` indexes the stored list. While
//     `phasesNeedAttention` the phase list is empty.
//  2. Dates are written as `CutScorecardPresenter.Wording` writes a short day ("10 Feb" in en_GB);
//     only the day number and the month abbreviation are asserted, never the separator or a year.
//  3. Counts whose English source is a plural ("Logged before: %lld times", "%lld updates are
//     dated …") may use a singular variant for 1; only the leading words and the number are asserted.
//  4. Weekly means are written to one decimal (design proposal); a change carries its sign.
//  5. A flag that is off reads none of its part's stored-list keys. Reading the flag key itself is
//     allowed: it is how the part learns it is off.
//  6. The cut-stress model publishes `.idle` while either its own flag or `noop.cutScorecardEnabled`
//     is off: the screen is reachable only from the scorecard, and a restored route pops (§10.7).
//  7. "Not read" is observed through `Stage6RecordingDefaults`, which records the keys passed to
//     the getters; an implementation reaching a value by `dictionaryRepresentation` is not seen.
//
// Fixture: the one Fixture Person (stage 1 §13, ruling A7) with stage 6 §13. The rule ids of §13.1
// ("r-a" to "r-e") are stored here as "r-0000000a" to "r-0000000e", the store's id shape (§9.1);
// nothing else differs. Every label, location and date is invented. App tests that read nights from
// the repository use dates relative to the real clock (stage 1 ruling R31); the 2031 fixture serves
// the presenters and the settings.

import XCTest
import StrandAnalytics
import WhoopStore
@testable import Strand

// MARK: - Defaults helpers

/// The defaults suites one test class created, removed in its `tearDown`.
final class Stage6Suites {
    private(set) var names: [String] = []

    func make(_ label: String = "Stage6") throws -> UserDefaults {
        let name = "\(label)-\(UUID().uuidString)"
        names.append(name)
        return try XCTUnwrap(UserDefaults(suiteName: name))
    }

    func recording(_ label: String = "Stage6Recording") -> Stage6RecordingDefaults {
        let name = "\(label)-\(UUID().uuidString)"
        names.append(name)
        return Stage6RecordingDefaults(suiteName: name)!
    }

    func removeAll() {
        for name in names { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        names = []
    }
}

/// A defaults suite that records the keys its getters and setters are given.
final class Stage6RecordingDefaults: UserDefaults {
    var reads: [String] = []
    var writes: [String] = []

    override func object(forKey defaultName: String) -> Any? {
        reads.append(defaultName); return super.object(forKey: defaultName)
    }
    override func string(forKey defaultName: String) -> String? {
        reads.append(defaultName); return super.string(forKey: defaultName)
    }
    override func data(forKey defaultName: String) -> Data? {
        reads.append(defaultName); return super.data(forKey: defaultName)
    }
    override func array(forKey defaultName: String) -> [Any]? {
        reads.append(defaultName); return super.array(forKey: defaultName)
    }
    override func dictionary(forKey defaultName: String) -> [String: Any]? {
        reads.append(defaultName); return super.dictionary(forKey: defaultName)
    }
    override func bool(forKey defaultName: String) -> Bool {
        reads.append(defaultName); return super.bool(forKey: defaultName)
    }
    override func value(forKey key: String) -> Any? {
        reads.append(key); return super.value(forKey: key)
    }
    override func set(_ value: Any?, forKey defaultName: String) {
        writes.append(defaultName); super.set(value, forKey: defaultName)
    }
    override func set(_ value: Bool, forKey defaultName: String) {
        writes.append(defaultName); super.set(value, forKey: defaultName)
    }
    override func removeObject(forKey defaultName: String) {
        writes.append(defaultName); super.removeObject(forKey: defaultName)
    }
}

/// Saves and restores keys of the runner's standard defaults around a test that has to use them
/// (the static flags, `AICoachEngine` and the live stores read `.standard`).
struct Stage6StandardKeys {
    private let saved: [String: Any?]

    init(_ keys: [String]) {
        var saved: [String: Any?] = [:]
        for key in keys { saved[key] = UserDefaults.standard.object(forKey: key) }
        self.saved = saved
    }

    func restore() {
        for (key, value) in saved {
            if let value { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }
}

// MARK: - Fixture

enum Stage6Fixture {

    static let british = Locale(identifier: "en_GB")
    static let utc = TimeZone(identifier: "UTC")!

    static let enabledKeys = ["noop.niggleLogEnabled", "noop.cutStressEnabled", "noop.checkpointTimelineEnabled"]
    static let listKeys = ["niggleLog.entries", "niggleLog.rules", "niggleLog.paused", "timeline.checkpoints"]

    /// 12:00 UTC of a day key.
    static func noon(_ day: String) -> Date {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        return parser.date(from: day + "T12:00:00Z")!
    }

    // MARK: §13.1 rules

    static let professionalRule = "Fixture rule text."

    static func rule(_ letter: String, _ action: NiggleAction, characters: [NiggleCharacter] = [],
                     trends: [NiggleTrend] = [], weakness: Bool? = nil, from: Int?, through: Int? = nil) -> StoredTriageRule {
        StoredTriageRule(id: "r-0000000\(letter)", label: "Fixture label \(letter.uppercased())", action: action,
                         characters: characters, trends: trends, weakness: weakness, fromDay: from,
                         throughDay: through, note: "Fixture rule note \(letter.uppercased())")
    }

    static let ruleA = rule("a", .watch, characters: [.diffuse], trends: [.easing], from: 1, through: 10)
    static let ruleB = rule("b", .modify, characters: [.positional], from: 5)
    static let ruleC = rule("c", .seeProfessional, from: 30)
    static let ruleD = rule("d", .seeProfessional, trends: [.worsening], from: 20)
    static let ruleE = rule("e", .modify, characters: [.localised], weakness: true, from: 1)
    static let rules = StoredTriageRules(professionalRule: professionalRule, rules: [ruleA, ruleB, ruleC, ruleD, ruleE])
    static let noRules = StoredTriageRules(professionalRule: "", rules: [])

    // MARK: §13.2 complaints

    static func complaint(_ n: Int, _ location: String, _ side: StoredNiggle.Side, _ character: NiggleCharacter,
                          _ trend: NiggleTrend, weakness: Bool = false, onset: String, resolved: String? = nil,
                          updates: [StoredNiggleUpdate] = [], note: String = "") -> StoredNiggle {
        StoredNiggle(id: "n-0000000\(n)", kind: .complaint, location: location, side: side, character: character,
                     onsetDay: onset, resolvedDay: resolved, trend: trend, weakness: weakness, updates: updates,
                     note: note)
    }

    static let n1 = complaint(1, "Fixture location A", .left, .diffuse, .easing, onset: "2031-02-03",
                              resolved: "2031-02-12")
    static let n2 = complaint(2, "Fixture location B", .right, .positional, .unchanged, onset: "2031-03-03",
                              updates: [StoredNiggleUpdate(seq: 1, day: "2031-03-22", trend: .worsening,
                                                           weakness: false, note: "")],
                              note: "Fixture note")
    static let n3 = complaint(3, "Fixture location C", .both, .localised, .unchanged, weakness: true,
                              onset: "2031-04-07")
    static let n4 = StoredNiggle(id: "n-00000004", kind: .observation, location: "Fixture observation",
                                 side: .notApplicable, character: .other, onsetDay: "2031-01-13", resolvedDay: nil,
                                 trend: .notRecorded, weakness: false, updates: [],
                                 note: "Fixture observation note")
    static let n5 = complaint(5, "Fixture location D", .right, .diffuse, .notRecorded, onset: "2031-05-05")
    static let n6 = complaint(6, "Fixture location E", .left, .diffuse, .easing, onset: "2031-06-02")
    /// §13.2: a second "Fixture location B", right; a recurrence of N2.
    static let n7 = complaint(7, "Fixture location B", .right, .positional, .unchanged, onset: "2031-06-16")

    // MARK: §13.2 paused exercises

    static let pausedPress = StoredPausedExercise(id: "p-00000001", exercise: "Fixture Press", reason: "Fixture reason A",
                                                  until: "Fixture until text", pausedDay: "2031-03-10",
                                                  niggleId: "n-00000002", resumedDay: nil)
    static let pausedRow = StoredPausedExercise(id: "p-00000002", exercise: "Fixture Row", reason: "Fixture reason B",
                                                until: nil, pausedDay: "2031-01-20", niggleId: nil,
                                                resumedDay: "2031-02-10")

    // MARK: §13.4 phases and checkpoints

    static let p0 = CutScorecardStoredPhase(kind: .cut, name: "Fixture cut", startDay: "2031-01-06",
                                            targetWeightKg: 94.0, rateLowPercentPerWeek: 0.40,
                                            rateHighPercentPerWeek: 1.20)
    static let p1 = CutScorecardStoredPhase(kind: .other, name: "Fixture hold", startDay: "2031-06-16",
                                            targetWeightKg: nil, rateLowPercentPerWeek: 0.40,
                                            rateHighPercentPerWeek: 1.20)
    static let phases = [p0, p1]

    static let c1 = StoredCheckpoint(id: "c-000000a1", title: "Fixture waypoint", category: .weightWaypoint,
                                     day: "2031-03-19", approximate: true, done: false, waypointWeightKg: 96.0,
                                     phaseStartDay: nil)
    static let c2 = StoredCheckpoint(id: "c-000000a2", title: "Fixture panel", category: .bloodPanel,
                                     day: "2031-02-10", approximate: false, done: true, waypointWeightKg: nil,
                                     phaseStartDay: nil)
    static let c3 = StoredCheckpoint(id: "c-000000a3", title: "Fixture second scan", category: .scan,
                                     day: "2031-03-17", approximate: false, done: false, waypointWeightKg: nil,
                                     phaseStartDay: nil)
    static let c4 = StoredCheckpoint(id: "c-000000a4", title: "Fixture benchmark", category: .benchmark,
                                     day: "2031-02-05", approximate: false, done: false, waypointWeightKg: nil,
                                     phaseStartDay: nil)
    static let c5 = StoredCheckpoint(id: "c-000000a5", title: "Fixture target date", category: .targetDate,
                                     day: "2031-06-02", approximate: false, done: false, waypointWeightKg: nil,
                                     phaseStartDay: "2031-01-06")
    static let checkpoints = [c1, c2, c3, c4, c5]

    static let scanDays = ["2031-01-08", "2031-03-17"]

    // MARK: §13.4 events (the adapter fixture)

    static let e1 = PersonalEvent(id: "e100000000000000", kind: .deload, label: nil, startDay: "2031-02-17",
                                  endDay: "2031-02-23", note: nil, sensitive: false, createdAt: 1000)
    static let e2 = PersonalEvent(id: "e200000000000000", kind: .deload, label: nil, startDay: "2031-04-07",
                                  endDay: "2031-04-13", note: "Fixture note", sensitive: true, createdAt: 1001)
    static let e3 = PersonalEvent(id: "e300000000000000", kind: .dietBreak, label: nil, startDay: "2031-03-24",
                                  endDay: nil, note: nil, sensitive: false, createdAt: 1002)
    static let e4 = PersonalEvent(id: "e400000000000000", kind: .travel, label: nil, startDay: "2031-05-05",
                                  endDay: "2031-05-09", note: "Fixture trip", sensitive: false, createdAt: 1003)
    static let events = [e1, e2, e3, e4]

    static func scan(day: String, takenAt: Int) -> BodyScan {
        BodyScan(id: BodyScan.id(source: "body-scan-fixture", takenAt: takenAt), source: "body-scan-fixture",
                 takenAt: takenAt, day: day, values: [:], rows: [:], note: nil, unreadableKeys: [],
                 conflictingKeys: [])
    }

    // MARK: Pure inputs from stored values (assumption 1)

    static func timelinePhases(_ phases: [CutScorecardStoredPhase]) -> [TimelinePhase] {
        phases.map { TimelinePhase(startDay: $0.startDay, isCut: $0.kind == .cut, targetWeightKg: $0.targetWeightKg) }
    }

    static func timelineCheckpoints(_ checkpoints: [StoredCheckpoint]) -> [TimelineCheckpoint] {
        checkpoints.map {
            TimelineCheckpoint(day: $0.day, isApproximate: $0.approximate, category: $0.category,
                               waypointWeightKg: $0.waypointWeightKg, phaseStartDay: $0.phaseStartDay, isDone: $0.done)
        }
    }

    static func spans(_ events: [PersonalEvent]) -> [TimelineSpan] {
        events.map { TimelineSpan(kind: $0.kind == .deload ? .deload : .dietBreak, startDay: $0.startDay, endDay: $0.endDay) }
    }

    /// §13.4 run through the pure function.
    static func build(today: String, phases: [CutScorecardStoredPhase] = phases,
                      checkpoints: [StoredCheckpoint] = checkpoints, scanDays: [String] = scanDays,
                      events: [PersonalEvent] = [e1, e3], projection: TimelineProjection? =
                        TimelineProjection(status: .projected, targetDay: "2031-05-27"),
                      scans: TimelineSourceState = .on, eventsState: TimelineSourceState = .on) -> CheckpointTimelineResult {
        CheckpointTimeline.build(CheckpointTimelineInput(
            phases: timelinePhases(phases), checkpoints: timelineCheckpoints(checkpoints), scanDays: scanDays,
            spans: spans(events), projection: projection, scans: scans, events: eventsState, today: today))
    }

    // MARK: The stored shapes of §9.2 and §9.3

    static func json(_ object: Any) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
        return String(decoding: data, as: UTF8.self)
    }

    static func element(_ n: StoredNiggle) -> [String: Any] {
        var object: [String: Any] = [
            "character": n.character.rawValue, "id": n.id, "kind": n.kind.rawValue, "location": n.location,
            "note": n.note, "onsetDay": n.onsetDay, "side": n.side.rawValue, "trend": n.trend.rawValue,
            "updates": n.updates.map { ["day": $0.day, "note": $0.note, "seq": $0.seq, "trend": $0.trend.rawValue,
                                        "weakness": $0.weakness] as [String: Any] },
            "v": 1, "weakness": n.weakness,
        ]
        if let resolved = n.resolvedDay { object["resolvedDay"] = resolved }
        return object
    }

    static func element(_ r: StoredTriageRule) -> [String: Any] {
        var object: [String: Any] = [
            "action": r.action.rawValue, "characters": r.characters.map(\.rawValue), "id": r.id, "label": r.label,
            "note": r.note, "trends": r.trends.map(\.rawValue),
        ]
        if let weakness = r.weakness { object["weakness"] = weakness }
        if let from = r.fromDay { object["fromDay"] = from }
        if let through = r.throughDay { object["throughDay"] = through }
        return object
    }

    static func element(_ p: StoredPausedExercise) -> [String: Any] {
        var object: [String: Any] = ["exercise": p.exercise, "id": p.id, "pausedDay": p.pausedDay, "reason": p.reason,
                                     "v": 1]
        if let until = p.until { object["until"] = until }
        if let niggle = p.niggleId { object["niggleId"] = niggle }
        if let resumed = p.resumedDay { object["resumedDay"] = resumed }
        return object
    }

    static func element(_ c: StoredCheckpoint) -> [String: Any] {
        var object: [String: Any] = ["approximate": c.approximate, "category": c.category.rawValue, "day": c.day,
                                     "done": c.done, "id": c.id, "title": c.title, "v": 1]
        if let weight = c.waypointWeightKg { object["waypointWeightKg"] = weight }
        if let phase = c.phaseStartDay { object["phaseStartDay"] = phase }
        return object
    }

    static func storedEntries(_ entries: [StoredNiggle]) -> String { json(entries.map(element)) }
    static func storedRules(_ rules: StoredTriageRules) -> String {
        json(["professionalRule": rules.professionalRule, "rules": rules.rules.map(element), "v": 1] as [String: Any])
    }
    static func storedPaused(_ paused: [StoredPausedExercise]) -> String { json(paused.map(element)) }
    static func storedCheckpoints(_ checkpoints: [StoredCheckpoint]) -> String { json(checkpoints.map(element)) }

    /// Writes the whole fixture to `defaults` in its stored shape.
    static func seed(_ defaults: UserDefaults, entries: [StoredNiggle] = [n1, n2, n4],
                     rules: StoredTriageRules = rules, paused: [StoredPausedExercise] = [pausedPress, pausedRow],
                     checkpoints: [StoredCheckpoint] = checkpoints) {
        defaults.set(storedEntries(entries), forKey: "niggleLog.entries")
        defaults.set(storedRules(rules), forKey: "niggleLog.rules")
        defaults.set(storedPaused(paused), forKey: "niggleLog.paused")
        defaults.set(storedCheckpoints(checkpoints), forKey: "timeline.checkpoints")
    }

    /// Every piece of owner text the fixture stores: none may leave the app's own screens.
    static let needles: [String] = [
        "Fixture location A", "Fixture location B", "Fixture location C", "Fixture location D", "Fixture location E",
        "Fixture observation", "Fixture label A", "Fixture label B", "Fixture label C", "Fixture label D",
        "Fixture label E", "Fixture rule note", "Fixture rule text.", "Fixture reason A", "Fixture reason B",
        "Fixture until text", "Fixture waypoint", "Fixture panel", "Fixture second scan", "Fixture benchmark",
        "Fixture target date", "Fixture note",
    ]
}

// MARK: - Reading presentations

enum Stage6Text {
    /// Every `String` inside a value, found through its mirror.
    static func strings(in value: Any) -> [String] {
        if let text = value as? String { return [text] }
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            return mirror.children.first.map { strings(in: $0.value) } ?? []
        }
        return mirror.children.flatMap { strings(in: $0.value) }
    }

    static func joined(_ value: Any) -> String { strings(in: value).joined(separator: "\n") }

    /// Whole word, case-insensitive.
    static func containsWord(_ text: String, _ word: String) -> Bool {
        text.range(of: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b",
                   options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// A word beginning with `stem`, case-insensitive ("diagnos" finds "diagnosis").
    static func containsStem(_ text: String, _ stem: String) -> Bool {
        text.range(of: "\\b\(NSRegularExpression.escapedPattern(for: stem))",
                   options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The stored JSON array under `key`, or nil.
    static func array(_ defaults: UserDefaults, _ key: String) -> [[String: Any]]? {
        guard let text = defaults.string(forKey: key), let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
    }

    /// The stored JSON object under `key`, or nil.
    static func object(_ defaults: UserDefaults, _ key: String) -> [String: Any]? {
        guard let text = defaults.string(forKey: key), let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// The four stored lists and the phases string, as stored.
    static func raw(_ defaults: UserDefaults) -> [String: String] {
        var out: [String: String] = [:]
        for key in Stage6Fixture.listKeys + ["cutScorecard.phases"] { out[key] = defaults.string(forKey: key) ?? "<absent>" }
        return out
    }
}
