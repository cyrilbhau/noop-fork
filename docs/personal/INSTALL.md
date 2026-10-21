# Personal iPhone build and installation

This is a source build for a personally owned WHOOP 4.0 and a paid Apple Developer account.
The pinned upstream baseline is `8e4b0c16e7640607600fa6bde5424095eba6034e`.
No iOS build, signing, installation, or Bluetooth test has been performed in the Linux cloud machine.
A Mac running Xcode is required for those checks; passing Linux package tests cannot substitute for them.

**Current owner's Mac:** setup, baseline/personal builds, 94 relevant tests and the final unsigned
iPhone-only build have passed. The app launched in Simulator. Physical installation is blocked by
Apple Developer device status **Processing**. Use [MAC-CONTINUE.md](MAC-CONTINUE.md) to resume the
existing task after **Enabled**, preserving its uncommitted source and private signing configuration.
The steps below are the general setup reference, not a request to repeat completed setup.

## 1. Prepare the Mac

1. Obtain this task's prepared source folder on the Mac. It is the folder containing `project.yml`,
   `Packages`, and `Tools`. The prepared source is on the `personal/iphone-baseline` branch of
   `cyrilbhau/noop-fork`. A local Codex task in **Noop for Cyril** can follow
   [MAC-CONTINUE.md](MAC-CONTINUE.md) to clone that branch into an unused child directory and do
   the Mac work. Preserve existing files and installations.
   The provided `noop-personal-source.tar.gz` bundle contains the prepared folder **and its pinned
   baseline Git history**. Double-click it in Finder to expand `noop-personal`, then use that folder.
   Keep the hidden `.git` directory: the baseline helper needs the original commit. The bundle
   excludes build caches, local signing configuration, private data and toolchain downloads.
2. Install **Xcode 26 or newer**, open it once, accept its terms, and install its iOS simulator SDK.
   Prefer per-command `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` when the global
   selection points elsewhere. The owner's existing Xcode 27.1 setup and global selection are preserved.
3. In **Xcode → Settings → Accounts**, sign in to the paid Apple Developer account. Keep the
   password, signing certificates, and private keys on the Mac; do not paste them into chat.
4. Install **XcodeGen 2.45 or newer**. If Homebrew is already installed, run `brew install xcodegen`.
5. Open Terminal, type `cd ` (including the space), drag the source folder from Finder into Terminal,
   and press Return. Run:

   ```bash
   bash Tools/personal/ios.sh check
   ```

The phone must run iOS 17 or newer and be supported by the installed Xcode. An iOS 26 SDK is a
build prerequisite even when deploying to an older supported phone.

## 2. Original baseline gate — completed

The Mac already built the exact pinned original from a temporary Git archive, without signing,
for both Simulator architectures. Its log is retained in ignored `build/personal/logs/baseline-ios.log`.
That original included upstream watch targets before the owner's iPhone-only scope instruction.
Do not repeat that watch work during the current resume. The personal target graph now contains
only the iPhone app and widget; standalone upstream watch sources are retained but not embedded.

Simulator compilation cannot exercise Bluetooth, the strap, overnight collection, HealthKit
provisioning or signed widget capabilities. Those remain separate gates after installation.

## 3. Give the personal app its own identity

The owner's Mac already has its paid team and the ignored configuration set. Reuse them rather
than asking for account/Team ID again. The following is a reference for an unconfigured installation.

Find the 10-character **Team ID** in the Apple Developer account's Membership details. Choose a
unique reverse-domain prefix for this project, such as `com.cyrilbhau.personalhealth` if it belongs to
this account and is not used by another installed copy. Run the following after replacing the Team ID:

```bash
bash Tools/personal/ios.sh configure --prefix com.cyrilbhau.personalhealth --team YOURTEAMID
```

`YOURTEAMID` is a placeholder; replace it with the real Team ID, not an Apple ID email or password.
The command writes only the upstream-supported, gitignored `Config/BundleIdSecrets.xcconfig`.
It preserves a different existing configuration and refuses upstream/example identifiers. Repeating
it with the same settings is safe. If a different file already exists, inspect it in a text editor
rather than deleting it blindly.

