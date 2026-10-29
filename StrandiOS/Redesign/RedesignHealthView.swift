import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

/// The Health tab (redesign round 2 "05 Health"). Every number comes from the existing Health reads:
/// the vital-sign readings resolve through `HealthVitalsInputs` / `BodyVitalSigns` (the same funnel the
/// classic Health Monitor's grid uses), Fitness Age through `FitnessAgeSnapshot`, and the illness heads-up
/// from `AppModel`. Skin temperature is shown only as the difference from the wearer's baseline: an
/// absolute reading is never put on this screen. Blood oxygen shows a value only when the existing logic
/// resolves one (an import, Apple Health, or the default-off strap estimate); otherwise it is an empty row.
/// The classic sections this screen does not restate stay one tap away in "More health".
struct RedesignHealthView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var router: NavRouter
    @Environment(\.scrollToTopSignal) private var scrollToTopSignal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    @AppStorage(NoopTheme.Keys.ambientIntensity) private var ambientIntensityRaw = AmbientIntensity.balanced.rawValue

    @State private var inputs = HealthVitalsInputs()
    @State private var fitness = FitnessAgeSnapshot()
    @State private var loaded = false
    @State private var showsRangeNote = false
    @State private var showAllMetrics = false
    @State private var showFitnessDetail = false

    private static let topAnchorID = "health-top"
    private static let vitalsAnchorID = "health-vitals"
    private static let fitnessAnchorID = "health-fitness"

    private var temperatureUnit: TemperatureUnit {
        UnitPrefs.resolveTemperature(system: UnitSystem(rawValue: unitSystemRaw) ?? .metric, override: temperatureRaw)
    }

    var body: some View {
        // One resolution per body pass. Skin temperature is asked for as the deviation first; a night that
        // only has an absolute is blanked below rather than shown (the redesign's honesty rule).
        let signals = HealthVitalSignals(
            readings: inputs.readings(repo: repo, temperatureUnit: temperatureUnit, skinTempPreferred: .deviation))
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id(Self.topAnchorID)
                    Text("Health")
                        .noopFont(.largeTitle)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, NoopTheme.Layout.gutter)
                    chips(signals, proxy: proxy)
                        .padding(.top, NoopTheme.Layout.m)
                        .noopSkeleton(!loaded, cornerRadius: NoopTheme.Layout.tileRadius)
                    headline(signals)
                        .padding(.horizontal, NoopTheme.Layout.sectionSide)
                        .padding(.top, NoopTheme.Layout.xl)
                        .noopEntrance(index: 0)
                    HealthIllnessHeadsUp()
                        .padding(.horizontal, NoopTheme.Layout.gutter)
                    lanesCard(signals)
                        .padding(.horizontal, NoopTheme.Layout.gutter)
                        .padding(.top, NoopTheme.Layout.l)
                        .noopSkeleton(!loaded)
                        .noopEntrance(index: 1)
                    NoopSectionHeader("Vitals", linkTitle: "All metrics") { showAllMetrics = true }
                        .id(Self.vitalsAnchorID)
                    tiles(signals)
                        .padding(.horizontal, NoopTheme.Layout.gutter)
                        .noopSkeleton(!loaded, cornerRadius: NoopTheme.Layout.tileRadius)
                        .noopEntrance(index: 2)
                    Text("Skin temperature is relative to your baseline, not an absolute reading.")
                        .noopFont(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, NoopTheme.Layout.sectionSide)
                        .padding(.top, NoopTheme.Layout.s)
                    bloodOxygenRow(signals.spo2)
                        .padding(.horizontal, NoopTheme.Layout.gutter)
                        .padding(.top, NoopTheme.Layout.m)
                        .noopEntrance(index: 3)
                    fitnessSection
                        .id(Self.fitnessAnchorID)
                        .noopEntrance(index: 4)
                    NoopSectionHeader("More")
                    moreCard
                        .padding(.horizontal, NoopTheme.Layout.gutter)
                        .noopEntrance(index: 5)
                }
                .padding(.bottom, NoopTheme.Layout.xl)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .onChange(of: scrollToTopSignal) { _, _ in
                withAnimation(NoopTheme.Motion.resolved(NoopTheme.Motion.entrance, reduceMotion: reduceMotion)) {
                    proxy.scrollTo(Self.topAnchorID, anchor: .top)
                }
            }
        }
        .noopAmbientBackground(
            AmbientPreset.health.blobs(intensity: AmbientIntensity(rawValue: ambientIntensityRaw) ?? .balanced))
        .refreshable { await repo.refresh() }
        .task(id: "\(repo.refreshSeq)-\(PuffinExperiment.spo2CandidateDisplayEnabled)") {
            inputs = await HealthVitalsInputs.load(repo: repo)
            fitness = await FitnessAgeSnapshot.load(repo: repo)
            loaded = true
        }
        .navigationDestination(isPresented: $showAllMetrics) { MetricExplorerView() }
        .navigationDestination(isPresented: $showFitnessDetail) {
            HealthClassicSectionScreen(section: .fitnessAge)
                .navigationTitle(Text(Self.title(for: .fitnessAge)))
                .navigationBarTitleDisplayMode(.inline)
        }
        .navigationDestination(for: HealthClassicSection.self) { section in
            HealthClassicSectionScreen(section: section)
                .navigationTitle(Text(Self.title(for: section)))
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Chips

    private func chips(_ signals: HealthVitalSignals, proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: NoopTheme.Layout.s) {
                healthSummaryChip(label: "Vitals", value: signals.summaryWord,
                                  color: signals.summaryColor, systemImage: nil) {
                    scroll(proxy, to: Self.vitalsAnchorID)
                }
                healthSummaryChip(label: "Resting HR", value: signals.rhr?.chipValue,
                                  color: NoopTheme.heart, systemImage: "heart.fill") {
                    scroll(proxy, to: Self.vitalsAnchorID)
                }
                healthSummaryChip(label: "Fitness Age", value: fitnessChipValue,
                                  color: NoopTheme.hrv, systemImage: "figure.run") {
                    scroll(proxy, to: Self.fitnessAnchorID)
                }
            }
            .padding(.horizontal, NoopTheme.Layout.gutter)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private func scroll(_ proxy: ScrollViewProxy, to id: String) {
        withAnimation(NoopTheme.Motion.resolved(NoopTheme.Motion.entrance, reduceMotion: reduceMotion)) {
            proxy.scrollTo(id, anchor: .top)
        }
    }

    /// One summary chip: a tinted circle (a status dot, or an SF Symbol) beside a label and its value.
    /// A nil value reads "—".
    private func healthSummaryChip(label: LocalizedStringKey, value: String?, color: Color, systemImage: String?,
                                   action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: NoopTheme.Layout.s + HealthLayout.chipInnerGap) {
                Circle()
                    .fill(color.opacity(HealthLayout.chipBadgeOpacity))
                    .frame(width: HealthLayout.chipBadge, height: HealthLayout.chipBadge)
                    .overlay {
                        if let systemImage {
                            Image(systemName: systemImage)
                                .noopFont(.footnote, color: false)
                                .fontWeight(.semibold)
                                .foregroundStyle(color)
                        } else {
                            Circle().fill(color).frame(width: HealthLayout.chipDot, height: HealthLayout.chipDot)
                        }
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(label).noopFont(.caption, color: false).foregroundStyle(NoopTheme.textSecondary)
                    Text(verbatim: value ?? "—").noopFont(.rowTitle).monospacedDigit()
                }
            }
            .padding(.leading, NoopTheme.Layout.s + HealthLayout.chipInnerGap)
            .padding(.trailing, NoopTheme.Layout.m + HealthLayout.chipInnerGap)
            .padding(.vertical, NoopTheme.Layout.s + HealthLayout.chipInnerGap)
            .background {
                RoundedRectangle(cornerRadius: HealthLayout.chipRadius, style: .continuous).fill(NoopTheme.control)
            }
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.noopPress)
    }

    private var fitnessChipValue: String? {
        fitness.fitnessAge.map { age in
            let shown = Int(age.rounded())
            return fitnessAgeBoundSymbol(age) + String(localized: "\(shown) yrs")
        }
    }

    // MARK: - Headline

    private func headline(_ signals: HealthVitalSignals) -> some View {
        VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
                    HStack(spacing: NoopTheme.Layout.s) {
                        Image(systemName: signals.headlineSymbol).accessibilityHidden(true)
                        Text("Overnight vitals")
                    }
                    .noopFont(.rowTitle, color: false)
                    .foregroundStyle(signals.summaryColor)
                    Text(verbatim: signals.headlineText)
                        .noopFont(.screenHeadline)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: NoopTheme.Layout.s)
                NoopIconButton(systemImage: "info.circle", accessibilityLabel: "How vitals are judged") {
                    withAnimation(NoopTheme.Motion.resolved(NoopTheme.Motion.entrance, reduceMotion: reduceMotion)) {
                        showsRangeNote.toggle()
                    }
                }
            }
            Text(verbatim: signals.headlineBody)
                .noopFont(.body)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, NoopTheme.Layout.xs)
            if showsRangeNote {
                Text("Once NOOP has 14 nights of history, in-range compares each vital to your own baseline (approximate, not medical advice); until then, typical adult ranges apply.")
                    .noopFont(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            if let latest = signals.latestDayLabel {
                SourceCaption(verbatim: "\(String(localized: "Latest")) · \(latest)")
                    .padding(.top, NoopTheme.Layout.xs)
            }
        }
    }

    // MARK: - Per-signal lanes

    private func lanesCard(_ signals: HealthVitalSignals) -> some View {
        NoopGlassCard(flush: true) {
            VStack(spacing: 0) {
                ForEach(Array(signals.lanes.enumerated()), id: \.element.id) { index, signal in
                    VStack(spacing: 0) {
                        if index > 0 {
                            Rectangle().fill(NoopTheme.separator).frame(height: 1).accessibilityHidden(true)
                        }
                        HStack(spacing: NoopTheme.Layout.m) {
                            VStack(alignment: .leading, spacing: HealthLayout.textGap) {
                                Text(verbatim: signal.name)
                                    .noopFont(.footnote, color: false)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(signal.color)
                                Text(verbatim: signal.stateWord)
                                    .noopFont(.bodySmall, color: false)
                                    .foregroundStyle(NoopTheme.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(width: HealthLayout.laneLabelWidth, alignment: .leading)
                            NoopLineChart(points: signal.points, color: signal.color, compact: true,
                                          accessibilityLabel: Text(verbatim: signal.name))
                                .frame(height: HealthLayout.laneChartHeight)
                        }
                        .padding(.vertical, NoopTheme.Layout.s)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    // MARK: - Vitals tiles

    private func tiles(_ signals: HealthVitalSignals) -> some View {
        let columns = [GridItem(.flexible(), spacing: NoopTheme.Layout.cardGap),
                       GridItem(.flexible(), spacing: NoopTheme.Layout.cardGap)]
        return LazyVGrid(columns: columns, spacing: NoopTheme.Layout.cardGap) {
            ForEach(signals.lanes) { signal in
                NavigationLink(value: TabRoute.metric(signal.metricKey)) {
                    healthVitalTile(signal)
                }
                .buttonStyle(.noopPress)
            }
        }
    }

    /// A tinted vitals tile: the signal name in its colour, the value and unit, a provenance caption, and the
    /// trend line running to the tile's bottom edge.
    private func healthVitalTile(_ signal: HealthVitalSignal) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
                Text(verbatim: signal.name)
                    .noopFont(.rowTitle, color: false)
                    .foregroundStyle(signal.color)
                HStack(alignment: .firstTextBaseline, spacing: HealthLayout.textGap) {
                    if let value = signal.value {
                        Text(verbatim: value).noopFont(.tileNumber)
                        Text(verbatim: signal.unit).noopFont(.unit)
                    } else {
                        Text(verbatim: "—").noopFont(.tileNumber, color: false).foregroundStyle(NoopTheme.textSecondary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                Text(verbatim: signal.caption)
                    .noopFont(.caption)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding([.top, .horizontal], NoopTheme.Layout.l)
            Spacer(minLength: NoopTheme.Layout.s)
            NoopLineChart(points: signal.points, color: signal.color, showsLatestDot: signal.value != nil,
                          accessibilityLabel: Text(verbatim: signal.name))
                .frame(height: HealthLayout.tileChartHeight)
        }
        .frame(maxWidth: .infinity, minHeight: NoopTheme.Layout.tileMinHeight + HealthLayout.tileExtraHeight,
               alignment: .topLeading)
        .background {
            LinearGradient(colors: [signal.color.opacity(HealthLayout.tileTintOpacity), .clear],
                           startPoint: .topLeading, endPoint: HealthLayout.tileTintEnd)
        }
        .noopGlassBackground(cornerRadius: NoopTheme.Layout.tileRadius)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: signal.accessibility))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Blood oxygen

    @ViewBuilder
    private func bloodOxygenRow(_ reading: BodyVitalReading?) -> some View {
        if let reading, let value = reading.value {
            // A value exists only through the existing logic: an import, Apple Health, or the default-off
            // strap estimate (the source is the computed row only for that estimate, so it is labelled).
            let isEstimate = reading.source == .noopComputed
            NavigationLink(value: TabRoute.metric("spo2")) {
                NoopGlassCard {
                    HStack(spacing: NoopTheme.Layout.m) {
                        VStack(alignment: .leading, spacing: HealthLayout.textGap) {
                            Text("Blood oxygen").noopFont(.rowTitle, color: false).foregroundStyle(NoopTheme.breath)
                            Text(verbatim: isEstimate
                                 ? "\(String(localized: "strap estimate (unverified)")) · \(reading.provenanceCaption)"
                                 : reading.provenanceCaption)
                                .noopFont(.footnote)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: NoopTheme.Layout.s)
                        HStack(alignment: .firstTextBaseline, spacing: HealthLayout.textGap) {
                            Text(verbatim: reading.format(value)).noopFont(.rowNumber)
                            Text(verbatim: reading.unit).noopFont(.unit)
                        }
                    }
                }
            }
            .buttonStyle(.noopPress)
        } else {
            HStack(spacing: NoopTheme.Layout.m) {
                VStack(alignment: .leading, spacing: HealthLayout.textGap) {
                    Text("Blood oxygen").noopFont(.rowTitle, color: false).foregroundStyle(NoopTheme.textSecondary)
                    Text("Not measured offline").noopFont(.footnote, color: false).foregroundStyle(NoopTheme.textTertiary)
                    if let reading {
                        Text(verbatim: reading.missingCaption).noopFont(.caption)
                    }
                }
                Spacer(minLength: NoopTheme.Layout.s)
                Text(verbatim: "—").noopFont(.rowNumber, color: false).foregroundStyle(NoopTheme.textTertiary)
            }
            .padding(.vertical, NoopTheme.Layout.rowVerticalPadding)
            .padding(.horizontal, NoopTheme.Layout.l)
            .overlay {
                RoundedRectangle(cornerRadius: NoopTheme.Layout.cardRadius, style: .continuous)
                    .strokeBorder(NoopTheme.trackEmpty, style: StrokeStyle(lineWidth: 1, dash: HealthLayout.dash))
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Fitness Age

    private var fitnessSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            NoopSectionHeader("Fitness Age", linkTitle: "Details") { showFitnessDetail = true }
            fitnessCard
                .padding(.horizontal, NoopTheme.Layout.gutter)
                .noopSkeleton(!loaded)
        }
    }

    private var fitnessCard: some View {
        NoopGlassCard {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
                HStack(alignment: .top, spacing: NoopTheme.Layout.m) {
                    VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
                        Text("Fitness Age").noopFont(.footnote)
                        healthYearsValue(fitness.fitnessAge.map { "\(fitnessAgeBoundSymbol($0))\(Int($0.rounded()))" },
                                         color: NoopTheme.hrv)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
                        Text("Actual age").noopFont(.footnote)
                        healthYearsValue(profile.age > 0 ? "\(profile.age)" : nil, color: NoopTheme.textPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if fitness.fitnessAge != nil {
                    Text("± \(Int(FitnessAgeEngine.displayBandYears)) yr · a fitness comparison, not a biological age")
                        .noopFont(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                } else if loaded {
                    Text(verbatim: fitnessReadyLeadCopy(rhrDays: repo.days.suffix(7).compactMap { $0.restingHr }.count,
                                                        hasAge: profile.age > 0, hasSex: !profile.sex.isEmpty))
                        .noopFont(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let vo2 = fitness.vo2max {
                    HStack(alignment: .firstTextBaseline, spacing: HealthLayout.textGap) {
                        Text("VO₂max").noopFont(.footnote)
                        Text(verbatim: String(format: "%.0f", vo2)).noopFont(.rowTitle).monospacedDigit()
                        Text("ml/kg/min").noopFont(.unit)
                    }
                    SourceCaption(verbatim: "\(String(localized: "On-device")) · \(vo2MaxEstimatorDisplayName(fitness.vo2maxEstimator))")
                } else if fitness.fitnessAge != nil {
                    SourceCaption(verbatim: "\(String(localized: "On-device")) · \(String(localized: "Weekly"))")
                }
            }
        }
    }

    private func healthYearsValue(_ value: String?, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: HealthLayout.textGap) {
            if let value {
                Text(verbatim: value).noopFont(.statNumber, color: false).foregroundStyle(color)
                Text("yrs").noopFont(.unit)
            } else {
                Text(verbatim: "—").noopFont(.statNumber, color: false).foregroundStyle(NoopTheme.textSecondary)
            }
        }
    }

    // MARK: - More health

    private var moreCard: some View {
        NoopGlassCard(flush: true) {
            VStack(spacing: 0) {
                NavigationLink(value: MoreDestination.live) {
                    NoopListRow("Live heart rate", systemImage: "waveform.path.ecg", color: NoopTheme.heart,
                                showsDivider: false)
                }
                NavigationLink(value: MoreDestination.explore) {
                    NoopListRow("All metrics", systemImage: "square.grid.2x2", color: NoopTheme.hrv)
                }
                NavigationLink(value: HealthClassicSection.skinTemperature) {
                    NoopListRow("Skin temperature", systemImage: "thermometer.medium", color: NoopTheme.temp)
                }
                NavigationLink(value: HealthClassicSection.vitality) {
                    NoopListRow("Vitality", systemImage: "sparkles", color: NoopTheme.recovery)
                }
                NavigationLink(value: HealthClassicSection.contributors) {
                    NoopListRow("Contributors", systemImage: "chart.bar.fill", color: NoopTheme.recovery)
                }
                NavigationLink(value: HealthClassicSection.sync) {
                    NoopListRow("Strap sync", systemImage: "arrow.triangle.2.circlepath", color: NoopTheme.breath)
                }
                Button { router.openLabBook() } label: {
                    NoopListRow("Lab Book", systemImage: "books.vertical.fill", color: NoopTheme.hrv)
                }
                Button { router.openFusedRecord() } label: {
                    NoopListRow("Your Data, Fused", systemImage: "square.stack.3d.up.fill", color: NoopTheme.coach)
                }
            }
            .buttonStyle(.noopPress)
        }
    }

    private static func title(for section: HealthClassicSection) -> LocalizedStringKey {
        switch section {
        case .fitnessAge: return "Fitness Age"
        case .skinTemperature: return "Skin temperature"
        case .vitality: return "Vitality"
        case .contributors: return "Contributors"
        case .sync: return "Strap sync"
        }
    }
}

// MARK: - Illness heads-up leaf

/// The illness heads-up, shown only when the engine returned a non-quiet level. A leaf so the Health tab
/// does not observe `AppModel` (which publishes live heart rate about once a second).
private struct HealthIllnessHeadsUp: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let illness = model.illnessSignal, illness.level != .quiet {
            NavigationLink(value: HealthClassicSection.skinTemperature) {
                HeadsUpCard(result: illness, distance: model.illnessDistance, redesign: true)
            }
            .buttonStyle(.noopPress)
            .padding(.top, NoopTheme.Layout.l)
        }
    }
}

// MARK: - Signals

/// One overnight signal on the Health tab, resolved from a `BodyVitalReading`.
private struct HealthVitalSignal: Identifiable {
    let id: String
    let metricKey: String
    let name: String
    let color: Color
    /// The formatted number without its unit; nil when missing (or a skin reading that is not relative).
    let value: String?
    let unit: String
    let band: VitalBands.Band
    let basis: VitalBands.Basis
    let stateWord: String
    let caption: String
    let points: [NoopChartPoint]
    let accessibility: String

    var chipValue: String? { value.map { "\($0) \(unit)" } }
}

/// The four overnight signals plus blood oxygen, and the headline built from their existing bands.
private struct HealthVitalSignals {
    let hrv: HealthVitalSignal?
    let rhr: HealthVitalSignal?
    let resp: HealthVitalSignal?
    let skin: HealthVitalSignal?
    let spo2: BodyVitalReading?
    let latestDayLabel: String?

    init(readings: [BodyVitalReading]) {
        func reading(_ key: String) -> BodyVitalReading? { readings.first { $0.key == key } }
        hrv = reading("hrv").map { Self.signal($0, metricKey: "hrv", name: String(localized: "HRV"), color: NoopTheme.hrv) }
        rhr = reading("rhr").map {
            Self.signal($0, metricKey: "rhr", name: String(localized: "Resting HR"), color: NoopTheme.heart)
        }
        resp = reading("resp").map {
            Self.signal($0, metricKey: "resp_rate", name: String(localized: "Respiratory"), color: NoopTheme.breath)
        }
        skin = reading("skin").map {
            Self.signal($0, metricKey: "skin_temp", name: String(localized: "Skin temp"), color: NoopTheme.temp)
        }
        spo2 = reading("spo2")
        let shown = [hrv, rhr, resp, skin].compactMap { $0 }.filter { $0.value != nil }
        // Only days a shown reading came from (a blanked absolute skin night does not count).
        let relevant = readings.filter { r in
            r.key != "skin" ? ["hrv", "rhr", "resp"].contains(r.key) : (skin?.value != nil)
        }
        latestDayLabel = shown.isEmpty ? nil : BodyVitalSigns.latestDayLabel(relevant)
    }

    var lanes: [HealthVitalSignal] { [hrv, rhr, resp, skin].compactMap { $0 } }

    private var measured: [HealthVitalSignal] { lanes.filter { $0.value != nil && $0.band != .noData } }
    private var outside: [HealthVitalSignal] { measured.filter { $0.band == .outOfRange } }

    var summaryWord: String? {
        guard !measured.isEmpty else { return nil }
        return outside.isEmpty ? String(localized: "Typical") : String(localized: "Off baseline")
    }

    var summaryColor: Color {
        guard !measured.isEmpty else { return NoopTheme.textTertiary }
        return outside.isEmpty ? NoopTheme.recovery : NoopTheme.recoveryMid
    }

    var headlineSymbol: String {
        guard !measured.isEmpty else { return "moon.zzz" }
        return outside.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
    }

    var headlineText: String {
        guard !measured.isEmpty else { return String(localized: "No overnight vitals yet") }
        switch outside.count {
        case 0: return String(localized: "All typical")
        case 1: return String(localized: "1 signal to watch")
        default: return String(localized: "\(outside.count) signals to watch")
        }
    }

    var headlineBody: String {
        guard !measured.isEmpty else { return String(localized: "Wear your strap overnight and your vitals appear here.") }
        if !outside.isEmpty {
            return String(localized: "Outside range: \(outside.map(\.name).joined(separator: ", "))")
        }
        return measured.allSatisfy { $0.basis == .personal }
            ? String(localized: "Every signal is inside your own range.")
            : String(localized: "Every signal is inside the typical adult range. Your own baseline takes over after 14 nights.")
    }

    private static func signal(_ r: BodyVitalReading, metricKey: String, name: String, color: Color) -> HealthVitalSignal {
        // Skin temperature is shown only relative to baseline: an absolute night is blanked, with its own
        // caption, and its chart is not drawn.
        let blankedAbsolute = r.key == "skin" && (r.value.map(VitalBands.isAbsoluteSkinTemp) ?? false)
        let value = blankedAbsolute ? nil : r.value
        let caption = blankedAbsolute
            ? String(localized: "Needs about 4 worn nights to learn your baseline")
            : r.provenanceCaption
        let series = blankedAbsolute ? [] : (r.sparkline ?? [])
        let points = series.enumerated().map { NoopChartPoint(x: Double($0.offset), y: $0.element) }
        let band: VitalBands.Band = blankedAbsolute ? .noData : r.banding.band
        let formatted = value.map(r.format)
        let stateWord = blankedAbsolute ? String(localized: "No data") : r.stateText
        let spoken = formatted.map { "\(name): \($0) \(r.unit), \(stateWord), \(caption)" }
            ?? "\(name): \(String(localized: "No data")), \(caption)"
        return HealthVitalSignal(id: r.key, metricKey: metricKey, name: name, color: color, value: formatted,
                                 unit: r.unit, band: band, basis: r.banding.basis, stateWord: stateWord,
                                 caption: caption, points: points, accessibility: spoken)
    }
}

/// Geometry from the round 2 "05 Health" board with no `NoopTheme` token.
private enum HealthLayout {
    static let chipRadius: CGFloat = 18
    static let chipBadge: CGFloat = 34
    static let chipDot: CGFloat = 10
    static let chipBadgeOpacity: Double = 0.18
    static let chipInnerGap: CGFloat = 2
    static let textGap: CGFloat = 2
    static let laneLabelWidth: CGFloat = 104
    static let laneChartHeight: CGFloat = 40
    static let tileChartHeight: CGFloat = 76
    static let tileExtraHeight: CGFloat = 60
    static let tileTintOpacity: Double = 0.16
    static let tileTintEnd = UnitPoint(x: 0.6, y: 0.9)
    static let dash: [CGFloat] = [4, 4]
}
