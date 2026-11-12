import Foundation

// The body record: the comparison of two body-composition scans, the figures derived from one scan's
// segment lean masses, and the entry cross-checks of a scan sheet (stage 4 specification §6.3, §7.3
// to §7.5).
//
// PURE. No store, no clock, no `Calendar`, no `TimeZone`, no `Date`, no day key: every input is a
// number the caller has already read in its display unit. Nothing here throws or traps, and no
// result is NaN or infinity.
//
// Missing data is "not measured" (`nil`, `.neither`, `.notAvailable`), never zero. Nothing here
// judges a value: there is no band, target or verdict, only arithmetic on the numbers shown.
//
// Units: the comparison is unit-free (both readings are in one display unit). Segment lean masses
// are in one unit of the caller's choice. The cross-checks take kilograms and percentages.

// MARK: - Display and quantize

/// The text a body-record value is shown as, and the number that text stands for.
/// No Kotlin twin, by ruling R43 of the stage 1 specification.
public enum BodyRecordMath {
    /// A magnitude at or beyond this has no display number: it is shown as a dash.
    private static let displayLimit = 1e15
    /// Decimals are clamped to this range.
    private static let decimalsRange = 0...6
    /// What is shown for a value with no display number.
    private static let dash = "\u{2014}"

    /// The text a value is shown as. `decimals` is clamped to 0...6.
    ///   decimals == 0:  String(Int(x.rounded()))            (half away from zero)
    ///   otherwise:      String(format: "%.<decimals>f", x)  (no locale: a "." separator)
    /// A result that is a negative zero ("-0", "-0.0", …) loses its minus sign.
    /// "—" when x is not finite or abs(x) >= 1e15.
    public static func displayString(_ x: Double, decimals: Int) -> String {
        guard x.isFinite, abs(x) < displayLimit else { return dash }
        let places = min(max(decimals, decimalsRange.lowerBound), decimalsRange.upperBound)
        if places == 0 {
            // abs(x) < 1e15, so the rounded value always fits an Int. Int(-0.0) is 0: no "-0".
            return String(Int(x.rounded(.toNearestOrAwayFromZero)))
        }
        let text = String(format: "%.\(places)f", x)
        // "-0.0", "-0.00", …: every digit is a zero, so the minus sign says nothing true.
        if text.hasPrefix("-"), !text.contains(where: { $0 >= "1" && $0 <= "9" }) {
            return String(text.dropFirst())
        }
        return text
    }

    /// The number `displayString` shows, as a Double. `x` unchanged when it is not finite or
    /// abs(x) >= 1e15. Never negative zero.
    public static func quantize(_ x: Double, decimals: Int) -> Double {
        guard x.isFinite, abs(x) < displayLimit,
              let shown = Double(displayString(x, decimals: decimals)) else { return x }
        return shown == 0 ? 0 : shown
    }
}

// MARK: - Comparison

/// One value as it is displayed: already in the display unit, with the decimals it is shown at.
/// No Kotlin twin, by ruling R43 of the stage 1 specification.
public struct BodyRecordReading: Equatable, Sendable {
    public let value: Double
    public let decimals: Int

    public init(value: Double, decimals: Int) {
        self.value = value; self.decimals = decimals
    }
}

/// Which way a displayed value moved between two scans. Descriptive only: not a judgement.
/// No Kotlin twin, by ruling R43 of the stage 1 specification.
public enum BodyRecordDirection: String, Sendable { case up, down, same }

/// The change between two displayed values.
/// No Kotlin twin, by ruling R43 of the stage 1 specification.
public struct BodyRecordDelta: Equatable, Sendable {
    public let earlier: Double      // quantized
    public let later: Double        // quantized
    public let delta: Double        // quantize(later - earlier); never negative zero
    public let percent: Double?     // quantize(delta / earlier * 100, decimals: 1); nil unless earlier > 0
    public let direction: BodyRecordDirection   // from the sign of `delta`

    public init(earlier: Double, later: Double, delta: Double, percent: Double?,
                direction: BodyRecordDirection) {
        self.earlier = earlier; self.later = later; self.delta = delta
        self.percent = percent; self.direction = direction
    }
}

/// What two scans say about one field.
/// No Kotlin twin, by ruling R43 of the stage 1 specification.
public enum BodyRecordChange: Equatable, Sendable {
    case both(BodyRecordDelta)
    case onlyEarlier(Double)        // quantized
    case onlyLater(Double)          // quantized
    case neither
}

/// The scan-to-scan comparison of one field.
/// No Kotlin twin, by ruling R43 of the stage 1 specification.
public enum BodyRecordComparison {
    /// The decimals a percent change is shown at.
    private static let percentDecimals = 1

