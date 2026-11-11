# Stage 2 specification — coach packet

Gate G0 for stage 2 of the health super-app workstream. Read [CONTEXT.md](../CONTEXT.md),
[ROADMAP.md](../ROADMAP.md) (stage 2, and stages 1, 3 and 5, which feed or extend it),
[QUALITY-GATES.md](../QUALITY-GATES.md) and the [stage 1 specification](stage-1.md) first.

Verified against the source at commit `0b89b814` (branch `personal/superapp-2-coach-packet-spec`, cut
from `personal/superapp-1-screens`, which holds stage 1 as built). Every `path:line` below is as of
that commit. Paths are relative to the repository root. Nothing was built or run for this document;
it is a reading of the code. The example in §7.9 was produced by a scratch script that implements
§7, not by Swift (see §18).

This file contains no personal measurement, target, date, medication or injury detail. Every number
in an example belongs to the synthetic "Fixture Person" of §13.

By the stage brief this stage is local only: nothing is pushed and no pull request is opened. Gate
G7 as written in QUALITY-GATES.md asks for a pull request; the orchestrator records how that gate is
met locally.

## 1. Goal and scope

**Goal.** One action produces everything the coach needs from the app as plain text in a stable,
labelled format, so the owner pastes it into Claude and retypes nothing.

**In scope**

- A pure packet renderer with a versioned, fixed-order text format (§7).
- One shared formatter for the per-day line and the averages, used by the packet and by the in-app
  Coach context, with the in-app Coach context byte-identical before and after (§6.1, §8).
- An assembler that gathers the packet's inputs through the app's existing single resolvers (§8).
- A preview sheet with section switches and a range choice, shown before anything is copied (§10).
- Copy to a local-only, expiring pasteboard item; the system share sheet; a Shortcuts action that
  returns the same text (§9, §10).
- A privacy scan that fails closed (§7.11).
- The Claude-side half as text the owner can paste (§16).
- A default-off setting, `noop.coachPacketEnabled`.

**Out of scope**

- Any network call. The app sends the packet nowhere. It leaves the phone only by the owner's own
  paste or share.
- Sending the packet to the in-app Coach provider, and any change to what the in-app Coach is told.
- Writing the packet to a file or a cloud folder (backlog).
- Intake and events content. Their sections are absent until stages 3 and 5 exist (§7.2).
- Lab Book markers other than weight and waist, the profile (age, sex, height), the journal, stress,
  SpO₂, skin temperature and respiration. None is in format version 1.
- A Today card, a widget, a notification, a Siri phrase.
- A migration, a backup-whitelist key, a marker-catalogue key, a Health read or write, a build
  target, an entitlement. None is needed and none is added.
- Android. No Kotlin twin is written (ruling R43). The disposition is in §14.4.
- Any medical statement. The packet reports the owner's numbers and names their source.

## 2. Re-check of "what exists"

| # | Claim in the planning documents | Status | Evidence |
|---|---|---|---|
| 1 | `AICoach.buildContext()` writes a 14-day summary with 30-day averages and marks unmeasured values with a dash | Confirmed, with the differences in §3 C1 to C3 | `Strand/AI/AICoach.swift:1607-1645`; the legend "A dash means NOT MEASURED, not zero" at `:1622-1623` |
| 2 | `buildFullContext` adds recent workouts, a stress line and, on a second opt-in, the on-device signals block | Confirmed | `AICoach.swift:1207-1220`, `:1227-1240`, `:1246-1312`, `:1650-1671` |
| 3 | The Coach context states the resolver's weight and waist | Confirmed, done in stage 1 | `AICoach.swift:1273-1281`, `:1305-1309`, `:1316-1325`; tests `StrandTests/OneNumberPerVariableTests.swift:639-826` |
| 4 | The per-day line has a test seam | Confirmed: `dayLine(_:)` and `efficiencyPercentOrDash(_:)` are internal for that reason | `AICoach.swift:1675-1701`, `:1719-1724`; `StrandTests/AICoachSleepContextTests.swift:24-51` |
| 5 | Coach providers: Anthropic, ChatGPT, Custom, Gemini, OpenAI | Confirmed. The packet uses none of them | `Strand/AI/Providers/` |
| 6 | Siri and Shortcuts: Mark a Moment, Buzz Strap, Sync Strap, Ask Coach | Incomplete: a fifth intent returns a value (§3 C4) | `StrandiOS/System/NOOPAppIntents.swift:63-127`; `StrandiOS/System/ExportWorkoutRouteIntent.swift:62-103` |
| 7 | The only export of Coach text is copying a single reply | Confirmed for Coach text; the copy has no pasteboard options (§3 C5) | `Strand/Screens/CoachView.swift:687-706` |
| 8 | Stage 1 is built: scorecard, weigh-in storage, resolver, provider, settings, presenter, model | Confirmed | `Packages/StrandAnalytics/Sources/StrandAnalytics/CutScorecard.swift`; `Strand/Data/WeighInStore.swift`, `BodyMeasurementResolver.swift`, `BodyMeasurementProvider.swift:51-302`, `CutScorecardSettings.swift:61-67`, `CutScorecardInputBuilder.swift:11-56`, `CutScorecardModel.swift:68-214`, `CutScorecardPresenter.swift` |
| 9 | A debug demo harness, a local gate script and a design pipeline exist | Confirmed | `StrandiOS/Scorecard/ScorecardDemo.swift:32-63`; `StrandiOS/App/StrandiOSApp.swift:572-626`; `Tools/personal/gate.sh`; `design/round6-scorecard/`, `design/tools/serve.py`, `design/figma-plugin/manifest.json:22-30` |
| 10 | Daily read model for recovery, sleep, HRV and resting heart rate | Confirmed: `Repository.days`, oldest to newest | `Strand/Data/Repository.swift:184`; `Packages/WhoopStore/Sources/WhoopStore/MetricsCache.swift:82-139` |
| 11 | A personal baseline exists | Confirmed, three of them (§3 C7) | `Repository.swift:190`; `Packages/StrandAnalytics/Sources/StrandAnalytics/ChargeBaselines.swift:31`, `:127-144` |
| 12 | Steps carry a source | Confirmed, with three precedences in the tree (§3 C8) | `Strand/Data/RollingStepsAverage.swift:44-58` |
| 13 | Workout summaries exist with a classified source | Confirmed | `Repository.swift:2774-2810`; `Packages/WhoopStore/Sources/WhoopStore/JournalWorkoutAppleCache.swift:30-43`; `Strand/Data/WorkoutSource.swift:17-25` |

## 3. Corrections to the planning documents

| # | Document says | The code says | Consequence for this stage |
|---|---|---|---|
| C1 | "a 14-day biometric summary with 30-day averages" (`ROADMAP.md:262-263`, `CONTEXT.md:82`) | They are the last 14 and the last 30 **rows**, not calendar windows: `days.suffix(14)` and `days.suffix(30)` (`AICoach.swift:1620`, `:1629`). A gap in wear stretches both windows back in time | The shared formatter takes a list of rows and does not choose a window. The Coach keeps its row windows (byte identity). The packet passes the rows inside its calendar range and prints one line for every calendar day (§7.5) |
| C2 | The per-day line is taken as a clean model | The line is built as `[day + ":"]` followed by the fields, joined with `", "` (`AICoach.swift:1680`, `:1700`), so it reads `2031-03-03:, charge 62, …` with a comma after the colon | The comma is kept in the in-app Coach (byte identity). The packet uses the same field list with its own day separator (§6.1) |
| C3 | The packet shows recovery, strain and sleep | The in-app line says `charge`, `effort` and `rest` (`AICoach.swift:1622-1623`, `:1681-1683`), and prints strain on the stored 0 to 100 axis whatever display scale the owner chose (`Strand/Data/Units.swift:351-366`) | One formatter, two styles: labels, day separator and strain factor are parameters (§6.1). The packet prints the labels and the strain scale the app shows (ruling R41) |
| C4 | Four intents (`CONTEXT.md:84`) | Five on iPhone: `ExportWorkoutRouteIntent` returns a file with `ReturnsValue` and `openAppWhenRun = false` (`ExportWorkoutRouteIntent.swift:62-103`). A separate macOS file declares two (`Strand/System/NOOPAppIntents.swift:26-59`) | The packet intent follows the route-export precedent and lives in its own iPhone-only file. `NOOPAppIntents.swift` is not edited |
| C5 | "apart from copying a single reply" (`CONTEXT.md:96`); risk 9 names the clipboard (`CONTEXT.md:195`) | That copy writes `UIPasteboard.general.string` with no options (`CoachView.swift:690-695`), next to a `ShareLink` (`:699`). A second writer, `PlatformPasteboard.copy`, does the same (`Strand/System/Platform.swift:29-38`, used at `Strand/Screens/SettingsView.swift:3414`). No code in the tree uses `localOnly` or an expiry | The packet gets its own writer (§9). The two existing writers are not changed; they are reported in §15 P10 |
| C6 | The stage 1 specification says "Stage 2 replaces it with the resolver's value" of the Coach's Lab Book roll-up (`specs/stage-1.md:94`) | Stage 1 already did it under ruling R41 (`AICoach.swift:1273-1309`) | Stage 2 does not touch `onDeviceSignalsBlock` |
| C7 | "against the personal baseline", as if there were one (`ROADMAP.md:290`) | Three exist: the recovery engine's, resolved once per refresh over a 21-day window (`Repository.swift:190`, `ChargeBaselines.swift:31`); the classic Health screen's mean of every earlier day (`Strand/Screens/HealthView.swift:633-637`); the Coach chips' 30-row mean (`Packages/StrandAnalytics/Sources/StrandAnalytics/CoachSuggestions.swift:99-103`) | The packet reads `Repository.chargeBaselines` only, with the band the Recovery detail screen draws (`StrandiOS/Redesign/ScoreDetailData.swift:156-160`) |
| C8 | "steps per day with the source named" (`ROADMAP.md:291`) | Three precedences: the shared resolution used by the detail and the rolling tile, measured strap, then phone, then strap estimate (`RollingStepsAverage.swift:44-58`); Today, the same order from its own fields (`Strand/Liquid/LiquidTodayView.swift:3610-3611`, `Strand/Data/TodayCardReadout.swift:231-240`); the widget, Health first, then the estimate (`StrandiOS/Widgets/WidgetPublish.swift:130-160`). The in-app Coach's average reads a fourth thing, `DailyMetric.steps` alone (`AICoach.swift:1641`) | The packet reads `Repository.resolvedSteps` only. The differences are pre-existing and are not repaired here (§15 P10) |
| C9 | The Coach context is assumed to be English | Its body-measurement line takes the source name from a localised string (`AICoach.swift:1322`; `Strand/Data/CutScorecardPresenter.swift:542-548`) | The packet does not reuse that line. It prints the same resolved value with fixed English source tokens, and a test ties the two numbers together (§12.3) |
| C10 | WP 2-5 lists "pasteboard" with no platform; the work-package table has no owner for the assembler or the app-target tests (`ROADMAP.md:306-315`) | `UIPasteboard` options exist on iOS only. Shared sources compile for macOS as well | The writer is an iPhone-only file behind a protocol declared in shared code (§9). §14 assigns the missing owners |
| C11 | The in-app workouts block is not mentioned by the design rule | It prints distance in the owner's unit system and takes the day from the device zone with its own formatter (`AICoach.swift:1653-1667`, `:1742-1747`) | It is left untouched and is not shared. The packet's workout lines are metric and have their own template (§7.7) |
| C12 | The packet "includes the stage 1 result" | The evaluation the screens show is private to the screen model, including the substitution of an upcoming phase (`Strand/Data/CutScorecardModel.swift:196-213`). A second caller would have to repeat it | The function moves to `CutScorecardInputBuilder` so the screen and the packet call one evaluation (§8.2) |
| C13 | The roadmap says stages 1 and 2 are sequential and end in a pull request (`ROADMAP.md:23-27`) | Later instructions run the stages at once on separate branches, locally | §14.3 lists what may run beside other stages and what must be serialised |

## 4. Every reader and writer

Stage 2 stores nothing except its own settings (§9.3). It adds one new **reader** of each fact below.
"Funnel" is the one function the packet reads the fact through.

