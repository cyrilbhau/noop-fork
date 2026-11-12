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
#   specification's list; added because rulings R25 and R42 make the read across every device id
#   part of the funnel (`LabBookRows`, labbook-ownership.md §6.2), and a direct
#   `labMarkers(deviceId:markerKey:)` read would see one id only. Any direct Lab Book read, whatever
#   its marker, is policed by ``test_lab_book_single_read_path.py``.
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


# ---------------------------------------------------------------------------------------------
# Ruling R41 (specification §18): one number per variable, on every surface.
#
# The scan above polices the spellings §8.6 listed. The surface audit of 11 November 2026 found
# readers and labels those spellings cannot see. Each is a pattern or a positive requirement here,
# so the bypass found once fails this file if it comes back. The behavioural half is
# ``StrandTests/OneNumberPerVariableTests.swift``, whose "API ASSUMED" block defines the members
# named below (``BodyMeasurementCorrection``, ``BodyMeasurementSourcePage``,
# ``AICoachEngine.bodyMeasurements``, ``WeighInSheetModel(weighIns:provider:…)``).
#
# weight-metric-route: a tap hard-wired to the catalogue page of the Apple Health weight series
#   (`.metric("weight")`). A current-weight readout takes its route from
#   `BodyMeasurementCorrection.route(for:policy:)`, which returns that page only with the flag off.
# lab-category-read: Lab Book rows read by category, which carries the `weight` and `waist` rows
#   past the `lab-marker-key` pattern (the Coach roll-up, listed under LIMITS above until R41).
#   Since ruling R42 the two allowed readers spell it `LabBookRows.all(` and
#   `LabBookRows.category(` (labbook-ownership.md §6.2); the per-id spelling is still matched, so a
#   new reader written either way is an occurrence.
# newest-as-latest: a page of ONE source's series calling its newest point "Latest". Scanned only in
#   the source pages; the wording comes from `BodyMeasurementSourcePage`. It constrains the labels a
#   weight or waist series can reach: the generic stat labels of a metric page (`"Latest"`,
#   `"Latest reading"`) and an interpolated `, latest \(…)` label. A string that names one metric
#   which is not a body measurement cannot be shown for a weight or a waist, so it is not a readout
#   of either; `NOT_A_BODY_SERIES` lists those strings.
R41_PATTERNS: dict[str, re.Pattern[str]] = {
    "weight-metric-route": re.compile(r"\.metric\(\s*\"(?:weight|waist)\"\s*\)"),
    "lab-category-read": re.compile(
        r"\blabMarkers\([^)]*\bcategory:|\bLabBookRows\s*\.\s*(?:all|category)\("),
    "newest-as-latest": re.compile(r"\"Latest(?: reading)?\"|, latest \\\("),
}

# Lines the newest-as-latest pattern does not constrain: string literals that name a metric which is
# not body weight or waist. Today that is the steps chart's VoiceOver summary ("Steps chart, …,
# latest … steps, …"), which predates ruling R41 and is drawn for the steps metric only.
# ``test_r41_allowlist_entries_still_match`` fails when an entry here stops matching.
NOT_A_BODY_SERIES: tuple[re.Pattern[str], ...] = (
    re.compile(r"\"Steps chart, "),
)

# The pages that list one source's body-measurement series.
SOURCE_PAGES = (
    "Strand/Screens/MetricExplorerView.swift",
    "Strand/Screens/LabBookView.swift",
    "Strand/Screens/AppleHealthView.swift",
)
# Pattern -> the files it is scanned in (None: every app-target file).
R41_SCOPE: dict[str, tuple[str, ...] | None] = {
    "weight-metric-route": None,
    "lab-category-read": None,
    "newest-as-latest": SOURCE_PAGES,
}
# File -> (the R41 patterns it may contain, the reason, a spelling the file must ALSO contain).
R41_ALLOWLIST: dict[str, tuple[frozenset[str], str, str | None]] = {
    "Strand/Screens/LabBookView.swift":
        (frozenset({"lab-category-read"}), "the Lab Book list: a labelled source page, read through LabBookRows",
         None),
    "Strand/AI/AICoach.swift":
        (frozenset({"lab-category-read"}),
         "the Coach roll-up of the OTHER markers; weight and waist come from the provider",
         "bodyMeasurements"),
}

