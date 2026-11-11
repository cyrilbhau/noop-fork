import Foundation
import Combine
import StrandAnalytics
import WhoopStore

// Stage 1 (weigh-in and scorecard), specification §10: everything below the scorecard views. The
// views live in StrandiOS; every rule they follow is held by a type in this file so that it can be
// tested without a view, and so that the card, the Health row and the screen read one object.

// MARK: - The feature flag

/// The one observable copy of `noop.cutScorecardEnabled` (ruling R40). Today, Settings and the card
/// editor observe this object; reading it never writes the key. The observation itself is
/// `ObservableDefaultsFlag`'s: `isEnabled`, `$isEnabled` and `set(_:)` are inherited from it.
@MainActor
final class CutScorecardFlag: ObservableDefaultsFlag {
    /// The app's copy, over the standard defaults.
    static let shared = CutScorecardFlag()

    init(defaults: UserDefaults = .standard) {
        super.init(key: CutScorecardSettings.enabledKey, defaults: defaults)
    }

    /// The policy a Today weight resolves under while the flag has this value.
    var displayPolicy: BodyMeasurementPolicy {
        BodyMeasurementResolver.policy(flagEnabled: isEnabled, consumer: .display)
    }
}

// MARK: - Scorecard screen and card

/// The scorecard screen, the Today card and the Health row read this one object.
@MainActor
final class CutScorecardModel: ObservableObject {
    enum State: Equatable {
        case idle, loading
        case loaded(CutScorecardPresentation)
    }

    /// `.idle` until the first load, and whenever the flag is off.
    @Published private(set) var state: State = .idle

    private let repository: Repository
    private let provider: BodyMeasurementProvider
    private let settings: CutScorecardSettings
    private let unitSystem: () -> UnitSystem
    private let now: () -> Date
    private let timeZone: () -> TimeZone
    private let locale: () -> Locale
    private let evaluate: (@MainActor (_ today: String) async -> CutScorecardEvaluation)?
    /// Counts loads. A load publishes only while it is still the latest one.
    private var generation = 0
    private var revisionObserver: AnyCancellable?
    /// The weekly reminder, told the newest weigh-in day after each result so that a week which
    /// already has its weigh-in is not reminded. Nil in tests; the app's shared model sets it.
    var reminder: WeighInReminder?

    /// `evaluate` nil: the stored readings, lifts, protein, phase and rules through
    /// `CutScorecardInputBuilder.evaluation(today:)`, the one evaluation the coach packet also calls.
    init(repository: Repository, provider: BodyMeasurementProvider, settings: CutScorecardSettings,
         unitSystem: @escaping () -> UnitSystem,
         now: @escaping () -> Date = { Date() },
         timeZone: @escaping () -> TimeZone = { TimeZone.current },
         locale: @escaping () -> Locale = { AppLanguage.activeLocale },
         evaluate: (@MainActor (_ today: String) async -> CutScorecardEvaluation)? = nil) {
        self.repository = repository
        self.provider = provider
        self.settings = settings
        self.unitSystem = unitSystem
        self.now = now
        self.timeZone = timeZone
        self.locale = locale
        self.evaluate = evaluate
    }

    // MARK: The app's shared instance

    private static var liveModel: (model: CutScorecardModel, repository: Repository, profile: ProfileStore)?

    /// The model the Today card, the Health row and the scorecard screen share. Created on first
    /// use, which only happens while the flag is on.
    static func live(repository: Repository, profile: ProfileStore) -> CutScorecardModel {
        if let held = liveModel, held.repository === repository, held.profile === profile { return held.model }
        let model = CutScorecardModel(
            repository: repository,
            provider: BodyMeasurementProvider.live(repository: repository, profile: profile),
            settings: CutScorecardSettings(),
            unitSystem: {
                UnitSystem(rawValue: UserDefaults.standard.string(forKey: UnitPrefs.systemKey) ?? "") ?? .metric
            })
        model.reminder = WeighInReminder.live
        liveModel = (model, repository, profile)
        return model
    }

    /// The Today card for the current state: a skeleton until the first result.
    var card: CutScorecardCard {
        if case .loaded(let presentation) = state { return presentation.card }
        return CutScorecardPresenter.loadingCard()
    }

    // MARK: Loading

