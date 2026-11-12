import Combine
import Foundation
import StrandAnalytics

// The niggle log's screen model (stage 6 specification §8.1, §10.2 to §10.6). One object the log, the
// detail screen and the sheets read and write through. With `noop.niggleLogEnabled` off it publishes
// `.idle` and reads none of the log's stored lists.
//
// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).

@MainActor
final class NiggleLogModel: ObservableObject {
    enum State: Equatable {
        case idle, loading
        case loaded(NiggleLogPresentation)
    }

    @Published private(set) var state: State = .idle

    let settings: NiggleLogSettings
    private let now: () -> Date
    private let timeZone: () -> TimeZone
    private let locale: () -> Locale
    /// What the latest load read, so a detail is the same moment as the list.
    private var snapshot: Snapshot?

    private struct Snapshot {
        let entries: [StoredNiggle]
        let rules: StoredTriageRules
        let paused: [StoredPausedExercise]
        let rulesNeedAttention: Bool
        let today: String
        let locale: Locale
    }

    init(settings: NiggleLogSettings = NiggleLogSettings(), now: @escaping () -> Date = Date.init,
         timeZone: @escaping () -> TimeZone = { .current },
         locale: @escaping () -> Locale = { AppLanguage.activeLocale }) {
        self.settings = settings
        self.now = now
        self.timeZone = timeZone
        self.locale = locale
    }

    /// Flag off: `.idle`, and no list is read. Flag on: the stored lists through the presenter, for
    /// the day the clock is on (read once).
    func load() async {
        guard settings.isEnabled else {
            snapshot = nil
            if state != .idle { state = .idle }
            return
        }
        let today = LocalDayWindows(timeZone: timeZone()).dayKey(for: now())
        let shownLocale = locale()
        let entriesNeedAttention = settings.entriesNeedAttention
        let rulesNeedAttention = settings.rulesNeedAttention
        let pausedNeedAttention = settings.pausedNeedAttention
        let read = Snapshot(entries: settings.entries, rules: settings.rules, paused: settings.paused,
                            rulesNeedAttention: rulesNeedAttention, today: today, locale: shownLocale)
        snapshot = read
        let presentation = NiggleLogPresenter.present(
            entries: read.entries, rules: read.rules, paused: read.paused, entriesNeedAttention: entriesNeedAttention,
            rulesNeedAttention: rulesNeedAttention, pausedNeedAttention: pausedNeedAttention, today: today,
            locale: shownLocale)
        if state != .loaded(presentation) { state = .loaded(presentation) }
    }

    /// The detail of one entry as of the latest load; nil when it no longer exists (the screen pops).
    func detail(niggleId: String) -> NiggleDetailPresentation? {
        guard let s = snapshot else { return nil }
        return NiggleLogPresenter.detail(niggleId: niggleId, entries: s.entries, rules: s.rules, paused: s.paused,
                                         rulesNeedAttention: s.rulesNeedAttention, today: s.today, locale: s.locale)
    }

    /// The Health tab's row over the app's own store: nil while the flag is off, and no list is
    /// read then.
    static func liveHealthRow(settings: NiggleLogSettings = NiggleLogSettings(), now: Date = Date(),
                              timeZone: TimeZone = .current) -> NiggleLogHealthRow? {
        guard settings.isEnabled else { return nil }
        return NiggleLogPresenter.healthRow(enabled: true, entries: settings.entries,
                                            today: LocalDayWindows(timeZone: timeZone).dayKey(for: now),
                                            locale: AppLanguage.activeLocale)
    }

    // MARK: What the sheets edit

    /// The stored entry, for an edit.
    func entry(id: String) -> StoredNiggle? { snapshot?.entries.first { $0.id == id } }
    func pause(id: String) -> StoredPausedExercise? { snapshot?.paused.first { $0.id == id } }
    /// The stored rules, for the rules sheet.
    var rules: StoredTriageRules { snapshot?.rules ?? StoredTriageRules(professionalRule: "", rules: []) }
    /// The open complaints a pause may be linked to, by id and location.
    var openComplaints: [StoredNiggle] {
        (snapshot?.entries ?? []).filter { $0.kind == .complaint && $0.resolvedDay == nil }
    }
    /// The day the latest load was for.
    var today: String { snapshot?.today ?? LocalDayWindows(timeZone: timeZone()).dayKey(for: now()) }

    // MARK: Writes. Each reloads; each returns whether it saved.

