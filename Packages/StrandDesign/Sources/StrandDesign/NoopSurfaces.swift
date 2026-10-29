import SwiftUI

// MARK: - Surfaces and controls (docs/personal/REDESIGN-IMPLEMENTATION.md §3.4, §3.6 items 6 and 9)
//
// The redesign's cards, tiles, headers, pills and buttons, drawn only from `NoopTheme` / `NoopType`. Names
// avoid the existing `NoopCard` / `SectionHeader` / `NoopPrimaryButtonStyle` in `Components.swift`, which
// unmigrated screens still use. Labels are supplied by callers; the package carries no copy.

/// Component geometry from `design/system/noop.css` that has no `NoopTheme` token yet.
private enum SurfaceMetrics {
    /// `.icon.sm`: the small domain icon tile.
    static let smallIconTile: CGFloat = 32
    /// Symbol size relative to its domain icon tile.
    static let iconSymbolRatio: CGFloat = 0.46
    /// Symbol size inside a round icon button.
    static let iconButtonSymbol: CGFloat = 17
    static let pillHorizontalPadding: CGFloat = 12
    static let pillGap: CGFloat = 6
    static let dot: CGFloat = 7
    static let sourceDot: CGFloat = 5
    static let sourceGap: CGFloat = 5
    static let chipVerticalPadding: CGFloat = 8
    /// `.seg`: track inset, track radius, segment radius and segment vertical padding.
    static let segmentInset: CGFloat = 2
    static let segmentTrackRadius: CGFloat = 10
    static let segmentRadius: CGFloat = 8
    static let segmentVerticalPadding: CGFloat = 7
    /// `.seg` track (`rgba(118,118,128,.24)`) and selected segment (white 16 %).
    static let segmentTrack = Color(red: 118 / 255, green: 118 / 255, blue: 128 / 255).opacity(0.24)
    static let segmentSelected = Color.white.opacity(0.16)
    static let headerChevronGap: CGFloat = 4
    /// Domain icon tile background: the domain colour at this opacity.
    static let iconTintOpacity: Double = 0.14
    static let disabledOpacity: Double = 0.4
}

// MARK: - Glass background

private struct NoopGlassBackground: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(NoopTheme.card)
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(NoopTheme.cardBorder, lineWidth: 1))
    }
}

public extension View {
    /// The redesign's card surface: `NoopTheme.card` over an ultra-thin material, a 1 pt `cardBorder`, clipped
    /// to a continuous rounded rectangle.
    func noopGlassBackground(cornerRadius: CGFloat = NoopTheme.Layout.cardRadius) -> some View {
        modifier(NoopGlassBackground(radius: cornerRadius))
    }
}

// MARK: - Card and tile

/// A redesign card: glass surface, radius 22, padding 18. `flush` is the list-card variant (4 pt vertical,
/// 18 pt horizontal) for stacks of `NoopMetricRow` / `NoopListRow`, which carry their own vertical padding.
public struct NoopGlassCard<Content: View>: View {
    private let flush: Bool
    private let content: Content

    public init(flush: Bool = false, @ViewBuilder content: () -> Content) {
        self.flush = flush
        self.content = content()
    }

    public var body: some View {
        let vertical = flush ? NoopTheme.Layout.xs : NoopTheme.Layout.cardPadding
        content
            .padding(.vertical, vertical)
            .padding(.horizontal, NoopTheme.Layout.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .noopGlassBackground(cornerRadius: NoopTheme.Layout.cardRadius)
    }
}

/// A grid tile: glass surface, radius 20, padding 16, at least 150 pt tall, content top-leading.
public struct NoopTile<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(NoopTheme.Layout.l)
            .frame(maxWidth: .infinity, minHeight: NoopTheme.Layout.tileMinHeight, alignment: .topLeading)
            .noopGlassBackground(cornerRadius: NoopTheme.Layout.tileRadius)
    }
}

// MARK: - Section header

/// A sentence-case section title with an optional trailing link ("See all ›"). Padding 26 top, 10 bottom,
/// 20 sides, measured from the screen edge, so place it outside the screen gutter. Never uppercased, even
/// inside a `List` section.
public struct NoopSectionHeader: View {
    private let title: LocalizedStringKey
    private let linkTitle: LocalizedStringKey?
    private let action: (() -> Void)?

    public init(_ title: LocalizedStringKey, linkTitle: LocalizedStringKey? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.linkTitle = linkTitle
        self.action = action
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .noopFont(.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: NoopTheme.Layout.s)
            if let linkTitle, let action {
                Button(action: action) {
                    HStack(spacing: SurfaceMetrics.headerChevronGap) {
                        Text(linkTitle)
                            .noopFont(.bodySmall, color: false)
                            .foregroundStyle(NoopTheme.textSecondary)
                        Image(systemName: "chevron.right")
                            .noopFont(.footnote, color: false)
                            .fontWeight(.semibold)
                            .foregroundStyle(NoopTheme.textTertiary)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: NoopTheme.Layout.minTouchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.noopPress)
            }
        }
        .textCase(nil)
        .padding(.top, NoopTheme.Layout.sectionTop)
        .padding(.bottom, NoopTheme.Layout.sectionBottom)
        .padding(.horizontal, NoopTheme.Layout.sectionSide)
    }
}

