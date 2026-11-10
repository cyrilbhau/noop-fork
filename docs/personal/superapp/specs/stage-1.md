# Stage 1 specification — weigh-in and scorecard

Gate G0 for stage 1 of the health super-app workstream. Read [CONTEXT.md](../CONTEXT.md),
[ROADMAP.md](../ROADMAP.md) (stage 1) and [QUALITY-GATES.md](../QUALITY-GATES.md) first.

Verified against the source at commit `6413d94c` (branch `personal/superapp-1-spec`, cut from
`personal/superapp-0-foundation`). Every `path:line` below is as of that commit. Paths are relative to
the repository root. Nothing was built or run for this document; it is a reading of the code.

This file contains no personal measurements. Every number in an example belongs to the synthetic
"Fixture Person" in §13, and every default in §6.3 was chosen for this document.

## 1. Goal and scope

**Goal.** The owner records weight and waist once a week in under thirty seconds and sees a verdict
derived only from their own fixed rules.

**In scope**

- A weigh-in sheet (weight, then waist) with backdating, and a history list with edit and delete.
- One resolver for "current weight" and "current waist", used by Today, the profile-dependent
  estimates and the new screen.
- A pure function producing weekly points, rate of loss, a projection, four signals and a verdict.
- Phase configuration and the owner's rule parameters as settings.
- An entry card in Your Cards, behind a default-off flag.
- An optional weekly local reminder, off by default.

**Out of scope**

- Daily weigh-in prompts, streaks, badges, any nudge beyond the one opt-in weekly reminder.
- Any automatic change to a calorie target or any other setting. The verdict is text. Nothing is
  written anywhere as a result of it.
- Smart-scale pairing. Any change to the Apple Health read set (`readTypes` stays as it is).
- Charts with horizontal bands, target lines or rules. Curves and fills only.
- Rules for phases that are not a cut. A phase of any other kind produces no verdict (§7.2).
- Android screens. Android receives the Kotlin twin of the pure function and the two backup keys only.
- Any medical statement. The screen reports the owner's own numbers against the owner's own rules.
- A migration. None is needed and none is added.

## 2. Re-check of "what exists"

| # | Claim in the planning documents | Status | Evidence |
|---|---|---|---|
| 1 | `labMarker` stores timestamped readings; columns `id`, `deviceId`, `markerKey`, `category`, `day`, `takenAt`, `value`, `valueText`, `unit`, `source`, `note`, `referenceText` | Confirmed | `Packages/WhoopStore/Sources/WhoopStore/Database.swift:330-356` (migration `v17-lab-book`) |
| 2 | Catalogue keys `weight`, `waist`, `body_fat`, `height` exist | Confirmed: `weight` kg, `body_fat` %, `waist` cm, `height` cm, all one decimal, category `bodyMeasurement` | `Packages/StrandImport/Sources/StrandImport/MarkerCatalog.swift:111-114`; category enum `LabMarker.swift:26-33` |
| 3 | A Kotlin twin of the catalogue exists | Confirmed, same four entries | `android/app/src/main/java/com/noop/analytics/MarkerCatalog.kt:102-105` |
| 4 | The newest migration is `v47-rr-whoop5-fill` | Confirmed | `Database.swift:1103` |
| 5 | Lab Book has an editor with a unit switcher for dual-unit markers | Confirmed for five blood markers only. Weight and waist have no switcher (see §3, C3) | `Strand/Screens/MarkerEditorView.swift:483-499` |
| 6 | `Profile.weightKg`, `waistCm`, `heightCm` are single profile values feeding VO₂max and calorie estimates | Confirmed. The type is `ProfileStore`. Weight defaults to 75 and height to 178 when never set; waist uses 0 for "not set" | `Strand/Data/Profile.swift:23-27`, `:88-92`, `:125-127` |
| 7 | Today resolves weight as Apple Health first, profile second (search `#204`) | Confirmed for display, with three differing implementations (see §3, C2) | `Strand/Liquid/LiquidTodayView.swift:2946`, `:3130`, `:3246-3252`, `:1613-1618`; `Strand/Screens/TodayView.swift:4136-4139`, `:4694`, `:5212-5217`; `StrandiOS/Redesign/RedesignTodayView.swift:608-614` |
| 8 | `weight` and `body_fat` are Apple Health sourced series in the metric catalogue | Confirmed | `Strand/Data/MetricCatalog.swift:179-180` |
| 9 | Lift sessions and sets are stored; pasted-text and CSV imports exist | Confirmed. Imports are written under device id `lifting` with session id `lift-import:<startTs>` | `Database.swift:978-1101`; `Strand/Data/PersonalLiftingImport.swift:6-33`; `Packages/WhoopStore/Sources/WhoopStore/LiftLogImport.swift:8-18` |
| 10 | Health reads are limited to workouts and steps while activity-only mode is on | Confirmed. Body mass is in the full read list but is not requested in this build | `StrandiOS/Health/HealthKitBridge.swift:67` (`activityImportsOnly = true`), `:100-105`, `:140` |
| 11 | The `.noopbak` whitelist carries only Int, Double and String | Confirmed | `Packages/WhoopStore/Sources/WhoopStore/BackupSettings.swift:29-31`, `:49-70`; `android/app/src/main/java/com/noop/data/BackupSettings.kt:36`, `:50-76` |
| 12 | Coach context includes a Lab Book roll-up | Confirmed: latest reading per marker, first eight markers | `Strand/AI/AICoach.swift:1268-1285` |
| 13 | There is no weekly weigh-in flow, rate of loss, projection or scorecard | Confirmed. `AdaptiveExpenditureEngine` computes a weight slope for a different purpose and has no caller in the app targets | `Packages/StrandAnalytics/Sources/StrandAnalytics/AdaptiveExpenditureEngine.swift:82-100` |

## 3. Corrections to the planning documents

| # | Document says | The code says | Consequence for this stage |
|---|---|---|---|
| C1 | "One fact currently has three homes" (ROADMAP stage 1, "What exists"; CONTEXT §5) | Body weight has **six** stores: `profile.weightKg` in UserDefaults (`Profile.swift:23`); the `appleDaily.weightKg` column (`Database.swift:194`, written at `HealthKitBridge.swift:696`, `Strand/Data/AppleHealthImport.swift:48`, `Strand/Data/ShortcutHealthImport.swift:221`); `metricSeries` key `weight` under `apple-health` (`Packages/StrandImport/Sources/StrandImport/AppleHealthAggregator.swift:289`, `ShortcutHealthImport.swift:247`); `metricSeries` key `weight` under `nutrition-csv`, stored in the export's own unit with no unit recorded (`Packages/StrandImport/Sources/StrandImport/NutritionCsvImport.swift:23-24`, `:105`; written at `Strand/Screens/DataSourcesView.swift:450`); `labMarker` rows with key `weight`; and their daily projection in `metricSeries` under `lab-book` (`LabMarkerStore.swift:96`, `:217-241`). Waist has three: `profile.waistCm`, `labMarker` `waist`, and its `lab-book` projection | The resolver's candidate list in §8 names each one and says which are excluded and why |
| C2 | "Today resolves weight from Apple Health first and the profile second" | True, but the three Today implementations do not agree with each other. Liquid resolves for the **selected** day over a 91-day window (`LiquidTodayView.swift:3130`, `:3251-3252`). Classic resolves the **latest** day over a 90-day window, regardless of the selected day (`TodayView.swift:3934`, `:4694`, `:5213`). The redesign reuses the Liquid day model (`RedesignTodayView.swift:609`). The estimates never consult Apple Health at all: they read the profile value only (`Strand/Data/IntelligenceEngine.swift:897`, `Strand/App/AppModel.swift:1044`) | Today and the estimates can already show and use different weights. §8 fixes this when the flag is on and reproduces it exactly when the flag is off |
| C3 | Lab Book "editor with a unit switcher" covers the weigh-in need; test plan line "Unit handling: kilograms and pounds in, kilograms stored" sits under pure logic | The switcher exists only for mg/dL markers (`MarkerEditorView.swift:483-499`). A weight typed in pounds in the Lab Book editor is stored as that number with unit `kg` (`:419-422`). CSV import stores the file's unit verbatim with no conversion (`Packages/StrandImport/Sources/StrandImport/LabMarkerCsvImport.swift:19`, `:37-41`, `:195-203`), so a `labMarker` weight row can carry unit `lb` | Unit conversion is an app-layer concern of the new sheet and of the resolver, tested in `StrandTests` (§12.3), using the app's existing constants (`Strand/Data/Units.swift:178`, `:180`). The pure function takes kilograms and centimetres only |
| C4 | Scope asks for "edit and delete" on Lab Book storage | The store has upsert and delete but no edit of the instant. Upsert conflicts on `(deviceId, markerKey, takenAt, source)` only (`LabMarkerStore.swift:127`); re-inserting an existing `id` with a different `takenAt` violates the primary key. The Lab Book screen itself only adds and deletes (`Strand/Screens/LabBookView.swift:475-486`) | Editing a date is "insert the new row, then delete the old one" (§9.1). No new store API |
| C5 | "Weekly points: one per ISO week" | The codebase already has a Monday-week rule over day-key strings, with a Kotlin twin: `WeeklyDigestEngine.mondayOfWeek(containing:)` and `addDays` (`Packages/StrandAnalytics/Sources/StrandAnalytics/WeeklyDigest.swift:421`, `:430`; `android/app/src/main/java/com/noop/analytics/WeeklyDigest.kt:440`, `:449`). It is free of `Calendar` and time zones. A second, different week rule exists in the Training hub: the locale's first weekday (`StrandiOS/App/TrainingHubView.swift:163-166`) | The stage reuses `mondayOfWeek`. A week is identified by its Monday's day key, not by an ISO week number. The Training hub's week is not used |
| C6 | Q2 offers "a new tab" as a placement | The tab bar already holds four tabs plus a conditional Coach tab (`StrandiOS/App/RootTabView.swift:174-181`, `:592-601`). A sixth tab would push one into the system "More" overflow whenever Coach is on | §10.9 recommends the Today card plus a Health row, and the design gate should show the tab option honestly as "replaces or overflows" |
| C7 | WP 1-9 owns "Notification settings files" | There is no shared notification-settings file for local reminders. Each reminder is its own type in `Strand/System/` with its own keys (`WindDownNudge.swift:15-27`, `CoachBriefScheduler.swift:32-44`). `Strand/Data/NotificationSettingsStore.swift` is the macOS strap-buzz forwarder and is excluded from the iPhone target (`project.yml:235-236`) | WP 1-9 owns one new file, `Strand/System/WeighInReminder.swift` |
| C8 | The work-package table gives the Test author only the `CutScorecard` suite | The roadmap's own test plan also needs store tests, app-target tests and a source-scanning test. Nobody owns them | §14 assigns them to WP 1-3 as separate files |
| C9 | The frame list has no frame for entering the phase and the rules | Phase configuration is in scope and needs a screen | §10.5 adds the phase and rules sheet to the frame list |
| C10 | "Any setting that should survive a backup restore must be added to the whitelist on both platforms" assumes the two whitelists agree today | They do not. Android carries `units.skinTempDisplay` (`BackupSettings.kt:61`); the Swift whitelist has no such key (`BackupSettings.swift:49-70`) | Pre-existing drift, not caused by this stage and not repaired by it (one concern per pull request). The stage's whitelist test compares only the keys it adds. Reported to the owner in §16 |

## 4. Every reader and writer

### 4.1 Body weight

"Action" is what stage 1 does to the site. "Resolver" means the site reads through §8.

| Site | What it does | Action |
|---|---|---|
| `Strand/Data/Profile.swift:23`, `:125` | Stores and loads `profile.weightKg`, default 75 | Kept. Becomes a mirror of the resolved value when the flag is on (§8.5) |
| `Strand/Screens/SettingsView.swift:524-533`, `:888-892` | Edits the profile value (kg or lb) | Writer. When the flag is on and a dated reading resolves, the row shows the resolved value with its source and date and offers "Log weigh-in" in place of the stepper (§10.7) |
| `Strand/Onboarding/OnboardingWizard.swift:807-809` | Edits the profile value at first run | Writer, unchanged. No dated reading exists at that point |
| `Strand/Data/IntelligenceEngine.swift:897` | Builds `UserProfile` for calorie estimates in the scoring pass | Resolver (`.estimate`) |
| `Strand/App/AppModel.swift:1044` | Builds `UserProfile` for a manual session's calories | Resolver (`.estimate`) |
| `Strand/Data/IntelligenceEngine.swift:637-638`, `:2615-2616` | Passes weight to `fitnessAgeRows`, where it only gates readiness (`:586`) | Resolver (`.estimate`) |
| `Strand/Screens/HealthView.swift:768` | Readiness checklist: "has height and weight" | Resolver (`.estimate`) |
| `Strand/Screens/TestCentreView.swift:116` | Prefills an experimental ring user-info field | Resolver (`.estimate`) |
| `Strand/Liquid/LiquidTodayView.swift:3130`, `:3246-3252`, `:1613-1618` | Loads and renders the Today weight tile | Resolver (`.display`) |
| `Strand/Screens/TodayView.swift:4136-4139`, `:4694`, `:5212-5217` | Classic Today weight tile | Resolver (`.display`) |
| `StrandiOS/Redesign/RedesignTodayView.swift:608-614` | Redesign Today weight row; routes to `.metric("weight")`, the Apple Health chart | Resolver (`.display`). With the flag on the row routes to the scorecard |
| `Strand/Screens/LabBookView.swift:475-486`, `Strand/Screens/MarkerEditorView.swift:425-441` | Add and delete `labMarker` rows, including `weight` | Writer, unchanged. The resolver's provider refreshes after `repo.refresh()`, which both paths already call (`LabBookView.swift:478`, `:485`) |
| `Strand/Screens/LabBookView.swift:255-281` | CSV import of Lab Book rows | Writer, unchanged |
| `Strand/AI/AICoach.swift:1268-1285` | Prints the latest Lab Book reading per marker under a "LAB BOOK" heading | Allowed as it is: the line is labelled with its source. Stage 2 replaces it with the resolver's value |
| `Strand/Screens/AppleHealthView.swift:107`, `:530`, `:633` | The Apple Health page's own weight tile and chart | Allowed: a source page that states its source |
| `Strand/Screens/CompareView.swift:137`, `Strand/Screens/LabBookView.swift:962` | Offer `weight` as a series to compare | Allowed: they chart a named source series, they do not state a current weight |
| `Strand/Data/ShortcutHealthImport.swift:187`, `:221`, `:247`; `Strand/Data/AppleHealthImport.swift:48`; `StrandiOS/Health/HealthKitBridge.swift:640-642`, `:696`, `:726` | Write Apple Health weight | Writers, unchanged. The HealthKit path is inactive in this build (row 10 of §2) |
| `Strand/Screens/DataSourcesView.swift:450` | Writes `weight` under `nutrition-csv` | Writer, unchanged. Excluded from the resolver: the unit is not recorded |
| `Strand/Data/AppleDemoSeeder.swift:144`, `:166` | Demo data. Writes `appleDaily.weightKg` and a series under the key `weightKg`, which no reader uses | Unchanged. Noted for the fixture work: demo weight reaches Today through `appleDaily`, not through the series |
| `Packages/NoopLocalAccess/Sources/NoopLocalAccessCore/LocalAccessCore.swift:154`, `:262`, `:544` | Local export of source-labelled series | Allowed, unchanged |
| `Packages/WhoopStore/Sources/WhoopStore/BackupSettings.swift:52`, `:78` | Backs up `profile.weightKg` | Unchanged |
| Widgets (`StrandiOSWidgets/`, `StrandiOSShared/`) | No weight or waist reader found | None |

