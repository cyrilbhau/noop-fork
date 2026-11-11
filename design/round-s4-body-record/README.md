# Round S4 · Body record (Stage 4)

Design source for stage 4 of the health super-app workstream, gate G1
([QUALITY-GATES](../../docs/personal/superapp/QUALITY-GATES.md)), built from the stage 4
specification (`docs/personal/superapp/specs/stage-4.md`, §10 states, §11 strings, §13 fixture) and
the cross-stage rulings addendum. The approved stage 1 round (`design/round6-scorecard/`) is the
model: same tokens, same components, same export route.

**The frames have not been viewed.** No browser was available while this round was built. The
model and the frame builders were run under Node and audited there (see "Checks"); layout, wrapping,
clipping and the largest-text frames have not been seen by anyone. The orchestrator renders, exports
and views them next, and anything below about how a frame looks is an intention until then.

**Every value is synthetic.** The one Fixture Person of every stage (stage 1 §13): scans A, B and C
dated on stage 1 weigh-in days (8 Jan, 9 Apr, 28 May 2031) with that day's weight as total mass, the
§13.5 benchmarks and blood results, and the named variants of §13.4. "Today" in the frames is Wed
4 Jun 2031 unless a frame's note says otherwise.

## How the numbers are made

`model.js` is a design model of the specification: the field table and ranges (§7.7), the unit
table (§7.2), `displayString`, `quantize` and `compare` (§6.3, §7.3), `derive` (§7.4), `mismatches`
(§7.5), scan order and unreadable or conflicting keys (§7.6), and the §13 fixture. `frames.js` runs
the fixture, or one named variant, through it and words the result. The scan sheet's messages, its
Save state and the weigh-in line are worked out from what is "typed", not set per frame. No figure is
typed by hand; the only literals are the fixture itself and the variant inputs §13.4 names.

It is a mockup aid, not the implementation, and has no parity twin. The weigh-in line (H8) uses a
small stand-in for stage 1's ruling R44; the app asks the resolver.

## Files

| File | Purpose |
|---|---|
| `index.html` | The page. Loads `../system/noop.css`, `body-record.css`, `../system/noop.js`, `model.js`, `frames.js`. |
| `model.js` | Design model and fixture. Pure; one global (`S4`); loadable in Node. |
| `frames.js` | Wording, frame builders and the frame list as pure strings (one global, `S4FRAMES`); the DOM part at the end runs only in a browser. |
| `body-record.css` | Round 6's `scorecard.css` copied unchanged, then this round's styles. `design/system/` is not edited. |
| `check.js` | The Node checks. |

## View and export

```bash
python3 design/tools/serve.py                 # http://localhost:8765/round-s4-body-record/index.html
#   ?static=1   settled state, no motion      ?only=J   only frames whose id starts with J
python3 design/tools/serve.py --export round-s4-body-record/index.html --name s4-frames.json
node design/round-s4-body-record/check.js --list
```

The page calls `exportSvgFrames` itself when it sees `?static=1&export=s4-frames.json`, as round 6
does. Each frame is named `S4 / <id> <title>`; that is also its Figma layer name.

## Frames (72)

### G · Body record screen (§10.1)
- **G1 loading** — skeleton in the loaded layout.
- **G2 nothing recorded** — "No scans yet" and "No benchmarks yet", each with its add button; the row to Lab Book.
- **G3 one scan** — scan A's card and "Add a second scan to compare".
- **G4 two or more scans** — the latest card (scan C), "Compare with Wed 9 Apr 2031", the three scans newest first, the three benchmarks.
- **G5 a scan with unreadable rows** — variant V9 on scan A: fat mass is absent from the card, with the line.
- **G5b a scan with a conflicting key** — variant V16: fat mass is not shown as a number, with the line.
- **G6 an imported scan** — variant V10: "Imported from CSV".
- **G7 benchmarks** — the two with several readings: latest value, date, change since the previous and the first reading.
- **G8 a benchmark with one reading** — the custom benchmark; no change line.
- **G9 store could not be opened** — the one sentence and nothing else.
- **G10 largest text size** — G4 and G7 in one frame, since they are one screen.

### H · Scan sheet (§10.2)
- **H1 new, empty** — date, kg / lb control, the five sections and the note, Save disabled.
- **H2 filled, valid** — scan A as printed, Save enabled; the sign toggle on T-score and Z-score.
- **H3 a field in another unit** — V6: total typed in pounds, "Stored as 100.0 kg."; bone mineral content typed in grams.
- **H4 a field out of range** — the range message in red, Save disabled.
- **H5 not a number** — "Use digits and one decimal separator."
- **H6 figures that do not add up** — V3: one neutral line under Whole body; Save stays enabled.
- **H7 only the total mass entered** — the line, Save disabled.
- **H8 a weigh-in in the chosen day's week** — the neutral line under Total mass.
- **H9 editing** — prefilled, Save and Delete.
- **H10 editing, day already holds a scan** — V12: "Another scan is already recorded at that time."
- **H11 saving** — controls dimmed.
- **H12 save failed** — the message; entries intact.
- **H13 delete confirmation** — the sentence, Delete, Cancel.
- **H14 largest text size** — H2.

