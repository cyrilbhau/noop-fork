# Owner acceptance on iPhone

Run after the private [rehearsal](REHEARSAL.md), design review and integrator checks. The owner
separately authorizes one installation after a fresh backup; this document does not authorize an
installation. All new switches start off. Enable and accept one part at a time, in the order below
([STATUS.md](STATUS.md)). Leave later parts off.

Use actual records and existing coach-agreed rules on the phone. Enter dates, units and values from
the original record; do not invent health history to exercise a branch. Empty-history, conflicting
rows, strap deletion, corrupt storage, permission failures and synthetic threshold cases belong in
the disposable simulator. Record each step as pass, fail or not run, with build, date and reason;
keep measurements, exports and screenshots private. A not-run check is not a pass.

## 0. Baseline and Lab Book ownership — always on

Sources: [ownership specification](specs/labbook-ownership.md) §§7, 12.10–12.11; A10–A15, A19.

1. Before installation, make a fresh backup. Privately note the existing Lab Book readings, Today
   values, Settings, Health rows, widget readings, reminders and in-app Coach behavior.
2. After the authorized installation, leave every new switch off. Open Lab Book. Every earlier
   reading must remain visible, including readings entered under an earlier or forgotten strap.
   Exact copies appear once; different readings at the same instant remain separate.
3. Open an existing reading. Its value, unit, time, note and reference text must match the original.
   Close without saving. Reopen the app: the reading remains unchanged.
4. Compare Today, existing Settings outside the new switch cards, Health, widgets and reminders with
   the notes. No new feature output or new Health permission prompt may appear. The intended
   difference is owner-wide Lab Book history and its repaired derived chart cells.
5. Confirm the rehearsal covered edit/delete of copies and conflicts, import twice, and strap
   delete/forget/re-add without loss. Do not delete a real strap or reading merely to repeat this
   check on the phone.

## 1. Weigh-in and scorecard

Sources: [stage 1](specs/stage-1.md) §§8–10, 12, 18; roadmap acceptance; R41, R44–R45.

1. Settings → **Scorecard**: enable the switch. Health gains its Scorecard row. Open it; if history
   is insufficient, expect an explicit missing-data reason rather than a fabricated value/verdict.
2. Open **Phase**. Enter the actual phase's name, kind, start date, target and agreed rate band.
   Open **Rules** and enter only the existing coach-agreed rules. Save; reopen both to check them.
3. Tap **Log weigh-in**. Enter a recorded weight in its displayed unit and original date/time.
   Enter the recorded waist or choose **Skip waist**. Save. History and Lab Book must show the
   entered reading; skipping waist must not create a zero.
4. Enter the owner's past readings needed for a known week. Compare the weekly point, verdict and
   each rule's explanation with the coach's conclusion. Missed weeks stay gaps. Insufficient
   history says why a rule cannot be judged. A non-falling trend has no invented target date.
5. Compare current weight/waist in Scorecard, Today and Settings. They must name the same resolved
   reading, source and day, allowing unit/display rounding. Reopen the weigh-in sheet: its offered
   current reading agrees. A source-history page may show another reading only as that source's.
6. If a correction is needed, edit the actual history row and verify every current surface updates
   without restarting. Keep the corrected record accurate. Check a past day: no later reading may
   appear as that day's value.
7. Add the Scorecard card in redesigned Today → Customize → Your cards. It opens Scorecard. A past
   day shows the specified past-day placeholder, not this week's live verdict.
8. If wanted, enable the weekly weigh-in reminder and choose weekday/time. Its generic notification
   contains no measurement. A week already weighed is not reminded. Switching the reminder off
   cancels it; denial must be explained without claiming it was scheduled.
9. Turn Scorecard off. Its Health row/card and reminder disappear; legacy weight behavior returns.
   Stored readings/rules remain. The profile mirror is not rolled back (R27). Re-enable only after
   the checks pass.

## 2. Coach packet

Sources: [stage 2](specs/stage-2.md) §§7–10, 12.8, 16; A17–A21, A25–A26.

1. Settings → **Coach packet**: enable it. Open Health → **Coach packet**, then open it from the
   Scorecard toolbar. Both use the same packet settings; there is no new Today packet card.
2. Choose each offered range. Toggle each section off and back on. The header, dates and listed
   sections follow the controls. Missing measurements are dashes; switched-off features say so.
   Compare measured rows, units and source labels with the corresponding app screens.
3. Copy the preview; paste into a private local text destination. The copied text must equal the
   preview. Changing a control or regenerating different text clears the old copied confirmation.
