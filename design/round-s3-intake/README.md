# Round S3 · Protein and intake (Stage 3)

Design source for stage 3 of the health super-app workstream
([ROADMAP](../../docs/personal/superapp/ROADMAP.md), [gate G1](../../docs/personal/superapp/QUALITY-GATES.md)),
drawn from `docs/personal/superapp/specs/stage-3.md` (§10 screens and states, §11 strings, §13 fixture)
and modelled on the approved stage 1 round, `design/round6-scorecard/`. The HTML here is the source of
truth; Figma receives an export of it.

**These frames have not been viewed.** No browser was available when they were written. They were
checked only by running the model, the frame builders and the page scripts under Node (below). That
proves the numbers, the strings, the frame count and names, and that the scripts load together. It
proves nothing about layout, spacing, wrapping or overlap. The orchestrator renders, exports and views
them; expect layout corrections after the first render.

**Every value is synthetic.** The subject is the one Fixture Person of stage 1 §13. Stage 3 adds only
the settings of its own §13.1: calorie range 2400 to 2600 kcal, hard floor 2100 kcal, cutoff 20:00,
"Fixture supplement", the apps "Fixture Food" and "Fixture Other", the preset "Fixture shake".

## How the numbers are made

- `model.js` is a design model of §7.1, §7.2, §7.4, §7.5, §7.6, §8.3, §9.4, §9.5 and the widget
  states of §10.8. The protein floor and the daily protein amounts are not copied: they are read from
  the stage 1 round's model file (`../round6-scorecard/model.js`), so the two rounds cannot disagree.
- Each frame is `scenario({...})`: the person at a stated moment, resolved once and passed down.
- `strings.js` holds every word. `frames.js` turns a scenario into markup using only `t()` (a string),
  `d()` (a model value) and `a()` (an annotation on a states sheet). No result is typed by hand.
- Moments used: **Wed 29 Jan 2031, 15:20** (most frames; Apple Health read at 15:10, or at 11:20 when
  stale), the same day at **20:40** (after the cutoff), **Mon 9 Dec 2030, 15:20** (the §13.2 sample
  day, before any history) and **Wed 12 Feb 2031, 08:10** (stage 1's week 6, which has days with no
  protein figure). Stage 1 gives 120 g as the total for 29 Jan; the 95, 100 and 105 g of §13.6 are
  that day in progress, so no day has two totals.

It is a mockup aid, not the implementation: no input validation (§6.4), fixed zone offsets for the
fixture dates, no parity twin.

## Files

| File | Purpose |
|---|---|
| `index.html` | The page. Loads `../system/noop.css`, `../round6-scorecard/scorecard.css`, `intake.css`, then `../system/noop.js`, `../round6-scorecard/model.js`, `model.js`, `strings.js`, `frames.js`, `intake.js`. |
| `model.js` | Design model and the §13 fixture. Pure; loads in Node. |
| `strings.js` | §11 strings verbatim, proposals, existing strings, iOS system text. Pure. |
| `frames.js` | Presenter and frame builders. Pure (no DOM); loads in Node. |
| `intake.js` | Page runtime: mounts the frames, draws the 28-day chart, the export hook. |
| `intake.css` | Local styles. Nothing under `design/system/` or `design/round6-scorecard/` is edited. |
| `check.js` | `node design/round-s3-intake/check.js` (add `--list` for the frame names). |

Round 6's tiles, cards, rows, sheets, skeletons, AX5 switch and local tokens are **imported** (its
stylesheet is linked). Its small markup helpers are copied into `frames.js` with the same class names.
The widget, Lock Screen and notification styles are copied from the approved round 4 page.

## View and export

```bash
python3 design/tools/serve.py        # http://localhost:8765/round-s3-intake/index.html
#   ?static=1   settled state, no motion      ?only=B   only frames whose id starts with B
python3 design/tools/serve.py --export round-s3-intake/index.html --name s3-frames.json
```

The export writes `design/export/s3-frames.json`. Each frame is named `S3 / <id> <title>`; that is
also its Figma layer name.

