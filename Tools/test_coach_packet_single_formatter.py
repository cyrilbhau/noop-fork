#!/usr/bin/env python3
"""Source scan: the coach packet shares one formatter with the in-app Coach and owns no fact.

API ASSUMED BY THESE TESTS

From docs/personal/superapp/specs/stage-2.md, with RULINGS-ADDENDUM.md beside it:

  §5     The files of the stage, at these paths:
           Packages/StrandAnalytics/Sources/StrandAnalytics/CoachDayFormat.swift, CoachPacket.swift
           Strand/Data/CoachPacketSettings.swift, CoachPacketAssembler.swift, CoachPacketModel.swift,
             CoachPacketPresenter.swift
           StrandiOS/CoachPacket/CoachPacketSheet.swift, CoachPacketPasteboard.swift,
             CoachPacketShareSheet.swift, CoachPacketDemo.swift
           StrandiOS/System/CoachPacketIntent.swift
  §8.1   ``Strand/AI/AICoach.swift`` calls ``CoachDayFormat.dayLine(``,
         ``CoachDayFormat.primaryAveragesLine(``, ``CoachDayFormat.vitalsAveragesLine(`` and
         ``CoachDayFormat.efficiencyPercent(``, and no longer declares ``hoursOrDash``, ``avgOne``,
         ``avgInt`` or ``avgSleepHours``.
  §8.2   ``evaluateStored`` is gone. ``Strand/Data/CutScorecardModel.swift`` and
         ``Strand/Data/CoachPacketAssembler.swift`` both call ``evaluation(today:``, which
         ``Strand/Data/CutScorecardInputBuilder.swift`` declares.
  §8.3   ``CoachPacketSettings.swift`` declares the flag as ``ObservableDefaultsFlag(key:``. No file
         declares a type named ``CoachPacketFlag``.
  §8.4   ``CoachPacketAssembler.swift`` calls ``ChargeTypicalBand.range(``, ``resolvedSteps(``,
         ``workoutRows(``, ``WorkoutSource.classify(`` and ``.current(`` on the provider, and never
         ``Baselines.sigma(``.
  §9.1   ``UIPasteboard`` is written in ``CoachPacketPasteboard.swift`` with ``.localOnly`` and
         ``.expirationDate``.
  §9.2   ``CoachPacketShareSheet.swift`` excludes ``.copyToPasteboard``.
  §9.3   ``CoachPacketIntent.swift`` declares ``GetCoachPacketIntent`` with ``openAppWhenRun = false``
         and ``.requiresAuthentication``, returns the assembler's text, throws ``switchedOff`` with
         the flag off, and touches no pasteboard. ``StrandiOS/System/NOOPAppIntents.swift`` does not
         name it.
  §10.1  The Health row (``StrandiOS/Redesign/RedesignHealthView.swift``) and the toolbar item
         (``StrandiOS/Scorecard/ScorecardView.swift``) present ``CoachPacketSheet`` and read
         ``CoachPacketSettings.flag``. ``StrandiOS/Redesign/RedesignRoute.swift`` is not edited.
  §10.2  The preview is not selectable: ``CoachPacketSheet.swift`` shows it with ``Text(verbatim:``
         and never enables text selection.
  §14.1  ``CoachPacketDemo.swift`` answers only names beginning ``packet-``; the app's registry has
         one element for it, ``DemoScreenPrefixes.packet``.

Specification §12.4, §12.5 and the source-scan faults of §12.6. Written before the implementation
exists: until the stage's files are in the tree, the tests that read them fail by naming the missing
file.

LIMITS. A source scan matches spellings, not meanings. It cannot see that a view shown only behind
the flag is in fact hidden, that the pasteboard options take effect, or that the Shortcuts action
returns what the sheet previews. The behavioural half is the ``CoachPacket*Tests`` and
``CoachContextByteIdentityTests`` classes under StrandTests/; the simulator and the device assert
the rest (specification §12.8). The iPhone-only files (the sheet, the pasteboard writer, the share
sheet, the demo and the Shortcuts action) are not compiled by the macOS test target, so this scan is
the only automated check on them.

Run with::

    cd Tools && python3 -m unittest test_coach_packet_single_formatter -v
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

from test_body_measurement_single_resolver import ROOT, strip_comments


PACKAGE_SOURCES = "Packages/StrandAnalytics/Sources/StrandAnalytics"
DAY_FORMAT = f"{PACKAGE_SOURCES}/CoachDayFormat.swift"
PACKET = f"{PACKAGE_SOURCES}/CoachPacket.swift"
AI_COACH = "Strand/AI/AICoach.swift"
SETTINGS = "Strand/Data/CoachPacketSettings.swift"
ASSEMBLER = "Strand/Data/CoachPacketAssembler.swift"
MODEL = "Strand/Data/CoachPacketModel.swift"
PRESENTER = "Strand/Data/CoachPacketPresenter.swift"
SCORECARD_MODEL = "Strand/Data/CutScorecardModel.swift"
SCORECARD_BUILDER = "Strand/Data/CutScorecardInputBuilder.swift"
SHEET = "StrandiOS/CoachPacket/CoachPacketSheet.swift"
PASTEBOARD = "StrandiOS/CoachPacket/CoachPacketPasteboard.swift"
SHARE_SHEET = "StrandiOS/CoachPacket/CoachPacketShareSheet.swift"
DEMO = "StrandiOS/CoachPacket/CoachPacketDemo.swift"
INTENT = "StrandiOS/System/CoachPacketIntent.swift"
APP_INTENTS = "StrandiOS/System/NOOPAppIntents.swift"
HEALTH_VIEW = "StrandiOS/Redesign/RedesignHealthView.swift"
SCORECARD_VIEW = "StrandiOS/Scorecard/ScorecardView.swift"
ROUTE = "StrandiOS/Redesign/RedesignRoute.swift"
SCORE_DETAIL = "StrandiOS/Redesign/ScoreDetailData.swift"
APP = "StrandiOS/App/StrandiOSApp.swift"
DEMO_REGISTRY = "Strand/Data/DemoScreenRegistry.swift"

# Where product Swift lives. Tests, tools and build output are out of scope.
PRODUCT_ROOTS = ("Strand", "StrandiOS", "StrandiOSShared", "StrandiOSWidgets")

# File -> why it may name UIPasteboard. Every entry must still name it.
PASTEBOARD_ALLOWLIST: dict[str, str] = {
    "Strand/System/Platform.swift": "the shared cross-platform clipboard write, as before this stage",
    "Strand/Screens/CoachView.swift": "copying one Coach reply, as before this stage",
    PASTEBOARD: "the packet's local-only, expiring item",
    "StrandiOS/Events/PersonalEventsView.swift": (
        "ruling A24: the events list's \"Copy stored text\" writes the same local-only, expiring item"
        " as the packet's writer (setItems with .localOnly and .expirationDate, never a plain string)"),
}


def code(relative: str) -> str:
    """The file's code with comments blanked. Fails the calling test when the file is missing."""
    path = ROOT / relative
    if not path.is_file():
        raise AssertionError(f"{relative} does not exist")
    return "\n".join(strip_comments(path.read_text(encoding="utf-8")))


