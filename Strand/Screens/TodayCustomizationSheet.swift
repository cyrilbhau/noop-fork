import SwiftUI
import StrandDesign

// MARK: - Unified Today customization

/// Every Today editing entry point presents the same sheet and optionally deep-links to one child editor.
enum TodayCustomizationDestination: String, Identifiable, Hashable {
    case today
    case keyMetrics
    case yourCards
    case addedCards

    var id: String { rawValue }
}

struct TodayCustomizationSheet: View {
    @Environment(\.dismiss) private var dismiss

    private enum Route: Hashable {
        case keyMetrics
        case yourCards
        case addedCards
    }

    private let initialSectionDraft: EditableLayoutDraft<TodaySection>
    private let initialKeyMetricDraft: EditableLayoutDraft<KeyMetric>
    private let initialDashboardDraft: EditableLayoutDraft<DashboardCard>
    private let initialHostedDraft: EditableLayoutDraft<HostedCard>
    private let initialDetailed: Bool
    private let initialWindowDays: Int

    @Binding private var sectionOrderRaw: String
    @Binding private var hiddenSectionsRaw: String
    @Binding private var keyMetricsRaw: String
    @Binding private var keyMetricsDetailed: Bool
    @Binding private var keyMetricsWindowDays: Int
    @Binding private var dashboardCardsRaw: String
    @Binding private var hostedCardsRaw: String

    @State private var path: [Route]
    @State private var sectionDraft: EditableLayoutDraft<TodaySection>
    @State private var keyMetricDraft: EditableLayoutDraft<KeyMetric>
    @State private var dashboardDraft: EditableLayoutDraft<DashboardCard>
    @State private var hostedDraft: EditableLayoutDraft<HostedCard>
    @State private var detailed: Bool
    @State private var windowDays: Int

    #if os(iOS)
    // A5 (iPhone redesign): the Background settings ride the same draft / Save / Cancel flow as every other
    // edit here. nil = untouched, so a sheet the user only looks at stays clean.
    @AppStorage(NoopTheme.Keys.redesignEnabled) private var redesignEnabled = true
    @AppStorage(NoopTheme.Keys.ambientFromScores) private var ambientFromScores = true
    @AppStorage(NoopTheme.Keys.ambientIntensity) private var ambientIntensityRaw = AmbientIntensity.balanced.rawValue
    @State private var ambientFromScoresDraft: Bool?
    @State private var ambientIntensityDraft: AmbientIntensity?

    private var storedAmbientIntensity: AmbientIntensity {
        AmbientIntensity(rawValue: ambientIntensityRaw) ?? .balanced
    }
    private var ambientDirty: Bool {
        (ambientFromScoresDraft.map { $0 != ambientFromScores } ?? false)
            || (ambientIntensityDraft.map { $0 != storedAmbientIntensity } ?? false)
    }
    #endif

    private var currentDestination: TodayCustomizationDestination {
        switch path.last {
        case .keyMetrics: return .keyMetrics
        case .yourCards: return .yourCards
        case .addedCards: return .addedCards
        case nil: return .today
        }
    }

    private var isDirty: Bool {
        sectionDraft != initialSectionDraft
            || keyMetricDraft != initialKeyMetricDraft
            || dashboardDraft != initialDashboardDraft
            || hostedDraft != initialHostedDraft
            || detailed != initialDetailed
            || windowDays != initialWindowDays
            || backgroundDirty
    }

    private var backgroundDirty: Bool {
        #if os(iOS)
        return ambientDirty
        #else
        return false
        #endif
    }

