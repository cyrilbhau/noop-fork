# Round S5 · Events layer (Stage 5)

Design source for stage 5 of the health super-app workstream, for gate G1
([QUALITY-GATES](../../docs/personal/superapp/QUALITY-GATES.md)), drawn from the stage 5
specification (`docs/personal/superapp/specs/stage-5.md`, §10 screens, §11 strings, §13 fixture) and
the rulings addendum. The HTML here is the source of truth; Figma receives an export of it.

**These frames have not been viewed.** No browser was available when they were written. The model
and the frame builders were run under node (see "Checks" below), which proves they execute, that the
numbers and strings are right, and that the markup keeps the rules that can be read from markup. It
does not prove what any frame looks like: spacing, wrapping, overlap and the largest-text layouts
are unverified until the orchestrator renders and exports them.

**Every value is synthetic.** The person is the one Fixture Person of stage 1 §13 ("Fixture cut" from
Mon 6 Jan 2031, weighed on Wednesdays, week 10 missed), with the eight events of stage 5 §13.1 added.

## How the numbers are made

`model.js` is a design model of stage 5 §7 (validation, order, overlap), §10.5 (marks, thinning,
caption), §10.6 (scorecard note) and §10.9 (presenter), plus the §13.1 events and the §13.4 variants.
It imports the stage 1 design model (`../round6-scorecard/model.js`) for weights, waists, the phase
and the verdict, and restates none of it. Every word this stage shows is held once, in `STR`, and
every frame is the fixture on a stated day run through the model. No date, count, value or event
line is typed in `frames.js`. It is a mockup aid, not the implementation.

Two things the specification's fixture does not contain are derived inside the model and are
invented, not specified:

- **Daily recovery, sleep and steps.** Stage 1 §13 gives weekly weights only. The model derives a
  value per day from a fixed hash of the day number, so a day always draws the same value. The strap
  is taken as not worn on 13 and 14 Mar 2031 (inside the fixture trip), which gives the "not
  measured" days.
- **Three design-only variants**: `DOpen` (the ongoing illness with Private switched off, for C5),
  `DMany` (three more events in week 15, for N9) and `DUpcoming` (three planned events seen from
  8 Jan, for L4).

## Files

| File | Purpose |
|---|---|
| `index.html` | The page. Loads `../system/noop.css`, `../round6-scorecard/scorecard.css`, `events.css`, `../system/noop.js`, `../round6-scorecard/model.js`, `model.js`, `frames.js`. |
| `model.js` | Design model and fixture. Pure; loads in the browser (as `S5M`) and in node. |
| `frames.js` | Frame builders and the frame list. Charts are built as strings, so it also runs in node. The scorecard screen is a copy of round 6's presenter and layout with the note and the mark row added. |
| `events.css` | Local styles. Round 6's stylesheet is imported, so components, tokens and the AX5 scale are the same app. `design/system/` and round 6 are not edited. |
| `check.js` | The node check. `node design/round-s5-events/check.js` |

## View and export

```bash
python3 design/tools/serve.py                 # http://localhost:8765/round-s5-events/index.html
#   ?static=1   settled state, no motion      ?only=N   only frames whose id starts with N
python3 design/tools/serve.py --export round-s5-events/index.html --name s5-frames.json
```

The page honours `?static=1&export=s5-frames.json` and calls `exportSvgFrames`, as round 6 does.

## Frames (82)

Each frame is named `S5 / <id> <title>`; the id is also the demo name (`--demo-screen events-<id>`).

### H · Health tab row (§10.1)
- **H1 Health row · one event now**: "Events · 1 now" on Wed 12 Mar, between Body record and Niggle log.
- **H2 Health row · nothing now**: the row with no value. Never "0 now".
- **H3 Health row · Personal events off**: no row.

