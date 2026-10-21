#!/usr/bin/env bash
# Local-only build helpers for the personal iOS fork. No install, upload, or device writes.
set -euo pipefail

BASELINE_COMMIT=8e4b0c16e7640607600fa6bde5424095eba6034e
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)

usage() {
    cat <<'USAGE'
Usage: bash Tools/personal/ios.sh COMMAND

  check       Check the Mac's Xcode, iOS simulator SDK, and XcodeGen versions.
  baseline    Compile the pinned, unmodified upstream iOS app without signing.
  configure --prefix YOUR.UNIQUE.PREFIX --team ABCDE12345
              Create the existing gitignored personal signing configuration.
              Refuse to overwrite a different existing configuration.
  build       Generate and compile this fork for iOS Simulator without signing.
  open        Generate the project and open it in Xcode for manual device signing.
  help        Show this help.

No command installs an app, requests provisioning, publishes, or modifies a strap.
The baseline and build commands require macOS, Xcode 26+, and XcodeGen 2.45+.
USAGE
}

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }

require_macos() {
    [[ $(uname -s) == Darwin ]] || fail 'iOS app builds require a Mac with Xcode; Linux package tests cannot build the iPhone app.'
}

version_at_least() {
    local value=$1 required_major=$2 required_minor=$3 major minor
    [[ $value =~ ([0-9]+)\.([0-9]+) ]] || return 1
    major=${BASH_REMATCH[1]}
    minor=${BASH_REMATCH[2]}
    (( major > required_major || (major == required_major && minor >= required_minor) ))
}

check_tools() {
    require_macos
    command -v xcodebuild >/dev/null || fail 'Install full Xcode, open it once, and select it in Xcode Settings > Locations > Command Line Tools.'
    command -v xcrun >/dev/null || fail 'Xcode command line tools are unavailable.'
    command -v xcodegen >/dev/null || fail 'Install XcodeGen 2.45 or newer (brew install xcodegen).'
    local xcode_version simulator_version xcodegen_version
    xcode_version=$(xcodebuild -version)
    simulator_version=$(xcrun --sdk iphonesimulator --show-sdk-version)
    xcodegen_version=$(xcodegen --version)
    version_at_least "$xcode_version" 26 0 || fail 'Xcode 26 or newer is required by the current iOS interface.'
    version_at_least "$simulator_version" 26 0 || fail 'An iOS 26 or newer simulator SDK must be installed in Xcode.'
    version_at_least "$xcodegen_version" 2 45 || fail 'XcodeGen 2.45 or newer is required.'
    printf '%s\niOS simulator SDK: %s\n%s\n' "$xcode_version" "$simulator_version" "$xcodegen_version"
}

