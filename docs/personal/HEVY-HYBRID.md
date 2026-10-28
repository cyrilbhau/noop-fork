# Personal Hevy imports and Health workout reads

The personal iPhone build supports reviewed workout text and manual Hevy CSV imports for exercises,
sets, repetitions, weights and notes. Apple Health supplies workout summaries separately. This is a
local import workflow; it does not connect to a Hevy account or require a new subscription.

## After a workout: paste text

Open **More → Lift Log → Paste workout text**, paste the Hevy shared workout message, then tap
**Preview**. Review the date, exercises, weights, repetitions and notes before **Save workout**.
Saved sessions can be reopened in Lift Log. A matching strength workout also exposes
**Exercises and sets** from its detail screen.

The parser accepts the shared English date header, exercise headings, quoted notes, and lines such
as `Set 1: 20 kg x 10`, `Set 2: 45 lb x 8`, or `Set 3: bodyweight x 12`. Unrecognized set lines block
saving and are shown for correction. Other formats may need editing before preview succeeds.

Weights are retained as logged, with pounds converted to kilograms once. A note about two dumbbells
does not double the weight. The complete pasted text is retained in the local session note. An
exercise without set details remains visible as unquantified; no repetitions, load or duration are
invented. Footer links and tags are stored as text and are not opened or executed.

If exactly one strength workout matches the start time within two minutes, its known start and end
are used. Otherwise the owner can add a duration. With no duration, the session and sets are saved
in Lift Log without creating a fabricated workout interval.

## Periodically: import a CSV

Keep the original Hevy export unchanged. In NOOP, open **More → Data Sources → Lifting log
(Hevy/Liftosaur) → Choose export…** and select the CSV. Supported Hevy columns retain exercise
names, set order/type, weights, repetitions, RPE, notes, and supplied duration/distance annotations.
Warmup-only sessions are retained without counting warmups toward working volume. The existing
Liftosaur path continues to import summaries.

Imports append sessions atomically using the existing lift-session and lift-set tables. A session
with the same imported start time is skipped, preserving the existing log and local edits. This is
not reconciliation of later Hevy edits or deletions. Review dates before saving pasted text so a
later CSV can recognize the same session. Retain source exports for fields or future formats that
the importer does not support.

## Automatic workout summaries through Apple Health

Open **More → Apple Health → Enable Apple Health**. Allow **Read → Workouts**. If iOS does not
show the permission sheet after an earlier denial, open **Health → profile → Apps → NOOP Cyril**
and enable Workouts reads there, then return to NOOP and choose **Sync now**. Health settings labels
may vary by iOS version. Hevy must already have written its workouts into Apple Health.

This personal build requests only workout reads and no Health write permissions. Both Health
writeback entry points return immediately in this mode, including when older write grants exist.
Daily vitals, sleep, steps and Apple Watch source selection are not imported by this route. Initial
manual sync covers the latest 30 days; foreground/Health observer updates remain subject to iOS
scheduling. iOS does not reveal whether a read grant was denied, so an empty result does not prove
there are no source workouts.

Health summaries do not contain the full Hevy lifting log. Text and CSV supply that detail. Existing
captured workout HR and Strain are preserved when an incoming summary lacks them. The import does
not infer muscular Strain or change Recovery, Sleep or Strain formulas. General duplicate matching
still depends on timestamps and sport; a Health relay with a different timestamp or classification
can require review.

## Validation recorded on 28 October 2026

- Signed iPhone app build succeeded; the combined Coach/Hevy candidate was installed in place.
  No Apple Watch app was built or embedded. Existing app identities were preserved.
- The owner confirmed that the pasted example preview showed the expected sets and notes, then
  saved it and reopened it successfully. Workouts read permission is enabled and recent Hevy-authored
  workouts exist in Apple Health. The owner also confirmed the imported session already appears in
  NOOP's Workouts list with an Apple Health source.
- The import package suite executed 329 tests: 328 passed and one pre-existing optional fixture test
  skipped. The selected macOS app suite passed 16 tests, including six new parser/storage/dedup tests.
- Source hygiene and whitespace checks passed. Hevy strings are present in all supported catalog
  languages; concurrent Coach localization changes are validated by that workstream.
- The CSV metadata model and parser were mirrored in Kotlin with a Swift output oracle. Android
  tests were not run because this Mac has no configured JDK/Android toolchain. The reviewed text
  entry and native lift-log import UI in this change are specific to the personal Apple build.

No personal workout example is committed as a test fixture. No Health samples were written or
deleted by this implementation. No schema migration, paid API connection or new network route was
added for these imports.

The Health acceptance check exposed a display/cache issue: the former empty-state test ignored
workouts, the source-page count ran after cross-source merging, and daily-metric refresh could leave
workout-only changes unpublished. The follow-up patch shows a focused workout count/list link,
counts retained Health source rows, and invalidates workout views after a successful nonempty Health
import. This changes the read/display path without changing the workout list's deduplication rules.
The follow-up iPhone build and 14 focused app tests passed, including three new regressions for
workout-only data, source counting after activity merging, and cache invalidation. The final combined
Coach/Health update was installed in place, preserving app data and sign-in. Its device/simulator
builds, signature verification and 133 focused app tests passed, including these 14 Health tests.
Automatic launch initially awaited the owner unlocking the phone. The owner then opened the final
installed build successfully and confirmed the Coach reply and retained sign-in. No further phone
setup is pending for these workflows.
