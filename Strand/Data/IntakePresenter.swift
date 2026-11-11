import Foundation
import StrandAnalytics

/// Turns the intake values into what the card, the screen, the widget and the forms show (stage 3
/// specification §10, §11). Every state is decided here, once; the views draw the result. Every
/// sentence is an English source string resolved through the app's String Catalog. None states or
/// implies a health outcome, praises, warns or urges.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
enum IntakePresenter {
    /// Seconds after its read time at which a Health figure is drawn as stale (question I8).
    static let staleAfter: TimeInterval = 3 * 3600
    /// The days the history chart covers, ending on the shown day.
    static let chartDays = 28

    // MARK: - Strings

    static var cardTitle: String { String(localized: "Protein") }
    static var cardSubtitle: String { String(localized: "Today against your floor") }
    static var settingsTitle: String { String(localized: "Intake") }
    static var settingsBlurb: String {
        String(localized: "Protein and calories against your own floor and range. Off by default. Everything stays on this iPhone.")
    }
    static var energyTitle: String { String(localized: "Calories eaten") }
    static var quickAddSaveFailed: String { String(localized: "Could not save. Nothing was changed.") }
    static var supplementsCaption: String { String(localized: "Supplements listed here are left out of the Coach.") }
    static var invalidAmountMessage: String { String(localized: "Enter a number from 0 to 100000") }
    static var refusedFloorMessage: String { String(localized: "Enter whole grams") }
    static var silentNearWindDown: String {
        String(localized: "Silent on days when it falls within 30 minutes of your wind-down reminder.")
    }
    static var targetsNeedAttention: String { String(localized: "Your targets need attention") }
    static var setupPrompt: String { String(localized: "Choose where intake comes from") }
    static var appleHealthName: String { String(localized: "Apple Health") }
    static var enteredHere: String { String(localized: "Entered here") }
    static var csvImport: String { String(localized: "CSV import") }

    /// The three setup sentences, in the order of `setupSources`.
    static var setupChoices: [String] {
        [String(localized: "Apple Health: read what your food app writes"),
         String(localized: "Enter here: add protein and calories yourself"),
         String(localized: "None: supplements and the cutoff reminder only")]
    }
    static let setupSources: [IntakeSourceSetting] = [.appleHealth, .quickAdd, .none]

    /// The name of a source choice in Settings.
    static func sourceName(_ source: IntakeSourceSetting) -> String {
        switch source {
        case .none: return String(localized: "None")
        case .appleHealth: return appleHealthName
        case .quickAdd: return String(localized: "Enter here")
        }
    }

    /// "HH:mm" in a 24-hour locale; the locale's own hour format otherwise.
    static func timeText(_ date: Date, timeZone: TimeZone, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        return formatter.string(from: date)
    }

    private static func whole(_ value: Int, _ locale: Locale) -> String {
        value.formatted(.number.locale(locale))
    }

    // MARK: - The card (§10.1)

    static func loadingCard() -> IntakeCard {
        IntakeCard(status: .loading, value: nil, unit: nil, caption: nil, ring: nil, floorGrams: nil,
                   isDimmed: false, opensIntake: false)
    }

