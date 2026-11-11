# Health super-app: roadmap

Written 10 November 2026. Read [CONTEXT.md](CONTEXT.md) first. Gates G0–G8 are defined in
[QUALITY-GATES.md](QUALITY-GATES.md); roles and brief templates are in
[ORCHESTRATION.md](ORCHESTRATION.md).

Names of new types, functions, keys and files in this document are **proposals**. Each stage's
specification gate (G0) confirms or replaces them after reading the current code.

## Overview

| # | Stage | Target window | Size | Needs a migration | Blocked on |
|---|---|---|---|---|---|
| 0 | Foundation and tooling | Before 19 Nov 2026 | Field work plus small tooling | No | Owner field work |
| 1 | Weigh-in and scorecard | Late Nov | Small to medium | No | Q2, Q6 |
| 2 | Coach packet | Late Nov, after stage 1 | Small | No | Nothing |
| 3 | Protein and intake | December | Medium | No | Q1, Q4 |
| 4 | Body record | Before the owner's next scan (see the private profile) | Small; photos medium | Photos only | Q5 for photos |
| 5 | Events layer | January 2027 | Medium | Possibly | Stage 5 investigation |
| 6 | Niggle log, cut-stress view, timeline | February 2027 onward | Medium | Possibly | Stages 1 to 5 |
| — | Backlog | Unscheduled | Varies | Varies | Owner request |

Stages run **in order**. Stages 1 and 2 share data and merge hotspots, so they are sequential.
Within a stage, work packages run in parallel where the file-ownership table allows.

Each stage ends with: a pull request into `personal/iphone-baseline`, owner acceptance on the device,
an annotated checkpoint tag, and an update to [docs/personal/CONTEXT.md](../CONTEXT.md).

---

## Stage 0 — Foundation and tooling

### Goal

Make the base trustworthy before anything is added to it, and make "the gates passed" a single
command with recorded output.

### 0A. Owner field work

No code. The orchestrator tracks these and reminds the owner; it cannot do them.

| Item | Why now | Evidence to record |
|---|---|---|
| Export the WHOOP history archive | The membership ends 19 November 2026; this cannot be redone later | File stored outside the repository; checksum noted in `PersonalData/` |
| Three recorded nights, one full workout, one ordinary locked-phone day | Open since October; everything else sits on collection | Per [DEVICE-TESTING.md](../DEVICE-TESTING.md) |
| Backup and restore rehearsal in a separate disposable install | Later stages make the app the only copy of more data | Restore succeeded; row counts compared |
| Two counted walks and one seated period for steps | The owner's standing requirement | Error per walk; false steps while seated |
| Widget value and freshness check on the phone | Stage 3 adds a widget | Screenshots kept private |

A backup and restore rehearsal must pass before any build that changes stored data is installed on
the phone.

### 0B. Tooling work packages

