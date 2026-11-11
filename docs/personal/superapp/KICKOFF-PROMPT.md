You are taking over a planned workstream on my personal iPhone fork of NOOP, an open-source, on-device companion app for WHOOP straps. I use this app every day and it holds the only copy of my collected health history. The workstream turns it from a WHOOP replacement into the home for a multi-year body-recomposition project: a weekly scorecard, a clean data hand-off to my coach, protein tracking, a body record and an events layer.

Nothing has been built yet. A previous session did the planning and verified what the code already provides. Your job is to carry out that plan to a standard where I can trust every number the app shows me. This whole message is the kickoff prompt; it is also attached as KICKOFF-PROMPT.md so you can file it with the rest.

Start working as soon as you have read this. Do not wait for me to confirm the plan. I list below the few things that need my go-ahead; everything else, proceed.

## What is attached

Six files are attached to this message:

- README.md, CONTEXT.md, ROADMAP.md, QUALITY-GATES.md, ORCHESTRATION.md — the planning set. They belong in the repository at `docs/personal/superapp/`, together with this prompt as KICKOFF-PROMPT.md.
- OWNER-PROFILE.md — my real measurements, targets, rules and medical notes. It is private. It belongs at `PersonalData/superapp/OWNER-PROFILE.md`, which the repository's `.gitignore` excludes. Nothing from it may appear in a tracked file, a test or fixture, a commit message, a pull request, a screenshot or a subagent brief. The repository may be published one day.

If OWNER-PROFILE.md is not attached, look for it at the path in step 3 below, and if it is not there either, ask me for it and carry on with everything that does not need my real numbers.

## Bootstrap — do this first

Your working directory is either my main checkout at `/Users/cyrilbhau/Documents/Noop/noop-fork` or a fresh worktree the app created from it. Find out which, and use absolute paths.

1. **Look before touching.** Run `git status` and note the current branch. Never discard, stash or overwrite uncommitted work you did not make; if the tree is dirty, tell me what you found and work in a separate worktree. Run `git fetch`. On 10 November 2026 the local `personal/iphone-baseline` was four commits behind `origin/personal/iphone-baseline` (158a5de3 against 85fc5329); the planning documents were verified at 85fc5329. Branch from the up-to-date remote tip. If you are in the main checkout and it is clean, a fast-forward of the local baseline is fine.

2. **Create the first branch**, `personal/superapp-0-foundation`, from the up-to-date baseline. Never commit directly to `personal/iphone-baseline`.

3. **File the planning set.** Byte-identical copies of everything may still exist on this Mac from the planning session:
   - `/Users/cyrilbhau/Documents/Noop/noop-fork/.claude/worktrees/noop-health-superapp-4bbc21/docs/personal/superapp/`
   - `/Users/cyrilbhau/Documents/Noop/noop-fork/.claude/worktrees/noop-health-superapp-4bbc21/PersonalData/superapp/OWNER-PROFILE.md`

   If those exist, copy from them with `cp` rather than retyping the attachments, so nothing drifts. If they do not, write the attachments out exactly as attached. Put the six planning files in `docs/personal/superapp/` and commit them alone as `docs: add health super-app handoff`.

4. **File the private profile.** Before writing it, run `git check-ignore -v PersonalData/superapp/OWNER-PROFILE.md` and confirm the path is ignored. Then place it there. Never stage it. After the commit in step 3, run `git status` and confirm it does not appear.

5. **Read**, in this order: `docs/personal/superapp/README.md`, CONTEXT.md, ROADMAP.md, QUALITY-GATES.md, ORCHESTRATION.md, then `AGENTS.md` and `docs/personal/CONTEXT.md` for the repository rules and the state of the installed build, then the private profile.

The planning documents were accurate on 10 November 2026. Code moves, so re-check any fact you are about to depend on, and tell me where a document turned out to be wrong. When you correct one, correct the file in the repository so there is a single source of truth.

## How I want you to work

Act as the orchestrator. Hold the plan, talk to me, and delegate bounded pieces to subagents using the roles and brief templates in ORCHESTRATION.md.