### L · Events screen (§10.2)
- **L1 rows in three sections**: Now, Upcoming, Earlier on 12 Mar; a Private tag; a note's first line.
- **L2 ongoing, with End today**: the ongoing private event under Now on 28 May, "Since 19 May".
- **L3 after End today**: the same event with its end day set to today; no action left.
- **L4 only future events**: Upcoming alone.
- **L5 empty**: "No events yet", one line, Add event as the primary action.
- **L6 loading**: skeleton rows.
- **L7 some entries unreadable**: the footnote; nothing offers to remove anything.
- **L8 store unreadable**: explanation, Copy stored text, Start again.
- **L9 Start again asks once**.
- **L10 swipe to edit or delete**.
- **L11 AX5**: dates stack under the name; the tag wraps.

### D · Delete confirmation (§10.4)
- **D1 asks once**: name and dates, "This cannot be undone.", Delete, Cancel.
- **D2 a private event**: shows the owner's own name, since this is inside the Events screen.

### S · Event sheet (§10.3)
- **S1 first open**: Travel, today, One day, empty note, Private off.
- **S2 choosing the kind**: the six kinds.
- **S3 Illness, Private follows the kind**.
- **S4 Private kept as the owner set it**: switched on, then kind changed to Deload.
- **S5 Something else, name needed**: Save disabled; the field says a name is needed.
- **S6 Something else, named**.
- **S7 Until, with an end date**.
- **S8 picking the end date**: calendar; days before the start dimmed.
- **S9 end before start**: Save disabled; the end field says why.
- **S10 Ongoing**.
- **S11 planned**: a future start; "Planned: this starts in the future".
- **S12 note near its limit**: the remaining count.
- **S13 Edit event**: the event's values; Delete.
- **S14 saving**: controls dimmed, buttons disabled.
- **S15 save failed**: values intact; Save is the retry.
- **S16 save failed, store unreadable**: says so and links to Events.
- **S17 with the coach packet sentence**: for the packet v2 change, not this stage's milestone.
- **S18 AX5**: each control on its own row.

### M · Marks on the time axis (§10.5)
- **M1–M4 Weight curve** (scorecard, weekly points): no event; one event; dense run (eleven marked weeks); missed week (ring with the dot beneath).
- **M5–M8 Recovery bars** (thirty days): no event; one event; dense run (fourteen days); days not measured.
- **M9–M12 Sleep line**: no event; one event; dense run over ninety days, thinned; days not measured (the line breaks).
- **M13 Steps bars · seven days**.
- **M14 Marks · AX5**.

### C · Chart caption (§10.5)
- **C1 one event**, **C2 two events**, **C3 more than two** ("and 3 more").
- **C4 a private event**: "Private event · 26 Mar".
- **C5 ongoing**: "Illness · since 19 May". **C6 ongoing and private**: "Private event · since 19 May".
- **C7 AX5**: lines wrap; no date is cut.
- **C8 spoken summary**: the VoiceOver text, as an annotation.

### O · Options for the owner
- **O1 / O2 Marks**: a dot per covered position (recommended) against a dot at the start and an open dot at the end. Same three charts.
- **O3 / O4 / O5 Scorecard captions**: under each curve (as specified); once, under the weight curve; marks only.
- **O6 Scorecard note · judged week only**: the other answer to S7. O4 shows both sections.

### N · Scorecard annotation (§10.6)
- **N1 no events stored**: the stage 1 screen, nothing added.
- **N2 an event in the judged week**.
- **N3 weigh-in due, in a week with an event**: earlier section only; the trip is on the curves under week 10's ring.
- **N4 after a missed week**: the gap explains itself.
- **N5 a private event**: "Private event · 26 Mar".
- **N6 during a deload**, **N7 during a diet break**: the scorecard keeps reporting.
- **N8 an ongoing private event**.
- **N9 more than three events**: three lines, then "and 1 more".
- **N10 private deload** (V9).
- **N11 no readings**: no note. **N12 weigh-in overdue**: no note; the curves keep their marks.
- **N13 AX5**.
- **N14 Today card · unchanged**.

### G · Settings (§10.7)
- **G1 Personal events off** (the default), **G2 on**.
- **G3 / G4 with the packet switch, off and on**: for the packet v2 change.
- **G5 AX5**.

### W · Notifications and widgets (§10.8)
- **W1 none**: an annotation frame.