CORRECTION_SURFACES: dict[str, tuple[str, ...]] = {
    "Strand/Liquid/LiquidTodayView.swift": ("liquidTodayWeightTile",),
    "Strand/Screens/TodayView.swift": ("classicTodayWeightTile",),
    "StrandiOS/Redesign/RedesignTodayView.swift": ("redesignTodayWeightRow",),
    "Strand/Screens/SettingsView.swift": ("settingsWeightRow", "settingsWaistRow"),
}

SOURCE_PAGE_MEMBERS: dict[str, tuple[str, ...]] = {
    "Strand/Screens/MetricExplorerView.swift": ("title", "newestLabel", "newestReadingLabel"),
    "Strand/Screens/LabBookView.swift": ("labBookAccessibilityLabel",),
    "Strand/Screens/AppleHealthView.swift": ("newestReadingLabel",),
    "Strand/Screens/CompareView.swift": ("title",),
}

# Surfaces R41 names that carry no body weight and no waist today. A weight added to one of them
# is a new readout of the current value and has to come from the provider, so it fails here first.
NO_BODY_MEASUREMENT = (
    "StrandiOSWidgets", "StrandiOSShared", "StrandiOS/Widgets",   # widgets and their shared payload
    "StrandiOS/System/NOOPAppIntents.swift",                      # Siri and Shortcuts answers
    "Strand/Data/CsvExport.swift", "Strand/Data/ShortcutHealthExport.swift",   # exports
    "Strand/Data/HydrationStore.swift",                           # the hydration goal
)
BODY_MEASUREMENT_WORD = re.compile(
    r"weightKg|waistCm|bodyMass|BodyMeasurement|estimateWeightKg|estimateWaistCm|\"(?:weight|waist)\"")


def code(file: str) -> str:
    """One file's code with comments blanked, as one string."""
    return "\n".join(strip_comments((ROOT / file).read_text(encoding="utf-8")))


def call_arguments(text: str, callee: str) -> list[str]:
    """The argument text of every `callee(` call in `text`, parentheses balanced."""
    found: list[str] = []
    for match in re.finditer(r"(?<![\w.])" + re.escape(callee) + r"\(", text):
        depth, i = 1, match.end()
        while i < len(text) and depth:
            depth += {"(": 1, ")": -1}.get(text[i], 0)
            i += 1
        found.append(text[match.end():i - 1])
    return found


def r41_matches(name: str, line: str) -> bool:
    """True when `line` is an occurrence of the R41 pattern `name`."""
    if not R41_PATTERNS[name].search(line):
        return False
    if name == "newest-as-latest" and any(other.search(line) for other in NOT_A_BODY_SERIES):
        return False
    return True


def r41_occurrences() -> list[tuple[str, int, str, str]]:
    found: list[tuple[str, int, str, str]] = []
    for path in swift_files():
        file = path.relative_to(ROOT).as_posix()
        lines = strip_comments(path.read_text(encoding="utf-8"))
        for name in R41_PATTERNS:
            scope = R41_SCOPE[name]
            if scope is not None and file not in scope:
                continue
            for number, line in enumerate(lines, start=1):
                if r41_matches(name, line):
                    found.append((file, number, name, line.strip()))
    return found


