#!/usr/bin/env python3
"""Source scan: stage 6 spells each of its facts in one place and reaches nothing it must not.

API ASSUMED BY THESE TESTS

From docs/personal/superapp/specs/stage-6.md (§5, §8.2, §8.4, §9, §10.1, §10.9, §12.4, §14), with
RULINGS-ADDENDUM.md (A1 to A21) and stage-1.md §18 beside it:

  §5     The stage's app files, at these paths:
           Strand/Data/NiggleLogSettings.swift, NiggleLogModel.swift, NiggleLogPresenter.swift,
             CutStressModel.swift, CutStressPresenter.swift, CheckpointTimelineSettings.swift,
             TimelineSources.swift, CheckpointTimelineModel.swift, CheckpointTimelinePresenter.swift
           StrandiOS/NiggleLog/*.swift (NiggleLogView, NiggleDetailView, NiggleSheet, NiggleRulesSheet,
             PausedExerciseSheet, Stage6Demo), StrandiOS/Scorecard/CutStressView.swift,
             StrandiOS/Timeline/*.swift (CheckpointTimelineView, CheckpointSheet)
         and the pure files Packages/StrandAnalytics/Sources/StrandAnalytics/{NiggleTriage,
         CutStressTrend,CheckpointTimeline}.swift (merged).
  §8.4   ``TimelineSources.swift`` is the only stage 6 file naming ``BodyRecordStore`` or
         ``PersonalEventStore``, and it calls ``PersonalEvents.visible(``.
  §9.4   Each flag is one ``ObservableDefaultsFlag(`` static; no stage 6 file observes
         ``UserDefaults.didChangeNotification``.
  §10.1  The entry points: ``StrandiOS/Redesign/RedesignHealthView.swift`` reads
         ``NiggleLogSettings.flag`` and ``CheckpointTimelineSettings.flag``;
         ``StrandiOS/Scorecard/ScorecardView.swift`` reads ``CutStressModel.flag`` and
         ``CheckpointTimelineSettings.flag``; ``Strand/Screens/SettingsView.swift`` reads all three;
         ``StrandiOS/Redesign/RedesignRoute.swift`` has the cases ``niggleLog``, ``niggle(id:``,
         ``cutStress`` and ``checkpointTimeline``.
  §12.8, ruling A4
         ``Strand/Data/DemoScreenRegistry.swift`` reserves ``niggle-``, ``cutstress-`` and
         ``timeline-`` for stage 6; ``StrandiOS/App/StrandiOSApp.swift`` names ``Stage6Demo``.

Two deliberate readings of §12.4, reported to the orchestrator:

  * ``test_triage_is_called_only_by_the_niggle_model`` allows ``NiggleLogPresenter.swift`` beside
    ``NiggleLogModel.swift``: the app-target tests (StrandTests/Stage6TestSupport.swift) give the
    presenter the stored lists, so the presenter is where the model's one call is made. Views may
    not call it.
  * ``test_checkpoints_carry_no_target_weight`` reads "``targetWeightKg`` appears in no stage 6
    storage file" as: no stored type of those files declares it and no string literal spells it.
    ``CheckpointTimelineSettings.issue`` has to hand the stored phases' targets to
    ``CheckpointTimeline.waypointIssue`` (§9.3), which names the phase property.
  * The cut-stress allowlist adds ``SettingsView.swift`` and ``ScorecardView.swift`` for the flag
    only (``CutStressModel.flag`` / ``CutStressModel.enabledKey``): the Settings card holds the
    switch and the scorecard holds the link (§10.1).

Written before the implementation exists: until the stage's files are in the tree, the tests that
read them fail by naming the missing file. The tests that read only merged code (the pure files,
the Coach, Android, the widgets) run now.

LIMITS. A source scan matches spellings, not meanings. It cannot see a key built by concatenation
or a call reached through a wrapper. The behavioural half is the Stage 6 classes under StrandTests/.
The iPhone-only files under StrandiOS/ are not compiled by the macOS test target, so this scan is
the only automated check on the entry points, the routes and the views.

Run with::

    cd Tools && python3 -m unittest test_stage6_single_source -v
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

from test_body_measurement_single_resolver import ROOT, strip_comments, swift_files


DATA = "Strand/Data"
NIGGLE_SETTINGS = f"{DATA}/NiggleLogSettings.swift"
NIGGLE_MODEL = f"{DATA}/NiggleLogModel.swift"
NIGGLE_PRESENTER = f"{DATA}/NiggleLogPresenter.swift"
CUT_STRESS_MODEL = f"{DATA}/CutStressModel.swift"
CUT_STRESS_PRESENTER = f"{DATA}/CutStressPresenter.swift"
CHECKPOINT_SETTINGS = f"{DATA}/CheckpointTimelineSettings.swift"
SOURCES = f"{DATA}/TimelineSources.swift"
TIMELINE_MODEL = f"{DATA}/CheckpointTimelineModel.swift"
TIMELINE_PRESENTER = f"{DATA}/CheckpointTimelinePresenter.swift"
DATA_FILES = (NIGGLE_SETTINGS, NIGGLE_MODEL, NIGGLE_PRESENTER, CUT_STRESS_MODEL, CUT_STRESS_PRESENTER,
              CHECKPOINT_SETTINGS, SOURCES, TIMELINE_MODEL, TIMELINE_PRESENTER)
STORAGE_FILES = (NIGGLE_SETTINGS, CHECKPOINT_SETTINGS)

NIGGLE_VIEW_DIR = "StrandiOS/NiggleLog"
TIMELINE_VIEW_DIR = "StrandiOS/Timeline"
CUT_STRESS_VIEW = "StrandiOS/Scorecard/CutStressView.swift"
DEMO = f"{NIGGLE_VIEW_DIR}/Stage6Demo.swift"
VIEWS = (tuple(f"{NIGGLE_VIEW_DIR}/{n}.swift" for n in
               ("NiggleLogView", "NiggleDetailView", "NiggleSheet", "NiggleRulesSheet", "PausedExerciseSheet"))
         + (CUT_STRESS_VIEW,)
         + tuple(f"{TIMELINE_VIEW_DIR}/{n}.swift" for n in ("CheckpointTimelineView", "CheckpointSheet")))

PURE_DIR = "Packages/StrandAnalytics/Sources/StrandAnalytics"
PURE_FILES = tuple(f"{PURE_DIR}/{n}.swift" for n in ("NiggleTriage", "CutStressTrend", "CheckpointTimeline"))

ROUTES = "StrandiOS/Redesign/RedesignRoute.swift"
HEALTH_VIEW = "StrandiOS/Redesign/RedesignHealthView.swift"
SCORECARD_VIEW = "StrandiOS/Scorecard/ScorecardView.swift"
SETTINGS_VIEW = "Strand/Screens/SettingsView.swift"
SCORE_DETAIL = "StrandiOS/Redesign/ScoreDetailData.swift"
TYPICAL_BAND = f"{DATA}/ChargeTypicalBand.swift"
APP = "StrandiOS/App/StrandiOSApp.swift"
DEMO_REGISTRY = f"{DATA}/DemoScreenRegistry.swift"
DASHBOARD_CARDS = "Strand/Screens/DashboardCards.swift"
AI_COACH = "Strand/AI/AICoach.swift"
SWIFT_BACKUP = "Packages/WhoopStore/Sources/WhoopStore/BackupSettings.swift"
DATABASE = "Packages/WhoopStore/Sources/WhoopStore/Database.swift"

LIST_KEYS = ("niggleLog.entries", "niggleLog.rules", "niggleLog.paused", "timeline.checkpoints")
FLAG_KEYS = ("noop.niggleLogEnabled", "noop.cutStressEnabled", "noop.checkpointTimelineEnabled")
TYPE_NAMES = ("NiggleTriage", "NiggleLogSettings", "NiggleLogModel", "NiggleLogPresenter", "StoredNiggle",
              "StoredTriageRule", "StoredPausedExercise", "CutStressTrend", "CutStressModel", "CutStressPresenter",
              "CheckpointTimeline", "StoredCheckpoint", "TimelineScanSource", "TimelineEventSource", "Stage6Demo")
RESERVED_PREFIXES = ("niggle-", "cutstress-", "timeline-")


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def code(relative: str) -> str:
    """The file's code with comments blanked. Fails the calling test when the file is missing."""
    path = ROOT / relative
    if not path.is_file():
        raise AssertionError(f"{relative} does not exist")
    return "\n".join(strip_comments(path.read_text(encoding="utf-8")))


