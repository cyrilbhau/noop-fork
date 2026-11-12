import Foundation
import WhoopStore

// The coach packet (stage 2 specification §6.2 and §7): one bounded plain-text block that carries the
// owner's recent numbers to a coach outside the app. This file is the renderer and its input types.
// What goes into the input is decided by the app-side assembler; nothing here reads a store.
//
// Pure: no store, no clock, no calendar, time-zone, date or locale object. Every function is
// total. Day keys are validated and stepped through `CanonicalDay.` and nowhere else. The per-day
// line and its averages are `CoachDayFormat`'s, the formatter the in-app Coach context uses.
//
// No Kotlin twin: the owner has skipped Android for the personal fork (stage 1 ruling R43).

// MARK: - Input types

/// A section of the packet. The raw value is the id printed in the header. The declaration order
/// is the fixed order of the packet (version 2, §7.12).
public enum CoachPacketSection: String, CaseIterable, Equatable, Sendable {
    case scorecard
    case weighIns = "weigh-ins"
    case intake
    case recoverySleep = "recovery-sleep"
    case trends
    case activity
    case events

    /// Whether the section is on when the owner has never chosen. True for all seven.
    public var isOnByDefault: Bool { true }

    /// The heading line of the section (§7.12 G-1).
    var heading: String {
        switch self {
        case .scorecard: return "== SCORECARD =="
        case .weighIns: return "== WEIGH-INS =="
        case .intake: return "== INTAKE =="
        case .recoverySleep: return "== RECOVERY AND SLEEP =="
        case .trends: return "== TRENDS =="
        case .activity: return "== ACTIVITY =="
        case .events: return "== EVENTS =="
        }
    }
}

public enum CoachPacketBodyKind: String, Equatable, Sendable { case weight, waist }

/// Where a current body value came from. A closed set: no stored source id is ever printed.
public enum CoachPacketBodySource: String, Equatable, Sendable {
    case labBook = "lab-book", appleHealth = "apple-health", profile
}

/// A current weight (kg) or waist (cm).
public struct CoachPacketBodyReading: Equatable, Sendable {
    public let kind: CoachPacketBodyKind
    /// kg or cm.
    public let value: Double
    public let source: CoachPacketBodySource
    /// nil for the undated profile value.
    public let day: String?

    public init(kind: CoachPacketBodyKind, value: Double, source: CoachPacketBodySource, day: String?) {
        self.kind = kind
        self.value = value
        self.source = source
        self.day = day
    }
}

/// The active phase as the packet words it.
public struct CoachPacketPhase: Equatable, Sendable {
    public let name: String
    public let startDay: String
    public let targetWeightKg: Double?
    public let rateLowPercentPerWeek: Double
    public let rateHighPercentPerWeek: Double

    public init(name: String, startDay: String, targetWeightKg: Double?, rateLowPercentPerWeek: Double,
                rateHighPercentPerWeek: Double) {
        self.name = name
        self.startDay = startDay
        self.targetWeightKg = targetWeightKg
        self.rateLowPercentPerWeek = rateLowPercentPerWeek
        self.rateHighPercentPerWeek = rateHighPercentPerWeek
    }
}

public enum CoachPacketScorecard: Equatable, Sendable {
    /// The scorecard feature is switched off in the app.
    case switchedOff
    case evaluated(phase: CoachPacketPhase?, result: CutScorecardResult)
}

/// A personal baseline behind the recovery score, with the band the Recovery detail screen draws.
public struct CoachPacketBaseline: Equatable, Sendable {
    public let center: Double
    /// `ChargeTypicalBand.range`; nil: the baseline is not usable.
    public let typical: ClosedRange<Double>?
    /// `BaselineStatus.rawValue`.
    public let status: String
    /// `BaselineState.nValid`.
    public let nights: Int

    public init(center: Double, typical: ClosedRange<Double>?, status: String, nights: Int) {
        self.center = center
        self.typical = typical
        self.status = status
        self.nights = nights
    }
}

public enum CoachPacketStepSource: String, Equatable, Sendable {
    case strap, appleHealth = "apple-health", strapEstimate = "strap-estimate"
}

public struct CoachPacketStepDay: Equatable, Sendable {
    public let day: String
    public let steps: Double
    public let source: CoachPacketStepSource

    public init(day: String, steps: Double, source: CoachPacketStepSource) {
        self.day = day
        self.steps = steps
        self.source = source
    }
}

public enum CoachPacketWorkoutSource: String, Equatable, Sendable {
    case whoop, appleHealth = "apple-health", detected, manual,
         liftLog = "lift-log", activityFile = "activity-file"
}

/// A workout summary. Its strain score is not carried and not printed.
public struct CoachPacketWorkout: Equatable, Sendable {
    /// The local day of the start.
    public let day: String
    /// 0…1439, local.
    public let startMinuteOfDay: Int
    public let sport: String
    public let source: CoachPacketWorkoutSource
    public let durationMinutes: Double?
    public let avgHr: Int?
    public let energyKcal: Double?
    public let distanceKm: Double?

    public init(day: String, startMinuteOfDay: Int, sport: String, source: CoachPacketWorkoutSource,
                durationMinutes: Double?, avgHr: Int?, energyKcal: Double?, distanceKm: Double?) {
        self.day = day
        self.startMinuteOfDay = startMinuteOfDay
        self.sport = sport
        self.source = source
        self.durationMinutes = durationMinutes
        self.avgHr = avgHr
        self.energyKcal = energyKcal
        self.distanceKm = distanceKm
    }
}

/// The events section's input: stage 5's rows, or the feature switched off in the app.
public enum CoachPacketEvents: Equatable, Sendable {
    /// The events feature is off in the app.
    case switchedOff
    /// Exactly what `PersonalEvents.packetLines` returned.
    case rows([String])
}

/// Where one day's intake came from. A closed set: no stored source id is ever printed. `mixed`:
/// the day's protein and energy came from two different sources.
public enum CoachPacketIntakeSource: String, Equatable, Sendable {
    case appleHealth = "apple-health", quickAdd = "quick-add", nutritionFile = "nutrition-file", mixed
}

/// One day's logged protein and energy.
public struct CoachPacketIntakeDay: Equatable, Sendable {
    public let day: String
    public let proteinGrams: Double?
    public let energyKcal: Double?
    public let source: CoachPacketIntakeSource?

