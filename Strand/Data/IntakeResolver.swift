import Foundation
import StrandAnalytics

/// Where one resolved intake value came from (stage 3 specification §9.4).
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
enum IntakeSource: String, Equatable {
    case appleHealth, quickAdd, nutritionCsv
}

/// The owner's choice of where intake comes from (`intake.source`). `none` is Path C: supplements
/// and the cutoff reminder only.
enum IntakeSourceSetting: String, Equatable, CaseIterable {
    case none, appleHealth, quickAdd
}

/// How the sources are consulted. `legacy` is the behaviour from before this stage: the CSV series
/// only. `unified` consults every intake source, the active one first.
enum IntakePolicy: Equatable {
    case legacy
    case unified(active: IntakeSourceSetting)
}

/// One nutrient's value for a day, with the source it came from and the time stored with it.
struct ResolvedIntakeValue: Equatable {
    let value: Double
    let source: IntakeSource
    /// Nil for a CSV value, which has no read time.
    let readAtEpochSeconds: Int?
}

/// One day's protein and energy, each resolved independently.
struct ResolvedIntakeDay: Equatable {
    let day: String
    let protein: ResolvedIntakeValue?
    let energy: ResolvedIntakeValue?
}

/// What the store holds under each source id.
struct IntakeCandidates {
    var appleHealth: [IntakeStoredDay]
    var quickAdd: [IntakeStoredDay]
    var nutritionCsv: [IntakeStoredDay]
}

/// The one rule for "protein on a day" and "energy on a day" (§9.4). Pure: no store access, no clock.
/// For each day and each nutrient, the value is the first source in the policy's order that holds a
/// finite, non-negative value for it. Sources are never summed: a meal logged in a food app and
/// quick-added as well would otherwise count twice.
enum IntakeResolver {
    /// The one place a flag state and a source setting become a policy.
    static func policy(flagEnabled: Bool, sourceSetting: IntakeSourceSetting) -> IntakePolicy {
        flagEnabled ? .unified(active: sourceSetting) : .legacy
    }

    /// The sources consulted, first match wins.
    static func order(_ policy: IntakePolicy) -> [IntakeSource] {
        switch policy {
        case .legacy: return [.nutritionCsv]
        case .unified(active: .quickAdd): return [.quickAdd, .appleHealth, .nutritionCsv]
        case .unified(active: .appleHealth), .unified(active: .none): return [.appleHealth, .quickAdd, .nutritionCsv]
        }
    }

    /// One entry per day that has any admitted value, ascending.
    static func series(candidates: IntakeCandidates, policy: IntakePolicy) -> [ResolvedIntakeDay] {
        let sources = order(policy)
        // Per source, the stored day for each key. A day listed twice keeps its last entry.
        var bySource: [IntakeSource: [String: IntakeStoredDay]] = [:]
        for source in sources {
            var days: [String: IntakeStoredDay] = [:]
            for stored in candidates.days(for: source) { days[stored.day] = stored }
            bySource[source] = days
        }
        let allDays = Set(bySource.values.flatMap(\.keys)).sorted()
        return allDays.compactMap { day in
            let protein = first(sources, bySource, day) { $0.proteinGrams }
            let energy = first(sources, bySource, day) { $0.energyKcal }
            guard protein != nil || energy != nil else { return nil }
            return ResolvedIntakeDay(day: day, protein: protein, energy: energy)
        }
    }

    /// `series(...)` entry for `day`, or nil when no source holds a usable value for it.
    static func resolve(day: String, candidates: IntakeCandidates,
                        policy: IntakePolicy) -> ResolvedIntakeDay? {
        series(candidates: candidates, policy: policy).first { $0.day == day }
    }

    private static func first(_ sources: [IntakeSource], _ bySource: [IntakeSource: [String: IntakeStoredDay]],
                              _ day: String, _ value: (IntakeStoredDay) -> Double?) -> ResolvedIntakeValue? {
        for source in sources {
            guard let stored = bySource[source]?[day], let amount = value(stored),
                  amount.isFinite, amount >= 0 else { continue }
            return ResolvedIntakeValue(value: amount, source: source,
                                       readAtEpochSeconds: source == .nutritionCsv ? nil : stored.readAtEpochSeconds)
        }
        return nil
    }
}

private extension IntakeCandidates {
    func days(for source: IntakeSource) -> [IntakeStoredDay] {
        switch source {
        case .appleHealth: return appleHealth
        case .quickAdd: return quickAdd
        case .nutritionCsv: return nutritionCsv
        }
    }
}
