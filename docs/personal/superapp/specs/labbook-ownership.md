# Lab Book ownership specification

Gate G0 for the "Lab Book ownership" change that ruling R42 of the
[stage 1 specification](stage-1.md) ordered. Read [CONTEXT.md](../CONTEXT.md),
[QUALITY-GATES.md](../QUALITY-GATES.md), [ORCHESTRATION.md](../ORCHESTRATION.md) and stage 1 §8, §9,
§14 and §18 (R25, R29, R34, R36, R39, R41, R42, R43) first.

Verified against the source at commit `0b89b814` (branch `personal/superapp-1b-labbook-ownership-spec`,
cut from `personal/superapp-1-screens`, which carries stage 1). Every `path:line` is as of that
commit. Paths are relative to the repository root. Nothing was built or run for this document; it is
a reading of the code.

This file contains no personal measurement, target, date, medication or injury detail. Every value in
an example belongs to the fictional "Fixture Person" of §13, who is the Fixture Person of stage 1
§13. No private file is an input to this specification.

Reconciled with the cross-stage check on 11 November 2026; §17 lists what changed. This change is
**first in the integration order** (step 1 of the serialised build order): stage 2 and stage 4 are
written against what it leaves behind (§6.3).

## 1. Goal and scope

**Goal.** A strap being disconnected, removed, forgotten, re-paired or gone never deletes or hides a
Lab Book reading the owner entered, and every screen that lists or uses Lab Book readings reads them
through one path.

**In scope**

- A strap's "Delete data" and "Forget device" stop deleting `labMarker` rows.
- Serial-identity adoption stops moving `labMarker` rows, so it can no longer drop one.
- One read path for Lab Book rows across every device id present in the table, registered or not,
  used by the Lab Book screen, the Coach roll-up, the weigh-in history and the body-measurement
  resolver.
- The `lab-book` daily projection is computed across all ids, and a one-off idempotent repair brings
  existing projected cells into line without removing any.
- Lab Book writes that mean "this same reading again" (a re-imported file, an edit, a delete) act on
  the reading wherever it is stored.
- One added sentence on two existing confirmation dialogs.
- The read and write surface that stage 4 (body record) builds on, stated in §6.3, so that no later
  stage keeps a Lab Book union or a projection rule of its own.

**Out of scope**

- Any migration, new table, new column or new index. None is added (§9).
- Re-keying, moving, merging or deleting any existing row on upgrade.
- Other data the owner entered by hand that a strap delete removes today (in-app lift log, manual
  workouts, sleep marks). §4.4 lists each with a recommendation; each is its own change.
- A "delete all Lab Book readings" control, and recovery of readings lost before this change (§15).
- Android. No Kotlin is written (R43). §12.7 records the drift this creates.
- Any change to the scorecard, the resolver's precedence, the marker catalogue or the backup format.

## 2. Re-check of "what exists"

| # | Claim | Status | Evidence |
|---|---|---|---|
| 1 | `labMarker` is keyed by a client `id`; the natural key `(deviceId, markerKey, takenAt, source)` is a unique index | Confirmed | `Packages/WhoopStore/Sources/WhoopStore/Database.swift:330-356` |
| 2 | A strap delete clears `labMarker` | Confirmed. `labMarker` is in `deviceScopedTables`; the comment says it was added so that "delete all of this device's data" would not leave "user-entered lab/blood markers" behind, described as a privacy defect | `Packages/WhoopStore/Sources/WhoopStore/DeviceRegistryStore.swift:162-173`; the delete loop `:205-215` |
| 3 | Adoption re-keys with `UPDATE OR IGNORE` and then deletes what is left | Confirmed, for every table in the list and for the `-noop` sibling id. A row whose natural key already exists under the target id is ignored by the update and removed by the delete | `DeviceRegistryStore.swift:229-274`, the two statements at `:265-266` |
| 4 | Four callers reach the delete | Confirmed | Devices "Delete data" (`Strand/Screens/DevicesView.swift:294-311` to `Strand/Data/DeviceRegistry.swift:121-129`); Devices "Forget device" (`DevicesView.swift:2082-2108` to `DeviceRegistry.swift:138-147`); Apple Health "delete imported data" (`Strand/Screens/DataSourcesView.swift:746-766`, id `apple-health`); Oura disconnect (`Strand/Oura/OuraConnectModel.swift:70-78`, id `oura-api`). All reach `WhoopStore.deleteAllData` (`Packages/WhoopStore/Sources/WhoopStore/WhoopStore.swift:211-219`) |
| 5 | Two callers reach the adoption | Confirmed. A WHOOP id adopts only when it starts `whoop-`; the legacy `my-whoop` never does (`Packages/WhoopStore/Sources/WhoopStore/WhoopSerialIdentity.swift:51-53`) | WHOOP: `Strand/BLE/BLEManager.swift:5342-5367` (direct store call at `:5354`); Oura: `Strand/BLE/SourceCoordinator.swift:466-485` through `DeviceRegistry.swift:91-95` |
| 6 | "Remove" (archive) keeps data | Confirmed. It only sets the registry status | `DeviceRegistryStore.swift:59-63`, `Strand/App/AppModel.swift:1274-1281` |
| 7 | Lab Book reads and writes under `repo.deviceId` only | Confirmed | Read `Strand/Screens/LabBookView.swift:468-478`; manual write `Strand/Screens/MarkerEditorView.swift:425-442` and `LabBookView.swift:481-486`; CSV write `LabBookView.swift:263-283`; delete by id `LabBookView.swift:488-493` |
| 8 | The Coach roll-up reads under `repo.deviceId` only | Confirmed | `Strand/AI/AICoach.swift:1283-1300` |
| 9 | `repo.deviceId` follows the registry's active id | Confirmed | `Strand/Data/Repository.swift:131-138`, `:262-267`; `AppModel.swift:702-709` |
| 10 | The projection is per id | Confirmed. The cell is written under the constant `lab-book`, but its value is chosen from the rows of **one** device id | `Packages/WhoopStore/Sources/WhoopStore/LabMarkerStore.swift:96`, `:217-241` (the `WHERE deviceId = ?` at `:223`) |
| 11 | Stage 1 reads weight and waist across the active id, registered WHOOPs and the canonical id | Confirmed | `Strand/Data/BodyMeasurementProvider.swift:225-250`; `Strand/Data/WeighInStore.swift:84`, `:147-150`, `:196-200`; `Repository.swift:325-333` |
| 12 | A test pins that the delete list covers every `deviceId` table | Confirmed. It enumerates the live schema | `Packages/WhoopStore/Tests/WhoopStoreTests/DeviceRegistryStoreTests.swift:220-239` |
| 13 | The backup carries `labMarker` | Confirmed: the backup is the whole SQLite file in a ZIP, so every row under every id travels as stored, and a restore replaces the file | `Strand/Data/DataBackup.swift:227-246`, `:409`, `:577-578` |
| 14 | A precedent exists for a start-up data repair that is not a migration | Confirmed | `removeActivityOnlyWatchPairing` (`DeviceRegistryStore.swift:65-91`, run from `AppModel.swift:636`), and the read-side repair argued for at `DeviceRegistryStore.swift:310-319` ("a migration repairs the rows that exist when it runs, once") |
| 15 | The newest migration is `v47-rr-whoop5-fill` | Confirmed | `Database.swift:1103` |

## 3. Corrections to the planning documents

| # | Document says | The code says | Consequence |
|---|---|---|---|
| L1 | [ROADMAP.md](../ROADMAP.md) has no entry for this change. Stage 1 "Data design" (`ROADMAP.md:120-134`) says "No migration" and treats Lab Book storage as settled | R42 (`specs/stage-1.md:1713`) created a stored-data change after the roadmap was written | This specification is the only plan for it. The roadmap overview should gain a line "1b Lab Book ownership" before stage 2 |
| L2 | R25 and R29: rows are "de-duplicated by marker, instant and source, the active id's copy winning" (`specs/stage-1.md:1696`, `:1700`) | The implementation hides a row whose **value differs** from the active id's row at the same instant (`BodyMeasurementProvider.swift:245`; pinned by `StrandTests/WeighInStoreTests.swift:906-937`, where 100.4 is hidden behind 100.0) | Under R42 that is a hidden reading. §7.1 narrows the rule: only rows equal in content collapse |
| L3 | R29: "rows under an id that is no longer registered are not listed by this stage" | Pinned by `WeighInStoreTests.swift:1021-1047`, `StrandTests/WeighInCrossIdOccupancyTests.swift:414-445`, `StrandTests/WeighInOccupiedInstantTests.swift:215`, `:335` | These four tests assert the behaviour R42 reverses. The Test author rewrites them (§12.6) |
| L4 | R42: "Erasing all of the app's data on purpose is a different action and still removes them" | The app has **no** erase-all action. A search of `Strand/`, `StrandiOS/` and `Packages/WhoopStore/Sources` for a database-wide delete found none. The only whole-data removals are deleting the app from the phone and restoring a backup over the store (`DataBackup.swift:409`) | §8.6 states how each still works. No erase-all is added |
| L5 | S18 (`specs/stage-1.md:1602`): the alternative to R25 is "to store weigh-ins under the canonical id, which Lab Book does not read" | Android's Lab Book reads and writes only `my-whoop` (`android/app/src/main/java/com/noop/ui/LabBookScreen.kt:96`, `:123`; `android/app/src/main/java/com/noop/ingest/LabMarkerCsvImport.kt:52`), while Swift uses the active id | The two platforms already disagree about where a Lab Book row lives. Pre-existing; recorded in §12.7 |
| L6 | [CONTEXT.md](../CONTEXT.md) §4: the `event` table is where "Mark a Moment" might live ("Current writers were not surveyed") | Mark a Moment writes a list of instants to `UserDefaults` under `moments`, capped at 500 (`AppModel.swift:1880-1885`, read at `:439`). It never touches `event`. `event` holds strap events and app-version events under `noop-app` (`AppModel.swift:623-624`) | Stage 5 should not assume moments are in `event`. A strap delete does not remove moments |
| L7 | The stage 1 comment on `unionedDeviceIds` calls the union "the ids the repository already unions for imported history" | The repository's imported-history union is the active id plus the canonical id only (`Repository.swift:157-159`); the wider list with every registered WHOOP is the **raw physiology** union (`Repository.swift:282-288`, `:329-336`) | Naming only. The helper is removed by this change (§5) |
| L8 | `DeviceRegistry.forget` says "we never leave orphaned recordings behind a removed row" (`DeviceRegistry.swift:136-137`) | `deleteAllData(deviceId:)` matches the exact id. The computed sibling `<id>-noop` is not cleared by "Delete data" or "Forget" (`DeviceRegistryStore.swift:205-215`; contrast the adoption loop at `:263`) | Not caused or changed here. Reported in §16 |