Not found: any hydration-goal use of body weight. `HydrationView` and its goal do not read the profile.

Not body weight, despite the name: every `weightKg` under `LiftSession*`, `LiftLog*`, `LiftMetrics`,
`LiftingImporter`, `HevyAPI` is a set's load. `Packages/OuraProtocol/.../UserInfo.swift:165` is a
ring's own stored value.

### 4.2 Waist

| Site | What it does | Action |
|---|---|---|
| `Strand/Data/Profile.swift:27`, `:127` | Stores `profile.waistCm`; 0 means not set | Kept; mirror when the flag is on |
| `Strand/Screens/SettingsView.swift:549-557`, `:935-990` | Edits the profile value | Writer; same change as weight |
| `Strand/Data/IntelligenceEngine.swift:637`, `:643`, `:2615`, `:2621` | Chooses the VO₂max estimator and feeds the waist-based estimate (`:582-593`, `:611-618`) | Resolver (`.estimate`) |
| `Strand/Screens/HealthView.swift:769`, `:807` | Readiness checklist and the "add a waist" prompt | Resolver (`.estimate`) |
| `Packages/WhoopStore/Sources/WhoopStore/ScoreInputProvenanceStore.swift:32` | Pure helper from a waist value | Unchanged; it is passed the resolved value |
| `Strand/Screens/LabBookView.swift`, `MarkerEditorView.swift` | Add and delete `waist` rows | Writers, unchanged |
| `Packages/WhoopStore/Sources/WhoopStore/BackupSettings.swift:54`, `:80` | Backs up `profile.waistCm` | Unchanged |

No Apple Health waist read exists anywhere in the tree.

### 4.3 Height

`profile.heightCm` (`Profile.swift:24`) is read at `IntelligenceEngine.swift:897`, `AppModel.swift:1044`,
`HealthView.swift:768`, `TestCentreView.swift:115`, `SettingsView.swift:535-543` and
`OnboardingWizard.swift:814-816`. Stage 1 does not touch height. It is listed so the bypass test in
§12.4 does not flag it.

### 4.4 Android twins of the shared pieces

| Piece | Where | Stage 1 |
|---|---|---|
| Marker catalogue | `android/app/src/main/java/com/noop/analytics/MarkerCatalog.kt:102-105` | Unchanged; no new key |
| Profile values | `android/app/src/main/java/com/noop/ui/SettingsScreen.kt:184` (`ProfileStore`) | Unchanged |
| Newest-weight resolver for Health Connect, which writes the newest reading into the profile | `android/app/src/main/java/com/noop/analytics/ProfileWeightSync.kt:18-36`, `android/app/src/main/java/com/noop/ui/HealthConnectWeightSync.kt:25-31` | Unchanged. It is the precedent for §8.5: an external reading written through to `profile.weightKg`, which then travels in the backup |
| Today weight tile | `android/app/src/main/java/com/noop/ui/TodayMetricsLogic.kt:107` | Unchanged |
| Backup whitelist | `android/app/src/main/java/com/noop/data/BackupSettings.kt:50-76` | Two keys added (§9.3) |
| Week and day helpers | `WeeklyDigest.kt:440`, `LocalDayWindows.kt:210`, `:308` | Reused by the Kotlin twin |

## 5. Final names

| Thing | Name | Where |
|---|---|---|
| Pure function | `CutScorecard.evaluate(_:)` (confirmed) | `Packages/StrandAnalytics/Sources/StrandAnalytics/CutScorecard.swift` |
| Its types | `CutScorecardInput`, `CutScorecardReading`, `CutScorecardLiftObservation`, `CutScorecardProteinDay`, `CutScorecardPhase`, `CutScorecardParameters`, `CutScorecardResult` and the output types in §6 | Same file. Top-level and prefixed, as `AdaptiveExpenditureDay` and `AdaptiveExpenditureEstimate` are |
| Kotlin twin | `com.noop.analytics.CutScorecard` | `android/app/src/main/java/com/noop/analytics/CutScorecard.kt` |
| Resolver | `BodyMeasurementResolver` (pure), `BodyMeasurementProvider` (repository-backed) | `Strand/Data/BodyMeasurementResolver.swift`, `Strand/Data/BodyMeasurementProvider.swift` |
| Write funnel | `WeighInStore` | `Strand/Data/WeighInStore.swift` |
| Settings | `CutScorecardSettings` | `Strand/Data/CutScorecardSettings.swift` |
| Input adapter | `CutScorecardInputBuilder` | `Strand/Data/CutScorecardInputBuilder.swift` |
| View model and presenter | `CutScorecardModel`, `CutScorecardPresenter` | `Strand/Data/CutScorecardModel.swift`, `Strand/Data/CutScorecardPresenter.swift` |
| Reminder | `WeighInReminder` | `Strand/System/WeighInReminder.swift` |
| Feature flag | `noop.cutScorecardEnabled`, Bool, default `false` | `CutScorecardSettings.enabledKey` |
| Phases | `cutScorecard.phases`, String (JSON array) | §9.2 |
| Rule parameters | `cutScorecard.rules`, String (JSON object) | §9.2 |
| Reminder | `cutScorecard.reminder.enabled` (Bool, default `false`), `cutScorecard.reminder.weekday` (Int, 1 = Sunday … 7 = Saturday), `cutScorecard.reminder.minuteOfDay` (Int) | §9.2 |
| Dashboard card | `DashboardCard.scorecard`, raw value `scorecard` | `Strand/Screens/DashboardCards.swift` |
| Navigation | `RedesignRoute.scorecard`, `RedesignRoute.weighInHistory` | `StrandiOS/Redesign/RedesignRoute.swift` |
| Stored reading | `labMarker` row, `markerKey` `weight` or `waist`, `category` `bodyMeasurement`, `source` `manual` | §9.1 |

The view model, presenter, resolver, write funnel, settings and reminder live under `Strand/` so that
`StrandTests`, which runs only on the macOS `Strand` scheme, can test them. The SwiftUI views live
under `StrandiOS/` and are verified by compiling and in the simulator.

## 6. Pure logic: the API

File `Packages/StrandAnalytics/Sources/StrandAnalytics/CutScorecard.swift`. No store, no clock, no
`Calendar`, no `TimeZone`, no `Date`. Follows the conventions of its neighbours: a caseless
`public enum` namespace with static functions, `Equatable, Sendable` value types with explicit public
initialisers, day keys as `"yyyy-MM-dd"` strings, and a doc line naming the Kotlin twin
(`AdaptiveExpenditureEngine.swift:6-14`, `:60-61`; `LiftMetrics.swift:29-43`).

### 6.1 How "today", the calendar and the time zone are passed in

- **Today** is `CutScorecardInput.today`, a day key. The function never reads a clock. The app passes
  `Repository.localDayKey(Date())` (`Strand/Data/Repository.swift:734`), the same calendar-day key
  `TrendsView` already pairs with `mondayOfWeek` (`Strand/Screens/TrendsView.swift:386-387`). It is
  the calendar day, not the 04:00 logical day (`Repository.swift:745`).
- **The calendar** is fixed: proleptic Gregorian, weeks start on Monday, computed by
  `WeeklyDigestEngine.mondayOfWeek(containing:)`. It is not a parameter.
- **The time zone** never reaches the function. Each reading arrives with the local day it was taken
  on, decided once when it was saved (§9.1). A reading's `day` is stored and is not recomputed when
  the device changes zone, so travel cannot move a past reading into another week.

### 6.2 Units

Kilograms for weight and lift loads, centimetres for waist, grams for protein, kilocalories for the
calorie amounts, percent of bodyweight per week for the band. Conversion from pounds and inches
happens in the app layer before the function is called.

### 6.3 Inputs

```swift
/// One dated weight (kg) or waist (cm) reading.
public struct CutScorecardReading: Equatable, Sendable {
    public let day: String      // local day the reading was taken, "yyyy-MM-dd"
    public let takenAt: Int     // epoch seconds; used only to order readings that share a day
    public let value: Double    // kg for weight, cm for waist
    public init(day: String, takenAt: Int, value: Double)
}

/// One performed working set, reduced to what the lift signal needs.
public struct CutScorecardLiftObservation: Equatable, Sendable {
    public let day: String      // local day the session started
    public let exercise: String // compared byte for byte: no trimming, no case folding
    public let weightKg: Double
    public init(day: String, exercise: String, weightKg: Double)
}

/// One day's protein total.
public struct CutScorecardProteinDay: Equatable, Sendable {
    public let day: String
    public let grams: Double
    public init(day: String, grams: Double)
}

/// The active cut phase. The app passes nil when no cut phase is active.
public struct CutScorecardPhase: Equatable, Sendable {
    public let name: String
    public let startDay: String
    public let targetWeightKg: Double?          // nil: no target, so no projection
    public let rateLowPercentPerWeek: Double    // expected band, inclusive
    public let rateHighPercentPerWeek: Double
    public init(name: String, startDay: String, targetWeightKg: Double?,
                rateLowPercentPerWeek: Double, rateHighPercentPerWeek: Double)
}

/// Every threshold, window and amount the rules use. Nothing in `evaluate` is a literal.
public struct CutScorecardParameters: Equatable, Sendable {
    public var rateWindowWeeks: Int                 // generic default 4
    public var waistWindowWeeks: Int                // 4
    public var waistMinDecreaseCm: Double           // 0.1
    public var liftDropTolerancePercent: Double     // 2.5
    public var liftDropShare: Double                // 0.5
    public var liftDropConsecutiveWeeks: Int        // 3
    public var addCaloriesKcal: Int                 // 100
    public var slowLossThresholdKgPerWeek: Double   // 0.25
    public var slowLossConsecutiveWeeks: Int        // 3
    public var reduceCarbsKcal: Int                 // 100
    public var proteinFloorGrams: Double?           // nil: no floor configured
    public var proteinMinDaysPerWeek: Int           // 5
    public var maxWeighInAgeWeeks: Int              // 1
    public var maxProjectionWeeks: Int              // 104
    public var targetToleranceKg: Double            // 0
    public init(/* every field, each defaulted to the value above */)
    /// The defaults above. Generic; the owner's values replace them in settings.
    public static let generic: CutScorecardParameters
}

public struct CutScorecardInput: Equatable, Sendable {
    public let weights: [CutScorecardReading]
    public let waists: [CutScorecardReading]
    public let lifts: [CutScorecardLiftObservation]
    public let proteinDays: [CutScorecardProteinDay]
    public let phase: CutScorecardPhase?
    public let parameters: CutScorecardParameters
    public let today: String
    public init(weights: [CutScorecardReading], waists: [CutScorecardReading],
                lifts: [CutScorecardLiftObservation] = [],
                proteinDays: [CutScorecardProteinDay] = [],
                phase: CutScorecardPhase?, parameters: CutScorecardParameters, today: String)
}
```

The generic default for a new phase's band, used only to prefill the setup sheet, is 0.25 to 0.75
percent per week. Input arrays need not be sorted. The result does not depend on their order, with
one stated exception (duplicate protein days, §7.1).

### 6.4 Outputs

