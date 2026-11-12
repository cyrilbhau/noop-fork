import Foundation
import StrandImport

/// Stage 4 (body record), docs/personal/superapp/specs/stage-4.md §9.4: the two default-off switches
/// and the one decision that follows from them outside the body record's own screens.
///
/// - `noop.labReportUnitsEnabled` (4B): off, the Lab Book editor is exactly as it was; on, it offers
///   the extended unit table, parses with the device's decimal separator, keeps the typed value and
///   unit beside the stored one, and offers "Save and add another".
/// - `noop.bodyRecordEnabled` (4A): off, there is no Health row, no body-record screen or sheet, the
///   markers CSV import resolves names in the built-in scope and the weigh-in history is as it was.
///
/// Both are per-install toggles and are not in the backup whitelist (§9.5). Switching either off hides
/// its surfaces and deletes nothing. Each is observed through one shared `ObservableDefaultsFlag`;
/// nothing here reads a flag at launch: the instances are created when a view first asks for them.
enum BodyRecordSettings {
    static let enabledKey = "noop.bodyRecordEnabled"
    static let labReportUnitsKey = "noop.labReportUnitsEnabled"

    /// The one observable copy of `noop.bodyRecordEnabled`.
    @MainActor static let enabledFlag = ObservableDefaultsFlag(key: enabledKey)
    /// The one observable copy of `noop.labReportUnitsEnabled`.
    @MainActor static let labReportUnitsFlag = ObservableDefaultsFlag(key: labReportUnitsKey)

    /// §4.4, §7.1: the scope the Lab Book markers CSV import resolves names in. The wide scope exactly
    /// while the body record is on, so with it off an import is byte-identical to before.
    static func csvScope(bodyRecordEnabled: Bool) -> MarkerCatalogScope {
        bodyRecordEnabled ? .withBodyRecord : .builtIn
    }
}
