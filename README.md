# NOOP for iPhone

An iPhone companion for an owned WHOOP strap, with local Bluetooth collection,
on-device history, and an optional AI Coach.

This project builds on [NOOP by @ryanbr and its contributors](https://github.com/ryanbr/noop).
It adds an iPhone-focused interface, workout workflows, widgets, and a ChatGPT
subscription connection for Coach. The underlying protocol, storage, and independent
recovery, strain, and sleep calculations come from NOOP.

[Build and run](docs/GETTING_STARTED.md) · [Project status](docs/PROJECT_STATUS.md) ·
[Contribute](CONTRIBUTING.md) · [Credits](ATTRIBUTION.md) · [License](LICENSE)

## What this version adds

| Area | iPhone additions |
|---|---|
| Daily view | A redesigned Today screen with Sleep, Recovery, and Strain rings, source labels, metric details, and configurable cards. |
| Navigation | Today, Sleep, Training, and Health tabs; a separate Coach tab; Profile access from the avatar. The earlier interface remains available through **Use classic Today**. |
| Training | Workout text paste with preview before saving, set-level Hevy CSV import, and Apple Health workout summaries. Imported summaries and full lifting logs remain distinguishable. |
| Coach | A native Coach view with optional ChatGPT subscription sign-in, alongside the existing API-key and Custom providers. Account access and consent to share health summaries are separate. |
| Widgets | Revised Home Screen and Lock Screen presentation, estimated-step/goal and sleep widgets, and Live Activities. |
| Accessibility | Larger Dynamic Type layouts, reduced-motion support, and shared score formatting across screens. |

These additions sit on top of upstream's Bluetooth collection, SQLite storage,
importers, backup format, and analytics. The project retains upstream's macOS and
Android source; the interface described here targets **iPhone**. Apple Watch is not
embedded in this version's iPhone build.

## Get it running

Distribution is currently **from source**. There is no signed iPhone download,
TestFlight invitation, or App Store release for this adaptation. Upstream NOOP
downloads contain upstream's app and interface.

The build needs a Mac, Xcode 26 or newer, XcodeGen 2.45 or newer, and personal
signing configuration. The app deployment target is iOS 17; the newer SDK is needed
to compile the interface.

```bash
git clone --branch personal/iphone-baseline https://github.com/cyrilbhau/noop-fork.git
cd noop-fork
bash Tools/personal/ios.sh check
```

Continue with the [setup guide](docs/GETTING_STARTED.md) to configure a unique app
identity, sign the app and widgets, and run on an iPhone. The installed display name
is currently **NOOP Cyril**; **NOOPiOS** is the Xcode scheme.

An owned WHOOP strap is needed for live collection. Existing WHOOP exports and Apple
Health export files can also be imported locally. Keep original exports and make an
app backup before adding history to an existing installation.

## What to expect

The development focus is **iPhone with WHOOP 4.0**. The inherited code also supports
other devices, but that does not establish validation for this adaptation. See
[project status](docs/PROJECT_STATUS.md) for the scope and remaining checks.

- **Scores are NOOP's own calculations.** Familiar Sleep, Recovery, and Strain labels
  do not make the results equivalent to WHOOP's proprietary scores. Sleep staging and
  derived metrics are estimates.
- **WHOOP 4.0 steps are estimated from motion.** Reliable phone-free counting remains
  unproven; an imported pedometer total does not validate the strap estimate.
- **WHOOP 4.0 blood oxygen is not measured by this app.** Historical imported values
  are a separate source. Skin temperature is useful as a provisional trend rather
  than a validated absolute measurement.
- **Background and overnight behavior need device testing.** A successful build or
  live heart-rate display does not establish complete stored history, sleep, or
  recovery. Widget refresh and backup/restore also need real-device checks.
- **HealthKit is limited to workout-summary reads in the shared baseline.** It does
  not write to Apple Health. File imports are a separate path.
- **Workout imports have limits.** Hevy CSV imports append and skip duplicate start
  times; they do not reconcile later edits or deletions. There is no direct Hevy or
  Strava account sync.

## Data and privacy

Strap collection, imports, storage, and analytics run on the device. This project
operates no backend, health-data account, or telemetry service.

Coach is optional. Requests go directly to the chosen provider and include
conversation text; health summaries require separate consent. ChatGPT subscription
access depends on provider authorization and the account's eligible plan access,
and consumes that account's allowance. API-key and Custom providers remain available.

The inherited release check is **on by default** and contacts GitHub without health
data. It currently checks **upstream NOOP releases**, which do not describe this
adaptation's updates. Turn off **Settings → About → Check automatically** to disable
automatic checks. The app does not install updates itself.

The [privacy and network inventory](docs/PRIVACY_SECURITY.md#11-network-paths-canonical-inventory)
describes the network paths, consent controls, and platform-service boundaries.
Keep health exports, databases, backups, credentials, and device logs outside Git.

## Development

[`project.yml`](project.yml) is the source of truth for the generated Xcode project.
Core logic lives in Swift packages; platform app layers handle Bluetooth and UI.

| Location | Purpose |
|---|---|
| `StrandiOS/`, `StrandiOSShared/`, `StrandiOSWidgets/` | iPhone app, shared widget models, and widget extension |
| `Strand/` | macOS app and shared Apple app code |
| `Packages/WhoopProtocol/`, `Packages/WhoopStore/` | Protocol decoding and local persistence |
| `Packages/StrandAnalytics/`, `Packages/StrandImport/` | Analytics and file importers |
| `Packages/StrandDesign/` | Shared SwiftUI design system and iPhone components |
| `android/` | Inherited Android implementation |
| `Tools/personal/ios.sh` | Local configuration and build helpers |

A quick package check, without a strap:

```bash
cd Packages/WhoopProtocol
swift build
swift test
```

Package tests do not compile the app targets or validate Bluetooth. See
[CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md) for the appropriate checks,
cross-platform contracts, and safety requirements.

## Credits and license

The direct upstream is [ryanbr/noop](https://github.com/ryanbr/noop), based here on
commit [`8e4b0c16`](https://github.com/ryanbr/noop/commit/8e4b0c16e7640607600fa6bde5424095eba6034e).
Credit belongs to its maintainers and contributors for the foundation, and to the
earlier interoperability projects recorded in [ATTRIBUTION.md](ATTRIBUTION.md).
The retained Git history records the upstream and iPhone work.

The source retains the [PolyForm Noncommercial 1.0.0 license](LICENSE), including
the upstream required notice. It is source-available; it is not offered under an
OSI open-source license. Dependencies retain their own terms; see [NOTICE](NOTICE)
and the [Apple dependency license texts](LICENSES/README.md). Permission to redistribute
some earlier inherited source has not been verified; public sharing remains pending that
[permission review and the history privacy decision](docs/PUBLICATION_REVIEW.md).

NOOP for iPhone is independent of WHOOP, Inc. and OpenAI. It is not endorsed by
either company and is not a medical device. See [DISCLAIMER.md](DISCLAIMER.md).
