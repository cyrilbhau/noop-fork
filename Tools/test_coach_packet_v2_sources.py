#!/usr/bin/env python3
"""Source scan for packet v2 (stage 2 specification §7.12 "Tests", source-scan item; stage 5 §9.6).

API ASSUMED BY THESE TESTS

  - ``PersonalEvents.packetLines(`` has one production caller, ``Strand/Data/CoachPacketAssembler.swift``.
  - ``CoachPacket.swift`` declares no ``eventsByteAllowance``: the allowance is stage 5's
    ``PersonalEvents.packetByteAllowance``, and the budget names it.
  - ``test_packet_switch_has_one_writer_and_one_reader`` (stage 5 §9.6): the literal key
    ``personalEvents.packetIncludesSensitive`` occurs in product code only in ``PersonalEventStore.swift``;
    ``packetIncludesSensitive`` occurs in product code only there, in ``SettingsView.swift`` and in the
    assembler.
  - The assembler reads intake through ``IntakeProvider`` (``.series()``) and names no intake key or
    intake source id (stage 3 §14.5).
  - ``CoachPacket.swift`` declares the closed ``CoachPacketIntakeSource`` enum and names no stored
    intake source id.
  - Packet v2 does not edit ``Strand/AI/AICoach.swift``: the in-app Coach never names the packet's
    new input types.

Run with::

    cd Tools && python3 -m unittest test_coach_packet_v2_sources -v
"""

from __future__ import annotations

import re
import unittest

from test_personal_events_boundaries import code, holders


PACKET = "Packages/StrandAnalytics/Sources/StrandAnalytics/CoachPacket.swift"
EVENTS_PACKET = "Packages/StrandAnalytics/Sources/StrandAnalytics/PersonalEventsPacket.swift"
ASSEMBLER = "Strand/Data/CoachPacketAssembler.swift"
STORE = "Strand/Data/PersonalEventStore.swift"
SETTINGS_VIEW = "Strand/Screens/SettingsView.swift"
AI_COACH = "Strand/AI/AICoach.swift"
APP_ROOTS = ("Strand/", "StrandiOS/", "StrandiOSShared/", "StrandiOSWidgets/", "Packages/")


def product(found: list[str]) -> list[str]:
    return sorted(rel for rel in found if rel.startswith(APP_ROOTS) and "/Tests/" not in rel)


class PacketVersionTwoSourceTests(unittest.TestCase):

    def test_packet_lines_has_one_production_caller_the_assembler(self) -> None:
        callers = [rel for rel in product(holders("packetLines(")) if rel != EVENTS_PACKET]
        self.assertEqual(callers, [ASSEMBLER])
        self.assertEqual(code(ASSEMBLER).count("PersonalEvents.packetLines("), 1, "called once")

    def test_the_packet_declares_no_events_allowance_of_its_own(self) -> None:
        text = code(PACKET)
        self.assertNotIn("eventsByteAllowance", text)
        self.assertIn("PersonalEvents.packetByteAllowance", text, "the budget names stage 5's constant")
        self.assertRegex(text, r"formatVersion\s*=\s*2\b")

    def test_packet_switch_has_one_writer_and_one_reader(self) -> None:
        key = product(holders("personalEvents.packetIncludesSensitive"))
        self.assertEqual(key, [STORE], "the literal key lives in the store only")
        users = product(holders("packetIncludesSensitive"))
        self.assertEqual(users, sorted([STORE, SETTINGS_VIEW, ASSEMBLER]))
        self.assertEqual(code(ASSEMBLER).count(".packetIncludesSensitive"), 1, "read once per assembly")

    def test_the_assembler_reads_intake_through_the_provider_only(self) -> None:
        text = code(ASSEMBLER)
        self.assertIn(".series()", text)
        for banned in ("protein_g", "calories_in", "intake_read_at", "proteinKey", "energyKey",
                       "noop-intake", "nutrition-csv", "healthSourceId", "quickAddSourceId", "csvSourceId",
                       "intake.entries", "IntakeQuickAddStore"):
            self.assertNotIn(banned, text, f"{ASSEMBLER} must not name {banned}")

    def test_the_packet_takes_intake_sources_as_a_closed_enum(self) -> None:
        text = code(PACKET)
        self.assertRegex(text, r"\benum\s+CoachPacketIntakeSource\s*:\s*String\b")
        for banned in ("noop-intake", "nutrition-csv", "ResolvedIntake"):
            self.assertNotIn(banned, text, f"{PACKET} must not name {banned}")
        self.assertNotRegex(text, r"\bIntakeSource\b", "the app's own source enum stays out of the pure packet")

    def test_the_in_app_coach_is_not_edited_by_packet_v2(self) -> None:
        text = code(AI_COACH)
        for banned in ("CoachPacketIntake", "CoachPacketEvents", "packetLines(", "packetIncludesSensitive"):
            self.assertNotIn(banned, text)


if __name__ == "__main__":
    unittest.main()
