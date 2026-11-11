#!/usr/bin/env python3
"""Source scan: the body record spells each of its facts in one place and reaches nothing new.

API ASSUMED BY THESE TESTS

From docs/personal/superapp/specs/stage-4.md (§5.1, §9, §10, §12.5, §12.9, §12.10, §14), with
RULINGS-ADDENDUM.md (A1 to A17) beside it:

  §5.1   The stage's app files, at these paths:
           Strand/Data/BodyRecordSettings.swift, BodyScanFields.swift, BodyRecordStore.swift,
             BodyRecordModel.swift, BodyRecordPresenter.swift
           StrandiOS/BodyRecord/BodyRecordView.swift, BodyScanSheet.swift, BodyScanDetailView.swift,
             BodyScanCompareView.swift, BenchmarkDetailView.swift, BenchmarkSheet.swift,
             BodyRecordKit.swift, BodyRecordDemo.swift
  §12.5  A ``"scan_`` or ``"bench_`` string literal occurs in the app targets only in
         ``BodyScanFields.swift``. ``BodyScanDerivation.derive(`` and ``BodyRecordComparison.compare(``
         occur only in ``BodyRecordPresenter.swift``. ``"body-scan"`` is spelled nowhere outside
         ``Packages/`` (read here as: no Swift file of the app targets or of ``StrandTests``; the
         constant is ``MarkerCatalog.scanSource``). ``replaceLabMarkers(`` only in
         ``BodyRecordStore.swift``. ``withoutOutrankedScans(`` in no stage 4 file.
         ``weighInOutranksDraft(`` only in ``BodyRecordPresenter.swift`` (its definition) and
         ``BodyRecordModel.swift`` (the sheet model). ``LabBookUnion`` and ``unionedDeviceIds`` in no
         file under ``Strand/`` or ``StrandiOS/``. No stage 4 file declares a class that observes
         ``UserDefaults.didChangeNotification``.
  §9.4   ``BodyRecordSettings.swift`` declares both flags as ``ObservableDefaultsFlag(key:``; the two
         keys are spelled in that file only.
  §9.1   ``BodyRecordStore.swift`` reads through ``LabBookRows.`` and never spells the ``"weight"``
         key (the total mass is read through ``WeighInStore``'s ``readings(``).
  §4.5   ``Strand/AI/AICoach.swift`` skips ``MarkerCatalog.isScanOnlyMarker(`` and
         ``MarkerCatalog.isBenchmark(`` keys in its roll-up.
  §10    The entry points: ``StrandiOS/Redesign/RedesignHealthView.swift`` and
         ``Strand/Screens/SettingsView.swift`` read ``BodyRecordSettings.enabledFlag``; the Settings
         card also reads ``BodyRecordSettings.labReportUnitsFlag``; ``Strand/Screens/LabBookView.swift``
         passes ``BodyRecordSettings.csvScope(``; ``Strand/Screens/MarkerEditorView.swift`` binds
         ``LabMarkerEntryDraft``. Each hot-file edit carries a ``// Stage 4:`` comment.
  §12.10, ruling A4
         ``BodyRecordDemo.swift`` is DEBUG-only, answers only names with this stage's reserved
         prefixes, and runs on an in-memory store; ``Strand/Data/DemoScreenRegistry.swift`` declares
         ``DemoScreenPrefixes.bodyRecord``; ``StrandiOS/App/StrandiOSApp.swift`` has one element for it.
  §1, §10, §16
         No widget, notification, network path, Health access or pasteboard; the views format and
         decide nothing and use design tokens only; no migration.

Written before the implementation exists: until the stage's files are in the tree, the tests that
read them fail by naming the missing file.

LIMITS. A source scan matches spellings, not meanings. It cannot see a key built by concatenation,
a call reached through a wrapper, or a view that formats through a helper declared elsewhere. The
behavioural half is the ``BodyRecord*Tests`` classes under StrandTests/. The iPhone-only files under
StrandiOS/BodyRecord are not compiled by the macOS test target, so this scan is the only automated
check on them.

Run with::

    cd Tools && python3 -m unittest test_body_record_single_source -v
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

from test_body_measurement_single_resolver import ROOT, strip_comments, swift_files


SETTINGS = "Strand/Data/BodyRecordSettings.swift"
FIELDS = "Strand/Data/BodyScanFields.swift"
STORE = "Strand/Data/BodyRecordStore.swift"
MODEL = "Strand/Data/BodyRecordModel.swift"
PRESENTER = "Strand/Data/BodyRecordPresenter.swift"
VIEW_DIR = "StrandiOS/BodyRecord"
VIEWS = tuple(f"{VIEW_DIR}/{name}.swift" for name in (
    "BodyRecordView", "BodyScanSheet", "BodyScanDetailView", "BodyScanCompareView", "BenchmarkDetailView",
    "BenchmarkSheet", "BodyRecordKit"))
DEMO = f"{VIEW_DIR}/BodyRecordDemo.swift"
STAGE_FILES = (SETTINGS, FIELDS, STORE, MODEL, PRESENTER) + VIEWS + (DEMO,)

AI_COACH = "Strand/AI/AICoach.swift"
HEALTH_VIEW = "StrandiOS/Redesign/RedesignHealthView.swift"
SETTINGS_VIEW = "Strand/Screens/SettingsView.swift"
LAB_BOOK_VIEW = "Strand/Screens/LabBookView.swift"
MARKER_EDITOR = "Strand/Screens/MarkerEditorView.swift"
SCORECARD_PRESENTER = "Strand/Data/CutScorecardPresenter.swift"
APP = "StrandiOS/App/StrandiOSApp.swift"
DEMO_REGISTRY = "Strand/Data/DemoScreenRegistry.swift"
DATABASE = "Packages/WhoopStore/Sources/WhoopStore/Database.swift"

RESERVED_PREFIXES = ("bodyrecord-", "scan-", "compare-", "bench-", "labunits-")

# Spelling -> (the files that may contain it, why). Every listed file MUST still contain it, so a
# stale entry fails (``test_allowlist_entries_still_match``).
SINGLE_HOMES: dict[str, tuple[re.Pattern[str], tuple[str, ...], str]] = {
    "scan-or-bench-literal": (re.compile(r"\"(scan|bench)_"), (FIELDS,),
                              "the field table is the one app file that names the catalogue's scan and benchmark keys"),
    "derive": (re.compile(r"\bBodyScanDerivation\.derive\("), (PRESENTER,),
               "derived figures are computed once, in the presenter"),
    "compare": (re.compile(r"\bBodyRecordComparison\.compare\("), (PRESENTER,),
                "the comparison is computed once, in the presenter"),
    "replace": (re.compile(r"\breplaceLabMarkers\("), (STORE,), "the one multi-row writer"),
    "weigh-in-line": (re.compile(r"\bweighInOutranksDraft\("), (PRESENTER, MODEL),
                      "its definition and the sheet model, its one caller"),
    "body-record-key": (re.compile(r"\"noop\.bodyRecordEnabled\""), (SETTINGS,), "the flag's one declaration"),
    "lab-units-key": (re.compile(r"\"noop\.labReportUnitsEnabled\""), (SETTINGS,), "the flag's one declaration"),
}


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def code(relative: str) -> str:
    """The file's code with comments blanked. Fails the calling test when the file is missing."""
    path = ROOT / relative
    if not path.is_file():
        raise AssertionError(f"{relative} does not exist")
    return "\n".join(strip_comments(path.read_text(encoding="utf-8")))


