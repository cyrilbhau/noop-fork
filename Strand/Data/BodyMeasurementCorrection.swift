import Foundation

// Stage 1 (weigh-in and scorecard), ruling R41 of specification §18: one number per variable.
//
// Two decisions every body-measurement surface shares, held here so that no view makes them:
// where a tap on a readout of the CURRENT weight or waist goes, and how a page that lists ONE
// source's series words itself. With `noop.cutScorecardEnabled` off (any legacy policy) both answer
// exactly as the base commit did.

/// A place that shows the current body weight or waist.
enum BodyMeasurementSurface: CaseIterable {
    case liquidTodayWeightTile, classicTodayWeightTile, redesignTodayWeightRow
    case settingsWeightRow, settingsWaistRow
    /// The Your Cards card and the Health tab row.
    case scorecardCard
}

/// Where a tap on such a place goes. The view binds to this value and to nothing else.
enum BodyMeasurementCorrectionRoute: Equatable {
    /// No tap target.
    case none
    /// The catalogue page of one source's series.
    case metricDetail(key: String)
    case weighInSheet, weighInHistory, scorecard

    /// True for the routes that lead to the weigh-in sheet or the weigh-in history. The scorecard
    /// screen hosts both.
    var offersCorrection: Bool {
        switch self {
        case .weighInSheet, .weighInHistory, .scorecard: return true
        case .none, .metricDetail: return false
        }
    }

    /// The catalogue push of a `.metricDetail` route, nil for every other route.
    var metricRoute: TabRoute? {
        if case .metricDetail(let key) = self { return .metric(key) }
        return nil
    }

    /// The catalogue key of a `.metricDetail` route, nil for every other route.
    var metricKey: String? {
        if case .metricDetail(let key) = self { return key }
        return nil
    }
}

enum BodyMeasurementCorrection {
    /// `.unified`: a route that offers correction, for every surface and whatever the source of the
    /// value shown. Any other policy: the base commit's route. Liquid and the redesign pushed the
    /// catalogue page of the Apple Health weight series; every other surface had no tap target.
    static func route(for surface: BodyMeasurementSurface,
                      policy: BodyMeasurementPolicy) -> BodyMeasurementCorrectionRoute {
        switch policy {
        case .unified:
            switch surface {
            case .liquidTodayWeightTile, .classicTodayWeightTile, .settingsWeightRow, .settingsWaistRow:
                return .weighInSheet
            case .redesignTodayWeightRow, .scorecardCard:
                return .scorecard
            }
        case .legacyDisplay, .legacyEstimate:
            switch surface {
            case .liquidTodayWeightTile, .redesignTodayWeightRow:
                return .metricDetail(key: BodyMeasurementKind.weight.markerKey)
            case .classicTodayWeightTile, .settingsWeightRow, .settingsWaistRow, .scorecardCard:
                return .none
            }
        }
    }

    /// The caption under a Today weight readout. `dated` is the dated reading the readout resolved,
    /// nil when it shows the profile value. Any legacy policy: "latest" or "from profile", as the
    /// base commit. `.unified`: the source of the reading, so a readout never calls one source's
    /// value "latest".
    static func todayCaption(dated: ResolvedBodyMeasurement?, policy: BodyMeasurementPolicy) -> String {
        guard let dated else { return String(localized: "from profile") }
        switch policy {
        case .unified: return CutScorecardPresenter.sourceCaption(dated.source)
        case .legacyDisplay, .legacyEstimate: return String(localized: "latest")
        }
    }
}

/// How a page of ONE source's body-measurement series words itself. `key` is the catalogue or
/// marker key; only "weight" and "waist" are body measurements. For any other key, and for every
/// key under a legacy policy, each function returns the base commit's text.
///
/// `newestLabel` and `newestReadingLabel` return the base commit's catalogue KEY ("Latest",
/// "Latest reading") in the base case, which each call site looks up exactly as its literal was;
/// their unified text is already localized, and a second lookup of it finds no key and changes nothing.
enum BodyMeasurementSourcePage {
    private static func namesSource(key: String, policy: BodyMeasurementPolicy) -> Bool {
        policy == .unified && BodyMeasurementKind(markerKey: key) != nil
    }

    /// Base: `title`. Unified, body key: the title and its source.
    static func title(_ title: String, key: String, sourceLabel: String,
                      policy: BodyMeasurementPolicy) -> String {
        guard namesSource(key: key, policy: policy) else { return title }
        return "\(title) · \(sourceLabel)"
    }

    /// The stat that carries the newest point of the series. Base: "Latest". Unified, body key:
    /// names the source.
    static func newestLabel(key: String, sourceLabel: String, policy: BodyMeasurementPolicy) -> String {
        guard namesSource(key: key, policy: policy) else { return "Latest" }
        return String(localized: "\(sourceLabel) reading")
    }

    /// The caption over the newest point of the series. Base: "Latest reading".
    static func newestReadingLabel(key: String, policy: BodyMeasurementPolicy) -> String {
        guard namesSource(key: key, policy: policy) else { return "Latest reading" }
        return String(localized: "Source reading")
    }

    /// The Lab Book marker card's VoiceOver label. Base: "<name>, latest <value>, <n> readings".
    /// Unified, body key: the name, the value and the count.
    static func labBookAccessibilityLabel(name: String, value: String, readings: Int, key: String,
                                          policy: BodyMeasurementPolicy) -> String {
        guard namesSource(key: key, policy: policy) else {
            return String(localized: "\(name), latest \(value), \(readings) readings")
        }
        return String(localized: "\(name), \(value), \(readings) readings")
    }
}
