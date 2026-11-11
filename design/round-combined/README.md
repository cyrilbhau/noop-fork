# Round combined · the surfaces every stage shares (stages 1 to 6)

Design source for the one combined layout the rulings addendum asks for
(`docs/personal/superapp/specs/RULINGS-ADDENDUM.md`, ruling A1) and gate G1
(`docs/personal/superapp/QUALITY-GATES.md`): the Health tab's "More health" card, the Settings cards,
the scorecard screen with every stage's addition, and Today's Your cards. It is the authority for the
order and density of those surfaces. Each stage's own screens (packet sheet, intake screen, body
record, events, niggle log, recovery context, timeline) belong to that stage's round and are not here.

**The frames have not been viewed.** No browser was available when this round was written. The model
and the frame builders were run under Node (see "Checks"); nothing was rendered, exported or looked at.
Wrapping, spacing, clipping and how the AX5 frames reflow are therefore unverified, and the first
render may need fixes.

**Every value is synthetic.** The frames use the one Fixture Person (stage 1 §13; ruling A7): phase
"Fixture cut" from Mon 6 Jan 2031, target 94.0 kg, weighed on Wednesdays, protein floor 100 g. The
default day is **Wed 5 Feb 2031, fixture week 5**, at 09:41 (the status bar's clock): the day stage
6's fixtures use and a week stage 5's deload covers, so every stage has something to show.

## How the numbers are made

- `../round6-scorecard/model.js` (the approved stage 1 design model) is loaded as it is, not copied.
- `model.js` adds what the other stages put on the shared surfaces, from each specification's own
  fixture: events (stage 5 §13.1), intake settings and today's protein (stage 3 §13.1, §13.4, §13.6),
  scan days (stage 4 §13), complaints, checkpoints and nights (stage 6 §13.2 to §13.4).
- `r6-presenter.js` is round 6's presenter and primitives, copied unchanged (the line numbers are in
  its header), so a stage 1 result is worded exactly as the approved frames word it.
- `frames.js` builds every frame as a string and words it through one string table (`STR`), each
  entry naming the file it was taken from or marked `proposal`.

