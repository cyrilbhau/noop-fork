import Foundation

// Stage 3 of the personal fork: protein against the floor and energy against the range, as pure logic
// (`docs/personal/superapp/specs/stage-3.md` §6.5, §7.4, §7.5).
//
// Every comparison is made on `CutScorecard.quantize` values, the same quantization the scorecard's
// protein signal uses, so "the ring is complete" and "this day counted toward the scorecard" cannot
// disagree. Nothing here throws or traps on any input, and no output holds NaN or infinity.
//
// The package declares no rule about which floors may be stored. That rule is stage 1's (R45) and
// lives in the app's settings type; a floor here is whatever the caller read through it.

/// The owner's intake targets. Every field is optional: nil means "not set".
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public struct IntakeTargets: Equatable, Sendable {
    public var proteinFloorGrams: Double?
    public var energyLowKcal: Double?
    public var energyHighKcal: Double?
    public var energyHardFloorKcal: Double?

    public init(proteinFloorGrams: Double? = nil, energyLowKcal: Double? = nil,
                energyHighKcal: Double? = nil, energyHardFloorKcal: Double? = nil) {
        self.proteinFloorGrams = proteinFloorGrams
        self.energyLowKcal = energyLowKcal
        self.energyHighKcal = energyHighKcal
        self.energyHardFloorKcal = energyHardFloorKcal
    }

    /// False when any present value is not finite, not positive or above 1e100, when low > high,
    /// or when the hard floor is above the low end.
    public var isValid: Bool {
        for value in [proteinFloorGrams, energyLowKcal, energyHighKcal, energyHardFloorKcal] {
            guard let value = value else { continue }
            guard value.isFinite, value > 0, value <= IntakeAggregation.largestAmountMagnitude else {
                return false
            }
        }
        if let low = energyLowKcal, let high = energyHighKcal, low > high { return false }
        if let hardFloor = energyHardFloorKcal, let low = energyLowKcal, hardFloor > low { return false }
        return true
    }
}

/// Where a day's protein stands against the floor.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public enum IntakeProteinState: String, Sendable {
    case noFloor
    case notMeasured
    case below
    case atFloor
    case above
}

/// A day's protein against the floor, with the whole numbers a screen prints (§7.4).
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public struct IntakeProteinProgress: Equatable, Sendable {
    public let state: IntakeProteinState
    /// As given; nil when not measured.
    public let grams: Double?
    /// As given.
    public let floorGrams: Double?
    /// Whole grams to display.
    public let shownGrams: Int?
    public let shownFloorGrams: Int?
    /// Above zero only in `below`; 0 in `atFloor` and `above`.
    public let remainingGrams: Int?
    /// Above zero only in `above`.
    public let overGrams: Int?
    /// 0...1; nil in `noFloor` and `notMeasured`.
    public let ringFraction: Double?

    public init(state: IntakeProteinState, grams: Double?, floorGrams: Double?, shownGrams: Int?,
                shownFloorGrams: Int?, remainingGrams: Int?, overGrams: Int?, ringFraction: Double?) {
        self.state = state
        self.grams = grams
        self.floorGrams = floorGrams
        self.shownGrams = shownGrams
        self.shownFloorGrams = shownFloorGrams
        self.remainingGrams = remainingGrams
        self.overGrams = overGrams
        self.ringFraction = ringFraction
    }
}

/// Where a day's energy stands against the range.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public enum IntakeEnergyState: String, Sendable {
    case notMeasured
    case noRange
    case soFar
    case belowHardFloor
    case belowRange
    case inRange
    case aboveRange
}

/// A day's energy against the range, with the whole numbers a screen prints (§7.5).
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public struct IntakeEnergyProgress: Equatable, Sendable {
    public let state: IntakeEnergyState
    public let kcal: Double?
    public let shownKcal: Int?
    /// Above zero only when a low end exists and the amount is under it.
    public let toLowEndKcal: Int?
    /// Above zero only in `aboveRange`.
    public let overHighEndKcal: Int?

    public init(state: IntakeEnergyState, kcal: Double?, shownKcal: Int?, toLowEndKcal: Int?,
                overHighEndKcal: Int?) {
        self.state = state
        self.kcal = kcal
        self.shownKcal = shownKcal
        self.toLowEndKcal = toLowEndKcal
        self.overHighEndKcal = overHighEndKcal
    }
}

/// Protein against the floor and energy against the range.
///
/// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
public enum IntakeProgress {

    /// The one "is the floor met" predicate (§7.4): the comparison the scorecard's protein signal
    /// makes, on quantized values. A value that is not a number meets nothing and is met by nothing.
    ///
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static func meetsFloor(grams: Double, floorGrams: Double) -> Bool {
        CutScorecard.quantize(grams) >= CutScorecard.quantize(floorGrams)
    }

