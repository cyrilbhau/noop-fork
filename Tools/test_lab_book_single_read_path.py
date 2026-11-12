#!/usr/bin/env python3
"""Source scan: Lab Book rows are read through one path, and a strap never owns them.

API ASSUMED BY THESE TESTS

From docs/personal/superapp/specs/labbook-ownership.md (ruling R42 of stage-1.md):

  §6.2  ``Strand/Data/LabBookRows.swift`` declares ``enum LabBookRows`` with ``all``, ``category``,
        ``marker`` and ``stored(marker:store:)``, and is the only app-target file that calls
        ``WhoopStore.allLabMarkers(...)``.
  §4.1  ``Strand/Screens/LabBookView.swift`` reads through ``LabBookRows.all(``, writes through
        ``upsertOwnerLabMarkers(`` (manual save and CSV import) and deletes through
        ``deleteLabMarkerAndCopies(``. ``Strand/AI/AICoach.swift`` reads through
        ``LabBookRows.category(``. ``Strand/Data/BodyMeasurementProvider.swift`` reads through
        ``LabBookRows.marker(`` and no longer declares ``unionedDeviceIds``.
        ``Strand/Data/WeighInStore.swift`` may still call ``labMarkers(deviceId:`` to look a row up
        under that row's own id, and deletes through ``deleteLabMarkerAndCopies(``.
  §6.1  ``Packages/WhoopStore/Sources/WhoopStore/DeviceRegistryStore.swift`` declares
        ``ownerEnteredTables`` (naming ``labMarker``) and ``strapScopedTables``; ``deleteAllData`` and
        ``adoptSerialIdentity`` iterate ``strapScopedTables`` and never ``deviceScopedTables``.
  §7.3  ``Strand/Data/Repository.swift`` runs the projection repair in its store open. The call is
        spelled ``repairLabBookProjection(``; ``StrandTests/LabBookOwnershipFlowTests.swift`` pins
        where and how often.

Specification §12.4 (cases 68, 69, 70 and 81) and §12.8 (faults F2, F11, F12, F28). The allowlist is
a literal in this file: a stage that needs a new reader adds the file and its reason here, in its own
change, and never widens a pattern (§6.3).

LIMITS. A source scan matches spellings, not meanings. It does not see a read reached through a
wrapper declared under Packages/, nor a row list fetched once and filtered by device id afterwards.
The behavioural half is ``StrandTests/LabBookRowsTests.swift`` and
``StrandTests/LabBookOwnershipFlowTests.swift``.

Run with::

    cd Tools && python3 -m unittest test_lab_book_single_read_path -v
"""

from __future__ import annotations

import re
import unittest

from test_body_measurement_single_resolver import ROOT, strip_comments, swift_files


# Patterns that mean "this line reads Lab Book rows by itself".
READ_PATTERNS: dict[str, re.Pattern[str]] = {
    "per-id-read": re.compile(r"\blabMarkers\(\s*deviceId:"),
    "all-id-read": re.compile(r"\ballLabMarkers\("),
    "marker-keys-read": re.compile(r"\bmarkerKeysPresent\("),
    "sql": re.compile(r"\"[^\"]*\blabMarker\b[^\"]*\""),
}

# File -> (the patterns it may contain, the reason). Every entry MUST still contain each of its
# patterns (case 69). A pattern outside an entry's set is an offence even in an allowlisted file.
ALLOWLIST: dict[str, tuple[frozenset[str], str]] = {
    "Strand/Data/LabBookRows.swift": (frozenset({"all-id-read"}), "the funnel"),
    "Strand/Data/WeighInStore.swift":
        (frozenset({"per-id-read"}), "row lookup under a row's own id, before an edit or a delete"),
}

# Names no app-target file may spell (case 81): a second union, or a device-id list built from the
# registry, beside the funnel.
FORBIDDEN_NAMES: dict[str, re.Pattern[str]] = {
    "LabBookUnion": re.compile(r"\bLabBookUnion\b"),
    "unionedDeviceIds(": re.compile(r"\bunionedDeviceIds\("),
}
FORBIDDEN_ROOTS = ("Strand/", "StrandiOS/")

# File -> spellings it must contain (the funnel's callers, and the owner-scope writes).
REQUIRED: dict[str, tuple[str, ...]] = {
    "Strand/Data/LabBookRows.swift": ("enum LabBookRows", "LabMarkerUnion.merged("),
    "Strand/Screens/LabBookView.swift":
        ("LabBookRows.all(", "upsertOwnerLabMarkers(", "deleteLabMarkerAndCopies("),
    "Strand/AI/AICoach.swift": ("LabBookRows.category(",),
    "Strand/Data/BodyMeasurementProvider.swift": ("LabBookRows.marker(",),
    "Strand/Data/WeighInStore.swift": ("deleteLabMarkerAndCopies(",),
    "Strand/Data/Repository.swift": ("repairLabBookProjection(",),
}
# File -> (spelling, the reason it must be gone).
RETIRED: dict[str, tuple[tuple[str, str], ...]] = {
    "Strand/Screens/LabBookView.swift": (
        ("upsertLabMarkers(", "a re-imported or re-saved reading must update the row wherever it is stored"),
        ("deleteLabMarker(", "deleting only the listed row lets the reading reappear from its copy"),
    ),
}

