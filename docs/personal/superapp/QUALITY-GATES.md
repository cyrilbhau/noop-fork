# Health super-app: quality gates

Written 10 November 2026. Every stage in [ROADMAP.md](ROADMAP.md) passes these gates in order. A gate
is passed when its evidence exists, not when someone reports that it passed.

## Gate sequence

| Gate | Name | Who passes it | Evidence |
|---|---|---|---|
| G0 | Specification | Orchestrator, after an Explorer and a Spec writer | `docs/personal/superapp/specs/stage-N.md`, committed |
| G1 | **Design approved in Figma** | **The owner** | Frame names and the approval date recorded in the specification |
| G2 | Tests written first | Test author | Failing tests committed on the stage branch |
| G3 | Implementation | Implementers | Commits per work package |
| G4 | Local gate script green | Orchestrator runs it | Script output pasted into the pull request |
| G5 | Adversarial review | Reviewers with fresh context | Findings list with each one fixed or answered |
| G6 | Simulator verification | Verifier | Screenshots from synthetic data beside the approved frames |
| G7 | Pull request merged | Owner approves the merge | PR link |
| G8 | Device acceptance and checkpoint | **The owner** | Acceptance notes; annotated tag |

No gate is skipped. If a gate cannot be passed, work stops and the owner is told why.

Three gates belong to the owner alone: G1, the merge in G7, and G8. The session never passes them on
the owner's behalf and never treats silence as approval.

---

## G0 — Specification

Before design or code, a short written specification per stage:

- The goal in one sentence, and what is out of scope.
- A re-check of every "what exists" row the stage relies on, with file paths and line numbers as
  they are now.
- Final names for types, functions, storage keys and settings.
- Every existing reader or writer of any fact the stage touches. This is where "two readouts of one
  fact" is caught.
- The complete list of states each screen can be in.
- The test plan from the roadmap, extended with anything the code reading revealed.
- Open questions for the owner, each with a recommendation.

The specification contains no personal measurements. Examples use the synthetic fixture.

## G1 — Design approved in Figma

**No implementation code is written for a stage until the owner has approved its frames.** Pure
logic with no interface (for example the scorecard function) may be specified and tested while
design is in progress, because it does not depend on layout.

### What a design submission contains

For every screen in the stage:

- The default state with realistic synthetic values.
- First use with no data. Loading skeleton. Stale or failed data. Every state listed in G0.
- The largest accessibility text size.
- Each widget in each supported size, with and without data.
- Notification text, written out.
- Where the owner must choose (for example screen placement), each option as its own frame.

Each frame is checked against the design rules in [CONTEXT.md](CONTEXT.md) §5 before it is shown:
semantic colour only, no horizontal chart rules or bands, no decorative glow, tokens that exist in
`StrandPalette` and `StrandFont` or a named proposal for a new token.

### How frames reach Figma

The Figma account is on the Starter plan and its MCP call allowance was exhausted in October 2026.
Check whether that has reset; if not, use the local route:

1. Build the screens as HTML using `design/system/noop.css` and `design/system/noop.js`, in a new
   folder beside `design/round1`–`round4`.
2. Open the page with `?static=1` and call `exportSvgFrames(name)`, which writes a frames file for
   the import plugin. It expects a small local file server on port 8765. That server script was
   kept in an earlier session's scratch folder and may need to be written again.
3. The local plugin `design/figma-plugin` ("NOOP design tools") imports the frames. Its commands are
   per round, so add a command for the new round in the plugin's code and manifest.
4. Run the plugin in the Figma desktop app by computer use: Tools in the left rail, Recents, "NOOP
   design tools", Run, then the command. The Tools panel has been observed to lag one screenshot
   behind. SF Pro Display sometimes fails the plugin's font probe and Inter is substituted; say so
   if it happens.
5. Put the frames on a new page named for the round and stage.

The Figma file link is in the private profile. Computer-use access is granted by the owner per
session; ask for it when the stage reaches this gate.

### Approval

- Tell the owner which page and frames to look at and what decisions are being asked.
- The owner approves in words in the conversation, or leaves comments in Figma.
- Changes requested are made in the HTML source, re-exported and re-imported. The HTML in `design/`
  stays the source of truth, so Figma and the repository do not drift.
- On approval, commit the design source as its own commit and record the frame names and date in the
  specification.

## G2 — Tests written first

- The Test author works from the specification and the fixture, without the implementation.
- Tests fail for the right reason before the implementation exists. A test that passes before the
  code is written is examined, not celebrated.
- Each test name states the behaviour it protects.

## G3 — Implementation

- One work package per commit, at minimum.
- Implementers do not edit tests written in G2. If a test is wrong, the Test author changes it and
  the reason is written in the commit message.
- New interface surfaces are behind a default-off setting.
- New code follows the layer rule: byte-level and maths-level logic goes into `Packages/` with no
  UIKit, AppKit or CoreBluetooth imports.

## G4 — Local gate script

CI does not currently run on the fork, so this is the evidence. Stage 0 delivers the script; until
then run the pieces by hand. Take each exact invocation from `.github/workflows/`, because flags
drift.

| Check | What it proves | Source of the invocation |
|---|---|---|
| `xcodegen generate` | The project definition is valid | `project.yml` |
| `swift test` in each touched package | Pure logic and storage | `swift-packages.yml` |
| macOS `Strand` build and `StrandTests` | Shared sources compile for macOS; app-target tests | `app-build.yml` |
| `NOOPiOS` simulator build including widgets | The iPhone app and widget compile | `Tools/personal/ios.sh build` |
| `Tools/doc_comment_lint.py` | No detached doc comments | `source-hygiene.yml` |
| `Tools/i18n_audit.py --ci` | New strings cover every locale | `i18n-coverage.yml` |
| Python unit tests under `Tools/` | Repository acceptance and tooling | `tools-python.yml` |
| `Tools/check_personal_widgets.py` | Personal widget invariants | The script itself |
| Android unit tests | Kotlin twins | `android.yml`; needs JDK 17 and the Android SDK |
| Parity oracle | Swift and Kotlin agree on generated inputs | Per stage |

