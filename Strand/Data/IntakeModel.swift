import Foundation
import StrandAnalytics

// Stage 3 (protein and intake): the values the intake surfaces draw. `IntakePresenter` builds every
// one of them; the views draw them and decide nothing (stage 3 specification §10, §11).
// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).

/// One clock for one render or publish (§9.5): the card, the ring, the freshness line and the widget
/// reading built together share it, and nothing below the screen model reads the time itself.
struct IntakeClock: Equatable {
    let now: Date
    /// `IntakeAggregation.dayKey` of `now` under the zone log.
    let today: String
    /// `now`'s minute of the day in the current zone.
    let minuteOfDay: Int
    /// §7.5: more food may still be logged for `today`.
    let dayIsOpen: Bool

    /// `cutoffMinuteOfDay` nil: the day closes only at midnight.
    static func resolve(now: Date, zoneLog: [IntakeZoneSegment], timeZone: TimeZone,
                        cutoffMinuteOfDay: Int?) -> IntakeClock {
        let today = IntakeAggregation.dayKey(epochSeconds: Int(now.timeIntervalSince1970.rounded(.down)),
                                             zoneLog: zoneLog)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return IntakeClock(now: now, today: today, minuteOfDay: minute,
                           dayIsOpen: cutoffMinuteOfDay.map { minute < $0 } ?? true)
    }

    /// The app's clock now: the stored zone log with the phone's zone appended for the read (the
    /// log itself is stored only by the funnels), and the owner's cutoff.
    static func current(settings: IntakeSettings, now: Date = Date(), timeZone: TimeZone = .current) -> IntakeClock {
        let log = IntakeAggregation.appending(zoneIdentifier: timeZone.identifier,
                                              at: Int(now.timeIntervalSince1970), to: settings.zoneLog)
        return resolve(now: now, zoneLog: log, timeZone: timeZone, cutoffMinuteOfDay: settings.dayClosingMinute)
    }
}

/// Everything one render needs, gathered once (§9.5).
struct IntakePresenterInput: Equatable {
    var source: IntakeSourceSetting
    /// `IntakeSettings.hasChosenSource`.
    var sourceChosen: Bool = true
    /// The calendar day shown.
    var day: String
    /// The provider's day; nil: nothing stored.
    var resolved: ResolvedIntakeDay? = nil
    /// The provider's series.
    var history: [ResolvedIntakeDay] = []
    /// `IntakeSettings.proteinFloorGrams`.
    var floorGrams: Double? = nil
    /// `IntakeSettings.targets(on: day)`.
    var targets: IntakeTargets = IntakeTargets()
    var targetsNeedAttention: Bool = false
    var lastHealthOutcome: IntakeHealthSync.Outcome? = nil
    var lastHealthAttemptAt: Date? = nil
    /// The Health apps that wrote on `day`.
    var healthAppNamesOnDay: [String] = []
    /// The app named in "From %@" and "Edit this in %@".
    var foodAppName: String? = nil
    /// Path B: the day's entries.
    var entries: [IntakeEntry] = []
    /// Path B: a total restored without its entry list (§9.3).
    var restoredTotal: IntakeStoredDay? = nil
    var isLoading: Bool = false

    init(source: IntakeSourceSetting, day: String) {
        self.source = source
        self.day = day
    }

    /// The one place a render's input is gathered from the provider and the settings. Reads only.
    @MainActor
    static func gather(provider: IntakeProvider, settings: IntakeSettings, day: String) -> IntakePresenterInput {
        var input = IntakePresenterInput(source: settings.source, day: day)
        input.sourceChosen = settings.hasChosenSource
        input.resolved = provider.day(day)
        input.history = provider.series()
        input.floorGrams = settings.proteinFloorGrams
        input.targets = settings.targets(on: day)
        input.targetsNeedAttention = settings.targetsNeedAttention
        input.lastHealthOutcome = provider.lastHealthOutcome
        input.lastHealthAttemptAt = provider.lastHealthAttemptAt
        let known = settings.knownHealthSources
        input.healthAppNamesOnDay = known.values.filter { $0.lastSeenDay == day }.map(\.name).sorted()
        input.foodAppName = known.values.max { ($0.lastSeenDay, $0.name) < ($1.lastSeenDay, $1.name) }?.name
        return input
    }

