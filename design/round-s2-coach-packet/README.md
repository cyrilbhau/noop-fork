# Round S2 · Coach packet (Stage 2)

Design source for stage 2 of the health super-app workstream
([gate G1](../../docs/personal/superapp/QUALITY-GATES.md)), drawn from the stage 2 specification
(`docs/personal/superapp/specs/stage-2.md` §7, §9 to §11, §13) under the cross-stage rulings
(`RULINGS-ADDENDUM.md`, stage 1 §18 R25 onward). The HTML here is the source of truth; Figma receives
an export of it. It is built on round 6 (`design/round6-scorecard/`), the approved stage 1 round, and
loads that round's stylesheet and design model unchanged.

**The frames have not been viewed.** No browser was available when this round was written. The model
and the frame builders were run under node and checked as text (see "Checks run"); nothing was
rendered, so layout, wrapping, clipping and the largest-text frames are unverified until the
orchestrator renders and exports them. Expect layout corrections after the first render.

**Every value is synthetic.** The frames use the one Fixture Person all stages share (stage 1 §13,
stage 2 §13), read on Sun 16 Mar 2031 at 07:42:10, in the week after the last weigh-in.

## How the numbers are made

`model.js` is a design model of the stage 2 format (§7), the size budget (§7.10), the privacy scan
(§7.11) and the copy plan (§9.1), plus the §13 fixture. The scorecard inside the packet is round 6's
design model of stage 1 (`../round6-scorecard/model.js`) evaluated on 2031-03-16; it is not typed in.
`frames.js` words each state with the §11 strings and builds the frames. No result is typed by hand:
the preview text, the size line, the clipboard time, the Health tiles and the scorecard context are
all computed. The typed inputs are the fixture tables of §13 and two design clocks (Copy is tapped
20 seconds after the packet appears; a later change regenerates the packet at 07:43:05).

The model's output for the full fixture **equals the specification's §7.9 example byte for byte**
(6,221 bytes). It is a mockup aid, not the implementation, and has no parity twin.

## Files

| File | Purpose |
|---|---|
| `index.html` | The page. Loads `../system/noop.css`, `../round6-scorecard/scorecard.css`, `packet.css`, `../system/noop.js`, `../round6-scorecard/model.js`, `model.js`, `frames.js`, `packet.js`. |
| `model.js` | Design model of §7, §7.10, §7.11, §9.1 and the §13 fixture. Pure; loadable in node. |
| `frames.js` | Presenter (§11 strings), frame builders, the frame list. Pure string building; loadable in node. |
| `packet.js` | Browser glue: puts the frames on the page, sets each status bar to the packet's clock, fits each preview to its viewport, export hook. |
| `packet.css` | Local styles. `design/system/` and round 6 are not edited. |
| `check.js` | The node checks listed below. |

## View and export

```bash
python3 design/tools/serve.py                 # http://localhost:8765/round-s2-coach-packet/index.html
#   ?static=1   settled state, no motion      ?only=B   only frames whose id starts with B
python3 design/tools/serve.py --export round-s2-coach-packet/index.html --name s2-frames.json
node design/round-s2-coach-packet/check.js
```

The export writes `design/export/s2-frames.json` (git-ignored). The plugin command `importS2` reads
it; that command is added by the orchestrator, not by this round.

## Frames (33)

Each frame is named `S2 / <id> <title>`; that is also its Figma layer name.

### A · Entry points (§10.1)
- **A1 Health tab · Coach packet row** — second row of the "More" card, directly beneath Scorecard (ruling A1). Title "Coach packet", detail "Copy your numbers for your coach".
- **A2 Health tab · scorecard off, packet row first** — the packet row is the first of the stage rows.
- **A3 Health tab · Coach packet off** — the default: no row, the tab as stage 1 left it.
- **A4 Scorecard · toolbar item, document icon (option 1)** — the second toolbar item beside the weigh-in button. The screen beneath is dimmed only to point at the toolbar.
- **A5 Scorecard · toolbar item, share icon (option 2)** — the same item with the system share mark.
- **A6 Health tab · AX5** — the two stage rows and the next two at the largest text size.

