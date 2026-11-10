#!/usr/bin/env python3
"""Source scan: no app-target reader of body weight or waist bypasses the resolver.

Stage 1 specification (docs/personal/superapp/specs/stage-1.md) §8.6 item 1 and §12.4. "Current
weight" and "current waist" have one funnel, ``BodyMeasurementResolver`` fed by
``BodyMeasurementProvider``. A screen or an estimate that reads the profile value, the Apple Health
series or a Lab Book row by itself is a second readout of the same fact, and two readouts can
disagree. This scan fails on any such read outside an explicit allowlist.

The allowlist is a literal in this file. Adding a reader means editing this test, which is the point.
``test_allowlist_entries_still_match`` fails on an entry that no longer contains a scanned pattern,
so the list cannot quietly outlive the code it excuses.

What the scan cannot see is listed under LIMITS below. The behavioural half of the check is
``StrandTests/BodyMeasurementSingleSourceTests.swift``.

Run with::

    cd Tools && python3 -m unittest test_body_measurement_single_resolver -v
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

# The app targets. Packages are out of scope: nothing under Packages/ may read the profile at all.
SCAN_ROOTS = ("Strand", "StrandiOS", "StrandiOSShared", "StrandiOSWidgets")
WATCH_GLOB = "NOOPWatch*"

# Patterns that mean "this line resolves a body weight or a waist by itself".
#
# profile-weight / profile-waist: the profile value, read, bound (`$profile.weightKg`) or addressed
#   by its UserDefaults key (`"profile.weightKg"`).
# weight-series: `series(key: "weight"` and `exploreSeries(key: "weight"`, the Apple Health series
#   or the Lab Book projection. `waist` is scanned as well: a waist series read would be the same bypass.
# weight-spark: `sparkValues("weight"` and its variants.
# lab-marker-key: a Lab Book read or write addressed to the `weight` or `waist` marker. Not in the
#   specification's list; added because ruling R25 makes the union across strap ids part of the
#   funnel, and a direct `labMarkers(deviceId:markerKey:)` read would see one id only.
# apple-daily-weight: a `.weightKg` member read in a file that handles `AppleDaily` rows, whose
#   receiver is not `profile` (those are already profile-weight). See LIMITS.
LINE_PATTERNS: dict[str, re.Pattern[str]] = {
    "profile-weight": re.compile(r"\$?\bprofile\.weightKg\b"),
    "profile-waist": re.compile(r"\$?\bprofile\.waistCm\b"),
    "weight-series": re.compile(r"[sS]eries\(\s*key:\s*\"(?:weight|waist)\""),
    "weight-spark": re.compile(r"sparkValues\w*\(\s*\"(?:weight|waist)\""),
    "lab-marker-key": re.compile(r"markerKey:\s*\"(?:weight|waist)\""),
}
APPLE_DAILY_FILE = re.compile(r"\bAppleDaily\b|\bappleDailyRows\b|\bappleDaily\(")
APPLE_DAILY_WEIGHT = re.compile(r"(?<!\bprofile)\??\.weightKg\b")

ALL_PATTERNS = frozenset(LINE_PATTERNS) | {"apple-daily-weight"}
PROFILE = frozenset({"profile-weight", "profile-waist"})
APPLE_WRITE = frozenset({"apple-daily-weight"})

# File -> (the patterns it may contain, the reason). Every entry MUST still contain at least one of
# its patterns. A pattern outside an entry's set is an offence even in an allowlisted file: the
# profile editor may bind the profile value, it may not start reading the Apple Health series.
ALLOWLIST: dict[str, tuple[frozenset[str], str]] = {
    "Strand/Data/Profile.swift": (PROFILE, "the profile store: owns the two UserDefaults keys"),
    "Strand/Data/BodyMeasurementProvider.swift":
        (ALL_PATTERNS, "the funnel: fetches the candidates and is the one writer of the profile mirror"),
    "Strand/Screens/SettingsView.swift": (PROFILE, "the profile editor (body metrics rows)"),
    "Strand/Onboarding/OnboardingWizard.swift": (PROFILE, "the profile editor at first run"),
    "Strand/Data/AppleHealthImport.swift": (APPLE_WRITE, "import writer: Apple Health export to appleDaily"),
    "Strand/Data/ShortcutHealthImport.swift":
        (APPLE_WRITE, "import writer: Shortcut payload to appleDaily and the series"),
    "StrandiOS/Health/HealthKitBridge.swift":
        (APPLE_WRITE, "import writer: HealthKit to appleDaily and the series"),
}

# Files the specification names as allowed that hold no scanned pattern today (or do not exist yet
# and need not spell one), so the "still matches" rule cannot apply to them. They may contain the
# patterns listed without failing; they need not.
#   BodyMeasurementResolver.swift  the pure half of the funnel; it has no store or defaults access
#   WeighInStore.swift             the write funnel; it may name the marker keys, never the profile
#   AppleHealthView.swift          a labelled source page; it reads its series through a key list
#   AppleDemoSeeder.swift          demo data; writes through argument labels, not member reads
# `DataSourcesView.swift` (the nutrition CSV writer, also named by the specification) is absent on
# purpose: it never reads a weight, so there is nothing to allow.
ALLOWED_IF_PRESENT: dict[str, tuple[frozenset[str], str]] = {
    "Strand/Data/BodyMeasurementResolver.swift": (ALL_PATTERNS, "the pure resolver"),
    "Strand/Data/WeighInStore.swift":
        (frozenset({"lab-marker-key"}), "the write funnel for weight and waist Lab Book rows"),
    "Strand/Screens/AppleHealthView.swift":
        (frozenset({"weight-series", "weight-spark", "apple-daily-weight"}),
         "a source page that states its source"),
    "Strand/Data/AppleDemoSeeder.swift": (APPLE_WRITE, "demo data"),
}

# LIMITS. A source scan matches spellings, not meanings. It does NOT see:
#   - a profile reached through another name (`let p = profile` then `p.weightKg`);
#   - a value already fetched and then reused as "current weight" under a local name
#     (`sparks["weight"]?.last`, `dayModel.weightKg` in a file that never names AppleDaily);
#   - a Lab Book read by category rather than by marker key (the Coach roll-up, which the
#     specification allows because the line is labelled with its source);
#   - anything under Packages/ (the local-access export, which is allowed and source-labelled).
# The behavioural test covers what this cannot.

BACKUP_KEYS = ("cutScorecard.phases", "cutScorecard.rules")
NOT_BACKED_UP = ("noop.cutScorecardEnabled", "cutScorecard.reminder.enabled",
                 "cutScorecard.reminder.weekday", "cutScorecard.reminder.minuteOfDay")
SWIFT_BACKUP = "Packages/WhoopStore/Sources/WhoopStore/BackupSettings.swift"
KOTLIN_BACKUP = "android/app/src/main/java/com/noop/data/BackupSettings.kt"


def strip_comments(text: str) -> list[str]:
    """Return the file's lines with `//` and `/* */` comments blanked, string literals kept.

    A key literal such as "profile.weightKg" is code and must stay visible; prose in a comment that
    names a pattern must not count as a reader.
    """
    out: list[str] = []
    in_block = False
    for line in text.splitlines():
        kept: list[str] = []
        in_string = False
        i = 0
        while i < len(line):
            ch = line[i]
            nxt = line[i + 1] if i + 1 < len(line) else ""
            if in_block:
                if ch == "*" and nxt == "/":
                    in_block = False
                    i += 2
                    continue
                i += 1
                continue
            if in_string:
                kept.append(ch)
                if ch == "\\" and nxt:
                    kept.append(nxt)
                    i += 2
                    continue
                if ch == '"':
                    in_string = False
                i += 1
                continue
            if ch == '"':
                in_string = True
                kept.append(ch)
                i += 1
                continue
            if ch == "/" and nxt == "/":
                break
            if ch == "/" and nxt == "*":
                in_block = True
                i += 2
                continue
            kept.append(ch)
            i += 1
        out.append("".join(kept))
    return out


def swift_files() -> list[Path]:
    roots = [ROOT / name for name in SCAN_ROOTS] + sorted(ROOT.glob(WATCH_GLOB))
    files: list[Path] = []
    for root in roots:
        if root.is_dir():
            files.extend(sorted(root.rglob("*.swift")))
    return files


def occurrences(path: Path) -> list[tuple[int, str, str]]:
    """Every (line number, pattern name, code) in one file."""
    text = path.read_text(encoding="utf-8")
    lines = strip_comments(text)
    handles_apple_daily = any(APPLE_DAILY_FILE.search(line) for line in lines)
    found: list[tuple[int, str, str]] = []
    for number, line in enumerate(lines, start=1):
        for name, pattern in LINE_PATTERNS.items():
            if pattern.search(line):
                found.append((number, name, line.strip()))
        if handles_apple_daily and APPLE_DAILY_WEIGHT.search(line):
            found.append((number, "apple-daily-weight", line.strip()))
    return found


def all_occurrences() -> dict[str, list[tuple[int, str, str]]]:
    result: dict[str, list[tuple[int, str, str]]] = {}
    for path in swift_files():
        found = occurrences(path)
        if found:
            result[path.relative_to(ROOT).as_posix()] = found
    return result


class BodyMeasurementSingleResolverTests(unittest.TestCase):
    maxDiff = None

    def test_scan_roots_exist(self) -> None:
        """A renamed target must not turn the scan into a pass over nothing."""
        for name in SCAN_ROOTS:
            self.assertTrue((ROOT / name).is_dir(), f"scan root {name} is missing")
        self.assertTrue(list(ROOT.glob(WATCH_GLOB)), "no watch target matched NOOPWatch*")
        self.assertGreater(len(swift_files()), 100, "the scan found implausibly few Swift files")

    def test_no_reader_bypasses_the_resolver(self) -> None:
        allowed = {**ALLOWED_IF_PRESENT, **ALLOWLIST}
        offenders = [
            f"{file}:{number}: [{name}] {code}"
            for file, found in sorted(all_occurrences().items())
            for number, name, code in found
            if file not in allowed or name not in allowed[file][0]
        ]
        self.assertEqual(
            offenders, [],
            "These lines resolve a body weight or waist without BodyMeasurementResolver "
            "(specification §8.4, §8.6). Route each through BodyMeasurementProvider, or, for a "
            "writer or a labelled source page, add the file and the pattern to ALLOWLIST with its "
            "reason:\n" + "\n".join(offenders),
        )

    def test_allowlist_entries_still_match(self) -> None:
        found = all_occurrences()
        stale = [
            f"{file} ({reason})"
            for file, (patterns, reason) in sorted(ALLOWLIST.items())
            if not (ROOT / file).is_file()
            or not any(name in patterns for _, name, _ in found.get(file, []))
        ]
        self.assertEqual(
            stale, [],
            "These allowlisted files are missing or no longer contain a pattern they are allowed. "
            "Remove the entry, or, before the stage's implementation lands, create the file:\n"
            + "\n".join(stale),
        )
        overlap = sorted(set(ALLOWLIST) & set(ALLOWED_IF_PRESENT))
        self.assertEqual(overlap, [], "a file belongs to one list only")
        for file, (patterns, _) in {**ALLOWLIST, **ALLOWED_IF_PRESENT}.items():
            self.assertTrue(patterns <= ALL_PATTERNS, f"{file} names an unknown pattern")
            self.assertTrue(patterns, f"{file} allows nothing; remove the entry")

    def test_comment_stripping_keeps_key_literals_and_drops_prose(self) -> None:
        """The scan's own lexer: a fault here would hide or invent readers."""
        lines = strip_comments(
            'let a = d.double(forKey: "profile.weightKg") // reads profile.waistCm too\n'
            "/// profile.weightKg in a doc comment\n"
            'let url = "https://example.invalid/x" + profile.waistCm.description\n'
            "/* profile.weightKg\n   profile.waistCm */ let b = 1\n"
        )
        self.assertIn('"profile.weightKg"', lines[0])
        self.assertNotIn("waistCm", lines[0])
        self.assertEqual(lines[1].strip(), "")
        self.assertIn("profile.waistCm", lines[2])
        self.assertNotIn("profile", lines[3])
        self.assertEqual(lines[4].strip(), "let b = 1")

    def test_patterns_match_the_spellings_the_specification_lists(self) -> None:
        samples = {
            "profile-weight": ["x(profile.weightKg)", "f($profile.weightKg)", 'd.object(forKey: "profile.weightKg")',
                               "model.profile.weightKg"],
            "profile-waist": ["profile.waistCm > 0", "g($profile.waistCm)"],
            "weight-series": ['repo.series(key: "weight", source: "apple-health", days: 91)',
                              'repo.exploreSeries(key: "weight", source: "lab-book")',
                              'repo.series( key:"waist", source: "lab-book")'],
            "weight-spark": ['sparkValues("weight", source: "apple-health", window: 90)',
                             'sparkValuesExplore("weight", source: "my-whoop", window: 14)'],
            "lab-marker-key": ['store.labMarkers(deviceId: repo.deviceId, markerKey: "weight")'],
        }
        for name, lines in samples.items():
            for line in lines:
                self.assertRegex(line, LINE_PATTERNS[name], f"{name} must match: {line}")
        for line in ["profile.heightCm", "set.weightKg", 'series(key: "steps", source: "apple-health")',
                     'sparkValues("steps", source: "apple-health", window: 14)', "myprofile.weightKgX"]:
            for name, pattern in LINE_PATTERNS.items():
                self.assertNotRegex(line, pattern, f"{name} must not match: {line}")
        self.assertRegex("rows.compactMap { $0.weightKg }.max()", APPLE_DAILY_WEIGHT)
        self.assertRegex("weightTile(aLatest?.weightKg)", APPLE_DAILY_WEIGHT)
        self.assertNotRegex("UserProfile(weightKg: profile.weightKg)", APPLE_DAILY_WEIGHT)

    def test_scorecard_backup_keys_match_on_both_platforms(self) -> None:
        """Only the two keys this stage adds are compared: the two whitelists already differ by an
        unrelated key (`units.skinTempDisplay`, specification §3 C10), which is not this stage's to fix.

        Both files must spell the key as a string literal, so this comparison can read them.
        """
        swift = (ROOT / SWIFT_BACKUP).read_text(encoding="utf-8")
        kotlin = (ROOT / KOTLIN_BACKUP).read_text(encoding="utf-8")
        problems: list[str] = []
        for key in BACKUP_KEYS:
            quoted = re.escape(f'"{key}"')
            if not re.search(quoted + r":\s*\.string\b", swift):
                problems.append(f"{SWIFT_BACKUP}: whitelist lacks {key} as .string")
            if not re.search(quoted + r":\s*" + quoted, swift):
                problems.append(f"{SWIFT_BACKUP}: appleDefaultsKey lacks {key} mapped to itself")
            if not re.search(quoted + r"\s+to\s+Kind\.STRING\b", kotlin):
                problems.append(f"{KOTLIN_BACKUP}: WHITELIST lacks {key} as Kind.STRING")
        for key in NOT_BACKED_UP:
            for name, text in ((SWIFT_BACKUP, swift), (KOTLIN_BACKUP, kotlin)):
                if f'"{key}"' in "\n".join(strip_comments(text)):
                    problems.append(f"{name}: {key} must stay out of the backup")
        self.assertEqual(problems, [], "\n".join(problems))


if __name__ == "__main__":
    unittest.main()
