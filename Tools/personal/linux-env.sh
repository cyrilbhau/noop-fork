#!/usr/bin/env bash
# Personal-fork Linux bootstrap. App builds still require Xcode on macOS.
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
WORKSPACE="${NOOP_WORKSPACE:-/workspace}"
TOOLCHAINS="$WORKSPACE/.toolchains"
DOWNLOADS="$TOOLCHAINS/downloads"
SWIFT_RELEASE='swift-6.0.3-RELEASE-ubuntu22.04'
SWIFT_DIR="$TOOLCHAINS/$SWIFT_RELEASE"
SWIFT_URL="https://download.swift.org/swift-6.0.3-release/ubuntu2204/swift-6.0.3-RELEASE/$SWIFT_RELEASE.tar.gz"
SWIFT_SIGNER='52BB7E3DE28A71BE22EC05FFEF80A866B47A981F'
SQLITE_DIR="$TOOLCHAINS/sqlite-snapshot"
SQLITE_COMMIT='b09c88c14082339b66c7b7158d609a771e64ca69'
SQLITE_C_HASH='b1dd5d74ec7f29055a6684fa06fb3c2f6821c87dd38f9a458dfd2e8a1db28189'
SQLITE_H_HASH='919e7f2e8ed1d8f56ac17b412b8971c76aa5d1a879752cc6058f75e7d5910e1d'
VALIDATION_DIR="$WORKSPACE/noop-validation"
JOBS=4

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'USAGE'
Usage: bash Tools/personal/linux-env.sh bootstrap
       bash Tools/personal/linux-env.sh test [PACKAGE ...]

bootstrap: prepare verified Swift 6.0.3 and snapshot-enabled SQLite 3.53.4.
test:      bootstrap, then run the selected existing Swift package test suites.
Default:   WhoopProtocol WhoopStore StrandAnalytics StrandImport
Allowed:   those defaults, OuraProtocol, PolarProtocol, NoopLocalAccess

No system packages are installed. Files and caches live under /workspace;
NOOP_WORKSPACE can select another writable root. The existing checkout is used.
USAGE
}

fetch_if_missing() {
    local url="$1" destination="$2" temporary
    if [[ -s "$destination" ]]; then return; fi
    temporary="$(mktemp "$DOWNLOADS/.download.XXXXXX")"
    if curl --fail --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
        --retry 3 --connect-timeout 20 --max-time 900 --output "$temporary" "$url"; then
        mv -- "$temporary" "$destination"
    else
        rm -f -- "$temporary"
        fail "Download failed: $url (TLS verification remains enabled)."
    fi
}

verify_sha256() {
    local expected="$1" path="$2"
    printf '%s  %s\n' "$expected" "$path" | sha256sum --check --status \
        || fail "Checksum mismatch: $path; preserving the file for diagnosis."
}

verify_swift_archive() {
    local status_file="$VALIDATION_DIR/swift-signature.status"
    gpg --batch --homedir "$TOOLCHAINS/gnupg" --import "$DOWNLOADS/swift-keys.asc" \
        >"$VALIDATION_DIR/swift-key-import.log" 2>&1
    gpg --batch --homedir "$TOOLCHAINS/gnupg" --status-fd 1 \
        --verify "$DOWNLOADS/swift-6.0.3.tar.gz.sig" "$DOWNLOADS/swift-6.0.3.tar.gz" \
        >"$status_file" 2>"$VALIDATION_DIR/swift-signature.log" \
        || fail "Swift signature verification failed; see $VALIDATION_DIR/swift-signature.log."
    awk -v fingerprint="$SWIFT_SIGNER" \
        '$1 == "[GNUPG:]" && $2 == "VALIDSIG" && $3 == fingerprint { valid=1 } END { exit !valid }' \
        "$status_file" || fail 'Swift archive was not signed by the pinned Swift release key.'
}

verify_sqlite_library() {
    python3 - "$SQLITE_DIR/libsqlite3.so.0" <<'PY'
import ctypes
import sys
try:
    library = ctypes.CDLL(sys.argv[1])
    library.sqlite3_libversion.restype = ctypes.c_char_p
    library.sqlite3_compileoption_used.argtypes = [ctypes.c_char_p]
    library.sqlite3_compileoption_used.restype = ctypes.c_int
    assert library.sqlite3_libversion() == b"3.53.4"
    assert library.sqlite3_compileoption_used(b"ENABLE_SNAPSHOT") == 1
    for name in ("sqlite3_snapshot_get", "sqlite3_snapshot_open", "sqlite3_snapshot_free"):
        getattr(library, name)
except (OSError, AttributeError, AssertionError):
    sys.exit(1)
PY
}