    /// The change from `earlier` to `later`, computed on the numbers the owner sees (§7.3). The
    /// order of the two scans is the caller's business.
    public static func compare(earlier: BodyRecordReading?,
                               later: BodyRecordReading?) -> BodyRecordChange {
        // 1. A reading whose value is not finite is treated as absent.
        let e = earlier.flatMap { $0.value.isFinite ? $0 : nil }
        let l = later.flatMap { $0.value.isFinite ? $0 : nil }

        // 2. Both absent, or one absent.
        switch (e, l) {
        case (nil, nil):
            return .neither
        case (let e?, nil):
            return .onlyEarlier(BodyRecordMath.quantize(e.value, decimals: e.decimals))
        case (nil, let l?):
            return .onlyLater(BodyRecordMath.quantize(l.value, decimals: l.decimals))
        case (let e?, let l?):
            // 3. Both present: at the larger of the two decimal counts, on the displayed values.
            let d = max(e.decimals, l.decimals)
            let a = BodyRecordMath.quantize(e.value, decimals: d)
            let b = BodyRecordMath.quantize(l.value, decimals: d)
            var delta = BodyRecordMath.quantize(b - a, decimals: d)
            if !delta.isFinite {
                // SPEC-NOTE: §7.3 does not say what the change is when `later - earlier` overflows
                // (two finite readings of opposite sign near the largest double). No output may be
                // infinite, so the change saturates at the largest finite magnitude. It keeps its
                // sign, so the direction is right, and `displayString` shows it as a dash.
                delta = delta > 0 ? .greatestFiniteMagnitude : -.greatestFiniteMagnitude
            }
            // 4. A percent only of a positive displayed base.
            var percent: Double?
            if a > 0 {
                let p = BodyRecordMath.quantize(delta / a * 100, decimals: percentDecimals)
                // SPEC-NOTE: §7.3 gives a percent whenever the earlier value is positive. A quotient
                // that overflows is not a number, so the percent is then absent, never infinite.
                percent = p.isFinite ? p : nil
            }
            // 5. The direction is the sign of the displayed change.
            let direction: BodyRecordDirection = delta > 0 ? .up : (delta < 0 ? .down : .same)
            return .both(BodyRecordDelta(earlier: a, later: b, delta: delta, percent: percent,
                                         direction: direction))
        }
    }
}

// MARK: - Derived figures

/// Segment lean masses of one scan, all in one unit. Nil means the report value was not entered.
/// No Kotlin twin, by ruling R43 of the stage 1 specification.
public struct BodyScanComponents: Equatable, Sendable {
    public var armsLean: Double?
    public var armLeftLean: Double?
    public var armRightLean: Double?
    public var legsLean: Double?
    public var legLeftLean: Double?
    public var legRightLean: Double?

    public init(armsLean: Double? = nil, armLeftLean: Double? = nil, armRightLean: Double? = nil,
                legsLean: Double? = nil, legLeftLean: Double? = nil, legRightLean: Double? = nil) {
        self.armsLean = armsLean; self.armLeftLean = armLeftLean; self.armRightLean = armRightLean
        self.legsLean = legsLean; self.legLeftLean = legLeftLean; self.legRightLean = legRightLean
    }
}

/// Why a derived figure has no number.
/// No Kotlin twin, by ruling R43 of the stage 1 specification.
public enum BodyScanDerivedGap: String, Sendable { case missingComponent, invalidComponent }

/// A derived figure: a number, or the reason there is none. Never zero for a missing component.
/// No Kotlin twin, by ruling R43 of the stage 1 specification.
public enum BodyScanDerivedValue: Equatable, Sendable {
    case value(Double)
    case notAvailable(BodyScanDerivedGap)
}

/// Where an arms or legs lean figure came from.
/// No Kotlin twin, by ruling R43 of the stage 1 specification.
public enum BodyScanComponentSource: String, Sendable { case printedTotal, sumOfSides }

/// The figures derived from one scan. Computed from stored entries and never stored.
/// No Kotlin twin, by ruling R43 of the stage 1 specification.
public struct BodyScanDerived: Equatable, Sendable {
    /// Arms lean mass as a percentage of legs lean mass, one decimal.
    public let armToLegLeanPercent: BodyScanDerivedValue
    /// Where the arms and legs figures came from. Nil when that side was not available.
    public let armsSource: BodyScanComponentSource?
    public let legsSource: BodyScanComponentSource?
    /// (left - right) / max(left, right) * 100, one decimal. Positive: the left side is larger.
    public let armSideDifferencePercent: BodyScanDerivedValue
    public let legSideDifferencePercent: BodyScanDerivedValue

