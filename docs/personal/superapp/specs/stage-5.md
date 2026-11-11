# Stage 5 specification — events layer

Gate G0 for stage 5 of the health super-app workstream. Read [CONTEXT.md](../CONTEXT.md),
[ROADMAP.md](../ROADMAP.md) (stage 5, and stages 1, 2 and 6 which feed or consume it),
[QUALITY-GATES.md](../QUALITY-GATES.md) and the stage 1 specification ([stage-1.md](stage-1.md),
especially §8, §9, §14 and rulings R25 to R43) first.

Verified against the source at commit `0b89b814` (branch `personal/superapp-5-events-spec`, cut from
`personal/superapp-1-screens`). Every `path:line` below is as of that commit. Paths are relative to
the repository root. Nothing was built or run for this document; it is a reading of the code.

This file contains no personal measurement, date, medication or injury detail. Every example belongs
to the synthetic "Fixture Person" of §13, whose dates sit on the stage 1 fixture's 2031 calendar.

## 1. Goal and scope

**Goal.** A gap in training or a jump on the scale carries its own explanation on every day-axis
chart, on the scorecard and in the coach packet, from events the owner enters once.

**In scope**

- Personal events: a kind, a start day, an optional end day, an optional note, a sensitivity flag.
- Kinds: travel, illness, diet break, deload, supplement change, and a custom kind the owner names.
- One store, one decode, one pure overlap module.
- An Events screen with add, edit and delete; a row in the Health tab; a Settings switch.
- Quiet dots on the time axis of the redesign's day-axis and week-axis charts, and a text caption.
- A scorecard annotation for the judged week and its evidence window. The verdict is untouched.
- A packet section function for stage 2's coach packet; sensitive events excluded unless switched on.
- Backup round trip.

**Out of scope**

- Any change to `CutScorecard.evaluate`, its input, or any score, estimate or analytic. Events are
  display context only. Nothing is computed from them.
- Events in the in-app Coach context (`AICoach.buildContext`, `buildFullContext`). See §3, C7.
- Events in any widget, Live Activity, notification or the watch. Not sensitive ones, not any.
- Reminders, streaks, prompts to log an event.
- A time of day on an event. Events are whole local days (§7.1).
- The niggle log and the checkpoint timeline (stage 6). §14.3 states what stage 6 can reuse.
- The existing "Mark a Moment" action, the `event` table and the Journal. None is read or written.
- A migration, a new target, an entitlement, a network path, a Health read. None is needed.
- Android. No Kotlin is written (R43). §9.4 states the drift.
- Any medical statement. "Illness" is the owner's own label for their own days.

## 2. Re-check of "what exists"

| # | Claim in the planning documents | Status | Evidence |
|---|---|---|---|
| 1 | An `event` table exists: `deviceId`, `ts`, `kind`, `payloadJSON` | Confirmed, with more: primary key `(deviceId, ts, kind)`, and a later `synced` column | `Packages/WhoopStore/Sources/WhoopStore/Database.swift:28-34`, `:130-134` |
| 2 | "Current writers were not surveyed" | Surveyed in §4.1. Every writer is strap, ring or app telemetry | §4.1 |
| 3 | "Mark a Moment" exists as an App Intent | Confirmed. It does **not** use the `event` table (§3, C1) | `StrandiOS/System/NOOPAppIntents.swift:63-70`, `:138-140`; `Strand/App/AppModel.swift:1876-1886` |
| 4 | The newest migration is `v47-rr-whoop5-fill` | Confirmed | `Database.swift:1103` |
| 5 | `metricSeries` is a per-day numeric series keyed `(deviceId, day, key)` | Confirmed; the value is one Double | `Database.swift:204-215` |
| 6 | The Journal holds per-day yes/no or numeric answers | Confirmed: `(deviceId, day, question)` with `answeredYes`, `notes`, `numericValue`, stored under the sentinel id `noop-journal` | `Database.swift:157-164`, `:399-403`; `Strand/Data/Repository.swift:2661` |
| 7 | Stage 1 stores phases as a JSON string in settings and carries it in the backup | Confirmed | `Strand/Data/CutScorecardSettings.swift:62-68`, `:106-134`; `Packages/WhoopStore/Sources/WhoopStore/BackupSettings.swift:68-73`, `:93-94` |
| 8 | The backup is a ZIP of the whole database plus a whitelisted `settings.json` | Confirmed. Restore swaps the database, then applies the whitelisted keys present in the file | `BackupSettings.swift:3-20`, `:120-127`; `Strand/Data/DataBackup.swift:289-300`, `:588-597` |
| 9 | The scorecard has a presenter that turns the result into strings and curves | Confirmed | `Strand/Data/CutScorecardPresenter.swift:53-151`, `:246`; curves at `:378-379`, `:412-413` |
| 10 | There are shared chart components | Confirmed, as four families, not one (§3, C5) | `Packages/StrandDesign/Sources/StrandDesign/NoopLineChart.swift:57`, `NoopBarChart.swift:13`, `TrendChart.swift:125`; `StrandiOS/Scorecard/ScorecardWeekChart.swift:10` |
| 11 | A week is identified by its Monday day key, with timezone-free helpers | Confirmed | `Packages/StrandAnalytics/Sources/StrandAnalytics/WeeklyDigest.swift:421`, `:430`; `CutScorecard.swift:966` |
| 12 | A feature flag pattern exists: one observable copy of a `noop.*` Bool | Confirmed | `Strand/Data/CutScorecardModel.swift:18-66` |
| 13 | The debug demo harness maps `--demo-screen <name>` to a screen | Confirmed; unknown names fall through to `ScorecardDemo.screen(named:)` | `StrandiOS/App/StrandiOSApp.swift:466-469`, `:569-623`; `StrandiOS/Scorecard/ScorecardDemo.swift:33` |
| 14 | Stage 2's coach packet exists | **Not on this branch.** No `CoachPacket` symbol in the tree. Its specification is being written in parallel | search of the tree |
| 15 | Widgets read a shared snapshot from the App Group suite, not the app's standard defaults | Confirmed | `StrandiOSShared/WidgetSnapshot.swift:6`, `:104` |

## 3. Corrections to the planning documents

| # | Document says | The code says | Consequence for this stage |
|---|---|---|---|
| C1 | ROADMAP stage 5 and CONTEXT §4 pair "the `event` table and the Mark a Moment action" as one storage | Mark a Moment never touches the table. It appends a timestamp to a `[Double]` under the UserDefaults key `moments`, trims silently to the newest 500, and buzzes the strap (`Strand/App/AppModel.swift:1880-1886`; loaded at `:439`). Its only reader is the Automations screen, which lists the last five and can clear them (`Strand/Screens/AutomationsView.swift:154-173`). On iPhone the intent queues into the App Group defaults and the app drains it on activation (`StrandiOS/System/NOOPAppIntents.swift:8-26`, `:63-70`; `StrandiOS/App/AppModel+iOS.swift:27`). The macOS intent calls the model directly (`Strand/System/NOOPAppIntents.swift:43-52`). `moments` is not in the backup whitelist | Moments are instants with no kind, note or range, they are capped by deletion, and they are not backed up. Stage 5 neither reuses nor changes them |
| C2 | CONTEXT §4: `event` has four columns | Five columns and a three-part primary key (§2 row 1). Inserts are `ON CONFLICT DO NOTHING` (`Packages/WhoopStore/Sources/WhoopStore/StreamStore.swift:286-295`, `WhoopStore.swift:187-193`). There is no update and no delete of a single row anywhere | Reuse would need new store functions and a key that two events of one kind on one start can collide on |
| C3 | "The table is keyed by strap deviceId" (the brief for this stage) | True for strap rows, but sentinel ids already exist: `noop-app` for the app-version event (`Strand/App/AppModel.swift:607`, `:623`) and `noop-journal` for the Journal (`Repository.swift:2661`). Strap deletion and serial adoption act only on a named device id (`Packages/WhoopStore/Sources/WhoopStore/DeviceRegistryStore.swift:162-165`, `:263-268`) | A sentinel id would satisfy R42 inside the table. The option is costed in §8 and still not recommended, for other reasons |
| C4 | ROADMAP: "If not, design a migration: GRDB and Room together" | R43 (11 November 2026) removes the Room half. And the roadmap offers two choices where there are at least five (§8) | §8 presents every option. The recommended one needs no migration |
| C5 | ROADMAP: "Charts show events as quiet marks on the time axis", as if there were one chart | Four chart families. `TrendChart` is Swift Charts with a real date axis, gridlines and an optional dashed baseline rule (`TrendChart.swift:329`, `:424-425`); it serves the classic screens. `NoopLineChart` hides its axis and prints a caption row under the plot (`NoopLineChart.swift:228-243`, `:515`, `:546-561`). `NoopBarChart` is index-based. `ScorecardWeekChart` is a hand-drawn weekly curve that already puts an open ring on the axis for a missed week (`ScorecardWeekChart.swift:72-78`). `ChartAxisDays` serves `TrendChart` only (`ChartAxisDays.swift:7-25`) | §10.5 defines one mark row and one layout function in `StrandDesign`, adopted by three of the four families through one parameter each. `TrendChart` is not adopted (S6) |
| C6 | ROADMAP test plan: "events across a time-zone change" implies events are instants | Every consumer is day-keyed: scorecard weeks are Monday day keys with no zone (`CutScorecard.swift:426-429`), weigh-ins carry a stored local day (stage 1 §9.1), and the day-axis charts plot per-day values | Events are stored as local day keys (§7.1). A zone change cannot move one. The test is restated in §12.3 |
| C7 | ROADMAP: "Sensitive kinds never appear in widgets or notifications" treats those as the only leak paths | The Coach brief is model output over the in-app Coach context, posted as a notification and copied into the App Group for `CoachBriefWidget` (`Strand/System/CoachBriefScheduler.swift:43-44`, `:274`, `:486`; context built at `Strand/AI/AICoach.swift:1207`, `:1607`). Anything in that context can surface in both, and is sent to a network provider | No event of any kind enters the in-app Coach context in this stage. §12.5 asserts it |
| C8 | ROADMAP stage 2: sensitive sections are "events of a medical kind" | Kind alone is the wrong test: the owner's custom kind is the sensitive one by design, and any event can carry a private note | Sensitivity is a per-event flag with a per-kind default (§7.2). Everything outside the Events screen keys on the flag |
| C9 | ROADMAP stage 5 has no work-package table and no screen list | — | §10 and §14 supply both |
| C10 | The app has an existing "illness" surface: a strap-derived early-warning banner and notification (`Strand/System/IllnessNotifier.swift:4-7`; `Strand/Screens/AutomationsView.swift:332-335`) | It is a derived signal. A personal event of kind illness is the owner's statement | The two never read each other. The event kind's wording is "Illness" in the owner's own list and the app draws no inference from it (S9) |

