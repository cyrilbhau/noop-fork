#!/usr/bin/env python3
"""Source scan: personal events have one store, one reader per surface, and leave the app nowhere.

API ASSUMED BY THESE TESTS

From docs/personal/superapp/specs/stage-5.md (§4.3, §5, §9, §10, §12.5, §14) with
RULINGS-ADDENDUM.md beside it:

  §5     The files of the stage, at these paths:
           Packages/StrandAnalytics/Sources/StrandAnalytics/PersonalEvents.swift, PersonalEventsPacket.swift
           Strand/Data/PersonalEventStore.swift, PersonalEventPresenter.swift, PersonalEventsModel.swift,
             PersonalEventChartSource.swift
           Strand/Screens/PersonalEventChartCaption.swift
           StrandiOS/Events/PersonalEventsView.swift, PersonalEventSheet.swift, ScorecardEventNoteView.swift,
             PersonalEventsDemo.swift
  §9.3   ``PersonalEventStore.swift`` declares ``static let flag = ObservableDefaultsFlag(key:`` over
         ``PersonalEventStore.enabledKey``; no type named ``PersonalEventsFlag`` exists.
  §9.4   ``BackupSettings.swift`` carries ``"personalEvents.items"`` in the whitelist and the storage map,
         and never ``noop.personalEventsEnabled``.
  §10.1  ``RedesignHealthView.swift`` shows the row only behind ``PersonalEventStore.flag`` and routes
         to ``RedesignRoute.personalEvents``; ``SettingsView.swift`` switches the flag through
         ``PersonalEventStore.flag.set(``.
  §10.5  The adopting chart sites call ``PersonalEventChartSource`` and pass ``axisMarks:``; ``TrendChart``
         is not adopted; intraday charts never take marks.
  §10.6  ``ScorecardView.swift`` calls ``ScorecardEventNoteView(``; ``CutScorecardModel.swift`` reads the
         store's ``.events`` into the presentation context.
  §14.1  ``PersonalEventsDemo.swift`` answers only names beginning ``events-``, inside ``#if DEBUG``; the
         app's registry has one element for it, ``DemoScreenPrefixes.events``.

Specification §12.5 (every named scan), §12.4 (nothing at launch with the flag off) and faults F14,
F16, F17, F27 and F29. Written before the implementation exists: until the stage's files are in the
tree, the tests that read them fail by naming the missing file.

Stage 3's ``Strand/System/IntakeCutoffReminder.swift`` is the eighth notification producer (§12.5,
X16). It is listed, and ``test_allowlists_still_match`` tolerates its absence only while stage 3 has
not merged into this branch, saying so in its skip message; once the file exists it is checked like
the other seven.

LIMITS. A source scan matches spellings, not meanings. The behavioural half is in StrandTests/
(``PersonalEventPrivacyTests``, ``PersonalEventStoreTests``, ``PersonalEventChartSourceTests``,
``CutScorecardEventNoteTests``). The iPhone-only views are not compiled by the macOS test target, so
this scan is the only automated check on them.

Run with::

    cd Tools && python3 -m unittest test_personal_events_boundaries -v
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

from test_body_measurement_single_resolver import ROOT, strip_comments


ANALYTICS = "Packages/StrandAnalytics/Sources/StrandAnalytics"
PURE = f"{ANALYTICS}/PersonalEvents.swift"
PACKET = f"{ANALYTICS}/PersonalEventsPacket.swift"
STORE = "Strand/Data/PersonalEventStore.swift"
PRESENTER = "Strand/Data/PersonalEventPresenter.swift"
MODELS = "Strand/Data/PersonalEventsModel.swift"
CHART_SOURCE = "Strand/Data/PersonalEventChartSource.swift"
CAPTION_VIEW = "Strand/Screens/PersonalEventChartCaption.swift"
EVENTS_VIEW = "StrandiOS/Events/PersonalEventsView.swift"
SHEET_VIEW = "StrandiOS/Events/PersonalEventSheet.swift"
NOTE_VIEW = "StrandiOS/Events/ScorecardEventNoteView.swift"
DEMO = "StrandiOS/Events/PersonalEventsDemo.swift"
BACKUP = "Packages/WhoopStore/Sources/WhoopStore/BackupSettings.swift"
SCORECARD_LOGIC = "Packages/StrandAnalytics/Sources/StrandAnalytics/CutScorecard.swift"
SCORECARD_BUILDER = "Strand/Data/CutScorecardInputBuilder.swift"
SCORECARD_MODEL = "Strand/Data/CutScorecardModel.swift"
SCORECARD_PRESENTER = "Strand/Data/CutScorecardPresenter.swift"
SCORECARD_VIEW = "StrandiOS/Scorecard/ScorecardView.swift"
WEEK_CHART = "StrandiOS/Scorecard/ScorecardWeekChart.swift"
HEALTH_VIEW = "StrandiOS/Redesign/RedesignHealthView.swift"
ROUTE = "StrandiOS/Redesign/RedesignRoute.swift"
SETTINGS_VIEW = "Strand/Screens/SettingsView.swift"
APP = "StrandiOS/App/StrandiOSApp.swift"
DEMO_REGISTRY = "Strand/Data/DemoScreenRegistry.swift"
TIMELINE = "Strand/Data/TimelineSources.swift"
TREND_CHART = "Packages/StrandDesign/Sources/StrandDesign/TrendChart.swift"
TODAY_REDESIGN = "StrandiOS/Redesign/RedesignTodayView.swift"
APP_MODEL = "Strand/App/AppModel.swift"
INTAKE_REMINDER = "Strand/System/IntakeCutoffReminder.swift"

# Where product Swift lives. Tests, tools and build output are out of scope.
PRODUCT_ROOTS = ("Strand", "StrandiOS", "StrandiOSShared", "StrandiOSWidgets")
WATCH_GLOB = "NOOPWatch*"

# The eight files that build notification content (§12.5). AppModel.swift is checked through its
# two notification functions only; the others as whole files.
NOTIFICATION_PRODUCERS = (
    APP_MODEL,
    "Strand/System/BatteryNotifier.swift",
    "Strand/System/CoachBriefScheduler.swift",
    "Strand/System/IllnessNotifier.swift",
    "Strand/System/StrainTargetNotifier.swift",
    "Strand/System/WeighInReminder.swift",
    "Strand/System/WindDownNudge.swift",
    INTAKE_REMINDER,
)
APP_MODEL_NOTIFICATION_FUNCTIONS = ("postWristAlert", "scheduleSmartAlarmBackupNotification")
# Allowed to be absent, with the reason printed: a file another stage adds.
NOT_YET_MERGED = {INTAKE_REMINDER: "stage 3's intake reminder has not merged into this branch"}

# The chart sites of §10.5 that pass marks, and the files that must never take them.
ADOPTING_SITES = (
    "StrandiOS/Redesign/RecoveryDetailView.swift",
    "StrandiOS/Redesign/StrainDetailView.swift",
    "Strand/Screens/MetricExplorerView.swift",
    "StrandiOS/App/TrainingHubView.swift",
    "Strand/Screens/TrendsView.swift",
)
NEVER_MARKED = (TREND_CHART, TODAY_REDESIGN)

# The patterns a personal event is recognised by in a file that must never carry one.
EVENT_PATTERN = re.compile(r"PersonalEvent|personalEvents\.|noop\.personalEventsEnabled")
EVENT_PATTERN_WITH_CHART = re.compile(r"PersonalEvent(?!Chart)|personalEvents\.|noop\.personalEventsEnabled")


def path_of(relative: str) -> Path:
    return ROOT / relative


def code(relative: str) -> str:
    """The file's code with comments blanked. Fails the calling test when the file is missing."""
    path = path_of(relative)
    if not path.is_file():
        raise AssertionError(f"{relative} does not exist")
    return "\n".join(strip_comments(path.read_text(encoding="utf-8")))


