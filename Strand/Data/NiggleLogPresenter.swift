import Foundation
import StrandAnalytics

// The words of the niggle log (stage 6 specification §10.2, §10.3, §10.5, §11): the log screen, the
// detail screen, the rules sheet's read-back and the Health row. Views draw these values and decide
// nothing.
//
// Every label comes from a rule the owner typed and is applied by `NiggleTriage.evaluate`, the one
// source of a label and a day count (§8.1). The owner's own text (labels, notes, the professional
// rule, locations, exercises, reasons) is shown verbatim. Nothing here names a cause, a prognosis or
// a treatment, and an action is a word, never a colour (decision D6).
//
// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).

/// The Health tab's row (§10.1): "Niggle log" and the open count, or nothing.
struct NiggleLogHealthRow: Equatable {
    var title: String
    var detail: String?
}

/// One open complaint on the log screen.
struct NiggleOpenRow: Equatable, Identifiable {
    var id: String
    var location: String
    var sideText: String
    var dayCountText: String
    /// The owner's label of the rule that applies; nil when none does.
    var label: String?
    var actionText: String?
    /// "Your rule, applied to what you logged. This is not a diagnosis.", under every label.
    var disclaimer: String?
    /// The line shown in place of a label.
    var triageLine: String?
    var nextChangeLine: String?
    var recurrenceText: String?
}

/// One paused (or resumed) exercise.
struct NigglePausedRow: Equatable, Identifiable {
    var id: String
    var exercise: String
    var reason: String
    var sinceText: String
    var untilText: String?
    var resumedText: String?
    var niggleId: String?
}

struct NiggleObservationRow: Equatable, Identifiable {
    var id: String
    var location: String
    var sideText: String
    var note: String
    var notedText: String
}

struct NiggleResolvedRow: Equatable, Identifiable {
    var id: String
    var location: String
    var sideText: String
    var durationText: String
    var datesText: String
}

/// The log screen (§10.2).
struct NiggleLogPresentation: Equatable {
    enum State: Equatable { case firstUse, list, entriesNeedAttention }
    var state: State
    /// The owner's text, verbatim; nil when none is written.
    var professionalRule: String?
    /// "No rules entered yet" or "You have not written a rule for seeing a professional".
    var professionalNotice: String?
    var open: [NiggleOpenRow]
    var paused: [NigglePausedRow]
    var resumed: [NigglePausedRow]
    var observations: [NiggleObservationRow]
    var resolved: [NiggleResolvedRow]
    var entriesAttentionText: String?
    var rulesAttentionText: String?
    var canAdd: Bool
    var limitText: String?
    /// "Log a niggle" on first use.
    var logTitle: String?
    /// "Set up your rules" beside the notice.
    var setUpRulesTitle: String?
    /// "Discard unreadable data" while a list needs attention.
    var discardTitle: String?
    /// True while the paused list cannot be read: its section offers only the discard action.
    var pausedNeedAttention: Bool
}

/// One update on the detail screen.
struct NiggleUpdateRow: Equatable {
    var seq: Int
    var dateText: String
    var trendText: String
    var note: String
    /// False for an update dated outside the complaint: kept, shown, and not used.
    var isUsed: Bool
}

/// The detail screen (§10.3).
struct NiggleDetailPresentation: Equatable {
    enum Kind: Equatable { case open, resolved, observation }
    enum Action: Equatable { case addUpdate, markResolved, reopen, edit, delete }
    var kind: Kind
    var location: String
    var sideText: String
    var dayCountText: String?
    var label: String?
    var actionText: String?
    /// The matched rule's own note, verbatim.
    var ruleNote: String?
    var disclaimer: String?
    var triageLine: String?
    var alsoMatchesText: String?
    var nextChangeLine: String?
    /// Newest first.
    var updates: [NiggleUpdateRow]
    var ignoredUpdatesText: String?
    var pausedExercises: [NigglePausedRow]
    var professionalRule: String?
    var note: String?
    var actions: [Action]
    /// "since 3 Mar", "3 Feb to 12 Feb" or "noted 13 Jan".
    var datesText: String?
}

enum NiggleLogPresenter {