## Checks run under Node (no browser)

`node design/round-s3-intake/check.js` passes, 76 frames:

1. **Model against §13**: 37 comparisons. All seven aggregation rows of §13.3 on zone log U, zone
   logs E and W, the seven protein rows and eight energy rows of §13.4, the six cutoff rows of §13.5,
   stage 1's floor and seven days (§13.6), the fresh and stale read times.
2. **Strings against §11**: the specification file is parsed; all 71 quoted §11 strings are in
   `strings.js` verbatim and nothing else is marked as specified.
3. **Frames**: 76 built, names unique and of the form `S3 / <id> <title>`, counts per group as below.
   1,758 text nodes were read: every one is a `strings.js` string, a model value or an annotation.
   No frame contains `undefined`, `NaN`, a `<line>`, a band or a target mark.
4. **Tone and privacy**: no app string contains praise, warning, urging or a health word; no widget
   or notification frame contains calories, a supplement name, an app name or an entry label; the
   notification is exactly "Food cutoff" / "Your cutoff time is now.".
5. **Sources**: `frames.js` passes no typed number to the string functions and types three colours
   only (primary text, white, black).
6. **Page scripts over a stub DOM**: the six scripts run together in page order (this caught one real
   load error, fixed), 76 frames mount with the right names, every class used has a style, and the
   chart draws 22 points in one unbroken run for B1 and breaks at the unmeasured days for B8, with no
   line or rectangle.

## Frames (76)

### A · Protein card in Your cards (§10.1)
- **A1 Today · below the floor** — 95 g, partial ring, "5 g to your floor · 15:10".
- **A2 Today · at the floor** — 100 g, complete ring, "Floor met · 15:10".
- **A3 Today · above the floor** — 105 g, ring stays complete, "+5 g over your floor · 15:10".
- **A4 Today · stale** — figure and ring in the tertiary colour, "Last read 11:20".
- **A5 Card · every state** — the twelve states of §10.1 plus the quick-add time and the CSV caption.
- **A6 Card · AX5** — four states, one column.
- **A7 Your cards editor · adding the card** — "Protein" / "Today against your floor" under More cards.

### B · Intake screen (§10.2)
- **B1 below the floor, calories so far** — the default. Path A, fresh.
- **B2 at the floor**, **B3 above the floor** — the ring completes and the figure keeps counting.
- **B4 loading** — skeletons for the ring and the chart.
- **B5 no source chosen** — the three choices, each with its sentence.
- **B6 source None kept (Path C)** — supplements and a row to the cutoff time only.
- **B7 no floor set** — numbers without a ring, "Set your protein floor".
- **B8 nothing logged today** — empty ring; the chart breaks at stage 1's unmeasured days.
- **B9 calories not measured**, **B10 no calorie range set**, **B11 calories above the range** (day open).
- **B12 a past day, calories in the range**, **B13 a past day, calories below the range**.
- **B14 after the cutoff, calories below the hard floor** — the plain note, one line.
- **B15 calories line, every state** — the eight §13.4 rows plus "No range set".
- **B16 two apps wrote today** — both named, "Choose one".
- **B17 stale** — time in the secondary colour, "Read again".
- **B18 Apple Health could not be read** — last figures kept, the failed attempt's time.
- **B19 Apple Health returned no food entries** — no claim that access was denied.
- **B20 first day, fewer than two days of history** — "More days will appear here".
- **B21 a value from a CSV import** — source named, row to Data Sources.
- **B22 targets need attention** — banner and a way to Settings.
- **B23 entered here (Path B)** — entries list and "Add food".
- **B24 entered here, a restored total** — the "Restored total" row with "Replace".
- **B25 a past day, not measured** — dash, "Not measured".
- **B26 AX5** — ring above the numbers, one column.

### C · Supplement tick (§10.6)
- **C1 every state** — not recorded, ticked, answered "no" in the Journal, a past day, four
  configured, none configured.