    /// Caption precedence where two states apply (design round S3, decision 5): no source, past day,
    /// read failed with nothing stored, targets unreadable, no floor, not measured, stale, then
    /// below, at or above the floor.
    static func card(_ input: IntakePresenterInput, clock: IntakeClock, timeZone: TimeZone,
                     locale: Locale) -> IntakeCard {
        if input.isLoading { return loadingCard() }
        let protein = input.resolved?.protein
        let progress = IntakeProgress.protein(grams: protein?.value, floorGrams: input.floorGrams)
        let value = progress.shownGrams.map { whole($0, locale) }
        func card(_ status: IntakeCard.Status, value: String?, caption: String, ring: Double?,
                  dimmed: Bool = false) -> IntakeCard {
            IntakeCard(status: status, value: value, unit: value == nil ? nil : "g", caption: caption, ring: ring,
                       floorGrams: progress.shownFloorGrams, isDimmed: dimmed, opensIntake: true)
        }

        if input.source == .none {
            return IntakeCard(status: .noSource, value: nil, unit: nil, caption: setupPrompt, ring: nil,
                              floorGrams: progress.shownFloorGrams, isDimmed: false, opensIntake: true)
        }
        if input.day != clock.today {
            guard let protein, value != nil else {
                return card(.pastDayNotMeasured, value: nil, caption: String(localized: "Not measured"), ring: nil)
            }
            return card(.pastDay, value: value, caption: joined(String(localized: "Day total"), csvTag(protein)),
                        ring: progress.ringFraction)
        }
        if protein == nil, input.source == .appleHealth, input.lastHealthOutcome == .failedRead {
            return card(.readFailed, value: nil, caption: String(localized: "Could not read Apple Health"), ring: nil)
        }
        if input.targetsNeedAttention {
            return card(.targetsNeedAttention, value: value, caption: targetsNeedAttention, ring: progress.ringFraction)
        }
        switch progress.state {
        case .noFloor:
            return card(.noFloor, value: value, caption: String(localized: "No floor set"), ring: nil)
        case .notMeasured:
            return card(.notMeasured, value: nil, caption: String(localized: "Nothing logged today"), ring: 0)
        case .below, .atFloor, .above:
            guard let protein else { break }
            if isStale(protein, clock: clock), let readAt = protein.readAtEpochSeconds {
                let time = timeText(Date(timeIntervalSince1970: TimeInterval(readAt)), timeZone: timeZone, locale: locale)
                return card(.stale, value: value, caption: String(localized: "Last read \(time)"),
                            ring: progress.ringFraction, dimmed: true)
            }
            let tail = protein.source == .nutritionCsv ? String(localized: "imported")
                : protein.readAtEpochSeconds.map {
                    timeText(Date(timeIntervalSince1970: TimeInterval($0)), timeZone: timeZone, locale: locale)
                }
            return card(status(progress.state), value: value, caption: joined(proteinLine(progress), tail),
                        ring: progress.ringFraction)
        }
        return card(.notMeasured, value: nil, caption: String(localized: "Nothing logged today"), ring: 0)
    }

    private static func status(_ state: IntakeProteinState) -> IntakeCard.Status {
        switch state {
        case .below: return .below
        case .atFloor: return .atFloor
        case .above: return .above
        case .noFloor: return .noFloor
        case .notMeasured: return .notMeasured
        }
    }

    /// The protein line for a measured day against a floor.
    private static func proteinLine(_ progress: IntakeProteinProgress) -> String {
        switch progress.state {
        case .below: return String(localized: "\(progress.remainingGrams ?? 1) g to your floor")
        case .atFloor: return String(localized: "Floor met")
        case .above: return String(localized: "+\(progress.overGrams ?? 0) g over your floor")
        case .noFloor: return String(localized: "No floor set")
        case .notMeasured: return String(localized: "Nothing logged today")
        }
    }

    /// A Health figure for today read at least `staleAfter` before the clock's now. Only a Health
    /// figure goes stale: an entry made here is as fresh as its last change.
    private static func isStale(_ value: ResolvedIntakeValue, clock: IntakeClock) -> Bool {
        guard value.source == .appleHealth, let readAt = value.readAtEpochSeconds else { return false }
        return clock.now.timeIntervalSince1970 - TimeInterval(readAt) >= staleAfter
    }

    private static func csvTag(_ value: ResolvedIntakeValue) -> String? {
        value.source == .nutritionCsv ? String(localized: "imported") : nil
    }

    private static func joined(_ head: String, _ tail: String?) -> String {
        guard let tail, !tail.isEmpty else { return head }
        return head + " · " + tail
    }

    // MARK: - The screen (§10.2)