    /// As `gather(provider:settings:day:)`, with the quick-add entries and a restored total of
    /// `entriesDay` (default `day`): the screen's entries card may list one of the seven days
    /// before today while the ring and totals stay on `day`.
    @MainActor
    static func gather(provider: IntakeProvider, settings: IntakeSettings, day: String,
                       quickAdd: IntakeQuickAddStore, entriesDay: String? = nil) async -> IntakePresenterInput {
        var input = gather(provider: provider, settings: settings, day: day)
        let listed = entriesDay ?? day
        input.entries = quickAdd.entries(day: listed)
        input.restoredTotal = await quickAdd.restoredTotal(day: listed)
        return input
    }
}

/// The protein card in Your cards (§10.1).
struct IntakeCard: Equatable {
    enum Status: Equatable {
        case loading, noSource, noFloor, notMeasured, below, atFloor, above, stale, readFailed, pastDay,
             pastDayNotMeasured, targetsNeedAttention
    }

    var status: Status
    /// Whole grams; nil draws the dash, never "0" for not measured.
    var value: String?
    /// "g" with a value.
    var unit: String?
    /// Nil only while loading.
    var caption: String?
    /// Nil: no ring; 0 is the empty ring; never above 1.
    var ring: Double?
    /// The printed floor (stage 1 ruling R45).
    var floorGrams: Int?
    /// The tertiary colour: a stale figure.
    var isDimmed: Bool
    var opensIntake: Bool
}

/// The intake screen (§10.2).
struct IntakeScreenModel: Equatable {
    enum Layout: Equatable { case loading, setup, supplementsOnly, full }

    struct Protein: Equatable {
        var value: String?
        var floorGrams: Int?
        var line: String
        var ring: Double?
        var showsSetFloorRow: Bool
    }

    struct Energy: Equatable {
        var title: String
        var state: IntakeEnergyState
        var value: String?
        var line: String?
    }

    struct ChartPoint: Equatable {
        let day: String
        /// Nil: not measured, a gap in the curve and never zero.
        let grams: Double?
        /// Nil when there is no floor or no figure.
        let meetsFloor: Bool?
    }

    struct Chart: Equatable {
        /// 28 days ending on the shown day, oldest first.
        var points: [ChartPoint]
        var message: String?
    }

    var layout: Layout
    /// The three sentences of §11 "Setup", in order: Apple Health, Enter here, None.
    var setupChoices: [String] = []
    var protein: Protein? = nil
    var energy: Energy? = nil
    var chart: Chart? = nil
    var sourceLine: String? = nil
    var freshness: String? = nil
    var freshnessIsStale: Bool = false
    var showsReadAgain: Bool = false
    var twoApps: String? = nil
    var showsChooseOne: Bool = false
    var problem: String? = nil
    var correction: String? = nil
    var showsDataSourcesRow: Bool = false
    var attention: String? = nil
    var entries: [IntakeEntry] = []
    var showsRestoredTotal: Bool = false
    var showsCutoffRow: Bool = false
}

/// The source of a figure the widget may show. The app target's copy of
/// `PersonalIntakeReading.Source`, which lives in a file the macOS target does not compile.
enum IntakeWidgetSource: String, Equatable {
    case appleHealth, quickAdd
}

/// What the widget may show for a day (§10.8). Never carries calories, labels or names.
struct IntakeWidgetValues: Equatable {
    let day: String
    let proteinGrams: Int?
    let floorGrams: Int?
    let remainingGrams: Int?
    let source: IntakeWidgetSource?
    let readAt: Date?
}

/// One quick-add amount field (§10.3).
enum IntakeAmountEntry: Equatable {
    case empty
    case amount(Double)
    case invalid(message: String)
}

/// The protein floor field (§9.2.1, §10.5).
enum IntakeFloorEntry: Equatable {
    case noFloor
    case grams(Double)
    case invalid(message: String)
}

/// The calorie range and hard floor fields (§10.5).
enum IntakeRangeEntry: Equatable {
    case valid(IntakeTargets)
    case invalid
}

/// The rows of the Intake card in Settings, top to bottom (§10.5).
enum IntakeSettingsRow: Equatable {
    case featureSwitch, source, proteinFloor, calorieRange, hardFloor, appsToCount, supplements, addSupplement,
         cutoffTime, cutoffReminder
}

/// One supplement on the intake screen (§10.6).
struct IntakeSupplementRow: Equatable {
    let question: String
    let name: String
    let isTicked: Bool
    let caption: String?
}