### D · Quick-add sheet (§10.3)
- **D1 default, nothing entered** (Save disabled), **D2 preset tapped**, **D3 one amount entered**,
  **D4 invalid amount**, **D5 backdating** (today and seven days), **D6 editing an entry** (with
  Delete entry), **D7 restored total** (Replace), **D8 save failed**, **D9 no presets yet**, **D10 AX5**.

### E · Settings card (§10.5) and reminder rows (§10.7)
- **E1 Intake off** — the switch and one sentence.
- **E2 on, source None** — caption that the card and widget have nothing to show.
- **E3 choosing Apple Health** — HealthKit's sheet for the two types, with the permission sentence.
- **E4 Apple Health, every row** — including "Apps to count".
- **E5 Apple Health not available**, **E6 this build cannot read Apple Health** — the row reverts.
- **E7 range invalid, low above high**, **E8 hard floor above the low end** — marked, nothing saved.
- **E9 protein floor field opened**, **E10 enter whole grams**, **E11 stored floor above the maximum**.
- **E12 Enter here, no supplement configured**, **E13 four supplements** (add row hidden).
- **E14 reminder on, with the notification**, **E15 notifications denied**, **E16 near the wind-down reminder**.
- **E17 AX5**.

### F · The notification (§10.7)
- **F1 at the cutoff time** — Lock Screen, 20:00.
- **F2 delivered silently near the wind-down reminder** — same text, no sound.

### W · Widget (§10.8) — each frame shows medium, small, rectangular and circular
- **W1 below the floor**, **W2 at the floor**, **W3 above the floor**, **W4 no floor set**,
  **W5 nothing logged today**, **W6 stale**, **W7 not set up**, **W8 gallery placeholder**,
  **W9 entered here**.

### O · Options for the owner
- **O1 apps to count, the choice** and **O2 one app counted** — against B16 (both counted).
- **O3 ring in Recovery green at the floor** — not the specification; against B2.
- **O4 the 28-day curve ends yesterday** — against B1.

## Notification text (§10.7), exactly

- Title: `Food cutoff`
- Body: `Your cutoff time is now.`

One a day at most, only with the reminder on (off by default). No amount, floor, judgement or
supplement name. Within 30 minutes of the wind-down reminder it is delivered silently with the same
text. There is no other notification in this stage.

## Decisions for the owner

1. **Path A, B or C (I2).** A = B1 (Apple Health), B = B23 (enter here), C = B6 (supplements and
   cutoff only). The specification's recommendation: A if the food app writes to Health and the owner
   agrees to the wider Health read (G1, G2); otherwise B.
2. **Two apps writing to Health (I4).** Count both (B16, the recommendation) or pick one (O1, O2).
3. **Ring colour.** Neutral and unchanged at the floor (B2, as §7.4 specifies; this round's
   recommendation), or stage 1's "met" green once the floor is met (O3). O3 contradicts the
   specification's "no colour change" and is offered only because stage 1 colours "met" green.
4. **Does the 28-day curve include today?** Drawn with today's running figure as the last point (B1),
   which reads as a low day until the evening. O4 ends the curve yesterday. No recommendation; the
   specification says "the last 28 days".
5. **Caption precedence on the card.** §10.1 lists the states but not which wins. Drawn as: no
   source, past day, read failed with nothing stored, targets unreadable, no floor, not measured,
   stale, then below / at / above.
6. **The switch label and its sentence.** Proposed "Protein and intake" and "Shows protein against
   your floor and calories against your range. Off until you turn it on."
7. **Wording of "From … · read HH:mm".** §10.2 writes it with a lower-case "read"; §11 has only
   "Read %@". Drawn with the §11 string: "From Fixture Food" on the left, "Read 15:10" on the right.
8. **"Gauge with N" on the circular widget.** Drawn as specified: the number inside the ring is the
   grams still to go (5), not the grams eaten. Say so if the eaten figure was meant.
9. **Thousands separators.** Sentences use them ("1,450 kcal so far"), as a localised `%lld` does.
   Settings fields show the digits as typed (2400).