def product_files() -> list[Path]:
    files: list[Path] = []
    roots = [ROOT / name for name in PRODUCT_ROOTS] + sorted(ROOT.glob(WATCH_GLOB))
    for root in roots:
        if root.is_dir():
            files.extend(sorted(root.rglob("*.swift")))
    for sources in sorted((ROOT / "Packages").glob("*/Sources")):
        files.extend(sorted(sources.rglob("*.swift")))
    return [f for f in files if ".build" not in f.parts]


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def file_code(path: Path) -> str:
    return "\n".join(strip_comments(path.read_text(encoding="utf-8")))


def calls_event_store_write(text: str) -> bool:
    """True when ``text`` calls one of the events store's writes (§12.5, ruling A23).

    ``add(kind:`` is the events store's own spelling. ``update(`` and ``delete(id:`` are shared with
    other stores, so they count only in a file that names ``PersonalEventStore``.
    """
    if re.search(r"\.add\(\s*kind\s*:", text):
        return True
    names_store = "PersonalEventStore" in text
    return names_store and (re.search(r"\.update\(", text) is not None
                            or re.search(r"\.delete\(\s*id\s*:", text) is not None)


def holders(pattern: str | re.Pattern[str]) -> list[str]:
    """Every product file whose code (comments blanked) contains the literal or matches the pattern."""
    found = []
    for f in product_files():
        text = file_code(f)
        hit = pattern.search(text) if isinstance(pattern, re.Pattern) else pattern in text
        if hit:
            found.append(relative(f))
    return sorted(found)