    init(
        initialDestination: TodayCustomizationDestination = .today,
        sectionOrderRaw: Binding<String>,
        hiddenSectionsRaw: Binding<String>,
        keyMetricsRaw: Binding<String>,
        keyMetricsDetailed: Binding<Bool>,
        keyMetricsWindowDays: Binding<Int>,
        dashboardCardsRaw: Binding<String>,
        hostedCardsRaw: Binding<String>
    ) {
        _sectionOrderRaw = sectionOrderRaw
        _hiddenSectionsRaw = hiddenSectionsRaw
        _keyMetricsRaw = keyMetricsRaw
        _keyMetricsDetailed = keyMetricsDetailed
        _keyMetricsWindowDays = keyMetricsWindowDays
        _dashboardCardsRaw = dashboardCardsRaw
        _hostedCardsRaw = hostedCardsRaw

        let fullSectionOrder = TodayLayoutPrefs.decodeOrder(sectionOrderRaw.wrappedValue)
        let hiddenSectionSet = Set(TodayLayoutPrefs.decodeHidden(hiddenSectionsRaw.wrappedValue))
        let sections = EditableLayoutDraft(
            visible: fullSectionOrder.filter { !hiddenSectionSet.contains($0) },
            hidden: fullSectionOrder.filter { hiddenSectionSet.contains($0) }
        )
        let metrics = EditableLayoutDraft(
            visible: KeyMetricPrefs.decodeEnabled(keyMetricsRaw.wrappedValue),
            allItems: KeyMetric.defaultOrder
        )
        let cards = EditableLayoutDraft(
            visible: DashboardCardPrefs.decodeEnabled(dashboardCardsRaw.wrappedValue),
            allItems: DashboardCard.canonicalOrder
        )
        let hosted = EditableLayoutDraft(
            visible: HostedCardPrefs.decodeEnabled(hostedCardsRaw.wrappedValue),
            allItems: HostedCard.canonicalOrder
        )

        initialSectionDraft = sections
        initialKeyMetricDraft = metrics
        initialDashboardDraft = cards
        initialHostedDraft = hosted
        initialDetailed = keyMetricsDetailed.wrappedValue
        initialWindowDays = keyMetricsWindowDays.wrappedValue

        _sectionDraft = State(initialValue: sections)
        _keyMetricDraft = State(initialValue: metrics)
        _dashboardDraft = State(initialValue: cards)
        _hostedDraft = State(initialValue: hosted)
        _detailed = State(initialValue: keyMetricsDetailed.wrappedValue)
        _windowDays = State(initialValue: keyMetricsWindowDays.wrappedValue)

        switch initialDestination {
        case .today:
            _path = State(initialValue: [])
        case .keyMetrics:
            _path = State(initialValue: [.keyMetrics])
        case .yourCards:
            _path = State(initialValue: [.yourCards])
        case .addedCards:
            _path = State(initialValue: [.addedCards])
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            TodaySectionsCustomizationPage(
                draft: $sectionDraft,
                keyMetricCount: keyMetricDraft.visible.count,
                dashboardCardCount: dashboardDraft.visible.count,
                hostedCardCount: hostedDraft.visible.count,
                onConfigure: openConfiguration,
                onReset: resetCurrentLayout,
                backgroundSection: backgroundSection
            )
            .toolbar {
                customizationToolbar(showCancel: true)
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .keyMetrics:
                    KeyMetricsCustomizationPage(
                        draft: $keyMetricDraft,
                        detailed: $detailed,
                        windowDays: $windowDays,
                        onReset: resetCurrentLayout
                    )
                    .toolbar {
                        customizationToolbar(showCancel: false)
                    }
                case .yourCards:
                    DashboardCardsCustomizationPage(
                        draft: $dashboardDraft,
                        onReset: resetCurrentLayout
                    )
                        .toolbar {
                            customizationToolbar(showCancel: false)
                        }
                case .addedCards:
                    HostedCardsCustomizationPage(
                        draft: $hostedDraft,
                        onReset: resetCurrentLayout
                    )
                        .toolbar {
                            customizationToolbar(showCancel: false)
                        }
                }
            }
        }
        .interactiveDismissDisabled(isDirty)
        .modifier(CustomizationSheetChrome())
        #if os(macOS)
        .frame(
            minWidth: NoopMetrics.editorSheetMinWidth,
            minHeight: NoopMetrics.editorSheetMinHeight
        )
        #endif
    }

    private func openConfiguration(_ section: TodaySection) {
        switch section {
        case .keyMetrics:
            path.append(.keyMetrics)
        case .yourCards:
            path.append(.yourCards)
        case .addedCards:
            path.append(.addedCards)
        default:
            break
        }
    }

    private func resetCurrentLayout() {
        switch currentDestination {
        case .today:
            sectionDraft = EditableLayoutDraft(
                visible: TodaySection.defaultOrder,
                allItems: TodaySection.defaultOrder
            )
        case .keyMetrics:
            keyMetricDraft = EditableLayoutDraft(
                visible: KeyMetric.defaultOrder,
                allItems: KeyMetric.defaultOrder
            )
            detailed = false
            windowDays = 14
        case .yourCards:
            dashboardDraft = EditableLayoutDraft(
                visible: DashboardCard.defaultSelection,
                allItems: DashboardCard.canonicalOrder
            )
        case .addedCards:
            hostedDraft = EditableLayoutDraft(
                visible: HostedCard.defaultSelection,
                allItems: HostedCard.canonicalOrder
            )
        }
    }

    private func cancel() {
        dismiss()
    }

    private func save() {
        sectionOrderRaw = TodayLayoutPrefs.encode(sectionDraft.visible + sectionDraft.hidden)
        hiddenSectionsRaw = TodayLayoutPrefs.encodeHidden(sectionDraft.hidden)
        keyMetricsRaw = KeyMetricPrefs.encode(keyMetricDraft.visible)
        keyMetricsDetailed = detailed
        keyMetricsWindowDays = windowDays
        dashboardCardsRaw = DashboardCardPrefs.encode(dashboardDraft.visible)
        hostedCardsRaw = HostedCardPrefs.encode(hostedDraft.visible)
        #if os(iOS)
        if let draft = ambientFromScoresDraft { ambientFromScores = draft }
        if let draft = ambientIntensityDraft { ambientIntensityRaw = draft.rawValue }
        #endif
        dismiss()
    }

    /// A5's Background section (§3.7): only on iPhone with the redesign on, where the ambient field exists.
    /// nil elsewhere, so macOS and the Liquid/classic Today keep the editor exactly as it was.
    private var backgroundSection: AnyView? {
        #if os(iOS)
        guard redesignEnabled else { return nil }
        let fromScores = Binding(get: { ambientFromScoresDraft ?? ambientFromScores },
                                 set: { ambientFromScoresDraft = $0 })
        let intensity = Binding(get: { ambientIntensityDraft ?? storedAmbientIntensity },
                                set: { ambientIntensityDraft = $0 })
        return AnyView(TodayBackgroundSection(fromScores: fromScores, intensity: intensity))
        #else
        return nil
        #endif
    }

    @ToolbarContentBuilder
    private func customizationToolbar(showCancel: Bool) -> some ToolbarContent {
        if showCancel {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: cancel)
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save", action: save)
        }
    }
}

