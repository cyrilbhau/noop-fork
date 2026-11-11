# Stage 4 specification — body record

Gate G0 for stage 4 of the health super-app workstream. Read [CONTEXT.md](../CONTEXT.md),
[ROADMAP.md](../ROADMAP.md) (stage 4), [QUALITY-GATES.md](../QUALITY-GATES.md) and the stage 1
specification ([stage-1.md](stage-1.md), especially §8, §9, §14 and rulings R25 to R43) first.

Verified against the source at commit `0b89b814` (branch `personal/superapp-4-body-record-spec`, cut
from the stage 1 branch `personal/superapp-1-screens`). Every `path:line` below is as of that commit.
Paths are relative to the repository root. Nothing was built or run for this document; it is a
reading of the code.

This file contains no personal measurement, target, date, medication or injury detail. Every number
in an example belongs to the synthetic "Fixture Person" of §13. The private profile was read only to
check that the list of measures in §5.2 and the benchmark kinds in §5.3 can express what its scan
layout and checkpoints name. No value, date or phrase from it appears here.

Stage 4 has three parts. **4A** (scans and benchmarks) and **4B** (laboratory unit entry) are
specified in full. **4C** (photo timeline) is an outline only and is out of scope until the owner
asks (§17).

## 1. Goal and scope

**Goal.** Body-composition scans, blood panels and fixed performance benchmarks become structured,
comparable entries that the owner types in as printed, so the comparison is ready on the day of the
next scan.

**In scope, 4A**

- A second catalogue list, `MarkerCatalog.bodyRecord`, holding the scan and benchmark markers.
- A scan as one dated entry made of several Lab Book rows, entered in one sheet in the order a
  report prints them, saved and edited in one database transaction.
- A scan's total mass stored as an ordinary `weight` reading and its body-fat percentage as an
  ordinary `body_fat` reading, so neither variable gains a second number (ruling R41).
- Derived figures computed by one tested function from stored entries and never stored.
- A scan-to-scan comparison, a benchmark list with entry and history, and one "Body record" screen
  that hosts them, behind the default-off flag `noop.bodyRecordEnabled`.
- A markers CSV that names the new markers imports under their catalogue keys while that flag is on.

**In scope, 4B**

- Entry of every catalogue blood marker in the unit a laboratory report prints, with the conversion
  shown before saving and the typed value kept beside the stored one, behind the default-off flag
  `noop.labReportUnitsEnabled`.
- "Save and add another" in the Lab Book editor, so a panel is typed in one sitting.

**Out of scope**

- The photo timeline (4C, §17).
- Any verdict, band, threshold, target or colour that judges a scan, a benchmark or a blood value.
  The catalogue's rule stands: no reference ranges, `higherIsBetter` is nil for every entry
  (`Packages/StrandImport/Sources/StrandImport/MarkerCatalog.swift:11-18`).
- Feeding the laboratory's resting-metabolic-rate estimate into the app's calorie model. It is shown
  only inside its scan, labelled as the laboratory's estimate.
- A Today card, a widget, a notification, a reminder. Stage 4 adds none of them.
- Charts. Stage 4 draws none; Lab Book already draws a sparkline per marker.
- Reading a report from a PDF or a photograph. Entry is by hand or by markers CSV.
- Any change to the Apple Health read set, any network path, any new build target, any migration,
  any entitlement. None is needed (§16).
- Kotlin. By ruling R43 no Kotlin twin is written. §12.7 records the disposition and the exact drift.
- A height from a scan report. Height has one home, `profile.heightCm`
  (`Strand/Data/Profile.swift:24`), and a scan entry does not ask for it.
- The "Lab Book ownership" change of ruling R42. Stage 4 depends on it for device acceptance (§15,
  B1) and does not contain it.

## 2. Re-check of "what exists"

| # | Claim in the planning documents | Status | Evidence |
|---|---|---|---|
| 1 | `labMarker` holds timestamped readings with columns `id`, `deviceId`, `markerKey`, `category`, `day`, `takenAt`, `value`, `valueText`, `unit`, `source`, `note`, `referenceText`; `category` and `markerKey` are text | Confirmed. `value` is nullable and `valueText` exists for qualitative rows. Natural key `(deviceId, markerKey, takenAt, source)` is a unique index | `Packages/WhoopStore/Sources/WhoopStore/Database.swift:330-356` |
| 2 | The newest migration is `v47-rr-whoop5-fill` | Confirmed | `Database.swift:1103` |
| 3 | The catalogue has no scan keys and no benchmarks | Confirmed. 30 entries: 23 `bloodPanel`, 3 `bloodPressure`, 4 `bodyMeasurement` (`weight` kg, `body_fat` %, `waist` cm, `height` cm, one decimal each). No entry uses `imaging`, `appointmentNote` or `other` | `MarkerCatalog.swift:73-115`; categories `Packages/StrandImport/Sources/StrandImport/LabMarker.swift:26-33` |
| 4 | Lab Book has an editor with a unit switcher for dual-unit markers | Confirmed for exactly five keys: `total_cholesterol`, `ldl`, `hdl`, `triglycerides`, `fasting_glucose`, each with one extra option, `mg/dL`. Every other marker has a single unit | `Strand/Screens/MarkerEditorView.swift:482-488`, `:497-500`, `:503-512` |
| 5 | "Whether the HbA1c editor converts between percent and mmol/mol was not verified" (CONTEXT §4) | **Verified: it does not.** `hba1c` is canonical `mmol/mol`, zero decimals, and is absent from the conversion table, so the editor offers one unit and stores the typed number as mmol/mol | `MarkerCatalog.swift:81`; `MarkerEditorView.swift:482-488`, `:419-422` |
| 6 | The store can add and delete a reading and cannot change its instant | Confirmed. There is also no call that writes or deletes several rows in one transaction with a delete among them: `upsertLabMarkers` is one transaction of upserts, `deleteLabMarker` is one row | `Packages/WhoopStore/Sources/WhoopStore/LabMarkerStore.swift:112-145`, `:191-202`; `Packages/WhoopStore/Sources/WhoopStore/WhoopStore.swift:171-173` |
| 7 | Every write projects a daily series under `lab-book` | Confirmed. Latest numeric reading per `(markerKey, day)`; a row with a nil `value` projects nothing | `LabMarkerStore.swift:217-241` |
| 8 | A markers CSV import exists with an alias table | Confirmed. Units are stored verbatim and never converted. A name that matches nothing becomes `custom_<slug>`. The WHOOP biomarker export parser shares the same name resolution | `Packages/StrandImport/Sources/StrandImport/LabMarkerCsvImport.swift:19-21`, `:267-278`, `:282-319`, `:356-375`; `Packages/StrandImport/Sources/StrandImport/WhoopBiomarkerExportParser.swift:110-130` |
| 9 | A Kotlin twin of the catalogue and of the CSV alias table exists | Confirmed, same 30 entries and the same extras | `android/app/src/main/java/com/noop/analytics/MarkerCatalog.kt:64-106`; `android/app/src/main/java/com/noop/ingest/LabMarkerCsvImport.kt:383-417` |
| 10 | Lab Book draws marker cards with a sparkline | Confirmed. One card per marker key, grouped by category in a fixed order; a sparkline when the marker has more than one numeric reading; a detail sheet with trend, comparison with a wearable signal and a history list with delete | `Strand/Screens/LabBookView.swift:343-414`, `:604-897` |
| 11 | Lab Book reads rows of the active strap id only | Confirmed, unchanged on this branch. The union across strap ids of ruling R25 exists only for `weight` and `waist` | `LabBookView.swift:469-479`; `Strand/Data/BodyMeasurementProvider.swift:225-250` |
| 12 | Stage 1's resolver admits any Lab Book `weight` row whatever its `source`, in kg, lb or lbs | Confirmed | `Strand/Data/BodyMeasurementResolver.swift:116-126`, `:150-161` |
| 13 | A strap's "Delete data" clears `labMarker` | Confirmed, still true on this branch: ruling R42's change is not built yet | `Packages/WhoopStore/Sources/WhoopStore/DeviceRegistryStore.swift:162-173` |
| 14 | The in-app Coach context includes a Lab Book roll-up | Confirmed. It is opt-in, and it prints the latest reading of the first eight markers in an order that depends on dictionary iteration within each category | `Strand/AI/AICoach.swift:293`, `:1283-1302` |
| 15 | The design pipeline exists | Confirmed: `design/round6-scorecard/`, `design/tools/serve.py`, and the plugin's per-round commands `import` and `import6` | `design/figma-plugin/manifest.json` (menu); `design/figma-plugin/code.js:52-57` |
| 16 | The debug demo harness and the local gate script exist | Confirmed. Unknown demo names fall through to `ScorecardDemo.screen(named:)`. The gate picks up every `Tools/test_*.py` | `StrandiOS/App/StrandiOSApp.swift:621-623`; `StrandiOS/Scorecard/ScorecardDemo.swift:33`; `Tools/personal/gate.sh:385` |

## 3. Corrections to the planning documents

| # | Document says | The code says | Consequence for this stage |
|---|---|---|---|
| D1 | ROADMAP 4A: "New catalogue entries for body-composition scans: total, fat and lean mass …" | Total mass is a body weight and the catalogue already has `weight`; a scan's body-fat percentage is the existing `body_fat` (`MarkerCatalog.swift:111-112`). A new `scan_total_mass` key would be a second store for the weight the resolver already serves | Total mass and body-fat percentage get **no** new entry. They are written under the existing keys with the scan's source (§8) |
| D2 | ROADMAP 4A: "The catalogue is a parity contract: the Swift file and `MarkerCatalog.kt` change together, and the CSV import alias tables on both platforms stay aligned"; test plan: "Catalogue parity … by a generated oracle" and "round-trips on both platforms" | Superseded by ruling R43 (stage 1 specification §18) | No Kotlin edit. `MarkerCatalog.builtIn` and the built-in alias table stay byte-identical to their Kotlin twins; the additions live in a separate list and a separate scope, so the drift is exactly "one list and one scope the Kotlin side lacks" (§12.7) |
| D3 | ROADMAP 4A: "No migration: `labMarker.category` and `markerKey` are text" | True, but a row whose category is outside the enum is never listed: both platforms load Lab Book category by category over the enum's cases (`LabBookView.swift:473-476`; `android/app/src/main/java/com/noop/ui/LabBookScreen.kt:120-123`) | No new category. Scan markers use the existing `imaging`; benchmarks use the existing `other`. An older build and Android both keep listing every row |
| D4 | CONTEXT §4: Lab Book has "an editor with a unit switcher for dual-unit markers (lipids and glucose, mmol/L and mg/dL)" and HbA1c is "not verified" | Row 5 of §2: HbA1c has no percent entry. The conversion mechanism is multiplicative only (`MarkerEditorView.swift:503-512`), and percent to mmol/mol is not a multiplication | 4B replaces the factor table with a conversion table that can express an offset (§7.2) |
| D5 | ROADMAP 4B: "No new screen. The deliverable is that the owner can type a report as printed" | The editor saves one marker and dismisses (`MarkerEditorView.swift:449-457`). A panel of ten markers is ten presentations, each starting at the marker search with the date reset to now (`:44`) | "Save and add another" is added to the existing sheet. It keeps the date and returns to the marker list (§10.6) |
| D6 | ROADMAP test plan: "entry in the report's unit stores the canonical unit and displays both" | The typed unit is discarded at save (`MarkerEditorView.swift:420-422`) and `labMarker` has no column for it | The typed value and unit are kept in the row's existing `valueText` column, which "may also annotate a numeric" reading (`LabMarker.swift:49-51`). No migration (§9.3) |
| D7 | ROADMAP 4A treats a scan as catalogue entries plus a view | A scan is many rows that must appear, move and disappear together, and the store has no multi-row transaction that includes a delete (§2 row 6) | One store function is added, `replaceLabMarkers(deleteIds:upsert:)`. It is an API addition in `WhoopStore`, not a migration (§9.2) |
| D8 | ROADMAP 4A lists "bone density scores" among the scan entries without qualification | A whole-body composition report prints them only when the laboratory ran that analysis | They are optional fields like every other field; a scan without them is complete |
| D9 | The Lab Book editor is described as accepting "a number from your own report" | It parses with `Double(_:)` (`MarkerEditorView.swift:445-447`), which accepts `nan` and `inf` and rejects a decimal comma. On a device whose decimal key is a comma, a typed "5,2" leaves Save disabled | 4B parses through one function that accepts the device's decimal separator and rejects everything that is not a finite number (§6.2) |
| D10 | Stage 1 specification §4.1 row for the Coach: "prints the latest Lab Book reading per marker" | The roll-up keeps eight markers chosen by dictionary order (`AICoach.swift:1286-1301`). Twenty new scan markers would displace blood markers at random and would send scan results to the provider | Body-record markers are left out of the roll-up (§4.5). What the coach receives from a scan is a stage 2 decision |
| D11 | ORCHESTRATION file ownership: "Marker catalogue (Swift and Kotlin): Parity agent"; "Backup settings whitelist: Parity agent" | By R43 there is no Parity agent. Stage 4 adds no backup whitelist key at all | The catalogue's sole writer in this stage is Implementer A1 (§14). The whitelist is untouched on both platforms |
| D12 | QUALITY-GATES §G1: design folders sit "beside `design/round1`–`round4`" and the server script "may need to be written again" | `design/round6-scorecard/` and `design/tools/serve.py` exist; the plugin needs one more command per round (`code.js:52-57`) | The design round for this stage is a new folder and a new plugin command (§14, WP 4-2) |
| D13 | Stage 1 specification cites `LabBookView.swift:571` for the day key and `:475-486` for add and delete | The file has moved since: the day key is at `LabBookView.swift:577`, load at `:469-479`, save and delete at `:481-493` | References in this document use the current lines |
| D14 | Stage 1 specification, ruling R42: Lab Book readings survive a strap removal | Not built on this branch (§2 row 13). Until it is, a strap "Delete data" would also delete scans, benchmarks and blood panels stored under that strap id | Stated as blocker B1 for device acceptance in §15. Stage 4 reads across strap ids from its first commit (§9.1) |

## 4. Every reader and writer

"Action" is what stage 4 does to the site.

### 4.1 Body weight (a scan's total mass)

Every site in the stage 1 specification §4.1 stands. The sites stage 4 adds or changes:

