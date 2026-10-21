# Continue locally: get NOOP onto the owner's iPhone

This is the continuation for the local Codex project **Noop for Cyril** at
`/Users/cyrilbhau/Documents/Noop`. The owner requested an installed personal app and authorized
the necessary development work. The cloud task has no Mac shell, task-creation/handoff tool,
Apple SDK, signing access or phone connection. This file carries the concrete continuation.

## Get the prepared source safely

Inspect the local project and its agent instructions first. Preserve existing files, repositories,
untracked work, signing settings and app installations. Reuse a matching checkout if present;
otherwise clone into a new `noop-fork` child directory, without creating a Git worktree:

```bash
git clone --branch personal/iphone-baseline https://github.com/cyrilbhau/noop-fork.git noop-fork
cd noop-fork
```

Read `AGENTS.md`, `PERSONAL.md`, this file, and `docs/personal/INSTALL.md`. The upstream reference
is exactly `8e4b0c16e7640607600fa6bde5424095eba6034e` (12.1.0 testing), not a moving tag.
If that object is absent from a shallow download, fetch it from the public upstream without resetting
the personal source:

```bash
git fetch https://github.com/ryanbr/noop.git 8e4b0c16e7640607600fa6bde5424095eba6034e
```

The source branch and the cloud archive contain no developer certificates, API keys or health data.
No app was built, signed or installed in the cloud. No release, TestFlight upload or paid CI job
is required to put this source build on the owner's phone.

## Execute the Mac work

1. Inspect actual macOS/architecture, installed Xcode and selected developer directory, iOS SDKs,
   XcodeGen, simulator availability, disk and existing signing configuration. Do not stop at a plan.
   Full **Xcode 26+**, its iOS SDK and **XcodeGen 2.45+** are needed. Prefer an existing suitable
   Xcode; a per-command `DEVELOPER_DIR` can avoid changing the machine-wide selection. Install
   missing ordinary tools using existing supported package tooling. Do not start a paid service.
2. Run `bash Tools/personal/ios.sh check` and then `bash Tools/personal/ios.sh baseline`. This builds
   the immutable upstream source in a temporary archive with signing off. Read failures, fix setup
   issues, and retry the affected operation. A repository defect needs its own documented patch;
   never describe a modified baseline as the unchanged one. No phone is needed for these checks.
3. Establish an app identity separate from every existing NOOP install. Suggested personal prefix:
   `com.cyrilbhau.personalhealth`, provided it is unused. Reuse a valid existing local config or find
   the paid development team from existing Xcode/signing metadata. Keep all certificates/private
   keys/passwords in macOS/Xcode/Keychain. If no account is signed in, ask the owner to sign in
   through Xcode; if multiple teams are ambiguous, ask for the team choice. Do not request secrets
   in chat or dump Keychain/credential files. The supported configure command is:

   ```bash
   bash Tools/personal/ios.sh configure --prefix com.cyrilbhau.personalhealth --team ACTUAL_TEAM_ID
   ```

   `ACTUAL_TEAM_ID` is a placeholder for the real ten-character ID. Preserve a different pre-existing
   `Config/BundleIdSecrets.xcconfig`; do not overwrite it blindly.
4. Run `bash Tools/personal/ios.sh build` to compile the personal source for Simulator. Re-run
   XcodeGen after source/project changes. Repair real SwiftUI/WidgetKit/app-target errors; package
   success alone does not validate them. Run relevant `StrandTests` on the Mac because shared
   Settings and widget-payload code was changed. A new widget resource catalog is included by
   the directory source entries. Verify all embedded watch targets compile, even without a watch.
   Launch the personal build in an available simulator for a useful first-launch check when feasible;
   show missing data honestly, without pairing or invented sample health metrics.
5. Verify the app/widget/watch bundle IDs, matching App Groups, HealthKit/background delivery,
   Bluetooth background mode and automatic signing team. Preserve the widget and watch extensions.
   A distinct display name such as **NOOP Cyril** will help distinguish the installed app; make
   such a small project change only after recording the unchanged baseline build result. Do not
   remove capabilities merely to make signing pass.

If a Mac operation requires administrator privileges or user authentication, finish independent
work, then give the owner the **exact command and the reason** to run it. Do not run sudo, type
passwords or assume silence is approval. Xcode terms, first-launch component installation, account
sign-in and security prompts may require the owner. Do not ask them to connect the phone just to
inspect tools or compile the simulator build.

## Connect and install when ready

Once the unsigned builds pass and the personal identity/account are established, tell the owner
to **connect the unlocked iPhone to the Mac by cable**. Have them accept **Trust** and enable
**Developer Mode** if iOS requests it. Some provisioning checks require the connected device;
report them accurately rather than waiting for a profile that cannot yet include the phone.

Build/sign for that actual iPhone with the owner's paid team, allowing ordinary Xcode development
provisioning where needed. Installation and launch of this separately identified personal app on
the owner's phone are authorized by the current request. Preserve the official WHOOP app, any
other NOOP installation and all their data. Use Xcode Run or supported `devicectl` operations,
verify installation and launch, and explain any required phone-side consent. Do not stop at an
IPA, simulator, open port or unsigned build and call the physical app installed.

The intended first-launch state is a real app showing pairing/missing-data states. Then use the
existing WHOOP 4.0 pairing flow and collect on the owned band. Confirm actual firmware/layout,
stored HR/R-R/motion coverage, reconnect/backfill and widget sharing; no firmware update or
experimental strap write is authorized. Avoid enabling full physiological debug logging.

## Limits and authority that carry forward

- Initial collection keeps Health write permissions off. Existing Health writeback deletes/replaces
  its own samples during reconciliation; the owner has not approved health-data deletion. Ask for
  that specific approval before enabling this behavior. Never delete existing health data to make
  deduplication or step tests pass.
- Do not update firmware, reset the band, change membership, overwrite another installation,
  restore over a populated database, publish the app or incur charges without explicit approval.
  The target is personal sideloading, with no required subscription or hosted backend.
- WHOOP 4.0 steps are sparse-motion estimates, not a decoded native counter. The owner accepted
  **≤10% absolute error on each manually counted 500–1,000-step walk** and **≤20 false steps in
  30 seated minutes**. Partial-phone days can suppress the estimate. Do not substitute phone counts
  into the phone-free trial. Offline calibrated SpO₂ is unavailable and absolute skin temperature
  is provisional. Preserve provenance and unknown freshness labels.
- Hevy currently uses manual CSV import, not automatic API sync. Keep the user's original WHOOP
  archive unchanged when it arrives. Keep health data, raw logs, exports and credentials out of Git.
- Cloud verification: **3,905 engine XCTest passes, 2 optional skips, 13 widget-model passes,
  338 existing Python-tool passes, 12 build-helper passes**, plus source/i18n checks. None of these
  establishes an iPhone build, signing, live collection, widget updates or overnight accuracy.
- Target: **12 November 2026** before the stated membership end **19 November 2026**. Report actual
  progress and remaining gates. Prioritize an installed, collecting baseline over a large redesign.

After the app is installed and launched, continue with `DEVICE-TESTING.md`. Record only real results.
The owner's next physical actions should be short, specific and timed to the operation that needs them.
