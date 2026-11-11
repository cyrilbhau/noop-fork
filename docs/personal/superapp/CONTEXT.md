# Health super-app: context

Written 10 November 2026, Asia/Kolkata. Read [the folder index](README.md) first.

## 1. The idea in one paragraph

The personal iPhone fork replaces a WHOOP subscription. The owner's actual health project is larger:
a multi-year body recomposition with phases (cut, slower cut, maintenance reset, build). Almost all
of that project lives outside the app today: lifting in Hevy, food in a separate tracker, a tape
measure, body-composition scans as PDFs, and a coaching document maintained with Claude. The
super-app workstream turns the app into the home for that project's **data and bookkeeping**, with
the strap as one sensor among several. Coaching judgement stays with the coach.

## 2. Decisions the owner has made

These are settled. Do not reopen them without a new instruction from the owner.

| Topic | Decision | Consequence |
|---|---|---|
| Lifting logger | **Hevy stays.** It is a habit and the owner likes its social side. | No in-app replacement for Hevy. No in-app progression or stall-rule engine. The app keeps training history complete through the existing Hevy CSV and pasted-text imports. |
| Coach | **Claude is the coach's home for now.** The owner does not mind where it moves later. | The in-app Coach is not taught the standing plan. The app's job is to hand Claude clean data: the "coach packet" (stage 2). Keep the design portable so the plan can move later. |
| Food tracking | The owner logs food in an app they call **Instinct** and believes it has an MCP server. | **Unverified.** Three web searches on 10 November 2026 found no food-logging app of that name with an MCP server; the nearest match was "Lift Instinct". Stage 3 starts with a discovery spike. See §6. |
| Process | Figma designs are created and approved **before any code** for a stage. The owner will grant computer-use access for Figma. | Gate G1 in [QUALITY-GATES.md](QUALITY-GATES.md). |
| Process | Every feature is checkpointed and committed, with separate pull requests where practical. | Branch, PR and tag rules in [QUALITY-GATES.md](QUALITY-GATES.md). |
| Process | Heavy emphasis on testing and on things verifiably working. | Each stage carries an enumerated test plan in [ROADMAP.md](ROADMAP.md). |
| Process | The plan is deliberately verbose and implementation is delegated to subagents. | [ORCHESTRATION.md](ORCHESTRATION.md). |

## 3. What the finished app looks like

The full vision, kept short. Stages in the roadmap implement the parts marked with a stage number.

1. **A cut scorecard (stage 1).** A weekly weigh-in flow (weight, then waist), weekly trends that
   expect noise, rate of loss as a percentage of bodyweight, a projected date for the next target,
   and a verdict from the owner's fixed feedback rules. Phase-aware.
2. **Clean hand-off to the coach (stage 2).** One tap produces a compact, labelled block of recent
   sleep, recovery, HRV, resting heart rate, steps, weigh-ins and the scorecard verdict.
3. **Protein as a first-class number (stage 3).** A protein floor shown beside the daily rings, a
   "grams remaining" widget, a calorie floor, an evening food cutoff tied to wind-down, and a daily
   supplement tick. Never "calories earned" from exercise.
4. **A body record (stage 4).** Body-composition scans as structured entries compared scan to scan,
   blood panels, fixed performance benchmarks, and optionally a private photo timeline.
5. **An events layer (stage 5).** Travel, illness, diet breaks, deloads and other dated changes as markers
   on charts, so gaps and scale spikes explain themselves.
6. **A niggle log, a cut-stress view and a checkpoint timeline (stage 6).**
7. **Trustworthy phone-free steps.** A standing requirement. It is a research track, not a stage.

Deliberately absent: social features, streaks and guilt, daily-weight nagging, automatic calorie
changes, cardio suggestions, heart-rate "strain" as the measure of a lifting session, and any
estimate presented as a measurement.

## 4. What the code already provides

Every row was checked in the source on 10 November 2026 at commit `85fc5329`. Paths are relative to
the repository root. Re-verify before relying on a row; the code moves.

### Storage that needs no migration