## 4. Every reader and writer

### 4.1 `labMarker` rows

| Where | Reads or writes | Device id used today | After this change |
|---|---|---|---|
| `LabBookView.swift:468-478` `load()` | Reads every category | `repo.deviceId` | `LabBookRows.all` (§6.2) |
| `LabBookView.swift:481-486` `save(_:)` | Writes manual drafts | Draft carries `repo.deviceId` (`MarkerEditorView.swift:431`) | `upsertOwnerLabMarkers` (§6.1) |
| `LabBookView.swift:263-283` CSV import | Writes imported rows at local noon | `repo.deviceId` | `upsertOwnerLabMarkers` |
| `LabBookView.swift:488-493` `delete(_:)` | Deletes by id | The row's own | `deleteLabMarkerAndCopies` (§6.1) |
| `AICoach.swift:1283-1300` | Reads every category, latest per marker | `repo.deviceId` | `LabBookRows.category` |
| `BodyMeasurementProvider.swift:238-250` `labBookRows` | Reads weight or waist | Active, registered WHOOPs, canonical | Delegates to `LabBookRows.marker` |
| `BodyMeasurementProvider.swift:225-232` `unionedDeviceIds` | Registry read | — | Removed |
| `WeighInStore.swift:75-101` `save` | Writes weight and waist | `repo.deviceId` | Unchanged id; the occupancy check spans every id (§7.4) |
| `WeighInStore.swift:119-177` `edit` | Updates or replaces one row | The row's own | Also keeps the row's copies in step (§7.4) |
| `WeighInStore.swift:182-190` `delete` | Deletes one row | The row's own | `deleteLabMarkerAndCopies` |
| `WeighInStore.swift:196-200` `readings` | Reads | Through the provider | Unchanged call |
| `StrandiOS/Scorecard/ScorecardDemo.swift:235` | Debug seed on an in-memory store | `scorecard-demo` | Unchanged; this change does not edit the file (§12.11) |
| `DeviceRegistryStore.swift:205-215` `deleteAllData` | Deletes every row of one id | The strap id | No longer touches `labMarker` |
| `DeviceRegistryStore.swift:263-268` adoption | Moves, then deletes the remainder | Old and new strap ids | No longer touches `labMarker` |
| `DataBackup.swift` export and restore | The whole file | All | Unchanged |

No widget, notification, Live Activity or watch target reads `labMarker` (search of
`StrandiOSShared/`, `StrandiOSWidgets/`, `NOOPWatch*`).

### 4.2 The `lab-book` projection (`metricSeries` under device id `lab-book`)

| Where | Reads or writes |
|---|---|
| `LabMarkerStore.swift:217-241` `reprojectCells` | The only writer. Called from `upsertLabMarkers` (`:142`) and `deleteLabMarker` (`:199`) |
| `LabBookView.swift:906` | Reads one marker's projected series for "Compare with a signal" |
| `Repository.swift:1850-1861` `series(key:source:)` | Generic read; `lab-book` is read verbatim. Explore, Compare and correlation reach it through the metric catalogue |
| `deleteAllData` | Never reaches it: no caller passes `lab-book`, so a strap delete leaves the projected cells of the readings it deleted |

The resolver excludes the projection on purpose (stage 1 §8.2), so the body-measurement path does not
read it.

### 4.3 The registry and the active id

`repo.deviceId` is written only by `Repository.adoptActiveDeviceId` (`Repository.swift:262-267`).
Lab Book drafts and weigh-ins capture it at write time. Nothing in this change alters which id a new
row is written under (decision D4, §8.4).

### 4.4 Other data the owner entered by hand

"Removed by a strap delete" means: "Delete data" or "Forget device" on the strap that was active when
the row was written removes it today.

| Data | Where stored | Id it is written under | Removed by a strap delete today | Hidden when the active id changes | Recommendation |
|---|---|---|---|---|---|
| Lab Book readings, weigh-ins included | `labMarker` | Active id | **Yes** (`DeviceRegistryStore.swift:173`) | **Yes** in Lab Book and Coach; weight and waist only partly (stage 1 union) | **The owner's. Fixed by this change** |
| In-app lift log: exercises, programmes, programme items, sessions, sets | `liftExercise`, `liftProgram`, `liftProgramItem`, `liftSession`, `liftSet` | Active id (`Strand/Screens/LiftLogView.swift:217`, `:388-396`; `Strand/Screens/LiftSessionView.swift:951`, `:969`) | **Yes** (`DeviceRegistryStore.swift:197`; pinned by `Packages/WhoopStore/Tests/WhoopStoreTests/LiftLogStoreTests.swift:537-542`) | **Yes** (`LiftLogView.swift:391` reads the active id only) | The owner's. Same defect, same remedy; its own change ("Lift Log ownership") using the mechanism of §6.1. Asked in §15 |
| Imported lifting sessions (Hevy CSV, pasted text) | `liftSession`, `liftSet`, `workout` | Constant `lifting` (`Strand/Data/PersonalLiftingImport.swift:7`) | No. `lifting` is not a strap id | No | Already safe |
| Manual workouts and re-labelled detected bouts | `workout`, source `manual` | Active id (`Repository.swift:2995-3046`) | **Yes** | No: the Workouts list reads every registered WHOOP and the canonical id (`Repository.swift:2787`) but not an unregistered id, so "Forget" would hide what it had not deleted | The owner's. Own change; asked in §15 |
| Sleep marks (bedtime and wake taps) | `UserDefaults` `sleepMarks` and `metricSeries` key `sleep_mark` | Active id for the series (`AppModel.swift:1911`, `Strand/Screens/SleepView.swift:3706`) | The series row: **yes**. The defaults list: no | Series: yes | Low value on its own; fold into the manual-workout change |
| Native journal answers | `journal` | Constant `noop-journal` (`Repository.swift:2661`, `:2732-2745`) | No | No | Already safe |
| Journal answers imported from a WHOOP export | `journal` | The import's id, which the repository treats as the canonical `my-whoop` (`Repository.swift:144-152`; `Strand/Data/WhoopImporter.swift:165`) | **Yes, if the strap deleted is `my-whoop`** | No | Imported archive, not hand entry in this app, and not reproducible from the app alone. Asked in §15 |
| Custom journal questions | `UserDefaults` `journal.catalog.v2` (`Strand/Data/JournalCatalog.swift:20-21`) | — | No | No | Already safe |
| Mark a Moment | `UserDefaults` `moments` (`AppModel.swift:1880-1885`) | — | No | No | Already safe (see L6) |
| Cycle log | `metricSeries` under `noop-cycle` (`Strand/Data/CycleTrackingStore.swift:13`) | Constant | No | No | Already safe |
| Nutrition CSV | `metricSeries` under `nutrition-csv` | Constant | No | No | Already safe |
| Coach conversation | `coachMessage`, no device id (`Database.swift:915-923`) | — | No | No | Already safe |
| Scorecard phases, rules, reminder | `UserDefaults` | — | No | No | Already safe |
| Sleep edits and manual naps | `sleepSession` under computed ids | `<id>-noop` | No: the delete does not match the sibling id (L8) | No | Strap-derived rows the owner corrected. Not hand entry; no change proposed |
| Live coaching sessions | `liveSession` under the active id (`Strand/App/LiveSessionRunner.swift:255-258`) | Active id | Yes | — | Recorded from the strap. The strap's; stays |

The pattern in the rows marked "already safe" is the remedy the codebase already uses for owner data:
a constant source id that is not a strap. Lab Book and the in-app lift log are the two features that
did not follow it.

## 5. Final names

| Thing | Name | Place |
|---|---|---|
| Tables a strap never owns | `DeviceRegistryStore.ownerEnteredTables` | `Packages/WhoopStore/Sources/WhoopStore/DeviceRegistryStore.swift` |
| Tables a strap delete and an adoption act on | `DeviceRegistryStore.strapScopedTables` | Same file |
| Pure merge rules | `LabMarkerUnion` | New `Packages/WhoopStore/Sources/WhoopStore/LabMarkerOwnership.swift` |
| Reading identity at owner scope | `LabMarkerUnion.ReadingKey` | Same |
| All-id store reads | `WhoopStore.allLabMarkers()`, `allLabMarkers(category:)`, `allLabMarkers(markerKey:)`, `labMarkerDeviceIds()` | Same |
| Owner-scope upsert | `WhoopStore.upsertOwnerLabMarkers(_:)` | Same |
| Owner-scope delete | `WhoopStore.deleteLabMarkerAndCopies(id:)` | Same |
| In-transaction write steps, module-internal | `WhoopStore.LabBookDayCell`, `ownerUpsert(_:rows:)`, `deleteWithCopies(_:id:)`, `reprojectCells(_:cells:)` | `Packages/WhoopStore/Sources/WhoopStore/LabMarkerStore.swift` |
| Projection repair | `WhoopStore.repairLabBookProjection()`, result `LabBookProjectionRepair` | Same |
| The app's one read path | `LabBookRows` | New `Strand/Data/LabBookRows.swift` |
| Removed | `BodyMeasurementProvider.unionedDeviceIds(store:activeDeviceId:)` | `Strand/Data/BodyMeasurementProvider.swift:225-232` |
| New user-facing string | "Lab Book readings you entered are kept." | `Strand/Resources/Localizable.xcstrings` |
| Rehearsal input | Environment variable `NOOP_REHEARSAL_DB` | Read only by `LabBookOwnershipRehearsalTests` |
| Debug demo provider | `LabBookOwnershipDemo`, demo names `labbook-ownership` and `labbook-ownership-forgot` | New `StrandiOS/Scorecard/LabBookOwnershipDemo.swift` (§12.11) |
| Not created by any stage | `LabBookUnion`, `Strand/Data/LabBookUnion.swift` | Stage 4 reads through `LabBookRows` instead (§6.3) |

No storage key, setting, flag, catalogue key, table, column or index is added.

## 6. API

### 6.1 `Packages/WhoopStore`

