import SwiftUI

// MARK: - Ambient field (docs/personal/REDESIGN-IMPLEMENTATION.md §3.7)
//
// A soft colour wash behind the top of each redesigned screen: a few radial-gradient blobs, a faint
// texture of concentric circles and a fade to black. On Today the blobs come from the day's scores
// (`ambientBlobs(for:intensity:)`); other screens use the fixed palettes copied from the mockups'
// `data-ambient` attributes (`AmbientPreset`). The geometry is expressed in the mockups' 402 pt wide
// design space; the view scales x positions to the real width.

/// The colour of an ambient blob. An enum rather than a `Color` so blob lists are `Equatable`/`Hashable`
/// and testable (two reads of a SwiftUI `Color` are not reliably `==`).
public enum AmbientHue: String, CaseIterable, Hashable, Sendable {
    case sleep
    case strain
    case recoveryHigh
    case recoveryMid
    case recoveryLow
    case hrv
    case heart
    case breath
    case temp
    case lift
    case stress
    case coach
    case rem
    case deep
    case zone3
    case zone4
    /// `textTertiary`: the no-data wash (E1) and the "Colour from your scores" off state.
    case neutral
    /// `textSecondary`: the calibrating screen's grey (E2).
    case neutralBright

    /// The Recovery hue for a band, so Recovery colour comes from its band everywhere.
    public static func recovery(_ band: NoopTheme.RecoveryBand) -> AmbientHue {
        switch band {
        case .low: return .recoveryLow
        case .mid: return .recoveryMid
        case .high: return .recoveryHigh
        }
    }

    /// The `NoopTheme` colour this hue paints with.
    public var color: Color {
        switch self {
        case .sleep: return NoopTheme.sleep
        case .strain: return NoopTheme.strain
        case .recoveryHigh: return NoopTheme.recovery
        case .recoveryMid: return NoopTheme.recoveryMid
        case .recoveryLow: return NoopTheme.recoveryLow
        case .hrv: return NoopTheme.hrv
        case .heart: return NoopTheme.heart
        case .breath: return NoopTheme.breath
        case .temp: return NoopTheme.temp
        case .lift: return NoopTheme.lift
        case .stress: return NoopTheme.stress
        case .coach: return NoopTheme.coach
        case .rem: return NoopTheme.stageREM
        case .deep: return NoopTheme.stageDeep
        case .zone3: return NoopTheme.zone3
        case .zone4: return NoopTheme.zone4
        case .neutral: return NoopTheme.textTertiary
        case .neutralBright: return NoopTheme.textSecondary
        }
    }
}

/// One radial-gradient blob: centre `(x, y)` in points in the 402 pt design space, `radius` in points,
/// peak opacity `alpha` (0…1). The gradient runs colour at `alpha` → `alpha × 0.45` at 38 % → clear at 70 %.
public struct AmbientBlob: Hashable, Sendable {
    public var hue: AmbientHue
    public var x: Double
    public var y: Double
    public var radius: Double
    public var alpha: Double

    public init(hue: AmbientHue, x: Double, y: Double, radius: Double, alpha: Double) {
        self.hue = hue
        self.x = x
        self.y = y
        self.radius = radius
        self.alpha = alpha
    }

    /// The single grey wash used when there are no scores at all (E1) and when the user has turned
    /// "Colour from your scores" off.
    public static let neutral = AmbientBlob(hue: .neutral, x: 201, y: 0, radius: 280, alpha: 0.3)

    /// The blob with its alpha multiplied by the intensity, capped at 1.
    public func scaled(by intensity: AmbientIntensity) -> AmbientBlob {
        var copy = self
        copy.alpha = min(1, max(0, alpha * intensity.multiplier))
        return copy
    }
}

/// The "Subtle / Balanced / Vivid" setting. Raw values are the `@AppStorage` representation under
/// `NoopTheme.Keys.ambientIntensity`.
public enum AmbientIntensity: String, CaseIterable, Sendable {
    case subtle
    case balanced
    case vivid

    /// Multiplier applied to every blob's alpha.
    public var multiplier: Double {
        switch self {
        case .subtle: return 0.6
        case .balanced: return 1.0
        case .vivid: return 1.4
        }
    }
}

