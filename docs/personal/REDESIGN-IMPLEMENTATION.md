# NOOP iPhone redesign: implementation plan

Written 29 October 2026 for an agent who has not seen the design conversation. If you were handed
this file with "Implement this", this file is your brief. Work through the phases in order, commit at
the end of each one, and stop only where a step says **Ask the owner**.

## 0. Read first, in this order

1. [`AGENTS.md`](../../AGENTS.md): repository rules. These override anything here if they conflict.
2. [`docs/personal/CONTEXT.md`](CONTEXT.md): the personal iPhone fork, the owner's preferences and the honesty rules.
3. This file.
4. The mockups in [`design/`](../../design). They are the visual source of truth (section 2).

## 1. Goal and hard boundaries

**Goal:** replace the iPhone app's current visual layer with the approved redesign. That layer is the
"Liquid" Today, textured vessel gauges, sky gradients and uppercase overlines. The new look is minimal
and information-dense, close to iOS 26 Apple Health. It has a black canvas with translucent cards,
thin rings and arcs, and gradient line charts. Background glows are driven by the day's scores. There
are skeleton loaders and spring motion throughout. It covers every iPhone screen, the widgets, the
Live Activities and Dynamic Island, and notification copy.

**Do not change (each is a hard rule):**
- Analytics, scoring formulas, BLE/collection, protocol decoders, database schema/migrations, import
  parsing/dedup, backup format, Coach transport/auth/consent. This is a presentation-layer project.
  If a screen needs a value that does not exist, **do not compute a new metric**. Omit the element
  or show the honest empty state, and list it under "Gaps" in your final report.
- Storage keys, `@AppStorage` keys, widget `kind` strings (`NOOPWidget`, `HeartRateWidget`,
  `StressWidget`, `CoachBriefWidget`, plus those in `PersonalMetricsWidgets.swift`), Live Activity
  attribute type names, bundle IDs, App Groups, signing, `Config/*`. Installed widgets and running
  activities must survive the update.
- Android. It is out of the personal scope; leave `android/` untouched and say so in commit messages.
- The macOS app's look. Shared files under `Strand/` still compile for macOS, but the macOS app must
  keep its current appearance (see 3.1).
- `main`. Work on a branch (Phase 0). Never push to `main` or `personal/iphone-baseline`.

**Honesty rules carried into the UI** (from CONTEXT.md, non-negotiable):
- Missing data shows a dash or a dashed empty ring, never `0` and never an animated fill.
- Stale data says when it is from ("Last: 58 ms · Tue night").
- WHOOP 4.0 steps are always labelled **estimated**. Skin temperature is always **relative to
  baseline**. Blood oxygen is **not available offline on WHOOP 4.0** and is shown as an empty
  "not measured" row, never a number.
- Imported WHOOP scores and NOOP-computed scores stay visibly distinguishable. Use a source caption
  such as "NOOP score · computed on iPhone" or "WHOOP import".
- Apple Health workouts are **summaries only**. Pasted or Hevy-CSV lifts have **full sets**. Label
  rows accordingly.
- Display terms are **Sleep, Recovery, Strain** (never Charge/Effort/Rest in UI). Internal
  identifiers such as `chargeColor` and `effort` may stay.

## 2. Design source of truth

| What | Where |
|---|---|
| Shared tokens (colour, radii, spacing, motion CSS) | `design/system/noop.css` |
| Rings, arc gauge, line/area charts, ambient field, skeleton + motion runtime | `design/system/noop.js` |
| Approved core direction (Today, Recovery, Sleep, Training, Health, loading, ambient states, motion spec) | `design/round2/index.html` |
| Batch A: Strain, All metrics, Metric detail (HRV), Live heart rate, Customise Today, Strap | `design/round3/today.html` |
| Batch B: Workout detail, Lift Log, Lift session, Paste workout, Workout in progress, Add sheet | `design/round3/training.html` |
| Batch C: Alarm, Trends, Stress, Breathe, Journal, What moves you | `design/round3/sleep-health.html` |
| Batch D: Coach, Coach connection, Profile, Data sources, Settings, Backup | `design/round3/coach-profile.html` |
| Batch E: Today with strap away, first-week calibrating, pair strap, widgets (superseded by round 4) | `design/round3/states.html` |
| Round 4: Home Screen widgets, Lock Screen, Dynamic Island, notifications | `design/round4/system.html` |
| Superseded first draft (reference only) | `design/round1/index.html` |

To view a mockup, open the HTML file in a browser. It animates on load, and there is a "Replay load"
button. Append `?static=1` to see the settled state. The relative `../system/` links work from
`file://`. The same frames are in Figma, at
`https://www.figma.com/design/pZiuw8RGJXIDdDSHXnA6O6`, on pages Round 2 to Round 4. The Figma MCP on
that account is rate-limited, so **treat the HTML as canonical**; do not depend on Figma.

