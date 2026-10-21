# Personal iOS fork: integration audit

Audited baseline: `ryanbr/noop@8e4b0c16e7640607600fa6bde5424095eba6034e`, 21 October 2026.
This is a source audit, not an iOS build or a physical-device test. Line references describe that
baseline. No private health data, API credentials, or WHOOP export were supplied or accessed.

## Capability matrix

“Implemented, unverified” means a real code path exists; it does not establish that iOS permissions,
Apple signing, background execution, or the wearer's strap produce the expected result.

| Capability | Baseline status | Evidence and limitation |
|---|---|---|
| Explicit Apple Health permissions | Implemented, unverified | `StrandiOS/Health/HealthKitBridge.swift:94` defines read/write scopes; `:217` requests both. Each writer checks its own share authorization. HealthKit intentionally hides read permission: successful authorization is not proof that a read scope was granted. |
| HR, RHR, respiratory rate writes | Implemented, unverified | `HealthKitBridge.swift:1015`, `:1037`, `:1138`. HR/RHR use count/minute, respiration count/minute; the HR series is one-minute averages, not a beat-by-beat stream. |
| HRV SDNN export | Implemented, unverified | `HealthKitBridge.swift:1018` writes only `avgSdnn` in milliseconds, and retracts older app-authored daily HRV when genuine SDNN is absent. There is no RMSSD fallback. `Strand/Health/HealthExportMerge.swift` preserves computed SDNN when a WHOOP CSV covers the same day. |
| RMSSD export as an independent Health metric | Unsupported | HealthKit has no corresponding RMSSD quantity type. RMSSD must remain a labelled local metric; it must not be relabelled SDNN. |
| SpO₂ export | Implemented, unverified | `HealthKitBridge.swift:1034` converts a stored percentage to the fraction expected by `HKUnit.percent()` (`spo2 / 100`). Availability and reliability of strap-derived percentages remain separate questions. |
| Wrist/skin temperature export | Unsupported | `HealthKitBridge.swift:145` excludes Apple's read-only wrist-temperature share type. No body-temperature fallback is used. A skin measurement must not be exported as core/body temperature. |
| WHOOP step export to Health | **Unsupported in baseline bridge** | `.stepCount` appears in read scopes (`HealthKitBridge.swift:124`) and import queries (`:541`, `:1458`), but not in either write scope or any writer. Successful Health sync therefore cannot establish that strap-derived steps reached Health. |
| Sleep stages and wake-time vital timestamps | Implemented, unverified | `HealthKitBridge.swift:844` unions computed/imported sleeps, withholds apparently open nights, and uses sessions for wake-time stamps (`writeVitals`, `:1011`). `writeSleep` (`:1077`) writes segments. Exporting a stage does not validate the stage's physiological accuracy. |
| Export after historical offload | Implemented, unverified | `StrandiOS/App/StrandiOSApp.swift:175` installs `model.healthWriteBack`; `HealthKitBridge.swift:782` is the write-only pass. It serializes with normal sync and coalesces concurrent arrivals, instead of writing only before offload on foreground entry. |
| Background Health writeback | Implemented, unverified | `StrandiOSApp.swift:161` registers an independent background scheduler. iOS schedules the actual wake; there is no continuous/instant update guarantee. Locked-phone testing remains required. |
| Health read/write loop protection | Implemented, unverified | `HealthKitBridge.swift:1431` excludes `HKSource.default()` from reads; `writeWorkouts` (`:1274`) excludes `apple-health` workouts. This prevents this app from simply rereading its own exports. It does not prove deduplication across two separately signed copies of NOOP. |
| Native widget extension | Implemented, unverified | `project.yml:375` includes WidgetKit extension, `:397` injects the same App Group identifier, and `:404` grants it. Keep the extension in the build and sign host and extension under the same paid team/group. |
| Recovery/strain/sleep-score widgets | Implemented, unverified | `StrandiOSWidgets/NOOPWidget.swift:31` renders Charge/Effort/Rest for Home and Lock Screen families; `StrandiOSShared/WidgetSnapshot.swift:7` stores those fields. Scores are NOOP's independent calculations, not recovered proprietary WHOOP scores. |
| Steps/goal widget; last-night duration widget | **Unsupported in baseline** | The baseline shared snapshot has no steps, goal, or sleep-duration field (`WidgetSnapshot.swift:6–62`). Rest is a sleep-performance score, not a last-night duration. |
| Visible widget freshness | **Incomplete in baseline** | Snapshot has `updated` (`WidgetSnapshot.swift:11`), but the main `NOOPWidget` never displays it. The provider asks for a new timeline after approximately 15 minutes (`NOOPWidget.swift:25`); this is a request to iOS, not evidence that sensor data advanced. |
| Hevy manual CSV import | Implemented, unverified with real export | `Strand/Screens/DataSourcesView.swift:437` parses a selected file and stores a Strength workout under `lifting`. No API key/account is needed for NOOP's side of this flow. |
| Hevy automatic API synchronization | **Unsupported** | `Packages/StrandImport/Sources/StrandImport/HevyAPI.swift:10` explicitly provides parsing only. There is no Hevy API transport/client, Keychain credential store, scheduler, or user connect flow. |
| Hevy sets/reps/weights | Aggregate import, not a lossless set log | `LiftingImporter.swift:23` produces session totals; `DataSourcesView.swift:464` persists one `WorkoutRow` with the volume note. Preserve the CSV to recover individual sets later. No measured muscular strain is manufactured. |
| WHOOP archive import | Implemented, unverified with user's export | `WhoopExportImporter.swift:209` opens ZIP in read mode; folder CSVs are read. `Strand/Data/WhoopImporter.swift:23` stores imported vendor metrics separately from the computed `-noop` namespace. The original archive remains external and unchanged. |
| Local recoverable backup | Implemented, unverified on iPhone | `Strand/Data/DataBackup.swift:82` checkpoints WAL, `:262` writes standard ZIP database/settings/provenance, and `:407` implements restore validation/rollback. `BackupSync.swift` supports a user-selected folder with retention. A full round trip on a spare test installation is still required. |

