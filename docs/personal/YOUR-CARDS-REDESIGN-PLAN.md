# Your Cards on the redesigned Today: design and implementation plan

Status: design proposal and implementation-ready plan, written 29 October 2026. Nothing here is
implemented yet. The visual reference is the mockup
[`design/round5/your-cards.html`](../../design/round5/your-cards.html) (frames YC1–YC8; open it through
any static server, or add `?static=1` to skip the load animation). The same frames are on the Figma page
"Round 5 · Your cards" (file `pZiuw8RGJXIDdDSHXnA6O6`). This plan is self-contained: an implementer needs
it, the mockup, and the repository.

Read first: [AGENTS.md](../../AGENTS.md), [CONTEXT.md](CONTEXT.md),
[REDESIGN-REPORT.md](REDESIGN-REPORT.md), [REDESIGN-IMPLEMENTATION.md](REDESIGN-IMPLEMENTATION.md),
[SPACING-ALIGNMENT-PLAN.md](SPACING-ALIGNMENT-PLAN.md) (section titles on the 16pt gutter; Your Cards
inherits it through `NoopSectionHeader`).

---

## 0. Before you start: the working tree is not clean

The owner's checkout `/Users/cyrilbhau/Documents/Noop/noop-fork` (branch `personal/iphone-baseline`)
carries substantial **uncommitted, unrelated work**: Health and steps-source changes, widgets, device and
sync changes, strap-steps repair, backfill idle policy, Android twins. Several files this plan touches
are in that set:

- `StrandiOS/Redesign/RedesignTodayView.swift`: adds `showStepSources` and makes the Key metrics Steps
  row open `PersonalStepSourcesView` (an untracked new file) instead of pushing a route. It also adds a
  "No step data for this day" subtitle.
- `Strand/Liquid/LiquidTodayView.swift`: in `TodayDayModel`, the `steps` spark now follows measured
  strap → Apple Health precedence per day.

Rules: do not reset, stash, overwrite, reformat or commit that work. Make **additive** edits to those
files, keep your changes in separate hunks, and stage only your own hunks (`git add -p`) when the owner
asks for a commit. If a step below conflicts with the uncommitted work, the uncommitted behaviour wins
and the step adapts. In particular, the **Steps** tile must use whatever the Key metrics Steps row does
at implementation time (today: open `PersonalStepSourcesView`).

---

## 1. Recommendation in one paragraph

Render Your Cards in the redesigned Today as a **two-column grid of compact tiles** under a standard
`NoopSectionHeader("Your cards", linkTitle: "Edit")`, in the user's saved order, at the section's saved
position. Each **metric tile** shows four things:

- icon and title in the metric's colour;
- one number with its unit;
- one honest caption: the source, the freshness, or why there is no number;
- a chevron when the tile is tappable.

Each **shortcut tile** (Coupled view, Coach) shows its title and a one-line description, and never a
number. At accessibility sizes the grid becomes one column.

Values come from the **same `TodayDayModel` the screen already loads**, through one new pure resolver
that the Key metrics rows also adopt for the metrics both sections can show. Your Cards and Key metrics
therefore cannot disagree about a number.

The customization flow gains a one-line purpose under each of the three card sections, and the Your
cards editor gains four aids:

- an "Also in Key metrics" note on duplicates;
- an explicit note on cards hidden by a feature gate;
- a footer showing where the section sits on Today, with a link back to reorder;
- a banner when the section itself is hidden.

### Why this design

- **Three sections, three shapes.** Key metrics is rows with trend lines, Your cards is a tile grid, and
  Added cards is full-width mirrored cards. The owner's confusion ("I added cards under Added Cards") came
  from three similar-sounding lists with no visible difference. Shape plus a purpose line fixes that
  without renaming any stored key.
- **Tiles suit what Your Cards holds.** Several of its metrics update weekly (fitness age, VO₂ max,
  vitality) or have no meaningful daily trend line here (stress, hydration, the 30-day average). A row
  with a sparkline would imply a series that is not shown. A tile with "as of 26 Oct" is honest.
- **Density.** Sixteen cards make eight tile rows, about 960pt. As full-width rows they would be about
  1,150pt with weaker scanning.
- **Matches the redesign.** The Health tab already uses two-column tiles (`.tile`, `--r-tile` 20).
  Apple Health's summary uses the same pattern.
- **No second loader.** Everything except the 30-day average is already on `TodayDayModel`. The 30-day
  average reuses the existing `RollingStepsAverage` resolution, keyed by the selected day.

---

## 2. Current state (verified 29 October 2026 against the working tree)

| Fact | Where |
|---|---|
| Redesigned Today renders `.yourCards` as `EmptyView()`, so the selection saves but never shows. **This is the bug.** | `RedesignTodayView.sectionView`, the `case .synthesis, .liveSession, .recoveryVitals, .yourCards:` arm |
| The Edit entry point already exists: `TodayCustomizationDestination.yourCards` opens `DashboardCardsCustomizationPage`. | `TodayCustomizationSheet.swift` |
| Prefs: `today.dashboardCards` (JSON `[String]`, order matters, empty ⇒ `DashboardCard.defaultSelection` = stress, fitnessAge, vitality, hrv, restingHr). It rides `.noopbak`; ids are byte-identical to Android. | `DashboardCards.swift` (`DashboardCardPrefs`) |
| Section order and visibility: `today.sectionOrder` and `today.hiddenSections`. | `TodayLayoutPrefs.swift` |
| Liquid Today renders Your cards with per-card resolvers inline in the view (`liquidCard(for:)`). Hydration and Coach are filtered at render (`hydrationEnabled`, `noop.coachEnabled`) and keep their saved position. | `LiquidTodayView.swift` ~760–960 |
| `TodayDayModel` (bottom of `LiquidTodayView.swift`) is the shared loader. It already publishes everything the cards need except per-day points for the "latest" metrics and the 30-day average. | `TodayDayModel.load` |
| `fitnessAge`, `vo2max` and `vitality` are the **history-wide latest** (`exploreSeries(...).last`), not day-scoped. `stress` is `StressModel(days:stored:).score`, scored on the newest day with signal. | `TodayDayModel.load` |
| Hydration total and goal are loaded for the **calendar today only** (`Repository.localDayKey(Date())`), whatever day is selected. | `TodayDayModel.load` |
| Carries (`cachedHrvDay`, `cachedRestingHrDay`, `cachedVitalsDay`, `cachedRespDay`, `cachedSkinTempReadingDay`) are populated **only at offset 0**. | `TodayDayModel.load` |
| The redesign's Key metrics rows already encode the honesty rules: a carried value moves to the sub-line ("Last: 58 ms · Tue"), the WHOOP 4.0 blood-oxygen gate, skin temperature as baseline deviation, and step precedence with "~" for estimates. | `RedesignTodayView.rowContent(_:)` |
| `EditableLayoutDraft.hide` refuses when `visible.count <= 1`, even when the list passes `allowEmpty: true`. | `EditableLayoutDraft.swift`, `EditableLayoutList.swift` |

