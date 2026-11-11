import Foundation

// The one day-key rule of the personal fork. Stage 1 (`CutScorecard`, ruling R5 of its specification)
// held it privately; the later stages each planned a copy. `CutScorecard` now calls this type, and so
// does every later stage, so that a day has one validation and one arithmetic.
//
// The calendar arithmetic itself is `WeeklyDigestEngine`'s (parse, format, Julian Day Number and its
// inverse), which is integer-only and already shared with the Kotlin side. This type adds the strict
// canonical form and the 0001 to 9999 range on top of it, exactly as `CutScorecard` did.
//
// No Kotlin twin: the owner has skipped Android for the personal fork, so every function here is
// unpaired in the parity ledger. The Kotlin `CutScorecard` keeps its own private copy of the rule.

/// The canonical day key: the ten-character "yyyy-MM-dd" form of a real proleptic-Gregorian date in
/// years 0001 to 9999, ASCII digits only. A day has exactly one key, and string order is calendar
/// order. Pure integer civil-date arithmetic: no `Date`, `Calendar`, `TimeZone` or clock.
public enum CanonicalDay {
    /// "0001-01-01" as a Julian Day Number. It is a Monday, so no week starts before it.
    public static let firstDayNumber = 1_721_426
    /// "9999-12-31" as a Julian Day Number.
    public static let lastDayNumber = 5_373_484

    /// True when `key` is a canonical day key.
    public static func isValid(_ key: String) -> Bool {
        dayNumber(key) != nil
    }

    /// The Julian Day Number of a canonical key, else nil. Julian Day Numbers divisible by seven are
    /// Mondays, so `number / 7` is a week index and `index * 7` that week's Monday.
    ///
    /// `WeeklyDigestEngine.parseYMD` alone is looser ("2031-1-8", "+2031-01-08"); the ten-byte length
    /// and the format round trip are what leave one key per day.
    public static func dayNumber(_ key: String) -> Int? {
        guard key.utf8.count == 10, let (y, m, d) = WeeklyDigestEngine.parseYMD(key),
              y >= 1, y <= 9999, WeeklyDigestEngine.formatYMD(y, m, d) == key else { return nil }
        return WeeklyDigestEngine.julianDayNumber(y, m, d)
    }

    /// The key of a Julian Day Number, or nil outside `firstDayNumber...lastDayNumber`.
    public static func key(dayNumber: Int) -> String? {
        guard dayNumber >= firstDayNumber, dayNumber <= lastDayNumber else { return nil }
        return clampedKey(dayNumber: dayNumber)
    }

    /// The key of a Julian Day Number clamped into `firstDayNumber...lastDayNumber`.
    public static func clampedKey(dayNumber: Int) -> String {
        let clamped = min(max(dayNumber, firstDayNumber), lastDayNumber)
        let (y, m, d) = WeeklyDigestEngine.fromJulianDayNumber(clamped)
        return WeeklyDigestEngine.formatYMD(y, m, d)
    }

    /// `key` moved by `days` (negative moves back). Nil when `key` is not canonical or the result is
    /// outside years 0001 to 9999. Never traps, whatever `days` is.
    public static func adding(_ days: Int, to key: String) -> String? {
        guard let number = dayNumber(key) else { return nil }
        let (sum, overflow) = number.addingReportingOverflow(days)
        guard !overflow else { return nil }
        return self.key(dayNumber: sum)
    }

    /// Whole days from `from` to `to` (positive when `to` is later). Nil unless both are canonical.
    public static func daysBetween(_ from: String, _ to: String) -> Int? {
        guard let a = dayNumber(from), let b = dayNumber(to) else { return nil }
        return b - a
    }

    /// -1 when `a` is earlier than `b`, 0 when they are the same day, 1 when later. Nil unless both
    /// are canonical.
    public static func compare(_ a: String, _ b: String) -> Int? {
        daysBetween(b, a)?.signum()
    }

    /// The Monday of the week containing `key`. Nil unless `key` is canonical. Forwards to
    /// `WeeklyDigestEngine.mondayOfWeek`, as `CutScorecard.weekStart(containing:)` always has.
    public static func weekStart(containing key: String) -> String? {
        guard dayNumber(key) != nil else { return nil }
        return WeeklyDigestEngine.mondayOfWeek(containing: key)
    }
}