```swift
public enum CutScorecardSignalState: String, Equatable, Sendable { case met, notMet, unknown }

public struct CutScorecardWeek: Equatable, Sendable {
    public let weekStart: String        // the Monday
    public let weightKg: Double?        // nil: no weigh-in that week ("not measured")
    public let weightDay: String?
    public let waistCm: Double?
    public let waistDay: String?
    public let inPhase: Bool
    public let weeklyLossKg: Double?    // previous week's weight minus this week's; nil if either is missing
}

public struct CutScorecardRate: Equatable, Sendable {
    public let lossKgPerWeek: Double    // positive when losing
    public let percentPerWeek: Double   // of `referenceWeightKg`
    public let referenceWeightKg: Double
    public let pointsUsed: Int
    public let spanWeeks: Int
    public let firstWeekStart: String
    public let lastWeekStart: String
}

public enum CutScorecardRateUnavailable: String, Equatable, Sendable {
    case noReadings, singleReading, gapLongerThanWindow, weighInOverdue
}

public enum CutScorecardProjectionStatus: String, Equatable, Sendable {
    case projected, noActivePhase, noTarget, targetReached, rateUnknown, notLosing,
         beyondHorizon, needsNewWeighIn, weighInOverdue
}

public struct CutScorecardProjection: Equatable, Sendable {
    public let status: CutScorecardProjectionStatus
    public let targetDay: String?       // set only when status == .projected
    public let weeksRemaining: Double?  // set only when status == .projected
    public let remainingKg: Double?     // set whenever a phase target and a current weight exist
}

public enum CutScorecardWaistReason: String, Equatable, Sendable {
    case shrinking, notShrinking, noWaistThisWeek, noEarlierWaist, weighInOverdue, noReadings
}
public struct CutScorecardWaistSignal: Equatable, Sendable {
    public let state: CutScorecardSignalState
    public let reason: CutScorecardWaistReason
    public let currentCm: Double?
    public let referenceCm: Double?
    public let referenceWeekStart: String?
    public let changeCm: Double?        // current minus reference; negative when shrinking
}

public enum CutScorecardLiftReason: String, Equatable, Sendable {
    case holding, dropping, noLiftData, noSessionsThisWeek, noSessionsPriorWeek,
         noCommonExercises, weighInOverdue, noReadings
}
public struct CutScorecardLiftSignal: Equatable, Sendable {
    public let state: CutScorecardSignalState
    public let reason: CutScorecardLiftReason
    public let commonExercises: Int
    public let dropped: Int
    public let climbed: Int
    public let held: Int
    public let windowStartDay: String?  // first day of the seven compared
    public let windowEndDay: String?    // last day of the seven compared
}

public enum CutScorecardProteinReason: String, Equatable, Sendable {
    case floorMet, floorMissed, noFloorConfigured, noProteinData, incompleteLogging,
         weighInOverdue, noReadings
}
public struct CutScorecardProteinSignal: Equatable, Sendable {
    public let state: CutScorecardSignalState
    public let reason: CutScorecardProteinReason
    public let daysLogged: Int
    public let daysAtOrAboveFloor: Int
    public let requiredDays: Int
    public let floorGrams: Double?
}

public enum CutScorecardRateBandReason: String, Equatable, Sendable {
    case withinBand, belowBand, aboveBand, noActivePhase, rateUnknown, weighInOverdue, noReadings
}
public struct CutScorecardRateBandSignal: Equatable, Sendable {
    public let state: CutScorecardSignalState
    public let reason: CutScorecardRateBandReason
    public let percentPerWeek: Double?
    public let lowPercentPerWeek: Double?
    public let highPercentPerWeek: Double?
}

public struct CutScorecardSignals: Equatable, Sendable {
    public let waist: CutScorecardWaistSignal
    public let lifts: CutScorecardLiftSignal
    public let protein: CutScorecardProteinSignal
    public let rateBand: CutScorecardRateBandSignal
}

/// The three feedback rules, in precedence order.
public enum CutScorecardRule: String, CaseIterable, Equatable, Sendable {
    case liftsHoldingWaistShrinking     // rule 1: change nothing
    case liftsDropping                  // rule 2: add calories
    case slowLoss                       // rule 3: reduce carbohydrate
}
public enum CutScorecardRuleState: String, Equatable, Sendable { case fired, notFired, unknown }
public enum CutScorecardRuleUnknownReason: String, Equatable, Sendable {
    case liftSignalUnknown, waistSignalUnknown, fewerWeeksThanWindow, missedWeighIn,
         noActivePhase, weighInOverdue, noReadings
}
public struct CutScorecardRuleEvaluation: Equatable, Sendable {
    public let rule: CutScorecardRule
    public let state: CutScorecardRuleState
    public let unknownReason: CutScorecardRuleUnknownReason?  // set only when state == .unknown
    public let consecutiveWeeks: Int   // weeks, counting back from the judged week, that satisfy the rule's weekly condition
    public let requiredWeeks: Int      // 1 for rule 1; the parameter for rules 2 and 3
}

public enum CutScorecardVerdictKind: String, Equatable, Sendable {
    case holdSteady, addCalories, reduceCarbs, insufficientData
}
public enum CutScorecardVerdictReason: String, Equatable, Sendable {
    case ruleFired, noChangeRuleFired, recompositionCheckIncomplete, noRuleEvaluable,
         noReadings, noActivePhase, phaseNotStarted, weighInOverdue, invalidInput
}
public struct CutScorecardVerdict: Equatable, Sendable {
    public let kind: CutScorecardVerdictKind
    public let reason: CutScorecardVerdictReason
    public let rule: CutScorecardRule?              // the rule that fired; nil otherwise
    public let calorieChangeKcal: Int?              // +addCaloriesKcal or -reduceCarbsKcal; nil otherwise
    public let overriddenRules: [CutScorecardRule]  // rules that fired but lost on precedence
    public let unevaluatedRules: [CutScorecardRule] // rules that could have changed this verdict and could not be evaluated
}

public enum CutScorecardInvalidInput: String, Equatable, Sendable { case parameters, phase, today }

public struct CutScorecardRejections: Equatable, Sendable {
    public let nonFinite: Int
    public let nonPositive: Int
    public let invalidDay: Int
    public let future: Int
}

public struct CutScorecardResult: Equatable, Sendable {
    public let weeks: [CutScorecardWeek]            // contiguous, ascending; empty when there is no valid reading
    public let judgedWeekStart: String?
    public let currentWeightKg: Double?             // the newest valid weight on or before today
    public let currentWeightDay: String?
    public let rate: CutScorecardRate?
    public let rateUnavailable: CutScorecardRateUnavailable?  // set exactly when rate is nil
    public let projection: CutScorecardProjection
    public let signals: CutScorecardSignals
    public let rules: [CutScorecardRuleEvaluation]  // always three, in precedence order
    public let verdict: CutScorecardVerdict
    public let evidenceStartDay: String?            // nothing dated before this day can change anything but `weeks`
    public let rejections: CutScorecardRejections
    public let invalidInput: CutScorecardInvalidInput?
}

/// Kotlin twin: `CutScorecard`.
public enum CutScorecard {
    public static func evaluate(_ input: CutScorecardInput) -> CutScorecardResult
    /// The Monday of the week containing `day`. Forwards to `WeeklyDigestEngine.mondayOfWeek`.
    public static func weekStart(containing day: String) -> String?
    /// Round to three decimals, halves away from zero. Every comparison in `evaluate` uses it.
    public static func quantize(_ x: Double) -> Double
}
```

Every type has a memberwise public initialiser in declaration order, so a test can build an expected
value.

### 6.5 Rejection behaviour

`evaluate` never throws and never traps. It is total over every input.

- A reading, lift observation or protein day is **dropped and counted** in `rejections` when its
  value is NaN or infinite (`nonFinite`), when its value is zero or negative (`nonPositive`; a protein
  total of exactly zero is valid, a negative one is not), when its `day` is not a real calendar date
  (`invalidDay`), or when its `day` is after `today` (`future`). A lift observation with an empty
  exercise name counts under `invalidDay`. The result is exactly what it would have been had the
  dropped items never been passed.
- **Invalid parameters** return the invalid result with `invalidInput == .parameters`: any non-finite
  Double; any window or consecutive-weeks count below 1; `maxWeighInAgeWeeks` below 0;
  `maxProjectionWeeks` below 1; `liftDropTolerancePercent` outside `0 ..< 100`; `liftDropShare`
  outside `0 < share <= 1`; a negative `waistMinDecreaseCm`, `slowLossThresholdKgPerWeek`,
  `targetToleranceKg`, `addCaloriesKcal` or `reduceCarbsKcal`; `proteinMinDaysPerWeek` outside 1…7;
  a `proteinFloorGrams` that is set and not positive.
- **An invalid phase** returns it with `.phase`: an unparseable `startDay`; a target that is set and
  not positive and finite; a non-finite or negative band bound; low above high.
- **An unparseable `today`** returns it with `.today`.

The invalid result has empty `weeks`, nil rate with `rateUnavailable == .noReadings`, projection
status `.noActivePhase`, every signal and rule `unknown` with reason `.noReadings`, zero rejections,
and verdict `insufficientData` with reason `.invalidInput`.

Plausibility ranges (a 600 kg weight) are not this function's job. The entry sheet enforces them
(§10.3).

## 7. Algorithm

### 7.1 Preparation

1. Validate as in §6.5. Drop and count invalid items.
2. **Quantize.** `quantize(x) = sign(x) × floor(|x| × 1000 + 0.5) ÷ 1000`. Written out because Swift's
   `rounded()` and the Kotlin rounding functions disagree on halves; the twin implements this
   expression, not a library call. Every threshold comparison below compares quantized values.
3. **Weeks.** `weekStart(day)` is the Monday of the day's week. `weeksBetween(a, b)` is the whole
   number of weeks from `weekStart(a)` to `weekStart(b)`.
4. **Weekly points.** Group the valid weights by `weekStart`. The week's representative is the reading
   that sorts last by `(day, takenAt, value)`: **the latest reading of the week**. Do the same,
   independently, for waist.

   Why the latest and not the mean, the minimum or the first: it is always a reading that exists, so
   the history list can show which one represents the week and the owner can correct it; it matches
   the store's own rule for several readings in one day, which keeps the latest
   (`LabMarkerStore.swift:105-108`, `:219-226`); a correction entered later supersedes the mistake
   without a delete; and the current week's point then equals the resolver's "current weight" by
   construction, so the two cannot disagree. A mean would be a number that appears nowhere else in
   the app.
5. **`weeks`.** One entry per Monday week from the earliest week holding any valid weight or waist
   reading to the week containing `today`, with no gaps. A week with no weigh-in has `weightKg == nil`.
   It is never filled, carried forward or interpolated.
6. **`currentWeightKg`.** The newest valid weight on or before `today`, by `(day, takenAt, value)`,
   regardless of phase and age.
7. **Duplicate protein days.** When two protein entries share a day, the one later in the input array
   wins. The app's adapter passes one per day.

### 7.2 Phase, domain and the judged week

- `phase == nil`: **no active phase**. Weekly points, rate (unclipped), and the waist, lift and
  protein signals are still computed. The rate-band signal is `unknown(.noActivePhase)`, the
  projection is `.noActivePhase`, all three rules are `unknown(.noActivePhase)` and the verdict is
  `insufficientData(.noActivePhase)`.
- `today < phase.startDay`: identical, except the verdict reason is `.phaseNotStarted`.
- Otherwise the **domain** is every week from `weekStart(phase.startDay)` on. `inPhase` marks them.
  Readings from before the domain appear in `weeks` and nowhere else. The first in-phase weigh-in is
  the baseline: a rule never reaches back across the start of the phase.
- The **judged week** `J` is the latest domain week that has a weight point. If the domain has none,
  the verdict is `insufficientData(.noReadings)` and everything else is `unknown(.noReadings)`.
- **Overdue.** If `weeksBetween(J, today) > maxWeighInAgeWeeks`, nothing current is asserted: rate is
  nil with `.weighInOverdue`, every signal and rule is `unknown(.weighInOverdue)`, the projection is
  `.weighInOverdue` and the verdict is `insufficientData(.weighInOverdue)`. With the default of 1, a
  verdict stays visible through the week after a weigh-in and lapses in the week after that.
- The **anchor day** `a` of a week is the day of its representative weight reading.

### 7.3 Weekly loss

For a domain week `w` with a weight point whose immediately preceding week `w − 1` is also in the
domain and also has a point: `weeklyLossKg(w) = quantize(weight(w − 1) − weight(w))`. Otherwise nil.
**A missed week is not bridged.** The loss across a gap is not attributed to either week, because the
owner's rule speaks of consecutive weeks and an average over a gap is not a week.

### 7.4 Rate of loss

The window is the weeks `J − rateWindowWeeks … J`, clipped to the domain: at most
`rateWindowWeeks + 1` weekly points.

- Fewer than two points in the window: rate is nil. The reason is `.singleReading` when the domain
  holds one weight point in total, and `.gapLongerThanWindow` when older points exist but all lie
  before the window.
- Otherwise fit a least-squares line through the points, with `x` the number of weeks since the
  window's first point and `y` the weight. Take the points in ascending week order and accumulate
  left to right, in `Double`:

  `x̄ = Σx ÷ n`, `ȳ = Σy ÷ n`, `slope = Σ(x − x̄)(y − ȳ) ÷ Σ(x − x̄)²`

  `lossKgPerWeek = quantize(−slope)`

  `referenceWeightKg = ȳ` (not quantized)

  `percentPerWeek = quantize(100 × lossKgPerWeek ÷ ȳ)`

Why a fitted line: the weekly numbers are noisy, and a line through every point in the window moves
less with one odd reading than the difference between the two end points does. With exactly two
points it is the end-point difference. A missed week inside the window simply contributes no point;
the line is fitted to the true week spacing of the others.

Why `ȳ` for the percentage: it is the bodyweight at the centre of the same fit, so the percentage and
the slope describe the same line. The difference from using the latest weight is below the third
decimal for any plausible rate.

### 7.5 The four signals

All four describe the judged week.

**Evidence window.** Lifts and protein are judged over **the seven local days before the anchor
day**, `a − 7 … a − 1`, not over the Monday week. A weigh-in taken on waking reflects the days before
it. Judging the calendar week instead would leave both signals `unknown` on every weigh-in morning,
because the week would still be in progress. The Monday week only decides which reading represents
which week and which weeks are consecutive.

1. **Waist shrinking.**
   - `unknown(.noWaistThisWeek)` if week `J` has no waist point.
   - The reference is the **earliest** waist point in the weeks `J − waistWindowWeeks … J − 1`, clipped
     to the domain. `unknown(.noEarlierWaist)` if there is none.
   - `changeCm = quantize(waist(J) − waist(reference))`.
   - `met(.shrinking)` if `changeCm <= −quantize(waistMinDecreaseCm)`, else `notMet(.notShrinking)`.
     A flat waist is `notMet`.
2. **Working weights holding or climbing.** For a week with anchor `a`:
   - `unknown(.noLiftData)` if the input holds no valid lift observation at all.
   - `current` is the greatest `weightKg` per exercise over the days `a − 7 … a − 1`; `previous` the
     same over `a − 14 … a − 8`. `unknown(.noSessionsThisWeek)` if `current` is empty, then
     `unknown(.noSessionsPriorWeek)` if `previous` is empty, then `unknown(.noCommonExercises)` if no
     exercise name appears in both.
   - For each common exercise: **dropped** if
     `quantize(current) < quantize(previous × (1 − liftDropTolerancePercent ÷ 100))`; **climbed** if
     `quantize(current) > quantize(previous)`; otherwise **held**.
   - The week is **dropping** if `dropped >= 1` and `dropped ÷ common >= liftDropShare`; otherwise
     **holding**.
   - The signal is `met(.holding)` or `notMet(.dropping)`.

   This is a statement about the heaviest working set per exercise and nothing else. It does not see
   repetitions, and it cannot tell a planned lighter week from an unplanned one. The screen says so
   (§11).
3. **Protein floor.**
   - `unknown(.noFloorConfigured)` if `proteinFloorGrams` is nil.
   - Over the days `a − 7 … a − 1`: `daysLogged` is the number of days with an entry;
     `daysAtOrAboveFloor` those with `quantize(grams) >= quantize(floor)`.
   - `unknown(.noProteinData)` if `daysLogged == 0`.
   - `met(.floorMet)` if `daysAtOrAboveFloor >= proteinMinDaysPerWeek`.
   - `notMet(.floorMissed)` if `daysAtOrAboveFloor + (7 − daysLogged) < proteinMinDaysPerWeek`: even
     if every unlogged day had reached the floor, the week could not.
   - Otherwise `unknown(.incompleteLogging)`. An unlogged day is not a day below the floor.
4. **Rate within the expected band.** `unknown(.rateUnknown)` if the rate is nil. Otherwise
   `met(.withinBand)` if `rateLow <= percentPerWeek <= rateHigh`, else `notMet(.belowBand)` or
   `notMet(.aboveBand)`. A rising weight is `belowBand`.

The protein and rate-band signals are shown and never feed the verdict. The owner's three rules do
not mention them.

### 7.6 Rule states

Each rule is `fired`, `notFired` or `unknown`. `N₂ = liftDropConsecutiveWeeks`,
`N₃ = slowLossConsecutiveWeeks`. "Lift status of week `w`" is the status from §7.5 item 2 computed
with that week's anchor, or unknown when the week has no weight point.

- **Rule 1, `liftsHoldingWaistShrinking`.** `fired` if the judged week's lift status is holding and
  the waist signal is `met`. `notFired` if the lift status is dropping or the waist signal is
  `notMet`. Otherwise `unknown`, with reason `.liftSignalUnknown` when the lift status is unknown and
  `.waistSignalUnknown` otherwise.
- **Rule 2, `liftsDropping`.** Over the weeks `J − N₂ + 1 … J`:
  `notFired` if any of those weeks that lies in the domain is holding; else `fired` if all `N₂` weeks
  lie in the domain and all are dropping; else `unknown`, with reason `.fewerWeeksThanWindow` if the
  window starts before the domain, else `.missedWeighIn` if a week in it has no weight point, else
  `.liftSignalUnknown`.
- **Rule 3, `slowLoss`.** Over the weeks `J − N₃ + 1 … J`:
  `notFired` if any of those weeks has a `weeklyLossKg` with
  `weeklyLossKg >= quantize(slowLossThresholdKgPerWeek)`; else `fired` if all `N₃` have a
  `weeklyLossKg`; else `unknown`, with reason `.fewerWeeksThanWindow` if `J − N₃` lies before the
  domain, else `.missedWeighIn`.

  Rule 3 therefore needs `N₃ + 1` weigh-ins in consecutive weeks. A weight that rises counts as a
  slow week: its loss is negative.

