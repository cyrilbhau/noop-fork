# Round S6 · Niggle log, recovery context, checkpoint timeline (Stage 6)

Design source for stage 6 of the health super-app workstream
([ROADMAP](../../docs/personal/superapp/ROADMAP.md), [gate G1](../../docs/personal/superapp/QUALITY-GATES.md)),
drawn from the stage 6 specification (`docs/personal/superapp/specs/stage-6.md`) and the binding
`RULINGS-ADDENDUM.md`. The HTML here is the source of truth; Figma receives an export of it.

**These frames have not been viewed.** No browser was available when they were written. The model,
the strings and the frame builders were run under Node and checked there (see "Checks" below).
Layout, wrapping, overlap, the look of each card and the AX5 frames are unverified until the
orchestrator renders, exports and views them. Treat any visual claim in this file as intent.

**Every value is synthetic.** The one Fixture Person of stage 1 §13 (phase "Fixture cut" from Mon
6 Jan 2031, target 94.0 kg, exercises "Fixture Press" and "Fixture Row"), extended by stage 6 §13:
five owner-typed rules, complaints at "Fixture location A" to "E", the §13.3 nights and the §13.4
timeline inputs. Nothing under any `PersonalData/` directory was read.

## How the frames are made

- `model.js` is a design model of stage 6 §7 (`NiggleTriage.evaluate`, `CutStressTrend.weekly`,
  `CheckpointTimeline.build`, the two adapters of §8.4 and the checkpoint save check of §9.3) plus
  the §13 fixture. Each frame is the fixture on a stated day run through that model. No label, day
  count, weekly mean, change or timeline row is typed by hand. It is a mockup aid, not the
  implementation.
- `strings.js` holds every word a frame can show, in three tables: `S6_SPEC` (copied from §11),
  `S6_QUOTED` (wording §10 gives in quotation marks but §11 does not list) and `S6_PROP`
  (proposals). Frames get text only through `t(key, …)`, which throws on an unknown key.
- `frames.js` builds each frame as an HTML string (so it also runs under Node), names it
  `S6 / <id> <title>`, and in the browser hands the page to `design/system/noop.js`. Charts are
  built as inline SVG strings by `weekChart`, a copy of round 6's weekly chart.
- `s6.css` adds local layout only. The page loads `../system/noop.css` and round 6's
  `../round6-scorecard/scorecard.css` unchanged, so cards, rows, sheets, skeleton blocks and the AX5
  switch are the approved round 6 ones. `design/system/`, `design/figma-plugin/`, `design/tools/`
  and every other round are untouched.
- `check.js` is the Node check.

## View and export

```bash
python3 design/tools/serve.py        # http://localhost:8765/round-s6-niggle-timeline/index.html
#   ?static=1   settled state, no motion      ?only=G   only frames whose id starts with G
python3 design/tools/serve.py --export round-s6-niggle-timeline/index.html --name s6-frames.json
node design/round-s6-niggle-timeline/check.js --list      # the checks, then the frame list
```

The export hook is round 6's: `?static=1&export=s6-frames.json` calls `exportSvgFrames`. The folder
is `round-s6-niggle-timeline` as this round's task names it; the specification (§5, §10) calls it
`round-s6-log-timeline`. The frames file name, `s6-frames.json`, is the same in both.

## Frames (94)

Each frame is named `S6 / <id> <title>`; that is also its Figma layer name.

### A · Niggle log (§10.2)
- **A1 open complaint, rule matched** — Sat 22 Mar 2031 (fixture row N2d). Two rules match; the more serious action shows. The next change line is what the owner's rules say on day 30.
- **A2 loading**
- **A3 first use, nothing stored**
- **A4 no rules entered** — No rule ships with the app. Each open row shows its day count and "No rules entered yet".
- **A5 rules entered, professional rule empty**
- **A6 open complaint, no rule matches** — Wed 14 May (fixture row N5).
- **A7 next change to no rule** — Wed 11 Jun (fixture row N6a). The owner's rule A stops at day 10.
- **A8 complaint seen again** — Mon 16 Jun: the second "Fixture location B", right. It is a new entry with its own day count.
- **A9 several open** — Sorted by action severity, then day count, then location.
- **A10 resumed exercises shown**
- **A11 resolved shown** — Resolved entries carry no label.
- **A12 no paused exercises** — Wed 5 Feb. The section is absent.
- **A13 entries need attention**
- **A14 rules need attention**
- **A15 limit reached** — The list is drawn with the fixture's entries; the state is the disabled action and the named limit.
- **A16 AX5**