### I · Scan detail (§10.3)
- **I1 a full scan** — scan A: five sections, the derived block, the note, Edit.
- **I2 a sparse scan** — scan C: only what was entered; absent sections are absent.
- **I3 derived figure not available** — "Not available. Enter arms and legs lean mass."
- **I4 derived figure from the two sides** — "From left and right arm."
- **I5 unreadable rows** — the line, naming the field.
- **I5b conflicting keys** — the line, naming the field; no Edit; Open Lab Book and Delete.
- **I6 imported scan** — no Edit, no Delete; the sentence and Open Lab Book.
- **I7 the scan no longer exists** — the Body record screen the owner lands on.
- **I8 largest text size** — I1.

### J · Scan comparison (§10.4)
- **J1 two scans** — A and B: the whole table of §13.3.
- **J2 a marker only in the earlier scan** — B and C (the default, the two newest).
- **J3 a marker only in the later scan** — A and B at Fat distribution.
- **J4 a marker in neither** — A and C: the row is absent.
- **J5 no change** — B and C at Whole body.
- **J6 one scan only** — the scan's values and the sentence.
- **J7 no scans** — "No scans yet" and the add button.
- **J8 the same scan cannot be chosen twice** — the Earlier menu, open.
- **J9 scans entered out of order** — identical to J1.
- **J10 a derived figure in one scan only** — B and C at the derived rows.
- **J10b a field unreadable in one scan** — V9: "not entered" in that column, the line under the table.
- **J11 largest text size** — J1 as stacked rows.

### K · Benchmarks (§10.5)
- **K1 sheet, new** — the eight benchmarks, then "Custom benchmark"; value, date and time, condition.
- **K2 sheet, a timed benchmark** — seconds, with the hint for minutes and seconds.
- **K3 sheet, custom** — name and a unit from reps, s, kg.
- **K4 sheet, invalid value** — "Enter a whole number."
- **K5 detail, several readings** — newest first, with the note and the change against the previous reading; delete on each.
- **K6 detail, one reading** — "One reading so far."
- **K7 delete confirmation** — "Delete this reading?"
- **K8 largest text size** — K5.

### L · Lab Book editor, report units (§10.6)
- **L1 a marker with several options** — Vitamin B12: ng/L, pg/mL, pmol/L.
- **L2 typed in a unit that is not the stored one** — LDL in mg/dL: "Stored as 2.59 mmol/L."
- **L2 HbA1c typed in percent, formula shown** — "Stored as 37 mmol/mol." and the formula.
- **L3 an identity option** — ferritin in ng/mL: "Same number, stored as µg/L."
- **L4 not a number** — Save disabled.
- **L5 after Save and add another** — the marker list, the date kept, "Saved LDL cholesterol."
- **L6 history row of an annotated reading** — "37 mmol/mol", then "Entered as 5.5 %".
- **L7 flag off** — the editor as it is today.

### M · Lab Book lists
- **M1 Imaging and Custom** — the scan figures as cards under "Imaging", the benchmarks under "Custom".

### W · Weigh-in history (§10.7)
- **W1 a scan row, body record on** — "Not the weekly point · Lab Book · body scan"; opens the scan.
- **W2 a scan row, body record off** — an ordinary Lab Book row.

### P · Health row and Settings card (§10.1, §10.8)
- **P1 Health row, with scans** — "Body record · Last scan Wed 28 May 2031".
- **P2 Health row, no scans** — "No scans yet".
- **P3 Settings card, both off** — the default.
- **P4 Settings card, both on**.

### O · Options
- **O7** — figures that do not add up block Save (the alternative to H6).
- **O9** — history row with the typed unit first (the alternative to L6).
- **O13** — one switch in Settings (the alternative to P3).

## Decisions for the owner

1. **Should figures that do not add up block Save?** (O7.) Recommended: no (H6). Alternative: O7.
2. **Lab Book history: stored unit first, or the typed unit first?** (O9.) Recommended: stored first
   (L6). Alternative: O9.
3. **Two switches or one?** (O13.) Recommended: two, report units first (P3). Alternative: O13.
4. **The two lists (O11).** H1 shows every scan field; K1 shows the eight benchmarks. The owner is
   asked to confirm both, and that each stays the generic list it is.
