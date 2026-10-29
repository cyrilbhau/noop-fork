import SwiftUI

/// Tokens for the iPhone redesign (`docs/personal/REDESIGN-IMPLEMENTATION.md` §3, values from
/// `design/system/noop.css`). A separate namespace from `StrandPalette`/`NoopMetrics`, so the macOS app and
/// any screen not yet migrated keep their current look. The redesign is dark-only: these are fixed colours,
/// not light/dark pairs.
public enum NoopTheme {

    // MARK: - Surfaces

    public static let canvas = Color(hex: "#000000")
    /// Card fill. Drawn over a material blur by `NoopCard`; `cardSolid` where blur is unavailable.
    public static let card = Color(hex: "#1A1A1E").opacity(0.74)
    public static let cardSolid = Color(hex: "#151518")
    public static let cardBorder = Color.white.opacity(0.05)
    /// Round icon buttons, pills, chips.
    public static let control = Color(hex: "#2C2C32").opacity(0.72)
    /// Ring, arc and bar tracks.
    public static let track = Color.white.opacity(0.08)
    /// The dashed track of an empty (missing-value) ring. Brighter than `track` because it is drawn thinner.
    public static let trackEmpty = Color.white.opacity(0.22)
    /// Arc-gauge knob.
    public static let knob = Color.white
    /// Target-band tick marks on an arc gauge.
    public static let targetTick = Color.white.opacity(0.8)
    public static let separator = Color.white.opacity(0.07)
    /// Sheet background (`.sheet` in the mockups).
    public static let sheet = Color(hex: "#1A1A1E")

    // MARK: - Text

    public static let textPrimary = Color(hex: "#F5F5F7")
    public static let textSecondary = Color(hex: "#9B9BA3")
    /// Captions and source lines. Raised from the mockups' #5F5F67 (2.7:1 on a sheet, 2.9:1 on a card) to
    /// #8A8A93 so caption-size text meets 4.5:1 on every redesign surface (5.1:1 on `sheet`, 5.4:1 on
    /// `card` over the canvas) while staying a step dimmer than `textSecondary`.
    public static let textTertiary = Color(hex: "#8A8A93")

    // MARK: - Domains

    public static let recovery = Color(hex: "#2FD27A")
    public static let recoveryMid = Color(hex: "#FFC83D")
    public static let recoveryLow = Color(hex: "#FF5A4F")
    public static let strain = Color(hex: "#3A9BFF")
    public static let sleep = Color(hex: "#8F7DFF")
    public static let heart = Color(hex: "#FF4D6B")
    public static let hrv = Color(hex: "#47C8F5")
    public static let breath = Color(hex: "#36D3BF")
    public static let temp = Color(hex: "#FF9F45")
    public static let lift = Color(hex: "#FF8A3D")
    public static let stress = Color(hex: "#FF7A59")
    public static let coach = Color(hex: "#C8A8FF")

    // MARK: - Sleep stages

    public static let stageAwake = Color(hex: "#C9C9D1")
    public static let stageREM = Color(hex: "#6FD3FF")
    public static let stageLight = Color(hex: "#8F7DFF")
    public static let stageDeep = Color(hex: "#4A3AD0")

    // MARK: - Heart-rate zones (1…5)

    public static let zone1 = Color(hex: "#7FD1FF")
    public static let zone2 = Color(hex: "#2FD27A")
    public static let zone3 = Color(hex: "#FFC83D")
    public static let zone4 = Color(hex: "#FF8A3D")
    public static let zone5 = Color(hex: "#FF4D6B")
    public static let zones: [Color] = [zone1, zone2, zone3, zone4, zone5]

    /// Zone colour for a 1-based zone number; values outside 1…5 clamp to the nearest zone.
    public static func zoneColor(_ zone: Int) -> Color {
        zones[min(max(zone, 1), 5) - 1]
    }

    // MARK: - Recovery band

    /// The three Recovery bands. Kept separate from the colour so the thresholds can be pinned by a test
    /// (two reads of a SwiftUI `Color` are not reliably `==`).
    public enum RecoveryBand: Equatable, Sendable {
        case low, mid, high
    }

    /// Mirrors `RecoveryScorer.bandRedMax` / `bandYellowMax` in StrandAnalytics (34 / 67). StrandDesign does
    /// not depend on StrandAnalytics, so the constants are repeated here and pinned by `NoopThemeTests`.
    public static let recoveryLowMax: Double = 34
    public static let recoveryMidMax: Double = 67

    public static func recoveryBand(for score: Double) -> RecoveryBand {
        if score < recoveryLowMax { return .low }
        if score < recoveryMidMax { return .mid }
        return .high
    }

    public static func recoveryColor(for band: RecoveryBand) -> Color {
        switch band {
        case .low: return recoveryLow
        case .mid: return recoveryMid
        case .high: return recovery
        }
    }

    /// Recovery colour comes from its band, everywhere.
    public static func recoveryColor(for score: Int) -> Color {
        recoveryColor(for: recoveryBand(for: Double(score)))
    }

    public static func recoveryColor(for score: Double) -> Color {
        recoveryColor(for: recoveryBand(for: score))
    }