### B · Niggle detail (§10.3)
- **B1 open, rule matched** — Fixture row N2d.
- **B2 open, no rule matches**
- **B3 no rules entered**
- **B4 rules need attention**
- **B5 resolved** — Fixture row N1.
- **B6 observation**
- **B7 an update not used** — Fixture row N2c: the stored update is dated outside the complaint as it stands on Fri 21 Mar, so it is kept, marked and not used.
- **B8 delete asks once**
- **B9 AX5**

### C · Niggle sheet (§10.4)
- **C1 add a complaint**
- **C2 add an observation**
- **C3 location empty**
- **C4 location too long**
- **C5 edit**
- **C6 add update**
- **C7 mark resolved**
- **C8 saving**
- **C9 save refused**
- **C10 AX5**

### D · Rules sheet (§10.5)
- **D1 first use**
- **D2 rules entered** — The five rules of §13.1.
- **D3 a rule**
- **D4 reorder**
- **D5 a value that cannot be saved**
- **D6 delete a rule asks once**
- **D7 limit** — Rules F to T are placeholders added to reach the limit of 20; they are not in §13.
- **D8 AX5**

### E · Paused exercise sheet (§10.6)
- **E1 add**
- **E2 reason empty**
- **E3 edit, mark resumed**
- **E4 delete asks once**
- **E5 AX5**

### F · Recovery context (§10.7)
- **F1 default, current week below the minimum** — Wed 5 Feb 2031, the §13.3 case. The curve ends at the last full week and breaks at the week of 20 Jan (3 nights).
- **F2 loading**
- **F3 current week at or above the minimum** — Thu 16 Jan: four nights this week.
- **F4 a week below the minimum in the middle** — Sun 2 Feb.
- **F5 only one week has a mean**
- **F6 no week has a mean**
- **F7 no nights at all**
- **F8 typical range not available**
- **F9 HRV present, resting heart rate absent**
- **F10 no cut phase started** — The latest 12 weeks; here the nights begin on 30 Dec.
- **F11 strap disconnected or removed** — Wed 26 Feb: no night after Sun 9 Feb. Stored weeks stay; later weeks read "not measured".
- **F12 AX5**

### G · Timeline (§10.8)
- **G1 phases, scans, checkpoints, events and the estimate** — Wed 5 Feb 2031, the first §13.4 case.
- **G2 loading**
- **G3 nothing but today**
- **G4 past items, a break running now** — Mon 24 Mar, the second §13.4 case: a done and a not-done checkpoint, a past deload, the recorded scan standing for the planned one, an open-ended diet break tagged "now".
- **G5 a deload running now** — Thu 20 Feb.
- **G6 waypoint at or past the target** — The §13.4 changed-target variant: the phase target is now 96.0 kg.
- **G7 target date, phase no longer stored**
- **G8 events off, scorecard off** — The third §13.4 case.
- **G9 body record off**
- **G10 later stages not in this build** — No scan, break or deload rows and no mention of them.
- **G11 no projection** — No item and nothing said; the scorecard explains why.
- **G12 a private event is absent** — Thu 10 Apr, the §13.4 adapter fixture: the private deload of 7 to 13 Apr and the travel event have no row, placeholder or count.
- **G13 checkpoints need attention**
- **G14 phases need attention**
- **G15 limit reached**
- **G16 AX5**

### H · Checkpoint sheet (§10.8)
- **H1 add, any category**
- **H2 edit, done**
- **H3 weight waypoint**
- **H4 waypoint at or beyond the target**
- **H5 target date**
- **H6 target date, no stored phase**
- **H7 target date not after the phase start**
- **H8 the phase already has a target date**
- **H9 other invalid input**
- **H10 save refused**
- **H11 delete asks once**
- **H12 AX5**

### P1 · Choice: which label shows when several rules fit (Q2)
- **P1.1 the most serious action (default)**
- **P1.2 the first matching rule in the owner's order**

### P2 · Choice: the day count on the day it started (Q3)
- **P2.1 day 1 on the onset day (default)**
- **P2.2 day 0 on the onset day**

### P3 · Choice: how the timeline shows its time axis
- **P3.1 separate rows (as specified)**
- **P3.2 marks on one vertical line**

### Specification states and the frame that draws each

Where one frame carries more than one listed state:

- §10.2 "Observations", "Paused exercises": A1. "Open complaint with a next change": A1 (to a rule)
  and A7 (to no rule). "Resumed exercises": A10. "Resolved": A11.
