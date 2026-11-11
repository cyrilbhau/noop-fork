# Stage 4 specification — body record

Gate G0 for stage 4 of the health super-app workstream. Read [CONTEXT.md](../CONTEXT.md),
[ROADMAP.md](../ROADMAP.md) (stage 4), [QUALITY-GATES.md](../QUALITY-GATES.md) and the stage 1
specification ([stage-1.md](stage-1.md), especially §8, §9, §14 and rulings R25 to R43) first.

Verified against the source at commit `0b89b814` (branch `personal/superapp-4-body-record-spec`, cut
from the stage 1 branch `personal/superapp-1-screens`). Every `path:line` below is as of that commit.
Paths are relative to the repository root. Nothing was built or run for this document; it is a
reading of the code.

Reconciled on 11 November 2026 with the cross-stage check (§20). Two things follow from it and
colour the whole document. First, the "Lab Book ownership" change
([labbook-ownership.md](labbook-ownership.md)) lands **before** this stage, so stage 4 is written
against its read path `LabBookRows` and its owner-scope writes; where a row of §2 describes the
source at `0b89b814`, the text says what ownership changes. Second, the orchestrator's shared
scaffolding commit (step 0 of the build order) exists before any stage 4 code: the demo registry,
the plugin command `importS4`, `ObservableDefaultsFlag`, `CanonicalDay`.

This file contains no personal measurement, target, date, medication or injury detail. Every number
in an example belongs to the synthetic "Fixture Person" of §13, who is the Fixture Person of the
stage 1 specification §13.

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
- One resolver rule: in a week that holds both a manual weigh-in and a scan, the weigh-in is the
  week's weight (§8.4).
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
- Android. By ruling R43 of the stage 1 specification Android work is skipped: nothing under
  `android/` is written, edited, compiled or run. §12.7 records the disposition and the drift.
- A coach-packet section for scans or benchmarks. Stage 2's packet has none, and none is added
  until the owner asks.
- A height from a scan report. Height has one home, `profile.heightCm`
  (`Strand/Data/Profile.swift:24`), and a scan entry does not ask for it.
- The "Lab Book ownership" change of ruling R42. It is a separate specification that lands first
  (§15, B1). Stage 4 is built on it and does not contain it.

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
| 11 | Lab Book reads rows of the active strap id only | Confirmed at `0b89b814`. The union across strap ids of ruling R25 exists only for `weight` and `waist`. **Changed before this stage by Lab Book ownership:** every reader goes through `LabBookRows`, which reads every device id present in the table | `LabBookView.swift:469-479`; `Strand/Data/BodyMeasurementProvider.swift:225-250`; ownership specification §6.2 |
| 12 | Stage 1's resolver admits any Lab Book `weight` row whatever its `source`, in kg, lb or lbs | Confirmed | `Strand/Data/BodyMeasurementResolver.swift:116-126`, `:150-161` |
| 13 | A strap's "Delete data" clears `labMarker` | Confirmed at `0b89b814`. **Changed before this stage by Lab Book ownership:** a strap delete and an adoption no longer touch `labMarker` | `Packages/WhoopStore/Sources/WhoopStore/DeviceRegistryStore.swift:162-173`; ownership specification §7.4 |
| 14 | The in-app Coach context includes a Lab Book roll-up | Confirmed. It is opt-in, and it prints the latest reading of the first eight markers in an order that depends on dictionary iteration within each category | `Strand/AI/AICoach.swift:293`, `:1283-1302` |
| 15 | The design pipeline exists | Confirmed: `design/round6-scorecard/`, `design/tools/serve.py`, and the plugin's per-round commands `import` and `import6`. The scaffolding commit adds the command `importS4` for this stage | `design/figma-plugin/manifest.json` (menu); `design/figma-plugin/code.js:52-57` |
| 16 | The debug demo harness and the local gate script exist | Confirmed. At `0b89b814` unknown demo names fall through to `ScorecardDemo.screen(named:)`; the scaffolding commit replaces that line with an ordered list of demo providers. The gate picks up every `Tools/test_*.py` | `StrandiOS/App/StrandiOSApp.swift:621-623`; `StrandiOS/Scorecard/ScorecardDemo.swift:33`; `Tools/personal/gate.sh:385` |

## 3. Corrections to the planning documents

| # | Document says | The code says | Consequence for this stage |
|---|---|---|---|
| D1 | ROADMAP 4A: "New catalogue entries for body-composition scans: total, fat and lean mass …" | Total mass is a body weight and the catalogue already has `weight`; a scan's body-fat percentage is the existing `body_fat` (`MarkerCatalog.swift:111-112`). A new `scan_total_mass` key would be a second store for the weight the resolver already serves | Total mass and body-fat percentage get **no** new entry. They are written under the existing keys with the scan's source (§8) |
| D2 | ROADMAP 4A: "The catalogue is a parity contract: the Swift file and `MarkerCatalog.kt` change together, and the CSV import alias tables on both platforms stay aligned"; test plan: "Catalogue parity … by a generated oracle" and "round-trips on both platforms" | Superseded by ruling R43 (stage 1 specification §18) | No Kotlin edit. `MarkerCatalog.builtIn` and the built-in alias table stay byte-identical to their Kotlin twins; the additions live in a separate list and a separate scope, so the drift is exactly "one list and one scope the Kotlin side lacks" (§12.7) |
| D3 | ROADMAP 4A: "No migration: `labMarker.category` and `markerKey` are text" | True, but a row whose category is outside the enum is never listed: both platforms load Lab Book category by category over the enum's cases (`LabBookView.swift:473-476`; `android/app/src/main/java/com/noop/ui/LabBookScreen.kt:120-123`) | No new category. Scan markers use the existing `imaging`; benchmarks use the existing `other`. An older build and Android both keep listing every row |
| D4 | CONTEXT §4: Lab Book has "an editor with a unit switcher for dual-unit markers (lipids and glucose, mmol/L and mg/dL)" and HbA1c is "not verified" | Row 5 of §2: HbA1c has no percent entry. The conversion mechanism is multiplicative only (`MarkerEditorView.swift:503-512`), and percent to mmol/mol is not a multiplication | 4B replaces the factor table with a conversion table that can express an offset (§7.2) |
| D5 | ROADMAP 4B: "No new screen. The deliverable is that the owner can type a report as printed" | The editor saves one marker and dismisses (`MarkerEditorView.swift:449-457`). A panel of ten markers is ten presentations, each starting at the marker search with the date reset to now (`:44`) | "Save and add another" is added to the existing sheet. It keeps the date and returns to the marker list (§10.6) |
| D6 | ROADMAP test plan: "entry in the report's unit stores the canonical unit and displays both" | The typed unit is discarded at save (`MarkerEditorView.swift:420-422`) and `labMarker` has no column for it | The typed value and unit are kept in the row's existing `valueText` column, which "may also annotate a numeric" reading (`LabMarker.swift:49-51`). No migration (§9.3) |
| D7 | ROADMAP 4A treats a scan as catalogue entries plus a view | A scan is many rows that must appear, move and disappear together, and the store has no multi-row transaction that includes a delete (§2 row 6); ownership adds none either | One store function is added, `replaceLabMarkers(deleteIds:upsert:)`, written on top of the ownership functions. It is an API addition in `WhoopStore`, not a migration (§9.2) |
| D8 | ROADMAP 4A lists "bone density scores" among the scan entries without qualification | A whole-body composition report prints them only when the laboratory ran that analysis | They are optional fields like every other field; a scan without them is complete |
| D9 | The Lab Book editor is described as accepting "a number from your own report" | It parses with `Double(_:)` (`MarkerEditorView.swift:445-447`), which accepts `nan` and `inf` and rejects a decimal comma. On a device whose decimal key is a comma, a typed "5,2" leaves Save disabled | 4B parses through one function that accepts the device's decimal separator and rejects everything that is not a finite number (§6.2) |
| D10 | Stage 1 specification §4.1 row for the Coach: "prints the latest Lab Book reading per marker" | The roll-up keeps eight markers chosen by dictionary order (`AICoach.swift:1286-1301`). Twenty new scan markers would displace blood markers at random and would send scan results to the provider | Body-record markers are left out of the roll-up (§4.5). Stage 2's packet has no scan or benchmark section either, and none is added until the owner asks |
| D11 | ORCHESTRATION file ownership: "Marker catalogue (Swift and Kotlin): Parity agent"; "Backup settings whitelist: Parity agent" | By R43 there is no Parity agent. Stage 4 adds no backup whitelist key at all | The catalogue's sole writer in this stage is Implementer A1 (§14). The whitelist is untouched on both platforms |
| D12 | QUALITY-GATES §G1: design folders sit "beside `design/round1`–`round4`" and the server script "may need to be written again" | `design/round6-scorecard/` and `design/tools/serve.py` exist; the plugin needs one more command per round (`code.js:52-57`) | The design round for this stage is the folder `design/round-s4-body-record/` with the plugin command `importS4` and the frames file `s4-frames.json`. The orchestrator creates the folder and adds the command in the scaffolding commit; the Designer edits only inside the folder (§14, WP 4-2) |
| D13 | Stage 1 specification cites `LabBookView.swift:571` for the day key and `:475-486` for add and delete | The file has moved since: the day key is at `LabBookView.swift:577`, load at `:469-479`, save and delete at `:481-493` | References in this document use the current lines |
| D14 | Stage 1 specification, ruling R42: Lab Book readings survive a strap removal | Not built at `0b89b814` (§2 row 13). It is specified in [labbook-ownership.md](labbook-ownership.md) and is step 1 of the serialised build order | Stage 4 starts after it merges. Every stage 4 read goes through `LabBookRows` and every stage 4 write uses the owner-scope rules (§9). Stage 4 has no union code of its own |

## 4. Every reader and writer

"Action" is what stage 4 does to the site.

### 4.1 Body weight (a scan's total mass)

Every site in the stage 1 specification §4.1 stands. The sites stage 4 adds or changes:

| Site | What it does | Action |
|---|---|---|
| `Strand/Data/BodyMeasurementResolver.swift:116-126` | Admits every Lab Book `weight` row as a candidate | **Changed in one step (§8.4):** a `weight` row whose source is `body-scan` is left out when its week also holds a usable `manual` weight row. In every other case a scan's total mass is a candidate from the moment it is saved (§8) |
| `Strand/Data/BodyMeasurementProvider.swift:238-250` | Reads `weight` rows; after ownership, one call to `LabBookRows.marker` over every id | Not edited by stage 4 (ownership is its only editor). It is how a scan's total mass is read back |
| `Strand/Data/WeighInStore.swift:196-200` (`readings(_:)`) | The read the weigh-in history uses | Reader of the scan's total mass for the scan screens (§9.1). Not edited by stage 4 |
| `Strand/Data/WeighInStore.swift:35` (`weightRangeKg`) | The accepted weight range | Reused as the range of a scan's total mass. Unchanged |
| New `Strand/Data/BodyRecordStore.swift` | Writes the scan's `weight` row in the same transaction as the scan's other rows, then runs the same finish as a weigh-in (`WeighInStore.swift:204-207`): `repository.refresh()`, then `provider.refresh()`, which mirrors the profile | New writer, inside the funnel's rules (§8.2) |
| `Strand/Data/CutScorecardPresenter.swift:822-890` (`history`) | Lists every weight row; a Lab Book row of any source is editable and deletable; marks the row that represents each week | Changed twice. Always: the week's representative is chosen from `BodyMeasurementResolver.withoutOutrankedScans` (§8.4), so the caption and the resolver cannot disagree. When `noop.bodyRecordEnabled` is on: a row whose source is `body-scan` is captioned as a scan, is not editable or deletable there, and opens its scan (§10.7) |
| `StrandiOS/Scorecard/WeighInHistoryView.swift:152` (`rowView`) | Draws a history row | Changed: a scan row's tap pushes the scan |
| `Strand/Data/CutScorecardInputBuilder.swift` | Builds the weekly series from the resolver's series | Not edited. It inherits §8.4 through the resolver's series: a scan's total mass is its week's point only when that week has no manual weigh-in |
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
| `LabBookView.swift:469-479`, `:481-493` | Load, save, delete. After ownership: `LabBookRows.all`, `upsertOwnerLabMarkers`, `deleteLabMarkerAndCopies` | Unchanged in 4A. Scan rows (category `imaging`) and benchmark rows (category `other`) appear as cards under "Imaging" and "Custom" with their catalogue names |
| `LabBookView.swift:228-311` | CSV import. After ownership it writes through `upsertOwnerLabMarkers` | Changed: passes `scope: .withBodyRecord` while `noop.bodyRecordEnabled` is on. The write call is not touched |
| `LabBookView.swift:522-526` (`LabBookFormat.value`) | Formats a value with the catalogue's decimals | Unchanged. `MarkerCatalog.definition(for:)` now also finds body-record keys, so their rows format with the catalogue's decimals |
| `LabBookView.swift:863-892` (`historyRow`) | One history row | 4B: gains the "Entered as" line (§10.6) |
| `MarkerEditorView.swift:110-116` | The marker picker lists `MarkerCatalog.builtIn` | Unchanged: `builtIn` does not grow, so scan and benchmark markers are entered only through their own sheets |
| `MarkerEditorView.swift:381-397`, `:402-423`, `:445-447` | Unit options, conversion at save, number parsing | 4B: all three go through `MarkerUnitTable` (§7.2), with the legacy tier while the flag is off |
| `LabMarkerStore.swift:112-145`, `:191-202` | Upsert and delete; ownership rewrites `reprojectCells` to project over every id | Not edited by stage 4 beyond one addition: `replaceLabMarkers` is added after ownership's change has merged, and uses its projection (§9.2) |
| `Strand/Data/DataBackup.swift:14-24` | The backup is the SQLite file | Unchanged. Scan and benchmark rows travel in it as rows |
| `DeviceRegistryStore.swift:162-173` | Strap "Delete data"; after ownership it leaves `labMarker` alone | Not changed by stage 4. See D14 |

