#if DEBUG && !os(watchOS)
import SwiftUI

/// Debug-only gallery of every redesign component, for screenshot review against the mockups in
/// `design/`. Values are placeholders; no screen ships this view. Strings are verbatim because the gallery
/// is a developer tool compiled out of release builds.
public struct NoopDesignGallery: View {
    @State private var segment = "W"
    @State private var selection: Double?
    @State private var loading = true
    @State private var intensity: AmbientIntensity = .balanced

    public init() {}

    private var samplePoints: [NoopChartPoint] {
        [58, 61, 57, 63, 66, 60, 62, 68, 64, 70].enumerated().map { NoopChartPoint(x: Double($0.offset), y: $0.element) }
    }

    private var hrPoints: [NoopChartPoint] {
        [92, 118, 135, 151, 164, 172, 158, 140, 126, 110].enumerated().map { NoopChartPoint(x: Double($0.offset), y: $0.element) }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopTheme.Layout.cardGap) {
                Text(verbatim: "Components").noopFont(.largeTitle)

                NoopGlassCard {
                    HStack(spacing: NoopTheme.Layout.l) {
                        NoopRing(value: 0.86, color: NoopTheme.sleep, diameter: 96, label: "86", unit: "%")
                        NoopRing(value: 0.68, color: NoopTheme.recoveryColor(for: 68), diameter: 96, label: "68", unit: "%")
                        NoopRing(value: nil, color: NoopTheme.strain, diameter: 96, label: "—")
                    }
                    .frame(maxWidth: .infinity)
                }
                .noopEntrance(index: 0)

                NoopGlassCard {
                    NoopArcGauge(value: 11.4 / 21, color: NoopTheme.strain, targetBand: (12.0 / 21)...(15.0 / 21),
                                 number: "11.4", caption: "Strain · of 21")
                        .frame(maxWidth: .infinity)
                }
                .noopEntrance(index: 1)

                NoopSectionHeader("Key metrics", linkTitle: "Edit", action: {})
                NoopGlassCard(flush: true) {
                    VStack(spacing: 0) {
                        NoopMetricRow("Heart rate variability", color: NoopTheme.hrv, subtitle: "Typical 52–66",
                                      value: "62", unit: "ms", showsDivider: false) {
                            NoopLineChart(points: samplePoints, color: NoopTheme.hrv, compact: true)
                        }
                        NoopMetricRow("Resting heart rate", color: NoopTheme.heart, subtitle: "Last: Tue night",
                                      value: nil, unit: "bpm")
                    }
                }

                NoopGlassCard {
                    VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
                        SegmentedPills(["D", "W", "M", "6M", "Y"], selection: $segment) { Text(verbatim: $0) }
                        NoopLineChart(points: samplePoints, color: NoopTheme.hrv, typicalRange: 50...72,
                                      xLabels: ["Mon", "Wed", "Fri", "Sun"], selection: $selection)
                            .frame(height: 160)
                        NoopLineChart(points: hrPoints, color: NoopTheme.heart, zones: true, zoneBounds: 90...190)
                            .frame(height: 120)
                    }
                }

                NoopGlassCard {
                    VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
                        NoopBarChart(values: [72, 45, nil, 28, 81, 66, 0, 90],
                                     colorForValue: { NoopTheme.recoveryColor(for: $0) })
                            .frame(height: 90)
                        ZoneBars(names: ["Z1", "Z2", "Z3", "Z4", "Z5"], values: [22, 18, 9, 4, 1],
                                 trailingLabels: ["22m", "18m", "9m", "4m", "1m"])
                        RangeIndicator(value: 62, range: 30...90, band: 52...66, color: NoopTheme.hrv)
                        StatGrid([StatGridItem("Latest", value: "62", unit: "ms"),
                                  StatGridItem("Low", value: "48", unit: "ms"),
                                  StatGridItem("High", value: nil)], columns: 3)
                    }
                }

                HStack(spacing: NoopTheme.Layout.s) {
                    NoopPill(verbatim: "82%", systemImage: "battery.75")
                    NoopChip(verbatim: "Vitals", isSelected: true)
                    DomainIcon(systemImage: "heart.fill", color: NoopTheme.heart)
                    NoopIconButton(systemImage: "person.crop.circle", accessibilityLabel: "Profile", action: {})
                }
                SourceCaption(verbatim: "NOOP score · computed on iPhone")

                NoopGlassCard {
                    VStack(spacing: 0) {
                        NoopListRow("Data sources", systemImage: "externaldrive", color: NoopTheme.breath,
                                    detail: "WHOOP 4.0, Apple Health", showsDivider: false)
                        NoopListRow("Backup", systemImage: "arrow.clockwise", value: "Today")
                    }
                }

                NoopGlassCard { Text(verbatim: "Loaded content").noopFont(.bodySmall) }
                    .noopSkeleton(loading)
                Button { loading.toggle() } label: { Text(verbatim: "Toggle skeleton") }
                    .buttonStyle(NoopSecondaryButton())
                Button {} label: { Text(verbatim: "Primary") }
                    .buttonStyle(NoopPrimaryButton())

                Picker(selection: $intensity) {
                    ForEach(AmbientIntensity.allCases, id: \.self) { Text(verbatim: $0.rawValue).tag($0) }
                } label: { Text(verbatim: "Ambient") }
                    .pickerStyle(.segmented)
            }
            .padding(.horizontal, NoopTheme.Layout.gutter)
        }
        .noopAmbientBackground(ambientBlobs(for: TodayScores(sleep: 86, recovery: 68, strain: 11.4),
                                            intensity: intensity))
    }
}

#Preview("Redesign gallery") {
    NoopDesignGallery()
}
#endif