`consecutiveWeeks` counts back from `J` while the rule's weekly condition is known to hold (dropping
for rule 2; a known loss under the threshold for rule 3; 1 or 0 for rule 1) and stops at the first
week where it is false or unknown.

### 7.7 Verdict and precedence

Precedence is rule 1, then rule 2, then rule 3. The first matching line wins.

| # | Condition | Verdict | `reason` | `rule` | `calorieChangeKcal` | `overriddenRules` | `unevaluatedRules` |
|---|---|---|---|---|---|---|---|
| 0 | A precondition from §7.2 or §6.5 failed | `insufficientData` | the precondition | nil | nil | empty | empty |
| 1 | Rule 1 fired | `holdSteady` | `ruleFired` | rule 1 | nil | rule 3 if it fired | empty |
| 2 | Rule 2 fired | `addCalories` | `ruleFired` | rule 2 | `+addCaloriesKcal` | rule 3 if it fired | empty |
| 3a | Rule 3 fired and rule 1 is `unknown` | `insufficientData` | `recompositionCheckIncomplete` | nil | nil | empty | rule 1, then rule 2 if `unknown` |
| 3b | Rule 3 fired and rule 1 is `notFired` | `reduceCarbs` | `ruleFired` | rule 3 | `−reduceCarbsKcal` | empty | rule 2 if `unknown` |
| 4a | No rule fired and all three are `unknown` | `insufficientData` | `noRuleEvaluable` | nil | nil | empty | all three |
| 4b | No rule fired otherwise | `holdSteady` | `noChangeRuleFired` | nil | nil | empty | every `unknown` rule, in precedence order |

Why this order and these lines:

- **Rule 1 beats rule 3.** A flat scale with a shrinking waist and lifts that hold or climb is a good
  week. Line 1 returns `holdSteady` and records rule 3 in `overriddenRules`, so the screen can say
  that the scale was slow and why nothing changes. `reduceCarbs` is unreachable while rule 1 fires.
- **Rule 2 beats rule 3.** Rules 1 and 2 cannot both fire: one needs the judged week holding, the
  other dropping. When lifts have been dropping and the scale has also been slow, the two remaining
  rules give opposite advice. Adding wins, because cutting further while working weights fall acts
  against the thing the phase is trying to keep.
- **Line 3a, the withheld verdict.** When the scale has been slow but rule 1 cannot be evaluated, the
  function cannot tell a good recomposition week from a stall. It does not assume lifts are holding
  (that would be line 1) and does not assume they are not (that would be line 3b). It returns no
  advice and names rule 1 as the rule it could not evaluate.
- **Line 3b with rule 2 unknown.** The waist is known not to be shrinking, or the judged week's lifts
  are known to be dropping, so rule 1 is settled and the recomposition case is excluded. The verdict
  stands and names rule 2 as unevaluated, because a full run of dropping weeks would have taken
  precedence.
- **Line 4b.** The owner's rules say that nothing else changes. When no rule fires, the answer is to
  change nothing, and the result lists what it could not check. This is not rule 1: `rule` is nil and
  the reason is `noChangeRuleFired`, so the screen never claims that lifts are holding.

`unevaluatedRules` lists only rules that could have changed the verdict. The full state of all three
is always in `rules`.

Reaching the phase target does not alter the verdict. The rules are the owner's and the function does
not add a fourth. The projection reports `targetReached` and the screen leads with it (§10.2).

### 7.8 Projection

Evaluated in this order; the first match is the status.

1. `noActivePhase` — no phase, or the phase has not started.
2. `weighInOverdue` — as in §7.2.
3. `noTarget` — the phase has no target weight.
4. `remainingKg = quantize(weight(J) − target)`. `targetReached` if
   `remainingKg <= quantize(targetToleranceKg)`. This covers a target already passed, a target equal
   to the current weight, and a target above the current weight.
5. `rateUnknown` — the rate is nil.
6. `notLosing` — `lossKgPerWeek <= 0`. A flat or rising weight has no projected date.
7. `weeksRemaining = remainingKg ÷ lossKgPerWeek`. `beyondHorizon` if
   `weeksRemaining > maxProjectionWeeks`.
8. `daysNeeded = ceil(quantize(weeksRemaining × 7))`, at least 1.
   `targetDay = addDays(anchor(J), daysNeeded)`.
9. `needsNewWeighIn` if `targetDay < today`: the projected day has passed and only a new reading can
   say whether the target was reached.
10. Otherwise `projected`, with `targetDay` and `weeksRemaining`.

The projection is never a past date, never infinite and never more than `maxProjectionWeeks` away.
It is a straight-line extension of the fitted rate and is labelled as an estimate (§11).

### 7.9 `evidenceStartDay`

`addDays(J, −7 × (m + 2))`, where `m` is the largest of `rateWindowWeeks`, `waistWindowWeeks`,
`slowLossConsecutiveWeeks` and `liftDropConsecutiveWeeks`; nil when there is no judged week. Any
reading, lift observation or protein day dated before it changes nothing in the result except the
length of `weeks`. The property test in §12.1 is stated against this field.

## 8. The resolver

### 8.1 One function

`Strand/Data/BodyMeasurementResolver.swift`, pure, no store access:

```swift
enum BodyMeasurementKind { case weight, waist }
enum BodyMeasurementSource: String { case labBook, appleHealth, profile, profileDefault }
enum BodyMeasurementConsumer { case display, estimate }
enum BodyMeasurementPolicy { case unified, legacyDisplay, legacyEstimate }

struct DatedBodyMeasurement: Equatable {
    let day: String
    let takenAt: Int?           // nil for a per-day Apple Health value
    let value: Double           // kg or cm
    let source: BodyMeasurementSource
    let rowId: String?          // the labMarker id, for edit and delete
}

struct ResolvedBodyMeasurement: Equatable {
    let kind: BodyMeasurementKind
    let value: Double           // kg or cm
    let source: BodyMeasurementSource
    let day: String?            // nil for the profile value, which has no date
}

struct BodyMeasurementCandidates {
    var labBook: [LabMarkerRow]                         // rows for this kind's marker key
    var appleHealth: [(day: String, value: Double)]     // weight only; empty for waist
    var profileValue: Double
    var profileIsSet: Bool                              // whether the profile key was ever written
}

enum BodyMeasurementResolver {
    /// The one place a flag state and a consumer become a policy.
    static func policy(flagEnabled: Bool, consumer: BodyMeasurementConsumer) -> BodyMeasurementPolicy
    /// Every dated reading the policy admits, ascending, one per (day, source rule below).
    static func series(_ kind: BodyMeasurementKind, candidates: BodyMeasurementCandidates,
                       policy: BodyMeasurementPolicy) -> [DatedBodyMeasurement]
    /// The current value as of `day`. Nil only for a waist that has never been set anywhere.
    static func resolve(_ kind: BodyMeasurementKind, asOf day: String,
                        candidates: BodyMeasurementCandidates,
                        policy: BodyMeasurementPolicy) -> ResolvedBodyMeasurement?
}
```

`resolve` is `series(...).last(where: day <= asOf)`, else the profile value. The scorecard's weekly
points are built from the same `series`. So the scorecard's `currentWeightKg`, the Today tile and the
estimates' input are three reads of one list.

### 8.2 Precedence (the `unified` policy)

The roadmap proposed "newest Lab Book reading, then Apple Health series, then the profile value".
That is **changed** to:

1. Among dated readings on or before the as-of day, **the newest day wins**, whichever source it
   came from.
2. On the same day, **Lab Book beats Apple Health**. Within Lab Book on the same day, the greatest
   `takenAt` wins, then the greatest `id`.
3. With no dated reading, the **profile value**: source `profile` when the profile key was written,
   `profileDefault` when it never was (the weight default of 75 at `Profile.swift:125`). A waist of 0
   is "not set" and resolves to nil.

Why the change: strict source precedence would let a months-old manual reading hide a newer one from
another source, and the Apple Health page (`AppleHealthView.swift:530`) would then show a different
"latest weight" from Today. Newest-wins is also what Android's existing resolver does
(`ProfileWeightSync.kt:36`). For the owner today the two rules give the same answer, because the
Health read set excludes body mass and the Apple series does not grow.

Candidates and exclusions:

| Store | Admitted | Notes |
|---|---|---|
| `labMarker` `weight` / `waist`, any `source` | Yes | Unit normalised: `kg` as is; `lb` or `lbs` divided by `UnitFormatter.poundsPerKilogram`; `cm` as is; `in` multiplied by `UnitFormatter.centimetersPerInch`; unit comparison is case-insensitive after trimming. A row with any other unit, a nil `value`, or a non-finite or non-positive value is ignored |
| `appleDaily.weightKg` and `metricSeries` `weight` under `apple-health` | Yes, weight only | Both are written from the same imports; merged per day, the daily column winning |
| `metricSeries` `weight` under `nutrition-csv` | **No** | The unit is not recorded (`NutritionCsvImport.swift:23-24`) |
| `metricSeries` under `lab-book` | **No** | It is a projection of the `labMarker` rows already admitted, and reading both would count one reading twice |
| `profile.weightKg`, `profile.waistCm` | Fallback only | Undated |

### 8.3 Flag off: exact legacy behaviour

With `noop.cutScorecardEnabled` off, the same function runs under the two legacy policies and returns
what the app returns today:

- `legacyDisplay`: Apple Health only, then the profile. Lab Book is not consulted. Each Today view
  keeps passing the Apple rows it already fetches, with its existing window (91 days in Liquid and
  the redesign, 90 in classic) and its existing as-of day (the selected day in Liquid and the
  redesign, the latest day in classic).
- `legacyEstimate`: the profile value only.

So every reader goes through the resolver in both states, and the flag changes the policy, not the
call sites. `policy(flagEnabled:consumer:)` returns `unified` for both consumers when the flag is on.

### 8.4 Readers that migrate

Every row marked "Resolver" in §4.1 and §4.2: `IntelligenceEngine.swift:637-643`, `:897`,
`:2615-2621`; `AppModel.swift:1044`; `HealthView.swift:768-769`, `:807`; `TestCentreView.swift:116`;
`LiquidTodayView.swift:3246-3252` and `:1613-1618`; `TodayView.swift:4136-4139` and `:5212-5217`;
`RedesignTodayView.swift:608-614`. `BodyMeasurementProvider` (main-actor, observable) fetches the
candidates from the repository, holds the resolved snapshot for today, and refreshes after
`Repository.refresh()` and after every `WeighInStore` write. The estimate call sites take the value
from that snapshot; the scoring pass captures it once at the start of a pass, as it captures its other
inputs (`IntelligenceEngine.swift:888-899`).

Two consequences the implementer and the data-safety reviewer must know:

- `UserProfile.cacheKey` includes the weight's bit pattern
  (`Packages/StrandAnalytics/Sources/StrandAnalytics/WorkoutDetector.swift:43-45`) and keys the
  per-cycle load cache (`Strand/Data/DayCycleIntelligenceIntegration.swift:217`). With the flag on, a
  weekly weigh-in invalidates that cache exactly as editing the weight in Settings does today, and the
  next pass re-estimates calories for its window with the new weight.
- The waist chooses the VO₂max estimator (`ScoreInputProvenanceStore.swift:32`). With the flag on, the
  weekly estimate uses the newest waist reading.

Both are the intended meaning of "the estimates never show a different weight". Neither changes a
formula, so no analytics twin changes.

### 8.5 Does saving a weigh-in update the profile value?

**The profile becomes a fallback for reading and a mirror for writing.** Readers never read it
directly. When the flag is on and the resolved value for today comes from a dated reading, the
provider writes that value to `profile.weightKg` (and `profile.waistCm`) if it differs. Nothing else
writes the profile value while a dated reading exists (§10.7).

Why keep the mirror when no reader uses it:

- `profile.weightKg` and `profile.waistCm` are in the backup whitelist on both platforms
  (`BackupSettings.swift:52`, `:54`; `BackupSettings.kt:53`, `:55`). The mirror keeps a backup's
  settings and its database rows in agreement.
- Android's analytics read the profile value. A database restored there computes from the same weight.
- If the flag is switched off, the legacy policies fall back to a profile value that is the last
  weigh-in, not a stale figure.
- There is precedent on both platforms: the derived age mirrored under the legacy key
  (`Profile.swift:15-19`), and Android's Health Connect weight written into the profile
  (`HealthConnectWeightSync.kt:25-31`).

The mirror has one writer, and §12.3 asserts it equals the resolver after every write.

### 8.6 The test that no reader bypasses the resolver

Two tests, because counting call sites alone is the weak form of this check.

1. **Source scan**, `Tools/test_body_measurement_single_resolver.py`, in the Python suite that already
   asserts on product source and runs on every change (`Tools/test_home_i18n.py`). It scans `Strand/`,
   `StrandiOS/`, `StrandiOSShared/`, `StrandiOSWidgets/` and the watch targets and fails on any
   occurrence of `profile.weightKg`, `profile.waistCm`, `$profile.weightKg`, `$profile.waistCm`,
   `series(key: "weight"`, `sparkValues("weight"` or a read of `.weightKg` from an `AppleDaily` row,
   outside an explicit allowlist of file-and-reason pairs: `Profile.swift` (the store),
   `BodyMeasurementResolver.swift` and `BodyMeasurementProvider.swift` (the funnel), `SettingsView.swift`
   and `OnboardingWizard.swift` (the profile editors), `AppleHealthView.swift` (a labelled source
   page), the import writers, and the demo seeder. The allowlist is a literal in the test, so adding a
   reader means editing the test. The test also asserts each allowlisted file still contains the
   pattern, so a stale entry fails.
2. **Behavioural**, `StrandTests/BodyMeasurementSingleSourceTests.swift`. With a store holding a Lab
   Book weight, an older Apple Health weight and a different profile value, it asserts that the
   Today tile input, the `UserProfile` handed to the estimates, the Health readiness input and
   `CutScorecardResult.currentWeightKg` are the same number, and the same again for waist. Then it
   deletes the Lab Book row and asserts all four move together.

## 9. Storage

### 9.1 Weigh-ins

A weigh-in is one or two `labMarker` rows, written only by `WeighInStore`:

| Column | Value |
|---|---|
| `id` | `"<markerKey>-<takenAt>-<8 hex>"`, the form the Lab Book editor uses (`MarkerEditorView.swift:430`) |
| `deviceId` | `repo.deviceId`, the same id Lab Book writes under (`LabBookView.swift:20`, `:266`), so both screens list the same rows |
| `markerKey` | `weight` or `waist` |
| `category` | `bodyMeasurement` |
| `takenAt` | The actual instant, epoch seconds |
| `day` | The local day of `takenAt` in the device's zone at the moment of saving, from `LocalDayWindows(timeZone:).dayKey(for:)` (`Packages/StrandAnalytics/Sources/StrandAnalytics/LocalDayWindows.swift:265`), which takes the zone as a parameter. A test asserts it equals `LabBookFormat.dayKey` (`LabBookView.swift:571`) for the same zone, so a row saved by either screen lands on the same day |
| `value` | Kilograms or centimetres, unrounded. Pounds and inches are converted with the app's constants before saving |
| `unit` | `kg` or `cm` |
| `source` | `manual` |
| `valueText`, `note`, `referenceText` | nil |

