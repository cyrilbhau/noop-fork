import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Recovery detail (round 2 "02 Recovery"). Arc gauge in the band colour, the band headline, the existing
/// readiness explanation and a provenance caption; "What shaped it" (HRV, resting HR, sleep performance,
/// respiratory rate) against the user's typical range; then the last 30 days in band colours with a link to
/// Trends. Every value comes from `RecoveryDetailModel`, which reuses Today's selectors (see
/// `ScoreDetailData.swift`). Calibrating or missing days draw a dashed empty gauge with no animation.
struct RecoveryDetailView: View {
    let dayKey: String?

    @EnvironmentObject private var repo: Repository
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(NoopTheme.Keys.ringsFillOnLoad) private var ringsFillOnLoad = true
    @AppStorage(NoopTheme.Keys.ambientFromScores) private var ambientFromScores = true
    @AppStorage(NoopTheme.Keys.ambientIntensity) private var ambientIntensityRaw = AmbientIntensity.balanced.rawValue

    @State private var model: RecoveryDetailModel?
    @State private var showTrends = false

    private var loading: Bool { model == nil }
    private var pct: Double? { model?.display.pct }
    private var band: NoopTheme.RecoveryBand? { pct.map { NoopTheme.recoveryBand(for: $0) } }
    private var bandColor: Color { band.map { NoopTheme.recoveryColor(for: $0) } ?? NoopTheme.textTertiary }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                    .noopEntrance(index: 0)
                NoopSectionHeader("What shaped it")
                factorsCard
                    .padding(.horizontal, NoopTheme.Layout.gutter)
                    .noopSkeleton(loading)
                    .noopEntrance(index: 1)
                NoopSectionHeader("Last 30 days", linkTitle: "Trends") { showTrends = true }
                historyCard
                    .padding(.horizontal, NoopTheme.Layout.gutter)
                    .noopSkeleton(loading)
                    .noopEntrance(index: 2)
            }
            .padding(.bottom, NoopTheme.Layout.xl)
        }
        .noopAmbientBackground(
            AmbientPreset.recovery(ambientFromScores ? band : nil)
                .blobs(intensity: AmbientIntensity(rawValue: ambientIntensityRaw) ?? .balanced))
        .navigationTitle(Text("Recovery"))
        .navigationDestination(isPresented: $showTrends) { MoreDestination.trends.destination }
        .task(id: "\(repo.refreshSeq)-\(dayKey ?? "")") {
            model = await RecoveryDetailModel.load(dayKey: dayKey, repo: repo)
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
            NoopArcGauge(
                value: pct.map { $0 / 100 },
                color: bandColor,
                number: pct.map { ScoreDetailFormat.score($0, decimals: 0) } ?? "—",
                caption: String(localized: "Recovery"),
                animate: pct != nil && NoopTheme.Motion.ringsAnimate(reduceMotion: reduceMotion,
                                                                     fillOnLoad: ringsFillOnLoad),
                accessibilityLabel: String(localized: "Recovery"),
                accessibilityValue: pct.map { "\(ScoreDetailFormat.score($0, decimals: 0))%" }
                    ?? String(localized: "No data")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, NoopTheme.Layout.l)

            VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                Text(verbatim: headline)
                    .noopFont(.screenHeadline)
                    .accessibilityAddTraits(.isHeader)
                ForEach(explanation, id: \.self) { line in
                    Text(verbatim: line)
                        .noopFont(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let caption = sourceCaption {
                    SourceCaption(verbatim: caption)
                        .padding(.top, NoopTheme.Layout.xs)
                }
            }
            .padding(.horizontal, NoopTheme.Layout.sectionSide)
            .noopSkeleton(loading)
        }
    }

    private var headline: String {
        guard let model else { return " " }
        switch model.display {
        case .calibrating: return String(localized: "Calibrating")
        case .noData: return String(localized: "No data")
        case .scored, .carried:
            // The SAME band word the Today ring and the widgets show for this score (one resolver), so the
            // ring that opened this screen and its headline cannot disagree.
            return band.map(RedesignTodayView.bandWord) ?? String(localized: "No data")
        }
    }

    /// The existing copy for the state: the calibration progress (and its reason) while the baseline forms,
    /// the readiness synthesis Liquid Today shows once there is a score, an honest line when there is none.
    private var explanation: [String] {
        guard let model else { return [" "] }
        switch model.display {
        case .calibrating:
            var lines = [model.display.calibrationDetail].compactMap { $0 }
            if let why = model.display.calibrationReason(dayKeys: repo.days.map(\.day),
                                                         nightlyHrv: repo.days.map(\.avgHrv),
                                                         today: Repository.logicalDayKey(Date())) {
                lines.append(why)
            }
            return lines
        case .noData:
            return [String(localized: "No Recovery score for this day.")]
        case .scored, .carried:
            return [TodayDayModel.readinessSentence(level: model.readiness.level, days: repo.days,
                                                    today: Repository.logicalDayKey(Date()))]
        }
    }

    /// Provenance, the carried night's stamp when Today is showing last night's score, and the day for a
    /// past day, joined into one caption.
    private var sourceCaption: String? {
        guard let model else { return nil }
        var parts: [String] = []
        if !model.day.isToday { parts.append(ScoreDetailFormat.dayTitle(model.day.key)) }
        if case .carried(_, let caption) = model.display { parts.append(caption) }
        if let provenance = model.provenance { parts.append(provenance.caption()) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: What shaped it

    private var factorsCard: some View {
        NoopGlassCard(flush: true) {
            VStack(spacing: 0) {
                ForEach(Array((model?.factors ?? placeholderFactors).enumerated()), id: \.element.id) { index, factor in
                    NavigationLink(value: TabRoute.metric(metricKey(factor.kind))) {
                        RecoveryFactorRow(factor: factor, showsDivider: index > 0)
                    }
                    .buttonStyle(.noopPress)
                }
            }
        }
    }

    private var placeholderFactors: [RecoveryFactor] {
        [.hrv, .restingHR, .sleep, .respiratory].map {
            RecoveryFactor(kind: $0, value: nil, typical: nil, deltaPoints: nil)
        }
    }

    private func metricKey(_ kind: RecoveryFactor.Kind) -> String {
        switch kind {
        case .hrv: return "hrv"
        case .restingHR: return "rhr"
        case .sleep: return "sleep_performance"
        case .respiratory: return "resp_rate"
        }
    }

    // MARK: Last 30 days

    private var historyCard: some View {
        let values = model?.bars ?? Array(repeating: nil, count: 30)
        let present = values.compactMap { $0 }
        let counts = present.reduce(into: [NoopTheme.RecoveryBand: Int]()) { $0[NoopTheme.recoveryBand(for: $1), default: 0] += 1 }
        let average = present.isEmpty ? nil : present.reduce(0, +) / Double(present.count)
        return NoopGlassCard {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        averageLabel(average)
                        Spacer(minLength: NoopTheme.Layout.s)
                        bandCounts(counts)
                    }
                    VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                        averageLabel(average)
                        bandCounts(counts)
                    }
                }
                NoopBarChart(
                    values: values,
                    colorForValue: { NoopTheme.recoveryColor(for: $0) },
                    maxValue: 100,
                    xLabels: ScoreDetailFormat.barCaptions(keys: model?.barKeys ?? [], isToday: model?.day.isToday ?? true),
                    animates: !reduceMotion && model != nil,
                    accessibilityLabel: Text("Last 30 days"),
                    valueFormat: { "\(ScoreDetailFormat.score($0, decimals: 0))%" }
                )
                .frame(height: RecoveryLayout.chartHeight)
            }
        }
    }

    private func averageLabel(_ average: Double?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: NoopTheme.Layout.xs) {
            Text(verbatim: average.map { "\(ScoreDetailFormat.score($0, decimals: 0))%" } ?? "—")
                .noopFont(.statNumber)
            Text("Avg").noopFont(.footnote)
        }
        .accessibilityElement(children: .combine)
    }

    private func bandCounts(_ counts: [NoopTheme.RecoveryBand: Int]) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: NoopTheme.Layout.s))
            : AnyLayout(HStackLayout(spacing: NoopTheme.Layout.m))
        return layout {
            bandCount(counts[.high] ?? 0, color: NoopTheme.recovery, label: String(localized: "\(counts[.high] ?? 0) green"))
            bandCount(counts[.mid] ?? 0, color: NoopTheme.recoveryMid, label: String(localized: "\(counts[.mid] ?? 0) yellow"))
            bandCount(counts[.low] ?? 0, color: NoopTheme.recoveryLow, label: String(localized: "\(counts[.low] ?? 0) red"))
        }
    }

    private func bandCount(_ n: Int, color: Color, label: String) -> some View {
        HStack(spacing: NoopTheme.Layout.xs) {
            Circle().fill(color).frame(width: RecoveryLayout.dot, height: RecoveryLayout.dot)
                .accessibilityHidden(true)
            Text(verbatim: label).noopFont(.caption, color: false).foregroundStyle(NoopTheme.textSecondary)
        }
    }
}

