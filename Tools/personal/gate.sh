#!/usr/bin/env bash
# Local quality gate for the personal iPhone fork (docs/personal/superapp/QUALITY-GATES.md §G4).
#
# Usage: bash Tools/personal/gate.sh [options]
#
#   --packages a,b      Run `swift test` only for these packages under Packages/ (default: every
#                       package in the swift-packages.yml matrix). Unselected packages are listed
#                       as NOT RUN (filtered) and do not affect the exit code.
#   --base REF          Base ref for the diff-scoped i18n gate
#                       (default: origin/personal/iphone-baseline).
#   --waive a,b         Accept that these checks cannot run. A waived check that cannot run is
#                       listed as NOT RUN (waived) and does not affect the exit code. A waived
#                       check that CAN run still runs and still counts.
#   --only a,b          Run only these checks. Every other check is listed as NOT RUN (not
#                       selected), which makes the exit code non-zero: a partial run is not a gate.
#   --parity-cmd CMD    Shell command (run from the repository root) for the per-stage parity
#                       oracle. Without it the parity-oracle row is NOT RUN.
#   --android-fresh     Add `--no-build-cache --rerun-tasks` to the Gradle invocations (required
#                       after a branch switch, see AGENTS.md).
#   --compare FILE      After the run, diff the stable summary against the block between
#                       `<!-- gate-stable:begin -->` and `<!-- gate-stable:end -->` in FILE
#                       (for example docs/personal/superapp/BASELINE.md). Informational only.
#   --list              Print the check names and exit.
#   -h, --help          Show this help.
#
# Every check runs even when an earlier one fails. Full output of each check goes to
# build/gate/<timestamp>/<check>.log. One summary table is printed at the end and also written to
# summary.txt; summary-stable.txt holds the same rows without durations and paths, plus the names
# of failing tests, so two runs can be compared with diff.
#
# Result values: PASS, FAIL, NOT RUN. NOT RUN is never a pass. Exit status is 1 when any check
# FAILED or was NOT RUN without a waiver or package filter, else 0. Exit status 2 is a usage error.
#
# All xcodebuild invocations share ONE DerivedData tree, build/personal/fork-derived, which is the
# path Tools/personal/ios.sh build already uses. SwiftPM scratch directories live under build/spm/.
# Nothing is installed, signed, uploaded or written to a device.
#
# Written for the bash 3.2 that ships with macOS; needs only python3, git, Xcode and XcodeGen.

set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

# Package matrix: .github/workflows/swift-packages.yml, job `test`, matrix.package.
ALL_PACKAGES="WhoopProtocol OuraProtocol PolarProtocol WhoopStore StrandAnalytics StrandImport StrandDesign NoopLocalAccess"
DERIVED="$REPO_ROOT/build/personal/fork-derived"

PACKAGES_FILTER=''
BASE_REF='origin/personal/iphone-baseline'
WAIVE=''
ONLY=''
PARITY_CMD=''
ANDROID_FRESH=0
COMPARE=''
LIST=0

usage() { sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed -e 's/^# \{0,1\}//'; }
die_usage() { printf 'Error: %s\n' "$*" >&2; exit 2; }

