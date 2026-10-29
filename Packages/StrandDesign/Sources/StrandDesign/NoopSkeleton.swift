import SwiftUI

// MARK: - Skeleton (docs/personal/REDESIGN-IMPLEMENTATION.md §3.5, §3.6 item 7)
//
// While data resolves, a card-shaped placeholder with faint text bars and a 110° light sweep stands in for
// the content, which stays laid out (so nothing jumps) but invisible. The skeleton is held for at least
// `NoopTheme.Motion.skeletonMinimum` so a fast load never flickers. Under Reduce Motion the placeholder is
// static.

/// The minimum-display rule, kept pure so it can be pinned by a test.
public enum NoopSkeletonTiming {

    /// Remainders shorter than this are treated as done: `Date` arithmetic leaves sub-microsecond residue
    /// that would otherwise schedule a pointless hide.
    public static let holdTolerance: TimeInterval = 0.001

    /// Seconds the skeleton must stay up after loading finishes. `shownAt` is when it appeared (nil when it
    /// never did, which needs no hold). The result is 0 or in `holdTolerance`…`minimum`: a clock that went
    /// backwards holds the full minimum rather than longer.
    public static func remainingHold(
        shownAt: Date?,
        now: Date,
        minimum: TimeInterval = NoopTheme.Motion.skeletonMinimum
    ) -> TimeInterval {
        guard let shownAt, minimum > 0 else { return 0 }
        let remaining = minimum - now.timeIntervalSince(shownAt)
        return remaining < holdTolerance ? 0 : min(minimum, remaining)
    }

    /// Whether the skeleton should be visible: while loading, and after it for whatever remains of the hold.
    public static func isVisible(
        isLoading: Bool,
        shownAt: Date?,
        now: Date,
        minimum: TimeInterval = NoopTheme.Motion.skeletonMinimum
    ) -> Bool {
        isLoading || remainingHold(shownAt: shownAt, now: now, minimum: minimum) > 0
    }
}

/// Skeleton colours from `design/system/noop.css` (`.sk`) that have no `NoopTheme` token yet.
private enum SkeletonStyle {
    static let base: Double = 0.035
    static let highlight: Double = 0.09
    /// The three text bars, top to bottom.
    static let barOpacities: [Double] = [0.07, 0.05, 0.04]
    static let barInset = CGSize(width: 18, height: 20)
    static let barHeight: CGFloat = 12
    static let barPitch: CGFloat = 24
    static let barWidthFraction: CGFloat = 0.46
    /// The sweep band is 2.5× the card's width, as the CSS `background-size: 250%`.
    static let sweepWidthFactor: CGFloat = 2.5
    /// 110° CSS gradient direction as unit points.
    static let sweepStart = UnitPoint(x: 0.03, y: 0.33)
    static let sweepEnd = UnitPoint(x: 0.97, y: 0.67)
}

private struct NoopSkeletonPlaceholder: View {
    let cornerRadius: CGFloat
    let animated: Bool
    @State private var phase = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(Color.white.opacity(SkeletonStyle.base))
            .overlay {
                if animated {
                    GeometryReader { geo in
                        let width = geo.size.width
                        let bandWidth = width * SkeletonStyle.sweepWidthFactor
                        // Over the base fill, the band adds enough white to peak at `highlight`.
                        let peak = (SkeletonStyle.highlight - SkeletonStyle.base) / (1 - SkeletonStyle.base)
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0), location: 0.3),
                                .init(color: Color.white.opacity(peak), location: 0.5),
                                .init(color: Color.white.opacity(0), location: 0.7),
                            ],
                            startPoint: SkeletonStyle.sweepStart, endPoint: SkeletonStyle.sweepEnd
                        )
                        .frame(width: bandWidth, height: geo.size.height)
                        .offset(x: phase ? width : -bandWidth)
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                GeometryReader { geo in
                    VStack(alignment: .leading, spacing: SkeletonStyle.barPitch - SkeletonStyle.barHeight) {
                        ForEach(Array(SkeletonStyle.barOpacities.enumerated()), id: \.offset) { _, opacity in
                            Capsule()
                                .fill(Color.white.opacity(opacity))
                                .frame(width: geo.size.width * SkeletonStyle.barWidthFraction, height: SkeletonStyle.barHeight)
                        }
                    }
                    .padding(.leading, SkeletonStyle.barInset.width)
                    .padding(.top, SkeletonStyle.barInset.height)
                }
            }
            .clipShape(shape)
            .onAppear {
                guard animated else { return }
                withAnimation(.linear(duration: NoopTheme.Motion.skeletonSweep).repeatForever(autoreverses: false)) {
                    phase = true
                }
            }
            .accessibilityHidden(true)
    }
}