| Fact | Existing readers | Existing writers | Funnel for the packet |
|---|---|---|---|
| Current weight and waist | Every site in stage 1 §4.1 and §4.2; the Coach at `AICoach.swift:1276-1281` | `WeighInStore`, Lab Book, the importers, the profile mirror | `BodyMeasurementProvider.current(_:consumer: .display)` (`BodyMeasurementProvider.swift:282`). A never-set profile is not printed, as the Coach does (`AICoach.swift:1280`) |
| Weekly weigh-in points, rate, projection, signals, rules, verdict | `CutScorecardModel.load` (`CutScorecardModel.swift:141-181`) for the card, the Health row and the screen | None (computed) | `CutScorecardInputBuilder.evaluation(today:)` (§8.2), the function the screen model calls after this stage |
| Recovery, strain, sleep, stages, efficiency, HRV, resting heart rate per day | The three Today views, the detail screens, Trends, the Coach (`AICoach.swift:1608-1626`), widgets | The scoring pass and the importers | `Repository.days` (`Repository.swift:184`), rendered by `CoachDayFormat` (§6.1) |
| Strain display scale | Every Effort readout through `UnitFormatter.effortDisplay` (`Units.swift:364-366`) | Settings (`effort.scale`, `Units.swift:98`) | `UnitPrefs.resolveEffortScale` (`Units.swift:158-160`) and `UnitFormatter.effortScaleFactor` (`Units.swift:354`), passed to `CoachDayFormat` as the strain factor |
| HRV and resting-heart-rate baseline | The Recovery detail (`ScoreDetailData.swift:149-166`), calibration counts (`LiquidTodayView.swift:3217-3218`, `Strand/Screens/TodayView.swift:865`, `:1161-1162`, `Strand/Screens/CoupledView.swift:62-63`, `:551`) | `Repository.refresh` (`Repository.swift:1004`, `:1037`) | `Repository.chargeBaselines` with `Baselines.sigma` (`Packages/StrandAnalytics/Sources/StrandAnalytics/Baselines.swift:602-604`) and `BaselineState.usable` (`Baselines.swift:69`) |
| Steps per day and their source | See C8 | Health import, the strap pipeline, the estimate engine | `Repository.resolvedSteps(from:to:)` (`RollingStepsAverage.swift:46-58`) |
| Workout summaries | Workouts screens, the Strain detail, the Coach (`AICoach.swift:1651`) | Strap, Health import, lifting imports, activity files | `Repository.workoutRows(days:)` (`Repository.swift:2774`) with `WorkoutSource.classify` (`WorkoutSource.swift:25`) |
| The general pasteboard | Nothing reads it | `CoachView.swift:690-695`; `PlatformPasteboard.copy` (`Platform.swift:29-38`) | New writer `SystemCoachPacketPasteboard` (§9); the two existing writers are unchanged |
| The in-app Coach context | `contextFor` (`AICoach.swift:1392-1398`), `generateBrief` (`:1189-1203`), `AskCoachIntent` through the app | — | Unchanged in content. Its per-day line and averages are produced by `CoachDayFormat` after this stage (§8.1) |

Android: `android/app/src/main/java/com/noop/ai/AiCoach.kt:405` is the Kotlin `buildContext`, with
its tests in `android/app/src/test/java/com/noop/ai/AiCoachContextTest.kt`. Neither is edited. The
Swift output it mirrors does not change by a byte, so this stage creates no drift there.

## 5. Final names

| Thing | Name | Where |
|---|---|---|
| Shared day formatter | `CoachDayFormat`, `CoachDayStyle` | `Packages/StrandAnalytics/Sources/StrandAnalytics/CoachDayFormat.swift` |
| Packet renderer and its input types | `CoachPacket`, `CoachPacketInput`, `CoachPacketSection`, `CoachPacketScorecard`, `CoachPacketBodyReading`, `CoachPacketBaseline`, `CoachPacketStepDay`, `CoachPacketWorkout` and the enums in §6.2 | `Packages/StrandAnalytics/Sources/StrandAnalytics/CoachPacket.swift` |
| Settings | `CoachPacketSettings` | `Strand/Data/CoachPacketSettings.swift` |
| Assembler | `CoachPacketAssembler`, `CoachPacketDocument`, `CoachPacketOutcome` | `Strand/Data/CoachPacketAssembler.swift` |
| Sheet model, presenter, copy plan, pasteboard protocol | `CoachPacketModel`, `CoachPacketPresenter`, `CoachPacketCopyPlan`, `CoachPacketPasteboardWriting` | `Strand/Data/CoachPacketModel.swift`, `Strand/Data/CoachPacketPresenter.swift` |
| Flag observer | `CoachPacketFlag` (the shape of `CutScorecardFlag`, `CutScorecardModel.swift:18-63`) | `Strand/Data/CoachPacketModel.swift` |
| Sheet | `CoachPacketSheet` | `StrandiOS/CoachPacket/CoachPacketSheet.swift` |
| Pasteboard writer | `SystemCoachPacketPasteboard` | `StrandiOS/CoachPacket/CoachPacketPasteboard.swift` |
| Share sheet wrapper | `CoachPacketShareSheet` | `StrandiOS/CoachPacket/CoachPacketShareSheet.swift` |
| Shortcuts action | `GetCoachPacketIntent`, `CoachPacketIntentError` | `StrandiOS/System/CoachPacketIntent.swift` |
| Debug demo | `CoachPacketDemo` | `StrandiOS/CoachPacket/CoachPacketDemo.swift` |
| Scorecard evaluation funnel | `CutScorecardInputBuilder.evaluation(today:)` | `Strand/Data/CutScorecardInputBuilder.swift` |
| Feature flag | `noop.coachPacketEnabled`, Bool, default `false` | `CoachPacketSettings.enabledKey` |
| Range | `coachPacket.rangeDays`, Int, default 14; allowed 7, 14, 28 | `CoachPacketSettings.rangeDaysKey` |
| Section switches | `coachPacket.sections`, String (JSON object, sorted keys) | `CoachPacketSettings.sectionsKey` |
| Format name and version | `NOOP-COACH-PACKET`, version `1` | `CoachPacket.formatName`, `CoachPacket.formatVersion` |

The renderer and the day formatter are pure and live in the package, where `swift test` runs them in
seconds without the shared build tree. The assembler, settings, model and presenter live under
`Strand/` so `StrandTests` (macOS scheme only) can test them. The SwiftUI and UIKit files live under
`StrandiOS/` and are verified by compiling and in the simulator. `project.yml` needs no change: the
three directories are included by directory. Run `xcodegen generate` after adding files.

## 6. Pure logic: the API

No store, no clock, no `Calendar`, no `TimeZone`, no `Date`, no `Locale`, no `String(localized:)`.
Every function is total: it never throws and never traps. Every type has a public memberwise
initialiser in declaration order.

### 6.1 `CoachDayFormat`

```swift
import WhoopStore   // DailyMetric

public struct CoachDayStyle: Equatable, Sendable {
    public let recoveryLabel: String
    public let strainLabel: String
    public let sleepLabel: String
    public let daySeparator: String     // between the day key and the first field
    public let strainFactor: Double     // multiplies the stored 0–100 strain before formatting

    /// The in-app Coach context exactly as it was: "charge", "effort", "rest", ":, ", 1.0.
    public static let coachContext: CoachDayStyle
    /// The packet: "recovery", "strain", "sleep", ": ", and the factor of the owner's display scale.
    public static func packet(strainFactor: Double) -> CoachDayStyle
}

public enum CoachDayFormat {
    /// "—" (U+2014). The one token for a value that was not measured.
    public static let notMeasured: String

    /// The nine value fields of one day, in order: recovery, strain, sleep, deep, REM, light, eff,
    /// HRV, RHR. Each is "<label> <value>" or "<label> —".
    public static func fields(_ day: DailyMetric, style: CoachDayStyle) -> [String]

    /// day + style.daySeparator + fields joined by ", ".
    public static func dayLine(_ day: DailyMetric, style: CoachDayStyle) -> String

    /// "<recovery>: A, <strain>: B, <sleep>: Ch, HRV: D ms, RHR: E bpm" over the rows given.
    public static func primaryAveragesLine(_ days: [DailyMetric], style: CoachDayStyle) -> String

    /// "SpO2: A%, respiration: B/min, skin-temp deviation: C°C, steps: D/day, active energy: Ekcal/day".
    /// Used by the in-app Coach only.
    public static func vitalsAveragesLine(_ days: [DailyMetric]) -> String

    /// A stored efficiency as "94%", normalising a value stored as a percentage; "—" otherwise.
    public static func efficiencyPercent(_ raw: Double?) -> String
}
```

Field formats, which are the formats of `AICoach.swift:1679-1740` as they stand:

| Field | Present | Absent |
|---|---|---|
| recovery | `"\(Int(v.rounded()))"` | `—` |
| strain | `String(format: "%.1f", v * style.strainFactor)` | `—` |
| sleep | `String(format: "%.1fh", minutes / 60)` | `—` |
| deep, REM, light | the same hours format | `—` |
| eff | `efficiencyPercent`: nil or `<= 0` is `—`; a value above 1.5 is divided by 100; a result outside `(0, 1]` is `—`; else `"\(Int((e * 100).rounded()))%"` | `—` |
| HRV | `"\(Int(v.rounded()))ms"` | `—` |
| RHR | `"\(v)bpm"` | `—` |

Averages: integer averages are `"\(Int(mean.rounded()))"`, one-decimal averages
`String(format: "%.1f", mean)`, the sleep average `String(format: "%.1f", meanMinutes / 60)`. An
empty list gives `—`, and the unit suffix still follows it (`sleep: —h`, `HRV: — ms`), as today. The
strain average is the mean of `v * strainFactor`.

Three rules beyond the existing code, each stated so the Test author can pin it:

- **F1. Non-finite values.** A value that is NaN or infinite, or whose magnitude is above `1e15`, is
  treated as absent. The existing code would trap on `Int(_:)` for such a value, so no existing
  output changes.
- **F2. Multiplying by 1.0.** With `strainFactor == 1.0` the product is the stored value, so the
  Coach style reproduces today's bytes.
- **F3. `rounded()`** is Swift's default, halves away from zero, as in the existing code.

### 6.2 `CoachPacket`

