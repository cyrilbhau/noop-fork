import Foundation

/// Draft-derived editor facts. No preferences are written until the sheet saves its encoded snapshot.
enum TodayCardsEditorPresentation {
    enum Note: Equatable {
        case hydrationOff, coachOff, duplicate, coupledShortcut, coachShortcut, description

        var isGate: Bool { self == .hydrationOff || self == .coachOff }
    }

    enum Position: Equatable {
        case hidden, first, after(TodaySection)
    }

    static func visibleKeyMetrics(sections: EditableLayoutDraft<TodaySection>,
                                  metrics: [KeyMetric]) -> [KeyMetric]? {
        sections.visible.contains(.keyMetrics) ? metrics : nil
    }

    static func selection(raw: String, redesign: Bool, sections: EditableLayoutDraft<TodaySection>,
                          metrics: [KeyMetric]) -> [DashboardCard] {
        guard redesign else { return DashboardCardPrefs.decodeEnabled(raw) }
        return TodayCardResolver.selection(raw: raw, visibleKeyMetrics: visibleKeyMetrics(sections: sections, metrics: metrics))
    }

    static func note(for card: DashboardCard, visibleKeyMetrics: [KeyMetric]?,
                     hydrationEnabled: Bool, coachEnabled: Bool) -> Note {
        if card == .hydration && !hydrationEnabled { return .hydrationOff }
        if card == .coach && !coachEnabled { return .coachOff }
        if let twin = TodayCardResolver.keyMetricTwin(for: card), visibleKeyMetrics?.contains(twin) == true {
            return .duplicate
        }
        if card == .coupled { return .coupledShortcut }
        if card == .coach { return .coachShortcut }
        return .description
    }

    static func position(in sections: EditableLayoutDraft<TodaySection>) -> Position {
        guard let index = sections.visible.firstIndex(of: .yourCards) else { return .hidden }
        return index == 0 ? .first : .after(sections.visible[index - 1])
    }
}

/// The sheet's complete layout commit. Card changes never implicitly show their containing section.
struct TodayCustomizationSaveValues: Equatable {
    let sectionOrderRaw: String
    let hiddenSectionsRaw: String
    let keyMetricsRaw: String
    let keyMetricsDetailed: Bool
    let keyMetricsWindowDays: Int
    let dashboardCardsRaw: String
    let hostedCardsRaw: String

    init(sections: EditableLayoutDraft<TodaySection>, metrics: [KeyMetric], detailed: Bool,
         windowDays: Int, dashboardCards: [DashboardCard], hostedCards: [HostedCard]) {
        sectionOrderRaw = TodayLayoutPrefs.encode(sections.visible + sections.hidden)
        hiddenSectionsRaw = TodayLayoutPrefs.encodeHidden(sections.hidden)
        keyMetricsRaw = KeyMetricPrefs.encode(metrics)
        keyMetricsDetailed = detailed
        keyMetricsWindowDays = windowDays
        dashboardCardsRaw = DashboardCardPrefs.encode(dashboardCards)
        hostedCardsRaw = HostedCardPrefs.encode(hostedCards)
    }
}
