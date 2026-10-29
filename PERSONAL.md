# Personal WHOOP 4.0 iPhone fork

**Current status — 29 October 2026:** NOOP Cyril is signed, installed and working on the owner's
iPhone. The owner confirmed ChatGPT Coach replies and retained sign-in, pasted-workout saving and
reopening, and Apple Health workout imports. The personal build contains the iPhone app and its
widgets only; the owner has no Apple Watch. The old device-provisioning blocker is resolved.

Start with [the current context and design handoff](docs/personal/CONTEXT.md). It covers both recent
workstreams, source entry points, remaining validation and the checkpoint
`checkpoint/2026-10-29-before-design`. Claude loads it through [CLAUDE.md](CLAUDE.md).
The [installation guide](docs/personal/INSTALL.md) remains a setup reference; use
[the device procedure](docs/personal/DEVICE-TESTING.md) for the remaining collection checks.

## What matters before investing in the interface

| Requirement | Current evidence |
|---|---|
| Reliable phone-free steps | **Unproven.** The 4.0 engine estimates steps from sparse motion; it does not decode a native pedometer count. An imported phone total can suppress that day's estimate. |
| Sleep, HR/HRV, recovery and cardiovascular strain | Implemented; relevant suites pass. The installed app uses Sleep/Recovery/Strain display names. Multi-night iPhone collection, background reliability and accuracy still need recorded validation. Scores are independent NOOP calculations. |
| Skin temperature | Provisional conversion/trend; accurate absolute temperature is unsupported. |
| Offline SpO₂ percentage | Unsupported from the 4.0 sensor stream. Imported historical percentages are a separate source. |
| Apple Health | Personal build imports workout summaries only. Reads are enabled and an imported Hevy workout is confirmed in NOOP. Health writes are blocked; vitals/sleep/steps are not imported by this route. |
| Hevy | Reviewed text paste/save and set-level Hevy CSV import are implemented. Owner confirmed paste/save/reopen. No direct account sync; CSV imports append/skip duplicate start times rather than reconcile later edits. Preserve source exports. |
| ChatGPT Coach | Subscription sign-in, model discovery, streaming replies, history, summaries and briefs implemented. Owner confirmed normal replies and saved sign-in. Overnight scheduling and other field cases remain separate checks. |
| Widgets | Recovery/Strain/Sleep presentation plus estimated steps/goal and recent sleep. Signed app/widget builds passed and app installation completed; widget values/freshness and refresh still need device acceptance. |
| Local storage, export and backup | Existing SQLite and `.noopbak` workflows; storage tests pass. An iPhone backup/restore rehearsal remains unverified. |

