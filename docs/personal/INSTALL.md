# Personal iPhone build and installation

This is a source build for a personally owned WHOOP 4.0 and a paid Apple Developer account.
The pinned upstream baseline is `8e4b0c16e7640607600fa6bde5424095eba6034e`.
No iOS build, signing, installation, or Bluetooth test has been performed in the Linux cloud machine.
A Mac running Xcode is required for those checks; passing Linux package tests cannot substitute for them.

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
   In **Xcode → Settings → Locations → Command Line Tools**, select this Xcode installation.
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

## 2. Compile the original baseline first

```bash
bash Tools/personal/ios.sh baseline
```

This extracts the exact pinned Git commit into a temporary directory and builds the unmodified
`NOOPiOS` scheme for iOS Simulator with signing disabled. It uses the committed package resolution.
It does not install anything or use personal signing settings. Build products are under the ignored
`build/personal/baseline-derived` directory; the temporary source is removed on exit.

Only **“Pinned upstream iOS simulator compile passed”** is a successful result. Save a failure's error
text without personal information. Do not proceed as though a failed baseline built. Simulator compilation
cannot exercise Bluetooth, the strap, overnight collection, HealthKit provisioning, or widget signing.

## 3. Give the personal app its own identity

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
| Embedded watch app | `com.cyrilbhau.personalhealth.noop.watch` |
| Watch complications | `com.cyrilbhau.personalhealth.noop.watch.complications` |

The `.staging` suffix on the App Group is intentional upstream configuration. Keep it consistent.
The unique app identifier creates a separate app sandbox/database; the unique App Group separates
widget snapshots. This does **not** isolate Apple Health, which remains the phone's shared health
store. The personal app may still be labelled “NOOP” on the Home Screen, so check its bundle ID in
Xcode rather than identifying it by its icon alone. Leave an existing installation and its data intact.

## 4. Build the fork, then sign and run in Xcode

```bash
bash Tools/personal/ios.sh build
bash Tools/personal/ios.sh open
```

The first command is another unsigned simulator compilation, this time of the prepared fork.
The second generates the project and opens Xcode; it does not build, provision, or install the app.
Never commit the generated `Strand.xcodeproj` project or build output. The tracked package lockfile
inside the generated project remains part of the source baseline.

1. Connect the unlocked iPhone to the Mac with a cable. Choose **Trust** if asked.
2. Enable **Settings → Privacy & Security → Developer Mode** on the iPhone if Xcode requests it;
   follow the phone's restart prompt.
3. In Xcode select the blue project icon, then **Signing & Capabilities**. Confirm the paid Team
   and **Automatically manage signing** on `NOOPiOS`, `NOOPiOSWidgets`, `NOOPWatch`, and
   `NOOPWatchComplications`. The watch targets are embedded even when an Apple Watch is not used.
4. Confirm **HealthKit** and **HealthKit background delivery** on `NOOPiOS`, and the same App Group
   on the app and widget targets. Preserve the embedded watch targets' generated capabilities too.
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
