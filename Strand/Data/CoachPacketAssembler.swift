import Foundation
import StrandAnalytics
import WhoopStore

// Stage 2 (coach packet), specification §8.4: gathers what `CoachPacket.render` prints. THE PACKET
// HAS NO NUMBER OF ITS OWN. Every fact is read through the one function the app's screens read it
// through (specification §4), so the packet and a screen cannot disagree. The assembler writes
// nothing, sends nothing, and needs neither the Coach switch nor the Coach's data consent.

/// One assembled packet: the exact text that may leave, and what the sheet says about it.
struct CoachPacketDocument: Equatable {
    let text: String
    /// `text.utf8.count`.
    let byteCount: Int
    /// The one clock reading the packet was built from.
    let generatedAt: Date
    let rangeDays: Int
    let sections: Set<CoachPacketSection>
    /// True when the gathered input holds no daily row, no step day and no workout in the range,
    /// no body reading and no weekly weigh-in point.
    let nothingMeasured: Bool
    /// Packet v2: the private-events choice the text was built with, read once in this assembly.
    /// Nil when the events feature is off in the app or the Events section is switched off. The
    /// sheet's caption is worded from this value and never from a second read of the setting.
    var privateEventsIncluded: Bool? = nil
}

enum CoachPacketOutcome: Equatable {
    case ready(CoachPacketDocument)
    /// The privacy scan found something; no text exists.
    case blocked(findings: Int)
    /// The store could not be read.
    case unavailable
}

@MainActor
struct CoachPacketAssembler {
    private let repository: Repository
    private let provider: BodyMeasurementProvider
    private let scorecardSettings: CutScorecardSettings
    private let settings: CoachPacketSettings
    private let now: () -> Date
    private let timeZone: () -> TimeZone
    private let effortScale: () -> EffortScale
    private let identifiers: () -> [String]?
    private let intake: IntakeProvider? // Stage 3: the protein days' funnel; nil is the live one
    /// Packet v2: the events store; nil is the app's shared one.
    private let events: PersonalEventStore?
    private let storeReadable: @MainActor () async -> Bool

    /// `identifiers` is read once per `assemble()`, at scan time. Nil means the list of known
    /// identifiers could not be read, and the packet is blocked: the scan fails closed and is never
    /// run with an empty list (ruling A20). `storeReadable` says whether the store can be read now,
    /// asked before the reads and after them; nil asks the repository for its store handle.
    init(repository: Repository, provider: BodyMeasurementProvider,
         scorecardSettings: CutScorecardSettings, settings: CoachPacketSettings,
         now: @escaping () -> Date = { Date() },
         timeZone: @escaping () -> TimeZone = { TimeZone.current },
         effortScale: @escaping () -> EffortScale,
         identifiers: @escaping () -> [String]?,
         intake: IntakeProvider? = nil, // Stage 3: nil is IntakeProvider.live(repository:)
         events: PersonalEventStore? = nil, // Packet v2: nil is PersonalEventStore.shared
         storeReadable: (@MainActor () async -> Bool)? = nil) {
        self.intake = intake // Stage 3
        self.events = events
        self.repository = repository
        self.provider = provider
        self.scorecardSettings = scorecardSettings
        self.settings = settings
        self.now = now
        self.timeZone = timeZone
        self.effortScale = effortScale
        self.identifiers = identifiers
        self.storeReadable = storeReadable ?? { await repository.storeIsReadable() }
    }

    /// What one assembly gathered: the renderer's input and the moment and choices it belongs to.
    private struct Gathered {
        let input: CoachPacketInput
        let generatedAt: Date
        let rangeDays: Int
        let nothingMeasured: Bool
        let privateEventsIncluded: Bool?
        /// The raw labels and notes behind the events rows, for the scan before the cut (ruling A20).
        let eventFreeText: [String]
    }

    /// The renderer's input for this moment, or nil when the store could not be read.
    func input() async -> CoachPacketInput? {
        await gather()?.input
    }

