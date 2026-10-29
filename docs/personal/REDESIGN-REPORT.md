# NOOP iPhone redesign: implementation report

Written 29 October 2026 at the end of the implementation of
[REDESIGN-IMPLEMENTATION.md](REDESIGN-IMPLEMENTATION.md). Branch `personal/redesign` on the private
repository, branched from `claude/noop-design-overhaul-3b7185` (30a7b3b7). Nothing was pushed to `main`
or `personal/iphone-baseline`, no PR was opened, and nothing was installed on the owner's phone.

| Phase | Commit |
|---|---|
| 0 Baseline | no file changes. NOOPiOS simulator and Strand macOS builds both succeeded on 30a7b3b7 |
| 1 Foundations | `07704641` |
| 2 Navigation shell | `d7858b34` |
| 3 + 4 Today, Recovery, Strain, Sleep | `4db57aec` (committed together: Today's rings push the detail screens, which reuse Today's day model) |
| 5 Training | `31d30f6d` |
| 6 Health, metrics, C2–C6 | `96d8f7e1` |
| 7 Coach, Profile, settings | `c154a160` |
| 8 Notifications, widgets, Live Activities | `071f8844`, `b234c574`, follow-ups `6dac6e3c`, `1b82a6ee` |
| 9 Polish | `38c5e2c1` |
| 10 Visual check fix | `e9479898` |

Every commit message carries its own verification output and a per-phase gap list. This report
summarises them.

## How the redesign is switched

- One flag, `noop.redesignEnabled` (`NoopTheme.Keys.redesignEnabled`), default **on** for iPhone. Settings
  → Look and feel → **Use classic Today** turns it off. That brings back the previous Liquid/classic Today
  and the previous layout of every other redesigned screen, and `noop.liquidTodayEnabled` still works
  underneath. Only root content swaps, so the tab and its navigation path are not remounted.
- Shared `Strand/` screens branch on `#if os(iOS)` plus the flag. The classic layout is kept unchanged as
  the macOS path and the redesign-off path. Loads, sheets, alerts and side effects attach once and serve
  both layouts, so no data is read twice. The macOS app keeps its current look.
- New tokens and components live in a separate namespace in `Packages/StrandDesign`: `NoopTheme`,
  `NoopType` and the `Noop*` components. No existing `StrandPalette`/`StrandFont` member was changed.
  Three planned names already existed, so they shipped as `NoopGlassCard`, `NoopSectionHeader` and
  `NoopMetricRow` instead of `NoopCard`, `SectionHeader` and `MetricRow`.

## What changed, per screen

- **Shell.** Tabs are Today, Sleep, Training and Health. Coach uses `Tab(role: .search)` on iOS 26+ and is
  a fifth tab below that. Profile replaces More and opens from the avatar. The iOS root is pinned dark. Tab
  tags stay literal, so paths and scroll positions survive a Coach toggle. Every former More row is still
  reachable; the full map is in `d7858b34`.
- **Today.** Header with the date, which opens the calendar; a battery pill that opens Devices; and the
  avatar, which opens Profile.
  - Sleep/Recovery/Strain rings: Recovery in its band colour with its band word; Strain "of 21" or "of 100"
    by the user's scale.
  - The existing synthesis line and a provenance caption.
  - Heart-rate card, key metrics with sparklines and "Last: …" carries, Activity with source labels,
    hosted cards.
  - States: skeleton while loading, a strap-away banner, and a calibrating bar.
  - The score-driven ambient background.
- **Recovery and Strain detail.** Arc gauges.
  - Recovery shows What shaped it (HRV, resting HR, sleep performance, respiratory rate) against
    baseline ± sigma, plus 30-day band bars.
  - Strain shows the real target band, the day's workouts, heart-rate zones from the day's samples, and
    30-day bars.
- **Sleep.** 7-night ring strip, an asleep hero with a need bar, a connected step-line hypnogram, stage rows
  with typical marks, and quality tiles. Every existing sleep feature is kept.