    public init(armToLegLeanPercent: BodyScanDerivedValue,
                armsSource: BodyScanComponentSource?, legsSource: BodyScanComponentSource?,
                armSideDifferencePercent: BodyScanDerivedValue,
                legSideDifferencePercent: BodyScanDerivedValue) {
        self.armToLegLeanPercent = armToLegLeanPercent
        self.armsSource = armsSource; self.legsSource = legsSource
        self.armSideDifferencePercent = armSideDifferencePercent
        self.legSideDifferencePercent = legSideDifferencePercent
    }
}

/// A component is usable when it is non-nil, finite and greater than zero (§7.4). Shared by the
/// derivation and the cross-checks so the two cannot disagree about what "entered" means.
private func bodyScanUsable(_ value: Double?) -> Double? {
    guard let value, value.isFinite, value > 0 else { return nil }
    return value
}

/// The derived figures of one scan (§7.4).
/// No Kotlin twin, by ruling R43 of the stage 1 specification.
public enum BodyScanDerivation {
    /// The decimals every derived percentage is shown at.
    private static let percentDecimals = 1

    /// A pair total (arms or legs) resolved from its printed total and its two sides.
    private enum PairTotal {
        case value(Double, BodyScanComponentSource)
        case gap(BodyScanDerivedGap)
    }

    private static func pairTotal(total: Double?, left: Double?, right: Double?) -> PairTotal {
        // 1. The printed total is usable: it is the authority.
        if let printed = bodyScanUsable(total) { return .value(printed, .printedTotal) }
        // 3a. A printed total that is not usable is a wrong entry, not an absent one: the sides do
        //     not stand in for it.
        if total != nil { return .gap(.invalidComponent) }
        // 2. No printed total and both sides usable: their sum.
        if let l = bodyScanUsable(left), let r = bodyScanUsable(right) {
            let sum = l + r
            // SPEC-NOTE: §7.4 does not cover two usable sides whose sum overflows. An infinite
            // total would turn the ratio into 0.0 or NaN, so the pair is then an invalid component.
            return sum.isFinite ? .value(sum, .sumOfSides) : .gap(.invalidComponent)
        }
        // 3b. No printed total, and a side that was entered is not usable.
        if (left != nil && bodyScanUsable(left) == nil) || (right != nil && bodyScanUsable(right) == nil) {
            return .gap(.invalidComponent)
        }
        // 4. Otherwise something was simply not entered.
        return .gap(.missingComponent)
    }

    private static func sideDifference(left: Double?, right: Double?) -> BodyScanDerivedValue {
        // A side that was entered and is not usable outranks a side that was not entered.
        if (left != nil && bodyScanUsable(left) == nil) || (right != nil && bodyScanUsable(right) == nil) {
            return .notAvailable(.invalidComponent)
        }
        guard let l = bodyScanUsable(left), let r = bodyScanUsable(right) else {
            return .notAvailable(.missingComponent)
        }
        // Both are finite and greater than zero, so the divisor is too and the quotient is within
        // -1...1.
        let percent = (l - r) / max(l, r) * 100
        guard percent.isFinite else { return .notAvailable(.invalidComponent) }
        return .value(BodyRecordMath.quantize(percent, decimals: percentDecimals))
    }

    public static func derive(_ components: BodyScanComponents) -> BodyScanDerived {
        let arms = pairTotal(total: components.armsLean, left: components.armLeftLean,
                             right: components.armRightLean)
        let legs = pairTotal(total: components.legsLean, left: components.legLeftLean,
                             right: components.legRightLean)

        var armsSource: BodyScanComponentSource?
        var legsSource: BodyScanComponentSource?
        if case .value(_, let source) = arms { armsSource = source }
        if case .value(_, let source) = legs { legsSource = source }

        let ratio: BodyScanDerivedValue
        switch (arms, legs) {
        case (.value(let a, _), .value(let l, _)):
            // `l` is greater than zero. The quotient can still overflow for a vanishingly small
            // legs figure; that is not a number to show.
            let r = a / l * 100
            ratio = r.isFinite ? .value(BodyRecordMath.quantize(r, decimals: percentDecimals))
                               : .notAvailable(.invalidComponent)
        case (.gap(.invalidComponent), _), (_, .gap(.invalidComponent)):
            // Invalid outranks missing.
            ratio = .notAvailable(.invalidComponent)
        default:
            ratio = .notAvailable(.missingComponent)
        }

        return BodyScanDerived(
            armToLegLeanPercent: ratio,
            armsSource: armsSource,
            legsSource: legsSource,
            armSideDifferencePercent: sideDifference(left: components.armLeftLean,
                                                     right: components.armRightLean),
            legSideDifferencePercent: sideDifference(left: components.legLeftLean,
                                                     right: components.legRightLean))
    }
}