---

## 3. Design specification

### 3.1 Placement and section header

- Your Cards renders wherever `TodayLayoutPrefs.visibleOrder` puts `.yourCards`. Do not move it
  automatically: saved order is the user's. In the default order it follows Heart rate, after Key
  metrics and Activity.
- Header: `NoopSectionHeader("Your cards", linkTitle: "Edit") { customizationDestination = .yourCards }`
  with `.padding(.horizontal, -NoopTheme.Layout.gutter)`, exactly like Key metrics. Title on the gutter
  (spacing plan), "Edit ›" trailing, 44pt touch target.
- The section is drawn on **every day** (current and past), unlike Added cards, which stays today-only.
  Section 3.6 gives the per-card day rules.
- Entrance: `.noopEntrance(index:)` like its siblings. The grid takes `.noopSkeleton(loading)` while
  `!dayModel.dataLoaded`: a shimmer on each tile, no fake numbers.

### 3.2 Grid

- `LazyVGrid` with two `.flexible(minimum: 0)` columns, spacing `NoopTheme.Layout.cardGap` (12)
  horizontally and vertically, inside the 16pt gutter column. Each tile is about 179pt wide on a
  402pt screen.
- If the count of **rendered** tiles is odd, the last tile spans both columns. Use a `Grid` /
  `GridRow` with `.gridCellColumns(2)`, or chunk into rows of two; pick whichever compiles cleanly
  with the skeleton modifier. It never reorders.
- Rows take the height of their tallest tile. Tiles align their content top-down, with the value
  pushed to a common baseline (`Spacer(minLength: 0)` above the value).
- **Accessibility sizes** (`dynamicTypeSize.isAccessibilitySize`): one column, every tile full-width,
  using the same switch the rings card uses. Nothing truncates. Titles and captions use
  `.fixedSize(horizontal: false, vertical: true)`.

### 3.3 Metric tile anatomy (YC1)

```
┌───────────────────────────┐  NoopTheme.card fill, cardBorder 1pt, tileRadius 20, padding 14
│ ⚡ Stress               › │  SF Symbol + title, .noopFont(.footnote) semibold, tint colour; chevron tertiary
│                           │
│ 1.4 of 3                  │  value .noopFont(.statNumber) (24 semibold, tabular), unit .noopFont(.unit)
│ Moderate                  │  caption .noopFont(.caption), textSecondary (amber when stale)
└───────────────────────────┘  min height 112
```

- New tokens go in `NoopTheme.Layout` (no literals in views): `yourCardMinHeight = 112`,
  `yourCardPadding = rowVerticalPadding` (14) as a reference, and `yourCardIcon = 16`. Reuse
  `tileRadius`, `cardGap`, `card` and `cardBorder`. Typography is `NoopType` only.
- The title stays at most two lines at default sizes and wraps fully at accessibility sizes.
  The value stays on one line: `.minimumScaleFactor` is **not** used; long values are short by
  construction (see the map below).
- **No-number state:** value "—" in `textTertiary`. The unit is dropped (never "—%"). The caption says
  why.
- **Not tappable** (WHOOP 4.0 blood oxygen, past-day hydration): no chevron, no button, no press style.
- **VoiceOver:** one element per tile, `.accessibilityElement(children: .combine)` with an explicit
  label of the form "<title>, <value> <unit spelled>, <caption>" and the `.isButton` trait when
  tappable. The YC5 note has an example.
- **Press:** `.buttonStyle(.noopPress)` (springy scale), as everywhere in the redesign.

### 3.4 Shortcut tile anatomy (Coupled view, Coach)

- Same tile chrome. The header carries the icon in a 28pt rounded tint chip
  (`tint.opacity(0.18)`) to mark it as a shortcut. The description is `.noopFont(.footnote)`,
  textSecondary, up to 4 lines at default size. **No value line and no invented score.**
- Coupled view pushes `TabRoute.coupled`.
- Coach presents `CoachLauncherSheet()` as a **sheet** (`showCoachLauncher` state on
  `RedesignTodayView`), exactly as Liquid does. Opening it makes no provider request. Consent and
  sign-in stay inside the sheet's existing flow.
- Coach description: reuse the existing catalogue string "Ask about your recovery, strain, sleep and
  workouts, grounded in your own numbers." (10 locales). Do **not** use `DashboardCard.coach.subtitle`,
  which still says "charge, effort, rest". Leave that property unchanged for Liquid and macOS.

### 3.5 Section-level states

| State | Behaviour |
|---|---|
| Loading | Header plus skeleton tiles, one per card that will render. |
| Every selected card gated off (for example, only Hydration selected and Hydration off) | Header plus one muted tile, spanning both columns, reading "Nothing to show while Hydration and Coach are off." (or the single-feature variant), with Edit in the header. Never silently empty. |
| Section hidden (`today.hiddenSections` contains `yourCards`) | Nothing renders. Editing cards does not unhide it (section 4.4). |