def app_files() -> list[Path]:
    """Every Swift file of the app targets (Strand, StrandiOS, StrandiOSShared, StrandiOSWidgets, watch)."""
    return [f for f in swift_files() if ".build" not in f.parts]


def stage_files() -> list[str]:
    """The stage's app files that exist, by the paths of §5 (a view directory may hold more files)."""
    found = [f for f in DATA_FILES + (CUT_STRESS_VIEW,) if (ROOT / f).is_file()]
    for directory in (NIGGLE_VIEW_DIR, TIMELINE_VIEW_DIR):
        found += sorted(rel(p) for p in (ROOT / directory).glob("*.swift")) if (ROOT / directory).is_dir() else []
    return found


def holders(pattern: re.Pattern[str], files: list[Path] | None = None) -> list[str]:
    found = []
    for path in files if files is not None else app_files():
        if pattern.search("\n".join(strip_comments(path.read_text(encoding="utf-8")))):
            found.append(rel(path))
    return sorted(found)


def key_literal(key: str) -> re.Pattern[str]:
    return re.compile(r"\"" + re.escape(key) + r"\"")


# Spelling -> (pattern, the app files that may contain it, why). Every listed file must still
# contain it once the stage is built (``test_allowlist_entries_still_match``).
SINGLE_HOMES: dict[str, tuple[re.Pattern[str], tuple[str, ...], str]] = {
    "entries-key": (key_literal("niggleLog.entries"), (NIGGLE_SETTINGS,), "the log's one store"),
    "rules-key": (key_literal("niggleLog.rules"), (NIGGLE_SETTINGS,), "the log's one store"),
    "paused-key": (key_literal("niggleLog.paused"), (NIGGLE_SETTINGS,), "the log's one store"),
    "checkpoints-key": (key_literal("timeline.checkpoints"), (CHECKPOINT_SETTINGS,), "the checkpoints' one store"),
    "niggle-flag-key": (key_literal("noop.niggleLogEnabled"), (NIGGLE_SETTINGS,), "the flag's one declaration"),
    "cut-stress-flag-key": (key_literal("noop.cutStressEnabled"), (CUT_STRESS_MODEL,), "the flag's one declaration"),
    "timeline-flag-key": (key_literal("noop.checkpointTimelineEnabled"), (CHECKPOINT_SETTINGS,),
                          "the flag's one declaration"),
    "triage": (re.compile(r"\bNiggleTriage\.evaluate\("), (NIGGLE_MODEL, NIGGLE_PRESENTER),
               "§8.1: the label and day count have one source (see the module docstring)"),
    "timeline-build": (re.compile(r"\bCheckpointTimeline\.build\("), (TIMELINE_MODEL,),
                       "§7.3: one list, built once, by the timeline model"),
    "cut-stress-weekly": (re.compile(r"\bCutStressTrend\.weekly\("), (CUT_STRESS_MODEL,),
                          "§8.1: the weekly means have one caller"),
}


