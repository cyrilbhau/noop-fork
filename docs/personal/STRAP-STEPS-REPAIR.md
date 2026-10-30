# Independent strap estimates and phone-free validation

Recorded 29 October 2026 for the personal iPhone fork. This update was signed and installed in place
on the physical iPhone. Its first functional revision launched normally; launch of the final
copy-only revision was blocked by the phone being locked. It includes the preceding Health Steps import and
the **Refresh widget design** artwork. Owner acceptance of the new source/check screen is pending.

## Confirmed defect and repair

The incumbent WHOOP 4 estimate is calibrated motion volume, not a validated decoded pedometer.
Its orchestration skipped every day with a positive Health step reference, hiding the independent
strap estimate even if part of the day was spent away from the phone. It also wrote under the
engine's computed namespace rather than the resolved day's owner.

Swift and Kotlin now plan separate owner-attributed estimates on all eligible scored WHOOP 4 days,
including Health-positive days. Both positively confirm registry family, distinguish failed reads
from empty input and reject unsafe numeric conversions. Failed reads preserve prior stored values
and calibration; no deletes were introduced. An absent plan entry does not invalidate a pre-existing
estimate, so previously stored estimates can remain stale when new input is unavailable. The
estimation formula and dashboard source preference remain unchanged. Counts are not summed or used
to fill missing Health intervals.

**Today → Steps** and Profile step settings open separate source readings, histories and calibration.
The counted-walk tool freezes calibration and one strap identity at start, stores up to ten local
trials, and reads only that strap's motion within the completed interval. A 500–1,000-step counted
walk is scored only with sufficient usable coverage and no gap over five seconds. This policy is
explicit, not a claimed sensor cadence. Invalid or incomplete input is not reported as zero.
Results show error and sample/gap diagnostics; they never train calibration or alter Health records.
This tool sends no new BLE command and starts no raw sensor capture.

## Verification and installation

- macOS app build and **71 focused app tests passed**, including 15 walk-model tests covering held-out
  calibration, source attribution, gaps, invalid input, duplicate conflicts and corrupted saved trials.
- Signed iPhone app and widget build passed. Existing app/widget identities and App Groups match;
  signatures, physical-phone profile inclusion and expiry were checked. Normal installation and
  launch of the first functional revision succeeded. The final copy-only revision installed, with
  launch blocked by the phone lock. No uninstall, restore or signing change was performed. Group-container paths
  match; app-container path metadata is not proof of retained history.
- **29 focused analytics XCTest methods passed**, compiling exact current source with a standalone
  runner. A **216-case Swift decision oracle** matches the fixtures in both languages. Full SwiftPM
  execution was blocked by an unavailable GRDB submodule checkout. Android tests were written but
  not executed because JDK and Android SDK are absent.
- Localization, detached-doc-comment and whitespace checks passed. Parity governance was checked
  separately; its result is recorded below without waiving new debt.

Exact frozen source hashes and private build/signing/device evidence are in ignored
`build/personal/strap-steps-device/`. The preceding installed source was preserved in ignored
`build/personal/steps-widget-source-installed/`. Source comments and handoff documentation added
after freezing do not change the installed executable.

The parity governance gate is **not green**. A guarded
`python3 Tools/parity_ledger.py --refresh-derived --base HEAD --migrate-authority` independently
re-derived the exact base and still rejected the personal Swift-only `upsertAppleDailySteps`
operation. Its narrow HealthKit step update intentionally has no Android caller/equivalent in this
personal scope. Truthful method-level comments pair the new analytics helpers correctly. The gate
restored both derived metadata snapshots; no baseline, disposition or external issue was added to
waive the remaining finding. Evidence is retained in ignored `parity-governance.log` alongside the
other repair checks. This is a repository-governance limitation, separate from the successful Apple
builds and installation.

## Remaining requirement

Reliable phone-free steps remain unqualified. Two separate counted walks and a seated false-step
check are still required; see [the device procedure](DEVICE-TESTING.md). One passing walk establishes
only that trial's result, and failure establishes a limitation of the current NOOP estimate/input,
not a hardware limitation.

The unchanged calibration can compare whole-day strap motion with partial-day phone counts, which
can bias its coefficient. It also shares a coefficient across WHOOP 4 owners/placements. Preserving
the separate estimate does not resolve these limitations or establish complete daily coverage.

[The parent-PR review](STEPS-UPSTREAM-REVIEW.md) found no open implementation that resolves this
requirement. No PR was cherry-picked. Native-counter investigation needs normal offline frames
across multiple labelled walking/stationary intervals. WHOOP 5's counter field is not validated for
WHOOP 4, and a captured live high-rate WHOOP 4 frame does not establish offline retention. No
speculative historical-save or firmware command was enabled.
