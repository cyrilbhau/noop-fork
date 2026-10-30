# Steps: upstream open-PR review

Review snapshot: **29 October 2026**. The GitHub connector returned **134 open pull requests**
from [`ryanbr/noop`](https://github.com/ryanbr/noop/pulls), across two complete pages. All titles
and descriptions were screened; relevant candidates were checked against their actual file diffs.
Additional open-PR searches for `pedometer`, `accelerometer` and `IMU` returned no matches.

**No reviewed open PR provides a validated native WHOOP 4.0 step counter or combines partial-day
Apple Health coverage with phone-free strap steps.** Calibration and an estimate derived from
motion remain different from validated step counting. A history-sync or display fix cannot establish
phone-free accuracy.

## Relevant candidates

| PR and reviewed head | Status and evidence | Relevance and limits |
|---|---|---|
| [#2816: WHOOP 4.0 EVENT watchdog](https://github.com/ryanbr/noop/pull/2816), `b6a5fab5486f` | Open, not draft. Swift/Kotlin helper tests; author reports local macOS build/tests and subsequent WHOOP 4.0/iPhone history drain. No check runs registered at this head. | Excludes periodic type-48 EVENT frames from watchdog rearming while preserving routing. The fork still has the unconditional rearm. Could unblock later motion-history sync; adds no step decoder. Repaired timeout was not directly observed on hardware. **Not included in this step change.** |
| [#2829: Android WHOOP 4 history recovery](https://github.com/ryanbr/noop/pull/2829), `7ab24c40fdb1` | Open draft; four registered checks pass, including Android build/tests. Real stall validation remains outstanding. | Requires durable cursor progress and adds bounded recovery/session fencing. Android only; overlaps #2816's Android watchdog. No iPhone or step-counting implementation. |
| [#2705: gravity-witness query](https://github.com/ryanbr/noop/pull/2705), `34042ba90029` | Open, not draft; all 17 registered checks pass, including both Apple builds. | Small adjacent performance candidate: scalar COUNT and indexed MAX remain in one statement/snapshot, with matching Kotlin SQL. The fork still has the older aggregate query. Counts, calibration, accuracy and coverage are unchanged. |
| [#2832: concurrent store reads](https://github.com/ryanbr/noop/pull/2832), `c3fdab4189b4` | Open, not draft; all 16 registered checks pass, including both Apple builds. | Lets read-only WhoopStore APIs use the database pool without waiting on the store actor. Motivating logs include long steps-processing delays. Broad API change with local store overlap; changes no formula or coverage. |
| [#959: staged HealthKit consent](https://github.com/ryanbr/noop/pull/959), `22970a49798c` | Open, not draft; all five registered checks pass, including both Apple builds. | Retains `.stepCount` in core reads. No strap counter or partial-day reconciliation. Broad overlap with the personal build's narrower Health consent boundary. |
| [#2757: batched Today publication](https://github.com/ryanbr/noop/pull/2757), `32939b9a1d13` | Open, not draft; all five registered checks pass, including both Apple builds. | Changes publication timing, preserving strap/Health precedence and the estimate fallback. Queries and storage are unchanged. |
| [#2753: legacy device-alias repair](https://github.com/ryanbr/noop/pull/2753), `58f0c669cf6c` | Open, not draft; author reports seven repair tests and WHOOP MG hardware evidence. No check runs registered at this head. | Could expose missing motion only in a specifically guarded split between legacy and registry identities. Moves stored rows and adds a migration; requires evidence of that condition before adoption. Android parity is missing. |

Registered successful checks are evidence for the named heads only. Zero registered checks is
not a green result. PR descriptions' local and hardware results are attributed author reports,
not tests performed during this review.

## Integration decision

No upstream PR was merged or cherry-picked. The unrelated BLE change in #2816 is not bundled.
#2705 is a bounded performance follow-up; #2832 needs a separate integration review. Neither
replaces counted-walk validation. The phone-free requirement remains open until strap-derived
counts pass the recorded walk and seated false-step checks in [DEVICE-TESTING.md](DEVICE-TESTING.md).
