# Resume the iPhone installation on the Mac

Latest scope: **iPhone app and iPhone widgets only**. The owner has no Apple Watch. Read
[MAC-STATUS.md](MAC-STATUS.md) before doing setup or retrying a build. The immutable baseline,
personal Simulator build, 94 relevant Mac tests and final unsigned iPhone-only build have passed
on the owner's Mac. Simulator launch was verified before watch removal. The physical app has
**not** been signed successfully, installed or launched.

The last confirmed blocker is Apple Developer device status **Processing**. Do not retry signing
or installation until the owner confirms **Enabled**. Do not schedule background polling, repeat
registration, revoke certificates, disable devices, change membership or introduce a paid workaround.

## Preserve and reconcile the existing checkout

Continue the existing **Install Noop on iPhone** task in **Noop for Cyril**. The checkout is
`/Users/cyrilbhau/Documents/Noop/noop-fork`, branch `personal/iphone-baseline`. Do not create a new
worktree or replace the checkout. Inspect applicable local agent instructions and current Git status.

At handoff the Mac was at `398af6155ebbe5cf4cae1acdc5e45bc029b9f8d3`, with four uncommitted source
changes. The cloud has synchronized that exact diff into the shared branch. Preserve the local
versions before bringing in later commits:

1. Inspect the diff and compare the four blob prefixes in `MAC-STATUS.md`. Preserve any new user
   edits separately; do not assume the checkout still contains only the original four changes.
2. If the original four changes are still uncommitted, stage only these source paths and commit
   them locally. Do not stage ignored signing configuration, profiles, build logs or device files:

   ```bash
   git add -- Strand/Screens/SettingsView.swift project.yml StrandiOS/Resources/Info.plist StrandiOSWidgets/Info.plist
   git commit -m "Preserve Mac-validated iPhone-only source changes [skip ci]"
   ```

3. Fetch `origin personal/iphone-baseline`, then merge `origin/personal/iphone-baseline` into the
   existing local branch. The synchronized source edits match; resolve any unexpected conflict
   by inspection, preserving local work. Do not force-pull, reset, overwrite config or automatically
   delete/stash a populated working tree. A different local commit ID for the same edits is expected.
4. Retain `Config/BundleIdSecrets.xcconfig`, the existing build products and ignored `build/personal/`
   evidence. Keep credentials, profiles, device identifiers and app inventory local. Nothing private
   needs to be transferred to the cloud or added to Git.

For a genuinely new Mac/checkout, first read `INSTALL.md`; use the prepared branch from
`https://github.com/cyrilbhau/noop-fork.git`. The pinned original baseline is still
`8e4b0c16e7640607600fa6bde5424095eba6034e`. Its recorded historical build is not a direction to
resume watch compilation.

## Reuse completed setup

- Xcode **27.1 (27A9275)** at `/Applications/Xcode.app`; XcodeGen **2.45.4**; required SDKs installed.
- License and first launch completed. No further sudo command is currently needed.
- Use per-command `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; preserve the
  machine-wide developer-directory selection.
- Reuse the already selected paid team and private signing configuration. Do not ask for account,
  Team ID or keys again. Do not print/export certificates, Keychain or credential-file contents.
- App: `com.cyrilbhau.personalhealth.noop`; widget: `com.cyrilbhau.personalhealth.noop.widgets`;
  group: `group.com.cyrilbhau.personalhealth.noop.staging`; display name: **NOOP Cyril**.
- The personal `NOOPiOS` graph must contain only the iPhone app/widget. No watch target may be built
  or embedded. Retain the iPhone widget, HealthKit/background delivery and Bluetooth background mode.
- Read `build/personal/mac-progress.json` and `iphone-only-build-result.json` locally. Reuse valid
  outputs; rerun only checks affected by source/toolchain changes. Do not reinstall Xcode, repeat
  the already verified baseline or rebuild watch targets merely to resume provisioning.

If a genuinely necessary Mac operation requires administrator privileges, provide the exact command
and reason for the owner to execute. Do not run sudo or type passwords. No approval is needed again
for the already authorized personal signing, installation and launch once its prerequisites hold.

## After the owner confirms Enabled

1. Reconnect the **unlocked iPhone by cable**. Recheck its pairing, Developer Mode and device services.
   These previously worked; do not repeat trust/reset operations unless an actual failure calls for it.
2. Read the target device identifier from its ignored local record without printing it. Recheck the
   complete installed-app inventory using the supported tool's include-all-apps option. Confirm the
   separate personal identifier remains unused; do not overwrite another app or delete its data.
3. Refresh development provisioning and build/sign `NOOPiOS` with the existing paid team. Permit
   ordinary Xcode development provisioning as already authorized. If a cached task-specific profile
   is demonstrably stale, preserve it before refreshing; do not remove unrelated profiles/certificates.
4. Verify the **signed** app and widget: bundle IDs, team, App Group, HealthKit/background delivery,
   development profile including this phone, valid executable and no embedded `Watch` bundle.
   Do not infer signed entitlements from `project.yml` or the earlier unsigned build.
5. Install and launch with Xcode Run or supported `devicectl` commands. Verify the actual device app
   listing and launch response. An unsigned app, successful compiler result or Simulator is not a
   physical installation. Let the owner review the first-run agreement and permissions.
6. Continue the normal WHOOP 4.0 pairing/collection flow and `DEVICE-TESTING.md`. Record actual
   firmware/layout and stored HR/R-R/motion coverage. Keep Health writes off and avoid full raw
   physiological debug logs. No firmware update or experimental strap write is authorized.

If provisioning still fails after Enabled, inspect the new error and profile inclusion before
retrying. Do not loop unchanged builds or reinterpret the old Processing result as missing credentials.

## Constraints that remain in force

Preserve all existing apps/data and the original WHOOP export. Health writeback deletes/replaces
its own samples during reconciliation; health-data deletion has not been approved. No firmware
change, band reset, membership change, restore over a populated database, paid service or app
publication is authorized. The goal is personal sideloading without a required subscription/backend.

WHOOP 4.0 steps are motion estimates. Agreed acceptance: **≤10% absolute error on each counted
500–1,000-step walk** and **≤20 false steps in 30 seated minutes**. Do not substitute phone steps.
Offline calibrated SpO₂ is unavailable; absolute skin temperature is provisional. Hevy currently
uses CSV import, not automatic sync. Preserve provenance and missing/freshness labels.

The target remains **12 November 2026**, before the stated **19 November 2026** membership end.
Apple's Processing window is not a guaranteed completion time. Prioritize installed collection
validation over a large redesign; report signed build, installation, launch and sensor results
separately. No background retry or monitoring is currently running.