## Notification text

None. This stage sends no notification and adds nothing to a widget, a Live Activity or the watch
(§10.8). There is no text to write out.

## Decisions for the owner

1. **Mark style: O1 or O2.** O1 (a dot per covered day or week) is the specification's
   recommendation and this design's. O2 is lighter on a long event but leaves the weeks inside it
   unmarked, so a missed week inside a trip would have no dot under its ring.
2. **Captions on the scorecard: O3, O4 or O5.** The specification gives every adopting chart its
   own caption, so the scorecard would name the same events three times (O3). This design recommends
   O4, one caption under the weight curve, and the N frames are drawn that way. O5 drops the caption,
   but then the dots have no text on days when the note is absent (N12) or cannot list an event (N3).
3. **Scorecard note: both sections (O4) or the judged week only (O6).** Question S7; both is in force.
4. **Mark size.** Drawn as proposed: a 4pt dot in the tertiary text grey, in an 8pt row, thinned to
   6pt spacing. The dot does not grow with text size; the caption does (M14).
5. **Two ways to delete.** Swipe on a row (L10) and a Delete button in the edit sheet (S13). Keep
   both, or one.
6. **Kind as a menu (S2)** on one row, rather than six chips.
7. **How the sheet says what is wrong.** An empty name is said by the field's own placeholder, in
   grey (S5). An end before the start is said in red under the field (S9), as stage 1 marks an entry
   that cannot be saved.
8. **Order of event lines.** The caption's order is specified (latest start first). The note's is
   not; drawn the same way.
9. **Year in a date.** Shown only when it differs from today's year ("1 – 7 Dec 2030").
10. **Planned events.** "From 19 May" is used for a planned ongoing event. A planned event with an
    end shows its range, and a planned one-day event its day.
11. **"End today"** is a small pill in the row, under the date (L2).

## Proposed strings (not in §11)

| Where | String | Why |
|---|---|---|
| L7 | `%lld entry could not be read. It is kept.` | The singular of "%lld entries could not be read. They are kept." Variant V6 has exactly one. |
| S12 | `%lld left` | §10.3 asks for a remaining count on the note and gives no words. Drawn as "28 left". |
| L10 | `Edit` | The swipe action. §11 has "Edit event" (the sheet title) only. |

Reused §11 strings in places the specification does not name: "Cancel" dismisses the sheet; "This
cannot be undone." and "Start again" are the detail and the button of the Start again confirmation
(L9); "Events" with a chevron is the link in S16; "Delete" is the button in the edit sheet; the
delete detail is the caption format "%@ · %@" ("Travel · 10 – 16 Mar").

Words that are not this stage's: "Settings", "Health", "More health", "Scorecard", "Body record",
"Niggle log", "Recovery · 30 days", "Sleep · 90 days", "Steps · 7 days", "Strap", "Apple Health"
and every scorecard string. They stand in for existing screens or other stages' rows.

## Token gaps and local components

No colour is added. An event has no colour: dot, tag and text are neutral.

1. **`NoopTheme.Layout.chartAxisMark` 4, `chartAxisMarkRow` 8, `chartAxisMarkSpacing` 6.** The
   specification's proposals, drawn as given. They do not exist in `NoopTheme.Layout` yet.
2. **`--t3a` (`#8A8A93`)**, round 6's local mirror of `NoopTheme.textTertiary`, is the dot colour.
   It is still missing from `design/system/noop.css`.
3. **A tag component.** "Private" uses the pill round 6 drew for "Estimate" (white at 8%, secondary
   text). Proposal: one shared tag style.
4. **The mark row** (`NoopChartAxisMarkRow`) and **the caption** (`PersonalEventChartCaption`): new
   shared components, built from existing tokens.
5. **Form rows in a sheet** use the grey fill of round 6's sheet fields (`rgba(118,118,128,.18)`),
   which is not a named token.
6. **The kind menu** is a drawing of the system menu; its surface (`#2C2C31`) is local and not a token.
7. **Local icons** `cal`, `trash`, `pencil`, as in round 6; SF Symbols in the app.