Rules:

- Compare results against `BASELINE.md`. A failure that is in the baseline is named as pre-existing;
  anything else blocks.
- A check that could not run is reported as **not run**, with the reason. It is never counted as a
  pass. A Kotlin twin that was written but not executed is reported as written and unverified.
- After switching branches, Android runs use `--no-build-cache --rerun-tasks`.
- The `doc_comment_lint` baseline is a per-file count. A failure it prints may point at a line far
  from the edit; look at what was inserted, usually a declaration placed between a neighbour and its
  doc comment.

### What "tested" means here

Every stage shows all of these, or says which is missing and why:

1. **Enumerated cases.** The stage's test plan in the roadmap, one named test per line.
2. **Edge states.** Empty, single, missing, stale, backdated, edited, deleted, time-zone change.
3. **Fault injection.** For each rule or threshold, break it on purpose and confirm a test fails. A
   gate must be able to fail on the change that would break it.
4. **Parity by oracle.** Generated expected values, both directions.
5. **Flag-off equivalence.** With the new setting off, the baseline suite's results are unchanged.
6. **Single-resolver assertions.** Where a fact has several readers, a test asserts they share one
   function.
7. **Privacy scans.** Outputs that leave the app (packet, widget payload, notification text) are
   scanned for identifiers and sensitive kinds.
8. **Real-data rehearsal.** The owner's history in a simulator, privately, before a device install.

## G5 — Adversarial review

At least two reviewers with fresh context, given the specification and the diff but not the
implementer's reasoning:

- **Correctness reviewer.** Tries to construct an input that produces a wrong verdict, a wrong total
  or a crash.
- **Contract reviewer.** Checks the repository rules: parity, migrations, design tokens, single
  resolver, "not measured is not zero", no medical claims, no personal data in the diff.

For a stage that changes stored data or Health access, add a third: **data-safety reviewer**, who
looks only for ways the owner's existing history could be lost, overwritten or double-counted.

Each finding is fixed, or answered in writing with a reason. Findings are verified before they are
acted on; a reviewer can be wrong.

## G6 — Simulator verification

- Run the built app in the iOS Simulator with synthetic data, using the debug demo launch arguments
  where they fit.
- Reproduce every approved frame and capture it. Compare side by side with the Figma frame.
- Default and largest text size. Reduce Motion on and off. Dark appearance (the iOS root is pinned
  dark).
- Exercise the flows by tapping, not only by reading the code: enter, edit, delete, backdate.
- Screenshots that are committed come from synthetic data only.

## G7 — Pull request

### Branches

- One branch per stage from `personal/iphone-baseline`: `personal/superapp-N-short-name`.
- Subagents work in their own worktrees on sub-branches and are merged into the stage branch by the
  orchestrator.
- Never commit directly to `personal/iphone-baseline`.

### Commits

- Small, one purpose each, English, using the prefixes already in the history (`feat:`, `fix:`,
  `design:`, `docs:`, `test:`).
- The design source is its own commit, before the code that implements it.
- Tests are committed before the implementation they cover.
- No issue-closing keywords. Reference with `Refs #N`.
- End each commit message with the attribution line the session is configured to use.

### Pull requests

- One concern each. A Health-access change, a migration and an interface change are three pull
  requests.
- The description contains: what changed; the gate script output; the fault-injection results; the
  parity evidence or the stated reason there is none; what was **not** verified; the screenshots
  from synthetic data.
- No personal measurements anywhere in the pull request.
- The session may push stage branches and open pull requests against `personal/iphone-baseline`
  without asking. **Merging is the owner's.** Auto-merge is not enabled.

## G8 — Device acceptance and checkpoint

- The owner makes a fresh backup first.
- The build is signed with the existing personal identity and installed in place. It is never
  uninstalled. Follow [INSTALL.md](../INSTALL.md) and [DEVICE-TESTING.md](../DEVICE-TESTING.md).
- The signing configuration is an ignored file that exists only in the main checkout. Build the
  signed app there, from the merged baseline, not from a subagent worktree.
- The session asks before installing, every time. An earlier go-ahead does not carry over.
- A build that changes stored data is installed only after its migration was rehearsed on a private
  copy of the real database.
- The owner works through the stage's acceptance list on the phone and reports the result.
- On acceptance: switch the stage's setting on by default if the owner wants it, create an annotated
  tag `checkpoint/YYYY-MM-DD-superapp-short-name`, push it, and update
  [docs/personal/CONTEXT.md](../CONTEXT.md). Existing checkpoint tags are never moved.
- Installation evidence stays under the ignored `build/personal/`.

## Stop conditions

An open question with a default in [CONTEXT.md](CONTEXT.md) §6 is not a stop condition: proceed on
the default and report it. When one piece of work has to stop, the pieces it does not affect keep
moving.

Stop that piece and ask the owner when:

- A gate cannot be passed.
- A change would need a migration that the roadmap did not plan.
- A change would widen Apple Health access, add a network path, add a target, or touch signing.
- A test in the baseline starts failing and the cause is not the current change.
- Anything would be installed on, or deleted from, the phone.
- A finding suggests existing collected data is wrong or at risk.
