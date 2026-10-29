#if os(iOS)
import SwiftUI
import StrandDesign

// Shared pieces for the redesigned Coach, Profile and settings screens (`docs/personal/REDESIGN-IMPLEMENTATION.md`
// Phase 7, mockups D1–D6, A6, C1, E3): the grouped-row card, toggle and control rows, the large screen title,
// the fixed ambient wash, and the redesign text-field surface. Presentation only: every row is handed its
// binding or action by the screen that owns the behaviour.
//
// Layout follows the mockups' column: section headers (`NoopSectionHeader`) carry their own screen-edge
// padding, cards take `NoopTheme.Layout.gutter`. Names carry a `FormKit` prefix so the i18n audit, which
// keys localising helpers by NAME repo-wide, never mistakes an unrelated same-named call for one of these.

/// Geometry from `design/round3/coach-profile.html` with no `NoopTheme` token.
enum FormKitLayout {
    /// `.lrow` vertical padding (12 pt in the mockup).
    static let rowVertical: CGFloat = 12
    /// Gap between a row title and its detail line.
    static let detailGap: CGFloat = 2
    /// Large-title block: gap between the title and its subtitle.
    static let titleGap: CGFloat = 2
    /// The text-field surface radius (the mockup's inputs and the redesign's 14 pt control radius).
    static let fieldRadius: CGFloat = 14
    static let fieldHorizontal: CGFloat = 14
    static let fieldVertical: CGFloat = 11
    /// Hairline weight.
    static let hairline: CGFloat = 1
    /// Badge (`.badge`): horizontal and vertical padding and tint strength.
    static let badgeHorizontal: CGFloat = 8
    static let badgeVertical: CGFloat = 3
    static let badgeTint: Double = 0.16
    /// Symbol size inside a round 40 pt icon button (matches `NoopIconButton`).
    static let iconSymbol: CGFloat = 17
}

// MARK: - Ambient

/// The fixed ambient palette of a Phase 7 screen, at the intensity chosen in Settings. Fixed palettes are
/// not score-driven, so "Colour from your scores" does not switch them off (same as the Sleep and Training
/// screens); the intensity still scales them.
private struct FormKitAmbient: ViewModifier {
    let preset: AmbientPreset
    @AppStorage(NoopTheme.Keys.ambientIntensity) private var intensityRaw = AmbientIntensity.balanced.rawValue

    func body(content: Content) -> some View {
        content.noopAmbientBackground(preset.blobs(intensity: AmbientIntensity(rawValue: intensityRaw) ?? .balanced))
    }
}

extension View {
    /// Black canvas plus the preset's ambient wash behind the top of the screen.
    func formKitAmbient(_ preset: AmbientPreset) -> some View {
        modifier(FormKitAmbient(preset: preset))
    }

    /// The redesign text-field surface: control fill, hairline border, 14 pt radius.
    func formKitField() -> some View {
        let shape = RoundedRectangle(cornerRadius: FormKitLayout.fieldRadius, style: .continuous)
        return self
            .noopFont(.body, color: false)
            .foregroundStyle(NoopTheme.textPrimary)
            .padding(.horizontal, FormKitLayout.fieldHorizontal)
            .padding(.vertical, FormKitLayout.fieldVertical)
            .background(shape.fill(NoopTheme.control))
            .overlay(shape.strokeBorder(NoopTheme.cardBorder, lineWidth: FormKitLayout.hairline))
    }

    /// Screen-edge gutter for a card in the Phase 7 column.
    func formKitGutter() -> some View {
        padding(.horizontal, NoopTheme.Layout.gutter)
    }
}

// MARK: - Title

/// The mockups' large title block (`.lt` + `.sub`), padded to the screen gutter.
struct FormKitTitle: View {
    private let title: LocalizedStringKey
    private let subtitle: LocalizedStringKey?

    init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FormKitLayout.titleGap) {
            Text(title)
                .noopFont(.largeTitle)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .noopFont(.bodySmall, color: false)
                    .foregroundStyle(NoopTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, NoopTheme.Layout.gutter)
    }
}

// MARK: - Card and rows

/// A flush glass card holding a column of rows (`.card.flush`).
struct FormKitCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        NoopGlassCard(flush: true) {
            VStack(alignment: .leading, spacing: 0) {
                content
            }
        }
        .formKitGutter()
    }
}

/// The 1 pt separator between rows of a card.
struct FormKitDivider: View {
    var body: some View {
        Rectangle()
            .fill(NoopTheme.separator)
            .frame(height: FormKitLayout.hairline)
            .accessibilityHidden(true)
    }
}