- **Training.** Hub with sessions, daily Strain this week, a three-month consistency calendar, volume
  lifted, and recent sessions with source labels. Plus B1 workout detail, B2 Lift Log, B3 lift session,
  B4 paste (preview before save, unchanged), B5 workout in progress, and the B6 add sheet.
- **Health.** Chips, the overnight-vitals headline, line charts per signal, tinted vitals tiles, the blood
  oxygen honest row and Fitness Age. A2 All metrics, A3 the generic metric detail, A4 Live.
- **Trends, Stress, Breathe, Journal, What moves you.** Restyled with every feature kept. What moves you
  uses diverging bars with confidence captions and the sentence "A pattern in your data, not proof of
  cause."
- **Coach, Profile, Settings, Data sources, Backup, Devices, Alarm, Pair strap.** Restyled. Coach
  transport, auth and consent are untouched. Alarm's armed line comes from one gated resolver and one
  clock.
- **Widgets and Live Activities (round 4).** Light numerals, a time or source label on every value, Lock
  Screen accessories, and a Dynamic Island restyle.
  - Every widget `kind` and every attribute type name is unchanged.
  - Live HR gains an optional `zone`, so older activities still decode.
  - Sync shows a chunk count, never a percentage.
- **Notifications.** Copy-only changes for strain target, wind-down, battery, illness subtitle and Coach
  brief.

## Deviations from the plan (deliberate, with the reason)

1. **Calibration shows 4 segments, not 7.** The real seed is `Baselines.minNightsSeed = 4`; the mockup's
   7 is illustrative.
2. **The Strain target is recovery-dependent:** 14–18, 10–14 or 4–10 of 21, from
   `CoupledView.optimalStrainRange`. The mockups' fixed 12–15 is not used.
3. **Respiratory rate is not labelled "not part of the score".** It carries 5% of NOOP's Recovery formula.
4. **The strain-target notification keeps the title "Optimal strain reached".** The copy deck's "Strain
   target reached" is too close to WHOOP's own string, which an existing clean-room test guards against.
   The new body is used.
5. **There is no morning-summary sender in the app**, so there was nothing to restyle. The plan's
   "AppModel ~1526" is the wrist-alert mirror.
6. **One band-word resolver.** Today's ring, the Recovery headline and the widgets all say
   Low / Moderate / High, so the screens cannot disagree.
7. **One source-label resolver** (`TrainingProvenance`) for Today, Strain detail and Training.
   - A bare lifting-import workout row reads "Lifting import", because it cannot say whether sets are
     stored.
   - Pasted text and Hevy CSV share "Pasted or Hevy CSV · full sets", because they are stored identically.
8. **`textTertiary` is #8A8A93, not #5F5F67.** The mockup value was 2.7–2.9:1 on cards; the new value is
   5.1–5.4:1.
9. **Pair strap footer:** "NOOP never changes your strap's firmware." The mockup's "only reads" would be
   false, because NOOP sends reversible writes such as the alarm.

## Gaps (mockup elements omitted for lack of data)