// MARK: - Source caption

/// The provenance line under a card: a small tertiary dot and a caption
/// ("Computed on iPhone · synced 6:12 AM", supplied by the caller).
public struct SourceCaption: View {
    private let text: Text

    public init(_ key: LocalizedStringKey) {
        self.text = Text(key)
    }

    /// For an already-localized, composed string.
    public init(verbatim string: String) {
        self.text = Text(verbatim: string)
    }

    public var body: some View {
        HStack(spacing: SurfaceMetrics.sourceGap) {
            Circle()
                .fill(NoopTheme.textTertiary)
                .frame(width: SurfaceMetrics.sourceDot, height: SurfaceMetrics.sourceDot)
                .accessibilityHidden(true)
            text.noopFont(.caption)
        }
    }
}

// MARK: - Pill and chip

/// A 32 pt capsule on the control fill with an optional leading SF Symbol or coloured dot (status, date,
/// strap). Wrap in a `Button` with `.buttonStyle(.noopPress)` when tappable.
public struct NoopPill: View {
    private let title: Text
    private let systemImage: String?
    private let dot: Color?
    private let tint: Color

    public init(_ title: LocalizedStringKey, systemImage: String? = nil, dot: Color? = nil, tint: Color = NoopTheme.textPrimary) {
        self.title = Text(title)
        self.systemImage = systemImage
        self.dot = dot
        self.tint = tint
    }

    /// For an already-localized or formatted value ("82%", "Wed 29").
    public init(verbatim title: String, systemImage: String? = nil, dot: Color? = nil, tint: Color = NoopTheme.textPrimary) {
        self.title = Text(verbatim: title)
        self.systemImage = systemImage
        self.dot = dot
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: SurfaceMetrics.pillGap) {
            if let dot {
                Circle().fill(dot)
                    .frame(width: SurfaceMetrics.dot, height: SurfaceMetrics.dot)
                    .accessibilityHidden(true)
            }
            if let systemImage {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            title
        }
        .noopFont(.pill, color: false)
        .foregroundStyle(tint)
        .padding(.horizontal, SurfaceMetrics.pillHorizontalPadding)
        .frame(minHeight: NoopTheme.Layout.pillHeight)
        .background {
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(NoopTheme.control)
            }
        }
        .clipShape(Capsule())
    }
}

/// A selectable suggestion/filter chip on the control fill; selected chips take the selected-segment fill.
public struct NoopChip: View {
    private let title: Text
    private let systemImage: String?
    private let isSelected: Bool

    public init(_ title: LocalizedStringKey, systemImage: String? = nil, isSelected: Bool = false) {
        self.title = Text(title)
        self.systemImage = systemImage
        self.isSelected = isSelected
    }

    public init(verbatim title: String, systemImage: String? = nil, isSelected: Bool = false) {
        self.title = Text(verbatim: title)
        self.systemImage = systemImage
        self.isSelected = isSelected
    }

    public var body: some View {
        HStack(spacing: SurfaceMetrics.pillGap) {
            if let systemImage {
                Image(systemName: systemImage).accessibilityHidden(true)
            }
            title.lineLimit(1)
        }
        .noopFont(.chip, color: false)
        .foregroundStyle(NoopTheme.textPrimary)
        .padding(.vertical, SurfaceMetrics.chipVerticalPadding)
        .padding(.horizontal, SurfaceMetrics.pillHorizontalPadding)
        .background(Capsule().fill(isSelected ? SurfaceMetrics.segmentSelected : NoopTheme.control))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Segmented pills

/// A compact segmented control (D / W / M / 6M / Y): grey track, the selected segment on a white-16 % fill.
public struct SegmentedPills<Option: Hashable>: View {
    private let options: [Option]
    @Binding private var selection: Option
    private let label: (Option) -> Text
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionSpace

    public init(_ options: [Option], selection: Binding<Option>, label: @escaping (Option) -> Text) {
        self.options = options
        self._selection = selection
        self.label = label
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    withAnimation(NoopTheme.Motion.resolved(NoopTheme.Motion.pressUp, reduceMotion: reduceMotion)) {
                        selection = option
                    }
                } label: {
                    label(option)
                        .noopFont(.pill, color: false)
                        .foregroundStyle(selected ? NoopTheme.textPrimary : NoopTheme.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SurfaceMetrics.segmentVerticalPadding)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: SurfaceMetrics.segmentRadius, style: .continuous)
                                    .fill(SurfaceMetrics.segmentSelected)
                                    .matchedGeometryEffect(id: "selection", in: selectionSpace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(SurfaceMetrics.segmentInset)
        .background(
            RoundedRectangle(cornerRadius: SurfaceMetrics.segmentTrackRadius, style: .continuous)
                .fill(SurfaceMetrics.segmentTrack)
        )
    }
}

// MARK: - Domain icon

/// A domain icon tile: the SF Symbol in the domain colour on that colour at 14 %. 42 pt (radius 13) by
/// default; pass `DomainIcon.smallSize` for the 32 pt list variant. The corner radius scales with size.
public struct DomainIcon: View {
    /// The small (list row) variant's size.
    public static let smallSize: CGFloat = SurfaceMetrics.smallIconTile

    private let systemImage: String
    private let color: Color
    private let size: CGFloat

    public init(systemImage: String, color: Color, size: CGFloat = NoopTheme.Layout.iconTile) {
        self.systemImage = systemImage
        self.color = color
        self.size = size
    }

    public var body: some View {
        let radius = NoopTheme.Layout.iconTileRadius * size / NoopTheme.Layout.iconTile
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(color.opacity(SurfaceMetrics.iconTintOpacity))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: size * SurfaceMetrics.iconSymbolRatio, weight: .semibold))
                    .foregroundStyle(color)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Icon button

/// A 40 pt round icon button on the control fill, with a hit area of at least 44 pt.
public struct NoopIconButton: View {
    private let systemImage: String
    private let accessibilityLabel: LocalizedStringKey
    private let action: () -> Void

    public init(systemImage: String, accessibilityLabel: LocalizedStringKey, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: SurfaceMetrics.iconButtonSymbol, weight: .semibold))
                .foregroundStyle(NoopTheme.textPrimary)
                .frame(width: NoopTheme.Layout.iconButton, height: NoopTheme.Layout.iconButton)
                .background {
                    ZStack {
                        Circle().fill(.ultraThinMaterial)
                        Circle().fill(NoopTheme.control)
                    }
                }
                .clipShape(Circle())
                .frame(width: NoopTheme.Layout.minTouchTarget, height: NoopTheme.Layout.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.noopPress)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

// MARK: - Capsule buttons

/// The redesign's primary action: a full-width 52 pt capsule, near-white fill, black label.
/// (Distinct from the gold `NoopPrimaryButtonStyle` used by unmigrated screens.)
public struct NoopPrimaryButton: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        NoopCapsuleButtonBody(configuration: configuration, fill: NoopTheme.textPrimary, ink: NoopTheme.canvas)
    }
}