| Site | What it does | Action |
|---|---|---|
| `Strand/Data/BodyMeasurementResolver.swift:116-126` | Admits every Lab Book `weight` row as a candidate | **Unchanged.** A scan's total mass is such a row, so it is a candidate from the moment it is saved (§8) |
| `Strand/Data/BodyMeasurementProvider.swift:238-250` | Reads `weight` rows across the strap ids of ruling R25 | Unchanged. It is how a scan's total mass is read back |
| `Strand/Data/WeighInStore.swift:196-200` (`readings(_:)`) | The union read the weigh-in history uses | Reader of the scan's total mass for the scan screens (§9.1). Unchanged |
| `Strand/Data/WeighInStore.swift:35` (`weightRangeKg`) | The accepted weight range | Reused as the range of a scan's total mass. Unchanged |
| New `Strand/Data/BodyRecordStore.swift` | Writes the scan's `weight` row in the same transaction as the scan's other rows, then runs the same finish as a weigh-in (`WeighInStore.swift:204-207`): `repository.refresh()`, then `provider.refresh()`, which mirrors the profile | New writer, inside the funnel's rules (§8.2) |
| `Strand/Data/CutScorecardPresenter.swift:822-890` (`history`) | Lists every weight row; a Lab Book row of any source is editable and deletable | Changed when `noop.bodyRecordEnabled` is on: a row whose source is `body-scan` is captioned as a scan, is not editable or deletable there, and opens its scan (§10.7) |
| `StrandiOS/Scorecard/WeighInHistoryView.swift:152` (`rowView`) | Draws a history row | Changed: a scan row's tap pushes the scan |
| `Strand/Data/CutScorecardInputBuilder.swift` | Builds the weekly series from the resolver's series | Unchanged. A scan's total mass can be the latest reading of its week (§15, O2) |
| `Tools/test_body_measurement_single_resolver.py` (`lab-marker-key` pattern) | Fails on a literal `markerKey: "weight"` outside the allowlist | Unchanged and still binding: `BodyRecordStore` names the key through `BodyMeasurementKind.weight.markerKey` and is not added to the allowlist |

### 4.2 Body-fat percentage

| Site | What it does | Action |
|---|---|---|
| `MarkerCatalog.swift:112` | Catalogue entry `body_fat`, %, one decimal | Unchanged. A scan's body-fat percentage is a row under this key |
| `Strand/Screens/LabBookView.swift:371-414` | The Lab Book "Body fat" card and its history | Unchanged. It lists the scan's reading with the others |
| `Strand/Data/MetricCatalog.swift:180`; `Strand/Screens/AppleHealthView.swift:535`, `:638` | The Apple Health `body_fat` series and its source page | Unchanged. A labelled source page (ruling R41). Not read in this build (`StrandiOS/Health/HealthKitBridge.swift:67`) |
| `Strand/Screens/MetricExplorerView.swift:53`, `:90` | Formatting of the Apple Health series | Unchanged |

No site states a "current body fat". Stage 4 adds none: a body-fat percentage appears only inside a
dated scan, or in Lab Book's list of readings.

### 4.3 Lean mass, resting energy

| Site | What it does | Action |
|---|---|---|
| `Packages/StrandImport/Sources/StrandImport/AppleHealthAggregator.swift:291`; `AppleHealthView.swift:109` | The Apple Health `lean_mass` series (lean body mass, which includes bone) | Unchanged. The scan's lean mass is lean soft tissue without bone, a different measure, under a different key (`scan_lean_mass`). `lean_mass` is deliberately **not** a CSV alias (§7.1) |
| `Packages/StrandAnalytics/Sources/StrandAnalytics/WorkoutDetector.swift:585-669` | The app's own resting-energy model from weight, height, age and sex | Unchanged and not fed by the scan. `scan_rmr_lab_estimate` is displayed only in its scan with the words "laboratory estimate" |

### 4.4 Lab Book rows in general

| Site | What it does | Action |
|---|---|---|
| `LabBookView.swift:469-479`, `:481-493` | Load, save, delete under the active strap id | Unchanged in 4A. Scan rows (category `imaging`) and benchmark rows (category `other`) appear as cards under "Imaging" and "Custom" with their catalogue names |
| `LabBookView.swift:228-311` | CSV import | Changed: passes `scope: .withBodyRecord` while `noop.bodyRecordEnabled` is on |
| `LabBookView.swift:522-526` (`LabBookFormat.value`) | Formats a value with the catalogue's decimals | Unchanged. `MarkerCatalog.definition(for:)` now also finds body-record keys, so their rows format with the catalogue's decimals |
| `LabBookView.swift:863-892` (`historyRow`) | One history row | 4B: gains the "Entered as" line (§10.6) |
| `MarkerEditorView.swift:110-116` | The marker picker lists `MarkerCatalog.builtIn` | Unchanged: `builtIn` does not grow, so scan and benchmark markers are entered only through their own sheets |
| `MarkerEditorView.swift:381-397`, `:402-423`, `:445-447` | Unit options, conversion at save, number parsing | 4B: all three go through `MarkerUnitTable` (§7.2), with the legacy tier while the flag is off |
| `LabMarkerStore.swift:112-145`, `:191-202` | Upsert and delete | Unchanged. `replaceLabMarkers` is added beside them |
| `Strand/Data/DataBackup.swift:14-24` | The backup is the SQLite file | Unchanged. Scan and benchmark rows travel in it as rows |
| `DeviceRegistryStore.swift:162-173` | Strap "Delete data" clears `labMarker` | Not changed by stage 4. See D14 |

### 4.5 Places where Lab Book values leave the screen they were typed on

| Site | What leaves | Action |
|---|---|---|
| `Strand/AI/AICoach.swift:1283-1302` | With "Also share my patterns & Lab Book" on, the latest value of up to eight markers goes to the Coach provider | Changed: a key for which `MarkerCatalog.isScanOnlyMarker` or `MarkerCatalog.isBenchmark` is true is skipped. No such row exists before stage 4, so the text for existing data is unchanged |
| `metricSeries` under `lab-book` | The daily projection of every numeric row | New keys appear in it. Readers found: the Lab Book detail's own comparison (`LabBookView.swift:906`). No widget, notification or export reader of `lab-book` was found in `Strand/`, `StrandiOS/`, `StrandiOSShared/` or `StrandiOSWidgets/` |
| `Strand/Data/CsvExport.swift:101-110` | The CSV export's series sidecar | Covers the imported and computed ids, not `lab-book`. Unchanged |
| Widgets, notifications | Nothing from Lab Book | Stage 4 adds nothing |

### 4.6 Android twins of the shared pieces

| Piece | Where | Stage 4 |
|---|---|---|
| Catalogue | `MarkerCatalog.kt:64-106` | Not updated, by the owner's decision. Still equal to Swift `builtIn` |
| Category enum | `MarkerCatalog.kt:24-36` | Unchanged and still equal: stage 4 adds no category |
| CSV alias table | `LabMarkerCsvImport.kt:383-417` | Not updated. Still equal to the Swift built-in scope |
| Unit switcher | `android/app/src/main/java/com/noop/ui/MarkerEditorScreen.kt:414-433` | Not updated. Equal to the Swift legacy tier |
| Lab Book list | `LabBookScreen.kt:120-123`, `:657`, `:663-666` | Unchanged. Lists body-record rows with a name made from the key |

## 5. Final names

### 5.1 Types, functions, files

| Thing | Name | Where |
|---|---|---|
| Second catalogue list | `MarkerCatalog.bodyRecord` | `Packages/StrandImport/Sources/StrandImport/MarkerCatalog.swift` |
| Catalogue scope | `MarkerCatalogScope` (`builtIn`, `withBodyRecord`) | Same file |
| Unit conversions | `MarkerUnitTable`, `MarkerUnitOption`, `MarkerUnitConversion`, `MarkerUnitTier` | New `Packages/StrandImport/Sources/StrandImport/MarkerUnitTable.swift` |
| Comparison and derived figures | `BodyRecordMath`, `BodyRecordReading`, `BodyRecordChange`, `BodyRecordDelta`, `BodyRecordDirection`, `BodyRecordComparison`, `BodyScanComponents`, `BodyScanDerived`, `BodyScanDerivedValue`, `BodyScanDerivedGap`, `BodyScanComponentSource`, `BodyScanDerivation`, `BodyScanCheckInput`, `BodyScanCheck`, `BodyScanChecks` | New `Packages/StrandAnalytics/Sources/StrandAnalytics/BodyRecord.swift` |
| Multi-row store call | `WhoopStore.replaceLabMarkers(deleteIds:upsert:)` | `Packages/WhoopStore/Sources/WhoopStore/LabMarkerStore.swift` |
| Union read for any marker | `LabBookUnion` | New `Strand/Data/LabBookUnion.swift` |
| Field table | `BodyScanField`, `BodyScanSection`, `BodyScanEntryUnit` | New `Strand/Data/BodyScanFields.swift` |
| Read and write funnel | `BodyRecordStore`, `BodyScan`, `BodyScanDraft`, `BodyRecordError` | New `Strand/Data/BodyRecordStore.swift` |
| Settings and flags | `BodyRecordSettings`, `BodyRecordFlags` | New `Strand/Data/BodyRecordSettings.swift` |
| Model and presenter | `BodyRecordModel`, `BodyScanSheetModel`, `BenchmarkSheetModel`, `BodyRecordPresenter` | New `Strand/Data/BodyRecordModel.swift`, `Strand/Data/BodyRecordPresenter.swift` |
| Screens | `BodyRecordView`, `BodyScanSheet`, `BodyScanDetailView`, `BodyScanCompareView`, `BenchmarkDetailView`, `BenchmarkSheet`, `BodyRecordKit` | New folder `StrandiOS/BodyRecord/` |
| Demo harness | `BodyRecordDemo` | New `StrandiOS/BodyRecord/BodyRecordDemo.swift` |
| Navigation | `RedesignRoute.bodyRecord`, `.bodyScan(id: String)`, `.bodyScanCompare(earlierId: String?, laterId: String?)`, `.benchmark(key: String)` | `StrandiOS/Redesign/RedesignRoute.swift` |
| Feature flag, 4A | `noop.bodyRecordEnabled`, Bool, default `false` | `BodyRecordSettings.enabledKey` |
| Feature flag, 4B | `noop.labReportUnitsEnabled`, Bool, default `false` | `BodyRecordSettings.labReportUnitsKey` |
| Scan source id | `"body-scan"` (`MarkerCatalog.scanSource`) | The `source` column of every row a scan sheet writes |
| Scan note key | `"scan_note"` (`MarkerCatalog.scanNoteKey`) | A row with nil `value` and the note in `valueText` |

The model, presenter, store, field table and settings live under `Strand/` so that `StrandTests`,
which runs only on the macOS `Strand` scheme, can test them, as stage 1 did (stage 1 specification
§5). The SwiftUI views live under `StrandiOS/`.

### 5.2 Scan markers

Appended to `MarkerCatalog.bodyRecord` in this order. Every entry has `referenceTextHint: nil` and
`higherIsBetter: nil`. "Stored unit" is the catalogue's `canonicalUnit` and the unit every row the
scan sheet writes carries.

| Key | Display name | Category | Stored unit | Decimals |
|---|---|---|---|---|
| `scan_fat_mass` | Fat mass (scan) | `imaging` | kg | 1 |
| `scan_lean_mass` | Lean mass (scan) | `imaging` | kg | 1 |
| `scan_bone_mass` | Bone mineral content (scan) | `imaging` | kg | 2 |
| `scan_fat_free_mass` | Fat-free mass (scan) | `imaging` | kg | 1 |
| `scan_visceral_fat_mass` | Visceral fat mass (scan) | `imaging` | g | 0 |
| `scan_visceral_fat_area` | Visceral fat area (scan) | `imaging` | cm² | 0 |
| `scan_android_fat_pct` | Android fat (scan) | `imaging` | % | 1 |
| `scan_gynoid_fat_pct` | Gynoid fat (scan) | `imaging` | % | 1 |
| `scan_android_gynoid_ratio` | Android to gynoid ratio (scan) | `imaging` | ratio | 2 |
| `scan_arms_lean_mass` | Arms lean mass, total (scan) | `imaging` | kg | 2 |
| `scan_arm_left_lean_mass` | Left arm lean mass (scan) | `imaging` | kg | 2 |
| `scan_arm_right_lean_mass` | Right arm lean mass (scan) | `imaging` | kg | 2 |
| `scan_legs_lean_mass` | Legs lean mass, total (scan) | `imaging` | kg | 2 |
| `scan_leg_left_lean_mass` | Left leg lean mass (scan) | `imaging` | kg | 2 |
| `scan_leg_right_lean_mass` | Right leg lean mass (scan) | `imaging` | kg | 2 |
| `scan_trunk_lean_mass` | Trunk lean mass (scan) | `imaging` | kg | 2 |
| `scan_bmd` | Bone mineral density (scan) | `imaging` | g/cm² | 3 |
| `scan_bmd_t_score` | Bone density T-score (scan) | `imaging` | SD | 1 |
| `scan_bmd_z_score` | Bone density Z-score (scan) | `imaging` | SD | 1 |
| `scan_rmr_lab_estimate` | Resting metabolic rate (laboratory estimate) | `imaging` | kcal/day | 0 |
| `scan_note` | Scan note | `imaging` | (empty) | 0 |

Two measures a scan report prints have **no** entry here because they already have one:

| Measure | Key it is stored under | Category of the row |
|---|---|---|
| Total mass | `weight` (`MarkerCatalog.scanTotalMassKey`) | `bodyMeasurement` |
| Body-fat percentage | `body_fat` (`MarkerCatalog.scanBodyFatKey`) | `bodyMeasurement` |

Check against the private layout: every measure it lists has a row in one of the two tables above,
in a unit it prints, at a precision at least as fine as it prints. The leg sides, the bone density
figures and the note go beyond it and are optional.

### 5.3 Benchmark markers

Appended to `MarkerCatalog.bodyRecord` after the scan markers. Category `other` (D3). The list is a
general set of bodyweight tests; nothing in it says which ones the owner uses.

| Key | Display name | Stored unit | Decimals |
|---|---|---|---|
| `bench_pushup_reps` | Push-ups, most in one set | reps | 0 |
| `bench_incline_pushup_reps` | Incline push-ups, most in one set | reps | 0 |
| `bench_knee_pushup_reps` | Knee push-ups, most in one set | reps | 0 |
| `bench_pullup_reps` | Pull-ups, most in one set | reps | 0 |
| `bench_dead_hang_s` | Dead hang, longest hold | s | 0 |
| `bench_plank_s` | Plank, longest hold | s | 0 |
| `bench_wall_sit_s` | Wall sit, longest hold | s | 0 |
| `bench_grip_kg` | Grip strength | kg | 1 |

A custom benchmark is a row whose key is `LabMarkerCsvImport.customKey("bench " + name)`, which gives
`custom_bench_<slug>` (`LabMarkerCsvImport.swift:356-375`), with category `other` and a unit chosen
from `reps`, `s` and `kg`. `MarkerCatalog.isBenchmark(_:)` is true for the eight keys above and for
any key with the prefix `custom_bench_`.

The condition a test was done under (the height of the surface, the grip, a pause) goes in the
reading's `note` and is shown beside the reading. The app does not compare across different notes
any differently: it shows the note and leaves the judgement to the owner.

## 6. Pure logic: the API

No store, no clock, no `Calendar`, no `TimeZone`, no `Date`, no UI import in any of §6.

### 6.1 Catalogue — `Packages/StrandImport/Sources/StrandImport/MarkerCatalog.swift`

