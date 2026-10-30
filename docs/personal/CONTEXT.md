# NOOP Cyril project context and design handoff

Updated 30 October 2026, Asia/Kolkata. This is the current handoff for Claude and other contributors
working on the personal iPhone fork. The owner confirmed existing history and saved Coach sign-in
after the earlier audited redesign was installed in place. The owner approved promoting the
redesign to the personal baseline and creating the installed-redesign checkpoint.

## Start here

- Checkout: `/Users/cyrilbhau/Documents/Noop/noop-fork`.
- Private repository: [cyrilbhau/noop-fork](https://github.com/cyrilbhau/noop-fork).
- Working branch: `personal/iphone-baseline`.
- Latest installed update: **Your Cards and spacing redesign**, including A1/A2, retaining independent
  strap estimates, the counted-walk check, Steps import, device/sync repairs and refreshed widget
  artwork. The signed update installed in place and launched normally; latest history/sign-in and
  runtime acceptance remain deferred at the owner's request. The exact frozen source and installation
  evidence are in ignored `build/personal/your-cards-device/`. Prior sources remain recorded in
  `build/personal/sync-device/source.json` and `build/personal/strap-steps-device/source.json`.
- Earlier installed redesign source: [`c176345781a50a904287044f93743879ba67e22e`](https://github.com/cyrilbhau/noop-fork/commit/c176345781a50a904287044f93743879ba67e22e).
- Earlier redesign checkpoint: `checkpoint/2026-10-29-redesign-installed`. It records that earlier
  application source and installation acceptance; it does not identify the latest installed update.
- Earlier recovery point: `checkpoint/2026-10-29-before-design`, retained unchanged.
- Redesign evidence and remaining checks: [implementation report](REDESIGN-REPORT.md).
- Installed app: **NOOP Cyril**, built and signed locally with its existing personal identity.
- Scope: personal **iPhone app and iPhone widgets**. No Android feature work, Apple Watch integration,
  public release, or hosted backend is planned. Shared Apple sources must still compile for macOS.

Read [AGENTS.md](../../AGENTS.md) for repository rules and [PERSONAL.md](../../PERSONAL.md) for the
short project overview. This handoff supersedes the current-status claims in the 21 October setup
records. Their provisioning blocker was resolved; do not restart registration or installation setup.

## Purpose and owner preferences

The app is intended to replace the owner's WHOOP subscription for an owned WHOOP 4.0 strap while
retaining local collection, health history, recovery/sleep/strain views, workouts and useful widgets.
The recorded readiness target is **12 November 2026**, ahead of the stated **19 November 2026**
membership end. These remain planning dates, not a completed reliability qualification.

The owner wants the interface to resemble WHOOP as closely as practical for familiar, apples-to-apples
comparison. The accepted display terminology is **Sleep, Recovery and Strain**. The earlier
Charge/Effort/Rest presentation was changed in the personal app and widgets. This was a presentation
change: NOOP's independent calculations were not replaced with proprietary WHOOP algorithms.

The owner uses Hevy, Strava and Apple Health, has no Hevy Pro/API access, and accepted a hybrid of
automatic Health workout summaries plus pasted workout text after a session or occasional CSV
imports for full lifting details. Do not turn that into a paid API requirement.

Coach uses the owner's ChatGPT subscription without an API key. Signing in and consenting to send
health context are separate choices. The owner also requested commit-and-push checkpoints at
validated milestones. This handoff records both recent implementation workstreams together.

## Implemented and accepted

The 29 October redesign adds Today / Sleep / Training / Health tabs, a native separate Coach tab,
Profile access from the avatar, redesigned screens/widgets and the live classic-mode fallback.
Both Apple app targets compile, the isolated app and design suites pass, and synthetic simulator
captures cover default, AX5 and genuine empty states. See the report for exact results, known
baseline tool-test failures and the remaining widget, strap, alarm, haptic and overnight checks.
The owner reconfirmed history and saved Coach sign-in after this update; the workflow confirmations
below were recorded on 28 October and were not all repeated after the redesign.

| Area | Current behavior and evidence |
|---|---|
| Personal installation | Signed app and iPhone widget built; combined update installed in place. The owner opened the final app successfully. Existing app data and sign-in were retained. |
| Terminology | Recovery, Strain and Sleep labels updated across the relevant personal screens, explanations and widgets; installed and launched on the phone. Internal identifiers may still say Charge/Effort/Rest. |
| ChatGPT Coach | Browser sign-in, verified identity, device-only Keychain sessions, account-provided model discovery, Responses streaming, local chat history and existing context controls are implemented. The owner confirmed connection verification, normal replies and saved sign-in. |
| Coach summaries and briefs | Routed through the same session-aware provider with cancellation and account isolation. Automated checks passed; overnight execution and exact iOS scheduling remain field checks. Existing API-key and Custom providers remain available. |
| Workout text | More → Lift Log → Paste workout text → Preview → Save workout. Retains exercise names, sets, reps, weights and notes. The owner confirmed preview, saving and reopening. |
| Hevy CSV | More → Data Sources → Lifting log (Hevy/Liftosaur) → Choose export. Hevy set-level metadata is retained; identical imported start times are skipped. This is append/dedup behavior, not reconciliation of later edits or deletions. |
| Apple Health | Steps and workout summaries, with no Health writes or physiological imports. The combined update is installed and launched; the owner confirmed that Steps and existing data look right. Phone-free strap step tracking remains unresolved. The previously accepted Hevy workout import remains supported. |
| Widgets | The refreshed gradient backgrounds, contour artwork and layered score rings are installed for small/medium/large Home Screen score widgets. The steps widget now accepts source-labelled Apple Health totals, falling back to the existing band estimate. Physical rendering, value freshness and refresh behavior still need explicit acceptance. |

The workout parser preserves logged weights rather than inferring a combined dumbbell load. Missing
sets or durations stay unquantified. With no known interval, it can save a lift session without
inventing a workout duration. Hevy details do not add a muscular Strain model or change score formulas.
See [HEVY-HYBRID.md](HEVY-HYBRID.md) for supported formats, matching and import limits.

The earlier installed checkpoint requested workout summaries only. The 29 October combined update
is installed and expands that boundary to **Steps + Workouts reads**, using
`importsActivityOnly = true`. Existing workout consent resumes through the same persisted key; the
authorization fingerprint requests the added Steps scope on the next foreground sync. Daily and
hourly steps backfill up to 90 days after access is granted, then refresh on foreground entry and
Health observer delivery. Today, detail charts, source history and the steps widget retain the
Apple Health source label. The widget falls back to the existing WHOOP 4.0 estimate when no Health
count exists. Empty/failed reads preserve stored totals; step-only updates preserve unrelated
Health columns and metric series. Both Health writeback paths remain blocked, and physiological
imports remain outside this boundary. Installation and a normal foreground launch succeeded;
the owner confirmed that Steps, existing history and Coach sign-in look right.

Local validation of the repair: unsigned iPhone app/widget build passed; the shared macOS app
built and 56 focused app tests passed; five step-store tests passed. Localization and detached-doc
comment gates passed. Builds used an isolated source snapshot excluding concurrent widget-art
changes. These checks do not establish real Health access or background refresh on the phone.

The owner then asked to combine the repair with the **Refresh widget design** chat and install it.
The combined app and widget were signed with the unchanged personal identity; both signatures,
matching App Groups, HealthKit/background-delivery entitlements, unexpired profiles and physical-phone
inclusion were verified. The combined macOS build and all 56 focused app tests passed again. The
widget chat's 211 design tests passed. Installation succeeded on the physical iPhone and the app
launched normally after the owner unlocked it, without demo arguments or a debugger. Pre/post app
metadata retains the bundle identity, App Groups and group-container paths. The app data-container
path changed during the update, so metadata alone is not evidence that history survived; owner
confirmation is the acceptance check. The owner subsequently confirmed that Steps and existing
history/Coach sign-in look right, while questioning phone-free step tracking. The current 4.0 motion
estimate is not a validated replacement for a strap pedometer; Health totals do not establish that
phone-free walks were captured. No uninstall, restore,
Health write or signing-identity change was performed. Local install/launch evidence and the exact
combined source manifest are in ignored `build/personal/steps-widget-device/`. The earlier checkpoint
tags remain unchanged.

The initial Health/widget change targets the personal iPhone app and widgets; it did not change
Android behavior, schema, BLE commands or the step-estimation formula. A Health workout summary does not contain the complete lifting log.
No direct Hevy or Strava API sync was added.

### Subsequent strap-step repair and open-PR review

The owner clarified that carrying the phone cannot be required for steps and asked to inspect parent
repository PRs. [The upstream review](STEPS-UPSTREAM-REVIEW.md) screened all 134 open PRs returned on
29 October and inspected relevant diffs/checks. None adds a validated native WHOOP 4.0 pedometer or
reconciles partial-day Health coverage. No PR was cherry-picked. #2816 is an adjacent history-watchdog
candidate requiring separate hardware validation; #2705 and #2832 are performance candidates.

The later installed repair removes Health-positive-day suppression of the separate `steps_est` row.
Swift/Android orchestration now positively confirms the resolved day's WHOOP 4.0 owner and writes its
`owner-noop` namespace. Failed reads preserve existing values, and unknown registry families do not
erase calibration. A matched pure planning helper rejects nonfinite inputs and unsafe integer
conversions. The incumbent `coefficient × motion` estimator and default Health display preference
remain unchanged. Sources are not summed, gap-filled or described as measured strap steps.

On iPhone, **Today → Steps** (also Profile step settings) displays Health and the separate strap
estimate, source histories and calibration. Its local **Phone-free walk check** records a counted
500–1,000-step trial with one fixed strap identity, start/end and calibration. It requires usable
motion across the interval, rejects gaps over five seconds and reports incomplete coverage instead
of zero. It reports absolute error and sample/gap diagnostics; passing applies only to that walk.
Trials stay in app preferences, with no calibration feedback, Health writes or BLE capture commands.
The model is held-out instrumentation, not a new validated pedometer.

This repair was signed and installed in place on the physical iPhone. Its first functional revision
launched normally; the final copy-only revision also installed, but iOS blocked its launch because
the phone was locked. It can be opened normally after unlocking. App/widget
identities, App Groups, signatures, phone inclusion and unexpired profiles were checked. The prior
widget artwork remains included. Owner acceptance of this latest screen and repeated counted walks
are pending; earlier acceptance does not qualify this binary's step accuracy. Exact source hashes,
build, installation and launch evidence are in ignored `build/personal/strap-steps-device/`.

Validation: both Apple app targets compile; 71 focused macOS app tests pass, including 15 walk-model
cases. A standalone runner built from exact current analytics sources passed 29 XCTest methods and
the 216-case decision oracle matches Swift/Kotlin fixtures. Android tests are written but unrun
because the host lacks JDK/Android SDK. Full SwiftPM execution was blocked by an unavailable GRDB
submodule checkout; the focused runner avoids claiming a full package pass. Localization, whitespace
and detached-doc-comment checks passed. Parity governance status is recorded in the local repair
report; no debt disposition or external issue was created merely to bypass a gate.

The native-protocol investigation found no validated WHOOP 4.0 step field in NOOP. WHOOP 5's counter
offset is not evidence for WHOOP 4. A captured WHOOP 4 high-rate live frame exists, but its connection
to normal offline storage is unproved; the current IMU session writer does not preserve those 4.0
arrays. A failed NOOP walk check would establish a limitation of the current estimate/input, not of
the strap hardware. Further native-counter research needs a bounded private corpus of normal
offloads across labelled walks and stationary periods; no speculative historical-save command is
authorized or enabled by this repair.

## Original design brief — historical context

This section records the brief before the implemented redesign. For the current interface and
its flag, source map, deviations and verification, start with [the redesign report](REDESIGN-REPORT.md).

The design direction is WHOOP familiarity, using **Sleep / Recovery / Strain** consistently. The
broader intended native interface covers **Today / Sleep / Health / Training**; the final navigation
structure is still a design decision. The current tabs are **Today, Trends, Sleep, Coach, More**, with
Coach conditional on its master switch. Preserve access to the working Coach and import workflows.

An existing reference is [WHOOP design language](../superpowers/specs/2026-06-22-whoop-design-language.md).
It describes a dark neutral canvas, white/grey type, functional status colors, blue actions, three
Sleep/Recovery/Strain rings, compact metric rows and clear hierarchy. Treat it as a historical visual
reference, not proof of the current WHOOP app or a replacement for the owner's current preferences.
Its local screenshot paths may not exist on another machine. Existing upstream screenshots under
`docs/assets/` show NOOP reference screens, not necessarily the current installed personal build.

There are two Today implementations. **Liquid Today is enabled by default**, selected through
`noop.liquidTodayEnabled`; classic Today is the fallback. Reviewing only `TodayView.swift` can miss
the interface the owner actually sees. The repository contains several generations of visual
language, including Titanium & Gold/Liquid Metal and the earlier WHOOP reference. Resolve the
visible experience through the active view and tokens rather than applying every old spec together.

Useful review priorities:

1. The Today hierarchy: Sleep/Recovery/Strain, date selection, connection/battery, and useful daily
   health/training context with clear drill-downs.
2. Consistent labels, score formatting, chart colors and comparison baselines across Today, detail
   views and widgets. Search for legacy display words; keep stable storage and protocol keys intact.
3. Honest empty, stale, calibrating and disconnected states. Show source and freshness where needed;
   missing data must not look like a measured zero or a live reading.
4. The workout journey between Workouts, Lift Log and Health summaries; preserve the preview-before-save
   text importer and avoid presenting a summary as full set-level sync.
5. iPhone readability, Dynamic Type, contrast, safe areas and navigation state. Preserve the native
   back gesture and avoid remounting tabs when a preference changes.

UI work uses `StrandPalette`, `StrandFont` and shared layout/components. Put deliberate palette or
typography changes into tokens; do not scatter literal colors, font sizes or spacing across views.
Keep shared token APIs compatible. Use original implementation/assets and preserve upstream credits;
WHOOP logos, bundled proprietary assets and decompiled code do not belong in this fork.

Visual comparison does not establish score equivalence. Imported WHOOP scores, locally computed
scores and measured/imported biometrics need distinguishable provenance. WHOOP 4.0 steps are an
estimate from sparse motion; absolute skin temperature and offline SpO₂ percentages are not established
capabilities of that stream. Styling must not imply otherwise.

## Source map

| Concern | Entry points |
|---|---|
| iPhone shell and tabs | `StrandiOS/App/RootTabView.swift`, `StrandiOS/App/StrandiOSApp.swift` |
| Active/default Today | `Strand/Liquid/LiquidTodayView.swift`; supporting liquid components in `Strand/Liquid/` |
| Classic Today and detail screens | `Strand/Screens/TodayView.swift`, `SleepView.swift`, `HealthView.swift`, `WorkoutsView.swift`, `WorkoutDetailView.swift` |
| Design tokens and shared UI | `Packages/StrandDesign/Sources/StrandDesign/{Palette,NoopVisualStyle,Typography,DomainTheme,Components,StrandCard}.swift` |
| Metric labels and provenance | `Strand/Data/MetricCatalog.swift`, `Strand/Data/Repository.swift`, `Strand/Resources/Localizable.xcstrings` |
| Coach UI | `Strand/Screens/{CoachView,CoachSettingsView,CoachLauncherSheet}.swift`, `StrandiOS/App/ChatGPTConnectionView.swift` |
| Coach engine and transport | `Strand/AI/AICoach.swift`, `Strand/AI/ChatGPT/`, `Strand/AI/Providers/ChatGPT.swift`, `Strand/System/CoachBriefScheduler.swift` |
| iPhone sign-in lifecycle | `StrandiOS/App/{ChatGPTSignInCoordinator,ChatGPTLoopbackListener}.swift` |
| Lifting UI and imports | `Strand/Screens/{LiftLogView,LiftSessionDetailSheet,WorkoutTextImportSheet,DataSourcesView}.swift`, `Strand/Data/PersonalLiftingImport.swift` |
| Import parser and persistence | `Packages/StrandImport/Sources/StrandImport/LiftingImporter.swift`, `Packages/WhoopStore/Sources/WhoopStore/LiftLogImport.swift` |
| Health read/display | `StrandiOS/Health/HealthKitBridge.swift`, `Strand/Screens/AppleHealthView.swift`, `Strand/Data/HealthWorkoutReadMerge.swift` |
| Widgets | `StrandiOSWidgets/{NOOPWidget,NOOPLiveActivity}.swift`, `StrandiOSShared/PersonalWidgetMetrics.swift` |
| BLE and collection | `Strand/BLE/`, `Strand/Collect/`; protocol in `Packages/WhoopProtocol/` |
| Local data and analytics | `Packages/WhoopStore/`, `Packages/StrandAnalytics/`; backup orchestration in `Strand/Data/DataBackup.swift` |
| Build definition | `project.yml`; `Config/BundleId.xcconfig`; pinned `Strand.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` |

`project.yml` is authoritative. Generated Xcode project files and build products stay out of Git,
with the existing tracked SwiftPM lockfile exception. App version is still **12.1.0**, build **438**;
the checkpoint tag versions this working state without claiming a new product release.

## Earlier functional validation — 28 October

These are the 28 October implementation results, not fresh runtime tests performed for this
documentation checkpoint. The combined source commit records them, and the detailed Coach plan
has an [implementation checkpoint](../superpowers/plans/2026-10-28-iphone-chatgpt-coach.md#implementation-checkpoint--2026-10-28).

- Signed physical-iPhone build and signature verification passed; iPhone Simulator build passed.
- **133 focused app tests passed**: 68 subscription/auth/transport/engine/scheduler, 38 existing
  Coach regressions, 13 backup round-trip tests and 14 Health tests.
- Import package suite: **329 executed, 328 passed, one optional fixture test skipped**. Import
  work also passed its focused parser/storage/dedup checks.
- Source hygiene, whitespace and diff-scoped localization checks passed; new UI copy covered the
  existing ten locales.
- The owner confirmed the final installed app opens, Coach replies work, sign-in remains saved,
  pasted workouts save/reopen, and the Health-imported workout appears in the workout list.
- Kotlin CSV metadata/parser changes were mirrored for shared import parity. Android tests were
  not run on this Mac; there is no Android feature-delivery milestone in this personal scope.

## Remaining functional work

The owner reporting that the app works establishes accepted daily workflows, not completed sensor
accuracy or background qualification. The remaining checks are:

1. **WHOOP collection:** inspect stored HR/RR/motion and scored coverage, then record at least three
   nights, one complete workout, ordinary locked-phone operation, and reconnect/backfill after time
   away from the phone. Distinguish continuous collection from later catch-up.
2. **Phone-free steps:** two manually counted 500–1,000-step walks with at most **10% absolute error
   each**, plus at most **20 false steps in 30 seated minutes**. Calibration expects phone-step
   references; the installed update now supplies those after Steps consent. A read-only check of the
   phone's saved step settings after installation found banked motion and an automatic fit from three
   overlapping days. This is calibration evidence, not walk-accuracy evidence. The repaired engine
   preserves the independent WHOOP 4.0 estimate even on Health-positive days; it does not sum sources
   or fill partial-phone gaps. A validated strap-only counter/path remains the
   owner's requirement; merely preferring an estimate or changing its source label does not meet it.
3. **Widgets:** verify values, source/freshness labels, signed App Group publication and real refresh
   behavior. iOS controls refresh timing.
4. **Recovery:** export a private `.noopbak` and rehearse restoration in a separate disposable
   container. Preserve the official WHOOP export/history archive and verify any real import separately.
5. **Coach field behavior:** overnight briefs, locked-phone generation, dictation, connectivity
   interruptions, real token expiry and multiple live accounts. Automated seams cover these areas
   in part; normal sign-in/chat is the accepted on-device path. Scheduled wake timing is best effort.

The broader plan places data-validation gates before treating the custom interface as a finished
replacement. Claude can review and propose design changes now. See [DEVICE-TESTING.md](DEVICE-TESTING.md)
for the procedure; its sleep/workout tolerances beyond the agreed step limits are proposals.

## Build and collaboration notes

The later 29 October device/sync repair was signed, installed in place and launched normally after
the owner unlocked the iPhone. Device logs confirm Watch-pairing cleanup and completed WHOOP history
syncs with all observed sessions ended at the final capture. The personal activity-only Health path now
removes stale `liveAppleWatch` pairing metadata before source routing, retains all recorded Health
data, and cannot register phone steps as a Watch. Removing a non-WHOOP source cannot call WHOOP's
nil-peripheral disconnect fallback. Only intact history records/metadata renew the unchanged
60-second history idle timer; the policy is mirrored in Android. The signed iPhone/widget build,
shared macOS build, 101 focused app tests and 22 registry-store tests passed. Java/Kotlin tests were
unavailable locally. Private source/build/install evidence is in ignored `build/personal/sync-device/`.
The device logs include two 25/33-minute timeout sessions with near-total logging gaps, consistent
with suspension or delayed execution; they do not prove chatter caused those observed delays.
A quiet continuation pass exited at the existing 60-second idle limit; subsequent passes reached
`HISTORY_COMPLETE`. This verifies reconnect and bounded foreground behavior, not background or
overnight reliability, or the cause of the earlier suspended waits. History/sign-in retention
after this update still requires owner acceptance; the app was not uninstalled or restored.
The new Apple-only repair has a validated parity disposition. Derived-ledger refresh is still
blocked by the existing unreproducible `HEAD` authority and the earlier `upsertAppleDailySteps`
declaration; the rejected refresh restored both snapshots, with no authority waiver or migration.

Use the existing checkout and ignored local signing configuration; do not replace bundle IDs,
App Groups, team settings or the app container for visual changes. Keep both the iPhone app and
widget in the build graph, with no embedded watch app. The existing Xcode setup uses
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` per command.

From the repository root, the existing helper provides a setup check and an unsigned simulator build:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash Tools/personal/ios.sh check
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash Tools/personal/ios.sh build
```

The helper does not install or launch. For app changes, compile `NOOPiOS` and its widget; compile
`Strand` too when shared Apple sources change. Relevant `StrandTests` run under the macOS-hosted
`Strand` scheme. Package tests alone do not compile app-target screens. Regenerate with XcodeGen
after build-definition or source-membership changes. Select focused regression tests for the behavior
being changed, then visually review the active Today path and relevant detail states.

Before editing, inspect `git status` and coordinate any shared files with other active work. Do not
discard another contributor's edits. Design work should preserve BLE, formulas, schema, import
deduplication, account isolation, cancellation and consent boundaries unless separately required.
Shared analytics, stored-data and decoder changes retain the Swift/Kotlin parity contract even
though the personal product target is iPhone-only.

Credentials, signing profiles, device identifiers, health exports, databases, screenshots containing
personal data and build logs stay out of commits. `Config/BundleIdSecrets.xcconfig` and `build/personal/`
are ignored local state. ChatGPT tokens remain in the device-only Keychain, outside backups and
widget storage. A source checkpoint does **not** back up installed health data or credentials.

## Checkpoint and recovery

The annotated tag `checkpoint/2026-10-29-redesign-installed` records the accepted installed redesign
and its handoff on `personal/iphone-baseline`. The earlier annotated tag
`checkpoint/2026-10-29-before-design` remains the return point for the interface before the redesign.

```bash
git show --no-patch checkpoint/2026-10-29-redesign-installed
git diff checkpoint/2026-10-29-before-design -- path/to/file.swift
```

To start a recovery branch, first preserve any new work and confirm a clean working tree, then use
`git switch -c personal/recover-before-design checkpoint/2026-10-29-before-design`. Rebuild with the
same personal identity if returning that source to the phone. A Git checkout does not downgrade an
installed app, restore its database, recover Keychain state, or reconstruct ignored signing files.
Do not uninstall the working app or restore over its populated database to test this checkpoint.

Keep later work in small validated commits and push at useful milestones. Leave both checkpoint tags unchanged.