    public init(day: String, proteinGrams: Double?, energyKcal: Double?, source: CoachPacketIntakeSource?) {
        self.day = day
        self.proteinGrams = proteinGrams
        self.energyKcal = energyKcal
        self.source = source
    }
}

/// The intake section's input: the resolved days, or the feature switched off in the app.
public enum CoachPacketIntake: Equatable, Sendable {
    /// The intake feature is off in the app.
    case switchedOff
    case days([CoachPacketIntakeDay])
}

/// Everything one packet is rendered from.
public struct CoachPacketInput: Equatable {
    // SPEC-NOTE: §6.2 lists this type as `Sendable` and allows dropping it when `DailyMetric` cannot
    // be marked `Sendable` from this package. `DailyMetric` (WhoopStore) declares no `Sendable`, so it
    // is dropped here; nothing depends on it.

    /// Local time with its UTC offset, as text: "2031-03-16T07:42:10+01:00".
    public let generatedAt: String
    public let rangeStartDay: String
    /// Today.
    public let rangeEndDay: String
    public let sections: Set<CoachPacketSection>
    public let days: [DailyMetric]
    /// 1.0 or 0.21.
    public let strainFactor: Double
    public let scorecard: CoachPacketScorecard
    public let body: [CoachPacketBodyReading]
    public let hrvBaseline: CoachPacketBaseline?
    public let restingHrBaseline: CoachPacketBaseline?
    public let steps: [CoachPacketStepDay]
    public let workouts: [CoachPacketWorkout]
    public let intake: CoachPacketIntake
    public let events: CoachPacketEvents

    public init(generatedAt: String, rangeStartDay: String, rangeEndDay: String,
                sections: Set<CoachPacketSection>, days: [DailyMetric], strainFactor: Double,
                scorecard: CoachPacketScorecard, body: [CoachPacketBodyReading],
                hrvBaseline: CoachPacketBaseline?, restingHrBaseline: CoachPacketBaseline?,
                steps: [CoachPacketStepDay], workouts: [CoachPacketWorkout],
                intake: CoachPacketIntake, events: CoachPacketEvents) {
        self.generatedAt = generatedAt
        self.rangeStartDay = rangeStartDay
        self.rangeEndDay = rangeEndDay
        self.sections = sections
        self.days = days
        self.strainFactor = strainFactor
        self.scorecard = scorecard
        self.body = body
        self.hrvBaseline = hrvBaseline
        self.restingHrBaseline = restingHrBaseline
        self.steps = steps
        self.workouts = workouts
        self.intake = intake
        self.events = events
    }
}

// MARK: - Renderer

/// The packet renderer, its limits, and the privacy scan that decides whether a text may leave.
public enum CoachPacket {
    public static let formatName = "NOOP-COACH-PACKET"
    public static let formatVersion = 2
    /// The most weekly weigh-in rows printed.
    public static let weeklyRowLimit = 8
    /// The most workout rows printed.
    public static let workoutRowLimit = 20
    /// The most UTF-8 bytes of one free-text field.
    public static let freeTextByteLimit = 48

    /// The fixed part of the size budget, in UTF-8 bytes.
    static let budgetBaseBytes = 8000
    /// The per-day part of the size budget, in UTF-8 bytes: version 1's 220 and an intake row of
    /// five-digit amounts, 70 with its line break. Like a step count, a larger amount is printed in
    /// full rather than dropped (ruling A25); a packet it widens past the budget is reported as over
    /// budget, never shortened by turning a value into absence.
    static let budgetBytesPerDay = 290
    /// The longest events row printed, in UTF-8 bytes: stage 5's widest row with its line break.
    static let eventRowByteLimit = 141
    /// The trailing window of the trends section's second mean, in calendar days.
    static let recentWindowDays = 7
    /// The shortest identifier the privacy scan searches for, in characters.
    static let identifierMinimumLength = 4
    /// A heart rate outside this range is not a measurement.
    static let heartRateRange = 1...300
    /// The minutes of a local day.
    static let minuteOfDayRange = 0...1439
    /// What `sanitize` returns for text with nothing left in it.
    static let unnamed = "unnamed"

    private static let dash = CoachDayFormat.notMeasured

    /// The packet text. Ends with exactly one "\n".
    public static func render(_ input: CoachPacketInput) -> String {
        let keys = dayKeys(from: input.rangeStartDay, to: input.rangeEndDay)
        var blocks: [[String]] = [header(input, keys: keys)]
        if let first = CanonicalDay.number(input.rangeStartDay), !keys.isEmpty {
            let range = PacketRange(firstNumber: first, keys: keys)
            for section in CoachPacketSection.allCases where input.sections.contains(section) {
                blocks.append([section.heading] + body(of: section, input: input, range: range))
            }
        }
        blocks.append(notes)
        return blocks.map { $0.joined(separator: "\n") }.joined(separator: "\n\n") + "\n"
    }

    /// The size the packet must stay under, in UTF-8 bytes:
    /// 8000 + 290 × rangeDays + `PersonalEvents.packetByteAllowance` (version 2, ruling A5).
    public static func byteBudget(rangeDays: Int) -> Int {
        // SPEC-NOTE: §7.12 gives the formula for a range of 7, 14 or 28 days. A negative count is
        // read as zero days and an overflowing product saturates, so the function is total.
        let (perDay, overflowed) = budgetBytesPerDay.multipliedReportingOverflow(by: max(0, rangeDays))
        guard !overflowed else { return Int.max }
        let (total, overflowedSum) = budgetBaseBytes.addingReportingOverflow(perDay)
        guard !overflowedSum else { return Int.max }
        let (withEvents, overflowedEvents) = total.addingReportingOverflow(PersonalEvents.packetByteAllowance)
        return overflowedEvents ? Int.max : withEvents
    }

    /// Every calendar day from `start` to `end` inclusive, ascending; empty when either key is
    /// invalid or `end` is before `start`. A key is valid exactly when `CanonicalDay.number` is
    /// not nil (stage 1 ruling R5); the keys come from `CanonicalDay.key`.
    public static func dayKeys(from start: String, to end: String) -> [String] {
        guard let first = CanonicalDay.number(start), let last = CanonicalDay.number(end),
              first <= last else { return [] }
        return (first...last).map { CanonicalDay.key($0) }
    }