def product_files() -> list[Path]:
    files: list[Path] = []
    for name in PRODUCT_ROOTS:
        root = ROOT / name
        if root.is_dir():
            files.extend(sorted(root.rglob("*.swift")))
    for sources in sorted((ROOT / "Packages").glob("*/Sources")):
        files.extend(sorted(sources.rglob("*.swift")))
    return [f for f in files if ".build" not in f.parts]


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


class OneDayFormatterTests(unittest.TestCase):
    """§8.1, §12.4: the Coach's day line and averages come from ``CoachDayFormat`` and nowhere else."""

    def test_ai_coach_calls_the_shared_formatter(self) -> None:
        text = code(AI_COACH)
        for call in ("CoachDayFormat.dayLine(", "CoachDayFormat.primaryAveragesLine(",
                     "CoachDayFormat.vitalsAveragesLine(", "CoachDayFormat.efficiencyPercent("):
            self.assertIn(call, text, f"{AI_COACH} must call {call}")
        self.assertIn(".coachContext", text, "the Coach uses the style that reproduces its bytes")

    def test_ai_coach_no_longer_formats_a_day_itself(self) -> None:
        text = code(AI_COACH)
        for literal in ('"deep "', '"REM "', '"light "', '"HRV "', '"RHR "', '"charge "', '"effort "', '"rest "'):
            self.assertNotIn(literal, text, f"{AI_COACH} still builds a day field from {literal}")
        for helper in ("hoursOrDash", "avgOne", "avgInt", "avgSleepHours"):
            self.assertIsNone(re.search(rf"\bfunc\s+{helper}\b", text), f"{helper} was to be deleted (§8.1)")

    def test_ai_coach_keeps_its_two_internal_seams(self) -> None:
        text = code(AI_COACH)
        self.assertRegex(text, r"(?m)^\s*func\s+dayLine\(_", "dayLine(_:) stays an internal method")
        self.assertRegex(text, r"(?m)^\s*func\s+efficiencyPercentOrDash\(_",
                         "efficiencyPercentOrDash(_:) stays an internal method")

    def test_only_the_shared_formatter_spells_a_day_field(self) -> None:
        owners = [relative(f) for f in product_files()
                  if '"REM "' in "\n".join(strip_comments(f.read_text(encoding="utf-8")))]
        self.assertEqual(owners, [DAY_FORMAT], 'the literal "REM " belongs to one file')

    def test_the_packet_renders_days_through_the_shared_formatter(self) -> None:
        text = code(PACKET)
        self.assertIn("CoachDayFormat.dayLine(", text)
        self.assertIn("CoachDayFormat.primaryAveragesLine(", text)


