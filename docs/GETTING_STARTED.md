# Getting started with NOOP for iPhone

NOOP for iPhone is an iPhone adaptation of [NOOP by @ryanbr and its contributors](https://github.com/ryanbr/noop).
This guide covers building the adaptation from source with a separate app identity for each developer.
The current branch is `personal/iphone-baseline` in [`cyrilbhau/noop-fork`](https://github.com/cyrilbhau/noop-fork).
See the [README](../README.md) for the adaptation's scope and [LICENSE](../LICENSE) for the
PolyForm Noncommercial 1.0.0 terms.

The steps below produce a local development build. This repository does not provide a signed
iPhone download or promise an App Store, TestFlight, or public binary release. The app's current
Home Screen and widget display name is **NOOP Cyril**; the Xcode scheme is **NOOPiOS**.

## Prerequisites

- A Mac with **Xcode 26 or newer**, including an **iOS 26 or newer Simulator SDK**. Use a macOS
  version supported by that Xcode release: Xcode 26.3 supports macOS Sequoia 15.6 and later within
  Apple's listed range; newer Xcode releases can require newer macOS. Check
  [Apple's Xcode system requirements](https://developer.apple.com/xcode/system-requirements/).
- **XcodeGen 2.45 or newer**. With Homebrew installed: `brew install xcodegen`.
- An **iPhone running iOS 17 or newer**, supported by the installed Xcode, and a cable for the first run.
- An **Apple Developer Program team** for the documented physical-device signing path and its
  HealthKit and App Group capabilities. Sign in through **Xcode → Settings → Accounts**. Keep
  certificates and private keys on the Mac.
- A WHOOP strap owned by the person using the app for live Bluetooth collection. Simulator builds
  can check compilation and UI, but cannot validate strap communication or physical-device signing.

Open Xcode once, accept its terms, and install the required SDK components before continuing.
Linux package tests do not build or validate the iPhone app.

## 1. Clone and check the tools

Choose an unused directory, then run:

```bash
git clone --branch personal/iphone-baseline https://github.com/cyrilbhau/noop-fork.git
cd noop-fork
bash Tools/personal/ios.sh check
```

The check verifies macOS, Xcode, the Simulator SDK, and XcodeGen. If several Xcode versions are
installed, select the intended one under **Xcode → Settings → Locations → Command Line Tools**,
or prefix each helper command with its developer directory, for example:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash Tools/personal/ios.sh check
```

The helpers are documented in [`Tools/personal/ios.sh`](../Tools/personal/ios.sh). They generate
and compile locally; device signing and installation happen separately in Xcode.

## 2. Configure a separate app identity

Choose a unique reverse-domain bundle prefix belonging to the developer's account, and find the
10-character **Team ID** in the Apple Developer account's Membership details. Replace both
placeholders before running:

```bash
bash Tools/personal/ios.sh configure --prefix YOUR.UNIQUE.PREFIX --team YOURTEAMID
```

This creates **`Config/BundleIdSecrets.xcconfig`**, which is ignored by Git. The helper refuses
upstream/example prefixes and preserves any different existing configuration. If it reports an
existing file, inspect that file before making changes. Do not commit signing configuration,
credentials, or provisioning profiles.

The tracked [`Config/BundleId.xcconfig`](../Config/BundleId.xcconfig) uses that prefix consistently:

| Component | Derived identifier |
|---|---|
| iPhone app | `<prefix>.noop` |
| iPhone widget extension | `<prefix>.noop.widgets` |
| Shared App Group | `group.<prefix>.noop.staging` |

Keep the App Group's `.staging` suffix: the app and widget must use the same value. Use identifiers
different from every installed NOOP copy that should be preserved. A separate bundle identifier
creates a separate app container, and a separate App Group isolates widget snapshots. Apple Health
remains the phone's shared health store. Check bundle identifiers in Xcode; display names alone do
not identify an installation.

## 3. Build, sign, and run

```bash
bash Tools/personal/ios.sh build
bash Tools/personal/ios.sh open
```

`build` generates `Strand.xcodeproj` from [`project.yml`](../project.yml) and compiles the
**NOOPiOS** scheme for a generic iOS Simulator without signing. `open` regenerates the project
and opens it in Xcode. Neither command installs the app. Keep the generated project and build
output out of Git; retain the tracked Swift package lockfile.

For the physical iPhone:

1. Connect and unlock the phone. Complete the Mac trust prompt if shown. Enable **Settings →
   Privacy & Security → Developer Mode** on the phone if Xcode requests it.
2. Open the project's **Signing & Capabilities** settings. Confirm the developer's own Team and
   **Automatically manage signing** for **NOOPiOS** and **NOOPiOSWidgets**.
3. Confirm **HealthKit**, **HealthKit background delivery**, and the derived App Group on
   **NOOPiOS**. Confirm the same App Group on **NOOPiOSWidgets**. Provision both targets with the
   capabilities requested by the project. If an identifier belongs to another team, choose another
   prefix; keep the capabilities in place.
4. Select the **NOOPiOS** scheme and the connected **physical iPhone** as the destination. Confirm
   the app and widget bundle identifiers belong to this new installation, then press **Run**.
5. At first launch, review the app's terms and grant Bluetooth access for strap collection. Review
   any Apple Health permission request independently.

The **NOOPiOS** scheme embeds the iPhone widget extension. Watch sources and a separate watch
scheme remain in the repository, but the iPhone adaptation does **not** embed a watch app; no
watch target needs to be added for these steps.

Development provisioning expires. Check the installed profile's actual expiry and re-sign updates
using the same prefix and Team to retain that app's container. Keep existing installations and data
intact. After a successful run, stop the Xcode session and launch the app from the phone when testing
background or overnight collection; an attached debugger can change background behavior.

## 4. Pair and add history

Use the app's normal pairing flow for the owned strap. If another app currently holds the Bluetooth
connection, close it for the test and retry. On the phone, confirm live heart rate and battery,
complete a normal sync, then background and reopen the app to check reconnection. Before relying
on overnight collection, run a trial night and inspect the next morning's timeline and sync status.
A successful Simulator build does not establish those hardware behaviors. See the
[README](../README.md) for the adaptation's validation status and limitations.

Optional data sources are available under **Data sources**:

- **WHOOP Export** accepts an existing WHOOP export archive. Keep the original archive intact and
  import a copy. Create an app backup before adding history to a populated installation.
- **Apple Health** can import a selected `export.zip` archive locally. This file importer is separate
  from the live HealthKit connection.
- The iPhone **HealthKit connection reads Steps and workout summaries**. It does not write to
  Apple Health or read physiological HealthKit samples. Permissions are controlled in the
  Health app; an empty result does not prove that read permission was granted.
- Other import cards, including nutrition and workout files, are optional. No import is required
  to begin collecting from a strap.

A `.noopbak` restore replaces the local database. It is not an import or merge step for an existing
installation. Keep exports, backups, databases, and device logs private and outside Git.

## Optional Coach and network access

Strap collection, storage, and analytics run locally. **Coach** requires separate provider setup
and can be left unconfigured. Requests go directly to the chosen provider and include conversation
text; attaching metric and workout summaries requires the separate health-data consent. Provider
processing and retention policies apply. API-key providers use the developer's own credentials;
Custom providers use the configured endpoint.

The iPhone adaptation also contains a **ChatGPT subscription** connection. Availability depends on
OpenAI authorization and the account's eligible plan access; a ChatGPT subscription alone is not a
guarantee of access. Sign-in and permission to use plan usage are separate from permission to share
health summaries. Eligible requests consume that account's usage allowance. Each user connects
their own provider account; keep provider credentials out of Git.

The automatic release check is enabled by default. It can be disabled under **Settings → About →
Check automatically**. See the [privacy and network inventory](PRIVACY_SECURITY.md#11-network-paths-canonical-inventory)
for Coach, release checks, and other optional network paths.

## macOS, Android, and contributing

This guide covers the iPhone adaptation. The upstream project maintains the macOS reference app
and Android app; use [upstream NOOP](https://github.com/ryanbr/noop), its
[macOS build guide](https://github.com/ryanbr/noop/blob/main/docs/BUILD.md), and
[Android guide](https://github.com/ryanbr/noop/blob/main/android/README.md) for those routes.
Upstream release artifacts are separate from this adaptation's source build.

Before changing code, read [AGENTS.md](../AGENTS.md) and the [contributor guide](../CONTRIBUTING.md).
NOOP is independent of WHOOP, and its derived metrics are informational rather than medical advice;
see the [disclaimer](../DISCLAIMER.md).