For that example prefix, the project derives:

| Component | Identifier |
|---|---|
| iPhone app | `com.cyrilbhau.personalhealth.noop` |
| iPhone widgets | `com.cyrilbhau.personalhealth.noop.widgets` |
| Shared App Group | `group.com.cyrilbhau.personalhealth.noop.staging` |

The `.staging` suffix on the App Group is intentional upstream configuration. Keep it consistent.
The unique app identifier creates a separate app sandbox/database; the unique App Group separates
widget snapshots. This does **not** isolate Apple Health, which remains the phone's shared health
store. The personal app and widget display **NOOP Cyril**. Also check their bundle IDs in Xcode;
an icon or name alone does not establish identity. Leave existing installations and data intact.

## 4. Build the fork, then sign and run in Xcode

```bash
bash Tools/personal/ios.sh build
bash Tools/personal/ios.sh open
```

The first command is another unsigned simulator compilation, this time of the prepared fork.
The second generates the project and opens Xcode; it does not build, provision, or install the app.
Never commit the generated `Strand.xcodeproj` project or build output. The tracked package lockfile
inside the generated project remains part of the source baseline.

1. For the current owner, wait for **Enabled** in Apple Developer before retrying provisioning.
   Then connect the unlocked iPhone to the Mac with a cable. Choose **Trust** only if asked again.
2. Enable **Settings → Privacy & Security → Developer Mode** on the iPhone if Xcode requests it;
   follow the phone's restart prompt.
3. In Xcode select the blue project icon, then **Signing & Capabilities**. Confirm the paid Team
   and **Automatically manage signing** on `NOOPiOS` and `NOOPiOSWidgets` only. No watch target
   should be built or embedded for this personal iPhone-only app.
4. Confirm **HealthKit** and **HealthKit background delivery** on `NOOPiOS`, and the same App Group
   on the app and widget targets. Verify the signed profiles/entitlements once provisioning succeeds.
   If Xcode reports that an identifier belongs to another team, choose a different personal prefix;
   do not remove HealthKit, widgets, or entitlements to hide the error.
5. Select the **NOOPiOS** scheme and the connected **physical iPhone** as the run destination.
   Press the triangular **Run** button. This local action signs and installs the app on that phone;
   no Archive, Distribute, TestFlight, or App Store step is needed.
6. At first launch allow Bluetooth. Read each Apple Health prompt: begin with needed reads and keep
   write-back disabled until collection is verified. Later enable intended writes explicitly and
   inspect the source of each exported type. A refused Health permission cannot be inferred from
   an empty read alone; check **Health → profile → Apps and Services → the personal NOOP app**.
7. Stop running from Xcode and launch the installed app from the phone for overnight tests. Avoid
   leaving the debugger attached, which can change background behavior.

A paid account generally provides a longer development provisioning period than a free account;
it is not a permanent installation. Check the actual expiry in NOOP's iOS diagnostics/provisioning
and re-sign before expiry using the same prefix/team to preserve the app's container.

## 5. Pair and validate without changing the band

Use the app's existing pairing flow for the owned WHOOP 4.0. Record the reported firmware version;
do not update firmware as a troubleshooting step. If another app holds the Bluetooth connection,
close that app for the test and retry the existing connect action. Do not delete the WHOOP app,
forget the band, reset/reboot/trim it, or use experimental protocol controls merely to make pairing pass.

Follow [the device procedure](DEVICE-TESTING.md). Keep the official WHOOP app and the original WHOOP
export archive intact. Import a **copy** through the existing WHOOP Export data-source flow only after
creating a NOOP backup. Do not restore a backup over a populated app as a trial: restore replaces the
local database. Use a disposable app identity/container for a restore rehearsal and export that
container's data first if it contains anything valuable.

All build helpers are local-only: no install, upload, automatic provisioning request, firmware write,
HealthKit data deletion, membership change, subscription, or paid service is performed by them.
