# Linux development environment for the personal iOS fork

The cloud workspace runs Linux. It can compile/test protocol, storage, analytics and import packages. It cannot build the iPhone app, run an iOS simulator, sign an app, exercise CoreBluetooth/HealthKit/WidgetKit, or prove locked-phone collection. Those checks require Xcode on a Mac and the owner's iPhone/WHOOP 4.0; see the personal iOS instructions.

## Prepare and run package checks

From the existing checkout, without creating a worktree:

```bash
cd /workspace/noop-fork
bash Tools/personal/linux-env.sh bootstrap
bash Tools/personal/linux-env.sh test
# To rerun a relevant individual suite:
bash Tools/personal/linux-env.sh test WhoopProtocol
bash Tools/personal/linux-env.sh test WhoopStore StrandAnalytics StrandImport
```

The default test command runs `WhoopProtocol`, `WhoopStore`, `StrandAnalytics` and `StrandImport` sequentially, with four compiler jobs per package. `OuraProtocol`, `PolarProtocol` and `NoopLocalAccess` are also accepted as explicit package names. `StrandDesign` uses SwiftUI and is not supported by this Linux helper. Each invocation bootstraps idempotently, then captures each selected test's output in `/workspace/noop-validation/` with a timestamp, process ID and package name. It retains the Swift command's failure status even when output is piped to `tee`, attempts the remaining selected packages, and exits with the first failure status. A log-write error also fails the run. Do not treat skipped or Darwin-excluded tests as passed coverage.

Prerequisites already available in this cloud machine are an x86_64 Linux host, C compiler/linker and development headers, `make`, `curl`, `git`, `gpg`, `tar`, `sha256sum`, `awk`, Python 3 and `flock`, plus the shared libraries required by the official Swift Ubuntu 22.04 archive. No command in the helper uses `sudo`, changes system packages, edits application source, or updates lockfiles deliberately. Missing C/runtime prerequisites fail setup and require an image with those dependencies; the script does not disable verification or rewrite a checksum to proceed. `docs/BUILD.md` lists the usual Linux distribution dependencies.

## Tool versions and verification

The helper prepares these tools under `/workspace/.toolchains`, outside the project checkout:

- **Swift 6.0.3, official Ubuntu 22.04 x86_64 release.** It downloads the official HTTPS tarball and detached signature from `download.swift.org`, imports public Swift release keys from the official `swiftlang/swift-org-website` repository, and requires a valid GPG signature by fingerprint `52BB7E3DE28A71BE22EC05FFEF80A866B47A981F`. A downloaded key bundle alone is not trusted: the pinned signer must match. Cached archives are signature-checked on every bootstrap. An existing version-matching installation is reused.
- **SQLite 3.53.4 with `SQLITE_ENABLE_SNAPSHOT=1`.** GRDB's Linux path needs snapshot APIs. The official SQLite Git repository's `version-3.53.4` tag is fetched and the commit must equal `b09c88c14082339b66c7b7158d609a771e64ca69`. The amalgamation is generated out of tree with `configure --disable-readline --disable-tcl` and `make sqlite3.c -j 4`. Its SHA-256 must equal the unchanged upstream `docs/BUILD.md` value `b1dd5d74ec7f29055a6684fa06fb3c2f6821c87dd38f9a458dfd2e8a1db28189`. The generated header is pinned to `919e7f2e8ed1d8f56ac17b412b8971c76aa5d1a879752cc6058f75e7d5910e1d`. The private shared library is checked for version, enabled snapshot compilation and snapshot symbols before reuse. The existing system SQLite is not replaced.

Direct `sqlite.org` amalgamation download returned HTTP 403 during setup. Generating the identical, checksum-verified amalgamation from the official Git mirror provided the supported fallback. This did not relax integrity checks. Cached verified sources avoid that download in later runs. Tool downloads, extracted toolchains, SQLite sources and build caches can be retained in an environment snapshot; they contain no user credentials or health data.

Required network destinations are `download.swift.org`, `raw.githubusercontent.com` and `github.com` (including the platform's existing Git proxy route). No account, WHOOP subscription, Hevy API key or hosted service is used for package validation. TLS verification remains enabled. A signature/checksum mismatch stops setup and preserves the unexpected cached artifact for diagnosis; do not add verification-bypass flags.

## Cache and link configuration

The helper sets workspace-writable caches because the cloud home directory may be read-only:

```text
CLANG_MODULE_CACHE_PATH=/workspace/.cache/clang
SWIFT_MODULECACHE_PATH=/workspace/.cache/clang
Swift --cache-path /workspace/.cache/swiftpm
Swift --config-path /workspace/.config/swiftpm
Swift --security-path /workspace/.config/swiftpm-security
```

It prepends the prepared Swift `usr/bin` to `PATH` in the helper process. GRDB-linked tests receive `LD_LIBRARY_PATH=/workspace/.toolchains/sqlite-snapshot` (preserving any existing additional entries), `-Xcc -I/workspace/.toolchains/sqlite-snapshot` and `-Xlinker -L/workspace/.toolchains/sqlite-snapshot`. These settings are deliberately scoped to the helper; they do not rewrite shell profiles or globally replace tools. `NOOP_WORKSPACE` can select a different writable root; the default and the validated cloud configuration are `/workspace`.

Bootstrap serializes tool installation with a file lock. Test processes may reuse the prepared tools, but do not run two SwiftPM builds in the same package build directory simultaneously. The script does not stop other processes or delete build directories. Existing repository checkouts remain in place.

## Evidence and remaining gates

The helper's shell syntax and reuse of the prepared Swift/SQLite environment were checked in this workspace. SQLite amalgamation generation was also rerun in a separate temporary build directory; both generated source and header matched the pinned hashes. The complete test counts and outcomes belong in the task's validation report; existence of a test script is not evidence that its commands ran. Fresh-machine restoration and every clean-install download branch have not been independently exercised here.

The owner's Mac has since completed the baseline/personal builds, identity setup, relevant tests and final unsigned iPhone-only build; see `MAC-STATUS.md`. Current next gates are Apple device status Enabled, signed app/widget provisioning, installation/launch on the actual iPhone, and the collection/accuracy checks in `COLLECTION-AUDIT.md`. Do not restore watch embedding or repeat watch builds. Passing Linux package tests alone cannot establish those Mac or physical-device results.