| Mockup | Omitted element |
|---|---|
| 01 Today | 7-day average / typical sub-lines on metric rows; "Aim for Strain 12–15" in the summary; a live-growing HR bar; a "Training ›" link (no router API to switch tabs) |
| E1 | "Add last night" (no such flow); "Paused 6:40 AM" (no last-data time); a dedicated reconnect action (Reconnect opens Devices, as everywhere else) |
| E2 | Start/ready dates; 4-night average tiles |
| 02 Recovery | Sleep "of need" sub-line; nav-bar date and info button |
| A1 Strain | "Today so far" cumulative line (no cumulative Strain series); coaching copy |
| 03 Sleep | Stages "Details ›" link; disturbances typical; shared sleep cards (sleep marks, debt ledger, stages vs typical, asleep duration, body clock) keep their old style, including an uppercase overline in Sleep marks |
| 04 Training | Sessions-per-week goal (none exists, so the ring is unfilled and reads "no goal set"); weekly Strain total and week-over-week change; "3.4 a week"; distinguishing pasted from CSV |
| B1–B3 | "HR from strap" badge; usual HR recovery; Up next / active program; a per-dumbbell flag; RPE badge colours. The live lift-session screen and `WorkoutsView` are not restyled |
| A2–A4 | Per-row latest value and sparkline; a D range and manual entry; motion-stream freshness |
| 05 Health | "14 nights" link |
| C2–C6 | Sleep-hours Trends tile (Trends shows performance %, #732); live stress and notes; journal item icons; one-tap experiment start. MindSection, CaffeineLogCard, StressCheckInCard and TrainingLoadCard keep their old style |
| D1–D6, A6, C1, E3 | Coach context chips; verification time and extra include toggles; profile name and "tracking since"; per-row counts and ages; backup size, nights and snapshot list; per-stream dots, "worn on", "last charged"; a readback-confirmed alarm time and week strip; pair-strap step counter |
| R4 | Strain small widget and Lock Screen gauge (need a new kind or intent); sleep "% of need"; stress band word; imported vs computed provenance in widgets; zone bpm range; HR trace in the island; lift set totals and session name; sync total, percentage and strap model |
| R4-5 | Morning summary (no sender exists); the long-press custom notification view (a Notification Content Extension, which the plan says to ask about first) |

## Behaviour consciously preserved

- No changes to analytics, scoring, BLE, decoders, schema, migrations, import parsing or dedup, backup
  format, Coach transport/auth/consent, storage keys, `@AppStorage` keys, widget kinds, Live Activity
  attribute type names, bundle IDs, App Groups, signing or `Config/*`. Android untouched.
- Preview-before-save for pasted workouts; end-workout, discard and delete confirms; sleep delete with the
  7-second undo; every former More row is reachable.
- Missing data reads "—" or a dashed empty ring and is never animated or shown as 0.
- Steps are labelled estimated. Skin temperature is shown relative to baseline only.
- Blood oxygen shows a value only where the existing logic resolves one. Otherwise it is a "not measured"
  row.
- Imported vs computed scores carry source captions. Health workouts are labelled "summary only".
- Never-settling animations consult `NoopMotionState.poseStill` (Reduce Motion, Low Power, quiet motion).
- The new Devices buttons call existing user-initiated actions: Sync now (`syncNow`) and Buzz strap
  (`buzzStrapOnce`, the same call as Live's button). Nothing is sent automatically.

## Settings added or hidden (iOS)

- **Added:**
  - **Settings → Look and feel:** Colour from your scores, plus Subtle / Balanced / Vivid; Rings fill on
    every load (forced off under Reduce Motion, stored choice kept); Use classic Today.
  - **Customise Today → Background:** the same colour and intensity controls.
- **Hidden with the redesign on:** Theme (System/Light/Dark), which is inert because the root is pinned
  dark; **Accent colour**; **Chart colours**. Their stored values are untouched, and macOS still honours
  them.
- **Left visible, though they only affect classic or Liquid screens:** Preset, Day-cycle background, Sky
  behind cards, card transparency and background image.
- **Not hidden yet:** the tab bar tint still follows the Accent setting.

## Test and build results (final tree, `38c5e2c1` + `e9479898`)

- **`cd Packages/StrandDesign && swift test`:** 211 tests, 0 failures.
- **NOOPiOS (app and widgets), generic iOS Simulator:** `** BUILD SUCCEEDED **`.
- **Strand macOS build plus StrandTests:** 2392 tests, 2 skipped, 2 failures.
  - Both failures are assertions in `TodayChargeTapCollapseTests.testReadinessWord_mapsEveryLevel`, which
    expects "Rest" where `TodayView.readinessWord` returns "Rest up".
  - That function is untouched by this work; the mismatch dates from `e6e14c6a` on the baseline.
- **`python3 Tools/i18n_audit.py --ci HEAD`:** exit 0. Every new string has all 10 locales.
- **`python3 Tools/doc_comment_lint.py`:** OK.
- **`python3 -m unittest discover -s Tools`:** only the failures already present on the unmodified
  baseline.
  - 4 × `test_check_source_references` (macOS `/var` vs `/private/var` temp paths).
  - Parity governance `test_checked_metadata_is_compact_v3...` (authority 509 vs 510 files).
- **Process notes.**
  - The lexical parity ledger and i18n audit flagged generic helper names three times during the work
    (`clock`, `stat`/`statCell`, and a literal nested in an interpolation). Each was renamed or hoisted
    rather than editing a baseline.
  - Two StrandTests hosts run concurrently left `noop.coachEnabled = 0` in the throwaway test host's
    defaults domain (`com.noopapp.noop.staging`), which produced spurious Coach test failures. The key was
    removed and the suites were re-run one at a time.
  - That domain belongs to the unsigned /tmp worktree builds, not to the owner's app.

## Screenshots (simulator only, synthetic `--demo-seed` data, no personal data)

- **Simulator:** a dedicated "NOOP Redesign Review" device (iPhone 18 Pro, iOS 27.0), dark mode, status
  bar pinned to 9:41.
- **Location:** the gitignored `build/personal/redesign-screens/` folder in this worktree. The paths are
  local to the owner's Mac.
- **Before:** baseline build 30a7b3b7, in `before/`.
  - Populated: shell, liquidtoday, sleep, health, live, explore, trends, stress, insights, settings,
    devices, workouts.
  - Empty: liquidtoday, sleep, health, live, trends, settings.
- **After:** final build, in `after/`, populated and empty for shell, redesigntoday, recovery, strain,
  sleep, training, redesignhealth, profile, live, explore, trends, stress, insights, settings, devices
  and gallery. "shell-empty" is the first-run gate, as expected without a seed.
- **Largest accessibility text size:** `after-ax5/` holds redesigntoday, recovery, sleep, training,
  redesignhealth and profile. Titles and rows wrap without clipping in those shots.
- **Regenerating:** run a DEBUG build with `--demo-seed --demo-screen <name>`. The new names are
  redesigntoday, recovery, strain, training, redesignhealth, profile and gallery (the component gallery).

## Needs on-device checking

- **Coach tab shape.** On the iOS 27 simulator, `Tab(role: .search)` drew Coach inside the bar as a fifth
  item rather than as the separate circle. The code follows the plan; check on the phone.
- **Dynamic Type at the largest size.** The AX5 capture scaled less than expected, so check on the device.
- **Widgets.** Gallery sizes, Lock Screen vibrancy, refresh timing and "Updated" labels.
- **Live Activities.** Zone colours on a live banner from a real strap; the rest ring draining in the
  compact island; the striped sync bar.
- **Haptics and motion.** Ring-fill haptics, the heartbeat pulse at the measured BPM, ambient crossfade on
  day swipe.
- **Today flows.** The strap-away banner timing; pull-to-refresh starting a sync.
- **Alarm.** The armed / not-yet line against a real arm, connected vs queued.
- **Devices.** Sync now and Buzz strap on a WHOOP 4.0.
- **Breathe.** Orb timing against haptics and audio cues.
- **Settings.** Flipping "Use classic Today" live keeps navigation state.
- **Readouts across screens.** That Recovery and Strain match the Today rings after the 04:00 rollover and
  while calibrating.
- **Follow-up inconsistency.** The Live Activity shows Strain on the 0–100 axis, while widgets use the
  user's scale (pre-existing). Fixing it needs an `effortDisplay` field in the activity state.
- **Install.** The owner installs with `Tools/personal/ios.sh` and their own identity, as before.
