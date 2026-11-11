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
stage to be planned now, so the specifications were written together. A cross-stage check on
11 November 2026 settled the names, storage homes and order shared between them. §2.2 lists what
this stage takes from each other stage and from the orchestrator's shared scaffolding commit
("step 0"); the last section records what the check changed in this file. Each item in §2.2 is
confirmed against the merged code before G2 for the part that depends on it.

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
  owner-entered checkpoints (the home of target dates, waypoint weights and planned scans),
  recorded scan days (stage 4), diet breaks and deloads (stage 5), and the scorecard's projection.
- Three default-off settings, one per part.

**One rule shared with stages 1 and 5.** A diet break or a deload is an **event** (stage 5). A
phase (stage 1) is only a long block. The scorecard keeps reporting during an event, with the event
noted beneath the verdict as stage 5 specifies. The timeline therefore shows a break or a deload
only as a stage 5 span, never as a phase, and no stage 6 screen or string suggests adding a phase
for one.

**Out of scope**

- Any diagnosis, any suggestion of a cause or a treatment, any shipped default triage rule. The app
  applies rules the owner typed and says so.
- Any new score, band, tier, colour state or adjective for resting heart rate or HRV. Nothing in
  part (b) is read by Recovery, Strain, the scorecard verdict, illness detection, the Coach context
  or any widget (AGENTS.md, "Deriving a physiological signal").
- Notifications of any kind. Stage 6 adds none (§10.9). Widgets: none (§10.9).
- A Today card. Stage 6 adds no `DashboardCard` case (decision D7).
- Sending niggles, rules or paused exercises to the in-app Coach or the coach packet. Stage 2 owns
  the packet; the follow-up change "packet v2" adds intake and events only, and a niggle section
  stays out until the owner asks for one (§15, Q6).
- A second target weight. The one target weight stays in the active phase (stage 1). A checkpoint
  may carry a waypoint weight, which is never called a target and never read by the scorecard
  (§9.3).
- Enforcing a pause (hiding or flagging a paused exercise in lift sessions or imports).
- A migration, a new table, a new catalogue key, a new target, entitlement or network path, any
  change to Health access. None is needed (§9).
- Android. Skipped by the owner's decision (R43): no Kotlin is written or run. §9.5 states the one
  stored-data drift and §12.7 the dispositions.
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
| 6 | One observable copy of a feature flag exists | Confirmed for the scorecard key only; the class is not generic. Step 0 adds the generic `ObservableDefaultsFlag` (§9.4) | `CutScorecardModel.swift:18-63` |
| 7 | Baselines for resting heart rate and HRV exist | Confirmed. `Repository.chargeBaselines` is resolved once per refresh by `ChargeBaselines.resolve` and is "the single funnel every Charge readout below the headline reads" | `Strand/Data/Repository.swift:185-190`, `:1004`, `:1037`; `Packages/StrandAnalytics/Sources/StrandAnalytics/ChargeBaselines.swift:151` |
| 8 | Today shows trends for HRV and resting heart rate | Confirmed: sparklines built from the merged daily rows (`repo.days`), keyed `hrv` and `rhr`, filtered to a 7, 14 or 30 day window | `Strand/Liquid/LiquidTodayView.swift:3363-3364`, `:3639-3647`, `:1188-1194`; `StrandiOS/Redesign/RedesignTodayView.swift:602` |
| 9 | A "typical range" is shown for HRV and resting heart rate | Confirmed, in one place: Recovery detail's factors, the baseline plus and minus the recovery engine's spread for that baseline state, when the baseline is usable. The expression is a local function and the only one of its kind in the app targets | `StrandiOS/Redesign/ScoreDetailData.swift:156-165`. Step 0 moves the expression to `ChargeTypicalBand.range(_:)`, the only name stage 6 uses for it (§8.2) |
| 10 | `HRVReadiness` is available as a trend read model | It exists, is experimental, opt-in, and read only by the Test Centre. It is a **tier** (primed, normal, suppressed) | `Packages/StrandAnalytics/Sources/StrandAnalytics/HRVReadiness.swift:1-28`, `:93`; `Strand/Screens/TestCentreView.swift:753`. Not used by this stage (D9) |
| 11 | The `event` table can hold personal events | It is a strap stream table: primary key `(deviceId, ts, kind)`, carries a `synced` column, is written by the collector and by `recordEvent`, and is in the list a strap delete clears | `Packages/WhoopStore/Sources/WhoopStore/Database.swift:28-34`, `:130-135`; `WhoopStore.swift:187-192`; `StreamStore.swift:288`; `DeviceRegistryStore.swift:162-165`. Not used by this stage (D1) |
| 12 | `labMarker` is cleared by a strap delete | Confirmed today; ruling R42 reverses it in a separate change that has not landed on this branch | `DeviceRegistryStore.swift:166-173` |
| 13 | The backup whitelist carries only Int, Double and String, and a JSON array or object rides as a String | Confirmed; restore writes only keys present in the incoming file | `Packages/WhoopStore/Sources/WhoopStore/BackupSettings.swift:29-31`, `:49-76`, `:82-97`, `:119-126` |
| 14 | Calendar-free day arithmetic exists | Confirmed: `WeeklyDigestEngine.mondayOfWeek`, `addDays` (public); `parseYMD` (public); `formatYMD`, `julianDayNumber`, `fromJulianDayNumber` (module-internal). The canonical-key rule of R5 is private to `CutScorecard`. Step 0 adds `CanonicalDay` (§6.0) | `WeeklyDigest.swift:421`, `:430`, `:462`, `:471`, `:480`, `:488`; `CutScorecard.swift:1046`, `:1055` |
| 15 | The weekly curve component exists | Confirmed: `ScorecardWeekChart(points:firstLabel:lastLabel:color:)`, one optional point per week, a missing week breaks the line, no rule or band | `StrandiOS/Scorecard/ScorecardWeekChart.swift:4-15` |
| 16 | The debug demo harness can host new frames | Confirmed: `--demo-screen <name>` falls through to `ScorecardDemo.screen(named:)`; each state runs on an in-memory store and its own defaults suite. Step 0 replaces the single fall-through with one ordered registry of demo providers | `StrandiOS/App/StrandiOSApp.swift:621-623`; `StrandiOS/Scorecard/ScorecardDemo.swift:26-63` |
| 17 | The design pipeline exists | Confirmed: `design/tools/serve.py` (preview and `--export`), `design/round6-scorecard/`, plugin commands `import` and `import6`. Step 0 adds the commands `importS2` to `importS6` and the stage-named folders | `design/tools/serve.py:1-25`; `design/figma-plugin/manifest.json:21-26` |
| 18 | The local gate script exists | Confirmed | `Tools/personal/gate.sh:1-36` |
| 19 | Lab Book has a category for imaging | Confirmed: `LabMarkerCategory` has `imaging`. No body-composition scan key exists yet | `Packages/StrandImport/Sources/StrandImport/LabMarker.swift:26-33` |
| 20 | The newest migration is `v47-rr-whoop5-fill` | Confirmed | `Database.swift:1103` |

### 2.2 What stage 6 takes from the other stages and from step 0

The names below are the ones the cross-stage check fixed. Each is confirmed against the merged code
before the part that uses it is built. A difference changes only the adapter named, never the pure
functions.

| # | Stage 6 relies on | Owner | Used by |
|---|---|---|---|
| A1 | `BodyRecordStore.scans() async -> [BodyScan]` (main actor), each `BodyScan` carrying `day: String`. The read spans every device id (Lab Book ownership, R42). Stage 6 takes `day` exactly as stage 4 reports it, for a typed scan and for an imported one alike, and never derives a day from `takenAt` itself | Stage 4 (§9 there) | `TimelineScanSource` (§8.4) |
| A2 | Stage 4's switch `noop.bodyRecordEnabled`, named `BodyRecordSettings.enabledKey`, Bool, default `false`, readable without writing | Stage 4 | `TimelineSourceState` for scans |
| A3 | `PersonalEventStore.events`, a synchronous main-actor property returning `[PersonalEvent]`; it returns `[]` while stage 5's switch is off or its store is unreadable. `PersonalEvent` has `id`, `kind`, `startDay`, `endDay`, `sensitive`. `PersonalEvents.visible(_:includeSensitive:)` filters private events | Stage 5 (§6, §9.3 there) | `TimelineEventSource` (§8.4) |
| A4 | Stage 5 stores events as the settings string `personalEvents.items`, with no strap id (R42 holds by construction) | Stage 5 | Timeline |
| A5 | Stage 5's switch `noop.personalEventsEnabled`, read through `PersonalEventStore.isEnabled` | Stage 5 | `TimelineSourceState` for events |
| A6 | Stage 5's scorecard note does not change `CutScorecardResult.projection` | Stage 5 | Timeline projection item |
| A7 | Stage 2 moves `evaluateStored` out of `CutScorecardModel` to `CutScorecardInputBuilder.evaluation(today:) async -> CutScorecardEvaluation`, and moves the `CutScorecardEvaluation` type beside the builder. Stage 2 adds no stored evaluation to the model; stage 6 adds it (§8.3) | Stage 2 (§8.2 there) | §8.3 |
| A8 | The packet has no niggle section; "packet v2" adds intake and events only | Stage 2 | §1 |
| A9 | Stage 3 adds a widget and a reminder; stage 6 adds neither, so the notification count is unchanged by this stage | Stage 3 | §10.9 |
| A10 | The Health tab's "More health" card, the Settings screen and the scorecard screen each have one combined design frame covering every stage, approved once. The Settings cards and the Health rows follow one order, top to bottom: Scorecard, Coach packet, Intake, Body record, Events, Niggle log, Recovery context, Timeline. The combined frame set is the authority; this specification states only its own three places, the last three | Orchestrator and Designer | §10.1; work package 6-8a |
| A11 | Stage 5 adds `axisMarks: NoopChartAxisMarks? = nil` to `ScorecardWeekChart`. Stage 6 reuses the view after that change and passes no marks | Stage 5 | §10.7 |
| A12 | Lab Book ownership (R42) lands first in the build order. Stage 6 stores nothing in `labMarker`, so it does not depend on it except through A1 | Lab Book ownership | §9 |
| A13 | Routes `RedesignRoute.bodyRecord` (stage 4) and `RedesignRoute.personalEvents` (stage 5) exist when their adapters are written | Stages 4, 5 | §10.8 |
| A14 | Step 0 has landed: the demo registry in `StrandiOSApp`'s debug block; the plugin commands `importS2` to `importS6` and the folder `design/round-s6-log-timeline/`; `ObservableDefaultsFlag`; `CanonicalDay` with its pinning test; `ChargeTypicalBand` extracted from `ScoreDetailData`; the comment block above the Swift backup whitelist that lists the fork-only keys | Orchestrator | §5, §6.0, §8.2, §9.4, §9.5, §12.8, §14 |

Until stage 4 or stage 5 is merged, its adapter is the `notBuilt` value of §8.4 and the timeline
shows its specified states for that (§10.8).

## 3. Corrections to the planning documents

