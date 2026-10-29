import SwiftUI

/// The redesign's type ramp (`docs/personal/REDESIGN-IMPLEMENTATION.md` §3.3). SF Pro default design (not
/// rounded). Every style scales with Dynamic Type through `@ScaledMetric`, relative to the closest system
/// text style, and numerals use monospaced digits.
public enum NoopType: CaseIterable, Sendable {
    case largeTitle
    case screenHeadline
    case sectionTitle
    case rowTitle
    case body
    case bodySmall
    case footnote
    case caption
    case heroNumber
    case bigNumber
    case tileNumber
    case rowNumber
    case statNumber
    case unit
    case navTitle
    case listTitle
    case pill
    /// Capsule buttons (17 semibold).
    case button
    /// Chips (14 medium).
    case chip
    /// Widgets and Live Activities: deliberately thinner numerals.
    case widgetNumber
    case widgetLabel
    case widgetCaption

    public var size: CGFloat {
        switch self {
        case .largeTitle: return 34
        case .screenHeadline: return 30
        case .sectionTitle: return 20
        case .rowTitle: return 15
        case .body: return 17
        case .bodySmall: return 15
        case .footnote: return 13
        case .caption: return 12
        case .heroNumber: return 84
        case .bigNumber: return 48
        case .tileNumber: return 40
        case .rowNumber: return 22
        case .statNumber: return 24
        case .unit: return 13
        case .navTitle: return 17
        case .listTitle: return 16
        case .pill: return 13
        case .button: return 17
        case .chip: return 14
        case .widgetNumber: return 42
        case .widgetLabel: return 12
        case .widgetCaption: return 12
        }
    }

    public var weight: Font.Weight {
        switch self {
        case .largeTitle, .screenHeadline, .heroNumber: return .bold
        case .sectionTitle, .rowTitle, .bigNumber, .tileNumber, .rowNumber, .statNumber, .navTitle, .pill, .button:
            return .semibold
        case .listTitle, .caption, .widgetLabel, .chip: return .medium
        case .body, .bodySmall, .footnote, .unit, .widgetCaption: return .regular
        case .widgetNumber: return .light
        }
    }

    /// Letter spacing in points.
    public var tracking: CGFloat {
        switch self {
        case .largeTitle, .screenHeadline: return -0.6
        case .sectionTitle: return -0.3
        case .heroNumber: return -4
        case .bigNumber: return -1.5
        case .tileNumber: return -1.2
        case .statNumber: return -0.5
        case .widgetNumber: return -1.4
        default: return 0
        }
    }

    /// Extra line spacing (only body copy sets one: 24 pt line height on 17 pt text).
    public var lineSpacing: CGFloat {
        self == .body ? 24 - 17 * 1.19 : 0
    }

    /// The default colour for the style. Views may override with `.foregroundStyle`.
    public var defaultColor: Color {
        switch self {
        case .body, .footnote, .unit: return NoopTheme.textSecondary
        case .caption: return NoopTheme.textTertiary
        case .widgetCaption: return Color.white.opacity(0.5)
        default: return NoopTheme.textPrimary
        }
    }

    public var isNumeric: Bool {
        switch self {
        case .heroNumber, .bigNumber, .tileNumber, .rowNumber, .statNumber, .widgetNumber: return true
        default: return false
        }
    }

    /// The system text style Dynamic Type scaling is relative to.
    public var relativeTo: Font.TextStyle {
        switch self {
        case .largeTitle, .heroNumber, .bigNumber, .tileNumber, .widgetNumber: return .largeTitle
        case .screenHeadline: return .title
        case .sectionTitle, .statNumber, .rowNumber: return .title3
        case .rowTitle, .listTitle, .navTitle, .bodySmall, .chip: return .subheadline
        case .button: return .body
        case .body: return .body
        case .footnote, .unit, .pill: return .footnote
        case .caption, .widgetLabel, .widgetCaption: return .caption
        }
    }

    /// A non-scaling font at the style's base size. Prefer `.noopFont(_:)`, which scales.
    public var fixedFont: Font {
        let f = Font.system(size: size, weight: weight, design: .default)
        return isNumeric ? f.monospacedDigit() : f
    }

    /// Font for a ring label: ring diameter × 0.25, semibold.
    public static func ringLabelFont(diameter: CGFloat) -> Font {
        Font.system(size: max(9, diameter * 0.25), weight: .semibold, design: .default).monospacedDigit()
    }

    /// Font for the unit under a ring label: ring diameter × 0.13, regular.
    public static func ringUnitFont(diameter: CGFloat) -> Font {
        Font.system(size: max(7, diameter * 0.13), weight: .regular, design: .default)
    }
}

private struct NoopFontModifier: ViewModifier {
    let style: NoopType
    let applyColor: Bool
    @ScaledMetric private var size: CGFloat

    init(style: NoopType, applyColor: Bool) {
        self.style = style
        self.applyColor = applyColor
        _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.relativeTo)
    }

    func body(content: Content) -> some View {
        let font = Font.system(size: size, weight: style.weight, design: .default)
        let styled = content
            .font(style.isNumeric ? font.monospacedDigit() : font)
            .tracking(style.tracking * size / style.size)
            .lineSpacing(style.lineSpacing)
        if applyColor {
            styled.foregroundStyle(style.defaultColor)
        } else {
            styled
        }
    }
}

public extension View {
    /// Applies a redesign type style: Dynamic-Type-scaled size, weight, tracking and (by default) its colour.
    func noopFont(_ style: NoopType, color: Bool = true) -> some View {
        modifier(NoopFontModifier(style: style, applyColor: color))
    }
}