5. **The fixture (O17).** The owner is asked to confirm that none of the figures drawn is their own.
6. **Lab Book under "Imaging" and "Custom" (O4).** M1 shows what that means: about twenty cards
   under Imaging once scans exist, and a custom benchmark listed by its key ("Custom Bench Fixture
   Carry"), because Lab Book has no stored name for a custom key.
7. **Units in the scan sheet.** The specification gives one kg / lb control for the sheet (H1) and
   also kg, lb and g per mass field (§7.7). Drawn as both: the control sets the default and each mass
   field has its own unit menu. If only the sheet-wide control was meant, grams cannot be typed.
8. **The comparison layout.** Each row is the field name on its own line, then three columns
   (earlier, later, change). A four-column table does not fit the longer names at this width.
9. **How a change reads.** A signed figure with its unit, then the direction word and, where
   allowed, the percentage: "−5.0 kg · down · −5.0%"; "+15 s · up". No colour.
10. **Side differences in the comparison.** Each scan's text is shown ("Right 3.9% more", "Equal")
    with no change figure: the specification compares only arms to legs (§13.3) and does not say
    whether a side difference gets a change.
11. **The derived block** is absent when a scan has no arm or leg figure at all, so a whole-body-only
    scan does not end in three "Not available" lines. The Body record card shows the derived line
    only when it has a value.
12. **Dates carry the year** ("Wed 8 Jan 2031") on every stage 4 screen, since scans are months
    apart. The weigh-in history keeps stage 1's format.
13. **The scan list rows show each scan's total mass** beside its date. It is the scan's own dated
    figure, not a current weight.

## Proposed strings (not in §11)

| Where | Proposal | Why |
|---|---|---|
| G5, I5, J10b | `1 value in this scan could not be read. It remains in Lab Book.` | §11 gives only the plural. |
| G5b, I5b | `1 figure in this scan has two different stored values. Open Lab Book to delete the one that is wrong.` | The same. |
| I5 | `Could not be read: <field names>` | §10.3 says "naming the fields" and gives no wording. |
| I5b | `Two stored values: <field names>` | The same. |
| H9, H10, H13 | `Edit scan` (sheet title) | §11 has no title for the sheet. A new scan uses "Add a scan". |
| I, J | `Derived` (header of the derived block) | No header string. |
| K1 to K4 | `Benchmark` (label above the picker) | No label string. |
| K2 | `Seconds, or minutes and seconds: 45 or 1:30` | §10.5 says what is accepted and gives no hint text. |
| P3, P4 | `Switching either off hides its screens and deletes nothing.` | §10.8's own sentence, as a footer. |
| O13 | `Scans, benchmarks, and blood results typed in the unit your report prints.` and `Switching it off hides its screens and deletes nothing.` | Only if one switch is chosen. |

"Compare with <date>" and "Couldn't open the local store." are used as §10.1 gives them; neither is
in the §11 table. Strings reused from the app or from stage 1 (not new): "Add a reading", "Reading",
"Value", "Date taken", "Note (optional)", "Name", "Unit", "Blood panel", "Search markers (e.g. LDL,
ferritin)", "Add a custom marker", "History", "1 reading · your own entries", "last taken …",
"n markers", "Lab Book", "Imaging", "Custom", "Stored as mmol/L. × 0.02586 on save." (L7 only),
"Represents its week", "Not the weekly point", "not measured", "Weight", "Waist", "Health", "More
health", "Scorecard", "Live heart rate", "All metrics", "Skin temperature", "Settings".

## Notifications and widgets

None. The specification's list is empty by decision (§10): stage 4 has no widget and no
notification, so there is no notification text to write out and nothing from a scan, a benchmark or
a blood result can appear in either.

## Where the specification could not be drawn as written

- **J1 "all markers in both".** The fixture's A and B do not hold the same fields, so J1 is the full
  §13.3 table and also contains J2 and J3 rows. J3 and J5 are the same screen scrolled to one section.
- **"Not available. A figure it needs could not be used."** Not drawn. §13.2 reaches it with a legs
  total of 0, but 0 is outside the field's range (§7.7), so such a row is unreadable and reads as
  missing. No stored state was found that is readable and unusable. Either the string is unreachable
  on screen or §7.6 should say an unreadable row counts as invalid for `derive`.
- **"Left <value>% more"**, **"From left and right leg."** and the plural unreadable and conflicting
  lines have no fixture case. The builders produce them; no frame shows them.