    /// Flag off: `.idle`, and nothing is read. Flag on: `.loading` on the first load, then
    /// `.loaded`. A load that finishes after a later one began publishes nothing.
    func load() async {
        generation += 1
        let request = generation
        guard settings.isEnabled else {
            if state != .idle { state = .idle }
            return
        }
        // Captured before the first suspension, so one load describes one moment.
        let today = LocalDayWindows(timeZone: timeZone()).dayKey(for: now())
        let system = unitSystem()
        let shownLocale = locale()
        let attention = settings.rulesNeedAttention
        let storedPhaseName = settings.activePhase(on: today)?.name
        if state == .idle { state = .loading }
        // Before the snapshot is read: a change published while this load is still evaluating then
        // starts another load, instead of being missed.
        followProvider()

        let evaluation: CutScorecardEvaluation
        if let evaluate {
            evaluation = await evaluate(today)
        } else {
            evaluation = await CutScorecardInputBuilder(repository: repository, provider: provider,
                                                        settings: settings, timeZone: timeZone)
                .evaluation(today: today)
        }
        guard request == generation else { return }
        guard settings.isEnabled else {
            state = .idle
            return
        }
        // The source of the weight the result calls current: the provider's reading of that day.
        let source = evaluation.result.currentWeightDay.flatMap { day in
            provider.series(.weight, consumer: .display).last { $0.day == day }?.source
        } ?? .labBook
        let context = CutScorecardPresentationContext(
            unitSystem: system, weightSource: source, rulesNeedAttention: attention, locale: shownLocale,
            storedPhaseName: storedPhaseName)
        let presentation = CutScorecardPresenter.present(evaluation.result, input: evaluation.input, context: context)
        if state != .loaded(presentation) { state = .loaded(presentation) }
        // A weigh-in saved or deleted reaches the reminder here: every such write reloads this model.
        await reminder?.reconcile(latestWeighInDay: evaluation.result.currentWeightDay)
    }

    /// From the first load with the flag on, a changed provider snapshot reloads the model (ruling
    /// R32): that is how a saved, edited or deleted weigh-in reaches the card and the screen. The
    /// generation guard stops the load it overtakes from publishing.
    private func followProvider() {
        guard revisionObserver == nil else { return }
        revisionObserver = provider.$revision.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in await self?.load() }
        }
    }
}

// MARK: - Weigh-in sheet

/// Why a typed weight or waist cannot be saved.
enum WeighInFieldIssue: Equatable { case notANumber, belowMinimum, aboveMaximum }

/// The weigh-in sheet (specification §10.3): step 1 weight, step 2 waist, one instant for both.
/// Nothing is written until `save()` or `skipWaist()`.
@MainActor
final class WeighInSheetModel: ObservableObject {
    enum Step: Equatable { case weight, waist }
    enum Phase: Equatable { case editing, saving, failed, saved }

    @Published var weightText: String
    @Published var waistText: String
    @Published var takenAt: Date
    @Published private(set) var step: Step
    @Published private(set) var phase: Phase = .editing

    private let weighIns: WeighInStore
    /// The one source of the current weight and waist (ruling R41). Nil: the sheet offers the
    /// newest Lab Book row, as it did before the provider was handed to it.
    private let provider: BodyMeasurementProvider?
    private let unitSystem: UnitSystem
    private let now: () -> Date
    private let timeZone: () -> TimeZone
    private let locale: Locale
    private let words: CutScorecardPresenter.Wording
    private let isEditing: Bool
    /// The stored rows an edit acts on. Replaced by what each edit returns, so a retry after a
    /// partial failure acts on the rows as they now are.
    private var editedWeightRow: LabMarkerRow?
    private var editedWaistRow: LabMarkerRow?
    /// What each field showed when an edit opened: the stored value rounded for display. A field
    /// still showing it was not changed, and is never written back from that rounded text.
    private let seededWeightText: String?
    private let seededWaistText: String?
    /// The reading of each kind offered in the field: with a provider the value every other
    /// surface shows as current, with its source; else the newest Lab Book row. Nil while editing.
    private var lastWeight: OfferedReading?
    private var lastWaist: OfferedReading?
    /// Why the last save was refused before anything was written, when the general message would
    /// not say what to change. Nil otherwise.
    private var refusal: String?
    /// Every usable weight reading, for the note about the week the instant falls in.
    private var weightReadings: [(day: String, takenAt: Int, kg: Double, id: String)] = []

    /// A reading offered in a field: its number, its day and, when known, the name of its source.
    private typealias OfferedReading = (text: String, day: String, source: String?)

    init(weighIns: WeighInStore, provider: BodyMeasurementProvider? = nil, unitSystem: UnitSystem,
         now: @escaping () -> Date = { Date() },
         timeZone: @escaping () -> TimeZone = { TimeZone.current },
         locale: Locale = AppLanguage.activeLocale,
         editing: WeighInHistoryRow? = nil) {
        self.weighIns = weighIns
        self.provider = provider
        self.unitSystem = unitSystem
        self.now = now
        self.timeZone = timeZone
        self.locale = locale
        words = CutScorecardPresenter.Wording(unitSystem: unitSystem, locale: locale)
        isEditing = editing != nil
        editedWeightRow = editing?.weightRow
        editedWaistRow = editing?.waistRow
        seededWeightText = editing?.weightText
        seededWaistText = editing?.waistText
        weightText = editing?.weightText ?? ""
        waistText = editing?.waistText ?? ""
        takenAt = editing?.takenAt.map { Date(timeIntervalSince1970: Double($0)) } ?? now()
        // A reading that is a waist only has no weight step.
        step = editing != nil && editing?.weightRow == nil ? .waist : .weight
    }