class PureLogicTests(unittest.TestCase):
    """§6, §12.4: the renderer and the formatter read no clock, zone, locale or catalogue."""

    def test_pure_files_have_no_clock_locale_or_catalogue(self) -> None:
        for path in (PACKET, DAY_FORMAT):
            text = code(path)
            for banned in ("String(localized", "Locale", "Date(", "TimeZone", "UserDefaults", "import SwiftUI",
                           "import UIKit", "import AppKit"):
                self.assertNotIn(banned, text, f"{path} must not contain {banned}")

    def test_the_packet_has_no_day_arithmetic_of_its_own(self) -> None:
        text = code(PACKET)
        self.assertIn("CanonicalDay.", text)
        for banned in ("parseYMD", "julianDayNumber", "DateFormatter", "Calendar"):
            self.assertNotIn(banned, text, f"{PACKET} must go through CanonicalDay, not {banned}")

    def test_canonical_day_surface_is_declared_once(self) -> None:
        declared = []
        for f in product_files():
            text = "\n".join(strip_comments(f.read_text(encoding="utf-8")))
            if "CanonicalDay" in text and re.search(r"\bstatic\s+func\s+number\(_\s+key\s*:\s*String\s*\)", text):
                declared.append(relative(f))
        self.assertEqual(declared, [f"{PACKAGE_SOURCES}/CanonicalDay+Surface.swift"], "ruling A9")


class OneEvaluationTests(unittest.TestCase):
    """§8.2, §12.4: the screen and the packet call one scorecard evaluation."""

    def test_evaluate_stored_is_gone(self) -> None:
        holders = [relative(f) for f in product_files()
                   if "evaluateStored" in "\n".join(strip_comments(f.read_text(encoding="utf-8")))]
        self.assertEqual(holders, [], "evaluateStored moved to CutScorecardInputBuilder.evaluation(today:)")

    def test_the_builder_declares_the_funnel(self) -> None:
        self.assertRegex(code(SCORECARD_BUILDER), r"\bfunc\s+evaluation\(\s*today\s*:")

    def test_the_screen_model_and_the_assembler_both_call_it(self) -> None:
        for path in (SCORECARD_MODEL, ASSEMBLER):
            self.assertIn("evaluation(today:", code(path), f"{path} must call evaluation(today:)")

    def test_the_assembler_evaluates_nothing_itself(self) -> None:
        text = code(ASSEMBLER)
        self.assertNotIn("CutScorecard.evaluate(", text, "the packet has no evaluation of its own")
        self.assertEqual(text.count("CutScorecardInputBuilder("), 1, "one construction of the builder (§8.4 step 3)")