```swift
/// Which catalogue lists a name lookup may resolve against.
public enum MarkerCatalogScope: Sendable {
    /// The 30 built-in markers only. Byte-identical to the Kotlin catalogue.
    case builtIn
    /// The built-in markers and `MarkerCatalog.bodyRecord`.
    case withBodyRecord
}

extension MarkerCatalog {
    /// Scan and benchmark markers (stage 4 specification §5.2, §5.3), in that order.
    /// Not updated on Android, by the owner's decision (ruling R43).
    public static let bodyRecord: [MarkerDefinition]

    public static let scanSource = "body-scan"
    public static let scanTotalMassKey = "weight"
    public static let scanBodyFatKey = "body_fat"
    public static let scanNoteKey = "scan_note"
    public static let customBenchmarkPrefix = "custom_bench_"

    /// `builtIn`, or `builtIn + bodyRecord`.
    public static func definitions(in scope: MarkerCatalogScope) -> [MarkerDefinition]
    /// True for the 21 keys of §5.2 and for no other key. False for `weight` and `body_fat`.
    public static func isScanOnlyMarker(_ key: String) -> Bool
    /// True for the 8 keys of §5.3 and for any key with the prefix `custom_bench_`.
    public static func isBenchmark(_ key: String) -> Bool
}
```

`MarkerCatalog.builtIn` is not edited. `MarkerCatalog.definition(for:)` (`MarkerCatalog.swift:125`)
looks in `builtIn` first and then in `bodyRecord`, in every scope. That is safe with both flags off:
a body-record key can only be stored by a body-record sheet or by a CSV import in the
`withBodyRecord` scope, so no existing row changes its name or its formatting.

### 6.2 Unit table — `Packages/StrandImport/Sources/StrandImport/MarkerUnitTable.swift`

```swift
/// How a typed value becomes the stored one. The arithmetic is exactly as written.
public enum MarkerUnitConversion: Sendable, Equatable {
    case identity                                      // stored = typed
    case multiply(Double)                              // stored = typed * f
    case divide(Double)                                // stored = typed / d
    case affine(subtract: Double, divideBy: Double)    // stored = (typed - s) / d
}

public struct MarkerUnitOption: Sendable, Equatable {
    public let label: String                // as a report prints it, e.g. "mg/dL", "%"
    public let conversion: MarkerUnitConversion
    public init(label: String, conversion: MarkerUnitConversion)
}

public enum MarkerUnitTier: Sendable {
    /// Exactly today's switcher: five markers, one extra option each.
    case legacy
    /// Every option of §7.2.
    case extended
}

public enum MarkerUnitTable {
    public static let poundsPerKilogram = 2.20462
    public static let centimetersPerInch = 2.54

    /// The options for a catalogue key, the stored unit first with `.identity`. A key with no
    /// catalogue definition has no options (empty array).
    public static func options(for key: String, tier: MarkerUnitTier) -> [MarkerUnitOption]

    /// The stored value for `value` typed in the unit `label`. Nil when the key has no such option
    /// in the tier, or when `value` or the result is not finite.
    public static func toStored(_ value: Double, key: String, from label: String,
                                tier: MarkerUnitTier) -> Double?

    /// The inverse. Nil under the same conditions.
    public static func fromStored(_ value: Double, key: String, to label: String,
                                  tier: MarkerUnitTier) -> Double?

    /// A unit label reduced for matching: trimmed, lowercased, "μ" (U+03BC) folded to "µ"
    /// (U+00B5), "^2" and "2" after "cm" folded to "²".
    public static func normalizedLabel(_ label: String) -> String

    /// The stored-unit value of a row that carries any unit string: the row's own value when its
    /// unit matches the stored unit, the converted value when it matches an extended option, both
    /// compared through `normalizedLabel`. Nil for any other unit, and for a non-finite value.
    public static func storedValue(_ value: Double, key: String, rowUnit: String) -> Double?

    /// A number typed into an entry field. `decimalSeparator` is the device locale's.
    public static func parseEntry(_ text: String, decimalSeparator: Character) -> Double?
}
```

Inverses: `identity` returns the value; `multiply(f)` gives `stored / f`; `divide(d)` gives
`stored * d`; `affine(s, d)` gives `stored * d + s`.

`parseEntry` rules, decided:

1. Leading and trailing whitespace is removed.
2. One optional leading `-`.
3. Then one or more ASCII digits, optionally one separator and one or more ASCII digits.
4. The separator is `decimalSeparator` when that is `.` or `,`; otherwise `.`. The other of the two
   characters is not a separator: the text is rejected. Nothing is guessed about thousands groups.
5. Anything else returns nil: an empty string, an exponent, letters (`nan`, `inf`), two separators,
   a trailing separator, non-ASCII digits.
6. The result is nil unless finite.

`"5,5"` with separator `,` is 5.5. `"5,5"` with separator `.` is nil. `"1,500"` with separator `.`
is nil, never 1.5 and never 1500.

### 6.3 Comparison and derived figures — `Packages/StrandAnalytics/Sources/StrandAnalytics/BodyRecord.swift`

Conventions as `CutScorecard.swift`: caseless `public enum` namespaces, `Equatable, Sendable` value
types with explicit public initialisers, and on each public declaration a doc line stating "No
Kotlin twin, by ruling R43 of the stage 1 specification."

```swift
public enum BodyRecordMath {
    /// The text a value is shown as. `decimals` is clamped to 0...6.
    ///   decimals == 0:  String(Int(x.rounded()))            (half away from zero)
    ///   otherwise:      String(format: "%.<decimals>f", x)  (no locale: a "." separator)
    /// A result that is a negative zero ("-0", "-0.0", …) loses its minus sign.
    /// "—" when x is not finite or abs(x) >= 1e15.
    public static func displayString(_ x: Double, decimals: Int) -> String

    /// The number `displayString` shows, as a Double. `x` unchanged when it is not finite or
    /// abs(x) >= 1e15. Never negative zero.
    public static func quantize(_ x: Double, decimals: Int) -> Double
}

/// One value as it is displayed: already in the display unit, with the decimals it is shown at.
public struct BodyRecordReading: Equatable, Sendable {
    public let value: Double
    public let decimals: Int
    public init(value: Double, decimals: Int)
}

public enum BodyRecordDirection: String, Sendable { case up, down, same }

public struct BodyRecordDelta: Equatable, Sendable {
    public let earlier: Double      // quantized
    public let later: Double        // quantized
    public let delta: Double        // quantize(later - earlier); never negative zero
    public let percent: Double?     // quantize(delta / earlier * 100, decimals: 1); nil unless earlier > 0
    public let direction: BodyRecordDirection   // from the sign of `delta`
}

public enum BodyRecordChange: Equatable, Sendable {
    case both(BodyRecordDelta)
    case onlyEarlier(Double)        // quantized
    case onlyLater(Double)          // quantized
    case neither
}

public enum BodyRecordComparison {
    public static func compare(earlier: BodyRecordReading?,
                               later: BodyRecordReading?) -> BodyRecordChange
}
```

```swift
/// Segment lean masses of one scan, all in one unit. Nil means the report value was not entered.
public struct BodyScanComponents: Equatable, Sendable {
    public var armsLean: Double?
    public var armLeftLean: Double?
    public var armRightLean: Double?
    public var legsLean: Double?
    public var legLeftLean: Double?
    public var legRightLean: Double?
    public init(armsLean: Double? = nil, armLeftLean: Double? = nil, armRightLean: Double? = nil,
                legsLean: Double? = nil, legLeftLean: Double? = nil, legRightLean: Double? = nil)
}

public enum BodyScanDerivedGap: String, Sendable { case missingComponent, invalidComponent }

public enum BodyScanDerivedValue: Equatable, Sendable {
    case value(Double)
    case notAvailable(BodyScanDerivedGap)
}

public enum BodyScanComponentSource: String, Sendable { case printedTotal, sumOfSides }

public struct BodyScanDerived: Equatable, Sendable {
    /// Arms lean mass as a percentage of legs lean mass, one decimal.
    public let armToLegLeanPercent: BodyScanDerivedValue
    /// Where the arms and legs figures came from. Nil when that side was not available.
    public let armsSource: BodyScanComponentSource?
    public let legsSource: BodyScanComponentSource?
    /// (left - right) / max(left, right) * 100, one decimal. Positive: the left side is larger.
    public let armSideDifferencePercent: BodyScanDerivedValue
    public let legSideDifferencePercent: BodyScanDerivedValue
}

public enum BodyScanDerivation {
    public static func derive(_ components: BodyScanComponents) -> BodyScanDerived
}
```

```swift
/// The printed figures a scan sheet can cross-check. Masses in kilograms. Nil: not entered.
public struct BodyScanCheckInput: Equatable, Sendable {
    public var totalMass: Double?
    public var fatMass: Double?
    public var leanMass: Double?
    public var boneMass: Double?
    public var fatFreeMass: Double?
    public var bodyFatPercent: Double?
    public var armsLean: Double?
    public var armLeftLean: Double?
    public var armRightLean: Double?
    public var legsLean: Double?
    public var legLeftLean: Double?
    public var legRightLean: Double?
    public var androidFatPercent: Double?
    public var gynoidFatPercent: Double?
    public var androidGynoidRatio: Double?
    public init()        // every field nil
}

public enum BodyScanCheck: String, CaseIterable, Sendable {
    case totalIsFatLeanBone
    case fatFreeIsLeanBone
    case bodyFatPercentIsFatShare
    case armsIsLeftPlusRight
    case legsIsLeftPlusRight
    case ratioIsAndroidOverGynoid
}

public enum BodyScanChecks {
    public static let massToleranceKg = 0.25
    public static let percentTolerancePoints = 0.5
    public static let ratioTolerance = 0.02
    /// The checks whose operands are all present and usable and which do not hold, in
    /// `BodyScanCheck.allCases` order.
    public static func mismatches(_ input: BodyScanCheckInput) -> [BodyScanCheck]
}
```

## 7. Algorithms and formats

### 7.1 CSV name resolution

`LabMarkerCsvImport.parse(data:)`, `parse(text:)` and `resolveMarker(_:)` each gain a parameter
`scope: MarkerCatalogScope = .builtIn` (`LabMarkerCsvImport.swift:116`, `:126`, `:267`).

- `.builtIn`: the existing alias table (`:282-319`), unchanged. Output is byte-identical to today.
- `.withBodyRecord`: the existing table is consulted first; when it has no entry, a second table is
  consulted; then the custom-key fallback as today.

The second table is built once from `MarkerCatalog.bodyRecord`: for each definition,
`matchNorm(key)` and `matchNorm(displayName)` map to its key, exactly as the first table is built
(`:284-287`). Then these extras, written in `matchNorm` form:

| Alias | Key |
|---|---|
| `total_mass`, `total_body_mass`, `scan_total_mass` | `weight` |
| `scan_body_fat`, `body_fat_scan`, `total_body_fat_pct` | `body_fat` |
| `fat_mass`, `total_fat_mass` | `scan_fat_mass` |
| `lean_tissue_mass`, `lean_soft_tissue_mass`, `lean_mass_scan` | `scan_lean_mass` |
| `bmc`, `bone_mineral_content`, `bone_mass` | `scan_bone_mass` |
| `fat_free_mass`, `ffm` | `scan_fat_free_mass` |
| `visceral_fat_mass`, `vat_mass` | `scan_visceral_fat_mass` |
| `visceral_fat_area`, `vat_area` | `scan_visceral_fat_area` |
| `android_fat`, `android_fat_pct` | `scan_android_fat_pct` |
| `gynoid_fat`, `gynoid_fat_pct` | `scan_gynoid_fat_pct` |
| `android_gynoid_ratio`, `a_g_ratio`, `ag_ratio` | `scan_android_gynoid_ratio` |
| `arms_lean_mass`, `arms_lean` | `scan_arms_lean_mass` |
| `left_arm_lean_mass`, `left_arm_lean` | `scan_arm_left_lean_mass` |
| `right_arm_lean_mass`, `right_arm_lean` | `scan_arm_right_lean_mass` |
| `legs_lean_mass`, `legs_lean` | `scan_legs_lean_mass` |
| `left_leg_lean_mass`, `left_leg_lean` | `scan_leg_left_lean_mass` |
| `right_leg_lean_mass`, `right_leg_lean` | `scan_leg_right_lean_mass` |
| `trunk_lean_mass`, `trunk_lean` | `scan_trunk_lean_mass` |
| `bmd`, `bone_mineral_density` | `scan_bmd` |
| `t_score` | `scan_bmd_t_score` |
| `z_score` | `scan_bmd_z_score` |
| `rmr`, `resting_metabolic_rate` | `scan_rmr_lab_estimate` |
| `push_ups`, `pushups` | `bench_pushup_reps` |
| `incline_push_ups`, `incline_pushups` | `bench_incline_pushup_reps` |
| `knee_push_ups`, `knee_pushups` | `bench_knee_pushup_reps` |
| `pull_ups`, `pullups` | `bench_pullup_reps` |
| `dead_hang` | `bench_dead_hang_s` |
| `plank` | `bench_plank_s` |
| `wall_sit` | `bench_wall_sit_s` |
| `grip_strength` | `bench_grip_kg` |

`lean_mass` is not an alias: a scale's "lean mass" includes bone and a scan's does not. `scan_note`
is not importable by CSV: the importer skips a non-numeric value (`:192`).

A build-time assertion in the test suite (§12.1): no key of the second table is a key of the first.

`WhoopBiomarkerExportParser` keeps the default scope. The category and unit fallback at `:196-203`
needs no change: it already reads `MarkerCatalog.definition(for:)`.

### 7.2 The unit table

Legacy tier, bit-identical to `MarkerEditorView.swift:482-488`:

| Key | Stored unit | Extra option | Conversion |
|---|---|---|---|
| `total_cholesterol`, `ldl`, `hdl` | mmol/L | mg/dL | `multiply(1.0 / 38.67)` |
| `triglycerides` | mmol/L | mg/dL | `multiply(1.0 / 88.57)` |
| `fasting_glucose` | mmol/L | mg/dL | `multiply(1.0 / 18.0)` |

Extended tier: the legacy rows, plus:

| Key | Stored unit | Extra options | Conversion to the stored unit |
|---|---|---|---|
| `hba1c` | mmol/mol | % | `affine(subtract: 2.152, divideBy: 0.09148)` |
| `ferritin` | µg/L | ng/mL | `identity` |
| `iron` | µmol/L | µg/dL | `multiply(0.1791)` |
| `haemoglobin` | g/L | g/dL | `multiply(10)` |
| `vitamin_d` | nmol/L | ng/mL | `multiply(2.496)` |
| `vitamin_b12` | ng/L | pg/mL; pmol/L | `identity`; `multiply(1.355)` |
| `folate` | µg/L | ng/mL; nmol/L | `identity`; `divide(2.266)` |
| `tsh` | mIU/L | µIU/mL | `identity` |
| `free_t4` | pmol/L | ng/dL | `multiply(12.87)` |
| `crp` | mg/L | mg/dL | `multiply(10)` |
| `creatinine` | µmol/L | mg/dL | `multiply(88.4)` |
| `alt`, `ast`, `ggt` | U/L | IU/L | `identity` |
| `sodium`, `potassium` | mmol/L | mEq/L | `identity` |
| `weight`, `bench_grip_kg` | kg | lb | `divide(2.20462)` |
| `waist`, `height` | cm | in | `multiply(2.54)` |
| `scan_fat_mass`, `scan_lean_mass`, `scan_bone_mass`, `scan_fat_free_mass`, the seven segment keys | kg | lb; g | `divide(2.20462)`; `divide(1000)` |
| `scan_visceral_fat_mass` | g | kg; lb | `multiply(1000)`; `multiply(1000.0 / 2.20462)` |
| `bench_dead_hang_s`, `bench_plank_s`, `bench_wall_sit_s` | s | min | `multiply(60)` |

