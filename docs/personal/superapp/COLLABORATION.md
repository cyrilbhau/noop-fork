# Health super-app: two agents, one repository

Written 11 November 2026. The owner asked for every remaining stage to be built now, in parallel, and
offered a second coding agent (Codex, on the owner's ChatGPT subscription) alongside the Claude
session that has run the workstream so far. This document is the contract between the two. Both
agents read it before touching anything. It adds to [ORCHESTRATION.md](ORCHESTRATION.md) and
[QUALITY-GATES.md](QUALITY-GATES.md); where it is stricter, it wins.

## 1. Who does what

| | Claude session | Codex session |
|---|---|---|
| Role | **Integrator.** Holds the plan, owns every stage branch, every merge, every gate and all talk with the owner about decisions | **Builder and independent checker.** Owns the lanes assigned to it in §6, end to end, on its own branches |
| Merges into a stage branch | Yes, and only Claude | Never |
| Edits a hot file (§4) | With the lock | With the lock, and only when its lane's brief names the file |
| Pushes, opens pull requests | No. The owner decided the work stays local | No |
| Installs on the phone, changes Mac settings, installs software | No, without the owner's yes in that conversation | No |

The most valuable use of a second model is **independence**: tests for code the other agent wrote,
and review of the other agent's diff. A lane therefore names which agent writes the tests and which
writes the implementation, and they are never the same agent.

## 2. Rules both agents follow

1. **Local only.** The GitHub repository is public. Nothing is pushed and no pull request is opened
   unless the owner says so in words.
2. **Private data stays private.** The owner's real measurements are in the ignored
   `PersonalData/superapp/OWNER-PROFILE.md`. Nothing from it goes into a tracked file, a test, a
   commit message, a screenshot or a prompt. **Codex does not open that file at all** unless the
   owner tells it to: reading it would send the owner's health data to a second provider, and that
   is the owner's decision, not an agent's. Everything Codex needs is in the specifications, which
   use a fictional fixture person.
3. **The specification is law.** Each stage has one under `docs/personal/superapp/specs/`. The
   rulings at the end of `stage-1.md` (R25 to R43) bind every stage. If the code or a test
   contradicts the specification, stop on that item and write it in the hand-off note; do not pick
   silently.
4. **Tests first, by the other agent.** Tests are written from the specification before the
   implementation and are not edited by the implementer.
5. **Flag off is sacred.** Every new surface sits behind a default-off setting. With it off the app
   behaves exactly as before the feature.
6. **The owner's data is never at risk.** No change deletes, overwrites, re-keys or hides a stored
   row or a setting except by the owner's explicit edit or delete. No migration, wider Health
   access, new build target, entitlement or network path without the owner's yes.
7. **Owner decisions already made:** one number per variable throughout the app (R41); a strap
   being gone never deletes or hides the owner's readings (R42); no Android work, so no Kotlin
   (R43).
8. **A report is a claim.** Whoever integrates reads the diff and reruns the checks.

## 3. Where each agent works

- One Git worktree per lane, never the main checkout (it holds another session's uncommitted work)
  and never another lane's worktree.
- Claude's worktrees: `.claude/worktrees/superapp-*`. Codex's worktrees:
  `.claude/worktrees/codex-<lane>`, created with
  `git worktree add -b personal/codex/<lane> .claude/worktrees/codex-<lane> <base>` where `<base>`
  is the commit the lane's row in §6 names.
- Branch names: Claude `personal/superapp-…`; Codex `personal/codex/<lane>`. An agent commits only
  to its own branches.
- **Builds.** Each agent uses its own DerivedData inside its own worktree's ignored `build/`
  directory, and its own simulator device (Codex creates one named "NOOP Codex Verify"). Neither
  resets, deletes or reuses the other's. Disk is limited: one DerivedData tree per agent, and
  delete scratch products.
- Commit messages are English, one purpose each, with the prefixes in the history (`feat:`, `fix:`,
  `test:`, `docs:`, `design:`, `chore:`). Codex ends its messages with
  `Co-Authored-By: Codex <noreply@openai.com>`.

## 4. Hot files and the lock

These files are edited by almost every stage. Two agents editing one at the same time produce
conflicts that are expensive to untangle, so each has exactly one writer at a time.

| File | Why |
|---|---|
| `Strand/Resources/Localizable.xcstrings` | A large generated catalogue. Claude's Localiser is the sole writer; Codex lists its new English strings in the hand-off note and does not touch the file |
| `Strand/Screens/DashboardCards.swift`, `Strand/Data/TodayCardReadout.swift` | The Today card registry |
| `Strand/Screens/SettingsView.swift` | Every stage adds a row |
| `Strand/Liquid/LiquidTodayView.swift`, `Strand/Screens/TodayView.swift`, `StrandiOS/Redesign/RedesignTodayView.swift` | The three Today variants |
| `StrandiOS/App/StrandiOSApp.swift`, `StrandiOS/App/RootTabView.swift` | App entry, the debug demo block, scene-phase hooks |
| `Packages/StrandImport/Sources/StrandImport/MarkerCatalog.swift` | The marker catalogue |
| `Packages/WhoopStore/Sources/WhoopStore/Database.swift`, `BackupSettings.swift`, `DeviceRegistryStore.swift` | Stored-data contracts |
| `Strand/AI/AICoach.swift` | The Coach context |
| `project.yml` | Claude only |

**The lock** is a plain file outside every branch, so both agents see the same copy whatever they
have checked out: `/Users/cyrilbhau/Documents/Noop/noop-fork/build/superapp-coordination/LOCKS.md`
(`build/` is ignored by Git).

- To take a lock, append one line: `<file> | <agent> | <lane> | <UTC time> | <what for>`, then
  re-read the file. If another line for the same file was there first, remove yours and wait.
- Hold a lock for one commit's worth of work, release it by deleting your line, and say so in the
  board.
- A lock older than four hours with no matching recent commit is stale: write a note in the board
  and ask the owner before taking it.

## 5. The board and hand-offs

Same directory, also outside every branch:

- `BOARD.md` — one row per lane: lane, agent, branch, base commit, state (`todo`, `tests`,
  `building`, `ready for review`, `changes requested`, `merged`), and a one-line note. Each agent
  updates its own rows when the state changes and reads the whole board at the start of every
  working session.
- `handoff/<lane>.md` — written by the builder when a lane is ready for review. It contains: the
  branch and commit range; what was built, file by file; the exact commands run and their results
  with counts; every new or changed user-facing English string; every place the specification did
  not match the code; what was **not** verified; and any hot-file lock still held.
- `review/<lane>.md` — written by the reviewer: findings ranked by severity, each with file and
  line, the concrete failing input or state, and whether it was confirmed by running something.

A lane is done when the integrator has merged it. Until then it is a claim.

## 6. Lanes

Filled in by the integrator once the specifications for the remaining stages and their cross-stage
check are in. Each row names the specification section, the base commit, the files the lane owns,
who writes its tests and who writes its implementation.

| Lane | Stage | Tests by | Implementation by | Base | State |
|---|---|---|---|---|---|
| — | — | — | — | — | Lanes are assigned in `BOARD.md` |

## 7. Checks before a hand-off

Run from the lane's worktree and paste the summary table into the hand-off note:

```
bash Tools/personal/gate.sh --waive android --compare docs/personal/superapp/BASELINE.md
```

A failure that is in [BASELINE.md](BASELINE.md) is named as pre-existing. Anything else blocks the
hand-off. A check that could not run is reported as not run, never as passed. If the lane has pure
logic with a rule or a threshold, break each one on purpose and record which test fails.

## 8. When the two agents disagree

Neither overrules the other. The disagreement goes in the hand-off or review note with the evidence,
and the integrator rules in the specification, as stage 1's rulings were made. If the ruling would
change a decision the owner made, the integrator asks the owner.