class AssemblerFunnelTests(unittest.TestCase):
    """§4, §8.4, §12.4: every fact is read through the function the screens read it through."""

    def test_the_typical_range_is_the_shared_one(self) -> None:
        text = code(ASSEMBLER)
        self.assertIn("ChargeTypicalBand.range(", text)
        self.assertNotIn("Baselines.sigma(", text, "the assembler computes no band of its own")
        self.assertNotIn(".usable", text, "usable is `typical != nil`, decided by ChargeTypicalBand (§4)")

    def test_the_recovery_detail_draws_the_same_range(self) -> None:
        text = code(SCORE_DETAIL)
        self.assertIn("ChargeTypicalBand.range(", text)
        self.assertNotIn("Baselines.sigma(", text)

    def test_the_assembler_reads_through_the_named_funnels(self) -> None:
        text = code(ASSEMBLER)
        for call in ("resolvedSteps(", "workoutRows(", "WorkoutSource.classify(", "chargeBaselines",
                     "LocalDayWindows(", ".refresh()", "CoachPacket.render(", "CoachPacket.scan("):
            self.assertIn(call, text, f"{ASSEMBLER} must contain {call}")
        self.assertRegex(text, r"\.current\(\s*\.weight\s*,\s*consumer:\s*\.display\s*\)")

    def test_the_assembler_reads_no_store_table_and_no_other_setting(self) -> None:
        text = code(ASSEMBLER)
        for banned in ("storeHandle(", "labMarkers(", "LabBookRows.", "upsert", "delete", "\"profile.",
                       "noop.coachEnabled", "ai.dataConsent", "dataConsent", "UserDefaults.standard.set",
                       "URLSession", "UIPasteboard", "NSPasteboard"):
            self.assertNotIn(banned, text, f"{ASSEMBLER} must not contain {banned}")

    def test_the_packet_takes_sources_as_closed_enums(self) -> None:
        # A raw `source` string would need a stored namespace or a device id to pass through.
        text = code(PACKET)
        for banned in ("apple_health", "nutrition-csv", "deviceId", "WorkoutRow", "ResolvedMetricPoint"):
            self.assertNotIn(banned, text, f"{PACKET} must not name {banned}")
        for enum in ("CoachPacketBodySource", "CoachPacketStepSource", "CoachPacketWorkoutSource"):
            self.assertRegex(text, rf"\benum\s+{enum}\s*:\s*String\b")


class FlagTests(unittest.TestCase):
    """§8.3, §12.4, §12.5: one flag, one observer, and nothing built while it is off."""

    def test_no_flag_type_is_declared(self) -> None:
        declared = [relative(f) for f in product_files()
                    if re.search(r"\b(class|struct|enum|actor)\s+CoachPacketFlag\b",
                                 "\n".join(strip_comments(f.read_text(encoding="utf-8"))))]
        self.assertEqual(declared, [])

    def test_the_settings_declare_the_one_observer(self) -> None:
        text = code(SETTINGS)
        self.assertIn("ObservableDefaultsFlag(key:", text)
        self.assertIn('"noop.coachPacketEnabled"', text)
        self.assertIn('"coachPacket.rangeDays"', text)
        self.assertIn('"coachPacket.sections"', text)

    def test_the_flag_key_is_spelled_in_one_file(self) -> None:
        holders = [relative(f) for f in product_files()
                   if "noop.coachPacketEnabled" in "\n".join(strip_comments(f.read_text(encoding="utf-8")))]
        self.assertEqual(holders, [SETTINGS], "every other file reads CoachPacketSettings.enabledKey or .flag")

    def test_the_entry_points_exist_only_behind_the_flag(self) -> None:
        for path in (HEALTH_VIEW, SCORECARD_VIEW):
            text = code(path)
            self.assertIn("CoachPacketSheet(", text, f"{path} presents the sheet")
            self.assertIn("CoachPacketSettings.flag", text, f"{path} shows its entry only while the flag is on")
            self.assertIn(".sheet(", text, "the packet is presented, not pushed (§10.1)")

    def test_the_route_file_has_no_packet_route(self) -> None:
        self.assertNotIn("CoachPacket", code(ROUTE), "the sheet is presented with .sheet; no route is added")

    def test_the_packet_reaches_no_today_card_widget_or_notification(self) -> None:
        offenders = []
        for f in product_files():
            rel = relative(f)
            if not any(part in rel for part in ("StrandiOSWidgets/", "StrandiOSShared/", "NOOPWatch", "Strand/Liquid/",
                                                "Strand/Screens/TodayView.swift", "Strand/Screens/DashboardCards.swift",
                                                "Strand/Data/TodayCardReadout.swift", "Notification")):
                continue
            if "CoachPacket" in "\n".join(strip_comments(f.read_text(encoding="utf-8"))):
                offenders.append(rel)
        self.assertEqual(offenders, [], "no Today card, widget or notification carries the packet (§10.5)")