### 3.6 Current day versus past days

- **Nightly and daily metrics** (HRV, resting HR, respiratory, blood oxygen, skin temperature, sleep,
  steps, calories):
  - On the selected day, show that day's own value.
  - **Only on today**, when the own value is missing, show "—" with the carry caption
    `String(localized: "Last: \(value) · \(TodayView.carriedCaption(...))")`, the same string and
    helper the Key metrics row uses.
  - Past days never carry; the model's carries are nil off offset 0.
- **Weekly or latest metrics** (fitness age, VO₂ max, vitality): show the latest point **on or before**
  the selected day, with caption "as of <d MMM>" (existing "as of %@"). The caption turns amber when
  the point is older than 14 days (two weekly cadences); that threshold is a display rule, not a
  formula. With no point on or before the day: "—", "No data".
- **Stress:** on today, `StressModel.score` with its band word. On a past day, the stress trend point
  for that day (`StressModel.fullTrend`, last point with date ≤ selected day). If that trend uses a
  different scale from `score`, show "—", "No data" on past days instead and record why in a code
  comment. Verify with a test before choosing.
- **30-day step average:** the 30 calendar days ending on the selected day (`RollingStepsAverage`
  already takes `day`).
- **Hydration:** logged for the calendar today only. On a past day: "—", caption "Logged for today
  only" (new string), not tappable. Never show today's total under a past date.
- **Shortcuts** are day-independent.

### 3.7 Default duplication rule (Key metrics vs Your cards)

Twins are cards that both sections can show:

| `DashboardCard` | `KeyMetric` |
|---|---|
| `hrv` | `hrv` |
| `restingHr` | `restingHr` |
| `respiratory` | `respiratory` |
| `steps` | `steps` |
| `bloodOxygen` | `bloodOxygen` |
| `skinTemp` | `skinTemp` |
| `calories` | `calories` |

1. **Implicit default** (`today.dashboardCards` empty or whitespace: the user never saved Your Cards).
   The redesign renders `defaultSelection` **minus** any card whose twin is a rendered Key metrics row,
   where the Key metrics section is visible and the metric is enabled. For a stock install this
   renders Stress, Fitness age and Vitality, because HRV and resting HR are already Key metrics.
2. **Explicit selection** (any saved value): render exactly what was saved, duplicates included.
   Explicit choices are respected.
3. **Editor:** a twin that is currently a rendered Key metrics row gets the subtitle "Also in Key
   metrics" in the Your cards editor. When the editor opens on an implicit default (iOS, redesign on),
   its initial Shown list is the **same deduplicated list** Today rendered, so what you see is what you
   edit. Reset in that editor produces the same deduplicated default. Saving writes it explicitly.
4. Liquid, classic and macOS keep their current behaviour: no dedupe, `defaultSelection` as is. Gate
   the editor changes on `NoopTheme.Keys.redesignEnabled` under `#if os(iOS)`, as
   `TodayCustomizationSheet` already does for the Background section.

### 3.8 Customization flow (YC6–YC8)

- **Root page ("Customize Today")**: each of the three card sections shows its count plus a purpose
  line. New strings:
  - Key metrics: "\(n) shown · readings with a trend line"
  - Your cards: "\(n) shown · metrics and shortcuts you pick"
  - Added cards: "\(n) added · full cards from Sleep, Trends and Stress", or "None added yet · full
    cards from Sleep, Trends and Stress"

  These replace the current count-only subtitles **on iOS with the redesign on**. Elsewhere, keep the
  existing strings.