    /// Reads the earlier readings: the offer in each field, the hints and the week note. Writes
    /// nothing.
    func prepare() async {
        let weights = await weighIns.readings(.weight)
        let waists = await weighIns.readings(.waist)
        let editedId = editedWeightRow?.id
        weightReadings = weights.compactMap { row in
            guard row.id != editedId,
                  let kg = BodyMeasurementResolver.normalizedValue(of: row, as: .weight) else { return nil }
            return (day: row.day, takenAt: row.takenAt, kg: kg, id: row.id)
        }
        guard !isEditing else { return }
        // Ruling R41: the value offered is the one every other surface shows as current, so the
        // sheet holds no second answer to "the last weight". An undated profile value is no reading.
        if let provider, provider.displayPolicy == .unified {
            lastWeight = offer(provider.current(.weight, consumer: .display))
            lastWaist = offer(provider.current(.waist, consumer: .display))
            if weightText.isEmpty, let lastWeight { weightText = lastWeight.text }
            if waistText.isEmpty, let lastWaist { waistText = lastWaist.text }
            return
        }
        if let newest = weightReadings.max(by: { ($0.takenAt, $0.id) < ($1.takenAt, $1.id) }) {
            lastWeight = (words.weightNumber(newest.kg), newest.day, nil)
            if weightText.isEmpty { weightText = words.weightNumber(newest.kg) }
        }
        let usableWaists = waists.compactMap { row in
            BodyMeasurementResolver.normalizedValue(of: row, as: .waist).map { (row: row, cm: $0) }
        }
        if let newest = usableWaists.max(by: { ($0.row.takenAt, $0.row.id) < ($1.row.takenAt, $1.row.id) }) {
            lastWaist = (words.lengthNumber(newest.cm), newest.row.day, nil)
            if waistText.isEmpty { waistText = words.lengthNumber(newest.cm) }
        }
    }

    /// The provider's current value as an offer: only a dated reading, named by its source.
    private func offer(_ current: ResolvedBodyMeasurement?) -> OfferedReading? {
        guard let current, let day = current.day else { return nil }
        let text = current.kind == .weight ? words.weightNumber(current.value) : words.lengthNumber(current.value)
        return (text, day, CutScorecardPresenter.sourceCaption(current.source))
    }

    // MARK: Fields

    var weightUnit: String { words.weightUnit }
    var waistUnit: String { words.lengthUnit }

    /// Nil for an empty field and for a valid one.
    var weightIssue: WeighInFieldIssue? { issue(weightText, kind: .weight) }
    var waistIssue: WeighInFieldIssue? { issue(waistText, kind: .waist) }

    var weightHint: String { hint(weightText, kind: .weight, last: lastWeight, namesRange: false) }
    var weightHintIsError: Bool { weightIssue != nil }
    var waistHint: String {
        if isEditing, editedWaistRow == nil {
            return String(localized: "This reading has no waist. Log a new weigh-in to add one.")
        }
        return hint(waistText, kind: .waist, last: lastWaist, namesRange: true)
    }
    var waistHintIsError: Bool { waistIssue != nil }

    /// False for a reading being edited that has no stored waist: stage 1 adds a waist only with a
    /// new weigh-in.
    var canEditWaist: Bool { !isEditing || editedWaistRow != nil }

    var dateIsInTheFuture: Bool { takenAt > now() }
    var dateHint: String { String(localized: "Future dates cannot be picked.") }

