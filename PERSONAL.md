# Personal WHOOP 4.0 iPhone fork

The source and Linux engine checks are prepared. **The iPhone app has not been built or tested on
a device in this task.** The next gate is the unchanged baseline build on a Mac, followed by the
phone-free step and overnight tests. A dependable replacement is not yet established.

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
| Widgets | Existing Charge/Effort/Rest widgets plus new source for estimated steps/goal and recent sleep. Pure payload tests pass; WidgetKit compilation, signing and refresh remain unverified. |
| Local storage, export and backup | Existing SQLite and `.noopbak` workflows; storage tests pass. An iPhone backup/restore rehearsal remains unverified. |

Full evidence: [collection](docs/personal/COLLECTION-AUDIT.md),
[integrations](docs/personal/INTEGRATIONS-AUDIT.md),
[license/releases/issues](docs/personal/UPSTREAM-AUDIT.md), and
[executed checks](docs/personal/VALIDATION.md).

## Source baseline and personal changes

Upstream: <https://github.com/ryanbr/noop> at
`8e4b0c16e7640607600fa6bde5424095eba6034e` (12.1.0 testing, iOS build 438).
This exact main commit was selected to audit current fixes. It is newer testing code, not the
stable 12.0.0 release or a hardware-qualified version. The build helper compiles that immutable
baseline from a temporary Git archive before compiling any personal changes.

Personal additions are deliberately modular:

- Reusable Linux setup and Mac build/signing helpers, private app identity, and device acceptance plan.
- A conditional `FoundationXML` import repairing the baseline's Linux XLSX compilation failure.
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
are not granted. No app has been published and no changes have been pushed to GitHub.

## Next milestones

1. Compile the original and fork with Xcode 26+, then sign under a distinct personal identity.
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