/// A row with a title, an optional detail line and a trailing control (a toggle, a menu picker, a value).
/// `showsDivider` draws the hairline ABOVE the row; pass false for the first row in a card.
struct FormKitControlRow<Control: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let title: Text
    private let detail: Text?
    private let titleColor: Color
    private let showsDivider: Bool
    private let control: Control

    init(_ title: LocalizedStringKey,
         detail: LocalizedStringKey? = nil,
         titleColor: Color = NoopTheme.textPrimary,
         showsDivider: Bool = true,
         @ViewBuilder control: () -> Control) {
        self.title = Text(title)
        self.detail = detail.map { Text($0) }
        self.titleColor = titleColor
        self.showsDivider = showsDivider
        self.control = control()
    }

    /// For rows whose title or detail is already a resolved (runtime) string.
    init(verbatimTitle: String,
         detail: String? = nil,
         titleColor: Color = NoopTheme.textPrimary,
         showsDivider: Bool = true,
         @ViewBuilder control: () -> Control) {
        self.title = Text(verbatim: verbatimTitle)
        self.detail = detail.map { Text(verbatim: $0) }
        self.titleColor = titleColor
        self.showsDivider = showsDivider
        self.control = control()
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsDivider { FormKitDivider() }
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: NoopTheme.Layout.s))
                : AnyLayout(HStackLayout(spacing: NoopTheme.Layout.m))
            layout {
                VStack(alignment: .leading, spacing: FormKitLayout.detailGap) {
                    title
                        .noopFont(.listTitle, color: false)
                        .foregroundStyle(titleColor)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        detail
                            .noopFont(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                control
            }
            .padding(.vertical, FormKitLayout.rowVertical)
            .frame(minHeight: NoopTheme.Layout.minTouchTarget)
        }
    }
}

/// A toggle row (`.lrow` + `.toggle`). The switch tints with the Recovery green, as in the mockups.
struct FormKitToggleRow: View {
    private let title: LocalizedStringKey
    private let detail: LocalizedStringKey?
    @Binding private var isOn: Bool
    private let showsDivider: Bool

    init(_ title: LocalizedStringKey, detail: LocalizedStringKey? = nil, isOn: Binding<Bool>, showsDivider: Bool = true) {
        self.title = title
        self.detail = detail
        self._isOn = isOn
        self.showsDivider = showsDivider
    }

    var body: some View {
        FormKitControlRow(title, detail: detail, showsDivider: showsDivider) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(NoopTheme.recovery)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The trailing grey value text of a row (`.lrow .val`).
struct FormKitValue: View {
    private let text: Text

    init(_ key: LocalizedStringKey) { text = Text(key) }
    init(verbatim: String) { text = Text(verbatim: verbatim) }

    var body: some View {
        text
            .noopFont(.bodySmall, color: false)
            .foregroundStyle(NoopTheme.textSecondary)
            .multilineTextAlignment(.trailing)
    }
}

/// A trailing chevron for a row that pushes or opens something.
struct FormKitChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .noopFont(.footnote, color: false)
            .fontWeight(.semibold)
            .foregroundStyle(NoopTheme.textTertiary)
            .accessibilityHidden(true)
    }
}

/// A small status badge (`.badge`): tinted capsule with a short label.
struct FormKitBadge: View {
    private let text: Text
    private let tint: Color

    init(_ key: LocalizedStringKey, tint: Color) {
        self.text = Text(key)
        self.tint = tint
    }

    init(verbatim: String, tint: Color) {
        self.text = Text(verbatim: verbatim)
        self.tint = tint
    }

    var body: some View {
        text
            .noopFont(.caption, color: false)
            .fontWeight(.semibold)
            .foregroundStyle(tint)
            .padding(.horizontal, FormKitLayout.badgeHorizontal)
            .padding(.vertical, FormKitLayout.badgeVertical)
            .background(Capsule().fill(tint.opacity(FormKitLayout.badgeTint)))
    }
}

/// The round 40 pt icon-button face (`NoopIconButton`'s look) for controls that are not a plain button,
/// such as a `Menu` label. Keeps the 44 pt hit area.
struct FormKitIconFace: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: FormKitLayout.iconSymbol, weight: .semibold))
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
}

/// Footnote copy under a card, aligned with card content from a full-bleed parent.
struct FormKitFootnote: View {
    private let text: Text

    init(_ key: LocalizedStringKey) { text = Text(key) }
    init(verbatim: String) { text = Text(verbatim: verbatim) }

    var body: some View {
        text
            .noopFont(.footnote)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, NoopTheme.Layout.gutter + NoopTheme.Layout.captionInset)
            .padding(.top, NoopTheme.Layout.m)
    }
}
#endif