Current implementation evidence: [Coach checkpoint](docs/superpowers/plans/2026-10-28-iphone-chatgpt-coach.md#implementation-checkpoint--2026-10-28)
and [Hevy/Health acceptance](docs/personal/HEVY-HYBRID.md). Earlier audit evidence: [collection](docs/personal/COLLECTION-AUDIT.md),
[integrations](docs/personal/INTEGRATIONS-AUDIT.md),
[license/releases/issues](docs/personal/UPSTREAM-AUDIT.md), and
[executed checks](docs/personal/VALIDATION.md).

## Source baseline and personal changes

Upstream: <https://github.com/ryanbr/noop> at
`8e4b0c16e7640607600fa6bde5424095eba6034e` (12.1.0 testing, iOS build 438).
This exact main commit was selected to audit current fixes. It is newer testing code, not the
stable 12.0.0 release or a hardware-qualified version. The unchanged baseline was built from an
immutable temporary Git archive on the Mac. That historical check is complete; do not repeat its
watch compilation during the current iPhone-only provisioning resume.

Personal additions are deliberately modular:

- Reusable Linux setup and Mac build/signing helpers, private app identity, and device acceptance plan.
- A conditional `FoundationXML` import repairing the baseline's Linux XLSX compilation failure.
- Mac-validated shared form-row visibility fix, **NOOP Cyril** display names and an iPhone-only
  dependency graph that keeps the phone widget while excluding watch compilation/embedding.
- Additive optional widget payload, estimated-step/goal and sleep widgets, and a user-selected goal
  under **Settings → Profile → Daily step goal**. No goal is assumed; local steps remain labelled
  estimates with unknown freshness, and sleep carries its real end time and source.
- Additional private-data ignore patterns; private signing configuration and health data remain local.
- ChatGPT subscription Coach with device-only Keychain credentials and separate health-context consent;
  existing API-key providers remain available. No NOOP backend or new paid subscription was added.
- Workout text and Hevy CSV set-level imports, workout-only Apple Health reads and display/cache fixes.
- Sleep/Recovery/Strain presentation for the owner's familiar WHOOP comparison.

These additions do not change BLE commands, firmware, protocol decoding, database migrations or
analytics formulas. The personal UI and subscription integration target iPhone; shared CSV metadata
and parsing changes were mirrored in Kotlin. Existing screens remain the baseline interface apart
from the accepted additions and labels. The owner now wants Claude to review design; the broader
Today/Sleep/Health/Training redesign remains ahead, with collection evidence still needed for readiness.

The source remains under [PolyForm Noncommercial 1.0.0](LICENSE). Keep `LICENSE`, `NOTICE`,
`ATTRIBUTION.md` and `DISCLAIMER.md`; personal noncommercial use is permitted, commercial rights
are not granted. Prepared source is now available on
[`personal/iphone-baseline`](https://github.com/cyrilbhau/noop-fork/tree/personal/iphone-baseline).
The personal app is installed on the owner's iPhone; no public release was made. Scheduled governance/branch-cleanup jobs are gated to the
upstream repository; personal-fork runs remain manual. No hosted build service was started.

The accepted implementation is committed and pushed as
[`e6e14c6a`](https://github.com/cyrilbhau/noop-fork/commit/e6e14c6a4853419aa7801a7e454caee013e85048).
The 29 October checkpoint adds current documentation to the same application source. Earlier
[Mac continuation notes](docs/personal/MAC-CONTINUE.md) are historical; retain the existing local
checkout, signing identity, app data and ignored configuration for subsequent updates.

## Next milestones

1. Validate stored WHOOP collection on the installed build: at least three nights, a full workout,
   locked-phone operation and reconnect/backfill. Installation, Coach and the accepted import flows
   are complete; do not repeat provisioning setup.
2. Check two phone-free walks against the **agreed ≤10% error** limit and a seated trial against
   **≤20 false steps per 30 minutes**. If the estimate cannot meet the requirement, use an explicitly
   attributed measured pedometer source; carrying the iPhone is the smallest existing alternative.
   Automatic calibration expects phone-step references, which the current workout-only Health route
   does not import; resolve that dependency before claiming calibration or accuracy.
3. Validate installed widget values/freshness, a private backup/restore rehearsal, and retention/import
   of the original WHOOP archive. Keep source attribution and original exports intact.
4. Check Coach overnight briefs, locked-phone operation and real token expiry. iOS scheduling remains
   best effort. Keep Health writes blocked under the current personal integration.
5. Review the custom native shell with Claude using the current handoff and WHOOP design direction.
   Implement it over the working engine without treating visual similarity as score equivalence.

Target: **12 November 2026**, before the stated **19 November 2026** membership end. These are
planning dates; neither a green engine suite nor this source handoff guarantees readiness by them.

Cloud tasks use the existing isolated checkout; do not create a Git worktree unless explicitly
requested. See [Linux setup](docs/personal/LINUX.md). Keep health data and credentials outside
Git and logs. Store private exports outside the source folder; ignored `PersonalData/` is only a
fallback, not encryption. No firmware change, health deletion, installation over another app,
publication, membership change or charge is authorized by these helpers.