def raw(relative: str) -> str:
    path = ROOT / relative
    if not path.is_file():
        raise AssertionError(f"{relative} does not exist")
    return path.read_text(encoding="utf-8")


def app_files() -> list[Path]:
    """Every Swift file of the app targets (Strand, StrandiOS, StrandiOSShared, StrandiOSWidgets, watch)."""
    return [f for f in swift_files() if ".build" not in f.parts]


def holders(pattern: re.Pattern[str], files: list[Path] | None = None) -> list[str]:
    found = []
    for path in files if files is not None else app_files():
        if pattern.search("\n".join(strip_comments(path.read_text(encoding="utf-8")))):
            found.append(rel(path))
    return sorted(found)


class SingleSourceTests(unittest.TestCase):
    """§12.5."""

    maxDiff = None

    def test_scan_sees_the_app_targets(self) -> None:
        files = {rel(p) for p in app_files()}
        self.assertGreater(len(files), 100, "the scan found implausibly few Swift files")
        for root in ("Strand/", "StrandiOS/", "StrandiOSShared/", "StrandiOSWidgets/"):
            self.assertTrue(any(f.startswith(root) for f in files), f"no Swift file under {root}")

    def test_patterns_match_the_spellings_they_name(self) -> None:
        samples = {
            "scan-or-bench-literal": ['let key = "scan_fat_mass"', 'case "bench_plank_s":'],
            "derive": ["let derived = BodyScanDerivation.derive(components)"],
            "compare": ["BodyRecordComparison.compare(earlier: a, later: b)"],
            "replace": ["try await store.replaceLabMarkers(deleteIds: ids, upsert: rows)"],
            "weigh-in-line": ["BodyRecordPresenter.weighInOutranksDraft(draftRow: row, weighInRows: rows, today: day)"],
            "body-record-key": ['static let enabledKey = "noop.bodyRecordEnabled"'],
            "lab-units-key": ['static let labReportUnitsKey = "noop.labReportUnitsEnabled"'],
        }
        self.assertEqual(set(samples), set(SINGLE_HOMES))
        for name, lines in samples.items():
            for line in lines:
                self.assertRegex(line, SINGLE_HOMES[name][0], f"{name} must match: {line}")
        for line in ['let key = MarkerCatalog.scanNoteKey', 'Text("Scan note")', "scanFatMass", '"scanned"',
                     "BodyScanDerivation.self", "replaceLabMarker(", 'Text("Bench press")']:
            for name, (pattern, _, _) in SINGLE_HOMES.items():
                self.assertNotRegex(line, pattern, f"{name} must not match: {line}")

    def _assert_single_home(self, name: str) -> None:
        pattern, allowed, reason = SINGLE_HOMES[name]
        outside = [f for f in holders(pattern) if f not in allowed]
        self.assertEqual(outside, [], f"[{name}] {reason}. Found outside {list(allowed)}:\n" + "\n".join(outside))

    def test_scan_keys_are_spelled_in_one_app_file(self) -> None:
        """Faults: a view or the store spelling a catalogue key of its own."""
        self._assert_single_home("scan-or-bench-literal")

    def test_derive_and_compare_have_one_caller(self) -> None:
        """Fault F30: a view calls BodyScanDerivation.derive itself."""
        self._assert_single_home("derive")
        self._assert_single_home("compare")

    def test_scan_source_literal_is_not_respelled(self) -> None:
        files = app_files() + sorted((ROOT / "StrandTests").rglob("*.swift"))
        found = holders(re.compile(r"\"body-scan\""), files)
        self.assertEqual(found, [], "name the scan source through MarkerCatalog.scanSource:\n" + "\n".join(found))

    def test_replace_lab_markers_has_one_app_caller(self) -> None:
        self._assert_single_home("replace")

    def test_stage_4_does_not_call_the_outranking_function(self) -> None:
        """Ruling A3: the rule is stage 1's; who may call it is stage 1's to assert (R44)."""
        stage = [p for p in app_files() if re.match(r"Strand/Data/(BodyRecord\w*|BodyScanFields)\.swift$", rel(p))
                 or rel(p).startswith(VIEW_DIR + "/")]
        self.assertEqual(holders(re.compile(r"\bwithoutOutrankedScans\("), stage), [])

    def test_weigh_in_line_has_one_caller(self) -> None:
        """Faults F45, F46: the sheet asks the resolver through one presenter function."""
        self._assert_single_home("weigh-in-line")

    def test_no_union_code_in_stage_4(self) -> None:
        files = [p for p in app_files() if rel(p).startswith(("Strand/", "StrandiOS/"))]
        self.assertEqual(holders(re.compile(r"\bLabBookUnion\b|\bunionedDeviceIds\b"), files), [])

    def test_no_flag_class_is_cloned(self) -> None:
        """Fault F43."""
        offenders = []
        for path in app_files():
            name = rel(path)
            if not (re.match(r"Strand/Data/BodyRecord\w*\.swift$", name) or name.startswith(VIEW_DIR + "/")):
                continue
            text = "\n".join(strip_comments(path.read_text(encoding="utf-8")))
            if re.search(r"\bclass\s+\w+", text) and "didChangeNotification" in text:
                offenders.append(name)
            if re.search(r"\b(class|struct|enum)\s+BodyRecordFlags?\b", text):
                offenders.append(name + " (declares BodyRecordFlag)")
        self.assertEqual(offenders, [], "use the shared ObservableDefaultsFlag")
        settings = code(SETTINGS)
        self.assertEqual(len(re.findall(r"ObservableDefaultsFlag\(\s*key:", settings)), 2, "two flags, one class")
        self.assertIn("enabledFlag", settings)
        self.assertIn("labReportUnitsFlag", settings)

    def test_flag_keys_are_spelled_in_one_file(self) -> None:
        self._assert_single_home("body-record-key")
        self._assert_single_home("lab-units-key")

    def test_allowlist_entries_still_match(self) -> None:
        """A stale entry fails: every allowed file exists and still contains its spelling."""
        stale = []
        for name, (pattern, allowed, reason) in sorted(SINGLE_HOMES.items()):
            for file in allowed:
                if not (ROOT / file).is_file():
                    stale.append(f"[{name}] {file}: missing ({reason})")
                elif not pattern.search(code(file)):
                    stale.append(f"[{name}] {file}: no longer contains it ({reason})")
        self.assertEqual(stale, [], "\n".join(stale))