/// The three Today scores that drive the ambient field. nil means the score is missing for the day.
public struct TodayScores: Equatable, Sendable {
    /// Sleep performance, 0…100.
    public var sleep: Double?
    /// Recovery, 0…100.
    public var recovery: Double?
    /// Strain, 0…21.
    public var strain: Double?

    public init(sleep: Double? = nil, recovery: Double? = nil, strain: Double? = nil) {
        self.sleep = sleep
        self.recovery = recovery
        self.strain = strain
    }

    public static let empty = TodayScores()
}

/// The Today ambient blobs for a day's scores (§3.7), with s = sleep/100, r = recovery/100, t = strain/21:
/// Sleep at (40, 10) radius 150+170s α 0.16+0.38s; Strain at (380, 40) radius 150+170t α 0.16+0.38t;
/// Recovery in its band colour at (210, −30) radius 170+190r α 0.18+0.42r. Inputs are clamped to their
/// valid ranges; a missing or non-finite score contributes no blob, and with no scores at all the result is
/// the single `AmbientBlob.neutral`. The intensity multiplies every alpha, capped at 1.
public func ambientBlobs(for scores: TodayScores, intensity: AmbientIntensity = .balanced) -> [AmbientBlob] {
    var blobs: [AmbientBlob] = []
    if let sleep = ambientClamp(scores.sleep, max: 100) {
        let s = sleep / 100
        blobs.append(AmbientBlob(hue: .sleep, x: 40, y: 10, radius: 150 + 170 * s, alpha: 0.16 + 0.38 * s))
    }
    if let strain = ambientClamp(scores.strain, max: 21) {
        let t = strain / 21
        blobs.append(AmbientBlob(hue: .strain, x: 380, y: 40, radius: 150 + 170 * t, alpha: 0.16 + 0.38 * t))
    }
    if let recovery = ambientClamp(scores.recovery, max: 100) {
        let r = recovery / 100
        let hue = AmbientHue.recovery(NoopTheme.recoveryBand(for: recovery))
        blobs.append(AmbientBlob(hue: hue, x: 210, y: -30, radius: 170 + 190 * r, alpha: 0.18 + 0.42 * r))
    }
    if blobs.isEmpty { blobs = [.neutral] }
    return blobs.map { $0.scaled(by: intensity) }
}

/// `value` clamped to 0…max, or nil when it is missing or not finite.
private func ambientClamp(_ value: Double?, max upper: Double) -> Double? {
    guard let value, value.isFinite else { return nil }
    return min(max(value, 0), upper)
}

// MARK: - Fixed palettes

/// Fixed ambient palettes for screens whose wash does not follow the day's scores. Values are copied
/// verbatim from the mockups' `data-ambient` attributes (`design/round2/index.html`,
/// `design/round3/*.html`); the mockup frame is named beside each case.
public enum AmbientPreset: Equatable, Sendable {
    /// Recovery detail (round 2 "02 Recovery"): band colour plus HRV. A nil band (no score) paints the
    /// band blob neutral rather than inventing a colour.
    case recovery(NoopTheme.RecoveryBand?)
    /// Sleep (round 2 "03 Sleep"): sleep, REM and deep.
    case sleep
    /// Training (round 2 "04 Training") and B6 "Add".
    case training
    /// Health (round 2 "05 Health").
    case health
    /// A1 Strain detail.
    case strain
    /// A2 All metrics.
    case allMetrics
    /// A3 Metric detail.
    case metricDetail
    /// A4 Live heart rate.
    case liveHeartRate
    /// A6 Strap and battery.
    case strap
    /// B1 Workout detail.
    case workoutDetail
    /// B2 Lift Log.
    case liftLog
    /// B3 Lift session.
    case liftSession
    /// B4 Paste workout preview.
    case pasteWorkout
    /// B5 Workout in progress.
    case workoutInProgress
    /// C1 Alarm.
    case alarm
    /// C3 Stress.
    case stress
    /// C4 Breathe.
    case breathe
    /// C5 Journal.
    case journal
    /// C6 What moves you.
    case whatMovesYou
    /// D1 Coach.
    case coach
    /// D2 Coach connection.
    case coachConnection
    /// D4 Data sources.
    case dataSources
    /// D5 Settings.
    case settings
    /// D6 Backup.
    case backup
    /// E1 Today with the strap away and no sleep yet.
    case strapAway
    /// E2 First week, calibrating.
    case calibrating
    /// E3 Pair your strap.
    case pairStrap

