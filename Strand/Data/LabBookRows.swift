import Foundation
import WhoopStore

/// The app's ONE read path for Lab Book readings (personal fork, stage 1 ruling R42;
/// docs/personal/superapp/specs/labbook-ownership.md §6.2, §6.3).
///
/// A Lab Book reading is the owner's, whichever strap was active when it was entered. Every reader
/// (the Lab Book screen, the Coach roll-up, the weigh-in history, the body-measurement resolver and
/// through it the scorecard) reads here, so no screen can list one device id and hide the rest:
///
/// - "Every id" means every device id PRESENT IN THE TABLE, registered or not, any brand. It is not
///   a list built from the registry: such a list is what hid the readings under a forgotten strap.
/// - Rows equal in content under two ids are one reading and are listed once; rows at one instant
///   that differ are different readings and are both listed (`LabMarkerUnion.merged`).
/// - `activeDeviceId` only chooses which stored row stands for a set of copies. It filters nothing.
///
/// This is the only app-target file that names an all-id store read; `Tools/test_lab_book_single_read_path.py`
/// keeps it that way. A later stage reads through these functions and builds no union of its own.
/// Reads only: nothing here stores, moves or deletes a row.
///
/// Android is knowingly not updated (stage 1 ruling R43): its Lab Book still reads one device id.
enum LabBookRows {

    /// Every reading, every category, oldest first by (`takenAt`, `id`). Empty when the store read
    /// throws, as the readers it replaces behaved.
    static func all(store: WhoopStore, activeDeviceId: String) async -> [LabMarkerRow] {
        let stored = (try? await store.allLabMarkers()) ?? []
        return LabMarkerUnion.merged(stored, activeDeviceId: activeDeviceId)
    }

    /// Every reading of one category, oldest first by (`takenAt`, `id`). Empty when the read throws.
    static func category(_ category: String, store: WhoopStore, activeDeviceId: String) async -> [LabMarkerRow] {
        let stored = (try? await store.allLabMarkers(category: category)) ?? []
        return LabMarkerUnion.merged(stored, activeDeviceId: activeDeviceId)
    }

    /// Every reading of one marker, oldest first by (`takenAt`, `id`). Empty when the read throws.
    static func marker(_ markerKey: String, store: WhoopStore, activeDeviceId: String) async -> [LabMarkerRow] {
        let stored = (try? await store.allLabMarkers(markerKey: markerKey)) ?? []
        return LabMarkerUnion.merged(stored, activeDeviceId: activeDeviceId)
    }

    /// The stored rows of one marker under every id, NOT merged, in (`takenAt`, `id`) order: copies
    /// and conflicting rows are all returned. For write-side checks (is an instant free, which rows
    /// are copies of this one), where a failed read must refuse the write rather than look empty,
    /// so this one throws.
    static func stored(marker markerKey: String, store: WhoopStore) async throws -> [LabMarkerRow] {
        try await store.allLabMarkers(markerKey: markerKey)
    }
}