**Screen IDs** used below (A1…E3, R4-1…R4-5) are the `board-title` labels in those files.

The mockups use made-up numbers. Every number in the app must come from the existing data layer.

## 3. Foundations spec

### 3.1 Where the new tokens live

Add a **new** token namespace in `Packages/StrandDesign` rather than mutating existing values. The
macOS app and any screen not yet migrated then keep working unchanged.

- New file `Packages/StrandDesign/Sources/StrandDesign/NoopTheme.swift`, `public enum NoopTheme`,
  for colours, radii, spacing and motion.
- New file `NoopType.swift` for the type ramp.
- New component files (3.6). Keep each file single-purpose, as the package already does.
- Do **not** rename or change existing `StrandPalette`/`StrandFont` members; other code reads them.
  You may add members. Redesigned views use only `NoopTheme`/`NoopType` and the new components; no
  literals in views (AGENTS.md "Design system is law").
- No `import UIKit` under `Packages/` (guard with `#if canImport(UIKit)` if ever needed).

### 3.2 Colour tokens (dark-only)

The redesign is dark-only. Apply `.preferredColorScheme(.dark)` on the iOS root (`StrandiOSApp`),
and do not touch macOS. Values come from `design/system/noop.css`.

| Token | Value | Use |
|---|---|---|
| `canvas` | `#000000` | screen background |
| `card` | `#1A1A1E` at 74% + `.ultraThinMaterial`-style blur, 1 pt `white 5%` border | cards, tiles |
| `cardSolid` | `#151518` | where blur is unavailable (widgets use their own) |
| `control` | `#2C2C32` at 72% | round icon buttons, pills, chips |
| `track` | white 8% | ring/arc/bar tracks |
| `separator` | white 7% | row dividers |
| `textPrimary` | `#F5F5F7` | |
| `textSecondary` | `#9B9BA3` | |
| `textTertiary` | `#5F5F67` | captions, source lines |
| `recovery` (high ≥67) / `recoveryMid` (34–66) / `recoveryLow` (<34) | `#2FD27A` / `#FFC83D` / `#FF5A4F` | Recovery colour comes from its band, everywhere |
| `strain` | `#3A9BFF` | |
| `sleep` | `#8F7DFF` | |
| `heart` | `#FF4D6B` | heart rate, resting HR |
| `hrv` | `#47C8F5` | |
| `breath` | `#36D3BF` | respiratory, Breathe, sync |
| `temp` | `#FF9F45` | skin temperature |
| `lift` | `#FF8A3D` | lifting, steps |
| `stress` | `#FF7A59` | |
| `coach` | `#C8A8FF` | Coach |
| `stageAwake/REM/Light/Deep` | `#C9C9D1` / `#6FD3FF` / `#8F7DFF` / `#4A3AD0` | hypnogram, stage rows |
| `zone1…zone5` | `#7FD1FF` `#2FD27A` `#FFC83D` `#FF8A3D` `#FF4D6B` | HR zones, zone-gradient lines |

Provide `NoopTheme.recoveryColor(for score: Int) -> Color` implementing the band thresholds above.
Verify they match the existing band logic in `StrandAnalytics`/`Repository`. If they differ, **use
the existing thresholds** and note it.

### 3.3 Type ramp

Use the default SF Pro design (`.default`), not `.rounded`; the current `StrandFont` is rounded.
Every style must scale with Dynamic Type (`Font.system(size:weight:design:)` wrapped with
`@ScaledMetric`, or text styles with `.fontWeight`). Numerals use `.monospacedDigit()`.

| Style | Size / weight / tracking | Use |
|---|---|---|
| `largeTitle` | 34 bold, −0.6 | tab titles ("Today", "Sleep") |
| `screenHeadline` | 30 bold, −0.6 | "Recovered", "Moderate" |
| `sectionTitle` | 20 semibold, −0.3 | section headers ("Key metrics"), sentence case. **No uppercase overlines** |
| `rowTitle` | 15 semibold | metric/list row titles |
| `body` | 17 regular, secondary colour, 24 line height | explanatory copy |
| `bodySmall` | 15 regular | card copy |
| `footnote` | 13 regular secondary | sub-lines |
| `caption` | 12 medium tertiary | source/freshness captions |
| `heroNumber` | 84 bold, −4 | Recovery/Strain arc centre |
| `bigNumber` | 44–52 semibold, −1.5 | Sleep "7h 42m", live HR |
| `tileNumber` | 40 semibold, −1.2 | tile values |
| `rowNumber` | 22 semibold | metric row values; unit 13 regular secondary |
| `ringLabel` | ring size × 0.25, semibold | numbers inside rings |
| **Widgets / Live Activities** | numerals **Light (300)**, 38–46, −1.4; labels **Medium 12**; captions Regular 12 at white 50% | round 4. Widgets are deliberately thinner and airier than in-app |

