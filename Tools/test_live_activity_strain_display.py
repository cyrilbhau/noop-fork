"""Exercise the real Live Activity payload without starting an app or touching defaults."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("swiftc"), "Swift compiler is unavailable")
class LiveActivityStrainDisplayTests(unittest.TestCase):
    def test_legacy_decode_and_selected_scale_round_trip(self):
        source = (ROOT / "StrandiOSShared/LiveActivityAttributes.swift").read_text()
        # Only the OS gate and framework protocol are substituted. ContentState, including its
        # synthesized Codable/Hashable implementations, is the production source verbatim.
        self.assertTrue(source.startswith("#if os(iOS)\n"))
        source = source.replace("#if os(iOS)", "#if true", 1).replace(
            "import ActivityKit",
            "public protocol ActivityAttributes { associatedtype ContentState: Codable & Hashable }",
            1,
        )
        checks = r'''
import Foundation

typealias State = NOOPActivityAttributes.ContentState
let decoder = JSONDecoder()
func decode(_ json: String) throws -> State {
    try decoder.decode(State.self, from: Data(json.utf8))
}

// Payloads from before both optional additions still decode, with no invented Strain.
let original = try decode(#"{"bpm":58,"recovery":72,"bonded":true}"#)
precondition(original.effort == nil && original.zone == nil && original.effortDisplay == nil)
precondition(original.shownEffort == nil)

// Existing activities keep their known native-axis number until the app supplies selected-scale text.
let legacy = try decode(#"{"bpm":58,"recovery":72,"bonded":true,"effort":60,"zone":2}"#)
precondition(legacy.effortDisplay == nil && legacy.shownEffort == "60")
let legacyZero = try decode(#"{"bonded":true,"effort":0}"#)
precondition(legacyZero.shownEffort == "0")
let explicitNull = try decode(#"{"bonded":true,"effort":null,"effortDisplay":null}"#)
precondition(explicitNull.shownEffort == nil)

let selected = State(bpm: 58, recovery: 72, bonded: true, effort: 60, zone: 2,
                     effortDisplay: "12.5")
let encoded = try JSONEncoder().encode(selected)
let roundTripped = try decoder.decode(State.self, from: encoded)
precondition(roundTripped == selected)
precondition(selected.shownEffort == "12.5" && selected.effort == 60)
var native = selected
native.effortDisplay = "60"
precondition(native.shownEffort == "60" && native != selected)
// Equality sees a scale-only change, so the controller's push policy can publish it.
precondition(Set([native, selected]).count == 2)
let zero = State(bpm: nil, recovery: nil, bonded: false, effort: 0, effortDisplay: "0.0")
precondition(zero.shownEffort == "0.0")
let missing = State(bpm: nil, recovery: nil, bonded: false)
precondition(missing.shownEffort == nil)
'''
        with tempfile.TemporaryDirectory(prefix="noop-live-activity-") as temporary:
            directory = Path(temporary)
            payload = directory / "LiveActivityAttributes.swift"
            payload.write_text(source)
            main = directory / "main.swift"
            main.write_text(checks)
            executable = directory / "check"
            compiled = subprocess.run(
                [shutil.which("swiftc"), "-module-cache-path", str(directory / "modules"),
                 str(payload), str(main), "-o", str(executable)],
                capture_output=True, text=True, timeout=60,
            )
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            result = subprocess.run([str(executable)], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