class OneNumberPerVariableScanTests(unittest.TestCase):
    maxDiff = None

    def test_r41_patterns_match_the_bypasses_the_audit_found(self) -> None:
        samples = {
            "weight-metric-route": ['sparkKey: "weight", route: .metric("weight"), opensScorecard: isWeighIn)',
                                    'path.append(TabRoute.metric( "waist" ))'],
            "lab-category-read": [
                "let rows = (try? await store.labMarkers(deviceId: repo.deviceId, category: category.rawValue)) ?? []",
                # The same two reads as labbook-ownership.md §6.2 spells them.
                "let rows = await LabBookRows.category(category.rawValue, store: store, activeDeviceId: repo.deviceId)",
                "markers = await LabBookRows.all(store: store, activeDeviceId: repo.deviceId)"],
            "newest-as-latest": ['StatGridItem("Latest", value: latestValue?.value, unit: latestValue?.unit),',
                                 'Text("Latest reading").strandOverline()',
                                 r'.accessibilityLabel("\(displayName(for: key)), latest \(latestLabel(latest, key: key))")'],
        }
        # The five metric-page sites the pattern was written for, as they read before ruling R41.
        samples["newest-as-latest"] += [
            '("Latest", heroValue),',
            'StatTile(label: "Latest", value: latestPoint.map { fmt($0.value) } ?? "—",',
            'return ([String(localized: "Latest reading"), date] + (source.map { [$0] } ?? [])).joined(separator: " · ")',
            # A body series worded like the steps summary is still an occurrence.
            r'return String(localized: "Weight chart, \(points.count) readings, latest \(latest.value) kg")',
        ]
        self.assertEqual(set(samples), set(R41_PATTERNS))
        for name, lines in samples.items():
            for line in lines:
                self.assertTrue(r41_matches(name, line), f"{name} must match: {line}")
        for line in ['route: .metric("steps")', "case .metric(let key):", ".metricDetail(key: \"weight\")",
                     'store.labMarkers(deviceId: id, markerKey: key)', 'private enum Aggregate { case latest, mean }',
                     'await LabBookRows.marker(kind.markerKey, store: store, activeDeviceId: activeDeviceId)',
                     'try await LabBookRows.stored(marker: kind.markerKey, store: store)',
                     'String(localized: "latest")', 'StatGridItem("Lowest", value: low.value)',
                     # The steps chart's VoiceOver summaries: one named metric, not a body measurement.
                     r'return String(localized: "Steps chart, \(buckets.count) daily \(noun), latest \(latest.mean) steps, \(period)")',
                     r'return String(localized: "Steps chart, \(buckets.count) weekly \(noun), latest \(latest.mean) average steps per observed day, \(period)")',
                     r'return String(localized: "Steps chart, \(buckets.count) monthly \(noun), latest \(latest.mean) average steps per observed day, \(period)")']:
            for name in R41_PATTERNS:
                self.assertFalse(r41_matches(name, line), f"{name} must not match: {line}")

    def test_no_surface_bypasses_the_resolver_or_calls_a_source_series_latest(self) -> None:
        offenders = []
        for file, number, name, line in r41_occurrences():
            allowed = R41_ALLOWLIST.get(file)
            if allowed and name in allowed[0] and (allowed[2] is None or allowed[2] in code(file)):
                continue
            offenders.append(f"{file}:{number}: [{name}] {line}")
        self.assertEqual(
            offenders, [],
            "Ruling R41, one number per variable. weight-metric-route: take the tap target from "
            "BodyMeasurementCorrection.route(for:policy:). lab-category-read: a roll-up that reads Lab "
            "Book rows by category must leave weight and waist to BodyMeasurementProvider (AICoach.swift "
            "is allowed the read only while it also names `bodyMeasurements`). newest-as-latest: word a "
            "source page through BodyMeasurementSourcePage, which keeps \"Latest\" for every metric that "
            "is not a body measurement and for the flag-off state:\n" + "\n".join(offenders))

    def test_r41_allowlist_entries_still_match(self) -> None:
        found = {(file, name) for file, _, name, _ in r41_occurrences()}
        for file, (patterns, reason, _) in R41_ALLOWLIST.items():
            self.assertTrue((ROOT / file).is_file(), f"{file} is missing ({reason})")
            self.assertTrue(patterns <= set(R41_PATTERNS), f"{file} names an unknown pattern")
            self.assertTrue(any((file, name) in found for name in patterns),
                            f"{file} no longer contains a pattern it is allowed ({reason}); remove the entry")
        for file in SOURCE_PAGES:
            self.assertTrue((ROOT / file).is_file(), f"source page {file} is missing")
        pages = "\n".join(code(file) for file in SOURCE_PAGES)
        for other in NOT_A_BODY_SERIES:
            self.assertTrue(any(other.search(line) and R41_PATTERNS["newest-as-latest"].search(line)
                                for line in pages.splitlines()),
                            f"NOT_A_BODY_SERIES entry {other.pattern} excuses no line any more; remove it")

    def test_estimates_read_the_provider_and_nothing_else(self) -> None:
        """Calories, fitness age, VO2max, Health readiness and the Test Centre prefill."""
        required = {
            "Strand/Data/IntelligenceEngine.swift": {"estimateWeightKg()": 3, "estimateWaistCm()": 2},
            "Strand/App/AppModel.swift": {"estimateWeightKg()": 1},
            "Strand/Screens/HealthView.swift": {"estimateWeightKg()": 1, "estimateWaistCm()": 2},
            "Strand/Screens/TestCentreView.swift": {"estimateWeightKg()": 1},
        }
        for file, members in required.items():
            text = code(file)
            for member, count in members.items():
                self.assertGreaterEqual(text.count("bodyMeasurements." + member), count,
                                        f"{file} must read bodyMeasurements.{member} at least {count} time(s)")
        constructions = [(path.relative_to(ROOT).as_posix(), arguments)
                         for path in swift_files()
                         for arguments in call_arguments(code(path.relative_to(ROOT).as_posix()), "UserProfile")]
        self.assertEqual(sorted(file for file, _ in constructions),
                         ["Strand/App/AppModel.swift", "Strand/Data/IntelligenceEngine.swift"],
                         "a new UserProfile construction is a new reader of the current weight: pin it here")
        for file, arguments in constructions:
            self.assertRegex(arguments, r"^\s*weightKg:\s*bodyMeasurements\.estimateWeightKg\(\)\s*,",
                             f"{file}: the estimates' UserProfile takes its weight from the provider")

    def test_today_views_take_the_weight_from_the_provider(self) -> None:
        required = {
            "Strand/Liquid/LiquidTodayView.swift": ("displayWeightSeries(days: 91)", "provider.displayWeight(from:",
                                                    "displayWeightValue("),
            "Strand/Screens/TodayView.swift": ("displayWeightSeries(days: 91, trailingDays: 90)",
                                               "bodyMeasurements.displayWeight(from:", "asOf: .latest",
                                               "displayWeightValue("),
            "StrandiOS/Redesign/RedesignTodayView.swift": ("dayModel.shownBodyWeight(provider)",
                                                           "provider.displayWeightValue(dated)"),
        }
        for file, spellings in required.items():
            text = code(file)
            for spelling in spellings:
                self.assertIn(spelling, text, f"{file} no longer reads {spelling}")

    def test_settings_scorecard_and_reminder_read_the_provider(self) -> None:
        required = {
            "Strand/Screens/SettingsView.swift": ("bodyMeasurements.current(kind, consumer: .display)",
                                                  "scorecardFlag.isEnabled"),
            "Strand/Data/CutScorecardInputBuilder.swift": ("provider.series(",),
            "Strand/Data/CutScorecardModel.swift": ("provider.series(.weight, consumer: .display)",),
            "Strand/System/WeighInReminder.swift": ("provider.series(.weight, consumer: .display)",),
        }
        for file, spellings in required.items():
            text = code(file)
            for spelling in spellings:
                self.assertIn(spelling, text, f"{file} no longer reads {spelling}")

    def test_every_current_value_surface_binds_its_correction_route(self) -> None:
        missing = []
        for file, surfaces in CORRECTION_SURFACES.items():
            text = code(file)
            if not re.search(r"BodyMeasurementCorrection\s*\.\s*route\(", text):
                missing.append(f"{file}: no BodyMeasurementCorrection.route(for:policy:) call")
            for surface in surfaces:
                if not re.search(r"\." + surface + r"\b", text):
                    missing.append(f"{file}: does not name .{surface}")
        self.assertEqual(
            missing, [],
            "Ruling R41: every place that shows the current weight or waist offers a way to correct it. "
            "Each view takes its tap target from BodyMeasurementCorrection.route(for:policy:), naming its "
            "own BodyMeasurementSurface case in the file:\n" + "\n".join(missing))

    def test_scorecard_screen_hosts_the_weigh_in_sheet_and_the_history(self) -> None:
        text = code("StrandiOS/Scorecard/ScorecardView.swift")
        self.assertRegex(text, r"\bWeighInSheet\w*\(", "the scorecard screen is a correction route: it opens the sheet")
        self.assertRegex(text, r"\bWeighInHistory\w*\(", "the scorecard screen links to the weigh-in history")

    def test_source_pages_word_themselves_through_one_helper(self) -> None:
        missing = [
            f"{file}: BodyMeasurementSourcePage.{member}("
            for file, members in SOURCE_PAGE_MEMBERS.items()
            for member in members
            if not re.search(r"BodyMeasurementSourcePage\s*\.\s*" + member + r"\(", code(file))
        ]
        self.assertEqual(
            missing, [],
            "Ruling R41: a page of one source's weight or waist series is labelled as that source and "
            "never as \"latest\" or \"current\". These pages do not take their wording from "
            "BodyMeasurementSourcePage:\n" + "\n".join(missing))

    def test_coach_context_takes_weight_and_waist_from_the_provider(self) -> None:
        coach = code("Strand/AI/AICoach.swift")
        self.assertRegex(coach, r"\bbodyMeasurements\b",
                         "AICoach.swift builds the context without the body-measurement provider")
        wired = [path.relative_to(ROOT).as_posix() for path in swift_files()
                 if re.search(r"coach\.bodyMeasurements\s*=|AICoachEngine\([^)]*bodyMeasurements:",
                              code(path.relative_to(ROOT).as_posix()))]
        self.assertTrue(wired, "no app-target file hands the shared BodyMeasurementProvider to the Coach engine "
                               "(`coach.bodyMeasurements = …`); the engine would keep its flag-off text")

    def test_weigh_in_sheet_offers_the_resolver_value(self) -> None:
        constructions = [(path.relative_to(ROOT).as_posix(), arguments)
                         for path in swift_files()
                         for arguments in call_arguments(code(path.relative_to(ROOT).as_posix()), "WeighInSheetModel")]
        self.assertTrue(constructions, "no WeighInSheetModel construction was found; the scan is broken")
        without = [f"{file}: WeighInSheetModel({' '.join(arguments.split())})"
                   for file, arguments in constructions if not re.search(r"\bprovider:", arguments)]
        self.assertEqual(without, [], "the weigh-in sheet is built without the provider, so the value it offers "
                                      "is its own newest Lab Book row and not the resolver's:\n" + "\n".join(without))
        text = code("Strand/Data/CutScorecardModel.swift")
        section = re.search(r"^final class WeighInSheetModel\b.*?(?=^(?:@MainActor\n)?(?:final class|struct|enum) )",
                            text, re.MULTILINE | re.DOTALL)
        self.assertIsNotNone(section, "WeighInSheetModel was not found in CutScorecardModel.swift")
        self.assertRegex(section.group(0), r"\.current\(",
                         "WeighInSheetModel never asks the provider for the current value")

    def test_surfaces_with_no_body_measurement_stay_without_one(self) -> None:
        files: list[Path] = []
        for name in NO_BODY_MEASUREMENT:
            target = ROOT / name
            self.assertTrue(target.exists(), f"{name} is missing; update NO_BODY_MEASUREMENT")
            files.extend(sorted(target.rglob("*.swift")) if target.is_dir() else [target])
        for root in sorted(ROOT.glob(WATCH_GLOB)):
            files.extend(sorted(root.rglob("*.swift")))
        self.assertGreater(len(files), 10, "the scan found implausibly few files")
        offenders = [
            f"{path.relative_to(ROOT).as_posix()}:{number}: {line.strip()}"
            for path in files
            for number, line in enumerate(strip_comments(path.read_text(encoding="utf-8")), start=1)
            if BODY_MEASUREMENT_WORD.search(line)
        ]
        self.assertEqual(
            offenders, [],
            "Widgets, the watch, Siri and Shortcuts answers, the exports and the hydration goal carry no "
            "body weight or waist. One added here is a new readout of the current value: take it from "
            "BodyMeasurementProvider, add a test for the surface to OneNumberPerVariableTests.swift, and "
            "then remove the file from NO_BODY_MEASUREMENT:\n" + "\n".join(offenders))


if __name__ == "__main__":
    unittest.main()