    /// The packet: gathered, rendered, then scanned. The scan reads the rendered text and every
    /// free text the owner typed or imported before it was sanitised and cut, against one reading
    /// of the identifier list (ruling A20). A finding means no text exists to copy, share or return.
    func assemble() async -> CoachPacketOutcome {
        guard let gathered = await gather() else { return .unavailable }
        let text = CoachPacket.render(gathered.input)
        let findings = CoachPacket.scan(gathered.input, rendered: text, identifiers: identifiers(),
                                        freeText: gathered.eventFreeText)
        guard findings.isEmpty else { return .blocked(findings: findings.count) }
        return .ready(CoachPacketDocument(text: text, byteCount: text.utf8.count, generatedAt: gathered.generatedAt,
                                          rangeDays: gathered.rangeDays, sections: gathered.input.sections,
                                          nothingMeasured: gathered.nothingMeasured,
                                          privateEventsIncluded: gathered.privateEventsIncluded))
    }

    private func gather() async -> Gathered? {
        // Captured before the first suspension, so one assembly describes one moment: one clock
        // reading gives `generated:`, today and the range.
        let instant = now()
        let zone = timeZone()
        let rangeDays = settings.rangeDays
        let sections = settings.sections
        let strainFactor = effortScale() == .whoop ? UnitFormatter.effortScaleFactor : 1.0
        let scorecardEnabled = scorecardSettings.isEnabled
        // Packet v2: whether each new feature is on, and the private-events choice, read once here.
        // A section the owner switched off reads nothing for it.
        let intakeProvider = intake ?? .live(repository: repository) // Stage 3: the one provider
        let intakeEnabled = sections.contains(.intake) && intakeProvider.settings.isEnabled
        let eventStore = events ?? .shared
        let eventsEnabled = sections.contains(.events) && eventStore.isEnabled
        let includeSensitive = eventsEnabled ? eventStore.packetIncludesSensitive : false
        let storedEvents = eventsEnabled ? eventStore.events : []

        let days = LocalDayWindows(timeZone: zone)
        let today = days.dayKey(for: instant)
        guard let todayNumber = CanonicalDay.number(today) else { return nil }
        let start = CanonicalDay.key(todayNumber - (rangeDays - 1))
        let inRange: (String) -> Bool = { $0 >= start && $0 <= today }

        // The repository's reads answer an unreadable store with nothing, which would print as a
        // packet of dashes. The store is asked first, and again once the reads are done, so a
        // store that could not be read is `.unavailable` and never "nothing measured".
        guard await storeReadable() else { return nil }

        // Weight and waist: the value every other surface shows as current. A profile that was
        // never written is not the owner's measurement and is not printed.
        await provider.refresh()
        var body: [CoachPacketBodyReading] = []
        if let weight = Self.reading(.weight, provider.current(.weight, consumer: .display)) { body.append(weight) }
        if let waist = Self.reading(.waist, provider.current(.waist, consumer: .display)) { body.append(waist) }

        // The scorecard: the one evaluation the scorecard screens show.
        let scorecard: CoachPacketScorecard
        var hasWeeklyPoint = false
        if scorecardEnabled {
            let evaluation = await CutScorecardInputBuilder(repository: repository, provider: provider,
                                                            settings: scorecardSettings,
                                                            intake: intakeProvider, // Stage 3
                                                            timeZone: { zone })
                .evaluation(today: today)
            let phase = evaluation.input.phase.map {
                CoachPacketPhase(name: $0.name, startDay: $0.startDay, targetWeightKg: $0.targetWeightKg,
                                 rateLowPercentPerWeek: $0.rateLowPercentPerWeek,
                                 rateHighPercentPerWeek: $0.rateHighPercentPerWeek)
            }
            hasWeeklyPoint = evaluation.result.weeks.contains { $0.weightKg != nil || $0.waistCm != nil }
            scorecard = .evaluated(phase: phase, result: evaluation.result)
        } else {
            scorecard = .switchedOff
        }

        let rows = repository.days.filter { inRange($0.day) }
        let baselines = repository.chargeBaselines
        let steps = await repository.resolvedSteps(from: start, to: today).points.filter { inRange($0.day) }.map {
            CoachPacketStepDay(day: $0.day, steps: $0.value, source: Self.stepSource($0))
        }
        // Newest first from the repository; the packet lists oldest first.
        let workouts = await repository.workoutRows(days: rangeDays + 1).reversed().map { row -> CoachPacketWorkout in
            let begins = Date(timeIntervalSince1970: TimeInterval(row.startTs))
            return CoachPacketWorkout(
                day: days.dayKey(for: begins),
                startMinuteOfDay: Self.secondOfDay(begins, in: zone) / 60,
                sport: row.sport, source: Self.workoutSource(WorkoutSource.classify(row.source)),
                durationMinutes: row.durationS.map { $0 / 60 }, avgHr: row.avgHr, energyKcal: row.energyKcal,
                distanceKm: row.distanceM.map { $0 / 1000 })
        }.filter { inRange($0.day) }

        // Packet v2, intake: the provider's resolved days, filtered to the range. The packet reads no
        // intake store and names no intake key.
        let intakeSection: CoachPacketIntake
        if intakeEnabled {
            await intakeProvider.refresh()
            intakeSection = .days(intakeProvider.series().filter { inRange($0.day) }.map(Self.intakeDay))
        } else {
            intakeSection = .switchedOff
        }

        // Packet v2, events: stage 5's rows for the one range of this assembly, and the raw text
        // behind them for the scan.
        let eventsSection: CoachPacketEvents
        var eventFreeText: [String] = []
        if eventsEnabled {
            eventsSection = .rows(PersonalEvents.packetLines(events: storedEvents, firstDay: start, lastDay: today,
                                                             includeSensitive: includeSensitive))
            let listed = PersonalEvents.events(overlapping: start, today,
                                               in: PersonalEvents.visible(storedEvents, includeSensitive: includeSensitive))
            eventFreeText = listed.flatMap { [$0.label, $0.note].compactMap { $0 } }
        } else {
            eventsSection = .switchedOff
        }

        let input = CoachPacketInput(
            generatedAt: Self.generatedAt(instant, today: today, in: zone),
            rangeStartDay: start, rangeEndDay: today, sections: sections, days: rows,
            strainFactor: strainFactor, scorecard: scorecard, body: body,
            hrvBaseline: Self.baseline(baselines?.hrv), restingHrBaseline: Self.baseline(baselines?.restingHR),
            steps: steps, workouts: workouts, intake: intakeSection, events: eventsSection)
        guard await storeReadable() else { return nil }

        let nothingMeasured = rows.isEmpty && steps.isEmpty && workouts.isEmpty && body.isEmpty && !hasWeeklyPoint
        return Gathered(input: input, generatedAt: instant, rangeDays: rangeDays, nothingMeasured: nothingMeasured,
                        privateEventsIncluded: eventsEnabled ? includeSensitive : nil, eventFreeText: eventFreeText)
    }