    @discardableResult func save(_ niggle: StoredNiggle) async -> Bool { await after(settings.save(niggle)) }
    @discardableResult func delete(niggleId: String) async -> Bool { await after(settings.delete(niggleId: niggleId)) }
    @discardableResult func resolve(niggleId: String, on day: String) async -> Bool {
        await after(settings.resolve(niggleId: niggleId, on: day))
    }
    @discardableResult func reopen(niggleId: String) async -> Bool { await after(settings.reopen(niggleId: niggleId)) }
    @discardableResult func addUpdate(niggleId: String, day: String, trend: NiggleTrend, weakness: Bool,
                                      note: String) async -> Bool {
        await after(settings.addUpdate(niggleId: niggleId, day: day, trend: trend, weakness: weakness, note: note))
    }
    @discardableResult func saveRules(_ rules: StoredTriageRules) async -> Bool { await after(settings.saveRules(rules)) }
    @discardableResult func save(_ pause: StoredPausedExercise) async -> Bool { await after(settings.save(pause)) }
    @discardableResult func resume(pausedId: String, on day: String) async -> Bool {
        await after(settings.resume(pausedId: pausedId, on: day))
    }
    @discardableResult func delete(pausedId: String) async -> Bool { await after(settings.delete(pausedId: pausedId)) }

    /// The owner's "Discard unreadable data": removes each list that cannot be read, and only those.
    func discardUnreadable() async {
        settings.discardUnreadableEntries()
        settings.discardUnreadableRules()
        settings.discardUnreadablePaused()
        await load()
    }

    private func after(_ saved: Bool) async -> Bool {
        await load()
        return saved
    }
}

// MARK: - Drafts

/// The niggle sheet's editable values (§10.4): captured before the write, kept intact when it is refused.
struct NiggleDraft: Equatable {
    var niggle: StoredNiggle

    /// A new complaint with its onset today.
    static func new(today: String) -> NiggleDraft {
        NiggleDraft(niggle: StoredNiggle(id: "", kind: .complaint, location: "", side: .notApplicable,
                                         character: .diffuse, onsetDay: today, resolvedDay: nil, trend: .notRecorded,
                                         weakness: false, updates: [], note: ""))
    }

    private var location: String { niggle.location.trimmingCharacters(in: .whitespacesAndNewlines) }
    var locationIsEmpty: Bool { location.isEmpty }
    var locationIsTooLong: Bool { location.count > NiggleLogSettings.maxLocation }
    var noteIsTooLong: Bool {
        niggle.note.trimmingCharacters(in: .whitespacesAndNewlines).count > NiggleLogSettings.maxNote
    }
    var canSave: Bool { !locationIsEmpty && !locationIsTooLong && !noteIsTooLong }
}

/// The rules sheet's editable values (§10.5).
struct TriageRulesDraft: Equatable {
    var rules: StoredTriageRules

    static func newRule() -> StoredTriageRule {
        StoredTriageRule(id: "", label: "", action: .watch, characters: [], trends: [], weakness: nil, fromDay: nil,
                         throughDay: nil, note: "")
    }

    var canAddRule: Bool { rules.rules.count < NiggleLogSettings.maxRules }

    /// The rule at `index` cannot be saved as it stands.
    func ruleIsInvalid(_ index: Int) -> Bool {
        guard rules.rules.indices.contains(index) else { return false }
        let rule = rules.rules[index]
        let label = rule.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let from = rule.fromDay ?? 1
        return label.isEmpty || label.count > NiggleLogSettings.maxRuleLabel || from < 1
            || (rule.throughDay.map { $0 < from } ?? false)
            || rule.note.trimmingCharacters(in: .whitespacesAndNewlines).count > NiggleLogSettings.maxRuleNote
    }

    var canSave: Bool {
        rules.professionalRule.trimmingCharacters(in: .whitespacesAndNewlines).count <= NiggleLogSettings.maxProfessionalRule
            && !rules.rules.indices.contains(where: ruleIsInvalid)
    }
}

/// The paused-exercise sheet's editable values (§10.6).
struct PausedExerciseDraft: Equatable {
    var pause: StoredPausedExercise

    static func new(today: String) -> PausedExerciseDraft {
        PausedExerciseDraft(pause: StoredPausedExercise(id: "", exercise: "", reason: "", until: nil, pausedDay: today,
                                                        niggleId: nil, resumedDay: nil))
    }

    var exerciseIsEmpty: Bool { pause.exercise.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var reasonIsEmpty: Bool { pause.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var canSave: Bool { !exerciseIsEmpty && !reasonIsEmpty }
}