Operations, all through existing store calls (`LabMarkerStore.swift:112`, `:163`, `:191`):

- **Save.** `upsertLabMarkers`. Two saves in the same second for the same marker update one row (the
  natural key). A second weigh-in on another instant is a second row; the latest represents the day
  and the week.
- **Edit the value.** `upsertLabMarkers` with the same `id`, `takenAt` and `source`: updated in place.
- **Edit the date or time.** Insert the new row first, then `deleteLabMarker` the old `id`. In that
  order an interruption leaves two readings, which the owner can see and delete, and never none.
- **Delete.** `deleteLabMarker`. The store re-projects the day (`LabMarkerStore.swift:199`).
- After each: `repo.refresh()`, then the provider refreshes and mirrors.

No migration, no new table, no new column, no new catalogue key, no new store function.

### 9.2 Settings

All in `UserDefaults.standard`, declared in `CutScorecardSettings`.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `noop.cutScorecardEnabled` | Bool | `false` | The feature flag. Follows the `noop.*` toggle convention (`RootTabView.swift:73`). Off: no card, no screen, no reminder, legacy resolver policies |
| `cutScorecard.phases` | String | absent | JSON array of phases, ascending by `startDay` |
| `cutScorecard.rules` | String | absent | JSON object of rule parameters |
| `cutScorecard.reminder.enabled` | Bool | `false` | The reminder switch |
| `cutScorecard.reminder.weekday` | Int | 7 | 1 = Sunday … 7 = Saturday, the numbering `WindDownNudge` uses (`WindDownNudge.swift:24`) |
| `cutScorecard.reminder.minuteOfDay` | Int | 480 | Minutes after local midnight |

`cutScorecard.phases` element:

```json
{"kind":"cut","name":"Fixture cut","rateHighPercentPerWeek":1.2,"rateLowPercentPerWeek":0.4,"startDay":"2031-01-06","targetWeightKg":94.0,"v":1}
```

`kind` is `cut` or `other`. The active phase is the element with the greatest `startDay` on or before
today. The app passes a `CutScorecardPhase` to `evaluate` only when the active phase's kind is `cut`;
otherwise it passes nil. `targetWeightKg` is omitted when there is no target. Stage 1's interface
edits the active phase and can start a new one; it does not edit past phases.

`cutScorecard.rules` is an object whose keys are the property names of `CutScorecardParameters`, plus
`"v":1`. `proteinFloorGrams` is omitted when unset. A missing key takes the generic default. An
object that fails to parse, or that fails the validation in §6.5, is treated as absent and the screen
shows the "rules need attention" state rather than a verdict.

Both strings are written with sorted keys so that the same settings give the same bytes.

### 9.3 Backup whitelist

| Canonical key | JSON kind | Swift storage key | Joins the whitelist |
|---|---|---|---|
| `cutScorecard.phases` | String | `cutScorecard.phases` | **Yes**, both platforms |
| `cutScorecard.rules` | String | `cutScorecard.rules` | **Yes**, both platforms |
| `noop.cutScorecardEnabled` | — | — | No. A Bool cannot cross, and `noop.*` toggles are per install by the whitelist's own rule (`BackupSettings.swift:40-42`). After a restore the feature is off until switched on, which is the safe direction |
| `cutScorecard.reminder.*` | — | — | No. A reminder depends on this device's notification permission; restoring "on" would persist a switch that cannot fire, the defect `WindDownNudge.swift:128-135` documents |

Edits: `BackupSettings.whitelist` and `BackupSettings.appleDefaultsKey` (`BackupSettings.swift:49-70`,
`:75-89`); `BackupSettingsCodec.WHITELIST` and the snapshot and apply mappings (`BackupSettings.kt:50-76`,
`:143`, `:191`). A JSON array carried as a String has a precedent in `today.hostedCards`
(`BackupSettings.swift:44-48`, `:62`). Android stores and re-exports the two strings without parsing
them.

The whitelist's header requires that the file stay safe to share (`BackupSettings.swift:13-15`). A
target weight is the same class of value as the `profile.weightKg` it already carries.

## 10. Screens and states

Frames are designed at G1. This section fixes what each surface must be able to show. Every state
below needs a frame, at the default text size and at the largest accessibility size (the redesign
allows up to `accessibility5`, `StrandiOS/App/StrandiOSApp.swift:247`).

### 10.1 Entry card in Your Cards

`DashboardCard.scorecard`. Not in `defaultSelection`, like `coupled` and `coach`
(`DashboardCards.swift:35-46`, `:146-148`), so it appears only when the owner adds it, and it renders
only while the flag is on (`TodayCardResolver.renderList`, `Strand/Data/TodayCardReadout.swift:106-111`,
gains a `scorecardEnabled` parameter defaulting to `false`). It is a value card, not a shortcut card.
The editor hides it while the flag is off. Classic and Liquid Today and macOS do not render it.

| State | Value | Caption |
|---|---|---|
| Loading | skeleton (`noopSkeleton`, `StrandiOS/Redesign/YourCardsSection.swift:102`) | — |
| Flag on, no cut phase | dash | "Set up your phase" |
| No readings | dash | "Log your first weigh-in" |
| One reading | the weight | "First weigh-in logged" |
| Verdict available | the current weight | the short verdict (§11) |
| Fewer readings than the rules need | the current weight | "Building: n of m weeks" |
| Weigh-in due (no reading this week, last week has one) | the current weight | "Weigh-in due this week" |
| Overdue | the last weight, tertiary colour | "Last weigh-in <date>" |
| Lift signal unknown, verdict withheld | the current weight | "Lifts not known this week" |
| Target reached | the current weight | "Target reached" |
| Weight rising | the current weight | the short verdict; no colour change, no warning |
| A past day selected on Today | dash | "Shown for today only", as Hydration does (`TodayCardReadout.swift:269-271`) |

The card's weight is `ResolvedBodyMeasurement.value` from the provider. It taps through to the
scorecard screen.

### 10.2 Scorecard screen

Sections, top to bottom: verdict; four signal rows; weight curve; waist curve; projection; a "Log
weigh-in" action; links to history and to phase and rules.

| State | What shows |
|---|---|
| Loading | Skeleton for every section |
| No cut phase | One explanation and a "Set up phase" action. If readings exist, the curves still show |
| Phase not started | The phase name and start date; curves; no verdict |
| No readings | Empty curves area with "Not measured yet"; the "Log weigh-in" action is primary |
| One reading | The point on each curve; rate "needs a second weigh-in"; verdict per the result |
| Fewer readings than a rule's window | Each rule row shows "n of m weeks"; the verdict is whatever §7.7 returns, with the unevaluated rules named |
| Steady loss in the band | `holdSteady` by rule 1; four signals met or unknown |
| Recomposition week | `holdSteady` by rule 1, with the line that the scale was slow and nothing changes because waist and lifts are on track |
| `addCalories` | The owner's amount as text; "Nothing has been changed" underneath |
| `reduceCarbs` | The owner's amount as text; the same line underneath |
| Lift signal unknown | The lifts row says "Not known: no imported sessions for these days". If the verdict was withheld, the verdict area says which rule could not be checked. If it was not, the verdict shows with the unevaluated rule named beneath |
| A missed week | A gap in each curve at that week: the line breaks, it is not drawn across. The rule rows show the reason |
| Two or more missed weeks, overdue | "Last weigh-in <date>"; no verdict; signals unknown; curves end at the last point |
| Target reached | "Target reached" leads the screen with the date; the verdict remains below it |
| Weight rising | Rate shown as a gain; projection "no date while weight is not falling"; verdict per the rules |
| No target set | Projection row: "No target set" |
| Projection beyond the horizon | "More than two years at this rate" (the number comes from the parameter) |
| Projected day passed | "Log a weigh-in to check the target" |
| No protein floor set / no protein data / incomplete logging | Three distinct captions on the protein row; none of them is "0 days" |
| Rules need attention | The stored rules failed validation: an explanation and a link to the rules sheet; no verdict |
| Readings in a non-metric unit preference | Every weight in the unit system, every waist in the matching length unit |
| Largest text size | Signal rows stack label over value; curves keep their height; nothing truncates a number |
| Reduce Motion | No count-up and no staggered entrance |

Curves are a line with a gradient fill, one point per week. No horizontal band for the expected rate,
no target line, no rule. The target appears as a number in the projection row.

### 10.3 Weigh-in sheet

Step 1, weight. Step 2, waist. One date for both.

| State | Behaviour |
|---|---|
| Step 1, first use | Empty field, focused; the unit from `units.system`; date and time default to now |
| Step 1, prior reading exists | The field is prefilled with the last weight, selected for overtyping |
| Out of range | Weight outside 30–250 kg (the range Settings and onboarding use, `SettingsView.swift:530`, `OnboardingWizard.swift:807`) or not a number: "Next" is disabled and the field says which bound |
| Backdating | The date control allows any past instant and no future one, as the Lab Book editor does (`MarkerEditorView.swift:224`). The sheet shows the week the reading will fall in |
| Already logged this week | A line: "You logged <value> on <day>. This reading will represent the week." Saving is allowed |
| Step 2 | Waist field, prefilled the same way; range 40–200 cm; "Skip" saves weight only |
| Step 2 skipped | Weight saved; the waist signal for that week will be "not measured" |
| Saving | Buttons disabled; inputs captured before the write begins |
| Save failed | The sheet stays open with the values intact and a retry |
| Saved | Dismisses to the scorecard, which shows the new result |
| Decimal separator | A comma or a point is accepted, per the device locale |
| Largest text size | Field, unit and date stack vertically |

### 10.4 History

Newest first, weight and waist of the same day and instant on one row.

| State | Behaviour |
|---|---|
| Loading | Skeleton rows |
| Empty | "No weigh-ins yet" |
| Rows | Date, weight, waist or "not measured", and a mark on the reading that represents its week |
| A reading from another source | Shown with its source (for example a Lab Book CSV import or Apple Health). An Apple Health value is read-only here; a Lab Book row can be edited and deleted whatever wrote it |
| A reading in an unrecognised unit | Not listed here; it remains in Lab Book. A footnote says how many were left out |
| Edit | Opens the sheet with that reading's values and instant |
| Delete | Asks once. On confirmation the row goes, the weekly series and the verdict recompute |
| Delete of the only reading in a week | That week becomes a missed week |
| Edit that moves a reading to another week | Both weeks update |

### 10.5 Phase and rules sheet

Not in the roadmap's frame list (§3, C9).

| State | Behaviour |
|---|---|
| First use | Phase name, start date (today), optional target weight, band prefilled with the generic default; rules prefilled with the generic parameters; each is editable |
| Editing | Current values |
| Invalid | A field that fails §6.5 is marked and "Save" is disabled |
| Start a new phase | Appends a phase; the previous one stays in the stored list |
| Kind "other" | No target, no band, no rules; the scorecard shows "No cut phase is active" |
| Protein floor left empty | Allowed; the protein signal reads "No floor set" |

### 10.6 Settings

A toggle "Weekly weigh-in and scorecard" for the flag, with the reminder row beneath it, visible only
while the flag is on: off; on with weekday and time; and "Notifications are off for NOOP" with a link
to system settings when permission was denied (the outcome `WindDownNudge.swift:124`, `:137-175`
models).

### 10.7 Body metrics rows in Settings

Flag off: unchanged. Flag on and the resolved value has a date: the weight row (and the waist row)
shows the value, its source and its date, and a "Log weigh-in" action, in place of the stepper.
Flag on and no dated reading: the stepper, as today. This is what stops Settings and the scorecard
from holding two different weights.

### 10.8 Today weight row and tile

Flag off: unchanged. Flag on: the value is the resolved value as of the selected day; the caption
names the source ("Lab Book", "latest" for Apple Health, "from profile"); the row routes to the
scorecard when the source is Lab Book and to the existing metric page otherwise.

### 10.9 Placement (Q2)

Two frames: (a) the Today card with a pushed scorecard screen, plus a row in the Health tab; (b) a
tab. The specification recommends (a). See C6 for why (b) costs a tab.

### 10.10 Notification text

Title: "Weekly weigh-in". Body: "Weight, then waist. It takes under a minute." No measurement, no
verdict and no phase name ever appears in a notification.

## 11. User-facing strings

The pure function returns enum cases and numbers. `CutScorecardPresenter` turns them into strings,
all through the String Catalog (`Strand/Resources/Localizable.xcstrings`; locales `de`, `en`, `es`,
`fr`, `it`, `pl`, `pt-PT`, `ru`, `zh-Hans`, `zh-Hant`). The English source strings:

| Case | String |
|---|---|
| Verdict `holdSteady`, rule 1 | "Change nothing" / "Lifts are holding and your waist is shrinking." |
| …with rule 3 overridden | adds "The scale was slow for %lld weeks. That is expected when waist and lifts are on track." |
| Verdict `holdSteady`, `noChangeRuleFired` | "Change nothing" / "None of your change rules fired." |
| Verdict `addCalories` | "Your rule: add %lld kcal" / "Working weights dropped %lld weeks running." |
| Verdict `reduceCarbs` | "Your rule: take %lld kcal from carbohydrate" / "Loss was under %@ per week for %lld weeks." |
| Under any advice | "This is your own rule applied to your own numbers. Nothing has been changed." |
| Overridden rule 3 beside `addCalories` | "The scale was also slow. Your lifts rule comes first." |
| `recompositionCheckIncomplete` | "No verdict this week" / "The scale was slow, but lifts are not known, so a good week cannot be told from a stall." |
| `noRuleEvaluable` | "Not enough to judge yet" |
| `noReadings` | "Log a weigh-in to begin" |
| `noActivePhase` | "No cut phase is active" |
| `phaseNotStarted` | "Your phase starts %@" |
| `weighInOverdue` | "Last weigh-in %@" |
| `invalidInput` | "Your rules need attention" |
| Unevaluated rule 1 | "Could not check: lifts holding and waist shrinking" |
| Unevaluated rule 2 | "Could not check: lifts dropping" |
| Unevaluated rule 3 | "Could not check: slow loss" |
| Signal titles | "Waist", "Working weights", "Protein floor", "Rate of loss" |
| Waist reasons | "Down %@ in %lld weeks", "Not shrinking", "Not measured this week", "Needs an earlier reading" |
| Lift reasons | "Holding or climbing", "Dropping", "Not known: no imported sessions", "Not known: no sessions in these days", "Not known: nothing to compare with", "Not known: no exercise in common" |
| Lift footnote | "Compares the heaviest working set of each exercise with the week before." |
| Protein reasons | "%lld of 7 days at or above your floor", "Below your floor on %lld days", "No floor set", "No protein data", "Not enough days logged" |
| Rate reasons | "%@ per week, %@ of bodyweight", "Below your band", "Above your band", "Needs a second weigh-in", "Gap longer than %lld weeks" |
| Projection | "Estimated %@ at this rate", "Target reached", "No target set", "No date while weight is not falling", "More than %lld weeks at this rate", "Log a weigh-in to check the target" |
| Rule progress | "%lld of %lld weeks" |
| Source captions | "Lab Book", "Apple Health", "from profile" |