Units are always smaller and secondary ("62 ms", "52 bpm", "68%").

### 3.4 Layout tokens

Screen gutter 16; gap between cards 12; card radius 22; tile radius 20; widget radius 24
(the system clips, so match the container); card padding 18 (rows 14/18); section header padding
26 top, 10 bottom, 20 sides. Round icon buttons are 40 pt. The tab bar and its hit areas stay
native. The minimum touch target is 44 pt.

### 3.5 Motion tokens

| Motion | SwiftUI |
|---|---|
| Card entrance | rise 16 pt plus scale 0.98→1 plus fade; `.spring(response: 0.45, dampingFraction: 0.78)`; 40 ms stagger top to bottom |
| Ring/arc fill on **every appearance and refresh** | trim 0→value, `.spring(response: 0.9, dampingFraction: 0.72)` (≤4% overshoot); the number counts up in step (0.9 s ease-out, `contentTransition(.numericText())`); `.sensoryFeedback(.impact(weight: .light))` on settle |
| Chart draw | line `trim` 0→1 over 0.7 s ease-out; area fades in 0.2 s later; latest-point dot pops 0→1.15→1 |
| Bars | grow from the baseline with a spring, 18 ms stagger |
| Skeleton | card-shaped placeholders with 2–3 faint text bars; 110° light sweep, 1.25 s linear loop; shown only while loading, at least 300 ms so it never flickers |
| Press | scale 0.965 on touch-down (0.12 s), spring back |
| Ambient field | crossfade 0.8 s when the date or scores change; slow drift 18 s autoreverse while idle |
| Day swipe | interactive spring; incoming day's rings refill and the ambient crossfades |
| Live heart | heart icon pulses at the measured BPM |
| Tab switch | native; symbol bounce on select |
| **Reduce Motion** | everything becomes a 0.15 s fade; no drift, overshoot or pulsing; rings appear filled |

Put the curves in `NoopTheme.Motion`. Respect `@Environment(\.accessibilityReduceMotion)`. Add a
Settings toggle **"Rings fill on every load"** (default on, forced off under Reduce Motion).

**Never animate missing data:** no fill and no count-up from 0 for a value that is absent.

### 3.6 Components to build in `StrandDesign`

Each needs a SwiftUI preview, and a unit test wherever there is logic (band mapping, ambient
weights, chart domain).

1. **`NoopRing`** (value 0…1 or nil, colour, lineWidth, optional label/unit/icon, `empty` state
   drawn as a dashed 45%-width track). Starts at 12 o'clock, round caps, track at `track` colour.
   Used everywhere from 30 pt (week strip) to 230 pt (live HR).
2. **`NoopArcGauge`**: 240° sweep starting at 150° (7–8 o'clock to 4–5 o'clock), stroke 22, white
   knob at the value, gradient from colour at 55% to 100%. Optional target-band ticks; Strain shows
   its 12–15 target. Used for Recovery and Strain detail heroes (round 2 "02 Recovery", A1).
3. **`NoopLineChart`** (Swift Charts): `LineMark` with `.catmullRom` interpolation; `AreaMark` with
   a vertical gradient from colour at 42% to 0; stroke gradient left to right from 30% to 100%
   opacity; latest-point dot with a 22% halo. Optional `zones: true` colours the line by HR zone
   (vertical gradient z5→z1). Optional selected-point vertical rule and tooltip (A3).
   **No horizontal gridlines, rule marks or range bands**: the owner explicitly rejected straight
   horizontal lines across charts. A "typical range" may only set the y-domain. Axis labels are a few
   captions under the chart, not chart axes.
4. **`NoopBarChart`**: rounded capsule bars; colour per bar (Recovery band) or single colour; latest
   bar full opacity, others 75%.
5. **`AmbientField`**: the score-driven background (3.7).
6. **`NoopCard`**, **`NoopTile`**, **`MetricRow`** (title in domain colour, sub-line, value plus
   unit, optional sparkline `NoopLineChart` 64–72×30), **`SectionHeader`** (sentence-case title plus
   trailing link with chevron), **`SourceCaption`** (dot plus "Computed on iPhone · synced 6:12 AM"),
   **`NoopPill`**, **`NoopChip`**, **`SegmentedPills`** (D/W/M/6M/Y), **`ZoneBars`**,
   **`RangeIndicator`** (track, typical band and value dot; this one may show a band because it is a
   gauge, not a chart, as on the Recovery "What shaped it" rows), **`StatGrid`**.
7. **`SkeletonModifier`**: `.noopSkeleton(isLoading)` draws the shimmer card and hides the content.
8. **`NoopEntrance`**: a staggered-entrance modifier driven by an index.
9. **`DomainIcon`** tiles (42 pt, radius 13, colour at 14% background, SF Symbol in colour). Use
   SF Symbols, not the mockup's hand-drawn SVG icons.