    // MARK: - Layout (§3.4)

    public enum Layout {
        public static let gutter: CGFloat = 16
        public static let cardGap: CGFloat = 12
        public static let cardRadius: CGFloat = 22
        public static let tileRadius: CGFloat = 20
        public static let widgetRadius: CGFloat = 24
        public static let iconTileRadius: CGFloat = 13
        public static let cardPadding: CGFloat = 18
        public static let rowVerticalPadding: CGFloat = 14
        public static let rowHorizontalPadding: CGFloat = 18
        public static let sectionTop: CGFloat = 28
        public static let sectionBottom: CGFloat = 12
        /// Title inset from the screen edge; use outside the gutter column.
        public static let sectionSide: CGFloat = gutter
        /// Caption inset inside the gutter column, aligning text with card content. Full-bleed
        /// captions add `gutter`; screen-edge titles use `sectionSide` instead.
        public static let captionInset: CGFloat = cardPadding
        /// Compact tiles in the redesigned Today Your cards section.
        public static let yourCardMinHeight: CGFloat = 112
        public static let yourCardPadding: CGFloat = rowVerticalPadding
        public static let yourCardIcon: CGFloat = 16
        /// Border shared by the dashboard metric and shortcut tiles.
        public static let yourCardBorderWidth: CGFloat = 1
        /// Tint chip distinguishing shortcut tiles from metric tiles.
        public static let shortcutIconChip: CGFloat = 28
        public static let shortcutIconOpacity: Double = 0.18
        public static let iconButton: CGFloat = 40
        public static let iconTile: CGFloat = 42
        public static let minTouchTarget: CGFloat = 44
        public static let pillHeight: CGFloat = 32
        public static let buttonHeight: CGFloat = 52
        public static let tileMinHeight: CGFloat = 150
        /// Height of the ambient wash behind the top of each screen.
        public static let ambientHeight: CGFloat = 600
        /// Small gaps between stacked elements inside a card.
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 24
    }

    // MARK: - Motion (§3.5)

    public enum Motion {
        public static let entrance = Animation.spring(response: 0.45, dampingFraction: 0.78)
        /// Per-card entrance stagger, top to bottom.
        public static let entranceStagger: Double = 0.04
        public static let entranceRise: CGFloat = 16
        public static let entranceScale: CGFloat = 0.98
        /// Ring and arc fill (≤4 % overshoot).
        public static let ringFill = Animation.spring(response: 0.9, dampingFraction: 0.72)
        /// Number count-up beside a ring fill.
        public static let countUp = Animation.easeOut(duration: 0.9)
        public static let chartDraw = Animation.easeOut(duration: 0.7)
        public static let chartAreaDelay: Double = 0.2
        public static let chartArea = Animation.easeOut(duration: 0.3)
        public static let dotPop = Animation.spring(response: 0.4, dampingFraction: 0.55)
        public static let bar = Animation.spring(response: 0.55, dampingFraction: 0.75)
        public static let barStagger: Double = 0.018
        public static let skeletonSweep: Double = 1.25
        public static let skeletonMinimum: Double = 0.3
        public static let pressDown = Animation.easeOut(duration: 0.12)
        public static let pressUp = Animation.spring(response: 0.45, dampingFraction: 0.6)
        public static let pressScale: CGFloat = 0.965
        public static let ambientCrossfade = Animation.easeInOut(duration: 0.8)
        /// Seconds per half-cycle of the idle ambient drift (autoreversing; built where the motion gate is read).
        public static let ambientDriftDuration: Double = 18
        public static let daySwipe = Animation.interactiveSpring(response: 0.4, dampingFraction: 0.86)
        /// Everything collapses to this under Reduce Motion.
        public static let reduced = Animation.easeInOut(duration: 0.15)

        /// The animation to use for `base`, or the short fade when Reduce Motion is on.
        public static func resolved(_ base: Animation, reduceMotion: Bool) -> Animation {
            reduceMotion ? reduced : base
        }

        /// Whether rings should animate from empty on appearance. False under Reduce Motion (rings appear
        /// filled) or when the "Rings fill on every load" setting is off.
        public static func ringsAnimate(reduceMotion: Bool, fillOnLoad: Bool) -> Bool {
            !reduceMotion && fillOnLoad
        }

        /// Seconds between beats for the live-heart pulse; nil (no pulse) for a missing or implausible BPM,
        /// or under Reduce Motion.
        public static func heartbeatInterval(bpm: Int?, reduceMotion: Bool) -> Double? {
            guard !reduceMotion, let bpm, bpm >= 25, bpm <= 250 else { return nil }
            return 60.0 / Double(bpm)
        }
    }

    // MARK: - Settings keys

    /// `@AppStorage` keys for the redesign's own settings. New keys only; nothing existing is renamed.
    public enum Keys {
        public static let redesignEnabled = "noop.redesignEnabled"
        public static let ringsFillOnLoad = "noop.redesign.ringsFillOnLoad"
        public static let ambientFromScores = "noop.redesign.ambientFromScores"
        public static let ambientIntensity = "noop.redesign.ambientIntensity"
    }
}
