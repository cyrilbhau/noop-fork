# Validation record — 21 October 2026

Audited baseline: `8e4b0c16e7640607600fa6bde5424095eba6034e`. Linux x86_64, Swift 6.0.3,
snapshot-enabled SQLite 3.53.4. This record separates engine checks from the unrun Apple app build.
No health export, API credential, iPhone or WHOOP device was available.

## Executed checks

| Check | Result |
|---|---|
| WHOOP protocol package | 816 XCTest cases executed, 815 passed, 1 skipped, 0 failures. |
| Storage package | 621 XCTest cases executed and passed, 0 failures. |
| Analytics package | 2,143 XCTest cases executed and passed, 0 failures. |
| Import package, unmodified baseline | **Build failed**: `XlsxSheet.swift` omitted the separate `FoundationXML` import needed on Linux. No import tests executed in that attempt. |
| Import package, after conditional import | 327 XCTest cases executed, 326 passed, 1 skipped, 0 failures. Existing WHOOP, Apple Health, Hevy and other importer fixtures ran; the user's real exports were unavailable. |
| Existing Python tools | 338 tests passed. |
| Personal build-helper behavior | 12 Python tests passed: private identity, preservation/repeatability, unsafe arguments, tool versions and Linux refusal. Tool commands are mocked in these tests; they are not Apple build evidence. |
| Personal widget payload | 13 standalone XCTest cases passed against the actual shared model/snapshot source. This covers legacy decoding, sources, missing/invalid data, real zero, no invented freshness, goals, midnight/time-zone/DST handling, sleep bounds and reload decisions. It does not compile WidgetKit views or app wiring. |
| Linux setup helper | Shell syntax and repeated bootstrap passed, preserving prepared tool mtimes. The documented wrapper ran the import suite successfully and retained its exit status. |
| Tool integrity | Swift detached GPG signature matched pinned release key. SQLite source/header hashes and snapshot API/version verified. Independent out-of-tree SQLite regeneration matched the same expected hashes. |
| Source checks | Detached-doc-comment lint, diff whitespace checks, JSON catalogs and the repository i18n gate passed. XcodeGen YAML parsed successfully; generation still requires the Mac tool. |

Across the four engine suites: **3,905 passed, 2 skipped, 0 failed** after the portability repair.
The separate Swift Testing runner prints a zero-test summary after XCTest; the completed XCTest
counts above are the evidence. The extra 13 widget cases are reported separately.

The protocol skip requires an optional WHOOP 5 raw optical corpus (`WHOOP_R20_CORPUS`); the import
skip requires a real Xiaomi export (`XIAOMI_REAL_DB`). Neither was supplied or generated. Darwin-only
Compression/raw-outbox tests compile out on Linux and are **unrun**, not passed or skipped cases.
`StrandDesign`, other device-brand packages, Android, app-target `StrandTests`, simulator and hardware
checks were not used as substitutes for the selected iPhone workflow.

## Apple build and hardware gate

Before personal app-source changes, the baseline iOS build was attempted through the build tool
entry point. `xcodebuild` was absent: the command could not execute, and no SDK or simulator exists
on Linux. Recorded status: **blocked/unrun**, not a failed application compile or a successful build.
The personal Mac preflight also correctly refused Linux with a clear explanation.

The new UI is **implemented but uncompiled**. A Swift 6.0.3 parse of the app publisher also encounters
pre-existing argument trailing-comma syntax in the immutable baseline; Xcode 26's newer Swift/Apple
SDK remains the required app check. Pure payload compilation cannot establish SwiftUI/WidgetKit or
CoreBluetooth compatibility. `Tools/personal/ios.sh baseline` and `build` supply the exact Mac commands;
they must both actually pass before calling the app build verified.

No app signing, provisioning, installation, live Bluetooth connection, locked-phone collection,
step accuracy, sleep accuracy, HealthKit writes/deletions, widget refresh, real import or iPhone
backup/restore test was performed. Keep all those outcomes **unverified**. The accepted first step
thresholds are ≤10% on each 500–1,000-step walk and ≤20 false steps in 30 seated minutes; no measured
walk results exist yet. Other quantitative tolerances remain proposals in the device plan.

## Reproduction and evidence

From `/workspace/noop-fork`:

```bash
bash Tools/personal/linux-env.sh bootstrap
bash Tools/personal/linux-env.sh test WhoopProtocol WhoopStore StrandAnalytics StrandImport
python3 -m unittest discover -s Tools -p 'test_*.py'
python3 -m unittest discover -s Tools/personal -p 'test_*.py'
python3 Tools/check_personal_widgets.py --swiftc /workspace/.toolchains/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc
```

Current-run engine logs and tool-integrity receipts are outside Git at `/workspace/noop-validation`.
The wrapper writes timestamped package logs there; the initial logs are `whoop-protocol.log`,
`whoop-store.log`, `strand-analytics.log`, `strand-import.log` and `python-tools.log`.
`strand-import-baseline-failure.log` preserves the diagnosed original failure. The baseline iOS
availability record is `baseline-ios.json`. No test data was downloaded from the user's accounts.

Reusable `install_script` and `start_skill` were saved to the cloud configuration draft. They
prepare/activate the retained Linux toolchain and explain the Mac/device gate. They do not start a
backend, publish an environment or app, or establish fresh-task restoration. Review and save the
changes in environment settings, then publish the environment when desired; publication has not
been verified by this task. Repository/network/credential settings were preserved.
