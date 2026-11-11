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
"Fixture Person" in §13, and every default was chosen for this document.

**The stage is blocked on two owner answers** (Q1: which food app; Q4: may Health reads widen). All
three paths are specified in full so that work starts the moment the owner answers:

| Path | Chosen when | What is built |
|---|---|---|
| A | The food app writes protein and energy to Apple Health **and** the owner approves the wider read | Everything in this document |
| B | No Health writes, or the owner declines the wider read, and accepts a second entry per meal | Everything except §8 (the Health read); the quick-add sheet of §10.3 is the source |
| C | The owner only needs the coach to see intake | Only the supplement tick (§10.6) and the cutoff reminder (§10.7) |

The pure logic (§6, §7), the resolver (§9), the settings, the supplement tick and the cutoff reminder
are common to A and B and are built and tested before the owner answers. Path C is a strict subset.

## 1. Goal and scope

**Goal.** The owner sees today's protein against their floor all day, on the phone and on a widget,
without logging food twice.

**In scope**

- One resolver for "protein on a day" and "energy on a day", used by the card, the detail screen,
  the widget, the stage 1 scorecard's protein signal and (later) the stage 2 packet.
- Path A: reading dietary protein and dietary energy samples from Apple Health into daily totals,
  each with the time it was last read.
- Path B: a quick-add sheet with per-entry edit and delete.
- A protein card in Your Cards and an intake screen: ring to the floor, calories against a range.
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
- A dated override of the calorie range for a planned period. That is an event (stage 5);
  `IntakeSettings.targets(on:)` takes the day so stage 5 can supply one without touching callers.
- Any direct connection to a food app, an MCP server, or a network path.
- A migration, a new build target, a new entitlement. None is needed and none is added.
- Android. No Kotlin is written (R43). The dispositions are in §12.7.
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
| C2 | ROADMAP: daily totals stored "in the Apple Health source namespace already used by imported series" | True, but the metric catalogue binds `protein_g` and `calories_in` to source `nutrition-csv` (`Strand/Data/MetricCatalog.swift:186-187`), so rows under `apple-health` are invisible to Explore, whose "Protein" stays the CSV history | Accepted. Explore keeps showing one labelled source's history (allowed by R41). No catalogue descriptor is added |
| C3 | ROADMAP: "Each total carries the time it was last read" | `metricSeries` has no time column (`Database.swift:204-210`) | The read time is a sibling key, `intake_read_at`, written in the same transaction as the totals (§9.1). No migration |
| C4 | ROADMAP WP 3-4: "pure, with Kotlin twin if it is stored or analytic" | Superseded by R43 | No twin. Written dispositions in §12.7 |
| C5 | ROADMAP: "A new widget kind; the App Group payload gains optional fields only" | `StrandTests` compiles the shared payload files by name (`project.yml:170-189`), and `Tools/check_personal_widgets.py:36` compiles `PersonalWidgetMetrics.swift` alone | The new payload type goes **inside** `StrandiOSShared/PersonalWidgetMetrics.swift`, Foundation only, so `project.yml` and that script need no change |
| C6 | ROADMAP: the cutoff reminder is "coordinated with the existing wind-down" | `WindDownNudge` exposes no hook or change notification; its schedule lives in the notification centre and its settings in private keys (`WindDownNudge.swift:19-29`) | Coordination is one-way: the cutoff reads the nudge's public statics and adapts itself. The nudge is not edited (§7.6). A change to the nudge takes effect on the cutoff at the next app activation |
| C7 | ROADMAP test plan: "a step-only or protein-only update does not disturb unrelated Health columns or series" | A `metricSeries` upsert touches exactly one `(deviceId, day, key)` (`MetricSeriesStore.swift:38-50`); protein never touches `appleDaily` | The risk is the reverse: a wide delete. Tested in §12.2 |
| C8 | CONTEXT §4: the Health usage text is not mentioned | The permission sheet text names only "steps and workout summaries" (`project.yml:314`; generated copy `StrandiOS/Resources/Info.plist:66-67`) | Path A changes that sentence in `project.yml` (owner go-ahead G2, §15) |
| C9 | ROADMAP surfaces: a "Calories" line | `DashboardCard.calories` already exists and means **active energy burned** (`Strand/Screens/DashboardCards.swift:33`, `:104`) | Intake energy is never titled "Calories" alone. It is "Calories eaten" (§11) and has no card of its own |
| C10 | ROADMAP: "Authorisation: … Simulator first, then the device" | A comment in the bridge states HealthKit has no simulator support (`HealthKitBridge.swift:357`) | Not settled by reading (§16). The plan does not depend on it: every decision is in code that tests on macOS (§8.2) |
| C11 | CONTEXT §3 item 3: a protein floor "shown beside the daily rings" | ROADMAP stage 3 says a card in Your Cards | The card. A fourth headline ring is not designed |