def function_body(text: str, name: str) -> str:
    """The text of `func name` from its declaration to its matching closing brace."""
    match = re.search(rf"\bfunc\s+{re.escape(name)}\b", text)
    if match is None:
        raise AssertionError(f"func {name} not found")
    start = text.index("{", match.end())
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[match.start():i + 1]
    raise AssertionError(f"func {name} has no closing brace")


def debug_blocks(text: str) -> str:
    """The parts of a file inside `#if DEBUG` ... `#endif` (one level; nested #if counted)."""
    out: list[str] = []
    depth = 0
    inside = False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("#if"):
            if not inside and stripped.startswith("#if DEBUG"):
                inside = True
                depth = 1
                continue
            if inside:
                depth += 1
        elif stripped.startswith("#endif") and inside:
            depth -= 1
            if depth == 0:
                inside = False
                continue
        if inside:
            out.append(line)
    return "\n".join(out)


def outside_debug_blocks(text: str) -> str:
    """The lines of a file outside every `#if DEBUG` ... `#endif` block."""
    out: list[str] = []
    depth = 0
    inside = False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("#if"):
            if not inside and stripped.startswith("#if DEBUG"):
                inside = True
                depth = 1
                continue
            if inside:
                depth += 1
        elif stripped.startswith("#endif") and inside:
            depth -= 1
            if depth == 0:
                inside = False
                continue
        if not inside:
            out.append(line)
    return "\n".join(out)