Single-unit markers in the extended tier (one option, the stored unit): `transferrin_saturation`,
`egfr`, `bp_systolic`, `bp_diastolic`, `resting_pulse`, `body_fat`, and every other body-record key.

The HbA1c row is the published master equation between the two reporting systems:
`percent = 0.09148 × mmol/mol + 2.152`. The weight and waist rows use the same constants and the
same operation as the resolver (`BodyMeasurementResolver.swift:156-157`), so a weight typed in
pounds in any sheet stores the kilograms the resolver would have computed. A test asserts
`MarkerUnitTable.poundsPerKilogram == UnitFormatter.poundsPerKilogram` and the same for the inch
(`Strand/Data/Units.swift:178`, `:180`).

Which unit the editor accepts for each blood marker a typical report gives, as found by reading:

| Marker | Report commonly prints | Editor accepts today | After 4B (flag on) |
|---|---|---|---|
| Fasting glucose | mg/dL or mmol/L | both | both |
| Total, LDL, HDL cholesterol, triglycerides | mg/dL or mmol/L | both | both |
| HbA1c | % or mmol/mol | **mmol/mol only** | both |
| Haemoglobin | g/dL | g/L only | both |
| Creatinine | mg/dL | µmol/L only | both |
| Vitamin D | ng/mL | nmol/L only | both |
| Vitamin B12 | pg/mL | ng/L only (same number, other label) | all three |
| Ferritin, folate | ng/mL | µg/L only (same number, other label) | both labels; folate also nmol/L |
| Serum iron | µg/dL | µmol/L only | both |
| TSH | µIU/mL | mIU/L only (same number) | both labels |
| Free T4 | ng/dL | pmol/L only | both |
| CRP | mg/L or mg/dL | mg/L only | both |
| ALT, AST, GGT | U/L or IU/L | U/L | both labels |
| Sodium, potassium | mmol/L or mEq/L | mmol/L | both labels |
| eGFR, transferrin saturation | as stored | as stored | as stored |

### 7.3 `quantize` and `compare`

`quantize(x, decimals)` is `Double(displayString(x, decimals))`. Defining it through the display
text makes the comparison a calculation on the numbers the owner sees, which is what the roadmap's
acceptance asks ("matches a hand calculation").

`compare(earlier:later:)`:

1. A reading whose `value` is not finite is treated as absent.
2. Both absent: `.neither`. One absent: `.onlyEarlier(q)` or `.onlyLater(q)` with the quantized
   value of the one present.
3. Both present. `d = max(earlier.decimals, later.decimals)`. `a = quantize(earlier.value, d)`,
   `b = quantize(later.value, d)`, `delta = quantize(b - a, d)`.
4. `percent = quantize(delta / a * 100, 1)` when `a > 0`; otherwise nil.
5. `direction` is `.up` when `delta > 0`, `.down` when `delta < 0`, `.same` when `delta == 0`.

The order of the two scans is the caller's business: `BodyRecordPresenter` always passes the scan
with the smaller `takenAt` as `earlier` (§7.6).

### 7.4 `derive`

A component is **usable** when it is non-nil, finite and greater than zero.

Resolving a pair total (arms, then legs, each from its total and its two sides):

1. The printed total is usable: use it; source `printedTotal`.
2. The printed total is nil and both sides are usable: use `left + right`; source `sumOfSides`.
3. The printed total is non-nil and not usable, or it is nil and a side is non-nil and not usable:
   `invalidComponent`.
4. Otherwise: `missingComponent`.

`armToLegLeanPercent`:

- Either pair total is `invalidComponent`: `.notAvailable(.invalidComponent)`.
- Otherwise either is `missingComponent`: `.notAvailable(.missingComponent)`.
- Otherwise `r = arms / legs * 100`. Not finite: `.notAvailable(.invalidComponent)`. Else
  `.value(quantize(r, 1))`.

`armSideDifferencePercent` (and legs likewise):

- A side is non-nil and not usable: `.notAvailable(.invalidComponent)`.
- A side is nil: `.notAvailable(.missingComponent)`.
- Otherwise `.value(quantize((left - right) / max(left, right) * 100, 1))`.

The function never returns zero for a missing component, never divides by a value that is not
greater than zero, and never returns a non-finite number.

### 7.5 `mismatches`

A check is evaluated only when every operand it names is usable (§7.4); otherwise it is silent.

| Check | Mismatch when |
|---|---|
| `totalIsFatLeanBone` | `abs(total - (fat + lean + bone)) > 0.25` |
| `fatFreeIsLeanBone` | `abs(fatFree - (lean + bone)) > 0.25` |
| `bodyFatPercentIsFatShare` | `abs(p - fat / total * 100) > 0.5` **and**, when lean is usable, `abs(p - fat / (fat + lean) * 100) > 0.5`. Reports differ on whether bone is in the denominator; either reading passes. Operands required: `p`, fat, total |
| `armsIsLeftPlusRight` | `abs(arms - (left + right)) > 0.25` |
| `legsIsLeftPlusRight` | `abs(legs - (left + right)) > 0.25` |
| `ratioIsAndroidOverGynoid` | `abs(ratio - android / gynoid) > 0.02` |

A mismatch is an entry aid. It shows one neutral line (§11) and never blocks Save: the report is the
authority, and a report can be internally rounded in ways this cannot know.

### 7.6 What a scan is, and the order of scans

A **scan** is every Lab Book row that shares one `source` and one `takenAt`, across the strap ids of
ruling R25, provided at least one of those rows has a scan-only key (§6.1). Its members are:

- every row of that `(source, takenAt)` whose key is scan-only, and
- the `weight` row and the `body_fat` row of that `(source, takenAt)`, when they exist.

Consequences, all intended:

- A scan needs no table, no id column and no settings key. Its identity is
  `"<source>\u{1F}<takenAt>"`.
- A scan typed in the sheet has source `body-scan`. A scan imported from a markers CSV has source
  `lab-csv` and `takenAt` at noon UTC of its day (`LabBookView.swift:596-599`); it is shown as a
  scan and is read-only in the body record.
- A `weight` row with no scan-only row at its `(source, takenAt)` is not a scan. A manual weigh-in
  never becomes one.
- A row stored under two strap ids (same key, instant, source) is one row; the copy under the
  earlier id in the union order stands for it, as in `BodyMeasurementProvider.swift:238-250`.

Scans are ordered by `takenAt` ascending, then by `source`. The order in which they were typed in
plays no part. "The latest scan" is the last of that order; "the previous scan" is the one before.

Reading a member row's value: `MarkerUnitTable.storedValue(value, key:, rowUnit:)`, then the range
of §7.7. A row whose value is nil, whose unit is not recognised, or whose stored value is outside
the range is **unreadable**: it is counted and named, and it is never shown as a number or as zero.

### 7.7 Fields, sections, ranges

`BodyScanField` lists the fields in the order a report prints them. Ranges are inclusive, in the
stored unit. They guard against a slipped decimal point and are not a statement about any body.

| Section | Field | Key | Entry units | Range | Percent change shown |
|---|---|---|---|---|---|
| Whole body | Total mass | `weight` | kg, lb | 30 … 250 (`WeighInStore.weightRangeKg`) | yes |
| | Fat mass | `scan_fat_mass` | kg, lb, g | 1 … 200 | yes |
| | Lean mass | `scan_lean_mass` | kg, lb, g | 10 … 150 | yes |
| | Bone mineral content | `scan_bone_mass` | kg, lb, g | 0.5 … 6 | yes |
| | Fat-free mass | `scan_fat_free_mass` | kg, lb, g | 10 … 160 | yes |
| | Body fat | `body_fat` | % | 1 … 75 | no (a change in points) |
| Fat distribution | Visceral fat mass | `scan_visceral_fat_mass` | g, kg, lb | 0 … 10000 | yes |
| | Visceral fat area | `scan_visceral_fat_area` | cm² | 0 … 1000 | yes |
| | Android fat | `scan_android_fat_pct` | % | 1 … 80 | no |
| | Gynoid fat | `scan_gynoid_fat_pct` | % | 1 … 80 | no |
| | Android to gynoid ratio | `scan_android_gynoid_ratio` | ratio | 0.1 … 5 | yes |
| Lean mass by region | Arms, total | `scan_arms_lean_mass` | kg, lb, g | 1 … 30 | yes |
| | Left arm | `scan_arm_left_lean_mass` | kg, lb, g | 0.5 … 15 | yes |
| | Right arm | `scan_arm_right_lean_mass` | kg, lb, g | 0.5 … 15 | yes |
| | Legs, total | `scan_legs_lean_mass` | kg, lb, g | 5 … 60 | yes |
| | Left leg | `scan_leg_left_lean_mass` | kg, lb, g | 2 … 30 | yes |
| | Right leg | `scan_leg_right_lean_mass` | kg, lb, g | 2 … 30 | yes |
| | Trunk | `scan_trunk_lean_mass` | kg, lb, g | 5 … 80 | yes |
| Bone density | Bone mineral density | `scan_bmd` | g/cm² | 0.3 … 2.5 | yes |
| | T-score | `scan_bmd_t_score` | SD | −8 … 8 | no |
| | Z-score | `scan_bmd_z_score` | SD | −8 … 8 | no |
| Energy | Resting metabolic rate, laboratory estimate | `scan_rmr_lab_estimate` | kcal/day | 500 … 5000 | yes |
| Note | Note | `scan_note` | text, at most 500 characters | — | — |

Visceral fat mass and area admit zero: a report can print a measured zero. Every other empty field
writes no row, and an empty field is "not entered", never zero.

Benchmark ranges: `reps` 0 … 1000 (whole numbers only); `s` 0 … 86400; `bench_grip_kg` 1 … 150.

Display unit: masses stored in kilograms are shown in kilograms or pounds following `units.system`,
through the app's existing formatter (`Strand/Data/Units.swift:242`). Grams, areas, densities,
scores, ratios, percentages and kcal are always shown in the stored unit. Decimals are the
catalogue's in either unit.

### 7.8 The instant and the day of a scan

The scan sheet asks for a date, not a time.

- New scan, or an edit that changes the day: `takenAt` is 12:00:00 local time on the chosen day in
  the device's zone at the moment of saving, or the moment of saving if that is earlier (a scan
  entered before noon on its own day). Local noon exists on every day in every zone.
- An edit that keeps the day keeps `takenAt` exactly.
- `day` is `LocalDayWindows(timeZone:).dayKey(for:)` of `takenAt` in that zone
  (`Packages/StrandAnalytics/Sources/StrandAnalytics/LocalDayWindows.swift:265`), the rule
  `WeighInStore.swift:82` uses. It is stored and never recomputed, so travel does not move a scan.
- A future day is refused.

A benchmark and a blood reading keep the date-and-time picker they have today.

## 8. Ruling R41: how a scan's total mass joins the resolver

### 8.1 The rule

**A scan's total mass is a Lab Book `weight` row.** Its `markerKey` is `weight`, its `category`
`bodyMeasurement`, its `unit` `kg`, its `source` `body-scan`, its `takenAt` and `day` the scan's. It
is the only place the total is stored. There is no `scan_total_mass` key, no copy in a scan table,
no settings value.

Therefore:

- The resolver needs **no change**. Under the `unified` policy it already admits every Lab Book
  `weight` row whatever its source (`BodyMeasurementResolver.swift:116-126`). Newest day wins; on
  one day the greatest `takenAt` wins, then the greatest `id` (stage 1 specification §8.2).
- The scan screens read the total from that same row, through the weigh-in store's union read
  (`WeighInStore.swift:196-200`), picking the row whose `(source, takenAt)` is the scan's.
- Today, Settings, the estimates, Health readiness, the scorecard, the weigh-in history and the
  Coach context each show the resolver's value as before. When the scan is the newest weight
  reading, that value is the scan's total mass, and it is the same stored number the scan shows.
- With `noop.cutScorecardEnabled` off the legacy policies ignore Lab Book, so a scan changes nothing
  on Today or in the estimates, exactly as a Lab Book weight entry changes nothing today.

The same construction applies to body-fat percentage and the `body_fat` key, although no "current
body fat" readout exists (§4.2).

### 8.2 The writer

`BodyRecordStore` writes the `weight` row inside the scan's single transaction. It does not go
through `WeighInStore.save`, which writes source `manual` and one or two rows of its own
(`WeighInStore.swift:75-101`). It keeps the funnel's rules by construction:

- the key comes from `BodyMeasurementKind.weight.markerKey` (`BodyMeasurementResolver.swift:16-21`),
  so the source scan's `lab-marker-key` pattern never matches in the new file;
- the value is validated against `WeighInStore.weightRangeKg`, converted with the resolver's
  constant (§7.2), and stored in kilograms, unrounded;
- every write ends with `repository.refresh()` and then `provider.refresh()`, the provider being the
  one writer of the profile mirror (`BodyMeasurementProvider.swift:209-220`).

### 8.3 Correcting it

Ruling R41 asks that every place showing the current value offers a way to correct it. Those places
are unchanged: they open the weigh-in sheet or the history. In the history a scan's row says where
it came from and opens the scan (§10.7), and the scan has Edit and Delete. Deleting a scan deletes
its total-mass row with it, and the delete sheet says so.

### 8.4 What this means for the scorecard

A scan's total mass is a weight reading on its day, so it can be the latest reading of its week and
feed the fitted rate. That follows from "one number per variable": excluding it from the scorecard
would make the scorecard's current weight differ from every other surface's on a scan day. The
weigh-in history already captions the reading that represents each week
(`CutScorecardPresenter.swift:861-874`), so the owner can see when it is the scan. Question O2 in
§15 asks the owner to confirm.

## 9. Storage

### 9.1 Rows

Scan rows, written only by `BodyRecordStore`:

| Column | Value |
|---|---|
| `id` | `"<markerKey>-<takenAt>-<8 hex>"`, the form `MarkerEditorView.swift:430` uses |
| `deviceId` | The active strap id for a new scan, as Lab Book writes (ruling R25). For an edit: the device id of the scan's existing rows; when they span more than one id, the one that comes first in the union order |
| `markerKey` | A key of §7.7 |
| `category` | `imaging` for a scan-only key, `bodyMeasurement` for `weight` and `body_fat` |
| `takenAt`, `day` | §7.8, the same for every row of the scan |
| `value` | The stored-unit value, unrounded. Nil for `scan_note` |
| `valueText` | Nil, except `scan_note`: the note text, trimmed |
| `unit` | The stored unit. The empty string for `scan_note` |
| `source` | `body-scan` |
| `note`, `referenceText` | Nil |

