# Stage 3 specification — protein and intake

Gate G0 for stage 3 of the health super-app workstream. Read [CONTEXT.md](../CONTEXT.md),
[ROADMAP.md](../ROADMAP.md) (stage 3, and stages 1, 2 and 5 which feed or consume it),
[QUALITY-GATES.md](../QUALITY-GATES.md) and [the stage 1 specification](stage-1.md) first. Stage 1's
rulings R41 (one number per variable), R42 (a strap never owns the owner's readings) and R43 (no
Android work) bind this stage.

Verified against the source at commit `0b89b814` (branch `personal/superapp-3-protein-spec`, cut
from `personal/superapp-1-screens`). Every `path:line` below is as of that commit. Paths are relative
to the repository root. Nothing was built or run for this document; it is a reading of the code.

This file contains no personal measurements. Every number in an example belongs to the synthetic
"Fixture Person" in §13 (the same invented person as stage 1's fixture), and every default was chosen
for this document.

Reconciled on 11 November 2026 with the cross-stage check, in two passes; the changes are listed in
§18. Where this
document and an older planning note disagree, this document is the design in force.

**The stage is blocked on two owner answers** (Q1: which food app; Q4: may Health reads widen). All
three paths are specified in full so that work starts the moment the owner answers:

| Path | Chosen when | What is built |
|---|---|---|
| A | The food app writes protein and energy to Apple Health **and** the owner approves the wider read | Everything in this document |
| B | No Health writes, or the owner declines the wider read, and accepts a second entry per meal | Everything except §8 (the Health read); the quick-add sheet of §10.3 is the source |
| C | The owner only needs the coach to see intake | Only the supplement tick (§10.6) and the cutoff reminder (§10.7) |

The pure logic (§6, §7), the resolver (§9), the settings, the supplement tick and the cutoff reminder
are common to A and B and are built and tested before the owner answers. Path C is a strict subset.

**Two merges.** The stage lands in the serialised build order as step 4. The first merge is the
common parts and Path B (or C): the builder switch, the protein card, the widget, the reminder, the
quick-add store. Path A's two edits that need the owner's yes (`StrandiOS/Health/HealthKitBridge.swift`
and `project.yml`) land afterwards as a second small merge. `IntakeHealthSync` imports no HealthKit
and is part of the first merge; it stays inert until the bridge calls it.

## 1. Goal and scope

**Goal.** The owner sees today's protein against their floor all day, on the phone and on a widget,
without logging food twice.

**In scope**

- One resolver for "protein on a day" and "energy on a day", used by the card, the detail screen,
  the widget, the stage 1 scorecard's protein signal and, later, the coach packet's intake section
  (built by the separate "packet v2" change, not by this stage; §14.5).
- Path A: reading dietary protein and dietary energy samples from Apple Health into daily totals,
  each with the time it was last read.
- Path B: a quick-add sheet with per-entry edit and delete.
- A protein card in Your Cards and an intake screen: ring to the floor, calories against a range.
- A row in the Health tab's "More health" card that opens the intake screen (§10.9).
- A daily supplement tick stored as a Journal answer.
- An evening cutoff reminder, opt-in, that does not ring on top of the wind-down nudge.
- A new widget kind for grams remaining, in four families.
- Everything behind `noop.intakeEnabled`, default off.

**Out of scope**

- A food database, barcode scanning, meal photos, recipes. The app records totals, not foods.
- "Calories earned" from exercise, in any form. Intake is never offset against activity.
- Any automatic change to a target. Any advice. Any statement about health.
- Streaks, badges, "days in a row", a reminder to log food. The only notification is the cutoff.
- Fat and carbohydrate (question I5). Water and caffeine (they exist already and are unchanged).
- Health writes. Any Health read beyond the two dietary types of Path A.
- A dated override of the calorie range for a planned period. None is built, by this stage or by
  stage 5 (whose events are display context only and compute nothing). `IntakeSettings.targets(on:)`
  keeps its day parameter and returns the same targets for every day. A real override is a later
  change with its own specification.
- A caption on the intake screen during a diet-break event. Stage 3 merges before stage 5 and reads
  no event. If the owner wants the caption it is a display-only follow-up after stage 5; it changes
  no target and no state.
- The coach packet's intake section: its format, its `CoachPacketSection` case, the version bump,
  the goldens and the Claude-side text all belong to the "packet v2" change (§14.5).
- Any direct connection to a food app, an MCP server, or a network path.
- A migration, a new build target, a new entitlement. None is needed and none is added.
- Android. No Kotlin is written or run (R43). The stored-data drift is stated in §9.6 and §12.7.
- macOS, classic Today and Liquid Today screens. They compile and are unchanged.

## 2. Re-check of "what exists"

| # | Claim in the planning documents | Status | Evidence |
|---|---|---|---|
| 1 | Health reads are workouts and step count while activity-only mode is on | Confirmed. The mode is a compile-time constant | `StrandiOS/Health/HealthKitBridge.swift:67` (`activityImportsOnly = true`), `:100-105` (`readTypes`) |
| 2 | Dietary protein and energy are read nowhere in the bridge | Confirmed. Dietary **water** and **caffeine** are read in the full mode, which is the nearest precedent | `HealthKitBridge.swift:134-151` (`quantityReadIds`), `:664`, `:1667-1701` |
| 3 | The authorisation fingerprint re-prompts once when the read set changes | Confirmed. The fingerprint is the sorted `read:`/`write:` identifiers; a mismatch re-requests in the foreground only and stores the fingerprint only on success | `HealthKitBridge.swift:176` (key `noop.health.readTypeSignature`), `:186-190`, `:209-227` |
| 4 | An empty or failed Steps read preserves stored totals | Confirmed, with a limit (see C1). A failed read returns before any write; a day with no samples is simply absent from the rows upserted | `HealthKitBridge.swift:529-568`; `Packages/WhoopStore/Sources/WhoopStore/AppleStepHourStore.swift:15-30` |
| 5 | Step-only updates preserve unrelated Health columns | Confirmed: `ON CONFLICT … SET steps = excluded.steps` | `AppleStepHourStore.swift:19-22` |
| 6 | `metricSeries` is a per-day numeric series keyed `(deviceId, day, key)` with upsert, range read and single-point delete | Confirmed. It has no timestamp column | `Packages/WhoopStore/Sources/WhoopStore/Database.swift:198-216` (migration `v9`); `MetricSeriesStore.swift:31-50`, `:57`, `:97` |
| 7 | The Apple Health source namespace is `apple-health` | Confirmed | `Strand/App/AppModel.swift:54`; `Strand/Data/Repository.swift:721` |
| 8 | A nutrition CSV import exists and writes protein | Confirmed. Source id `nutrition-csv`; keys `calories_in` (kcal), `protein_g`, `carbs_g`, `fat_g`, `weight` (unit not recorded); one row per day, latest wins | `Packages/StrandImport/Sources/StrandImport/NutritionCsvImport.swift:96-108`; writer `Strand/Screens/DataSourcesView.swift:426-450` |
| 9 | Stage 1's protein signal reads `protein_g` under `nutrition-csv` | Confirmed, at one call site | `Strand/Data/CutScorecardInputBuilder.swift:13-14`, `:50-52` |
| 10 | The protein floor lives in the scorecard's rule parameters | Confirmed: `CutScorecardParameters.proteinFloorGrams`, stored in `cutScorecard.rules` | `Packages/StrandAnalytics/Sources/StrandAnalytics/CutScorecard.swift:78`; `Strand/Data/CutScorecardSettings.swift:64`, `:165-170`, `:222`, `:243` |
| 11 | The Journal can hold a daily yes/no answer | Confirmed. Native answers are written under device id `noop-journal`, which is not a strap id (R42 holds) | `Strand/Data/Repository.swift:2661`, `:2730-2735`, `:2763-2766`; catalogue `Strand/Data/JournalCatalog.swift:261-270` (`addCustom`) |
| 12 | A wind-down reminder exists | Confirmed. A static enum with its own keys; its time is derived (wake − sleep need − lead) and can differ per weekday; it plays the default sound | `Strand/System/WindDownNudge.swift:19-29`, `:95-121`, `:199-240` |
| 13 | Widget kinds are `NOOPWidget`, `PersonalStepsWidget`, `PersonalSleepWidget`, `HeartRateWidget`, `StressWidget`, `CoachBriefWidget` | Confirmed. The bundle also holds three Live Activities, nine entries in all | `StrandiOSWidgets/NOOPWidgetBundle.swift:9-21`; `PersonalMetricsWidgets.swift:193-215` |
| 14 | The App Group payload can gain optional fields | Confirmed. `WidgetSnapshot.personal` is an optional `PersonalWidgetMetrics`, and the reload check compares it | `StrandiOSShared/WidgetSnapshot.swift:44-46`, `:218-240`; `StrandiOSShared/PersonalWidgetMetrics.swift:5-15` |
| 15 | The newest migration is `v47-rr-whoop5-fill` | Confirmed | `Database.swift:1103` |
| 16 | The local gate script and the design pipeline exist | Confirmed | `Tools/personal/gate.sh`; `design/tools/serve.py`; `design/figma-plugin/manifest.json:21-30`; `design/round6-scorecard/` |
| 17 | HealthKit entitlements, including background delivery, are already present | Confirmed in the project definition | `project.yml:346-349` |

## 3. Corrections to the planning documents

| # | Document says | The code says | Consequence for this stage |
|---|---|---|---|
| C1 | ROADMAP, Path A: follow the Steps pattern, "an empty or failed read preserves stored totals" | The Steps read is a per-day statistics query (`HealthKitBridge.swift:536-541`, `:1576-1608`). A day whose samples were all deleted is absent from its result, so its stored total is never corrected. Water takes the opposite rule and writes zero for every empty day (`:755-772`), which would turn "not logged" into a measured zero | Neither rule is right for protein. §7.3 defines a third: a whole window with no sample writes nothing; inside a window that has samples, a day that lost all of its samples has its stored rows **deleted** |
| C2 | ROADMAP: daily totals stored "in the Apple Health source namespace already used by imported series" | Two problems. Deliberately deleting the Apple Health source's imported data removes every row under `apple-health` (`Strand/Screens/DataSourcesView.swift:745-766`), and a later read restores only the read window, so older intake days would be lost. And the metric catalogue binds `protein_g` and `calories_in` to source `nutrition-csv` (`Strand/Data/MetricCatalog.swift:186-187`), so Explore's "Protein" stays the CSV history wherever the totals live | Path A totals are stored under a dedicated id, `noop-intake-health` (§9.1), never under `apple-health`. The Apple Health page's delete therefore cannot touch intake. Explore keeps showing one labelled source's history (allowed by R41). No catalogue descriptor is added |
| C3 | ROADMAP: "Each total carries the time it was last read" | `metricSeries` has no time column (`Database.swift:204-210`) | The read time is a sibling key, `intake_read_at`, written in the same transaction as the totals (§9.1). No migration |
| C4 | ROADMAP WP 3-4: "pure, with Kotlin twin if it is stored or analytic" | Superseded by R43 | No twin. Written dispositions in §12.7 |
| C5 | ROADMAP: "A new widget kind; the App Group payload gains optional fields only" | `StrandTests` compiles the shared payload files by name (`project.yml:170-189`), and `Tools/check_personal_widgets.py:36` compiles `PersonalWidgetMetrics.swift` alone | The new payload type goes **inside** `StrandiOSShared/PersonalWidgetMetrics.swift`, Foundation only, so `project.yml` and that script need no change |
| C6 | ROADMAP: the cutoff reminder is "coordinated with the existing wind-down" | `WindDownNudge` exposes no hook or change notification; its schedule lives in the notification centre and its settings in private keys (`WindDownNudge.swift:19-29`) | Coordination is one-way: the cutoff reads the nudge's public statics and adapts itself. The nudge is not edited (§7.6). A change to the nudge takes effect on the cutoff at the next app activation |
| C7 | ROADMAP test plan: "a step-only or protein-only update does not disturb unrelated Health columns or series" | A `metricSeries` upsert touches exactly one `(deviceId, day, key)` (`MetricSeriesStore.swift:38-50`); protein never touches `appleDaily`, and with the dedicated id it never writes under `apple-health` at all | The risk is the reverse: a wide delete. Tested in §12.2 |
| C8 | CONTEXT §4: the Health usage text is not mentioned | The permission sheet text names only "steps and workout summaries" (`project.yml:314`; generated copy `StrandiOS/Resources/Info.plist:66-67`) | Path A changes that sentence in `project.yml` (owner go-ahead G2, §15) |
| C9 | ROADMAP surfaces: a "Calories" line | `DashboardCard.calories` already exists and means **active energy burned** (`Strand/Screens/DashboardCards.swift:33`, `:104`) | Intake energy is never titled "Calories" alone. It is "Calories eaten" (§11) and has no card of its own |
| C10 | ROADMAP: "Authorisation: … Simulator first, then the device" | A comment in the bridge states HealthKit has no simulator support (`HealthKitBridge.swift:357`) | Not settled by reading (§16). The plan does not depend on it: every decision is in code that tests on macOS (§8.2) |
| C11 | CONTEXT §3 item 3: a protein floor "shown beside the daily rings" | ROADMAP stage 3 says a card in Your Cards | The card. A fourth headline ring is not designed |
| C12 | ROADMAP: the supplement tick is "a Journal answer", with names kept out of notifications and widgets | Journal rows feed the in-app Coach's behaviour ranking (`Strand/AI/AICoach.swift:1249-1251`), whose text goes to a network provider when the Coach is on and whose output becomes the Coach brief notification and widget | Questions listed in `intake.supplement.questions` are removed from the rows the Coach reads (§10.6.1) |

## 4. Every reader and writer

### 4.1 Protein and energy intake

| Location | Reads or writes | After this stage |
|---|---|---|
| `Strand/Screens/DataSourcesView.swift:426-450` | Writes `calories_in`, `protein_g`, `carbs_g`, `fat_g`, `weight` under `nutrition-csv` | Unchanged. An import writer |
| `Strand/Data/CutScorecardInputBuilder.swift:50-52` | Reads `protein_g` under `nutrition-csv` for the scorecard's protein signal | **Resolver.** Reads `IntakeProvider.proteinDays()` (§9.4) |
| `Packages/StrandAnalytics/Sources/StrandAnalytics/CutScorecard.swift:484-490`, `:700-722` | Consumes the protein days it is handed; judges the seven days before the weigh-in, never the weigh-in day | Unchanged. Not edited |
| `Strand/Data/MetricCatalog.swift:186-189`; `Strand/Screens/MetricExplorerView.swift:1962` | Explore lists and colours the `nutrition-csv` series | Unchanged. One source's labelled history |
| `Strand/Data/CsvExport.swift:41-42`, `:102-109` | Exports every key under the strap read ids (`importedReadIds` and `computedReadIds`) | Unchanged. It does not walk the intake ids, so the CSV export carries no intake row. The database backup carries them (§9.6) |
| `Strand/Data/Repository.swift:1850-1862` (`series(key:source:)`) | The generic read used by the above | Unchanged; `IntakeProvider` calls it |
| `Strand/AI/AICoach.swift:1207`, `:1607` | Coach context. Reads no intake today (searched: no dietary or protein key) | Reads no intake after this stage either. Its one Journal read (`:1250`) gains the supplement exclusion (§10.6.1) |
| `StrandiOS/Widgets/WidgetPublish.swift:126-218` | Builds the personal widget payload (steps, sleep, goal) | Gains the intake reading from `IntakeProvider` (§8.4) |
| New: `IntakeHealthSync` | Writes `protein_g`, `calories_in`, `intake_read_at` under `noop-intake-health` | Path A only |
| New: `IntakeQuickAddStore` | Writes the same three keys under `noop-intake` | Path B only |

No other reader or writer exists. Searched `Strand`, `StrandiOS`, `StrandiOSShared`,
`StrandiOSWidgets`, `StrandTests` and the package sources for `protein_g`, `calories_in`,
`nutrition-csv`, `NutritionCsvImporter`, `dietary` and `intake.`.

### 4.2 The protein floor

| Location | Role |
|---|---|
| `CutScorecard.swift:78`, `:703`, `:1084`, `:1217` | The parameter and its use and validation |
| `CutScorecardSettings.swift:165-170`, `:222`, `:243` | The one stored copy, inside `cutScorecard.rules` |
| `Strand/Data/CutScorecardModel.swift:702-723`, `:815`, `:856`; `CutScorecardPresenter.swift:1253`, `:1317-1318`, `:1360` | The rules sheet's "Daily floor" field |
| New: `IntakeSettings.proteinFloorGrams`, `setProteinFloorGrams(_:)` | A pass-through that gets and sets `CutScorecardSettings.parameters.proteinFloorGrams`. It stores nothing of its own (§9.2) |

The floor keeps exactly one home. The intake settings' floor field and the rules sheet's field are
two editors of one stored value, written through one setter, and §12.3 asserts it.

**The floor is whole grams, and the rule is stage 1's.** Ruling R45 of the stage 1 specification
(`stage-1.md` §9.2, "The protein floor: one home, whole grams, one printed form") owns the rule: the
`parameters` getter and setter of `CutScorecardSettings` normalise the floor, one function,
`CutScorecardSettings.isWholeGramProteinFloor`, decides what either editor may save, and every
surface prints `CutScorecardSettings.proteinFloorWholeGrams`. This stage adds no rule, no predicate,
no bound and no state of its own. Its field writes the same stored value through the same setter (§9.2.1), and its
card, ring and widget print the same integer (§7.4). Stage 1's work package 1-10 lands that rule
before stage 2, so this stage never sees a fractional floor.

### 4.3 Other facts the stage touches

| Fact | Existing readers and writers | This stage |
|---|---|---|
| Health read set and fingerprint | `HealthKitBridge.swift:100-105`, `:186-190`, `:209-227`, `:232-266` | `readTypes` gains two types only while `IntakeSettings.healthReadEnabled` is true (§8.1) |
| Observed Health types | `HealthKitBridge.swift:333-388` | The two dietary types join the activity-only list under the same condition |
| Journal answers | Writers: `Strand/Screens/JournalLogCard.swift:225`, `:253`, `:398-400`, `:630-632`, `:660`; `Strand/Screens/InsightsView.swift:887`; `Strand/Screens/CoachView.swift:1068`. Readers: `Repository.swift:2665-2708`; the on-device Insights screens (`InsightsView.swift:377`, `InsightsHubView.swift:860`); the illness watch's confounder flags (`Strand/App/AppModel.swift:1988`); the in-app Coach (`AICoach.swift:1250`) | The supplement tick is one more writer of the same row, through the same two repository calls (§10.6). The Coach's read is filtered (§10.6.1); the on-device readers are unchanged |
| Wind-down schedule | Written only by `WindDownNudge` (`:199-240`), driven from `Strand/Screens/SmartAlarmView.swift:472-743` | Read only |
| Widget payload | Writer `StrandiOS/Widgets/WidgetPublish.swift:47`, `:214-217`, `:248-255`; readers the widget views | One optional field; one new reader |
| Today card list | `Strand/Data/TodayCardReadout.swift:116-121`, `:127-137`; `Strand/Screens/DashboardCards.swift:20-58` | One new case and one new defaulted parameter |
| Health tab "More health" card | `StrandiOS/Redesign/RedesignHealthView.swift:472-482` (the scorecard row, mounted under its flag); the row view at `:526-537` | One row, mounted only while the intake flag is on (§10.9) |

## 5. Final names

| Thing | Name | Where |
|---|---|---|
| Pure aggregation | `IntakeAggregation` and its types (§6) | `Packages/StrandAnalytics/Sources/StrandAnalytics/IntakeAggregation.swift` |
| Pure progress | `IntakeProgress` and its types (§6.5) | `Packages/StrandAnalytics/Sources/StrandAnalytics/IntakeProgress.swift` |
| Resolver | `IntakeResolver` (pure), `IntakeProvider` (repository-backed) | `Strand/Data/IntakeResolver.swift`, `Strand/Data/IntakeProvider.swift` |
| Settings and flag | `IntakeSettings`; the observable flag is the static instance `IntakeSettings.flag`, an `ObservableDefaultsFlag` (shared scaffolding, `Strand/Data/ObservableDefaultsFlag.swift`). No `IntakeFlag` type exists | `Strand/Data/IntakeSettings.swift` |
| Health write funnel | `IntakeHealthSync` | `Strand/Data/IntakeHealthSync.swift` |
| Quick-add write funnel | `IntakeQuickAddStore`, `IntakeEntry` | `Strand/Data/IntakeQuickAddStore.swift` |
| Supplement tick | `IntakeSupplementTick` | `Strand/Data/IntakeSupplementTick.swift` |
| Presenter and models | `IntakePresenter`, `IntakeCard`, `IntakeScreenModel` | `Strand/Data/IntakePresenter.swift`, `Strand/Data/IntakeModel.swift` |
| Cutoff reminder | `IntakeCutoffReminder`, `IntakeCutoffPlan` (pure) | `Strand/System/IntakeCutoffReminder.swift` |
| Screens | `IntakeView`, `IntakeQuickAddSheet`, `IntakeSettingsSection` | `StrandiOS/Intake/` |
| Debug harness | `IntakeDemo` | `StrandiOS/Intake/IntakeDemo.swift` |
| Widget | `PersonalProteinWidget`, kind string `PersonalProteinWidget` | `StrandiOSWidgets/PersonalProteinWidget.swift` |
| Widget payload | `PersonalIntakeReading`; field `PersonalWidgetMetrics.intake` | `StrandiOSShared/PersonalWidgetMetrics.swift` |
| Dashboard card | `DashboardCard.protein`, raw value `protein` | `Strand/Screens/DashboardCards.swift` |
| Navigation | `RedesignRoute.intake` | `StrandiOS/Redesign/RedesignRoute.swift` |
| Feature flag | `noop.intakeEnabled`, Bool, default `false` | `IntakeSettings.enabledKey` |
| Source ids | `noop-intake-health` (new: totals read from Apple Health), `noop-intake` (new: quick-add), `nutrition-csv` (existing). Nothing of this stage is stored under `apple-health` | §9.1 |
| Series keys | `protein_g`, `calories_in` (both existing), `intake_read_at` (new) | §9.1 |
| Notification ids | `intake-cutoff-wd1` … `intake-cutoff-wd7` | §7.6 |
| Design round | `design/round-s3-intake/`; plugin command `importS3`; export `s3-frames.json` | The stage-named scheme every stage uses. The folder and the plugin command are created by the orchestrator's scaffolding commit; this stage's designer edits only inside the folder |
| Demo names | reserved prefix `intake-` | One element in the demo registry, answered by `IntakeDemo` (§12.9) |
| Health tab row | `HealthIntakeRow`, a private view | `StrandiOS/Redesign/RedesignHealthView.swift` (§10.9) |
| Day-key rule | `CanonicalDay` (shared scaffolding, `Packages/StrandAnalytics/Sources/StrandAnalytics/CanonicalDay.swift`) | Used for every day-key validity check and day arithmetic in this stage; no second implementation is written |
| Coach exclusion | `IntakeSettings.coachVisible(_:defaults:)` | §10.6.1 |
| Source scan | `Tools/test_intake_single_resolver.py` | §12.4 |

The model, presenter, resolver, funnels, settings and reminder live under `Strand/` so `StrandTests`
(macOS only) can test them, as in stage 1 (`stage-1.md` §5). Views live under `StrandiOS/`.
`Strand`, `StrandiOS`, `StrandTests` and `StrandiOSWidgets` include their sources by directory
(`project.yml:87-91`, `:170`, `:220-244`, `:387`), so new files need only `xcodegen generate`.

## 6. Pure logic: the API

No store, no clock, no `Calendar.current`, no `TimeZone.current`. Conventions follow
`CutScorecard.swift`: caseless `public enum` namespaces, `Equatable, Sendable` value types with
explicit public initialisers, day keys as canonical `yyyy-MM-dd` strings. `TimeZone(identifier:)` and
`LocalDayWindows` (`Packages/StrandAnalytics/Sources/StrandAnalytics/LocalDayWindows.swift:160-267`)
are used; both are already in the package.

Day keys are validated and moved only through `CanonicalDay` (stage 6 specification §6.0, landed by
the shared scaffolding commit): a key is canonical when `CanonicalDay.number(key) != nil`; the day
`n` days before `key` is `CanonicalDay.key(CanonicalDay.number(key)! - n)`. This stage writes no
day-key parser of its own. The day an *instant* falls on is a different question and stays with
`LocalDayWindows` (§7.1).

Each public declaration carries the doc line "No Kotlin twin: iPhone-only by the owner's decision
(stage 1 ruling R43)."

### 6.1 Units

Grams for protein, kilocalories for energy, epoch seconds (`Int`) for instants. Conversion from
HealthKit quantities happens in the bridge.

### 6.2 Inputs

```swift
public enum IntakeNutrient: String, Sendable, CaseIterable { case protein, energy }

/// One logged amount of one nutrient.
public struct IntakeSample: Equatable, Sendable {
    public let id: String                // stable: a HealthKit uuid string or a quick-add entry id
    public let nutrient: IntakeNutrient
    public let startEpochSeconds: Int    // the instant the food is logged for
    public let amount: Double            // g or kcal
    public let sourceId: String          // the writing app's bundle id, or "noop-intake"
    public init(id: String, nutrient: IntakeNutrient, startEpochSeconds: Int,
                amount: Double, sourceId: String)
}

/// From `fromEpochSeconds` on, days are counted in `zoneIdentifier`.
public struct IntakeZoneSegment: Equatable, Sendable, Codable {
    public let fromEpochSeconds: Int
    public let zoneIdentifier: String
    public init(fromEpochSeconds: Int, zoneIdentifier: String)
}

/// What the store holds for one day under one source id.
public struct IntakeStoredDay: Equatable, Sendable {
    public let day: String
    public let proteinGrams: Double?
    public let energyKcal: Double?
    public let readAtEpochSeconds: Int?
    public init(day: String, proteinGrams: Double?, energyKcal: Double?, readAtEpochSeconds: Int?)
}
```

### 6.3 Outputs

```swift
public struct IntakeDayTotal: Equatable, Sendable {
    public let day: String
    public let proteinGrams: Double?   // nil: no admitted protein sample on this day
    public let energyKcal: Double?     // nil: no admitted energy sample on this day
    public let sampleCount: Int        // admitted samples of either nutrient
    public let sourceIds: [String]     // distinct, ascending
}

public struct IntakeRejections: Equatable, Sendable {
    public let nonFinite: Int
    public let negative: Int
    public let duplicateId: Int
    public let outsideWindow: Int      // day key before firstDay or after lastDay
    public let excludedSource: Int
}

public struct IntakeAggregationResult: Equatable, Sendable {
    public let totals: [IntakeDayTotal]   // ascending; only days with at least one admitted sample
    public let emptyDays: [String]        // ascending; days in the window with none
    public let rejected: IntakeRejections
}

public enum IntakeWriteReason: String, Sendable { case windowEmpty, unchanged, changed }

public struct IntakeWritePlan: Equatable, Sendable {
    public struct Point: Equatable, Sendable { public let day: String; public let key: String; public let value: Double }
    public struct Deletion: Equatable, Sendable { public let day: String; public let key: String }
    public let upserts: [Point]           // ascending by day, then key
    public let deletions: [Deletion]      // ascending by day, then key
    public let reason: IntakeWriteReason
    public let changedDays: [String]      // days whose protein or energy value differs from stored
}

public enum IntakeAggregation {
    public static let proteinKey = "protein_g"
    public static let energyKey = "calories_in"
    public static let readAtKey = "intake_read_at"

    /// The zone in force at an instant: the segment with the greatest `fromEpochSeconds` at or
    /// before it; before every segment, the earliest segment. A segment whose identifier Foundation
    /// does not know is skipped. With no usable segment the zone is UTC.
    public static func zone(atEpochSeconds t: Int, zoneLog: [IntakeZoneSegment]) -> TimeZone

    /// The local day an instant belongs to (§7.1).
    public static func dayKey(epochSeconds t: Int, zoneLog: [IntakeZoneSegment]) -> String

    /// The log to store after observing `zoneIdentifier` at `now` (§7.1). Returns the input
    /// unchanged when the last segment already names that zone.
    public static func appending(zoneIdentifier: String, at now: Int,
                                 to zoneLog: [IntakeZoneSegment]) -> [IntakeZoneSegment]

    /// Daily totals for the day keys `firstDay ... lastDay` inclusive (§7.2).
    /// `admittedSourceIds == nil` admits every source.
    public static func aggregate(samples: [IntakeSample], zoneLog: [IntakeZoneSegment],
                                 admittedSourceIds: Set<String>?,
                                 firstDay: String, lastDay: String) -> IntakeAggregationResult

    /// What to write so the store equals `result` over its window (§7.3).
    public static func plan(result: IntakeAggregationResult, stored: [IntakeStoredDay],
                            readAtEpochSeconds: Int) -> IntakeWritePlan
}
```

### 6.4 Rejection behaviour

`aggregate` never traps and never throws. A sample is dropped and counted once, checked in this
order: `nonFinite` (amount not finite, or magnitude above `1e100`, the stage 1 arithmetic limit R3),
`negative` (amount below zero), `excludedSource`, `outsideWindow`, `duplicateId` (same `id` and
nutrient as an earlier sample in the input array; the first is kept). A zero amount is valid and
counts as a sample. If `firstDay` or `lastDay` is not a canonical real day key (stage 1 R5, tested
with `CanonicalDay.number(_:) == nil`), or `firstDay > lastDay`, the result has no totals, no empty
days, and every sample counted as `outsideWindow`.

### 6.5 Progress

```swift
public struct IntakeTargets: Equatable, Sendable {
    public var proteinFloorGrams: Double?
    public var energyLowKcal: Double?
    public var energyHighKcal: Double?
    public var energyHardFloorKcal: Double?
    public init(proteinFloorGrams: Double? = nil, energyLowKcal: Double? = nil,
                energyHighKcal: Double? = nil, energyHardFloorKcal: Double? = nil)
    /// False when any present value is not finite, not positive or above 1e100, when low > high,
    /// or when the hard floor is above the low end.
    public var isValid: Bool { get }
}

public enum IntakeProteinState: String, Sendable { case noFloor, notMeasured, below, atFloor, above }

public struct IntakeProteinProgress: Equatable, Sendable {
    public let state: IntakeProteinState
    public let grams: Double?            // as given; nil when not measured
    public let floorGrams: Double?       // as given
    public let shownGrams: Int?          // whole grams to display
    public let shownFloorGrams: Int?
    public let remainingGrams: Int?      // > 0 only in `below`; 0 in `atFloor` and `above`
    public let overGrams: Int?           // > 0 only in `above`
    public let ringFraction: Double?     // 0...1; nil in `noFloor` and `notMeasured`
}

public enum IntakeEnergyState: String, Sendable {
    case notMeasured, noRange, soFar, belowHardFloor, belowRange, inRange, aboveRange
}

public struct IntakeEnergyProgress: Equatable, Sendable {
    public let state: IntakeEnergyState
    public let kcal: Double?
    public let shownKcal: Int?
    public let toLowEndKcal: Int?        // > 0 only when a low end exists and the amount is under it
    public let overHighEndKcal: Int?     // > 0 only in `aboveRange`
}

public enum IntakeProgress {
    /// The one "is the floor met" predicate (§7.4).
    public static func meetsFloor(grams: Double, floorGrams: Double) -> Bool
    public static func protein(grams: Double?, floorGrams: Double?) -> IntakeProteinProgress
    /// `dayIsOpen`: more food may still be logged for this day (§7.5).
    public static func energy(kcal: Double?, targets: IntakeTargets, dayIsOpen: Bool) -> IntakeEnergyProgress
}
```

The pure package declares no rule about which floors may be stored. That rule is stage 1's (R45) and
lives in `CutScorecardSettings`; `floorGrams` here is whatever the caller read through it.

## 7. Algorithm

### 7.1 The day an entry belongs to

The day boundary is local midnight, the calendar day, as in stage 1 (`stage-1.md` §6.1). It is not
the 04:00 logical day (`Repository.swift:745-756`).

The rule, decided once for the stage: **an instant belongs to the local calendar day it fell on in
the zone the phone was in at that instant, as far as the app knows.** The app's knowledge is the
*zone log*: an ordered list of `(fromEpochSeconds, zoneIdentifier)`.

- `dayKey(epochSeconds: t, zoneLog:)` is `LocalDayWindows(timeZone: zone(atEpochSeconds: t, …)).dayKey(for:)`.
- `appending(zoneIdentifier: z, at: now, to: log)`: if the log is empty the result is
  `[(0, z)]`. If the last segment's identifier is `z` the log is returned unchanged. Otherwise
  `(now, z)` is appended. A log longer than 32 segments drops its second segment (the first stays, so
  old instants keep a zone). If `now` is at or before the last segment's start (the clock moved
  back), the last segment is replaced by `(lastStart, z)`.