4. Leave the clipboard untouched for ten minutes. The packet expires. If a second signed-in Apple
   device is available, confirm the copy is not offered there. Otherwise mark the cross-device
   check not run; do not claim it passed.
5. Open **Share**. Its own system **Copy** action is absent. Cancel the sheet; canceling does not
   regenerate or change the preview. Sharing to another destination is an explicit owner choice.
6. In Shortcuts, add **Get Coach Packet**. Run unlocked and compare with the preview made in the same
   minute; only `generated:` may differ. Run locked: authentication is required. The action must
   not speak or show the health text as a Siri dialog.
7. Inspect the export privately: no strap/device identifier, serial, account name or file path.
   An identifier-scan warning must block copy, share and Shortcuts, not offer an unsafe fallback.
8. With the agreed packet-reading instructions in place, complete one real coaching exchange by
   explicitly pasting the packet. Every section must be read correctly without retyping numbers.
   The separate in-app Coach must retain its existing behavior.
9. Turn Coach packet off, including while a preview is open. Copy/share must stop; Shortcuts must
   fail with the switched-off explanation. Re-enable only after acceptance.

## 3. Intake — quick-add path

Sources: [stage 3](specs/stage-3.md) §§7, 9–10, 12; R45; A25–A26.

1. Settings → **Intake**: enable it, choose **Quick-add**, and enter the existing agreed protein
   floor. Whole grams only; a fractional floor is refused. This is the same floor as Scorecard
   Rules. Keep Apple Health dietary access unenabled; that path needs separate owner approval.
2. Enter any agreed calorie range, hard floor and cutoff; leave unwanted optional settings unset.
   Reopen settings to confirm them. No target should be inferred from a missing field.
3. Health → **Intake** → **Add food**: enter a known meal's protein/calories and, optionally, a
   label. Save. The daily total equals the logged amounts. Edit or delete an entry only to correct
   the actual meal; totals, Today card and packet must follow without restarting.
4. Add the Protein card in redesigned Today → Customize → Your cards and add the Protein widget.
   Card, Intake screen, widget and fresh packet agree on protein/floor, allowing specified rounding.
   The widget shows a read/entry time, never a value without one. No food label, calorie amount or
   supplement name appears there. An old-day widget cannot present yesterday as today.
5. Open a previous logged day. Its total stays on that day; no meal is counted twice across sources.
   If a restored total has no entry list, it is labeled as restored, not silently erased.
6. For three consecutive days, privately compare the total with the actual meal log (or food app
   used as a manual reference). This accepts quick-add only; it does not validate a Health import.
7. Change the floor through Intake, then read Scorecard Rules and protein displays; change it back
   through Rules. Every reader uses the same whole-gram setting and updates without restarting.
8. If used, list the existing Journal supplement questions and tick one recorded occurrence. It
   uses that Journal entry, not a second log. Supplement names stay out of widgets/packet; listed
   questions stay excluded from in-app Coach patterns even when Intake is later off.
9. If wanted, enable the cutoff reminder. Its text is generic; near a wind-down reminder it is
   passive/silent. Turn Intake off: its card, Health row, widget data and reminder disappear. Stored
   entries remain. Re-enable after acceptance.

## 4. Laboratory units, then Body record

Sources: [stage 4](specs/stage-4.md) §§7–10, 12; A2–A3, A16, A22.

1. Settings → **Body record**: enable **Laboratory units** first. Open Lab Book → add marker. Enter
   an actual blood result in the unit printed on its report. Check the conversion preview, save,
   and reopen: canonical stored value and **Entered as** line agree with that report.
2. Enter the real blood panel in one sitting using **Save and add another**. Each successful save
   confirms the marker; date is retained, fields reset as specified, and no earlier result changes.
   Canceling the next entry adds nothing. Turning Laboratory units off restores the legacy editor.
3. Enable **Body record**. Health → **Body record** → **Add a scan**: enter an actual report's date,
   total mass and other printed fields, preserving missing fields as missing. No photo import,
   diagnosis, reference band or new score is promised.
4. Compare the scan with Lab Book. Total mass uses the ordinary weight marker. Where a manual
   weigh-in exists in the same week it outranks a `body-scan` reading for current/weekly weight;
   otherwise the scan can supply weight. All current readers must agree.
5. After a second actual scan exists, select both in **Compare scans**. Hand-check each displayed
   later-minus-earlier delta and percentage using displayed values. Missing components yield
   **Not available**, never zero/infinity. Imported source rows remain labeled as their source.
