import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// Strain detail (mockup A1). Arc gauge with today's optimal band as target ticks, the band headline, a line
/// on where the day sits against that band, a provenance caption; the day's workouts with source labels; time
/// in each heart-rate zone over the day's window; then the last 30 days with a link to Trends.
///
/// The value is Liquid Today's (`StrainScorer.effectiveEffort` with the live floor) on the user's Effort
/// scale; the target band is `CoupledView.optimalStrainRange` (14–18 / 10–14 / 4–10 of 21 from Recovery),
/// carried onto the 0–100 axis through `StrainScorer.effortValue(fromWhoopStrain:)` when that scale is in
/// use. The mockup's "Today so far" cumulative line is omitted: no cumulative Strain series exists.
struct StrainDetailView: View {
    let dayKey: String?

    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @AppStorage(DayCycleMode.storageKey) private var dayCycleModeRaw = DayCycleMode.sleepOnset.rawValue
    @AppStorage(NoopTheme.Keys.ringsFillOnLoad) private var ringsFillOnLoad = true
    @AppStorage(NoopTheme.Keys.ambientIntensity) private var ambientIntensityRaw = AmbientIntensity.balanced.rawValue

    @State private var model: StrainDetailModel?
    @State private var showTrends = false

    private var loading: Bool { model == nil }
    private var scale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }
    private var scaleMax: Double { scale == .whoop ? StrainScorer.whoopMaxStrain : StrainScorer.maxStrain }
    private var decimals: Int { scale == .whoop ? 1 : 0 }
    private var effort: Double? { model?.effort }
    private var shown: Double? { effort.map { UnitFormatter.effortValue($0, scale: scale) } }

    /// The optimal band on the 0–21 axis, nil without a Recovery score (no ticks, never a guessed band).
    private var target21: ClosedRange<Int>? { CoupledView.optimalStrainRange(recovery: model?.recoveryForTarget) }

    /// The band on the display scale: 0–21 as is; 0–100 through the shipped 0–21 → Effort mapping.
    private var targetShown: ClosedRange<Double>? {
        guard let t = target21 else { return nil }
        let lo = Double(t.lowerBound), hi = Double(t.upperBound)
        return scale == .whoop
            ? lo...hi
            : StrainScorer.effortValue(fromWhoopStrain: lo)...StrainScorer.effortValue(fromWhoopStrain: hi)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                    .noopEntrance(index: 0)
                NoopSectionHeader("Workouts")
                workoutsCard
                    .padding(.horizontal, NoopTheme.Layout.gutter)
                    .noopSkeleton(loading)
                    .noopEntrance(index: 1)
                NoopSectionHeader("Heart rate zones")
                zonesCard
                    .padding(.horizontal, NoopTheme.Layout.gutter)
                    .noopSkeleton(loading)
                    .noopEntrance(index: 2)
                NoopSectionHeader("Last 30 days", linkTitle: "Trends") { showTrends = true }
                historyCard
                    .padding(.horizontal, NoopTheme.Layout.gutter)
                    .noopSkeleton(loading)
                    .noopEntrance(index: 3)
            }
            .padding(.bottom, NoopTheme.Layout.xl)
        }
        .noopAmbientBackground(AmbientPreset.strain.blobs(
            intensity: AmbientIntensity(rawValue: ambientIntensityRaw) ?? .balanced))
        .navigationTitle(Text("Strain"))
        .navigationDestination(isPresented: $showTrends) { MoreDestination.trends.destination }
        .task(id: "\(repo.refreshSeq)-\(dayKey ?? "")-\(dayCycleModeRaw)") {
            model = await StrainDetailModel.load(dayKey: dayKey, repo: repo, profile: profile,
                                                 mode: DayCycleMode.persisted(dayCycleModeRaw))
        }
    }

    // MARK: Hero

    private var gaugeCaption: String {
        guard let t = targetShown else { return String(localized: "Strain") }
        let lo = Int(t.lowerBound.rounded()), hi = Int(t.upperBound.rounded())
        return String(localized: "Strain · target \(lo)–\(hi)")
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
            NoopArcGauge(
                value: shown.map { $0 / scaleMax },
                color: NoopTheme.strain,
                targetBand: targetShown.map { ($0.lowerBound / scaleMax)...($0.upperBound / scaleMax) },
                number: shown.map { ScoreDetailFormat.score($0, decimals: decimals) } ?? "—",
                caption: gaugeCaption,
                animate: shown != nil && NoopTheme.Motion.ringsAnimate(reduceMotion: reduceMotion,
                                                                       fillOnLoad: ringsFillOnLoad),
                accessibilityLabel: gaugeCaption,
                accessibilityValue: shown.map {
                    String(localized: "\(ScoreDetailFormat.score($0, decimals: decimals)) of \(UnitFormatter.effortScaleMax(scale))")
                } ?? String(localized: "No data")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, NoopTheme.Layout.l)

            VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                Text(verbatim: headline)
                    .noopFont(.screenHeadline)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: explanation)
                    .noopFont(.body)
                    .fixedSize(horizontal: false, vertical: true)
                if let caption = sourceCaption {
                    SourceCaption(verbatim: caption)
                        .padding(.top, NoopTheme.Layout.xs)
                }
            }
            .padding(.horizontal, NoopTheme.Layout.sectionSide)
            .noopSkeleton(loading)
        }
    }

    /// The band headline, resolved by `CoupledView.strainBand` on the 0–21 axis. Its own keys: the
    /// shared "Light" key is translated as light sleep / illumination in several locales.
    private var headline: String {
        guard model != nil else { return " " }
        guard let effort else { return String(localized: "No data") }
        let s21 = UnitFormatter.effortValue(effort, scale: .whoop)
        switch CoupledView.strainBand(strain21: s21) {
        case .light: return String(localized: "Light day")
        case .moderate: return String(localized: "Moderate day")
        case .strenuous: return String(localized: "Strenuous day")
        case .high: return String(localized: "High-strain day")
        case nil: return String(localized: "No data")
        }
    }

    /// Where the day sits against the optimal band. Compared on the 0–21 axis the band is defined on.
    private var explanation: String {
        guard model != nil else { return " " }
        guard let effort else { return String(localized: "No Strain recorded for this day.") }
        guard let t = target21 else { return String(localized: "No target yet: Recovery isn't scored for this day.") }
        let s21 = UnitFormatter.effortValue(effort, scale: .whoop)
        if s21 < Double(t.lowerBound) { return String(localized: "Below the target your Recovery sets.") }
        if s21 > Double(t.upperBound) { return String(localized: "Above the target your Recovery sets.") }
        return String(localized: "Within the target your Recovery sets.")
    }

    private var sourceCaption: String? {
        guard let model else { return nil }
        var parts: [String] = []
        if !model.day.isToday { parts.append(ScoreDetailFormat.dayTitle(model.day.key)) }
        if let provenance = model.provenance {
            parts.append(provenance.caption(scale: scale == .whoop ? String(localized: "0–21") : String(localized: "0–100")))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Workouts

    @ViewBuilder private var workoutsCard: some View {
        let rows = model?.workouts ?? []
        if rows.isEmpty {
            NoopGlassCard {
                Text(model == nil ? " " : String(localized: "No workouts logged for this day."))
                    .noopFont(.bodySmall, color: false)
                    .foregroundStyle(NoopTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            NoopGlassCard(flush: true) {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        NavigationLink {
                            WorkoutDetailView(row: row)
                        } label: {
                            StrainWorkoutRow(row: row, scale: scale, showsDivider: index > 0)
                        }
                        .buttonStyle(.noopPress)
                    }
                }
            }
        }
    }

    // MARK: Zones

    @ViewBuilder private var zonesCard: some View {
        if let seconds = model?.zoneSeconds {
            NoopGlassCard {
                ZoneBars(
                    names: (1...5).map { String(localized: "Z\($0)") },
                    values: seconds.map { $0 },
                    trailingLabels: seconds.map { ScoreDetailFormat.duration(seconds: $0) },
                    scale: .largest,
                    animates: !reduceMotion
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Heart rate zones"))
                .accessibilityValue(Text(verbatim: zip(1...5, seconds).reversed().map { zone, s in
                    String(localized: "Zone \(zone) · \(ScoreDetailFormat.duration(seconds: s))")
                }.joined(separator: ", ")))
            }
        } else {
            NoopGlassCard {
                Text(model == nil ? " " : String(localized: "No heart rate for this day"))
                    .noopFont(.bodySmall, color: false)
                    .foregroundStyle(NoopTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Last 30 days

    private var historyCard: some View {
        let values: [Double?] = (model?.bars ?? Array(repeating: nil, count: 30))
            .map { $0.map { UnitFormatter.effortValue($0, scale: scale) } }
        let keys = model?.barKeys ?? []
        let present = values.compactMap { $0 }
        let average = present.isEmpty ? nil : present.reduce(0, +) / Double(present.count)
        let peakIndex = values.indices.filter { values[$0] != nil }.max { (values[$0] ?? 0) < (values[$1] ?? 0) }
        return NoopGlassCard {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        averageLabel(average)
                        Spacer(minLength: NoopTheme.Layout.s)
                        peakLabel(peakIndex.map { (values[$0], keys.indices.contains($0) ? keys[$0] : nil) })
                    }
                    VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
                        averageLabel(average)
                        peakLabel(peakIndex.map { (values[$0], keys.indices.contains($0) ? keys[$0] : nil) })
                    }
                }
                NoopBarChart(
                    values: values,
                    color: NoopTheme.strain,
                    maxValue: scaleMax,
                    xLabels: ScoreDetailFormat.barCaptions(keys: keys, isToday: model?.day.isToday ?? true),
                    animates: !reduceMotion && model != nil,
                    accessibilityLabel: Text("Last 30 days"),
                    valueFormat: { ScoreDetailFormat.score($0, decimals: decimals) }
                )
                .frame(height: StrainLayout.chartHeight)
            }
        }
    }

    private func averageLabel(_ average: Double?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: NoopTheme.Layout.xs) {
            Text(verbatim: average.map { ScoreDetailFormat.score($0, decimals: 1) } ?? "—")
                .noopFont(.statNumber)
            Text("Avg").noopFont(.footnote)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func peakLabel(_ peak: (value: Double?, key: String?)?) -> some View {
        if let peak, let value = peak.value, let key = peak.key {
            Text(verbatim: String(localized: "Peak \(ScoreDetailFormat.score(value, decimals: decimals)) · \(ScoreDetailFormat.shortDate(key))"))
                .noopFont(.footnote)
        }
    }
}

/// Geometry from the mockup with no `NoopTheme` token.
private enum StrainLayout {
    /// `.cbars` height in A1.
    static let chartHeight: CGFloat = 90
    static let hairline: CGFloat = 1
}

/// One workout of the day: sport icon, name, start time · duration · source label, and its Strain when the
/// row carries one. Apple Health rows are labelled summaries; imported or pasted lifts carry full sets.
private struct StrainWorkoutRow: View {
    let row: WorkoutRow
    let scale: EffortScale
    let showsDivider: Bool

    /// The same resolver Today and the Training hub use, so one workout carries one label everywhere.
    private var sourceLabel: String? { TrainingProvenance.forWorkout(row).label }

    private var detail: String {
        let seconds = row.durationS ?? Double(max(0, row.endTs - row.startTs))
        var parts = [ScoreDetailFormat.time(row.startTs)]
        if seconds > 0 { parts.append(ScoreDetailFormat.duration(seconds: seconds)) }
        if let sourceLabel { parts.append(sourceLabel) }
        return parts.joined(separator: " · ")
    }

    private var strainText: String? {
        row.strain.map { ScoreDetailFormat.score(UnitFormatter.effortValue($0, scale: scale),
                                                 decimals: scale == .whoop ? 1 : 0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsDivider {
                Rectangle().fill(NoopTheme.separator).frame(height: StrainLayout.hairline)
                    .accessibilityHidden(true)
            }
            HStack(spacing: NoopTheme.Layout.m) {
                DomainIcon(systemImage: sportSymbol(row.sport), color: NoopTheme.lift, size: DomainIcon.smallSize)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: NoopTheme.Layout.xs / 2) {
                    Text(verbatim: WorkoutSource.displaySport(row.sport)).noopFont(.listTitle)
                    Text(verbatim: detail).noopFont(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let strainText {
                    Text(verbatim: strainText)
                        .noopFont(.rowTitle, color: false)
                        .foregroundStyle(NoopTheme.strain)
                        .monospacedDigit()
                }
                Image(systemName: "chevron.right")
                    .noopFont(.footnote)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, NoopTheme.Layout.rowVerticalPadding)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
