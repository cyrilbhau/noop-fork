import SwiftUI

// MARK: - Entrance and press motion (docs/personal/REDESIGN-IMPLEMENTATION.md §3.5, §3.6 item 8)

private struct NoopEntranceModifier: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        // Under Reduce Motion the card only fades: no rise, no scale.
        let moving = !shown && !reduceMotion
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(moving ? NoopTheme.Motion.entranceScale : 1)
            .offset(y: moving ? NoopTheme.Motion.entranceRise : 0)
            .onAppear {
                guard !shown else { return }
                let animation = reduceMotion
                    ? NoopTheme.Motion.reduced
                    : NoopTheme.Motion.entrance.delay(Double(max(0, index)) * NoopTheme.Motion.entranceStagger)
                withAnimation(animation) { shown = true }
            }
    }
}

public extension View {
    /// Staggered card entrance: rises `NoopTheme.Motion.entranceRise`, scales 0.98 → 1 and fades in with the
    /// entrance spring, delayed `index × entranceStagger` (top to bottom). Under Reduce Motion it is a 0.15 s
    /// fade with no delay. Runs once per appearance of the view.
    func noopEntrance(index: Int) -> some View {
        modifier(NoopEntranceModifier(index: index))
    }
}

/// Press feedback for tappable cards, tiles, pills and icon buttons: scales to
/// `NoopTheme.Motion.pressScale` on touch-down and springs back. Under Reduce Motion it dims instead.
public struct NoopPressStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        NoopPressBody(configuration: configuration)
    }
}

/// Opacity a pressed control dims to under Reduce Motion. No `NoopTheme` token yet.
let noopPressedDimOpacity: Double = 0.6

private struct NoopPressBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .scaleEffect(pressed && !reduceMotion ? NoopTheme.Motion.pressScale : 1)
            .opacity(pressed && reduceMotion ? noopPressedDimOpacity : 1)
            .animation(
                reduceMotion ? NoopTheme.Motion.reduced : (pressed ? NoopTheme.Motion.pressDown : NoopTheme.Motion.pressUp),
                value: pressed
            )
    }
}

public extension ButtonStyle where Self == NoopPressStyle {
    /// `.buttonStyle(.noopPress)`.
    static var noopPress: NoopPressStyle { NoopPressStyle() }
}

#if DEBUG
#Preview("NoopEntrance / NoopPressStyle") {
    ScrollView {
        VStack(spacing: NoopTheme.Layout.cardGap) {
            ForEach(0..<6, id: \.self) { index in
                Button {} label: {
                    NoopGlassCard {
                        Text(verbatim: "Card \(index + 1)").noopFont(.rowTitle)
                    }
                }
                .buttonStyle(.noopPress)
                .noopEntrance(index: index)
            }
        }
        .padding(NoopTheme.Layout.gutter)
    }
    .background(NoopTheme.canvas)
}
#endif