    /// A day's protein against the floor (§7.4).
    ///
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static func protein(grams: Double?, floorGrams: Double?) -> IntakeProteinProgress {
        // An amount that is nil, not finite or negative is not a measurement.
        let measured = grams.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        // A floor that is nil, not finite or not positive is not a floor.
        let usableFloor = floorGrams.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        // SPEC-NOTE: §6.5 says `floorGrams` is reported "as given". A floor that is NaN or infinite is
        // reported as nil instead, because no output of this stage may hold NaN or infinity. A finite
        // floor, usable or not, is reported as given.
        let reportedFloor = floorGrams.flatMap { $0.isFinite ? $0 : nil }

        let g = measured.map { CutScorecard.quantize($0) }
        let shownGrams = g.map { wholeNumber($0.rounded(.down)) }

        // SPEC-NOTE: §7.4 lists `noFloor` before `notMeasured` and does not say which wins with neither
        // a floor nor an amount. The listed order is followed: `noFloor`, with no number and no ring.
        // An unusable floor is never printed, so `shownFloorGrams` is nil. The remaining and over
        // figures are nil (not zero) in `noFloor` and `notMeasured`: there is nothing to be short of.
        guard let floor = usableFloor else {
            return IntakeProteinProgress(state: .noFloor, grams: measured, floorGrams: reportedFloor,
                                         shownGrams: shownGrams, shownFloorGrams: nil,
                                         remainingGrams: nil, overGrams: nil, ringFraction: nil)
        }
        let f = CutScorecard.quantize(floor)
        let shownFloorGrams = wholeNumber(f.rounded(.up))

        // SPEC-NOTE: §7.4 says `notMeasured` has "no number, no ring"; that is read as the amount. The
        // floor is known and usable, so `shownFloorGrams` is still set and a screen can print it.
        guard let g = g, let shownGrams = shownGrams else {
            return IntakeProteinProgress(state: .notMeasured, grams: nil, floorGrams: reportedFloor,
                                         shownGrams: nil, shownFloorGrams: shownFloorGrams,
                                         remainingGrams: nil, overGrams: nil, ringFraction: nil)
        }

        if g < f {
            // Grams round down and the floor rounds up, so at least one gram always remains here.
            // `f` is above `g`, which is at least zero, so the division is defined and under 1.
            return IntakeProteinProgress(state: .below, grams: measured, floorGrams: reportedFloor,
                                         shownGrams: shownGrams, shownFloorGrams: shownFloorGrams,
                                         remainingGrams: max(1, shownFloorGrams - shownGrams),
                                         overGrams: 0, ringFraction: g / f)
        }
        if shownGrams <= shownFloorGrams {
            return IntakeProteinProgress(state: .atFloor, grams: measured, floorGrams: reportedFloor,
                                         shownGrams: shownGrams, shownFloorGrams: shownFloorGrams,
                                         remainingGrams: 0, overGrams: 0, ringFraction: 1)
        }
        // The ring completes at the floor and stays complete: no second lap.
        return IntakeProteinProgress(state: .above, grams: measured, floorGrams: reportedFloor,
                                     shownGrams: shownGrams, shownFloorGrams: shownFloorGrams,
                                     remainingGrams: 0, overGrams: shownGrams - shownFloorGrams,
                                     ringFraction: 1)
    }

    /// A day's energy against the range (§7.5).
    /// `dayIsOpen`: more food may still be logged for this day.
    ///
    /// No Kotlin twin: iPhone-only by the owner's decision (stage 1 ruling R43).
    public static func energy(kcal: Double?, targets: IntakeTargets, dayIsOpen: Bool) -> IntakeEnergyProgress {
        // SPEC-NOTE: §7.5 names only nil as `notMeasured`. An amount that is not finite or is negative
        // is read the same way, as §7.4 does for protein: it is not a measurement and is never shown
        // as a number (the committed tests take this reading).
        guard let measured = kcal.flatMap({ $0.isFinite && $0 >= 0 ? $0 : nil }) else {
            return IntakeEnergyProgress(state: .notMeasured, kcal: nil, shownKcal: nil,
                                        toLowEndKcal: nil, overHighEndKcal: nil)
        }
        let k = CutScorecard.quantize(measured)
        let shownKcal = wholeNumber(k.rounded())

        // SPEC-NOTE: the detail figures are nil where no range applies (`notMeasured`, `noRange`) and
        // a number, zero when it does not apply, in every state judged against a range.
        guard targets.isValid, targets.energyLowKcal != nil || targets.energyHighKcal != nil else {
            return IntakeEnergyProgress(state: .noRange, kcal: measured, shownKcal: shownKcal,
                                        toLowEndKcal: nil, overHighEndKcal: nil)
        }
        let low = targets.energyLowKcal.map { CutScorecard.quantize($0) }
        let high = targets.energyHighKcal.map { CutScorecard.quantize($0) }
        let hardFloor = targets.energyHardFloorKcal.map { CutScorecard.quantize($0) }

        // Both distances round up, so neither is ever zero while its bound is still unmet.
        let toLowEnd = low.map { $0 > k ? wholeNumber(($0 - k).rounded(.up)) : 0 } ?? 0

        // Above the range is reported open or closed: more food cannot lower it.
        if let high = high, k > high {
            return IntakeEnergyProgress(state: .aboveRange, kcal: measured, shownKcal: shownKcal,
                                        toLowEndKcal: 0,
                                        overHighEndKcal: wholeNumber((k - high).rounded(.up)))
        }
        let state: IntakeEnergyState
        if dayIsOpen {
            // No judgement is made about a day still in progress.
            if let low = low, k < low { state = .soFar } else { state = .inRange }
        } else if let hardFloor = hardFloor, k < hardFloor {
            state = .belowHardFloor
        } else if let low = low, k < low {
            state = .belowRange
        } else {
            state = .inRange
        }
        return IntakeEnergyProgress(state: state, kcal: measured, shownKcal: shownKcal,
                                    toLowEndKcal: toLowEnd, overHighEndKcal: 0)
    }

    // MARK: - Private

    /// A non-negative double as an `Int`, truncated, saturating at `Int.max` instead of trapping.
    /// Saturation is only reachable beyond about 9.2e18, far past any real amount.
    private static func wholeNumber(_ value: Double) -> Int {
        guard value.isFinite, value > 0 else { return 0 }
        // `Double(Int.max)` rounds up to 2^63, the first value `Int(_:)` cannot hold.
        return value >= Double(Int.max) ? Int.max : Int(value)
    }
}
