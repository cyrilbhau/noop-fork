import XCTest
@testable import StrandAnalytics

// The parity oracle of `CutScorecard`, Swift side (docs/personal/superapp/specs/stage-1.md §12.7).
//
// The block between the two ORACLE-SHARED markers is the whole oracle: a fixed-seed generator, the
// synthetic fixture of §13, the named edges and one canonical line per case. It uses Foundation only, so
// `Tools/personal/cut_scorecard_oracle.sh` can lift it out unchanged, compile it standalone with
// `CutScorecard.swift`, `WeeklyDigest.swift` and `ComparisonEngine.swift`, and diff its standard output
// against `android/app/src/test/resources/cut_scorecard_oracle.txt`.
//
// That file is the expected literal for both directions. The Kotlin twin's
// `CutScorecardParityOracleTest` rebuilds the same inputs with a transliteration of this generator and
// compares against it; the test class below does the same on the Swift side, so a change to
// `CutScorecard.swift` fails here and not only on Android. There is one copy of the literal, read by
// both, so the two sides cannot hold different expectations.
//
// Everything here is invented. No value was taken from a real person's log.

// ORACLE-SHARED-BEGIN
enum CutScorecardOracle {

    // MARK: Generator

    /// A 64-bit linear congruential generator, written out so Kotlin reproduces it with `Long`
    /// arithmetic. Only integers leave it; a Double is always an integer divided by a constant.
    struct LCG {
        var state: UInt64
        init(seed: UInt64) { state = seed }

        /// The next value, in 0 ..< 2^31.
        mutating func next() -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(state >> 33)
        }

        /// A value in 0 ..< n.
        mutating func below(_ n: Int) -> Int { next() % n }