None of these strings states or implies a health outcome. "Estimated" marks the projection.

## 12. Test plan

One named test per line. Names state the behaviour protected.

### 12.1 Pure logic — `Packages/StrandAnalytics/Tests/StrandAnalyticsTests/CutScorecardTests.swift`

Empty and small inputs

- `testEmptyInputReturnsInsufficientDataNoReadings`
- `testEmptyInputHasNoWeeksNoRateAndNoProjection`
- `testOneReadingWithoutLiftsIsNoRuleEvaluable`
- `testOneReadingWithHoldingLiftsIsHoldSteadyNoChangeRuleFired`
- `testOneReadingRateIsSingleReading`
- `testTwoReadingsInSameWeekUseTheLatest`
- `testTwoReadingsOnSameDayUseTheGreatestTakenAt`
- `testTwoReadingsExactlyAWeekApartGiveEndpointRate`
- `testFewerWeeksThanSlowLossWindowLeavesRuleThreeUnknownAndOthersEvaluate`
- `testFewerWeeksThanLiftWindowLeavesRuleTwoUnknownAndOthersEvaluate`

Rules and precedence

- `testSteadyLossInsideBandIsHoldSteadyByRuleOne`
- `testSlowLossForExactlyTheWindowIsReduceCarbs`
- `testSlowLossOneWeekShortOfTheWindowIsNotReduceCarbs`
- `testSlowLossAtExactlyTheThresholdDoesNotCount`
- `testSlowLossWithShrinkingWaistAndHoldingLiftsIsHoldSteadyNeverReduceCarbs`
- `testRecompositionWeekRecordsSlowLossAsOverridden`
- `testSlowLossWithShrinkingWaistAndClimbingLiftsIsHoldSteady`
- `testLiftsDroppingForTheWindowIsAddCalories`
- `testLiftsDroppingOneWeekShortOfTheWindowIsNotAddCalories`
- `testLiftsDroppingAndSlowLossTogetherIsAddCaloriesWithSlowLossOverridden`
- `testOneHoldingWeekInsideTheLiftWindowSettlesRuleTwoAsNotFired`
- `testLiftSignalUnknownWithSlowLossAndShrinkingWaistWithholdsVerdictAndNamesRuleOne`
- `testLiftSignalUnknownWithSlowLossAndFlatWaistIsReduceCarbsNamingRuleTwo`
- `testLiftSignalUnknownWithNoRuleFiredIsHoldSteadyNamingUnevaluatedRules`
- `testLiftSignalUnknownNeverYieldsRuleOne`
- `testWaistUnknownWithSlowLossAndHoldingLiftsWithholdsVerdict`
- `testNoRuleFiredIsHoldSteadyWithNilRule`
- `testCalorieAmountsComeFromParameters`
- `testChangingEveryParameterChangesTheOutcomeItGoverns`

Signals

- `testWaistShrinkingComparesWithEarliestReadingInWindow`
- `testFlatWaistIsNotMet`
- `testWaistDecreaseBelowMinimumIsNotMet`
- `testWaistMissingThisWeekIsUnknownNotZero`
- `testLiftDropWithinToleranceIsHeld`
- `testLiftDropShareBelowThresholdIsHolding`
- `testLiftSignalUsesSevenDaysBeforeTheWeighIn`
- `testLiftExerciseNamesCompareExactly`
- `testNoCommonExerciseIsUnknown`
- `testProteinMetAtRequiredDays`
- `testProteinNotMetOnlyWhenUnloggedDaysCannotRescueIt`
- `testProteinIncompleteLoggingIsUnknown`
- `testProteinWithoutFloorIsUnknown`
- `testRateBandBoundsAreInclusive`
- `testRisingWeightIsBelowBand`

Gaps and edits

- `testMissedWeekInTheMiddleLeavesANilWeekAndBreaksTheSlowLossRun`
- `testMissedWeekStillFitsRateAcrossTrueSpacing`
- `testTwoMissedWeeksAtTheEndIsWeighInOverdue`
- `testOneMissedWeekAtTheEndKeepsLastWeeksVerdict`
- `testGapLongerThanWindowHasNoRate`
- `testBackdatedReadingChangesOnlyItsOwnWeek`
- `testDeletedReadingLeavesAMissedWeek`
- `testWeightExactlyFlatIsSlowLossAndNotLosing`
- `testSingleOutlierWeekMovesRateLessThanEndpointDifference`
- `testWeightRisingProjectionIsNotLosing`

Phase and projection

- `testNoPhaseIsInsufficientDataNoActivePhaseButSeriesAndRateRemain`
- `testPhaseNotStartedIsReported`
- `testReadingsBeforePhaseStartDoNotFeedRules`
- `testFirstInPhaseReadingIsTheBaseline`
- `testTargetAlreadyReached`
- `testTargetEqualToCurrentWeightIsReached`
- `testTargetAboveCurrentWeightIsReached`
- `testNoTargetHasNoProjection`
- `testProjectionWithZeroSlopeIsNotLosing`
- `testProjectionWithPositiveSlopeIsNotLosing`
- `testProjectionIsNeverBeforeToday`
- `testProjectionBeyondHorizonIsReported`
- `testProjectionDateRoundsUpToWholeDays`
- `testProjectionOnExactWeekBoundaryIsNotPushedADayByFloatingPoint`
- `testReachingTargetDoesNotChangeTheVerdict`

Week boundaries, in day-key space

- `testSundayAndMondayFallInDifferentWeeks`
- `testWeekSpanningAMonthAndAYearBoundary`
- `testWeekContainingFebruaryTwentyNinth`

Rejection

- `testNonFiniteWeightIsDroppedAndCounted`
- `testNegativeAndZeroWeightAreDroppedAndCounted`
- `testInvalidDayIsDroppedAndCounted`
- `testFutureReadingIsIgnoredAndCounted`
- `testDroppedReadingsLeaveTheResultUnchanged`
- `testNonFiniteParameterIsInvalidInput`
- `testZeroWindowIsInvalidInput`
- `testBandLowAboveHighIsInvalidInput`
- `testUnparseableTodayIsInvalidInput`

Properties

- `testReadingBeforeEvidenceStartDayNeverChangesAnythingButWeeks` (generated)
- `testInputOrderDoesNotChangeTheResult` (generated)
- `testSameInputAndTodayGiveEqualResults`
- `testQuantizeRoundsHalvesAwayFromZero`
- `testEveryEnumRawValueIsStable` (pins every raw value string, since they reach the coach packet in stage 2)

Fixture

- `testFixtureVerdictSequence` (§13, all 22 weeks)
- `testFixtureVariants` (§13.4)

### 12.2 Store — `Packages/WhoopStore/Tests/WhoopStoreTests/WeighInLabMarkerTests.swift`

- `testWeighInRowRoundTrips`
- `testEditingValueWithSameInstantUpdatesInPlace`
- `testInsertThenDeleteMovesAReadingToAnotherDay`
- `testReinsertingAnIdWithANewInstantFails` (pins correction C4)
- `testDeleteRemovesTheRowAndItsProjectedDay`
- `testTwoReadingsOnOneDayProjectTheLatest`
- `testDeletedReadingIsAbsentFromTheMarkerHistory`
- `testWeightAndWaistAtTheSameInstantAreSeparateRows`

### 12.3 App target — `StrandTests/`

`BodyMeasurementResolverTests.swift`

- `testNewestDayWinsAcrossSources`
- `testLabBookWinsTheSameDay`
- `testLatestTakenAtWinsWithinADay`
- `testProfileIsUsedOnlyWithoutADatedReading`
- `testUnsetProfileWeightIsMarkedAsDefault`
- `testUnsetWaistResolvesToNil`
- `testAsOfDayExcludesLaterReadings`
- `testPoundsRowIsConvertedToKilograms`
- `testInchesRowIsConvertedToCentimetres`
- `testUnknownUnitRowIsIgnored`
- `testNutritionCsvWeightIsNeverACandidate`
- `testLegacyDisplayPolicyIgnoresLabBook`
- `testLegacyEstimatePolicyReturnsProfileOnly`
- `testFlagOffPoliciesMatchTheOldTodayAndEstimateBehaviour`
- `testSeriesAndResolveAgreeOnTheCurrentValue`

`BodyMeasurementSingleSourceTests.swift` — the behavioural test in §8.6, plus
`testProfileMirrorEqualsResolverAfterSaveEditAndDelete` and
`testMirrorIsNotWrittenWhileTheFlagIsOff`.

`WeighInStoreTests.swift`

- `testSaveWritesManualBodyMeasurementRows`
- `testPoundsInKilogramsStored`
- `testInchesInCentimetresStored`
- `testDayIsTheLocalDayOfTheInstantInTheGivenZone`
- `testReadingAt2359And0001LandOnDifferentDays`
- `testReadingAcrossADaylightSavingChangeKeepsItsLocalDay`
- `testZoneChangeBetweenTwoReadingsDoesNotMoveTheFirst`
- `testDayKeyAgreesWithLabBookFormat`
- `testBackdatedSaveUsesTheChosenInstant`
- `testEditingTheDateInsertsBeforeDeleting`
- `testOutOfRangeValuesAreRefused`

`CutScorecardSettingsTests.swift`

- `testPhasesRoundTripWithSortedKeys`
- `testActivePhaseIsTheLatestStartedOnOrBeforeToday`
- `testNonCutPhaseYieldsNoPhaseForEvaluation`
- `testRulesRoundTripAndMissingKeysTakeDefaults`
- `testCorruptRulesAreTreatedAsAbsent`
- `testFlagDefaultsToOff`

`CutScorecardInputBuilderTests.swift`

- `testWarmUpAndUnperformedSetsAreExcluded`
- `testImportedAndInAppSessionsBothFeedLifts`
- `testNoSessionsYieldsEmptyLifts`
- `testProteinDaysComeFromTheNutritionSeries`
- `testWeightsComeFromTheResolverSeries`

`CutScorecardPresenterTests.swift` — one test per row of §10.1 and §10.2, named for the state, each
asserting the presentation built from a fixture result; plus `testNoStateRendersAMissingValueAsZero`
and `testNoStringContainsAnInterpolatedNilOrNaN`.

`WeighInReminderTests.swift`

- `testReminderIsOffByDefault`
- `testEnablingSchedulesOneWeeklyRequest`
- `testDisablingRemovesTheRequest`
- `testTurningTheFeatureFlagOffRemovesTheRequest`
- `testDeniedPermissionLeavesTheSwitchOff`
- `testNotificationTextContainsNoNumberOrPhaseName` (privacy scan)

`TodayCardResolverTests.swift` (existing file, extended)

- `testScorecardCardIsHiddenWhileTheFlagIsOff`
- `testScorecardCardIsNotInTheDefaultSelection`

Backup — `Packages/WhoopStore/Tests/WhoopStoreTests/BackupSettingsTests.swift` (extended)

- `testScorecardPhasesAndRulesRoundTripAsStrings`
- `testScorecardFlagAndReminderAreNotExported`

### 12.4 Source scan — `Tools/test_body_measurement_single_resolver.py`

- `test_no_reader_bypasses_the_resolver`
- `test_allowlist_entries_still_match`
- `test_scorecard_backup_keys_match_on_both_platforms` (reads the two whitelist files and compares
  only the two keys this stage adds, because of C10)

### 12.5 Flag-off equivalence

With the flag off, the baseline suite's results are unchanged: `renderList` keeps its existing call
shape through a defaulted parameter, the legacy policies return the old values, the card is absent
from the editor, no notification request exists, and no `labMarker` row or profile value is written.
`testFlagOffPoliciesMatchTheOldTodayAndEstimateBehaviour` and
`testMirrorIsNotWrittenWhileTheFlagIsOff` are the direct assertions.

### 12.6 Fault injection

For each line, make the change, confirm at least one named test fails, restore. Record the result in
the pull request.

| # | Deliberate break | A test that must fail |
|---|---|---|
| F1 | Rule 3 checked before rule 1 | `testSlowLossWithShrinkingWaistAndHoldingLiftsIsHoldSteadyNeverReduceCarbs` |
| F2 | Rule 3 checked before rule 2 | `testLiftsDroppingAndSlowLossTogetherIsAddCaloriesWithSlowLossOverridden` |
| F3 | Unknown lift status treated as holding | `testLiftSignalUnknownNeverYieldsRuleOne` |
| F4 | Unknown lift status treated as dropping | `testLiftSignalUnknownWithSlowLossAndShrinkingWaistWithholdsVerdictAndNamesRuleOne` |
| F5 | `slowLossConsecutiveWeeks` off by one, either way | `testSlowLossForExactlyTheWindowIsReduceCarbs`, `testSlowLossOneWeekShortOfTheWindowIsNotReduceCarbs` |
| F6 | `liftDropConsecutiveWeeks` off by one | `testLiftsDroppingForTheWindowIsAddCalories`, `testLiftsDroppingOneWeekShortOfTheWindowIsNotAddCalories` |
| F7 | Slow-loss comparison `<=` in place of `<` | `testSlowLossAtExactlyTheThresholdDoesNotCount` |
| F8 | Slow-loss threshold replaced by a literal | `testChangingEveryParameterChangesTheOutcomeItGoverns` |
| F9 | Lift tolerance ignored | `testLiftDropWithinToleranceIsHeld` |
| F10 | Lift share ignored | `testLiftDropShareBelowThresholdIsHolding` |
| F11 | Waist minimum ignored, or flat counted as shrinking | `testFlatWaistIsNotMet`, `testWaistDecreaseBelowMinimumIsNotMet` |
| F12 | Waist compared with the previous week only | `testWaistShrinkingComparesWithEarliestReadingInWindow` |
| F13 | Band bound made exclusive | `testRateBandBoundsAreInclusive` |
| F14 | Rate window off by one | `testFixtureVerdictSequence` (rate columns) |
| F15 | Week representative changed to first or mean | `testTwoReadingsInSameWeekUseTheLatest` |
| F16 | Missed week bridged | `testMissedWeekInTheMiddleLeavesANilWeekAndBreaksTheSlowLossRun` |
| F17 | Overdue check removed | `testTwoMissedWeeksAtTheEndIsWeighInOverdue` |
| F18 | Projection allowed with a non-positive rate | `testProjectionWithZeroSlopeIsNotLosing` |
| F19 | Projection horizon removed | `testProjectionBeyondHorizonIsReported` |
| F20 | Quantize removed before the day ceiling | `testProjectionOnExactWeekBoundaryIsNotPushedADayByFloatingPoint` |
| F21 | Protein: unlogged days counted as below the floor | `testProteinIncompleteLoggingIsUnknown` |
| F22 | Calorie amounts hard-coded | `testCalorieAmountsComeFromParameters` |
| F23 | Phase clipping removed | `testReadingsBeforePhaseStartDoNotFeedRules` |
| F24 | Resolver: Apple Health preferred on the same day | `testLabBookWinsTheSameDay` |
| F25 | Resolver: Lab Book admitted under a legacy policy | `testLegacyDisplayPolicyIgnoresLabBook` |
| F26 | A Today view reads `profile.weightKg` directly | `test_no_reader_bypasses_the_resolver` |
| F27 | Edit deletes before inserting | `testEditingTheDateInsertsBeforeDeleting` |
| F28 | Mirror written with the flag off | `testMirrorIsNotWrittenWhileTheFlagIsOff` |