    static func screen(_ input: IntakePresenterInput, clock: IntakeClock, timeZone: TimeZone,
                       locale: Locale) -> IntakeScreenModel {
        if input.isLoading { return IntakeScreenModel(layout: .loading) }
        if input.source == .none {
            guard input.sourceChosen else { return IntakeScreenModel(layout: .setup, setupChoices: setupChoices) }
            return IntakeScreenModel(layout: .supplementsOnly, showsCutoffRow: true)
        }
        var model = IntakeScreenModel(layout: .full)
        let isToday = input.day == clock.today
        let protein = input.resolved?.protein
        let energy = input.resolved?.energy
        let progress = IntakeProgress.protein(grams: protein?.value, floorGrams: input.floorGrams)

        // Protein: the numbers and the ring.
        let line: String
        let ring: Double?
        if !isToday {
            line = progress.shownGrams == nil ? String(localized: "Not measured") : String(localized: "Day total")
            ring = progress.ringFraction
        } else {
            line = proteinLine(progress)
            ring = progress.state == .notMeasured ? 0 : progress.ringFraction
        }
        model.protein = IntakeScreenModel.Protein(value: progress.shownGrams.map { whole($0, locale) },
                                                  floorGrams: progress.shownFloorGrams, line: line, ring: ring,
                                                  showsSetFloorRow: progress.state == .noFloor)

        // Calories eaten: a past day is closed; today closes at the owner's cutoff (§7.5).
        let dayIsOpen = isToday && clock.dayIsOpen
        let energyProgress = IntakeProgress.energy(kcal: energy?.value, targets: input.targets, dayIsOpen: dayIsOpen)
        model.energy = IntakeScreenModel.Energy(
            title: energyTitle, state: energyProgress.state,
            value: energyProgress.shownKcal.map { dayIsOpen ? String(localized: "\($0) kcal so far") : String(localized: "\($0) kcal") },
            line: energyLine(energyProgress, targets: input.targets, attention: input.targetsNeedAttention))

        model.chart = chart(input, endingOn: input.day)

        // Source and freshness: of the protein figure, or of the energy figure when protein has none.
        let shown = protein ?? energy
        if let shown {
            switch shown.source {
            case .appleHealth:
                model.sourceLine = input.healthAppNamesOnDay.count == 1
                    ? String(localized: "From \(input.healthAppNamesOnDay[0])") : appleHealthName
            case .quickAdd: model.sourceLine = enteredHere
            case .nutritionCsv: model.sourceLine = csvImport
            }
            if let readAt = shown.readAtEpochSeconds {
                let time = timeText(Date(timeIntervalSince1970: TimeInterval(readAt)), timeZone: timeZone, locale: locale)
                switch shown.source {
                case .appleHealth:
                    let stale = isToday && isStale(shown, clock: clock)
                    model.freshness = stale ? String(localized: "Last read \(time)") : String(localized: "Read \(time)")
                    model.freshnessIsStale = stale
                case .quickAdd: model.freshness = String(localized: "Entered \(time)")
                case .nutritionCsv: model.freshness = String(localized: "imported")
                }
            } else if shown.source == .nutritionCsv {
                model.freshness = String(localized: "imported")
            }
            if shown.source == .appleHealth {
                let app = input.foodAppName ?? input.healthAppNamesOnDay.first ?? appleHealthName
                model.correction = String(localized: "Edit this in \(app). NOOP reads it again when you return.")
                if input.healthAppNamesOnDay.count >= 2 {
                    model.twoApps = String(localized:
                        "Two apps wrote today: \(input.healthAppNamesOnDay[0]) and \(input.healthAppNamesOnDay[1]). Both are counted.")
                    model.showsChooseOne = true
                }
            }
            model.showsDataSourcesRow = shown.source == .nutritionCsv
        } else {
            switch input.source {
            case .appleHealth: model.sourceLine = appleHealthName
            case .quickAdd: model.sourceLine = enteredHere
            case .none: break
            }
        }

        if input.source == .appleHealth {
            model.showsReadAgain = true
            switch input.lastHealthOutcome {
            case .failedRead:
                let time = input.lastHealthAttemptAt.map { timeText($0, timeZone: timeZone, locale: locale) } ?? "—"
                model.problem = String(localized: "Apple Health could not be read at \(time). Showing the last figures.")
            case .preserved:
                let app = input.foodAppName ?? input.healthAppNamesOnDay.first ?? String(localized: "your food app")
                model.problem = String(localized:
                    "Apple Health returned no food entries. If you log in \(app), check that it is allowed to write to Health.")
            default: break
            }
        }
        if input.targetsNeedAttention { model.attention = targetsNeedAttention }
        model.entries = input.entries
        model.showsRestoredTotal = input.restoredTotal != nil
        return model
    }

    private static func energyLine(_ progress: IntakeEnergyProgress, targets: IntakeTargets, attention: Bool) -> String? {
        let low = targets.energyLowKcal.map { Int(CutScorecard.quantize($0).rounded()) }
        let high = targets.energyHighKcal.map { Int(CutScorecard.quantize($0).rounded()) }
        let hard = targets.energyHardFloorKcal.map { Int(CutScorecard.quantize($0).rounded()) }
        switch progress.state {
        case .notMeasured: return String(localized: "Not measured")
        // A stored range that cannot be read is not "no range": the attention line says so instead.
        case .noRange: return attention ? nil : String(localized: "No range set")
        case .soFar: return String(localized: "\(progress.toLowEndKcal ?? 0) kcal to the bottom of your range")
        case .aboveRange: return String(localized: "\(progress.overHighEndKcal ?? 0) kcal above your range")
        case .belowHardFloor: return hard.map { String(localized: "Below your floor of \($0) kcal") }
        case .belowRange:
            guard let low else { return nil }
            guard let high else { return String(localized: "\(progress.toLowEndKcal ?? 0) kcal to the bottom of your range") }
            return String(localized: "Below your range of \(low) to \(high) kcal")
        case .inRange:
            guard let low, let high else { return nil }
            return String(localized: "In your range of \(low) to \(high) kcal")
        }
    }