- The app calls `appending` with `TimeZone.current.identifier` before every Health read and every
  quick-add save, and stores the result (§9.2).

Consequences, each a test in §12.1:

- Every instant maps to exactly one day key, so no entry is counted twice or dropped by travel.
- A stored day does not change when the phone later changes zone, because the segment covering
  that day's instants is unchanged. This is stage 1's "decided once" rule applied to read data.
- Daylight-saving shifts are exact, because a segment names a zone, not an offset.
- After a westward change a later instant can fall on an earlier day key. That is correct: the
  owner lived that local day twice in part.
- The app learns of a change only when it next runs. Entries logged between the real change and
  that moment are counted in the old zone. This is stated, not hidden (§16).

A quick-add entry stores its day when saved (§9.3) and is never re-keyed.

### 7.2 Daily aggregation

`aggregate`:

1. Drop and count samples as in §6.4.
2. Key each remaining sample by `dayKey(epochSeconds: startEpochSeconds, zoneLog:)`.
3. For each day key in `firstDay ... lastDay` with at least one sample: `proteinGrams` is the sum
   of its protein amounts, or nil if it has no protein sample; `energyKcal` likewise. Sums are
   taken in ascending `(startEpochSeconds, id)` order so the result does not depend on input order.
   Totals are stored unrounded and are not quantized; comparison quantizes (§7.4).
4. Every other day key in the window is an empty day.

How the listed cases fall out:

| Case | Behaviour |
|---|---|
| Several entries in a day | Summed |
| Two sources | Every admitted source is summed. With `admittedSourceIds` set, others are dropped and counted. The interface names the sources when more than one wrote on the day (§10.2) and offers the choice (§10.5). Default: all sources, which is what the Health app's own daily total shows |
| An entry edited in the food app | Each read is a full replacement of the window, not a delta, so the new amount simply appears. Whether the food app keeps or replaces the sample id does not matter |
| An entry deleted | The next read's total is lower. If it was the day's last entry the day becomes empty (§7.3) |
| Just before and just after midnight | 23:59:59 local is that day; 00:00:00 local is the next |
| A time-zone change mid-day | §7.1 |
| An entry dated later today | Counted toward today (the food app's own total includes it). A day key after `lastDay` is `outsideWindow` |

### 7.3 What a read writes

`plan(result:stored:readAtEpochSeconds:)`, for one source id:

1. **Whole window empty** (`result.totals` is empty): no upserts, no deletions, reason
   `windowEmpty`. HealthKit does not reveal a denied read; an empty window may mean "access declined",
   "food app removed" or "nothing logged", and none of those is evidence that stored days are wrong.
2. Otherwise, for each total day: upsert `protein_g` when `proteinGrams` is non-nil, else delete a
   stored `protein_g`; the same for `calories_in`; upsert `intake_read_at = readAtEpochSeconds`.
3. For each empty day that has a stored row: delete its `protein_g`, `calories_in` and
   `intake_read_at`. The day then reads "not measured". It is never written as zero.
4. A value upsert is omitted when the stored value differs by at most `1e-9` (the tolerance
   `HydrationStore.swift:183-185` uses). `intake_read_at` is still upserted for every total day,
   so freshness advances when nothing changed.
5. `changedDays` lists the days where step 2 or 3 changed a protein or energy value. Reason is
   `changed` if it is non-empty, else `unchanged`.

A **failed** read never reaches `plan`: `IntakeHealthSync` returns before aggregating (§8.2).

A written day must lie wholly inside the queried instants under any zone log. The query therefore
starts four local days before the first written day (§8.2). The margin is the worst case of two
zones up to 26 hours apart.

### 7.4 The floor

`meetsFloor(grams:floorGrams:)` is `CutScorecard.quantize(grams) >= CutScorecard.quantize(floorGrams)`
(`CutScorecard.swift:977`), the comparison the scorecard's protein signal makes
(`CutScorecard.swift:707`). A test asserts the two agree over a generated spread (§12.1), so "the ring
is complete" and "this day counted toward the scorecard" cannot disagree.

`protein(grams:floorGrams:)`:

- `noFloor` when `floorGrams` is nil, not finite or not positive. `shownGrams` is still set when
  grams are known. No ring.
- `notMeasured` when `grams` is nil (or not finite, or negative). No number, no ring.
- Otherwise, with `g = quantize(grams)` and `f = quantize(floor)`:
  `shownGrams = Int(g.rounded(.down))`, `shownFloorGrams = Int(f.rounded(.up))`.
  - `below` when `g < f`: `remainingGrams = max(1, shownFloorGrams − shownGrams)`,
    `ringFraction = g ÷ f`.
  - `atFloor` when `g >= f` and `shownGrams <= shownFloorGrams`: remaining 0, over 0, fraction 1.
  - `above` otherwise: `overGrams = shownGrams − shownFloorGrams`, remaining 0, fraction 1.

Rounding grams down and the floor up means the screen never shows "0 g remaining" before the floor
is met, and `shownGrams + remainingGrams == shownFloorGrams` whenever the floor is a whole number.

**The printed floor is stage 1's integer.** Every caller in the app passes
`IntakeSettings.proteinFloorGrams`, which is `CutScorecardSettings.parameters.proteinFloorGrams` and
is therefore already a whole number (stage 1 R45: the getter normalises, including a fractional
floor stored before that ruling or restored from a backup). So `shownFloorGrams` equals
`CutScorecardSettings.proteinFloorWholeGrams`, the integer the rules sheet, the scorecard's protein
row and the coach packet print, and `testShownFloorIsTheScorecardsWholeGramFloor` (§12.3) asserts it
for the card, the screen and the widget reading. The round-up above is only the pure function's
defined behaviour for an argument that is not whole; no code in this stage passes one.

**The ring completes at the floor and stays complete.** Past the floor the number keeps counting
and a second line reads "+N g over your floor". There is no second lap, no colour change and no
celebration: the floor is a floor, not a target.

### 7.5 Energy against the range

`energy(kcal:targets:dayIsOpen:)`:

- `notMeasured` when `kcal` is nil.
- `noRange` when neither `energyLowKcal` nor `energyHighKcal` is set, or `targets.isValid` is false.
  The amount is shown alone.
- With `k = quantize(kcal)` and the bounds quantized:
  - `aboveRange` when a high end exists and `k > high`. This is reported whether or not the day is
    open, since more food cannot lower it. `overHighEndKcal = ceil(k − high)`.
  - `soFar` when `dayIsOpen` and the amount is under the low end. `toLowEndKcal = ceil(low − k)`.
    No judgement is made about a day still in progress.
  - `belowHardFloor` when the day is closed, a hard floor exists and `k < hardFloor`.
  - `belowRange` when the day is closed, a low end exists and `k < low`.
  - `inRange` otherwise.
- `shownKcal = Int(k.rounded())`.

`dayIsOpen` is computed by the app from one clock (§9.5): the day is today, and either no cutoff
time is set or the current minute of the day is before it. A past day is closed. So the plain note
below the hard floor appears only for a day that is over, or for today after the owner's own cutoff.
It never appears in the morning.

### 7.6 The cutoff reminder and the wind-down nudge

```swift
enum IntakeCutoffPlan {
    struct Trigger: Equatable { let weekday: Int; let minuteOfDay: Int; let playsSound: Bool }
    /// `windDownMinuteByWeekday`: the calendar weekday (1 = Sunday … 7 = Saturday) each wind-down
    /// trigger fires on, mapped to its minute of the day. Empty when the nudge is off.
    static func triggers(cutoffMinuteOfDay: Int, windDownMinuteByWeekday: [Int: Int],
                         quietWindowMinutes: Int = 30) -> [Trigger]
    /// The map above, from the nudge's public statics.
    static func windDownFireTimes(enabled: Bool, hasPerDayOverrides: Bool, dailyMinute: Int,
                                  minuteForWakeWeekday: (Int) -> Int,
                                  dayShiftForWakeWeekday: (Int) -> Int) -> [Int: Int]
}
```

- `triggers` always returns seven triggers, weekdays 1 to 7 ascending, each at the cutoff minute
  (clamped to `0 ... 1439`).
- A trigger's `playsSound` is false when any wind-down fire time lies within `quietWindowMinutes`
  of it, measured on the week as a circle of 10 080 minutes (so 23:50 and 00:10 the next day are 20
  minutes apart). Exactly at the window's edge counts as inside. Otherwise true.
- `windDownFireTimes`: empty when not enabled. Without per-day overrides every weekday maps to
  `dailyMinute` (`WindDownNudge.nudgeMinuteOfDay()`, `WindDownNudge.swift:186-190`). With overrides,
  for each wake weekday `v` the fire weekday is `WindDownNudge.shiftedWeekday(weekday: v, by: shift(v))`
  and the minute is `nudgeMinuteOfDay(forWeekday: v)` (`:95-121`), exactly what `schedule()` does
  (`:211-229`).

The phone therefore sounds once. The wind-down nudge is never edited, delayed or silenced. A silent
cutoff is delivered with no sound and `interruptionLevel = .passive`; it still appears in the list.

`IntakeCutoffReminder` follows `WeighInReminder` (`Strand/System/WeighInReminder.swift:52-67`,
`:98-123`, `:172-184`): an injected centre (it reuses the `WeighInReminderCenter` protocol, `:7-14`,
without renaming it), an `Outcome` of `scheduled`, `denied` or `off`, permission asked only when the
owner switches it on, a denied permission reverting the switch, and reconciliation on app activation
(the pattern at `StrandiOS/App/RootTabView.swift:120-131`). Reconciliation removes the seven ids and
adds them again from `triggers`. With the flag or the switch off it does nothing at all: no task, no
call to the notification centre.

`Strand/System/IntakeCutoffReminder.swift` is a new file that builds `UNMutableNotificationContent`.
Stage 5's source scan `test_notification_producers_never_name_personal_events`
(`Tools/test_personal_events_boundaries.py`) lists every such file and fails on an unlisted one.
Stage 3 merges first, so stage 5 adds this file to its list when it writes the scan. If the order is
ever reversed, the stage 3 commit that adds this file adds the list entry in the same commit.

## 8. Path A: reading Apple Health

Needs the owner's go-ahead (G1, G2 in §15). Path B is the alternative that avoids it.

### 8.1 Read set, fingerprint and the one prompt

`IntakeSettings.healthReadEnabled` is true only when `noop.intakeEnabled` is on **and**
`intake.source == "appleHealth"`. In `HealthKitBridge`:

- `readTypes` (`:100-105`), in its activity-only branch, also inserts `.dietaryProtein` and
  `.dietaryEnergyConsumed` when `healthReadEnabled` is true. `writeTypes` is untouched (`:118-119`
  stays empty).
- `enableLiveDelivery` (`:337`) observes the same two types under the same condition.
- Nothing else in the read set changes. With the setting off the fingerprint string
  (`:186-190`) is byte-identical to today's, so no prompt appears and flag-off equivalence holds.

When the owner picks "Apple Health" as the source (§10.5), the settings code calls a new
`HealthKitBridge.requestIntakeReadAccess()`, which runs the existing
`requestNewAuthorizationTypesIfNeeded()` (`:209-227`) and then `sync()`. HealthKit shows its sheet for
the two undetermined types only, once. The fingerprint is stored only on success, so a failed
request is retried at the next foreground sync. Switching the source away again changes the
fingerprint back; the re-request shows no sheet because nothing is undetermined.

A fresh install reaches the same place through `requestAuthorization()` (`:232-266`), which already
requests `readTypes`.

### 8.2 The read

The bridge gains one fetch, modelled on `collectCaffeine` (`:1667-1701`):

```swift
/// Protein and energy samples in [start, end). Nil when either query failed.
private func collectIntakeSamples(start: Date, end: Date) async -> [IntakeSample]?
```

Two `HKSampleQuery` calls (`.dietaryProtein` in grams, `.dietaryEnergyConsumed` in kilocalories),
the predicate the other reads use (window with `.strictStartDate`, plus `notNoopAuthored`). Each
sample maps to `IntakeSample(id: uuid string, nutrient, startEpochSeconds: floor of the start,
amount, sourceId: sourceRevision.source.bundleIdentifier)`. A failed cast or an error on either
query returns nil for both, as `:1679-1684` does.

Everything after the fetch is `IntakeHealthSync`, which imports no HealthKit and is tested on macOS:

```swift
@MainActor
struct IntakeHealthSync {
    enum Outcome: Equatable {
        case disabled                     // setting off: nothing read, nothing written
        case failedRead                   // samples nil: nothing written
        case preserved                    // window empty: nothing written
        case unchanged                    // only read times advanced
        case written(changedDays: [String])
        case failedWrite
    }
    init(repository: Repository, settings: IntakeSettings, now: @escaping () -> Date,
         zoneIdentifier: @escaping () -> String)
    /// The instants to query for a read covering `days` local days back from today.
    func queryWindow(days: Int) -> (start: Date, end: Date, firstDay: String, lastDay: String)
    func apply(samples: [IntakeSample]?, firstDay: String, lastDay: String) async -> Outcome
}
```

- `queryWindow(days:)`: append the current zone to the zone log and store it. `lastDay` is
  today's key under the log. `firstDay` is `lastDay` minus `days`
  (`CanonicalDay.key(CanonicalDay.number(lastDay)! - days)`). `end` is the start of the day
  after `lastDay` in the current zone. `start` is the start of the day `days + 4` before today in
  the current zone (§7.3).
- `apply`: nil samples → `failedRead`. Otherwise aggregate with the stored zone log and
  `IntakeSettings.admittedHealthSources`, read the stored days for the window under
  `noop-intake-health`
  (a failed store read returns `failedWrite` and writes nothing, the rule at
  `HydrationStore.swift:164-170`), build the plan, apply the upserts in one `upsertMetricSeries` call
  and then each deletion, record the sources seen (§9.2), then tell `IntakeProvider` to refresh.
- In `sync(days:)` the intake pass runs inside the activity-only branch **before** the step read
  (`:529`) and independently of it: its outcome does not change `sync`'s return value or
  `lastError`, and a failed step read does not skip it. Its own last outcome and time are published
  on `IntakeProvider` for the interface.
- The window is `days` from the caller (30 from a foreground sync, 1 to 31 from an observer wake,
  `:412`). The first successful read backfills 90 days, gated by `intake.health.backfilled`,
  set only once a read returned at least one sample, the rule Steps uses (`:531-534`, `:561-563`).

The observer coalescing (`:419-436`) applies unchanged: a wake inside fifteen minutes of a sync
that covered its window stands down.

### 8.3 Freshness

Each day's `intake_read_at` is the instant of the last successful read whose window contained the
day and found samples in the window. The interface shows it wherever it shows the total (§10). A
read that failed, or a window that came back empty, does not advance it. So an old time means
exactly "NOOP has not confirmed this figure since then".

HealthKit's store is unreadable while the phone is locked, so a background wake on a locked phone is
expected to produce `failedRead`. That is why the widget has a stale state (§10.8).

### 8.4 Publishing to the widget

`WidgetSnapshot.publish(from:)` runs on activation, on a repository refresh while active, and on
entering the background (`StrandiOS/App/StrandiOSApp.swift:275-277`, `:390`, `:410`). An intake write
does not bump `refreshSeq` (`Repository.swift:1017-1024`), so a new fast path is added beside
`publishLive` (`StrandiOS/Widgets/WidgetPublish.swift:228-241`):

```swift
@MainActor static func publishIntake(_ reading: PersonalIntakeReading?)
```

It loads the stored snapshot, replaces `personal.intake`, and if the value changed saves and calls
`WidgetCenter.shared.reloadTimelines(ofKind: "PersonalProteinWidget")` (the single-kind reload
`Strand/System/CoachBriefScheduler.swift:285` uses). With no stored snapshot it does nothing; the
next full publish carries the reading. `IntakeProvider` calls it after every refresh that changed
today's resolved protein, floor or read time. The full publish path (`WidgetPublish.swift:214-217`)
includes the same reading, built by the same `IntakePresenter.widgetReading` function.

Reload count is bounded by the number of times today's total changes, a handful a day.

## 9. Storage and the resolver

### 9.1 Daily totals

`metricSeries` rows. No migration, no new table, no new column, no new store function.

| `deviceId` | `key` | Value | Writer |
|---|---|---|---|
| `noop-intake-health` | `protein_g` | grams for the day | `IntakeHealthSync` only |
| `noop-intake-health` | `calories_in` | kilocalories for the day | `IntakeHealthSync` only |
| `noop-intake-health` | `intake_read_at` | epoch seconds of the last confirming read | `IntakeHealthSync` only |
| `noop-intake` | `protein_g`, `calories_in` | sums of that day's quick-add entries | `IntakeQuickAddStore` only |
| `noop-intake` | `intake_read_at` | epoch seconds of the last entry change | `IntakeQuickAddStore` only |
| `nutrition-csv` | `protein_g`, `calories_in`, … | as today | The CSV import, unchanged |

Three sibling keys for one day are written by one `upsertMetricSeries` call, which is one
transaction (`MetricSeriesStore.swift:31-35`), so a total and its read time cannot be torn apart.

R42: none of these ids is a strap id. Removing, forgetting or losing a strap deletes rows only under
that strap's id (`Packages/WhoopStore/Sources/WhoopStore/DeviceRegistryStore.swift:162-173`, `:203-215`)
and cannot touch them.

**Why a dedicated id for Path A.** The Apple Health page's "delete imported data" removes every row
under `apple-health` (`Strand/Screens/DataSourcesView.swift:745-766`). A later read restores only the
read window (30 days, 90 on the first read), so intake stored there would lose its older days to an
action taken on a different feature. Totals read from Apple Health are therefore stored under
`noop-intake-health`, which no registry entry names and no existing delete addresses. `IntakeHealthSync`
is the only code that writes or deletes under it, and it deletes only the day-and-key pairs of its
own plan (§7.3). Neither intake id is registered as a device or shown in Devices or Data Sources.
Tests assert that deleting a strap's data and deleting the Apple Health source's data both leave
every intake row in place (§12.2).

This stage offers no control that erases the Apple Health intake history as a whole (question I14).
A wrong day is corrected at the source and follows at the next read (§10.2).

The keys `protein_g` and `calories_in` are reused, not renamed, so the three sources hold the same
quantity under the same name and unit.

### 9.2 Settings

All in `UserDefaults.standard`, declared in `IntakeSettings`. The observable copy of the flag is
`IntakeSettings.flag`, one static `ObservableDefaultsFlag(key: IntakeSettings.enabledKey)`. That
class comes from the shared scaffolding commit: it is the body of `CutScorecardFlag`
(`Strand/Data/CutScorecardModel.swift:18-63`) with the key as a parameter, `@MainActor`, an
`ObservableObject` with `@Published private(set) var isEnabled: Bool` and `func set(_ enabled: Bool)`;
reading it never writes the key. Views, the card editor and Settings observe `IntakeSettings.flag`.
This stage declares no flag class of its own.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `noop.intakeEnabled` | Bool | `false` | The feature flag. Off: no card, no screen, no tick, no reminder, no Health read, no widget data, legacy resolver policy |
| `intake.source` | String | absent (`none`) | `none`, `appleHealth` or `quickAdd`. Path C is `none` |
| `intake.targets` | String | absent | JSON object, sorted keys: `{"energyHardFloorKcal":2100,"energyHighKcal":2600,"energyLowKcal":2400,"v":1}`. Any key may be omitted. An object that fails to parse or fails `IntakeTargets.isValid` is treated as absent and the screen says the targets need attention |
| `intake.zoneLog` | String | absent | JSON array of `{"from":0,"tz":"Etc/UTC"}`, ascending |
| `intake.health.sources` | String | absent (all) | JSON array of admitted bundle ids |
| `intake.health.knownSources` | String | absent | JSON object: bundle id → `{"lastSeenDay":"2030-12-09","name":"Fixture Food"}`. For the source picker and the "two apps" line |
| `intake.health.backfilled` | Bool | `false` | The 90-day backfill has run |
| `intake.supplement.questions` | String | absent | JSON array, at most four canonical Journal questions, in display order |
| `intake.cutoff.enabled` | Bool | `false` | The reminder switch |
| `intake.cutoff.minuteOfDay` | Int | 1260 | Minutes after local midnight. Also closes the day for §7.5 when set, whether or not the reminder is on |
| `intake.cutoff.timeSet` | Bool | `false` | The owner has chosen a cutoff time. False: the day closes only at midnight |
| `intake.quickAdd.presets` | String | absent | JSON array, at most six `{"energyKcal":150,"label":"Fixture shake","proteinGrams":30}` |
| `intake.entries.<yyyy-MM-dd>` | String | absent | That day's quick-add entries (§9.3) |

The protein floor is **not** in this table. `IntakeSettings.proteinFloorGrams` reads
`CutScorecardSettings.parameters.proteinFloorGrams`, and `setProteinFloorGrams(_:)` writes it
through the same `parameters` setter the rules sheet uses, whatever the state of the scorecard flag. `IntakeSettings.targets(on day: String) -> IntakeTargets`
combines that floor with `intake.targets`. It returns the same targets for every day: the parameter
exists so a later dated override needs no change at any call site, and nothing reads it today.

Reading never rewrites a stored string (stage 1 R30).

#### 9.2.1 The settings type

```swift
final class IntakeSettings {
    static let enabledKey = "noop.intakeEnabled"
    static let sourceKey = "intake.source"
    static let targetsKey = "intake.targets"
    static let zoneLogKey = "intake.zoneLog"
    static let healthSourcesKey = "intake.health.sources"
    static let healthKnownSourcesKey = "intake.health.knownSources"
    static let healthBackfilledKey = "intake.health.backfilled"
    static let supplementQuestionsKey = "intake.supplement.questions"
    static let cutoffEnabledKey = "intake.cutoff.enabled"
    static let cutoffMinuteOfDayKey = "intake.cutoff.minuteOfDay"
    static let cutoffTimeSetKey = "intake.cutoff.timeSet"
    static let quickAddPresetsKey = "intake.quickAdd.presets"
    static let entriesKeyPrefix = "intake.entries."
    static let maxSupplements = 4
    static let maxPresets = 6

    /// The one observable copy of `noop.intakeEnabled`.
    @MainActor static let flag = ObservableDefaultsFlag(key: enabledKey)

    /// `scorecard` nil: a `CutScorecardSettings` over the same `defaults`.
    init(defaults: UserDefaults = .standard, scorecard: CutScorecardSettings? = nil)

    var isEnabled: Bool { get set }
    var source: IntakeSourceSetting { get set }          // an unknown stored string reads as .none
    var healthReadEnabled: Bool { get }                  // isEnabled && source == .appleHealth

    /// The stored range and hard floor, without the protein floor. Nil when absent or unusable.
    var storedTargets: IntakeTargets? { get }
    /// True when `intake.targets` holds a string that does not parse or is not valid.
    var targetsNeedAttention: Bool { get }
    /// Writes `intake.targets` with sorted keys and `"v":1`. Ignores `proteinFloorGrams`.
    /// Returns false and writes nothing when the range is not valid.
    @discardableResult func setTargets(_ targets: IntakeTargets) -> Bool
    /// The floor from the scorecard rules plus `storedTargets`. The same for every `day`.
    func targets(on day: String) -> IntakeTargets

    /// `scorecard.parameters.proteinFloorGrams`: whole grams by stage 1 R45, or nil.
    var proteinFloorGrams: Double? { get }
    /// Nil clears the floor. Otherwise assigns `grams` to `scorecard.parameters.proteinFloorGrams`
    /// through the `parameters` setter (stage 1 §9.2). Returns false and writes nothing when
    /// `CutScorecardSettings.isWholeGramProteinFloor(grams)` is false. No other check is made.
    @discardableResult func setProteinFloorGrams(_ grams: Double?) -> Bool

    var zoneLog: [IntakeZoneSegment] { get set }
    var admittedHealthSources: Set<String>? { get set }  // nil: every source
    struct KnownSource: Equatable, Codable { let name: String; let lastSeenDay: String }
    var knownHealthSources: [String: KnownSource] { get }
    func recordHealthSource(bundleId: String, name: String, day: String)
    var healthBackfilled: Bool { get set }

    var supplementQuestions: [String] { get }            // display order, at most `maxSupplements`
    /// False and no write when the list is full or already holds the question.
    @discardableResult func addSupplementQuestion(_ question: String) -> Bool
    func removeSupplementQuestion(_ question: String)

    var cutoffEnabled: Bool { get set }
    var cutoffMinuteOfDay: Int { get set }               // default 1260; clamped to 0...1439 on write
    var cutoffTimeSet: Bool { get set }

    struct Preset: Equatable, Codable { let label: String; let proteinGrams: Double?; let energyKcal: Double? }
    var quickAddPresets: [Preset] { get set }            // at most `maxPresets`; extra items are dropped on write

    /// Journal rows the in-app Coach may read (§10.6.1).
    static func coachVisible(_ entries: [JournalEntry], defaults: UserDefaults = .standard) -> [JournalEntry]
}
```

Every getter reads the defaults at each access and caches nothing, so a restored backup is seen by
the next read. No getter writes.

**The floor field.** The whole-gram rule is stage 1's ruling R45 (`stage-1.md` §9.2 and §10.5) and is
not restated here as a second rule. This stage's field is the second editor that ruling names, and it
does exactly what the ruling says of both editors: a whole-number keypad; the entry is valid exactly
when `CutScorecardSettings.isWholeGramProteinFloor` is true for it; an entry for which it is false
marks the field ("Enter whole grams") and nothing is saved; the editor does not round what was
typed; an empty field means no floor and is saved as nil. The range (1 to
`CutScorecardSettings.proteinFloorMaximumGrams`) is stage 1's and is not written a second time in
this stage's code. The setter writes through `CutScorecardSettings.parameters`, so the stored number
is whatever stage 1's setter stores.

A fractional floor stored before R45, or restored from an older backup, reads as the nearest whole
gram through `CutScorecardSettings.parameters`; the field opens showing that whole number, as the
rules sheet does, and the stored string becomes whole at the next save from either editor. This
stage never sees a fraction, so it has no state, string or accessor for one. The one stored floor
either editor would refuse is one above stage 1's maximum, which only a hand-edited settings string
can hold; as stage 1 §9.2 says of both editors, the field then opens marked until a floor in range
is typed.

### 9.3 Quick-add entries (Path B)

The hydration pattern: a per-day entry list in defaults, and the canonical day total in
`metricSeries` (`Strand/Data/HydrationStore.swift:31-36`, `:202-218`, `:254-262`).

```swift
struct IntakeEntry: Identifiable, Equatable, Codable {
    let id: UUID
    var loggedAt: Date
    let day: String              // decided at save from the zone log; never re-keyed
    var proteinGrams: Double?    // nil: this entry says nothing about protein
    var energyKcal: Double?
    var label: String?           // at most 40 characters; stays on the phone
}

@MainActor
final class IntakeQuickAddStore {
    enum Failure: Error, Equatable { case nothingToSave, invalidAmount, storeUnavailable }
    init(repository: Repository, settings: IntakeSettings, defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init,
         zoneIdentifier: @escaping () -> String = { TimeZone.current.identifier })
    func entries(day: String) -> [IntakeEntry]                    // ascending by loggedAt, then id
    @discardableResult func add(proteinGrams: Double?, energyKcal: Double?, label: String?,
                                at instant: Date) async throws -> IntakeEntry
    func update(_ entry: IntakeEntry) async throws
    func delete(id: UUID, day: String) async throws
    /// Re-derives the stored totals for `day` from its entries.
    func rebank(day: String) async throws
}
```

- `add` rejects an entry with neither amount (`nothingToSave`) and any amount that is not finite,
  is negative or is above 100 000 (`invalidAmount`). Zero is allowed.
- Every change writes the entry list first, then calls `rebank`. `rebank` sums the entries
  (§7.2 step 3), upserts or deletes `protein_g` and `calories_in`, and upserts `intake_read_at = now`;
  when the day has no entries left it deletes all three rows.
- An interruption between the two writes leaves the list ahead of the total. Opening the intake
  screen rebanks today and yesterday, so the total follows the list.
- A day that has a stored total but no entry list (after a restore: the database carries totals,
  defaults do not carry entries) shows one synthetic row, "Restored total", which can be replaced.
  Replacing it writes one real entry holding the old amounts and proceeds as any edit.
- Entries can be added, edited and deleted for today and the seven days before it, the reach the
  Journal has (`Strand/Screens/JournalLogCard.swift:378`).

### 9.4 The resolver

`Strand/Data/IntakeResolver.swift`, pure, no store access:

```swift
enum IntakeSource: String { case appleHealth, quickAdd, nutritionCsv }
enum IntakeSourceSetting: String { case none, appleHealth, quickAdd }
enum IntakePolicy: Equatable { case legacy, unified(active: IntakeSourceSetting) }

struct ResolvedIntakeValue: Equatable {
    let value: Double
    let source: IntakeSource
    let readAtEpochSeconds: Int?      // nil for a CSV value, which has no read time
}

struct ResolvedIntakeDay: Equatable {
    let day: String
    let protein: ResolvedIntakeValue?
    let energy: ResolvedIntakeValue?
}

struct IntakeCandidates {
    var appleHealth: [IntakeStoredDay]
    var quickAdd: [IntakeStoredDay]
    var nutritionCsv: [IntakeStoredDay]
}

enum IntakeResolver {
    /// The one place a flag state and a source setting become a policy.
    static func policy(flagEnabled: Bool, sourceSetting: IntakeSourceSetting) -> IntakePolicy
    /// The sources consulted, first match wins.
    static func order(_ policy: IntakePolicy) -> [IntakeSource]
    /// One entry per day that has any admitted value, ascending.
    static func series(candidates: IntakeCandidates, policy: IntakePolicy) -> [ResolvedIntakeDay]
    static func resolve(day: String, candidates: IntakeCandidates,
                        policy: IntakePolicy) -> ResolvedIntakeDay?
}
```

| Policy | Order |
|---|---|
| `legacy` (flag off) | `nutritionCsv` only. Exactly today's behaviour |
| `unified(.appleHealth)` | `appleHealth`, `quickAdd`, `nutritionCsv` |
| `unified(.quickAdd)` | `quickAdd`, `appleHealth`, `nutritionCsv` |
| `unified(.none)` | `appleHealth`, `quickAdd`, `nutritionCsv` |

- For each day and each nutrient independently, the value is the first source in the order that
  has a finite, non-negative value for that day.
- **Sources are never summed.** A meal in the food app and the same meal quick-added would count
  twice otherwise. The cost is stated in question I3.
- `resolve` is `series(...).first { $0.day == day }`.
- The lower-priority sources exist so that history survives a change of source: days logged by
  quick-add before a move to Apple Health, and days imported by CSV before either.

`IntakeProvider` (`@MainActor`, observable, `Strand/Data/IntakeProvider.swift`) follows
`BodyMeasurementProvider`: it fetches the candidates through `Repository.series(key:source:)` for the
three source ids (`noop-intake-health` for the `appleHealth` candidates, `noop-intake` for `quickAdd`,
`nutrition-csv`) and the three keys, holds the resolved series, exposes a `revision`, and refreshes
after every completed repository refresh, after every `IntakeHealthSync` write and after every
`IntakeQuickAddStore` write (stage 1 R32). With the flag off it does no work when nothing asks.

```swift
init(repository: Repository, settings: IntakeSettings)
/// The app's one instance for a repository, over the standard defaults (the pattern of
/// `BodyMeasurementProvider.live`, `BodyMeasurementProvider.swift:128`).
static func live(repository: Repository) -> IntakeProvider
static let healthSourceId = "noop-intake-health"
static let quickAddSourceId = "noop-intake"
static let csvSourceId = "nutrition-csv"
func refresh() async
var revision: Int { get }
func day(_ day: String) -> ResolvedIntakeDay?
func series() -> [ResolvedIntakeDay]
/// What the scorecard reads. One entry per day with a protein value.
func proteinDays() -> [CutScorecardProteinDay]
var lastHealthOutcome: IntakeHealthSync.Outcome? { get }
var lastHealthAttemptAt: Date? { get }
```

**The scorecard's switch.** `CutScorecardInputBuilder.build` (`:50-52`) stops reading the store and
takes `intake.proteinDays()` after `await intake.refresh()`. The builder's initialiser becomes

```swift
init(repository: Repository, provider: BodyMeasurementProvider, settings: CutScorecardSettings,
     intake: IntakeProvider, timeZone: @escaping () -> TimeZone = { TimeZone.current })
```

and its two private constants `nutritionSource` and `proteinKey` (`:13-14`) are deleted.

This edit is written **after** stage 2's move of `evaluateStored` into the builder as
`evaluation(today:)` (`stage-2.md` §8.2). That function calls `build`, so the screen, the card and
the coach packet all receive the resolved protein days through one evaluation. The construction
sites updated in the same commit:

| Site | Change |
|---|---|
| `Strand/Data/CutScorecardModel.swift` | `init` gains `intake: IntakeProvider? = nil` (nil: `IntakeProvider.live(repository:)`) and passes it where it constructs the builder. One parameter and one argument; nothing else in the file |
| `Strand/Data/CoachPacketAssembler.swift` (stage 2) | `init` gains `intake: IntakeProvider? = nil` with the same meaning and passes it where it constructs the builder. The assembler reads no intake itself |
| `StrandTests/CutScorecardInputBuilderTests.swift:106`, `StrandTests/OneNumberPerVariableTests.swift:177`, `StrandTests/BodyMeasurementSingleSourceTests.swift:145` | Each builder construction gains `intake: IntakeProvider(repository: repo, settings: IntakeSettings(defaults: defaults))` over the test's own defaults suite |

With `noop.intakeEnabled` off the policy is `legacy` and the list is the `nutrition-csv` series, value
for value what the builder passes today; the existing tests
`testProteinDaysComeFromTheNutritionSeries` and `testNoNutritionSeriesYieldsNoProteinDays`
(`StrandTests/CutScorecardInputBuilderTests.swift:377`, `:404`) keep passing unchanged apart from the
added initialiser argument. With it on, the scorecard's protein row, the card, the intake screen and
the widget are four reads of one list. The scorecard's row gains the source caption and opens the
intake screen (R41: every place that shows the value offers the way to correct it).

Today is never judged by the scorecard: its window ends the day before the weigh-in
(`CutScorecard.swift:704`), so a day still in progress cannot count as a missed floor.

### 9.5 One clock

Each render and each publish resolves one value and passes it down:

```swift
struct IntakeClock: Equatable {
    let now: Date
    let today: String            // dayKey(now) under the stored zone log
    let minuteOfDay: Int         // in the current zone
    let dayIsOpen: Bool          // §7.5, for `today`
}
```

Nothing below the screen model reads `Date()`. The card, the ring, the freshness line and the widget
reading built for one render share one `IntakeClock`.

**Today on the Today screen.** The redesign passes the selected *logical* day (04:00 rollover).
Under the unified policy, when the selected day is the current day the card shows the calendar day
(stage 1 R33), so after midnight it shows the new day's intake, not yesterday's. When a past day is
selected the card shows that day's closed total, without "remaining".

### 9.6 Backup

| Canonical key | JSON kind | Joins the Swift whitelist | Kotlin |
|---|---|---|---|
| `intake.targets` | String | **Yes**: one entry in `BackupSettings.whitelist` and one identity entry in `BackupSettings.appleDefaultsKey` (`Packages/WhoopStore/Sources/WhoopStore/BackupSettings.swift`) | Not updated, by the owner's decision |
| `intake.supplement.questions` | String | **Yes**, the same two entries | Not updated, by the owner's decision |
| `noop.intakeEnabled`, `intake.source`, `intake.health.*`, `intake.zoneLog`, `intake.cutoff.*`, `intake.entries.*`, `intake.quickAdd.presets` | — | No. Per install: they depend on this phone's Health permission, notification permission, zone history and food app | — |

The daily totals are `metricSeries` rows and ride the database backup as every series does. The
supplement answers are Journal rows and do too. The protein floor is already carried inside
`cutScorecard.rules`.

Both keys are listed in the comment block for fork-only keys that the shared scaffolding commit puts
above the Swift whitelist; this stage adds its two names to that block in the commit that adds the
entries. `BackupSettings.swift` and `BackupSettingsTests.swift` have one writer at a time across
stages. This stage's entries are added in its place in the shared-file order (§14.3), in the
orchestrator's commit 3-6h.

Both values sit in clear text in the backup's `settings.json`: the calorie range and hard floor as
numbers, and the supplement questions, which contain the supplement names the owner typed. The
backup file is the owner's to keep private (question G5).

**The drift this creates (Android, R43).** The whitelist is described in the repository guidance as a
byte-identical contract between the two platforms; this stage knowingly leaves the Kotlin side
behind. Android's codec iterates its own whitelist and drops any key it does not list
(`android/app/src/main/java/com/noop/data/BackupSettings.kt:92-107`), so a backup made on the iPhone
and restored on Android loses `intake.targets` and `intake.supplement.questions` silently, and a
backup then made on Android does not contain them. The database rows under `noop-intake-health` and
`noop-intake` survive on both but nothing on Android reads them. No Kotlin is edited.

The marker catalogue (`Packages/StrandImport/Sources/StrandImport/MarkerCatalog.swift`) is **not
edited** by this stage on either platform.

## 10. Screens and states

Frames are designed at G1 in `design/round-s3-intake/`. Three surfaces this stage adds to are shared
with other stages and are laid out once, in the combined frame set drawn by the orchestrator's
designer (Health card, Settings, scorecard screen). That frame set is the authority for them: the
Intake card in Settings (§10.5), the Intake row in the Health tab (§10.9) and the protein row's
caption on the scorecard screen (§10.4) are drawn there, not in this stage's round.

**This stage's place in Settings and in the Health tab.** Intake is third in the one order both
surfaces use, top to bottom: directly below Coach packet and directly above Body record, or next to
whichever neighbour is present when one of those is not.

This section fixes what each surface must be able to show. Every state needs a frame at the default
text size and at `accessibility5`.
Charts show the curve and its fill; the floor and the range are never drawn as a line or a band.

### 10.1 Protein card in Your Cards

`DashboardCard.protein`. Not in `defaultSelection`, redesign-only (`isRedesignOnly`,
`DashboardCards.swift:60`), a value card. It renders only while the flag is on:
`TodayCardResolver.renderList` and `gatedCaption` (`Strand/Data/TodayCardReadout.swift:116-137`) gain
an `intakeEnabled` parameter defaulting to `false`. The editor hides it while the flag is off, as it
hides the scorecard (`Strand/Screens/TodayCustomizationSheet.swift:32`, `:150`). It taps through to
the intake screen (`TodayCardReadout.Tap` gains `intake`).

| State | Value | Caption |
|---|---|---|
| Loading | skeleton | — |
| No source chosen | dash | "Choose where intake comes from" |
| No floor set | grams so far, no ring | "No floor set" |
| Not measured today | dash, empty ring | "Nothing logged today" |
| Below the floor | grams, partial ring | "N g to your floor · HH:mm" |
| At the floor | grams, complete ring | "Floor met · HH:mm" |
| Above the floor | grams, complete ring | "+N g over your floor · HH:mm" |
| Stale (Health source, read more than three hours ago, today) | grams in the tertiary colour | "Last read HH:mm" |
| Health read failed and nothing stored for today | dash | "Could not read Apple Health" |
| A past day selected, measured | that day's grams, ring as it ended | "Day total" |
| A past day selected, not measured | dash | "Not measured" |
| Targets unreadable | grams | "Your targets need attention" |

HH:mm is the read time (Health) or the last entry time (quick-add). A CSV value has no time and its
caption ends "· imported".

### 10.2 Intake screen

Pushed as `RedesignRoute.intake`. Sections, top to bottom: protein ring and numbers; calories line;
supplements (§10.6); the last 28 days of protein as a curve with fill, days at or above the floor
marked by the point style; source and freshness; entries (Path B) or the Health note (Path A).

| State | What shows |
|---|---|
| Loading | Skeletons for the ring and the chart |
| Flag on, no source | The setup prompt: the three choices of §10.5, each with one sentence |
| Path C (source `none` kept) | Only the supplements section and a row to the cutoff setting. No ring, no chart |
| No floor set | The numbers without a ring, and a row "Set your protein floor" |
| Not measured today | Empty ring, "Nothing logged today", and the source line |
| Below, at, above the floor | Ring and lines per §7.4 |
| Energy: not measured, no range, so far, in range, above range, below range, below hard floor | Line per §7.5 and §11 |
| One source wrote today | "From <app> · read HH:mm" |
| Two or more Health sources wrote today | "Two apps wrote today: A and B. Both are counted." with a row "Choose one" |
| Stale | The time in the secondary colour and a "Read again" button |
| Read failed | "Apple Health could not be read at HH:mm. Showing the last figures." |
| Window came back empty | "Apple Health returned no food entries. If you log in <app>, check that it is allowed to write to Health." No claim that access was denied: the app cannot know |
| History, fewer than two days | The chart area says "More days will appear here" |
| A day edited or deleted at the source | The figure changes at the next read; no marker |
| Value from an older source (CSV or the non-active source) | The source caption names it |
| Targets unreadable | "Your targets need attention" with a row to settings |
| Largest text size | Ring above the numbers, single column |

**Correcting a value (R41).** Path A: the figure is the food app's; the screen says "Edit this in
<app>. NOOP reads it again when you return." and offers "Read again". Path B: every entry opens for
edit or delete. CSV: a row to Data Sources.

### 10.3 Quick-add sheet (Path B)

| State | What shows |
|---|---|
| Default | Protein (g) and Calories (kcal) fields, either may be left empty; presets as chips; Save |
| Preset tapped | Both fields filled; Save enabled |
| Nothing entered | Save disabled |
| Invalid amount | Field message "Enter a number from 0 to 100000" |
| Backdating | A day picker: today and the seven days before |
| Editing an entry | Same sheet, with Delete |
| Restored total row | "Restored total" with Replace |
| Save failed | "Could not save. Nothing was changed." |
| No presets yet | A row "Add a preset" |

### 10.4 Scorecard protein row

Unchanged strings (`stage-1.md` §11). With the intake flag on it gains a source caption ("Apple
Health", "Entered here", "CSV import", or "Several sources" when the seven days mix them) and opens
the intake screen. With the flag off the row is exactly stage 1's.

`StrandiOS/Scorecard/ScorecardView.swift` is a shared file. This stage's edit (the protein row's
caption and tap) is made in its place in the shared-file order (§14.3), in the orchestrator's commit
3-6h.

### 10.5 Settings

A card in Settings, iPhone only, in the section that holds the scorecard card
(`Strand/Screens/SettingsView.swift:466`, `:1854-1977`), third in the Settings order (§10). The edit
to `SettingsView.swift` is made in this stage's place in the shared-file order (§14.3), in the
orchestrator's commit 3-6h, and `Strand` is built after it because the file is shared with macOS.

The card holds the feature switch, so the switch and one sentence are shown whether the flag is on or
off; every other row of the card is present only while `noop.intakeEnabled` is on. Rows: the feature
switch; source (None, Apple Health, Enter here); protein floor (the same stored value as the rules
sheet's "Daily floor", whole grams, §9.2.1); calorie range low and high; hard floor; Health apps to
count (Path A, when more than one is known); supplements; cutoff time; cutoff reminder.

| State | What shows |
|---|---|
| Flag off | Only the switch and one sentence |
| Flag on, source None | The other rows; a caption that the card and widget have nothing to show |
| Choosing Apple Health | HealthKit's sheet for the two types, once; then a first read |
| Apple Health chosen, Health unavailable or the build lacks the entitlement | The row reverts and says why, using the bridge's existing states (`HealthKitBridge.swift:20-28`, `:91-95`) |
| Range invalid (low above high, hard floor above low) | The field is marked and nothing is saved |
| Protein floor entry for which `CutScorecardSettings.isWholeGramProteinFloor` is false | The field is marked "Enter whole grams" and nothing is saved (stage 1 R45's rule for both editors) |
| Protein floor field opened | Shows the stored floor as a whole number with the unit `g`, the value `CutScorecardSettings.proteinFloorWholeGrams`; empty when no floor is set. A stored floor above stage 1's maximum (a hand-edited settings string) opens marked, as in the rules sheet |
| Supplements row | Caption: "Supplements listed here are left out of the Coach." |
| Reminder: off, on, denied by the system | As the weigh-in reminder rows behave (`SettingsView.swift:1992-2031`) |
| Reminder near the wind-down nudge | Caption: "Silent on days when it falls within 30 minutes of your wind-down reminder." |

### 10.6 Supplement tick

A supplement is a Journal question. Adding one named N creates the canonical question
`"Did you take N?"` through `JournalCatalogStore.addCustom(_:kind:group:)` with kind `.bool` and group
`.supplements` (`Strand/Data/JournalCatalog.swift:261-270`), or adopts an existing Journal item the
owner picks (a starter of that shape exists, `:40`). The canonical string is data and is never
localised (`:28-30`).

```swift
@MainActor
struct IntakeSupplementTick {
    init(repository: Repository, settings: IntakeSettings)
    /// question → true (ticked), false (answered no in the Journal), nil (not recorded)
    func states(day: String) async -> [String: Bool?]
    func set(_ ticked: Bool, question: String, day: String) async
}
```

- Ticking writes `saveJournalAnswer(day:question:answeredYes: true)`; unticking calls
  `clearJournalAnswer` (`Repository.swift:2730-2735`, `:2763-2766`). An unticked box is "not
  recorded", never a recorded "no".
- The day is the calendar day, `Repository.localDayKey`, the key the Journal card itself uses
  (`JournalLogCard.swift:53-56`). The tick and the Journal card are two controls over one row, so
  they cannot disagree.
- The box shows ticked only when the stored answer is yes.

| State | What shows |
|---|---|
| No supplement configured | The section is absent; settings offers "Add a supplement" |
| Not recorded today | Empty box, the supplement's display name |
| Ticked | Filled box and the time is not shown (the Journal stores none) |
| Answered "no" in the Journal | Empty box, caption "Marked not taken in Journal" |
| A past day selected | That day's state, editable within the Journal's reach |
| Four configured | Four rows; the add row is hidden |

No count of consecutive days is shown anywhere.

#### 10.6.1 Supplement questions stay out of the in-app Coach

A supplement name may be a medication name. Journal rows reach the in-app Coach at one place: the
behaviour ranking in `onDeviceSignalsBlock` (`Strand/AI/AICoach.swift:1250`,
`let entries = await repo.journalEntries()`), whose sentences name the question. That text goes to
the Coach's network provider when the Coach is on, and the Coach's output becomes the Coach brief
notification and the Coach brief widget. So:

```swift
/// `entries` without every row whose question is listed in `intake.supplement.questions`.
/// Order is preserved. With no list stored, the input is returned unchanged.
static func coachVisible(_ entries: [JournalEntry], defaults: UserDefaults = .standard) -> [JournalEntry]
```

- A row is removed when its `question`, with leading and trailing whitespace removed, equals a
  listed question under a case-insensitive comparison. Nothing else about a row is examined.
- The one edit to `AICoach.swift` is that line:
  `let entries = IntakeSettings.coachVisible(await repo.journalEntries())`.
- The exclusion follows the list, not the feature flag: a question stays excluded while it is in
  the list even if Intake is later switched off. Removing a supplement from the list ends its
  exclusion.
- With the list absent, which is the state of every install that has not added a supplement, the
  function is the identity and the Coach context is byte-for-byte what it was. Stage 2's
  byte-identity tests are unaffected.
- **Adopting an existing Journal item changes the Coach.** If the owner adopts an existing Journal
  question as a supplement, that question leaves the Coach's behaviour ranking from then on,
  including its earlier answers. The settings caption says so (§10.5).
- The on-device readers are not filtered: the Journal card, the Insights screens and the illness
  watch's confounder flags keep reading every row. None of them leaves the phone or prints a
  question in a notification or widget.
- The supplement list is also not read by any widget, notification or App Group payload (§12.8).

`AICoach.swift` is edited in one fixed order: Lab Book ownership, then the stage 2 extraction, then
this stage's one-line supplement exclusion, then stage 4. This stage is third. The line is written
against the file as the stage 2 extraction leaves it and touches no other line; stage 2's
byte-identity suite is run unchanged after it and stays green.

### 10.7 Cutoff reminder

Opt-in, off by default. Title: "Food cutoff". Body: "Your cutoff time is now." No amount, no floor,
no judgement and no supplement name ever appears in a notification. One a day at most.

| State | Behaviour |
|---|---|
| Off | No pending request |
| On, permission granted | Seven weekday requests |
| On, wind-down within 30 minutes on some weekdays | Those weekdays are silent and passive |
| Permission denied | The switch reverts; a row to system Settings |
| Flag switched off | All seven removed |

Notification budget after this stage: the weekly weigh-in reminder and this daily one, both opt-in.

### 10.8 Widget

Kind `PersonalProteinWidget`, display name "Protein", in `StrandiOSWidgets/PersonalProteinWidget.swift`
with its own timeline provider reading `WidgetSnapshot.load()?.personal?.intake`. It is appended to
`NOOPWidgetBundle` (`StrandiOSWidgets/NOOPWidgetBundle.swift:11-19`). Existing kinds, their kind
strings, families and order are unchanged. Families: `systemSmall`, `systemMedium`,
`accessoryRectangular`, `accessoryCircular`. It reuses `WidgetHeader`, `WidgetNumber` and `WidgetRing`
(`StrandiOSWidgets/NOOPWidget.swift:416`, `:440`, `:486`).

Payload, added to `StrandiOSShared/PersonalWidgetMetrics.swift`:

```swift
public struct PersonalIntakeReading: Codable, Equatable {
    public enum Source: String, Codable { case appleHealth, quickAdd }
    public let day: String
    public let proteinGrams: Int?        // shown grams; nil: not measured
    public let floorGrams: Int?          // shown floor; nil: no floor set
    public let source: Source?
    public let readAt: Date?             // nil: unknown
    public static func reading(day: String, progress: IntakeProteinValues, source: Source?,
                               readAt: Date?) -> Self
    /// Seconds after `readAt` at which a Health figure is drawn as stale.
    public static let staleAfter: TimeInterval = 3 * 3600
}
// PersonalWidgetMetrics gains: public var intake: PersonalIntakeReading?
// and: public func todayIntake(now: Date, calendar: Calendar = .current) -> PersonalIntakeReading?
```

`IntakeProteinValues` is a three-field Foundation-only struct (`shownGrams`, `shownFloorGrams`,
`remainingGrams`) defined in the same file, because the shared file cannot import the analytics
package; `IntakePresenter.widgetReading` fills it from `IntakeProteinProgress`.

- The new field is optional and synthesised `Codable` omits a nil optional, so with the flag off
  the encoded payload is byte-identical to today's, and a payload written by an older build decodes
  with `intake == nil`.
- `todayIntake` returns nil for any day but the entry's, the rule `todaySteps` follows (`:28-31`).
- **A value is never drawn without its time.** A reading with a figure and no `readAt` draws the
  no-data state. A CSV-sourced value is therefore never published (it has no read time).
- Calories, supplement names, entry labels and source app names are not in the payload.
- The timeline has entries at now, at `readAt + staleAfter` when that is in the future (so the
  stale state appears without the app), and at the next local midnight (so yesterday's figure
  expires), with the 15-minute policy the other personal widgets use
  (`StrandiOSWidgets/PersonalMetricsWidgets.swift:22-32`).

| State | Small | Medium | Rectangular (Lock Screen) | Circular (Lock Screen) |
|---|---|---|---|---|
| Below the floor | Ring; "N g to go"; "as of HH:mm" | Ring; grams of floor; "N g to go"; source and "as of HH:mm" | "Protein"; "N g to go"; "HH:mm" | Gauge with N |
| At or above the floor | Complete ring; "Floor met"; "as of HH:mm" | Adds "+N g over" when above | "Floor met"; "HH:mm" | Full gauge, a tick |
| No floor set | Grams; "No floor set"; "as of HH:mm" | Same | Grams; "HH:mm" | Grams |
| Nothing logged today | Empty ring; "Nothing logged today" | Same, with the floor | "Nothing logged today" | Empty gauge, dash |
| Stale (Health, older than three hours) | Figure in the tertiary colour; "Last read HH:mm" | Same; adds "Open NOOP to refresh" | "Last read HH:mm" | Dimmed gauge |
| Not set up (flag off, source None, or never published) | "Set up in NOOP" | Same | Same | Dash |
| Gallery placeholder | No sample figure, as the other personal widgets do (`PersonalMetricsWidgets.swift:11-14`) | Same | Same | Same |

A new kind appears in the widget gallery even while the flag is off; a widget extension cannot hide
one at run time. It then draws "Set up in NOOP" (question I6).

### 10.9 Health tab row

One row in the Health tab's "More health" card (`StrandiOS/Redesign/RedesignHealthView.swift:472-482`),
third in the order of §10. It is a private view, `HealthIntakeRow`, built like `HealthScorecardRow`
(`:526-537`): a `NavigationLink(value: RedesignRoute.intake)` around a `NoopListRow` titled "Intake"
with the icon of `DashboardCard.protein`. `RedesignHealthView` observes `IntakeSettings.flag` and
mounts the row only while it is on; with the flag off the row is absent and the card is exactly as
it was. Dividers between the stage rows and the first existing row are as the combined frame shows.

The row carries no value and no caption. Today's grams are shown on the card, the screen and the
widget, each with its time; a fourth copy without a time is not added.

| State | What shows |
|---|---|
| Flag off | No row |
| Flag on, any source, any path | The row "Intake"; tapping pushes the intake screen (§10.2) in whatever state that screen is in |

Under Path C this row and the Settings card are the two ways to the intake screen.

## 11. User-facing strings

All through the String Catalog (`Strand/Resources/Localizable.xcstrings` for the app,
`StrandiOSWidgets/Localizable.xcstrings` for the widget; ten locales). Pure functions return cases
and numbers; `IntakePresenter` turns them into strings. English sources:

| Where | String |
|---|---|
| Card title and subtitle | "Protein" / "Today against your floor" |
| Protein states | "%lld g to your floor", "Floor met", "+%lld g over your floor", "No floor set", "Nothing logged today", "Day total", "Not measured" |
| Energy title | "Calories eaten" |
| Energy states | "%lld kcal so far", "%lld kcal to the bottom of your range", "In your range of %lld to %lld kcal", "%lld kcal above your range", "Below your range of %lld to %lld kcal", "Below your floor of %lld kcal", "No range set", "Not measured" |
| Freshness | "Read %@", "Last read %@", "Entered %@", "imported", "Read again" |
| Sources | "Apple Health", "Entered here", "CSV import", "Several sources", "From %@", "Two apps wrote today: %@ and %@. Both are counted.", "Choose one" |
| Read problems | "Could not read Apple Health", "Apple Health could not be read at %@. Showing the last figures.", "Apple Health returned no food entries. If you log in %@, check that it is allowed to write to Health." |
| Correcting | "Edit this in %@. NOOP reads it again when you return.", "Edit entry", "Delete entry", "Restored total", "Replace" |
| Quick-add | "Add food", "Protein", "Calories", "Label (optional)", "Enter a number from 0 to 100000", "Add a preset", "Could not save. Nothing was changed." |
| Setup | "Choose where intake comes from", "Apple Health: read what your food app writes", "Enter here: add protein and calories yourself", "None: supplements and the cutoff reminder only" |
| Settings | "Intake", "Source", "Protein floor", "Calorie range", "Hard floor", "Apps to count", "Supplements", "Add a supplement", "Cutoff time", "Cutoff reminder", "Silent on days when it falls within 30 minutes of your wind-down reminder.", "Your targets need attention" |
| Supplements | "Supplements", "Marked not taken in Journal", "Supplements listed here are left out of the Coach." |
| Floor field | "Enter whole grams" (the mark on an entry the field refuses; there is no string for a stored fraction, because none is ever read) |
| Health tab row | "Intake" (the Settings card's title string) |
| Chart | "More days will appear here" |
| Notification | "Food cutoff" / "Your cutoff time is now." |
| Widget | "Protein", "%lld g to go", "Floor met", "+%lld g over", "as of %@", "Last read %@", "Nothing logged today", "No floor set", "Set up in NOOP", "Open NOOP to refresh" |
| Health permission sentence (Path A, `project.yml:314`) | "NOOP reads your steps, workout summaries and, if you turn on Intake, the protein and energy your food app logs, from Apple Health on-device. Nothing leaves your device." |

None of these states or implies a health outcome. "Below your floor of N kcal" reports the owner's
own number against the owner's own setting and nothing more. No string praises, warns or urges.

## 12. Test plan

One named test per line. Names state the behaviour protected. Tests are written from this document
and §13 by an agent that does not see the implementation.

No test reads or writes `UserDefaults.standard`. Every settings object, provider, store and flag in
a test is built over a uniquely named suite that the test removes afterwards, so one test's
`noop.intakeEnabled` or supplement list cannot change another's result. Where a function takes
`defaults:` the suite is passed.

### 12.1 Pure logic — `Packages/StrandAnalytics/Tests/StrandAnalyticsTests/IntakeAggregationTests.swift`, `IntakeProgressTests.swift`, `IntakeFixture.swift`

Aggregation:
- `testSeveralEntriesInADayAreSummed`
- `testProteinAndEnergyAreSummedIndependently`
- `testADayWithEnergyButNoProteinHasNilProtein`
- `testAZeroAmountIsASampleNotAnAbsence`
- `testTwoSourcesAreBothCountedByDefault`
- `testAnExcludedSourceIsDroppedAndCounted`
- `testAnEditedEntryWithANewIdReplacesTheOldAmount`
- `testAnEditedEntryKeepingItsIdUsesTheNewAmount`
- `testADeletedEntryLowersTheTotal`
- `testADayThatLosesEveryEntryBecomesAnEmptyDay`
- `testEntryOneSecondBeforeMidnightBelongsToThatDay`
- `testEntryAtMidnightBelongsToTheNextDay`
- `testDuplicateIdsAreCountedOnceFirstWins`
- `testTheSameIdForTwoNutrientsIsNotADuplicate`
- `testNonFiniteAndNegativeAmountsAreRejectedAndCounted`
- `testAmountsAboveTheArithmeticLimitAreRejected`
- `testSamplesOutsideTheWindowAreRejectedAndCounted`
- `testAnInvalidWindowYieldsNothing`
- `testWindowValidityFollowsCanonicalDay` (for a spread of strings, the window is accepted exactly
  when `CanonicalDay.number` is non-nil for both ends and the first is not after the last)
- `testResultDoesNotDependOnInputOrder`
- `testFixtureDayTotals`

Zones:
- `testEmptyZoneLogCountsDaysInUTC`
- `testAnUnknownZoneIdentifierIsSkipped`
- `testInstantsBeforeTheFirstSegmentUseTheFirstSegment`
- `testEastwardChangeMidDayMovesLaterEntriesToTheNextDay`
- `testWestwardChangeCanPutALaterInstantOnAnEarlierDay`
- `testEveryInstantMapsToExactlyOneDayAcrossAChange`
- `testADayStoredBeforeAChangeKeepsItsTotalAfterIt`
- `testDaylightSavingShiftIsExactWithinOneSegment`
- `testAppendingTheSameZoneReturnsTheLogUnchanged`
- `testAppendingANewZoneAddsASegmentAtNow`
- `testAppendingWhenTheClockMovedBackReplacesTheLastSegment`
- `testTheLogKeepsItsFirstSegmentWhenTrimmedTo32`

Write plan:
- `testAWholeEmptyWindowWritesAndDeletesNothing`
- `testAnEmptyDayInsideANonEmptyWindowDeletesItsStoredRows`
- `testAnEmptyDayWithNothingStoredIsLeftAlone`
- `testNoDayIsEverWrittenAsZeroBecauseItIsEmpty`
- `testAnUnchangedTotalStillAdvancesItsReadTime`
- `testATotalWithinToleranceIsNotRewritten`
- `testProteinDisappearingFromADayDeletesOnlyTheProteinRow`
- `testChangedDaysListsOnlyDaysWhoseValuesMoved`
- `testDaysOutsideTheWindowAreNeverPlanned`
- `testPlanIsSortedAndStable`

Progress:
- `testBelowAtAndAboveTheFloor`
- `testRingIsCompleteAtTheFloorAndStaysComplete`
- `testGramsKeepCountingPastTheFloor`
- `testNoFloorHidesTheRingButKeepsTheNumber`
- `testAZeroOrNegativeFloorIsNoFloor`
- `testNotMeasuredHasNoNumberAndNoRing`
- `testRemainingIsNeverZeroBeforeTheFloorIsMet`
- `testShownGramsPlusRemainingEqualsTheShownFloor`
- `testMeetsFloorAgreesWithTheScorecardSignalOverASpread` (builds a `CutScorecardInput` whose seven
  days each hold one generated protein value, and asserts `daysAtOrAboveFloor` equals the count of
  `meetsFloor`)
- `testEnergySoFarMakesNoJudgementWhileTheDayIsOpen`
- `testEnergyAboveRangeIsReportedEvenWhileOpen`
- `testEnergyBelowHardFloorOnlyOnAClosedDay`
- `testEnergyBelowRangeInRangeAndBoundsAreInclusive`
- `testEnergyWithNoRangeShowsTheAmountAlone`
- `testInvalidTargetsBehaveAsNoRange`
- `testTargetsValidityRules`
- `testShownFloorEqualsTheStoredFloorForEveryWholeValue` (for each whole floor from 1 to 400 and a
  measured amount, `shownFloorGrams` equals the floor and equals `Int(floor.rounded())`)

### 12.2 Store — `Packages/WhoopStore/Tests/WhoopStoreTests/IntakeSeriesTests.swift`

- `testTotalsAndReadTimeAreWrittenInOneTransaction`
- `testIntakeWritesAndDeletesTouchNothingUnderAppleHealth` (seed `steps` and `weight` under
  `apple-health`; write and delete intake under `noop-intake-health`; assert both seeded rows
  untouched and that no intake key exists under `apple-health`)
- `testIntakeDeletionRemovesOnlyTheNamedDayAndKey`
- `testIntakeRowsSurviveDeletingAStrapsData` (R42: `deleteAllData` for a strap id leaves the rows
  under `noop-intake-health` and `noop-intake`)
- `testDeletingAppleHealthDataLeavesEveryIntakeRow` (`deleteAllData(deviceId: "apple-health")` with
  intake days older and newer than 30 days stored under both intake ids; every one remains)
- `testTheTwoIntakeIdsAreIndependent` (deleting a day and key under one id leaves the other id's
  row for the same day and key)
- Additions to `BackupSettingsTests.swift`, new methods only, placed after stage 1's and before any
  later stage's: `testIntakeTargetsAndSupplementQuestionsRoundTrip`,
  `testIntakeFlagSourceAndCutoffAreNotCarried`

### 12.3 App target — `StrandTests/`

`IntakeResolverTests.swift`
- `testLegacyPolicyReadsOnlyTheCsvSeries`
- `testUnifiedOrderForEachSourceSetting`
- `testSourcesAreNeverSummed`
- `testProteinAndEnergyResolveIndependently`
- `testOlderSourcesFillDaysTheActiveSourceLacks`
- `testANonFiniteOrNegativeStoredValueIsSkipped`
- `testPolicyIsLegacyWheneverTheFlagIsOff`

`IntakeSingleSourceTests.swift` (behavioural single-resolver assertion)
- `testCardScreenWidgetAndScorecardShareOneProteinNumber` (a store holding a Health total, a
  different quick-add total and a different CSV total for the same day; asserts the card readout,
  the screen model, the widget reading and the `CutScorecardInput.proteinDays` entry are the same
  number; then deletes the Health rows and asserts all four move together). The scorecard number
  is taken from `CutScorecardInputBuilder.evaluation(today:).input.proteinDays`, the one funnel
  stage 2 introduces, so the packet's scorecard lines are covered by the same assertion
- `testFloorHasOneStoredCopy` (set through `IntakeSettings`; read through `CutScorecardSettings`;
  and the reverse; assert `intake.targets` never contains a protein key)
- `testRingCompleteAndScorecardDayCountedAgree`
- `testShownFloorIsTheScorecardsWholeGramFloor` (for rules strings written directly with
  `"proteinFloorGrams"` 99.4, 99.5 and 100, and for no floor: the card readout's floor, the screen
  model's floor and the widget reading's `floorGrams` each equal
  `CutScorecardSettings.proteinFloorWholeGrams`, which is 99, 100, 100 and nil)

`IntakeHealthSyncTests.swift`
- `testDisabledSettingReadsAndWritesNothing`
- `testAFailedReadLeavesEveryStoredDayUntouched`
- `testAnEmptyWindowLeavesEveryStoredDayUntouched`
- `testASuccessfulReadWritesTotalsAndReadTimes`
- `testADeletedLastEntryRemovesTheDayAtTheNextRead`
- `testAStoreReadFailureWritesNothing`
- `testQueryWindowStartsFourDaysBeforeTheFirstWrittenDay`
- `testTheZoneLogIsExtendedBeforeTheRead`
- `testTheBackfillFlagIsSetOnlyAfterSamplesWereFound`
- `testTotalsAreWrittenUnderTheDedicatedIdAndNeverUnderAppleHealth`
- `testKnownSourcesAreRecordedWithTheirLastSeenDay`
- `testProviderRevisionMovesAfterAWrite`

`IntakeQuickAddStoreTests.swift`
- `testAddEditAndDeleteRederiveTheDayTotal`
- `testDeletingTheLastEntryRemovesTheDayRows`
- `testAnEntryWithNoAmountIsRejected`
- `testInvalidAmountsAreRejectedAndWriteNothing`
- `testAnEntryKeepsItsDayAcrossAZoneChange`
- `testTheListIsWrittenBeforeTheTotal`
- `testRebankRepairsATotalThatLagsItsList`
- `testARestoredTotalWithNoListCanBeReplaced`

`IntakeSettingsTests.swift`
- `testEveryKeyHasItsDocumentedDefault`
- `testTargetsRoundTripWithSortedKeys`
- `testUnreadableTargetsAreTreatedAsAbsentAndNotRewritten`
- `testHealthReadEnabledNeedsBothTheFlagAndTheSource`
- `testReadingTheFlagWritesNothing`
- `testTheFlagIsAnObservableDefaultsFlagOverTheIntakeKey` (an `ObservableDefaultsFlag` built over a
  suite with `IntakeSettings.enabledKey` follows a write made through `IntakeSettings.isEnabled`,
  and `set(_:)` on it is read back by `IntakeSettings`)
- `testFloorSetterWritesThroughTheScorecardSetter` (`setProteinFloorGrams(100)` returns true, and
  `CutScorecardSettings.parameters.proteinFloorGrams` is 100 and `proteinFloorWholeGrams` is 100;
  nil clears the floor and the rules string then holds no `proteinFloorGrams` key)
- `testFloorSetterAcceptsExactlyWhatStageOnesRuleAccepts` (for 1, 100, 100 000, 0, 0.5, 99.4, 99.5,
  −5, 100 001, NaN and infinity: the setter's return value equals
  `CutScorecardSettings.isWholeGramProteinFloor` of the value, and every refused value leaves the
  stored rules string byte-identical)
- `testAFractionalFloorStoredEarlierReadsWholeThroughIntakeSettings` (the rules string written
  directly with `"proteinFloorGrams":99.4`: `IntakeSettings.proteinFloorGrams` is 99,
  `targets(on:)` carries 99, and the stored string is byte-equal after every getter). It depends on
  stage 1's work package 1-10, which lands first
- `testTargetsAreTheSameOnEveryDay` (`targets(on:)` for a spread of days, including a non-canonical
  string, returns equal values)
- `testSetTargetsNeverWritesAProteinKey`
- `testSupplementListHoldsAtMostFourAndNoDuplicates`

`IntakeCoachExclusionTests.swift`
- `testListedSupplementQuestionsAreRemoved`
- `testOtherRowsPassThroughUnchangedAndInOrder`
- `testAnAbsentListIsTheIdentity`
- `testMatchingIgnoresCaseAndSurroundingWhitespace`
- `testExclusionDoesNotDependOnTheIntakeFlag`
- `testRemovingASupplementEndsItsExclusion`
- `testCoachRankingInputNeverContainsAListedSupplement` (a repository seeded with Journal rows for
  "Did you take Fixture supplement?" and for one other question, over the stage's reach of days:
  `repo.journalEntries()` contains both questions, which proves the seed is read;
  `IntakeSettings.coachVisible(_:defaults:)` over the test's suite, with the supplement listed,
  returns every row of the other question, in order, and no row whose question contains "Fixture
  supplement"). The Coach engine itself reads the standard defaults and is not driven by this test;
  the source scan `test_coach_reads_journal_only_through_the_exclusion` (§12.4) pins its one call
  site to this function

`IntakeSupplementTickTests.swift`
- `testTickWritesAYesAnswerUnderTheJournalId`
- `testUntickClearsTheAnswerAndNeverWritesNo`
- `testAJournalNoShowsAsUnticked`
- `testTickAndJournalCardReadTheSameRow`
- `testAddingASupplementCreatesOneJournalItemInTheSupplementsGroup`

`IntakeCutoffReminderTests.swift`
- `testSevenTriggersAtTheCutoffMinute`
- `testWithinTheQuietWindowIsSilent`
- `testExactlyAtTheWindowEdgeIsSilent`
- `testOutsideTheWindowPlaysSound`
- `testDistanceWrapsAcrossMidnightAndTheWeek`
- `testPerWeekdayWindDownSilencesOnlyThoseWeekdays`
- `testWindDownOffLeavesEveryTriggerAudible`
- `testFireTimesMatchWhatTheNudgeSchedules`
- `testEnablingAsksPermissionAndDenialRevertsTheSwitch`
- `testFlagOffRemovesEveryRequestAndReconcileDoesNothing`
- `testNotificationTextCarriesNoNumber`

`IntakePresenterTests.swift`
- One test per row of §10.1, per row of §10.2 that has text, and per widget state of §10.8.
- `testAValueIsNeverPublishedWithoutItsTime`
- `testACsvValueIsNeverPublishedToTheWidget`
- `testCardAndFreshnessLineUseOneClock`

Additions to existing files
- `StrandTests/PersonalWidgetMetricsTests.swift`: `testPayloadWithoutIntakeStillDecodes`,
  `testPayloadWithNilIntakeEncodesNoIntakeKey`, `testTodayIntakeDropsAnyOtherDay`,
  `testIntakeChangeCountsAsRenderedContent`
- `StrandTests/TodayCardResolverTests.swift`: `testProteinCardRendersOnlyWithTheFlagOn`,
  `testRenderListIsUnchangedWhenIntakeIsNotPassed`
- `StrandTests/CutScorecardInputBuilderTests.swift`: `testProteinDaysFollowTheIntakeResolverWhenTheFlagIsOn`,
  `testEvaluationCarriesTheResolvedProteinDays`. This file and `TodayCardResolverTests.swift` are
  edited by stage 2 first (the evaluation move), then by this stage (the initialiser argument and
  the new tests).
- `StrandTests/OneNumberPerVariableTests.swift:177`, `StrandTests/BodyMeasurementSingleSourceTests.swift:145`:
  the added `intake:` argument only (§9.4). No assertion changes.

### 12.4 Source scan — `Tools/test_intake_single_resolver.py`

Built like `Tools/test_body_measurement_single_resolver.py` (`:62-90`): a literal allowlist of
file-and-reason pairs, and a check that each entry still matches.

- `test_no_reader_bypasses_the_intake_resolver`: fails on `"protein_g"`, `"calories_in"`,
  `"intake_read_at"`, `IntakeAggregation.proteinKey`, `.energyKey` or `.readAtKey` in `Strand/`,
  `StrandiOS/`, `StrandiOSShared/`, `StrandiOSWidgets/` outside: `IntakeProvider.swift`,
  `IntakeHealthSync.swift`, `IntakeQuickAddStore.swift` (the funnel), `MetricCatalog.swift` and
  `MetricExplorerView.swift` (a labelled source history), `IntakeDemo.swift` (the seeder).
- `test_allowlist_entries_still_match`
- `test_protein_floor_is_stored_only_in_scorecard_rules`: `proteinFloor` appears in no defaults
  key string other than through `CutScorecardSettings`.
- `test_bridge_requests_dietary_types_only_behind_the_setting`: in `HealthKitBridge.swift`,
  `.dietaryProtein` and `.dietaryEnergyConsumed` appear only in lines guarded by
  `healthReadEnabled` and in `collectIntakeSamples`; neither appears in any write list.
- `test_intake_backup_keys_are_swift_only_by_decision`: the two keys are in the Swift whitelist and
  in the fork-only comment block above it, absent from the Kotlin whitelist (the Kotlin file is read
  as text, never compiled), and the test's message quotes R43, so the drift is deliberate and visible.
- `test_no_intake_code_names_the_apple_health_source`: the literal `"apple-health"` and
  `appleDeviceId` occur in no `Intake*.swift` file; `"noop-intake-health"` occurs only in
  `IntakeProvider.swift`.
- `test_coach_reads_journal_only_through_the_exclusion`: under `Strand/AI/`, every occurrence of
  `journalEntries(` is the argument of `IntakeSettings.coachVisible(`.
- `test_supplement_list_reaches_no_widget_or_notification`: `supplementQuestions` and the key string
  `intake.supplement.questions` occur in no file under `StrandiOSWidgets/`, `StrandiOSShared/`,
  `Strand/System/` or `StrandiOS/Widgets/`.
- `test_intake_declares_no_flag_class_and_no_day_parser`: no `class IntakeFlag`; the literal
  `noop.intakeEnabled` occurs only in `IntakeSettings.swift`; no `Intake*.swift` file contains a
  `DateFormatter` with a `yyyy-MM-dd` format.
- `test_intake_declares_no_floor_rule_of_its_own`: the names `isWholeGramFloor` and
  `proteinFloorNeedsWholeGrams` occur in no Swift file; no `Intake*.swift` file declares a function
  or property with `WholeGram` in its name or contains the literal `100000` or `100_000` beside
  `Floor`; `IntakeSettings.swift` calls `CutScorecardSettings.isWholeGramProteinFloor` and reads and
  writes the floor only through `.parameters` of a `CutScorecardSettings`.
- `test_health_row_is_mounted_only_under_the_intake_flag`: in
  `StrandiOS/Redesign/RedesignHealthView.swift`, `RedesignRoute.intake` occurs only inside
  `HealthIntakeRow`, and `HealthIntakeRow(` occurs once, inside an `if` on the observed
  `IntakeSettings.flag`.

### 12.5 Flag-off equivalence

With `noop.intakeEnabled` off: `renderList` keeps its call shape through a defaulted parameter; the
resolver policy is `legacy` and the scorecard's protein days are the CSV series as before; the Health
fingerprint string is unchanged; no notification request exists; no `metricSeries` row, defaults key
or Journal row is written; the widget payload bytes are unchanged; the Health tab's "More health"
card has no Intake row (`test_health_row_is_mounted_only_under_the_intake_flag`); with no supplement listed the
Coach's Journal rows are unchanged (`testAnAbsentListIsTheIdentity`). Direct assertions:
`testPolicyIsLegacyWheneverTheFlagIsOff`, `testDisabledSettingReadsAndWritesNothing`,
`testPayloadWithNilIntakeEncodesNoIntakeKey`, `testFlagOffRemovesEveryRequestAndReconcileDoesNothing`,
`testRenderListIsUnchangedWhenIntakeIsNotPassed`, `testReadingTheFlagWritesNothing`, and
`test_bridge_requests_dietary_types_only_behind_the_setting`. The baseline suite's results are
compared with `BASELINE.md` by the gate script.

### 12.6 Fault injection

For each line, make the change, confirm at least one named test fails, restore.

| # | Deliberate break | A test that must fail |
|---|---|---|
| F1 | An empty day written as zero | `testNoDayIsEverWrittenAsZeroBecauseItIsEmpty` |
| F2 | A whole empty window deletes stored days | `testAWholeEmptyWindowWritesAndDeletesNothing`, `testAnEmptyWindowLeavesEveryStoredDayUntouched` |
| F3 | A failed read treated as empty | `testAFailedReadLeavesEveryStoredDayUntouched` |
| F4 | An emptied day left with its old total | `testAnEmptyDayInsideANonEmptyWindowDeletesItsStoredRows` |
| F5 | Midnight comparison off by one second | `testEntryAtMidnightBelongsToTheNextDay`, `testEntryOneSecondBeforeMidnightBelongsToThatDay` |
| F6 | Day keyed by the current zone, ignoring the log | `testADayStoredBeforeAChangeKeepsItsTotalAfterIt` |
| F7 | Zone segment chosen by `<` in place of `<=` | `testAppendingANewZoneAddsASegmentAtNow`, `testEastwardChangeMidDayMovesLaterEntriesToTheNextDay` |
| F8 | Duplicate ids summed | `testDuplicateIdsAreCountedOnceFirstWins` |
| F9 | Source filter ignored | `testAnExcludedSourceIsDroppedAndCounted` |
| F10 | Read time not advanced when unchanged | `testAnUnchangedTotalStillAdvancesItsReadTime` |
| F11 | Query margin removed | `testQueryWindowStartsFourDaysBeforeTheFirstWrittenDay` |
| F12 | Floor comparison without quantize, or `>` | `testMeetsFloorAgreesWithTheScorecardSignalOverASpread`, `testBelowAtAndAboveTheFloor` |
| F13 | Ring fraction allowed above 1 | `testRingIsCompleteAtTheFloorAndStaysComplete` |
| F14 | Grams capped at the floor | `testGramsKeepCountingPastTheFloor` |
| F15 | Remaining rounded to nearest | `testRemainingIsNeverZeroBeforeTheFloorIsMet` |
| F16 | Hard-floor note on an open day | `testEnergyBelowHardFloorOnlyOnAClosedDay`, `testEnergySoFarMakesNoJudgementWhileTheDayIsOpen` |
| F17 | Range bound made exclusive | `testEnergyBelowRangeInRangeAndBoundsAreInclusive` |
| F18 | Resolver sums two sources | `testSourcesAreNeverSummed` |
| F19 | Resolver order swapped | `testUnifiedOrderForEachSourceSetting` |
| F20 | CSV ignored under the legacy policy, or Health admitted | `testLegacyPolicyReadsOnlyTheCsvSeries` |
| F21 | Scorecard builder reads the store directly | `test_no_reader_bypasses_the_intake_resolver`, `testCardScreenWidgetAndScorecardShareOneProteinNumber` |
| F22 | A second stored protein floor | `testFloorHasOneStoredCopy`, `test_protein_floor_is_stored_only_in_scorecard_rules` |
| F23 | Dietary types requested with the setting off | `test_bridge_requests_dietary_types_only_behind_the_setting`, `testHealthReadEnabledNeedsBothTheFlagAndTheSource` |
| F24 | Widget value published without a time | `testAValueIsNeverPublishedWithoutItsTime` |
| F25 | Yesterday's figure shown as today's | `testTodayIntakeDropsAnyOtherDay` |
| F26 | Untick writes a "no" | `testUntickClearsTheAnswerAndNeverWritesNo` |
| F27 | Quiet window ignored | `testWithinTheQuietWindowIsSilent` |
| F28 | Quiet window not circular | `testDistanceWrapsAcrossMidnightAndTheWeek` |
| F29 | Quick-add total written before the list | `testTheListIsWrittenBeforeTheTotal` |
| F30 | Intake delete widened to the whole source | `testIntakeDeletionRemovesOnlyTheNamedDayAndKey`, `testTheTwoIntakeIdsAreIndependent` |
| F31 | A number placed in the notification body | `testNotificationTextCarriesNoNumber` |
| F32 | Path A totals written under `apple-health` | `testTotalsAreWrittenUnderTheDedicatedIdAndNeverUnderAppleHealth`, `testDeletingAppleHealthDataLeavesEveryIntakeRow`, `test_no_intake_code_names_the_apple_health_source` |
| F33 | The floor setter accepts 99.4, or refuses by a check of its own with a different bound | `testFloorSetterAcceptsExactlyWhatStageOnesRuleAccepts` |
| F34 | The Coach's Journal read loses its filter | `test_coach_reads_journal_only_through_the_exclusion`, `testCoachRankingInputNeverContainsAListedSupplement` |
| F35 | The exclusion compares case-sensitively | `testMatchingIgnoresCaseAndSurroundingWhitespace` |
| F36 | `targets(on:)` made to vary with the day | `testTargetsAreTheSameOnEveryDay` |
| F37 | The exclusion gated on the intake flag | `testExclusionDoesNotDependOnTheIntakeFlag` |
| F38 | `IntakeSettings.proteinFloorGrams` decodes the rules string itself, bypassing `CutScorecardSettings.parameters` | `testAFractionalFloorStoredEarlierReadsWholeThroughIntakeSettings`, `testShownFloorIsTheScorecardsWholeGramFloor`, `test_intake_declares_no_floor_rule_of_its_own` |
| F39 | The Health tab row mounted without its flag check | `test_health_row_is_mounted_only_under_the_intake_flag` |

### 12.7 Parity: written dispositions (R43)

No Kotlin is written, edited or run. Each disposition is recorded with the change.

| Piece | Disposition |
|---|---|
| `IntakeAggregation`, `IntakeProgress` (package analytics) | No twin. iPhone-only feature; Android has no intake surface. New public declarations in `StrandAnalytics` carry the "No Kotlin twin" doc line; the parity ledger will list them as one-sided, which is recorded debt, not a failure to hide |
| Stored rows: `protein_g`, `calories_in`, `intake_read_at` under `noop-intake-health` and `noop-intake` | Not updated on Android, by the owner's decision. Drift: an Android build restoring this database keeps the rows under two source ids it does not know, shows none of them, and its Health Connect import does not write them. Whether its CSV export would list them was not read |
| Backup keys `intake.targets`, `intake.supplement.questions` | Not updated on Android, by the owner's decision. Drift as in §9.6 |
| `DashboardCard.protein` | No Android id. A dashboard selection containing `protein` restored on Android has an unknown id, which its decoder drops; dashboard selections are not in the backup whitelist in any case (`BackupSettings.swift:40-42`) |
| Journal question created for a supplement | Carried by the existing `journal.customBehaviors` key on both platforms. No change |
| Coach exclusion of supplement questions | iPhone only. Android's Coach, if used with a restored database, would read those Journal rows; it has no supplement list |
| Marker catalogue | Not edited |
| Gate script | Android rows waived by flag and reported as waived (R43) |

### 12.8 Privacy scans

- `testWidgetPayloadCarriesNoCaloriesLabelsOrSourceNames`: encode a payload built from the
  fixture and assert the bytes contain none of the fixture's energy figures, entry labels, bundle
  ids, source names or supplement names.
- `testNotificationTextCarriesNoNumber` (above), and it asserts the fixture's supplement name and
  floor are absent too.
- `testBackupSettingsCarryNoEntryLabelsOrSourceIds`.
- `testCoachRankingInputNeverContainsAListedSupplement` and
  `test_supplement_list_reaches_no_widget_or_notification` (above).
- `Strand/System/IntakeCutoffReminder.swift` is listed in stage 5's
  `test_notification_producers_never_name_personal_events` (§7.6).

### 12.9 Simulator and rehearsal

- Every frame of §10 reproduced from `IntakeDemo` at the default and largest text size, Reduce
  Motion on and off: `--demo-screen intake-<state>` names. The debug block
  (`StrandiOS/App/StrandiOSApp.swift:623`) holds the demo registry, added by the orchestrator's
  step 0. This stage has its own demo file, `StrandiOS/Intake/IntakeDemo.swift`, exposing
  `static func screen(named: String) -> AnyView?`, and one element in that registry, added in
  3-6h. Its reserved prefix is `intake-`: every name it answers starts with it, and it returns nil
  for any other name. Compiled for the simulator only.
- The demo's seeded person is stage 1's Fixture Person (§13.6), so a combined demo or simulator seed
  shows one person.
- Flows by tapping: add, edit, delete, backdate a quick-add entry; tick and untick; change the
  source; set and clear targets.
- Path A on the device, with the owner: the discovery checklist (§14.1), then a known meal logged
  in the food app, NOOP opened, the total and its time confirmed; an entry edited and one deleted at
  the source and the totals followed; the phone locked for an hour and the widget's state recorded.
- Real-data rehearsal on the private copy (0B-7): flag off, the scorecard's protein row is
  unchanged; flag on with source None, the same. Results stay out of the repository.

## 13. Fixture

`Packages/StrandAnalytics/Tests/StrandAnalyticsTests/IntakeFixture.swift`. Everything here is
invented. Instants are written as UTC ISO strings and parsed by a helper in the fixture.

**One Fixture Person across the stages.** The person is the one stage 1 defines (`stage-1.md` §13):
phase "Fixture cut" starting 2031-01-06, weigh-ins on Wednesdays from 2031-01-08, protein floor
100 g, and the daily protein amounts of stage 1 §13.2 for the weeks inside the phase. This stage adds
the intake settings below to that person and contradicts none of stage 1's values:

- The hand-worked samples of §13.2 to §13.3 exercise the pure aggregation. They are dated
  2030-12-09 and 2030-12-10, four weeks before the phase starts, where stage 1 states no protein
  figure, so no day has two different totals across the stages.
- App-target fixtures and the simulator demo (§13.6) use stage 1's floor and stage 1's protein days.

### 13.1 Person and settings

| Setting | Value |
|---|---|
| Protein floor | 100 g (stage 1's `proteinFloorGrams`; a whole number, as stage 1 R45 requires) |
| Calorie range | 2400 to 2600 kcal |
| Hard floor | 2100 kcal |
| Cutoff time | 20:00 (minute 1200) |
| Supplement | "Fixture supplement"; question "Did you take Fixture supplement?" |
| Food app | name "Fixture Food", bundle id `app.fixture.food` |
| Second app | name "Fixture Other", bundle id `app.fixture.other` |
| Preset | "Fixture shake": 30 g, 150 kcal |

### 13.2 Samples

All from `app.fixture.food` unless stated. Window `2030-12-09 ... 2030-12-10`.

| id | Nutrient | Instant (UTC) | Amount |
|---|---|---|---|
| s1 | protein | 2030-12-09T08:00:00Z | 30 |
| s2 | energy | 2030-12-09T08:00:00Z | 450 |
| s3 | protein | 2030-12-09T13:00:00Z | 40 |
| s4 | energy | 2030-12-09T13:00:00Z | 700 |
| s5 | protein | 2030-12-09T23:59:59Z | 25 |
| s6 | energy | 2030-12-09T23:59:59Z | 300 |
| s7 | protein | 2030-12-10T00:00:00Z | 20 |
| s8 | energy | 2030-12-10T00:00:00Z | 250 |
| s9 (`app.fixture.other`) | protein | 2030-12-09T10:00:00Z | 10 |

### 13.3 Expected totals

Zone log U: `[(0, "Etc/UTC")]`.

| Case | 2030-12-09 protein / energy | 2030-12-10 protein / energy |
|---|---|---|
| s1 to s8, log U | 95 / 1450 | 20 / 250 |
| s1 to s9, all sources | 105 / 1450 | 20 / 250 |
| s1 to s9, admitted `app.fixture.food` | 95 / 1450, one `excludedSource` | 20 / 250 |
| Edit: s3 replaced by s3b (same instant, 45) | 100 / 1450: exactly at the floor | 20 / 250 |
| Delete s5 and s6 | 70 / 1150 | 20 / 250 |
| Delete s7 and s8 | 95 / 1450 | empty day; stored rows deleted by the plan |
| No samples at all | plan writes nothing; stored rows kept | same |

Zone log E (eastward): `[(0, "Etc/UTC"), (2030-12-09T18:00:00Z, "Pacific/Auckland")]`. Auckland is
thirteen hours ahead of UTC on these dates. With s1 to s8:

| Day | Samples | Protein / energy |
|---|---|---|
| 2030-12-09 | s1 to s4 (before the change, UTC day) | 70 / 1150 |
| 2030-12-10 | s5 to s8 (after the change, Auckland day) | 45 / 550 |

Zone log W (westward): `[(0, "Pacific/Auckland"), (2030-12-09T20:00:00Z, "America/Los_Angeles")]`.
Los Angeles is eight hours behind UTC on these dates. Two protein samples: x at
`2030-12-09T19:00:00Z` (10 g) falls on 2030-12-10 in Auckland; y at `2030-12-09T21:00:00Z` (15 g)
falls on 2030-12-09 in Los Angeles. The later instant is on the earlier day, and each is counted once.

### 13.4 Progress

| Grams | Floor | State | Shown | Remaining | Over | Ring |
|---|---|---|---|---|---|---|
| nil | 100 | notMeasured | — | — | — | nil |
| 95 | 100 | below | 95 | 5 | 0 | 0.95 |
| 99.9994 | 100 | below | 99 | 1 | 0 | 0.99999 |
| 99.9996 | 100 | atFloor | 100 | 0 | 0 | 1 |
| 100 | 100 | atFloor | 100 | 0 | 0 | 1 |
| 105 | 100 | above | 105 | 0 | 5 | 1 |
| 105 | nil | noFloor | 105 | — | — | nil |

The two rows with fractional amounts are amounts eaten, not floors; the floor is 100 in every row.

| kcal | Day open | State | Detail |
|---|---|---|---|
| nil | either | notMeasured | — |
| 1450 | open | soFar | 950 to the low end |
| 2700 | open | aboveRange | 100 over |
| 1500 | closed | belowHardFloor | — |
| 2100 | closed | belowRange | the hard floor itself is not below it |
| 2400 | closed | inRange | inclusive |
| 2600 | closed | inRange | inclusive |
| 2601 | closed | aboveRange | 1 over |

### 13.5 Cutoff and wind-down

| Cutoff | Wind-down fire times | Expected |
|---|---|---|
| 20:00 | off | seven audible triggers |
| 20:00 | 20:20 every day | seven silent |
| 20:00 | 20:30 every day | seven silent (edge) |
| 20:00 | 20:31 every day | seven audible |
| 23:50 | 00:10, fired on the following weekday | silent on the weekday before each |
| 20:00 | 20:10 on weekday 2 only, 22:00 otherwise | weekday 2 silent, six audible |

### 13.6 App-target fixtures

The repository's series reads stop one day after the real clock (`Repository.swift:1852-1854`), so
`StrandTests` and simulator runs that go through the store use dates relative to the real clock
(stage 1 R31). The dated fixture of §13.2 is for the pure functions.

Values for app-target tests and for `IntakeDemo`, all stage 1's person:

| What | Value |
|---|---|
| Protein floor | 100 g, written through the scorecard rules |
| The seven days before today, oldest first (protein, g) | 120, 120, 120, 80, 120, 120, 120: the week pattern of stage 1 §13.2, so the scorecard's protein row reads 6 of 7 days at or above the floor |
| Today, for the card and widget states | not measured; 95 (below, 5 to go); 100 (at the floor); 105 (above, 5 over) |
| Calories eaten today | 1450 with the day open; a closed past day at 2400 (in range) |
| Calorie range, hard floor, cutoff, supplement, apps, preset | as §13.1 |
| Three-source day for `testCardScreenWidgetAndScorecardShareOneProteinNumber` | 120 g under `noop-intake-health`, 80 g under `noop-intake`, 60 g under `nutrition-csv`, all for yesterday |
| Weigh-ins, phase, lifts | stage 1's, re-based onto the real clock exactly as stage 1's own app-target fixture does. `IntakeDemo` seeds no weight of its own |

Read times are relative to the injected clock: "fresh" is ten minutes before now, "stale" is four
hours before now.

## 14. Work packages and file ownership

A package edits only the files listed for it.

### 14.1 WP 3-0: the discovery spike (the owner, five minutes on the phone)

1. Open the food app. In its own settings, look for "Apple Health", "Health" or "Integrations" and
   note whether a switch exists and whether it is on.
2. Open **Health**. Tap the profile picture, then **Apps** (under Privacy). Is the food app listed?
3. Tap it. Under "Allow … to write", note which of these appear and which are on: **Protein**,
   **Dietary Energy** (or "Energy consumed"), Carbohydrates, Total Fat.
4. Log one small test item in the food app with a known protein amount.
5. In Health: **Browse → Nutrition → Protein → Show All Data**. Is there a new entry with that
   amount? Tap it: note the **source** name, and whether its time is the meal time or the time of
   logging.
6. Edit the item's amount in the food app. Does the Health entry change? Delete the item. Does the
   Health entry go?
7. Does the food app offer an export (CSV) or document an MCP server? Send the App Store link.

Report to the orchestrator: the app's exact name; yes or no for protein and for energy; meal time or
logging time; whether edits and deletes propagate; export or MCP, if any. The orchestrator then asks
the owner for the path and, for Path A, for go-aheads G1 and G2.

| Outcome | Path |
|---|---|
| Protein and energy are written, edits and deletes propagate | A, on the owner's yes to the wider read |
| Written, but edits or deletes do not propagate | A is still correct for what Health holds; the screen's figures will follow Health, not the food app. Tell the owner before choosing |
| Not written, or the owner declines | B, or C |
| The owner only wants the coach to see intake | C |

### 14.2 Packages

| WP | Role | Paths | Files |
|---|---|---|---|
| 3-2 | Designer | A, B, C | Files inside `design/round-s3-intake/` only (the folder exists from the scaffolding commit); export `s3-frames.json`. The plugin files `design/figma-plugin/code.js` and `manifest.json` are **not** edited: `importS3` is already there. The Settings card's position and the scorecard protein row's caption follow the combined frame set |
| 3-3 | Test author | A, B, C | Every test file named in §12; `IntakeFixture.swift`; additions to the existing test files named in §12.2 and §12.3; `Tools/test_intake_single_resolver.py` |
| 3-4 | Implementer A (pure) | A, B | `Packages/StrandAnalytics/Sources/StrandAnalytics/IntakeAggregation.swift`, `IntakeProgress.swift` |
| 3-5a | Implementer B (storage and resolver) | A, B, C | New: `Strand/Data/IntakeSettings.swift`, `IntakeResolver.swift`, `IntakeProvider.swift`, `IntakeQuickAddStore.swift`, `IntakeSupplementTick.swift`, `IntakeHealthSync.swift`. Edited, each as one small commit in this stage's place in the order of §14.3: `Strand/Data/CutScorecardInputBuilder.swift` (the protein read and the initialiser, written against the file as stage 2 leaves it) with its construction sites `Strand/Data/CutScorecardModel.swift` and `Strand/Data/CoachPacketAssembler.swift` (one parameter and one argument each, §9.4); `Strand/AI/AICoach.swift` (the one line of §10.6.1). 3-5a does not edit `BackupSettings.swift` (3-6h) |
| 3-5b | Implementer B, after G1 go-ahead | A only | `StrandiOS/Health/HealthKitBridge.swift` (`readTypes`, `enableLiveDelivery`, `collectIntakeSamples`, `requestIntakeReadAccess`, the call in `sync`) |
| 3-6 | Implementer C, after design approval and after 3-4 and 3-5a merge | A, B (C: tick and reminder parts) | New: `Strand/Data/IntakePresenter.swift`, `IntakeModel.swift`; `Strand/System/IntakeCutoffReminder.swift`; `StrandiOS/Intake/IntakeView.swift`, `IntakeQuickAddSheet.swift`, `IntakeSettingsSection.swift`, `IntakeDemo.swift`. Edited: `Strand/Screens/DashboardCards.swift`, `Strand/Data/TodayCardReadout.swift`, `Strand/Screens/TodayCustomizationMetadata.swift`, `Strand/Screens/TodayCustomizationSheet.swift`, `Strand/Data/TodayCardsEditorPresentation.swift`, `StrandiOS/Redesign/YourCardsSection.swift`, `StrandiOS/Redesign/RedesignTodayView.swift` (card inputs and the flag), `StrandiOS/App/RootTabView.swift` (reminder reconcile); `Strand/Screens/TodayView.swift` and `Strand/Liquid/LiquidTodayView.swift` only to keep their `DashboardCard` switches exhaustive. 3-6 does not edit the files of 3-6h; `IntakeSettingsSection`, `IntakeView` and `IntakeDemo` are complete in their own files so that 3-6h is wiring only |
| 3-6h | Orchestrator: this stage's one commit of edits to files other stages also edit, on the integration branch, after 3-5a and 3-6 and before 3-8 | A, B (C: the Settings card, the Health row, the route, the registry element and the backup keys; not the scorecard row) | `Strand/Screens/SettingsView.swift` (one card that embeds `IntakeSettingsSection`, at the position of §10); `StrandiOS/Redesign/RedesignHealthView.swift` (`HealthIntakeRow` and its flag-gated mount, §10.9); `StrandiOS/Redesign/RedesignRoute.swift` (the case `intake` and its arm); `StrandiOS/Scorecard/ScorecardView.swift` (the protein row's caption and tap, §10.4); `StrandiOS/App/StrandiOSApp.swift` (one element, `IntakeDemo`, in the demo registry); `Packages/WhoopStore/Sources/WhoopStore/BackupSettings.swift` (two entries in each table and two names in the fork-only comment block, §9.6). `Strand` and `NOOPiOS` are built after the commit |
| 3-7 | Implementer D | A, B | `StrandiOSShared/PersonalWidgetMetrics.swift`; `StrandiOSWidgets/PersonalProteinWidget.swift` (new); `StrandiOSWidgets/NOOPWidgetBundle.swift`; `StrandiOS/Widgets/WidgetPublish.swift` |
| 3-8 | Localiser | A, B, C | `Strand/Resources/Localizable.xcstrings`; `StrandiOSWidgets/Localizable.xcstrings` |
| 3-9 | Orchestrator, after G2 go-ahead | A only | `project.yml` (the usage sentence), then `xcodegen generate` |
| 3-10 | Reviewers (correctness, contract, data safety) and Verifier | all | None |

Path C builds 3-3 (the tick, reminder, settings, flag and Coach-exclusion tests), the settings, tick,
Coach-exclusion and reminder parts of 3-5a and 3-6, the Path C part of 3-6h, and 3-8. It builds no
card, no widget, no resolver switch and no Health read.

No work package writes, edits or runs Kotlin (R43).

### 14.3 Shared hotspots and order

**The one order.** Every file that more than one change edits is edited in this order: Lab Book
ownership, stage 2, stage 3, stage 4, stage 5, stage 6, then packet v2. **This stage is third.** Each
row below gives this stage's position for that file and nothing about any other stage's edit; where
a file is not edited by Lab Book ownership or by stage 2, third still means "in this stage's step,
before stage 4's step". Stage 1's follow-up packages that precede stage 2 (the R40 flag observation
in the Today views, and work package 1-10 for the floor) are already in the files this stage finds.

Each hotspot edit is one small commit on the integration branch in this stage's step (step 4 of the
build order), with the Localiser last. The files of 3-6h are one orchestrator commit.

| File | Package | This stage's position | Rule |
|---|---|---|---|
| `Strand/Resources/Localizable.xcstrings` | 3-8 | Third | Sole writer while it runs, once, the last step of the stage, after the English strings are final. Never two branches at once |
| `StrandiOSWidgets/Localizable.xcstrings` | 3-8 | Third; no earlier change edits it | Same rule |
| `Strand/Screens/DashboardCards.swift`, `Strand/Data/TodayCardReadout.swift`, `Strand/Screens/TodayCustomizationMetadata.swift`, `TodayCustomizationSheet.swift`, `Strand/Data/TodayCardsEditorPresentation.swift`, `StrandiOS/Redesign/YourCardsSection.swift`, `StrandiOS/Redesign/RedesignTodayView.swift`, `Strand/Screens/TodayView.swift`, `Strand/Liquid/LiquidTodayView.swift` | 3-6 | Third; written against the files as stage 1's R40 follow-up leaves them | One new case in each switch; one defaulted parameter, one `Tap` case and one readout case in `TodayCardReadout`; exhaustiveness only in the classic and Liquid Today views; card inputs and the observed flag in the redesign Today view |
| `Strand/Screens/SettingsView.swift` | 3-6h | Third, after the combined Settings frame is approved | One self-contained card that embeds `IntakeSettingsSection`, placed third in the Settings order (§10). Shared with macOS: build `Strand` after the edit |
| `StrandiOS/Redesign/RedesignHealthView.swift` | 3-6h | Third, after the combined Health frame is approved | One private row view and one flag-gated mount, placed third in the Health order (§10.9) |
| `StrandiOS/Redesign/RedesignRoute.swift` | 3-6h | Third | One additive case, `intake`, and its arm in the route switch |
| `StrandiOS/Scorecard/ScorecardView.swift` | 3-6h | Third | The protein row's caption and tap only (§10.4) |
| `StrandiOS/App/StrandiOSApp.swift` (debug block, `:623`) | 3-6h | Third; the registry itself comes from the orchestrator's step 0 | One array element, `IntakeDemo`. The registry line itself is not rewritten |
| `Packages/WhoopStore/Sources/WhoopStore/BackupSettings.swift` | 3-6h | Third | One writer at a time. Two entries in each table, two names in the fork-only comment block |
| `Packages/WhoopStore/Tests/WhoopStoreTests/BackupSettingsTests.swift` | 3-3 | Third | New methods only, appended after the methods already in the file |
| `Strand/Data/CutScorecardInputBuilder.swift` | 3-5a | Third; written against the file as stage 2 leaves it, with `evaluation(today:)` | The protein read through `IntakeProvider` and the initialiser parameter (§9.4) |
| `Strand/Data/CutScorecardModel.swift`, `Strand/Data/CoachPacketAssembler.swift` | 3-5a | Third; after stage 2's move of the evaluation, which creates the assembler | One defaulted parameter and one argument each, in the same commit as the builder edit. Nothing else |
| `StrandTests/CutScorecardInputBuilderTests.swift`, `StrandTests/TodayCardResolverTests.swift` | 3-3 | Third | The initialiser argument and new test methods |
| `StrandTests/OneNumberPerVariableTests.swift`, `StrandTests/BodyMeasurementSingleSourceTests.swift` | 3-3 | Third | The added `intake:` argument at one line each. No assertion changes |
| `Strand/AI/AICoach.swift` | 3-5a | Third: after Lab Book ownership and the stage 2 extraction, before stage 4 (§10.6.1) | One line at the Journal read. Applied after stage 2's byte-identity baseline is green; with no supplement listed it changes no byte, and that suite is re-run unchanged after it |
| `Strand/System/IntakeCutoffReminder.swift` (new) against stage 5's `Tools/test_personal_events_boundaries.py` | 3-6 | This stage's file lands third, before the scan exists | The scan's list of notification producers must name this file (§7.6). If the scan already exists when this file lands, 3-6 adds the list entry in the commit that adds the file |
| `StrandiOSShared/PersonalWidgetMetrics.swift`, `StrandiOS/Widgets/WidgetPublish.swift`, `StrandiOSWidgets/NOOPWidgetBundle.swift`, `StrandiOS/App/RootTabView.swift` | 3-7, 3-6 | This stage only | One implementer per file |
| `StrandiOS/Health/HealthKitBridge.swift` | 3-5b | This stage only; waits for the owner's yes (G1) | Second merge |
| `project.yml` | 3-9 | This stage only; waits for the owner's yes (G2) | Orchestrator only; second merge |
| `design/figma-plugin/code.js`, `manifest.json` | nobody in this stage | Not edited; `importS3` comes from the orchestrator's step 0 | — |
| `Packages/StrandImport/…/MarkerCatalog.swift` | nobody in this stage | Not edited | — |

### 14.4 Parallel and serial

Can run now, in parallel with other stages, in its own worktree and with no app build: 3-2 (HTML
frames only), 3-3 (tests in new files), 3-4 (pure logic and its `swift test`, one package at a time
per worktree), the new files of 3-5a, and the new files of 3-6 and 3-7 written but not built. WP 3-0
(the owner's five-minute check) runs at the same time.

Serialised, on the single app build tree, as step 4 of the build order (after Lab Book ownership,
stage 1's R40 follow-up and stage 2): every row of §14.3, `xcodegen generate`, the `NOOPiOS` and
`Strand` builds, `StrandTests` and the gate script.

Within the stage: 3-3 and 3-4 start now, before the owner answers. 3-5a's settings, tick, resolver
and quick-add store start now. Interface code (3-6, 3-7 views) waits for design approval, including
the combined frame set. 3-6 follows 3-4 and 3-5a. 3-6h, the orchestrator's one commit of wiring
edits, follows 3-5a and 3-6. 3-8 follows 3-6, 3-6h and 3-7 and is the stage's last step. 3-5b and 3-9 wait for G1 and G2 and form the second merge; the Localiser's
strings for Path A are written in the first merge so the second touches no catalogue.

Shared scaffolding this stage expects to exist before its own code is integrated (the
orchestrator's step 0): the demo registry line in `StrandiOSApp`; the plugin command `importS3` and
the folder `design/round-s3-intake/`; `ObservableDefaultsFlag`; `CanonicalDay`; the fork-only backup
keys comment block. `ChargeTypicalBand` is part of the same commit and is not used by this stage.

Phone: this stage is installed together with stage 4 at one milestone, after a fresh backup, with
`noop.intakeEnabled` off until the owner switches it on.

### 14.5 Consumers

- **The coach packet (packet v2).** Stage 2 ships version 1 of the packet with `intake` listed under
  `not-recorded-by-app`. After this stage and stage 5 have merged, one follow-up change adds the
  `intake` and `events` sections together: one `CoachPacketSection` case each, both names removed
  from `not-recorded-by-app`, one version bump, one new golden set and one revision of the
  Claude-side text. That change owns the section's format under stage 2's grammar. This stage has no
  work package for it and writes no packet line. What this stage guarantees to it: protein and
  energy for a day come only from `IntakeProvider.series()` (each value with its source and read
  time), and targets only from `IntakeSettings.targets(on:)`; the packet must not read the store.
  The source scan of §12.4 will fail a packet file that names an intake key. Supplement ticks are
  not offered to the packet by this stage; whether they ever join it is that change's question.
- **The scorecard's protein line in packet version 1** needs nothing from this stage: it is part of
  the scorecard evaluation, which after §9.4 carries the resolved protein days.
- **Stage 5.** Supplies nothing to this stage and reads nothing from it. No dated override of the
  calorie range exists (§1).

## 15. Open questions for the owner

Work proceeds on each recommendation.

**Needs the owner's go-ahead before the named work starts**

| # | What | Why | The alternative that avoids it |
|---|---|---|---|
| G1 | Widen Apple Health reads to dietary protein and dietary energy (Q4), only while Intake is on with Apple Health as its source | Path A cannot exist without it | Path B (quick-add) or Path C |
| G2 | Change the Health permission sentence in `project.yml` (§11, last row) | The current sentence names only steps and workouts | Leave it; the sheet then asks for nutrition under a sentence that does not mention it. Not recommended |
| G3 | A new widget kind in the existing widget extension | It is the stage's widget. No new target, identifier, profile or entitlement | Add a protein line to an existing widget instead; that changes an accepted widget |
| G4 | One more local notification (the cutoff), opt-in, off by default | Notification budget | Path without the reminder: the cutoff time still closes the day in §7.5 |
| G5 | Two Swift-only backup keys, with the Android drift of §9.6. Both sit in clear text in the backup, and the supplement questions contain the names the owner typed | Targets and supplement choices survive a restore | Leave them out; they are re-entered after a restore |
| G6 | The combined layout for the Health tab's "More health" card, Settings and the scorecard screen covering all stages, then this stage's own frames | Needed before any view code. It draws the Intake card in Settings and the Intake row in the Health tab, both third in the order (§10), and how the protein row's caption reads | None; the view work waits |

No migration, no network path, no new target and no new entitlement is needed on any path.

**Questions with a recommendation in force**

| # | Question | Recommendation |
|---|---|---|
| I1 (Q1) | Which food app, and does it write to Health? | The spike of §14.1 answers it. Until then: build the common parts, source None |
| I2 | Path A, B or C? | A if the spike allows and the owner says yes to G1; otherwise B |
| I3 | If the food app is the source and something is also entered here on the same day, add them or use one? | Use one: the active source wins for the day. Adding them risks counting a meal twice |
| I4 | When two apps write protein to Health, count both or pick one? | Count both by default, as the Health app does, name them on the screen, and offer the choice |
| I5 | Track fat and carbohydrate too? | Not in this stage. Under Path A each is a further Health type and a further go-ahead; the stored keys `fat_g` and `carbs_g` already exist for it |
| I6 | The new widget appears in the gallery while Intake is off | Accept; it draws "Set up in NOOP" |
| I7 | When does a day close for the calorie note? | At the cutoff time if one is set, otherwise at midnight |
| I8 | How old may a Health figure be before the widget and card draw it as stale? | Three hours |
| I9 | Should the cutoff or the wind-down be the silent one when they fall together? | The cutoff. The wind-down is an accepted feature and is not edited. A single merged notification is possible later and means editing the nudge |
| I10 | Should an unticked supplement at the cutoff time prompt anything? | No. The tick is a record, not a task |
| I11 | Pre-logged food dated later today: count it now? | Yes, so the figure equals the food app's |
| I12 | Should a past day's total keep following the food app after a correction there? | Yes, within the 30-day read window (90 on the first read) |
| I13 | Should the hard-floor note use the words "your floor"? | Yes: "Below your floor of N kcal". It is the owner's setting; no other wording is added |
| I14 | Should Intake settings offer a way to erase the intake history read from Apple Health? | Not in this stage. The history is stored under its own id, so the Apple Health page's delete no longer removes it, and a wrong day is corrected at the source |

**Decided by default in the cross-stage check (11 November 2026)**

Each is the design in force in this document. The last column says what changes if the owner
decides otherwise.

| # | Decision in force | If the owner says otherwise |
|---|---|---|
| D1 | Supplement ticks are Journal answers, and the questions listed as supplements are excluded from the in-app Coach's context (§10.6.1) | Accepting the leak instead: delete `coachVisible`, the one-line edit to `AICoach.swift`, `IntakeCoachExclusionTests.swift`, the scan `test_coach_reads_journal_only_through_the_exclusion`, fault lines F34, F35 and F37, and the settings caption. Nothing stored changes |
| D2 | Two intake keys join the iPhone backup only, in clear text, with Android knowingly behind (§9.6). The cross-stage recommendation also raises encrypted backups in priority; that is not part of this stage | Leaving them out: remove the two whitelist entries, the two names in the comment block and the two backup tests; targets and the supplement list are re-entered after a restore |
| D3 | Apple Health reads widen to dietary protein and dietary energy only while Intake is on with Apple Health as its source, with the permission sentence updated (G1, G2). In force only if the food app writes to Health; otherwise quick-add | No: Path B. The second merge (3-5b, 3-9) is never made; `IntakeHealthSync` stays inert and `noop-intake-health` stays empty |
| D4 | A new widget kind, Protein, in the existing extension, drawing "Set up in NOOP" while Intake is off (G3, I6) | No: drop 3-7's widget file and bundle entry; the payload field and its tests may stay unused or be dropped with them |
| D5 | One more opt-in local notification, the food cutoff, silent within 30 minutes of the wind-down reminder (G4) | No: drop `IntakeCutoffReminder` and its settings rows; the cutoff time still closes the day (§7.5); stage 5's producer list needs no entry |
| D6 | No dated override of the calorie range exists; `targets(on:)` is the same every day | A real override is a new specification; no call site changes because the parameter is already there |
| D7 | Path A totals are stored under `noop-intake-health`, not under `apple-health` | Storing under `apple-health` with a warning sentence in the Apple Health delete dialog instead: change one constant, restore the forgetting test, and add the dialog string; older days would again be lost on that delete |
| D8 | The protein floor is whole grams. The rule is stage 1's ruling R45 (stage 1 question S23); this stage's field writes the same stored value through the same setter and adds no rule | Allowing fractions is a change to stage 1's rule and so to stages 1, 2 and 3 together: every surface must then agree on one rounding for display. In this stage only the field's keypad would change, since the setter already defers to stage 1's function |
| D11 | Intake has a row in the Health tab's "More health" card, third in the order, present only while the flag is on (§10.9) | No row: remove `HealthIntakeRow`, the `RedesignHealthView.swift` edit from 3-6h, the scan `test_health_row_is_mounted_only_under_the_intake_flag` and fault line F39. Under Path C the intake screen is then reached only from the Settings card |
| D9 | The coach packet's intake section is built once, with the events section, as "packet v2" after stages 3 and 5 (§14.5) | Building it inside this stage: a new work package, a packet version of its own and a second revision of the Claude-side text |
| D10 | Installs happen at milestones; this stage reaches the phone together with stage 4, after a fresh backup, with the flag off | A separate install for this stage alone is possible and changes no code |

**To confirm.** The fixture's settings in §13.1 (protein floor 100 g, calorie range 2400 to
2600 kcal, hard floor 2100 kcal, cutoff 20:00) are invented round values. If any of them happens to
equal a real setting, tell the orchestrator which row and it is replaced with a different invented
value; nothing else depends on the particular numbers except the tables of §13.

## 16. Not determined

- **What the owner's food app does**: whether it writes dietary types to Health, whether it stamps
  the meal time or the logging time, and whether its edits and deletes propagate. Only the spike
  (§14.1) can tell.
- **Whether HealthKit can be exercised in the simulator.** A comment in the bridge says it cannot
  (`HealthKitBridge.swift:357`). Not tested. The plan keeps every decision in macOS-testable code
  and leaves only the two queries and the permission sheet to the device.
- **Whether HealthKit honours hourly background delivery for dietary types**, and how often a wake
  arrives while the phone is locked. The stale state exists for this; the device check records it.
- **Whether a read can succeed while the phone is locked.** HealthKit's store is protected data, so
  failure is expected. Not tested.
- **How late the app notices a zone change.** The zone log records the change when the app next
  runs. Entries logged between the real change and that moment are keyed in the old zone. The size
  of that gap in practice is unknown.
- **The widget bundle's size limit.** The bundle holds nine entries (`NOOPWidgetBundle.swift:11-19`);
  this is the tenth. The builder is believed to take ten in one block. If the tenth does not
  compile, the body is split into two nested bundles, which changes no kind string.
- **Whether the cached day formatter in the bridge follows a zone change** (`HealthKitBridge.swift:2016-2020`:
  a static formatter that captured the zone at first use). It affects Steps today. This stage does
  not use it.
- **Whether a given database holds `nutrition-csv` rows** makes no difference to the design: the
  resolver handles both cases, and the rehearsal checks the flag-off path either way.
- **The illness watch's confounder flags** are set by substring matches on Journal questions
  answered yes in the last two days (`Strand/App/AppModel.swift:1988-1996`: "alcohol", "drink",
  "workout", "train", "exercise", "sick", "ill", "unwell"). A ticked supplement whose typed name
  happens to contain one of those letter sequences would set a flag. This is existing behaviour for
  any custom Journal question, it stays on the phone and prints no question, and this stage does
  not change it. It is recorded so nobody is surprised.
- **Whether any on-device code walks every stored source id** and would list `noop-intake-health`
  or `noop-intake` somewhere unexpected. The CSV export walks the strap read ids only (§4.1), and
  Devices and Data Sources read the registry, which holds neither id. Not checked beyond those.
- **Whether the owner wants intake in the CSV export.** It is not there (§4.1); adding the two ids
  to the export is a small separate change.
- **How an imported WHOOP Journal row spells a question** that the owner later adopts as a
  supplement. The exclusion matches without regard to case and surrounding whitespace; any other
  difference in spelling is a different question to the Journal as well.
- **The path to the intake screen under Path C.** Path C builds no card, so the supplements section
  and the cutoff row are reached from the Health tab row (§10.9) and from the Intake card in
  Settings. Whether that is enough is for the combined frame review.
- **Whether Explore's "Protein" row, labelled "Nutrition", will confuse** once another source feeds
  the intake screen. It is one source's history and is left as it is; a clearer label is a
  one-string change the owner can ask for.
- **Parity ledger behaviour** for one-sided `StrandAnalytics` declarations (stage 0 item 0B-9). The
  doc-line wording in §6 was not run through the ledger.
- **Android.** Nothing on the Kotlin side was read beyond the backup codec lines cited, and nothing
  was written, compiled or run (R43).
- **Expected values in §13** were worked by hand for this document. The test author recomputes
  them; a disagreement is reported, not silently corrected.

## 17. Design approval record (G1)

Not yet submitted. Frames, page name, the approval date and the owner's choices are recorded here
when the owner approves.

## 18. Reconciliation (11 November 2026)

Changes made to this file after the cross-stage consistency check. One line per conflict applied.

| Conflict | What changed in this file |
|---|---|
| X4 | The packet's intake section is no longer described as stage 2's or this stage's work. §1 and the new §14.5 assign it to the single "packet v2" change after stages 3 and 5; this stage only guarantees the read API (`IntakeProvider.series()`, `IntakeSettings.targets(on:)`). Decision D9 |
| X5 | The stage-named design scheme was already used here and is now the common one. WP 3-2 no longer edits `design/figma-plugin/code.js` or `manifest.json`; the orchestrator adds `importS3` and the folder (§5, §14.2, §14.3) |
| X6 | "One chained call" in the debug block became one element in the shared demo registry, with the `intake-` prefix and `IntakeDemo.screen(named:)` (§5, §12.9, §14.2, §14.3) |
| X12 (superseded by the second pass below) | The protein floor is whole grams. Added `IntakeProgress.isWholeGramFloor`, `IntakeSettings.setProteinFloorGrams(_:)` and `proteinFloorNeedsWholeGrams` (§4.2, §6.5, §7.4, §9.2.1), the settings states and string (§10.5, §11), four tests and fault line F33 (§12). Decision D8 |
| X13 | No dated calorie-range override. `targets(on:)` keeps its parameter and returns the same targets every day; the claim that stage 5 supplies an override was removed (§1, §9.2, §14.5), with `testTargetsAreTheSameOnEveryDay` and F36. Decision D6 |
| X15 | Supplement questions are excluded from the in-app Coach: correction C12, new §10.6.1, `IntakeSettings.coachVisible`, one line in `AICoach.swift`, `IntakeCoachExclusionTests.swift`, two source scans, F34, F35, F37, a settings caption. Decision D1 |
| X16 | §7.6, §12.8 and the hotspot table record that `IntakeCutoffReminder.swift` must be in stage 5's notification-producer list, added by whichever stage merges second |
| X18 | The builder change is written after stage 2's move to `evaluation(today:)`. §9.4 gives the new initialiser and every construction site, including `CoachPacketAssembler`; §12.3 and §14.3 give the order of the test-file edits |
| X19 | `IntakeFlag` was removed; the flag is `IntakeSettings.flag`, a static `ObservableDefaultsFlag`. Day-key validity and arithmetic go through `CanonicalDay` (§5, §6, §6.4, §8.2, §9.2), with `testTheFlagIsAnObservableDefaultsFlagOverTheIntakeKey`, `testWindowValidityFollowsCanonicalDay` and a source scan |
| X21 | §9.6 names the two whitelist tables instead of line ranges, adds the fork-only comment block and the one-writer order (3, then 5, then 6), states the clear-text content and the drift against the byte-identical contract. Decisions D2 and G5 |
| X22 (extended by the second pass below) | The Intake card's position in Settings and the scorecard protein row's caption follow the combined frame set; edit orders for `SettingsView.swift`, `ScorecardView.swift` and `RedesignRoute.swift` are stated (§10, §10.4, §10.5, §14.3). Question G6 |
| X24 | Path A totals moved from `apple-health` to the dedicated id `noop-intake-health` (C2, §4.1, §5, §8.2, §9.1, §9.4, §12.2, §12.4, §12.7), so deleting Apple Health's imported data cannot remove intake history. The test that asserted the old clearing was replaced by `testDeletingAppleHealthDataLeavesEveryIntakeRow`; F32 added. Decision D7 and question I14 |
| X20 (fixture; applied by instruction although stage 3 is not in its list) | One Fixture Person: §13 now takes stage 1's person, floor and protein days. The hand-worked aggregation samples moved to 2030-12-09 and 2030-12-10, before stage 1's phase, with the same amounts and expected totals (the Los Angeles offset on those dates is eight hours). §13.6 gives app-target and demo values from stage 1 |

Other changes in the same pass:

- **Privacy.** The food app is no longer named anywhere; it is "the owner's food app". The note about
  what a database may hold was reworded so it says nothing about a particular database. The
  fixture's settings are listed for the owner to confirm as invented (§15).
- **Android (R43).** No instruction to write or run Kotlin remains. The stored-data drift is one
  paragraph in §9.6 and the table in §12.7.
- **Build order.** The stage is two merges (common parts and Path B or C; then Path A's bridge and
  `project.yml` edits after the owner's yes), installed with stage 4.
- **Completeness.** §9.2.1 lists the `IntakeSettings` API, and §9.4 the `IntakeProvider`
  initialiser, `live(repository:)` and source-id constants, so tests can be written from this
  document. §12 states that no test touches the standard defaults.

**Shared scaffolding expected from the orchestrator's step 0**

| Scaffolding | What this stage does with it |
|---|---|
| The demo registry line in `StrandiOS/App/StrandiOSApp.swift` | Adds one element, `IntakeDemo` (in 3-6h) |
| Plugin commands `importS2` to `importS6` and the stage-named design folders | Uses `importS3` and `design/round-s3-intake/`; edits no plugin file |
| `ObservableDefaultsFlag` (`Strand/Data/ObservableDefaultsFlag.swift`) | `IntakeSettings.flag` is one instance of it. Expected shape: `@MainActor final class ObservableDefaultsFlag: ObservableObject`, `init(key: String, defaults: UserDefaults = .standard)`, `@Published private(set) var isEnabled: Bool`, `func set(_ enabled: Bool)`. If the scaffolding's shape differs, the scaffolding is authoritative and §9.2.1 and one test follow it |
| `CanonicalDay` (`Packages/StrandAnalytics/Sources/StrandAnalytics/CanonicalDay.swift`) | Day-key validity and day arithmetic in `IntakeAggregation`, `IntakeHealthSync` and the quick-add store. Uses `number(_:)` and `key(_:)` as stage 6 §6.0 lists them |
| `ChargeTypicalBand` | Not used by this stage |
| The fork-only backup keys comment block above the Swift whitelist | Adds `intake.targets` and `intake.supplement.questions` to it (in 3-6h) |

### Second pass

Changes made after the independent re-check and the orchestrator's rulings (a) to (k). Where a line
of the first-pass table above disagrees with this list, this list is the design in force.

| Item | What changed in this file |
|---|---|
| X12 and ruling (b): one whole-gram floor rule, owned by stage 1 | Removed `IntakeProgress.isWholeGramFloor`, `IntakeSettings.proteinFloorNeedsWholeGrams`, the "stored floor that is not whole" settings state, this stage's own statement of the upper bound, `testWholeGramFloorPredicate`, `testFloorSetterAcceptsOnlyWholeGrams`, `testAFractionalStoredFloorIsReportedAndNotRewritten` and the §16 item about the rules sheet. `setProteinFloorGrams(_:)` now writes through `CutScorecardSettings.parameters`, the setter the rules sheet uses, and refuses exactly what `CutScorecardSettings.isWholeGramProteinFloor` refuses; the field calls that one function and nothing else, and the range is stage 1's `proteinFloorMaximumGrams`, not a second constant (§4.2, §6.5, §7.4, §9.2, §9.2.1, §10.5, §11, §13.1, §13.4, D8). A fractional floor stored before R45 reads as the nearest whole gram through stage 1's getter, so this stage has no state for it |
| X12: one printed floor | §7.4 states that the card, ring and widget print the integer of `CutScorecardSettings.proteinFloorWholeGrams`; new tests `testShownFloorIsTheScorecardsWholeGramFloor`, `testFloorSetterWritesThroughTheScorecardSetter`, `testFloorSetterAcceptsExactlyWhatStageOnesRuleAccepts`, `testAFractionalFloorStoredEarlierReadsWholeThroughIntakeSettings`, the scan `test_intake_declares_no_floor_rule_of_its_own`; F33 rewritten, F38 added |
| X22: hotspot edits are one orchestrator commit | New package 3-6h holds the `SettingsView`, `RedesignHealthView`, `RedesignRoute`, `ScorecardView`, `StrandiOSApp` registry and `BackupSettings` edits; they were removed from 3-6 and 3-5a (§9.6, §10.4, §10.5, §14.2, §14.3, §14.4) |
| Ruling (c): one shared-file order that includes stage 3 | §14.3 states the order once and gives, for every shared file, only this stage's position (third). The lists of other stages' edits were removed from §9.6, §10.4, §10.5 and the table |
| Ruling (d): Settings and Health order | §10 states this stage's position: third, below Coach packet and above Body record, with the combined frame set as the authority. The ruling's list places Intake on the Health tab as well, so this stage now has a row there: new §10.9, `HealthIntakeRow`, the `RedesignHealthView.swift` edit in 3-6h, `test_health_row_is_mounted_only_under_the_intake_flag`, F39, decision D11; the earlier sentence that this stage adds no Health row was removed, and the Path C note in §16 follows |
| X6 and ruling (h): demo registry | §5 and §12.9 state only this stage's file (`StrandiOS/Intake/IntakeDemo.swift`), its reserved prefix (`intake-`) and its one registry element; the list of other stages' providers was removed |
| X17, the new-conflict item on files ordered without stage 3, and ruling (i): `AICoach.swift` | §10.6.1 and §14.3 give the order as Lab Book ownership, the stage 2 extraction, this stage's one line, stage 4, with this stage third, and say that stage 2's byte-identity suite is re-run unchanged after the line |
| The same new-conflict item: `CutScorecardModel.swift` and `CoachPacketAssembler.swift` | §14.3 gives this stage's position (third, after stage 2's move) and no other stage's |
| Ruling (k) and the privacy point on §12.8 | The sentence about a check of the diff against the private profile was removed from §12.8. Nothing replaces it in this file |
| Privacy point on §13.1 | Unchanged: the calorie range, hard floor and cutoff remain listed in §15 for the owner to confirm as invented |
| Rulings (a), (e), (f), (g), (j) | Not this stage's. This file does not specify the weigh-in-outranks-scan rule, the private-events switch, the packet's events rows, the `LabMarkerStore` building blocks or `ChargeTypicalBand`, and edits none of their files |

One point the orchestrator should know:

- **The Settings card and "present only while its flag is on".** The Intake card holds the feature
  switch. §10.5 therefore keeps the switch and one sentence visible with the flag off, and makes every
  other row of the card present only while the flag is on. If the combined frame puts the switch
  elsewhere, §10.5's "Flag off" row and the first row of the card follow the frame.