Benchmark rows: `category` `other`, `source` `manual`, `unit` the stored unit, `note` the condition
text or nil, written with the existing `upsertLabMarkers` and removed with `deleteLabMarker`.

Reads go through `LabBookUnion`:

```swift
enum LabBookUnion {
    /// Rows of one marker across the ids of ruling R25, de-duplicated by instant and source,
    /// the copy under the earlier id standing for a duplicate. Oldest first.
    static func rows(markerKey: String, store: WhoopStore, activeDeviceId: String) async -> [LabMarkerRow]
    /// Rows of one category across the same ids, de-duplicated by marker, instant and source.
    static func rows(category: String, store: WhoopStore, activeDeviceId: String) async -> [LabMarkerRow]
}
```

It takes its ids from `BodyMeasurementProvider.unionedDeviceIds(store:activeDeviceId:)`
(`BodyMeasurementProvider.swift:225-232`) and repeats the loop of `:238-250` for an arbitrary key.
It is never called with the `weight` or `waist` key: those are read through `WeighInStore.readings`.
When the "Lab Book ownership" change of ruling R42 lands it should own this union; until then this
file is its second user and says so in a comment.

`BodyRecordStore`:

```swift
struct BodyScan: Equatable, Identifiable {
    let id: String                       // "<source>\u{1F}<takenAt>"
    let source: String
    let takenAt: Int
    let day: String
    let values: [String: Double]         // key -> stored-unit value, readable rows only
    let rows: [String: LabMarkerRow]     // key -> the stored row, every member
    let note: String?
    let unreadableKeys: [String]         // sorted
    var isEditable: Bool { source == MarkerCatalog.scanSource }
}

struct BodyScanDraft: Equatable {
    var day: String                      // "yyyy-MM-dd", the chosen local day
    var values: [String: Double]         // key -> stored-unit value; absent key = not entered
    var note: String?
}

enum BodyRecordError: Error, Equatable {
    case nothingToSave                   // no scan-only numeric value in the draft
    case outOfRange(key: String)
    case noteTooLong
    case futureDay
    case instantOccupied                 // another scan already holds the target instant
    case scanNotFound
    case notEditable                     // the scan's source is not body-scan
    case storeUnavailable
}

@MainActor final class BodyRecordStore {
    init(repository: Repository, provider: BodyMeasurementProvider? = nil,
         timeZone: @escaping () -> TimeZone = { TimeZone.current },
         now: @escaping () -> Date = { Date() })
    func scans() async -> [BodyScan]
    @discardableResult func save(_ draft: BodyScanDraft, replacing existing: BodyScan?) async throws -> BodyScan
    func delete(_ scan: BodyScan) async throws
    func benchmarkReadings(key: String) async -> [LabMarkerRow]
    func benchmarkKeysPresent() async -> [String]
    @discardableResult func saveBenchmark(key: String, value: Double, unit: String, takenAt: Date,
                                          note: String?) async throws -> LabMarkerRow
    func deleteBenchmark(_ row: LabMarkerRow) async throws
}
```

The initialiser mirrors `WeighInStore.swift:52-59`.

`save`, new scan: validate everything first (at least one scan-only numeric value; every value in
its range; the note within its length; the day not in the future). Compute `takenAt` and `day`
(§7.8). Refuse with `instantOccupied` if any row with source `body-scan` and that `takenAt` exists
under any unioned id for any key of §7.7. Build the rows. One `replaceLabMarkers(deleteIds: [],
upsert: rows)`. Finish as §8.2. Return the scan as stored.

`save`, replacing: re-read the scan; `scanNotFound` if no row of it remains; `notEditable` unless
its source is `body-scan`. Then:

- same day: a key present before and after keeps its row `id`, `deviceId`, `category`, `takenAt`,
  `day`, `source`, `note` and `referenceText`, and gets the new `value` and `unit`; a key that was
  removed has its row id in `deleteIds`; a new key gets a new row.
- another day: the occupied check runs at the new instant; every old row id goes in `deleteIds` and
  every row is new.

Either way it is **one** `replaceLabMarkers` call, so there is no state in which half a scan exists.

`delete`: `notEditable` unless the source is `body-scan`; then one `replaceLabMarkers(deleteIds:
allRowIds, upsert: [])` and the finish of §8.2.

### 9.2 The store function

Added to `LabMarkerStore.swift`, beside `upsertLabMarkers`:

```swift
/// Delete the rows with these ids and upsert `rows`, in one transaction, then re-project every
/// touched (deviceId, markerKey, day) cell. An id that is not stored is skipped. Returns the number
/// of rows written by the upsert. If anything throws, nothing is changed.
@discardableResult
public func replaceLabMarkers(deleteIds: [String], upsert rows: [LabMarkerRow]) async throws -> Int
```

Inside one `syncWrite` (`WhoopStore.swift:171-173`, a single GRDB write transaction): for each id,
fetch the row, delete it, remember its cell; for each row, the same `INSERT … ON CONFLICT` statement
`upsertLabMarkers` runs (`LabMarkerStore.swift:122-138`); then `reprojectCells` over the union of the
cells. With both arguments empty it does nothing and returns 0.

This is a function, not a schema change: no migration, no new table, no new column, no new index.
The Room side has no counterpart; §12.7 records it.

### 9.3 The "entered as" annotation (4B)

When `noop.labReportUnitsEnabled` is on and a reading is typed in an option other than the stored
unit, the row's `valueText` is set to the typed text and the option's label, separated by one space:
the typed text is trimmed and its decimal separator written as `.`, with nothing else changed, so
"5,50" in percent becomes `5.50 %`. For an `identity` option (another label for the same number)
the annotation is written as well, since the label is what the report printed. When the stored unit
is used, `valueText` stays nil.

`value` and `unit` are the stored-unit value and the stored unit, as today. Every existing reader
takes `value` first and looks at `valueText` only when `value` is nil (`LabBookView.swift:449-453`,
`:894-897`; `AICoach.swift:1294`; `LabBookScreen.kt:675`), so the annotation changes no existing
readout.

### 9.4 Settings

All in `UserDefaults.standard`, declared in `BodyRecordSettings`.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `noop.bodyRecordEnabled` | Bool | `false` | 4A. Off: no Health row, no body-record screen or sheet, built-in CSV scope, the weigh-in history as it is today |
| `noop.labReportUnitsEnabled` | Bool | `false` | 4B. Off: the legacy unit tier, `Double(_:)` parsing, no annotation, no "Save and add another" |

`BodyRecordFlags` is the one observable copy of both, built as `CutScorecardFlag` is
(`Strand/Data/CutScorecardModel.swift:18-42`): it follows every write to either key and reading it
never writes.

### 9.5 Backup whitelist

**No change on either platform.** Both keys are `noop.*` toggles, which are per install by the
whitelist's own rule (`Packages/WhoopStore/Sources/WhoopStore/BackupSettings.swift:40-42`), and a
Bool cannot cross. Stage 4 stores nothing else in settings. After a restore both features are off
until switched on, and every scan, benchmark and annotated reading is in the database rows.

## 10. Screens and states

Frames are designed at G1 (§14, WP 4-2). Every state below needs a frame, at the default text size
and at the largest accessibility size (`StrandiOS/App/StrandiOSApp.swift:247`). No frame draws a
chart, a band, a target line or a colour that judges a value: figures are in the primary text
colour, a change carries a sign and a direction word, and the only semantic colour is red on Delete.

There is **no widget and no notification** in this stage; that list is empty by decision.

### 10.1 Body record screen (`BodyRecordView`, route `.bodyRecord`)

Reached from a row in the Health tab's "More health" card, mounted only while the flag is on, in the
manner of the scorecard row (`StrandiOS/Redesign/RedesignHealthView.swift:474-483`).

| # | State | Shows |
|---|---|---|
| G1 | Loading | Skeleton |
| G2 | Nothing recorded | "No scans yet" and "No benchmarks yet", each with its add button; a row to Lab Book for blood results |
| G3 | One scan | The scan card (date, the whole-body figures entered, the derived line) and "Add a second scan to compare" |
| G4 | Two or more scans | The latest scan card; "Compare with <date of the previous scan>"; the list of scans, newest first |
| G5 | A scan with unreadable rows | The card, plus "<n> values in this scan could not be read. They remain in Lab Book." |
| G6 | An imported scan | The card with "Imported from CSV" |
| G7 | Benchmarks | One row per benchmark with a reading: name, latest value, date, change since the previous reading and since the first |
| G8 | A benchmark with one reading | The row with no change line |
| G9 | Store could not be opened | "Couldn't open the local store." and nothing else |
| G10 | Largest text size | G4 and G7 |

The screen shows no "current weight". A scan's total mass appears with the scan's date.

### 10.2 Scan sheet (`BodyScanSheet`)

| # | State | Shows |
|---|---|---|
| H1 | New, empty | Date (today), the mass-unit control (kg or lb, following `units.system`), the sections of §7.7 with empty fields, Save disabled |
| H2 | Filled, valid | Save enabled |
| H3 | A field in another unit | Under the field: "Stored as <value> <unit>." (the idiom of `MarkerEditorView.swift:283-287`) |
| H4 | A field out of range | Under the field: "Enter a value between <low> and <high> <unit>." Save disabled |
| H5 | Not a number | "Use digits and one decimal separator." Save disabled |
| H6 | Figures that do not add up | One line under the affected section (§11). Save stays enabled |
| H7 | Only the total mass entered | "Add at least one scan figure besides total mass." Save disabled |
| H8 | A weigh-in already on that day | A neutral line: "A weight of <value> is already recorded on this day. Both are kept." |
| H9 | Editing | Fields prefilled in the display unit; Save and Delete |
| H10 | Editing, day changed to one that already has a scan at that instant | "Another scan is already recorded at that time." Nothing is written |
| H11 | Saving | Controls disabled |
| H12 | Save failed | "Couldn't save the scan. Nothing was changed." |
| H13 | Delete confirmation | "Delete this scan? Its total mass is removed from your weight history too." Delete, Cancel |
| H14 | Largest text size | H2 |

Score fields (T-score, Z-score) carry a sign toggle, because the decimal keypad has no minus key.

### 10.3 Scan detail (`BodyScanDetailView`, route `.bodyScan(id:)`)

| # | State | Shows |
|---|---|---|
| I1 | A full scan | Sections in report order, each entered figure with its unit; the derived block; the note; Edit |
| I2 | A sparse scan | Only the fields entered. A section with nothing entered is absent. No field is shown as zero or as a dash-with-unit |
| I3 | Derived figure not available | "Arms to legs: not available. Enter arms and legs lean mass." |
| I4 | Derived figure from the two sides | "From left and right arm." under the figure |
| I5 | Unreadable rows | As G5, naming the fields |
| I6 | Imported scan | No Edit. "Imported from CSV. Edit or delete its readings in Lab Book." |
| I7 | The scan no longer exists | The screen leaves the stack |
| I8 | Largest text size | I1 |

### 10.4 Scan comparison (`BodyScanCompareView`, route `.bodyScanCompare`)

Two scans are chosen from two menus. Nil ids mean the two newest. Whatever is chosen, the scan with
the smaller `takenAt` is the left column.

| # | State | Shows |
|---|---|---|
| J1 | Two scans, all markers in both | Per field: earlier value, later value, change with sign and unit, percent change where §7.7 allows; then the derived rows |
| J2 | A marker only in the earlier scan | Earlier value; "not entered" in the later column; no change |
| J3 | A marker only in the later scan | "not entered"; later value; no change |
| J4 | A marker in neither | The row is absent |
| J5 | No change | "No change" |
| J6 | One scan only | That scan's values and "One scan so far. A second scan makes a comparison." |
| J7 | No scans | "No scans yet" and the add button |
| J8 | The same scan chosen twice | The menus do not allow it: the other menu's choice is absent from each |
| J9 | Scans entered out of order | Identical to J1 |
| J10 | A derived figure available in one scan only | As J2 or J3, with "not available" |
| J11 | Largest text size | J1, laid out as stacked rows |

### 10.5 Benchmarks (`BenchmarkDetailView`, `BenchmarkSheet`)

| # | State | Shows |
|---|---|---|
| K1 | Sheet, new | Benchmark picker (the eight, then "Custom benchmark"), value, date and time, condition note |
| K2 | Sheet, a timed benchmark | The value accepts seconds (`45`) or minutes and seconds (`1:30`) |
| K3 | Sheet, custom | Name and a unit from reps, s, kg |
| K4 | Sheet, invalid value | Range or number message as H4, H5; a repetition count with a decimal part: "Enter a whole number." |
| K5 | Detail, several readings | Newest first: value, date, note; change against the previous reading; delete on each |
| K6 | Detail, one reading | The reading and "One reading so far." |
| K7 | Delete confirmation | "Delete this reading?" |
| K8 | Largest text size | K5 |

### 10.6 Lab Book editor (4B, flag `noop.labReportUnitsEnabled`)

| # | State | Shows |
|---|---|---|
| L1 | A marker with several options | The existing segmented control with every option of §7.2 |
| L2 | A non-stored option chosen, value typed | "Stored as <stored value> <stored unit>." For an offset conversion the formula is shown in words (§11) |
| L3 | An identity option chosen | "Same number, stored as <stored unit>." |
| L4 | Not a number | Save disabled and "Use digits and one decimal separator." |
| L5 | After "Save and add another" | The marker list again, the date kept, "Saved <marker name>." |
| L6 | History row of an annotated reading | The stored value and unit, and under it "Entered as <typed text and unit>" |
| L7 | Flag off | The editor exactly as it is at `0b89b814` |

### 10.7 Weigh-in history (stage 1 screen)

While `noop.bodyRecordEnabled` is on, a weight row whose source is `body-scan` shows the caption
"Lab Book · body scan" in place of "Lab Book", has no edit or delete action there, and a tap pushes
`.bodyScan(id:)`. While the flag is off it is an ordinary Lab Book row, as every non-manual row is
today (`CutScorecardPresenter.swift:876-889`).

### 10.8 Settings

Two rows in a "Body record" card built as the scorecard card is (`Strand/Screens/SettingsView.swift:1860-1880`),
iPhone only: "Body record" (scans and benchmarks) and "Report units in Lab Book". Both off by
default. Switching either off hides its surfaces and deletes nothing.

## 11. User-facing strings

English, final unless the owner edits them at G1. Each is localised in the ten existing locales by
WP 4-8. No string judges a value.