## 4. Every reader and writer

### 4.1 Protein and energy intake

| Location | Reads or writes | After this stage |
|---|---|---|
| `Strand/Screens/DataSourcesView.swift:426-450` | Writes `calories_in`, `protein_g`, `carbs_g`, `fat_g`, `weight` under `nutrition-csv` | Unchanged. An import writer |
| `Strand/Data/CutScorecardInputBuilder.swift:50-52` | Reads `protein_g` under `nutrition-csv` for the scorecard's protein signal | **Resolver.** Reads `IntakeProvider.proteinDays()` (§9.4) |
| `Packages/StrandAnalytics/Sources/StrandAnalytics/CutScorecard.swift:484-490`, `:700-722` | Consumes the protein days it is handed; judges the seven days before the weigh-in, never the weigh-in day | Unchanged. Not edited |
| `Strand/Data/MetricCatalog.swift:186-189`; `Strand/Screens/MetricExplorerView.swift:1962` | Explore lists and colours the `nutrition-csv` series | Unchanged. One source's labelled history |
| `Strand/Data/CsvExport.swift:106` | Exports every key under each source | Unchanged. The new rows are exported as they are |
| `Strand/Data/Repository.swift:1850-1862` (`series(key:source:)`) | The generic read used by the above | Unchanged; `IntakeProvider` calls it |
| `Strand/AI/AICoach.swift:1207`, `:1607` | Coach context. Reads no intake today (searched: no dietary or protein key) | Unchanged in this stage |
| `StrandiOS/Widgets/WidgetPublish.swift:126-218` | Builds the personal widget payload (steps, sleep, goal) | Gains the intake reading from `IntakeProvider` (§8.4) |
| New: `IntakeHealthSync` | Writes `protein_g`, `calories_in`, `intake_read_at` under `apple-health` | Path A only |
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
| New: `IntakeSettings.proteinFloorGrams` | A pass-through to `CutScorecardSettings.parameters.proteinFloorGrams`. It stores nothing of its own (§9.2) |

The floor keeps exactly one home. The intake screen's floor field and the rules sheet's field are two
editors of one stored value, and §12.3 asserts it.

### 4.3 Other facts the stage touches

| Fact | Existing readers and writers | This stage |
|---|---|---|
| Health read set and fingerprint | `HealthKitBridge.swift:100-105`, `:186-190`, `:209-227`, `:232-266` | `readTypes` gains two types only while `IntakeSettings.healthReadEnabled` is true (§8.1) |
| Observed Health types | `HealthKitBridge.swift:333-388` | The two dietary types join the activity-only list under the same condition |
| Journal answers | Writers: `Strand/Screens/JournalLogCard.swift:225`, `:253`, `:398-400`, `:630-632`, `:660`; `Strand/Screens/InsightsView.swift:887`; `Strand/Screens/CoachView.swift:1068`. Readers: `Repository.swift:2665-2708` and the insights that consume them | The supplement tick is one more writer of the same row, through the same two repository calls (§10.6) |
| Wind-down schedule | Written only by `WindDownNudge` (`:199-240`), driven from `Strand/Screens/SmartAlarmView.swift:472-743` | Read only |
| Widget payload | Writer `StrandiOS/Widgets/WidgetPublish.swift:47`, `:214-217`, `:248-255`; readers the widget views | One optional field; one new reader |
| Today card list | `Strand/Data/TodayCardReadout.swift:116-121`, `:127-137`; `Strand/Screens/DashboardCards.swift:20-58` | One new case and one new defaulted parameter |

## 5. Final names