class FunnelTests(unittest.TestCase):
    """§9.1, §4.5: the store reads through the one path; the Coach skips the new markers."""

    def test_the_store_reads_through_lab_book_rows_and_never_names_the_weight_key(self) -> None:
        text = code(STORE)
        self.assertIn("LabBookRows.", text)
        self.assertIn("readings(", text, "the total mass is read through the weigh-in store")
        self.assertNotIn('"weight"', text, "the key comes from BodyMeasurementKind.weight.markerKey")
        for banned in ("labMarkers(deviceId:", "allLabMarkers(", "markerKeysPresent(", "upsertLabMarkers("):
            self.assertNotIn(banned, text, f"{STORE} must not call {banned}")
        self.assertIn("MarkerCatalog.scanSource", text)

    def test_the_coach_skips_scan_and_benchmark_markers(self) -> None:
        text = code(AI_COACH)
        self.assertIn("isScanOnlyMarker(", text)
        self.assertIn("isBenchmark(", text)
        self.assertNotIn("BodyRecordStore", text, "the Coach is told nothing new by this stage")


class EntryPointTests(unittest.TestCase):
    """§10.1, §10.6, §10.8, ruling A1: every surface exists only behind its own flag."""

    def test_the_health_row_and_the_settings_card_read_the_flags(self) -> None:
        self.assertIn("BodyRecordSettings.enabledFlag", code(HEALTH_VIEW))
        settings = code(SETTINGS_VIEW)
        self.assertIn("BodyRecordSettings.enabledFlag", settings)
        self.assertIn("BodyRecordSettings.labReportUnitsFlag", settings)
        self.assertLess(settings.find("labReportUnitsFlag"), settings.find("BodyRecordSettings.enabledFlag"),
                        "§10.8: \"Report units in Lab Book\" first, then \"Body record\"")

    def test_the_lab_book_import_and_editor_follow_the_flags(self) -> None:
        self.assertIn("BodyRecordSettings.csvScope(", code(LAB_BOOK_VIEW))
        self.assertIn("LabMarkerEntryDraft", code(MARKER_EDITOR))

    def test_every_hot_file_edit_is_marked(self) -> None:
        for path in (HEALTH_VIEW, SETTINGS_VIEW, APP, SCORECARD_PRESENTER, AI_COACH):
            self.assertIn("// Stage 4:", raw(path), f"{path}: mark the stage 4 edit for the merge")


