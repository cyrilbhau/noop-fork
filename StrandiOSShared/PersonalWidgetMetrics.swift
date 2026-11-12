import Foundation

// Personal iOS fork only. These values describe presentation and provenance; they do not alter
// analytics, storage schemas, protocol decoding, or the existing cross-platform score snapshot.
public struct PersonalWidgetMetrics: Codable, Equatable {
    public static let stepGoalKey = "personal.stepsGoal"
    public var steps: PersonalStepReading?
    public var sleep: PersonalSleepReading?
    public var stepGoal: Int?
    /// Stage 3: today's protein against the floor. Nil (flag off, no source, never published) is
    /// omitted from the encoded payload, so the bytes are what they were before the field existed.
    public var intake: PersonalIntakeReading?

    public init(steps: PersonalStepReading? = nil, sleep: PersonalSleepReading? = nil, stepGoal: Int? = nil,
                intake: PersonalIntakeReading? = nil) {
        self.steps = steps
        self.sleep = sleep
        self.stepGoal = stepGoal.flatMap { (1...50_000).contains($0) ? $0 : nil }
        self.intake = intake
    }

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // A widget extension can wake after midnight without the app running. Recheck on READ, rather
    // than relying on the app to clear yesterday's goal progress at its next foreground entry.
    public func todaySteps(now: Date, calendar: Calendar = .current) -> PersonalStepReading? {
        guard let steps, steps.day == Self.dayKey(now, calendar: calendar) else { return nil }
        return steps
    }

    /// Stage 3: the protein reading for the entry's own day only; yesterday's figure is never shown
    /// as today's.
    public func todayIntake(now: Date, calendar: Calendar = .current) -> PersonalIntakeReading? {
        guard let intake, intake.day == Self.dayKey(now, calendar: calendar) else { return nil }
        return intake
    }

    /// Stage 3: what the protein widget draws at `now`. Not set up only when nothing was published
    /// or the reading has no source (§10.8). A set-up reading from an earlier day is "Nothing logged
    /// today" with its floor: its figure and time are never drawn as today's.
    public func intakeWidgetState(now: Date, calendar: Calendar = .current) -> PersonalIntakeWidgetState {
        guard let intake, intake.source != nil else { return .notSetUp }
        guard intake.day == Self.dayKey(now, calendar: calendar) else { return .nothingLogged(floorGrams: intake.floorGrams) }
        return intake.widgetState
    }

    public func recentSleep(now: Date, calendar: Calendar = .current) -> PersonalSleepReading? {
        guard let sleep, sleep.end <= now,
              let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return nil }
        let endDay = Self.dayKey(sleep.end, calendar: calendar)
        return endDay == Self.dayKey(now, calendar: calendar)
            || endDay == Self.dayKey(yesterday, calendar: calendar) ? sleep : nil
    }
}

public struct PersonalStepReading: Codable, Equatable {
    public enum Source: String, Codable { case whoop4MotionEstimate, appleHealth }

    public let count: Int
    public let day: String
    public let source: Source
    // Daily totals have no durable measurement/calculation timestamp here. nil means unknown,
    // never the publication time or the newest motion row that MAY not have been scored yet.
    public let observedAt: Date?

    public static func estimate(value: Double, day: String) -> Self? {
        guard value.isFinite, value >= 0, value.rounded() < Double(Int.max) else { return nil }
        return Self(count: Int(value.rounded()), day: day, source: .whoop4MotionEstimate, observedAt: nil)
    }

    public static func health(value: Int, day: String) -> Self? {
        guard value >= 0 else { return nil }
        return Self(count: value, day: day, source: .appleHealth, observedAt: nil)
    }
}

public struct PersonalSleepReading: Codable, Equatable {
    public enum Source: String, Codable { case localEstimate, whoopImport }

    public let asleepMinutes: Int
    public let start: Date
    public let end: Date
    public let source: Source
    public let incomplete: Bool
    public let userEdited: Bool

    // Bounds and duration come from the existing sleep selector/decoder. A clock span is never
    // substituted for missing asleep minutes; empty or impossible stage totals remain absent.
    public static func reading(asleepMinutes: Double, start: Date, end: Date, source: Source,
                               incomplete: Bool, userEdited: Bool) -> Self? {
        let spanMinutes = end.timeIntervalSince(start) / 60
        guard asleepMinutes.isFinite, asleepMinutes > 0, end > start,
              asleepMinutes <= spanMinutes + 1, asleepMinutes.rounded() < Double(Int.max) else { return nil }
        return Self(asleepMinutes: Int(asleepMinutes.rounded()), start: start, end: end,
                    source: source, incomplete: incomplete, userEdited: userEdited)
    }
}

// MARK: - Stage 3: protein and intake (specification §10.8)

/// The shown protein figures, filled by the app's presenter from the pure progress. Foundation only:
/// this file cannot import the analytics package.
public struct IntakeProteinValues: Equatable {
    public let shownGrams: Int?
    public let shownFloorGrams: Int?
    public let remainingGrams: Int?