### 12.7 Parity

Layout follows `android/app/src/test/java/com/noop/analytics/LiftMetricsParityOracleTest.kt:1-80`.

1. **Swift to Kotlin.** Compile `CutScorecard.swift` with `WeeklyDigest.swift` and a `main.swift`
   standalone (`swiftc -O`). `main.swift` evaluates the fixture at each of its 22 days, every variant
   in §13.4, and a generated spread: a fixed-seed linear congruential generator written out in the
   file (not a library generator, which differs by platform) producing at least 500 inputs that vary
   reading counts, gaps, values, lift coverage and every parameter. It prints one block per
   evaluation: every field of the result in declaration order, Doubles as `%.6f`, nil as `nil`,
   enums as raw values. That standard output is pasted verbatim as the expected literal in
   `android/app/src/test/java/com/noop/analytics/CutScorecardParityOracleTest.kt`, which builds the
   same inputs with the same generator and prints through the same format.
2. **Kotlin to Swift.** `Packages/StrandAnalytics/Tests/StrandAnalyticsTests/CutScorecardOracleTests.swift`
   holds the same literal and asserts the Swift output against it, so a later change on the Swift
   side fails on the Swift side.
3. Named edges the spread must include, since they are where a port diverges: `quantize` on exact
   halves and on negatives; a `ceil` on a value that is an integer but for floating-point error;
   the tie order in "latest reading of the week"; integer division of negative week differences;
   exercise names that differ only by case or trailing space; day keys before 1970.
4. `android/app/src/test/java/com/noop/analytics/CutScorecardTest.kt` mirrors the named cases of
   §12.1.
5. Android tests cannot run on this machine (no JDK; Q3). Until that changes the Kotlin twin and its
   tests are reported as **written, not run**, and the pull request says so.
6. The two backup keys are checked by `test_scorecard_backup_keys_match_on_both_platforms` and by
   `BackupSettingsCodecTest.kt`.
7. **Written disposition for the resolver.** `BodyMeasurementResolver` has no Kotlin twin. It is
   app-layer selection among platform-specific sources, Android has no scorecard surface in this
   workstream, and it produces no new stored shape: its only writes are `labMarker` rows and the
   existing `profile.weightKg` and `profile.waistCm` keys. Android keeps `ProfileWeightSync`.

### 12.8 Simulator and rehearsal

As in the roadmap: every frame reproduced from the fixture at default and largest text size, Reduce
Motion on and off, with enter, edit, delete and backdate exercised by tapping; then the private
real-data rehearsal from 0B-7, whose results stay out of the repository.

## 13. Fixture

Everything here is invented. "Fixture Person" does not exist; the numbers are round on purpose.

### 13.1 Person, phase and parameters

- Phase: name "Fixture cut", kind `cut`, start 2031-01-06 (a Monday), target 94.0 kg, band 0.40 to
  1.20 percent per week.
- Weigh-ins on Wednesdays, starting 2031-01-08, `takenAt` at 07:00 UTC of the day.
- Parameters: `rateWindowWeeks` 4, `waistWindowWeeks` 2, `waistMinDecreaseCm` 0.5,
  `liftDropTolerancePercent` 5, `liftDropShare` 0.5, `liftDropConsecutiveWeeks` 3, `addCaloriesKcal`
  300, `slowLossThresholdKgPerWeek` 0.4, `slowLossConsecutiveWeeks` 3, `reduceCarbsKcal` 250,
  `proteinFloorGrams` 100, `proteinMinDaysPerWeek` 5, `maxWeighInAgeWeeks` 1, `maxProjectionWeeks`
  104, `targetToleranceKg` 0.

  These differ from the generic defaults in several fields on purpose, so a test that passes proves
  the parameters were read.

### 13.2 Lifts and protein

Two exercises, "Fixture Press" and "Fixture Row", one session each Monday (two days before the
weigh-in), one working set each. Sessions also exist on the two Mondays before week 1.

| Monday of week | Fixture Press (kg) | Fixture Row (kg) |
|---|---|---|
| two before week 1, one before week 1, 1–4 | 60.0 | 50.0 |
| 5 | 62.5 | 50.0 |
| 6 | 62.5 | 50.0 |
| 7 | 62.5 | 52.5 |
| 8, 9 | 62.5 | 52.5 |
| 10–15 | no session | no session |
| 16 | 62.5 | 52.5 |
| 17 | 57.5 | 47.5 |
| 18 | 52.5 | 42.5 |
| 19 | 47.5 | 40.0 |
| 20, 21 | 47.5 | 40.0 |
| 22 | 50.0 | 40.0 |

Protein, in grams, for the seven days before the weigh-in, oldest first:

| Week | Days |
|---|---|
| 2, 3, 4 | 120, 120, 120, 80, 120, 120, 120 |
| 5 | 120, 80, 80, 120, 80, 80, 120 |
| 6 | 120, none, 120, none, none, 120, none |
| all others | none |

### 13.3 Weekly readings and the expected sequence

One extra reading: Monday 2031-01-20, 98.9 kg, in week 3. It must lose to Wednesday's 98.4.

Each row is the result of `evaluate` with `today` set to that row's day and only the readings up to
that day. "Loss" is `weeklyLossKg`. "Rate" is `lossKgPerWeek` / `percentPerWeek`. Rules are in the
order rule 1, rule 2, rule 3: F fired, N not fired, U unknown.

| Wk | Day | Weight | Waist | Loss | Rate | Waist signal | Lift signal | Rules | Verdict | Reason / rule | Overridden | Unevaluated | Projection |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 2031-01-08 | 100.0 | 100.0 | — | none (`singleReading`) | unknown | met | U N U | holdSteady | noChangeRuleFired | — | 1, 3 | rateUnknown |
| 2 | 2031-01-15 | 99.2 | 99.5 | 0.8 | 0.800 / 0.803 | met (−0.5) | met | F N N | holdSteady | rule 1 | — | — | 2031-03-02 |
| 3 | 2031-01-22 | 98.4 | 99.0 | 0.8 | 0.800 / 0.806 | met (−1.0) | met | F N N | holdSteady | rule 1 | — | — | 2031-03-02 |
| 4 | 2031-01-29 | 97.6 | 98.5 | 0.8 | 0.800 / 0.810 | met (−1.0) | met | F N N | holdSteady | rule 1 | — | — | 2031-03-02 |
| 5 | 2031-02-05 | 97.5 | 98.0 | 0.1 | 0.660 / 0.670 | met (−1.0) | met | F N N | holdSteady | rule 1 | — | — | 2031-03-15 |
| 6 | 2031-02-12 | 97.4 | 97.5 | 0.1 | 0.450 / 0.459 | met (−1.0) | met | F N N | holdSteady | rule 1 | — | — | 2031-04-06 |
| 7 | 2031-02-19 | 97.3 | 97.0 | 0.1 | 0.240 / 0.246 | met (−1.0) | met | F N F | holdSteady | rule 1 | 3 | — | 2031-05-27 |
| 8 | 2031-02-26 | 97.2 | 97.0 | 0.1 | 0.100 / 0.103 | met (−0.5) | met | F N F | holdSteady | rule 1 | 3 | — | 2031-10-08 |
| 9 | 2031-03-05 | 97.1 | 97.0 | 0.1 | 0.100 / 0.103 | notMet (0.0) | met | N N F | reduceCarbs (−250) | rule 3 | — | — | 2031-10-08 |
| 10 | 2031-03-12 | none | none | — | as week 9 | as week 9 | as week 9 | N N F | reduceCarbs (−250) | rule 3 | — | — | 2031-10-08 |
| 11 | 2031-03-19 | 96.0 | 96.5 | none | 0.331 / 0.342 | met (−0.5) | unknown | U N U | holdSteady | noChangeRuleFired | — | 1, 3 | 2031-05-01 |
| 12 | 2031-03-26 | 95.2 | 96.0 | 0.8 | 0.510 / 0.529 | met (−0.5) | unknown | U U N | holdSteady | noChangeRuleFired | — | 1, 2 | 2031-04-12 |
| 13 | 2031-04-02 | 95.1 | 95.5 | 0.1 | 0.531 / 0.554 | met (−1.0) | unknown | U U N | holdSteady | noChangeRuleFired | — | 1, 2 | 2031-04-17 |
| 14 | 2031-04-09 | 95.0 | 95.0 | 0.1 | 0.310 / 0.325 | met (−1.0) | unknown | U U N | holdSteady | noChangeRuleFired | — | 1, 2 | 2031-05-02 |
| 15 | 2031-04-16 | 94.9 | 94.5 | 0.1 | 0.240 / 0.252 | met (−1.0) | unknown | U U F | insufficientData | recompositionCheckIncomplete | — | 1, 2 | 2031-05-13 |
| 16 | 2031-04-23 | 94.8 | 94.5 | 0.1 | 0.100 / 0.105 | met (−0.5) | unknown | U U F | insufficientData | recompositionCheckIncomplete | — | 1, 2 | 2031-06-18 |
| 17 | 2031-04-30 | 94.7 | 94.5 | 0.1 | 0.100 / 0.105 | notMet (0.0) | notMet | N U F | reduceCarbs (−250) | rule 3 | — | 2 | 2031-06-18 |
| 18 | 2031-05-07 | 94.6 | 94.5 | 0.1 | 0.100 / 0.105 | notMet (0.0) | notMet | N U F | reduceCarbs (−250) | rule 3 | — | 2 | 2031-06-18 |
| 19 | 2031-05-14 | 94.5 | 94.5 | 0.1 | 0.100 / 0.106 | notMet (0.0) | notMet | N F F | addCalories (+300) | rule 2 | 3 | — | 2031-06-18 |
| 20 | 2031-05-21 | 95.5 | 94.5 | −1.0 | −0.120 / −0.127 | notMet (0.0) | met | N N F | reduceCarbs (−250) | rule 3 | — | — | notLosing |
| 21 | 2031-05-28 | 94.0 | 94.0 | 1.5 | 0.050 / 0.053 | met (−0.5) | met | F N N | holdSteady | rule 1 | — | — | targetReached |
| 22 | 2031-06-04 | 93.5 | 93.5 | 0.5 | 0.270 / 0.286 | met (−1.0) | met | F N N | holdSteady | rule 1 | — | — | targetReached |

The verdict sequence, which the acceptance test asserts exactly:

`holdSteady` ×8, `reduceCarbs` ×2, `holdSteady` ×4, `insufficientData` ×2, `reduceCarbs` ×2,
`addCalories`, `reduceCarbs`, `holdSteady` ×2.

What each stretch covers:

- Week 1: one reading. Weeks 2–4: steady loss inside the band. Week 3: two readings in a week.
- Weeks 5–8: the scale slows while waist and lifts are on track. Weeks 7 and 8 are the recomposition
  case: rule 3 fires and rule 1 overrides it.
- Week 9: the waist stops shrinking and `reduceCarbs` appears for the first time.
- Week 10: a missed week; the previous verdict stands for one week.
- Week 11: the first reading after a gap; rule 3 is unknown. Rule 2 is still settled by week 9.
- Weeks 12–16: no lift sessions. Weeks 12–14 name the unevaluated rules; weeks 15 and 16 withhold the
  verdict.
- Weeks 17–18: lifts drop, rule 2 is not yet evaluable for its full window, and the verdict names it.
- Week 19: rule 2 fires and overrides rule 3.
- Week 20: weight rises; no projection.
- Weeks 21–22: target equal to the current weight, then target above it.
- Protein: weeks 2–4 `met` (6 of 7), week 5 `notMet` (3 of 7 logged at the floor), week 6
  `unknown(.incompleteLogging)` (3 logged), every other week `unknown(.noProteinData)`.

These values were produced by a scratch model of §7 written for this document, not by the
implementation, which does not exist yet. The Test author recomputes any row by hand before relying
on it; a disagreement is a defect in this table or in §7 and is reported, not worked around.

### 13.4 Variants

Each is the fixture with one change.

| Variant | Change | Expected |
|---|---|---|
| V1 | No readings at all | `insufficientData(.noReadings)`, empty `weeks` |
| V2 | Week 1 only, no lift observations | `insufficientData(.noRuleEvaluable)`, unevaluated 1, 2, 3 |
| V3 | Week 11's reading removed, `today` 2031-03-19 | `insufficientData(.weighInOverdue)` |
| V4 | `phase` nil, `today` 2031-01-29 | `insufficientData(.noActivePhase)`; rate 0.800 still reported |
| V5 | Phase start moved to 2031-02-03 (the Monday of week 5), `today` 2031-02-19 | Weeks 1–4 not in phase; week 5 is the baseline with no weekly loss; rule 3 `unknown(.fewerWeeksThanWindow)` |
| V6 | Target removed, `today` 2031-01-29 | Projection `noTarget`; verdict unchanged |
| V7 | A reading of 98.0 kg backdated to Thursday 2031-01-16, `today` 2031-03-05 | Week 2's point becomes 98.0 and the weekly losses of weeks 2 and 3 change; every other week keeps its point; the verdict for week 9 is unchanged |
| V8 | Week 6's weight replaced by 99.9 (an outlier), `today` 2031-02-26 | Weekly losses for weeks 6 and 7 change; the fitted rate moves by less than the end-point difference would |
| V9 | A NaN weight and a −5.0 weight added in week 4 | Result identical to the fixture; `rejections.nonFinite == 1`, `nonPositive == 1` |
| V10 | A reading dated 2029-06-06 added | Only `weeks` grows |
| V11 | "Fixture Press" renamed "fixture press" from week 17 on | Common exercises fall to one |
| V12 | Target 80.0, `today` 2031-02-26 | `beyondHorizon` (17.2 kg at 0.1 kg per week) |

## 14. Work packages and file ownership

A package edits only the files listed for it. WP 1-8 is the sole writer of the String Catalog.

