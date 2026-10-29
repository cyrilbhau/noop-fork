#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import StrandImport
import WhoopStore

// Shared pieces for the redesigned Training screens (`docs/personal/REDESIGN-IMPLEMENTATION.md` Phase 5):
// the provenance labels, the merged session list the hub draws, and the mockup geometry that has no
// `NoopTheme` token. Nothing here computes a new metric: every figure is a stored value, a count, or the
// existing `LiftMetrics` arithmetic over logged sets.

/// Geometry from `design/round2` "04 Training" and `design/round3/training.html` with no `NoopTheme` token.
enum TrainingLayout {
    static let hubRing: CGFloat = 64
    static let hubRingLine: CGFloat = 8
    static let weekBarsHeight: CGFloat = 46
    static let dot: CGFloat = 8
    static let dotGap: CGFloat = 7
    static let todayRingInset: CGFloat = 2
    static let todayRingLine: CGFloat = 1.5
    static let headerIcon: CGFloat = 56
    static let chartHeight: CGFloat = 140
    static let hrrRing: CGFloat = 52
    static let hrrRingLine: CGFloat = 10
    static let hairline: CGFloat = 1
    static let setBadge: CGFloat = 24
    static let setBadgeRadius: CGFloat = 8
    static let badgeTint: Double = 0.14
    static let mutedFill: Double = 0.07
    static let warnFill: Double = 0.10
    static let warnBorder: Double = 0.22
    static let liveZoneRing: CGFloat = 230
    static let liveZoneLine: CGFloat = 6
    static let liveStrainRing: CGFloat = 184
    static let liveStrainLine: CGFloat = 7
    static let liveRingsHeight: CGFloat = 250
    static let liveControl: CGFloat = 76
    static let liveSecondaryControl: CGFloat = 56
    static let stopFill: Double = 0.18
    static let zoneStripHeight: CGFloat = 10
    static let editorMinHeight: CGFloat = 180
    static let liftCardTint: Double = 0.22
    static let sourceDot: CGFloat = 6
    static let sourceGap: CGFloat = 6
    static let badgeHorizontal: CGFloat = 10
    /// The muscle bar below the research floor, and the floor tick (the classic Lift Log's values).
    static let belowFloorOpacity: Double = 0.45
    static let floorTickOpacity: Double = 0.45
}

// MARK: - Provenance

/// Where a session came from, phrased as what NOOP actually holds for it. Apple Health workouts are
/// summaries; sessions with logged sets carry the full sets. Pasted Hevy text and Hevy CSV are stored
/// identically (`PersonalLiftingImport`, device id "lifting"), so they share one truthful label.
enum TrainingProvenance: Equatable {
    case importedSets
    case loggedSets
    case appleHealth
    case liftingSummary
    case whoop
    case manual
    case detected
    case activityFile

    var label: String {
        switch self {
        case .importedSets: return String(localized: "Pasted or Hevy CSV · full sets")
        case .loggedSets: return String(localized: "Lift log · full sets")
        case .appleHealth: return String(localized: "Apple Health · summary only")
        case .liftingSummary: return String(localized: "Lifting import · summary only")
        case .whoop: return String(localized: "WHOOP import")
        case .manual: return String(localized: "Added manually")
        case .detected: return String(localized: "Detected from heart rate")
        case .activityFile: return String(localized: "Workout file")
        }
    }

    var hasFullSets: Bool { self == .importedSets || self == .loggedSets }

    /// The dot colour beside the label: lifting colour for full sets, neutral otherwise (round 2 "04").
    var dotColor: Color { hasFullSets ? NoopTheme.lift : NoopTheme.textTertiary }

    static func forWorkout(_ row: WorkoutRow) -> TrainingProvenance {
        switch WorkoutSource.classify(row.source) {
        case .apple: return .appleHealth
        case .lifting: return .liftingSummary
        case .whoop: return .whoop
        case .manual: return .manual
        case .detected: return .detected
        case .activityFile: return .activityFile
        }
    }