        /// True once in `n` draws.
        mutating func chance(_ n: Int) -> Bool { below(n) == 0 }
    }

    static let seed: UInt64 = 20_311_106
    static let generatedCount = 600

    // MARK: Input digest

    /// FNV-1a over the input, so a difference in the generated inputs is told apart from a difference in
    /// the engine. Integers and Double bit patterns only; no formatting is involved.
    struct Digest {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325

        mutating func byte(_ value: UInt64) { hash = (hash ^ (value & 0xff)) &* 0x0000_0100_0000_01b3 }

        mutating func int(_ value: Int) {
            var bits = UInt64(bitPattern: Int64(value))
            for _ in 0..<8 { byte(bits); bits >>= 8 }
        }

        mutating func double(_ value: Double) {
            var bits = value.isNaN ? 0x7ff8_0000_0000_0000 : value.bitPattern
            for _ in 0..<8 { byte(bits); bits >>= 8 }
        }

        mutating func optionalDouble(_ value: Double?) {
            if let value = value { byte(1); double(value) } else { byte(0) }
        }

        mutating func string(_ value: String) {
            for unit in value.utf8 { byte(UInt64(unit)) }
            byte(0xff)
        }

        var hex: String {
            let digits = String(hash, radix: 16)
            return String(repeating: "0", count: 16 - digits.count) + digits
        }
    }

    static func digest(_ input: CutScorecardInput) -> String {
        var d = Digest()
        d.int(input.weights.count)
        for r in input.weights { d.string(r.day); d.int(r.takenAt); d.double(r.value) }
        d.int(input.waists.count)
        for r in input.waists { d.string(r.day); d.int(r.takenAt); d.double(r.value) }
        d.int(input.lifts.count)
        for l in input.lifts { d.string(l.day); d.string(l.exercise); d.double(l.weightKg) }
        d.int(input.proteinDays.count)
        for e in input.proteinDays { d.string(e.day); d.double(e.grams) }
        if let phase = input.phase {
            d.byte(1)
            d.string(phase.name); d.string(phase.startDay); d.optionalDouble(phase.targetWeightKg)
            d.double(phase.rateLowPercentPerWeek); d.double(phase.rateHighPercentPerWeek)
        } else {
            d.byte(0)
        }
        let p = input.parameters
        d.int(p.rateWindowWeeks); d.int(p.waistWindowWeeks); d.double(p.waistMinDecreaseCm)
        d.double(p.liftDropTolerancePercent); d.double(p.liftDropShare); d.int(p.liftDropConsecutiveWeeks)
        d.int(p.addCaloriesKcal); d.double(p.slowLossThresholdKgPerWeek); d.int(p.slowLossConsecutiveWeeks)
        d.int(p.reduceCarbsKcal); d.optionalDouble(p.proteinFloorGrams); d.int(p.proteinMinDaysPerWeek)
        d.int(p.maxWeighInAgeWeeks); d.int(p.maxProjectionWeeks); d.double(p.targetToleranceKg)
        d.string(input.today)
        return d.hex
    }

    // MARK: Day arithmetic (independent of the engine)

    /// Days since 1970-01-01 of a civil date in years 0001 to 9999. Every division is of non-negative
    /// integers, so truncating and flooring division agree.
    static func dayNumber(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = y / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    static func pad(_ value: Int, _ width: Int) -> String {
        let digits = String(value)
        return digits.count >= width ? digits : String(repeating: "0", count: width - digits.count) + digits
    }

    /// The "yyyy-MM-dd" key of a day number from `dayNumber`.
    static func key(_ number: Int) -> String {
        let z = number + 719_468
        let era = z / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
        return pad(y, 4) + "-" + pad(m, 2) + "-" + pad(d, 2)
    }

    /// Epoch seconds at `hour`:00 UTC of a day number.
    static func epoch(_ number: Int, _ hour: Int) -> Int { number * 86_400 + hour * 3_600 }

    static func reading(_ number: Int, _ value: Double, _ hour: Int) -> CutScorecardReading {
        CutScorecardReading(day: key(number), takenAt: epoch(number, hour), value: value)
    }

    static func lift(_ number: Int, _ exercise: String, _ kg: Double) -> CutScorecardLiftObservation {
        CutScorecardLiftObservation(day: key(number), exercise: exercise, weightKg: kg)
    }

    static func protein(_ number: Int, _ grams: Double) -> CutScorecardProteinDay {
        CutScorecardProteinDay(day: key(number), grams: grams)
    }

    // MARK: Canonical line

    static func f(_ value: Double) -> String { String(format: "%.6f", value) }
    static func fo(_ value: Double?) -> String { value == nil ? "nil" : f(value ?? 0) }
    static func so(_ value: String?) -> String { value ?? "nil" }
    static func io(_ value: Int?) -> String { value == nil ? "nil" : String(value ?? 0) }

    static func rules(_ list: [CutScorecardRule]) -> String {
        var parts: [String] = []
        for rule in list { parts.append(rule.rawValue) }
        return "[" + parts.joined(separator: "+") + "]"
    }

    /// Every field of the result, in declaration order. Doubles as "%.6f", nil as "nil", enums as raw
    /// values.
    static func format(_ r: CutScorecardResult) -> String {
        var weeks: [String] = []
        for w in r.weeks {
            weeks.append([w.weekStart, fo(w.weightKg), so(w.weightDay), fo(w.waistCm), so(w.waistDay),
                          w.inPhase ? "true" : "false", fo(w.weeklyLossKg)].joined(separator: ","))
        }
        var rate = "nil"
        if let x = r.rate {
            rate = [f(x.lossKgPerWeek), f(x.percentPerWeek), f(x.referenceWeightKg), String(x.pointsUsed),
                    String(x.spanWeeks), x.firstWeekStart, x.lastWeekStart].joined(separator: ",")
        }
        let projection = [r.projection.status.rawValue, so(r.projection.targetDay),
                          fo(r.projection.weeksRemaining), fo(r.projection.remainingKg)].joined(separator: ",")
        let waist = r.signals.waist
        let lifts = r.signals.lifts
        let protein = r.signals.protein
        let band = r.signals.rateBand
        var ruleParts: [String] = []
        for e in r.rules {
            ruleParts.append([e.rule.rawValue, e.state.rawValue, so(e.unknownReason?.rawValue),
                              String(e.consecutiveWeeks), String(e.requiredWeeks)].joined(separator: ":"))
        }
        let v = r.verdict
        var fields: [String] = []
        fields.append("weeks=" + String(r.weeks.count) + "[" + weeks.joined(separator: ";") + "]")
        fields.append("judged=" + so(r.judgedWeekStart))
        fields.append("current=" + fo(r.currentWeightKg) + "," + so(r.currentWeightDay))
        fields.append("rate=" + rate)
        fields.append("rateUnavailable=" + so(r.rateUnavailable?.rawValue))
        fields.append("projection=" + projection)
        fields.append("waist=" + [waist.state.rawValue, waist.reason.rawValue, fo(waist.currentCm),
                                  fo(waist.referenceCm), so(waist.referenceWeekStart),
                                  fo(waist.changeCm)].joined(separator: ","))
        fields.append("lifts=" + [lifts.state.rawValue, lifts.reason.rawValue, String(lifts.commonExercises),
                                  String(lifts.dropped), String(lifts.climbed), String(lifts.held),
                                  so(lifts.windowStartDay), so(lifts.windowEndDay)].joined(separator: ","))
        fields.append("protein=" + [protein.state.rawValue, protein.reason.rawValue, String(protein.daysLogged),
                                    String(protein.daysAtOrAboveFloor), String(protein.requiredDays),
                                    fo(protein.floorGrams)].joined(separator: ","))
        fields.append("rateBand=" + [band.state.rawValue, band.reason.rawValue, fo(band.percentPerWeek),
                                     fo(band.lowPercentPerWeek), fo(band.highPercentPerWeek)].joined(separator: ","))
        fields.append("rules=" + ruleParts.joined(separator: ";"))
        fields.append("verdict=" + [v.kind.rawValue, v.reason.rawValue, so(v.rule?.rawValue),
                                    io(v.calorieChangeKcal), rules(v.overriddenRules),
                                    rules(v.unevaluatedRules)].joined(separator: ","))
        fields.append("evidence=" + so(r.evidenceStartDay))
        fields.append("rejections=" + [String(r.rejections.nonFinite), String(r.rejections.nonPositive),
                                       String(r.rejections.invalidDay), String(r.rejections.future)].joined(separator: ","))
        fields.append("invalid=" + so(r.invalidInput?.rawValue))
        return fields.joined(separator: "|")
    }

    static func line(_ label: String, _ input: CutScorecardInput) -> String {
        label + "|in=" + digest(input) + "|" + format(CutScorecard.evaluate(input))
    }

    static func bitsHex(_ value: Double) -> String {
        let digits = String(value.isNaN ? 0x7ff8_0000_0000_0000 : value.bitPattern, radix: 16)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }

    // MARK: Fixture (§13)

    static let fixtureMonday = dayNumber(2031, 1, 6)
    static let fixtureWeekCount = 22
    static let pressName = "Fixture Press"
    static let rowName = "Fixture Row"

    static let fixtureWeights: [Double?] = [
        100.0, 99.2, 98.4, 97.6, 97.5, 97.4, 97.3, 97.2, 97.1, nil, 96.0,
        95.2, 95.1, 95.0, 94.9, 94.8, 94.7, 94.6, 94.5, 95.5, 94.0, 93.5,
    ]
    static let fixtureWaists: [Double?] = [
        100.0, 99.5, 99.0, 98.5, 98.0, 97.5, 97.0, 97.0, 97.0, nil, 96.5,
        96.0, 95.5, 95.0, 94.5, 94.5, 94.5, 94.5, 94.5, 94.5, 94.0, 93.5,
    ]
    /// One Monday session per entry: fixture week, Fixture Press kg, Fixture Row kg.
    static let fixtureSessionWeeks: [Int] = [-1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 16, 17, 18, 19, 20, 21, 22]
    static let fixturePressKg: [Double] = [60.0, 60.0, 60.0, 60.0, 60.0, 60.0, 62.5, 62.5, 62.5, 62.5, 62.5,
                                           62.5, 57.5, 52.5, 47.5, 47.5, 47.5, 50.0]
    static let fixtureRowKg: [Double] = [50.0, 50.0, 50.0, 50.0, 50.0, 50.0, 50.0, 50.0, 52.5, 52.5, 52.5,
                                         52.5, 47.5, 42.5, 40.0, 40.0, 40.0, 40.0]
    /// Protein for the seven days before the weigh-in of fixture weeks 2 to 6, oldest first.
    static let fixtureProteinWeeks: [Int] = [2, 3, 4, 5, 6]
    static let fixtureProtein: [[Double?]] = [
        [120, 120, 120, 80, 120, 120, 120],
        [120, 120, 120, 80, 120, 120, 120],
        [120, 120, 120, 80, 120, 120, 120],
        [120, 80, 80, 120, 80, 80, 120],
        [120, nil, 120, nil, nil, 120, nil],
    ]

    static let fixtureParameters = CutScorecardParameters(
        rateWindowWeeks: 4, waistWindowWeeks: 2, waistMinDecreaseCm: 0.5,
        liftDropTolerancePercent: 5, liftDropShare: 0.5, liftDropConsecutiveWeeks: 3,
        addCaloriesKcal: 300, slowLossThresholdKgPerWeek: 0.4, slowLossConsecutiveWeeks: 3,
        reduceCarbsKcal: 250, proteinFloorGrams: 100, proteinMinDaysPerWeek: 5,
        maxWeighInAgeWeeks: 1, maxProjectionWeeks: 104, targetToleranceKg: 0)

    /// The fixture's data with week 1's Monday on day number `monday`, uncut.
    struct Data {
        var weights: [CutScorecardReading] = []
        var waists: [CutScorecardReading] = []
        var lifts: [CutScorecardLiftObservation] = []
        var proteinDays: [CutScorecardProteinDay] = []
    }

    /// The Monday of fixture week `week` (weeks before week 1 are 0, -1, and so on).
    static func monday(_ base: Int, _ week: Int) -> Int { base + 7 * (week - 1) }

    /// The Wednesday of fixture week `week`: the weigh-in day.
    static func weighIn(_ base: Int, _ week: Int) -> Int { monday(base, week) + 2 }

    static func fixtureData(_ base: Int) -> Data {
        var data = Data()
        for i in 0..<fixtureWeekCount {
            if let kg = fixtureWeights[i] { data.weights.append(reading(weighIn(base, i + 1), kg, 7)) }
            if let cm = fixtureWaists[i] { data.waists.append(reading(weighIn(base, i + 1), cm, 7)) }
        }
        // The one extra reading: Monday of week 3. It must lose to Wednesday's 98.4.
        data.weights.append(reading(monday(base, 3), 98.9, 7))
        for i in 0..<fixtureSessionWeeks.count {
            let day = monday(base, fixtureSessionWeeks[i])
            data.lifts.append(lift(day, pressName, fixturePressKg[i]))
            data.lifts.append(lift(day, rowName, fixtureRowKg[i]))
        }
        for i in 0..<fixtureProteinWeeks.count {
            let anchor = weighIn(base, fixtureProteinWeeks[i])
            for k in 0..<7 {
                if let grams = fixtureProtein[i][k] { data.proteinDays.append(protein(anchor + k - 7, grams)) }
            }
        }
        return data
    }

    static func fixturePhase(_ base: Int) -> CutScorecardPhase {
        CutScorecardPhase(name: "Fixture cut", startDay: key(base), targetWeightKg: 94.0,
                          rateLowPercentPerWeek: 0.40, rateHighPercentPerWeek: 1.20)
    }

    /// `data` as it stood on day number `today`: every array cut to the items dated on or before it.
    /// `data` holds canonical keys only, so string order is calendar order.
    static func cut(_ data: Data, today: Int, phase: CutScorecardPhase?,
                    parameters: CutScorecardParameters) -> CutScorecardInput {
        let todayKey = key(today)
        var weights: [CutScorecardReading] = []
        for r in data.weights where r.day <= todayKey { weights.append(r) }
        var waists: [CutScorecardReading] = []
        for r in data.waists where r.day <= todayKey { waists.append(r) }
        var lifts: [CutScorecardLiftObservation] = []
        for l in data.lifts where l.day <= todayKey { lifts.append(l) }
        var proteinDays: [CutScorecardProteinDay] = []
        for e in data.proteinDays where e.day <= todayKey { proteinDays.append(e) }
        return CutScorecardInput(weights: weights, waists: waists, lifts: lifts, proteinDays: proteinDays,
                                 phase: phase, parameters: parameters, today: todayKey)
    }

    /// The fixture on the weigh-in day of `week`.
    static func fixtureInput(week: Int) -> CutScorecardInput {
        cut(fixtureData(fixtureMonday), today: weighIn(fixtureMonday, week), phase: fixturePhase(fixtureMonday),
            parameters: fixtureParameters)
    }

    /// §13.4, V1 to V12, plus the corrected V8 of §18 R16.
    static func fixtureVariants() -> [(String, CutScorecardInput)] {
        let base = fixtureMonday
        let phase = fixturePhase(base)
        let p = fixtureParameters
        let data = fixtureData(base)
        var out: [(String, CutScorecardInput)] = []

        out.append(("fixture-V1", CutScorecardInput(weights: [], waists: [], lifts: [], proteinDays: [],
                                                    phase: phase, parameters: p, today: key(weighIn(base, 1)))))

        var v2 = data
        v2.lifts = []
        out.append(("fixture-V2", cut(v2, today: weighIn(base, 1), phase: phase, parameters: p)))

        var v3 = data
        v3.weights = []
        for r in data.weights where r.day != key(weighIn(base, 11)) { v3.weights.append(r) }
        v3.waists = []
        for r in data.waists where r.day != key(weighIn(base, 11)) { v3.waists.append(r) }
        out.append(("fixture-V3", cut(v3, today: weighIn(base, 11), phase: phase, parameters: p)))

        out.append(("fixture-V4", cut(data, today: weighIn(base, 4), phase: nil, parameters: p)))

        let v5Phase = CutScorecardPhase(name: "Fixture cut", startDay: key(monday(base, 5)), targetWeightKg: 94.0,
                                        rateLowPercentPerWeek: 0.40, rateHighPercentPerWeek: 1.20)
        out.append(("fixture-V5", cut(data, today: weighIn(base, 7), phase: v5Phase, parameters: p)))

        let v6Phase = CutScorecardPhase(name: "Fixture cut", startDay: key(base), targetWeightKg: nil,
                                        rateLowPercentPerWeek: 0.40, rateHighPercentPerWeek: 1.20)
        out.append(("fixture-V6", cut(data, today: weighIn(base, 4), phase: v6Phase, parameters: p)))

        var v7 = data
        v7.weights.append(reading(dayNumber(2031, 1, 16), 98.0, 7))
        out.append(("fixture-V7", cut(v7, today: weighIn(base, 9), phase: phase, parameters: p)))

        var v8 = data
        v8.weights = []
        for r in data.weights {
            v8.weights.append(r.day == key(weighIn(base, 6)) ? reading(weighIn(base, 6), 99.9, 7) : r)
        }
        out.append(("fixture-V8", cut(v8, today: weighIn(base, 8), phase: phase, parameters: p)))
        // §18 R16: the outlier as the last point of the fit window.
        out.append(("fixture-V8-R16", cut(v8, today: weighIn(base, 6), phase: phase, parameters: p)))

        var v9 = data
        v9.weights.append(reading(monday(base, 4) + 1, Double.nan, 7))
        v9.weights.append(reading(monday(base, 4) + 3, -5.0, 7))
        out.append(("fixture-V9", cut(v9, today: weighIn(base, 4), phase: phase, parameters: p)))

        var v10 = data
        v10.weights.append(reading(dayNumber(2029, 6, 6), 101.0, 7))
        out.append(("fixture-V10", cut(v10, today: weighIn(base, 22), phase: phase, parameters: p)))

        var v11 = data
        v11.lifts = []
        for i in 0..<fixtureSessionWeeks.count {
            let day = monday(base, fixtureSessionWeeks[i])
            v11.lifts.append(lift(day, fixtureSessionWeeks[i] >= 17 ? "fixture press" : pressName, fixturePressKg[i]))
            v11.lifts.append(lift(day, rowName, fixtureRowKg[i]))
        }
        out.append(("fixture-V11-w17", cut(v11, today: weighIn(base, 17), phase: phase, parameters: p)))
        out.append(("fixture-V11-w18", cut(v11, today: weighIn(base, 18), phase: phase, parameters: p)))

        let v12Phase = CutScorecardPhase(name: "Fixture cut", startDay: key(base), targetWeightKg: 80.0,
                                         rateLowPercentPerWeek: 0.40, rateHighPercentPerWeek: 1.20)
        out.append(("fixture-V12", cut(data, today: weighIn(base, 8), phase: v12Phase, parameters: p)))
        return out
    }

    // MARK: Named edges (§12.7 item 3, §18 R1 to R16)

    /// One Wednesday reading per week from week 1 of `base`; nil leaves the week empty.
    static func weekly(_ base: Int, _ values: [Double?]) -> [CutScorecardReading] {
        var out: [CutScorecardReading] = []
        for i in 0..<values.count {
            if let value = values[i] { out.append(reading(weighIn(base, i + 1), value, 7)) }
        }
        return out
    }

    /// Monday sessions at an unchanging 60.0 / 50.0 for fixture weeks `first` through `last`.
    static func holding(_ base: Int, _ first: Int, _ last: Int) -> [CutScorecardLiftObservation] {
        var out: [CutScorecardLiftObservation] = []
        var week = first
        while week <= last {
            out.append(lift(monday(base, week), pressName, 60.0))
            out.append(lift(monday(base, week), rowName, 50.0))
            week += 1
        }
        return out
    }

    /// Monday sessions of Fixture Press alone: `kg[i]` in fixture week `first + i`.
    static func press(_ base: Int, _ first: Int, _ kg: [Double]) -> [CutScorecardLiftObservation] {
        var out: [CutScorecardLiftObservation] = []
        for i in 0..<kg.count { out.append(lift(monday(base, first + i), pressName, kg[i])) }
        return out
    }

    /// A scenario of weekly Wednesday readings; `today` is the Wednesday of the last week plus `after` days.
    static func scenario(_ base: Int, weights: [Double?], waists: [Double?], lifts: [CutScorecardLiftObservation],
                         proteinDays: [CutScorecardProteinDay], phase: CutScorecardPhase?,
                         parameters: CutScorecardParameters, after: Int) -> CutScorecardInput {
        CutScorecardInput(weights: weekly(base, weights), waists: weekly(base, waists), lifts: lifts,
                          proteinDays: proteinDays, phase: phase, parameters: parameters,
                          today: key(weighIn(base, weights.count > 0 ? weights.count : 1) + after))
    }

    static func phase(_ start: Int, _ target: Double?, _ low: Double, _ high: Double) -> CutScorecardPhase {
        CutScorecardPhase(name: "Edge cut", startDay: key(start), targetWeightKg: target,
                          rateLowPercentPerWeek: low, rateHighPercentPerWeek: high)
    }

    static func edgeCases() -> [(String, CutScorecardInput)] {
        let base = fixtureMonday
        let fp = fixtureParameters
        let ph = fixturePhase(base)
        let wed = weighIn(base, 1)
        var out: [(String, CutScorecardInput)] = []
        func add(_ label: String, _ input: CutScorecardInput) { out.append((label, input)) }
        func only(_ weights: [CutScorecardReading], _ today: Int) -> CutScorecardInput {
            CutScorecardInput(weights: weights, waists: [], lifts: [], proteinDays: [], phase: ph,
                              parameters: fp, today: key(today))
        }

        // The tie order in "latest reading of the week", in both input orders.
        add("tie-later-day-a", only([reading(wed - 1, 98.9, 7), reading(wed + 1, 98.4, 7)], wed + 1))
        add("tie-later-day-b", only([reading(wed + 1, 98.4, 7), reading(wed - 1, 98.9, 7)], wed + 1))
        add("tie-same-day-instant-a", only([reading(wed, 100.0, 7), reading(wed, 99.0, 9)], wed))
        add("tie-same-day-instant-b", only([reading(wed, 99.0, 9), reading(wed, 100.0, 7)], wed))
        add("tie-same-instant-value-a", only([reading(wed, 100.0, 7), reading(wed, 99.5, 7)], wed))
        add("tie-same-instant-value-b", only([reading(wed, 99.5, 7), reading(wed, 100.0, 7)], wed))
        // `takenAt` beyond 32 bits: truncated to 32 bits the first would sort before the second.
        add("taken-at-beyond-32-bits",
            only([CutScorecardReading(day: key(wed), takenAt: 4_294_967_301, value: 99.0),
                  CutScorecardReading(day: key(wed), takenAt: 10, value: 100.0)], wed))
        add("taken-at-extremes",
            only([CutScorecardReading(day: key(wed), takenAt: Int.min, value: 99.0),
                  CutScorecardReading(day: key(wed), takenAt: Int.max, value: 100.0),
                  CutScorecardReading(day: key(wed), takenAt: -1, value: 101.0)], wed))

        // Day keys before 1970: the whole fixture moved to a Monday in 1968, so every `takenAt` is negative.
        let old = dayNumber(1968, 12, 30)
        let oldData = fixtureData(old)
        for week in [1, 3, 9, 11, 19, 22] {
            add("pre-1970-w" + pad(week, 2),
                cut(oldData, today: weighIn(old, week), phase: fixturePhase(old), parameters: fp))
        }

        // Exercise names that differ only by case or by a trailing space are different exercises.
        let names = [lift(wed - 9, "Squat", 100.0), lift(wed - 2, "squat", 100.0), lift(wed - 2, "Squat ", 100.0)]
        add("names-case-and-space", CutScorecardInput(weights: [reading(wed, 100.0, 7)], waists: [], lifts: names,
                                                      proteinDays: [], phase: ph, parameters: fp, today: key(wed)))
        // Canonically equivalent names: precomposed against decomposed. One exercise to a Swift `String`.
        let accents = [lift(wed - 9, "Caf\u{E9} Press", 100.0), lift(wed - 2, "Cafe\u{301} Press", 90.0),
                       lift(wed - 3, "Caf\u{E9} Press", 80.0)]
        add("names-canonical-equivalence",
            CutScorecardInput(weights: [reading(wed, 100.0, 7)], waists: [], lifts: accents, proteinDays: [],
                              phase: ph, parameters: fp, today: key(wed)))
        add("names-empty", CutScorecardInput(weights: [reading(wed, 100.0, 7)], waists: [],
                                             lifts: [lift(wed - 2, "", 100.0), lift(wed - 9, "", Double.nan)],
                                             proteinDays: [], phase: ph, parameters: fp, today: key(wed)))

        // The ends of the calendar (§18 R5, R11).
        let first = dayNumber(1, 1, 1)
        var wide = fp
        wide.rateWindowWeeks = Int.max
        wide.waistWindowWeeks = Int.max
        wide.liftDropConsecutiveWeeks = Int.max
        wide.slowLossConsecutiveWeeks = Int.max
        add("year-0001", CutScorecardInput(
            weights: [reading(first + 2, 100.0, 7), reading(first + 9, 99.5, 7)],
            waists: [reading(first + 2, 100.0, 7), reading(first + 9, 99.0, 7)],
            lifts: [lift(first, pressName, 60.0), lift(first + 7, pressName, 60.0)],
            proteinDays: [protein(first, 120.0), protein(first + 8, 120.0)],
            phase: phase(first, 94.0, 0.4, 1.2), parameters: fp, today: key(first + 9)))
        add("year-0001-widest-windows", CutScorecardInput(
            weights: [reading(first + 2, 100.0, 7), reading(first + 9, 99.5, 7)], waists: [], lifts: [],
            proteinDays: [], phase: phase(first, 94.0, 0.4, 1.2), parameters: wide, today: key(first + 9)))
        let last = dayNumber(9999, 12, 31)
        var far = fp
        far.maxProjectionWeeks = Int.max
        far.maxWeighInAgeWeeks = Int.max
        add("year-9999-projection-past-the-calendar", CutScorecardInput(
            weights: [reading(last - 11, 100.0, 7), reading(last - 4, 99.5, 7)], waists: [], lifts: [],
            proteinDays: [], phase: phase(last - 20, 94.0, 0.4, 1.2), parameters: far, today: key(last)))
        add("year-9999-projection-on-the-last-day", CutScorecardInput(
            weights: [reading(last - 11, 100.0, 7), reading(last - 4, 99.5, 7)], waists: [], lifts: [],
            proteinDays: [], phase: phase(last - 20, 99.3, 0.4, 1.2), parameters: far, today: key(last)))
        add("day-keys-outside-the-calendar", CutScorecardInput(
            weights: [CutScorecardReading(day: "0000-12-31", takenAt: 0, value: 100.0),
                      CutScorecardReading(day: "10000-01-01", takenAt: 0, value: 100.0),
                      CutScorecardReading(day: "2031-1-8", takenAt: 0, value: 100.0),
                      CutScorecardReading(day: "+2031-01-08", takenAt: 0, value: 100.0),
                      CutScorecardReading(day: "2031-02-29", takenAt: 0, value: 100.0),
                      CutScorecardReading(day: "2031-01-08 ", takenAt: 0, value: 100.0),
                      CutScorecardReading(day: "", takenAt: 0, value: 100.0),
                      CutScorecardReading(day: "\u{662}\u{660}\u{663}\u{661}-01-08", takenAt: 0, value: 100.0),
                      CutScorecardReading(day: "2032-02-29", takenAt: 0, value: 100.0)],
            waists: [], lifts: [], proteinDays: [], phase: nil, parameters: fp, today: "2032-03-01"))

        // A `ceil` on a value that is an integer but for floating-point error: 0.3 / 0.1 × 7.
        add("ceil-near-integer", scenario(base, weights: [80.3, 80.2], waists: [], lifts: [], proteinDays: [],
                                          phase: phase(base, 79.9, 0.0, 5.0), parameters: fp, after: 0))
        // 0.1 / 0.35 × 7 is 2.0000000000000004: two days once quantized, three if the raw product were rounded up.
        add("ceil-just-above-integer", scenario(base, weights: [80.35, 80.0], waists: [], lifts: [],
                                                proteinDays: [], phase: phase(base, 79.9, 0.0, 5.0),
                                                parameters: fp, after: 0))

        // §18 R3: the arithmetic limit.
        let over = Double(bitPattern: (1e100).bitPattern + 1)
        add("limit-accepted", only([reading(wed, 1e100, 7), reading(wed + 7, 1e100, 7)], wed + 7))
        add("limit-rejected", only([reading(wed, over, 7), reading(wed + 1, -over, 7), reading(wed + 2, -1e100, 7),
                                    reading(wed + 3, 100.0, 7)], wed + 3))
        add("limit-target", scenario(base, weights: [100.0, 99.0], waists: [], lifts: [], proteinDays: [],
                                     phase: phase(base, 1e100, 0.0, 1e100), parameters: fp, after: 0))
        add("limit-phase-bound-over", scenario(base, weights: [100.0, 99.0], waists: [], lifts: [], proteinDays: [],
                                               phase: phase(base, 94.0, 0.0, over), parameters: fp, after: 0))
        add("limit-phase-target-over", scenario(base, weights: [100.0, 99.0], waists: [], lifts: [], proteinDays: [],
                                                phase: phase(base, over, 0.0, 1.0), parameters: fp, after: 0))

        // §18 R4: a weekly loss that rounds to zero from below is positive zero.
        add("negative-zero-loss", scenario(base, weights: [80.0001, 80.0002, 80.0003], waists: [100.0, 100.0001, 100.0002],
                                           lifts: [], proteinDays: [], phase: phase(base, 79.0, 0.0, 5.0),
                                           parameters: fp, after: 0))

        // §18 R12: the order in which invalid input is reported, and one count per item.
        var bad = fp
        bad.rateWindowWeeks = 0
        let badPhase = CutScorecardPhase(name: "Edge cut", startDay: "2031-13-01", targetWeightKg: 94.0,
                                         rateLowPercentPerWeek: 0.4, rateHighPercentPerWeek: 1.2)
        add("invalid-parameters-phase-today", CutScorecardInput(weights: weekly(base, [100.0]), waists: [], lifts: [],
                                                                proteinDays: [], phase: badPhase, parameters: bad,
                                                                today: "today"))
        add("invalid-phase-today", CutScorecardInput(weights: weekly(base, [100.0]), waists: [], lifts: [],
                                                     proteinDays: [], phase: badPhase, parameters: fp, today: "today"))
        for today in ["today", "", "2031-1-8", "+2031-01-08", "2031-02-29", "2031-01-08T00:00", "20310108", "0000-01-01"] {
            add("invalid-today-" + today, CutScorecardInput(weights: weekly(base, [100.0]), waists: [], lifts: [],
                                                            proteinDays: [], phase: ph, parameters: fp, today: today))
        }
        add("one-count-per-item", CutScorecardInput(
            weights: [CutScorecardReading(day: "nonsense", takenAt: 0, value: Double.nan),
                      CutScorecardReading(day: "nonsense", takenAt: 0, value: -1.0),
                      CutScorecardReading(day: "nonsense", takenAt: 0, value: 100.0),
                      CutScorecardReading(day: key(wed + 30), takenAt: 0, value: -Double.infinity),
                      CutScorecardReading(day: key(wed + 30), takenAt: 0, value: 0.0),
                      CutScorecardReading(day: key(wed + 30), takenAt: 0, value: 100.0),
                      reading(wed, 100.0, 7)],
            waists: [CutScorecardReading(day: key(wed + 1), takenAt: 0, value: 100.0),
                     CutScorecardReading(day: key(wed), takenAt: 0, value: Double.infinity)],
            lifts: [lift(wed + 1, pressName, 60.0), lift(wed - 2, pressName, 0.0), lift(wed - 2, "", -1.0),
                    lift(wed - 2, "", 60.0)],
            proteinDays: [protein(wed - 1, -0.0), protein(wed - 2, 0.0), protein(wed - 3, -1.0),
                          protein(wed + 1, 100.0), protein(wed - 4, Double.nan),
                          CutScorecardProteinDay(day: "2031-01-32", grams: 100.0)],
            phase: ph, parameters: fp, today: key(wed)))

        // §6.5 and §18 R13: every invalid parameter, one at a time.
        for kind in 0..<30 {
            var p = fp
            switch kind {
            case 0: p.rateWindowWeeks = 0
            case 1: p.waistWindowWeeks = 0
            case 2: p.liftDropConsecutiveWeeks = 0
            case 3: p.slowLossConsecutiveWeeks = -3
            case 4: p.maxWeighInAgeWeeks = -1
            case 5: p.maxProjectionWeeks = 0
            case 6: p.liftDropTolerancePercent = 100
            case 7: p.liftDropTolerancePercent = -0.5
            case 8: p.liftDropShare = 0
            case 9: p.liftDropShare = 1.001
            case 10: p.waistMinDecreaseCm = -0.1
            case 11: p.slowLossThresholdKgPerWeek = -0.25
            case 12: p.targetToleranceKg = -1
            case 13: p.addCaloriesKcal = -1
            case 14: p.reduceCarbsKcal = Int.min
            case 15: p.proteinMinDaysPerWeek = 0
            case 16: p.proteinMinDaysPerWeek = 8
            case 17: p.proteinFloorGrams = 0
            case 18: p.proteinFloorGrams = -5
            case 19: p.proteinFloorGrams = Double.nan
            case 20: p.proteinFloorGrams = Double.infinity
            case 21: p.proteinFloorGrams = over
            case 22: p.waistMinDecreaseCm = Double.nan
            case 23: p.liftDropTolerancePercent = Double.infinity
            case 24: p.liftDropShare = Double.nan
            case 25: p.slowLossThresholdKgPerWeek = over
            case 26: p.targetToleranceKg = Double.infinity
            case 27: p.waistMinDecreaseCm = over
            case 28: p.rateWindowWeeks = Int.min; p.liftDropConsecutiveWeeks = Int.max; p.proteinMinDaysPerWeek = Int.max
            default: p.targetToleranceKg = over
            }
            add("invalid-parameter-" + pad(kind, 2),
                scenario(base, weights: [100.0, 99.2], waists: [100.0, 99.0], lifts: holding(base, -1, 2),
                         proteinDays: [], phase: ph, parameters: p, after: 0))
        }
        // Valid at the edge of validity.
        for kind in 0..<6 {
            var p = fp
            switch kind {
            case 0: p.liftDropTolerancePercent = 0
            case 1: p.liftDropShare = 1
            case 2: p.maxWeighInAgeWeeks = 0
            case 3: p.proteinFloorGrams = 1e100; p.targetToleranceKg = 1e100
            case 4: p.addCaloriesKcal = Int.max; p.reduceCarbsKcal = Int.max; p.liftDropConsecutiveWeeks = 1
            default: p.proteinMinDaysPerWeek = 1; p.waistMinDecreaseCm = 1e100; p.slowLossThresholdKgPerWeek = 1e100
            }
            add("valid-parameter-edge-" + String(kind),
                scenario(base, weights: [100.0, 99.2, 99.1, 99.0, 98.9], waists: [100.0, 99.0, 98.0, 97.0, 96.0],
                         lifts: press(base, -1, [60.0, 60.0, 60.0, 55.0, 50.0, 45.0, 40.0]),
                         proteinDays: [protein(weighIn(base, 5) - 1, 120.0)], phase: ph, parameters: p, after: 0))
        }

        // §6.5: every way a phase is invalid.
        for kind in 0..<10 {
            var start = key(base)
            var target: Double? = 94.0
            var low = 0.4
            var high = 1.2
            switch kind {
            case 0: start = "2031-02-30"
            case 1: start = ""
            case 2: target = Double.nan
            case 3: target = 0
            case 4: target = -94
            case 5: target = Double.infinity
            case 6: low = Double.nan
            case 7: low = -0.1
            case 8: low = 1.3
            default: high = Double.infinity
            }
            add("invalid-phase-" + String(kind), CutScorecardInput(
                weights: weekly(base, [100.0, 99.2]), waists: [], lifts: [], proteinDays: [],
                phase: CutScorecardPhase(name: "Edge cut", startDay: start, targetWeightKg: target,
                                         rateLowPercentPerWeek: low, rateHighPercentPerWeek: high),
                parameters: fp, today: key(weighIn(base, 2))))
        }
        add("phase-band-equal-bounds", scenario(base, weights: [100.0, 99.2], waists: [], lifts: [], proteinDays: [],
                                                phase: phase(base, 94.0, 0.803, 0.803), parameters: fp, after: 0))
        add("phase-band-zero", scenario(base, weights: [100.0, 99.2], waists: [], lifts: [], proteinDays: [],
                                        phase: phase(base, 94.0, 0, 0), parameters: fp, after: 0))

        // §18 R14: a waist minimum of zero makes an unchanged waist `met`.
        var flat = fp
        flat.waistMinDecreaseCm = 0
        add("waist-minimum-zero-flat", scenario(base, weights: [100.0, 99.2], waists: [100.0, 100.0],
                                                lifts: holding(base, -1, 2), proteinDays: [], phase: ph,
                                                parameters: flat, after: 0))
        add("waist-minimum-zero-growing", scenario(base, weights: [100.0, 99.2], waists: [100.0, 100.001],
                                                   lifts: holding(base, -1, 2), proteinDays: [], phase: ph,
                                                   parameters: flat, after: 0))
        add("waist-minimum-exact", scenario(base, weights: [100.0, 99.2], waists: [100.0, 99.5],
                                            lifts: holding(base, -1, 2), proteinDays: [], phase: ph,
                                            parameters: fp, after: 0))
        add("waist-minimum-one-thousandth-short", scenario(base, weights: [100.0, 99.2], waists: [100.0, 99.501],
                                                           lifts: holding(base, -1, 2), proteinDays: [], phase: ph,
                                                           parameters: fp, after: 0))
        add("waist-none-this-week", scenario(base, weights: [100.0, 99.2], waists: [100.0, nil],
                                             lifts: holding(base, -1, 2), proteinDays: [], phase: ph,
                                             parameters: fp, after: 0))
        add("waist-outside-window", scenario(base, weights: [100.0, 99.2, 98.4, 97.6, 96.8],
                                             waists: [100.0, nil, nil, nil, 98.0], lifts: holding(base, -1, 5),
                                             proteinDays: [], phase: ph, parameters: fp, after: 0))

        // §18 R10: the lift share, the lift tolerance, the band and the horizon compare quantized values.
        var third = fp
        third.liftDropShare = 0.333
        let threeLifts = [lift(wed - 9, "A", 100.0), lift(wed - 9, "B", 100.0), lift(wed - 9, "C", 100.0),
                          lift(wed - 2, "A", 90.0), lift(wed - 2, "B", 100.0), lift(wed - 2, "C", 105.0)]
        add("lift-share-one-third-meets-0.333", CutScorecardInput(
            weights: [reading(wed, 100.0, 7)], waists: [], lifts: threeLifts, proteinDays: [], phase: ph,
            parameters: third, today: key(wed)))
        // One third against 0.3334: met only because both sides are quantized to 0.333.
        third.liftDropShare = 0.3334
        add("lift-share-one-third-meets-0.3334", CutScorecardInput(
            weights: [reading(wed, 100.0, 7)], waists: [], lifts: threeLifts, proteinDays: [], phase: ph,
            parameters: third, today: key(wed)))
        third.liftDropShare = 0.334
        add("lift-share-one-third-misses-0.334", CutScorecardInput(
            weights: [reading(wed, 100.0, 7)], waists: [], lifts: threeLifts, proteinDays: [], phase: ph,
            parameters: third, today: key(wed)))
        add("lift-tolerance-exact", CutScorecardInput(
            weights: [reading(wed, 100.0, 7)], waists: [],
            lifts: [lift(wed - 9, "A", 100.0), lift(wed - 2, "A", 95.0)], proteinDays: [], phase: ph,
            parameters: fp, today: key(wed)))
        add("lift-tolerance-one-thousandth-under", CutScorecardInput(
            weights: [reading(wed, 100.0, 7)], waists: [],
            lifts: [lift(wed - 9, "A", 100.0), lift(wed - 2, "A", 94.999)], proteinDays: [], phase: ph,
            parameters: fp, today: key(wed)))
        add("lift-window-edges", CutScorecardInput(
            weights: [reading(wed, 100.0, 7)], waists: [],
            lifts: [lift(wed - 14, "A", 100.0), lift(wed - 15, "A", 500.0), lift(wed - 8, "A", 101.0),
                    lift(wed - 7, "A", 101.0), lift(wed - 1, "A", 90.0), lift(wed, "A", 500.0),
                    lift(wed - 7, "A", 99.0)],
            proteinDays: [], phase: ph, parameters: fp, today: key(wed)))
        add("lift-no-sessions-prior-week", CutScorecardInput(
            weights: [reading(wed, 100.0, 7)], waists: [], lifts: [lift(wed - 2, "A", 100.0)], proteinDays: [],
            phase: ph, parameters: fp, today: key(wed)))
        add("lift-no-sessions-this-week", CutScorecardInput(
            weights: [reading(wed, 100.0, 7)], waists: [], lifts: [lift(wed - 9, "A", 100.0)], proteinDays: [],
            phase: ph, parameters: fp, today: key(wed)))
        add("band-low-quantized-equal", scenario(base, weights: [100.0, 99.2], waists: [], lifts: [], proteinDays: [],
                                                 phase: phase(base, 94.0, 0.8034, 1.2), parameters: fp, after: 0))
        add("band-high-quantized-equal", scenario(base, weights: [100.0, 99.2], waists: [], lifts: [], proteinDays: [],
                                                  phase: phase(base, 94.0, 0.1, 0.8025), parameters: fp, after: 0))
        add("band-above", scenario(base, weights: [100.0, 99.2], waists: [], lifts: [], proteinDays: [],
                                   phase: phase(base, 94.0, 0.1, 0.802), parameters: fp, after: 0))
        var horizon = fp
        horizon.maxProjectionWeeks = 4
        add("horizon-exact", scenario(base, weights: [100.0, 99.5], waists: [], lifts: [], proteinDays: [],
                                      phase: phase(base, 97.5, 0.0, 5.0), parameters: horizon, after: 0))
        add("horizon-one-thousandth-over", scenario(base, weights: [100.0, 99.5], waists: [], lifts: [], proteinDays: [],
                                                    phase: phase(base, 97.4995, 0.0, 5.0), parameters: horizon, after: 0))
        // 10.001 / 2.5 is 4.0004: inside a four-week horizon only because the quotient is quantized.
        add("horizon-quantized-equal", scenario(base, weights: [102.501, 100.001], waists: [], lifts: [], proteinDays: [],
                                                phase: phase(base, 90.0, 0.0, 5.0), parameters: horizon, after: 0))
        var tolerance = fp
        tolerance.targetToleranceKg = 0.5
        add("target-tolerance-exact", scenario(base, weights: [100.0, 99.5], waists: [], lifts: [], proteinDays: [],
                                               phase: phase(base, 99.0, 0.0, 5.0), parameters: tolerance, after: 0))
        add("target-tolerance-one-thousandth-over", scenario(base, weights: [100.0, 99.5], waists: [], lifts: [],
                                                             proteinDays: [], phase: phase(base, 98.999, 0.0, 5.0),
                                                             parameters: tolerance, after: 0))

        // §18 R1: a run longer than its window is counted in full.
        let slow: [Double?] = [100.0, 99.9, 99.8, 99.7, 99.6, 99.5, 99.4, 99.3, 99.2]
        add("long-slow-run", scenario(base, weights: slow, waists: [], lifts: holding(base, -1, 9), proteinDays: [],
                                      phase: ph, parameters: fp, after: 0))
        add("long-drop-run", scenario(base, weights: slow, waists: [],
                                      lifts: press(base, -1, [100.0, 100.0, 90.0, 80.0, 70.0, 60.0, 50.0, 40.0, 30.0, 20.0, 10.0]),
                                      proteinDays: [], phase: ph, parameters: fp, after: 0))
        add("slow-loss-at-threshold", scenario(base, weights: [100.0, 99.6, 99.2, 98.8], waists: [],
                                               lifts: holding(base, -1, 4), proteinDays: [], phase: ph,
                                               parameters: fp, after: 0))
        add("slow-loss-one-thousandth-under", scenario(base, weights: [100.0, 99.601, 99.202, 98.803], waists: [],
                                                       lifts: holding(base, -1, 4), proteinDays: [], phase: ph,
                                                       parameters: fp, after: 0))

        // §7.7, the lines the fixture does not reach.
        add("verdict-rule-2-alone", scenario(base, weights: [100.0, 99.2, 98.4, 97.6], waists: [],
                                             lifts: press(base, -1, [100.0, 100.0, 90.0, 80.0, 70.0, 60.0]),
                                             proteinDays: [], phase: ph, parameters: fp, after: 0))
        add("verdict-withheld-naming-rule-1-only", scenario(base, weights: [100.0, 99.9, 99.8, 99.7], waists: [],
                                                            lifts: holding(base, -1, 4), proteinDays: [], phase: ph,
                                                            parameters: fp, after: 0))
        add("verdict-reduce-with-flat-waist", scenario(base, weights: [100.0, 99.9, 99.8, 99.7],
                                                       waists: [100.0, 100.0, 100.0, 100.0], lifts: [],
                                                       proteinDays: [], phase: ph, parameters: fp, after: 0))
        add("verdict-rule-2-missed-weigh-in", scenario(base, weights: [100.0, nil, 98.4, 97.6], waists: [],
                                                       lifts: press(base, -1, [100.0, 100.0, 90.0, 80.0, 70.0, 60.0]),
                                                       proteinDays: [], phase: ph, parameters: fp, after: 0))

        // §7.2 and §18 R6 to R9: the preconditions.
        add("no-phase-overdue", scenario(base, weights: [100.0, 99.2], waists: [100.0, 99.0],
                                         lifts: holding(base, -1, 2), proteinDays: [], phase: nil, parameters: fp,
                                         after: 14))
        add("no-phase-no-readings", CutScorecardInput(weights: [], waists: [reading(wed, 100.0, 7)], lifts: [],
                                                      proteinDays: [], phase: nil, parameters: fp, today: key(wed)))
        add("phase-not-started", scenario(base, weights: [100.0, 99.2, 98.4], waists: [100.0, 99.0, 98.0],
                                          lifts: holding(base, -1, 3), proteinDays: [],
                                          phase: phase(weighIn(base, 3) + 1, 94.0, 0.4, 1.2), parameters: fp, after: 0))
        add("phase-not-started-overdue", scenario(base, weights: [100.0, 99.2, 98.4], waists: [], lifts: [],
                                                  proteinDays: [], phase: phase(weighIn(base, 3) + 40, 94.0, 0.4, 1.2),
                                                  parameters: fp, after: 21))
        add("phase-starts-today", scenario(base, weights: [100.0, 99.2, 98.4], waists: [], lifts: [], proteinDays: [],
                                           phase: phase(weighIn(base, 3), 94.0, 0.4, 1.2), parameters: fp, after: 0))
        add("phase-without-in-phase-weigh-in", scenario(base, weights: [100.0, 99.2], waists: [100.0, 99.0], lifts: [],
                                                        proteinDays: [], phase: phase(monday(base, 3), 94.0, 0.4, 1.2),
                                                        parameters: fp, after: 6))
        add("phase-without-in-phase-weigh-in-or-target",
            scenario(base, weights: [100.0, 99.2], waists: [], lifts: [], proteinDays: [],
                     phase: phase(monday(base, 3), nil, 0.4, 1.2), parameters: fp, after: 6))
        add("overdue-with-target", scenario(base, weights: [100.0, 99.2], waists: [], lifts: [], proteinDays: [],
                                            phase: ph, parameters: fp, after: 14))
        add("overdue-without-target", scenario(base, weights: [100.0, 99.2], waists: [], lifts: [], proteinDays: [],
                                               phase: phase(base, nil, 0.4, 1.2), parameters: fp, after: 14))
        var strict = fp
        strict.maxWeighInAgeWeeks = 0
        add("age-zero-same-week", scenario(base, weights: [100.0, 99.2], waists: [], lifts: [], proteinDays: [],
                                           phase: ph, parameters: strict, after: 4))
        add("age-zero-next-week", scenario(base, weights: [100.0, 99.2], waists: [], lifts: [], proteinDays: [],
                                           phase: ph, parameters: strict, after: 5))
        var patient = fp
        patient.maxWeighInAgeWeeks = 60
        add("needs-new-weigh-in", scenario(base, weights: [100.0, 99.0], waists: [], lifts: [], proteinDays: [],
                                           phase: phase(base, 98.0, 0.0, 5.0), parameters: patient, after: 40))
        add("projected-on-today", scenario(base, weights: [100.0, 99.0], waists: [], lifts: [], proteinDays: [],
                                           phase: phase(base, 98.0, 0.0, 5.0), parameters: patient, after: 7))
        add("phase-starts-mid-week", scenario(base, weights: [100.0, 99.2, 98.4], waists: [100.0, 99.0, 98.0],
                                              lifts: holding(base, -1, 3), proteinDays: [],
                                              phase: phase(weighIn(base, 2) + 2, 94.0, 0.4, 1.2), parameters: fp,
                                              after: 0))

        // §7.4: the rate window.
        add("rate-gap-inside-window", scenario(base, weights: [100.0, nil, 99.0, 98.5], waists: [], lifts: [],
                                               proteinDays: [], phase: ph, parameters: fp, after: 0))
        var narrow = fp
        narrow.rateWindowWeeks = 2
        add("rate-gap-longer-than-window", scenario(base, weights: [100.0, nil, nil, nil, 99.0], waists: [], lifts: [],
                                                    proteinDays: [], phase: ph, parameters: narrow, after: 0))
        add("rate-window-clips", scenario(base, weights: [100.0, 90.0, 89.0, 88.0], waists: [], lifts: [],
                                          proteinDays: [], phase: ph, parameters: narrow, after: 0))
        add("rate-gaining", scenario(base, weights: [100.0, 100.5, 101.0], waists: [], lifts: [], proteinDays: [],
                                     phase: ph, parameters: fp, after: 0))

        // §7.5 item 3: protein.
        let anchor = weighIn(base, 2)
        var floorDays: [CutScorecardProteinDay] = []
        for k in 1...7 { floorDays.append(protein(anchor - k, k <= 5 ? 99.9995 : 99.9994)) }
        add("protein-floor-quantized", scenario(base, weights: [100.0, 99.2], waists: [], lifts: [],
                                                proteinDays: floorDays, phase: ph, parameters: fp, after: 0))
        add("protein-later-entry-wins", scenario(base, weights: [100.0, 99.2], waists: [], lifts: [],
                                                 proteinDays: [protein(anchor - 1, 50.0), protein(anchor - 1, 150.0),
                                                               protein(anchor - 2, 150.0), protein(anchor - 2, 50.0),
                                                               protein(anchor, 150.0), protein(anchor - 8, 150.0)],
                                                 phase: ph, parameters: fp, after: 0))
        add("protein-zero-days", scenario(base, weights: [100.0, 99.2], waists: [], lifts: [],
                                          proteinDays: [protein(anchor - 1, 0.0), protein(anchor - 2, -0.0),
                                                        protein(anchor - 3, 0.0)],
                                          phase: ph, parameters: fp, after: 0))
        var noFloor = fp
        noFloor.proteinFloorGrams = nil
        add("protein-no-floor", scenario(base, weights: [100.0, 99.2], waists: [], lifts: [],
                                         proteinDays: [protein(anchor - 1, 150.0)], phase: ph, parameters: noFloor,
                                         after: 0))
        return out
    }

    // MARK: Generated spread

    static let exercisePool = ["Squat", "squat", "Squat ", "Bench", "Row", "Caf\u{E9}", "Cafe\u{301}"]

    /// One generated input. Every draw is taken in a fixed order, one statement per draw.
    static func generated(_ rng: inout LCG) -> CutScorecardInput {
        let bases = [dayNumber(2031, 1, 6), dayNumber(1968, 12, 30), dayNumber(2024, 2, 26), dayNumber(1999, 12, 27)]
        let base = bases[rng.below(4)]
        let weekCount = 1 + rng.below(14)

        // Parameters.
        let rateWindow = 1 + rng.below(6)
        let waistWindow = 1 + rng.below(5)
        let waistMinimum = [0, 0.1, 0.5, 1.0][rng.below(4)]
        let liftTolerance = [0, 2.5, 5, 10][rng.below(4)]
        let liftShare = [0.25, 0.333, 0.5, 1.0][rng.below(4)]
        let liftWeeks = 1 + rng.below(4)
        let addKcal = [0, 100, 300][rng.below(3)]
        let slowThreshold = [0, 0.25, 0.4, 0.5][rng.below(4)]
        let slowWeeks = 1 + rng.below(4)
        let reduceKcal = [0, 100, 250][rng.below(3)]
        let floorChoice = rng.below(4)
        let proteinDaysRequired = 1 + rng.below(7)
        let maxAge = [0, 1, 1, 2, 3, 60][rng.below(6)]
        let maxProjection = [1, 4, 52, 104, 100_000][rng.below(5)]
        let targetTolerance = [0, 0, 0.1, 0.5][rng.below(4)]
        var parameters = CutScorecardParameters(
            rateWindowWeeks: rateWindow, waistWindowWeeks: waistWindow, waistMinDecreaseCm: waistMinimum,
            liftDropTolerancePercent: liftTolerance, liftDropShare: liftShare, liftDropConsecutiveWeeks: liftWeeks,
            addCaloriesKcal: addKcal, slowLossThresholdKgPerWeek: slowThreshold, slowLossConsecutiveWeeks: slowWeeks,
            reduceCarbsKcal: reduceKcal,
            proteinFloorGrams: floorChoice == 0 ? nil : [100, 120.5, 80][floorChoice - 1],
            proteinMinDaysPerWeek: proteinDaysRequired, maxWeighInAgeWeeks: maxAge,
            maxProjectionWeeks: maxProjection, targetToleranceKg: targetTolerance)
        if rng.chance(25) {
            switch rng.below(8) {
            case 0: parameters.rateWindowWeeks = 0
            case 1: parameters.waistWindowWeeks = -1
            case 2: parameters.liftDropConsecutiveWeeks = 0
            case 3: parameters.maxProjectionWeeks = 0
            case 4: parameters.liftDropTolerancePercent = 100
            case 5: parameters.liftDropShare = 0
            case 6: parameters.proteinMinDaysPerWeek = 8
            default: parameters.targetToleranceKg = Double.nan
            }
        }

        // Weights and waists.
        var weights: [CutScorecardReading] = []
        var waists: [CutScorecardReading] = []
        let startGrams = 60_000 + rng.below(60_001)
        var grams = startGrams
        var waistMillimetres = 800 + rng.below(400)
        let weightMode = rng.below(5)
        var lastWeighDay = base
        for w in 0..<weekCount {
            var step = 0
            switch weightMode {
            case 0: step = 300 + rng.below(700)
            case 1: step = rng.below(300)
            case 2: step = 0 - rng.below(400)
            case 3: step = rng.below(1_600) - 800
            default: step = [250, 249, 251, 400, 0, 500][rng.below(6)]
            }
            if w > 0 { grams -= step }
            let missedDraw = rng.chance(6)
            let missed = w > 0 && missedDraw
            let weekday = rng.below(7)
            let day = base + 7 * w + weekday
            if !missed {
                weights.append(reading(day, Double(grams) / 1000.0, 7))
                lastWeighDay = day
                if rng.chance(8) {
                    let kind = rng.below(3)
                    let other = Double(grams + 100 + rng.below(900)) / 1000.0
                    if kind == 0 {
                        weights.append(reading(base + 7 * w + rng.below(7), other, 7))
                    } else if kind == 1 {
                        weights.append(reading(day, other, 6 + 2 * rng.below(2)))
                    } else {
                        weights.append(reading(day, other, 7))
                    }
                }
            }
            let waistStep = [10, 5, 1, 0, -5, 4][rng.below(6)]
            if w > 0 { waistMillimetres -= waistStep }
            if rng.below(4) != 0 { waists.append(reading(day, Double(waistMillimetres) / 10.0, 7)) }
        }

        // Lifts: sessions from two weeks before the first weigh-in week.
        var lifts: [CutScorecardLiftObservation] = []
        let liftMode = rng.below(6)
        let exerciseCount = 1 + rng.below(4)
        let poolStart = rng.below(7)
        var halfKilograms: [Int] = []
        for _ in 0..<exerciseCount { halfKilograms.append(40 + rng.below(200)) }
        if liftMode != 0 {
            for w in 0..<(weekCount + 2) {
                let day = base + 7 * w - 14 + rng.below(7)
                let skipped = liftMode == 5 && rng.chance(2)
                for k in 0..<exerciseCount {
                    switch liftMode {
                    case 1: break
                    case 2: halfKilograms[k] -= 2 + rng.below(8)
                    case 3: halfKilograms[k] += rng.below(5)
                    default: halfKilograms[k] += rng.below(11) - 5
                    }
                    if halfKilograms[k] < 1 { halfKilograms[k] = 1 }
                    if !skipped {
                        lifts.append(lift(day, exercisePool[(poolStart + k) % 7], Double(halfKilograms[k]) / 2.0))
                    }
                }
            }
        }

        // Protein: the days from a week before the first weigh-in week to the end of the last.
        var proteinDays: [CutScorecardProteinDay] = []
        let proteinMode = rng.below(4)
        if proteinMode != 0 {
            for i in 0..<(7 * weekCount + 7) {
                let day = base - 7 + i
                let logged = proteinMode == 1 || rng.below(3) != 0
                let halfGrams = 120 + rng.below(180)
                if logged { proteinDays.append(protein(day, Double(halfGrams) / 2.0)) }
                if proteinMode == 3 && rng.chance(5) {
                    proteinDays.append(protein(day, Double(120 + rng.below(180)) / 2.0))
                }
            }
        }

        // Phase.
        var phase: CutScorecardPhase?
        let phaseDraw = rng.below(8)
        let startWeek = rng.below(weekCount + 3)
        let startMidWeek = rng.chance(3)
        let startWeekday = rng.below(7)
        let targetDraw = rng.below(5)
        let targetGrams = startGrams - 12_000 + rng.below(14_000)
        let low = [0, 0.25, 0.4, 0.5][rng.below(4)]
        let high = [0.5, 1.0, 1.2, 0.4][rng.below(4)]
        if phaseDraw != 0 {
            phase = CutScorecardPhase(name: "Generated cut",
                                      startDay: key(base + 7 * startWeek - 14 + (startMidWeek ? startWeekday : 0)),
                                      targetWeightKg: targetDraw == 0 ? nil : Double(targetGrams) / 1000.0,
                                      rateLowPercentPerWeek: low, rateHighPercentPerWeek: high)
        }

        // Today.
        var today = lastWeighDay
        let todayDraw = rng.below(10)
        let todayOffset = rng.below(126)
        if todayDraw == 5 || todayDraw == 6 {
            today = lastWeighDay + todayOffset % 7
        } else if todayDraw == 7 {
            today = lastWeighDay + 7 + todayOffset % 21
        } else if todayDraw == 8 {
            today = base + todayOffset % (7 * weekCount)
        } else if todayDraw == 9 {
            today = lastWeighDay + todayOffset
        }
        var todayKey = key(today)
        if rng.chance(40) { todayKey = "2031-02-30" }

        // Items that must be dropped and counted.
        if rng.chance(5) {
            let junkCount = 1 + rng.below(4)
            for _ in 0..<junkCount {
                let day = base + rng.below(7 * weekCount)
                switch rng.below(10) {
                case 0: weights.append(reading(day, Double.nan, 7))
                case 1: weights.append(reading(day, Double.infinity, 7))
                case 2: weights.append(reading(day, -70.5, 7))
                case 3: weights.append(reading(day, 0.0, 7))
                case 4: weights.append(reading(day, 1e101, 7))
                case 5: weights.append(CutScorecardReading(day: "2031-1-8", takenAt: 0, value: 70.5))
                case 6: waists.append(reading(day, -Double.infinity, 7))
                case 7: lifts.append(lift(day, "", 50.0))
                case 8: proteinDays.append(protein(day, -1.0))
                default: weights.append(reading(today + 1 + rng.below(30), 70.5, 7))
                }
            }
        }

        // The result does not depend on input order (protein: the later of two entries on a day wins).
        var i = weights.count - 1
        while i > 0 { weights.swapAt(i, rng.below(i + 1)); i -= 1 }
        i = waists.count - 1
        while i > 0 { waists.swapAt(i, rng.below(i + 1)); i -= 1 }
        i = lifts.count - 1
        while i > 0 { lifts.swapAt(i, rng.below(i + 1)); i -= 1 }
        i = proteinDays.count - 1
        while i > 0 { proteinDays.swapAt(i, rng.below(i + 1)); i -= 1 }

        return CutScorecardInput(weights: weights, waists: waists, lifts: lifts, proteinDays: proteinDays,
                                 phase: phase, parameters: parameters, today: todayKey)
    }

    // MARK: Every case, in order

    static func cases() -> [(String, CutScorecardInput)] {
        var out: [(String, CutScorecardInput)] = []
        for week in 1...fixtureWeekCount { out.append(("fixture-w" + pad(week, 2), fixtureInput(week: week))) }
        out.append(contentsOf: fixtureVariants())
        out.append(contentsOf: edgeCases())
        var rng = LCG(seed: seed)
        for index in 0..<generatedCount { out.append(("generated-" + pad(index, 4), generated(&rng))) }
        return out
    }

    /// `quantize` on exact halves, on negatives, on zero of either sign and on the unrepresentable.
    static func quantizeLines() -> [String] {
        var values: [Double] = [0.0, -0.0, 0.0005, -0.0005, 0.0015, -0.0015, 0.0025, -0.0025, 0.0004, -0.0004,
                                0.00049999, -0.00049999, 1.0005, -1.0005, 1.005, -1.005, 2.5, -2.5, 4.35, 0.1 + 0.2,
                                0.8034, 0.8025, 99.9995, 99.9994, 1e100, -1e100, 1e305, 1.7e308, -1.7e308,
                                Double.greatestFiniteMagnitude, Double.leastNonzeroMagnitude,
                                -Double.leastNonzeroMagnitude, Double.infinity, -Double.infinity, Double.nan,
                                4_503_599_627_370_496.5, 9_007_199_254_740_992.0, 1e15, 123_456_789.0005]
        var rng = LCG(seed: seed + 1)
        for _ in 0..<200 {
            // An odd count of half-thousandths: an exact half in the third decimal, as nearly as a Double holds it.
            let halves = 2 * rng.below(200_000) + 1
            let negative = rng.chance(2)
            let value = Double(halves) / 2000.0
            values.append(negative ? -value : value)
        }
        var out: [String] = []
        for value in values {
            let result = CutScorecard.quantize(value)
            out.append("quantize|" + bitsHex(value) + "|" + bitsHex(result) + "|" + f(result))
        }
        return out
    }

    /// `weekStart(containing:)` across valid and invalid keys.
    static func weekStartLines() -> [String] {
        var keys = ["2031-01-08", "2031-01-06", "2031-01-12", "2031-1-8", "+2031-01-08", "0001-01-01", "0001-01-07",
                    "0000-12-31", "9999-12-31", "10000-01-01", "2031-02-29", "2032-02-29", "1900-02-29",
                    "2000-02-29", "1969-12-31", "1970-01-01", "", "2031-01-08 ", " 2031-01-08", "2031/01/08",
                    "2031-13-01", "2031-00-10", "2031-01-00", "2031-01-32", "-031-01-08", "0031-01-08",
                    "2031-01-08-01", "20310108", "\u{662}\u{660}\u{663}\u{661}-01-08", "2031-01-0\u{663}"]
        var rng = LCG(seed: seed + 2)
        for _ in 0..<60 { keys.append(key(dayNumber(1, 1, 1) + rng.below(3_652_059))) }
        var out: [String] = []
        for k in keys { out.append("weekStart|" + k + "|" + so(CutScorecard.weekStart(containing: k))) }
        return out
    }

    /// The formatter itself: ties, signed zero and large magnitudes, so "%.6f" is pinned on both sides.
    static func formatLines() -> [String] {
        let values: [Double] = [0.0078125, 0.0234375, -0.0078125, -0.0, -1e-9, 1e-9, 0.1 + 0.2, 2.5e-7, 1e21,
                                123_456_789.123456789, 0.0000005, 0.0000015, 2.9999999999999996, 1e100]
        var out: [String] = []
        for value in values { out.append("format|" + bitsHex(value) + "|" + f(value)) }
        return out
    }

    /// The whole oracle: one line per case.
    static func allLines() -> [String] {
        var out = formatLines()
        out.append(contentsOf: quantizeLines())
        out.append(contentsOf: weekStartLines())
        for (label, input) in cases() { out.append(line(label, input)) }
        return out
    }
}
// ORACLE-SHARED-END

