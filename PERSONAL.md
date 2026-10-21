# Personal WHOOP 4.0 iPhone fork

The original baseline, personal Simulator build and final unsigned iPhone-only build have passed
on the owner's Mac, along with **94 relevant Mac tests**. The personal app launched in Simulator.
**Installation on the physical iPhone is blocked by Apple Developer device status Processing.**
The personal build contains the iPhone app and its widgets only; the owner has no Apple Watch.
See [the Mac status and source synchronization record](docs/personal/MAC-STATUS.md).

Start with [Mac build, signing and installation](docs/personal/INSTALL.md), then use
[the short device procedure](docs/personal/DEVICE-TESTING.md).

## What matters before investing in the interface

| Requirement | Current evidence |
|---|---|
| Reliable phone-free steps | **Unproven.** The 4.0 engine estimates steps from sparse motion; it does not decode a native pedometer count. An imported phone total can suppress that day's estimate. |
| Sleep, HR/HRV, recovery and cardiovascular strain | Implemented upstream; relevant engine suites pass. iPhone collection, firmware compatibility, background behavior and accuracy remain unverified. Scores are independent NOOP calculations. |
| Skin temperature | Provisional conversion/trend; accurate absolute temperature is unsupported. |
| Offline SpO₂ percentage | Unsupported from the 4.0 sensor stream. Imported historical percentages are a separate source. |
| Apple Health | Existing reads/writes and genuine SDNN export; no step writer. Keep writes off for the collection baseline. Reconciliation deletes/replaces app-authored samples and needs explicit approval before use. |
| Hevy | Manual CSV import is implemented. Automatic synchronization and lossless set-level history are not implemented; preserve the original CSV. |
| Widgets | Existing Charge/Effort/Rest widgets plus estimated steps/goal and recent sleep. Pure payload tests and Mac compilation passed; signed physical installation and refresh remain unverified. |
| Local storage, export and backup | Existing SQLite and `.noopbak` workflows; storage tests pass. An iPhone backup/restore rehearsal remains unverified. |

Full evidence: [collection](docs/personal/COLLECTION-AUDIT.md),
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
- Additional private-data ignore patterns. No new telemetry, hosted backend, credential or subscription.

These additions do not change BLE commands, firmware, protocol decoding, database migrations or
analytics formulas. The widget and goal UI are specific to this requested personal iPhone fork;
Android UI has not been extended. Shared data/algorithm parity remains unchanged. Existing screens
remain the baseline interface; the Today/Sleep/Health/Training redesign waits for collection evidence.

The source remains under [PolyForm Noncommercial 1.0.0](LICENSE). Keep `LICENSE`, `NOTICE`,
`ATTRIBUTION.md` and `DISCLAIMER.md`; personal noncommercial use is permitted, commercial rights
are not granted. Prepared source is now available on
[`personal/iphone-baseline`](https://github.com/cyrilbhau/noop-fork/tree/personal/iphone-baseline).
No app has been published or installed on the physical iPhone. Scheduled governance/branch-cleanup jobs are gated to the
upstream repository; personal-fork runs remain manual. No hosted build service was started.

For the authorized Mac-to-iPhone installation work, follow
[the local Codex continuation](docs/personal/MAC-CONTINUE.md). The next runtime must be a local
Mac task, because this cloud task cannot execute Xcode or create the local task itself.

## Next milestones

1. After Apple shows the phone as **Enabled**, resume the existing Mac task, preserve its local
   source/configuration, refresh provisioning, then sign/install/launch the iPhone app and widget.
2. Check two phone-free walks against the **agreed ≤10% error** limit and a seated trial against
   **≤20 false steps per 30 minutes**. If the estimate cannot meet the requirement, use an explicitly
   attributed measured pedometer source; carrying the iPhone is the smallest existing alternative.
3. Validate at least three nights, a full workout, reconnect/backfill, widgets, and a private backup.
4. Validate approved Health writeback and manual WHOOP/Hevy imports with real exports. Keep imported
   WHOOP scores distinct from local scores and preserve the original archives unchanged.
5. Build the custom native shell over the working engine after these gates. Automatic Hevy sync
   additionally needs official API/account verification, retained workout IDs and Keychain handling.

Target: **12 November 2026**, before the stated **19 November 2026** membership end. These are
planning dates; neither a green engine suite nor this source handoff guarantees readiness by them.

Cloud tasks use the existing isolated checkout; do not create a Git worktree unless explicitly
requested. See [Linux setup](docs/personal/LINUX.md). Keep health data and credentials outside
Git and logs. Store private exports outside the source folder; ignored `PersonalData/` is only a
fallback, not encryption. No firmware change, health deletion, installation over another app,
publication, membership change or charge is authorized by these helpers.