## Health export correctness and remaining risks

The code already addresses the cited RMSSD/SDNN and pre-offload export bugs. A device test must
still inspect values, types, units, dates, sources, and repeat-sync counts; documentation or a
merged fix is not runtime proof.

- **Deduplication is implemented through deletion and replacement.** Vital keys use metric/day;
  sleep keys and workouts use natural identifiers; predicates additionally scope to this app's
  Health source. HR uses a range rewrite. A one-time migration (`HealthKitBridge.swift:896`) also
  removes this app's old records in the recent write window before replacing them. These paths do
  not target another app's data. They nevertheless delete Health records. Keep all write permissions
  off during the collection baseline, and obtain approval for enabling a writeback workflow that
  reconciles its own Health records. Do not run a cleanup migration or delete existing Health data
  as part of setup.
- **Delete errors are swallowed in several writers.** For example, `:1055`, `:1120`, `:1154`, and
  `:1300` use `try?`. If a deletion fails but saving succeeds, duplicate records can remain while the
  pass reports success. This is a concrete deduplication/error-reporting gap to fix and test.
- **Recent-history limits matter.** Normal writeback covers 14 days. HR advances a cursor with a
  48-hour rewrite overlap (`:1133`). Data arriving farther behind that cursor is not automatically
  reconciled. Do not promise complete all-time Health backfill.
- **Multiple apps remain multiple Health sources.** A separate personal bundle identity is useful for
  safe side-by-side installation, but its `HKSource.default()` cannot exclude the stock app's writes.
  Leave Health writes enabled in only one app; do not merge or sum the two histories.
- **Temperature read-scope drift exists.** `.bodyTemperature` is requested in the baseline read list,
  but no matching aggregate is performed in `sync`. It is not evidence that WHOOP skin temperature
  has been imported or exported.
- **No step writer exists.** A new implementation should publish only strap-derived interval counts,
  with deterministic identifiers and explicit source attribution. Never export a merged total that
  contains imported iPhone/Apple Health steps back into Health; it creates a loop/double counting.
  Do not present a daily rescaled counter as one physically measured sample at midnight.

## WHOOP scores and source attribution