**You have my standing request to spawn subagents for this whole workstream.** Do not ask each time. I have plenty of capacity and would rather spend it on independent test authors, several reviewers with fresh context, parity oracles and simulator passes over every state than on running more features at once. Give each writing subagent its own worktree and its own files. Treat what a subagent reports as a claim: read the diff and rerun the checks before you tell me something works.

Work through the stages in order and take each one through every gate in QUALITY-GATES.md. Three things matter most to me:

- **Design before code.** For each stage, build the screens as frames in my Figma file and get my approval before any interface code is written. Cover every state, not only the happy one. When a stage's frames are ready to import, ask me for computer-use access to Figma and tell me exactly which page and frames to review. While I am reviewing, keep going on everything that does not depend on layout: specifications, the synthetic fixture, tests, pure logic, storage, the Kotlin twin and the tooling.

- **Testing that would catch a real fault.** Tests are written from the specification, before the implementation, by an agent that has not seen the implementation. Every rule gets a deliberate break to prove a test fails. Shared logic gets a Kotlin twin proven by oracle, or an explicit statement that it was written and not run. CI does not currently run on this fork, so a local gate script is the evidence; stage 0 builds it. A check that could not run is reported as not run, never as passed.

- **Checkpoints.** One branch per stage from the baseline, small commits with one purpose each, the design source and the tests committed before the code they govern, one pull request per concern, and an annotated checkpoint tag after I accept the stage on my phone.

## Open questions — use these defaults and keep moving

CONTEXT.md section 6 lists the open questions. Do not stop on them. Proceed on the default and tell me you did; I will overrule where I disagree.

- **Q1, the food app.** I call it "Instinct"; its identity is unconfirmed. Stage 3 stays blocked until I give you its App Store link. Stages 0, 1, 2 and 4 do not depend on it.
- **Q2, where the scorecard lives.** Design both placements as frames and I will choose from the pictures.
- **Q3, Android.** Do not install anything on this Mac. Write the Kotlin twins, mark them "written, not run" in every report and pull request, and remind me this is outstanding.
- **Q4, wider Apple Health reads.** No, until I say yes at stage 3.
- **Q5, progress photos.** Out of scope until I ask.
- **Q6, the lift signal.** Treat it as unknown to the app unless imported sessions cover the period, and say so on the screen.

## What needs my go-ahead every time

Ask me, and wait for a clear yes in this conversation, before you: treat a design as approved; merge a pull request into the baseline; install anything on my phone; widen Apple Health access; add a database migration the roadmap did not plan; add a network path, a build target or any change to signing; install software on this Mac; or change CI workflow files. An earlier yes does not carry over to the next occasion.

Pushing stage branches and opening pull requests against `personal/iphone-baseline` is fine without asking. Do not enable auto-merge.

My phone is never wiped, the app is never uninstalled, and a backup is never restored over the working install. Device builds need my local signing configuration, which is an ignored file that exists only in the main checkout, not in worktrees.

If a gate cannot be passed, or you find something suggesting my existing data is wrong or at risk, stop that piece and tell me rather than working around it. Keep the unaffected pieces moving.

## First session — begin now

After the bootstrap, start these together:

1. Stage 0 tooling work packages that do not need me: the baseline record, the local gate script, the CI investigation, the package-test reachability check, the synthetic fixture and the Figma pipeline check.
2. The stage 1 specification, starting with an Explorer pass over every reader and writer of body weight and waist.
3. The stage 1 design frames as HTML in `design/`, in both placements, ready to import as soon as I grant Figma access.
4. Once the stage 1 specification exists: the scorecard tests, then the pure scorecard function, then its Kotlin twin. None of that needs the design.

Then send me one short message: what you started, anything in the plan that the code contradicted, and my own stage 0 field work with its dates. The WHOOP history export has a hard deadline of 19 November 2026.

## Reporting

At the end of each working session tell me, briefly: which gate each stage has reached, what was verified and by what evidence, what was not verified, and what is waiting on me as short questions. Lead with what I need to decide. Be plain, and say when you were wrong. Keep measured and estimated values distinct in everything you write and everything the app shows.