```swift
public struct DeviceRegistryStore {
    /// Every table with a `deviceId` column. Unchanged, and still what the schema-coverage test checks.
    static let deviceScopedTables: [String]
    /// Tables whose rows the owner entered. A strap delete and an adoption never touch them.
    static let ownerEnteredTables: Set<String>          // ["labMarker"]
    /// `deviceScopedTables` without `ownerEnteredTables`, in the same order.
    static var strapScopedTables: [String] { get }
    public func deleteAllData(deviceId: String) throws                                   // iterates strapScopedTables
    public func adoptSerialIdentity(from activeId: String, to serialId: String) throws -> Bool   // iterates strapScopedTables
}

public enum LabMarkerUnion {
    public struct ReadingKey: Hashable, Sendable {
        public let markerKey: String
        public let takenAt: Int
        public let source: String
    }
    public static func key(_ row: LabMarkerRow) -> ReadingKey
    /// The same reading stored twice: equal in every column except `id`, `deviceId` and `day`.
    public static func isCopy(_ a: LabMarkerRow, _ b: LabMarkerRow) -> Bool
    /// One row per distinct reading, oldest first.
    public static func merged(_ rows: [LabMarkerRow], activeDeviceId: String) -> [LabMarkerRow]
    /// `row` and every copy of it found in `rows`, ordered by (`deviceId`, `id`).
    public static func copies(of row: LabMarkerRow, in rows: [LabMarkerRow]) -> [LabMarkerRow]
    /// Keys held by two or more rows that are not copies of each other, ordered by (takenAt, markerKey, source).
    public static func conflictingKeys(_ rows: [LabMarkerRow]) -> [ReadingKey]
}

public struct LabBookProjectionRepair: Equatable, Sendable {
    public let inserted: Int      // cells that were missing
    public let updated: Int       // cells replaced by the correct value
    public let unchanged: Int     // cells already correct
    public let unbackedKept: Int  // cells left exactly as stored (§7.3)
}

extension WhoopStore {
    /// Every stored row, under any device id. Ordered by (takenAt, id) ascending.
    public func allLabMarkers() async throws -> [LabMarkerRow]
    public func allLabMarkers(category: String) async throws -> [LabMarkerRow]
    public func allLabMarkers(markerKey: String) async throws -> [LabMarkerRow]
    /// Distinct device ids that hold at least one row, ascending.
    public func labMarkerDeviceIds() async throws -> [String]
    /// Returns the number of stored rows inserted or updated.
    @discardableResult public func upsertOwnerLabMarkers(_ rows: [LabMarkerRow]) async throws -> Int
    /// Returns the ids deleted, ascending. Empty when `id` is not stored.
    @discardableResult public func deleteLabMarkerAndCopies(id: String) async throws -> [String]
    @discardableResult public func repairLabBookProjection() async throws -> LabBookProjectionRepair
}
```

The existing per-id functions (`labMarkers(deviceId:category:)`, `labMarkers(deviceId:markerKey:)`,
`markerKeysPresent(deviceId:)`, `upsertLabMarkers`, `deleteLabMarker(id:)`,
`LabMarkerStore.swift:112-202`) keep their signatures and their behaviour, except that their
projection step follows §7.2. The stage 1 tests and the weigh-in store call them.

The three write rules are also available as steps that run inside a transaction the caller already
holds. They are module-internal (no `public`), live in `LabMarkerStore.swift`, and are what the
public functions above call inside their own `syncWrite`:

```swift
extension WhoopStore {
    /// One projected cell. It carries no device id (§7.2). Replaces the private `DayCell`
    /// (`LabMarkerStore.swift:205-209`).
    struct LabBookDayCell: Hashable {
        let markerKey: String
        let day: String
    }
    /// §7.4 owner-scope upsert, without the projection step. `written` is the number of stored rows
    /// inserted or updated; `touched` holds every cell to recompute, the old day of an updated row
    /// included.
    func ownerUpsert(_ db: Database, rows: [LabMarkerRow]) throws -> (written: Int, touched: Set<LabBookDayCell>)
    /// §7.4 delete of a row and its copies, without the projection step. `deleted` is ascending and
    /// empty when `id` is not stored.
    func deleteWithCopies(_ db: Database, id: String) throws -> (deleted: [String], touched: Set<LabBookDayCell>)
    /// §7.2 for each cell. Was `private`; now internal, with the device-id filter removed.
    func reprojectCells(_ db: Database, cells: Set<LabBookDayCell>) throws
}
```

`upsertOwnerLabMarkers` is `ownerUpsert` then `reprojectCells` in one `syncWrite`;
`deleteLabMarkerAndCopies` is `deleteWithCopies` then `reprojectCells`. `upsertLabMarkers` and
`deleteLabMarker` keep their own statements and call the same `reprojectCells`. Tests reach the
three steps through `@testable import WhoopStore` only where §12.2 says so; the app target cannot
call them.

### 6.2 App target

```swift
// Strand/Data/LabBookRows.swift
enum LabBookRows {
    /// Every reading, every category: `LabMarkerUnion.merged` over `allLabMarkers()`.
    static func all(store: WhoopStore, activeDeviceId: String) async -> [LabMarkerRow]
    static func category(_ category: String, store: WhoopStore, activeDeviceId: String) async -> [LabMarkerRow]
    static func marker(_ markerKey: String, store: WhoopStore, activeDeviceId: String) async -> [LabMarkerRow]
    /// The stored rows of one marker, not merged, for the write-side checks of §7.4.
    static func stored(marker markerKey: String, store: WhoopStore) async throws -> [LabMarkerRow]
}
```

The three merged reads return an empty list when the store read throws, as the readers they replace
do (`LabBookView.swift:474`, `AICoach.swift:1287`, `BodyMeasurementProvider.swift:244`).
`BodyMeasurementProvider.labBookRows(_:store:activeDeviceId:)` keeps its signature and becomes one
call to `LabBookRows.marker`.

### 6.3 What later stages build on (cross-check X1, X2, X17)

This change merges before stage 2's extraction in `AICoach.swift` and before any stage 4 code that
reads or writes Lab Book rows. The following is the whole contract those stages are written against.
Stage 4's own design is in [stage 4](stage-4.md) §9; this section fixes only what it may assume and
what it may not add.

- **One union.** `LabBookRows` is the only Lab Book union in the app target. Stage 4 creates no
  `LabBookUnion` and no file `Strand/Data/LabBookUnion.swift`. It reads a category through
  `LabBookRows.category` and one marker through `LabBookRows.marker`. `weight` and `waist` are still
  read through `WeighInStore.readings`, which reaches the same funnel.
- **Ids.** `BodyMeasurementProvider.unionedDeviceIds` does not exist after this change. No stage
  builds a device-id list from the registry to read Lab Book rows. "Every id" means every device id
  present in `labMarker` (D2).
- **Occupancy.** A check that an instant is free for a marker and source reads
  `LabBookRows.stored(marker:store:)` and looks at rows under every id. A row under an unregistered
  or other-brand id occupies the instant.
- **Scan identity.** A group of rows that stage 4 treats as one scan is identified at owner scope:
  each member by `LabMarkerUnion.key`, never by `(deviceId, source, takenAt)`. A conflicting row at
  the same identity under another id is a different reading (§7.1) and is listed, not hidden.
- **Scan delete and replace.** Removing a stored row on the owner's behalf removes its copies under
  the rule of `deleteLabMarkerAndCopies` (§7.4), so a deleted scan cannot reappear from a copy under
  another id.
- **`replaceLabMarkers(deleteIds:upsert:)`** is stage 4's function (work package 4-4c), added to
  `LabMarkerStore.swift` after LO-2 has merged. Inside its single `syncWrite` it calls
  `deleteWithCopies` for each id, `ownerUpsert` for the rows, and one `reprojectCells` over the union
  of the touched cells (§6.1). It does not repeat the per-id `INSERT … ON CONFLICT` statement and
  does not project per device id. This change adds no `replaceLabMarkers`.
- **Coach roll-up.** After this change the roll-up reads `LabBookRows.category`
  (`AICoach.swift:1283-1300`). Stage 2 captures its byte-identity baseline for the extraction after
  this change is merged. Stage 4's skip of scan and benchmark keys is one line written against the
  `LabBookRows` read.
- **Fixture.** Stage 4's cross-id store tests use the device labels and rules of §13 (active,
  archived, unregistered and other-brand ids; copies collapse, conflicts are both listed).
- **Source scan.** Test 68's allowlist (§12.4) is the list of files allowed to name a per-id or
  all-id Lab Book read. A stage that needs a new entry adds the file and its reason in its own
  change; it does not widen a pattern.

One writer at a time edits `LabMarkerStore.swift`: LO-2, then 4-4c.

## 7. Rules, decided

### 7.1 Which rows are one reading (`LabMarkerUnion`)

- **Identity.** A reading's identity at owner scope is `(markerKey, takenAt, source)`: the store's
  natural key without the device id.
- **Copy.** Two rows are copies when `markerKey`, `takenAt`, `source`, `category`, `value`,
  `valueText`, `unit`, `note` and `referenceText` are all equal. Optionals compare with `==`; a `nil`
  equals only `nil`. `id`, `deviceId` and `day` are not compared. `day` is left out for the reason
  R39 gives: it is derived from the instant and the zone of the write.
- **Conflict.** Rows with one identity that are not copies are different readings. Both are listed.
  Neither is hidden, merged or changed.
- **`merged(rows, activeDeviceId)`.** Sort the input by `takenAt` ascending, then rows whose
  `deviceId` equals `activeDeviceId` first, then `deviceId` ascending, then `id` ascending. Walk it,
  keeping a row unless an already kept row is a copy of it. Return the kept rows ordered by
  (`takenAt`, `id`) ascending. So a set of copies is represented by the active id's row when there is
  one, else by the row with the smallest `deviceId`, then the smallest `id`. An input with no two
  rows sharing an identity comes back unchanged apart from order.
- `merged` is a read rule. It stores, moves and deletes nothing.

This replaces R25's "de-duplicated by marker, instant and source". "The active id's copy wins" still
holds, for copies only. The resolver's same-day rule (stage 1 §8.2: greatest `takenAt`, then greatest
`id`) already orders two conflicting rows deterministically.

### 7.2 Projection