class Stage6SingleSourceTests(unittest.TestCase):
    """§12.4 and the entry points of §10.1."""

    maxDiff = None

    def test_scan_sees_the_app_targets(self) -> None:
        files = {rel(p) for p in app_files()}
        self.assertGreater(len(files), 100, "the scan found implausibly few Swift files")
        for root in ("Strand/", "StrandiOS/", "StrandiOSShared/", "StrandiOSWidgets/"):
            self.assertTrue(any(f.startswith(root) for f in files), f"no Swift file under {root}")

    def test_patterns_match_the_spellings_they_name(self) -> None:
        samples = {
            "entries-key": ['static let entriesKey = "niggleLog.entries"'],
            "rules-key": ['static let rulesKey = "niggleLog.rules"'],
            "paused-key": ['static let pausedKey = "niggleLog.paused"'],
            "checkpoints-key": ['static let checkpointsKey = "timeline.checkpoints"'],
            "niggle-flag-key": ['static let enabledKey = "noop.niggleLogEnabled"'],
            "cut-stress-flag-key": ['static let enabledKey = "noop.cutStressEnabled"'],
            "timeline-flag-key": ['static let enabledKey = "noop.checkpointTimelineEnabled"'],
            "triage": ["let result = NiggleTriage.evaluate(input)"],
            "timeline-build": ["let result = CheckpointTimeline.build(input)"],
            "cut-stress-weekly": ["result = CutStressTrend.weekly(input)"],
        }
        self.assertEqual(set(samples), set(SINGLE_HOMES))
        for name, lines in samples.items():
            for line in lines:
                self.assertRegex(line, SINGLE_HOMES[name][0], f"{name} must match: {line}")
        for line in ["NiggleLogSettings.entriesKey", '"niggleLog.entriesV2"', "NiggleTriage.severity(.watch)",
                     "CheckpointTimeline.kindOrder(kind)", "CutStressTrend.self", '"timeline.checkpointsOld"']:
            for name, (pattern, _, _) in SINGLE_HOMES.items():
                self.assertNotRegex(line, pattern, f"{name} must not match: {line}")

    def _assert_single_home(self, name: str) -> None:
        pattern, allowed, reason = SINGLE_HOMES[name]
        outside = [f for f in holders(pattern) if f not in allowed]
        self.assertEqual(outside, [], f"[{name}] {reason}. Found outside {list(allowed)}:\n" + "\n".join(outside))

    # §12.4, in the specification's order

    def test_niggle_keys_are_read_only_by_their_store(self) -> None:
        """Faults: a view, a widget or the Coach spelling a stored key of its own."""
        for name in ("entries-key", "rules-key", "paused-key", "checkpoints-key", "niggle-flag-key",
                     "cut-stress-flag-key", "timeline-flag-key"):
            self._assert_single_home(name)
        backup = code(SWIFT_BACKUP)
        for key in LIST_KEYS:
            self.assertIn(f'"{key}"', backup, f"{key} joins the Swift backup whitelist (§9.5)")
        for key in FLAG_KEYS:
            self.assertNotIn(f'"{key}"', backup, f"{key} is per install and never backed up (§9.5, fault F31)")

    def test_triage_is_called_only_by_the_niggle_model(self) -> None:
        self._assert_single_home("triage")

    def test_cut_stress_is_referenced_only_by_its_own_surfaces(self) -> None:
        """Fault F21: a scorer, the Coach or a widget reading the weekly means."""
        pattern = re.compile(r"\b(CutStressTrend|CutStressModel|CutStressPresenter|CutStress(Input|Result|Week|Night|Change))\b")
        allowed = {CUT_STRESS_MODEL, CUT_STRESS_PRESENTER, CUT_STRESS_VIEW, ROUTES, DEMO}
        flag_only = {SETTINGS_VIEW, SCORECARD_VIEW}
        flag = re.compile(r"\bCutStressModel\.(flag|enabledKey)\b")
        found = holders(pattern)
        outside = [f for f in found
                   if f not in allowed and not (f in flag_only and not pattern.search(flag.sub("", code(f))))]
        self.assertEqual(outside, [], "the weekly means feed nothing (§8.2):\n" + "\n".join(outside))
        forbidden = re.compile(r"(IntelligenceEngine|Scorer|CutScorecard|AICoach|CoachPacket)[^/]*\.swift$")
        for f in found:
            self.assertFalse(forbidden.search(f) or f.startswith(("StrandiOSWidgets/", "StrandiOSShared/")),
                             f"{f} reads the cut-stress figures")

    def test_timeline_is_built_only_by_its_model(self) -> None:
        self._assert_single_home("timeline-build")
        self._assert_single_home("cut-stress-weekly")

    def test_typical_band_has_one_definition(self) -> None:
        """Fault F22: the cut-stress presenter computes its own range."""
        self.assertEqual(holders(re.compile(r"\benum\s+ChargeTypicalBand\b|\bstruct\s+ChargeTypicalBand\b")),
                         [TYPICAL_BAND])
        self.assertRegex(code(TYPICAL_BAND), r"\bstatic\s+func\s+range\(")
        self.assertEqual(holders(re.compile(r"\bBaselines\.sigma\(")), [TYPICAL_BAND],
                         "the spread is read through ChargeTypicalBand.range alone")
        self.assertIn("ChargeTypicalBand.range(", code(CUT_STRESS_PRESENTER))
        self.assertIn("ChargeTypicalBand.range(", code(SCORE_DETAIL), "Recovery detail reads the same range")
        own_band = re.compile(r"\.baseline\s*[-+]|\.spread\b|ClosedRange<Double>\(|\.\.\.\s*\(?\w*\.baseline")
        for f in stage_files():
            self.assertNotRegex(code(f), own_band, f"{f} builds a range from a baseline by other means")

    def test_stage6_defines_no_flag_observer(self) -> None:
        """Fault F42: a settings type clones the flag observer."""
        for f in stage_files():
            self.assertNotIn("UserDefaults.didChangeNotification", code(f), f)
            self.assertIsNone(re.search(r"\bclass\s+\w*Flag\b", code(f)), f"{f} declares a flag class")
        for f, static in ((NIGGLE_SETTINGS, "flag"), (CUT_STRESS_MODEL, "flag"), (CHECKPOINT_SETTINGS, "flag")):
            self.assertRegex(code(f), r"static\s+let\s+" + static + r"\s*=\s*ObservableDefaultsFlag\(key:\s*enabledKey",
                             f"{f}: one ObservableDefaultsFlag over enabledKey")

    def test_stage6_has_no_day_arithmetic_of_its_own(self) -> None:
        for f in PURE_FILES:
            text = code(f)
            for spelling in ("parseYMD(", "julianDayNumber(", "fromJulianDayNumber(", "formatYMD(", "DateFormatter",
                             "Calendar", "TimeZone", "Date(", "Date.", "mondayOfWeek("):
                self.assertNotIn(spelling, text, f"{f} spells {spelling}")
            self.assertIn("CanonicalDay.", text, f"{f} reads day keys through CanonicalDay")
        for f in [x for x in DATA_FILES if (ROOT / x).is_file()]:
            text = code(f)
            for spelling in ("parseYMD(", "julianDayNumber(", "mondayOfWeek("):
                self.assertNotIn(spelling, text, f"{f} spells {spelling}")

    def test_other_stage_stores_are_named_only_in_the_adapters(self) -> None:
        for f in stage_files():
            if f == SOURCES:
                continue
            text = code(f)
            for name in ("BodyRecordStore", "PersonalEventStore", "BodyRecordSettings"):
                self.assertNotRegex(text, r"\b" + name + r"\b", f"{f} names {name} (D20)")
        sources = code(SOURCES)
        self.assertIn("PersonalEvents.visible(", sources)
        self.assertRegex(sources, r"includeSensitive:\s*false")
        self.assertIn("BodyRecordStore", sources)
        self.assertIn("PersonalEventStore", sources)
        self.assertNotIn("takenAt", sources, "a scan day is BodyScan.day, never derived from its instant (F35)")
        self.assertNotIn(".label", sources, "a span copies kind and days only (F34)")
        self.assertNotIn(".note", sources, "a span copies kind and days only (F34)")

    def test_checkpoints_carry_no_target_weight(self) -> None:
        """Fault F39: a weight stored on a target-date checkpoint. See the module docstring."""
        for f in STORAGE_FILES:
            text = code(f)
            self.assertNotIn('"targetWeightKg"', text, f"{f} spells the key")
            self.assertIsNone(re.search(r"\b(var|let)\s+targetWeightKg\b", text), f"{f} declares a target weight")
        pure = (ROOT / f"{PURE_DIR}/CheckpointTimeline.swift").read_text(encoding="utf-8")
        owners = []
        current = None
        for line in strip_comments(pure):
            m = re.search(r"\b(?:struct|enum)\s+(\w+)", line)
            if m:
                current = m.group(1)
            if re.search(r"\b(let|var)\s+targetWeightKg\b", line):
                owners.append(current)
        self.assertEqual(sorted(set(owners)), ["TimelineItem", "TimelinePhase"], f"declared on {owners}")

    def test_scorecard_evaluation_has_one_caller_in_stage6(self) -> None:
        """Faults F27, F41: the timeline evaluates the scorecard itself."""
        for f in stage_files():
            text = code(f)
            self.assertNotIn("evaluation(today:", text, f)
            self.assertNotIn("CutScorecard.evaluate(", text, f)
            self.assertNotIn("CutScorecardInputBuilder", text, f)
        self.assertIn(".evaluation", code(TIMELINE_MODEL), "the timeline reads the shared model's stored evaluation")

    def test_stage6_adds_no_kotlin(self) -> None:
        """R43: the drift of §9.5 is a decision, not an accident."""
        tokens = LIST_KEYS + FLAG_KEYS + TYPE_NAMES
        found = []
        for path in sorted((ROOT / "android").rglob("*")):
            if path.suffix not in (".kt", ".kts", ".java", ".xml", ".json") or "build" in path.parts:
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
            found += [f"{rel(path)}: {t}" for t in tokens if t in text]
        self.assertEqual(found, [])

    # §10.1 entry points and §10.9

    def test_entry_points_are_guarded_by_their_flags(self) -> None:
        health = code(HEALTH_VIEW)
        self.assertIn("NiggleLogSettings.flag", health)
        self.assertIn("CheckpointTimelineSettings.flag", health)
        scorecard = code(SCORECARD_VIEW)
        self.assertIn("CutStressModel.flag", scorecard)
        self.assertIn("CheckpointTimelineSettings.flag", scorecard)
        settings = code(SETTINGS_VIEW)
        for flag in ("NiggleLogSettings.flag", "CutStressModel.flag", "CheckpointTimelineSettings.flag"):
            self.assertIn(flag, settings)
        routes = code(ROUTES)
        for case in (r"case\s+niggleLog\b", r"case\s+niggle\(id:", r"case\s+cutStress\b", r"case\s+checkpointTimeline\b"):
            self.assertRegex(routes, case)

    def test_settings_cards_keep_the_one_order(self) -> None:
        """Ruling A1: Niggle log, Recovery context, Timeline are the last three cards, in that order."""
        settings = code(SETTINGS_VIEW)
        positions = [settings.find(flag) for flag in ("NiggleLogSettings.flag", "CutStressModel.flag",
                                                      "CheckpointTimelineSettings.flag")]
        self.assertNotIn(-1, positions)
        self.assertEqual(positions, sorted(positions))
        for earlier in ("PersonalEventStore.flag", "BodyRecordSettings.enabledFlag"):
            index = settings.find(earlier)
            if index != -1:
                self.assertLess(index, positions[0], f"{earlier} comes before the stage 6 cards")

    def test_no_widget_notification_or_today_card(self) -> None:
        """§10.9 and D7: nothing of stage 6 reaches a widget, a notification or Today."""
        tokens = re.compile(r"\b(" + "|".join(TYPE_NAMES) + r")\b|" + "|".join(re.escape(k) for k in LIST_KEYS + FLAG_KEYS))
        outside = [rel(p) for p in app_files()
                   if rel(p).startswith(("StrandiOSWidgets/", "StrandiOSShared/", "StrandiOS/Widgets/", "NOOPWatch"))
                   and tokens.search("\n".join(strip_comments(p.read_text(encoding="utf-8"))))]
        self.assertEqual(outside, [])
        self.assertIsNone(tokens.search(code(DASHBOARD_CARDS)), "no Today card (D7)")
        for f in stage_files():
            text = code(f)
            for spelling in ("UNMutableNotificationContent", "UNNotificationRequest", "UNUserNotificationCenter",
                             "WidgetCenter", "URLSession", "UIPasteboard", "NSPasteboard", "HKHealthStore"):
                self.assertNotIn(spelling, text, f"{f} spells {spelling}")

    def test_coach_and_packet_read_no_stage6_fact(self) -> None:
        """§1, Q6: niggles, rules, pauses and checkpoints stay out of the Coach and the packet."""
        tokens = re.compile(r"\b(" + "|".join(TYPE_NAMES) + r")\b|" + "|".join(re.escape(k) for k in LIST_KEYS + FLAG_KEYS))
        coach = [p for p in app_files() if rel(p) == AI_COACH or re.search(r"/CoachPacket\w*\.swift$", rel(p))
                 or rel(p).startswith("Strand/AI/")]
        self.assertTrue(coach, "the scan finds the Coach files")
        self.assertEqual([rel(p) for p in coach if tokens.search("\n".join(strip_comments(p.read_text(encoding="utf-8"))))],
                         [])
        packet = sorted((ROOT / PURE_DIR).glob("CoachPacket*.swift"))
        self.assertEqual([rel(p) for p in packet if tokens.search(p.read_text(encoding="utf-8"))], [])

    def test_views_decide_nothing(self) -> None:
        for f in [v for v in VIEWS if (ROOT / v).is_file()] or list(VIEWS):
            text = code(f)
            for spelling in ("NiggleTriage.", "CheckpointTimeline.build(", "CutStressTrend.", "DateFormatter",
                             "ChargeTypicalBand", "String(format:"):
                self.assertNotIn(spelling, text, f"{f} decides or formats by itself: {spelling}")

    def test_demo_is_registered_with_its_reserved_prefixes(self) -> None:
        registry = code(DEMO_REGISTRY)
        for prefix in RESERVED_PREFIXES:
            self.assertIn(f'"{prefix}"', registry, f"ruling A4 reserves {prefix}")
        self.assertIn("Stage6Demo", code(APP))
        demo = code(DEMO)
        self.assertIn("#if DEBUG", (ROOT / DEMO).read_text(encoding="utf-8"))
        for name in ("BodyRecordStore", "PersonalEventStore", "CutScorecard.evaluate("):
            self.assertNotIn(name, demo, f"the demo gives the adapters closures (§12.8), not {name}")

    def test_no_migration_or_table(self) -> None:
        database = code(DATABASE)
        for word in ("niggle", "checkpoint", "triage"):
            self.assertIsNone(re.search(word, database, re.IGNORECASE), f"§9: no table for {word}")

    def test_allowlist_entries_still_match(self) -> None:
        for name, (pattern, allowed, _) in SINGLE_HOMES.items():
            if name == "triage":
                # Either file may hold the one call (see the module docstring); one of them must.
                self.assertTrue(any(pattern.search(code(f)) for f in allowed), f"[{name}] no allowlisted file matches")
                continue
            for f in allowed:
                self.assertRegex(code(f), pattern, f"[{name}] {f} is allowlisted but no longer matches")


if __name__ == "__main__":
    unittest.main()
