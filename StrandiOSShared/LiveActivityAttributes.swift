#if os(iOS)
import Foundation
import ActivityKit

/// Live Activity attributes for an active live-HR / workout session. Shared between the app (which
/// starts/updates the activity) and the widget extension (which renders it on the Lock Screen and in
/// the Dynamic Island).
public struct NOOPActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var bpm: Int?
        public var recovery: Int?
        public var bonded: Bool
        // Effort / strain on NOOP's 0–100 axis (#446) — one more stat in the Dynamic Island expanded
        // region. OPTIONAL with a nil default so an activity started by an older build still decodes.
        public var effort: Int?
        // Strain formatted APP-SIDE on the user's selected axis, just like the widgets. Optional so
        // an older activity still decodes; its known 0–100 `effort` remains the display fallback.
        public var effortDisplay: String?
        // Heart-rate zone of `bpm` (1–5, 0 = below Zone 1), resolved APP-SIDE through the profile's
        // `hrZoneSet` so the banner uses the same zones as Live HR and workouts. Nil with no reading.
        // OPTIONAL with a nil default, like `effort`, so an activity started by an older build still decodes.
        public var zone: Int?

        public init(bpm: Int?, recovery: Int?, bonded: Bool, effort: Int? = nil, zone: Int? = nil,
                    effortDisplay: String? = nil) {
            self.bpm = bpm
            self.recovery = recovery
            self.bonded = bonded
            self.effort = effort
            self.zone = zone
            self.effortDisplay = effortDisplay
        }

        /// The selected-scale text, or the native 0–100 value for a banner an older build started.
        public var shownEffort: String? { effortDisplay ?? effort.map(String.init) }
    }

    /// Static title shown for the session.
    public var title: String

    public init(title: String = "Live HR") {
        self.title = title
    }
}
#endif
