# WHOOP 4.0 device validation

No hardware results are available yet. Use the personal app identity from [INSTALL.md](INSTALL.md).
Keep the unchanged engine as the reference until collection passes. The target is a dependable
replacement by **12 November 2026**, before the stated membership end on **19 November 2026**;
these dates are planning targets, not evidence that the app is ready.

**Steps are a release gate.** At the pinned baseline, WHOOP 4.0 steps are estimated from sparse
motion and calibrated against phone counts; they are not a decoded band pedometer count. A phone-free
walk therefore tests the estimate's fitness for this requirement, and may establish that this band
cannot satisfy it. WHOOP-app agreement or an attractive dashboard does not prove accuracy.

## Before testing

- Keep firmware, wrist placement, strap tightness, and app version constant. Charge the band and phone.
- Record privately: personal app version/commit, iPhone/iOS, band model/firmware, selected data source,
  time zone, and whether Health read/write permissions are enabled. Never include serial numbers,
  Bluetooth identifiers, credentials, raw health records, or a WHOOP archive in Git or build logs.
- Open **Settings → Advanced → Test Centre** and enable only the relevant diagnostic domain (**Steps**,
  **Sleep & Rest**, **HRV**, or **Connection & Sync**). Inspect Apple Health write status separately. Do not enable experimental strap writes.
  The existing **Steps** readout includes calibration state. Phone calibration needs at least three
  usable paired days; until then report “uncalibrated” rather than judging the walk against a final model.
- Let an initial sync/offload finish in the foreground and note the displayed sync time and the diagnostic offload/write outcome.
  A sync timestamp or connected icon is not proof that history has reached storage or scoring.
- Do not force-quit the app during ordinary background tests. iOS can prevent relaunch after a
  deliberate force-quit. Test an ordinary locked phone with the installed app outside Xcode first.

## Agreed step tolerances and proposed remaining checks

The owner accepted the walking and sedentary thresholds below on **21 October 2026**. They are
practical acceptance criteria, not measurements or clinical validation. Sleep timing and workout
gap thresholds remain proposals; record those results as pending agreement until confirmed.

| Check | Proposed starting criterion |
|---|---|
| Phone-free steps — agreed | Two separate manually counted 500–1,000-step walks; absolute error at most 10% on each after calibration. Report signed and absolute error, not a daily total alone. |
| Sedentary false steps — agreed | At most 20 added steps in a 30-minute seated period; log ordinary hand/arm activities privately so false counts are interpretable. |
| Sleep timing | At least three nights with usable overnight HR/accepted HRV input; main sleep start/end each within 30 minutes of a written sleep diary, allowing that remembered sleep onset is uncertain. |
| Workout continuity | One 30-minute or longer workout retains its full intended duration after locking the phone; no unexplained session termination or stored-data gap longer than 5 minutes. |
| Reconnect/backfill | After 30–60 minutes away from the phone, reconnect completes and stored history covers the interval after the app reports offload finished; judge latency after observing the first successful baseline rather than inventing a deadline. |
| Apple Health | Intended samples appear after a completed sync, with the correct source/type/unit/time; an immediate repeat sync adds no duplicate logical samples from this app. |
| Widgets | After a completed sync and reopening/locking the phone, the correct snapshot eventually appears, shows freshness, and never presents old values as continuously live. iOS sets the refresh schedule; no fixed refresh-rate guarantee. |

Sleep stages, recovery, strain, and SpO₂ cannot be validated clinically by this small procedure.
A plausible score is not proof of accuracy. Report unavailable or rejected inputs explicitly.

## Short test sequence

1. **Phone-free walk.** After sync completes, note the app's step total/source and calibration state.
   Leave the phone behind. Manually count 500–1,000 normal walking steps using a tally counter or
   written batches. Return, finish sync/offload, and note the new total. Subtract the starting total;
   report `100 × (app delta − counted steps) / counted steps`. Repeat on another route/session.
   Do not include imported iPhone steps from carrying the phone to and from the test area.
   Confirm that the displayed value is this day's `steps_est`, not a phone total. At this baseline,
   any positive imported phone-step reference for a day suppresses the estimate for that day;
   a partial-phone day can therefore make this test unevaluable. Report that condition explicitly.
   Keep the calibration days and all health data intact; do not delete records to force an estimate.
2. **False steps.** Sync before and after a 30-minute seated period. Note whether tapping, eating,
   typing, or arm movement caused increments. A zero value with no stored motion is missing data,
   not evidence of perfect false-positive rejection.
