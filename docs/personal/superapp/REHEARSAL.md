# Private real-data rehearsal

Procedure for the owner and Verifier, before device acceptance. **Not an execution record.** Nothing
here has been run against an owner's backup. Run from an isolated verifier worktree after arranging
exclusive app-build time with the integrator. Never restore over the working app, use a physical
phone, connect a strap or reuse another session's simulator.

The written procedure is tracked; the input copy, extracted files, logs, hashes, exports, notes and
screenshots are not. Keep those under this worktree's ignored `PersonalData/`. Simulator containers
necessarily hold another private copy until the dedicated device is deleted. Do not paste private
output into an agent conversation or commit it. A `.noopbak` is an unencrypted ZIP, not anonymized.

Sources: [ownership §12.10](specs/labbook-ownership.md#1210-real-data-rehearsal-before-any-device-install),
[stage specifications](README.md), [acceptance checklist](ACCEPTANCE.md),
`Strand/Data/DataBackup.swift`, `BackupSync.swift`, `Strand/Collect/StorePaths.swift`,
`StrandiOS/App/StrandiOSApp.swift`, and `Tools/personal/`.

## 1. Create the private run directory and input copy

Use a local bash session, without shell tracing. The owner supplies a fresh, already exported
**copy** of an Apple NOOP `.noopbak`. Do not select a live SQLite database, Android Room archive or
anything in the working app's container. These commands only copy the selected archive; they never
move it or change its permissions.

```bash
cd /absolute/path/to/the/isolated/verifier/worktree
set -euo pipefail
umask 077
rehearsal_repo=$(git rev-parse --show-toplevel)
mkdir -p "$rehearsal_repo/PersonalData/superapp/rehearsal"
rehearsal_root=$(mktemp -d "$rehearsal_repo/PersonalData/superapp/rehearsal/run.XXXXXX")
export rehearsal_root
git check-ignore -q -- "$rehearsal_root/input.noopbak"
read -r -p 'Path to the owner-supplied backup copy: ' rehearsal_input
test -f "$rehearsal_input"
cp -p "$rehearsal_input" "$rehearsal_root/input.noopbak"
chmod 400 "$rehearsal_root/input.noopbak"
shasum -a 256 "$rehearsal_root/input.noopbak" > "$rehearsal_root/input.sha256"
git rev-parse HEAD > "$rehearsal_root/source-commit.txt"
df -h "$rehearsal_root" > "$rehearsal_root/free-space.txt"
```

Run blocks sequentially; stop on any failed command. Keep several times the uncompressed database
size free for the archive, extraction, independent copies, simulator store and restore sidecar.
Current normal restore ceiling is 2,147,483,648 uncompressed SQLite bytes; compressed size does not
predict it. An oversize archive needs a separately reviewed owner decision and sufficient space,
not a silent limit bypass in this procedure.

## 2. Extract only known entries; preserve an untouched comparison

Current export entries are `noop-backup.sqlite`, optional `settings.json`, and `manifest.json`.
Extract the exact DB/settings names rather than using `unzip` with arbitrary archive paths. The
normal app importer remains responsible for validating/applying the archive in the simulator.

```bash
python3 - "$rehearsal_root" <<'PY'
from pathlib import Path
import shutil, sys, zipfile
root = Path(sys.argv[1])
with zipfile.ZipFile(root / "input.noopbak") as archive:
    for name, limit in [("noop-backup.sqlite", 2_147_483_648), ("settings.json", 1_048_576)]:
        entries = [item for item in archive.infolist() if item.filename == name]
        if not entries and name == "settings.json":
            continue
        if len(entries) != 1 or entries[0].file_size > limit:
            raise SystemExit("Missing, duplicate or oversize expected entry; stop and review locally")
        destination = root / ("before.sqlite" if name.endswith(".sqlite") else name)
        count = 0
        with archive.open(entries[0]) as source, destination.open("xb") as target:
            while chunk := source.read(1024 * 1024):
                count += len(chunk)
                if count > limit:
                    raise SystemExit("Uncompressed entry exceeds the rehearsal limit")
                target.write(chunk)
        if count != entries[0].file_size:
            raise SystemExit("Truncated entry")
shutil.copy2(root / "before.sqlite", root / "work.sqlite")
(root / "before.sqlite").chmod(0o400)
PY
sqlite3 -readonly "$rehearsal_root/before.sqlite" 'PRAGMA quick_check;' > "$rehearsal_root/integrity.txt"
grep -qx 'ok' "$rehearsal_root/integrity.txt"
test "$(sqlite3 -readonly "$rehearsal_root/before.sqlite" "SELECT count(*) FROM sqlite_master WHERE name='grdb_migrations';")" = 1
```

A missing settings entry is a valid legacy archive; it restores DB-only. A malformed settings entry
may apply fewer whitelisted keys rather than fail the whole restore. Record that distinction. The
extraction limit above is a conservative procedure limit, not a replacement for the app's decoder.

## 3. Run ownership repair against work.sqlite only

The existing opt-in test opens the explicit path, runs repair twice, checks reading preservation
and copy/conflict listing, and rehearses each registered strap's deletion on further temporary
copies beside it. It checkpoints before copying and cleans those temporary copies. With the
environment variable absent, its real-data test **skips**; a skip is not rehearsal evidence.

```bash
NOOP_REHEARSAL_DB="$rehearsal_root/work.sqlite" \
  swift test --package-path Packages/WhoopStore \
  --scratch-path "$rehearsal_root/store-test-build" \
  --filter LabBookOwnershipRehearsalTests \
  > "$rehearsal_root/ownership-tests.log" 2>&1
```

Require the real-data test to run and pass, not just the synthetic companion. Inspect its log
locally: rows, distinct IDs, unregistered IDs, copies, conflicts, qualitative rows and repair counts.
Expected: every original `labMarker` row unchanged; second repair inserts/updates nothing; only true
copies are collapsed in listing; deleting any strap on a temporary copy preserves every reading.
Repair may add/correct derived `lab-book` series cells under A11/A13/A14/A19.

Independently compare the ordered table content, without printing values to the terminal:

```bash
for rehearsal_copy in before work; do
  sqlite3 -readonly "$rehearsal_root/$rehearsal_copy.sqlite" \
    '.mode quote' 'SELECT * FROM labMarker ORDER BY id;' \
    | shasum -a 256 > "$rehearsal_root/$rehearsal_copy.labMarker.sha256"
done
cmp "$rehearsal_root/before.labMarker.sha256" "$rehearsal_root/work.labMarker.sha256"
```

A failure stops rollout. Keep the full failure log private: an assertion may include row values,
even though the normal test report prints counts only. Do not repair the input archive by hand.

## 4. Prepare an app and a new simulator

`Tools/personal/ios.sh check` checks prerequisites; `build` uses the fixed
`build/personal/fork-derived` and requires local signing configuration. `gate.sh` uses that same
build tree. Neither installs anything, and neither restores a backup. Do not run them concurrently
with the integrator. `ios.sh baseline` builds a pinned upstream commit, **not** the super-app
flag-off comparison commit `85fc5329`.

Prefer the integrator's matching unsigned **simulator** `NOOP.app`. If a fresh build is needed, the
Verifier uses this isolated worktree and its own DerivedData (commands for the Verifier, not a task
for a read-only review lane):

```bash
xcodegen generate > "$rehearsal_root/xcodegen.log" 2>&1
xcodebuild -project Strand.xcodeproj -scheme NOOPiOS -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$rehearsal_repo/build/rehearsal-derived" \
  -onlyUsePackageVersionsFromResolvedFile \
  BUNDLE_ID_PREFIX=org.noop.rehearsal CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  build > "$rehearsal_root/ios-build.log" 2>&1
rehearsal_app="$rehearsal_repo/build/rehearsal-derived/Build/Products/Debug-iphonesimulator/NOOP.app"
```

When using an existing artifact instead, set `rehearsal_app` to its absolute path and record its
source commit/build privately. Read its bundle ID rather than guessing the owner's identifier.
Select an **available iOS 26-or-newer runtime and compatible iPhone type** from the following lists;
enter the displayed identifiers at the prompts. Do not install a runtime as part of this procedure.

```bash
test -d "$rehearsal_app"
rehearsal_bundle=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$rehearsal_app/Info.plist")
xcrun simctl list runtimes available
xcrun simctl list devicetypes
read -r -p 'Available iOS runtime identifier: ' rehearsal_runtime
read -r -p 'Compatible iPhone device-type identifier: ' rehearsal_type
xcrun simctl create "NOOP Codex Verify Rehearsal $(date +%Y%m%d-%H%M%S)" \
  "$rehearsal_type" "$rehearsal_runtime" > "$rehearsal_root/simulator-udid.txt"
rehearsal_udid=$(cat "$rehearsal_root/simulator-udid.txt")
xcrun simctl boot "$rehearsal_udid"
xcrun simctl bootstatus "$rehearsal_udid" -b
open -a Simulator --args -CurrentDeviceUDID "$rehearsal_udid"
xcrun simctl install "$rehearsal_udid" "$rehearsal_app"
rehearsal_container=$(xcrun simctl get_app_container "$rehearsal_udid" "$rehearsal_bundle" data)
mkdir -p "$rehearsal_container/Documents"
cp "$rehearsal_root/input.noopbak" "$rehearsal_container/Documents/rehearsal.noopbak"
xcrun simctl launch "$rehearsal_udid" "$rehearsal_bundle" > "$rehearsal_root/first-launch.log" 2>&1
```

Every simctl command names this UDID; never substitute `booted`, a physical-device tool or a
wildcard. The simulator holds no signed-in cloud account, provider credential or external backup
folder. Do not enable the existing AI provider, scheduled brief, Shortcut health-file export or
Backup & Sync automatic folder writes. Do not pair hardware or grant new Health permissions.

## 5. Import through the actual restore path

1. In this simulator only, complete first-run terms/onboarding as needed, without pairing hardware.
   Open Settings → **Backup & restore** → **Import…**. In the document picker, browse On My iPhone →
   NOOP and choose `rehearsal.noopbak`. The supplied copy is already in the app's Documents folder.
2. Wait for **Backup imported**, whose message asks to quit and reopen. If the import reports a
   problem or oversize warning, stop and inspect privately. Do not manually copy SQLite over an
   open app to bypass the error.
3. Terminate and relaunch this app on this device:

```bash
xcrun simctl terminate "$rehearsal_udid" "$rehearsal_bundle"
xcrun simctl launch "$rehearsal_udid" "$rehearsal_bundle" > "$rehearsal_root/restored-launch.log" 2>&1
```

The actual DataBackup path validates ZIP/SQLite origin/integrity, keeps the previous simulator DB
as a sidecar, swaps with rollback checks, then applies whitelisted settings. Restore does not
replace excluded per-install flags, credentials or folder bookmarks. A fresh simulator is therefore
important. Repository's first store open runs the always-on ownership repair. Its log line contains
counts only and appears only if cells changed; absence of a line is not proof it ran incorrectly.

There is **no** `--restore-backup` or `--database-path` app launch argument. `--demo-screen <name>`
selects synthetic isolated fixtures, `--demo-seed` can insert synthetic history/skip gates,
`--demo-hour` pins Today and `--demo-sync` simulates sync. Never use them on this restored copy;
they cannot validate the owner's data. Use a different clean simulator for design/demo checks.

## 6. Compare each stage, one toggle at a time

Keep all data-bearing evidence in the private run folder. Use the numbered [acceptance steps](ACCEPTANCE.md)
on this simulator first. Synthetic/adversarial edits are allowed only here and are recorded as such.
Never send the real packet to a provider merely to test rendering.

| Order | Compare and require |
|---|---|
| Ownership, all new switches off | Counts/hash above; Lab Book includes readings from earlier/unregistered IDs, collapses copies only, keeps conflicts/qualitative rows and unbacked traces. Compare Today/Health/widgets/Settings with a separate baseline run at `85fc5329` on another disposable device if baseline equivalence is being claimed. Build that baseline separately; never replace this simulator's app mid-comparison. |
| Scorecard | Actual phase/rules and dated records vs original reports; same current weight/waist in Today/Settings/Scorecard, coherent past-day selection, R44 same-week scan precedence. Missing history stays missing. Only deliberate entries/edits and the specified profile mirror may change stored inputs; scorecard does not write a new recovery/strain/sleep score. |
| Coach packet | Selected ranges/sections vs app screens; raw identifier scan blocks unsafe text; preview equals copy/share/Shortcuts snapshot. No identifiers, paths or accidental private text. No outbound network call. |
| Intake, Quick-add only | Exact entry list and stored totals through add/edit/delete/backdate/rebank; restored total without list is preserved until explicitly converted. Resolver/card/widget/scorecard/packet agree; floor edits propagate both ways. Missing totals are absent, not zero. No dietary Health authorization. |
| Laboratory units, then Body record | Reports' entered units and canonical conversions; original notes/date and “Entered as”; scans/benchmarks use ordinary Lab Book rows. Two-scan changes match hand calculations. Missing/overflowing components stay unavailable. A scan does not replace a same-week manual weigh-in in the resolver. |
| Events, then packet v2 | Enter/edit/end/delete on the copy; chart/scorecard values unchanged. Private labels/notes/counts absent from chart captions, widgets and notifications; private spans absent from Timeline. Packet private switch off excludes them; on includes only the requested visible range. Raw identifier-containing text blocks even if rendering would truncate it. Intake-only packets have no empty-measurement claim. |
| Niggle log | Owner rules, severity/order, inclusive onset day and calendar rollover; update/resolve/reopen/pause/resume preserve history and do not alter workout rows or generate medical advice. |
| Recovery context | RHR/HRV week means, night counts, gaps and change labels vs a private hand check. Existing scores and scorecard verdict are unchanged. |
| Timeline | Phase, scan, non-private diet-break/deload dates and checkpoints vs source pages. Exactly one Today, projection from the same scorecard evaluation, no private/niggle text, refused waypoints leave stored checkpoints unchanged. |
| All switches off again | No stage output/notifications/Health reads; legacy readers resume. New stored lists remain durable and appear in full backups. Supplement exclusions follow the list even off; scan/benchmark-only values stay out of in-app Coach. Static widget/action entries can remain, without data. |

For a private packet byte check, choose its actual 7/14/28-day range in the sheet, copy it, then:

```bash
xcrun simctl pbpaste "$rehearsal_udid" > "$rehearsal_root/packet.txt"
read -r -p 'Range days selected in the sheet (7, 14 or 28): ' rehearsal_days
python3 - "$rehearsal_root/packet.txt" "$rehearsal_days" > "$rehearsal_root/packet-size.txt" <<'PY'
from pathlib import Path
import sys
days = int(sys.argv[2])
assert days in (7, 14, 28)
size = len(Path(sys.argv[1]).read_bytes())
budget = 8000 + 290 * days + 2000
assert 0 < size <= budget, (size, budget)
print("bytes", size, "budget", budget)
PY
```

The app assembler already performs the raw/rendered privacy scan with the restored registry's known
identifiers; a size pass alone is not a privacy pass. Read the packet privately against actual IDs
and screens; do not paste the identifiers into this document or use a demo's empty identifier list.

## 7. Capture a consistent post-run store and test round-trip

First terminate the app as in step 5 (if already terminated, confirm that state locally). Obtain
the current data container again. StorePaths on iOS is exactly
`Library/Application Support/OpenWhoop/whoop.sqlite`; preserve WAL content using SQLite's backup
API rather than copying a possibly uncheckpointed main file alone.

```bash
rehearsal_container=$(xcrun simctl get_app_container "$rehearsal_udid" "$rehearsal_bundle" data)
python3 - "$rehearsal_container" "$rehearsal_root" <<'PY'
from pathlib import Path
from urllib.parse import quote
import sqlite3, sys
source = Path(sys.argv[1]) / "Library/Application Support/OpenWhoop/whoop.sqlite"
destination = Path(sys.argv[2]) / "after.sqlite"
assert source.is_file() and not destination.exists()
with sqlite3.connect("file:" + quote(str(source), safe="/") + "?mode=ro", uri=True) as src:
    with sqlite3.connect(destination) as dst:
        src.backup(dst)
PY
```

Compare original Lab Book rows with the allowed deliberate changes, not raw whole-file hashes:
migrations, derived repair cells, read timestamps and profile mirrors may legitimately differ.
Record each expected difference privately and investigate every unexplained row loss/change.

Relaunch and use **Export…** to create a fresh `.noopbak` via the normal app checkpoint/validation.
If testing Backup & Sync instead, choose only NOOP's **internal Files folder** on this simulator;
leave auto-backup off, use **Back up now**, and never select a cloud-synced or working-phone folder.
FolderBackup calls the same `DataBackup.writeBackup(checkpoint:to:)`; files need the same checks.
Copy that exported archive from the simulator into this private run folder, then repeat steps 4–6
on a second newly created simulator. Check rows plus whitelisted profile/units/phases/targets/events/
niggles/checkpoints; new flags and packet-private preference must still default off. Labels/notes
are cleartext in settings.json by specification. A DB-only legacy input cannot restore absent settings.

## 8. Record outcome and remove only dedicated simulator copies

Save pass/fail/not-run, exact source/artifact/runtime, ownership test counts, expected differences,
private comparisons and remaining blockers in this run folder. No real-data result is committed;
a public handoff can say only which checks ran and their non-sensitive outcome. Unexplained data
loss, privacy leak or a required check not run blocks phone rollout.

After reviewing/saving private evidence, shut down and delete **only each UDID created by this run**:

```bash
xcrun simctl shutdown "$rehearsal_udid"
xcrun simctl delete "$rehearsal_udid"
shasum -a 256 -c "$rehearsal_root/input.sha256" > "$rehearsal_root/input-unchanged.txt"
git status --short > "$rehearsal_root/tracked-status.txt"
```

Repeat cleanup with the second simulator's own recorded UDID, not `all`. Keep/delete the private
run directory only at the owner's choice. This procedure creates no checkpoint tag, changes no
phone installation and records no owner acceptance; those follow [ACCEPTANCE.md](ACCEPTANCE.md).
