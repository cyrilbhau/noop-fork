import SwiftUI
import StrandDesign

/// The user's dashboard selection uses the same day snapshot and readings as the Key metrics rows.
struct YourCardsSection: View {
    let cards: [DashboardCard]
    let inputs: TodayCardInputs
    let isAccessibilitySize: Bool
    let loading: Bool
    let refreshSequence: Int
    let gatedCaption: String?
    let onEdit: () -> Void
    let onCoach: () -> Void
    let onStepSources: () -> Void
    let loadStepsAverage: (String) async -> RollingStepsAverage?
    @State private var captionHeights: [DashboardCard: CGFloat] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NoopSectionHeader("Your cards", linkTitle: "Edit", action: onEdit)
                .padding(.horizontal, -NoopTheme.Layout.gutter)
            if cards.isEmpty {
                Text(verbatim: gatedCaption ?? String(localized: "No data"))
                    .noopFont(.bodySmall)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(NoopTheme.Layout.yourCardPadding)
                    .background(tileSurface)
            } else if isAccessibilitySize {
                VStack(spacing: NoopTheme.Layout.cardGap) {
                    ForEach(cards) { card in tile(card) }
                }
            } else {
                Grid(alignment: .topLeading,
                     horizontalSpacing: NoopTheme.Layout.cardGap,
                     verticalSpacing: NoopTheme.Layout.cardGap) {
                    ForEach(0..<((cards.count + 1) / 2), id: \.self) { row in
                        GridRow(alignment: .top) {
                            tile(cards[row * 2])
                                .gridCellColumns(row * 2 + 1 < cards.count ? 1 : 2)
                            if row * 2 + 1 < cards.count { tile(cards[row * 2 + 1]) }
                        }
                    }
                }
            }
        }
        .onPreferenceChange(YourCardCaptionHeights.self) { captionHeights = $0 }
    }

    private func tile(_ card: DashboardCard) -> some View {
        YourCardTile(card: card, inputs: inputs, isAccessibilitySize: isAccessibilitySize,
                     loading: loading, refreshSequence: refreshSequence,
                     captionMinimum: captionMinimum(for: card),
                     onCoach: onCoach, onStepSources: onStepSources, loadStepsAverage: loadStepsAverage)
            .id(card)
    }

    private func captionMinimum(for card: DashboardCard) -> CGFloat {
        guard !isAccessibilitySize, let index = cards.firstIndex(of: card) else { return 0 }
        let rowStart = index - index % 2
        return cards[rowStart..<min(rowStart + 2, cards.count)]
            .filter { !$0.isShortcut }.compactMap { captionHeights[$0] }.max() ?? 0
    }

    private var tileSurface: some View {
        RoundedRectangle(cornerRadius: NoopTheme.Layout.tileRadius, style: .continuous)
            .fill(NoopTheme.card)
            .overlay {
                RoundedRectangle(cornerRadius: NoopTheme.Layout.tileRadius, style: .continuous)
                    .strokeBorder(NoopTheme.cardBorder, lineWidth: NoopTheme.Layout.yourCardBorderWidth)
            }
    }
}

private struct YourCardTile: View {
    let card: DashboardCard
    let inputs: TodayCardInputs
    let isAccessibilitySize: Bool
    let loading: Bool
    let refreshSequence: Int
    let captionMinimum: CGFloat
    let onCoach: () -> Void
    let onStepSources: () -> Void
    let loadStepsAverage: (String) async -> RollingStepsAverage?
    @State private var average: RollingStepsAverage?
    @State private var averageIdentity: String?
    @ScaledMetric(relativeTo: .subheadline) private var iconDimension = NoopTheme.Layout.yourCardIcon
    @ScaledMetric(relativeTo: .subheadline) private var chipDimension = NoopTheme.Layout.shortcutIconChip

    private var loadIdentity: String { "\(card.rawValue)|\(inputs.selectedDayKey)|\(refreshSequence)" }

    private var readout: TodayCardReadout {
        var snapshot = inputs
        if card == .stepsAverage30 {
            snapshot.rollingStepsAverage = averageIdentity == loadIdentity ? average : nil
        }
        return TodayCardResolver.readout(card, snapshot)
    }

    var body: some View {
        interactiveTile
            .noopSkeleton(loading, cornerRadius: NoopTheme.Layout.tileRadius)
            .task(id: loadIdentity) {
                guard card == .stepsAverage30 else { return }
                let identity = loadIdentity
                let result = await loadStepsAverage(inputs.selectedDayKey)
                guard !Task.isCancelled else { return }
                average = result
                averageIdentity = identity
            }
    }

