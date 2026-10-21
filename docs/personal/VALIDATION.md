# Validation record — 21 October 2026

Audited baseline: `8e4b0c16e7640607600fa6bde5424095eba6034e`. Linux x86_64, Swift 6.0.3,
snapshot-enabled SQLite 3.53.4. The initial cloud checks below had no Apple SDK, signing access,
iPhone or WHOOP device. Subsequent Mac results are recorded separately; see `MAC-STATUS.md`.

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

## Subsequent Mac verification

The owner's local task recorded the following completed work on 21 October 2026 (IST). The cloud
read its command results/build-summary outputs and final source diff; it did not rerun Xcode.

| Mac check | Recorded outcome |
|---|---|
| Unmodified pinned baseline | Build passed from an immutable temporary archive, signing disabled, arm64/x86_64 Simulator. Historical watch compilation preceded the later iPhone-only scope. |
| Personal Simulator app/widgets | Build passed after the `FormRow` access-level fix. Widget views compiled. |
| Relevant app-target tests | **94 passed, zero failures** across personal widget metrics, snapshots, settings defaults, HR/stress traces and widget telemetry. |
| Simulator launch | Installed/launched and first-run agreement screen visually checked; no agreement/permissions accepted. This run preceded watch removal. |
| Final iPhone-only iPhoneOS build | Build passed unsigned, with the iPhone app/widget only and no watch build/embedding. Compilation for hardware is not execution on the physical phone. |
| Signed physical build | Two attempts blocked during provisioning. Owner confirmed device status **Processing** and profiles excluded this phone. No successful signed build/install/launch. |

The cloud synchronized the exact four source changes shown by the Mac task. Resulting blob prefixes
match `8103a08b` (shared Settings), `279494c3` (project), `3c2cc7fb` (iPhone plist) and `5347b66f`
(widget plist). YAML/plist checks confirmed the iPhone/widget-only target graph, display names,
App Group placeholders, background identifiers and retained HealthKit declarations. This does not
establish signed entitlements; those require successful development provisioning.

The source/property change and the Mac build/compiler fix are now recorded together. Future
resumes must preserve the Mac's original uncommitted changes before merging the cloud branch;
see `MAC-CONTINUE.md`. No local signing config, profile, device identifier or app inventory was
transferred to the cloud source. The 94 Mac results are distinct from the earlier cloud counts.

## Initial cloud-only Apple build boundary (historical)

Before personal app-source changes, the baseline iOS build was attempted through the build tool
entry point. `xcodebuild` was absent: the command could not execute, and no SDK or simulator exists
on Linux. Recorded status: **blocked/unrun**, not a failed application compile or a successful build.
The personal Mac preflight also correctly refused Linux with a clear explanation.

At that earlier point, the new UI was **implemented but uncompiled**. A Swift 6.0.3 parse of the app publisher also encounters
pre-existing argument trailing-comma syntax in the immutable baseline; Xcode 26's newer Swift/Apple
SDK remains the required app check. Pure payload compilation cannot establish SwiftUI/WidgetKit or
CoreBluetooth compatibility. `Tools/personal/ios.sh baseline` and `build` supply the exact Mac commands;
the later Mac records above establish those completed builds.

No app signing, provisioning, installation, live Bluetooth connection, locked-phone collection,
step accuracy, sleep accuracy, HealthKit writes/deletions, widget refresh, real import or iPhone
backup/restore test was performed in the cloud. Physical signing/installation/launch and collection
remain **unverified** after the Mac update. The accepted first step
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
