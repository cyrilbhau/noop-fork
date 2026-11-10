# Health super-app: orchestration

Written 10 November 2026. How the work in [ROADMAP.md](ROADMAP.md) is divided between one
orchestrating session and the subagents it starts.

## Principle

The main session is the **orchestrator**. It holds the plan, talks to the owner, starts subagents,
checks what they return and owns every gate. It writes little code itself. Subagents do bounded
pieces with a brief that stands on its own.

Spare capacity is best spent on **verification**: independent test authors, several reviewers,
oracle runs, simulator passes over every state. It is poorly spent on running more features at once,
because the stages share a handful of files and a single phone.

## Roles

| Role | Does | Writes files | Context it needs |
|---|---|---|---|
| **Orchestrator** | Plans, briefs, merges, runs the gate script, reports to the owner, owns gates | Specs, docs, merges | Everything |
| **Explorer** | Read-only survey: where a fact is read and written, what a table's writers are, how a workflow invokes a check | None | The question and the search breadth |
| **Spec writer** | Turns a roadmap stage and an Explorer's findings into the G0 specification | One spec file | Roadmap stage, findings, constraints |
| **Designer** | Builds the HTML frames, exports them, imports to Figma by computer use | `design/roundN-*`, plugin | Design rules, the state list, the Figma procedure. Runs in the main session if subagents lack computer use. |
| **Test author** | Writes tests from the specification and fixture, without seeing the implementation | Test files only | Spec, fixture, test conventions of the target package |
| **Implementer** | Implements one work package to make the committed tests pass | The files named in its brief | Spec, the tests, the files it owns |
| **Parity agent** | Writes the Kotlin twin, builds the standalone Swift oracle, pastes its output as Kotlin expectations, adds the reverse test | `android/...`, oracle script | Spec, the Swift implementation, [AGENTS.md](../../../AGENTS.md) parity section |
| **Localiser** | Adds strings for all locales | `Localizable.xcstrings` only | The new English strings and their context |
| **Reviewer** | Tries to break the change; one lens per reviewer | None | Spec and diff, not the implementer's explanation |
| **Verifier** | Builds, runs suites, runs the simulator, captures screenshots, runs fault injection | Evidence files only | Gate list, approved frames |

## Rules

1. **A report is a claim.** The orchestrator reads the diff and reruns the gate script before
   telling the owner anything is done. It never predicts or invents a subagent's result.
2. **One writer per file.** No two running subagents may edit the same file. The table below names
   the files that only one role may touch.
3. **Worktrees for writers.** Each writing subagent works in its own Git worktree on a sub-branch.
   The orchestrator merges into the stage branch in dependency order.
4. **Briefs stand alone.** A subagent starts with none of this conversation. Its brief names the
   goal, the files, the constraints, what done looks like and what to return.
5. **Tests and implementation come from different agents.** The implementer may not change the
   tests. Disagreement goes back through the orchestrator.
6. **Reviewers are fresh.** A reviewer has not seen the implementation being written.
7. **Owner gates are never delegated.** No subagent approves a design, merges into the baseline
   branch, or installs on the phone.
8. **Private data stays private.** Briefs do not quote the owner's measurements. A subagent that
   needs the real numbers (rare; mostly the real-data rehearsal) is pointed at the private profile
   path and told that nothing from it may be written to a tracked file, a commit message or a
   pull request.
9. **Outside actions belong to the orchestrator, and some need the owner.** Only the orchestrator
   pushes branches and opens pull requests; it may do both without asking. Merging into the
   baseline, installing on the device, changing settings on the Mac and installing software each
   need the owner's yes, every time. Subagents do none of these.
10. **Long commands run in the background.** Builds and full suites exceed two minutes.
11. **Subagents are standing policy.** The owner has asked for subagents throughout this workstream.
    The orchestrator spawns them as the roadmap's work packages call for, without asking each time.
12. **Start, do not wait.** The first session begins stage 0 tooling and stage 1 specification,
    design frames, tests and pure logic together. Only interface code waits for design approval.

## File ownership

These files are touched by almost every stage. They have exactly one writer at a time.

| File or area | Sole writer | Why |
|---|---|---|
| `Strand/Resources/Localizable.xcstrings` | Localiser, once per stage, after the English strings are final | A large generated catalogue; parallel edits conflict badly |
| `project.yml` | Orchestrator | The project definition; then `xcodegen generate` |
| Marker catalogue (Swift and Kotlin) | Parity agent | A byte-identical contract |
| `Packages/WhoopStore/.../Database.swift` migrations | One implementer, only in a stage that planned a migration | Never edited in parallel, never edited retroactively |
| Backup settings whitelist (Swift and Kotlin) | Parity agent | A byte-identical contract |
| Changelog and "what's new" | Orchestrator, at the end of the stage | Avoids a conflict per work package |
| `docs/personal/CONTEXT.md` | Orchestrator, at G8 | The installed-state authority |
| Widget payload types in `StrandiOSShared/` | One implementer per stage | Additive, optional fields only |

## Parallelism map

What may run at the same time within a stage:

```
G0  Explorer ──► Spec writer
                    │
        ┌───────────┼──────────────────┐
G1      Designer    │                  │
        (owner      G2 Test author     │
        approval)   │                  │
        │           G3 Implementer A (pure logic) ──► Parity agent
        │           G3 Implementer B (storage / resolver)
        │                              │
        └──────────► G3 Implementer C (screens)   ← needs G1 approved and A, B merged
                                       │
                                  Localiser
                                       │
                 G4 gate script (orchestrator)
                                       │
        G5 Reviewers (2–3, in parallel)   G6 Verifier (parallel with G5)
                                       │
                                  G7  PR ──► G8 device
```

- Design and pure-logic work overlap. Interface code waits for the design.
- Reviewers and the Verifier run together once the gate script is green.
- Stages themselves do not overlap, with one exception: stage 0's owner field work runs alongside
  everything.

## Brief templates

Fill every bracket. Remove nothing.

### Explorer

```
Read-only task in the repository at [path]. Do not edit files.

Question: [one precise question].
Search breadth: [medium | very thorough].
Look in: [directories], and anywhere else the naming suggests.

Return:
- Every relevant location as path:line with one line on what it does.
- Anything that contradicts the assumption "[assumption]".
- What you could not determine, stated plainly.
Do not summarise files you did not open.
```

### Test author

```
Write tests only. Do not write or read the implementation of [type]; it does not exist yet or you
must not look at it.

Specification: [path to spec, section].
Fixture: [path]. Use only synthetic values. Never use real personal data.
Target: [package or test bundle], following the conventions of [neighbouring test file].

Cover every case in the specification's test plan, one named test per case. Add cases you find
missing and list them in your report. Tests must fail now for the right reason (the type or
behaviour is absent), not because of a typo.

Files you may create or edit: [list]. Touch nothing else.
Run: [command]. Report the exact output, including failures.
Return: the list of tests, the added cases, and anything in the specification that was ambiguous.
```

### Implementer

```
Implement work package [id]: [one sentence].

Specification: [path, section]. Tests already committed at [paths]; make them pass. Do not edit
them. If you believe a test is wrong, stop and say why.

Files you own: [list]. Touch nothing else. In particular do not edit Localizable.xcstrings,
project.yml, the marker catalogue or any migration.

Constraints:
- [Layer rule: no UIKit/AppKit/CoreBluetooth under Packages/.]
- [Design tokens only: StrandPalette, StrandFont, shared components.]
- [Shared sources must compile for both NOOPiOS and the macOS Strand target.]
- [New surface behind the default-off setting [key].]
- [Missing data is "not measured", never zero.]
- [This fact has one resolver: [function]. Do not read it any other way.]

Work in the worktree at [path] on branch [name]. Commit when the tests pass. Do not push.
Run: [commands]. Report exact output.
Return: what you changed, what you ran and its result, what you did not verify, and any place where
the specification did not match the code you found.
```

### Parity agent

```
Produce the Kotlin twin of [Swift type] at [path] and prove the two agree.

1. Write the Kotlin implementation at [path], following the neighbouring Android code.
2. Compile the Swift implementation standalone and run it over [the fixture and a generated spread
   of N cases]. Save the script.
3. Paste the oracle's output verbatim as the expected literal in the Kotlin test.
4. Add the matching direction on the Swift side so Swift cannot drift.
5. Run the Android unit tests with [command]. If the toolchain is missing, do not claim a pass:
   report "written, not executed".

Do not reason that the two look the same. Only the oracle counts.
Return: files, the oracle command, the outputs, and the execution status of each side.
```

### Reviewer

```
Review a change you did not write. Your lens: [correctness | repository contract | data safety].

Specification: [path]. Diff: [how to obtain it]. Do not ask for the author's reasoning.

[Correctness] Try to construct inputs that produce a wrong result, a crash, or a value shown as
measured when it is not. Run code to confirm each suspicion.
[Contract] Check against AGENTS.md: parity, migrations, design tokens, single resolver, no medical
claims, English text, one concern. Check that no personal measurement appears anywhere in the diff.
[Data safety] Find any path by which existing stored history could be lost, overwritten,
double-counted or left unreadable, including on upgrade from the installed version.

Return findings ranked by severity. For each: file and line, the concrete failing scenario, and
whether you confirmed it by running something. Report nothing you cannot make concrete.
```

### Verifier

```
Verify stage [N] on branch [name]. Do not change product code.

1. Run the gate script [path]. Report its full summary table. Compare with BASELINE.md and separate
   pre-existing failures from new ones.
2. Fault injection: for each rule in [list], change the threshold or condition, confirm a test
   fails, then restore the file. Report which tests caught which fault. A fault nothing catches is a
   finding.
3. Build and launch the iPhone app in the simulator with synthetic data. Reproduce each approved
   frame in [list]. Capture default and largest text size, Reduce Motion on and off.
4. Exercise each flow by interaction: [list].

Return: the tables, the screenshot paths, every difference from the approved frames, and everything
you could not check.
```

## Reporting to the owner

At the end of each working session the orchestrator reports:

- Which gate each active stage has reached.
- What was verified, by which evidence.
- What was not verified.
- What is waiting on the owner, as short questions.

It does not report a stage as done before G8.