```swift
public enum CoachPacketSection: String, CaseIterable, Equatable, Sendable {
    case scorecard                       // "scorecard"
    case weighIns = "weigh-ins"
    case recoverySleep = "recovery-sleep"
    case trends
    case activity
    // Version 1 has no case for intake or events. They are added with their stages (§7.2).

    /// Whether the section is on when the owner has never chosen. True for all five.
    public var isOnByDefault: Bool { get }
}

public enum CoachPacketBodyKind: String, Equatable, Sendable { case weight, waist }
public enum CoachPacketBodySource: String, Equatable, Sendable {
    case labBook = "lab-book", appleHealth = "apple-health", profile
}
public struct CoachPacketBodyReading: Equatable, Sendable {
    public let kind: CoachPacketBodyKind
    public let value: Double             // kg or cm
    public let source: CoachPacketBodySource
    public let day: String?              // nil for the undated profile value
}

public struct CoachPacketPhase: Equatable, Sendable {
    public let name: String
    public let startDay: String
    public let targetWeightKg: Double?
    public let rateLowPercentPerWeek: Double
    public let rateHighPercentPerWeek: Double
}
public enum CoachPacketScorecard: Equatable, Sendable {
    case switchedOff                                             // noop.cutScorecardEnabled is off
    case evaluated(phase: CoachPacketPhase?, result: CutScorecardResult)
}

public struct CoachPacketBaseline: Equatable, Sendable {
    public let center: Double
    public let sigma: Double
    public let status: String            // BaselineStatus.rawValue
    public let nights: Int               // BaselineState.nValid
    public let usable: Bool              // BaselineState.usable
}

public enum CoachPacketStepSource: String, Equatable, Sendable {
    case strap, appleHealth = "apple-health", strapEstimate = "strap-estimate"
}
public struct CoachPacketStepDay: Equatable, Sendable {
    public let day: String
    public let steps: Double
    public let source: CoachPacketStepSource
}

public enum CoachPacketWorkoutSource: String, Equatable, Sendable {
    case whoop, appleHealth = "apple-health", detected, manual,
         liftLog = "lift-log", activityFile = "activity-file"
}
public struct CoachPacketWorkout: Equatable, Sendable {
    public let day: String               // local day of the start
    public let startMinuteOfDay: Int     // 0…1439, local
    public let sport: String
    public let source: CoachPacketWorkoutSource
    public let durationMinutes: Double?
    public let avgHr: Int?
    public let energyKcal: Double?
    public let distanceKm: Double?
}

public struct CoachPacketInput: Equatable, Sendable {
    public let generatedAt: String       // "2031-03-16T07:42:10+01:00"
    public let rangeStartDay: String
    public let rangeEndDay: String       // today
    public let sections: Set<CoachPacketSection>
    public let days: [DailyMetric]
    public let strainFactor: Double      // 1.0 or 0.21
    public let scorecard: CoachPacketScorecard
    public let body: [CoachPacketBodyReading]
    public let hrvBaseline: CoachPacketBaseline?
    public let restingHrBaseline: CoachPacketBaseline?
    public let steps: [CoachPacketStepDay]
    public let workouts: [CoachPacketWorkout]
}

public enum CoachPacket {
    public static let formatName: String        // "NOOP-COACH-PACKET"
    public static let formatVersion: Int        // 1
    public static let weeklyRowLimit: Int       // 8
    public static let workoutRowLimit: Int      // 20
    public static let freeTextByteLimit: Int    // 48

    /// The packet text. Ends with exactly one "\n".
    public static func render(_ input: CoachPacketInput) -> String
    /// The size the packet must stay under, in UTF-8 bytes: 8000 + 220 × rangeDays.
    public static func byteBudget(rangeDays: Int) -> Int
    /// Every calendar day from `start` to `end` inclusive, ascending; empty when either key is
    /// invalid or `end` is before `start`. Day keys follow stage 1 ruling R5.
    public static func dayKeys(from start: String, to end: String) -> [String]
    /// One line of free text: control characters and line breaks become spaces, runs of spaces
    /// collapse, the ends are trimmed, `"` becomes `'`, and the result is cut at a character
    /// boundary to at most `freeTextByteLimit` UTF-8 bytes. Empty input gives "unnamed".
    public static func sanitize(_ text: String) -> String
    /// What must not leave the phone, found in `text` (§7.11). Empty means the text may leave.
    public static func privacyViolations(in text: String, identifiers: [String]) -> [String]
}
```

`DailyMetric` and `CutScorecardResult` are `Equatable` already. If `DailyMetric` cannot be marked
`Sendable` from this package, `CoachPacketInput` drops `Sendable`; nothing here depends on it.

Input handling, so that `render` is total:

- `rangeStartDay` or `rangeEndDay` invalid, or the end before the start: the packet is the header
  with `range: invalid`, no sections, and the notes.
- A row, step day, workout or body reading whose day is outside the range or invalid is ignored
  (body readings are never filtered by range: they are current values).
- Two `days` rows for one day: the last in the array wins. Two step days for one day: the last wins.
- Any non-finite or non-positive weight, waist, baseline centre or sigma makes that item absent.
  A non-finite or negative step count, duration, energy or distance is absent. A heart rate outside
  1…300 is absent. `startMinuteOfDay` outside 0…1439 prints `--:--`.

## 7. The format, version 1

Plain text, UTF-8, `\n` line ends, no tabs, no trailing spaces, one blank line between sections, one
trailing newline. English whatever the interface language. ISO day keys. Metric units. Fixed section
order: header, scorecard, weigh-ins, recovery and sleep, trends, activity, notes. Rows run oldest
first everywhere.

### 7.1 Number formats

All through `String(format:)` with no locale, so the decimal separator is always a point.

| Quantity | Format |
|---|---|
| kg, cm | `%.1f` |
| percent per week, kg per week, km | `%.2f` |
| weeks remaining | `%.1f` |
| grams, kcal, steps, minutes, bpm, ms in trends | `Int(x.rounded())` |
| a signed change | the same format with an explicit sign: `+0.4`, `-1.5`, `+0`, `-1` |

A value that would print as negative zero (`-0.0`, `-0.00`, `-0`) prints as its positive form, with
the sign rule then giving `+0.0`, `+0.00` or `+0`.

Enum values print as their `rawValue`. They are the stable identifiers of stage 1 §6.4 and are never
translated.

### 7.2 Header

Always present, exactly these eight lines:

```
NOOP-COACH-PACKET v1
generated: <generatedAt>
range: <start>..<end> (<n> days; the last day is today and is partial)
sections: <included section ids in fixed order, joined by ", " | none>
switched-off: <the other version-1 section ids in fixed order, joined by ", " | none>
not-recorded-by-app: intake, events
units: kg, cm, hours (h), ms, bpm, steps, kcal, km; dates are YYYY-MM-DD in the phone's time zone
missing: "—" means NOT MEASURED, never zero
```

`generatedAt` is local time with its UTC offset and no zone name (§15 P4). `not-recorded-by-app` is a
constant in version 1. It is how the packet says that intake and events are absent because the app
does not hold them, which is different from nothing eaten and nothing happening. When stage 3 or 5
adds a section, the name leaves this line, the section gains a case, and the version becomes 2.

**Version rule.** Any change that alters the bytes for some input raises `formatVersion`. The first
line and the last line carry it.

### 7.3 Scorecard

Heading `== SCORECARD ==`.

`CoachPacketScorecard.switchedOff`: one line, `not available: the scorecard is switched off in the app`.

`result.invalidInput != nil`: one line, `not available: the stored rules need attention (<invalidInput>)`.

Otherwise, in this order:

| Line | Template |
|---|---|
| phase | `phase: none active` when `phase` is nil. Else `phase: "<sanitize(name)>" (cut), <started\|starts> <startDay>, <target T kg\|no target>, band <low> to <high> %/week`. `starts` when `verdict.reason == phaseNotStarted`, else `started` |
| judged week | `judged-week: <judgedWeekStart\|none>` |
| verdict | `verdict: <kind>; reason <reason>; rule <rule\|none>; calorie-change <+N kcal\|-N kcal\|none>; overridden <rules joined by ", "\|none>; could-not-check <unevaluatedRules joined by ", "\|none>` |
| three rules, in `result.rules` order | `rule <rule>: <state>, <consecutiveWeeks> of <requiredWeeks> weeks`, with ` (<unknownReason>)` after the state when it is set |
| waist signal | `signal waist: <state> (<reason>)`, then `; now <currentCm> cm` when set, `; reference <referenceCm> cm in week <referenceWeekStart>` when both are set, `; change <signed changeCm> cm` when set |
| lift signal | `signal lifts: <state> (<reason>)`, then `; <commonExercises> exercises in common: <dropped> dropped, <climbed> climbed, <held> held` when `commonExercises > 0`, then `; days <windowStartDay>..<windowEndDay>` when both are set |
| protein signal | `signal protein: <state> (<reason>); <daysAtOrAboveFloor> of <requiredDays> days at or above floor; <daysLogged> days logged; <floor F g\|floor not set>` |
| rate-band signal | `signal rate-band: <state> (<reason>)`, then `; <percentPerWeek> %/week` when set, `; band <low> to <high> %/week` when both are set |
| rate | `rate: <losing\|gaining\|flat> <abs(lossKgPerWeek)> kg/week (<abs(percentPerWeek)> %/week of <referenceWeightKg> kg); fitted over <pointsUsed> weigh-ins, weeks <firstWeekStart>..<lastWeekStart>`. `losing` when the quantized loss is above 0, `gaining` below, `flat` at 0. With no rate: `rate: not available (<rateUnavailable>)` |
| projection | `projected`: `projection: <targetDay> (estimate), <weeksRemaining> weeks, <remainingKg> kg remaining`. Any other status: `projection: none (<status>)`, then `; <remainingKg> kg remaining` when set |
| rejections | Only when any count is above 0: `ignored-readings: <total> (nonFinite a, nonPositive b, invalidDay c, future d)` |

"Which rules were unknown" is therefore stated once per rule, on its own line, and "which rules the
verdict could not take into account" once, in `could-not-check`. The packet prints the owner's
calorie amount because the result carries it; it never adds advice of its own.

### 7.4 Weigh-ins

Heading `== WEIGH-INS ==`.

```
current weight: <v> kg (<source>[, <day>])        or   current weight: —
current waist: <v> cm (<source>[, <day>])         or   current waist: —
```

Then the weekly block:

- Scorecard switched off: `weekly: not available (the scorecard is switched off in the app)`.
- `result.weeks` empty, or the stored rules invalid: `weekly: no weigh-ins yet`.
- Else the line `weekly, weeks start Monday, the latest reading of a week represents it, last <k> of <total> weeks:`
  with `k = min(total, 8)`, followed by the last `k` elements of `result.weeks`, each
  `  <weekStart>: weight <v> kg (<weightDay>), waist <v> cm (<waistDay>), change <signed> kg`, where
  an absent weight is `weight —`, an absent waist `waist —`, and `change` is the negated
  `weeklyLossKg` (negative means lighter than the week before) or `change —`.

The current values and the weekly points come from one series (stage 1 §8.1), so the last weekly
weight and the current weight agree whenever the newest reading falls in the last listed week.

### 7.5 Recovery and sleep

Heading `== RECOVERY AND SLEEP ==`.

```
per day, oldest first: recovery (0-100), strain (<0-21 scale|0-100 scale>), sleep (h), deep/REM/light (h), eff (%), HRV (ms), RHR (bpm)
  <CoachDayFormat.dayLine(row, style: .packet(strainFactor:))>[ [sleep staged from heart rate only]]
  …one line for every calendar day of the range…
averages over <n> of <N> days with data: <CoachDayFormat.primaryAveragesLine(rows in range, style:)>
```

A calendar day with no row prints the line of a row whose every field is nil. The scale words are
`0-21 scale` when `strainFactor` is below 1 and `0-100 scale` otherwise. The suffix appears when the
row's `sleepHrOnly` is true. With no row in the range the last line is `averages: no data in range`.
`n` counts days that have a row; `N` is the range length.

### 7.6 Trends

Heading `== TRENDS ==`.

```
baseline is the app's personal baseline behind the recovery score; typical is baseline plus or minus one sigma
HRV: <baseline clause>; <range clause>[; <last-7 clause>][; <outside clause>]
RHR: <baseline clause>; <range clause>[; <last-7 clause>][; <outside clause>]
```

| Clause | Template |
|---|---|
| baseline, usable | `baseline <B> <unit> (typical <lo> to <hi>, <status>, <nights> nights)` with `B = round(center)`, `lo = round(center − sigma)`, `hi = round(center + sigma)` |
| baseline, not usable | `baseline not established (<status>, <nights> nights)` |
| baseline, nil | `baseline not available` |
| range | `range mean <M> <unit> over <k> nights` and, with a usable baseline, ` (<signed M − B> vs baseline)`. With no value in the range: `range mean — over 0 nights` |
| last 7 | Only when the range is longer than 7 days and has at least one value in its last seven calendar days: `last 7 days mean <M7> <unit> over <k7> nights` and, with a usable baseline, ` (<signed M7 − B> vs baseline)` |
| outside | Only with a usable baseline and at least one value: `outside typical: <a> below, <b> above`, counting values below `center − sigma` and above `center + sigma`, unrounded |

Units are `ms` for HRV (`avgHrv`) and `bpm` for RHR (`restingHr`). The differences are differences
of the printed integers, so the line's arithmetic can be checked by eye. The section gives numbers
only. It does not say whether a difference is good or bad.

### 7.7 Activity

Heading `== ACTIVITY ==`.

```
steps per day; "strap-estimate" is an estimate from strap motion, not a count:
  <day>: <steps> <source>[ (today so far)]      or    <day>: ~<steps> strap-estimate[ (today so far)]     or    <day>: —
  …one line for every calendar day of the range…
steps average: <A> over <n> of <N−1> full days (<source c>, …)
```

The average leaves out the last day, which is today and partial. Its source counts list only the
sources that occur, in the order `strap`, `apple-health`, `strap-estimate`. With no full day that
has a value: `steps average: — (no step data in range)`. Sources are never summed and a missing day
is never filled.

Workouts follow:

```
workouts in range, oldest first, summaries only:
  <day> <HH:MM> <sanitize(sport)>, <D min|— min>, avg HR <H bpm|—>, <K kcal|— kcal>[, <km> km] [<source>]
