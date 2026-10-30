import SwiftUI

/// Static counterparts of the app's ambient field for WidgetKit. There are no appearance-driven
/// animations, materials or image assets: every timeline entry renders its finished artwork at once.
public enum NoopWidgetArt {
    public static let smallRing: CGFloat = 46
    public static let mediumRing: CGFloat = 68
    public static let largeRing: CGFloat = 84
    public static let ringWidth: CGFloat = 5
    public static let largeRingWidth: CGFloat = 6
    public static let timestamp = NoopTheme.textPrimary.opacity(0.62)
    public static let caption = NoopTheme.textPrimary.opacity(0.82)
}

/// A compact ambient composition: score-coloured light over graphite, with flowing contour artwork.
/// Callers supply neutral colours for missing scores, so the illustration never implies a good band.
public struct NoopWidgetBackdrop: View {
    private let colors: [Color]
    @Environment(\.colorSchemeContrast) private var contrast

    public init(colors: [Color]) {
        self.colors = colors
    }

    public var body: some View {
        ZStack {
            LinearGradient(colors: [NoopTheme.sheet, NoopTheme.cardSolid, NoopTheme.canvas],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if contrast != .increased {
                Canvas { context, size in
                    let bounds = Path(CGRect(origin: .zero, size: size))
                    for (index, color) in colors.enumerated() {
                        let x = (CGFloat(index) + 0.5) / CGFloat(max(1, colors.count))
                        context.fill(bounds, with: .radialGradient(
                            Gradient(stops: [
                                .init(color: color.opacity(0.36), location: 0),
                                .init(color: color.opacity(0.14), location: 0.48),
                                .init(color: color.opacity(0), location: 1)
                            ]),
                            center: CGPoint(x: size.width * x, y: size.height * 0.18),
                            startRadius: 0, endRadius: size.width * 0.64))
                    }
                    // Sweeping lines echo the app's ambient texture without competing with the scores.
                    for index in 0..<8 {
                        let offset = CGFloat(index) * size.height * 0.065
                        var contour = Path()
                        contour.move(to: CGPoint(x: -size.width * 0.15, y: size.height * 0.52 + offset))
                        contour.addCurve(
                            to: CGPoint(x: size.width * 1.12, y: size.height * 0.70 + offset),
                            control1: CGPoint(x: size.width * 0.28, y: size.height * 1.22 + offset),
                            control2: CGPoint(x: size.width * 0.54, y: -size.height * 0.14 + offset))
                        context.stroke(contour, with: .linearGradient(
                            Gradient(colors: [NoopTheme.sleep.opacity(0.04),
                                              NoopTheme.textPrimary.opacity(0.10),
                                              NoopTheme.strain.opacity(0.07)]),
                            startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)),
                            lineWidth: 0.6)
                    }
                }
                LinearGradient(colors: [NoopTheme.canvas.opacity(0), NoopTheme.canvas.opacity(0.32)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A finished, dimensional score ring for widgets. The inset contains the stroke within its frame.
/// Missing scores remain dashed, while a measured zero retains its round-cap bead.
public struct NoopWidgetScoreRing: View {
    private let fraction: Double?
    private let tint: Color
    private let diameter: CGFloat
    private let lineWidth: CGFloat
    private let decorated: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    public init(fraction: Double?, tint: Color, diameter: CGFloat, lineWidth: CGFloat,
                decorated: Bool = true) {
        self.fraction = NoopRing.clampedFraction(fraction)
        self.tint = tint
        self.diameter = diameter
        self.lineWidth = lineWidth
        self.decorated = decorated
    }

    public var body: some View {
        ZStack {
            if let fraction {
                if decorated && contrast != .increased {
                    Circle()
                        .fill(RadialGradient(colors: [tint.opacity(0.12), tint.opacity(0)],
                                             center: .center, startRadius: 0, endRadius: diameter / 2))
                    Circle()
                        .inset(by: lineWidth * 1.7)
                        .stroke(tint.opacity(0.13), lineWidth: 0.5)
                }
                Circle()
                    .inset(by: lineWidth / 2)
                    .stroke(NoopTheme.track, lineWidth: lineWidth)
                Circle()
                    .inset(by: lineWidth / 2)
                    .trim(from: 0, to: max(0.0001, fraction))
                    .stroke(AngularGradient(
                        colors: decorated
                            ? [tint.opacity(0.65), tint, tint,
                               StrandPalette.sample(stops: [.init(color: tint, location: 0),
                                                            .init(color: NoopTheme.textPrimary, location: 1)],
                                                    at: 0.32)]
                            : [tint, tint],
                        center: .center, startAngle: .degrees(0), endAngle: .degrees(360)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                Circle()
                    .inset(by: lineWidth / 2)
                    .stroke(NoopTheme.trackEmpty,
                            style: StrokeStyle(lineWidth: NoopRing.missingLineWidth(lineWidth: lineWidth),
                                               dash: NoopRing.dashPattern(diameter: diameter)))
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

#Preview("Widget artwork") {
    let fractions = [0.81, 0.68, 0.21]
    let colors = [NoopTheme.sleep, NoopTheme.recovery, NoopTheme.strain]
    HStack(spacing: NoopTheme.Layout.xl) {
        ForEach(fractions.indices, id: \.self) { index in
            NoopWidgetScoreRing(fraction: fractions[index], tint: colors[index],
                                diameter: NoopWidgetArt.mediumRing, lineWidth: NoopWidgetArt.ringWidth)
        }
    }
    .padding(NoopTheme.Layout.cardPadding)
    .background(NoopWidgetBackdrop(colors: [NoopTheme.sleep, NoopTheme.recovery, NoopTheme.strain]))
    .clipShape(RoundedRectangle(cornerRadius: NoopTheme.Layout.widgetRadius))
    .padding()
    .background(NoopTheme.canvas)
}