    /// The week the reading will fall in when that is not this week, and what that week already
    /// holds. Nil when there is nothing to say.
    var dateNote: String? {
        let days = LocalDayWindows(timeZone: timeZone())
        let day = days.dayKey(for: takenAt)
        guard let week = CutScorecard.weekStart(containing: day) else { return nil }
        var parts: [String] = []
        if week != CutScorecard.weekStart(containing: days.dayKey(for: now())) {
            parts.append(String(localized: "Falls in the week of \(words.shortDate(week))."))
        }
        let held = weightReadings.filter { CutScorecard.weekStart(containing: $0.day) == week }
            .max { ($0.day, $0.takenAt, $0.id) < ($1.day, $1.takenAt, $1.id) }
        if let held {
            let logged = words.weight(held.kg)
            let on = words.date(held.day)
            // The latest reading of a week represents it.
            let isLater = (day, Int(takenAt.timeIntervalSince1970)) > (held.day, held.takenAt)
            parts.append(isLater
                ? String(localized: "You logged \(logged) on \(on). This reading will represent the week.")
                : String(localized: "You logged \(logged) on \(on). That reading will still represent the week."))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// "Next" on step 1.
    var canAdvance: Bool {
        step == .weight && phase != .saving && weightIsValid && !dateIsInTheFuture
    }

    /// "Save" on step 2: a valid waist with a valid weight. An empty waist is skipped, not saved.
    /// Editing a reading that has no waist, Save is the weight-only save.
    var canSave: Bool {
        guard step == .waist, phase != .saving, !dateIsInTheFuture else { return false }
        if editsWeightOnly { return weightIsValid }
        guard canEditWaist, weightIsValid || editsWaistOnly else { return false }
        if waistIsUnchanged { return true }
        return !waistText.trimmingCharacters(in: .whitespaces).isEmpty && waistIssue == nil
    }

    /// False exactly when the sheet edits a reading that has a weight and no waist: Save is then
    /// the weight-only save, so Skip would be a second button for the same thing.
    var offersSkip: Bool { !editsWeightOnly }

    var primaryTitle: String {
        guard step == .waist else { return String(localized: "Next") }
        switch phase {
        case .saving: return String(localized: "Saving…")
        case .failed: return String(localized: "Try again")
        case .editing, .saved: return String(localized: "Save")
        }
    }

    /// Only after a save was refused.
    var failureMessage: String? {
        phase == .failed ? refusal ?? String(localized: "Could not save. Your entries are still here.") : nil
    }

    /// What Skip does to a new weigh-in. Nil while editing: Skip then leaves a stored waist as it
    /// is, so the week does not become unmeasured.
    var skipNote: String? {
        isEditing ? nil
            : String(localized: "Saves the weight only. Waist for this week will read \"Not measured this week\".")
    }

    // MARK: Steps

    /// Step 1 to step 2. Writes nothing.
    func advance() {
        guard canAdvance else { return }
        step = .waist
    }

    func back() {
        guard phase != .saving, !editsWaistOnly else { return }
        step = .weight
    }

    /// Step 2: the weight and the waist, at one instant. A waist that was not changed in an edit
    /// is not written from its text: it keeps its stored value, as it does through Skip.
    func save() async {
        guard canSave else { return }
        await write(waist: editsWeightOnly || waistIsUnchanged ? nil : Self.parse(waistText, locale: locale))
    }

    /// Step 2: the weight only. A skipped waist was not measured and writes no row.
    func skipWaist() async {
        guard step == .waist, phase != .saving, weightIsValid, !dateIsInTheFuture else { return }
        await write(waist: nil)
    }

    // MARK: Internals

    private var editsWaistOnly: Bool { isEditing && editedWeightRow == nil }

    /// Stage 1 adds a waist only with a new weigh-in, so this edit can change the weight alone.
    private var editsWeightOnly: Bool { isEditing && editedWaistRow == nil && editedWeightRow != nil }

    /// An edit whose field still shows what it opened with. The comparison is of the text, so
    /// retyping the same figure also counts as unchanged.
    private var weightIsUnchanged: Bool { Self.isUnchanged(weightText, seed: seededWeightText) }
    private var waistIsUnchanged: Bool {
        editedWaistRow != nil && Self.isUnchanged(waistText, seed: seededWaistText)
    }

    private static func isUnchanged(_ text: String, seed: String?) -> Bool {
        guard let seed else { return false }
        return text.trimmingCharacters(in: .whitespaces) == seed.trimmingCharacters(in: .whitespaces)
    }

    /// A stored weight that was not changed is valid as it stands: the edit does not rewrite it.
    private var weightIsValid: Bool {
        if isEditing, editedWeightRow != nil, weightIsUnchanged { return true }
        return !weightText.trimmingCharacters(in: .whitespaces).isEmpty && weightIssue == nil
    }

    private func write(waist: Double?) async {
        // Captured before the write suspends.
        let weight = Self.parse(weightText, locale: locale)
        let instant = takenAt
        let system = unitSystem
        refusal = nil
        // Before any write: an edit that moves the instant carries each untouched value to the new
        // instant through the store, which accepts its own range only. A stored value outside it
        // (the Lab Book editor has no range) would fail after its partner had moved, leaving the
        // pair at two instants. Nothing is written then, and the message names the field.
        if let carried = carriedValueOutOfRange(to: Int(instant.timeIntervalSince1970), waist: waist) {
            refusal = Self.carriedRefusal(carried, limits: bounds(carried))
            phase = .failed
            return
        }
        phase = .saving
        do {
            if isEditing {
                let epoch = Int(instant.timeIntervalSince1970)
                if let row = editedWeightRow {
                    // An unchanged weight is never written from its rounded display text: it keeps
                    // its stored value, and is written at all only to follow a changed instant.
                    if weightIsUnchanged, let stored = BodyMeasurementResolver.normalizedValue(of: row, as: .weight) {
                        if row.takenAt != epoch {
                            editedWeightRow = try await weighIns.edit(row, value: stored, unitSystem: .metric,
                                                                      takenAt: instant)
                        }
                    } else if let weight {
                        editedWeightRow = try await weighIns.edit(row, value: weight, unitSystem: system,
                                                                  takenAt: instant)
                    }
                }
                if let row = editedWaistRow {
                    if let waist {
                        editedWaistRow = try await weighIns.edit(row, value: waist, unitSystem: system, takenAt: instant)
                    } else if row.takenAt != epoch,
                              let stored = BodyMeasurementResolver.normalizedValue(of: row, as: .waist) {
                        // The waist keeps its value and follows its weigh-in to the new instant.
                        editedWaistRow = try await weighIns.edit(row, value: stored, unitSystem: .metric, takenAt: instant)
                    }
                }
            } else {
                guard let weight else { throw WeighInError.weightOutOfRange }
                try await weighIns.save(weight: weight, waist: waist, unitSystem: system, takenAt: instant)
            }
            phase = .saved
        } catch {
            phase = .failed
        }
    }

    /// The kind whose stored value this edit would carry unchanged to `epoch` although the store
    /// would refuse it there: a value outside the store's range, or one it cannot read. Nil for a
    /// new weigh-in, for an edit that keeps the instant, and when every carried value is in range.
    /// `waist` is the waist about to be written, nil when the stored one is kept.
    private func carriedValueOutOfRange(to epoch: Int, waist: Double?) -> BodyMeasurementKind? {
        guard isEditing else { return nil }
        if let row = editedWeightRow, row.takenAt != epoch, weightIsUnchanged,
           let stored = BodyMeasurementResolver.normalizedValue(of: row, as: .weight),
           !WeighInStore.weightRangeKg.contains(stored) {
            return .weight
        }
        if let row = editedWaistRow, row.takenAt != epoch, waist == nil {
            guard let stored = BodyMeasurementResolver.normalizedValue(of: row, as: .waist),
                  WeighInStore.waistRangeCm.contains(stored) else { return .waist }
        }
        return nil
    }

    private static func carriedRefusal(_ kind: BodyMeasurementKind,
                                       limits: (low: String, high: String, unit: String)) -> String {
        switch kind {
        case .weight:
            return String(localized: "Could not move this reading: its stored weight is outside \(limits.low) to \(limits.high) \(limits.unit). Enter a weight in that range, then save.")
        case .waist:
            return String(localized: "Could not move this reading: its stored waist is outside \(limits.low) to \(limits.high) \(limits.unit). Enter a waist in that range, then save.")
        }
    }

    private func issue(_ text: String, kind: BodyMeasurementKind) -> WeighInFieldIssue? {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        guard let typed = Self.parse(text, locale: locale) else { return .notANumber }
        // The range is the store's, applied to the stored unit.
        let range = kind == .weight ? WeighInStore.weightRangeKg : WeighInStore.waistRangeCm
        let stored: Double
        switch (kind, unitSystem) {
        case (_, .metric): stored = typed
        case (.weight, .imperial): stored = typed / UnitFormatter.poundsPerKilogram
        case (.waist, .imperial): stored = typed * UnitFormatter.centimetersPerInch
        }
        if stored < range.lowerBound { return .belowMinimum }
        if stored > range.upperBound { return .aboveMaximum }
        return nil
    }

    /// The accepted range in the display unit, whole numbers that lie inside the stored range.
    private func bounds(_ kind: BodyMeasurementKind) -> (low: String, high: String, unit: String) {
        let range = kind == .weight ? WeighInStore.weightRangeKg : WeighInStore.waistRangeCm
        let low = kind == .weight ? words.weightValue(range.lowerBound) : words.lengthValue(range.lowerBound)
        let high = kind == .weight ? words.weightValue(range.upperBound) : words.lengthValue(range.upperBound)
        return (String(Int(low.rounded(.up))), String(Int(high.rounded(.down))),
                kind == .weight ? words.weightUnit : words.lengthUnit)
    }

    private func hint(_ text: String, kind: BodyMeasurementKind, last: OfferedReading?,
                      namesRange: Bool) -> String {
        let limits = bounds(kind)
        let range = String(localized: "\(limits.low) to \(limits.high) \(limits.unit)")
        switch issue(text, kind: kind) {
        case .notANumber?: return String(localized: "Enter a number.")
        case .belowMinimum?: return String(localized: "Enter \(limits.low) \(limits.unit) or more.")
        case .aboveMaximum?: return String(localized: "Enter \(limits.high) \(limits.unit) or less.")
        case nil: break
        }
        guard let last else { return range }
        let earlier = (["\(last.text) \(limits.unit)", words.date(last.day)] + (last.source.map { [$0] } ?? []))
            .joined(separator: " · ")
        // Once typed over, the offer is gone and the earlier reading stays as a reference.
        guard text == last.text else { return String(localized: "Last: \(earlier)") }
        let offer = String(localized: "Last: \(earlier). Type to replace.")
        return namesRange ? "\(offer) \(range)." : offer
    }

    /// A typed number. A comma and a point are both read as the decimal separator: no weight or
    /// waist in range has a thousands group, so "97,5" is ninety-seven and a half in every locale.
    static func parse(_ text: String, locale: Locale) -> Double? {
        var cleaned = text.trimmingCharacters(in: .whitespaces)
        if let separator = locale.decimalSeparator, separator != "." {
            cleaned = cleaned.replacingOccurrences(of: separator, with: ".")
        }
        cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        let digits = cleaned.filter { $0 != "." }
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              cleaned.count - digits.count <= 1 else { return nil }
        return Double(cleaned)
    }
}

// MARK: - History

/// The weigh-in history screen (specification §10.4).
@MainActor
final class WeighInHistoryModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded(WeighInHistory)
    }

