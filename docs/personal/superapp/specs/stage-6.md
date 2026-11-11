# Stage 6 specification — niggle log, cut-stress view, checkpoint timeline

Gate G0 for stage 6 of the health super-app workstream. Read [CONTEXT.md](../CONTEXT.md),
[ROADMAP.md](../ROADMAP.md) (stage 6, and stages 1, 4 and 5 which feed it),
[QUALITY-GATES.md](../QUALITY-GATES.md) and the stage 1 specification ([stage-1.md](stage-1.md),
especially §8, §9, §14 and rulings R25 to R43) first.

Verified against the source at commit `0b89b814` (branch `personal/superapp-6-niggle-timeline-spec`,
cut from `personal/superapp-1-screens`, on which stage 1 is built). Every `path:line` is as of that
commit. Paths are relative to the repository root. Nothing was built or run for this document; it is
a reading of the code.

The roadmap says this stage is specified only after stage 5. The owner has since asked for every
stage to be planned now, so this document is written on **stated assumptions** about stages 2 to 5
(§2.2). Each is checked when the stage it names lands, before G2 for the part that depends on it.

This file contains no personal measurement, date, rule or injury detail. Every example belongs to
the synthetic "Fixture Person" of §13; every label, number and date was invented for this document.

LOCAL ONLY, by the owner's decision: nothing in this stage is pushed and no pull request is opened.

## 1. Goal and scope

**Goal.** The owner keeps a dated log of complaints labelled by their own written rules, sees
resting heart rate and HRV week by week beside the scorecard as context for the coach, and sees
every phase, scan, break, deload, checkpoint and the scorecard's projection in one dated list.

**In scope**

- (a) **Niggle log.** Complaints with location, side, character and onset day; dated updates;
  resolve and reopen; a label from the owner's own triage rules; the day count; the owner's own
  written rule for seeing a professional, shown verbatim; standing observations; and a list of
  exercises the coach has paused, each with its reason.
- (b) **Cut-stress view.** Weekly means of nightly resting heart rate and nightly HRV on the
  scorecard's own weeks, with the number of nights behind each mean and the personal typical range
  as text. Display only.
- (c) **Checkpoint timeline.** One list built by one pure function from: stage 1's stored phases,
  owner-entered checkpoints (the home of target dates and planned scans), recorded scan days
  (stage 4), diet breaks and deloads (stage 5), and the scorecard's projection.
- Three default-off settings, one per part.

**Out of scope**

- Any diagnosis, any suggestion of a cause or a treatment, any shipped default triage rule. The app
  applies rules the owner typed and says so.
- Any new score, band, tier, colour state or adjective for resting heart rate or HRV. Nothing in
  part (b) is read by Recovery, Strain, the scorecard verdict, illness detection, the Coach context
  or any widget (AGENTS.md, "Deriving a physiological signal").
- Notifications of any kind. Stage 6 adds none (§10.9). Widgets: none (§10.8).
- A Today card. Stage 6 adds no `DashboardCard` case (decision D7).
- Sending niggles, rules or paused exercises to the in-app Coach or the coach packet. Stage 2 owns
  the packet; a niggle section is a later change to it, default off (§15, Q6).
- Enforcing a pause (hiding or flagging a paused exercise in lift sessions or imports).
- A migration, a new table, a new catalogue key, a new target, entitlement or network path, any
  change to Health access. None is needed (§9).
- Android. No Kotlin twin is written (R43); §12.7 records the dispositions and the drift.
- Charts with horizontal rules, bands or target lines.

## 2. Re-check of "what exists", and assumptions

### 2.1 What exists

| # | Claim | Status | Evidence |
|---|---|---|---|
| 1 | Stage 1 stores phases as a settings string | Confirmed: `cutScorecard.phases`, a JSON array, sorted keys, `"v":1` per element, read on each access, never rewritten by a read | `Strand/Data/CutScorecardSettings.swift:64-69`, `:106-117`, `:254-259` |
| 2 | A stored phase has a target date | **Wrong.** A phase has `kind`, `name`, `startDay`, optional `targetWeightKg` and a rate band. It has no end day and no target day | `CutScorecardSettings.swift:5-17`. See §3, C2 |
| 3 | The scorecard produces a projection | Confirmed: `CutScorecardProjection` with `status`, `targetDay` (set only when `projected`), `weeksRemaining`, `remainingKg` | `Packages/StrandAnalytics/Sources/StrandAnalytics/CutScorecard.swift:190-200` |
| 4 | The scorecard model exposes its result | **No.** `CutScorecardModel` publishes only a `CutScorecardPresentation` (strings). The raw `CutScorecardEvaluation` is local to `load()` | `Strand/Data/CutScorecardModel.swift:69-76`, `:141-180`. See §3, C3 |
| 5 | Unreadable stored settings are surfaced, not overwritten | Confirmed: `phasesNeedAttention`, `discardUnreadablePhases`, and a save that refuses while it is true | `CutScorecardSettings.swift:119-137` |
| 6 | One observable copy of a feature flag exists | Confirmed for the scorecard key only; the class is not generic | `CutScorecardModel.swift:18-63` |
| 7 | Baselines for resting heart rate and HRV exist | Confirmed. `Repository.chargeBaselines` is resolved once per refresh by `ChargeBaselines.resolve` and is "the single funnel every Charge readout below the headline reads" | `Strand/Data/Repository.swift:185-190`, `:1004`, `:1037`; `Packages/StrandAnalytics/Sources/StrandAnalytics/ChargeBaselines.swift:151` |
| 8 | Today shows trends for HRV and resting heart rate | Confirmed: sparklines built from the merged daily rows (`repo.days`), keyed `hrv` and `rhr`, filtered to a 7, 14 or 30 day window | `Strand/Liquid/LiquidTodayView.swift:3363-3364`, `:3639-3647`, `:1188-1194`; `StrandiOS/Redesign/RedesignTodayView.swift:602` |
| 9 | A "typical range" is shown for HRV and resting heart rate | Confirmed, in one place: Recovery detail's factors, `baseline ± Baselines.sigma(state)` when the baseline is usable. The expression is a local function | `StrandiOS/Redesign/ScoreDetailData.swift:156-165`; `Baselines.swift:602`. It is the only app-target caller of `Baselines.sigma` |
| 10 | `HRVReadiness` is available as a trend read model | It exists, is experimental, opt-in, and read only by the Test Centre. It is a **tier** (primed, normal, suppressed) | `Packages/StrandAnalytics/Sources/StrandAnalytics/HRVReadiness.swift:1-28`, `:93`; `Strand/Screens/TestCentreView.swift:753`. Not used by this stage (D9) |
| 11 | The `event` table can hold personal events | It is a strap stream table: primary key `(deviceId, ts, kind)`, carries a `synced` column, is written by the collector and by `recordEvent`, and is in the list a strap delete clears | `Packages/WhoopStore/Sources/WhoopStore/Database.swift:28-34`, `:130-135`; `WhoopStore.swift:187-192`; `StreamStore.swift:288`; `DeviceRegistryStore.swift:162-165`. Not used by this stage (D1) |
| 12 | `labMarker` is cleared by a strap delete | Confirmed today; ruling R42 reverses it in a separate change that has not landed on this branch | `DeviceRegistryStore.swift:166-173` |
| 13 | The backup whitelist carries only Int, Double and String, and a JSON array or object rides as a String | Confirmed; restore writes only keys present in the incoming file | `Packages/WhoopStore/Sources/WhoopStore/BackupSettings.swift:29-31`, `:49-76`, `:82-97`, `:119-126` |
| 14 | Calendar-free day arithmetic exists | Confirmed: `WeeklyDigestEngine.mondayOfWeek`, `addDays` (public); `parseYMD` (public); `formatYMD`, `julianDayNumber`, `fromJulianDayNumber` (module-internal). The canonical-key rule of R5 is private to `CutScorecard` | `WeeklyDigest.swift:421`, `:430`, `:462`, `:471`, `:480`, `:488`; `CutScorecard.swift:1046`, `:1055` |
| 15 | The weekly curve component exists | Confirmed: `ScorecardWeekChart(points:firstLabel:lastLabel:color:)`, one optional point per week, a missing week breaks the line, no rule or band | `StrandiOS/Scorecard/ScorecardWeekChart.swift:4-15` |
| 16 | The debug demo harness can host new frames | Confirmed: `--demo-screen <name>` falls through to `ScorecardDemo.screen(named:)`; each state runs on an in-memory store and its own defaults suite | `StrandiOS/App/StrandiOSApp.swift:621-623`; `StrandiOS/Scorecard/ScorecardDemo.swift:26-63` |
| 17 | The design pipeline exists | Confirmed: `design/tools/serve.py` (preview and `--export`), `design/round6-scorecard/`, plugin commands `import` and `import6` | `design/tools/serve.py:1-25`; `design/figma-plugin/manifest.json:21-26` |
| 18 | The local gate script exists | Confirmed | `Tools/personal/gate.sh:1-36` |
| 19 | Lab Book has a category for imaging | Confirmed: `LabMarkerCategory` has `imaging`. No body-composition scan key exists yet | `Packages/StrandImport/Sources/StrandImport/LabMarker.swift:26-33` |
| 20 | The newest migration is `v47-rr-whoop5-fill` | Confirmed | `Database.swift:1103` |

### 2.2 Assumptions about stages 2 to 5

Each is checked when its stage lands. A false assumption changes only the adapter named, not the
pure functions.

| # | Assumption | Used by | If false |
|---|---|---|---|
| A1 | Stage 4 stores a body-composition scan as `labMarker` rows that share one `day`, and offers one read that returns the distinct scan days (assumed `BodyRecordStore.scanDays() async -> [String]`, or an equivalent), reading across strap ids as R25 and R42 require | `TimelineScanSource` (§5) | Rewrite the adapter body. The timeline's input is `[String]` either way |
| A2 | Stage 4 has its own default-off setting, readable without writing | `TimelineSourceState` for scans | The state is `.on` whenever the adapter exists |
| A3 | Stage 5 stores personal events with a kind, a start day, an optional end day and a sensitivity flag, and offers one read returning them (assumed `PersonalEventStore.events() async -> [PersonalEvent]`). The kinds include a diet break and a deload | `TimelineEventSource` (§5) | Rewrite the adapter. The timeline's input is `[TimelineSpan]` either way |
| A4 | Stage 5's storage does not depend on a strap id, or reads across ids (R42) | Timeline | Nothing in stage 6 changes; the gap is stage 5's |
| A5 | Stage 5 has its own default-off setting | `TimelineSourceState` for events | As A2 |
| A6 | Stage 5's scorecard annotation does not change `CutScorecardResult.projection` | Timeline projection item | None: the timeline reads whatever the shared model holds |
| A7 | Stage 2 may already have added a way to read the raw evaluation from `CutScorecardModel` | §8.3 | If it exists, stage 6 uses it and adds nothing. If not, stage 6 adds the property in §8.3 |
| A8 | Stage 2's packet has no niggle section and stage 6 adds none | §1 | Nothing |
| A9 | Stage 3 adds a widget and a reminder; stage 6 adds neither, so the notification count is unchanged by this stage | §10.9 | Nothing |
| A10 | Stages 2 to 5 each add their own row to the Health tab's "More health" card or to Settings; the insertion points in §14 are still present | Work packages 6-7, 6-8 | The implementer rebases the two insertions |
| A11 | Design rounds 7 to 10 are taken by stages 2 to 5, so this stage is `design/round11-stage6/` with plugin command `import11` | Work package 6-2 | The orchestrator assigns the next free number |
| A12 | The "Lab Book ownership" change (R42) may or may not have landed. Stage 6 stores nothing in `labMarker`, so it does not depend on it | §9 | Nothing |

## 3. Corrections to the planning documents