### 3.7 Ambient field

This is the owner's favourite idea, so get it right. It is a soft colour wash behind the top ~600 pt
of each screen, rendered as a few radial gradients ("blobs"), a faint texture of concentric circles,
and a fade to black. The colours and strength come from the data, like Apple Card changing with
spending.

- **Blob** = radial gradient, stops 0 → colour at α, 38% → α×0.45, 70% → 0. Two of three blobs
  drift.
- **Texture:** concentric circles centred at (330, 40) pt, radii 48…640 every 34 pt, white 3.5%,
  1 pt stroke.
- **Fade:** linear gradient from clear to 25% black at 45%, 85% black at 80%, solid black at 100%.
- **Today** (s = sleep %/100, r = recovery %/100, t = strain/21):
  - Sleep blob: `sleep` at (40, 10), radius 150+170s, α 0.16+0.38s
  - Strain blob: `strain` at (380, 40), radius 150+170t, α 0.16+0.38t
  - Recovery blob: **band colour** at (210, −30), radius 170+190r, α 0.18+0.42r
  - A missing score contributes no blob. With no scores at all, use a neutral `textTertiary` blob at
    α 0.3 (E1).
- **Other screens** use fixed palettes, listed as `[colour, x, y, radius, α]` in each mockup's
  `data-ambient` attribute (for example Recovery: band colour plus `hrv`; Sleep: `sleep` + REM +
  deep; Training: `lift` + `strain`; Health: `recovery` + `hrv` + `heart`). Copy them from the HTML.
- **Setting:** "Colour from your scores" toggle, plus **Subtle / Balanced / Vivid**, which multiplies
  α by 0.6 / 1.0 / 1.4. These settings appear in A5 Customise Today and D5 Settings.
- Implement it as a pure function `ambientBlobs(for: TodayScores, intensity:) -> [Blob]` plus a
  view. Unit-test the function.

## 4. Phases

Commit at the end of every phase; small commits within a phase are fine. Keep the app shippable after
each phase: unmigrated screens may look old, but nothing may break.

### Phase 0: branch and baseline

- `git fetch origin && git switch -c personal/redesign origin/claude/noop-design-overhaul-3b7185`.
  That branch contains the checkpointed app source plus `design/`. If it is missing, branch from
  `checkpoint/2026-10-29-before-design` and copy `design/` from the design branch.
- Confirm a clean baseline build:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash Tools/personal/ios.sh check`, then
  `… ios.sh build`. Also build macOS: `xcodegen generate && xcodebuild -project Strand.xcodeproj
  -scheme Strand -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`. Record any
  pre-existing failures before you change anything.

### Phase 1: foundations (StrandDesign)

Build section 3: `NoopTheme`, `NoopType`, motion tokens, all components and `AmbientField`, with
previews and `swift test` coverage in `Packages/StrandDesign/Tests/StrandDesignTests` (band mapping,
ambient weights and intensity, chart y-domain including the typical range, the reduce-motion path).
Add a debug-only gallery view that shows every component for screenshot review.

**Done when:** `cd Packages/StrandDesign && swift build && swift test` passes and both app targets
still build.

### Phase 2: navigation shell (`StrandiOS/App/RootTabView.swift`)

The new structure: **Today · Sleep · Training · Health** as tabs, **Coach** as a separate circular
button, and **Profile** (replacing More) behind an avatar button at the top-right of each tab's
header.

- On iOS 26 use `Tab(role: .search)` for Coach, so the system draws it as the separate circle next to
  the tab bar. Keep the label "Coach" and the sparkles symbol. On iOS 17–25 it falls back to a normal
  fifth tab. Keep the existing master-switch behaviour: Coach hidden when off, and if it is switched
  off while selected, return to Today.
- **Re-index carefully.** `tabPaths` and `scrollTop` are indexed by tag, and the code deliberately
  keeps tags literal so paths and scroll positions survive a Coach toggle. Keep that property with
  the new tags, and keep re-tap-to-pop and scroll-to-top.
- The Today tab's horizontal swipe changes **days**, so tab-swipe stays disabled there, as now.
- **Profile** (D3) is a sheet with its own `NavigationStack`. It reuses `MoreDestination` for every
  row that existed in More (none may become unreachable). Group the rows as **Your data** (Data
  sources, Apple Health, Backup), **Tools** (Alarm, Breathe, Stress, Journal, Intervals, Live), and
  **Insights** (What moves you, Trends, All metrics, Intelligence, Compare, Lab Book). Add
  **Settings** (gear button) and a **More tools** group holding the remaining rows (Rhythm, Your
  Data Fused, Mi Band, Shortcuts Export, NOOP Limitations, Automations, Test Centre, Siri &
  Shortcuts, Power saving). Show the strap card (battery ring and sync state) at the top.
- **Training tab** = a new hub view (round 2 "04 Training"). It links to the existing `WorkoutsView`
  (restyled in Phase 5), Lift Log, and workout detail.
- **Health tab** = round 2 "05 Health" (new view; restyled vitals).
- **Trends** is no longer a tab. Reach it from Recovery "Last 30 days › Trends", Strain, and Profile.
- `.tint` stays native. Do not build a custom tab bar; the mockup's pill bar is the iOS 26 Liquid
  Glass bar.

**Done when:** every destination reachable today is still reachable (list them in the commit
message), Coach and Profile work, and state is preserved across tab switches and Coach toggles.

### Phase 3: Today (the screen the owner looks at most)

Mockups: round 2 "01 Today" and "01b Today, loading"; E1 and E2 for the states.

- Build a new `RedesignTodayView` (iOS). **Reuse the data plumbing from `Strand/Liquid/LiquidTodayView.swift`**:
  - the day navigation (swipe and calendar, day-keyed reads)
  - the `// MARK: - Data` and `// MARK: - Derived` sections
  - the key-metric editor (`KeyMetricPrefs`)
  - the hosted cards
  - the strap battery and sync state
  - the synthesis one-liner

  Extract shared logic into a model type if needed, **without changing behaviour**. Do not duplicate
  reads.