| Need | Existing mechanism | Where |
|---|---|---|
| Timestamped weight, waist, body fat, height | `labMarker` table; catalogue keys `weight`, `waist`, `body_fat`, `height` | `Packages/WhoopStore/Sources/WhoopStore/Database.swift` (migration `v17-lab-book`), `LabMarkerStore.swift`, `Packages/StrandImport/Sources/StrandImport/MarkerCatalog.swift` |
| Blood markers | Same table; keys include `ldl`, `hba1c`, `bp_systolic` | Same |
| A generic per-day numeric series | `metricSeries` table, primary key `(deviceId, day, key)` | `Database.swift`, `MetricSeriesStore.swift` (`upsertMetricSeries`, `metricSeries`, `metricKeys`, `deleteMetricSeriesPoint`) |
| Custom daily yes/no or numeric questions | Journal, with numeric answers since `v20-journal-numeric` | `Strand/Data/JournalCatalog.swift` |
| A generic timestamped event with a JSON payload | `event` table: `deviceId`, `ts`, `kind`, `payloadJSON` | `Database.swift`. Current writers were not surveyed; stage 5 investigates before reusing it. |

`labMarker` columns: `id`, `deviceId`, `markerKey`, `category`, `day`, `takenAt`, `value`,
`valueText`, `unit`, `source`, `note`, `referenceText`.

The newest migration is `v47-rr-whoop5-fill`.

### Screens and features that exist

| Area | State | Where |
|---|---|---|
| Lab Book | Marker cards with sparklines; an editor with a unit switcher for dual-unit markers (lipids and glucose, mmol/L and mg/dL). It has no kg/lb or cm/in handling, and the store cannot change a reading's instant (add and delete only). | `Strand/Screens/LabBookView.swift`, `MarkerEditorView.swift` |
| Lab marker catalogue on Android | A Kotlin twin exists | `android/app/src/main/java/com/noop/analytics/MarkerCatalog.kt`, `.../ingest/LabMarkerCsvImport.kt` |
| Body weight elsewhere | `Profile.weightKg`, `waistCm` and `heightCm` are single profile values that feed VO₂max and calorie estimates. Weight has six stores, not three (profile, `appleDaily.weightKg`, `metricSeries` `weight` under `apple-health` and under `nutrition-csv`, `labMarker` rows and their `lab-book` projection). Liquid and classic Today resolve it over different days and windows, and the estimates read the profile only. See the stage 1 specification §3 and §4. | `Strand/Data/Profile.swift`, `Strand/Liquid/LiquidTodayView.swift` (search `#204`) |
| Metric catalogue | `weight` and `body_fat` are defined as Apple Health sourced series | `Strand/Data/MetricCatalog.swift` |
| Lift programmes | Items carry target sets, rep range, weight, RPE, rest seconds and a cue | tables `liftProgram`, `liftProgramItem` |
| Lift sessions | Live session with rest timers; sets carry weight, reps, RPE, warm-up flag, rest taken and a note. No per-side or machine field. | `Strand/Data/LiftSessionEngine.swift`, tables `liftSession`, `liftSet` |
| Lifting imports | Pasted workout text with preview, and Hevy CSV with set-level detail; CSV skips duplicate start times | `Strand/Screens/WorkoutTextImportSheet.swift`, `Strand/Data/PersonalLiftingImport.swift`, `Packages/StrandImport/.../LiftingImporter.swift` |
| Coach context | A 14-day summary plus 30-day averages (`buildContext`), then recent workouts, journal associations and a Lab Book roll-up (`buildFullContext`). No lift sets, no notes, no standing plan beyond an editable system prompt. | `Strand/AI/AICoach.swift` |
| Coach providers | Anthropic, ChatGPT, Custom, Gemini, OpenAI | `Strand/AI/Providers/` |
| Siri and Shortcuts | Mark a Moment, Buzz Strap, Sync Strap, Ask Coach | `StrandiOS/System/NOOPAppIntents.swift` |
| Widgets | Kinds `NOOPWidget`, `PersonalStepsWidget`, `PersonalSleepWidget`, `HeartRateWidget`, `StressWidget`, `CoachBriefWidget` | `StrandiOSWidgets/` |
| Backup | Daily on-launch catch-up to a user-chosen folder, seven snapshots kept. The file is an **unencrypted** ZIP. | `Strand/Data/BackupSync.swift`, `DataBackup.swift` |
| Debug screenshot harness | `--demo-screen <name>`, `--demo-hour <Int>`, `--demo-sync` launch arguments in debug builds | `StrandiOS/App/StrandiOSApp.swift` |
| Design sources | HTML/CSS design system, earlier rounds and a local Figma plugin | `design/system/noop.css`, `design/system/noop.js`, `design/round1`–`round4`, `design/figma-plugin/` |

### What is missing

- Apple Health reads are limited to workouts and step count while `importsActivityOnly` is true
  (`StrandiOS/Health/HealthKitBridge.swift`, `readTypes`). Dietary protein and dietary energy are
  not read anywhere in the bridge, in either mode.
