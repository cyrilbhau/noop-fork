import SwiftUI
import StrandDesign
import WhoopStore
import StrandAnalytics
import WhoopProtocol

/// The iPhone redesign's Today (`docs/personal/REDESIGN-IMPLEMENTATION.md` Phase 3; mockups round 2
/// "01 Today" / "01b Today, loading", round 3 E1 / E2). Presentation only: every value comes from the
/// SAME `TodayDayModel` loader `LiquidTodayView` uses (no second copy of its reads), and every derived
/// read-out (Recovery carry, live Strain, synthesis line, step precedence, key-metric carries) goes
/// through the model's shared helpers so this screen and Liquid Today cannot disagree about a number.
///
/// Selected by `NoopTheme.Keys.redesignEnabled` in `RootTabView.todayTabRoot`; switching swaps only the
/// root content, so the tab's NavigationStack and its path survive.
struct RedesignTodayView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var router: NavRouter
    @EnvironmentObject private var profile: ProfileStore
    /// For pull-to-refresh only (`syncNow()`), exactly as Liquid Today. BLEManager publishes connection
    /// state, never the 1 Hz heart rate, so observing it does not re-render Today every second.
    @EnvironmentObject private var ble: BLEManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openProfile) private var openProfile
    @Environment(\.scrollToTopSignal) private var scrollToTopSignal

    @StateObject private var dayModel = TodayDayModel()

    // Shared preferences: the same keys Liquid Today and the Customise sheet read and write.
    @AppStorage(DayCycleMode.storageKey) private var dayCycleModeRaw = DayCycleMode.sleepOnset.rawValue
    @AppStorage(HydrationStore.enabledKey) private var hydrationEnabled = false
    @AppStorage(DashboardCardPrefs.selectionKey) private var dashboardCardsRaw = ""
    @AppStorage(HostedCardPrefs.selectionKey) private var hostedCardsRaw = ""
    @AppStorage(TodayLayoutPrefs.orderKey) private var sectionOrderRaw = ""
    @AppStorage(TodayLayoutPrefs.hiddenKey) private var hiddenSectionsRaw = ""
    @AppStorage(KeyMetricPrefs.layoutKey) private var keyMetricsRaw = ""
    @AppStorage("today.keyMetricsDetailed") private var keyMetricsDetailed = false
    @AppStorage("today.keyMetricsWindowDays") private var keyMetricsWindowDays = 14
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceSystemRaw = ""

    // Redesign settings (Phase 1 keys).
    @AppStorage(NoopTheme.Keys.ringsFillOnLoad) private var ringsFillOnLoad = true
    @AppStorage(NoopTheme.Keys.ambientFromScores) private var ambientFromScores = true
    @AppStorage(NoopTheme.Keys.ambientIntensity) private var ambientIntensityRaw = AmbientIntensity.balanced.rawValue

    @State private var showDayPicker = false
    @State private var customizationDestination: TodayCustomizationDestination?
    /// Whether the ACTIVE strap is positively a WHOOP 4.0 (registry evidence via the canonical resolver).
    /// Drives the honest "not measured" Blood Oxygen row; unknown stays false.
    @State private var activeIsWhoop4 = false

    private static let topAnchorID = "redesignToday.top"

    // MARK: - Resolved state (all from the shared model)

    private var selectedDayOffset: Int {
        get { dayModel.selectedDayOffset }
        nonmutating set { dayModel.selectedDayOffset = newValue }
    }
    private var selectedLogicalDay: Date { dayModel.selectedLogicalDay }
    private var selectedDayKey: String { dayModel.selectedDayKey(repo: repo) }
    private var displayDay: DailyMetric? { dayModel.cachedDisplayDay }
    private var chargeDisplay: LiquidTodayView.ChargeDisplay { dayModel.cachedChargeDisplay }
    private var isToday: Bool { selectedDayOffset == 0 }
    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    private var temperatureUnit: TemperatureUnit {
        UnitPrefs.resolveTemperature(system: unitSystem, override: temperatureRaw)
    }
    private var distanceUnitSystem: UnitSystem {
        UnitPrefs.resolveDistance(system: unitSystem, override: distanceSystemRaw)
    }
    private var ambientIntensity: AmbientIntensity {
        AmbientIntensity(rawValue: ambientIntensityRaw) ?? .balanced
    }
    private var ringsAnimate: Bool {
        NoopTheme.Motion.ringsAnimate(reduceMotion: reduceMotion, fillOnLoad: ringsFillOnLoad)
    }
    private var loading: Bool { !dayModel.dataLoaded }
    /// The resolved Strain on the stored 0–100 axis (live in-progress for today, #1001).
    private var strainStored: Double? { dayModel.effortStrain(displayDay) }

    /// The user's section order and visibility, shared with Liquid Today and the Customise sheet. Sections
    /// the redesign folds into another card (synthesis → rings card) or does not draw are skipped.
    private var sectionOrder: [TodaySection] {
        TodayLayoutPrefs.visibleOrder(orderRaw: sectionOrderRaw, hiddenRaw: hiddenSectionsRaw)
    }

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: NoopTheme.Layout.cardGap) {
                    Color.clear.frame(height: 0).id(Self.topAnchorID)
                    header
                    if isToday { StrapAwayBanner().noopEntrance(index: 0) }
                    // Pinned like Liquid/classic Today so a raised alert or a running workout is never
                    // reordered below the fold. Each renders nothing when idle.
                    HealthAlertBanner()
                    ActiveWorkoutIndicatorSection()
                    ForEach(Array(sectionOrder.enumerated()), id: \.element) { index, section in
                        sectionView(section, index: index + 1)
                    }
                    AutoWorkoutCard()
                    customizeButton
                }
                .padding(.horizontal, NoopTheme.Layout.gutter)
                .padding(.bottom, NoopTheme.Layout.xl)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .onChange(of: scrollToTopSignal) { _, _ in
                withAnimation(NoopTheme.Motion.resolved(NoopTheme.Motion.entrance, reduceMotion: reduceMotion)) {
                    proxy.scrollTo(Self.topAnchorID, anchor: .top)
                }
            }
        }
        .noopAmbientBackground(ambientBlobs(for: ambientScores, intensity: ambientIntensity),
                               enabled: ambientFromScores)
        .simultaneousGesture(daySwipeGesture)
        .sensoryFeedback(.selection, trigger: selectedDayOffset)
        .refreshable { await pullToRefresh() }
        // Same trigger set as Liquid Today, so a refresh, a day change, a logged drink or a day-cycle
        // change re-reads exactly as it does there.
        .task(id: "\(repo.refreshSeq)-\(selectedDayOffset)-\(repo.hydrationSeq)-\(hydrationEnabled)-\(dayCycleModeRaw)") {
            DashboardCardPrefs.migrateLegacyStepsAverage()
            await load()
        }
        .task(id: repo.deviceId) { await resolveActiveFamily() }
        .sheet(item: $customizationDestination) { destination in
            TodayCustomizationSheet(
                initialDestination: destination,
                sectionOrderRaw: $sectionOrderRaw,
                hiddenSectionsRaw: $hiddenSectionsRaw,
                keyMetricsRaw: $keyMetricsRaw,
                keyMetricsDetailed: $keyMetricsDetailed,
                keyMetricsWindowDays: $keyMetricsWindowDays,
                dashboardCardsRaw: $dashboardCardsRaw,
                hostedCardsRaw: $hostedCardsRaw
            )
        }
    }

    @ViewBuilder
    private func sectionView(_ section: TodaySection, index: Int) -> some View {
        switch section {
        case .hero:
            ringsCard.noopSkeleton(loading).noopEntrance(index: index)
            if chargeLegacyRRGap { ChargeLegacyRRGapNote() }
        case .heartRate:
            heartRateSection.noopEntrance(index: index)
        case .keyMetrics:
            keyMetricsSection.noopEntrance(index: index)
        case .workouts:
            activitySection.noopEntrance(index: index)
        case .addedCards:
            if isToday { hostedCardsSection.noopEntrance(index: index) }
        case .menstrualCycle:
            if isToday { MenstrualCycleHomeCard() }
        case .journal:
            if isToday { JournalReminderCard() }
        case .synthesis, .liveSession, .recoveryVitals, .yourCards:
            // Synthesis lives inside the rings card; the vitals are the key-metric rows. Live Session
            // and "Your cards" are not part of the redesigned Today (their destinations stay reachable
            // from Profile and the other tabs).
            EmptyView()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: NoopTheme.Layout.m) {
            Button { showDayPicker = true } label: {
                VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
                    Text(verbatim: dayTitle)
                        .noopFont(.largeTitle)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: dateLine)
                        .noopFont(.footnote)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.noopPress)
            .accessibilityLabel("\(dayTitle). Tap to pick a day, swipe to change day.")
            .popover(isPresented: $showDayPicker) {
                DatePicker("", selection: dayPickerBinding, in: ...Repository.logicalDay(Date()),
                           displayedComponents: [.date])
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(NoopTheme.Layout.m)
                    .frame(minWidth: Self.datePickerMinWidth, minHeight: Self.datePickerMinHeight)
                    .presentationCompactAdaptation(.popover)
            }

            HStack(spacing: NoopTheme.Layout.s) {
                StrapBatteryPill()
                Button {
                    openProfile?()
                } label: {
                    ProfileAvatarView(imageData: profile.avatarImageData, size: NoopTheme.Layout.iconButton,
                                      fallbackTint: NoopTheme.textSecondary)
                        .frame(width: NoopTheme.Layout.minTouchTarget, height: NoopTheme.Layout.minTouchTarget)
                        .contentShape(Circle())
                }
                .buttonStyle(.noopPress)
                .accessibilityLabel("Profile and settings")
            }
        }
        .padding(.top, NoopTheme.Layout.s)
    }

    private static let datePickerMinWidth: CGFloat = 320
    private static let datePickerMinHeight: CGFloat = 360

    private var dayTitle: String {
        switch selectedDayOffset {
        case 0: return String(localized: "Today")
        case 1: return String(localized: "Yesterday")
        default: return selectedLogicalDay.formatted(.dateTime.weekday(.wide).locale(AppLanguage.activeLocale))
        }
    }

    private var dateLine: String {
        selectedLogicalDay.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)
            .locale(AppLanguage.activeLocale))
    }

    private var dayPickerBinding: Binding<Date> {
        Binding(
            get: { selectedLogicalDay },
            set: { newValue in
                selectedDayOffset = LiquidTodayView.pickedDayOffset(pickedDate: newValue,
                                                                    anchorLogicalDay: Repository.logicalDay(Date()))
                showDayPicker = false
            }
        )
    }

    /// Horizontal swipe between days (right = older, left = newer — `TodayView.daySwipeDelta`), clamped
    /// to [today, earliest]; the same helpers Liquid Today uses. The incoming day's rings refill.
    private var daySwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let dx = value.translation.width, dy = value.translation.height
                guard abs(dx) > abs(dy) * 1.5, abs(dx) > 50 else { return }
                let maxOffset = LiquidTodayView.maxDayOffset(earliestDayKey: repo.freshness.earliestDay,
                                                             todayKey: Repository.logicalDayKey(Date()))
                let next = LiquidTodayView.clampedDayOffset(current: selectedDayOffset,
                                                            delta: TodayView.daySwipeDelta(dx: dx),
                                                            maxOffset: maxOffset)
                guard next != selectedDayOffset else { return }
                withAnimation(NoopTheme.Motion.resolved(NoopTheme.Motion.daySwipe, reduceMotion: reduceMotion)) {
                    selectedDayOffset = next
                }
            }
    }

    // MARK: - Rings card

    private var ringsCard: some View {
        NoopGlassCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: NoopTheme.Layout.xs) {
                    sleepRing
                    recoveryRing
                    strainRing
                }
                // Day change re-mounts the rings so the incoming day refills even when a value repeats.
                .id(selectedDayOffset)
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(NoopTheme.separator)
                    .frame(height: Self.hairline)
                    .padding(.vertical, NoopTheme.Layout.l)

                summary
            }
        }
    }

    private static let ringDiameter: CGFloat = 96
    private static let hairline: CGFloat = 1

    private var sleepRing: some View {
        let score = dayModel.restScore
        return ringColumn(
            route: TabRoute.sleep,
            ring: NoopRing(value: score.map { $0 / 100 }, color: NoopTheme.sleep, diameter: Self.ringDiameter,
                           label: score.map { String(Int($0.rounded())) } ?? Self.dash,
                           unit: score == nil ? nil : "%",
                           animate: ringsAnimate,
                           accessibilityLabel: String(localized: "Sleep"),
                           accessibilityValue: score.map { String(localized: "\(Int($0.rounded())) percent") }
                               ?? String(localized: "No data")),
            title: String(localized: "Sleep"),
            caption: score == nil ? String(localized: "No data") : sleepDurationText,
            captionColor: NoopTheme.textSecondary)
    }

    private var recoveryRing: some View {
        let display = chargeDisplay
        let pct = display.pct
        let band = pct.map { NoopTheme.recoveryBand(for: $0) }
        let label: String
        let caption: String
        let spoken: String
        switch display {
        case .scored(let p):
            label = String(Int(p.rounded()))
            caption = Self.bandWord(NoopTheme.recoveryBand(for: p))
            spoken = String(localized: "\(Int(p.rounded())) percent") + ", " + caption
        case .carried(let p, let carried):
            label = String(Int(p.rounded()))
            caption = carried
            spoken = String(localized: "\(Int(p.rounded())) percent") + ", "
                + Self.bandWord(NoopTheme.recoveryBand(for: p)) + ", " + carried
        case .calibrating(let nights):
            label = "\(nights)/\(Baselines.minNightsSeed)"
            caption = String(localized: "Calibrating")
            spoken = display.calibrationDetail ?? caption
        case .noData:
            label = Self.dash
            caption = String(localized: "No data")
            spoken = caption
        }
        return ringColumn(
            route: RedesignRoute.recovery(dayKey: isToday ? nil : selectedDayKey),
            ring: NoopRing(value: pct.map { $0 / 100 },
                           color: band.map { NoopTheme.recoveryColor(for: $0) } ?? NoopTheme.recovery,
                           diameter: Self.ringDiameter, label: label, unit: pct == nil ? nil : "%",
                           animate: ringsAnimate,
                           accessibilityLabel: String(localized: "Recovery"), accessibilityValue: spoken),
            title: String(localized: "Recovery"),
            caption: caption,
            captionColor: band.map { NoopTheme.recoveryColor(for: $0) } ?? NoopTheme.textTertiary)
    }

    private var strainRing: some View {
        let stored = strainStored
        let scaleMax = UnitFormatter.effortScaleMax(effortScale)
        // The user's scale, honestly: NOOP's 0–100 or WHOOP's 0–21 (#45 — one decimal on the 0–21 axis,
        // a whole number on 0–100, matching the Liquid hero).
        let label = stored.map {
            effortScale == .whoop ? UnitFormatter.effortDisplay($0, scale: .whoop)
                                  : String(Int(UnitFormatter.effortValue($0, scale: .hundred).rounded()))
        }
        let ofScale = String(localized: "of \(scaleMax)")
        return ringColumn(
            route: RedesignRoute.strain(dayKey: isToday ? nil : selectedDayKey),
            ring: NoopRing(value: stored.map { $0 / 100 }, color: NoopTheme.strain, diameter: Self.ringDiameter,
                           label: label ?? Self.dash, animate: ringsAnimate,
                           accessibilityLabel: String(localized: "Strain"),
                           accessibilityValue: label.map { "\($0) \(ofScale)" } ?? String(localized: "No data")),
            title: String(localized: "Strain"),
            caption: stored == nil ? String(localized: "No data") : ofScale,
            captionColor: NoopTheme.textSecondary)
    }

    private func ringColumn<Route: Hashable>(route: Route, ring: NoopRing, title: String, caption: String?,
                            captionColor: Color) -> some View {
        NavigationLink(value: route) {
            VStack(spacing: NoopTheme.Layout.xs) {
                ring
                    .padding(.bottom, NoopTheme.Layout.xs)
                Text(verbatim: title)
                    .noopFont(.rowTitle)
                    .multilineTextAlignment(.center)
                    .accessibilityHidden(true)
                if let caption {
                    Text(verbatim: caption)
                        .noopFont(.caption, color: false)
                        .foregroundStyle(captionColor)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.noopPress)
    }

    /// The selected night's asleep time, "7h 42m", or nil.
    private var sleepDurationText: String? {
        guard let m = displayDay?.totalSleepMin else { return nil }
        return "\(Int(m) / 60)h \(Int(m) % 60)m"
    }

    /// The Recovery band word, from the existing catalogue (Low / Moderate / High). The band thresholds are
    /// `NoopTheme.recoveryBand` (pinned to `RecoveryScorer`'s 34 / 67).
    static func bandWord(_ band: NoopTheme.RecoveryBand) -> String {
        switch band {
        case .low: return String(localized: "Low")
        case .mid: return String(localized: "Moderate")
        case .high: return String(localized: "High")
        }
    }

    // MARK: Summary (the existing synthesis)

    @ViewBuilder
    private var summary: some View {
        VStack(alignment: .leading, spacing: NoopTheme.Layout.s) {
            if let headline = summaryHeadline {
                Text(verbatim: headline)
                    .noopFont(.sectionTitle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The calibration progress replaces the readiness line while the baseline forms — the same
            // swap Liquid and classic Today make (`calibrationDetail ?? synthLine`).
            Text(verbatim: chargeDisplay.calibrationDetail ?? dayModel.synthLine(repo: repo))
                .noopFont(.bodySmall)
                .fixedSize(horizontal: false, vertical: true)
            if case .calibrating(let nights) = chargeDisplay {
                CalibrationProgress(banked: nights, seed: Baselines.minNightsSeed)
                    .padding(.top, NoopTheme.Layout.xs)
            }
            if let why = chargeDisplay.calibrationReason(
                dayKeys: repo.days.map(\.day), nightlyHrv: repo.days.map(\.avgHrv),
                today: Repository.logicalDayKey(Date())) {
                Text(verbatim: why)
                    .noopFont(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = dayModel.effortZeroNote {
                Text(verbatim: note)
                    .noopFont(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let source = scoreSourceCaption {
                SyncedSourceCaption(base: source)
                    .padding(.top, NoopTheme.Layout.xs)
            }
        }
        .padding(.horizontal, NoopTheme.Layout.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryHeadline: String? {
        if case .calibrating = chargeDisplay { return String(localized: "Calibrating") }
        return dayModel.readinessWord(repo: repo)
    }

    /// "NOOP score · computed on iPhone" vs "<brand> import", derived only from the winning series source the
    /// shared loader already resolved for each score (a "-noop" source is NOOP-computed; anything else is an
    /// imported score). The input device ("from WHOOP") rides along from the existing provider label.
    private var scoreSourceCaption: String? {
        let metrics: [(key: String, name: String)] = [
            ("sleep_performance", String(localized: "Sleep")),
            ("recovery", String(localized: "Recovery")),
            ("strain", String(localized: "Strain")),
        ]
        let resolved = metrics.compactMap { m in
            dayModel.heroResolvedSourceByMetric[m.key].map { (name: m.name, source: $0) }
        }
        guard !resolved.isEmpty else { return nil }
        func kind(_ raw: String) -> String {
            raw.hasSuffix("-noop")
                ? String(localized: "computed on iPhone")
                : String(localized: "\(TodayView.provenanceDisplayLabel(rawSource: raw, deviceId: repo.deviceId)) import")
        }
        let kinds = resolved.map { kind($0.source) }
        if Set(kinds).count == 1 {
            if resolved.allSatisfy({ $0.source.hasSuffix("-noop") }) {
                let base = String(localized: "NOOP score · computed on iPhone")
                if let inputs = dayModel.heroSourceLabel { return "\(base) · \(inputs)" }
                return base
            }
            return kinds[0]
        }
        return zip(resolved, kinds).map { String(localized: "\($0.0.name): \($0.1)") }.joined(separator: " · ")
    }

    /// Match Liquid/classic Today's legacy WHOOP 5 R-R note for an unscored selected night.
    private var chargeLegacyRRGap: Bool {
        guard let day = displayDay, day.recovery == nil else { return false }
        return Whoop5RR.legacyUnscorableNight(
            strictWhoop5: dayModel.whoop5StrictRR, day: day.day,
            firstRecordedDay: dayModel.firstRecordedRRDay, firstScorableDay: dayModel.firstScorableRRDay,
            avgHrv: day.avgHrv, totalSleepMin: day.totalSleepMin)
    }

    // MARK: - Heart rate

    private var heartRateSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            NoopSectionHeader("Heart rate")
                .padding(.horizontal, -NoopTheme.Layout.gutter)
            NavigationLink(value: TabRoute.fullDayChart) {
                NoopGlassCard {
                    LiveHeartRateCard(values: dayModel.hrValues, bucketTs: dayModel.hrBucketTs,
                                      dayStart: Calendar.current.startOfDay(for: selectedLogicalDay),
                                      isToday: isToday, animate: ringsAnimate)
                }
            }
            .buttonStyle(.noopPress)
            .accessibilityHint("Opens the full-day heart rate timeline")
            .noopSkeleton(loading)
        }
    }

    // MARK: - Key metrics

    /// The user's key-metric selection, minus Recovery / Strain / Sleep: the rings card above already
    /// shows those three, and a second copy of a fact on one screen is noise (AGENTS.md).
    private var keyMetricRows: [KeyMetric] {
        KeyMetricPrefs.decodeEnabled(keyMetricsRaw).filter { ![.charge, .effort, .rest].contains($0) }
    }

    @ViewBuilder
    private var keyMetricsSection: some View {
        let rows = keyMetricRows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                NoopSectionHeader("Key metrics", linkTitle: "Edit") { customizationDestination = .keyMetrics }
                    .padding(.horizontal, -NoopTheme.Layout.gutter)
                NoopGlassCard(flush: true) {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element) { index, metric in
                            keyMetricRow(metric, first: index == 0)
                        }
                    }
                }
                .noopSkeleton(loading)
            }
        }
    }

    /// One row's resolved content. `value` is the SELECTED day's own reading; a reading carried from an
    /// earlier night never stands in for it. It moves to the sub-line, stamped with whose night it was.
    private struct MetricRowContent {
        var title: LocalizedStringKey
        var color: Color
        var subtitle: String?
        var value: String?
        var unit: String?
        var sparkKey: String?
        var route: TabRoute?
    }

    @ViewBuilder
    private func keyMetricRow(_ metric: KeyMetric, first: Bool) -> some View {
        let c = rowContent(metric)
        let spark = c.sparkKey.map { dayModel.windowedSpark($0, windowDays: keyMetricsWindowDays) } ?? []
        let row = NoopMetricRow(c.title, color: c.color, subtitle: c.subtitle, value: c.value, unit: c.unit,
                                showsDivider: !first) {
            if spark.count >= 2 {
                NoopLineChart(points: spark.enumerated().map { NoopChartPoint(x: Double($0.offset), y: $0.element) },
                              color: c.color, compact: true, animates: ringsAnimate)
            } else {
                Color.clear
            }
        }
        if let route = c.route {
            NavigationLink(value: route) { row.contentShape(Rectangle()) }
                .buttonStyle(.noopPress)
        } else {
            row
        }
    }

    private func rowContent(_ metric: KeyMetric) -> MetricRowContent {
        let carryDayKey = displayDay?.day ?? selectedDayKey
        func carried(_ value: String, from row: DailyMetric?) -> String? {
            guard let row else { return nil }
            let caption = TodayView.carriedCaption(priorDayKey: row.day, todayKey: carryDayKey)
            return String(localized: "Last: \(value) · \(caption)")
        }
        switch metric {
        case .hrv:
            let own = displayDay?.avgHrv
            let carry = own == nil ? dayModel.cachedHrvDay : nil
            return MetricRowContent(
                title: "HRV", color: NoopTheme.hrv,
                subtitle: carry?.avgHrv.flatMap { carried("\(Int($0.rounded())) ms", from: carry) },
                value: own.map { String(Int($0.rounded())) }, unit: "ms", sparkKey: "hrv", route: .metric("hrv"))
        case .restingHr:
            let own = displayDay?.restingHr
            let carry = own == nil ? dayModel.cachedRestingHrDay : nil
            return MetricRowContent(
                title: "Resting heart rate", color: NoopTheme.heart,
                subtitle: carry?.restingHr.flatMap { carried("\($0) bpm", from: carry) },
                value: own.map { String($0) }, unit: "bpm", sparkKey: "rhr", route: .metric("rhr"))
        case .respiratory:
            let own = displayDay?.respRateBpm
            let carry = own == nil ? (dayModel.cachedVitalsDay?.respRateBpm != nil
                                      ? dayModel.cachedVitalsDay : dayModel.cachedRespDay) : nil
            return MetricRowContent(
                title: "Respiratory rate", color: NoopTheme.breath,
                subtitle: carry?.respRateBpm.flatMap { carried(Self.oneDecimal($0) + " rpm", from: carry) },
                value: own.map(Self.oneDecimal), unit: "rpm", sparkKey: "resp_rate", route: .metric("resp_rate"))
        case .bloodOxygen:
            // WHOOP 4.0 does not measure blood oxygen offline: an honest empty row, never a number
            // (and never the unverified strap estimate).
            if activeIsWhoop4 {
                return MetricRowContent(title: "Blood oxygen", color: NoopTheme.textTertiary,
                                        subtitle: String(localized: "Not measured on WHOOP 4.0"),
                                        value: nil, unit: nil, sparkKey: nil, route: nil)
            }
            let own = displayDay?.spo2Pct
            let carry = own == nil ? dayModel.cachedVitalsDay : nil
            return MetricRowContent(
                title: "Blood oxygen", color: NoopTheme.hrv,
                subtitle: carry?.spo2Pct.flatMap { carried("\(Int($0.rounded()))%", from: carry) },
                value: own.map { String(Int($0.rounded())) }, unit: "%", sparkKey: "spo2", route: .metric("spo2"))
        case .skinTemp:
            // Always relative to the personal baseline (the deviation), never an absolute reading.
            let fahrenheit = temperatureUnit == .fahrenheit
            let own = displayDay?.skinTempDevC
            let carryRow = own == nil
                ? [dayModel.cachedVitalsDay, dayModel.cachedSkinTempReadingDay].compactMap { $0 }
                    .first { $0.skinTempDevC != nil }
                : nil
            let format = { (v: Double) in
                SkinTempDisplay.formatReading(SkinTempDisplay.Reading(value: v, kind: .deviation),
                                              fahrenheit: fahrenheit)
            }
            return MetricRowContent(
                title: "Skin temperature", color: NoopTheme.temp,
                subtitle: carryRow?.skinTempDevC.flatMap { carried(format($0), from: carryRow) }
                    ?? String(localized: "Relative to baseline"),
                value: own.map(format), unit: nil, sparkKey: "skin_temp", route: .metric("skin_temp"))
        case .steps:
            let detail = dayModel.stepsDetailMetric
            let measured = displayDay?.steps != nil
            let imported = !measured && dayModel.importedStepsDay != nil
            let subtitle: String = measured ? String(localized: "Strap")
                : imported ? "Apple Health" : String(localized: "Estimated from strap")
            let value = dayModel.stepCount.map { count -> String in
                let text = count.formatted(.number.precision(.fractionLength(0)).locale(AppLanguage.activeLocale))
                return (measured || imported) ? text : "~" + text
            }
            let key = detail?.key ?? "steps_est"
            return MetricRowContent(
                title: "Steps", color: NoopTheme.lift, subtitle: subtitle, value: value, unit: nil,
                sparkKey: key,
                route: .metricSourced(key: key, source: detail?.source ?? Repository.whoopSource))
        case .weight:
            let kg = dayModel.weightKg
            return MetricRowContent(
                title: "Weight", color: NoopTheme.temp,
                subtitle: kg == nil ? String(localized: "from profile") : String(localized: "latest"),
                value: UnitFormatter.massFromKilograms(kg ?? profile.weightKg, system: unitSystem), unit: nil,
                sparkKey: "weight", route: .metric("weight"))
        case .calories:
            let detail = dayModel.caloriesDetailMetric
            let key = detail?.key ?? "energy_kcal"
            return MetricRowContent(
                title: "Calories", color: NoopTheme.temp, subtitle: nil,
                value: dayModel.caloriesCount.map { String(Int($0.rounded())) }, unit: "kcal",
                sparkKey: "energy_kcal",
                route: .metricSourced(key: key, source: detail?.source ?? Repository.whoopSource))
        case .charge, .effort, .rest:
            // Filtered out above (the rings card shows them); kept exhaustive for the compiler.
            return MetricRowContent(title: "", color: NoopTheme.textTertiary, value: nil)
        }
    }

    // MARK: - Activity

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            NoopSectionHeader("Activity")
                .padding(.horizontal, -NoopTheme.Layout.gutter)
            NoopGlassCard(flush: true) {
                if dayModel.workouts.isEmpty {
                    Text("No workouts yet")
                        .noopFont(.bodySmall)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, NoopTheme.Layout.rowVerticalPadding)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(dayModel.workouts.enumerated()), id: \.offset) { index, workout in
                            NavigationLink(value: TabRoute.workouts) {
                                workoutRow(workout, first: index == 0)
                            }
                            .buttonStyle(.noopPress)
                        }
                    }
                }
            }
            .noopSkeleton(loading)
        }
    }

    private func workoutRow(_ w: WorkoutRow, first: Bool) -> some View {
        VStack(spacing: 0) {
            if !first {
                Rectangle().fill(NoopTheme.separator).frame(height: Self.hairline)
            }
            HStack(spacing: NoopTheme.Layout.m) {
                DomainIcon(systemImage: WorkoutTypeIconography.systemSymbolName(for: w.sport),
                           color: WorkoutSource.classify(w.source) == .lifting ? NoopTheme.lift : NoopTheme.strain)
                VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
                    Text(verbatim: WorkoutSource.displaySport(w.sport))
                        .noopFont(.listTitle)
                    Text(verbatim: workoutSubtitle(w))
                        .noopFont(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let strain = w.strain {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(verbatim: UnitFormatter.effortDisplay(strain, scale: effortScale))
                            .noopFont(.rowNumber, color: false)
                            .foregroundStyle(NoopTheme.strain)
                        Text("Strain").noopFont(.caption)
                    }
                }
            }
            .padding(.vertical, NoopTheme.Layout.rowVerticalPadding)
        }
        .accessibilityElement(children: .combine)
    }

    /// "6:40 PM · 52 min · Apple Health · Summary only". The source names where the row came from, and
    /// summary vs full-set detail is said outright so a Health summary never reads as a full lift log.
    private func workoutSubtitle(_ w: WorkoutRow) -> String {
        var parts: [String] = []
        parts.append(Date(timeIntervalSince1970: TimeInterval(w.startTs))
            .formatted(.dateTime.hour().minute().locale(AppLanguage.activeLocale)))
        let secs = w.durationS ?? Double(max(w.endTs - w.startTs, 0))
        if secs > 0 { parts.append("\(Int(secs / 60)) \(String(localized: "min"))") }
        if let dm = w.distanceM, dm > 0 {
            parts.append(UnitFormatter.distanceFromMeters(dm, system: distanceUnitSystem))
        }
        switch WorkoutSource.classify(w.source) {
        case .apple: parts.append("Apple Health"); parts.append(String(localized: "Summary only"))
        case .lifting: parts.append(String(localized: "Lifting")); parts.append(String(localized: "Full sets"))
        case .whoop: parts.append(String(localized: "Whoop"))
        case .manual: parts.append(String(localized: "Manual"))
        case .detected: parts.append(String(localized: "Detected"))
        case .activityFile: parts.append(String(localized: "File"))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Hosted cards

    @ViewBuilder
    private var hostedCardsSection: some View {
        let cards = HostedCardPrefs.decodeEnabled(hostedCardsRaw)
        if !cards.isEmpty {
            VStack(spacing: NoopTheme.Layout.cardGap) {
                ForEach(cards) { card in
                    let view = TodayHostedCardView(
                        card: card, days: repo.days, effortScale: effortScale,
                        sleepModel: dayModel.hostedSleepModel, stressHours: dayModel.hostedStressHours,
                        stressActivityMaskedHours: dayModel.hostedStressActivityMaskedHours)
                    if let route = card.route {
                        NavigationLink(value: route) { view }.buttonStyle(.plain)
                    } else {
                        view
                    }
                }
            }
        }
    }

    private var customizeButton: some View {
        Button { customizationDestination = .today } label: {
            Label("Customize Today", systemImage: "slider.horizontal.3")
        }
        .buttonStyle(NoopSecondaryButton())
        .padding(.top, NoopTheme.Layout.l)
    }

    // MARK: - Ambient

    private var ambientScores: TodayScores {
        TodayScores(sleep: dayModel.restScore,
                    recovery: chargeDisplay.pct,
                    strain: strainStored.map { UnitFormatter.effortValue($0, scale: .whoop) })
    }

    // MARK: - Loading

    private func load() async {
        await dayModel.load(repo: repo, profile: profile, inputs: TodayLoadInputs(
            hydrationEnabled: { hydrationEnabled },
            dayCycleMode: { DayCycleMode.persisted(dayCycleModeRaw) },
            hostedCardsRaw: { hostedCardsRaw }))
    }

    /// Pull to refresh: Liquid Today's pull, on the native control. A strap history offload is requested
    /// only when the client's own precondition holds (#1748); `syncNow()` is internally gated as well.
    private func pullToRefresh() async {
        if ble.state.historyReady { ble.syncNow() }
        await repo.refresh()
        await load()
    }

    /// Registry evidence for the active strap's family, through the canonical resolver. Unknown stays
    /// false, so the Blood Oxygen row only says "not measured" for a positively identified 4.0.
    private func resolveActiveFamily() async {
        guard let store = await repo.storeHandle() else { activeIsWhoop4 = false; return }
        let device = (try? DeviceRegistryStore(dbQueue: store.registryWriter).all())?
            .first(where: { $0.id == repo.deviceId })
        activeIsWhoop4 = DeviceFamily.confirmedRegistryFamily(model: device?.model, brand: device?.brand) == .whoop4
    }

    // MARK: - Formatting

    private static let dash = "—"

    private static func oneDecimal(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(1)).locale(AppLanguage.activeLocale))
    }
}