| # | Document says | The code says | Consequence |
|---|---|---|---|
| C1 | ROADMAP stage 6: "Needs a migration: Possibly" | None of the three parts needs one. The log, the rules, the paused list and the checkpoints are small owner-authored lists and are stored as settings strings, as stage 1 stores phases (`CutScorecardSettings.swift:106-117`) | No migration, no owner go-ahead needed for storage (§9) |
| C2 | ROADMAP stage 6: the timeline shows "target dates" as if they were stored | A stored phase has a target **weight** and no date (`CutScorecardSettings.swift:5-17`). The only dated target the app holds is the projection's `targetDay`, which is an estimate (`CutScorecard.swift:196-200`) | Target dates are owner-entered checkpoints (§9.3). The projection is a separate item, labelled as an estimate |
| C3 | Stage 1 specification §8.1: the scorecard's values are "reads of one list" available to other surfaces | The model publishes strings only (`CutScorecardModel.swift:69-76`). A second surface that needs the projection day would have to evaluate again, which is the "two readouts of one fact" shape | §8.3 adds one read-only property to the shared model. The timeline never calls `CutScorecard.evaluate` |
| C4 | CONTEXT §4: the `event` table is "a generic timestamped event with a JSON payload" that later stages might reuse | It is keyed by strap id and instant, deduplicates on `(deviceId, ts, kind)` with `DO NOTHING`, has a `synced` flag and is cleared by a strap delete (`Database.swift:28-34`; `WhoopStore.swift:187-192`; `DeviceRegistryStore.swift:162-165`) | Unusable for owner-entered records under R42 (D1). Stage 5 must reach the same conclusion or record why not |
| C5 | ROADMAP stage 6 names "resting heart rate and HRV trends" as if a trend read model existed | There is no weekly read model. Today's trends are per-night sparklines (`LiquidTodayView.swift:3363-3364`); `HRVReadiness` is a tier, experimental and Test-Centre only (`TestCentreView.swift:753`) | §6.2 specifies a small pure weekly aggregation; it is an arithmetic mean of values the app already shows, and it has one caller |
| C6 | Stage 1 specification R5 fixes the canonical day-key rule | The rule is implemented privately inside `CutScorecard` (`CutScorecard.swift:1046-1059`), so a second pure type cannot reuse it without editing a stage 1 file | §6.0 adds `CanonicalDay`, and a test asserts it agrees with `CutScorecard.weekStart(containing:)` on validity |
| C7 | ORCHESTRATION: the backup whitelist's sole writer is the Parity agent, "Swift and Kotlin" | Under R43 no Kotlin is written | The Swift whitelist is edited by Implementer B of this stage; the Kotlin side is recorded as not updated (§9.5) |
| C8 | QUALITY-GATES G1 step 2: the local server script "may need to be written again" | It exists at `design/tools/serve.py` | Nothing to rebuild |
| C9 | QUALITY-GATES G7 and ORCHESTRATION rule 9: stage branches are pushed and pull requests opened | The owner has since decided this workstream is local only | Stage 6 ends in local commits on its branch; G7 is the owner's local merge |

## 4. Every reader and writer

### 4.1 Nightly resting heart rate and HRV (part b)

The fact is `DailyMetric.restingHr` and `DailyMetric.avgHrv` per day (`MetricsCache.swift:83-91`),
published merged as `Repository.days` (`Repository.swift:184`, set at `:1036`).

| Site | What it does | Stage 6 |
|---|---|---|
| `Strand/Data/IntelligenceEngine.swift` (29 uses), `Strand/Data/DayCycleIntelligenceIntegration.swift`, `Strand/App/AppModel.swift` | Compute and write the nightly values; feed Recovery and Strain | Untouched. Stage 6 writes nothing |
| `Strand/Data/Repository.swift:1004`, `:1036-1037` | Merges rows into `days`; resolves `chargeBaselines` | The **one source** part (b) reads |
| `Strand/Liquid/LiquidTodayView.swift:1200-1201`, `:1703-1704`, `:3363-3364`; `Strand/Screens/TodayView.swift`; `StrandiOS/Redesign/RedesignTodayView.swift:602` | Today tiles and sparklines: the night's value, with a carried value at rollover | Untouched. Part (b) shows no "current" value, so it cannot disagree with them (§8.2) |
| `Strand/Data/TodayCardReadout.swift:188-197` | Your Cards HRV and Resting HR readouts | Untouched |
| `StrandiOS/Redesign/ScoreDetailData.swift:149-165` | Recovery detail: value and typical range | The typical-range expression moves to one shared function (§8.2) |
| `Strand/Screens/VitalSignsSummary.swift:178`, `:210-211`; `Strand/Screens/HealthView.swift`; `Strand/Screens/SleepModel.swift:412` | Vital signs: freshest carried value | Untouched |
| `Strand/Screens/TrendsView.swift`, `TrendsReportView.swift`, `WeeklyDigestView.swift`, `HostedTrendCard.swift`, `MetricExplorerView.swift`, `InsightsView.swift`, `StressView.swift` | Charts and reports of the nightly series | Untouched. They chart nights; part (b) charts weekly means and says so |
| `Strand/AI/AICoach.swift:1607`, `:1635-1636`, `:1698-1699` | Coach context: per-day values and 30-day averages | Untouched. Part (b) feeds nothing to the Coach |
| `Strand/Screens/TestCentreView.swift:753` | Experimental HRV readiness tier | Untouched and not reused |
| `StrandiOS/Widgets/WidgetPublish.swift`, `StrandiOSShared/WidgetSnapshot.swift`, `StrandiOSWidgets/NOOPWidget.swift` | Widget snapshot of the night's values | Untouched |

### 4.2 Phases, projection, target weight (part c)

| Site | What it does | Stage 6 |
|---|---|---|
| `Strand/Data/CutScorecardSettings.swift:106-117` | The one reader and writer of `cutScorecard.phases` | The timeline reads `phases` through this type only |
| `Strand/Data/CutScorecardModel.swift:881` (`ScorecardPhaseDraft.save`), `StrandiOS/Scorecard/ScorecardPhaseSheet.swift` | Writes phases | Untouched. A phase item on the timeline opens this sheet to correct it (R41) |
| `Strand/Data/CutScorecardModel.swift:141-180` | Evaluates and presents | Gains one read-only property (§8.3) |
| `Strand/Data/CutScorecardPresenter.swift` (projection strings), `StrandiOS/Scorecard/ScorecardView.swift:507` | Show the projection | Untouched. The timeline's projection item is built from the same evaluation and worded by the same `Wording` (`CutScorecardPresenter.swift:1024`, `:1044`) |
| `Packages/WhoopStore/Sources/WhoopStore/BackupSettings.swift:74-75`, `:95-96` | Back up phases and rules | Untouched for those keys |

### 4.3 Facts that are new in this stage

Niggles, triage rules, the professional rule, paused exercises and checkpoints have no existing
reader or writer. Searches for `niggle`, `injur`, `paused`, `checkpoint` and `timeline` under
`Strand/`, `StrandiOS/`, `StrandiOSShared/`, `StrandiOSWidgets/` and `Packages/` found no stored
fact of these kinds. Each gets exactly one store type (§5) and the source scan of §12.4 keeps it so.

### 4.4 Android

No Android file is read, written or changed by this stage. `android/app/src/main/java/com/noop/data/BackupSettings.kt:81-82`
shows the two stage 1 keys as the newest entries; the four keys of §9.5 are not added.

## 5. Final names

| Thing | Name | Where |
|---|---|---|
| Day-key helper | `CanonicalDay` | `Packages/StrandAnalytics/Sources/StrandAnalytics/CanonicalDay.swift` |
| Triage | `NiggleTriage.evaluate(_:)` and the `NiggleTriage*`, `Niggle*` types of §6.1 | `Packages/StrandAnalytics/Sources/StrandAnalytics/NiggleTriage.swift` |
| Weekly trend | `CutStressTrend.weekly(_:)` and the `CutStress*` types of §6.2 | `.../CutStressTrend.swift` |
| Timeline | `CheckpointTimeline.build(_:)` and the `Timeline*` types of §6.3 | `.../CheckpointTimeline.swift` |
| Observable flag | `ObservableDefaultsFlag` | `Strand/Data/ObservableDefaultsFlag.swift` |
| Niggle storage | `NiggleLogSettings`; stored types `StoredNiggle`, `StoredNiggleUpdate`, `StoredTriageRules`, `StoredTriageRule`, `StoredPausedExercise` | `Strand/Data/NiggleLogSettings.swift` |
| Niggle model and presenter | `NiggleLogModel`, `NiggleLogPresenter`, `NiggleDraft`, `TriageRulesDraft`, `PausedExerciseDraft` | `Strand/Data/NiggleLogModel.swift`, `NiggleLogPresenter.swift` |
| Cut-stress model and presenter | `CutStressModel`, `CutStressPresenter` | `Strand/Data/CutStressModel.swift`, `CutStressPresenter.swift` |
| Typical range | `ChargeTypicalBand.range(_:)` | `Strand/Data/ChargeTypicalBand.swift` |
| Checkpoint storage | `CheckpointTimelineSettings`; stored type `StoredCheckpoint` | `Strand/Data/CheckpointTimelineSettings.swift` |
| Timeline sources | `TimelineScanSource`, `TimelineEventSource` | `Strand/Data/TimelineSources.swift` |
| Timeline model and presenter | `CheckpointTimelineModel`, `CheckpointTimelinePresenter`, `CheckpointDraft` | `Strand/Data/CheckpointTimelineModel.swift`, `CheckpointTimelinePresenter.swift` |
| Views | `NiggleLogView`, `NiggleDetailView`, `NiggleSheet`, `NiggleRulesSheet`, `PausedExerciseSheet` | `StrandiOS/NiggleLog/` |
| | `CutStressView` | `StrandiOS/Scorecard/CutStressView.swift` |
| | `CheckpointTimelineView`, `CheckpointSheet` | `StrandiOS/Timeline/` |
| Demo | `Stage6Demo` | `StrandiOS/NiggleLog/Stage6Demo.swift` |
| Routes | `RedesignRoute.niggleLog`, `.niggle(id: String)`, `.cutStress`, `.checkpointTimeline` | `StrandiOS/Redesign/RedesignRoute.swift` |
| Flags (Bool, default `false`) | `noop.niggleLogEnabled`, `noop.cutStressEnabled`, `noop.checkpointTimelineEnabled` | `NiggleLogSettings.enabledKey`, `CutStressModel.enabledKey`, `CheckpointTimelineSettings.enabledKey` |
| Stored strings | `niggleLog.entries` (JSON array), `niggleLog.rules` (JSON object), `niggleLog.paused` (JSON array), `timeline.checkpoints` (JSON array) | §9 |

Models, presenters, settings and adapters live under `Strand/` so `StrandTests` (macOS `Strand`
scheme) can test them, as stage 1 does. Views live under `StrandiOS/`. `project.yml` needs no edit:
both directories are included by path (`project.yml:88`, `:221`, `:240`); run `xcodegen generate`.

## 6. Pure logic: the API

All four files are in `Packages/StrandAnalytics`. No store, no clock, no `Calendar`, no `TimeZone`,
no `Date`, no free text. Every type is `public`, `Equatable`, `Sendable`, with a public memberwise
`init` taking the stored properties in declaration order with the defaults shown. Enums with raw
values are `String`. "Today" is always passed in as a day key.

### 6.0 `CanonicalDay`

```swift
public enum CanonicalDay {
    /// Julian Day Number of a canonical "yyyy-MM-dd" key (ten characters, years 0001–9999, a real
    /// date); nil otherwise. The rule of stage 1 ruling R5.
    public static func number(_ key: String) -> Int?
    /// The key of a day number, clamped to 0001-01-01 … 9999-12-31 (stage 1 ruling R21).
    public static func key(_ number: Int) -> String
    /// `number(to) - number(from)`; nil if either key is not canonical.
    public static func daysBetween(_ from: String, _ to: String) -> Int?
    /// The Monday of the week containing `key`; nil if not canonical.
    public static func weekStart(_ key: String) -> String?
}
```

Implemented with `WeeklyDigestEngine.parseYMD`, `formatYMD`, `julianDayNumber`,
`fromJulianDayNumber` and `mondayOfWeek` (`WeeklyDigest.swift:421-488`). `CutScorecard.swift` is not
edited. `CanonicalDay.number(k) != nil` must equal `CutScorecard.weekStart(containing: k) != nil`
for every string, and `CanonicalDay.weekStart(k)` must equal `CutScorecard.weekStart(containing: k)`.

### 6.1 `NiggleTriage`