- **I7** has no layout of its own.
- **G10** is one frame, not two.
- **L2** is two frames with the same id (a multiplied unit and the HbA1c formula).
- **H11 saving** has no string: Cancel, Save and the fields are dimmed.
- **Range messages** give the range in the stored unit (§7.7). What a field typed in pounds should
  say is not specified; not drawn. A ratio has no unit, so its message would end "between 0.1 and
  5 ."; not drawn.
- **A ratio's unit.** The stored unit is the word "ratio". The stage 4 screens show the number
  alone; Lab Book (M1) shows "1.15 ratio", as its row format does today.
- **A custom benchmark's name.** Body record shows "Fixture carry"; the stored key is
  `custom_bench_fixture_carry` and nothing stores the typed name, so Lab Book shows the humanised
  key. The specification does not say where the Body record screen gets the name from.
- **The screen note.** §11 calls it the existing Lab Book note reused, but the shipped text is
  "These are your own numbers shown back to you. NOOP doesn't decide whether any value is normal,
  high or low." (`LabBookView.swift:641`), and §11's wording differs ("figures", "does not"). §11's
  wording is drawn.
- **Lab Book rows (M1, L6)** leave out the 64 pt sparkline the shipped row and detail draw for a
  marker with several readings, because §10 says no stage 4 frame draws a chart. Stage 4 does not
  change that sparkline; it will still be there in the app.
- **Health row and Settings card (P).** §10 says stage 4 draws no frame for these and the combined
  frame set is the authority. They are drawn here for context only, without the other stages' rows
  and cards.
- **Pounds as the display unit** is drawn for entry (H3) only, not for the detail or the comparison.
- **Largest text size** is drawn where §10 lists it (G10, H14, I8, J11, K8); the Lab Book editor,
  the benchmark sheet, M, W and P are not drawn at that size.
- **Reduce Motion** has no frame: it is the settled state (`?static=1`).
- **Exact rounding ties** (§18): the model uses JavaScript's `toFixed`; the fixture has no tie.

## Token use and gaps

Existing tokens only: `--t1`, `--t2`, card, separator and control tokens, `--rec-low` for Delete
and for an entry that cannot be saved, the system green on switches. No metric colour appears on a
stage 4 screen, and there is no ambient glow, because nothing here is a score.

1. **`--t3a: #8A8A93`** (local, as round 6). Mirrors `NoopTheme.textTertiary`; still not in `noop.css`.
2. **Menu surface `#2A2A2F`** (J8 popover). A literal: the system has no token for a menu or
   popover surface. Proposal: one, or use the system menu in the app and drop the frame's own.
3. **Local icons** `cal`, `trash` (copied from round 6); SF Symbols in the app.
4. **Local components** to build from existing tokens: entry row with a unit menu, the plus / minus
   sign toggle, the comparison row (label, then earlier, later, change), the two-menu header, the
   three-column figure grid of the scan card. Round 6's `--sig-*` aliases are carried in the copied
   stylesheet and unused here.

## Rule check

Intended per frame, and checked by `check.js` where a check is possible without rendering: black
canvas and translucent cards; no chart, ring, band, rule or target line anywhere in the round; no
glow; colour only for Delete, an unsaveable entry and the system switch; loading is a shimmer
skeleton (G1); factual wording with no warning and no judgement of a value; a missing figure is
absent or reads "not entered", "not available" or "Not available. …", never 0 and never a dash with
a unit; the laboratory's resting-metabolic-rate figure is labelled an estimate wherever it appears;
no notification and no widget.

## Checks

Run under Node, no browser: `node design/round-s4-body-record/check.js --list`. Result on the
committed files:

```
model: §13.2, §13.3 (22 rows + derived), V3–V6, §13.5 reproduced; scans A, B, C sit on stage 1 weigh-ins
frames: 72 in 10 groups, names unique, every §10 state id present (61)
text: 4680 text nodes audited; 107 specification strings, 37 existing app strings, 42 names, 11 proposals
checks passed: 5277
```

What it asserts: the model gives the specification's own derived figures, comparison table,
mismatch variants, benchmark changes and blood conversions; each scan's total equals stage 1's
weigh-in of that day in round 6's model; 72 uniquely named frames exist and every state id of §10 has
one; J9's markup equals J1's; Save is enabled or disabled as each H state says; the weigh-in line
appears in H8 and H9 and is absent from H1, H2, H3, H6 and H7 (H10 and H13 also use the combined seed and show it); every text node of every frame is a recorded string or fixture data (a
number, a unit, a date); every recorded specification string occurs in §10 or §11; every reused
string occurs in the app's source or in stage 1; every name occurs in the specification or the
marker catalogue; no frame contains a chart, a ring, a glow, a notification or a metric colour.

What it cannot assert: anything visual.