prepare_sqlite() {
    local source_dir="$TOOLCHAINS/sqlite-source" source_head build_dir temporary
    if [[ ! -f "$SQLITE_DIR/sqlite3.c" || ! -f "$SQLITE_DIR/sqlite3.h" ]]; then
        if [[ ! -e "$source_dir" ]]; then
            temporary="$(mktemp -d "$TOOLCHAINS/.sqlite-source.XXXXXX")"
            if git clone --depth=1 --branch version-3.53.4 \
                https://github.com/sqlite/sqlite.git "$temporary" \
                >"$VALIDATION_DIR/sqlite-clone.log" 2>&1; then
                mv -- "$temporary" "$source_dir"
            else
                rm -rf -- "$temporary"
                fail "Official SQLite Git checkout failed; see $VALIDATION_DIR/sqlite-clone.log."
            fi
        fi
        source_head="$(git -C "$source_dir" rev-parse --verify 'HEAD^{commit}')"
        [[ "$source_head" == "$SQLITE_COMMIT" ]] \
            || fail "SQLite source checkout must be pinned to $SQLITE_COMMIT; preserving its current state."
        # Out-of-tree generation preserves the verified official source checkout.
        build_dir="$(mktemp -d "$TOOLCHAINS/.sqlite-build.XXXXXX")"
        if (cd "$build_dir" && "$source_dir/configure" --disable-readline --disable-tcl \
            && make sqlite3.c -j "$JOBS") >"$VALIDATION_DIR/sqlite-generate.log" 2>&1; then
            verify_sha256 "$SQLITE_C_HASH" "$build_dir/sqlite3.c"
            verify_sha256 "$SQLITE_H_HASH" "$build_dir/sqlite3.h"
            mkdir -p "$SQLITE_DIR"
            # Never overwrite an unexpected existing source file.
            if [[ -e "$SQLITE_DIR/sqlite3.c" ]]; then verify_sha256 "$SQLITE_C_HASH" "$SQLITE_DIR/sqlite3.c"; fi
            if [[ -e "$SQLITE_DIR/sqlite3.h" ]]; then verify_sha256 "$SQLITE_H_HASH" "$SQLITE_DIR/sqlite3.h"; fi
            cp -- "$build_dir/sqlite3.c" "$build_dir/sqlite3.h" "$SQLITE_DIR/"
            rm -rf -- "$build_dir"
        else
            fail "SQLite source generation failed; see $VALIDATION_DIR/sqlite-generate.log; build retained at $build_dir."
        fi
    fi
    verify_sha256 "$SQLITE_C_HASH" "$SQLITE_DIR/sqlite3.c"
    verify_sha256 "$SQLITE_H_HASH" "$SQLITE_DIR/sqlite3.h"
    if ! verify_sqlite_library; then
        temporary="$(mktemp "$SQLITE_DIR/.libsqlite3.XXXXXX")"
        cc -shared -fPIC -DSQLITE_ENABLE_SNAPSHOT=1 "$SQLITE_DIR/sqlite3.c" \
            -o "$temporary" >"$VALIDATION_DIR/sqlite-compile.log" 2>&1 \
            || fail "SQLite compilation failed; see $VALIDATION_DIR/sqlite-compile.log."
        mv -- "$temporary" "$SQLITE_DIR/libsqlite3.so.0"
    fi
    ln -sfn libsqlite3.so.0 "$SQLITE_DIR/libsqlite3.so"
    verify_sqlite_library || fail 'SQLite snapshot-library validation failed.'
    printf 'SQLite 3.53.4: source checksums and snapshot API verified.\n'
}

activate() {
    export PATH="$SWIFT_DIR/usr/bin:$PATH"
    export CLANG_MODULE_CACHE_PATH="$WORKSPACE/.cache/clang"
    export SWIFT_MODULECACHE_PATH="$WORKSPACE/.cache/clang"
    export LD_LIBRARY_PATH="$SQLITE_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    mkdir -p "$CLANG_MODULE_CACHE_PATH" "$WORKSPACE/.cache/swiftpm" \
        "$WORKSPACE/.config/swiftpm" "$WORKSPACE/.config/swiftpm-security"
}