```swift
public enum NiggleCharacter: String, CaseIterable { case diffuse, localised, positional, other }
public enum NiggleTrend: String, CaseIterable { case easing, unchanged, worsening, notRecorded }
public enum NiggleAction: String, CaseIterable { case watch, modify, seeProfessional }

public struct NiggleUpdate {
    public let day: String
    public let sequence: Int          // orders updates that share a day; greater is later
    public let trend: NiggleTrend
    public let weakness: Bool
}

public struct NiggleComplaint {
    public let onsetDay: String
    public let resolvedDay: String?   // nil: open
    public let character: NiggleCharacter
    public let trend: NiggleTrend     // as recorded at onset
    public let weakness: Bool         // as recorded at onset
    public let updates: [NiggleUpdate]   // default []
}

public struct NiggleTriageRule {
    public var id: String
    public var action: NiggleAction
    public var characters: [NiggleCharacter]   // empty: any character
    public var trends: [NiggleTrend]           // empty: any trend
    public var weakness: Bool?                 // nil: either
    public var fromDay: Int?                   // inclusive lower bound on the day count; nil: 1
    public var throughDay: Int?                // inclusive upper bound; nil: none
}

public struct NiggleTriageInput {
    public let complaint: NiggleComplaint
    public let rules: [NiggleTriageRule]       // the owner's order
    public let today: String
}

public enum NiggleTriageStatus: String { case matched, noRuleMatches, noRulesEntered, resolved, invalidInput }
public enum NiggleTriageInvalid: String {
    case today, rules, onsetDay, onsetAfterToday, resolvedDay, resolvedBeforeOnset, resolvedAfterToday
}

public struct NiggleTriageNextChange {
    public let dayCount: Int
    public let day: String
    public let ruleId: String?        // nil: no rule will match from that day
    public let action: NiggleAction?
}

public struct NiggleTriageResult {
    public let status: NiggleTriageStatus
    public let invalid: NiggleTriageInvalid?   // set exactly when status == .invalidInput
    public let isOpen: Bool
    public let dayCount: Int?                  // nil exactly when invalid
    public let currentTrend: NiggleTrend
    public let currentWeakness: Bool
    public let stateDay: String?               // the day the current trend and weakness were recorded
    public let ruleId: String?                 // set exactly when status == .matched
    public let action: NiggleAction?           // set exactly when status == .matched
    public let matchedRuleIds: [String]        // every matching rule, in the owner's order
    public let nextChange: NiggleTriageNextChange?
    public let ignoredUpdates: Int
}

public enum NiggleTriage {
    public static func evaluate(_ input: NiggleTriageInput) -> NiggleTriageResult
    /// 0 for watch, 1 for modify, 2 for seeProfessional.
    public static func severity(_ action: NiggleAction) -> Int
    /// True when the rule list is usable (step 2 of §7.1).
    public static func rulesAreValid(_ rules: [NiggleTriageRule]) -> Bool
}
```

The function sees no location, side, note or label: the text never leaves the app layer.

### 6.2 `CutStressTrend`

```swift
public struct CutStressNight {
    public let day: String
    public let restingHr: Double?     // bpm; nil: not measured
    public let hrv: Double?           // ms; nil: not measured
}

public struct CutStressInput {
    public let nights: [CutStressNight]
    public let firstWeekStart: String?   // a Monday; nil: start at the earliest admitted night
    public let today: String
    public let minNightsPerWeek: Int     // default 4
    public let maxWeeks: Int             // default 26
}

public struct CutStressWeek {
    public let weekStart: String
    public let restingHrMean: Double?    // nil: fewer than minNightsPerWeek nights ("not measured")
    public let restingHrNights: Int
    public let hrvMean: Double?
    public let hrvNights: Int
    public let isCurrentWeek: Bool
}

public struct CutStressChange {
    public let fromWeekStart: String
    public let toWeekStart: String
    public let from: Double
    public let to: Double
    public let delta: Double             // to minus from
}

public struct CutStressRejections {
    public let nonFinite: Int
    public let outOfRange: Int
    public let invalidDay: Int
    public let future: Int
    public let duplicateDay: Int
}

public enum CutStressInvalidInput: String { case today, firstWeekStart, parameters }

public struct CutStressResult {
    public let weeks: [CutStressWeek]    // contiguous, ascending; empty when nothing can be shown
    public let restingHrChange: CutStressChange?
    public let hrvChange: CutStressChange?
    public let rejections: CutStressRejections
    public let invalidInput: CutStressInvalidInput?
}

public enum CutStressTrend {
    public static func weekly(_ input: CutStressInput) -> CutStressResult
}
```

There is no state, tier, band, score or boolean "elevated" anywhere in the output, on purpose.

### 6.3 `CheckpointTimeline`

```swift
public enum TimelineItemKind: String, CaseIterable {
    case phaseStart, scan, checkpoint, dietBreak, deload, today, projection
}
public enum TimelineCheckpointCategory: String, CaseIterable {
    case scan, bloodPanel, benchmark, weightTarget, appointment, other
}
public enum TimelineSpanKind: String, CaseIterable { case dietBreak, deload }
public enum TimelineSourceState: String { case notBuilt, off, on }
public enum TimelinePosition: String { case past, current, upcoming }

public struct TimelinePhase {
    public let startDay: String
    public let isCut: Bool
    public let targetWeightKg: Double?
}
public struct TimelineCheckpoint {
    public let day: String
    public let isApproximate: Bool
    public let category: TimelineCheckpointCategory
    public let targetWeightKg: Double?   // only meaningful for weightTarget
    public let isDone: Bool
}
public struct TimelineSpan {
    public let kind: TimelineSpanKind
    public let startDay: String
    public let endDay: String?           // nil: open-ended
}
public struct TimelineProjection {
    public let status: CutScorecardProjectionStatus
    public let targetDay: String?
}

public struct CheckpointTimelineInput {
    public let phases: [TimelinePhase]
    public let checkpoints: [TimelineCheckpoint]
    public let scanDays: [String]
    public let spans: [TimelineSpan]
    public let projection: TimelineProjection?   // nil: the scorecard is off or not loaded
    public let scans: TimelineSourceState
    public let events: TimelineSourceState
    public let today: String
}

public struct TimelineItem {
    public let kind: TimelineItemKind
    public let day: String               // the sort day; a span's start
    public let endDay: String?           // spans only
    public let isOpenEnded: Bool         // a span with no end
    public let position: TimelinePosition
    public let sourceIndex: Int?         // index into the input array of this kind; nil for today and projection
    public let isApproximate: Bool
    public let isDone: Bool
    public let isEstimate: Bool          // true only for the projection
    public let category: TimelineCheckpointCategory?
    public let targetWeightKg: Double?
    public let phaseIsCut: Bool?
}

public struct TimelineRejections {
    public let invalidDay: Int
    public let endBeforeStart: Int
    public let futureScan: Int
    public let duplicate: Int
    public let nonFinite: Int
}

public struct CheckpointTimelineResult {
    public let items: [TimelineItem]     // the single list; ascending
    public let todayIndex: Int?          // index of the today item; nil exactly when invalid
    public let scans: TimelineSourceState
    public let events: TimelineSourceState
    public let rejections: TimelineRejections
    public let invalidToday: Bool
}

public enum CheckpointTimeline {
    public static func build(_ input: CheckpointTimelineInput) -> CheckpointTimelineResult
    /// phaseStart 0, scan 1, checkpoint 2, dietBreak 3, deload 4, today 5, projection 6.
    public static func kindOrder(_ kind: TimelineItemKind) -> Int
}
```

## 7. Algorithms

### 7.1 Triage

1. `today` not canonical: `invalidInput(.today)`. In every invalid result `isOpen` is false,
   `dayCount` nil, `currentTrend` and `currentWeakness` echo the complaint's own values, `stateDay`
   nil, no rule, `matchedRuleIds` empty, `nextChange` nil, `ignoredUpdates` 0.
2. Rules are valid when every `id` is non-empty, ids are unique, every `fromDay` that is set is at
   least 1, and every `throughDay` that is set is at least `fromDay ?? 1`. Otherwise
   `invalidInput(.rules)`. Duplicates inside `characters` or `trends` are harmless.
3. `onsetDay` not canonical: `.onsetDay`. After `today`: `.onsetAfterToday`. `resolvedDay` set and
   not canonical: `.resolvedDay`; before `onsetDay`: `.resolvedBeforeOnset`; after `today`:
   `.resolvedAfterToday`. Checked in that order, after steps 1 and 2.
4. An update is ignored, and counted once in `ignoredUpdates`, when its day is not canonical, is
   before `onsetDay`, is after `today`, or is after `resolvedDay`.
5. Current state: the kept update with the greatest `(day, sequence)`; among equals the later in
   input order. Its `trend`, `weakness` and `day` become `currentTrend`, `currentWeakness`,
   `stateDay`. With no kept update they are the complaint's own values and `onsetDay`.
6. Resolved: `status .resolved`, `isOpen false`, `dayCount = daysBetween(onsetDay, resolvedDay) + 1`,
   no rule, `matchedRuleIds` empty, `nextChange` nil.
7. Open: `n = daysBetween(onsetDay, today) + 1`. The onset day is day 1.
8. No rules: `status .noRulesEntered`, `dayCount n`, `nextChange` nil.
9. A rule **matches at** a day count `k` when all hold: `characters` is empty or contains the
   complaint's `character`; `trends` is empty or contains `currentTrend`; `weakness` is nil or equals
   `currentWeakness`; `k >= (fromDay ?? 1)`; `throughDay` is nil or `k <= throughDay`.
10. `matchedRuleIds` is every rule matching at `n`, in input order. The **winner at k** is the
    matching rule with the greatest `severity(action)`; among equals, the earliest in input order;
    none when nothing matches. Winner at `n` exists: `status .matched` with its id and action.
    Otherwise `.noRuleMatches`.
11. `nextChange`. Candidates are, for every rule whose three non-day conditions hold: `fromDay` when
    it is greater than `n`; and `throughDay + 1` when `throughDay >= n` and `throughDay < Int.max`.
    Take candidates in ascending order; the first `c` at which the winner at `c` differs from the
    winner at `n` (by rule id; "none" is a value) gives `nextChange(dayCount: c, day: key(number(onsetDay) + c - 1), ruleId, action)`.
    If that day would lie after 9999-12-31, or no candidate differs, `nextChange` is nil. It
    describes what the owner's rules say if nothing else is recorded; it predicts nothing.

Why severity and not first-match (decision D4): a complaint that fits a mild rule and has also
passed the owner's own threshold for a professional must show the professional rule, whatever order
the rules were typed in.

### 7.2 Weekly trend

1. `today` not canonical: `invalidInput .today`, empty result. `minNightsPerWeek < 1` or greater
   than 7, or `maxWeeks < 1`: `.parameters`. `firstWeekStart` set and not canonical, or not a Monday
   (`CanonicalDay.weekStart(x) != x`), or after `today`: `.firstWeekStart`.
2. A night is rejected whole, counted once in this order, when its day is not canonical
   (`invalidDay`) or after `today` (`future`). When several nights share a day the last in input
   order is kept and each earlier one counts as `duplicateDay`.
3. Per metric, a value is dropped when it is not finite (`nonFinite`) or outside the inclusive
   bounds of `Baselines.restingHRCfg` for resting heart rate and `Baselines.hrvCfg` for HRV
   (`Baselines.swift:251-252`) (`outOfRange`). These are the bounds `ChargeBaselines` and
   `HRVReadiness` already apply, so a decode artefact is excluded here exactly where it is there.
   The two metrics are judged independently; a night may count for one and not the other.
4. `last = weekStart(today)`. `bound = last − 7 × (maxWeeks − 1)` days. `start` is `firstWeekStart`
   when set, else the Monday of the earliest night that survived step 2 and has at least one
   admitted value; then `start = max(start, bound)`. With no such night and no `firstWeekStart`,
   `weeks` is empty.
5. `weeks` is every Monday from `start` to `last`. A night belongs to the week of
   `CanonicalDay.weekStart(day)`; nights before `start` are unused and not counted as rejected.
6. Per week and metric: `nights` is the count of admitted values; the mean is
   `CutScorecard.quantize(sum ÷ nights)` when `nights >= minNightsPerWeek`, else nil.
   `isCurrentWeek` is true only for `last`.
7. Per metric, `change` is set when at least two different weeks have a mean: `from` is the earliest
   such week and `to` the latest; `delta = quantize(to − from)`.

The week is the Monday week of `DailyMetric.day`, the same week key the scorecard's curves use
(`CutScorecard.weekStart`), so the three curves on the two screens share one time axis.

### 7.3 Timeline

1. `today` not canonical: `invalidToday true`, empty `items`, `todayIndex` nil; `scans` and `events`
   echo the input.
2. Phases: one `phaseStart` item per phase with a canonical `startDay`, carrying `phaseIsCut`,
   `targetWeightKg` (dropped to nil and counted `nonFinite` when not finite or not positive), and
   `sourceIndex`. A non-canonical day counts `invalidDay`.
