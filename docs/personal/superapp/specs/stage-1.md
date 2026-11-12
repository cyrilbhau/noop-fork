# Stage 1 specification — weigh-in and scorecard

Gate G0 for stage 1 of the health super-app workstream. Read [CONTEXT.md](../CONTEXT.md),
[ROADMAP.md](../ROADMAP.md) (stage 1) and [QUALITY-GATES.md](../QUALITY-GATES.md) first.

Verified against the source at commit `6413d94c` (branch `personal/superapp-1-spec`, cut from
`personal/superapp-0-foundation`). Every `path:line` below is as of that commit. Paths are relative to
the repository root. Nothing was built or run for this document; it is a reading of the code.

This file contains no personal measurements. Every number in an example belongs to the synthetic
"Fixture Person" in §13, and every default in §6.3 was chosen for this document.

Reconciled with the cross-stage check on 11 November 2026, in two passes: see §19 for what changed
and rulings R44 to R48 in §18 for the changes of behaviour. Two rules of the workstream have their
one home in this file: a manual weigh-in outranks a body scan within its week (§8.7, R44) and the
protein floor is a whole number of grams (§9.2, R45). Android work is stopped by ruling R43; every mention of
Kotlin below describes files already in the tree and orders no further Kotlin work.

## 1. Goal and scope

Android: ruling R43 (§18) stops all Android work. Nothing in this section orders a Kotlin change.

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
- Diet breaks and deloads. They are events (stage 5 specification, the `dietBreak` and `deload`
  kinds), never phases. A phase is only a long block. The scorecard keeps reporting during an event
  (§7.2, ruling R46).
- A target date, and any second weight goal. The one target weight is the active phase's
  `targetWeightKg` (§9.2). A dated target on the timeline is a stage 6 checkpoint with no weight, and
  a checkpoint that carries a weight is a waypoint (stage 6 specification; ruling R47).
- Android, entirely (R43). The Kotlin twin of the pure function, its oracle test and the two backup
  keys were written before that ruling; they stay in the tree as written, were never executed, and
  are not maintained.
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

A record of what exists on the Kotlin side. Under R43 none of it is edited, compiled or run again.

| Piece | Where | Stage 1 |
|---|---|---|
| Marker catalogue | `android/app/src/main/java/com/noop/analytics/MarkerCatalog.kt:102-105` | Unchanged; no new key |
| Profile values | `android/app/src/main/java/com/noop/ui/SettingsScreen.kt:184` (`ProfileStore`) | Unchanged |
| Newest-weight resolver for Health Connect, which writes the newest reading into the profile | `android/app/src/main/java/com/noop/analytics/ProfileWeightSync.kt:18-36`, `android/app/src/main/java/com/noop/ui/HealthConnectWeightSync.kt:25-31` | Unchanged. It is the precedent for §8.5: an external reading written through to `profile.weightKg`, which then travels in the backup |
| Today weight tile | `android/app/src/main/java/com/noop/ui/TodayMetricsLogic.kt:107` | Unchanged |
| Backup whitelist | `android/app/src/main/java/com/noop/data/BackupSettings.kt:50-76` | The two keys of §9.3 were added before R43. No later key is added |
| Week and day helpers | `WeeklyDigest.kt:440`, `LocalDayWindows.kt:210`, `:308` | Used by the Kotlin twin as written |

## 5. Final names

| Thing | Name | Where |
|---|---|---|
| Pure function | `CutScorecard.evaluate(_:)` (confirmed) | `Packages/StrandAnalytics/Sources/StrandAnalytics/CutScorecard.swift` |
| Its types | `CutScorecardInput`, `CutScorecardReading`, `CutScorecardLiftObservation`, `CutScorecardProteinDay`, `CutScorecardPhase`, `CutScorecardParameters`, `CutScorecardResult` and the output types in §6 | Same file. Top-level and prefixed, as `AdaptiveExpenditureDay` and `AdaptiveExpenditureEstimate` are |
| Kotlin twin | `com.noop.analytics.CutScorecard`. Written before R43, never executed, not maintained | `android/app/src/main/java/com/noop/analytics/CutScorecard.kt` |
| Protein floor, whole grams | `CutScorecardSettings.isWholeGramProteinFloor(_:)`, `CutScorecardSettings.proteinFloorMaximumGrams`, `CutScorecardSettings.normalizedProteinFloorGrams(_:)`, `CutScorecardSettings.proteinFloorWholeGrams` (§9.2, R45) | `Strand/Data/CutScorecardSettings.swift` |
| Weigh-in outranks scan | `BodyMeasurementResolver.withoutOutrankedScans(_:asOf:)`, `BodyMeasurementResolver.weighInSource` (§8.7, R44) | `Strand/Data/BodyMeasurementResolver.swift` |
| Debug demo | `ScorecardDemo`; its names are the existing unprefixed set in that file, and any name added later takes the prefix `scorecard-` | `StrandiOS/Scorecard/ScorecardDemo.swift` |
| Scan source id, read only | `MarkerCatalog.scanSource` (`"body-scan"`), declared by stage 4 | `Packages/StrandImport/Sources/StrandImport/MarkerCatalog.swift` |
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
   `rounded()` and other languages' rounding functions disagree on halves; any port implements this
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

   The function applies this rule to the readings it is given. Which readings it is given is the
   resolver's decision: in a week that holds both a manual weigh-in and a body-scan weight row, the
   resolver's series leaves the scan row out (§8.7, ruling R44), so the week's point is the
   latest manual weigh-in. `CutScorecardReading` carries no source and the function is unchanged.
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
- **A diet break or a deload is not a phase** (ruling R46). It is a stage 5 event. The function is
  given the same active cut phase throughout it and reports as in any other week; nothing in the
  input says an event is running, and no rule, window or count pauses for it. The event's note is
  shown under the verdict by stage 5 (its `CutScorecardPresentation.eventNote`), not by this stage.
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
not add a fourth. The projection runs to the phase's `targetWeightKg` and to nothing else: a stage 6
waypoint weight never reaches this function (ruling R47). The projection reports `targetReached` and the screen leads with it (§10.2).

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
    /// `asOf` nil: every candidate. `asOf` set: candidates dated after it are left out before any
    /// rule of §8.2 runs, so a later reading can never change which earlier one is admitted.
    static func series(_ kind: BodyMeasurementKind, candidates: BodyMeasurementCandidates,
                       policy: BodyMeasurementPolicy, asOf: String? = nil) -> [DatedBodyMeasurement]
    /// The current value as of `day`. Nil only for a waist that has never been set anywhere.
    static func resolve(_ kind: BodyMeasurementKind, asOf day: String,
                        candidates: BodyMeasurementCandidates,
                        policy: BodyMeasurementPolicy) -> ResolvedBodyMeasurement?
    /// The row's value in kg or cm, or nil when its unit or value is not usable (§8.2, table).
    static func normalizedValue(of row: LabMarkerRow, as kind: BodyMeasurementKind) -> Double?

    /// R44 (§8.7). The source the weigh-in sheet and the Lab Book editor write.
    static let weighInSource = "manual"
    /// R44 (§8.7). `rows` in their given order, without each `weight` or `waist` row whose source is
    /// `MarkerCatalog.scanSource` and whose Monday week also holds a usable row of the same marker
    /// key with source `weighInSource`. Only rows dated on or before `asOf` are judged or can
    /// outrank; nil judges every row. Every other row is returned untouched.
    static func withoutOutrankedScans(_ rows: [LabMarkerRow], asOf: String? = nil) -> [LabMarkerRow]
}
```

`resolve(kind, asOf: day, …)` is `series(kind, …, asOf: day).last`, else the profile value. The
scorecard's weekly points are built from the same list: `BodyMeasurementProvider.series(_:consumer:asOf:)`
(its `asOf` also defaults to nil) forwards to the function above, and `CutScorecardInputBuilder`
passes `asOf: today`. So the scorecard's `currentWeightKg`, the Today tile and the estimates' input
are three reads of one list. Under the two legacy policies `asOf` only drops the later days, which
is what `last(where: day <= asOf)` did before the parameter existed, so their results are unchanged.
`withoutOutrankedScans` and the `asOf` parameter arrive with work package 1-11 (§8.7, §14).

### 8.2 Precedence (the `unified` policy)

The roadmap proposed "newest Lab Book reading, then Apple Health series, then the profile value".
That is **changed** to:

1. Among dated readings on or before the as-of day, **the newest day wins**, whichever source it
   came from.
2. On the same day, **Lab Book beats Apple Health**. Within Lab Book on the same day, the greatest
   `takenAt` wins, then the greatest `id`.
3. **Within one Monday week a manual weigh-in outranks a body scan** (ruling R44). Under the
   `unified` policy the Lab Book rows pass through
   `withoutOutrankedScans(candidates.labBook, asOf: asOf)` before rules 1 and 2 run. §8.7 is the
   whole of the rule: what a week, a manual row and a scan are, the function, its two callers and
   what follows from it.
4. With no dated reading, the **profile value**: source `profile` when the profile key was written,
   `profileDefault` when it never was (the weight default of 75 at `Profile.swift:125`). A waist of 0
   is "not set" and resolves to nil.

Why the change: strict source precedence would let a months-old manual reading hide a newer one from
another source, and the Apple Health page (`AppleHealthView.swift:530`) would then show a different
"latest weight" from Today. Newest-wins is also what Android's existing resolver does
(`ProfileWeightSync.kt:36`). In this build the two rules give the same answer wherever no Apple
Health weight is newer than a Lab Book one, because the Health read set excludes body mass and the
Apple series does not grow.

Candidates and exclusions:

| Store | Admitted | Notes |
|---|---|---|
| `labMarker` `weight` / `waist`, any `source` | Yes, subject to rule 3 for `body-scan` rows | Unit normalised: `kg` as is; `lb` or `lbs` divided by `UnitFormatter.poundsPerKilogram`; `cm` as is; `in` multiplied by `UnitFormatter.centimetersPerInch`; unit comparison is case-insensitive after trimming. A row with any other unit, a nil `value`, or a non-finite or non-positive value is ignored |
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
- Android's analytics, as they stand in the tree, read the profile value. A backup restored there
  would compute from the same weight. (A description of existing code; R43 orders no Android work.)
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
   deletes the Lab Book row and asserts all four move together. A third pass adds a `body-scan`
   weight row later in the same week as a manual weigh-in and asserts that none of the four moves
   (R44).

For the rule of §8.7 the same pair applies: the source scan
`test_outranking_rule_has_two_callers` (§12.4) fixes where the function may be called, and the
behavioural tests above and in §12.3 assert what the two callers produce.

### 8.7 Ruling R44: a manual weigh-in outranks a scan within its week

This section is the one specification of the rule in the workstream. The resolver is this stage's,
so the rule is a ruling on the resolver. No other specification restates it: the stage 4
specification refers here and keeps only the scan sheet's own notice and the variants and tests
that exercise the rule with scans.

A scan's total mass comes from another instrument than the bathroom scale, clothed and later in the
day. If it could stand for a week that also has a morning weigh-in, it would move the fitted rate
and could change the verdict. So:

> Within one Monday week, a usable manual row outranks every body-scan row of the same marker key
> in that week, for the weekly point, the current value, the profile mirror and the estimates. In a
> week with no usable manual row, a body-scan row is an ordinary reading.

Exactly:

- **Week** is `CutScorecard.weekStart(containing: row.day)`, the Monday rule of §7 (the step 0
  `CanonicalDay` rule is pinned to it by test). A row whose `day` is not a canonical day key belongs
  to no week: it outranks nothing and is not outranked.
- **Manual** is a row whose `source` equals `BodyMeasurementResolver.weighInSource` (`"manual"`,
  what `WeighInStore` and the Lab Book editor write). **Scan** is a row whose `source` equals
  `MarkerCatalog.scanSource` (`"body-scan"`, declared by stage 4's catalogue package). The resolver
  file imports `StrandImport` and names the scan source only through that constant; it never spells
  the literal.
- **Any other source is neither.** A row imported from a markers CSV (source `lab-csv`), an Apple
  Health value and every other source are not outranked and outrank nothing. In particular **a scan
  imported by CSV is not outranked**: it competes with a manual weigh-in by instant, under rules 1
  and 2 of §8.2, as any other reading does (S24).
- **Usable** is `normalizedValue(of: row, as: kind) != nil`. A manual row in an unknown unit, or
  with no value, does not outrank a scan.
- **Kinds.** The rule runs per marker key, for `weight` and for `waist`, the two keys the resolver
  reads. A manual weight does not outrank a scan's waist, nor the reverse. Rows of any other marker
  key pass through untouched.
- **As-of day.** Only rows dated on or before the as-of day are judged, and only such rows can
  outrank. **A row dated after the as-of day never suppresses**, and is itself returned untouched.
  So a look-back at a past day returns what was true on that day, and adding a reading later never
  changes it. With `asOf` nil every row is judged.
- **Order and identity.** The function returns the surviving rows in the order it was given them.
  It copies, changes and deletes nothing: there is still one stored number per reading (R41), and
  the scan row stays listed in the history (§10.4) and in the body record, as a dated figure.
- **Device ids.** The function looks at `markerKey`, `day`, `source`, `unit` and `value` only. Rows
  under different device ids in the given list are judged together, which is what the candidates
  hold after the Lab Book ownership change.

The function is the one in §8.1, in `Strand/Data/BodyMeasurementResolver.swift`. It has exactly two
callers, and a source scan keeps it at two (§12.4):

1. **`BodyMeasurementResolver.series`**, `unified` policy only, both kinds. The Lab Book fold
   iterates `withoutOutrankedScans(candidates.labBook, asOf: asOf)` in place of
   `candidates.labBook`, and then drops what is dated after `asOf`. `resolve`, the provider's
   snapshot, the profile mirror, the estimates' input and the scorecard's weekly points are all
   built from `series`, so they follow from one list. `BodyMeasurementProvider.series(_:consumer:asOf:)`
   only forwards the parameter, and `CutScorecardInputBuilder` passes `asOf: today`.
2. **`CutScorecardPresenter.history`**, which lists stored rows rather than the series and so needs
   the rule a second time. It gains one parameter, `today: String`, given by the model from the same
   `today` it hands the builder. The loop that marks each week's representative skips an entry whose
   weight row is not in `withoutOutrankedScans(weights, asOf: today)`. The entry is still listed,
   without the mark.

What follows, stated so that nobody finds it later:

- A scan on Wednesday and a manual weigh-in on the Monday of the same week: the current weight on
  Wednesday is Monday's weigh-in, although the scan is newer. That is the rule, not a defect.
- A scan in a week with no usable manual row is that week's point and, while it is the newest
  reading, the current weight.
- Entering a manual weigh-in later in a scan's week moves the week's point and the current value
  from the scan to the weigh-in from that day on. Looking back at a day before the weigh-in still
  returns the scan. Deleting the weigh-in moves them back.
- A scan on Sunday and a manual weigh-in on the Monday after are in different weeks; both count.
- The rule is not gated by stage 4's flag: a `body-scan` row can exist only if that flag was once
  on, and it keeps being read after the flag goes off. With `noop.cutScorecardEnabled` off the
  legacy policies never read Lab Book and the history screen is not reachable, so nothing changes.
- The pure function `CutScorecard.evaluate`, its Kotlin twin and every stored row are unchanged.

Where it is built: work package 1-11 (§14), in stage 4's serialised step, after stage 4's catalogue
package has declared `MarkerCatalog.scanSource` and before stage 4's scan writer exists. The cases
are in §13.5, the tests in §12.3 and §12.4, the faults in §12.6 (F29 to F35, F40 to F43).

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

**What a phase is, and is not** (rulings R46 and R47).

- A phase is a long block: a cut, or a stretch of some other kind that the owner wants the scorecard
  to stay silent for. A **diet break or a deload is never entered as a phase.** It is a stage 5 event
  (`personalEvents.items`, kinds `dietBreak` and `deload`; that specification owns its storage and
  its screens). Starting a phase of kind `other` for a two-week break would silence the verdict and,
  when the cut resumed as a new phase, reset the baseline of every rule (§7.2); an event does
  neither. The phase sheet says so beside the kind control (§10.5).
- `targetWeightKg` in the active phase is **the only target weight in the app.** The projection
  (§7.8), the scorecard's projection row, stage 2's packet and stage 6's timeline all read it from
  here. A phase element has no target date and no end date, and gains none. A date the owner wants
  to aim for is a stage 6 checkpoint of category `targetDate`, with no weight, attached to the
  phase by `phaseStartDay`. A stage 6 checkpoint that carries a weight (`timeline.checkpoints`,
  category `weightWaypoint`, field `waypointWeightKg`) is a **waypoint**: it is
  labelled "waypoint", never "target", it is not read by anything in this stage, and stage 6's sheet
  refuses a waypoint equal to or beyond the phase target with a link to the phase sheet of §10.5.

The settings type, as the tests use it:

```swift
struct CutScorecardStoredPhase: Equatable, Codable {
    enum Kind: String, Codable { case cut, other }
    var kind: Kind
    var name: String
    var startDay: String                 // "yyyy-MM-dd"
    var targetWeightKg: Double?          // nil: the key is omitted from the stored JSON
    var rateLowPercentPerWeek: Double
    var rateHighPercentPerWeek: Double
    init(kind: Kind, name: String, startDay: String, targetWeightKg: Double?,
         rateLowPercentPerWeek: Double, rateHighPercentPerWeek: Double)
}