- Add `noop.redesignEnabled` (`@AppStorage`, default **true** on iOS), with a Settings row to fall
  back to the existing Liquid/classic Today. `noop.liquidTodayEnabled` keeps working underneath.
  The switch must not remount the tab or lose navigation state (CONTEXT.md priority 5).
- Layout, top to bottom:
  1. The header: large title, date, strap battery pill and avatar.
  2. The rings card: three 96 pt `NoopRing`s, in the order Sleep, Recovery, Strain. Recovery takes
     its band colour and a band word; Strain shows "of 21". A divider, then the summary headline and
     sentence (existing synthesis), then the source caption.
  3. **Heart rate**: the live value with a pulsing heart, today's range, and the day's HR bars.
  4. **Key metrics** rows, with sparklines, from the user's key-metric selection.
  5. **Activity**: today's workouts.
  6. Then any hosted cards the user has added.
- Tapping a ring opens its detail (Phase 4). Tapping a metric row opens Metric detail (Phase 6).
- **States:** a skeleton while loading. E1 is the strap-disconnected banner with Reconnect, empty
  dashed rings for missing scores, "Last: … · Tue night" sub-lines and "Add last night". E2 is the
  calibrating state, "Night 4 of 7", with a 7-segment progress bar. Use the existing calibration and
  baseline signals; do not invent new ones.
- **A5 Customise Today** sheet: restyle the existing `TodayCustomizationSheet`, keep its behaviour,
  and add the Background section (3.7).

### Phase 4: score details

- **Recovery** (round 2 "02 Recovery"): arc gauge, headline (band word), explanation, source caption.
  **What shaped it** lists HRV, resting HR, sleep performance and respiratory rate, each as a
  `RangeIndicator` against the user's typical range; respiratory is marked "not part of the score"
  if that is true of NOOP's formula (check). Then 30-day band-coloured bars with avg and green/yellow/
  red counts, linking to Trends.
- **Strain** (A1): arc gauge with the 12–15 target ticks (use the existing target logic in
  `Strand/System/StrainTargetNotifier.swift`), "Today so far" cumulative line, today's workouts,
  HR-zone bars and 30-day bars.
- **Sleep tab** (round 2 "03 Sleep"):
  - restyle `SleepView` and keep all its features (naps, sleep marks, wake-time editor, alarms entry,
    delete/undo, provenance explainer)
  - a 7-night ring strip, the asleep hero with need bar, the stage chart and stage rows with typical
    marks, and quality tiles
  - the hypnogram may be redrawn as a connected step line, which the owner preferred to blocks

### Phase 5: Training

Mockups: round 2 "04 Training"; B1–B6.