## 4. Every reader and writer

### 4.1 The `event` table

"Action" is what stage 5 does to the site. Every row is **untouched**.

| Site | What it does |
|---|---|
| `Packages/WhoopStore/Sources/WhoopStore/StreamStore.swift:286-295` | Writer. Inserts decoded strap and ring events from a stream batch |
| `Packages/WhoopProtocol/Sources/WhoopProtocol/Streams.swift:870`, `HistoricalStreams.swift:452` | Produce WHOOP events (for example the `WRIST_ON` and `WRIST_OFF` families) for that insert |
| `Packages/WhoopStore/Sources/WhoopStore/OuraStreamMapping.swift:38-46`, `:122`, `:185`, `:212` | Produce `OURA_HRV`, `OURA_SLEEP_PHASE`, `OURA_MOTION` |
| `Packages/WhoopStore/Sources/WhoopStore/StandardHRMapping.swift:16`, `:38` | Produces `STANDARD_HR_CONTACT` |
| `Packages/WhoopStore/Sources/WhoopStore/WhoopStore.swift:187-193` (`recordEvent`), called at `Strand/App/AppModel.swift:623` | Writer. `APP_VERSION_CHANGED` under `noop-app` (`BackupProvenance.swift:36-38`). No reader of that kind was found in the Apple targets |
| `Strand/Collect/Collector.swift:277` | Reads the batch's event timestamps for a window bound |
| `Packages/WhoopStore/Sources/WhoopStore/Reads.swift:623-637` (`events`) | Reader. All kinds for one device id and time range |
| `Strand/Data/IntelligenceEngine.swift:1370` → `Packages/StrandAnalytics/Sources/StrandAnalytics/AnalyticsEngine.swift:25-28` | Reads the day owner's events and keeps the wrist-on and wrist-off kinds for the off-wrist sleep backstop. **This feeds scoring** |
| `Strand/Data/Repository.swift:2182-2187` | Reads `OURA_MOTION` for a timeline track |
| `Reads.swift:84-98` (`standardHRContacts`) | Reads `STANDARD_HR_CONTACT` |
| `Reads.swift:221` (`analysisFingerprint`) | Uses `MAX(rowid)` of the **whole** table, every device id, as a change detector for rescoring |
| `Reads.swift:296-297` | Per-device, per-window count and newest timestamp, same purpose |
| `StreamStore.swift:596-604` | Raw CSV export of one device's events, payload included (`Strand/Screens/SettingsView.swift:2521`) |
| `StreamStore.swift:675`, `Reads.swift:981`, `:1008`; `Packages/NoopLocalAccess/Sources/NoopLocalAccessCore/LocalAccessCore.swift:346` | Row counts for storage statistics and the read-only access tool |
| `DeviceRegistryStore.swift:162-165`, `:263-268` | Deletes or re-keys a named device's rows |
| `android/app/src/main/java/com/noop/data/Entities.kt:184`, `WhoopRepository.kt:1147` | The Room twin of the table and of `recordEvent` |

Not the `event` table, despite the name: `Strand/Collect/RawDataSessionStore.swift:28` holds a raw
capture session's own event list in a file.

### 4.2 Mark a Moment and sleep marks

| Site | What it does | Action |
|---|---|---|
| `Strand/App/AppModel.swift:87-88`, `:439`, `:1876-1886` | Stores `moments` | Untouched |
| `Strand/Screens/AutomationsView.swift:154-173` | Lists and clears moments | Untouched |
| `StrandiOS/System/NOOPAppIntents.swift:8-70`, `:138-140`; `Strand/System/NOOPAppIntents.swift:43-66`; `StrandiOS/App/SiriShortcutsSettingsView.swift:40`; `Strand/System/MacActions.swift:11` | The intent and its listings | Untouched |
| `Strand/App/AppModel.swift:1892-1911` | Sleep marks: a second UserDefaults list plus a `metricSeries` row | Untouched |

### 4.3 Personal events (new fact)

No reader or writer exists today. After this stage, the complete list is:

| Site | Role |
|---|---|
| `PersonalEventStore` | The only code that reads or writes the storage key, and the only decode |
| `PersonalEventSheetModel`, `PersonalEventsModel` | The only callers of the store's write functions |
| `PersonalEventChartSource` | The only reader for charts |
| `CutScorecardModel.load()` | Passes the store's events to the presenter through the context |
| The coach packet builder (stage 2) | Calls `PersonalEvents.packetLines` with the store's events |
| `BackupSettings` | Carries the stored string, unparsed |

§12.5 asserts this list by source scan.

### 4.4 Facts this stage shows that already have a reader

| Fact | Existing resolver | How stage 5 reads it |
|---|---|---|
| The judged week and the evidence window | `CutScorecardResult.judgedWeekStart`, `.evidenceStartDay` (`CutScorecard.swift:392-402`) | The presenter reads those two fields. It does not recompute a week |
| The weeks a curve shows | The presenter's `weeks` list (`CutScorecardPresenter.swift:262-263`) | Marks are computed over that same list, in the same call |
| "Today" | `LocalDayWindows(timeZone:).dayKey(for:)`, captured once per load (`CutScorecardModel.swift:149`) | The same captured value. No second clock |

## 5. Final names

| Thing | Name | Where |
|---|---|---|
| Pure types and functions | `PersonalEventKind`, `PersonalEvent`, `PersonalEventIssue`, `PersonalEventWeekRelation`, `PersonalEventSlot`, `PersonalEvents` | `Packages/StrandAnalytics/Sources/StrandAnalytics/PersonalEvents.swift` |
| Store | `PersonalEventStore`, `PersonalEventStoreError` | `Strand/Data/PersonalEventStore.swift` |
| Presenter | `PersonalEventPresenter`, `PersonalEventRow`, `PersonalEventsPresentation`, `PersonalEventCaption`, `PersonalEventDeleteConfirmation` | `Strand/Data/PersonalEventPresenter.swift` |
| Models | `PersonalEventsFlag`, `PersonalEventsModel`, `PersonalEventSheetModel`, `PersonalEventDraft` | `Strand/Data/PersonalEventsModel.swift` |
| Chart reader | `PersonalEventChartSource` | `Strand/Data/PersonalEventChartSource.swift` |
| Chart caption view (shared with macOS) | `PersonalEventChartCaption` | `Strand/Screens/PersonalEventChartCaption.swift` |
| Mark type, layout and row | `NoopChartAxisMarks`, `ChartAxisMarkLayout`, `NoopChartAxisMarkRow` | `Packages/StrandDesign/Sources/StrandDesign/ChartAxisMarks.swift` |
| Screens | `PersonalEventsView`, `PersonalEventSheet` | `StrandiOS/Events/` |
| Demo harness | `PersonalEventsDemo` | `StrandiOS/Events/PersonalEventsDemo.swift` |
| Feature flag | `noop.personalEventsEnabled`, Bool, default `false` | `PersonalEventStore.enabledKey` |
| Stored list | `personalEvents.items`, String (JSON array) | `PersonalEventStore.itemsKey` |
| Packet switch | `personalEvents.packetIncludesSensitive`, Bool, default `false` | `PersonalEventStore.packetSensitiveKey` |
| Navigation | `RedesignRoute.personalEvents` | `StrandiOS/Redesign/RedesignRoute.swift` |
| Scorecard additions | `CutScorecardPresentation.EventNote`, `CutScorecardPresentation.eventNote`, `CutScorecardPresentation.Curve.marked`, `CutScorecardPresentationContext.events` | `Strand/Data/CutScorecardPresenter.swift` |

The store, presenter, models and chart source live under `Strand/` so `StrandTests` (macOS scheme
only) can test them, as stage 1 did (stage 1 §5).

## 6. Pure logic: the API

File `Packages/StrandAnalytics/Sources/StrandAnalytics/PersonalEvents.swift`. No store, no clock, no
`Calendar`, no `TimeZone`, no `Date`, no localisation. Uses `WeeklyDigestEngine.parseYMD`,
`formatYMD`, `addDays` and `mondayOfWeek` from the same module (`WeeklyDigest.swift:421`, `:430`,
`:463`).

