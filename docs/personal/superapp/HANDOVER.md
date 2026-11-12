# Health super-app: handover for the next agent

Written 12 November 2026 by the Claude session that planned and built the workstream. Development
is complete; what remains is validation on the owner's phone and rollout, which another harness will
run. This document is self-contained. Read it first, then the documents it points to.

## 1. What this is

A personal iPhone fork of NOOP, an on-device companion app for WHOOP straps. The installed app holds
the **only copy** of the owner's health history. The workstream turns it into the home for a
multi-year body-recomposition project: a weekly weigh-in and scorecard, a clean data hand-off to a
coach, protein tracking, a body record, an events layer, a niggle log, a recovery-context view and a
checkpoint timeline. Coaching judgement stays outside the app.

The owner's real measurements, targets and rules are in an **ignored** file,
`PersonalData/superapp/OWNER-PROFILE.md` (only in the checkout where it was placed). The GitHub
repository `cyrilbhau/noop-fork` is **public**. Nothing personal may enter a tracked file, a commit
message, a pull request, a screenshot or a prompt to a third-party service.

## 2. State at hand-over

**All development is done and pushed as stacked draft pull requests.** Nothing is merged into
`personal/iphone-baseline` (still at `85fc5329`). Nothing has been installed on the phone.

| PR | Branch | Base | Content |
|---|---|---|---|
| #2 | `personal/superapp-0-foundation` | `personal/iphone-baseline` | Planning set, local gate script, baseline record |
| #3 | `personal/superapp-1-scorecard` | #2 | Stage 1 weigh-in and scorecard; every specification; design sources; shared scaffolding |
| #9 | `personal/superapp-1-reminder-race` | #3 | Fix: the latest weekly-reminder choice wins |
| #4 | `personal/superapp-1b-labbook-ownership` | #3 | A removed strap never deletes or hides Lab Book readings |
| #5 | `personal/superapp-2-coach-packet` | #4 | Stage 2 coach packet |
| #6 | `personal/superapp-3-app` | #5 | Stage 3 protein and intake (quick-add path) |
| #7 | `personal/superapp-4-app` | #5 | Stage 4 body record |
| #8 | `personal/superapp-5-app` | #5 | Stage 5 events |
| #10 | `personal/superapp-integration` | #5 | Stages 3 to 5 merged, plus #9 and later fixes |
| #11 | `personal/superapp-6-app` | #10 | Stage 6 niggle log, recovery context, timeline |
| #12 | `personal/superapp-packet-v2` | #11 | Coach packet version 2 (intake and events) and all strings |
| #13 | `personal/superapp-codex-tests` | #12 | Independent tests and every later fix |

**`personal/superapp-codex-tests` is the canonical tip: it contains everything.** Build, test and
install from it. The pull requests below it exist for review; their descriptions record what was
verified at the time each was pushed, and some later fixes live only further up the stack.

Every new feature is behind its own setting, **off by default** (`noop.cutScorecardEnabled`, the
coach packet, intake, body record, events, and three stage 6 settings). With all of them off the app
behaves as the baseline, verified by an independent sweep. The one always-on change is Lab Book
ownership, which protects stored data and changes no stored row on upgrade.

## 3. Verification at the tip

- `bash Tools/personal/gate.sh --waive android --parity-cmd 'bash Tools/personal/cut_scorecard_oracle.sh' --compare docs/personal/superapp/BASELINE.md`:
  the same four failing checks as the untouched baseline, nothing new.
- `StrandTests` hosted: 3,855 tests; the only failures are the 5 `BugReportTemplateTests` in
  `BASELINE.md`. Packages: StrandAnalytics 2,912, WhoopStore 788, StrandImport 384, all passing.
- Method used throughout: specification first; tests written by a separate agent before the
  implementation; adversarial reviews with every finding checked by an independent agent before
  acting; fault injection on pure logic; Codex (a different model) reviewed every stage and swept the
  whole line for privacy, flag-off equivalence and one-number-per-variable. Every confirmed finding
  is fixed with a test written first.

**Not verified:** anything on the phone; a rehearsal on a copy of the owner's real database;
interaction by tapping (flows were driven through the models in the simulator); VoiceOver by ear;
Kotlin (skipped by the owner, see §6); translations (machine-written); the design frames for stages
2 to 6 (built to the approved direction, not yet reviewed by the owner).

## 4. What the owner must do

1. **Export the WHOOP history archive before 19 November 2026.** It cannot be redone afterwards.
2. **Make a fresh backup** from the phone before any rehearsal or install.
3. **Stage 3:** say which food app is used and whether NOOP may read dietary protein and energy from
   Apple Health. Until then stage 3 runs with quick-add only (§6).
4. **Review the design frames** for stages 2 to 6 (§8) and give edits.
5. **Merge the pull requests** from the bottom of the stack when satisfied.

## 5. What the next agent does, in order

1. **Real-data rehearsal**, following [REHEARSAL.md](REHEARSAL.md) (on the tip branch): restore the
   owner's backup into a disposable simulator, never the working install; keep the copy under
   `PersonalData/`; run the Lab Book ownership repair and each stage against it; compare row counts.
   Results stay private.
2. **Install** one build carrying all the code, after a fresh backup and with the owner's explicit
   go-ahead in that conversation. Every feature stays off. Follow `docs/personal/INSTALL.md` and
   `docs/personal/DEVICE-TESTING.md`. The signed build needs `Config/BundleIdSecrets.xcconfig`, an
   ignored file that exists only in the main checkout; never uninstall the app.