private struct NoopSkeletonModifier: ViewModifier {
    let isLoading: Bool
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The sweep never settles, so it also stops for Low Power, quiet motion and hidden windows.
    @ObservedObject private var motion = NoopMotionState.shared
    @State private var showing: Bool
    @State private var shownAt: Date?
    @State private var hideTask: Task<Void, Never>?

    init(isLoading: Bool, cornerRadius: CGFloat) {
        self.isLoading = isLoading
        self.cornerRadius = cornerRadius
        _showing = State(initialValue: isLoading)
        _shownAt = State(initialValue: isLoading ? Date() : nil)
    }

    func body(content: Content) -> some View {
        content
            .opacity(showing ? 0 : 1)
            .accessibilityHidden(showing)
            .overlay {
                if showing {
                    NoopSkeletonPlaceholder(cornerRadius: cornerRadius, animated: !motion.poseStill(reduceMotion))
                        .transition(.opacity)
                }
            }
            .animation(NoopTheme.Motion.reduced, value: showing)
            .onChangeCompat(of: isLoading) { update(loading: $0) }
            .onDisappear { hideTask?.cancel() }
    }

    private func update(loading: Bool) {
        hideTask?.cancel()
        hideTask = nil
        if loading {
            if !showing {
                shownAt = Date()
                showing = true
            }
            return
        }
        let hold = NoopSkeletonTiming.remainingHold(shownAt: shownAt, now: Date())
        guard hold > 0 else {
            showing = false
            shownAt = nil
            return
        }
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
            guard !Task.isCancelled else { return }
            showing = false
            shownAt = nil
        }
    }
}

public extension View {
    /// While `isLoading`, hides the content (keeping its layout) and draws a card-shaped shimmer with faint
    /// text bars in its place. Once shown, the skeleton stays for at least
    /// `NoopTheme.Motion.skeletonMinimum` so it never flickers. Static under Reduce Motion.
    func noopSkeleton(_ isLoading: Bool, cornerRadius: CGFloat = NoopTheme.Layout.cardRadius) -> some View {
        modifier(NoopSkeletonModifier(isLoading: isLoading, cornerRadius: cornerRadius))
    }
}

#if DEBUG
private struct NoopSkeletonPreview: View {
    @State private var loading = true

    var body: some View {
        VStack(spacing: NoopTheme.Layout.cardGap) {
            NoopGlassCard {
                VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                    Text(verbatim: "Key metrics").noopFont(.sectionTitle)
                    Text(verbatim: "HRV 62 ms · Resting HR 52 bpm").noopFont(.footnote)
                    Text(verbatim: "Computed on iPhone").noopFont(.caption)
                }
            }
            .noopSkeleton(loading)

            NoopTile {
                Text(verbatim: "Steps").noopFont(.rowTitle)
            }
            .noopSkeleton(loading, cornerRadius: NoopTheme.Layout.tileRadius)

            Button { loading.toggle() } label: {
                Text(verbatim: loading ? "Finish loading" : "Load again")
            }
            .buttonStyle(NoopSecondaryButton())
        }
        .padding(NoopTheme.Layout.gutter)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(NoopTheme.canvas)
    }
}

#Preview("NoopSkeleton") {
    NoopSkeletonPreview()
}
#endif