| # | Document says | The code says | Consequence |
|---|---|---|---|
| C1 | ROADMAP stage 6: "Needs a migration: Possibly" | None of the three parts needs one. The log, the rules, the paused list and the checkpoints are small owner-authored lists and are stored as settings strings, as stage 1 stores phases (`CutScorecardSettings.swift:106-117`) | No migration, no owner go-ahead needed for storage (§9) |
| C2 | ROADMAP stage 6: the timeline shows "target dates" as if they were stored | A stored phase has a target **weight** and no date (`CutScorecardSettings.swift:5-17`). The only dated target the app holds is the projection's `targetDay`, which is an estimate (`CutScorecard.swift:196-200`) | Target dates are owner-entered checkpoints (§9.3). The projection is a separate item, labelled as an estimate |
| C3 | Stage 1 specification §8.1: the scorecard's values are "reads of one list" available to other surfaces | The model publishes strings only (`CutScorecardModel.swift:69-76`). A second surface that needs the projection day would have to evaluate again, which is the "two readouts of one fact" shape | §8.3 adds one read-only property to the shared model. The timeline never calls `CutScorecard.evaluate` |
| C4 | CONTEXT §4: the `event` table is "a generic timestamped event with a JSON payload" that later stages might reuse | It is keyed by strap id and instant, deduplicates on `(deviceId, ts, kind)` with `DO NOTHING`, has a `synced` flag and is cleared by a strap delete (`Database.swift:28-34`; `WhoopStore.swift:187-192`; `DeviceRegistryStore.swift:162-165`) | Unusable for owner-entered records under R42 (D1). Stage 5 must reach the same conclusion or record why not |
| C5 | ROADMAP stage 6 names "resting heart rate and HRV trends" as if a trend read model existed | There is no weekly read model. Today's trends are per-night sparklines (`LiquidTodayView.swift:3363-3364`); `HRVReadiness` is a tier, experimental and Test-Centre only (`TestCentreView.swift:753`) | §6.2 specifies a small pure weekly aggregation; it is an arithmetic mean of values the app already shows, and it has one caller |
| C6 | Stage 1 specification R5 fixes the canonical day-key rule | The rule is implemented privately inside `CutScorecard` (`CutScorecard.swift:1046-1059`), so a second pure type cannot reuse it without editing a stage 1 file | Step 0 adds `CanonicalDay` (§6.0) with a test that pins it to `CutScorecard.weekStart(containing:)`. Stage 6 uses it and writes no day arithmetic of its own |
| C7 | ORCHESTRATION: the backup whitelist's sole writer is the Parity agent, "Swift and Kotlin" | Under R43 no Kotlin is written | The Swift whitelist has one writer at a time, in stage order (3, then 5, then 6); this stage's four keys are added by the orchestrator's hotspot commit. The Kotlin side is recorded as not updated (§9.5) |
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
| `StrandiOS/Redesign/ScoreDetailData.swift:149-165` | Recovery detail: value and typical range | Not edited by this stage. Step 0 moves the typical-range expression to `ChargeTypicalBand`; the cut-stress presenter calls the same function (§8.2) |
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
| `Strand/Data/CutScorecardModel.swift:141-180` | Evaluates and presents; after stage 2 it calls `CutScorecardInputBuilder.evaluation(today:)` | Gains one stored read-only property (§8.3), in this stage's place in the shared-file order (§14.1) |
| `Strand/Data/CutScorecardPresenter.swift` (projection strings), `StrandiOS/Scorecard/ScorecardView.swift:507` | Show the projection | Untouched. The timeline's projection item is built from the same evaluation and worded by the same `Wording` (`CutScorecardPresenter.swift:1024`, `:1044`) |
| `Packages/WhoopStore/Sources/WhoopStore/BackupSettings.swift:74-75`, `:95-96` | Back up phases and rules | Untouched for those keys |

### 4.3 Facts that are new in this stage

Niggles, triage rules, the professional rule, paused exercises and checkpoints (including waypoint
weights and target dates) have no existing reader or writer. Searches for `niggle`, `injur`,
`paused`, `checkpoint` and `timeline` under
`Strand/`, `StrandiOS/`, `StrandiOSShared/`, `StrandiOSWidgets/` and `Packages/` found no stored
fact of these kinds. Each gets exactly one store type (§5) and the source scan of §12.4 keeps it so.

### 4.4 Android

Android is skipped by the owner's decision (stage 1 ruling R43). No Android file is read, written
or changed by this stage, and no Kotlin is written or run. The one stored-data contract this stage
moves is the backup whitelist; §9.5 states the drift.

## 5. Final names

Created by this stage:

| Thing | Name | Where |
|---|---|---|
| Triage | `NiggleTriage.evaluate(_:)` and the `NiggleTriage*`, `Niggle*` types of §6.1 | `Packages/StrandAnalytics/Sources/StrandAnalytics/NiggleTriage.swift` |
| Weekly trend | `CutStressTrend.weekly(_:)` and the `CutStress*` types of §6.2 | `.../CutStressTrend.swift` |
| Timeline | `CheckpointTimeline.build(_:)`, `.governingPhaseIndex(on:phases:)`, `.waypointIssue(weightKg:on:phases:)` and the `Timeline*` types of §6.3 | `.../CheckpointTimeline.swift` |
| Niggle storage | `NiggleLogSettings`; stored types `StoredNiggle`, `StoredNiggleUpdate`, `StoredTriageRules`, `StoredTriageRule`, `StoredPausedExercise` | `Strand/Data/NiggleLogSettings.swift` |
| Niggle model and presenter | `NiggleLogModel`, `NiggleLogPresenter`, `NiggleDraft`, `TriageRulesDraft`, `PausedExerciseDraft` | `Strand/Data/NiggleLogModel.swift`, `NiggleLogPresenter.swift` |
| Cut-stress model and presenter | `CutStressModel`, `CutStressPresenter` | `Strand/Data/CutStressModel.swift`, `CutStressPresenter.swift` |
| Checkpoint storage | `CheckpointTimelineSettings`; stored type `StoredCheckpoint`; `CheckpointIssue`, `CheckpointSaveResult` | `Strand/Data/CheckpointTimelineSettings.swift` |
| Timeline sources | `TimelineScanSource`, `TimelineEventSource` | `Strand/Data/TimelineSources.swift` |
| Timeline model and presenter | `CheckpointTimelineModel`, `CheckpointTimelinePresenter`, `CheckpointDraft` | `Strand/Data/CheckpointTimelineModel.swift`, `CheckpointTimelinePresenter.swift` |
| Views | `NiggleLogView`, `NiggleDetailView`, `NiggleSheet`, `NiggleRulesSheet`, `PausedExerciseSheet` | `StrandiOS/NiggleLog/` |
| | `CutStressView` | `StrandiOS/Scorecard/CutStressView.swift` |
| | `CheckpointTimelineView`, `CheckpointSheet` | `StrandiOS/Timeline/` |
| Demo | `Stage6Demo`, one element of the demo registry; reserved prefixes `niggle-`, `cutstress-` and `timeline-` (§12.8) | `StrandiOS/NiggleLog/Stage6Demo.swift` |
| Routes | `RedesignRoute.niggleLog`, `.niggle(id: String)`, `.cutStress`, `.checkpointTimeline` | `StrandiOS/Redesign/RedesignRoute.swift` |
| Flags (Bool, default `false`) | `noop.niggleLogEnabled`, `noop.cutStressEnabled`, `noop.checkpointTimelineEnabled` | `NiggleLogSettings.enabledKey`, `CutStressModel.enabledKey`, `CheckpointTimelineSettings.enabledKey` |
| Observable copies of the flags | `NiggleLogSettings.flag`, `CutStressModel.flag`, `CheckpointTimelineSettings.flag`, each `static let … = ObservableDefaultsFlag(key: enabledKey)` | the same three files |
| Stored strings | `niggleLog.entries` (JSON array), `niggleLog.rules` (JSON object), `niggleLog.paused` (JSON array), `timeline.checkpoints` (JSON array) | §9 |
| Design round | `design/round-s6-log-timeline/`; plugin command `importS6`; export `s6-frames.json` | Named by stage, as every stage's round is |

Used by this stage and created by step 0 (stage 6 neither creates nor edits these files):

| Thing | Name | Expected at |
|---|---|---|
| Day-key helper | `CanonicalDay` (§6.0) | `Packages/StrandAnalytics/Sources/StrandAnalytics/CanonicalDay.swift` |
| Observable flag | `ObservableDefaultsFlag` (§9.4) | `Strand/Data/ObservableDefaultsFlag.swift` |
| Typical range | `ChargeTypicalBand.range(_:)` (§8.2) | `Strand/Data/ChargeTypicalBand.swift` |
| Demo registry | the ordered list of demo providers | `StrandiOS/App/StrandiOSApp.swift`, debug block |

Used by this stage and owned by another stage: `BodyRecordStore`, `BodyScan`,
`BodyRecordSettings.enabledKey`, `RedesignRoute.bodyRecord` (stage 4); `PersonalEventStore`,
`PersonalEvent`, `PersonalEventKind`, `PersonalEvents.visible`, `RedesignRoute.personalEvents`
(stage 5); `CutScorecardInputBuilder.evaluation(today:)`, `CutScorecardEvaluation` (stage 2).

Models, presenters, settings and adapters live under `Strand/` so `StrandTests` (macOS `Strand`
scheme) can test them, as stage 1 does. Views live under `StrandiOS/`. `project.yml` needs no edit:
both directories are included by path (`project.yml:88`, `:221`, `:240`); run `xcodegen generate`.

## 6. Pure logic: the API

The three stage 6 files and `CanonicalDay` are in `Packages/StrandAnalytics`. No store, no clock, no
`Calendar`, no `TimeZone`, no `Date`, no free text. Every type is `public`, `Equatable`, `Sendable`,
with a public memberwise `init` taking the stored properties in declaration order with the defaults
shown. Enums with raw values are `String`. "Today" is always passed in as a day key.

### 6.0 `CanonicalDay` (step 0; the surface stage 6 calls)

Step 0 creates this file and its tests. It is listed here because every stage 6 pure function is
written against it. Stage 6 does not create or edit it, and no stage 6 file parses a day key or
does Julian-day arithmetic by any other route.

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

`CanonicalDay.number(k) != nil` equals `CutScorecard.weekStart(containing: k) != nil` for every
string, and `CanonicalDay.weekStart(k)` equals `CutScorecard.weekStart(containing: k)`; step 0's
test pins both. If the scaffolding's surface differs from this listing, the scaffolding stands and
this listing and the stage 6 call sites are corrected to it.

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
    case scan, bloodPanel, benchmark, weightWaypoint, targetDate, appointment, other
}
public enum TimelineSpanKind: String, CaseIterable { case dietBreak, deload }
public enum TimelineSourceState: String { case notBuilt, off, on }
public enum TimelinePosition: String { case past, current, upcoming }
public enum TimelineWaypointIssue: String { case nonFinite, atOrBeyondTarget }

public struct TimelinePhase {
    public let startDay: String
    public let isCut: Bool
    public let targetWeightKg: Double?   // the one stored target weight (stage 1)
}
public struct TimelineCheckpoint {
    public let day: String
    public let isApproximate: Bool
    public let category: TimelineCheckpointCategory
    public let waypointWeightKg: Double? // only meaningful for weightWaypoint
    public let phaseStartDay: String?    // only meaningful for targetDate: the phase it belongs to
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
    public let targetWeightKg: Double?   // phaseStart items only: that phase's stored target
    public let waypointWeightKg: Double? // weightWaypoint checkpoints only
    public let phaseIndex: Int?          // targetDate checkpoints only: index into input.phases
    public let phaseIsCut: Bool?
}

