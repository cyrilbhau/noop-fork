import Foundation
import StrandAnalytics

// Stage 2 (coach packet), specification §8.3: the flag, the range and the section switches. Three
// per-install preferences, deliberately outside the backup whitelist (specification §14.4, P14).

/// The coach packet's stored choices. Reading never writes: an absent or unusable stored value
/// reads as its default and is left exactly as it is.
final class CoachPacketSettings {
    static let enabledKey = "noop.coachPacketEnabled"
    static let rangeDaysKey = "coachPacket.rangeDays"
    static let sectionsKey = "coachPacket.sections"
    static let allowedRanges = [7, 14, 28]
    static let defaultRangeDays = 14

    /// The one observable copy of the flag, over the standard defaults. Views observe this;
    /// nothing declares another.
    @MainActor static let flag = ObservableDefaultsFlag(key: enabledKey)

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The feature flag. Off unless switched on.
    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    /// The range in days. A stored value outside `allowedRanges` reads as the default, and a value
    /// outside them is not stored.
    var rangeDays: Int {
        get {
            guard let stored = defaults.object(forKey: Self.rangeDaysKey) as? Int,
                  Self.allowedRanges.contains(stored) else { return Self.defaultRangeDays }
            return stored
        }
        set {
            guard Self.allowedRanges.contains(newValue) else { return }
            defaults.set(newValue, forKey: Self.rangeDaysKey)
        }
    }

    /// The sections that are on: the stored choices over each section's default.
    var sections: Set<CoachPacketSection> {
        let stored = storedChoices()
        return Set(CoachPacketSection.allCases.filter { stored[$0] ?? $0.isOnByDefault })
    }

    /// Stores one choice. The stored value is one JSON object of booleans keyed by section raw
    /// value, keys ascending, so the same choices always give the same bytes.
    func setSection(_ section: CoachPacketSection, on: Bool) {
        var choices = storedChoices()
        choices[section] = on
        let body = choices.keys.sorted { $0.rawValue < $1.rawValue }
            .map { "\"\($0.rawValue)\":\(choices[$0] == true ? "true" : "false")" }
            .joined(separator: ",")
        defaults.set("{\(body)}", forKey: Self.sectionsKey)
    }

    /// The choices the stored string validly names. A value that is not a string, does not parse,
    /// or holds a key that is no section or a value that is no boolean contributes nothing.
    private func storedChoices() -> [CoachPacketSection: Bool] {
        guard let raw = defaults.object(forKey: Self.sectionsKey) as? String,
              let object = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] else {
            return [:]
        }
        var choices: [CoachPacketSection: Bool] = [:]
        for (key, value) in object {
            guard let section = CoachPacketSection(rawValue: key), let number = value as? NSNumber,
                  CFGetTypeID(number) == CFBooleanGetTypeID() else { continue }
            choices[section] = number.boolValue
        }
        return choices
    }
}