### B · Packet sheet (§10.2)
- **B1 loading** — controls visible, Copy and Share disabled, skeleton for the preview and the size line.
- **B2 ready** — 14 days, every section on. "6.2 kB · 14 days". The preview is the exact text.
- **B3 ready, 7 days** — "4.9 kB · 7 days".
- **B4 nothing measured in the range** — golden G2; caption "Nothing was measured in this range"; preview drawn scrolled to the weigh-ins so the dashes show.
- **B5 scorecard off in the app** — caption under the Scorecard and Weigh-ins switches; preview drawn scrolled to the scorecard section.
- **B6 a section switched off** — Activity off; the header's `switched-off:` line names it.
- **B7 every section off** — header and notes only; "Switch on at least one section"; Copy and Share disabled.
- **B8 regenerating after a change** — range just changed to 7 days; the 14-day text and its size line stay, dimmed; actions disabled.
- **B9 copied** — "Copied to this iPhone only. It leaves the clipboard at 07:52." replaces the size line.
- **B10 copied, then a control changed** — Trends switched off; new text; "The clipboard still holds the earlier packet".
- **B11 share** — the system share sheet over the dimmed sheet, with no Copy of its own.
- **B12 blocked** — no preview; the blocked sentence; "Try again".
- **B13 unavailable** — "Your data could not be read. Try again."; "Try again".
- **B14 larger than the budget** — not reachable by construction; the size line says so; actions enabled.
- **B15 AX5** — controls stack; the preview keeps its size.
- **B16 copied, AX5**.
- **B17 blocked, AX5**.

### O · Options for the owner
- **O1 long lines wrap (proposal)** — B2 with the preview wrapping instead of scrolling sideways.
- **O2 size line with the generated time (proposal)** — "6.2 kB · 14 days · 07:42".
- **O3 compact controls (proposal)** — sections as five toggling chips, Copy and Share side by side.

### C · Settings (§10.3)
- **C1 Coach packet off** — the default. One card, one switch, the §11 blurb, directly after the Scorecard card.
- **C2 Coach packet on**.
- **C3 AX5**.

### D · Shortcuts action (§10.4)
- **D1 the action and its result** — "Get Coach Packet" with its description, and the text it returns.
- **D2 every result** — the six rows of §10.4 with the exact failure messages.

### R · The text that leaves (§7)
- **R1 complete, 14 days** — the whole packet, every line unwrapped (a wide frame). It is §7.9.
- **R2 nothing measured** — golden G2 in full.

## Notifications and widgets

**None.** §10.5: the packet never appears in a widget payload or in notification text, and this stage
adds no notification, no reminder, no Today card and no Siri phrase. There is no notification text to
write out. The copied confirmation is inline in the sheet (B9); it is not a toast or a banner.

## Decisions for the owner

1. **Toolbar icon on the scorecard: A4 (document) or A5 (share mark).** Recommended: A4. The sheet's
   primary action is Copy and nothing is sent; the share mark promises a destination.
2. **Long lines in the preview: scroll sideways (B2, as specified) or wrap (O1).** Recommended: O1 at
   ordinary text sizes. The packet's longest line is 201 characters and about 52 fit; with B2 the
   owner must scroll sideways to see what leaves. Wrapping changes the screen only, not the text.