public struct TimelineRejections {
    public let invalidDay: Int
    public let endBeforeStart: Int
    public let futureScan: Int
    public let duplicate: Int
    public let nonFinite: Int
    public let waypointBeyondTarget: Int
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
    /// Index of the phase in force on `day`: the phase with the greatest canonical `startDay` on or
    /// before `day`; among equal start days the greater index. Nil when `day` is not canonical or no
    /// phase has started by then. The rule of `CutScorecardSettings.activePhase(on:)`.
    public static func governingPhaseIndex(on day: String, phases: [TimelinePhase]) -> Int?
    /// Nil when `weightKg` may stand as a waypoint on `day` (§7.3, step 4a).
    public static func waypointIssue(weightKg: Double, on day: String,
                                     phases: [TimelinePhase]) -> TimelineWaypointIssue?
}
```

A checkpoint never carries a target weight. `targetWeightKg` exists only on `TimelinePhase` and on
the `phaseStart` item built from it; a `targetDate` item points at its phase by `phaseIndex`, and
the presenter reads the weight from that phase.

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
4. Checkpoints: one `checkpoint` item each (canonical day required; otherwise `invalidDay`), with
   `targetWeightKg` always nil.
   - a. **Waypoint weight.** `waypointWeightKg` is carried only for `weightWaypoint`. It is dropped
     to nil and counted `nonFinite` when `waypointIssue` returns `.nonFinite`, and dropped to nil
     and counted `waypointBeyondTarget` when it returns `.atOrBeyondTarget`; the item itself stays.
     `waypointIssue(weightKg:on:phases:)`: a weight that is not finite or not positive is
     `.nonFinite`. Otherwise let `g = governingPhaseIndex(on: day, phases:)`. With no `g`, or a
     phase `g` whose `targetWeightKg` is nil, not finite or not positive, there is no issue. When
     phase `g` is a cut, `weightKg <= targetWeightKg` is `.atOrBeyondTarget`. When it is not a cut,
     only `weightKg == targetWeightKg` is `.atOrBeyondTarget` (a phase of kind `other` has no
     direction). Anything else is no issue. The sheet refuses such a weight at save (§9.3); this
     step covers a phase target changed after the waypoint was saved.
   - b. **Target date.** For `targetDate`, `phaseIndex` is the index of the first phase whose
     canonical `startDay` equals the checkpoint's `phaseStartDay`; nil when `phaseStartDay` is nil
     or matches no phase. A `targetDate` checkpoint whose non-nil `phaseStartDay` equals that of an
     earlier kept `targetDate` checkpoint (input order) is dropped and counted `duplicate`: a phase
     has at most one target date. For every other category `phaseIndex` is nil.
   - c. **Planned scan.** A checkpoint of category `scan` whose day equals a kept scan day is
     dropped and counted `duplicate`: the recorded scan stands for it.
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
| Typical range | `ChargeTypicalBand.range` over `Repository.chargeBaselines` | Recovery detail (existing), the coach packet (stage 2) and the cut-stress screen | Not correctable |
| Phase start | `CutScorecardSettings.phases` | Scorecard (existing), timeline | The existing phase sheet, opened from the timeline item |
| **Target weight** | `CutScorecardSettings.phases`: the phase's `targetWeightKg`, and nothing else | Scorecard (existing); the timeline's phase row and that phase's target-date row | The existing phase sheet, opened from either row |
| Target date | One `targetDate` checkpoint per phase, in `CheckpointTimelineSettings.checkpoints` | Timeline | The checkpoint sheet |
| Waypoint weights | `weightWaypoint` checkpoints, in `CheckpointTimelineSettings.checkpoints` | Timeline only, always labelled "waypoint" | The checkpoint sheet |
| Projection day | The shared `CutScorecardModel`'s stored evaluation (§8.3) | Scorecard (existing), timeline | The weigh-in sheet and history, opened from the timeline item |
| Scan days | `BodyRecordStore.scans()` through `TimelineScanSource` (§8.4) | Timeline | Stage 4's screen (`RedesignRoute.bodyRecord`), opened from the item |
| Diet breaks and deloads | `PersonalEventStore.events` through `TimelineEventSource` (§8.4) | Timeline | Stage 5's screen (`RedesignRoute.personalEvents`), opened from the item |
| Other checkpoints | `CheckpointTimelineSettings.checkpoints` | Timeline | The checkpoint sheet |

A waypoint weight is a different variable from the target weight, and the design keeps them from
being read as one: a waypoint is never worded as a target, is never read by the scorecard or its
projection, and cannot be saved equal to or beyond the phase target (§9.3). The date the owner
wants to reach the target by is a checkpoint with no weight; its row shows the phase's own stored
target.

### 8.2 Part (b) adds no score and feeds none

- The screen shows, per metric: a curve of weekly means; the latest week's mean with its night
  count; the earliest shown week's mean; the difference as a signed number; and the typical range
  as text. No adjective, no arrow that means good or bad, no colour other than the neutral primary
  text colour, no band on the chart.
- It shows **no current value**. The night's value stays on Today, Health and Recovery detail, so
  there is nothing here for those to disagree with. A weekly mean is labelled "week average".
- The typical range comes from `ChargeTypicalBand.range(_ state: BaselineState?) -> ClosedRange<Double>?`,
  which step 0 extracts from the local function at `ScoreDetailData.swift:156-160` with the same
  body. Recovery detail calls it; stage 2's packet assembler takes the range from
  `ChargeTypicalBand.range(_:)` and holds no sigma; the cut-stress presenter calls `range`. Stage 6
  edits neither `ChargeTypicalBand.swift` nor `ScoreDetailData.swift`, changes no formula, and
  computes no band, centre or spread of its own: `ChargeTypicalBand.range(_:)` is the only way a
  stage 6 file obtains the range (§12.4).
- The framing sentence on the screen is fixed (§11): it says the figures are context for the coach
  and are not used by any score.
- Enforced by test (§12.4): `CutStressTrend` and `CutStressModel` are referenced only from their
  own files, the cut-stress view, the routes file and the demo; never from `IntelligenceEngine`,
  the scorers, `CutScorecard*`, `AICoach`, `CoachPacket*`, a widget, a notification or a backup.
- Disposition under the derived-signal rule: a weekly arithmetic mean of nightly values the app
  already stores and shows is not a new physiological signal derived from raw sensor data. It still
  ships behind a default-off setting and stays out of every gate until the owner asks otherwise.

### 8.3 The scorecard's evaluation

After stage 2, `CutScorecardModel.load()` obtains its result from the one funnel
`CutScorecardInputBuilder.evaluation(today:)`, and the type `CutScorecardEvaluation` lives beside
the builder. Stage 6 adds one stored property to `CutScorecardModel`, assigned in `load()` from the
value that funnel returned for that load, in the same step that sets `state`, and cleared to nil
wherever `state` becomes `.idle`:

```swift
/// The evaluation behind the published presentation: the value `CutScorecardInputBuilder
/// .evaluation(today:)` returned for the latest load. Nil while idle or before the first result.
private(set) var evaluation: CutScorecardEvaluation?
```

`CheckpointTimelineModel` reads `CutScorecardModel.live(...).evaluation?.result.projection` after
awaiting that model's `load()`. It never builds a `CutScorecardInput`, never calls
`CutScorecard.evaluate` and never calls `CutScorecardInputBuilder.evaluation(today:)` itself, so the
projection day on the timeline is the one the scorecard screen is showing.

Order on this file: the one shared-file order of §14.1. This property is stage 6's edit, made
after every earlier editor in that order has made its own and before packet v2. It is one small
commit of its own (6-8b).

### 8.4 Timeline sources: the two adapters

`Strand/Data/TimelineSources.swift` is the only stage 6 file that names a stage 4 or stage 5 type.
Each adapter is a value built from closures, so a test supplies its own.

```swift
@MainActor
struct TimelineScanSource {
    init(state: @escaping () -> TimelineSourceState, scans: @escaping () async -> [BodyScan])
    /// Stage 4 merged: state from `BodyRecordSettings.enabledKey`, scans from `BodyRecordStore.scans()`.
    static func live(repository: Repository, defaults: UserDefaults = .standard) -> TimelineScanSource
    /// Stage 4 not in this build.
    static let notBuilt: TimelineScanSource
    /// `.on`: the distinct scan days. `.off` or `.notBuilt`: an empty list, and `scans` is not called.
    func read() async -> (state: TimelineSourceState, days: [String])
    /// `scans.map(\.day)` with repeats removed, in first-seen order.
    static func days(of scans: [BodyScan]) -> [String]
}

@MainActor
struct TimelineEventSource {
    init(state: @escaping () -> TimelineSourceState, events: @escaping () -> [PersonalEvent])
    /// Stage 5 merged: state from `store.isEnabled`, events from the property `store.events`.
    static func live(store: PersonalEventStore = .shared) -> TimelineEventSource
    /// Stage 5 not in this build.
    static let notBuilt: TimelineEventSource
    /// `.on`: the events the timeline may show. `.off` or `.notBuilt`: empty, and `events` is not read.
    func read() -> (state: TimelineSourceState, events: [PersonalEvent])
    /// `PersonalEvents.visible(events, includeSensitive: false)`, then only `.dietBreak` and `.deload`,
    /// order kept.
    static func timelineEvents(_ events: [PersonalEvent]) -> [PersonalEvent]
    /// Kind, `startDay` and `endDay` only. Label, note and id are not copied.
    static func span(_ event: PersonalEvent) -> TimelineSpan
}
```

Rules:

- **Scan days.** The adapter maps `BodyRecordStore.scans()` to `day` and removes repeats. It reads
  no `labMarker` row itself and derives no day from an instant; whatever day stage 4 gives a scan,
  typed or imported, is the day on the timeline. `state` is `.on` when `noop.bodyRecordEnabled` is
  true and `.off` otherwise; reading the key never writes it.
- **Events.** The adapter reads the synchronous property `PersonalEventStore.events` once per
  load, on the main actor, before the model's first suspension. `state` is `.on` when
  `store.isEnabled` and `.off` otherwise; stage 5's store already returns `[]` and does not touch
  its key while its flag is off.
- **Private events are absent.** Sensitivity in stage 5 is a per-event flag the owner can set on
  any kind. `timelineEvents` passes the list through `PersonalEvents.visible(_, includeSensitive:
  false)` **before** filtering by kind, so a diet break or deload the owner marked private does not
  appear on the timeline at all: no row, no "Private event" placeholder, no count, no footnote.
  `TimelineSpan` carries no label and no note, so no event text can reach a timeline row.
- **One row, one event.** `CheckpointTimelineModel` keeps the list `timelineEvents` returned beside
  the spans it built from it, so `TimelineItem.sourceIndex` leads back to the event for the tap
  that opens stage 5's screen. Stage 6 never writes an event or a scan.
- Until its stage is merged an adapter is `notBuilt`; the body of `live` is written when stage 4
  (for scans) or stage 5 (for events) is on the integration branch.

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
{"character":"positional","id":"n-0a1b2c3d","kind":"complaint","location":"Fixture location B","note":"Fixture note","onsetDay":"2031-03-03","side":"right","trend":"unchanged","updates":[{"day":"2031-03-22","note":"","seq":1,"trend":"worsening","weakness":false}],"v":1,"weakness":false}
```

| Field | Type | Rule |
|---|---|---|
| `kind` | `complaint` or `observation` | An observation is a standing note: it has `location`, `side`, `note` and `onsetDay` ("noted on"); it is never triaged and has no day count |
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
{"professionalRule":"Fixture rule text.","rules":[{"action":"watch","characters":["diffuse"],"fromDay":1,"id":"r-00000001","label":"Fixture label A","note":"","throughDay":10,"trends":["easing"]}],"v":1}
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
{"exercise":"Fixture Press","id":"p-0000000a","niggleId":"n-0a1b2c3d","pausedDay":"2031-03-10","reason":"Fixture reason A","until":"Fixture until text","v":1}
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

`timeline.checkpoints`, two elements:

```json
{"approximate":true,"category":"weightWaypoint","day":"2031-03-19","done":false,"id":"c-000000a1","title":"Fixture waypoint","v":1,"waypointWeightKg":96.0}
{"approximate":false,"category":"targetDate","day":"2031-06-02","done":false,"id":"c-000000a5","phaseStartDay":"2031-01-06","title":"Fixture target date","v":1}
```

```swift
struct StoredCheckpoint: Equatable, Identifiable {
    var id: String                       // "c-<8 lowercase hex>"; empty in a draft, issued on save
    var title: String
    var category: TimelineCheckpointCategory
    var day: String
    var approximate: Bool
    var done: Bool
    var waypointWeightKg: Double?        // weightWaypoint only; kilograms
    var phaseStartDay: String?           // targetDate only
}

enum CheckpointIssue: Equatable {
    case emptyTitle, titleTooLong, invalidDay
    case weightMissing                   // weightWaypoint with no weight
    case weightNotAllowed                // a weight on any other category
    case weightOutOfRange                // outside stage 1's 30–250 kg
    case waypointAtOrBeyondTarget        // §7.3 step 4a
    case phaseMissing                    // targetDate with no phaseStartDay, or one no stored phase has
    case phaseNotAllowed                 // a phaseStartDay on any other category
    case targetDateNotAfterPhaseStart
    case phaseAlreadyHasTargetDate       // another checkpoint is that phase's target date
}

enum CheckpointSaveResult: Equatable {
    case saved(StoredCheckpoint)
    case invalid(CheckpointIssue)
    case limitReached
    case needsAttention                  // the stored list is unreadable; nothing was written
}
```

| Field | Rule |
|---|---|
| `title` | 1 to 60 characters after trimming |
| `day` | Any canonical day, past or future |
| `approximate` | Marks a date the owner has only roughly fixed; shown as "around" |
| `done` | May be set only when `day` is today or earlier |
| `waypointWeightKg` | Required for `weightWaypoint`, refused on every other category. Kilograms, converted from the display unit with the constants stage 1 uses, inside stage 1's 30–250 kg range. **A waypoint, never a target**: the save is refused with `.waypointAtOrBeyondTarget` when `CheckpointTimeline.waypointIssue(weightKg:on:phases:)` says so for the stored phases, that is, when the phase in force on that day is a cut and the weight is at or below its target, or is any other kind and the weight equals its target |
| `phaseStartDay` | Required for `targetDate`, refused on every other category. It must equal the `startDay` of a stored phase; `day` must be after it; and no other stored checkpoint may be the target date of the same phase. A `targetDate` carries no weight: its row shows the phase's own `targetWeightKg` |

At most 200 checkpoints. The key name `targetWeightKg` does not occur in this string; a stored
element that carries it is unreadable in the sense of §9.1.

Operations on `CheckpointTimelineSettings`, all synchronous:

```swift
var checkpoints: [StoredCheckpoint] { get }          // [] while unreadable
var checkpointsNeedAttention: Bool { get }
/// The first issue found, in the order of `CheckpointIssue`'s cases; nil when the checkpoint may be saved.
static func issue(_ checkpoint: StoredCheckpoint, others: [StoredCheckpoint],
                  phases: [CutScorecardStoredPhase]) -> CheckpointIssue?
func save(_ checkpoint: StoredCheckpoint, phases: [CutScorecardStoredPhase]) -> CheckpointSaveResult
@discardableResult func delete(id: String) -> Bool
@discardableResult func setDone(id: String, _ done: Bool, today: String) -> Bool
@discardableResult func discardUnreadableCheckpoints() -> Bool
```