class PasteboardTests(unittest.TestCase):
    """§9.1, §9.2, §12.4: one new clipboard writer, local-only and expiring."""

    def test_uipasteboard_occurs_only_in_the_allowlist(self) -> None:
        holders = sorted(relative(f) for f in product_files()
                         if "UIPasteboard" in "\n".join(strip_comments(f.read_text(encoding="utf-8"))))
        self.assertEqual(holders, sorted(PASTEBOARD_ALLOWLIST),
                         "a new clipboard writer needs its file and its reason in PASTEBOARD_ALLOWLIST")

    def test_every_allowlisted_file_still_writes_the_pasteboard(self) -> None:
        for path in PASTEBOARD_ALLOWLIST:
            self.assertIn("UIPasteboard", code(path), f"{path} is allowlisted and no longer needs to be")

    def test_the_packet_writer_sets_local_only_and_an_expiry(self) -> None:
        text = code(PASTEBOARD)
        self.assertIn("SystemCoachPacketPasteboard", text)
        self.assertIn("CoachPacketPasteboardWriting", text)
        self.assertIn("setItems(", text)
        self.assertIn(".localOnly", text)
        self.assertIn(".expirationDate", text)
        self.assertIn("plan.expiresAt", text, "the expiry given to the system is the plan's")
        self.assertIn("plan.localOnly", text)
        self.assertNotIn(".string =", text, "a plain string write carries no options")

    def test_the_protocol_and_the_plan_are_shared_code(self) -> None:
        shared = code(MODEL) + code(PRESENTER)
        self.assertRegex(shared, r"\bprotocol\s+CoachPacketPasteboardWriting\b")
        self.assertRegex(shared, r"\bstruct\s+CoachPacketCopyPlan\b")
        for path in (MODEL, PRESENTER, SETTINGS, ASSEMBLER):
            text = code(path)
            self.assertNotIn("UIPasteboard", text)
            self.assertNotIn("import UIKit", text, f"{path} compiles for macOS")

    def test_the_share_sheet_has_no_copy_of_its_own(self) -> None:
        text = code(SHARE_SHEET)
        self.assertIn("UIActivityViewController", text)
        self.assertIn("excludedActivityTypes", text)
        self.assertIn(".copyToPasteboard", text)

    def test_the_preview_is_verbatim_and_not_selectable(self) -> None:
        text = code(SHEET)
        self.assertIn("Text(verbatim:", text, "the packet text never passes through the string catalogue")
        self.assertNotIn(".textSelection(.enabled)", text, "selecting part of it would bypass the local-only item")
        self.assertNotIn("TextEditor", text)
        self.assertNotIn("ShareLink", text, "ShareLink cannot drop the system's own Copy")
        self.assertNotIn("UIPasteboard", text, "the sheet copies through the model and its writer")


