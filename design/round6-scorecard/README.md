# Round 6 · Cut scorecard (Stage 1: weigh-in and scorecard)

Design source for stage 1 of the health super-app workstream
([ROADMAP](../../docs/personal/superapp/ROADMAP.md), [gate G1](../../docs/personal/superapp/QUALITY-GATES.md)).
The HTML here is the source of truth; Figma receives an export of it.

**Every value is synthetic.** "Fixture Person" starts a fictional cut at 88.5 kg on Fri 4 Sep 2026
with a target of 80.0 kg. The rule values in the pictures (a 0.4–0.8 kg/week band, a 150 g protein
floor, two-week rule windows, "3 weekly weigh-ins before the rules run") are placeholders chosen for
the drawings. The real parameters and the exact rule wording come from the stage 1 specification.

## Files

| File | Purpose |
|---|---|
| `index.html` | The page. Loads `../system/noop.css`, `scorecard.css`, `../system/noop.js`, `scorecard.js`. |
| `scorecard.js` | Fixture, frame builders, the weekly chart, and the frame list. |
| `scorecard.css` | Local styles. `design/system/noop.css` and `noop.js` are not edited. |

## View and export

```bash
python3 design/tools/serve.py                 # http://localhost:8765/round6-scorecard/index.html
#   ?static=1   settled state, no motion      ?only=B   only frames whose id starts with B
python3 design/tools/serve.py --export round6-scorecard/index.html --name r6-frames.json
```

The second command opens the page headless with `?static=1&export=r6-frames.json`, which calls
`exportSvgFrames('r6-frames.json')`; the server writes `design/export/r6-frames.json` (git-ignored
by a `.gitignore` the server creates inside `design/export/`) and checks it. With the server running,
the Figma plugin command **Import round 6 frames** reads that file onto the page
**Round 6 · Scorecard (Stage 1)**.

## Frames

Each frame is named `R6 / <id> <title>`; that is also its Figma layer name.

### A · Entry point on Today
- **A1 Today card · default** — full-width Your cards tile: verdict, four signals by name, weight, rate, last weigh-in.
- **A2 Today card · first use (no readings)** — no numbers; one button to add the first weigh-in.
- **A3 Today card · weigh-in due this week** — last verdict kept, a neutral "due" line and a Weigh in button.
- **A4 Today card · lift signal unknown** — Lifts shown with the dashed "not measured" ring; "1 rule not evaluated".
- **A5 Today card · other states** — one reading, too few readings, missed week, target reached, weight rising, flat-scale good week, loading.
- **A6 Today card · AX5** — largest text size: one column, sparkline dropped, signals stacked, button wraps.

### B · Scorecard screen
- **B1 Scorecard · default** — phase and target, verdict with the rule that fired, four signals with numbers, weight and waist curves, rate, projection, provenance.
- **B2 Scorecard · first use (no readings)** — empty state; all four signals unknown; no empty charts.
- **B3 Scorecard · one reading** — a single point; rate "—"; verdict Not enough data, 2 more weeks.
- **B4 Scorecard · fewer readings than the rules need** — two readings; signals that need two weeks are unknown; 1 more week.
- **B5 Scorecard · a missed week** — open ring on the time axis for the empty week; the rate says it spans it.
- **B6 Scorecard · target reached** — a neutral banner; projection replaced by "No projection: the target is reached".
- **B7 Scorecard · weight rising** — Reduce carbohydrate with its rule; "No projection: weight is not falling".
- **B8 Scorecard · lift signal unknown** — Hold steady, with the working-weights rule named as not evaluated.
- **B9 Scorecard · flat scale, waist shrinking, lifts climbing** — Hold steady with the explanation; nothing is reduced.
- **B10 Scorecard · loading skeleton** — shimmer blocks in the loaded layout.
- **B11 Scorecard · AX5** — everything stacks; chart axis labels scale; the axis target tick is dropped in favour of the text.

### C · Weigh-in sheet
- **C1 Weigh-in · step 1 weight** — big entry, last value as a grey hint, system decimal keypad, date chip.
- **C2 Weigh-in · step 2 waist** — weight confirmed above; Save, or "Skip waist this week" (stored as not taken, never 0).
- **C3 Weigh-in · backdating** — calendar open; says which week the reading counts for and which reading is the weekly point.
- **C4 Weigh-in · lb and in profile units** — the same step in pounds and inches.
- **C5 Weigh-in · AX5** — full-height sheet, title wraps under Cancel, buttons grow.

### D · History
- **D1 History · list** — by week; weight and waist per entry; "Not taken"; backdated entry; a week with two readings and which one counts.
- **D2 History · swipe to edit or delete** — row actions.
- **D3 History · edit entry** — date, weight, waist, Delete with its consequence stated.

### E · Phase and reminder
- **E1 Phase · reminder off (default)** — name, start date, target weight, expected rate band, reminder toggle off.
- **E2 Phase · reminder on, with the notification** — day, time and the notification as it will appear.

