#!/usr/bin/env bash
# Rebuild and rerun the standalone Swift oracle of CutScorecard, and compare its standard output with
# the committed expected literal that both the Swift and the Kotlin oracle tests read.
#
#   bash Tools/personal/cut_scorecard_oracle.sh           compare; exit 1 on any difference
#   bash Tools/personal/cut_scorecard_oracle.sh --write   replace the literal with the oracle's output
#
# The oracle is the block between the ORACLE-SHARED markers of CutScorecardOracleTests.swift, compiled
# with the three sources the engine needs and nothing else: no package, no XCTest, no store. Scratch
# files stay under the ignored build/ directory.
#
# This executes Swift only. It says nothing about the Kotlin twin, which compares against the same
# literal in CutScorecardParityOracleTest and has to be run under Gradle.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)
SOURCES="$REPO_ROOT/Packages/StrandAnalytics/Sources/StrandAnalytics"
SHARED="$REPO_ROOT/Packages/StrandAnalytics/Tests/StrandAnalyticsTests/CutScorecardOracleTests.swift"
EXPECTED="$REPO_ROOT/android/app/src/test/resources/cut_scorecard_oracle.txt"
WORK="$REPO_ROOT/build/cut-scorecard-oracle"

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }

MODE=compare
case "${1:-}" in
    "") ;;
    --write) MODE=write ;;
    *) fail "unknown argument: $1 (expected nothing or --write)" ;;
esac

command -v swiftc >/dev/null 2>&1 || fail 'swiftc not found; the oracle needs a Swift toolchain.'
[[ -f "$SHARED" ]] || fail "missing $SHARED"

mkdir -p "$WORK"
{
    printf 'import Foundation\n\n'
    sed -n '/^\/\/ ORACLE-SHARED-BEGIN$/,/^\/\/ ORACLE-SHARED-END$/p' "$SHARED"
    printf '\nfor line in CutScorecardOracle.allLines() { print(line) }\n'
} > "$WORK/main.swift"
grep -q '^// ORACLE-SHARED-END$' "$WORK/main.swift" || fail "the ORACLE-SHARED markers were not found in $SHARED"

swiftc -O "$SOURCES/CutScorecard.swift" "$SOURCES/WeeklyDigest.swift" "$SOURCES/ComparisonEngine.swift" \
    "$WORK/main.swift" -o "$WORK/t"
"$WORK/t" > "$WORK/actual.txt"

LINES=$(wc -l < "$WORK/actual.txt" | tr -d ' ')
CASES=$(grep -c '|in=' "$WORK/actual.txt" || true)

if [[ $MODE == write ]]; then
    cp "$WORK/actual.txt" "$EXPECTED"
    printf 'Wrote %s lines (%s evaluate cases) to %s\n' "$LINES" "$CASES" "${EXPECTED#"$REPO_ROOT"/}"
    exit 0
fi

[[ -f "$EXPECTED" ]] || fail "missing $EXPECTED; run with --write to create it"
if ! diff -u "$EXPECTED" "$WORK/actual.txt" > "$WORK/diff.txt"; then
    head -n 40 "$WORK/diff.txt" >&2
    fail "the Swift oracle differs from ${EXPECTED#"$REPO_ROOT"/} (full diff: ${WORK#"$REPO_ROOT"/}/diff.txt)"
fi
printf 'OK Swift oracle matches %s: %s lines, %s evaluate cases. Kotlin is not executed by this script.\n' \
    "${EXPECTED#"$REPO_ROOT"/}" "$LINES" "$CASES"