3. Scan days: used only when `scans == .on`. Non-canonical: `invalidDay`. After `today`:
   `futureScan`. A repeat of a day already taken: `duplicate`. `sourceIndex` is the index of the
   first occurrence.
4. Checkpoints: one `checkpoint` item each (canonical day required). A checkpoint of category
   `scan` whose day equals a kept scan day is dropped and counted `duplicate`: the recorded scan
   stands for it. `targetWeightKg` is carried only for `weightTarget` and only when finite and
   positive.
5. Spans: used only when `events == .on`. `startDay` must be canonical; `endDay`, when set, must be
   canonical and not before `startDay` (`endBeforeStart`). `isOpenEnded` is `endDay == nil`.
6. Projection: one item, `isEstimate true`, only when `projection.status == .projected` and
   `targetDay` is canonical. Any other status yields no item (the scorecard screen explains those).
7. One `today` item, always.
8. Position. Dated items: `past` when `day < today`, `current` when equal, `upcoming` when greater.
   Spans: `upcoming` when `startDay > today`; `past` when `endDay` is set and before `today`;
   otherwise `current`.
9. Order: ascending by `(number(day), kindOrder(kind), sourceIndex ?? 0)`. So on one day a phase
   start precedes a scan, the today marker follows that day's dated items, and the projection is
   last.
10. `todayIndex` is the index of the `today` item.

This list is the only one. The view draws it in order and derives its three headings from
`position`; nothing else assembles timeline rows.

## 8. One number per variable (R41) and no new score

### 8.1 The rule for this stage

| Fact | Single source | Who reads it in stage 6 | How it is corrected |
|---|---|---|---|
| A niggle's label and day count | `NiggleTriage.evaluate`, called only by `NiggleLogModel` | Log rows, detail screen, the Health row's count | Editing the niggle, adding an update, or editing the rules, from the same screens |
| The professional rule text | `NiggleLogSettings.rules.professionalRule` | Log header, detail screen | The rules sheet |
| Paused exercises | `NiggleLogSettings.paused` | Log section, a linked niggle's detail | The paused sheet |
| Weekly resting heart rate and HRV means | `CutStressTrend.weekly`, called only by `CutStressModel`, over `Repository.days` | The cut-stress screen only | Not correctable: a measured series. The screen links to the existing metric pages |
| Typical range | `ChargeTypicalBand.range` over `Repository.chargeBaselines` | Recovery detail (existing) and the cut-stress screen | Not correctable |
| Phase start and target weight | `CutScorecardSettings.phases` | Scorecard (existing), timeline | The existing phase sheet, opened from the timeline item |
| Projection day | The shared `CutScorecardModel`'s evaluation | Scorecard (existing), timeline | The weigh-in sheet and history, opened from the timeline item |
| Scan days | Stage 4's read (A1) through `TimelineScanSource` | Timeline | Stage 4's screen, opened from the item |
| Diet breaks and deloads | Stage 5's read (A3) through `TimelineEventSource` | Timeline | Stage 5's screen, opened from the item |
| Checkpoints | `CheckpointTimelineSettings.checkpoints` | Timeline | The checkpoint sheet |

### 8.2 Part (b) adds no score and feeds none

- The screen shows, per metric: a curve of weekly means; the latest week's mean with its night
  count; the earliest shown week's mean; the difference as a signed number; and the typical range
  as text. No adjective, no arrow that means good or bad, no colour other than the neutral primary
  text colour, no band on the chart.
- It shows **no current value**. The night's value stays on Today, Health and Recovery detail, so
  there is nothing here for those to disagree with. A weekly mean is labelled "week average".
- The typical range moves from the local function at `ScoreDetailData.swift:156-160` to
  `ChargeTypicalBand.range(_ state: BaselineState?) -> ClosedRange<Double>?` with the same body.
  Recovery detail calls it; the cut-stress presenter calls it. No formula changes.
- The framing sentence on the screen is fixed (§11): it says the figures are context for the coach
  and are not used by any score.
- Enforced by test (§12.4): `CutStressTrend` and `CutStressModel` are referenced only from their
  own files, the cut-stress view, the routes file and the demo; never from `IntelligenceEngine`,
  the scorers, `CutScorecard*`, `AICoach`, a widget, a notification or a backup.
- Disposition under the derived-signal rule: a weekly arithmetic mean of nightly values the app
  already stores and shows is not a new physiological signal derived from raw sensor data. It still
  ships behind a default-off setting and stays out of every gate until the owner asks otherwise.

### 8.3 The scorecard's evaluation

`CutScorecardModel` gains one property, set in `load()` in the same step that sets `state`, and
cleared to nil wherever `state` becomes `.idle`:

```swift
/// The evaluation behind the published presentation. Nil while idle or before the first result.
private(set) var evaluation: CutScorecardEvaluation?
```

`CheckpointTimelineModel` reads `CutScorecardModel.live(...).evaluation?.result.projection` after
awaiting that model's `load()`. It never builds a `CutScorecardInput`. If stage 2 has already added
an equivalent accessor (A7), that one is used and this property is not added.

## 9. Storage

### 9.1 The decision

Niggles, rules, paused exercises and checkpoints are **settings strings in `UserDefaults.standard`**,
in the style of stage 1's phases-as-settings (`CutScorecardSettings.swift:106-117`). Not Lab Book
rows, not the `event` table, not a new table.

| Option | Verdict | Reason |
|---|---|---|
| Settings strings | **Chosen** | No strap id anywhere, so R42 holds by construction: removing, forgetting or deleting a strap cannot touch them. No migration. Round-trips in a backup as String kinds (precedent: `today.hostedCards`, `cutScorecard.phases`). The lists are small and owner-authored, like phases |
| `labMarker` rows | Rejected | Rows are keyed by strap id and are today cleared by a strap delete (`DeviceRegistryStore.swift:166-173`) until the separate ownership change lands. A complaint is not a numeric reading: it has an onset, an end, updates and flags that the row shape (`value`, `unit`, `note`) cannot hold without overloading text columns |
| `event` table | Rejected | Strap stream storage (§3, C4) |
| A new table | Not needed | It would need a migration and the owner's go-ahead. Kept as the documented alternative if a list ever outgrows the limits in §9.2 |

Rules that apply to all four strings, copied from stage 1 (R30 and `CutScorecardSettings.swift:119-137`):

- Written with sorted keys; every element carries `"v":1`; optional fields are omitted when nil.
- Read on every access; nothing cached. **Reading never writes.**
- A stored value that is not a string, does not parse, or has one unreadable element makes the
  whole list read as empty and sets that list's `…NeedAttention` to true. While it is true every
  save to that key is refused, so an unreadable log is never replaced by an empty one. The owner's
  explicit "Discard unreadable data" action removes the key, only while it is unreadable.
- Ids are `"<prefix>-<8 lowercase hex>"`, generated by the store; `n` niggles, `r` rules, `p` paused,
  `c` checkpoints.
- Text is trimmed of leading and trailing whitespace and newlines before saving.

### 9.2 Niggle log

`niggleLog.entries`, element:

```json
{"character":"positional","id":"n-0a1b2c3d","kind":"complaint","location":"Fixture knee","note":"Fixture note","onsetDay":"2031-03-03","side":"right","trend":"unchanged","updates":[{"day":"2031-03-10","note":"","seq":1,"trend":"worsening","weakness":false}],"v":1,"weakness":false}
```

| Field | Type | Rule |
|---|---|---|
| `kind` | `complaint` or `observation` | An observation is a standing note (for example a side difference): it has `location`, `side`, `note` and `onsetDay` ("noted on"); it is never triaged and has no day count |
| `location` | String | Required, 1 to 60 characters |
| `side` | `left`, `right`, `both`, `notApplicable` | Required |
| `character` | a `NiggleCharacter` raw value | Complaints only; observations store `other` |
| `onsetDay` | day key | Not after today at the time of saving |
| `resolvedDay` | day key, optional | Not before `onsetDay`, not after today |
| `trend`, `weakness` | as recorded at onset | |
| `updates` | array, at most 100 | `seq` is 1 + the greatest `seq` in the entry, assigned by the store |
| `note` | String | At most 500 characters; may be empty |

At most 500 entries; a save beyond a limit is refused with a message, never truncated.

`niggleLog.rules`:

```json
{"professionalRule":"Fixture rule: book a fixture review after 20 days, or sooner if it worsens.","rules":[{"action":"watch","characters":["diffuse"],"fromDay":1,"id":"r-00000001","label":"Fixture label A","note":"","throughDay":5,"trends":["easing"]}],"v":1}
```

A stored rule is a `NiggleTriageRule` plus `label` (required, 1 to 40 characters, the owner's own
name for the outcome) and `note` (at most 200, the owner's own words for what they do).
`professionalRule` is at most 300 characters and may be empty. At most 20 rules. A rule list that
fails `NiggleTriage.rulesAreValid` is unreadable in the sense of §9.1.

**There are no default rules.** With nothing stored, the list is empty and every complaint shows
"No rules entered yet". A shipped default would be the app's opinion about a complaint; the owner's
rules are the only ones the app applies (decision D3).

`niggleLog.paused`, element:

```json
{"exercise":"Fixture Hinge","id":"p-0000000a","niggleId":"n-0a1b2c3d","pausedDay":"2031-03-05","reason":"Linked to the fixture knee","until":"Until a fixture review","v":1}
```

`exercise` 1 to 60 characters; `reason` 1 to 200, required, because the roadmap requires the reason
to be listed; `until` at most 100, optional; `niggleId` optional, and when its niggle no longer
exists the pause is shown without a link; `resumedDay` optional, not before `pausedDay`. At most 100.

Operations in `NiggleLogSettings`, all synchronous, each returning whether it saved:
`save(_ niggle:)` (insert or replace by id), `delete(niggleId:)`, `resolve(niggleId:on:)`,
`reopen(niggleId:)`, `addUpdate(niggleId:day:trend:weakness:note:)`, `deleteUpdate(niggleId:seq:)`,
`saveRules(_:)`, `save(_ paused:)`, `resume(pausedId:on:)`, `delete(pausedId:)`, and the three
`discardUnreadable…()` actions. Deleting a niggle leaves its paused exercises in place, unlinked.

### 9.3 Checkpoints

`timeline.checkpoints`, element:

```json
{"approximate":true,"category":"weightTarget","day":"2031-04-14","done":false,"id":"c-000000a1","targetWeightKg":96.0,"title":"Fixture waypoint","v":1}
```

`title` 1 to 60 characters; `day` any canonical day, past or future; `approximate` marks a date the
owner has only roughly fixed and is shown as "around"; `targetWeightKg` only with `weightTarget`,
in kilograms, converted from the display unit with the constants stage 1 uses; at most 200.
Operations: `save(_:)`, `delete(id:)`, `setDone(id:_:)`, `discardUnreadableCheckpoints()`.

### 9.4 Flags

| Key | Default | Off means |
|---|---|---|
| `noop.niggleLogEnabled` | `false` | No Health row, no screens, nothing read |
| `noop.cutStressEnabled` | `false` | No link on the scorecard, no screen, nothing computed |
| `noop.checkpointTimelineEnabled` | `false` | No link on the scorecard, no Health row, no screen, nothing read |

The cut-stress screen is reachable only from the scorecard, so it also needs
`noop.cutScorecardEnabled`. The timeline works without the scorecard flag (it then has no projection
item, and phases still show). Each flag is observed through one `ObservableDefaultsFlag(key:)`
instance held as a static on its settings type; the class is the body of `CutScorecardFlag`
(`CutScorecardModel.swift:18-63`) with the key as a parameter. `CutScorecardFlag` itself is not
changed. Switching a flag off deletes nothing.

### 9.5 Backup

| Canonical key | Kind | Swift storage key | Joins the Swift whitelist |
|---|---|---|---|
| `niggleLog.entries` | String | same | Yes (recommendation; §15, Q1) |
| `niggleLog.rules` | String | same | Yes |
| `niggleLog.paused` | String | same | Yes |
| `timeline.checkpoints` | String | same | Yes |
| the three `noop.*` flags | — | — | No: per install, as the whitelist's rule says (`BackupSettings.swift:40-42`) |

Edits: `BackupSettings.whitelist` and `appleDefaultsKey` (`BackupSettings.swift:49-76`, `:82-97`),
four lines each. Without the four keys a restore would silently lose the log, which is the outcome
R42 exists to prevent.

**Kotlin side: not updated, by the owner's decision (R43).** The exact drift this creates:
`BackupSettingsCodec.WHITELIST` (`android/app/src/main/java/com/noop/data/BackupSettings.kt`) lacks
the four keys, so (1) a backup made on the iPhone and restored on Android drops them, as unknown
keys are dropped; (2) a backup made on Android never carries them; (3) restoring an Android-made
backup on the iPhone leaves the four stored strings as they were, because restore writes only keys
present in the file (`BackupSettings.swift:119-126`). This joins the pre-existing drift noted in
stage 1 (C10). No marker-catalogue entry is added by this stage, so that contract does not move.

Sensitivity: the whitelist's header asks that `settings.json` stay safe to share
(`BackupSettings.swift:11-15`). The backup's database already holds blood results and weights; a
complaint log is the same class of data, and the backup remains unencrypted (CONTEXT §7 item 7).
That is why inclusion is put to the owner as Q1, with exclusion of `niggleLog.entries` as the
alternative.

## 10. Screens and states

Frames are designed at G1 (round 11 by assumption A11). Every state below needs a frame at the
default text size; every screen needs one at `accessibility5` (`StrandiOSApp.swift:247`). Shared
components: `NoopGlassCard` (`NoopSurfaces.swift:68`), `NoopListRow` (`NoopRows.swift:258`),
`ScorecardSectionHeader`, `ScorecardFootnote`, `ScorecardLinkRow`, `ScorecardSkeletonLines`,
`ScorecardDangerButton` (`StrandiOS/Scorecard/ScorecardKit.swift:205`, `:300`, `:316`, `:353`,
`:370`), `ScorecardWeekChart`. Tokens only. Action colours follow stage 1's approval record (§17
there): red is for Delete only. A label's action is shown as text, never as red, amber or green
(decision D6).