10. **The new widget kind in the gallery while Intake is off (I6, G3)** draws W7. Accept, or drop the
    widget.
11. **To confirm (§15):** the fixture's 100 g, 2400 to 2600 kcal, 2100 kcal and 20:00 are invented
    round values. If any equals a real setting, name the row and it is replaced.

## Proposed strings (not in §11)

| String | Why |
|---|---|
| `Set your protein floor` | §10.2 names this row; §11 has no entry for it |
| `None`, `Enter here` | §10.5 names the three source choices; §11 lists only "Apple Health" |
| `Protein and intake` | the feature switch needs a label; the card title "Intake" is directly above it |
| `Shows protein against your floor and calories against your range. Off until you turn it on.` | §10.5 asks for one sentence beside the switch and gives none |
| `With no source, the card and the widget have nothing to show.` | §10.5 asks for this caption and gives no wording |
| `Apple Health is not available on this device.` | §10.5: the row reverts "and says why". Replace with the Apple Health screen's existing wording at implementation |
| `This build cannot read Apple Health.` | as above, for the entitlement-missing state |
| `The low end is above the high end. Nothing was saved.` | §10.5 only marks the field; a mark with no reason is hard to act on |
| `The hard floor is above the low end. Nothing was saved.` | as above |
| `Enter %@ g or less.` | a stored floor above stage 1's maximum opens marked; follows round 6's "Enter 250 kg or less." |
| `of %lld g` | "grams of floor" beside the figure (screen and medium widget) |
| `%@ g`, `%@ kcal`, `g`, `kcal` | an amount with its unit; a unit beside a figure |
| `Last 28 days` | title of the history chart |
| `At or above your floor`, `Below your floor` | legend for the two point styles |
| `Entries` | title of the Path B entry list |
| `Day`, `Presets` | labels in the quick-add sheet |
| `One notification a day at your cutoff time. It never contains an amount, a floor or a supplement name.` | caption with the reminder on; follows round 6's reminder caption |
| `The reminder is off unless you turn it on. The cutoff time still closes the day for the calories line.` | caption with the reminder off; states §7.5's rule |
| `What it looks like` | approved in round 6; reused above the notification preview |