    /// The last 28 days ending on `day`, oldest first. An unmeasured day is a gap, never zero.
    private static func chart(_ input: IntakePresenterInput, endingOn day: String) -> IntakeScreenModel.Chart? {
        guard let end = CanonicalDay.number(day) else { return nil }
        var grams: [String: Double] = [:]
        for resolved in input.history { if let value = resolved.protein?.value { grams[resolved.day] = value } }
        if let today = input.resolved?.protein?.value { grams[day] = today }
        let floor = input.floorGrams.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let points = (0..<chartDays).map { offset -> IntakeScreenModel.ChartPoint in
            let key = CanonicalDay.key(end - (chartDays - 1) + offset)
            let value = grams[key]
            let meets = value.flatMap { value in floor.map { IntakeProgress.meetsFloor(grams: value, floorGrams: $0) } }
            return IntakeScreenModel.ChartPoint(day: key, grams: value, meetsFloor: meets)
        }
        let measured = points.filter { $0.grams != nil }.count
        return IntakeScreenModel.Chart(points: points,
                                       message: measured < 2 ? String(localized: "More days will appear here") : nil)
    }

    // MARK: - The widget reading (§8.4, §10.8)

    /// What the widget may show for `input.day`; nil when Intake is off or has no source. A figure
    /// without its time, and a CSV figure (which has none), is published as not measured.
    static func widgetReading(_ input: IntakePresenterInput, clock: IntakeClock,
                              flagEnabled: Bool) -> IntakeWidgetValues? {
        guard flagEnabled, input.source != .none else { return nil }
        var shown: ResolvedIntakeValue?
        if let protein = input.resolved?.protein, protein.source != .nutritionCsv, protein.readAtEpochSeconds != nil {
            shown = protein
        }
        let progress = IntakeProgress.protein(grams: shown?.value, floorGrams: input.floorGrams)
        let source: IntakeWidgetSource?
        switch shown?.source ?? (input.source == .quickAdd ? .quickAdd : .appleHealth) {
        case .appleHealth: source = .appleHealth
        case .quickAdd: source = .quickAdd
        case .nutritionCsv: source = nil
        }
        return IntakeWidgetValues(day: input.day, proteinGrams: progress.shownGrams,
                                  floorGrams: progress.shownFloorGrams, remainingGrams: progress.remainingGrams,
                                  source: source,
                                  readAt: shown?.readAtEpochSeconds.map { Date(timeIntervalSince1970: TimeInterval($0)) })
    }

    // MARK: - Quick-add sheet (§10.3)

    /// One amount field. Empty: no amount. Valid: a finite number from 0 to 100 000.
    static func amountEntry(_ text: String) -> IntakeAmountEntry {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        guard let value = Double(trimmed), IntakeQuickAddStore.isValidAmount(value) else {
            return .invalid(message: invalidAmountMessage)
        }
        return .amount(value)
    }

    /// Save is enabled when at least one field holds an amount and neither is invalid.
    static func canSaveQuickAdd(protein: IntakeAmountEntry, energy: IntakeAmountEntry) -> Bool {
        for entry in [protein, energy] { if case .invalid = entry { return false } }
        let hasAmount: (IntakeAmountEntry) -> Bool = { if case .amount = $0 { return true }; return false }
        return hasAmount(protein) || hasAmount(energy)
    }

    /// The backdating picker: today and the seven days before it, today first (the Journal's reach).
    static func quickAddDays(today: String) -> [String] {
        guard let number = CanonicalDay.number(today) else { return [today] }
        return (0...7).map { CanonicalDay.key(number - $0) }
    }

    // MARK: - Settings (§10.5)