| Thing | Name | Where |
|---|---|---|
| Pure aggregation | `IntakeAggregation` and its types (§6) | `Packages/StrandAnalytics/Sources/StrandAnalytics/IntakeAggregation.swift` |
| Pure progress | `IntakeProgress` and its types (§6.5) | `Packages/StrandAnalytics/Sources/StrandAnalytics/IntakeProgress.swift` |
| Resolver | `IntakeResolver` (pure), `IntakeProvider` (repository-backed) | `Strand/Data/IntakeResolver.swift`, `Strand/Data/IntakeProvider.swift` |
| Settings and flag | `IntakeSettings`, `IntakeFlag` | `Strand/Data/IntakeSettings.swift` |
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
| Source ids | `apple-health` (existing), `noop-intake` (new), `nutrition-csv` (existing) | §9.1 |
| Series keys | `protein_g`, `calories_in` (both existing), `intake_read_at` (new) | §9.1 |
| Notification ids | `intake-cutoff-wd1` … `intake-cutoff-wd7` | §7.6 |
| Design round | `design/round-s3-intake/`; plugin command `importS3`; export `s3-frames.json` | Named by stage, not by round number, so parallel stages cannot collide |
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
counts as a sample. If `firstDay` or `lastDay` is not a canonical real day key (stage 1 R5), or
`firstDay > lastDay`, the result has no totals, no empty days, and every sample counted as
`outsideWindow`.

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
  today's key under the log. `firstDay` is `lastDay` minus `days`. `end` is the start of the day
  after `lastDay` in the current zone. `start` is the start of the day `days + 4` before today in
  the current zone (§7.3).
- `apply`: nil samples → `failedRead`. Otherwise aggregate with the stored zone log and
  `IntakeSettings.admittedHealthSources`, read the stored days for the window under `apple-health`
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
| `apple-health` | `protein_g` | grams for the day | `IntakeHealthSync` only |
| `apple-health` | `calories_in` | kilocalories for the day | `IntakeHealthSync` only |
| `apple-health` | `intake_read_at` | epoch seconds of the last confirming read | `IntakeHealthSync` only |
| `noop-intake` | `protein_g`, `calories_in` | sums of that day's quick-add entries | `IntakeQuickAddStore` only |
| `noop-intake` | `intake_read_at` | epoch seconds of the last entry change | `IntakeQuickAddStore` only |
| `nutrition-csv` | `protein_g`, `calories_in`, … | as today | The CSV import, unchanged |

Three sibling keys for one day are written by one `upsertMetricSeries` call, which is one
transaction (`MetricSeriesStore.swift:31-35`), so a total and its read time cannot be torn apart.

R42: none of these ids is a strap id. Removing, forgetting or losing a strap deletes rows only under
that strap's id (`Packages/WhoopStore/Sources/WhoopStore/DeviceRegistryStore.swift:162-173`, `:203-215`)
and cannot touch them. Deliberately forgetting the Apple Health source clears `apple-health` rows,
intake included; the next read restores the window. A test asserts both (§12.2).

The keys `protein_g` and `calories_in` are reused, not renamed, so the three sources hold the same
quantity under the same name and unit.

### 9.2 Settings

All in `UserDefaults.standard`, declared in `IntakeSettings`. `IntakeFlag` is the observable copy of
the flag, built exactly as `CutScorecardFlag` is (`Strand/Data/CutScorecardModel.swift:18-48`).

| Key | Type | Default | Meaning |
|---|---|---|---|
| `noop.intakeEnabled` | Bool | `false` | The feature flag. Off: no card, no screen, no tick, no reminder, no Health read, no widget data, legacy resolver policy |
| `intake.source` | String | absent (`none`) | `none`, `appleHealth` or `quickAdd`. Path C is `none` |
| `intake.targets` | String | absent | JSON object, sorted keys: `{"energyHardFloorKcal":2100,"energyHighKcal":2600,"energyLowKcal":2400,"v":1}`. Any key may be omitted. An object that fails to parse or fails `IntakeTargets.isValid` is treated as absent and the screen says the targets need attention |
| `intake.zoneLog` | String | absent | JSON array of `{"from":0,"tz":"Etc/UTC"}`, ascending |
| `intake.health.sources` | String | absent (all) | JSON array of admitted bundle ids |
| `intake.health.knownSources` | String | absent | JSON object: bundle id → `{"lastSeenDay":"2031-03-10","name":"Fixture Food"}`. For the source picker and the "two apps" line |
| `intake.health.backfilled` | Bool | `false` | The 90-day backfill has run |
| `intake.supplement.questions` | String | absent | JSON array, at most four canonical Journal questions, in display order |
| `intake.cutoff.enabled` | Bool | `false` | The reminder switch |
| `intake.cutoff.minuteOfDay` | Int | 1260 | Minutes after local midnight. Also closes the day for §7.5 when set, whether or not the reminder is on |
| `intake.cutoff.timeSet` | Bool | `false` | The owner has chosen a cutoff time. False: the day closes only at midnight |
| `intake.quickAdd.presets` | String | absent | JSON array, at most six `{"energyKcal":150,"label":"Fixture shake","proteinGrams":30}` |
| `intake.entries.<yyyy-MM-dd>` | String | absent | That day's quick-add entries (§9.3) |