// MARK: - Calibration progress (E2)

/// One segment per night the baseline needs (`Baselines.minNightsSeed`, the real seed), filled for each
/// night already banked.
private struct CalibrationProgress: View {
    let banked: Int
    let seed: Int

    var body: some View {
        HStack(spacing: NoopTheme.Layout.xs) {
            ForEach(0..<max(seed, 1), id: \.self) { i in
                Capsule()
                    .fill(i < banked ? NoopTheme.sleep : NoopTheme.track)
                    .frame(height: Self.height)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Calibrating"))
        .accessibilityValue(Text(verbatim: Self.fraction(min(banked, seed), seed)))
    }

    /// "2/4": a numeric fraction, not copy.
    private static func fraction(_ n: Int, _ d: Int) -> String { [String(n), String(d)].joined(separator: "/") }

    private static let height: CGFloat = 6
}

// MARK: - LiveState leaves (only these re-render on the ~1 Hz strap updates)

/// The provenance caption plus when the strap last synced, read from LiveState in this leaf only.
private struct SyncedSourceCaption: View {
    let base: String
    @EnvironmentObject private var live: LiveState

    var body: some View {
        if let ts = live.lastSyncedAt {
            SourceCaption(verbatim: "\(base) · \(String(localized: "Synced \(relativeAgo(ts))"))")
        } else {
            SourceCaption(verbatim: base)
        }
    }
}

/// E1: the strap is the active device and is not connected. Reconnect opens Devices, the existing way the
/// app reconnects or re-pairs a strap; nothing here touches the BLE path. Held back for a short grace so a
/// launch-time connect does not flash the banner.
private struct StrapAwayBanner: View {
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var router: NavRouter
    @State private var graceElapsed = false

    private var away: Bool { live.activeIsWhoop && !live.connected }

    var body: some View {
        Group {
            if away && graceElapsed {
                HStack(alignment: .top, spacing: NoopTheme.Layout.m) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .noopFont(.sectionTitle, color: false)
                        .foregroundStyle(NoopTheme.recoveryMid)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
                        Text("Strap not connected").noopFont(.listTitle)
                        Group {
                            if let ts = live.lastSyncedAt {
                                Text(verbatim: String(localized: "Synced \(relativeAgo(ts))") + ". "
                                     + String(localized: "History on the strap syncs when it's back."))
                            } else {
                                Text("History on the strap syncs when it's back.")
                            }
                        }
                        .noopFont(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button { router.openDevices() } label: {
                        Text("Reconnect")
                            .noopFont(.pill, color: false)
                            .foregroundStyle(NoopTheme.recoveryMid)
                            .padding(.horizontal, NoopTheme.Layout.m)
                            .frame(minHeight: NoopTheme.Layout.minTouchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.noopPress)
                }
                .padding(.horizontal, NoopTheme.Layout.l)
                .padding(.vertical, NoopTheme.Layout.rowVerticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: NoopTheme.Layout.cardRadius, style: .continuous)
                        .fill(NoopTheme.recoveryMid.opacity(Self.fillOpacity))
                        .overlay(
                            RoundedRectangle(cornerRadius: NoopTheme.Layout.cardRadius, style: .continuous)
                                .strokeBorder(NoopTheme.recoveryMid.opacity(Self.strokeOpacity), lineWidth: 1)
                        )
                )
                .transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: Self.graceNanoseconds)
            graceElapsed = true
        }
    }

    private static let fillOpacity: Double = 0.10
    private static let strokeOpacity: Double = 0.22
    private static let graceNanoseconds: UInt64 = 4_000_000_000
}

/// The header's strap battery pill: the strap's charge under an active strap, a ring's own charge under an
/// active ring, resolved by Liquid Today's `StrapBatteryDisplay` truth table (#2208). Tap → Devices.
private struct StrapBatteryPill: View {
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var router: NavRouter

    private var display: LiquidTodayView.StrapBatteryDisplay {
        .resolve(activeIsWhoop: live.activeIsWhoop, connected: live.connected,
                 batteryPct: live.batteryPct, charging: live.charging,
                 ringPct: live.ouraBatteryPct, ringCharging: live.ouraWearState == .charging)
    }

    var body: some View {
        if case .notActiveDevice = display {
            EmptyView()
        } else {
            Button { router.openDevices() } label: { pill }
                .buttonStyle(.noopPress)
                .accessibilityLabel(accessibility)
        }
    }

    @ViewBuilder
    private var pill: some View {
        let syncing = live.backfilling
        switch display {
        case .charge(let pct, let charging, _):
            NoopPill(verbatim: "\(Int(pct.rounded()))%",
                     systemImage: syncing ? "arrow.triangle.2.circlepath" : (charging ? "bolt.fill" : nil),
                     dot: NoopTheme.recoveryColor(for: pct))
        case .pending(let charging):
            NoopPill(verbatim: "—", systemImage: syncing ? "arrow.triangle.2.circlepath" : (charging ? "bolt.fill" : nil),
                     dot: NoopTheme.textTertiary)
        case .offline:
            // E1: no live charge to show; say how long since the strap last synced instead.
            if let ts = live.lastSyncedAt {
                NoopPill(verbatim: relativeAgo(ts), dot: NoopTheme.recoveryMid, tint: NoopTheme.recoveryMid)
            } else {
                NoopPill(verbatim: "—", systemImage: "bolt.slash", tint: NoopTheme.textSecondary)
            }
        case .notActiveDevice:
            EmptyView()
        }
    }

    /// The same catalogue entries Liquid Today's battery control speaks.
    private var accessibility: String {
        if live.backfilling { return String(localized: "Syncing strap history") }
        switch display {
        case .notActiveDevice: return ""
        case .offline: return String(localized: "Strap battery, strap not connected")
        case .pending(let charging):
            return charging ? String(localized: "Strap battery charging, no reading yet")
                            : String(localized: "Strap battery, no reading yet")
        case .charge(let percent, let charging, let isRing):
            let n = Int(percent.rounded())
            if isRing {
                return charging ? String(localized: "Ring battery \(n) percent, charging")
                                : String(localized: "Ring battery \(n) percent")
            }
            return charging ? String(localized: "Strap battery \(n) percent, charging")
                            : String(localized: "Strap battery \(n) percent")
        }
    }
}

/// The heart-rate card body: the LIVE value (only while the strap streams; never a banked average drawn
/// as live) with a heart pulsing at the measured BPM, the day's range and its bars.
private struct LiveHeartRateCard: View {
    let values: [Double]
    let bucketTs: [Int]
    let dayStart: Date
    let isToday: Bool
    let animate: Bool

    @EnvironmentObject private var live: LiveState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var beat = false

    private var liveBpm: Int? {
        guard isToday, live.connected, let hr = live.heartRate, hr > 0 else { return nil }
        return hr
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopTheme.Layout.m) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: NoopTheme.Layout.xs) {
                    HStack(spacing: NoopTheme.Layout.s) {
                        Image(systemName: "heart.fill")
                            .scaleEffect(beat ? Self.beatScale : 1)
                            .accessibilityHidden(true)
                        Text("Now").noopFont(.footnote, color: false)
                    }
                    .foregroundStyle(NoopTheme.heart)
                    HStack(alignment: .firstTextBaseline, spacing: NoopTheme.Layout.xs) {
                        Text(verbatim: liveBpm.map(String.init) ?? "—")
                            .noopFont(.bigNumber, color: false)
                            .foregroundStyle(liveBpm == nil ? NoopTheme.textTertiary : NoopTheme.textPrimary)
                            .contentTransition(.numericText())
                        Text("BPM").noopFont(.unit)
                    }
                    if liveBpm == nil && isToday {
                        Group {
                            if live.connected { Text("Waiting for the strap") } else { Text("Strap not connected") }
                        }
                        .noopFont(.caption)
                    }
                }
                Spacer(minLength: NoopTheme.Layout.m)
                if let lo = values.min(), let hi = values.max() {
                    VStack(alignment: .trailing, spacing: NoopTheme.Layout.xs) {
                        Text("Range").noopFont(.footnote)
                        Text(verbatim: Self.rangeText(lo, hi))
                            .noopFont(.rowTitle)
                            .monospacedDigit()
                    }
                }
            }
            if bars.values.contains(where: { $0 != nil }) {
                NoopBarChart(values: bars.values, color: NoopTheme.heart, xLabels: bars.labels, animates: animate,
                             accessibilityLabel: Text("Heart rate"))
                    .frame(height: Self.barsHeight)
                if isToday {
                    Text("5-minute average · since midnight").noopFont(.caption)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .task(id: NoopTheme.Motion.heartbeatInterval(bpm: liveBpm, reduceMotion: reduceMotion)) {
            guard let interval = NoopTheme.Motion.heartbeatInterval(bpm: liveBpm, reduceMotion: reduceMotion) else {
                beat = false
                return
            }
            while !Task.isCancelled {
                withAnimation(.easeOut(duration: interval * Self.beatRiseShare)) { beat = true }
                try? await Task.sleep(nanoseconds: UInt64(interval * Self.beatRiseShare * 1_000_000_000))
                withAnimation(.easeIn(duration: interval * (1 - Self.beatRiseShare))) { beat = false }
                try? await Task.sleep(nanoseconds: UInt64(interval * (1 - Self.beatRiseShare) * 1_000_000_000))
            }
        }
    }

    private var bars: (values: [Double?], labels: [String]) {
        Self.halfHourBars(values: values, bucketTs: bucketTs, dayStart: dayStart,
                          end: isToday ? Date() : dayStart.addingTimeInterval(Self.daySeconds))
    }

    /// Display-only binning of the day's banked 5-minute means into half-hour bars (a slot with no bucket
    /// stays nil, so a gap reads as a gap). Captions sit under the slots that start on a six-hour mark.
    static func halfHourBars(values: [Double], bucketTs: [Int], dayStart: Date, end: Date)
        -> (values: [Double?], labels: [String]) {
        guard values.count == bucketTs.count, let firstTs = bucketTs.first else { return ([], []) }
        let slot = Self.slotSeconds
        let startTs = (min(firstTs, Int(dayStart.timeIntervalSince1970)) / slot) * slot
        let endTs = max(Int(end.timeIntervalSince1970), (bucketTs.last ?? firstTs) + 1)
        let count = max(1, Int(ceil(Double(endTs - startTs) / Double(slot))))
        var sums = [Double](repeating: 0, count: count)
        var counts = [Int](repeating: 0, count: count)
        for (v, ts) in zip(values, bucketTs) {
            let i = (ts - startTs) / slot
            guard i >= 0, i < count else { continue }
            sums[i] += v
            counts[i] += 1
        }
        let binned: [Double?] = (0..<count).map { counts[$0] > 0 ? sums[$0] / Double(counts[$0]) : nil }
        let cal = Calendar.current
        let labels: [String] = (0..<count).map { i in
            let date = Date(timeIntervalSince1970: TimeInterval(startTs + i * slot))
            let c = cal.dateComponents([.hour, .minute], from: date)
            guard c.minute == 0, let h = c.hour, h % 6 == 0 else { return "" }
            return date.formatted(.dateTime.hour().locale(AppLanguage.activeLocale))
        }
        return (binned, labels)
    }

    /// "48–142": a numeric range, not copy.
    private static func rangeText(_ lo: Double, _ hi: Double) -> String {
        [String(Int(lo.rounded())), String(Int(hi.rounded()))].joined(separator: "–")
    }

    private static let slotSeconds = 1800
    private static let daySeconds: TimeInterval = 86_400
    private static let barsHeight: CGFloat = 84
    private static let beatScale: CGFloat = 1.22
    private static let beatRiseShare = 0.35
}