```swift
public enum PersonalEventKind: String, CaseIterable, Sendable {
    case travel, illness, dietBreak, deload, supplementChange, custom
}

public struct PersonalEvent: Equatable, Sendable {
    public let id: String            // non-empty; the store issues 16 lowercase hex characters
    public let kind: PersonalEventKind
    public let label: String?        // required for .custom, nil for every other kind
    public let startDay: String      // "yyyy-MM-dd", canonical
    public let endDay: String?       // inclusive; nil = ongoing; equal to startDay = one day
    public let note: String?         // nil or non-empty
    public let sensitive: Bool
    public let createdAt: Int        // epoch seconds; ordering tie-break only
    public init(id: String, kind: PersonalEventKind, label: String?, startDay: String,
                endDay: String?, note: String?, sensitive: Bool, createdAt: Int)
}

public enum PersonalEventIssue: Equatable, Sendable {
    case emptyId, invalidStartDay, invalidEndDay, endBeforeStart
    case missingLabel, unexpectedLabel, labelTooLong, emptyNote, noteTooLong
}

public enum PersonalEventWeekRelation: Equatable, Sendable {
    case before        // the event ended before the range began
    case after         // the event starts after the range ends
    case within        // starts and ends inside the range
    case startsWithin  // starts inside, ends after it or is ongoing
    case endsWithin    // starts before, ends inside
    case covers        // starts on or before the first day's eve and ends after the last day, or is ongoing
}

/// An inclusive run of days that one chart position stands for: a day (first == last) or a week.
public struct PersonalEventSlot: Equatable, Sendable {
    public let firstDay: String
    public let lastDay: String
    public init(firstDay: String, lastDay: String)
}

public enum PersonalEvents {
    public static let maxLabelLength = 40      // Characters (grapheme clusters)
    public static let maxNoteLength = 280

    public static func defaultSensitive(_ kind: PersonalEventKind) -> Bool
    public static func isValidDay(_ day: String) -> Bool
    public static func issues(_ event: PersonalEvent) -> [PersonalEventIssue]
    public static func normalized(_ events: [PersonalEvent]) -> [PersonalEvent]

    public static func relation(of event: PersonalEvent, firstDay: String, lastDay: String)
        -> PersonalEventWeekRelation?
    public static func overlaps(_ event: PersonalEvent, firstDay: String, lastDay: String) -> Bool
    public static func events(overlapping firstDay: String, _ lastDay: String,
                              in events: [PersonalEvent]) -> [PersonalEvent]
    public static func events(overlappingWeekStarting weekStart: String,
                              in events: [PersonalEvent]) -> [PersonalEvent]
    public static func coveredSlots(events: [PersonalEvent], slots: [PersonalEventSlot]) -> [Bool]

    public static func visible(_ events: [PersonalEvent], includeSensitive: Bool) -> [PersonalEvent]
    public static func packetLines(events: [PersonalEvent], firstDay: String, lastDay: String,
                                   includeSensitive: Bool) -> [String]
}
```

Every function is total: it never throws and never traps, for any input.

## 7. Algorithm and format

### 7.1 Days, not instants

An event is a run of **local calendar days**. `startDay` and `endDay` are canonical ten-character
keys (stage 1 ruling R5): `isValidDay` is true only for `yyyy-MM-dd`, years 0001 to 9999, naming a
real date, and equal to `formatYMD` of its own parts. Canonical keys of that range order
lexicographically in date order, so every comparison below is a string comparison and no day
arithmetic is needed for overlap.

The editor turns the picked date into a key with `LocalDayWindows(timeZone:).dayKey(for:)`
(`Packages/StrandAnalytics/Sources/StrandAnalytics/LocalDayWindows.swift:265`) in the device's zone
at the moment of saving. The key is then fixed. Travelling does not move an event, and reading it in
another zone returns the same key.