bootstrap() {
    local program machine staging
    [[ "$(uname -s)" == Linux ]] || fail 'This helper is for Linux; use Tools/personal/ios.sh on a Mac.'
    machine="$(uname -m)"
    [[ "$machine" == x86_64 ]] || fail 'The pinned Swift archive supports x86_64 Linux only.'
    for program in curl gpg git tar sha256sum awk cc make python3 flock; do
        command -v "$program" >/dev/null || fail "Missing prerequisite: $program. See docs/personal/LINUX.md."
    done
    mkdir -p "$DOWNLOADS" "$VALIDATION_DIR" "$TOOLCHAINS/gnupg"
    chmod 700 "$TOOLCHAINS/gnupg"
    # Serialize bootstrap only. Parallel test processes may reuse the prepared tools.
    exec 9>"$TOOLCHAINS/noop-bootstrap.lock"
    flock 9
    fetch_if_missing "$SWIFT_URL" "$DOWNLOADS/swift-6.0.3.tar.gz"
    fetch_if_missing "$SWIFT_URL.sig" "$DOWNLOADS/swift-6.0.3.tar.gz.sig"
    fetch_if_missing 'https://raw.githubusercontent.com/swiftlang/swift-org-website/main/keys/all-keys.asc' \
        "$DOWNLOADS/swift-keys.asc"
    verify_swift_archive
    if [[ ! -x "$SWIFT_DIR/usr/bin/swift" ]]; then
        [[ ! -e "$SWIFT_DIR" ]] || fail "Incomplete Swift installation exists at $SWIFT_DIR; preserving it."
        staging="$(mktemp -d "$TOOLCHAINS/.swift-install.XXXXXX")"
        tar -xzf "$DOWNLOADS/swift-6.0.3.tar.gz" -C "$staging"
        [[ -x "$staging/$SWIFT_RELEASE/usr/bin/swift" ]] || fail "Swift archive has an unexpected layout: $staging."
        mv -- "$staging/$SWIFT_RELEASE" "$SWIFT_DIR"
        rmdir -- "$staging"
    fi
    "$SWIFT_DIR/usr/bin/swift" --version | tee "$VALIDATION_DIR/swift-version.log"
    awk '/Swift version 6[.]0[.]3/ { valid=1 } END { exit !valid }' "$VALIDATION_DIR/swift-version.log" \
        || fail 'Installed Swift does not match 6.0.3; preserving it for diagnosis.'
    printf 'Swift archive: GPG signature matches pinned release key.\n'
    prepare_sqlite
    activate
    flock -u 9
    exec 9>&-
    printf 'Linux package environment prepared; Xcode and physical-device validation remain separate.\n'
}

run_package_test() {
    local package="$1" logfile statuses
    logfile="$VALIDATION_DIR/$(date -u +%Y%m%dT%H%M%SZ)-$$-$package.log"
    printf '\nTesting %s; full output: %s\n' "$package" "$logfile"
    if (cd "$REPO_ROOT/Packages/$package" && swift test --jobs "$JOBS" \
        --cache-path "$WORKSPACE/.cache/swiftpm" \
        --config-path "$WORKSPACE/.config/swiftpm" \
        --security-path "$WORKSPACE/.config/swiftpm-security" \
        -Xcc "-I$SQLITE_DIR" -Xlinker "-L$SQLITE_DIR") 2>&1 | tee "$logfile"; then
        statuses=("${PIPESTATUS[@]}")
    else
        statuses=("${PIPESTATUS[@]}")
    fi
    # Preserve Swift's failure even when output is captured; also fail if log writing fails.
    if (( statuses[0] != 0 )); then return "${statuses[0]}"; fi
    return "${statuses[1]}"
}

command="${1:-help}"
case "$command" in
    bootstrap)
        [[ $# == 1 ]] || fail 'bootstrap takes no package arguments.'
        bootstrap
        ;;
    test)
        shift
        packages=("$@")
        if (( ${#packages[@]} == 0 )); then packages=(WhoopProtocol WhoopStore StrandAnalytics StrandImport); fi
        for package in "${packages[@]}"; do
            case "$package" in
                WhoopProtocol|WhoopStore|StrandAnalytics|StrandImport|OuraProtocol|PolarProtocol|NoopLocalAccess) ;;
                *) fail "Unsupported Linux test package: $package" ;;
            esac
        done
        bootstrap
        result=0
        for package in "${packages[@]}"; do
            if run_package_test "$package"; then
                printf 'PASS: %s\n' "$package"
            else
                status=$?
                printf 'FAIL: %s (exit %s)\n' "$package" "$status" >&2
                if (( result == 0 )); then result="$status"; fi
            fi
        done
        exit "$result"
        ;;
    help|-h|--help) usage ;;
    *) usage >&2; exit 2 ;;
esac