For one cell `(markerKey, day)`: the value is that of the row with the greatest `takenAt`, then the
greatest `id`, among **all** rows of that marker and day with a non-null `value`, under any device
id. With no such row the cell is deleted. `reprojectCells` (`LabMarkerStore.swift:217-241`) drops its
device-id filter and its cells lose the device id (`LabBookDayCell`, §6.1). The tie-break matches
`LabBookProjection.project(.latest)` fed in (`takenAt`, `id`) order
(`Packages/StrandAnalytics/Sources/StrandAnalytics/LabBookProjection.swift:139-146`), and matches the
resolver, so the projected point, the Lab Book card and the resolver name the same reading for a day.

There is no index on `(markerKey, day)` and none is added. The table holds hand-entered rows; the
implementer may fold all touched cells from one query per touched marker key.

### 7.3 Projection repair (`repairLabBookProjection`)

One write transaction:

1. `expected`: fold every row with a non-null `value` into cells by §7.2.
2. `stored`: every `metricSeries` row with `deviceId = 'lab-book'`.
3. For each expected cell: absent from `stored`, insert it (`inserted`); present and equal,
   leave it (`unchanged`); present and different, and the stored value equals the `value` of at least
   one existing row of that marker and day, replace it (`updated`); present and different, and the
   stored value matches no existing row of that marker and day, leave it (`unbackedKept`).
4. For each stored cell with no expected cell, leave it (`unbackedKept`).

Why step 3 distinguishes: a cell whose value no surviving row holds is the last trace of a reading
that an earlier strap delete or adoption removed. The repair never destroys it. It is idempotent: a
second run reports `inserted == 0` and `updated == 0`. Comparison is `==` on the stored doubles.

An unbacked cell stays until the owner writes or deletes a reading on that marker and day, when §7.2
recomputes the cell as it does today.

The repository calls it once per launch, straight after the store opens, in the single-flight open at
`Repository.swift:769-803` (after `:797`), ignoring a thrown error. It logs one line through the
existing strap log only when `inserted + updated > 0`, carrying the four counts and no value.

### 7.4 Writes

- **`upsertOwnerLabMarkers(rows)`**, one transaction. For each incoming row: find every stored row
  with the same `(markerKey, takenAt, source)` under any id. If there is none, insert the row as
  given. Otherwise update each of those stored rows in place: `category`, `day`, `value`, `valueText`,
  `unit`, `note` and `referenceText` take the incoming values; `id` and `deviceId` keep the stored
  ones. Then recompute the cell of every `(markerKey, day)` touched, the old day of an updated row
  included. This is the store's existing rule, "re-importing the same reading updates it"
  (`LabMarkerStore.swift:100-103`), applied without regard to which strap was active.
- **`deleteLabMarkerAndCopies(id)`**, one transaction. Load the row; load every row with its
  identity; delete those for which `LabMarkerUnion.isCopy` holds, the row itself included; recompute
  their cells. A conflicting row at the same identity is not deleted. Reason: the list shows a set of
  copies once, so deleting only the representative would make the reading reappear, the
  visible-but-undeletable defect recorded at `Repository.swift:290-297`.
- **Lab Book screen.** `save` and the CSV import call `upsertOwnerLabMarkers`; `delete` calls
  `deleteLabMarkerAndCopies`. Drafts are still built with `repo.deviceId`.