    /// `.loading` until the first load.
    @Published private(set) var state: State = .loading
    /// The row whose deletion is being confirmed.
    @Published private(set) var pendingDelete: WeighInHistoryRow?

    private let weighIns: WeighInStore
    private let provider: BodyMeasurementProvider
    private let unitSystem: () -> UnitSystem
    private let locale: () -> Locale
    // Stage 4: the local day the week mark is judged on (stage 1 work package 1-11, ruling R44).
    private let today: () -> String
    private var generation = 0
    private var revisionObserver: AnyCancellable?

    init(weighIns: WeighInStore, provider: BodyMeasurementProvider,
         unitSystem: @escaping () -> UnitSystem,
         locale: @escaping () -> Locale = { AppLanguage.activeLocale },
         today: @escaping () -> String = { Repository.localDayKey(Date()) }) {
        self.weighIns = weighIns
        self.provider = provider
        self.unitSystem = unitSystem
        self.locale = locale
        self.today = today
    }

    func load() async {
        generation += 1
        let request = generation
        // Captured before the reads suspend.
        let system = unitSystem()
        let shownLocale = locale()
        let apple = provider.candidates(.weight).appleHealth
        let weights = await weighIns.readings(.weight)
        let waists = await weighIns.readings(.waist)
        guard request == generation else { return }
        let history = CutScorecardPresenter.history(weights: weights, waists: waists, appleHealth: apple,
                                                    unitSystem: system, locale: shownLocale, today: today())
        if state != .loaded(history) { state = .loaded(history) }
        if revisionObserver == nil {
            // A write made elsewhere reaches the list when the provider's snapshot changes.
            revisionObserver = provider.$revision.dropFirst().sink { [weak self] _ in
                Task { @MainActor [weak self] in await self?.load() }
            }
        }
    }

