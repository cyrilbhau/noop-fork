# NOOP iPhone redesign: implementation report

Initial implementation and follow-up audit: 29 October 2026 (Asia/Kolkata), following
[REDESIGN-IMPLEMENTATION.md](REDESIGN-IMPLEMENTATION.md). Branch `personal/redesign` on the private
repository, branched from `claude/noop-design-overhaul-3b7185` (30a7b3b7). The owner approved promoting
the accepted redesign to `personal/iphone-baseline` and creating the annotated installed checkpoint.
Nothing was pushed to `main`, and no PR was opened. The audited redesign was installed in place on
the owner's physical iPhone after backup confirmation and approval; see the install record below.

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
summarises them. The audit continuation below supersedes the original gap and verification claims.

## Audit continuation — 29 October 2026

The handoff was audited against the source, both app builds, the isolated app tests, and settled
simulator screenshots. The accepted source is checkpointed on `personal/iphone-baseline` under
`checkpoint/2026-10-29-redesign-installed`; `personal/redesign` retains the same history. The earlier
`checkpoint/2026-10-29-before-design` and remote safety branches remain intact. The phone now runs
the audited redesign. The owner confirmed existing history and saved Coach sign-in are intact;
the remaining daily-workflow and hardware checks are listed below.

| Handoff item | Result |
|---|---|
| A1 readiness wording | Stale Swift assertions now expect the accepted “Rest up”. The Kotlin twin was checked; its “Rest” wording remains unchanged, with the same readiness-level mapping. |
| A2 Live Activity scale | Widgets and Live Activities share one formatter over the original Strain value. Optional display text preserves old payload decoding. Scale changes refresh quiet banners; nil remains different from measured zero. |
| A3 tab tint | Neutral redesign tint; saved classic accent retained. |
| A4 inactive appearance settings | Preset, day-cycle background, sky, transparency and image controls are hidden with the redesign on. Stored choices remain untouched. |
| A5 shared presentation | Sleep marks, debt, stages versus typical, asleep duration, both body-clock cards, Mind, caffeine, stress check-in, training load, the live lifting editor and Workouts are restyled behind the iOS flag. Existing actions and reads remain shared. |
| A6 Coach shape | Explicit native `.prominent` on iOS 27; `.search` on iOS 26; normal fallback below that. The settled iOS 27 simulator screenshot confirms the separate circle. |
| A7 largest Dynamic Type | Removed the redesign's inherited AX1 cap. Verified AX5 before launch; adapted app headers, rows, grids, controls, week strip and lifting fields. Widget gallery and physical accessibility acceptance remain manual. |
| A8 duplicated decisions | Liquid Today/Recovery share the original readiness sentence; Coupled/Strain share original band thresholds. Boundary tests cover readiness levels, stale nights, and Strain cutovers. |
| Additional display audit | Today no longer truncates sleep minutes while Sleep rounds them. Both use the existing Sleep rounding and localized duration through one formatter, with a minute/hour-boundary regression. Daily-import totals and decoded-night totals retain their existing source semantics. |
| Additional honesty audit | Today and Health share one positive WHOOP 4.0 registry-family gate. They show blood oxygen as not measured, with no percentage, while preserving stored imports and other devices' source-labelled values. Percentages stay gated until the current device resolves. |
| A9 optional widget additions | No speculative metrics, new widget kinds, or invented sync totals/percentages added. |