    /// The floor field: empty is no floor; otherwise valid exactly when stage 1's rule accepts it.
    /// The typed value is never rounded.
    static func floorEntry(_ text: String) -> IntakeFloorEntry {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .noFloor }
        guard let value = Double(trimmed), CutScorecardSettings.isWholeGramProteinFloor(value) else {
            return .invalid(message: refusedFloorMessage)
        }
        return .grams(value)
    }

    /// The calorie range and hard floor fields; an empty field leaves its key absent.
    static func rangeEntry(low: String, high: String, hardFloor: String) -> IntakeRangeEntry {
        func parse(_ text: String) -> Double?? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return .some(nil) }
            guard let value = Double(trimmed) else { return nil }
            return .some(value)
        }
        guard let low = parse(low), let high = parse(high), let hard = parse(hardFloor) else { return .invalid }
        let targets = IntakeTargets(energyLowKcal: low, energyHighKcal: high, energyHardFloorKcal: hard)
        return targets.isValid ? .valid(targets) : .invalid
    }

    /// Why a range entry was refused, for the mark under the fields.
    static func rangeMessage(low: String, high: String, hardFloor: String) -> String? {
        guard case .invalid = rangeEntry(low: low, high: high, hardFloor: hardFloor) else { return nil }
        let l = Double(low.trimmingCharacters(in: .whitespaces))
        let h = Double(high.trimmingCharacters(in: .whitespaces))
        let f = Double(hardFloor.trimmingCharacters(in: .whitespaces))
        if let l, let h, l > h { return String(localized: "The low end is above the high end. Nothing was saved.") }
        if let l, let f, f > l { return String(localized: "The hard floor is above the low end. Nothing was saved.") }
        return invalidAmountMessage
    }

    /// The sentence under the cutoff reminder switch.
    static func cutoffReminderNote(isOn: Bool) -> String {
        isOn ? String(localized: "One notification a day. It never contains an amount, a floor or a supplement name.")
            : String(localized: "The reminder is off unless you turn it on. One notification a day, at your cutoff time.")
    }

    /// The rows of the Intake card, top to bottom. With the flag off only the switch.
    static func settingsRows(flagEnabled: Bool, source: IntakeSourceSetting, knownHealthAppCount: Int,
                             supplementCount: Int) -> [IntakeSettingsRow] {
        guard flagEnabled else { return [.featureSwitch] }
        var rows: [IntakeSettingsRow] = [.featureSwitch, .source, .proteinFloor, .calorieRange, .hardFloor]
        if source == .appleHealth, knownHealthAppCount > 1 { rows.append(.appsToCount) }
        if supplementCount > 0 { rows.append(.supplements) }
        if supplementCount < IntakeSettings.maxSupplements { rows.append(.addSupplement) }
        rows += [.cutoffTime, .cutoffReminder]
        return rows
    }

    /// The caption under the source row while the source is None; nil otherwise.
    static func sourceNoneCaption(flagEnabled: Bool, source: IntakeSourceSetting) -> String? {
        guard flagEnabled, source == .none else { return nil }
        return String(localized: "With no source, the Protein card and widget have nothing to show.")
    }

    // MARK: - Supplements (§10.6)

    static func supplementRows(questions: [String], states: [String: Bool?],
                               displayName: (String) -> String) -> [IntakeSupplementRow] {
        questions.map { question in
            let state = states[question] ?? nil
            return IntakeSupplementRow(question: question, name: displayName(question), isTicked: state == true,
                                       caption: state == false ? String(localized: "Marked not taken in Journal") : nil)
        }
    }

    /// The supplement's name as typed: the canonical question without "Did you take" and "?".
    static func supplementName(question: String) -> String {
        let prefix = "Did you take "
        guard question.hasPrefix(prefix), question.hasSuffix("?"), question.count > prefix.count + 1 else { return question }
        return String(question.dropFirst(prefix.count).dropLast())
    }

    // MARK: - Cutoff reminder (§10.7)

    /// The caption under the reminder row: present when any weekday is silent.
    static func cutoffReminderCaption(_ triggers: [IntakeCutoffPlan.Trigger]) -> String? {
        triggers.contains { !$0.playsSound } ? silentNearWindDown : nil
    }

    // MARK: - Scorecard protein row (§10.4)

    /// The source caption of the scorecard's protein row; nil with the intake flag off, so the row
    /// is exactly stage 1's.
    static func scorecardProteinCaption(flagEnabled: Bool, sources: [IntakeSource]) -> String? {
        guard flagEnabled, let first = sources.first else { return nil }
        guard sources.allSatisfy({ $0 == first }) else { return String(localized: "Several sources") }
        switch first {
        case .appleHealth: return appleHealthName
        case .quickAdd: return enteredHere
        case .nutritionCsv: return csvImport
        }
    }
}