    /// Set exactly while a deletion is being confirmed.
    var deleteConfirmation: WeighInDeleteConfirmation? {
        pendingDelete.map {
            CutScorecardPresenter.deleteConfirmation(for: $0, unitSystem: unitSystem(), locale: locale())
        }
    }

    /// Asks once. A read-only row cannot be put up for deletion.
    func requestDelete(_ row: WeighInHistoryRow) {
        guard row.canDelete else { return }
        pendingDelete = row
    }

    func cancelDelete() {
        pendingDelete = nil
    }

    /// Deletes the confirmed weigh-in, its waist with its weight, then reloads. Without a pending
    /// row this does nothing.
    func confirmDelete() async {
        guard let row = pendingDelete else { return }
        pendingDelete = nil
        for stored in [row.weightRow, row.waistRow].compactMap({ $0 }) {
            // A row already gone leaves nothing to delete; the reload shows what is stored.
            try? await weighIns.delete(stored)
        }
        await load()
    }
}

// MARK: - Phase and rules sheet

/// The values of the phase and rules sheet (specification §10.5). Weights are kilograms here; the
/// view converts for display.
struct ScorecardPhaseDraft: Equatable {
    enum Field: String, CaseIterable {
        case name, startDay, targetWeight, rateLow, rateHigh
        case waistWindowWeeks, waistMinDecreaseCm
        case liftDropTolerancePercent, liftDropShare, liftDropConsecutiveWeeks, addCaloriesKcal
        case slowLossThresholdKgPerWeek, slowLossConsecutiveWeeks, reduceCarbsKcal
        case rateWindowWeeks, maxProjectionWeeks, targetToleranceKg
        case proteinFloorGrams, proteinMinDaysPerWeek
        case maxWeighInAgeWeeks

        var label: String {
            switch self {
            case .name: return String(localized: "Name")
            case .startDay: return String(localized: "Start date")
            case .targetWeight: return String(localized: "Target weight")
            case .rateLow: return String(localized: "At least")
            case .rateHigh: return String(localized: "At most")
            case .waistWindowWeeks: return String(localized: "Waist compared over")
            case .waistMinDecreaseCm: return String(localized: "Waist must be down at least")
            case .liftDropTolerancePercent: return String(localized: "A lift has dropped below")
            case .liftDropShare: return String(localized: "Share of lifts that dropped")
            case .liftDropConsecutiveWeeks, .slowLossConsecutiveWeeks: return String(localized: "For")
            case .addCaloriesKcal: return String(localized: "Then add")
            case .slowLossThresholdKgPerWeek: return String(localized: "Loss under")
            case .reduceCarbsKcal: return String(localized: "Then take from carbohydrate")
            case .rateWindowWeeks: return String(localized: "Rate fitted over")
            case .maxProjectionWeeks: return String(localized: "Projection stops at")
            case .targetToleranceKg: return String(localized: "Target counts as reached within")
            case .proteinFloorGrams: return String(localized: "Daily floor")
            case .proteinMinDaysPerWeek: return String(localized: "Days a week at or above it")
            case .maxWeighInAgeWeeks: return String(localized: "A verdict lapses after")
            }
        }
    }

    struct Group: Equatable {
        var title: String
        var fields: [Field]
    }

    /// The band a new phase is prefilled with, percent of bodyweight per week (specification §6.3).
    static let genericBand: ClosedRange<Double> = 0.25...0.75