3. **Overnight collection.** For at least three nights, keep the iPhone near the band, lock it, and
   leave the app normally backgrounded. Write bed/wake estimates privately. Each morning allow
   foreground offload to complete; inspect the sleep window plus overnight HR/HRV quality. Record
   which layer failed if sleep is missing. Separate continuous locked-phone collection from a morning
   backfill that merely fills the same night later.
4. **Workout.** Start a known 30-minute workout, lock the phone, and record the intended stop time.
   Verify stored start/end, HR coverage and the app's independently calculated cardiovascular strain.
   A Hevy CSV import is a separate test; imported sets/reps/weight are not sensor measurements or
   automatically validated muscular strain.
5. **Leave the phone behind.** Wear the band away for 30–60 minutes. Return with the app backgrounded,
   observe whether it reconnects, then open it if needed. Record automatic versus foreground-assisted
   success separately. Verify backfilled timestamps, not just an open connection. Repeat once with
   a normally locked phone and once after an ordinary app relaunch; do not use a band reset.
6. **Apple Health.** Initial collection testing keeps all write types off. Existing writeback
   reconciles this app's own samples through deletion and replacement; obtain the owner's explicit
   approval for that behavior before enabling one intended write type at a time. No cleanup is
   authorized by this test plan. After offload/scoring finishes, open
   Health → Browse → that metric → Show All Data and inspect sample details/source, units and dates.
   Check HRV is **SDNN**, not RMSSD renamed; skin temperature must not appear as generic body
   temperature. Repeat sync and inspect for duplicate records from the personal app. Check steps and
   workouts against other writers separately: app-local deduplication does not deduplicate another
   app's contributions. Keep existing Health records; do not delete them to make the test pass.
7. **Widgets and backup.** Add a NOOP Home Screen widget and a Lock Screen widget. Complete a sync,
   lock/reopen the phone, and compare snapshot values and freshness to the app. Missing widget data
   with a working app points first to App Group signing/publication. Export a `.noopbak` from
   **Settings → Advanced → Backup & restore → Export** to a private location. A recoverable backup
   is unverified until restored into a separate disposable identity/container and its historical
   counts/date ranges checked; CSV export is not a substitute for the full restore test.

If the 4.0 phone-free step gate fails, the smallest alternative is a separately attributed phone or
supported wearable pedometer source, with the carrying/wearing requirement stated. Do not silently
substitute phone steps or tune a coefficient against the same walk being evaluated.

## Locate the failing layer

Use the existing Test Centre and diagnostics surfaces before proposing a protocol or algorithm change.
Counters and error categories are sufficient for the first triage; health measurements stay private.

| Layer | Evidence to inspect privately | What absence means |
|---|---|---|
| Collection | Connection/handshake transitions, offload start/completion and chunk/page progress; band/firmware identification | No accepted traffic or incomplete offload: collection is unresolved, regardless of a live HR number. |
| Decode/store | Accepted/CRC-rejected packet counts, stream/sample counts and stored date coverage; Settings' read-only raw sensor export only when needed | Traffic exists but expected decoded rows or time range do not: isolate decoder/store, not the UI. |
| Calculation | Presence of motion and accepted RR inputs, calibration state, quality/rejection reasons, completion of scoring after offload | Stored HR alone does not establish motion, accepted HRV, or sleep/recovery inputs. |
| Display/export | Metric source/time/quality in the app, completed HealthKit write status, source sample details, widget snapshot time and App Group capability | A computed/stored metric with an absent display/Health record/widget is a presentation or integration failure. |

The app already offers **Settings → Diagnostics**, **Test Centre** reports, and a read-only
**Export raw sensor data (CSV)**. Exporting a full log/report may include physiological details despite
redaction. Review it locally before sharing; keep only firmware/app versions, counters, error categories
and relative timing in a shareable issue. Never upload raw CSV, `.noopbak`, a database, or the WHOOP
archive automatically. Store private evidence outside the source checkout in protected storage;
ordinary plaintext archives/backups are not encrypted merely because they have a custom extension.

A compact private run note can use these fields: run date/time zone; baseline/fork commit; firmware;
scenario; permissions/source; observed collection/decode/store/calculation/display state; expected
versus observed counts/times; proposed tolerance version; pass/fail/**pending agreement**; next action.
Do not create a filled-in evidence file in this repository.