### P · Placement (question Q2)
- **P1.1 / P1.2** — P1: a Today card that pushes the scorecard; the tab bar stays on Today.
- **P2.1 / P2.2 / P2.3** — P2: a Body section in the Health tab; the scorecard under Health; the optional compact Today tile.
- **P3.1** — P3: a fifth "Cut" tab.

## Decisions for the owner

1. **Placement (Q2): P1, P2 or P3.** Recommendation: **P1**, optionally with P2's Body section added
   later as a second door to the same screen. The scorecard is read once a week, right after the
   weigh-in, and Your cards is where the owner already chooses what Today shows. P2 fits if the
   scorecard should sit beside Lab Book as part of a body record. **P3 is not recommended**: a weekly
   screen would hold a permanent daily tab, five tabs plus Coach crowd the bar at larger text sizes,
   and it would be the only tab named after a temporary phase.
2. **Lift signal presentation (Q6).** Drawn as the default: unknown unless imported sessions cover the
   period. The verdict then still reports the rules it could evaluate, carries "1 rule not
   evaluated", names the working-weights rule and offers "Import lift sessions". The alternative, if
   preferred, is for an unknown lift signal to force the verdict to "Not enough data".
3. **Signal colours.** Met = Recovery green, not met = Recovery mid amber, unknown = neutral grey with
   the dashed ring. Amber rather than red for "not met", because a missed signal is information, not
   an alarm; red stays reserved for Delete. Say so if not met should be red (`recoveryLow`).
4. **Neutral curves and card header.** Weight and waist have no semantic colour in the palette, so the
   curves and the card header are drawn in the primary text colour. The alternative is a new "body"
   colour token; none is proposed here.
5. **Protein before stage 3.** Until an intake source exists the protein signal will read "Unknown ·
   No intake source connected" (frames B2–B4). B1 shows it met only to draw the full design.
6. **Which reading counts when a week has two.** Drawn as "the later reading is the weekly point".
   The specification owns this rule; the frames change if it decides otherwise.
7. **Target reached.** Drawn as a neutral banner while the rules keep running. The alternative is to
   end the phase automatically.
8. **Rate sign.** Rates are signed everywhere (−0.50 kg/week is a loss, +0.40 a gain), so one figure
   cannot be read two ways between the card, the signal row and the curve.

## Notification text

One local notification per week, only when the reminder is on (it is off by default), at the chosen
day and time. It is not sent if that week already has a weigh-in and it is never repeated.

- Title: `Weekly weigh-in`
- Body: `Record this week's weight and waist.`

## Token use and proposals

Existing tokens only, with these notes:

| Use | Mockup token | App token |
|---|---|---|
| Signal met | `--recovery` | `NoopTheme.recovery` |
| Signal not met | `--rec-mid` | `NoopTheme.recoveryMid` |
| Signal unknown | dashed ring, white at 34% | `NoopTheme.trackEmpty` pattern, label in `NoopTheme.textTertiary` |
| Delete | `--rec-low` | `NoopTheme.recoveryLow` |
| Curves, card header | `--t1` | `NoopTheme.textPrimary` |

Named proposals:

1. **`--t3a: #8A8A93`** (local to `scorecard.css`). It mirrors the app's existing
   `NoopTheme.textTertiary`; `noop.css` `--t3` is `#5F5F67`, which is too faint for words. Proposal:
   add it to `noop.css`, or correct `--t3` to the app value. No new app token is needed.
2. **`--sig-met`, `--sig-not`, `--sig-unk`** (local aliases of the three tokens above). Proposal: a
   small `SignalState` colour mapping in `NoopTheme` so the three states resolve in one place. No new
   colour values.
3. **Local icons** `tape`, `cal`, `trash`, `pencil` (defined in `scorecard.js`). In the app these are
   SF Symbols; nothing to add to the design system beyond the mockup icon set.
4. **Local components** to build in the app from existing tokens: the weekly chart (`weekChart`: line,
   gradient area, weekly points, axis tick), the signal glyph, the skeleton block (`.skb`, same
   shimmer as `.sk`), the numeric entry (`StrandFont.number(64)`).

## Rule check and exceptions

Checked per frame: black canvas and translucent cards; colour only for signal state, the existing
metric tints on neighbouring tiles, and Delete; no chart rules, bands or target lines; ambient glow on
the scorecard is sized by the count of met (green) and not met (amber) signals and is absent when
everything is unknown; no streaks, prompts or warnings; missing values read "—", "Not taken",
"Unknown" or "Not measured yet", never 0; the projection is labelled Estimate.

Exceptions and things to know:

- The gradient fill ends on the chart's baseline. It fades to transparent there, but the axis labels
  sit on that same line. It is the time axis, not a rule across the chart.
- The time-axis target tick (B1) is a short vertical mark, not a line across the plot. It is drawn only
  when the projected date is close enough to fit; otherwise the projection is text alone.
- List separators inside cards are the existing hairline (`NoopTheme.separator`).
- The reminder toggle uses the existing `.toggle.on` green, the system convention already in the mockups.
- The keypad is a drawing of the system decimal pad, not a custom control.
- AX5 sizes follow round 5's scale (about 2× body), not exact iOS point sizes.