    static func forLift(_ session: LiftSessionRow) -> TrainingProvenance {
        session.deviceId == PersonalLiftingImport.deviceId ? .importedSets : .loggedSets
    }
}

/// The provenance line: a small dot and a caption, as in the mockups' `.src` rows.
struct TrainingSourceLine: View {
    let provenance: TrainingProvenance

    var body: some View {
        HStack(spacing: TrainingLayout.sourceGap) {
            Circle()
                .fill(provenance.dotColor)
                .frame(width: TrainingLayout.sourceDot, height: TrainingLayout.sourceDot)
                .accessibilityHidden(true)
            Text(verbatim: provenance.label).noopFont(.caption)
        }
    }
}

// MARK: - Merged sessions

/// One row of the Training hub: a workout row, a lift session, or both when they are the same session.
struct TrainingSession: Identifiable {
    let workout: WorkoutRow?
    let lift: LiftSessionRow?
    /// Sets logged for `lift` (empty when there is no lift or its sets were not read).
    let sets: [LiftSetRow]

    var id: String {
        if let lift { return "lift:\(lift.id)" }
        if let workout { return "workout:\(workout.startTs)|\(workout.sport)|\(workout.source)" }
        return UUID().uuidString
    }

    var startTs: Int { workout?.startTs ?? lift?.startTs ?? 0 }

    var provenance: TrainingProvenance {
        if let lift { return TrainingProvenance.forLift(lift) }
        if let workout { return TrainingProvenance.forWorkout(workout) }
        return .manual
    }

    /// A lift for the consistency calendar: a session with logged sets, an imported lifting row, or a
    /// strength-type sport.
    var isLift: Bool {
        if lift != nil { return true }
        guard let workout else { return false }
        if WorkoutSource.classify(workout.source) == .lifting { return true }
        switch KnownWorkoutType.resolving(workout.sport) {
        case .strength, .bodybuilding, .weightlifting: return true
        default: return false
        }
    }

    /// Program or imported title when the lift carries one, else the workout's sport.
    var title: String {
        if let name = lift?.programName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return WorkoutSource.displaySport(workout?.sport ?? lift?.sport ?? LiftingImporter.sport)
    }

    var symbol: String { isLift ? "dumbbell.fill" : sportSymbol(workout?.sport ?? "") }

    var tint: Color { isLift ? NoopTheme.lift : NoopTheme.strain }

    /// Seconds, from the workout row, else the lift session's own interval. Nil when neither exists.
    var durationSeconds: Double? {
        if let workout {
            let s = workout.durationS ?? Double(workout.endTs - workout.startTs)
            return s > 0 ? s : nil
        }
        if let lift, let end = lift.endTs, end > lift.startTs { return Double(end - lift.startTs) }
        return nil
    }

    /// Performed sets: a zero-rep set was discarded, as on the Lift session screen.
    var performedSets: [LiftSetRow] { sets.filter { LiftMetrics.isPerformed(reps: $0.reps) } }

    /// Working sets with weight × reps summed by `LiftMetrics` (weights exactly as logged, never doubled).
    var volumeKg: Double? { LiftMetrics.volumeLoadKg(performedSets) }

    /// Pair workout rows with lift sessions. A local lift pairs with the workout it wrote (same start and
    /// sport); an imported lift pairs with a same-sport row starting within two minutes, the rule
    /// `WorkoutDetailView` uses to find "Exercises and sets". Unpaired lifts (no duration, so no workout
    /// row) still appear. Newest first.
    static func merge(workouts: [WorkoutRow], lifts: [LiftSessionRow],
                      sets: [String: [LiftSetRow]]) -> [TrainingSession] {
        var remaining = lifts
        var out: [TrainingSession] = []
        for row in workouts {
            let key = WorkoutSource.sportKey(row.sport)
            let index = remaining.indices
                .filter { WorkoutSource.sportKey(remaining[$0].sport) == key
                    && abs(remaining[$0].startTs - row.startTs) <= 120 }
                .min { abs(remaining[$0].startTs - row.startTs) < abs(remaining[$1].startTs - row.startTs) }
            if let index {
                let lift = remaining.remove(at: index)
                out.append(TrainingSession(workout: row, lift: lift, sets: sets[lift.id] ?? []))
            } else {
                out.append(TrainingSession(workout: row, lift: nil, sets: []))
            }
        }
        out += remaining.map { TrainingSession(workout: nil, lift: $0, sets: sets[$0.id] ?? []) }
        return out.sorted { $0.startTs > $1.startTs }
    }
}