### 10.1 Entry points

| Where | Row | Shown when |
|---|---|---|
| Health tab, "More health" card (`RedesignHealthView.swift:472-482`) | "Niggle log", detail = open count or nothing | `noop.niggleLogEnabled` |
| Same card | "Timeline", detail = next upcoming item's date or nothing | `noop.checkpointTimelineEnabled` |
| Scorecard screen links card (`ScorecardView.swift:548-559`) | "Recovery context" | `noop.cutStressEnabled` |
| Same card | "Timeline" | `noop.checkpointTimelineEnabled` |
| Settings | One section "Log and timeline" with three toggles | Always on iPhone; macOS does not show it |

With all three flags off the Health card, the scorecard links card and every other screen are
exactly as before.

### 10.2 Niggle log screen

Sections: the professional rule; open complaints; paused exercises; observations; resolved.

| State | What shows |
|---|---|
| Loading | Skeleton lines per section |
| First use, nothing stored | One explanation, "Log a niggle" (primary), "Set up your rules" |
| No rules entered | Header reads "No rules entered yet" with "Set up your rules"; each open row shows its day count and "No rules entered yet" |
| Rules entered, professional rule empty | Header shows "You have not written a rule for seeing a professional" with a link to the rules sheet |
| Open complaint, rule matched | Location and side; "Day n"; the owner's label; the action as plain text |
| Open complaint, no rule matches | "Day n"; "None of your rules covers this" |
| Open complaint with a next change | A second line: "Day k: your rule “<label>” applies" or "Day k: no rule of yours applies" |
| Open complaint seen again | "Logged before: m times" when earlier entries share the same location (case-insensitive, trimmed) and side |
| Several open | Sorted by action severity descending, then day count descending, then location |
| Paused exercises | Exercise, reason, "since <date>", and the `until` text when set |
| No paused exercises | The section is absent |
| Resumed exercises | Under a disclosure, "Resumed <date>" |
| Observations | Location, side, note, "noted <date>" |
| Resolved | Under a disclosure; "Resolved after n days" and the dates; no label |
| Entries need attention | "Your log could not be read. Nothing has been changed." with "Discard unreadable data"; adding is disabled |
| Rules need attention | The same shape for rules; complaints show day counts and "Your rules need attention" |
| Limit reached | Adding is disabled with the limit named |
| Largest text size | Rows stack: location, then day count, then label; nothing truncates a number |
| Reduce Motion | No staggered entrance |

### 10.3 Niggle detail

| State | What shows |
|---|---|
| Open, matched | Day count; the label; the action text; the owner's rule note; "Your rule, applied to what you logged. This is not a diagnosis."; other matching rules listed by label; the next change; updates newest first; linked paused exercises; the professional rule verbatim; actions "Add update", "Mark resolved", "Edit", "Delete" |
| Open, no rule matches / no rules entered / rules need attention | The same layout with the matching line of §11 in place of the label |
| Resolved | "Resolved after n days"; dates; updates; "Reopen", "Edit", "Delete" |
| Observation | Note and date; "Edit", "Delete"; no triage area |
| Updates ignored | A footnote: "m updates are dated outside this complaint and were not used" |
| Delete | Asks once; on confirmation the entry goes and linked pauses lose their link |
| Entry no longer exists (deleted elsewhere) | The screen pops |

### 10.4 Niggle sheet (add, edit, update)

| State | Behaviour |
|---|---|
| Add | Kind (complaint or observation); location (focused); side; character with one line of meaning each; how it is changing; "Any weakness" toggle; onset date defaulting to today, no future date; note |
| Add an observation | Location, side, date, note only |
| Invalid | Empty location, or over a length limit: "Save" disabled and the field says why |
| Edit | Current values; changing the onset to after an update's day is allowed and that update is then ignored and footnoted, never deleted |
| Add update | Date (onset to today), how it is changing, weakness, note |
| Mark resolved | A date from onset to today, defaulting to today |
| Saving / save refused | Inputs captured before the write; a refused save (limit or unreadable store) keeps the sheet open with the values intact and the reason |

### 10.5 Rules sheet

| State | Behaviour |
|---|---|
| First use | The professional-rule text field, empty, with the caption "Write it in your own words. The app shows it back to you and does nothing else with it."; an empty rule list; "Add a rule" |
| A rule | Label; action (three choices, in words); which characters (none selected means any); which changes (none means any); weakness (either, with, without); from day; through day; note |
| A preview line per rule | A sentence built from the rule's fields (§11), so the owner can read back what they entered |
| Reorder | Drag to reorder; order only breaks ties between equal actions, and the sheet says so |
| Invalid | `fromDay` below 1, `throughDay` below `fromDay`, an empty label: marked, "Save" disabled |
| Delete a rule | Asks once |
| Limit | "Add a rule" disabled at 20 |

### 10.6 Paused exercise sheet

Add or edit: exercise, reason (required), until (optional), paused date, optional link to an open
niggle; "Mark resumed" with a date; delete asks once. Invalid: empty exercise or reason.

### 10.7 Cut-stress screen ("Recovery context")

| State | What shows |
|---|---|
| Loading | Skeleton for the framing line and both cards |
| Default | The framing sentence; a card per metric: weekly curve (`ScorecardWeekChart`, neutral colour), "Latest week average" with "n of 7 nights", "First week shown" with its value, the signed change, and "Your typical range" as text |
| Current week below the minimum | The curve ends at the last full week; "This week so far: n nights. A weekly average needs 4." |
| Current week at or above the minimum | Its mean is shown and labelled "this week so far" |
| A week below the minimum in the middle | The line breaks at that week; never drawn across |
| Only one week has a mean | That value; no change line; "Needs a second week" |
| No week has a mean | "Not measured yet" with the night counts; no curve |
| No nights at all | "Not measured yet. These come from nights recorded by your strap." |
| Typical range not available (baseline not usable) | "Typical range: still calibrating" |
| HRV present, resting heart rate absent (or the reverse) | Each card stands alone |
| No cut phase started | Weeks are the latest 12; the header says so |
| Phase started | Weeks from the phase's first week, at most 26 |
| Strap disconnected or removed | Stored nights still show; later weeks read "not measured" |
| Scorecard flag off | The screen is unreachable; a restored route pops |
| Largest text size | Value rows stack label over value; curves keep their height |
| Reduce Motion | No curve reveal |

No horizontal rule, band or typical-range shading on either curve.

### 10.8 Timeline screen

One list, oldest first, opened scrolled to the today marker.

| State | What shows |
|---|---|
| Loading | Skeleton rows |
| Nothing but today | "Nothing on your timeline yet" with "Add a checkpoint" and, when no phase exists and the scorecard is on, "Set up your phase" |
| Phase start | The phase name, "started <date>" or "starts <date>", and "Target <weight>" when set |
| Checkpoint, upcoming | Title, date ("around <date>" when approximate), category, target weight when present |
| Checkpoint, past, done | The same, marked done |
| Checkpoint, past, not done | The same with "Not marked done". No red, no "overdue", no count |
| Scan | "Scan" and the date; opens stage 4's screen |
| Diet break / deload, past | Kind and "<start> to <end>" |
| Diet break / deload, current | "Since <start>" or "<start> to <end>", placed before the today marker by its start day and tagged "now" |
| Diet break / deload, open-ended | "Since <start>" |
| Projection | "Estimated <date> at this rate" and the target weight; tagged "estimate"; opens the scorecard |
| No projection | No item; nothing is said (the scorecard explains why) |
| Scans: stage 4 not in this build (`notBuilt`) | No scan items and no mention |
| Scans: stage 4 present, its setting off (`off`) | No scan items; one footnote: "Scans are not shown while the body record is off" |
| Events: `notBuilt` / `off` | As for scans, with "Breaks and deloads are not shown while events are off" |
| Scorecard flag off | Phases still show; no projection item; a footnote: "No estimate while the scorecard is off" |
| Checkpoints need attention | The banner of §10.2's shape; adding disabled; other items still show |
| Phases need attention (`phasesNeedAttention`) | No phase items; a footnote linking to the phase sheet |
| Largest text size | Date above title; nothing truncates a date |
| Reduce Motion | No staggered entrance |

The time axis is the list itself. No horizontal rule or band is drawn; a span is a row, not a bar
across other rows.

Checkpoint sheet: title, category, date, "approximate" toggle, target weight (only for the weight
target category, in the display unit), "done" toggle (only when the date is today or earlier);
delete asks once; invalid: empty title, or a target weight outside stage 1's 30–250 kg range.

### 10.9 Widgets and notifications

**None.** Stage 6 adds no widget, no widget payload field, no notification request and no Shortcuts
action. The notification count is unchanged. A complaint log is of the sensitive kind stage 5's
roadmap entry keeps out of widgets and notifications; the test in §12.3 asserts no stage 6 string
or stored key is read by the widget publish path or by any `UNNotification` request.

## 11. User-facing strings

Built by the three presenters through the String Catalog, ten locales. The owner's own text (labels,
notes, the professional rule, locations, titles, exercises, reasons) is shown verbatim and is never
translated, capitalised or shortened. English sources:

| Case | String |
|---|---|
| Health rows | "Niggle log", "Timeline"; details "%lld open", "Next: %@" |
| Scorecard links | "Recovery context", "Timeline" |
| Settings | "Log and timeline"; "Niggle log" / "Record a complaint and see it against your own rules. Off by default."; "Recovery context" / "Weekly resting heart rate and HRV beside the scorecard. Not a score."; "Timeline" / "Phases, checkpoints and your estimate in one list."; "Everything stays on this iPhone." |
| Log sections | "Your rule for seeing a professional", "Open", "Paused by your coach", "Observations", "Resolved" |
| Day count | "Day %lld", "Resolved after %lld days", "noted %@", "since %@", "Resumed %@" |
| Action words | "Watch", "Modify training", "See a professional" |
| Triage lines | "None of your rules covers this", "No rules entered yet", "Your rules need attention", "Day %lld: your rule “%@” applies", "Day %lld: no rule of yours applies", "Also matches: %@", "Logged before: %lld times" |
| Under every label | "Your rule, applied to what you logged. This is not a diagnosis." |
| Professional rule empty | "You have not written a rule for seeing a professional" |
| Rules sheet caption | "Write it in your own words. The app shows it back to you and does nothing else with it." |
| Rule preview parts | "Any complaint", "%@ complaints", "that is %@", "with weakness", "without weakness", "from day %lld", "through day %lld", "is labelled “%@”" |
| Tie note | "When two rules with the same action both apply, the higher one in this list is shown." |
| Characters | "Spread over an area", "One spot", "Only in one position or movement", "Something else" |
| Changes | "Easing", "No change", "Getting worse", "Not recorded" |
| Sides | "Left", "Right", "Both", "Not applicable" |
| Actions | "Log a niggle", "Set up your rules", "Add update", "Mark resolved", "Reopen", "Add a rule", "Pause an exercise", "Mark resumed", "Add a checkpoint", "Discard unreadable data" |
| Attention | "Your log could not be read. Nothing has been changed.", "Your rules could not be read. Nothing has been changed.", "Your checkpoints could not be read. Nothing has been changed." |
| Ignored updates | "%lld updates are dated outside this complaint and were not used" |
| Limits | "The log holds up to %lld entries" (and the same shape for rules, pauses, checkpoints) |
| Cut-stress framing | "Weekly averages of your nightly resting heart rate and HRV, as context for your coach. They are not a score and no score uses them." |
| Cut-stress rows | "Resting heart rate", "HRV", "Latest week average", "this week so far", "First week shown", "Change", "%lld of 7 nights", "Your typical range", "%@ to %@", "Typical range: still calibrating", "Needs a second week", "Not measured yet", "Not measured yet. These come from nights recorded by your strap.", "This week so far: %lld nights. A weekly average needs %lld.", "Last 12 weeks", "Since %@" |
| Timeline headings | "Earlier", "Today", "Ahead" |
| Timeline items | "%@ started %@", "%@ starts %@", "Target %@", "around %@", "Scan", "Diet break", "Deload", "%@ to %@", "Since %@", "now", "Estimated %@ at this rate", "estimate", "Not marked done", "Done" |
| Checkpoint categories | "Scan", "Blood panel", "Benchmark", "Weight target", "Appointment", "Other" |
| Timeline footnotes | "Scans are not shown while the body record is off", "Breaks and deloads are not shown while events are off", "No estimate while the scorecard is off", "Nothing on your timeline yet" |

None of these states or implies a cause, a prognosis or a treatment. "See a professional" appears
only as the name of an action the owner assigned to their own rule. "Estimated" and "estimate" mark
the projection.

## 12. Test plan

One named test per line.

### 12.1 Pure logic — `Packages/StrandAnalytics/Tests/StrandAnalyticsTests/`

`CanonicalDayTests.swift`

- `testCanonicalKeysRoundTripThroughNumber`
- `testLooseAndOutOfRangeKeysAreNil`
- `testValidityAgreesWithCutScorecardWeekStartOverASpread`
- `testWeekStartAgreesWithCutScorecardWeekStart`
- `testDaysBetweenAcrossMonthYearAndLeapDay`
- `testKeyClampsBelowYearOneAndAboveYear9999`

`NiggleTriageTests.swift`

- `testOnsetDayIsDayOne`
- `testDayCountAcrossAMonthAndALeapDay`
- `testNoRulesEnteredReportsDayCountAndNoLabel`
- `testNoRuleMatchesWhenCharacterDiffers`
- `testEmptyCharactersAndTrendsMatchAnything`
- `testFromDayIsInclusive` / `testOneDayBeforeFromDayDoesNotMatch`
- `testThroughDayIsInclusive` / `testOneDayAfterThroughDayDoesNotMatch`
- `testHigherSeverityWinsWhateverTheOrder`
- `testEqualSeverityTakesTheEarlierRule`
- `testMatchedRuleIdsListsEveryMatchInOwnerOrder`
- `testWeaknessNilMatchesBoth` / `testWeaknessTrueRequiresWeakness` / `testWeaknessFalseExcludesWeakness`
- `testLatestUpdateSuppliesTrendAndWeakness`
- `testUpdatesOnTheSameDayUseTheGreaterSequence`
- `testUpdateAfterTodayIsIgnoredAndCounted`
- `testUpdateBeforeOnsetIsIgnoredAndCounted`
- `testUpdateAfterResolvedDayIsIgnoredAndCounted`
- `testNotRecordedTrendDoesNotMatchARuleNamingTrends`
- `testResolvedReportsDurationAndNoRule`
- `testResolvedOnTheOnsetDayIsOneDay`
- `testNextChangeIsTheFirstDayTheWinnerDiffers`
- `testNextChangeWhenAWindowEndsWithNothingAfter`
- `testNextChangeSkipsACandidateThatKeepsTheWinner`
- `testNextChangeIsNilWhenNothingWillChange`
- `testNextChangeIgnoresRulesWhoseOtherConditionsFail`
- `testThroughDayIntMaxDoesNotOverflow`
- `testNextChangeBeyondYear9999IsNil`
- `testInvalidTodayOnsetAndResolvedEachReportTheirCause`
- `testInvalidOrderIsTodayThenRulesThenComplaint`
- `testDuplicateOrEmptyRuleIdsAreInvalid`
- `testFromDayBelowOneAndThroughBeforeFromAreInvalid`
- `testFixtureComplaintsGiveTheExpectedTable` (§13.2)
- `testSameInputSameOutput`
- `testChangingEachRuleFieldChangesTheOutcomeItGoverns`

`CutStressTrendTests.swift`

- `testEmptyNightsAndNoFirstWeekGiveNoWeeks`
- `testWeeksAreContiguousFromFirstWeekToTodaysWeek`
- `testWeekBelowTheMinimumHasNoMeanButReportsItsNights`
- `testWeekAtExactlyTheMinimumHasAMean`
- `testMeanIsQuantizedToThreeDecimals`
- `testMetricsAreCountedIndependently`
- `testOutOfRangeAndNonFiniteValuesAreDroppedAndCounted`
- `testBoundsAreTheBaselineConfigsInclusive`
- `testFutureAndInvalidDaysAreRejected`
- `testDuplicateDayKeepsTheLast`
- `testSundayAndMondayFallInDifferentWeeks`
- `testCurrentWeekIsFlaggedAndFollowsTheSameMinimum`
- `testChangeRunsFromEarliestToLatestWeekWithAMean`
- `testChangeIsNilWithOneMean`
- `testFirstWeekEarlierThanMaxWeeksIsClamped`
- `testNilFirstWeekStartsAtTheEarliestAdmittedNight`
- `testFirstWeekNotAMondayIsInvalid` / `testFirstWeekAfterTodayIsInvalid`
- `testInvalidParametersAndToday`
- `testNightsBeforeTheFirstWeekAreUnusedAndNotRejected`
- `testFixtureWeeksGiveTheExpectedTable` (§13.3)
- `testAddingANightOutsideTheShownWeeksChangesNothing`
- `testResultHasNoStateOrTierField` (a mirror-based check that no property name contains "state",
  "tier", "band", "score", "elevated" or "suppressed")

`CheckpointTimelineTests.swift`

- `testOnlyTodayWhenEverythingIsEmpty`
- `testItemsAreAscendingByDayThenKindThenIndex`
- `testTodayMarkerFollowsItemsDatedToday`
- `testProjectionIsLastOnItsDayAndMarkedEstimate`
- `testProjectionAppearsOnlyWhenProjected` (one assertion per other status)
- `testNilProjectionYieldsNoItem`
- `testScansAreIgnoredUnlessTheSourceIsOn` / `testSpansAreIgnoredUnlessTheSourceIsOn`
- `testSourceStatesAreEchoed`
- `testFutureScanDayIsRejected`
- `testRepeatedScanDayIsCountedOnce`
- `testScanCheckpointOnARecordedScanDayIsDropped`
- `testScanCheckpointOnAnotherDayIsKept`
- `testSpanPositions` (before, ending yesterday, ending today, spanning today, starting today,
  starting tomorrow, open-ended in the past, open-ended in the future, zero-length)
- `testSpanEndingBeforeItStartsIsRejected`
- `testCheckpointPositionsAndFlagsAreCarried`
- `testTargetWeightIsCarriedOnlyForWeightTargets`
- `testNonFiniteTargetWeightIsDroppedAndCounted`
- `testInvalidDaysAreRejectedPerKind`
- `testInvalidTodayGivesAnEmptyList`
- `testFixtureTimelineGivesTheExpectedList` (§13.4, at three values of today)
- `testSameInputSameOutput`

### 12.2 Store — `Packages/WhoopStore/Tests/WhoopStoreTests/BackupSettingsTests.swift` (extended)

- `testStage6ListsRoundTripAsStrings`
- `testStage6FlagsAreNotExported`
- `testRestoreWithoutStage6KeysLeavesStoredListsUntouched`

### 12.3 App target — `StrandTests/`

`NiggleLogSettingsTests.swift`

