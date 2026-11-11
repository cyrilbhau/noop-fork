# API ASSUMED BY THESE TESTS
#
# The source layout of stage 3 (docs/personal/superapp/specs/stage-3.md §5, §12.4 and §14.2):
#   Strand/Data/IntakeSettings.swift, IntakeResolver.swift, IntakeProvider.swift,
#   IntakeHealthSync.swift, IntakeQuickAddStore.swift, IntakeSupplementTick.swift,
#   IntakePresenter.swift, IntakeModel.swift; Strand/System/IntakeCutoffReminder.swift;
#   StrandiOS/Intake/IntakeView.swift, IntakeQuickAddSheet.swift, IntakeSettingsSection.swift,
#   IntakeDemo.swift; StrandiOSWidgets/PersonalProteinWidget.swift; the private view
#   `HealthIntakeRow` in StrandiOS/Redesign/RedesignHealthView.swift; the observed flag
#   `IntakeSettings.flag`; `IntakeSettings.coachVisible(`; `IntakeDemo.screen(named:)`;
#   the widget kind string "PersonalProteinWidget"; the reserved demo prefix "intake-" (ruling A4).
"""Source scan: intake has one resolver, one floor, one flag and stays where it belongs.

Stage 3 specification §12.4, plus the scans §7.6, §9.6, §10.6.1, §10.8, §10.9 and §12.9 imply.
Protein and energy for a day have one funnel, ``IntakeProvider`` (fed by ``IntakeResolver``), and
two writers, ``IntakeHealthSync`` and ``IntakeQuickAddStore``. A screen, a widget or the scorecard
that reads ``protein_g`` by itself is a second readout of the same fact, and two readouts can
disagree (stage 1 ruling R41). The protein floor has one stored home, the scorecard rules
(stage 1 ruling R45). The supplement list never leaves the phone by a widget or a notification,
and the in-app Coach reads the Journal only through the exclusion.

The allowlist is a literal in this file. Adding a reader means editing this test, which is the
point. ``test_allowlist_entries_still_match`` fails on an entry that no longer matches, so the
list cannot quietly outlive the code it excuses.

Written before the implementation exists: until the files above land, the tests that require them
fail with a message naming the missing file. What the scan cannot see is listed under LIMITS.
The behavioural half is ``StrandTests/IntakeSingleSourceTests.swift``.

Run with::

    cd Tools && python3 -m unittest test_intake_single_resolver -v
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

SCAN_ROOTS = ("Strand", "StrandiOS", "StrandiOSShared", "StrandiOSWidgets")

# "this line names an intake series key". The constants of IntakeAggregation count as the key.
KEY_PATTERN = re.compile(
    r'"(?:protein_g|calories_in|intake_read_at)"'
    r"|\bIntakeAggregation\.(?:proteinKey|energyKey|readAtKey)\b"
)

# File -> reason. Each MUST still name a key (test_allowlist_entries_still_match).
ALLOWLIST: dict[str, str] = {
    "Strand/Data/MetricCatalog.swift": "a labelled source history: Explore's nutrition-csv descriptors",
    "Strand/Screens/MetricExplorerView.swift": "a labelled source history: Explore's nutrition colours",
}
# Files the specification allows that need not spell a key (they may use the package constants
# through a local name, or not exist yet). They may contain a key; they need not.
ALLOWED_IF_PRESENT: dict[str, str] = {
    "Strand/Data/IntakeProvider.swift": "the funnel: fetches the three sources' candidates",
    "Strand/Data/IntakeHealthSync.swift": "the Path A writer",
    "Strand/Data/IntakeQuickAddStore.swift": "the Path B writer",
    "StrandiOS/Intake/IntakeDemo.swift": "the simulator seeder",
}

INTAKE_HEALTH_ID = '"noop-intake-health"'

# LIMITS. A source scan matches spellings, not meanings. It does NOT see:
#   - a key built at run time ("protein" + "_g") or held in another constant;
#   - a value already resolved and then re-derived under a local name;
#   - anything under Packages/ (the CSV importer's own key constants are the import writer).
# The behavioural tests cover what this cannot.


def strip_comments(text: str) -> list[str]:
    """Return the file's lines with `//` and `/* */` comments blanked, string literals kept."""
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