class ShortcutsActionTests(unittest.TestCase):
    """§9.3, §10.4: the action returns the sheet's text and writes no pasteboard."""

    def test_the_action_is_declared_as_specified(self) -> None:
        text = code(INTENT)
        self.assertRegex(text, r"\bstruct\s+GetCoachPacketIntent\s*:\s*AppIntent\b")
        self.assertRegex(text, r"openAppWhenRun\s*(:\s*Bool\s*)?=\s*false")
        self.assertIn(".requiresAuthentication", text)
        self.assertIn("ReturnsValue<String>", text)
        self.assertRegex(text, r"\benum\s+CoachPacketIntentError\b")
        for case in ("switchedOff", "notReady", "blocked", "unavailable"):
            self.assertRegex(text, rf"\b{case}\b")
        self.assertNotIn("@Parameter", text, "the action has no parameters: it uses the stored choices")

    def test_the_action_returns_the_assemblers_text(self) -> None:
        text = code(INTENT)
        self.assertIn("CoachPacketAssembler.live()", text)
        self.assertIn(".assemble()", text)
        self.assertNotIn("CoachPacket.render(", text, "the action renders nothing itself")
        self.assertNotIn("CoachPacketInput(", text)

    def test_the_action_writes_no_pasteboard_and_shows_no_dialog(self) -> None:
        text = code(INTENT)
        for banned in ("UIPasteboard", "CoachPacketPasteboardWriting", "SystemCoachPacketPasteboard",
                       "CoachPacketCopyPlan", "ProvidesDialog", "IntentDialog", "dialog:"):
            self.assertNotIn(banned, text, f"{INTENT} must not contain {banned}")

    def test_the_action_fails_with_the_flag_off(self) -> None:
        text = code(INTENT)
        self.assertRegex(text, r"isEnabled|CoachPacketSettings\.flag", "the action reads the flag")
        self.assertRegex(text, r"throw\s+CoachPacketIntentError\.switchedOff")

    def test_the_action_has_no_siri_phrase(self) -> None:
        self.assertNotIn("GetCoachPacketIntent", code(APP_INTENTS),
                         "no entry in NOOPShortcuts: no Siri phrase and no tip (§9.3)")


class DebugDemoTests(unittest.TestCase):
    """§14.1, ruling A4: one registry element, one prefix."""

    def test_the_demo_answers_only_its_own_prefix(self) -> None:
        text = code(DEMO)
        self.assertRegex(text, r"static\s+func\s+screen\(\s*named\s+\w+\s*:\s*String\s*\)\s*->\s*AnyView\?")
        self.assertIn('hasPrefix("packet-")', text, "any other name is answered with nil")
        names = re.findall(r'case\s+"([^"]+)"', text)
        self.assertTrue(names, "the demo names its frames in a switch")
        self.assertEqual([n for n in names if not n.startswith("packet-")], [],
                         "every demo name of this stage begins packet-")

    def test_the_registry_has_one_element_for_the_packet(self) -> None:
        self.assertRegex(code(DEMO_REGISTRY), r'static\s+let\s+packet\s*=\s*\[\s*"packet-"\s*\]')
        app = code(APP)
        self.assertEqual(app.count("CoachPacketDemo.screen(named:)"), 1)
        self.assertIn("DemoScreenPrefixes.packet", app)


class LocalOnlyTests(unittest.TestCase):
    """§1: the app sends the packet nowhere and stores it nowhere."""

    def test_no_packet_file_opens_a_network_path_or_writes_a_file(self) -> None:
        for path in (PACKET, DAY_FORMAT, SETTINGS, ASSEMBLER, MODEL, PRESENTER, SHEET, PASTEBOARD, SHARE_SHEET, INTENT):
            text = code(path)
            for banned in ("URLSession", "URLRequest", "http://", "https://", "NWConnection", ".write(to:",
                           "FileManager", "callProvider", "AIProvider"):
                self.assertNotIn(banned, text, f"{path} must not contain {banned}")

    def test_the_packet_is_never_handed_to_the_in_app_coach(self) -> None:
        text = code(AI_COACH)
        for banned in ("CoachPacket.", "CoachPacketAssembler", "CoachPacketSettings", "coachPacket"):
            self.assertNotIn(banned, text, "the in-app Coach is told nothing new by this stage")


if __name__ == "__main__":
    unittest.main()
