# Health super-app handoff

Written 10 November 2026. This folder hands the "health super-app" workstream to a fresh session.
It records what was decided, what the code already provides, the staged plan, the quality gates and
the way work is split across subagents.

Nothing in this workstream has been built yet. These documents are a plan, not a status report.

## How the handoff runs

1. The owner opens the `noop-fork` folder in a new session.
2. The owner pastes the whole of [KICKOFF-PROMPT.md](KICKOFF-PROMPT.md) into the chat. The file is
   the prompt; it has no wrapper to strip.
3. The owner attaches the other five files in this folder, the prompt file itself, and the private
   profile described below.
4. The session files the documents into the repository as its first commit, places the private
   profile in its ignored location, and starts work without waiting for confirmation.

The prompt's bootstrap section tells the session to copy from the planning worktree when it still
exists, so the filed copies are byte-identical to these, and to fall back to the attachments when it
does not.

## Reading order

| # | File | What it holds |
|---|---|---|
| 1 | [CONTEXT.md](CONTEXT.md) | Why this exists, the owner's decisions, verified code findings, constraints, open questions with defaults, and the risks that were not obvious at the start |
| 2 | [ROADMAP.md](ROADMAP.md) | Every stage in detail: scope, storage, logic, screens, work packages, test plan, acceptance, device checks |
| 3 | [QUALITY-GATES.md](QUALITY-GATES.md) | The gate sequence each stage passes, including the Figma design approval that comes before any interface code |
| 4 | [ORCHESTRATION.md](ORCHESTRATION.md) | Subagent roles, brief templates, file-ownership rules and where parallel work is safe |
| 5 | [KICKOFF-PROMPT.md](KICKOFF-PROMPT.md) | The prompt the owner pastes |

## The private file

The owner's measurements, targets, programme and medical notes are **not in this folder and not in
Git**. They live in an ignored file, relative to whichever checkout the session is working in:

```
PersonalData/superapp/OWNER-PROFILE.md
```

`/PersonalData/` is ignored by the repository's `.gitignore`. An ignored file exists only in the
checkout where it was written and does not follow a branch. The planning session wrote it at:

```
/Users/cyrilbhau/Documents/Noop/noop-fork/.claude/worktrees/noop-health-superapp-4bbc21/PersonalData/superapp/OWNER-PROFILE.md
```

That worktree can be removed when its session is archived, so the owner keeps a copy and attaches it
with the kickoff prompt. The live source of truth for the owner's numbers is the training log named
inside the profile; the profile is a dated snapshot.

**The tracked documents here deliberately contain no body measurements, scan results, medication
details or injury history.** The repository has a publication review in progress
([`docs/PUBLICATION_REVIEW.md`](../../PUBLICATION_REVIEW.md)), and Git history is hard to scrub.
Keep it that way: tests and fixtures use synthetic values, and screenshots use the demo harness.

## Relationship to the existing handoff

[`docs/personal/CONTEXT.md`](../CONTEXT.md) remains the authority on the installed iPhone build, its
checkpoints and the open collection checks. This folder builds on it and does not replace it. Where
the two disagree about installed state, the older file wins until it is updated.