    /// One line of free text: control characters and line breaks become spaces, runs of spaces
    /// collapse, the ends are trimmed, `"` becomes `'`, and the result is cut at a character
    /// boundary to at most `freeTextByteLimit` UTF-8 bytes. Empty input gives "unnamed".
    public static func sanitize(_ text: String) -> String {
        var cut = ""
        var bytes = 0
        for character in normalizedFreeText(text) {
            let width = character.utf8.count
            guard bytes + width <= freeTextByteLimit else { break }
            cut.append(character)
            bytes += width
        }
        // SPEC-NOTE: the cut can land just after a space. That space is dropped, so "the ends are
        // trimmed" still holds for the text that is printed.
        while cut.hasSuffix(" ") { cut.removeLast() }
        // SPEC-NOTE: "Empty input gives unnamed" is read as "text that is empty once cleaned", so no
        // line ever carries an empty name.
        return cut.isEmpty ? unnamed : cut
    }

    /// `sanitize` without the cut and without the "unnamed" fallback: control characters and every
    /// white space become one space between words, the ends are trimmed and `"` becomes `'`. The
    /// privacy scan searches for an identifier in this form too, which is how a name is printed.
    static func normalizedFreeText(_ text: String) -> String {
        var cleaned = String.UnicodeScalarView()
        var spacePending = false
        for scalar in text.unicodeScalars {
            // SPEC-NOTE: §6.2 names control characters and line breaks. Every other Unicode white
            // space (a no-break space, U+3000) is read as a space as well, so "runs of spaces
            // collapse" holds for all of them and no line ends in an invisible one.
            if scalar.properties.generalCategory == .control || scalar.properties.isWhitespace {
                spacePending = true
                continue
            }
            if spacePending, !cleaned.isEmpty { cleaned.append(" ") }
            spacePending = false
            cleaned.append(scalar == "\"" ? "'" : scalar)
        }
        return String(cleaned)
    }

    /// Every owner-typed or imported string the renderer passes through `sanitize`, as given, for
    /// the sections that are on: the phase name when the scorecard section is on and evaluated with
    /// a phase, then every workout's sport in input order when the activity section is on. A text
    /// whose section is off does not leave, so it is not scanned. A later section that prints free
    /// text adds its fields here (ruling A20).
    public static func freeText(of input: CoachPacketInput) -> [String] {
        var texts: [String] = []
        if input.sections.contains(.scorecard), case let .evaluated(phase?, _) = input.scorecard {
            texts.append(phase.name)
        }
        if input.sections.contains(.activity) { texts += input.workouts.map(\.sport) }
        return texts
    }

    /// What the assembler's scan finds (ruling A20): the rendered text and, each on its own, every
    /// string of `freeText(of:)` and of `freeText` before it is sanitised and cut. `freeText` is what
    /// the assembler gathered beside the input: the raw labels and notes behind the events rows,
    /// which the input carries only as rows already cut. A workout the row limit leaves out can
    /// therefore block the packet, which is the fail-closed direction. `identifiers` nil means the
    /// list of known identifiers could not be read; that is a finding, never an empty list. A
    /// description found more than once is listed once.
    public static func scan(_ input: CoachPacketInput, rendered text: String, identifiers: [String]?,
                            freeText extra: [String] = []) -> [String] {
        guard let identifiers else { return [unreadableIdentifiersFinding] }
        var findings: [String] = []
        for source in [text] + freeText(of: input) + extra {
            for finding in privacyViolations(in: source, identifiers: identifiers) where !findings.contains(finding) {
                findings.append(finding)
            }
        }
        return findings
    }

    /// The finding for an identifier list that could not be read.
    static let unreadableIdentifiersFinding = "known identifiers could not be read"

    /// What must not leave the phone, found in `text` (§7.11). Empty means the text may leave.
    ///
    /// One description per kind of finding and per identifier found. A description names the kind
    /// and never repeats the text that was found.
    public static func privacyViolations(in text: String, identifiers: [String]) -> [String] {
        var findings: [String] = []
        let lowered = text.lowercased()
        var searched = Set<String>()
        for (index, identifier) in identifiers.enumerated() {
            // As given, and in the form `sanitize` prints it (ruling A20): a doubled space, a line
            // break, an end space or a `"` in the identifier is printed differently.
            var found = false
            for form in [identifier, normalizedFreeText(identifier)] where form.count >= identifierMinimumLength {
                let needle = form.lowercased()
                if searched.insert(needle).inserted, lowered.contains(needle) { found = true }
            }
            if found { findings.append("known identifier (entry \(index + 1) of the list)") }
        }
        // Raw storage namespaces and paths, compared as written.
        for literal in rawNamespaceLiterals where text.contains(literal) {
            findings.append("raw storage namespace \"\(literal)\"")
        }
        for literal in pathLiterals where text.contains(literal) {
            findings.append("file path \"\(literal)\"")
        }
        let bytes = Array(text.utf8)
        if containsUUID(bytes) { findings.append("UUID") }
        if containsMACAddress(bytes) { findings.append("MAC address") }
        if containsEmailAddress(text) { findings.append("email address") }
        return findings
    }

    /// The raw storage namespaces of §7.11. The packet prints its own source tokens instead.
    static let rawNamespaceLiterals = ["my-whoop", "-noop"]
    /// The path fragments of §7.11.
    static let pathLiterals = ["/Users/", "/var/", "/private/", "file://", "~/"]

    // MARK: - Privacy patterns

    private static func isHex(_ byte: UInt8) -> Bool {
        (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x46) || (byte >= 0x61 && byte <= 0x66)
    }

    /// The group lengths of a UUID's text form.
    private static let uuidGroups = [8, 4, 4, 4, 12]

    /// True when `bytes` holds `8-4-4-4-12` hexadecimal digits anywhere.
    private static func containsUUID(_ bytes: [UInt8]) -> Bool {
        let length = uuidGroups.reduce(0, +) + uuidGroups.count - 1
        guard bytes.count >= length else { return false }
        for start in 0...(bytes.count - length) {
            var position = start
            var matched = true
            for (index, group) in uuidGroups.enumerated() where matched {
                if index > 0 {
                    matched = bytes[position] == 0x2D
                    position += 1
                }
                for offset in 0..<group where matched {
                    matched = isHex(bytes[position + offset])
                }
                position += group
            }
            if matched { return true }
        }
        return false
    }

    /// The number of hexadecimal pairs in a MAC address.
    private static let macPairs = 6