while (( $# )); do
    case "$1" in
        --packages) (( $# >= 2 )) || die_usage '--packages requires a value.'; PACKAGES_FILTER=$2; shift 2 ;;
        --base) (( $# >= 2 )) || die_usage '--base requires a value.'; BASE_REF=$2; shift 2 ;;
        --waive) (( $# >= 2 )) || die_usage '--waive requires a value.'; WAIVE="$WAIVE,$2"; shift 2 ;;
        --only) (( $# >= 2 )) || die_usage '--only requires a value.'; ONLY="$ONLY,$2"; shift 2 ;;
        --parity-cmd) (( $# >= 2 )) || die_usage '--parity-cmd requires a value.'; PARITY_CMD=$2; shift 2 ;;
        --android-fresh) ANDROID_FRESH=1; shift ;;
        --compare) (( $# >= 2 )) || die_usage '--compare requires a value.'; COMPARE=$2; shift 2 ;;
        --list) LIST=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die_usage "Unknown argument: $1 (see --help)" ;;
    esac
done

CHECKS="xcodegen"
for p in $ALL_PACKAGES; do CHECKS="$CHECKS spm:$p"; done
CHECKS="$CHECKS macos-build macos-test ios-build doc-comment-lint protocol-doc-examples protocol-doc-refs i18n-audit py-linux-capture py-parity-acceptance py-rr-contract py-core-tools personal-widgets android-assemble android-test parity-oracle"

if (( LIST )); then for c in $CHECKS; do printf '%s\n' "$c"; done; exit 0; fi

in_list() { case ",$2," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

# Reject names that match nothing, so a typo cannot silently waive or select nothing.
validate_names() {
    local label=$1 list=$2 name known old_ifs=$IFS
    IFS=,
    for name in $list; do
        [[ -n $name ]] || continue
        known=0
        IFS=$old_ifs
        for c in $CHECKS; do
            if [[ $c == "$name" || ( $name == android && $c == android-* ) || ( $name == spm && $c == spm:* ) ]]; then known=1; fi
        done
        IFS=,
        (( known )) || { IFS=$old_ifs; die_usage "$label: unknown check '$name' (see --list)"; }
    done
    IFS=$old_ifs
}
validate_names --waive "$WAIVE"
validate_names --only "$ONLY"
if [[ -n $PACKAGES_FILTER ]]; then
    old_ifs=$IFS; IFS=,
    for p in $PACKAGES_FILTER; do
        IFS=$old_ifs
        in_list "$p" "${ALL_PACKAGES// /,}" || die_usage "--packages: unknown package '$p' (known: $ALL_PACKAGES)"
        IFS=,
    done
    IFS=$old_ifs
fi

# `android` waives/selects both Android rows; `spm` both applies to every package row.
name_matches() {
    local check=$1 list=$2
    in_list "$check" "$list" && return 0
    [[ $check == android-* ]] && in_list android "$list" && return 0
    [[ $check == spm:* ]] && in_list spm "$list" && return 0
    return 1
}
is_waived() { name_matches "$1" "$WAIVE"; }
is_selected() { [[ -z ${ONLY//,/} ]] || name_matches "$1" "$ONLY"; }

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
LOGDIR="$REPO_ROOT/build/gate/$STAMP"
mkdir -p "$LOGDIR" || { printf 'Error: cannot create %s\n' "$LOGDIR" >&2; exit 2; }
ROWS="$LOGDIR/rows.tsv"
: > "$ROWS"
rel() { printf '%s' "${1#"$REPO_ROOT"/}"; }
safe() { printf '%s' "$1" | tr ':/' '--'; }

# Row: check, result, executed, passed, failed, skipped, seconds, log, note.
add_row() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@" >> "$ROWS"; }

# A check that cannot run. Never a pass; affects the exit code unless waived.
not_run() {
    local check=$1 reason=$2
    if is_waived "$check"; then
        add_row "$check" 'NOT RUN (waived)' - - - - - - "$reason"
    else
        add_row "$check" 'NOT RUN' - - - - - - "$reason"
    fi
    printf '[gate] %-22s NOT RUN: %s\n' "$check" "$reason"
}

# Reads a check's log and prints "executed passed failed skipped" ("- - - -" when the tool reports
# no counts), and writes the names of failing tests to the given file.
parse_counts() {
    python3 - "$1" "$2" "$3" "${4:-}" <<'PY'
import json, re, subprocess, sys, xml.etree.ElementTree as ET
from pathlib import Path

kind, log_path, failures_path, extra = sys.argv[1:5]
text = Path(log_path).read_text(encoding="utf-8", errors="replace")
names, counts = [], None

def xctest_names():
    found = re.findall(r"Test [Cc]ase '(.+?)' failed", text)
    found += re.findall(r"^✘ Test (.+?) (?:failed|recorded an issue)", text, re.M)
    return found

if kind == "xctest":            # swift test: XCTest summary plus the Swift Testing line
    m = re.findall(r"Executed (\d+) tests?, with (?:(\d+) tests? skipped and )?(\d+) failures?", text)
    executed = failed = skipped = 0
    seen = False
    if m:
        seen = True
        e, s, f = m[-1]
        executed, skipped, failed = int(e), int(s or 0), int(f)
    t = re.findall(r"Test run with (\d+) tests? in \d+ suites? (passed|failed)[^\n]*", text)
    if t:
        seen = True
        n = int(t[-1][0])
        executed += n
        issues = re.findall(r"^✘ Test (.+?) failed", text, re.M)
        failed += len(set(issues))
    if seen:
        counts = (executed, executed - failed - skipped, failed, skipped)
    names = xctest_names()
elif kind == "xcresult":        # xcodebuild test: counts from the result bundle, not from the log
    try:
        out = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", extra],
                             capture_output=True, text=True, check=True).stdout
        d = json.loads(out)
        counts = (d["totalTestCount"], d["passedTests"], d["failedTests"] + d.get("expectedFailures", 0),
                  d["skippedTests"])
        names = [f'{x.get("testIdentifierString") or x.get("testName")}: {" ".join(str(x.get("failureText", "")).split())[:200]}'
                 for x in d.get("testFailures", [])]
    except Exception as exc:    # no bundle (build failed before testing): leave counts unknown
        print(f"result bundle unreadable: {exc}", file=sys.stderr)
    if not names:
        names = xctest_names()
elif kind == "unittest":        # python3 -m unittest -v
    m = re.findall(r"^Ran (\d+) tests? in", text, re.M)
    if m:
        executed = int(m[-1])
        tail = text[text.rfind("\nRan "):]
        def field(key):
            g = re.search(key + r"=(\d+)", tail)
            return int(g.group(1)) if g else 0
        failed = field("failures") + field("errors") + field("unexpected successes")
        skipped = field("skipped")
        counts = (executed, executed - failed - skipped, failed, skipped)
    names = [f"{a}: {b}" for a, b in re.findall(r"^(FAIL|ERROR): (.+)$", text, re.M)]
elif kind == "gradle":          # JUnit XML written by testFullDebugUnitTest
    executed = failed = skipped = 0
    files = list(Path(extra).glob("**/TEST-*.xml")) if extra else []
    for f in files:
        try:
            root = ET.parse(f).getroot()
        except ET.ParseError:
            continue
        executed += int(root.get("tests", 0))
        failed += int(root.get("failures", 0)) + int(root.get("errors", 0))
        skipped += int(root.get("skipped", 0))
        for case in root.iter("testcase"):
            if case.find("failure") is not None or case.find("error") is not None:
                names.append(f'{case.get("classname")}.{case.get("name")}')
    if files:
        counts = (executed, executed - failed - skipped, failed, skipped)

Path(failures_path).write_text("".join(n + "\n" for n in dict.fromkeys(names)), encoding="utf-8")
print(" ".join(str(c) for c in counts) if counts else "- - - -")
PY
}

# run_check CHECK PARSER PARSER_ARG FLOOR WORKDIR COMMAND...
#   PARSER      none | xctest | xcresult | unittest | gradle
#   FLOOR       minimum number of executed tests (0 = none); below it the check FAILS, as in CI.
# A test check whose tool exits 0 but reports no executed tests is a FAIL, never a PASS.
run_check() {
    local check=$1 parser=$2 parser_arg=$3 floor=$4 workdir=$5
    shift 5
    is_selected "$check" || { skip_unselected "$check"; return 0; }
    local log="$LOGDIR/$(safe "$check").log" failures="$LOGDIR/$(safe "$check").failures.txt"
    local start=$SECONDS status counts executed passed failed skipped result note=''
    printf '[gate] %-22s running...\n' "$check"
    {
        printf '# check: %s\n# cwd: %s\n# command:' "$check" "$(rel "$workdir")"
        printf ' %q' "$@"
        printf '\n\n'
    } > "$log"
    ( cd -- "$workdir" && "$@" ) >> "$log" 2>&1
    status=$?
    local seconds=$(( SECONDS - start ))
    : > "$failures"
    executed=-; passed=-; failed=-; skipped=-
    if [[ $parser != none ]]; then
        counts=$(parse_counts "$parser" "$log" "$failures" "$parser_arg" 2>>"$log")
        read -r executed passed failed skipped <<EOF
${counts:-- - - -}
EOF
    fi
    if (( status == 0 )); then result=PASS; else result=FAIL; note="exit $status"; fi
    if [[ $parser != none && $result == PASS ]]; then
        if [[ $executed == - || $executed == 0 ]]; then
            result=FAIL; note='tool exited 0 but reported no executed tests'
        elif (( executed < floor )); then
            result=FAIL; note="collected $executed tests, CI floor is $floor"
        elif [[ $failed != 0 ]]; then
            result=FAIL; note='tool exited 0 but reported failures'
        fi
    fi
    add_row "$check" "$result" "$executed" "$passed" "$failed" "$skipped" "$seconds" "$(rel "$log")" "$note"
    printf '[gate] %-22s %s (%ss)\n' "$check" "$result" "$seconds"
}

skip_unselected() {
    add_row "$1" 'NOT RUN' - - - - - - 'not selected by --only'
}

cd -- "$REPO_ROOT" || exit 2

# ---------------------------------------------------------------------------------------------
# xcodegen generate
# Mirrors: .github/workflows/app-build.yml, job `build`, step "Generate Xcode project".
# Deviation: CI installs XcodeGen with Homebrew first; locally it must already be installed.
if ! is_selected xcodegen; then skip_unselected xcodegen
elif ! command -v xcodegen >/dev/null 2>&1; then not_run xcodegen 'xcodegen is not installed'
else run_check xcodegen none '' 0 "$REPO_ROOT" xcodegen generate
fi

# ---------------------------------------------------------------------------------------------
# swift test per package
# Mirrors: .github/workflows/swift-packages.yml, job `test`, steps "Build <package>" (swift build)
# and "Test <package>" (swift test), working-directory Packages/<package>.
# Deviations: --scratch-path build/spm/<package> keeps build products under the ignored build/
# directory instead of Packages/<package>/.build; CI runs on macos-15, this runs on the local
# toolchain. The workflow's `tools` job (Tools/SleepBench, SleepPSG, Backfill) is not part of §G4
# and is not run here.
for pkg in $ALL_PACKAGES; do
    check="spm:$pkg"
    if ! is_selected "$check"; then skip_unselected "$check"; continue; fi
    if [[ -n $PACKAGES_FILTER ]] && ! in_list "$pkg" "$PACKAGES_FILTER"; then
        add_row "$check" 'NOT RUN (filtered)' - - - - - - 'not in --packages'
        continue
    fi
    if [[ ! -f Packages/$pkg/Package.swift ]]; then not_run "$check" "Packages/$pkg/Package.swift is missing"; continue; fi
    scratch="$REPO_ROOT/build/spm/$pkg"
    run_check "$check" xctest '' 0 "$REPO_ROOT/Packages/$pkg" \
        bash -c 'swift build --scratch-path "$1" && swift test --scratch-path "$1"' gate "$scratch"
done

# ---------------------------------------------------------------------------------------------
# macOS Strand build
# Mirrors: .github/workflows/app-build.yml, job `build`, matrix leg scheme=Strand
# (destination generic/platform=macOS, extra_args ARCHS="x86_64 arm64" ONLY_ACTIVE_ARCH=NO),
# step "Build Strand".
# Deviations: -derivedDataPath points at the one shared DerivedData tree under build/;
# CI runs this leg on macos-15.
if ! is_selected macos-build; then skip_unselected macos-build
elif ! command -v xcodebuild >/dev/null 2>&1; then not_run macos-build 'xcodebuild is not available'
else
    run_check macos-build none '' 0 "$REPO_ROOT" \
        xcodebuild -scheme Strand -configuration Debug \
        -destination 'generic/platform=macOS' 'ARCHS=x86_64 arm64' ONLY_ACTIVE_ARCH=NO \
        -derivedDataPath "$DERIVED" \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
        build
fi

# ---------------------------------------------------------------------------------------------
# macOS StrandTests
# Mirrors: .github/workflows/app-build.yml, job `build`, step "Test Strand"
# (runs only on the Strand leg; destination platform=macOS).
# Deviations: shared -derivedDataPath; -resultBundlePath so the counts in the summary come from
# the result bundle rather than from scraping the log.
if ! is_selected macos-test; then skip_unselected macos-test
elif ! command -v xcodebuild >/dev/null 2>&1; then not_run macos-test 'xcodebuild is not available'
else
    bundle="$LOGDIR/macos-test.xcresult"
    run_check macos-test xcresult "$bundle" 0 "$REPO_ROOT" \
        xcodebuild -scheme Strand -configuration Debug \
        -destination 'platform=macOS' \
        -derivedDataPath "$DERIVED" -resultBundlePath "$bundle" \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
        test
fi

# ---------------------------------------------------------------------------------------------
# NOOPiOS simulator build, including the widget extension
# Mirrors: §G4 names Tools/personal/ios.sh build as the source. That helper matches
# .github/workflows/app-build.yml, job `build`, matrix leg scheme=NOOPiOS (destination
# generic/platform=iOS Simulator, Debug, CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO).
# Deviations (the helper's, not added here): it re-runs xcodegen, passes -project,
# -onlyUsePackageVersionsFromResolvedFile and -derivedDataPath build/personal/fork-derived, and
# refuses to run without the ignored Config/BundleIdSecrets.xcconfig. CI uses macos-26.
if ! is_selected ios-build; then skip_unselected ios-build
elif [[ ! -f Config/BundleIdSecrets.xcconfig ]]; then
    not_run ios-build 'Config/BundleIdSecrets.xcconfig is missing; Tools/personal/ios.sh build refuses to run without it (see ios.sh configure)'
else
    run_check ios-build none '' 0 "$REPO_ROOT" bash Tools/personal/ios.sh build
fi

# ---------------------------------------------------------------------------------------------
# Detached doc comments, and the two protocol-document checks from the same job
# Mirrors: .github/workflows/source-hygiene.yml, job `doc-comments`, steps "Detached doc comments
# (regression gate)", "Protocol doc examples (arithmetic check)" and "Protocol doc source
# references (existence check)". §G4 lists only the first; the other two are run because they
# share the job and cost seconds.
run_check doc-comment-lint none '' 0 "$REPO_ROOT" python3 Tools/doc_comment_lint.py
run_check protocol-doc-examples none '' 0 "$REPO_ROOT" python3 docs/protocol-examples/validate_examples.py
run_check protocol-doc-refs none '' 0 "$REPO_ROOT" python3 docs/protocol-examples/check_source_references.py

# ---------------------------------------------------------------------------------------------
# i18n coverage (diff-scoped)
# Mirrors: .github/workflows/i18n-coverage.yml, job `check`, step "i18n audit (regression gate)":
# python3 Tools/i18n_audit.py --ci <base>. In CI the base is origin/<PR target branch> for a pull
# request, or the pre-push tip (else HEAD~1) for a push.
# Deviation: the base is --base, default origin/personal/iphone-baseline, the branch personal
# pull requests target (the workflow itself only triggers for `main`).
if ! is_selected i18n-audit; then skip_unselected i18n-audit
elif ! git rev-parse --verify --quiet "$BASE_REF^{commit}" >/dev/null; then
    not_run i18n-audit "base ref '$BASE_REF' does not resolve to a commit (fetch it or pass --base)"
else
    run_check i18n-audit none '' 0 "$REPO_ROOT" python3 Tools/i18n_audit.py --ci "$BASE_REF"
fi

# ---------------------------------------------------------------------------------------------
# Python unit tests under Tools/
# Mirrors: .github/workflows/tools-python.yml, job `linux-capture`, its four test steps in order,
# with the same working directories and the same minimum-collected floors (200, 49, 2, 114).
# Deviations: CI pins Python 3.12 on ubuntu; this uses the local python3 on macOS. The core step
# builds its module list with GNU `find -printf` and bash 4 `mapfile`; neither exists on stock
# macOS, so the same list (Tools/test_*.py, depth 1, sorted) is built with a glob.
# Tools/personal/test_ios.py and Tools/tests/test_parity_{arity,artefact_filter,
# disposition_kinds,harness,ledger}.py are not in that workflow and are not run here.
run_check py-linux-capture unittest '' 200 "$REPO_ROOT/Tools/linux-capture" \
    python3 -m unittest discover -p 'test_*.py' -v
run_check py-parity-acceptance unittest '' 49 "$REPO_ROOT/Tools" \
    python3 -m unittest -v tests.test_parity_governance_acceptance
run_check py-rr-contract unittest '' 2 "$REPO_ROOT/Tools" \
    python3 -m unittest -v tests.test_rr_legacy_preservation_contract
run_check py-core-tools unittest '' 114 "$REPO_ROOT/Tools" \
    bash -c 'modules=(); for f in test_*.py; do [ -f "$f" ] && modules+=("${f%.py}"); done; python3 -m unittest -v "${modules[@]}"'

# ---------------------------------------------------------------------------------------------
# Personal widget invariants
# Mirrors: no workflow; the invocation is the script's own usage line
# (python3 Tools/check_personal_widgets.py, --swiftc defaulting to the swiftc on PATH).
# The script prints an XCTest summary when it runs its cases, so the xctest parser applies.
run_check personal-widgets xctest '' 0 "$REPO_ROOT" python3 Tools/check_personal_widgets.py

# ---------------------------------------------------------------------------------------------
# Android: debug APK and JVM unit tests
# Mirrors: .github/workflows/android.yml, job `build-and-test`, steps "Build debug APK"
# (./gradlew assembleFullDebug) and "Run unit tests" (./gradlew testFullDebugUnitTest),
# working-directory android, JDK 17 (temurin).
# Deviations: CI provisions JDK 17 and the SDK on ubuntu; locally they must already exist. macOS
# ships a /usr/bin/java stub with no runtime behind it, so the JDK is probed with
# /usr/libexec/java_home -v 17 (or a JAVA_HOME that reports version 17), never with `command -v
# java`. --android-fresh adds --no-build-cache --rerun-tasks (AGENTS.md, after a branch switch).
android_reason=''
android_java=''
if [[ -n ${JAVA_HOME:-} && -x $JAVA_HOME/bin/java ]] && "$JAVA_HOME/bin/java" -version 2>&1 | grep -q 'version "17\.'; then
    android_java=$JAVA_HOME
elif [[ -x /usr/libexec/java_home ]] && android_java=$(/usr/libexec/java_home -v 17 2>/dev/null) && [[ -n $android_java ]]; then
    :
else
    android_java=''
    android_reason='no JDK 17 runtime (/usr/libexec/java_home -v 17 found none)'
fi
android_sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
if [[ -z $android_sdk && -f android/local.properties ]]; then
    android_sdk=$(sed -n 's/^sdk\.dir=//p' android/local.properties | head -n 1)
fi
if [[ -z $android_sdk || ! -d $android_sdk/platforms ]]; then
    android_reason="${android_reason:+$android_reason; }no Android SDK (ANDROID_HOME, ANDROID_SDK_ROOT and android/local.properties sdk.dir are unset or have no platforms/)"
fi
gradle_extra=''
(( ANDROID_FRESH )) && gradle_extra='--no-build-cache --rerun-tasks'
for step in assemble test; do
    check="android-$step"
    if ! is_selected "$check"; then skip_unselected "$check"; continue; fi
    if [[ -n $android_reason ]]; then not_run "$check" "$android_reason"; continue; fi
    if [[ $step == assemble ]]; then
        # shellcheck disable=SC2086
        run_check "$check" none '' 0 "$REPO_ROOT/android" \
            env JAVA_HOME="$android_java" ANDROID_HOME="$android_sdk" ./gradlew assembleFullDebug $gradle_extra
    else
        # shellcheck disable=SC2086
        run_check "$check" gradle "$REPO_ROOT/android/app/build/test-results/testFullDebugUnitTest" 0 "$REPO_ROOT/android" \
            env JAVA_HOME="$android_java" ANDROID_HOME="$android_sdk" ./gradlew testFullDebugUnitTest $gradle_extra
    fi
done

# ---------------------------------------------------------------------------------------------
# Parity oracle (Swift and Kotlin agree on generated inputs)
# Mirrors: nothing in .github/workflows/. §G4 lists its source as "Per stage": each stage supplies
# its own command through --parity-cmd. Without one the row is NOT RUN.
if ! is_selected parity-oracle; then skip_unselected parity-oracle
elif [[ -z $PARITY_CMD ]]; then not_run parity-oracle 'no --parity-cmd given for this stage'
else run_check parity-oracle none '' 0 "$REPO_ROOT" bash -c "$PARITY_CMD"
fi

# ---------------------------------------------------------------------------------------------
# Summary
SUMMARY="$LOGDIR/summary.txt"
STABLE="$LOGDIR/summary-stable.txt"
fmt_duration() { if [[ $1 == - ]]; then printf -- '-'; else printf '%dm%02ds' $(( $1 / 60 )) $(( $1 % 60 )); fi; }

{
    printf '%-22s %-18s %8s %7s %6s %7s\n' CHECK RESULT EXECUTED PASSED FAILED SKIPPED
    while IFS=$'\t' read -r check result executed passed failed skipped seconds log note; do
        printf '%-22s %-18s %8s %7s %6s %7s' "$check" "$result" "$executed" "$passed" "$failed" "$skipped"
        [[ -n $note ]] && printf '  %s' "$note"
        printf '\n'
    done < "$ROWS"
    for f in "$LOGDIR"/*.failures.txt; do
        [[ -s $f ]] || continue
        name=$(basename "$f" .failures.txt)
        printf '\nFailing tests in %s:\n' "$name"
        sort "$f" | sed 's/^/  /'
    done
} > "$STABLE"

{
    printf 'Gate summary  commit %s  branch %s  %s\n\n' \
        "$(git rev-parse --short=12 HEAD 2>/dev/null)" "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" "$STAMP"
    printf '%-22s %-18s %8s %7s %6s %7s %9s  %s\n' CHECK RESULT EXECUTED PASSED FAILED SKIPPED DURATION LOG
    while IFS=$'\t' read -r check result executed passed failed skipped seconds log note; do
        printf '%-22s %-18s %8s %7s %6s %7s %9s  %s\n' "$check" "$result" "$executed" "$passed" "$failed" "$skipped" \
            "$(fmt_duration "$seconds")" "$log"
        [[ -n $note ]] && printf '%-22s   note: %s\n' '' "$note"
    done < "$ROWS"
    if grep -q '^Failing tests in ' "$STABLE"; then printf '\n'; sed -n '/^Failing tests in /,$p' "$STABLE"; fi
    n_pass=$(awk -F'\t' '$2=="PASS"' "$ROWS" | wc -l | tr -d ' ')
    n_fail=$(awk -F'\t' '$2=="FAIL"' "$ROWS" | wc -l | tr -d ' ')
    n_notrun=$(awk -F'\t' '$2=="NOT RUN"' "$ROWS" | wc -l | tr -d ' ')
    n_excused=$(awk -F'\t' '$2=="NOT RUN (waived)" || $2=="NOT RUN (filtered)"' "$ROWS" | wc -l | tr -d ' ')
    printf '\nTotals: %s PASS, %s FAIL, %s NOT RUN, %s NOT RUN (waived or filtered)\n' "$n_pass" "$n_fail" "$n_notrun" "$n_excused"
    [[ -n ${ONLY//,/} ]] && printf 'PARTIAL RUN (--only): this is not a gate result.\n'
    printf 'Logs: %s   build/ size: %s\n' "$(rel "$LOGDIR")" "$(du -sh "$REPO_ROOT/build" 2>/dev/null | awk '{print $1}')"
} > "$SUMMARY"

printf '\n'
cat "$SUMMARY"

if [[ -n $COMPARE ]]; then
    printf '\nComparison with %s (informational; < baseline, > this run):\n' "$COMPARE"
    if [[ ! -f $COMPARE ]]; then
        printf '  cannot compare: file not found\n'
    else
        sed -n '/<!-- gate-stable:begin -->/,/<!-- gate-stable:end -->/p' "$COMPARE" \
            | sed -e '/<!-- gate-stable/d' -e '/^```/d' > "$LOGDIR/compare-baseline.txt"
        if [[ ! -s $LOGDIR/compare-baseline.txt ]]; then
            printf '  cannot compare: no gate-stable block in the file\n'
        elif diff "$LOGDIR/compare-baseline.txt" "$STABLE"; then
            printf '  identical to the recorded baseline\n'
        fi
    fi
fi

if awk -F'\t' '$2=="FAIL" || $2=="NOT RUN" { bad=1 } END { exit bad ? 0 : 1 }' "$ROWS"; then
    exit 1
fi
exit 0
