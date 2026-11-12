# Round 6 · Cut scorecard (Stage 1: weigh-in and scorecard)

Design source for stage 1 of the health super-app workstream
([ROADMAP](../../docs/personal/superapp/ROADMAP.md), [gate G1](../../docs/personal/superapp/QUALITY-GATES.md)),
reconciled with the stage 1 specification (`docs/personal/superapp/specs/stage-1.md`, on the
`personal/superapp-1-spec` branch). The HTML here is the source of truth; Figma receives an export of it.

**Every value is synthetic.** The frames use the specification's own fixture (§13): "Fixture Person",
phase "Fixture cut" from Mon 6 Jan 2031, target 94.0 kg, band 0.40–1.20% per week, weighed on
Wednesdays, with the fixture's rule values (add 300 kcal, take 250 kcal, slow loss under 0.4 kg for
3 weeks, protein floor 100 g). The generic defaults (§6.3) appear only where the app would show
them: the first-use phase and rules sheet (E1).

## How the numbers are made

`model.js` is a design model of §7 (`CutScorecard.evaluate`) plus the §13 fixture. Each frame is the
fixture on a stated day run through that model, then worded by the presenter in `scorecard.js` with
the §11 strings. No result is typed by hand. The model reproduces all 22 rows of the §13.3 table
(weekly loss, fitted rate and percentage, waist and lift signals, rule states, verdict, reason,
overridden and unevaluated rules, projection) and variants V1, V2, V3, V4, V6 and V12. It is a mockup
aid, not the implementation: it leaves out input validation (§6.5) and has no parity twin.

## Files

| File | Purpose |
|---|---|
| `index.html` | The page. Loads `../system/noop.css`, `scorecard.css`, `../system/noop.js`, `model.js`, `scorecard.js`. |
| `model.js` | Design model of §7 and the §13 fixture. Pure; also loadable in Node. |
| `scorecard.js` | Presenter (§11 strings), frame builders, the weekly chart, the frame list. |
| `scorecard.css` | Local styles. `design/system/noop.css` and `noop.js` are not edited. |

## View and export

```bash
python3 design/tools/serve.py                 # http://localhost:8765/round6-scorecard/index.html
#   ?static=1   settled state, no motion      ?only=B   only frames whose id starts with B
python3 design/tools/serve.py --export round6-scorecard/index.html --name r6-frames.json
```

The export writes `design/export/r6-frames.json` (git-ignored) and checks it. With the plain server
running, the Figma plugin command **Import round 6 frames** reads it onto the page
**Round 6 · Scorecard (Stage 1)**.

## Frames (61)

Each frame is named `R6 / <id> <title>`; that is also its Figma layer name.

### A · Entry card in Your cards (§10.1)
- **A1 Today card · verdict available** — value card: current weight, caption "Change nothing". Week 4. The existing Weight tile beside it shows the same value and "Lab Book" (§10.8).
- **A2 Today card · every state** — loading, no cut phase, no readings, one reading, fewer readings than the rules need, weigh-in due, overdue, lifts unknown with the verdict withheld, target reached, weight rising, an "add" verdict, a past day selected.
- **A3 Today card · AX5** — one column; value, caption and long verdict wrap.
- **A4 Today card · wider card with the four signals** — a proposal that is not in the specification (decision 3).

### B · Scorecard screen (§10.2)
- **B1 steady loss in the band** — week 4; rule 1 fired; four signals met.
- **B2 no readings** — "Log a weigh-in to begin"; curves area "Not measured yet"; Log weigh-in is primary.
- **B3 no cut phase** — V4; explanation and "Set up phase"; curves and fitted rate still show.
- **B4 phase not started** — "Your phase starts Mon 3 Feb"; curves; no verdict.
- **B5 one reading** — week 1; "Change nothing / None of your change rules fired" with rules 1 and 3 not checked.
- **B6 one reading, no lift sessions** — V2; "Not enough to judge yet", all three rules not checked.
- **B7 fewer readings than a rule needs** — V5 without lifts; slow loss at "2 of 3 weeks".
- **B8 protein below the floor** — week 5; "Below your floor on 4 days".
- **B9 protein logging incomplete** — week 6; "Not enough days logged".
- **B10 recomposition week** — week 7; rule 1 with rule 3 overridden.
- **B11 reduce carbohydrate** — week 9.
- **B12 weigh-in due, last verdict stands** — week 10 before a reading; banner and primary Log weigh-in.
- **B13 after a missed week** — week 11; curves break at the missed week; rule 3 "a week has no weigh-in".
- **B14 no rule fired, lifts not known** — week 13; §7.7 line 4b.
- **B15 verdict withheld** — week 15; line 3a; "No verdict this week".
- **B16 reduce carbohydrate, lifts rule not checked** — week 17; line 3b.
- **B17 add calories, slow loss overridden** — week 19.
- **B18 weight rising** — week 20; rate shown as a gain; "No date while weight is not falling".
- **B19 target reached** — week 21; "Target reached" leads, verdict below.
- **B20 weigh-in overdue** — V3; "Last weigh-in Wed 5 Mar"; signals unknown.
- **B21 no target set, no protein floor** — V6 with the floor empty.
- **B22 projection beyond the horizon** — V12; "More than 104 weeks at this rate".
- **B23 projected day passed** — "Log a weigh-in to check the target".
- **B24 rules need attention** — stored rules failed validation; link to the rules sheet; no verdict.
- **B25 pounds and inches** — week 4 in lb and in.
- **B26 loading skeleton**.
- **B27 AX5** — week 17; everything stacks.

