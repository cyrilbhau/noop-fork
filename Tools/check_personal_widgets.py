#!/usr/bin/env python3
"""Compile and run the personal widget's pure Swift/XCTest cases without Apple SDKs.

Usage: python3 Tools/check_personal_widgets.py --swiftc /path/to/swiftc
This checks shared data/presentation behavior, not SwiftUI/WidgetKit app compilation.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--swiftc", default=shutil.which("swiftc"), help="Swift compiler (default: PATH)")
    args = parser.parse_args()
    if not args.swiftc:
        parser.error("Swift is required; activate the repository's supported Swift toolchain first")

    root = Path(__file__).resolve().parents[1]
    test = root / "StrandTests/PersonalWidgetMetricsTests.swift"
    names = re.findall(r"func (test\w+)\(", test.read_text(encoding="utf-8"))
    if not names or len(names) != len(set(names)):
        print("Personal widget XCTest discovery is empty or ambiguous", file=sys.stderr)
        return 2

    sources = [
        root / "StrandiOSShared/HrTrace.swift",
        root / "StrandiOSShared/StressTrace.swift",
        root / "StrandiOSShared/PersonalWidgetMetrics.swift",
        root / "StrandiOSShared/WidgetSnapshot.swift",
        test,
    ]
    with tempfile.TemporaryDirectory(prefix="noop-personal-widgets-") as scratch:
        work = Path(scratch)
        driver = work / "main.swift"
        cases = ",\n".join(f'("{name}", PersonalWidgetMetricsTests.{name})' for name in names)
        driver.write_text("import XCTest\nXCTMain([testCase([\n" + cases + "\n])])\n", encoding="utf-8")
        executable = work / "personal-widget-checks"
        command = [
            args.swiftc,
            "-module-cache-path", str(work / "module-cache"),
            *map(str, sources), str(driver), "-o", str(executable),
        ]
        compiled = subprocess.run(command, cwd=root, check=False)
        if compiled.returncode:
            return compiled.returncode
        print(f"Running {len(names)} personal widget XCTest cases (no Apple SDK validation)", flush=True)
        return subprocess.run([str(executable)], cwd=root, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