`save` inserts or replaces by id; `others` in `issue` is the stored list without the element being
replaced. The caller passes `CutScorecardSettings().phases`; while `phasesNeedAttention` is true
the caller passes `[]`, so a waypoint saves unchecked (§7.3 step 4a still applies at build time)
and a target date is refused with `.phaseMissing`.

Editing a phase's target in stage 1's sheet does not rewrite any checkpoint. A waypoint that the new
target overtakes keeps its stored weight, and the timeline shows the row without it, with one
footnote (§10.8). Deleting a phase or changing its start day leaves its target-date checkpoint in
place, shown without a phase name until the owner edits or deletes it.

### 9.4 Flags

| Key | Default | Off means |
|---|---|---|
| `noop.niggleLogEnabled` | `false` | No Health row, no screens, nothing read |
| `noop.cutStressEnabled` | `false` | No link on the scorecard, no screen, nothing computed |
| `noop.checkpointTimelineEnabled` | `false` | No link on the scorecard, no Health row, no screen, nothing read |

The cut-stress screen is reachable only from the scorecard, so it also needs
`noop.cutScorecardEnabled`. The timeline works without the scorecard flag (it then has no projection
item, and phases still show). Switching a flag off deletes nothing.

Each flag is observed through one instance of step 0's `ObservableDefaultsFlag`, held as a static on
its settings type (§5). Stage 6 defines no observer class of its own and does not clone
`CutScorecardFlag`. The surface stage 6 calls:

```swift
@MainActor
final class ObservableDefaultsFlag: ObservableObject {
    init(key: String, defaults: UserDefaults = .standard)
    /// The stored value, false when the key is absent; follows every write to the key.
    @Published private(set) var isEnabled: Bool
    /// Writes the one key; the new value is published before this returns.
    func set(_ enabled: Bool)
}
```

Reading it never writes the key. If the scaffolding's surface differs, the scaffolding stands and
the three one-line statics are corrected to it.

### 9.5 Backup

| Canonical key | Kind | Swift storage key | Joins the Swift whitelist |
|---|---|---|---|
| `niggleLog.entries` | String | same | Yes |
| `niggleLog.rules` | String | same | Yes |
| `niggleLog.paused` | String | same | Yes |
| `timeline.checkpoints` | String | same | Yes |
| the three `noop.*` flags | — | — | No: per install, as the whitelist's rule says |

All four join by the owner-decision default of the cross-stage check (§15, Q1). Without them a
restore would silently lose the log, which is the outcome R42 exists to prevent.

Edits to `Packages/WhoopStore/Sources/WhoopStore/BackupSettings.swift`: four entries in
`BackupSettings.whitelist`, four in `appleDefaultsKey`, and the four names added to the fork-only
comment block step 0 placed above the whitelist. The file has one writer at a time across stages, in
the one shared-file order of §14.1; this stage's four entries are added in stage 6's place in that
order, below the entries of every earlier editor. `BackupSettingsTests.swift` is extended in the
same order, new methods only.

**Android drift (R43).** The Kotlin whitelist is not edited and is knowingly behind. A backup made
on the iPhone and restored on Android drops the four keys; a backup made on Android never carries
them; restoring an Android-made backup on the iPhone leaves the four stored strings as they were,
because restore writes only keys present in the file. No marker-catalogue entry, migration or other
shared stored contract moves in this stage.

Sensitivity: the four strings sit in clear text in the backup's `settings.json`, like the events
list of stage 5, and the backup is unencrypted (CONTEXT §7 item 7). The whitelist's header asks that
`settings.json` stay safe to share; a complaint log is health data of the same class as the readings
already in the backup's database. The owner-decision default is to include all four and to raise
encrypted backups in priority; the alternative is in Q1.

## 10. Screens and states

Frames are designed at G1 in `design/round-s6-log-timeline/` (export `s6-frames.json`, plugin
command `importS6`). Every state below needs a frame at the default text size; every screen needs
one at `accessibility5` (`StrandiOSApp.swift:247`). Shared components: `NoopGlassCard`
(`NoopSurfaces.swift:68`), `NoopListRow` (`NoopRows.swift:258`), `ScorecardSectionHeader`,
`ScorecardFootnote`, `ScorecardLinkRow`, `ScorecardSkeletonLines`, `ScorecardDangerButton`
(`StrandiOS/Scorecard/ScorecardKit.swift:205`, `:300`, `:316`, `:353`, `:370`),
`ScorecardWeekChart`. Tokens only. Action colours follow stage 1's approval record (§17 there): red
is for Delete only. A label's action is shown as text, never as red, amber or green (decision D6).

The three surfaces every stage adds to (the Health tab's "More health" card, the Settings screen
and the scorecard screen) are **not** designed in this round. Each has one combined frame covering
all stages, approved once by the owner; this stage's rows go where that frame puts them.

### 10.1 Entry points

The Settings cards and the Health tab rows of every stage follow one order, top to bottom, drawn
in the combined frame set, which is the authority: Scorecard, Coach packet, Intake, Body record,
Events, Niggle log, Recovery context, Timeline. This stage's entries are the last three of that
list, in that order. This specification states only those three places.

| Where | Row | Shown when | Position |
|---|---|---|---|
| Health tab, "More health" card (`RedesignHealthView.swift:472-482`) | "Niggle log", detail = open count or nothing | `noop.niggleLogEnabled` | Sixth place of the one order: the first of this stage's rows |
| Same card | "Timeline", detail = next upcoming item's date or nothing | `noop.checkpointTimelineEnabled` | Eighth and last place of the one order, below "Niggle log" |
| Scorecard screen links card (`ScorecardView.swift:548-559`) | "Recovery context" | `noop.cutStressEnabled` | Per the combined scorecard frame; above "Timeline" |
| Same card | "Timeline" | `noop.checkpointTimelineEnabled` | Per the combined scorecard frame; below "Recovery context" |
| Settings | Card "Niggle log", holding the switch for `noop.niggleLogEnabled` | iPhone only; macOS does not show it | Sixth place of the one order |
| Settings | Card "Recovery context", holding the switch for `noop.cutStressEnabled` | iPhone only | Seventh place |
| Settings | Card "Timeline", holding the switch for `noop.checkpointTimelineEnabled` | iPhone only | Eighth and last place |

Recovery context has the seventh place of the one order. Its Settings card takes that place. Its
entry point is the scorecard screen's link row, and this stage adds no "Recovery context" row to
the Health card, so on that card this stage's two rows are adjacent.

A Settings card is the place its own switch is turned on, so the three cards are present on
iPhone whether their switch is on or off; each shows its title, its one-line description and its
switch, and nothing else. A Health row or a scorecard link is present only while its own flag is
on.

A row whose flag is off is simply absent; the order of the rows that are present does not
change. With all three stage 6 flags off the Health card, the scorecard links
card and every other screen are exactly as before.

The "Next:" detail on the Health row is the date of the first `upcoming` item of the built list
(§7.3), so it can never name a private event (§8.4) and never shows a title, a weight or a label.

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

No horizontal rule, band or typical-range shading on either curve. `ScorecardWeekChart` is reused as
it stands after stage 5's change; the cut-stress screen passes no `axisMarks`, so no event mark is
drawn on these curves.

### 10.8 Timeline screen

One list, oldest first, opened scrolled to the today marker.

| State | What shows |
|---|---|
| Loading | Skeleton rows |
| Nothing but today | "Nothing on your timeline yet" with "Add a checkpoint" and, when no phase exists and the scorecard is on, "Set up your phase" |
| Phase start | The phase name, "started <date>" or "starts <date>", and "Target <weight>" when the phase has one. Opens stage 1's phase sheet |
| Checkpoint, upcoming | Title, date ("around <date>" when approximate), category |
| Checkpoint, past, done | The same, marked done |
| Checkpoint, past, not done | The same with "Not marked done". No red, no "overdue", no count |
| Weight waypoint | As any checkpoint, plus "Waypoint <weight>". The word "target" does not appear on the row |
| Weight waypoint at or past the phase target (the target was changed after it was saved) | The row without its weight, and one footnote for the list: "A waypoint at or past your target weight is not shown" with a link to the checkpoint |
| Target date, phase found | "Target date for <phase name>", the date ("around <date>" when approximate), and "Target <weight>" read from that phase when it has one. Tapping the weight opens stage 1's phase sheet; tapping the row opens the checkpoint sheet |
| Target date, phase no longer stored | "Target date", the title and the date; no phase name, no weight |
| Scan | "Scan" and the date; opens stage 4's screen (`RedesignRoute.bodyRecord`) |
| Diet break / deload, past | Kind and "<start> to <end>"; opens stage 5's screen (`RedesignRoute.personalEvents`) |
| Diet break / deload, current | "Since <start>" or "<start> to <end>", placed before the today marker by its start day and tagged "now" |
| Diet break / deload, open-ended | "Since <start>" |
| Diet break / deload the owner marked private | Absent: no row, no placeholder, no footnote, no count (§8.4) |
| Any other event kind (travel, illness, supplement change, custom) | Absent |
| Projection | "Estimated <date> at this rate" and the phase's target weight; tagged "estimate"; opens the scorecard |
| No projection | No item; nothing is said (the scorecard explains why) |
| Scans: stage 4 not in this build (`notBuilt`) | No scan items and no mention |
| Scans: stage 4 present, its setting off (`off`) | No scan items; one footnote: "Scans are not shown while the body record is off" |
| Events: `notBuilt` / `off` | As for scans, with "Breaks and deloads are not shown while events are off" |
| Scorecard flag off | Phases still show; no projection item; a footnote: "No estimate while the scorecard is off" |
| Checkpoints need attention | The banner of §10.2's shape; adding disabled; other items still show |
| Phases need attention (`phasesNeedAttention`) | No phase items; target-date rows show without a phase; a footnote linking to the phase sheet |
| Largest text size | Date above title; nothing truncates a date |
| Reduce Motion | No staggered entrance |

The time axis is the list itself. No horizontal rule or band is drawn; a span is a row, not a bar
across other rows. A span row shows the kind and its dates only: an event's label and note are never
shown on the timeline. A break or a deload appears here only as a stage 5 event; the screen offers
"Add a checkpoint" and never "add a phase" for one (§1).

Checkpoint sheet (add or edit):

| State | Behaviour |
|---|---|
| Any category | Title; category; date; "approximate" toggle; "done" toggle (only when the date is today or earlier); delete asks once |
| Category "Weight waypoint" | A weight field in the display unit, captioned "A waypoint on the way. Your target weight is set in your phase." |
| Waypoint at or beyond the target | "Save" disabled; the field says "A waypoint has to be short of your target (<weight>)." with the link "Edit phase", which opens stage 1's phase sheet |
| Category "Target date" | A phase picker listing the stored phases by name (the active phase preselected); no weight field; the caption shows that phase's "Target <weight>" read-only with the link "Edit phase" |
| Target date, no stored phase | The category cannot be saved: "Set up your phase first" with the link to the phase sheet |
| Target date on or before the phase's start | "Save" disabled: "Choose a date after the phase starts" |
| Target date, the phase already has one | "Save" disabled: "This phase already has a target date" with a link that opens that checkpoint |
| Other invalid input | Empty title, or a waypoint weight outside stage 1's 30–250 kg range: marked, "Save" disabled |
| Save refused by the store | The sheet stays open with its values intact and the reason (§9.3) |

### 10.9 Widgets and notifications

**None.** Stage 6 adds no widget, no widget payload field, no notification request and no Shortcuts
action. The notification count is unchanged. A complaint log is of the sensitive kind stage 5's
roadmap entry keeps out of widgets and notifications; the test in §12.3 asserts no stage 6 string
or stored key is read by the widget publish path or by any `UNNotification` request. Stage 6 adds
no file that builds `UNMutableNotificationContent`, so stage 5's notification-producer scan needs no
new entry for this stage.

## 11. User-facing strings

Built by the three presenters through the String Catalog, ten locales. The owner's own text (labels,
notes, the professional rule, locations, titles, exercises, reasons) is shown verbatim and is never
translated, capitalised or shortened. English sources:

| Case | String |
|---|---|
| Health rows | "Niggle log", "Timeline"; details "%lld open", "Next: %@" |
| Scorecard links | "Recovery context", "Timeline" |
| Settings (three cards, each a title and a description) | "Niggle log" / "Record a complaint and see it against your own rules. Off by default."; "Recovery context" / "Weekly resting heart rate and HRV beside the scorecard. Not a score."; "Timeline" / "Phases, checkpoints and your estimate in one list." |
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
| Timeline items | "%@ started %@", "%@ starts %@", "Target %@", "Waypoint %@", "Target date for %@", "Target date", "around %@", "Scan", "Diet break", "Deload", "%@ to %@", "Since %@", "now", "Estimated %@ at this rate", "estimate", "Not marked done", "Done" |
| Checkpoint categories | "Scan", "Blood panel", "Benchmark", "Weight waypoint", "Target date", "Appointment", "Other" |
| Checkpoint sheet | "A waypoint on the way. Your target weight is set in your phase.", "A waypoint has to be short of your target (%@).", "Edit phase", "Set up your phase first", "Choose a date after the phase starts", "This phase already has a target date" |
| Timeline footnotes | "Scans are not shown while the body record is off", "Breaks and deloads are not shown while events are off", "No estimate while the scorecard is off", "A waypoint at or past your target weight is not shown", "Nothing on your timeline yet" |

None of these states or implies a cause, a prognosis or a treatment. "See a professional" appears
only as the name of an action the owner assigned to their own rule. "Estimated" and "estimate" mark
the projection. "Target" is used only for the phase's stored target weight and for the target date;
a checkpoint weight is always "waypoint". No string here contains an event's label or note, and none
says "Private event": a private event has no row.

## 12. Test plan

One named test per line.

### 12.1 Pure logic — `Packages/StrandAnalytics/Tests/StrandAnalyticsTests/`

`CanonicalDayTests.swift` is created by step 0 with `CanonicalDay`, and carries at least the test
that pins it to `CutScorecard.weekStart`. Stage 6's Test author does not create the file. Any of the
six tests below that step 0's file lacks is added to it as a new method, in the same serialised
commit as this stage's other shared-file edits:

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
- `testTargetWeightIsCarriedOnlyOnPhaseStartItems` (every checkpoint item has `targetWeightKg` nil)
- `testWaypointWeightIsCarriedOnlyForWeightWaypoints`
- `testNonFiniteTargetWeightIsDroppedAndCounted`
- `testNonFiniteOrNonPositiveWaypointWeightIsDroppedAndCounted`
- `testWaypointShortOfACutTargetKeepsItsWeight`
- `testWaypointEqualToACutTargetLosesItsWeightAndIsCounted`
- `testWaypointBelowACutTargetLosesItsWeightAndIsCounted`
- `testWaypointEqualToANonCutTargetLosesItsWeight` / `testWaypointEitherSideOfANonCutTargetKeepsItsWeight`
- `testWaypointWithNoGoverningPhaseOrNoPhaseTargetIsKept`
- `testWaypointIsJudgedAgainstThePhaseInForceOnItsOwnDay` (two phases with different targets)
- `testWaypointItemStaysWhenItsWeightIsDropped`
- `testWaypointIssueAgreesWithBuildForEveryCase`
- `testGoverningPhaseIsTheLatestStartOnOrBeforeTheDay`
- `testGoverningPhaseTakesTheGreaterIndexAmongEqualStartDays`
- `testGoverningPhaseIsNilBeforeTheFirstPhaseAndForANonCanonicalDay`
- `testTargetDateCarriesItsPhaseIndexAndNoWeight`
- `testTargetDateForAnUnknownPhaseHasNoPhaseIndex`
- `testSecondTargetDateForOnePhaseIsDroppedAsDuplicate`
- `testPhaseIndexIsNilForEveryOtherCategory`
- `testInvalidDaysAreRejectedPerKind`
- `testInvalidTodayGivesAnEmptyList`
- `testFixtureTimelineGivesTheExpectedList` (§13.4, at three values of today, and the changed-target variant)
- `testSameInputSameOutput`

### 12.2 Store — `Packages/WhoopStore/Tests/WhoopStoreTests/BackupSettingsTests.swift` (extended)