- §10.3 "Updates ignored": B7. "Entry no longer exists": no frame (the screen pops).
- §10.4 "Invalid": C3 and C4. "Saving / save refused": C8 and C9.
- §10.5 "A preview line per rule": D2 and D3. "Invalid": D5.
- §10.6: E1 to E4.
- §10.7 "Default", "Phase started", "Current week below the minimum": F1. "A week below the minimum
  in the middle": F1 and F4. "Scorecard flag off": no frame (the screen is unreachable).
- §10.8 "Phase start", "Checkpoint, upcoming", "Weight waypoint", "Target date, phase found",
  "Scan", "Projection": G1. "Checkpoint, past, done / not done", "Diet break / deload, past",
  "current", "open-ended": G4 and G5. "Private" and "any other event kind": G12.
  "Events: notBuilt" and "Scans: notBuilt": G10. "Events: off" and "Scorecard flag off": G8.
- Reduce Motion has no frame: it is the settled state every frame shows with `?static=1`.

## Notifications and widgets

**None.** Stage 6 adds no notification, no widget, no widget payload field and no Shortcuts action
(§10.9), so there is no notification text to write out and no frame draws one. `check.js` asserts
that no frame contains one. The log, the rules and the timeline never leave the app's own screens.

## Decisions for the owner