    // MARK: The log screen

    static func present(entries: [StoredNiggle], rules: StoredTriageRules, paused: [StoredPausedExercise],
                        entriesNeedAttention: Bool, rulesNeedAttention: Bool, pausedNeedAttention: Bool,
                        today: String, locale: Locale) -> NiggleLogPresentation {
        let words = CutScorecardPresenter.Wording(unitSystem: .metric, locale: locale)
        let shownRules = rulesNeedAttention ? [] : rules.rules
        var open: [(row: NiggleOpenRow, severity: Int, dayCount: Int, location: String)] = []
        var observations: [NiggleObservationRow] = []
        var resolved: [NiggleResolvedRow] = []
        if !entriesNeedAttention {
            for entry in entries {
                switch entry.kind {
                case .observation:
                    observations.append(NiggleObservationRow(
                        id: entry.id, location: entry.location, sideText: sideText(entry.side), note: entry.note,
                        notedText: String(localized: "noted \(words.shortDate(entry.onsetDay))")))
                case .complaint:
                    let triage = self.triage(entry, rules: shownRules, today: today)
                    if !isListedOpen(triage) {
                        resolved.append(NiggleResolvedRow(
                            id: entry.id, location: entry.location, sideText: sideText(entry.side),
                            durationText: resolvedAfterText(triage.dayCount ?? 1),
                            datesText: rangeText(entry.onsetDay, entry.resolvedDay ?? entry.onsetDay, words)))
                    } else {
                        let row = openRow(entry, triage: triage, entries: entries, rules: shownRules,
                                          rulesNeedAttention: rulesNeedAttention)
                        open.append((row, triage.action.map(NiggleTriage.severity) ?? -1, triage.dayCount ?? 0,
                                     entry.location.lowercased()))
                    }
                }
            }
        }
        open.sort { a, b in
            if a.severity != b.severity { return a.severity > b.severity }
            if a.dayCount != b.dayCount { return a.dayCount > b.dayCount }
            if a.location != b.location { return a.location < b.location }
            return a.row.id < b.row.id
        }
        let shownPauses = pausedNeedAttention ? [] : paused
        let pausedRows = shownPauses.filter { $0.resumedDay == nil }.map { pausedRow($0, words) }
        let resumedRows = shownPauses.filter { $0.resumedDay != nil }.map { pausedRow($0, words) }

        let professional = rules.professionalRule.isEmpty || rulesNeedAttention ? nil : rules.professionalRule
        var notice: String?
        if !rulesNeedAttention {
            if rules.rules.isEmpty {
                notice = String(localized: "No rules entered yet")
            } else if rules.professionalRule.isEmpty {
                notice = String(localized: "You have not written a rule for seeing a professional")
            }
        }
        let isFirstUse = !entriesNeedAttention && !rulesNeedAttention && !pausedNeedAttention && entries.isEmpty
            && rules.rules.isEmpty && rules.professionalRule.isEmpty && paused.isEmpty
        let full = entries.count >= NiggleLogSettings.maxEntries
        let anyAttention = entriesNeedAttention || rulesNeedAttention || pausedNeedAttention
        return NiggleLogPresentation(
            state: entriesNeedAttention ? .entriesNeedAttention : (isFirstUse ? .firstUse : .list),
            professionalRule: professional, professionalNotice: notice,
            open: open.map(\.row), paused: pausedRows, resumed: resumedRows, observations: observations,
            resolved: resolved,
            entriesAttentionText: entriesNeedAttention
                ? String(localized: "Your log could not be read. Nothing has been changed.") : nil,
            rulesAttentionText: rulesNeedAttention
                ? String(localized: "Your rules could not be read. Nothing has been changed.") : nil,
            canAdd: !entriesNeedAttention && !full,
            limitText: full ? String(localized: "The log holds up to \(NiggleLogSettings.maxEntries) entries") : nil,
            logTitle: isFirstUse ? String(localized: "Log a niggle") : nil,
            setUpRulesTitle: isFirstUse || notice != nil ? String(localized: "Set up your rules") : nil,
            discardTitle: anyAttention ? String(localized: "Discard unreadable data") : nil,
            pausedNeedAttention: pausedNeedAttention)
    }

