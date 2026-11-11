# Stage 5 specification — events layer

Gate G0 for stage 5 of the health super-app workstream. Read [CONTEXT.md](../CONTEXT.md),
[ROADMAP.md](../ROADMAP.md) (stage 5, and stages 1, 2 and 6 which feed or consume it),
[QUALITY-GATES.md](../QUALITY-GATES.md) and the stage 1 specification ([stage-1.md](stage-1.md),
especially §8, §9, §14 and rulings R25 to R43) first.

Verified against the source at commit `0b89b814` (branch `personal/superapp-5-events-spec`, cut from
`personal/superapp-1-screens`). Every `path:line` below is as of that commit. Paths are relative to
the repository root. Nothing was built or run for this document; it is a reading of the code.

Reconciled on 11 November 2026 with the cross-stage check of all seven specifications; §18 lists
what changed, including a second pass under the orchestrator's rulings, and the shared scaffolding
this stage expects. Where a line number below falls in a
file an earlier stage edits first (§14.2), the edit is located by the named function or comment, not
by the number.

This file contains no personal measurement, date, medication or injury detail. Every example belongs
to the synthetic "Fixture Person" of §13, who is the stage 1 fixture person on the stage 1 fixture's
2031 calendar (stage 1 §13). There is one Fixture Person across all stages.

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
- The body rows of the coach packet's events section, as one pure function written in stage 2's
  packet grammar (§7.5); sensitive events excluded unless the caller asks for them. The section
  itself joins the packet in the separate "packet v2" change (§14.3), not in this stage.
- The specification of the private-events packet setting (§9.6). It is specified here and **built by
  the packet v2 change**, with its one reader. This stage's own milestone ships no such switch.
- Backup round trip.

**One rule, stated the same way in stages 1, 5 and 6.** A diet break or a deload is an **event**.
Phases (stage 1) are only the long blocks. The scorecard keeps reporting during an event, and the
event is noted under the verdict (§10.6). Nothing in this stage creates, ends or changes a phase.

**Out of scope**

- Any change to `CutScorecard.evaluate`, its input, or any score, estimate or analytic. Events are
  display context only. Nothing is computed from them.
- A dated override of the intake targets. None is built. Stage 3's `IntakeSettings.targets(on:)`
  keeps its day parameter and returns the same targets every day; this stage supplies nothing to it.
  During a diet-break event the intake screen may show the event caption of §10.5 and nothing more;
  that one call is not in any work package here. A real override is a later change with its own
  specification.
- The packet's section case, heading, version number, size budget, whole-packet goldens and the
  Claude-side text. They belong to stage 2's grammar and to the packet v2 change (§7.5, §14.3).
- The stored key, the store property, the Settings switch and the strings of the private-events
  packet setting. §9.6 specifies them; the packet v2 change builds them (§14.1).