Used and not proposals: strings already in the app or approved in round 6 ("Today", "Your cards",
"Edit", "Settings", "Cancel", "Save", "Data Sources", "Notifications are off for NOOP", "The reminder
cannot be delivered until they are allowed.", "Open Settings", the editor's card names), and iOS
system text ("Health Access", "Allow “NOOP” to Read:", "Dietary Energy", "Protein", "Allow",
"Don’t Allow", "now", "20m ago"). The system sheet's wording is approximate; iOS draws it.

One §11 string is not drawn: **"Several sources"**. It belongs to the scorecard protein row (§10.4),
which the combined frame set draws.

## Token use and gaps

Existing tokens only. Gaps and proposals:

1. **No colour for intake.** The palette has Sleep, Recovery and Strain. The ring, figures and curve
   use the primary text colour (`--t1`, `NoopTheme.textPrimary`). Proposal: keep intake neutral
   rather than add a token.
2. **`--t3a: #8A8A93`** (round 6's local token, imported). Used for the stale figure and ring and
   for placeholder text. Round 6 already proposes adding it to `noop.css`.
3. **Invalid entry** uses `--rec-low` on the field's value and border, as round 6 does. There is no
   named "invalid" token.
4. **Widget and Lock Screen surfaces** (`.wg`, `.wall`, `.acc`, the notification) are round 4's
   inline styles, copied because they are not in `noop.css`. Proposal: move them to the system file.
5. **Local components to build from existing tokens:** the 28-day chart (line, gradient area, filled
   and open points, a break at an unmeasured day), the tick box, the inline field box, the preset chip.
6. **Local icons** `cal` and `trash` (round 6's drawings); `fork` is used for the card. SF Symbols
   in the app.

## Rule check and exceptions

Checked per frame, by reading the markup and by `check.js`:

- Black canvas and translucent cards on every app screen. The widget and Lock Screen frames sit on
  round 4's wallpaper, as iOS shows them.
- Colour: none for intake. Red only on an invalid entry and on "Delete entry". Green only on
  switches and the editor's add mark (existing), on the Recovery pill and ring of the Today header,
  and in option O3.
- Chart: a smooth line with a gradient fill. No floor line, no range band, no target line. The floor
  is carried by the point style and the legend; the calorie range is words only, with no gauge.
- An unmeasured day breaks the curve and is a quiet open mark on the time axis; it is never zero.
- No ambient glow on the intake screen: there is no score to drive it. The Today frames keep the
  existing score-driven glow.
- Loading is shimmer skeletons (A5, B4).
- Tone: no praise at the floor, no warning below the hard floor, no streak or count of days, no
  prompt to log. "Floor met" is a state, drawn in the same weight and colour as the others.
- Not measured reads "—", "Not measured" or "Nothing logged today". Nothing in this stage is an
  estimate, so no estimate label appears.
- Widgets and the notification carry no calories, supplement, entry label or food app name.
- List separators inside cards are the existing hairline. The keypad is a drawing of the system pad.
- AX5 sizes follow round 6's scale, not exact iOS point sizes.
- The status bar shows each frame's stated time (15:20, 20:40, 08:10) instead of 9:41, so it agrees
  with the read times in the frame.

## Where the specification could not be drawn as written

- **Settings card, Health tab row, scorecard protein row.** §10 says these three are drawn in the
  combined frame set, not in this round. The Settings card is drawn here because this round was asked
  for it; the combined set stays the authority for its position (third, below Coach packet, above
  Body record). The Health tab row (§10.9) and the scorecard row's source caption (§10.4) are not
  drawn here.
- **"Every state needs a frame at accessibility5" (§10).** AX5 is drawn for the card, the intake
  screen, the quick-add sheet and the Settings card (A6, B26, D10, E17), not for every state.
- **Which day the intake screen shows.** §10.2 has no day selector. Past-day frames (B12, B13, B21,
  B24, B25) assume the screen follows the day selected on Today, and show the date under the title.
- **"Not measured today … and the source line" (§10.2).** A day with no row has no read time (§8.3),
  so B8 shows "Apple Health" with no time.
- **Past day on the screen.** §9.5 says a past day shows its closed total "without remaining". Drawn
  as "Day total" with the ring as it ended and no "over" line.
- **Targets unreadable.** §7.5 says the amount is shown alone. B22 shows the amount with no range
  line, since "No range set" would be untrue.
- **Flag-off sentence, source-None caption, the reason a Health choice reverts, range errors.**
  §10.5 describes them without wording. See the proposals.
- **Adding or adopting a supplement.** §10.6 gives the data rule, not a screen. Only the Settings
  rows are drawn. The caption "Supplements listed here are left out of the Coach." is on every frame
  with the rows; a sentence about adopting an existing Journal item (§10.6.1) has no string.
- **Four supplements.** The fixture defines one. C1 and E13 number the fixture name (2 to 4).
- **Presets.** §10.3 shows them in the sheet; §10.5 lists no Settings row to manage them. An add chip
  is drawn in the sheet and nothing in Settings.
- **"A reading with a figure and no read time draws the no-data state" (§10.8).** It is not said
  which state that is. The model treats it as "not set up" (never published); no frame depends on it.
- **Widget gallery placeholder.** Drawn as redacted blocks with no text, as iOS draws a placeholder.
- **Silent delivery (F2)** looks the same as F1; the difference is sound and interruption level.
- **Calories on past days.** Stage 1 states no energy figures. Two closed days carry §13.4 rows
  (28 Jan 2,400, 27 Jan 2,100); other past days would read "Not measured".
- **Path B history.** B23 and B24 reuse stage 1's daily protein amounts as quick-add totals. The
  three-source day of §13.6 is a test fixture and is not drawn.
- **Not drawn:** a day edited at the source (the figure changes at the next read, no marker), the
  flag switched off (surfaces absent), the stored fractional floor (stage 1 reads it whole).