class OneStoreTests(unittest.TestCase):
    """§4.3, §9: one store, one decode, writes only through the models."""

    def test_items_key_is_spelled_only_in_the_store_and_the_whitelist(self) -> None:
        self.assertEqual(holders('"personalEvents.items"'), sorted([STORE, BACKUP]))

    def test_the_flag_key_is_spelled_only_in_the_store(self) -> None:
        self.assertEqual(holders('"noop.personalEventsEnabled"'), [STORE])

    def test_only_the_models_call_the_store_writes(self) -> None:
        offenders = [relative(f) for f in product_files()
                     if relative(f) not in (STORE, MODELS) and calls_event_store_write(file_code(f))]
        self.assertEqual(sorted(set(offenders)), [], "only PersonalEventsModel.swift writes events (§4.3, A23)")
        models = code(MODELS)
        self.assertRegex(models, r"\.add\(\s*kind\s*:")
        self.assertRegex(models, r"\.update\(")
        self.assertRegex(models, r"\.delete\(\s*id\s*:")

    def test_the_write_matcher_flags_event_store_writes_and_nothing_else(self) -> None:
        # Ruling A23: a surface that changes an event calls the events model, never the store. The
        # store's `update(` and `delete(id:` share their spelling with other stores' writes (stage 3's
        # `IntakeQuickAddStore.delete(id:day:)`, stage 6's `CheckpointTimelineSettings.delete(id:)`),
        # so they count only in a file that names the events store (§12.5: "on the store").
        self.assertTrue(calls_event_store_write("model.add(kind: .deload, start: day)"))
        self.assertTrue(calls_event_store_write("let s = PersonalEventStore.shared\ntry s.delete(id: x)"))
        self.assertTrue(calls_event_store_write("let s: PersonalEventStore\ntry s.update(event)"))
        self.assertFalse(calls_event_store_write("let deleted = settings.delete(id: checkpointId)"))
        self.assertFalse(calls_event_store_write("try await store.delete(id: entry.id, day: entry.day)"))
        self.assertFalse(calls_event_store_write("try await store.update(entry)"))

    def test_the_store_decodes_with_json_serialization_and_has_no_database(self) -> None:
        text = code(STORE)
        self.assertIn("JSONSerialization", text)
        self.assertIn(".sortedKeys", text)
        for banned in ("WhoopStore", "Repository", "deviceId", "activeDeviceId", "suiteName:", "import GRDB"):
            self.assertNotIn(banned, text, f"{STORE} must not contain {banned} (§9.5, R42)")

    def test_no_flag_class_is_cloned(self) -> None:
        declared = holders(re.compile(r"\b(class|struct|enum|actor)\s+PersonalEventsFlag\b"))
        self.assertEqual(declared, [])
        self.assertRegex(code(STORE), r"static\s+let\s+flag\s*=\s*ObservableDefaultsFlag\(\s*key\s*:")
        # No view observes the key by another route.
        observed = holders(re.compile(r"AppStorage\(\s*(PersonalEventStore\.enabledKey|\"noop\.personalEventsEnabled\")"))
        self.assertEqual(observed, [], "views observe PersonalEventStore.flag, never @AppStorage")


class LeavesTheAppNowhereTests(unittest.TestCase):
    """§10.8, §12.5, C7: no widget, watch, notification, App Group or Coach context carries an event."""

    def test_widgets_watch_and_shared_payloads_never_name_personal_events(self) -> None:
        offenders = []
        for f in product_files():
            rel = relative(f)
            if rel.startswith(("StrandiOSWidgets/", "StrandiOSShared/", "NOOPWatch")):
                if EVENT_PATTERN.search(file_code(f)):
                    offenders.append(rel)
        self.assertEqual(offenders, [])

    def test_notification_producers_never_name_personal_events(self) -> None:
        for rel in NOTIFICATION_PRODUCERS:
            if not path_of(rel).is_file():
                continue
            text = code(rel)
            if rel == APP_MODEL:
                for name in APP_MODEL_NOTIFICATION_FUNCTIONS:
                    self.assertIsNone(EVENT_PATTERN.search(function_body(text, name)), f"{rel} {name}")
            else:
                self.assertIsNone(EVENT_PATTERN.search(text), rel)

    def test_every_notification_producer_is_listed(self) -> None:
        builders = holders("UNMutableNotificationContent")
        unlisted = [rel for rel in builders if rel not in NOTIFICATION_PRODUCERS]
        self.assertEqual(unlisted, [], "a new notification producer needs its place in NOTIFICATION_PRODUCERS")

    def test_coach_context_never_reads_personal_events(self) -> None:
        offenders = [rel for rel in holders(EVENT_PATTERN) if rel.startswith("Strand/AI/")]
        self.assertEqual(offenders, [], "no event of any kind enters the in-app Coach context (C7, S8)")

    def test_app_group_suite_is_never_given_the_events(self) -> None:
        offenders = []
        for f in product_files():
            text = file_code(f)
            if "UserDefaults(suiteName:" in text and re.search(r"personalEvents\.|noop\.personalEventsEnabled", text):
                offenders.append(relative(f))
            if "PersonalEventStore(defaults:" in text and re.search(r"PersonalEventStore\(defaults:\s*UserDefaults\(suiteName", text):
                offenders.append(relative(f))
        self.assertEqual(sorted(set(offenders)), [])

    def test_the_store_lives_in_standard_defaults(self) -> None:
        text = code(STORE)
        self.assertRegex(text, r"defaults\s*:\s*UserDefaults\s*=\s*\.standard")
        self.assertNotIn("WidgetSnapshot", text)