/// The redesign's secondary action: a full-width 52 pt capsule on the control fill.
public struct NoopSecondaryButton: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        NoopCapsuleButtonBody(configuration: configuration, fill: NoopTheme.control, ink: NoopTheme.textPrimary)
    }
}

private struct NoopCapsuleButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let fill: Color
    let ink: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .noopFont(.button, color: false)
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, minHeight: NoopTheme.Layout.buttonHeight)
            .padding(.horizontal, NoopTheme.Layout.xl)
            .background(Capsule().fill(fill))
            .contentShape(Capsule())
            .opacity(isEnabled ? (pressed && reduceMotion ? noopPressedDimOpacity : 1) : SurfaceMetrics.disabledOpacity)
            .scaleEffect(pressed && !reduceMotion ? NoopTheme.Motion.pressScale : 1)
            .animation(
                reduceMotion ? NoopTheme.Motion.reduced : (pressed ? NoopTheme.Motion.pressDown : NoopTheme.Motion.pressUp),
                value: pressed
            )
    }
}

#if DEBUG
private struct NoopSurfacesPreview: View {
    @State private var range = "W"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                NoopSectionHeader("Key metrics", linkTitle: "See all", action: {})
                VStack(spacing: NoopTheme.Layout.cardGap) {
                    NoopGlassCard {
                        VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                            Text(verbatim: "Recovered").noopFont(.screenHeadline)
                            SourceCaption(verbatim: "Computed on iPhone · synced 6:12 AM")
                        }
                    }
                    HStack(spacing: NoopTheme.Layout.cardGap) {
                        NoopTile {
                            VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                                DomainIcon(systemImage: "heart.fill", color: NoopTheme.heart)
                                Text(verbatim: "52").noopFont(.tileNumber)
                            }
                        }
                        NoopTile {
                            DomainIcon(systemImage: "figure.walk", color: NoopTheme.lift, size: DomainIcon.smallSize)
                        }
                    }
                    HStack(spacing: NoopTheme.Layout.s) {
                        NoopPill(verbatim: "82%", systemImage: "battery.75")
                        NoopPill(verbatim: "Connected", dot: NoopTheme.recovery)
                        NoopIconButton(systemImage: "slider.horizontal.3", accessibilityLabel: "Customise") {}
                    }
                    HStack(spacing: NoopTheme.Layout.s) {
                        NoopChip(verbatim: "How did I sleep?")
                        NoopChip(verbatim: "Selected", systemImage: "checkmark", isSelected: true)
                    }
                    SegmentedPills(["D", "W", "M", "6M", "Y"], selection: $range) { Text(verbatim: $0) }
                    Button {} label: { Text(verbatim: "Save workout") }
                        .buttonStyle(NoopPrimaryButton())
                    Button {} label: { Text(verbatim: "Cancel") }
                        .buttonStyle(NoopSecondaryButton())
                }
                .padding(.horizontal, NoopTheme.Layout.gutter)
            }
        }
        .background(NoopTheme.canvas)
    }
}

#Preview("Noop surfaces") {
    NoopSurfacesPreview()
}
#endif