| WP | Deliverable | Owner role | Notes |
|---|---|---|---|
| 0B-0 | **Bootstrap.** Check the working tree, fetch, branch `personal/superapp-0-foundation` from the up-to-date baseline, file the six planning documents as the first commit, place the private profile in its ignored path and confirm Git ignores it. | Orchestrator | Steps are in [KICKOFF-PROMPT.md](KICKOFF-PROMPT.md). Copy from the planning worktree when it exists; otherwise write the attachments out exactly. |
| 0B-1 | **Baseline record.** Build both Apple targets and run every local suite on the untouched branch. Record pass counts and every pre-existing failure. | Verifier | The redesign report already mentions known baseline tool-test failures. New work is judged against this record, so a later failure can be attributed. Store as `docs/personal/superapp/BASELINE.md`. |
| 0B-2 | **One local gate script**, proposed `Tools/personal/gate.sh`. Runs every check in [QUALITY-GATES.md](QUALITY-GATES.md) §G4 and prints one summary table. | Implementer | Derive each invocation from the workflow files in `.github/workflows/`, not from memory. A check that cannot run (for example Android with no JDK) prints `NOT RUN` with the reason and makes the script exit non-zero unless explicitly waived by flag. It must never skip silently. |
| 0B-3 | **Why CI is skipped.** Find out why workflow runs on the fork conclude `skipped` and report the options to the owner. | Explorer | Done 10 November 2026: see [CONTEXT.md](CONTEXT.md) §7 item 2. Do not change workflow files without the owner's decision. The repository is public, so the private-repository cost concern may not apply; that was not checked against GitHub's terms. |
| 0B-4 | **Android decision (Q3).** Present the two options: install JDK 17 and the Android SDK so twins are run, or record a written disposition per change. | Orchestrator | Installing software on the Mac needs the owner's go-ahead. Until answered, the default applies: twins are written and reported as "written, not run". This does not block other work. |
| 0B-5 | **Package test reachability.** The older handoff reports that a full SwiftPM run was blocked by an unavailable GRDB checkout. Reproduce, fix or document. | Verifier | Done 10 November 2026: not reproducible. There is no submodule; GRDB is a SwiftPM dependency and all eight package suites run. See [BASELINE.md](BASELINE.md). |
| 0B-6 | **Synthetic fixture set.** A documented, obviously fictional person with weekly weigh-ins, waist readings, protein days, scan entries and events, covering every edge case listed in stages 1 to 5. | Test author | Lives with the tests. Values must not resemble the owner's. |
| 0B-7 | **Real-data rehearsal procedure.** A written procedure for restoring a private backup into a simulator, with the copy kept under `PersonalData/`. | Verifier | Never committed. Screenshots from this path are never committed. |
| 0B-8 | **Figma pipeline check.** Confirm the design HTML renders, the frame export works, the local server script exists (it previously lived in a session scratchpad and may be gone), and the plugin has a command for the new round. | Designer | See [QUALITY-GATES.md](QUALITY-GATES.md) §G1. Needs computer-use access from the owner. |
| 0B-9 | **Parity governance state.** The older handoff notes the derived-ledger refresh was blocked by an unreproducible authority. Establish whether that affects new work. | Explorer | Report only. No waiver or migration without the owner. |

### Acceptance

- The planning documents are committed and the private profile is in place and ignored.
- `BASELINE.md` exists with pass counts and the list of pre-existing failures.
- The gate script runs end to end and its output for the untouched branch matches `BASELINE.md`.
- Q3 is answered, or its default is recorded as still in force, in [CONTEXT.md](CONTEXT.md) §6.
- The owner has confirmed the archive export, or has explicitly accepted the risk of not doing it.

Stage 0 tooling does not hold up stage 1. The stage 1 specification, design frames, tests and pure
logic start in the first session, alongside it.

### Checkpoint

Commit per work package. One pull request, "tooling: local gate and baseline". No device install.

---

## Stage 1 — Weigh-in and scorecard

### Goal

The owner records weight and waist once a week in under thirty seconds and sees a verdict derived
only from their own fixed rules.

### What exists

Lab Book already stores timestamped `weight` and `waist` readings and draws a sparkline per marker.
The profile holds a single weight and waist. The code reading for the specification found that
weight has six stores and waist three, that the Today views already resolve weight differently from
each other, and that the estimates read the profile only. The specification
([specs/stage-1.md](specs/stage-1.md) §3, §4 and §8) is the authority; where it differs from the
proposals below, the specification wins.

### Scope

In:

- A weekly weigh-in flow: weight, then waist, with backdating, edit and delete.
- A single resolver for "current weight" and "current waist" used by the profile-dependent
  estimates, Today and the new screen.
- Weekly series, rate of loss per week in kilograms and as a percentage of bodyweight, and a
  projected date for the active target.
- A scorecard with the owner's four weekly signals and a verdict from their three feedback rules.
- Phase configuration: phase name, start, target weight, expected rate band.
- An optional weekly local reminder, off by default.

Out:

- Daily weigh-in prompts, streaks, any automatic change to calorie targets.
- Smart-scale pairing. Apple Health weight import (the read boundary is unchanged in this stage).
- Charts with horizontal range bands or rules.

### Data design

- Weigh-ins are `labMarker` rows: `markerKey` `weight` or `waist`, category as the catalogue defines,
  `source` `manual`, `takenAt` the actual instant, `day` the local day.