### C · Weigh-in sheet (§10.3)
- **C1 step 1, first use** — empty focused field; Next disabled.
- **C2 step 1, last weight prefilled** — selected for overtyping.
- **C3 out of range** — names the bound; Next disabled.
- **C4 backdating** — calendar; shows the week the reading falls in.
- **C5 already logged this week** — "You logged 97.6 kg on Wed 29 Jan. This reading will represent the week."
- **C6 step 2 waist** — prefilled; Save; Skip.
- **C7 saving** — buttons disabled.
- **C8 save failed** — values intact; Try again.
- **C9 pounds, comma decimal separator**.
- **C10 AX5** — title, date and field stack.

### D · History (§10.4)
- **D1 list, with other sources** — newest first; dot on the reading that represents its week; an Apple Health row (read-only), a CSV import row; "not measured" waist; footnote for an unrecognised unit.
- **D2 swipe to edit or delete**.
- **D3 delete asks once**.
- **D4 empty** — "No weigh-ins yet".
- **D5 loading**.

### E · Phase and rules sheet (§10.5)
- **E1 first use, generic defaults** — band 0.25–0.75%; every rule value at its generic default; no target; no protein floor.
- **E2 editing** — the fixture's values; "Start a new phase".
- **E3 a value that cannot be saved** — band low above high; Save disabled.
- **E4 new phase of kind Other** — no target, band or rules.

### F · Settings and the notification (§10.6, §10.7, §10.10)
- **F1 scorecard on, reminder off**.
- **F2 reminder on, with the notification** — Saturday 08:00, the stored defaults.
- **F3 notifications denied**.
- **F4 body metrics rows** — with a dated reading (value, source, date, Log weigh-in) and without (stepper).

### P · Placement (Q2 / S1)
- **P1.1–P1.4** — the specification's recommendation: a Today card the owner adds (P1.1), the editor where it sits outside the default selection (P1.2), a row in the Health tab (P1.3), the pushed screen (P1.4).
- **P2.1, P2.2** — a Body section in the Health tab with a full-width card; the scorecard under Health.
- **P3.1** — its own tab.

## Decisions for the owner

1. **Placement: P1, P2 or P3.** P1 is the specification's recommendation and this design's. P3 is
   not recommended: with Coach on it is the sixth destination, so it overflows into "More" or
   replaces a tab; the frame draws the kindest case.
2. **Signal colours.** Met = Recovery green, not met = Recovery mid amber, unknown = neutral grey
   with the dashed ring. Red is kept for Delete and invalid entries. Rule rows (fired, not fired,
   could not check) are deliberately neutral: a rule firing is not a good or bad week.
3. **The card: plain value card (A1, as specified) or the wider card with the four signals (A4).**
4. **Lift signal (S2–S4).** Drawn as specified: unknown without sessions in the compared days; the
   verdict is withheld in the 3a case (B15) and names the unchecked rule in 3b and 4b (B16, B14).
5. **Neutral curves and card header.** Weight and waist have no semantic colour in the palette.
6. **Wording questions.** The §11 strings are used as written. Proposed alternatives, for the owner:
   - "Your rule: take 250 kcal from carbohydrate" is long as a 12pt card caption and wraps to three
     lines as an AX5 title. Proposed card caption: "Take 250 kcal from carbs".
   - "Loss was under %@ per week for %lld weeks." The count is drawn as the consecutive run (5, then
     8 weeks in B11 and B18), not the rule's required 3. If the required count was meant, say so.
   - "Change nothing / None of your change rules fired." with one reading (B5) reads as a judgement
     after a single weigh-in. Proposed second line: "Nothing to act on yet."
   - "%@ per week, %@ of bodyweight" has no form for a gain. A gain is drawn as "Rate of gain" on
     the curve and "Gaining 0.12 kg per week, 0.13% of bodyweight" in the row detail.
   - "Not known: no sessions in these days": the row adds the dates ("26 Mar – 1 Apr") as a detail.