class ScorecardBoundaryTests(unittest.TestCase):
    """§10.6, F14: events reach the presenter's context and nothing that computes the verdict."""

    def test_scorecard_logic_never_sees_events(self) -> None:
        for rel in (SCORECARD_LOGIC, SCORECARD_BUILDER):
            self.assertIsNone(EVENT_PATTERN.search(code(rel)), f"{rel} must not see events")

    def test_the_model_fills_the_context_from_the_store(self) -> None:
        text = code(SCORECARD_MODEL)
        self.assertIn("PersonalEventStore", text)
        self.assertRegex(text, r"\.events\b")
        body = function_body(text, "load")
        self.assertIn("events", body, "load() passes the store's events to the presenter's context")
        self.assertNotRegex(body, r"evaluation\(\s*today\s*:[^)]*events", "the events never enter the evaluation")

    def test_the_presenter_declares_the_two_outputs(self) -> None:
        text = code(SCORECARD_PRESENTER)
        self.assertRegex(text, r"\bstruct\s+EventNote\b")
        self.assertRegex(text, r"\bvar\s+eventNote\s*:\s*[\w.]*EventNote\?")
        self.assertRegex(text, r"\bvar\s+marked\s*:\s*\[Bool\]")
        self.assertRegex(text, r"\bvar\s+events\s*:\s*\[PersonalEvent\]")

    def test_the_scorecard_screen_draws_the_note_through_its_own_view(self) -> None:
        text = code(SCORECARD_VIEW)
        self.assertEqual(text.count("ScorecardEventNoteView("), 1)
        self.assertIn("axisMarks:", text)
        self.assertNotIn("PersonalEventStore", text, "the screen reads the presentation, not the store")
        note = code(NOTE_VIEW)
        self.assertIn("eventNote", note)
        self.assertNotIn("PersonalEventStore", note, "the note view reads no store (§5)")


class ChartAdoptionTests(unittest.TestCase):
    """§10.5: one reader for every chart site; TrendChart and intraday charts are not adopted."""

    def test_adopting_sites_read_the_one_chart_source(self) -> None:
        for rel in ADOPTING_SITES:
            text = code(rel)
            self.assertIn("PersonalEventChartSource", text, f"{rel} reads marks through the chart source")
            self.assertIn("axisMarks:", text, rel)
            self.assertIn("PersonalEventChartCaption(", text, f"{rel} draws the caption under the chart")
            self.assertNotIn("PersonalEventStore", text, f"{rel} never reads the store itself")
            self.assertNotIn("PersonalEvents.", text, f"{rel} computes no overlap itself")

    def test_trend_chart_and_intraday_charts_take_no_marks(self) -> None:
        for rel in NEVER_MARKED:
            self.assertNotIn("axisMarks", code(rel), rel)

    def test_the_week_chart_takes_one_optional_parameter(self) -> None:
        self.assertRegex(code(WEEK_CHART), r"axisMarks\s*:\s*NoopChartAxisMarks\?\s*=\s*nil")

    def test_the_chart_source_reads_the_store_once_and_uses_the_pure_slots(self) -> None:
        text = code(CHART_SOURCE)
        self.assertIn("PersonalEvents.coveredSlots(", text)
        self.assertIn("PersonalEventSlot(", text)
        self.assertNotIn("DateFormatter", text)