    /// Every preset, with Recovery in each band and without one. For previews and tests.
    public static let all: [AmbientPreset] = [
        .recovery(.high), .recovery(.mid), .recovery(.low), .recovery(nil),
        .sleep, .training, .health, .strain, .allMetrics, .metricDetail, .liveHeartRate, .strap,
        .workoutDetail, .liftLog, .liftSession, .pasteWorkout, .workoutInProgress,
        .alarm, .stress, .breathe, .journal, .whatMovesYou,
        .coach, .coachConnection, .dataSources, .settings, .backup,
        .strapAway, .calibrating, .pairStrap,
    ]

    /// The palette at Balanced intensity.
    public var baseBlobs: [AmbientBlob] {
        func b(_ hue: AmbientHue, _ x: Double, _ y: Double, _ r: Double, _ a: Double) -> AmbientBlob {
            AmbientBlob(hue: hue, x: x, y: y, radius: r, alpha: a)
        }
        switch self {
        case .recovery(let band):
            let hue = band.map(AmbientHue.recovery) ?? .neutral
            return [b(hue, 201, 150, 260, 0.42), b(.hrv, 380, 20, 190, 0.32)]
        case .sleep:
            return [b(.sleep, 120, 20, 290, 0.48), b(.rem, 380, 120, 180, 0.28), b(.deep, 10, 220, 180, 0.35)]
        case .training:
            return [b(.lift, 90, 10, 260, 0.44), b(.strain, 380, 90, 200, 0.26)]
        case .health:
            return [b(.recoveryHigh, 200, -10, 260, 0.28), b(.hrv, 400, 140, 170, 0.22), b(.heart, 0, 150, 150, 0.2)]
        case .strain:
            return [b(.strain, 201, 150, 270, 0.44), b(.recoveryHigh, 380, 10, 170, 0.2)]
        case .allMetrics:
            return [b(.hrv, 60, 0, 220, 0.26), b(.sleep, 380, 40, 200, 0.24)]
        case .metricDetail:
            return [b(.hrv, 200, 40, 280, 0.4), b(.sleep, 400, 200, 170, 0.18)]
        case .liveHeartRate:
            return [b(.zone3, 201, 230, 300, 0.36), b(.heart, 60, 40, 180, 0.22)]
        case .strap:
            return [b(.recoveryHigh, 201, 170, 260, 0.34), b(.hrv, 400, 20, 170, 0.18)]
        case .workoutDetail:
            return [b(.strain, 120, 30, 260, 0.42), b(.zone4, 400, 150, 180, 0.22)]
        case .liftLog:
            return [b(.lift, 100, 10, 270, 0.46), b(.recoveryMid, 400, 120, 170, 0.18)]
        case .liftSession:
            return [b(.lift, 200, 0, 280, 0.4), b(.strain, 400, 160, 160, 0.18)]
        case .pasteWorkout:
            return [b(.lift, 80, 0, 220, 0.3), b(.recoveryHigh, 400, 40, 170, 0.16)]
        case .workoutInProgress:
            return [b(.zone3, 201, 260, 320, 0.42), b(.lift, 40, 30, 200, 0.24)]
        case .alarm:
            return [b(.sleep, 90, 20, 260, 0.42), b(.temp, 390, 110, 200, 0.26)]
        case .stress:
            return [b(.stress, 120, 20, 240, 0.32), b(.breath, 400, 140, 190, 0.22)]
        case .breathe:
            return [b(.breath, 201, 300, 320, 0.42), b(.hrv, 60, 40, 200, 0.22)]
        case .journal:
            return [b(.sleep, 120, 0, 240, 0.34), b(.coach, 400, 100, 180, 0.2)]
        case .whatMovesYou:
            return [b(.recoveryHigh, 120, 10, 250, 0.34), b(.recoveryLow, 400, 150, 170, 0.2)]
        case .coach:
            return [b(.coach, 201, 0, 280, 0.36), b(.recoveryHigh, 420, 140, 170, 0.16)]
        case .coachConnection:
            return [b(.coach, 120, 10, 250, 0.34), b(.hrv, 410, 120, 170, 0.16)]
        case .dataSources:
            return [b(.hrv, 100, 10, 240, 0.3), b(.lift, 410, 140, 170, 0.2)]
        case .settings:
            return [b(.sleep, 80, 0, 220, 0.24), b(.strain, 420, 60, 180, 0.2)]
        case .backup:
            return [b(.recoveryHigh, 201, 120, 280, 0.34), b(.hrv, 30, 20, 180, 0.2)]
        case .strapAway:
            return [b(.neutral, 201, 0, 280, 0.3), b(.strain, 400, 60, 160, 0.18)]
        case .calibrating:
            return [b(.sleep, 40, 10, 250, 0.4), b(.strain, 380, 40, 200, 0.28), b(.neutralBright, 210, -30, 240, 0.18)]
        case .pairStrap:
            return [b(.breath, 201, 300, 320, 0.36), b(.hrv, 40, 40, 200, 0.24)]
        }
    }