class LocalOnlyTests(unittest.TestCase):
    """§1, §10, §12.9, §16: nothing of the body record leaves the app or reaches a new surface."""

    def test_no_stage_file_reaches_a_widget_notification_network_health_or_pasteboard(self) -> None:
        for path in STAGE_FILES:
            text = code(path)
            for banned in ("URLSession", "URLRequest", "http://", "https://", "NWConnection", "WidgetCenter",
                           "UNUserNotificationCenter", "UNMutableNotificationContent", "HKHealthStore",
                           "UIPasteboard", "FileManager", ".write(to:", "suiteName:", "AppGroup"):
                self.assertNotIn(banned, text, f"{path} must not contain {banned}")

    def test_no_widget_watch_or_today_card_carries_the_body_record(self) -> None:
        offenders = []
        for path in app_files():
            name = rel(path)
            if not name.startswith(("StrandiOSWidgets/", "StrandiOSShared/", "NOOPWatch", "Strand/Liquid/")) \
                    and name not in ("Strand/Screens/TodayView.swift", "Strand/Screens/DashboardCards.swift",
                                     "Strand/Data/TodayCardReadout.swift"):
                continue
            text = "\n".join(strip_comments(path.read_text(encoding="utf-8")))
            if re.search(r"\b(BodyRecord|BodyScan|Benchmark)\w*", text):
                offenders.append(name)
        self.assertEqual(offenders, [], "stage 4 adds no Today card, widget or notification (§1)")

    def test_no_migration(self) -> None:
        text = code(DATABASE)
        self.assertIn('"v47-rr-whoop5-fill"', text)
        self.assertIsNone(re.search(r'registerMigration\("v4[89]', text), "stage 4 needs no migration (§16)")