- `testFlagDefaultsToOff`
- `testEntriesRoundTripWithSortedKeysAndVersion`
- `testReadingNeverWrites`
- `testUnreadableEntriesReadAsEmptyAndNeedAttention`
- `testSaveIsRefusedWhileEntriesNeedAttention`
- `testDiscardRemovesOnlyUnreadableData`
- `testOneUnreadableElementMakesTheWholeListUnreadable`
- `testSaveReplacesById` / `testDeleteRemovesOnlyThatEntry`
- `testResolveAndReopen`
- `testAddUpdateAssignsTheNextSequence`
- `testLimitsRefuseAndNeverTruncate`
- `testTextIsTrimmedAndEmptyLocationRefused`
- `testFutureOnsetIsRefused` / `testResolvedBeforeOnsetIsRefused`
- `testRulesRoundTripAndInvalidRulesNeedAttention`
- `testNoRulesAreStoredByDefault`
- `testPausedRoundTripResumeAndDelete`
- `testDeletingANiggleUnlinksItsPausedExercises`
- `testStoredStringsContainNoDeviceIdentifier` (R42: the encoded JSON of a full fixture has no key
  named `deviceId` and none of the repository's strap ids)
- `testRemovingEveryRegisteredStrapLeavesTheLogReadable` (R42: build a store, register and delete a
  strap's data through `DeviceRegistryStore`, assert all four lists are unchanged)

`NiggleLogModelTests.swift` and `NiggleLogPresenterTests.swift` — one test per row of §10.2 and
§10.3, named for the state; plus

- `testFlagOffReadsNothingAndPublishesIdle`
- `testOpenRowsSortBySeverityThenDayCount`
- `testRecurrenceCountsEarlierEntriesWithTheSameLocationAndSide`
- `testObservationsAreNeverTriaged`
- `testOwnerTextIsShownVerbatim`
- `testEveryLabelCarriesTheNotADiagnosisLine`
- `testNoPresenterStringNamesACauseOrTreatment` (scans every English source string of §11 against a
  word list: diagnos- outside the fixed disclaimer, injur-, tendon, strain, sprain, tear, treat-,
  rest it, ice, should)
- `testNoStateRendersAMissingValueAsZero`
- `testTodayIsCapturedOncePerLoad`

`CutStressModelTests.swift`, `CutStressPresenterTests.swift` — one test per row of §10.7; plus

- `testFlagOffComputesNothing`
- `testNightsComeFromRepositoryDays`
- `testWeeksStartAtThePhaseWeekWhenACutPhaseHasStarted` / `testLastTwelveWeeksWithoutAPhase`
- `testTypicalRangeEqualsRecoveryDetailsRange` (single resolver: the same `BaselineState` through
  `ChargeTypicalBand.range` and through `RecoveryDetailModel`'s factor gives one range)
- `testNoStringCarriesAJudgementWord` (elevated, suppressed, high, low, good, bad, warning, stress
  outside the fixed framing sentence)
- `testNightCountsAreShownBesideEveryMean`
- `testWeekBelowMinimumIsNotMeasuredNeverZero`

`CheckpointTimelineSettingsTests.swift` — the storage tests of the niggle settings, for checkpoints.

`CheckpointTimelineModelTests.swift`, `CheckpointTimelinePresenterTests.swift` — one test per row
of §10.8; plus

- `testProjectionDayEqualsTheScorecardModelsProjectionDay` (single resolver: one store, one shared
  `CutScorecardModel`; the timeline item's day equals `evaluation.result.projection.targetDay`)
- `testTimelineNeverEvaluatesTheScorecardItself` (an injected evaluator counts calls: one)
- `testPhaseItemsEqualStoredPhases`
- `testTargetWeightUsesTheScorecardsWording`
- `testScanSourceNotBuiltShowsNoFootnote` / `testScanSourceOffShowsTheFootnote` (and the two for events)
- `testScorecardFlagOffKeepsPhasesAndDropsTheEstimate`
- `testPastCheckpointNotDoneHasNoOverdueWording`
- `testViewRowsAreExactlyTheBuiltItemsInOrder`

`Stage6FlagOffTests.swift`

- `testAllFlagsOffAddsNoHealthRowNoScorecardLinkAndNoRoute`
- `testAllFlagsOffReadsNoStage6Key` (a defaults suite that records reads)
- `testSwitchingAFlagOffDeletesNothing`
- `testCutScorecardModelPresentationIsUnchangedByTheNewProperty`

`Stage6PrivacyTests.swift`

- `testWidgetSnapshotContainsNoStage6Text` (encode the widget snapshot with a full fixture stored;
  scan for every fixture location, label, exercise and title)
- `testNoNotificationRequestIsAddedByStage6`
- `testCoachContextContainsNoStage6Text` (`AICoach.buildContext` and `buildFullContext` output
  scanned for the same strings)
- `testBackupSettingsCarryStage6ListsAndNoFlag`

### 12.4 Source scan — `Tools/test_stage6_single_source.py`

Modelled on `Tools/test_body_measurement_single_resolver.py:204-237`, with a literal allowlist that
must still match.

- `test_niggle_keys_are_read_only_by_their_store` (the four key literals appear only in
  `NiggleLogSettings.swift`, `CheckpointTimelineSettings.swift` and `BackupSettings.swift`)
- `test_triage_is_called_only_by_the_niggle_model`
- `test_cut_stress_is_referenced_only_by_its_own_surfaces` (§8.2 list; fails on any reference from
  `IntelligenceEngine`, a scorer, `CutScorecard*`, `AICoach*`, `StrandiOSWidgets/`, `StrandiOSShared/`)
- `test_timeline_is_built_only_by_its_model`
- `test_typical_band_has_one_definition` (`Baselines.sigma(` appears in app targets only in
  `ChargeTypicalBand.swift`)
- `test_stage6_adds_no_kotlin` (no file under `android/` contains a stage 6 key or type name; the
  recorded disposition, so the drift of §9.5 is a decision and not an accident)
- `test_allowlist_entries_still_match`

### 12.5 Flag-off equivalence

With the three flags off: no Health row, no scorecard link, no screen, no stored key read, nothing
computed, and the baseline suite's results are unchanged. The two edits that run with the flags off
are the extraction of the typical range (same body, asserted by
`testTypicalRangeEqualsRecoveryDetailsRange`) and the new stored property on `CutScorecardModel`
(asserted by `testCutScorecardModelPresentationIsUnchangedByTheNewProperty`).

### 12.6 Fault injection

| # | Deliberate break | A test that must fail |
|---|---|---|
| F1 | Day count without the `+ 1` | `testOnsetDayIsDayOne` |
| F2 | First match wins, ignoring severity | `testHigherSeverityWinsWhateverTheOrder` |
| F3 | Ties broken by the later rule | `testEqualSeverityTakesTheEarlierRule` |
| F4 | `fromDay` made exclusive | `testFromDayIsInclusive` |
| F5 | `throughDay` made exclusive | `testThroughDayIsInclusive` |
| F6 | Onset values used when an update exists | `testLatestUpdateSuppliesTrendAndWeakness` |
| F7 | Future updates applied | `testUpdateAfterTodayIsIgnoredAndCounted` |
| F8 | Empty `characters` treated as "none" | `testEmptyCharactersAndTrendsMatchAnything` |
| F9 | `weakness: nil` treated as false | `testWeaknessNilMatchesBoth` |
| F10 | A resolved complaint still triaged | `testResolvedReportsDurationAndNoRule` |
| F11 | `nextChange` returns the first candidate unconditionally | `testNextChangeSkipsACandidateThatKeepsTheWinner` |
| F12 | A default rule shipped | `testNoRulesAreStoredByDefault` |
| F13 | A read rewrites an unreadable string | `testReadingNeverWrites`, `testSaveIsRefusedWhileEntriesNeedAttention` |
| F14 | Entries stored under a strap id | `testStoredStringsContainNoDeviceIdentifier` |
| F15 | Weekly minimum off by one | `testWeekAtExactlyTheMinimumHasAMean`, `testWeekBelowTheMinimumHasNoMeanButReportsItsNights` |
| F16 | A short week reported as 0 | `testWeekBelowMinimumIsNotMeasuredNeverZero` |
| F17 | Bounds check removed | `testOutOfRangeAndNonFiniteValuesAreDroppedAndCounted` |
| F18 | Week keyed from Sunday | `testSundayAndMondayFallInDifferentWeeks` |
| F19 | Change taken from the first two weeks | `testChangeRunsFromEarliestToLatestWeekWithAMean` |
| F20 | A "elevated" flag added to the result | `testResultHasNoStateOrTierField` |
| F21 | The scorer reads `CutStressTrend` | `test_cut_stress_is_referenced_only_by_its_own_surfaces` |
| F22 | The cut-stress presenter computes its own range | `test_typical_band_has_one_definition` |
| F23 | Today marker sorted before the day's items | `testTodayMarkerFollowsItemsDatedToday` |
| F24 | Projection emitted for `needsNewWeighIn` | `testProjectionAppearsOnlyWhenProjected` |
| F25 | Spans read while the source is off | `testSpansAreIgnoredUnlessTheSourceIsOn` |
| F26 | A span ending today marked past | `testSpanPositions` |
| F27 | The timeline evaluates the scorecard itself | `testTimelineNeverEvaluatesTheScorecardItself` |
| F28 | "Overdue" wording on a past checkpoint | `testPastCheckpointNotDoneHasNoOverdueWording` |
| F29 | A flag-off screen reads its key | `testAllFlagsOffReadsNoStage6Key` |
| F30 | Niggle text added to the widget snapshot | `testWidgetSnapshotContainsNoStage6Text` |
| F31 | A stage 6 key added to the whitelist as a flag | `testStage6FlagsAreNotExported` |

### 12.7 Parity: written dispositions (R43)

No Kotlin is written and no oracle is built.

| Piece | Disposition |
|---|---|
| `CanonicalDay`, `NiggleTriage`, `CutStressTrend`, `CheckpointTimeline` | Shared pure logic with **no Kotlin twin, by the owner's decision**. Each produces display values only; none writes a stored value or changes an existing formula. The parity ratchet's Kotlin lines for these declarations are recorded debt, as R43 states. Each public declaration carries the doc-comment line "No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43)." |
| The four backup keys | Swift only; drift as written in §9.5 |
| Marker catalogue, `DashboardCard` ids, migrations | Not touched |
| Gate script | Android rows waived by flag and reported as waived; the parity-oracle row is NOT RUN, with this section cited as the reason |

### 12.8 Simulator and rehearsal

Every frame of §10 reproduced from the fixture through `Stage6Demo` (names `niggle-g<n>`,
`nigglesheet-h<n>`, `rules-i<n>`, `stress-j<n>`, `timeline-k<n>`, and `flow6-<step>` simulator-only
flows), at default and largest text size, Reduce Motion on and off; add, edit, update, resolve,
reopen, delete, reorder rules, pause and resume, add and tick a checkpoint exercised by tapping.
Per stage 1 ruling R31, app-target tests and simulator runs that read nights from the repository use
dates relative to the real clock; the 2031 fixture is for the pure functions and the settings.

Real-data rehearsal, private (0B-7): on a restored copy, enter the owner's own rules, complaints,
paused exercises and checkpoints from the private profile and confirm each can be expressed without
a workaround; open the cut-stress screen over the real nights; open the timeline over the real
phases. Results stay under `PersonalData/`.

## 13. Fixture

Everything here is invented. "Fixture Person" does not exist. It extends stage 1's fixture: phase
"Fixture cut", kind cut, start 2031-01-06 (a Monday), target 94.0 kg.

### 13.1 Rules

Professional rule text: "Fixture rule: book a fixture review after 20 days, or sooner if it worsens."

| Order | id | Label | Action | Characters | Trends | Weakness | From | Through |
|---|---|---|---|---|---|---|---|---|
| 1 | `r-a` | Fixture label A | watch | diffuse | easing | either | 1 | 5 |
| 2 | `r-b` | Fixture label B | modify | positional | any | either | 3 | none |
| 3 | `r-c` | Fixture label C | seeProfessional | any | any | either | 21 | none |
| 4 | `r-d` | Fixture label D | seeProfessional | any | worsening | either | 8 | none |
| 5 | `r-e` | Fixture label E | modify | localised | any | with | 1 | none |

### 13.2 Complaints and expected results

| # | Complaint | Today | n | Status | Rule | Matched | Next change |
|---|---|---|---|---|---|---|---|
| N1 | "Fixture shoulder", left, diffuse, easing, onset 2031-02-03, resolved 2031-02-06 | 2031-03-01 | 4 | resolved | — | — | — |
| N2a | "Fixture knee", right, positional, unchanged, onset 2031-03-03, update 2031-03-10 seq 1 worsening | 2031-03-03 | 1 | noRuleMatches | — | — | day 3, 2031-03-05, `r-b` |
| N2b | same | 2031-03-05 | 3 | matched | `r-b` modify | `r-b` | day 21, 2031-03-23, `r-c` |
| N2c | same | 2031-03-09 | 7 | matched | `r-b` | `r-b` | day 21, 2031-03-23, `r-c`; `ignoredUpdates` 1 |
| N2d | same | 2031-03-10 | 8 | matched | `r-d` seeProfessional | `r-b`, `r-d` | day 21, 2031-03-23, `r-c` (equal severity, earlier rule) |
| N3 | "Fixture wrist", both, localised, unchanged, weakness, onset 2031-04-07 | 2031-04-07 | 1 | matched | `r-e` modify | `r-e` | day 21, 2031-04-27, `r-c` |
| N4 | Observation "Fixture side difference", left, noted 2031-01-13 | any | — | not triaged | — | — | — |
| N5 | "Fixture calf", right, diffuse, notRecorded, onset 2031-05-05 | 2031-05-12 | 8 | noRuleMatches | — | — | day 21, 2031-05-25, `r-c` |
| N6a | "Fixture forearm", left, diffuse, easing, onset 2031-06-02 | 2031-06-06 | 5 | matched | `r-a` watch | `r-a` | day 6, 2031-06-07, none |
| N6b | same | 2031-06-07 | 6 | noRuleMatches | — | — | day 21, 2031-06-22, `r-c` |

A second "Fixture knee", right, onset 2031-06-16, gives a recurrence count of 1 against N2.

Paused: "Fixture Hinge", paused 2031-03-05, reason "Linked to the fixture knee", until "Until a
fixture review", linked to N2. "Fixture Carry", paused 2031-01-20, reason "Fixture reason", resumed
2031-02-10.

### 13.3 Nights and expected weeks

`today` 2031-02-05 (a Wednesday), `firstWeekStart` 2031-01-06, `minNightsPerWeek` 4, `maxWeeks` 26.

| Week of | Resting heart rate nights (bpm) | HRV nights (ms) | Expected RHR mean / nights | Expected HRV mean / nights |
|---|---|---|---|---|
| 2031-01-06 | 60 on all seven days | 50 on all seven | 60.000 / 7 | 50.000 / 7 |
| 2031-01-13 | 61 Monday to Thursday | 48 Monday to Thursday | 61.000 / 4 | 48.000 / 4 |
| 2031-01-20 | 62 Monday to Wednesday | 47 Monday to Wednesday | nil / 3 | nil / 3 |
| 2031-01-27 | 63, 63, 64, 64, 65, 65, 66 | 46, 46, 45, 45, 44, 44, 43 | 64.286 / 7 | 44.714 / 7 |
| 2031-02-03 (current) | 64 Monday to Wednesday | 45 Monday to Wednesday | nil / 3 | nil / 3 |

Extra nights that must change nothing but the counters: 2031-01-17 with resting heart rate 500
(`outOfRange` 1; HRV absent); 2031-01-18 with HRV NaN (`nonFinite` 1); 2031-02-09 with both values
(`future` 1); 2030-12-30 with both values (before the first week: unused, not counted).

Expected changes: resting heart rate from 60.000 (week of 2031-01-06) to 64.286 (week of
2031-01-27), delta 4.286; HRV from 50.000 to 44.714, delta −5.286.

The fixture moves both series across the weeks on purpose, so the test recovers several different
values and not one.

### 13.4 Timeline

Inputs: phases [Fixture cut, 2031-01-06, cut, 94.0], and [Fixture hold, 2031-06-16, other, no
target]. Checkpoints: C1 "Fixture waypoint", weightTarget 96.0, 2031-04-14, approximate, not done;
C2 "Fixture panel", bloodPanel, 2031-02-10, done; C3 "Fixture second scan", scan, 2031-03-17, not
done; C4 "Fixture benchmark", benchmark, 2031-02-05, not done. Scan days: 2031-01-08, 2031-03-17.
Spans: deload 2031-02-17 to 2031-02-23; diet break 2031-03-24, open-ended. Projection: `projected`,
2031-05-27. Both sources `on`.

Expected with `today` 2031-02-05, in order: phaseStart 01-06 (past); scan 01-08 (past); checkpoint
C4 02-05 (current); today; checkpoint C2 02-10 (upcoming); deload 02-17 (upcoming); scan 03-17 is
rejected as `futureScan`, so checkpoint C3 03-17 stays (upcoming); dietBreak 03-24 (upcoming, open);
checkpoint C1 04-14 (upcoming, approximate); projection 05-27 (upcoming, estimate); phaseStart 06-16
(upcoming).

With `today` 2031-03-24: scan 03-17 is kept and C3 is dropped (`duplicate` 1); deload is past;
dietBreak 03-24 is current and precedes the today marker.

With `today` 2031-02-20, `events` `off` and projection nil: no deload, no diet break, no projection;
`events` echoed as `off`.

These tables were worked by hand from §7 for this document, not produced by an implementation. The
Test author recomputes a row before relying on it and reports any disagreement as a defect in this
table or in §7.

## 14. Work packages and file ownership

A package edits only the files listed for it.

| WP | Role | Files |
|---|---|---|
| 6-1 | Spec writer | `docs/personal/superapp/specs/stage-6.md` |
| 6-2 | Designer | `design/round11-stage6/` (new; number by A11); `design/figma-plugin/code.js`, `manifest.json` (one new command) |
| 6-3 | Test author | Every test file named in §12, and the three additions to `BackupSettingsTests.swift` |
| 6-4 | Implementer A (pure) | `CanonicalDay.swift`, `NiggleTriage.swift`, `CutStressTrend.swift`, `CheckpointTimeline.swift` under `Packages/StrandAnalytics/Sources/StrandAnalytics/` |
| 6-5 | Implementer B (storage) | New: `Strand/Data/ObservableDefaultsFlag.swift`, `NiggleLogSettings.swift`, `CheckpointTimelineSettings.swift`, `TimelineSources.swift`, `ChargeTypicalBand.swift`. Edited: `Packages/WhoopStore/Sources/WhoopStore/BackupSettings.swift` (four keys); `StrandiOS/Redesign/ScoreDetailData.swift:156-160` (call the shared range); `Strand/Data/CutScorecardModel.swift` (the one property of §8.3, unless A7 holds) |
| 6-6 | Implementer C (niggle log), after G1 and 6-4, 6-5 | New: `Strand/Data/NiggleLogModel.swift`, `NiggleLogPresenter.swift`; `StrandiOS/NiggleLog/*.swift` except the demo |
| 6-7 | Implementer D (cut-stress and timeline), after G1 and 6-4, 6-5 | New: `Strand/Data/CutStressModel.swift`, `CutStressPresenter.swift`, `CheckpointTimelineModel.swift`, `CheckpointTimelinePresenter.swift`; `StrandiOS/Scorecard/CutStressView.swift`; `StrandiOS/Timeline/*.swift` |
| 6-8 | Implementer E (wiring), after 6-6 and 6-7 | Edited: `StrandiOS/Redesign/RedesignRoute.swift` (four cases); `StrandiOS/Redesign/RedesignHealthView.swift` (two rows in `moreCard`); `StrandiOS/Scorecard/ScorecardView.swift` (two link rows); `Strand/Screens/SettingsView.swift` (one section, iPhone only); new `StrandiOS/NiggleLog/Stage6Demo.swift`; `StrandiOS/App/StrandiOSApp.swift` debug block (chain `Stage6Demo.screen(named:)` before the scorecard fallback at `:623`) |
| 6-9 | Localiser | `Strand/Resources/Localizable.xcstrings` |
| 6-10 | Reviewers (correctness, contract, data safety), Verifier | None; read-only |

### 14.1 Shared hotspots

| Hotspot | Edited by stage 6 | Note |
|---|---|---|
| `Strand/Resources/Localizable.xcstrings` | **Yes**, 6-9 only | Serialised across stages: one stage's Localiser at a time |
| `Strand/Screens/SettingsView.swift` | **Yes**, 6-8 | One new section beside `scorecardCard` (`:466`, `:1860`); serialised with every stage that adds a Settings section |
| `StrandiOS/App/StrandiOSApp.swift` debug block | **Yes**, 6-8, one line at `:623` | Serialised with every stage that adds a demo |
| `StrandiOS/Redesign/RedesignRoute.swift` | **Yes**, 6-8 | Not on the brief's hotspot list, but every stage with a screen adds cases here; treat as one |
| `StrandiOS/Redesign/RedesignHealthView.swift` (`moreCard`) | **Yes**, 6-8 | Same remark (A10) |
| `StrandiOS/Scorecard/ScorecardView.swift` (`linksCard`) | **Yes**, 6-8 | Stage 5's annotation may also touch this file |
| `Strand/Data/CutScorecardModel.swift` | **Yes**, 6-5, one property | Stage 2 probably needs the same accessor (A7): whichever lands first adds it |
| `Packages/WhoopStore/Sources/WhoopStore/BackupSettings.swift` | **Yes**, 6-5 | Every stage that stores settings adds lines to the same two literals |
| `design/figma-plugin/code.js`, `manifest.json` | **Yes**, 6-2 | One command per round |
| `Strand/Screens/DashboardCards.swift` | No | No Today card (D7) |
| `Strand/Data/TodayCardReadout.swift` | No | |
| The three Today views | No | |
| `Packages/StrandImport` `MarkerCatalog` | No | No catalogue key |
| `project.yml` | No | |
| `Packages/WhoopStore/.../Database.swift` | No | No migration |

### 14.2 Parallel and serial

- **In parallel with any other stage, now:** 6-2 (design source), 6-3 for the pure functions, 6-4.
  The four pure files and their tests touch nothing another stage owns.
- **In parallel with other stages once stage 1 is merged:** 6-5's new files, the niggle log (6-6),
  and the cut-stress model, presenter and view. The niggle log depends on no other stage at all.
- **Serialised with other stages:** 6-8 and 6-9 (the hotspots above), and the two one-line edits in
  6-5 to `BackupSettings.swift` and `CutScorecardModel.swift`.
- **Waits for stage 4:** the body of `TimelineScanSource` (until then it returns `.notBuilt`).
  **Waits for stage 5:** the body of `TimelineEventSource`. The timeline ships without them and its
  states for that are specified (§10.8), so neither wait blocks the stage.
- Within the stage: 6-4 and 6-5 in parallel; 6-6 and 6-7 in parallel after them and after G1; then
  6-8; then 6-9.

## 15. Open questions for the owner

Work proceeds on each recommendation.

| # | Question | Recommendation, in force until overruled |
|---|---|---|
| Q1 | Should the niggle log, rules, paused list and checkpoints be included in backups? The backup file is unencrypted | Yes, all four, so a restore cannot lose the log. The alternative keeps `niggleLog.entries` out and accepts that a restore starts with an empty log |
| Q2 | When several of your rules fit a complaint, which label shows? | The most serious action; between equals, the higher rule in your list |
| Q3 | Is the day count "day 1" on the day it started? | Yes |
| Q4 | Are four characters enough ("spread over an area", "one spot", "only in one position or movement", "something else"), and three actions ("watch", "modify training", "see a professional")? | Yes. They are fixed lists so that rules can refer to them; your own words go in the label and the note |
| Q5 | Should the app ship example rules? | No. An example rule would be the app's opinion. The sheet starts empty |
| Q6 | Should niggles and paused exercises go into the coach packet? | Not in this stage. Later, as a packet section that is off by default, as the roadmap treats sensitive events |
| Q7 | Should the log have a Today card? | No. It lives under Health; Today stays as it is |
| Q8 | Should a paused exercise be flagged when an imported session contains it? | No. The list is a record, not a check |
| Q9 | Recovery context: weekly averages need at least four nights in the week. Right number? | Four, the count the app already uses before trusting a baseline provisionally (`Baselines.swift:98`) |
| Q10 | Recovery context: should the screen say whether a change is good or bad? | No. It shows the numbers; the coach interprets them |
| Q11 | Timeline: only diet breaks and deloads from the events layer, or travel and illness too? | Only the two the roadmap names. Sensitive kinds never appear |
| Q12 | Timeline: should open niggles appear on it? | No |
| Q13 | Timeline: a planned scan is a checkpoint you enter; when you record the scan on that exact day the checkpoint is replaced by it. On another day both show until you tick or delete the checkpoint. Acceptable? | Yes |
| Q14 | A past checkpoint that is not ticked shows "Not marked done" and nothing else. Acceptable? | Yes |
| Q15 | Three separate switches, or one? | Three, so each part can be accepted on the phone on its own |

## 16. Needs the owner's go-ahead

Nothing in this stage needs one of the gated changes:

| Gated change | Needed? |
|---|---|
| Migration | No |
| Health read or write change | No |
| New target or entitlement | No |
| Network path | No |
| Backup whitelist additions (not on the gated list, but a stored-data contract with recorded Kotlin drift) | Proceeds on Q1's recommendation; the owner may overrule |

The alternative that would need a go-ahead, a `niggle` table with a migration, is not proposed.

## 17. Decisions made where the roadmap left a choice

| # | Decision | Reason |
|---|---|---|
| D1 | Settings strings, not Lab Book rows, the `event` table or a new table | No strap id, so R42 holds by construction; no migration |
| D2 | The pure triage function sees no text | Labels, locations and notes cannot leak through logic, logs or tests |
| D3 | No default triage rules | A shipped rule would be the app's medical opinion |
| D4 | Highest severity wins, then the owner's order | A complaint past the owner's professional threshold must never show a milder label |
| D5 | A recurrence is a new entry counted against earlier ones with the same location and side | Keeps each episode's day count honest |
| D6 | Actions are words, never red, amber or green | No alarm colouring, no implied medical judgement |
| D7 | No Today card | Avoids five hotspot files for little value; the log is not a daily metric |
| D8 | Observations share the niggle store with a `kind` | The owner's standing notes need a home and no second mechanism |
| D9 | Cut-stress uses weekly means of stored nights, not `HRVReadiness` | `HRVReadiness` is a tier and experimental; a mean adds no score |
| D10 | Cut-stress shows no current value and no adjective | Nothing for Today to disagree with; nothing that reads as a score |
| D11 | Weeks are Monday weeks of the night's day key | The same axis as the scorecard's curves |
| D12 | The typical range is extracted, not recomputed | One definition for two screens |
| D13 | Target dates are owner-entered checkpoints | A stored phase has no date (C2) |
| D14 | The timeline reads the shared scorecard model's evaluation | One projection day across the app (R41) |
| D15 | A source that is not built says nothing; a source switched off says so once | The owner should not be told about features that do not exist |
| D16 | No notification and no widget | Sensitive content; the notification budget is unchanged |
| D17 | `CanonicalDay` is a new file, not a change to `CutScorecard` | A stage 1 file stays untouched; a test pins the two to one rule |

## 18. Not determined

- **Stages 2 to 5.** Their specifications were being written at the same time and were not
  available. Every item in §2.2 is an assumption, not a finding.
- **Whether the "Lab Book ownership" change has landed** on the branch this stage will be built
  from. Stage 6 does not depend on it.
- **Whether stage 2 exposes the scorecard evaluation** (A7).
- **The design round number** (A11).
- **How large `UserDefaults` strings behave at the limits in §9.2** on the device. The limits were
  chosen to keep each string in the tens of kilobytes; no measurement was made.
- **Whether `Repository.days` covers 26 weeks on the owner's phone.** `refresh(days:)` defaults to
  4000 (`Repository.swift:948`); the actual stored span was not inspected.
- **Whether the owner's nights are dense enough** for weekly means at four nights per week. The
  rehearsal will show it.
- **Whether a paused exercise should match lift-session exercise names.** Free text is specified;
  no matching was designed.
- **A dated "target reached" item.** The scorecard reports the status without a date of its own;
  the timeline shows nothing for it.
- **Parity ledger.** Whether the new public declarations can be registered without a Kotlin claim
  was not run through `Tools/parity_ledger.py`; stage 1 left the ledger's state open (0B-9).
- **The tables in §13** were worked by hand, as stated there.
- **Nothing was compiled.** Signatures in §6 follow the conventions of `CutScorecard.swift` and
  were not built.