    // MARK: - Mapping onto the packet's closed tokens

    /// The resolved reading under the packet's own source token; nil for no reading and for the
    /// never-written profile default.
    private static func reading(_ kind: CoachPacketBodyKind,
                                _ resolved: ResolvedBodyMeasurement?) -> CoachPacketBodyReading? {
        guard let resolved else { return nil }
        let source: CoachPacketBodySource
        switch resolved.source {
        case .labBook: source = .labBook
        case .appleHealth: source = .appleHealth
        case .profile: source = .profile
        case .profileDefault: return nil
        }
        return CoachPacketBodyReading(kind: kind, value: resolved.value, source: source, day: resolved.day)
    }

    /// The centre, status and night count of a resolved baseline, with the typical range every
    /// reader of that range takes from `ChargeTypicalBand`. The range is nil exactly when the
    /// baseline cannot be used; nothing here decides that a second time.
    private static func baseline(_ state: BaselineState?) -> CoachPacketBaseline? {
        guard let state else { return nil }
        return CoachPacketBaseline(center: state.baseline, typical: ChargeTypicalBand.range(state),
                                   status: state.status.rawValue, nights: state.nValid)
    }

    /// One resolved intake day under the packet's own source token: the one source both values came
    /// from, or `mixed` when protein and energy came from two different sources.
    private static func intakeDay(_ day: ResolvedIntakeDay) -> CoachPacketIntakeDay {
        let sources = [day.protein?.source, day.energy?.source].compactMap { $0 }
        let source: CoachPacketIntakeSource?
        if let first = sources.first {
            source = sources.allSatisfy { $0 == first } ? intakeSource(first) : .mixed
        } else {
            source = nil
        }
        return CoachPacketIntakeDay(day: day.day, proteinGrams: day.protein?.value, energyKcal: day.energy?.value,
                                    source: source)
    }

    private static func intakeSource(_ source: IntakeSource) -> CoachPacketIntakeSource {
        switch source {
        case .appleHealth: return .appleHealth
        case .quickAdd: return .quickAdd
        case .nutritionCsv: return .nutritionFile
        }
    }

