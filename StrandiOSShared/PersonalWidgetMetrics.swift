import Foundation

// Personal iOS fork only. These values describe presentation and provenance; they do not alter
// analytics, storage schemas, protocol decoding, or the existing cross-platform score snapshot.
public struct PersonalWidgetMetrics: Codable, Equatable {
    public static let stepGoalKey = "personal.stepsGoal"
    public var steps: PersonalStepReading?
    public var sleep: PersonalSleepReading?
    public var stepGoal: Int?

    public init(steps: PersonalStepReading? = nil, sleep: PersonalSleepReading? = nil, stepGoal: Int? = nil) {
        self.steps = steps
        self.sleep = sleep
        self.stepGoal = stepGoal.flatMap { (1...50_000).contains($0) ? $0 : nil }
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

    public func recentSleep(now: Date, calendar: Calendar = .current) -> PersonalSleepReading? {
        guard let sleep, sleep.end <= now,
              let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return nil }
        let endDay = Self.dayKey(sleep.end, calendar: calendar)
        return endDay == Self.dayKey(now, calendar: calendar)
            || endDay == Self.dayKey(yesterday, calendar: calendar) ? sleep : nil
    }
}

public struct PersonalStepReading: Codable, Equatable {
    public enum Source: String, Codable { case whoop4MotionEstimate }

    public let count: Int
    public let day: String
    public let source: Source
    // The daily estimate has no durable calculation timestamp. nil deliberately means unknown,
    // never the publication time or the newest motion row that MAY not have been scored yet.
    public let observedAt: Date?

    public static func estimate(value: Double, day: String) -> Self? {
        guard value.isFinite, value >= 0, value.rounded() < Double(Int.max) else { return nil }
        return Self(count: Int(value.rounded()), day: day, source: .whoop4MotionEstimate, observedAt: nil)
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