3. **Size line: "6.2 kB · 14 days" (B2, §11) or with the generated time (O2, §10.2's sentence).** The
   specification says both. Recommended: B2. The generated time is already the preview's second
   line, and one readout of a fact is the safer design.
4. **Section controls: five switch rows (B2, as specified) or chips with side-by-side actions (O3).**
   Recommended: B2. O3 roughly doubles the preview's height, but the chips are a new component and
   the standard switch is clearer with VoiceOver and at the largest text size.
5. **Blocked and unavailable (B12, B13): Copy and Share are removed, not shown disabled**, because
   no text exists. The range and section controls stay, since changing them may clear the cause. The
   specification does not say either way. Confirm.
6. **Colour.** This surface has no Sleep, Recovery or Strain value of its own, so it is neutral:
   primary and secondary text on the sheet. Switches use the existing green, as stage 1's do. The
   copied confirmation is a check mark and primary text, not green: it is a fact, not a met signal.
   Blocked and unavailable carry no red and no warning mark. Confirm.
7. **Where captions sit.** "The scorecard is off, so these sections say so" sits inside the section
   card, under the two switches it is about. The other three captions ("Nothing was measured in this
   range", "Switch on at least one section", "The clipboard still holds the earlier packet") sit on
   one line under the size line. Only one of the three shows at a time; drawn precedence is stale
   clipboard, every section off, nothing measured.
8. **The size's unit.** The specification gives the example "6.2 kB" and no rule. Drawn as bytes
   divided by 1,000 with one decimal.

## Proposed strings (not in §11)

| Where | Proposed English source | Why |
|---|---|---|
| Sheet, leading bar button | "Done" | The sheet needs a dismiss control that VoiceOver can reach; §11 has none. |
| Size line when over the budget (B14) | "%@ · %lld days · larger than expected" | §10.2 says "the size line says so" and gives no wording. |
| Size line with the generated time (O2 only) | "%@ · %lld days · %@" | Needed only if decision 3 goes to O2. |

Text in the frames that is **not** this stage's and goes in no catalogue for it: the Health tab's own
rows and tiles; stage 1's scorecard strings in A1, A4, A5 and C1 to C3 (worded as round 6 and the
shipped Settings card word them); the system share sheet's labels in B11 ("Plain Text", "AirDrop",
"Messages", "Mail", "Notes", "Save to Files"); the Shortcuts app's chrome in D1; the state labels in
D2, which are the left column of the §10.4 table; the byte counts above the text in R1 and R2.

The toolbar item's accessibility label ("Coach packet", §11) cannot be drawn; it is in A4's note.

## Token use and gaps

Existing tokens only: `--t1`, `--t2`, the card, separator and control tokens of `noop.css`, and the
metric tints already on the Health tab's rows (`--heart`, `--hrv`, `--temp`, `--recovery`,
`--breath`). `packet.css` contains no colour value of its own beyond neutral black and white
translucency. Round 6's local `--t3a` proposal is inherited through its stylesheet, unchanged.

1. **A monospaced token in the mockup system.** The app has `StrandFont.mono`; `noop.css` has no
   equivalent, so the preview's font stack is local to `packet.css`. Proposal: add `--mono` to
   `noop.css`. No new app token is needed (the specification says the same).
2. **Preview block.** A local component: an inset, darker than the sheet, 11pt monospaced, 15pt
   lines. Built from existing values; proposed as a shared "verbatim text" block if a later stage
   shows text of this kind.
3. **Section chips** (O3 only) would be a new component. Not needed if decision 4 stays with B2.
4. **Icons.** Mockup icons `doc`, `paste`, `upload`, `shield`, `info`, `refresh`, `check` stand in
   for SF Symbols in the app.

## Checks run (node, no rendering)

`node design/round-s2-coach-packet/check.js` — 31 checks, all passing:

- The model's text for the full fixture equals the specification's §7.9 example byte for byte, at
  6,221 UTF-8 bytes; the size line computes to the §10.2 example "6.2 kB · 14 days"; a copy 20
  seconds after generation expires at the §10.2 example time 07:52; the privacy scan finds nothing.
- Golden G2 prints the §13.3 lines for no data and no measured value as zero; scorecard off, one
  section off and every section off give the lines §7 states; an account address in the phase name
  is blocked; an unreadable store is unavailable; 7, 14 and 28 days are under the §7.10 budget
  (4,877 of 9,540; 6,221 of 11,080; 7,971 of 14,160 bytes); no tab, no trailing space, one trailing
  newline.
- 33 frames, unique names of the form `S2 / <id> <title>`; no chart element in any frame; every
  frame's markup is balanced; every icon exists in `noop.js`; every class has a rule in `noop.css`,
  round 6's `scorecard.css` or `packet.css`; every colour is an existing token.
- All 28 presenter strings are in §11 word for word; every one is drawn in a frame except the
  accessibility label; every text node of every frame (1,865) is a §11 string, a named proposal,
  context from another surface, or a line of the packet; each sheet preview is its document line
  for line; the copied confirmation is the §10.2 sentence; no string contains an exclamation, a
  warning, a streak or an instruction to the owner.

`node --check` passes on `model.js`, `frames.js` and `packet.js`. `packet.js` itself (DOM code) has
not been executed.