    public init(shownGrams: Int?, shownFloorGrams: Int?, remainingGrams: Int?) {
        self.shownGrams = shownGrams
        self.shownFloorGrams = shownFloorGrams
        self.remainingGrams = remainingGrams
    }
}

/// What the protein widget draws (§10.8).
public enum PersonalIntakeWidgetState: Equatable {
    case notSetUp
    case nothingLogged(floorGrams: Int?)
    case noFloor(grams: Int)
    case below(grams: Int, floorGrams: Int, remainingGrams: Int)
    case atFloor(grams: Int, floorGrams: Int)
    case above(grams: Int, floorGrams: Int, overGrams: Int)
}

extension PersonalIntakeWidgetState {
    /// Codex C19: the whole state in words, for a family that draws only a gauge (the circular Lock
    /// Screen widget). Grams eaten against the floor, what remains or is over, and when the figure was
    /// read or entered, or that it is stale; `time` nil with a figure says the time is not known.
    public func spokenDescription(time: String?, stale: Bool) -> String {
        var parts: [String] = []
        var hasFigure = true
        switch self {
        case .notSetUp:
            return String(localized: "Set up in NOOP")
        case .nothingLogged(let floor):
            parts.append(String(localized: "Nothing logged today"))
            if let floor { parts.append(String(localized: "Floor \(floor) g")) }
            hasFigure = false
        case .noFloor(let grams):
            parts.append(String(localized: "\(grams) g logged"))
            parts.append(String(localized: "No floor set"))
        case .below(let grams, let floor, let remaining):
            parts.append(String(localized: "\(grams) g of \(floor) g"))
            parts.append(String(localized: "\(remaining) g to go"))
        case .atFloor(let grams, let floor):
            parts.append(String(localized: "\(grams) g of \(floor) g"))
            parts.append(String(localized: "Floor met"))
        case .above(let grams, let floor, let over):
            parts.append(String(localized: "\(grams) g of \(floor) g"))
            parts.append(String(localized: "Floor met"))
            parts.append(String(localized: "+\(over) g over"))
        }
        if hasFigure {
            if let time {
                parts.append(stale ? String(localized: "Last read \(time)") : String(localized: "as of \(time)"))
            } else {
                parts.append(String(localized: "Time not known"))
            }
            if stale { parts.append(String(localized: "Open NOOP to refresh")) }
        }
        return parts.joined(separator: ", ")
    }
}

/// Today's protein for the widget: whole grams, the printed floor, where the figure came from and
/// when it was read or entered. No calories, labels, app names or supplements.
public struct PersonalIntakeReading: Codable, Equatable {
    public enum Source: String, Codable { case appleHealth, quickAdd }

    public let day: String
    /// Shown grams; nil: not measured.
    public let proteinGrams: Int?
    /// Shown floor; nil: no floor set.
    public let floorGrams: Int?
    public let source: Source?
    /// Nil: unknown.
    public let readAt: Date?

    /// Seconds after `readAt` at which a Health figure is drawn as stale.
    public static let staleAfter: TimeInterval = 3 * 3600

    public static func reading(day: String, progress: IntakeProteinValues, source: Source?,
                               readAt: Date?) -> Self {
        Self(day: day, proteinGrams: progress.shownGrams, floorGrams: progress.shownFloorGrams, source: source,
             readAt: readAt)
    }

    /// A value is never drawn without its time: a figure with no read time, or a reading with no
    /// source, draws the not-set-up state.
    public var widgetState: PersonalIntakeWidgetState {
        guard source != nil else { return .notSetUp }
        guard let grams = proteinGrams else { return .nothingLogged(floorGrams: floorGrams) }
        guard readAt != nil else { return .notSetUp }
        guard let floor = floorGrams, floor > 0 else { return .noFloor(grams: grams) }
        if grams < floor { return .below(grams: grams, floorGrams: floor, remainingGrams: max(1, floor - grams)) }
        if grams == floor { return .atFloor(grams: grams, floorGrams: floor) }
        return .above(grams: grams, floorGrams: floor, overGrams: grams - floor)
    }

    /// A Health figure at or after `readAt + staleAfter`. An entry made in the app is never stale.
    public func isStale(now: Date) -> Bool {
        guard source == .appleHealth, let readAt else { return false }
        return now >= readAt.addingTimeInterval(Self.staleAfter)
    }

    /// When the widget should draw again without the app: now, when a Health figure turns stale (if
    /// that is still ahead), and the next local midnight (so yesterday's figure expires). Ascending.
    public func timelineDates(now: Date, calendar: Calendar = .current) -> [Date] {
        var dates = [now]
        if source == .appleHealth, let readAt {
            let stale = readAt.addingTimeInterval(Self.staleAfter)
            if stale > now { dates.append(stale) }
        }
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)), midnight > now {
            dates.append(midnight)
        }
        return dates.sorted()
    }
}
