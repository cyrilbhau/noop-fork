# Personal iOS widgets: first additive milestone

This changes the pinned baseline recorded in `INTEGRATIONS-AUDIT.md`. The audit's tables describe
that upstream baseline; this page describes the personal fork additions. Bluetooth collection,
protocol decoding, physiological algorithms, database schema, and existing widgets stay with the
baseline engine. This is an intentional iOS-only personal presentation preference and widget
addition; it does not change the Swift/Kotlin analytics or stored-data parity contract.

## Compiled on the Mac; physical widget behavior unverified

Update, 21 October 2026: the owner's personal Simulator and final unsigned iPhone-only builds
passed, including these widget views. Relevant Mac app tests also passed (94 cases). Signed
physical installation and refresh remain blocked by Apple device processing. See `MAC-STATUS.md`;
the Linux validation below describes the earlier cloud-only evidence.

- **Band Steps** Home Screen and rectangular Lock Screen widgets read the optional personal payload
  in the existing App Group snapshot. The number is labelled **Estimated • WHOOP 4.0**. No iPhone or
  imported Apple Health steps are substituted. The estimate must belong to the resolved day's
  positively identified WHOOP 4.0 source. A missing calibration, unknown family, or un-attributable
  legacy/re-paired namespace shows unavailable. This conservative source requirement may hide an
  otherwise visible legacy estimate rather than misattribute it.
- The current day's count expires at local midnight when the extension renders, even if the app has
  not republished. The timeline also contains an explicit next-midnight entry. Goal progress never
  reuses yesterday's steps. Missing counts remain missing, rather than zero.
- **Freshness unknown** is explicit. The existing `steps_est` daily cache has no durable calculation
  timestamp/input revision. Neither the app's publication time nor the newest motion record proves
  which data the cached estimate includes, so the fork does not manufacture a measurement time.
- The existing Settings profile section gains a **Daily step goal** control. It starts **Not set**,
  uses explicit chosen values, and updates the widget on change. It writes only a local display
  preference (`personal.stepsGoal`), not calibration or physiological data. The shared payload
  accepts only positive goals up to 50,000. A goal remains visible when the count is unavailable,
  without drawing fabricated zero progress.
- **Recent Sleep** Home and rectangular Lock Screen widgets reuse the existing main-night selector
  and stage-duration decoder. They show actual stored wake endpoint/date, distinguish **Local
  estimate** from **WHOOP history**, preserve the incomplete-data warning and user-correction flag,
  and omit missing/impossible stage totals. A clock span is never substituted for asleep duration.
  Open local nights are withheld using the existing `HealthWriteback.nightIsStillOpen` policy.
  Data ending before yesterday or in the future is not shown as recent.
- Existing recovery/strain/Rest widgets remain available. The new optional payload preserves legacy
  snapshot decoding. Live HR/battery publication carries it forward without refreshing estimate
  observation time. Rendered personal values and goal changes participate in widget reload decisions.

All new widget colors, fonts and spacing use `StrandPalette`, `StrandFont`, and `NoopMetrics`.
Numeric values use tabular digits. These are small native additions, not the requested five-screen
redesign. Reliable collection and the baseline physical-device checks still gate that larger work.

## Validation actually performed

On Linux, a verified Swift 6.0.3 toolchain compiled the production shared sources (`HrTrace`,
`StressTrace`, `WidgetSnapshot`, `PersonalWidgetMetrics`) and
`StrandTests/PersonalWidgetMetricsTests.swift` directly into a standalone XCTest executable.
All **13 tests passed**, with zero skips and failures. They exercise legacy decoding, new payload
round trips, missing/invalid/zero estimates, unknown freshness, goal bounds, midnight rollover,
India's local date, a daylight-saving boundary, sleep source/quality/wake times, future/old sleep,
rendered-content reload decisions, and the actual pure helper used by live publication.

The reusable runner is committed as source. From the checkout root, with Swift activated:

```sh
python3 Tools/check_personal_widgets.py
# Or select a toolchain explicitly:
python3 Tools/check_personal_widgets.py --swiftc /path/to/swiftc
```

It compiles the production shared sources and the same XCTest cases into a temporary directory,
discovers every test method, runs them, and preserves the underlying compiler/test exit status.
It never opens a database, reads health exports, or requests an Apple signing identity.

The compile command and test log are retained in the current workspace at
`/workspace/noop-validation/personal-widgets/command.json` and `result.txt`. They are generated
validation artifacts, not health data or application source. Xcode's `StrandTests` target also
includes the helper so the same XCTest cases can be run on a Mac.

The new WidgetKit file and widget bundle passed Swift frontend parsing. This is syntax evidence
only. The Linux Swift 6.0.3 parser rejects pre-existing trailing argument commas in
`WidgetPublish.swift` that use the repository's newer Apple Swift dialect; those baseline lines
were not changed to obtain an artificial pass. No Apple SDK, SwiftUI type check, iOS build,
provisioning, installed widget, or background-delivery result was obtained on Linux.

## Mac/iPhone checks still required

Use the separate personal identity and App Group from the build instructions. Keep Health writes
ungranted during collection validation.

1. Build the baseline on the Mac, then build this fork with Xcode 26 and the required SDK. Generate
   the project from `project.yml`; do not hand-edit or commit `Strand.xcodeproj`.
2. Confirm the app and widget share the personally provisioned App Group and that the widget
   extension remains embedded. Install beside any existing NOOP build.
3. Choose WHOOP 4.0 in pairing/registry and collect enough data for a calibrated step estimate.
   Until calibration/source is usable, **unavailable** is the correct state.
4. Add **Band Steps** and **Recent Sleep** from the widget gallery. Change the goal from Not set to
   a chosen value in Settings. Check the app and widget describe the same day's estimate; compare
   against manually counted walks using the agreed tolerances, not WHOOP agreement alone.
5. Lock the phone, complete an offload/reconnect, reopen the app, and record when widgets actually
   refresh. iOS controls refresh timing; a 15-minute timeline request is not a continuous-data promise.
6. Check **Freshness unknown** is visible for estimates. At local midnight, yesterday's count must
   disappear while the chosen goal remains. Test a sparse/incomplete night and a vendor-imported
   night: source, duration, end time and incomplete status must remain explicit.

A recovery/strain freshness redesign, a reliable step measurement from 4.0, Health step export, and
an automatic Hevy API client are not delivered by these widgets. See the audit and device plan for
those remaining limitations.