final class CutScorecardOracleTests: XCTestCase {

    /// The committed expected literal, shared with the Kotlin twin's `CutScorecardParityOracleTest`.
    private static let relativePath = "android/app/src/test/resources/cut_scorecard_oracle.txt"

    private func expectedLines() throws -> [String] {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<12 {
            let candidate = directory.appendingPathComponent(Self.relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                let text = try String(contentsOf: candidate, encoding: .utf8)
                var lines = text.components(separatedBy: "\n")
                if lines.last == "" { lines.removeLast() }
                return lines
            }
            directory.deleteLastPathComponent()
        }
        XCTFail("committed oracle \(Self.relativePath) not found above \(#filePath)")
        return []
    }

    /// Swift against the committed literal: a change to `CutScorecard.swift` that moves any field of any
    /// case fails here. Regenerate with `Tools/personal/cut_scorecard_oracle.sh --write` only together
    /// with the matching change to the Kotlin twin.
    func testSwiftOutputMatchesTheCommittedOracle() throws {
        let expected = try expectedLines()
        let actual = CutScorecardOracle.allLines()
        XCTAssertEqual(actual.count, expected.count, "line count")
        var reported = 0
        for index in 0..<min(actual.count, expected.count) where actual[index] != expected[index] {
            reported += 1
            if reported <= 5 {
                XCTFail("line \(index + 1) differs\n  expected: \(expected[index])\n  actual:   \(actual[index])")
            }
        }
        XCTAssertEqual(reported, 0, "lines that differ from the committed oracle")
    }