6. Add an actual benchmark from its fixed list or a named custom benchmark. Save and reopen its
   history. It is a record, without a favorable/unfavorable judgment; it does not alter a score.
7. Turn both switches off. Their new Health/editor surfaces disappear; rows and annotations remain
   in Lab Book and full backup. Scan/benchmark-only markers stay out of the in-app Coach roll-up.

## 5. Events and packet v2

Sources: [stage 5](specs/stage-5.md) §§7, 9–10, 12; [packet v2](specs/stage-2.md#712-grammar-for-later-sections-and-packet-v2); A20, A23–A24.

1. Settings → **Events**: enable **Personal events**. Open Health → **Events**. Add an actual event
   with its kind, recorded start, one-day/end/ongoing length and optional note. Custom requires a
   name; end-before-start cannot save. Reopen, correct or end an actual event and check the list.
2. Inspect an adopting chart and Scorecard in its date window. Event marks add context only; values,
   axes, weekly points, verdict and scores must not change. Private events have no name, note or
   revealing count outside Events. Widgets and notifications contain no event data.
3. Make an event private. With **Include private events in the coach packet** off, inspect the fresh
   packet: no private label/note or hidden-event count. The caption says private events are left
   out. A private diet break/deload is absent from the timeline, not merely renamed.
4. If private export is wanted, enable that separate Settings switch and regenerate. Only selected
   in-range visible events are included; the caption says private events are included. Turn it off
   again and regenerate: the text disappears. Copy/share/Shortcuts follow the scanned preview.
5. Check packet v2's Intake section against the app's daily totals: protein/calories are whole
   numbers with closed source labels, no food labels. An intake-only measured range must not say
   nothing was measured. Disable Intake/Events individually: their sections say switched off.
6. Keep the packet section switches off if those data should not leave. Any privacy-scan warning
   blocks export. If rescue **Copy stored text** is needed, it is explicit, local-only and expiring;
   it can contain the whole private list and is not an anonymous packet.
7. Turn Personal events off. Its Health row, chart marks and Scorecard context disappear. Stored
   events remain in the unencrypted full backup, including private notes; do not share that archive
   as an anonymous diagnostic. The in-app Coach gains no event input.

## 6. Niggle log, Recovery context, Timeline — separate switches

Sources: [stage 6](specs/stage-6.md) §§7–10, 12.8; A27.

1. Enable **Niggle log** in Settings; open its Health row. Record an actual complaint's location,
   onset, character, trend and weakness. Enter only the owner's existing triage rules, in their
   agreed order. The result names that rule/action, not a diagnosis or medical recommendation.
2. Check onset is day 1 and today is inclusive. Leave the screen/detail mounted through a calendar
   rollover or return on the next day: the count updates. Add a recorded update, resolve/reopen
   only as accurate, and check the current trend and history. Paused exercises record the owner's
   reason; pause/resume does not rewrite the workout log.
3. Enable **Recovery context**. Compare the resting-HR/HRV weekly means and night counts with
   available history. Insufficient nights give no mean. Missing weeks remain gaps. Charge,
   Effort, Rest and Scorecard verdict must not change: this is context, never a new score.
4. Enable **Timeline**. Check phase/scan dates, non-private diet breaks/deloads and Today. Add an
   actual checkpoint or planned target date; mark it done and reopen. An approximate date is
   labeled approximate. A refused weight waypoint explains the phase/target constraint; it must
   not modify the target or existing checkpoint.
5. Compare the projection with Scorecard's same evaluation. No projection is shown when unavailable;
   no target date is invented. Private spans, niggle details, unrelated event kinds and medical
   labels are absent. Source features turned off are identified as off.
6. Turn each stage-6 switch off separately. Only its own Health row/screen disappears. Stored log,
   rules, pauses and checkpoints remain; no widget, notification, packet or existing score gains
   a niggle diagnosis or checkpoint detail.

## Finish each accepted part

1. At largest text size, read and operate every new screen used above; controls and text remain
   reachable. With VoiceOver, names, values and actions are understandable; charts have useful
   summaries. Repeat with Reduce Motion enabled. Record any untested screen or optional path.
2. Confirm cancel/back/relaunch preserve saved records and do not save an unfinished draft. Return
   unwanted switches to off. Make a fresh backup after accepted data entry.
3. Keep a private acceptance record with step results and remaining issues. Only after explicit
   owner acceptance does the integrator create `checkpoint/YYYY-MM-DD-superapp-<stage>` and update
   `docs/personal/CONTEXT.md`, without measurements or private screenshots. A failing step is fixed
   and rechecked before that part is accepted; this checklist records no acceptance by itself.