    // MARK: The detail screen

    /// Nil when the entry no longer exists: the screen pops.
    static func detail(niggleId: String, entries: [StoredNiggle], rules: StoredTriageRules,
                       paused: [StoredPausedExercise], rulesNeedAttention: Bool, today: String,
                       locale: Locale) -> NiggleDetailPresentation? {
        guard let entry = entries.first(where: { $0.id == niggleId }) else { return nil }
        let words = CutScorecardPresenter.Wording(unitSystem: .metric, locale: locale)
        let linked = paused.filter { $0.niggleId == entry.id }.map { pausedRow($0, words) }
        if entry.kind == .observation {
            return NiggleDetailPresentation(
                kind: .observation, location: entry.location, sideText: sideText(entry.side), dayCountText: nil,
                label: nil, actionText: nil, ruleNote: nil, disclaimer: nil, triageLine: nil, alsoMatchesText: nil,
                nextChangeLine: nil, updates: [], ignoredUpdatesText: nil, pausedExercises: linked,
                professionalRule: nil, note: entry.note.isEmpty ? nil : entry.note, actions: [.edit, .delete],
                datesText: String(localized: "noted \(words.shortDate(entry.onsetDay))"))
        }
        let shownRules = rulesNeedAttention ? [] : rules.rules
        let triage = self.triage(entry, rules: shownRules, today: today)
        let updates = entry.updates
            .sorted { ($0.day, $0.seq) > ($1.day, $1.seq) }
            .map { update in
                NiggleUpdateRow(seq: update.seq, dateText: words.shortDate(update.day),
                                trendText: trendText(update.trend), note: update.note,
                                isUsed: isUsed(update, of: entry, today: today))
            }
        let ignored = triage.ignoredUpdates > 0
            ? String(localized: "\(triage.ignoredUpdates) updates are dated outside this complaint and were not used")
            : nil
        let professional = rules.professionalRule.isEmpty || rulesNeedAttention ? nil : rules.professionalRule
        let note = entry.note.isEmpty ? nil : entry.note
        if !isListedOpen(triage) {
            return NiggleDetailPresentation(
                kind: .resolved, location: entry.location, sideText: sideText(entry.side),
                dayCountText: resolvedAfterText(triage.dayCount ?? 1), label: nil, actionText: nil, ruleNote: nil,
                disclaimer: nil, triageLine: nil, alsoMatchesText: nil, nextChangeLine: nil, updates: updates,
                ignoredUpdatesText: ignored, pausedExercises: linked, professionalRule: professional, note: note,
                actions: [.reopen, .edit, .delete],
                datesText: rangeText(entry.onsetDay, entry.resolvedDay ?? entry.onsetDay, words))
        }
        let row = openRow(entry, triage: triage, entries: entries, rules: shownRules,
                          rulesNeedAttention: rulesNeedAttention)
        let winner = shownRules.first { $0.id == triage.ruleId }
        let others = triage.matchedRuleIds.filter { $0 != triage.ruleId }
            .compactMap { id in shownRules.first { $0.id == id }?.label }
        return NiggleDetailPresentation(
            kind: .open, location: entry.location, sideText: sideText(entry.side), dayCountText: row.dayCountText,
            label: row.label, actionText: row.actionText,
            ruleNote: winner.flatMap { $0.note.isEmpty ? nil : $0.note }, disclaimer: row.disclaimer,
            triageLine: row.triageLine,
            alsoMatchesText: others.isEmpty ? nil : String(localized: "Also matches: \(others.joined(separator: ", "))"),
            nextChangeLine: row.nextChangeLine, updates: updates, ignoredUpdatesText: ignored,
            pausedExercises: linked, professionalRule: professional, note: note,
            actions: [.addUpdate, .markResolved, .edit, .delete],
            datesText: String(localized: "since \(words.shortDate(entry.onsetDay))"))
    }

    // MARK: Health row