// MARK: - Formatting

enum TrainingFormat {
    /// "52 min", or "1h 4m" from an hour up. Nil for a missing or zero duration.
    static func duration(_ seconds: Double?) -> String? {
        guard let seconds, seconds >= 60 else { return nil }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60
        if h > 0 { return String(localized: "\(h)h \(m)m") }
        return String(localized: "\(m) min")
    }

    /// "Today", "Yesterday", a weekday within the week, else "27 Oct".
    static func relativeDay(_ ts: Int, now: Date = Date()) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ts))
        let cal = Calendar.current
        if cal.isDateInToday(date) { return String(localized: "Today") }
        if cal.isDateInYesterday(date) { return String(localized: "Yesterday") }
        if let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day,
           days < 7 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// A grouped whole-number mass in the user's unit ("12,450"), from stored kilograms.
    static func groupedMass(_ kg: Double, system: UnitSystem) -> String {
        let value = LiftFormat.display(fromKilograms: kg, system: system)
        return Int(value.rounded()).formatted(.number.grouping(.automatic))
    }
}

// MARK: - Section title

/// A sentence-case section title with an optional trailing caption (not a link), padded like
/// `NoopSectionHeader`, so place it outside the screen gutter.
struct TrainingSectionTitle: View {
    let title: LocalizedStringKey
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .noopFont(.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: NoopTheme.Layout.s)
            if let trailing {
                Text(verbatim: trailing).noopFont(.footnote)
            }
        }
        .padding(.top, NoopTheme.Layout.sectionTop)
        .padding(.bottom, NoopTheme.Layout.sectionBottom)
        .padding(.horizontal, NoopTheme.Layout.sectionSide)
    }
}

/// A row hairline in the separator colour.
struct TrainingDivider: View {
    var body: some View {
        Rectangle()
            .fill(NoopTheme.separator)
            .frame(height: TrainingLayout.hairline)
            .accessibilityHidden(true)
    }
}

/// A small capsule badge on a tinted fill ("Apple Health · summary only", "RPE 8").
struct TrainingBadge: View {
    let text: String
    let tint: Color
    var fill: Color?

    var body: some View {
        Text(verbatim: text)
            .noopFont(.caption, color: false)
            .foregroundStyle(tint)
            .padding(.horizontal, TrainingLayout.badgeHorizontal)
            .padding(.vertical, NoopTheme.Layout.xs)
            .background(Capsule().fill(fill ?? tint.opacity(TrainingLayout.badgeTint)))
    }
}

/// The amber caution card (B4): a warning glyph, a title and a sentence, tinted `recoveryMid`.
struct TrainingWarningCard: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: NoopTheme.Layout.cardRadius, style: .continuous)
        HStack(alignment: .top, spacing: NoopTheme.Layout.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .noopFont(.sectionTitle, color: false)
                .foregroundStyle(NoopTheme.recoveryMid)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
                Text(title).noopFont(.rowTitle)
                Text(message).noopFont(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, NoopTheme.Layout.rowVerticalPadding)
        .padding(.horizontal, NoopTheme.Layout.l)
        .background(shape.fill(NoopTheme.recoveryMid.opacity(TrainingLayout.warnFill)))
        .overlay(shape.strokeBorder(NoopTheme.recoveryMid.opacity(TrainingLayout.warnBorder),
                                    lineWidth: TrainingLayout.hairline))
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// The ambient field for a Training screen, at the user's intensity.
    func trainingAmbient(_ preset: AmbientPreset, intensityRaw: String) -> some View {
        noopAmbientBackground(preset.blobs(intensity: AmbientIntensity(rawValue: intensityRaw) ?? .balanced))
    }
}
#endif