    var isNewPhase: Bool
    var kind: CutScorecardStoredPhase.Kind
    var name: String
    var startDay: String
    var targetWeightKg: Double?
    var rateLowPercentPerWeek: Double
    var rateHighPercentPerWeek: Double
    var parameters: CutScorecardParameters
    /// The start day of the stored phase this draft edits; nil for a new phase.
    private var storedStartDay: String?
    /// The start day of the stored phase before the one this draft writes: the phase before the
    /// edited one, or the edited one itself for "Start a new phase". Nil when there is none. A
    /// phase that started before it would sort ahead of that phase and stop being the active one.
    private(set) var earliestStartDay: String? = nil

    /// First use: a cut starting today, no target, the generic band and the generic rules.
    static func firstUse(today: String) -> ScorecardPhaseDraft {
        ScorecardPhaseDraft(isNewPhase: true, kind: .cut, name: String(localized: "Cut"), startDay: today,
                            targetWeightKg: nil, rateLowPercentPerWeek: genericBand.lowerBound,
                            rateHighPercentPerWeek: genericBand.upperBound, parameters: .generic,
                            storedStartDay: nil)
    }

    /// The active phase and the stored rules. With no active phase, the next stored one; with no
    /// phase stored at all, `firstUse`.
    static func current(settings: CutScorecardSettings, today: String) -> ScorecardPhaseDraft {
        let phases = settings.phases
        guard let stored = settings.activePhase(on: today) ?? phases.first(where: { $0.startDay > today }) else {
            return firstUse(today: today)
        }
        // `save(to:)` replaces the last stored phase with this start day; the one before it is the floor.
        let index = phases.lastIndex { $0.startDay == stored.startDay }
        let before = index.flatMap { $0 > 0 ? phases[$0 - 1].startDay : nil }
        return ScorecardPhaseDraft(isNewPhase: false, kind: stored.kind, name: stored.name,
                                   startDay: stored.startDay, targetWeightKg: stored.targetWeightKg,
                                   rateLowPercentPerWeek: stored.rateLowPercentPerWeek,
                                   rateHighPercentPerWeek: stored.rateHighPercentPerWeek,
                                   parameters: settings.parameters, storedStartDay: stored.startDay,
                                   earliestStartDay: before)
    }

    /// "Start a new phase": a draft that will be appended, starting today. The band and the rules
    /// carry over; the name and the target do not.
    func startingNewPhase(today: String) -> ScorecardPhaseDraft {
        var next = self
        next.isNewPhase = true
        next.kind = .cut
        next.name = String(localized: "Cut")
        next.startDay = today
        next.targetWeightKg = nil
        // The new phase follows the one this draft was opened from, once that one has started. A
        // phase still ahead of today is no floor: the new phase starts today, before it, and the
        // later one takes over on its own start day.
        next.earliestStartDay = (storedStartDay ?? earliestStartDay).flatMap { $0 <= today ? $0 : nil }
        next.storedStartDay = nil
        return next
    }

    var title: String {
        isNewPhase ? String(localized: "New phase") : String(localized: "Phase and rules")
    }

    /// The sheet's sections. A phase that is not a cut has no target, no band and no rules.
    var groups: [Group] {
        guard kind == .cut else {
            return [Group(title: String(localized: "Phase"), fields: [.name, .startDay])]
        }
        return [
            Group(title: String(localized: "Phase"), fields: [.name, .startDay, .targetWeight]),
            Group(title: String(localized: "Expected rate of loss"), fields: [.rateLow, .rateHigh]),
            Group(title: String(localized: "Rule 1 · change nothing"), fields: [.waistWindowWeeks, .waistMinDecreaseCm]),
            Group(title: String(localized: "Rule 2 · lifts dropping"),
                  fields: [.liftDropTolerancePercent, .liftDropShare, .liftDropConsecutiveWeeks, .addCaloriesKcal]),
            Group(title: String(localized: "Rule 3 · slow loss"),
                  fields: [.slowLossThresholdKgPerWeek, .slowLossConsecutiveWeeks, .reduceCarbsKcal]),
            Group(title: String(localized: "Rate and projection"),
                  fields: [.rateWindowWeeks, .maxProjectionWeeks, .targetToleranceKg]),
            Group(title: String(localized: "Protein"), fields: [.proteinFloorGrams, .proteinMinDaysPerWeek]),
            Group(title: String(localized: "Weigh-ins"), fields: [.maxWeighInAgeWeeks]),
        ]
    }