New methods only, placed in this stage's place in the shared-file order of §14.1, below the
methods of every earlier editor.

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
- `testTypicalRangeEqualsRecoveryDetailsRange` (single resolver: for the same `BaselineState`, the
  range the cut-stress presenter prints, the value of `ChargeTypicalBand.range` and the range in
  `RecoveryDetailModel`'s factor are one range)
- `testChartIsGivenNoAxisMarks`
- `testNoStringCarriesAJudgementWord` (elevated, suppressed, high, low, good, bad, warning, stress
  outside the fixed framing sentence)
- `testNightCountsAreShownBesideEveryMean`
- `testWeekBelowMinimumIsNotMeasuredNeverZero`

`CheckpointTimelineSettingsTests.swift` — the storage tests of the niggle settings, for checkpoints
(flag default, round trip with sorted keys and version, reading never writes, unreadable list,
refused save while unreadable, discard, replace by id, delete, limit, trimming); plus

- `testWaypointRoundTripsUnderTheKeyWaypointWeightKg`
- `testAStoredElementCarryingTargetWeightKgIsUnreadable`
- `testWaypointWithoutAWeightIsRefused` / `testWeightOnAnotherCategoryIsRefused`
- `testWaypointOutsideThirtyToTwoHundredFiftyKgIsRefused`
- `testWaypointEqualToTheCutTargetIsRefused` / `testWaypointBelowTheCutTargetIsRefused`
- `testWaypointShortOfTheCutTargetIsSaved`
- `testWaypointIsSavedWhenNoPhaseGovernsItsDay`
- `testTargetDateNeedsAStoredPhase` / `testPhaseOnAnotherCategoryIsRefused`
- `testTargetDateOnOrBeforeThePhaseStartIsRefused`
- `testSecondTargetDateForAPhaseIsRefused` / `testEditingThePhasesOwnTargetDateIsNotASecondOne`
- `testTargetDateStoresNoWeight`
- `testIssueReportsTheFirstIssueInDeclarationOrder`
- `testSetDoneIsRefusedForAFutureDay`
- `testChangingThePhaseTargetRewritesNoCheckpoint`
- `testGoverningPhaseAgreesWithCutScorecardSettingsActivePhase` (a spread of days over stored
  phases: `CheckpointTimeline.governingPhaseIndex` picks the phase `activePhase(on:)` returns)
- `testStoredCheckpointsContainNoDeviceIdentifier` / `testRemovingEveryRegisteredStrapLeavesCheckpointsReadable`

`TimelineSourcesTests.swift`

- `testScanDaysAreDistinctInFirstSeenOrder`
- `testScanDayIsTakenFromTheScanAndNotFromItsInstant` (a `BodyScan` whose `day` differs from the
  local day of its `takenAt` yields its `day`)
- `testScanSourceOffReturnsNothingAndNeverCallsScans`
- `testScanSourceStateFollowsTheBodyRecordKeyWithoutWritingIt`
- `testNotBuiltSourcesReturnNothing`
- `testEventSourceReadsTheStorePropertyOncePerRead`
- `testEventSourceOffReturnsNothingAndNeverReadsEvents`
- `testOnlyDietBreaksAndDeloadsBecomeSpans` (one event of every `PersonalEventKind`)
- `testPrivateDeloadIsAbsentFromTheTimeline` (a deload with `sensitive: true` beside a public one:
  one span; then built through `CheckpointTimeline.build`: one deload item)
- `testPrivateDietBreakIsAbsentFromTheTimeline`
- `testSpanCopiesKindAndDaysOnly` (an event with a label and a note: neither string occurs in the
  encoded span, the built items or any presenter row)
- `testOngoingEventBecomesAnOpenEndedSpan`

`CheckpointTimelineModelTests.swift`, `CheckpointTimelinePresenterTests.swift` — one test per row
of §10.8; plus

- `testProjectionDayEqualsTheScorecardModelsProjectionDay` (single resolver: one store, one shared
  `CutScorecardModel`; the timeline item's day equals `evaluation.result.projection.targetDay`)
- `testTimelineNeverEvaluatesTheScorecardItself` (an injected evaluator counts calls: one)
- `testModelEvaluationIsTheValueTheBuilderFunnelReturned` (`CutScorecardModel.evaluation` after
  `load()` equals `CutScorecardInputBuilder.evaluation(today:)` for the same store and day, and is
  nil while idle)
- `testPhaseItemsEqualStoredPhases`
- `testTargetWeightUsesTheScorecardsWording`
- `testTargetDateRowShowsThePhasesStoredTargetWeight` (change the phase target: the row follows,
  and no checkpoint was rewritten)
- `testTargetDateRowWithoutItsPhaseShowsNoWeight`
- `testWaypointRowIsNeverWordedAsATarget` (no string of a waypoint row contains "target",
  case-insensitive, in the English source)
- `testWaypointPastTheTargetShowsTheRowWithoutWeightAndOneFootnote`
- `testPrivateEventLeavesNoRowNoFootnoteAndNoCount`
- `testSpanRowShowsKindAndDatesOnly`
- `testHealthRowNextDetailIsADateOnly`
- `testScanItemOpensTheBodyRecordRoute` / `testSpanItemOpensTheEventsRoute`
- `testNoStringOffersAPhaseForABreakOrDeload`
- `testScanSourceNotBuiltShowsNoFootnote` / `testScanSourceOffShowsTheFootnote` (and the two for events)
- `testScorecardFlagOffKeepsPhasesAndDropsTheEstimate`
- `testPastCheckpointNotDoneHasNoOverdueWording`
- `testViewRowsAreExactlyTheBuiltItemsInOrder`

`Stage6FlagOffTests.swift`

- `testAllFlagsOffAddsNoHealthRowNoScorecardLinkAndNoRoute`
- `testAllFlagsOffReadsNoStage6Key` (a defaults suite that records reads)
- `testSwitchingAFlagOffDeletesNothing`
- `testCutScorecardModelPresentationIsUnchangedByTheNewProperty`
- `testEachFlagIsOneObservableDefaultsFlagOverItsKey` (the three statics follow a write to their
  key made by any writer, and reading them writes nothing)
- `testTimelineOffReadsNeitherTheBodyRecordNorTheEventsStore`

`Stage6PrivacyTests.swift`

- `testWidgetSnapshotContainsNoStage6Text` (encode the widget snapshot with a full fixture stored;
  scan for every fixture location, label, exercise and title)
- `testNoNotificationRequestIsAddedByStage6`
- `testCoachContextContainsNoStage6Text` (`AICoach.buildContext` and `buildFullContext` output
  scanned for the same strings)
- `testCoachPacketContainsNoStage6Text` (once stage 2 is merged: the assembled packet, every
  section on, scanned for the same strings)
- `testBackupSettingsCarryStage6ListsAndNoFlag`

### 12.4 Source scan — `Tools/test_stage6_single_source.py`

Modelled on `Tools/test_body_measurement_single_resolver.py:204-237`, with a literal allowlist that
must still match.

- `test_niggle_keys_are_read_only_by_their_store` (the four key literals appear only in
  `NiggleLogSettings.swift`, `CheckpointTimelineSettings.swift` and `BackupSettings.swift`)
- `test_triage_is_called_only_by_the_niggle_model`
- `test_cut_stress_is_referenced_only_by_its_own_surfaces` (§8.2 list; fails on any reference from
  `IntelligenceEngine`, a scorer, `CutScorecard*`, `AICoach*`, `CoachPacket*`, `StrandiOSWidgets/`,
  `StrandiOSShared/`)
- `test_timeline_is_built_only_by_its_model`
- `test_typical_band_has_one_definition` (tree-wide over the app targets: exactly one declaration
  of `ChargeTypicalBand` and of its `range(` function, in `ChargeTypicalBand.swift`; the cut-stress
  presenter contains `ChargeTypicalBand.range(`; no stage 6 file builds a `ClosedRange` from a
  `BaselineState` by any other means; the spread function that `ChargeTypicalBand.range` wraps is called in the app
  targets from `ChargeTypicalBand.swift` alone. The last clause holds because stage 2's packet
  assembler takes the range from `ChargeTypicalBand.range(_:)` and holds no sigma, as the build
  order requires)
- `test_stage6_defines_no_flag_observer` (`UserDefaults.didChangeNotification` appears in no stage 6
  file; each stage 6 flag is an `ObservableDefaultsFlag(`)
- `test_stage6_has_no_day_arithmetic_of_its_own` (`parseYMD(`, `julianDayNumber(`, `DateFormatter`
  and `Calendar` appear in no stage 6 pure file; day keys go through `CanonicalDay.`)
- `test_other_stage_stores_are_named_only_in_the_adapters` (`BodyRecordStore` and
  `PersonalEventStore` appear in stage 6 files only in `TimelineSources.swift`, and that file
  contains `PersonalEvents.visible(`)
- `test_checkpoints_carry_no_target_weight` (`targetWeightKg` appears in no stage 6 storage file,
  and in `CheckpointTimeline.swift` only on `TimelinePhase` and `TimelineItem`)
- `test_scorecard_evaluation_has_one_caller_in_stage6` (`evaluation(today:` and
  `CutScorecard.evaluate(` appear in no stage 6 file)
- `test_stage6_adds_no_kotlin` (no file under `android/` contains a stage 6 key or type name; the
  recorded disposition, so the drift of §9.5 is a decision and not an accident)
- `test_allowlist_entries_still_match`

### 12.5 Flag-off equivalence

With the three flags off: no Health row, no scorecard link, no screen, no stored key read, nothing
computed, neither adapter read, and the baseline suite's results are unchanged. The one stage 6
edit that runs with the flags off is the new stored property on `CutScorecardModel` (asserted by
`testCutScorecardModelPresentationIsUnchangedByTheNewProperty`). The extraction of the typical
range is step 0's edit, not this stage's; `testTypicalRangeEqualsRecoveryDetailsRange` still pins
the cut-stress screen to it.

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
| F32 | The event adapter filters by kind before, or without, the sensitivity filter | `testPrivateDeloadIsAbsentFromTheTimeline` |
| F33 | A private event rendered as a "Private event" row | `testPrivateEventLeavesNoRowNoFootnoteAndNoCount` |
| F34 | An event's note copied into the span | `testSpanCopiesKindAndDaysOnly` |
| F35 | Scan days not de-duplicated, or derived from `takenAt` | `testScanDaysAreDistinctInFirstSeenOrder`, `testScanDayIsTakenFromTheScanAndNotFromItsInstant` |
| F36 | The store accepts a waypoint equal to the cut target | `testWaypointEqualToTheCutTargetIsRefused` |
| F37 | The build keeps a waypoint weight the target has overtaken | `testWaypointEqualToACutTargetLosesItsWeightAndIsCounted` |
| F38 | A waypoint row worded "Target" | `testWaypointRowIsNeverWordedAsATarget` |
| F39 | A weight stored on a target-date checkpoint | `testTargetDateStoresNoWeight`, `test_checkpoints_carry_no_target_weight` |
| F40 | Two target dates kept for one phase | `testSecondTargetDateForAPhaseIsRefused`, `testSecondTargetDateForOnePhaseIsDroppedAsDuplicate` |
| F41 | The timeline model calls the builder's funnel itself | `test_scorecard_evaluation_has_one_caller_in_stage6`, `testTimelineNeverEvaluatesTheScorecardItself` |
| F42 | A stage 6 settings type clones the flag observer | `test_stage6_defines_no_flag_observer` |
| F43 | The model's `evaluation` set from a second evaluation | `testModelEvaluationIsTheValueTheBuilderFunnelReturned` |

### 12.7 Parity: written dispositions (R43)

Android is skipped by the owner's decision. No Kotlin is written or run and no oracle is built.

| Piece | Disposition |
|---|---|
| `NiggleTriage`, `CutStressTrend`, `CheckpointTimeline` | Shared pure logic with **no Kotlin twin, by the owner's decision**. Each produces display values only; none writes a stored value or changes an existing formula. The parity ratchet's Kotlin lines for these declarations are recorded debt, as R43 states. Each public declaration carries the doc-comment line "No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43)." |
| `CanonicalDay` | Step 0's file; its disposition is recorded with step 0 |
| The four backup keys | Swift only; the drift is the paragraph in §9.5 |
| Marker catalogue, `DashboardCard` ids, migrations | Not touched |
| Gate script | Android rows waived by flag and reported as waived; the parity-oracle row is NOT RUN, with this section cited as the reason |

### 12.8 Simulator and rehearsal

Every frame of §10 is reproduced through `Stage6Demo`, which is one element of step 0's demo
registry: this stage adds its own file, `StrandiOS/NiggleLog/Stage6Demo.swift`, and one registry
element, in stage 6's place in the shared-file order of §14.1, and edits no other demo line. The
element answers only names that begin with one of this stage's three reserved prefixes and returns
nil for every other name:

| Prefix | Names |
|---|---|
| `niggle-` | `niggle-log-<n>`, `niggle-detail-<n>`, `niggle-sheet-<n>`, `niggle-rules-<n>`, `niggle-paused-<n>`, `niggle-flow-<step>` |
| `cutstress-` | `cutstress-<n>` |
| `timeline-` | `timeline-<n>`, `timeline-sheet-<n>`, `timeline-flow-<step>` |

The `-flow-` names are simulator-only flows. Each state runs at default and largest text size, with
Reduce Motion on and off; add, edit, update, resolve, reopen, delete, reorder rules, pause and
resume, add and tick a checkpoint, a refused waypoint and a target date are exercised by tapping.

One Fixture Person serves every stage's demo. `Stage6Demo` defines no weights, phases, scans or
events of its own: its scorecard states are seeded by the seeding stage 1's demo uses (the stage 1
weekly series, weigh-ins on Wednesdays, protein floor 100 g), and its scan days and spans are the
Fixture Person's of §13.4, given to the two adapters through their closure initialisers (§8.4). It
adds only the stage 6 strings of §13 and the nights of §13.3.
Per stage 1 ruling R31, app-target tests and simulator runs that read nights from the repository use
dates relative to the real clock; the 2031 fixture is for the pure functions and the settings.

Rehearsal on real data, private (0B-7): on a restored copy, the owner enters entries of their own
choosing in each of the three parts and confirms each can be expressed without a workaround, then
opens the cut-stress screen and the timeline. Results stay under `PersonalData/` and are not
described in this repository.

## 13. Fixture

Everything here is invented. "Fixture Person" does not exist; every label, location, number and
date was made up for this document and the values are round on purpose.

There is **one** Fixture Person across all stages, and stage 1's §13 is the reference: phase
"Fixture cut", kind cut, start 2031-01-06 (a Monday), target 94.0 kg; weigh-ins on Wednesdays from
2031-01-08, starting at 100.0 kg; protein floor 100 g; exercises "Fixture Press" and "Fixture Row".
This section adds only what stage 6 needs and contradicts none of it. The tables below are
pure-logic goldens and keep their own invented values where stage 1 has none; the demo seed takes
its weights, scans and events from stages 1, 4 and 5 (§12.8).

### 13.1 Rules

Professional rule text: "Fixture rule text."

| Order | id | Label | Action | Characters | Trends | Weakness | From | Through |
|---|---|---|---|---|---|---|---|---|
| 1 | `r-a` | Fixture label A | watch | diffuse | easing | either | 1 | 10 |
| 2 | `r-b` | Fixture label B | modify | positional | any | either | 5 | none |
| 3 | `r-c` | Fixture label C | seeProfessional | any | any | either | 30 | none |
| 4 | `r-d` | Fixture label D | seeProfessional | any | worsening | either | 20 | none |
| 5 | `r-e` | Fixture label E | modify | localised | any | with | 1 | none |

### 13.2 Complaints and expected results

Locations are the strings "Fixture location A" to "Fixture location E". Sides are spread over the
enum's values only so that every case is exercised.

| # | Complaint | Today | n | Status | Rule | Matched | Ignored updates | Next change |
|---|---|---|---|---|---|---|---|---|
| N1 | "Fixture location A", left, diffuse, easing, onset 2031-02-03, resolved 2031-02-12 | 2031-03-01 | 10 | resolved | — | — | 0 | — |
| N2a | "Fixture location B", right, positional, unchanged, onset 2031-03-03, update 2031-03-22 seq 1 worsening | 2031-03-03 | 1 | noRuleMatches | — | — | 1 | day 5, 2031-03-07, `r-b` modify |
| N2b | same | 2031-03-07 | 5 | matched | `r-b` modify | `r-b` | 1 | day 30, 2031-04-01, `r-c` seeProfessional |
| N2c | same | 2031-03-21 | 19 | matched | `r-b` modify | `r-b` | 1 | day 30, 2031-04-01, `r-c` |
| N2d | same | 2031-03-22 | 20 | matched | `r-d` seeProfessional | `r-b`, `r-d` | 0 | day 30, 2031-04-01, `r-c` (equal severity, earlier rule) |
| N3 | "Fixture location C", both, localised, unchanged, weakness, onset 2031-04-07 | 2031-04-07 | 1 | matched | `r-e` modify | `r-e` | 0 | day 30, 2031-05-06, `r-c` |
| N4 | Observation "Fixture observation", notApplicable, noted 2031-01-13 | any | — | not triaged | — | — | — | — |
| N5 | "Fixture location D", right, diffuse, notRecorded, onset 2031-05-05 | 2031-05-14 | 10 | noRuleMatches | — | — | 0 | day 30, 2031-06-03, `r-c` |
| N6a | "Fixture location E", left, diffuse, easing, onset 2031-06-02 | 2031-06-11 | 10 | matched | `r-a` watch | `r-a` | 0 | day 11, 2031-06-12, none |
| N6b | same | 2031-06-12 | 11 | noRuleMatches | — | — | 0 | day 30, 2031-07-01, `r-c` |

In N2a to N2c the update is dated after `today`, so it is ignored and counted, and the current
trend is the onset's "unchanged" with `stateDay` 2031-03-03. In N2d the update is kept: the current
trend is "worsening" and `stateDay` is 2031-03-22.

A second "Fixture location B", right, onset 2031-06-16, gives a recurrence count of 1 against N2.
The same location with side left gives 0.

Paused: "Fixture Press", paused 2031-03-10, reason "Fixture reason A", until "Fixture until text",
linked to N2. "Fixture Row", paused 2031-01-20, reason "Fixture reason B", resumed 2031-02-10.

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

Inputs. Phases: P0 [Fixture cut, 2031-01-06, cut, target 94.0] and P1 [Fixture hold, 2031-06-16,
other, no target]. Checkpoints, in input order:

| # | Title | Category | Day | Other fields |
|---|---|---|---|---|
| C1 | "Fixture waypoint" | weightWaypoint | 2031-03-19 | approximate; waypoint 96.0; not done |
| C2 | "Fixture panel" | bloodPanel | 2031-02-10 | done |
| C3 | "Fixture second scan" | scan | 2031-03-17 | not done |
| C4 | "Fixture benchmark" | benchmark | 2031-02-05 | not done |
| C5 | "Fixture target date" | targetDate | 2031-06-02 | `phaseStartDay` 2031-01-06; no weight; not done |

Scan days: 2031-01-08, 2031-03-17. Spans: deload 2031-02-17 to 2031-02-23; diet break 2031-03-24,
open-ended. Projection: `projected`, 2031-05-27. Both sources `on`.

Expected with `today` 2031-02-05, in order: phaseStart P0 01-06 (past, target 94.0); scan 01-08
(past); checkpoint C4 02-05 (current); today; checkpoint C2 02-10 (upcoming); deload 02-17
(upcoming); scan 03-17 is rejected as `futureScan`, so checkpoint C3 03-17 stays (upcoming);
checkpoint C1 03-19 (upcoming, approximate, waypoint 96.0, `targetWeightKg` nil); dietBreak 03-24
(upcoming, open); projection 05-27 (upcoming, estimate); checkpoint C5 06-02 (upcoming,
`phaseIndex` 0, no weight of either kind); phaseStart P1 06-16 (upcoming). Rejections: `futureScan`
1, all others 0.

With `today` 2031-03-24: phaseStart P0; scan 01-08; C4; C2; deload (past); scan 03-17 is kept and
C3 is dropped (`duplicate` 1); C1 03-19 (past); dietBreak 03-24 (current, open) precedes the today
marker; today; projection 05-27; C5 06-02; phaseStart P1.

With `today` 2031-02-20, `events` `off` and projection nil: no deload, no diet break, no projection;
`events` echoed as `off`; `futureScan` 1.

Changed-target variant: the first case with P0's target 96.0. C1's item stays with
`waypointWeightKg` nil; `waypointBeyondTarget` 1; nothing else changes, and the phaseStart item
carries 96.0. With P0's target 95.9 the waypoint keeps 96.0 and the counter is 0.

Adapter fixture (§8.4), for `TimelineSourcesTests`: events E1 deload 2031-02-17 to 2031-02-23,
`sensitive` false; E2 deload 2031-04-07 to 2031-04-13, `sensitive` true, note "Fixture note";
E3 dietBreak 2031-03-24, ongoing, `sensitive` false; E4 travel 2031-05-05 to 2031-05-09,
`sensitive` false. Expected spans: E1 and E3 only. Scans with days 2031-01-08, 2031-03-17,
2031-01-08: expected days 2031-01-08, 2031-03-17.

These tables were worked by hand from §7 for this document, not produced by an implementation. The
Test author recomputes a row before relying on it and reports any disagreement as a defect in this
table or in §7.

## 14. Work packages and file ownership

A package edits only the files listed for it. Step 0's files (`CanonicalDay.swift`,
`ObservableDefaultsFlag.swift`, `ChargeTypicalBand.swift`, `ScoreDetailData.swift`'s extraction, the
demo registry, the plugin commands and the design folder) are the orchestrator's and are edited by
no stage 6 package.

