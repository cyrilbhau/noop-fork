import Foundation
import WhoopStore

// The one place a body weight or a waist is chosen from the stores that can hold one
// (docs/personal/superapp/specs/stage-1.md §8). Pure: no store, no defaults, no clock. The
// repository-backed half is `BodyMeasurementProvider`.
//
// No Kotlin twin, by the written disposition of §12.7 item 7: this is app-layer selection among
// platform-specific sources and it produces no new stored shape.

/// Which body measurement is being resolved.
enum BodyMeasurementKind {
    case weight, waist

    /// The Lab Book marker key the kind is stored under (`MarkerCatalog`).
    var markerKey: String {
        switch self {
        case .weight: return "weight"
        case .waist: return "waist"
        }
    }

    /// The kind a Lab Book marker key names, nil for every other marker.
    init?(markerKey: String) {
        switch markerKey {
        case "weight": self = .weight
        case "waist": self = .waist
        default: return nil
        }
    }
}

/// Where a resolved value came from.
enum BodyMeasurementSource: String {
    case labBook, appleHealth, profile, profileDefault
}

/// Who is asking. With the feature flag off the two consumers keep their separate legacy rules.
enum BodyMeasurementConsumer {
    case display, estimate
}

/// The rule set a resolution runs under.
enum BodyMeasurementPolicy {
    /// Flag on: newest day wins across Lab Book and Apple Health, then the profile value.
    case unified
    /// Flag off, Today: Apple Health only, then the profile value. Lab Book is not consulted.
    case legacyDisplay
    /// Flag off, estimates: the profile value only.
    case legacyEstimate
}

/// One dated reading the policy admits. `value` is kilograms or centimetres.
struct DatedBodyMeasurement: Equatable {
    let day: String
    let takenAt: Int?
    let value: Double
    let source: BodyMeasurementSource
    let rowId: String?
}

/// The value in force on a day. `day` is nil for the profile value, which has no date.
struct ResolvedBodyMeasurement: Equatable {
    let kind: BodyMeasurementKind
    let value: Double
    let source: BodyMeasurementSource
    let day: String?
}

/// Everything a resolution may choose from, for one kind.
struct BodyMeasurementCandidates {
    var labBook: [LabMarkerRow]
    var appleHealth: [(day: String, value: Double)]
    var profileValue: Double
    var profileIsSet: Bool
}

enum BodyMeasurementResolver {
    /// The one place a flag state and a consumer become a policy.
    static func policy(flagEnabled: Bool, consumer: BodyMeasurementConsumer) -> BodyMeasurementPolicy {
        guard flagEnabled else {
            switch consumer {
            case .display: return .legacyDisplay
            case .estimate: return .legacyEstimate
            }
        }
        return .unified
    }

    /// Every dated reading the policy admits, ascending by day, one per day.
    ///
    /// `unified`: Lab Book rows of this kind in a unit of this kind, and for a weight the Apple
    /// Health values; a value that is missing, not finite or not positive is not a reading. On one day
    /// Lab Book beats Apple Health, and within Lab Book the greatest `takenAt` wins, then the greatest
    /// `id`. `legacyDisplay`: the Apple Health values exactly as given, the later of two entries that
    /// share a day standing for it. `legacyEstimate`: nothing.
    static func series(_ kind: BodyMeasurementKind, candidates: BodyMeasurementCandidates,
                       policy: BodyMeasurementPolicy) -> [DatedBodyMeasurement] {
        var byDay: [String: DatedBodyMeasurement] = [:]
        switch policy {
        case .legacyEstimate:
            return []
        case .legacyDisplay:
            guard kind == .weight else { return [] }
            for entry in candidates.appleHealth {
                byDay[entry.day] = DatedBodyMeasurement(day: entry.day, takenAt: nil, value: entry.value,
                                                        source: .appleHealth, rowId: nil)
            }
        case .unified:
            if kind == .weight {
                for entry in candidates.appleHealth where isUsable(entry.value) {
                    byDay[entry.day] = DatedBodyMeasurement(day: entry.day, takenAt: nil, value: entry.value,
                                                            source: .appleHealth, rowId: nil)
                }
            }
            var labByDay: [String: (row: LabMarkerRow, value: Double)] = [:]
            for row in candidates.labBook where row.markerKey == kind.markerKey {
                guard let value = normalizedValue(of: row, as: kind) else { continue }
                if let held = labByDay[row.day],
                   (held.row.takenAt, held.row.id) >= (row.takenAt, row.id) { continue }
                labByDay[row.day] = (row, value)
            }
            for (day, entry) in labByDay {
                byDay[day] = DatedBodyMeasurement(day: day, takenAt: entry.row.takenAt, value: entry.value,
                                                  source: .labBook, rowId: entry.row.id)
            }
        }
        return byDay.keys.sorted().compactMap { byDay[$0] }
    }

    /// The value in force as of `day`: the newest admitted reading on or before it, else the profile
    /// value. Nil only for a waist that has never been set anywhere.
    static func resolve(_ kind: BodyMeasurementKind, asOf day: String,
                        candidates: BodyMeasurementCandidates,
                        policy: BodyMeasurementPolicy) -> ResolvedBodyMeasurement? {
        if let reading = series(kind, candidates: candidates, policy: policy).last(where: { $0.day <= day }) {
            return ResolvedBodyMeasurement(kind: kind, value: reading.value, source: reading.source,
                                           day: reading.day)
        }
        // A waist of 0 is the profile's "not set"; a weight always has the profile value or its default.
        if kind == .waist, !(candidates.profileValue > 0) { return nil }
        return ResolvedBodyMeasurement(kind: kind, value: candidates.profileValue,
                                       source: candidates.profileIsSet ? .profile : .profileDefault,
                                       day: nil)
    }

    /// A Lab Book row's value in kilograms (weight) or centimetres (waist), nil when the row is not
    /// a usable reading of that kind. Units are partitioned by kind (ruling R30): a weight is admitted
    /// in kg, lb or lbs only and a waist in cm or in only, compared case-insensitively after trimming.
    static func normalizedValue(of row: LabMarkerRow, as kind: BodyMeasurementKind) -> Double? {
        guard let raw = row.value else { return nil }
        let unit = row.unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let value: Double
        switch (kind, unit) {
        case (.weight, "kg"), (.waist, "cm"): value = raw
        case (.weight, "lb"), (.weight, "lbs"): value = raw / UnitFormatter.poundsPerKilogram
        case (.waist, "in"): value = raw * UnitFormatter.centimetersPerInch
        default: return nil
        }
        return isUsable(value) ? value : nil
    }

    private static func isUsable(_ value: Double) -> Bool {
        value.isFinite && value > 0
    }
}