    /// True when `bytes` holds six hexadecimal pairs separated by colons or dashes in any mixture
    /// (ruling A17).
    private static func containsMACAddress(_ bytes: [UInt8]) -> Bool {
        let length = macPairs * 3 - 1
        guard bytes.count >= length else { return false }
        for start in 0...(bytes.count - length) {
            var matched = true
            for pair in 0..<macPairs where matched {
                let at = start + pair * 3
                matched = isHex(bytes[at]) && isHex(bytes[at + 1])
                    && (pair == macPairs - 1 || bytes[at + 2] == 0x3A || bytes[at + 2] == 0x2D)
            }
            if matched { return true }
        }
        return false
    }

    /// True when a run of non-white-space in `text` has the shape `\S+@\S+\.\S+`.
    private static func containsEmailAddress(_ text: String) -> Bool {
        var run: [Unicode.Scalar] = []
        func isAddress(_ run: [Unicode.Scalar]) -> Bool {
            // Something before the "@", something between it and a later ".", something after.
            guard run.count >= 5 else { return false }
            for at in 1..<(run.count - 3) where run[at] == "@" {
                for dot in (at + 2)..<(run.count - 1) where run[dot] == "." { return true }
            }
            return false
        }
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                if isAddress(run) { return true }
                run.removeAll(keepingCapacity: true)
            } else {
                run.append(scalar)
            }
        }
        return isAddress(run)
    }

    // MARK: - Numbers (§7.1)

    /// `value` when it is a finite number within the formatter's limit, else nil.
    private static func number(_ value: Double?) -> Double? {
        // SPEC-NOTE: §6.2 says a non-finite number is absent. The magnitude limit of `CoachDayFormat`
        // rule F1 is applied to every number of the packet as well, so that `Int(_:)` cannot trap on
        // a finite but absurd value (1e300) and no line grows without bound.
        CoachDayFormat.measured(value)
    }

    /// A weight, a waist or a baseline centre: a number that is also above zero.
    private static func positive(_ value: Double?) -> Double? {
        number(value).flatMap { $0 > 0 ? $0 : nil }
    }

    /// A count, a duration, an energy or a distance: a number that is not below zero.
    private static func nonNegative(_ value: Double?) -> Double? {
        number(value).flatMap { $0 >= 0 ? $0 : nil }
    }

    /// `value` to `decimals` places with a point, and a negative zero printed as its positive form.
    private static func fixed(_ value: Double, _ decimals: Int) -> String {
        let text = String(format: "%.\(decimals)f", value)
        guard text.hasPrefix("-"), !text.contains(where: { $0 != "-" && $0 != "0" && $0 != "." })
        else { return text }
        return String(text.dropFirst())
    }

    /// `fixed` with an explicit sign: "+0.4", "-1.5", "+0.0".
    private static func signed(_ value: Double, _ decimals: Int) -> String {
        let text = fixed(value, decimals)
        return text.hasPrefix("-") ? text : "+" + text
    }

    /// A whole number with an explicit sign: "+2", "-1", "+0".
    private static func signed(_ value: Int) -> String {
        value < 0 ? "\(value)" : "+\(value)"
    }

    /// A number to the nearest whole, halves away from zero. `value` has passed `number`.
    private static func rounded(_ value: Double) -> Int {
        Int(value.rounded())
    }

    /// A day key from another type, printed only when it is canonical.
    private static func dayText(_ key: String?) -> String {
        // SPEC-NOTE: §7 prints the scorecard's day keys as given. A key that `CanonicalDay` rejects
        // is printed as the dash instead, so no text of unknown shape reaches a line of the packet.
        guard let key, CanonicalDay.number(key) != nil else { return dash }
        return key
    }

    private static func joined(_ rules: [CutScorecardRule]) -> String {
        rules.isEmpty ? "none" : rules.map(\.rawValue).joined(separator: ", ")
    }

    // MARK: - Range

    /// The calendar days of a valid range.
    private struct PacketRange {
        let firstNumber: Int
        let keys: [String]

        var lastNumber: Int { firstNumber + keys.count - 1 }

        /// The day number of `key` when it is canonical and inside the range.
        func number(of key: String) -> Int? {
            guard let number = CanonicalDay.number(key), number >= firstNumber, number <= lastNumber
            else { return nil }
            return number
        }
    }

    /// The daily rows of the range by day number. Two rows for one day: the last in the array wins.
    private static func rowsByDay(_ input: CoachPacketInput, _ range: PacketRange) -> [Int: DailyMetric] {
        var rows: [Int: DailyMetric] = [:]
        for row in input.days {
            if let number = range.number(of: row.day) { rows[number] = row }
        }
        return rows
    }

    // MARK: - Header and notes (§7.2, §7.8)

    private static func header(_ input: CoachPacketInput, keys: [String]) -> [String] {
        let on = CoachPacketSection.allCases.filter { input.sections.contains($0) }.map(\.rawValue)
        let off = CoachPacketSection.allCases.filter { !input.sections.contains($0) }.map(\.rawValue)
        let rangeLine: String
        let included: [String]
        if keys.isEmpty {
            // SPEC-NOTE: §6.2 gives "the header with `range: invalid`, no sections" and does not say
            // what the two section lines read. `sections:` says "none", because none is printed;
            // `switched-off:` still lists only what the owner switched off, because the range, not
            // the owner, left the others out.
            rangeLine = "range: invalid"
            included = []
        } else {
            rangeLine = "range: \(input.rangeStartDay)..\(input.rangeEndDay) "
                + "(\(keys.count) days; the last day is today and is partial)"
            included = on
        }
        // SPEC-NOTE: §7.2 prints `generatedAt` as given. It is passed through `sanitize` (one line,
        // 48 bytes; a timestamp with its offset is 25) so that a malformed value cannot add a line.
        let generated = input.generatedAt.isEmpty ? dash : sanitize(input.generatedAt)
        return [
            "\(formatName) v\(formatVersion)",
            "generated: \(generated)",
            rangeLine,
            "sections: " + (included.isEmpty ? "none" : included.joined(separator: ", ")),
            "switched-off: " + (off.isEmpty ? "none" : off.joined(separator: ", ")),
            // Version 2: both sections exist, so the app names nothing it does not hold.
            "not-recorded-by-app: none",
            "units: kg, cm, g, hours (h), ms, bpm, steps, kcal, km; dates are YYYY-MM-DD in the phone's time zone",
            "missing: \"\(dash)\" means NOT MEASURED, never zero",
        ]
    }

    private static var notes: [String] {
        [
            "== NOTES ==",
            "measured: weight and waist as entered, heart rate, HRV and resting heart rate from the strap, steps marked apple-health or strap.",
            "estimated by the app: recovery and strain scores (not WHOOP's scores), sleep duration and stages, steps marked strap-estimate, workout calories, the projection date.",
            "logged by the owner: intake (protein and energy) and events; a day with no intake value was not logged, which is not zero.",
            "the app cannot know: food intake the owner did not log, lifting loads beyond imported sessions, anything on a day the strap was not worn, how the owner feels.",
            "the verdict is the owner's own rule applied to the owner's own numbers; the app changed nothing and makes no medical claim.",
            "end of \(formatName) v\(formatVersion)",
        ]
    }

    private static func body(of section: CoachPacketSection, input: CoachPacketInput,
                             range: PacketRange) -> [String] {
        switch section {
        case .scorecard: return scorecardLines(input.scorecard)
        case .weighIns: return weighInLines(input)
        case .intake: return intakeLines(input.intake, range)
        case .recoverySleep: return recoverySleepLines(input, range)
        case .trends: return trendLines(input, range)
        case .activity: return stepLines(input, range) + workoutLines(input, range)
        case .events: return eventLines(input.events)
        }
    }

    // MARK: - Scorecard (§7.3)

    private static func scorecardLines(_ scorecard: CoachPacketScorecard) -> [String] {
        guard case let .evaluated(phase, result) = scorecard else {
            return ["not available: the scorecard is switched off in the app"]
        }
        if let invalid = result.invalidInput {
            return ["not available: the stored rules need attention (\(invalid.rawValue))"]
        }
        var lines = [phaseLine(phase, verdict: result.verdict),
                     "judged-week: " + (result.judgedWeekStart.map { dayText($0) } ?? "none"),
                     verdictLine(result.verdict)]
        for rule in result.rules {
            let reason = rule.unknownReason.map { " (\($0.rawValue))" } ?? ""
            lines.append("rule \(rule.rule.rawValue): \(rule.state.rawValue)\(reason), "
                + "\(rule.consecutiveWeeks) of \(rule.requiredWeeks) weeks")
        }
        lines.append(waistLine(result.signals.waist))
        lines.append(liftLine(result.signals.lifts))
        lines.append(proteinLine(result.signals.protein))
        lines.append(rateBandLine(result.signals.rateBand))
        lines.append(rateLine(result))
        lines.append(projectionLine(result.projection))
        if let rejections = rejectionLine(result.rejections) { lines.append(rejections) }
        return lines
    }

    private static func phaseLine(_ phase: CoachPacketPhase?, verdict: CutScorecardVerdict) -> String {
        guard let phase else { return "phase: none active" }
        let verb = verdict.reason == .phaseNotStarted ? "starts" : "started"
        let target: String
        if let kilograms = phase.targetWeightKg {
            // SPEC-NOTE: a target that is set but is not a positive finite number prints "target —
            // kg". "no target" is kept for the phase that has none.
            target = "target \(positive(kilograms).map { fixed($0, 1) } ?? dash) kg"
        } else {
            target = "no target"
        }
        return "phase: \"\(sanitize(phase.name))\" (cut), \(verb) \(dayText(phase.startDay)), \(target), "
            + "band \(percent(phase.rateLowPercentPerWeek)) to \(percent(phase.rateHighPercentPerWeek)) %/week"
    }

    /// A percentage per week to two decimals, or the dash.
    private static func percent(_ value: Double?) -> String {
        number(value).map { fixed($0, 2) } ?? dash
    }

    private static func verdictLine(_ verdict: CutScorecardVerdict) -> String {
        "verdict: \(verdict.kind.rawValue); reason \(verdict.reason.rawValue)"
            + "; rule \(verdict.rule?.rawValue ?? "none")"
            + "; calorie-change " + (verdict.calorieChangeKcal.map { "\(signed($0)) kcal" } ?? "none")
            + "; overridden \(joined(verdict.overriddenRules))"
            + "; could-not-check \(joined(verdict.unevaluatedRules))"
    }

    private static func waistLine(_ signal: CutScorecardWaistSignal) -> String {
        var line = "signal waist: \(signal.state.rawValue) (\(signal.reason.rawValue))"
        if let current = positive(signal.currentCm) { line += "; now \(fixed(current, 1)) cm" }
        if let reference = positive(signal.referenceCm), let week = signal.referenceWeekStart {
            line += "; reference \(fixed(reference, 1)) cm in week \(dayText(week))"
        }
        if let change = number(signal.changeCm) { line += "; change \(signed(change, 1)) cm" }
        return line
    }

    private static func liftLine(_ signal: CutScorecardLiftSignal) -> String {
        var line = "signal lifts: \(signal.state.rawValue) (\(signal.reason.rawValue))"
        if signal.commonExercises > 0 {
            line += "; \(signal.commonExercises) exercises in common: \(signal.dropped) dropped, "
                + "\(signal.climbed) climbed, \(signal.held) held"
        }
        if let start = signal.windowStartDay, let end = signal.windowEndDay {
            line += "; days \(dayText(start))..\(dayText(end))"
        }
        return line
    }

    private static func proteinLine(_ signal: CutScorecardProteinSignal) -> String {
        let floor: String
        if let grams = signal.floorGrams {
            // SPEC-NOTE: a floor that is set but is not a positive finite number prints "floor — g".
            // "floor not set" is kept for the signal that carries no floor.
            floor = "floor \(positive(grams).map { "\(rounded($0))" } ?? dash) g"
        } else {
            floor = "floor not set"
        }
        return "signal protein: \(signal.state.rawValue) (\(signal.reason.rawValue))"
            + "; \(signal.daysAtOrAboveFloor) of \(signal.requiredDays) days at or above floor"
            + "; \(signal.daysLogged) days logged; \(floor)"
    }

    private static func rateBandLine(_ signal: CutScorecardRateBandSignal) -> String {
        var line = "signal rate-band: \(signal.state.rawValue) (\(signal.reason.rawValue))"
        if let rate = number(signal.percentPerWeek) { line += "; \(fixed(rate, 2)) %/week" }
        if let low = number(signal.lowPercentPerWeek), let high = number(signal.highPercentPerWeek) {
            line += "; band \(fixed(low, 2)) to \(fixed(high, 2)) %/week"
        }
        return line
    }

    private static func rateLine(_ result: CutScorecardResult) -> String {
        // SPEC-NOTE: a fitted rate whose loss is not a finite number is worded as no rate, with the
        // result's own reason when it carries one and the dash otherwise.
        guard let rate = result.rate, let loss = number(rate.lossKgPerWeek) else {
            return "rate: not available (\(result.rateUnavailable?.rawValue ?? dash))"
        }
        // The word turns on the loss quantized as stage 1 quantizes every compared value.
        let quantized = CutScorecard.quantize(loss)
        let word = quantized > 0 ? "losing" : (quantized < 0 ? "gaining" : "flat")
        let share = number(rate.percentPerWeek).map { fixed(abs($0), 2) } ?? dash
        let reference = positive(rate.referenceWeightKg).map { fixed($0, 1) } ?? dash
        return "rate: \(word) \(fixed(abs(loss), 2)) kg/week (\(share) %/week of \(reference) kg)"
            + "; fitted over \(rate.pointsUsed) weigh-ins, weeks "
            + "\(dayText(rate.firstWeekStart))..\(dayText(rate.lastWeekStart))"
    }

    private static func projectionLine(_ projection: CutScorecardProjection) -> String {
        let remaining = number(projection.remainingKg).map { fixed($0, 1) }
        if projection.status == .projected {
            let weeks = number(projection.weeksRemaining).map { fixed($0, 1) } ?? dash
            return "projection: \(dayText(projection.targetDay)) (estimate), \(weeks) weeks, "
                + "\(remaining ?? dash) kg remaining"
        }
        return "projection: none (\(projection.status.rawValue))"
            + (remaining.map { "; \($0) kg remaining" } ?? "")
    }

    private static func rejectionLine(_ rejections: CutScorecardRejections) -> String? {
        let counts = [rejections.nonFinite, rejections.nonPositive, rejections.invalidDay, rejections.future]
        guard counts.contains(where: { $0 > 0 }) else { return nil }
        // The sum saturates, so four absurd counts cannot trap.
        let total = counts.reduce(0) { sum, count in
            let (next, overflowed) = sum.addingReportingOverflow(count)
            return overflowed ? (count > 0 ? Int.max : Int.min) : next
        }
        return "ignored-readings: \(total) (nonFinite \(rejections.nonFinite), "
            + "nonPositive \(rejections.nonPositive), invalidDay \(rejections.invalidDay), "
            + "future \(rejections.future))"
    }

    // MARK: - Weigh-ins (§7.4)

    private static func weighInLines(_ input: CoachPacketInput) -> [String] {
        var lines = [currentLine(.weight, "weight", unit: "kg", input.body),
                     currentLine(.waist, "waist", unit: "cm", input.body)]
        guard case let .evaluated(_, result) = input.scorecard else {
            return lines + ["weekly: not available (the scorecard is switched off in the app)"]
        }
        guard result.invalidInput == nil, !result.weeks.isEmpty else {
            return lines + ["weekly: no weigh-ins yet"]
        }
        let shown = result.weeks.suffix(weeklyRowLimit)
        lines.append("weekly, weeks start Monday, the latest reading of a week represents it, "
            + "last \(shown.count) of \(result.weeks.count) weeks:")
        for week in shown {
            // The change is the negated loss: negative means lighter than the week before.
            let change = number(week.weeklyLossKg).map { "\(signed(-$0, 1)) kg" } ?? dash
            lines.append("  \(dayText(week.weekStart)): "
                + "weight \(weeklyValue(week.weightKg, unit: "kg", day: week.weightDay)), "
                + "waist \(weeklyValue(week.waistCm, unit: "cm", day: week.waistDay)), "
                + "change \(change)")
        }
        return lines
    }

    private static func weeklyValue(_ value: Double?, unit: String, day: String?) -> String {
        guard let value = positive(value) else { return dash }
        return "\(fixed(value, 1)) \(unit) (\(dayText(day)))"
    }

    private static func currentLine(_ kind: CoachPacketBodyKind, _ label: String, unit: String,
                                    _ body: [CoachPacketBodyReading]) -> String {
        // Ruling A17: a reading whose day is not a canonical key is ignored and never printed, and
        // the later of the remaining readings of a kind wins, as for days and steps. A reading with
        // no day at all (the undated profile value) is kept and printed without one.
        // SPEC-NOTE: a winning value that is not a positive finite number makes the item absent.
        let usable = body.last(where: { reading in
            guard reading.kind == kind else { return false }
            guard let day = reading.day else { return true }
            return CanonicalDay.number(day) != nil
        })
        guard let reading = usable, let value = positive(reading.value)
        else { return "current \(label): \(dash)" }
        let day = reading.day.map { ", \($0)" } ?? ""
        return "current \(label): \(fixed(value, 1)) \(unit) (\(reading.source.rawValue)\(day))"
    }

    // MARK: - Intake (§7.12)

    /// The lead line of the intake section.
    static let intakeLead = "per day, oldest first, as the owner logged it; "
        + "the source is \"mixed\" when protein and energy came from different sources:"

    /// Whether the rendered packet prints at least one intake amount (ruling A26: an intake value is
    /// a measurement, so the sheet does not say nothing was measured). False while the Intake section
    /// is not selected or the feature is off. Read from the same rows `render` prints.
    public static func printsIntakeAmount(_ input: CoachPacketInput) -> Bool {
        guard input.sections.contains(.intake), let first = CanonicalDay.number(input.rangeStartDay) else {
            return false
        }
        let keys = dayKeys(from: input.rangeStartDay, to: input.rangeEndDay)
        guard !keys.isEmpty else { return false }
        let rows = intakeRows(input.intake, PacketRange(firstNumber: first, keys: keys)) ?? []
        return rows.contains { $0.protein != nil || $0.energy != nil }
    }

    /// One printed intake row per day of the range; nil while the feature is off in the app.
    private static func intakeRows(_ intake: CoachPacketIntake, _ range: PacketRange)
        -> [(key: String, protein: Int?, energy: Int?, source: CoachPacketIntakeSource?)]? {
        guard case let .days(days) = intake else { return nil }
        // Two entries for one day: the last wins, as for days and steps.
        var byDay: [Int: CoachPacketIntakeDay] = [:]
        for day in days {
            if let number = range.number(of: day.day) { byDay[number] = day }
        }
        return range.keys.enumerated().map { offset, key in
            let day = byDay[range.firstNumber + offset]
            return (key: key, protein: day.flatMap { intakeAmount($0.proteinGrams) },
                    energy: day.flatMap { intakeAmount($0.energyKcal) }, source: day?.source)
        }
    }

    private static func intakeLines(_ intake: CoachPacketIntake, _ range: PacketRange) -> [String] {
        guard let rows = intakeRows(intake, range) else {
            return ["not available: intake is switched off in the app"]
        }
        var lines = [intakeLead]
        for row in rows {
            var line = "  \(row.key): protein \(row.protein.map { "\($0) g" } ?? dash), "
                + "energy \(row.energy.map { "\($0) kcal" } ?? dash)"
            // The source says where a printed value came from, so a day with none prints no source.
            if row.protein != nil || row.energy != nil, let source = row.source { line += " [\(source.rawValue)]" }
            lines.append(line)
        }
        return lines
    }

    /// A logged amount as a whole number, or nil when it is no number at all: not finite or above
    /// rule F1's limit, or below zero. Ruling A25: the packet adds no limit of its own, so every
    /// amount the app accepted, and a day's sum past the store's per-entry limit, is printed.
    private static func intakeAmount(_ value: Double?) -> Int? {
        nonNegative(value).map(rounded)
    }

    // MARK: - Events (§7.12)

    /// The renderer prints the rows stage 5 returned and adds nothing to them. It treats them as text
    /// it did not write: a row that is not the lead line, the "none listed" row or a two-space row is
    /// dropped, and a longer row is cut, so `render` stays total and the budget true by construction.
    private static func eventLines(_ events: CoachPacketEvents) -> [String] {
        guard case let .rows(rows) = events else {
            return ["not available: events is switched off in the app"]
        }
        var lines: [String] = []
        var indented = 0
        var sentinelKept = false
        for row in rows {
            // SPEC-NOTE: a row with a control character (a line break, a tab) would break the line
            // grammar of §7.12 G-2, so it is malformed and dropped like a row without the indent.
            guard !row.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else { continue }
            if row == PersonalEvents.packetIntroRow || row == PersonalEvents.packetNoneListedRow {
                // Stage 5 returns one of the two, once: the lead line before its rows, or "none
                // listed" alone. The first is kept and any repeat dropped, so the allowance, which
                // counts one lead line and the indented row limit, holds for any rows (Codex C16).
                guard !sentinelKept else { continue }
                sentinelKept = true
                lines.append(row)
            } else if row.hasPrefix(PersonalEvents.packetRowIndent) {
                // A row that is only its indent, or ends in spaces, would print a trailing space.
                let kept = cut(row, toBytes: eventRowByteLimit)
                guard kept.count > PersonalEvents.packetRowIndent.count else { continue }
                // SPEC-NOTE: §7.12 bounds each row, not their number. Stage 5 returns at most the
                // "earlier" row and twelve event rows, so at most that many indented rows are kept and
                // the allowance covers the section for any input.
                guard indented < PersonalEvents.packetRowLimit + 1 else { continue }
                indented += 1
                lines.append(kept)
            }
        }
        // SPEC-NOTE: G-6 says an empty list in words. Rows that leave nothing are worded as stage 5
        // words an empty listing; stage 5 itself never returns none.
        return lines.isEmpty ? [PersonalEvents.packetNoneListedRow] : lines
    }

    /// `text` cut at a character boundary to at most `limit` UTF-8 bytes, without a trailing space.
    private static func cut(_ text: String, toBytes limit: Int) -> String {
        var kept = ""
        var bytes = 0
        for character in text {
            let width = character.utf8.count
            guard bytes + width <= limit else { break }
            kept.append(character)
            bytes += width
        }
        while kept.hasSuffix(" ") { kept.removeLast() }
        return kept
    }

    // MARK: - Recovery and sleep (§7.5)

    private static func recoverySleepLines(_ input: CoachPacketInput, _ range: PacketRange) -> [String] {
        let style = CoachDayStyle.packet(strainFactor: input.strainFactor)
        let scale = input.strainFactor < 1 ? "0-21 scale" : "0-100 scale"
        let rows = rowsByDay(input, range)
        var lines = ["per day, oldest first: recovery (0-100), strain (\(scale)), sleep (h), "
            + "deep/REM/light (h), eff (%), HRV (ms), RHR (bpm)"]
        var present: [DailyMetric] = []
        for (offset, key) in range.keys.enumerated() {
            let row = rows[range.firstNumber + offset]
            if let row { present.append(row) }
            // A calendar day with no row prints the line of a row whose every field is nil.
            let shown = row ?? DailyMetric(day: key, totalSleepMin: nil, efficiency: nil, deepMin: nil,
                                           remMin: nil, lightMin: nil, disturbances: nil,
                                           restingHr: nil, avgHrv: nil, recovery: nil, strain: nil,
                                           exerciseCount: nil)
            let suffix = row?.sleepHrOnly == true ? " [sleep staged from heart rate only]" : ""
            lines.append("  " + CoachDayFormat.dayLine(shown, style: style) + suffix)
        }
        if present.isEmpty {
            lines.append("averages: no data in range")
        } else {
            lines.append("averages over \(present.count) of \(range.keys.count) days with data: "
                + CoachDayFormat.primaryAveragesLine(present, style: style))
        }
        return lines
    }

    // MARK: - Trends (§7.6)

    private static func trendLines(_ input: CoachPacketInput, _ range: PacketRange) -> [String] {
        let rows = rowsByDay(input, range)
        var hrv: [(day: Int, value: Double)] = []
        var restingHr: [(day: Int, value: Double)] = []
        for number in range.firstNumber...range.lastNumber {
            guard let row = rows[number] else { continue }
            if let value = self.number(row.avgHrv) { hrv.append((number, value)) }
            if let value = self.number(row.restingHr.map(Double.init)) { restingHr.append((number, value)) }
        }
        return [
            "baseline is the app's personal baseline behind the recovery score; typical is baseline plus or minus one sigma",
            trendLine("HRV", unit: "ms", baseline: input.hrvBaseline, values: hrv, range: range),
            trendLine("RHR", unit: "bpm", baseline: input.restingHrBaseline, values: restingHr, range: range),
        ]
    }

    /// The mean of `values` to the nearest whole number; nil for no values.
    private static func wholeMean(_ values: [Double]) -> Int? {
        guard !values.isEmpty else { return nil }
        return rounded(values.reduce(0, +) / Double(values.count))
    }

    private static func trendLine(_ label: String, unit: String, baseline: CoachPacketBaseline?,
                                  values: [(day: Int, value: Double)], range: PacketRange) -> String {
        // A baseline whose centre is not a positive finite number is absent. It is usable exactly
        // when it has a typical range with finite bounds.
        let center = baseline.flatMap { positive($0.center) }.map { rounded($0) }
        var typical: (lower: Double, upper: Double)?
        if center != nil, let band = baseline?.typical,
           let lower = number(band.lowerBound), let upper = number(band.upperBound) {
            typical = (lower, upper)
        }
        var clauses: [String] = []
        if let baseline, let center {
            let state = "\(sanitize(baseline.status)), \(baseline.nights) nights"
            if let typical {
                clauses.append("baseline \(center) \(unit) "
                    + "(typical \(rounded(typical.lower)) to \(rounded(typical.upper)), \(state))")
            } else {
                clauses.append("baseline not established (\(state))")
            }
        } else {
            clauses.append("baseline not available")
        }
        // The difference is the difference of the two printed integers.
        func versusBaseline(_ mean: Int) -> String {
            guard typical != nil, let center else { return "" }
            return " (\(signed(mean - center)) vs baseline)"
        }
        let all = values.map(\.value)
        if let mean = wholeMean(all) {
            clauses.append("range mean \(mean) \(unit) over \(all.count) nights" + versusBaseline(mean))
        } else {
            clauses.append("range mean \(dash) over 0 nights")
        }
        let recent = values.filter { $0.day > range.lastNumber - recentWindowDays }.map(\.value)
        if range.keys.count > recentWindowDays, let mean = wholeMean(recent) {
            clauses.append("last \(recentWindowDays) days mean \(mean) \(unit) over \(recent.count) nights"
                + versusBaseline(mean))
        }
        if let typical, !all.isEmpty {
            // Counted against the unrounded bounds; a value on a bound is inside.
            let below = all.filter { $0 < typical.lower }.count
            let above = all.filter { $0 > typical.upper }.count
            clauses.append("outside typical: \(below) below, \(above) above")
        }
        return "\(label): " + clauses.joined(separator: "; ")
    }

    // MARK: - Activity (§7.7)

    private static func stepLines(_ input: CoachPacketInput, _ range: PacketRange) -> [String] {
        // Two step days for one day: the last wins, and its count is then a value or not.
        var byDay: [Int: CoachPacketStepDay] = [:]
        for day in input.steps {
            if let number = range.number(of: day.day) { byDay[number] = day }
        }
        var lines = ["steps per day; \"strap-estimate\" is an estimate from strap motion, not a count:"]
        var sum = 0.0
        var counted = 0
        var bySource: [CoachPacketStepSource: Int] = [:]
        for (offset, key) in range.keys.enumerated() {
            let isToday = offset == range.keys.count - 1
            guard let day = byDay[range.firstNumber + offset], let steps = nonNegative(day.steps) else {
                // SPEC-NOTE: §7.7 gives the missing form as "<day>: —" with no "(today so far)", so a
                // missing today is printed bare.
                lines.append("  \(key): \(dash)")
                continue
            }
            let mark = day.source == .strapEstimate ? "~" : ""
            lines.append("  \(key): \(mark)\(rounded(steps)) \(day.source.rawValue)"
                + (isToday ? " (today so far)" : ""))
            // The average leaves out the last day, which is today and partial.
            if !isToday {
                sum += steps
                counted += 1
                bySource[day.source, default: 0] += 1
            }
        }
        if counted == 0 {
            lines.append("steps average: \(dash) (no step data in range)")
        } else {
            let sources = [CoachPacketStepSource.strap, .appleHealth, .strapEstimate]
                .compactMap { source in bySource[source].map { "\(source.rawValue) \($0)" } }
                .joined(separator: ", ")
            // A mean of values of at most 1e15 cannot leave the range `Int(_:)` accepts.
            lines.append("steps average: \(rounded(sum / Double(counted))) over \(counted) "
                + "of \(range.keys.count - 1) full days (\(sources))")
        }
        return lines
    }

    private static func workoutLines(_ input: CoachPacketInput, _ range: PacketRange) -> [String] {
        // Every value is settled before the sort, so the order is a total one that does not depend
        // on the order the workouts arrived in.
        struct Row {
            let day: Int
            let minute: Int
            let sport: String
            let source: String
            let duration: Double?
            let heartRate: Int?
            let energy: Double?
            let distance: Double?

            /// By day, then start minute; the remaining fields only settle ties.
            static func precedes(_ a: Row, _ b: Row) -> Bool {
                if (a.day, a.minute) != (b.day, b.minute) { return (a.day, a.minute) < (b.day, b.minute) }
                if (a.sport, a.source) != (b.sport, b.source) {
                    return (a.sport, a.source) < (b.sport, b.source)
                }
                let x = (a.duration ?? -1, a.heartRate ?? -1, a.energy ?? -1, a.distance ?? -1)
                let y = (b.duration ?? -1, b.heartRate ?? -1, b.energy ?? -1, b.distance ?? -1)
                return x < y
            }
        }
        var rows: [Row] = []
        for workout in input.workouts {
            guard let day = range.number(of: workout.day) else { continue }
            rows.append(Row(day: day, minute: workout.startMinuteOfDay, sport: sanitize(workout.sport),
                            source: workout.source.rawValue,
                            duration: nonNegative(workout.durationMinutes),
                            heartRate: workout.avgHr.flatMap { heartRateRange.contains($0) ? $0 : nil },
                            energy: nonNegative(workout.energyKcal),
                            distance: nonNegative(workout.distanceKm)))
        }
        guard !rows.isEmpty else { return ["workouts: none recorded in range"] }
        rows.sort(by: Row.precedes)
        var lines = ["workouts in range, oldest first, summaries only:"]
        if rows.count > workoutRowLimit {
            lines.append("  (\(rows.count - workoutRowLimit) earlier workouts in range not shown)")
        }
        for row in rows.suffix(workoutRowLimit) {
            var line = "  \(CanonicalDay.key(row.day)) \(clock(row.minute)) \(row.sport)"
            line += ", \(row.duration.map { "\(rounded($0))" } ?? dash) min"
            line += ", avg HR " + (row.heartRate.map { "\($0) bpm" } ?? dash)
            line += ", \(row.energy.map { "\(rounded($0))" } ?? dash) kcal"
            if let distance = row.distance { line += ", \(fixed(distance, 2)) km" }
            lines.append(line + " [\(row.source)]")
        }
        return lines
    }

    /// A minute of the day as "HH:MM"; "--:--" outside 0…1439.
    private static func clock(_ minute: Int) -> String {
        guard minuteOfDayRange.contains(minute) else { return "--:--" }
        func two(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
        return two(minute / 60) + ":" + two(minute % 60)
    }
}
