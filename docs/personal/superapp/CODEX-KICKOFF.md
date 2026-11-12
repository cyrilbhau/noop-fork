You are joining a workstream already in progress on my personal iPhone fork of NOOP, an on-device companion app for WHOOP straps. Another agent, a Claude session, has run it so far and stays the integrator. You are the second agent: a builder and an independent checker. This whole message is your kickoff prompt.

## Read first, in this order

Everything is on the local branch `personal/superapp-1-scorecard`. Do not check that branch out in the main folder; read it from a worktree you create (below).

1. `docs/personal/superapp/COLLABORATION.md` — the contract between you and the Claude session. It is binding.
2. `AGENTS.md` — the repository's rules.
3. `docs/personal/superapp/README.md`, `CONTEXT.md`, `QUALITY-GATES.md`.
4. `docs/personal/superapp/specs/RULINGS-ADDENDUM.md`, then `specs/stage-1.md` section 18 (rulings R25 onward). Both bind every stage.
5. The board: `/Users/cyrilbhau/Documents/Noop/noop-fork/build/superapp-coordination/BOARD.md`. Your lanes are C1 to C5.

## Hard rules

- **Local only.** The GitHub repository is public. Never push, never open a pull request.
- **Do not open `PersonalData/` at all.** It holds my real health data. Everything you need uses a fictional "Fixture Person".
- **Never work in the main folder** `/Users/cyrilbhau/Documents/Noop/noop-fork` itself: it holds another session's uncommitted work. Never touch a worktree whose name does not start with `codex-`.
- **Never commit to `personal/superapp-…` branches** and never merge into the integration branch. Your branches are `personal/codex/<lane>`.
- **Never edit a hot file** (listed in COLLABORATION.md section 4) and never edit `Strand/Resources/Localizable.xcstrings` or `project.yml`.
- **Never edit a test you did not write.** If a test looks wrong, stop on it and write it up.
- **No Android work.** Write no Kotlin.
- No migration, no wider Apple Health access, no new build target, entitlement or network path. Install nothing on this Mac. Nothing goes near my phone.
- Do not run `xcodebuild` for the app targets or use the simulator unless a lane says so: the Claude session owns the app build. `swift test` inside a package is yours to run.

## How to start a lane

1. Read the board. Pick the first of your lanes whose state is `todo` (a lane marked `waiting` is not ready). Write your name and the new state into its row, save, and re-read the file to make sure the Claude session did not take it at the same moment.
2. Create your worktree from the integration branch's current tip and record that commit in the board:

```
cd /Users/cyrilbhau/Documents/Noop/noop-fork
git worktree add -b personal/codex/<lane> .claude/worktrees/codex-<lane> personal/superapp-1-scorecard
```

3. Work only inside that worktree. Use absolute paths.

## Your lanes

- **C1, review stage 1 (start here; it needs nothing else).** Read-only. Try to break it: an input that gives a wrong verdict, a wrong number or a crash; any path that could lose, overwrite, re-key or hide a stored row or a setting; any difference from the app's behaviour before the feature when the setting `noop.cutScorecardEnabled` is off (compare with commit `138cc60b`); any place that shows or uses a current weight or waist that is not the single resolver's value. Run `swift test` in `Packages/StrandAnalytics` and `Packages/WhoopStore` freely. Write findings to `build/superapp-coordination/review/stage-1.md`, ranked by severity, each with file and line, the concrete input or state, the wrong result, and whether you confirmed it by running something. Report nothing you cannot make concrete. An empty list is a valid result.
- **C2, C3, C4, implement pure logic** for stages 5, 6 and 3 in `Packages/StrandAnalytics`, once the board shows them `todo`. The tests are already written by the Claude session and each test file begins with "API ASSUMED BY THESE TESTS": implement exactly that API and make the tests pass without editing them. Pure Swift only: no `Date()`, no `Calendar.current`, no `TimeZone`, no clock, no UIKit or SwiftUI; "today" and every day arrive as `yyyy-MM-dd` strings; never throw or trap on any input; missing data is "not measured", never zero. Use the shared helpers the specification names (`CanonicalDay`, `ChargeTypicalBand`) rather than writing your own. Run `swift test --filter <YourTypes>` and then the whole package's tests, and `python3 Tools/doc_comment_lint.py`. Then break each rule and threshold on purpose, one at a time, and record which test fails; a fault no test catches is a finding for the hand-off note.
- **C5, write tests** for stage 2's app-side assembler and stage 4's app-side stores, from the specifications, before the Claude session implements them. New files under `StrandTests/` only, each beginning with an "API ASSUMED BY THESE TESTS" block. You cannot compile them (no app build); parse-check each with `swiftc -parse` and say so.

## Handing off

When a lane is done, write `build/superapp-coordination/handoff/<lane>.md` as COLLABORATION.md section 5 describes (branch and commits; what you built; exact commands and results with counts; every place the specification did not match the code or the tests; what you did not verify), set the lane's state to `ready for review` on the board, and take the next `todo` lane. If nothing is `todo`, stop and say so. Commit messages are English with the repository's prefixes and end with `Co-Authored-By: Codex <noreply@openai.com>`.

When something is ambiguous, do not guess silently: take the reading most consistent with the rulings, mark it in a comment, and list it in the hand-off note. The Claude session rules on it in the specification.