The protein floor is **not** in this table. `IntakeSettings.proteinFloorGrams` gets and sets
`CutScorecardSettings.parameters.proteinFloorGrams`, whatever the state of the scorecard flag.
`IntakeSettings.targets(on day: String) -> IntakeTargets` combines that floor with `intake.targets`.

Reading never rewrites a stored string (stage 1 R30).

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
three source ids and the three keys, holds the resolved series, exposes a `revision`, and refreshes
after every completed repository refresh, after every `IntakeHealthSync` write and after every
`IntakeQuickAddStore` write (stage 1 R32). With the flag off it does no work when nothing asks.

```swift
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
takes `provider.proteinDays()`. The builder gains an `IntakeProvider` parameter. With
`noop.intakeEnabled` off the policy is `legacy` and the list is the `nutrition-csv` series, value for
value what the builder passes today; the existing tests
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
| `intake.targets` | String | **Yes** (`Packages/WhoopStore/Sources/WhoopStore/BackupSettings.swift:49-76`, `:81-97`) | Not updated, by the owner's decision |
| `intake.supplement.questions` | String | **Yes** | Not updated, by the owner's decision |
| `noop.intakeEnabled`, `intake.source`, `intake.health.*`, `intake.zoneLog`, `intake.cutoff.*`, `intake.entries.*`, `intake.quickAdd.presets` | — | No. Per install: they depend on this phone's Health permission, notification permission, zone history and food app | — |

The daily totals are `metricSeries` rows and ride the database backup as every series does. The
supplement answers are Journal rows and do too. The protein floor is already carried inside
`cutScorecard.rules`.

**The drift this creates.** Android's codec iterates its own whitelist and drops any key it does not
list (`android/app/src/main/java/com/noop/data/BackupSettings.kt:92-107`). A backup made on the iPhone
and restored on Android loses `intake.targets` and `intake.supplement.questions` silently, and a
backup then made on Android does not contain them. The database rows survive on both. Nothing on
Android reads either key. This adds two keys to the pre-existing whitelist difference recorded in
stage 1 (C10 there).

The marker catalogue (`Packages/StrandImport/Sources/StrandImport/MarkerCatalog.swift`) is **not
edited** by this stage on either platform.

## 10. Screens and states

Frames are designed at G1 in `design/round-s3-intake/`. This section fixes what each surface must
be able to show. Every state needs a frame at the default text size and at `accessibility5`.
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
the intake screen.

### 10.5 Settings

A card in Settings, iPhone only, below the scorecard card (`Strand/Screens/SettingsView.swift:466`,
`:1854-1977`). Rows: the feature switch; source (None, Apple Health, Enter here); protein floor (the
same stored value as the rules sheet's "Daily floor"); calorie range low and high; hard floor; Health
apps to count (Path A, when more than one is known); supplements; cutoff time; cutoff reminder.

| State | What shows |
|---|---|
| Flag off | Only the switch and one sentence |
| Flag on, source None | The other rows; a caption that the card and widget have nothing to show |
| Choosing Apple Health | HealthKit's sheet for the two types, once; then a first read |
| Apple Health chosen, Health unavailable or the build lacks the entitlement | The row reverts and says why, using the bridge's existing states (`HealthKitBridge.swift:20-28`, `:91-95`) |
| Range invalid (low above high, hard floor above low) | The field is marked and nothing is saved |
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
| Supplements | "Supplements", "Marked not taken in Journal" |
| Chart | "More days will appear here" |
| Notification | "Food cutoff" / "Your cutoff time is now." |
| Widget | "Protein", "%lld g to go", "Floor met", "+%lld g over", "as of %@", "Last read %@", "Nothing logged today", "No floor set", "Set up in NOOP", "Open NOOP to refresh" |
| Health permission sentence (Path A, `project.yml:314`) | "NOOP reads your steps, workout summaries and, if you turn on Intake, the protein and energy your food app logs, from Apple Health on-device. Nothing leaves your device." |

None of these states or implies a health outcome. "Below your floor of N kcal" reports the owner's
own number against the owner's own setting and nothing more. No string praises, warns or urges.

## 12. Test plan

One named test per line. Names state the behaviour protected. Tests are written from this document
and §13 by an agent that does not see the implementation.

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

### 12.2 Store — `Packages/WhoopStore/Tests/WhoopStoreTests/IntakeSeriesTests.swift`

- `testTotalsAndReadTimeAreWrittenInOneTransaction`
- `testIntakeKeysDoNotDisturbOtherKeysUnderAppleHealth` (seed `steps` and `weight`; write and delete
  intake; assert both untouched)
- `testIntakeDeletionRemovesOnlyTheNamedDayAndKey`
- `testIntakeRowsSurviveDeletingAStrapsData` (R42: `deleteAllData` for a strap id)
- `testForgettingAppleHealthClearsItsIntakeRowsAndNotQuickAdd`
- Additions to `BackupSettingsTests.swift`: `testIntakeTargetsAndSupplementQuestionsRoundTrip`,
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
  number; then deletes the Health rows and asserts all four move together)
- `testFloorHasOneStoredCopy` (set through `IntakeSettings`; read through `CutScorecardSettings`;
  and the reverse; assert `intake.targets` never contains a protein key)
- `testRingCompleteAndScorecardDayCountedAgree`

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
- `StrandTests/CutScorecardInputBuilderTests.swift`: `testProteinDaysFollowTheIntakeResolverWhenTheFlagIsOn`

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
- `test_intake_backup_keys_are_swift_only_by_decision`: the two keys are in the Swift whitelist,
  absent from the Kotlin one, and the test's message quotes R43, so the drift is deliberate and visible.

### 12.5 Flag-off equivalence

With `noop.intakeEnabled` off: `renderList` keeps its call shape through a defaulted parameter; the
resolver policy is `legacy` and the scorecard's protein days are the CSV series as before; the Health
fingerprint string is unchanged; no notification request exists; no `metricSeries` row, defaults key
or Journal row is written; the widget payload bytes are unchanged. Direct assertions:
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
| F30 | Intake delete widened to the whole source | `testIntakeKeysDoNotDisturbOtherKeysUnderAppleHealth` |
| F31 | A number placed in the notification body | `testNotificationTextCarriesNoNumber` |

### 12.7 Parity: written dispositions (R43)

No Kotlin is written. Each is recorded in the pull request.

| Piece | Disposition |
|---|---|
| `IntakeAggregation`, `IntakeProgress` (package analytics) | No twin. iPhone-only feature; Android has no intake surface. New public declarations in `StrandAnalytics` carry the "No Kotlin twin" doc line; the parity ledger will list them as one-sided, which is recorded debt, not a failure to hide |
| Stored rows: `protein_g`, `calories_in`, `intake_read_at` under `apple-health` and `noop-intake` | Not updated on Android, by the owner's decision. Drift: an Android build restoring this database keeps the rows but shows none of them, and its Health Connect import does not write them. `intake_read_at` would appear in an Android CSV export as an unlabelled column |
| Backup keys `intake.targets`, `intake.supplement.questions` | Not updated on Android, by the owner's decision. Drift as in §9.6 |
| `DashboardCard.protein` | No Android id. A dashboard selection containing `protein` restored on Android has an unknown id, which its decoder drops; dashboard selections are not in the backup whitelist in any case (`BackupSettings.swift:40-42`) |
| Journal question created for a supplement | Carried by the existing `journal.customBehaviors` key on both platforms. No change |
| Marker catalogue | Not edited |
| Gate script | Android rows waived by flag and reported as waived (R43) |

### 12.8 Privacy scans

- `testWidgetPayloadCarriesNoCaloriesLabelsOrSourceNames`: encode a payload built from the
  fixture and assert the bytes contain none of the fixture's energy figures, entry labels, bundle
  ids, source names or supplement names.
- `testNotificationTextCarriesNoNumber` (above), and it asserts the fixture's supplement name and
  floor are absent too.
- `testBackupSettingsCarryNoEntryLabelsOrSourceIds`.
- A grep in the gate's pull-request checklist for the private profile's values is the
  orchestrator's, run against the diff from the ignored file, with nothing echoed.

### 12.9 Simulator and rehearsal

- Every frame of §10 reproduced from `IntakeDemo` at the default and largest text size, Reduce
  Motion on and off: `--demo-screen intake-<state>` names, chained after the scorecard's in the debug
  block (`StrandiOS/App/StrandiOSApp.swift:623`), compiled for the simulator only as the scorecard's
  flows are.
- Flows by tapping: add, edit, delete, backdate a quick-add entry; tick and untick; change the
  source; set and clear targets.
- Path A on the device, with the owner: the discovery checklist (§14.1), then a known meal logged
  in the food app, NOOP opened, the total and its time confirmed; an entry edited and one deleted at
  the source and the totals followed; the phone locked for an hour and the widget's state recorded.
- Real-data rehearsal on the private copy (0B-7): flag off, the scorecard's protein row is
  unchanged; flag on with source None, the same. Results stay out of the repository.

## 13. Fixture

`Packages/StrandAnalytics/Tests/StrandAnalyticsTests/IntakeFixture.swift`. Fixture Person is
invented. Instants are written as UTC ISO strings and parsed by a helper in the fixture.

### 13.1 Person and settings

| Setting | Value |
|---|---|
| Protein floor | 100 g |
| Calorie range | 2400 to 2600 kcal |
| Hard floor | 2100 kcal |
| Cutoff time | 20:00 (minute 1200) |
| Supplement | "Fixture supplement"; question "Did you take Fixture supplement?" |
| Food app | name "Fixture Food", bundle id `app.fixture.food` |
| Second app | name "Fixture Other", bundle id `app.fixture.other` |
| Preset | "Fixture shake": 30 g, 150 kcal |

### 13.2 Samples

All from `app.fixture.food` unless stated. Window `2031-03-10 ... 2031-03-11`.

| id | Nutrient | Instant (UTC) | Amount |
|---|---|---|---|
| s1 | protein | 2031-03-10T08:00:00Z | 30 |
| s2 | energy | 2031-03-10T08:00:00Z | 450 |
| s3 | protein | 2031-03-10T13:00:00Z | 40 |
| s4 | energy | 2031-03-10T13:00:00Z | 700 |
| s5 | protein | 2031-03-10T23:59:59Z | 25 |
| s6 | energy | 2031-03-10T23:59:59Z | 300 |
| s7 | protein | 2031-03-11T00:00:00Z | 20 |
| s8 | energy | 2031-03-11T00:00:00Z | 250 |
| s9 (`app.fixture.other`) | protein | 2031-03-10T10:00:00Z | 10 |

### 13.3 Expected totals

Zone log U: `[(0, "Etc/UTC")]`.

| Case | 2031-03-10 protein / energy | 2031-03-11 protein / energy |
|---|---|---|
| s1 to s8, log U | 95 / 1450 | 20 / 250 |
| s1 to s9, all sources | 105 / 1450 | 20 / 250 |
| s1 to s9, admitted `app.fixture.food` | 95 / 1450, one `excludedSource` | 20 / 250 |
| Edit: s3 replaced by s3b (same instant, 45) | 100 / 1450: exactly at the floor | 20 / 250 |
| Delete s5 and s6 | 70 / 1150 | 20 / 250 |
| Delete s7 and s8 | 95 / 1450 | empty day; stored rows deleted by the plan |
| No samples at all | plan writes nothing; stored rows kept | same |

Zone log E (eastward): `[(0, "Etc/UTC"), (2031-03-10T18:00:00Z, "Pacific/Auckland")]`. Auckland is
thirteen hours ahead of UTC on these dates. With s1 to s8:

| Day | Samples | Protein / energy |
|---|---|---|
| 2031-03-10 | s1 to s4 (before the change, UTC day) | 70 / 1150 |
| 2031-03-11 | s5 to s8 (after the change, Auckland day) | 45 / 550 |

Zone log W (westward): `[(0, "Pacific/Auckland"), (2031-03-10T20:00:00Z, "America/Los_Angeles")]`.
Los Angeles is seven hours behind UTC on these dates. Two protein samples: x at
`2031-03-10T19:00:00Z` (10 g) falls on 2031-03-11 in Auckland; y at `2031-03-10T21:00:00Z` (15 g)
falls on 2031-03-10 in Los Angeles. The later instant is on the earlier day, and each is counted once.

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
(stage 1 R31). The 2031 fixture is for the pure functions.

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
| 3-2 | Designer | A, B, C | `design/round-s3-intake/` (new); `design/figma-plugin/code.js`, `manifest.json` (one command, `importS3`) |
| 3-3 | Test author | A, B, C | Every test file named in §12; `IntakeFixture.swift`; additions to the four existing test files named in §12.3; `Tools/test_intake_single_resolver.py` |
| 3-4 | Implementer A (pure) | A, B | `Packages/StrandAnalytics/Sources/StrandAnalytics/IntakeAggregation.swift`, `IntakeProgress.swift` |
| 3-5a | Implementer B (storage and resolver) | A, B, C | New: `Strand/Data/IntakeSettings.swift`, `IntakeResolver.swift`, `IntakeProvider.swift`, `IntakeQuickAddStore.swift`, `IntakeSupplementTick.swift`, `IntakeHealthSync.swift`. Edited: `Strand/Data/CutScorecardInputBuilder.swift` (the protein read only) and its construction sites; `Packages/WhoopStore/Sources/WhoopStore/BackupSettings.swift` |
| 3-5b | Implementer B, after G1 go-ahead | A only | `StrandiOS/Health/HealthKitBridge.swift` (`readTypes`, `enableLiveDelivery`, `collectIntakeSamples`, `requestIntakeReadAccess`, the call in `sync`) |
| 3-6 | Implementer C, after design approval and after 3-4 and 3-5a merge | A, B (C: tick and reminder parts) | New: `Strand/Data/IntakePresenter.swift`, `IntakeModel.swift`; `Strand/System/IntakeCutoffReminder.swift`; `StrandiOS/Intake/IntakeView.swift`, `IntakeQuickAddSheet.swift`, `IntakeSettingsSection.swift`, `IntakeDemo.swift`. Edited: `Strand/Screens/DashboardCards.swift`, `Strand/Data/TodayCardReadout.swift`, `Strand/Screens/TodayCustomizationMetadata.swift`, `Strand/Screens/TodayCustomizationSheet.swift`, `Strand/Data/TodayCardsEditorPresentation.swift`, `StrandiOS/Redesign/YourCardsSection.swift`, `StrandiOS/Redesign/RedesignRoute.swift`, `StrandiOS/Redesign/RedesignTodayView.swift` (card inputs and the flag), `Strand/Screens/SettingsView.swift` (one card), `StrandiOS/App/RootTabView.swift` (reminder reconcile), `StrandiOS/App/StrandiOSApp.swift` (one line in the debug block), `StrandiOS/Scorecard/ScorecardView.swift` (the protein row's caption and tap); `Strand/Screens/TodayView.swift` and `Strand/Liquid/LiquidTodayView.swift` only to keep their `DashboardCard` switches exhaustive |
| 3-7 | Implementer D | A, B | `StrandiOSShared/PersonalWidgetMetrics.swift`; `StrandiOSWidgets/PersonalProteinWidget.swift` (new); `StrandiOSWidgets/NOOPWidgetBundle.swift`; `StrandiOS/Widgets/WidgetPublish.swift` |
| 3-8 | Localiser | A, B, C | `Strand/Resources/Localizable.xcstrings`; `StrandiOSWidgets/Localizable.xcstrings` |
| 3-9 | Orchestrator, after G2 go-ahead | A only | `project.yml` (the usage sentence), then `xcodegen generate` |
| 3-10 | Reviewers (correctness, contract, data safety) and Verifier | all | None |

Path C builds 3-3 (the tick, reminder, settings and flag tests), the settings, tick and reminder
parts of 3-5a and 3-6, and 3-8. It builds no card, no widget, no resolver switch and no Health read.

### 14.3 Shared hotspots and order

| File | Edited by | Rule |
|---|---|---|
| `Strand/Resources/Localizable.xcstrings`, `StrandiOSWidgets/Localizable.xcstrings` | 3-8 | Sole writer, once, after the English strings are final. Serialised across stages |
| `Strand/Screens/DashboardCards.swift` | 3-6 | One new case in each switch. Serialised across stages: every stage that adds a card edits the same switches |
| `Strand/Data/TodayCardReadout.swift` | 3-6 | One defaulted parameter, one `Tap` case, one readout case. Serialised across stages |
| `Strand/Screens/SettingsView.swift` | 3-6 | One self-contained card. Serialised across stages |
| `Strand/Screens/TodayView.swift`, `Strand/Liquid/LiquidTodayView.swift`, `StrandiOS/Redesign/RedesignTodayView.swift` | 3-6 | Exhaustiveness only in the first two; card inputs in the third. Serialised across stages |
| `StrandiOS/App/StrandiOSApp.swift` (debug block) | 3-6 | One chained call. Serialised across stages |
| `Packages/StrandImport/…/MarkerCatalog.swift` | nobody | Not edited by this stage |
| `StrandiOSShared/PersonalWidgetMetrics.swift`, `StrandiOS/Widgets/WidgetPublish.swift`, `StrandiOSWidgets/NOOPWidgetBundle.swift` | 3-7 | One implementer. Serialised with any other stage that adds a widget or payload field |
| `Strand/Data/CutScorecardInputBuilder.swift`, `StrandiOS/Scorecard/ScorecardView.swift` | 3-5a, then 3-6 | Stage 1 files. Serialised with stage 1 follow-up work and with stage 2 if it touches the builder |
| `StrandiOS/Health/HealthKitBridge.swift` | 3-5b | One implementer; no other stage is expected to edit it |
| `Packages/WhoopStore/…/BackupSettings.swift` | 3-5a | Two lines in each table. Serialised with any stage adding keys |
| `project.yml` | 3-9 | Orchestrator only |

### 14.4 Parallel and serial

Can run in parallel with other stages, because the files are new: 3-2 (design), 3-3 (tests in new
files), 3-4 (pure logic), the new files of 3-5a, the new files of 3-6 and 3-7 once design is approved.

Must be serialised with other stages: every row of §14.3. The practical rule is that each stage's
edits to the hotspot files are one small commit, applied by the orchestrator one stage at a time
onto the integration branch, with the Localiser last.

Within the stage: 3-3 and 3-4 start now, before the owner answers. 3-5a's settings, tick, resolver
and quick-add store start now. 3-5b waits for G1. Interface code (3-6, 3-7 views) waits for design
approval. 3-6 follows 3-4 and 3-5a. 3-8 follows 3-6 and 3-7.

Consumers: stage 2's packet takes its intake section from `IntakeProvider.series()` and prints the
source beside each value; it must not read the store. Stage 5 may supply a dated override through
`IntakeSettings.targets(on:)`.

## 15. Open questions for the owner

Work proceeds on each recommendation.

**Needs the owner's go-ahead before the named work starts**

| # | What | Why | The alternative that avoids it |
|---|---|---|---|
| G1 | Widen Apple Health reads to dietary protein and dietary energy (Q4), only while Intake is on with Apple Health as its source | Path A cannot exist without it | Path B (quick-add) or Path C |
| G2 | Change the Health permission sentence in `project.yml` (§11, last row) | The current sentence names only steps and workouts | Leave it; the sheet then asks for nutrition under a sentence that does not mention it. Not recommended |
| G3 | A new widget kind in the existing widget extension | It is the stage's widget. No new target, identifier, profile or entitlement | Add a protein line to an existing widget instead; that changes an accepted widget |
| G4 | One more local notification (the cutoff), opt-in, off by default | Notification budget | Path without the reminder: the cutoff time still closes the day in §7.5 |
| G5 | Two Swift-only backup keys, with the Android drift of §9.6 | Targets and supplement choices survive a restore | Leave them out; they are re-entered after a restore |

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

## 16. Not determined

- **Which app "Instinct" is**, whether it writes dietary types to Health, whether it stamps the meal
  time or the logging time, and whether its edits and deletes propagate. Only the spike can tell.
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
- **Whether the owner's database already holds `nutrition-csv` rows.** The rehearsal shows it. The
  resolver handles both cases.
- **Whether Explore's "Protein" row, labelled "Nutrition", will confuse** once another source feeds
  the intake screen. It is one source's history and is left as it is; a clearer label is a
  one-string change the owner can ask for.
- **Parity ledger behaviour** for one-sided `StrandAnalytics` declarations (stage 0 item 0B-9). The
  doc-line wording in §6 was not run through the ledger.
- **Android.** Nothing on the Kotlin side was read beyond the backup codec lines cited, and nothing
  was compiled or run.
- **Expected values in §13** were worked by hand for this document. The test author recomputes
  them; a disagreement is reported, not silently corrected.

## 17. Design approval record (G1)

Not yet submitted. Frames, page name, the approval date and the owner's choices are recorded here
when the owner approves.