class ViewsDecideNothingTests(unittest.TestCase):
    """Views format and decide nothing: every rule is in the presenter, the models or the pure module."""

    def test_event_views_hold_no_rule_and_no_formatter(self) -> None:
        for rel in (EVENTS_VIEW, SHEET_VIEW, NOTE_VIEW, CAPTION_VIEW):
            text = code(rel)
            for banned in ("PersonalEvents.", "DateFormatter", ".formatted(", "dayKey(for:", "LocalDayWindows",
                           "UserDefaults", "JSONSerialization", ".add(kind:", ".delete(id:"):
                self.assertNotIn(banned, text, f"{rel} must not contain {banned}")

    def test_the_caption_view_is_shared_with_macos(self) -> None:
        text = code(CAPTION_VIEW)
        self.assertNotIn("import UIKit", text)
        self.assertIn("PersonalEventCaption", text)


class PureLogicTests(unittest.TestCase):
    """§6, F27: the pure files use CanonicalDay and nothing else for days."""

    def test_personal_events_declare_no_day_rule_of_their_own(self) -> None:
        for rel in (PURE, PACKET):
            text = code(rel)
            for banned in ("parseYMD(", "formatYMD(", "isValidDay", "DateFormatter", "Calendar(", "TimeZone",
                           "Date(", "String(localized"):
                self.assertNotIn(banned, text, f"{rel} must not contain {banned}")
        self.assertIn("CanonicalDay.", code(PURE))

    def test_packet_lines_has_at_most_one_production_caller(self) -> None:
        callers = [rel for rel in holders("packetLines(") if rel != PACKET]
        self.assertLessEqual(len(callers), 1, f"packetLines( outside its file: {callers}")
        for rel in callers:
            self.assertIn("CoachPacket", rel, "the one caller is stage 2's assembler (packet v2)")

    def test_no_packet_setting_without_its_reader(self) -> None:
        callers = [rel for rel in holders("packetLines(") if rel != PACKET]
        if callers:
            return
        for needle in ("packetIncludesSensitive", "personalEvents.packetIncludesSensitive"):
            found = [rel for rel in holders(needle) if rel.startswith(("Strand/", "StrandiOS/"))]
            self.assertEqual(found, [], f"{needle} arrives with packet v2 and its reader (§9.6, F29)")

    def test_timeline_reads_events_only_through_visible(self) -> None:
        path = path_of(TIMELINE)
        if not path.is_file():
            self.skipTest(f"{TIMELINE} does not exist yet: stage 6 merges after this stage")
        text = code(TIMELINE)
        if "PersonalEventStore" not in text:
            self.skipTest(f"{TIMELINE} does not read PersonalEventStore")
        self.assertRegex(text, r"PersonalEvents\.visible\([^)]*includeSensitive\s*:\s*false")


class EntryPointTests(unittest.TestCase):
    """§10.1, §10.7, §12.4: the row and the screen exist only behind the flag; launch does nothing."""

    def test_the_health_row_is_behind_the_flag_and_routes_to_the_screen(self) -> None:
        text = code(HEALTH_VIEW)
        self.assertIn("PersonalEventStore.flag", text)
        self.assertIn(".personalEvents", text)
        self.assertRegex(code(ROUTE), r"\bcase\s+personalEvents\b")
        self.assertIn("PersonalEventsView(", code(ROUTE))

    def test_the_settings_card_switches_the_one_flag(self) -> None:
        text = code(SETTINGS_VIEW)
        self.assertIn("PersonalEventStore.flag.set(", text)
        # Packet v2 has landed: the second switch is mounted behind both flags and is the setting's
        # one writer (§9.6, §10.7). `test_coach_packet_v2_sources` pins the writer and the reader.
        self.assertIn("PersonalEventStore.shared.packetIncludesSensitive = ", text)
        self.assertIn("personalEventsFlag.isEnabled && coachPacketFlag.isEnabled", text)

    def test_nothing_at_launch_reads_the_store(self) -> None:
        for rel in (APP_MODEL, APP, "StrandiOS/App/AppModel+iOS.swift", "Strand/App/StrandApp.swift"):
            if not path_of(rel).is_file():
                continue
            text = code(rel)
            outside_debug = outside_debug_blocks(text)
            self.assertNotIn("PersonalEventStore", outside_debug, f"{rel} touches the store at launch")
            self.assertNotIn("PersonalEventChartSource", outside_debug, rel)