## Where the specification could not be drawn as written

- **§13.2, "today 2031-03-12 … E1 appears".** On that day the judged week is week 9 (3 – 9 Mar).
  By §10.6's own definitions the note lists events overlapping the judged week or the earlier
  evidence window, both of which end on Sun 9 Mar; the trip starts on 10 Mar, so the note cannot
  list it. In N3 the trip appears as the dot under week 10's ring and in the curve caption.
- **The note's title** is not optional in §10.6, but "Events this week" over an empty list reads
  wrongly. Drawn only when the judged week has an event (N3, N4 show the earlier section alone).
- **`moreText`** is one field for two lists. Drawn once, at the end of the note, as the sum cut.
- **The combined layout.** The Health card, the Settings cards and the scorecard screen are approved
  once in the orchestrator's combined frame set, which did not exist in this worktree. H, G and N
  use round 6's layout with placeholder neighbours, in the order of ruling A1. The combined set wins.
- **The host charts** are sketches of existing charts, not captures. Only the mark row and the
  caption are this stage's. An open ring for a day not measured is drawn on bar charts as it is on
  the weekly curve; whether `NoopBarChart` shows that today was not read.
- **A custom event with Private switched off**, outside the Events screen: §10.9 says "its kind
  name", which would be "Something else", not the owner's label. Not drawn; worth one sentence.
- **Spoken text**: "joined by ", "" is drawn as "Events: Travel · 10 – 16 Mar, Travel · 22 – 24 Feb,
  and 2 more".
- **Thinning** only occurs past about fifty-five days in a 332pt plot, so only M11 shows it.
- **AX5.** §10 asks for every state at the largest size. Drawn for each primary surface (L11, S18,
  M14, C7, N13, G5) only. The Health row and the confirmations are not drawn at AX5.
- **Not drawn:** Reduce Motion (it is the settled state every frame shows under `?static=1`);
  "Saved" (the sheet dismisses); the start-date calendar (S8 shows the end-date one); a count on the
  40-character name; the packet sheet's "Private events: left out / included" caption (stage 2's
  sheet, packet v2); stage 6's timeline; the intake screen's caption; each adopting site separately
  (Strain detail, Metric Explorer, Trends, Training hub) beyond one frame per chart family.

## Rule check

Checked by `check.js` on every frame: no rule, band, target line or dashed stroke in any plot; no
zero-height bar; a private event's name and note appear only in the Events screen, its delete sheet
and its editor; every event line elsewhere is "<kind or Private event> · <dates>"; no causal,
medical, urging or scoring word. Checked by reading, not by viewing: black canvas and translucent
cards (round 6's components); colour only where round 6 uses it (Recovery by band, Sleep violet,
signal states, the green switch, red for Delete and an entry that cannot be saved); a missed week
and a day not measured break the curve or leave the bar out; skeletons for loading (L6).

## Checks

`node design/round-s5-events/check.js`, last run output:

```
frames: 82
  H · Health tab row (§10.1): 3
  L · Events screen (§10.2): 11
  D · Delete confirmation (§10.4): 2
  S · Event sheet (§10.3): 18
  M · Marks on the time axis (§10.5): 14
  C · Chart caption (§10.5): 8
  O · Options for the owner: 6
  N · Scorecard annotation (§10.6): 14
  G · Settings (§10.7): 5
  W · Notifications and widgets (§10.8): 1
plots: 60   event lines: 105   text nodes checked against §11 and the fixture: 642
README proposals check: done
browser path (stub document): every frame written to #boards
OK: 3757 checks passed
```

What it covers: the model against §13.2 (covered weeks, relations), variants V1 to V5 and V9, the
kind defaults, the note on 26 Mar and stage 1's evidence window; the stage 1 verdict unchanged with
and without events on all 22 weigh-in days; every `STR` value present in §11 and no proposal present
there; frame count, unique names and ids; every text node of the L, D, S and G frames being a §11
string, a listed proposal, a fixture value or a date; mark counts per frame; and the page's scripts
run in one shared scope against a stub document, which caught one load-order error the node path
could not. It renders nothing.