1. **Which label shows when several of your rules fit (Q2).** P1.1 the most serious action, then
   your order (the specification's default); P1.2 the first matching rule in your order.
2. **The day count on the day it started (Q3).** P2.1 "Day 1" (default); P2.2 "Day 0".
3. **How the timeline shows its time axis.** P3.1 separate rows, each with its own quiet mark (as
   specified); P3.2 the same marks joined by one thin vertical line. P3.2 is a proposal: the line is
   vertical and sits behind the marks, but it is a straight line, so it is yours to accept or not.
4. **Action words carry no colour (D6).** "Watch", "Modify training" and "See a professional" are
   plain text in the primary colour, and a label is your own text in semibold. Nothing in the log is
   green, amber or red. Confirm.
5. **Recovery context is neutral.** Both curves use the primary text colour, not the HRV or heart
   tints the Health tab uses, because §8.2 forbids any colour there. Confirm, or ask for the metric
   tints (they would be the existing `--heart` and `--hrv` tokens, with no band meaning).
6. **Timeline marks.** A phase start is a solid diamond; a scan an open square; a checkpoint an open
   ring, or a solid disc with a tick once done; a break or deload an upright capsule, solid while it
   is running; the estimate a dashed ring (the same dashed vocabulary round 6 uses for "unknown").
   All neutral greys.
7. **Where a running break sits.** §7.3 sorts a span by its start day and §10.8 asks for three
   headings taken from each item's position. A long-running break that began before some past item
   would then sit under "Earlier" while tagged "now". Drawn as: items that are current and have no
   past item after them go under "Today"; any other current span stays in date order under
   "Earlier" with its "now" tag. No fixture case reaches the second branch.
8. **Wording questions.** The §11 strings are drawn as written. For your decision:
   - The rule read-back does not form a sentence: "Spread over an area complaints that is Easing
     from day 1 through day 10 is labelled “Fixture label A”" (D2). The parts are drawn in the order
     §11 lists them. A reworded set would be needed for it to read cleanly.
   - "Since %@" for a break that has not started yet reads oddly: G1 shows "Diet break · Since 24
     Mar" on 5 Feb. Proposed for an upcoming open-ended span: "From 24 Mar" (not drawn).
   - "Logged before: %lld times", "%lld updates are dated … were not used" and "Resolved after %lld
     days" have no singular in §11. The fixture produces a count of 1 for the first two, so the
     frames draw the proposed singulars "Logged before: 1 time" (A8) and "1 update is dated outside
     this complaint and was not used" (B7). The plural sources are therefore not drawn.
   - §10.4 asks for each character "with one line of meaning each". §11 gives one string per
     character, so the four strings are drawn as the choices themselves, with no second line.
   - "Your typical range" beside weekly averages (F1) can be read as a judgement when the average
     sits outside it, although no word says so. It is drawn as §10.7 specifies.

## Proposed strings

The specification gives no string for these. Each is in `S6_PROP` in `strings.js`.

- **Already in the app (system or stage 1):** "Cancel", "Save", "Edit", "Delete", "Saving…",
  "Could not save.", "Open phase and rules".
- **Niggle log and detail:** "A dated record of a complaint: where, what kind, and how it changes.
  Labels come only from rules you write." (first use); "Resumed" (the disclosure); "Logged before:
  %lld time"; "%lld update is dated outside this complaint and was not used"; "Resolved after %lld
  day"; "not used"; "Started" (the onset row's tag); "Updates"; "Your rule"; "Next"; "Delete this
  entry?" / "Paused exercises linked to it stay in your list, without the link."
- **Niggle sheet:** "Kind", "Complaint", "Observation", "Location", "Side", "Character", "How it is
  changing", "Started", "Noted", "Note", "Date", "Resolved on", "Edit niggle", "Optional", "Enter a
  location.", "A location can be up to 60 characters.", "Future dates cannot be picked.", "From %@
  to today.", "An update dated before the new start is kept and not used."
- **Rules sheet:** "Your rules", "Rule", "Label", "Action", "Which complaints", "Which changes",
  "Weakness", "Either", "With", "Without", "From day", "Through day", "No end", "Any", "Reads as",
  "or" (joins several characters or changes in the read-back), "Enter a label.", "From day starts
  at 1.", "Through day cannot be before from day.", "Delete this rule?" / "Complaints are labelled
  again without it.", "The list holds up to %lld rules" (§11 says "the same shape" as the log's).
- **Paused exercise sheet:** "Exercise", "Reason", "Until", "Paused on", "Linked niggle", "None",
  "Resumed on", "Edit pause", "Enter an exercise.", "Enter a reason.", "Delete this pause?" / "The
  niggle it is linked to is not changed."
- **Recovery context:** "week of %@", "Week of %@", "bpm", "ms". Weekly averages and the change are
  drawn to one decimal ("64.3 bpm", "+4.3 bpm", "−5.3 ms"); the specification gives no format.
- **Timeline and checkpoint sheet:** "Open checkpoint" (the footnote's link), "Your phases could not
  be read. Target dates are shown without a phase.", "Title", "Category", "Approximate date",
  "Weight", "Phase", "Edit checkpoint", "Enter a title.", "A title can be up to 60 characters.",
  "Enter a weight.", "Enter 30 to 250 kg.", "Open that checkpoint", "Delete this checkpoint?" /
  "Nothing else on the timeline changes.", "The timeline holds up to %lld checkpoints".
- **Defined for states no frame reaches** (in `S6_PROP`, not drawn): "Resolved after %lld day", "Enter a
  label.", "From day starts at 1.", "Enter an exercise.", "A title can be up to 60 characters.", "Enter a
  weight."
- **Quoted in §10 but missing from §11** (drawn; they need a §11 row): "Any weakness" (§10.4),
  "Set up your phase" (§10.8), "not measured" (§10.7).
- **In §11 and not drawn here**, because they belong to the combined Health, Settings and scorecard
  frames this round does not design: "%lld open", "Next: %@" and the three Settings descriptions.

## Fixture values the specification does not give

Listed so nothing invented passes as specified:

- **Typical range.** Stage 6 §13 has none. The frames use the Fixture Person's ranges from the stage
  2 specification's packet example: 52 to 56 bpm and 51 to 64 ms. They do not bracket the §13.3
  nights (60 to 66 bpm), which are a separate golden.
- **Rule notes.** §13.1 has none; "Fixture rule note A" to "E" are added so B1 can show one.
- **The second "Fixture location B"** (§13.2) is given its side and onset only; its character and
  change repeat N2's.
- **Two extra nights** (2031-02-09 and 2030-12-30) are given "both values" with no numbers; they
  repeat their neighbours' (64 / 45 and 60 / 50).
- **Rules F to T** in D7 are placeholders that reach the limit of 20.
- **The timeline's projection** is §13.4's 2031-05-27. Stage 1's fixture, run through round 6's
  model on 5 Feb 2031, projects 2031-03-15; §12.8 says the demo takes the scorecard's own value.
- **C2 "Fixture panel"** is stored done but dated 10 Feb, ahead of "today" in the first §13.4 case.
  §9.3 allows done only on or after the day, so G1 draws it not done and G4 draws it done.

## Where the specification could not be drawn as written

- **Entry points.** The Health rows, the scorecard links and the three Settings cards are in the
  combined frame set, not here (§10.1). So "beside the scorecard" is not drawn as a placement: F
  frames show the pushed Recovery context screen only.
- **Niggle detail title.** §10.3 gives no navigation title. Drawn as a large header: the location,
  with the side and character beneath.
- **"Limit reached"** (A15, G15) is drawn with the fixture's few entries; only the disabled action
  and the named limit show the state.
- **"First week shown"** (§10.7) is drawn as the earliest week that has a mean, with its week named,
  which is `CutStressChange.from`. In F10 the earliest week on the axis (30 Dec) has one night and
  no mean, so the value shown is the week of 6 Jan.
- **"Strap disconnected or removed"** (F11) lists each later week as "Week of … · not measured". The
  specification gives the words but not the layout.
- **"Updates ignored"** (B7) uses fixture row N2c, where the stored update is dated after "today".
  The app's own sheet cannot create that; the real route is an edited onset (§10.4).
- **Checkpoint category picker.** H1 draws all seven categories as a list; the other H frames draw
  the chosen one as a row.
- **AX5** is drawn once per screen (8 frames), not for every state.
- **Not drawn:** deleting an update, discarding unreadable data (its confirmation), the rules
  sheet's "limit" and "invalid label" messages other than D5 and D7, and the `-flow-` simulator
  flows of §12.8.

## Token use and gaps

No new colour. Everything is an existing `noop.css` token or one of round 6's named local tokens
(`--t3a`), loaded from round 6's stylesheet.

1. **`--t3a`** is still local to round 6 (`#8A8A93`, `NoopTheme.textTertiary`). This round depends
   on it. The standing proposal to add it to `noop.css` now has two users.
2. **No token for "neutral data line".** The recovery context curves use the primary text colour
   `#F5F5F7` as a literal in the chart builder, as round 6's weight curve does through `--t1`.
3. **Text field.** There is no shared multi-line field in `noop.css`; `.fld2` is local (an existing
   fill, `rgba(118,118,128,.18)`, and the existing red for an invalid border).
4. **Timeline marks** are local SVG, 20 pt, neutral greys. In the app they would be SF Symbols or a
   small shared mark view; no symbol names are proposed here.
5. **Radio and multi-select marks**, the drag state of a rule card (`--card2` and a shadow) and the
   disclosure row are local. The shadow under a dragged card is the system's drag lift, not a glow.
6. **Local icon** `trash`, copied from round 6.

## Rule check

Checked per frame by `check.js` where markup can show it, and by reading the builders otherwise:
black canvas and translucent cards (the shared `.screen` and `.card`); no ambient glow, because no
score is on these screens; colour only where round 6 already has it (the toggle's green, red for
Delete and an invalid field); charts are a smooth line with a gradient fill and one point per week,
with no rule, band or target line, and a week without a mean breaks the line and leaves an open ring
on the time axis; skeletons are round 6's shimmer blocks in the loaded layout; no warning, streak,
count of missed items, "overdue", cause, prognosis or treatment; a missing value reads "—", "Not
measured yet" or "not measured", never 0; the projection is tagged "estimate"; a private event has
no row.

## Checks

`node design/round-s6-niggle-timeline/check.js`, as last run:

```
ok    §13.2 triage: 10 rows (N1, N2a–d, N3, N5, N6a, N6b) and the N2 state days
ok    §13.3 weekly means, night counts, rejection counters and changes
ok    §13.4 timeline: three cases, the changed-target variant, the adapter fixture
ok    115 SPEC strings found verbatim in §11; 3 QUOTED strings found in §10
ok    94 frames, names unique, each "S6 / <id> <title>"; one AX5 frame for each of the 8 screens
ok    text pieces: 1359 specification (§11), 16 quoted in §10, 499 proposals, 328 fixture text, 319 dates and numbers; 0 unmatched
ok    15 charts: only a smooth line, a gradient area, points and axis labels; no rule, band or target line
ok    no semantic colour in any frame's markup (labels, actions and both curves are neutral; Delete and invalid fields take red from the round 6 styles)
ok    no diagnosis, cause, treatment, warning, "overdue", streak or good/bad wording (the one "not a diagnosis" sentence of §11 aside)
ok    recovery context: no 0 is drawn for an unmeasured week; "—" and "Not measured yet" are
ok    every frame that shows the projection tags it "estimate"
ok    no notification and no widget is drawn (stage 6 adds none, §10.9)
ok    timeline: no event label or note, and nothing marks a private event
ok    a waypoint row never carries the word "target"

SPEC strings not drawn in any frame (2): "Logged before: %lld times", "%lld updates are dated outside this complaint and were not used"
§11 strings with no entry in the SPEC table (9): "%lld open", "Next: %@", "Record a complaint and see it against your own rules. Off by default.", "Weekly resting heart rate and HRV beside the scorecard. Not a score.", "Phases, checkpoints and your estimate in one list.", "Estimated", "Target", "waypoint", "Private event"
PROP strings defined but not drawn: resolvedAfter1, labelEmpty, fromLow, exEmpty, titleLong, weightMissing

ALL CHECKS PASSED · 94 frames
```
