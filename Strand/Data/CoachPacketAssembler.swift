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
    private let identifiers: () -> [String]
    private let storeReadable: () -> Bool

    /// `storeReadable` false: the assembly is `.unavailable` and nothing is read. The app passes
    /// whether its device registry could be opened, because without it the privacy scan would not
    /// know which identifiers to look for, and the scan fails closed.
    init(repository: Repository, provider: BodyMeasurementProvider,
         scorecardSettings: CutScorecardSettings, settings: CoachPacketSettings,
         now: @escaping () -> Date = { Date() },
         timeZone: @escaping () -> TimeZone = { TimeZone.current },
         effortScale: @escaping () -> EffortScale,
         identifiers: @escaping () -> [String],
         storeReadable: @escaping () -> Bool = { true }) {
        self.repository = repository
        self.provider = provider
        self.scorecardSettings = scorecardSettings
        self.settings = settings
        self.now = now
        self.timeZone = timeZone
        self.effortScale = effortScale
        self.identifiers = identifiers
        self.storeReadable = storeReadable
    }

    /// What one assembly gathered: the renderer's input and the moment and choices it belongs to.
    private struct Gathered {
        let input: CoachPacketInput
        let generatedAt: Date
        let rangeDays: Int
        let nothingMeasured: Bool
    }

    /// The renderer's input for this moment, or nil when the store could not be read.
    func input() async -> CoachPacketInput? {
        await gather()?.input
    }

    /// The packet: gathered, rendered, then scanned. A finding means no text exists to copy, share
    /// or return.
    func assemble() async -> CoachPacketOutcome {
        guard let gathered = await gather() else { return .unavailable }
        let text = CoachPacket.render(gathered.input)
        let findings = CoachPacket.privacyViolations(in: text, identifiers: identifiers())
        guard findings.isEmpty else { return .blocked(findings: findings.count) }
        return .ready(CoachPacketDocument(text: text, byteCount: text.utf8.count, generatedAt: gathered.generatedAt,
                                          rangeDays: gathered.rangeDays, sections: gathered.input.sections,
                                          nothingMeasured: gathered.nothingMeasured))
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
        guard storeReadable() else { return nil }

        let days = LocalDayWindows(timeZone: zone)
        let today = days.dayKey(for: instant)
        guard let todayNumber = CanonicalDay.number(today) else { return nil }
        let start = CanonicalDay.key(todayNumber - (rangeDays - 1))
        let inRange: (String) -> Bool = { $0 >= start && $0 <= today }

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
                                                            settings: scorecardSettings, timeZone: { zone })
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

        let input = CoachPacketInput(
            generatedAt: Self.generatedAt(instant, today: today, in: zone),
            rangeStartDay: start, rangeEndDay: today, sections: sections, days: rows,
            strainFactor: strainFactor, scorecard: scorecard, body: body,
            hrvBaseline: Self.baseline(baselines?.hrv), restingHrBaseline: Self.baseline(baselines?.restingHR),
            steps: steps, workouts: workouts)
        let nothingMeasured = rows.isEmpty && steps.isEmpty && workouts.isEmpty && body.isEmpty && !hasWeeklyPoint
        return Gathered(input: input, generatedAt: instant, rangeDays: rangeDays, nothingMeasured: nothingMeasured)
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
            // Both are called by the assembler, which lives on the main actor.
            identifiers: { [weak app] in MainActor.assumeIsolated { app.flatMap(knownIdentifiers) ?? [] } },
            storeReadable: { [weak app] in MainActor.assumeIsolated { app.flatMap(knownIdentifiers) != nil } })
    }

    /// Everything on this phone that names a device or an account (specification §7.11), for the
    /// privacy scan. Nil when the device registry has not been opened or the account list cannot
    /// be read: the scan then cannot be trusted, so no packet is made. Reads only.
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