configure() {
    local prefix='' team='' config_path="$REPO_ROOT/Config/BundleIdSecrets.xcconfig" expected
    while (( $# )); do
        case "$1" in
            --prefix) (( $# >= 2 )) || fail '--prefix requires a value.'; prefix=$2; shift 2 ;;
            --team) (( $# >= 2 )) || fail '--team requires a value.'; team=$2; shift 2 ;;
            *) fail "Unknown configure argument: $1" ;;
        esac
    done
    [[ $prefix =~ ^[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z][A-Za-z0-9-]*)+$ ]] || fail 'Use a reverse-domain prefix containing letters, numbers, dots, or hyphens; no spaces or shell syntax.'
    case "$prefix" in
        com.noopapp|com.noopapp.*|com.example|com.example.*|com.yourdomain|com.yourdomain.*)
            fail 'Choose a unique personal prefix, rather than an upstream or example identifier.' ;;
    esac
    [[ $team != YOURTEAMID ]] || fail 'Replace YOURTEAMID with the Team ID from Apple Developer Membership details.'
    [[ $team =~ ^[A-Z0-9]{10}$ ]] || fail 'Use the 10-character Team ID from Apple Developer Membership details, not a password or API key.'
    [[ -d "$REPO_ROOT/Config" && -f "$REPO_ROOT/Config/BundleId.xcconfig" ]] || fail 'The supported Config/BundleId.xcconfig wrapper is missing.'
    expected=$(printf '// Local personal signing configuration. Never commit this file.\nBUNDLE_ID_PREFIX = %s\nDEVELOPMENT_TEAM = %s\n' "$prefix" "$team")
    if [[ -L $config_path ]]; then
        fail 'The signing configuration is a symlink; inspect it manually rather than replacing it.'
    elif [[ -e $config_path ]]; then
        [[ -f $config_path ]] || fail 'The existing signing configuration is not a regular file.'
        [[ $(cat "$config_path") == "$expected" ]] || fail 'A different Config/BundleIdSecrets.xcconfig already exists. It was preserved; inspect it in a text editor.'
        printf 'The requested personal configuration already exists; no changes made.\n'
    else
        (umask 077; set -o noclobber; printf '%s\n' "$expected" > "$config_path")
        printf 'Created gitignored Config/BundleIdSecrets.xcconfig.\n'
    fi
    printf 'iPhone app: %s.noop\nWidgets: %s.noop.widgets\nApp Group: group.%s.noop.staging\n' "$prefix" "$prefix" "$prefix"
    printf 'These identifiers must differ from every NOOP copy you want to keep. Open Xcode next to check all targets and capabilities.\n'
}

require_personal_config() {
    [[ -f "$REPO_ROOT/Config/BundleIdSecrets.xcconfig" ]] || fail 'Run configure with a unique personal prefix and your Developer Team ID first.'
}

compile_simulator() {
    local source_root=$1 derived_root=$2
    (cd -- "$source_root" && xcodegen generate)
    xcodebuild -project "$source_root/Strand.xcodeproj" -scheme NOOPiOS \
        -configuration Debug -destination 'generic/platform=iOS Simulator' \
        -derivedDataPath "$derived_root" -onlyUsePackageVersionsFromResolvedFile \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
}

command_name=${1:-help}
(( $# == 0 )) || shift
case "$command_name" in
    help|--help|-h) (( $# == 0 )) || fail 'help takes no arguments.'; usage ;;
    configure) configure "$@" ;;
    check)
        (( $# == 0 )) || fail 'check takes no arguments.'
        check_tools ;;
    baseline)
        (( $# == 0 )) || fail 'baseline takes no arguments.'
        check_tools
        git -C "$REPO_ROOT" cat-file -e "$BASELINE_COMMIT^{commit}" || fail 'The pinned baseline commit is missing from the local repository.'
        baseline_tmp=$(mktemp -d "${TMPDIR:-/tmp}/noop-baseline.XXXXXX")
        trap 'rm -rf -- "$baseline_tmp"' EXIT
        mkdir -- "$baseline_tmp/source"
        git -C "$REPO_ROOT" archive "$BASELINE_COMMIT" | tar -xf - -C "$baseline_tmp/source"
        printf 'Building unmodified upstream commit %s. No personal signing configuration is included.\n' "$BASELINE_COMMIT"
        compile_simulator "$baseline_tmp/source" "$REPO_ROOT/build/personal/baseline-derived"
        printf 'Pinned upstream iOS simulator compile passed. This does not verify Bluetooth or device installation.\n' ;;
    build)
        (( $# == 0 )) || fail 'build takes no arguments.'
        check_tools
        require_personal_config
        compile_simulator "$REPO_ROOT" "$REPO_ROOT/build/personal/fork-derived"
        printf 'Fork iOS simulator compile passed. This does not verify signing, Bluetooth, or device installation.\n' ;;
    open)
        (( $# == 0 )) || fail 'open takes no arguments.'
        check_tools
        require_personal_config
        (cd -- "$REPO_ROOT" && xcodegen generate)
        open "$REPO_ROOT/Strand.xcodeproj" ;;
    *) usage >&2; fail "Unknown command: $command_name" ;;
esac