    /// The palette with the intensity applied (alpha capped at 1).
    public func blobs(intensity: AmbientIntensity = .balanced) -> [AmbientBlob] {
        baseBlobs.map { $0.scaled(by: intensity) }
    }
}

// MARK: - View

/// Drawing constants from `design/system/noop.css` / `noop.js` that have no `NoopTheme` token yet.
private enum AmbientGeometry {
    /// Width of the mockup frame the blob coordinates are expressed in.
    static let designWidth: Double = 402
    static let textureCenter = CGPoint(x: 330, y: 40)
    static let textureFirstRadius: CGFloat = 48
    static let textureLastRadius: CGFloat = 640
    static let textureStep: CGFloat = 34
    static let textureOpacity: Double = 0.035
    static let driftOffset = CGSize(width: 18, height: 14)
    static let driftScale: CGFloat = 1.08
    /// CSS sizes a `radial-gradient(circle at 50% 50%)` to the box's farthest corner (r√2), so the 70 % stop
    /// lands just inside the circle's edge.
    static let gradientReach: Double = 2.0.squareRoot()
}

/// The ambient wash: blobs, the concentric-circle texture and the fade to black, `height` tall. Blobs
/// crossfade when they change; two of every three drift slowly unless Reduce Motion is on. With
/// `enabled` false (the user turned "Colour from your scores" off) only the neutral blob is drawn.
public struct AmbientField: View {
    private let blobs: [AmbientBlob]
    private let enabled: Bool
    private let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Drift is a never-settling loop, so it also stops for Low Power, quiet motion and hidden windows.
    @ObservedObject private var motion = NoopMotionState.shared

    public init(blobs: [AmbientBlob], enabled: Bool = true, height: CGFloat = NoopTheme.Layout.ambientHeight) {
        self.blobs = blobs
        self.enabled = enabled
        self.height = height
    }

    /// The Today field for a day's scores.
    public init(scores: TodayScores, intensity: AmbientIntensity = .balanced, enabled: Bool = true,
                height: CGFloat = NoopTheme.Layout.ambientHeight) {
        self.init(blobs: ambientBlobs(for: scores, intensity: intensity), enabled: enabled, height: height)
    }