- **Weigh-in store.** A new row is still written under `repo.deviceId` (R25 stands). "Unioned ids"
  becomes "every id":
  - `save`: a manual row of the marker at that instant under the active id is the row the save lands
    on (R34, unchanged). With none there, a manual row of the marker at that instant under **any**
    other id refuses the weigh-in with `instantOccupied` (R36, widened).
  - `edit`, same instant: the row and each of its copies take the new value and unit, each under its
    own id, in one `upsertLabMarkers` call.
  - `edit`, another instant: occupants are the stored rows of the marker and source at the target
    instant under any id. With no occupant: insert the replacement under the edited row's device id,
    then `deleteLabMarkerAndCopies` the old row. When every occupant is a copy of the replacement
    (R36 and R39's exception, generalised from "exactly one occupant"): write nothing and
    `deleteLabMarkerAndCopies` the old row. Otherwise `instantOccupied`, nothing written.
  - `delete`: `deleteLabMarkerAndCopies`.
- **Strap delete and adoption.** Both iterate `strapScopedTables`. Neither issues any statement
  against `labMarker` or against `metricSeries` rows of `lab-book` on behalf of Lab Book.

## 8. Design decision

### 8.1 Options

**Option 1. Leave rows where they are; exempt owner tables from strap operations; read across every
id present.**

- Upgrade touches no `labMarker` row. Rollback to the previous build finds the table exactly as it
  left it.
- No migration. No clash can arise because nothing moves.
- Cost: readers must not filter by device id, and a source scan has to keep it that way. Rows stay
  spread over several ids for good. Writes need the owner-scope rules of §7.4.
- Risk: a future reader written against one id. Mitigated by §12.4.

**Option 2. Re-key every owner row to one stable owner id on upgrade.**

- Is it a migration? A registered GRDB migration is the repository's only sanctioned way to rewrite
  stored rows once, it needs a Room twin that will not be written (R43), and its name has to be
  placed against the upstream sequence (CONTEXT §7 item 4). Run instead as an unregistered idempotent
  repair at launch, it is still a rewrite of the owner's only copy, repeated against every restored
  backup.
- Natural-key clashes: two rows with one `(markerKey, takenAt, source)` under two ids cannot both
  take the same device id; the unique index forbids it (`Database.swift:346-349`). Keeping both means
  either changing one row's `takenAt` or `source` (an overwrite of what the owner recorded) or
  leaving the clashing row under its old id, in which case readers must union across ids anyway.
  Option 2 therefore contains option 1's read path and adds a rewrite.
- Benefit: later writes are idempotent by the unique index alone. §7.4 obtains the same result
  without moving anything.
- Risk: the highest of the three. A fault in the re-key runs against the installed database.

**Option 3. A new owner-scoped column or table.**

- A migration, with the owner's go-ahead, an upstream-name collision risk and an unwritten Room twin.
  Existing rows still have to be copied or re-keyed (option 2's clash question again). A second table
  doubles the places a reading can be until the first is retired.
- Benefit: the cleanest long-term model, and the right shape if a later stage needs owner-scoped
  storage that is not a marker.

### 8.2 Recommendation

**Option 1.** It is the only option under which the installed database is not rewritten, which is the
property the owner asked for, and it needs no migration, target, entitlement, Health access or
network path. Options 2 and 3 are fully described above as the alternatives; either would need the
owner's go-ahead and neither is proposed.

### 8.3 What happens on upgrade

| Existing state | After the first launch of the new build |
|---|---|
| Rows under the active id | Untouched. Listed as before |
| Rows under another registered id (archived or paired, any brand) | Untouched. Now listed in Lab Book and the Coach roll-up |
| Rows under an id with no registry row (a forgotten strap, an id left by adoption) | Untouched. Now listed everywhere, weigh-in history and resolver included |
| Copies under two ids | Both stay stored. Listed once |
| Conflicting rows at one instant under two ids | Both stay stored. Both listed (stage 1 listed one) |
| A projected cell that is missing or holds the wrong one of the day's readings | Inserted or corrected by the repair |
| A projected cell no surviving reading backs | Left exactly as stored and counted |
| Rows an earlier strap delete already removed | Not recoverable from `labMarker`. See §15 Q3 |

No existing `labMarker` row is deleted, overwritten, moved or hidden by upgrading. The only stored
values the upgrade changes are derived projection cells whose correct value is still held by a row.

### 8.4 Decisions where the plan left a choice

| # | Decision | Reason |
|---|---|---|
| D1 | Option 1 | §8.2 |
| D2 | The union is every device id present in `labMarker`, not a list built from the registry | A registry-built list is what hid rows under a forgotten strap (L3); the table itself is the only complete answer |
| D3 | Only content-equal rows collapse; conflicting rows are both listed | R42: nothing hidden (L2) |
| D4 | New rows keep being written under the active id | R25 is an owner decision; every id is read, so the id no longer matters; no stage 1 write test changes |
| D5 | A set of copies behaves as one reading for edit and delete | Otherwise a delete appears to do nothing (`Repository.swift:290-297`) |
| D6 | Lab Book's own writes use owner-scope upsert; the weigh-in sheet keeps refusing an occupied instant | A re-imported file must update, not double, now that old ids are listed; the sheet's refusal is the conservative R36 behaviour and the case is rare |
| D7 | Adoption does not move owner rows at all | The simplest rule under which a clash cannot drop a row |
| D8 | The projection repair keeps unbacked cells | They may be the last trace of a lost reading |
| D9 | No setting gates any of it | §8.5 |
| D10 | The in-app lift log and manual workouts are not included | One concern per pull request; each needs its own reader changes (§4.4) |
| D11 | The repair is a launch-time idempotent step, not a registered migration | It rewrites derived cells only, must also run on a database restored later, and has the precedents of §2 row 14 |

### 8.5 Flag behaviour

The change ships **on, with no setting**, and independent of `noop.cutScorecardEnabled`.

- The protections live in the store. A switch that could turn them off would be a switch that lets a
  strap delete remove the owner's readings again.
- It adds no screen, card, widget, notification or tab. An existing list shows more of the owner's
  own rows, and two dialogs gain a sentence.
- For an install whose rows all sit under the active id, every reader returns exactly what it
  returns today (§12.5 proves it), so the common case is unchanged.
- Nothing stored is rewritten, so reinstalling the previous build is a complete rollback.
- With the scorecard flag off, the weight and waist readers stay on their legacy policies and do not
  read Lab Book at all (stage 1 §8.3). That is unchanged.

### 8.6 How whole-data removal still works

- **Deleting the app** removes its container and the database in it. Unchanged.
- **Restoring a backup** replaces the database file (`DataBackup.swift:409`); the restored file's
  rows are then read by the same path, and the repair runs at the next launch.
- **One reading** is deleted from Lab Book or the weigh-in history, under whichever id it sits.
- There is no in-app "erase everything" today (L4), so none can regress.

### 8.7 Adoption

`adoptSerialIdentity` moves and clears only `strapScopedTables`. `labMarker` rows written under the
provisional id stay under it. That id's registry row is removed (`DeviceRegistryStore.swift:270`), so
the rows sit under an unregistered id, which every reader now includes. Nothing is ignored, so
nothing is dropped. The `UPDATE OR IGNORE` then `DELETE` pair is unchanged for strap tables, where
"the target id's row wins" is the intended rule for duplicate samples; the owner-entered rows that
live in strap tables (§4.4) remain exposed to it and are named in §15 Q2.

## 9. Storage

No schema change. `labMarker` and `metricSeries` keep their columns, keys and indexes.

| Stored thing | Change |
|---|---|
| `labMarker` rows | None on upgrade. Afterwards written, edited and deleted only by the owner's actions |
| `metricSeries` under `lab-book` | Repaired per §7.3; afterwards maintained per §7.2 |
| `.noopbak` settings whitelist | No key added, so this change has no entry in the fork-only backup keys comment. Kotlin side: not updated, by the owner's decision; there is nothing to update |
| Marker catalogue | Untouched. Kotlin side: not updated, by the owner's decision; nothing to update |
| `.noopbak` database | Same file. A backup written by the new build restores into the old build and the reverse |

## 10. States

### 10.1 Lab Book list (`LabBookView`)

| State | Shown |
|---|---|
| Not loaded | As today |
| No readings under any id | The existing empty state |
| Readings under the active id only | As today, identical |
| Readings under several ids, registered or not | One list, oldest first within a marker; nothing indicates which strap was active |
| Copies under two ids | One line |
| Conflicting readings at one instant | Two lines with the same date and their own values; each has its own delete control |
| Qualitative reading (no number) | Listed; not projected, as today |
| Store cannot be opened | As today: the list stays as it was |
| After a strap's "Delete data" or "Forget device" | Unchanged |
| After the strap is re-paired or adopts a serial id | Unchanged |

### 10.2 Devices dialogs

| Dialog | Message |
|---|---|
| "Delete all of this device's data?" (`DevicesView.swift:294-311`) | The existing sentence, then "Lab Book readings you entered are kept." |
| "Forget this device?" (`DevicesView.swift:2089-2105`) | The existing sentence, then "Lab Book readings you entered are kept." |

The Apple Health and Oura delete paths show their own existing text and are not changed.

### 10.3 Weigh-in history and scorecard (stage 1 screens)

No new state. A reading under an unregistered id now appears in the history and the weekly series;
conflicting readings at one instant both appear in the history, and the resolver picks by its
existing rule. Edit and delete follow §7.4.

### 10.4 Widgets, notifications, Live Activities

None read Lab Book. No state is added. Nothing new leaves the app.

## 11. User-facing strings

| Key | Where | Note |
|---|---|---|
| `Lab Book readings you entered are kept.` | Appended to both dialog messages as a second `Text`, joined to the first by a space | New. Ten locales (`en` plus the nine in the catalogue). The existing keys `This permanently deletes all data recorded from %@. This can't be undone.` and `NOOP removes this device from your list and deletes its recorded data here. You can re-pair the strap to pull its recent history back.` are not edited |

The log line of §7.3 is diagnostic text, English only, and carries counts only.

## 12. Test plan

### 12.1 Pure rules — `Packages/WhoopStore/Tests/WhoopStoreTests/LabMarkerUnionTests.swift`

1. `testRowsWithDistinctIdentitiesAllSurviveMergeInInstantOrder`
2. `testCopiesUnderTwoIdsCollapseToTheActiveIdsRow`
3. `testCopiesWithNoActiveRowCollapseToTheSmallestDeviceIdThenSmallestId`
4. `testThreeCopiesCollapseToOne`
5. `testRowsDifferingInValueAtOneIdentityAreBothKept`
6. `testRowsDifferingOnlyIn` + each of `Unit`, `Note`, `ReferenceText`, `ValueText`, `Category` + `AreBothKept` (five tests)
7. `testRowsDifferingOnlyInDayAreCopies`
8. `testRowsDifferingInSourceAreDifferentReadings`
9. `testNilAndZeroValuesAreNotCopies`
10. `testMergeOfAnEmptyListIsEmpty`
11. `testMergeIsIndependentOfInputOrder` (every permutation of the §13 rows gives one result)
12. `testMergeOfSingleIdRowsReturnsThemUnchanged`
13. `testCopiesOfReturnsTheRowAndItsCopiesOnly`
14. `testConflictingKeysNamesOnlyIdentitiesWithNonCopies`
15. `testTwoCopiesPlusOneConflictListTwoReadings`

### 12.2 Store — `LabMarkerOwnershipStoreTests.swift`, `LabBookProjectionRepairTests.swift`, additions to `DeviceRegistryStoreTests.swift`

Strap operations:

16. `testDeleteAllDataLeavesEveryLabMarkerRowOfThatDevice` (byte-identical rows before and after)
17. `testDeleteAllDataStillClearsEveryStrapScopedTableOfThatDevice` (one seeded row per table)
18. `testDeleteAllDataLeavesTheLabBookProjectionUntouched`
19. `testOwnerEnteredTablesAreASubsetOfDeviceScopedTables`
20. `testStrapScopedTablesIsDeviceScopedTablesWithoutOwnerEnteredTablesInOrder`
21. `testLabMarkerIsOwnerEntered`
22. `testAdoptSerialLeavesLabMarkerRowsUnderTheProvisionalId`
23. `testAdoptSerialWithAClashingLabMarkerUnderTheSerialIdKeepsBothRows` (the dropped-row case)
24. `testAdoptSerialStillMovesStrapRowsAndTheComputedSibling` (existing behaviour kept)
25. `testRemoveRegistryRowLeavesLabMarkerRows`
26. The existing `testDeviceScopedTablesCoversEveryDeviceIdKeyedTable` stays unedited and green.

All-id reads and owner-scope writes:

27. `testAllLabMarkersReturnsRowsUnderRegisteredUnregisteredAndOtherBrandIds`
28. `testAllLabMarkersByCategoryAndByMarkerFilterOnly`
29. `testLabMarkerDeviceIdsListsEachIdOnce`
30. `testUpsertOwnerInsertsWhenNoIdHoldsTheIdentity`
31. `testUpsertOwnerUpdatesTheRowUnderAnotherIdInPlaceKeepingItsIdAndDeviceId`
32. `testUpsertOwnerUpdatesEveryRowAtTheIdentityAcrossIds`
33. `testUpsertOwnerReimportOfTheSameRowsIsANoOpInRowCount`
34. `testUpsertOwnerMovingADayRecomputesBothCells`
35. `testDeleteAndCopiesRemovesTheRowAndItsCopiesAcrossIds`
36. `testDeleteAndCopiesLeavesAConflictingRowAtTheSameIdentity`
37. `testDeleteAndCopiesOfAnUnknownIdDeletesNothing`
38. `testDeleteAndCopiesNeverTouchesAnotherMarkerOrInstant` (bystander rows byte-identical)
80. `testOwnerUpsertAndDeleteWithCopiesComposeInOneTransaction` (through `@testable import`: inside
    one `syncWrite`, `deleteWithCopies` of F7 then `ownerUpsert` of a new `ldl` row at T4 then one
    `reprojectCells` over both touched sets leaves no `ldl` cell on `2031-01-15` and one on
    `2031-01-29`; a throw after the delete leaves all ten rows and all six cells as they were)

Projection:

39. `testProjectionPicksTheLatestReadingOfTheDayAcrossIds`
40. `testProjectionTieOnInstantPicksTheGreatestId`
41. `testDeletingOneIdsLastReadingOfADayKeepsTheCellWhenAnotherIdHasOne` (the R29 quirk)
42. `testWritingAnEarlierReadingUnderOneIdDoesNotReplaceALaterOneUnderAnother`
43. `testQualitativeRowsNeverProject`
44. `testRepairInsertsAMissingCell`
45. `testRepairCorrectsACellHoldingAnotherOfTheDaysReadings`
46. `testRepairKeepsACellWhoseValueNoRowHolds`
47. `testRepairKeepsACellWithNoRowsThatDay`
48. `testRepairIsIdempotent`
49. `testRepairOnAnEmptyTableChangesNothing`
50. `testRepairLeavesMetricSeriesOfOtherSourcesUntouched`
51. `testRepairDoesNotChangeAnyLabMarkerRow`

### 12.3 App target — `StrandTests/LabBookRowsTests.swift`, `StrandTests/LabBookOwnershipFlowTests.swift`

52. `testLabBookListShowsReadingsUnderEveryId`
53. `testCoachRollUpUsesTheLatestReadingAcrossIds`
54. `testWeighInHistoryAndResolverSeeAReadingUnderAnUnregisteredId`
55. `testListCoachHistoryAndResolverAgreeOnTheNewestWeight` (single-path, behavioural)
56. `testReadingsSurviveDeleteDataOnTheStrapTheyWereEnteredUnder` (through `DeviceRegistry.deleteDeviceData`)
57. `testReadingsSurviveForgetDevice`
58. `testReadingsSurviveArchiveThenANewActiveStrap`
59. `testReadingsSurviveSerialAdoption`
60. `testCsvReimportAfterTheActiveIdChangedUpdatesInsteadOfDoubling`
61. `testLabBookDeleteOfACollapsedReadingRemovesItForGood`
62. `testWeighInValueEditKeepsCopiesInStep`
63. `testWeighInDateEditRemovesTheOldReadingAndItsCopies`
64. `testWeighInSaveOntoAnInstantHeldUnderAnUnregisteredIdIsRefused`
65. `testInterruptedDateEditStillCompletesOnRetryWhenCopiesExist`
66. `testRepositoryOpenRunsTheProjectionRepairOnce`
67. `testAFailedStoreReadLeavesTheLabBookListAsItWas`

### 12.4 Source scan — `Tools/test_lab_book_single_read_path.py`

68. No file under `Strand/`, `StrandiOS/`, `StrandiOSShared/`, `StrandiOSWidgets/` or `NOOPWatch*`
    contains `labMarkers(deviceId:`, `allLabMarkers(`, `markerKeysPresent(` or a SQL string naming
    `labMarker`, outside a literal allowlist of file-and-reason pairs: `Strand/Data/LabBookRows.swift`
    (the funnel) and `Strand/Data/WeighInStore.swift` (row lookup under a row's own id).
69. Each allowlisted file still contains its pattern, so a stale entry fails.
70. `DeviceRegistryStore.swift` contains `strapScopedTables` in both `deleteAllData` and
    `adoptSerialIdentity` and does not iterate `deviceScopedTables` in either.
71. `Tools/test_body_measurement_single_resolver.py` is updated by the Test author where it names the
    lines this change rewrites (`:66`, `:88`, `:265`, `:340-354`, `:434`); its assertions are kept.
    The same holds for line references in `StrandTests/OneNumberPerVariableTests.swift`. Stage 4 adds
    its own two tests to these files only after this change has merged.
81. No file under `Strand/` or `StrandiOS/` contains `LabBookUnion` or `unionedDeviceIds(`.

Both Python files run in the unfiltered `tools-python` leg and in `Tools/personal/gate.sh`.

### 12.5 Single-id equivalence (stands in for flag-off equivalence)

There is no flag. The equivalent proof: with every row under the active id,

72. `testSingleIdInstallListsExactlyTheRowsThePerIdReadReturns`
73. `testSingleIdInstallProjectionIsUnchangedByTheRepair`
74. The whole stage 1 suite is green with only the edits of §12.6.
75. The gate's stable summary differs from [BASELINE.md](../BASELINE.md) only by the added tests.
79. `testSingleIdInstallCoachRollUpTextIsUnchanged` (in `LabBookRowsTests.swift`): with every row
    under the active id, the Lab Book lines of the Coach roll-up built from `LabBookRows.category`
    equal, byte for byte, the lines built from the per-id read `labMarkers(deviceId:category:)`.
    Stage 2 takes its byte-identity baseline after this test is green on the merged change (§6.3).

### 12.6 Stage 1 tests the Test author rewrites, with the reason in the commit message

| Test | Why |
|---|---|
| `StrandTests/WeighInStoreTests.swift:906` `testDuplicateAcrossIdsCollapsesWithTheActiveCopyWinning` | Its two rows differ in value; they are now both listed. A copy case replaces the collapse assertion |
| `WeighInStoreTests.swift:993` `testDeletingTheActiveCopyOfADuplicateLeavesTheOtherIdsCopy` | Same data; both rows are listed from the start |
| `WeighInStoreTests.swift:1021` `testRowsOutsideTheUnionAreNotListedAndNeverTouched` | Now listed. "Never touched" stays asserted |
| `StrandTests/WeighInCrossIdOccupancyTests.swift:414` | An instant held under an unregistered or other-brand id now blocks |
| `StrandTests/WeighInOccupiedInstantTests.swift:215`, `:335` | Same |
| To re-check, expected unchanged apart from line references: `StrandTests/BodyMeasurementSingleSourceTests.swift:618-655`, `StrandTests/OneNumberPerVariableTests.swift:784-840`, `StrandTests/CutScorecardModelTests.swift:1236`, `WeighInCrossIdOccupancyTests.swift:271` | They use cross-id rows; none was read closely enough here to rule out a hidden-row assertion. The Test author reads each cross-id case and rewrites any that asserts a hidden row |

### 12.7 Parity disposition (R43)

No Kotlin is written, compiled or run for this change. The pull request records this drift:

On Android a strap delete still removes Lab Book readings and an adoption still re-keys them with
`UPDATE OR IGNORE` (`DeviceRegistryDao.kt:110`, `:158`); on iPhone neither happens any more. Android
lists only the rows under `my-whoop` (`LabBookScreen.kt:96`), so a database from the iPhone restored
there shows a subset of what the iPhone lists; that was already so (L5) and the complete iPhone list
widens the visible difference. Android's projection still chooses within one device id, so a cell
repaired on iPhone can be recomputed per id by a later Android write on that day. The stored-data
contracts themselves (schema, backup whitelist, marker catalogue) are not edited on either side.

New public declarations in `Packages/WhoopStore/Sources` fall under the parity ledger's glob
(`Tools/parity_ledger.py:44`). Each carries the sentence "No Kotlin twin, by the owner's decision
(stage 1 ruling R43)." Whether the ledger accepts that wording was not run (§16). The gate script's
Android rows are reported as waived, never as passed.

### 12.8 Fault injection

Each line is one deliberate break; a named test must fail. A break nothing catches is a finding.

| # | Break | Caught by |
|---|---|---|
| F1 | Put `labMarker` back into the delete loop | 16, 56, 57 |
| F2 | Iterate `deviceScopedTables` in adoption | 22, 23, 59, 70 |
| F3 | Empty `ownerEnteredTables` | 21, 16 |
| F4 | Add a strap table to `ownerEnteredTables` | 17, 24 |
| F5 | `merged` collapses on identity alone | 5, 6, 15 |
| F6 | `isCopy` compares `day` | 7 |
| F7 | `isCopy` ignores `note` | 6 |
| F8 | `merged` prefers the non-active row | 2 |
| F9 | `merged` drops the final sort | 1, 11 |
| F10 | `allLabMarkers` filters to registered ids | 27, 54 |
| F11 | `LabBookView.load` reads `repo.deviceId` again | 52, 68 |
| F12 | Coach roll-up reads `repo.deviceId` again | 53, 68 |
| F13 | Projection keeps its device-id filter | 39, 41, 42 |
| F14 | Projection tie-break by smallest id | 40 |
| F15 | Repair deletes cells with no expected value | 47 |
| F16 | Repair overwrites a cell whose value no row holds | 46 |
| F17 | Repair touches other sources' series | 50 |
| F18 | Repair not run at open | 66 |
| F19 | `deleteLabMarkerAndCopies` deletes by identity | 36 |
| F20 | `deleteLabMarkerAndCopies` deletes the one row only | 35, 61 |
| F21 | `upsertOwnerLabMarkers` always inserts | 31, 33, 60 |
| F22 | `upsertOwnerLabMarkers` rewrites `deviceId` to the incoming one | 31 |
| F23 | Weigh-in occupancy checks registered ids only | 64 |
| F24 | Value edit skips the copies | 62 |
| F25 | Date edit deletes only the edited row | 63 |
| F26 | Remove the sentence from a dialog | The i18n audit does not catch this; a `StrandTests` source assertion on `DevicesView.swift` is added as test 76, `testBothStrapDialogsStateThatLabBookReadingsAreKept` |
| F27 | `deleteLabMarkerAndCopies` projects before the delete instead of after | 35, 80 |
| F28 | Re-add a registry-built id list beside `LabBookRows` | 81, 54 |
| F29 | Coach roll-up drops or reorders a line for a single-id install | 79 |

### 12.9 Privacy scan

Nothing new leaves the app. The scan confirms it:

77. `testRepairLogLineCarriesCountsOnly` (no marker key, value, unit, note or device id in the line).
78. The committed test files, the fixture and this document are searched for any marker value outside
    the §13 set by the contract reviewer.

### 12.10 Real-data rehearsal, before any device install

Run by the Verifier on the Mac, with no simulator and no device. Nothing it produces is committed.

1. The owner makes a fresh backup from the phone (Settings, backup) and places the `.noopbak` under
   `PersonalData/superapp/rehearsal/` in the main checkout. The folder is ignored by Git.
2. Unzip it there and copy the SQLite file to `before.sqlite` and `work.sqlite`. Every later step
   opens `work.sqlite` only.
3. `NOOP_REHEARSAL_DB=<absolute path to work.sqlite> swift test --filter LabBookOwnershipRehearsalTests`
   in `Packages/WhoopStore`. The test is skipped when the variable is unset. It opens the copy,
   and prints counts only: rows, distinct device ids, ids with no registry row, identities with
   copies, identities with conflicts, qualitative rows, and the four repair counts. Then it asserts:
   - every `labMarker` row is byte-identical before and after the repair;
   - a second repair reports `inserted == 0` and `updated == 0`;
   - `merged` over all rows hides only copies: the listed count plus the surplus copies equals the
     row count;
   - for each registered id in turn, on a fresh copy, `deleteAllData` leaves the `labMarker` row
     count and content unchanged.
4. Compare `labMarker` in `before.sqlite` and `work.sqlite` with `sqlite3` and a row dump piped to
   `shasum`; only the hashes are recorded.
5. Report to the owner in words: how many ids, whether any are unregistered, whether any unbacked
   cells exist (the evidence for §15 Q3), whether any conflicts exist. No value, marker name or date
   is written anywhere outside `PersonalData/`.
6. Optional, if the owner wants to see it: restore the same backup into a simulator following the
   stage 0 rehearsal procedure and look at Lab Book. No screenshot is committed.

### 12.11 Simulator verification (G6)

Synthetic data only. Run by the Verifier in the serialised step, not by the specification's author.

The debug block of `StrandiOS/App/StrandiOSApp.swift` resolves a demo name through one ordered list
of demo providers, landed once by the orchestrator's shared scaffolding commit before any stage
(cross-check X6). This change adds:

- one new file, `StrandiOS/Scorecard/LabBookOwnershipDemo.swift`, wholly inside `#if DEBUG`:

  ```swift
  enum LabBookOwnershipDemo {
      /// The view for a demo name this provider owns, else nil. Same shape as
      /// `ScorecardDemo.screen(named:)` (`StrandiOS/Scorecard/ScorecardDemo.swift:33`).
      static func screen(named name: String) -> AnyView?
  }
  ```

- one element for it in the registry list, placed straight after the scorecard provider (this change
  is first in integration order). The orchestrator applies that one-line edit.

`ScorecardDemo.swift` is not edited. The provider answers exactly two names, both carrying the
reserved prefix `labbook-ownership`, and returns nil for every other name:

| Name | Shows |
|---|---|
| `labbook-ownership` | The Lab Book screen on an in-memory store seeded with the ten rows of §13 and its registry, N active |
| `labbook-ownership-forgot` | The same after `forget` on the fixture's archived strap B |

Each state runs on its own in-memory store and its own defaults suite; nothing is read from or
written to the app's store or settings. Capture default and largest text size; exercise add, delete
of a collapsed reading, and CSV re-import by hand.

## 13. Fixture

"Fixture Person": the one fictional person of stage 1 §13, used by every stage. Everything here is
invented. The weekly weights and the waist are stage 1's (§13.3: Wednesdays from 2031-01-08,
`takenAt` at 07:00 UTC, 100.0, 99.2, 98.4 and 97.6 kg; waist 100.0 cm in week 1). The rows spread
them over several device ids. Three rows exist only for this change and are marked "constructed":
F3 and F9 (two further weight readings on 2031-01-22) and the `ldl` pair with the text row.

Seeded as given, the latest reading of each day is stage 1's value for that day, so a demo or
simulator seed that combines this fixture with stage 1's shows one weight series.

Device ids:

| Label | Id | Registry |
|---|---|---|
| A | `my-whoop` | Registered, paired, brand WHOOP |
| B | `whoop-FIXTURE-OLD` | Registered, archived, brand WHOOP |
| C | `whoop-FIXTURE-GONE` | No registry row |
| D | `oura-FIXTURE-RING` | Registered, paired, brand Oura |
| N | `whoop-FIXTURE-NEW` | Registered, active, brand WHOOP |

Instants (epoch seconds, UTC): `T1 = 1925622000` (day `2031-01-08`, 07:00),
`T2 = 1926226800` (`2031-01-15`, 07:00), `T3a = 1926828000` (`2031-01-22`, 06:00, one hour before
T3), `T3 = 1926831600` (`2031-01-22`, 07:00), `T4 = 1927436400` (`2031-01-29`, 07:00). Each row's
`day` is the day shown for its instant.

| Row | `id` | Device | Marker | Category | Instant | Value | Unit | Source | Note |
|---|---|---|---|---|---|---|---|---|---|
| F1 | `weight-1925622000-F0000001` | A | `weight` | `bodyMeasurement` | T1 | 100.0 | kg | `manual` | — |
| F2 | `weight-1926226800-F0000002` | B | `weight` | `bodyMeasurement` | T2 | 99.2 | kg | `manual` | — |
| F3 | `weight-1926831600-F0000003` | C | `weight` | `bodyMeasurement` | T3 | 98.0 | kg | `manual` | — (constructed) |
| F4 | `weight-1927436400-F0000004` | N | `weight` | `bodyMeasurement` | T4 | 97.6 | kg | `manual` | — |
| F5 | `waist-1925622000-F0000005` | D | `waist` | `bodyMeasurement` | T1 | 100.0 | cm | `manual` | — |
| F6 | `ldl-1926226800-F0000006` | B | `ldl` | `bloodPanel` | T2 | 3.0 | mmol/L | `lab-csv` | "fixture panel" (constructed) |
| F7 | `ldl-1926226800-F0000007` | N | `ldl` | `bloodPanel` | T2 | 3.0 | mmol/L | `lab-csv` | "fixture panel" (constructed) |
| F8 | `weight-1926831600-F0000008` | N | `weight` | `bodyMeasurement` | T3 | 98.4 | kg | `manual` | — |
| F9 | `weight-1926828000-F0000009` | B | `weight` | `bodyMeasurement` | T3a | 98.2 | kg | `manual` | — (constructed) |
| F10 | `fixture_note-1926226800-F0000010` | C | `fixture_note` | `other` | T2 | nil, text "clear" | `text` | `manual` | — (constructed) |

`valueText` and `referenceText` are nil except F10's text. The "Note" column is the row's `note`;
"(constructed)" is a remark of this table and is not stored. F7 is a copy of F6. F8 conflicts with
F3: same marker, instant and source, different value.

Expected, with N active:

- `merged` over all ten, in (`takenAt`, `id`) order: F5, F1, F10, F7, F2, F9, F3, F8, F4 (nine
  readings). F7 stands for the pair F6 and F7, because N is active.
- Weight history: F1, F2, F9, F3, F8, F4. The stage 1 implementation lists F1, F2, F9, F8, F4.
- The representative of the `ldl` pair: with N active, F7; with B active, F6; with any other id
  active, F7, because `whoop-FIXTURE-NEW` sorts before `whoop-FIXTURE-OLD`.
- Projection cells under `lab-book`: `weight` `2031-01-08` 100.0; `2031-01-15` 99.2; `2031-01-22`
  98.4 (F3 and F8 share the latest instant and F8 has the greater `id`; F9 is earlier);
  `2031-01-29` 97.6; `waist` `2031-01-08` 100.0; `ldl` `2031-01-15` 3.0. No cell for `fixture_note`.
  Six cells.
- `conflictingKeys`: the one identity (`weight`, T3, `manual`).
- `deleteAllData` on B, then on N, then `remove` of B: all ten rows byte-identical.
- `deleteLabMarkerAndCopies("ldl-1926226800-F0000007")` returns the ids of F6 and F7, deletes both
  and removes the `ldl` cell.
- `deleteLabMarkerAndCopies("weight-1926831600-F0000008")` deletes F8 only; the `2031-01-22` cell
  becomes 98.0 (F3, now alone at the latest instant).
- `deleteLabMarkerAndCopies("weight-1926831600-F0000003")` deletes F3 only; the `2031-01-22` cell
  stays 98.4.

Repair variants, each starting from the ten rows with correctly projected cells:

| Variant | Stored cell before | Expected result |
|---|---|---|
| V1 | `weight` `2031-01-22` absent | `inserted` 1, `unchanged` 5, cell 98.4 |
| V2 | `weight` `2031-01-22` = 98.0 (F3's value, a surviving row) | `updated` 1, `unchanged` 5, cell 98.4 |
| V3 | `weight` `2031-01-22` = 90.0 (no row holds it) | `unbackedKept` 1, `unchanged` 5, cell stays 90.0 |
| V4 | extra cell `weight` `2031-02-05` = 97.5, no rows that day | `unbackedKept` 1, `unchanged` 6, cell stays |
| V5 | no difference | `inserted` 0, `updated` 0, `unchanged` 6, `unbackedKept` 0 |

## 14. Work packages and file ownership

| WP | Role | Files |
|---|---|---|
| LO-1 | Test author | New: `Packages/WhoopStore/Tests/WhoopStoreTests/LabMarkerUnionTests.swift`, `LabMarkerOwnershipStoreTests.swift`, `LabBookProjectionRepairTests.swift`, `LabBookOwnershipRehearsalTests.swift`, `LabBookOwnershipFixture.swift`; `StrandTests/LabBookRowsTests.swift`, `LabBookOwnershipFlowTests.swift`; `Tools/test_lab_book_single_read_path.py`. Edited: `Packages/WhoopStore/Tests/WhoopStoreTests/DeviceRegistryStoreTests.swift` (additions only), the stage 1 tests of §12.6 (`StrandTests/OneNumberPerVariableTests.swift` included), `Tools/test_body_measurement_single_resolver.py` |
| LO-2 | Implementer A (store) | New `Packages/WhoopStore/Sources/WhoopStore/LabMarkerOwnership.swift`. Edited: `DeviceRegistryStore.swift`, `LabMarkerStore.swift` |
| LO-3 | Implementer B (app), after LO-2 merges | New `Strand/Data/LabBookRows.swift`, `StrandiOS/Scorecard/LabBookOwnershipDemo.swift`. Edited: `Strand/Data/BodyMeasurementProvider.swift`, `Strand/Data/WeighInStore.swift`, `Strand/Screens/LabBookView.swift`, `Strand/AI/AICoach.swift`, `Strand/Data/Repository.swift` (the repair call), `Strand/Screens/DevicesView.swift` (the sentence) |
| LO-3h | Orchestrator, one small commit | `StrandiOS/App/StrandiOSApp.swift`: one element in the demo registry list (§12.11) |
| LO-4 | Localiser, last step, after LO-3's English is final | `Strand/Resources/Localizable.xcstrings`, one key |
| LO-5 | Verifier | Gate script, fault injection, rehearsal (§12.10), simulator (§12.11). Evidence files only |
| LO-6 | Reviewers: correctness, contract, **data safety** | None |

Files only this change edits (cross-check shared-file list): `DeviceRegistryStore.swift`,
`Strand/Data/Repository.swift` (the repair call), `Strand/Screens/DevicesView.swift`,
`Strand/Data/WeighInStore.swift` and `Strand/Data/BodyMeasurementProvider.swift`. Stage 4 only calls
the last two, and is written after `unionedDeviceIds` is gone. `DeviceRegistryStore.swift` is
re-checked by hand after any upstream merge: the comment at `:167-173` and the list must keep
`labMarker` out of the strap loops.

Shared files this change edits, and its place in each file's order:

| File | Order | This change's edit |
|---|---|---|
| `Strand/Resources/Localizable.xcstrings` | 1b, 2, 3, 4, 5, 6; one Localiser at a time, never two branches at once | One key (LO-4) |
| `StrandiOS/App/StrandiOSApp.swift` (debug block) | Scaffolding first, then one element per stage in integration order | One registry element (LO-3h) |
| `Strand/AI/AICoach.swift` | 1b (roll-up read), then stage 2 (extraction, byte-identity baseline captured after 1b), then stage 4 (roll-up skip) | The roll-up read at `:1283-1300` only |
| `Packages/WhoopStore/Sources/WhoopStore/LabMarkerStore.swift` | 1b (LO-2), then stage 4's 4-4c | §6.1 and §7.2 |
| `Strand/Screens/LabBookView.swift` | 1b (load, save, CSV import, delete), then stage 4's 4-6 (CSV scope argument), then 4-7 (Entered-as line) | The four call sites of §4.1 |
| `StrandTests/OneNumberPerVariableTests.swift`, `Tools/test_body_measurement_single_resolver.py` | 1b (line references, cross-id cases re-checked), then stage 4 adds its two tests | §12.4 item 71, §12.6 |

Files this change reads and does not edit: `Strand/Screens/MarkerEditorView.swift` (stage 4's 4-7
edits it after this change merges), `StrandiOS/Scorecard/ScorecardDemo.swift`,
`StrandiOS/Scorecard/WeighInHistoryView.swift` (stage 4 only; after this change its list holds rows
under every id).

Shared hotspots it does **not** edit: `Strand/Screens/DashboardCards.swift`,
`Strand/Data/TodayCardReadout.swift`, `Strand/Screens/SettingsView.swift`, the three Today views,
`StrandiOS/Redesign/RedesignHealthView.swift`, `StrandiOS/Redesign/RedesignRoute.swift`,
`StrandiOS/Scorecard/ScorecardView.swift`, `Packages/StrandImport` `MarkerCatalog`, `project.yml`,
`Database.swift`, `BackupSettings.swift`, `BackupSettingsTests.swift`, `design/figma-plugin/`.

Parallel and serial (cross-check build order):

- Now, in this change's own worktree, with no app build: LO-1 (new test files), and LO-2's pure
  part (`LabMarkerUnion`) with its `swift test` in `Packages/WhoopStore`, one package at a time in
  the worktree. New app files (`LabBookRows.swift`, `LabBookOwnershipDemo.swift`) may be written but
  not built. The owner's fresh phone backup for §12.10 is requested now.
- Serialised step 1, alone on the single app build tree (`xcodegen generate`, NOOPiOS build, Strand
  build, `StrandTests`, the gate script): LO-2's store edits, LO-3, the rewritten stage 1 tests of
  §12.6, the rehearsal on the backup copy, then LO-3h and LO-4 last. It goes first because it is a
  data-safety fix and stage 4 is blocked on it.
- After it merges: stage 2's extraction in `AICoach.swift` (baseline captured then), and stage 4
  against `LabBookRows` (§6.3).
- It must not run in parallel with any other change to `WeighInStore.swift`,
  `BodyMeasurementProvider.swift`, `LabMarkerStore.swift` or `AICoach.swift`.
- G1: there is no frame and no design round; this change uses no plugin command and no design
  folder. The sentence of §11 is in force by default (§15 Q5); a different wording from the owner is
  a one-key change before LO-4. Store work does not wait for it.
- G8: the build is installed only after §12.10 has been run on a fresh backup and reported. It is
  the first of the milestone installs (after step 1, with the rehearsal report and a fresh backup).

`project.yml` needs no change; the new files fall under directories it already includes. Run
`xcodegen generate` after adding them.

## 15. Open questions for the owner

Work proceeds on each recommendation. Q1, Q2, Q5, Q7 and Q9 are the cross-check's owner decisions
for this change (11 November 2026): each is **decided by default** on its recommendation, and the
last column says what changes if the owner says otherwise.

| # | Question | Recommendation in force | If the owner says otherwise |
|---|---|---|---|
| Q9 | May the next build stop a strap's "Delete data" and "Forget device" from deleting Lab Book readings, with no migration and no rewrite of stored rows? | **Decided by default: yes.** It needs a fresh backup from the phone first, for the rehearsal of §12.10 | The change is not installed. The read path (`LabBookRows`, the all-id projection) can still merge so stage 4 is not blocked, but `ownerEnteredTables` is left empty, tests 16, 21, 56 and 57 and the dialog sentence are withdrawn, and R42 needs a new ruling |
| Q5 | Wording of the added sentence: "Lab Book readings you entered are kept." | **Decided by default: as written** | Another wording: one key changes before LO-4 and test 76 follows it. No sentence at all: §10.2, §11, LO-4 and test 76 are dropped and the dialogs stay as they are |
| Q7 | Two readings at the same instant with different values, stored under two strap ids, are now both listed (stage 1 showed one). Acceptable? | **Decided by default: yes.** It is what "never hidden" means, and either can be deleted | One of the two would have to be hidden, which R42 forbids; it needs a new ruling naming which row wins. `merged` would then collapse on identity (tests 5, 6, 15 and fault F5 reverse) and `deleteLabMarkerAndCopies` would delete by identity |
| Q1 | The in-app lift log (programmes, sessions, sets) is deleted by a strap delete and hidden when the active strap changes, exactly as Lab Book was. Should it be protected the same way? | **Decided by default: yes, as a follow-up change, lift log first**, reusing `ownerEnteredTables`. Until then the dialogs' new sentence names Lab Book only, which is accurate | No follow-up is planned. Nothing in this change alters |
| Q2 | Manual workouts and sleep marks are written under the active strap id and are deleted with it. Protect them too? | **Decided by default: yes for manual workouts, as a follow-up change after the lift log.** They share a table with strap-recorded workouts, so the remedy is a filter on `source = 'manual'`, not a table exemption, and it needs its own specification | No follow-up is planned. Nothing in this change alters |
| Q3 | If the rehearsal finds projected cells that no reading backs, they are traces of readings an earlier strap delete or adoption removed. Recreate those as Lab Book readings? | No automatic recovery. Keep the cells as they are and report the count. A recovered row would need an invented instant and, for custom markers, an unknown unit. If the count is not zero, the owner is shown the days privately and decides | A recovery step would be its own change with its own specification |
| Q4 | "Delete data" on the legacy `my-whoop` entry also deletes the history imported from the WHOOP export, journal answers included, because the import is stored under that id. Should that entry be protected or the dialog say so? | Out of scope here. Raise it as its own item; until then do not use "Delete data" or "Forget" on that entry | Its own change |
| Q6 | With strap deletes no longer clearing Lab Book, readings can only be deleted one at a time. Add "Delete all readings" to Lab Book? | Not in this change. It is a new destructive control and would need a frame and its own approval | Its own change, with a frame |
| Q8 | New readings are still stored under whichever strap is active. Acceptable now that every id is read? | Yes. Moving to one owner id is option 2 and would need the owner's go-ahead | Option 2 of §8.1, which needs a new specification |

**Needs the owner's go-ahead:** nothing in the recommended design. No migration, Health access,
target, entitlement or network path. Options 2 and 3 (§8.1) would each need it. Installing the build
needs it as always, after the rehearsal and a fresh backup, at the first milestone install.

## 16. Not determined

- **The owner's database.** How many device ids hold Lab Book rows, whether any id is unregistered,
  whether any strap's data was ever deleted, whether any unbacked projected cell exists, and whether
  any copies or conflicts exist. §12.10 answers all five.
- **Which id is active on the phone**, and whether the strap has adopted, or will adopt, a serial id.
  A WHOOP 4.0 adopts after a second sighting of its serial (`BLEManager.swift:5330-5333`) unless its
  id is `my-whoop`.
- **Whether the WHOOP export import writes under `my-whoop` in every path.** The importer takes the
  id as a parameter (`WhoopImporter.swift:14`); its callers were not opened. Q4 rests on the
  repository's own description (`Repository.swift:144-152`).
- **The cross-id tests listed "to re-check" in §12.6** were located, not read line by line.
- **Parity ledger and ratchet.** Whether the R43 sentence is an accepted disposition for new public
  declarations in `Packages/WhoopStore` was not run. The ledger is recorded as stale on this branch
  (CONTEXT §7 item 3).
- **Explore and Compare.** That they reach the projection only through `Repository.series` was
  inferred from the metric catalogue and one call site (`LabBookView.swift:906`); each consumer was
  not opened.
- **Time cost of the repair and of the per-cell projection on a large import.** Not measured. The
  table is hand-entered data and no index covers `(markerKey, day)` without a device id.
- **`LabBookFormat.dayKey` after a zone change** (stage 1 §16) is still open and affects the `day` a
  Lab Book draft is stored under. `isCopy` ignores `day` for that reason.
- **Upstream.** Whether upstream intends `labMarker` to stay in the strap delete was not checked. A
  later merge of `DeviceRegistryStore.swift` needs a manual look.
- **Android.** Nothing on the Kotlin side was compiled, run or changed.
- **Whether a stage 0 rehearsal procedure document exists.** The roadmap lists it as 0B-7; no file
  for it was found under `docs/personal/superapp/` or `Tools/personal/`. §12.10 stands on its own.

## 17. Reconciliation (11 November 2026)

Applied from the cross-stage check. One line per conflict that names this change.

| Id | What changed in this file |
|---|---|
| X1 | New §6.3: `LabBookRows` is the only Lab Book union; stage 4 creates no `LabBookUnion`, reads through `LabBookRows.category` / `.marker`, checks occupancy across every id through `LabBookRows.stored`, and removes copies as `deleteLabMarkerAndCopies` does. §5 names `LabBookUnion` as not created; test 81 and fault F28 guard it; §14 places this change first |
| X2 | §6.1 adds the module-internal in-transaction steps `LabBookDayCell`, `ownerUpsert`, `deleteWithCopies` and the now-internal all-id `reprojectCells`, so stage 4's `replaceLabMarkers` (4-4c, after LO-2) composes them instead of a per-id statement; test 80 and fault F27 added; `LabMarkerStore.swift` order is LO-2 then 4-4c |
| X6 | §12.11 and §14: the two demo names move out of `ScorecardDemo.screen(named:)` into a new provider file `LabBookOwnershipDemo.swift` plus one element in the orchestrator's demo registry (LO-3h); `ScorecardDemo.swift` is no longer edited; prefix `labbook-ownership` |
| X17 | §6.3 and §14: `AICoach.swift` order is this change, then stage 2's extraction with its baseline captured afterwards, then stage 4's skip; test 79 and fault F29 pin the single-id roll-up text |
| X20 (fixture, by instruction) | §13 re-based onto stage 1's Fixture Person: weekly weights 100.0, 99.2, 98.4, 97.6 kg at 07:00 UTC; the constructed second reading of 2031-01-22 moved an hour earlier (T3a) so each day's latest reading is stage 1's value; projection cells and repair variants recomputed |

Shared-file order adopted in §14: `Localizable.xcstrings` (1b first), `LabBookView.swift` (1b, 4-6,
4-7), `MarkerEditorView.swift` (read only here), `WeighInStore.swift` and
`BodyMeasurementProvider.swift` (1b the only editor), `OneNumberPerVariableTests.swift` and
`Tools/test_body_measurement_single_resolver.py` (1b, then stage 4), `DeviceRegistryStore.swift`,
`Repository.swift` and `DevicesView.swift` (1b only).

Owner decisions adopted as the design in force (§15): Q9 (strap deletes stop removing Lab Book
readings, no migration, fresh backup first), Q5 (the sentence), Q7 (conflicting readings both
listed), Q1 and Q2 (lift log, then manual workouts, as follow-up changes).

Android (R43): no instruction to write or run Kotlin remains; §12.7 states the drift in one
paragraph.

Privacy: the header sentence that described opening a private file is removed. Recorded as a process
breach: an ignored private file was opened while this specification was first drafted; nothing from
it is in this document and no private file is an input to it. One phrase in §4.4 that referred to
the owner's circumstances was replaced by a neutral one.

Shared scaffolding this change expects from the orchestrator's step 0:

| Scaffolding | Use here |
|---|---|
| The demo registry line in `StrandiOS/App/StrandiOSApp.swift` (an ordered list of demo providers, each answering `screen(named:) -> AnyView?`) | **Required.** §12.11 adds one provider file and one list element. If the registry's element shape differs from `screen(named:)`, `LabBookOwnershipDemo` conforms to the shape landed |
| Plugin commands `importS2` to `importS6` and the stage-named design folders | Not used. This change has no frame and no design round |
| `ObservableDefaultsFlag` | Not used. The change ships with no flag (§8.5) |
| `CanonicalDay` | Not used. No day key is computed here; a row's `day` is stored by its writer, and `isCopy` ignores it (§7.1) |
| `ChargeTypicalBand` | Not used |
| The fork-only backup keys comment above the Swift whitelist | Not used. No backup key is added (§9); this change has no line in it |