The importer keeps WHOOP recovery (`WhoopImporter.swift:34`) and rescales WHOOP Day Strain from
0–21 to NOOP's 0–100 display axis (`:36`; inverse defined in `WhoopExportImporter.swift:42`). The
underlying importer does not overwrite the user's ZIP. Store namespaces remain separate: imported
`my-whoop`/registered strap identifiers and locally computed `-noop` siblings. Source-aware vital
rows label those separately (`Repository.swift:1149`).

The dashboard merges sources with precedence, so an imported vendor value can be displayed on a day
that also has a local score. The custom interface must keep an explicit score-origin label on
recovery, strain, and sleep; a shared numerical display scale is not a claim that the algorithms
match. Retain the original archive and its unscaled vendor values as the historical reference.

## Hevy recommendation

Use the existing CSV import as the dependable first integration boundary: Hevy export → Files →
NOOP Data Sources → Lifting log. The importer computes transparent volume load (working-set
weight × reps), excludes warm-up volume, and never writes that total as cardiovascular Effort
(`DataSourcesView.swift:437–476`). Apple Health workouts cannot supply a lossless set/repetition log.

The JSON parser has models for API pages, templates, body measurements, user info, updates, and
removed workouts. Its own comment (`HevyAPI.swift:110`) identifies a missing prerequisite for
incremental synchronization: the store does not retain Hevy's workout identifier. A changed start
time would create a second session, and a deletion cannot be reconciled by an identifier that was
never persisted. A future API integration needs retained source IDs, pagination, update/delete
semantics, error handling, and Keychain storage before a “sync” switch is honest.

Official account requirements could not be checked on this machine. On 21 October 2026, read-only
requests to `https://api.hevyapp.com/docs/` and
`https://www.hevyapp.com/features/hevy-api/` both returned proxy tunnel `403 Forbidden` before
reaching the site. Do not infer free/Pro access or request a key from that result. Verify the current
requirement with Hevy's official developer documentation before offering API connection; retain CSV
as the path that does not require this app to make a hosted API dependency.

## Backup and raw-data boundaries

A `.noopbak` is a standard **unencrypted ZIP**, not encrypted storage. It contains sensitive health
history. Keep it in an owner-controlled location; do not attach it to issues or commit it. Its
manifest records build/schema/export provenance, not a cryptographic authenticity guarantee.
The backup code checks database integrity before writing and reads the result back; restore checks
format, origin, integrity, size, and attempts rollback. Mac/iOS backups are not interchangeable with
Android Room database backups; CSV is the supported cross-platform boundary.

Decoded HR/R-R and other streams are stored independently of the raw outbox. Raw packet retention
is bounded to approximately 50 MiB (`Strand/Collect/PrunePolicy.swift:8`). `RawOutbox.swift:175`
describes why oldest packets can be evicted. Additional waveform/aux blobs have newest-row caps
(`WhoopStore/StreamStore.swift:66`, `:113`). A later algorithm can rerun from retained inputs, but
this is not an indefinite archive of every original radio packet. Export a full backup before
algorithm experiments; retain the user's WHOOP ZIP unchanged. Standard CSV export alone does not
preserve every raw sensor stream.

## Next checks on the paid-team iPhone build

1. Collect and back up band-only data with all Health writes disabled.
2. Verify matching App Group entitlements in the signed app and widget; add both Home and Lock Screen
   widgets, lock the phone, reconnect, sync, reopen, and compare values and timestamps. Record iOS
   refresh delays rather than declaring the widget continuously live.
3. After explicit approval for app-authored reconciliation, grant selected Health write types. Sync
   once, record per-type record counts, sync unchanged data again, and confirm no count growth.
   Repeat after a new offload and an edited local sleep/workout. Inspect source app, units and times.
4. Check Health HRV records contain genuine SDNN or no new record; never accept RMSSD under that type.
   Inspect a temperature record only if a supported type exists. The baseline should write none.
5. Import a copied Hevy CSV twice, check stable workout counts, known session dates, working-set volume
   and warm-up exclusion. Confirm no invented HR strain or automatic-sync claim.
6. Import a copied WHOOP ZIP, confirm the original's checksum is unchanged, and inspect vendor versus
   local score labels. Test backup restore only in a disposable separately identified installation,
   with approval before replacing its database.