    /// Nil while the flag is off. The detail is the count of open complaints, and nothing at none.
    static func healthRow(enabled: Bool, entries: [StoredNiggle], today: String,
                          locale: Locale) -> NiggleLogHealthRow? {
        guard enabled else { return nil }
        let open = entries.filter { $0.kind == .complaint && isListedOpen(triage($0, rules: [], today: today)) }.count
        return NiggleLogHealthRow(title: String(localized: "Niggle log"),
                                  detail: open > 0 ? String(localized: "\(open) open") : nil)
    }

    // MARK: Rules sheet

    /// The rule read back from its fields (§10.5), so the owner can check what they entered.
    static func rulePreview(_ rule: StoredTriageRule, locale: Locale) -> String {
        let or = " " + String(localized: "or") + " "
        var parts: [String] = []
        if rule.characters.isEmpty {
            parts.append(String(localized: "Any complaint"))
        } else {
            let names = rule.characters.map(characterText).joined(separator: or)
            parts.append(String(localized: "\(names) complaints"))
        }
        if !rule.trends.isEmpty {
            let names = rule.trends.map(trendText).joined(separator: or)
            parts.append(String(localized: "that is \(names)"))
        }
        if let weakness = rule.weakness {
            parts.append(weakness ? String(localized: "with weakness") : String(localized: "without weakness"))
        }
        if let from = rule.fromDay { parts.append(String(localized: "from day \(from)")) }
        if let through = rule.throughDay { parts.append(String(localized: "through day \(through)")) }
        parts.append(String(localized: "is labelled \u{201C}\(rule.label)\u{201D}"))
        return parts.joined(separator: " ")
    }

    /// "When two rules with the same action both apply, the higher one in this list is shown."
    static var tieNote: String {
        String(localized: "When two rules with the same action both apply, the higher one in this list is shown.")
    }

    /// The rules sheet's caption under the professional rule.
    static var professionalRuleCaption: String {
        String(localized: "Write it in your own words. The app shows it back to you and does nothing else with it.")
    }

    // MARK: Screen labels

    static var title: String { String(localized: "Niggle log") }
    static var professionalTitle: String { String(localized: "Your rule for seeing a professional") }
    static var openTitle: String { String(localized: "Open") }
    static var pausedTitle: String { String(localized: "Paused by your coach") }
    static var observationsTitle: String { String(localized: "Observations") }
    static var resolvedTitle: String { String(localized: "Resolved") }
    static var resumedTitle: String { String(localized: "Resumed") }
    static var logNiggleTitle: String { String(localized: "Log a niggle") }
    static var setUpRulesTitle: String { String(localized: "Set up your rules") }
    static var pauseExerciseTitle: String { String(localized: "Pause an exercise") }
    static var addUpdateTitle: String { String(localized: "Add update") }
    static var markResolvedTitle: String { String(localized: "Mark resolved") }
    static var reopenTitle: String { String(localized: "Reopen") }
    static var addRuleTitle: String { String(localized: "Add a rule") }
    static var markResumedTitle: String { String(localized: "Mark resumed") }
    static var editTitle: String { String(localized: "Edit") }
    static var deleteTitle: String { String(localized: "Delete") }
    static var updatesTitle: String { String(localized: "Updates") }
    static var rulesTitle: String { String(localized: "Your rules") }
    static var ruleTitle: String { String(localized: "Rule") }
    static var editPauseTitle: String { String(localized: "Edit pause") }
    static var notUsedTag: String { String(localized: "not used") }
    static var firstUseText: String {
        String(localized: "A dated record of a complaint: where, what kind, and how it changes. Labels come only from rules you write.")
    }
    static var deleteEntryTitle: String { String(localized: "Delete this entry?") }
    static var deleteEntryDetail: String {
        String(localized: "Paused exercises linked to it stay in your list, without the link.")
    }
    static var deleteRuleTitle: String { String(localized: "Delete this rule?") }
    static var deleteRuleDetail: String { String(localized: "Complaints are labelled again without it.") }
    static var deletePauseTitle: String { String(localized: "Delete this pause?") }
    static var deletePauseDetail: String { String(localized: "The niggle it is linked to is not changed.") }

    // MARK: Sheet messages (§10.4 to §10.6)