    private var shown: [AmbientBlob] { enabled ? blobs : [.neutral] }

    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let scaleX = width / AmbientGeometry.designWidth
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { index, blob in
                        AmbientBlobView(blob: blob, scaleX: scaleX, drifts: index % 3 != 2 && !motion.poseStill(reduceMotion))
                    }
                }
                .frame(width: width, height: height, alignment: .topLeading)
                .id(shown)
                .transition(.opacity)

                AmbientTexture(scaleX: scaleX)
                    .frame(width: width, height: height)

                LinearGradient(
                    stops: [
                        .init(color: NoopTheme.canvas.opacity(0), location: 0),
                        .init(color: NoopTheme.canvas.opacity(0.25), location: 0.45),
                        .init(color: NoopTheme.canvas.opacity(0.85), location: 0.8),
                        .init(color: NoopTheme.canvas, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(width: width, height: height)
            }
            .frame(width: width, height: height, alignment: .topLeading)
            .animation(NoopTheme.Motion.resolved(NoopTheme.Motion.ambientCrossfade, reduceMotion: reduceMotion), value: shown)
        }
        .frame(height: height)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct AmbientBlobView: View {
    let blob: AmbientBlob
    let scaleX: Double
    let drifts: Bool
    @State private var drifted = false

    var body: some View {
        let color = blob.hue.color
        let radius = CGFloat(max(0, blob.radius))
        Circle()
            .fill(
                RadialGradient(
                    stops: [
                        .init(color: color.opacity(blob.alpha), location: 0),
                        .init(color: color.opacity(blob.alpha * 0.45), location: 0.38),
                        .init(color: color.opacity(0), location: 0.7),
                    ],
                    center: .center, startRadius: 0, endRadius: radius * AmbientGeometry.gradientReach
                )
            )
            .frame(width: radius * 2, height: radius * 2)
            .scaleEffect(drifted ? AmbientGeometry.driftScale : 1)
            .offset(drifted ? AmbientGeometry.driftOffset : .zero)
            .position(x: blob.x * scaleX, y: blob.y)
            .onAppear { setDrift(drifts) }
            .onChangeCompat(of: drifts) { setDrift($0) }
    }

    private func setDrift(_ on: Bool) {
        if on {
            withAnimation(.easeInOut(duration: NoopTheme.Motion.ambientDriftDuration).repeatForever(autoreverses: true)) { drifted = true }
        } else if drifted {
            withAnimation(NoopTheme.Motion.reduced) { drifted = false }
        }
    }
}

private struct AmbientTexture: View {
    let scaleX: Double

    var body: some View {
        Canvas { context, _ in
            let center = CGPoint(x: AmbientGeometry.textureCenter.x * scaleX, y: AmbientGeometry.textureCenter.y)
            var path = Path()
            var radius = AmbientGeometry.textureFirstRadius
            while radius < AmbientGeometry.textureLastRadius {
                path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                radius += AmbientGeometry.textureStep
            }
            context.stroke(path, with: .color(Color.white.opacity(AmbientGeometry.textureOpacity)), lineWidth: 1)
        }
    }
}

public extension View {
    /// Puts the canvas black and an ambient field behind the content, running under the top safe area.
    /// The field is a fixed backdrop: it does not scroll with the content.
    func noopAmbientBackground(_ blobs: [AmbientBlob], enabled: Bool = true) -> some View {
        background(alignment: .top) {
            ZStack(alignment: .top) {
                NoopTheme.canvas.ignoresSafeArea()
                AmbientField(blobs: blobs, enabled: enabled)
                    .ignoresSafeArea(edges: .top)
            }
        }
    }
}

#if DEBUG
#Preview("AmbientField / Today") {
    ScrollView {
        VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
            Text(verbatim: "Today").noopFont(.largeTitle)
            Text(verbatim: "Sleep 86 · Recovery 68 · Strain 11.4").noopFont(.footnote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NoopTheme.Layout.gutter)
    }
    .noopAmbientBackground(ambientBlobs(for: TodayScores(sleep: 86, recovery: 68, strain: 11.4)))
}

#Preview("AmbientField / presets") {
    ScrollView {
        VStack(spacing: NoopTheme.Layout.cardGap) {
            AmbientField(scores: .empty, height: 160)
            AmbientField(scores: TodayScores(sleep: 40, recovery: 20, strain: 18), intensity: .vivid, height: 160)
            AmbientField(scores: TodayScores(sleep: 86, recovery: 68, strain: 11.4), enabled: false, height: 160)
            ForEach(Array(AmbientPreset.all.enumerated()), id: \.offset) { _, preset in
                AmbientField(blobs: preset.blobs(), height: 160)
            }
        }
    }
    .background(NoopTheme.canvas)
}
#endif