// MARK: - Entry cross-checks

/// The printed figures a scan sheet can cross-check. Masses in kilograms. Nil: not entered.
/// No Kotlin twin, by ruling R43 of the stage 1 specification.
public struct BodyScanCheckInput: Equatable, Sendable {
    public var totalMass: Double?
    public var fatMass: Double?
    public var leanMass: Double?
    public var boneMass: Double?
    public var fatFreeMass: Double?
    public var bodyFatPercent: Double?
    public var armsLean: Double?
    public var armLeftLean: Double?
    public var armRightLean: Double?
    public var legsLean: Double?
    public var legLeftLean: Double?
    public var legRightLean: Double?
    public var androidFatPercent: Double?
    public var gynoidFatPercent: Double?
    public var androidGynoidRatio: Double?

    /// Every field nil.
    public init() {}
}

/// One internal-consistency check of a scan's printed figures.
/// No Kotlin twin, by ruling R43 of the stage 1 specification.
public enum BodyScanCheck: String, CaseIterable, Sendable {
    case totalIsFatLeanBone
    case fatFreeIsLeanBone
    case bodyFatPercentIsFatShare
    case armsIsLeftPlusRight
    case legsIsLeftPlusRight
    case ratioIsAndroidOverGynoid
}

/// The entry cross-checks of a scan sheet (§7.5). A mismatch is an entry aid: it never blocks a
/// save, because the report is the authority.
/// No Kotlin twin, by ruling R43 of the stage 1 specification.
public enum BodyScanChecks {
    public static let massToleranceKg = 0.25
    public static let percentTolerancePoints = 0.5
    public static let ratioTolerance = 0.02

    /// The checks whose operands are all present and usable and which do not hold, in
    /// `BodyScanCheck.allCases` order.
    public static func mismatches(_ input: BodyScanCheckInput) -> [BodyScanCheck] {
        BodyScanCheck.allCases.filter { isMismatch($0, input) }
    }

    /// True when every operand the check names is usable and the check does not hold. A check with
    /// an operand that is absent, zero, negative or not finite is silent.
    private static func isMismatch(_ check: BodyScanCheck, _ input: BodyScanCheckInput) -> Bool {
        switch check {
        case .totalIsFatLeanBone:
            guard let total = bodyScanUsable(input.totalMass), let fat = bodyScanUsable(input.fatMass),
                  let lean = bodyScanUsable(input.leanMass), let bone = bodyScanUsable(input.boneMass)
            else { return false }
            return abs(total - (fat + lean + bone)) > massToleranceKg

        case .fatFreeIsLeanBone:
            guard let fatFree = bodyScanUsable(input.fatFreeMass), let lean = bodyScanUsable(input.leanMass),
                  let bone = bodyScanUsable(input.boneMass)
            else { return false }
            return abs(fatFree - (lean + bone)) > massToleranceKg

        case .bodyFatPercentIsFatShare:
            guard let p = bodyScanUsable(input.bodyFatPercent), let fat = bodyScanUsable(input.fatMass),
                  let total = bodyScanUsable(input.totalMass)
            else { return false }
            // Reports differ on whether bone is in the denominator; either reading passes. The
            // second reading exists only when lean mass is usable.
            guard abs(p - fat / total * 100) > percentTolerancePoints else { return false }
            if let lean = bodyScanUsable(input.leanMass) {
                return abs(p - fat / (fat + lean) * 100) > percentTolerancePoints
            }
            return true

        case .armsIsLeftPlusRight:
            guard let arms = bodyScanUsable(input.armsLean), let left = bodyScanUsable(input.armLeftLean),
                  let right = bodyScanUsable(input.armRightLean)
            else { return false }
            return abs(arms - (left + right)) > massToleranceKg

        case .legsIsLeftPlusRight:
            guard let legs = bodyScanUsable(input.legsLean), let left = bodyScanUsable(input.legLeftLean),
                  let right = bodyScanUsable(input.legRightLean)
            else { return false }
            return abs(legs - (left + right)) > massToleranceKg

        case .ratioIsAndroidOverGynoid:
            guard let ratio = bodyScanUsable(input.androidGynoidRatio),
                  let android = bodyScanUsable(input.androidFatPercent),
                  let gynoid = bodyScanUsable(input.gynoidFatPercent)
            else { return false }
            // SPEC-NOTE: §7.5 writes this as a comparison of doubles against 0.02, which is not
            // exact in binary: a printed ratio exactly 0.02 from android / gynoid can land a hair
            // beyond the tolerance and fire (1.22 against 36 / 30). The arithmetic is kept as
            // written; the line is an entry aid and never blocks a save.
            return abs(ratio - android / gynoid) > ratioTolerance
        }
    }
}