REGISTRY_STORE = "Packages/WhoopStore/Sources/WhoopStore/DeviceRegistryStore.swift"


def code(file: str) -> str:
    """One file's code with comments blanked, as one string. Empty when the file is missing."""
    path = ROOT / file
    if not path.is_file():
        return ""
    return "\n".join(strip_comments(path.read_text(encoding="utf-8")))


def read_occurrences() -> list[tuple[str, int, str, str]]:
    """Every (file, line number, pattern name, code) in the app targets."""
    found: list[tuple[str, int, str, str]] = []
    for path in swift_files():
        file = path.relative_to(ROOT).as_posix()
        for number, line in enumerate(strip_comments(path.read_text(encoding="utf-8")), start=1):
            for name, pattern in READ_PATTERNS.items():
                if pattern.search(line):
                    found.append((file, number, name, line.strip()))
    return found


def function_body(text: str, name: str) -> str | None:
    """The text between the braces of the first `func name(` in `text`, braces balanced."""
    match = re.search(r"\bfunc\s+" + re.escape(name) + r"\s*\(", text)
    if match is None:
        return None
    start = text.find("{", match.end())
    if start < 0:
        return None
    depth, i = 1, start + 1
    while i < len(text) and depth:
        depth += {"{": 1, "}": -1}.get(text[i], 0)
        i += 1
    return text[start + 1:i - 1]