    @ViewBuilder
    private var interactiveTile: some View {
        switch readout.tap {
        case .route(let route):
            NavigationLink(value: route) { content }
                .buttonStyle(.noopPress)
        case .stepSources:
            Button(action: onStepSources) { content }
                .buttonStyle(.noopPress)
        case .coachSheet:
            Button(action: onCoach) { content }
                .buttonStyle(.noopPress)
        case .none:
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
            HStack(alignment: .top, spacing: NoopTheme.Layout.s) {
                icon
                Text(verbatim: TodayCardResolver.cardTitle(card))
                    .noopFont(.footnote, color: false)
                    .fontWeight(.semibold)
                    .foregroundStyle(readout.tint.redesignColor)
                    .lineLimit(isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if readout.tap != .none {
                    Image(systemName: "chevron.right")
                        .noopFont(.caption)
                        .accessibilityHidden(true)
                }
            }
            if card.isShortcut {
                Text(verbatim: readout.caption ?? "")
                    .noopFont(.footnote)
                    .lineLimit(isAccessibilitySize ? nil : 4)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: NoopTheme.Layout.xs) {
                    Text(verbatim: numberParts.primary ?? "—")
                        .noopFont(.tileNumber, color: false)
                        .foregroundStyle(readout.value == nil ? NoopTheme.textTertiary : NoopTheme.textPrimary)
                        .lineLimit(isAccessibilitySize ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    if readout.value != nil, let unit = numberParts.secondary {
                        Text(verbatim: unit).noopFont(.unit)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let caption = readout.caption {
                    Text(verbatim: caption)
                        .noopFont(.caption, color: false)
                        .foregroundStyle(readout.captionIsStale ? NoopTheme.recoveryMid : NoopTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(key: YourCardCaptionHeights.self,
                                                       value: [card: geometry.size.height])
                            }
                        }
                        .frame(minHeight: captionMinimum, alignment: .topLeading)
                }
            }
        }
        .padding(NoopTheme.Layout.yourCardPadding)
        .frame(maxWidth: .infinity, minHeight: NoopTheme.Layout.yourCardMinHeight,
               maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: NoopTheme.Layout.tileRadius, style: .continuous)
                .fill(NoopTheme.card)
                .overlay {
                    RoundedRectangle(cornerRadius: NoopTheme.Layout.tileRadius, style: .continuous)
                        .strokeBorder(NoopTheme.cardBorder, lineWidth: NoopTheme.Layout.yourCardBorderWidth)
                }
        }
        .contentShape(RoundedRectangle(cornerRadius: NoopTheme.Layout.tileRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spokenLabel))
    }

    /// Compound readings retain the shared value, with the goal or temperature unit in the smaller ramp.
    private var numberParts: (primary: String?, secondary: String?) {
        guard let value = readout.value else { return (nil, nil) }
        if card == .hydration, let divider = value.range(of: " / ") {
            return (String(value[..<divider.lowerBound]), "/ " + value[divider.upperBound...])
        }
        if card == .skinTemp, let divider = value.firstIndex(of: " ") {
            return (String(value[..<divider]), String(value[value.index(after: divider)...]))
        }
        return (value, readout.unit)
    }

    private var icon: some View {
        Image(systemName: card.icon)
            .noopFont(.listTitle, color: false)
            .foregroundStyle(readout.tint.redesignColor)
            .frame(width: card.isShortcut ? chipDimension : iconDimension,
                   height: card.isShortcut ? chipDimension : iconDimension)
            .background {
                if card.isShortcut {
                    RoundedRectangle(cornerRadius: NoopTheme.Layout.s, style: .continuous)
                        .fill(readout.tint.redesignColor.opacity(NoopTheme.Layout.shortcutIconOpacity))
                }
            }
            .accessibilityHidden(true)
    }

    private var spokenLabel: String {
        var pieces = [TodayCardResolver.cardTitle(card)]
        if !card.isShortcut {
            if let value = readout.value {
                let spokenUnit: String?
                switch card == .fitnessAge ? "yrs" : readout.unit {
                case "ms": spokenUnit = String(localized: "milliseconds")
                case "bpm": spokenUnit = String(localized: "beats per minute")
                case "rpm": spokenUnit = String(localized: "breaths per minute")
                case "kcal": spokenUnit = String(localized: "kilocalories")
                case "yrs": spokenUnit = String(localized: "years")
                case "%": spokenUnit = String(localized: "percent")
                default: spokenUnit = readout.unit
                }
                pieces.append([spokenValue(value), spokenUnit].compactMap { $0 }.joined(separator: " "))
            } else { pieces.append(String(localized: "No data")) }
        }
        if let caption = readout.caption { pieces.append(caption) }
        return pieces.joined(separator: ", ")
    }

    private func spokenValue(_ value: String) -> String {
        let formatter = MeasurementFormatter()
        formatter.locale = inputs.locale
        formatter.unitStyle = .long
        formatter.unitOptions = .providedUnit
        if card == .hydration, value.hasSuffix(" L") {
            return String(value.dropLast(2)) + " " + formatter.string(from: UnitVolume.liters)
        }
        if card == .skinTemp {
            return value.replacingOccurrences(of: "°C", with: " " + formatter.string(from: UnitTemperature.celsius))
                .replacingOccurrences(of: "°F", with: " " + formatter.string(from: UnitTemperature.fahrenheit))
        }
        if card == .sleep, let minutes = inputs.displayDay?.totalSleepMin {
            let duration = DateComponentsFormatter()
            duration.allowedUnits = [.hour, .minute]
            duration.unitsStyle = .full
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = inputs.locale
            duration.calendar = calendar
            return duration.string(from: (minutes.rounded()) * 60) ?? value
        }
        return value
    }
}

private struct YourCardCaptionHeights: PreferenceKey {
    static var defaultValue: [DashboardCard: CGFloat] { [:] }

    static func reduce(value: inout [DashboardCard: CGFloat], nextValue: () -> [DashboardCard: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: max)
    }
}

extension TodayCardReadout.Tint {
    var redesignColor: Color {
        switch self {
        case .hrv: return NoopTheme.hrv
        case .heart: return NoopTheme.heart
        case .breath: return NoopTheme.breath
        case .lift: return NoopTheme.lift
        case .stress: return NoopTheme.stress
        case .recovery: return NoopTheme.recovery
        case .sleep: return NoopTheme.sleep
        case .temp: return NoopTheme.temp
        case .coach: return NoopTheme.coach
        case .muted: return NoopTheme.textTertiary
        }
    }
}