### 4.5 Places where Lab Book values leave the screen they were typed on

| Site | What leaves | Action |
|---|---|---|
| `Strand/AI/AICoach.swift:1283-1302` | With "Also share my patterns & Lab Book" on, the latest value of up to eight markers goes to the Coach provider. After ownership the rows come from `LabBookRows.category` | Changed by one line, written after ownership's read change and after stage 2's extraction have both merged: a key for which `MarkerCatalog.isScanOnlyMarker` or `MarkerCatalog.isBenchmark` is true is skipped. No such row exists before stage 4, so the text for existing data is unchanged |
| Stage 2's coach packet | Version 1 carries weight and waist only | No scan or benchmark section. None is added until the owner asks; it would then be its own change with its own version bump |
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
| Read path for every Lab Book row | `LabBookRows` (owned by Lab Book ownership, §6.2 of its specification) | `Strand/Data/LabBookRows.swift`. Stage 4 calls it and does not edit it. There is no `LabBookUnion` |
| Weigh-in outranks scan | `BodyMeasurementResolver.withoutOutrankedScans(_:)`, `BodyMeasurementResolver.weighInSource` | `Strand/Data/BodyMeasurementResolver.swift` |
| Field table | `BodyScanField`, `BodyScanSection`, `BodyScanEntryUnit` | New `Strand/Data/BodyScanFields.swift` |
| Read and write funnel | `BodyRecordStore`, `BodyScan`, `BodyScanDraft`, `BodyRecordError` | New `Strand/Data/BodyRecordStore.swift` |
| Settings and flags | `BodyRecordSettings`, with the two static instances `BodyRecordSettings.enabledFlag` and `BodyRecordSettings.labReportUnitsFlag` of the shared `ObservableDefaultsFlag` | New `Strand/Data/BodyRecordSettings.swift`. There is no `BodyRecordFlags` type |
| Model and presenter | `BodyRecordModel`, `BodyScanSheetModel`, `BenchmarkSheetModel`, `BodyRecordPresenter` | New `Strand/Data/BodyRecordModel.swift`, `Strand/Data/BodyRecordPresenter.swift` |
| Screens | `BodyRecordView`, `BodyScanSheet`, `BodyScanDetailView`, `BodyScanCompareView`, `BenchmarkDetailView`, `BenchmarkSheet`, `BodyRecordKit` | New folder `StrandiOS/BodyRecord/` |
| Demo harness | `BodyRecordDemo`, with `static func screen(named: String) -> AnyView?` | New `StrandiOS/BodyRecord/BodyRecordDemo.swift`, plus one element in the scaffolding's demo-provider list |
| Design round | `design/round-s4-body-record/`, plugin command `importS4`, frames file `s4-frames.json` | Folder and command created by the scaffolding commit |
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

Every field is optional (§7.7). A scan with any subset of them is complete.

### 5.3 Benchmark markers

Appended to `MarkerCatalog.bodyRecord` after the scan markers. Category `other` (D3). The list is a
general set of common bodyweight and grip tests; anything else is a custom benchmark.

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

The rows a scan is built from are the **merged** rows `LabBookRows` returns: every device id present
in the table is read, registered or not, and only content-equal copies are collapsed (ownership
specification §7.1). Stage 4 adds no merge rule of its own.

A **scan** is every merged Lab Book row that shares one `source` and one `takenAt`, provided at
least one of those rows has a scan-only key (§6.1). Its members are:

- every merged row of that `(source, takenAt)` whose key is scan-only, and
- every merged `weight` row and `body_fat` row of that `(source, takenAt)`.

Consequences, all intended:

- A scan needs no table, no id column and no settings key. Its identity is
  `"<source>\u{1F}<takenAt>"`.
- A scan typed in the sheet has source `body-scan`. A scan imported from a markers CSV has source
  `lab-csv` and `takenAt` at noon UTC of its day (`LabBookView.swift:596-599`); it is shown as a
  scan and is read-only in the body record.
- A `weight` row with no scan-only row at its `(source, takenAt)` is not a scan. A manual weigh-in
  never becomes one.
- **Copies.** Rows stored under two device ids that are equal in every column except `id`,
  `deviceId` and `day` are one reading. `LabBookRows` lists it once, represented by the active id's
  row when there is one. The scan has one member for that key.
- **Conflicts.** Two rows with one `(markerKey, takenAt, source)` that are not copies are two
  readings, and `LabBookRows` lists both. The scan then has two or more members for that key. The
  key is **conflicting**: it is counted and named, it is never shown as a number, it takes no part
  in a comparison or a derived figure, and nothing is hidden: both rows stay listed in Lab Book,
  where the owner deletes the one that is wrong. A scan with a conflicting key is not editable in
  the body record until then. It can still be deleted, and the delete removes every member.

Scans are ordered by `takenAt` ascending, then by `source`. The order in which they were typed in
plays no part. "The latest scan" is the last of that order; "the previous scan" is the one before.

Reading a member row's value (a key with exactly one member):
`MarkerUnitTable.storedValue(value, key:, rowUnit:)`, then the range of §7.7. A row whose value is
nil, whose unit is not recognised, or whose stored value is outside the range is **unreadable**: it
is counted and named, and it is never shown as a number or as zero. The note row is read from
`valueText` and is never unreadable.

A scan's `day` is the stored `day` of its first member in the field order of §7.7 (for a
conflicting key, the member with the smaller `id`). Rows a scan sheet writes all carry one day, so
this matters only for rows written elsewhere.

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
- A future day is refused. A day key that is not canonical (`CanonicalDay.number(day) == nil`, the
  shared rule of stage 1 ruling R5) is refused as `invalidDay`. Stage 4 writes no day-key rule of
  its own.

A benchmark and a blood reading keep the date-and-time picker they have today.

## 8. Ruling R41: how a scan's total mass joins the resolver

### 8.1 The rule

**A scan's total mass is a Lab Book `weight` row.** Its `markerKey` is `weight`, its `category`
`bodyMeasurement`, its `unit` `kg`, its `source` `body-scan`, its `takenAt` and `day` the scan's. It
is the only place the total is stored. There is no `scan_total_mass` key, no copy in a scan table,
no settings value.

Therefore:

- Under the `unified` policy the resolver already admits every Lab Book `weight` row whatever its
  source (`BodyMeasurementResolver.swift:116-126`). Newest day wins; on one day the greatest
  `takenAt` wins, then the greatest `id` (stage 1 specification §8.2). Stage 4 adds one step in
  front of that, §8.4, and changes nothing else in the resolver.
- The scan screens read the total from that same row, through the weigh-in store's read
  (`WeighInStore.swift:196-200`, which after ownership is `LabBookRows.marker`), picking the row
  whose `(source, takenAt)` is the scan's.
- Today, Settings, the estimates, Health readiness, the scorecard, the weigh-in history and the
  Coach context each show the resolver's value as before. When the scan is the reading the resolver
  chooses, that value is the scan's total mass, and it is the same stored number the scan shows.
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

### 8.4 A manual weigh-in outranks a scan within its week

Decided by default from the cross-stage check (X11), pending the owner (§15, O2 and O3). It is a
change to the resolver's rule, so it needs a new ruling in the stage 1 specification §18; the text
here is that ruling's content.

A scan's total mass comes from another instrument than the bathroom scale, clothed and later in
the day. If it could stand for a week that also has a morning weigh-in, it would move the fitted
rate and could change the verdict. So:

> Within one week, a usable `manual` weight row outranks every `body-scan` weight row of that week,
> for the weekly point and for the current value. In a week with no usable `manual` weight row, a
> `body-scan` row is an ordinary reading.

Exactly:

- **Week** is `CanonicalDay.weekStart(row.day)`, the Monday rule the scorecard uses. A row whose
  `day` is not canonical belongs to no week: it outranks nothing and is not outranked.
- **Manual** is a row whose `source` equals `BodyMeasurementResolver.weighInSource` (`"manual"`,
  what the weigh-in sheet and the Lab Book editor write). **Scan** is a row whose `source` equals
  `MarkerCatalog.scanSource`. Rows of any other source (`lab-csv`, an import) are neither: they are
  not outranked and they outrank nothing.
- **Usable** is `BodyMeasurementResolver.normalizedValue(of: row, as: .weight) != nil`. A manual
  row in an unknown unit does not outrank a scan.
- The rule applies to `weight` rows only. No scan writes a `waist` row.
- It is one stored number still (R41 stands): nothing is copied, changed or deleted. The scan keeps
  showing its own total with its own date, as a dated figure and never as "current".

One function states the rule, in `Strand/Data/BodyMeasurementResolver.swift`:

```swift
extension BodyMeasurementResolver {
    /// The source the weigh-in sheet and the Lab Book editor write.
    static let weighInSource = "manual"

    /// `rows` without every row whose key is `weight`, whose source is `MarkerCatalog.scanSource`
    /// and whose week also holds a usable `weight` row with source `weighInSource`. Order is kept.
    /// Rows of any other key pass through untouched.
    static func withoutOutrankedScans(_ rows: [LabMarkerRow]) -> [LabMarkerRow]
}
```

The scan source is named only through `MarkerCatalog.scanSource`, so the resolver file imports
`StrandImport` and never spells the literal (§12.5). The function has exactly two callers, and a
source scan keeps it that way (§12.5):

1. `BodyMeasurementResolver.series`, `unified` policy, weight kind: the Lab Book fold at `:116-126`
   iterates `withoutOutrankedScans(candidates.labBook)` in place of `candidates.labBook`. `resolve`
   and the scorecard's weekly points are built from `series`, so the current value, the Today tile,
   the estimates' input, the profile mirror and the week's point all follow from one list.
2. `CutScorecardPresenter.history`: the loop that marks each week's representative
   (`CutScorecardPresenter.swift:861-866`) skips an entry whose weight row is not in
   `withoutOutrankedScans(weights)`. The entry is still listed, with "Not the weekly point".

What follows, stated so nobody finds it later:

- A scan on Wednesday and a manual weigh-in on the Monday of the same week: the current weight on
  Wednesday is Monday's weigh-in, although the scan is newer. That is the rule, not a defect.