- There is no weekly weigh-in flow, no rate-of-loss calculation, no projection and no scorecard.
- There is no export of coach context outside the in-app Coach, apart from copying a single reply.
- The marker catalogue has no body-composition scan keys (segmental lean mass, visceral fat, bone
  density) and no performance benchmarks.
- Whether the HbA1c editor converts between percent and mmol/mol was **not verified**. The canonical
  unit is mmol/mol; many laboratory reports give percent.
- `project.yml` has no share-extension target.

## 5. Constraints that shape every stage

### From the repository rules ([AGENTS.md](../../../AGENTS.md))

- **Swift and Kotlin parity.** Android reimplements the same logic. A change to analytics, a stored
  value, a migration or the marker catalogue needs its Kotlin twin in the same change, verified by an
  oracle, or an explicit written reason why not. The personal product is iPhone only, but the
  contract still applies to shared logic and stored data.
- **Migrations.** Versioned, tested, never edited after the fact, and the GRDB and Room schemas must
  agree. This is why the roadmap prefers designs that need no migration.
- **Two readouts of one fact must not be able to disagree.** Resolve a fact through one function and
  one clock. Stage 1 hits this immediately: weight exists in the profile, in Apple Health series and
  in Lab Book.
- **A diagnostic may only assert what it can attribute.** Missing data is "not measured", never zero.
  Estimates are labelled as estimates.
- **Design system is law.** `StrandPalette`, `StrandFont` and shared components only.
- **One concern per pull request.** English text. Reference issues with `Refs #N` only.
- **Generated project files stay out of Git.** `project.yml` is the source; run `xcodegen generate`.
- **No medical claims.** The app is not a medical device.

### From the personal fork ([docs/personal/CONTEXT.md](../CONTEXT.md))

- The installed app holds the **only copy** of the owner's collected history. It is updated in
  place. It is never uninstalled, and a backup is never restored over it as a test.
- Signing identity, bundle identifiers and App Groups do not change for feature work.
- Apple Health writes are blocked. Health reads beyond steps and workouts were deliberately excluded;
  widening them is an owner decision each time.
- ChatGPT tokens stay in the device Keychain. Health-context consent is separate from sign-in.
- Shared Apple sources must compile for both `NOOPiOS` and the macOS `Strand` target.

### From the owner's design taste

Approved in the October 2026 redesign rounds:

- Minimal but information-dense, in the manner of Apple Health on iOS 26. Black canvas, translucent
  cards.
- Colour is semantic: Sleep violet; Recovery green, yellow or red by band; Strain blue.
- Liked: ambient background glows driven by the scores, smooth line charts with gradient area fills,
  shimmer skeleton loaders, springy staggered entrances, rings that refill on load, count-up numbers.
- Rejected: textured, three-dimensional or "liquid vessel" looks; bevels; glows as decoration; hard
  straight horizontal lines across charts such as range bands and rules. Show the curve and the fill.

## 6. Open questions

The session does not stop on these. It proceeds on the default, says so, and the owner overrules
where they disagree.

| # | Question | Who answers | Default until answered |
|---|---|---|---|
| Q1 | Exactly which app is "Instinct"? Does it write dietary protein and energy to Apple Health? Does it have an MCP server or an export? | Owner supplies the App Store link; the discovery spike checks the rest | Stage 3 stays blocked. Stages 0, 1, 2 and 4 proceed. |
| Q2 | Does the scorecard screen live in a new tab, under Health, or as a Today card with a detail screen? | Owner, at the stage 1 design gate | Design both placements as frames; the owner chooses from the pictures. |
| Q3 | Is Android parity enforced by running tests locally (install JDK 17 and the Android SDK), or recorded as a written disposition per change? | Owner | Install nothing. Write the Kotlin twins and report each as "written, not run". Remind the owner it is outstanding. |
| Q4 | May Health reads widen to dietary protein and energy? | Owner, at stage 3 | No. |
| Q5 | Are progress photos in scope, and if so are they included in backups? | Owner, at stage 4 | Out of scope. |
| Q6 | Should the app's lift signal for the scorecard come from monthly CSV imports, per-session pastes, or stay "unknown to the app"? | Owner, at the stage 1 design gate | Unknown to the app unless imported sessions cover the period; the screen says so. |

## 7. Risks and items that were easy to miss

These surfaced while planning. Each is assigned to a stage in the roadmap.

1. **Health data in Git.** The GitHub repository is **public** (checked with `gh repo view` on
   10 November 2026; earlier documents call it private). Every push is a publication. Measurements, scan results, medication
   notes and injury history must never be committed, including in test fixtures, screenshots, commit
   messages and pull-request descriptions.
