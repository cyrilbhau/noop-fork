#!/usr/bin/env python3
"""Check commits for the owner's private values before they are pushed to the public repository.

Reads the owner's private profile (an ignored file under ``PersonalData/``) for its distinctive
numbers (decimals and comma-grouped thousands), and an optional ignored list of private words, and searches every line
ADDED by the given commit range for them. It prints counts and, for a hit, the line with the value
masked as ``<N>``; it never prints a private value.

Usage, from the repository root:

    python3 -I Tools/personal/privacy_scan.py <base>..<head> [<base>..<head> ...]
    python3 -I Tools/personal/privacy_scan.py --profile /path/to/OWNER-PROFILE.md origin/x..x

Exit status: 0 when nothing matched, 1 when something matched, 2 when the profile cannot be read.
A match is not automatically a leak (a synthetic fixture can coincide with a real number); read the
masked context and decide. Run it before every push.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

DEFAULT_PROFILE = Path("PersonalData/superapp/OWNER-PROFILE.md")

# Private words (one per line) live in an ignored file beside the profile, because the list itself
# would disclose private details if it were tracked.
DEFAULT_WORDS = Path("PersonalData/superapp/private-words.txt")


def profile_tokens(text: str) -> set[str]:
    decimals = set(re.findall(r"\b\d{2,3}\.\d{1,2}\b", text))
    grouped = set(re.findall(r"\b\d,\d{3}\b", text))
    return {n for n in decimals | grouped if not re.fullmatch(r"\d+\.0", n)}


def added_lines(rng: str) -> list[str]:
    out = subprocess.run(["git", "log", "-p", "--no-color", "--format=%B", rng],
                         capture_output=True, text=True, errors="replace", check=True).stdout
    lines = []
    for line in out.splitlines():
        if line.startswith("+") and not line.startswith("+++"):
            lines.append(line[1:])
        elif not line.startswith(("-", " ", "@@", "diff ", "index ", "new file", "deleted file")):
            lines.append(line)  # commit message bodies
    return lines


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("ranges", nargs="+", help="git ranges such as origin/branch..branch")
    ap.add_argument("--profile", type=Path, default=DEFAULT_PROFILE)
    ap.add_argument("--words", type=Path, default=DEFAULT_WORDS,
                    help="ignored file with one private word or phrase per line (optional)")
    args = ap.parse_args()
    try:
        tokens = profile_tokens(args.profile.read_text())
    except OSError as error:
        print(f"cannot read the private profile at {args.profile}: {error}", file=sys.stderr)
        return 2
    try:
        private_words = [w.strip() for w in args.words.read_text().splitlines() if w.strip()]
    except OSError:
        private_words = []
        print(f"note: no private word list at {args.words}; checking numbers only", file=sys.stderr)
    found = False
    for rng in args.ranges:
        lines = added_lines(rng)
        text = "\n".join(lines)
        hits = [n for n in tokens if re.search(r"(?<![\d.])" + re.escape(n) + r"(?![\d])", text)]
        words = [w for w in private_words if re.search(re.escape(w), text, re.I)]
        print(f"{rng}: {len(lines)} lines, profile numbers matched: {len(hits)}, words matched: {len(words)}")
        for n in hits:
            pattern = re.compile(r"(?<![\d.])" + re.escape(n) + r"(?![\d])")
            for line in [l for l in lines if pattern.search(l)][:3]:
                print("    " + pattern.sub("<N>", line.strip())[:160])
        for w in words:
            for line in [l for l in lines if re.search(re.escape(w), l, re.I)][:3]:
                print(f"    [word] {line.strip()[:160]}")
        found = found or bool(hits or words)
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