```

Ordered by day, then start minute. At most the 20 latest are listed; when more exist a line
`  (<m> earlier workouts in range not shown)` comes first. With none:
`workouts: none recorded in range`. A workout's strain score is not printed (§15 P6).

### 7.8 Notes

Always present, constant in version 1:

```
== NOTES ==
measured: weight and waist as entered, heart rate, HRV and resting heart rate from the strap, steps marked apple-health or strap.
estimated by the app: recovery and strain scores (not WHOOP's scores), sleep duration and stages, steps marked strap-estimate, calories, the projection date.
the app cannot know: food intake, lifting loads beyond imported sessions, anything on a day the strap was not worn, how the owner feels.
the verdict is the owner's own rule applied to the owner's own numbers; the app changed nothing and makes no medical claim.
end of NOOP-COACH-PACKET v1
```

### 7.9 Complete example

The full fixture of §13 with every section on. This is golden file G1.

```
NOOP-COACH-PACKET v1
generated: 2031-03-16T07:42:10+01:00
range: 2031-03-03..2031-03-16 (14 days; the last day is today and is partial)
sections: scorecard, weigh-ins, recovery-sleep, trends, activity
switched-off: none
not-recorded-by-app: intake, events
units: kg, cm, hours (h), ms, bpm, steps, kcal, km; dates are YYYY-MM-DD in the phone's time zone
missing: "—" means NOT MEASURED, never zero

== SCORECARD ==
phase: "Fixture cut" (cut), started 2031-01-06, target 94.0 kg, band 0.40 to 1.20 %/week
judged-week: 2031-03-10
verdict: holdSteady; reason noChangeRuleFired; rule none; calorie-change none; overridden none; could-not-check liftsDropping
rule liftsHoldingWaistShrinking: unknown (liftSignalUnknown), 0 of 1 weeks
rule liftsDropping: unknown (liftSignalUnknown), 0 of 2 weeks
rule slowLoss: notFired, 0 of 3 weeks
signal waist: met (shrinking); now 91.0 cm; reference 92.5 cm in week 2031-02-17; change -1.5 cm
signal lifts: unknown (noLiftData); days 2031-03-08..2031-03-14
signal protein: unknown (noProteinData); 0 of 5 days at or above floor; 0 days logged; floor 150 g
signal rate-band: met (withinBand); 0.41 %/week; band 0.40 to 1.20 %/week
rate: losing 0.40 kg/week (0.41 %/week of 97.4 kg); fitted over 4 weigh-ins, weeks 2031-02-17..2031-03-10
projection: 2031-05-13 (estimate), 8.5 weeks, 3.4 kg remaining

== WEIGH-INS ==
current weight: 97.4 kg (lab-book, 2031-03-15)
current waist: 91.0 cm (lab-book, 2031-03-15)
weekly, weeks start Monday, the latest reading of a week represents it, last 8 of 10 weeks:
  2031-01-20: weight 100.6 kg (2031-01-25), waist 93.5 cm (2031-01-25), change -0.6 kg
  2031-01-27: weight 100.0 kg (2031-02-01), waist 93.0 cm (2031-02-01), change -0.6 kg
  2031-02-03: weight 99.4 kg (2031-02-08), waist 92.5 cm (2031-02-08), change -0.6 kg
  2031-02-10: weight —, waist —, change —
  2031-02-17: weight 98.6 kg (2031-02-22), waist 92.5 cm (2031-02-22), change —
  2031-02-24: weight 98.2 kg (2031-03-01), waist 92.0 cm (2031-03-01), change -0.4 kg
  2031-03-03: weight 97.8 kg (2031-03-08), waist 91.5 cm (2031-03-08), change -0.4 kg
  2031-03-10: weight 97.4 kg (2031-03-15), waist 91.0 cm (2031-03-15), change -0.4 kg

== RECOVERY AND SLEEP ==
per day, oldest first: recovery (0-100), strain (0-21 scale), sleep (h), deep/REM/light (h), eff (%), HRV (ms), RHR (bpm)
  2031-03-03: recovery 62, strain 9.9, sleep 7.4h, deep 1.3h, REM 1.7h, light 4.4h, eff 91%, HRV 58ms, RHR 54bpm
  2031-03-04: recovery 71, strain 8.0, sleep 7.7h, deep 1.4h, REM 1.8h, light 4.5h, eff 93%, HRV 63ms, RHR 52bpm
  2031-03-05: recovery 55, strain 13.0, sleep 6.7h, deep 1.1h, REM 1.5h, light 4.1h, eff 88%, HRV 52ms, RHR 56bpm
  2031-03-06: recovery 48, strain 6.3, sleep 6.3h, deep 1.0h, REM 1.4h, light 3.9h, eff 86%, HRV 47ms, RHR 58bpm
  2031-03-07: recovery —, strain —, sleep —, deep —, REM —, light —, eff —, HRV —, RHR —
  2031-03-08: recovery 66, strain 9.2, sleep 7.5h, deep 1.4h, REM 1.8h, light 4.4h, eff 92%, HRV 60ms, RHR 53bpm
  2031-03-09: recovery 74, strain 5.2, sleep 8.0h, deep 1.5h, REM 1.9h, light 4.6h, eff 94%, HRV 66ms, RHR 51bpm
  2031-03-10: recovery 60, strain 10.5, sleep 7.2h, deep 1.2h, REM 1.6h, light 4.3h, eff 90%, HRV 57ms, RHR 54bpm
  2031-03-11: recovery 58, strain 8.6, sleep 7.0h, deep —, REM —, light —, eff —, HRV 55ms, RHR 55bpm [sleep staged from heart rate only]
  2031-03-12: recovery 64, strain 12.2, sleep 7.3h, deep 1.3h, REM 1.6h, light 4.4h, eff 91%, HRV 59ms, RHR 54bpm
  2031-03-13: recovery —, strain 7.3, sleep —, deep —, REM —, light —, eff —, HRV —, RHR —
  2031-03-14: recovery 69, strain 9.7, sleep 7.6h, deep 1.4h, REM 1.7h, light 4.5h, eff 92%, HRV 62ms, RHR 52bpm
  2031-03-15: recovery 72, strain 6.9, sleep 7.8h, deep 1.4h, REM 1.8h, light 4.5h, eff 93%, HRV 64ms, RHR 52bpm
  2031-03-16: recovery 67, strain 1.3, sleep 7.5h, deep 1.4h, REM 1.7h, light 4.5h, eff 92%, HRV 61ms, RHR 53bpm
averages over 13 of 14 days with data: recovery: 64, strain: 8.3, sleep: 7.3h, HRV: 59 ms, RHR: 54 bpm

== TRENDS ==
baseline is the app's personal baseline behind the recovery score; typical is baseline plus or minus one sigma
HRV: baseline 57 ms (typical 51 to 64, trusted, 21 nights); range mean 59 ms over 12 nights (+2 vs baseline); last 7 days mean 60 ms over 6 nights (+3 vs baseline); outside typical: 1 below, 2 above
RHR: baseline 54 bpm (typical 52 to 56, trusted, 21 nights); range mean 54 bpm over 12 nights (+0 vs baseline); last 7 days mean 53 bpm over 6 nights (-1 vs baseline); outside typical: 1 below, 1 above

== ACTIVITY ==
steps per day; "strap-estimate" is an estimate from strap motion, not a count:
  2031-03-03: 9120 apple-health
  2031-03-04: 11240 apple-health
  2031-03-05: 8460 apple-health
  2031-03-06: ~7300 strap-estimate
  2031-03-07: —
  2031-03-08: 12080 apple-health
  2031-03-09: 6540 apple-health
  2031-03-10: 9870 apple-health
  2031-03-11: 10310 apple-health
  2031-03-12: 8890 apple-health
  2031-03-13: ~5200 strap-estimate
  2031-03-14: 9640 apple-health
  2031-03-15: 13020 apple-health
  2031-03-16: 1480 apple-health (today so far)
steps average: 9306 over 12 of 13 full days (apple-health 10, strap-estimate 2)
workouts in range, oldest first, summaries only:
  2031-03-03 18:10 strength, 62 min, avg HR 108 bpm, 380 kcal [lift-log]
  2031-03-05 07:05 cycling, 45 min, avg HR 132 bpm, 410 kcal, 18.40 km [apple-health]
  2031-03-08 18:20 strength, 58 min, avg HR —, — kcal [lift-log]
  2031-03-10 06:50 walking, 40 min, avg HR 96 bpm, 170 kcal, 3.60 km [detected]
  2031-03-12 18:05 strength, 65 min, avg HR 110 bpm, 400 kcal [lift-log]

== NOTES ==
measured: weight and waist as entered, heart rate, HRV and resting heart rate from the strap, steps marked apple-health or strap.
estimated by the app: recovery and strain scores (not WHOOP's scores), sleep duration and stages, steps marked strap-estimate, calories, the projection date.
the app cannot know: food intake, lifting loads beyond imported sessions, anything on a day the strap was not worn, how the owner feels.
the verdict is the owner's own rule applied to the owner's own numbers; the app changed nothing and makes no medical claim.
end of NOOP-COACH-PACKET v1
```

It is 6,221 UTF-8 bytes.

### 7.10 Size budget

`CoachPacket.byteBudget(rangeDays:) = 8000 + 220 × rangeDays` bytes: 9,540 for 7 days, 11,080 for 14
(about 3,000 tokens), 14,160 for 28. The bound holds by construction: free text is cut to 48 bytes,
weekly rows stop at 8, workouts at 20, and every other line has a fixed widest form. A typical
14-day packet is a little over 6 kB. The renderer never truncates to meet the budget; a test builds
the widest input and asserts the bound (§12.1).

### 7.11 Privacy scan

`CoachPacket.privacyViolations(in:identifiers:)` returns one description per finding:

- any `identifiers` element of four or more characters occurring in the text, compared without case;
- the literals `my-whoop` and `-noop` (raw storage namespaces; the packet uses its own tokens);
- `/Users/`, `/var/`, `/private/`, `file://`, `~/`;
- a UUID (`8-4-4-4-12` hexadecimal), a MAC address (six colon- or dash-separated hexadecimal pairs);
- an email address (`\S+@\S+\.\S+`).

The assembler passes: every registered device's `id` that is not a fixed namespace constant
(`Repository.whoopSource`, `Repository.appleHealthSource`, `PersonalLiftingImport.deviceId`) and is at
least six characters long, its `nickname` and its `peripheralId`
(`Packages/WhoopStore/Sources/WhoopStore/PairedDevice.swift:7-11`); `repository.deviceId` under the
same rule; every stored ChatGPT profile's `email`, `name`, `subject` and `label`
(`Strand/AI/ChatGPT/ChatGPTAuth.swift:64-72`); the device name; the home directory path.

The scan fails closed. If it finds anything the assembler returns `.blocked` and no text exists to
copy, share or return. By construction nothing should ever be found: the renderer prints source
tokens from closed enums and never a raw `source` string. The scan is the check that this stays true
when a free-text field (a phase name, a sport name) or a later section carries something it should
not.

## 8. App-side logic

### 8.1 The extraction in `AICoach.swift`

Only `Strand/AI/AICoach.swift:1607-1645` and `:1679-1740` change:

- `dayLine(_:)` becomes `CoachDayFormat.dayLine(d, style: .coachContext)`. It stays an internal
  method, so `AICoachSleepContextTests` compiles and passes unedited.
- `efficiencyPercentOrDash(_:)` forwards to `CoachDayFormat.efficiencyPercent`.
- In `buildContext()` the two averages lines become
  `"  " + CoachDayFormat.primaryAveragesLine(last30, style: .coachContext)` and
  `"  " + CoachDayFormat.vitalsAveragesLine(last30)`.
- `hoursOrDash`, `avgOne`, `avgInt` and `avgSleepHours` are deleted.
- The headings, the legend, the row windows, `recentWorkoutsBlock`, `dateString`, the stress line and
  `onDeviceSignalsBlock` are not touched.

The Coach context is the same in both flag states: the extraction is unconditional and changes no
byte. The proof is in §12.2.

### 8.2 One scorecard evaluation

`CutScorecardModel.evaluateStored(today:)` (`CutScorecardModel.swift:196-213`) moves, body unchanged,
to `CutScorecardInputBuilder`:

```swift
/// The stored state as an evaluation, with an upcoming cut phase passed when none is active.
func evaluation(today: String) async -> CutScorecardEvaluation
```

`CutScorecardModel` calls it where it called its private copy. The packet calls the same function.
`CutScorecardEvaluation` (`CutScorecardModel.swift:11`) moves beside the builder. The phase the
packet prints is `evaluation.input.phase`, the phase that was judged.

### 8.3 `CoachPacketSettings`

```swift
final class CoachPacketSettings {
    static let enabledKey = "noop.coachPacketEnabled"
    static let rangeDaysKey = "coachPacket.rangeDays"
    static let sectionsKey = "coachPacket.sections"
    static let allowedRanges = [7, 14, 28]
    static let defaultRangeDays = 14

    init(defaults: UserDefaults = .standard)
    var isEnabled: Bool { get set }
    var rangeDays: Int { get set }                       // a stored value outside allowedRanges reads as 14
    var sections: Set<CoachPacketSection> { get }        // stored choices over each section's default
    func setSection(_ section: CoachPacketSection, on: Bool)
}
```

Reading never writes.

### 8.4 `CoachPacketAssembler`

```swift
struct CoachPacketDocument: Equatable {
    let text: String
    let byteCount: Int
    let generatedAt: Date
    let rangeDays: Int
    let sections: Set<CoachPacketSection>
}
enum CoachPacketOutcome: Equatable {
    case ready(CoachPacketDocument)
    case blocked(findings: Int)          // the privacy scan found something; no text exists
    case unavailable                     // the store could not be read
}

@MainActor
struct CoachPacketAssembler {
    init(repository: Repository, provider: BodyMeasurementProvider,
         scorecardSettings: CutScorecardSettings, settings: CoachPacketSettings,
         now: @escaping () -> Date = { Date() },
         timeZone: @escaping () -> TimeZone = { TimeZone.current },
         effortScale: @escaping () -> EffortScale,
         identifiers: @escaping () -> [String])
    func input() async -> CoachPacketInput?   // nil when the store could not be read
    func assemble() async -> CoachPacketOutcome
    static func live() -> CoachPacketAssembler?   // nil until AppModel.shared exists
}
```

Order of work in `input()`:

1. Before the first suspension, capture once: `now()`, the zone, `settings.rangeDays`,
   `settings.sections`, the effort scale, `scorecardSettings.isEnabled`. One clock gives
   `generatedAt`, today and the range. Today is `LocalDayWindows(timeZone:).dayKey(for:)`, the rule
   stage 1 uses (`CutScorecardModel.swift:149`). The range is today and the `rangeDays − 1` days
   before it.
2. `await provider.refresh()` (`BodyMeasurementProvider.swift:174`), then read
   `provider.current(.weight, consumer: .display)` and the same for waist; drop `profileDefault`.
3. With the scorecard flag on: `CutScorecardInputBuilder.evaluation(today:)`. Off: `.switchedOff`.
4. `repository.days`, filtered to the range.
5. `repository.chargeBaselines`: for HRV and resting heart rate, `center = state.baseline`,
   `sigma = Baselines.sigma(state)`, `status`, `nValid`, `usable`.
6. `repository.resolvedSteps(from:to:)`. A point is `strapEstimate` when its `sourceKey` is
   `steps_est`, `appleHealth` when its `source` is `Repository.appleHealthSource`, else `strap`.
7. `repository.workoutRows(days: rangeDays + 1)`, each mapped through `WorkoutSource.classify`, with
   the local day and start minute taken in the captured zone, duration from `durationS`, distance
   from `distanceM`.

`assemble()` renders, runs the privacy scan with `identifiers()`, and returns `.blocked` or `.ready`.
The assembler reads no setting, table or cache that this list does not name, and it writes nothing.
It does not require the Coach master switch (`noop.coachEnabled`) or the Coach's data consent,
because the app sends nothing (§15 P11).

### 8.5 `CoachPacketModel`

```swift
@MainActor
final class CoachPacketModel: ObservableObject {
    enum State: Equatable { case idle, loading, ready(CoachPacketDocument), blocked, unavailable }
    enum CopyState: Equatable { case none, copied(expiresAt: Date) }

    @Published private(set) var state: State
    @Published private(set) var copyState: CopyState

    init(assemble: @escaping @MainActor () async -> CoachPacketOutcome,
         settings: CoachPacketSettings, pasteboard: CoachPacketPasteboardWriting,
         now: @escaping () -> Date = { Date() })
    func load() async                                   // flag off: .idle, nothing read
    func setSection(_ section: CoachPacketSection, on: Bool) async
    func setRangeDays(_ days: Int) async
    func copy()                                         // only in .ready
    var shareText: String? { get }                      // the previewed text, only in .ready
}
```

Rules, following `docs/STATE_MACHINES.md` and the shape of `CutScorecardModel.load`
(`CutScorecardModel.swift:141-181`):

- A generation counter. A load that finishes after a later one began publishes nothing.
- A changed section or range stores the choice, clears `copyState` and reloads.
- **What is previewed is what leaves.** `copy()` and `shareText` use the document in `state`. They do
  not assemble again.
- `copy()` builds `CoachPacketCopyPlan(text:, copiedAt: now())` and hands it to the pasteboard, then
  sets `.copied(expiresAt: plan.expiresAt)`. The time the sheet shows and the time given to the
  system are the one `expiresAt`.
- With every section off, `copy()` and `shareText` are unavailable.

## 9. Pasteboard, share sheet and Shortcuts

### 9.1 The pasteboard item

```swift
struct CoachPacketCopyPlan: Equatable {
    static let lifetimeSeconds: TimeInterval = 600
    let text: String
    let copiedAt: Date
    var expiresAt: Date { copiedAt.addingTimeInterval(Self.lifetimeSeconds) }
    var localOnly: Bool { true }
}
protocol CoachPacketPasteboardWriting { func write(_ plan: CoachPacketCopyPlan) }
```

The iPhone writer, in `StrandiOS/CoachPacket/CoachPacketPasteboard.swift`:

```swift
UIPasteboard.general.setItems(
    [[UTType.utf8PlainText.identifier: plan.text]],
    options: [.localOnly: plan.localOnly, .expirationDate: plan.expiresAt])
```

`UIPasteboard.OptionsKey.localOnly` and `.expirationDate` are the system's own keys for this.

What the API does and does not do:

- `localOnly` keeps the item off other devices: it is not offered through Universal Clipboard and
  Handoff.
- `expirationDate` has the system remove the item at that time. A later copy of anything replaces it
  sooner.
- It does not stop another app on this iPhone from reading the item when the owner pastes there, or
  when that app reads the pasteboard and the owner allows it.
- The options cannot be read back from the pasteboard, so no unit test can observe them on the real
  pasteboard. Tests assert the plan; the simulator and the device assert the effect (§12.8).
- The app does not clear the pasteboard itself afterwards. Doing so would need the app to be running
  and could remove something else the owner copied since.
- macOS has no expiry on `NSPasteboard`. The sheet is iPhone-only, and no macOS writer is built. The
  shared model compiles for macOS against the protocol.

### 9.2 The share sheet

`CoachPacketShareSheet` wraps `UIActivityViewController` (precedent
`Strand/System/FileExport.swift:131`) with the text as its one item and
`excludedActivityTypes = [.copyToPasteboard]`. The system's own Copy would write the general
pasteboard with no local-only flag and no expiry, so the sheet's "Copy" is the only copy path
(§15 P8). Everything else in the share sheet is the owner's own choice of destination.

### 9.3 The Shortcuts action

```swift
struct GetCoachPacketIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Coach Packet"
    static var description = IntentDescription(
        "Returns the coach packet as text, using the sections and range chosen in NOOP.")
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String>
}
enum CoachPacketIntentError: Error, CustomLocalizedStringResourceConvertible {
    case switchedOff, notReady, blocked, unavailable
}
```

- It returns `CoachPacketAssembler.live()?.assemble()` and nothing else: the same function, the same
  stored sections and range as the sheet. It has no parameters.
- No dialog. A dialog would put health text on the lock screen or have it spoken.
- `requiresAuthentication`: the phone must be unlocked.
- It waits up to eight seconds for `AppModel.shared` and `repository.loaded`
  (`Strand/App/AppModel.swift:27`, `:447`; `Repository.swift:195`), as `startStrapSyncFromShortcut`
  waits for its link (`StrandiOS/App/AppModel+iOS.swift:52-69`), then throws `.notReady`.
- It does not write the pasteboard. The owner's shortcut adds the system "Copy to Clipboard" action,
  which has its own local-only and expiry settings, or passes the text on directly.
- No entry is added to `NOOPShortcuts` (`NOOPAppIntents.swift:129-157`): no Siri phrase, no tip.
  The action is still listed in the Shortcuts app, because an intent's presence is static. With the
  flag off it throws `.switchedOff`.

## 10. Screens and states

Frames are designed at G1 in `design/round7-coach-packet/`, built on `design/system/noop.css` and
`noop.js`, served by `design/tools/serve.py`, exported as `r7-frames.json`, and imported by a new
plugin command `import7` beside `import6` (`design/figma-plugin/manifest.json:22-30`). Each state
below needs a frame at the default text size and at the largest accessibility size
(`StrandiOS/App/StrandiOSApp.swift:247`). Tokens: `StrandFont.mono` for the preview
(`Packages/StrandDesign/Sources/StrandDesign/Typography.swift:94`, `:112`), existing palette and
components for the rest. No new token is proposed.

### 10.1 Entry points

Present only while `noop.coachPacketEnabled` is on.

| Entry | Where | Behaviour |
|---|---|---|
| Health tab row "Coach packet" | Beneath the Scorecard row in the "More health" card (`StrandiOS/Redesign/RedesignHealthView.swift:474-482`) | Opens the sheet |
| Scorecard screen | A second toolbar item beside the weigh-in button (`StrandiOS/Scorecard/ScorecardView.swift:77-82`) | Opens the sheet |

Both present the sheet with `.sheet`, so `RedesignRoute.swift` is not edited. With the flag off
neither exists and both screens are exactly as they are today. A Today card is not built (§15 P1).

### 10.2 The packet sheet

Top to bottom: title; range choice (7, 14, 28 days); five section switches; a line with the size and
the generated time; the preview in a scrolling monospaced block; "Copy" (primary); "Share"
(secondary).

| State | What shows |
|---|---|
| Loading | Skeleton for the preview (`noopSkeleton`); controls visible, actions disabled |
| Ready | The preview is the exact text that will leave. The size line reads "6.2 kB · 14 days" |
| Ready, nothing measured in the range | The packet is still valid and shows its dashes. A caption says "Nothing was measured in this range" |
| Ready, scorecard off in the app | The Scorecard and Weigh-ins switches stay usable; a caption under them says "The scorecard is off, so these sections say so" |
| A section switched off | The preview regenerates; the header's `switched-off` line names it |
| Every section off | The preview shows header and notes; "Copy" and "Share" are disabled; caption "Switch on at least one section" |
| Regenerating after a change | The previous preview stays, dimmed, until the new one arrives; actions disabled meanwhile |
| Copied | An inline confirmation replaces the size line: "Copied to this iPhone only. It leaves the clipboard at 07:52." No toast, no haptic pattern beyond the standard success |
| Copied, then a control changed | The confirmation clears. The clipboard still holds the earlier text until it expires; the caption says "The clipboard still holds the earlier packet" |
| Share | The system share sheet over this sheet, without its own Copy |
| Blocked | No preview. "The packet was not created because it contained something that identifies a device or an account." A "Try again" action |
| Unavailable | "Your data could not be read. Try again." A "Try again" action |
| Larger than the budget | Not reachable by construction. If it happens the size line says so and the actions stay enabled |
| Reopened later | A fresh packet is assembled each time the sheet opens, and when the app returns to the foreground with the sheet open |
| Largest text size | Controls stack; the preview keeps its monospaced size and scrolls both ways; no number is truncated |
| Reduce Motion | No dimming animation and no entrance animation |

The preview text is not selectable. Selecting part of it and using the system Copy would bypass the
local-only item.

### 10.3 Settings

A card "Coach packet" directly after the Scorecard card (`Strand/Screens/SettingsView.swift:466`,
`:1860`): one switch, "Coach packet", with the blurb in §11. Off by default. No reminder, no
notification.

### 10.4 Shortcuts action states

| State | Result |
|---|---|
| Flag on, data loaded | The text |
| Flag off | Fails with "Coach packet is switched off in NOOP." |
| App still starting after eight seconds | Fails with "NOOP is still starting. Run the shortcut again." |
| Blocked by the scan | Fails with "The packet was not created because it contained something that identifies a device or an account." |
| Store unreadable | Fails with "NOOP could not read your data." |
| Phone locked | The system asks for unlock first |

### 10.5 Widgets and notifications

None. The packet never appears in a widget payload or in notification text.

## 11. User-facing strings

Interface strings go through the String Catalog in all ten locales. The packet text itself is never
localised, never passes through the catalogue, and is shown with `Text(verbatim:)`.

| Where | English source |
|---|---|
| Settings card title and switch | "Coach packet" |
| Settings blurb | "One block of text with your recent numbers, for pasting to your coach. Off by default. NOOP sends it nowhere." |
| Row and sheet title | "Coach packet" |
| Row detail | "Copy your numbers for your coach" |
| Toolbar item accessibility label | "Coach packet" |
| Range label and options | "Range"; "%lld days" |
| Section switches | "Scorecard", "Weigh-ins", "Recovery and sleep", "Trends", "Activity" |
| Size line | "%@ · %lld days" |
| Actions | "Copy", "Share", "Try again" |
| Copied | "Copied to this iPhone only. It leaves the clipboard at %@." |
| Stale clipboard | "The clipboard still holds the earlier packet" |
| Nothing measured | "Nothing was measured in this range" |
| Scorecard off | "The scorecard is off, so these sections say so" |
| All off | "Switch on at least one section" |
| Blocked | "The packet was not created because it contained something that identifies a device or an account." |
| Unavailable | "Your data could not be read. Try again." |
| Intent title and description | "Get Coach Packet"; "Returns the coach packet as text, using the sections and range chosen in NOOP." |
| Intent errors | "Coach packet is switched off in NOOP."; "NOOP is still starting. Run the shortcut again."; "NOOP could not read your data." |

`CoachPacketPresenter` owns every one of these, as `CutScorecardPresenter` does for stage 1, so the
views contain no literal copy. None of them states or implies a health outcome.

## 12. Test plan

One named test per line. Names state the behaviour protected. Golden expectations are Swift string
literals in a test source file; the package's test target has no resources and `Package.swift` is not
edited.

### 12.1 Pure logic — `Packages/StrandAnalytics/Tests/StrandAnalyticsTests/`

`CoachDayFormatTests.swift`

- `testCoachStyleLineMatchesTheFrozenLegacyLine`
- `testPacketStyleLineUsesRecoveryStrainSleepAndAPlainColon`
- `testBothStylesShareTheSameValueTokens` (strip the labels: the nine values are equal with factor 1)
- `testEveryAbsentFieldPrintsTheDashAndNoFieldIsDropped`
- `testStrainFactorScalesTheLineAndTheAverage`
- `testStrainFactorOfOneReproducesTheStoredValue`
- `testEfficiencyStoredAsAPercentageIsNotMultipliedAgain`
- `testEfficiencyOutsideItsRangePrintsTheDash`
- `testNonFiniteAndHugeValuesPrintTheDashAndDoNotTrap`
- `testPrimaryAveragesMatchTheFrozenLegacyLine`
- `testVitalsAveragesMatchTheFrozenLegacyLine`
- `testAveragesOfNoRowsPrintDashesWithTheirUnits`
- `testGeneratedSpreadMatchesTheFrozenLegacyFormatter` (500 seeded random rows and row lists)

The "frozen legacy" is a private copy, in the test file, of `AICoach.swift:1679-1740` as it stands at
`0b89b814`, taking a `DailyMetric`. It is the oracle for byte identity and is never edited.

`CoachPacketTests.swift` with `CoachPacketGolden.swift` and `CoachPacketFixture.swift`

- `testFullFixtureMatchesGoldenG1`
- `testScorecardSectionOffMatchesGolden`, and the same for `WeighIns`, `RecoverySleep`, `Trends`,
  `Activity` (five tests): the section's lines are gone, the header lists it under `switched-off`,
  every other line is unchanged
- `testEverySectionOffLeavesHeaderAndNotes`
- `testNoDataAtAllMatchesGoldenG2` (§13.3)
- `testRangeWithUnmeasuredDaysPrintsALineForEachDay`
- `testRangeAcrossAMonthBoundaryListsEveryDay`
- `testRangeAcrossAYearBoundaryListsEveryDay`
- `testRangeAcrossTheEndOfFebruaryInALeapYear`
- `testSevenDayRangeOmitsTheLastSevenClause`
- `testTwentyEightDayRangeStaysOrdered`
- `testInvalidRangePrintsHeaderAndNotesOnly`
- `testScorecardSwitchedOffSaysSoInBothSections`
- `testInvalidRulesSaySoAndPrintNoVerdict`
- `testNoActivePhasePrintsNoneActive`
- `testPhaseNotStartedPrintsStarts`
- `testEachVerdictKindAndReasonPrintsItsRawValue`
- `testCalorieChangeCarriesItsSign`
- `testUnknownRulePrintsItsReason`
- `testCouldNotCheckListsTheUnevaluatedRules`
- `testOverriddenRulesAreListed`
- `testEachSignalPrintsOnlyTheClausesItHas`
- `testGainingAndFlatRatesAreWorded`
- `testRateUnavailablePrintsItsReason`
- `testEachProjectionStatusPrints`
- `testRejectedReadingsAreCounted`
- `testWeeklyBlockStopsAtEightWeeks`
- `testMissedWeekPrintsDashesAndTheNextChangeIsADash`
- `testCurrentValueFromTheProfileHasNoDay`
- `testAbsentCurrentWaistPrintsADash`
- `testBaselineNotUsablePrintsItsStatus`
- `testBaselineNilPrintsNotAvailable`
- `testOutsideTypicalCountsUseTheUnroundedBand`
- `testDifferencesAreDifferencesOfThePrintedIntegers`
- `testEstimatedStepsCarryATildeAndTheirSource`
- `testStepAverageLeavesOutToday`
- `testStepAverageWithNoFullDaySaysSo`
- `testMissingStepDayPrintsADashNotZero`
- `testWorkoutWithNothingButATimePrintsDashes`
- `testMoreThanTwentyWorkoutsPrintsTheCount`
- `testNoWorkoutsSaysSo`
- `testFreeTextIsOneLineQuotedSafelyAndCutAtFortyEightBytes`
- `testNegativeZeroNeverPrints`
- `testNoZeroIsPrintedForAMissingValue` (every numeric field nil: the text has no standalone `0`)
- `testSameInputGivesTheSameBytes`
- `testDuplicateDayKeepsTheLastRow`
- `testItemsOutsideTheRangeAreIgnored`
- `testNonFiniteInputsAreAbsentAndNothingTraps`
- `testTextEndsWithOneNewlineAndHasNoTrailingSpacesOrTabs`
- `testFirstAndLastLinesCarryTheVersion`
- `testFullFixtureIsWithinTheBudget`
- `testWidestPossibleInputIsWithinTheBudgetForEachRange` (7, 14, 28)
- `testIntakeAndEventsNeverAppearAsSections` (no `== INTAKE ==`, no `== EVENTS ==`, and the header
  names both as not recorded)

`CoachPacketPrivacyTests.swift`

- `testCleanFixtureHasNoFindings`
- `testEachKnownIdentifierIsFoundWhateverItsCase`
- `testShortIdentifiersAreNotSearchedFor`
- `testRawNamespacesAreFound`
- `testPathsUuidsMacAddressesAndEmailsAreFound`
- `testThePacketsOwnSourceTokensAreNotFindings`
- `testFixtureIdentifiersPlantedInFreeTextAreFound` (a device name as a phase name, an email as a
  sport name)

### 12.2 Byte identity of the in-app Coach context — `StrandTests/CoachContextByteIdentityTests.swift`

Written and run **before** the extraction. These tests pass on the untouched code; that is their
purpose, and the commit message says so. They must still pass after it.

- `testBuildContextForTheFixtureEqualsTheRecordedText`: a repository whose `days` is the fixture
  (`Repository.days` is settable, `Repository.swift:184`); the expected literal is the output of the
  untouched code, pasted verbatim.
- `testBuildContextWithNoDaysEqualsTheRecordedText`
- `testBuildContextWithMoreThanThirtyRowsEqualsTheRecordedText`
- `testDayLineForRowsWithEveryFieldAbsentEqualsTheRecordedText`
- `testCoachContextIsTheSameWithThePacketFlagOnAndOff`
- Existing, unedited, still passing: `AICoachSleepContextTests`, `OneNumberPerVariableCoachContextTests`,
  `CoachConversationDayTests`.

### 12.3 App target — `StrandTests/`

`CoachPacketSettingsTests.swift`

- `testFlagDefaultsToOff`
- `testRangeDefaultsToFourteenAndRejectsOtherValues`
- `testSectionsDefaultToOnAndStoredChoicesWin`
- `testSectionsAreStoredWithSortedKeys`
- `testReadingNeverWrites`

`CoachPacketAssemblerTests.swift`

- `testOneClockGivesGeneratedAtTodayAndTheRange`
- `testGeneratedAtCarriesTheOffsetAndNoZoneName`
- `testRangeAcrossADaylightSavingChangeHasTheRightDays`
- `testZoneChangeBetweenTwoAssembliesMovesTheRangeWithTheNewToday`
- `testScorecardFlagOffYieldsSwitchedOff`
- `testStepsAreClassifiedByKeyAndSource`
- `testWorkoutsTakeTheirLocalDayAndMinuteInTheGivenZone`
- `testWorkoutSourcesComeFromTheClassifier`
- `testBaselinesCarryTheSigmaTheRecoveryScreenUses`
- `testUnsetProfileWeightIsNotPrinted`
- `testAPlantedDeviceIdentifierBlocksThePacket`
- `testAssemblyWritesNothing` (defaults and the store are byte-identical before and after)
- `testAssemblyWorksWithTheCoachSwitchOffAndNoConsent`

`CoachPacketSingleSourceTests.swift` (the single-resolver assertions)

- `testPacketWeightAndWaistEqualTheProviderAndTheCoachContextNumber`
- `testPacketScorecardEqualsTheScreenModelsEvaluation` (both come from `evaluation(today:)`)
- `testPacketWeeklyPointsEqualTheScorecardWeeks`
- `testPacketStepsEqualResolvedSteps`
- `testPacketBaselineBandEqualsTheRecoveryFactorBand`
- `testPacketStrainEqualsTheEffortDisplayOnEachScale`
- `testPacketDayValuesEqualTheCoachContextValuesForTheSameRows`
- `testPacketFollowsADeletedWeighIn`

`CoachPacketModelTests.swift`

- `testFlagOffStaysIdleAndReadsNothing`
- `testLoadPublishesReady`
- `testAnOvertakenLoadPublishesNothing`
- `testChangingASectionStoresReloadsAndClearsTheCopiedState`
- `testCopyWritesExactlyThePreviewedText`
- `testCopyPlanIsLocalOnlyAndExpiresInTenMinutes`
- `testTheShownExpiryIsThePlansExpiry`
- `testShareTextIsThePreviewedText`
- `testCopyAndShareAreUnavailableWithEverySectionOff`
- `testBlockedAndUnavailableOfferNoText`
- `testTheIntentPathAndTheSheetPathReturnTheSameText` (both call `assemble()` with one clock)

`CoachPacketPresenterTests.swift`: one test per row of §11, plus `testSizeLineFormatsKilobytes`.

### 12.4 Source scan — `Tools/test_coach_packet_single_formatter.py`

In the Python suite that already asserts on product source.

- `AICoach.swift` calls `CoachDayFormat.dayLine(` and `CoachDayFormat.primaryAveragesLine(`, and no
  longer contains the literals `"deep "`, `"REM "`, `"light "`, `"HRV "` or `"RHR "`.
- Under `Strand/`, `StrandiOS/`, `StrandiOSShared/` and `Packages/*/Sources`, only
  `CoachDayFormat.swift` contains the literal `"REM "`.
- `UIPasteboard` occurs only in an allowlist of file-and-reason pairs: `Platform.swift`,
  `CoachView.swift`, `CoachPacketPasteboard.swift`. The test also asserts each allowlisted file still
  contains it.
- `CoachPacket.swift` and `CoachDayFormat.swift` contain no `String(localized`, `Locale`, `Date(` or
  `TimeZone`.
- `evaluateStored` no longer exists; `CutScorecardModel.swift` and `CoachPacketAssembler.swift` both
  call `evaluation(today:`.

### 12.5 Flag-off equivalence

With `noop.coachPacketEnabled` off: the baseline suite's results are unchanged; no Health row, no
toolbar item, no model, no store read; `testFlagOffStaysIdleAndReadsNothing` and
`testCoachContextIsTheSameWithThePacketFlagOnAndOff` hold. Simulator captures of the Health tab and
the scorecard screen with the flag off are compared with captures from the base commit.

### 12.6 Fault injection

Each is made, a failing test is confirmed, and the file is restored. A fault nothing catches is a
finding.

| Fault | Expected to fail |
|---|---|
| Change the Coach style's separator, a label or the factor | `testCoachStyleLineMatchesTheFrozenLegacyLine`, §12.2 |
| Print `0` in place of the dash for one field | `testNoZeroIsPrintedForAMissingValue`, G1 |
| Drop an absent field from the line | `testEveryAbsentFieldPrintsTheDashAndNoFieldIsDropped` |
| Swap two sections | G1 |
| Print a section although it is off | the five section-off goldens |
| Add an `== INTAKE ==` heading | `testIntakeAndEventsNeverAppearAsSections` |
| Include today in the step average | `testStepAverageLeavesOutToday` |
| Print an estimate without its tilde or source | `testEstimatedStepsCarryATildeAndTheirSource` |
| Use the rounded band for the outside count | `testOutsideTypicalCountsUseTheUnroundedBand` |
| Raise the weekly or workout limit | the two limit tests, the budget test |
| Remove the free-text cut | `testFreeTextIsOneLineQuotedSafelyAndCutAtFortyEightBytes`, the budget test |
| Print a raw `source` string | `testRawNamespacesAreFound`, `testAPlantedDeviceIdentifierBlocksThePacket` |
| Return the text although the scan found something | `testAPlantedDeviceIdentifierBlocksThePacket` |
| Read the clock twice in the assembler | `testOneClockGivesGeneratedAtTodayAndTheRange` |
| Assemble again inside `copy()` | `testCopyWritesExactlyThePreviewedText` |
| Set `localOnly` false or change the lifetime | `testCopyPlanIsLocalOnlyAndExpiresInTenMinutes` |
| Give the packet its own scorecard evaluation | `testPacketScorecardEqualsTheScreenModelsEvaluation`, the source scan |
| Read steps from `DailyMetric.steps` | `testPacketStepsEqualResolvedSteps` |
| Ignore the display scale for strain | `testPacketStrainEqualsTheEffortDisplayOnEachScale` |
| Leave the version out of the last line | `testFirstAndLastLinesCarryTheVersion` |

### 12.7 Parity

None. No Kotlin twin is written (ruling R43). The gate script's `parity-oracle` and Android rows are
waived by flag and reported as waived. The frozen-legacy oracle of §12.1 guards the one thing a
Kotlin twin mirrors, the Coach day line, in the Swift direction.

### 12.8 Simulator, device and rehearsal

- **Simulator.** Every frame of §10 reproduced through `--demo-screen packet-<frame>` on synthetic
  data, at the default and the largest text size, Reduce Motion on and off. Flows by tapping: switch
  each section, change the range, copy, share. After a copy, paste into another app in the
  simulator and compare bytes with the preview. After the lifetime has passed,
  `UIPasteboard.general.hasStrings` is false.
- **Device, with the owner.** Copy, then check that a second signed-in Apple device nearby does not
  receive the text, if the owner has one. Run the Shortcuts action and compare its output with the
  sheet's preview taken in the same minute (only `generated:` may differ). Confirm the action asks
  for unlock on a locked phone.
- **Real-data rehearsal.** By the procedure of work package 0B-7: assemble a packet on the private
  copy, run the privacy scan with the real identifiers, check the size against the budget, and read
  every section against the app's screens. The packet text and any screenshot stay under
  `PersonalData/` and are never committed.
- **End to end.** The owner pastes a real packet into Claude with the text of §16 in place and
  confirms each section is read correctly.

## 13. Fixture

"Fixture Person" is fictional. Every value is round and invented. The dates are in 2031, as in
stage 1. App-target tests that read steps or workouts through the repository use dates relative to
the real clock instead (stage 1 ruling R31) and the same values.

### 13.1 Clock, range and settings

Generated at `2031-03-16T07:42:10+01:00`; range `2031-03-03` to `2031-03-16` (14 days); every section
on; strain factor 0.21.

### 13.2 Daily rows (stored strain 0 to 100, sleep and stages in minutes, efficiency as a fraction)

| Day | Recovery | Strain | Sleep | Deep | REM | Light | Eff | HRV | RHR | HR-only |
|---|---|---|---|---|---|---|---|---|---|---|
| 2031-03-03 | 62 | 47 | 444 | 78 | 102 | 264 | 0.91 | 58 | 54 | |
| 2031-03-04 | 71 | 38 | 462 | 84 | 108 | 270 | 0.93 | 63 | 52 | |
| 2031-03-05 | 55 | 62 | 402 | 66 | 90 | 246 | 0.88 | 52 | 56 | |
| 2031-03-06 | 48 | 30 | 378 | 60 | 84 | 234 | 0.86 | 47 | 58 | |
| 2031-03-07 | no row | | | | | | | | | |
| 2031-03-08 | 66 | 44 | 450 | 81 | 105 | 264 | 0.92 | 60 | 53 | |
| 2031-03-09 | 74 | 25 | 480 | 90 | 114 | 276 | 0.94 | 66 | 51 | |
| 2031-03-10 | 60 | 50 | 432 | 75 | 99 | 258 | 0.90 | 57 | 54 | |
| 2031-03-11 | 58 | 41 | 420 | nil | nil | nil | nil | 55 | 55 | true |
| 2031-03-12 | 64 | 58 | 438 | 78 | 96 | 264 | 0.91 | 59 | 54 | |
| 2031-03-13 | nil | 35 | nil | nil | nil | nil | nil | nil | nil | |
| 2031-03-14 | 69 | 46 | 456 | 84 | 102 | 270 | 0.92 | 62 | 52 | |
| 2031-03-15 | 72 | 33 | 468 | 87 | 108 | 273 | 0.93 | 64 | 52 | |
| 2031-03-16 | 67 | 6 | 450 | 81 | 102 | 267 | 0.92 | 61 | 53 | |

Baselines: HRV centre 57.2, sigma 6.4, status `trusted`, 21 nights, usable. Resting heart rate centre
54.1, sigma 2.2, `trusted`, 21 nights, usable.

### 13.3 Scorecard, body, steps and workouts

The scorecard is a `CutScorecardResult` built by hand for the renderer, not the output of
`evaluate`: the renderer prints whatever result it is given. Phase "Fixture cut", started
2031-01-06, target 94.0 kg, band 0.40 to 1.20. Judged week 2031-03-10. Verdict `holdSteady`, reason
`noChangeRuleFired`, no rule, no calorie change, nothing overridden, unevaluated `liftsDropping`.
Rules: 1 unknown (`liftSignalUnknown`) 0 of 1; 2 unknown (`liftSignalUnknown`) 0 of 2; 3 `notFired`
0 of 3. Waist signal met, `shrinking`, 91.0 against 92.5 in week 2031-02-17, change −1.5. Lift signal
unknown, `noLiftData`, no counts, window 2031-03-08 to 2031-03-14. Protein signal unknown,
`noProteinData`, 0 of 5, 0 logged, floor 150. Rate-band signal met, `withinBand`, 0.41, bounds as the
phase. Rate: loss 0.40, 0.41 percent of 97.4, 4 points, weeks 2031-02-17 to 2031-03-10. Projection
`projected`, 2031-05-13, 8.5 weeks, 3.4 kg. No rejections.

Weeks, ten in all from 2031-01-06; the last eight are those printed in §7.9, with the week of
2031-02-10 missed. Current weight 97.4 kg and waist 91.0 cm, both Lab Book, both dated 2031-03-15.

Steps and workouts are exactly those printed in §7.9. 2031-03-07 has no step value. The two
`strap-estimate` days are 2031-03-06 and 2031-03-13.

**Golden G2, no data at all.** The same clock and range, every list empty, both baselines nil, no
body reading, scorecard `evaluated` with no phase and the stage 1 result for no readings. Every day
prints a line of dashes; the averages line is `averages: no data in range`; both trend lines read
`baseline not available; range mean — over 0 nights`; steps print dashes and
`steps average: — (no step data in range)`; `workouts: none recorded in range`.

### 13.4 Identifiers for the privacy tests

Invented: device id `FIXTURE-STRAP-0001`, nickname `Fixture Band`, peripheral
`00000000-0000-4000-8000-000000000001`, account `fixture.person@example.invalid`, device name
`Fixture Phone`, home `/Users/fixture`.

## 14. Work packages and file ownership

A package edits only the files listed for it.

| WP | Role | Files |
|---|---|---|
| 2-2 | Designer | `design/round7-coach-packet/*`; `design/figma-plugin/code.js`, `manifest.json` (command `import7`) |
| 2-3 | Test author | `Packages/StrandAnalytics/Tests/StrandAnalyticsTests/CoachDayFormatTests.swift`, `CoachPacketTests.swift`, `CoachPacketGolden.swift`, `CoachPacketFixture.swift`, `CoachPacketPrivacyTests.swift`; `StrandTests/CoachContextByteIdentityTests.swift`, `CoachPacketSettingsTests.swift`, `CoachPacketAssemblerTests.swift`, `CoachPacketSingleSourceTests.swift`, `CoachPacketModelTests.swift`, `CoachPacketPresenterTests.swift`; `Tools/test_coach_packet_single_formatter.py` |
| 2-4a | Implementer A | New: `Packages/StrandAnalytics/Sources/StrandAnalytics/CoachDayFormat.swift`, `CoachPacket.swift`. Edited, extraction only: `Strand/AI/AICoach.swift` |
| 2-4b | Implementer B | New: `Strand/Data/CoachPacketSettings.swift`, `CoachPacketAssembler.swift`, `CoachPacketModel.swift`, `CoachPacketPresenter.swift`. Edited, the move of §8.2 only: `Strand/Data/CutScorecardInputBuilder.swift`, `Strand/Data/CutScorecardModel.swift` |
| 2-5 | Implementer C, after G1 and after 2-4a and 2-4b merge | New: `StrandiOS/CoachPacket/CoachPacketSheet.swift`, `CoachPacketPasteboard.swift`, `CoachPacketShareSheet.swift`, `CoachPacketDemo.swift`; `StrandiOS/System/CoachPacketIntent.swift`. Edited: `Strand/Screens/SettingsView.swift` (the card), `StrandiOS/Redesign/RedesignHealthView.swift` (the row), `StrandiOS/Scorecard/ScorecardView.swift` (the toolbar item), `StrandiOS/App/StrandiOSApp.swift` (one line of the debug block) |
| 2-6 | Localiser | `Strand/Resources/Localizable.xcstrings` |
| 2-7 | Orchestrator, with the owner's approval of the wording | Nothing in the repository. The text is §16 |
| 2-8 | Reviewers, Verifier | None; read-only |

2-3, 2-4a and 2-2 start together. 2-4b starts with them and merges after 2-4a. The byte-identity
tests of §12.2 are committed and run green before 2-4a touches `AICoach.swift`.

### 14.1 Shared hotspots this stage edits

| File | Edit | Size |
|---|---|---|
| `Strand/Resources/Localizable.xcstrings` | The strings of §11 | About thirty keys, sole writer 2-6 |
| `Strand/Screens/SettingsView.swift` | One card and its mount, after the Scorecard card (`:466`, `:1860`) | About thirty lines |
| `StrandiOS/App/StrandiOSApp.swift` debug block | `:623` becomes `ScorecardDemo.screen(named: name) ?? CoachPacketDemo.screen(named: name)` | One line |
| `Strand/AI/AICoach.swift` | §8.1 | Two regions |

### 14.2 Shared hotspots this stage does not edit

`Strand/Screens/DashboardCards.swift`, `Strand/Data/TodayCardReadout.swift`, the three Today views,
`Packages/StrandImport/.../MarkerCatalog.swift`, `project.yml`, the backup whitelist, `Database.swift`,
`StrandiOS/System/NOOPAppIntents.swift`, `StrandiOS/Redesign/RedesignRoute.swift`, the widget payload
types.

### 14.3 Beside other stages

May run in parallel with any other stage: 2-2, 2-3, all new files of 2-4a, 2-4b and 2-5.

Must be serialised with other stages, by the orchestrator, in this order of risk:

1. `Localizable.xcstrings`: one Localiser at a time across all stages.
2. `Strand/Data/CutScorecardInputBuilder.swift`: stage 3 is expected to change where protein days
   come from (`CutScorecardInputBuilder.swift:13-14`, `:51`). The move of §8.2 lands first.
3. `Strand/Screens/SettingsView.swift`, `StrandiOS/Redesign/RedesignHealthView.swift`,
   `StrandiOS/Scorecard/ScorecardView.swift`: any stage adding a card, a Health row or a scorecard
   toolbar item.
4. The debug block's one line: each stage appends one `??` term. The orchestrator may prefer to land
   a single registry line once for all stages.
5. `Strand/AI/AICoach.swift`: any stage that adds to the Coach context waits for 2-4a.

A later stage that adds a packet section owns a version bump: a new `CoachPacketSection` case, a new
input field, the removal of its name from `not-recorded-by-app`, new goldens and an update to §16.

### 14.4 Android disposition (ruling R43)

Recorded in place of a Kotlin twin:

- `CoachDayFormat` reproduces `AICoach.dayLine` and the averages byte for byte. Its existing Kotlin
  counterpart is `AiCoach.buildContext` (`AiCoach.kt:405`), unchanged. **Drift created: none.**
- `CoachPacket`, the assembler, the settings and the screens have no Kotlin counterpart. Android
  gains no packet. **Not updated, by the owner's decision.**
- Stored-data contracts: no backup key, no marker-catalogue key, no migration, no stored value.
  **Drift created: none.**
- New public declarations in `Packages/StrandAnalytics` carry the comment "No Kotlin twin, by the
  owner's decision (stage 2 specification §14.4)". Their effect on the parity ledger is in §18.

## 15. Open questions for the owner

Work proceeds on each recommendation.

| # | Question | Recommendation, in force until overruled |
|---|---|---|
| P1 | Where is the packet opened from? | A row in the Health tab and a button on the scorecard screen. No Today card: it would edit five files every other stage also edits, and the Shortcuts action already gives a one-tap route from the Home Screen or the Action Button |
| P2 | How long may the copied packet stay on the clipboard? | Ten minutes |
| P3 | Which strain scale does the packet use? | The one the app shows, named in the section's first line. The in-app Coach keeps the stored 0 to 100 scale, because its text must not change |
| P4 | Should `generated:` carry the zone's name? | No, the UTC offset only. A zone name hints at a location and the coach does not need it |
| P5 | The phase name and workout names are free text the owner typed or imported. May they be in the packet? | Yes, as one line each, cut to 48 bytes |
| P6 | Should a workout's strain score be printed? | No. Duration, average heart rate and calories are. The lifting detail comes from the lifting log the owner pastes separately |
| P7 | Which ranges? | 7, 14 and 28 days, 14 by default |
| P8 | May the share sheet's own Copy be removed? | Yes, so that the only copy is the local-only, expiring one |
| P9 | May the Shortcuts action exist with no Siri phrase and require an unlocked phone? | Yes |
| P10 | Reading the code found defects in the in-app Coach's text that this stage must leave alone: the comma after each day's colon (C2); its step average reading a different source from every screen (C8); and two clipboard writers with no local-only flag (C5). Fix them? | Not in this stage, whose acceptance is that the in-app Coach is unchanged. Record them for a separate change |
| P11 | Should the packet work with the in-app Coach switched off and with no data consent given to a provider? | Yes. The consent is about sending data to a provider; the packet sends nothing |
| P12 | The scorecard's protein signal can appear in the packet before stage 3, from an imported nutrition file, while the intake section is absent. Acceptable? | Yes. It is part of the scorecard result, and the line says what it counted |
| P13 | Should Lab Book markers beyond weight and waist ever be in the packet? | Not in version 1. When stage 4 adds them they arrive as a section that is off by default |
| P14 | Should the packet's choices (range and sections) be in backups? | No. They are a per-install preference, and leaving them out keeps the backup contract untouched |

Needing the owner's go-ahead in the sense of the standing rules (migration, Health access, build
target, entitlement, network path): **nothing**. Owner gates that remain: the design approval (G1),
the wording of §16, and any install on the phone.

## 16. The Claude-side half

Text for the owner to paste. Neither block contains anything personal.

### 16.1 For the training document: "Reading the packet"

```
## Reading the packet

The app can produce a text block that starts with the line "NOOP-COACH-PACKET v1" and ends with
"end of NOOP-COACH-PACKET v1". When I paste one, read it by these rules.

1. Check the first and last lines. If the last line is missing, the paste was cut short: say so and
   ask for it again. If the version is higher than 1, read the sections you recognise and tell me
   which lines you did not recognise. Do not guess at them.
2. The header says what is in the block. "sections" lists what is included. "switched-off" lists
   what I chose to leave out. "not-recorded-by-app" lists what the app does not hold at all. A
   section that is not in the block tells you nothing: it does not mean zero, and it does not mean
   nothing happened.
3. A long dash means NOT MEASURED. Never read it as zero, and never average across it as if it were
   a value.
4. Dates are YYYY-MM-DD. Units are metric. Rows run oldest first. The last day of the range is
   today and is incomplete.
5. SCORECARD is the app applying my own written rules to my own weigh-ins. Words such as
   "holdSteady" or "liftSignalUnknown" are fixed identifiers. A rule marked "unknown" was not
   evaluated: name it and say what would be needed to evaluate it. "could-not-check" lists rules
   that might have changed the verdict. Treat the verdict as the output of my rules and not as your
   own conclusion; if you disagree with it, say why.
6. WEIGH-INS gives one point per week, starting Monday. "change" is against the week before, and a
   negative change means lighter. Expect noise week to week.
7. RECOVERY AND SLEEP: recovery and strain are the app's own scores, not WHOOP's, and the first line
   of the section names the strain scale. Sleep stages are estimates. A line tagged "sleep staged
   from heart rate only" is a weaker estimate.
8. TRENDS compares the range with the app's own baseline. It gives numbers and no judgement.
9. ACTIVITY names the source of each day's steps. A value with "~" and "strap-estimate" is an
   estimate from strap motion and is not a count. Workouts are summaries. Heart rate and calories
   are the wrong instruments for a lifting session; use the lifting log I paste for loads.
10. NOTES says what is measured, what is estimated and what the app cannot know. Keep that
    distinction in everything you say back to me.
11. Do not ask me to retype a number that is in the packet. Do ask for anything the packet says it
    cannot know when you need it.
```

### 16.2 For the coaching skill

Add this paragraph to the skill's instructions:

```
When the conversation contains a block beginning "NOOP-COACH-PACKET v", treat it as the source of
truth for the period it covers and read it by the "Reading the packet" section of the training
document. Before anything else, state in one line the range it covers and which sections are
included, switched off and not recorded. Use its numbers exactly as printed. Keep measured values,
estimates and unknowns apart, never turn a dash or a missing section into a zero, and say plainly
when a question cannot be answered from the packet. If the version is higher than the one the
training document describes, say so and continue with the sections you recognise.
```

The orchestrator cannot edit either document. The owner pastes both, and the end-to-end check of
§12.8 confirms they work.

## 17. Decisions where the roadmap left a choice

| # | Decision | Reason |
|---|---|---|
| D1 | The renderer and the day formatter live in `Packages/StrandAnalytics` | Pure text logic, tested in seconds without the shared build tree, as `CutScorecard` is |
| D2 | One formatter with a style (labels, day separator, strain factor) | The only way to give the packet the app's words and scale while the Coach text stays byte-identical |
| D3 | Byte identity is proved by a frozen copy of the old code and by recorded text | A golden alone cannot cover inputs it does not list |
| D4 | The packet lists every calendar day; the Coach keeps its row windows | "Unmeasured days are marked" needs a line per day; byte identity needs the old windows |
| D5 | Baseline is `Repository.chargeBaselines` with the Recovery screen's band | It is the baseline behind the score the owner sees |
| D6 | Steps come from `Repository.resolvedSteps` | The one function the detail and the rolling tile already share |
| D7 | The step average leaves out today | Today is partial and would drag the mean down |
| D8 | Scorecard values print as enum raw values | English and stable whatever the interface language |
| D9 | Intake and events are named in a header line and have no section | Absent, never zero, and the coach is told why |
| D10 | The privacy scan fails closed | A packet that might identify a device must not exist to be copied |
| D11 | Copy uses the previewed text and does not assemble again | The owner approves what they saw |
| D12 | The Shortcuts action returns text and does not write the pasteboard | A background pasteboard write is not dependable, and Shortcuts has its own copy action |
| D13 | The sheet is presented, not pushed | `RedesignRoute.swift` stays unedited |
| D14 | Settings are not backed up | No whitelist edit, so no drift from the Kotlin side |
| D15 | Golden files are Swift literals | The test target has no resources and `Package.swift` stays unedited |
| D16 | The size budget is a formula in the range and holds by construction | A fixed number would fail a 28-day packet or be too loose for a 7-day one |

## 18. Not determined

- **Whether the example in §7.9 equals what Swift prints, byte for byte.** It came from a scratch
  script implementing §7 with C-style formatting and halves-away-from-zero rounding. If a golden
  differs from the implementation in a rounding edge, the Test author reports it and the
  orchestrator rules, as stage 1 did for its fixture rows.
- **Whether `IntentAuthenticationPolicy.requiresAuthentication` behaves as described on the owner's
  iOS version**, and whether an intent that throws shows the localised message in Shortcuts. Read
  from the framework's interface, not run.
- **The exact names of the local-only and expiry settings in the Shortcuts "Copy to Clipboard"
  action** on the owner's iOS version.
- **Whether the system removes an expired pasteboard item while the app is suspended.** The API
  states the item expires; it was not observed. §12.8 checks it.
- **Universal Clipboard behaviour** can be checked only with a second signed-in device.
- **Which day a night's `DailyMetric` row is keyed to** between midnight and the app's 04:00 logical
  rollover (`Repository.swift:754`), and so whether today's line is empty in those hours. The packet
  prints what the row list holds.
- **Whether `DailyMetric.steps` is populated for the owner's strap.** It decides whether the in-app
  Coach's step average is a dash today (C8). Not needed by the packet.
- **The full set of `WorkoutRow.sport` strings**, including what an imported lifting session carries
  there. The packet sanitises and cuts it; the rehearsal will show the real values.
- **The effect of new public declarations on the parity ledger.** The repository-acceptance suite
  already fails on this branch for a pre-existing reason (`BASELINE.md`, `py-parity-acceptance`).
  Whether the count of failures changes was not run.
- **Whether `CoachPacketInput` can be `Sendable`**, which depends on `DailyMetric`.
- **Whether `String(format:)` and `UnitFormatter.effortDisplay` print the same strain** for every
  value under every device locale. `testPacketStrainEqualsTheEffortDisplayOnEachScale` compares them
  after normalising the decimal separator.
- **Android.** Nothing on the Kotlin side was read beyond the two files named, compiled or run.
- **The Claude-side documents.** Their current wording was not seen; §16 is written to stand alone.