## Where the specification could not be drawn as written

- **Size line and generated time.** §10.2 lists "a line with the size and the generated time"; §11's
  string is "%@ · %lld days". Drawn as §11 (B2), with the other reading as O2.
- **"Larger than the budget."** No string. Drawn with a proposal, at budget plus one byte (11,081
  bytes, "11.1 kB"), which no input can produce.
- **Dismissing the sheet.** No string. Drawn with "Done".
- **Blocked (B12)** is reached in the model by naming the phase with the fixture's invented account
  address (§13.4), which the scan finds. The frame shows none of it.
- **Golden G2's scorecard block.** §13.3 gives G2's other sections line by line but not its
  scorecard lines. R2 shows what the design model gives for no phase and no readings; its protein
  line takes the counts as zero and the floor from the fixture's parameters. Stage 1's real result
  decides.
- **Reopened later** and **Reduce Motion** have no frame. The first is B1 then B2 with a later
  generated time (the fixture has one clock); the second is the settled state every frame shows.
- **28 days** is not drawn in the sheet. The fixture holds 14 days of daily rows, so a 28-day frame
  would be 14 days of dashes above the same 14 days. The model renders it (7,971 bytes).
- **The preview's scroll position** in B4 and B5 is drawn scrolled, so the lines the state is about
  are visible. An opened sheet starts at the top.
- **AX5.** §10 asks for every state at the largest size. Drawn for the Health row (A6), the sheet
  ready, copied and blocked (B15 to B17) and Settings (C3). The other sheet states are not drawn at
  AX5, and the toolbar item has no text to scale. AX sizes follow round 6's scale (about 2× body).
- **The three shared surfaces.** The Health card, the Settings section and the scorecard screen are
  laid out by the orchestrator's combined frame set (§10, P17). A1 to A6 and C1 to C3 show this
  stage's row, toolbar item and card in the place rulings A1 and §10.1 give them; the rows and cards
  of stages 3 to 6 are not drawn here.
- **The share sheet and the Shortcuts app** are iOS's. They are drawn approximately, for position
  and for the strings this stage supplies. Whether Shortcuts shows an intent's localised error text
  is listed in §18 as not determined.
- **One clock.** Each frame's status bar shows the time its packet was generated (07:42, or 07:43 in
  B10), not the mockup system's usual 9:41, so the frame cannot show two times for one moment.

## Notes for the specification

- **§18, first item** (whether §7.9 equals what Swift prints). To match §7.9 the model had to round
  `%.1f` values as C does: an exact tie goes to the even digit. 75 minutes prints "1.2h" and a
  stored strain of 25 at factor 0.21 prints "5.2"; halves-away-from-zero gives "1.3h" and "5.3".
  §18 describes the scratch script as "halves-away-from-zero"; for the `String(format:)` fields the
  golden follows the C rule, and §7.1 should say so. `Int(x.rounded())` fields are unaffected.
- **§18, second item** (whether `evaluate` returns the hand-built result of §13.3). Round 6's design
  model of `evaluate`, given stage 1's fixture and today = 2031-03-16, produces every scorecard and
  weigh-in line of §7.9 exactly, including rule 3's 5 of 3 weeks and the lift counts. That is a
  design model agreeing with the specification, not Swift agreeing with it.

## Rule check

Checked by reading the builders, not by viewing frames: black canvas; translucent cards on the
Health and Settings screens and the standard sheet surface for the sheet; dense, with the preview
given all the height the controls leave; no chart, so no rule, band or target line can occur; no
decorative glow (the Health frames carry the tab's existing ambient field, nothing is added);
shimmer skeleton for loading (round 6's `.skb`); factual wording with no warning, advice or medical
statement; missing values are "—" in the packet and never 0; the packet labels its own estimates
(`~` and `strap-estimate`, `(estimate)` on the projection, the notes section); nothing of the packet
is in a widget or a notification.

- List separators inside cards are the existing hairline, as in round 6.
- Switches use the existing green. The preview text is one colour throughout: it is verbatim text,
  and colouring parts of it would make the screen differ from what leaves.
- The preview is not selectable (§10.2); nothing in the frames suggests selection.