- **Ongoing** (open-ended): `endDay == nil`. It overlaps every range that ends on or after its start.
- **One day** (the roadmap's "zero-length"): `endDay == startDay`.
- A future start is allowed (a planned trip or deload). A future event simply overlaps nothing shown.

### 7.2 Kinds and the sensitivity default

| Kind | Raw value | Label | `defaultSensitive` |
|---|---|---|---|
| Travel | `travel` | none | false |
| Illness | `illness` | none | **true** |
| Diet break | `dietBreak` | none | false |
| Deload | `deload` | none | false |
| Supplement change | `supplementChange` | none | false |
| Custom | `custom` | required, the owner's words | **true** |

The default only presets the editor's switch. The stored `sensitive` flag is the owner's choice and
is the only thing any consumer tests. The app offers no suggested labels for the custom kind.

### 7.3 Validation

`issues` returns every applicable issue, in the order the enum declares them:

- `emptyId`: `id` is empty.
- `invalidStartDay` / `invalidEndDay`: fails `isValidDay`.
- `endBeforeStart`: both days valid and `endDay < startDay`.
- `missingLabel`: kind `custom` and the label is nil or empty after trimming whitespace and newlines.
- `unexpectedLabel`: any other kind with a non-nil label.
- `labelTooLong`: more than 40 `Character`s. `noteTooLong`: more than 280.
- `emptyNote`: the note is non-nil and empty after trimming. An absent note is nil.

`normalized` keeps events with no issues, removes duplicates by `id` (the **last** occurrence in the
input wins), and sorts ascending by `(startDay, createdAt, id)`. Every list-returning function
returns its result in that order and treats its input as if `normalized` had been applied.

### 7.4 Overlap

For an event with start `s` and end `e` (nil when ongoing) and a range `[a, b]`:

- If `a` or `b` is not a valid day, or `b < a`, or the event has any issue: `relation` is nil,
  `overlaps` is false, and the event is absent from every list.
- `before` when `e != nil && e < a`. `after` when `s > b`.
- Otherwise the event overlaps, and: `within` when `s >= a` and `e != nil && e <= b`;
  `startsWithin` when `s >= a` and (`e == nil` or `e > b`); `endsWithin` when `s < a` and
  `e != nil && e <= b`; `covers` when `s < a` and (`e == nil` or `e > b`).
- `overlaps` is `relation` not in `{nil, before, after}`: equivalently `s <= b && (e == nil || e >= a)`.

`events(overlappingWeekStarting:)` requires `weekStart` to be a valid day that equals
`WeeklyDigestEngine.mondayOfWeek(containing: weekStart)`; otherwise it returns `[]`. The range is
`[weekStart, addDays(weekStart, 6)]`.

`coveredSlots` returns one Bool per slot, in order: whether any event overlaps `[firstDay, lastDay]`.
An invalid slot is false. Sensitive events count: a dot carries no text (§10.5).

### 7.5 Visibility and the packet section

`visible(events, includeSensitive:)` is `normalized(events)` with `sensitive` events removed unless
`includeSensitive` is true. It is the one function that applies the flag; the presenter, the chart
caption and the packet all go through it or through `packetLines`.

`packetLines` returns the lines of the coach packet's Events section, English regardless of the
interface language, ISO dates:

```
EVENTS (entered by the owner; whole local days)
- 2031-01-22: Supplement change
- 2031-02-22 to 2031-02-24: Travel
- 2031-03-10 to 2031-03-16: Travel. Note: Fixture trip
- 2031-05-19, ongoing: Illness
```

- Line 1 is the fixed header above.
- One line per event of `visible(events, includeSensitive:)` that overlaps `[firstDay, lastDay]`.
- Dates: `s` alone when `e == s`; `s to e`; `s, ongoing` when `e == nil`. The stored days are
  printed whole, not clipped to the range.
- Name: `Travel`, `Illness`, `Diet break`, `Deload`, `Supplement change`; for `custom`, the label.
- A note is appended as `. Note: <note>`, with every run of whitespace and newlines collapsed to one
  space.
- With no line to print: the header, then `- none listed`. "Listed", because hidden sensitive
  events may exist and the packet must neither reveal nor deny them.
- An invalid range returns the header and `- none listed`.
- Nothing else: no id, no `createdAt`, no count of hidden events, no sensitivity marker.

## 8. Storage decision

### 8.1 Options

| # | Home | Migration | What it costs | R42 |
|---|---|---|---|---|
| A | The `event` table under a sentinel device id | No | The table is the telemetry stream of straps and rings and one reader feeds scoring (§4.1). Every personal insert moves `analysisFingerprint`'s whole-table `MAX(rowid)` (`Reads.swift:221`), so logging a trip would make the app believe sensor data changed. Rows are insert-only: edit and delete need new SQL in `WhoopStore`, whose neighbours are declared Kotlin twins. The key `(deviceId, ts, kind)` has no id and collides for two events of one kind on one start; a synthetic `ts` would make the range reads meaningless. Storage counts and the access tool would count personal rows as sensor rows (`Reads.swift:981`, `LocalAccessCore.swift:346`). One real advantage: Room has the same table, so rows would survive an Android round trip with no contract change | Met with a sentinel id (C3) |
| B | **A JSON list in settings, on the backup whitelist** (the stage 1 phases pattern) | No | Not transactional with the database. The whole list is rewritten on each change (events are few; a year of heavy use is under 100 KB). The value travels in the readable `settings.json` entry of the backup, whose header asks that the file stay safe to share (`BackupSettings.swift:11-15`); the archive already contains the health database, but an event note in plain JSON is easier to read than a SQLite row. The Swift whitelist gains a key the Kotlin one does not have (§9.4). Not queryable in SQL, which stage 6 may want | Met by construction: no device id exists in the store |
| C | `metricSeries`, one row per covered day per kind, under a sentinel id | No | One Double per `(day, key)`: no note, no id, no custom label, no ongoing state, and a range becomes many rows to rewrite on every edit. The series appears wherever series are enumerated (Compare, the access tool's exports) | Met with a sentinel id |
| D | The Journal, one row per covered day | No | The Journal is read by the Coach's behaviour-to-outcome ranking (`Strand/AI/AICoach.swift:1249-1251`) and by journal analytics. Events would become "behaviours" correlated against recovery and would enter the in-app Coach context, the exact leak C7 forbids. A range is again many rows | Met (`noop-journal`) |
| E | `labMarker` rows with the kind as the marker key | No | Lab Book would list events as markers and the Coach's Lab Book roll-up would print them. Rows are keyed by the active strap id until the separate Lab Book ownership change lands (R42) | Not met today |
| F | A new table `personalEvent` with no `deviceId` column | **Yes** | Needs the owner's go-ahead. A merge hotspot with upstream at the tail of `Database.swift`. The Room schema is not updated (R43), so the GRDB and Room schemas stop agreeing. Needs a rehearsal on a copy of the real database before any install | Met by construction; and a table without `deviceId` passes the existing coverage test (`Packages/WhoopStore/Tests/WhoopStoreTests/DeviceRegistryStoreTests.swift:220-239`) |

### 8.2 Recommendation

**Option B.** It is the only option that needs no migration, disturbs no existing reader, cannot be
deleted with a strap, and has a working precedent on this branch with its tests (stage 1 §9.2,
§9.3). Option A's fingerprint side effect alone rules it out: it would turn a diary entry into a
rescoring trigger, which is "disturbing the table's current meaning" in the plainest sense.

The store is written behind one type with one decode (§9), so a later move to option F changes that
file and nothing else. §8.3 records the migration design so that stage 6, or the owner, can choose it
without redoing this investigation.

### 8.3 Option F, designed — needs the owner's go-ahead; not part of this stage

- **Name:** `fork-p1-personal-event`. GRDB identifies a migration by its name string, so a name
  outside the `vNN-` sequence can never equal one upstream adds. Registered after upstream's last
  registration, from a separate file (`Database+Fork.swift`) reached by one call line, so an upstream
  merge that appends `v48-…` conflicts with one line at most.
- **Schema:** `personalEvent(id TEXT PRIMARY KEY, kind TEXT NOT NULL, label TEXT, startDay TEXT NOT
  NULL, endDay TEXT, note TEXT, sensitive INTEGER NOT NULL, createdAt INTEGER NOT NULL)`; index on
  `startDay`. Additive: no existing table is read or changed.
- **Data move:** on first launch after the migration, the store imports `personalEvents.items` into
  the table inside one transaction, verifies the count, and only then removes the settings key and
  drops it from the whitelist.
- **Tests:** the migration test; the device-scoped coverage test still passing; the import test,
  including an interruption between insert and key removal.
- **Room:** not updated, by the owner's decision. Consequence: an iPhone backup opened by the Android
  app carries a table Room has no entity for. Whether Room rejects or ignores it was not determined.
- **Open risk:** whether GRDB applies an upstream migration that is registered *before* an
  already-applied fork migration was not verified (§16). The rehearsal must prove it.

## 9. Storage design (option B)

### 9.1 Keys

All in `UserDefaults.standard`, declared in `PersonalEventStore`. Never in the App Group suite.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `noop.personalEventsEnabled` | Bool | `false` | The feature flag. Off: no row, no screen, no marks, no caption, no scorecard note, no packet section, and the store is never read |
| `personalEvents.items` | String | absent | JSON array of events |
| `personalEvents.packetIncludesSensitive` | Bool | `false` | Whether the coach packet lists sensitive events |

### 9.2 The stored string

A JSON array, written with sorted keys and no insignificant whitespace, elements in `normalized`
order, so equal lists give equal bytes. One element:

```json
{"createdAt":1930000000,"endDay":"2031-03-16","id":"0f1e2d3c4b5a6978","kind":"travel","note":"Fixture trip","sensitive":false,"startDay":"2031-03-10","v":1}
```

`endDay`, `label` and `note` are omitted when nil. `v` is 1.

**Reading.** The string is parsed with `JSONSerialization` into an array, then each element is
decoded on its own:

- An element that decodes, has `v == 1` and has no issue (§7.3) is an event.
- Any other element (unknown kind, `v` above 1, wrong type, an issue) is **held as it was parsed**
  and written back unchanged on every save. It is never shown as an event and never dropped. The
  Events screen states how many entries could not be read.
- A stored value that is not a string, or does not parse as a JSON array, sets `needsAttention`.
  While it is set: `events` is empty, every write throws `PersonalEventStoreError.storeUnreadable`,
  and nothing is overwritten. The owner may copy the raw text and may then choose to discard it
  (`discardUnreadableStore()`, which removes the key only while it is unreadable). This follows
  `CutScorecardSettings.phasesNeedAttention` and `discardUnreadablePhases`
  (`CutScorecardSettings.swift:122-134`).
- Reading never writes.

### 9.3 The store

```swift
enum PersonalEventStoreError: Error, Equatable {
    case storeUnreadable
    case invalid([PersonalEventIssue])
    case notFound
}

@MainActor
final class PersonalEventStore: ObservableObject {
    static let enabledKey = "noop.personalEventsEnabled"
    static let itemsKey = "personalEvents.items"
    static let packetSensitiveKey = "personalEvents.packetIncludesSensitive"
    static let shared: PersonalEventStore

    init(defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init,
         makeId: @escaping () -> String = PersonalEventStore.randomId)

    @Published private(set) var revision: Int      // moves on every change to itemsKey, whoever writes it
    var isEnabled: Bool { get }                    // reads enabledKey
    var packetIncludesSensitive: Bool { get set }
    var events: [PersonalEvent] { get }            // [] while the flag is off or the store is unreadable
    var unreadableEntryCount: Int { get }
    var needsAttention: Bool { get }
    var rawStoredText: String? { get }             // for the copy action only

    @discardableResult
    func add(kind: PersonalEventKind, label: String?, startDay: String, endDay: String?,
             note: String?, sensitive: Bool) throws -> PersonalEvent
    func update(_ event: PersonalEvent) throws     // by id; keeps createdAt; .notFound if absent
    func delete(id: String) throws                 // .notFound if absent
    @discardableResult func discardUnreadableStore() -> Bool
}
```

- `add` and `update` trim the label and the note (whitespace and newlines at both ends), turn an
  empty note into nil, validate with `PersonalEvents.issues`, and throw `.invalid` without writing.
- Each write reads the current string, changes one element, and writes the whole array once. An
  interruption therefore leaves either the old list or the new one.
- `events` reads the defaults at each access and caches nothing, so a string written by a backup
  restore is seen by the next read (the stage 1 rule, `CutScorecardSettings.swift:58-61`).
- `revision` follows `UserDefaults.didChangeNotification` for its defaults object and moves only
  when the stored string changed, as `CutScorecardFlag` follows its key
  (`CutScorecardModel.swift:31-45`).
- With the flag off, `events` returns `[]` without touching `itemsKey`. Stored events are kept;
  switching the flag back on shows them again.
- There is no count limit and nothing is ever trimmed. (Contrast `moments`, which deletes beyond
  500.)

`PersonalEventsFlag` is the observable copy of the flag, the same shape as `CutScorecardFlag`.

### 9.4 Backup whitelist

| Canonical key | JSON kind | Swift storage key | Joins the whitelist |
|---|---|---|---|
| `personalEvents.items` | String | `personalEvents.items` | **Yes, Swift only** |
| `noop.personalEventsEnabled` | — | — | No. A `noop.*` toggle is per install (`BackupSettings.swift:40-42`); after a restore the feature is off until switched on, and the events are there when it is |
| `personalEvents.packetIncludesSensitive` | — | — | No. A Bool cannot cross, and off is the safe direction |

Edits: `BackupSettings.whitelist` and `BackupSettings.appleDefaultsKey`
(`BackupSettings.swift:49-74`, `:79-95`). The string is carried and never parsed there.

Restore semantics, unchanged from every other key: a backup that carries the key **replaces** this
device's list; a backup without it leaves the list alone (`BackupSettings.swift:120-127`).

**Kotlin side: not updated, by the owner's decision (R43).** The exact drift this creates:

- `BackupSettingsCodec.WHITELIST` (`android/app/src/main/java/com/noop/data/BackupSettings.kt:50-82`)
  has no `personalEvents.items`. The Swift header's statement that the whitelist is mirrored
  byte-for-byte becomes false for this one key; the comment added beside the key says so.
- An iPhone backup restored by the Android app loses the events: unknown keys are dropped on decode.
- A backup made by the Android app never carries events; restored on the iPhone it leaves the
  iPhone's list untouched.
- Android re-exporting a restored iPhone backup produces a file without events.
- No existing test compares the two whitelists as wholes; the one cross-platform check compares the
  two stage 1 keys only (`Tools/test_body_measurement_single_resolver.py:278`). Nothing fails.

**What the backup now contains.** Labels and notes of sensitive events, in clear text in
`settings.json`. The backup is already an unencrypted copy of the health database (CONTEXT §7 item
7). This raises the stakes of that backlog item and is put to the owner as S3.

### 9.5 Ownership (R42)

The store has no device id. Disconnecting, forgetting or deleting a strap, re-pointing the active
id, and adopting a serial identity do not read or write it. Erasing all of the app's data on purpose
removes it with everything else.

## 10. Screens and states

Frames are designed at G1 in a new round, `design/round7-events/`, with the pipeline stage 1 used
(`design/round6-scorecard/`, `design/tools/serve.py`, a new command in `design/figma-plugin`). Every
state below needs a frame at the default text size and at the largest accessibility size.

### 10.1 Entry points

- A row "Events" in the Health tab, beside the scorecard's row
  (`StrandiOS/Redesign/RedesignHealthView.swift:476-482`, `:523-532`), mounted only while the flag
  is on. Its value is the count of events overlapping today ("1 now"), or nothing.
- The scorecard's event note (§10.6) links to the Events screen.
- No Today card, no tab, no widget.

### 10.2 Events screen — `PersonalEventsView`

Newest start first. Sections: "Now" (overlapping today), "Upcoming" (start after today), "Earlier".

| State | What shows |
|---|---|
| Loading | Skeleton rows (`noopSkeleton`) |
| Empty | "No events yet" and one line: "Add travel, illness, a diet break or a deload, and charts will show when it happened." The add action is primary |
| Rows | Kind name or the owner's label; the dates ("10 – 16 Mar", "22 Jan", "Since 19 May"); the first line of the note; a small "Private" tag when sensitive. Labels and notes of sensitive events are shown here in full: this is the owner's own list |
| Ongoing | Listed under "Now" with "Since <date>" and an "End today" action |
| Only future events | "Upcoming" alone |
| Some entries unreadable | Footnote: "%lld entries could not be read. They are kept." No destructive action |
| Store unreadable | An explanation, "Copy stored text", and "Start again", which asks once before discarding |
| Delete | Asks once (§10.4) |
| Largest text size | Dates stack under the name; the tag wraps below |
| Reduce Motion | No staggered entrance |

### 10.3 Event sheet — `PersonalEventSheet`

One sheet for add and edit.

| State | Behaviour |
|---|---|
| Add, first open | Kind: travel. Start: today. Length: "One day". Note empty. Private: the kind's default |
| Kind changed | The Private switch moves to the new kind's default **unless** the owner has already changed it in this sheet |
| Custom kind | A name field appears, required, 40 characters. Empty: "Save" disabled and the field says a name is needed |
| Length | Three choices: "One day", "Until" with an end date, "Ongoing" |
| End before start | "Save" disabled; the end field says it must be on or after the start |
| Future start | Allowed. A line says the event is planned |
| Note | Optional, 280 characters, with a remaining count from 240 on |
| Edit | Opens with the event's values; the kind can be changed |
| Saving | Buttons disabled; inputs captured before the write |
| Save failed | The sheet stays open with the values intact and a retry. If the store is unreadable the message says so and links to the Events screen |
| Saved | Dismisses; the list, the charts and the scorecard note update from `revision` |
| Largest text size | Each control on its own row |

### 10.4 Delete confirmation

Title "Delete this event?". Detail: the name and dates. Buttons "Delete" (destructive) and "Cancel".
Deleting is immediate and has no undo; the confirmation says so.

### 10.5 Chart marks and captions

**The mark, defined once.** `Packages/StrandDesign/Sources/StrandDesign/ChartAxisMarks.swift`:

```swift
public struct NoopChartAxisMarks: Equatable, Sendable {
    public var fractions: [Double]          // 0...1 along the plot's x extent; ascending, distinct
    public var accessibilityText: String?   // appended to the chart's spoken summary
    public init(fractions: [Double], accessibilityText: String? = nil)
    /// Positions drawn at index / (count - 1): line and weekly-point charts. One position: 0.5.
    public static func points(covered: [Bool], accessibilityText: String? = nil) -> NoopChartAxisMarks
    /// Positions drawn at (index + 0.5) / count: bar charts.
    public static func bars(covered: [Bool], accessibilityText: String? = nil) -> NoopChartAxisMarks
    /// Positions of covered x values on a continuous x-domain.
    public static func values(_ xs: [Double], covered: [Bool], domain: ClosedRange<Double>,
                              accessibilityText: String? = nil) -> NoopChartAxisMarks
}

public enum ChartAxisMarkLayout {
    /// x offsets in points for a plot of `width` inset by `leading` and `trailing`, thinned so that
    /// neighbours are at least `minSpacing` apart. The first and last mark of every unbroken run
    /// are always kept.
    public static func offsets(_ marks: NoopChartAxisMarks, width: CGFloat, leading: CGFloat,
                               trailing: CGFloat, minSpacing: CGFloat) -> [CGFloat]
}

public struct NoopChartAxisMarkRow: View   // marks:, leading:, trailing:
```

The row is a fixed-height strip under the plot and above any caption row. Each mark is a small
filled dot in `NoopTheme.textTertiary`. There is no line joining dots, no band, no rule, no label
and no gesture. Proposed tokens (the designer confirms at G1): `NoopTheme.Layout.chartAxisMark`
(dot diameter 4), `chartAxisMarkRow` (row height 8), `chartAxisMarkSpacing` (minimum 6). An empty
`fractions` draws no row and takes no height, so a chart with no events is pixel-identical to today.

**Adoption: one optional parameter per family, defaulting to nil.**

| Family | Change | Sites that pass marks |
|---|---|---|
| `ScorecardWeekChart` | `axisMarks: NoopChartAxisMarks? = nil`; row between the plot and the two date labels (`ScorecardWeekChart.swift:28-36`). The missed-week ring stays on the baseline; an event dot sits in the row beneath it | `StrandiOS/Scorecard/ScorecardView.swift:461` (weight and waist) |
| `NoopBarChart` | `axisMarks:` likewise | `StrandiOS/Redesign/RecoveryDetailView.swift:188`, `StrainDetailView.swift:241` (thirty day bars with day keys); `Strand/Screens/MetricExplorerView.swift:2351`; `StrandiOS/App/TrainingHubView.swift:217` (seven day bars) |
| `NoopLineChart` | `axisMarks:` likewise, drawn with the chart's own insets (`NoopLineChart.swift:310-313`) between `plot` and the caption row (`:234-238`). Ignored when `compact` | `Strand/Screens/MetricExplorerView.swift:2356`; `Strand/Screens/TrendsView.swift:1039` |
| `TrendChart` | **Not adopted** (S6) | — |

Charts that never take marks: intraday charts (`StrandiOS/Redesign/RedesignTodayView.swift:1153`,
`OverviewHRChart`, workout traces), compact sparklines (`RedesignTodayView.swift:669`,
`RedesignHealthView.swift:271`) and the Health tiles (`RedesignHealthView.swift:323`).

**One reader for every site.** `PersonalEventChartSource` (main-actor, observable, `shared`):

```swift
func marks(dayKeys: [String], style: MarkStyle) -> NoopChartAxisMarks?      // .points or .bars
func marks(weekStarts: [String]) -> NoopChartAxisMarks?                      // .points
func marks(dayKeys: [String], xs: [Double], domain: ClosedRange<Double>) -> NoopChartAxisMarks?
func caption(firstDay: String, lastDay: String, today: String) -> PersonalEventCaption?
```

Each returns nil while the flag is off, and nil when nothing overlaps. Each builds
`PersonalEventSlot`s and calls `PersonalEvents.coveredSlots`. A site therefore adds two lines: the
`axisMarks:` argument and, under the chart, `PersonalEventChartCaption(caption)`.

**The caption** names what the dots mean, since a dot has no text:

| State | What shows |
|---|---|
| Flag off, or no event in the window | Nothing; no height |
| One or two events | One line each: "Travel · 10 – 16 Mar" |
| More than two | The two with the latest start, then "and %lld more" |
| A sensitive event | "Private event · 26 Mar". Never the label, never the note |
| Ongoing | "Illness · since 19 May" for a non-sensitive event; "Private event · since 19 May" otherwise |
| Largest text size | Lines wrap; nothing truncates a date |

Spoken summary: the chart's own summary, then "Events:" and the caption lines.

### 10.6 Scorecard annotation

`CutScorecardPresentationContext` gains `events: [PersonalEvent] = []` and
`CutScorecardPresenter.present` gains two outputs. `CutScorecardModel.load()` fills `events` from
`PersonalEventStore.events`, captured before its first suspension with its other inputs
(`CutScorecardModel.swift:148-153`).

```swift
struct EventNote: Equatable {
    var title: String            // "Events this week"
    var lines: [String]          // events overlapping the judged week
    var earlierTitle: String?    // "Earlier in the weeks behind this verdict"
    var earlierLines: [String]   // overlapping [evidenceStartDay, judged week's Sunday] but not the judged week
    var moreText: String?        // "and %lld more", when either list was cut at three
    var footnote: String         // "Shown for context. Events do not change the verdict."
}
var eventNote: EventNote? = nil          // on CutScorecardPresentation
var marked: [Bool] = []                  // on CutScorecardPresentation.Curve; one per point, or empty
```

| State | What shows |
|---|---|
| Flag off, or no events at all | `eventNote` nil, `marked` empty. The presentation equals today's, field for field |
| An event overlaps the judged week | The note under the verdict, with that event's line |
| Events only earlier in the evidence window | The note with the earlier section alone |
| An event in a week with no weigh-in | The curve shows the missed-week ring with a dot beneath it, and the note names the event. This is the "gap explains itself" case |
| No judged week (no readings, overdue with no week) | No note; curve marks still show if weeks are shown |
| Sensitive event | "Private event · <dates>" |
| More than three in a list | Three, then "and %lld more" |
| The Today card | Unchanged in every state. Events never reach `CutScorecardCard` |

The verdict, the rules, the signals, the rate and the projection are computed before and without the
events, and no string of theirs changes.

### 10.7 Settings

In the iPhone-only block beside the scorecard card (`Strand/Screens/SettingsView.swift:462-468`,
`:1860-1871`): a switch "Personal events"; beneath it, visible only while on, a switch "Include
private events in the coach packet" (off), with the footnote "Private events and their notes stay
out of the packet unless this is on."

### 10.8 Widgets and notifications

None. This stage adds no widget kind, no widget field, no Live Activity field, no notification and
no notification text. §12.5 proves the absence.

## 11. User-facing strings

English source strings, all through `Strand/Resources/Localizable.xcstrings` in the ten locales
(`de`, `en`, `es`, `fr`, `it`, `pl`, `pt-PT`, `ru`, `zh-Hans`, `zh-Hant`). The packet lines of §7.5
are fixed English and are **not** localised.

| Use | String |
|---|---|
| Kind names | "Travel", "Illness", "Diet break", "Deload", "Supplement change", "Something else" |
| Outside the Events screen, any sensitive event | "Private event" |
| Tag | "Private" |
| Dates | "%@" (one day), "%@ – %@", "Since %@" / "since %@", "From %@" (planned) |
| Health row | "Events"; value "%lld now" |
| Screen | "Events"; sections "Now", "Upcoming", "Earlier"; "Add event"; "End today" |
| Empty | "No events yet"; "Add travel, illness, a diet break or a deload, and charts will show when it happened." |
| Unreadable entries | "%lld entries could not be read. They are kept." |
| Unreadable store | "Your events could not be read"; "Nothing has been changed. You can copy the stored text before starting again."; "Copy stored text"; "Start again"; "Start again and discard the stored events?" |
| Sheet | "New event", "Edit event"; "Kind"; "Name"; "A name is needed"; "Starts"; "Length"; "One day", "Until", "Ongoing"; "Ends"; "Must be on or after the start"; "Planned: this starts in the future"; "Note"; "Private"; "Private events show as \"Private event\" outside this screen and stay out of the coach packet unless you include them."; "Save"; "Could not save. Try again." |
| Delete | "Delete this event?"; "This cannot be undone."; "Delete"; "Cancel" |
| Caption | "%@ · %@"; "and %lld more" |
| Scorecard note | "Events this week"; "Earlier in the weeks behind this verdict"; "Shown for context. Events do not change the verdict." |
| Settings | "Personal events"; "Include private events in the coach packet"; "Private events and their notes stay out of the packet unless this is on." |
| Spoken | "Events:" |

No string states or implies a cause ("because you travelled"), a diagnosis, or advice.

## 12. Test plan

Tests are written from this document before the implementation, by an agent who has not seen it.

### 12.1 Pure logic — `Packages/StrandAnalytics/Tests/StrandAnalyticsTests/PersonalEventsTests.swift`

Validation
- `testCanonicalDayIsValidAndPaddedOrImpossibleDaysAreNot`
- `testEndBeforeStartIsAnIssue`
- `testCustomKindNeedsALabelAndOtherKindsRejectOne`
- `testLabelAndNoteLengthsAreCountedInCharacters` (a 40-character label of combined emoji passes; 41 fails)
- `testWhitespaceOnlyLabelIsMissing`
- `testIssuesAreReportedInDeclarationOrder`
- `testDefaultSensitiveIsTrueOnlyForIllnessAndCustom`

Normalisation
- `testNormalizedDropsInvalidEvents`
- `testNormalizedKeepsTheLastOfADuplicatedId`
- `testNormalizedOrdersByStartThenCreatedAtThenId`

Overlap, against one week `[2031-03-10, 2031-03-16]`
- `testEventEndingTheDayBeforeTheWeekIsBefore`
- `testEventStartingTheDayAfterTheWeekIsAfter`
- `testEventInsideTheWeekIsWithin`
- `testEventOnExactlyTheWeekIsWithin`
- `testEventSpanningTheWeekCovers`
- `testEventStartingInTheWeekAndEndingAfterStartsWithin`
- `testEventStartingBeforeAndEndingInTheWeekEndsWithin`
- `testEventEndingOnTheMondayOverlaps` and `testEventStartingOnTheSundayOverlaps` (inclusive bounds)
- `testOngoingEventStartedBeforeTheWeekCovers`
- `testOngoingEventStartedInTheWeekStartsWithin`
- `testOngoingEventStartingAfterTheWeekIsAfter`
- `testOneDayEventOnEachDayOfTheWeekIsWithin`
- `testOneDayEventOnTheSundayBeforeIsBefore`
- `testWeekStartThatIsNotAMondayReturnsNothing`
- `testInvalidRangeOrInvalidEventNeverOverlaps`
- `testOverlapAcrossAYearBoundaryAndALeapDay`
- `testOverlapsAgreesWithRelationForEveryCaseAbove`

Slots
- `testCoveredSlotsMarksEachDayOfARange`
- `testCoveredSlotsOverWeeksMatchesTheFixtureTable` (§13.2)
- `testCoveredSlotsCountsSensitiveEvents`
- `testCoveredSlotsOfNoEventsIsAllFalseAndOfNoSlotsIsEmpty`
- `testInvalidSlotIsFalse`

Visibility and packet
- `testVisibleRemovesSensitiveEventsUnlessIncluded`
- `testPacketLinesForTheFixtureWithSensitiveOff` (golden, §13.3)
- `testPacketLinesForTheFixtureWithSensitiveOn` (golden, §13.3)
- `testPacketLinesWithNothingListedSayNoneListed`
- `testPacketLinesWithOnlySensitiveEventsAndSensitiveOffSayNoneListed`
- `testPacketLinesPrintWholeStoredDaysNotClippedToTheRange`
- `testPacketNoteCollapsesNewlinesAndRunsOfSpaces`
- `testPacketLinesContainNoIdAndNoCreatedAt`
- `testPacketLinesForAnInvalidRange`

Properties
- `testAddingAnEventOutsideARangeNeverChangesThatRangesResult`
- `testSameInputGivesSameOutput`
- `testNoFunctionTrapsOnGeneratedGarbage` (fixed-seed generator, 500 inputs)

### 12.2 Design package — `Packages/StrandDesign/Tests/StrandDesignTests/ChartAxisMarksTests.swift`

- `testPointsPlacesIndexOverCountMinusOne` and `testSinglePointSitsInTheMiddle`
- `testBarsPlacesIndexPlusHalfOverCount`
- `testValuesMapsOntoTheDomainAndDropsValuesOutsideIt`
- `testNothingCoveredGivesNoFractions`
- `testOffsetsRespectInsets`
- `testThinningKeepsMinimumSpacing`
- `testThinningKeepsTheFirstAndLastMarkOfEveryRun`
- `testZeroOrNegativeWidthGivesNoOffsets`

### 12.3 App target — `StrandTests/`

`PersonalEventStoreTests.swift`
- `testFlagDefaultsToOff`
- `testEventsAreEmptyAndTheKeyIsNotReadWhileTheFlagIsOff`
- `testAddWritesSortedKeysAndNormalizedOrder`
- `testAddTrimsLabelAndNoteAndTurnsAnEmptyNoteIntoNil`
- `testAddOfAnInvalidEventThrowsAndWritesNothing`
- `testUpdateKeepsIdAndCreatedAt`
- `testUpdateOfAMissingIdThrowsNotFound`
- `testDeleteRemovesOnlyThatEvent`
- `testSameListGivesSameBytes`
- `testUnreadableElementIsKeptVerbatimAcrossAddUpdateAndDelete`
- `testElementWithAHigherVersionOrUnknownKindIsKeptAndNotShown`
- `testNonArrayStoredValueNeedsAttentionAndRefusesEveryWrite`
- `testDiscardRemovesTheKeyOnlyWhileUnreadable`
- `testReadingNeverWrites`
- `testRevisionMovesWhenAnotherWriterChangesTheKey` (the restore path)
- `testSwitchingTheFlagOffKeepsTheStoredEvents`
- `testNothingIsTrimmedAtFiveHundredAndOneEvents`
- `testDayKeyOfThePickedDateUsesTheZoneAtSaveTime`
- `testChangingTheZoneAfterSavingDoesNotMoveAnEvent` (the roadmap's time-zone case: save in one
  injected zone, read and overlap in another, identical keys and identical overlap)
- `testEventSavedJustBeforeAndJustAfterLocalMidnightLandsOnDifferentDays`
- `testEventAcrossADaylightSavingChangeKeepsItsDays`

`PersonalEventOwnershipTests.swift` (R42)
- `testDeletingAStrapsDataLeavesEveryEvent`
- `testForgettingAStrapAndRepointingTheActiveIdLeavesEveryEvent`
- `testNoEventIsStoredInTheDatabase` (no table gains a row from an add)

`PersonalEventPresenterTests.swift` — one test per row of §10.2, §10.3 and §10.5's caption table,
named for the state; plus
- `testSensitiveLabelAndNoteAppearOnlyInTheEventsScreenPresentation`
- `testCaptionShowsTheTwoLatestStartsThenTheCount`
- `testNoStringContainsAnInterpolatedNilOrAnEmptyDate`

`PersonalEventSheetModelTests.swift`
- `testKindChangeMovesThePrivateSwitchUntilTheOwnerTouchesIt`
- `testSaveIsDisabledForAnEmptyCustomNameAndForAnEndBeforeTheStart`
- `testInputsAreCapturedBeforeTheWrite`
- `testFailedSaveKeepsTheValues`
- `testEndTodayTurnsAnOngoingEventIntoARange`

`PersonalEventChartSourceTests.swift`
- `testEveryFunctionReturnsNilWhileTheFlagIsOff`
- `testDayBarsAndDayPointsAgreeOnWhichDaysAreCovered`
- `testWeekMarksMatchTheFixtureTable`
- `testMarksAndCaptionAreResolvedFromTheSameEvents` (one read; a caption never names an event the
  marks did not see)

`CutScorecardEventNoteTests.swift`
- `testNoEventsLeavesThePresentationEqualToThePresentationWithoutTheContextField`
- `testVerdictRulesSignalsRateProjectionAndCardAreIdenticalWithAndWithoutEventsForAllTwentyTwoFixtureWeeks`
- `testJudgedWeekEventAppearsInTheNote`
- `testEarlierEvidenceWindowEventAppearsInTheEarlierSection`
- `testMissedWeekWithAnEventIsMarkedOnBothCurves`
- `testSensitiveEventIsWordedPrivateEvent`
- `testMoreThanThreeEventsAreCutWithACount`
- `testNoJudgedWeekGivesNoNote`
- `testMarkedHasOneEntryPerCurvePoint`

Backup — `Packages/WhoopStore/Tests/WhoopStoreTests/BackupSettingsTests.swift` (extended)
- `testPersonalEventsRoundTripAsOneString`
- `testPersonalEventsFlagAndPacketSwitchAreNotExported`
- `testRestoreWithoutTheKeyLeavesExistingEvents`
- `testRestoreWithTheKeyReplacesTheList`

and in `StrandTests/PersonalEventBackupTests.swift`:
`testEventsSurviveAFullExportAndRestoreThroughDataBackup`, byte-identical stored string, sensitive
events and an unreadable entry included.

### 12.4 Flag-off equivalence

With `noop.personalEventsEnabled` off: the baseline suite's results are unchanged; every new chart
parameter defaults to nil and draws nothing; `CutScorecardPresentation` equals its current value
(the new fields default); the Health tab has no new row; `personalEvents.items` is never read and
never written. Direct assertions: `testEventsAreEmptyAndTheKeyIsNotReadWhileTheFlagIsOff`,
`testEveryFunctionReturnsNilWhileTheFlagIsOff`,
`testNoEventsLeavesThePresentationEqualToThePresentationWithoutTheContextField`. The existing
`CutScorecardPresenterTests` pass unedited.

### 12.5 Single-resolver assertions and privacy scans — `Tools/test_personal_events_boundaries.py`

In the Python suite that already asserts on product source (stage 1 §8.6).

- `test_items_key_is_spelled_only_in_the_store_and_the_whitelist`: the literal `personalEvents.items`
  occurs only in `PersonalEventStore.swift`, `BackupSettings.swift` and tests.
- `test_only_the_models_call_the_store_writes`: `.add(kind:`, `.update(`, `.delete(id:` on the store
  occur only in `PersonalEventsModel.swift`.
- `test_widgets_watch_and_shared_payloads_never_name_personal_events`: no occurrence of
  `PersonalEvent` or `personalEvents.` under `StrandiOSWidgets/`, `StrandiOSShared/` or the watch
  targets.
- `test_notification_producers_never_name_personal_events`: none in the seven files that build
  notification content (`Strand/App/AppModel.swift` excepted by a narrower pattern on its
  notification function; `Strand/System/BatteryNotifier.swift`, `CoachBriefScheduler.swift`,
  `IllnessNotifier.swift`, `StrainTargetNotifier.swift`, `WeighInReminder.swift`,
  `WindDownNudge.swift`), and the test fails if a new file under `Strand/` or `StrandiOS/` builds
  `UNMutableNotificationContent` without being added to the list.
- `test_coach_context_never_reads_personal_events`: none in `Strand/AI/`.
- `test_scorecard_logic_never_sees_events`: none in `CutScorecard.swift` or
  `CutScorecardInputBuilder.swift`.
- `test_app_group_suite_is_never_given_the_events`: no file writes a `personalEvents.` key through
  `UserDefaults(suiteName:`.
- `test_allowlists_still_match`: each allowlisted file still contains its pattern.

Behavioural scans, in `StrandTests/PersonalEventPrivacyTests.swift`. The fixture's sensitive label
("Fixture change"), its note ("Fixture note") and the non-sensitive note ("Fixture trip") are the
needles:

- `testWidgetSnapshotEncodingContainsNoEventText` (encode a `WidgetSnapshot` built with the fixture
  store populated; scan the bytes for all three needles and every kind name)
- `testEveryNotificationTextContainsNoEventText` (the weigh-in reminder's content and the other
  static notification texts)
- `testInAppCoachContextContainsNoEventText` (`buildContext` and `buildFullContext` with the store
  populated)
- `testDefaultPacketSectionContainsNoSensitiveLabelOrNote`
- `testChartCaptionAndScorecardNoteContainNoSensitiveLabelOrNote`
- `testAccessibilityTextOfMarksContainsNoSensitiveLabelOrNote`
- `testAppGroupDefaultsContainNoEventKey`

### 12.6 Fault injection

For each line: make the change, confirm a named test fails, restore. Record the result in the pull
request.

| # | Deliberate break | A test that must fail |
|---|---|---|
| F1 | Overlap upper bound made exclusive | `testEventStartingOnTheSundayOverlaps` |
| F2 | Overlap lower bound made exclusive | `testEventEndingOnTheMondayOverlaps` |
| F3 | Ongoing treated as ending on its start day | `testOngoingEventStartedBeforeTheWeekCovers` |
| F4 | Week range of six days, or of eight | `testOneDayEventOnEachDayOfTheWeekIsWithin`, `testOneDayEventOnTheSundayBeforeIsBefore` |
| F5 | `visible` ignores the flag | `testVisibleRemovesSensitiveEventsUnlessIncluded` |
| F6 | `packetLines` prints a hidden-count line | `testPacketLinesWithOnlySensitiveEventsAndSensitiveOffSayNoneListed` |
| F7 | Caption prints the label of a sensitive event | `testChartCaptionAndScorecardNoteContainNoSensitiveLabelOrNote` |
| F8 | `coveredSlots` skips sensitive events | `testCoveredSlotsCountsSensitiveEvents` |
| F9 | Store drops an unreadable element on save | `testUnreadableElementIsKeptVerbatimAcrossAddUpdateAndDelete` |
| F10 | Store writes while unreadable | `testNonArrayStoredValueNeedsAttentionAndRefusesEveryWrite` |
| F11 | Store reads the key with the flag off | `testEventsAreEmptyAndTheKeyIsNotReadWhileTheFlagIsOff` |
| F12 | Store trims the list at 500 | `testNothingIsTrimmedAtFiveHundredAndOneEvents` |
| F13 | Day key taken in UTC, not the save-time zone | `testDayKeyOfThePickedDateUsesTheZoneAtSaveTime` |
| F14 | Events passed into `CutScorecardInput` or the builder | `test_scorecard_logic_never_sees_events` |
| F15 | The presenter alters a verdict line when an event overlaps | `testVerdictRulesSignalsRateProjectionAndCardAreIdenticalWithAndWithoutEventsForAllTwentyTwoFixtureWeeks` |
| F16 | An event field added to `WidgetSnapshot` | `test_widgets_watch_and_shared_payloads_never_name_personal_events` |
| F17 | Events appended to the Coach context | `test_coach_context_never_reads_personal_events`, `testInAppCoachContextContainsNoEventText` |
| F18 | The key removed from the whitelist | `testPersonalEventsRoundTripAsOneString` |
| F19 | The flag added to the whitelist | `testPersonalEventsFlagAndPacketSwitchAreNotExported` |
| F20 | Thinning drops the last mark of a run | `testThinningKeepsTheFirstAndLastMarkOfEveryRun` |
| F21 | Bar marks placed at index over count minus one | `testBarsPlacesIndexPlusHalfOverCount` |
| F22 | Caption and marks read the store separately, one filtered | `testMarksAndCaptionAreResolvedFromTheSameEvents` |

### 12.7 Parity

**Written disposition (R43); no Kotlin is written.**

- `PersonalEvents` (pure logic in `StrandAnalytics`) has no Kotlin twin. Android has no events
  surface in this workstream and the owner has no Android device. Each public declaration carries
  the comment "No Kotlin twin: personal iPhone fork, owner decision of 11 November 2026."
- `ChartAxisMarks` is `StrandDesign`, which has no Kotlin counterpart by design.
- The stored shape that crosses a contract is the one whitelist key. Its drift is stated in §9.4.
- The gate script's Android rows are waived by flag and reported as waived (`Tools/personal/gate.sh`,
  `--waive android`), never as passed.
- What the parity ledger and ratchet print for new one-sided declarations was not run (§16).

### 12.8 Simulator and rehearsal

- Every frame of round 7 reproduced from `PersonalEventsDemo` at the default and largest text size,
  Reduce Motion on and off; add, edit, delete, end-today and the unreadable-store path exercised by
  tapping.
- Side-by-side captures of each adopting chart with the flag off against the base commit: identical.
- Real-data rehearsal (0B-7): the owner's history in a simulator with a handful of events entered
  privately; check the scorecard note against the weeks the owner remembers, and a backup and
  restore of that copy. Results stay under `PersonalData/`.

## 13. Fixture

Everything here is invented. "Fixture Person" does not exist. The calendar is the stage 1 fixture's
(stage 1 §13): week 1 starts Monday 2031-01-06, weigh-ins on Wednesdays, week 10 has no weigh-in.

### 13.1 Events

| Id | Kind | Label | Start | End | Note | Sensitive | `createdAt` |
|---|---|---|---|---|---|---|---|
| E1 | travel | — | 2031-03-10 | 2031-03-16 | "Fixture trip" | false | 1000 |
| E2 | deload | — | 2031-02-03 | 2031-02-09 | — | false | 1001 |
| E3 | dietBreak | — | 2031-04-14 | 2031-04-27 | — | false | 1002 |
| E4 | supplementChange | — | 2031-01-22 | 2031-01-22 | — | false | 1003 |
| E5 | illness | — | 2031-05-19 | ongoing | — | true | 1004 |
| E6 | custom | "Fixture change" | 2031-03-26 | 2031-03-26 | "Fixture note" | true | 1005 |
| E7 | travel | — | 2030-12-01 | 2030-12-07 | — | false | 1006 |
| E8 | travel | — | 2031-02-22 | 2031-02-24 | — | false | 1007 |

Stored ids are `e1` … `e8` padded to sixteen hex characters in the test fixture file.

### 13.2 Expected overlap by week

Week n starts on 2031-01-06 plus 7 × (n − 1) days.

| Weeks | Events | What it covers |
|---|---|---|
| 1, 2, 4, 6, 9, 11, 13, 14, 17, 18, 19 | none | — |
| 3 | E4 | A one-day event inside a week |
| 5 | E2 | An event exactly on a week (`within`) |
| 7 | E8 | `startsWithin` (Saturday of week 7) |
| 8 | E8 | `endsWithin` (Monday of week 8) |
| 10 | E1 | The missed week carries its explanation |
| 12 | E6 | A sensitive one-day event |
| 15, 16 | E3 | One event over two whole weeks |
| 20, 21, 22 | E5 | Ongoing: `startsWithin` in week 20, `covers` after |
| — | E7 | Before every week: overlaps nothing |

`coveredSlots` over the 22 weeks is therefore true at weeks 3, 5, 7, 8, 10, 12, 15, 16, 20, 21, 22.

Scorecard note, `today` 2031-03-12 (stage 1 frame for the missed week): judged-week lines per the
stage 1 result for that day; E1 appears, and both curves mark week 10. With `today` 2031-03-26: the
judged week is week 12, the note's line is "Private event · 26 Mar", and E1 appears in the earlier
section if `evidenceStartDay` is on or before 2031-03-16. The Test author reads `evidenceStartDay`
from the stage 1 result and does not assume it.

### 13.3 Packet goldens, range 2031-01-06 to 2031-06-04

Sensitive off:

```
EVENTS (entered by the owner; whole local days)
- 2031-01-22: Supplement change
- 2031-02-03 to 2031-02-09: Deload
- 2031-02-22 to 2031-02-24: Travel
- 2031-03-10 to 2031-03-16: Travel. Note: Fixture trip
- 2031-04-14 to 2031-04-27: Diet break
```

Sensitive on adds, in start order, `- 2031-03-26: Fixture change. Note: Fixture note` after the
March travel line and `- 2031-05-19, ongoing: Illness` at the end.

### 13.4 Variants

| Variant | Change | Expected |
|---|---|---|
| V1 | No events | Every list empty; packet "none listed"; no note; no marks |
| V2 | Only E5 and E6, sensitive off | Packet "none listed"; marks at weeks 12, 20, 21, 22; captions say "Private event" |
| V3 | E1 with `endDay` 2031-03-09 (before its start) | Dropped by `normalized`; the store refuses to save it |
| V4 | A second event with E1's id and a different start | The later one in input order is kept |
| V5 | E5 given `endDay` 2031-05-25 | Weeks 21 and 22 lose their mark |
| V6 | Stored string with one extra element of kind `"somethingNew"` | Eight events read; one unreadable entry reported and preserved through a save |
| V7 | Stored value `"{"` | `needsAttention`; no events; writes refused |
| V8 | App-target tests that involve the repository's clock-bound reads | Dates relative to the real clock (stage 1 ruling R31); the 2031 fixture is for pure logic and store-only cases |

## 14. Work packages and file ownership

### 14.1 Packages

| WP | Role | Files |
|---|---|---|
| 5-2 | Designer | `design/round7-events/` (new); a round 7 command in `design/figma-plugin/code.js` and `manifest.json` |
| 5-3 | Test author | New: `Packages/StrandAnalytics/Tests/StrandAnalyticsTests/PersonalEventsTests.swift`, `PersonalEventsFixture.swift`; `Packages/StrandDesign/Tests/StrandDesignTests/ChartAxisMarksTests.swift`; `StrandTests/PersonalEventStoreTests.swift`, `PersonalEventOwnershipTests.swift`, `PersonalEventPresenterTests.swift`, `PersonalEventSheetModelTests.swift`, `PersonalEventChartSourceTests.swift`, `CutScorecardEventNoteTests.swift`, `PersonalEventBackupTests.swift`, `PersonalEventPrivacyTests.swift`; `Tools/test_personal_events_boundaries.py`. Extended: `Packages/WhoopStore/Tests/WhoopStoreTests/BackupSettingsTests.swift` (new methods only) |
| 5-4 | Implementer A (pure) | `Packages/StrandAnalytics/Sources/StrandAnalytics/PersonalEvents.swift` |
| 5-5 | Implementer B (storage) | New: `Strand/Data/PersonalEventStore.swift`. Edited: `Packages/WhoopStore/Sources/WhoopStore/BackupSettings.swift` (two entries and a comment) |
| 5-6 | Implementer C (chart marks) | New: `Packages/StrandDesign/Sources/StrandDesign/ChartAxisMarks.swift`. Edited, one parameter and one row each: `NoopLineChart.swift`, `NoopBarChart.swift`, `StrandiOS/Scorecard/ScorecardWeekChart.swift` |
| 5-7 | Implementer D, after G1 and after 5-4, 5-5, 5-6 merge | New: `Strand/Data/PersonalEventPresenter.swift`, `PersonalEventsModel.swift`, `PersonalEventChartSource.swift`; `Strand/Screens/PersonalEventChartCaption.swift`; `StrandiOS/Events/PersonalEventsView.swift`, `PersonalEventSheet.swift`, `PersonalEventsDemo.swift`. Edited: `Strand/Data/CutScorecardPresenter.swift` and `CutScorecardModel.swift` (the context field and the two outputs); `StrandiOS/Scorecard/ScorecardView.swift` (the note and `axisMarks:`); `StrandiOS/Redesign/RedesignRoute.swift`, `RedesignHealthView.swift` (the row); `RecoveryDetailView.swift`, `StrainDetailView.swift`, `StrandiOS/App/TrainingHubView.swift`, `Strand/Screens/MetricExplorerView.swift`, `Strand/Screens/TrendsView.swift` (two lines per chart site); `Strand/Screens/SettingsView.swift` (the two switches); `StrandiOS/App/StrandiOSApp.swift` debug block (one line: fall through to `PersonalEventsDemo.screen(named:)` after `ScorecardDemo`, `:623`) |
| 5-8 | Localiser | `Strand/Resources/Localizable.xcstrings` |
| 5-9 | Implementer A, after stage 2's builder merges | The one call from the packet builder to `PersonalEvents.packetLines`, and the packet preview's "private events left out" line. Files named by the stage 2 specification |
| 5-10 | Reviewers (correctness, contract, data-safety) and Verifier | None; read-only |

`project.yml` needs no change; the directories are included by path (stage 1 §14). Run
`xcodegen generate` after adding files. `StrandiOS/Events/` is a new directory under an included
root.

### 14.2 Shared hotspots this stage edits

| Hotspot | Edit | Order |
|---|---|---|
| `Strand/Resources/Localizable.xcstrings` | New strings | Localiser only, once, after English is final. **Serialise with every other stage** |
| `Strand/Screens/SettingsView.swift` | Two switches in the iPhone-only block | After stage 1's edits are merged; serialise with stages 2, 3 and 4 if they add switches |
| `StrandiOS/App/StrandiOSApp.swift` debug block | One line | Serialise with any stage adding a demo screen |
| `Packages/WhoopStore/.../BackupSettings.swift` | One key in two maps | Serialise with any stage adding a backup key |
| `Strand/Data/CutScorecardPresenter.swift`, `CutScorecardModel.swift`, `StrandiOS/Scorecard/ScorecardView.swift`, `ScorecardWeekChart.swift` | Additive fields and one row | Serialise with stage 1 follow-ups and with stage 2's extraction if it touches the presenter |
| `StrandiOS/Redesign/RedesignHealthView.swift`, `RedesignRoute.swift` | One row, one case | Serialise with stages 4 and 6 |
| `Strand/Screens/MetricExplorerView.swift`, `TrendsView.swift` | Two lines per chart | Shared with macOS: build `Strand` too |
| `NoopLineChart.swift`, `NoopBarChart.swift` | One defaulted parameter each | Serialise with stage 3 if its card adds chart options |

**Not edited:** `Strand/Screens/DashboardCards.swift`, `Strand/Data/TodayCardReadout.swift`, the
three Today views, `Packages/StrandImport` `MarkerCatalog`, `Packages/WhoopStore/.../Database.swift`,
any widget file, any notification file, `Strand/AI/`, anything under `android/`.

### 14.3 Parallel and serial

- **Parallel with any other stage, from now:** 5-2 (design), 5-3 (tests), 5-4 (pure logic), 5-6
  (the `StrandDesign` file and its tests; the three one-line chart edits wait their turn in §14.2).
- **Parallel with each other:** 5-4, 5-5, 5-6.
- **Serial:** 5-7 after G1 and after 5-4, 5-5, 5-6; 5-8 after 5-7's English is final; 5-9 after
  stage 2 merges. If stage 5 merges before stage 2, `packetLines` ships tested with no production
  caller and 5-9 adds the caller in stage 2's branch; the parity ledger's "production caller in the
  same change" expectation (CONTEXT §7 item 3) is then knowingly unmet for that one function and the
  pull request says so.
- **For stage 6:** the checkpoint timeline can read `PersonalEventStore.events` and
  `PersonalEvents.events(overlapping:_:in:)` as they are. The niggle log needs fields an event does
  not have (location, character, triage); it should not be squeezed into `PersonalEvent`. If stage 6
  needs SQL, §8.3 is the designed path.

## 15. Open questions for the owner

Work proceeds on each recommendation.

| # | Question | Recommendation, in force until overruled |
|---|---|---|
| S1 | Where are events stored: a settings list carried in the backup (no migration), or a new database table (a migration)? | The settings list (§8.2). The table is designed in §8.3 and needs your go-ahead if you prefer it |
| S2 | Are whole days enough, or does an event need a time of day? | Whole days. Every chart and the scorecard that would show an event is per day or per week |
| S3 | Private events and their notes will be inside backup files, readable by anyone who opens the file. Keep them in the backup? | Yes: a record that vanishes on restore is worse, and the backup already holds the health database. It makes the "encrypted backups" backlog item more pressing |
| S4 | Outside the Events screen, should a private event show its name, or the words "Private event"? | "Private event" everywhere else in the app: chart captions, the scorecard note, spoken text |
| S5 | Which kinds start as private? | Illness and "Something else". You can flip the switch on any single event |
| S6 | Should the classic charts (`TrendChart`, used when classic mode is on) also get marks? | No. They carry gridlines and a baseline rule you have rejected, and the redesign is the interface in use. Adoption later is one parameter |
| S7 | Should the scorecard note also list events from the earlier weeks its rules look back over, or the judged week only? | Both, in two short sections, three lines each at most |
| S8 | Should the in-app Coach (the ChatGPT-backed one) ever see events? | No, not in this stage. Its output reaches a notification and a widget, and its input leaves the phone |
| S9 | The app already has its own strap-derived "illness watch". Should logging an illness event affect it, or the other way round? | Neither. One is your statement, the other is an estimate; they stay separate |
| S10 | Should a chart caption be a link to the Events screen? | Not in this stage: the caption sits in screens shared with macOS that do not know the iPhone routes. The Health row and the scorecard note are the ways in |
| S11 | Should the packet tell the coach that private events were left out? | No. The packet says "none listed" or lists what is visible. The app's own preview tells you how many were left out |
| S12 | Should planned (future) events be allowed? | Yes. They appear under "Upcoming" and mark nothing until their days arrive |
| S13 | Should "Mark a Moment" offer to create an event? | No. It stays as it is; it is a strap gesture with no kind or range |

## 16. Not determined

- **Whether GRDB applies a migration registered before an already-applied one** (§8.3). Relevant
  only if option F is chosen. Not verified by reading GRDB or by a test.
- **Whether Room rejects or ignores a database that carries a table it has no entity for.** Relevant
  only to option F and to an Android restore the owner will not perform.
- **What `Tools/parity_ledger.py` and `parity_ratchet.py` report** for new public declarations in
  `StrandAnalytics` with no twin claim. Not run. The stored authority already fails to reproduce on
  this branch (BASELINE.md), so the effect could not be isolated by reading.
- **Stage 2's names and its section order on this branch.** The packet builder does not exist here.
  §7.5 fixes this stage's lines; where they are placed belongs to the stage 2 specification.
- **The exact x-values each `NoopLineChart` site plots** (`MetricExplorerView.swift:2356`,
  `TrendsView.swift:1039`). Both pass date-based points; whether every point sits on a day boundary
  was not traced. The implementer of 5-7 confirms per site and uses the `values` constructor.
- **Whether `evidenceStartDay` reaches back to the fixture's E1 on 2031-03-26** (§13.2). It follows
  from stage 1's parameters and was not recomputed here.
- **Row layout at the largest text size inside `NoopBarChart`**, whose bars already carry a caption
  row. Left to G1.
- **Whether any reader of `APP_VERSION_CHANGED` exists outside the Apple targets** (for example in a
  support tool). None was found under `Strand/`, `StrandiOS/` or `Packages/`.
- **The token names in §10.5** are proposals. `NoopTheme.Layout` was read for its existing members
  only (`Packages/StrandDesign/Sources/StrandDesign/NoopTheme.swift:114-139`).
- **Whether the owner's real history holds any `moments`.** Irrelevant to the design; noted because
  that list silently drops entries beyond 500.
- **Nothing was compiled or run.** Every API in §6, §9.3 and §10.5 is a design, not a build result.

## 17. Design approval record (G1)

Not yet submitted. Frames required, round 7: Health row (2); Events screen (every row of §10.2);
event sheet (every row of §10.3); delete confirmation; chart marks on a weekly curve, a thirty-day
bar chart and a line chart, each with no event, one event, a dense run, and a missed week; the
caption in each state of its table; the scorecard note in each state of §10.6; the two Settings
switches. Two options to choose between, as their own frames: a dot per covered position (the
recommendation) against a dot at the start and an open dot at the end.
