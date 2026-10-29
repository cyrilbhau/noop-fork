# Section-title alignment and vertical rhythm: implementation plan

Status: proposed on 29 October 2026, not yet implemented. A presentation-only change for the personal
iPhone redesign. It touches design tokens and their call sites. It does not change data, formulas, BLE,
storage, imports or Coach. The Your Cards plan ([YOUR-CARDS-REDESIGN-PLAN.md](YOUR-CARDS-REDESIGN-PLAN.md))
assumes this plan has landed. If it has not, Your Cards uses the same `NoopSectionHeader` and simply
inherits whichever values are current.

## Problem

The redesign has one horizontal grid:

- screen gutter: 16pt (`NoopTheme.Layout.gutter`), where every card's outer edge sits;
- card content: 16 + 18 = 34pt (`cardPadding`).

Section titles ("Heart rate", "Key metrics", "Activity") are drawn by `NoopSectionHeader` with
`.padding(.horizontal, -gutter)` at the call site and `sectionSide` = 20 inside the header. They land
at 20pt from the screen edge. That is 4pt right of the card edge and 14pt left of the card content, so
they align with neither. The round-1 mockups set this value (`.sec{padding:26px 20px 10px}`), and the
implementation copied it faithfully.

Vertical rhythm is close to right, but the heading-to-card gap (10) is tight next to the 12pt card gap.
That makes a heading read as slightly closer to the card above than to its own card.

## Decision

| Token | Now | New | Why |
|---|---:|---:|---|
| `sectionSide` | 20 | **16** (`= gutter`) | Titles share the card edge: one left line from the large title down. |
| `sectionBottom` | 10 | **12** | Heading-to-card gap equals the card gap. The heading stays bound to its card. |
| `sectionTop` | 26 | **28** | Slightly more air between groups than inside a group (28 vs 12). |
| new `captionInset` | — | **18** (`= cardPadding`) | Explanatory text in the gutter column aligns with card content (34pt). |

Rejected: a 20pt heading-to-content gap. It detaches the heading from what it labels. iOS grouped
lists keep this gap small.

## The token currently has two meanings

`sectionSide` is used for two different things. Changing one value alone would leave half the call
sites wrong.

1. **Title inset from the screen edge.** Used in a full-bleed context, or in the gutter column with
   `-gutter` applied first. These should resolve to the card edge (16pt from the screen).
2. **Text inset inside the gutter column.** Captions, footnotes and source lines under a card, whose
   parent already applies the 16pt gutter. Today they land at 36pt. They should match card content at
   34pt, so they move to `captionInset` (18).

Classify each call site by checking whether its parent already applies `gutter`. Known call sites as
of `personal/iphone-baseline` at `faaff38a` (verify, as working-tree changes may add more):

| Call site | Expected class |
|---|---|
| `Packages/StrandDesign/.../NoopSurfaces.swift` `NoopSectionHeader` | 1: keeps `sectionSide` |
| `StrandiOS/Redesign/TrainingKit.swift` (header at ~258) | 1 |
| `StrandiOS/Redesign/InsightsKit.swift` (header at ~127) | 1 |
| `StrandiOS/App/TrainingHubView.swift` (~397) | 1 |
| `Strand/Screens/JournalLogCard.swift` (~581), `DevicesView.swift` (~892, ~1169) | 1 |
| `Strand/Screens/SettingsView.swift` (~3040, `sectionSide - gutter`) | 1: becomes 0, now on the card edge |
| `StrandiOS/Redesign/RedesignHealthView.swift` (~64, ~83) | 2 → `captionInset` |
| `StrandiOS/Redesign/RecoveryDetailView.swift` (~89), `StrainDetailView.swift` (~123) | 2 |
| `StrandiOS/Redesign/FormKit.swift` (~305), `InsightsKit.swift` (~92) | 2 |
| `Strand/Screens/MetricExplorerView.swift` (~2004, ~2010, ~2065, ~2179) | 2 |
| `Strand/Screens/LiftLogView.swift` (~436), `LiftSessionDetailSheet.swift` (~539), `WorkoutDetailView.swift` (~709) | 2 |
| `Strand/Screens/JournalLogCard.swift` (~533), `BackupSyncView.swift` (~564) | 2 |
| `StrandiOS/App/ChatGPTConnectionView.swift` (~321, ~436) | 2 |

Find them with `grep -rn "Layout.sectionSide\|Layout.sectionTop\|Layout.sectionBottom" Strand StrandiOS Packages`.
A site that is genuinely neither class keeps its current rendered position, using an explicit token
expression with a one-line comment.

## Steps

1. In `Packages/StrandDesign/Sources/StrandDesign/NoopTheme.swift`, set `sectionSide = gutter`
   (written as a reference, not the literal 16), `sectionBottom = 12` and `sectionTop = 28`. Add
   `captionInset = cardPadding` with a doc comment explaining the two classes above.
2. Migrate the class-2 call sites to `captionInset`.
3. `design/system/noop.css` already carries the new values (`.sec{padding:28px 16px 12px}`). Mirror
   them in `docs/personal/REDESIGN-IMPLEMENTATION.md` (layout tokens), so the mockups, the spec and
   the app agree.
4. Leave Liquid Today and classic Today alone. They do not use these tokens for their own section
   headers. Shared `Strand/Screens` files that do use them (Settings, Devices, Metric Explorer, Lift
   Log, Workout detail, Journal, Backup) also compile for macOS: build the `Strand` scheme and open
   one of them to confirm nothing jumps unexpectedly.

## Verification

- `cd Packages/StrandDesign && swift build` (macOS only).
- Build `NOOPiOS` with its widget, and `Strand` (macOS), per `docs/personal/CONTEXT.md` (unsigned
  simulator build via `Tools/personal/ios.sh build`).
- In the simulator, with synthetic data, check Today, Health, Training, Recovery detail, Strain detail
  and Settings at the default size and at AX5. For each screen, confirm the large title, section
  titles and card edges share one left line, and that captions under cards line up with the card
  text.
- `python3 Tools/doc_comment_lint.py` for the new token's doc comment. No new copy, so there is no
  localisation impact.

Figma: the round 2–4 frames were realigned on 29 October 2026 with the "Align section titles to gutter"
command of the local `design/figma-plugin`. Horizontal positions only: the 2pt vertical changes are
too small to redraw imported frames for, and the tokens own them.