class LabBookSingleReadPathTests(unittest.TestCase):
    maxDiff = None

    def test_scan_sees_the_app_targets(self) -> None:
        """A renamed target must not turn the scan into a pass over nothing."""
        files = {path.relative_to(ROOT).as_posix() for path in swift_files()}
        self.assertGreater(len(files), 100, "the scan found implausibly few Swift files")
        for root in ("Strand/", "StrandiOS/", "StrandiOSShared/", "StrandiOSWidgets/", "NOOPWatch"):
            self.assertTrue(any(file.startswith(root) for file in files), f"no Swift file under {root}")
        self.assertIn("Strand/Screens/LabBookView.swift", files)

    def test_patterns_match_the_spellings_the_specification_lists(self) -> None:
        samples = {
            "per-id-read": [
                "let rows = (try? await store.labMarkers(deviceId: repo.deviceId, category: category.rawValue)) ?? []",
                "try await store.labMarkers(deviceId: deviceId, markerKey: kind.markerKey)",
                "store.labMarkers( deviceId: id, markerKey: key)"],
            "all-id-read": ["let rows = (try? await store.allLabMarkers()) ?? []",
                            "try await store.allLabMarkers(markerKey: markerKey)"],
            "marker-keys-read": ["let keys = try await store.markerKeysPresent(deviceId: repo.deviceId)"],
            "sql": ['try db.execute(sql: "DELETE FROM labMarker WHERE deviceId = ?", arguments: [id])',
                    'let sql = "SELECT * FROM labMarker"'],
        }
        self.assertEqual(set(samples), set(READ_PATTERNS))
        for name, lines in samples.items():
            for line in lines:
                self.assertRegex(line, READ_PATTERNS[name], f"{name} must match: {line}")
        for line in ["await LabBookRows.all(store: store, activeDeviceId: repo.deviceId)",
                     "await LabBookRows.marker(kind.markerKey, store: store, activeDeviceId: deviceId)",
                     "try await store.upsertOwnerLabMarkers(rows)",
                     "try await store.deleteLabMarkerAndCopies(id: id)",
                     "try await store.upsertLabMarkers(rows)",
                     'Text("Lab Book readings you entered are kept.")',
                     'logImport("labMarkers imported")',
                     "markers = all.sorted { $0.takenAt < $1.takenAt }"]:
            for name, pattern in READ_PATTERNS.items():
                self.assertNotRegex(line, pattern, f"{name} must not match: {line}")

    def test_no_app_file_reads_lab_book_rows_outside_the_funnel(self) -> None:
        """Case 68. Protects F11, F12 and F28."""
        offenders = [
            f"{file}:{number}: [{name}] {line}"
            for file, number, name, line in read_occurrences()
            if file not in ALLOWLIST or name not in ALLOWLIST[file][0]
        ]
        self.assertEqual(
            offenders, [],
            "Ruling R42 (labbook-ownership.md §6.2, §6.3): a Lab Book reading is the owner's, whichever "
            "strap was active when it was entered. These lines read Lab Book rows by themselves, so "
            "they can list one device id and hide the rest. Read through LabBookRows (all, category, "
            "marker, or stored for a write-side check). A new reader that genuinely needs its own "
            "read is added to ALLOWLIST with its reason, in its own change:\n" + "\n".join(offenders))

    def test_allowlist_entries_still_match(self) -> None:
        """Case 69: a stale entry fails."""
        found = {(file, name) for file, _, name, _ in read_occurrences()}
        stale = []
        for file, (patterns, reason) in sorted(ALLOWLIST.items()):
            self.assertTrue(patterns, f"{file} allows nothing; remove the entry")
            self.assertTrue(patterns <= set(READ_PATTERNS), f"{file} names an unknown pattern")
            if not (ROOT / file).is_file():
                stale.append(f"{file}: missing ({reason})")
                continue
            for name in sorted(patterns):
                if (file, name) not in found:
                    stale.append(f"{file}: no longer contains [{name}] ({reason})")
        self.assertEqual(
            stale, [],
            "These allowlisted files are missing or no longer contain a pattern they are allowed. "
            "Remove the entry, or, before the implementation lands, create the file:\n" + "\n".join(stale))

    def test_no_second_union_and_no_registry_built_id_list(self) -> None:
        """Case 81. Protects F28."""
        offenders = []
        for path in swift_files():
            file = path.relative_to(ROOT).as_posix()
            if not file.startswith(FORBIDDEN_ROOTS):
                continue
            for number, line in enumerate(strip_comments(path.read_text(encoding="utf-8")), start=1):
                for name, pattern in FORBIDDEN_NAMES.items():
                    if pattern.search(line):
                        offenders.append(f"{file}:{number}: [{name}] {line.strip()}")
        self.assertEqual(
            offenders, [],
            "LabBookRows is the only Lab Book union in the app target (labbook-ownership.md §6.3). "
            "\"Every id\" means every device id present in labMarker; a list built from the registry "
            "is what hid the readings under a forgotten strap:\n" + "\n".join(offenders))

    def test_readers_and_writers_go_through_the_owner_scope_calls(self) -> None:
        missing = [f"{file}: {spelling}"
                   for file, spellings in sorted(REQUIRED.items())
                   for spelling in spellings if spelling not in code(file)]
        self.assertEqual(
            missing, [],
            "labbook-ownership.md §4.1 and §7.4 name the call each of these files makes. Missing "
            "(a missing file counts as missing every spelling):\n" + "\n".join(missing))
        view = code("Strand/Screens/LabBookView.swift")
        self.assertGreaterEqual(view.count("upsertOwnerLabMarkers("), 2,
                                "LabBookView.swift: both the manual save and the CSV import write through "
                                "upsertOwnerLabMarkers")
        retired = [f"{file}: {spelling} ({reason})"
                   for file, entries in sorted(RETIRED.items())
                   for spelling, reason in entries
                   if re.search(r"(?<![\w])" + re.escape(spelling), code(file))]
        self.assertEqual(retired, [], "These per-id writes are superseded by the owner-scope calls:\n"
                         + "\n".join(retired))

    def test_strap_delete_and_adoption_iterate_the_strap_scoped_tables(self) -> None:
        """Case 70. Protects F1, F2 and F3."""
        self.assertTrue((ROOT / REGISTRY_STORE).is_file(), f"{REGISTRY_STORE} is missing")
        text = code(REGISTRY_STORE)
        for name in ("deleteAllData", "adoptSerialIdentity"):
            body = function_body(text, name)
            self.assertIsNotNone(body, f"{REGISTRY_STORE}: func {name} was not found")
            self.assertIn("strapScopedTables", body,
                          f"{name} must iterate strapScopedTables (labbook-ownership.md §6.1)")
            self.assertNotIn("deviceScopedTables", body,
                             f"{name} iterates deviceScopedTables, which holds labMarker: a strap delete or "
                             "an adoption would remove or drop the owner's Lab Book readings")
            self.assertNotRegex(body, r"\blabMarker\b", f"{name} must issue no statement against labMarker")
        owner = re.search(r"\bstatic\s+let\s+ownerEnteredTables\b[^=]*=\s*\[([^\]]*)\]", text)
        self.assertIsNotNone(owner, f"{REGISTRY_STORE}: static let ownerEnteredTables was not found")
        self.assertIn('"labMarker"', owner.group(1), "labMarker must be an owner-entered table")
        self.assertRegex(text, r"\bstatic\s+var\s+strapScopedTables\b",
                         f"{REGISTRY_STORE}: static var strapScopedTables was not found")
        scoped = re.search(r"\bstatic\s+let\s+deviceScopedTables\s*=\s*\[(.*?)\n\s*\]", text, re.DOTALL)
        self.assertIsNotNone(scoped, f"{REGISTRY_STORE}: static let deviceScopedTables was not found")
        self.assertIn('"labMarker"', scoped.group(1),
                      "deviceScopedTables is unchanged and still lists every deviceId table, labMarker included")

    def test_function_body_reads_a_balanced_body(self) -> None:
        """The scan's own parser: a fault here would hide or invent a table loop."""
        text = ("func a() { for t in Self.deviceScopedTables { run(t) } }\n"
                "func deleteAllData(deviceId: String) throws {\n"
                "    try q.write { db in for t in Self.strapScopedTables { run(t) } }\n"
                "}\n"
                "func b() { x(Self.deviceScopedTables) }\n")
        body = function_body(text, "deleteAllData")
        self.assertIsNotNone(body)
        self.assertIn("strapScopedTables", body)
        self.assertNotIn("deviceScopedTables", body)
        self.assertIsNone(function_body(text, "noSuchFunction"))


if __name__ == "__main__":
    unittest.main()