- **Hub:** sessions ring, week Strain, the consistency dot calendar (lift vs cardio, 3 months),
  volume lifted (from logged sets), recent sessions with **source labels** ("Pasted from Hevy · full
  sets", "Apple Health · summary only", "Hevy CSV · full sets"), and a "Paste a workout" row. If no
  sessions-per-week goal exists, show the count without a goal (Gap).
- **B1 Workout detail:** restyle `WorkoutDetailView`: stat grid, zone-coloured HR line, zone bars,
  HR recovery ring. Keep the existing route map and exports where data exists. Keep "Route and splits
  are not in Apple Health workout summaries" for Health-sourced rows.
- **B2 Lift Log, B3 Lift session:** restyle `LiftLogView` and `LiftSessionDetailSheet`. Keep the
  per-dumbbell wording, RPE and notes.
- **B4 Paste workout:** restyle `WorkoutTextImportSheet`. **Keep the preview-before-save flow
  exactly.** Warnings ("Duration not provided") use the amber card. Parse warnings use per-row warn
  icons.
- **B5 Workout in progress:** restyle `LiveWorkoutView` and the live session. The zone ring and Strain
  ring are concentric; there are big elapsed and BPM figures and end/pause controls (keep the existing
  confirm-to-end behaviour).
- **B6 Add sheet** from the "+" button: Record a workout, Start a lift session, Paste workout text,
  Import Hevy CSV, Add a past workout. Each row routes to the existing flow.

### Phase 6: Health and metrics

Mockups: round 2 "05 Health"; A2, A3, A4; C2–C6.

- **Health tab:**
  - chips (Vitals, Resting HR, Fitness Age) and the overnight-vitals headline
  - **line charts per signal**, gradient-filled, with no horizontal lines
  - four tinted vitals tiles, with their charts bleeding to the tile's bottom edge
  - the blood oxygen empty row, and Fitness Age
  - reuse the data from `HealthView` (vital signs, Fitness Age, skin temp suite) and keep its other
    sections reachable
- **A2 All metrics:** restyle `MetricExplorerView`, grouped by category, with a source caption per row.
- **A3 Metric detail:** a generic template for any metric. D/W/M/6M/Y segment, average, chart with
  tap-to-select tooltip, stat grid (latest, trend, low, high), and an About card with
  how-it's-measured text.
- **A4 Live heart rate:** restyle `LiveView` with the big pulsing BPM, zone strip, last 5 min chart,
  and stream freshness rows.
- **C2 Trends, C3 Stress, C4 Breathe, C5 Journal, C6 What moves you:** restyle `TrendsView`,
  `StressView`, `BreathingView`, the journal views (`JournalLogCard` and related) and
  `InsightsHubView`/`InsightsView`.
  - Keep every existing feature, including the Breathe sweeps, audio cues, coherence and personal
    experiments.
  - C6 shows diverging bars around a centre line, with a confidence caption.
  - It keeps the sentence "A pattern in your data, not proof of cause."

### Phase 7: Coach, Profile and settings

Mockups: D1–D6, A6, C1, E3.

- **D1 Coach:** restyle `CoachView`. Keep the scope chip "Using today's scores, sleep and workouts"
  (only when health context is enabled), and context chips under answers when the response carries
  them. Add suggested prompts and an input bar with a mic (existing `CoachVoiceInput`). The typing
  indicator is three bouncing dots. **Do not touch transport, auth or consent logic.**
- **D2 Coach connection:** restyle `CoachSettingsView` and `ChatGPTConnectionView`. Keep the
  existing provider choices (ChatGPT plan, API key, Custom) and the separate consent toggle. The
  morning-brief copy says "Timing is up to iOS, so it can arrive late".
- **D4 Data sources, D5 Settings, D6 Backup, A6 Strap, C1 Alarm, E3 Pair strap:** restyle
  `DataSourcesView`, `SettingsView` (iOS sections only), `BackupSyncView`, `DevicesView`,
  `SmartAlarmView` and `AddDeviceWizard`. Each keeps all its behaviour.
  - **Alarm:** the countdown/"Armed on strap" line appears only when the alarm is actually armed
    (AGENTS.md "Two readouts of one fact").
  - **Settings:** add the redesign rows (Colour from your scores and intensity; Rings fill on every
    load; Use classic Today).
  - Existing "Accent colour" and "Chart colours" settings do not affect redesigned screens. Hide them
    on iOS when the redesign is on, and **mention this in the report**.

### Phase 8: widgets, Live Activities and notifications

Mockups: round 4 (R4-1…R4-5).

- **Widgets** (`StrandiOSWidgets/*.swift`):
  - restyle to R4-1: Light numerals, 18 pt padding, one idea per widget, and a time/source label on
    every value
  - keep every `kind` and all configuration intents
  - keep `containerBackground` for iOS 17+, and support the Lock Screen accessory families as in
    R4-2 (circular gauges, rectangular "Recovery 68% · HRV 62 · Slept 7h 42m")
  - widget strings live in `StrandiOSWidgets/Localizable.xcstrings`
- **Live Activities** (`NOOPLiveActivity`, `LiftLiveActivity`, `SyncLiveActivity`): restyle the
  Lock Screen and Dynamic Island compact, minimal and expanded regions (R4-2, R4-3, R4-4).
  - **Live HR:** the zone colour needs a max-HR-derived zone. Compute the zone in the app and add an
    optional `zone: Int?` to `NOOPActivityAttributes.ContentState`. Optional keeps decoding
    compatible. Keep `Self.shownBpm` semantics.
  - **Lift:** the existing timers stay `Text(timerInterval:)` (they tick without the app). Show the
    rest ring only if `restEndsAt` exists.
  - **Sync:** there is a `chunks` count but **no total**. Show "25 chunks" and an indeterminate bar,
    **not a percentage**, unless a real total exists (Gap).
- **Notifications:** update **only the copy** in the six senders:
  - morning summary (`AppModel.swift` ~1526)
  - Coach brief (`CoachBriefScheduler.swift`)
  - Strain target (`StrainTargetNotifier.swift`)
  - wind-down (`WindDownNudge.swift`)
  - battery (`BatteryNotifier.swift`)
  - illness (`IllnessNotifier.swift`, which keeps its "not a diagnosis" subtitle)

  Use the copy deck in the appendix, filling numbers from the same values each sender already has.
  If a sender lacks a value the copy needs, keep its current wording for that part.
- The long-press custom view needs a **Notification Content Extension**: a new target, a new bundle
  ID and new provisioning. **Ask the owner before doing this**; by default leave it out and list it as
  a follow-up.

### Phase 9: polish and accessibility pass

- Reduce Motion, Dynamic Type up to AX5 (titles wrap, nothing clips), VoiceOver labels for every ring
  and chart, and contrast. Secondary text on cards must stay ≥4.5:1; check `textTertiary`, and
  raise it if needed for body-size text.
- Safe areas, the iOS 26 tab bar minimise-on-scroll (existing `noopTabBarAutoHide`), and the native
  back gesture on every pushed screen.
- Remove dead code only where it is now unreachable **and** not used by macOS. When in doubt, leave
  it.

### Phase 10: verification and handoff

See section 6. Then write the report (section 7).

## 5. Localisation

The repo's i18n gate (`Tools/i18n_audit.py --ci`, CI `i18n-coverage.yml`) requires every new
user-facing string to have entries for the existing locales:
- in `Strand/Resources/Localizable.xcstrings` (app)
- in `StrandiOSWidgets/Localizable.xcstrings` (widgets)

Add translations for all existing locales. Reuse existing keys where the meaning is identical. Run
the audit locally before each commit that adds strings. Keep "Sleep / Recovery / Strain"
terminology consistent with the existing translations.

## 6. Verification for every phase

Run what applies, and paste the results into the commit message or report. AGENTS.md is explicit that
package tests alone do not validate app-target code.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash Tools/personal/ios.sh build   # NOOPiOS + widgets, simulator
cd Packages/StrandDesign && swift build && swift test                                           # components/tokens
xcodegen generate && xcodebuild -project Strand.xcodeproj -scheme Strand -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build   # shared sources still compile for macOS
xcodebuild -project Strand.xcodeproj -scheme Strand -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:StrandTests   # existing app tests, unchanged behaviour
python3 Tools/i18n_audit.py --ci
python3 Tools/doc_comment_lint.py
python3 -m unittest discover -s Tools          # some suites read product source
```

- Run `xcodegen generate` after adding or removing files. `project.yml` is authoritative; never commit
  `Strand.xcodeproj/`.
- **`doc_comment_lint` reports at the wrong line on purpose.** If it fails after you insert a
  declaration, you probably split a neighbour's doc comment from its declaration (AGENTS.md).
- **Visual check:**
  - install on an iPhone simulator and screenshot each migrated screen, in a populated state and an
    empty state
  - compare side by side with the mockup (open the HTML with `?static=1`)
  - do this for Today, Recovery, Sleep, Training, Health, Profile, the widgets and the Dynamic Island
    at minimum
- **Do not** install on the owner's phone or touch signing. The owner installs with
  `Tools/personal/ios.sh` and their local identity.

## 7. Commits, branch and final report

- One phase per commit or a few small commits. Messages in English, describing what and why, with
  verification output. Push `personal/redesign` to `origin` at the end of each phase:
  `git push origin refs/heads/personal/redesign:refs/heads/personal/redesign`. Do not open a PR to
  `main`.
- Final report (`docs/personal/REDESIGN-REPORT.md`, committed):
  - what changed per screen
  - **Gaps**: mockup elements omitted for lack of data, with the mockup ID
  - behaviour you consciously preserved
  - settings hidden or added
  - test and build results
  - before/after simulator screenshot paths, without personal data (simulators only)
  - anything that needs on-device checking: widget refresh, Live Activity on a real strap, haptics

## 8. Decisions already made (do not re-open)

- Tabs are Today, Sleep, Training, Health, plus a Coach circle; Profile replaces More.
- The redesign is dark-only.
- SF Pro default design, not rounded. In-app numerals are semibold or bold; widget and Live Activity
  numerals are Light.
- There are no textured, 3D, "liquid" or glow-as-decoration elements, and no uppercase overline
  section labels.
- Charts are smooth lines with gradient fills and **no horizontal lines** across the plot.
- The ambient background is driven by scores, with an intensity setting.
- Skeleton loaders and spring motion are used everywhere, and rings refill on every load.
- Health-workout summaries and full-set lifts are always labelled distinctly.

## 9. Open questions (defaults chosen; note them in the report rather than blocking)

| Question | Default |
|---|---|
| A notification content extension for the long-press view? | Not built; ask the owner |
| A new app icon (notifications currently use the existing icon)? | Out of scope |
| Accent and chart-colour settings with the redesign on | Hidden on iOS |
| A sessions-per-week goal on Training | Shown only if a goal setting already exists |
| Sync percentage in the Dynamic Island | Only with a real total |

## Appendix A: notification copy deck

| Sender | Title | Body |
|---|---|---|
| Morning summary | `Recovered · 68%` (band word plus score; "Adequate"/"Low" for other bands) | `HRV is up and you slept 7h 42m. Good day to push: aim for Strain 12–15.` Build from the same facts the current body uses. Drop any clause whose value is missing |
| Coach brief | `Your morning brief` | first sentence(s) of the brief, as now |
| Strain target | `Strain target reached` | `13.2 after Pull day. Anything more today is extra load for tomorrow.` |
| Wind-down | `Time to wind down` | `Lights low now keeps you on track to wake at 6:45, well rested.` |
| Battery | `Strap battery at 15%` | `About 12 hours left. Charge it before bed so tonight's sleep is recorded.` Omit the hours clause if no estimate exists |
| Illness | `Early warning: take it easy` (unchanged) | subtitle `On-device estimate, not a diagnosis`; body names the signals that are actually elevated, e.g. `Resting heart rate and skin temperature have been up for two nights.` |

Titles state the fact; bodies say what to do. No exclamation marks. Every new string needs
translations (section 5).

## Appendix B: screen-to-code map

| Mockup | Existing code to restyle or reuse |
|---|---|
| Today (r2-01), E1, E2, A5 | `Strand/Liquid/LiquidTodayView.swift` (data), `TodayCustomizationSheet.swift`, `KeyMetricPrefs.swift` |
| Recovery (r2-02) | `TodayView.swift` charge detail parts, `Repository` recovery reads |
| A1 Strain | effort/strain detail parts in `TodayView.swift`, `StrainTargetNotifier.swift` (target) |
| Sleep (r2-03) | `SleepView.swift`, `StagesCard.swift`, `StagesVsTypicalCard.swift`, `SleepDebtLedgerCard.swift`, `HoursVsNeededCard.swift` |
| Training (r2-04), B1–B6 | `WorkoutsView.swift`, `WorkoutDetailView.swift`, `LiftLogView.swift`, `LiftSessionDetailSheet.swift`, `WorkoutTextImportSheet.swift`, `LiveWorkoutView.swift`, `ManualWorkoutSheet.swift`, `DataSourcesView.swift` (CSV import) |
| Health (r2-05) | `HealthView.swift`, `VitalSignsSummary.swift`, `SkinTempCardsView.swift` |
| A2, A3 | `MetricExplorerView.swift`, `Strand/Data/MetricCatalog.swift` |
| A4 | `LiveView.swift`, `Strand/Liquid/LiveSessionView.swift` |
| A6, E3 | `DevicesView.swift`, `AddDeviceWizard.swift` |
| C1 | `SmartAlarmView.swift` |
| C2 | `TrendsView.swift` |
| C3 | `StressView.swift` |
| C4 | `BreathingView.swift` |
| C5 | `JournalLogCard.swift` and the journal views |
| C6 | `InsightsHubView.swift`, `InsightsView.swift` |
| D1, D2 | `CoachView.swift`, `CoachSettingsView.swift`, `StrandiOS/App/ChatGPTConnectionView.swift` |
| D3 | `StrandiOS/App/RootTabView.swift` (`moreTab`, `MoreDestination`) |
| D4, D5, D6 | `DataSourcesView.swift`, `SettingsView.swift`, `BackupSyncView.swift` |
| R4-1, R4-2 | `StrandiOSWidgets/NOOPWidget.swift`, `HeartRateWidget.swift`, `StressWidget.swift`, `CoachBriefWidget.swift`, `PersonalMetricsWidgets.swift`, `StrandiOSShared/PersonalWidgetMetrics.swift` |
| R4-2, R4-3, R4-4 | `StrandiOSWidgets/NOOPLiveActivity.swift`, `LiftLiveActivity.swift`, `SyncLiveActivity.swift`, `StrandiOSShared/*ActivityAttributes.swift` |
| R4-5 | the six senders listed in Phase 8 |

## Prompt for the implementing session

> Read `docs/personal/REDESIGN-IMPLEMENTATION.md` and implement it, phase by phase, following
> `AGENTS.md`. Branch as Phase 0 says, commit and push at the end of each phase, and finish with the
> report in section 7. Ask me only where the plan says "Ask the owner".