class ViewTests(unittest.TestCase):
    """§10: the views format and decide nothing, and draw with design tokens only."""

    def test_the_views_format_and_compute_nothing(self) -> None:
        for path in VIEWS:
            text = code(path)
            for banned in ("String(format:", "LabBookFormat.", "NumberFormatter", "MarkerUnitTable.",
                           "BodyRecordMath.", "BodyScanChecks.", "UnitFormatter.", "BodyMeasurementResolver."):
                self.assertNotIn(banned, text, f"{path} must not call {banned}: the presenter decides")

    def test_the_views_use_design_tokens_only(self) -> None:
        for path in VIEWS:
            text = code(path)
            for pattern in (r"\bColor\(\s*(red|\.sRGB|hue|white)", r"\.font\(\s*\.system\(", r"\bFont\.system\(",
                            r"\bColor\.(red|green|orange|yellow|blue)\b", r"#[0-9A-Fa-f]{6}\b"):
                self.assertIsNone(re.search(pattern, text), f"{path}: {pattern} (use StrandPalette / StrandFont)")


class DebugDemoTests(unittest.TestCase):
    """§12.10, ruling A4: one registry element owning the stage's reserved prefixes."""

    def test_the_demo_is_debug_only_and_answers_only_its_own_prefixes(self) -> None:
        source = raw(DEMO)
        self.assertTrue(source.lstrip().startswith(("#if DEBUG", "//")) and "#if DEBUG" in source,
                        "the whole demo file is inside #if DEBUG")
        text = code(DEMO)
        self.assertRegex(text, r"static\s+func\s+screen\(\s*named\s+\w+\s*:\s*String\s*\)\s*->\s*AnyView\?")
        names = re.findall(r'case\s+"([^"]+)"', text)
        self.assertTrue(names, "the demo names its frames in a switch")
        self.assertEqual([n for n in names if not n.startswith(RESERVED_PREFIXES)], [],
                         "every demo name of this stage uses a reserved prefix")
        self.assertEqual([n for n in names if n != n.lower()], [], "demo names are lower case")
        for expected in ("bodyrecord-g1", "bodyrecord-g5b", "scan-h8", "scan-i5b", "compare-j10b", "bench-k5",
                         "labunits-l7", "bodyrecord-history-on", "bodyrecord-history-off"):
            self.assertIn(expected, names)
        self.assertIn("inMemory(", text, "the demo runs on an in-memory store (§12.9)")

    def test_the_registry_has_one_element_for_the_body_record(self) -> None:
        registry = code(DEMO_REGISTRY)
        self.assertRegex(registry, r'static\s+let\s+bodyRecord\s*=\s*\[\s*"bodyrecord-"\s*,\s*"scan-"\s*,\s*'
                                   r'"compare-"\s*,\s*"bench-"\s*,\s*"labunits-"\s*\]')
        app = code(APP)
        self.assertEqual(app.count("BodyRecordDemo.screen(named:)"), 1)
        self.assertIn("DemoScreenPrefixes.bodyRecord", app)


if __name__ == "__main__":
    unittest.main()
