import Foundation

// The two spellings the stage specifications (stage 2 §6.2, stage 6 §6.0) and their committed tests
// call, forwarded to the scaffolding's own names. They add no rule: there is still one validation and
// one arithmetic, in `CanonicalDay.swift`.

extension CanonicalDay {
    /// The Julian Day Number of a canonical key, else nil. `dayNumber(_:)` under the name the stage
    /// specifications use.
    public static func number(_ key: String) -> Int? {
        dayNumber(key)
    }

    /// The key of a day number, clamped to 0001-01-01 … 9999-12-31. `clampedKey(dayNumber:)` under
    /// the name the stage specifications use.
    public static func key(_ number: Int) -> String {
        clampedKey(dayNumber: number)
    }
}