/// Geometry from the mockup with no `NoopTheme` token.
private enum RecoveryLayout {
    /// `#recbars` height in round 2 "02 Recovery".
    static let chartHeight: CGFloat = 96
    /// `.dot` legend swatch.
    static let dot: CGFloat = 8
    /// The leading status glyph column (`margin-left: 24px` on the sub-line and range).
    static let glyphColumn: CGFloat = 24
    static let hairline: CGFloat = 1
}

/// One "What shaped it" row: glyph for the term's effect, title in its domain colour, value, the range
/// sub-line with the signed points, and the range indicator.
private struct RecoveryFactorRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let factor: RecoveryFactor
    let showsDivider: Bool

    private var title: LocalizedStringKey {
        switch factor.kind {
        case .hrv: return "Heart rate variability"
        case .restingHR: return "Resting heart rate"
        case .sleep: return "Sleep performance"
        case .respiratory: return "Respiratory rate"
        }
    }

    private var color: Color {
        switch factor.kind {
        case .hrv: return NoopTheme.hrv
        case .restingHR: return NoopTheme.heart
        case .sleep: return NoopTheme.sleep
        case .respiratory: return NoopTheme.breath
        }
    }

    private var unit: String {
        switch factor.kind {
        case .hrv: return "ms"
        case .restingHR: return "bpm"
        case .sleep: return "%"
        case .respiratory: return "rpm"
        }
    }

    private var valueText: String? {
        guard let v = factor.value else { return nil }
        switch factor.kind {
        case .respiratory: return String(format: "%.1f", locale: AppLanguage.activeLocale, v)
        default: return String(Int(v.rounded()))
        }
    }

    /// Where the value sits against the typical band (the same band `Baselines.deviation` calls normal).
    private var rangeLine: String? {
        guard let v = factor.value else { return String(localized: "Not recorded") }
        guard factor.kind != .sleep else { return nil }
        guard let band = factor.typical else { return String(localized: "No personal range yet") }
        if v > band.upperBound { return String(localized: "Above your usual range") }
        if v < band.lowerBound { return String(localized: "Below your usual range") }
        return String(localized: "Within your usual range")
    }

    private var subline: String? {
        let parts = [rangeLine, factor.deltaPoints.map { ChargeBreakdownFormat.chipLabel(deltaPoints: $0) }]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var glyph: (name: String, color: Color) {
        guard let d = factor.deltaPoints else { return ("circle", NoopTheme.textTertiary) }
        if d > 0 { return ("checkmark.circle.fill", NoopTheme.recovery) }
        if d < 0 { return ("exclamationmark.circle.fill", NoopTheme.recoveryLow) }
        return ("minus.circle", NoopTheme.textTertiary)
    }

    /// The track spans the band with room either side, widened to keep today's dot on it.
    private var range: ClosedRange<Double> {
        if factor.kind == .sleep { return 0...100 }
        let v = factor.value
        guard let band = factor.typical else {
            guard let v else { return 0...1 }
            return (v * 0.8)...(v * 1.2)
        }
        let pad = max(band.upperBound - band.lowerBound, 0.1)
        var lo = band.lowerBound - pad
        var hi = band.upperBound + pad
        if let v { lo = min(lo, v - pad / 2); hi = max(hi, v + pad / 2) }
        return lo...hi
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsDivider {
                Rectangle().fill(NoopTheme.separator).frame(height: RecoveryLayout.hairline)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: NoopTheme.Layout.s))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: NoopTheme.Layout.s))
                layout {
                    HStack(alignment: .firstTextBaseline, spacing: NoopTheme.Layout.s) {
                        Image(systemName: glyph.name)
                            .noopFont(.footnote, color: false)
                            .foregroundStyle(glyph.color)
                            .fixedSize()
                            .frame(width: dynamicTypeSize.isAccessibilitySize ? nil
                                   : RecoveryLayout.glyphColumn - NoopTheme.Layout.s, alignment: .leading)
                            .accessibilityHidden(true)
                        Text(title)
                            .noopFont(.rowTitle, color: false)
                            .foregroundStyle(color)
                            .fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "chevron.right")
                            .noopFont(.caption)
                            .accessibilityHidden(true)
                    }
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: NoopTheme.Layout.s) }
                    HStack(alignment: .firstTextBaseline, spacing: NoopTheme.Layout.xs / 2) {
                        Text(verbatim: valueText ?? "—")
                            .noopFont(.rowTitle, color: false)
                            .foregroundStyle(valueText == nil ? NoopTheme.textSecondary : NoopTheme.textPrimary)
                            .monospacedDigit()
                        if valueText != nil { Text(verbatim: unit).noopFont(.unit) }
                    }
                }
                Group {
                    if let subline {
                        Text(verbatim: subline).noopFont(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    RangeIndicator(value: factor.value, range: range, band: factor.typical, color: color)
                }
                .padding(.leading, RecoveryLayout.glyphColumn)
            }
            .padding(.vertical, NoopTheme.Layout.rowVerticalPadding)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(verbatim: [valueText.map { "\($0) \(unit)" } ?? "—", subline].compactMap { $0 }
            .joined(separator: ", ")))
        .accessibilityAddTraits(.isButton)
    }
}