| WP | Role | Files |
|---|---|---|
| 1-3 | Test author | `Packages/StrandAnalytics/Tests/StrandAnalyticsTests/CutScorecardTests.swift`, `.../CutScorecardFixture.swift`; `Packages/WhoopStore/Tests/WhoopStoreTests/WeighInLabMarkerTests.swift`; additions to `Packages/WhoopStore/Tests/WhoopStoreTests/BackupSettingsTests.swift`; `StrandTests/BodyMeasurementResolverTests.swift`, `BodyMeasurementSingleSourceTests.swift`, `WeighInStoreTests.swift`, `CutScorecardSettingsTests.swift`, `CutScorecardInputBuilderTests.swift`, `CutScorecardPresenterTests.swift`, `WeighInReminderTests.swift`; additions to `StrandTests/TodayCardResolverTests.swift`; `Tools/test_body_measurement_single_resolver.py` |
| 1-4 | Implementer A | `Packages/StrandAnalytics/Sources/StrandAnalytics/CutScorecard.swift` |
| 1-5 | Parity agent | `android/app/src/main/java/com/noop/analytics/CutScorecard.kt`; `android/app/src/test/java/com/noop/analytics/CutScorecardTest.kt`, `CutScorecardParityOracleTest.kt`; `Packages/StrandAnalytics/Tests/StrandAnalyticsTests/CutScorecardOracleTests.swift`; `android/app/src/main/java/com/noop/data/BackupSettings.kt`; `android/app/src/test/java/com/noop/data/BackupSettingsCodecTest.kt`. The oracle `main.swift` is scratch and is not committed |
| 1-6 | Implementer B | New: `Strand/Data/BodyMeasurementResolver.swift`, `BodyMeasurementProvider.swift`, `WeighInStore.swift`, `CutScorecardSettings.swift`, `CutScorecardInputBuilder.swift`. Edited, reader migration only: `Strand/Data/IntelligenceEngine.swift`, `Strand/App/AppModel.swift`, `Strand/Screens/HealthView.swift`, `Strand/Screens/TestCentreView.swift`, `Strand/Liquid/LiquidTodayView.swift`, `Strand/Screens/TodayView.swift`, `StrandiOS/Redesign/RedesignTodayView.swift` (the weight row only), `Packages/WhoopStore/Sources/WhoopStore/BackupSettings.swift` |
| 1-7 | Implementer C, after G1 and after 1-4 and 1-6 merge | New: `Strand/Data/CutScorecardModel.swift`, `CutScorecardPresenter.swift`; `StrandiOS/Scorecard/ScorecardView.swift`, `WeighInSheet.swift`, `WeighInHistoryView.swift`, `ScorecardPhaseSheet.swift`. Edited: `Strand/Screens/DashboardCards.swift`, `Strand/Data/TodayCardReadout.swift`, `Strand/Screens/TodayCustomizationMetadata.swift`, `Strand/Screens/TodayCustomizationSheet.swift`, `Strand/Data/TodayCardsEditorPresentation.swift`, `StrandiOS/Redesign/YourCardsSection.swift`, `StrandiOS/Redesign/RedesignRoute.swift`, `StrandiOS/Redesign/RedesignTodayView.swift` (card inputs), `StrandiOS/Redesign/RedesignHealthView.swift` (the Health row), `Strand/Screens/SettingsView.swift` (flag toggle and body-metrics rows); `Strand/Screens/TodayView.swift` and `Strand/Liquid/LiquidTodayView.swift` only to make their `DashboardCard` switches exhaustive and to filter the new case out |
| 1-8 | Localiser | `Strand/Resources/Localizable.xcstrings` |
| 1-9 | Implementer C | `Strand/System/WeighInReminder.swift`; the reminder row in `Strand/Screens/SettingsView.swift` |

Shared-file order: `LiquidTodayView.swift`, `TodayView.swift` and `RedesignTodayView.swift` are edited
by 1-6 and then by 1-7, in that order, never in parallel. `SettingsView.swift` is edited by 1-7 and
then 1-9. `Packages/WhoopStore/.../BackupSettingsTests.swift` and
`Packages/StrandAnalytics/Tests/` receive files from 1-3 and from 1-5; they add separate files or
separate test methods and do not edit each other's.

`project.yml` needs no change: `Strand`, `StrandiOS` and `StrandTests` are included by directory
(`project.yml:87-91`, `:220-244`, `:170`). Run `xcodegen generate` after adding files.

Existing tests that the new enum case or parameter can touch, for the Test author to check before
G2: `StrandTests/TodayCardsEditorTests.swift:43` (asserts the shortcut cards; the new card is not a
shortcut), `StrandTests/TodayCardResolverTests.swift:37-41` (calls `renderList`; unaffected by a
defaulted parameter), `Tools/test_home_i18n.py:96-100` (pins Android card ids; Android gains none).

Parity governance: new public declarations in `Packages/StrandAnalytics` are inventoried by
`Tools/parity_ledger.py`. Each carries a twin claim in the existing form ("Kotlin twin: `CutScorecard`."
on the type, "The Kotlin twin is `CutScorecard.evaluate`." on a function). Whether the ledger can be
refreshed at all is the open item of 0B-9; this stage does not attempt it.

## 15. Open questions for the owner

Work proceeds on each recommendation. None of these leaves the algorithm undecided.

| # | Question | Recommendation, in force until overruled |
|---|---|---|
| S1 (Q2) | Where does the scorecard live? | A Today card with a pushed screen, plus a row in the Health tab. A tab would be the sixth with Coach on |
| S2 (Q6) | Where does the lift signal come from? | Imported and in-app lift sessions. Without sessions in the seven days before a weigh-in and the seven before those, the signal is unknown and the screen says so. A manual "lifts held this week" tick is possible later and is not built |
| S3 | When the scale has been slow, the waist is shrinking, and lifts are unknown, should the app withhold the verdict (line 3a) or show `reduceCarbs` with a caveat? | Withhold. It is the only reading that neither assumes lifts are holding nor advises a cut in what may be a good week |
| S4 | When the scale has been slow, the waist is **not** shrinking, and it is unknown whether lifts have been dropping, should `reduceCarbs` show? | Yes, naming the lifts rule as unchecked. Withholding here would mean the rule can never fire without imports |
| S5 | When lifts are dropping and the scale is slow together, which rule wins? | Add calories (rule 2) |
| S6 | Is "dropping" the heaviest working set per exercise falling by more than a tolerance, on at least a set share of the exercises done in both weeks? | Yes. The tolerance and the share are parameters |
| S7 | Is "waist shrinking" measured against the earliest reading in a window of weeks, or against last week? | The window. One tape reading is too coarse to compare week on week |
| S8 | Is the rate a fitted line over the window or the difference between its first and last weigh-ins? | The fitted line |
| S9 | Should lifts and protein be judged over the seven days before the weigh-in, or over the Monday-to-Sunday week? | The seven days before the weigh-in |
| S10 | After a missed week, should the loss across the gap count toward the slow-loss run? | No. The run restarts |
| S11 | Should reaching the target silence the verdict? | No. The screen leads with "Target reached" and the rules keep reporting until the owner ends the phase |
| S12 | With the flag on, may Settings stop offering a stepper for weight and waist once a dated reading exists? | Yes. It is what keeps Settings and the scorecard from disagreeing |
| S13 | May a weekly weigh-in change the weight used by the calorie estimates, and a waist reading change the VO₂max estimate, from that week on? | Yes. It is the stage's stated aim, and it is the same effect as editing the profile today |
| S14 | Should phases and rules be included in backups? | Yes, as two string keys on both platforms. The flag and the reminder are not |
| S15 | Stage 1 supports cut phases only. Is "no verdict outside a cut" acceptable until a later stage? | Yes |
| S16 | Which protein source feeds the protein signal before stage 3? | The existing nutrition CSV series if present; otherwise the signal is "no protein data". The signal never affects the verdict |

## 16. Not determined

- **Whether a cached `DateFormatter` follows a change of device time zone.** `LabBookFormat.dayKey`
  uses a static formatter with no explicit zone (`LabBookView.swift:565-571`). Whether its zone
  updates after the device changes zone while the app is running was not established by reading.
  The weigh-in path avoids the question by passing the zone explicitly (§9.1), and
  `testDayKeyAgreesWithLabBookFormat` records the agreement for the current zone only.
- **Whether the owner's Lab Book already holds weight or waist rows**, and in which unit. The
  rehearsal in 0B-7 will show it. The resolver handles `kg`, `lb`, `cm` and `in`.
- **Readings and a changed strap id.** Lab Book rows are stored under `repo.deviceId`, which is
  re-pointed when a strap is removed and added again (`Repository.swift:131-138`, `:261`). Rows saved
  under the earlier id are then not returned by `labMarkers(deviceId:markerKey:)`. This is existing
  Lab Book behaviour, it would apply to weigh-ins equally, and it was not tested. It needs the
  owner's decision before G8: fix Lab Book and the scorecard together in a separate pull request, or
  accept it. Whether the owner's strap id has ever changed is not known.
- **The size of the re-estimation window** that a changed weight triggers in the scoring pass (§8.4).
  The mechanism was read; the number of days was not traced.
- **Parity ledger state.** Whether new `StrandAnalytics` declarations can be registered depends on
  0B-9. The claim syntax in §14 follows the existing files and was not run through the ledger.
- **The pre-existing whitelist difference** (C10) was observed in the two source files. Whether it is
  known upstream was not checked.
- **Android.** Nothing on the Kotlin side was compiled or run.
- **Row values in §13.3** come from a scratch model, as stated there.

## 17. Design approval record (G1)

To be completed by the orchestrator when the owner approves the frames.

| Frame | Page | Approved on |
|---|---|---|
| — | — | — |

## 18. Rulings after independent tests and implementation (10 November 2026)

The tests (WP 1-3) and the implementation (WP 1-4) were written by separate agents from §6 and §7.
Where they found this document ambiguous or self-contradictory, the orchestrator ruled as below.
These rulings are binding on the tests, the Swift implementation and the Kotlin twin, and they
override the earlier section they name.

| # | Section | Ruling |
|---|---|---|
| R1 | §7.6 | `consecutiveWeeks` is **not capped** at `requiredWeeks`. It counts back from the judged week until the first week where the rule's weekly condition is false or unknown, however long the run. |
| R2 | §7.9 | The claim is narrowed. An item dated before `evidenceStartDay` never changes a signal state, a rule state, the verdict, the rate or the projection. It may change: `weeks`; `rateUnavailable` (`singleReading` against `gapLongerThanWindow`); the lift signal's reason (`noLiftData` against `noSessionsThisWeek`); and `consecutiveWeeks` (R1). The property test is stated against this narrowed claim. |
| R3 | §6.5 | A reading, lift weight or protein total whose magnitude is above `1e100` is rejected and counted as `nonFinite`. A parameter or phase bound above `1e100` is invalid input. This is an arithmetic limit so that no sum or product can overflow into the output; it is not a plausibility range. The twin uses the same constant. |
| R4 | §7.1 | `quantize` returns positive zero, never negative zero. It returns its argument unchanged if `abs(x) × 1000` is not finite (unreachable for inputs that pass R3, kept as a guard). |
| R5 | §6.1 | A day key is valid only in the canonical ten-character form `yyyy-MM-dd`, years 0001 to 9999, naming a real calendar date. Anything else is `invalidDay`, or invalid `today` or phase. `weekStart(containing:)` returns nil for it. |
| R6 | §7.2 | The overdue rule applies with no active phase as well: the rate is nil with `weighInOverdue` and the waist, lift and protein signals are `unknown(weighInOverdue)`. The rate-band signal, the rules, the projection and the verdict keep reporting `noActivePhase` or `phaseNotStarted`. |
| R7 | §7.2, §7.3 | A phase that has not started is treated exactly as no phase: `inPhase` is false for every week, the domain is every week, `weeklyLossKg` is reported for every pair of consecutive weeks, and the judged week is the latest week with a weight. The band bounds in the rate-band signal are nil. |
| R8 | §7.8 | With an active phase and no in-phase weigh-in, the projection status is `noTarget` when the phase has no target and `rateUnknown` otherwise; `remainingKg` is nil. |
| R9 | §6.4, §7.8 | `remainingKg` is set whenever a phase target and an in-phase current weight exist, including while overdue. |
| R10 | §7.1, §7.5, §7.8 | Every threshold comparison uses quantized operands on both sides, including the rate-band bounds, the lift share (`dropped ÷ common` against `liftDropShare`) and `weeksRemaining` against `maxProjectionWeeks`. The reported `weeksRemaining` is the unquantized quotient. |
| R11 | §7.8, §7.9 | A projected day after 9999-12-31 is `beyondHorizon`. `evidenceStartDay` is clamped to `0001-01-01`. |
| R12 | §6.5 | When several inputs are invalid the order checked is parameters, then phase, then `today`. An item with several faults is counted once, in the order `nonFinite`, `nonPositive`, `invalidDay`, `future`. |
| R13 | §6.4 | Secondary fields of unknown signals: counts are zero and optionals nil, except that `noEarlierWaist` carries `currentCm`; the lift signal carries its window days whenever a judged week is evaluated (nil for `noReadings` and `weighInOverdue`); the protein signal always carries `requiredDays` and `floorGrams` and counts `daysLogged` even with no floor; the rate-band signal carries its bounds whenever a started phase exists and `percentPerWeek` only when met or not met. A rule in a precondition-failed state has `consecutiveWeeks` 0 and `requiredWeeks` 1 for rule 1 and the parameter otherwise. `judgedWeekStart` and `evidenceStartDay` stay set while overdue. In the invalid result `requiredWeeks` and `requiredDays` echo the parameters as given, `floorGrams` is set only when finite and positive, and `currentWeightKg`, `judgedWeekStart` and `evidenceStartDay` are nil. |
| R14 | §7.5 | `waistMinDecreaseCm == 0` is valid and makes an unchanged waist `met`. The sentence "a flat waist is `notMet`" describes any positive minimum, including the default. |
| R15 | §6.4 | `spanWeeks` is the number of weeks from the first to the last point used in the fit. |
| R16 | §13.4 | Variant V8 was wrong as written: its outlier sits at the centre of the fit window, where it moves neither the fitted rate nor the end-point difference. The comparison the row intended holds when the outlier is the last point of the window, and the test `testSingleOutlierWeekMovesRateLessThanEndpointDifference` asserts that case. |
| R17 | §12.7 | The standalone oracle compiles with `CutScorecard.swift`, `WeeklyDigest.swift` and `ComparisonEngine.swift`. |
| R18 | §6.4 | Readings echoed in the result (`weeks[].weightKg`, `weeks[].waistCm`, `currentWeightKg`, and the waist signal's `currentCm` and `referenceCm`) are the values as given, not quantized. Derived figures (`weeklyLossKg`, `changeCm`, the rate) are quantized as §7 states. |
| R19 | §6.4 | The rate-band signal reports `lowPercentPerWeek` and `highPercentPerWeek` as given in the phase. Only the comparison quantizes them (R10). |
| R20 | §6.5 | In the invalid result the rate-band bounds and `currentWeightDay` are nil. |
| R21 | §6.4 | Any day the function reports that would fall before 0001-01-01 (for example a lift window for a weigh-in in the first week of year 0001) is reported as `0001-01-01`. The function does not trap. |
| R22 | §6.5 | An integer parameter is valid at any value at or above its stated lower bound, `Int.max` included. No arithmetic on it may overflow. |
| R23 | §7.6 | `consecutiveWeeks` never counts a week before the phase domain. |

Fault injection on 10 November 2026 ran 198 single mutations of the implementation. Three were not
caught by any test and are covered by tests added afterwards: the heaviest set when one exercise has
several sets on one day; the prior lift window ending at `a − 8`, not `a − 7`; and the `dropped >= 1`
condition when `liftDropShare` quantizes to zero. Seven mutations were equivalent (they cannot change
any output).