| WP | Role | Files |
|---|---|---|
| 6-1 | Spec writer | `docs/personal/superapp/specs/stage-6.md` |
| 6-2 | Designer | Files inside `design/round-s6-log-timeline/` only (the folder and the `importS6` command exist from step 0). Not the combined Health, Settings and scorecard frames, which are one shared design task across stages |
| 6-3 | Test author | Every new test file named in §12: `NiggleTriageTests.swift`, `CutStressTrendTests.swift`, `CheckpointTimelineTests.swift`; `NiggleLogSettingsTests.swift`, `NiggleLogModelTests.swift`, `NiggleLogPresenterTests.swift`, `CutStressModelTests.swift`, `CutStressPresenterTests.swift`, `CheckpointTimelineSettingsTests.swift`, `TimelineSourcesTests.swift`, `CheckpointTimelineModelTests.swift`, `CheckpointTimelinePresenterTests.swift`, `Stage6FlagOffTests.swift`, `Stage6PrivacyTests.swift`; `Tools/test_stage6_single_source.py`. The methods for the shared files `BackupSettingsTests.swift` and `CanonicalDayTests.swift` are written by this package and applied in 6-8a |
| 6-4 | Implementer A (pure) | `NiggleTriage.swift`, `CutStressTrend.swift`, `CheckpointTimeline.swift` under `Packages/StrandAnalytics/Sources/StrandAnalytics/` |
| 6-5 | Implementer B (storage) | New: `Strand/Data/NiggleLogSettings.swift`, `CheckpointTimelineSettings.swift`, `TimelineSources.swift` (with both adapters' `notBuilt` values; the `live` bodies are 6-9) |
| 6-6 | Implementer C (niggle log), after G1 and 6-4, 6-5 | New: `Strand/Data/NiggleLogModel.swift`, `NiggleLogPresenter.swift`; `StrandiOS/NiggleLog/*.swift` except the demo |
| 6-7 | Implementer D (cut-stress and timeline), after G1 and 6-4, 6-5 | New: `Strand/Data/CutStressModel.swift`, `CutStressPresenter.swift`, `CheckpointTimelineModel.swift`, `CheckpointTimelinePresenter.swift`; `StrandiOS/Scorecard/CutStressView.swift`; `StrandiOS/Timeline/*.swift` |
| 6-8 | Implementer E (demo), after 6-6 and 6-7 | New: `StrandiOS/NiggleLog/Stage6Demo.swift` |
| 6-8a | Orchestrator: the hotspot commit, one small commit in this stage's serialised step | Edited: `StrandiOS/Redesign/RedesignRoute.swift` (four cases and the route switch); `StrandiOS/Redesign/RedesignHealthView.swift` (two rows in `moreCard`, in the places of §10.1); `StrandiOS/Scorecard/ScorecardView.swift` (two link rows); `Strand/Screens/SettingsView.swift` (three cards, iPhone only, the last three of the one order of §10.1); `Packages/WhoopStore/Sources/WhoopStore/BackupSettings.swift` (four keys and the comment block); `Packages/WhoopStore/Tests/WhoopStoreTests/BackupSettingsTests.swift` (three methods); `StrandiOS/App/StrandiOSApp.swift` debug block (one element in the demo registry) |
| 6-8b | Orchestrator: the scorecard model commit | Edited: `Strand/Data/CutScorecardModel.swift` (the one property of §8.3), in stage 6's place in the shared-file order (§14.1) |
| 6-9 | Implementer B (adapters), after stage 4 and stage 5 are on the integration branch | Edited: `Strand/Data/TimelineSources.swift` (the two `live` bodies) |
| 6-10 | Localiser, last | `Strand/Resources/Localizable.xcstrings` |
| 6-11 | Reviewers (correctness, contract, data safety), Verifier | None; read-only |

### 14.1 Shared hotspots

Every shared file has one writer at a time, in one order for every hotspot: Lab Book ownership, stage 2, stage 3, stage 4, stage 5, stage 6, then packet v2. An
editor that does not touch a given file is skipped. The table states only this stage's position.

| Hotspot | Edited for stage 6 | This stage's position |
|---|---|---|
| `Strand/Resources/Localizable.xcstrings` | **Yes**, 6-10 only, the last step of this stage | Stage 6's place: after stage 5, before packet v2 |
| `Strand/Screens/SettingsView.swift` | **Yes**, 6-8a, three cards | Stage 6's place: after stage 5, before packet v2; after the combined Settings frame is approved. Shared with macOS: build `Strand` afterwards |
| `StrandiOS/App/StrandiOSApp.swift` debug block | **Yes**, 6-8a, one registry element | Stage 6's place: after stage 5, before packet v2. Step 0 lands the registry |
| `StrandiOS/Redesign/RedesignRoute.swift` | **Yes**, 6-8a, four additive cases and the route switch | Stage 6's place: after stage 5, before packet v2 |
| `StrandiOS/Redesign/RedesignHealthView.swift` (`moreCard`) | **Yes**, 6-8a, two rows | Stage 6's place: after stage 5, before packet v2 |
| `StrandiOS/Scorecard/ScorecardView.swift` (`linksCard`) | **Yes**, 6-8a, two link rows | Stage 6's place: after stage 5, before packet v2 |
| `Strand/Data/CutScorecardModel.swift` | **Yes**, 6-8b, the one `evaluation` property | Stage 6's place: after stage 5, before packet v2 |
| `Packages/WhoopStore/Sources/WhoopStore/BackupSettings.swift` and `BackupSettingsTests.swift` | **Yes**, 6-8a, four keys and three test methods | Stage 6's place: after stage 5, before packet v2 |
| `StrandiOS/Scorecard/ScorecardWeekChart.swift` | No; reused as it stands when this stage's step starts, with `axisMarks` present (A11) | Not an editor |
| `StrandiOS/Redesign/ScoreDetailData.swift`, `Strand/Data/ChargeTypicalBand.swift` | No; step 0's. This stage's presenter calls `ChargeTypicalBand.range(_:)` | Not an editor |
| `design/figma-plugin/code.js`, `manifest.json` | No; step 0's | Not an editor |
| `Strand/Data/CutScorecardInputBuilder.swift`, `Strand/Data/CutScorecardPresenter.swift` | No | Not an editor |
| `Strand/Data/BodyMeasurementResolver.swift`, `Strand/Data/BodyMeasurementProvider.swift` | No. Stage 6 reads no body measurement and takes no part in the weigh-in and scan ranking, which is a stage 1 ruling on the resolver | Not an editor |
| `Strand/AI/AICoach.swift`, `CoachPacket*` | No. Stage 6 feeds nothing to the Coach or the packet (§1, §8.2) | Not an editor |
| `Packages/WhoopStore/.../LabMarkerStore.swift` | No. Stage 6 stores nothing in `labMarker` (§9.1) | Not an editor |
| `Strand/Screens/DashboardCards.swift`, `Strand/Data/TodayCardReadout.swift`, the three Today views | No | No Today card (D7) |
| `Packages/StrandImport` `MarkerCatalog` | No | No catalogue key |
| `project.yml` | No | |
| `Packages/WhoopStore/.../Database.swift` | No | No migration |
| Any file that builds `UNMutableNotificationContent` | No | Stage 6 adds no notification |

### 14.2 Parallel and serial

- **In parallel with any other stage, now, with no app build:** 6-2 (design source), 6-3 (new test
  files), 6-4 and its `swift test` (one package at a time per worktree), 6-5, and the new-file code
  of 6-6, 6-7 and 6-8, written but not built.
- **Serialised on the single app build tree, as step 7 of the build order,** after stage 5's step
  and before packet v2: every shared-file edit of this stage (6-8a, 6-8b, 6-10) is made in this
  step and in no earlier one, and the timeline's two adapters (6-9) are written here, when stage 4
  and stage 5 are on the integration branch. In this stage's step: 6-8a, then 6-8b, then `xcodegen
  generate`, the `NOOPiOS` build, the `Strand` build, `StrandTests`, the gate script; 6-10 last.
- **Never built here:** `xcodebuild` and the simulator are run only on the single app build tree by
  the orchestrator, not in a stage worktree.
- Within the stage: 6-4 and 6-5 in parallel; 6-6 and 6-7 in parallel after them and after G1; then
  6-8.
- **Phone:** this stage is installed with stage 5, as one milestone, after a fresh backup, with all
  three flags off until the owner switches each on.

## 15. Open questions for the owner

Every question below is **decided by default**: the recommendation is the design in force and work
proceeds on it. The last column says what changes if the owner decides otherwise.

| # | Question | Decided by default | If the owner says otherwise |
|---|---|---|---|
| Q1 | Should the niggle log, rules, paused list and checkpoints be included in backups? They are four of the seven new settings keys from stages 3, 5 and 6; they join the iPhone backup only, in clear text, with Android knowingly behind | Yes, all four, so a restore cannot lose the log; encrypted backups are raised in priority | Excluding a key removes its two lines from `BackupSettings.swift` and its name from the comment block, and `testStage6ListsRoundTripAsStrings` asserts its absence instead. A restore then starts with that list empty |
| Q2 | When several of your rules fit a complaint, which label shows? | The most serious action; between equals, the higher rule in your list | First-match-in-your-order would replace step 10 of §7.1 and the tests F2, F3 |
| Q3 | Is the day count "day 1" on the day it started? | Yes | Day 0 on the onset day removes the `+ 1` in §7.1 steps 6, 7 and 11 and shifts every table in §13.2 |
| Q4 | Are four characters enough ("spread over an area", "one spot", "only in one position or movement", "something else"), and three actions ("watch", "modify training", "see a professional")? | Yes. They are fixed lists so that rules can refer to them; your own words go in the label and the note | A new case is one enum value, one string and one stored raw value; stored entries stay readable |
| Q5 | Should the app ship example rules? | No. Labels come only from rules you type; the sheet starts empty | Examples would need the owner's own wording and a way to tell them from typed rules; `testNoRulesAreStoredByDefault` would change |
| Q6 | Should niggles and paused exercises go into the coach packet? | No. The packet's next version adds intake and events only; a niggle section stays out until you ask | A later packet change adds a section that is off by default, with its own version bump and goldens, owned by stage 2's grammar |
| Q7 | Should the log have a Today card? | No. It lives under Health; Today stays as it is | A card is a separate change touching the Today hotspot files |
| Q8 | Should a paused exercise be flagged when an imported session contains it? | No. The list is a record, not a check | Name matching against lift sessions would need its own design |
| Q9 | Recovery context: weekly averages need at least four nights in the week. Right number? | Four, the count the app already uses before trusting a baseline provisionally (`Baselines.swift:98`) | `minNightsPerWeek` is one parameter; §13.3's expected means change with it |
| Q10 | Recovery context: should the screen say whether a change is good or bad, or feed any score? | No. It shows the numbers with no good or bad wording and feeds no score | Any judgement wording or downstream use falls under the derived-signal rule and needs its own validation first |
| Q11 | Timeline: only diet breaks and deloads from the events layer, or travel and illness too? | Only the two the roadmap names, and never one you marked private | Another kind is one more case in `TimelineSpanKind` and `TimelineItemKind`; private events stay absent in every case |
| Q12 | Timeline: should open niggles appear on it? | No | A new item kind and a second reader of `NiggleTriage`'s result, through `NiggleLogModel` |
| Q13 | Timeline: a planned scan is a checkpoint you enter; when you record the scan on that exact day the checkpoint is replaced by it. On another day both show until you tick or delete the checkpoint. Acceptable? | Yes | A matching window in days would replace the equality in §7.3 step 4c |
| Q14 | A past checkpoint that is not ticked shows "Not marked done" and nothing else. Acceptable? | Yes | |
| Q15 | Three separate switches, or one? No Today card, no notification | Three, so each part can be accepted on the phone on its own | One switch collapses the three keys of §9.4 into one |
| Q16 | A weight on a checkpoint is a **waypoint only**. The one target weight stays in your phase; a waypoint is never called a target, the scorecard never reads it, and the sheet refuses a waypoint equal to or beyond the phase target and points to the phase sheet. The date you want to reach the target by is a checkpoint with no weight, attached to the phase. Acceptable? | Yes | If a checkpoint were allowed its own target weight, the scorecard's projection and the timeline could show two targets for one variable (R41); that would need a new ruling on which one the scorecard judges, and §7.3 step 4, §9.3 and the F36 to F40 tests would be rewritten |
| Q17 | A diet break or a deload is an event, never a phase; phases are only the long blocks. During one the scorecard keeps giving its verdict with the event noted beneath it, and the timeline shows it as a span | Yes (shared with stages 1 and 5) | If a break were a phase, the timeline's span kinds would move to phase items and stage 1's "no verdict for kind `other`" would apply during it; all three specifications would change together |
| Q18 | The Health card, Settings and the scorecard screen each get one combined layout for all stages, with one order for the Settings cards and the Health rows: Scorecard, Coach packet, Intake, Body record, Events, Niggle log, Recovery context, Timeline. This stage's three are the last three | Yes; needed before any view code | A different order moves two rows and three cards in 6-8a and nothing else |
| Q19 | Installed on the phone together with stage 5, after a fresh backup, with all three switches off | Yes | A separate install changes only the schedule |
| Q20 | The fixture's rule day counts, locations and sides in §13 are invented. Please confirm none happens to match a rule or an entry of your own | Assumed invented and kept | Any that matches is replaced by another invented value and the tables of §13.2 are recomputed |

## 16. Needs the owner's go-ahead

Nothing in this stage needs one of the gated changes:

| Gated change | Needed? |
|---|---|
| Migration | No |
| Health read or write change | No |
| New target or entitlement | No |
| Network path | No |
| Backup whitelist additions (not on the gated list, but a stored-data contract with recorded Android drift) | Proceeds on Q1's default; the owner may overrule |

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
| D8 | Observations share the niggle store with a `kind` | Standing notes need a home and no second mechanism |
| D9 | Cut-stress uses weekly means of stored nights, not `HRVReadiness` | `HRVReadiness` is a tier and experimental; a mean adds no score |
| D10 | Cut-stress shows no current value and no adjective | Nothing for Today to disagree with; nothing that reads as a score |
| D11 | Weeks are Monday weeks of the night's day key | The same axis as the scorecard's curves |
| D12 | The typical range is read through `ChargeTypicalBand`, never recomputed | One definition for Recovery detail, the packet and this screen |
| D13 | Target dates are owner-entered checkpoints attached to a phase, with no weight | A stored phase has no date (C2), and the target weight has one home |
| D14 | The timeline reads the shared scorecard model's stored evaluation | One projection day across the app (R41) |
| D15 | A source that is not built says nothing; a source switched off says so once | The owner should not be told about features that do not exist |
| D16 | No notification and no widget | Sensitive content; the notification budget is unchanged |
| D17 | Day keys go through step 0's `CanonicalDay`; flags through step 0's `ObservableDefaultsFlag` | One rule and one observer for every stage, not a copy per stage |
| D18 | A checkpoint weight is a waypoint, refused at or beyond the phase target, and dropped from the row if the target later overtakes it | Two weights called "target" would be two numbers for one variable |
| D19 | A private event is absent from the timeline, not shown as a placeholder | A placeholder on a dated list would still disclose that something private happened on those days |
| D20 | The adapters are the only stage 6 code that names a stage 4 or stage 5 type | A change in either stage's read touches one file |

## 18. Not determined

- **The merged shape of the other stages.** §2.2 uses the names the cross-stage check fixed; each
  is confirmed against the merged code before the part that uses it is built.
- **Step 0's exact surfaces** for `CanonicalDay`, `ObservableDefaultsFlag`, `ChargeTypicalBand` and
  the demo registry. §5, §6.0, §8.2 and §9.4 give the surface stage 6 calls; the scaffolding commit
  stands where it differs.
- **The day stage 4 reports for an imported scan.** Stage 6 uses `BodyScan.day` as given and does
  not decide it.
- **The combined Health, Settings and scorecard frames** are not yet approved; row positions in
  §10.1 follow the one order stated there and wait for them.
- **How large `UserDefaults` strings behave at the limits in §9.2** on the device. The limits were
  chosen to keep each string in the tens of kilobytes; no measurement was made.
- **How many weeks `Repository.days` covers on a device.** `refresh(days:)` defaults to 4000
  (`Repository.swift:948`); no stored span was inspected.
- **Whether a paused exercise should match lift-session exercise names.** Free text is specified;
  no matching was designed.
- **A dated "target reached" item.** The scorecard reports the status without a date of its own;
  the timeline shows nothing for it.
- **A waypoint in a phase of kind `other`.** Only equality with that phase's target is refused,
  because such a phase has no direction. Whether that is enough is for the owner (Q16).
- **Parity ledger.** Whether the new public declarations can be registered without a Kotlin claim
  was not run through `Tools/parity_ledger.py`; stage 1 left the ledger's state open (0B-9).
- **The tables in §13** were worked by hand, as stated there.
- **Nothing was compiled.** Signatures in §6, §8.4 and §9 follow the conventions of
  `CutScorecard.swift` and of the other stages' specifications and were not built.

## Reconciliation (11 November 2026)

What the cross-stage check changed in this file, by conflict id.

| Id | Change in this file |
|---|---|
| X4 | §1 and Q6: niggles stay out of the packet; "packet v2" adds intake and events only, and a niggle section waits until the owner asks. |
| X5 | The design round is `design/round-s6-log-timeline/` with `importS6` and `s6-frames.json`; the guessed round number is gone, and the plugin files are the orchestrator's, not work package 6-2's. |
| X6 | `Stage6Demo` is one element of the demo registry; the chained fall-through is gone; demo names use only the prefixes `niggle-`, `cutstress-` and `timeline-` (§12.8). |
| X7 | `ChargeTypicalBand` is step 0's file. Stage 6 no longer creates it or edits `ScoreDetailData.swift`; §8.2, §12.4, §12.5 and work package 6-5 say so, and the single-definition scan notes its dependence on stage 2's assembler using it. |
| X8 | The assumed reads are replaced by the real ones in new §8.4: `TimelineScanSource` maps `BodyRecordStore.scans()` to de-duplicated `day` values; `TimelineEventSource` reads the synchronous property `PersonalEventStore.events`; the stored `evaluation` property stays on `CutScorecardModel`, set from `CutScorecardInputBuilder.evaluation(today:)` (§8.3). `TimelineSourcesTests` added. |
| X9 | `TimelineEventSource.timelineEvents` filters through `PersonalEvents.visible(_, includeSensitive: false)` before filtering by kind; a private diet break or deload has no row, placeholder, footnote or count (§8.4, §10.8, §11); tests for a private deload and faults F32 to F34 added. |
| X10 | Checkpoint weights are waypoints: category `weightWaypoint`, field `waypointWeightKg`, never worded "target", refused at or beyond the phase target with a link to the phase sheet, and dropped from the row if the target later overtakes it. The target date is the new category `targetDate`, with no weight, attached to a phase by `phaseStartDay`, at most one per phase. §6.3, §7.3 step 4, §8.1, §9.3, §10.8, §11, §12, §13.4 and Q16 changed. |
| X14 | §1 states the shared rule: a diet break or deload is an event, a phase is only a long block, the scorecard keeps reporting; §10.8 and Q17 repeat it. |
| X18 | The `evaluation` property is its own small commit (6-8b), after stage 2's move and stage 5's context field (§8.3, §14.1). |
| X19 | `CanonicalDay` and `ObservableDefaultsFlag` are step 0's. Stage 6 creates neither; §6.0 and §9.4 list the surface it calls; the three flags are one-line static instances; source-scan tests forbid a cloned observer or private day arithmetic. |
| X20 | §13 states there is one Fixture Person with stage 1 as the reference; paused exercises use stage 1's exercise names; the demo seed takes weights, scans and events from stages 1, 4 and 5 (§12.8). |
| X21 | §9.5: one writer at a time on `BackupSettings.swift` in the order 3, 5, 6; the four names join step 0's fork-only comment block; line-range citations removed; the clear-text note and the one-paragraph Android drift statement added; Q1 rewritten as decided by default. |
| X22 | §10.1 places the rows by the fixed order Scorecard, Body record, Events, Timeline, Niggle log, Coach packet, with the Settings section last; the three shared surfaces use the combined frames and are not designed in this round; Q18 added. |

Owner decisions applied as defaults: Q1 (backups), Q2, Q3 and Q5 (rules typed by the owner only,
most serious action wins, day 1 is the onset day), Q6, Q7 and Q15 (three switches, no Today card,
no notification, niggles out of the packet), Q9 and Q10 (weekly averages of at least four nights,
no good or bad wording, no score), Q16 (waypoints), Q17 (events, not phases), Q18 (combined
layout), Q19 (install milestone).

Privacy: the fixture's locations are now "Fixture location A" to "E", the observation carries no
side, the rule day counts and the professional-rule text were replaced by other invented values,
and the rehearsal paragraph no longer describes what the owner will enter. Q20 asks the owner to
confirm that no fixture value matches a real one.

Android (R43): no instruction to write or run Kotlin remains; the one shared stored-data contract
this stage moves, the backup whitelist, has its drift stated in one paragraph in §9.5.

Shared scaffolding this stage expects from the orchestrator's step 0:

- the demo registry line in `StrandiOSApp`'s debug block, to which stage 6 adds one element;
- the plugin commands `importS2` to `importS6` and the stage-named design folders, including
  `design/round-s6-log-timeline/`;
- `ObservableDefaultsFlag` (surface in §9.4);
- `CanonicalDay` with its test pinned to `CutScorecard.weekStart` (surface in §6.0);
- `ChargeTypicalBand`, extracted from `ScoreDetailData.swift` (§8.2);
- the comment block above the Swift backup whitelist that lists the fork-only keys (§9.5).

### Second pass

What the independent re-check and the orchestrator's rulings (a) to (k) changed in this file. Where
a row of the table above disagrees with a row here, this one stands.

| Item | Change in this file |
|---|---|
| X7, ruling (j) | §8.2 now says stage 2's packet assembler takes the range from `ChargeTypicalBand.range(_:)` and holds no sigma. Every remaining mention of the engine's spread function by name is gone: §2.1 row 9, §8.2 and the source scan `test_typical_band_has_one_definition` (§12.4) are worded through `ChargeTypicalBand` only. The scan keeps its name, which stage 2's specification cites. |
| X6, ruling (h) | §12.8 states this stage's demo file (`StrandiOS/NiggleLog/Stage6Demo.swift`), its one registry element and its three reserved prefixes (`niggle-`, `cutstress-`, `timeline-`), and no longer lists any other stage's provider or the registry's order. The demo's scan days and spans are the Fixture Person's of §13.4, passed to the two adapters through their closure initialisers, so `Stage6Demo` depends on no other stage's demo file. |
| X22, ruling (d) | The one order for Settings cards and Health rows is Scorecard, Coach packet, Intake, Body record, Events, Niggle log, Recovery context, Timeline; this stage's three are the last three. §10.1 is rewritten to it: on the Health card "Niggle log" now comes before "Timeline"; in Settings the single "Log and timeline" section becomes three cards, "Niggle log", "Recovery context", "Timeline". The strings "Log and timeline" and "Everything stays on this iPhone." are removed from §11. A10, Q18, work package 6-8a and §18 follow. This supersedes the X22 row above. |
| Ruling (c), and the re-check's "stage 3 became an editor" | §14.1 gives the one shared-file order (Lab Book ownership, stage 2, stage 3, stage 4, stage 5, stage 6, then packet v2) once and, for each hotspot, only this stage's position in it. The lists of other stages' edits are removed from §4.2, §8.3, §9.5, §10.1, §12.2, 6-8a, 6-8b and §14.1, which also removes the stale model order "2, 5, 6". §14.2 places every shared-file edit of this stage in its own serialised step. This supersedes the wording of the X18 and X21 rows above; the edits themselves are unchanged. |
| Ruling (e) | The mention of stage 5's "two switches" in Settings is gone; this file says nothing about the private-events packet switch. §8.4 is unchanged: a private event is absent from the timeline whatever that switch says. |
| Rulings (a), (g), (i) | Nothing in this stage specified the weigh-in and scan ranking, the `LabMarkerStore` steps or an `AICoach.swift` edit. §14.1 now lists those files as not edited by stage 6. |
| Rulings (b), (f), (k) | No change: this stage stores no protein floor (the fixture's 100 g is whole grams), writes no packet row, and the re-check found no privacy point in this file. |
| X10 | No change here. The names in this file (`weightWaypoint`, `waypointWeightKg`, `targetDate`, `phaseStartDay`) are the ones the stage 1 specification is to cite. |

One point left to the combined frame set: Recovery context holds the seventh place of the one
order and has a Settings card there, but this stage gives it no Health row (its entry point is the
scorecard link, §10.1). If the combined frame draws a "Recovery context" Health row, that is one
more row in 6-8a between "Niggle log" and "Timeline", one more string use, and one more flag-off
assertion in `Stage6FlagOffTests.swift`.