    /// The oracle's own copy of the §13 fixture is the fixture the other suites assert against.
    func testOracleFixtureIsTheSharedFixture() {
        for week in 1...CutScorecardOracle.fixtureWeekCount {
            XCTAssertEqual(CutScorecardOracle.fixtureInput(week: week), CutScorecardFixture.input(week: week),
                           "fixture week \(week)")
        }
    }

    func testGeneratedSpreadIsAtLeastFiveHundredCases() {
        XCTAssertGreaterThanOrEqual(CutScorecardOracle.generatedCount, 500)
        let labels = CutScorecardOracle.cases().map { $0.0 }
        XCTAssertEqual(Set(labels).count, labels.count, "case labels are unique")
    }

    /// The generator is deterministic: two runs give the same lines.
    func testOracleIsDeterministic() {
        XCTAssertEqual(CutScorecardOracle.allLines(), CutScorecardOracle.allLines())
    }

    /// Every outcome the result type can express is reached by at least one case, so the literal pins
    /// each of them on both platforms.
    func testCasesReachEveryOutcome() {
        var seen = Set<String>()
        for (_, input) in CutScorecardOracle.cases() {
            let r = CutScorecard.evaluate(input)
            seen.insert("projection." + r.projection.status.rawValue)
            seen.insert("rateUnavailable." + (r.rateUnavailable?.rawValue ?? "nil"))
            seen.insert("waist." + r.signals.waist.state.rawValue + "." + r.signals.waist.reason.rawValue)
            seen.insert("lifts." + r.signals.lifts.state.rawValue + "." + r.signals.lifts.reason.rawValue)
            seen.insert("protein." + r.signals.protein.state.rawValue + "." + r.signals.protein.reason.rawValue)
            seen.insert("rateBand." + r.signals.rateBand.state.rawValue + "." + r.signals.rateBand.reason.rawValue)
            for e in r.rules {
                seen.insert("rule." + e.rule.rawValue + "." + e.state.rawValue + "." + (e.unknownReason?.rawValue ?? "nil"))
            }
            let v = r.verdict
            seen.insert("verdict." + v.kind.rawValue + "." + v.reason.rawValue + "." + (v.rule?.rawValue ?? "nil")
                        + "." + CutScorecardOracle.rules(v.overriddenRules) + "." + CutScorecardOracle.rules(v.unevaluatedRules))
            seen.insert("invalid." + (r.invalidInput?.rawValue ?? "nil"))
            if r.rejections.nonFinite > 0 { seen.insert("rejections.nonFinite") }
            if r.rejections.nonPositive > 0 { seen.insert("rejections.nonPositive") }
            if r.rejections.invalidDay > 0 { seen.insert("rejections.invalidDay") }
            if r.rejections.future > 0 { seen.insert("rejections.future") }
            if r.weeks.contains(where: { $0.weightKg == nil }) { seen.insert("weeks.missed") }
        }
        let required = [
            // Every projection status.
            "projection.projected", "projection.noActivePhase", "projection.noTarget", "projection.targetReached",
            "projection.rateUnknown", "projection.notLosing", "projection.beyondHorizon",
            "projection.needsNewWeighIn", "projection.weighInOverdue",
            "rateUnavailable.nil", "rateUnavailable.noReadings", "rateUnavailable.singleReading",
            "rateUnavailable.gapLongerThanWindow", "rateUnavailable.weighInOverdue",
            "waist.met.shrinking", "waist.notMet.notShrinking", "waist.unknown.noWaistThisWeek",
            "waist.unknown.noEarlierWaist", "waist.unknown.weighInOverdue", "waist.unknown.noReadings",
            "lifts.met.holding", "lifts.notMet.dropping", "lifts.unknown.noLiftData",
            "lifts.unknown.noSessionsThisWeek", "lifts.unknown.noSessionsPriorWeek",
            "lifts.unknown.noCommonExercises", "lifts.unknown.weighInOverdue", "lifts.unknown.noReadings",
            "protein.met.floorMet", "protein.notMet.floorMissed", "protein.unknown.noFloorConfigured",
            "protein.unknown.noProteinData", "protein.unknown.incompleteLogging",
            "protein.unknown.weighInOverdue", "protein.unknown.noReadings",
            "rateBand.met.withinBand", "rateBand.notMet.belowBand", "rateBand.notMet.aboveBand",
            "rateBand.unknown.noActivePhase", "rateBand.unknown.rateUnknown", "rateBand.unknown.weighInOverdue",
            "rateBand.unknown.noReadings",
            "rule.liftsHoldingWaistShrinking.fired.nil", "rule.liftsHoldingWaistShrinking.notFired.nil",
            "rule.liftsHoldingWaistShrinking.unknown.liftSignalUnknown",
            "rule.liftsHoldingWaistShrinking.unknown.waistSignalUnknown",
            "rule.liftsDropping.fired.nil", "rule.liftsDropping.notFired.nil",
            "rule.liftsDropping.unknown.fewerWeeksThanWindow", "rule.liftsDropping.unknown.missedWeighIn",
            "rule.liftsDropping.unknown.liftSignalUnknown",
            "rule.slowLoss.fired.nil", "rule.slowLoss.notFired.nil",
            "rule.slowLoss.unknown.fewerWeeksThanWindow", "rule.slowLoss.unknown.missedWeighIn",
            "rule.slowLoss.unknown.noActivePhase", "rule.slowLoss.unknown.weighInOverdue",
            "rule.slowLoss.unknown.noReadings",
            // Every line of §7.7.
            "verdict.insufficientData.noReadings.nil.[].[]",
            "verdict.insufficientData.noActivePhase.nil.[].[]",
            "verdict.insufficientData.phaseNotStarted.nil.[].[]",
            "verdict.insufficientData.weighInOverdue.nil.[].[]",
            "verdict.insufficientData.invalidInput.nil.[].[]",
            "verdict.holdSteady.ruleFired.liftsHoldingWaistShrinking.[].[]",
            "verdict.holdSteady.ruleFired.liftsHoldingWaistShrinking.[slowLoss].[]",
            "verdict.addCalories.ruleFired.liftsDropping.[].[]",
            "verdict.addCalories.ruleFired.liftsDropping.[slowLoss].[]",
            "verdict.insufficientData.recompositionCheckIncomplete.nil.[].[liftsHoldingWaistShrinking]",
            "verdict.insufficientData.recompositionCheckIncomplete.nil.[].[liftsHoldingWaistShrinking+liftsDropping]",
            "verdict.reduceCarbs.ruleFired.slowLoss.[].[]",
            "verdict.reduceCarbs.ruleFired.slowLoss.[].[liftsDropping]",
            "verdict.insufficientData.noRuleEvaluable.nil.[].[liftsHoldingWaistShrinking+liftsDropping+slowLoss]",
            "verdict.holdSteady.noChangeRuleFired.nil.[].[]",
            "verdict.holdSteady.noChangeRuleFired.nil.[].[liftsHoldingWaistShrinking+slowLoss]",
            "verdict.holdSteady.noChangeRuleFired.nil.[].[liftsHoldingWaistShrinking+liftsDropping]",
            "invalid.nil", "invalid.parameters", "invalid.phase", "invalid.today",
            "rejections.nonFinite", "rejections.nonPositive", "rejections.invalidDay", "rejections.future",
            "weeks.missed",
        ]
        for outcome in required {
            XCTAssertTrue(seen.contains(outcome), "no oracle case reaches \(outcome)")
        }
    }
}