- A scan in a week with no manual weigh-in is that week's point and, while it is the newest
  reading, the current weight.
- Entering a manual weigh-in later in a scan's week moves the week's point and the current value
  from the scan to the weigh-in at that moment. Deleting the weigh-in moves them back.
- An Apple Health value in the scan's week is not a manual weigh-in. The existing rule stands:
  newest day wins, and on one day Lab Book beats Apple Health.
- The rule is not gated by `noop.bodyRecordEnabled`. A `body-scan` row can exist only if that flag
  was once on, and it keeps being read after the flag goes off. With `noop.cutScorecardEnabled` off
  the legacy policies never read Lab Book, so nothing changes.

The scan sheet tells the owner when this applies (§10.2, H8), and the weigh-in history already
captions which reading represents each week.

## 9. Storage

### 9.1 Rows

Scan rows, written only by `BodyRecordStore`:

| Column | Value |
|---|---|
| `id` | `"<markerKey>-<takenAt>-<8 hex>"`, the form `MarkerEditorView.swift:430` uses |
| `deviceId` | The active strap id (`repo.deviceId`) for every row stage 4 inserts, as Lab Book writes (ruling R25; ownership decision D4). A row that an edit updates in place keeps the id it was stored under |
| `markerKey` | A key of §7.7 |
| `category` | `imaging` for a scan-only key, `bodyMeasurement` for `weight` and `body_fat` |
| `takenAt`, `day` | §7.8, the same for every row of the scan |
| `value` | The stored-unit value, unrounded. Nil for `scan_note` |
| `valueText` | Nil, except `scan_note`: the note text, trimmed |
| `unit` | The stored unit. The empty string for `scan_note` |
| `source` | `body-scan` |
| `note`, `referenceText` | Nil |

Benchmark rows: `category` `other`, `source` `manual`, `unit` the stored unit, `note` the condition
text or nil, written with ownership's `upsertOwnerLabMarkers` and removed with
`deleteLabMarkerAndCopies`, the calls the Lab Book screen itself uses after ownership.

**Reads.** Every read goes through `LabBookRows` (ownership specification §6.2). Stage 4 has no
union code, never passes a device id to a store read, and never calls `labMarkers(deviceId:`,
`allLabMarkers(` or `markerKeysPresent(`: ownership's source scan
(`Tools/test_lab_book_single_read_path.py`) fails on any of them outside its allowlist, and stage 4
adds no file to that allowlist.

| What | Read |
|---|---|
| Scan-only rows and the note | `LabBookRows.category("imaging", store:, activeDeviceId:)`, kept where `MarkerCatalog.isScanOnlyMarker(row.markerKey)` |
| A scan's total mass | `WeighInStore.readings(.weight)` (after ownership, `LabBookRows.marker("weight", …)`). `BodyRecordStore` never names the `weight` key itself |
| A scan's body-fat percentage | `LabBookRows.marker(MarkerCatalog.scanBodyFatKey, store:, activeDeviceId:)` |
| Benchmark rows | `LabBookRows.category("other", store:, activeDeviceId:)`, kept where `MarkerCatalog.isBenchmark(row.markerKey)` |
| Stored, unmerged rows for the write-side checks below | `LabBookRows.stored(marker:store:)`, one call per key |

`BodyRecordStore`:

```swift
struct BodyScan: Equatable, Identifiable {
    let id: String                       // "<source>\u{1F}<takenAt>"
    let source: String
    let takenAt: Int
    let day: String                      // §7.6
    let values: [String: Double]         // key -> stored-unit value; readable, non-conflicting keys only
    let rows: [String: [LabMarkerRow]]   // key -> the merged member rows, ordered by id; two or more = conflicting
    let note: String?                    // nil when there is no note row or the note key is conflicting
    let unreadableKeys: [String]         // sorted; one member, value not readable (§7.6)
    let conflictingKeys: [String]        // sorted; two or more members (§7.6)
    var isEditable: Bool { source == MarkerCatalog.scanSource && conflictingKeys.isEmpty }
    var isDeletable: Bool { source == MarkerCatalog.scanSource }
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
    case invalidDay                      // the draft's day is not a canonical day key
    case futureDay
    case instantOccupied                 // a body-scan row already holds the target instant, under any id
    case scanNotFound
    case notEditable                     // source is not body-scan, or a key is conflicting
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

`scans()` returns every scan of §7.6 in the order of §7.6, whatever its source, and an empty list
when the store cannot be read. It does not consult `noop.bodyRecordEnabled`: a caller outside the
body record checks `BodyRecordSettings.enabledFlag.isEnabled` first. It is the one read other
stages use. Stage 6's `TimelineScanSource` takes its scan days as `scans().map(\.day)`,
de-duplicated; there is no separate `scanDays()` function. A scan imported by CSV is stamped at
noon UTC, so its `day` is the day key its import stored, which can differ from the local day a
typed scan on the same date would carry.

`benchmarkReadings(key:)` returns the merged rows of that key, oldest first, conflicting rows
included as separate readings. `benchmarkKeysPresent()` returns the distinct benchmark keys that
have a row, in catalogue order and then custom keys ascending.

**The stored rows of a scan** are every row, under any device id, whose `source` and `takenAt` are
the scan's and whose key is a key of §7.7: the members, every copy of a member, and nothing else.
They are found with `LabBookRows.stored(marker:store:)` for each key of §7.7.

**Occupancy.** A target instant is occupied when any stored row, under **any** device id, registered
or not, has source `body-scan`, that `takenAt`, and a key of §7.7. The check reads the stored rows,
not the merged ones.

`save`, new scan: validate everything first (the day canonical and not in the future; at least one
scan-only numeric value; every value in its range; the note within its length). Compute `takenAt`
and `day` (§7.8). Refuse with `instantOccupied` if the instant is occupied. Build the rows under
the active id. One `replaceLabMarkers(deleteIds: [], upsert: rows)`. Finish as §8.2. Return the
scan as stored.

`save`, replacing: re-read the scan; `scanNotFound` if no row of it remains; `notEditable` unless
`isEditable`. Then:

- same day: for a key present before and after, the upsert carries a row with the member's `id`,
  `deviceId`, `category`, `takenAt`, `day`, `source`, `note` and `referenceText` and the new
  `value` and `unit`; the owner-scope upsert of §9.2 then updates the member and every copy of it
  in place, each keeping its own `id` and `deviceId`. A key that was removed has its member's id in
  `deleteIds`, which removes the member and every copy. A new key gets a new row under the active
  id.
- another day: the occupancy check runs at the new instant; every member's id goes in `deleteIds`
  and every row is new, under the active id.

Either way it is **one** `replaceLabMarkers` call, so there is no state in which half a scan exists,
and no copy under another id is left behind to bring a deleted figure back.

`delete`: `notEditable` unless `isDeletable`; then one `replaceLabMarkers(deleteIds: ids, upsert:
[])`, `ids` being the id of every member (for a conflicting key, of each of its members), and the
finish of §8.2. Because the store call removes every copy of each id, the result is that no stored
row of the scan remains under any device id, and the scan cannot reappear.

`saveBenchmark` validates the value against §7.7, builds one row under the active id and calls
`upsertOwnerLabMarkers`. `deleteBenchmark` calls `deleteLabMarkerAndCopies(id:)`. Each finishes
with `repository.refresh()`.

### 9.2 The store function

Added to `LabMarkerStore.swift`, beside `upsertLabMarkers`, **after** Lab Book ownership's change to
this file has merged (one writer at a time on this file):

```swift
/// In one transaction: delete the rows with these ids and every copy of each, upsert `rows` by
/// the owner-scope rule, then re-project every touched (markerKey, day) cell over all device ids.
/// An id that is not stored is skipped. Returns the number of stored rows inserted or updated by
/// the upsert. If anything throws, nothing is changed.
@discardableResult
public func replaceLabMarkers(deleteIds: [String], upsert rows: [LabMarkerRow]) async throws -> Int
```

Inside one `syncWrite` (`WhoopStore.swift:171-173`, a single GRDB write transaction), in this
order:

1. **Deletes**, by the rule of `deleteLabMarkerAndCopies(id:)` (ownership specification §7.4). For
   each id: load the row; load every stored row with its `(markerKey, takenAt, source)` under any
   device id; delete those for which `LabMarkerUnion.isCopy` holds with the row, the row itself
   included; remember each deleted row's `(markerKey, day)`. A conflicting row at the same identity
   is not deleted by this id; it is deleted only if its own id is in `deleteIds`.
2. **Upserts**, by the rule of `upsertOwnerLabMarkers(_:)` (same section), evaluated against the
   table as step 1 left it. For each incoming row: find every stored row with the same
   `(markerKey, takenAt, source)` under any device id. With none, insert the row as given.
   Otherwise update each of them in place: `category`, `day`, `value`, `valueText`, `unit`, `note`
   and `referenceText` take the incoming values; `id` and `deviceId` keep the stored ones. Remember
   the `(markerKey, day)` of every row written, and the old day of an updated row.
3. **Projection**: ownership's rewritten `reprojectCells` over the union of the remembered cells.
   It has no device-id filter: a cell's value is the row with the greatest `takenAt`, then the
   greatest `id`, among all rows of that marker and day under any id (ownership specification §7.2).

With both arguments empty it does nothing and returns 0. The implementer shares the per-row delete
and upsert steps with ownership's two functions as private helpers that take the open database
handle, so the rules exist once.

This is a function, not a schema change: no migration, no new table, no new column, no new index.

### 9.3 The "entered as" annotation (4B)

When `noop.labReportUnitsEnabled` is on and a reading is typed in an option other than the stored
unit, the row's `valueText` is set to the typed text and the option's label, separated by one space:
the typed text is trimmed and its decimal separator written as `.`, with nothing else changed, so
"5,50" in percent becomes `5.50 %`. For an `identity` option (another label for the same number)
the annotation is written as well, since the label is what the report printed. When the stored unit
is used, `valueText` stays nil.

`value` and `unit` are the stored-unit value and the stored unit, as today. Every existing reader
takes `value` first and looks at `valueText` only when `value` is nil (`LabBookView.swift:449-453`,
`:894-897`; `AICoach.swift:1294`), so the annotation changes no existing readout.

The annotation is part of what makes two rows copies (`LabMarkerUnion.isCopy` compares
`valueText`). A reading typed as `5.5 %` and the same reading stored elsewhere without the
annotation are therefore two readings at one instant, and both are listed. That is the ownership
rule applied as written; it can arise only from a re-import of an older file.

### 9.4 Settings

All in `UserDefaults.standard`, declared in `BodyRecordSettings`.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `noop.bodyRecordEnabled` | Bool | `false` | 4A. Off: no Health row, no body-record screen or sheet, built-in CSV scope, the weigh-in history as it is today |
| `noop.labReportUnitsEnabled` | Bool | `false` | 4B. Off: the legacy unit tier, `Double(_:)` parsing, no annotation, no "Save and add another" |

Each flag is observed through one instance of the shared `ObservableDefaultsFlag` (scaffolding
commit, `Strand/Data/ObservableDefaultsFlag.swift`), held as a static on the settings type:

```swift
enum BodyRecordSettings {
    static let enabledKey = "noop.bodyRecordEnabled"
    static let labReportUnitsKey = "noop.labReportUnitsEnabled"
    @MainActor static let enabledFlag = ObservableDefaultsFlag(key: enabledKey)
    @MainActor static let labReportUnitsFlag = ObservableDefaultsFlag(key: labReportUnitsKey)
}
```

`ObservableDefaultsFlag` is the body of `CutScorecardFlag`
(`Strand/Data/CutScorecardModel.swift:18-63`) with the key as a parameter: an `ObservableObject`
with `init(key: String, defaults: UserDefaults = .standard)`, a published read-only `isEnabled`
that is false when the key is absent and follows every write to the key, and `set(_ enabled: Bool)`.
Reading it never writes. Stage 4 declares no flag class of its own; tests build their own instance
over a private defaults suite.

### 9.5 Backup whitelist

**No change.** `BackupSettings.swift` is not edited and stage 4 adds no line to its comment block of
fork-only keys. Both keys are `noop.*` toggles, which are per install by the
whitelist's own rule (`Packages/WhoopStore/Sources/WhoopStore/BackupSettings.swift:40-42`), and a
Bool cannot cross. Stage 4 stores nothing else in settings. After a restore both features are off
until switched on, and every scan, benchmark and annotated reading is in the database rows.

## 10. Screens and states

Frames are designed at G1 (§14, WP 4-2) in `design/round-s4-body-record/`. The Health tab's "More
health" card, the Settings section and the scorecard screen are designed once for all stages in a
combined frame set that the owner approves once; stage 4's row and card take the place that set
gives them (§10.1, §10.8) and stage 4 draws no frame of its own for those three surfaces.

Every state below needs a frame, at the default text size
and at the largest accessibility size (`StrandiOS/App/StrandiOSApp.swift:247`). No frame draws a
chart, a band, a target line or a colour that judges a value: figures are in the primary text
colour, a change carries a sign and a direction word, and the only semantic colour is red on Delete.

There is **no widget and no notification** in this stage; that list is empty by decision.

### 10.1 Body record screen (`BodyRecordView`, route `.bodyRecord`)

Reached from a row in the Health tab's "More health" card, mounted only while the flag is on, in the
manner of the scorecard row (`StrandiOS/Redesign/RedesignHealthView.swift:474-483`). The card's row
order is fixed across stages: Scorecard, **Body record**, Events, Timeline, Niggle log, Coach
packet. The Body record row sits directly beneath the Scorecard row, or first when the scorecard is
off.

| # | State | Shows |
|---|---|---|
| G1 | Loading | Skeleton |
| G2 | Nothing recorded | "No scans yet" and "No benchmarks yet", each with its add button; a row to Lab Book for blood results |
| G3 | One scan | The scan card (date, the whole-body figures entered, the derived line) and "Add a second scan to compare" |
| G4 | Two or more scans | The latest scan card; "Compare with <date of the previous scan>"; the list of scans, newest first |
| G5 | A scan with unreadable rows | The card, plus "<n> values in this scan could not be read. They remain in Lab Book." |
| G5b | A scan with a conflicting key | The card, plus "<n> figures in this scan have two different stored values. Open Lab Book to delete the one that is wrong." The conflicting figures are not shown as numbers |
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
| H8 | A manual weigh-in already in the chosen day's week | A neutral line: "You have a weigh-in this week. It stays this week's weight; the scan keeps its own total." Shown whenever §8.4 would leave the scan's total out, and only then |
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
| I5b | Conflicting keys | As G5b, naming the fields. No Edit; Delete stays for a typed scan |
| I6 | Imported scan | No Edit, no Delete. "Imported from CSV. Edit or delete its readings in Lab Book." |
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
| J10b | A field unreadable or conflicting in one scan | Treated as not entered in that scan (J2 or J3), with the G5 or G5b line under the table |
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

In both flag states the lead of the caption follows §8.4: a scan row in a week that has a usable
manual weigh-in reads "Not the weekly point", and the weigh-in that outranks it reads "Represents
its week". After ownership the history lists rows under every device id; stage 4 changes nothing
about which rows are listed.

### 10.8 Settings

Two rows in a "Body record" card built as the scorecard card is (`Strand/Screens/SettingsView.swift:1860-1880`),
iPhone only, in this order: "Report units in Lab Book" first, then "Body record" (scans and
benchmarks). The order is the order they are built and accepted in. Both off by default. Switching
either off hides its surfaces and deletes nothing. The card's place among the other stages' cards is
the one the combined Settings frame fixes: after the Coach packet card and the Intake card, before
the Events switches and the "Log and timeline" section.

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
| Weigh-in in the same week | You have a weigh-in this week. It stays this week's weight; the scan keeps its own total. |
| Occupied | Another scan is already recorded at that time. |
| Save failed | Couldn't save the scan. Nothing was changed. |
| Delete scan | Delete this scan? Its total mass is removed from your weight history too. |
| Delete reading | Delete this reading? |
| Imported | Imported from CSV · Imported from CSV. Edit or delete its readings in Lab Book. |
| Unreadable | <n> values in this scan could not be read. They remain in Lab Book. |
| Conflicting | <n> figures in this scan have two different stored values. Open Lab Book to delete the one that is wrong. |
| Not entered | not entered |
| Derived | Arms to legs · <value>% of legs lean mass · Left and right arm · Left and right leg · Left <value>% more · Right <value>% more · Equal · From left and right arm. · From left and right leg. |
| Derived, missing | Not available. Enter arms and legs lean mass. · Not available. Enter both sides. |
| Derived, invalid | Not available. A figure it needs could not be used. |
| Comparison | Earlier · Later · Change · No change · up · down · <value> points |
| One scan | One scan so far. A second scan makes a comparison. |
| Benchmark | Condition (optional) · e.g. surface height or grip · One reading so far. · Since the previous reading · Since the first reading · Custom benchmark |
| History caption | Lab Book · body scan |
| Lab Book editor | Save and add another · Saved <marker name>. · Entered as <typed value and unit> |
| Settings | Report units in Lab Book · Type blood results in the unit your report prints. · Body record · Scans and benchmarks, entered as printed and compared. |
| Screen note | These are your own figures shown back to you. NOOP does not decide whether any value is normal, high or low. |

The last string is the existing Lab Book note (`LabBookView.swift:641`) reused, not a new one.

## 12. Test plan

Every test uses the §13 fixture or values invented beside it. No test reads the real store. Tests
that need rows under several device ids use the device ids and the rules of the ownership fixture
(ownership specification §13): `my-whoop`, `whoop-FIXTURE-OLD` (registered, archived),
`whoop-FIXTURE-GONE` (no registry row), `oura-FIXTURE-RING` (registered, another brand) and
`whoop-FIXTURE-NEW` (registered, active).

### 12.1 `Packages/StrandImport/Tests/StrandImportTests/`

`MarkerCatalogBodyRecordTests.swift`

- `testBuiltInListIsUnchanged` — the 30 keys, names, categories, units and decimals as a literal.
- `testBodyRecordCatalogueIsPinned` — one line per entry, `key|displayName|category|unit|decimals`,
  as a literal. This literal is the written record of the Swift-only list (§12.7).
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

Seeded with the ten rows F1 to F10 of the ownership fixture (ownership specification §13), through
its `LabBookOwnershipFixture.swift`, with their cells projected. Row labels below are that
fixture's.

- `testReplaceWithOnlyUpsertsBehavesAsTheOwnerUpsert` — the same rows through
  `upsertOwnerLabMarkers` on a second store give an identical table and identical cells.
- `testReplaceDeletesAndInsertsInOneCall`
- `testReplaceDeleteRemovesEveryCopyUnderOtherIds` — `deleteIds: [F7.id]` removes F6 and F7 and
  the `ldl` cell of `2031-01-15`.
- `testReplaceDeleteLeavesAConflictingRow` — `deleteIds: [F8.id]` removes F8 only; F3 stays; the
  `weight` cell of `2031-01-22` stays 98.2.
- `testReplaceUpsertUpdatesTheStoredRowUnderAnotherIdInPlace` — an incoming row with F2's
  `(markerKey, takenAt, source)`, device id `whoop-FIXTURE-NEW`, a new `id` and value 99.5: F2 now
  holds 99.5 and keeps its `id` and its device id `whoop-FIXTURE-OLD`; the row count is unchanged;
  the returned count is 1.
- `testReplaceUpsertUpdatesEveryCopy` — an incoming row with the identity of F6 and F7 and value
  3.5: both hold 3.5, each under its own id; the returned count is 2.
- `testReplaceEvaluatesUpsertsAfterDeletes` — `deleteIds: [F7.id]` with an upsert of a row at the
  identity of F6 and F7: exactly one row holds that identity afterwards, the incoming one as given.
- `testReplaceReprojectsAcrossAllDeviceIds` — `deleteIds: [F9.id]`: the `weight` cell of
  `2031-01-22` becomes 98.5 (F8, the greatest `id` of the two rows left at the greatest `takenAt`),
  although F8 and F3 sit under two device ids and neither is F9's.
- `testReplaceReprojectsDeletedAndInsertedCells` — the old day and the new day of a moved row.
- `testReplaceSkipsAnUnknownId`
- `testReplaceRollsBackEverythingWhenAnInsertFails` — an upsert of a row with a new identity whose
  `id` equals F1's violates the primary key; every deleted row is back in place, byte-identical.
- `testReplaceWithEmptyArgumentsDoesNothing`
- `testNoteRowWithNilValueProjectsNothing`
- `testScanWeightRowAndManualWeightRowAtOneInstantAreTwoRows`
- `testReplaceTouchesNoRowOutsideItsArguments` — every row not named is byte-identical afterwards.

### 12.4 App target — `StrandTests/`

`BodyRecordStoreTests.swift` — the active id is `whoop-FIXTURE-NEW` unless the test says otherwise.

Writing

- `testSaveWritesOneRowPerEnteredFieldWithTheScanSource`
- `testSaveWritesTotalMassAsAWeightRow` and `testSaveWritesBodyFatUnderTheExistingKey`
- `testNewRowsAreWrittenUnderTheActiveId`
- `testEmptyFieldsWriteNoRow`
- `testTypedZeroVisceralFatIsStoredAsZero`
- `testOnlyTotalMassIsNothingToSave`
- `testOutOfRangeValueWritesNothing`
- `testFutureDayIsRefused` and `testNonCanonicalDayIsRefusedAsInvalidDay`
- `testInstantIsLocalNoonOrNowWhicheverIsEarlier`
- `testDayIsTheLocalDayInTheGivenZoneAndSurvivesAZoneChange`
- `testNoonExistsAcrossADaylightSavingChange`
- `testSecondScanAtTheSameInstantIsRefused`
- `testOccupancySpansUnregisteredAndOtherBrandIds` — a `body-scan` row at the target instant under
  `whoop-FIXTURE-GONE`, and separately under `oura-FIXTURE-RING`, each refuses the save with
  `instantOccupied` and writes nothing.
- `testEditSameDayKeepsRowIdsAndInstant`
- `testEditSameDayUpdatesCopiesInPlaceUnderTheirOwnIds` — a member copied under
  `whoop-FIXTURE-OLD` takes the new value there too and keeps that id.
- `testEditRemovingAFieldDeletesItsRowAndItsCopies`
- `testEditToAnotherDayMovesEveryRowInOneTransaction`
- `testEditToAnotherDayLeavesNoCopyBehind`
- `testEditOntoAnOccupiedInstantWritesNothing`
- `testDeleteRemovesEveryRowIncludingTheWeightRow`
- `testDeleteRemovesCopiesUnderEveryIdSoTheScanCannotReappear` — scan A with every row copied
  under `whoop-FIXTURE-GONE`: after `delete`, `scans()` is empty and no stored row of the scan
  remains under any id.
- `testDeleteOfAConflictingScanRemovesEveryMember`
- `testNoteRoundTripsAndLongNoteIsRefused`

Reading

- `testScanUnderAnotherRegisteredIdIsListed` — scan A written while `whoop-FIXTURE-OLD` was active
  (V13).
- `testScanUnderAnUnregisteredIdIsListed` — scan A's rows under `whoop-FIXTURE-GONE` (V14).
- `testCopyOfAScanRowUnderTwoIdsIsListedOnce` (V15)
- `testConflictingScanRowsAreBothKeptAndTheKeyIsConflicting` (V16) — the key is in
  `conflictingKeys`, absent from `values`, `rows[key]` has two rows, and both rows are still
  returned by `LabBookRows.category`.
- `testConflictingScanIsNotEditableAndIsDeletable`
- `testImportedScanIsListedAndNeitherEditableNorDeletable`
- `testImportedScanDayIsTheStoredDay`
- `testScansAreOrderedByInstantNotByEntryOrder`
- `testManualWeighInIsNeverAScan`
- `testUnreadableUnitIsCountedAndNeverShownAsANumber`
- `testScansReadDoesNotConsultTheFlag`
- `testAFailedStoreReadGivesAnEmptyList`

Benchmarks

- `testBenchmarkSaveReadAndDelete`, `testCustomBenchmarkKeyHasThePrefix`,
  `testBenchmarkRepsMustBeWhole`
- `testBenchmarkDeleteRemovesCopies`
- `testBenchmarkUnderAnUnregisteredIdIsListed`

`BodyRecordSingleNumberTests.swift` (the single-resolver assertions, with the scorecard flag on
unless stated)

- `testScanTotalMassIsTheResolverValueWhenItsWeekHasNoWeighIn` — scan A alone: the Today tile
  input, the estimate weight, the scorecard's `currentWeightKg`, the week's point, the profile
  mirror and the scan's total are one number (V7a).
- `testManualWeighInOutranksAScanOnTheSameDay` (V7)
- `testManualWeighInOutranksALaterScanInTheSameWeek` (V7b) — the weigh-in is on the Monday, the
  scan on the Wednesday.
- `testManualWeighInInThePreviousWeekDoesNotOutrank` (V7c) — the weigh-in is on the Sunday before.
- `testNewerWeighInInALaterWeekIsTheCurrentValue` (V8)
- `testOlderScanDoesNotOverrideANewerWeighIn`
- `testWeeklyPointIsTheWeighInWhenBothExist` — the input builder's weekly series for V7.
- `testAddingAWeighInMovesEverySurfaceTogether` and `testDeletingThatWeighInMovesThemBack`
- `testDeletingTheScanMovesEverySurfaceBackTogether`
- `testCsvWeightRowNeitherOutranksNorIsOutranked` (V7d)
- `testManualRowInAnUnknownUnitDoesNotOutrank` (V7e)
- `testAppleHealthValueInTheScanWeekDoesNotOutrankIt`
- `testRowWithANonCanonicalDayIsNeitherOutrankedNorOutranking`
- `testWithoutOutrankedScansKeepsOrderAndLeavesOtherKeysAlone`
- `testWaistSeriesIsUnchangedByTheRule`
- `testHistoryRepresentativeAgreesWithTheResolver` — for V7, V7a, V7b and V7c the row captioned
  "Represents its week" is the row whose value the resolver's series holds for that week.
- `testCombinedSeedLeavesTheStageOneWeeklySeriesUnchanged` — stage 1's weigh-ins plus scans A, B
  and C give the weekly points of the stage 1 specification §13.3 exactly.
- `testTotalMassIsStoredUnderNoOtherKey`
- `testPoundsEnteredInTheScanEqualTheResolverConversion`
- `testScanChangesNothingOnTodayWhileTheScorecardFlagIsOff`
- `testUnitConstantsEqualTheAppFormatterConstants`

`BodyRecordPresenterTests.swift` — one test per state row of §10.1 to §10.5 and §10.7, named for the
state, each asserting the presentation built from the fixture; plus:

- `testNoStateRendersAMissingValueAsZero`
- `testAConflictingKeyIsNeverRenderedAsANumber`
- `testWeighInThisWeekLineShowsOnlyWhenTheScanWouldBeOutranked` (H8)
- `testNoStringContainsAnInterpolatedNilNaNOrInfinity`
- `testEveryDisplayedScanValueEqualsLabBookFormat` — for every body-record key and a spread of
  values that do not round to zero from below.
- `testComparisonAlwaysPutsTheOlderScanFirst`
- `testPercentChangeIsHiddenForPercentAndScoreFields`
- `testDurationParsesSecondsAndMinutesSeconds` and `testDurationRejectsSixtyOrMoreSeconds`

`BodyRecordFlagTests.swift`

- `testBothFlagsDefaultToOff`
- `testEachFlagFollowsAWriteToItsOwnKeyOnly` — two `ObservableDefaultsFlag` instances over a
  private defaults suite, one per key.
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
- `test_outranking_rule_has_two_callers` — `withoutOutrankedScans(` appears in the app targets only
  in `BodyMeasurementResolver.swift` (its definition and the one call in `series`) and once in
  `CutScorecardPresenter.swift`.
- `test_no_union_code_in_stage_4` — the strings `LabBookUnion` and `unionedDeviceIds` appear in no
  file under `Strand/` or `StrandiOS/`.
- `test_no_flag_class_is_cloned` — no file under `Strand/Data/BodyRecord*.swift` or
  `StrandiOS/BodyRecord/` declares a class that observes `UserDefaults.didChangeNotification`.
- `test_allowlist_entries_still_match` — as the stage 1 scan does, so a stale entry fails.

Two existing scans stay binding and must stay green:

- `Tools/test_body_measurement_single_resolver.py` proves that no new file reads or writes a
  `weight` row by a literal key. Its assertions are kept. Where it names line numbers of
  `BodyMeasurementResolver.swift` that §8.4's edit moves, the Test author updates the numbers only,
  after ownership's own update of that file.
- Ownership's `Tools/test_lab_book_single_read_path.py` proves that no stage 4 file reads
  `labMarker` by device id or by an all-id store call. Stage 4 adds nothing to its allowlist.

### 12.6 Flag-off equivalence

With both flags off: `MarkerCatalog.builtIn`, the built-in CSV scope and the legacy unit tier are
pinned by literals (§12.1); the Health list has no new row; the routes are unreachable; the editor
is unchanged; the weigh-in history treats every source as today; the Coach context is unchanged for
existing data; no row is written. The baseline suite's results are unchanged.

Three things are **not** flag-gated, by design, and are stated here so nobody finds them later:
`MarkerCatalog.definition(for:)` resolves body-record keys, the Coach roll-up skips them, and the
resolver leaves out a scan's weight row in a week with a manual weigh-in (§8.4). None can change
anything until a body-record row exists, which needs the flag to have been on.
`testCombinedSeedLeavesTheStageOneWeeklySeriesUnchanged` and the whole stage 1 suite, which holds no
`body-scan` row, prove the resolver step is inert without one.

### 12.7 Parity (ruling R43)

Android is skipped by the owner's decision (ruling R43 of the stage 1 specification). Nothing under
`android/` is written, edited, compiled or run by this stage, and no test of this stage has a
Kotlin counterpart. The written disposition, recorded with the change:

> Stage 4 changes shared catalogue data and shared import logic on the Swift side only, by the
> owner's decision of 11 November 2026 (no Android device; Android work skipped). The Android rows
> of the gate are waived by flag and reported as waived.

**The drift, in one paragraph.** Stage 4 changes no stored-data contract that Android already
reads: no migration, no new table or column, no new category, no backup whitelist key, and
`MarkerCatalog.builtIn` and the built-in CSV alias table stay byte-identical to their Kotlin twins.
What it adds exists on the Swift side only: 29 catalogue entries in a second list, one CSV scope,
the extended unit table, the `valueText` annotation on numeric rows, the source id `body-scan`, the
store call `replaceLabMarkers`, and the rule that a manual weigh-in outranks a scan within its
week. An Android install that opened the same database would list every such row under its stored
category with a name made from its key, show the stored-unit value, ignore the annotation, and
treat a scan's `weight` row as an ordinary weight reading.

The same drift, item by item:

| # | Swift after stage 4 | Kotlin, not updated | Effect on an Android install that opens the same data |
|---|---|---|---|
| P1 | `MarkerCatalog.bodyRecord`, 29 entries | No such list (`MarkerCatalog.kt:64-106`) | A row with one of these keys is listed under its category with a name made from the key and up to three decimals (`LabBookScreen.kt:657`; `android/app/src/main/java/com/noop/ui/LabValueFormat.kt:19`). Nothing is hidden or lost |
| P2 | `MarkerCatalog.builtIn` unchanged | Equal | None |
| P3 | `LabMarkerCategory` unchanged | Equal (`MarkerCatalog.kt:24-36`) | None |
| P4 | `MarkerCatalogScope.withBodyRecord` and its alias table | No scope (`LabMarkerCsvImport.kt:383-417`) | The same CSV imports its scan rows as `custom_<slug>` keys on Android and as catalogue keys on iPhone. The same file imported on both sides produces two histories for one measure |
| P5 | `MarkerUnitTable`, extended tier | Five-marker switcher only (`MarkerEditorScreen.kt:414-433`) | Android cannot enter HbA1c in percent, or any other added unit. Rows written on iPhone hold the stored unit and read correctly |
| P6 | `valueText` annotation on a numeric row | Never written | Android shows the numeric value and ignores the annotation (`LabBookScreen.kt:675`) |
| P7 | `replaceLabMarkers`, on top of ownership's all-id rules | No DAO counterpart | Android has no scan entry |
| P8 | `BodyRecord.swift` (compare, derive, checks) | No twin | Android has no comparison |
| P9 | Scan identity by `(source, takenAt)` and source `body-scan` | Unknown to Android | Scan rows appear as separate Lab Book cards |
| P10 | Backup whitelist | Equal | None. No key was added |
| P11 | A manual weigh-in outranks a `body-scan` weight row within its week (§8.4) | Android's weight resolver knows no such rule | On Android a scan's total mass would count as the newest weight even in a week with a weigh-in |

The Swift tests pin the Swift side: `testBodyRecordCatalogueIsPinned` holds the catalogue literal,
`testFixtureScanAToScanBTable` and `testFixtureDerivedValuesForScansABAndC` hold the expected
outputs, and `testEveryAliasOfTheSecondTableResolves` holds the alias pairs.

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
| F11 | The provider refresh dropped after a scan write | `testScanTotalMassIsTheResolverValueWhenItsWeekHasNoWeighIn` |
| F12 | Pounds converted by multiplication with a rounded factor | `testPoundsEnteredInTheScanEqualTheResolverConversion` |
| F13 | Scan edit done as delete calls followed by an upsert call | `testEditToAnotherDayMovesEveryRowInOneTransaction` (it injects a failure into the write and expects the old scan whole) |
| F14 | `replaceLabMarkers` without a transaction around both halves | `testReplaceRollsBackEverythingWhenAnInsertFails` |
| F15 | The occupied-instant check removed | `testSecondScanAtTheSameInstantIsRefused` |
| F16 | An empty field written as a zero row | `testEmptyFieldsWriteNoRow` |
| F17 | An unreadable unit shown as its raw number | `testUnreadableUnitIsCountedAndNeverShownAsANumber` |
| F18 | A manual weigh-in grouped as a scan | `testManualWeighInIsNeverAScan` |
| F19 | A body-record read filtered to the active device id | `testScanUnderAnotherRegisteredIdIsListed`, `testScanUnderAnUnregisteredIdIsListed`, ownership's source scan |
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
| F33 | Scan delete removes the listed rows only, not their copies | `testDeleteRemovesCopiesUnderEveryIdSoTheScanCannotReappear` |
| F34 | `replaceLabMarkers` always inserts the incoming row | `testReplaceUpsertUpdatesTheStoredRowUnderAnotherIdInPlace`, `testReplaceUpsertUpdatesEveryCopy` |
| F35 | `replaceLabMarkers` rewrites `deviceId` to the incoming one | `testReplaceUpsertUpdatesTheStoredRowUnderAnotherIdInPlace` |
| F36 | `replaceLabMarkers` projects with a device-id filter | `testReplaceReprojectsAcrossAllDeviceIds` |
| F37 | `replaceLabMarkers` deletes by identity, taking a conflicting row with it | `testReplaceDeleteLeavesAConflictingRow` |
| F38 | `replaceLabMarkers` deletes the one row only | `testReplaceDeleteRemovesEveryCopyUnderOtherIds` |
| F39 | Upserts evaluated before the deletes | `testReplaceEvaluatesUpsertsAfterDeletes` |
| F40 | The occupancy check limited to registered ids, or to the active id | `testOccupancySpansUnregisteredAndOtherBrandIds` |
| F41 | A conflicting key shown as the value of its first row | `testConflictingScanRowsAreBothKeptAndTheKeyIsConflicting` |
| F42 | A scan with a conflicting key left editable | `testConflictingScanIsNotEditableAndIsDeletable` |
| F43 | The outranking step removed from `series` | `testManualWeighInOutranksAScanOnTheSameDay`, `testWeeklyPointIsTheWeighInWhenBothExist` |
| F44 | Outranking applied across weeks (any manual row outranks any scan) | `testManualWeighInInThePreviousWeekDoesNotOutrank` |
| F45 | Outranking applied only on the scan's own day | `testManualWeighInOutranksALaterScanInTheSameWeek` |
| F46 | A `lab-csv` weight row treated as a scan, or as a weigh-in | `testCsvWeightRowNeitherOutranksNorIsOutranked` |
| F47 | The history's representative chosen without the rule | `testHistoryRepresentativeAgreesWithTheResolver` |
| F48 | A flag class cloned for stage 4 | `test_no_flag_class_is_cloned` |
| F49 | `scans()` returns nothing while the flag is off | `testScansReadDoesNotConsultTheFlag` |

### 12.9 Privacy scans

- Stage 4 has no widget payload, no notification text and no export of its own. The scan that
  matters is the Coach context: `testCoachRollUpLeavesOutScanAndBenchmarkMarkers` builds the context
  for a store holding the whole fixture and asserts that no fixture scan value, no scan display name
  and no benchmark name occurs in it.
- A repository scan before each commit of this stage: the diff contains no number that is not in
  §13, and no file under `PersonalData/` is staged.
- The demo harness runs on an in-memory store and its own defaults suite, as `ScorecardDemo` does
  (`StrandiOS/Scorecard/ScorecardDemo.swift:25-28`). Its seed is the combined seed of §13: stage 1's
  weigh-ins and this stage's scans, one Fixture Person. Committed screenshots come from it only.

### 12.10 Simulator and rehearsal

Every frame of §10 reproduced from the fixture through `--demo-screen`, at the default and the
largest text size, with Reduce Motion on and off; enter, edit, move to another day, delete and
compare exercised by tapping. The names, all lower case, use only the prefixes reserved for this
stage in the demo registry (`bodyrecord-`, `scan-`, `compare-`, `bench-`, `labunits-`):

| Frames | Demo names |
|---|---|
| §10.1 G1 to G10, G5b | `bodyrecord-g1` … `bodyrecord-g10`, `bodyrecord-g5b` |
| §10.2 H1 to H14 | `scan-h1` … `scan-h14` |
| §10.3 I1 to I8, I5b | `scan-i1` … `scan-i8`, `scan-i5b` |
| §10.4 J1 to J11, J10b | `compare-j1` … `compare-j11`, `compare-j10b` |
| §10.5 K1 to K8 | `bench-k1` … `bench-k8` |
| §10.6 L1 to L7 | `labunits-l1` … `labunits-l7` |
| §10.7 | `bodyrecord-history-on`, `bodyrecord-history-off` |

`BodyRecordDemo.screen(named:)` returns nil for any other name, so the registry passes it on.

Then the private real-data rehearsal (roadmap 0B-7). It answers, privately: which Lab Book rows the
owner already has and in which units; whether any existing `custom_…` row is one of the §5.2
measures under another name (stage 4 re-keys nothing; the owner would re-enter or leave them); and
whether a scan typed as printed from a real report passes every range in §7.7. Nothing from the
rehearsal is committed.

## 13. Fixture

Everything here is invented. "Fixture Person" does not exist; the numbers are round on purpose.

There is **one** Fixture Person across all stages, and stage 1 defines them (stage 1 specification
§13): the phase "Fixture cut" from Monday 2031-01-06, weigh-ins on Wednesdays at 07:00 UTC, 100.0 kg
on 2031-01-08 falling to 94.0 kg on 2031-05-28. Each scan below is dated on a stage 1 weigh-in day
and its total mass is the stage 1 weight of that day. So:

- the **combined seed** (stage 1's weigh-ins and waists, plus the three scans and the benchmarks
  below) is one consistent person, and is what `BodyRecordDemo` and any simulator seed use;
- by §8.4 every scan's week holds a manual weigh-in, so in the combined seed the scans change
  nothing in stage 1's weekly points, rates or verdicts;
- tests that need a scan to be the resolver's value seed the scan without that week's weigh-in
  (variants V7a to V7e).

Tests in the pure packages use the zone-free values below. App-target tests that need an instant use
12:00 UTC of the day with the time zone injected as UTC. Device ids are those of the ownership
fixture (ownership specification §13); the active id is `whoop-FIXTURE-NEW` unless a variant says
otherwise.

| Scan | Day | `takenAt` (12:00 UTC) | Stage 1 week | Stage 1 weigh-in that day (07:00 UTC) |
|---|---|---|---|---|
| A | 2031-01-08 | 1925640000 | 1 | 100.0 kg at 1925622000 |
| B | 2031-04-09 | 1933502400 | 14 | 95.0 kg at 1933484400 |
| C | 2031-05-28 | 1937736000 | 21 | 94.0 kg at 1937718000 |

### 13.1 Three scans

| Field | Scan A · 2031-01-08 | Scan B · 2031-04-09 | Scan C · 2031-05-28 |
|---|---|---|---|
| Total mass (kg) | 100.0 | 95.0 | 94.0 |
| Fat mass (kg) | 30.0 | 26.0 | 25.0 |
| Lean mass (kg) | 67.0 | 66.0 | 66.0 |
| Bone mineral content (kg) | 3.00 | 3.00 | 3.00 |
| Fat-free mass (kg) | 70.0 | 69.0 | — |
| Body fat (%) | 30.0 | 27.4 | — |
| Visceral fat mass (g) | 1000 | 800 | — |
| Visceral fat area (cm²) | — | 80 | — |
| Android fat (%) | 36.0 | 30.0 | — |
| Gynoid fat (%) | 30.0 | 26.0 | — |
| Android to gynoid ratio | 1.20 | 1.15 | — |
| Arms lean, total (kg) | 10.00 | 10.40 | — |
| Left arm (kg) | 4.90 | 5.20 | 5.30 |
| Right arm (kg) | 5.10 | 5.20 | 5.30 |
| Legs lean, total (kg) | 20.00 | 19.60 | 19.50 |
| Left leg (kg) | 10.00 | 9.80 | — |
| Right leg (kg) | 10.00 | 9.80 | — |
| Trunk (kg) | 32.00 | 31.50 | — |
| Bone mineral density (g/cm²) | 1.200 | — | — |
| T-score | 0.5 | — | — |
| Z-score | 0.4 | — | — |
| RMR, laboratory estimate (kcal/day) | 1900 | 1850 | — |
| Note | "Fixture note" | — | — |

A dash is a field that was not entered. Entry order in the out-of-order tests: A, then C, then B.
Each scan is internally consistent within the tolerances of §7.5: fat, lean and bone add up to the
total, fat-free mass is lean plus bone, body fat is fat over total (26.0 ÷ 95.0 = 27.4 % for B), and
the ratio is android over gynoid (30.0 ÷ 26.0 = 1.15 for B).

### 13.2 Expected derived figures

| Scan | Arms to legs | Arms source | Arm side difference | Leg side difference |
|---|---|---|---|---|
| A | 50.0 | printedTotal | −3.9 (right larger) | 0.0 |
| B | 53.1 | printedTotal | 0.0 | 0.0 |
| C | 54.4 | sumOfSides | 0.0 | notAvailable(missingComponent) |

A with its legs total removed and no leg sides: `notAvailable(missingComponent)`. A with legs total
set to 0: `notAvailable(invalidComponent)`.

### 13.3 Expected comparison, scan A to scan B

| Field | Earlier | Later | Change | Percent | Direction |
|---|---|---|---|---|---|
| Total mass | 100.0 | 95.0 | −5.0 | −5.0 | down |
| Fat mass | 30.0 | 26.0 | −4.0 | −13.3 | down |
| Lean mass | 67.0 | 66.0 | −1.0 | −1.5 | down |
| Bone mineral content | 3.00 | 3.00 | 0.00 | 0.0 | same |
| Fat-free mass | 70.0 | 69.0 | −1.0 | −1.4 | down |
| Body fat | 30.0 | 27.4 | −2.6 points | hidden | down |
| Visceral fat mass | 1000 | 800 | −200 | −20.0 | down |
| Visceral fat area | — | 80 | onlyLater | — | — |
| Android fat | 36.0 | 30.0 | −6.0 points | hidden | down |
| Gynoid fat | 30.0 | 26.0 | −4.0 points | hidden | down |
| Android to gynoid ratio | 1.20 | 1.15 | −0.05 | −4.2 | down |
| Arms lean, total | 10.00 | 10.40 | 0.40 | 4.0 | up |
| Left arm | 4.90 | 5.20 | 0.30 | 6.1 | up |
| Right arm | 5.10 | 5.20 | 0.10 | 2.0 | up |
| Legs lean, total | 20.00 | 19.60 | −0.40 | −2.0 | down |
| Left leg | 10.00 | 9.80 | −0.20 | −2.0 | down |
| Right leg | 10.00 | 9.80 | −0.20 | −2.0 | down |
| Trunk | 32.00 | 31.50 | −0.50 | −1.6 | down |
| Bone mineral density | 1.200 | — | onlyEarlier | — | — |
| T-score, Z-score | 0.5, 0.4 | — | onlyEarlier | — | — |
| RMR, laboratory estimate | 1900 | 1850 | −50 | −2.6 | down |
| Arms to legs (derived) | 50.0 | 53.1 | 3.1 points | hidden | up |

"Hidden" means `compare` still returns a percent and the presenter does not show it (§7.7).

These values were worked for this document from §7.3 and §7.4 with a scratch calculation, not
produced by an implementation, which does not exist yet. The Test author recomputes each row before
relying on it; a disagreement is a defect in this table or in §7 and is reported, not worked around.

### 13.4 Variants

Each is the fixture with one change. "Alone" means seeded without stage 1's weigh-ins.

| Variant | Change | Expected |
|---|---|---|
| V1 | No scans | G2, J7 |
| V2 | Scan A only | G3, J6 |
| V3 | Scan B with fat-free mass typed 96.0 | `mismatches` contains `fatFreeIsLeanBone`; Save stays enabled |
| V4 | Scan B with body fat typed 28.3 (fat over fat plus lean) | No mismatch |
| V5 | Scan B with body fat typed 31.0 | `bodyFatPercentIsFatShare` |
| V6 | Scan A's total typed in pounds as 220.5 | Stored `220.5 / 2.20462` kg; shown as 100.0 kg |
| V7 | Scan A alone, plus a manual weigh-in of 101.0 kg at 07:00 UTC on 2031-01-08 (the scan's day) | Two weight rows on that day. The resolver's value for that day, the week's point and the current value are 101.0, although the scan's instant is later. The scan still shows 100.0. H8 is shown in the sheet. The history captions the weigh-in "Represents its week" and the scan "Not the weekly point". Deleting the weigh-in makes all three 100.0 |
| V7a | Scan A alone | The resolver's value as of 2031-01-08, the week's point and the current value are 100.0, from the scan's row |
| V7b | Scan A alone, plus a manual weigh-in of 101.0 kg at 07:00 UTC on Monday 2031-01-06 (same week, earlier day) | As V7: 101.0 everywhere, as of 2031-01-08 as well |
| V7c | Scan A alone, plus a manual weigh-in of 101.0 kg at 07:00 UTC on Sunday 2031-01-05 (the week before) | The scan is not outranked: the value as of 2031-01-08 is 100.0; the week of 2030-12-30 has the point 101.0 and the week of 2031-01-06 the point 100.0 |
| V7d | Scan A alone, plus a `lab-csv` weight row of 101.0 kg at 07:00 UTC on 2031-01-08 | The scan is not outranked and the CSV row is not a weigh-in: the later instant wins, 100.0 |
| V7e | Scan A alone, plus a manual weight row of 16.0 in the unit `stone` at 07:00 UTC on 2031-01-08 | The row is not usable, so it does not outrank: 100.0 |
| V8 | Scan A alone, plus stage 1's weigh-in of 99.2 kg on 2031-01-15 | The resolver's current value is 99.2; scan A's total stays 100.0 inside the scan |
| V9 | Scan A's fat-mass row rewritten with unit `stone` | Fat mass is unreadable in A: G5, I5; the comparison row is `onlyLater` |
| V10 | The same scan rows imported by CSV in the wide scope | A scan with source `lab-csv`, read-only (G6, I6) |
| V11 | The CSV of V10 imported in the built-in scope | No scan: rows have `custom_…` keys |
| V12 | Scan B moved to 2031-01-08 | Refused: `instantOccupied`; scan B is unchanged |
| V13 | Scan A written while `whoop-FIXTURE-OLD` was the active id; the active id then re-pointed to `whoop-FIXTURE-NEW` | Scan A is listed, whole, and is editable. An edit updates its rows in place under `whoop-FIXTURE-OLD`; a field added by the edit is written under `whoop-FIXTURE-NEW` |
| V14 | Scan A's rows stored under `whoop-FIXTURE-GONE`, which has no registry row | Scan A is listed, whole. A new scan at A's instant is refused with `instantOccupied` |
| V15 | Scan A under `whoop-FIXTURE-NEW`, with its fat-mass row also stored under `whoop-FIXTURE-OLD`, equal in every column except `id` and `deviceId` | One scan; fat mass has one member, 30.0, represented by the active id's row. Deleting the scan removes both stored fat-mass rows |
| V16 | As V15, but the second fat-mass row holds 31.0 | One scan; `conflictingKeys == ["scan_fat_mass"]`; fat mass is absent from `values` and is not shown as a number (G5b, I5b); both rows are listed in Lab Book; the scan is not editable; deleting the scan removes both rows. After the 31.0 row is deleted in Lab Book the scan is as V2 and editable |

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

**Before stage 4 starts**, and not part of it:

- The orchestrator's scaffolding commit (step 0 of the build order). Stage 4 expects from it: the
  demo-provider list in the debug block of `StrandiOS/App/StrandiOSApp.swift`; the plugin command
  `importS4` in `design/figma-plugin/code.js` and `manifest.json` and the folder
  `design/round-s4-body-record/`; `Strand/Data/ObservableDefaultsFlag.swift`;
  `Packages/StrandAnalytics/Sources/StrandAnalytics/CanonicalDay.swift`. It also brings
  `ChargeTypicalBand` and the comment block of fork-only backup keys, neither of which stage 4 uses
  or edits.
- Lab Book ownership, merged (step 1 of the serialised order): `LabBookRows`, `LabMarkerUnion`,
  `upsertOwnerLabMarkers`, `deleteLabMarkerAndCopies`, the all-id `reprojectCells`, and the removal
  of `BodyMeasurementProvider.unionedDeviceIds`.
- Stage 2's extraction in `AICoach.swift`, merged, before the one-line roll-up skip.
- The combined design frame set for the Health card, Settings and the scorecard screen, approved,
  before the hotspot commit.

| WP | Role | Files |
|---|---|---|
| 4-2 | Designer | Files inside `design/round-s4-body-record/` only (`index.html`, `model.js`, `bodyrecord.js`, `bodyrecord.css`, `README.md`, `s4-frames.json`), imported with the plugin command `importS4` to the page "Stage 4 · Body record". The Designer does not edit `design/figma-plugin/code.js` or `manifest.json` |
| 4-3 | Test author | New: `Packages/StrandImport/Tests/StrandImportTests/MarkerCatalogBodyRecordTests.swift`, `LabMarkerCsvBodyRecordScopeTests.swift`, `MarkerUnitTableTests.swift`; `Packages/StrandAnalytics/Tests/StrandAnalyticsTests/BodyRecordTests.swift`, `BodyRecordFixture.swift`; `Packages/WhoopStore/Tests/WhoopStoreTests/LabMarkerReplaceTests.swift` (it uses ownership's `LabBookOwnershipFixture.swift` and does not edit it); `StrandTests/BodyRecordStoreTests.swift`, `BodyRecordSingleNumberTests.swift`, `BodyRecordPresenterTests.swift`, `BodyRecordFlagTests.swift`, `LabReportUnitsEditorTests.swift`; `Tools/test_body_record_single_source.py`. Edited, after ownership's own edits to the same files: `StrandTests/OneNumberPerVariableTests.swift` (two added tests), `Tools/test_body_measurement_single_resolver.py` (line numbers only, §12.5) |
| 4-4a | Implementer A1 | `Packages/StrandImport/Sources/StrandImport/MarkerCatalog.swift`, `LabMarkerCsvImport.swift`; new `MarkerUnitTable.swift` |
| 4-4b | Implementer A2 | New `Packages/StrandAnalytics/Sources/StrandAnalytics/BodyRecord.swift` |
| 4-4c | Implementer A3, after ownership's LO-2 has merged | `Packages/WhoopStore/Sources/WhoopStore/LabMarkerStore.swift` (the one function of §9.2 and the private helpers it shares with ownership's two functions) |
| 4-5 | Implementer B, after 4-4a, b, c and after ownership's LO-3 has merged | New: `Strand/Data/BodyRecordSettings.swift`, `BodyScanFields.swift`, `BodyRecordStore.swift`, `BodyRecordModel.swift`, `BodyRecordPresenter.swift`. Edited: `Strand/Data/BodyMeasurementResolver.swift` (§8.4: the constant, the function, and one line in `series`), `Strand/Data/CutScorecardPresenter.swift` (the representative loop of §8.4, and the history caption and the read-only rule behind a defaulted parameter), `Strand/AI/AICoach.swift` (the roll-up skip, one line, after stage 2's extraction) |
| 4-6 | Implementer C, after G1 and 4-5 | New: `StrandiOS/BodyRecord/BodyRecordView.swift`, `BodyScanSheet.swift`, `BodyScanDetailView.swift`, `BodyScanCompareView.swift`, `BenchmarkDetailView.swift`, `BenchmarkSheet.swift`, `BodyRecordKit.swift`, `BodyRecordDemo.swift`. Edited: `StrandiOS/Scorecard/WeighInHistoryView.swift` (the scan row's tap), `Strand/Screens/LabBookView.swift` (the CSV scope argument) |
| 4-H | Orchestrator, one small commit inside stage 4's serialised step, after 4-6's new files exist | `StrandiOS/Redesign/RedesignRoute.swift` (the four cases of §5.1 and the route switch), `StrandiOS/Redesign/RedesignHealthView.swift` (the Body record row, in the fixed order of §10.1), `Strand/Screens/SettingsView.swift` (the card of §10.8, in the fixed order), `StrandiOS/App/StrandiOSApp.swift` (one element, `BodyRecordDemo.screen(named:)`, in the demo-provider list, after intake and before events) |
| 4-7 | Implementer D (4B), after 4-4a and after ownership has merged | `Strand/Screens/MarkerEditorView.swift`; `Strand/Screens/LabBookView.swift` (the "Entered as" line in `historyRow`); the editor draft type in `Strand/Data/BodyRecordPresenter.swift` |
| 4-8 | Localiser, once, after the strings are final, last step of the stage | `Strand/Resources/Localizable.xcstrings` |
| 4-9 | Reviewers (correctness, contract, data safety) and Verifier | Evidence only |

**Shared files this stage edits**, each with one writer at a time across all stages, in the order
the cross-stage check fixes:

| File | Stage 4 writer | Order across stages |
|---|---|---|
| `Strand/Resources/Localizable.xcstrings` | 4-8 | One Localiser at a time, last step of each stage: ownership, 2, 3, **4**, 5, 6 |
| `StrandiOS/App/StrandiOSApp.swift` (debug block) | 4-H | Scaffolding lands the list; each stage adds one element in integration order |
| `Strand/Screens/SettingsView.swift` | 4-H | After the combined Settings frame is approved: 2, 3, **4**, 5, 6. Shared with macOS: build `Strand` after it |
| `StrandiOS/Redesign/RedesignHealthView.swift` | 4-H | 2, **4**, 5, 6, rows in the approved order |
| `StrandiOS/Redesign/RedesignRoute.swift` | 4-H | 3, **4**, 5, 6. Additive cases |
| `Strand/Data/CutScorecardPresenter.swift` | 4-5 | **4**, then 5. Different functions; still serial |
| `Strand/AI/AICoach.swift` | 4-5 | Ownership (the roll-up read), 2 (the extraction), then **4** (the roll-up skip) |
| `Packages/WhoopStore/.../LabMarkerStore.swift` | 4-4c | Ownership, then **4-4c** |
| `Strand/Screens/LabBookView.swift` | 4-6, then 4-7 | Ownership (load, save, CSV import, delete), then **4-6** (CSV scope argument), then **4-7** ("Entered as" line) |
| `Strand/Screens/MarkerEditorView.swift` | 4-7 | Ownership only reads it; **4-7** edits after ownership merges |
| `StrandiOS/Scorecard/WeighInHistoryView.swift` | 4-6 | Stage 4 only, after ownership, whose history lists rows under every id |
| `StrandTests/OneNumberPerVariableTests.swift`, `Tools/test_body_measurement_single_resolver.py` | 4-3 | Ownership rewrites line references and re-checks the cross-id cases; stage 4 then adds its two tests |
| `Packages/StrandImport/.../MarkerCatalog.swift`, `LabMarkerCsvImport.swift` | 4-4a | Stage 4 only |
| `Strand/Data/BodyMeasurementResolver.swift` | 4-5 | Stage 4 only. No other stage lists it; stage 1's ruling for §8.4 is recorded before the edit |

**Not edited by this stage:** `Strand/Screens/DashboardCards.swift`, `Strand/Data/TodayCardReadout.swift`,
the three Today views, `project.yml`, `Packages/WhoopStore/.../Database.swift`,
`Packages/WhoopStore/.../BackupSettings.swift`, `Packages/WhoopStore/.../LabMarkerOwnership.swift`,
`Strand/Data/LabBookRows.swift`, `Strand/Data/BodyMeasurementProvider.swift`,
`Strand/Data/WeighInStore.swift` (ownership is the only editor of the last four; stage 4 only calls
them), `Strand/Data/CutScorecardInputBuilder.swift`, `Strand/Data/ObservableDefaultsFlag.swift`,
`CanonicalDay.swift`, `design/figma-plugin/code.js` and `manifest.json`,
`StrandiOS/Scorecard/ScorecardDemo.swift`, anything under `android/`.

`project.yml` needs no change: `Strand` and `StrandiOS` are included by directory
(`project.yml:88`, `:221`, `:240`). Run `xcodegen generate` after adding files.

**Parallel and serial.**

- Now, in this stage's own worktree, with no app build: 4-2 (HTML frames), 4-3 (new test files),
  4-4a and 4-4b with their `swift test`, one package at a time, and the new files of 4-5 and 4-6
  written but not built. 4-4c waits for ownership's change to `LabMarkerStore.swift`.
- Serialised on the single app build tree, as step 5 of the build order (after ownership, the stage
  1 follow-up, stage 2 and stage 3): **4B first** (4-4a's unit table, 4-7), then **4A** (4-4c, 4-5,
  4-6, 4-H), both written against `LabBookRows`; then 4-8. Each serialised commit runs `xcodegen`,
  the `NOOPiOS` build, the `Strand` build, `StrandTests` and the gate script.
- 4-6 and 4-7 both edit `LabBookView.swift`, in different functions: 4-6's scope argument first,
  then 4-7's line.
- Changes, in order, each behind its own flag: "fix: laboratory unit entry" (4-4a's unit table,
  4-7) first, then "feat: body-composition and benchmark markers". The work is local by the owner's
  decision; nothing is pushed.
- Phone: stage 4 is installed together with stage 3, at the milestone "after intake plus body
  record", after a fresh backup, with both flags off until the owner switches them on, laboratory
  units first.

Parity governance: new public declarations under `Packages/` carry the doc line of §6.3. Whether the
parity ledger accepts a Swift-only declaration without a twin claim is the open item of roadmap 0B-9
and is not attempted here.

## 15. Open questions for the owner

Work proceeds on each recommendation. Rows marked "decided by default" come from the cross-stage
check of 11 November 2026: the recommendation is the design in force in this document, and the last
column says what changes if the owner decides otherwise.

**Prerequisite**

| # | Item | Status |
|---|---|---|
| B1 | Ruling R42 ("Lab Book ownership") | Its own specification, built and merged before stage 4's serialised step, and installed after its rehearsal on a fresh backup. Stage 4 has no code that works without it |

**Decisions**

| # | Question | Recommendation, in force until overruled | If the owner says otherwise |
|---|---|---|---|
| O1 | Is a scan's total mass the weight for that day everywhere in the app? Decided by default (X11, owner decision list) | Yes. It is stored once, as a `weight` reading, and the resolver treats it like any other, subject to O2 (§8) | A separate `scan_total_mass` key would be a second number for one variable and would break R41; it would need a new ruling, a catalogue entry and a rewrite of §8 |
| O2 | When a week has both a manual weigh-in and a scan, which one does the scorecard judge, and which is the current weight? Decided by default (X11) | The weigh-in outranks the scan within that week, for the weekly point and the current value (§8.4). In a week with no weigh-in the scan is used. One stored number either way | "The later instant wins, as for any two readings": delete §8.4, `withoutOutrankedScans`, its two call sites, state H8 and its string, the tests of §12.4 that name the rule, and faults F43 to F47; a scan at noon then outranks a morning weigh-in and can be the week's point |
| O3 | On a day with both a morning weigh-in and a scan, which is the day's weight? Decided by default (X11) | The weigh-in, by O2: the day is in a week that has a weigh-in | As O2 |
| O4 | Scan markers appear in Lab Book under "Imaging" and benchmarks under "Custom". Acceptable? Decided by default | Yes. A new category would hide the rows from any older build (D3) | A new category needs a list change in Lab Book and makes the rows invisible to an older build |
| O5 | Should the in-app Coach see scan and benchmark values when "share Lab Book" is on? Decided by default | No. The roll-up skips them (§4.5), and stage 2's packet has no scan or benchmark section until the owner asks | Remove the one-line skip and its two tests; a packet section would be its own change with a version bump |
| O6 | Should the comparison be computed from the figures as displayed, or from the stored values? | As displayed, so it matches a hand calculation from the screen | §7.3 step 3 changes and §13.3 is recomputed |
| O7 | Should figures that do not add up block saving? | No. One neutral line; the report is the authority | H6 disables Save |
| O8 | Should the laboratory's resting-metabolic-rate estimate be used by the app's calorie figures? | No. It is shown in the scan and nowhere else | A separate change to the calorie model, with its own specification |
| O9 | Should Lab Book show a blood result in the unit it was typed in, with the stored unit second? | Stored unit first, "Entered as" second. Making the typed unit primary is a display preference that can follow | L6 swaps its two lines |
| O10 | Should the stricter number parsing of 4B (no `nan`, the device's decimal separator) apply even with its flag off? | Not yet: flag-off behaviour stays identical. Make it unconditional when 4B is accepted | `testFlagOffUsesTheLegacyTierAndPlainDoubleParsing` changes |
| O11 | Is the benchmark list of §5.3 right (push-up variants, pull-ups, dead hang, plank, wall sit, grip), with custom benchmarks for anything else? Decided by default. The owner is also asked to confirm the list is a general one and should stay as it is | Yes | Entries are added to or removed from §5.3, §7.1 and the pinned literal; nothing else changes |
| O12 | Should the Lab Book editor's kg and lb, cm and in entry for weight and waist ship with 4B? Decided by default | Yes. Without it a weight typed in pounds in Lab Book is stored as kilograms (stage 1 specification, C3) and reaches the resolver. The same cm and in option is offered for `height` | Remove the `weight`, `waist` and `height` rows from the extended tier of §7.2 |
| O13 | Two switches, or one? Decided by default | Two: laboratory units first, scans second, so the blood-panel fix can be accepted before the scan screens | One key gates both; §9.4, §10.8 and `BodyRecordFlagTests` shrink |
| O14 | Photo timeline (4C) stays unbuilt until the owner asks. Decided by default | Confirmed: §17 is an outline only | 4C gets its own specification, design gate and go-aheads (§17) |
| O15 | One combined layout for the Health tab's "More health" card, the Settings section and the scorecard screen, covering all stages, approved once, with the fixed row order Scorecard, Body record, Events, Timeline, Niggle log, Coach packet. Decided by default (X22) | Yes. Stage 4's row and card take their place from it (§10.1, §10.8) | The row and card move; only WP 4-H changes |
| O16 | Install stage 4 together with stage 3, after a fresh backup, with both flags off. Decided by default | Yes | Its own install |
| O17 | The fixture's figures (§13) are invented and round, including the side difference in §13.2. The owner is asked to confirm that none of them is a figure of their own | They stay | Any value named is replaced by another round one and §13 is recomputed |

## 16. What needs the owner's go-ahead

| Kind | Needed by 4A or 4B? |
|---|---|
| Database migration | **No.** One store function is added; the schema is untouched |
| Apple Health read or write | **No** |
| New build target, extension or entitlement | **No** |
| Network path | **No** |
| Backup whitelist key | **No** |
| Signing, bundle id, App Group | **No** |
| A change to the resolver's rule (§8.4) | Yes: a new ruling in the stage 1 specification. In force by default (O2) |
| Installing on the phone | Yes, as always, asked at G8, after a fresh backup and after B1, together with stage 3 |
| Switching either flag on by default | Yes, at acceptance |
| 4C | Yes, in full: see §17 |

## 17. 4C — photo timeline (outline only, OUT OF SCOPE)

Not designed, not planned for build (§15, O14). It starts only when the owner asks for it, and then
with its own specification, design gate and change.

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
- **Whether some scan methods print measures this list lacks.** The catalogue is not a gate: any
  further figure can be a custom marker.
- **Ownership's final code.** `LabBookRows`, `LabMarkerUnion`, `upsertOwnerLabMarkers`,
  `deleteLabMarkerAndCopies` and the rewritten `reprojectCells` are taken from the ownership
  specification, not from code, which does not exist yet. If a signature differs when it merges,
  §9 follows the merged code and the rules stay as written here.
- **The scaffolding's exact shapes.** The name and element type of the demo-provider list, and the
  final signatures of `ObservableDefaultsFlag` and `CanonicalDay`, are the orchestrator's. §9.4 and
  §7.8 state what stage 4 relies on.
- **The ruling number for §8.4** in the stage 1 specification, and whether stage 1's own text
  already states the rule when this stage is built.
- **Whether every reader of "the latest weight" goes through the resolver's `series`.** §8.4 relies
  on stage 1's flag-on audit (R41). A reader that picks the newest `weight` row itself would show a
  scan's total in a week with a weigh-in; `Tools/test_body_measurement_single_resolver.py` is the
  guard, and it was not re-run for this document.

## 19. Design approval record (G1)

Not yet submitted. Frames G1 to G10 and G5b, H1 to H14, I1 to I8 and I5b, J1 to J11 and J10b, K1 to
K8 and L1 to L7 are to be built in `design/round-s4-body-record/` from the §13 fixture, imported to
Figma by the local plugin's `importS4` command, and approved by the owner before WP 4-6 and WP 4-7
write any view code. The Health row, the Settings card and anything on the scorecard screen are
approved separately, once, in the combined frame set (§15, O15), before WP 4-H. The pure packages,
the store function, the tests and `Strand/Data/` logic do not wait for either.

## 20. Reconciliation (11 November 2026)

What the cross-stage check changed in this file, per conflict id.

| Id | What changed here |
|---|---|
| X1 | `LabBookUnion` and its file are removed. Every read goes through ownership's `LabBookRows` (§5.1, §9.1). A scan is built from merged rows; copies are one member, conflicting rows are both kept and make the key conflicting (§7.6, states G5b, I5b, J10b). Occupancy spans every device id present, registered or not. Scan delete and edit remove copies under every id. V13 was rewritten and V14 to V16 added on the ownership fixture's device ids; the store tests of §12.4 were rewritten to match. B1 became a prerequisite (§15) |
| X2 | `replaceLabMarkers` is specified on top of ownership: deletes by the rule of `deleteLabMarkerAndCopies`, upserts by the rule of `upsertOwnerLabMarkers`, projection over all device ids, written by 4-4c after LO-2 merges (§9.2). §12.3 was rewritten against ownership's fixture rows; faults F33 to F39 added. Benchmarks write through ownership's two owner-scope calls |
| X4 | No coach-packet section for scans or benchmarks is planned; the text that left it to stage 2 now says none exists until the owner asks (§1, D10, §4.5, O5) |
| X5 | The design round is `design/round-s4-body-record/`, command `importS4`, frames `s4-frames.json`. The Designer no longer edits the plugin files; the old round number and its open question are gone (D12, §5.1, §14, §19) |
| X6 | The demo line is no longer rewritten by this stage. `BodyRecordDemo` is one new file and one element in the scaffolding's demo-provider list, added in WP 4-H. Demo names use only the reserved prefixes; `scandetail-` became `scan-i…` (§12.10) |
| X8 | `scans() async -> [BodyScan]` is stated as the one read other stages use; stage 6's adapter maps `scans().map(\.day)`. No `scanDays()` exists. The day of a CSV-imported scan and the flag behaviour of the read are specified (§7.6, §9.1) |
| X11 | Adopted by default: a manual weigh-in outranks a scan within its week, for the weekly point and the current value. New §8.4, `BodyMeasurementResolver.withoutOutrankedScans` with two callers, state H8 and its string reworded, tests and faults F43 to F47, variants V7 to V7e, drift row P11, open questions O1 to O3 |
| X17 | The `AICoach.swift` roll-up skip is written last, against `LabBookRows.category`, after ownership and after stage 2's extraction (§4.5, §14) |
| X19 | `BodyRecordFlags` is removed; the two flags are static `ObservableDefaultsFlag` instances on `BodyRecordSettings` (§5.1, §9.4). The draft's day is validated with `CanonicalDay`; error `invalidDay` added (§7.8, §9.1) |
| X20 | One Fixture Person: the three scans are re-dated onto stage 1 weigh-in days (2031-01-08, 2031-04-09, 2031-05-28) with stage 1's weights as total mass (100.0, 95.0, 94.0), and every dependent table of §13 was recomputed. The demo uses the combined seed |
| X22 | The Health row and the Settings card take a fixed place from the combined frame set, approved once; the row order and the card order are stated (§10, §10.1, §10.8); the hotspot edits moved to the orchestrator's commit WP 4-H; the Settings card lists laboratory units first |
| Shared-file order | §14's table now carries the cross-check's order for every shared file this stage touches |
| Owner decisions | Each stage 4 decision is in §15 as decided by default, with what changes otherwise: O1 to O5, O11 to O16 |
| R43 | No instruction to write or run Kotlin remains. §12.7 opens with the drift in one paragraph and keeps the item list, with P11 added |
| Privacy | The header and §5.2 now state only the design; §5.3 and one line of §18 were reworded neutrally; every fixture value is round and belongs to the one Fixture Person; O11 and O17 ask the owner to confirm the benchmark list and the fixture figures |

Shared scaffolding this stage expects from the orchestrator's step 0, before any stage 4 code:

| Scaffolding | What stage 4 does with it |
|---|---|
| The demo registry line in `StrandiOS/App/StrandiOSApp.swift` (an ordered list of demo providers) | Adds one element, `BodyRecordDemo.screen(named:)`, after intake and before events (WP 4-H) |
| The plugin commands `importS2` to `importS6` and the stage-named design folders | Uses `importS4` and works only inside `design/round-s4-body-record/` |
| `ObservableDefaultsFlag` | Two static instances on `BodyRecordSettings` (§9.4) |
| `CanonicalDay` | Validates a draft's day (§7.8) and gives the week of §8.4 |
| `ChargeTypicalBand` | Not used by stage 4 |
| The comment block of fork-only backup keys above the Swift whitelist | Not edited: stage 4 adds no backup key (§9.5) |