def swift_files(roots: tuple[str, ...] = SCAN_ROOTS) -> list[Path]:
    files: list[Path] = []
    for name in roots:
        root = ROOT / name
        if root.is_dir():
            files.extend(sorted(root.rglob("*.swift")))
    return files


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def code(path: Path) -> list[str]:
    return strip_comments(path.read_text(encoding="utf-8"))


def intake_files() -> list[Path]:
    return [p for p in swift_files() if p.name.startswith("Intake")]


def require(test: unittest.TestCase, relative: str) -> Path:
    path = ROOT / relative
    test.assertTrue(path.is_file(), f"{relative} does not exist yet (stage 3 §5 names it)")
    return path


def key_occurrences() -> dict[str, list[tuple[int, str]]]:
    found: dict[str, list[tuple[int, str]]] = {}
    for path in swift_files():
        for number, line in enumerate(code(path), start=1):
            if KEY_PATTERN.search(line):
                found.setdefault(rel(path), []).append((number, line.strip()))
    return found


def function_body(lines: list[str], name: str) -> range | None:
    """The line indexes of the body of `func name`, by brace depth; None when absent."""
    for start, line in enumerate(lines):
        if re.search(rf"\bfunc\s+{re.escape(name)}\b", line):
            depth = 0
            opened = False
            for index in range(start, len(lines)):
                depth += lines[index].count("{") - lines[index].count("}")
                opened = opened or "{" in lines[index]
                if opened and depth <= 0:
                    return range(start, index + 1)
            return range(start, len(lines))
    return None


def type_body(lines: list[str], kind: str, name: str) -> range | None:
    for start, line in enumerate(lines):
        if re.search(rf"\b{kind}\s+{re.escape(name)}\b", line):
            depth = 0
            opened = False
            for index in range(start, len(lines)):
                depth += lines[index].count("{") - lines[index].count("}")
                opened = opened or "{" in lines[index]
                if opened and depth <= 0:
                    return range(start, index + 1)
            return range(start, len(lines))
    return None