| Audit concern | Commit |
|---|---|
| A1 — align readiness expectations with accepted wording | [`48ca0ce6`](https://github.com/cyrilbhau/noop-fork/commit/48ca0ce68be86fbafb77c165b42c505fdc017c63) |
| A2 — share the selected Strain scale with Live Activities | [`ff41e121`](https://github.com/cyrilbhau/noop-fork/commit/ff41e1210bd2efcd9882abe4bde0db3dd3cb6e46) |
| A3 — use neutral tab tint in the iPhone redesign | [`724d121c`](https://github.com/cyrilbhau/noop-fork/commit/724d121cc3ffdff8b262e4a56d227a01361bab2f) |
| A4 — hide inactive classic appearance settings | [`b0c3e773`](https://github.com/cyrilbhau/noop-fork/commit/b0c3e77318297a8e0b110fd40345852e37b26dd9) |
| A6 — request native prominent Coach tab on iOS 27 | [`ce02776d`](https://github.com/cyrilbhau/noop-fork/commit/ce02776dcf4ca61cd09914405f8fe5c582a9f15f) |
| A8 — share readiness copy and Strain band decisions | [`c26378e3`](https://github.com/cyrilbhau/noop-fork/commit/c26378e35ceaa43b4ff0c49667302b0df01e0f2c) |
| A7 — support actual AX5 text in redesigned screens | [`c779cacd`](https://github.com/cyrilbhau/noop-fork/commit/c779cacd393187a145e046873503889349de937b) |
| A10 — keep WHOOP 4 blood oxygen readouts consistent | [`0b7caf08`](https://github.com/cyrilbhau/noop-fork/commit/0b7caf080d435702ec90e19d0ea7a54d3fa74907) |
| A5-sleep — finish redesigned shared sleep cards | [`5e8f5a11`](https://github.com/cyrilbhau/noop-fork/commit/5e8f5a1133fe331604842ad53364bd20027adc71) |
| A5-wellness — finish redesigned wellness and training-load cards | [`115997bb`](https://github.com/cyrilbhau/noop-fork/commit/115997bb9298a4cfb435cd6d68657cbe385eab67) |
| A5-lift — finish the live lifting editor presentation | [`bb3d82ef`](https://github.com/cyrilbhau/noop-fork/commit/bb3d82efd2ade54eb0afe1ea189dab92d1d9c725) |
| A5-workouts — finish the redesigned workout history | [`95a2f1da`](https://github.com/cyrilbhau/noop-fork/commit/95a2f1da3e3517d9fe1514fa2305533771c7d178) |
| A7-caption — keep the full Strain target readable at AX5 | [`552be742`](https://github.com/cyrilbhau/noop-fork/commit/552be742f984273fa24700a39246fb385f3639c4) |
| A11-duration — format sleep duration consistently across Today and Sleep | [`b9a24f7f`](https://github.com/cyrilbhau/noop-fork/commit/b9a24f7fabb100887f6c2fcf4d760e45a7831095) |

The Strain target caption moves outside the arc at accessibility sizes so the actual range can wrap.
The minimized lifting-session bar retains its existing chrome; the full editor and finish flow are restyled.

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

- **Shell.** Tabs are Today, Sleep, Training and Health. Coach uses the native prominent role on iOS 27,
  the search role on iOS 26, and a regular fifth tab below that. Profile replaces More and opens from the
  avatar. The iOS root is pinned dark. Tab tags stay literal, so paths and scroll positions survive a Coach toggle. Every former More row is still
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
| 03 Sleep | Stages "Details ›" link; disturbances typical |
| 04 Training | Sessions-per-week goal (none exists, so the ring is unfilled and reads "no goal set"); weekly Strain total and week-over-week change; "3.4 a week"; distinguishing pasted from CSV |
| B1–B3 | "HR from strap" badge; usual HR recovery; Up next / active program; a per-dumbbell flag; RPE badge colours |
| A2–A4 | Per-row latest value and sparkline; a D range and manual entry; motion-stream freshness |
| 05 Health | "14 nights" link |
| C2–C6 | Sleep-hours Trends tile (Trends shows performance %, #732); live stress and notes; journal item icons; one-tap experiment start |
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
- A positively identified WHOOP 4.0 shows blood oxygen as “not measured” in Today and Health. Other
  or unknown devices retain existing source-labelled values after the shared registry lookup resolves.
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
- **Also hidden with the redesign on:** Preset, Day-cycle background, Sky behind cards, card transparency
  and background image. Their stored values are retained.
- **Tab tint:** neutral for the redesign; the saved Accent is used by classic mode.

## Test and build results — audited source

- **`cd Packages/StrandDesign && swift build && swift test`:** passed, 211 tests, zero failures.
- **NOOPiOS, generic iOS Simulator:** app and widget build succeeded.
- **Strand macOS build + StrandTests:** passed, 2,398 tests, two optional fixture tests skipped, zero
  failures. Tests ran alone with `-parallel-testing-enabled NO` in a disposable `/tmp` Git worktree,
  without `Config/BundleIdSecrets.xcconfig`, using the throwaway staging defaults domain.
- **Signed generic iOS build:** passed with the existing personal identity/profile and unchanged local
  config. App and widget signatures verify; they share the same team and App Groups. No watch app is embedded.
- **`python3 Tools/i18n_audit.py --ci HEAD`:** passed before each audit commit. Existing translated keys
  were reused; no catalog changes were required.
- **`python3 Tools/doc_comment_lint.py`:** passed.
- **`python3 -m unittest discover -s Tools`:** 339 tests; five failures, exactly the reproduced baseline set:
  four `test_check_source_references` assertions over `/var` versus `/private/var`, and the existing
  compact parity-authority mismatch (509 versus 510 files). The new Live Activity payload regression passed.
- **`git diff --check`:** passed.

The body-clock dial retains fixed-size hour numerals and its existing layout invariant test. The new Strain and sleep-duration
formatter tests and shared-readout tests pass in the full app suite. These checks establish compilation and
regression coverage; real strap interactions and physical widget refresh remain the checklist below.
Local build logs, device metadata and `.xcresult` bundles remain outside Git.

## Screenshots (simulator only, synthetic data)

- Dedicated **NOOP Redesign Review**, iPhone 18 Pro / iOS 27.0; dark appearance, status bar pinned to 9:41.
  The personal-data simulator was not used.
- Refreshed screenshots: gitignored `build/personal/redesign-screens/audit/default/` and `audit/ax5/`.
  They cover Today, Recovery, Strain, Sleep, Training, Health, Profile, Settings, Workouts and live lifting.
  The native shell capture confirms Coach's separate circle. Earlier before/after captures remain available.
- AX5 was set with `simctl ui … content_size accessibility-extra-extra-extra-large`, then read back before
  launching each batch. `capture-settings.json` records the category. The redesign now allows that category
  through the root; classic mode retains the previous cap.
- True empty-state captures use a separately created **NOOP Empty Audit** simulator with a fresh app
  container and no seed, covering Today, Recovery, Strain and Health. Missing scores/vitals render dashes
  and dashed rings, while calibration truthfully shows 0 of 4 nights. Simply omitting `--demo-seed`
  retains the previous database; those initial
  captures were relabelled `audit/retained-demo/`, never accepted as empty-state evidence.
- Captures wait for loading and entrance motion to settle. Early captures that were still loading were replaced; a loading
  frame is not evidence of a settled zero or an empty screen.
- Compared with the canonical Round 2, Round 3 and Round 4 HTML opened with `?static=1`. Functional controls,
  provenance and honest empty states take precedence over the mockups' illustrative values.
- At AX sizes, content stacks or scrolls instead of forcing data into fixed columns. Lifting numeric widths
  scale, the clock strip scrolls horizontally, and range/intensity pickers use menus. Fixed-family widget
  layouts still need native gallery/Lock Screen review; this host exposes simulator CLI capture but has no
  Simulator.app GUI for exercising that gallery.

## Needs on-device checking

- **Coach tab shape.** The separate circle is verified on the iOS 27 simulator with the explicit prominent
  role. Confirm it on the phone, including Coach being disabled and re-enabled.
- **Dynamic Type.** App AX5 captures now apply the real size. Confirm lower scrolled content, VoiceOver,
  native pickers, widget gallery and Lock Screen layouts on the phone.
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
- **Live Activity scale.** Fixed in source and covered by payload/formatter tests. Confirm both display
  scales against the app with a real activity, including switching scales without another HR sample.
- **Install acceptance.** The signed update is installed and launched. The owner confirmed existing
  history and saved Coach sign-in are intact. The remaining daily-workflow and hardware checks are pending.

## Install record — installed, history and sign-in confirmed

- **Date and source:** 29 October 2026 (Asia/Kolkata), source `c176345781a50a904287044f93743879ba67e22e`,
  version 12.1.0, build 438. Subsequent report-only commits do not change the installed binary.
- **Backup and authorization:** the owner supplied a fresh `.noopbak`, confirmed it had been created,
  and explicitly authorized proceeding. The backup remains private and was not restored or committed.
- **Preparation:** signed app and one widget extension built from the redesign worktree. Existing ignored
  signing config is byte-identical to the baseline checkout and remains ignored. No Config, entitlements,
  bundle IDs, team settings, storage keys or database migrations were changed by this audit.
- **Identity check:** pre- and post-update metadata from the physical iPhone confirms **NOOP Cyril**
  uses `com.cyrilbhau.personalhealth.noop`, matching the signed build. App and widget signatures verify,
  their team and App Groups match, and no watch app is embedded. Private identifiers are not recorded here.
- **Device selection correction:** an initial attempt selected a simulator and was rejected for platform
  mismatch before changing the phone. Selection was corrected to require `hardwareProperties.reality`
  equal to `physical`; the existing app identity was then verified on that phone before installation.
  Earlier connected-device metadata alone was simulator evidence, not physical-phone verification.
- **Installation:** `devicectl device install app` succeeded on the physical iPhone using the existing
  app identity. No uninstall, database restore or signing change was performed.
- **Launch and owner confirmation:** a normal foreground launch succeeded, without demo arguments or
  a debugger. Post-update app metadata confirms the expected identity. The owner explicitly confirmed
  that existing history and saved Coach sign-in are intact. Coach replies, widget freshness and strap
  behavior have not been reverified by this update.
- **Evidence:** installation/launch JSON, metadata and logs stay in ignored `build/personal/audit-device/`.
- A source checkout changes files on the Mac; it cannot downgrade or wipe the installed phone database.
  It is also not a backup of health data. An install or restore is a separate action requiring approval.
- After installation, record the owner-observed results for Coach sign-in, pasted-workout preview/save,
  Health summaries, Today/detail consistency and 04:00 rollover, calibration, widgets, alarms, Devices
  actions, Breathe timing, haptics, live HR/rest ring, and live classic-mode toggling.
- **Baseline checkpoint approval:** after confirming history and sign-in, the owner explicitly approved
  fast-forwarding `personal/iphone-baseline` to the accepted redesign and creating/pushing the annotated
  tag `checkpoint/2026-10-29-redesign-installed`. This documentation checkpoint preserves all tested
  application source. Remote branch deletion was not part of that approval.