| Where | String |
|---|---|
| Health row, screen title | Body record |
| Health row detail, no scans | No scans yet |
| Health row detail | Last scan <date> |
| Sections | Scans · Benchmarks · Blood results |
| Buttons | Add a scan · Add a benchmark · Compare scans · Edit · Delete · Save · Cancel · Open Lab Book |
| Empty | No scans yet · No benchmarks yet |
| One scan | Add a second scan to compare |
| Scan sections | Whole body · Fat distribution · Lean mass by region · Bone density · Energy · Note |
| Field labels | Total mass · Fat mass · Lean mass · Bone mineral content · Fat-free mass · Body fat · Visceral fat mass · Visceral fat area · Android fat · Gynoid fat · Android to gynoid ratio · Arms, total · Left arm · Right arm · Legs, total · Left leg · Right leg · Trunk · Bone mineral density · T-score · Z-score · Resting metabolic rate · Note |
| RMR caption | Laboratory estimate. Not used by NOOP's calorie figures. |
| Scan sheet intro | Type the figures as your report prints them. Leave out anything it does not give. |
| Converted | Stored as <value> <unit>. |
| Identity option | Same number, stored as <unit>. |
| HbA1c conversion | mmol/mol = (percent − 2.152) ÷ 0.09148 |
| Range | Enter a value between <low> and <high> <unit>. |
| Not a number | Use digits and one decimal separator. |
| Whole number | Enter a whole number. |
| Too little | Add at least one scan figure besides total mass. |
| Mismatch | These figures do not add up as typed. Check them against the report. |
| Same-day weight | A weight of <value> is already recorded on this day. Both are kept. |
| Occupied | Another scan is already recorded at that time. |
| Save failed | Couldn't save the scan. Nothing was changed. |
| Delete scan | Delete this scan? Its total mass is removed from your weight history too. |
| Delete reading | Delete this reading? |
| Imported | Imported from CSV · Imported from CSV. Edit or delete its readings in Lab Book. |
| Unreadable | <n> values in this scan could not be read. They remain in Lab Book. |
| Not entered | not entered |
| Derived | Arms to legs · <value>% of legs lean mass · Left and right arm · Left and right leg · Left <value>% more · Right <value>% more · Equal · From left and right arm. · From left and right leg. |
| Derived, missing | Not available. Enter arms and legs lean mass. · Not available. Enter both sides. |
| Derived, invalid | Not available. A figure it needs could not be used. |
| Comparison | Earlier · Later · Change · No change · up · down · <value> points |
| One scan | One scan so far. A second scan makes a comparison. |
| Benchmark | Condition (optional) · e.g. surface height or grip · One reading so far. · Since the previous reading · Since the first reading · Custom benchmark |
| History caption | Lab Book · body scan |
| Lab Book editor | Save and add another · Saved <marker name>. · Entered as <typed value and unit> |
| Settings | Body record · Scans and benchmarks, entered as printed and compared. · Report units in Lab Book · Type blood results in the unit your report prints. |
| Screen note | These are your own figures shown back to you. NOOP does not decide whether any value is normal, high or low. |

The last string is the existing Lab Book note (`LabBookView.swift:641`) reused, not a new one.

## 12. Test plan

Every test uses the §13 fixture or values invented beside it. No test reads the real store.

### 12.1 `Packages/StrandImport/Tests/StrandImportTests/`

`MarkerCatalogBodyRecordTests.swift`

- `testBuiltInListIsUnchanged` — the 30 keys, names, categories, units and decimals as a literal.
- `testBodyRecordCatalogueIsPinned` — one line per entry, `key|displayName|category|unit|decimals`,
  as a literal. This literal is the oracle a later Kotlin test pastes (§12.7).
- `testNoBodyRecordKeyCollidesWithABuiltInKey`
- `testEveryEntryHasNoReferenceHintAndNoDirection`
- `testScanEntriesUseTheImagingCategoryAndBenchmarksUseOther`
- `testDefinitionForResolvesBothLists`
- `testIsScanOnlyMarkerIsFalseForWeightAndBodyFat`
- `testIsBenchmarkCoversTheEightAndTheCustomPrefix`
- `testDefinitionsInScope`

`LabMarkerCsvBodyRecordScopeTests.swift`

- `testBuiltInScopeOutputIsUnchangedForAFileNamingScanMarkers` — they import as `custom_…` keys.
- `testDefaultScopeIsBuiltIn`
- `testEveryBodyRecordKeyRoundTripsInTheWideScope`
- `testEveryBodyRecordDisplayNameRoundTripsInTheWideScope`
- `testEveryAliasOfTheSecondTableResolves` — one assertion per row of §7.1.
- `testTotalMassAliasResolvesToWeightOnlyInTheWideScope`
- `testLeanMassIsNotAnAlias`
- `testNoSecondTableKeyShadowsAFirstTableKey`
- `testUnitsStayVerbatimInTheWideScope`
- `testWhoopBiomarkerParserStillUsesTheBuiltInScope`

`MarkerUnitTableTests.swift`

- `testLegacyTierIsExactlyTheFiveMarkerSwitcher`
- `testLegacyConversionIsBitIdenticalToMultiplyingByTheOldFactor`
- `testEveryBuiltInKeyHasItsStoredUnitFirst`
- `testUnknownKeyHasNoOptions`
- `testHbA1cPercentToMmolPerMol` and `testHbA1cRoundTripsWithinDisplayPrecision`
- `testEveryExtendedOptionRoundTripsBothWays` — for each option, `fromStored(toStored(x))` within
  1e-9 relative, over a spread of values.
- `testIdentityOptionsReturnTheSameNumber`
- `testPoundsUseDivisionByTheSharedConstant`
- `testNonFiniteInputIsNil`
- `testNormalizedLabelFoldsMicroSignsCaseAndSquares`
- `testStoredValueAcceptsStoredUnitAndExtendedOptionsOnly`
- `testParseEntryAcceptsTheLocaleSeparator`, `testParseEntryRejectsTheOtherSeparator`,
  `testParseEntryRejectsNanInfExponentAndTwoSeparators`, `testParseEntryAcceptsALeadingMinus`,
  `testParseEntryNeverReadsAThousandsGroup`

### 12.2 `Packages/StrandAnalytics/Tests/StrandAnalyticsTests/BodyRecordTests.swift`

Quantize and display

- `testDisplayStringZeroDecimalsRoundsHalfAwayFromZero` (2.5 → "3", −2.5 → "-3")
- `testDisplayStringMatchesFormatForOneToThreeDecimals`
- `testDisplayStringNeverShowsNegativeZero` (−0.04 at one decimal → "0.0")
- `testDisplayStringOfNonFiniteAndHugeIsADash`
- `testQuantizeIsTheNumberDisplayed`
- `testDecimalsAreClampedToZeroThroughSix`

Compare

- `testBothPresentGivesDeltaPercentAndDirection`
- `testOnlyEarlier`, `testOnlyLater`, `testNeither`
- `testNoChangeIsSameWithPositiveZeroDelta`
- `testDeltaIsComputedFromDisplayedValues` (two raw values whose difference rounds differently)
- `testPercentIsNilWhenEarlierIsZeroOrNegative`
- `testNonFiniteReadingIsTreatedAsAbsent`
- `testDifferentDecimalsUseTheLarger`
- `testFixtureScanAToScanBTable` — every row of §13.3.

Derive

- `testRatioFromPrintedTotals`
- `testRatioFromSidesWhenTotalIsAbsent` with `sumOfSides`
- `testPrintedTotalWinsOverSides`
- `testMissingArmsIsNotAvailableNeverZero`
- `testMissingLegsIsNotAvailableNeverInfinity`
- `testZeroLegsIsInvalidNotInfinity`
- `testNegativeOrNonFiniteComponentIsInvalid`
- `testInvalidOutranksMissing`
- `testOneSideAloneIsMissing`
- `testSideDifferenceSignAndMagnitude`, `testEqualSidesGiveZeroNotNegativeZero`
- `testSideDifferenceNeedsBothSides`
- `testFixtureDerivedValuesForScansABAndC`
- `testNoResultIsEverNonFinite` — a generated spread including zeros, negatives, infinities, NaN.

Checks

- `testConsistentFixtureScanHasNoMismatch`
- One test per `BodyScanCheck` case that it fires just beyond its tolerance and is silent at it.
- `testBodyFatPercentAcceptsEitherDenominator`
- `testACheckWithAMissingOperandIsSilent`
- `testMismatchesComeInDeclarationOrder`

### 12.3 `Packages/WhoopStore/Tests/WhoopStoreTests/LabMarkerReplaceTests.swift`

- `testReplaceWithOnlyUpsertsBehavesAsUpsert`
- `testReplaceDeletesAndInsertsInOneCall`
- `testReplaceReprojectsDeletedAndInsertedCells`
- `testReplaceSkipsAnUnknownId`
- `testReplaceRollsBackEverythingWhenAnInsertFails` — an insert that violates the primary key
  leaves every deleted row in place.
- `testReplaceWithEmptyArgumentsDoesNothing`
- `testNoteRowWithNilValueProjectsNothing`
- `testScanWeightRowAndManualWeightRowAtOneInstantAreTwoRows`

### 12.4 App target — `StrandTests/`

`BodyRecordStoreTests.swift`

