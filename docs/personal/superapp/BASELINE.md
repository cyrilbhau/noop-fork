# Baseline record

Stage 0 work packages 0B-1 (baseline record) and 0B-5 (package test reachability). New work is
judged against this file: a failure named here is pre-existing; anything else blocks.

Contents: [what was run](#0b-1--baseline-run) · [summary](#summary-table) ·
[pre-existing failures](#pre-existing-failures) · [not run](#not-run) · [skipped tests](#skipped-tests) ·
[how to compare](#comparing-a-later-run) · [package reachability](#0b-5--package-test-reachability)

## 0B-1 — Baseline run

| Item | Value |
|---|---|
| Source commit | `6413d94cab04aea05e798a628132dfb11a464c8a` (`personal/superapp-0-gate`, identical in product code and tests to `personal/superapp-0-foundation` at the same commit) |
| Baseline branch tip, used as the i18n diff base | `origin/personal/iphone-baseline` = `85fc53294f104a53af03118222ccc767a8ec10ce` |
| Date | 10 November 2026 (run stamp `20261110T112208Z`) |
| Command | `bash Tools/personal/gate.sh` with no options, from the repository root |
| Exit status | 1 (four checks FAILED, three NOT RUN) |
| Host | macOS 27.0.1 (26A434), arm64 |
| Xcode | 27.2 (27B52), iOS Simulator SDK 27.2 |
| Swift | Apple Swift 6.4.2 (swiftlang-6.4.2.1.9) |
| XcodeGen | 2.45.4 |
| Python | 3.14.4 (CI pins 3.12) |
| JDK 17, Android SDK | Not installed |

The working tree held only the gate script itself (untracked at the time, committed afterwards
unchanged) and ignored local files. No product code or test was modified.

One ignored local file was created for the run: `Config/BundleIdSecrets.xcconfig`, written by
`bash Tools/personal/ios.sh configure --prefix dev.noopgate.local --team GATE000000`. Both values
are placeholders. `Tools/personal/ios.sh build` refuses to run without that file, and an unsigned
simulator build does not use the team. The placeholder prefix also keeps the macOS test host away
from the bundle identifier of any real installed copy. A worktree that lacks the file reports
`ios-build` as NOT RUN.

### Summary table

Full table as printed (durations are from this run and will vary):

```text
Gate summary  commit 6413d94cab04  branch personal/superapp-0-gate  20261110T112208Z

CHECK                  RESULT             EXECUTED  PASSED FAILED SKIPPED  DURATION  LOG
xcodegen               PASS                      -       -      -       -     0m00s  build/gate/20261110T112208Z/xcodegen.log
spm:WhoopProtocol      PASS                    816     815      0       1     0m19s  build/gate/20261110T112208Z/spm-WhoopProtocol.log
spm:OuraProtocol       PASS                    267     267      0       0     0m13s  build/gate/20261110T112208Z/spm-OuraProtocol.log
spm:PolarProtocol      PASS                     25      25      0       0     0m12s  build/gate/20261110T112208Z/spm-PolarProtocol.log
spm:WhoopStore         PASS                    637     637      0       0     0m39s  build/gate/20261110T112208Z/spm-WhoopStore.log
spm:StrandAnalytics    PASS                   2150    2150      0       0     2m37s  build/gate/20261110T112208Z/spm-StrandAnalytics.log
spm:StrandImport       PASS                    329     328      0       1     0m34s  build/gate/20261110T112208Z/spm-StrandImport.log
spm:StrandDesign       PASS                    211     211      0       0     0m23s  build/gate/20261110T112208Z/spm-StrandDesign.log
spm:NoopLocalAccess    PASS                     14      14      0       0     0m22s  build/gate/20261110T112208Z/spm-NoopLocalAccess.log
macos-build            PASS                      -       -      -       -     3m18s  build/gate/20261110T112208Z/macos-build.log
macos-test             FAIL                   2454    2447      5       2     1m49s  build/gate/20261110T112208Z/macos-test.log
                         note: exit 65
ios-build              PASS                      -       -      -       -     3m30s  build/gate/20261110T112208Z/ios-build.log
doc-comment-lint       PASS                      -       -      -       -     0m02s  build/gate/20261110T112208Z/doc-comment-lint.log
protocol-doc-examples  PASS                      -       -      -       -     0m00s  build/gate/20261110T112208Z/protocol-doc-examples.log
protocol-doc-refs      PASS                      -       -      -       -     0m00s  build/gate/20261110T112208Z/protocol-doc-refs.log
i18n-audit             PASS                      -       -      -       -     0m23s  build/gate/20261110T112208Z/i18n-audit.log
py-linux-capture       PASS                    234     233      0       1     0m03s  build/gate/20261110T112208Z/py-linux-capture.log
py-parity-acceptance   FAIL                     50      48      2       0     1m07s  build/gate/20261110T112208Z/py-parity-acceptance.log
                         note: exit 1
py-rr-contract         PASS                      2       2      0       0     0m00s  build/gate/20261110T112208Z/py-rr-contract.log
py-core-tools          FAIL                    154     150      4       0     0m09s  build/gate/20261110T112208Z/py-core-tools.log
                         note: exit 1
personal-widgets       FAIL                      -       -      -       -     0m01s  build/gate/20261110T112208Z/personal-widgets.log
                         note: exit 1
android-assemble       NOT RUN                   -       -      -       -         -  -
                         note: no JDK 17 runtime (/usr/libexec/java_home -v 17 found none); no Android SDK (ANDROID_HOME, ANDROID_SDK_ROOT and android/local.properties sdk.dir are unset or have no platforms/)
android-test           NOT RUN                   -       -      -       -         -  -
                         note: no JDK 17 runtime (/usr/libexec/java_home -v 17 found none); no Android SDK (ANDROID_HOME, ANDROID_SDK_ROOT and android/local.properties sdk.dir are unset or have no platforms/)
parity-oracle          NOT RUN                   -       -      -       -         -  -
                         note: no --parity-cmd given for this stage

Failing tests in macos-test:
  BugReportTemplateTests/testAttachZipCheckboxPresent(): XCTAssertTrue failed
  BugReportTemplateTests/testHasTestProfileDropdownWithId(): XCTAssertTrue failed
  BugReportTemplateTests/testLogTextareaTellsToAttachZipNotPaste(): XCTAssertTrue failed
  BugReportTemplateTests/testSourceDropdownGainsImporters(): XCTAssertTrue failed - missing source importer: Oura import
  BugReportTemplateTests/testTestProfileOptionsCoverAllProfilesPlusEscapes(): XCTAssertTrue failed - missing test_profile option: Sleep & Rest

Failing tests in py-core-tools:
  FAIL: test_missing_backtick_target_reports_file_failure (test_check_source_references.SourceReferenceTests.test_missing_backtick_target_reports_file_failure)
  FAIL: test_missing_link_target_reports_file_failure (test_check_source_references.SourceReferenceTests.test_missing_link_target_reports_file_failure)
  FAIL: test_missing_symbol_reports_line_and_failure (test_check_source_references.SourceReferenceTests.test_missing_symbol_reports_line_and_failure)
  FAIL: test_qualified_signature_extracts_final_symbol_and_matches_whole_words (test_check_source_references.SourceReferenceTests.test_qualified_signature_extracts_final_symbol_and_matches_whole_words)

Failing tests in py-parity-acceptance:
  FAIL: test_checked_in_inventory_and_baseline_match_current_sources (tests.test_parity_governance_acceptance.RepositoryBaselineTests.test_checked_in_inventory_and_baseline_match_current_sources)
  FAIL: test_checked_metadata_is_compact_v3_and_expands_losslessly (tests.test_parity_governance_acceptance.RepositoryBaselineTests.test_checked_metadata_is_compact_v3_and_expands_losslessly)

Totals: 17 PASS, 4 FAIL, 3 NOT RUN, 0 NOT RUN (waived or filtered)
Logs: build/gate/20261110T112208Z   build/ size: 8.6G
```

Stable form for comparison (`summary-stable.txt`; no durations, no paths):

<!-- gate-stable:begin -->
```text
CHECK                  RESULT             EXECUTED  PASSED FAILED SKIPPED
xcodegen               PASS                      -       -      -       -
spm:WhoopProtocol      PASS                    816     815      0       1
spm:OuraProtocol       PASS                    267     267      0       0
spm:PolarProtocol      PASS                     25      25      0       0
spm:WhoopStore         PASS                    637     637      0       0
spm:StrandAnalytics    PASS                   2150    2150      0       0
spm:StrandImport       PASS                    329     328      0       1
spm:StrandDesign       PASS                    211     211      0       0
spm:NoopLocalAccess    PASS                     14      14      0       0
macos-build            PASS                      -       -      -       -
macos-test             FAIL                   2454    2447      5       2  exit 65
ios-build              PASS                      -       -      -       -
doc-comment-lint       PASS                      -       -      -       -
protocol-doc-examples  PASS                      -       -      -       -
protocol-doc-refs      PASS                      -       -      -       -
i18n-audit             PASS                      -       -      -       -
py-linux-capture       PASS                    234     233      0       1
py-parity-acceptance   FAIL                     50      48      2       0  exit 1
py-rr-contract         PASS                      2       2      0       0
py-core-tools          FAIL                    154     150      4       0  exit 1
personal-widgets       FAIL                      -       -      -       -  exit 1
android-assemble       NOT RUN                   -       -      -       -  no JDK 17 runtime (/usr/libexec/java_home -v 17 found none); no Android SDK (ANDROID_HOME, ANDROID_SDK_ROOT and android/local.properties sdk.dir are unset or have no platforms/)
android-test           NOT RUN                   -       -      -       -  no JDK 17 runtime (/usr/libexec/java_home -v 17 found none); no Android SDK (ANDROID_HOME, ANDROID_SDK_ROOT and android/local.properties sdk.dir are unset or have no platforms/)
parity-oracle          NOT RUN                   -       -      -       -  no --parity-cmd given for this stage

Failing tests in macos-test:
  BugReportTemplateTests/testAttachZipCheckboxPresent(): XCTAssertTrue failed
  BugReportTemplateTests/testHasTestProfileDropdownWithId(): XCTAssertTrue failed
  BugReportTemplateTests/testLogTextareaTellsToAttachZipNotPaste(): XCTAssertTrue failed
  BugReportTemplateTests/testSourceDropdownGainsImporters(): XCTAssertTrue failed - missing source importer: Oura import
  BugReportTemplateTests/testTestProfileOptionsCoverAllProfilesPlusEscapes(): XCTAssertTrue failed - missing test_profile option: Sleep & Rest

Failing tests in py-core-tools:
  FAIL: test_missing_backtick_target_reports_file_failure (test_check_source_references.SourceReferenceTests.test_missing_backtick_target_reports_file_failure)
  FAIL: test_missing_link_target_reports_file_failure (test_check_source_references.SourceReferenceTests.test_missing_link_target_reports_file_failure)
  FAIL: test_missing_symbol_reports_line_and_failure (test_check_source_references.SourceReferenceTests.test_missing_symbol_reports_line_and_failure)
  FAIL: test_qualified_signature_extracts_final_symbol_and_matches_whole_words (test_check_source_references.SourceReferenceTests.test_qualified_signature_extracts_final_symbol_and_matches_whole_words)

Failing tests in py-parity-acceptance:
  FAIL: test_checked_in_inventory_and_baseline_match_current_sources (tests.test_parity_governance_acceptance.RepositoryBaselineTests.test_checked_in_inventory_and_baseline_match_current_sources)
  FAIL: test_checked_metadata_is_compact_v3_and_expands_losslessly (tests.test_parity_governance_acceptance.RepositoryBaselineTests.test_checked_metadata_is_compact_v3_and_expands_losslessly)
```
<!-- gate-stable:end -->

### Counts per suite

| Suite | Executed | Passed | Failed | Skipped |
|---|---:|---:|---:|---:|
| `swift test` WhoopProtocol | 816 | 815 | 0 | 1 |
| `swift test` OuraProtocol | 267 | 267 | 0 | 0 |
| `swift test` PolarProtocol | 25 | 25 | 0 | 0 |
| `swift test` WhoopStore | 637 | 637 | 0 | 0 |
| `swift test` StrandAnalytics | 2150 | 2150 | 0 | 0 |
| `swift test` StrandImport | 329 | 328 | 0 | 1 |
| `swift test` StrandDesign | 211 | 211 | 0 | 0 |
| `swift test` NoopLocalAccess | 14 | 14 | 0 | 0 |
| **Packages total** | **4449** | **4447** | **0** | **2** |
| `StrandTests` (macOS, `Strand` scheme) | 2454 | 2447 | 5 | 2 |
| Python `Tools/linux-capture` | 234 | 233 | 0 | 1 |
| Python parity repository-acceptance | 50 | 48 | 2 | 0 |
| Python legacy R-R contract | 2 | 2 | 0 | 0 |
| Python core `Tools/test_*.py` | 154 | 150 | 4 | 0 |
| `Tools/check_personal_widgets.py` | none: failed to compile | | | |
| Android unit tests | not run | | | |

Checks without test counts: `xcodegen generate` passed; the macOS `Strand` build (universal,
`x86_64 arm64`) ended `** BUILD SUCCEEDED **`; the `NOOPiOS` simulator build ended
`** BUILD SUCCEEDED **` and embedded `NOOPWidgets.appex`; `doc_comment_lint.py` passed (23 baselined
sites remaining); both protocol-document checks passed; `i18n_audit.py --ci
origin/personal/iphone-baseline` passed.

The CI minimum-collected floors in `tools-python.yml` (200, 49, 2 and 114) were all met, so test
discovery is intact.

### Pre-existing failures

Twelve named failures in four checks. The four failing checks were run a second time
(`bash Tools/personal/gate.sh --only macos-test,py-parity-acceptance,py-core-tools,personal-widgets`,
run stamp `20261110T113810Z`): identical counts and identical failing names. Nothing flaked.

**`macos-test` — `StrandTests`, 5 failures, all in `BugReportTemplateTests`.** The tests read
`.github/ISSUE_TEMPLATE/bug_report.yml` and assert the upstream Test Centre fields. Commit
`158a5de3` on the baseline branch shortened that template (24 lines added, 132 removed), so the
fields are gone. These are newer than the redesign report, which recorded zero `StrandTests`
failures.

| Test | Reason |
|---|---|
| `BugReportTemplateTests/testAttachZipCheckboxPresent()` | `XCTAssertTrue failed`: the attach-zip checkbox is not in the template |
| `BugReportTemplateTests/testHasTestProfileDropdownWithId()` | `XCTAssertTrue failed`: no `id: test_profile` dropdown |
| `BugReportTemplateTests/testLogTextareaTellsToAttachZipNotPaste()` | `XCTAssertTrue failed`: the attach guidance text is absent |
| `BugReportTemplateTests/testSourceDropdownGainsImporters()` | `missing source importer: Oura import` |
| `BugReportTemplateTests/testTestProfileOptionsCoverAllProfilesPlusEscapes()` | `missing test_profile option: Sleep & Rest` |

**`py-core-tools` — 4 failures, all in `test_check_source_references.SourceReferenceTests`.** Each
compares an expected message built from a temporary path under `/var/...` with output that reports
the resolved path `/private/var/...`. On macOS `/var` is a symbolic link to `/private/var`; the
tests pass on Linux CI. These are the four the redesign report named.

| Test | Reason |
|---|---|
| `test_missing_backtick_target_reports_file_failure` | `AssertionError`: `/var/...` expected, `/private/var/...` reported |
| `test_missing_link_target_reports_file_failure` | same |
| `test_missing_symbol_reports_line_and_failure` | same |
| `test_qualified_signature_extracts_final_symbol_and_matches_whole_words` | same |

**`py-parity-acceptance` — 2 failures in
`tests.test_parity_governance_acceptance.RepositoryBaselineTests`.** The stored parity authority no
longer reproduces from the current sources. This is the item work package 0B-9 examines. The
redesign report recorded one failure here (509 against 510 files); there are now two and the
count is 512.

| Test | Reason |
|---|---|
| `test_checked_in_inventory_and_baseline_match_current_sources` | `AssertionError: Lists differ: [] != ['test-only-callsite\|Packages/WhoopProtocol']` |
| `test_checked_metadata_is_compact_v3_and_expands_losslessly` | `AssertionError`: stored authority has `files.count` 509, derived authority has 512 (hashes differ) |

The scanner globs tracked source directories and excludes build output, so the gate's own files
under `build/` do not contribute to that count.

**`personal-widgets` — `Tools/check_personal_widgets.py` fails before any test runs.** The script
compiles a driver that calls `XCTMain` with a bare `swiftc`; on macOS that stops at
`error: no such module 'XCTest'` (exit 1). The script's own header says it is meant to run "without
Apple SDKs", that is, with a Linux toolchain. On this Mac it has never been a working check, and the
same test file (`StrandTests/PersonalWidgetMetricsTests.swift`) is executed inside `StrandTests`
by `macos-test`. Zero tests executed here; it is recorded as FAIL, not as a pass.

### Not run

| Check | Reason |
|---|---|
| `android-assemble`, `android-test` | No JDK 17 runtime (`/usr/libexec/java_home -v 17` finds none; `/usr/bin/java` is the macOS stub) and no Android SDK (`ANDROID_HOME`, `ANDROID_SDK_ROOT` and `android/local.properties` all absent). Kotlin twins are therefore written and unverified until work package 0B-4 is decided. The Gradle branch of the gate script has itself never been executed. |
| `parity-oracle` | No `--parity-cmd` was given. There is no stage oracle yet; each stage supplies its own. |

Also outside this baseline, because §G4 does not list them: the `tools` job of
`swift-packages.yml` (`Tools/SleepBench`, `Tools/SleepPSG`, `Tools/Backfill`), the remaining modules
of `parity-governance.yml` (`test_parity_ledger`, `test_parity_disposition_kinds`,
`test_parity_harness`), `Tools/tests/test_parity_arity.py`, `Tools/tests/test_parity_artefact_filter.py`,
`Tools/personal/test_ios.py`, and the Windows leg. Nothing here exercises Bluetooth, signing, a
device, or the widget at run time.

### Skipped tests

| Suite | Test | Stated reason |
|---|---|---|
| WhoopProtocol | `Whoop5RawOpticalTests.testFullCorpusDecodesWithPublishedInvariants` | `WHOOP_R20_CORPUS` is not set (optional private corpus) |
| StrandImport | `XiaomiBandImporterTests.testRealExportIfAvailable` | optional real export not present |
| StrandTests | `RawHistoryArchiveReplayTests.testArchiveAndDirectoryUseBackgroundReadableProtection` | File Data Protection is iOS-only; `StrandTests` runs on the macOS scheme |
| StrandTests | `XiaomiImporterIntegrationTests.testRealExportRoundTripsIntoStore` | optional real export not present |
| `Tools/linux-capture` | `test_integration_real_db_if_present` | `real capture DB not present` |

### Disk

After the run `build/` held 8.7 GB: 5.2 GB for the one shared DerivedData tree
(`build/personal/fork-derived`, macOS universal plus iOS Simulator), 3.3 GB for the eight SwiftPM
scratch directories (`build/spm/`), and 0.2 GB of logs and result bundles (`build/gate/`). All of it
is ignored by Git and can be deleted; the next run rebuilds it.

### Comparing a later run

```bash
bash Tools/personal/gate.sh --compare docs/personal/superapp/BASELINE.md
```

prints a `diff` of the new stable summary against the block above. A line that differs is either a
count that moved or a failure that is not in this record. When the baseline legitimately changes
(for example a pre-existing failure is repaired in its own change), replace the block with the new
`build/gate/<stamp>/summary-stable.txt` and update the tables in the same commit.

## 0B-5 — Package test reachability

**Finding: nothing blocks `swift test`. All eight packages build and test on this Mac.**

The earlier handoffs ([CONTEXT.md](../CONTEXT.md), [STRAP-STEPS-REPAIR.md](../STRAP-STEPS-REPAIR.md))
say a full SwiftPM run "was blocked by an unavailable GRDB submodule checkout". That could not be
reproduced on 10 November 2026, and the description does not match how the repository is built:

- The repository has no Git submodules. There is no `.gitmodules` file and `git submodule status`
  prints nothing.
- GRDB is not vendored. It is an ordinary SwiftPM dependency fetched by URL at an exact version,
  `https://github.com/groue/GRDB.swift.git` `6.29.3`, declared in the `Package.swift` of
  `WhoopStore`, `StrandImport` and `NoopLocalAccess`, and reached by `StrandAnalytics` through its
  local path dependency on `WhoopStore`. `StrandImport` also fetches `ZIPFoundation` `0.9.20`.
  Each of those four packages has a tracked `Package.resolved`.
- `WhoopProtocol`, `OuraProtocol`, `PolarProtocol` and `StrandDesign` have no remote dependencies.

What a run needs: either network access to github.com for the first resolve, or a populated SwiftPM
repository cache. On this Mac the user-level SwiftPM cache already held GRDB and ZIPFoundation, so
the resolve logged `Fetching ... from cache` and needed no download. No tracked file was changed, no
submodule command was needed and nothing was installed.

The most likely cause of the earlier report is a run in a sandbox or worktree with neither network
access nor a warm cache, where the GRDB fetch fails; that is an environment condition and it would
recur in the same conditions. It was not investigated further because the original log was not kept.

Reproduction, from the repository root (the gate script runs the same thing per package):

```bash
cd Packages/WhoopStore
swift build --scratch-path ../../build/spm/WhoopStore
swift test  --scratch-path ../../build/spm/WhoopStore
```

`--scratch-path` only moves build products under the ignored `build/` directory; plain `swift test`
behaves the same. Per-package counts are in the baseline table below.