class IntakeSingleResolverTests(unittest.TestCase):
    maxDiff = None

    def test_scan_roots_exist(self) -> None:
        for name in SCAN_ROOTS:
            self.assertTrue((ROOT / name).is_dir(), f"scan root {name} is missing")
        self.assertGreater(len(swift_files()), 100, "the scan found implausibly few Swift files")

    def test_no_reader_bypasses_the_intake_resolver(self) -> None:
        allowed = {**ALLOWLIST, **ALLOWED_IF_PRESENT}
        offenders = [
            f"{file}:{number}: {line}"
            for file, found in sorted(key_occurrences().items())
            for number, line in found
            if file not in allowed
        ]
        self.assertEqual(
            offenders, [],
            "These lines name an intake series key outside the funnel (stage 3 §9.4, §12.4). Read "
            "IntakeProvider instead, or, for a writer or a labelled source page, add the file to "
            "ALLOWLIST with its reason:\n" + "\n".join(offenders),
        )

    def test_allowlist_entries_still_match(self) -> None:
        found = key_occurrences()
        stale = [f"{file} ({reason})" for file, reason in sorted(ALLOWLIST.items())
                 if not (ROOT / file).is_file() or file not in found]
        self.assertEqual(stale, [], "allowlisted files that no longer name a key:\n" + "\n".join(stale))
        self.assertEqual(sorted(set(ALLOWLIST) & set(ALLOWED_IF_PRESENT)), [])

    def test_the_scorecard_builder_reads_protein_through_the_provider(self) -> None:
        lines = code(ROOT / "Strand/Data/CutScorecardInputBuilder.swift")
        text = "\n".join(lines)
        self.assertFalse('"nutrition-csv"' in text, "the builder's nutritionSource constant is deleted (§9.4)")
        self.assertFalse('"protein_g"' in text, "the builder's proteinKey constant is deleted (§9.4)")
        self.assertRegex(text, r"\bintake\.proteinDays\(\)", "the builder takes the provider's protein days")
        self.assertRegex(text, r"await\s+intake\.refresh\(\)")

    def test_protein_floor_is_stored_only_in_scorecard_rules(self) -> None:
        offenders: list[str] = []
        for path in swift_files():
            if rel(path) == "Strand/Data/CutScorecardSettings.swift":
                continue
            for number, line in enumerate(code(path), start=1):
                for literal in re.findall(r'"[^"\n]*"', line):
                    if "proteinfloor" in literal.lower().replace("_", "").replace(".", ""):
                        offenders.append(f"{rel(path)}:{number}: {literal}")
        self.assertEqual(offenders, [], "a second stored protein floor (stage 1 R45, stage 3 §4.2):\n"
                         + "\n".join(offenders))

    def test_bridge_requests_dietary_types_only_behind_the_setting(self) -> None:
        lines = code(ROOT / "StrandiOS/Health/HealthKitBridge.swift")
        collect = function_body(lines, "collectIntakeSamples")
        offenders: list[str] = []
        for index, line in enumerate(lines):
            if not re.search(r"\.dietary(?:Protein|EnergyConsumed)\b", line):
                continue
            if collect is not None and index in collect:
                continue
            guard = " ".join(lines[max(0, index - 3):index + 1])
            if "healthReadEnabled" not in guard:
                offenders.append(f"{index + 1}: {line.strip()}")
            if re.search(r"\bwrite", line, re.IGNORECASE):
                offenders.append(f"{index + 1} (a write list): {line.strip()}")
        writes = type_body(lines, "var", "writeTypes") or function_body(lines, "writeTypes")
        if writes is not None:
            for index in writes:
                if re.search(r"\.dietary(?:Protein|EnergyConsumed)\b", lines[index]):
                    offenders.append(f"{index + 1} (writeTypes): {lines[index].strip()}")
        self.assertEqual(offenders, [], "dietary protein or energy outside the guarded read (§8.1):\n"
                         + "\n".join(offenders))

    def test_intake_backup_keys_are_swift_only_by_decision(self) -> None:
        swift_path = ROOT / "Packages/WhoopStore/Sources/WhoopStore/BackupSettings.swift"
        kotlin_path = ROOT / "android/app/src/main/java/com/noop/data/BackupSettings.kt"
        swift_raw = swift_path.read_text(encoding="utf-8")
        swift = "\n".join(strip_comments(swift_raw))
        kotlin = "\n".join(strip_comments(kotlin_path.read_text(encoding="utf-8")))
        comment_block = swift_raw.split("public static let whitelist", 1)[0]
        problems: list[str] = []
        for key in ("intake.targets", "intake.supplement.questions"):
            quoted = re.escape(f'"{key}"')
            if not re.search(quoted + r":\s*\.string\b", swift):
                problems.append(f"whitelist lacks {key} as .string")
            if not re.search(quoted + r":\s*" + quoted, swift):
                problems.append(f"appleDefaultsKey lacks {key} mapped to itself")
            if key not in comment_block:
                problems.append(f"the fork-only comment block above the whitelist does not name {key}")
            if f'"{key}"' in kotlin:
                problems.append(f"{key} appears in the Kotlin whitelist")
        for key in ("noop.intakeEnabled", "intake.source", "intake.zoneLog", "intake.cutoff.enabled",
                    "intake.quickAdd.presets", "intake.health.sources"):
            if f'"{key}"' in swift:
                problems.append(f"{key} must stay out of the backup")
        self.assertEqual(
            problems, [],
            "Stage 3 §9.6: the two intake keys join the iPhone backup only. Ruling R43 (no Android "
            "work) makes the Kotlin drift deliberate and visible; it is not to be fixed here.\n"
            + "\n".join(problems))

    def test_no_intake_code_names_the_apple_health_source(self) -> None:
        offenders: list[str] = []
        files = intake_files()
        self.assertTrue(files, "no Intake*.swift file exists yet (stage 3 §5)")
        for path in files:
            for number, line in enumerate(code(path), start=1):
                if '"apple-health"' in line or re.search(r"\bappleDeviceId\b|\bappleHealthSource\b", line):
                    offenders.append(f"{rel(path)}:{number}: {line.strip()}")
        for path in swift_files():
            if rel(path) == "Strand/Data/IntakeProvider.swift":
                continue
            for number, line in enumerate(code(path), start=1):
                if INTAKE_HEALTH_ID in line:
                    offenders.append(f"{rel(path)}:{number}: {line.strip()} (only IntakeProvider spells the id)")
        self.assertEqual(offenders, [], "\n".join(offenders))
        require(self, "Strand/Data/IntakeProvider.swift")
        self.assertIn(INTAKE_HEALTH_ID, "\n".join(code(ROOT / "Strand/Data/IntakeProvider.swift")))

    def test_coach_reads_journal_only_through_the_exclusion(self) -> None:
        offenders: list[str] = []
        seen = 0
        for path in swift_files(("Strand/AI",)):
            for number, line in enumerate(code(path), start=1):
                for match in re.finditer(r"journalEntries\(", line):
                    seen += 1
                    before = line[:match.start()]
                    if not re.search(r"IntakeSettings\.coachVisible\(\s*(?:await\s+)?[\w.]*$", before):
                        offenders.append(f"{rel(path)}:{number}: {line.strip()}")
        self.assertGreater(seen, 0, "the Coach's Journal read was not found; the scan would pass over nothing")
        self.assertEqual(offenders, [], "a Coach Journal read without IntakeSettings.coachVisible (§10.6.1):\n"
                         + "\n".join(offenders))

    def test_supplement_list_reaches_no_widget_or_notification(self) -> None:
        offenders: list[str] = []
        for path in swift_files(("StrandiOSWidgets", "StrandiOSShared", "Strand/System", "StrandiOS/Widgets")):
            for number, line in enumerate(code(path), start=1):
                if "supplementQuestions" in line or "intake.supplement.questions" in line:
                    offenders.append(f"{rel(path)}:{number}: {line.strip()}")
        self.assertEqual(offenders, [], "\n".join(offenders))

    def test_intake_declares_no_flag_class_and_no_day_parser(self) -> None:
        offenders: list[str] = []
        for path in swift_files():
            lines = code(path)
            for number, line in enumerate(lines, start=1):
                if re.search(r"\bclass\s+IntakeFlag\b|\bstruct\s+IntakeFlag\b", line):
                    offenders.append(f"{rel(path)}:{number}: {line.strip()}")
                if '"noop.intakeEnabled"' in line and rel(path) != "Strand/Data/IntakeSettings.swift":
                    offenders.append(f"{rel(path)}:{number}: the flag key outside IntakeSettings")
            if path.name.startswith("Intake"):
                text = "\n".join(lines)
                if "DateFormatter" in text and "yyyy-MM-dd" in text:
                    offenders.append(f"{rel(path)}: a yyyy-MM-dd DateFormatter (use CanonicalDay)")
        self.assertEqual(offenders, [], "\n".join(offenders))
        settings = require(self, "Strand/Data/IntakeSettings.swift")
        text = "\n".join(code(settings))
        self.assertRegex(text, r"ObservableDefaultsFlag\(\s*key:\s*enabledKey")

    def test_intake_declares_no_floor_rule_of_its_own(self) -> None:
        offenders: list[str] = []
        for path in swift_files():
            text = "\n".join(code(path))
            for name in ("isWholeGramFloor", "proteinFloorNeedsWholeGrams"):
                if re.search(rf"\b{name}\b", text):
                    offenders.append(f"{rel(path)}: {name}")
        for path in intake_files():
            for number, line in enumerate(code(path), start=1):
                if re.search(r"\b(?:func|var|let)\s+\w*WholeGram\w*", line):
                    offenders.append(f"{rel(path)}:{number}: declares a whole-gram rule")
                if re.search(r"100_?000", line) and "Floor" in line:
                    offenders.append(f"{rel(path)}:{number}: a floor bound of its own")
        self.assertEqual(offenders, [], "\n".join(offenders))
        text = "\n".join(code(require(self, "Strand/Data/IntakeSettings.swift")))
        self.assertIn("CutScorecardSettings.isWholeGramProteinFloor", text)
        self.assertRegex(text, r"\.parameters\b")
        self.assertFalse("cutScorecard.rules" in text, "the floor is read only through CutScorecardSettings.parameters")
        self.assertFalse("rulesKey" in text, "the floor is read only through CutScorecardSettings.parameters")

    def test_health_row_is_mounted_only_under_the_intake_flag(self) -> None:
        lines = code(ROOT / "StrandiOS/Redesign/RedesignHealthView.swift")
        row = type_body(lines, "struct", "HealthIntakeRow")
        self.assertIsNotNone(row, "HealthIntakeRow is not declared yet (§10.9)")
        assert row is not None
        offenders = [f"{i + 1}: {lines[i].strip()}" for i, line in enumerate(lines)
                     if "RedesignRoute.intake" in line or re.search(r"value:\s*\.intake\b", line)
                     if i not in row]
        self.assertEqual(offenders, [], "the intake route outside HealthIntakeRow:\n" + "\n".join(offenders))
        mounts = [i for i, line in enumerate(lines) if "HealthIntakeRow(" in line and i not in row]
        self.assertEqual(len(mounts), 1, "HealthIntakeRow( occurs once, outside its declaration")
        guard = " ".join(lines[max(0, mounts[0] - 3):mounts[0] + 1])
        self.assertRegex(guard, r"\bif\b[^\n]*\b\w*[iI]ntake\w*\.isEnabled\b",
                         "mounted inside an `if` on the observed IntakeSettings.flag")
        self.assertRegex("\n".join(lines), r"IntakeSettings\.flag")

    def test_widget_kinds_are_unchanged_and_protein_is_appended(self) -> None:
        bundle = "\n".join(code(ROOT / "StrandiOSWidgets/NOOPWidgetBundle.swift"))
        body = re.findall(r"^\s*(\w+)\(\)\s*$", bundle, re.MULTILINE)
        existing = ["NOOPWidget", "NOOPLiveActivity", "CoachBriefWidget", "HeartRateWidget", "StressWidget",
                    "LiftLiveActivity", "SyncLiveActivity", "PersonalStepsWidget", "PersonalSleepWidget"]
        self.assertEqual(body[:len(existing)], existing, "existing widgets keep their order")
        self.assertIn("PersonalProteinWidget", body[len(existing):], "the protein widget is appended (§10.8)")
        kinds = {
            "StrandiOSWidgets/NOOPWidget.swift": '"NOOPWidget"',
            "StrandiOSWidgets/CoachBriefWidget.swift": '"CoachBriefWidget"',
            "StrandiOSWidgets/HeartRateWidget.swift": '"HeartRateWidget"',
            "StrandiOSWidgets/StressWidget.swift": '"StressWidget"',
            "StrandiOSWidgets/PersonalMetricsWidgets.swift": '"PersonalStepsWidget"',
        }
        for file, kind in kinds.items():
            self.assertIn(kind, (ROOT / file).read_text(encoding="utf-8"), f"{file} keeps its kind string")
        self.assertIn('"PersonalSleepWidget"', (ROOT / "StrandiOSWidgets/PersonalMetricsWidgets.swift").read_text())
        protein = "\n".join(code(require(self, "StrandiOSWidgets/PersonalProteinWidget.swift")))
        self.assertIn('"PersonalProteinWidget"', protein)

    def test_widget_payload_has_no_energy_label_or_source_name(self) -> None:
        lines = code(ROOT / "StrandiOSShared/PersonalWidgetMetrics.swift")
        reading = type_body(lines, "struct", "PersonalIntakeReading")
        self.assertIsNotNone(reading, "PersonalIntakeReading is not declared yet (§10.8)")
        assert reading is not None
        offenders = [f"{i + 1}: {lines[i].strip()}" for i in reading
                     if re.search(r"\b(?:let|var)\s+\w*(?:[Ee]nergy|[Kk]cal|[Cc]alori|[Ll]abel|[Nn]ame|[Bb]undle|"
                                  r"[Ss]upplement)\w*", lines[i])]
        self.assertEqual(offenders, [], "the widget payload carries no calories, labels, names or supplements:\n"
                         + "\n".join(offenders))
        text = "\n".join(lines)
        self.assertNotRegex(text, r"^\s*import\s+(?!Foundation\b)\w+", "Foundation only (§10.8, C5)")

    def test_notification_text_is_fixed_and_carries_nothing(self) -> None:
        lines = code(require(self, "Strand/System/IntakeCutoffReminder.swift"))
        text = "\n".join(lines)
        self.assertIn('"Food cutoff"', text)
        self.assertIn('"Your cutoff time is now."', text)
        for line in lines:
            if re.search(r"\.(?:title|body|subtitle)\s*=", line):
                self.assertNotRegex(line, r"\\\(", f"no interpolation into the notification: {line.strip()}")
            self.assertNotIn("supplementQuestions", line)
            self.assertNotRegex(line, r"\buserInfo\s*=", "nothing rides along in the notification")

    def test_demo_answers_only_its_reserved_prefix(self) -> None:
        path = require(self, "StrandiOS/Intake/IntakeDemo.swift")
        raw = path.read_text(encoding="utf-8")
        lines = strip_comments(raw)
        first = next((line.strip() for line in lines if line.strip()), "")
        self.assertEqual(first, "#if DEBUG", "the demo is compiled into debug builds only (ruling A4, §12.9)")
        text = "\n".join(lines)
        self.assertRegex(text, r"static\s+func\s+screen\(\s*named\b")
        names = re.findall(r'case\s+((?:"[^"]*"\s*,?\s*)+):', text)
        literals = [lit for group in names for lit in re.findall(r'"([^"]*)"', group)]
        self.assertTrue(literals, "the demo answers no name")
        self.assertEqual([n for n in literals if not n.startswith("intake-")], [],
                         "every name starts with the reserved prefix intake-")
        if re.search(r"upsertMetricSeries|saveJournalAnswer|\.add\(proteinGrams|setStoreForTesting", text):
            self.assertIn("targetEnvironment(simulator)", text, "a live-store write runs in the simulator only")

    def test_hot_file_edits_are_marked(self) -> None:
        """Each shared file this stage edits carries the "// Stage 3:" marker the orchestrator merges by.

        Only files that already mention an intake symbol are checked, so a file the stage has not
        reached yet does not fail here.
        """
        hot = ["Strand/Screens/SettingsView.swift", "StrandiOS/Redesign/RedesignHealthView.swift",
               "StrandiOS/App/StrandiOSApp.swift", "StrandiOS/Scorecard/ScorecardView.swift", "Strand/AI/AICoach.swift",
               "Strand/Screens/DashboardCards.swift", "Strand/Data/TodayCardReadout.swift",
               "Strand/Data/CutScorecardInputBuilder.swift", "Strand/Data/CutScorecardModel.swift",
               "Strand/Data/CoachPacketAssembler.swift", "StrandiOS/Redesign/RedesignTodayView.swift"]
        unmarked: list[str] = []
        for file in hot:
            path = ROOT / file
            if not path.is_file():
                continue
            raw = path.read_text(encoding="utf-8")
            if re.search(r"\bIntake\w*|\.protein\b|\bintake\b", "\n".join(strip_comments(raw))) and "// Stage 3:" not in raw:
                unmarked.append(file)
        self.assertEqual(unmarked, [], "shared files edited for stage 3 without a '// Stage 3:' marker:\n"
                         + "\n".join(unmarked))

    def test_comment_stripping_keeps_key_literals_and_drops_prose(self) -> None:
        lines = strip_comments('let a = "protein_g" // protein_g in prose\n/// "calories_in" in a doc\n'
                               '/* "intake_read_at" */ let b = 1\n')
        self.assertIn('"protein_g"', lines[0])
        self.assertNotIn("prose", lines[0])
        self.assertEqual(lines[1].strip(), "")
        self.assertEqual(lines[2].strip(), "let b = 1")
        self.assertTrue(KEY_PATTERN.search('series(key: "calories_in", source: x)'))
        self.assertTrue(KEY_PATTERN.search("let k = IntakeAggregation.readAtKey"))
        self.assertFalse(KEY_PATTERN.search('"carbs_g"'))


if __name__ == "__main__":
    unittest.main()