class DebugDemoTests(unittest.TestCase):
    """§14.1, ruling A4: one registry element, one prefix, debug builds only."""

    def test_the_demo_answers_only_its_own_prefix(self) -> None:
        text = code(DEMO)
        self.assertRegex(text, r"static\s+func\s+screen\(\s*named\s+\w+\s*:\s*String\s*\)\s*->\s*AnyView\?")
        self.assertIn('hasPrefix("events-")', text, "any other name is answered with nil")
        names = re.findall(r'case\s+"([^"]+)"', text)
        self.assertTrue(names, "the demo names its frames in a switch")
        self.assertEqual([n for n in names if not n.startswith("events-")], [])
        self.assertIn("PersonalEventsDemo", debug_blocks(text), "the demo is debug-only")
        self.assertNotIn("PersonalEventsDemo", outside_debug_blocks(text), "nothing of the demo outside #if DEBUG")

    def test_anything_writing_a_live_store_is_simulator_only(self) -> None:
        text = code(DEMO)
        for writer in ("UserDefaults.standard.set(", "PersonalEventStore.shared.add(", ".shared.add(kind:"):
            if writer in text:
                self.assertIn("targetEnvironment(simulator)", text, f"{DEMO} writes a live store outside the simulator")

    def test_the_registry_has_one_element_for_events(self) -> None:
        self.assertRegex(code(DEMO_REGISTRY), r'static\s+let\s+events\s*=\s*\[\s*"events-"\s*\]')
        app = code(APP)
        self.assertEqual(app.count("PersonalEventsDemo.screen(named:)"), 1)
        self.assertIn("DemoScreenPrefixes.events", app)
        self.assertIn("PersonalEventsDemo", debug_blocks(app), "the element is inside #if DEBUG")


class BackupWhitelistTests(unittest.TestCase):
    """§9.4: one key joins the Swift whitelist; the flag never does."""

    def test_the_list_joins_the_whitelist_and_the_flag_does_not(self) -> None:
        text = code(BACKUP)
        self.assertEqual(text.count('"personalEvents.items"'), 3,
                         "one whitelist entry and one storage mapping (key and value)")
        self.assertNotIn("noop.personalEventsEnabled", text)
        self.assertNotIn("packetIncludesSensitive", text)

    def test_the_fork_only_comment_names_the_key(self) -> None:
        raw = path_of(BACKUP).read_text(encoding="utf-8")
        block = raw.split("FORK-ONLY KEYS", 1)[-1].split("THE whitelist", 1)[0]
        self.assertIn("personalEvents.items", block)


class AllowlistTests(unittest.TestCase):
    """Each allowlisted file still exists and still contains its pattern."""

    def test_allowlists_still_match(self) -> None:
        for rel in NOTIFICATION_PRODUCERS:
            if not path_of(rel).is_file() and rel in NOT_YET_MERGED:
                continue
            self.assertIn("UNMutableNotificationContent", code(rel), f"{rel} no longer builds notifications")
        app_model = code(APP_MODEL)
        for name in APP_MODEL_NOTIFICATION_FUNCTIONS:
            self.assertIn("UNMutableNotificationContent", function_body(app_model, name), name)
        for rel in ADOPTING_SITES + NEVER_MARKED:
            self.assertTrue(path_of(rel).is_file(), f"{rel} is listed and missing")

    def test_files_not_yet_merged_are_reported(self) -> None:
        missing = [f"{rel}: {why}" for rel, why in NOT_YET_MERGED.items() if not path_of(rel).is_file()]
        if missing:
            self.skipTest("; ".join(missing))


if __name__ == "__main__":
    unittest.main()