final class CutScorecardSettings {
    static let enabledKey = "noop.cutScorecardEnabled"
    static let phasesKey = "cutScorecard.phases"
    static let rulesKey = "cutScorecard.rules"
    static let reminderEnabledKey = "cutScorecard.reminder.enabled"
    static let reminderWeekdayKey = "cutScorecard.reminder.weekday"
    static let reminderMinuteOfDayKey = "cutScorecard.reminder.minuteOfDay"
    static let storedVersion = 1

    init(defaults: UserDefaults = .standard)

    var isEnabled: Bool { get set }
    var reminderEnabled: Bool { get set }
    var reminderWeekday: Int { get set }
    var reminderMinuteOfDay: Int { get set }

    var phases: [CutScorecardStoredPhase] { get set }     // ascending by startDay; unreadable: []
    var phasesNeedAttention: Bool { get }
    @discardableResult func discardUnreadablePhases() -> Bool
    func activePhase(on today: String) -> CutScorecardStoredPhase?
    func evaluationPhase(on today: String) -> CutScorecardPhase?   // nil unless the active phase is a cut

    var parameters: CutScorecardParameters { get set }    // the only reader and writer of cutScorecard.rules
    var rulesNeedAttention: Bool { get }

    /// R45. The greatest floor an editor accepts, in grams.
    static let proteinFloorMaximumGrams = 100_000
    /// R45. The one rule for a floor an editor may save: finite, at least 1, at most
    /// `proteinFloorMaximumGrams`, and equal to its own rounded value.
    static func isWholeGramProteinFloor(_ grams: Double) -> Bool
    /// R45. The whole-gram form of a stored protein floor.
    static func normalizedProteinFloorGrams(_ grams: Double?) -> Double?
    /// R45. The floor as every surface prints it; nil when no floor is set.
    var proteinFloorWholeGrams: Int? { get }
}
```

`cutScorecard.rules` is an object whose keys are the property names of `CutScorecardParameters`, plus
`"v":1`. `proteinFloorGrams` is omitted when unset. A missing key takes the generic default. An
object that fails to parse, or that fails the validation in §6.5, is treated as absent and the screen
shows the "rules need attention" state rather than a verdict.

**The protein floor: one home, one rule, one printed form** (ruling R45). This is the one
specification of the rule in the workstream. The phase-and-rules sheet of §10.5 is the first editor
of the floor; stage 3's intake settings are the second, and they write the same stored value through
the same setter and add no rule of their own.

- **One home.** The floor is `proteinFloorGrams` inside `cutScorecard.rules` and nowhere else. No
  other defaults key, table or file holds a protein floor. `CutScorecardSettings.parameters` is the
  only getter and the only setter. Stage 3's intake settings read and write the floor through that
  property and store nothing of their own; stage 2's packet reads the same property.
- **One rule for what may be saved.** `isWholeGramProteinFloor(g)` is true when `g` is finite,
  `1 <= g <= 100000` and `g == g.rounded()`. Both editors call this one function (or, where a
  package cannot see it, a predicate that a test asserts equal to it over the cases of §12.3) and
  use nothing else to decide: a whole-number keypad, and an entry for which the function is false
  marks the field invalid and disables "Save". Neither editor rounds what the owner typed. An empty
  field means no floor and is saved as nil. So `100` is accepted; `99.5`, `0`, `-5` and `100001`
  are refused.
- **Stored and read whole.** `normalizedProteinFloorGrams(x)` returns nil for nil; for a finite
  `x > 0` it returns `max(1, x.rounded(.toNearestOrAwayFromZero))`; any other value (zero, negative,
  NaN, infinite) is returned unchanged, so the validation of §6.5 still rejects it and the rules
  still "need attention". The `parameters` setter applies it before writing, so the stored JSON
  number is always whole (`100`, written by the encoder as `100` or `100.0`; both read back equal)
  whichever caller wrote it. The `parameters` getter applies it after reading, so a fractional floor
  stored before this ruling reads as the nearest whole gram everywhere; the stored string is not
  rewritten by a read (R30) and becomes whole at the next save. The type stays `Double?` in
  `CutScorecardParameters`, so the pure function and its signature are unchanged.
- **No reader ever sees a fraction**, so no surface has a "needs whole grams" state and none is
  specified anywhere: a floor stored as a fraction before this ruling is, for every reader and both
  editors, the nearest whole gram. The only stored floor that an editor would refuse is one above
  the maximum, which no editor can write; a settings string holding one (a hand-edited backup) reads
  as stored, and each editor opens with the field marked until a floor in range is typed.
- **One printed form.** `proteinFloorWholeGrams` is
  `parameters.proteinFloorGrams.flatMap { Int(exactly: $0) }`: the whole number, or nil when no floor
  is set. Every surface that prints the floor prints that integer followed by `g` with no decimal
  places: the rules sheet, the scorecard's protein row, stage 2's packet line (`floor 100 g`) and
  stage 3's card, ring and widget. Because the value is whole, rounding it up, down or to nearest
  gives the same number, so no two surfaces can print different floors.

Both strings are written with sorted keys so that the same settings give the same bytes.

### 9.3 Backup whitelist

| Canonical key | JSON kind | Swift storage key | Joins the whitelist |
|---|---|---|---|
| `cutScorecard.phases` | String | `cutScorecard.phases` | **Yes** |
| `cutScorecard.rules` | String | `cutScorecard.rules` | **Yes** |
| `noop.cutScorecardEnabled` | — | — | No. A Bool cannot cross, and `noop.*` toggles are per install by the whitelist's own rule (`BackupSettings.swift:40-42`). After a restore the feature is off until switched on, which is the safe direction |
| `cutScorecard.reminder.*` | — | — | No. A reminder depends on this device's notification permission; restoring "on" would persist a switch that cannot fire, the defect `WindDownNudge.swift:128-135` documents |

Edits: `BackupSettings.whitelist` and `BackupSettings.appleDefaultsKey` (`BackupSettings.swift:49-70`,
`:75-89`). A JSON array carried as a String has a precedent in `today.hostedCards`
(`BackupSettings.swift:44-48`, `:62`). The same two keys were added to `BackupSettingsCodec.WHITELIST`
and its snapshot and apply mappings (`BackupSettings.kt:50-76`, `:143`, `:191`) before R43; that
code stores and re-exports the two strings without parsing them, and it is not edited again.

**Drift from Android (R43).** The two keys of this stage are on both whitelists. The reconciliation
adds no key and changes no stored shape: the floor inside `cutScorecard.rules` is now always a whole
number, which the Kotlin side carries untouched as part of an opaque string, and the scan rule of
§8.2 changes which stored `labMarker` row is read, not what is stored. The Kotlin `CutScorecard`
still matches the Swift pure function, which did not change. Android has no counterpart of the
resolver, so on Android a body-scan weight row is an ordinary Lab Book reading. The keys later
stages add are on the Swift whitelist only; they are listed in the fork-only comment block above
`BackupSettings.whitelist` that the shared scaffolding commit adds (§19), and the Kotlin whitelist
is knowingly behind.

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
| A diet break or deload event overlaps the judged week | The verdict is exactly what it would be without the event. Stage 5 adds one note under it (its specification, `eventNote`); with stage 5's flag off the screen is as this table says |
| A scan and a manual weigh-in in one week | The curve's point, the current weight and the rate use the manual weigh-in (§8.7) |

Curves are a line with a gradient fill, one point per week. No horizontal band for the expected rate,
no target line, no rule. The target appears as a number in the projection row, and it is always the
phase's `targetWeightKg`: a stage 6 waypoint weight is never shown on this screen.

Later stages add to this screen as the combined design frame fixes. None of them changes a row of
the table above.

### 10.3 Weigh-in sheet

Step 1, weight. Step 2, waist. One date for both.

| State | Behaviour |
|---|---|
| Step 1, first use | Empty field, focused; the unit from `units.system`; date and time default to now |
| Step 1, prior reading exists | The field is prefilled with the last weight, selected for overtyping |
| Out of range | Weight outside 30–250 kg (the range Settings and onboarding use, `SettingsView.swift:530`, `OnboardingWizard.swift:807`) or not a number: "Next" is disabled and the field says which bound |
| Backdating | The date control allows any past instant and no future one, as the Lab Book editor does (`MarkerEditorView.swift:224`). The sheet shows the week the reading will fall in |
| Already logged this week | A line: "You logged <value> on <day>. This reading will represent the week." Saving is allowed. The line is true whether the earlier reading is a manual weigh-in or a scan: a manual weigh-in outranks a scan of the same week (R44) |
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
| Rows | Date, weight, waist or "not measured", and a mark on the reading that represents its week. The mark follows the resolver: in a week with both a usable manual weigh-in and a scan it sits on the latest manual weigh-in, never on the scan (R44). The presenter decides it with `withoutOutrankedScans(weights, asOf: today)`, the function the resolver's series uses, with the same `today` the scorecard was evaluated for (§8.7), not by a second rule in the view. The outranked scan stays listed without the mark |
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
| Kind "other" | No target, no band, no rules; the scorecard shows "No cut phase is active". Beside the kind control: "For a diet break or a deload, add an event instead. The scorecard keeps reporting." The line is shown whatever the state of stage 5's flag; it links to the Events screen only while that flag is on |
| Target weight | The one target weight in the app (§9.2). Optional. No target-date field exists here |
| Protein floor left empty | Allowed; the protein signal reads "No floor set" |
| Protein floor entered | Whole grams only, from 1 to 100 000, whole-number keypad; the entry is valid exactly when `CutScorecardSettings.isWholeGramProteinFloor` is true (§9.2). "100" is accepted; "99.5", "0", "-5" and "100001" mark the field and disable "Save". The field shows the stored value as a whole number with the unit `g` |
| Protein floor stored as a fraction before R45 | The field opens showing the nearest whole gram (what every reader already sees); saving writes the whole number |

### 10.6 Settings

A toggle "Weekly weigh-in and scorecard" for the flag, with the reminder row beneath it, visible only
while the flag is on: off; on with weekday and time; and "Notifications are off for NOOP" with a link
to system settings when permission was denied (the outcome `WindDownNudge.swift:124`, `:137-175`
models).

Position: the Scorecard card is the first of the workstream's cards in Settings, top to bottom, and
is present whatever the other flags are. The combined frame set is the authority for the whole
list.

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

Position: in the Health tab's list of the workstream's rows the Scorecard row is the first, top to
bottom, present only while `noop.cutScorecardEnabled` is on. The combined frame set is the authority
for the whole list.

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
| Protein floor, wherever it is printed | "%lld g": the whole number from `proteinFloorWholeGrams`, never a decimal (R45) |
| Phase sheet, beside the kind control | "For a diet break or a deload, add an event instead. The scorecard keeps reporting." |

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

Manual weigh-in against a scan (R44, §8.7; cases in §13.5; these land with work package 1-11)

- `testManualWeighInOutranksALaterScanInTheSameWeek`
- `testManualWeighInOutranksAScanOnTheSameDayWithALaterInstant`
- `testScanAloneInAWeekIsThatWeeksReading`
- `testScanInOneWeekIsNotSuppressedByAManualWeighInInAnotherWeek`
- `testScanIsCurrentUntilAManualWeighInIsSavedInItsWeek` (`asOf` before, then on, the manual day)
- `testAManualRowAfterTheAsOfDayDoesNotSuppressAScan`
- `testSundayScanAndMondayWeighInAreInDifferentWeeksAndBothCount`
- `testCsvImportedRowNeitherSuppressesNorIsSuppressed`
- `testCsvImportedScanCompetesWithAManualWeighInByInstant` (S7b: the later instant wins either way)
- `testManualRowInAnUnknownUnitDoesNotOutrank` (S11)
- `testRowWithANonCanonicalDayIsNeitherOutrankedNorOutranking` (S12)
- `testAppleHealthValueInAScanWeekDoesNotOutrankIt` (S13)
- `testManualWaistOutranksAScanWaistInTheSameWeek`
- `testManualWeightDoesNotOutrankAScanWaist` (S14)
- `testScanRuleDoesNotApplyUnderTheLegacyPolicies`
- `testResolveEqualsLastOfSeriesForEveryAsOfDay` (generated over the §13.5 rows)
- `testAsOfNilAndAsOfAfterEveryRowGiveTheSameSeries`

The function itself, called directly:

- `testWithoutOutrankedScansKeepsOrderAndLeavesOtherMarkerKeysAlone` (S15)
- `testWithoutOutrankedScansReturnsRowsAfterTheAsOfDayUntouched` (S16)
- `testWithoutOutrankedScansJudgesRowsUnderDifferentDeviceIdsTogether`
- `testWithoutOutrankedScansOfNoRowsIsEmpty`
- `testWeighInSourceIsTheSourceTheWeighInStoreWrites` (saves through `WeighInStore` and compares the
  stored row's `source` with `BodyMeasurementResolver.weighInSource`)

`BodyMeasurementSingleSourceTests.swift` — the behavioural test in §8.6, plus
`testProfileMirrorEqualsResolverAfterSaveEditAndDelete`,
`testMirrorIsNotWrittenWhileTheFlagIsOff` and, with work package 1-11,
`testScanInAWeekWithAManualWeighInMovesNoCurrentWeightReader` and
`testProfileMirrorKeepsTheManualWeighInWhenAScanFollowsInTheSameWeek`.

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

Protein floor (R45; work package 1-10)

- `testIsWholeGramProteinFloorAcceptsWholeGramsFromOneToTheMaximumOnly` (true for 1, 100 and
  100 000; false for 0, 0.5, 99.4, 99.5, −5, 100 001, NaN and infinity)
- `testNoValueAnEditorAcceptsIsChangedByNormalisation` (for 1, 100 and 100 000, the value written
  and the value read back are the value given)
- `testNormalizedProteinFloorRoundsHalvesAwayFromZeroAndNeverBelowOne` (99.4 → 99, 99.5 → 100,
  0.2 → 1, nil → nil)
- `testNormalizedProteinFloorLeavesInvalidValuesForValidationToReject` (0, −5, NaN and infinity come
  back unchanged, and rules holding one of them still need attention)
- `testSettingAFractionalFloorStoresAWholeNumber`
- `testFractionalFloorStoredEarlierReadsWholeAndTheStoredStringIsNotRewritten` (writes the rules
  string directly with `"proteinFloorGrams":99.4`, reads 99, and asserts the stored string is
  byte-equal afterwards)
- `testProteinFloorWholeGramsIsNilWithoutAFloor`
- `testProteinFloorWholeGramsEqualsTheParameterTheScorecardIsGiven` (floor 100: the accessor is 100
  and `CutScorecardInputBuilder`'s input carries `proteinFloorGrams == 100`)
- `testCeilingFloorAndNearestOfTheStoredFloorAgree` (for stored 99.4, 99.5 and 100: `rounded(.up)`,
  `rounded(.down)` and `rounded()` of the value read are one number)

Phases (R46, R47)

- `testAStoredPhaseHasNoTargetDateOrEndDateKey` (the encoded element's keys are exactly `kind`,
  `name`, `rateHighPercentPerWeek`, `rateLowPercentPerWeek`, `startDay`, `targetWeightKg`, `v`)
- `testTargetWeightIsReadOnlyFromTheActivePhase`

`CutScorecardInputBuilderTests.swift`

- `testWarmUpAndUnperformedSetsAreExcluded`
- `testImportedAndInAppSessionsBothFeedLifts`
- `testNoSessionsYieldsEmptyLifts`
- `testProteinDaysComeFromTheNutritionSeries`
- `testWeightsComeFromTheResolverSeries`
- `testWeeklyPointIsTheManualWeighInWhenAScanSharesTheWeek` (work package 1-11)
- `testBuilderPassesTodayAsTheSeriesAsOfDay` (work package 1-11)

`CutScorecardPresenterTests.swift` — one test per row of §10.1 and §10.2, named for the state, each
asserting the presentation built from a fixture result; plus `testNoStateRendersAMissingValueAsZero`
and `testNoStringContainsAnInterpolatedNilOrNaN`. With work package 1-10:
`testRulesSheetAcceptsAWholeProteinFloor`, `testRulesSheetRefusesAFractionalProteinFloor`,
`testRulesSheetRefusesAZeroOrNegativeProteinFloor`, `testRulesSheetShowsTheFloorAsAWholeNumber`,
`testProteinRowPrintsTheFloorWithoutADecimal`, `testPhaseSheetOtherKindPointsToEvents` and
`testProjectionRowTargetIsThePhaseTarget` and `testRulesSheetRefusesAProteinFloorAboveTheMaximum`.
With work package 1-11: `testHistoryMarksTheManualWeighInNotTheScanAsRepresentingTheWeek`,
`testHistoryStillListsTheOutrankedScanWithoutTheMark`,
`testHistoryMarksTheScanInAWeekWithNoManualWeighIn` and
`testHistoryIgnoresAManualRowDatedAfterTodayWhenMarking`. The rules-sheet tests drive the
sheet's draft through the same entry point the view uses for typed text (a typed string in, the
field's validity and the saved `parameters.proteinFloorGrams` out) and assert on those two outputs
only.

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
- `test_scorecard_backup_keys_match_on_both_platforms` (reads the two whitelist files as text and
  compares only the two keys this stage adds, because of C10. It compiles and runs nothing on the
  Kotlin side, so it stays valid under R43; it is not extended to any later key)
- `test_protein_floor_has_one_stored_home` (work package 1-10): outside
  `Strand/Data/CutScorecardSettings.swift`, no file under `Strand/`, `StrandiOS/`, `StrandiOSShared/`
  or `StrandiOSWidgets/` contains a string literal with `proteinFloor` in it, so no second defaults
  key or JSON field for the floor can appear. Stage 3 states the same check from its side
  (`test_protein_floor_is_stored_only_in_scorecard_rules`); the two are kept, one per suite

- `test_outranking_rule_has_two_callers` (work package 1-11): under `Strand/`, `StrandiOS/`,
  `StrandiOSShared/`, `StrandiOSWidgets/` and the watch targets, `withoutOutrankedScans(` occurs
  only in `Strand/Data/BodyMeasurementResolver.swift` (its declaration and one call, inside
  `series`) and once in `Strand/Data/CutScorecardPresenter.swift`; and neither of those two files
  contains the string literal `"body-scan"`. A third caller, or the literal spelled beside the
  constant, fails the test, and its message says that §8.7 of this specification is the rule's one
  home

The behavioural tests of §8.6 stay the stronger check for the scan rule (R44): every current-weight
reader keeps the manual weigh-in when a scan follows it.

### 12.5 Flag-off equivalence

With the flag off, the baseline suite's results are unchanged: `renderList` keeps its existing call
shape through a defaulted parameter, the legacy policies return the old values, the card is absent
from the editor, no notification request exists, and no `labMarker` row or profile value is written.
The scan rule (R44) runs only under the `unified` policy, and the whole-gram floor (R45) changes no
read while no floor is stored.
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
| F29 | Scan rule removed (the scan is admitted beside a manual weigh-in) | `testManualWeighInOutranksALaterScanInTheSameWeek` |
| F30 | Scan rule applied per day, not per Monday week | `testManualWeighInOutranksALaterScanInTheSameWeek`, `testSundayScanAndMondayWeighInAreInDifferentWeeksAndBothCount` |
| F31 | Scan rows dropped even with no manual weigh-in in the week | `testScanAloneInAWeekIsThatWeeksReading` |
| F32 | Rows after the as-of day allowed to suppress | `testAManualRowAfterTheAsOfDayDoesNotSuppressAScan` |
| F33 | Any non-scan source allowed to suppress a scan | `testCsvImportedRowNeitherSuppressesNorIsSuppressed` |
| F34 | Scan rule applied under a legacy policy | `testScanRuleDoesNotApplyUnderTheLegacyPolicies` |
| F35 | Builder calls `series` without `asOf` | `testBuilderPassesTodayAsTheSeriesAsOfDay` |
| F40 | A manual row in an unknown unit allowed to outrank | `testManualRowInAnUnknownUnitDoesNotOutrank` |
| F41 | The rule applied across marker keys (a manual weight outranks a scan waist), or to weight only | `testManualWeightDoesNotOutrankAScanWaist`, `testManualWaistOutranksAScanWaistInTheSameWeek` |
| F42 | The history marks its week without calling the function | `testHistoryMarksTheManualWeighInNotTheScanAsRepresentingTheWeek` |
| F43 | A third caller of the function added, or the scan source spelled as a literal | `test_outranking_rule_has_two_callers` |
| F36 | Floor not normalised on write | `testSettingAFractionalFloorStoresAWholeNumber` |
| F37 | Floor not normalised on read, or the read rewrites the stored string | `testFractionalFloorStoredEarlierReadsWholeAndTheStoredStringIsNotRewritten` |
| F38 | Rules sheet rounds a typed fraction and saves it | `testRulesSheetRefusesAFractionalProteinFloor` |
| F39 | Floor printed with decimals | `testProteinRowPrintsTheFloorWithoutADecimal`, `testRulesSheetShowsTheFloorAsAWholeNumber` |
| F44 | The editor rule's upper bound removed, or its whole-number test dropped | `testIsWholeGramProteinFloorAcceptsWholeGramsFromOneToTheMaximumOnly`, `testRulesSheetRefusesAProteinFloorAboveTheMaximum` |

### 12.7 Parity

**Status under R43.** Android work is stopped. Items 1, 3, 4 and 6 below record how the Kotlin
files that are in the tree were produced; they are not instructions, and nobody writes, compiles or
runs Kotlin for this stage again. Item 2 is a Swift test and stays in force: it is what stops the
Swift function drifting from the recorded oracle output. The gate script's Android rows are waived
by flag and reported as waived. The reconciliation changes (R44 to R48) touch no file with a Kotlin
twin: the pure function is unchanged, so the oracle literal is unchanged and is not regenerated.

Layout follows `android/app/src/test/java/com/noop/analytics/LiftMetricsParityOracleTest.kt:1-80`.

1. **Swift to Kotlin (done before R43).** Compile `CutScorecard.swift` with `WeeklyDigest.swift` and a `main.swift`
   standalone (`swiftc -O`). `main.swift` evaluates the fixture at each of its 22 days, every variant
   in §13.4, and a generated spread: a fixed-seed linear congruential generator written out in the
   file (not a library generator, which differs by platform) producing at least 500 inputs that vary
   reading counts, gaps, values, lift coverage and every parameter. It prints one block per
   evaluation: every field of the result in declaration order, Doubles as `%.6f`, nil as `nil`,
   enums as raw values. That standard output was pasted verbatim as the expected literal in
   `android/app/src/test/java/com/noop/analytics/CutScorecardParityOracleTest.kt`, which builds the
   same inputs with the same generator and prints through the same format.
2. **Kotlin to Swift.** `Packages/StrandAnalytics/Tests/StrandAnalyticsTests/CutScorecardOracleTests.swift`
   holds the same literal and asserts the Swift output against it, so a later change on the Swift
   side fails on the Swift side.
3. Named edges the spread includes, since they are where a port diverges: `quantize` on exact
   halves and on negatives; a `ceil` on a value that is an integer but for floating-point error;
   the tie order in "latest reading of the week"; integer division of negative week differences;
   exercise names that differ only by case or trailing space; day keys before 1970.
4. `android/app/src/test/java/com/noop/analytics/CutScorecardTest.kt` mirrors the named cases of
   §12.1.
5. The Kotlin twin and its tests are **written, never run** (R43), and every report says so. They
   are not counted as passing anywhere.
6. The two backup keys are checked by `test_scorecard_backup_keys_match_on_both_platforms`, which
   reads source text only. `BackupSettingsCodecTest.kt` holds the Kotlin-side case as written and
   is not run.
7. **Written disposition for the resolver.** `BodyMeasurementResolver` has no Kotlin twin. It is
   app-layer selection among platform-specific sources, Android has no scorecard surface in this
   workstream, and it produces no new stored shape: its only writes are `labMarker` rows and the
   existing `profile.weightKg` and `profile.waistCm` keys. Android keeps `ProfileWeightSync`.
8. **Written disposition for R44 and R45.** Neither has a Kotlin counterpart and neither needs one
   under R43. R44 is a rule of the resolver of item 7. R45 lives in `CutScorecardSettings`, an
   app-layer type with no twin; the stored key and its JSON kind are unchanged. The drift is stated
   in §9.3.

### 12.8 Simulator and rehearsal

As in the roadmap: every frame reproduced from the fixture at default and largest text size, Reduce
Motion on and off, with enter, edit, delete and backdate exercised by tapping; then the private
real-data rehearsal from 0B-7, whose results stay out of the repository.

## 13. Fixture

Everything here is invented. "Fixture Person" does not exist; the numbers are round on purpose.

**This is the one Fixture Person for every stage** (ruling R48). Demo screens, simulator seeds and
app-target fixtures of stages 2 to 6 and of the Lab Book ownership change use this person: the phase
of §13.1, weigh-ins on Wednesdays from 2031-01-08 with the weights and waists of §13.3 (100.0 kg and
100.0 cm in week 1, 93.5 kg and 93.5 cm in week 22), week 10 missed, the lift table and protein days
of §13.2, and a protein floor of 100 g. A fixture in another stage that needs a body weight on a day
takes the weight this table gives for that day's week (a scan in week 4 has a total mass of 97.6 kg,
not some other person's), and one that needs a floor takes 100 g. A pure-logic golden in another
stage may keep its own values when it is never shown beside these. Where R31 forces dates relative
to the real clock, the series keeps its weekday and its week numbers and is shifted by whole weeks.

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

### 13.5 Resolver cases for a scan beside a manual weigh-in (R44, §8.7)

Lab Book `weight` rows in kg unless stated, all under one device id, `unified` policy, no Apple
Health values, profile weight 75 and set. "manual" is source `manual`; "scan" is source
`MarkerCatalog.scanSource`. Times are UTC and the stored `day` is as given. Each case starts from the
fixture's manual weigh-ins of weeks 1 to 4 (100.0, 99.2, 98.4 and 97.6 kg on 2031-01-08, -15, -22
and -29 at 07:00) and adds the rows listed. The added values differ from the week's weigh-in on
purpose, so that a test can tell which row was chosen; they are resolver test rows, not demo data
(a demo scan takes the week's own weight, §13).

| Case | Added rows | Expected |
|---|---|---|
| S1 | scan 98.0 on Thursday 2031-01-30 at 12:00 | `series` holds no entry for 2031-01-30. `resolve(asOf: 2031-01-30)` and `resolve(asOf: 2031-02-02)` are 97.6, source `labBook`, day 2031-01-29. The scorecard's week 4 point is 97.6 |
| S2 | scan 98.0 on Wednesday 2031-01-29 at 12:00 (same day as the manual row, later instant) | The entry for 2031-01-29 is 97.6 with the manual row's `rowId` |
| S3 | scan 97.0 on Wednesday 2031-02-05 at 12:00; no manual row in week 5 | The entry for 2031-02-05 is 97.0. `resolve(asOf: 2031-02-05)` is 97.0, day 2031-02-05. Week 5's point is 97.0 |
| S4 | as S3, then manual 97.5 on Friday 2031-02-07 at 07:00 | `resolve(asOf: 2031-02-05)` and `resolve(asOf: 2031-02-06)` are 97.0 (the scan). `resolve(asOf: 2031-02-07)` is 97.5, and `series(asOf: 2031-02-07)` holds no entry for 2031-02-05. Week 5's point evaluated with `today` 2031-02-07 is 97.5 |
| S5 | scan 97.0 on Sunday 2031-02-02 at 12:00 (week 4); manual 97.5 on Monday 2031-02-03 at 07:00 (week 5) | Week 4 holds a manual row (2031-01-29), so the Sunday scan is left out. `resolve(asOf: 2031-02-02)` is 97.6; `resolve(asOf: 2031-02-03)` is 97.5 |
| S6 | as S5 with the week 4 manual row removed | The Sunday scan is week 4's reading (97.0) and the Monday row is week 5's (97.5); both are in `series` |
| S7 | a row with source `lab-csv`, 98.0 on Thursday 2031-01-30 at 12:00 | Not a scan for this rule: the entry for 2031-01-30 is 98.0 and `resolve(asOf: 2031-01-30)` is 98.0 |
| S7b | a row with source `lab-csv`, 98.0 on Wednesday 2031-01-29 at 12:00 (same day as the manual row, later instant); then the same row at 06:00 | A scan imported by CSV is not outranked and competes by instant: at 12:00 the entry for 2031-01-29 is 98.0; at 06:00 it is 97.6 |
| S8 | scan 98.0 on Thursday 2031-01-30 at 12:00 and a `lab-csv` row 97.9 on Friday 2031-01-31 at 12:00 | The scan is left out (week 4 has a manual row); the CSV row stays. `resolve(asOf: 2031-01-31)` is 97.9 |
| S9 | waist rows: manual 98.5 cm on 2031-01-29 at 07:00, scan 99.0 cm on 2031-01-30 at 12:00 | Waist `resolve(asOf: 2031-01-30)` is 98.5 |
| S10 | S1's rows under `legacyDisplay` and `legacyEstimate` | Unchanged from before R44: Lab Book is not consulted |
| S11 | week 5 only: manual row 15.3 in the unit `stone` on Monday 2031-02-03 at 07:00; scan 97.0 on Wednesday 2031-02-05 at 12:00 | The manual row is not usable, so it does not outrank: the entry for 2031-02-05 is 97.0 and `resolve(asOf: 2031-02-05)` is 97.0 |
| S12 | scan 98.0 with the stored `day` `2031-1-30` (not a canonical key) at 12:00 on that date | The row belongs to no week and is returned by the function untouched. What `series` then does with a non-canonical day is unchanged by R44 |
| S13 | week 5 only: an Apple Health weight 97.4 on Monday 2031-02-03; scan 97.0 on Wednesday 2031-02-05 at 12:00 | The Apple Health value is not a manual weigh-in: both are in `series`, and `resolve(asOf: 2031-02-05)` is 97.0 |
| S14 | S1's rows, plus a scan waist row 99.0 cm on Thursday 2031-01-30 at 12:00 and no manual waist row in week 4 | The scan weight is left out (97.6 stands); the scan waist stays: waist `resolve(asOf: 2031-01-30)` is 99.0 |
| S15 | the function called on, in this order: the S1 scan, a `body_fat` row with source `MarkerCatalog.scanSource` on 2031-01-30, the week 4 manual row | Returns the `body_fat` row then the manual row, in that order; the `body_fat` row is untouched |
| S16 | the function called with `asOf: 2031-02-05` on S4's rows | Returns all of them, the scan included and the Friday manual row included: the Friday row is after the as-of day, so it neither outranks nor is removed |

## 14. Work packages and file ownership

Android: ruling R43 (§18) stops all Android work. Work package 1-5 is closed as it stands; nothing
below orders a Kotlin change.

A package edits only the files listed for it. WP 1-8 is the sole writer of the String Catalog.

| WP | Role | Files |
|---|---|---|
| 1-3 | Test author | `Packages/StrandAnalytics/Tests/StrandAnalyticsTests/CutScorecardTests.swift`, `.../CutScorecardFixture.swift`; `Packages/WhoopStore/Tests/WhoopStoreTests/WeighInLabMarkerTests.swift`; additions to `Packages/WhoopStore/Tests/WhoopStoreTests/BackupSettingsTests.swift`; `StrandTests/BodyMeasurementResolverTests.swift`, `BodyMeasurementSingleSourceTests.swift`, `WeighInStoreTests.swift`, `CutScorecardSettingsTests.swift`, `CutScorecardInputBuilderTests.swift`, `CutScorecardPresenterTests.swift`, `WeighInReminderTests.swift`; additions to `StrandTests/TodayCardResolverTests.swift`; `Tools/test_body_measurement_single_resolver.py` |
| 1-4 | Implementer A | `Packages/StrandAnalytics/Sources/StrandAnalytics/CutScorecard.swift` |
| 1-5 | Parity agent. **Closed (R43)**: done before the ruling, never executed, no further work | `android/app/src/main/java/com/noop/analytics/CutScorecard.kt`; `android/app/src/test/java/com/noop/analytics/CutScorecardTest.kt`, `CutScorecardParityOracleTest.kt`; `Packages/StrandAnalytics/Tests/StrandAnalyticsTests/CutScorecardOracleTests.swift`; `android/app/src/main/java/com/noop/data/BackupSettings.kt`; `android/app/src/test/java/com/noop/data/BackupSettingsCodecTest.kt`. The oracle `main.swift` is scratch and is not committed |
| 1-6 | Implementer B | New: `Strand/Data/BodyMeasurementResolver.swift`, `BodyMeasurementProvider.swift`, `WeighInStore.swift`, `CutScorecardSettings.swift`, `CutScorecardInputBuilder.swift`. Edited, reader migration only: `Strand/Data/IntelligenceEngine.swift`, `Strand/App/AppModel.swift`, `Strand/Screens/HealthView.swift`, `Strand/Screens/TestCentreView.swift`, `Strand/Liquid/LiquidTodayView.swift`, `Strand/Screens/TodayView.swift`, `StrandiOS/Redesign/RedesignTodayView.swift` (the weight row only), `Packages/WhoopStore/Sources/WhoopStore/BackupSettings.swift` |
| 1-7 | Implementer C, after G1 and after 1-4 and 1-6 merge | New: `Strand/Data/CutScorecardModel.swift`, `CutScorecardPresenter.swift`; `StrandiOS/Scorecard/ScorecardView.swift`, `WeighInSheet.swift`, `WeighInHistoryView.swift`, `ScorecardPhaseSheet.swift`. Edited: `Strand/Screens/DashboardCards.swift`, `Strand/Data/TodayCardReadout.swift`, `Strand/Screens/TodayCustomizationMetadata.swift`, `Strand/Screens/TodayCustomizationSheet.swift`, `Strand/Data/TodayCardsEditorPresentation.swift`, `StrandiOS/Redesign/YourCardsSection.swift`, `StrandiOS/Redesign/RedesignRoute.swift`, `StrandiOS/Redesign/RedesignTodayView.swift` (card inputs), `StrandiOS/Redesign/RedesignHealthView.swift` (the Health row), `Strand/Screens/SettingsView.swift` (flag toggle and body-metrics rows); `Strand/Screens/TodayView.swift` and `Strand/Liquid/LiquidTodayView.swift` only to make their `DashboardCard` switches exhaustive and to filter the new case out |
| 1-8 | Localiser | `Strand/Resources/Localizable.xcstrings` |
| 1-9 | Implementer C | `Strand/System/WeighInReminder.swift`; the reminder row in `Strand/Screens/SettingsView.swift` |
| 1-10 | Reconciliation, protein floor and phase wording (R45, R46, R47). Test author first, then one implementer; runs in the serialised step "stage 1 follow-up", after the Lab Book ownership change has merged and before stage 2 | Tests: additions to `StrandTests/CutScorecardSettingsTests.swift`, `CutScorecardInputBuilderTests.swift`, `CutScorecardPresenterTests.swift`; `test_protein_floor_has_one_stored_home` in `Tools/test_body_measurement_single_resolver.py`. Source: `Strand/Data/CutScorecardSettings.swift` (the four new members of §9.2, normalisation in the `parameters` getter and setter); `Strand/Data/CutScorecardModel.swift` and `Strand/Data/CutScorecardPresenter.swift` (the "Daily floor" field becomes a whole-number field validated by `isWholeGramProteinFloor`, and its printed form; the projection row and protein row read as §10 says); `StrandiOS/Scorecard/ScorecardPhaseSheet.swift` (the line beside the kind control). Then the Localiser adds the one new string to `Strand/Resources/Localizable.xcstrings` |
| 1-11 | Reconciliation, manual weigh-in outranks a scan (R44, §8.7). Test author first, then one implementer; runs inside stage 4's serialised step, after stage 4's catalogue package has declared `MarkerCatalog.scanSource` and before stage 4's scan writer and before any stage 4 edit of the files listed here | Tests: additions to `StrandTests/BodyMeasurementResolverTests.swift`, `BodyMeasurementSingleSourceTests.swift`, `CutScorecardInputBuilderTests.swift`, `CutScorecardPresenterTests.swift`; `test_outranking_rule_has_two_callers` in `Tools/test_body_measurement_single_resolver.py`. Source: `Strand/Data/BodyMeasurementResolver.swift` (`weighInSource`, `withoutOutrankedScans(_:asOf:)`, the `asOf` parameter of `series`, the call inside `series`, `import StrandImport`), `Strand/Data/BodyMeasurementProvider.swift` (`series(_:consumer:asOf:)` forwarding only), `Strand/Data/CutScorecardInputBuilder.swift` (passes `asOf: today`), `Strand/Data/CutScorecardPresenter.swift` (`history` gains `today:` and its week mark calls the function), `Strand/Data/CutScorecardModel.swift` (passes `today` to `history`, one argument). No string changes |

Shared-file order: `LiquidTodayView.swift`, `TodayView.swift` and `RedesignTodayView.swift` are edited
by 1-6 and then by 1-7, in that order, never in parallel. `SettingsView.swift` is edited by 1-7 and
then 1-9. `Packages/WhoopStore/.../BackupSettingsTests.swift` and
`Packages/StrandAnalytics/Tests/` receive files from 1-3 and from 1-5; they add separate files or
separate test methods and do not edit each other's.

**Hotspot table: this stage's position on each shared file.** The one order for every shared file
is Lab Book ownership, stage 2, stage 3, stage 4, stage 5, stage 6, then packet v2. This stage's
original packages (1-3 to 1-9) are merged before any of them. Its two follow-up packages sit in
that order as follows, and the table says nothing about what any other stage does to a file.

| File | Stage 1 package | Position |
|---|---|---|
| The nine Today files (`Strand/Screens/DashboardCards.swift`, `Strand/Data/TodayCardReadout.swift`, `TodayCustomizationMetadata.swift`, `TodayCustomizationSheet.swift`, `TodayCardsEditorPresentation.swift`, `YourCardsSection.swift`, `RedesignTodayView.swift`, `TodayView.swift`, `LiquidTodayView.swift`) | 1-6, 1-7 and the R40 follow-up | Complete and merged before Lab Book ownership. Not edited by 1-10 or 1-11 |
| `Strand/Data/CutScorecardSettings.swift` | 1-10 | After Lab Book ownership, before stage 2 |
| `StrandiOS/Scorecard/ScorecardPhaseSheet.swift` | 1-10 | After Lab Book ownership, before stage 2 |
| `Strand/Data/CutScorecardModel.swift` | 1-10, then 1-11 | 1-10 after Lab Book ownership and before stage 2. 1-11 after stage 3 and before stage 4's own edits (one argument) |
| `Strand/Data/CutScorecardPresenter.swift` | 1-10, then 1-11 | 1-10 after Lab Book ownership and before stage 2. 1-11 after stage 3, first in stage 4's step, before stage 4's own edit of the file |
| `Strand/Data/CutScorecardInputBuilder.swift` | 1-11 | After stage 3, first in stage 4's step. 1-10 does not edit it |
| `Strand/Data/BodyMeasurementResolver.swift` | 1-11 | After stage 3, in stage 4's step after its catalogue package. This stage is the file's only editor |
| `Strand/Data/BodyMeasurementProvider.swift` | 1-11 | After Lab Book ownership's edits, in stage 4's step: the one forwarding parameter |
| `Strand/Data/WeighInStore.swift` | none | Not edited by 1-10 or 1-11 |
| `StrandTests/CutScorecardInputBuilderTests.swift`, `CutScorecardPresenterTests.swift` | 1-10, then 1-11 | New test methods only, at the same two positions as the source files |
| `Tools/test_body_measurement_single_resolver.py` | 1-10, then 1-11 | One new test function each, at the same two positions |
| `Strand/Resources/Localizable.xcstrings` | 1-10's Localiser pass | One writer at any moment: after Lab Book ownership's Localiser, before stage 2's. 1-11 adds no string |
| `StrandiOS/App/StrandiOSApp.swift` (debug demo registry) | none | The orchestrator's step 0 adds the registry with this stage's element, `ScorecardDemo.screen(named:)`. Neither follow-up package edits the file |
| `StrandiOS/Scorecard/ScorecardDemo.swift` | none | This stage's demo file. Not edited by 1-10 or 1-11, and by no other stage |
| `StrandiOS/Scorecard/ScorecardView.swift` | none | Not edited by 1-10 or 1-11 |
| `Strand/Screens/SettingsView.swift`, `StrandiOS/Redesign/RedesignHealthView.swift` | none | This stage's card and row are merged and are first in the list of §10.6 and §10.9. Not edited by 1-10 or 1-11 |
| `Strand/AI/AICoach.swift` | none | This stage does not edit it, in any package |
| `Packages/WhoopStore/Sources/WhoopStore/BackupSettings.swift` | none | This stage's two keys are merged. Not edited by 1-10 or 1-11 |

Each follow-up package is written against the file as it stands at its position. In particular,
after stage 2 the evaluation funnel has moved inside `CutScorecardInputBuilder`, and 1-11's builder
test and its `asOf: today` argument use whichever name is in the tree at its step.

`project.yml` needs no change: `Strand`, `StrandiOS` and `StrandTests` are included by directory
(`project.yml:87-91`, `:220-244`, `:170`). Run `xcodegen generate` after adding files.

Existing tests that the new enum case or parameter can touch, for the Test author to check before
G2: `StrandTests/TodayCardsEditorTests.swift:43` (asserts the shortcut cards; the new card is not a
shortcut), `StrandTests/TodayCardResolverTests.swift:37-41` (calls `renderList`; unaffected by a
defaulted parameter), `Tools/test_home_i18n.py:96-100` (pins Android card ids; Android gains none).

Parity governance: new public declarations in `Packages/StrandAnalytics` are inventoried by
`Tools/parity_ledger.py`. Each carries a twin claim in the existing form ("Kotlin twin: `CutScorecard`."
on the type, "The Kotlin twin is `CutScorecard.evaluate`." on a function). Whether the ledger can be
refreshed at all is the open item of 0B-9; this stage does not attempt it. Work packages 1-10 and
1-11 add no public declaration to a package, so they add nothing to the ledger; under R43 their
pull requests carry the written disposition of §12.7 item 8 and the Kotlin lines of the parity
ratchet stay as recorded debt.

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
| S14 | Should phases and rules be included in backups? | Yes, as two string keys. The flag and the reminder are not. (Both keys also reached the Kotlin whitelist before R43; nothing further is done there) |
| S15 | Stage 1 supports cut phases only. Is "no verdict outside a cut" acceptable until a later stage? | Yes |
| S16 | Which protein source feeds the protein signal before stage 3? | The existing nutrition CSV series if present; otherwise the signal is "no protein data". The signal never affects the verdict |
| S17 | Lab Book reads only the active strap id. After a strap is removed and added again the active id changes, and readings saved under the earlier id are no longer listed (`LabBookView.swift:468`, `MarkerEditorView.swift:431`, `Repository.swift:144-158`, `AppModel.swift:693-700`). The rows stay in the database unless the owner chose to delete that device's data; adopting a serial identity does move them (`DeviceRegistryStore.swift:162-173`, `:263-268`). Confirmed by reading on 10 November 2026, not by a test. How should weigh-ins behave? | Write under the active id as Lab Book does, and have the weigh-in store and the resolver read weight and waist rows across the same ids the repository already unions for imported history (active strap first, then the canonical id and other registered straps), de-duplicated by marker, instant and source, with a test that re-points the id and still sees every reading. Fix Lab Book's own listing in a separate pull request. Work package 1-6 waits for the owner's answer, because this concerns existing data |
| S18 | Review, 10 November 2026: a strap's "Delete data" or "Forget" deletes every row stored under that strap id, Lab Book readings included (`DeviceRegistryStore.swift:162-173`). Because weigh-ins are written under the active strap id (R25), deleting an old strap's data would delete the weigh-ins logged while it was active. This is existing, deliberate behaviour for Lab Book. Should weigh-ins be exempt? | Keep R25 for stage 1 and state the consequence on the delete confirmation in the separate Lab Book change. The alternative is to store weigh-ins under the canonical id, which Lab Book does not read, so the two screens would list different rows |
| S19 | Review, 10 November 2026: when the flag is switched on, the profile mirror replaces the Settings weight with the newest dated reading however old it is (§8.2 has no age limit), and switching the flag off does not restore the earlier Settings value. | Accept: it is the specified meaning of "newest dated reading wins", and a first weigh-in supersedes any old reading. The alternative is an age limit on dated readings |
| S20 | Cross-stage check X10, **decided by default** on its recommendation. Stage 6 lets a timeline checkpoint carry a weight. Is that a second target? | No. The one target weight stays in the active phase and is the only weight the scorecard projects to (R47). A checkpoint weight is a waypoint, labelled so, and stage 6 refuses one equal to or beyond the phase target. A dated target is a checkpoint with no weight. **If the owner says otherwise** (a dated target the scorecard should project to): the phase element gains a target day, which is a change to the stored `cutScorecard.phases` shape, to §7.8 and to the pure function, with its own specification |
| S21 | Cross-stage check X11, **decided by default** on its recommendation. When a week has both a manual weigh-in and a body scan, which does the scorecard judge? | The manual weigh-in, in that week only; a scan alone in a week is used (R44, §8.7). One stored number per reading still (R41). **If the owner says otherwise** (the later instant wins, the scan included): §8.7, rule 3 of §8.2, `withoutOutrankedScans` and its two call sites, `test_outranking_rule_has_two_callers`, the §13.5 cases, faults F29 to F35 and F40 to F43, and work package 1-11 are dropped; the stage 4 specification then drops its notice on the scan sheet; nothing else in this document changes |
| S22 | Cross-stage check X14, **decided by default** on its recommendation. Is a diet break or a deload a phase or an event? | An event (stage 5). Phases are only the long blocks. The scorecard keeps giving its verdict during the event and stage 5 shows the event's note under it (R46). **If the owner says otherwise** (the scorecard should be silent during a break): that is a new input to the pure function saying an event is running and a new verdict reason, specified separately; entering the break as a phase of kind `other` would also reset every rule's baseline when the cut resumes, which is why it is not the recommended route |
| S23 | Cross-stage check X12, binding on the stages and reported here because it limits what can be typed. The protein floor is whole grams. | In force (R45). A fractional floor cannot be entered, nor one above 100 000 g; one stored earlier as a fraction reads as the nearest whole gram. **If the owner wants a fractional floor**: every surface must then agree on one rounding for display, which is a change in stages 1, 2 and 3 together |
| S24 | Raised by this reconciliation. A scan imported from a markers CSV carries the source `lab-csv` (stage 4), not `body-scan`, so the rule of §8.7 does not treat it as a scan: it is not outranked, and within a week it competes with a manual weigh-in by instant, as any other reading does. Settled for this pass by the orchestrator's ruling (§19, second pass); the owner may still say otherwise. | Leave it so. The rule is keyed on the one source id a scan sheet writes; widening it to imported rows needs stage 4's scan identity inside the resolver. **If the owner says otherwise**: the resolver asks stage 4's scan grouping which `weight` rows are scans, and S7 in §13.5 changes |

## 16. Not determined

- **Whether a cached `DateFormatter` follows a change of device time zone.** `LabBookFormat.dayKey`
  uses a static formatter with no explicit zone (`LabBookView.swift:565-571`). Whether its zone
  updates after the device changes zone while the app is running was not established by reading.
  The weigh-in path avoids the question by passing the zone explicitly (§9.1), and
  `testDayKeyAgreesWithLabBookFormat` records the agreement for the current zone only.
- **Which units existing Lab Book weight or waist rows carry on a given install.** The resolver
  handles `kg`, `lb`, `cm` and `in`; a row in any other unit is left out and counted (§10.4).
- **Readings and a changed strap id.** Lab Book rows are stored under `repo.deviceId`, which is
  re-pointed when a strap is removed and added again (`Repository.swift:131-138`, `:261`). Rows saved
  under the earlier id are then not returned by `labMarkers(deviceId:markerKey:)`. This is existing
  Lab Book behaviour, it would apply to weigh-ins equally, and it was not tested. It needs the
  owner's decision before G8: fix Lab Book and the scorecard together in a separate pull request, or
  accept it. Since decided: rulings R25, R29 and R42, and the Lab Book ownership specification.
- **The size of the re-estimation window** that a changed weight triggers in the scoring pass (§8.4).
  The mechanism was read; the number of days was not traced.
- **Parity ledger state.** Whether new `StrandAnalytics` declarations can be registered depends on
  0B-9. The claim syntax in §14 follows the existing files and was not run through the ledger.
- **The pre-existing whitelist difference** (C10) was observed in the two source files. Whether it is
  known upstream was not checked.
- **Android.** Nothing on the Kotlin side was compiled or run, and under R43 nothing will be.
- **Whether `MarkerCatalog.scanSource` is the only source a scan sheet writes** is stage 4's
  statement, taken as given for §8.7. See S24 for the imported case.
- **The rules sheet's typed-text entry point.** §12.3 describes the rules-sheet tests by their two
  outputs. The name of the draft function a typed string goes through is the implementation's
  (`CutScorecardModel.swift`, `CutScorecardPresenter.swift`) and was read, not specified, here.
- **Row values in §13.3** come from a scratch model, as stated there.

## 17. Design approval record (G1)

**Approved to proceed by the owner on 10 November 2026**, in the conversation, after the frames were
imported to the Figma page "Round 6 · Scorecard (Stage 1)" (61 frames, from
`design/round6-scorecard/`, commit `72189fed`). The owner's words: the basics look right, go ahead
with implementation, and details will be edited in flight afterwards. This is approval of the
direction and the frame set, not a sign-off of every string; wording and details remain open to the
owner's changes, which are made in the HTML source first and re-imported.

The owner did not choose between the options offered, so the recommendations stand until changed:

| Decision | In force |
|---|---|
| Placement | P1: a Today card outside the default card selection, plus a row in the Health tab (frames P1.1 to P1.4) |
| Lift signal unknown | As drawn in B14, B15 and B16: the verdict names the rule it could not check |
| Signal colours | Met: Recovery green. Not met: Recovery mid amber. Unknown: neutral grey, dashed ring. Red for Delete only |
| Wording | The §11 strings and the designer's proposals in the round 6 README, as drawn |
| Reminder | Title "Weekly weigh-in", body "Weight, then waist. It takes under a minute." Off by default |

| Frames | Page | Approved on |
|---|---|---|
| A1 to A4 (entry card) | Round 6 · Scorecard (Stage 1) | 10 November 2026 |
| B1 to B27 (scorecard) | Round 6 · Scorecard (Stage 1) | 10 November 2026 |
| C1 to C10 (weigh-in sheet) | Round 6 · Scorecard (Stage 1) | 10 November 2026 |
| D1 to D5 (history) | Round 6 · Scorecard (Stage 1) | 10 November 2026 |
| E1 to E4 (phase and rules) | Round 6 · Scorecard (Stage 1) | 10 November 2026 |
| F1 to F4 (settings and reminder) | Round 6 · Scorecard (Stage 1) | 10 November 2026 |
| P1.1 to P1.4 (placement in force); P2, P3 not built | Round 6 · Scorecard (Stage 1) | 10 November 2026 |

Not verified at approval: which font the import used, and how each frame rendered in Figma (the
session could not see the Figma window).

## 18. Rulings after independent tests and implementation (10 November 2026)

The tests (WP 1-3) and the implementation (WP 1-4) were written by separate agents from §6 and §7.
Where they found this document ambiguous or self-contradictory, the orchestrator ruled as below.
These rulings are binding on the tests, the Swift implementation and the Kotlin twin, and they
override the earlier section they name. Since R43 the Kotlin twin is frozen as written: where a
ruling from R1 to R24 says what the twin does, it describes that file and orders no further work.
Rulings R44 to R48 were added on 11 November 2026 from the cross-stage check (§19).

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
| R24 | §6.3 | Exercise names are compared by Unicode canonical equivalence, which is what Swift `String` equality does: a precomposed and a decomposed spelling of the same name are one exercise. There is still no trimming and no case folding. This replaces "byte for byte". The Kotlin twin normalises names to NFC before using them as keys. The parity oracle carries a case for it. |
| R25 | §8, §9 | Owner decision, 10 November 2026 (question S17). A weigh-in is written under the active strap id, as Lab Book writes. The weigh-in store and the body-measurement resolver **read** `weight` and `waist` Lab Book rows across every id the repository already unions for imported history: the active strap first, then the canonical id and every other registered WHOOP (`Repository.swift:144-158`, `:271-330`). Rows are de-duplicated by marker, instant and source, the active id's copy winning. Edit and delete act on the row under the id it was stored under. Nothing is re-keyed, moved or deleted by this stage. A test re-points the active id and asserts that every earlier reading is still returned, in the weekly series and by the resolver. Lab Book's own listing is unchanged here and is fixed in a separate pull request. |
| R26 | §8.3, §8.6 | The source scan of §8.6 stands as written: the Today views do not fetch weight themselves. Their Apple Health fetches move into `BodyMeasurementProvider`. With the flag off each view must show **exactly** the number it shows today, so the legacy display path takes the view's own window and as-of rule from the call site (91 days and the selected day in Liquid and the redesign; 90 days and the latest day in classic, including its sparkline source). An implementer who cannot reproduce a view's flag-off result through the provider stops and reports instead of approximating. |
| R27 | §8.5 | The profile mirror is not unwound. If the last dated reading is deleted, the profile keeps the last mirrored value and becomes the fallback again. Tests assert only that the mirror equals the resolver while a dated reading exists. |
| R28 | §8.5 | `ProfileStore` holds published copies of the profile values (`Profile.swift:82`). In the app the mirror is written through the live `ProfileStore` so its published values and the stored defaults cannot disagree; in tests it is written to the injected defaults. There is still exactly one writer of the mirror: the provider's `refresh()`. |
| R29 | §18 R25 | The union order is the repository's existing one (`Repository.swift:325-331`): the active strap, then other registered straps, then the canonical id. Only "the active id's copy wins a duplicate" is binding. A date edit writes the new row under the old row's id. Rows under an id that is no longer registered are not listed by this stage; that case belongs to the separate Lab Book change, together with the per-id re-projection quirk at `LabMarkerStore.swift:217-241`. |
| R30 | §8.2, §9.2 | Units are partitioned by kind: a weight is admitted only in kg, lb or lbs, a waist only in cm or in. A `cutScorecard.phases` string that cannot be read yields no phases. Reading never rewrites a stored string. |
| R31 | §13, §12.8 | The repository's Apple Health, protein and lift reads stop at one day after the real clock (`Repository.swift:1843-1848`, `:3378-3385`). App-target tests and simulator runs that involve those sources therefore use dates relative to the real clock; the 2031 fixture is for the pure function and for Lab Book-only cases. |
| R32 | §8.4 | Review finding, confirmed. A Lab Book or weigh-in write does not change the caches `Repository.refresh()` compares, so `refreshSeq` does not move (`Repository.swift:1017-1024`). The provider therefore refreshes after **every completed** repository refresh, including one that found its caches unchanged, and after every `WeighInStore` write. With the flag on, each view that shows weight re-resolves when the provider's `revision` changes. With the flag off none of this does any work: no store read, no profile write, no extra view reload. |
| R33 | §8.1 | Review finding, confirmed. Liquid and the redesign pass the selected **logical** day (04:00 rollover), while the estimates, the mirror and the scorecard use the calendar day. Under the `unified` policy only, when the selected day is the current day the display resolves as of the later of the selected day and the calendar day, so a weigh-in saved between midnight and 04:00 shows on the tile at once. The legacy policies are untouched. |
| R34 | §9.1 | Review finding, confirmed. A date edit whose target instant is already taken by another row of the same marker, source and device id throws `WeighInError.instantOccupied` and writes nothing. A save that lands on the instant of an existing row updates that row's value and unit only; its id, category, note, reference text and stored day are kept. |
| R35 | §8.3 | Review finding, confirmed. With the flag off the classic Today tile must match the base commit in transient frames too: the reading is resolved at each point where an input of the base render-time expression changed during a load, not once at the end. |
| R36 | §18 R34 | Second review, confirmed. The occupied-instant check spans every id of the R25 union, not only the row's own id: a date edit onto an instant already held by another row of the same marker and source under **any** unioned id throws `instantOccupied` and writes nothing, because the cross-id de-duplication would otherwise hide one of the two readings. One exception: when the occupying row already equals the replacement in every column except `id` (the state an interrupted date edit leaves behind), the edit completes by deleting the old row and writing nothing new. A save keeps R34's behaviour for a row under the active id; a save onto an instant held only under another unioned id throws `instantOccupied`. |
| R37 | §18 R35 | Second review, confirmed. The classic Today tile resolves its reading from the view's live state (the current series and the current daily rows), not from values local to one load pass, so two overlapping loads cannot leave a reading the base commit would not show. |
| R38 | §8.3 | Second review, confirmed. A reading cached by a Today view records the policy it was resolved under. A cached reading resolved under another policy than the current one is not restored: the view resolves again. Switching the flag off therefore returns every Today view to the legacy value at once, without waiting for an unrelated refresh. |
| R39 | §18 R36 | Third review, confirmed. In the equality exception of R36 the stored `day` is not compared: it is derived from the instant and the zone of the original write, so a retry after the device changed zone must still complete. Every other column except `id` is compared. |
| R40 | §18 R38 | Third review, confirmed, **carried into work package 1-7**. Two parts of R38 are not complete and cannot be reached until 1-7 adds the switch that changes the flag: (a) the Liquid and redesign weight **sparkline** is not resolved again when the policy changes, only the value is; (b) no Today view observes the flag itself, so a change made while Today stays mounted and nothing else changes is not picked up until the next body evaluation. Work package 1-7 owns both: each Today view observes `noop.cutScorecardEnabled` (reading it with a default writes nothing), folds it into its weight task identity, and resolves value and sparkline together. Its tests cover switching the flag on and off with Today mounted. |
| R41 | S19, §8, §10.7 | Owner decision, 11 November 2026. The owner wants **one number per variable throughout the app**: today the profile shows one weight and the home screen another (from Apple Health). With the flag on, every surface that shows or uses the *current* weight or waist shows the resolver's value and nothing else: Today (all three variants), Profile, Settings, the estimates, Health readiness, the scorecard and the Coach context. A surface that lists one source's history (the Apple Health page, the Lab Book list, Compare charts) may show that source's series, labelled as that source, and never as "current". The profile mirror may replace the Settings value when the flag goes on (S19 accepted). Every place that shows the current value offers a way to correct it: it opens the weigh-in sheet or the history. A flag-on audit of every surface, with a test per surface, is part of stage 1. |
| R42 | S18, R25, R29 | Owner decision, 11 November 2026: **a strap being disconnected, removed or gone must not delete the owner's readings.** Weight, waist and every other Lab Book reading the owner entered are the owner's data, not the strap's. Removing, forgetting or deleting a strap's data must leave them in place and still listed. This reverses, for this fork, the earlier decision to include `labMarker` in the tables a strap delete clears (`DeviceRegistryStore.swift:162-173`). It is a stored-data change with its own specification, tests, data-safety review and pull request ("Lab Book ownership"), and it also takes the items R29 deferred: Lab Book's listing across strap ids and the per-id re-projection. Erasing all of the app's data on purpose is a different action and still removes them. |
| R43 | Q3 | Owner decision, 11 November 2026: the owner has no Android device and Android work is skipped. The Kotlin twins already written (the scorecard, its oracle test, the two backup keys) stay in the tree as written and never executed. From here on a change to shared logic records a written disposition in its pull request instead of a Kotlin twin, and the gate script's Android rows are waived by flag and reported as waived, never as passed. The parity ratchet's Kotlin lines stay as recorded debt. |
| R44 | §7.1, §8.1, §8.2, §8.7, R41 | Cross-stage check X11, owner decision in force by default (S21), 11 November 2026; restated in the second reconciliation pass, where the orchestrator ruled that this is the rule's one home. A ruling on `BodyMeasurementResolver`. Within one Monday week, a usable row with source `manual` outranks every row of the same marker key (`weight` or `waist`) with source `MarkerCatalog.scanSource` (`body-scan`): the scan rows of that week are not readings for the resolver, not for the weekly point, the current value, the profile mirror or the estimates. A scan alone in its week is a reading like any other. No other source outranks or is outranked; a scan imported by CSV is not outranked and competes by instant. Only rows dated on or before the as-of day are judged or can outrank: a row after the as-of day never suppresses. The rule is one function, `BodyMeasurementResolver.withoutOutrankedScans(_:asOf:)` in `Strand/Data/BodyMeasurementResolver.swift`, with exactly two callers: `BodyMeasurementResolver.series` under the `unified` policy, before the newest-day and same-day rules, and `CutScorecardPresenter.history` for the week mark. `BodyMeasurementResolver.series` and `BodyMeasurementProvider.series` gain `asOf: String? = nil`; `resolve(asOf:)` is the last element of `series(asOf:)`; the input builder passes `asOf: today`. The pure function, its Kotlin twin and every stored row are unchanged, and R41 stands: one stored number per reading, one resolver. §8.7 is the full text. It is implemented by work package 1-11 in stage 4's serialised step, after stage 4's catalogue package declares the scan source constant. |
| R45 | §9.2, §10.5, §11 | Cross-stage check X12, binding, 11 November 2026; restated in the second reconciliation pass, where the orchestrator ruled that this is the rule's one home. The protein floor has one home, `proteinFloorGrams` in `cutScorecard.rules`, and is stored and edited as a whole number of grams, from 1 to 100 000, or absent. One function, `CutScorecardSettings.isWholeGramProteinFloor`, decides what an editor may save; the rules sheet is the first editor and stage 3's intake settings the second, writing the same stored value through the same setter with no rule of their own. Neither editor rounds a typed fraction. `CutScorecardSettings.parameters` normalises on write and on read through `normalizedProteinFloorGrams` (nearest whole, halves away from zero, never below 1; invalid values pass through to validation); a read never rewrites the stored string (R30). No reader sees a fraction, so no surface has a state for one. Every surface prints `proteinFloorWholeGrams` followed by `g` with no decimals. `CutScorecardParameters.proteinFloorGrams` stays `Double?`. |
| R46 | §1, §7.2, §9.2, §10.2, §10.5 | Cross-stage check X14, owner decision in force by default (S22), 11 November 2026. A diet break or a deload is a stage 5 event and is never entered as a phase; phases are only the long blocks. The pure function receives the same active phase throughout an event and reports as in any other week: no rule, window or count pauses. Stage 5 shows the event's note under the verdict. The phase sheet says beside its kind control that a break or deload is added as an event. Kind `other` keeps its existing meaning and behaviour. |
| R47 | §1, §7.7, §7.8, §9.2, §10.2, §10.5 | Cross-stage check X10, owner decision in force by default (S20), 11 November 2026. The active phase's `targetWeightKg` is the only target weight in the app and the only weight the projection runs to. A phase element has no target date and gains none. A stage 6 checkpoint that carries a weight is a waypoint, labelled so, never read by this stage, and refused by stage 6 when equal to or beyond the phase target; a dated target is a checkpoint with no weight, attached to the phase. |
| R48 | §13, R31 | Cross-stage check X20, binding, 11 November 2026. The Fixture Person of §13 is the one fixture person of the workstream. Demo, simulator and app-target fixtures in every stage take their phase, weigh-in weekday, weights, waists, missed week, lifts, protein days and protein floor (100 g) from §13, shifted by whole weeks where R31 requires real-clock dates. A pure-logic golden elsewhere may keep its own values. This stage's own fixture and `ScorecardDemo` do not change. |

Fault injection on 10 November 2026 ran 198 single mutations of the implementation. Three were not
caught by any test and are covered by tests added afterwards: the heaviest set when one exercise has
several sets on one day; the prior lift window ending at `a − 8`, not `a − 7`; and the `dropped >= 1`
condition when `liftDropShare` quantizes to zero. Seven mutations were equivalent (they cannot change
any output).

## 19. Reconciliation (11 November 2026)

Applied from the cross-stage check (`build/superapp-coordination/cross-check.md`, an ignored local
file). One line per conflict that names this stage, then what is expected from elsewhere.

| Conflict | Decided by | What changed in this file |
|---|---|---|
| X10 | Owner, in force by default (S20) | §1, §7.7, §9.2, §10.2, §10.5: the phase's `targetWeightKg` is stated as the only target weight; a stage 6 checkpoint weight is a waypoint and a dated target is a checkpoint with no weight. Test `testAStoredPhaseHasNoTargetDateOrEndDateKey`. Ruling R47 |
| X11 | Owner, in force by default (S21) | §7.1, §8.1, §8.2 (new rule 3; the profile fallback is now rule 4), §8.6, §10.2 to §10.4, §12.3, §12.6 (F29 to F35), §13.5, §14 (work package 1-11): a manual weigh-in outranks a body scan within its Monday week; `series` gains `asOf`. Ruling R44 |
| X12 | Orchestrator, binding | §5, §9.2, §10.5, §11, §12.3, §12.4, §12.6 (F36 to F39), §14 (work package 1-10): the floor has one home, is whole grams at both editors, normalised on read and write, and printed one way. Ruling R45; S23 |
| X14 | Owner, in force by default (S22) | §1, §7.2, §9.2, §10.2, §10.5, §11: a diet break or deload is an event, never a phase; the scorecard keeps reporting; one new line on the phase sheet. Ruling R46 |
| X20 | Orchestrator, binding | §13: this fixture is declared the one Fixture Person for every stage, with its base values listed and the whole-week shift under R31. Ruling R48 |
| X23 | Orchestrator, binding | Pointers to R43 at the top of §1 and §14. Beyond the resolution's minimum, as the reconciliation brief required: the header, §1, §4.4, §5, §7.1, §8.5, §9.3, §12.4, §12.7, §14, S14, §16 and the §18 preamble no longer instruct anyone to write or run Kotlin; work package 1-5 is marked closed; §9.3 states the drift |

Not applied here, because the conflict does not name this stage: X1 to X9, X13, X15 to X19, X21,
X22, X24. Three of them touch files this stage created, and §14 records the order only: X18 (model
and builder), X22 (the scorecard screen's additions) and the shared-file row for the nine Today
files.

Privacy: the cross-check lists no finding against this file. On re-reading, three sentences that
spoke about the state of a real install were reworded to speak about the build (§8.2, and two items
of §16). No value, date or product was involved.

**Shared scaffolding this stage expects from the orchestrator's step 0** (one commit on the
integration branch, before any stage builds):

- **The demo registry line** in `StrandiOS/App/StrandiOSApp.swift`, added by step 0. This stage's
  demo file is `StrandiOS/Scorecard/ScorecardDemo.swift` and its one registry element is
  `ScorecardDemo.screen(named:)`. Its reserved names are the existing unprefixed set in that file
  (they predate the registry and are not renamed); any scorecard demo name added later takes the
  prefix `scorecard-`. It returns nil for every other name. Work packages 1-10 and 1-11 add no demo
  name.
- **The plugin import commands and stage-named design folders** (`importS2` to `importS6`,
  `design/round-sN-…`). This stage's approved frames stay where §17 records them
  (`design/round6-scorecard/`); it needs no new command. The combined frame for the scorecard
  screen, the Health card and Settings (cross-check X22) is drawn over this stage's approved frames
  and does not replace them.
- **`ObservableDefaultsFlag`.** `CutScorecardFlag.shared` is the type the other flags copied. After
  step 0 it is expected to be one static instance of `ObservableDefaultsFlag` over
  `noop.cutScorecardEnabled`, with the same observable `isEnabled` and no change at its call sites
  (`TodayView`, `LiquidTodayView`, `SettingsView`, `LabBookView`, `CompareView`,
  `TodayCustomizationSheet`). The R40 behaviour (a Today view that stays mounted picks up a flag
  change) must hold after the swap; its existing tests are the check.
- **`CanonicalDay`**, the one implementation of ruling R5's day-key rule outside the package, with
  the test that pins it to `CutScorecard.weekStart(containing:)`. `CutScorecard`'s own private rule
  is not removed. Work package 1-11 groups rows by `CutScorecard.weekStart(containing:)` directly.
- **`ChargeTypicalBand`.** Not used by this stage; listed so that nothing here is read as needing
  it.
- **The fork-only backup keys comment** above `BackupSettings.whitelist`. This stage's two keys are
  on both whitelists and are not fork-only; the comment should say so in one line, so that a reader
  does not take them for keys the Kotlin side lacks.

### Second pass

Applied from the independent re-check of the first pass (`build/superapp-coordination/recheck.md`,
an ignored local file) and the orchestrator's rulings for this pass. One line per item that names
this file or touches this stage.

| Item | Decided by | What changed in this file |
|---|---|---|
| X11, and the new conflict "specified and implemented twice" (ruling a) | Orchestrator, binding | The rule has its one home here. New §8.7 holds the whole rule; §8.2 rule 3 is now a pointer to it. The rule's shape is one function, `BodyMeasurementResolver.withoutOutrankedScans(_:asOf:)`, with `weighInSource`, and exactly two callers: `series` and `CutScorecardPresenter.history` (§5, §8.1, §8.7, §10.4). Kept from the first pass: the `asOf` parameter and "a row after the as-of day never suppresses"; the rule per marker key, for weight and for waist. Added: a manual row must be usable to outrank; a row with a non-canonical day belongs to no week; a scan imported by CSV is not outranked and competes by instant, stated as a rule and no longer only as an open question (S24). `history` gains `today:`. New tests in §12.3, the source scan `test_outranking_rule_has_two_callers` in §12.4 (the first pass had said no source scan), faults F40 to F43, cases S7b and S11 to S16 in §13.5. R44 restated; S21 lists what is dropped if the owner decides otherwise. Work package 1-11 stays the implementer, in stage 4's serialised step after stage 4's catalogue package; it now also edits `CutScorecardModel.swift` (one argument) and the Python source-scan file |
| X12, and the new conflict "two whole-gram rules" (ruling b) | Orchestrator, binding | The rule has its one home here (§9.2, R45). Added the one editor predicate `CutScorecardSettings.isWholeGramProteinFloor` and `proteinFloorMaximumGrams` (100 000 g, the bound the intake field already used, so the two editors accept the same range). §9.2 now states that both editors write through the `parameters` setter, that no reader sees a fraction and that no "needs whole grams" state exists anywhere. The clause about a stored value too large to print, which no path could reach through an editor, is replaced by the one statement of what a hand-edited out-of-range value does. §10.5, two tests, one presenter test, fault F44, S23 |
| X10 | Re-check | §9.2: the stage 6 names are now `weightWaypoint` with `waypointWeightKg` for a waypoint, and category `targetDate` attached by `phaseStartDay` for a dated target. `weightTarget` no longer appears |
| Shared-file order includes stage 3 (ruling c), and the new conflict "stage 3 became an editor" | Orchestrator, binding | §14: the list "order against the other stages" is replaced by a hotspot table that gives this stage's own position on each shared file in the one order (Lab Book ownership, stage 2, stage 3, stage 4, stage 5, stage 6, packet v2) and no other stage's. The orders it used to quote for the model, builder, presenter and view are removed. Work package 1-10 is placed after Lab Book ownership and before stage 2; 1-11 after stage 3, first in stage 4's step |
| Settings and Health order (ruling d; X22) | Orchestrator, binding | §10.6 and §10.9 state this stage's position only: Scorecard is first. §10.2 no longer lists what later stages add to the scorecard screen |
| Debug demo registry (ruling h; X6) | Orchestrator, binding | §5 and the scaffolding list above: this stage's file (`ScorecardDemo.swift`), its one registry element and its names (the existing unprefixed set; `scorecard-` for any later name). The sentence about the order of the registry is removed |
| `AICoach.swift` order (ruling i; X17) | Orchestrator, binding | §14 hotspot table: this stage does not edit the file |
| Privacy (ruling k) | Orchestrator | Ruling R43 is left exactly as it was. Nothing else in this file was named |

Rulings (e), (f), (g) and (j) name no text of this stage and changed nothing here.

What this pass expects from the other specifications, so that the texts agree:

- **Stage 4** refers to §8.7 and R44 and specifies no resolver code: no second declaration of
  `withoutOutrankedScans` or `weighInSource`, no source scan of its callers, and no edit of
  `BodyMeasurementResolver.swift`. Its variants assert through `series(…, asOf:)` or through the
  function as declared in §8.1, with the `asOf` parameter. Its statement that the rule covers weight
  rows only is superseded by "per marker key, weight and waist" here; the two agree for every row a
  scan sheet writes while no scan writes a waist row.
- **Stage 3** validates its floor field with `isWholeGramProteinFloor` (or a predicate tested equal
  to it), writes through `CutScorecardSettings.parameters`, and prints `proteinFloorWholeGrams`.
- **Stage 6** uses the checkpoint names quoted in §9.2.

Not made consistent from this file alone:

- `CutScorecardModel.swift` gains one argument in work package 1-11 (`today` passed to `history`).
  The re-check's proposed order for that file did not include 1-11; the position is stated in §14.
- Whether work package 1-10 runs before or after the Lab Book ownership change was not fixed by the
  cross-check. §14 places it after, because both add to the String Catalog and ownership is first
  in the one order. The two packages share no other file.
