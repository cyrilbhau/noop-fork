# Health super-app: status and hand-off

Written 12 November 2026 by the Claude session that ran the workstream, for whoever continues it (a
new Claude session or Codex). Read this first, then [COLLABORATION.md](COLLABORATION.md) and
[specs/RULINGS-ADDENDUM.md](specs/RULINGS-ADDENDUM.md).

## Where everything is

Every stage is built, reviewed and pushed as a **draft pull request**. Each pull request targets the
branch below it, so nothing reaches `personal/iphone-baseline` until the owner merges the stack from
the bottom. Nothing has been merged into the baseline. Nothing has been installed on the phone.

| PR | Branch | Targets | What |
|---|---|---|---|
| #2 | `personal/superapp-0-foundation` | `personal/iphone-baseline` | Plan, local gate script, baseline record |
| #3 | `personal/superapp-1-scorecard` | #2 | Stage 1 weigh-in and scorecard, all specifications, design source, shared scaffolding |
| #9 | `personal/superapp-1-reminder-race` | #3 | Fix: the latest weekly-reminder choice always wins |
| #4 | `personal/superapp-1b-labbook-ownership` | #3 | A removed strap never deletes or hides Lab Book readings |
| #5 | `personal/superapp-2-coach-packet` | #4 | Stage 2 coach packet |
| #6 | `personal/superapp-3-app` | #5 | Stage 3 protein and intake (quick-add path) |
| #7 | `personal/superapp-4-app` | #5 | Stage 4 body record |
| #8 | `personal/superapp-5-app` | #5 | Stage 5 events |
| #10 | `personal/superapp-integration` | #5 | Stages 3, 4, 5 merged together, plus #9 and later fixes |
| #11 | `personal/superapp-6-app` | #10 | Stage 6 niggle log, recovery context, timeline |
| #12 | `personal/superapp-packet-v2` | #11 | Coach packet version 2 (intake and events sections) and all strings |
| #13 | `personal/superapp-codex-tests` | #12 | Codex's independent app tests for stages 2 and 4 |

`personal/superapp-codex-tests` (the top of the stack) contains everything.

Every new feature is behind its own setting, **off by default**. The one change that is always on is
Lab Book ownership (#4), because it protects stored data; it changes no stored row on upgrade.

## Verification on the top of the stack

- Gate (`bash Tools/personal/gate.sh --waive android`): the same four failing checks as the untouched
  baseline in [BASELINE.md](BASELINE.md), nothing new. Android is waived by the owner's decision.
- `StrandTests`: all 407 classes ran, about 3,830 tests. The only failures are the 5
  `BugReportTemplateTests` listed in the baseline.
- Packages: StrandAnalytics about 2,890, WhoopStore 788, StrandImport 382; all pass.
- Every stage had tests written before its implementation by a separate agent, at least one
  adversarial review with every finding verified by an independent agent, and fault injection on its
  pure logic. Codex (a different model) reviewed stages 1 to 5 and Lab Book ownership; all eight of
  its confirmed findings are fixed.
- Before every push, every added line was scanned against the owner's private profile. No personal
  value is in any branch.

**Not verified:** anything on the phone; a rehearsal on a copy of the owner's real database;
interaction by tapping (flows were driven through the models in the simulator); Kotlin (skipped by
the owner's decision); translations (machine-written, not reviewed by native speakers); the design
frames for stages 2 to 6 (built to the owner's approved direction, not yet reviewed in Figma).

## What the owner still has to do

1. **Export the WHOOP history archive before 19 November 2026.** It cannot be redone later.
2. **Make a fresh backup** from the phone, for the rehearsal below.
3. **Stage 3:** say which food app is used and whether NOOP may read dietary protein and energy from
   Apple Health. Until then stage 3 ships with quick-add only.
4. **Review the design frames** for stages 2 to 6 in Figma (pages "Stage 2" to "Stage 6" and
   "Combined"; import commands are in the plugin) and give edits.
5. **Merge the pull requests** from the bottom of the stack when satisfied.

## What happens next, in order

1. **Real-data rehearsal.** Restore the owner's backup into a disposable simulator, run the Lab Book
   ownership repair and each stage against it, and compare. Codex lane C18 is writing the procedure
   as `REHEARSAL.md`. Never restore over the working install.
2. **Rollout, one stage at a time** (the owner's decision). One build carrying all the code is
   installed on the phone after a fresh backup and with the owner's go-ahead in that conversation;
   every feature stays off. The owner then switches on one stage at a time and accepts it with the
   checklist in `ACCEPTANCE.md` (Codex lane C17). Suggested order: Lab Book ownership (always on),
   scorecard, coach packet, intake, body record, events, niggle log and timeline.
3. **After each acceptance:** annotated tag `checkpoint/YYYY-MM-DD-superapp-<stage>`, and update
   `docs/personal/CONTEXT.md`.

## Open items

- Codex round 3 lanes C11 to C19 (see `build/superapp-coordination/BOARD.md`, outside Git):
  reviews of stage 6 and packet v2, whole-line sweeps for privacy, flag-off equivalence and
  one-number-per-variable, property tests, the acceptance and rehearsal documents, an accessibility
  audit. Fix confirmed findings test-first on the branch where they belong and merge forward.
- Two device-free indexes on `labMarker` would speed large Lab Books (ruling A15). It is a
  migration and waits for the owner's go-ahead.
- Stage 3 Path A (Apple Health reads) waits for the owner's yes.
- The parity ledger cannot be refreshed without the owner's decision (pre-existing).

## How to work here

- The coordination folder `build/superapp-coordination/` (board, locks, hand-offs, reviews) is
  outside Git in the main folder.
- The local gate is the evidence; CI does not run on this fork.
- If the Mac's screen is locked, `xcodebuild test` hangs. Build with `build-for-testing` and run each
  class with `/Applications/Xcode.app/Contents/Developer/usr/bin/xctest`, setting
  `DYLD_FRAMEWORK_PATH` and `DYLD_LIBRARY_PATH` to the DerivedData `Build/Products/Debug`; the 14
  classes that need the running app then need an unlocked session.
- Before any push: scan the added lines against the private profile, as every push so far has been.