No result is typed by hand. Three figures are fixture inputs with a stated origin, not results: the
status-bar time 09:41, stage 1's stored reminder default (Saturday 08:00), and the refused floor
entry "99.5" (stage 1 §10.5's own example).

## Files

| File | Purpose |
|---|---|
| `index.html` | The page. Loads `../system/noop.css`, `../round6-scorecard/scorecard.css`, `combined.css`, then `../system/noop.js`, `../round6-scorecard/model.js`, `model.js`, `r6-presenter.js`, `frames.js`, `combined.js`. |
| `model.js` | Design model for the shared surfaces. Pure; loadable in Node. |
| `r6-presenter.js` | Round 6's presenter, copied unchanged inside a wrapper. |
| `frames.js` | String table, frame builders, the weekly chart as data, the frame list. No DOM. |
| `combined.js` | Puts the frames on the page, draws the charts, carries the export hook. |
| `combined.css` | Local styles added to round 6's. `design/system/` is not edited. |
| `check.js` | The Node checks. |

## View and export

```bash
python3 design/tools/serve.py                 # http://localhost:8765/round-combined/index.html
#   ?static=1   settled state, no motion      ?only=B   only frames whose id starts with B
python3 design/tools/serve.py --export round-combined/index.html --name combined-frames.json
```

The export writes `design/export/combined-frames.json`. Each frame is named `SC / <id> <title>`; that
is also its Figma layer name.

## Frames (47)

### H · Health tab: the "More health" card
- **H1 every switch on** — eight stage rows in the order of A1, then the card's existing rows unchanged. Details: Scorecard "Change nothing · 97.5 kg"; Coach packet "Copy your numbers for your coach"; Intake none; Body record "Last scan 8 Jan"; Events "1 now"; Niggle log "1 open"; Recovery context none; Timeline "Next: 10 Feb".
- **H2 every switch on, Recovery context reached from the scorecard only (option)** — seven rows, as stage 6 §10.1 is written.
- **H3 some switches on** — Coach packet, Events, Recovery context and Timeline on, scorecard off: three rows, Coach packet first.
- **H4 one switch on** — Intake alone.
- **H5 every switch off** — the card as it is today.
- **H6 every switch on, nothing recorded yet** — Mon 6 Jan: vitals "—" and "Not measured"; rows with nothing to report carry no detail; Body record "No scans yet".
- **H7 loading** — shimmer for the tiles and the details.
- **H8 AX5** — detail wraps under the title.

### S · Settings: the eight cards
- **S1 every switch off** — the default install: eight cards, nine switches (Body record holds two), all off.
- **S2 every switch on** — each card with its rows; both reminders still off.
- **S3 some switches on** — as H3; Recovery context says it opens from the scorecard; the second Events switch shows because the packet is on.
- **S4 compact cards (option)** — the same cards and order with the switch row leading.
- **S5 Scorecard card, weekly reminder on** — Day, Time, and the notification as it looks.
- **S6 Intake card, source None.**
- **S7 Intake card, cutoff reminder on** — with the wind-down caption and the notification.
- **S8 Intake card, Apple Health not available** — the source row back at None, saying why.
- **S9 Intake card, values that cannot be saved** — "Enter whole grams"; a range with its ends reversed.
- **S10 notifications denied** — both reminder rows with "Notifications are off for NOOP".
- **S11 AX5** — every switch off.

### B · Scorecard screen with every stage's addition
- **B1 every switch on** — packet button in the toolbar; event note under the verdict (deload this week, supplement change earlier); protein row "Apple Health" with a chevron; a dot on the time axis of both curves under weeks 3 and 5; Recovery context and Timeline links.
- **B2 only the scorecard on** — round 6's screen, nothing added.
- **B3 some switches on** — Coach packet and Events.
- **B4 events only earlier in the evidence window** — week 4.
- **B5 an event in a week with no weigh-in** — week 11: the line breaks at week 10, ring on the axis, dot beneath it, note names the trip.
- **B6 a private event** — week 12: "Private event · 26 Mar".
- **B7 an ongoing private event** — week 20: "Private event · since 19 May".
- **B8 more than three events in a list** — "and 3 more" (three events invented for this frame only).
- **B9 every switch on, no readings** — no note, no marks.
- **B10 events on, none stored** — B1 without the note and the dots; the charts keep their height.
- **B11 weigh-in due while an event is running** — Wed 12 Mar.
- **B12 protein row, every source caption** — off (stage 1's row), "Apple Health", "Entered here", "CSV import", "Several sources", no data, no floor.
- **B13 links card, each combination** — neither, Recovery context, Timeline, both.
- **B14 loading.**
- **B15 AX5.**
- **B16 event note inside the verdict card (option).**
- **B17 event captions under the curves as well (option).**
- **B18 toolbar, packet button options** — document, clipboard or share icon; and the toolbar with the packet off.

### T · Today: Your cards
- **T1 Scorecard and Protein cards** — "97.5 kg · Change nothing"; "95 g · 5 g to your floor · 09:31" with a partial ring; the Weight tile shows the same 97.5 kg.
- **T2 Protein card, every state** — the twelve states of stage 3 §10.1 plus a CSV value ("· imported").
- **T3 Scorecard card, every state** — the twelve states of stage 1 §10.1.
- **T4 only the scorecard on.** **T5 only Intake on.** **T6 every switch off.**
- **T7 adding the cards** — both under "More cards".
- **T8 loading.** **T9 AX5.**

### N · Notifications
- **N1 every notification, written out.**

## Notification text, exactly

| Stage | Title | Body | When |
|---|---|---|---|
| 1 | `Weekly weigh-in` | `Weight, then waist. It takes under a minute.` | Opt-in, one a week |
| 3 | `Food cutoff` | `Your cutoff time is now.` | Opt-in, one a day at most |

Stages 2, 4, 5 and 6 send none. No widget is drawn in this round: the Protein widget is stage 3's.

## Decisions for the owner

1. **Recovery context on the Health card: H1 (a row, eight in all) or H2 (no row, seven).** Ruling A1
   lists eight entries; stage 6 §10.1 gives Recovery context a Settings card and a scorecard link but
   no Health row, and leaves the point to this frame set. H1 costs one more row that must also hide
   while the scorecard is off, because the screen cannot be reached without it (H3). H2 leaves the
   screen with one way in.
2. **Settings density: S1 (the shipped scorecard card's shape, eight times) or S4 (compact).** S1 is
   long with everything off. S4 drops the separate title, so "Scorecard" and "Events" are named only
   by their switch labels ("Weekly weigh-in and scorecard", "Personal events").
3. **Where the event note sits: its own card under the verdict card (B1) or inside the verdict card
   above the rules (B16).** B1 leaves the approved verdict card untouched.
4. **Event captions under the curves: left out (B1) or shown (B17).** Stage 5 §10.5 adds a caption
   under every chart that takes marks. On this screen the note already names the events, so B17 says
   each event three times. B1 keeps the dots and lets the note be their legend.
5. **The packet button: icon and position (B18).** Drawn as a document icon left of the weigh-in button.
6. **Health row detail placement.** Drawn trailing, as round 6's P1.3 and the shipped row do. "Copy
   your numbers for your coach" is long for a trailing detail and will wrap; the alternative is no
   detail on that row.
7. **Order of lines in the event note, and which three survive the cut.** The specification gives
   neither. Drawn newest start first, as the Events screen lists them.
8. **Wording** of the eleven proposed strings below.

## Proposed strings (not in any specification)

| Where | String |
|---|---|
| Intake card, the one sentence (§10.5 asks for one, §11 has none) | "Protein and calories against your own floor and range. Off by default. Everything stays on this iPhone." |
| Events card, the one sentence | "Mark travel, illness, a diet break or a deload, and charts show when it happened. Off by default." |
| Recovery context card, switch on while the scorecard is off | "Opens from the scorecard, so it shows once the scorecard is on." |
| Intake, source None | "With no source, the Protein card and widget have nothing to show." |
| Intake, Apple Health unavailable | "Apple Health is not available on this iPhone. Source is back to None." |
| Intake, range low above high | "The low end is above the high end. Nothing was saved." |
| Cutoff reminder, off | "The reminder is off unless you turn it on. One notification a day, at your cutoff time." |
| Cutoff reminder, on | "One notification a day. It never contains an amount, a floor or a supplement name." |
| Calorie range and hard floor values | "%lld to %lld kcal", "%lld kcal" |
| Editor subtitle of the Scorecard card (round 6's) | "Weight and this week's verdict" |

Also proposed, with no new string: the switch labels of the Niggle log, Recovery context and Timeline
cards reuse each card's title (stage 6 §11 gives a title and a description only); "What it looks like"
is reused above the cutoff notification; the vitals tiles reuse "Not measured"; dates in row details
are day and month ("8 Jan"); "Apps to count" lists the app names separated by a comma.

Reviewer annotations inside frames (a state's name above a tile or row, in the tertiary colour) are
not app copy.

## Token use and gaps

Existing tokens only, plus round 6's local proposals (`--t3a`, `--sig-met`, `--sig-not`, `--sig-unk`).

1. **Chart axis mark** (stage 5's proposal, confirmed here as drawn): dot diameter 4, row height 8, in
   `NoopTheme.textTertiary`; a missed week's ring stays on the baseline and the dot sits 8pt beneath it.
   The plot keeps its height; the chart grows by the row only when a mark exists.
2. **No colour for the stage rows and cards.** Icons and titles are neutral (`--t1`). The palette has
   no colour for body composition, intake, events or a log, and none is invented.
3. **Protein ring.** Neutral white on the track token; it is progress to the owner's own floor, not a
   met or not-met judgement, so it takes no signal colour. Dimmed with the value when stale.
4. **Icons.** From `noop.js`: `scale`, `doc`, `fork`, `flask`, `trend`. Local: `cal` and `pencil`
   (copied from round 6) and `timeline` (new). In the app each is an SF Symbol to be chosen.
5. **Local components** built from existing tokens: the Settings card (title, sentence, switch rows,
   captions), the Health list row with a trailing detail, the event note, the two-cluster toolbar.

## Rule check

Checked in text by `check.js`, per frame: the A1 order on both surfaces; every switch off by default;
no warning, streak, praise or medical wording; nothing unmeasured shown as 0; every projected date
labelled Estimate; a private event never showing its kind, label or note; the two notifications word
for word; charts made only of gradients, paths, circles and two date labels (no line, rect or band
element, no straight horizontal path); one stroke per unbroken run, so a missed week breaks the curve.

Not checkable without a render, and to be looked at first: black canvas and translucent cards, colour
use, the gradient fills, the shimmer, contrast of the tertiary text, and every wrap.

## Where a specification could not be drawn as written

- **Stage 5 §13.2, 12 March.** It says the trip (E1) "appears" in the note on 2031-03-12. By the
  note's own definition (§10.6) it does not: the judged week is week 9 and E1 lies after it. B11 draws
  the definition: E1 only as the dot under week 10. The "gap explains itself" case is drawn a week
  later (B5), where E1 is in the earlier section.
- **Stage 1 §7.9 evidence window before the phase.** In the first weeks it reaches back before the
  phase starts, so on 8 Jan the December trip (E7) would be listed as "earlier in the weeks behind
  this verdict". Not drawn; reported for a ruling.
- **"More than three in a list" (stage 5 §10.6).** The fixture never has more than three; B8 adds
  three invented events and says so.
- **Today's rings.** The Fixture Person has no Sleep, Recovery or Strain score on 5 Feb (stage 2's
  daily rows cover 3 to 16 March), so the Today frames show the Your cards section alone, without
  rings or the score glow.
- **Intake card: "Choosing Apple Health" and the Health-unavailable wording.** The first is the
  system's permission sheet and is not drawn. For the second the specification points at the bridge's
  states without giving words; S8 uses a proposal.
- **Stage 3 §10.5 "Apps to count ... when more than one is known".** Drawn with both fixture apps.
- **Not drawn:** Reduce Motion (it is the settled state every frame shows with `?static=1`); AX5 for
  the state frames (one AX5 frame per primary screen: H8, S11, B15, T9); the scorecard's other stage 1
  states with the additions (they are round 6's B frames plus the same four additions); the second
  Events switch turned on; widgets.

## Checks

```bash
node design/round-combined/check.js            # add --list for the frame names, --proposals for the proposals
```

159 checks, all passing when this was committed: the frame count and names; the three scripts loaded
as page scripts after `noop.js` and round 6's model, giving byte-identical frames to the Node load;
`combined.js` run against a stub document, drawing 26 charts; 97 strings found verbatim in their source
file; 2130 text runs each traced to a specification string, a listed proposal, round 6's presenter,
round 6's layout copy or fixture data; and the fixtures reproducing the specifications' own tables
(stage 5 §13.2 covered weeks, stage 3 §13.4 progress, stage 6 §13.2 to §13.4, stage 1 week 5).