- **Your cards editor** (`DashboardCardsCustomizationPage`):
  - Shown rows: subtitle priority is the gate note ("Hidden while Hydration is off" / "Hidden while
    Coach is off", amber), then "Also in Key metrics", then the card's description. Shortcut rows say
    "Shortcut · opens Coupled view" / "Shortcut · opens Coach".
  - The Available (hidden) list is grouped with the existing `group:` parameter into "Metrics" (catalogue
    string exists) and "Shortcuts" (new).
  - The Shown footer adds a position line: "Shown on Today after \(sectionTitle)." or "Shown first on
    Today." Next to it, a "Change position" button pops back to the root page (`path.removeLast()`).
    The section title comes from the draft's section order, so it reflects unsaved reordering.
  - When `.yourCards` is in the **draft's** hidden set, a banner at the top says "Hidden on Today" /
    "Your choices here are saved, but the section stays hidden until you show it." with a **Show**
    button. Show moves the section from `sectionDraft.hidden` to the end of `sectionDraft.visible`
    (`EditableLayoutDraft.show`). That edits the draft only: Cancel discards it, Save writes it.
- Titles in the redesign editor and on tiles use sentence case. "Fitness age" and "VO₂ max" are new
  strings; everything else reuses existing keys (section 8). `DashboardCard.title` stays as is for
  Liquid and macOS. The redesign maps through its own `redesignTitle`.

---

## 4. Behaviour contract

### 4.1 Selection and order
Tiles render in `DashboardCardPrefs.decodeEnabled(raw)` order (or the deduplicated implicit default,
section 3.7), filtered only by feature gates. Nothing is sorted by kind.

### 4.2 Section position and visibility
Only the root page moves or hides the section, through `today.sectionOrder` / `today.hiddenSections`.
The per-card editor never changes either, except through the explicit Show button in the banner,
which edits the same draft.

### 4.3 Save, Cancel, Reset
- **Save** writes every draft at once (existing `save()`).
- **Cancel** dismisses without writing (existing). Interactive dismiss is disabled while dirty
  (existing).
- **Reset This Layout** resets only the editor on screen (existing `resetCurrentLayout`). On the Your
  cards page it does not touch section order, visibility, Key metrics or Added cards.

### 4.4 Hidden section
Saving card changes while the section is hidden keeps it hidden. Pin this with a test on the sheet's
save path: draft with `yourCards` hidden plus a changed card list ⇒ `hiddenSectionsRaw` still contains
`yourCards`.

### 4.5 Feature gates
- Hydration renders only while `HydrationStore.enabledKey` is on. Coach renders only while
  `noop.coachEnabled` is on.
- Both stay in the saved list at their position. Turning the feature back on restores them in place.
  The editor never drops them.

### 4.6 Missing data
Every selected card renders a tile. Missing values are "—" plus a reason, never 0 and never a carried
number in the value slot.

### 4.7 Destinations
A tap opens the detail of the value shown, from the source shown:

| Card | Destination |
|---|---|
| Steps | Whatever the Key metrics Steps row does (currently the `PersonalStepSourcesView` sheet). Otherwise `.metricSourced(key: stepsDetailMetric.key, source: stepsDetailMetric.source)`. |
| Calories | `.metricSourced(caloriesDetailMetric)` |
| Blood oxygen, WHOOP 4.0 | Not tappable |
| Sleep, past day | `.metric("sleep_total_min")` (today: `.sleep`) |
| Every other card | Section 5 |

---

## 5. Card-by-card map

Common inputs, all already on screen: `dayModel` (`TodayDayModel`), `displayDay = dayModel.cachedDisplayDay`,
`isToday`, `activeIsWhoop4` (`RedesignTodayView.activeStrapIsWhoop4`), the unit prefs, `effortScale`, and
`hydrationEnabled` / `coachEnabled`. Colours are `NoopTheme` tokens. "Carry" means the today-only
"Last: … · <day>" caption.

| Card (id) | Value · unit | Caption | Source / resolver | Today vs past | Destination | Gate |
|---|---|---|---|---|---|---|
| HRV (`hrv`) | `avgHrv` rounded · "ms" | own: "Last night" today / date on past days; carry: "Last: N ms · day" | `displayDay.avgHrv`, carry `cachedHrvDay` (same as Key metrics row) | carry today only | `.metric("hrv")` | — |
| Resting HR (`restingHr`) | `restingHr` · "bpm" | as HRV | `displayDay.restingHr`, carry `cachedRestingHrDay` | carry today only | `.metric("rhr")` | — |
| Respiratory (`respiratory`) | `respRateBpm` 1 dp · "rpm" | as HRV | `displayDay.respRateBpm`, carry `cachedVitalsDay ?? cachedRespDay` (Key metrics rule) | carry today only | `.metric("resp_rate")` | — |
| Steps (`steps`) | count, "~" prefix when estimated | "Strap" / "Apple Health" / "Estimated from strap" / "No step data for this day" | `dayModel.stepCount`, `stepsDetailMetric`, `importedStepsDay` (Key metrics row, working-tree version) | day-scoped | as Key metrics Steps row (section 4.7) | — |
| 30-day step average (`stepsAverage30`) | mean, no decimals | "\(n) of 30 days" (exists) | `RollingStepsAverage.calculate(readings: repo.resolvedSteps(from:to:), ending: selectedDayKey)`, extracted into a shared async helper used by both this tile and `RollingStepsAverageCard` | window ends on the selected day | `.metricSourced(key: "steps", source: MetricCatalog.combinedStepsSource)` | — |
| Stress (`stress`) | score 1 dp · "of 3" ("of %@") | band word: "Low" / "Moderate" / "High" (from `StressBand(score:)`; existing sentence-case strings) | today: `dayModel.stress`; past: new `dayModel.stressPoint(onOrBefore:)` from `StressModel.fullTrend` | section 3.6 | `.stress` | — |
| Fitness age (`fitnessAge`) | `fitnessAgeBoundSymbol` + value · "yrs" | "as of d MMM" (amber after 14 days) | new `dayModel.fitnessAgePoint` (latest ≤ selected day) | latest ≤ day | `.metric("fitness_age")` | — |
| VO₂ max (`vo2max`) | value 1 dp, no unit | "Estimated · as of d MMM" | new `dayModel.vo2maxPoint` | latest ≤ day | `.metric("vo2max_est")` | — |
| Vitality (`vitality`) | value 0 dp | "as of d MMM" | new `dayModel.vitalityPoint` | latest ≤ day | `.metric("vitality")` | — |
| Blood oxygen (`bloodOxygen`) | WHOOP 4.0 / unknown: "—"; else `spo2Pct` 0 dp · "%" | WHOOP 4.0: "Not measured on WHOOP 4.0"; unknown: "Not measured offline"; candidate (experiment on): "strap estimate (unverified)" | identical to Key metrics row gate (`activeIsWhoop4 != false` ⇒ no number); candidate via `spo2CandidateByDay` only when `PuffinExperiment.spo2CandidateDisplayEnabled` | carry today only | gated: none; else `.metric("spo2")` (never `spo2_candidate`) | WHOOP 4.0 gate |
| Skin temperature (`skinTemp`) | signed deviation, `SkinTempDisplay.formatReading(kind: .deviation)` (carries the degree sign) | "Relative to baseline", or carry | `displayDay.skinTempDevC`, carry rows as the Key metrics row; **always the deviation in the redesign** | carry today only | `.metric("skin_temp")` | — |
| Sleep (`sleep`) | `UnitFormatter.nightSleepDurationDisplay(totalSleepMin)` | "Last night" today; date on past days ("Night of %@", new) | `displayDay.totalSleepMin` | day-scoped, no carry | today `.sleep`; past `.metric("sleep_total_min")` | — |
| Calories (`calories`) | `caloriesCount` 0 dp · "kcal" | "Apple Health" when imported, else "Estimated from strap" | `dayModel.caloriesCount`, `caloriesDetailMetric` | day-scoped | `.metricSourced(caloriesDetailMetric)` | — |
| Hydration (`hydration`) | `HydrationGoal.cardValueString(totalML:goalML:)` ("1.4 / 2.5 L"), no separate unit | "Today's fluid" (exists); past: "Logged for today only" | `dayModel.hydrationTotalML`, `hydrationGoalML` | today only (section 3.6) | `.hydration` (today) | `HydrationStore.enabledKey` |
| Coupled view (`coupled`) | — (shortcut) | "Recovery, strain and sleep in one glance" (exists) | none | any day | `.coupled` | — |
| Coach (`coach`) | — (shortcut) | "Ask about your recovery, strain, sleep and workouts, grounded in your own numbers." (exists) | none | any day | sheet `CoachLauncherSheet()` | `noop.coachEnabled` |

Icons: reuse `DashboardCard.icon`. Tints: hrv/spo2/hydration `NoopTheme.hrv`, restingHr `heart`,
respiratory `breath`, steps and 30-day `lift`, stress `stress`, fitnessAge/vo2max `recovery`,
vitality `sleep`, skinTemp/calories `temp`, sleep `sleep`, coupled `recovery`, coach `coach`. Keep them
identical to the redesign's Key metrics row colours where a twin exists.

---

## 6. Architecture

### 6.1 One resolver, two sections

Create `Strand/Data/TodayCardReadout.swift`. It is **shared Apple source**, so it compiles for macOS
and is testable from `StrandTests`. `StrandiOS/` files are not in the macOS test host.

```swift
/// What one Today metric reads on the selected day: value text, unit, caption, provenance and where a tap
/// goes. Pure: built from a snapshot of TodayDayModel's published values, no Repository access.
struct TodayCardReadout: Equatable {
    enum Tint { case hrv, heart, breath, lift, stress, recovery, sleep, temp, coach, muted }
    enum Tap: Equatable { case route(TabRoute), stepSources, coachSheet, none }
    var value: String?          // nil ⇒ render "—" and drop the unit
    var unit: String?
    var caption: String?
    var captionIsStale = false  // amber caption
    var tint: Tint
    var tap: Tap
}

struct TodayCardInputs {        // value snapshot taken from TodayDayModel on the main actor
    var isToday: Bool
    var selectedDayKey: String
    var displayDay: DailyMetric?
    var hrvCarry, restingHrCarry, vitalsCarry, respCarry, skinTempCarry: DailyMetric?
    var stepCount: Double?; var stepsDetail: MetricDescriptor?; var importedStepsDay: Int?
    var caloriesCount: Double?; var caloriesDetail: MetricDescriptor?; var hasImportedKcal: Bool
    var stressToday: Double?; var stressPoint: (day: String, value: Double)?
    var fitnessAgePoint, vo2maxPoint, vitalityPoint: (day: String, value: Double)?
    var hydrationTotalML: Double?; var hydrationGoalML: Int?
    var activeIsWhoop4: Bool?; var spo2Candidate: Double?
    var fahrenheit: Bool; var locale: Locale
}

enum TodayCardResolver {
    static func readout(_ card: DashboardCard, _ inputs: TodayCardInputs) -> TodayCardReadout
    static func readout(_ metric: KeyMetric, _ inputs: TodayCardInputs) -> TodayCardReadout   // twins only
    static func renderList(raw: String, hydrationEnabled: Bool, coachEnabled: Bool,
                           visibleKeyMetrics: [KeyMetric]?) -> [DashboardCard]              // §3.7 + gates
}
```

- Shape of the code: an `Equatable` struct for the result, an input snapshot, and static functions,
  following `TodayLayoutPrefs` and `HostedCard.route`. Names are suggestions; keep the shape.
- Move the **logic** of `RedesignTodayView.rowContent(_:)` for twin metrics into
  `TodayCardResolver.readout(KeyMetric)`. Map it back into `MetricRowContent` in the view, so Key
  metrics renders pixel-identically. That is the "two readouts of one fact must not disagree" defence
  from AGENTS.md: assert **one resolver**, not matching call sites.
- `Tint` maps to `NoopTheme` colours in the iOS view (`StrandiOS/Redesign/YourCardsSection.swift`), so
  the shared file imports no iOS-only colour tokens.

### 6.2 `TodayDayModel` additions

These go in `Strand/Liquid/LiquidTodayView.swift` and are additive only. That file has uncommitted
work; edit it in separate hunks.

- `@Published var fitnessAgePoint`, `vo2maxPoint`, `vitalityPoint: (day: String, value: Double)?`:
  in `load`, the last point of the already-awaited `fitA` / `vo2A` / `vitA` series with
  `day <= selectedDayKey`. **Do not change** the existing `fitnessAge` / `vo2max` / `vitality`
  (Liquid keeps reading them).
- `@Published var stressTrend: [(day: String, value: Double)]`: keep the `StressModel`'s `fullTrend`
  mapped to day keys (it is computed already; also keep its `score` as today). Add
  `func stressPoint(onOrBefore:)`. No second `StressModel` run.
- Nothing else. No new repository reads beyond the existing 30-day-average resolution, which already
  exists in `RollingStepsAverageCard`. Extract that card's `.task` body into
  `RollingStepsAverage.load(repo:day:) async -> RollingStepsAverage?` and call it from both places.

### 6.3 New iOS view

Create `StrandiOS/Redesign/YourCardsSection.swift` with `struct YourCardsSection: View`. It takes:

- the `[DashboardCard]` render list;
- a `TodayCardInputs` snapshot;
- `isAccessibilitySize`, `loading` and `animate`;
- callbacks `onEdit`, `onCoach` and `onStepSources`.

It draws the header, the grid, the tiles and the gated-empty tile. It reads no environment objects
except what NavigationLink needs, and the 30-day tile owns its small `.task(id: "\(day)|\(repo.refreshSeq)")`
via the shared helper.

In `RedesignTodayView`:

- `case .yourCards:` renders `YourCardsSection(...)` with `.noopEntrance(index:)`. Remove `.yourCards`
  from the `EmptyView()` arm and update that arm's comment.
- Add `@AppStorage("noop.coachEnabled") coachEnabled = true` and `@State showCoachLauncher`, plus
  `.sheet(isPresented: $showCoachLauncher) { CoachLauncherSheet() }`.
- The steps tile calls the same action as the Key metrics Steps row (`showStepSources = true` in the
  current working tree).

Run `xcodegen generate` after adding files (sources are globbed, but regenerate anyway). Never commit
`Strand.xcodeproj/`.

### 6.4 Editor changes

The editor lives in `TodayCustomizationSheet.swift` (shared). Gate everything new on
`#if os(iOS)` and `redesignEnabled`:

- Pass `keyMetricDraft.visible`, the section draft and the gate flags into
  `DashboardCardsCustomizationPage`, so subtitles reflect the **draft**.
- Initial and Reset drafts: implement the section 3.7 rule in the sheet's `init` and
  `resetCurrentLayout`. The sheet's `init` must know whether the raw value was implicit (empty).
- Group the Available list into Metrics and Shortcuts: `group: { $0.isShortcut ? shortcuts : metrics }`.
  `DashboardCard.isShortcut` = `self == .coupled || self == .coach`. Add it in `DashboardCards.swift`;
  it is pure and has no Android parity impact because it is not persisted.
- Footer position line, "Change position" button, and the hidden-section banner with its Show button
  that edits `sectionDraft`.
- Root-page purpose lines (section 3.8).

`EditableLayoutList` needs two optional additions with defaults that keep current callers unchanged:
`footer: ((Item) -> …)`, or simply an `extraFooter: AnyView?` for the Shown section, and a
`header: AnyView?` for the banner. Do not fork the list.

---

## 7. Phases

Each phase compiles on its own and gets its own commit when the owner asks for commits.

**Phase 1: resolver and model (shared, testable).**
`TodayCardReadout.swift` (new), the `TodayDayModel` additions, the `RollingStepsAverage.load` helper,
and `DashboardCard.isShortcut`. Tests in `StrandTests/TodayCardResolverTests.swift`. No UI change yet.

**Phase 2: Key metrics adopts the resolver.**
`RedesignTodayView.rowContent` delegates twin metrics to `TodayCardResolver`. Snapshot of output
before and after: identical strings, routes and colours for every `KeyMetric` across today, past-day,
carry, WHOOP 4.0 and unknown-strap inputs. This phase is the regression guard for the next one.

**Phase 3: Your Cards renders (the bug fix).**
`YourCardsSection.swift`, the `RedesignTodayView` wiring, the Coach sheet and coachEnabled, the
gated-empty tile, AX one-column layout, skeleton, VoiceOver labels and the new layout tokens in
`NoopTheme.swift`.

**Phase 4: editor clarity.**
Purpose lines, "Also in Key metrics", gate notes, Metrics/Shortcuts grouping, position footer and
"Change position", the hidden-section banner and Show, and implicit-default dedupe in the editor.

**Phase 5: localisation.**
Add every new string in section 8 to `Strand/Resources/Localizable.xcstrings` with all locales the
catalogue carries (10). Run `python3 Tools/i18n_audit.py --ci` (diff-scoped).

Adjacent fixes (section 9) are separate commits after Phase 3, each optional.

### What stays unchanged

- Analytics and formulas, BLE, storage and schema, migrations, imports, the `.noopbak` format and
  whitelist, Android (no stored value or id changes: `isShortcut` and the redesign titles are not
  persisted), signing, bundle IDs, App Groups, and Coach transport, auth and consent.
- Liquid Today, classic Today and macOS rendering and editor behaviour. Every editor change is behind
  `os(iOS) && redesignEnabled`.
- Preference keys `today.dashboardCards`, `today.sectionOrder`, `today.hiddenSections`,
  `today.keyMetrics` and `today.hostedCards`, their encodings, ids and orders.
- `DashboardCard.title`, `subtitle` and `defaultSelection`, and `TodaySection.defaultOrder`.

---

## 8. Copy deck

Reused, already in the catalogue:

- "Your cards", "Edit", "HRV", "Resting heart rate", "Respiratory rate", "Steps", "30-day step
  average", "Stress", "Vitality", "Blood oxygen", "Skin temperature", "Sleep", "Calories",
  "Hydration", "Coupled view", "Coach", "Metrics", "Last night", "Today's fluid", "as of %@", "of %@",
  "Low", "Moderate", "High", "Not measured on WHOOP 4.0", "Not measured offline", "Relative to
  baseline", "Estimated from strap", "Apple Health", "Strap", "No data", "No step data for this day",
  "%lld of 30 days", "Last: %@ · %@", "strap estimate (unverified)", "Recovery, strain and sleep in
  one glance", "Ask about your recovery, strain, sleep and workouts, grounded in your own numbers."
- Check each string's locale count. "Your cards" and "Edit" showed 9 of 10, so confirm the missing
  locale is the development language rather than a gap.

New, each needing all 10 locales:

| Key | Use |
|---|---|
| "Fitness age" | sentence-case tile/editor title |
| "VO₂ max" | sentence-case tile/editor title |
| "Estimated · as of %@" | VO₂ max caption |
| "Night of %@" | past-day nightly caption |
| "Logged for today only" | past-day hydration |
| "Nothing to show while Hydration and Coach are off." / "…while Hydration is off." / "…while Coach is off." | gated-empty tile |
| "Also in Key metrics" | editor subtitle |
| "Hidden while Hydration is off" / "Hidden while Coach is off" | editor gate note |
| "Shortcut · opens Coupled view" / "Shortcut · opens Coach" | editor subtitle |
| "Shortcuts" | Available group |
| "Shown on Today after %@." / "Shown first on Today." / "Change position" | editor footer |
| "Hidden on Today" / "Your choices here are saved, but the section stays hidden until you show it." / "Show" | banner (check the existing "Show" key's capitalisation first) |
| "%lld shown · readings with a trend line" / "%lld shown · metrics and shortcuts you pick" / "%lld added · full cards from Sleep, Trends and Stress" / "None added yet · full cards from Sleep, Trends and Stress" | root purpose lines |

---

## 9. Adjacent issues: assessment

**Essential to Your Cards:** none of the issues below block it. Your Cards does not depend on them,
and none of them changes Your Cards' behaviour.

| # | Issue | Verdict | Fix | Risk / dependency |
|---|---|---|---|---|
| A1 | Newly added sleep/stress hosted cards show a placeholder until refresh: `TodayDayModel.load` reads `hostedCardsRaw` to decide whether to build `hostedSleepModel` / stress hours, but the redesign's `.task(id:)` key does not include the selection. | **Recommended, same release.** Cheap, and the customization flow is what triggers it. | Add a dependency signature to the task id: `"…-\(hostedNeedsSleep)-\(hostedNeedsStress)"`, computed from `HostedCardPrefs.decodeEnabled(hostedCardsRaw)` (a Sleep-origin card present; `.stressToday` present). Changing the order alone must not reload. Mirror in Liquid only if the owner wants it; Liquid has the same key. | Low. Test: the signature changes on add or remove of a sleep-origin card, and not on reorder. |
| A2 | Added Cards cannot remove its last item: `EditableLayoutDraft.hide` guards `visible.count > 1` even when the list passes `allowEmpty: true`. | **Recommended.** A real bug. | `mutating func hide(_ item:, allowEmpty: Bool = false)` with guard `visible.count > (allowEmpty ? 0 : 1)`. `EditableLayoutList.hide` passes its `allowEmpty`. Default false keeps the others. | Low. Draft unit tests for both modes. |
| A3 | Key metrics ignores its "Today / Trends" (`keyMetricsDetailed`) setting: the redesign always draws sparklines. | **Follow-up.** It is a design decision, not a bug fix: either honour it (compact = no spark, trends = spark with window) or remove the picker in the redesign editor. | Recommend honouring it: `detailed == false` ⇒ no accessory, rows keep alignment. | Touches Key metrics visuals only. |
| A4 | Selected score metrics (Charge/Effort/Rest key metrics) are always filtered out, even when the hero is hidden, and their `rowContent` branch returns blanks. | **Follow-up.** | Filter them only while `.hero` is visible; give them real readouts from the same values the rings use (`restScore`, `chargeDisplay`, `strainStored`) with Sleep / Recovery / Strain titles. Routes: `.sleep`, `RedesignRoute.recovery`, `RedesignRoute.strain`. | Must reuse the ring resolvers to avoid two readouts disagreeing. |
| A5 | Live session, Synthesis and Recovery vitals are skipped or folded into the hero; the root editor still lists them and still names the hero "Charge / Effort / Rest". | **Follow-up.** | In the redesign editor, show Synthesis and Recovery vitals as "Included in Sleep, Recovery & Strain" (non-toggleable info rows) or hide them. Rename the hero row label for the redesign only ("Sleep, Recovery & Strain"). Live session: render the existing `liveSessionStartRow` equivalent or hide the row when `liveSessionsBeta` is off. | Copy changes need translation. Stored ids stay. |

Tradeoff: doing A1 and A2 with Your Cards costs about 30 lines and removes two ways the owner could
conclude "cards don't work" while testing this very feature. A3–A5 change other sections' visuals and
deserve their own review.

---

## 10. Acceptance scenarios

Run with synthetic data (sections 11.3 and 11.4). Unless stated, the redesign is on and the date is
today.

**Selection and order**

1. Fresh install (`today.dashboardCards` unset, Key metrics default visible) ⇒ Your cards shows Stress,
   Fitness age, Vitality in that order. HRV and resting HR are not repeated.
2. Same as 1, but Key metrics hidden ⇒ Stress, Fitness age, Vitality, HRV, Resting HR.
3. Saved `["coach","hrv","stress"]` ⇒ tiles Coach, HRV, Stress in that order. HRV shows even though
   it is a Key metric (explicit choice).
4. Reorder in the editor, then Save ⇒ Today matches the new order immediately, with no relaunch.
5. All 16 selected ⇒ 16 tiles (8 rows); an odd count's last tile spans both columns.

**Section visibility and position**

6. Move Your cards above Key metrics on the root page, Save ⇒ it renders above. Relaunch ⇒ still
   above.
7. Hide Your cards, open its editor from the root, add Calories, Save ⇒ the section stays hidden;
   `today.hiddenSections` still contains `yourCards`; `today.dashboardCards` contains `calories`.
8. Same as 7, but tap Show in the banner before Save ⇒ the section is visible, at the end of the shown
   order. Cancel instead ⇒ nothing changed.
9. Reset on the Your cards page ⇒ only the card draft resets. Section order, Key metrics and Added
   cards drafts are untouched (compare raw values after Save).

**Feature gates**

10. Hydration selected at position 2, Hydration off ⇒ no Hydration tile; the editor shows it at
    position 2 with "Hidden while Hydration is off". Turn Hydration on ⇒ the tile appears at position
    2.
11. Coach selected, Coach master switch off ⇒ no Coach tile and no Coach tab. Back on ⇒ the tile
    returns at its position.
12. Only Hydration selected, Hydration off ⇒ the gated-empty tile with the Hydration message.

**Missing data and honesty**

13. Today with no HRV row, last HRV on Tuesday ⇒ HRV tile "—", caption "Last: 58 ms · Tue". The Key
    metrics HRV row shows the same caption (one resolver).
14. Active strap WHOOP 4.0 ⇒ Blood oxygen tile "—", "Not measured on WHOOP 4.0", not tappable.
    Unknown strap ⇒ "Not measured offline".
15. Skin temperature on any strap ⇒ a signed deviation with "Relative to baseline". Never an absolute
    temperature.
16. Steps from the strap estimate ⇒ "~6,240", "Estimated from strap". Health steps present ⇒ the Health
    value without "~", "Apple Health". Both tiles match the Key metrics Steps row.
17. No stress signal ⇒ "—", "No data". Never "Calibrating" unless the stress model reports calibration.
18. Fitness age last computed 17 days ago ⇒ "as of 12 Oct" in amber.

**Past days**

19. Swipe to Monday ⇒ HRV shows Monday's own value or "—" with no carry. Fitness age shows the
    latest point on or before Monday with its date. Hydration shows "—", "Logged for today only", not
    tappable. The 30-day average is the window ending Monday.
20. Swipe between days ⇒ no tile shows a value from a different day than its caption claims (spot
    check three cards against the Metric Explorer).

**Navigation**

21. Tap each metric tile ⇒ the destination in section 5. Steps behaves exactly like the Key metrics
    Steps row. Calories opens the source it displayed.
22. Tap Coach ⇒ `CoachLauncherSheet` presents as a sheet; no network request is made until the user
    acts in it (see the Coach launcher's existing tests). Tap Coupled view ⇒ pushes `CoupledView`.
23. Back gesture from any destination returns to Today at the same scroll position and selected day.
    Re-tapping the Today tab pops to root (`TabRoute` value pushes).

**Accessibility**

24. AX5 ⇒ one column. No truncation in titles, values or captions. The header Edit stays reachable
    (wraps under the title if needed). VoiceOver reads each tile as one element with a button trait
    when tappable.
25. Reduce Motion on ⇒ no entrance spring or shimmer motion (existing `NoopTheme.Motion` gates).

**Other surfaces unchanged**

26. Redesign off (Liquid): Your cards renders as before; the editor has no purpose lines, no dedupe,
    no banner. macOS: the `Strand` build's Today and editor are unchanged.

---

## 11. Verification

1. **Package and pure tests, no signing.**
   ```bash
   cd Packages/StrandDesign && swift build        # new layout tokens (macOS only)
   ```
2. **macOS-hosted app tests** (`StrandTests` runs only under the `Strand` scheme):
   ```bash
   xcodegen generate
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Strand.xcodeproj \
     -scheme Strand -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
     -only-testing:StrandTests/TodayCardResolverTests -only-testing:StrandTests/TodayLayoutPrefsTests \
     -only-testing:StrandTests/KeyMetricPrefsDecodeTests -only-testing:StrandTests/HostedCardPrefsTests \
     -only-testing:StrandTests/RollingStepsAverageTests
   ```
   `TodayCardResolverTests` is new (add `EditableLayoutDraftTests` too if A2 is taken). The others
   exist and must stay green: `TodayLayoutPrefsTests` already covers `DashboardCardPrefs` and
   `EditableLayoutDraft`. `HydrationGoal` is in `StrandAnalytics` (`swift test` in that package covers
   `cardValueString`). New tests cover:
   - `renderList`: implicit-default dedupe, explicit selections, gates, order;
   - each `DashboardCard` readout across today, past day, carry, missing, the WHOOP 4.0 gate, the
     estimate prefix and latest-on-or-before;
   - Key metrics twin parity: one resolver gives identical output for the twin pair;
   - `hide(allowEmpty:)` (if A2 is taken);
   - the hosted-load signature (if A1 is taken);
   - the save path keeping a hidden section hidden.
3. **iPhone app and widget compile** (unsigned, no personal signing config):
   ```bash
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash Tools/personal/ios.sh check
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash Tools/personal/ios.sh build
   ```
   This builds `NOOPiOS` for the simulator with the widget extension in the graph.
4. **macOS compile for shared changes** (`TodayCustomizationSheet`, `DashboardCards`,
   `EditableLayout*`, `LiquidTodayView`, new `Strand/Data` file):
   ```bash
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Strand.xcodeproj \
     -scheme Strand -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
   ```
5. **Hygiene:** `python3 Tools/doc_comment_lint.py` (insert new declarations above a neighbour's doc
   block, never between it and its declaration), `python3 Tools/i18n_audit.py --ci`, and
   `git diff --check`.
6. **Synthetic simulator review.** Use the existing synthetic/demo data path used for the redesign's
   simulator captures (see `REDESIGN-REPORT.md`). Never the owner's database, and never on the owner's
   phone. Capture:
   - YC1-equivalent default;
   - 16 cards;
   - strap-away/carry;
   - a past day;
   - WHOOP 4.0 blood oxygen;
   - Hydration and Coach gated;
   - AX5;
   - the three editor states.

   Compare against `design/round5/your-cards.html`. Screenshots with personal data stay out of git.
7. **Not covered here:** on-device behaviour with the real strap and real history. The owner confirms
   on the phone after an in-place install with the existing signing identity, per CONTEXT.md. Do not
   uninstall or restore over the database.

---

## 12. Mockup index (`design/round5/your-cards.html`)

| Frame | Shows |
|---|---|
| YC1 | Default Today: Key metrics (rows) above Your cards (tiles); few cards, a shortcut tile |
| YC2 | All 16 cards in saved order; long labels; odd last tile spanning |
| YC3 | Today with the strap away: carried captions, stale weekly value, WHOOP 4.0 gate, no data |
| YC4 | A past day: own-day values, latest-on-or-before, hydration today-only |
| YC5 | AX5: one column, wrapping |
| YC6 | Customize Today root with purpose lines |
| YC7 | Your cards editor: duplicate note, gate note, Metrics/Shortcuts grouping, position footer |
| YC8 | Editing while the section is hidden: banner with Show |

The mockup uses synthetic numbers and the mockup token set (`design/system/noop.css`), which mirrors
`NoopTheme`. Where a pixel value in the mockup and a token in this plan disagree, the token wins.