- `testSaveWritesOneRowPerEnteredFieldWithTheScanSource`
- `testSaveWritesTotalMassAsAWeightRow` and `testSaveWritesBodyFatUnderTheExistingKey`
- `testEmptyFieldsWriteNoRow`
- `testTypedZeroVisceralFatIsStoredAsZero`
- `testOnlyTotalMassIsNothingToSave`
- `testOutOfRangeValueWritesNothing`
- `testFutureDayIsRefused`
- `testInstantIsLocalNoonOrNowWhicheverIsEarlier`
- `testDayIsTheLocalDayInTheGivenZoneAndSurvivesAZoneChange`
- `testNoonExistsAcrossADaylightSavingChange`
- `testSecondScanAtTheSameInstantIsRefused`
- `testEditSameDayKeepsRowIdsAndInstant`
- `testEditRemovingAFieldDeletesItsRow`
- `testEditToAnotherDayMovesEveryRowInOneTransaction`
- `testEditOntoAnOccupiedInstantWritesNothing`
- `testDeleteRemovesEveryRowIncludingTheWeightRow`
- `testImportedScanIsListedAndNotEditable`
- `testScansAreOrderedByInstantNotByEntryOrder`
- `testManualWeighInIsNeverAScan`
- `testRowsUnderAnEarlierStrapIdAreStillListed` (re-points the active id, as ruling R25's test does)
- `testDuplicateRowUnderTwoIdsIsListedOnce`
- `testUnreadableUnitIsCountedAndNeverShownAsANumber`
- `testNoteRoundTripsAndLongNoteIsRefused`
- `testBenchmarkSaveReadAndDelete`, `testCustomBenchmarkKeyHasThePrefix`,
  `testBenchmarkRepsMustBeWhole`

`BodyRecordSingleNumberTests.swift` (the single-resolver assertions)

- `testScanTotalMassIsTheResolverValueWhenItIsTheNewestReading` — with the scorecard flag on, the
  Today tile input, the estimate weight, the scorecard's `currentWeightKg`, the profile mirror and
  the scan's total are one number.
- `testOlderScanDoesNotOverrideANewerWeighIn`
- `testSameDayLaterInstantWins`
- `testDeletingTheScanMovesEverySurfaceBackTogether`
- `testTotalMassIsStoredUnderNoOtherKey`
- `testPoundsEnteredInTheScanEqualTheResolverConversion`
- `testScanChangesNothingOnTodayWhileTheScorecardFlagIsOff`
- `testUnitConstantsEqualTheAppFormatterConstants`

`BodyRecordPresenterTests.swift` — one test per state row of §10.1 to §10.5 and §10.7, named for the
state, each asserting the presentation built from the fixture; plus:

- `testNoStateRendersAMissingValueAsZero`
- `testNoStringContainsAnInterpolatedNilNaNOrInfinity`
- `testEveryDisplayedScanValueEqualsLabBookFormat` — for every body-record key and a spread of
  values that do not round to zero from below.
- `testComparisonAlwaysPutsTheOlderScanFirst`
- `testPercentChangeIsHiddenForPercentAndScoreFields`
- `testDurationParsesSecondsAndMinutesSeconds` and `testDurationRejectsSixtyOrMoreSeconds`

`BodyRecordFlagTests.swift`

- `testBothFlagsDefaultToOff`
- `testScreenIsUnreachableWhileTheFlagIsOff`
- `testCsvScopeFollowsTheFlag`
- `testHistoryTreatsAScanRowAsPlainLabBookWhileTheFlagIsOff`
- `testHistoryMakesAScanRowReadOnlyAndRoutedWhileTheFlagIsOn`

`LabReportUnitsEditorTests.swift` (4B; the editor's draft logic is extracted to a testable type in
`Strand/Data/BodyRecordPresenter.swift` so the view only binds)

- `testFlagOffUsesTheLegacyTierAndPlainDoubleParsing`
- `testFlagOnOffersEveryExtendedOption`
- `testPercentHbA1cStoresMmolPerMolAndAnnotates`
- `testIdentityOptionAnnotatesAndStoresTheSameNumber`
- `testStoredUnitEntryLeavesValueTextNil`
- `testAnnotationKeepsTheTypedDigits`
- `testSaveAndAddAnotherKeepsTheDate`
- `testWeightTypedInPoundsStoresKilograms`

`OneNumberPerVariableTests.swift` (existing, extended)

- `testCoachRollUpLeavesOutScanAndBenchmarkMarkers`
- `testCoachContextIsUnchangedForAStoreWithoutBodyRecordRows`

### 12.5 Source scan — `Tools/test_body_record_single_source.py`

- `test_scan_keys_are_spelled_in_one_app_file` — a `"scan_` or `"bench_` string literal appears in
  the app targets only in `Strand/Data/BodyScanFields.swift`.
- `test_derive_and_compare_have_one_caller` — `BodyScanDerivation.derive(` and
  `BodyRecordComparison.compare(` appear in the app targets only in `BodyRecordPresenter.swift`.
- `test_scan_source_literal_is_not_respelled` — `"body-scan"` appears outside `Packages/` nowhere.
- `test_replace_lab_markers_has_one_app_caller` — `replaceLabMarkers(` only in `BodyRecordStore.swift`.
- `test_allowlist_entries_still_match` — as the stage 1 scan does, so a stale entry fails.

`Tools/test_body_measurement_single_resolver.py` runs unchanged and must stay green: it proves that
no new file reads or writes a `weight` row by a literal key.

### 12.6 Flag-off equivalence

With both flags off: `MarkerCatalog.builtIn`, the built-in CSV scope and the legacy unit tier are
pinned by literals (§12.1); the Health list has no new row; the routes are unreachable; the editor
is unchanged; the weigh-in history treats every source as today; the Coach context is unchanged for
existing data; no row is written. The baseline suite's results are unchanged.

Two things are **not** flag-gated, by design, and are stated here so nobody finds them later:
`MarkerCatalog.definition(for:)` resolves body-record keys, and the Coach roll-up skips them. Neither
can change anything until a body-record row exists, which needs the flag to have been on.

### 12.7 Parity (ruling R43)

No Kotlin is written. The written disposition, to be copied into each pull request:

> Stage 4 changes shared catalogue data and shared import logic on the Swift side only, by the
> owner's decision of 11 November 2026 (no Android device; Android work skipped). The Android rows
> of the gate are waived by flag and reported as waived.

The drift this creates, exactly:

| # | Swift after stage 4 | Kotlin, not updated | Effect on an Android install that opens the same data |
|---|---|---|---|
| P1 | `MarkerCatalog.bodyRecord`, 29 entries | No such list (`MarkerCatalog.kt:64-106`) | A row with one of these keys is listed under its category with a name made from the key and up to three decimals (`LabBookScreen.kt:657`; `android/app/src/main/java/com/noop/ui/LabValueFormat.kt:19`). Nothing is hidden or lost |
| P2 | `MarkerCatalog.builtIn` unchanged | Equal | None |
| P3 | `LabMarkerCategory` unchanged | Equal (`MarkerCatalog.kt:24-36`) | None |
| P4 | `MarkerCatalogScope.withBodyRecord` and its alias table | No scope (`LabMarkerCsvImport.kt:383-417`) | The same CSV imports its scan rows as `custom_<slug>` keys on Android and as catalogue keys on iPhone. The same file imported on both sides produces two histories for one measure |
| P5 | `MarkerUnitTable`, extended tier | Five-marker switcher only (`MarkerEditorScreen.kt:414-433`) | Android cannot enter HbA1c in percent, or any other added unit. Rows written on iPhone hold the stored unit and read correctly |
| P6 | `valueText` annotation on a numeric row | Never written | Android shows the numeric value and ignores the annotation (`LabBookScreen.kt:675`) |
| P7 | `replaceLabMarkers` | No DAO counterpart | Android has no scan entry |
| P8 | `BodyRecord.swift` (compare, derive, checks) | No twin | Android has no comparison |
| P9 | Scan identity by `(source, takenAt)` and source `body-scan` | Unknown to Android | Scan rows appear as separate Lab Book cards |
| P10 | Backup whitelist | Equal | None. No key was added |

What a later Android catch-up needs: the 29 entries appended in the same order with the same five
fields; the scope parameter and the §7.1 table; the unit table with a conversion type that can
express `affine`; a Room transaction equal to `replaceLabMarkers`; twins of the three pure
namespaces. The oracle is ready on the Swift side: `testBodyRecordCatalogueIsPinned` holds the
catalogue literal, `testFixtureScanAToScanBTable` and `testFixtureDerivedValuesForScansABAndC` hold
the expected outputs, and `testEveryAliasOfTheSecondTableResolves` holds the alias pairs. A Kotlin
test pastes each literal and must produce it; the Swift tests already stop Swift drifting from them.

Gate invocation for this stage: `bash Tools/personal/gate.sh --waive android`, with the
parity-oracle row reported as NOT RUN, never as a pass.

### 12.8 Fault injection

For each line, make the change, confirm at least one named test fails, restore. Record the result in
the pull request.

| # | Deliberate break | A test that must fail |
|---|---|---|
| F1 | A missing arms figure treated as zero | `testMissingArmsIsNotAvailableNeverZero` |
| F2 | The zero-legs guard removed | `testZeroLegsIsInvalidNotInfinity` |
| F3 | Sides summed even when a printed total exists | `testPrintedTotalWinsOverSides` |
| F4 | Ratio inverted (legs over arms) | `testFixtureDerivedValuesForScansABAndC` |
| F5 | Delta computed from raw values | `testDeltaIsComputedFromDisplayedValues` |
| F6 | Earlier and later swapped | `testFixtureScanAToScanBTable`, `testComparisonAlwaysPutsTheOlderScanFirst` |
| F7 | Percent computed with a zero earlier value | `testPercentIsNilWhenEarlierIsZeroOrNegative` |
| F8 | Negative zero allowed through | `testNoChangeIsSameWithPositiveZeroDelta` |
| F9 | Scans ordered by row id or entry order | `testScansAreOrderedByInstantNotByEntryOrder` |
| F10 | Total mass written under a new key | `testSaveWritesTotalMassAsAWeightRow`, `testTotalMassIsStoredUnderNoOtherKey` |
| F11 | The provider refresh dropped after a scan write | `testScanTotalMassIsTheResolverValueWhenItIsTheNewestReading` |
| F12 | Pounds converted by multiplication with a rounded factor | `testPoundsEnteredInTheScanEqualTheResolverConversion` |
| F13 | Scan edit done as delete calls followed by an upsert call | `testEditToAnotherDayMovesEveryRowInOneTransaction` (it injects a failure into the write and expects the old scan whole) |
| F14 | `replaceLabMarkers` without a transaction around both halves | `testReplaceRollsBackEverythingWhenAnInsertFails` |
| F15 | The occupied-instant check removed | `testSecondScanAtTheSameInstantIsRefused` |
| F16 | An empty field written as a zero row | `testEmptyFieldsWriteNoRow` |
| F17 | An unreadable unit shown as its raw number | `testUnreadableUnitIsCountedAndNeverShownAsANumber` |
| F18 | A manual weigh-in grouped as a scan | `testManualWeighInIsNeverAScan` |
| F19 | Union read replaced by the active id only | `testRowsUnderAnEarlierStrapIdAreStillListed` |
| F20 | HbA1c treated as a multiplication | `testHbA1cPercentToMmolPerMol` |
| F21 | A legacy factor changed | `testLegacyConversionIsBitIdenticalToMultiplyingByTheOldFactor` |
| F22 | `parseEntry` reads "1,500" as 1.5 | `testParseEntryNeverReadsAThousandsGroup` |
| F23 | `parseEntry` accepts "nan" | `testParseEntryRejectsNanInfExponentAndTwoSeparators` |
| F24 | A body-record entry added to `builtIn` | `testBuiltInListIsUnchanged` |
| F25 | The wide scope made the default | `testDefaultScopeIsBuiltIn`, `testBuiltInScopeOutputIsUnchangedForAFileNamingScanMarkers` |
| F26 | `lean_mass` added as an alias | `testLeanMassIsNotAnAlias` |
| F27 | The extended tier used with the flag off | `testFlagOffUsesTheLegacyTierAndPlainDoubleParsing` |
| F28 | The annotation written for a stored-unit entry | `testStoredUnitEntryLeavesValueTextNil` |
| F29 | Scan markers let into the Coach roll-up | `testCoachRollUpLeavesOutScanAndBenchmarkMarkers` |
| F30 | A view calls `BodyScanDerivation.derive` itself | `test_derive_and_compare_have_one_caller` |
| F31 | A mismatch tolerance made zero | The per-check "silent at its tolerance" test |
| F32 | Body-fat check accepts only fat over total | `testBodyFatPercentAcceptsEitherDenominator` |

### 12.9 Privacy scans

- Stage 4 has no widget payload, no notification text and no export of its own. The scan that
  matters is the Coach context: `testCoachRollUpLeavesOutScanAndBenchmarkMarkers` builds the context
  for a store holding the whole fixture and asserts that no fixture scan value, no scan display name
  and no benchmark name occurs in it.
- A repository scan before each commit of this stage: the diff contains no number that is not in
  §13, and no file under `PersonalData/` is staged.
- The demo harness runs on an in-memory store and its own defaults suite, as `ScorecardDemo` does
  (`StrandiOS/Scorecard/ScorecardDemo.swift:25-28`). Committed screenshots come from it only.

### 12.10 Simulator and rehearsal

Every frame of §10 reproduced from the fixture through `--demo-screen` (`bodyrecord-g1 … g10`,
`scan-h1 … h14`, `scandetail-i1 … i8`, `compare-j1 … j11`, `bench-k1 … k8`, `labunits-l1 … l7`), at
the default and the largest text size, with Reduce Motion on and off; enter, edit, move to another
day, delete and compare exercised by tapping.

Then the private real-data rehearsal (roadmap 0B-7). It answers, privately: which Lab Book rows the
owner already has and in which units; whether any existing `custom_…` row is one of the §5.2
measures under another name (stage 4 re-keys nothing; the owner would re-enter or leave them); and
whether a scan typed as printed from a real report passes every range in §7.7. Nothing from the
rehearsal is committed.

## 13. Fixture

Everything here is invented. "Fixture Person" does not exist; the numbers are round on purpose.
Tests in the pure packages use the zone-free values below; app-target tests that need an instant use
12:00 UTC of the day with the time zone injected as UTC.

### 13.1 Three scans

| Field | Scan A · 2031-02-03 | Scan B · 2031-05-05 | Scan C · 2031-08-04 |
|---|---|---|---|
| Total mass (kg) | 80.0 | 76.0 | 73.0 |
| Fat mass (kg) | 20.0 | 16.5 | 14.0 |
| Lean mass (kg) | 57.2 | 56.7 | 56.2 |
| Bone mineral content (kg) | 2.80 | 2.80 | 2.80 |
| Fat-free mass (kg) | 60.0 | 59.5 | — |
| Body fat (%) | 25.0 | 21.7 | — |
| Visceral fat mass (g) | 750 | 550 | — |
| Visceral fat area (cm²) | — | 60 | — |
| Android fat (%) | 30.0 | 24.0 | — |
| Gynoid fat (%) | 24.0 | 20.0 | — |
| Android to gynoid ratio | 1.25 | 1.20 | — |
| Arms lean, total (kg) | 9.00 | 9.40 | — |
| Left arm (kg) | 4.60 | 4.70 | 4.80 |
| Right arm (kg) | 4.40 | 4.70 | 4.80 |
| Legs lean, total (kg) | 18.00 | 17.60 | 17.50 |
| Left leg (kg) | 9.00 | 8.80 | — |
| Right leg (kg) | 9.00 | 8.80 | — |
| Trunk (kg) | 27.00 | 26.50 | — |
| Bone mineral density (g/cm²) | 1.200 | — | — |
| T-score | 0.5 | — | — |
| Z-score | 0.4 | — | — |
| RMR, laboratory estimate (kcal/day) | 1600 | 1560 | — |
| Note | "Fixture note" | — | — |

A dash is a field that was not entered. Entry order in the out-of-order tests: A, then C, then B.
Each scan is internally consistent: fat, lean and bone add up to the total, fat-free mass is lean
plus bone, and body fat is fat over total.

### 13.2 Expected derived figures

| Scan | Arms to legs | Arms source | Arm side difference | Leg side difference |
|---|---|---|---|---|
| A | 50.0 | printedTotal | 4.3 (left larger) | 0.0 |
| B | 53.4 | printedTotal | 0.0 | 0.0 |
| C | 54.9 | sumOfSides | 0.0 | notAvailable(missingComponent) |

A with its legs total removed and no leg sides: `notAvailable(missingComponent)`. A with legs total
set to 0: `notAvailable(invalidComponent)`.

### 13.3 Expected comparison, scan A to scan B

| Field | Earlier | Later | Change | Percent | Direction |
|---|---|---|---|---|---|
| Total mass | 80.0 | 76.0 | −4.0 | −5.0 | down |
| Fat mass | 20.0 | 16.5 | −3.5 | −17.5 | down |
| Lean mass | 57.2 | 56.7 | −0.5 | −0.9 | down |
| Bone mineral content | 2.80 | 2.80 | 0.00 | 0.0 | same |
| Fat-free mass | 60.0 | 59.5 | −0.5 | −0.8 | down |
| Body fat | 25.0 | 21.7 | −3.3 points | hidden | down |
| Visceral fat mass | 750 | 550 | −200 | −26.7 | down |
| Visceral fat area | — | 60 | onlyLater | — | — |
| Android fat | 30.0 | 24.0 | −6.0 points | hidden | down |
| Gynoid fat | 24.0 | 20.0 | −4.0 points | hidden | down |
| Android to gynoid ratio | 1.25 | 1.20 | −0.05 | −4.0 | down |
| Arms lean, total | 9.00 | 9.40 | 0.40 | 4.4 | up |
| Left arm | 4.60 | 4.70 | 0.10 | 2.2 | up |
| Right arm | 4.40 | 4.70 | 0.30 | 6.8 | up |
| Legs lean, total | 18.00 | 17.60 | −0.40 | −2.2 | down |
| Left leg | 9.00 | 8.80 | −0.20 | −2.2 | down |
| Right leg | 9.00 | 8.80 | −0.20 | −2.2 | down |
| Trunk | 27.00 | 26.50 | −0.50 | −1.9 | down |
| Bone mineral density | 1.200 | — | onlyEarlier | — | — |
| T-score, Z-score | 0.5, 0.4 | — | onlyEarlier | — | — |
| RMR, laboratory estimate | 1600 | 1560 | −40 | −2.5 | down |
| Arms to legs (derived) | 50.0 | 53.4 | 3.4 points | hidden | up |

"Hidden" means `compare` still returns a percent and the presenter does not show it (§7.7).

These values were worked for this document from §7.3 and §7.4 with a scratch calculation, not
produced by an implementation, which does not exist yet. The Test author recomputes each row before
relying on it; a disagreement is a defect in this table or in §7 and is reported, not worked around.

### 13.4 Variants

| Variant | Change | Expected |
|---|---|---|
| V1 | No scans | G2, J7 |
| V2 | Scan A only | G3, J6 |
| V3 | Scan B with fat-free mass typed 95.5 | `mismatches` contains `fatFreeIsLeanBone`; Save stays enabled |
| V4 | Scan B with body fat typed 22.5 (fat over fat plus lean) | No mismatch |
| V5 | Scan B with body fat typed 24.0 | `bodyFatPercentIsFatShare` |
| V6 | Scan A's total typed in pounds as 176.4 | Stored `176.4 / 2.20462` kg; shown as 80.0 kg |
| V7 | A manual weigh-in of 80.4 kg at 07:00 UTC on scan A's day | Two weight rows on that day; the resolver's value for that day is 80.0 (the later instant); deleting scan A makes it 80.4 |
| V8 | A manual weigh-in of 79.0 kg on 2031-02-10 | The resolver's current value is 79.0; scan A's total stays 80.0 inside the scan |
| V9 | Scan A's fat-mass row rewritten with unit `stone` | Fat mass is unreadable in A: G5, I5; the comparison row is `onlyLater` |
| V10 | The same scan rows imported by CSV in the wide scope | A scan with source `lab-csv`, read-only (G6, I6) |
| V11 | The CSV of V10 imported in the built-in scope | No scan: rows have `custom_…` keys |
| V12 | Scan B moved to 2031-02-03 | Refused: `instantOccupied`; scan B is unchanged |
| V13 | The active strap id re-pointed after scan A | Scan A is still listed |

### 13.5 Benchmarks and blood results

| Benchmark | Readings |
|---|---|
| `bench_dead_hang_s` | 20 s on 2031-01-06; 30 s on 2031-02-17; 45 s on 2031-03-31, note "Fixture bar" |
| `bench_pushup_reps` | 10 on 2031-01-06; 14 on 2031-02-17 |
| `custom_bench_fixture_carry` | One reading, 60 s on 2031-01-06 |

Dead hang: change since the previous reading +15 s; since the first +25 s.

| Marker | Typed | Stored | Shown | Annotation |
|---|---|---|---|---|
| `hba1c` | 5.5 % | (5.5 − 2.152) ÷ 0.09148 = 36.598… mmol/mol | 37 mmol/mol | `5.5 %` |
| `ldl` | 100 mg/dL | 100 × (1 ÷ 38.67) = 2.5859… mmol/L | 2.59 mmol/L | `100 mg/dL` |
| `hdl` | 50 mg/dL | 1.2929… mmol/L | 1.29 mmol/L | `50 mg/dL` |
| `total_cholesterol` | 200 mg/dL | 5.1719… mmol/L | 5.17 mmol/L | `200 mg/dL` |
| `triglycerides` | 150 mg/dL | 1.6935… mmol/L | 1.69 mmol/L | `150 mg/dL` |
| `fasting_glucose` | 90 mg/dL | 5.0 mmol/L | 5.0 mmol/L | `90 mg/dL` |
| `ferritin` | 80 ng/mL | 80 µg/L | 80 µg/L | `80 ng/mL` |
| `tsh` | 2.00 mIU/L | 2.00 mIU/L | 2.00 mIU/L | none |

## 14. Work packages and file ownership

A package edits only the files listed for it. Tests are written by WP 4-3 before any implementation
package starts, from this document alone.

| WP | Role | Files |
|---|---|---|
| 4-2 | Designer | New `design/round9-body-record/` (`index.html`, `model.js`, `bodyrecord.js`, `bodyrecord.css`, `README.md`). Edited: `design/figma-plugin/code.js`, `design/figma-plugin/manifest.json` (one new command, `import9`, file `r9-frames.json`, page "Round 9 · Body record (Stage 4)"). The round number is a proposal: the orchestrator confirms it against the other stages' rounds |
| 4-3 | Test author | New: `Packages/StrandImport/Tests/StrandImportTests/MarkerCatalogBodyRecordTests.swift`, `LabMarkerCsvBodyRecordScopeTests.swift`, `MarkerUnitTableTests.swift`; `Packages/StrandAnalytics/Tests/StrandAnalyticsTests/BodyRecordTests.swift`, `BodyRecordFixture.swift`; `Packages/WhoopStore/Tests/WhoopStoreTests/LabMarkerReplaceTests.swift`; `StrandTests/BodyRecordStoreTests.swift`, `BodyRecordSingleNumberTests.swift`, `BodyRecordPresenterTests.swift`, `BodyRecordFlagTests.swift`, `LabReportUnitsEditorTests.swift`; `Tools/test_body_record_single_source.py`. Edited: `StrandTests/OneNumberPerVariableTests.swift` (two added tests) |
| 4-4a | Implementer A1 | `Packages/StrandImport/Sources/StrandImport/MarkerCatalog.swift`, `LabMarkerCsvImport.swift`; new `MarkerUnitTable.swift` |
| 4-4b | Implementer A2 | New `Packages/StrandAnalytics/Sources/StrandAnalytics/BodyRecord.swift` |
| 4-4c | Implementer A3 | `Packages/WhoopStore/Sources/WhoopStore/LabMarkerStore.swift` |
| 4-5 | Implementer B, after 4-4a, b, c | New: `Strand/Data/BodyRecordSettings.swift`, `LabBookUnion.swift`, `BodyScanFields.swift`, `BodyRecordStore.swift`, `BodyRecordModel.swift`, `BodyRecordPresenter.swift`. Edited: `Strand/Data/CutScorecardPresenter.swift` (the history caption and the read-only rule, behind a defaulted parameter), `Strand/AI/AICoach.swift` (the roll-up skip, one line) |
| 4-6 | Implementer C, after G1 and 4-5 | New: `StrandiOS/BodyRecord/BodyRecordView.swift`, `BodyScanSheet.swift`, `BodyScanDetailView.swift`, `BodyScanCompareView.swift`, `BenchmarkDetailView.swift`, `BenchmarkSheet.swift`, `BodyRecordKit.swift`, `BodyRecordDemo.swift`. Edited: `StrandiOS/Redesign/RedesignRoute.swift`, `StrandiOS/Redesign/RedesignHealthView.swift` (one row), `StrandiOS/Scorecard/WeighInHistoryView.swift` (the scan row's tap), `Strand/Screens/SettingsView.swift` (the card), `Strand/Screens/LabBookView.swift` (the CSV scope argument), `StrandiOS/App/StrandiOSApp.swift` (one line: the demo fall-through becomes `ScorecardDemo.screen(named:) ?? BodyRecordDemo.screen(named:)`) |
| 4-7 | Implementer D (4B), after 4-4a | `Strand/Screens/MarkerEditorView.swift`; `Strand/Screens/LabBookView.swift` (the "Entered as" line in `historyRow`); the editor draft type in `Strand/Data/BodyRecordPresenter.swift` |
| 4-8 | Localiser, once, after the strings are final | `Strand/Resources/Localizable.xcstrings` |
| 4-9 | Reviewers (correctness, contract, data safety) and Verifier | Evidence only |

**Shared hotspots this stage edits**, each with one writer at a time across all stages:

| File | Stage 4 writer | Collides with |
|---|---|---|
| `Strand/Resources/Localizable.xcstrings` | 4-8 | Every stage |
| `Packages/StrandImport/.../MarkerCatalog.swift` | 4-4a | Any stage that adds a marker |
| `Strand/Screens/SettingsView.swift` | 4-6 | Every stage that adds a flag row |
| `StrandiOS/App/StrandiOSApp.swift` (debug block) | 4-6 | Every stage with a demo |
| `StrandiOS/Redesign/RedesignRoute.swift`, `RedesignHealthView.swift` | 4-6 | Stages that add a screen or a Health row |
| `Strand/AI/AICoach.swift` | 4-5 | Stage 2, which extracts the shared formatter from this file |
| `Strand/Data/CutScorecardPresenter.swift`, `StrandiOS/Scorecard/WeighInHistoryView.swift` | 4-5, 4-6 | Stage 1 follow-ups; stage 5's annotations |
| `Strand/Screens/LabBookView.swift`, `MarkerEditorView.swift`, `Packages/WhoopStore/.../LabMarkerStore.swift` | 4-6 then 4-7; 4-4c | The "Lab Book ownership" change (ruling R42) |
| `design/figma-plugin/code.js`, `manifest.json` | 4-2 | Every stage's design round |

**Not edited by this stage:** `Strand/Screens/DashboardCards.swift`, `Strand/Data/TodayCardReadout.swift`,
the three Today views, `project.yml`, `Packages/WhoopStore/.../Database.swift`,
`Packages/WhoopStore/.../BackupSettings.swift`, `Strand/Data/BodyMeasurementResolver.swift`,
`Strand/Data/BodyMeasurementProvider.swift`, `Strand/Data/WeighInStore.swift`, anything under
`android/`.

`project.yml` needs no change: `Strand` and `StrandiOS` are included by directory
(`project.yml:88`, `:221`, `:240`). Run `xcodegen generate` after adding files.

**Parallel and serial.**

- Inside the stage: 4-2, 4-3 and the three 4-4 packages can run together (different files, no
  layout dependency). 4-5 follows the 4-4 packages. 4-6 follows G1 and 4-5. 4-7 needs only 4-4a and
  can run beside 4-5; it and 4-6 both edit `LabBookView.swift`, in different functions, so 4-6
  merges first and 4-7 rebases. 4-8 is last.
- Against other stages: the three pure packages and every new file can be built while any other
  stage is in progress. The hotspot edits above are one-line or one-function changes and are applied
  at merge time in a fixed order agreed by the orchestrator; the `AICoach.swift` line waits for
  stage 2's extraction to merge, or is handed to stage 2 to carry.
- Pull requests, were they opened (the owner has ruled this work local): "fix: laboratory unit
  entry" (4-4a's unit table, 4-7) first, then "feat: body-composition and benchmark markers".
  Each is behind its own flag.

Parity governance: new public declarations under `Packages/` carry the doc line of §6.3. Whether the
parity ledger accepts a Swift-only declaration without a twin claim is the open item of roadmap 0B-9
and is not attempted here.

## 15. Open questions for the owner

Work proceeds on each recommendation.

**Blocking device acceptance, not the build**

| # | Item | Recommendation |
|---|---|---|
| B1 | Ruling R42 ("Lab Book ownership") is not built on this branch. Until it is, a strap "Delete data" deletes scans, benchmarks and blood results stored under that strap id (`DeviceRegistryStore.swift:162-173`), and Lab Book lists only the active id's rows | Build and merge "Lab Book ownership" before stage 4 reaches G8. Stage 4's own screens already read across strap ids |

**Decisions**

| # | Question | Recommendation, in force until overruled |
|---|---|---|
| O1 | Is a scan's total mass the weight for that day everywhere in the app? | Yes. It is stored once, as a `weight` reading, and the resolver treats it like any other (§8) |
| O2 | May a scan's total mass be the weekly point the scorecard judges, although it comes from another instrument than the bathroom scale? | Yes. Excluding it would give the scorecard a different current weight from the rest of the app on a scan day. The history shows which reading represents the week. The alternative is a rule that a `manual` reading in the same week outranks a scan, which needs a resolver change and a new ruling |
| O3 | On a day with both a morning weigh-in and a scan, which is the day's weight? | The later instant, as for any two readings. A scan is stamped at local noon, so it wins over a morning weigh-in and loses to an evening one |
| O4 | Scan markers appear in Lab Book under "Imaging" and benchmarks under "Custom". Acceptable? | Yes. A new category would hide the rows from any older build (D3) |
| O5 | Should the in-app Coach see scan and benchmark values when "share Lab Book" is on? | No, not in this stage. Stage 2's packet decides what the coach receives from a scan |
| O6 | Should the comparison be computed from the figures as displayed, or from the stored values? | As displayed, so it matches a hand calculation from the screen |
| O7 | Should figures that do not add up block saving? | No. One neutral line; the report is the authority |
| O8 | Should the laboratory's resting-metabolic-rate estimate be used by the app's calorie figures? | No. It is shown in the scan and nowhere else |
| O9 | Should Lab Book show a blood result in the unit it was typed in, with the stored unit second? | Stored unit first, "Entered as" second. Making the typed unit primary is a display preference that can follow |
| O10 | Should the stricter number parsing of 4B (no `nan`, the device's decimal separator) apply even with its flag off? | Not yet: flag-off behaviour stays identical. Make it unconditional when 4B is accepted |
| O11 | Is the benchmark list of §5.3 right, with custom benchmarks for anything else? | Yes |
| O12 | Should the Lab Book editor's new kg and lb, cm and in options for weight, waist and height ship with 4B? | Yes. Without them a weight typed in pounds in Lab Book is stored as kilograms (stage 1 specification, C3) and reaches the resolver |
| O13 | Two flags, or one? | Two, so the blood-panel fix can be accepted before the scan screens |
| O14 | Design round folder `design/round9-body-record` and plugin command `import9` | As proposed, unless another stage has taken the number |

## 16. What needs the owner's go-ahead

| Kind | Needed by 4A or 4B? |
|---|---|
| Database migration | **No.** One store function is added; the schema is untouched |
| Apple Health read or write | **No** |
| New build target, extension or entitlement | **No** |
| Network path | **No** |
| Backup whitelist key | **No** |
| Signing, bundle id, App Group | **No** |
| Installing on the phone | Yes, as always, asked at G8, after a fresh backup and after B1 |
| Switching either flag on by default | Yes, at acceptance |
| 4C | Yes, in full: see §17 |

## 17. 4C — photo timeline (outline only, OUT OF SCOPE)

Not designed, not planned for build. It starts only when the owner answers question Q5 with a yes,
and then with its own specification, design gate and pull request.

What that specification would have to settle:

- **Storage.** Image files in the app's container, never in the database, never in the App Group
  container, with a small index. Whether the index is a table (a migration: needs the owner's
  go-ahead) or a file beside the images (no migration: the alternative that avoids it).
- **Capture and import.** Camera and photo-library access each need a usage description in
  `Info.plist` and the owner's go-ahead. The alternative that avoids both permissions is the system
  photo picker, which needs neither.
- **Lock.** Device authentication before any image is drawn (a Face ID usage description; needs the
  owner's go-ahead). App-switcher snapshots must not show an image.
- **Leak paths to close.** No widget, no notification, no Coach context, no coach packet, no local
  export, no thumbnail cache outside the container.
- **Backup.** Excluded from `.noopbak`, which is a cross-platform contract and is unencrypted; a
  separate export the owner triggers. Whether images are excluded from the device's own iCloud
  backup is the owner's choice.
- **Deletion.** Removes the file and its index entry, verified by a test that looks at the disk.
- **Comparison.** Two photos side by side by date, with the scan of the nearest date named, and no
  judgement.

## 18. Not determined

- **The conversion factors of §7.2 beyond the five legacy ones** were written from standard
  published values and were not checked against an independent reference in this session. The Test
  author verifies each against one before G2; a wrong factor is a defect in §7.2.
- **The exact strings `String(format:)` produces on exact binary ties** (for example 0.25 at one
  decimal) were reasoned, not run. §6.3 defines `displayString` as whatever that call returns, so
  the definition is exact; the pinned expectations in the tests are confirmed by running them.
- **Whether the owner's Lab Book already holds scan-like rows** under `custom_…` keys, or `weight`
  rows in pounds. The rehearsal of §12.10 shows it. Stage 4 re-keys nothing.
- **Whether a real report's every figure falls inside the ranges of §7.7.** The ranges were set
  wide by judgement. The rehearsal checks one real report privately; a refusal there is a defect in
  §7.7.
- **How the weekly reminder counts a scan's total mass.** `WeighInReminder` reconciles against the
  latest weigh-in day (`Strand/Screens/SettingsView.swift:1983`); whether a non-manual `weight` row
  counts as that day was not traced.
- **Local export.** `Packages/NoopLocalAccess/Sources/NoopLocalAccessCore/LocalAccessCore.swift:471-473`
  lists series keys for the strap, computed and Apple Health ids. Whether any path there reaches the
  `lab-book` projection was not traced to the end.
- **The parity ledger.** Whether `Tools/parity_ledger.py` inventories `Packages/StrandImport` and how
  it treats a Swift-only declaration was not run. See §14.
- **Android.** Nothing on the Kotlin side was compiled or run. The Android behaviours in §12.7 are
  read from the cited lines only.
- **The row values in §13.2 and §13.3** come from a scratch calculation, as stated there.
- **The design round number** (§14, WP 4-2) depends on what the other stages take.
- **Whether a scan from a method other than whole-body X-ray** (for example bioimpedance) prints
  measures this list lacks. The catalogue is not a gate: any further figure can be a custom marker.

## 19. Design approval record (G1)

Not yet submitted. Frames G1 to G10, H1 to H14, I1 to I8, J1 to J11, K1 to K8 and L1 to L7 are to be
built in `design/round9-body-record/` from the §13 fixture, imported to Figma by the local plugin,
and approved by the owner before WP 4-6 and WP 4-7 write any view code. The pure packages, the store
function, the tests and `Strand/Data/` logic do not wait for it.