// MARK: - Sheet chrome

/// The sheet's tint and surface. macOS (and an iPhone with the redesign off) keep the shipped accent
/// unchanged; the iPhone redesign (A5) draws it dark on the redesign's sheet colour with blue actions.
private struct CustomizationSheetChrome: ViewModifier {
    #if os(iOS)
    @AppStorage(NoopTheme.Keys.redesignEnabled) private var redesignEnabled = true
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
        if redesignEnabled {
            content
                .tint(NoopTheme.strain)
                .preferredColorScheme(.dark)
                .presentationBackground(NoopTheme.sheet)
        } else {
            content.tint(StrandPalette.accent)
        }
        #else
        content.tint(StrandPalette.accent)
        #endif
    }
}

#if os(iOS)
/// A5 "Background": whether the ambient glow takes its colours from the day's scores, and how strongly
/// (Subtle / Balanced / Vivid multiply every blob's opacity by 0.6 / 1.0 / 1.4, §3.7).
private struct TodayBackgroundSection: View {
    @Binding var fromScores: Bool
    @Binding var intensity: AmbientIntensity

    var body: some View {
        Section {
            Toggle(isOn: $fromScores) {
                VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
                    Text("Colour from your scores").noopFont(.listTitle)
                    Text("The glow follows Sleep, Recovery and Strain")
                        .noopFont(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            SegmentedPills(AmbientIntensity.allCases, selection: $intensity) { option in
                switch option {
                case .subtle: return Text("Subtle")
                case .balanced: return Text("Balanced")
                case .vivid: return Text("Vivid")
                }
            }
            .disabled(!fromScores)
            .opacity(fromScores ? 1 : Self.disabledOpacity)
            .accessibilityLabel(Text("Intensity"))
        } header: {
            Text("Background").noopFont(.footnote)
        }
    }

    private static let disabledOpacity: Double = 0.45
}
#endif

// MARK: - Editor pages

private struct TodaySectionsCustomizationPage: View {
    @Binding var draft: EditableLayoutDraft<TodaySection>
    let keyMetricCount: Int
    let dashboardCardCount: Int
    let hostedCardCount: Int
    let onConfigure: (TodaySection) -> Void
    let onReset: () -> Void
    var backgroundSection: AnyView? = nil

    var body: some View {
        EditableLayoutList(
            draft: $draft,
            shownTitle: String(localized: "Shown on Today"),
            hiddenTitle: String(localized: "Hidden"),
            title: \.title,
            subtitle: subtitle,
            icon: \.customizationIcon,
            tint: \.customizationTint,
            configurationLabel: configurationLabel,
            onConfigure: onConfigure,
            onReset: onReset
        ) {
            if let backgroundSection { backgroundSection }
        }
        .navigationTitle("Customize Today")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func subtitle(for section: TodaySection) -> String? {
        switch section {
        case .liveSession:
            return String(localized: "Requires Live Sessions to be enabled in Settings.")
        case .keyMetrics:
            return String(localized: "\(keyMetricCount) metrics shown")
        case .yourCards:
            return String(localized: "\(dashboardCardCount) cards shown")
        case .addedCards:
            return hostedCardCount == 0
                ? String(localized: "None added yet")
                : String(localized: "\(hostedCardCount) added")
        default:
            return nil
        }
    }

    private func configurationLabel(for section: TodaySection) -> String? {
        switch section {
        case .keyMetrics, .yourCards, .addedCards:
            return String(localized: "Edit")
        default:
            return nil
        }
    }
}

private struct KeyMetricsCustomizationPage: View {
    @Binding var draft: EditableLayoutDraft<KeyMetric>
    @Binding var detailed: Bool
    @Binding var windowDays: Int
    let onReset: () -> Void

    var body: some View {
        EditableLayoutList(
            draft: $draft,
            shownTitle: String(localized: "Shown"),
            hiddenTitle: String(localized: "Hidden"),
            title: \.title,
            subtitle: { _ in nil },
            icon: \.customizationIcon,
            tint: \.customizationTint,
            configurationLabel: { _ in nil },
            onConfigure: { _ in },
            onReset: onReset
        ) {
            Section("Display") {
                Picker("Key Metrics", selection: $detailed) {
                    Text("Today").tag(false)
                    Text("Trends").tag(true)
                }
                .pickerStyle(.segmented)

                if detailed {
                    Picker("Trend window", selection: $windowDays) {
                        Text("1 week").tag(7)
                        Text("2 weeks").tag(14)
                        Text("1 month").tag(30)
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
        .navigationTitle("Key Metrics")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

private struct DashboardCardsCustomizationPage: View {
    @Binding var draft: EditableLayoutDraft<DashboardCard>
    let onReset: () -> Void

    var body: some View {
        EditableLayoutList(
            draft: $draft,
            shownTitle: String(localized: "Shown"),
            hiddenTitle: String(localized: "Hidden"),
            title: \.title,
            subtitle: \.subtitle,
            icon: \.icon,
            tint: \.customizationTint,
            configurationLabel: { _ in nil },
            onConfigure: { _ in },
            onReset: onReset
        ) {
            EmptyView()
        }
        .navigationTitle(String(localized: "Your cards"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// The Customise page for the Trends/Sleep cards hosted in Today (#today-hosted-cards). Reuses the shared
/// Shown/Hidden editor exactly like "Your cards"; the Shown list is the `HostedCardPrefs` selection in
/// order, the Hidden list is every not-yet-hosted card. Subtitle names the originating tab.
private struct HostedCardsCustomizationPage: View {
    @Binding var draft: EditableLayoutDraft<HostedCard>
    let onReset: () -> Void

    var body: some View {
        EditableLayoutList(
            draft: $draft,
            shownTitle: String(localized: "Added to Today"),
            hiddenTitle: String(localized: "Available"),
            title: \.title,
            subtitle: { String(localized: "from \($0.origin)") },
            icon: \.customizationIcon,
            tint: \.customizationTint,
            configurationLabel: { _ in nil },
            onConfigure: { _ in },
            onReset: onReset,
            allowEmpty: true,   // hosting is opt-in: the last card can be un-hosted (Shown may be empty)
            group: { $0.origin }   // group the Available list by origin tab ("Sleep", "Trends")
        ) {
            EmptyView()
        }
        .navigationTitle(String(localized: "Added Cards"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#if DEBUG
#Preview("Customize Today") {
    TodayCustomizationSheet(
        sectionOrderRaw: .constant(""),
        hiddenSectionsRaw: .constant(""),
        keyMetricsRaw: .constant(""),
        keyMetricsDetailed: .constant(false),
        keyMetricsWindowDays: .constant(14),
        dashboardCardsRaw: .constant(""),
        hostedCardsRaw: .constant("")
    )
    .preferredColorScheme(.dark)
}
#endif
