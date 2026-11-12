import Foundation
import StrandAnalytics
import WhoopStore

/// Gathers everything `CutScorecard.evaluate` reads (specification §6.3) and is its production
/// caller.
///
/// Weights and waists are the body-measurement provider's series, the same list the Today tile and
/// the estimates resolve from (§8.1), so the scorecard's current weight cannot differ from theirs.
/// The builder reads no Lab Book row and no Apple Health value by itself, and it writes nothing.
@MainActor
struct CutScorecardInputBuilder {
    private static let nutritionSource = "nutrition-csv"
    private static let proteinKey = "protein_g"

    private let repository: Repository
    private let provider: BodyMeasurementProvider
    private let settings: CutScorecardSettings
    private let timeZone: () -> TimeZone

    init(repository: Repository, provider: BodyMeasurementProvider, settings: CutScorecardSettings,
         timeZone: @escaping () -> TimeZone = { TimeZone.current }) {
        self.repository = repository
        self.provider = provider
        self.settings = settings
        self.timeZone = timeZone
    }

    /// The scorecard for `today`, from the provider's current snapshot and the stored lifts,
    /// protein days, phase and rules.
    func evaluate(today: String) async -> CutScorecardResult {
        CutScorecard.evaluate(await build(today: today))
    }

    /// Everything `CutScorecard.evaluate` reads, for `today`.
    ///
    /// A missing measurement is absent from its list, never a zero: a skipped waist has no reading,
    /// a set with no load has no observation and an unlogged day has no protein entry.
    func build(today: String) async -> CutScorecardInput {
        // Captured before the first suspension, so one build describes one moment.
        let weights = readings(.weight)
        let waists = readings(.waist)
        let phase = settings.evaluationPhase(on: today)
        let parameters = settings.parameters
        let activeDeviceId = repository.deviceId
        let zone = timeZone()

        let lifts = await liftObservations(activeDeviceId: activeDeviceId, zone: zone)
        let protein = await repository.series(key: Self.proteinKey, source: Self.nutritionSource)
        return CutScorecardInput(
            weights: weights, waists: waists, lifts: lifts,
            proteinDays: protein.map { CutScorecardProteinDay(day: $0.day, grams: $0.value) },
            phase: phase, parameters: parameters, today: today)
    }

    /// One reading per day of the provider's series. An Apple Health value has no instant; it is
    /// the only reading of its day in the series, so the 0 it is given orders nothing.
    private func readings(_ kind: BodyMeasurementKind) -> [CutScorecardReading] {
        provider.series(kind, consumer: .display).map {
            CutScorecardReading(day: $0.day, takenAt: $0.takenAt ?? 0, value: $0.value)
        }
    }

    /// One observation per performed working set with a load above zero, from finished sessions
    /// logged in the app (the active strap id) and imported ones (`PersonalLiftingImport.deviceId`),
    /// the two lists the Lift Log shows. The day is the local day the session started on.
    private func liftObservations(activeDeviceId: String, zone: TimeZone) async -> [CutScorecardLiftObservation] {
        guard let store = await repository.storeHandle() else { return [] }
        let now = Int(Date().timeIntervalSince1970)
        var deviceIds = [activeDeviceId]
        if activeDeviceId != PersonalLiftingImport.deviceId { deviceIds.append(PersonalLiftingImport.deviceId) }
        let days = LocalDayWindows(timeZone: zone)
        var observations: [CutScorecardLiftObservation] = []
        for deviceId in deviceIds {
            let sessions = (try? await store.liftSessions(deviceId: deviceId, fromTs: 0, toTs: now)) ?? []
            for session in sessions where session.endTs != nil {
                let day = days.dayKey(for: Date(timeIntervalSince1970: Double(session.startTs)))
                let sets = (try? await store.liftSets(sessionId: session.id)) ?? []
                for set in sets where !set.isWarmup && LiftMetrics.isPerformed(reps: set.reps) {
                    guard let load = set.weightKg, load > 0 else { continue }
                    observations.append(CutScorecardLiftObservation(day: day, exercise: set.exercise, weightKg: load))
                }
            }
        }
        return observations
    }
}