- Events in the in-app Coach context (`AICoach.buildContext`, `buildFullContext`). See §3, C7.
- Events in any widget, Live Activity, notification or the watch. Not sensitive ones, not any.
- Reminders, streaks, prompts to log an event.
- A time of day on an event. Events are whole local days (§7.1).
- The niggle log and the checkpoint timeline (stage 6). §14.3 states what stage 6 can reuse.
- The existing "Mark a Moment" action, the `event` table and the Journal. None is read or written.
- A migration, a new target, an entitlement, a network path, a Health read. None is needed.
- Android. Skipped by the owner's decision (R43). §9.4 states the drift in the one shared contract.
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
| 12 | A feature flag pattern exists: one observable copy of a `noop.*` Bool | Confirmed. The shared scaffolding (§18) lands `ObservableDefaultsFlag`, the same class with the key as a parameter; this stage uses it and writes no copy | `Strand/Data/CutScorecardModel.swift:18-66` |
| 13 | The debug demo harness maps `--demo-screen <name>` to a screen | Confirmed; at this commit unknown names fall through to `ScorecardDemo.screen(named:)`. The shared scaffolding (§18) replaces that line with one ordered registry of demo providers | `StrandiOS/App/StrandiOSApp.swift:466-469`, `:569-623`; `StrandiOS/Scorecard/ScorecardDemo.swift:33` |
| 14 | Stage 2's coach packet exists | **Not on this branch.** No `CoachPacket` symbol in the tree. Its grammar is fixed by the stage 2 specification (stage 2 §7), and stage 2 merges before this stage (§14.3) | search of the tree; [stage-2.md](stage-2.md) |
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
| The coach packet assembler, in the packet v2 change | Calls `PersonalEvents.packetLines` with the store's events and the store's `packetIncludesSensitive`, a property the same change adds (§9.6) |
| `TimelineEventSource` (stage 6, `Strand/Data/TimelineSources.swift`) | Reads the store's `events` property, passes it through `PersonalEvents.visible(_, includeSensitive: false)`, then keeps diet breaks and deloads. A private event is absent from the timeline |
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
| Packet rows | `PersonalEvents.packetLines`, `PersonalEvents.packetRowLimit`, `PersonalEvents.packetByteAllowance` (an extension) | `Packages/StrandAnalytics/Sources/StrandAnalytics/PersonalEventsPacket.swift` |
| Day keys (shared scaffolding, not this stage's file) | `CanonicalDay` | `Packages/StrandAnalytics/Sources/StrandAnalytics/CanonicalDay.swift` |
| Store | `PersonalEventStore`, `PersonalEventStoreError` | `Strand/Data/PersonalEventStore.swift` |
| Presenter | `PersonalEventPresenter`, `PersonalEventRow`, `PersonalEventsPresentation`, `PersonalEventCaption`, `PersonalEventDeleteConfirmation` | `Strand/Data/PersonalEventPresenter.swift` |
| Models | `PersonalEventsModel`, `PersonalEventSheetModel`, `PersonalEventDraft` | `Strand/Data/PersonalEventsModel.swift` |
| Observable flag | `PersonalEventStore.flag`, one static `ObservableDefaultsFlag(key: PersonalEventStore.enabledKey)`. There is no `PersonalEventsFlag` type | `Strand/Data/PersonalEventStore.swift`; the class is the scaffolding's `Strand/Data/ObservableDefaultsFlag.swift` |
| Chart reader | `PersonalEventChartSource` | `Strand/Data/PersonalEventChartSource.swift` |
| Chart caption view (shared with macOS) | `PersonalEventChartCaption` | `Strand/Screens/PersonalEventChartCaption.swift` |
| Mark type, layout and row | `NoopChartAxisMarks`, `ChartAxisMarkLayout`, `NoopChartAxisMarkRow` | `Packages/StrandDesign/Sources/StrandDesign/ChartAxisMarks.swift` |
| Screens | `PersonalEventsView`, `PersonalEventSheet` | `StrandiOS/Events/` |
| Scorecard note view | `ScorecardEventNoteView`, which draws `CutScorecardPresentation.eventNote` and reads no store | `StrandiOS/Events/ScorecardEventNoteView.swift` |
| Design round | `design/round-s5-events/`, frames `s5-frames.json`, plugin command `importS5` | §10 |
| Demo harness | `PersonalEventsDemo`; demo names all begin `events-` | `StrandiOS/Events/PersonalEventsDemo.swift` |
| Feature flag | `noop.personalEventsEnabled`, Bool, default `false` | `PersonalEventStore.enabledKey` |
| Stored list | `personalEvents.items`, String (JSON array) | `PersonalEventStore.itemsKey` |
| Packet setting (specified in §9.6; added by the packet v2 change, not by this stage's packages) | `personalEvents.packetIncludesSensitive`, Bool, default `false`. It stays under this prefix, not under `coachPacket.sections`: it is a fact about events | `PersonalEventStore.packetSensitiveKey`, `PersonalEventStore.packetIncludesSensitive` |
| Navigation | `RedesignRoute.personalEvents` | `StrandiOS/Redesign/RedesignRoute.swift` |
| Scorecard additions | `CutScorecardPresentation.EventNote`, `CutScorecardPresentation.eventNote`, `CutScorecardPresentation.Curve.marked`, `CutScorecardPresentationContext.events` | `Strand/Data/CutScorecardPresenter.swift` |

The store, presenter, models and chart source live under `Strand/` so `StrandTests` (macOS scheme
only) can test them, as stage 1 did (stage 1 §5).

## 6. Pure logic: the API

File `Packages/StrandAnalytics/Sources/StrandAnalytics/PersonalEvents.swift`. No store, no clock, no
`Calendar`, no `TimeZone`, no `Date`, no localisation. Every day-key question goes through the
shared `CanonicalDay` of the same module (stage 6 §6.0; landed by the scaffolding, §18):
`CanonicalDay.number(_:)` for validity, `CanonicalDay.weekStart(_:)` for the Monday of a week, and
`CanonicalDay.key(_:)` for the day six days later. This file does not call
`WeeklyDigestEngine.parseYMD` or `formatYMD` itself and declares no day-validity function of its
own.

`packetLines` and its two constants are declared in an extension in
`PersonalEventsPacket.swift`, because they call stage 2's `CoachPacket.sanitize` (stage 2 §6.2).
Keeping them in their own file lets `PersonalEvents.swift` and its tests compile before stage 2's
`CoachPacket.swift` exists.

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
}

// PersonalEventsPacket.swift
extension PersonalEvents {
    public static let packetRowLimit = 12          // event rows printed at most
    public static let packetByteAllowance = 2000   // UTF-8 bytes the events section may add to a packet
    /// The body rows of the packet's events section (§7.5). No heading, no blank line, no "\n".
    public static func packetLines(events: [PersonalEvent], firstDay: String, lastDay: String,
                                   includeSensitive: Bool) -> [String]
}
```

Every function is total: it never throws and never traps, for any input. "A valid day" below always
means `CanonicalDay.number(day) != nil`.

## 7. Algorithm and format

### 7.1 Days, not instants

An event is a run of **local calendar days**. `startDay` and `endDay` are canonical ten-character
keys (stage 1 ruling R5): a day is valid only when `CanonicalDay.number(day) != nil`, which holds
for `yyyy-MM-dd`, years 0001 to 9999, naming a real date, in exactly that ten-character form. The
rule has one definition, `CanonicalDay`, which the scaffolding pins to `CutScorecard.weekStart` with
a test; this stage adds no second one. Canonical keys of that range order lexicographically in date
order, so every comparison below is a string comparison and no day arithmetic is needed for overlap.

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
- `invalidStartDay` / `invalidEndDay`: `CanonicalDay.number` of the day is nil.
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
`CanonicalDay.weekStart(weekStart)`; otherwise it returns `[]`. The range is
`[weekStart, CanonicalDay.key(CanonicalDay.number(weekStart)! + 6)]` (the force-unwrap is notation:
the value is known non-nil at that point, and the implementation binds it).

`coveredSlots` returns one Bool per slot, in order: whether any event overlaps `[firstDay, lastDay]`.
An invalid slot is false. Sensitive events count: a dot carries no text (§10.5).

### 7.5 Visibility and the packet rows

`visible(events, includeSensitive:)` is `normalized(events)` with `sensitive` events removed unless
`includeSensitive` is true. It is the one function that applies the flag. The presenter, the chart
caption, `packetLines` and stage 6's `TimelineEventSource` all go through it. Two readers pass
`false` always: the timeline (a private event is **absent** there, whatever its kind) and every
caption or note outside the Events screen that then words what it shows from `sensitive` (§10.5,
§10.6).

**Who owns what in the packet.** Stage 2 owns the packet grammar (stage 2 §7): headings of the form
`== NAME ==`, two-space indented rows, oldest first, enum values printed as their raw values, free
text through `CoachPacket.sanitize`, a size budget that holds by construction. This stage owns only
the **body rows** of the events section, returned by `packetLines`. The heading `== EVENTS ==`, the
blank line between sections, the `CoachPacketSection` case, the removal of `events` from the
header's `not-recorded-by-app` line, the version number and the whole-packet goldens are written by
the packet v2 change (§14.3) under stage 2's rules. `packetLines` never returns a heading.

**The rows.** English whatever the interface language, ISO day keys, no tabs, no trailing spaces.
Stage 2 §7.12 is the authority for the grammar (rules G-2 to G-8); where that section and this one
differ, that section is right and this one is corrected. The example below is golden G-E1 with
private events included: the fixture events of §13.1 over the range 2031-03-13 to 2031-03-26. Stage
2 §7.12 shows the same rows for the same fixture events, taken from goldens G-E1, G-E3 and G-E6;
§13.3 holds all six goldens and is the one text both documents copy from:

```
entered by the owner, whole local days, oldest first:
  2031-03-10..2031-03-16: travel; note "Fixture trip"
  2031-03-26: custom "Fixture change"; note "Fixture note"
```

- Let `listed` be the events of `visible(events, includeSensitive:)` that overlap
  `[firstDay, lastDay]`, in `normalized` order (oldest start first).
- **Nothing listed:** the result is the single row `events: none listed in range`. "Listed", because
  hidden sensitive events may exist and the packet must neither reveal nor deny them. An invalid
  range (either day invalid, or `lastDay < firstDay`) gives the same single row.
- **Otherwise** row 1 is the fixed intro `entered by the owner, whole local days, oldest first:`.
- **Row cap.** At most `packetRowLimit` (12) event rows are printed: the **last** twelve of `listed`,
  still oldest first. When `listed` holds more, the row
  `  (<m> earlier events in range not shown)` comes directly after the intro, where `m` is
  `listed.count - 12`. `m` counts only listed events; a hidden sensitive event is never counted.
- **An event row** is two spaces, the dates, `: `, the name, and an optional note:
  `  <dates>: <name>` or `  <dates>: <name>; note "<n>"`.
  - Dates: `s` alone when `e == s`; `s..e`; `s..ongoing` when `e == nil`. The stored days are
    printed whole, not clipped to the range.
  - Name: the kind's raw value (`travel`, `illness`, `dietBreak`, `deload`, `supplementChange`);
    for `custom`, `custom "<l>"` where `<l>` is `CoachPacket.sanitize(label)`.
  - Note: `<n>` is `CoachPacket.sanitize(note)`. An event with a nil note has no note part.
  - `CoachPacket.sanitize` (stage 2 §6.2) turns control characters and line breaks into spaces,
    collapses runs of spaces, trims, replaces `"` with `'` and cuts at a character boundary to at
    most 48 UTF-8 bytes; empty input gives `unnamed`. This function applies no other cleaning, so a
    quoted value can never contain `"` or a line break.
- Nothing else: no id, no `createdAt`, no count of hidden events, no sensitivity marker.

**Size.** The widest event row is 140 bytes (two spaces, two ten-byte days joined by `..`, `: `,
`custom "` + 48 + `"`, `; note "` + 48 + `"`), the intro is 53 and the "earlier" row is at most 57
(an `Int` has at most 19 digits). With one `\n` per row the rows total at most
`54 + 58 + 12 × 141 = 1,804` bytes; with stage 2's heading line and the blank line before it, 1,818.
`packetByteAllowance` is 2,000. The packet v2 change adds this fixed allowance to stage 2's budget
(`8000 + 220 × rangeDays`, stage 2 §7.10); the bound holds by construction, for any range length and
any number of stored events, and a test builds the widest input and asserts it (§12.1).

**The privacy scan.** The rows are part of the packet text that stage 2's scan reads, and that scan
fails closed (stage 2 §7.11). A label or note that looks like an email address, a file path or a
device identifier blocks the whole packet, and stage 2's blocked state says so. `packetLines` does
not scan, does not drop a row and does not rewrite a note to get past the scan.

**A row the scan would block (stage 2 G-8).** This stage's tests include a note that looks like an
email address and one that looks like a path, and assert that `packetLines` returns each row with
that text intact (§12.1). The whole-packet test that the scan then blocks belongs to packet v2.

**The setting.** The `includeSensitive` argument is a plain parameter in this stage: the tests pass
`false` and `true`, and no stored setting exists yet. The stored setting
`personalEvents.packetIncludesSensitive`, its switch and the packet sheet's read-only caption are
specified in §9.6 and built by the packet v2 change, together with the one caller of `packetLines`.

## 8. Storage decision

### 8.1 Options

| # | Home | Migration | What it costs | R42 |
|---|---|---|---|---|
| A | The `event` table under a sentinel device id | No | The table is the telemetry stream of straps and rings and one reader feeds scoring (§4.1). Every personal insert moves `analysisFingerprint`'s whole-table `MAX(rowid)` (`Reads.swift:221`), so logging a trip would make the app believe sensor data changed. Rows are insert-only: edit and delete need new SQL in `WhoopStore`, whose neighbours are declared Kotlin twins. The key `(deviceId, ts, kind)` has no id and collides for two events of one kind on one start; a synthetic `ts` would make the range reads meaningless. Storage counts and the access tool would count personal rows as sensor rows (`Reads.swift:981`, `LocalAccessCore.swift:346`). One real advantage: Room has the same table, so rows would survive an Android round trip with no contract change | Met with a sentinel id (C3) |
| B | **A JSON list in settings, on the backup whitelist** (the stage 1 phases pattern) | No | Not transactional with the database. The whole list is rewritten on each change (events are few; a year of heavy use is under 100 KB). The value travels in the readable `settings.json` entry of the backup, whose header asks that the file stay safe to share (`BackupSettings.swift:11-15`); the archive already contains the health database, but an event note in plain JSON is easier to read than a SQLite row. The Swift whitelist gains a key the Kotlin one does not have (§9.4). Not queryable in SQL | Met by construction: no device id exists in the store |
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

A third key, `personalEvents.packetIncludesSensitive`, is specified in §9.6. It does not exist until
the packet v2 change.

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
    static let shared: PersonalEventStore

    init(defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init,
         makeId: @escaping () -> String = PersonalEventStore.randomId)

    @Published private(set) var revision: Int      // moves on every change to itemsKey, whoever writes it
    var isEnabled: Bool { get }                    // reads enabledKey
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

The observable copy of the flag is one line, a static on the store:

```swift
extension PersonalEventStore {
    static let flag = ObservableDefaultsFlag(key: PersonalEventStore.enabledKey)
}
```

`ObservableDefaultsFlag` is the scaffolding's class (stage 6 §9.4): the body of `CutScorecardFlag`
with the key as a parameter, a published read-only `isEnabled` and `set(_:)`. Views observe
`PersonalEventStore.flag`; the Settings switch calls `PersonalEventStore.flag.set(_:)`. This stage
declares no flag class of its own. `PersonalEventStore.isEnabled` reads the same key from the
store's own defaults object, so a store built over an injected suite in a test follows that suite.

### 9.4 Backup whitelist

| Canonical key | JSON kind | Swift storage key | Joins the whitelist |
|---|---|---|---|
| `personalEvents.items` | String | `personalEvents.items` | **Yes, Swift only** |
| `noop.personalEventsEnabled` | — | — | No. A `noop.*` toggle is per install (`BackupSettings.swift:40-42`); after a restore the feature is off until switched on, and the events are there when it is |
| `personalEvents.packetIncludesSensitive` (§9.6, packet v2) | — | — | No. A Bool cannot cross, and off is the safe direction |

Edits: one entry in `BackupSettings.whitelist` and one in `BackupSettings.appleDefaultsKey`
(`BackupSettings.swift:49-74`, `:79-95` at the base commit), and one line naming the key in the
comment block of fork-only keys that the scaffolding places above the Swift whitelist (§18). The
string is carried and never parsed there.

The file has one writer at a time, in the one order of §14.2. This stage's turn is the fifth: its
entry is written after stage 4's serialised step and before stage 6's, in the orchestrator's commit
5-7h, and sits after whatever entries the earlier stages have added. It is found by that position,
not by a line number. The same holds for `BackupSettingsTests.swift`, where this stage adds new
methods only, after the methods already there.

Restore semantics, unchanged from every other key: a backup that carries the key **replaces** this
device's list; a backup without it leaves the list alone (`BackupSettings.swift:120-127`).

**Drift from the Android contract (R43).** AGENTS.md calls the backup whitelist a byte-identical
contract between `BackupSettings.swift` and the Kotlin `BackupSettingsCodec`. This stage adds
`personalEvents.items` to the Swift side only, so the two whitelists knowingly differ by this key:
a backup made on the iPhone and restored by the Android app loses the events (unknown keys are
dropped on decode), and a backup made by the Android app never carries them and leaves the iPhone's
list untouched on restore. No Kotlin file is edited, and no existing test compares the two
whitelists as wholes, so nothing fails. The fork-only comment block and the fork's personal
documents record that the Kotlin whitelist is behind.

**What the backup now contains.** Labels and notes of sensitive events, in clear text in
`settings.json`. The backup is already an unencrypted copy of the health database (CONTEXT §7 item
7). This raises the priority of the encrypted-backup backlog item and is put to the owner as S3.

### 9.5 Ownership (R42)

The store has no device id. Disconnecting, forgetting or deleting a strap, re-pointing the active
id, and adopting a serial identity do not read or write it. Erasing all of the app's data on purpose
removes it with everything else.

### 9.6 The private-events packet setting — specified here, built by packet v2

Orchestrator ruling: this setting ships with packet v2, not with this stage's first milestone,
because nothing reads it until the packet has an events section. This section is its complete
specification. The packet v2 change (§14.1) builds every item below in the same change that adds
the caller of `packetLines`; stage 2 §7.12 reads the setting and specifies nothing about it.

| Item | Specification |
|---|---|
| Key | `personalEvents.packetIncludesSensitive`, Bool, default `false`, in `UserDefaults.standard`. Never in the App Group suite and not on the backup whitelist (§9.4) |
| Store | Two additions to `PersonalEventStore`: `static let packetSensitiveKey = "personalEvents.packetIncludesSensitive"` and `var packetIncludesSensitive: Bool { get set }`. The property reads and writes the store's own defaults object at each access and caches nothing. It does not depend on `isEnabled` |
| The one reader | Stage 2's packet assembler. It reads the property **once per assembly**, passes the value as `includeSensitive:` to `packetLines`, and hands the same value to the packet sheet for its caption. The rows and the caption therefore come from one read and cannot disagree |
| The one writer | A switch in this stage's Events card in Settings (§10.7), beneath the "Personal events" switch: "Include private events in the coach packet", off by default, footnote "Private events and their notes stay out of the packet unless this is on." It is mounted only while **both** `noop.personalEventsEnabled` and stage 2's `noop.coachPacketEnabled` are on, so it is never shown when nothing would read it |
| Packet sheet | A read-only caption with no control: "Private events: left out" or "Private events: included", then "Change this in Settings." No count of private events appears there or anywhere else outside the Events screen (S11) |
| Event sheet | One added sentence under the Private switch, shown beneath this stage's sentence while `noop.coachPacketEnabled` is on: "Private events stay out of the coach packet unless you include them in Settings." |
| Strings | The switch label, its footnote, the three caption strings and the event-sheet sentence join the catalogue in the packet v2 change (§11) |
| Tests, added by the packet v2 change | In `PersonalEventStoreTests.swift`: `testPacketSwitchDefaultsToOffAndRoundTripsThroughTheStore`, `testPacketSwitchIsIndependentOfTheEventsFlag`. In `BackupSettingsTests.swift`: `testPersonalEventsPacketSwitchIsNotExported`. In `Tools/test_personal_events_boundaries.py`: `test_packet_switch_has_one_writer_and_one_reader` (the literal key occurs only in `PersonalEventStore.swift` and tests; `packetIncludesSensitive` occurs outside tests only there, in `SettingsView.swift` and in stage 2's assembler). The whole-packet goldens with the switch off and on are packet v2's, on stage 2's fixture |

Until packet v2 lands the key is never written, the property does not exist, and a private event
cannot reach the packet by any path: version 1 of the packet has no events section.

## 10. Screens and states

Frames are designed at G1 in the round `design/round-s5-events/` (frames file `s5-frames.json`,
plugin command `importS5`), with the pipeline stage 1 used (`design/round6-scorecard/`,
`design/tools/serve.py`). The folder and the `importS5` command in `design/figma-plugin/code.js` and
`manifest.json` are created by the orchestrator's scaffolding commit (§18), with the other stages'
commands; the designer of this stage edits only files inside `design/round-s5-events/`. Every state
below needs a frame at the default text size and at the largest accessibility size.

Three surfaces are shared with other stages and are designed **once for all stages**, in one
combined frame set drawn by the orchestrator's designer and approved once: the Health tab's "More
health" card, the Settings cards and the scorecard screen. That frame set is the authority for the
order. This stage's frames show its own part inside that approved layout and do not re-open it.

**This stage's position.** The Settings cards and the Health tab rows share one order, top to
bottom, each entry present only while its own flag is on. **Events is the fifth entry of that list:
directly after Body record and directly before Niggle log.** When neither neighbour is mounted, it
takes the place the remaining entries leave it. This document states no other entry's position.

### 10.1 Entry points

- A row "Events" in the Health tab's "More health" card
  (`StrandiOS/Redesign/RedesignHealthView.swift:476-482`, `:523-532`), mounted only while this
  stage's flag is on, whatever the scorecard flag says. Its value is the count of events overlapping
  today ("1 now"), or nothing. Its place among the card's rows is the fifth entry of the one order
  (§10): after "Body record", before "Niggle log".
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

**During a diet break or a deload the scorecard keeps reporting.** A diet break or deload is an
event, never a phase (§1), so the active phase, the judged week and the verdict are exactly what
they would be with no event stored. The event is named in the note under the verdict and marked on
the curves. That is the whole effect.

`CutScorecardPresentationContext` gains `events: [PersonalEvent] = []` and
`CutScorecardPresenter.present` gains two outputs. `CutScorecardModel.load()` fills `events` from
`PersonalEventStore.events`, captured before its first suspension with its other inputs
(`CutScorecardModel.swift:148-153` at the base commit).

This edit is made in this stage's turn of the one order (§14.2), the fifth. By then `load()` calls
`CutScorecardInputBuilder.evaluation(today:)` (stage 2 §8.2) and the model's initialiser carries the
parameters earlier turns gave it; this stage changes neither. The edit is located by the function
name `load()`, not by a line number. The
events go from `load()` into the presenter's context only. They are never passed to
`evaluation(today:)`, to the builder or to `CutScorecardInput` (§12.5 asserts it). On the screen
the note sits directly under the verdict, as the combined scorecard frame shows; it is one view,
`ScorecardEventNoteView`, in this stage's own file, so the shared `ScorecardView.swift` gains one
call and one argument (5-7h).

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

In the iPhone-only block that holds the scorecard card (`Strand/Screens/SettingsView.swift:462-468`,
`:1860-1871` at the base commit): one card, "Events", holding one switch, "Personal events", which
calls `PersonalEventStore.flag.set(_:)`. The card carries the switch that turns the feature on, so
it is drawn on the iPhone whether the flag is on or off, as the scorecard card is; the Health row,
by contrast, is present only while the flag is on. If the combined frame set draws the off state
differently, the frame set is right. Its place among the Settings cards is the fifth entry of
the one order (§10): after the Body record card, before the Niggle log card.

This stage adds nothing else to Settings. The second switch, "Include private events in the coach
packet", is specified in §9.6 and added to this card by the packet v2 change.

### 10.8 Widgets and notifications

None. This stage adds no widget kind, no widget field, no Live Activity field, no notification and
no notification text. §12.5 proves the absence.

### 10.9 App-side API

The types the app-target tests of §12.3 are written against. All are in `Strand/Data/` (§5). Text
is produced for `locale`; tests pass `Locale(identifier: "en_GB")` and compare against §11.

```swift
struct PersonalEventRow: Equatable, Identifiable {
    var id: String                 // the event's id
    var title: String              // the kind's name, or the owner's label; shown in full here only
    var dateText: String           // "10 – 16 Mar", "22 Jan", "Since 19 May", "From 2 Jul"
    var noteFirstLine: String?     // nil when the event has no note
    var isPrivate: Bool            // shows the "Private" tag
    var offersEndToday: Bool       // true for an ongoing event that has started
}

struct PersonalEventsPresentation: Equatable {
    enum State: Equatable { case empty, rows, storeUnreadable }
    var state: State
    var now: [PersonalEventRow]          // overlapping today; newest start first
    var upcoming: [PersonalEventRow]     // start after today; newest start first
    var earlier: [PersonalEventRow]      // ended before today; newest start first
    var unreadableEntriesText: String?   // "%lld entries could not be read. They are kept."
    var healthRowValue: String?          // "%lld now"; nil when nothing overlaps today
}

struct PersonalEventCaption: Equatable {
    var lines: [String]            // at most two, "Travel · 10 – 16 Mar" or "Private event · 26 Mar"
    var moreText: String?          // "and %lld more"
    var spokenText: String         // "Events:" then the lines and moreText, joined by ", "
}

struct PersonalEventDeleteConfirmation: Equatable {
    var title: String              // "Delete this event?"
    var detail: String             // the title and dateText of the row
    var warning: String            // "This cannot be undone."
    var confirmTitle: String       // "Delete"
    var cancelTitle: String        // "Cancel"
}

enum PersonalEventPresenter {
    /// The Events screen. The one place a sensitive label or note is turned into text.
    static func present(events: [PersonalEvent], today: String, unreadableEntryCount: Int,
                        needsAttention: Bool, locale: Locale) -> PersonalEventsPresentation
    /// One line for an event outside the Events screen: its kind name, or "Private event" when
    /// `sensitive`, then " · " and its dates. Never the label of a sensitive event, never a note.
    static func outsideLine(for event: PersonalEvent, locale: Locale) -> String
    /// The chart caption for a window; nil when no event overlaps it.
    static func caption(events: [PersonalEvent], firstDay: String, lastDay: String, today: String,
                        locale: Locale) -> PersonalEventCaption?
    static func deleteConfirmation(for event: PersonalEvent, locale: Locale)
        -> PersonalEventDeleteConfirmation
    static func kindName(_ kind: PersonalEventKind, locale: Locale) -> String
}

struct PersonalEventDraft: Equatable {
    enum Length: Equatable { case oneDay, until, ongoing }
    var kind: PersonalEventKind = .travel
    var label: String = ""
    var start: Date
    var length: Length = .oneDay
    var end: Date                  // read only when length == .until
    var note: String = ""
    var isPrivate: Bool
}

@MainActor
final class PersonalEventsModel: ObservableObject {
    init(store: PersonalEventStore = .shared, now: @escaping () -> Date = Date.init,
         timeZone: @escaping () -> TimeZone = { .current }, locale: Locale = AppLanguage.activeLocale)
    @Published private(set) var presentation: PersonalEventsPresentation   // rebuilt on store.revision
    func reload()
    func deleteConfirmation(id: String) -> PersonalEventDeleteConfirmation?
    func delete(id: String) throws
    func endToday(id: String) throws         // sets endDay to today's key; .notFound if absent
    var rawStoredText: String? { get }       // for "Copy stored text"
    @discardableResult func discardUnreadableStore() -> Bool
}

@MainActor
final class PersonalEventSheetModel: ObservableObject {
    enum Phase: Equatable { case editing, saving, failed(storeUnreadable: Bool), saved }
    /// `editing` nil: a new event with the defaults of §10.3.
    init(store: PersonalEventStore = .shared, editing: PersonalEvent? = nil,
         now: @escaping () -> Date = Date.init, timeZone: @escaping () -> TimeZone = { .current })
    @Published var draft: PersonalEventDraft
    @Published private(set) var phase: Phase
    func setKind(_ kind: PersonalEventKind)  // moves isPrivate to the kind's default unless touched
    func setPrivate(_ value: Bool)           // marks the switch as touched
    var issues: [PersonalEventIssue] { get } // of the draft as it would be saved
    var canSave: Bool { get }                // no issue and phase is .editing or .failed
    var isPlanned: Bool { get }              // start day after today's key
    var noteRemaining: Int? { get }          // nil until the note reaches 240 characters
    func save()                              // captures the draft, then writes once; sets phase
}
```

`PersonalEventChartSource` has the four functions of §10.5 and this initialiser:
`init(store: PersonalEventStore = .shared, locale: Locale = AppLanguage.activeLocale)`. Its
`MarkStyle` is `enum MarkStyle { case points, bars }`. Each function reads `store.events` once per
call.

A day key for "today", for a draft's start and for a draft's end is
`LocalDayWindows(timeZone: timeZone()).dayKey(for:)` of the date, taken once per operation.

## 11. User-facing strings

English source strings, all through `Strand/Resources/Localizable.xcstrings` in the ten locales
(`de`, `en`, `es`, `fr`, `it`, `pl`, `pt-PT`, `ru`, `zh-Hans`, `zh-Hant`). The packet rows of §7.5
are fixed English and are **not** localised. The catalogue has one writer at a time across all
stages, in the one order of §14.2; this stage's Localiser runs as the last step of this stage, the
fifth turn.

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
| Sheet | "New event", "Edit event"; "Kind"; "Name"; "A name is needed"; "Starts"; "Length"; "One day", "Until", "Ongoing"; "Ends"; "Must be on or after the start"; "Planned: this starts in the future"; "Note"; "Private"; "Private events show as \"Private event\" outside this screen."; "Save"; "Could not save. Try again." |
| Delete | "Delete this event?"; "This cannot be undone."; "Delete"; "Cancel" |
| Caption | "%@ · %@"; "and %lld more" |
| Scorecard note | "Events this week"; "Earlier in the weeks behind this verdict"; "Shown for context. Events do not change the verdict." |
| Settings | Card title "Events"; "Personal events" |
| Spoken | "Events:" |
| The packet setting of §9.6 (all added to the catalogue by the packet v2 change, not by this stage's Localiser) | Settings: "Include private events in the coach packet"; "Private events and their notes stay out of the packet unless this is on." Event sheet: "Private events stay out of the coach packet unless you include them in Settings." Packet sheet caption: "Private events: left out"; "Private events: included"; "Change this in Settings." |

No string states or implies a cause ("because you travelled"), a diagnosis, or advice.

## 12. Test plan

Tests are written from this document before the implementation, by an agent who has not seen it.

### 12.1 Pure logic — `Packages/StrandAnalytics/Tests/StrandAnalyticsTests/PersonalEventsTests.swift`

Validation
- `testCanonicalDaysPassAndUnpaddedOrImpossibleDaysAreInvalidStartOrEndDays` (through `issues`:
  `2031-03-10` has no issue; `2031-3-10`, `2031-02-30`, `0000-01-01` and the empty string give
  `invalidStartDay` as a start and `invalidEndDay` as an end)
- `testDayValidityAgreesWithCanonicalDayForGeneratedStrings` (fixed seed, 500 strings: `issues`
  reports `invalidStartDay` exactly when `CanonicalDay.number` is nil)
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

Visibility
- `testVisibleRemovesSensitiveEventsUnlessIncluded`
- `testVisibleRemovesAPrivateDeloadAndAPrivateDietBreak` (the flag decides, not the kind: fixture
  variant V9)
- `testVisibleKeepsNormalizedOrder`

Packet rows — a separate file, `PersonalEventsPacketTests.swift`, because it needs stage 2's
`CoachPacket.sanitize` and is added by WP 5-9 (§14.1)
- `testPacketLinesFourteenDayGoldenWithSensitiveOff` and `…WithSensitiveOn` (G-E1, §13.3)
- `testPacketLinesTwentyEightDayGolden` (G-E2; identical with the switch on or off)
- `testPacketLinesOngoingGoldenWithSensitiveOn` (G-E3)
- `testPacketLinesOneDayGolden` (G-E4)
- `testPacketLinesWithNothingListedSayNoneListed` (one row, no intro)
- `testPacketLinesWithOnlySensitiveEventsAndSensitiveOffSayNoneListed` (G-E3 with the switch off)
- `testPacketLinesPrintWholeStoredDaysNotClippedToTheRange` (G-E5)
- `testPacketLabelAndNoteGoThroughCoachPacketSanitize` (a `"` becomes `'`; a line break and a run
  of spaces become one space; a 280-character note is cut to at most 48 UTF-8 bytes at a character
  boundary; the expected text is built by calling `CoachPacket.sanitize` in the test)
- `testPacketLinesStopAtTheRowLimitWithAnEarlierNotShownRow` (G-E6)
- `testEarlierNotShownCountsOnlyListedEvents` (G-E6 plus three sensitive one-day events in range,
  switch off: the count stays 3)
- `testExactlyTheRowLimitPrintsNoEarlierRow`
- `testEveryRowAfterTheIntroStartsWithTwoSpacesAndNoRowHasATabATrailingSpaceOrALineBreak`
- `testPacketLinesNeverReturnAHeading` (no row begins `==`)
- `testPacketLinesContainNoIdAndNoCreatedAt`
- `testPacketLinesForAnInvalidRange`
- `testARowWhoseNoteLooksLikeAnEmailAddressOrAPathIsReturnedIntact` (stage 2 G-8: the row is neither
  dropped nor rewritten here; blocking is the packet scan's work, tested in packet v2)
- `testWidestPacketRowsStayUnderTheByteAllowance` (twenty events in range, each `custom` with a
  40-character label of four-byte characters, a 280-character note and an end day; the rows joined
  with one `\n` each, plus 14 bytes for stage 2's heading and blank line, are at most
  `PersonalEvents.packetByteAllowance`)
- `testRowLimitIsTwelveAndByteAllowanceIsTwoThousand`

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
- `testStoreFlagIsAnObservableDefaultsFlagOverTheEnabledKey` (`PersonalEventStore.flag` follows a
  write to `noop.personalEventsEnabled` made by another writer, and `set(true)` writes that key)
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
- `testHealthRowValueCountsEventsOverlappingTodayAndIsEmptyWithNone`
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
- `testDietBreakAndDeloadLeaveTheVerdictAndTheActivePhaseUnchanged` (fixture E2 and E3: for every
  fixture week they overlap, the presentation with events differs from the one without only in
  `eventNote` and `marked`)

Backup — `Packages/WhoopStore/Tests/WhoopStoreTests/BackupSettingsTests.swift` (extended)
- `testPersonalEventsRoundTripAsOneString`
- `testPersonalEventsFlagIsNotExported` (the packet setting's twin,
  `testPersonalEventsPacketSwitchIsNotExported`, is added by packet v2, §9.6)
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
- `test_notification_producers_never_name_personal_events`: none in the eight files that build
  notification content (`Strand/App/AppModel.swift` excepted by a narrower pattern on its
  notification function; `Strand/System/BatteryNotifier.swift`, `CoachBriefScheduler.swift`,
  `IllnessNotifier.swift`, `StrainTargetNotifier.swift`, `WeighInReminder.swift`,
  `WindDownNudge.swift`, and stage 3's `Strand/System/IntakeCutoffReminder.swift`), and the test
  fails if a new file under `Strand/` or `StrandiOS/` builds `UNMutableNotificationContent` without
  being added to the list. Seven of the eight exist at the base commit. The eighth is stage 3's:
  whichever of stages 3 and 5 merges second adds it to the list in the same commit. Stage 3 merges
  first under the build order, so this stage's test is written with all eight. If stage 3's
  reminder is not built, the entry is left out, because `test_allowlists_still_match` fails on a
  listed file that does not exist.
- `test_coach_context_never_reads_personal_events`: none in `Strand/AI/`.
- `test_scorecard_logic_never_sees_events`: none in `CutScorecard.swift` or
  `CutScorecardInputBuilder.swift`.
- `test_app_group_suite_is_never_given_the_events`: no file writes a `personalEvents.` key through
  `UserDefaults(suiteName:`.
- `test_personal_events_declare_no_day_rule_of_their_own`: `PersonalEvents.swift` and
  `PersonalEventsPacket.swift` contain no `parseYMD(`, no `formatYMD(` and no `isValidDay`; each
  day-key question there is a `CanonicalDay.` call.
- `test_no_flag_class_is_cloned`: no file declares `PersonalEventsFlag`, and
  `noop.personalEventsEnabled` is observed only through `ObservableDefaultsFlag`.
- `test_packet_lines_has_at_most_one_production_caller`: `packetLines(` occurs outside tests only in
  `PersonalEventsPacket.swift` and, once the packet v2 change has merged, in stage 2's assembler.
- `test_no_packet_setting_without_its_reader`: while no production file calls `packetLines(`, no
  file under `Strand/` or `StrandiOS/` contains `packetIncludesSensitive` or the literal
  `personalEvents.packetIncludesSensitive`. Once the caller exists the check passes without
  condition, and packet v2's own scan (§9.6) takes over.
- `test_timeline_reads_events_only_through_visible`: when `Strand/Data/TimelineSources.swift` exists
  and names `PersonalEventStore`, it also contains `PersonalEvents.visible(` with
  `includeSensitive: false`. The check is skipped, and reported as skipped, while the file does not
  exist (stage 6 merges after this stage); stage 6's own test of a private deload is the behavioural
  half.
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
- `testPacketRowsWithSensitiveExcludedContainNoSensitiveLabelOrNote` (`packetLines` with
  `includeSensitive: false` over the fixture; added with WP 5-9)
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
| F6 | `packetLines` prints a hidden-count line, or counts hidden events in the "earlier" row | `testPacketLinesWithOnlySensitiveEventsAndSensitiveOffSayNoneListed`, `testEarlierNotShownCountsOnlyListedEvents` |
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
| F19 | The flag added to the whitelist | `testPersonalEventsFlagIsNotExported` |
| F20 | Thinning drops the last mark of a run | `testThinningKeepsTheFirstAndLastMarkOfEveryRun` |
| F21 | Bar marks placed at index over count minus one | `testBarsPlacesIndexPlusHalfOverCount` |
| F22 | Caption and marks read the store separately, one filtered | `testMarksAndCaptionAreResolvedFromTheSameEvents` |
| F23 | The row cap removed from `packetLines` | `testPacketLinesStopAtTheRowLimitWithAnEarlierNotShownRow`, `testWidestPacketRowsStayUnderTheByteAllowance` |
| F24 | A note printed without `CoachPacket.sanitize` | `testPacketLabelAndNoteGoThroughCoachPacketSanitize` |
| F25 | `packetLines` returns the `== EVENTS ==` heading as its first row | `testPacketLinesNeverReturnAHeading` |
| F26 | `visible` keeps a sensitive event whose kind is not sensitive by default | `testVisibleRemovesAPrivateDeloadAndAPrivateDietBreak` |
| F27 | A private day-validity function written inside `PersonalEvents.swift` | `test_personal_events_declare_no_day_rule_of_their_own` |
| F28 | The presenter suppresses the verdict while a diet break overlaps the judged week | `testDietBreakAndDeloadLeaveTheVerdictAndTheActivePhaseUnchanged` |
| F29 | The packet switch added to Settings and the store in this stage, before `packetLines` has a caller | `test_no_packet_setting_without_its_reader` |

### 12.7 Parity

**Written disposition (R43). Android is skipped; this stage has no Kotlin work.**

- `PersonalEvents` (pure logic in `StrandAnalytics`) has no Kotlin twin. Android has no events
  surface in this workstream. Each public declaration carries the comment "No Kotlin twin:
  iPhone-only by the owner's decision (stage 1 ruling R43)."
- `ChartAxisMarks` is `StrandDesign`, which has no Kotlin counterpart by design.
- The one stored shape that crosses a contract shared with Android is the whitelist key. Its drift
  is stated in §9.4.
- The gate script's Android rows are waived by flag and reported as waived (`Tools/personal/gate.sh`,
  `--waive android`), never as passed.
- What the parity ledger and ratchet print for new one-sided declarations was not run (§16).

### 12.8 Simulator and rehearsal

- Every frame of `design/round-s5-events/s5-frames.json` reproduced from `PersonalEventsDemo` through
  `--demo-screen events-<frame id>` at the default and largest text size, Reduce Motion on and off;
  add, edit, delete, end-today and the unreadable-store path exercised by tapping. Captures come
  from the simulator and the demo names, never from the phone.
- The demo's data is the one Fixture Person: the stage 1 series (weigh-ins on Wednesdays from
  2031-01-08, 100.0 kg falling towards the 94.0 kg target, protein floor 100 g, week 10 missed) with
  the events of §13.1 added. `PersonalEventsDemo` builds its scorecard states from the stage 1 demo
  fixture and does not define a second set of weights.
- Side-by-side captures of each adopting chart with the flag off against the base commit: identical.
- Real-data rehearsal (0B-7), run privately in a simulator: the scorecard note, a backup and a
  restore. Its results stay out of the repository.

## 13. Fixture

Everything here is invented. "Fixture Person" does not exist, and is the same invented person in
every stage: the reference is stage 1 §13. Phase "Fixture cut", kind `cut`, started Monday
2031-01-06, target 94.0 kg; weigh-ins on Wednesdays from 2031-01-08, starting at 100.0 kg; protein
floor 100 g; week 10 (2031-03-10 to 2031-03-16) has no weigh-in. This stage adds events to that
person and changes none of those values. Demo and app-target fixtures use that series (§12.8).

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

E2 and E3 are the diet-break and deload cases of §1's rule: both lie inside the one phase "Fixture
cut", no phase starts or ends on their days, and the stage 1 verdict sequence (stage 1 §13.3) is
unchanged with them stored.

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

### 13.3 Packet row goldens

Each golden is the exact array `packetLines` returns for the eight events of §13.1 (G-E6 uses its
own events). The ranges are the lengths stage 2's packet offers, ending on a fixture Wednesday.

| Golden | Range | Days |
|---|---|---|
| G-E1 | 2031-03-13 to 2031-03-26 | 14 |
| G-E2 | 2031-01-30 to 2031-02-26 | 28 |
| G-E3 | 2031-05-08 to 2031-06-04 | 28 |
| G-E4 | 2031-01-09 to 2031-01-22 | 14 |
| G-E5 | 2031-04-10 to 2031-04-23 | 14 |
| G-E6 | 2031-02-27 to 2031-03-26 | 28 |

G-E1, sensitive off:

```
entered by the owner, whole local days, oldest first:
  2031-03-10..2031-03-16: travel; note "Fixture trip"
```

G-E1, sensitive on, adds one row at the end:

```
  2031-03-26: custom "Fixture change"; note "Fixture note"
```

G-E2, the same with the switch off or on:

```
entered by the owner, whole local days, oldest first:
  2031-02-03..2031-02-09: deload
  2031-02-22..2031-02-24: travel
```

G-E3, sensitive off, is the single row:

```
events: none listed in range
```

G-E3, sensitive on:

```
entered by the owner, whole local days, oldest first:
  2031-05-19..ongoing: illness
```

G-E4, either setting:

```
entered by the owner, whole local days, oldest first:
  2031-01-22: supplementChange
```

G-E5, either setting. The event runs four days past the range and is printed whole:

```
entered by the owner, whole local days, oldest first:
  2031-04-14..2031-04-27: dietBreak
```

G-E6. Events: fifteen one-day `travel` events, no note, not sensitive, on 2031-03-01 to 2031-03-15,
`createdAt` 2000 to 2014. Fourteen rows:

```
entered by the owner, whole local days, oldest first:
  (3 earlier events in range not shown)
  2031-03-04: travel
  2031-03-05: travel
  2031-03-06: travel
  2031-03-07: travel
  2031-03-08: travel
  2031-03-09: travel
  2031-03-10: travel
  2031-03-11: travel
  2031-03-12: travel
  2031-03-13: travel
  2031-03-14: travel
  2031-03-15: travel
```

The whole-packet goldens that contain these rows under `== EVENTS ==` belong to the packet v2 change
and are written there, on stage 2's fixture.

### 13.4 Variants

| Variant | Change | Expected |
|---|---|---|
| V1 | No events | Every list empty; packet rows are the single row `events: none listed in range`; no note; no marks |
| V2 | Only E5 and E6, sensitive off | Packet rows are the single row `events: none listed in range` for any range; marks at weeks 12, 20, 21, 22; captions say "Private event" |
| V3 | E1 with `endDay` 2031-03-09 (before its start) | Dropped by `normalized`; the store refuses to save it |
| V4 | A second event with E1's id and a different start | The later one in input order is kept |
| V5 | E5 given `endDay` 2031-05-25 | Weeks 21 and 22 lose their mark |
| V6 | Stored string with one extra element of kind `"somethingNew"` | Eight events read; one unreadable entry reported and preserved through a save |
| V7 | Stored value `"{"` | `needsAttention`; no events; writes refused |
| V8 | App-target tests that involve the repository's clock-bound reads | Dates relative to the real clock (stage 1 ruling R31); the 2031 fixture is for pure logic and store-only cases |
| V9 | E2 (deload) and E3 (diet break) with `sensitive` true | `visible(_, includeSensitive: false)` returns neither; captions and the scorecard note say "Private event"; with the switch off G-E2 loses its deload row and G-E5 becomes the single "none listed" row; weeks 5, 15 and 16 keep their marks |

## 14. Work packages and file ownership

### 14.1 Packages

| WP | Role | Files |
|---|---|---|
| 5-2 | Designer | Files inside `design/round-s5-events/` only, including `s5-frames.json`. The folder and the `importS5` plugin command already exist (orchestrator's scaffolding, §18); `design/figma-plugin/code.js` and `manifest.json` are **not** edited by this stage. The combined frames for the Health card, Settings and the scorecard screen are a separate, shared design task |
| 5-3 | Test author | New: `Packages/StrandAnalytics/Tests/StrandAnalyticsTests/PersonalEventsTests.swift`, `PersonalEventsFixture.swift`; `Packages/StrandDesign/Tests/StrandDesignTests/ChartAxisMarksTests.swift`; `StrandTests/PersonalEventStoreTests.swift`, `PersonalEventOwnershipTests.swift`, `PersonalEventPresenterTests.swift`, `PersonalEventSheetModelTests.swift`, `PersonalEventChartSourceTests.swift`, `CutScorecardEventNoteTests.swift`, `PersonalEventBackupTests.swift`, `PersonalEventPrivacyTests.swift`; `Tools/test_personal_events_boundaries.py`. Also writes the new methods for `Packages/WhoopStore/Tests/WhoopStoreTests/BackupSettingsTests.swift` and hands them to the orchestrator, who commits them in 5-7h; the Test author does not edit that shared file |
| 5-4 | Implementer A (pure) | `Packages/StrandAnalytics/Sources/StrandAnalytics/PersonalEvents.swift`. Needs the scaffolding's `CanonicalDay.swift`; does not need stage 2 |
| 5-5 | Implementer B (storage) | New: `Strand/Data/PersonalEventStore.swift` (needs the scaffolding's `ObservableDefaultsFlag.swift`). No shared file: the `BackupSettings.swift` edit is in 5-7h |
| 5-6 | Implementer C (chart marks) | New: `Packages/StrandDesign/Sources/StrandDesign/ChartAxisMarks.swift`. Edited, one parameter and one row each: `NoopLineChart.swift`, `NoopBarChart.swift`, `StrandiOS/Scorecard/ScorecardWeekChart.swift` |
| 5-7 | Implementer D, after G1 and after 5-4, 5-5, 5-6 merge | New: `Strand/Data/PersonalEventPresenter.swift`, `PersonalEventsModel.swift`, `PersonalEventChartSource.swift`; `Strand/Screens/PersonalEventChartCaption.swift`; `StrandiOS/Events/PersonalEventsView.swift`, `PersonalEventSheet.swift`, `ScorecardEventNoteView.swift`, `PersonalEventsDemo.swift`. Edited: `Strand/Data/CutScorecardPresenter.swift` and `CutScorecardModel.swift` (the context field and the two outputs), each as one small commit in this stage's turn (§14.2). The note's view is a new file, `StrandiOS/Events/ScorecardEventNoteView.swift`; its one call site in `ScorecardView.swift` is in 5-7h. Edited, this stage only: `RecoveryDetailView.swift`, `StrainDetailView.swift`, `StrandiOS/App/TrainingHubView.swift`, `Strand/Screens/MetricExplorerView.swift`, `Strand/Screens/TrendsView.swift` (two lines per chart site) |
| 5-7h | Orchestrator, one small commit inside this stage's serialised step, after 5-7's new files exist | Every hotspot edit to a file other stages also edit, in this stage's turn of the one order (§14.2): `StrandiOS/Redesign/RedesignRoute.swift` (the case and the route switch); `RedesignHealthView.swift` (the row, at the fifth place of the one order, §10); `Strand/Screens/SettingsView.swift` (the Events card with its one switch, at the same place); `StrandiOS/Scorecard/ScorecardView.swift` (the call of `ScorecardEventNoteView` under the verdict and the `axisMarks:` argument); `Packages/WhoopStore/Sources/WhoopStore/BackupSettings.swift` (two entries and one line in the fork-only comment block) with the new methods of `BackupSettingsTests.swift` written by the Test author; and one array element for `PersonalEventsDemo.screen(named:)` in the demo registry of `StrandiOS/App/StrandiOSApp.swift` |
| 5-8 | Localiser, last step of this stage | `Strand/Resources/Localizable.xcstrings` |
| 5-9 | Implementer A, after stage 2 has merged | New: `Packages/StrandAnalytics/Sources/StrandAnalytics/PersonalEventsPacket.swift` and `Packages/StrandAnalytics/Tests/StrandAnalyticsTests/PersonalEventsPacketTests.swift` (written by the Test author first). `packetLines` then has tests and no production caller until the packet v2 change |
| 5-10 | Reviewers (correctness, contract, data-safety) and Verifier | None; read-only |

`PersonalEventsDemo.screen(named:)` has the signature of `ScorecardDemo.screen(named:)`
(`static func screen(named name: String) -> AnyView?`) and returns nil for every name that does not
begin `events-`, the prefix reserved for this stage. The orchestrator's step 0 adds the registry.
This stage's demo file is `StrandiOS/Events/PersonalEventsDemo.swift`; it adds that file and its one
registry element and changes no other element.

**Not this stage's work: packet v2.** After stages 3 and 5 have merged, one follow-up change adds
the `intake` and `events` sections to the packet together: both `CoachPacketSection` cases, the
input fields, the removal of both names from the header's `not-recorded-by-app` line, one version
bump, the events allowance in the byte budget (`PersonalEvents.packetByteAllowance`), one new set of
whole-packet goldens and one revision of the Claude-side text. From this stage it takes
`packetLines` and the two constants, unchanged. Stage 2 ships version 1 unchanged, with `events`
still listed under `not-recorded-by-app`.

The same change builds the private-events packet setting exactly as §9.6 specifies it, so the
setting and its reader arrive together: the key constant and the property in
`Strand/Data/PersonalEventStore.swift`; the second switch in this stage's Events card in
`Strand/Screens/SettingsView.swift`; the added sentence in `StrandiOS/Events/PersonalEventSheet.swift`;
the read-only caption in the packet sheet; the strings of §11's last row; and the tests §9.6 names.
Packet v2 is the last turn of the one order (§14.2), so no other writer holds those files then.

`project.yml` needs no change; the directories are included by path (stage 1 §14). Run
`xcodegen generate` after adding files. `StrandiOS/Events/` is a new directory under an included
root.

### 14.2 Shared hotspots this stage edits

**The one order.** Every shared file has one writer at a time, and the order is the same for every
file: Lab Book ownership, stage 2, stage 3, stage 4, stage 5, stage 6, then packet v2. **This stage
is the fifth turn**: each edit below is made after stage 4's serialised step has merged (that step
contains every earlier edit to the file, whichever specification owns it) and before stage 6's
begins. This table states this stage's edit and its place; what the other turns do to a file is in
their own specifications.

| Hotspot | This stage's edit | Package | Turn |
|---|---|---|---|
| `Strand/Resources/Localizable.xcstrings` | New strings (§11, all rows but the last) | 5-8 | Fifth; the last step of this stage |
| `StrandiOS/App/StrandiOSApp.swift` debug block | One array element in the demo registry | 5-7h | Fifth; the registry itself is step 0's |
| `Strand/Screens/SettingsView.swift` | The Events card with one switch | 5-7h | Fifth. Shared with macOS: build `Strand` after the edit |
| `StrandiOS/Redesign/RedesignHealthView.swift` | One row | 5-7h | Fifth |
| `StrandiOS/Redesign/RedesignRoute.swift` | One additive case, and its arm in the route switch | 5-7h | Fifth |
| `StrandiOS/Scorecard/ScorecardView.swift` | One call of `ScorecardEventNoteView` and the `axisMarks:` argument | 5-7h | Fifth |
| `Strand/Data/CutScorecardModel.swift` | `events` into the context in `load()` | 5-7, one small commit | Fifth |
| `Strand/Data/CutScorecardPresenter.swift` | `eventNote` and `marked` | 5-7, one small commit | Fifth |
| `Packages/WhoopStore/.../BackupSettings.swift` and `Packages/WhoopStore/Tests/WhoopStoreTests/BackupSettingsTests.swift` | One key in two maps and one comment line; new test methods only | 5-7h | Fifth |
| `StrandiOS/Scorecard/ScorecardWeekChart.swift` | The `axisMarks` parameter | 5-6 | Fifth |
| `NoopLineChart.swift`, `NoopBarChart.swift`, `Strand/Screens/MetricExplorerView.swift`, `TrendsView.swift`, `RecoveryDetailView.swift`, `StrainDetailView.swift`, `StrandiOS/App/TrainingHubView.swift` | One defaulted parameter per chart type; two lines per chart site | 5-6, 5-7 | Fifth. `MetricExplorerView` and `TrendsView` are shared with macOS: build `Strand` too |

`Tools/test_personal_events_boundaries.py` is this stage's own new file. Its notification list is
written with all eight producers (§12.5), because stage 3's turn comes before this one.

Packet v2, the last turn, edits three of this stage's files to build §9.6 (§14.1):
`PersonalEventStore.swift`, `PersonalEventSheet.swift` and this stage's card in `SettingsView.swift`.

**Not edited:** `Strand/Screens/DashboardCards.swift`, `Strand/Data/TodayCardReadout.swift`, the
three Today views, `Packages/StrandImport` `MarkerCatalog`, `Packages/WhoopStore/.../Database.swift`,
`Strand/Data/CutScorecardInputBuilder.swift`, `Packages/StrandAnalytics/.../CutScorecard.swift`,
`CanonicalDay.swift`, `ObservableDefaultsFlag.swift`, `design/figma-plugin/`, stage 2's
`CoachPacket.swift` and assembler, stage 3's intake files, stage 6's `TimelineSources.swift`, any
widget file, any notification file, `Strand/AI/`, anything under `android/`.

### 14.3 Parallel and serial

- **Before anything:** the orchestrator's scaffolding commit (§18).
- **Parallel with any other stage, from now, with no app build:** 5-2 (design), 5-3 (tests, new
  files only), 5-4 (pure logic and its `swift test`), the new `ChartAxisMarks.swift` of 5-6 and its
  tests, and the new files of 5-5 and 5-7 written but not built. Package tests run one package at a
  time per worktree.
- **Serialised on the one app build tree**, as step 6 of the build order: Lab Book ownership, the
  stage 1 follow-up, stage 2, stage 3, stage 4, then **this stage** (store, chart marks, scorecard
  note, Events screen), then stage 6, then packet v2. Inside this stage: 5-4, 5-5, 5-6; then 5-7
  after G1; then 5-7h; then 5-9; then 5-8 last. The backup tests of §12.3 pass from 5-7h on, when
  the whitelist entry exists.
- **5-9 and the packet.** Stage 2 merges before this stage, so `CoachPacket.sanitize` exists when
  5-9 is written. `packetLines` ships tested with no production caller; the packet v2 change adds
  the caller. The parity ledger's "production caller in the same change" expectation (CONTEXT §7
  item 3) is knowingly unmet for that one function between the two merges, and the pull request
  says so.
- **For stage 6.** `PersonalEventStore.events` is a synchronous main-actor **property** (not an
  `async` function); it returns `[]` while this stage's flag is off or the store is unreadable.
  Stage 6's `TimelineEventSource` is an adapter over it: it reads the property, calls
  `PersonalEvents.visible(_, includeSensitive: false)`, then keeps the kinds it shows. A private
  event of any kind, a private deload included, is absent from the timeline; stage 6 owns the test.
  This stage offers stage 6 nothing else and changes nothing for it. The niggle log needs fields an
  event does not have (location, character, triage) and is not squeezed into `PersonalEvent`. If a
  later stage needs SQL, §8.3 is the designed path.
- **Phone.** No install for this stage alone. Events are installed together with stage 6 and packet
  v2 at one accepted milestone, after a fresh backup, with the flag off until the owner switches it
  on. Should a build without packet v2 ever be installed, it carries no packet switch (§9.6): there
  is no control without an effect.

## 15. Open questions for the owner

Work proceeds on each recommendation. Every row is **decided by default**: the recommendation is the
design in force in this document. The last column says what changes if the owner says otherwise.

| # | Question | Recommendation, in force | If the owner says otherwise |
|---|---|---|---|
| S1 | Where are events stored: a settings list carried in the backup (no migration), or a new database table (a migration)? | The settings list (§8.2) | §8.3 is built instead: a migration, a data move from the settings key, a rehearsal on a copy of the database before any install. `PersonalEventStore` is the only file whose body changes; its API stays |
| S2 | Are whole days enough, or does an event need a time of day? | Whole days. Every chart and the scorecard that would show an event is per day or per week | A new stored field and version `v` 2 of the element; overlap stays per day |
| S3 | Private events and their notes will be inside backup files, in clear text, with the Android side knowingly behind (one of seven such fork-only keys across stages 3, 5 and 6). Keep them in the backup? | Yes: a record that vanishes on restore is worse, and the backup already holds the health database. Encrypted backups rise in priority | The key leaves the whitelist and §9.4's tests invert: events do not survive a restore, and the Events screen says so |
| S4 | Outside the Events screen, should a private event show its name, or the words "Private event"? | "Private event" in chart captions, the scorecard note and spoken text; absent from stage 6's timeline; out of the packet unless switched on (the switch arrives with packet v2, §9.6) | The caption and the note print the kind name (never the note) for private events, and the privacy tests of §12.5 change their needles |
| S5 | Which kinds start as private? | Illness and "Something else". You can flip the switch on any single event | `defaultSensitive` changes for the kinds named; stored events keep the flag they have |
| S6 | Should the classic charts (`TrendChart`, used when classic mode is on) also get marks? | No. The redesign is the interface in use. Adoption later is one parameter | One more adopting family in §10.5 and its sites |
| S7 | Should the scorecard note also list events from the earlier weeks its rules look back over, or the judged week only? | Both, in two short sections, three lines each at most | `earlierTitle` and `earlierLines` are dropped |
| S8 | Should the in-app Coach (the one that sends its context to a network provider) ever see events? | No. Its output reaches a notification and a widget, and its input leaves the phone | A separate change with its own consent wording; the two Coach tests of §12.5 are replaced, not deleted |
| S9 | The app already has its own strap-derived "illness watch". Should logging an illness event affect it, or the other way round? | Neither. One is your statement, the other is an estimate; they stay separate | A separate specification; nothing here reads the other |
| S10 | Should a chart caption be a link to the Events screen? | Not in this stage: the caption sits in screens shared with macOS that do not know the iPhone routes. The Health row and the scorecard note are the ways in | The caption view gains an optional action supplied by the iPhone screens |
| S11 | Should the packet tell the coach that private events were left out? | No. The packet says "none listed" or lists what is visible. The packet sheet shows you, as a read-only caption, whether private events are left out or included | A fixed row is added to `packetLines` and the events allowance is recomputed |
| S12 | Should planned (future) events be allowed? | Yes. They appear under "Upcoming" and mark nothing until their days arrive | The sheet refuses a start after today |
| S13 | Should "Mark a Moment" offer to create an event? | No. It stays as it is; it is a strap gesture with no kind or range | A separate change to the Automations screen |
| S14 | During a diet break or a deload, should the scorecard keep giving its verdict with the event noted beneath it? And is a diet break an event, not a phase? | Yes to both. A diet break or deload is an event; phases are only the long blocks (§1, §10.6). Stages 1 and 6 state the same rule | If the verdict should pause instead, that is a change to stage 1's evaluation with a new ruling; this stage's presenter still only adds the note |
| S15 | A supplement or medication name can reach the in-app Coach through the Journal, where stage 3 keeps its supplement ticks. Events themselves never reach it (S8). Should stage 3 keep those Journal questions out of the Coach context? | Yes; stage 3 builds the exclusion and its test. Nothing in this stage changes either way: no event, of kind "Supplement change" or any other, enters the Coach context | Stage 3 leaves the Journal as it is; this stage is unaffected |
| S16 | The Health card, the Settings cards and the scorecard screen each gain entries from several stages. Approve the one combined layout drawn by the orchestrator's designer, in which Events is the fifth entry of the shared order, after Body record and before Niggle log? | Yes; approved once, before any view code, then this stage's own frames | The place stated in §10, §10.1 and §10.7 follows the layout you choose; no logic changes |
| S17 | Install events on the phone together with stage 6 and packet v2 at one milestone, after a fresh backup, with the flag off until you switch it on? | Yes | The install plan changes; the code does not |
| S18 | The switch that lets private events into the coach packet arrives with packet v2, when the packet first has an events section, and is shown only while both Events and the Coach packet are switched on. Acceptable? | Yes (orchestrator ruling). Until then no private event can reach the packet at all | The switch, key and strings of §9.6 move into this stage's packages and the scan `test_no_packet_setting_without_its_reader` is dropped |

## 16. Not determined

- **Whether GRDB applies a migration registered before an already-applied one** (§8.3). Relevant
  only if option F is chosen. Not verified by reading GRDB or by a test.
- **Whether Room rejects or ignores a database that carries a table it has no entity for.** Relevant
  only to option F and to an Android restore the owner will not perform.
- **What `Tools/parity_ledger.py` and `parity_ratchet.py` report** for new public declarations in
  `StrandAnalytics` with no twin claim. Not run. The stored authority already fails to reproduce on
  this branch (BASELINE.md), so the effect could not be isolated by reading.
- **Stage 2's code on this branch.** The packet renderer does not exist here. §7.5 follows the
  grammar of the stage 2 specification as written; `CoachPacket.sanitize` was read from that
  specification, not from code. Where the events section sits among the packet's sections, and the
  input field that carries the rows, are fixed by the packet v2 change.
- **A label or note that trips stage 2's privacy scan** blocks the whole packet (§7.5). Whether the
  blocked state should name the events section, or the event sheet should warn while typing, is not
  designed here.
- **The exact declarations of the scaffolding** (`ObservableDefaultsFlag`, `CanonicalDay`, the demo
  registry's element type, the wording of the fork-only backup comment block). §18 states what this
  stage relies on; the scaffolding commit is the authority.
- **The row height and divider rule of the Health card with three or more rows.** Left to the
  combined frame.
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
- **Whether the `moments` list's silent trim beyond 500 entries should be fixed.** Outside this
  stage; noted because it is the behaviour this stage's store avoids.
- **Nothing was compiled or run.** Every API in §6, §9.3 and §10.5 is a design, not a build result.

## 17. Design approval record (G1)

Not yet submitted. Two approvals are needed, in this order.

1. **The combined layout, shared by all stages, approved once:** the Health tab's "More health" card,
   the Settings cards and the scorecard screen, drawn by the orchestrator's designer. It is the
   authority for the order (§10), is not this stage's round and is not re-opened here.
2. **This stage's frames,** `design/round-s5-events/s5-frames.json`: Health row (2, inside the
   approved card); Events screen (every row of §10.2); event sheet (every row of §10.3); delete
   confirmation; chart marks on a weekly curve, a thirty-day bar chart and a line chart, each with
   no event, one event, a dense run, and a missed week; the caption in each state of its table; the
   scorecard note in each state of §10.6 (inside the approved scorecard layout); the Events card
   in Settings with its one switch (inside the approved Settings layout), and, as a frame for the
   packet v2 change, the same card with the second switch of §9.6. Two options to choose between, as their own
   frames: a dot per covered position (the recommendation) against a dot at the start and an open
   dot at the end.

Each frame id is also a demo name: `--demo-screen events-<frame id>`.

## 18. Reconciliation (11 November 2026)

What changed in this file for each conflict of the cross-stage check that names stage 5. This table
is the record of the first pass; where the "Second pass" below changes an item (X3's switch, X6,
X18, X21, X22), the second pass is the text in force.

| Conflict | Change in this file |
|---|---|
| X3 | `packetLines` now returns body rows only, in stage 2's grammar: no heading, a fixed intro row, two-space rows, raw kind values, label and note through `CoachPacket.sanitize`, a cap of 12 rows with an "earlier not shown" row, and a fixed allowance of 2,000 bytes (§6, §7.5). "None listed" wording kept. The switch stays `personalEvents.packetIncludesSensitive` and is shown in the packet sheet as a read-only caption (§7.5, §10.7). Goldens rewritten over 14-day and 28-day ranges (§13.3); tests and fault lines updated (§12.1, §12.6) |
| X4 | The section case, heading, version bump, budget, whole-packet goldens, sheet caption and Claude-side text moved out of this stage to the one "packet v2" change after stages 3 and 5 (§1, §14.1, §14.3). WP 5-9 now delivers only `PersonalEventsPacket.swift` and its tests |
| X5 | Design round renamed `design/round-s5-events/`, frames `s5-frames.json`, command `importS5`; the plugin files are no longer edited by this stage (§5, §10, §12.8, §14.1, §17) |
| X6 | The debug block edit is one array element in the scaffolding's demo registry; demo names carry the prefix `events-` (§2, §5, §14.1, §14.2) |
| X8 | `PersonalEventStore.events` is stated as a synchronous main-actor property that is `[]` while the flag is off; stage 6 adapts to it and this stage adds no `async` read (§4.3, §14.3) |
| X9 | Stage 6's `TimelineEventSource` is listed as a reader that must pass through `visible(_, includeSensitive: false)`; a private event is absent from the timeline. Added a private deload and diet break variant, a `visible` test, a source scan and a fault line (§4.3, §7.5, §12.1, §12.5, §12.6, §13.4 V9, S4) |
| X13 | Stated that no intake-target override is built or supplied; the intake screen may show the event caption only (§1) |
| X14 | Stated the one rule: a diet break or deload is an event, phases are the long blocks, the scorecard keeps reporting with the note under the verdict (§1, §10.6, §13.1); a test and a fault line added; listed as S14, decided by default |
| X15 | Recorded as S15, decided by default: stage 3 excludes its supplement Journal questions from the Coach context; no event of any kind enters it (S8 unchanged) |
| X16 | The notification-producer scan lists eight files, the eighth being stage 3's `IntakeCutoffReminder.swift`; the second of the two stages to merge adds it (§12.5, §14.2) |
| X18 | The `CutScorecardModel.load()` edit is ordered after stage 2's move and stage 3's builder change and before stage 6's property; the presenter edit after stage 4's; `ScorecardView` after stages 2 and 3 (§10.6, §14.2) |
| X19 | `PersonalEvents.isValidDay` removed; every day-key question goes through `CanonicalDay`. The `PersonalEventsFlag` type removed; the flag is one static `ObservableDefaultsFlag` on the store (§5, §6, §7.1, §7.3, §7.4, §9.3, §12.1, §12.3, §12.5) |
| X20 | Stated that there is one Fixture Person, the stage 1 one, with its phase, weights, floor and missed week; the demo uses that series (header, §12.8, §13) |
| X21 | Backup edit ordered after stage 3's and before stage 6's, with one line in the shared fork-only comment block; the Android drift stated in one paragraph; folded into S3 as decided by default (§9.4, §14.2) |
| X22 | Health row placed third in the fixed order; Settings and scorecard-screen order fixed by the combined frame; the combined layout is a separate approval (§10, §10.1, §10.6, §10.7, §17, S16) |

Owner decisions adopted as the design in force: the settings list (S1), "Private event" outside the
Events screen with illness and custom kinds private by default (S4, S5), no events in the in-app
Coach (S8), the verdict continuing through a diet break or deload (S14), the fork-only backup key in
clear text (S3), the combined layout (S16) and milestone installs (S17).

Android (R43): this document contains no instruction to write or run Kotlin. The one stored-data
contract it changes is the backup whitelist, and §9.4 states the drift.

Also added, so that tests can be written from this document alone: the app-side API of §10.9.

**Shared scaffolding this stage expects from the orchestrator's step 0**, one commit on the
integration branch before any stage:

| Scaffolding | What this stage relies on |
|---|---|
| The demo registry line in `StrandiOS/App/StrandiOSApp.swift` | An ordered list of demo providers consulted for an unknown `--demo-screen` name, each provider returning nil for a name outside its own reserved prefix. This stage adds one element for `PersonalEventsDemo.screen(named:)`, prefix `events-` |
| The plugin import commands and stage-named design folders | `importS5` in `design/figma-plugin/code.js` and `manifest.json`, reading `design/round-s5-events/s5-frames.json`; the folder `design/round-s5-events/` |
| `ObservableDefaultsFlag` | `Strand/Data/ObservableDefaultsFlag.swift`: a main-actor `ObservableObject` with `init(key: String, defaults: UserDefaults = .standard)`, a published read-only `isEnabled` that follows every write to the key, and `set(_:)` |
| `CanonicalDay` | `Packages/StrandAnalytics/Sources/StrandAnalytics/CanonicalDay.swift` with `number(_:)`, `key(_:)`, `daysBetween(_:_:)` and `weekStart(_:)` as in stage 6 §6.0, and the one test that pins it to `CutScorecard.weekStart` |
| `ChargeTypicalBand` | Nothing. This stage neither reads nor shows the typical range; listed so the absence is deliberate |
| The fork-only backup keys comment | A comment block above the Swift whitelist in `BackupSettings.swift` listing every fork-only key; this stage adds the line for `personalEvents.items`. Also the note in the fork's personal documents that the Kotlin whitelist is knowingly behind |

### Second pass

Applied after the independent re-check of the first pass, under the orchestrator's rulings (a) to
(k). Each line says what the ruling or re-check item changed here.

| Item | Change in this file |
|---|---|
| Ruling (a), weigh-in outranks a scan | Nothing is specified here. This file never stated the rule and still does not; it is stage 1's ruling on `BodyMeasurementResolver` (stage 1 §18, R44), implemented as work package 1-11 inside stage 4's serialised step. The only consequence here is the order: this stage's `CutScorecardPresenter.swift` edit is made after the whole of stage 4's step, which contains every earlier edit to that file (§14.2) |
| Ruling (b), whole-gram floor | Not this stage's. The fixture line "protein floor 100 g" (§12.8, §13) is already a whole number; unchanged |
| Ruling (c), shared-file order, and the re-check's "stage 3 became an editor" | §14.2 rewritten: the one order is stated once (Lab Book ownership, 2, 3, 4, 5, 6, packet v2) and every row states this stage's turn, the fifth, and nothing about other stages' edits. The per-file lists of other stages ("2, 5, 6" for the model, "4, then 5" for the presenter, "3, 5, 6" for the backup file) are removed from §9.4, §10.6, §11 and §14.2. The model edit is located by `load()` and no longer assumes which earlier stages touched the file |
| Ruling (d), Settings and Health order (re-check X22, "Settings card order was read two ways") | §10, §10.1, §10.7, 5-7h, S16 and §17 now say one thing: Events is the fifth entry of the one order, after Body record and before Niggle log, and the orchestrator's combined frame set is the authority. The six-row list ending in "Coach packet", the "third in the fixed order" wording and the list of other stages' Settings cards are removed. This stage's Settings entry is now a card, "Events", holding one switch (§10.7, §11) |
| Re-check X22, hotspot edits as one orchestrator commit | The `ScorecardView.swift` and `BackupSettings.swift` edits, and the new `BackupSettingsTests.swift` methods, moved from 5-7, 5-5 and 5-3 into the orchestrator's commit 5-7h. The scorecard note's view became this stage's own file, `StrandiOS/Events/ScorecardEventNoteView.swift`, so the shared view gains one call and one argument (§10.6, §14.1, §14.2, §14.3) |
| Ruling (e), the private-events packet switch | The switch, its key, the store property, its footnote and the event-sheet sentence about the packet left this stage's milestone. New §9.6 specifies the setting completely, and the packet v2 change builds it with its one reader. Removed from §9.1's key table and §9.3's store listing; §1, §4.3, §5, §7.5, §9.4, §10.7, §11, §14.1 and §17 follow. The event sheet's sentence is now "Private events show as "Private event" outside this screen."; the packet sentence is a separate string added by packet v2. Tests: the backup test is split (`testPersonalEventsFlagIsNotExported` here; the switch's twin in packet v2), a scan `test_no_packet_setting_without_its_reader` and fault line F29 are added, and §9.6 names the tests packet v2 adds. Recorded for the owner as S18 |
| Ruling (f), packet rows (re-check X3) | §7.5 names stage 2 §7.12 as the authority for the grammar and replaces its mixed example with golden G-E1 (private events included), the rows stage 2 §7.12 also prints, with §13.3 as the one text both documents copy from. No golden or constant changed: the caption has no count, the allowance is this stage's `PersonalEvents.packetByteAllowance` (2,000), and the widest row is 140 bytes, 141 with its line break. One test added for stage 2's rule G-8 (a row whose note looks like an email address or a path is returned intact) |
| Ruling (g), `LabMarkerStore` building blocks | Not this stage's. No Lab Book file is read or edited here (§8.1 option E, §14.2 "Not edited") |
| Ruling (h), demo registry (re-check X6) | §14.1 and the scaffolding table state this stage's file (`StrandiOS/Events/PersonalEventsDemo.swift`), its reserved prefix (`events-`) and its one registry element. The list of other stages' providers is removed |
| Ruling (i), `AICoach.swift` order | This stage has no position in it: `Strand/AI/` is not edited (§14.2) and a source scan asserts it (§12.5) |
| Ruling (j), `ChargeTypicalBand` | Not this stage's; the scaffolding table already says this stage uses neither it nor `Baselines.sigma` |
| Ruling (k), privacy | No change needed. This file names no product, no private file and no private value; every example is the Fixture Person's |