    /// Why a niggle draft cannot be saved; nil when it can.
    static func draftIssue(_ draft: NiggleDraft) -> String? {
        if draft.locationIsEmpty { return String(localized: "Enter a location.") }
        if draft.locationIsTooLong { return String(localized: "A location can be up to 60 characters.") }
        return nil
    }

    /// Why a rule cannot be saved; nil when it can.
    static func ruleIssue(_ rule: StoredTriageRule) -> String? {
        if rule.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return String(localized: "Enter a label.") }
        if let from = rule.fromDay, from < 1 { return String(localized: "From day starts at 1.") }
        if let through = rule.throughDay, through < (rule.fromDay ?? 1) {
            return String(localized: "Through day cannot be before from day.")
        }
        return nil
    }

    /// Why a paused-exercise draft cannot be saved; nil when it can.
    static func pauseIssue(_ draft: PausedExerciseDraft) -> String? {
        if draft.exerciseIsEmpty { return String(localized: "Enter an exercise.") }
        if draft.reasonIsEmpty { return String(localized: "Enter a reason.") }
        return nil
    }

    /// A refused write: the sheet stays open with its values.
    static var couldNotSave: String { String(localized: "Could not save.") }
    /// "The list holds up to 20 rules".
    static var rulesLimitText: String { String(localized: "The list holds up to \(NiggleLogSettings.maxRules) rules") }
    /// "The log holds up to 100 paused exercises".
    static var pausedLimitText: String {
        String(localized: "The log holds up to \(NiggleLogSettings.maxPaused) paused exercises")
    }

    // MARK: Words

    static func actionText(_ action: NiggleAction, locale: Locale) -> String {
        switch action {
        case .watch: return String(localized: "Watch")
        case .modify: return String(localized: "Modify training")
        case .seeProfessional: return String(localized: "See a professional")
        }
    }

    static func sideText(_ side: StoredNiggle.Side) -> String {
        switch side {
        case .left: return String(localized: "Left")
        case .right: return String(localized: "Right")
        case .both: return String(localized: "Both")
        case .notApplicable: return String(localized: "Not applicable")
        }
    }

    static func characterText(_ character: NiggleCharacter) -> String {
        switch character {
        case .diffuse: return String(localized: "Spread over an area")
        case .localised: return String(localized: "One spot")
        case .positional: return String(localized: "Only in one position or movement")
        case .other: return String(localized: "Something else")
        }
    }

    static func trendText(_ trend: NiggleTrend) -> String {
        switch trend {
        case .easing: return String(localized: "Easing")
        case .unchanged: return String(localized: "No change")
        case .worsening: return String(localized: "Getting worse")
        case .notRecorded: return String(localized: "Not recorded")
        }
    }

    /// A stored day written as the scorecard writes a short day ("10 Mar").
    static func dayText(_ day: String, locale: Locale) -> String {
        CutScorecardPresenter.Wording(unitSystem: .metric, locale: locale).shortDate(day)
    }

    // MARK: Pieces

    /// The one call of the triage for a stored complaint (§8.1).
    /// Whether the log lists a complaint under Open: every triage result but `.resolved`, an invalid
    /// one included (a day ahead of "today" after a time-zone change). The Health row counts the
    /// same set, so its count and the Open section cannot disagree.
    private static func isListedOpen(_ triage: NiggleTriageResult) -> Bool { triage.status != .resolved }

    private static func triage(_ entry: StoredNiggle, rules: [StoredTriageRule], today: String) -> NiggleTriageResult {
        let complaint = NiggleComplaint(
            onsetDay: entry.onsetDay, resolvedDay: entry.resolvedDay, character: entry.character, trend: entry.trend,
            weakness: entry.weakness,
            updates: entry.updates.map { NiggleUpdate(day: $0.day, sequence: $0.seq, trend: $0.trend, weakness: $0.weakness) })
        return NiggleTriage.evaluate(NiggleTriageInput(complaint: complaint, rules: rules.map(\.triageRule), today: today))
    }

    private static func openRow(_ entry: StoredNiggle, triage: NiggleTriageResult, entries: [StoredNiggle],
                                rules: [StoredTriageRule], rulesNeedAttention: Bool) -> NiggleOpenRow {
        let label = triage.status == .matched ? rules.first { $0.id == triage.ruleId }?.label : nil
        var line: String?
        if rulesNeedAttention {
            line = String(localized: "Your rules need attention")
        } else {
            switch triage.status {
            case .noRulesEntered: line = String(localized: "No rules entered yet")
            case .noRuleMatches: line = String(localized: "None of your rules covers this")
            default: line = nil
            }
        }
        var next: String?
        if !rulesNeedAttention, let change = triage.nextChange {
            if let id = change.ruleId, let nextLabel = rules.first(where: { $0.id == id })?.label {
                next = String(localized: "Day \(change.dayCount): your rule \u{201C}\(nextLabel)\u{201D} applies")
            } else {
                next = String(localized: "Day \(change.dayCount): no rule of yours applies")
            }
        }
        let place = entry.location.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let before = entries.filter { other in
            other.id != entry.id && other.onsetDay < entry.onsetDay && other.side == entry.side
                && other.location.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == place
        }.count
        return NiggleOpenRow(
            id: entry.id, location: entry.location, sideText: sideText(entry.side),
            dayCountText: triage.dayCount.map { String(localized: "Day \($0)") } ?? CutScorecardPresenter.missingValue,
            label: label, actionText: label == nil ? nil : triage.action.map { actionText($0, locale: .current) },
            disclaimer: label == nil ? nil : String(localized: "Your rule, applied to what you logged. This is not a diagnosis."),
            triageLine: label == nil ? line : nil, nextChangeLine: next,
            recurrenceText: before > 0 ? String(localized: "Logged before: \(before) times") : nil)
    }

    private static func pausedRow(_ pause: StoredPausedExercise, _ words: CutScorecardPresenter.Wording) -> NigglePausedRow {
        NigglePausedRow(id: pause.id, exercise: pause.exercise, reason: pause.reason,
                        sinceText: String(localized: "since \(words.shortDate(pause.pausedDay))"),
                        untilText: pause.until,
                        resumedText: pause.resumedDay.map { String(localized: "Resumed \(words.shortDate($0))") },
                        niggleId: pause.niggleId)
    }

    private static func resolvedAfterText(_ days: Int) -> String {
        String(localized: "Resolved after \(days) days")
    }

    private static func rangeText(_ from: String, _ to: String, _ words: CutScorecardPresenter.Wording) -> String {
        String(localized: "\(words.shortDate(from)) to \(words.shortDate(to))")
    }

    /// The rule of §7.1 step 4: an update is used when dated from onset to today, and not after the
    /// resolved day.
    private static func isUsed(_ update: StoredNiggleUpdate, of entry: StoredNiggle, today: String) -> Bool {
        CanonicalDay.isValid(update.day) && update.day >= entry.onsetDay && update.day <= today
            && (entry.resolvedDay.map { update.day <= $0 } ?? true)
    }
}