    /// The fields that fail the pure function's validation (specification §6.5), in
    /// `Field.allCases` order. Only fields the sheet shows for this kind can be marked.
    var invalidFields: [Field] {
        var invalid: Set<Field> = []
        func amount(_ value: Double, atLeast low: Double = 0) -> Bool {
            value.isFinite && value >= low && value <= Self.largestMagnitude
        }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { invalid.insert(.name) }
        if CutScorecard.weekStart(containing: startDay) == nil { invalid.insert(.startDay) }
        // Day keys compare as text. The same day as the earlier phase is allowed: the stored order
        // is stable, so the phase written here stays the later of the two.
        if let earliestStartDay, startDay < earliestStartDay { invalid.insert(.startDay) }
        if kind == .cut {
            let p = parameters
            if let target = targetWeightKg, !(amount(target) && target > 0) { invalid.insert(.targetWeight) }
            if !amount(rateLowPercentPerWeek) { invalid.insert(.rateLow) }
            if !amount(rateHighPercentPerWeek) { invalid.insert(.rateHigh) }
            if amount(rateLowPercentPerWeek), amount(rateHighPercentPerWeek),
               rateLowPercentPerWeek > rateHighPercentPerWeek {
                invalid.formUnion([.rateLow, .rateHigh])
            }
            if p.waistWindowWeeks < 1 { invalid.insert(.waistWindowWeeks) }
            if !amount(p.waistMinDecreaseCm) { invalid.insert(.waistMinDecreaseCm) }
            if !(p.liftDropTolerancePercent.isFinite && p.liftDropTolerancePercent >= 0
                 && p.liftDropTolerancePercent < 100) { invalid.insert(.liftDropTolerancePercent) }
            if !(p.liftDropShare.isFinite && p.liftDropShare > 0 && p.liftDropShare <= 1) {
                invalid.insert(.liftDropShare)
            }
            if p.liftDropConsecutiveWeeks < 1 { invalid.insert(.liftDropConsecutiveWeeks) }
            if p.addCaloriesKcal < 0 { invalid.insert(.addCaloriesKcal) }
            if !amount(p.slowLossThresholdKgPerWeek) { invalid.insert(.slowLossThresholdKgPerWeek) }
            if p.slowLossConsecutiveWeeks < 1 { invalid.insert(.slowLossConsecutiveWeeks) }
            if p.reduceCarbsKcal < 0 { invalid.insert(.reduceCarbsKcal) }
            if p.rateWindowWeeks < 1 { invalid.insert(.rateWindowWeeks) }
            if p.maxProjectionWeeks < 1 { invalid.insert(.maxProjectionWeeks) }
            if !amount(p.targetToleranceKg) { invalid.insert(.targetToleranceKg) }
            if let floor = p.proteinFloorGrams, !(amount(floor) && floor > 0) { invalid.insert(.proteinFloorGrams) }
            if !(1...7).contains(p.proteinMinDaysPerWeek) { invalid.insert(.proteinMinDaysPerWeek) }
            if p.maxWeighInAgeWeeks < 0 { invalid.insert(.maxWeighInAgeWeeks) }
        }
        return Field.allCases.filter(invalid.contains)
    }

    /// Nil exactly when `invalidFields` is empty and the pure function accepts the values.
    var validationMessage: String? {
        let invalid = invalidFields
        if invalid == [.rateLow, .rateHigh], rateLowPercentPerWeek > rateHighPercentPerWeek {
            return String(localized: "\"\(Field.rateLow.label)\" is above \"\(Field.rateHigh.label)\". Fix one of them to save.")
        }
        if let first = invalid.first {
            return String(localized: "\"\(first.label)\" has a value that cannot be saved.")
        }
        return isAcceptedByTheScorecard ? nil : String(localized: "A value cannot be saved.")
    }

    var canSave: Bool { invalidFields.isEmpty && isAcceptedByTheScorecard }

    /// Stores the phase, and for a cut the rules. A new phase is appended; an edit replaces the
    /// stored phase it was opened from. Writes nothing and returns false when `!canSave`, and when
    /// the stored phases cannot be read: saving would replace every one of them with this one.
    @discardableResult
    func save(to settings: CutScorecardSettings) -> Bool {
        guard canSave, !settings.phasesNeedAttention else { return false }
        let isCut = kind == .cut
        let stored = CutScorecardStoredPhase(
            kind: kind, name: name, startDay: startDay, targetWeightKg: isCut ? targetWeightKg : nil,
            rateLowPercentPerWeek: isCut ? rateLowPercentPerWeek : Self.genericBand.lowerBound,
            rateHighPercentPerWeek: isCut ? rateHighPercentPerWeek : Self.genericBand.upperBound)
        var phases = settings.phases
        if !isNewPhase, let index = phases.lastIndex(where: { $0.startDay == storedStartDay }) {
            phases[index] = stored
        } else {
            phases.append(stored)
        }
        settings.phases = phases
        // A phase that is not a cut has no rules of its own: the stored ones are left as they were.
        if isCut { settings.parameters = parameters }
        return true
    }

    /// The pure function's arithmetic limit on a value (ruling R3).
    private static let largestMagnitude = 1e100

    /// The pure function is the one authority on what a valid phase and parameter set is.
    private var isAcceptedByTheScorecard: Bool {
        guard kind == .cut else { return true }
        let phase = CutScorecardPhase(name: name, startDay: startDay, targetWeightKg: targetWeightKg,
                                      rateLowPercentPerWeek: rateLowPercentPerWeek,
                                      rateHighPercentPerWeek: rateHighPercentPerWeek)
        let probe = CutScorecardInput(weights: [], waists: [], phase: phase, parameters: parameters,
                                      today: startDay)
        return CutScorecard.evaluate(probe).invalidInput == nil
    }
}
