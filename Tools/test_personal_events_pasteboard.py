#!/usr/bin/env python3
"""Source scan: personal events reach the pasteboard only as a local-only, expiring item.

"Copy stored text" (stage 5 specification §10.4) copies the raw stored list, which can hold the names
and notes of private events. Like the coach packet (stage 2 §9.1), it must never be offered to
another device through Universal Clipboard or Handoff, and the system removes it after a while.
The behavioural half is ``Stage5ReviewFixTests`` in StrandTests, which checks the copy plan the model
hands to its writer; the iPhone writer itself is not compiled by the macOS test target, and the
options it passes cannot be read back from the pasteboard, so this scan is the check on it.

Run with::

    cd Tools && python3 -m unittest test_personal_events_pasteboard -v
"""

from __future__ import annotations

import unittest

from test_body_measurement_single_resolver import ROOT, strip_comments

EVENTS_DIR = ROOT / "StrandiOS" / "Events"


def code(path) -> str:
    return "\n".join(strip_comments(path.read_text(encoding="utf-8")))


class PersonalEventsPasteboardTests(unittest.TestCase):

    def test_no_events_file_assigns_the_general_pasteboard_directly(self) -> None:
        for path in sorted(EVENTS_DIR.glob("*.swift")):
            text = code(path)
            for banned in ("UIPasteboard.general.string", "UIPasteboard.general.strings",
                           "UIPasteboard.general.items =", "UIPasteboard.general.addItems("):
                self.assertNotIn(banned, text, f"{path.relative_to(ROOT)} must not use {banned}")

    def test_every_pasteboard_write_is_local_only_and_expires(self) -> None:
        writes = 0
        for path in sorted(EVENTS_DIR.glob("*.swift")):
            text = code(path)
            if "UIPasteboard" not in text:
                continue
            for chunk in text.split("setItems(")[1:]:
                writes += 1
                call = chunk[:400]
                self.assertIn(".localOnly:", call, f"{path.relative_to(ROOT)}: setItems without .localOnly")
                self.assertIn(".expirationDate:", call,
                              f"{path.relative_to(ROOT)}: setItems without .expirationDate")
        self.assertGreaterEqual(writes, 1, "the rescue copy's writer is expected under StrandiOS/Events/")


if __name__ == "__main__":
    unittest.main()