/// The date controls of the stage 6 sheets work in instants; the stored values are day keys. These
/// two conversions are the only place a sheet's date becomes a key and back, so no view formats one.
enum Stage6DayPicker {
    /// Noon of a canonical day key in `timeZone`; nil for a key that names no day.
    static func date(forDay day: String, timeZone: TimeZone) -> Date? {
        guard CanonicalDay.isValid(day) else { return nil }
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// The day key `date` falls on in `timeZone`.
    static func day(for date: Date, timeZone: TimeZone) -> String {
        LocalDayWindows(timeZone: timeZone).dayKey(for: date)
    }
}

/// The one-line descriptions of the three stage 6 Settings cards (§10.1, §11), and the Recovery
/// context title as the Settings card and the scorecard link show it (neither names the cut-stress
/// types beyond their flag, §12.4).
enum Stage6SettingsText {
    static var recoveryContextTitle: String { String(localized: "Recovery context") }
    static var niggleLogBlurb: String {
        String(localized: "Record a complaint and see it against your own rules. Off by default.")
    }
    static var recoveryContextBlurb: String {
        String(localized: "Weekly resting heart rate and HRV beside the scorecard. Not a score.")
    }
    static var timelineBlurb: String {
        String(localized: "Phases, checkpoints and your estimate in one list.")
    }
}