    private static func stepSource(_ point: ResolvedMetricPoint) -> CoachPacketStepSource {
        if point.sourceKey == "steps_est" { return .strapEstimate }
        return point.source == Repository.appleHealthSource ? .appleHealth : .strap
    }

    private static func workoutSource(_ source: WorkoutSource) -> CoachPacketWorkoutSource {
        switch source {
        case .whoop: return .whoop
        case .apple: return .appleHealth
        case .detected: return .detected
        case .manual: return .manual
        case .lifting: return .liftLog
        case .activityFile: return .activityFile
        }
    }

    // MARK: - The clock

    /// Seconds since local midnight of `instant` in `zone`, 0…86399.
    private static func secondOfDay(_ instant: Date, in zone: TimeZone) -> Int {
        let local = Int(instant.timeIntervalSince1970.rounded(.down)) + zone.secondsFromGMT(for: instant)
        return ((local % 86_400) + 86_400) % 86_400
    }

    /// "2031-03-16T07:42:10+01:00": local time with its numeric offset and no zone name
    /// (specification §15 P4). The date is `today`, the key the range ends on, so the header's
    /// two lines cannot name different days.
    private static func generatedAt(_ instant: Date, today: String, in zone: TimeZone) -> String {
        let second = secondOfDay(instant, in: zone)
        let offset = zone.secondsFromGMT(for: instant)
        let magnitude = abs(offset)
        return String(format: "%@T%02d:%02d:%02d%@%02d:%02d", today, second / 3_600, second / 60 % 60, second % 60,
                      offset < 0 ? "-" : "+", magnitude / 3_600, magnitude / 60 % 60)
    }
}

// MARK: - The app's assembler

extension CoachPacketAssembler {
    /// The assembler the sheet and the Shortcuts action share, over the app's repository and its
    /// stored choices. Nil until `AppModel.shared` exists.
    static func live() -> CoachPacketAssembler? {
        guard let app = AppModel.shared else { return nil }
        let repository = app.repo
        return CoachPacketAssembler(
            repository: repository,
            provider: BodyMeasurementProvider.live(repository: repository, profile: app.profile),
            scorecardSettings: CutScorecardSettings(), settings: CoachPacketSettings(),
            effortScale: {
                UnitPrefs.resolveEffortScale(UserDefaults.standard.string(forKey: UnitPrefs.effortScaleKey) ?? "")
            },
            // Called by the assembler, which lives on the main actor. Nil blocks the packet.
            identifiers: { [weak app] in MainActor.assumeIsolated { app.flatMap(knownIdentifiers) } })
    }

    /// Everything on this phone that names a device or an account (specification §7.11), for the
    /// privacy scan. Nil when the device registry has not been opened or the account list cannot
    /// be read: the scan then cannot be trusted, so the packet is blocked. Reads only.
    private static func knownIdentifiers(_ app: AppModel) -> [String]? {
        guard let registry = app.deviceRegistry,
              let accounts = try? ChatGPTCredentialStore().load().map({ $0.registrations.map(\.profile) }) ?? []
        else { return nil }
        // Fixed namespace constants are not identifiers; the packet prints its own tokens for them.
        let namespaces = [Repository.whoopSource, Repository.appleHealthSource, PersonalLiftingImport.deviceId]
        func deviceIdentifier(_ id: String) -> String? {
            id.count >= 6 && !namespaces.contains(id) ? id : nil
        }
        var found: [String?] = [deviceIdentifier(app.repo.deviceId)]
        for device in registry.devices {
            found.append(deviceIdentifier(device.id))
            found.append(device.peripheralId)
            // A nickname that only repeats the catalogue's brand or model names no one, and the
            // packet's own notes say "WHOOP": searching for it would block every packet.
            if let nickname = device.nickname,
               nickname.caseInsensitiveCompare(device.brand) != .orderedSame,
               nickname.caseInsensitiveCompare(device.model) != .orderedSame {
                found.append(nickname)
            }
        }
        for account in accounts {
            found += [account.email, account.name, account.subject, account.label]
        }
        found.append(hostName())
        found.append(NSHomeDirectory())
        return found.compactMap { $0 }.filter { !$0.isEmpty }
    }

    /// The device's network name, which usually carries the name the owner gave it. Nil when the
    /// system gives none or only the generic "localhost".
    private static func hostName() -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        guard gethostname(&buffer, buffer.count - 1) == 0 else { return nil }
        let name = String(cString: buffer)
        return name.isEmpty || name == "localhost" ? nil : name
    }
}
