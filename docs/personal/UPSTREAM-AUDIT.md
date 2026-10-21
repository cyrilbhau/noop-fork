# Upstream, license and issue audit

Audited on **21 October 2026**. Public GitHub issue and release pages were read directly, without
credentials. These are source and report observations, not validation on an iPhone or strap.

## Recorded baseline

- Upstream: <https://github.com/ryanbr/noop>.
- Exact audit baseline: **`8e4b0c16e7640607600fa6bde5424095eba6034e`**.
- Commit: `build: testing build 557 / 438`, authored and committed **15 October 2026, 17:31 UTC**
  (23:01 India time). `project.yml:21-24` sets app version **12.1.0**, iOS build **438**.
- At inspection, upstream `main` and rolling `testing-latest` pointed to that same SHA. The SHA is the
  reproducibility reference: a rolling tag can change.
- Latest stable release visible on GitHub: **v12.0.0**, published **4 October 2026**, commit
  **`7acce06c3d22cb5dfe959f2c4a43902471d21332`**. The selected baseline is newer testing code,
  **not a stable release or a hardware-qualified build**. Retaining its exact SHA permits comparison
  before applying personal changes; the 12.0.0 tag remains a comparison point if regressions arise.
- Release pages: [testing build](https://github.com/ryanbr/noop/releases/tag/testing-latest),
  [12.0.0](https://github.com/ryanbr/noop/releases/tag/v12.0.0).

**Installation trap:** the testing release explicitly states that its unsigned **iOS IPA uses the
production bundle identity and replaces an existing official NOOP installation**, sharing its data.
Android/macOS staging behavior does not establish iOS isolation. This personal project should be built
from source with its own bundle prefix and App Group, preserving any existing installation and data.

## License and dependency obligations

| Item | Evidence | Consequence for this personal fork |
|---|---|---|
| NOOP source and documentation | `LICENSE:1-19`, `LICENSE:74-84` | **PolyForm Noncommercial 1.0.0**, source available. Personal hobby modification without an anticipated commercial application is permitted. It is not an unrestricted commercial open-source grant. |
| Redistribution notices | `LICENSE:52-58` | Retain the license or its URL and **`Required Notice: Copyright 2026 NoopApp`** for recipients. Keep `LICENSE`, `NOTICE`, `ATTRIBUTION.md` and `DISCLAIMER.md` intact. |
| Protocol research | `NOTICE:24-40`, `ATTRIBUTION.md`, `DISCLAIMER.md:24-32` | Upstream describes clean-room implementations of observed wire facts, not copied proprietary code. Do not add WHOOP firmware, decompiled code, credentials or branded assets. |
| GRDB.swift | `Packages/WhoopStore/Package.swift:14`, `NOTICE:11-13` | Exact version **6.29.3**, MIT; preserve its upstream license/notices with any redistributed bundle. |
| ZIPFoundation | `Packages/StrandImport/Package.swift:14`, `project.yml:75-77`, `NOTICE:15-17` | Exact version **0.9.20**, MIT; preserve its upstream license/notices. |
| MarkdownUI | `project.yml:46-48`, `ATTRIBUTION.md:100-101` | Exact version **2.4.1**. It and its transitive dependencies appear in the committed Xcode SwiftPM lockfile; `NOTICE` only lists GRDB and ZIPFoundation. Before distributing a compiled app, include the license texts from the resolved MarkdownUI/NetworkImage/swift-cmark checkouts as well. Attribution alone is not the complete dependency notice inventory. |

The committed Xcode SwiftPM lockfile at
`Strand.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` also pins **NetworkImage
6.0.1** and **swift-cmark 0.8.0** by revision. Package-level `Package.resolved` files pin the GRDB and
ZIPFoundation dependencies used by headless tests. No dependency declarations or lockfiles were
changed by this audit. Apple signing tools, HealthKit and WidgetKit remain Apple platform prerequisites;
they are not supplied by the source license.

## Four reported problem areas: live status checked

| Report | Status observed on 21 October | What it establishes and what it does not |
|---|---|---|
| [#89: steps missing after update](https://github.com/ryanbr/noop/issues/89) | **Closed, completed**, linked merged [PR #124](https://github.com/ryanbr/noop/pull/124). Last issue update 9 July. | The reporter used iOS/4.0. The maintainer first identified missing Health import/calibration; a real import-to-`DailyMetric` omission was then repaired (`1bd6819`, merged `59087b0`; `docs/releases/v8.5.0.md:27`). This does **not** establish that native 4.0 step counts are readable or that phone-free estimates are accurate. |
| [#1313: sleep not tracked](https://github.com/ryanbr/noop/issues/1313) | **Open**, last update 14 August. | Android/4.0 report had HR and R-R but no motion; the maintainer identified a future-dated clock/backfill gate as a possible cause and requested evidence distinguishing records never banked from records dropped. It is not a proven iOS defect or evidence that a plausible HR chart guarantees sleep/recovery. |
| [#1021: Apple Health not updated after sleep](https://github.com/ryanbr/noop/issues/1021) | **Closed, completed**, linked merged [PR #1024](https://github.com/ryanbr/noop/pull/1024). Last update 1 August. | The maintainer identified foreground export racing asynchronous history offload and overly broad authorization gating. The linked fix (`063e97b`) runs write-back after an offload lands; `docs/releases/v9.3.1.md:65` records it. Actual locked-phone delivery and partial permissions still need a device check. |
| [#2264: HRV density and RMSSD labelled SDNN](https://github.com/ryanbr/noop/issues/2264) | **Open**, created 16 September. | The issue remains open, but its timeline links a computed-SDNN merge repair ([`1a312a9`](https://github.com/ryanbr/noop/commit/1a312a99d7e47ceb65fa9b060b86672ce6b7eaad)) and removal of the RMSSD-as-SDNN fallback ([`dab0efe`](https://github.com/ryanbr/noop/commit/dab0efe30214e9a0ccfe0e736971883fd79f9a0d)). Status alone cannot tell which parts remain. Inspect and test the current Health export code separately, including segmented HRV timing and summary-only imports. |

## Current risks relevant to this project

- **Steps remain the leading acceptance gate.** `docs/FEATURES.md:107-110` says 4.0's native step
  counter is not yet readable through this implementation. Its available paths include imported phone
  steps and calibrated estimates from strap motion. The [maintainer's #89 explanation](https://github.com/ryanbr/noop/issues/89#issuecomment-4914413521)
  gives the same limitation. A manual 500–1,000-step walk without the phone must validate the estimate;
  phone import and comparison against WHOOP are not substitutes for that test.
- [#2815](https://github.com/ryanbr/noop/issues/2815), **open**, created **20 October**: iOS 12.1.0
  testing, a **brand-new, never-provisioned** 4.0 bonds and acknowledges commands but delivers no HR/R-R
  while its optical AFE reports FIFO timeouts. This is not evidence that an already-used, functioning
  band has the same problem. It does bar a blanket claim that every factory-state 4.0 works.
- [#2808](https://github.com/ryanbr/noop/issues/2808), **open**, created **19 October**: iOS automatic
  workout candidate detection reportedly never starts because its task is attached to an empty
  `Group`. Manual workout recording and auto-detection must be evaluated separately.
- [#2818](https://github.com/ryanbr/noop/issues/2818), **open**, created **21 October**: Stress and
  Today HRV comparisons reportedly include nights before a manual Charge-baseline reset. A reassuring
  Today comparison is not enough to verify that all screens use the same baseline.
- [#2805](https://github.com/ryanbr/noop/issues/2805), **open**, created **17 October**: Android/4.0
  firmware **41.11.7.0**, a large offload stalled until app restart. Keep as a backfill stress-test
  case; do not label it a confirmed iOS failure.
- [#2793](https://github.com/ryanbr/noop/issues/2793), **open**, is a proposed bounded read-only 4.0
  optical diagnostic. It explicitly says the physical red/IR channel map is unvalidated. It supplies
  no justification for inventing new SpO₂ values or changing optical configuration.

The current open-issue index and the specific linked reports were inspected; this is a targeted
review, not an exhaustive review of every issue. User reports and merged patches describe observed
failures and intended fixes, not laboratory validation or this user's hardware results.

## Verification boundary

Read-only HTTPS Git access, the exact local HEAD, public release pages and issue statuses were
checked. Public `api.github.com` requests returned proxy **403**; allowed `github.com` HTML pages
provided the issue/release evidence, so no new token was needed or requested. No issue/comment was
posted, no workflow dispatched, no release downloaded or installed, and no source changed by this
audit. Test/build outcomes belong in the project validation report: this document does not claim a
successful iOS build, signing run, Bluetooth session or overnight recording.