2. **CI does not run on this fork.** Investigated on 10 November 2026. The `skipped` runs are
   scheduled runs of two workflows that carry a guard added in commit `398af615` to keep scheduled
   jobs off personal forks. Every other workflow triggers only on `main`, which this repository
   does not have, so none has ever run. Two workflows (`source-hygiene`, `i18n-coverage`) have no
   manual dispatch. Until the owner chooses otherwise, the local gate script
   (`Tools/personal/gate.sh`, recorded in [BASELINE.md](BASELINE.md)) is the evidence. Dispatching
   `android.yml` by hand on a pushed branch is a way to run Kotlin twins without installing
   anything on the Mac; it was not tried.
3. **No Java runtime on the Mac.** Android unit tests cannot run locally. Kotlin twins written without
   being run are unverified. See Q3.
   The parity ledger is also stale on this branch: its stored authority has not reproduced since
   11 October 2026, the ratchet always prints one pre-existing error, and the ledger cannot see
   committed one-sided code here. New analytics functions need a twin claim on both sides and a
   production caller in the same change. No refresh or migration without the owner.
4. **Upstream migration collisions.** The fork tracks `ryanbr/noop`. If the fork adds a migration
   named like upstream's next one, a later merge collides. Prefer no migration; where one is
   unavoidable, design its name and position with the upstream sequence in mind and write that
   reasoning into the pull request.
5. **Merge hotspots.** `Strand/Resources/Localizable.xcstrings`, `project.yml`, the marker catalogue
   and the changelog are touched by nearly every stage. Two branches editing them in parallel will
   conflict. See the file-ownership rules in [ORCHESTRATION.md](ORCHESTRATION.md).
6. **Localisation gate.** New interface strings must cover the ten existing locales, checked by
   `Tools/i18n_audit.py`.
7. **The backup is unencrypted.** As the app accumulates scans, blood results and possibly photos,
   the backup file becomes more sensitive. Encryption is in the backlog; photos stay out of the
   backup format unless the owner decides otherwise.
8. **The other half of the hand-off is outside the repository.** The Claude coaching skill and the
   training document need to learn the coach-packet format. Stage 2 includes that work.
9. **The clipboard.** A coach packet copied to the general pasteboard can reach other devices through
   Universal Clipboard. Use a local-only, expiring pasteboard item.
10. **Dates near the start.** The WHOOP membership ends 19 November 2026 and the history archive
    must be exported before then. The recorded readiness target is 12 November 2026. The collection
    checks in the older handoff are still open.
11. **Real-data rehearsal.** A screen that works on demo data can fail on the owner's real history.
    Rehearse on a private copy restored into a simulator before a device install, and keep that copy
    under `PersonalData/`.
12. **Feature flags and rollback.** Each new surface ships behind a default-off setting until the
    owner accepts it on the device, so a faulty build cannot break daily use.
13. **Laboratory units.** Reports in the owner's country commonly use mg/dL and HbA1c percent. Entry
    must accept the units on the report and convert visibly.
14. **Time zones and travel.** Weekly weigh-ins, daily protein totals and the evening cutoff all
    depend on a day boundary. Decide the rule once and test it across a time-zone change.
15. **Notification budget.** The owner does not want nagging. Every new reminder is opt-in, and the
    total count is reviewed at each design gate.
16. **Signing.** A new extension target needs its own identifier and profile. Avoid new targets until
    a stage truly needs one.
17. **Figma access.** The Figma account is on the Starter plan and its MCP call limit was exhausted in
    October 2026. Design frames go through the local plugin by computer use. The plugin's import
    commands are per round, so a new round needs a new command.
18. **The local baseline branch is behind.** On 10 November 2026 the main checkout's
    `personal/iphone-baseline` was at `158a5de3`, four commits behind `origin/personal/iphone-baseline`
    at `85fc5329`. These documents were verified at `85fc5329`. Fetch and branch from the remote tip.
19. **Signing configuration lives only in the main checkout.** `Config/BundleIdSecrets.xcconfig` is an
    ignored local file; a worktree has only the example file. Unsigned simulator builds work anywhere.
    A signed device build has to run where the real file is. The same applies to the ignored
    `build/personal/` evidence folders.
20. **The session may not be in the main checkout.** The desktop app can start a session in a fresh
    worktree under `.claude/worktrees/`. Ignored files (the private profile, signing configuration)
    do not exist there until placed. Use absolute paths and check before assuming.