7. **Strings the specification does not give** (all proposals): rule row names ("Lifts holding and
   waist shrinking", "Lifts dropping", "Slow loss", taken from the "Could not check" strings) and
   state words ("Fired", "Not fired", "Could not check"); why a rule is unknown ("lifts not known",
   "waist not known", "the phase is younger than this rule needs", "a week has no weigh-in", "the
   last weigh-in is too old", "no weigh-ins yet"); a signal row while overdue ("No current
   weigh-in") and before any reading ("Not measured yet"); the due banner; the numbers line under
   each signal reason; "Line fitted to n weekly points, weeks of a – b"; every label in the phase
   and rules sheet; sheet validation ("Enter 250 kg or less."); the save-failed and delete texts.
8. **Card caption precedence.** §10.1 lists the states but not which wins. Drawn as: overdue, due,
   one reading, target reached, verdict withheld, building, then the short verdict.

## Notification text (§10.10)

- Title: `Weekly weigh-in`
- Body: `Weight, then waist. It takes under a minute.`

One a week, only with the reminder on (off by default). No measurement, verdict or phase name.

## Where the specification could not be drawn as written

- **Card title.** §10.1 gives value and caption but no title. Drawn as "Scorecard".
- **"Building: n of m weeks."** The specification does not say which rule's count. Drawn as the slow
  loss rule's consecutive weeks of its required weeks, shown when the verdict is "Not enough to
  judge yet" and more than one weigh-in exists.
- **Target reached "with the date" (§10.2).** The result carries no first-reached date. The banner
  shows the judged reading's weight and day.
- **"More than two years at this rate" (§10.2).** §11's string is used instead: "More than 104 weeks
  at this rate".
- **Rule rows "n of m weeks".** Rule 1 has no window, so its row has no count. A run longer than
  the window is shown capped ("3 of 3 weeks").
- **No cut phase and phase not started.** The four signal rows still show what §7.2 computes; the
  rule rows are hidden because all three are unknown for the same reason.
- **History rows from other sources** (Apple Health, CSV import) and the unrecognised-unit footnote
  are invented rows outside the §13 fixture, dated before the phase.
- **Reduce Motion** has no frame: it is the settled state every frame already shows (`?static=1`).
- **AX5.** §10 asks for every state at the largest size. Drawn for the card, the scorecard and the
  sheet (A3, B27, C10) only; history, the phase and rules sheet and Settings are not drawn at AX5.
- **§10.8 Today weight row.** Only the Your cards tile is drawn (A1), not the key-metrics row.
- **Not drawn:** step 2 skipped as its own frame (C6 shows Skip and its consequence), "Saved"
  (dismisses to the scorecard), an edit that moves a reading to another week, and delete of the only
  reading in a week (both are recomputations with no new layout).

## Token use and proposals

Existing tokens only (`--recovery`, `--rec-mid`, `--rec-low`, `--t1`/`--t2`, card and separator
tokens; `NoopTheme` equivalents). Named proposals:

1. **`--t3a: #8A8A93`** (local). Mirrors the app's `NoopTheme.textTertiary`; `noop.css` `--t3`
   (`#5F5F67`) is too faint for words. Add it to `noop.css` or correct `--t3`.
2. **`--sig-met`, `--sig-not`, `--sig-unk`** (local aliases). Proposal: one `SignalState` colour
   mapping in `NoopTheme`. No new colour values.
3. **Local icons** `cal`, `trash`, `pencil`; SF Symbols in the app.
4. **Local components** to build from existing tokens: the weekly chart (line, gradient area, weekly
   points, a break at a missed week), signal glyph, rule dot, skeleton block, 64pt numeric entry.

## Rule check and exceptions

Checked per frame: black canvas and translucent cards; colour only for signal state, existing metric
tints on neighbouring tiles, Delete and invalid entries; no chart rules, bands or target lines (the
round's earlier time-axis target tick is removed; the target is a number in the projection row);
ambient glow sized by the count of met and not met signals and absent when all are unknown; no
streaks, prompts or warnings; missing values read "—", "not measured", "Unknown" or "Not measured
yet", never 0; the projection is labelled Estimate.

- The gradient fill ends on the chart's baseline, where the axis labels sit. It is the time axis.
- A missed week is an open ring on the time axis; the line breaks there.
- List separators inside cards are the existing hairline.
- Toggles and the editor's add mark use the existing green; the remove mark and Delete use red.
- The keypad is a drawing of the system decimal pad.
- AX5 sizes follow round 5's scale (about 2× body), not exact iOS point sizes.