3. **Roll out one stage at a time** (the owner's decision): the owner switches one stage on and
   accepts it with [ACCEPTANCE.md](ACCEPTANCE.md). Suggested order: Lab Book ownership (already
   on), scorecard, coach packet, intake, body record, events, niggle log and timeline.
4. **After each acceptance:** an annotated tag `checkpoint/YYYY-MM-DD-superapp-<stage>` (never move
   an existing tag) and an update to `docs/personal/CONTEXT.md`.
5. **Coach side:** give the owner `docs/personal/superapp/coach-side/PACKET-V2-CLAUDE-SIDE.md` to
   paste into their coaching document once the packet is in use.

## 6. Decisions already made (do not reopen without the owner)

- **Hevy stays** the lifting logger; **Claude is the coach**; the app hands data over, it does not
  coach.
- **One number per variable** throughout the app (ruling R41): every current weight, waist and
  protein figure comes from one resolver and offers a way to correct it.
- **A strap being gone never deletes or hides the owner's readings** (R42).
- **No Android work** (R43): Kotlin twins that exist were never compiled; shared logic records a
  written disposition instead.
- **Stage 3 Path A** (Apple Health dietary reads) waits for the owner's yes; the code has one switch
  for it and adds no Health read today.
- Events are a settings list carried in the backup: **no database migration** anywhere in this
  workstream. Two device-free indexes on `labMarker` would speed large Lab Books; that is a
  migration and needs the owner's go-ahead (A15).
- The two clipboard paths that predate the workstream (copying a Coach reply, copying diagnostics)
  are unchanged; hardening them is recommended to the owner as a separate change (A28).
- Stages are built first and introduced to the phone one at a time (owner, 12 November).

All rulings: stage 1 specification §18 (R25 to R44) and
[specs/RULINGS-ADDENDUM.md](specs/RULINGS-ADDENDUM.md) (A1 to A29). They override earlier
specification text.

## 7. Rules for working here

- **Never** commit to or push `personal/iphone-baseline`; never merge into it. The owner merges.
- **Before every push**, run the privacy scan and read any masked hit:
  `python3 -I Tools/personal/privacy_scan.py <base>..<branch>` (needs the private profile in
  `PersonalData/`, and optionally an ignored `PersonalData/superapp/private-words.txt` with one
  private word per line; never put that list in a tracked file). Every push so far has passed it.
- Ask the owner, every time, before: installing on the phone; merging; widening Apple Health access;
  adding a migration, build target, entitlement or network path; installing software on the Mac;
  changing CI workflows. An earlier yes does not carry over.
- Never restore a backup over the working install, never uninstall the app, never wipe the phone.
- Missing data is "not measured", never zero; no medical claims; design tokens only; with a
  feature's setting off, the app is exactly as before.
- Commits: English, one purpose each, prefixes from the history (`feat:`, `fix:`, `test:`, `docs:`,
  `design:`), no issue-closing keywords.

## 8. Where things are

| What | Where |
|---|---|
| Specifications | `docs/personal/superapp/specs/` (stage-1 to stage-6, labbook-ownership, RULINGS-ADDENDUM) |
| Plan and gates | `docs/personal/superapp/` README, CONTEXT, ROADMAP, QUALITY-GATES, ORCHESTRATION |
| Baseline test record | `docs/personal/superapp/BASELINE.md` |
| Acceptance checklists, rehearsal | `ACCEPTANCE.md`, `REHEARSAL.md` (on the tip branch) |
| Design sources | `design/round6-scorecard/` (stage 1, approved), `design/round-s2-…` to `round-s6-…`, `design/round-combined/` |
| Figma import | `design/tools/serve.py --export <round>/index.html --name <file>`, then the "NOOP design tools" plugin in Figma (Plugins, Development). The plugin Figma has registered lives in the worktree `noop-design-overhaul-3b7185`; its commands for the new rounds are added there, uncommitted |
| Gate script | `Tools/personal/gate.sh` (`--help`) |
| Parity oracle for the scorecard | `Tools/personal/cut_scorecard_oracle.sh` |
| Two-agent contract and board | `COLLABORATION.md`; the live board, reviews and hand-offs are in `build/superapp-coordination/` in the main folder (outside Git) |
| Codex kickoff prompt | `CODEX-KICKOFF.md` |

## 9. Practical notes

- **The main checkout holds another session's uncommitted work** (state-machine changes from
  9 November). Do not touch it; work in a worktree.
- **CI does not run on this fork**: every workflow triggers only on `main`. The local gate is the
  evidence.
- **Locked screen:** `xcodebuild test` hangs ("test runner hung before establishing connection").
  Build with `build-for-testing`, then run each class with
  `/Applications/Xcode.app/Contents/Developer/usr/bin/xctest` (not through `xcrun`, which strips the
  variables), with `DYLD_FRAMEWORK_PATH` and `DYLD_LIBRARY_PATH` set to the DerivedData
  `Build/Products/Debug`. About 14 classes need the running app and only run hosted, unlocked.
- **Disk is tight** on this Mac. A DerivedData tree is about 5 GB; keep one per active worktree and
  delete finished ones. `Tools/personal/ios.sh build` hard-codes `build/personal/fork-derived`.
- **zsh** treats `:r` in a refspec as a modifier; push with plain branch names.
- `git` in a fresh worktree may lack remote-tracking refs for these branches; fetch the branch
  explicitly before computing a range.
- The test-bundle catalogue: per-class `xctest` runs load no app string catalogue, so a wrong string
  key only shows in a hosted run.
