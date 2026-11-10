# Baseline record

Stage 0 work packages 0B-1 (baseline record) and 0B-5 (package test reachability). New work is
judged against this file: a failure named here is pre-existing; anything else blocks.

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