- No migration. No new catalogue key is needed for this stage.
- Phase configuration and reminder preference are settings. Any setting that should survive a backup
  restore must be added to the `.noopbak` whitelist **on both platforms**
  (`BackupSettings.swift` and Android's `BackupSettingsCodec`), with canonical keys and JSON kinds.
  Only Int, Double and String cross that boundary.
- **Resolver rule.** One function returns the current weight with its source and date. Proposed
  precedence: newest Lab Book reading, then Apple Health series, then the profile value. The
  specification gate confirms this against every existing reader of `Profile.weightKg` and
  `waistCm`, and decides whether saving a weigh-in also updates the profile value or the profile
  becomes a fallback only. Whichever is chosen, a test asserts that all readers go through the
  resolver.

### Pure logic

Lives in `Packages/StrandAnalytics`, database-free, with a Kotlin twin.

Proposed: `CutScorecard.evaluate(input) -> result`.

Inputs: weigh-ins and waist readings as dated values; the active phase; rule parameters; an optional
lift signal; an optional protein adherence figure; "today" passed in, never read from the clock.

Outputs:

- Weekly points: one per ISO week, with the rule for choosing the reading when a week has several.
- Rate of loss over the configured window, in kg per week and percent per week.
- Projection: a date for the phase target, or an explicit "no projection" with a reason.
- Each of the four signals as `met`, `notMet` or `unknown`, with the numbers behind it.
- A verdict: `holdSteady`, `addCalories`, `reduceCarbs` or `insufficientData`, with the rule that
  fired stated in words.

The rule parameters and their values are in the private profile. Defaults in code are generic and
overridable; tests use synthetic parameters.

**The lift signal (Q6).** One feedback rule depends on working weights falling for two weeks. With
Hevy as the logger, the app knows this only if sessions are imported. The scorecard must show that
signal as `unknown` when it has no data for the period, and the verdict must then say which rule it
could not evaluate. It must not assume "holding".

### Screens

Decided at the design gate (Q2). Frames required:

1. Entry point on Today (a card in Your Cards).
2. The scorecard screen: four signals, verdict, weekly weight and waist curves, projection.
3. The weigh-in sheet, both steps, with backdating.
4. History list with edit and delete.
5. States for each: first use with no readings; one reading; fewer readings than the rules need;
   a missed week; target reached; weight rising; lift signal unknown.
6. Loading skeleton, and the largest accessibility text size.
7. Two placement options for Q2, so the owner chooses from pictures.

### Work packages

| WP | Deliverable | Role | Files owned |
|---|---|---|---|
| 1-1 | Specification: confirm names, resolver precedence, week rule, every existing reader of profile weight and waist | Explorer, then Spec writer | `docs/personal/superapp/specs/stage-1.md` |
| 1-2 | Design frames and owner approval | Designer | `design/round6-*`, plugin command |
| 1-3 | Test suite for `CutScorecard`, written from the specification before the implementation | Test author | `Packages/StrandAnalytics/Tests/...` |
| 1-4 | `CutScorecard` implementation | Implementer A | `Packages/StrandAnalytics/Sources/...` |
| 1-5 | Kotlin twin and oracle-derived expected values | Parity agent | `android/...` |
| 1-6 | Resolver, and migration of existing readers onto it | Implementer B | `Strand/Data/...` |
| 1-7 | Screens, sheet, history, Your Cards entry, setting behind a default-off flag | Implementer C, after 1-2 is approved and 1-4, 1-6 merge | `Strand/Screens/...`, `StrandiOS/...` |
| 1-8 | Strings in all ten locales | Localiser | `Strand/Resources/Localizable.xcstrings` (sole writer) |
| 1-9 | Reminder notification | Implementer C | A new reminder type beside the existing ones in `Strand/System/`; there is no shared notification settings file for local reminders |
| 1-10 | Adversarial review, then simulator verification | Reviewer, Verifier | None; read-only |

1-3 and 1-4 run in parallel in separate worktrees. 1-7 does not start before the design is approved.

### Test plan

Pure logic, each a named test case:

- Empty input returns `insufficientData`, no projection, no crash.
- One reading; two readings in the same week; two readings exactly a week apart.
- Fewer weeks than each rule's window: that rule is `unknown`, others still evaluate.
- Steady loss inside the expected band: `holdSteady`.
- Loss below the threshold for exactly the rule's window: `reduceCarbs`. One week short of the
  window: not yet.
- Loss below the threshold while waist shrinks and the lift signal is `met`: the result explains the
  recomposition case and matches the owner's rule for it (see the private profile).
- Lift signal `notMet` for the rule's window: `addCalories`. Lift signal `unknown`: verdict names the
  unevaluated rule.
- A missed week in the middle; two missed weeks; a gap longer than the window.
- A reading backdated into an earlier week changes that week only.
- Weight rising; weight exactly flat; a single outlier week.
- Target already reached; target equal to current weight; target above current weight.
- Projection with zero or positive slope returns "no projection" with a reason, never a date in the
  past or an infinite date.
- Week boundaries: a reading at 23:59 and at 00:01 local time on the boundary; a week spanning a
  daylight-saving change; a time-zone change between two readings.
- Non-finite and negative inputs are rejected.
- Unit handling: kilograms and pounds in, kilograms stored. (An app-layer test, not pure logic: the
  pure function takes kilograms only, and Lab Book has no kg/lb handling today.)
- Property check: adding a reading outside the evaluation window never changes the verdict.
- Determinism: the same input and the same "today" always give the same output.

Parity: compile the Swift function standalone, run it over the whole synthetic fixture set and a
generated spread, and paste that output as the expected literal in the Kotlin test. Add the matching
direction on the Swift side.

Store: write, read, edit and delete of weigh-ins; `day` derived correctly from `takenAt`; a deleted
reading disappears from the weekly series.

App target (`StrandTests`): the resolver's precedence; a test asserting no reader bypasses it; the
view model's states for every design frame.

Fault injection: for each rule, deliberately break its threshold and confirm at least one test fails.
Record this in the pull request.

Simulator: every design frame reproduced with fixture data, compared side by side with the approved
frame, at default and largest text sizes, with Reduce Motion on and off.

Real-data rehearsal: the owner's actual history through the procedure from 0B-7. Results stay
private.

### Acceptance

- Entering the synthetic fixture produces exactly the expected verdict sequence.
- The profile-dependent estimates, Today and the scorecard never show different weights.
- With the flag off, the app behaves exactly as before: the baseline suite is unchanged.
- The owner enters their own past readings on the phone and confirms the verdict matches what their
  coach concluded for those weeks.

### Checkpoint

Pull request "feat: weekly weigh-in and cut scorecard". Tag after owner acceptance.

---

## Stage 2 — Coach packet

### Goal

One action produces everything the coach needs from the app, in a stable labelled format, so the
owner pastes two things into Claude (the Hevy session and the packet) and nothing is retyped.

### What exists

`AICoach.buildContext()` already writes a 14-day biometric summary with 30-day averages for the
in-app Coach, and marks unmeasured values with a dash.

### Scope

In:

- A packet builder with sections the owner can switch on or off, and a preview before anything is
  copied.
- Copy to a local-only, expiring pasteboard item; the system share sheet; and a Shortcuts action.
- A version header so the coach side can detect format changes.
- The Claude-side update: the coaching skill and the training document learn the format.

Out:

- Any network call. The packet leaves the phone only by the owner's own paste or share.
- Sending the packet to the in-app Coach provider automatically.
- Writing the packet to a cloud folder (backlog).

### Format

Plain text, English regardless of interface language, ISO dates, metric units, fixed section order.
Proposed sections:

1. Header: format name and version, generated-at time with zone, date range.
2. Scorecard: the stage 1 result, including which rules were `unknown`.
3. Weigh-ins: the last several weekly points for weight and waist.
4. Recovery and sleep: per-day lines for the range, with unmeasured values marked.
5. Trends: resting heart rate and HRV against the personal baseline.
6. Activity: steps per day with the source named; workouts as summaries.
7. Intake: protein and calories per day once stage 3 exists; absent until then, not zero.
8. Events: once stage 5 exists.
9. Footer: what is measured, what is estimated, and what the app cannot know.

Every value carries its provenance where sources differ. Nothing identifies the device or the
person. Sensitive sections (events of a medical kind) default to off.

### Design rule

The packet and the in-app Coach context must not be two independent formatters of the same facts.
Extract the shared per-day line and averages into one component used by both, then assert it.

### Work packages

| WP | Deliverable | Role |
|---|---|---|
| 2-1 | Specification, including the exact format with a full synthetic example | Spec writer |
| 2-2 | Design frames: preview sheet, section toggles, copied confirmation, empty state | Designer |
| 2-3 | Golden-file tests written from the specification | Test author |
| 2-4 | Shared formatter extraction and packet builder | Implementer A |
| 2-5 | Preview sheet, pasteboard, share sheet, Shortcuts action | Implementer B |
| 2-6 | Strings | Localiser |
| 2-7 | Claude-side: update the coaching skill and add a "reading the packet" section to the training document | Orchestrator, with the owner's approval of the wording |
| 2-8 | Adversarial review and simulator verification | Reviewer, Verifier |

### Test plan

- Golden files for: a full fixture; every section toggled off individually; no data at all; a range
  with unmeasured days; a range crossing a month and a year boundary.
- The in-app Coach context for the same fixture is byte-identical before and after the extraction.
- No section prints a zero for a missing value.
- The packet contains no device identifier, strap serial, account name or file path. Assert by
  scanning the output for the fixture's known identifiers.
- Size: the full packet for a 14-day range stays under the agreed budget.
- Stability: the same input and clock give the same bytes.
- The pasteboard item is local-only and has an expiry. Verified on a simulator, and on the device
  with a second signed-in Apple device nearby if the owner has one.
- The Shortcuts action returns the same text as the button.
- End to end: the owner pastes a real packet into Claude with the updated skill and confirms the
  coach reads each section correctly.

### Acceptance

- The owner completes one real coaching exchange using the packet without retyping any number.
- The in-app Coach behaves exactly as before.

### Checkpoint

Pull request "feat: coach packet export". Tag after owner acceptance.

---

## Stage 3 — Protein and intake

### Goal

The protein floor is visible all day, on the phone and on a widget, without the owner logging food
twice.

### Step one: discovery spike (Q1, Q4)

Before any design or code:

1. The owner supplies the food app's App Store link.
2. Check on the phone: Health app, Sharing, Apps. Does the food app appear, and which data types does
   it write? Record exactly: dietary protein, dietary energy, carbohydrate, fat, per-meal timestamps.
3. Check whether the vendor documents an MCP server or an export.
4. Report three facts to the owner and get a decision on the path.

| Path | Condition | App work |
|---|---|---|
| A. Read from Apple Health | The food app writes protein and energy to Health, and the owner approves widening Health reads | Medium |
| B. Quick-add in the app | No Health writes; the owner accepts a second entry per meal | Medium, and adds friction |
| C. Coach-side only | An MCP server exists and the owner only needs Claude to see intake | None in the app; stage 3 reduces to the supplement tick and the cutoff reminder |

### Path A design

- Add dietary protein and dietary energy to the read set used while activity-only mode is on. Follow
  the existing pattern from the Steps change: the authorisation fingerprint re-prompts once, and an
  empty or failed read preserves stored totals.
- HealthKit does not reveal whether a read was denied. An empty result is "no data", shown as such.
- Daily totals are stored in `metricSeries` under proposed keys for protein grams and energy in
  kilocalories, in the Apple Health source namespace already used by imported series.
- Day boundary: the local calendar day, using the same rule as stage 1.
- Each total carries the time it was last read. The interface shows that time, because freshness
  depends on the food app writing and on iOS delivering.
- Health writes stay blocked. Physiological imports stay excluded.

### Surfaces

- A protein card for Today (Your Cards): grams so far, the floor, grams remaining. The ring completes
  at the floor and keeps counting past it, because the number is a floor, not a target.
- Calories shown against the owner's range, with a plain note below the hard floor. Wording is
  factual. No warnings about health.
- A daily supplement tick, reusing the Journal.
- An evening cutoff reminder at a time the owner sets, off by default, coordinated with the existing
  wind-down so the phone does not ring twice.
- A widget: grams remaining. A new widget kind; the App Group payload gains optional fields only.
- The coach packet gains its intake section.

### Work packages

| WP | Deliverable | Role |
|---|---|---|
| 3-0 | Discovery spike and owner decision | Explorer, Orchestrator |
| 3-1 | Specification for the chosen path | Spec writer |
| 3-2 | Design frames: card, detail, widget in each size, stale and no-data states | Designer |
| 3-3 | Tests for daily aggregation and the floor logic | Test author |
| 3-4 | Aggregation and floor logic (pure, with Kotlin twin if it is stored or analytic) | Implementer A, Parity agent |
| 3-5 | Health read change (path A only) | Implementer B |
| 3-6 | Card, detail, supplement tick, reminder | Implementer C |
| 3-7 | Widget and payload | Implementer D |
| 3-8 | Strings; review; verification | Localiser, Reviewer, Verifier |

### Test plan

- Aggregation: several entries in a day; entries from two sources; an entry edited in the food app;
  an entry deleted; an entry just before and just after midnight; a time-zone change mid-day.
- A failed read leaves yesterday's stored total untouched. A read returning nothing does not write
  zero.
- A step-only or protein-only update does not disturb unrelated Health columns or series.
- Floor logic: below, at and above the floor; no data; a floor of zero or unset hides the card.
- Widget: payload with the new fields absent still decodes; the widget labels its time; every size
  renders with no data.
- Existing widget kinds and identifiers are unchanged.
- Authorisation: fresh install path, existing-consent path, and the re-prompt after the read set
  changes. Simulator first, then the device.
- Device: log a known meal in the food app, open NOOP, confirm the total and its timestamp; lock the
  phone for an hour and record how stale the widget becomes.

### Acceptance

- For three consecutive days the app's daily protein total equals the food app's.
- The widget never shows a value without the time it was read.
- With the flag off, the baseline suite is unchanged and Health reads are as before.

### Checkpoint

Pull requests: "feat: read dietary protein and energy from Apple Health" (path A, its own concern),
then "feat: protein floor card and widget". Tag after owner acceptance.

---

## Stage 4 — Body record

### Goal

Scans, blood panels and benchmarks become structured, comparable entries before the owner's next
scan, so the comparison is ready on the day.

### 4A. Scan and benchmark markers

- New catalogue entries for body-composition scans: total, fat and lean mass; segmental lean mass for
  arms, legs and trunk; visceral fat; bone density scores. Exact keys and units at the specification
  gate, checked against a real report layout the owner provides privately.
- New catalogue entries for the owner's fixed performance benchmarks.
- The catalogue is a parity contract: the Swift file and `MarkerCatalog.kt` change together, and the
  CSV import alias tables on both platforms stay aligned.
- Derived figures (for example the arm-to-leg lean ratio) are computed from stored entries, not
  stored. One function, tested.
- A scan-to-scan comparison view: each marker's change between two chosen dates.
- No migration: `labMarker.category` and `markerKey` are text.

### 4B. Blood panel readiness

- Verify, with a test, which units the editor accepts for each blood marker the owner's laboratory
  reports. HbA1c in percent is the known doubt. Add a visible conversion where it is missing.
- No new screen. The deliverable is that the owner can type a report as printed.

### 4C. Photo timeline (only if the owner says yes to Q5)

- Stored as files in the app container, never in the database, never in a widget, never in the coach
  packet, never sent to a provider.
- Excluded from the `.noopbak` format, which is a cross-platform contract. A separate export.
- Behind device authentication.
- This sub-stage gets its own specification, design gate and pull request.

### Test plan

- Catalogue parity: the full key list, units and decimals compared between Swift and Kotlin by a
  generated oracle, not by reading.
- CSV import: each new key and each alias round-trips on both platforms.
- Unit conversion: every dual-unit marker converts both ways within rounding; entry in the report's
  unit stores the canonical unit and displays both.
- Comparison view: two scans; one scan only; a marker present in one scan and not the other; scans
  entered out of order.
- Derived ratios: missing component gives "not available", never zero or infinity.
- Photos, if built: capture, storage outside backup, deletion actually removes the file, lock state.

### Acceptance

- The owner enters a real scan report and a real blood panel on the phone, as printed, in one sitting.
- After the next scan, the comparison view matches a hand calculation for every marker.

### Checkpoint

Pull requests: "feat: body-composition and benchmark markers", "fix: laboratory unit entry" if
needed, "feat: photo timeline" if approved.

---

## Stage 5 — Events layer

### Goal

A gap in training or a jump on the scale carries its own explanation on every chart and in the coach
packet.

### Investigation first

- Survey current writers and readers of the `event` table and the "Mark a Moment" action. Decide
  whether ranged personal events can reuse that storage without disturbing its current meaning.
- If not, design a migration: GRDB and Room together, tested, named with the upstream sequence in
  mind. Present both options to the owner with their costs.

### Scope

- Event kinds: travel, illness, diet break, deload, supplement change, and a generic sensitive kind
  the owner names. The full list the owner needs is in the private profile.
- Each has a start, an optional end, an optional note and a sensitivity flag.
- Charts show events as quiet marks on the time axis. No horizontal bands or rules.
- The scorecard notes when an event overlaps a week it is judging. It does not change the verdict;
  it annotates it.
- The coach packet lists events; sensitive kinds are excluded unless the owner switches them on.
- Sensitive kinds never appear in widgets or notifications.

### Test plan

- Overlap logic: event before, inside, spanning and after a week; open-ended events; zero-length
  events; events across a time-zone change.
- Sensitive events are absent from widget payloads, notification text and a default packet. Assert
  by scanning outputs.
- Backup round trip includes events.
- If a migration is added: the migration test, the schema-agreement test, and a rehearsal on a copy
  of the owner's real database before any device install.

### Checkpoint

Pull request "feat: personal events on charts". If a migration is involved it is its own pull
request, merged and rehearsed first.

---

## Stage 6 — Niggle log, cut-stress view, timeline

Specified in detail only after stage 5, because each depends on what the earlier stages taught.

- **Niggle log.** Record a complaint with location, character and date. The app applies the owner's
  written triage rules to label it and shows the day count. It states the owner's own rule for when
  to see a professional; it gives no diagnosis. Exercises the coach has paused are listed with the
  reason.
- **Cut-stress view.** Resting heart rate and HRV trends beside the scorecard, described as context
  for the coach. Not a new score and not an input to any existing score until it is shown to track
  a varying input, per the repository's rule on derived signals.
- **Checkpoint timeline.** Phases, scan dates, diet breaks, deloads and target dates on one view.

---

## Backlog

Not scheduled. Each needs an explicit owner request.

| Item | Note |
|---|---|
| Share-sheet target for Hevy | Two-tap import of a session. Needs a new extension target, identifier and profile. |
| Coach packet written to the backup folder | If that folder syncs to a cloud drive, Claude could read it without a paste. Background writes are unreliable on iOS; test before promising. |
| In-app Coach on Claude | A provider exists but needs a paid API key and would lack the training document. |
| Encrypted backups | Increasingly important as the record grows. Touches the cross-platform backup contract. |
| Phone-free step research | Needs a private corpus of labelled walks. No speculative strap commands. |
| Per-side and machine fields for lift sets | Only relevant if the app becomes the logger. It is not. |
| Apple Health weight import | Only if the owner starts using a connected scale. |

## Standing rules for every stage

1. No code before the design is approved.
2. Tests are written from the specification by someone who has not seen the implementation.
3. A subagent's report is a claim. The orchestrator checks the diff and reruns the gate script.
4. Synthetic data in everything committed. Real data only under `PersonalData/`.
5. New surfaces are off by default until the owner accepts them on the device.
6. Nothing is installed on the phone without the owner's go-ahead in that conversation, and never
   before a fresh backup.
7. When a fact cannot be verified, the document says so.
